# Renderer, post pipeline, resize and dynamic resolution (port of src/core/render.js; ARCHITECTURE §5/§12, GDD §3.9,
# §14).
#
# Pipeline (Godot): the 3D world renders into `view`, an HDR SubViewport (use_hdr_2d: linear half-float, 4x MSAA,
# sized window x pixelRatio; linear tone mapper, exposure 1: the image stays linear HDR). The bloom is an exact port
# of three's UnrealBloomPass (strength 0.45, radius 0.55, threshold 0.8: luminance high pass at half res, 5 mips of
# separable gaussian blurs, composite) as a chain of nested half-float SubViewports (shaders/bloom.gdshader; nesting
# makes Godot draw them after the world view, in order). A full-screen ColorRect on a CanvasLayer (layer -100, under
# every UI layer) shows the view + bloom through shaders/post.gdshader = the GradePass, which works in linear HDR
# and ends with three's ACES Filmic (toneMappingExposure 1.05) + sRGB, exactly like the JS pass that folds the
# OutputPass in. It implements every `render.post` knob:
#   saturation (1), contrast, warmth (70s tint), grain, vignette (extra, on top of a subtle base), chroma (px),
#   damage   signal loss: static creeping in from the edges + chromatic aberration + line jitter + hold slip,
#   static   full-screen snow, roll = vertical roll, whiteout = Big Shot flash (also boosts bloom),
#   scanlines, crt (commercial look: barrel + scanlines + chroma), collapse (CRT power-off: 0 -> 1 = image
#   squashes to a white line, the line shrinks to a dot, the dot fades out).
# Other systems animate `game.render.post.*` as plain numbers; defaults are 0 except saturation 1.
# setCameraOverride(camera, {aspect}) renders another camera (it must live under game.scene) into a centered
# viewport of that aspect (letterboxed black, the HUD bezel covers it): the view is resized to that aspect and the
# grade remaps it (uView). addPrePass(fn) runs fn(render) every frame before the frame is drawn.
# TEMPORARY EFFECT LAYERS: setFx(owner, knobs, { ttl }) / clearFx(owner) / clearAllFx() / hasFx(owner). A short-lived
# look (Instant Replay's VHS rewind, ...) is a named layer combined into the grade uniforms every frame WITHOUT
# writing render.post: roll, chroma, scanlines, static, whiteout, crt, collapse, vignette, damage and grain take the
# max of render.post and every layer; saturation is multiplied by each layer's `saturation`. Ending the effect is
# clearFx(owner), which removes exactly that contribution whatever else changed meanwhile. With `ttl` (s, real time)
# a layer also drops by itself when its owner stops refreshing it, so a crashed or interrupted effect can never
# leave its look on screen. reset() clears every layer.
# Camera occlusion fade (materials uOcc*, computed by camera.gd as cam.occ): uploaded for the gameplay main camera
# only (the shaders compare CAMERA_POSITION_WORLD with daOccCam, so feeds and shadows never fade).
# addMainHook(hook = {before, shadow, after}): before(camera) and shadow() run at the end of frame() (Godot draws
# the frame after the scripts), after() when the frame has been drawn (RenderingServer.frame_post_draw).
#
# Godot-only plumbing (no JS counterpart): `view` (the world SubViewport; SubViewports rendering game.scene from other
# cameras (feeds) share its World3D automatically), `env` (the WorldEnvironment of game.scene's world: background
# #150F1C, no Godot ambient/reflections/glow), `fog` (THREE scene.fog of game.scene: {color: Color sRGB, near, far};
# lights.gd drives it, frame() uploads the daFog* shader globals + the native depth fog of `env` for non-DEAD-AIR
# materials), CAM_NOFOG / CAM_FULLCOLOR (camera cull_mask flag bits read by the shaders: other worlds' cameras set
# them), makeEnvironment(bg) (the same settings for other worlds: menu, ending), bloomStrength (current UnrealBloom
# strength), QA params screenshot=/abs/path.png + shotafter=<s> (saves the window image after s seconds of wall
# time, then quits) and quitafter=<s>.
# Not ported (engine plumbing, SPEC §0.2): WebGLRenderer/EffectComposer setup, NaN guard, program sort, two-pass
# twins, skipHiddenRoots, the shadow-map render hook of staticopt.js.
extends RefCounted

