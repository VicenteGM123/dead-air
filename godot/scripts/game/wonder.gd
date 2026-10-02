# Wonder weapons + signal colors: game.wonder (GDD §9.3 Tiny Tele, §9.4 Zapper / Boom Mic / Chroma-Key, §9.5 upgraded
# versions, §10.4 signal colors, §15 audio ids). Port of src/game/wonder.js (owned by the wonder engineer).
#
# INTEGRATION: an ordinary system here (game.gd SYSTEMS / INIT_ORDER / UPDATE_ORDER right after 'weapons'). The JS
#   install(game) hook is not ported: its side effects live in init() (resources + listeners), reset() and the
#   'game:start' reset. update(dt) runs once per frame from Game's UPDATE_ORDER.
#
# API (weapons.gd delegates every weapon whose def.fire is 'custom': zapper, boom_mic, chroma_key)
#   fire(weaponId, ctx) -> bool   every frame while the weapon is held (weapons ctx Dictionary: { def, upgraded, signal,
#       slot, origin, dir (camera aim ray), muzzle, aimPoint, aimDist, triggerDown, triggerPressed, triggerReleased, ads,
#       dt, ready, model }). Returns true when a click / shot / playback went off this frame. Wonder owns its weapons'
#       ammo (slot.mag--, reload moves reserve -> mag), empty-mag reloads and dry fire, and emits weapon:fire /
#       weapon:reload / weapon:empty itself (weapons detects that and only adds the model spring + crosshair bloom).
#   reload(weaponId, ctx) -> seconds   starts the battery / reel-swap / goo-cartridge reload (0 = refused: full, no
#       reserve, recording); weapons mirrors reloading / reloadId / reloadProgress for the pose.
#   holster(weaponId) / equip(weaponId)   weapons hooks: holstering cancels a recording (charge lost) or a reload.
#   throwTele(ctx?) -> bool   Q. ctx = { origin (left hand), dir, velocity, aimPoint } from weapons, which already
#       took one from weapons.teles; without ctx (tests / self-drive) wonder consumes one itself. Plays tele_throw.
#   reloading, reloadId, reloadProgress (0..1), recording (Boom Mic held), charge (0..10), busy(weaponId) -> bool,
#   isWonder(id), applySignal(z, signal, {weaponId, splash}), teles (live Tiny Teles), init(), reset(), update(dt)
#   (world dt).
#   debug: trigger(down|null) (a simulated trigger, also through weapons), step(seconds) (advances wonder + fx
#   with time.scale 0, for stepped screenshots), gag(z|id, name), key(z|id, world, upgraded), tumble(z|id),
#   tele(x, z), signal_(z|id, s), burn/laugh/freeze(z|id), state() (actors, hidden, status, blobs, puddles, puddleAt,
#   teles [{state, pos, seated, sat (plopped down), live, yaw}], lastZap ...).
# Numbers: ctx.def wins (weapon_defs: cone/spread, range, chain, chainR, killUpTo, dmg, bossDmg, stunPulse, record,
#   playback, blob, splash, puddle, worlds, mag, reload); the G table below mirrors GDD §9.3–9.5 as the fallback.
#
# Events emitted: weapon:fire {weaponId, upgraded} (audio voices wpn_zapper / wpn_chroma_fire; the Boom Mic plays
#   wpn_boom_playback itself), weapon:reload {weaponId}, weapon:empty {weaponId}, wonder:gag {z, gag},
#   wonder:key {z, world}, wonder:tele {state:'land'|'implode', pos}, wonder:signal {z, signal, weaponId, splash}.
# Listens: zombie:hit (x1.5 while laughing / frozen; signal-color roll of upgraded weapons: weapons.hit.primary only,
#   weapons.slots[].signal, half chance on splash targets, cooldown per weapon + color; wonder weapons roll too),
#   zombie:kill (Cold Open shatter), game:start (reset).
#
# Zombie contract used (defensive; ARCHITECTURE §10): zombies.alive [{ id, hp, maxHp, pos, yaw, group, head, height,
#   radius, speed, state, type, anim, animator {override, kick}, stun }], zombies.damage(z, amount, {
#   weaponId, cause, dir, point, upgraded }) -> killed, zombies.raycast, zombies.stun(z, s) (stars), zombies.setLure.
#   Wonder deaths: the zombie's pose is cloned (Node.duplicate: Skeleton3D bone poses are copied) and the original
#   hidden BEFORE zombies.damage runs (info.corpse = false, so the manager skips its own death visuals: topple, stars,
#   confetti); the clone performs the five channel gags, the keyed swirl, the playback tumble or the tele implosion.
#   Status effects write temporary state and restore it: z.speed (record slow 35 %, Cold Open on specials 50 %),
#   z.stun (seated, laughing, frozen, panicking; direct writes, no stars), z.animator.override (poses),
#   z.animator.updateFn (frozen solid: rig.gd's assignable update), mesh materials (material_override: ice, static,
#   bars). Damage bonuses lower z.hp directly unless lethal (then zombies.damage with cause 'signal_bonus').
#
# PORT NOTES (GDScript / Godot plumbing; behaviour is the JS one):
#   * Zombies are Dictionaries: maps / sets keyed by zombie (JS Map / Set) are keyed by z.id here (_zk), identity
#     tests use is_same(). Every optional field is read through _g() (Dictionary key or Object property).
#   * Frozen solid (Cold Open): the JS replaced z.animator.update with a no-op; rig.gd makes `update` assignable as
#     the Callable field animator.updateFn (see its header), so the freeze swaps updateFn and restores it.
#   * Boss adapter (actors/boss.js wraps wonder._zombies()): set game.wonder._zombiesHook = func(list) -> list
#     (e.g. list + [proxy]) while the fight runs, reset it to Callable() when it ends.
#   * fxMaterial (MeshBasicMaterial patched by onBeforeCompile) = a Godot spatial shader (FX_SHADER) with one #define
#     per kind; gl_FragCoord is rebuilt bottom-up from FRAGCOORD / VIEWPORT_SIZE so the JS maths is unchanged, the
#     footage frame (uFxFrame) is passed in NDC and turned into pixels in the shader.
#   * Instanced pools (THREE.InstancedMesh) = MultiMeshInstance3D with per-instance colours (linear, like three's).
#   * Static meshes (tumbleweed, gelatin mold, bunny, battery, flame, puddle blobs, squiggle, rings, rounded cube,
#     spheres) come from Blender: blender/runtime/wonder.py -> res://assets/runtime/wonder/*.glb.
#   * Not ported (engine plumbing, SPEC §0.2): warmup() / _warmStatic / _warmZombie / _compile (shader precompile)
#     and the zombie:spawn warm-up listener. _registerCues: the four wonder_* WebAudio recipes (fwoomp, yeowch,
#     freeze, shatter) are rendered offline by tools/audio like every other cue; here it only checks they exist.
#   * polygonOffset on the puddle / splat layers has no Godot material equivalent (the layers keep their JS
#     geometric offsets).
# RENAMES (§3.2): debug.signal -> debug.signal_. Node names 'wonder:corpse' / 'wonder:flame' / 'wonder:tiny_tele' /
#   'wonder:pool:*' -> 'wonder_*' (':' is not allowed in Godot node names).
extends RefCounted

const WONDER := ["zapper", "boom_mic", "chroma_key"]
const SPECIALS := ["sock_hopper", "forecaster", "big_shot"]
const STANDERS := ["forecaster", "big_shot"]
const GAGS := ["cartoon", "western", "cooking", "nature", "signoff"]
const WORLDS := ["space", "beach", "volcano", "underwater"]
const WORLDS_UP := ["desert", "moon"]
const WORLD_TINT := {"space": "#B9A8FF", "beach": "#7FE7FF", "volcano": "#FF8A3C", "underwater": "#5FE3FF", "desert": "#FFC98A", "moon": "#E8E4F0"}
# Where the keyed silhouette looks into each world card (texture uv, y up): its most iconic bit, since a body is
# only ~0.35 card-heights wide (ringed planet, sun + sea + beach umbrella, the cone, the fish, the sliced sun, Earth).
const WORLD_FOCUS := {"space": [0.66, 0.53], "beach": [0.74, 0.5], "volcano": [0.5, 0.52], "underwater": [0.56, 0.52], "desert": [0.31, 0.44], "moon": [0.75, 0.52]}
const SIGNALS := ["hot_mic", "laugh_track", "cold_open"]
const DEG := PI / 180.0
const UP := Vector3(0, 1, 0)
const ZAXIS := Vector3(0, 0, 1)
const RT := "res://assets/runtime/wonder/"

# GDD §9.3–9.5 numbers. ctx.def wins when the weapons table carries the field (mag, reserve, reload, range, chain...).
const G := {
	"zapper": {"cone": [5, 2], "range": [25, 40], "rangeUp": [35, 50], "chain": 3, "chainUp": 6, "hop": 4, "interval": 0.45, "killUpTo": 25,
		"killUpToUp": 35, "dmg": 6000, "dmgUp": 12000, "stun": 1, "boss": 2000, "pulseR": 2.5, "pulseStun": 1.5, "reload": 1.6},
	"boom": {"rec": 3, "recCone": 40, "recRange": 12, "slow": 0.35, "base": 1, "per": 2, "bossCount": 3, "max": 10, "cone": 50, "range": 15, "killAt": 3,
		"killUpTo": 30, "killUpToUp": 40, "late": 8000, "weak": 500, "knock": 4, "weakStun": 1.5, "boss": 700, "recover": 0.8, "reload": 2.5},
	"chroma": {"r": 0.18, "speed": 22, "grav": 6, "fuse": 2, "splash": 3, "splashUp": 4.5, "puddleR": 3, "puddleT": 4, "puddleTUp": 8, "puddleN": 6,
		"puddleNUp": 10, "killUpTo": 25, "killUpToUp": 35, "late": 6000, "boss": 3000, "interval": 0.7, "reload": 2.2},
	"tele": {"lure": 15, "fuse": 6, "killR": 4, "killUpTo": 30, "late": 20000, "seatR": 2.2, "speed": 10.5, "up": 3.4, "grav": 18, "scale": 1.55},
}
const MAGS := {"zapper": [13, 52, 21, 126], "boom_mic": [2, 12, 3, 18], "chroma_key": [6, 36, 10, 60]}

# ------------------------------------------------------------------------------------------------ fx shader
# MeshBasicMaterial patched per kind: 'flat' (solid color), 'static' (TV snow), 'bars' (SMPTE bars) and 'footage'
# (the Chroma-Key stock-footage window: a world_* card sampled with screen-space UVs), all with a fresnel rim.
# Works on skinned clones (Godot skins before the material). fc = gl_FragCoord (bottom-up pixels).
const FX_SHADER := """
render_mode unshaded, fog_disabled, cull_back;
uniform vec3 uFxColor : source_color = vec3(1.0);
uniform float uFxIntensity = 1.0;
uniform vec3 uFxRim : source_color = vec3(1.0);
uniform float uFxRimK = 0.5;
uniform float uFxTime = 0.0;
uniform sampler2D uFxMap : source_color, filter_linear_mipmap, repeat_disable;
uniform float uFxWorld = 0.0;
uniform vec3 uFxFrame = vec3(0.0, 0.0, 0.8333);
uniform vec2 uFxFocus = vec2(0.5, 0.5);
float fxHash( vec2 p ) { return fract( sin( dot( p, vec2( 12.9898, 78.233 ) ) ) * 43758.5453 ); }
vec3 fxBar( float i ) {
	if ( i < 0.5 ) return vec3( 0.84, 0.84, 0.84 );
	if ( i < 1.5 ) return vec3( 0.9, 0.75, 0.05 );
	if ( i < 2.5 ) return vec3( 0.05, 0.67, 0.75 );
	if ( i < 3.5 ) return vec3( 0.08, 0.64, 0.06 );
	if ( i < 4.5 ) return vec3( 0.67, 0.08, 0.67 );
	if ( i < 5.5 ) return vec3( 0.78, 0.07, 0.05 );
	return vec3( 0.05, 0.1, 0.78 );
}
void fragment() {
	vec2 res = VIEWPORT_SIZE;
	vec2 fc = vec2( FRAGCOORD.x, res.y - FRAGCOORD.y );
	vec3 c = uFxColor * uFxIntensity;
#ifdef FX_STATIC
	float n = fxHash( floor( fc / 3.0 ) + floor( uFxTime * 30.0 ) * 17.31 );
	c = vec3( n * n ) * 1.8;
#endif
#ifdef FX_BARS
	c = fxBar( floor( mod( fc.x / max( 6.0, res.x / 56.0 ) + floor( uFxTime * 12.0 ), 7.0 ) ) ) * 1.35;
#endif
#ifdef FX_FOOTAGE
	// screen-space UVs framed on the keyed zombie (uFxFrame = its projected centre + height, NDC), so the silhouette
	// is a window onto the world card around uFxFocus (its iconic bit) and the footage stays put while the body moves
	vec2 fpx = ( uFxFrame.xy * 0.5 + 0.5 ) * res;
	float fh = max( 8.0, uFxFrame.z * 0.5 * res.y );
	vec2 uv = ( fc - fpx ) / max( fh, 8.0 );
	uv = vec2( uv.x * 0.7 / 1.7778, uv.y * 0.7 ) + uFxFocus;
	float w = uFxWorld;
	float t = uFxTime;
	if ( w < 0.5 ) uv += vec2( sin( t * 0.6 ), cos( t * 0.5 ) ) * 0.012;
	else if ( w < 1.5 ) uv.x += sin( uv.y * 40.0 + t * 3.0 ) * 0.004 * step( uv.y, 0.45 );
	else if ( w < 2.5 ) uv += vec2( sin( uv.y * 30.0 + t * 8.0 ), cos( uv.x * 24.0 + t * 7.0 ) ) * 0.004;
	else if ( w < 3.5 ) uv += vec2( sin( uv.y * 14.0 + t * 2.2 ), cos( uv.x * 12.0 + t * 1.8 ) ) * 0.01;
	else if ( w < 4.5 ) uv.x += sin( uv.y * 50.0 + t * 6.0 ) * 0.003;
	else uv.x += sin( t * 0.4 ) * 0.008;
	vec2 tuv = clamp( uv, 0.002, 0.998 );
	c = texture( uFxMap, vec2( tuv.x, 1.0 - tuv.y ) ).rgb * 1.3;
	if ( w < 0.5 || w > 4.5 ) c += vec3( step( 0.994, fxHash( floor( fc / 2.0 ) + floor( t * 6.0 ) ) ) ) * 1.5;
	if ( w > 1.5 && w < 2.5 ) c *= 1.0 + 0.25 * sin( t * 5.0 );
	if ( w > 2.5 && w < 3.5 ) c += vec3( 0.2, 0.35, 0.4 ) * pow( max( 0.0, sin( uv.x * 30.0 + t * 2.0 ) * sin( uv.y * 26.0 - t * 1.6 ) ), 6.0 );
	c *= 0.9 + 0.1 * sin( fc.y * 1.7 );
#endif
	float rim = pow( 1.0 - abs( normalize( NORMAL ).z ), 2.2 ) * uFxRimK;
	ALBEDO = mix( c, uFxRim, clamp( rim, 0.0, 1.0 ) );
}
"""

# Additive instanced pools (rings, bold rings, squiggles): MeshBasicMaterial white, additive, double sided, no depth
# write, fog off; the instance colour (COLOR, linear) is the whole colour.
const ADD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
}
"""

# Chroma splat marks: map (the goo splat canvas) with instanceColor.r scaling alpha instead of tinting (alphaFromInstance).
const SPLAT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;
uniform sampler2D map : source_color, filter_linear_mipmap_anisotropic;
void fragment() {
	vec4 t = texture( map, UV );
	ALBEDO = t.rgb;
	ALPHA = t.a * COLOR.r;
}
"""

# ------------------------------------------------------------------------------------------------ math helpers
static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func seg(t: float, a: float, b: float) -> float:
	return clamp01((t - a) / (b - a))

class E:
	static func inQuad(t: float) -> float:
		return t * t
	static func outQuad(t: float) -> float:
		return t * (2.0 - t)
	static func inCubic(t: float) -> float:
		return t * t * t
	static func outCubic(t: float) -> float:
		return 1.0 - pow(1.0 - t, 3.0)
	static func inOutQuad(t: float) -> float:
		return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
	static func outBack(t: float, s: float = 1.7) -> float:
		return 1.0 + (s + 1.0) * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)
	static func inBack(t: float, s: float = 1.7) -> float:
		return t * t * ((s + 1.0) * t - s)
	static func outElastic(t: float) -> float:
		if t <= 0.0:
			return 0.0
		if t >= 1.0:
			return 1.0
		return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * (TAU / 3.0)) + 1.0

# THREE.Quaternion.setFromUnitVectors (exact port, incl. the opposite-vectors branch).
static func qFromUnit(vFrom: Vector3, vTo: Vector3) -> Quaternion:
	var r := vFrom.dot(vTo) + 1.0
	var q: Quaternion
	if r < 2.220446049250313e-16:
		r = 0.0
		if absf(vFrom.x) > absf(vFrom.z):
			q = Quaternion(-vFrom.y, vFrom.x, 0.0, r)
		else:
			q = Quaternion(0.0, -vFrom.z, vFrom.y, r)
	else:
		q = Quaternion(vFrom.y * vTo.z - vFrom.z * vTo.y, vFrom.z * vTo.x - vFrom.x * vTo.z, vFrom.x * vTo.y - vFrom.y * vTo.x, r)
	var l := q.length()
	return Quaternion() if l < 1e-12 else q / l

# THREE.Quaternion.setFromAxisAngle (axis normalized by the caller; a zero axis gives three's degenerate result).
static func qAxis(axis: Vector3, angle: float) -> Quaternion:
	var s := sin(angle / 2.0)
	return Quaternion(axis.x * s, axis.y * s, axis.z * s, cos(angle / 2.0))

# Matrix4.compose(position, quaternion, scale).
static func compose(p: Vector3, q: Quaternion, s: Vector3) -> Transform3D:
	return Transform3D(Basis(q.normalized()) * Basis.from_scale(s), p)

# Vector3.reflect(normal) of three (= Godot's bounce()).
static func reflect(v: Vector3, n: Vector3) -> Vector3:
	return v - n * (2.0 * v.dot(n))

# '#rrggbb' -> linear THREE.Color, times k (alpha stays 1: instance colours).
static func lin(hex, k: float = 1.0) -> Color:
	var c: Color = DAU.color(hex).srgb_to_linear()
	return Color(c.r * k, c.g * k, c.b * k, 1.0)

static func cmul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)

# ------------------------------------------------------------------------------------------------ JS-shape helpers
# obj.k for a Dictionary key or an Object property; `def` when missing / null (JS `?? def`).
static func _g(o, k: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		var v = o.get(k)
		return def if v == null else v
	if o is Object:
		if not is_instance_valid(o):
			return def
		var v2 = o.get(k)
		return def if v2 == null else v2
	return def

static func _sset(o, k: String, v) -> void:
	if o is Dictionary:
		o[k] = v
	elif o is Object and is_instance_valid(o):
		o.set(k, v)

static func _has(o, k: String) -> bool:
	if o is Dictionary:
		return o.has(k)
	if o is Object and is_instance_valid(o):
		return k in o
	return false

# JS truthiness.
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
	if v is Object:
		return is_instance_valid(v)
	return true

# JS `a || b` / `a ?? b`.
static func _or(a, b):
	return a if _t(a) else b

static func _nz(a, b):
	return a if a != null else b

static func _num(v, def: float = 0.0) -> float:
	if v is float or v is int:
		return float(v)
	return def

static func _isNum(v) -> bool:
	return v is float or v is int

# h.m(...args) for an Object handle (method or Callable field) or a Dictionary of Callables (m or m without the §3.2 '_').
static func _hcall(h, m: String, args: Array = []):
	if h == null:
		return null
	if h is Object:
		if not is_instance_valid(h):
			return null
		if h.has_method(m):
			return h.callv(m, args)
		var f = h.get(m)
		if f is Callable and f.is_valid():
			return f.callv(args)
		return null
	if h is Dictionary:
		var f2 = h.get(m, h.get(m.trim_suffix("_")))
		if f2 is Callable and f2.is_valid():
			return f2.callv(args)
	return null

# game.<sys>.<m>(args) when both exist (the JS `g.fx?.burst?.(...)`).
func _sys(name: String, m: String, args: Array = []):
	var s = game.get(name)
	if s == null or not (s is Object) or not is_instance_valid(s) or not s.has_method(m):
		return null
	return s.callv(m, args)

static func _drop(n) -> void:
	if n is Node and is_instance_valid(n):
		DAU.detach(n)
		n.queue_free()

# Makes a node's Euler order three's 'XYZ' keeping its current transform (imported glTF nodes default to YXZ).
static func _xyz(n) -> void:
	if n is Node3D and n.rotation_order != EULER_ORDER_XYZ:
		var tr: Transform3D = n.transform
		n.rotation_order = EULER_ORDER_XYZ
		n.transform = tr

static func _meshes(root: Node, out: Array, visibleOnly: bool = false) -> Array:
	if root is MeshInstance3D and (not visibleOnly or (root as MeshInstance3D).visible):
		out.append(root)
	for c in root.get_children():
		_meshes(c, out, visibleOnly)
	return out

# new THREE.Mesh(geometry, material): no shadow casting unless asked (three's castShadow default is false).
static func _mi(mesh: Mesh, mat: Material, name: String = "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat != null:
		m.material_override = mat
	if name != "":
		m.name = name
	return m

# ------------------------------------------------------------------------------------------------ instanced pools
# Tiny instanced effect pools (rings, squiggles, debris): one draw call each, hidden while empty.
class Pool extends RefCounted:
	var mesh: MultiMeshInstance3D
	var mm: MultiMesh
	var items: Array = []
	var head := 0

	func _init(scene: Node, geometry: Mesh, material: Material, cap: int, makeItem: Callable, pname: String) -> void:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = geometry
		mm.instance_count = cap
		mm.visible_instance_count = 0
		mesh = MultiMeshInstance3D.new()
		mesh.multimesh = mm
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))   # frustumCulled = false
		mesh.visible = false
		mesh.name = "wonder_pool_%s" % pname
		scene.add_child(mesh)
		for i in cap:
			var it := {"alive": false, "c": Color(1, 1, 1, 1), "m": Transform3D()}
			it.merge(makeItem.call(), true)
			items.append(it)

	func spawn() -> Dictionary:
		var it: Dictionary = items[head]
		head = (head + 1) % items.size()
		it.alive = true
		return it

	# fn(item, dt) -> bool alive; the item writes item.m / item.c.
	func update(dt: float, fn: Callable) -> void:
		var n := 0
		for it in items:
			if not it.alive:
				continue
			if not fn.call(it, dt):
				it.alive = false
				continue
			mm.set_instance_transform(n, it.m)
			mm.set_instance_color(n, it.c)
			n += 1
		mm.visible_instance_count = n
		mesh.visible = n > 0

	func clear() -> void:
		for it in items:
			it.alive = false
		mm.visible_instance_count = 0
		mesh.visible = false

# ------------------------------------------------------------------------------------------------ corpses (clones)
# A frozen clone of the zombie's current pose: pivot (world pos + yaw) -> tilt -> body.
class Corpse extends RefCounted:
	var w
	var pivot: Node3D
	var tilt: Node3D
	var body: Node3D
	var meshes: Array = []
	var h := 1.6
	var blob = null
	var pos0y := 0.0
	var _restored := false

	func setMat(mat) -> void:
		for o in meshes:
			if is_instance_valid(o):
				o.material_override = mat if mat != null else o.get_meta("__wmat", null)

	# the contact blob follows the body while it is visible and not shrunk away
	func sync() -> void:
		if blob == null:
			return
		var ts := tilt.scale
		var s := minf(minf(ts.x, ts.y), 1.0 if ts.z > 0.05 else ts.x) * pivot.scale.x
		var vis := pivot.visible and s > 0.25 and pivot.position.y - pos0y < 0.8
		if blob is Dictionary:
			blob.visible = vis
		elif blob is Object and is_instance_valid(blob):
			blob.set("visible", vis)

	func dispose() -> void:
		w._drop(pivot)
		if blob != null:
			w._hcall(blob, "remove")
			blob = null

# ------------------------------------------------------------------------------------------------ Wonder
var game
var reloading := false
var reloadId = null
var reloadProgress := 0.0
var recording := false
var charge := 0.0
var teles: Array = []
var debug
var res := {}
var pools := {}
var _ready := false
var _frame := -1
var _delegated := false
var _dbgTrigger = null
var _dbgPrev := false
var _dbgPresses := 0
var _sdPrev := false
var _actors: Array = []       # gag / keyed / tumble / implode corpse actors + misc effects: { update(dt) -> bool, dispose() }
var _hidden := {}             # zk -> { z, group, t } originals hidden while their clone performs
var _claimed := {}            # zk -> true: zombies already doomed by a wonder effect this frame (no double targeting)
var _status := {}             # zk -> status record (slow, panic, laugh, frozen, seat...)
var _st := {}                 # per-weapon state
var _blobs: Array = []        # chroma goo blobs in flight
var _puddles: Array = []
var _sigCd := {}
var _tele0 = null             # Tiny Tele prototype (built lazily; false = unavailable)
var _teleCheck = null
var _lastTeles = null
var _applying := 0
var _dooming := 0
var _dmgCtx = null
var _kick := {"x": 0.0, "v": 0.0}
var _micTip := Vector3()
var _recLoop = null
var _ctxSD := {"def": null, "upgraded": false, "slot": null, "origin": Vector3(), "dir": Vector3(), "muzzle": Vector3(),
	"triggerDown": false, "triggerPressed": false, "triggerReleased": false, "ads": false, "dt": 0.0}
