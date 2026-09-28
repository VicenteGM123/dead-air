# DEAD AIR — commercial overlay (port of src/ui/commercial.js; GDD §10.3, §11 INSTANT REPLAY, §14 "Commercial bezel" /
# "Replay bug"). Owned by the sponsors agent. One full-screen 2D canvas (a CanvasLayer at layer 15, the JS z-index:
# over the HUD (10), under the menus (20)), drawn only while something shows; the 3D picture shows through its
# transparent parts.
#
#   COMMERCIAL  the wood-grain 1977 console-TV bezel framing the centered 4:3 picture that render.setCameraOverride
#               draws (same maths: viewport()), chrome screen trim with rounded CRT corners, glass glare, a speaker
#               grille on the left panel and two knobs on the right one (the channel knob clicks on the cut), the
#               one-frame white flash of the hard cut, a VCR OSD ("II" pause / "◀◀" rewind pictograms), VHS
#               tracking lines, the Jump Cut tape splice (white frame + a diagonal splice line), the logo card
#               sliding in on its starburst (cards sponsor_logo_<perkId>) behind CRT scanlines, and the 5-point
#               STAR WIPE: a star hole growing out of the product reveals the gameplay camera, bezel and all.
#   REPLAY      the sports-replay wipe (a spinning WZTV "13" roundel sweeping over diagonal team-colour bars) and the
#               rewind's VHS tracking band + streaks over the whole screen. The "◀◀" bug itself is the HUD's.
#
# API
#   getOverlay() -> CommercialOverlay (singleton; the CanvasLayer is created on first use)
#   overlay.viewport(aspect = 4/3) -> { x, y, w, h } canvas px of the picture rectangle
#   overlay.draw(state)   call every frame while active     overlay.clear()   hide (drops the canvas content)
#   overlay.innerSize() -> Vector2   the screen size in canvas px (the JS innerWidth / innerHeight)
#   state = {
#     mode: 'commercial' | 'replay',  t (s, real),  perkId,
#     flash 0..1 (white over everything),  cut 0..1 (the channel knob's click),
#     osd: null | 'pause' | 'rew' | 'play',  tracking 0..1 (VHS tracking noise),  splice 0..1 (jump-cut splice),
#     card: -1 | 0..1 (logo card slide-in progress; 1 = settled),
#     cardHold: 0..1 (progress through the held card after it settled: slow push-in + one sheen sweep),
#     star: null | { x, y, r, rot }  (canvas px; the hole reveals the game; r = outer radius),
#     wipe: -1 | 0..1 (replay roundel wipe progress),  bezel: 0..1 (commercial frame opacity, default 1),
#   }
# Nothing here touches the game state; sponsors.gd / perks.gd drive it.
# Drawing is the JS canvas code line by line on the Canvas 2D emulation (scripts/gfx/canvas2d.gd, DACanvas).
# canvasTex(w, h, draw) is the shared "draw a canvas texture once" helper of the sponsors files.
# CSS px -> canvas units of the 1920x1080 stretch stage (the layout is relative to the 4:3 picture, like the JS);
# devicePixelRatio -> window pixels per canvas unit (capped at 1.5 like the JS).
extends RefCounted

const CANVAS_PATH := "res://scripts/gfx/canvas2d.gd"
const LAYER := 15
const TAU := PI * 2.0
const FONTS := {
	"hud": '"Titan One", "Arial Black", sans-serif',
	"tape": '"VT323", "Courier New", monospace',
	"logo": '"Shrikhand", "Georgia", serif',
	"sign": '"Bungee", "Arial Black", sans-serif',
}

static func _clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func _easeOutBack(x: float, k: float = 1.9) -> float:
	return 1.0 + (k + 1.0) * pow(x - 1.0, 3.0) + k * pow(x - 1.0, 2.0)

static func _smooth(a: float, b: float, x: float) -> float:
	var t := _clamp01((x - a) / (b - a))
	return t * t * (3.0 - 2.0 * t)

static func _round(x: float) -> int:
	return int(floorf(x + 0.5))

# Seeded random for the procedural textures (deterministic look): the JS rng() is mulberry32.
static func rng(seed: int) -> Callable:
	return Rng.mulberry32(seed)

static var _canvasScript = null
static func _C():
	if _canvasScript == null and ResourceLoader.exists(CANVAS_PATH):
		_canvasScript = load(CANVAS_PATH)
	return _canvasScript

# document.createElement('canvas') with width/height (null when the Canvas 2D emulation is missing).
static func canvas(w: float, h: float):
	var C = _C()
	if C == null:
		return null
	return C.new(maxi(1, _round(w)), maxi(1, _round(h)))

# Draws a canvas once (draw(ctx, w, h)) and returns its texture (null without the Canvas 2D emulation).
static func canvasTex(w: int, h: int, draw: Callable):
	var c = canvas(w, h)
	if c == null:
		return null
	var ctx = c.getContext("2d")
	draw.call(ctx, w, h)
	return c.texture

static func roundRect(ctx, x: float, y: float, w: float, h: float, r: float) -> void:
	r = minf(r, minf(w / 2.0, h / 2.0))
	ctx.moveTo(x + r, y)
	ctx.arcTo(x + w, y, x + w, y + h, r)
	ctx.arcTo(x + w, y + h, x, y + h, r)
	ctx.arcTo(x, y + h, x, y, r)
	ctx.arcTo(x, y, x + w, y, r)
	ctx.closePath()