const BLOOM := {"strength": 0.45, "radius": 0.55, "threshold": 0.8}
const MIN_PR := 0.6
const BLOOM_KERNELS := [6, 10, 14, 18, 22]
const CAM_NOFOG := 1 << 18
const CAM_FULLCOLOR := 1 << 19
const BG := "#150F1C"

var game
var view: SubViewport
var scene: Node3D
var camera: Camera3D
var env: Environment
var worldEnv: WorldEnvironment
var bloomStrength: float = BLOOM.strength
var postLayer: CanvasLayer
var postRect: ColorRect
var grade: ShaderMaterial
var fog := {"color": Color(BG), "near": 1000.0, "far": 2000.0}

var post := {
	"saturation": 1.0, "damage": 0.0, "static": 0.0, "roll": 0.0, "whiteout": 0.0, "scanlines": 0.0, "crt": 0.0,
	"collapse": 0.0, "vignette": 0.0, "chroma": 0.0, "contrast": 1.06, "warmth": 1.0, "grain": 0.03,
}

var maxPixelRatio := 1.0
var pixelRatio := 1.0
var dynamic := true
var occlusionFade := true
var cameraOverride:
	get:
		return _override

var _fpsAvg := 60.0
var _lowT := 0.0
var _highT := 0.0
var _rollPhase := 0.0
var _override: Camera3D = null
var _overrideAspect := 4.0 / 3.0
var _bloom := {}            # UnrealBloomPass chain: {bright, h: [5], v: [5], comp} = {vp: SubViewport, mat}
var _fx := {}               # owner -> { knobs, until }: temporary effect layers (setFx)
var _eff := {}              # effective knob values of the current frame (render.post + layers)
var _prePasses: Array = []
var _preErrT := -1e9
var _mainHooks: Array = []
var _fogSent := {}
var _t0 := 0
var _shotPath := ""
var _shotAfter := -1.0
var _quitAfter := -1.0
var _shotDone := false
var _afterConnected := false

func _init(g) -> void:
	game = g
	_t0 = Time.get_ticks_msec()
	RenderingServer.set_default_clear_color(Color(0, 0, 0))

	view = SubViewport.new()
	view.name = "WorldView"
	view.use_hdr_2d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	view.use_taa = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	view.positional_shadow_atlas_size = 0
	_buildBloom()

	env = makeEnvironment(Color(BG))
	worldEnv = WorldEnvironment.new()
	worldEnv.name = "WorldEnvironment"
	worldEnv.environment = env
	view.add_child(worldEnv)

	scene = Node3D.new()
	scene.name = "World"
	view.add_child(scene)

	# near 0.1 (was 0.05): twice the depth precision everywhere (trims, decals, frames stop shimmering at range);
	# the camera probe keeps the eye >= 0.23 m from walls and the hero dither-fades under 0.8 m, so nothing clips.
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.rotation_order = EULER_ORDER_XYZ
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 260.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = (1 << Config.LAYERS.WORLD) | (1 << Config.LAYERS.ZOMBIES)
	scene.add_child(camera)
	camera.current = true

	postLayer = CanvasLayer.new()
	postLayer.name = "PostLayer"
	postLayer.layer = -100
	game.add_child(postLayer)
	postRect = ColorRect.new()
	postRect.name = "Grade"
	postRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	postRect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade = ShaderMaterial.new()
	grade.shader = load("res://shaders/post.gdshader")
	grade.set_shader_parameter("tDiffuse", view.get_texture())
	grade.set_shader_parameter("tBloom", _bloom.comp.vp.get_texture())
	grade.set_shader_parameter("uLift", Color(Config.PAL.shadow))
	postRect.material = grade
	postLayer.add_child(postRect)

	var dpr := DisplayServer.screen_get_scale()
	if dpr <= 0.0:
		dpr = 1.0
	maxPixelRatio = minf(1.0, 1.5 / dpr)
	pixelRatio = maxPixelRatio
	game.get_tree().root.size_changed.connect(resize)
	resize()

# Environment with the DEAD AIR settings: flat background colour, no Godot ambient / reflections (the shaders do
# three's hemisphere + RoomEnvironment IBL themselves), linear tone mapping (the grade does ACES), native depth fog
# (only for non-DEAD-AIR materials; ours use render_mode fog_disabled + daFog*), no Godot glow (the bloom is the
# UnrealBloomPass chain of the main view; three renders feeds and other targets without bloom).
static func makeEnvironment(bg: Color) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0, 0, 0)
	e.ambient_light_energy = 0.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.tonemap_white = 1.0
	e.ssao_enabled = false
	e.ssr_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.glow_enabled = false
	e.fog_enabled = false
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_density = 1.0
	e.fog_depth_curve = 1.0
	e.fog_depth_begin = 1000.0
	e.fog_depth_end = 2000.0
	e.fog_sky_affect = 0.0
	e.fog_sun_scatter = 0.0
	e.fog_aerial_perspective = 0.0
	return e