var _reloadT := 0.0
var _reloadEl := 0.0
var _reloadSlot = null
var _reloadMag := 0
var _reloadFx := 0
var _reloadCue := ""
var _reloadBeat := 1
var _lastZap = null
var _lureTele = null
var _teleDefSrc = null
var _teleDefC = null
var _snow = null
var _snowTried := false
var _cartoon = null
var _screenTex = null
var _fxTime := 0.0
var _fxMats: Array = []       # every fx ShaderMaterial (their uFxTime is the shared FXU.time of the JS)
var _meshLib := {}            # name -> Mesh (res://assets/runtime/wonder/meshes.glb)
var _wid := 0
var _zombiesHook := Callable()   # boss adapter (see the header)
# MP (scripts/game/wonder_net.gd; RECONCILE R17): every wonder resolution (victims, statuses, lure, puddle keys) runs on
# the host; clients run the owner's fire logic + visuals and send requests. null / true in solo.
const NET_PATH := "res://scripts/game/wonder_net.gd"
var mp = null                    # WonderNet while an MP game runs
var _au := true                  # may mutate the world (solo / host); false on an MP client
var _byCtx = null                # acting peer id while the host resolves someone's action (zombies.damage info.by)
var _warned := {}

func _init(g) -> void:
	game = g
	debug = WonderDebug.new(self)

# ------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	if _ready:
		return
	_ready = true
	var g = game
	_buildResources()
	var ev = g.events
	ev.on("zombie:hit", func(p): _onHit(p))
	ev.on("zombie:kill", func(p): _onKill(p))
	# ('zombie:spawn' -> per-art shader warm-up: engine plumbing, not ported)
	ev.on("game:start", func(_p): reset())
	_registerCues()

func reset() -> void:
	if not _ready:
		return
	for a in _actors:
		if a.has("dispose"):
			a.dispose.call()
	_actors.clear()
	for k in _hidden:
		var h = _hidden[k]
		if is_instance_valid(h.group):
			h.group.visible = true
	_hidden.clear()
	_claimed.clear()
	for k in _status.keys():
		if _status.has(k):
			_clearStatus(_status[k].z)
	_status.clear()
	for b in _blobs:
		_drop(b.mesh)
	_blobs.clear()
	for p in _puddles:
		_disposePuddle(p)
	_puddles.clear()
	for t in teles:
		_disposeTele(t)
	teles.clear()
	_stopRecording(false)
	for k in ["rings", "bold", "squig", "debris", "splat", "splatUp"]:
		pools[k].clear()
	_sigCd.clear()
	_st = {}
	reloading = false
	reloadId = null
	reloadProgress = 0.0
	charge = 0.0
	_teleCheck = null
	_lastTeles = null
	_kick.x = 0.0
	_kick.v = 0.0
	var n = game.get("net")
	if n != null and n.inGame:
		if mp == null:
			mp = load(NET_PATH).new(self)
		mp.reset()
		_au = mp.authority()
	else:
		mp = null
		_au = true
	if _au:
		_sys("zombies", "setLure", [null])

# Once per frame, from Game's UPDATE_ORDER (right after weapons).
func update(dt: float) -> void:
	var g = game
	if not _ready:
		init()
	if _frame == int(g.time.frame):
		return
	_frame = int(g.time.frame)
	_fxTime = float(g.time.realNow)
	_syncFxTime()
	if g.state != "playing" and g.state != "down":
		dt = 0.0
	if mp != null:
		_au = mp.authority()
		mp.update(dt)
	# (JS try/finally kept these balanced; a GDScript error inside zombies.damage cannot leave them raised)
	_applying = 0
	_dooming = 0
	_claimed.clear()
	_selfDrive(dt)
	_updateReload(dt)
	_updateWeaponState(dt)
	_updateHeldModel(dt)
	_updateBlobs(dt)
	_updatePuddles(dt)
	_updateTeles(dt)
	_updateStatus(dt)
	_updateActors(dt)
	_updateHidden(dt)
	_updatePools(dt)
	_updateTeleCount()

func _syncFxTime() -> void:
	for i in range(_fxMats.size() - 1, -1, -1):
		var m = _fxMats[i]
		if m == null:
			_fxMats.remove_at(i)
			continue
		m.set_shader_parameter("uFxTime", _fxTime)

# ------------------------------------------------------------------------------------------ public API
func isWonder(id) -> bool:
	return WONDER.has(id)

func busy(weaponId) -> bool:
	return (reloading and reloadId == weaponId) or (weaponId == "boom_mic" and recording)

func fire(weaponId, ctx) -> bool:
	_delegated = true
	if ctx != null and _dbgTrigger != null:
		# tests: the simulated trigger replaces the mouse (still gated by weapons' ready flag)
		var rdy = ctx.get("ready")
		var d: bool = _t(_dbgTrigger) and not (rdy is bool and rdy == false)
		ctx.triggerDown = d
		ctx.triggerPressed = d and not _dbgPrev
		ctx.triggerReleased = not d and _dbgPrev
		if ctx.triggerPressed:
			_dbgPresses += 1
		_dbgPrev = d
	return _fire(weaponId, ctx)

# weapons hooks (optional): the held wonder weapon was put away / raised.
func holster(weaponId, _ctx = null) -> bool:
	if weaponId == "boom_mic" and recording:
		_stopRecording(false)
	if reloading and reloadId == weaponId:
		_cancelReload()
	return true

func equip(weaponId, _ctx = null) -> bool:
	var st := _state(weaponId)
	st.buffer = 0.0
	st.erase("needle")
	return true

func reload(weaponId, ctx = null) -> float:
	if not WONDER.has(weaponId):
		return 0.0
	if ctx == null:
		ctx = {}
	var slot = _or(ctx.get("slot"), _slotOf(weaponId))
	var def = _or(ctx.get("def"), _defOf(weaponId, _t(_g(slot, "upgraded"))))
	return _startReload(weaponId, slot, def)

# ctx (from weapons) = { origin (left hand), dir, velocity, aimPoint }: weapons already took one from
# weapons.teles. Without ctx (self-drive / tests) wonder consumes one itself.
func throwTele(ctx = null) -> bool:
	if not _ready:
		init()
	var g = game
	var w = g.weapons
	var p = g.player
	if p == null or not _t(_g(p, "alive")) or _t(_g(p, "downed")):
		return false
	var st := _state("tele")
	if st.cool > 0.0:
		return false
	var fromWeapons: bool = ctx != null and ctx is Dictionary and ctx.get("origin") != null and ctx.get("velocity") != null
	var consume := false
	if not fromWeapons and w != null and _isNum(_g(w, "teles")):
		var cur := int(w.teles)
		var last := int(_lastTeles) if _lastTeles != null else cur
		if cur < last:
			consume = false          # the caller already took one this frame
		elif cur > 0:
			consume = true
		else:
			return false             # none left
	st.cool = 0.3
	if _spawnTele(ctx if fromWeapons else null) == null:
		return false
	if consume:
		_teleCheck = {"value": int(w.teles), "frame": int(g.time.frame)}
	return true

# Forces a signal-color proc on z (weapons may call it; also the debug path). signal: hot_mic|laugh_track|cold_open.
func applySignal(z, sig, opts = null) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	var weaponId = o.get("weaponId")
	var splash := _t(o.get("splash"))
	var s := str(sig if sig != null else "")
	if s.begins_with("signal_"):
		s = s.substr(7)
	if z == null or not SIGNALS.has(s) or not _alive(z):
		return false
	if s == "hot_mic":
		_ignite(z, 1, weaponId)
	elif s == "laugh_track":
		_laughTrack(z, weaponId)
	else:
		_coldOpen(z, weaponId)
	game.events.emit("wonder:signal", {"z": z, "signal": s, "weaponId": weaponId, "splash": splash})
	return true

# ------------------------------------------------------------------------------------------ helpers
func _state(id) -> Dictionary:
	if not _st.has(id):
		_st[id] = {"cool": 0.0, "buffer": 0.0, "recover": 0.0, "rec": 0.0, "playT": 0.0}
	return _st[id]

func _curSlot():
	var w = game.weapons
	if w == null:
		return null
	var slots = _g(w, "slots")
	var cur = _g(w, "current", -1)
	if not (slots is Array) or not _isNum(cur) or int(cur) < 0 or int(cur) >= slots.size():
		return null
	return slots[int(cur)]

func _slotOf(id):
	var w = game.weapons
	var slots = _g(w, "slots")
	if slots is Array:
		for s in slots:
			if s != null and _g(s, "id") == id:
				return s
	return null

func _defOf(id, upgraded):
	var w = game.weapons
	var cur = _curSlot()
	if cur != null and _g(cur, "id") == id and w.has_method("currentDef"):
		var d0 = w.currentDef()
		if d0 != null:
			return d0
	var defs = _g(w, "defs")
	var d = defs.get(id) if defs is Dictionary else null
	if d != null and _t(upgraded) and d.get("upgraded") is Dictionary:
		var m: Dictionary = d.duplicate()
		m.merge(d.upgraded, true)
		m.isUpgraded = true
		return m
	return d

func _mag(id, def, up: bool) -> int:
	var m = MAGS.get(id)
	var dm = _g(def, "mag")
	if _t(dm):
		return int(dm)
	return int(m[2 if up else 0]) if m != null else 1

func _round() -> int:
	var r = game.rounds
	return maxi(1, int(_or(_g(r, "round"), 1)))

func _isBoss(z) -> bool:
	return z != null and (_g(z, "type") == "boss_baron" or _g(z, "boss") == true or _t(_g(_g(z, "flags"), "boss")))

# Stable key of a zombie record (JS Map / Set keys by object identity).
func _zk(z):
	var id = _g(z, "id")
	if id != null:
		return id
	var k = _g(z, "__wid")
	if k == null:
		_wid += 1
		k = "w%d" % _wid
		_sset(z, "__wid", k)
	return k

func _hp(z) -> float:
	return _num(_g(z, "hp"), 0.0)

func _zstate(z) -> String:
	return str(_g(z, "state", ""))

func _alive(z) -> bool:
	return z != null and _zstate(z) != "dying" and _zstate(z) != "dead" and not (_hp(z) <= 0.0) and not _claimed.has(_zk(z))

func _zombies() -> Array:
	var zm = game.zombies
	var L: Array = []
	var a = _g(zm, "alive")
	if a is Array:
		L = a
	if _zombiesHook.is_valid():
		var r = _zombiesHook.call(L)
		if r is Array:
			return r
	return L

func _inList(list: Array, z) -> bool:
	for o in list:
		if is_same(o, z):
			return true
	return false

func _zh(z) -> float:
	return float(_or(_g(z, "height"), 1.6))

func _zr(z, def: float = 0.4) -> float:
	return float(_or(_g(z, "radius"), def))

# Chest aim point of a zombie.
func _chest(z) -> Vector3:
	var h := _zh(z)
	return Vector3(z.pos.x, z.pos.y + h * 0.58, z.pos.z)

func _headPos(z) -> Vector3:
	var hd = _g(z, "head")
	if hd is Node3D and is_instance_valid(hd):
		return DAU.worldPos(hd)
	return Vector3(z.pos.x, z.pos.y + _zh(z) * 0.85, z.pos.z)

func _col():
	return _g(game.level, "col")

func _los(a: Vector3, b: Vector3) -> bool:
	var col = _col()
	return col == null or bool(col.lineOfSight(a, b))

func _damage(z, amount: float, weaponId, cause, extra: Dictionary = {}) -> bool:
	var zm = game.zombies
	if zm == null or not zm.has_method("damage"):
		return false
	var prev = _dmgCtx
	_dmgCtx = {"weaponId": weaponId, "cause": cause, "splash": _t(extra.get("splash")), "upgraded": _t(extra.get("upgraded"))}
	if mp != null:
		_dmgCtx.by = int(extra.get("by", _byCtx if _byCtx != null else mp.localId()))
	_applying += 1
	# inside _doom a lethal hit must not play the manager's own death (the clone animates it): corpse false
	var info := {"head": false, "weaponId": weaponId, "cause": cause}
	if _dooming > 0:
		info.corpse = false
	info.merge(extra, true)
	if mp != null and not info.has("by"):
		info.by = _byCtx if _byCtx != null else mp.localId()
	var r = zm.damage(z, amount, info)
	_applying -= 1
	_dmgCtx = prev
	return _t(r)

# Kills z (for a corpse wonder animates). Returns true when it died.
func _kill(z, weaponId, cause, extra: Dictionary = {}) -> bool:
	var e := {"corpse": false, "knockback": 0}
	e.merge(extra, true)
	var killed := _damage(z, 1e7, weaponId, cause, e)
	return killed or _hp(z) <= 0.0 or _zstate(z) == "dying"

# Damages z through fn() with its corpse clone already built and the original hidden, so the zombie manager's
# own death visuals (stun stars, static dissolve) stay invisible and wonder's death animation replaces them.
# Returns the corpse (or true without a model) when z died, else null (the original is shown again).
func _doom(z, fn: Callable):
	var P = _corpse(z)
	var killed := false
	_dooming += 1
	killed = _t(fn.call())
	_dooming -= 1
	killed = killed or not (_hp(z) > 0.0) or _zstate(z) == "dying" or _g(z, "dead") == true
	if not killed:
		if P != null:
			P.dispose()
		_unhide(z)
		return null
	return P if P != null else true

# Real stun (stars over the head): zombies.stun when available.
func _stun(z, s: float) -> void:
	if not _au:
		return
	var zm = game.zombies
	if zm != null and zm.has_method("stun"):
		zm.stun(z, s)
		return
	_hold(z, s)

# Keeps the zombie AI idle for s seconds (no walking, no attacks).
func _hold(z, s: float) -> void:
	if not _au:
		return
	var cur = _g(z, "stun")
	if cur == null or _isNum(cur):
		_sset(z, "stun", maxf(_num(cur, 0.0), s))
	elif game.zombies != null and game.zombies.has_method("stun"):
		game.zombies.stun(z, s)

func _akick(z, amount: float) -> void:
	_hcall(_g(z, "animator"), "kick", [amount])

func _stunRadius(pos: Vector3, r: float, s: float, except = null) -> void:
	for z in _zombies():
		if is_same(z, except) or not _alive(z) or _isBoss(z):
			continue
		if z.pos.distance_to(pos) <= r:
			_stun(z, s)
			_akick(z, 0.8)

func _play(id: String, opts: Dictionary = {}):
	var A = game.audio
	if A == null or not A.has_method("play"):
		return null
	return A.play(id, opts)

func _emit(name: String, payload) -> void:
	game.events.emit(name, payload)

func _fx(m: String, args: Array) -> void:
	_sys("fx", m, args)

func _floorY(x: float, z: float, yFrom: float):
	var col = _col()
	var f: float = float(col.floorAt(x, z, yFrom)) if col != null else 0.0
	return f if f > -INF else null

# Keeps a moving effect out of walls: returns the allowed travel distance from `from` along dir (xz).
func _clearDist(from: Vector3, dir: Vector3, dist: float, margin: float = 0.35) -> float:
	var col = _col()
	if col == null:
		return dist
	var a := Vector3(from.x, from.y + 0.4, from.z)
	var hit = col.raycast(a, Vector3(dir.x, 0, dir.z).normalized(), dist + margin)
	return maxf(0.0, float(hit.dist) - margin) if hit != null else dist

# col.moveCircle(z.pos, delta, ...) mutates pos in JS: the GDScript port returns the new pos (or a result holding it).
func _moveCircle(z, delta: Vector3, r: float, h: float, stepUp: float) -> void:
	var col = _col()
	if col == null:
		return
	# owner z: collision remembers "grounded" per owner (the JS WeakMap keyed by the pos object)
	var out = col.moveCircle(z.pos, delta, r, h, stepUp, null, z) if col.get_method_argument_count("moveCircle") >= 7 else col.moveCircle(z.pos, delta, r, h, stepUp)
	if out is Vector3:
		z.pos = out
	elif out is Dictionary and out.get("pos") is Vector3:
		z.pos = out.pos

# nav.dir(x, z, out) -> unit XZ toward the goal (JS mutates out; the port returns it: nav.dir(x, z)).
func _navDir(x: float, z: float) -> Vector3:
	var nav = game.nav
	if nav == null or not nav.has_method("dir"):
		return Vector3.ZERO
	var r = nav.dir(x, z)
	return r if r is Vector3 else Vector3.ZERO

# Camera aim ray (player.aimRay): camera world position + direction.
func _aimRay() -> Array:
	var cam = game.camera
	if cam == null or not is_instance_valid(cam):
		var p = game.player
		var o := Vector3.ZERO
		if p != null:
			o = p.pos + Vector3(0, 1.35, 0)
		return [o, Vector3(0, 0, -1)]
	var gt: Transform3D = cam.global_transform if cam.is_inside_tree() else cam.transform
	return [gt.origin, -gt.basis.z.normalized()]

# player.muzzle(out)
func _pmuzzle() -> Vector3:
	var p = game.player
	if p == null:
		return Vector3.ZERO
	if p.has_method("muzzle"):
		var r = p.call("muzzle", Vector3()) if p.get_method_argument_count("muzzle") >= 1 else p.call("muzzle")
		if r is Vector3:
			return r
	return p.pos + Vector3(0, 1.3, 0)

