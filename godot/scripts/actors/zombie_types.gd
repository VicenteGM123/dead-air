# Zombie type registry + model builders (GDD §8, §18.8; ARCHITECTURE §10). Port of src/actors/zombieTypes.js.
# Static module (class_name ZombieTypes): ZombieTypes.getType(id), ZombieTypes.acquireModel(game, typeId) … (or
# load("res://scripts/actors/zombie_types.gd").acquireModel(...)).
#
# ZOMBIE_TYPES[typeId] = the type module res://scripts/actors/types/<typeId>.gd merged over FALLBACK[typeId] (so a
# missing / stub module still spawns with the generic build). getType(id) -> type (unknown ids -> tuned_in).
#
# ---------------------------------------------------------------------------------------------------------------
# TYPE MODULE CONTRACT (res://scripts/actors/types/<id>.gd, `extends RefCounted`, instantiated once with .new()
# (no arguments). Its public member variables are the JS data fields, its public methods (names not starting with
# "_") the JS functions; both are merged over FALLBACK into the def Dictionary (functions as Callables:
# z.def.update.call(game, z, dt)). The instance is kept alive in def.module. Declare the FULL parameter lists below
# (GDScript errors when a Callable gets more arguments than it declares). Every field optional unless marked *;
# a module with `var stub := true` or without build() is ignored (fallback build):
#   id*                      'tuned_in' | 'sock_hopper' | 'forecaster' | 'big_shot'
#   height, radius           metres (body capsule for collision / boids / fallback hit zones)
#   dmg, range, windup, cd   generic melee used by the manager when update() does not handle movement
#   spawnMode                'window' (entries) | 'screen' (screen spawns; in the Yard: fence climbs) | 'both'
#   entryFilter(win) -> bool restrict entries (Big Shot: boarded windows + gate)
#   entry(game, z, win) -> { tear:bool=true, time:s, style:'vault'|'squeeze'|'toothpaste'|'blast' } | null
#                            called when the zombie reaches the outside point of its entry. tear:false skips the
#                            boards (Sock Hopper in Hullabaloo: squeeze under them, time 1.0); style 'blast' blows out
#                            every board at once then squeezes (Big Shot toothpaste, time 1.5).
#   hp(round, game) -> number        (the manager may override it with spawn opts.hp, e.g. Hullabaloo socks)
#   speed(round, game) -> m/s
#   build(game, z)*          create z.group (Node3D, feet at y 0, facing -z; the manager adds it to game.scene and
#                            moves/rotates it: its rotation_order becomes YXZ), z.rig, z.animator ({update(dt, state),
#                            kick(amount)}), z.head (Node3D at the head centre), z.headR, optional z.hitZones (format
#                            below), z.model (anything; handed back to release). Put every mesh on LAYERS.ZOMBIES
#                            (DAU.setLayerRecursive). acquireModel()/releaseModel() below pool models by variant.
#   release(game, z)         give z.model back to a pool / free extra objects (clouds, shootables...)
#   update(game, z, dt) -> bool  called every frame in 'chase'/'attack' states; return true when the type moved and
#                            attacked by itself this frame (the manager then skips its steering + melee; it still does
#                            collision-free bookkeeping: area, anti-stuck, animation of z.anim, LOD, separation).
#   updateEntry(game, z, dt) optional flavour during approach/tear/vault/screen states (the manager moves the body).
#   warmup(game) -> Node3D[] samples of the type's meshes (JS Game.precompile; not used by the Godot port).
#   onDamage(game, z, amount, info) -> amount   (info.zone / info.dir / info.head available; ×2 screen and ONE TAKE
#                            are applied by the manager after this hook; return null to keep the amount)
#   onDeath(game, z, info) -> seconds | null   return a duration to play a custom death: the manager then calls
#                            updateDeath(game, z, dt, t) each frame for that long (skipping the default topple + static
#                            dissolve) and finally release + removal. null = default Tuned-In death.
#   points: { killBonus }    extra points on a scoring kill (Forecaster 100, Big Shot 500)
#   oneTakeMul               ONE TAKE damage multiplier instead of the one-hit kill (Big Shot: 5)
#
# z (the zombie record, a Dictionary, see zombies.gd): { id, type, def (this type), pos, vel, yaw, hp, maxHp, state,
#   area, group, rig, animator, radius, height, speed, flags, head, headR, hitZones, model, anim (animator state
#   object: speed, attack, hurt, climb, dead, down...), cd, stun, stagger, round, fromRound, entry }.
#
# HIT ZONES  z.hitZones = [ { shape:'sphere'|'capsule', bone:Node3D, offset:[x,y,z] (bone-local),
#   bone2:Node3D, offset2:[x,y,z] (capsule end, bone2 defaults to bone), r (m), zone:'head'|'torso'|'limb'|<custom>,
#   head:bool (the weapon's head multiplier applies), mul (damage multiplier applied by zombies.damage; limb 0.8) } ]
#   or z.hitTest = Callable(origin, dir, maxDist) -> { dist, zone, head, mul } | null for custom shapes. Missing ->
#   humanoid zones (head sphere on z.head, torso capsule, limb capsules) or, without a rig, one head sphere + body
#   capsule.
# ---------------------------------------------------------------------------------------------------------------
#
# Builders: buildZombie(typeId, game, variant?) -> model { group, rig, animator, head, headR, def, baked, art,
#   variant, cards, bodies, details, gen } (cards / details = meshes hidden by distance LOD); acquireModel(game,
#   typeId, variant?) / releaseModel(model) pool them; humanoidHitZones(model) -> zones; bakedZombieIds(typeId) ->
#   baked art ids.
# ART HOOK: ZOMBIE_ART maps a type to character ids. Ids that are baked (godot/assets/chars/<id>.glb, built through
#   scripts/art/char_runtime.gd buildCharacter) are used, a random variant per spawn. Baked zombies: engine rig +
#   'zombie' Animator, LAYERS.ZOMBIES, static-snow eyes (one shared material, see setEyeMode), cards (ticket stub,
#   patch) listed in model.cards for distance LOD, only the skinned body casts shadows.
# Looks shared by every zombie: setEyeMode('static'|'stars') (ONE TAKE star eyes), setZombieTint(null|'standby')
# (PLEASE STAND BY test-card grey) and setFeedLook(bool) (feed passes: peach skin + plain eyes, GDD §8 common).
#
# Not ported (SPEC §0.2 engine plumbing / dev paths): the primitive placeholder zombie (buildPlaceholderZombie, the
#   `art=0` path: without baked art a type simply cannot build), charRuntime.mergeAttachments / geo.skinRig draw-call
#   merging and the crowd batches (updateCrowd, resetCrowd, crowdWarmup, crowdStats, CROWD_LAYER).
# Node names: ':' is not allowed in Godot node names, so 'part:headCenter' is 'part_headCenter' and
#   'zombie:<type>:<art>' is 'zombie_<type>_<art>'.
class_name ZombieTypes
extends RefCounted