# ---- UnrealBloomPass (see shaders/bloom.gdshader): nested SubViewports, innermost = the world view.
func _stage(name: String, inner: Viewport, mode: int) -> Dictionary:
	var vp := SubViewport.new()
	vp.name = name
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.size = Vector2i(8, 8)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bloom.gdshader")
	m.set_shader_parameter("mode", mode)
	rect.material = m
	vp.add_child(rect)
	if inner != null:
		vp.add_child(inner)
	return {"vp": vp, "mat": m, "rect": rect}

static func _blurKernel(k: int) -> Dictionary:
	var coeff: Array = []
	var sigma := k / 3.0
	for i in k:
		coeff.append(0.39894 * exp(-0.5 * i * i / (sigma * sigma)) / sigma)
	var offsets := PackedFloat32Array()
	var weights := PackedFloat32Array()
	for i in range(1, k, 2):
		var wa: float = coeff[i]
		var wb: float = coeff[i + 1] if i + 1 < k else 0.0
		var w := wa + wb
		offsets.append((i * wa + (i + 1) * wb) / w)
		weights.append(w)
	var n := offsets.size()
	offsets.resize(11)
	weights.resize(11)
	return {"center": coeff[0], "offsets": offsets, "weights": weights, "pairs": n}

func _buildBloom() -> void:
	var inner: Viewport = view
	var bright := _stage("BloomBright", inner, 0)
	bright.mat.set_shader_parameter("colorTexture", view.get_texture())
	bright.mat.set_shader_parameter("luminosityThreshold", BLOOM.threshold)
	bright.mat.set_shader_parameter("smoothWidth", 0.01)
	inner = bright.vp
	var src: Viewport = bright.vp
	var hs: Array = []
	var vs: Array = []
	for i in 5:
		var K := _blurKernel(BLOOM_KERNELS[i])
		var h := _stage("BloomH%d" % i, inner, 1)
		var v := _stage("BloomV%d" % i, h.vp, 1)
		for st in [h, v]:
			st.mat.set_shader_parameter("centerWeight", K.center)
			st.mat.set_shader_parameter("gaussianOffsets", K.offsets)
			st.mat.set_shader_parameter("gaussianWeights", K.weights)
			st.mat.set_shader_parameter("pairs", K.pairs)
		h.mat.set_shader_parameter("colorTexture", src.get_texture())
		h.mat.set_shader_parameter("direction", Vector2(1, 0))
		v.mat.set_shader_parameter("colorTexture", h.vp.get_texture())
		v.mat.set_shader_parameter("direction", Vector2(0, 1))
		hs.append(h)
		vs.append(v)
		src = v.vp
		inner = v.vp
	var comp := _stage("BloomComposite", inner, 2)
	for i in 5:
		comp.mat.set_shader_parameter("blurTexture%d" % (i + 1), vs[i].vp.get_texture())
	comp.mat.set_shader_parameter("bloomStrength", BLOOM.strength)
	comp.mat.set_shader_parameter("bloomRadius", BLOOM.radius)
	game.add_child(comp.vp)
	_bloom = {"bright": bright, "h": hs, "v": vs, "comp": comp}

# UnrealBloomPass.setSize(w, h): half res, then halved per mip (Math.round).
func _resizeBloom(w: int, h: int) -> void:
	if _bloom.is_empty():
		return
	var rx := int(floorf(w / 2.0 + 0.5))
	var ry := int(floorf(h / 2.0 + 0.5))
	_bloom.bright.vp.size = Vector2i(maxi(1, rx), maxi(1, ry))
	_bloom.comp.vp.size = Vector2i(maxi(1, rx), maxi(1, ry))
	for i in 5:
		var sz := Vector2i(maxi(1, rx), maxi(1, ry))
		for st in [_bloom.h[i], _bloom.v[i]]:
			st.vp.size = sz
			st.mat.set_shader_parameter("invSize", Vector2(1.0 / sz.x, 1.0 / sz.y))
		rx = int(floorf(rx / 2.0 + 0.5))
		ry = int(floorf(ry / 2.0 + 0.5))