# CRT tube opening: a rounded rectangle whose sides bulge a little (a 1970s picture tube, not a flat box).
static func tubePath(ctx, x: float, y: float, w: float, h: float, r: float, bulge: float) -> void:
	var bx := w * bulge
	var by := h * bulge
	ctx.moveTo(x + r, y)
	ctx.quadraticCurveTo(x + w / 2.0, y - by, x + w - r, y)
	ctx.quadraticCurveTo(x + w, y, x + w, y + r)
	ctx.quadraticCurveTo(x + w + bx, y + h / 2.0, x + w, y + h - r)
	ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
	ctx.quadraticCurveTo(x + w / 2.0, y + h + by, x + r, y + h)
	ctx.quadraticCurveTo(x, y + h, x, y + h - r)
	ctx.quadraticCurveTo(x - bx, y + h / 2.0, x, y + r)
	ctx.quadraticCurveTo(x, y, x + r, y)
	ctx.closePath()

static func starPath(ctx, cx: float, cy: float, r: float, rot: float, inner: float = 0.42) -> void:
	for i in 10:
		var a := rot - PI / 2.0 + (i * PI) / 5.0
		var rr := r * inner if i % 2 else r
		var x := cx + cos(a) * rr
		var y := cy + sin(a) * rr
		if i:
			ctx.lineTo(x, y)
		else:
			ctx.moveTo(x, y)
	ctx.closePath()

# ------------------------------------------------------------------------------------------ procedural textures
# Walnut veneer tile: warm base, long flowing grain lines, darker figure bands and pores (repeats on both axes).
static var _woodTile = null
static func woodTile():
	if _woodTile != null:
		return _woodTile
	var W := 512
	var H := 512
	var c = canvas(W, H)
	if c == null:
		return null
	var ctx = c.getContext("2d")
	var r := rng(1977)
	var g = ctx.createLinearGradient(0, 0, W, 0)
	g.addColorStop(0, "#6A3A1C")
	g.addColorStop(0.35, "#7E4722")
	g.addColorStop(0.62, "#6E3D1E")
	g.addColorStop(1, "#6A3A1C")
	ctx.fillStyle = g
	ctx.fillRect(0, 0, W, H)
	# figure bands (wide soft darker/lighter stripes along the grain, which runs horizontally)
	for i in 14:
		var y0: float = r.call() * H
		var th: float = 10.0 + r.call() * 40.0
		var a: float = 0.05 + r.call() * 0.1
		ctx.fillStyle = ("rgba(40,16,4,%s)" % _num(a)) if r.call() < 0.5 else ("rgba(190,110,50,%s)" % _num(a * 0.8))
		for oy in [-H, 0, H]:
			ctx.beginPath()
			var x := 0
			while x <= W:
				var y: float = y0 + oy + sin((float(x) / W) * TAU * 2.0 + i) * 6.0 + sin((float(x) / W) * TAU * 5.0 + i * 3) * 2.0
				if x:
					ctx.lineTo(x, y)
				else:
					ctx.moveTo(x, y)
				x += 16
			x = W
			while x >= 0:
				var y: float = y0 + oy + th + sin((float(x) / W) * TAU * 2.0 + i + 0.7) * 6.0
				ctx.lineTo(x, y)
				x -= 16
			ctx.closePath()
			ctx.fill()
	# fine grain lines (periodic in x so the tile repeats)
	for i in 150:
		var y0: float = r.call() * H
		var amp: float = 2.0 + r.call() * 7.0
		var f: float = 1.0 + floorf(r.call() * 3.0)
		var ph: float = r.call() * TAU
		ctx.strokeStyle = ("rgba(35,14,4,%s)" % _num(0.12 + r.call() * 0.22)) if r.call() < 0.7 else ("rgba(210,140,80,%s)" % _num(0.06 + r.call() * 0.1))
		ctx.lineWidth = 0.6 + r.call() * 1.3
		for oy in [-H, 0, H]:
			ctx.beginPath()
			var x := 0
			while x <= W:
				var y: float = y0 + oy + sin((float(x) / W) * TAU * f + ph) * amp + sin((float(x) / W) * TAU * (f + 3.0) + ph * 2.0) * amp * 0.25
				if x:
					ctx.lineTo(x, y)
				else:
					ctx.moveTo(x, y)
				x += 8
			ctx.stroke()
	# pores
	for i in 2200:
		ctx.fillStyle = "rgba(30,10,2,%s)" % _num(0.15 + r.call() * 0.25)
		ctx.fillRect(r.call() * W, r.call() * H, 1.0 + r.call() * 3.0, 0.8 + r.call() * 0.8)
	_woodTile = c
	return c

# Speaker cloth: dark brown woven fabric with gold threads.
static var _clothTile = null
static func clothTile():
	if _clothTile != null:
		return _clothTile
	var W := 64
	var H := 64
	var c = canvas(W, H)
	if c == null:
		return null
	var ctx = c.getContext("2d")
	var r := rng(413)
	ctx.fillStyle = "#3A2414"
	ctx.fillRect(0, 0, W, H)
	var y := 0
	while y < H:
		ctx.fillStyle = "rgba(120,80,40,0.35)" if y % 8 else "rgba(200,150,70,0.28)"
		ctx.fillRect(0, y, W, 2)
		y += 4
	var x := 0
	while x < W:
		ctx.fillStyle = "rgba(20,10,4,0.35)"
		ctx.fillRect(x, 0, 1.5, H)
		x += 4
	for i in 90:
		ctx.fillStyle = "rgba(230,180,90,%s)" % _num(r.call() * 0.18)
		ctx.fillRect(r.call() * W, r.call() * H, 1, 1)
	_clothTile = c
	return c

