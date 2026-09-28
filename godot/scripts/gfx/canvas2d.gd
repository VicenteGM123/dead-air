# DACanvas: HTML Canvas 2D emulation for the DEAD AIR port (SPEC §6). Canvas drawing code of the JS game is ported
# line by line with the SAME names:
#   var cv := DACanvas.new(512, 384)            # document.createElement('canvas') + width/height
#   var ctx = cv.getContext("2d")               # CanvasRenderingContext2D (properties + methods, JS names)
#   ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(64, 64, 20, 0, TAU); ctx.fill()
#   mat.albedo_texture = cv.texture             # Texture2D, valid at once; content after the canvas renders
# Coverage: fillStyle/strokeStyle (CSS colour strings: #rgb[a] #rrggbb[aa] rgb() rgba() hsl() hsla() names,
# transparent; CanvasGradient from createLinearGradient/createRadialGradient/createConicGradient; CanvasPattern from
# createPattern), globalAlpha, lineWidth, lineCap, lineJoin, miterLimit, setLineDash/getLineDash/lineDashOffset,
# font (CSS shorthand), textAlign, textBaseline, direction, letterSpacing, globalCompositeOperation (all 26 modes),
# shadowBlur/shadowColor/shadowOffsetX/Y, filter (blur brightness contrast saturate grayscale sepia invert opacity
# hue-rotate), imageSmoothingEnabled; beginPath closePath moveTo lineTo arc arcTo ellipse quadraticCurveTo
# bezierCurveTo rect roundRect fill([path][, rule]) stroke([path]) clip([path][, rule]) isPointInPath fillRect
# strokeRect clearRect fillText strokeText measureText save restore reset translate rotate scale transform
# setTransform resetTransform getTransform drawImage (3/5/9 args; DACanvas, Texture2D or Image) createImageData
# getImageData putImageData. Path2D = DAPath2D (canvas_path.gd).
#
# Canvas object: width/height (setting them clears the canvas and resets the context, like JS), texture,
# toImage() (synchronous pixels), userData (JS expando fields: `canvas.ctx = …` -> `cv.userData.ctx = …`).
# Hints (port-only, no JS equivalent): opaque (content is opaque: skips the straight-alpha fixup pass),
# bakeMode "auto" (default: once the content stays unchanged for a frame it is read back into a mipmapped
# ImageTexture and the GPU target is freed) | "now" (bake right after the first render: static cards) | "never"
# (animated content redrawn every frame), mipmaps (baked texture mipmaps, default true).
#
# Animated content: just redraw — clearRect(0,0,w,h) (or any op covering the whole canvas) + the drawing code, every
# frame you want a new image; the texture keeps its identity. JS `texture.needsUpdate = true` is not needed.
# getContext("2d", {"willReadFrequently": true}) gives a CPU (software rasterised) canvas: exact synchronous
# getImageData every frame (Telly's dot-matrix mask); other canvases render on the GPU (Godot 2D renderer,
# canvas_gpu.gd) and getImageData/toImage on them forces a synchronous render (slow: avoid per frame).
#
# ImageData = Dictionary {width, height, data: PackedByteArray RGBA (straight)}. PackedByteArray is a VALUE type in
# GDScript: `var d: PackedByteArray = img.data; …modify d…; img.data = d` before putImageData (or write
# img.data[i] = v directly on the dictionary).
# Renames (SPEC §3.2): none on the public API. Approximations: see canvas_gpu.gd header and the port report.
class_name DACanvas
extends RefCounted

const TAU_ := PI * 2.0

var _w := 300
var _h := 150
var width: int:
	get:
		return _w
	set(v):
		_resize(v, _h)
var height: int:
	get:
		return _h
	set(v):
		_resize(_w, v)

var opaque := false
var bakeMode := "auto"
var mipmaps := true
var userData := {}

var _cpu := false            # software canvas
var _px := PackedFloat32Array()   # CPU pixels, premultiplied RGBA float
var _cpuTex: ImageTexture = null
var _cpuDirty := false

var _ver = null              # DACanvasGPU.RT: latest content version
var _baked: ImageTexture = null
var _hasContent := false
var _proxy := RID()
var _proxyTarget := RID()
var _texRef: WeakRef = null
var _state = null            # Context2D state holder (shared by every context facade)
var _ctxRef: WeakRef = null

var texture: Texture2D:
	get:
		return _texture()

func _init(w: int = 300, h: int = 150) -> void:
	_w = maxi(0, w)
	_h = maxi(0, h)
	_state = CtxState.new()

func getContext(type: String = "2d", attrs = null) -> Context2D:
	if type != "2d":
		return null
	if attrs is Dictionary and attrs.get("willReadFrequently", false) and not _hasContent and not _cpu:
		_cpu = true
		_px = PackedFloat32Array()
		_px.resize(_w * _h * 4)
	var c: Context2D = _ctxRef.get_ref() if _ctxRef != null else null
	if c == null:
		c = Context2D.new(self)
		_ctxRef = weakref(c)
	return c

func _resize(w: int, h: int) -> void:
	w = maxi(0, w)
	h = maxi(0, h)
	_w = w
	_h = h
	_state.reset()
	if _ver != null:
		DACanvasGPU.retire(_ver)
		_ver = null
	_baked = null
	_hasContent = false
	if _cpu:
		_px = PackedFloat32Array()
		_px.resize(_w * _h * 4)
		_cpuDirty = true
	if _proxy.is_valid():
		DACanvasGPU.markDirty(self)
	var t: CanvasTex = _texRef.get_ref() if _texRef != null else null
	if t != null:
		t.w = _w
		t.h = _h
		t.emit_changed()

# ------------------------------------------------------------------------------------------------ texture
class CanvasTex:
	extends Texture2D
	var canvas: DACanvas
	var rid: RID
	var w := 1
	var h := 1
	func _get_rid() -> RID:
		return rid
	func _get_width() -> int:
		return w
	func _get_height() -> int:
		return h
	func _has_alpha() -> bool:
		return true

func _texture() -> Texture2D:
	var t: CanvasTex = _texRef.get_ref() if _texRef != null else null
	if t != null:
		return t
	if not _proxy.is_valid():
		var base := _currentTexRid()
		_proxy = RenderingServer.texture_proxy_create(base)
		_proxyTarget = base
		DACanvasGPU.trackProxy(self, _proxy)
	t = CanvasTex.new()
	t.canvas = self
	t.rid = _proxy
	t.w = maxi(1, _w)
	t.h = maxi(1, _h)
	_texRef = weakref(t)
	return t

func _currentTexRid() -> RID:
	if _cpu:
		return _cpuTexture().get_rid()
	if _ver != null:
		return _ver.tex
	if _baked != null:
		return _baked.get_rid()
	return DACanvasGPU.blank(_w, _h).get_rid()

func _updateProxy() -> void:
	if not _proxy.is_valid():
		return
	var r := _currentTexRid()
	if r != _proxyTarget:
		RenderingServer.texture_proxy_update(_proxy, r)
		_proxyTarget = r

func _cpuTexture() -> ImageTexture:
	var img := _cpuImage()
	if _cpuTex == null or _cpuTex.get_width() != img.get_width() or _cpuTex.get_height() != img.get_height():
		_cpuTex = ImageTexture.create_from_image(img)
	elif _cpuDirty:
		_cpuTex.update(img)
	_cpuDirty = false
	return _cpuTex

# Called by DACanvasGPU at frame_post_draw; returns true when the canvas no longer needs watching.
func _bakeStep(frame: int) -> bool:
	if _cpu:
		return true
	if _ver == null:
		return true
	if _ver.state != 3:
		return false
	if bakeMode == "never":
		return true
	if bakeMode == "auto" and _ver.frameRendered >= frame:
		return false
	_bake()
	return true

func _bake() -> void:
	var img := RenderingServer.texture_2d_get(_ver.tex)
	if img == null:
		return
	if mipmaps:
		img.generate_mipmaps()
	if _baked != null and _baked.get_width() == img.get_width() and _baked.get_height() == img.get_height() and _baked.has_meta("mips") and _baked.get_meta("mips") == mipmaps:
		_baked.update(img)
	else:
		_baked = ImageTexture.create_from_image(img)
		_baked.set_meta("mips", mipmaps)
	var old = _ver
	_ver = null
	_updateProxy()
	DACanvasGPU.release(old)
	DACanvasGPU.stats.baked += 1

func _needsFixup(rt) -> bool:
	return not opaque and rt.hasContent

# Recording RT for new drawing. fullClear = the op replaces the whole canvas content.
func _target(fullClear: bool):
	var v = _ver
	if v != null and v.state == 1 and not v.sealed:
		if fullClear:
			DACanvasGPU.resetRT(v)
		return v
	var rt = null
	var needBlit := not fullClear and _hasContent
	if v != null and not needBlit and v.readFrame != DACanvasGPU.frame and v.state != 2:
		# nobody sampled the old content this frame: record the new version in the same viewport
		DACanvasGPU.resetRT(v)
		rt = v
	else:
		rt = DACanvasGPU.newRT(_w, _h, DACanvasGPU.MSAA, false)
		rt.owner = weakref(self)
		DACanvasGPU.trackVersion(rt)
		if needBlit:
			if v != null:
				DACanvasGPU.addDep(rt, v)
				DACanvasGPU.addCopy(rt, Rect2(0, 0, _w, _h), v.tex, Rect2(0, 0, _w, _h), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
			elif _baked != null:
				rt.keep.append(_baked)
				DACanvasGPU.addCopy(rt, Rect2(0, 0, _w, _h), _baked.get_rid(), Rect2(0, 0, _w, _h), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
		if v != null:
			DACanvasGPU.retire(v)
	_ver = rt
	_hasContent = true
	DACanvasGPU.markDirty(self)
	return rt

# Texture of the current content for sampling by another canvas (drawImage / createPattern).
# Returns [texRid, premultiplied, depRT, keepAlive, w, h].
func _source(reader) -> Array:
	if _cpu:
		var t := ImageTexture.create_from_image(_cpuImage())
		return [t.get_rid(), false, null, t, _w, _h]
	if _ver != null:
		if reader != null:
			DACanvasGPU.addDep(reader, _ver)
		else:
			_ver.readFrame = DACanvasGPU.frame
			if _ver.state == 1:
				_ver.sealed = true
		return [_ver.tex, false, _ver, self, _w, _h]
	if _baked != null:
		return [_baked.get_rid(), false, null, _baked, _w, _h]
	return [DACanvasGPU.blank(_w, _h).get_rid(), false, null, null, _w, _h]

# Synchronous pixels (straight RGBA8). Forces a render of pending GPU content.
func toImage() -> Image:
	if _w <= 0 or _h <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	if _cpu:
		return _cpuImage()
	if _ver != null:
		if _ver.state != 3:
			DACanvasGPU.drawNow()
		if _ver != null and _ver.state == 3:
			var img := RenderingServer.texture_2d_get(_ver.tex)
			if img != null:
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)
				return img
	if _baked != null:
		var im2 := _baked.get_image()
		if im2.has_mipmaps():
			im2.clear_mipmaps()
		if im2.get_format() != Image.FORMAT_RGBA8:
			im2.convert(Image.FORMAT_RGBA8)
		return im2
	return Image.create(_w, _h, false, Image.FORMAT_RGBA8)

func _cpuImage() -> Image:
	var n := _w * _h
	var b := PackedByteArray()
	b.resize(n * 4)
	for i in n:
		var o := i * 4
		var a := _px[o + 3]
		if a > 0.0:
			b[o] = clampi(int(_px[o] / a * 255.0 + 0.5), 0, 255)
			b[o + 1] = clampi(int(_px[o + 1] / a * 255.0 + 0.5), 0, 255)
			b[o + 2] = clampi(int(_px[o + 2] / a * 255.0 + 0.5), 0, 255)
			b[o + 3] = clampi(int(a * 255.0 + 0.5), 0, 255)
	if n == 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	return Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, b)