const TYPES_DIR := "res://scripts/actors/types/"
const CHAR_RUNTIME := "res://scripts/art/char_runtime.gd"
const RUNTIME_DIR := "res://assets/runtime/zombies/"
const CHARS_DIR := "res://assets/chars/"
const TYPE_IDS := ["tuned_in", "sock_hopper", "forecaster", "big_shot"]

# Type -> sculpted character ids (src/art/chars/<id>.js), used when baked. See the ART HOOK note above.
const ZOMBIE_ART := {
	"tuned_in": ["z_crew", "z_reporter", "z_disco", "z_mom"],
	"sock_hopper": ["z_sock"],
	"forecaster": ["z_forecaster"],
	"big_shot": ["z_bigshot"],
}
const SHIRTS := ["#C9703A", "#6B8FD6", "#D6B04A", "#9A5AA8", "#5E9E7A", "#D65A5A"]
const FUNCS := ["hp", "speed", "build", "release", "update", "updateEntry", "entry", "entryFilter", "warmup",
	"onDamage", "onDeath", "updateDeath"]

static var ZOMBIE_TYPES := {}
static var _built := false
static var warned := false
static var _crScript = null
static var _crChecked := false
static var _bakedCache := {}

# ------------------------------------------------------------------------------------------ registry
# GDD §7.2 (duplicated from rounds.gd on purpose in the JS: no import cycle rounds <-> types).
static func hpAt(r: int) -> int:
	var R: Dictionary = Config.T.rounds
	if r <= 9:
		return int(R.hpEarlyBase) + int(R.hpEarlyStep) * (maxi(1, r) - 1)
	return int(minf(float(R.hpCap), floorf(float(int(R.hpEarlyBase) + int(R.hpEarlyStep) * 8) * pow(float(R.hpMul), float(r - 9)) + 0.5)))

static func _jsRound(x: float) -> float:
	return floorf(x + 0.5)