func _warnOnce(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[wonder] " + msg)

# ------------------------------------------------------------------------------------------ resources
func _M():
	return game.mats

func _toon(color, opts: Dictionary) -> Material:
	var M = _M()
	if M != null and M.has_method("toon"):
		return M.toon(color, opts)
	# (materials.gd missing: plain StandardMaterial3D so the effect still shows)
	var m := StandardMaterial3D.new()
	m.albedo_color = DAU.color(color)
	m.roughness = float(opts.get("rough", 0.75))
	if opts.get("emissive") != null:
		m.emission_enabled = true
		m.emission = DAU.color(opts.emissive)
		m.emission_energy_multiplier = float(opts.get("emissiveIntensity", 1.0))
	if opts.get("transparent"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = float(opts.get("opacity", 1.0))
	if opts.get("vertexColors"):
		m.vertex_color_use_as_albedo = true
	return m

func _glow(color, intensity: float, opts: Dictionary = {}) -> Material:
	var M = _M()
	if M != null and M.has_method("glow"):
		return M.glow(color, intensity, opts)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c: Color = DAU.color(color)
	m.albedo_color = Color(c.r * intensity, c.g * intensity, c.b * intensity)
	if opts.get("additive"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _screenMat(tex, opts: Dictionary) -> Material:
	var M = _M()
	if M != null and M.has_method("screen"):
		return M.screen(tex, opts)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	return m

# screenMat.map = tex (materials.gd DAMaterial facade: `map` is the tScreen uniform + uTexel, like the JS).
func _setScreenMap(mat, tex) -> void:
	if mat == null:
		return
	if "map" in mat:
		mat.map = tex
	elif mat is ShaderMaterial:
		mat.set_shader_parameter("tScreen", tex)
		if tex is Texture2D and tex.get_width() > 0:
			mat.set_shader_parameter("uTexel", Vector2(1.0 / tex.get_width(), 1.0 / tex.get_height()))
	elif mat is BaseMaterial3D:
		mat.albedo_texture = tex

func _loadScene(name: String) -> Node:
	var path := RT + name + ".glb"
	if not ResourceLoader.exists(path):
		_warnOnce("glb_" + name, "missing %s (run blender/build_all.py --only runtime)" % path)
		return null
	var ps = load(path)
	if ps is PackedScene:
		return ps.instantiate()
	return null

# Material key of a Blender runtime mesh node: "da" extras {mat}, else the node-name prefix ("mBunny_3" -> mBunny).
static func _matKey(n: Node) -> String:
	var ex = n.get_meta("extras", null)
	if ex is Dictionary and ex.get("da") != null:
		var da = ex.da
		if da is String:
			da = JSON.parse_string(da)
		if da is Dictionary and da.get("mat") != null:
			return str(da.mat)
	var nm := String(n.name)
	var i := nm.rfind("_")
	return nm.substr(0, i) if i > 0 else nm

# Applies the wonder materials (R.<key>) to every mesh of an instantiated runtime scene; true = cast shadows.
func _dress(root: Node, cast: bool = true) -> Node:
	if root == null:
		return null
	for m in _meshes(root, []):
		var k := _matKey(m)
		if res.get(k) is Material:
			m.material_override = res[k]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	DAU.traverse(root, func(n): _xyz(n))
	return root

func _libMesh(name: String) -> Mesh:
	var m = _meshLib.get(name)
	if m is Mesh:
		return m
	# fallback primitives (Blender asset not built yet): engine placeholders, warned once
	_warnOnce("mesh_" + name, "runtime mesh '%s' missing: placeholder" % name)
	var pm: Mesh
	match name:
		"ring", "ringBold":
			var q := QuadMesh.new()
			q.size = Vector2(2, 2)
			pm = q
		"dot":
			var s := SphereMesh.new()
			s.radius = 0.06
			s.height = 0.12
			pm = s
		"cube":
			pm = BoxMesh.new()
		_:
			var s2 := SphereMesh.new()
			s2.radius = 1.0
			s2.height = 2.0
			pm = s2
	_meshLib[name] = pm
	return pm

func _buildResources() -> void:
	var g = game
	var S: Node = g.scene if g.scene != null else g
	var R := res
	# static meshes: blender/runtime/wonder.py (meshes.glb: one mesh node per geometry, named as the JS res keys)
	var lib := _loadScene("meshes")
	if lib != null:
		for m in _meshes(lib, []):
			_meshLib[String(m.name)] = m.mesh
		lib.free()
	R.ring = _libMesh("ring")               # RingGeometry(0.88, 1, 48)
	R.ringBold = _libMesh("ringBold")       # RingGeometry(0.7, 1, 48)
	R.tumble = _libMesh("tumble")           # tumbleweedGeo()
	R.blobGeo = _libMesh("blobGeo")         # geo.sphere(1, 20, 14)
	R.puddle = _libMesh("puddle")           # blobShapeGeo(11)
	R.squig = _libMesh("squig")             # squiggleGeo()
	R.flameOuter = _libMesh("flameOuter")   # flameGeo(1)
	R.flameInner = _libMesh("flameInner")   # flameGeo(0.62)
	R.dot = _libMesh("dot")                 # geo.sphere(0.06, 12, 8)
	R.cube = _libMesh("cube")               # geo.roundedBox(1, 1, 1, 0.18, 2)
	R.puddleSheen = _libMesh("puddleSheen") # blobShapeGeo(23, 18)
	var P: Dictionary = Config.PAL
	R.mTumble = _toon("#C79A55", {"keepColor": true, "rough": 0.85, "rim": 0.5, "rimColor": "#FFE2A8"})
	R.mGel = _toon("#38C850", {"keepColor": true, "rough": 0.05, "transparent": true, "opacity": 0.86, "rim": 0.7, "rimColor": "#DFFFD8", "rimPower": 2.2,
		"emissive": "#1B7A2E", "emissiveIntensity": 0.12, "env": 0.7, "name": "wonder_gel"})
	R.mGelEye = _toon("#1E7A30", {"keepColor": true, "rough": 0.2, "rim": 0.4})
	R.mPlate = _toon("#F4F1E8", {"keepColor": true, "rough": 0.25, "rim": 0.3, "env": 0.4})
	R.mCherry = _toon("#E23B3B", {"keepColor": true, "rough": 0.15, "rim": 0.6, "env": 0.6})
	R.mBunny = _toon("#FFFFFF", {"keepColor": true, "rough": 0.95, "rim": 0.75, "rimColor": "#FFFFFF", "wrap": 0.8})
	R.mPink = _toon("#FF9EC4", {"keepColor": true, "rough": 0.7, "rim": 0.4})
	R.mInk = _toon("#2A1D3A", {"keepColor": true, "rough": 0.3, "rim": 0.2})
	R.mGoo = _toon(P.chromaBlue, {"keepColor": true, "rough": 0.08, "rim": 0.9, "rimColor": "#BFD4FF", "emissive": P.chromaBlue, "emissiveIntensity": 0.5, "env": 0.9})
	R.mGooUp = _toon(P.greenScreen, {"keepColor": true, "rough": 0.08, "rim": 0.9, "rimColor": "#E4FFD8", "emissive": P.greenScreen, "emissiveIntensity": 0.5, "env": 0.9})
	# puddle = dark goo rim + saturated body + a glossy sheen blob (three stacked flat layers; the JS polygon offsets
	# -1/-2/-3 have no Godot material equivalent, the layers keep their geometric offsets)
	R.mPuddle = _toon("#1440D0", {"keepColor": true, "rough": 0.34, "rim": 0.2, "emissive": P.chromaBlue, "emissiveIntensity": 0.26, "env": 0.1, "name": "wonder_puddle"})
	R.mPuddleUp = _toon("#2CC24E", {"keepColor": true, "rough": 0.34, "rim": 0.2, "emissive": P.greenScreen, "emissiveIntensity": 0.2, "env": 0.1, "name": "wonder_puddle_up"})
	R.mPuddleRim = _toon("#0C2A8C", {"keepColor": true, "rough": 0.4, "rim": 0.1, "emissive": "#0C2A8C", "emissiveIntensity": 0.2, "name": "wonder_puddle_rim"})
	R.mPuddleRimUp = _toon("#14803A", {"keepColor": true, "rough": 0.4, "rim": 0.1, "emissive": "#14803A", "emissiveIntensity": 0.15, "name": "wonder_puddle_rim_up"})
	R.mPuddleSheen = _toon("#4F7BFF", {"keepColor": true, "rough": 0.12, "rim": 0.3, "emissive": "#3E6BFF", "emissiveIntensity": 0.32, "env": 0.3, "name": "wonder_puddle_sheen"})
	R.mPuddleSheenUp = _toon("#8CF08A", {"keepColor": true, "rough": 0.12, "rim": 0.3, "emissive": "#6CE86A", "emissiveIntensity": 0.26, "env": 0.3, "name": "wonder_puddle_sheen_up"})
	R.mFlame = _glow("#FF7A2E", 2.6, {"additive": true})
	R.mFlameIn = _glow("#FFE14D", 3.2, {"additive": true})
	R.mWhite = _glow("#FFFFFF", 3.2)
	R.mWhiteBody = _glow("#FFFFFF", 1.25)
	R.mIce = _toon("#5DB8EC", {"keepColor": true, "rough": 0.3, "rim": 0.45, "rimColor": "#E6F7FF", "rimPower": 2.2, "emissive": "#16508A", "emissiveIntensity": 0.1, "env": 0.3, "steps": 3, "name": "wonder_ice"})
	R.mBattery = _toon("#F4C81E", {"keepColor": true, "rough": 0.35, "rim": 0.4})
	R.fx = {
		"flat": _fxMaterial("flat", {"color": P.chromaBlue, "intensity": 1.25, "rim": "#9DB9FF", "rimK": 0.55}),
		"flatUp": _fxMaterial("flat", {"color": P.greenScreen, "intensity": 1.1, "rim": "#E4FFD8", "rimK": 0.55}),
		"static": _fxMaterial("static", {"rim": "#FFFFFF", "rimK": 0.3}),
		"bars": _fxMaterial("bars", {"rim": "#FFFFFF", "rimK": 0.25}),
	}
	R.foot = {}
	R.footOpts = {}
	var all := WORLDS + WORLDS_UP
	for i in all.size():
		var w: String = all[i]
		var map = _card("world_" + w)
		var fo := {"map": map, "world": i, "rim": WORLD_TINT[w], "rimK": 0.4, "focus": WORLD_FOCUS[w]}
		R.foot[w] = _fxMaterial("footage", fo)
		R.footOpts[w] = fo
	var ringMat := _addMaterial()
	var boldMat := _addMaterial()
	var squigMat := _addMaterial()
	# instance colours tint the debris toon (three's USE_INSTANCING_COLOR): vertexColors routes COLOR into the albedo
	var debrisMat := _toon("#FFFFFF", {"keepColor": true, "rough": 0.18, "rim": 0.55, "rimColor": "#EAF8FF", "env": 0.55, "emissive": "#3E86C8", "emissiveIntensity": 0.12, "name": "wonder_debris", "vertexColors": true})
	var ringItem := func(): return {"from": Vector3(), "to": Vector3(), "q": Quaternion(), "t": 0.0, "delay": 0.0, "dur": 0.2, "s0": 0.1, "s1": 0.4, "base": Color(), "flat": false, "kind": "trail"}
	pools = {
		"rings": Pool.new(S, R.ring, ringMat, 96, ringItem, "wonder_rings"),
		"bold": Pool.new(S, R.ringBold, boldMat, 64, ringItem, "wonder_bold"),
		"squig": Pool.new(S, R.squig, squigMat, 64, func(): return {"from": Vector3(), "t": 0.0, "dur": 0.45, "base": Color(), "seed": 0.0, "side": Vector3()}, "wonder_squig"),
		"debris": Pool.new(S, R.cube, debrisMat, 96, func(): return {"pos": Vector3(), "vel": Vector3(), "rot": Vector3(), "spin": Vector3(), "t": 0.0, "life": 1.0, "size": 0.1, "floor": 0.0}, "wonder_debris"),
	}
	pools.debris.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# chroma splat marks on walls / floors: fade out with the puddle (fixed pools, one draw each, hidden while empty)
	var quad := QuadMesh.new()   # PlaneGeometry(1, 1)
	quad.size = Vector2(1, 1)
	R.splatGeo = quad
	var splatItem := func(): return {"pos": Vector3(), "q": Quaternion(), "size": 1.1, "t": 0.0, "dur": 4.0}
	pools.splat = Pool.new(S, R.splatGeo, _splatMat(false), 24, splatItem, "wonder_splat")
	pools.splatUp = Pool.new(S, R.splatGeo, _splatMat(true), 24, splatItem, "wonder_splat_up")
	_screenTex = _makeCartoon()

func _addMaterial() -> ShaderMaterial:
	if not res.has("_addShader"):
		var sh := Shader.new()
		sh.code = ADD_SHADER
		res._addShader = sh
	var m := ShaderMaterial.new()
	m.shader = res._addShader
	return m

func _splatMat(up: bool) -> ShaderMaterial:
	if not res.has("_splatShader"):
		var sh := Shader.new()
		sh.code = SPLAT_SHADER
		res._splatShader = sh
	var m := ShaderMaterial.new()
	m.shader = res._splatShader
	m.set_shader_parameter("map", _splatTexture(up))
	return m

# fxMaterial(kind, { color, intensity, rim, rimK, map, world, focus }) -> ShaderMaterial (uFxTime driven per frame).
func _fxMaterial(kind: String, o: Dictionary) -> ShaderMaterial:
	var key := "_fxShader_" + kind
	if not res.has(key):
		var sh := Shader.new()
		sh.code = "shader_type spatial;\n#define FX_%s\n%s" % [kind.to_upper(), FX_SHADER]
		res[key] = sh
	var m := ShaderMaterial.new()
	m.shader = res[key]
	m.set_shader_parameter("uFxColor", DAU.color(o.get("color", "#ffffff")))
	m.set_shader_parameter("uFxIntensity", float(o.get("intensity", 1.0)))
	m.set_shader_parameter("uFxRim", DAU.color(o.get("rim", "#ffffff")))
	m.set_shader_parameter("uFxRimK", float(o.get("rimK", 0.5)))
	m.set_shader_parameter("uFxTime", _fxTime)
	if o.get("map") is Texture2D:
		m.set_shader_parameter("uFxMap", o.map)
	m.set_shader_parameter("uFxWorld", float(o.get("world", 0)))
	var f: Array = o.get("focus", [0.5, 0.5])
	m.set_shader_parameter("uFxFocus", Vector2(f[0], f[1]))
	m.resource_name = "wonder:" + kind
	_fxMats.append(m)
	return m

func _unregisterFx(m) -> void:
	var i := _fxMats.find(m)
	if i >= 0:
		_fxMats.remove_at(i)

# gfx cards (scripts/gfx/cards.gd): getCard(id) -> Texture2D, getAnimated(id) -> { texture, tick(time) }.
func _cardsApi():
	if game.cards != null:
		return game.cards
	if ResourceLoader.exists("res://scripts/gfx/cards.gd"):
		return load("res://scripts/gfx/cards.gd")
	return null

func _card(id: String):
	var C = _cardsApi()
	if C == null:
		return null
	for m in ["getCard", "get_", "card"]:
		if C.has_method(m):
			return C.call(m, id)
	return null

func _animated(id: String):
	var C = _cardsApi()
	if C == null:
		return null
	for m in ["getAnimated", "animated"]:
		if C.has_method(m):
			return C.call(m, id)
	return null

func _registerCues() -> void:
	# The JS registered four WebAudio recipes here (wonder_fwoomp, wonder_yeowch, wonder_freeze, wonder_shatter) when
	# audio.js lacked them. Godot plays pre-rendered cues (tools/audio renders the same recipes); only warn if absent.
	var A = game.audio
	if A == null:
		return
	var cues = _g(A, "cues")
	if cues is Dictionary:
		for id in ["wonder_fwoomp", "wonder_yeowch", "wonder_freeze", "wonder_shatter"]:
			if not cues.has(id):
				_warnOnce("cue_" + id, "audio cue '%s' not rendered (tools/audio must include wonder.js _registerCues)" % id)

func _canvasClass():
	var path := "res://scripts/gfx/canvas2d.gd"
	if not ResourceLoader.exists(path):
		return null
	return load(path)

# JS `texture.needsUpdate = true`: DACanvas re-renders by itself after drawing (nothing to do).
func _canvasDone(_cv) -> void:
	pass

# The Tiny Tele's bouncy cartoon: a private 160x120 canvas redrawn at 12 fps while a tele is live.
func _makeCartoon():
	var CV = _canvasClass()
	if CV == null:
		_warnOnce("canvas", "DACanvas (scripts/gfx/canvas2d.gd) missing: no Tiny Tele cartoon / splat marks")
		return null
	var cv = CV.new(160, 120)
	cv.bakeMode = "never"   # redrawn at 12 fps while a tele is live (DACanvas hint: keep it on the GPU)
	_cartoon = {"cv": cv, "ctx": cv.getContext("2d"), "tex": cv.texture, "frame": -1}
	_drawCartoon(0.0)
	return cv.texture

func _drawCartoon(time: float) -> void:
	var C = _cartoon
	if C == null:
		return
	var f := int(floor(time * 12.0))
	if f == C.frame:
		return
	C.frame = f
	var ctx = C.ctx
	var w := 160.0
	var h := 120.0
	var t := f / 12.0
	var sky = ctx.createLinearGradient(0, 0, 0, h)
	sky.addColorStop(0, "#FFB3D9")
	sky.addColorStop(1, "#FFE3A3")
	ctx.fillStyle = sky
	ctx.fillRect(0, 0, w, h)
	# spinning sunburst
	ctx.save()
	ctx.translate(w / 2, h * 0.55)
	ctx.rotate(t * 0.8)
	ctx.fillStyle = "rgba(255,255,255,0.35)"
	for i in 12:
		ctx.rotate(TAU / 12)
		ctx.beginPath()
		ctx.moveTo(0, 0)
		ctx.lineTo(120, -14)
		ctx.lineTo(120, 14)
		ctx.fill()
	ctx.restore()
	# checker floor in color bars
	var bars := ["#EDEDED", "#F4E03A", "#3FD6E0", "#52D24A", "#D64FD6", "#E4473A", "#3A58E4"]
	for i in 7:
		ctx.fillStyle = bars[(i + f) % 7]
		ctx.fillRect(i * (w / 7), h * 0.82, w / 7 + 1, h * 0.18)
	# bouncing blob buddy (squash & stretch)
	var ph := fmod(t * 2.5, 1.0)
	var hop := sin(ph * PI)
	var squash := 0.75 if (ph < 0.12 or ph > 0.88) else 1.0 + hop * 0.12
	var bx := w / 2 + sin(t * 1.3) * 34
	var by := h * 0.82 - 4 - hop * 46
	ctx.save()
	ctx.translate(bx, by)
	ctx.scale(1 / sqrt(squash), squash)
	ctx.fillStyle = "#E3662B"
	ctx.strokeStyle = "#2A1D3A"
	ctx.lineWidth = 3
	ctx.beginPath()
	ctx.ellipse(0, -18, 20, 18, 0, 0, TAU)
	ctx.fill()
	ctx.stroke()
	ctx.fillStyle = "#FFFFFF"
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.ellipse(s * 7, -22, 5, 6.5, 0, 0, TAU)
		ctx.fill()
		ctx.stroke()
	ctx.fillStyle = "#2A1D3A"
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.arc(s * 7 + 1.5, -21, 2.4, 0, TAU)
		ctx.fill()
	ctx.beginPath()
	ctx.arc(0, -13, 6, 0.15 * PI, 0.85 * PI)
	ctx.stroke()
	ctx.restore()
	# twinkles
	ctx.fillStyle = "#FFFFFF"
	for i in 5:
		var a := fmod(f * 0.7 + i * 1.7, 6.28)
		var x := 18 + ((i * 37 + f * 3) % 124)
		var y := 12 + ((i * 23) % 40)
		var r := 2 + absf(sin(a)) * 2.5
		ctx.beginPath()
		ctx.moveTo(x, y - r * 2)
		ctx.lineTo(x + r * 0.5, y)
		ctx.lineTo(x, y + r * 2)
		ctx.lineTo(x - r * 0.5, y)
		ctx.fill()
		ctx.beginPath()
		ctx.moveTo(x - r * 2, y)
		ctx.lineTo(x, y + r * 0.5)
		ctx.lineTo(x + r * 2, y)
		ctx.lineTo(x, y - r * 0.5)
		ctx.fill()
	# the channel 9 bug
	ctx.fillStyle = "rgba(255,255,255,0.85)"
	ctx.font = "bold 14px \"Titan One\", sans-serif"
	ctx.fillText("9", w - 16, 18)
	_canvasDone(C.cv)

# Chroma-goo splat mark (drawn in its final colours, 256 px): dark goo rim, saturated body with a lighter core, a few
# satellite drops, a glossy sheen. Lives in the 'splat' pools (fades out with the puddle; fx decals never fade).
func _splatTexture(up: bool):
	var CV = _canvasClass()
	if CV == null:
		return null
	var S := 256.0
	var H := S / 2
	var c = CV.new(256, 256)
	c.bakeMode = "now"      # static mark (DACanvas hint: bake to a mipmapped texture after the first render)
	var x = c.getContext("2d")
	var r: Callable = Rng.mulberry32(77 if up else 41)
	var P: Dictionary = Config.PAL
	var body: String = P.greenScreen if up else P.chromaBlue
	var rim := "#14803A" if up else "#0C2A8C"
	var core := "#8CF08A" if up else "#4F86FF"
	var ph: float = r.call() * TAU
	var lobes: Array = []
	for i in 9:
		var a: float = (i / 9.0) * TAU + r.call() * 0.5
		var d: float = S * (0.21 + r.call() * 0.1)
		lobes.append([H + cos(a) * d, H + sin(a) * d, S * (0.05 + r.call() * 0.05)])
	var drops: Array = []
	for i in 7:
		var a2: float = r.call() * TAU
		var d2: float = S * (0.36 + r.call() * 0.08)
		drops.append([H + cos(a2) * d2, H + sin(a2) * d2, S * (0.012 + r.call() * 0.018)])
	var shape := func(grow: float):
		x.beginPath()
		for i in 49:
			var a3 := (i / 48.0) * TAU
			var rr := S * 0.25 * (1 + 0.1 * sin(a3 * 3 + ph) + 0.06 * sin(a3 * 7 + ph * 2)) + grow
			if i == 0:
				x.moveTo(H + cos(a3) * rr, H + sin(a3) * rr)
			else:
				x.lineTo(H + cos(a3) * rr, H + sin(a3) * rr)
		x.closePath()
		x.fill()
		for L in lobes:
			x.beginPath()
			x.arc(L[0], L[1], L[2] + grow, 0, TAU)
			x.fill()
		for D in drops:
			x.beginPath()
			x.arc(D[0], D[1], D[2] + grow * 0.6, 0, TAU)
			x.fill()
	x.fillStyle = rim
	shape.call(S * 0.022)
	var gr = x.createRadialGradient(H - S * 0.05, H - S * 0.06, S * 0.02, H, H, S * 0.42)
	gr.addColorStop(0, core)
	gr.addColorStop(0.55, body)
	gr.addColorStop(1, body)
	x.fillStyle = gr
	shape.call(0.0)
	x.fillStyle = "rgba(228,255,216,0.7)" if up else "rgba(191,212,255,0.7)"
	x.beginPath()
	x.ellipse(H - S * 0.09, H - S * 0.1, S * 0.08, S * 0.04, -0.6, 0, TAU)
	x.fill()
	for D in drops:
		x.beginPath()
		x.arc(D[0] - D[2] * 0.3, D[1] - D[2] * 0.3, D[2] * 0.35, 0, TAU)
		x.fill()
	_canvasDone(c)
	res["_splatCanvas_%s" % up] = c   # keep the canvas alive (its texture is rendered by it)
	return c.texture

# ------------------------------------------------------------------------------------------ self drive / fallback
func _selfDrive(dt: float) -> void:
	if _delegated:
		return
	var g = game
	var w = g.weapons
	var p = g.player
	var slot = _curSlot()
	var input = g.input
	if input != null and dt > 0.0 and input.has_method("pressed") and input.pressed("tactical") and not (w != null and _t(_g(w, "_handlesTele"))):
		throwTele()
	if slot == null or not WONDER.has(_g(slot, "id")):
		_sdPrev = false
		return
	var ctx := _ctxSD
	var down: bool = _t(_dbgTrigger) if _dbgTrigger != null else (input != null and input.has_method("down") and _t(input.down("fire")))
	var canFire: bool = p != null and _t(_g(p, "alive")) and not _t(_g(p, "downed")) and not _t(_g(p, "sprinting")) and dt > 0.0
	ctx.triggerDown = down and canFire
	ctx.triggerPressed = ctx.triggerDown and not _sdPrev
	ctx.triggerReleased = not ctx.triggerDown and _sdPrev
	_sdPrev = ctx.triggerDown
	ctx.slot = slot
	ctx.upgraded = _t(slot.upgraded)
	ctx.def = _defOf(slot.id, slot.upgraded)
	ctx.ads = p != null and _t(_g(p, "ads"))
	ctx.dt = dt
	if p != null:
		var ray := _aimRay()
		ctx.origin = ray[0]
		ctx.dir = ray[1]
		ctx.muzzle = _pmuzzle()
	if input != null and input.has_method("pressed") and input.pressed("reload") and _dbgTrigger == null:
		_startReload(slot.id, slot, ctx.def)
	_fire(slot.id, ctx)

# ------------------------------------------------------------------------------------------ firing
func _fire(weaponId, ctx) -> bool:
	if not _ready:
		init()
	if not WONDER.has(weaponId) or ctx == null:
		return false
	var st := _state(weaponId)
	st.lastFire = float(game.time.now)
	st.ctx = ctx
	var slot = _or(ctx.get("slot"), _slotOf(weaponId))
	if slot == null:
		return false
	ctx.slot = slot
	if ctx.get("def") == null:
		ctx.def = _defOf(weaponId, _nz(ctx.get("upgraded"), slot.get("upgraded")))
	if ctx.get("upgraded") == null:
		ctx.upgraded = _t(slot.get("upgraded"))
	if reloading:
		if reloadId == weaponId:
			return false
	if weaponId == "zapper":
		return _zapperFire(ctx, st, slot)
	if weaponId == "boom_mic":
		return _boomFire(ctx, st, slot)
	return _chromaFire(ctx, st, slot)

# Empty mag: auto-reload, or dry fire on the press.
func _empty(weaponId, ctx, slot) -> bool:
	if _num(slot.mag) > 0:
		return false
	if _num(slot.reserve) > 0:
		_startReload(weaponId, slot, ctx.get("def"))
	elif _t(ctx.get("triggerPressed")):
		_emit("weapon:empty", {"weaponId": weaponId})
	return true

func _recoil(amount: float, _weaponId) -> void:
	var g = game
	var p = g.player
	var an = _g(p, "anim")
	if an != null:
		_sset(an, "recoil", 1.0)
	_sys("cam", "kick", [amount, (randf() - 0.5) * amount * 0.3])
	_kick.v -= amount * 60.0

func _startReload(weaponId, slot, def) -> float:
	if slot == null or not WONDER.has(weaponId):
		return 0.0
	if reloading and reloadId == weaponId:
		return _reloadT
	var up := _t(slot.get("upgraded"))
	var mag := _mag(weaponId, def, up)
	if _num(slot.mag) >= mag or not (_num(slot.reserve) > 0):
		return 0.0
	if weaponId == "boom_mic" and recording:
		return 0.0
	var fb: float = G.zapper.reload if weaponId == "zapper" else (G.boom.reload if weaponId == "boom_mic" else G.chroma.reload)
	var base := float(_or(_g(def, "reload"), fb))
	var mods = _g(game.player, "mods")
	reloading = true
	reloadId = weaponId
	reloadProgress = 0.0
	_reloadT = base * float(_or(_g(mods, "reloadSpeed"), 1.0))
	_reloadEl = 0.0
	_reloadSlot = slot
	_reloadMag = mag
	_reloadFx = 0
	_reloadCue = str(_or(_g(def, "reloadCue"), "reload_battery" if weaponId == "zapper" else ("reload_reel" if weaponId == "boom_mic" else "reload_goo")))
	_reloadBeat = 1
	_emit("weapon:reload", {"weaponId": weaponId})
	_play(_reloadCue, {"vol": 0.9, "rate": 0.9})
	return _reloadT

func _updateReload(dt: float) -> void:
	if not reloading:
		return
	var g = game
	var cur = _curSlot()
	if cur == null or cur.get("id") != reloadId:
		_cancelReload()
		return
	_reloadEl += dt
	var k := clamp01(_reloadEl / maxf(0.05, _reloadT))
	reloadProgress = k
	var an = _g(g.player, "anim")
	if an != null:
		_sset(an, "reload", minf(0.999, k))
	if reloadId == "zapper" and _reloadFx == 0 and k > 0.08:
		_reloadFx = 1
		_popBattery()
	# second beat: the fresh battery / reels / goo cartridge clicks home
	if _reloadBeat == 1 and k > 0.66:
		_reloadBeat = 2
		_play(_reloadCue, {"vol": 0.9, "rate": 1.15})
		if reloadId == "chroma_key":
			var parts = _heldParts()
			var m = parts.get("goo") if parts != null else null
			if m is Node3D:
				var P: Dictionary = Config.PAL
				_fx("burst", [DAU.worldPos(m), {"shape": "goo", "count": 5, "speed": 1.6, "size": 0.04, "life": 0.4,
					"colors": [P.greenScreen, "#E4FFD8"] if _t(_g(_reloadSlot, "upgraded")) else [P.chromaBlue, "#BFD4FF"]}])
	if k >= 1.0:
		var s = _reloadSlot
		if s != null and _num(s.mag) < _reloadMag:
			var n := mini(_reloadMag - int(s.mag), int(s.reserve))
			s.mag = int(s.mag) + n
			s.reserve = int(s.reserve) - n
		_cancelReload()

func _cancelReload() -> void:
	reloading = false
	reloadId = null
	reloadProgress = 0.0
	var an = _g(game.player, "anim")
	if an != null:
		_sset(an, "reload", 0.0)

# The spent battery springs out of the Zapper's rear and clatters on the floor.
func _popBattery() -> void:
	var g = game
	var p = g.player
	if p == null:
		return
	var parts = _heldParts()
	var src = parts.get("battery") if parts != null else null
	var a: Vector3 = DAU.worldPos(src) if src is Node3D else _pmuzzle()
	var R := res
	# battery.glb: the cell (mBattery, rot [PI/2,0,0]) + its ink cap (mInk, pos [0,0,-0.05]) — geo.mesh cylinders
	var bat := _dress(_loadScene("battery"))
	if bat == null:
		bat = DAU.node3d()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = 0.1
		var m := _mi(cyl, R.mBattery)
		m.rotation.x = PI / 2
		bat.add_child(m)
	var holder := DAU.node3d("wonder_battery")
	holder.add_child(bat)
	holder.position = a
	g.scene.add_child(holder)
	var yaw := float(_g(p, "yaw", 0.0))
	var b := Vector3(-sin(yaw), 0, -cos(yaw))   # player.forward()
	var st := {"t": 0.0, "bounces": 0, "vel": Vector3(-b.z * 1.2 + (randf() - 0.5), 3.2, b.x * 1.2) + b * -1.4, "spin": Vector3(9, 4, 6)}
	var fy = _floorY(a.x, a.z, a.y)
	var floor: float = float(fy) if fy != null else float(p.pos.y)
	_actors.append({
		"update": func(dt):
			st.t += dt
			st.vel.y -= 16.0 * dt
			holder.position += st.vel * dt
			holder.rotation.x += st.spin.x * dt
			holder.rotation.y += st.spin.y * dt
			if holder.position.y < floor + 0.03 and st.vel.y < 0.0:
				holder.position.y = floor + 0.03
				if st.bounces < 2:
					st.bounces += 1
					st.vel.y *= -0.38
					st.vel.x *= 0.5
					st.vel.z *= 0.5
					st.spin *= 0.5
					_play("grenade_bounce", {"pos": holder.position, "vol": 0.4, "rate": 1.6})
				else:
					st.bounces += 1
					st.vel = Vector3.ZERO
					st.spin = Vector3.ZERO
			if st.t > 2.2:
				holder.scale = Vector3.ONE * maxf(0.001, 1.0 - (st.t - 2.2) / 0.3)
			return st.t < 2.5,
		"dispose": func(): _drop(holder),
	})

func _updateWeaponState(dt: float) -> void:
	for id in _st:
		var st = _st[id]
		st.cool = maxf(0.0, st.cool - dt)
		st.buffer = maxf(0.0, st.buffer - dt)
		st.recover = maxf(0.0, st.recover - dt)
	var cur = _curSlot()
	# Boom Mic: stop recording when put away or no longer driven (sprint, swap, down).
	if recording:
		var st2 := _state("boom_mic")
		var stale: bool = float(game.time.now) - float(st2.get("lastFire", 0.0)) > 0.3
		if cur == null or cur.get("id") != "boom_mic" or stale:
			_stopRecording(false)
		else:
			_updateRecording(dt, st2)
	_kick.v += (-_kick.x * 260.0 - _kick.v * 18.0) * dt
	_kick.x += _kick.v * dt

# Held-model parts: VU needle, reels, battery, keys, goo (props weapons userData.parts).
func _heldModel():
	var m = _g(game.player, "weaponModel")
	return m if m is Node3D and is_instance_valid(m) else null

func _heldParts():
	var m = _heldModel()
	if m == null:
		return null
	var ud := DAU.ud(m)
	var cached = ud.get("__wonderParts")
	if cached is Dictionary and is_same(cached.get("model"), m):
		return cached.parts
	var parts = ud.get("parts")
	if not (parts is Dictionary) or parts.is_empty():
		parts = null
	if parts == null:
		var found := [null]
		DAU.traverse(m, func(o):
			if found[0] == null:
				var pu = DAU.ud(o).get("parts") if o.has_meta("userData") else null
				if pu is Dictionary and not pu.is_empty():
					found[0] = pu)
		parts = found[0]
	if parts == null:
		parts = {}
		for n in ["needle", "reelL", "reelR", "battery", "keys", "goo", "mic"]:
			var o = DAU.byName(m, n)
			if o != null:
				parts[n] = o
	for k in parts:
		var o = parts[k]
		if o is Node3D and not DAU.ud(o).has("__wbase"):
			_xyz(o)
			DAU.ud(o).__wbase = {"p": o.position, "r": o.rotation, "s": o.scale}
	ud.__wonderParts = {"model": m, "parts": parts}
	return parts

func _updateHeldModel(dt: float) -> void:
	var g = game
	var cur = _curSlot()
	var m = _heldModel()
	if m == null or cur == null:
		return
	var inner = DAU.byName(m, "wpn")
	if inner == null and m.get_child_count() > 0:
		inner = m.get_child(0)
	var cid = cur.get("id")
	if inner is Node3D and WONDER.has(cid):
		var iu := DAU.ud(inner)
		if not iu.has("__wrx"):
			_xyz(inner)
			iu.__wrx = inner.rotation.x
		inner.rotation.x = iu.__wrx - _kick.x
	if not WONDER.has(cid):
		return
	var parts = _heldParts()
	if parts == null:
		return
	var t := float(g.time.now)
	var rel: float = reloadProgress if (reloading and reloadId == cid) else -1.0
	if cid == "zapper":
		var keys = parts.get("keys")
		if keys is Node3D:
			var st := _state("zapper")
			var b = DAU.ud(keys).__wbase
			keys.position.y = b.p.y - (0.004 if st.cool > 0.33 else 0.0)
		var bat = parts.get("battery")
		if bat is Node3D:
			var b2 = DAU.ud(bat).__wbase
			var z := 0.0
			var vis := true
			if rel >= 0.0:
				if rel < 0.1:
					z = E.outBack(rel / 0.1) * 0.09
				elif rel < 0.55:
					vis = false
				elif rel < 0.85:
					z = (1.0 - E.outCubic(seg(rel, 0.55, 0.85))) * 0.09
			bat.position.z = b2.p.z + z
			bat.visible = vis
	elif cid == "boom_mic":
		var spin := (18.0 if _t(cur.get("upgraded")) else 10.0) if recording else 1.2
		var st2 := _state("boom_mic")
		st2.reelA = float(st2.get("reelA", 0.0)) + dt * spin
		var rs := 1.0
		if rel >= 0.0:
			rs = 1.0 - E.inBack(rel / 0.3) if rel < 0.3 else (0.0 if rel < 0.5 else E.outBack(seg(rel, 0.5, 0.8)))
		for kf in [["reelL", 1.0], ["reelR", 0.8]]:
			var o = parts.get(kf[0])
			if not (o is Node3D):
				continue
			o.rotation.y = st2.reelA * kf[1]
			o.scale = Vector3.ONE * (maxf(0.001, rs) * DAU.ud(o).__wbase.s.x)
		var needle = parts.get("needle")
		if needle is Node3D:
			var target: float = charge / 10.0 if recording else (st2.playT if st2.playT > 0.0 else 0.05 + 0.04 * sin(t * 5.0))
			if not st2.has("needle"):
				st2.needle = target
			else:
				st2.needle = lerpf(st2.needle, target + (sin(t * 31.0) * 0.035 if recording else 0.0), 1.0 - exp(-dt * 18.0))
			needle.rotation.x = 0.7 - clamp01(st2.needle) * 1.4
		var mic = parts.get("mic")
		if mic is Node3D:
			var s: float = 1.0 + (sin(t * 22.0) * 0.04 if recording else 0.0) + (st2.playT * 0.25 if st2.playT > 0.0 else 0.0)
			mic.scale = Vector3.ONE * s
		st2.playT = maxf(0.0, float(st2.get("playT", 0.0)) - dt * 1.4)
	elif cid == "chroma_key":
		var goo = parts.get("goo")
		if goo is Node3D:
			var fill := 1.0
			if rel >= 0.0:
				fill = 1.0 - E.inQuad(rel / 0.4) if rel < 0.4 else (0.05 if rel < 0.55 else E.outElastic(seg(rel, 0.55, 1.0)))
			var st3 := _state("chroma_key")
			var wob: float = sin(t * 7.0) * 0.035 + (sin(t * 40.0) * 0.08 * (st3.cool - 0.45) * 4.0 if st3.cool > 0.45 else 0.0)
			var bs: Vector3 = DAU.ud(goo).__wbase.s
			goo.scale = Vector3(bs.x * (1.0 + wob), bs.y * maxf(0.05, fill) * (1.0 - wob), bs.z * (1.0 + wob))

# ------------------------------------------------------------------------------------------ ZAPPER
func _zapperFire(ctx, st: Dictionary, slot) -> bool:
	if _t(ctx.get("triggerPressed")):
		st.buffer = 0.16
	if st.cool > 0.0 or st.buffer <= 0.0:
		return false
	if _empty("zapper", ctx, slot):
		st.buffer = 0.0
		return false
	st.buffer = 0.0
	var def = _or(ctx.get("def"), {})
	var up := _t(ctx.get("upgraded"))
	var mods = _g(game.player, "mods")
	var rpm = _g(def, "rpm")
	st.cool = (60.0 / float(rpm) if _t(rpm) else float(G.zapper.interval)) / float(_or(_g(mods, "fireRate"), 1.0))
	slot.mag = int(slot.mag) - 1
	_zap(ctx, up, def)
	return true

func _zap(ctx, up: bool, def) -> void:
	var g = game
	var Z: Dictionary = G.zapper
	var ads := _t(ctx.get("ads"))
	var ai := 1 if ads else 0
	var dr = _g(def, "range")
	var range: float = float(dr[ai]) if (dr is Array and _t(dr[ai])) else float((Z.rangeUp if up else Z.range)[ai])
	var dc = _g(def, "cone")
	var ds = _g(def, "spread")
	var cone: float
	if dc is Array and _t(dc[ai]):
		cone = float(dc[ai])
	elif ds is Array and _t(ds[ai]):
		cone = float(ds[ai])
	else:
		cone = float(Z.cone[ai])
	var chain := int(_nz(_g(def, "chain"), Z.chainUp if up else Z.chain))
	var muzzle: Vector3 = ctx.muzzle
	var origin: Vector3 = ctx.origin
	var dir: Vector3 = ctx.dir
	var first = _pickTarget(origin, dir, cone * DEG, range)
	var victims: Array = []
	if first != null:
		victims.append(first)
		var prev = first
		var hit := {_zk(first): true}
		for i in chain:
			var nxt = _nearest(prev.pos, float(_nz(_g(def, "chainR"), Z.hop)), hit, true)
			if nxt == null:
				break
			hit[_zk(nxt)] = true
			victims.append(nxt)
			prev = nxt
	# visuals: concentric ultrasonic rings along the ray, then along every jump
	var cols: Array = ["#FF5FA2", "#FFE14D", "#5FE3FF", "#9CFF57"] if up else ["#7FE7FF", "#D64FD6", "#F4E03A"]
	var end: Vector3
	if first != null:
		end = _chest(first)
	else:
		var col = _col()
		var hit2 = col.raycast(origin, dir, range) if col != null else null
		end = hit2.point if hit2 != null else origin + dir * range
	_ringTrail(muzzle, end, cols, 0.0, 9 if up else 7, 0.14)
	_fx("muzzle", [muzzle, (end - muzzle).normalized(), cols[0]])
	_fx("flashLight", [muzzle, cols[0], 6, 0.1])
	if first == null:
		_fx("burst", [end, {"shape": "static", "count": 8, "size": 0.06, "life": 0.4}])
	var delay := 0.07
	for i in victims.size():
		var z = victims[i]
		_claimed[_zk(z)] = true
		if i > 0:
			_ringTrail(_chest(victims[i - 1]), _chest(z), cols, delay - 0.06, 5, 0.1)
		_later(delay, func(): _zapHit(z, up, def))
		delay += 0.075
	_lastZap = {"t": float(g.time.now), "first": _nz(_g(first, "id"), true) if first != null else null, "victims": victims.size(), "round": _round()}
	_recoil(0.018, "zapper")
	_emit("weapon:fire", {"weaponId": "zapper", "upgraded": up})

func _zapHit(z, up: bool, def) -> void:
	var Z: Dictionary = G.zapper
	if z == null or _zstate(z) == "dying" or _t(_g(z, "dead")) or not (_hp(z) > 0.0):
		return
	var point := _chest(z)
	_fx("burst", [point, {"shape": "static", "count": 10, "size": 0.08, "life": 0.35}])
	_fx("burst", [point, {"shape": "spark", "count": 6, "size": 0.04, "speed": 4, "life": 0.25, "colors": ["#FF5FA2", "#FFE14D", "#5FE3FF"] if up else ["#7FE7FF", "#FFFFFF"]}])
	if _isBoss(z):
		_damage(z, float(_nz(_g(def, "bossDmg"), Z.boss)), "zapper", "zapper", {"upgraded": up, "point": point})
		return
	var killUpTo := int(_nz(_g(def, "killUpTo"), Z.killUpToUp if up else Z.killUpTo))
	var instant := _round() <= killUpTo
	var dmg := float(_nz(_g(def, "dmg"), Z.dmgUp if up else Z.dmg))
	var P = _doom(z, func():
		if instant:
			return _kill(z, "zapper", "zapper", {"upgraded": up, "point": point})
		return _damage(z, dmg, "zapper", "zapper", {"upgraded": up, "point": point}))
	if P != null:
		var gag: String = GAGS[int(floor(randf() * GAGS.size()))]
		_gag(z, gag, up, P)
		var pulse = _g(def, "stunPulse")
		if not _t(pulse):
			pulse = {"r": Z.pulseR, "s": Z.pulseStun} if up else null
		if pulse != null:
			_stunPulse(z.pos, float(pulse.r), float(pulse.s), z)
	else:
		_stun(z, float(_nz(_g(def, "stun"), Z.stun)))
		_akick(z, 1.0)
		_flashLive(z)

# The zombie closest to the aim ray inside the cone (half-angle): the angle is measured to the nearest point of
# its body axis (feet to head), so aiming at the head, the chest or just past the shoulder all count. A direct
# hit (zombies.raycast) always wins. Line of sight from the player's eyes.
func _pickTarget(origin: Vector3, dir: Vector3, cone: float, range: float):
	var g = game
	var p = g.player
	var best = null
	var bestScore := INF
	var eye: Vector3 = p.pos if p != null else origin
	if p != null:
		eye.y += 1.35
	var zm = g.zombies
	var direct = zm.raycast(origin, dir, range + 4) if zm != null and zm.has_method("raycast") else null
	for z in _zombies():
		if not _alive(z):
			continue
		var hgt := _zh(z)
		# closest point of the body axis to the ray (segment vs ray, clamped)
		var y0: float = z.pos.y + 0.25
		var y1: float = z.pos.y + hgt * 0.95
		var ax: float = z.pos.x - origin.x
		var az: float = z.pos.z - origin.z
		var tRay := (ax * dir.x + az * dir.z) / maxf(1e-6, dir.x * dir.x + dir.z * dir.z)
		var rayY := origin.y + dir.y * tRay
		var pp := Vector3(z.pos.x, minf(y1, maxf(y0, rayY)), z.pos.z)
		var a := pp - origin
		var d := a.length()
		if d < 1e-3:
			continue
		if p != null and Vector2(z.pos.x - p.pos.x, z.pos.z - p.pos.z).length() > range:
			continue
		var cs := a.dot(dir) / d
		if cs <= 0.0:
			continue
		var ang := acos(minf(1.0, cs)) - atan2(_zr(z) * 0.9, d)
		var isDirect: bool = direct != null and is_same(direct.get("z"), z)
		if ang > cone and not isDirect:
			continue
		if not _los(eye, _chest(z)) and not _los(eye, Vector3(z.pos.x, y1, z.pos.z)):
			continue
		var score := -1.0 if isDirect else ang
		if score < bestScore:
			bestScore = score
			best = z
	return best

func _nearest(pos: Vector3, r: float, exclude: Dictionary, los: bool = false):
	var best = null
	var bd := r
	for z in _zombies():
		if exclude.has(_zk(z)) or not _alive(z):
			continue
		var d: float = z.pos.distance_to(pos)
		if d > bd:
			continue
		if los and not _los(Vector3(pos.x, pos.y + 1.0, pos.z), Vector3(z.pos.x, z.pos.y + 1.0, z.pos.z)):
			continue
		bd = d
		best = z
	return best

func _ringTrail(from: Vector3, to: Vector3, cols: Array, delay: float, n: int, dur: float) -> void:
	var len := from.distance_to(to)
	if len < 0.05:
		return
	var q := qFromUnit(ZAXIS, (to - from).normalized())
	for i in n:
		var it: Dictionary = pools.rings.spawn()
		it.from = from
		it.to = to
		it.q = q
		it.t = 0.0
		it.delay = delay + i * (dur / n) * 0.9
		it.dur = dur + len * 0.004
		it.s0 = 0.06 + i * 0.012
		it.s1 = 0.3 + (i % 3) * 0.07
		it.base = lin(cols[i % cols.size()], 1.6)
		it.flat = false
		it.kind = "trail"

# An expanding flat ring on the floor (Channel Surfer stun pulse, tele implosion, splash).
func _floorRing(pos: Vector3, r: float, color, dur: float = 0.45, bold: bool = true, gain: float = 1.4) -> void:
	var it: Dictionary = (pools.bold if bold else pools.rings).spawn()
	it.from = Vector3(pos.x, pos.y + 0.06, pos.z)
	it.to = it.from
	it.q = qAxis(Vector3(1, 0, 0), -PI / 2)
	it.t = 0.0
	it.delay = 0.0
	it.dur = dur
	it.s0 = r * 0.15
	it.s1 = r
	it.base = lin(color, gain)
	it.kind = "grow"

func _stunPulse(pos: Vector3, r: float, s: float, except) -> void:
	_floorRing(pos, r, "#7FE7FF", 0.4, false, 0.75)
	_floorRing(pos, r * 0.7, "#FF5FA2", 0.3, false, 0.6)
	_stunRadius(pos, r, s, except)

func _later(delay: float, fn: Callable) -> void:
	var st := {"t": 0.0}
	_actors.append({"update": func(dt):
		st.t += dt
		if st.t >= delay:
			fn.call()
			return false
		return true})

# A surviving zombie flickers static for a moment (late-round zapper hit).
func _flashLive(z) -> void:
	var grp = _g(z, "group")
	if not (grp is Node) or not is_instance_valid(grp):
		return
	var meshes: Array = []
	for o in _meshes(grp, [], true):
		meshes.append([o, o.material_override])
	var R := res
	var st := {"t": 0.0}
	var restore := func():
		for om in meshes:
			var o = om[0]
			if is_instance_valid(o) and (o.material_override == R.fx.static or o.material_override == R.fx.bars):
				o.material_override = om[1]
	_actors.append({
		"update": func(dt):
			st.t += dt
			var mat = R.fx.static if st.t < 0.06 else (R.fx.bars if st.t < 0.12 else null)
			if mat == null:
				restore.call()
				return false
			for om in meshes:
				if is_instance_valid(om[0]) and not _iced(om[0]):
					om[0].material_override = mat
			return true,
		"dispose": restore,
	})

func _iced(mesh) -> bool:
	return mesh.material_override == res.mIce

# ------------------------------------------------------------------------------------------ corpses (clones)
# A frozen clone of the zombie's current pose: pivot (world pos + yaw) -> tilt -> body. The original is hidden.
func _corpse(z):
	var g = game
	var src = _g(z, "group")
	if not (src is Node3D) or not is_instance_valid(src):
		return null
	var h := _zh(z)
	var vis: bool = src.visible
	src.visible = true
	# SkeletonUtils.clone: a plain deep copy (Skeleton3D bone poses included) frozen in the current pose: no scene
	# re-instancing, no groups / signals / scripts (a copied script could keep following the live rig)
	var body = src.duplicate(0)
	src.visible = vis
	if not (body is Node3D):
		body = DAU.node3d()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = h
		var cm := _mi(cap, res.mGel)
		cm.position.y = h / 2
		body.add_child(cm)
	body.visible = true
	var P := Corpse.new()
	P.w = self
	var pivot := DAU.node3d("wonder_corpse")
	var gt: Transform3D = src.global_transform if src.is_inside_tree() else src.transform
	var sc := gt.basis.get_scale()
	pivot.position = gt.origin
	pivot.quaternion = gt.basis.get_rotation_quaternion()
	var tilt := DAU.node3d()
	pivot.add_child(tilt)
	tilt.add_child(body)
	body.position = Vector3.ZERO
	body.quaternion = Quaternion()
	body.scale = sc
	for o in _meshes(body, []):
		P.meshes.append(o)
		o.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))   # frustumCulled = false
		o.set_meta("__wmat", o.material_override)
	g.scene.add_child(pivot)
	_hide(z)
	P.pivot = pivot
	P.tilt = tilt
	P.body = body
	P.h = h
	P.blob = _sys("fx", "blob", [tilt, _zr(z) * 1.1])
	P.pos0y = pivot.position.y
	return P

func _hide(z) -> void:
	var grp = _g(z, "group")
	if not (grp is Node3D):
		return
	var k = _zk(z)
	if not _hidden.has(k):
		_hidden[k] = {"z": z, "group": grp, "t": 0.0}
	grp.visible = false

func _unhide(z) -> void:
	var k = _zk(z)
	var h = _hidden.get(k)
	if h != null:
		if is_instance_valid(h.group):
			h.group.visible = true
	else:
		var grp = _g(z, "group")
		if grp is Node3D and is_instance_valid(grp):
			grp.visible = true
	_hidden.erase(k)

func _updateHidden(dt: float) -> void:
	var alive := _zombies()
	for k in _hidden.keys():
		var h = _hidden[k]
		var z = h.z
		h.t += dt
		var grp = h.group
		if not is_instance_valid(grp):
			_hidden.erase(k)
			continue
		var dead: bool = not (_hp(z) > 0.0) or _zstate(z) == "dying" or _zstate(z) == "dead"
		var reused := false
		for o in alive:
			if not is_same(o, z) and is_same(_g(o, "group"), grp):
				reused = true
				break
		if grp.get_parent() != null and dead and not reused and h.t < 4.0:
			grp.visible = false
		else:
			grp.visible = true
			_hidden.erase(k)

func _updateActors(dt: float) -> void:
	var A := _actors
	var n := 0
	var i := 0
	while i < A.size():
		var a = A[i]
		var alive := _t(a.update.call(dt))
		if alive:
			A[n] = a
			n += 1
		elif a.has("dispose"):
			a.dispose.call()
		i += 1
	A.resize(n)

# Away-from-player direction on the floor plane.
func _away(pos: Vector3) -> Vector3:
	var p = game.player
	var out := Vector3(pos.x - (p.pos.x if p != null else 0.0), 0, pos.z - (p.pos.z if p != null else 0.0))
	if out.length_squared() < 1e-4:
		out = Vector3(0, 0, 1)
	return out.normalized()

# ------------------------------------------------------------------------------------------ channel gags
# The victim flashes 2 frames of static and 2 of color bars, then one of the five channel gags (GDD §9.4).
func _gag(z, gag: String, up: bool = false, pre = null) -> void:
	var P = pre if pre is Corpse else _corpse(z)
	if P == null:
		return
	var R := res
	var pos: Vector3 = P.pivot.position
	var away := _away(pos)
	var INTRO := 0.1
	var intro := func(t: float):
		if t < 0.05:
			P.setMat(R.fx.static)
		elif t < INTRO:
			P.setMat(R.fx.bars)
		elif not P._restored:
			P._restored = true
			P.setMat(null)
	_emit("wonder:gag", {"z": z, "gag": gag})
	var st := {"t": 0.0, "cued": false}
	var cue := func():
		if not st.cued and st.t >= INTRO:
			st.cued = true
			_play("gag_" + gag, {"pos": pos})
	var S := {"t": 0}
	var upd: Callable
	match gag:
		"cartoon":
			upd = func(_dt): return _gagCartoon(P, st.t, S)
		"western":
			upd = func(_dt): return _gagWestern(P, st.t, S, pos, away)
		"cooking":
			upd = func(_dt): return _gagCooking(P, st.t, S, pos)
		"nature":
			upd = func(_dt): return _gagNature(P, st.t, S, pos, away)
		_:
			upd = func(_dt): return _gagSignoff(P, st.t, S, pos)
	_actors.append({
		"update": func(dt):
			st.t += dt
			if gag != "signoff" or st.t < INTRO:
				intro.call(st.t)
			cue.call()
			var alive = upd.call(dt)
			P.sync()
			return alive,
		"dispose": func():
			P.dispose()
			if S.has("dispose"):
				S.dispose.call(),
	})

# CARTOON: paper-flat in 0.15 s, twists like a cardboard cutout (so the thin profile reads from the front), tips
# over backward with a flutter, slaps the floor, poofs.
func _gagCartoon(P, t: float, S: Dictionary) -> bool:
	var k1 := seg(t, 0.1, 0.25)
	var sz := lerpf(1.0, 0.02, E.outCubic(k1))
	var bulge := 1.0 + sin(k1 * PI) * 0.12
	P.tilt.scale = Vector3(bulge, 1.0 / bulge, sz)
	if k1 > 0.0 and not S.get("flat", false):
		S.flat = true
		var a: Vector3 = P.pivot.quaternion * Vector3(0, P.h * 0.55, 0) + P.pivot.position
		_fx("burst", [a, {"shape": "puff", "count": 4, "size": 0.12, "speed": 1.4, "life": 0.35, "colors": ["#FFFFFF", "#F4F1E8"]}])
	# the cutout swings edge-on (you see it is paper-thin) and flaps back
	var k2 := seg(t, 0.25, 0.58)
	P.tilt.rotation.y = sin(k2 * PI) * 1.25 + sin(k2 * TAU * 2.0) * 0.18 * (1.0 - k2)
	var k3 := seg(t, 0.58, 0.9)
	var ang := (PI / 2.0) * E.inQuad(k3)
	P.tilt.rotation.z = sin(k3 * PI * 3.0) * 0.12 * (1.0 - k3)
	var k4 := seg(t, 0.9, 1.08)
	if k4 > 0.0:
		ang = PI / 2.0 - sin(k4 * PI) * 0.16
	P.tilt.rotation.x = ang
	if t >= 0.9 and not S.get("slap", false):
		S.slap = true
		var a2: Vector3 = P.pivot.quaternion * Vector3(0, 0, P.h * 0.5) + P.pivot.position
		_fx("burst", [a2, {"shape": "puff", "count": 8, "size": 0.2, "speed": 2.4, "colors": ["#F4F1E8", "#E6DCCB"], "life": 0.5}])
		_play("telly_clonk", {"pos": a2, "vol": 0.7, "rate": 0.7})
	var k5 := seg(t, 1.12, 1.3)
	if k5 > 0.0:
		var s := 1.0 - E.inBack(k5)
		P.pivot.scale = Vector3.ONE * maxf(0.001, s)
		if not S.get("poof", false):
			S.poof = true
			var a3: Vector3 = P.pivot.quaternion * Vector3(0, 0.1, P.h * 0.5) + P.pivot.position
			_fx("burst", [a3, {"shape": "confetti", "count": 16, "colors": ["#F4F1E8", "#FFFFFF", "#E8E1D0"], "speed": 3}])
			_fx("burst", [a3, {"shape": "puff", "count": 6, "size": 0.18}])
	return t < 1.3

# WESTERN: shrinks into a tumbleweed of tangled tubes that rolls 4 m, hopping, and poofs.
func _gagWestern(P, t: float, S: Dictionary, pos: Vector3, away: Vector3) -> bool:
	var g = game
	var R := res
	if not S.has("weed"):
		var weed := _mi(R.tumble, R.mTumble)
		weed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var holder := DAU.node3d()
		holder.add_child(weed)
		holder.position = pos
		holder.scale = Vector3.ONE * 0.001
		g.scene.add_child(holder)
		var yaw := (randf() - 0.5) * 0.9
		S.dir = away.rotated(UP, yaw)
		S.dist = _clearDist(pos, S.dir, 4, 0.45)
		S.weed = weed
		S.holder = holder
		S.blob = _sys("fx", "blob", [holder, 0.32])
		S.axis = UP.cross(S.dir).normalized()
		S.bounce = 0
		S.dispose = func():
			_drop(holder)
			_hcall(S.blob, "remove")
	var k1 := seg(t, 0.1, 0.35)
	P.tilt.scale = Vector3.ONE * maxf(0.001, 1.0 - E.inBack(k1, 1.2) * 0.999)
	P.tilt.rotation.y = k1 * TAU
	var grow := E.outBack(seg(t, 0.18, 0.42))
	var k2 := seg(t, 0.35, 1.25)
	var d: float = S.dist * E.outQuad(k2)
	var hops := absf(sin(k2 * PI * 3.0)) * 0.5 * (1.0 - k2 * 0.7)
	var hp: Vector3 = pos + S.dir * d
	hp.y = pos.y + 0.36 + hops
	S.holder.position = hp
	var b := int(floor(k2 * 3.0))
	if k2 > 0.0 and b > S.bounce and b < 3:
		S.bounce = b
		_fx("burst", [Vector3(hp.x, pos.y + 0.05, hp.z), {"shape": "puff", "count": 4, "size": 0.12, "colors": ["#E0C48E", "#CDAE78"], "life": 0.5}])
	S.weed.quaternion = qAxis(S.axis, d / 0.34 + t * 2.0).normalized()
	var k3 := seg(t, 1.25, 1.42)
	S.holder.scale = Vector3.ONE * maxf(0.001, grow * (1.0 - E.inBack(k3)))
	if k3 > 0.0 and not S.get("poof", false):
		S.poof = true
		_fx("burst", [S.holder.position, {"shape": "puff", "count": 10, "size": 0.2, "colors": ["#E0C48E", "#F4E3BF"], "speed": 2.2}])
		_fx("burst", [S.holder.position, {"shape": "confetti", "count": 10, "colors": ["#C79A55", "#8A6334", "#E0C48E"], "speed": 3}])
	return t < 1.45

# COOKING: a jiggly green head-shaped gelatin mold (with a cherry) that wobbles and melts.
func _gagCooking(P, t: float, S: Dictionary, pos: Vector3) -> bool:
	var g = game
	if not S.has("mold"):
		# gelatin.glb: 'plate' (cylinder 0.42/0.36 x 0.03, mPlate) and 'mold' (the fluted jelly + eyes, mouth, cherry, stem)
		var src := _dress(_loadScene("gelatin"))
		var holder := DAU.node3d()
		var wob := DAU.node3d()
		wob.position.y = 0.03
		var mold: Node3D = DAU.node3d()
		var plate: Node3D = null
		if src != null:
			var pm = DAU.byName(src, "plate")
			var mm = DAU.byName(src, "mold")
			if pm is Node3D:
				DAU.detach(pm)
				plate = pm
			if mm is Node3D:
				DAU.detach(mm)
				mold = mm
			src.free()
		if plate != null:
			holder.add_child(plate)
		wob.add_child(mold)
		holder.add_child(wob)
		holder.position = pos
		holder.quaternion = P.pivot.quaternion
		holder.scale = Vector3.ONE * 0.001
		g.scene.add_child(holder)
		S.mold = mold
		S.holder = holder
		S.wob = wob
		S.plate = plate
		S.blob = _sys("fx", "blob", [holder, 0.45])
		S.dispose = func():
			_drop(holder)
			_hcall(S.blob, "remove")
	var k1 := seg(t, 0.1, 0.28)
	P.tilt.scale = Vector3(1.0 + k1 * 0.3, maxf(0.001, 1.0 - E.inBack(k1, 1.2)), 1.0 + k1 * 0.3)
	if k1 >= 1.0:
		P.pivot.visible = false
	var pop := E.outElastic(seg(t, 0.16, 0.7))
	S.holder.scale = Vector3.ONE * maxf(0.001, pop)
	var tw := maxf(0.0, t - 0.2)
	var sy := 1.0 + 0.2 * sin(tw * 19.0) * exp(-tw * 2.4)
	var k3 := seg(t, 0.95, 1.32)
	var sxz := 1.0 / sqrt(sy)
	if k3 > 0.0:
		sy *= lerpf(1.0, 0.07, E.inQuad(k3))
		sxz *= lerpf(1.0, 1.75, E.outQuad(k3))
		if not S.get("melt", false):
			S.melt = true
			_play("jelly_bwoing", {"pos": pos, "vol": 0.8, "rate": 0.8})
		if randf() < 0.3:
			_fx("burst", [Vector3(pos.x, pos.y + 0.1, pos.z), {"shape": "goo", "count": 1, "colors": ["#4FE06A", "#8CFF9A"], "speed": 1.5, "size": 0.06}])
	S.wob.scale = Vector3(sxz, sy, sxz)
	S.wob.rotation.z = sin(tw * 13.0) * 0.12 * exp(-tw * 2.0)
	S.wob.rotation.x = cos(tw * 11.0) * 0.08 * exp(-tw * 2.0)
	if t > 1.32 and not S.get("splat", false):
		S.splat = true
		_fx("burst", [Vector3(pos.x, pos.y + 0.1, pos.z), {"shape": "goo", "count": 10, "colors": ["#4FE06A", "#8CFF9A"], "speed": 2.5}])
	var k4 := seg(t, 1.32, 1.5)
	if k4 > 0.0:
		S.holder.scale = Vector3.ONE * maxf(0.001, 1.0 - E.inQuad(k4))
	return t < 1.5

# bunny.glb: root -> 'body' (spheres in mBunny / mInk / mPink + the 'earL' / 'earR' groups: pos (±0.06, 0.52, -0.13),
# rotation.z = ∓0.2, each a capsule 0.045/0.17 mBunny + an inner capsule 0.022/0.13 mPink).
func _buildBunny() -> Node3D:
	var b = _dress(_loadScene("bunny"))
	if b == null:
		b = DAU.node3d()
		var body := DAU.node3d("body")
		var sph := SphereMesh.new()
		sph.radius = 0.2
		sph.height = 0.4
		var m := _mi(sph, res.mBunny)
		m.position.y = 0.2
		body.add_child(m)
		for s in [-1, 1]:
			var ear := DAU.node3d("earL" if s < 0 else "earR")
			ear.position = Vector3(s * 0.06, 0.52, -0.13)
			ear.rotation.z = -s * 0.2
			body.add_child(ear)
		b.add_child(body)
	var root := DAU.node3d("wonder_bunny")
	var inner = DAU.byName(b, "body")
	if inner != null and inner != b:
		# re-root so bunny.children[0] is the body group, like the JS
		DAU.detach(inner)
		inner.owner = null   # the GLB scene root owned it (avoids the inconsistent-owner warning)
		root.add_child(inner)
		b.free()
	else:
		root.add_child(b)
	return root

# NATURE: a fluffy bunny that hops away 3 times and poofs into sparkles.
func _gagNature(P, t: float, S: Dictionary, pos: Vector3, away: Vector3) -> bool:
	var g = game
	if not S.has("bunny"):
		var bunny := _buildBunny()
		bunny.position = pos
		bunny.rotation.y = atan2(-away.x, -away.z)
		bunny.scale = Vector3.ONE * 0.001
		g.scene.add_child(bunny)
		S.bunny = bunny
		S.body = bunny.get_child(0)
		S.ears = [DAU.byName(bunny, "earL"), DAU.byName(bunny, "earR")]
		S.dir = away
		S.dist = _clearDist(pos, S.dir, 2.7, 0.4)
		S.blob = _sys("fx", "blob", [bunny, 0.25])
		S.dispose = func():
			_drop(bunny)
			_hcall(S.blob, "remove")
	var k1 := seg(t, 0.1, 0.22)
	P.tilt.scale = Vector3.ONE * maxf(0.001, 1.0 - E.inBack(k1, 1.3))
	if k1 > 0.0 and not S.get("poof1", false):
		S.poof1 = true
		_fx("burst", [Vector3(pos.x, pos.y + 0.8, pos.z), {"shape": "puff", "count": 10, "size": 0.22, "colors": ["#FFFFFF", "#F4F1E8"], "speed": 2}])
	if k1 >= 1.0:
		P.pivot.visible = false
	var pop := E.outBack(seg(t, 0.14, 0.34))
	var HOP0 := 0.34
	var HOP := 0.3
	var hk := (t - HOP0) / HOP
	var i := int(floor(hk))
	var y := 0.0
	var sq := 1.0
	var d := 0.0
	if hk >= 0.0 and i < 3:
		var f := hk - i
		y = sin(f * PI) * 0.42
		sq = 1.0 - (0.15 - f) * 2.0 if f < 0.15 else (1.0 - (f - 0.85) * 2.0 if f > 0.85 else 1.0 + sin(f * PI) * 0.18)
		d = ((i + E.inOutQuad(f)) / 3.0) * S.dist
		if i > int(S.get("lastHop", -1)):
			S.lastHop = i
			if i > 0:
				_fx("burst", [Vector3(S.bunny.position.x, pos.y + 0.03, S.bunny.position.z), {"shape": "puff", "count": 3, "size": 0.08, "life": 0.4}])
	elif hk >= 3.0:
		d = S.dist
	var bp: Vector3 = pos + S.dir * d
	bp.y = pos.y + y
	S.bunny.position = bp
	S.body.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	var earLag := cos((hk - i) * PI) * 0.5 if (hk >= 0.0 and i < 3) else 0.0
	for e in S.ears:
		if e is Node3D:
			e.rotation.x = earLag
	var k3 := seg(t, 1.28, 1.48)
	S.bunny.scale = Vector3.ONE * maxf(0.001, pop * (1.0 - E.inBack(k3)))
	if k3 > 0.0 and not S.get("poof2", false):
		S.poof2 = true
		var a := Vector3(S.bunny.position.x, S.bunny.position.y + 0.3, S.bunny.position.z)
		_fx("burst", [a, {"shape": "star", "count": 10, "speed": 2.8, "colors": ["#FFF3B0", "#FFC23A", "#FFFFFF"]}])
		_fx("burst", [a, {"shape": "confetti", "count": 12, "colors": ["#FF9EC4", "#BFE8FF", "#FFF3B0", "#C8F7C5"], "speed": 2.5}])
	return t < 1.5

# SIGN-OFF: squashes into a horizontal white line, then a dot, then gone (a CRT switching off).
func _gagSignoff(P, t: float, S: Dictionary, pos: Vector3) -> bool:
	var g = game
	var R := res
	if not S.get("init", false):
		S.init = true
		var mid: float = P.h * 0.5
		P.tilt.position.y = mid
		P.body.position.y = -mid
		var dot := _mi(R.dot, R.mWhite)
		dot.position = Vector3(pos.x, pos.y + mid, pos.z)
		dot.scale = Vector3.ONE * 0.001
		g.scene.add_child(dot)
		S.dot = dot
		for o in P.meshes:
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a glowing white line casts no shadow (and no stale one)
		S.dispose = func(): _drop(dot)
	if t < 0.05:
		P.setMat(R.fx.static)
	elif t < 0.1:
		P.setMat(R.fx.bars)
	else:
		P.setMat(R.mWhiteBody)
	var k1 := seg(t, 0.1, 0.34)
	var k2 := seg(t, 0.34, 0.56)
	var sy := lerpf(1.0, 0.012, E.inCubic(k1))
	var sx := lerpf(1.9, 0.02, E.inCubic(k2)) if k2 > 0.0 else lerpf(1.0, 1.9, E.outQuad(k1))
	var sz := lerpf(1.0, 0.02, E.inCubic(k2)) if k2 > 0.0 else 1.0
	P.tilt.scale = Vector3(sx, maxf(0.001, sy), sz)
	if k2 >= 1.0:
		P.pivot.visible = false
	var k3 := seg(t, 0.46, 1.0)
	var ds := 0.0 if k3 <= 0.0 else (E.outBack(k3 / 0.2) if k3 < 0.2 else 1.0 - E.inQuad((k3 - 0.2) / 0.8))
	S.dot.scale = Vector3.ONE * maxf(0.001, ds * 1.1)
	if k2 >= 1.0 and not S.get("flash", false):
		S.flash = true
		_fx("flashLight", [S.dot.position, "#FFFFFF", 5, 0.2])
	return t < 1.02

# ------------------------------------------------------------------------------------------ BOOM MIC
func _boomFire(ctx, st: Dictionary, slot) -> bool:
	var g = game
	_micTip = ctx.muzzle
	if recording:
		st.ctx = ctx
		var maxRec = _g(_g(ctx.get("def"), "record"), "max")
		if not _t(ctx.get("triggerDown")) or _t(ctx.get("triggerReleased")) or st.rec >= float(_nz(maxRec, G.boom.rec)):
			_playback(ctx, st)
			return true
		return false
	if st.recover > 0.0:
		return false
	if not _t(ctx.get("triggerDown")):
		return false
	if not _t(ctx.get("triggerPressed")):
		return false
	if _empty("boom_mic", ctx, slot):
		return false
	recording = true
	charge = 0.0
	st.rec = 0.0
	st.ctx = ctx
	st.up = _t(ctx.get("upgraded"))
	st.squigT = 0.0
	_recLoop = null
	if g.audio != null and g.audio.has_method("loop"):
		_recLoop = g.audio.loop("wpn_boom_record", {})
	return false

func _updateRecording(dt: float, st: Dictionary) -> void:
	var B: Dictionary = G.boom
	var ctx = st.get("ctx")
	if ctx == null or dt <= 0.0:
		return
	var RC = _g(ctx.get("def"), "record", {})
	var maxT := float(_nz(_g(RC, "max"), B.rec))
	st.rec += dt
	var zs := _inCone(ctx.origin, ctx.dir, float(_nz(_g(RC, "range"), B.recRange)), (float(_nz(_g(RC, "cone"), B.recCone)) / 2.0) * DEG)
	var count := 0.0
	var now := {}
	for z in zs:
		now[_zk(z)] = true
		count += float(_nz(_g(RC, "bossCounts"), B.bossCount)) if _isBoss(z) else 1.0
	var rate := (float(_nz(_g(RC, "chargeBase"), B.base)) + float(_nz(_g(RC, "chargePerZombie"), B.per)) * count) * float(_nz(_g(RC, "rate"), 2 if st.get("up") else 1))
	charge = minf(float(_nz(_g(RC, "chargeMax"), B.max)), charge + rate * dt)
	# slow everyone in the cone to 35 %; restore the ones that left
	for z in zs:
		_slow(z, "rec", float(_nz(_g(RC, "slow"), B.slow)))
	for k in _status.keys():
		var s = _status.get(k)
		if s != null and s.slows != null and s.slows.has("rec") and not now.has(k):
			_unslow(s.z, "rec")
	# sound squiggles fly from their mouths into the mic
	st.squigT -= dt
	if st.squigT <= 0.0 and zs.size() > 0:
		st.squigT = 0.07
		var z2 = zs[int(floor(randf() * zs.size()))]
		_squiggle(z2)
	if st.rec >= maxT:
		_playback(ctx, st)

func _inCone(origin: Vector3, dir: Vector3, range: float, half: float) -> Array:
	var out: Array = []
	var p = game.player
	var eye: Vector3 = p.pos if p != null else origin
	if p != null:
		eye.y += 1.3
	for z in _zombies():
		if not _alive(z):
			continue
		var pp := _chest(z)
		var a := pp - eye
		var d := a.length()
		if d > range or d < 1e-3:
			continue
		var b := Vector3(dir.x, dir.y * 0.35, dir.z).normalized()
		a /= d
		var cs := a.dot(b)
		var pad := atan2(_zr(z), d)
		if acos(clampf(cs, -1.0, 1.0)) > half + pad and d > 1.4:
			continue
		if not _los(eye, pp):
			continue
		out.append(z)
	return out

func _squiggle(z) -> void:
	var it: Dictionary = pools.squig.spawn()
	var from := _headPos(z)
	var yaw = _g(z, "yaw")
	var face := Vector3(-sin(yaw), 0, -cos(yaw)) if yaw != null else Vector3.ZERO
	from += face * 0.2
	from.y -= 0.08
	it.from = from
	it.t = 0.0
	it.dur = 0.34 + randf() * 0.14
	it.seed = randf() * TAU
	it.base = lin(["#7FE7FF", "#FF5FA2", "#FFE14D", "#9CFF57"][int(floor(randf() * 4))], 1.25)

func _stopRecording(keep: bool) -> void:
	if _recLoop != null:
		_hcall(_recLoop, "stop", [0.08])
		_recLoop = null
	if recording and not keep:
		charge = 0.0
	recording = false
	for k in _status.keys():
		if _status.has(k):
			_unslow(_status[k].z, "rec")

func _playback(ctx, st: Dictionary) -> void:
	var g = game
	var B: Dictionary = G.boom
	var slot = ctx.get("slot")
	var ch0 := charge
	var up := _t(st.get("up"))
	_stopRecording(true)
	if slot != null:
		slot.mag = maxi(0, int(slot.mag) - 1)
	st.recover = B.recover
	st.playT = clamp01(ch0 / 10.0)
	charge = 0.0
	var origin: Vector3 = ctx.origin
	var fwd := Vector3(ctx.dir.x, 0, ctx.dir.z)
	if fwd.length_squared() < 1e-4:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var cones: Array = [[fwd, ch0]]
	if up:
		var back := -fwd
		var left := Vector3(-fwd.z, 0, fwd.x)
		var right := -left
		for d in [back, left, right]:
			cones.append([d, ch0 / 2.0])
	var def = ctx.get("def")
	var killUpTo := int(_nz(_g(def, "killUpTo"), B.killUpToUp if up else B.killUpTo))
	var PB = _g(def, "playback", {})
	var done := {}
	var victims := 0
	for ci in cones.size():
		var dir: Vector3 = cones[ci][0]
		var ch: float = cones[ci][1]
		var full := ci == 0
		var aim: Vector3 = ctx.dir if full else dir
		_shockwave(_micTip, dir, ch, full)
		var list := _inCone(origin, aim, B.range, (B.cone / 2.0) * DEG)
		for z in list:
			var k = _zk(z)
			if done.has(k):
				continue
			done[k] = true
			if _isBoss(z):
				_damage(z, float(_nz(_g(PB, "bossPerCharge"), B.boss)) * ch, "boom_mic", "boom_mic", {"upgraded": up})
				continue
			if ch >= float(_nz(_g(PB, "killCharge"), B.killAt)):
				var instant := _round() <= killUpTo
				var dmg := float(_nz(_g(PB, "dmgAfter"), B.late)) * (ch / 10.0)
				var P = _doom(z, func():
					if instant:
						return _kill(z, "boom_mic", "boom_mic", {"upgraded": up, "dir": dir})
					return _damage(z, dmg, "boom_mic", "boom_mic", {"upgraded": up, "dir": dir}))
				if P != null:
					_tumble(z, dir, victims, P)
					victims += 1
				else:
					_knock(z, dir, float(_nz(_g(PB, "knock"), B.knock)) * 0.5, float(_nz(_g(PB, "stun"), B.weakStun)))
			else:
				var weak := float(_nz(_g(PB, "weakDmg"), B.weak))
				var P2 = _doom(z, func(): return _damage(z, weak, "boom_mic", "boom_mic", {"upgraded": up, "dir": dir}))
				if P2 != null:
					_tumble(z, dir, victims, P2)
					victims += 1
				else:
					_knock(z, dir, float(_nz(_g(PB, "knock"), B.knock)), float(_nz(_g(PB, "stun"), B.weakStun)))
	_play("wpn_boom_playback", {"upgraded": up})
	if up:
		_play("wpn_upgraded_sparkle")
	_recoil(0.035, "boom_mic")
	_sys("cam", "shake", [0.18 + ch0 * 0.02, 0.35])
	_fx("flashLight", [_micTip, "#FF5FA2", 5 + ch0, 0.15])
	_emit("weapon:fire", {"weaponId": "boom_mic", "upgraded": up})

# Translucent sound rings expanding along a 50° cone.
func _shockwave(from: Vector3, dir: Vector3, ch: float, full: bool) -> void:
	var n := 7 if full else 4
	var B: Dictionary = G.boom
	var len := _clearDist(from, dir, B.range, 0.2) + 0.5
	var q := qFromUnit(ZAXIS, dir.normalized())
	var cols := ["#FF5FA2", "#FFE14D", "#7FE7FF", "#FFFFFF"]
	var strength := 0.6 + clamp01(ch / 10.0) * 0.9
	for i in n:
		var it: Dictionary = pools.bold.spawn()
		it.from = from
		it.to = from + dir * len
		it.q = q
		it.t = 0.0
		it.delay = i * 0.05
		it.dur = 0.5
		it.s0 = 0.18
		it.s1 = tan((B.cone / 2.0) * DEG) * len * (1.0 if full else 0.8)
		it.base = lin(cols[i % cols.size()], 0.42 * strength * (1.0 if full else 0.7))
		it.kind = "cone"

func _knock(z, dir: Vector3, dist: float, stun: float) -> void:
	_stun(z, stun)
	_akick(z, 1.2)
	var col = _col()
	if col == null or _g(z, "pos") == null:
		return
	var st := {"t": 0.0}
	var d := Vector3(dir.x, 0, dir.z).normalized()
	_actors.append({"update": func(dt):
		if not _alive(z) and _zstate(z) != "dying":
			return false
		st.t += dt
		var k := maxf(0.0, 1.0 - st.t / 0.28)
		_moveCircle(z, d * (dist * 3.6 * k * dt), _zr(z, 0.35), _zh(z), 0.45)
		var grp = _g(z, "group")
		if grp is Node3D:
			grp.position = z.pos
		return st.t < 0.28})

# Playback death: tumbles backward head over heels, then pops into confetti (while its groan replays at 2x).
func _tumble(z, dir: Vector3, i: int, pre = null) -> void:
	var P = pre if pre is Corpse else _corpse(z)
	if P == null:
		return
	var pos: Vector3 = P.pivot.position
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var dist := _clearDist(pos, d, 3.2 + randf() * 1.6, 0.5)
	var mid: float = P.h * 0.5
	P.tilt.position.y = mid
	P.body.position.y = -mid
	# spin backward relative to the zombie's own facing
	var local: Vector3 = P.pivot.quaternion.inverse() * d
	var axis := Vector3(local.z, 0, -local.x).normalized()
	var turns := 1.0 + randf() * 0.6
	var dur := 0.72 + randf() * 0.12
	var st := {"t": 0.0, "popped": false}
	if i < 4:
		_later(0.05 + i * 0.07, func(): _play("zmb_groan", {"pos": pos, "rate": 2, "vol": 0.8}))
	_actors.append({
		"update": func(dt):
			st.t += dt
			var k := clamp01(st.t / dur)
			var pp: Vector3 = pos + d * (dist * E.outQuad(k))
			pp.y = pos.y + sin(k * PI) * (1.1 + dist * 0.12)
			P.pivot.position = pp
			P.tilt.quaternion = qAxis(axis, -k * TAU * turns).normalized()
			var sq := 1.0 + sin(k * PI * 3.0) * 0.08
			P.tilt.scale = Vector3(1.0 / sq, sq, 1.0 / sq)
			if k >= 1.0 and not st.popped:
				st.popped = true
				var a := Vector3(pp.x, pp.y + mid, pp.z)
				_fx("burst", [a, {"shape": "confetti", "count": 26, "speed": 5}])
				_fx("burst", [a, {"shape": "puff", "count": 6, "size": 0.2}])
				_fx("burst", [a, {"shape": "star", "count": 4}])
				_play("zmb_head_pop", {"pos": a, "rate": 1.3, "vol": 0.8})
			P.sync()
			return not st.popped,
		"dispose": func(): P.dispose(),
	})

# ------------------------------------------------------------------------------------------ CHROMA-KEY
func _chromaFire(ctx, st: Dictionary, slot) -> bool:
	if _t(ctx.get("triggerPressed")):
		st.buffer = 0.16
	if st.cool > 0.0 or st.buffer <= 0.0:
		return false
	if _empty("chroma_key", ctx, slot):
		st.buffer = 0.0
		return false
	st.buffer = 0.0
	var def = _or(ctx.get("def"), {})
	var up := _t(ctx.get("upgraded"))
	var mods = _g(game.player, "mods")
	var rpm = _g(def, "rpm")
	st.cool = (60.0 / float(rpm) if _t(rpm) else float(G.chroma.interval)) / float(_or(_g(mods, "fireRate"), 1.0))
	slot.mag = int(slot.mag) - 1
	_launchBlob(ctx, up, def)
	_recoil(0.03, "chroma_key")
	_emit("weapon:fire", {"weaponId": "chroma_key", "upgraded": up})
	return true

func _launchBlob(ctx, up: bool, def) -> void:
	var g = game
	var C: Dictionary = G.chroma
	var R := res
	var origin: Vector3 = ctx.origin
	var cdir: Vector3 = ctx.dir
	# aim point: first zombie / wall along the camera ray
	var col = _col()
	var wall = col.raycast(origin, cdir, 60) if col != null else null
	var zm = g.zombies
	var zh = zm.raycast(origin, cdir, float(wall.dist) if wall != null else 60.0) if zm != null and zm.has_method("raycast") else null
	var target: Vector3 = zh.point if zh != null else (wall.point if wall != null else origin + cdir * 40.0)
	var from: Vector3 = ctx.muzzle
	var B = _g(def, "blob", {})
	var speed := float(_nz(_g(B, "speed"), C.speed))
	var grav := float(_nz(_g(B, "gravity"), C.grav))
	var vel = _ballistic(from, target, speed, grav)
	if vel == null:
		vel = (target - from).normalized() * speed
	var r := float(_nz(_g(B, "r"), C.r))
	var mesh := _mi(R.blobGeo, R.mGooUp if up else R.mGoo)
	mesh.scale = Vector3.ONE * r
	mesh.position = from
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	g.scene.add_child(mesh)
	_blobs.append({"pos": from, "vel": vel, "t": 0.0, "up": up, "def": def, "mesh": mesh, "bounces": int(_nz(_g(B, "bounces"), 1 if up else 0)), "r": r, "grav": grav,
		"life": float(_nz(_g(B, "life"), C.fuse)), "trail": 0.0, "seed": randf() * 10.0, "squash": 0.0})
	var P: Dictionary = Config.PAL
	_fx("burst", [from, {"shape": "goo", "count": 6, "dir": vel.normalized(), "cone": 0.5, "speed": 4, "size": 0.07, "colors": [P.greenScreen, "#9CFF57"] if up else [P.chromaBlue, "#4F86FF"]}])

# Low-arc launch velocity reaching `to` at `speed` under gravity g (null when out of range).
func _ballistic(from: Vector3, to: Vector3, speed: float, grav: float):
	var dx := to.x - from.x
	var dz := to.z - from.z
	var dy := to.y - from.y
	var x := sqrt(dx * dx + dz * dz)
	if x < 0.5:
		return null
	var v2 := speed * speed
	var disc := v2 * v2 - grav * (grav * x * x + 2.0 * dy * v2)
	if disc < 0.0:
		return null
	var ang := atan2(v2 - sqrt(disc), grav * x)
	var h := cos(ang) * speed
	return Vector3((dx / x) * h, sin(ang) * speed, (dz / x) * h)

func _updateBlobs(dt: float) -> void:
	if _blobs.is_empty() or dt <= 0.0:
		return
	var g = game
	var col = _col()
	var zm = g.zombies
	var P: Dictionary = Config.PAL
	for i in range(_blobs.size() - 1, -1, -1):
		var b: Dictionary = _blobs[i]
		b.t += dt
		var burst = null
		var direct = null
		var normal = null
		var steps := maxi(1, int(ceil((b.vel.length() * dt) / 0.3)))
		var h := dt / steps
		var s := 0
		while s < steps and burst == null:
			b.vel.y -= b.grav * h
			var len: float = b.vel.length() * h
			var d: Vector3 = b.vel.normalized()
			var zh = zm.raycast(b.pos, d, len + b.r) if zm != null and zm.has_method("raycast") else null
			var wh = col.raycast(b.pos, d, len + b.r) if col != null else null
			if zh != null and (wh == null or float(zh.dist) <= float(wh.dist)) and _alive(zh.z):
				burst = zh.point
				direct = zh.z
				normal = -d
				break
			if wh != null:
				if b.bounces > 0:
					b.bounces -= 1
					b.squash = 1.0
					b.pos = wh.point + wh.normal * (b.r + 0.02)
					b.vel = reflect(b.vel, wh.normal) * 0.62
					_play("grenade_bounce", {"pos": b.pos, "rate": 0.6, "vol": 0.6})
					_fx("burst", [b.pos, {"shape": "goo", "count": 6, "colors": [P.greenScreen, "#9CFF57"], "dir": wh.normal, "speed": 3}])
					s += 1
					continue
				burst = wh.point
				normal = wh.normal
				break
			b.pos += b.vel * h
			var f = _floorY(b.pos.x, b.pos.z, b.pos.y + 0.3)
			if f != null and b.pos.y - b.r < f:
				if b.bounces > 0:
					b.bounces -= 1
					b.squash = 1.0
					b.pos.y = f + b.r
					b.vel.y = absf(b.vel.y) * 0.6
					b.vel.x *= 0.75
					b.vel.z *= 0.75
					_play("grenade_bounce", {"pos": b.pos, "rate": 0.6, "vol": 0.6})
					s += 1
					continue
				burst = Vector3(b.pos.x, f + 0.02, b.pos.z)
				normal = Vector3(0, 1, 0)
			s += 1
		if burst == null and b.t >= b.life:
			burst = b.pos
			normal = Vector3(0, 1, 0)
		# goo wobble (+ a bounce squash) stretched along the flight, trail
		b.squash = maxf(0.0, b.squash - dt * 5.0)
		var w := sin(b.t * 30.0 + b.seed) * 0.12
		var sp := minf(0.35, b.vel.length() * 0.012)
		b.mesh.position = b.pos
		b.mesh.quaternion = qFromUnit(ZAXIS, b.vel.normalized())
		var sq: float = b.squash * 0.45
		b.mesh.scale = Vector3(b.r * (1.0 + w + sq), b.r * (1.0 - w + sq), b.r * (1.0 + sp - sq * 1.2))
		b.trail -= dt
		if b.trail <= 0.0:
			b.trail = 0.035
			_fx("burst", [b.pos, {"shape": "goo", "count": 1, "speed": 0.4, "size": 0.05, "life": 0.4, "colors": [P.greenScreen] if b.up else [P.chromaBlue]}])
		if burst != null:
			_drop(b.mesh)
			_blobs.remove_at(i)
			_splash(burst, normal, b.up, b.def, direct)

func _splash(pos: Vector3, normal, up: bool, def, direct) -> void:
	var C: Dictionary = G.chroma
	var P: Dictionary = Config.PAL
	var r := float(_or(_g(_g(def, "splash"), "r"), C.splashUp if up else C.splash))
	var cols: Array = [P.greenScreen, "#9CFF57", "#E4FFD8"] if up else [P.chromaBlue, "#4F86FF", "#BFD4FF"]
	_play("wpn_chroma_splat", {"pos": pos})
	_fx("burst", [pos, {"shape": "goo", "count": 22, "colors": cols, "dir": normal, "cone": 1.1, "speed": 5.5, "size": 0.1}])
	_fx("burst", [pos, {"shape": "spark", "count": 10, "colors": cols, "speed": 6}])
	# walls / floor only (a body would leave it mid-air); fades out with the puddle (the old fx decal never went away)
	if direct == null:
		_splat(pos, normal, up, float(_nz(_g(_g(def, "puddle"), "life"), C.puddleTUp if up else C.puddleT)))
	_fx("flashLight", [pos, cols[0], 7, 0.25])
	# the splash ring and the puddle sit on the floor below the burst (a body hit bursts at chest height)
	var f = _splashFloor(pos, r)
	var onFloor: bool = f != null and pos.y - f < 2.6
	_floorRing(Vector3(pos.x, f, pos.z) if onFloor else pos, r, cols[0], 0.35, true, 0.8)
	if direct != null and _isBoss(direct):
		_damage(direct, float(_nz(_g(def, "bossDmg"), C.boss)), "chroma_key", "chroma_key", {"upgraded": up})
	var eye: Vector3 = pos + (normal if normal is Vector3 else UP) * 0.3
	for z in _zombies().duplicate():
		if not _alive(z) or _isBoss(z):
			continue
		var pp := _chest(z)
		if pp.distance_to(pos) > r + _zr(z) and z.pos.distance_to(pos) > r:
			continue
		if not _los(eye, pp) and not _los(eye, Vector3(z.pos.x, z.pos.y + 0.3, z.pos.z)):
			continue
		_keyZombie(z, up, def, not is_same(z, direct))
	if onFloor:
		_spawnPuddle(Vector3(pos.x, f, pos.z), up, def)

# Goo splat mark on the surface hit (normal), gone after `dur` s (= the puddle's lifetime): pops in, then fades
# and shrinks a little over its last second, together with the puddle's shrink (see _updatePools).
func _splat(pos: Vector3, normal, up: bool, dur: float) -> Dictionary:
	var it: Dictionary = (pools.splatUp if up else pools.splat).spawn()
	var n: Vector3 = normal if normal is Vector3 else UP
	it.q = qFromUnit(ZAXIS, n) * qAxis(ZAXIS, randf() * TAU)
	it.pos = pos + n * 0.006
	it.size = 1.1
	it.t = 0.0
	it.dur = maxf(0.5, dur if dur > 0.0 else float(G.chroma.puddleT))
	it.m = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	it.c = Color(0, 0, 0, 1)
	return it

# Floor height for a splash: the most common floor among the burst point and 8 samples around it, so a blob
# that bursts on a stool, a crate or a desk corner spills its puddle onto the floor around it (the prop hides
# part of it) instead of a 3 m disc floating at the prop's top; on a riser or the stage it stays up there.
func _splashFloor(pos: Vector3, r: float):
	var yFrom := pos.y + 0.2
	var hs: Array = []
	var f0 = _floorY(pos.x, pos.z, yFrom)
	if f0 != null:
		hs.append(f0)
	var rr := minf(1.8, r * 0.6)
	for i in 8:
		var a := (i / 8.0) * TAU
		var f = _floorY(pos.x + cos(a) * rr, pos.z + sin(a) * rr, yFrom)
		if f != null:
			hs.append(f)
	if hs.is_empty():
		return null
	var best: float = hs[0]
	var bestN := 0
	for h in hs:
		var n := 0
		for o in hs:
			if absf(o - h) < 0.15:
				n += 1
		if n > bestN or (n == bestN and h < best):
			best = h
			bestN = n
	return best

# Keyed: instant kill up to r25 (r35 upgraded), else 6,000 damage; the keyed swirl plays on the corpse.
func _keyZombie(z, up: bool, def, splash: bool = false) -> bool:
	var C: Dictionary = G.chroma
	_claimed[_zk(z)] = true
	var killUpTo := int(_nz(_g(def, "killUpTo"), C.killUpToUp if up else C.killUpTo))
	var instant := _round() <= killUpTo
	var extra := {"upgraded": up, "splash": splash}
	var dmg := float(_nz(_g(def, "dmg"), C.late))
	var P = _doom(z, func():
		if instant:
			return _kill(z, "chroma_key", "chroma_key", extra)
		return _damage(z, dmg, "chroma_key", "chroma_key", extra))
	if P != null:
		_keyed(z, up, null, P, def)
	else:
		_claimed.erase(_zk(z))
		_flashLive(z)
	return P != null

# Flat chroma color (0.3 s) -> a zombie-shaped window onto stock footage (0.8 s) -> swirls into a point (0.4 s).
func _keyed(z, up: bool, forceWorld = null, pre = null, def = null) -> void:
	var P = pre if pre is Corpse else _corpse(z)
	if P == null:
		return
	var R := res
	var worlds: Array = (WORLDS + WORLDS_UP) if up else WORLDS
	var dw = _g(def, "worlds")
	if dw is Array:
		var fromDef: Array = []
		for w in dw:
			var s := str(w)
			if s.begins_with("world_"):
				s = s.substr(6)
			if R.foot.has(s):
				fromDef.append(s)
		if not fromDef.is_empty():
			worlds = fromDef
	var world: String = str(forceWorld) if _t(forceWorld) else worlds[int(floor(randf() * worlds.size()))]
	var pos: Vector3 = P.pivot.position
	var mid: float = P.h * 0.5
	P.tilt.position.y = mid
	P.body.position.y = -mid
	_emit("wonder:key", {"z": z, "world": world})
	_play("wpn_chroma_key", {"pos": pos})
	var st := {"t": 0.0, "sounded": false, "flashed": false}
	var tint: String = WORLD_TINT[world]
	# own footage material (same program): its uFxFrame follows this body on screen
	var foot := _fxMaterial("footage", R.footOpts[world])
	_actors.append({
		"update": func(dt):
			st.t += dt
			var t: float = st.t
			var pp: Vector3 = P.pivot.position
			foot.set_shader_parameter("uFxFrame", _screenFrame(Vector3(pp.x, pp.y + mid, pp.z), P.h * maxf(0.3, P.tilt.scale.y)))
			if t < 0.3:
				P.setMat(R.fx.flatUp if up else R.fx.flat)
				var k := t / 0.3
				var s := 1.0 + sin(k * PI) * 0.07
				P.tilt.scale = Vector3(1.0 / s, s, 1.0 / s)
			elif t < 1.1:
				P.setMat(foot)
				if not st.sounded:
					st.sounded = true
					_play("world_" + world, {"pos": pos})
				P.pivot.position.y = pos.y + sin((t - 0.3) * 5.0) * 0.03 + (t - 0.3) * 0.08
				if randf() < 0.35:
					var a := Vector3((randf() - 0.5) * 0.7, randf() * P.h, (randf() - 0.5) * 0.7) + pos
					_fx("burst", [a, {"shape": "star", "count": 1, "size": 0.07, "speed": 0.6, "life": 0.5, "colors": [tint, "#FFFFFF"]}])
			else:
				var k2 := seg(t, 1.1, 1.5)
				P.tilt.rotation.y += dt * (8.0 + k2 * 40.0)
				var sxz := 1.0 - E.inCubic(k2)
				var sy := 1.0 - E.inQuad(k2) * 0.98
				P.tilt.scale = Vector3(maxf(0.001, sxz), maxf(0.001, sy), maxf(0.001, sxz))
				P.pivot.position.y = pos.y + 0.064 + k2 * 0.5
				if randf() < 0.6:
					var ang := t * 20.0
					var a2: Vector3 = Vector3(cos(ang) * 0.5 * sxz, mid + (randf() - 0.5) * P.h * sy, sin(ang) * 0.5 * sxz) + P.pivot.position
					_fx("burst", [a2, {"shape": "spark", "count": 1, "speed": 0.5, "size": 0.04, "life": 0.25, "colors": [tint]}])
				if k2 >= 1.0 and not st.flashed:
					st.flashed = true
					var a3: Vector3 = P.pivot.position + Vector3(0, mid, 0)
					_fx("burst", [a3, {"shape": "star", "count": 6, "speed": 2.2, "colors": [tint, "#FFFFFF"]}])
					_fx("flashLight", [a3, tint, 4, 0.12])
			P.sync()
			return st.t < 1.5,
		"dispose": func():
			P.dispose()
			_unregisterFx(foot),
	})

# Projected centre and on-screen height of a body of height h (NDC: the shader turns them into pixels).
func _screenFrame(center: Vector3, h: float) -> Vector3:
	var cam = game.camera
	if cam == null or not is_instance_valid(cam):
		return Vector3(0, 0, 0.8333)
	var a := _project(cam, center)
	var b := _project(cam, Vector3(center.x, center.y + h * 0.5, center.z))
	var c := _project(cam, Vector3(center.x, center.y - h * 0.5, center.z))
	return Vector3(a.x, a.y, absf(b.y - c.y))

# Vector3.project(camera): world -> NDC (y up).
static func _project(cam: Camera3D, p: Vector3) -> Vector3:
	var gt: Transform3D = cam.global_transform if cam.is_inside_tree() else cam.transform
	var v: Vector3 = gt.affine_inverse() * p
	var clip: Vector4 = cam.get_camera_projection() * Vector4(v.x, v.y, v.z, 1.0)
	if absf(clip.w) < 1e-9:
		return Vector3.ZERO
	return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)