# Forces the baked (mipmapped) texture as soon as possible (static content).
func markStatic() -> void:
	bakeMode = "now"
	if _ver != null:
		DACanvasGPU.watch(self)

# ================================================================================================ colours
static var _colorCache := {}
const NAMED := {
	"aliceblue": 0xf0f8ff, "antiquewhite": 0xfaebd7, "aqua": 0x00ffff, "aquamarine": 0x7fffd4, "azure": 0xf0ffff,
	"beige": 0xf5f5dc, "bisque": 0xffe4c4, "black": 0x000000, "blanchedalmond": 0xffebcd, "blue": 0x0000ff,
	"blueviolet": 0x8a2be2, "brown": 0xa52a2a, "burlywood": 0xdeb887, "cadetblue": 0x5f9ea0, "chartreuse": 0x7fff00,
	"chocolate": 0xd2691e, "coral": 0xff7f50, "cornflowerblue": 0x6495ed, "cornsilk": 0xfff8dc, "crimson": 0xdc143c,
	"cyan": 0x00ffff, "darkblue": 0x00008b, "darkcyan": 0x008b8b, "darkgoldenrod": 0xb8860b, "darkgray": 0xa9a9a9,
	"darkgreen": 0x006400, "darkgrey": 0xa9a9a9, "darkkhaki": 0xbdb76b, "darkmagenta": 0x8b008b,
	"darkolivegreen": 0x556b2f, "darkorange": 0xff8c00, "darkorchid": 0x9932cc, "darkred": 0x8b0000,
	"darksalmon": 0xe9967a, "darkseagreen": 0x8fbc8f, "darkslateblue": 0x483d8b, "darkslategray": 0x2f4f4f,
	"darkslategrey": 0x2f4f4f, "darkturquoise": 0x00ced1, "darkviolet": 0x9400d3, "deeppink": 0xff1493,
	"deepskyblue": 0x00bfff, "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1e90ff, "firebrick": 0xb22222,
	"floralwhite": 0xfffaf0, "forestgreen": 0x228b22, "fuchsia": 0xff00ff, "gainsboro": 0xdcdcdc,
	"ghostwhite": 0xf8f8ff, "gold": 0xffd700, "goldenrod": 0xdaa520, "gray": 0x808080, "green": 0x008000,
	"greenyellow": 0xadff2f, "grey": 0x808080, "honeydew": 0xf0fff0, "hotpink": 0xff69b4, "indianred": 0xcd5c5c,
	"indigo": 0x4b0082, "ivory": 0xfffff0, "khaki": 0xf0e68c, "lavender": 0xe6e6fa, "lavenderblush": 0xfff0f5,
	"lawngreen": 0x7cfc00, "lemonchiffon": 0xfffacd, "lightblue": 0xadd8e6, "lightcoral": 0xf08080,
	"lightcyan": 0xe0ffff, "lightgoldenrodyellow": 0xfafad2, "lightgray": 0xd3d3d3, "lightgreen": 0x90ee90,
	"lightgrey": 0xd3d3d3, "lightpink": 0xffb6c1, "lightsalmon": 0xffa07a, "lightseagreen": 0x20b2aa,
	"lightskyblue": 0x87cefa, "lightslategray": 0x778899, "lightslategrey": 0x778899, "lightsteelblue": 0xb0c4de,
	"lightyellow": 0xffffe0, "lime": 0x00ff00, "limegreen": 0x32cd32, "linen": 0xfaf0e6, "magenta": 0xff00ff,
	"maroon": 0x800000, "mediumaquamarine": 0x66cdaa, "mediumblue": 0x0000cd, "mediumorchid": 0xba55d3,
	"mediumpurple": 0x9370db, "mediumseagreen": 0x3cb371, "mediumslateblue": 0x7b68ee, "mediumspringgreen": 0x00fa9a,
	"mediumturquoise": 0x48d1cc, "mediumvioletred": 0xc71585, "midnightblue": 0x191970, "mintcream": 0xf5fffa,
	"mistyrose": 0xffe4e1, "moccasin": 0xffe4b5, "navajowhite": 0xffdead, "navy": 0x000080, "oldlace": 0xfdf5e6,
	"olive": 0x808000, "olivedrab": 0x6b8e23, "orange": 0xffa500, "orangered": 0xff4500, "orchid": 0xda70d6,
	"palegoldenrod": 0xeee8aa, "palegreen": 0x98fb98, "paleturquoise": 0xafeeee, "palevioletred": 0xdb7093,
	"papayawhip": 0xffefd5, "peachpuff": 0xffdab9, "peru": 0xcd853f, "pink": 0xffc0cb, "plum": 0xdda0dd,
	"powderblue": 0xb0e0e6, "purple": 0x800080, "rebeccapurple": 0x663399, "red": 0xff0000, "rosybrown": 0xbc8f8f,
	"royalblue": 0x4169e1, "saddlebrown": 0x8b4513, "salmon": 0xfa8072, "sandybrown": 0xf4a460, "seagreen": 0x2e8b57,
	"seashell": 0xfff5ee, "sienna": 0xa0522d, "silver": 0xc0c0c0, "skyblue": 0x87ceeb, "slateblue": 0x6a5acd,
	"slategray": 0x708090, "slategrey": 0x708090, "snow": 0xfffafa, "springgreen": 0x00ff7f, "steelblue": 0x4682b4,
	"tan": 0xd2b48c, "teal": 0x008080, "thistle": 0xd8bfd8, "tomato": 0xff6347, "turquoise": 0x40e0d0,
	"violet": 0xee82ee, "wheat": 0xf5deb3, "white": 0xffffff, "whitesmoke": 0xf5f5f5, "yellow": 0xffff00,
	"yellowgreen": 0x9acd32,
}

# CSS colour -> Color (straight alpha, sRGB values) or null when invalid (the assignment is then ignored, as in JS).
static func parseColor(v) -> Variant:
	if v is Color:
		return v
	if v is int:
		return Color.hex((v << 8) | 0xFF)
	if not (v is String or v is StringName):
		return null
	var s := String(v)
	var hit = _colorCache.get(s)
	if hit != null:
		return hit
	var c = _parseColor(s.strip_edges().to_lower())
	if c != null:
		if _colorCache.size() > 8192:
			_colorCache.clear()
		_colorCache[s] = c
	return c

static func _parseColor(s: String) -> Variant:
	if s.begins_with("#"):
		var h := s.substr(1)
		if not h.is_valid_hex_number():
			return null
		match h.length():
			3, 4:
				var r := ("0x" + h[0] + h[0]).hex_to_int()
				var g := ("0x" + h[1] + h[1]).hex_to_int()
				var b := ("0x" + h[2] + h[2]).hex_to_int()
				var a := ("0x" + h[3] + h[3]).hex_to_int() if h.length() == 4 else 255
				return Color8(r, g, b, a)
			6, 8:
				var r2 := ("0x" + h.substr(0, 2)).hex_to_int()
				var g2 := ("0x" + h.substr(2, 2)).hex_to_int()
				var b2 := ("0x" + h.substr(4, 2)).hex_to_int()
				var a2 := ("0x" + h.substr(6, 2)).hex_to_int() if h.length() == 8 else 255
				return Color8(r2, g2, b2, a2)
		return null
	if s == "transparent":
		return Color(0, 0, 0, 0)
	if s == "currentcolor":
		return Color(0, 0, 0, 1)
	if NAMED.has(s):
		var n: int = NAMED[s]
		return Color8((n >> 16) & 255, (n >> 8) & 255, n & 255, 255)
	var p := s.find("(")
	if p < 0 or not s.ends_with(")"):
		return null
	var fn := s.substr(0, p).strip_edges()
	var inner := s.substr(p + 1, s.length() - p - 2).replace("/", " / ").replace(",", " ")
	var parts: Array = []
	for t in inner.split(" ", false):
		parts.append(t)
	var alpha := 1.0
	var ai := parts.find("/")
	if ai >= 0:
		if ai + 1 < parts.size():
			alpha = _num(parts[ai + 1], 1.0)
		parts = parts.slice(0, ai)
	elif parts.size() == 4:
		alpha = _num(parts[3], 1.0)
		parts = parts.slice(0, 3)
	if parts.size() != 3:
		return null
	alpha = clampf(alpha, 0.0, 1.0)
	if fn == "rgb" or fn == "rgba":
		var ch: Array = []
		for t in parts:
			var tt: String = t
			if tt.ends_with("%"):
				ch.append(clampf(float(tt.trim_suffix("%")) * 2.55, 0.0, 255.0))
			else:
				ch.append(clampf(float(tt), 0.0, 255.0))
		# Chrome rounds channel values to integers
		return Color8(int(roundf(ch[0])), int(roundf(ch[1])), int(roundf(ch[2])), int(roundf(alpha * 255.0)))
	if fn == "hsl" or fn == "hsla":
		var hs: String = parts[0]
		var hue := 0.0
		if hs.ends_with("deg"):
			hue = float(hs.trim_suffix("deg"))
		elif hs.ends_with("rad"):
			hue = rad_to_deg(float(hs.trim_suffix("rad")))
		elif hs.ends_with("turn"):
			hue = float(hs.trim_suffix("turn")) * 360.0
		else:
			hue = float(hs)
		var sat := clampf(float(String(parts[1]).trim_suffix("%")) / 100.0, 0.0, 1.0)
		var lig := clampf(float(String(parts[2]).trim_suffix("%")) / 100.0, 0.0, 1.0)
		hue = fposmod(hue, 360.0) / 360.0
		var q := lig * (1.0 + sat) if lig < 0.5 else lig + sat - lig * sat
		var pp := 2.0 * lig - q
		var r3 := _hue2rgb(pp, q, hue + 1.0 / 3.0)
		var g3 := _hue2rgb(pp, q, hue)
		var b3 := _hue2rgb(pp, q, hue - 1.0 / 3.0)
		return Color8(int(roundf(r3 * 255.0)), int(roundf(g3 * 255.0)), int(roundf(b3 * 255.0)), int(roundf(alpha * 255.0)))
	return null