func init() -> void:
	var p: Dictionary = game.params
	var dr = p.get("dynres")
	dynamic = not (dr != null and float(dr) == 0.0) and not p.get("shot")
	if p.has("screenshot"):
		_shotPath = str(p.screenshot)
		_shotAfter = float(p.get("shotafter", 6.0))
	if p.has("quitafter"):
		_quitAfter = float(p.quitafter)

func reset() -> void:
	for k in ["damage", "static", "roll", "whiteout", "scanlines", "crt", "collapse", "vignette", "chroma"]:
		post[k] = 0.0
	post.saturation = 1.0
	_rollPhase = 0.0
	_fx.clear()
	setCameraOverride(null)

# ---- temporary effect layers (see the header)
func setFx(owner, knobs, opts := {}) -> Dictionary:
	var ttl = opts.get("ttl", INF)
	var L = _fx.get(owner)
	if L == null:
		L = {"knobs": null, "until": INF}
		_fx[owner] = L
	L.knobs = knobs if knobs != null else {}
	L.until = game.time.realNow + maxf(0.0, float(ttl)) if ttl != null and is_finite(float(ttl)) else INF
	return L

func clearFx(owner) -> bool:
	return _fx.erase(owner)

func clearAllFx() -> void:
	_fx.clear()

func hasFx(owner) -> bool:
	return _fx.has(owner)

# render.post combined with the live layers (expired layers are dropped here), written into _eff.
func _effective() -> Dictionary:
	var p := post
	var e := _eff
	for k in ["roll", "chroma", "scanlines", "static", "whiteout", "crt", "collapse", "vignette", "damage", "grain", "saturation"]:
		e[k] = float(p[k])
	if not _fx.is_empty():
		var now: float = game.time.realNow
		for owner in _fx.keys():
			var L: Dictionary = _fx[owner]
			if now > float(L.until):
				_fx.erase(owner)
				continue
			var kn: Dictionary = L.knobs
			for name in kn:
				var v = kn[name]
				if not (v is float or v is int) or not is_finite(float(v)):
					continue
				if name == "saturation":
					e.saturation *= float(v)
				elif e.has(name) and float(v) > float(e[name]):
					e[name] = float(v)
	return e

func _windowSize() -> Vector2i:
	var w: Window = game.get_window()
	var s: Vector2i = w.size if w != null else Vector2i(1280, 720)
	return Vector2i(maxi(1, s.x), maxi(1, s.y))

func resize() -> void:
	_resizeView()
	_updateView()

func _resizeView() -> void:
	var s := _windowSize()
	var w := maxf(1.0, s.x * pixelRatio)
	var h := maxf(1.0, s.y * pixelRatio)
	if _override != null:
		# the override picture is rendered at its own aspect (same height) and letterboxed by the grade
		var screen := float(s.x) / float(s.y)
		if _overrideAspect < screen:
			w = h * _overrideAspect
		else:
			h = w / _overrideAspect
	var size := Vector2i(maxi(1, int(roundf(w))), maxi(1, int(roundf(h))))
	if view.size != size:
		view.size = size
		_resizeBloom(size.x, size.y)
	grade.set_shader_parameter("uRes", Vector2(s.x * pixelRatio, s.y * pixelRatio))

func setPixelRatio(pr: float) -> void:
	var v := clampf(pr, MIN_PR, maxPixelRatio)
	if absf(v - pixelRatio) < 1e-3:
		return
	pixelRatio = v
	resize()

# Render from `camera` into a centered viewport of `aspect` (null restores the gameplay camera).
func setCameraOverride(cam, opts := {}) -> void:
	var aspect: float = float(opts.get("aspect", 4.0 / 3.0))
	_override = cam if cam != null else null
	_overrideAspect = aspect
	if _override != null:
		if not view.is_ancestor_of(_override):
			push_warning("[render] setCameraOverride: the camera is not under game.scene; it cannot render the world")
		_override.current = true
	elif is_instance_valid(camera):
		camera.current = true
	_resizeView()
	_updateView()

func _updateView() -> void:
	if _override == null:
		grade.set_shader_parameter("uView", Vector4(0, 0, 1, 1))
		return
	var s := _windowSize()
	var screen := float(s.x) / float(s.y)
	if _overrideAspect < screen:
		var w := _overrideAspect / screen
		grade.set_shader_parameter("uView", Vector4((1.0 - w) / 2.0, 0, w, 1))
	else:
		var h := screen / _overrideAspect
		grade.set_shader_parameter("uView", Vector4(0, (1.0 - h) / 2.0, 1, h))