# Fallback data per type: used alone while a type module is absent or a stub, and as defaults under a real module.
static func _fallback() -> Dictionary:
	var T: Dictionary = Config.T
	var Z: Dictionary = T.zombies
	var R: Dictionary = T.rounds
	var P = Config.PAL
	return {
		"tuned_in": {
			"id": "tuned_in", "height": 1.62, "radius": 0.36, "dmg": Z.tunedIn.dmg, "range": Z.tunedIn.range,
			"windup": Z.tunedIn.windup, "cd": Z.tunedIn.cd, "spawnMode": "window",
			"rig": {"height": 1.62, "headScale": 1.25, "shoulderW": 0.44, "hipW": 0.28}, "shirts": SHIRTS,
			"hp": func(r, _g = null): return hpAt(int(r)),
			"speed": func(_r = null, _g = null): return float(R.speeds.walk),
		},
		"sock_hopper": {
			"id": "sock_hopper", "height": 1.0, "radius": 0.3, "dmg": Z.sock.dmg, "range": 1.2, "windup": 0.3,
			"cd": Z.sock.cd, "spawnMode": "both",
			"rig": {"height": 1.0, "headScale": 1.0, "shoulderW": 0.3, "hipW": 0.2, "legLen": 0.5},
			"shirts": [P.sockRed, P.sockYellow, P.sockBlue],
			"hp": func(r, _g = null): return int(_jsRound(float(Z.sock.hpMix) * hpAt(int(r)))),
			"speed": func(r, _g = null): return float(Z.sock.speed15) if int(r) >= 15 else float(Z.sock.speed),
			"entry": func(game, _z = null, _win = null):
				return {"tear": false, "time": 1.0, "style": "squeeze"} if game.rounds != null and str(game.rounds.special) == "hullabaloo" else null,
		},
		"forecaster": {
			"id": "forecaster", "height": 1.8, "radius": 0.4, "dmg": Z.forecaster.strikeDmg, "range": 1.5,
			"windup": 0.5, "cd": 1.4, "spawnMode": "screen",
			"rig": {"height": 1.8, "headScale": 1.2, "shoulderW": 0.46}, "shirts": ["#3A6BB5"],
			"hp": func(r, _g = null): return int(_jsRound(float(Z.forecaster.hpMul) * hpAt(int(r)) + float(Z.forecaster.hpAdd))),
			"speed": func(_r = null, _g = null): return float(Z.forecaster.strafe),
			"points": {"killBonus": T.points.forecaster},
		},
		"big_shot": {
			"id": "big_shot", "height": 2.2, "radius": 0.6, "dmg": Z.bigShot.rush.dmg, "range": 1.7, "windup": 0.6,
			"cd": 1.6, "spawnMode": "window",
			"rig": {"height": 2.2, "headScale": 1.3, "shoulderW": 0.62, "hipW": 0.36}, "shirts": ["#5A4A3A"],
			"hp": func(r, _g = null): return maxf(float(Z.bigShot.hpMul) * hpAt(int(r)), float(Z.bigShot.hpMin)),
			"speed": func(_r = null, _g = null): return float(Z.bigShot.speed),
			"entryFilter": func(w): return _f(w, "type") == "boarded" or _f(w, "type") == "gate",
			"entry": func(_game = null, _z = null, _win = null): return {"tear": false, "time": 1.5, "style": "blast"},
			"points": {"killBonus": T.points.bigShot}, "oneTakeMul": 5,
		},
	}

# Generic build/release for stub types: a pooled model (baked art) with humanoid zones.
static func genericBuild(game, z: Dictionary) -> void:
	var m = acquireModel(game, z.type)
	if m == null:
		return
	z.model = m
	z.group = m.group
	z.rig = m.rig
	z.animator = m.animator
	z.head = m.head
	z.headR = m.headR
	z.hitZones = humanoidHitZones(m)

static func genericRelease(_game, z: Dictionary) -> void:
	releaseModel(z.model)
	z.model = null

# The type module instance of res://scripts/actors/types/<id>.gd, or null (absent / failed to load).
static func _loadModule(id: String):
	var path := TYPES_DIR + id + ".gd"
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s == null or not (s is Script) or not s.can_instantiate():
		push_error("[zombies] type module '%s' failed to load" % path)
		return null
	return s.new()

static func _merge(fb: Dictionary, mod) -> Dictionary:
	var def := fb.duplicate()
	var s: Script = mod.get_script()
	for p in s.get_script_property_list():
		var n: String = p.name
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or n.begins_with("_"):
			continue
		def[n] = mod.get(n)
	for m in s.get_script_method_list():
		var n: String = m.name
		if n.begins_with("_"):
			continue
		def[n] = Callable(mod, n)
	def.module = mod           # keeps the RefCounted module alive (bound Callables do not)
	def.fallback = false
	return def