static func _num(t: String, d: float) -> float:
	if t.ends_with("%"):
		return float(t.trim_suffix("%")) / 100.0
	if t.is_valid_float() or t.is_valid_int():
		return float(t)
	return d

static func _hue2rgb(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p

static func colorString(c: Color) -> String:
	if c.a8 >= 255:
		return "#%02x%02x%02x" % [c.r8, c.g8, c.b8]
	var a := snappedf(c.a, 0.001)
	return "rgba(%d, %d, %d, %s)" % [c.r8, c.g8, c.b8, str(a)]

# DOMMatrix-like {a,b,c,d,e,f} / Transform2D / [a,b,c,d,e,f] -> Transform2D
static func toXform(m) -> Transform2D:
	if m is Transform2D:
		return m
	if m is Dictionary:
		return Transform2D(Vector2(float(m.get("a", 1.0)), float(m.get("b", 0.0))), Vector2(float(m.get("c", 0.0)), float(m.get("d", 1.0))), Vector2(float(m.get("e", 0.0)), float(m.get("f", 0.0))))
	if m is Array and m.size() >= 6:
		return Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
	return Transform2D.IDENTITY

# ================================================================================================ gradients etc.
class CanvasGradient:
	extends RefCounted
	var kind := 1            # 1 linear, 2 radial, 3 conic
	var p := PackedFloat64Array()
	var stops: Array = []    # [offset, Color]
	var _key := ""
	func addColorStop(offset: float, color) -> void:
		if offset < 0.0 or offset > 1.0 or is_nan(offset):
			push_error("[canvas] IndexSizeError: addColorStop offset")
			return
		var c = DACanvas.parseColor(color)
		if c == null:
			push_error("[canvas] SyntaxError: addColorStop colour '%s'" % str(color))
			return
		stops.append([offset, c])
		_key = ""
	func key() -> String:
		if _key == "":
			var parts := PackedStringArray()
			for s in stops:
				var c: Color = s[1]
				parts.append("%.5f:%s" % [s[0], c.to_html(true)])
			_key = ",".join(parts)
		return _key

class CanvasPattern:
	extends RefCounted
	var src = null
	var rep := 3             # bit 1 = repeat x, 2 = repeat y
	var m := Transform2D.IDENTITY
	func setTransform(mat = null) -> void:
		m = DACanvas.toXform(mat) if mat != null else Transform2D.IDENTITY

# Gradient ramp (256x1, unpremultiplied interpolation like the spec) -> [ImageTexture, Image]
static var _ramps := {}
static func ramp(g: CanvasGradient, cm = null) -> Array:
	var key := g.key() + ("" if cm == null else "|" + str(cm))
	var hit = _ramps.get(key)
	if hit != null:
		return hit
	if _ramps.size() > 1024:
		_ramps.clear()
	var st: Array = g.stops.duplicate()
	# stable sort by offset
	var idx := range(st.size())
	idx.sort_custom(func(a, b): return st[a][0] < st[b][0] or (st[a][0] == st[b][0] and a < b))
	var sorted: Array = []
	for i in idx:
		var c: Color = st[i][1]
		if cm != null:
			c = _applyCm(c, cm)
		sorted.append([st[i][0], c])
	var b := PackedByteArray()
	b.resize(256 * 4)
	for i in 256:
		var t := float(i) / 255.0
		var c := _rampAt(sorted, t)
		b[i * 4] = c.r8
		b[i * 4 + 1] = c.g8
		b[i * 4 + 2] = c.b8
		b[i * 4 + 3] = c.a8
	var img := Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, b)
	var res := [ImageTexture.create_from_image(img), img]
	_ramps[key] = res
	return res

static func _rampAt(st: Array, t: float) -> Color:
	var n := st.size()
	if n == 0:
		return Color(0, 0, 0, 0)
	if t <= st[0][0]:
		# with several stops at the first offset, the first wins below it
		return st[0][1]
	if t >= st[n - 1][0]:
		return st[n - 1][1]
	for i in range(n - 1):
		var a: float = st[i][0]
		var b: float = st[i + 1][0]
		if t >= a and t < b:
			var f := (t - a) / (b - a)
			return (st[i][1] as Color).lerp(st[i + 1][1], f)
	return st[n - 1][1]

# ------------------------------------------------------------------------------------------------ filters
# CSS filter string -> {blur: float (sigma px), cm: Array[Vector4] (m0..m3, mo) or null}
static var _filters := {}
static func parseFilter(s: String) -> Dictionary:
	var hit = _filters.get(s)
	if hit != null:
		return hit
	var res := {"blur": 0.0, "cm": null}
	var str2 := s.strip_edges().to_lower()
	if str2 == "" or str2 == "none":
		_filters[s] = res
		return res
	var M := Projection.IDENTITY   # columns: we use rows via helper
	var rows := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1)]
	var off := Vector4.ZERO
	var any := false
	var i := 0
	while i < str2.length():
		var p := str2.find("(", i)
		if p < 0:
			break
		var q := str2.find(")", p)
		if q < 0:
			break
		var fn := str2.substr(i, p - i).strip_edges()
		var arg := str2.substr(p + 1, q - p - 1).strip_edges()
		i = q + 1
		var v := 0.0
		if arg.ends_with("%"):
			v = float(arg.trim_suffix("%")) / 100.0
		elif arg.ends_with("px"):
			v = float(arg.trim_suffix("px"))
		elif arg.ends_with("deg"):
			v = deg_to_rad(float(arg.trim_suffix("deg")))
		elif arg.ends_with("turn"):
			v = float(arg.trim_suffix("turn")) * TAU_
		elif arg.ends_with("rad"):
			v = float(arg.trim_suffix("rad"))
		else:
			v = float(arg) if arg != "" else 1.0
		var fm = null   # [rows(4 Vector4), offset Vector4]
		match fn:
			"blur":
				res.blur = v
			"brightness":
				fm = [[Vector4(v, 0, 0, 0), Vector4(0, v, 0, 0), Vector4(0, 0, v, 0), Vector4(0, 0, 0, 1)], Vector4.ZERO]
			"contrast":
				var o := 0.5 - 0.5 * v
				fm = [[Vector4(v, 0, 0, 0), Vector4(0, v, 0, 0), Vector4(0, 0, v, 0), Vector4(0, 0, 0, 1)], Vector4(o, o, o, 0)]
			"saturate":
				fm = [[Vector4(0.213 + 0.787 * v, 0.715 - 0.715 * v, 0.072 - 0.072 * v, 0), Vector4(0.213 - 0.213 * v, 0.715 + 0.285 * v, 0.072 - 0.072 * v, 0), Vector4(0.213 - 0.213 * v, 0.715 - 0.715 * v, 0.072 + 0.928 * v, 0), Vector4(0, 0, 0, 1)], Vector4.ZERO]
			"grayscale":
				var g := 1.0 - clampf(v, 0.0, 1.0)
				fm = [[Vector4(0.2126 + 0.7874 * g, 0.7152 - 0.7152 * g, 0.0722 - 0.0722 * g, 0), Vector4(0.2126 - 0.2126 * g, 0.7152 + 0.2848 * g, 0.0722 - 0.0722 * g, 0), Vector4(0.2126 - 0.2126 * g, 0.7152 - 0.7152 * g, 0.0722 + 0.9278 * g, 0), Vector4(0, 0, 0, 1)], Vector4.ZERO]
			"sepia":
				var a := 1.0 - clampf(v, 0.0, 1.0)
				fm = [[Vector4(0.393 + 0.607 * a, 0.769 - 0.769 * a, 0.189 - 0.189 * a, 0), Vector4(0.349 - 0.349 * a, 0.686 + 0.314 * a, 0.168 - 0.168 * a, 0), Vector4(0.272 - 0.272 * a, 0.534 - 0.534 * a, 0.131 + 0.869 * a, 0), Vector4(0, 0, 0, 1)], Vector4.ZERO]
			"invert":
				var k := clampf(v, 0.0, 1.0)
				var d := 1.0 - 2.0 * k
				fm = [[Vector4(d, 0, 0, 0), Vector4(0, d, 0, 0), Vector4(0, 0, d, 0), Vector4(0, 0, 0, 1)], Vector4(k, k, k, 0)]
			"opacity":
				fm = [[Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, clampf(v, 0.0, 1.0))], Vector4.ZERO]
			"hue-rotate":
				var c := cos(v)
				var sn := sin(v)
				fm = [[Vector4(0.213 + c * 0.787 - sn * 0.213, 0.715 - c * 0.715 - sn * 0.715, 0.072 - c * 0.072 + sn * 0.928, 0), Vector4(0.213 - c * 0.213 + sn * 0.143, 0.715 + c * 0.285 + sn * 0.140, 0.072 - c * 0.072 - sn * 0.283, 0), Vector4(0.213 - c * 0.213 - sn * 0.787, 0.715 - c * 0.715 + sn * 0.715, 0.072 + c * 0.928 + sn * 0.072, 0), Vector4(0, 0, 0, 1)], Vector4.ZERO]
		if fm != null:
			any = true
			# compose: new = F * current  (F applied after)
			var nr: Array = []
			var fr: Array = fm[0]
			for r in 4:
				var row: Vector4 = fr[r]
				var acc := Vector4.ZERO
				for k2 in 4:
					acc += (rows[k2] as Vector4) * row[k2]
				nr.append(acc)
			var fo: Vector4 = fm[1]
			var noff := Vector4(fr[0].dot(off), fr[1].dot(off), fr[2].dot(off), fr[3].dot(off)) + fo
			rows = nr
			off = noff
	if any:
		res.cm = [rows[0], rows[1], rows[2], rows[3], off]
	_filters[s] = res
	return res