# VHS noise strip (white speckle + streaks), stretched over the tracking band.
static var _noise = null
static func noiseStrip():
	if _noise != null:
		return _noise
	var W := 256
	var H := 48
	var c = canvas(W, H)
	if c == null:
		return null
	var ctx = c.getContext("2d")
	var r := rng(88)
	var img = ctx.createImageData(W, H)
	var data := PackedByteArray()
	data.resize(W * H * 4)
	for y in H:
		var row := 0.4 + 0.6 * sin((float(y) / H) * PI)
		for x in W:
			var v: float = 150.0 + r.call() * 105.0 if r.call() < 0.5 * row else r.call() * 40.0
			var i := (y * W + x) * 4
			# Uint8ClampedArray stores: clamp + round half to even of the float
			data[i] = _u8(v)
			data[i + 1] = _u8(v)
			data[i + 2] = _u8(v + 10.0)
			data[i + 3] = 220 if r.call() < 0.75 * row else 40
	img.data = data
	ctx.putImageData(img, 0, 0)
	_noise = c
	return c

static func _u8(v: float) -> int:
	# Uint8ClampedArray store: clamp, round to nearest, ties to even
	if v <= 0.0:
		return 0
	if v >= 255.0:
		return 255
	var f := floorf(v)
	var d := v - f
	if d > 0.5:
		return int(f) + 1
	if d < 0.5:
		return int(f)
	return int(f) + (int(f) & 1)

# Number -> string inside a CSS colour (the JS template-string form).
static func _num(v: float) -> String:
	return str(v)

