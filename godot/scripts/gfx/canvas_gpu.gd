# DACanvasGPU: the GPU backend of the Canvas 2D emulation (no JS counterpart; engine glue for canvas2d.gd).
#
# Every canvas CONTENT VERSION is an RS viewport (render target "RT", MSAA 2D, transparent) holding one RS canvas
# whose canvas items carry the device-space triangles of the draw calls. RTs render ONCE (update mode ONCE) in the
# frame they were recorded; after that their pixels are immutable. A canvas modified after its version rendered
# (or after another canvas sampled it: drawImage/createPattern snapshot semantics) starts a new version, whose
# first item blits the previous content unless the op clears the whole canvas. Auxiliary RTs: clip masks, layers
# (shadows, blur filter, non-local composite ops) and blur passes.
#
# Scheduling: at RenderingServer.frame_pre_draw every RT recorded this frame is sealed (a transparent canvas also gets
# a small non-MSAA "display" RT that un-premultiplies its latest version), topologically sorted by its sampling
# dependencies and chained
# through viewport parents (children render before parents; the chain ends at the main viewport), so dependent
# canvases render in the right order in the same frame. At frame_post_draw auxiliary / superseded RTs go back to
# the pool and settled canvases are BAKED: their pixels are read back once into a mipmapped ImageTexture and the
# RT is released, so a canvas that does not change costs nothing per frame (and little VRAM).
# canvas.texture is a stable Texture2D over an RS texture proxy retargeted to the latest version / baked texture.
#
# Blending (version RTs hold PREMULTIPLIED colour):
#   direct = blend_premul_alpha (source-over), blend_add (lighter, exact alpha via sqrt), blend_mul
#            (destination-out); geometry must not overlap unless the paint is opaque (overdraw-safe);
#   layer  = overlapping transparent geometry (stroke pieces, overlapping subpaths) is first drawn into a small aux
#            RT with blend_disabled (union: every covered sample gets the paint once), then composited as one quad;
#   comp   = every other composite op (source-atop, multiply, overlay, destination-in …): the op is drawn into a
#            layer, the canvas forks a new version whose first item blits the previous one, and a quad samples
#            src (layer) and dst (previous version, as a normal texture: the 2D screen texture has no alpha in
#            Godot 4.7) and writes mix(dst, composite(op, src, dst), clipCoverage) with blend_disabled.
class_name DACanvasGPU
extends RefCounted

static var MSAA: int = RenderingServer.VIEWPORT_MSAA_4X   # MSAA of canvas versions (4X; 8X looks closer to Chrome)
static var POOL_MAX := 12                                 # idle RTs kept per size (evicted after POOL_AGE frames)
static var POOL_AGE := 300

static var frame := 0                   # incremented at every frame_post_draw
static var _hooked := false
static var _recording: Array = []       # RTs recorded since the last pre_draw
static var _submitted: Array = []       # RTs scheduled for the current draw
static var _retire: Array = []          # RTs to release after the current draw
static var _pool := {}                  # "w|h|msaa" -> Array[RT]
static var _dirtyCanvases: Array = []   # canvases whose proxy target must be refreshed at schedule time
static var _watch: Array = []           # canvases that may bake
static var _versions: Array = []        # live canvas versions (RT) -> released once their canvas is gone
static var _proxies: Array = []         # [WeakRef(canvas), proxy RID] -> freed once the canvas is gone
static var _sweepT := 0
static var _all := {}                   # every RT that owns RS resources (freed by shutdown())
static var _shut := false
static var _shaders := {}
static var _mats := {}                  # variant -> material RID (no mask)
static var _blank := {}                 # "w|h" -> ImageTexture
static var _white: ImageTexture = null
static var stats := {"rts": 0, "rtsLive": 0, "rendered": 0, "baked": 0, "items": 0}

enum { DIRECT = 0, ADD = 1, MUL = 2, ISO = 3 }
const OPS := {
	"source-over": 0, "source-in": 1, "source-out": 2, "source-atop": 3, "destination-over": 4,
	"destination-in": 5, "destination-out": 6, "destination-atop": 7, "lighter": 8, "copy": 9, "xor": 10,
	"multiply": 11, "screen": 12, "overlay": 13, "darken": 14, "lighten": 15, "color-dodge": 16,
	"color-burn": 17, "hard-light": 18, "soft-light": 19, "difference": 20, "exclusion": 21, "hue": 22,
	"saturation": 23, "color": 24, "luminosity": 25,
}
# ops that change the destination outside the source shape (need a layer + full-area composite)
const NONLOCAL := [1, 2, 5, 7, 9]