# fn(render) runs before the main render each frame; returns an unsubscribe Callable.
func addPrePass(fn: Callable) -> Callable:
	_prePasses.append(fn)
	return func():
		var i := _prePasses.find(fn)
		if i >= 0:
			_prePasses.remove_at(i)

# hook = { before(camera), shadow(), after() } (Dictionary of Callables, all optional); returns an unsubscribe Callable.
func addMainHook(hook: Dictionary) -> Callable:
	_mainHooks.append(hook)
	if not _afterConnected:
		_afterConnected = true
		RenderingServer.frame_post_draw.connect(_onPostDraw)
	return func():
		var i := _mainHooks.find(hook)
		if i >= 0:
			_mainHooks.remove_at(i)

func _runHooks(name: String, arg = null) -> void:
	for h in _mainHooks.duplicate():
		var f = h.get(name)
		if f == null or not (f is Callable) or not f.is_valid():
			continue
		if f.get_argument_count() > 0:
			f.call(arg)
		else:
			f.call()

func _onPostDraw() -> void:
	if not _mainHooks.is_empty():
		_runHooks("after")

func setLayerRecursive(object3d: Node, layer: int) -> void:
	DAU.setLayerRecursive(object3d, layer)

# Four boxes into two mat4 uniforms (materials uOccBox0/1, uOccWall0/1): columns min.xyz + level, max.xyz.
static func _occBoxes(list: Array, n: int) -> Array:
	var cols: Array = []
	for i in 4:
		var b = list[i] if i < n and i < list.size() else null
		if b != null:
			var mn := DAU.v3(b.get("min"))
			var mx := DAU.v3(b.get("max"))
			cols.append(Vector4(mn.x, mn.y, mn.z, float(b.get("level", 0.0))))
			cols.append(Vector4(mx.x, mx.y, mx.z, 0.0))
		else:
			cols.append(Vector4.ZERO)
			cols.append(Vector4.ZERO)
	return [Projection(cols[0], cols[1], cols[2], cols[3]), Projection(cols[4], cols[5], cols[6], cols[7])]

# Camera occlusion uniforms for this main render from camera.gd's cam.occ (NDC ellipse -> view-target pixels,
# occluder boxes). Only when cam.occ was computed for the camera exactly as it renders now. uOccRect is in Godot
# FRAGCOORD pixels (top-left origin: the NDC y is flipped here). Returns true when the fade is on.
func _occBegin() -> bool:
	var M = game.mats
	var U = M.uniforms if M != null else null
	var cam = game.cam
	var o = cam.get("occ") if cam != null else null
	if not occlusionFade or U == null or not U.has("uOccAmt") or o == null or _override != null:
		return false
	if not (float(o.get("amt", 0.0)) > 0.001) or not cam.has_method("occValid") or not cam.occValid(camera):
		return false
	var W := float(view.size.x)
	var H := float(view.size.y)
	var cx := float(o.cx)
	var cy := float(o.cy)
	U.uOccRect.value = Vector4((cx * 0.5 + 0.5) * W, (0.5 - cy * 0.5) * H,
		2.0 / maxf(1e-3, float(o.rx) * W), 2.0 / maxf(1e-3, float(o.ry) * H))
	U.uOccZ.value = Vector4(float(o.zFull), float(o.zSoft), 0.0, float(o.feetY))
	var bx := _occBoxes(o.get("boxes", []), int(o.get("n", 0)))
	U.uOccBox0.value = bx[0]
	U.uOccBox1.value = bx[1]
	var wl := _occBoxes(o.get("walls", []), int(o.get("nw", 0)))
	U.uOccWall0.value = wl[0]
	U.uOccWall1.value = wl[1]
	U.uOccAmt.value = float(o.amt)
	RenderingServer.global_shader_parameter_set("daOccCam", camera.global_position)
	return true