# ------------------------------------------------------------------------------------------ the overlay
class CommercialOverlay extends RefCounted:
	var el = null            # the canvas (DACanvas)
	var ctx = null
	var layer: CanvasLayer = null
	var rect: TextureRect = null
	var visible := false
	var _w := 0.0
	var _h := 0.0
	var _dpr := 1.0
	var _bezel = null          # cached bezel canvas for the current size
	var _layout = null
	var _card = null           # cached logo card canvas { id, w, h, c }
	var _rand: Callable
	var CO                     # the commercial.gd script (static helpers)

	func _init() -> void:
		CO = load("res://scripts/ui/commercial.gd")
		_rand = CO.rng(7)

	func _ensure() -> void:
		if layer != null and is_instance_valid(layer):
			return
		var host: Node = DAGame.inst
		if host == null:
			var ml = Engine.get_main_loop()
			host = ml.root if ml is SceneTree else null
		layer = CanvasLayer.new()
		layer.name = "deadair-commercial"
		layer.layer = 15
		layer.visible = false
		rect = TextureRect.new()
		rect.name = "picture"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.add_child(rect)
		if host != null:
			host.add_child(layer)

	# innerWidth / innerHeight (canvas px of the stretch stage).
	func innerSize() -> Vector2:
		var ml = Engine.get_main_loop()
		if ml is SceneTree and (ml as SceneTree).root != null:
			var s: Vector2 = (ml as SceneTree).root.get_visible_rect().size
			return Vector2(maxf(1.0, s.x), maxf(1.0, s.y))
		return Vector2(1920, 1080)

	# Picture rectangle of a centered `aspect` viewport (render.setCameraOverride uses the same rule).
	func viewport(aspect: float = 4.0 / 3.0) -> Dictionary:
		var S := innerSize()
		var W := S.x
		var H := S.y
		var screen := W / H
		if aspect < screen:
			var w := H * aspect
			return {"x": (W - w) / 2.0, "y": 0.0, "w": w, "h": H}
		var h := W / aspect
		return {"x": 0.0, "y": (H - h) / 2.0, "w": W, "h": h}

	func _resize() -> void:
		var S := innerSize()
		var W := S.x
		var H := S.y
		var winH := float(DisplayServer.window_get_size().y) if DisplayServer.get_name() != "headless" else H
		var dpr := minf(maxf(winH / H, 0.01), 1.5)
		if W == _w and H == _h and dpr == _dpr and _bezel != null and el != null:
			return
		_w = W
		_h = H
		_dpr = dpr
		el = CO.canvas(W * dpr, H * dpr)
		if el == null:
			return
		ctx = el.getContext("2d")
		rect.texture = el.texture
		_layout = _makeLayout(W, H)
		_bezel = _buildBezel(W, H, dpr, _layout)
		_card = null

	# Screen opening (a little inside the 4:3 picture so the frame overlaps its edges), side panels, knobs.
	func _makeLayout(W: float, H: float) -> Dictionary:
		var v := viewport(4.0 / 3.0)
		var u: float = minf(v.h, v.w * 0.75) / 1080.0             # reference unit: 1080 p picture height
		var mY := 26.0 * u
		var mX := 30.0 * u
		var open := {"x": v.x + mX, "y": v.y + mY, "w": v.w - 2.0 * mX, "h": v.h - 2.0 * mY, "r": 96.0 * u}
		var trim := 16.0 * u
		var side: float = v.x                                        # free width on each side of the picture
		var lay := {"v": v, "u": u, "open": open, "trim": trim, "side": side, "knobs": [], "grille": null, "plate": null, "panel": null}
		var kr := minf(side * 0.36, 78.0 * u * 1.25)
		if side > 70.0 * u:
			var cx := W - side / 2.0
			lay.knobs.append({"x": cx, "y": H * 0.34, "r": kr, "kind": "channel"})
			lay.knobs.append({"x": cx, "y": H * 0.34 + kr * 2.7, "r": kr * 0.72, "kind": "volume"})
			lay.panel = {"x": W - side + side * 0.12, "y": H * 0.1, "w": side * 0.76, "h": H * 0.8}
			lay.grille = {"x": side * 0.12, "y": H * 0.1, "w": side * 0.76, "h": H * 0.8}
		else:
			# narrow screens: small knobs sit on the bottom-right of the frame
			var r0 := maxf(18.0, 34.0 * u)
			lay.knobs.append({"x": v.x + v.w - r0 * 3.6, "y": v.y + v.h - r0 * 1.1, "r": r0, "kind": "channel"})
			lay.knobs.append({"x": v.x + v.w - r0 * 1.4, "y": v.y + v.h - r0 * 1.1, "r": r0 * 0.75, "kind": "volume"})
		lay.plate = {"x": v.x + v.w / 2.0, "y": open.y + open.h + (v.y + v.h - (open.y + open.h)) * 0.5, "s": maxf(9.0, 15.0 * u)}
		return lay

	func _buildBezel(W: float, H: float, dpr: float, L: Dictionary):
		var c = CO.canvas(W * dpr, H * dpr)
		if c == null:
			return null
		var ctx = c.getContext("2d")
		ctx.scale(dpr, dpr)
		var open: Dictionary = L.open
		var trim: float = L.trim
		var u: float = L.u
		# walnut cabinet everywhere
		var pat = ctx.createPattern(CO.woodTile(), "repeat")
		var k := maxf(0.6, H / 900.0)
		if pat != null and pat.has_method("setTransform"):
			pat.setTransform(_scaleMatrix(k))
		ctx.fillStyle = pat
		ctx.fillRect(0, 0, W, H)
		# cabinet shading: darker toward the outer edges, warm sheen band across the top
		var g = ctx.createRadialGradient(W / 2.0, H * 0.45, minf(W, H) * 0.3, W / 2.0, H / 2.0, maxf(W, H) * 0.75)
		g.addColorStop(0, "rgba(0,0,0,0)")
		g.addColorStop(1, "rgba(20,6,0,0.55)")
		ctx.fillStyle = g
		ctx.fillRect(0, 0, W, H)
		g = ctx.createLinearGradient(0, 0, 0, H)
		g.addColorStop(0, "rgba(255,210,150,0.10)")
		g.addColorStop(0.12, "rgba(255,210,150,0)")
		g.addColorStop(0.88, "rgba(0,0,0,0)")
		g.addColorStop(1, "rgba(0,0,0,0.25)")
		ctx.fillStyle = g
		ctx.fillRect(0, 0, W, H)
		# side panels: speaker grille (left) and the control panel (right), both inset with a bevel
		if L.grille != null:
			var q: Dictionary = L.grille
			_inset(ctx, q.x, q.y, q.w, q.h, 14.0 * u)
			ctx.save()
			ctx.beginPath()
			CO.roundRect(ctx, q.x + 6.0 * u, q.y + 6.0 * u, q.w - 12.0 * u, q.h - 12.0 * u, 10.0 * u)
			ctx.clip()
			ctx.fillStyle = ctx.createPattern(CO.clothTile(), "repeat")
			ctx.fillRect(q.x, q.y, q.w, q.h)
			# vertical wooden slats over the cloth
			var n := 5
			var sw: float = (q.w - 12.0 * u) / (n * 2 - 1)
			for i in n:
				var x: float = q.x + 6.0 * u + i * sw * 2.0
				if i == 0:
					continue
				ctx.fillStyle = pat
				ctx.fillRect(x - sw, q.y, sw, q.h)
				var sg = ctx.createLinearGradient(x - sw, 0, x, 0)
				sg.addColorStop(0, "rgba(255,200,140,0.18)")
				sg.addColorStop(0.5, "rgba(0,0,0,0)")
				sg.addColorStop(1, "rgba(0,0,0,0.35)")
				ctx.fillStyle = sg
				ctx.fillRect(x - sw, q.y, sw, q.h)
			var vg = ctx.createLinearGradient(0, q.y, 0, q.y + q.h)
			vg.addColorStop(0, "rgba(0,0,0,0.35)")
			vg.addColorStop(0.2, "rgba(0,0,0,0)")
			vg.addColorStop(1, "rgba(0,0,0,0.3)")
			ctx.fillStyle = vg
			ctx.fillRect(q.x, q.y, q.w, q.h)
			ctx.restore()
		if L.panel != null:
			var q: Dictionary = L.panel
			_inset(ctx, q.x, q.y, q.w, q.h, 14.0 * u)
			ctx.save()
			ctx.beginPath()
			CO.roundRect(ctx, q.x + 6.0 * u, q.y + 6.0 * u, q.w - 12.0 * u, q.h - 12.0 * u, 10.0 * u)
			ctx.clip()
			var pg = ctx.createLinearGradient(q.x, 0, q.x + q.w, 0)
			pg.addColorStop(0, "#2A1D18")
			pg.addColorStop(0.5, "#3A2A22")
			pg.addColorStop(1, "#241814")
			ctx.fillStyle = pg
			ctx.fillRect(q.x, q.y, q.w, q.h)
			# brushed-aluminium strip with the channel numbers around the tuner knob
			ctx.restore()
			var kn: Dictionary = L.knobs[0]
			ctx.save()
			ctx.fillStyle = "#E8DCC0"
			ctx.font = "%dpx %s" % [CO._round(kn.r * 0.24), CO.FONTS.sign]
			ctx.textAlign = "center"
			ctx.textBaseline = "middle"
			var chans := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
			for i in chans.size():
				var ch: int = chans[i]
				var a := -PI * 0.8 + (float(i) / (chans.size() - 1)) * PI * 1.6 - PI / 2.0
				var rr: float = kn.r * 1.28
				ctx.fillStyle = "#FF6A4A" if ch == 13 else "#E8DCC0"
				ctx.fillText(str(ch), kn.x + cos(a) * rr, kn.y + sin(a) * rr)
			ctx.font = "%dpx %s" % [CO._round(kn.r * 0.2), CO.FONTS.sign]
			ctx.fillStyle = "rgba(232,220,192,0.8)"
			ctx.fillText("VHF", kn.x, kn.y + kn.r * 1.62)
			var k2: Dictionary = L.knobs[1]
			ctx.fillText("VOLUME", k2.x, k2.y + k2.r * 1.55)
			# tiny red power lamp
			ctx.beginPath()
			ctx.arc(k2.x, k2.y + k2.r * 2.3, maxf(3.0, 6.0 * u), 0, TAU)
			ctx.fillStyle = "#FF3B30"
			ctx.shadowColor = "#FF3B30"
			ctx.shadowBlur = 12.0 * u
			ctx.fill()
			ctx.restore()
		# chrome trim ring around the tube
		ctx.save()
		ctx.beginPath()
		CO.tubePath(ctx, open.x - trim, open.y - trim, open.w + trim * 2.0, open.h + trim * 2.0, open.r + trim, 0.012)
		var tg = ctx.createLinearGradient(0, open.y - trim, 0, open.y + open.h + trim)
		tg.addColorStop(0, "#F4F0E6")
		tg.addColorStop(0.18, "#9A9A98")
		tg.addColorStop(0.5, "#D8D6D0")
		tg.addColorStop(0.82, "#7A7874")
		tg.addColorStop(1, "#E8E4DA")
		ctx.fillStyle = tg
		ctx.shadowColor = "rgba(0,0,0,0.6)"
		ctx.shadowBlur = 18.0 * u
		ctx.shadowOffsetY = 4.0 * u
		ctx.fill()
		ctx.restore()
		# black rubber gasket between trim and glass
		ctx.beginPath()
		CO.tubePath(ctx, open.x - trim * 0.35, open.y - trim * 0.35, open.w + trim * 0.7, open.h + trim * 0.7, open.r + trim * 0.35, 0.012)
		ctx.fillStyle = "#141014"
		ctx.fill()
		# cut the picture opening
		ctx.save()
		ctx.globalCompositeOperation = "destination-out"
		ctx.beginPath()
		CO.tubePath(ctx, open.x, open.y, open.w, open.h, open.r, 0.012)
		ctx.fill()
		ctx.restore()
		# inner glass edge shadow + glare (inside the opening, low alpha so the picture reads)
		ctx.save()
		ctx.beginPath()
		CO.tubePath(ctx, open.x, open.y, open.w, open.h, open.r, 0.012)
		ctx.clip()
		ctx.lineWidth = 40.0 * u
		ctx.strokeStyle = "rgba(0,0,0,0.45)"
		ctx.filter = "blur(%dpx)" % CO._round(14.0 * u)
		ctx.beginPath()
		CO.tubePath(ctx, open.x, open.y, open.w, open.h, open.r, 0.012)
		ctx.stroke()
		ctx.filter = "none"
		var gl = ctx.createLinearGradient(open.x, open.y, open.x + open.w * 0.55, open.y + open.h * 0.7)
		gl.addColorStop(0, "rgba(255,255,255,0.16)")
		gl.addColorStop(0.35, "rgba(255,255,255,0.05)")
		gl.addColorStop(0.36, "rgba(255,255,255,0)")
		ctx.fillStyle = gl
		ctx.fillRect(open.x, open.y, open.w, open.h)
		ctx.restore()
		# brand plate under the tube
		var P: Dictionary = L.plate
		ctx.save()
		ctx.font = "%dpx %s" % [CO._round(P.s), CO.FONTS.sign]
		ctx.textAlign = "center"
		ctx.textBaseline = "middle"
		var label := "SOLID STATE  ✦  COLOR"
		var tw: float = ctx.measureText(label).width
		ctx.beginPath()
		CO.roundRect(ctx, P.x - tw / 2.0 - P.s, P.y - P.s * 0.8, tw + P.s * 2.0, P.s * 1.6, P.s * 0.4)
		var bg = ctx.createLinearGradient(0, P.y - P.s, 0, P.y + P.s)
		bg.addColorStop(0, "#E8D9A8")
		bg.addColorStop(0.5, "#B8914A")
		bg.addColorStop(1, "#E0C888")
		ctx.fillStyle = bg
		ctx.fill()
		ctx.fillStyle = "#3A2410"
		ctx.fillText(label, P.x, P.y + P.s * 0.05)
		ctx.restore()
		return c

	# new DOMMatrix().scale(k, k) for CanvasPattern.setTransform (the emulation's DOMMatrix when it has one).
	func _scaleMatrix(k: float):
		var C = CO._C()
		var cm: Dictionary = C.get_script_constant_map() if C != null else {}
		if cm.has("DOMMatrix"):
			var m = cm.DOMMatrix.new()
			return m.scale(k, k) if m.has_method("scale") else m
		return Transform2D(Vector2(k, 0), Vector2(0, k), Vector2.ZERO)

	# Recessed panel: dark inner shadow + light lower-right lip.
	func _inset(ctx, x: float, y: float, w: float, h: float, r: float) -> void:
		ctx.save()
		ctx.beginPath()
		CO.roundRect(ctx, x, y, w, h, r)
		ctx.fillStyle = "rgba(20,8,2,0.55)"
		ctx.fill()
		ctx.lineWidth = 3
		ctx.strokeStyle = "rgba(255,200,140,0.22)"
		ctx.stroke()
		ctx.restore()

	func _knob(ctx, k: Dictionary, angle: float) -> void:
		var x: float = k.x
		var y: float = k.y
		var r: float = k.r
		ctx.save()
		# drop shadow + skirt
		ctx.beginPath()
		ctx.arc(x, y + r * 0.08, r * 1.04, 0, TAU)
		ctx.fillStyle = "rgba(0,0,0,0.45)"
		ctx.fill()
		var g = ctx.createRadialGradient(x - r * 0.3, y - r * 0.35, r * 0.1, x, y, r)
		g.addColorStop(0, "#6A4A34")
		g.addColorStop(0.7, "#3A2418")
		g.addColorStop(1, "#1E120C")
		ctx.beginPath()
		ctx.arc(x, y, r, 0, TAU)
		ctx.fillStyle = g
		ctx.fill()
		# knurled ridges
		ctx.translate(x, y)
		ctx.rotate(angle)
		ctx.strokeStyle = "rgba(0,0,0,0.5)"
		ctx.lineWidth = maxf(1.0, r * 0.035)
		for i in 28:
			var a := (i / 28.0) * TAU
			ctx.beginPath()
			ctx.moveTo(cos(a) * r * 0.82, sin(a) * r * 0.82)
			ctx.lineTo(cos(a) * r * 0.99, sin(a) * r * 0.99)
			ctx.stroke()
		# chrome cap
		g = ctx.createLinearGradient(-r * 0.6, -r * 0.6, r * 0.6, r * 0.6)
		g.addColorStop(0, "#FFFFFF")
		g.addColorStop(0.4, "#B8B8B4")
		g.addColorStop(0.6, "#8A8A86")
		g.addColorStop(1, "#E8E8E0")
		ctx.beginPath()
		ctx.arc(0, 0, r * 0.62, 0, TAU)
		ctx.fillStyle = g
		ctx.fill()
		# pointer
		ctx.fillStyle = "#FF5A3C"
		ctx.beginPath()
		CO.roundRect(ctx, -r * 0.07, -r * 0.95, r * 0.14, r * 0.5, r * 0.07)
		ctx.fill()
		ctx.restore()

	func _cardCanvas(perkId: String, w: float, h: float):
		var id := "sponsor_logo_" + perkId
		if _card != null and _card.id == id and _card.w == CO._round(w) and _card.h == CO._round(h):
			return _card.c
		var c = CO.canvas(w, h)
		if c == null:
			return null
		var ctx = c.getContext("2d")
		var cards = DAGame.inst.cards if DAGame.inst != null else null
		if cards != null and (cards is Object and cards.has_method("drawTo")):
			cards.drawTo(ctx, id, c.width, c.height, 0)
		elif cards is Dictionary and cards.get("drawTo") is Callable:
			cards.drawTo.call(ctx, id, c.width, c.height, 0)
		else:
			ctx.fillStyle = "#E3662B"
			ctx.fillRect(0, 0, c.width, c.height)
		# CRT scanlines + vignette baked on the card
		ctx.fillStyle = "rgba(0,0,0,0.13)"
		var y := 0
		while y < c.height:
			ctx.fillRect(0, y, c.width, 1)
			y += 3
		var vg = ctx.createRadialGradient(c.width / 2.0, c.height / 2.0, c.height * 0.35, c.width / 2.0, c.height / 2.0, c.height * 0.85)
		vg.addColorStop(0, "rgba(0,0,0,0)")
		vg.addColorStop(1, "rgba(0,0,0,0.4)")
		ctx.fillStyle = vg
		ctx.fillRect(0, 0, c.width, c.height)
		_card = {"id": id, "w": c.width, "h": c.height, "c": c}
		return c

	func clear() -> void:
		if el == null or not visible:
			return
		visible = false
		if layer != null and is_instance_valid(layer):
			layer.visible = false
		ctx.setTransform(1, 0, 0, 1, 0, 0)
		ctx.clearRect(0, 0, el.width, el.height)

	func draw(s: Dictionary) -> void:
		_ensure()
		_resize()
		if el == null:
			return
		if not visible:
			visible = true
			layer.visible = true
		var W := _w
		var H := _h
		var dpr := _dpr
		ctx.setTransform(1, 0, 0, 1, 0, 0)
		ctx.clearRect(0, 0, el.width, el.height)
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
		if s.get("mode") == "commercial":
			_drawCommercial(ctx, W, H, s)
		elif s.get("mode") == "replay":
			_drawReplay(ctx, W, H, s)
		var flash: float = s.get("flash", 0.0) if s.get("flash") != null else 0.0
		if flash > 0:
			ctx.save()
			ctx.globalCompositeOperation = "source-over"
			ctx.fillStyle = "rgba(255,255,250,%s)" % CO._num(CO._clamp01(flash))
			ctx.fillRect(0, 0, W, H)
			ctx.restore()

	func _drawCommercial(ctx, W: float, H: float, s: Dictionary) -> void:
		var L: Dictionary = _layout
		var o: Dictionary = L.open
		var u: float = L.u
		var t: float = s.get("t", 0.0) if s.get("t") != null else 0.0
		var bez: float = s.get("bezel", 1.0) if s.get("bezel") != null else 1.0
		# picture-level FX first (they sit on the 3D picture, under the glass/bezel)
		ctx.save()
		ctx.beginPath()
		CO.tubePath(ctx, o.x, o.y, o.w, o.h, o.r, 0.012)
		ctx.clip()
		var tracking: float = s.get("tracking", 0.0) if s.get("tracking") != null else 0.0
		if tracking > 0:
			_tracking(ctx, o.x, o.y, o.w, o.h, tracking, t)
		var splice: float = s.get("splice", 0.0) if s.get("splice") != null else 0.0
		if splice > 0:
			var a: float = CO._clamp01(splice)
			ctx.fillStyle = "rgba(255,255,255,%s)" % CO._num(a * 0.85)
			ctx.fillRect(o.x, o.y, o.w, o.h)
			# the diagonal splice line + tape edge
			ctx.strokeStyle = "rgba(30,20,10,%s)" % CO._num(a)
			ctx.lineWidth = 6.0 * u
			var sx: float = o.x + o.w * 0.2
			var ex: float = o.x + o.w * 0.8
			ctx.beginPath()
			ctx.moveTo(sx, o.y)
			ctx.lineTo(ex, o.y + o.h)
			ctx.stroke()
			ctx.strokeStyle = "rgba(255,210,120,%s)" % CO._num(a)
			ctx.lineWidth = 2.0 * u
			ctx.beginPath()
			ctx.moveTo(sx + 10.0 * u, o.y)
			ctx.lineTo(ex + 10.0 * u, o.y + o.h)
			ctx.stroke()
		var card: float = s.get("card", -1.0) if s.get("card") != null else -1.0
		if card >= 0:
			var p: float = CO._clamp01(card)
			var e: float = CO._easeOutBack(p, 1.6)
			var cw: float = o.w * 1.02
			var ch: float = o.h * 1.02
			var x: float = o.x - o.w * 0.01 + (1.0 - e) * o.w * 1.1
			var y: float = o.y - o.h * 0.01
			var c = _cardCanvas(str(s.get("perkId", "")), minf(1024.0, cw), minf(768.0, ch))
			# while it holds (the product name is being read) the card keeps moving: a slow 3.5 % push-in
			var hold: float = CO._clamp01(float(s.get("cardHold", 0.0)) if s.get("cardHold") != null else 0.0)
			ctx.save()
			ctx.translate(x + cw / 2.0, y + ch / 2.0)
			ctx.rotate((1.0 - e) * 0.18)
			var sc: float = (0.92 + 0.08 * e + sin(p * PI) * 0.02) * (1.0 + 0.035 * CO._smooth(0.0, 1.0, hold))
			ctx.scale(sc, sc)
			if c != null:
				ctx.drawImage(c, -cw / 2.0, -ch / 2.0, cw, ch)
			# ...and one soft diagonal sheen sweeps across it, like light over a glossy title card
			var sw: float = CO._smooth(0.3, 0.75, hold)
			if sw > 0 and sw < 1:
				var bx := -cw * 0.75 + sw * cw * 1.5
				var band := cw * 0.16
				var g = ctx.createLinearGradient(bx - band, -ch * 0.2, bx + band, ch * 0.2)
				g.addColorStop(0, "rgba(255,248,230,0)")
				g.addColorStop(0.5, "rgba(255,248,230,%s)" % String.num(0.2 * sin(sw * PI), 3))
				g.addColorStop(1, "rgba(255,248,230,0)")
				ctx.globalCompositeOperation = "lighter"
				ctx.fillStyle = g
				ctx.fillRect(-cw / 2.0, -ch / 2.0, cw, ch)
				ctx.globalCompositeOperation = "source-over"
			ctx.restore()
		var osd = s.get("osd")
		if osd:
			var f: int = CO._round(58.0 * u)
			ctx.font = "%dpx %s" % [f, CO.FONTS.tape]
			ctx.textBaseline = "top"
			ctx.fillStyle = "rgba(0,0,0,0.5)"
			var txt := "II" if osd == "pause" else ("◀◀" if osd == "rew" else "▶")
			var blink: bool = osd == "pause" or int(floorf(t * 6.0)) % 2 == 0
			if blink:
				ctx.fillText(txt, o.x + 92.0 * u + 3.0 * u, o.y + 60.0 * u + 3.0 * u)
				ctx.fillStyle = "#7CFF8A"
				ctx.shadowColor = "#3AFF5A"
				ctx.shadowBlur = 10.0 * u
				ctx.fillText(txt, o.x + 92.0 * u, o.y + 60.0 * u)
				ctx.shadowBlur = 0
		ctx.restore()
		# the cabinet
		if bez > 0:
			ctx.globalAlpha = bez
			if _bezel != null:
				ctx.drawImage(_bezel, 0, 0, W, H)
			var click: float = s.get("cut", 0.0) if s.get("cut") != null else 0.0
			for i in L.knobs.size():
				var ang := (0.35 + 0.35 * sin(click * PI) * (1.0 - click) + (0.52 if click > 0.5 else 0.0)) if i == 0 else -0.8
				_knob(ctx, L.knobs[i], ang)
			ctx.globalAlpha = 1
		# star wipe: a hole revealing the gameplay camera, rimmed in gold
		var st = s.get("star")
		if st != null and float(st.r) > 0:
			var rot: float = st.get("rot", 0.0) if st.get("rot") != null else 0.0
			ctx.save()
			ctx.globalCompositeOperation = "destination-out"
			ctx.fillStyle = "#000"
			ctx.globalAlpha = 1
			ctx.beginPath()
			CO.starPath(ctx, st.x, st.y, st.r, rot)
			ctx.fill()
			ctx.restore()
			ctx.save()
			ctx.beginPath()
			CO.starPath(ctx, st.x, st.y, st.r, rot)
			ctx.lineJoin = "round"
			ctx.lineWidth = maxf(4.0, st.r * 0.035)
			ctx.strokeStyle = "#FFD84A"
			ctx.shadowColor = "#FFB020"
			ctx.shadowBlur = 24.0 * u
			ctx.stroke()
			ctx.lineWidth = maxf(1.5, st.r * 0.012)
			ctx.strokeStyle = "#FFFFFF"
			ctx.shadowBlur = 0
			ctx.stroke()
			ctx.restore()

	# VHS tracking: a rolling noise band, thin white streaks and a colour smear.
	func _tracking(ctx, x: float, y: float, w: float, h: float, amt: float, t: float) -> void:
		var n = CO.noiseStrip()
		var r := _rand
		var bandH := h * (0.07 + 0.05 * amt)
		var by := y + fmod(t * 0.9, 1.0) * (h + bandH) - bandH
		ctx.save()
		ctx.globalAlpha = 0.55 * amt
		if n != null:
			ctx.drawImage(n, 0, 0, n.width, n.height, x - r.call() * 30.0, by, w + 60.0, bandH)
		ctx.globalAlpha = 0.35 * amt
		if n != null:
			ctx.drawImage(n, 0, 0, n.width, n.height, x, y + h - bandH * 0.6, w, bandH * 0.6)
		ctx.globalAlpha = 1
		var i := 0
		while i < 10.0 * amt:
			var ly: float = y + r.call() * h
			var lw: float = w * (0.1 + r.call() * 0.5)
			var lx: float = x + r.call() * (w - lw)
			ctx.fillStyle = "rgba(255,255,255,%s)" % CO._num(0.25 + r.call() * 0.4)
			ctx.fillRect(lx, ly, lw, 1.0 + r.call() * 2.0)
			i += 1
		ctx.globalCompositeOperation = "screen"
		ctx.fillStyle = "rgba(80,0,120,%s)" % CO._num(0.12 * amt)
		ctx.fillRect(x, y, w, h)
		ctx.restore()

	func _drawReplay(ctx, W: float, H: float, s: Dictionary) -> void:
		var t: float = s.get("t", 0.0) if s.get("t") != null else 0.0
		var tracking: float = s.get("tracking", 0.0) if s.get("tracking") != null else 0.0
		if tracking > 0:
			_tracking(ctx, 0, 0, W, H, tracking, t)
		var wipe: float = s.get("wipe", -1.0) if s.get("wipe") != null else -1.0
		if wipe >= 0 and wipe <= 1:
			var p := wipe
			var D := Vector2(W, H).length()
			# diagonal team-colour bars racing across
			ctx.save()
			ctx.translate(W / 2.0, H / 2.0)
			ctx.rotate(-0.5)
			var cols := ["#F4C81E", "#2F5BD3", "#F4F1E8", "#E23B3B", "#2F5BD3"]
			var bw := D * 0.16
			for i in cols.size():
				var k: float = CO._smooth(0.0 + i * 0.05, 0.45 + i * 0.05, p) - CO._smooth(0.55 + i * 0.04, 1.0, p)
				if k <= 0:
					continue
				var off := (i - 2) * bw * 0.9
				ctx.fillStyle = cols[i]
				ctx.fillRect(-D / 2.0 - D * (1.0 - k) * (-1.0 if i % 2 else 1.0), off - bw / 2.0, D, bw)
			ctx.restore()
			# the spinning 13 roundel
			var grow: float = CO._smooth(0.0, 0.45, p)
			var shrink: float = CO._smooth(0.55, 1.0, p)
			var R := D * 0.36 * grow * (1.0 - shrink) + 1.0
			if R > 2:
				ctx.save()
				ctx.translate(W / 2.0, H / 2.0)
				ctx.rotate(p * TAU * 1.5)
				ctx.shadowColor = "rgba(0,0,0,0.5)"
				ctx.shadowBlur = R * 0.1
				ctx.beginPath()
				ctx.arc(0, 0, R, 0, TAU)
				ctx.fillStyle = "#E23B3B"
				ctx.fill()
				ctx.shadowBlur = 0
				ctx.beginPath()
				ctx.arc(0, 0, R * 0.8, 0, TAU)
				ctx.fillStyle = "#2F5BD3"
				ctx.fill()
				ctx.beginPath()
				ctx.arc(0, 0, R * 0.8, 0, TAU)
				ctx.lineWidth = R * 0.05
				ctx.strokeStyle = "#F4F1E8"
				ctx.stroke()
				ctx.font = "%dpx %s" % [CO._round(R * 0.95), CO.FONTS.logo]
				ctx.textAlign = "center"
				ctx.textBaseline = "middle"
				ctx.fillStyle = "#B5472A"
				ctx.fillText("13", R * 0.03, R * 0.1)
				ctx.fillStyle = "#FFE14D"
				ctx.fillText("13", 0, R * 0.06)
				ctx.restore()

static var _overlay = null
static func getOverlay() -> CommercialOverlay:
	if _overlay == null:
		_overlay = CommercialOverlay.new()
	return _overlay