class RT:
	extends RefCounted
	var vp: RID
	var cv: RID
	var tex: RID
	var w := 0
	var h := 0
	var msaa := 0
	var origin := Vector2.ZERO
	var items: Array = []
	var nused := 0
	var deps: Array = []
	var state := 0            # 0 free, 1 recording, 2 submitted, 3 rendered
	var sealed := false
	var readFrame := -1
	var aux := true
	var owner = null          # WeakRef to the DACanvas (versions)
	var gen := 0              # bumped on release
	var frameRendered := -1
	var relFrame := -1
	var hasContent := false
	var keep: Array = []      # objects (textures, source canvases) that must live until this RT rendered
	var opMats: Array = []    # per-op materials (reused when the RT is recorded again)
	var opShader: Array = []  # variant of each opMats entry
	var nOpMats := 0
	var maskMat: RID          # mask drawing material (with parent mask)
	# open batch
	var bKey := ""
	var bItem: RID
	var bP := PackedVector2Array()
	var bI := PackedInt32Array()
	var bC := PackedColorArray()
	var bU := PackedVector2Array()
	var bTex: RID

# ------------------------------------------------------------------------------------------------ lifecycle
static var _inDrawNow := false

static func _hook() -> void:
	if _hooked:
		return
	_hooked = true
	RenderingServer.frame_pre_draw.connect(_preDraw)
	RenderingServer.frame_post_draw.connect(_postDraw)
	_hookExit()

static var _exitHooked := false
static func _hookExit() -> void:
	if _exitHooked:
		return
	var ml = Engine.get_main_loop()   # null while a -s SceneTree script runs _init
	if ml is SceneTree and (ml as SceneTree).root != null:
		(ml as SceneTree).root.tree_exiting.connect(shutdown)
		_exitHooked = true

# Frees every RS resource of the backend (viewports, canvases, items, materials, proxies). Connected to the root
# viewport's tree_exiting, so the engine exits without leak reports; canvases must not be drawn afterwards.
static func shutdown() -> void:
	if _shut:
		return
	_shut = true
	for rt in _all.keys():
		_freeRT(rt)
	_all.clear()
	_pool.clear()
	_recording = []
	_submitted = []
	_retire = []
	_versions = []
	_watch = []
	_dirtyCanvases = []
	for e in _proxies:
		RenderingServer.free_rid(e[1])
	_proxies = []
	for v in _mats.values():
		RenderingServer.free_rid(v)
	_mats.clear()
	_shaders.clear()
	_blank.clear()
	_white = null

static func mainViewport() -> RID:
	var ml = Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		return (ml as SceneTree).root.get_viewport_rid()
	return RID()

# Size classes of auxiliary layers (so layers of similar size share pooled viewports: creating a viewport costs
# far more than drawing a few transparent pixels).
static func bucket(s: Vector2i) -> Vector2i:
	return Vector2i(_bucket1(s.x), _bucket1(s.y))

static func _bucket1(n: int) -> int:
	var q := 16 if n <= 64 else (32 if n <= 256 else 64)
	return mini(4096, (n + q - 1) / q * q)