static func _applyCm(c: Color, cm: Array) -> Color:
	var v := Vector4(c.r, c.g, c.b, c.a)
	return Color(clampf((cm[0] as Vector4).dot(v) + cm[4].x, 0.0, 1.0), clampf((cm[1] as Vector4).dot(v) + cm[4].y, 0.0, 1.0), clampf((cm[2] as Vector4).dot(v) + cm[4].z, 0.0, 1.0), clampf((cm[3] as Vector4).dot(v) + cm[4].w, 0.0, 1.0))

# ================================================================================================ paint
class Paint:
	extends RefCounted
	var kind := 0            # 0 solid, 1 straight texture (linear ramp / image), 2 radial, 3 conic, 4 pattern,
	                         # 5 premultiplied layer, 6 shadow (colour x layer alpha)
	var color := Color.BLACK
	var tex := RID()
	var keep = null          # keeps the texture alive
	var xf := Transform2D.IDENTITY   # device -> uv (kinds 1, 4, 5, 6) or device -> user (2, 3)
	var a := Vector4.ZERO
	var b := Vector4.ZERO
	var rep := 3
	var premul := false
	var opaque := false
	var dep = null           # RT to render first
	var smooth := true
	var cm = null            # colour matrix for textures
	var img: Image = null    # CPU sampling (ramp or source image)
	var srcW := 1
	var srcH := 1

# ================================================================================================ clip
class Clip:
	extends RefCounted
	var empty := false
	var isRect := false
	var rect := Rect2()      # device rect (analytic) or bounding box of the mask region
	var P := PackedVector2Array()   # device triangles (mask)
	var I := PackedInt32Array()
	var parent: Clip = null
	var rt = null
	var rtGen := -1
	var cpu := PackedFloat32Array()   # software canvas coverage (w*h)
	func maskRT(cw: int, ch: int):
		if isRect or empty:
			return null
		if rt != null and rt.gen == rtGen and rt.state != 0:
			return rt
		var pr = parent.maskRT(cw, ch) if parent != null else null
		var box := Rect2i(Vector2i(int(floor(rect.position.x)) - 1, int(floor(rect.position.y)) - 1), Vector2i.ZERO)
		var e := Vector2i(int(ceil(rect.end.x)) + 1, int(ceil(rect.end.y)) + 1)
		box.size = e - box.position
		box = box.intersection(Rect2i(0, 0, cw, ch))
		if box.size.x <= 0 or box.size.y <= 0:
			box = Rect2i(0, 0, 1, 1)
		rt = DACanvasGPU.mask(P, I, box, pr)
		rtGen = rt.gen
		return rt

# ================================================================================================ state
class St:
	extends RefCounted
	var fillStyle: Variant = "#000000"
	var strokeStyle: Variant = "#000000"
	var fillColor = Color.BLACK       # parsed colour or gradient/pattern object
	var strokeColor = Color.BLACK
	var globalAlpha := 1.0
	var lineWidth := 1.0
	var lineCap := "butt"
	var lineJoin := "miter"
	var miterLimit := 10.0
	var dash := PackedFloat64Array()
	var dashOffset := 0.0
	var font := "10px sans-serif"
	var textAlign := "start"
	var textBaseline := "alphabetic"
	var direction := "ltr"
	var letterSpacing := "0px"
	var letterPx := 0.0
	var gco := "source-over"
	var op := 0
	var shadowBlur := 0.0
	var shadowColor := Color(0, 0, 0, 0)
	var shadowColorStr := "rgba(0, 0, 0, 0)"
	var shadowOffsetX := 0.0
	var shadowOffsetY := 0.0
	var filter := "none"
	var flt: Dictionary = {"blur": 0.0, "cm": null}
	var smoothing := true
	var smoothingQuality := "low"
	var xf := Transform2D.IDENTITY
	var clip: Clip = null
	func copy() -> St:
		var s := St.new()
		s.fillStyle = fillStyle; s.strokeStyle = strokeStyle; s.fillColor = fillColor; s.strokeColor = strokeColor
		s.globalAlpha = globalAlpha; s.lineWidth = lineWidth; s.lineCap = lineCap; s.lineJoin = lineJoin
		s.miterLimit = miterLimit; s.dash = dash; s.dashOffset = dashOffset; s.font = font; s.textAlign = textAlign
		s.textBaseline = textBaseline; s.direction = direction; s.letterSpacing = letterSpacing; s.letterPx = letterPx
		s.gco = gco; s.op = op; s.shadowBlur = shadowBlur; s.shadowColor = shadowColor; s.shadowColorStr = shadowColorStr
		s.shadowOffsetX = shadowOffsetX; s.shadowOffsetY = shadowOffsetY; s.filter = filter; s.flt = flt
		s.smoothing = smoothing; s.smoothingQuality = smoothingQuality; s.xf = xf; s.clip = clip
		return s

class CtxState:
	extends RefCounted
	var st := St.new()
	var stack: Array = []
	var path := DAPath2D.Builder.new()
	func reset() -> void:
		st = St.new()
		stack = []
		path = DAPath2D.Builder.new()