static func _ensure() -> void:
	if _built:
		return
	_built = true
	var FB := _fallback()
	for id in FB:
		var mod = _loadModule(id)
		var real: bool = mod != null and mod.get("stub") != true and mod.has_method("build")
		if real:
			ZOMBIE_TYPES[id] = _merge(FB[id], mod)
		else:
			var d: Dictionary = FB[id].duplicate()
			d.build = genericBuild
			d.release = genericRelease
			d.fallback = true
			ZOMBIE_TYPES[id] = d

# Rebuilds the registry (a type module appeared / changed while the game runs; tests).
static func reload() -> void:
	_built = false
	ZOMBIE_TYPES.clear()
	_bakedCache.clear()
	_ensure()

static func getType(id) -> Dictionary:
	_ensure()
	return ZOMBIE_TYPES.get(id, ZOMBIE_TYPES.tuned_in)

# ------------------------------------------------------------------------------------------ art hook
# scripts/art/char_runtime.gd (static module: buildCharacter(defOrId, opts), getDef(id), characterIds(), charOpt).
static func _cr():
	if not _crChecked:
		_crChecked = true
		if ResourceLoader.exists(CHAR_RUNTIME):
			_crScript = load(CHAR_RUNTIME)
	return _crScript

static func _crHas(name: String) -> bool:
	var s = _cr()
	if s == null:
		return false
	for m in s.get_script_method_list():
		if m.name == name:
			return true
	return false

static func artDef(id: String):
	if _crHas("getDef"):
		var d = _cr().getDef(id)
		if d != null:
			return d
	return null

static func _isBaked(id: String) -> bool:
	if _crHas("characterIds"):
		var ids = _cr().characterIds()
		if ids is Array or ids is PackedStringArray:
			return id in ids
	return ResourceLoader.exists(CHARS_DIR + id + ".glb")

# Baked character ids available for a zombie type (empty when none).
static func bakedZombieIds(typeId, _game = null) -> Array:
	if _bakedCache.has(typeId):
		return _bakedCache[typeId]
	var out: Array = []
	if _crHas("buildCharacter"):
		for id in ZOMBIE_ART.get(typeId, []):
			if _isBaked(id) and (not _crHas("getDef") or artDef(id) != null):
				out.append(id)
	_bakedCache[typeId] = out
	return out

# ------------------------------------------------------------------------------------------ shared looks
static var eyeMat: ShaderMaterial = null
static var starTex = null
static var eyeMode := "static"
static var normalEyeTex = null
static var tinted := {}       # materials used by zombie bodies (for the stand-by tint / feed look) -> true
static var veils := {}        # baked eye-veil materials: full-disc UVs, so ONE TAKE draws its star on them -> true
static var tintMode = null
static var feedLook := false
static var _baseSave := {}    # material -> { color, emissive } (JS mat.userData.zBase / zVeil)
static var _eyePrev = null    # JS eyeMat.userData.prev
static var _shaders := {}

# MeshBasicMaterial equivalent: unlit colour × map (map decoded sRGB -> linear, `color` is LINEAR like THREE's
# setRGB / multiplyScalar results). flip_y (default on): the meshes carry three.js UVs (glTF from the Blender
# pipeline, SPEC §5.3), so the top-down canvas image is sampled at (u, 1 - v) like THREE's flipY textures.
const BASIC_SHADER := """
shader_type spatial;
render_mode unshaded, %s;
uniform sampler2D map : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_map = false;
uniform bool flip_y = true;
uniform vec3 color = vec3(1.0);
void fragment() {
	vec3 c = color;
	if (use_map) { c *= texture(map, vec2(UV.x, flip_y ? 1.0 - UV.y : UV.y)).rgb; }
	ALBEDO = c;
}
"""

static func basicShader(side := "cull_back") -> Shader:
	if not _shaders.has(side):
		var sh := Shader.new()
		sh.code = BASIC_SHADER % side
		_shaders[side] = sh
	return _shaders[side]

# A MeshBasicMaterial-like ShaderMaterial: color = LINEAR Color, map = Texture2D | null, side 'front'|'double'.
static func basicMaterial(color: Color, map = null, side := "front", name := "", flipY := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = basicShader("cull_disabled" if side == "double" else "cull_back")
	m.resource_name = name
	m.set_shader_parameter("flip_y", flipY)
	_basicSet(m, map, color)
	return m

static func _basicSet(m: ShaderMaterial, map, color: Color) -> void:
	m.set_shader_parameter("map", map)
	m.set_shader_parameter("use_map", map != null)
	m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))