func _spawnPuddle(pos: Vector3, up: bool, def = null) -> void:
	var g = game
	var C: Dictionary = G.chroma
	var R := res
	var P: Dictionary = Config.PAL
	var PD = _g(def, "puddle", {})
	var r := float(_nz(_g(PD, "r"), C.puddleR))
	var mesh := _mi(R.puddle, R.mPuddleUp if up else R.mPuddle, "wonder_puddle")
	mesh.position = Vector3(pos.x, pos.y + 0.012, pos.z)
	mesh.rotation.y = randf() * TAU
	mesh.scale = Vector3(0.001, 1, 0.001)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rim := _mi(R.puddle, R.mPuddleRimUp if up else R.mPuddleRim)
	rim.scale = Vector3(1.08, 1, 1.08)
	rim.position.y = -0.004
	var sheen := _mi(R.puddleSheen, R.mPuddleSheenUp if up else R.mPuddleSheen)
	sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheen.scale = Vector3(0.34, 1, 0.22)
	sheen.position = Vector3(0.22, 0.003, -0.2)
	sheen.rotation.y = 0.6
	mesh.add_child(rim)
	mesh.add_child(sheen)
	g.scene.add_child(mesh)
	var pool = _sys("fx", "lightPool", [pos, r * 1.2, P.greenScreen if up else P.chromaBlue, 0.0])
	_puddles.append({"pos": pos, "r": r, "t": 0.0, "dur": float(_nz(_g(PD, "life"), C.puddleTUp if up else C.puddleT)),
		"keys": int(_nz(_g(PD, "keys"), C.puddleNUp if up else C.puddleN)), "up": up, "def": def, "mesh": mesh, "pool": pool, "bub": 0.0})