# ================================================================================================ Context2D
class Context2D:
	extends RefCounted
	var canvas: DACanvas
	var _cs: CtxState

	func _init(c: DACanvas) -> void:
		canvas = c
		_cs = c._state

	# -------------------------------------------------------------------------------------------- properties
	var fillStyle: Variant:
		get:
			return _cs.st.fillStyle
		set(v):
			var p = _style(v)
			if p != null:
				_cs.st.fillStyle = v if not (v is String) or not (p is Color) else DACanvas.colorString(p)
				_cs.st.fillColor = p
	var strokeStyle: Variant:
		get:
			return _cs.st.strokeStyle
		set(v):
			var p = _style(v)
			if p != null:
				_cs.st.strokeStyle = v if not (v is String) or not (p is Color) else DACanvas.colorString(p)
				_cs.st.strokeColor = p
	var globalAlpha: float:
		get:
			return _cs.st.globalAlpha
		set(v):
			if is_finite(v) and v >= 0.0 and v <= 1.0:
				_cs.st.globalAlpha = v
	var lineWidth: float:
		get:
			return _cs.st.lineWidth
		set(v):
			if is_finite(v) and v > 0.0:
				_cs.st.lineWidth = v
	var lineCap: String:
		get:
			return _cs.st.lineCap
		set(v):
			if v in ["butt", "round", "square"]:
				_cs.st.lineCap = v
	var lineJoin: String:
		get:
			return _cs.st.lineJoin
		set(v):
			if v in ["miter", "round", "bevel"]:
				_cs.st.lineJoin = v
	var miterLimit: float:
		get:
			return _cs.st.miterLimit
		set(v):
			if is_finite(v) and v > 0.0:
				_cs.st.miterLimit = v
	var lineDashOffset: float:
		get:
			return _cs.st.dashOffset
		set(v):
			if is_finite(v):
				_cs.st.dashOffset = v
	var font: String:
		get:
			return _cs.st.font
		set(v):
			if DACanvasText.resolve(v) != null:
				_cs.st.font = v
	var textAlign: String:
		get:
			return _cs.st.textAlign
		set(v):
			if v in ["start", "end", "left", "right", "center"]:
				_cs.st.textAlign = v
	var textBaseline: String:
		get:
			return _cs.st.textBaseline
		set(v):
			if v in ["top", "hanging", "middle", "alphabetic", "ideographic", "bottom"]:
				_cs.st.textBaseline = v
	var direction: String:
		get:
			return _cs.st.direction
		set(v):
			if v in ["ltr", "rtl", "inherit"]:
				_cs.st.direction = v
	var letterSpacing: String:
		get:
			return _cs.st.letterSpacing
		set(v):
			var s := String(v).strip_edges()
			var px := 0.0
			if s.ends_with("px"):
				px = float(s.trim_suffix("px"))
			elif s.ends_with("em"):
				px = float(s.trim_suffix("em")) * _fontPx()
			elif s == "0" or s == "normal":
				px = 0.0
			else:
				return
			_cs.st.letterSpacing = s
			_cs.st.letterPx = px
	var fontKerning := "auto"
	var textRendering := "auto"
	var wordSpacing := "0px"
	var fontStretch := "normal"
	var fontVariantCaps := "normal"
	var globalCompositeOperation: String:
		get:
			return _cs.st.gco
		set(v):
			if DACanvasGPU.OPS.has(v):
				_cs.st.gco = v
				_cs.st.op = DACanvasGPU.OPS[v]
	var shadowBlur: float:
		get:
			return _cs.st.shadowBlur
		set(v):
			if is_finite(v) and v >= 0.0:
				_cs.st.shadowBlur = v
	var shadowColor: Variant:
		get:
			return _cs.st.shadowColorStr
		set(v):
			var c = DACanvas.parseColor(v)
			if c != null:
				_cs.st.shadowColor = c
				_cs.st.shadowColorStr = DACanvas.colorString(c)
	var shadowOffsetX: float:
		get:
			return _cs.st.shadowOffsetX
		set(v):
			if is_finite(v):
				_cs.st.shadowOffsetX = v
	var shadowOffsetY: float:
		get:
			return _cs.st.shadowOffsetY
		set(v):
			if is_finite(v):
				_cs.st.shadowOffsetY = v
	var filter: String:
		get:
			return _cs.st.filter
		set(v):
			_cs.st.filter = v
			_cs.st.flt = DACanvas.parseFilter(v)
	var imageSmoothingEnabled: bool:
		get:
			return _cs.st.smoothing
		set(v):
			_cs.st.smoothing = v
	var imageSmoothingQuality: String:
		get:
			return _cs.st.smoothingQuality
		set(v):
			_cs.st.smoothingQuality = v

	func _style(v) -> Variant:
		if v is CanvasGradient or v is CanvasPattern:
			return v
		return DACanvas.parseColor(v)

	func _fontPx() -> float:
		var sp = DACanvasText.resolve(_cs.st.font)
		return sp.px if sp != null else 10.0

	# -------------------------------------------------------------------------------------------- state
	func save() -> void:
		_cs.stack.append(_cs.st.copy())

	func restore() -> void:
		if _cs.stack.is_empty():
			return
		_cs.st = _cs.stack.pop_back()

	func reset() -> void:
		_cs.reset()
		canvas._clearAll()

	func getContextAttributes() -> Dictionary:
		return {"alpha": true, "willReadFrequently": canvas._cpu}

	func isContextLost() -> bool:
		return false

	# -------------------------------------------------------------------------------------------- transforms
	func translate(x: float, y: float) -> void:
		var t := _cs.st.xf
		t.origin += t.x * x + t.y * y
		_cs.st.xf = t

	func rotate(a: float) -> void:
		_cs.st.xf = _cs.st.xf * Transform2D(a, Vector2.ZERO)

	func scale(sx: float, sy: float) -> void:
		var t := _cs.st.xf
		t.x *= sx
		t.y *= sy
		_cs.st.xf = t

	func transform(a: float, b: float, c: float, d: float, e: float, f: float) -> void:
		_cs.st.xf = _cs.st.xf * Transform2D(Vector2(a, b), Vector2(c, d), Vector2(e, f))

	func setTransform(a = null, b = null, c = null, d = null, e = null, f = null) -> void:
		if a == null:
			_cs.st.xf = Transform2D.IDENTITY
		elif b == null:
			_cs.st.xf = DACanvas.toXform(a)
		else:
			_cs.st.xf = Transform2D(Vector2(a, b), Vector2(c, d), Vector2(e, f))

	func resetTransform() -> void:
		_cs.st.xf = Transform2D.IDENTITY

	func getTransform() -> Dictionary:
		var t := _cs.st.xf
		return {"a": t.x.x, "b": t.x.y, "c": t.y.x, "d": t.y.y, "e": t.origin.x, "f": t.origin.y, "is2D": true,
			"isIdentity": t == Transform2D.IDENTITY}

	# -------------------------------------------------------------------------------------------- path
	func _pb() -> DAPath2D.Builder:
		var b: DAPath2D.Builder = _cs.path
		b.setXf(_cs.st.xf)
		return b

	func beginPath() -> void:
		_cs.path.clear()

	func closePath() -> void:
		_cs.path.closePath()

	func moveTo(x: float, y: float) -> void:
		_pb().moveTo(x, y)

	func lineTo(x: float, y: float) -> void:
		_pb().lineTo(x, y)

	func quadraticCurveTo(cx: float, cy: float, x: float, y: float) -> void:
		_pb().quadraticCurveTo(cx, cy, x, y)

	func bezierCurveTo(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> void:
		_pb().bezierCurveTo(c1x, c1y, c2x, c2y, x, y)

	func arc(x: float, y: float, r: float, a0: float, a1: float, ccw: bool = false) -> void:
		_pb().arc(x, y, r, a0, a1, ccw)

	func arcTo(x1: float, y1: float, x2: float, y2: float, r: float) -> void:
		_pb().arcTo(x1, y1, x2, y2, r)

	func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: bool = false) -> void:
		_pb().ellipse(x, y, rx, ry, rot, a0, a1, ccw)

	func rect(x: float, y: float, w: float, h: float) -> void:
		_pb().rect(x, y, w, h)

	func roundRect(x: float, y: float, w: float, h: float, radii = 0.0) -> void:
		_pb().roundRect(x, y, w, h, radii)

	# Path geometry of the current path or a DAPath2D (replayed through the current transform).
	func _pathOf(p) -> DAPath2D.Builder:
		if p is DAPath2D:
			var b := DAPath2D.Builder.new()
			(p as DAPath2D).replay(b, _cs.st.xf)
			return b
		return _cs.path

	# -------------------------------------------------------------------------------------------- drawing
	func fill(a = null, b = null) -> void:
		var path = null
		var rule := "nonzero"
		if a is DAPath2D:
			path = a
			if b is String:
				rule = b
		elif a is String:
			rule = a
		var g := _pathOf(path).geo()
		canvas._fill(_cs.st, g[0], g[1], rule == "evenodd", false, _cs.st.fillColor, false)

	func stroke(p = null) -> void:
		var b := _pathOf(p)
		var pl := b.polylines()
		canvas._stroke(_cs.st, pl[0], pl[1])

	func clip(a = null, b = null) -> void:
		var path = null
		var rule := "nonzero"
		if a is DAPath2D:
			path = a
			if b is String:
				rule = b
		elif a is String:
			rule = a
		var g := _pathOf(path).geo()
		_cs.st.clip = canvas._makeClip(_cs.st.clip, g[0], g[1], rule == "evenodd")

	func isPointInPath(a, b, c = null, d = null) -> bool:
		var path = null
		var x: float
		var y: float
		var rule := "nonzero"
		if a is DAPath2D:
			path = a
			x = b
			y = c
			if d is String:
				rule = d
		else:
			x = a
			y = b
			if c is String:
				rule = c
		var g := _pathOf(path).geo()
		return DACanvas._pointIn(g[0], g[1], Vector2(x, y), rule == "evenodd")

	func fillRect(x: float, y: float, w: float, h: float) -> void:
		if w == 0.0 or h == 0.0:
			return
		var xf := _cs.st.xf
		var P := PackedVector2Array([xf * Vector2(x, y), xf * Vector2(x + w, y), xf * Vector2(x + w, y + h), xf * Vector2(x, y + h)])
		canvas._fill(_cs.st, P, PackedInt32Array([0]), false, true, _cs.st.fillColor, false)

	func strokeRect(x: float, y: float, w: float, h: float) -> void:
		var b := DAPath2D.Builder.new()
		b.setXf(_cs.st.xf)
		if w == 0.0 and h == 0.0:
			return
		if w == 0.0 or h == 0.0:
			b.moveTo(x, y)
			b.lineTo(x + w, y + h)
		else:
			b.rect(x, y, w, h)
		var pl := b.polylines()
		canvas._stroke(_cs.st, pl[0], pl[1])

	func clearRect(x: float, y: float, w: float, h: float) -> void:
		if w == 0.0 or h == 0.0:
			return
		var xf := _cs.st.xf
		var P := PackedVector2Array([xf * Vector2(x, y), xf * Vector2(x + w, y), xf * Vector2(x + w, y + h), xf * Vector2(x, y + h)])
		canvas._clear(_cs.st, P)

	# -------------------------------------------------------------------------------------------- text
	func fillText(text, x: float, y: float, maxWidth = null) -> void:
		canvas._text(_cs.st, str(text), x, y, maxWidth, false)

	func strokeText(text, x: float, y: float, maxWidth = null) -> void:
		canvas._text(_cs.st, str(text), x, y, maxWidth, true)

	func measureText(text) -> Dictionary:
		return canvas._measure(_cs.st, str(text))

	# -------------------------------------------------------------------------------------------- dashes
	func setLineDash(segs) -> void:
		var d := PackedFloat64Array()
		for v in segs:
			var f := float(v)
			if not is_finite(f) or f < 0.0:
				return
			d.append(f)
		if d.size() % 2 == 1:
			d.append_array(d.duplicate())
		_cs.st.dash = d

	func getLineDash() -> Array:
		return Array(_cs.st.dash)

	# -------------------------------------------------------------------------------------------- gradients
	func createLinearGradient(x0: float, y0: float, x1: float, y1: float) -> CanvasGradient:
		var g := CanvasGradient.new()
		g.kind = 1
		g.p = PackedFloat64Array([x0, y0, x1, y1])
		return g

	func createRadialGradient(x0: float, y0: float, r0: float, x1: float, y1: float, r1: float) -> CanvasGradient:
		if r0 < 0.0 or r1 < 0.0:
			push_error("[canvas] IndexSizeError: createRadialGradient radius")
		var g := CanvasGradient.new()
		g.kind = 2
		g.p = PackedFloat64Array([x0, y0, maxf(r0, 0.0), x1, y1, maxf(r1, 0.0)])
		return g

	func createConicGradient(startAngle: float, x: float, y: float) -> CanvasGradient:
		var g := CanvasGradient.new()
		g.kind = 3
		g.p = PackedFloat64Array([startAngle, x, y])
		return g

	func createPattern(img, repetition = "repeat") -> CanvasPattern:
		if img == null:
			return null
		var p := CanvasPattern.new()
		p.src = img
		var r := str(repetition) if repetition != null else "repeat"
		p.rep = 3 if r == "" or r == "repeat" else (1 if r == "repeat-x" else (2 if r == "repeat-y" else 0))
		return p

	# -------------------------------------------------------------------------------------------- images
	func drawImage(img, a: float, b: float, c = null, d = null, e = null, f = null, g = null, h = null) -> void:
		canvas._drawImage(_cs.st, img, a, b, c, d, e, f, g, h)

	func createImageData(a, b = null) -> Dictionary:
		var w: int
		var hh: int
		if a is Dictionary:
			w = int(a.width)
			hh = int(a.height)
		else:
			w = int(absf(float(a)))
			hh = int(absf(float(b)))
		var data := PackedByteArray()
		data.resize(w * hh * 4)
		return {"width": w, "height": hh, "data": data, "colorSpace": "srgb"}

	func getImageData(sx: float, sy: float, sw: float, sh: float) -> Dictionary:
		return canvas._getImageData(int(sx), int(sy), int(sw), int(sh))

	func putImageData(img: Dictionary, dx: float, dy: float, dirtyX = null, dirtyY = null, dirtyW = null, dirtyH = null) -> void:
		canvas._putImageData(img, int(dx), int(dy), dirtyX, dirtyY, dirtyW, dirtyH)

# ================================================================================================ canvas ops
func _clearAll() -> void:
	if _cpu:
		_px.fill(0.0)
		_cpuDirty = true
		DACanvasGPU.markDirty(self)
		return
	if _ver != null or _baked != null:
		_target(true)

# Resolves a fill/stroke style to a Paint for the current transform (null = draws nothing).
func _paint(style, st: St) -> Paint:
	var p := Paint.new()
	var cm = st.flt.cm
	if style is Color:
		p.kind = 0
		p.color = style if cm == null else DACanvas._applyCm(style, cm)
		p.opaque = p.color.a >= 1.0
		return p
	if style is CanvasGradient:
		var g: CanvasGradient = style
		if g.stops.is_empty():
			return null
		var rp := DACanvas.ramp(g, cm)
		p.tex = (rp[0] as ImageTexture).get_rid()
		p.keep = rp[0]
		p.img = rp[1]
		p.opaque = true
		for s in g.stops:
			if (s[1] as Color).a < 1.0:
				p.opaque = false
				break
		var inv := st.xf.affine_inverse()
		if g.kind == 1:
			var p0 := Vector2(g.p[0], g.p[1])
			var p1 := Vector2(g.p[2], g.p[3])
			var d := p1 - p0
			var dd := d.length_squared()
			if dd <= 0.0:
				return null
			var gg := d / dd
			var c0 := -p0.dot(gg)
			var s := 255.0 / 256.0
			var h := 0.5 / 256.0
			# u = s * (gg . (A p + o) + c0) + h
			p.kind = 1
			p.xf = Transform2D(Vector2(gg.dot(inv.x) * s, 0.0), Vector2(gg.dot(inv.y) * s, 0.0), Vector2((gg.dot(inv.origin) + c0) * s + h, 0.5))
			p.a = Vector4(1, 0, 0, 0)   # marks "ramp" for the CPU sampler
			return p
		if g.kind == 2:
			if g.p[0] == g.p[3] and g.p[1] == g.p[4] and g.p[2] == g.p[5]:
				return null
			p.kind = 2
			p.xf = inv
			p.a = Vector4(g.p[0], g.p[1], g.p[2], 0.0)
			p.b = Vector4(g.p[3], g.p[4], g.p[5], 0.0)
			# a radial gradient paints nothing outside the cone unless it covers the plane
			p.opaque = false
			return p
		p.kind = 3
		p.xf = inv
		p.a = Vector4(g.p[1], g.p[2], g.p[0], 0.0)
		return p
	if style is CanvasPattern:
		var pt: CanvasPattern = style
		var src := _imageSource(pt.src)
		if src.is_empty():
			return null
		p.kind = 4
		p.tex = src[0]
		p.premul = src[1]
		p.dep = src[2]
		p.keep = src[3]
		p.srcW = src[4]
		p.srcH = src[5]
		p.rep = pt.rep
		p.smooth = st.smoothing
		p.cm = cm
		var full := st.xf * pt.m
		p.xf = Transform2D(Vector2(1.0 / p.srcW, 0), Vector2(0, 1.0 / p.srcH), Vector2.ZERO) * full.affine_inverse()
		p.opaque = false
		p.set_meta("src", pt.src)
		return p
	return null