static func _staticNoise():
	var g = DAGame.inst
	if g != null and g.tex != null and g.tex.has_method("staticNoise"):
		return g.tex.staticNoise()
	return null

static func zombieEyeMaterial() -> ShaderMaterial:
	if eyeMat == null:
		eyeMat = basicMaterial(Color(1.35, 1.4, 1.45), _staticNoise(), "front", "zombieEyes")
	return eyeMat

# The two static canvas textures are drawn by blender/runtime/zombies.py (makeStarTexture / makeNormalEyeTexture,
# the same canvas code over skia) into res://assets/runtime/zombies/eye_star.png / eye_normal.png.
static func _runtimeTex(file: String):
	var path := RUNTIME_DIR + file
	if not ResourceLoader.exists(path):
		push_warning("[zombies] %s missing (run blender/build_all.py --only runtime)" % path)
		return null
	return load(path)

static func makeStarTexture():
	return _runtimeTex("eye_star.png")

static func makeNormalEyeTexture():
	return _runtimeTex("eye_normal.png")

# 'static' (default) | 'stars' (ONE TAKE). Shared materials, so this is free. Baked eyes map only a small patch of
# the static texture across the disc, so the star goes on their veil (a full-disc overlay) instead.
static func setEyeMode(mode) -> void:
	var m := zombieEyeMaterial()
	eyeMode = "stars" if mode == "stars" else "static"
	if feedLook:
		return
	if eyeMode == "stars":
		if starTex == null:
			starTex = makeStarTexture()
		_basicSet(m, starTex, Color(1.6, 1.5, 1.2))
	else:
		_basicSet(m, _staticNoise(), Color(1.35, 1.4, 1.45))
	applyVeils()

static func applyVeils() -> void:
	var stars := eyeMode == "stars" and not feedLook
	for v in veils:
		if not is_instance_valid(v):
			continue
		if not _baseSave.has(v):
			_baseSave[v] = {"map": matGetMap(v), "color": matGetColor(v)}
		var base: Dictionary = _baseSave[v]
		if stars:
			matSetMap(v, starTex)
			matSetColor(v, Color(1.5, 1.4, 1.15))
		else:
			matSetMap(v, base.map)
			if base.color != null:
				matSetColor(v, base.color)

static func registerVeil(mat) -> void:
	if mat == null or veils.has(mat) or matGetColor(mat) == null:
		return
	veils[mat] = true
	if eyeMode == "stars":
		applyVeils()

static func applyTint() -> void:
	for mat in tinted:
		if not is_instance_valid(mat):
			continue
		if not _baseSave.has(mat):
			_baseSave[mat] = {"color": matGetColor(mat), "emissive": matGetEmissive(mat)}
		var base: Dictionary = _baseSave[mat]
		if base.color == null:
			continue
		var c: Color = base.color
		if base.emissive != null:
			matSetEmissive(mat, base.emissive)
		if feedLook:
			c = Color(c.r * 1.34, c.g * 0.93, c.b * 0.93)
		elif tintMode == "standby":
			# Test-card grey with a faint colour-bar tint: darken + lift toward a cool lilac grey.
			c = Color(c.r * 0.5, c.g * 0.5, c.b * 0.5)
			if base.emissive != null:
				matSetEmissive(mat, Color(0.2, 0.2, 0.25))
		matSetColor(mat, c)

# null | 'standby' (PLEASE STAND BY freeze look). Every zombie body material, so all zombies change at once.
static func setZombieTint(mode) -> void:
	tintMode = mode if mode else null
	applyTint()

# Feed-camera look (GDD §8 common): human peach skin + plain eyes. Call around a feed render: on, render, off.
static func setFeedLook(on) -> void:
	on = _t(on)
	if on == feedLook:
		return
	feedLook = on
	applyTint()
	var m := zombieEyeMaterial()
	if on:
		if normalEyeTex == null:
			normalEyeTex = makeNormalEyeTexture()
		_eyePrev = {"map": m.get_shader_parameter("map"), "color": m.get_shader_parameter("color")}
		_basicSet(m, normalEyeTex, Color(1, 1, 1))
	elif _eyePrev != null:
		var col: Vector3 = _eyePrev.color
		_basicSet(m, _eyePrev.map, Color(col.x, col.y, col.z))
	applyVeils()

static func registerTint(mat) -> void:
	if mat == null or tinted.has(mat) or matGetColor(mat) == null:
		return
	tinted[mat] = true
	if tintMode or feedLook:
		applyTint()