func _disposePuddle(p) -> void:
	_drop(p.mesh)
	_hcall(p.pool, "remove")

func _updatePuddles(dt: float) -> void:
	var P: Dictionary = Config.PAL
	for i in range(_puddles.size() - 1, -1, -1):
		var p: Dictionary = _puddles[i]
		p.t += dt
		var kIn := E.outElastic(clamp01(p.t / 0.5))
		var kOut := 1.0 - E.inQuad(seg(p.t, p.dur - 0.5, p.dur))
		var wob := 1.0 + sin(p.t * 5.0) * 0.02
		var s: float = p.r * maxf(0.001, kIn * kOut)
		p.mesh.scale = Vector3(s * wob, 1, s / wob)
		if p.pool != null:
			_hcall(p.pool, "set_", [{"intensity": 0.22 * kIn * kOut}])   # handle.set() (renamed set_, §3.2)
		p.bub -= dt
		if p.bub <= 0.0:
			p.bub = 0.12
			var a := randf() * TAU
			var rr: float = sqrt(randf()) * p.r * 0.8 * kOut
			var bp := Vector3(p.pos.x + cos(a) * rr, p.pos.y + 0.05, p.pos.z + sin(a) * rr)
			_fx("burst", [bp, {"shape": "goo", "count": 1, "speed": 1.2, "size": 0.05, "life": 0.35, "gravity": 6, "dir": UP, "cone": 0.2,
				"colors": [P.greenScreen, "#E4FFD8"] if p.up else [P.chromaBlue, "#BFD4FF"]}])
		if p.keys > 0 and p.t < p.dur - 0.3:
			for z in _zombies().duplicate():
				if p.keys <= 0:
					break
				if not _alive(z) or _isBoss(z):
					continue
				var dx: float = z.pos.x - p.pos.x
				var dz: float = z.pos.z - p.pos.z
				if dx * dx + dz * dz > pow(p.r * 0.92, 2.0) or absf(z.pos.y - p.pos.y) > 0.8:
					continue
				if _keyZombie(z, p.up, p.def):
					p.keys -= 1
		if p.t >= p.dur:
			_disposePuddle(p)
			_puddles.remove_at(i)

