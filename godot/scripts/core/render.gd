# Renderer, post pipeline, resize and dynamic resolution (port of src/core/render.js; ARCHITECTURE §5/§12, GDD §3.9,
# §14).
#
# Pipeline (Godot): the 3D world renders into `view`, an HDR SubViewport (use_hdr_2d: linear half-float, 4x MSAA,
# sized window x pixelRatio) whose camera environment has the bloom (Godot glow tuned to UnrealBloom strength 0.45,
# radius 0.55, threshold 0.8; linear tone mapper, exposure 1: the image stays linear HDR). A full-screen ColorRect on
# a CanvasLayer (layer -100, under every UI layer) shows it through shaders/post.gdshader = the GradePass, which
# works in linear HDR and ends with three's ACES Filmic (toneMappingExposure 1.05) + sRGB, exactly like the JS
# pass that folds the OutputPass in. It implements every `render.post` knob:
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
# Godot-only plumbing (no JS counterpart): `view` (SubViewport), `env` (main camera Environment: background, bloom),
# `envFeed` (the WorldEnvironment of the shared World3D, no bloom: feed cameras use it), `fog` (THREE scene.fog of
# game.scene: {color: Color sRGB, near, far}; lights.gd drives it, frame() uploads daFog* + the native fog of both
# environments for non-DEAD-AIR materials), CAM_NOFOG / CAM_FULLCOLOR (camera cull_mask flag bits read by the
# shaders), makeEnvironment(bg, glow), QA params screenshot=/abs/path.png + shotafter=<s> (saves the window
# image after s seconds of wall time, then quits) and quitafter=<s>.
# Not ported (engine plumbing, SPEC §0.2): WebGLRenderer/EffectComposer setup, NaN guard, program sort, two-pass
# twins, skipHiddenRoots, the shadow-map render hook of staticopt.js.
extends RefCounted

const BLOOM := {"strength": 0.45, "radius": 0.55, "threshold": 0.8}
const MIN_PR := 0.6
# Godot glow intensity per unit of UnrealBloom strength (tuned against JS renders: tools/material_test).
const BLOOM_GAIN := 1.0
const CAM_NOFOG := 1 << 18
const CAM_FULLCOLOR := 1 << 19
const BG := "#150F1C"

var game
var view: SubViewport
var scene: Node3D
var camera: Camera3D
var env: Environment
var envFeed: Environment
var worldEnv: WorldEnvironment
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
var _overrideEnv = null
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
	game.add_child(view)

	# The shared World3D's default environment (feed cameras, anything without its own): no bloom.
	envFeed = makeEnvironment(Color(BG), false)
	worldEnv = WorldEnvironment.new()
	worldEnv.name = "WorldEnvironment"
	worldEnv.environment = envFeed
	view.add_child(worldEnv)
	env = makeEnvironment(Color(BG), true)

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
	camera.environment = env
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
# (only for non-DEAD-AIR materials; ours use render_mode fog_disabled + daFog*), optional bloom.
static func makeEnvironment(bg: Color, glow: bool) -> Environment:
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
	e.fog_enabled = false
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_density = 1.0
	e.fog_depth_curve = 1.0
	e.fog_depth_begin = 1000.0
	e.fog_depth_end = 2000.0
	e.fog_sky_affect = 0.0
	e.fog_sun_scatter = 0.0
	e.fog_aerial_perspective = 0.0
	e.glow_enabled = glow
	if glow:
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		e.glow_normalized = false
		e.glow_hdr_threshold = BLOOM.threshold
		e.glow_hdr_scale = 0.01
		e.glow_hdr_luminance_cap = 256.0
		e.glow_bloom = 0.0
		e.glow_strength = 1.0
		e.glow_intensity = BLOOM.strength * BLOOM_GAIN
		for i in 7:
			e.set_glow_level(i, _bloomLevel(i))
	return e

# UnrealBloomPass composite factors: mix(factor, 1.2 - factor, radius) for its 5 mips (1.0 0.8 0.6 0.4 0.2).
# Godot level i+1 has about the reach of Unreal mip i (half-res mip chain, blurred once per level).
static func _bloomLevel(i: int) -> float:
	var F := [1.0, 0.8, 0.6, 0.4, 0.2]
	var j := i - 1
	if j < 0 or j >= F.size():
		return 0.0
	var f: float = F[j]
	return lerpf(f, 1.2 - f, BLOOM.radius)

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
	var w := game.get_window()
	var s := w.size if w != null else Vector2i(1280, 720)
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
	if _override != null and _override != cam and is_instance_valid(_override):
		_override.environment = _overrideEnv
	var prev := _override
	_override = cam if cam != null else null
	_overrideAspect = aspect
	if _override != null:
		if prev != _override:
			_overrideEnv = _override.environment
		_override.environment = env
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
	env.glow_intensity = (BLOOM.strength + p.whiteout * 2.5) * BLOOM_GAIN

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

# THREE scene.fog of game.scene -> daFog* globals (DEAD AIR shaders) + the native fog of both environments.
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
	for e in [env, envFeed]:
		e.fog_enabled = far < 999.0
		e.fog_light_color = c
		e.fog_depth_begin = near
		e.fog_depth_end = far

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
	var img := game.get_viewport().get_texture().get_image()
	if img != null:
		var err := img.save_png(_shotPath)
		print("[render] screenshot ", _shotPath, " ", "ok" if err == OK else "error %d" % err)
	game.get_tree().quit()