# [texRid, premul, depRT, keep, w, h] for DACanvas / Texture2D / Image sources (empty = invalid).
static var _imgTex := {}
func _imageSource(img) -> Array:
	if img is DACanvas:
		var c: DACanvas = img
		if c._w <= 0 or c._h <= 0:
			return []
		return c._source(null)
	if img is Texture2D:
		var t: Texture2D = img
		if t is CanvasTex:
			return (t as CanvasTex).canvas._source(null)
		return [t.get_rid(), false, null, t, t.get_width(), t.get_height()]
	if img is Image:
		var im: Image = img
		var it: ImageTexture = im.get_meta("_dacanvas_tex") if im.has_meta("_dacanvas_tex") else null
		if it == null or im.has_meta("_dacanvas_dirty"):
			it = ImageTexture.create_from_image(im)
			im.set_meta("_dacanvas_tex", it)
			im.remove_meta("_dacanvas_dirty")
		return [it.get_rid(), false, null, it, im.get_width(), im.get_height()]
	if img is Dictionary and img.has("data"):
		var im2 := Image.create_from_data(int(img.width), int(img.height), false, Image.FORMAT_RGBA8, img.data)
		var it2 := ImageTexture.create_from_image(im2)
		return [it2.get_rid(), false, null, it2, im2.get_width(), im2.get_height()]
	return []

func _shadowOn(st: St) -> bool:
	return st.shadowColor.a > 0.0 and (st.shadowBlur > 0.0 or st.shadowOffsetX != 0.0 or st.shadowOffsetY != 0.0)

# Core fill: polygons P/S (device), convex = every polygon is convex and they may overlap (pieces).
func _fill(st: St, P: PackedVector2Array, S: PackedInt32Array, evenodd: bool, convex: bool, style, pieces: bool) -> void:
	if P.size() < 3 or S.is_empty() or st.globalAlpha <= 0.0:
		return
	if st.clip != null and st.clip.empty:
		return
	var paint := _paint(style, st)
	if paint == null:
		return
	if _cpu:
		DACanvasCPU.fill(self, st, P, S, evenodd, paint)
		return
	# triangles
	var opaqueSafe := paint.opaque and st.globalAlpha >= 1.0 and (st.op == 0 or st.op == 6)
	var tri: Array
	var overlap := false
	if convex:
		tri = DACanvasGeom.fanAll(P, S)
		overlap = pieces or (S.size() > 1 and not opaqueSafe and DACanvasGeom.anyOverlap(P, S))
	else:
		tri = DACanvasGeom.triangulate(P, S, evenodd, true)
		if S.size() > 1 and not opaqueSafe and tri.size() > 2 and tri[2]:
			overlap = DACanvasGeom.anyOverlap(P, S)
	var box := DACanvasGeom.bbox(P)
	_gpuOp(st, tri[0], tri[1], paint, overlap, box)

func _stroke(st: St, subs: Array, closed: Array) -> void:
	if subs.is_empty() or st.globalAlpha <= 0.0:
		return
	var xf := st.xf
	var sim := _similarity(xf)
	var hw := st.lineWidth * 0.5
	var cap := 0 if st.lineCap == "butt" else (1 if st.lineCap == "round" else 2)
	var join := 0 if st.lineJoin == "miter" else (1 if st.lineJoin == "round" else 2)
	var geo: Array
	if sim > 0.0:
		var s2 := subs
		var c2 := closed
		if not st.dash.is_empty():
			var dp := PackedFloat64Array()
			for v in st.dash:
				dp.append(v * sim)
			var dd := DACanvasGeom.dash(subs, closed, dp, st.dashOffset * sim)
			s2 = dd[0]
			c2 = dd[1]
		geo = DACanvasGeom.stroke(s2, c2, hw * sim, cap, join, st.miterLimit, 0.2)
	else:
		# non-uniform transform: stroke in user space
		var inv := xf.affine_inverse()
		var us: Array = []
		for sp in subs:
			us.append(inv * (sp as PackedVector2Array))
		var c3 := closed
		if not st.dash.is_empty():
			var dd2 := DACanvasGeom.dash(us, closed, st.dash, st.dashOffset)
			us = dd2[0]
			c3 = dd2[1]
		var sc := maxf(xf.x.length(), xf.y.length())
		geo = DACanvasGeom.stroke(us, c3, hw, cap, join, st.miterLimit, 0.2 / maxf(sc, 1e-6))
		geo[0] = xf * (geo[0] as PackedVector2Array)
	var P: PackedVector2Array = geo[0]
	var S: PackedInt32Array = geo[1]
	if S.is_empty():
		return
	_fill(st, P, S, false, true, st.strokeColor, S.size() > 1)

static func _similarity(t: Transform2D) -> float:
	var lx := t.x.length()
	var ly := t.y.length()
	if lx <= 0.0 or ly <= 0.0:
		return 0.0
	if absf(lx - ly) > 1e-4 * maxf(lx, ly):
		return -1.0
	if absf(t.x.dot(t.y)) > 1e-4 * lx * ly:
		return -1.0
	return lx

# Emits one op (device triangles) on the GPU target with shadows / filters / composite handling.
func _gpuOp(st: St, P: PackedVector2Array, I: PackedInt32Array, paint: Paint, overlap: bool, box: Rect2) -> void:
	if I.is_empty() or (st.clip != null and st.clip.empty):
		return
	var op := st.op
	var blurF: float = st.flt.blur
	var clip := st.clip
	var cw := float(_w)
	var ch := float(_h)
	var nonlocal := DACanvasGPU.NONLOCAL.has(op)
	# cull: fully outside the canvas (and not a non-local op)
	if not nonlocal and not _shadowOn(st) and blurF <= 0.0:
		var cr := Rect2(0, 0, cw, ch)
		if clip != null:
			cr = cr.intersection(clip.rect)
		if not box.grow(1.0).intersects(cr):
			return
	var fullClear := false
	if (op == 9 or (op == 0 and paint.opaque and st.globalAlpha >= 1.0)) and clip == null and not _shadowOn(st) and blurF <= 0.0 and paint.kind == 0 and _coversCanvas(P, I, box):
		fullClear = true
	var rt = _target(fullClear)
	if _shadowOn(st) or blurF > 0.0 or nonlocal:
		_gpuLayered(rt, st, P, I, paint, overlap, box)
		return
	_emit(rt, P, I, paint, st.globalAlpha, op, clip, overlap, box)

# True when the triangles are an axis-aligned quad covering the whole canvas.
func _coversCanvas(P: PackedVector2Array, I: PackedInt32Array, box: Rect2) -> bool:
	if P.size() != 4 or I.size() != 6:
		return false
	if box.position.x > 0.0 or box.position.y > 0.0 or box.end.x < _w or box.end.y < _h:
		return false
	for q in P:
		if not ((is_equal_approx(q.x, box.position.x) or is_equal_approx(q.x, box.end.x)) and (is_equal_approx(q.y, box.position.y) or is_equal_approx(q.y, box.end.y))):
			return false
	return true

# Writes triangles into rt with the right blend path.
func _emit(rt, P: PackedVector2Array, I: PackedInt32Array, paint: Paint, alpha: float, op: int, clip: Clip, overlap: bool, box: Rect2) -> void:
	if paint.dep != null:
		DACanvasGPU.addDep(rt, paint.dep)
	if paint.keep != null:
		rt.keep.append(paint.keep)
	var opaqueSafe := paint.opaque and alpha >= 1.0 and (op == 0 or op == 6)
	var variant := "iso"
	if op == 0 and (opaqueSafe or not overlap):
		variant = "direct"
	elif op == 8 and not overlap:
		variant = "add"
	elif op == 6 and (opaqueSafe or not overlap):
		variant = "mul"
	var filt := RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR if paint.smooth else RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var uv := PackedVector2Array()
	if paint.kind != 0:
		uv = paint.xf * P
	var col := paint.color
	if paint.kind == 0:
		col.a *= alpha
	elif paint.kind == 6:
		col = paint.color
		col.a *= alpha
	else:
		col = Color(1, 1, 1, alpha)
	var mask = clip.maskRT(_w, _h) if clip != null else null
	var simpleTex := paint.kind == 1 and not paint.premul and paint.cm == null
	var simplePat := paint.kind == 4 and paint.rep == 3 and not paint.premul and paint.cm == null
	if variant == "direct" and clip == null and (paint.kind == 0 or simpleTex or simplePat):
		var rep := RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED if simplePat else 0
		DACanvasGPU.addDefault(rt, P, I, col, paint.tex if paint.kind != 0 else RID(), uv, filt if paint.kind != 0 else 0, rep)
		return
	if mask != null:
		DACanvasGPU.addDep(rt, mask)
	var mat := DACanvasGPU.paintMaterial(variant, mask)
	var params := {
		"pk": Vector4(paint.kind, 1.0 if paint.premul else 0.0, op, paint.rep),
		"pa": paint.a, "pb": paint.b,
		"rc": Vector4(clip.rect.position.x, clip.rect.position.y, clip.rect.end.x, clip.rect.end.y) if clip != null and clip.isRect else Vector4(-1e9, -1e9, 1e9, 1e9),
	}
	var cm = paint.cm
	if cm != null:
		params["m0"] = cm[0]; params["m1"] = cm[1]; params["m2"] = cm[2]; params["m3"] = cm[3]; params["mo"] = cm[4]
	else:
		params["m0"] = Vector4(1, 0, 0, 0); params["m1"] = Vector4(0, 1, 0, 0); params["m2"] = Vector4(0, 0, 1, 0); params["m3"] = Vector4(0, 0, 0, 1); params["mo"] = Vector4.ZERO
	var copyRect = null
	if variant == "iso":
		var cb := box.grow(2.0).intersection(Rect2(rt.origin, Vector2(rt.w, rt.h)))
		if cb.size.x <= 0.0 or cb.size.y <= 0.0:
			return
		copyRect = cb
	var rep2 := RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED if paint.kind == 4 else 0
	DACanvasGPU.addMaterial(rt, P, I, col, paint.tex if paint.kind != 0 else RID(), uv, mat, params, filt if paint.kind != 0 else 0, rep2, copyRect)