# ------------------------------------------------------------------------------------------ TINY TELE
func _teleProto():
	if _tele0 != null:
		return _tele0 if _tele0 is Node3D else null
	var g = game
	var proto = null
	if g.props != null and g.props.has_method("build"):
		proto = g.props.build("tiny_tele", {"pose": "display", "unique": true})
	if proto is Node3D:
		_tele0 = proto
	else:
		push_warning("[wonder] tiny_tele prop unavailable, using a placeholder")
		var gp := DAU.node3d()
		var R := res
		var bm := BoxMesh.new()   # geo.roundedBox(0.3, 0.23, 0.22, 0.05, 2)
		bm.size = Vector3(0.3, 0.23, 0.22)
		var box := _mi(bm, _toon(Config.PAL.burntOrange, {"keepColor": true, "rough": 0.4}))
		box.position = Vector3(0, 0.13, 0)
		gp.add_child(box)
		var qm := QuadMesh.new()
		qm.size = Vector2(0.18, 0.14)
		var scr := _mi(qm, _screenMat(null, {"w": 0.18, "h": 0.14}), "screen")
		scr.position = Vector3(-0.03, 0.13, -0.112)
		scr.rotation.y = PI
		gp.add_child(scr)
		var ant := DAU.node3d("antenna")
		ant.position = Vector3(0.08, 0.25, 0.05)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.005
		cm.bottom_radius = 0.005
		cm.height = 0.25
		var am := _mi(cm, R.mInk)
		am.position.y = 0.12
		ant.add_child(am)
		gp.add_child(ant)
		_tele0 = gp
	return _tele0

func _spawnTele(ctx = null):
	var g = game
	var p = g.player
	var TT := _teleDef()
	var proto = _teleProto()
	if proto == null or p == null:
		return null
	var root := DAU.node3d("wonder_tiny_tele")
	var model: Node3D = proto.duplicate(Node.DUPLICATE_SCRIPTS)
	model.scale = Vector3.ONE * float(TT.scale)
	var spin := DAU.node3d()
	spin.add_child(model)
	root.add_child(spin)
	var screen = DAU.byName(model, "screen")
	var screenMat := _screenMat(_screenTex, {"w": 0.18, "h": 0.142, "bright": 1.1})
	if screen is GeometryInstance3D:
		screen.material_override = screenMat
	var snow = _snowTex()
	_setScreenMap(screenMat, snow if snow != null else _screenTex)
	var parts := {"ant": DAU.byName(model, "antenna"), "ant2": DAU.byName(model, "ant2"), "ant3": DAU.byName(model, "ant3")}
	for k in parts:
		_xyz(parts[k])
	# weapons hands over the throw (left hand + velocity); otherwise lob it from the right hand along the aim
	var a: Vector3
	var vel: Vector3
	if ctx != null:
		a = ctx.origin
		vel = ctx.velocity
	else:
		var hand = _g(_g(_g(p, "hero"), "slots"), "handR")
		if hand is Node3D:
			a = DAU.worldPos(hand)
		else:
			a = Vector3(p.pos.x, p.pos.y + 1.3, p.pos.z)
		var d: Vector3 = _aimRay()[1]
		vel = Vector3(d.x, 0, d.z).normalized() * (float(TT.speed) * maxf(0.35, cos(asin(clampf(d.y, -1.0, 1.0)))))
		vel.y = float(TT.up) + d.y * float(TT.speed) * 0.8
	root.position = a
	g.scene.add_child(root)
	var tele := {
		"root": root, "spin": spin, "model": model, "screen": screen, "screenMat": screenMat, "parts": parts, "pos": root.position, "vel": vel,
		"state": "fly", "t": 0.0, "live": 0.0, "bounces": 0, "tumble": Vector3(6.0 + randf() * 4.0, 3, 2), "seats": [], "seated": {}, "yaw": 0.0,
		"blob": _sys("fx", "blob", [root, 0.32]), "loop": null, "tick": null, "floor": 0.0, "q0": Quaternion(), "q1": Quaternion(),
		"free": [], "seatIdx": 0,
	}
	teles.append(tele)
	_play("tele_throw", {"pos": root.position})
	var an = _g(p, "anim")
	if an != null:
		_sset(an, "recoil", 1.0)
	return tele

# t.pos aliases root.position in the JS: every write goes through here.
static func _telePos(t: Dictionary, v: Vector3) -> void:
	t.pos = v
	t.root.position = v

# Tiny Tele numbers: weapon_defs tiny_tele (fuse, killR, killUpTo, dmgAfter) over the GDD fallback table.
func _teleDef() -> Dictionary:
	var d = _g(_g(game.weapons, "defs"), "tiny_tele")
	if d == null:
		return G.tele
	if not is_same(_teleDefSrc, d):
		_teleDefSrc = d
		var c: Dictionary = G.tele.duplicate()
		c.fuse = _nz(d.get("fuse"), G.tele.fuse)
		c.killR = _nz(d.get("killR"), G.tele.killR)
		c.killUpTo = _nz(d.get("killUpTo"), G.tele.killUpTo)
		c.late = _nz(d.get("dmgAfter"), G.tele.late)
		c.lure = _nz(d.get("lure"), G.tele.lure)
		_teleDefC = c
	return _teleDefC

# Animated TV snow (gfx card) shown while a tele flies and lands, before the cartoon flips on.
func _snowTex():
	if not _snowTried:
		_snowTried = true
		_snow = _animated("snow")
	return _g(_snow, "texture")