static func newRT(w: int, h: int, msaa: int, aux: bool, origin: Vector2 = Vector2.ZERO) -> RT:
	_hook()
	w = maxi(1, w)
	h = maxi(1, h)
	var key := "%d|%d|%d" % [w, h, msaa]
	var rt: RT = null
	var list: Array = _pool.get(key, [])
	# an RT released during the current frame's post-draw is not reused before the next frame: Godot 4.7 does not
	# redraw a viewport that already rendered in this frame when force_draw is nested in frame_post_draw
	if not list.is_empty() and (list[list.size() - 1] as RT).relFrame < frame:
		rt = list.pop_back()
	else:
		rt = RT.new()
		rt.w = w
		rt.h = h
		rt.msaa = msaa
		rt.vp = RenderingServer.viewport_create()
		RenderingServer.viewport_set_size(rt.vp, w, h)
		RenderingServer.viewport_set_transparent_background(rt.vp, true)
		RenderingServer.viewport_set_disable_3d(rt.vp, true)
		RenderingServer.viewport_set_msaa_2d(rt.vp, msaa)
		RenderingServer.viewport_set_clear_mode(rt.vp, RenderingServer.VIEWPORT_CLEAR_ALWAYS)
		RenderingServer.viewport_set_default_canvas_item_texture_filter(rt.vp, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
		RenderingServer.viewport_set_default_canvas_item_texture_repeat(rt.vp, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_DISABLED)
		rt.cv = RenderingServer.canvas_create()
		RenderingServer.viewport_attach_canvas(rt.vp, rt.cv)
		RenderingServer.viewport_set_active(rt.vp, true)
		rt.tex = RenderingServer.viewport_get_texture(rt.vp)
		_all[rt] = true
		stats.rts += 1
	RenderingServer.viewport_set_update_mode(rt.vp, RenderingServer.VIEWPORT_UPDATE_DISABLED)
	rt.aux = aux
	rt.origin = origin
	RenderingServer.viewport_set_canvas_transform(rt.vp, rt.cv, Transform2D(0.0, -origin))
	rt.state = 1
	rt.sealed = false
	rt.deps = []
	rt.readFrame = -1
	rt.hasContent = false
	rt.owner = null
	rt.bKey = ""
	_recording.append(rt)
	stats.rtsLive += 1
	return rt

# Clears the recorded content of a recording/rendered RT so it can be recorded again (same viewport).
static func resetRT(rt: RT) -> void:
	rt.bKey = ""
	rt.bP = PackedVector2Array()
	rt.bI = PackedInt32Array()
	rt.bC = PackedColorArray()
	rt.bU = PackedVector2Array()
	for i in rt.nused:
		var it: RID = rt.items[i]
		RenderingServer.canvas_item_clear(it)
		RenderingServer.canvas_item_set_material(it, RID())
		RenderingServer.canvas_item_set_copy_to_backbuffer(it, false, Rect2())
		RenderingServer.canvas_item_set_default_texture_filter(it, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_DEFAULT)
		RenderingServer.canvas_item_set_default_texture_repeat(it, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_DEFAULT)
	rt.nused = 0
	rt.nOpMats = 0
	rt.deps = []
	rt.keep = []
	rt.hasContent = false
	rt.sealed = false
	if rt.state != 1:
		rt.state = 1
		_recording.append(rt)

static func release(rt: RT) -> void:
	if rt == null or rt.state == 0:
		return
	resetRT(rt)
	_recording.erase(rt)
	rt.state = 0
	rt.gen += 1
	rt.owner = null
	RenderingServer.viewport_set_update_mode(rt.vp, RenderingServer.VIEWPORT_UPDATE_DISABLED)
	RenderingServer.viewport_set_parent_viewport(rt.vp, RID())
	stats.rtsLive -= 1
	var key := "%d|%d|%d" % [rt.w, rt.h, rt.msaa]
	var list: Array = _pool.get(key, [])
	if list.size() < POOL_MAX:
		rt.relFrame = frame
		list.push_front(rt)
		_pool[key] = list
	else:
		_freeRT(rt)

static func _freeRT(rt: RT) -> void:
	_all.erase(rt)
	for it in rt.items:
		RenderingServer.free_rid(it)
	rt.items = []
	for m in rt.opMats:
		RenderingServer.free_rid(m)
	rt.opMats = []
	rt.opShader = []
	if rt.maskMat.is_valid():
		RenderingServer.free_rid(rt.maskMat)
	RenderingServer.free_rid(rt.cv)
	RenderingServer.free_rid(rt.vp)
	stats.rts -= 1

# Release after the current frame's draw (superseded versions, aux RTs).
static func retire(rt: RT) -> void:
	if rt != null and not _retire.has(rt):
		_retire.append(rt)

static func addDep(rt: RT, src: RT) -> void:
	if src == null or src == rt:
		return
	if not rt.deps.has(src):
		rt.deps.append(src)
	src.readFrame = frame
	if src.state == 1:
		src.sealed = true

static func trackProxy(canvas, proxy: RID) -> void:
	_proxies.append([weakref(canvas), proxy])

static func trackVersion(rt: RT) -> void:
	if not _versions.has(rt):
		_versions.append(rt)

# Frees GPU resources of canvases that were dropped (no predelete hook on DACanvas: safe at engine exit).
static func _sweep() -> void:
	var keep: Array = []
	for rt in _versions:
		if rt.state == 0:
			continue
		var alive: bool = rt.owner != null and rt.owner.get_ref() != null
		if not alive and (rt.state == 3 or rt.state == 1):
			if rt.state == 1:
				_recording.erase(rt)
			release(rt)
			continue
		keep.append(rt)
	_versions = keep
	for key in _pool.keys():
		var list: Array = _pool[key]
		while not list.is_empty() and frame - (list[list.size() - 1] as RT).relFrame > POOL_AGE:
			_freeRT(list.pop_back())
		if list.is_empty():
			_pool.erase(key)
	var kp: Array = []
	for e in _proxies:
		if (e[0] as WeakRef).get_ref() == null:
			RenderingServer.free_rid(e[1])
		else:
			kp.append(e)
	_proxies = kp

static func markDirty(canvas) -> void:
	if not _dirtyCanvases.has(canvas):
		_dirtyCanvases.append(canvas)

static func watch(canvas) -> void:
	if not _watch.has(canvas):
		_watch.append(canvas)

# ------------------------------------------------------------------------------------------------ frame hooks
static func _preDraw() -> void:
	if _shut:
		return
	_hookExit()
	if _recording.is_empty() and _dirtyCanvases.is_empty():
		return
	for c in _dirtyCanvases:
		if c != null:
			c._prepareDisplay()
	var rec := _recording
	_recording = []
	for rt in rec:
		flush(rt)
	var order: Array = []
	var seen := {}
	for rt in rec:
		_visit(rt, seen, order)
	var main := RID() if _inDrawNow else mainViewport()
	for i in order.size():
		var rt: RT = order[i]
		var parent: RID = (order[i + 1] as RT).vp if i + 1 < order.size() else main
		RenderingServer.viewport_set_parent_viewport(rt.vp, parent)
		RenderingServer.viewport_set_update_mode(rt.vp, RenderingServer.VIEWPORT_UPDATE_ONCE)
		rt.state = 2
		rt.sealed = true
		_submitted.append(rt)
	for c in _dirtyCanvases:
		if c != null:
			c._updateProxy()
			watch(c)
	_dirtyCanvases = []

static func _visit(rt: RT, seen: Dictionary, order: Array) -> void:
	if seen.has(rt):
		return
	seen[rt] = true
	for d in rt.deps:
		if d.state == 1 and not seen.has(d):
			_visit(d, seen, order)
	if rt.state == 1:
		order.append(rt)

static func _postDraw() -> void:
	if _shut:
		return
	frame += 1
	for rt in _submitted:
		if rt.state == 2:
			rt.state = 3
			rt.frameRendered = frame
			stats.rendered += 1
	_submitted = []
	if not _retire.is_empty():
		var keep: Array = []
		for rt in _retire:
			if rt.state == 1 or rt.state == 2:
				keep.append(rt)   # recorded after this draw started: next frame
			else:
				release(rt)
		_retire = keep
	_sweepT += 1
	if _sweepT >= 30:
		_sweepT = 0
		_sweep()
	if not _watch.is_empty():
		var w2: Array = []
		for c in _watch:
			if c != null and not c._bakeStep(frame):
				w2.append(c)
		_watch = w2

# Renders everything pending right now (synchronous; used by getImageData/toImage on GPU canvases).
static func drawNow() -> void:
	if _shut or _inDrawNow or (_recording.is_empty() and _submitted.is_empty()):
		return   # (nested call from a frame_post_draw handler run by our own force_draw: content stays pending)
	var main := mainViewport()
	if main.is_valid():
		RenderingServer.viewport_set_active(main, false)
	_inDrawNow = true
	RenderingServer.force_draw(false, 0.0)
	_inDrawNow = false
	if main.is_valid():
		RenderingServer.viewport_set_active(main, true)

# ------------------------------------------------------------------------------------------------ textures
static func blank(w: int, h: int) -> ImageTexture:
	var key := "%d|%d" % [w, h]
	var t = _blank.get(key)
	if t == null:
		var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
		t = ImageTexture.create_from_image(img)
		_blank[key] = t
	return t

static func white() -> ImageTexture:
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white

# ------------------------------------------------------------------------------------------------ shaders
const PAINT_SHADER := """shader_type canvas_item;
render_mode %s;
uniform sampler2D clip_mask : filter_linear, repeat_disable;
uniform vec4 clip_box = vec4(0.0);
%s
uniform vec4 pk = vec4(0.0);
uniform vec4 pa = vec4(0.0);
uniform vec4 pb = vec4(0.0);
uniform vec4 rc = vec4(-1e9, -1e9, 1e9, 1e9);
uniform vec4 m0 = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 m1 = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 m2 = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 m3 = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 mo = vec4(0.0);
varying vec4 vcol;
varying vec2 vpos;
void vertex() {
	vcol = COLOR;
	vpos = VERTEX;
}
// The paint source is sampled in fragment(): Godot 4.7 cannot pass the TEXTURE built-in to a user function
// ("!actions.custom_samplers.has(...tex_builtin)" compile error), so paint() takes the sample `tx` instead.
// rampT: gradient parameter (x) and validity (y) of kinds 2 (radial) and 3 (conic).
vec2 rampT(int k, vec2 uv, vec4 A, vec4 B) {
	if (k == 3) {
		vec2 d = uv - A.xy;
		float ang = atan(d.y, d.x) - A.z;
		return vec2(fract(ang / 6.283185307179586), 1.0);
	}
	vec2 cd = B.xy - A.xy;
	vec2 pd = uv - A.xy;
	float dr = B.z - A.z;
	float qa = dot(cd, cd) - dr * dr;
	float qb = dot(pd, cd) + A.z * dr;
	float qc = dot(pd, pd) - A.z * A.z;
	float w = 0.0;
	bool ok = false;
	if (abs(qa) < 1e-9 * max(1.0, dot(cd, cd) + dr * dr)) {
		if (abs(qb) > 1e-12) {
			float t = qc / (2.0 * qb);
			if (A.z + t * dr >= 0.0) { w = t; ok = true; }
		}
	} else {
		float D = qb * qb - qa * qc;
		if (D >= 0.0) {
			float sq = sqrt(D);
			float t1 = (qb + sq) / qa;
			float t2 = (qb - sq) / qa;
			float hi = max(t1, t2);
			float lo = min(t1, t2);
			if (A.z + hi * dr >= 0.0) { w = hi; ok = true; }
			else if (A.z + lo * dr >= 0.0) { w = lo; ok = true; }
		}
	}
	return vec2(w, ok ? 1.0 : 0.0);
}
vec4 paint(vec4 tx, vec2 uv, vec4 col, vec4 k4, mat4 cm, vec4 cmo) {
	int k = int(k4.x + 0.5);
	vec4 c;
	if (k == 0) {
		c = col;
	} else if (k == 1) {
		c = tx;
		if (k4.y > 0.5) { c.rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0); }
		c.a *= col.a;
	} else if (k == 2 || k == 3) {
		c = tx;
		c.a *= col.a;
	} else if (k == 4) {
		int rb = int(k4.w + 0.5);
		bool rx = (rb & 1) != 0;
		bool ry = (rb & 2) != 0;
		if ((!rx && (uv.x < 0.0 || uv.x > 1.0)) || (!ry && (uv.y < 0.0 || uv.y > 1.0))) {
			c = vec4(0.0);
		} else {
			c = tx;
			if (k4.y > 0.5) { c.rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0); }
		}
		c.a *= col.a;
	} else if (k == 5) {
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
		return tx * col.a;
	} else {
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
		float a = tx.a * col.a;
		return vec4(col.rgb * a, a);
	}
	c = clamp(cm * c + cmo, 0.0, 1.0);
	return vec4(c.rgb * c.a, c.a);
}
float coverage(vec2 p, vec4 r) {
	float cx = clamp(min(p.x + 0.5, r.z) - max(p.x - 0.5, r.x), 0.0, 1.0);
	float cy = clamp(min(p.y + 0.5, r.w) - max(p.y - 0.5, r.y), 0.0, 1.0);
	float cov = cx * cy;
	if (clip_box.z > 0.0) {
		vec2 u = (p - clip_box.xy) / clip_box.zw;
		cov *= (u.x < 0.0 || u.y < 0.0 || u.x > 1.0 || u.y > 1.0) ? 0.0 : texture(clip_mask, u).a;
	}
	return cov;
}
%s
void fragment() {
	mat4 cm = transpose(mat4(m0, m1, m2, m3));
	int pkind = int(pk.x + 0.5);
	vec4 tx = vec4(0.0);
	if (pkind == 2 || pkind == 3) {
		vec2 rt = rampT(pkind, UV, pa, pb);
		tx = rt.y > 0.5 ? texture(TEXTURE, vec2(clamp(rt.x, 0.0, 1.0) * (255.0 / 256.0) + 0.5 / 256.0, 0.5)) : vec4(0.0);
	} else if (pkind == 4) {
		int rb = int(pk.w + 0.5);
		vec2 f = vec2((rb & 1) != 0 ? fract(UV.x) : UV.x, (rb & 2) != 0 ? fract(UV.y) : UV.y);
		tx = textureGrad(TEXTURE, f, dFdx(UV), dFdy(UV));
	} else if (pkind != 0) {
		tx = texture(TEXTURE, UV);
	}
	vec4 s = paint(tx, UV, vcol, pk, cm, mo);
	float cov = coverage(vpos, rc);
%s
}
"""

const ISO_FUNCS := """
float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }
vec3 clipColor(vec3 c) {
	float l = lum(c); float n = min(c.r, min(c.g, c.b)); float x = max(c.r, max(c.g, c.b));
	if (n < 0.0) c = l + (c - l) * l / max(l - n, 1e-6);
	if (x > 1.0) c = l + (c - l) * (1.0 - l) / max(x - l, 1e-6);
	return c;
}
vec3 setLum(vec3 c, float l) { return clipColor(c + (l - lum(c))); }
float sat(vec3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }
vec3 setSat(vec3 c, float s) {
	float mx = max(c.r, max(c.g, c.b)); float mn = min(c.r, min(c.g, c.b));
	vec3 r = vec3(0.0);
	if (mx > mn) r = (c - mn) * s / (mx - mn);
	return r;
}
float softL(float b, float s) {
	if (s <= 0.5) return b - (1.0 - 2.0 * s) * b * (1.0 - b);
	float d = b <= 0.25 ? ((16.0 * b - 12.0) * b + 4.0) * b : sqrt(b);
	return b + (2.0 * s - 1.0) * (d - b);
}
vec3 blendF(int op, vec3 b, vec3 s) {
	if (op == 11) return b * s;
	if (op == 12) return b + s - b * s;
	if (op == 13) return vec3(b.r <= 0.5 ? 2.0 * s.r * b.r : 1.0 - 2.0 * (1.0 - s.r) * (1.0 - b.r), b.g <= 0.5 ? 2.0 * s.g * b.g : 1.0 - 2.0 * (1.0 - s.g) * (1.0 - b.g), b.b <= 0.5 ? 2.0 * s.b * b.b : 1.0 - 2.0 * (1.0 - s.b) * (1.0 - b.b));
	if (op == 14) return min(b, s);
	if (op == 15) return max(b, s);
	if (op == 16) return vec3(b.r == 0.0 ? 0.0 : (s.r >= 1.0 ? 1.0 : min(1.0, b.r / (1.0 - s.r))), b.g == 0.0 ? 0.0 : (s.g >= 1.0 ? 1.0 : min(1.0, b.g / (1.0 - s.g))), b.b == 0.0 ? 0.0 : (s.b >= 1.0 ? 1.0 : min(1.0, b.b / (1.0 - s.b))));
	if (op == 17) return vec3(b.r >= 1.0 ? 1.0 : (s.r <= 0.0 ? 0.0 : 1.0 - min(1.0, (1.0 - b.r) / s.r)), b.g >= 1.0 ? 1.0 : (s.g <= 0.0 ? 0.0 : 1.0 - min(1.0, (1.0 - b.g) / s.g)), b.b >= 1.0 ? 1.0 : (s.b <= 0.0 ? 0.0 : 1.0 - min(1.0, (1.0 - b.b) / s.b)));
	if (op == 18) return vec3(s.r <= 0.5 ? 2.0 * s.r * b.r : 1.0 - 2.0 * (1.0 - s.r) * (1.0 - b.r), s.g <= 0.5 ? 2.0 * s.g * b.g : 1.0 - 2.0 * (1.0 - s.g) * (1.0 - b.g), s.b <= 0.5 ? 2.0 * s.b * b.b : 1.0 - 2.0 * (1.0 - s.b) * (1.0 - b.b));
	if (op == 19) return vec3(softL(b.r, s.r), softL(b.g, s.g), softL(b.b, s.b));
	if (op == 20) return abs(b - s);
	if (op == 21) return b + s - 2.0 * b * s;
	if (op == 22) return setLum(setSat(s, sat(b)), lum(b));
	if (op == 23) return setLum(setSat(b, sat(s)), lum(b));
	if (op == 24) return setLum(s, lum(b));
	return setLum(b, lum(s));
}
vec4 composite(int op, vec4 s, vec4 d) {
	float sa = s.a; float da = d.a;
	if (op == 0) return s + d * (1.0 - sa);
	if (op == 1) return s * da;
	if (op == 2) return s * (1.0 - da);
	if (op == 3) return s * da + d * (1.0 - sa);
	if (op == 4) return s * (1.0 - da) + d;
	if (op == 5) return d * sa;
	if (op == 6) return d * (1.0 - sa);
	if (op == 7) return s * (1.0 - da) + d * sa;
	if (op == 8) return min(s + d, vec4(1.0));
	if (op == 9) return s;
	if (op == 10) return s * (1.0 - da) + d * (1.0 - sa);
	vec3 cs = sa > 0.0 ? s.rgb / sa : vec3(0.0);
	vec3 cb = da > 0.0 ? d.rgb / da : vec3(0.0);
	vec3 r = (1.0 - da) * s.rgb + (1.0 - sa) * d.rgb + sa * da * clamp(blendF(op, cb, cs), 0.0, 1.0);
	return vec4(r, sa + da - sa * da);
}
"""

static func _shader(name: String) -> RID:
	var sh = _shaders.get(name)
	if sh != null:
		return sh.get_rid()
	var code := ""
	match name:
		"direct":
			code = PAINT_SHADER % ["blend_premul_alpha", "", "", "\tCOLOR = s * cov;"]
		"add":
			code = PAINT_SHADER % ["blend_add", "", "", "\tvec4 o = s * cov;\n\tfloat q = sqrt(max(o.a, 0.0));\n\tCOLOR = q > 0.0 ? vec4(o.rgb / q, q) : vec4(0.0);"]
		"mul":
			code = PAINT_SHADER % ["blend_mul", "", "", "\tCOLOR = vec4(1.0 - s.a * cov);"]
		"layer":
			code = PAINT_SHADER % ["blend_disabled", "", "", "\tCOLOR = s * cov;"]
		"comp":
			code = PAINT_SHADER % ["blend_disabled", "uniform sampler2D dst_tex : filter_nearest, repeat_disable;\nuniform vec4 dst_box = vec4(0.0, 0.0, 1.0, 1.0);", ISO_FUNCS,
				"\tvec4 d = texture(dst_tex, (vpos - dst_box.xy) / dst_box.zw);\n\tCOLOR = mix(d, composite(int(pk.z + 0.5), s, d), cov);"]
		"blur":
			code = """shader_type canvas_item;
render_mode blend_disabled;
uniform vec4 bp = vec4(0.0);
void fragment() {
	vec4 acc = vec4(0.0);
	float ws = 0.0;
	int R = int(bp.w);
	for (int i = -R; i <= R; i++) {
		float x = float(i);
		float w = exp(-0.5 * x * x / (bp.z * bp.z));
		acc += texture(TEXTURE, UV + bp.xy * x) * w;
		ws += w;
	}
	COLOR = acc / ws;
}
"""
		"unpremul":
			code = """shader_type canvas_item;
render_mode blend_disabled;
void fragment() {
	vec4 d = texture(TEXTURE, UV);
	COLOR = d.a > 0.0 ? vec4(clamp(d.rgb / d.a, 0.0, 1.0), d.a) : vec4(0.0);
}
"""
		"copy":
			code = """shader_type canvas_item;
render_mode blend_disabled;
void fragment() {
	COLOR = texture(TEXTURE, UV);
}
"""
		"copyStraight":
			code = """shader_type canvas_item;
render_mode blend_disabled;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(t.rgb * t.a, t.a);
}
"""
		"mask":
			code = """shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D parent_mask : filter_linear, repeat_disable;
uniform vec4 parent_box = vec4(0.0);
varying vec2 vpos;
void vertex() { vpos = VERTEX; }
void fragment() {
	float c = 1.0;
	if (parent_box.z > 0.0) {
		vec2 u = (vpos - parent_box.xy) / parent_box.zw;
		c = (u.x < 0.0 || u.y < 0.0 || u.x > 1.0 || u.y > 1.0) ? 0.0 : texture(parent_mask, u).a;
	}
	COLOR = vec4(1.0, 1.0, 1.0, c);
}
"""
	var s := Shader.new()
	s.code = code
	_shaders[name] = s
	return s.get_rid()

static func _material(variant: String) -> RID:
	var m = _mats.get(variant)
	if m != null:
		return m
	var r := RenderingServer.material_create()
	RenderingServer.material_set_shader(r, _shader(variant))
	_mats[variant] = r
	return r

# Per-op material of `variant` owned by rt (pooled with it). Canvas-item instance uniforms are NOT used: they
# proved unreliable for many items per frame in Godot 4.7 (parameters of earlier items got lost).
static func opMaterial(rt: RT, variant: String) -> RID:
	var m: RID
	if rt.nOpMats < rt.opMats.size():
		m = rt.opMats[rt.nOpMats]
		if rt.opShader[rt.nOpMats] != variant:
			RenderingServer.material_set_shader(m, _shader(variant))
			rt.opShader[rt.nOpMats] = variant
	else:
		m = RenderingServer.material_create()
		RenderingServer.material_set_shader(m, _shader(variant))
		rt.opMats.append(m)
		rt.opShader.append(variant)
	rt.nOpMats += 1
	return m

# ------------------------------------------------------------------------------------------------ items
static func _item(rt: RT) -> RID:
	var it: RID
	if rt.nused < rt.items.size():
		it = rt.items[rt.nused]
	else:
		it = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(it, rt.cv)
		rt.items.append(it)
		stats.items += 1
	# explicit order: Godot sorts sibling canvas items with an unstable sort (>= 16 siblings get reordered)
	RenderingServer.canvas_item_set_draw_index(it, rt.nused)
	rt.nused += 1
	rt.hasContent = true
	return it

# Submits the open batch of rt.
static func flush(rt: RT) -> void:
	if rt.bKey == "":
		return
	if not rt.bI.is_empty():
		RenderingServer.canvas_item_add_triangle_array(rt.bItem, rt.bI, rt.bP, rt.bC, rt.bU, PackedInt32Array(), PackedFloat32Array(), rt.bTex)
	rt.bKey = ""
	rt.bP = PackedVector2Array()
	rt.bI = PackedInt32Array()
	rt.bC = PackedColorArray()
	rt.bU = PackedVector2Array()

static func _colors(c: Color, n: int) -> PackedColorArray:
	var a := PackedColorArray()
	a.resize(n)
	a.fill(c)
	return a

# Appends triangles with the default canvas material (straight colour, source-over blend) to a batch.
# tex = RID() for solid colour. uv = per-vertex UVs (empty for solid).
static func addDefault(rt: RT, P: PackedVector2Array, I: PackedInt32Array, col: Color, tex: RID, uv: PackedVector2Array, filter: int, repeat: int) -> void:
	if I.is_empty():
		return
	var key := "d|%d|%d|%d" % [tex.get_id(), filter, repeat]
	if rt.bKey != key or rt.bP.size() > 60000:
		flush(rt)
		rt.bKey = key
		rt.bItem = _item(rt)
		rt.bTex = tex
		if filter != 0:
			RenderingServer.canvas_item_set_default_texture_filter(rt.bItem, filter)
		if repeat != 0:
			RenderingServer.canvas_item_set_default_texture_repeat(rt.bItem, repeat)
	var base := rt.bP.size()
	rt.bP.append_array(P)
	rt.bC.append_array(_colors(col, P.size()))
	if tex.is_valid():
		rt.bU.append_array(uv)
	if base == 0:
		rt.bI.append_array(I)
	else:
		for t in I:
			rt.bI.append(base + t)

# One item with a paint material (instance params). Returns the item.
static func addMaterial(rt: RT, P: PackedVector2Array, I: PackedInt32Array, col: Color, tex: RID, uv: PackedVector2Array, variant: String, mask: RT, params: Dictionary, filter: int, repeat: int, dst: RT = null) -> RID:
	flush(rt)
	var it := _item(rt)
	var material := opMaterial(rt, variant)
	RenderingServer.canvas_item_set_material(it, material)
	for k in params:
		RenderingServer.material_set_param(material, k, params[k])
	if mask != null:
		RenderingServer.material_set_param(material, "clip_mask", mask.tex)
		RenderingServer.material_set_param(material, "clip_box", Vector4(mask.origin.x, mask.origin.y, mask.w, mask.h))
	else:
		RenderingServer.material_set_param(material, "clip_box", Vector4(0, 0, 0, 0))
	if filter != 0:
		RenderingServer.canvas_item_set_default_texture_filter(it, filter)
	if repeat != 0:
		RenderingServer.canvas_item_set_default_texture_repeat(it, repeat)
	if dst != null:
		RenderingServer.material_set_param(material, "dst_tex", dst.tex)
		RenderingServer.material_set_param(material, "dst_box", Vector4(dst.origin.x, dst.origin.y, dst.w, dst.h))
	if not I.is_empty():
		var U := uv if tex.is_valid() or not uv.is_empty() else PackedVector2Array()
		RenderingServer.canvas_item_add_triangle_array(it, I, P, _colors(col, P.size()), U, PackedInt32Array(), PackedFloat32Array(), tex)
	return it

# Texture blitted with blend disabled (putImageData, continuing a previous version). premul = the source holds
# premultiplied colour (a version RT); otherwise it is straight (ImageTexture) and gets premultiplied.
static func addCopy(rt: RT, rect: Rect2, tex: RID, src: Rect2, filter: int, premul: bool = false) -> void:
	flush(rt)
	var it := _item(rt)
	RenderingServer.canvas_item_set_material(it, _material("copy" if premul else "copyStraight"))
	if filter != 0:
		RenderingServer.canvas_item_set_default_texture_filter(it, filter)
	RenderingServer.canvas_item_add_texture_rect_region(it, rect, tex, src)

# Display RT of a transparent canvas: its latest version un-premultiplied (straight alpha for materials / UI).
static func display(src: RT, disp: RT) -> RT:
	var d := disp
	if d == null or d.state == 0 or d.w != src.w or d.h != src.h or d.readFrame == frame or d.state == 2:
		d = newRT(src.w, src.h, 0, false)
	else:
		resetRT(d)
	addDep(d, src)
	var it := _item(d)
	RenderingServer.canvas_item_set_material(it, _material("unpremul"))
	RenderingServer.canvas_item_set_default_texture_filter(it, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	RenderingServer.canvas_item_add_texture_rect(it, Rect2(0, 0, src.w, src.h), src.tex)
	return d

# Separable Gaussian blur of an RT (premultiplied) into a new aux RT; sigma in device px.
static func blur(src: RT, sigma: float) -> RT:
	var ds := 1
	if sigma > 12.0:
		ds = 2
	if sigma > 24.0:
		ds = 4
	var w := int(ceil(float(src.w) / ds))
	var h := int(ceil(float(src.h) / ds))
	var s2 := sigma / ds
	var R := mini(int(ceil(s2 * 3.0)), 48)
	var a := newRT(w, h, 0, true)
	flush(src)
	addDep(a, src)
	var ia := _item(a)
	var ma := opMaterial(a, "blur")
	RenderingServer.canvas_item_set_material(ia, ma)
	RenderingServer.material_set_param(ma, "bp", Vector4(1.0 / src.w * ds, 0.0, s2, R))
	RenderingServer.canvas_item_add_texture_rect(ia, Rect2(0, 0, w, h), src.tex)
	var b := newRT(w, h, 0, true)
	addDep(b, a)
	var ib := _item(b)
	var mb := opMaterial(b, "blur")
	RenderingServer.canvas_item_set_material(ib, mb)
	RenderingServer.material_set_param(mb, "bp", Vector4(0.0, 1.0 / h, s2, R))
	RenderingServer.canvas_item_add_texture_rect(ib, Rect2(0, 0, w, h), a.tex)
	retire(a)
	retire(b)
	b.origin = src.origin   # device placement of the blurred image (covers src.w x src.h device px)
	return b

# Clip mask RT from device triangles (white, MSAA), multiplied by the parent mask.
static func mask(P: PackedVector2Array, I: PackedInt32Array, box: Rect2i, parent: RT) -> RT:
	var rt := newRT(box.size.x, box.size.y, MSAA, true, Vector2(box.position))
	if not rt.maskMat.is_valid():
		rt.maskMat = RenderingServer.material_create()
		RenderingServer.material_set_shader(rt.maskMat, _shader("mask"))
	if parent != null:
		addDep(rt, parent)
		RenderingServer.material_set_param(rt.maskMat, "parent_mask", parent.tex)
		RenderingServer.material_set_param(rt.maskMat, "parent_box", Vector4(parent.origin.x, parent.origin.y, parent.w, parent.h))
	else:
		RenderingServer.material_set_param(rt.maskMat, "parent_box", Vector4(0, 0, 0, 0))
	var it := _item(rt)
	RenderingServer.canvas_item_set_material(it, rt.maskMat)
	if not I.is_empty():
		RenderingServer.canvas_item_add_triangle_array(it, I, P, PackedColorArray([Color.WHITE]))
	retire(rt)
	return rt