# Shadow / filter blur / non-local composite through an offscreen layer.
func _gpuLayered(rt, st: St, P: PackedVector2Array, I: PackedInt32Array, paint: Paint, overlap: bool, box: Rect2) -> void:
	var sh := _shadowOn(st)
	var sigS := st.shadowBlur * 0.5
	var sigF: float = st.flt.blur
	var off := Vector2(st.shadowOffsetX, st.shadowOffsetY) if sh else Vector2.ZERO
	var margin := ceilf(3.0 * maxf(sigS if sh else 0.0, sigF)) + 2.0
	var lim := Rect2(-margin - absf(off.x), -margin - absf(off.y), _w + 2.0 * (margin + absf(off.x)), _h + 2.0 * (margin + absf(off.y)))
	var L := box.grow(margin).intersection(lim)
	if L.size.x <= 0.0 or L.size.y <= 0.0:
		return
	var Li := Rect2i(Vector2i(int(floor(L.position.x)), int(floor(L.position.y))), Vector2i.ZERO)
	Li.size = Vector2i(int(ceil(L.end.x)), int(ceil(L.end.y))) - Li.position
	Li.size = Li.size.clamp(Vector2i.ONE, Vector2i(4096, 4096))
	var layer = DACanvasGPU.newRT(Li.size.x, Li.size.y, DACanvasGPU.MSAA, true, Vector2(Li.position))
	DACanvasGPU.retire(layer)
	_emit(layer, P, I, paint, st.globalAlpha, 0, null, overlap, box)
	DACanvasGPU.flush(layer)
	var lr := Rect2(Li.position, Li.size)
	var quadOf := func(r: Rect2) -> PackedVector2Array:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var QI := PackedInt32Array([0, 1, 2, 0, 2, 3])
	if sh:
		var ssrc = DACanvasGPU.blur(layer, sigS) if sigS > 0.0 else layer
		if sigF > 0.0:
			ssrc = DACanvasGPU.blur(ssrc, sigF)
		var sp := Paint.new()
		sp.kind = 6
		sp.color = st.shadowColor
		sp.tex = ssrc.tex
		sp.dep = ssrc
		var sr := lr
		sr.position += off
		sp.xf = Transform2D(Vector2(1.0 / sr.size.x, 0), Vector2(0, 1.0 / sr.size.y), -sr.position / sr.size)
		var sq: PackedVector2Array = quadOf.call(sr)
		_emit(rt, sq, QI, sp, 1.0, st.op, st.clip, false, sr)
	var nonlocal := DACanvasGPU.NONLOCAL.has(st.op)
	if sigF <= 0.0 and not nonlocal:
		_emit(rt, P, I, paint, st.globalAlpha, st.op, st.clip, overlap, box)
		return
	var src = DACanvasGPU.blur(layer, sigF) if sigF > 0.0 else layer
	var lp := Paint.new()
	lp.kind = 5
	lp.tex = src.tex
	lp.dep = src
	lp.xf = Transform2D(Vector2(1.0 / lr.size.x, 0), Vector2(0, 1.0 / lr.size.y), -lr.position / lr.size)
	var qr := lr
	if nonlocal:
		qr = Rect2(0, 0, _w, _h)
		if st.clip != null:
			qr = qr.intersection(st.clip.rect.grow(1.0))
	var q: PackedVector2Array = quadOf.call(qr)
	_emit(rt, q, QI, lp, 1.0, st.op, st.clip, nonlocal, qr)

# clearRect: device quad -> transparent black (ignores alpha/composite/shadow; honours clip & transform).
func _clear(st: St, P: PackedVector2Array) -> void:
	if st.clip != null and st.clip.empty:
		return
	var box := DACanvasGeom.bbox(P)
	if _cpu:
		var pc := Paint.new()
		pc.kind = 0
		pc.color = Color(0, 0, 0, 1)
		DACanvasCPU.clear(self, st, P, pc)
		return
	var I := PackedInt32Array([0, 1, 2, 0, 2, 3])
	if st.clip == null and _coversCanvas(P, I, box):
		_clearAll()
		return
	if not _hasContent:
		return
	var rt = _target(false)
	var pc2 := Paint.new()
	pc2.kind = 0
	pc2.color = Color(0, 0, 0, 1)
	pc2.opaque = true
	_emit(rt, P, I, pc2, 1.0, 6, st.clip, false, box)

func _makeClip(parent: Clip, P: PackedVector2Array, S: PackedInt32Array, evenodd: bool) -> Clip:
	var c := Clip.new()
	c.parent = parent
	if parent != null and parent.empty:
		c.empty = true
		return c
	if P.size() < 3 or S.is_empty():
		c.empty = true
		return c
	var box := DACanvasGeom.bbox(P)
	# axis-aligned rectangle -> analytic clip
	if S.size() == 1 and P.size() == 4 and (parent == null or parent.isRect):
		var ok := true
		for q in P:
			if not ((is_equal_approx(q.x, box.position.x) or is_equal_approx(q.x, box.end.x)) and (is_equal_approx(q.y, box.position.y) or is_equal_approx(q.y, box.end.y))):
				ok = false
				break
		if ok:
			c.isRect = true
			c.rect = box if parent == null else box.intersection(parent.rect)
			if c.rect.size.x <= 0.0 or c.rect.size.y <= 0.0:
				c.empty = true
			if _cpu:
				c.cpu = DACanvasCPU.clipMask(self, P, S, evenodd, parent)
			return c
	c.rect = box if parent == null else box.intersection(parent.rect)
	if c.rect.size.x <= 0.0 or c.rect.size.y <= 0.0:
		c.empty = true
		return c
	if parent != null and parent.isRect:
		# fold an analytic parent into the mask geometry via its rect
		var rp := parent.rect
		var pq := PackedVector2Array([rp.position, Vector2(rp.end.x, rp.position.y), rp.end, Vector2(rp.position.x, rp.end.y)])
		var inter: Array = []
		var np := S.size()
		var allConvex := not evenodd
		for k in np:
			var a := S[k]
			var b := S[k + 1] if k + 1 < np else P.size()
			var poly := P.slice(a, b)
			for r in Geometry2D.intersect_polygons(poly, pq):
				inter.append(r)
		var P2 := PackedVector2Array()
		var S2 := PackedInt32Array()
		for r in inter:
			S2.append(P2.size())
			P2.append_array(r)
		c.parent = null
		if P2.size() < 3:
			c.empty = true
			return c
		P = P2
		S = S2
	if _cpu:
		c.cpu = DACanvasCPU.clipMask(self, P, S, evenodd, c.parent)
		return c
	var tri := DACanvasGeom.triangulate(P, S, evenodd, true)
	c.P = tri[0]
	c.I = tri[1]
	return c

# Text (fill or stroke) through the path pipeline.
func _text(st: St, text: String, x: float, y: float, maxWidth, isStroke: bool) -> void:
	if text == "" or st.globalAlpha <= 0.0:
		return
	var sp: DACanvasText.Spec = DACanvasText.resolve(st.font)
	if sp == null:
		sp = DACanvasText.resolve("10px sans-serif")
	text = text.replace("\n", " ").replace("\t", " ").replace("\r", " ").replace("\f", " ")
	var px := sp.px
	var k := px / DACanvasText.REF
	var sh := DACanvasText.shape(sp, text)
	var spRef := st.letterPx / k if k > 0.0 else 0.0
	var width := sh.width * k + st.letterPx * sh.nchars
	var hs := 1.0
	if maxWidth != null:
		var mw := float(maxWidth)
		if mw <= 0.0 or not is_finite(mw):
			return
		if width > mw:
			hs = mw / width
	var ax := _alignOffset(st, width * hs)
	var by := DACanvasText.baselineOffset(sp, px, st.textBaseline)
	var skew := -0.25 if sp.synthItalic else 0.0
	var T := st.xf * Transform2D(Vector2(k * hs, 0.0), Vector2(skew * k * hs, k), Vector2(x + ax, y + by))
	if _cpu:
		if isStroke:
			var lwR := st.lineWidth / k
			var g0 := DACanvasText.strokeGeo(sh, spRef, lwR, _capI(st), _joinI(st), st.miterLimit)
			var paint0 := _paint(st.strokeColor, st)
			if paint0 != null:
				DACanvasCPU.fill(self, st, T * (g0[0] as PackedVector2Array), g0[1], false, paint0)
		else:
			var g1 := DACanvasText.polyGeo(sh, spRef)
			var paint1 := _paint(st.fillColor, st)
			if paint1 != null:
				DACanvasCPU.fill(self, st, T * (g1[0] as PackedVector2Array), g1[1], false, paint1)
				if sp.synthBold > 0.0:
					var gb := DACanvasText.strokeGeo(sh, spRef, sp.synthBold * DACanvasText.REF, 1, 1, 4.0)
					DACanvasCPU.fill(self, st, T * (gb[0] as PackedVector2Array), gb[1], false, paint1)
		return
	if st.clip != null and st.clip.empty:
		return
	if isStroke:
		var lwRef := st.lineWidth / k
		var g := DACanvasText.strokeGeo(sh, spRef, lwRef, _capI(st), _joinI(st), st.miterLimit)
		var Pd := T * (g[0] as PackedVector2Array)
		if (g[1] as PackedInt32Array).is_empty():
			return
		var paint := _paint(st.strokeColor, st)
		if paint == null:
			return
		var tri := DACanvasGeom.fanAll(Pd, g[1])
		_gpuOp(st, tri[0], tri[1], paint, true, DACanvasGeom.bbox(Pd))
	else:
		var m := DACanvasText.fillMesh(sh, spRef)
		var Pf := T * (m[0] as PackedVector2Array)
		if Pf.is_empty():
			return
		var paintF := _paint(st.fillColor, st)
		if paintF == null:
			return
		if sp.synthBold > 0.0:
			var gb2 := DACanvasText.strokeGeo(sh, spRef, sp.synthBold * DACanvasText.REF, 1, 1, 4.0)
			var Pb := T * (gb2[0] as PackedVector2Array)
			var P2 := Pf.duplicate()
			var I2 := (m[1] as PackedInt32Array).duplicate()
			var fb := DACanvasGeom.fanAll(Pb, gb2[1])
			var base := P2.size()
			P2.append_array(Pb)
			for t in (fb[1] as PackedInt32Array):
				I2.append(base + t)
			_gpuOp(st, P2, I2, paintF, true, DACanvasGeom.bbox(P2))
			return
		_gpuOp(st, Pf, m[1], paintF, false, DACanvasGeom.bbox(Pf))