func _disposeTele(t: Dictionary) -> void:
	_drop(t.root)
	_hcall(t.blob, "remove")
	_hcall(t.loop, "stop", [0.05])
	_hcall(t.tick, "stop", [0.05])
	for k in t.seated.keys():
		_unseat(t.seated[k])
	t.seated.clear()

func _updateTeles(dt: float) -> void:
	if teles.is_empty():
		return
	var g = game
	var anyLive := false
	for i in range(teles.size() - 1, -1, -1):
		var t: Dictionary = teles[i]
		t.t += dt
		if t.state == "fly":
			_teleFly(t, dt)
		elif t.state == "land":
			_teleLand(t, dt)
		elif t.state == "live":
			anyLive = true
			_teleLive(t, dt)
		elif t.state == "implode" and _teleImplode(t, dt):
			_disposeTele(t)
			teles.remove_at(i)
			_relure()
	if anyLive:
		_drawCartoon(float(g.time.now))
	if _snow != null:
		var flying := false
		for x in teles:
			if x.state == "fly" or x.state == "land":
				flying = true
		if flying:
			_hcall(_snow, "tick", [float(g.time.realNow)])

func _teleFly(t: Dictionary, dt: float) -> void:
	var g = game
	var TT := _teleDef()
	var col = _col()
	if dt <= 0.0:
		return
	t.vel.y -= float(TT.grav) * dt
	var len: float = t.vel.length() * dt
	if col != null and len > 1e-4:
		var d: Vector3 = t.vel.normalized()
		var hit = col.raycast(Vector3(t.pos.x, t.pos.y + 0.2, t.pos.z), d, len + 0.25)
		if hit != null and absf(hit.normal.y) < 0.5:
			t.vel = reflect(t.vel, hit.normal) * 0.45
			_play("grenade_bounce", {"pos": t.pos, "rate": 0.5, "vol": 0.7})
	_telePos(t, t.pos + t.vel * dt)
	t.spin.rotation.x += t.tumble.x * dt
	t.spin.rotation.z += t.tumble.z * dt
	var f = _floorY(t.pos.x, t.pos.z, t.pos.y + 0.3)
	if f != null and t.pos.y <= f and t.vel.y < 0.0:
		_telePos(t, Vector3(t.pos.x, f, t.pos.z))
		if t.bounces < 1 and absf(t.vel.y) > 3.0:
			t.bounces += 1
			t.vel.y = absf(t.vel.y) * 0.32
			t.vel.x *= 0.45
			t.vel.z *= 0.45
			t.tumble *= 0.5
			_play("telly_clonk", {"pos": t.pos, "vol": 0.9})
			_fx("burst", [t.pos, {"shape": "puff", "count": 4, "size": 0.12, "life": 0.4}])
		else:
			t.state = "land"
			t.t = 0.0
			t.vel = Vector3.ZERO
			t.floor = f
			var p = g.player
			t.yaw = atan2(p.pos.x - t.pos.x, p.pos.z - t.pos.z) + PI if p != null else 0.0   # screen (-z) toward the thrower
			t.q0 = t.spin.quaternion
			t.q1 = qAxis(UP, t.yaw)
			_play("telly_clonk", {"pos": t.pos, "vol": 1, "rate": 0.85})
			_fx("burst", [t.pos, {"shape": "puff", "count": 6, "size": 0.15, "life": 0.5}])
	if t.t > 3.0 and t.state == "fly":
		# lost in the void: land where it is
		t.state = "land"
		t.t = 0.0
		t.floor = t.pos.y
		t.q0 = t.spin.quaternion
		t.q1 = Quaternion()

# Rights itself (squash on landing), telescopes the antenna, flips on with a burst of snow.
func _teleLand(t: Dictionary, dt: float) -> void:
	var g = game
	var k := clamp01(t.t / 0.28)
	t.spin.quaternion = (t.q0 as Quaternion).slerp(t.q1, E.outBack(k, 1.2)).normalized()
	var sq := 1.0 - sin(clamp01(t.t / 0.4) * PI) * 0.22 if t.t < 0.4 else 1.0
	t.spin.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	var ka := seg(t.t, 0.28, 0.62)
	if t.parts.ant2 is Node3D:
		t.parts.ant2.position.y = 0.08 * E.outBack(ka, 2.2)
	if t.parts.ant3 is Node3D:
		t.parts.ant3.position.y = 0.078 * E.outBack(seg(t.t, 0.36, 0.7), 2.2)
	if t.t >= 0.7:
		t.state = "live"
		t.t = 0.0
		t.live = 0.0
		_setScreenMap(t.screenMat, _screenTex)
		var TT := _teleDef()
		_sys("zombies", "setLure", [t.pos, float(_nz(t.get("lure"), _nz(TT.lure, 15)))])
		_lureTele = t
		t.loop = null
		if g.audio != null and g.audio.has_method("loop"):
			t.loop = g.audio.loop("tele_cartoon", {"pos": t.pos})
		t.tick = _play("tele_tick", {"pos": t.pos, "dur": TT.fuse})
		_play("crt_ping", {"pos": t.pos})
		_emit("wonder:tele", {"state": "land", "pos": t.pos})

func _teleLive(t: Dictionary, dt: float) -> void:
	var g = game
	var TT := _teleDef()
	t.live += dt
	var beat := float(g.time.now) * 2.5 * TAU
	var hop := maxf(0.0, sin(beat)) * 0.05
	var fuse := float(TT.fuse)
	var late := seg(t.live, fuse - 1.5, fuse)
	var shake := late * 0.03
	t.spin.position = Vector3((randf() - 0.5) * shake, hop * (1.0 - late) + randf() * shake, (randf() - 0.5) * shake)
	var sq := 1.0 + sin(beat) * 0.05
	t.spin.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	if t.parts.ant is Node3D:
		t.parts.ant.rotation.z = sin(beat * 0.5) * 0.25
	var U = _g(t.screenMat, "uniforms")
	if U is Dictionary and U.get("uBright") != null:
		U.uBright.value = 1.1 + (0.8 if (late > 0.0 and sin(t.live * 40.0) > 0.4) else 0.0)
	_seatZombies(t, dt)
	if t.live >= fuse:
		t.state = "implode"
		t.t = 0.0
		_teleBoom(t)

# Zombies that reach the tele sit cross-legged in a semicircle (r 2.2 m) facing it, mesmerized. Seats must be
# walkable and in sight of the tele and of the zombie; otherwise it stands and sways where it is.
func _seatZombies(t: Dictionary, _dt: float) -> void:
	var TT := _teleDef()
	for z in _zombies():
		if not _alive(z) or _isBoss(z) or t.seated.has(_zk(z)):
			continue
		# only zombies already inside (not tearing boards / vaulting / emerging from a screen) and in sight of the TV
		var zs := _zstate(z)
		if zs != "" and zs != "chase" and zs != "attack":
			continue
		var d := Vector2(z.pos.x - t.pos.x, z.pos.z - t.pos.z).length()
		if d > float(TT.seatR) + 1.4 or absf(z.pos.y - t.pos.y) > 1.2:
			continue
		if _seatOf(z) != null:
			continue
		if not _los(Vector3(z.pos.x, z.pos.y + 0.8, z.pos.z), Vector3(t.pos.x, t.pos.y + 0.4, t.pos.z)):
			continue
		var seat = null if STANDERS.has(_g(z, "type")) else _findSeat(t, z)
		t.seated[_zk(z)] = z
		var s := _stat(z)
		var walk: float = Vector2(seat.x - z.pos.x, seat.z - z.pos.z).length() if seat != null else 0.0
		s.seat = {"tele": t, "pos": seat if seat != null else z.pos, "from": z.pos, "t": 0.0, "stand": seat == null,
			"dur": minf(1.6, maxf(0.3, walk / 1.7)) if seat != null else 0.0, "yaw0": float(_or(_g(z, "yaw"), 0.0)), "plopped": false}
		s.t = 0.0
		_applyPose(z)

func _findSeat(t: Dictionary, z):
	var TT := _teleDef()
	var nav = game.nav
	var face := Vector3(-sin(t.yaw), 0, -cos(t.yaw))   # the screen side
	var reach := func(seat: Vector3) -> bool:
		return _los(Vector3(z.pos.x, z.pos.y + 0.6, z.pos.z), Vector3(seat.x, seat.y + 0.6, seat.z))
	for i in t.free.size():
		if reach.call(t.free[i]):
			var s0 = t.free[i]
			t.free.remove_at(i)
			return s0
	while t.seatIdx < 24:
		var idx: int = t.seatIdx
		t.seatIdx += 1
		var row := 0 if idx < 9 else 1
		var n := idx - 9 if row == 1 else idx
		var step := 16.0 if row == 1 else 20.0
		var a: float = ((1.0 if n % 2 == 1 else -1.0) * ceil(n / 2.0) * step + (8.0 if row == 1 else 0.0)) * DEG
		var r := float(TT.seatR) + row * 0.85
		var dir := face.rotated(UP, a)
		var seat := Vector3(t.pos.x + dir.x * r, t.pos.y, t.pos.z + dir.z * r)
		if nav != null and nav.has_method("walkable") and not nav.walkable(seat.x, seat.z):
			continue
		var f = _floorY(seat.x, seat.z, t.pos.y + 0.5)
		if f == null or absf(f - t.pos.y) > 0.5:
			continue
		seat.y = f
		if not _los(Vector3(t.pos.x, t.pos.y + 0.5, t.pos.z), Vector3(seat.x, seat.y + 0.5, seat.z)):
			continue
		if reach.call(seat):
			return seat
		t.free.append(seat)
	return null

func _seatOf(z):
	var s = _status.get(_zk(z))
	return s.seat if s != null else null

func _unseat(z) -> void:
	var s = _status.get(_zk(z))
	if s == null or s.seat == null:
		return
	var st = s.seat
	if not st.stand and st.tele != null and st.tele.state == "live":
		st.tele.free.append(st.pos)
	s.seat = null
	_releaseHold(z)
	_applyPose(z)
	_maybeDrop(z)

func _teleBoom(t: Dictionary) -> void:
	var TT := _teleDef()
	var center: Vector3 = t.pos + Vector3(0, 0.25, 0)
	_hcall(t.loop, "stop", [0.05])
	t.loop = null
	_play("tele_implode", {"pos": center})
	_fx("flashLight", [center, "#BFE8FF", 10, 0.3])
	_fx("burst", [center, {"shape": "static", "count": 24, "speed": 4}])
	_fx("burst", [center, {"shape": "spark", "count": 16, "colors": ["#FFFFFF", "#7FE7FF", "#FF5FA2"], "speed": 7}])
	_floorRing(t.pos, float(TT.killR), "#7FE7FF", 0.42, false, 0.8)
	_floorRing(t.pos, float(TT.killR) * 0.55, "#FF5FA2", 0.3, false, 0.7)
	_sys("cam", "shake", [0.2, 0.3])
	var late := _round() > int(TT.killUpTo)
	for z in _zombies().duplicate():
		if not _alive(z) or _isBoss(z):
			continue
		if z.pos.distance_to(t.pos) > float(TT.killR):
			continue
		var dmg := float(TT.late)
		var P = _doom(z, func():
			if late:
				return _damage(z, dmg, "tiny_tele", "tiny_tele")
			return _kill(z, "tiny_tele", "tiny_tele"))
		if P != null:
			_suckIn(z, center, P)
	for k in t.seated.keys():
		_unseat(t.seated[k])
	t.seated.clear()
	_emit("wonder:tele", {"state": "implode", "pos": t.pos})

# The TV crushes inward (anticipation swell), the screen collapses to a line and a dot.
func _teleImplode(t: Dictionary, dt: float) -> bool:
	var k := clamp01(t.t / 0.35)
	var swell := 1.0 + E.outQuad(k / 0.3) * 0.18 if k < 0.3 else 1.18 * (1.0 - E.inBack((k - 0.3) / 0.7, 2.0))
	t.spin.scale = Vector3(maxf(0.001, swell), maxf(0.001, swell * (1.0 if k < 0.3 else 1.0 - (k - 0.3) * 0.6)), maxf(0.001, swell))
	t.spin.rotation.y += dt * 12.0 * k
	return t.t >= 0.36

func _suckIn(z, center: Vector3, pre = null) -> void:
	var P = pre if pre is Corpse else _corpse(z)
	if P == null:
		return
	var from: Vector3 = P.pivot.position
	var mid: float = P.h * 0.5
	P.tilt.position.y = mid
	P.body.position.y = -mid
	var st := {"t": 0.0}
	var dur := 0.32 + randf() * 0.08
	var to := Vector3(center.x, center.y - mid * 0.3, center.z)
	_actors.append({
		"update": func(dt):
			st.t += dt
			var k := clamp01(st.t / dur)
			if st.t < 0.05:
				P.setMat(res.fx.static)
			else:
				P.setMat(null)
			P.pivot.position = from.lerp(to, E.inBack(k, 1.4))
			P.tilt.rotation.y += dt * 18.0
			var s := maxf(0.001, 1.0 - E.inQuad(k))
			P.tilt.scale = Vector3(s, maxf(0.001, s * (1.0 + k * 0.8)), s)
			P.sync()
			return k < 1.0,
		"dispose": func(): P.dispose(),
	})

# After an implosion the lure moves to the next live tele, or clears.
func _relure() -> void:
	var nxt = null
	for x in teles:
		if x.state == "live":
			nxt = x
			break
	_lureTele = nxt
	_sys("zombies", "setLure", [nxt.pos if nxt != null else null, float(_nz(nxt.get("lure"), _nz(_teleDef().lure, 15))) if nxt != null else INF])

func _updateTeleCount() -> void:
	var w = game.weapons
	if w == null or not _isNum(_g(w, "teles")):
		_lastTeles = null
		return
	if _teleCheck != null:
		if int(w.teles) == _teleCheck.value and int(game.time.frame) > _teleCheck.frame:
			w.teles = maxi(0, int(w.teles) - 1)
			_teleCheck = null
		elif int(w.teles) != _teleCheck.value:
			_teleCheck = null
	_lastTeles = int(w.teles)

# ------------------------------------------------------------------------------------------ status effects
func _stat(z) -> Dictionary:
	var k = _zk(z)
	var s = _status.get(k)
	if s == null:
		s = {"z": z, "slows": null, "baseSpeed": null, "panic": 0.0, "burn": 0.0, "burnGen": 0, "burnLeft": 0, "burnCap": 0.0, "burnWeapon": null,
			"laugh": 0.0, "frozen": 0.0, "slowT": 0.0, "seat": null, "holdT": 0.0, "pose": null, "prevOverride": null, "hasPrevOverride": false,
			"overrideFn": null, "prevUpdate": null, "hasPrevUpdate": false, "iced": null, "flame": null, "dmgMul": 1.0, "t": 0.0, "seed": randf() * TAU, "fire": 0.0}
		_status[k] = s
	return s

func _slow(z, key: String, mul: float) -> void:
	var s := _stat(z)
	if s.slows == null:
		s.slows = {}
	if s.baseSpeed == null and _isNum(_g(z, "speed")):
		s.baseSpeed = float(z.speed)
	s.slows[key] = mul
	_applySpeed(z, s)

func _unslow(z, key: String) -> void:
	var s = _status.get(_zk(z))
	if s == null or s.slows == null or not s.slows.has(key):
		return
	s.slows.erase(key)
	_applySpeed(z, s)
	_maybeDrop(z)

func _applySpeed(z, s: Dictionary) -> void:
	if s.baseSpeed == null or not _au:
		return
	var m := 1.0
	for k in s.slows:
		m = minf(m, s.slows[k])
	_sset(z, "speed", s.baseSpeed * m)
	if s.slows.is_empty():
		_sset(z, "speed", s.baseSpeed)
		s.baseSpeed = null

func _releaseHold(z) -> void:
	if not _au:
		return
	if _isNum(_g(z, "stun")):
		_sset(z, "stun", minf(float(z.stun), 0.05))

func _maybeDrop(z) -> void:
	var s = _status.get(_zk(z))
	if s == null:
		return
	var busy_: bool = (s.slows != null and not s.slows.is_empty()) or s.panic > 0.0 or s.burn > 0.0 or s.laugh > 0.0 or s.frozen > 0.0 or s.seat != null or s.slowT > 0.0
	if not busy_:
		_clearStatus(z)

func _clearStatus(z) -> void:
	var k = _zk(z)
	var s = _status.get(k)
	if s == null:
		return
	if s.baseSpeed != null:
		_sset(z, "speed", s.baseSpeed)
	s.slows = null
	s.baseSpeed = null
	_unfreeze(z, s)
	s.pose = null
	_setOverride(z, s, null)
	if s.flame != null:
		_drop(s.flame)
		s.flame = null
	_status.erase(k)

func _setOverride(z, s: Dictionary, fn) -> void:
	var an = _g(z, "animator")
	if an == null or not _has(an, "override"):
		return
	var cur = _g(an, "override")
	if fn != null:
		if s.overrideFn == null or cur != s.overrideFn:
			if not s.hasPrevOverride:
				s.prevOverride = cur
				s.hasPrevOverride = true
			if s.overrideFn == null:
				s.overrideFn = func(rig, dt): _pose(z, s, rig, dt)
			_sset(an, "override", s.overrideFn)
	elif s.hasPrevOverride or (s.overrideFn != null and cur == s.overrideFn):
		if s.overrideFn != null and cur == s.overrideFn:
			var prev = s.prevOverride
			if prev == null and _g(an, "override") is Callable:
				prev = Callable()
			_sset(an, "override", prev)
		s.hasPrevOverride = false
		s.prevOverride = null

func _applyPose(z) -> void:
	var s = _status.get(_zk(z))
	if s == null:
		return
	var pose = null
	if s.frozen > 0.0:
		pose = null
	elif s.laugh > 0.0:
		pose = "laugh"
	elif s.panic > 0.0:
		pose = "panic"
	elif s.seat != null:
		pose = "sway" if s.seat.stand else "sit"
	s.pose = pose
	_setOverride(z, s, true if pose != null else null)

# Joint poses (rig conventions: shoulder/hip.x > 0 swings forward, knee.x < 0 bends back, spine.x < 0 leans forward).
func _pose(z, s: Dictionary, rig, dt: float) -> void:
	var J = _g(rig, "joints")
	if J == null or _g(J, "hips") == null:
		return
	var D = _g(rig, "dims", {"hipsY": 0.8})
	var hipsY := float(_g(D, "hipsY", 0.8))
	s.t += dt
	var t: float = s.t + s.seed
	var setj := func(j: String, x: float, y: float, zr: float):
		var o = _g(J, j)
		if o is Node3D:
			o.rotation = Vector3(x, y, zr)
	var hips: Node3D = J.hips
	if s.pose == "laugh":
		var shake := sin(t * 22.0) * 0.12
		hips.position.y = hipsY * 0.3
		setj.call("hips", 1.32 + shake * 0.3, 0.0, sin(t * 5.0) * 0.1)
		setj.call("spine", -0.15 + shake, 0.0, 0.0)
		setj.call("chest", -0.2 + shake * 0.6, 0.0, 0.0)
		setj.call("neck", -0.25, 0.0, 0.0)
		setj.call("head", -0.35 + sin(t * 22.0 + 1.0) * 0.15, sin(t * 3.0) * 0.3, 0.0)
		for sk in [["L", 1.0], ["R", -1.0]]:
			var sd: String = sk[0]
			var k: float = sk[1]
			var ph := 0.0 if k > 0.0 else PI
			setj.call("shoulder" + sd, 0.9 + shake, 0.0, k * 0.35)
			setj.call("elbow" + sd, 1.9, 0.0, 0.0)
			setj.call("hip" + sd, 0.9 + sin(t * 13.0 + ph) * 0.55, 0.0, k * 0.25)
			setj.call("knee" + sd, -1.3 - maxf(0.0, sin(t * 13.0 + ph)) * 0.6, 0.0, 0.0)
	elif s.pose == "panic":
		var w := t * 16.0
		hips.position.y += absf(sin(w)) * 0.07
		setj.call("spine", 0.12, sin(w * 0.5) * 0.2, 0.0)
		setj.call("head", -0.35, sin(t * 9.0) * 0.5, 0.0)
		for sk in [["L", 1.0], ["R", -1.0]]:
			var sd: String = sk[0]
			var k: float = sk[1]
			var ph := 0.0 if k > 0.0 else PI
			setj.call("shoulder" + sd, 2.7 + sin(w * 1.3 + ph) * 0.45, 0.0, k * (0.35 + sin(w + ph) * 0.2))
			setj.call("elbow" + sd, 0.5 + sin(w * 1.7 + ph) * 0.4, 0.0, 0.0)
			setj.call("hip" + sd, sin(w + ph) * 0.95, 0.0, 0.0)
			setj.call("knee" + sd, -0.2 - maxf(0.0, cos(w + ph)) * 1.3, 0.0, 0.0)
	elif s.pose == "sit":
		var st = s.seat if s.seat != null else {"t": 1.0, "dur": 0.0}
		var walking: bool = st.dur > 0.0 and st.t < st.dur
		if walking:
			# mesmerized shuffle toward the seat: arms up, stiff little steps
			var w2: float = st.t * 10.0
			hips.position.y += absf(sin(w2)) * 0.03
			setj.call("spine", -0.12, sin(w2) * 0.08, 0.0)
			setj.call("head", 0.15, 0.0, sin(w2 * 0.5) * 0.1)
			for sk in [["L", 1.0], ["R", -1.0]]:
				var sd: String = sk[0]
				var k: float = sk[1]
				var ph := 0.0 if k > 0.0 else PI
				setj.call("shoulder" + sd, 1.35 + sin(w2 + ph) * 0.1, 0.0, k * 0.08)
				setj.call("elbow" + sd, 0.25, 0.0, 0.0)
				setj.call("hip" + sd, sin(w2 + ph) * 0.45, 0.0, 0.0)
				setj.call("knee" + sd, -maxf(0.0, cos(w2 + ph)) * 0.7, 0.0, 0.0)
			return
		# sit down: blend from the standing pose (outBack plop), then sway to the cartoon's beat
		var kk := E.outBack(seg(st.t, st.dur, st.dur + 0.32), 1.3)
		var blend := func(j: String, x: float, y: float, zr: float):
			var o = _g(J, j)
			if not (o is Node3D):
				return
			o.rotation = Vector3(lerpf(o.rotation.x, x, kk), lerpf(o.rotation.y, y, kk), lerpf(o.rotation.z, zr, kk))
		hips.position.y = lerpf(hips.position.y, hipsY * 0.27, clamp01(kk))
		var sway := sin(t * 2.6) * 0.09 * clamp01(kk)
		blend.call("hips", -0.08, 0.0, 0.0)
		blend.call("spine", 0.05, 0.0, sway)
		blend.call("chest", 0.0, 0.0, sway * 0.5)
		blend.call("head", sin(t * 5.2) * 0.1 - 0.05, sway * 1.5, sway)
		for sk in [["L", 1.0], ["R", -1.0]]:
			var sd: String = sk[0]
			var k2: float = sk[1]
			blend.call("hip" + sd, 1.45, 0.0, k2 * 0.95)
			blend.call("knee" + sd, -2.3, 0.0, 0.0)
			blend.call("foot" + sd, 0.3, 0.0, -k2 * 0.6)
			blend.call("shoulder" + sd, 0.55, 0.0, k2 * 0.15)
			blend.call("elbow" + sd, 0.9, 0.0, 0.0)
	elif s.pose == "sway":
		var sway2 := sin(t * 2.2) * 0.14
		setj.call("spine", 0.0, 0.0, sway2)
		setj.call("head", sin(t * 4.4) * 0.1, sway2, sway2 * 0.6)

func _unfreeze(z, s: Dictionary) -> void:
	if s.iced != null:
		for om in s.iced:
			if is_instance_valid(om[0]) and om[0].material_override == res.mIce:
				om[0].material_override = om[1]
		s.iced = null
	var an = _g(z, "animator")
	if s.hasPrevUpdate and an != null:
		# JS: delete the own `update` (null) or put the previous one back; rig.gd's assignable update is updateFn
		_sset(an, "updateFn", s.prevUpdate if s.prevUpdate != null else Callable())
		s.hasPrevUpdate = false
		s.prevUpdate = null

func _updateStatus(dt: float) -> void:
	if _status.is_empty():
		return
	var g = game
	var alive := _zombies()
	# JS Map iteration: entries deleted meanwhile are skipped, entries added meanwhile (a spreading burn) are visited
	var visited := {}
	while true:
		var key = null
		for k in _status:
			if not visited.has(k):
				key = k
				break
		if key == null:
			break
		visited[key] = true
		var s: Dictionary = _status[key]
		var z = s.z
		if z == null or not (_hp(z) > 0.0) or _zstate(z) == "dying" or _zstate(z) == "dead" or not _inList(alive, z):
			_clearStatus(z)
			continue
		if dt <= 0.0:
			continue
		# timers
		if s.slowT > 0.0:
			s.slowT -= dt
			if s.slowT <= 0.0:
				_unslow(z, "cold")
		if s.frozen > 0.0:
			s.frozen -= dt
			_hold(z, 0.2)
			if s.frozen <= 0.0:
				_unfreeze(z, s)
				_releaseHold(z)
				_fx("burst", [_chest(z), {"shape": "star", "count": 5, "colors": ["#DDF6FF", "#FFFFFF"], "speed": 2}])
				_applyPose(z)
		if s.laugh > 0.0:
			s.laugh -= dt
			_hold(z, 0.2)
			if s.laugh <= 0.0:
				_releaseHold(z)
				_applyPose(z)
		if s.burn > 0.0:
			_updateBurn(z, s, dt)
		if s.panic > 0.0:
			_updatePanic(z, s, dt)
		if s.seat != null:
			_updateSeat(z, s, dt)
		if s.pose != null:
			_setOverride(z, s, true)
		if _status.has(key):
			_maybeDrop(z)