func frame(dt: float) -> bool:
	_dynamicResolution(dt)
	var p := _effective()
	# Roll phase: rolls while `roll` (or the damage hold slip) is up, then settles back on a frame boundary.
	var slip := DAU.smoothstep3(p.damage, 0.65, 1.0)
	var speed: float = p.roll * 1.4 + slip * 0.35
	if speed > 0.001:
		_rollPhase += dt * speed
	else:
		_rollPhase = DAU.damp(_rollPhase, floorf(_rollPhase + 0.5), 6.0, dt)
	_rollPhase = fmod(_rollPhase, 8.0)

	var u := grade
	u.set_shader_parameter("uTime", game.time.realNow)
	u.set_shader_parameter("uSaturation", p.saturation)
	u.set_shader_parameter("uContrast", float(post.contrast))
	u.set_shader_parameter("uWarmth", float(post.warmth))
	u.set_shader_parameter("uGrain", p.grain)
	u.set_shader_parameter("uVignette", p.vignette)
	u.set_shader_parameter("uChroma", p.chroma)
	u.set_shader_parameter("uDamage", p.damage)
	u.set_shader_parameter("uStatic", p.static)
	u.set_shader_parameter("uRoll", p.roll)
	u.set_shader_parameter("uRollPhase", _rollPhase)
	u.set_shader_parameter("uWhiteout", p.whiteout)
	u.set_shader_parameter("uScanlines", p.scanlines)
	u.set_shader_parameter("uCrt", p.crt)
	u.set_shader_parameter("uCollapse", p.collapse)
	bloomStrength = BLOOM.strength + p.whiteout * 2.5
	_bloom.comp.mat.set_shader_parameter("bloomStrength", bloomStrength)

	for fn in _prePasses.duplicate():
		if not (fn is Callable) or not fn.is_valid():
			continue
		if fn.get_argument_count() > 0:
			fn.call(self)
		else:
			fn.call()
	_syncFog()
	# main render: occlusion uniforms + main hooks (the draw itself happens after the scripts in Godot)
	var occ := _occBegin()
	if not occ and game.mats != null and game.mats.uniforms.has("uOccAmt") and float(game.mats.uniforms.uOccAmt.value) != 0.0:
		game.mats.uniforms.uOccAmt.value = 0.0
	if not _mainHooks.is_empty() and _override == null:
		_runHooks("before", camera)
		_runHooks("shadow")
	_qa()
	return true

# THREE scene.fog of game.scene -> daFog* globals (DEAD AIR shaders) + the native fog of `env`.
func _syncFog() -> void:
	var c: Color = DAU.color(fog.color)
	var near := float(fog.near)
	var far := float(fog.far)
	if _fogSent.get("c") == c and _fogSent.get("n") == near and _fogSent.get("f") == far:
		return
	_fogSent = {"c": c, "n": near, "f": far}
	var lin := c.srgb_to_linear()
	RenderingServer.global_shader_parameter_set("daFogColor", Vector3(lin.r, lin.g, lin.b))
	RenderingServer.global_shader_parameter_set("daFogNear", near)
	RenderingServer.global_shader_parameter_set("daFogFar", far)
	env.fog_enabled = far < 999.0
	env.fog_light_color = c
	env.fog_depth_begin = near
	env.fog_depth_end = far

# Drop the pixel ratio in 0.1 steps when the average fps stays < 50 for 2 s; raise it again above 58.
func _dynamicResolution(dt: float) -> void:
	if not dynamic or dt <= 0.0:
		return
	_fpsAvg = lerpf(_fpsAvg, 1.0 / dt, minf(1.0, dt * 2.0))
	_lowT = _lowT + dt if _fpsAvg < 50.0 else 0.0
	_highT = _highT + dt if _fpsAvg > 58.0 else 0.0
	if _lowT > 2.0 and pixelRatio > MIN_PR:
		_lowT = 0.0
		setPixelRatio(pixelRatio - 0.1)
	elif _highT > 2.0 and pixelRatio < maxPixelRatio:
		_highT = 0.0
		setPixelRatio(pixelRatio + 0.1)

# ---- QA helpers (SPEC §2): screenshot=/abs/path.png shotafter=<s>, quitafter=<s> (wall-clock seconds)
func _qa() -> void:
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	if _shotPath != "" and not _shotDone and t >= _shotAfter:
		_shotDone = true
		RenderingServer.frame_post_draw.connect(_saveShot, CONNECT_ONE_SHOT)
	if _quitAfter >= 0.0 and t >= _quitAfter and not (_shotPath != "" and not _shotDone):
		_quitAfter = -1.0
		game.get_tree().quit()

func _saveShot() -> void:
	var img: Image = game.get_viewport().get_texture().get_image()
	if img != null:
		var err := img.save_png(_shotPath)
		print("[render] screenshot ", _shotPath, " ", "ok" if err == OK else "error %d" % err)
	game.get_tree().quit()