static func _capI(st: St) -> int:
	return 0 if st.lineCap == "butt" else (1 if st.lineCap == "round" else 2)

static func _joinI(st: St) -> int:
	return 0 if st.lineJoin == "miter" else (1 if st.lineJoin == "round" else 2)

func _alignOffset(st: St, width: float) -> float:
	var al := st.textAlign
	var rtl := st.direction == "rtl"
	if al == "start":
		al = "right" if rtl else "left"
	elif al == "end":
		al = "left" if rtl else "right"
	if al == "center":
		return -width * 0.5
	if al == "right":
		return -width
	return 0.0

func _measure(st: St, text: String) -> Dictionary:
	var sp: DACanvasText.Spec = DACanvasText.resolve(st.font)
	if sp == null:
		sp = DACanvasText.resolve("10px sans-serif")
	text = text.replace("\n", " ").replace("\t", " ")
	var px := sp.px
	var k := px / DACanvasText.REF
	var sh := DACanvasText.shape(sp, text)
	var spRef := st.letterPx / k if k > 0.0 else 0.0
	var width := sh.width * k + st.letterPx * sh.nchars
	var ax := _alignOffset(st, width)
	var by := DACanvasText.baselineOffset(sp, px, st.textBaseline)
	var ink := DACanvasText.inkBox(sh, spRef)
	var emA := roundf(sp.emAsc * px * 64.0) / 64.0
	return {
		"width": width,
		"actualBoundingBoxLeft": -(ink.position.x * k + ax) if not sh.glyphs.is_empty() else -ax,
		"actualBoundingBoxRight": (ink.end.x * k + ax) if not sh.glyphs.is_empty() else ax,
		"actualBoundingBoxAscent": (-ink.position.y * k - by) if not sh.glyphs.is_empty() else -by,
		"actualBoundingBoxDescent": (ink.end.y * k + by) if not sh.glyphs.is_empty() else by,
		"fontBoundingBoxAscent": roundf(sp.asc * px) - by,
		"fontBoundingBoxDescent": roundf(sp.desc * px) + by,
		"emHeightAscent": emA - by,
		"emHeightDescent": px - emA + by,
		"alphabeticBaseline": -by,
		"hangingBaseline": roundf(sp.asc * px) * 0.8 - by,
		"ideographicBaseline": -roundf(sp.desc * px) - by,
	}

func _drawImage(st: St, img, a: float, b: float, c, d, e, f, g, h) -> void:
	var src := _imageSource(img)
	if src.is_empty():
		return
	var iw: float = src[4]
	var ih: float = src[5]
	var sx := 0.0
	var sy := 0.0
	var sw := iw
	var sh := ih
	var dx := a
	var dy := b
	var dw := iw
	var dh := ih
	if c != null and e == null:
		dw = float(c)
		dh = float(d)
	elif e != null:
		sx = a; sy = b; sw = float(c); sh = float(d)
		dx = float(e); dy = float(f); dw = float(g); dh = float(h)
	if sw == 0.0 or sh == 0.0 or dw == 0.0 or dh == 0.0:
		return
	# normalise negative sizes
	if sw < 0.0:
		sx += sw; sw = -sw
	if sh < 0.0:
		sy += sh; sh = -sh
	if dw < 0.0:
		dx += dw; dw = -dw
	if dh < 0.0:
		dy += dh; dh = -dh
	# clip the source rect to the image, adjusting the destination
	var kx := dw / sw
	var ky := dh / sh
	if sx < 0.0:
		dx -= sx * kx; dw += sx * kx; sw += sx; sx = 0.0
	if sy < 0.0:
		dy -= sy * ky; dh += sy * ky; sh += sy; sy = 0.0
	if sx + sw > iw:
		var cut := sx + sw - iw
		sw -= cut; dw -= cut * kx
	if sy + sh > ih:
		var cut2 := sy + sh - ih
		sh -= cut2; dh -= cut2 * ky
	if sw <= 0.0 or sh <= 0.0 or dw <= 0.0 or dh <= 0.0:
		return
	var xf := st.xf
	var P := PackedVector2Array([xf * Vector2(dx, dy), xf * Vector2(dx + dw, dy), xf * Vector2(dx + dw, dy + dh), xf * Vector2(dx, dy + dh)])
	var p := Paint.new()
	p.kind = 1
	p.tex = src[0]
	p.premul = src[1]
	p.dep = src[2]
	p.keep = src[3]
	p.srcW = int(iw)
	p.srcH = int(ih)
	p.smooth = st.smoothing
	p.cm = st.flt.cm
	p.set_meta("src", img)
	# device -> uv
	var toSrc := Transform2D(Vector2(sw / dw / iw, 0.0), Vector2(0.0, sh / dh / ih), Vector2((sx - dx * sw / dw) / iw, (sy - dy * sh / dh) / ih))
	p.xf = toSrc * xf.affine_inverse()
	if st.globalAlpha <= 0.0:
		return
	if st.clip != null and st.clip.empty:
		return
	if _cpu:
		DACanvasCPU.fill(self, st, P, PackedInt32Array([0]), false, p)
		return
	_gpuOp(st, P, PackedInt32Array([0, 1, 2, 0, 2, 3]), p, false, DACanvasGeom.bbox(P))

func _getImageData(sx: int, sy: int, sw: int, sh: int) -> Dictionary:
	if sw < 0:
		sx += sw; sw = -sw
	if sh < 0:
		sy += sh; sh = -sh
	var out := PackedByteArray()
	out.resize(maxi(0, sw * sh * 4))
	if sw <= 0 or sh <= 0:
		return {"width": sw, "height": sh, "data": out, "colorSpace": "srgb"}
	if _cpu:
		for j in sh:
			var yy := sy + j
			if yy < 0 or yy >= _h:
				continue
			for i in sw:
				var xx := sx + i
				if xx < 0 or xx >= _w:
					continue
				var o := (yy * _w + xx) * 4
				var a := _px[o + 3]
				if a <= 0.0:
					continue
				var q := (j * sw + i) * 4
				out[q] = clampi(int(_px[o] / a * 255.0 + 0.5), 0, 255)
				out[q + 1] = clampi(int(_px[o + 1] / a * 255.0 + 0.5), 0, 255)
				out[q + 2] = clampi(int(_px[o + 2] / a * 255.0 + 0.5), 0, 255)
				out[q + 3] = clampi(int(a * 255.0 + 0.5), 0, 255)
		return {"width": sw, "height": sh, "data": out, "colorSpace": "srgb"}
	var img := toImage()
	var full := Rect2i(0, 0, img.get_width(), img.get_height())
	var want := Rect2i(sx, sy, sw, sh)
	var inter := full.intersection(want)
	if inter.size.x > 0 and inter.size.y > 0:
		var reg := img.get_region(inter)
		var data := reg.get_data()
		for j in inter.size.y:
			var srcOff := j * inter.size.x * 4
			var dstOff := ((inter.position.y - sy + j) * sw + (inter.position.x - sx)) * 4
			for i in inter.size.x * 4:
				out[dstOff + i] = data[srcOff + i]
	return {"width": sw, "height": sh, "data": out, "colorSpace": "srgb"}

func _putImageData(img: Dictionary, dx: int, dy: int, dirtyX, dirtyY, dirtyW, dirtyH) -> void:
	var iw := int(img.width)
	var ih := int(img.height)
	var data: PackedByteArray = img.data
	var rx := 0
	var ry := 0
	var rw := iw
	var rh := ih
	if dirtyX != null:
		rx = int(dirtyX); ry = int(dirtyY); rw = int(dirtyW); rh = int(dirtyH)
		if rw < 0:
			rx += rw; rw = -rw
		if rh < 0:
			ry += rh; rh = -rh
	var r := Rect2i(rx, ry, rw, rh).intersection(Rect2i(0, 0, iw, ih))
	# clip to the canvas
	r = r.intersection(Rect2i(-dx, -dy, _w, _h))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	if _cpu:
		for j in r.size.y:
			for i in r.size.x:
				var sxp := r.position.x + i
				var syp := r.position.y + j
				var so := (syp * iw + sxp) * 4
				var o := ((syp + dy) * _w + (sxp + dx)) * 4
				var a := data[so + 3] / 255.0
				_px[o] = data[so] / 255.0 * a
				_px[o + 1] = data[so + 1] / 255.0 * a
				_px[o + 2] = data[so + 2] / 255.0 * a
				_px[o + 3] = a
		_hasContent = true
		_cpuDirty = true
		DACanvasGPU.markDirty(self)
		return
	var im := Image.create_from_data(iw, ih, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(im)
	var full := r.position.x + dx <= 0 and r.position.y + dy <= 0 and r.end.x + dx >= _w and r.end.y + dy >= _h
	var rt = _target(full)
	rt.keep.append(tex)
	DACanvasGPU.addCopy(rt, Rect2(r.position.x + dx, r.position.y + dy, r.size.x, r.size.y), tex.get_rid(), Rect2(r.position, r.size), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)

# Point in polygons (nonzero / evenodd), device space.
static func _pointIn(P: PackedVector2Array, S: PackedInt32Array, q: Vector2, evenodd: bool) -> bool:
	var w := 0
	var np := S.size()
	for k in np:
		var a := S[k]
		var b := S[k + 1] if k + 1 < np else P.size()
		var prev := P[b - 1]
		for i in range(a, b):
			var cur := P[i]
			if prev.y <= q.y:
				if cur.y > q.y and (cur - prev).cross(q - prev) > 0.0:
					w += 1
			elif cur.y <= q.y and (cur - prev).cross(q - prev) < 0.0:
				w -= 1
			prev = cur
	return (w & 1) == 1 if evenodd else w != 0