# Walks to its seat (a shuffle cycle in the pose override), turns to the screen, plops down cross-legged.
func _updateSeat(z, s: Dictionary, dt: float) -> void:
	var st = s.seat
	var t = st.tele
	if t == null or t.state != "live":
		_unseat(z)
		return
	_hold(z, 0.2)
	st.t += dt
	var k: float = clamp01(st.t / st.dur) if st.dur > 0.0 else 1.0
	if not _au:
		if not st.plopped and not st.stand and st.t >= st.dur + 0.18:
			st.plopped = true
			_akick(z, 0.7)
		return   # MP client: position / yaw come from the snapshot
	z.pos = (st.from as Vector3).lerp(st.pos, E.inOutQuad(k))
	var face := atan2(-(t.pos.x - z.pos.x), -(t.pos.z - z.pos.z))
	var want := face
	if k < 1.0 and st.dur > 0.0:
		var walkYaw := atan2(-(st.pos.x - st.from.x), -(st.pos.z - st.from.z))
		var turn := seg(k, 0.6, 1.0)
		want = walkYaw + atan2(sin(face - walkYaw), cos(face - walkYaw)) * E.inOutQuad(turn)
	z.yaw = want
	var grp = _g(z, "group")
	if grp is Node3D:
		grp.position = z.pos
		grp.rotation.y = want
	var an = _g(z, "anim")
	if an != null:
		_sset(an, "speed", 0)
		_sset(an, "down", false)
	if not st.plopped and not st.stand and st.t >= st.dur + 0.18:
		st.plopped = true
		_akick(z, 0.7)
		_fx("burst", [Vector3(z.pos.x, z.pos.y + 0.05, z.pos.z), {"shape": "puff", "count": 3, "size": 0.12, "life": 0.45, "speed": 0.8}])

# ------------------------------------------------------------------------------------------ signal colors
# zombie:hit -> x1.5 damage while laughing / frozen, then the signal-color roll of upgraded weapons (GDD §10.4):
# primary hits only (weapons.hit.primary; Double Vision ghosts don't roll), half chance for splash targets,
# a cooldown per weapon + color. Wonder weapons roll too (their non-lethal late-round hits).
func _onHit(p) -> void:
	if not (p is Dictionary) or p.get("z") == null or not _au or p.get("predicted") == true:
		return
	var z = p.z
	var cause = p.get("cause")
	var internal: bool = cause == "signal_bonus" or cause == "burn"
	if internal:
		return
	var SIG: Dictionary = Config.T.uplink.signals
	var s = _status.get(_zk(z))
	var dmg := _num(p.get("dmg"), 0.0)
	var pby = p.get("by")
	var remote: bool = mp != null and pby != null and int(pby) != mp.localId()
	if s != null and (s.laugh > 0.0 or s.frozen > 0.0) and dmg > 0.0 and _hp(z) > 0.0:
		var bonus := dmg * (float(SIG.cold_open.mul if s.frozen > 0.0 else SIG.laugh_track.mul) - 1.0)
		if _hp(z) - bonus > 0.0:
			z.hp = _hp(z) - bonus
		else:
			_damage(z, bonus + 1.0, p.get("weaponId"), "signal_bonus", {"by": int(pby)} if pby != null and mp != null else {})
	if not _t(p.get("weaponId")) or _t(p.get("ghost")) or cause == "ghost":
		return
	if not (_hp(z) > 0.0) or _zstate(z) == "dying" or _t(_g(z, "dead")):
		return
	var wh = _g(game.weapons, "hit")
	var dc = _dmgCtx if _applying > 0 else null
	if wh != null and wh.get("primary") == false:
		return
	if remote:
		# MP: another player's hit (zombies.net_dmgBatch / a host-resolved action): its own weapon, never our slots
		if p.get("primary") == false:
			return
		wh = null
		dc = dc if (dc != null and dc.get("by") == int(pby)) else null
	var slot = _slotOf(p.weaponId) if not remote else null
	var upgraded = _nz(wh.get("upgraded") if (wh != null and wh.get("weaponId") == p.weaponId) else null,
		_nz(dc.upgraded if dc != null else null, _nz(p.get("upgraded"), _g(slot, "upgraded"))))
	if not _t(upgraded):
		return
	var sig := str(_or(_g(wh, "signal"), _or(p.get("signal"), _or(_g(slot, "signal"), ""))))
	if sig.begins_with("signal_"):
		sig = sig.substr(7)
	if not SIGNALS.has(sig):
		return
	var S: Dictionary = SIG[sig]
	var key := "%s|%s" % [p.weaponId, sig] if mp == null else "%s|%s|%s" % [str(pby), p.weaponId, sig]
	var now := float(game.time.now)
	if float(_sigCd.get(key, -1e9)) > now:
		return
	var splash: bool = _t(p.get("splash")) or cause == "splash" or (wh != null and wh.get("cause") == "splash") or (dc != null and _t(dc.splash))
	var chance := float(S.p) * (0.5 if splash else 1.0)
	if float(game.rand()) >= chance:
		return
	_sigCd[key] = now + float(S.cd)
	var prevBy = _byCtx
	if pby != null and mp != null:
		_byCtx = int(pby)
	applySignal(z, sig, {"weaponId": p.weaponId, "splash": splash})
	_byCtx = prevBy

func _onKill(p) -> void:
	var z = p.get("z") if p is Dictionary else null
	if z == null:
		return
	var s = _status.get(_zk(z))
	if s != null and s.frozen > 0.0:
		_shatter(z, s)

# HOT MIC: bursts into cartoon flame and panics (runs away, can't attack), 35 % max HP per second for 3 s.
func _ignite(z, gen: int, weaponId) -> void:
	var S: Dictionary = Config.T.uplink.signals.hot_mic
	var P: Dictionary = Config.PAL
	var s := _stat(z)
	var special := SPECIALS.has(_g(z, "type"))
	var boss := _isBoss(z)
	if s.burn > 0.0 and s.burnGen <= gen:
		s.burn = maxf(s.burn, float(S.dur))
		return
	s.burn = float(S.dur)
	s.burnGen = gen
	s.burnLeft = 2 if gen == 1 else 0
	if mp != null:
		s.burnBy = _byCtx if _byCtx != null else mp.localId()
		mp.signalOut("hot_mic", [z], gen)
	s.burnCap = 1500.0 if (special or boss) else INF
	s.burnWeapon = weaponId
	if not special and not boss:
		s.panic = float(S.dur)
		_applyPose(z)
	if s.flame == null:
		var R := res
		var fl := DAU.node3d("wonder_flame")
		fl.add_child(_mi(R.flameOuter, R.mFlame))
		var inner := _mi(R.flameInner, R.mFlameIn)
		inner.position.y = 0.02
		fl.add_child(inner)
		for c in fl.get_children():
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.scene.add_child(fl)
		s.flame = fl
	var a := _headPos(z)
	_play("wonder_fwoomp", {"pos": a})
	_later(0.12, func(): _play("wonder_yeowch", {"pos": a, "rate": 1.0 + randf() * 0.3}))
	_fx("burst", [a, {"shape": "spark", "count": 14, "colors": [P.hotMic, "#FFE14D", "#FFB347"], "speed": 5}])
	_fx("burst", [a, {"shape": "puff", "count": 5, "colors": ["#FFB347", "#FF7A2E"], "size": 0.18}])

func _updateBurn(z, s: Dictionary, dt: float) -> void:
	var g = game
	var S: Dictionary = Config.T.uplink.signals.hot_mic
	var P: Dictionary = Config.PAL
	s.burn -= dt
	var per := minf(float(_or(_g(z, "maxHp"), _or(_g(z, "hp"), 100))) * float(S.burn), s.burnCap)
	var dmg := per * dt
	if not _au:
		pass   # MP client: the host burns (visuals below only)
	elif _hp(z) - dmg > 0.0:
		z.hp = _hp(z) - dmg
	else:
		_applying += 1
		var bi := {"weaponId": _or(s.burnWeapon, "signal_hot_mic"), "cause": "burn"}
		if mp != null and s.get("burnBy") != null:
			bi.by = s.burnBy
		_sys("zombies", "damage", [z, dmg + 1.0, bi])
		_applying -= 1
	if s.flame != null and is_instance_valid(s.flame):
		var a := _headPos(z)
		s.flame.position = Vector3(a.x, a.y + 0.05, a.z)
		var f := 0.9 + sin(float(g.time.now) * 31.0 + s.seed) * 0.12 + randf() * 0.08
		var fade := minf(1.0, s.burn / 0.3)
		s.flame.scale = Vector3(f * 1.3 * fade, (2.0 - f) * 1.5 * fade, f * 1.3 * fade)
		s.flame.rotation.y += dt * 3.0
	s.fire -= dt
	if s.fire <= 0.0:
		s.fire = 0.07
		var c := _chest(z)
		c.x += (randf() - 0.5) * 0.3
		_fx("burst", [c, {"shape": "spark", "count": 2, "colors": [P.hotMic, "#FFE14D"], "speed": 1.6, "gravity": -3, "life": 0.5, "dir": UP, "cone": 0.4}])
		if randf() < 0.3:
			_fx("burst", [Vector3(c.x, c.y + 0.6, c.z), {"shape": "puff", "count": 1, "colors": ["#5A4A5A", "#7A6A70"], "size": 0.12, "gravity": -1.5, "life": 0.8}])
	# spread: touches up to 2 zombies (one generation)
	if s.burnLeft > 0 and _au:
		for o in _zombies():
			if is_same(o, z) or not _alive(o) or _isBoss(o):
				continue
			var os = _status.get(_zk(o))
			if os != null and os.burn > 0.0:
				continue
			if o.pos.distance_to(z.pos) > _zr(z) + _zr(o) + 0.25:
				continue
			_ignite(o, 2, s.burnWeapon)
			s.burnLeft -= 1
			if s.burnLeft <= 0:
				break
	if s.burn <= 0.0:
		s.burn = 0.0
		if s.flame != null:
			_drop(s.flame)
			s.flame = null

func _updatePanic(z, s: Dictionary, dt: float) -> void:
	var g = game
	var col = _col()
	s.panic -= dt
	_hold(z, 0.2)
	if s.panic <= 0.0:
		s.panic = 0.0
		_releaseHold(z)
		_applyPose(z)
		return
	if not _au:
		return   # MP client: the snapshot moves it (pose only here)
	# run away from the player along the reversed flow field (fallback: straight away), zig-zagging
	var d := -_navDir(z.pos.x, z.pos.z)
	if d.length_squared() < 1e-3:
		d = _away(z.pos)
	d = d.rotated(UP, sin(float(g.time.now) * 3.0 + s.seed) * 0.6).normalized()
	var speed := 3.4
	if col != null:
		var a := d * (speed * dt)
		a.y = -dt
		_moveCircle(z, a, _zr(z, 0.35), _zh(z), 0.45)
	var want := atan2(-d.x, -d.z)
	z.yaw = want
	var grp = _g(z, "group")
	if grp is Node3D:
		grp.position = z.pos
		grp.rotation.y = want

# LAUGH TRACK: the target and its 3 nearest zombies within 4 m fall down laughing for 4 s (x1.5 damage).
func _laughTrack(z, _weaponId) -> void:
	var S: Dictionary = Config.T.uplink.signals.laugh_track
	var P: Dictionary = Config.PAL
	var group: Array = [z]
	var near: Array = []
	for o in _zombies():
		if not is_same(o, z) and _alive(o) and not _isBoss(o) and o.pos.distance_to(z.pos) <= 4.0:
			near.append(o)
	near.sort_custom(func(a, b): return a.pos.distance_to(z.pos) < b.pos.distance_to(z.pos))
	group.append_array(near.slice(0, 3))
	if mp != null:
		mp.signalOut("laugh_track", group, 0)
	_laughGroup(group)

# The laugh itself on a resolved group (MP clients replay it from wonder.net_signal).
func _laughGroup(group: Array) -> void:
	var S: Dictionary = Config.T.uplink.signals.laugh_track
	var P: Dictionary = Config.PAL
	_play("crowd_laugh", {"dur": 2.5, "vol": 0.9})
	for o in group:
		if _isBoss(o):
			continue
		if SPECIALS.has(_g(o, "type")):
			_hold(o, 1.0)
			_akick(o, 1.2)
			continue
		var s := _stat(o)
		s.laugh = float(S.dur)
		s.t = 0.0
		_applyPose(o)
		var a := _chest(o)
		_fx("burst", [a, {"shape": "star", "count": 4, "colors": [P.laughTrack, "#FFF3B0"], "speed": 2.4}])
		_fx("text3d", [Vector3(a.x, a.y + 0.9, a.z), "HA!", P.laughTrack])

# COLD OPEN: the target and everyone within 3 m freeze solid in ice blue for 3 s (+50 % damage).
func _coldOpen(z, _weaponId) -> void:
	var S: Dictionary = Config.T.uplink.signals.cold_open
	var P: Dictionary = Config.PAL
	var list: Array = []
	for o in _zombies():
		if _alive(o) and not _isBoss(o) and (is_same(o, z) or o.pos.distance_to(z.pos) <= float(S.r)):
			list.append(o)
	if mp != null:
		mp.signalOut("cold_open", [z] + list, 0)
	_coldGroup(z, list)

# The freeze itself on a resolved list (MP clients replay it from wonder.net_signal).
func _coldGroup(z, list: Array) -> void:
	var S: Dictionary = Config.T.uplink.signals.cold_open
	var P: Dictionary = Config.PAL
	_play("wonder_freeze", {"pos": z.pos})
	_floorRing(z.pos, float(S.r), P.coldOpen, 0.4, true, 0.8)
	for o in list:
		if SPECIALS.has(_g(o, "type")):
			var s := _stat(o)
			s.slowT = float(S.dur)
			_slow(o, "cold", 0.5)
			continue
		_freeze(o, float(S.dur))

func _freeze(z, dur: float) -> void:
	var R := res
	var P: Dictionary = Config.PAL
	var s := _stat(z)
	s.frozen = dur
	s.laugh = 0.0
	s.panic = 0.0
	_hold(z, dur)
	if s.iced == null:
		s.iced = []
		var grp = _g(z, "group")
		if grp is Node:
			for o in _meshes(grp, []):
				if o.material_override != R.mIce:
					s.iced.append([o, o.material_override])
					o.material_override = R.mIce
	# frozen solid: the animator's update becomes a no-op (rig.gd: the assignable `update` is the updateFn Callable)
	var an = _g(z, "animator")
	if not s.hasPrevUpdate and an != null and _has(an, "updateFn"):
		var cur = _g(an, "updateFn")
		s.prevUpdate = cur if (cur is Callable and cur.is_valid()) else null
		s.hasPrevUpdate = true
		_sset(an, "updateFn", func(_dt, _st = null): pass)
	_applyPose(z)
	var a := _chest(z)
	_fx("burst", [a, {"shape": "puff", "count": 6, "colors": ["#E6F8FF", "#BFEFFF"], "size": 0.2, "life": 0.6}])
	_fx("burst", [a, {"shape": "star", "count": 4, "colors": ["#FFFFFF", P.coldOpen], "speed": 2}])

# Frozen zombies that die shatter into ice cubes.
func _shatter(z, s: Dictionary) -> void:
	var P: Dictionary = Config.PAL
	_unfreeze(z, s)
	_hide(z)
	var a := _chest(z)
	var h := _zh(z)
	for i in 22:
		var it: Dictionary = pools.debris.spawn()
		it.pos = Vector3(z.pos.x + (randf() - 0.5) * 0.6, z.pos.y + 0.2 + randf() * h * 0.9, z.pos.z + (randf() - 0.5) * 0.6)
		it.vel = Vector3((randf() - 0.5) * 5.0, 2.0 + randf() * 4.0, (randf() - 0.5) * 5.0)
		it.rot = Vector3(randf() * TAU, randf() * TAU, 0)
		it.spin = Vector3((randf() - 0.5) * 14.0, (randf() - 0.5) * 14.0, 0)
		it.t = 0.0
		it.life = 1.2 + randf() * 0.6
		it.size = 0.07 + randf() * 0.1
		it.floor = z.pos.y
		it.c = lin(["#BFE6FF", "#8FCBF2", "#DDF3FF"][int(floor(randf() * 3))], 0.85)
	_play("wonder_shatter", {"pos": a})
	_fx("burst", [a, {"shape": "star", "count": 8, "colors": ["#FFFFFF", P.coldOpen], "speed": 4}])
	_fx("burst", [a, {"shape": "puff", "count": 6, "colors": ["#E6F8FF"], "size": 0.22}])
	_clearStatus(z)

# ------------------------------------------------------------------------------------------ pools
func _updatePools(dt: float) -> void:
	var PL := pools
	var ZERO_M := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var ring := func(it: Dictionary, d: float) -> bool:
		it.t += d
		var t: float = it.t - it.delay
		if t < 0.0:
			it.m = ZERO_M
			it.c = Color(0, 0, 0, 1)
			return true
		var k := clamp01(t / it.dur)
		if it.kind == "grow":
			var s := lerpf(it.s0, it.s1, E.outCubic(k))
			it.m = compose(it.from, it.q, Vector3(s, s, s))
		else:
			var e := E.outQuad(k) if it.kind == "cone" else k
			var p: Vector3 = (it.from as Vector3).lerp(it.to, e)
			var s2 := lerpf(it.s0, it.s1, e)
			it.m = compose(p, it.q, Vector3(s2, s2, s2))
		var f := (1.0 - k) * (1.0 - k) * minf(1.0, k / 0.18) if it.kind == "cone" else (1.0 - k * k)
		it.c = cmul(it.base, f)
		return k < 1.0
	PL.rings.update(dt, ring)
	PL.bold.update(dt, ring)
	var tip := _micTip
	PL.squig.update(dt, func(it: Dictionary, d: float) -> bool:
		it.t += d
		var k := clamp01(it.t / it.dur)
		var e := E.inQuad(k)
		var p: Vector3 = (it.from as Vector3).lerp(tip, e)
		var a: Vector3 = tip - it.from
		var len := a.length()
		if len == 0.0:
			len = 1.0
		a /= len
		var b := a.cross(UP).normalized()
		p += b * (sin(k * PI) * 0.35 * sin(it.seed))
		p.y += sin(k * PI) * 0.25
		var q := qFromUnit(ZAXIS, a) * qAxis(ZAXIS, it.t * 14.0 + it.seed)
		var s := (k / 0.15 if k < 0.15 else 1.0 - E.inQuad(seg(k, 0.6, 1.0)) * 0.8) * 1.4
		it.m = compose(p, q, Vector3(s, s, s * (0.8 + sin(it.t * 30.0) * 0.2)))
		it.c = cmul(it.base, (1.0 - k) / 0.15 if k > 0.85 else 1.0)
		return k < 1.0)
	PL.debris.update(dt, func(it: Dictionary, d: float) -> bool:
		it.t += d
		it.vel.y -= 14.0 * d
		it.pos += it.vel * d
		if it.pos.y < it.floor + it.size * 0.5:
			it.pos.y = it.floor + it.size * 0.5
			it.vel.y = absf(it.vel.y) * 0.35
			it.vel.x *= 0.6
			it.vel.z *= 0.6
			it.spin *= 0.6
		it.rot.x += it.spin.x * d
		it.rot.y += it.spin.y * d
		var q := Basis.from_euler(it.rot, EULER_ORDER_XYZ).get_rotation_quaternion()
		var s: float = it.size * (maxf(0.001, (it.life - it.t) / 0.3) if it.t > it.life - 0.3 else 1.0)
		it.m = compose(it.pos, q, Vector3(s, s, s))
		return it.t < it.life)
	var splat := func(it: Dictionary, d: float) -> bool:
		it.t += d
		var fadeT := minf(1.0, it.dur * 0.3)
		var out := seg(it.t, it.dur - fadeT, it.dur)
		var a := 1.0 - out * out * (3.0 - 2.0 * out)
		var s: float = it.size * (0.55 + 0.45 * E.outBack(clamp01(it.t / 0.14), 2.2)) * (1.0 - 0.12 * out)
		it.m = compose(it.pos, it.q, Vector3(s, s, 1))
		it.c = Color(a, a, a, 1)                    # instance colour r = opacity (alphaFromInstance)
		return it.t < it.dur
	PL.splat.update(dt, splat)
	PL.splatUp.update(dt, splat)

# ------------------------------------------------------------------------------------------ debug
class WonderDebug extends RefCounted:
	var w

	func _init(wonder) -> void:
		w = wonder

	func _find(z):
		if z is int or z is float:
			for o in w._zombies():
				if w._g(o, "id") == int(z):
					return o
			return null
		return z

	func trigger(down = null) -> void:
		w._dbgTrigger = null if down == null else w._t(down)
		if w._dbgTrigger == null:
			w._dbgPrev = false

	func gag(z, name: String = "cartoon") -> bool:
		var zz = _find(z)
		if zz == null or not w._alive(zz):
			return false
		var P = w._doom(zz, func(): return w._kill(zz, "zapper", "zapper"))
		if P == null:
			return false
		w._gag(zz, name if GAGS.has(name) else "cartoon", false, P)
		return true

	func key(z, world: String = "beach", up: bool = false) -> bool:
		var zz = _find(z)
		if zz == null or not w._alive(zz):
			return false
		var P = w._doom(zz, func(): return w._kill(zz, "chroma_key", "chroma_key"))
		if P == null:
			return false
		w._keyed(zz, up, world, P)
		return true

	func tumble(z) -> bool:
		var zz = _find(z)
		if zz == null or not w._alive(zz):
			return false
		var P = w._doom(zz, func(): return w._kill(zz, "boom_mic", "boom_mic"))
		if P == null:
			return false
		w._tumble(zz, w._away(zz.pos), 0, P)
		return true

	func tele(x = null, z = null) -> bool:
		var t = w._spawnTele()
		if t != null and x != null:
			var f = w._floorY(float(x), float(z), 50.0)
			w._telePos(t, Vector3(float(x), (f if f != null else 0.0) + 1.5, float(z)))
			t.vel = Vector3.ZERO
		return t != null

	# Advances wonder's effects (and game.fx) by `seconds` in fixed steps: deterministic screenshots with time.scale 0.
	func step(seconds: float = 0.1, h: float = 1.0 / 60.0) -> Dictionary:
		var g = w.game
		var t := 0.0
		while t < seconds - 1e-6:
			var d := minf(h, seconds - t)
			w._fxTime += d
			w._syncFxTime()
			w._updateWeaponState(d)
			w._updateBlobs(d)
			w._updatePuddles(d)
			w._updateTeles(d)
			w._updateStatus(d)
			w._updateActors(d)
			w._updateHidden(d)
			w._updatePools(d)
			w._sys("fx", "update", [d])
			t += h
		w._sys("fx", "lateUpdate", [0.0])
		return state()

	func signal_(z, s) -> bool:
		return w.applySignal(_find(z), s, {"weaponId": "debug"})

	func burn(z) -> bool:
		return w.applySignal(_find(z), "hot_mic")

	func laugh(z) -> bool:
		return w.applySignal(_find(z), "laugh_track")

	func freeze(z) -> bool:
		return w.applySignal(_find(z), "cold_open")

	func state() -> Dictionary:
		var r2 := func(v: float) -> float: return snappedf(v, 0.01)
		var tl: Array = []
		for t in w.teles:
			var sat := 0
			for k in t.seated:
				var s = w._seatOf(t.seated[k])
				if s != null and (s.plopped or s.stand):
					sat += 1
			tl.append({"state": t.state, "pos": [r2.call(t.pos.x), r2.call(t.pos.y), r2.call(t.pos.z)], "seated": t.seated.size(), "live": r2.call(t.live),
				"yaw": snappedf(t.yaw, 0.001), "sat": sat})
		var pa: Array = []
		for p in w._puddles:
			pa.append([r2.call(p.pos.x), r2.call(p.pos.y), r2.call(p.pos.z)])
		var splats := 0
		for k in ["splat", "splatUp"]:
			for it in w.pools[k].items:
				if it.alive:
					splats += 1
		return {
			"delegated": w._delegated, "reloading": w.reloading, "reloadId": w.reloadId, "recording": w.recording, "charge": r2.call(w.charge),
			"actors": w._actors.size(), "hidden": w._hidden.size(), "status": w._status.size(), "blobs": w._blobs.size(), "puddles": w._puddles.size(),
			"teles": tl, "lastZap": w._lastZap, "puddleAt": pa, "splats": splats,
		}