# --- material colour access (THREE mat.color / mat.emissive / mat.map; colours handled LINEAR like THREE) -------
# BaseMaterial3D: albedo_color / emission (sRGB-encoded Colors) and albedo_texture. ShaderMaterial: the first
# uniform among the names below; a `source_color` (Color-typed) uniform is sRGB-encoded, a vec3 one linear.
const COLOR_UNIFORMS := ["color", "diffuse", "albedo", "albedo_color", "uColor", "base_color"]
const EMISSIVE_UNIFORMS := ["emissive", "emission", "uEmissive", "emissive_color"]
const MAP_UNIFORMS := ["map", "albedo_texture", "texture_albedo", "uMap"]

static func _uniform(mat: ShaderMaterial, names: Array):
	if mat.shader == null:
		return null
	var list := mat.shader.get_shader_uniform_list()
	for n in names:
		for u in list:
			if u.name == n:
				return u
	return null

static func _readColor(mat: ShaderMaterial, u):
	var v = mat.get_shader_parameter(u.name)
	if v is Color:
		return v.srgb_to_linear() if u.type == TYPE_COLOR else v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	if v is Vector4:
		return Color(v.x, v.y, v.z, v.w)
	return Color(1, 1, 1) if v == null and u.type == TYPE_VECTOR3 else (Color(1, 1, 1) if v == null else null)

static func _writeColor(mat: ShaderMaterial, u, c: Color) -> void:
	match u.type:
		TYPE_COLOR:
			mat.set_shader_parameter(u.name, c.linear_to_srgb())
		TYPE_VECTOR4:
			mat.set_shader_parameter(u.name, Vector4(c.r, c.g, c.b, c.a))
		_:
			mat.set_shader_parameter(u.name, Vector3(c.r, c.g, c.b))

static func matGetColor(mat):
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color.srgb_to_linear()
	if mat is ShaderMaterial:
		var u = _uniform(mat, COLOR_UNIFORMS)
		return _readColor(mat, u) if u != null else null
	return null

static func matSetColor(mat, c: Color) -> void:
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).albedo_color = Color(c.r, c.g, c.b, (mat as BaseMaterial3D).albedo_color.a).linear_to_srgb()
	elif mat is ShaderMaterial:
		var u = _uniform(mat, COLOR_UNIFORMS)
		if u != null:
			_writeColor(mat, u, c)

static func matGetEmissive(mat):
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).emission.srgb_to_linear() if (mat as BaseMaterial3D).emission_enabled else null
	if mat is ShaderMaterial:
		var u = _uniform(mat, EMISSIVE_UNIFORMS)
		return _readColor(mat, u) if u != null else null
	return null

static func matSetEmissive(mat, c: Color) -> void:
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).emission = c.linear_to_srgb()
	elif mat is ShaderMaterial:
		var u = _uniform(mat, EMISSIVE_UNIFORMS)
		if u != null:
			_writeColor(mat, u, c)

static func matGetMap(mat):
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		var u = _uniform(mat, MAP_UNIFORMS)
		return mat.get_shader_parameter(u.name) if u != null else null
	return null

static func matSetMap(mat, t) -> void:
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).albedo_texture = t
	elif mat is ShaderMaterial:
		var u = _uniform(mat, MAP_UNIFORMS)
		if u != null:
			mat.set_shader_parameter(u.name, t)
			if _uniform(mat, ["use_map"]) != null:
				mat.set_shader_parameter("use_map", t != null)

# The material a mesh draws with (override first, like the JS o.material after a swap).
static func meshMaterial(o: MeshInstance3D):
	if o.material_override != null:
		return o.material_override
	if o.mesh == null or o.mesh.get_surface_count() == 0:
		return null
	var m = o.get_surface_override_material(0)
	return m if m != null else o.mesh.surface_get_material(0)

static func isSkinned(o: Node) -> bool:
	return o is MeshInstance3D and ((o as MeshInstance3D).skin != null or o.get_parent() is Skeleton3D)

# JS Array.isArray(o.material): a multi-material mesh (the ticket stub / patch cards: face + edge materials).
static func isMultiMaterial(o: MeshInstance3D) -> bool:
	return o.mesh != null and o.mesh.get_surface_count() > 1

static func _matName(m) -> String:
	if m == null:
		return ""
	var n: String = m.resource_name
	if n == "" and m.has_meta("extras"):
		var ex = m.get_meta("extras")
		if ex is Dictionary and ex.has("da"):
			var da = ex.da
			if da is String:
				da = JSON.parse_string(da)
			if da is Dictionary:
				var o = da.get("opts", {})
				if o is Dictionary and o.get("name") is String:
					n = o.name
	return n

# ------------------------------------------------------------------------------------------ builders
# variant = index into the type's baked art ids (default: random). Returns the model record (see header), or null
# when no baked art can be built (the placeholder is not ported).
static func buildZombie(typeId, game, variant := -1):
	var def := getType(typeId)
	var ids := bakedZombieIds(def.id, game)
	if ids.size() > 0:
		var k: int = variant % ids.size() if variant >= 0 else int(floorf(randf() * ids.size()))
		var m = buildBakedZombie(def, ids[k], game)
		if m != null:
			return m
		if not warned:
			warned = true
			push_warning("[zombies] baked zombie '%s' failed" % ids[k])
	return null

static func _ud(n: Node) -> Dictionary:
	return DAU.ud(n)

static func buildBakedZombie(def: Dictionary, artId: String, game):
	var CR = _cr()
	if CR == null:
		return null
	var M = game.mats
	var opts := {"layer": Config.LAYERS.ZOMBIES, "animator": "zombie"}
	if M != null:
		var env = _f(M, "envMap")
		if env != null:
			opts.envMap = env
		var uni = _f(M, "uniforms")
		if uni != null:
			opts.globals = uni
	var ad = artDef(artId)
	var c = CR.buildCharacter(ad if ad != null else artId, opts)
	if c == null:
		return null
	var anim = _f(c, "animator")
	if anim == null or not (anim is Object) or not anim.has_method("update"):
		push_warning("[zombies] '%s' has no animator" % artId)
		return null
	var group: Node3D = _f(c, "group")
	var rig = _f(c, "rig")
	var eyes := zombieEyeMaterial()
	var cards: Array = []
	var bodies: Array = []
	var details: Array = []
	DAU.traverse(group, func(o):
		if not (o is MeshInstance3D):
			return
		var mi := o as MeshInstance3D
		if _ud(mi).get("staticEye"):
			mi.material_override = eyes
		var sk := isSkinned(mi)
		if sk:
			bodies.append(mi)
			registerTint(meshMaterial(mi))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sk else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not sk and isMultiMaterial(mi):
			cards.append(mi))
	# Distance LOD: the eye veil and rim are only drawn up close (model.details).
	DAU.traverse(group, func(o):
		if not (o is MeshInstance3D) or bodies.has(o) or cards.has(o):
			return
		var mn := _matName(meshMaterial(o))
		var nn := String(o.name)
		var veil := mn == "zombieEyeVeil" or nn.begins_with("staticEyeVeil")
		var rim := mn == "zombieEyeRim" or nn.begins_with("staticEyeRim")
		if veil or rim:
			details.append(o)
		if veil:
			registerVeil(meshMaterial(o)))
	var J = _f(rig, "joints", {})
	var dims = _f(rig, "dims")
	var headR: float = (float(_f(dims, "headH", 0.5)) if dims != null else 0.5) * 0.5
	var head := DAU.node3d("part_headCenter")
	head.position = Vector3(0, headR * 0.98, 0)
	var hj = _f(J, "head")
	(hj if hj != null else _f(rig, "root")).add_child(head)
	group.name = "zombie_%s_%s" % [def.id, artId]
	DAU.setLayerRecursive(group, Config.LAYERS.ZOMBIES)
	return {"group": group, "rig": rig, "animator": anim, "head": head, "headR": headR, "def": def, "baked": true,
		"art": c, "variant": artId, "cards": cards, "bodies": bodies, "details": details, "gen": modelGen()}

# ------------------------------------------------------------------------------------------ model pool
# Models are pooled per type + variant (building a sculpted zombie costs a few ms). Every model carries the
# charOpt.gen it was built under; stale pooled models are dropped instead of reused.
static var pools := {}

static func modelGen() -> int:
	var CR = _cr()
	if CR != null:
		var o = CR.get("charOpt")
		if o is Dictionary:
			return int(o.get("gen", 0))
	return 0

static func poolKey(typeId, variant) -> String:
	return "%s|%s" % [typeId, variant]

# A brand-new model of one variant name (an art id; 'placeholder' is not ported -> null), bypassing the pool.
static func buildVariant(game, typeId, name):
	var def := getType(typeId)
	if name == "placeholder":
		return null
	var ids := bakedZombieIds(def.id, game)
	var k := ids.find(name)
	return buildZombie(def.id, game, k) if k >= 0 else null

# variant: art id / index, or -1 = random among the baked ones. Returns a model ready to be added to the scene
# (null without baked art).
static func acquireModel(game, typeId, variant = -1):
	var def := getType(typeId)
	var ids := bakedZombieIds(def.id, game)
	var name := "placeholder"
	if ids.size() > 0:
		if variant is String or variant is StringName:
			name = variant
		else:
			var v := int(variant) if variant != null else -1
			name = ids[v % ids.size() if v >= 0 else int(floorf(randf() * ids.size()))]
	var list = pools.get(poolKey(def.id, name))
	while list != null and list.size() > 0:
		var m = list.pop_back()
		if int(m.get("gen", 0)) == modelGen():
			return m
	if name == "placeholder":
		return null
	var k := ids.find(name)
	return buildZombie(def.id, game, k)

static func releaseModel(model) -> void:
	if model == null or not (model is Dictionary) or model.get("group") == null:
		return
	DAU.detach(model.group)
	resetModelPose(model)
	var key := poolKey(model.def.id, model.variant)
	if not pools.has(key):
		pools[key] = []
	var list: Array = pools[key]
	if list.size() < 30 and int(model.get("gen", 0)) == modelGen():
		list.append(model)

# Pre-builds n models per variant of a type into the pool (called once per game so the first wave never hitches).
static func prewarmModels(game, typeId, n := 3) -> void:
	var def := getType(typeId)
	var ids := bakedZombieIds(def.id, game)
	for name in ids:
		var key := poolKey(def.id, name)
		if not pools.has(key):
			pools[key] = []
		var list: Array = pools[key]
		for i in range(list.size() - 1, -1, -1):
			if int(list[i].get("gen", 0)) != modelGen():
				list.remove_at(i)
		while list.size() < n:
			var m = buildZombie(def.id, game, ids.find(name))
			if m == null:
				break
			list.append(m)

static func resetModelPose(model: Dictionary) -> void:
	var g: Node3D = model.group
	g.visible = true
	g.scale = Vector3.ONE
	g.rotation = Vector3.ZERO
	g.position = Vector3.ZERO
	var rig = model.get("rig")
	var J = _f(rig, "joints") if rig != null else null
	if J != null:
		for j in (J.values() if J is Dictionary else []):
			if j is Node3D:
				j.scale = Vector3.ONE
		var root = _f(rig, "root")
		if root is Node3D:
			root.rotation = Vector3.ZERO
			root.scale = Vector3.ONE
	var a = model.get("animator")
	if a is Object and "override" in a:
		a.set("override", null)
	for c in model.get("cards", []):
		if is_instance_valid(c):
			c.visible = true
	for c in model.get("details", []):
		if is_instance_valid(c):
			c.visible = true

# Humanoid hit zones for a rig model (see HIT ZONES in the header).
static func humanoidHitZones(model):
	var rig = _f(model, "rig")
	var J = _f(rig, "joints") if rig != null else null
	if J == null or _f(J, "hips") == null:
		return null
	var D = _f(rig, "dims", {})
	var sw: float = float(_f(D, "shoulderW", 0.42)) if _f(D, "shoulderW") else 0.42
	var zones: Array = [
		{"shape": "sphere", "bone": _f(model, "head"), "offset": [0, 0, 0], "r": float(_f(model, "headR")) * 0.98, "zone": "head", "head": true, "mul": 1},
		{"shape": "capsule", "bone": J.hips, "offset": [0, -0.02, 0], "bone2": J.neck, "offset2": [0, -0.02, 0], "r": maxf(0.16, sw * 0.44), "zone": "torso", "head": false, "mul": 1},
	]
	for s in ["L", "R"]:
		zones.append({"shape": "capsule", "bone": J["shoulder" + s], "offset": [0, 0, 0], "bone2": J["hand" + s], "offset2": [0, -0.07, 0], "r": 0.085, "zone": "limb", "head": false, "mul": 0.8})
		zones.append({"shape": "capsule", "bone": J["hip" + s], "offset": [0, 0, 0], "bone2": J["foot" + s], "offset2": [0, 0, 0], "r": 0.1, "zone": "limb", "head": false, "mul": 0.8})
	return zones

# ------------------------------------------------------------------------------------------ helpers
# JS truthiness (!!v): null/false/0/NaN/"" are false; objects, arrays and dictionaries are true.
static func _t(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0 and not is_nan(v)
	if v is String or v is StringName:
		return v != ""
	return true

# JS `o.k` on a Dictionary or an Object (null / d when missing).
static func _f(o, k: String, d = null):
	if o is Dictionary:
		return o.get(k, d)
	if o is Object:
		var v = o.get(k)
		return d if v == null else v
	return d
