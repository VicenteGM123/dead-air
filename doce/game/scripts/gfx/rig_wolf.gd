class_name RigWolf
extends Rig
## WOLF of Nemea (bestiary): a lean grey-blue wolf, ~1.5 m from nose to rump (+0.45 m of tail), 0.8 m at the
## withers, lighter belly and legs, a dark saddle, amber glowing eyes. Three coats for packs (variant 0 grey,
## 1 dark alpha (bigger), 2 pale (smaller)); every wolf also gets a small random size and idle variation.
##
## Contract (see BRIEF "Bestiary rigs"): set_locomotion(speed, max_speed) every frame, play(action) -> length.
##   bite      head lunge, mouth closed            event impact
##   lunge     crouch, leap at the hero, land      events leap, impact (in the air), land
##             The rig lifts the body along the arc between leap and land; the encounter moves the root
##             horizontally (leap at LUNGE_LEAP s, impact LUNGE_HIT s, land at LUNGE_LAND s; ~2.5 m is a good jump).
##   howl      sits, head to the sky, mouth closed event howl
##   hit, stagger (bigger knock, stumbling steps), death (falls on its side and stays down; event fall)
## Locomotion: walk (~1.3 m/s), trot (~3.4 m/s), gallop (~8 m/s); the gait follows the speed given.
## Extras: set_alert(0..1) menacing stance (head low, ears pinned) for circling packs; set_look_target(p);
## set_hit_dir(world_dir) before play("hit"/"stagger"/"death"); attach points head(), muzzle(), neck(), chest(),
## paw(i); `ground_fn` (Callable (x, z) -> world height) plants the feet on slopes; events step (each footfall).
## stop() ends a looping action; is_dead(). The eyes flare (bigger, brighter halos) during every wind-up.
##
## The quadruped kit at the bottom of this file (RigWolf.SkinMesh, RigWolf.Quadruped) is shared by RigBoar and
## RigLion: each beast is ONE skinned mesh (one draw call + two eye halos) with smooth, blended weights (no
## cracks at the joints), posed every frame from code: spine curve, two-bone leg IK with planted feet, neck and
## head, tail chain, ears and eyelids, plus a body ground clamp (torso, neck and thighs never go under the ground;
## a dead beast rests on it). Models face -Z, origin on the ground under the middle of the body. Off screen the
## skeleton is not updated (the solver, events and attachment markers still are). Checked by
## tools/clip_check_beasts.tscn; previews in tools/preview_beasts.gd.

const COATS := [
	{"name": "grey", "scale": 1.05, "back": Color("6A6B75"), "side": Color("7E7F88"), "belly": Color("E2DCD0"),
		"saddle": Color("52535D"), "dark": Color("34343C"), "mask": Color("45464F"), "nose": Color("222228"),
		"eye": Color("FFB347"), "ruff": Color("CFCAC4")},
	{"name": "dark", "scale": 1.14, "back": Color("4E4F5A"), "side": Color("5C5D68"), "belly": Color("B9B3AA"),
		"saddle": Color("3C3D47"), "dark": Color("26262D"), "mask": Color("2E2F37"), "nose": Color("1A1A1F"),
		"eye": Color("FFA23A"), "ruff": Color("8E8C8E")},
	{"name": "pale", "scale": 0.96, "back": Color("8F8F98"), "side": Color("A3A2A8"), "belly": Color("F0ECE4"),
		"saddle": Color("73747E"), "dark": Color("4A4B55"), "mask": Color("6E6F78"), "nose": Color("26262E"),
		"eye": Color("FFC25A"), "ruff": Color("E8E4DE")},
]

const SPEC := {
	"spine_s": [0.0, 0.34, 0.68, 1.0],
	"hip": Vector3(0, 0.64, 0.30),
	"chest": Vector3(0, 0.665, -0.255),
	"neck_base": Vector3(0, 0.755, -0.385),
	"neck_len": 0.29,
	"neck_pitch": 0.62,
	"head_pitch": -0.2,
	"front": [Vector3(-0.10, 0.575, -0.30), Vector3(-0.106, 0.40, -0.212), Vector3(-0.098, 0.145, -0.25), Vector3(-0.098, 0.038, -0.28)],
	"hind": [Vector3(-0.092, 0.60, 0.315), Vector3(-0.118, 0.40, 0.215), Vector3(-0.10, 0.165, 0.37), Vector3(-0.10, 0.038, 0.305)],
	"tail_root": Vector3(0, 0.725, 0.46),
	"tail_n": 6,
	"tail_len": 0.46,
	"tail_pitch": -0.62,
	"tail_curl": 0.1,
	"tail_r": [0.05, 0.068, 0.078, 0.075, 0.064, 0.044, 0.014],
	"ear": [Vector3(-0.06, 0.1, 0.012), -0.28, -0.1],
	"eye": Vector3(0, 0.043, -0.095),
	"muzzle": Vector3(0, -0.03, -0.27),
	"lift_scale": 1.0,
	# walk (lateral sequence), trot (diagonal pairs), rotary gallop. Leg order FL FR HL HR.
	"gaits": [
		{"speed": 1.3, "freq": 1.6, "duty": 0.64, "off": [0.75, 0.25, 0.0, 0.5], "lift": 0.075, "flex": 0.9,
			"bob": 0.012, "bob_m": 2.0, "bob_ph": 0.1, "pitch": 0.006, "spine": 0.0, "roll": 0.025, "head": 0.035,
			"track_f": -0.025, "track_h": 0.046, "zoff_h": 0.035},
		{"speed": 3.4, "freq": 2.6, "duty": 0.46, "off": [0.5, 0.0, 0.0, 0.5], "lift": 0.11, "flex": 1.25,
			"bob": 0.022, "bob_m": 2.0, "bob_ph": 0.15, "pitch": 0.008, "spine": 0.0, "roll": 0.03, "head": 0.04,
			"track_f": -0.032, "track_h": 0.072, "zoff_h": 0.03},
		{"speed": 8.0, "freq": 3.0, "duty": 0.28, "off": [0.45, -0.45, 0.0, 0.9], "lift": 0.15, "flex": 1.5,
			"bob": 0.04, "bob_m": 1.0, "bob_ph": 0.9, "pitch": 0.05, "spine": 0.055, "roll": 0.02, "head": 0.06,
			"track_f": -0.032, "track_h": 0.074, "zoff_f": 0.09, "zoff_h": -0.04},
	],
	"gait_up": [1.9, 5.0],
	"max_stance": 0.52,
}

## Lunge timing (seconds into the action), for the encounter code that moves the wolf through the air.
const LUNGE_LEN := 1.25
const LUNGE_LEAP := 0.475
const LUNGE_HIT := 0.65
const LUNGE_LAND := 0.925

## Wolf animation: [length, loop, {channel: keys}, {event: time fraction}]. Keys are [t, value, ease] triples
## (t 0..1 of the action, ease into that key: 0 smooth, 1 fast-out (strikes), 2 slow-out (falls), 3 linear).
## Values are offsets added to the idle/locomotion pose; leg channels use Q.leg(i, k).
var actions := {}

var variant := 0
var coat: Dictionary
var size_k := 1.0
var q: Quadruped
var ground_fn: Callable:
	set(v):
		ground_fn = v
		if q:
			q.ground_fn = v
var alert := 0.0
var _alert_s := 0.0
var _halos: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _dead := false
## Once the death has played out the corpse holds its last pose: no solver, no skeleton update (it costs nothing).
var _frozen := false
## 1 alive .. 0 dead: idle motion (breathing, looking around, tail swish) fades out with it.
var _life := 1.0
var _hit_side := 1.0
var _death_side := 1.0

## Construction tables (shared by the mesh and the clip-check volumes). Torso rows [z, y, half width, half
## height above, below] from the rump; neck rows [f along the neck, w, ht, hb]; head rows in head space;
## leg radii (half width, half depth) at u = 0 .. 3 in half steps; paw rows in paw space.
const TORSO := [
	[0.475, 0.655, 0.03, 0.03, 0.03],
	[0.455, 0.655, 0.085, 0.075, 0.08],
	[0.425, 0.652, 0.12, 0.105, 0.12],
	[0.35, 0.65, 0.142, 0.12, 0.145],
	[0.24, 0.655, 0.132, 0.112, 0.118],
	[0.12, 0.66, 0.126, 0.112, 0.1],
	[0.0, 0.662, 0.14, 0.124, 0.16],
	[-0.12, 0.665, 0.155, 0.142, 0.215],
	[-0.225, 0.67, 0.16, 0.155, 0.245],
	[-0.305, 0.685, 0.152, 0.158, 0.225],
	[-0.36, 0.71, 0.13, 0.142, 0.18],
]
const NECK := [[0.1, 0.132, 0.125, 0.145], [0.42, 0.116, 0.11, 0.122], [0.72, 0.102, 0.096, 0.104], [0.98, 0.086, 0.084, 0.086], [1.1, 0.05, 0.05, 0.05]]
const HEAD := [
	[0.09, 0.04, 0.034, 0.034, 0.034],
	[0.065, 0.036, 0.09, 0.08, 0.072],
	[0.02, 0.03, 0.116, 0.098, 0.09],
	[-0.035, 0.02, 0.114, 0.093, 0.088],
	[-0.082, 0.01, 0.096, 0.077, 0.078],
	[-0.122, -0.008, 0.072, 0.06, 0.068],
	[-0.165, -0.022, 0.062, 0.05, 0.06],
	[-0.21, -0.03, 0.052, 0.044, 0.05],
	[-0.248, -0.034, 0.042, 0.037, 0.04],
]
const LEG_FRONT := [Vector2(0.074, 0.1), Vector2(0.064, 0.082), Vector2(0.052, 0.056), Vector2(0.044, 0.046), Vector2(0.038, 0.04), Vector2(0.034, 0.036), Vector2(0.033, 0.035)]
const LEG_HIND := [Vector2(0.09, 0.138), Vector2(0.076, 0.108), Vector2(0.056, 0.064), Vector2(0.047, 0.052), Vector2(0.039, 0.042), Vector2(0.034, 0.036), Vector2(0.033, 0.035)]
const PAW := [[0.022, -0.006, 0.027, 0.022, 0.022], [-0.006, -0.012, 0.04, 0.026, 0.026], [-0.036, -0.018, 0.04, 0.02, 0.02], [-0.056, -0.022, 0.03, 0.013, 0.016]]

## Eye placement on the head (head space): x offset of each eye from the eyelid bone and the eye's normal.
const EYE_X := 0.074
const EYE_N := Vector3(0.72, 0.58, -0.37)

static var _mesh_cache := {}


func _init(v: int = 0) -> void:
	variant = v


func _ready() -> void:
	_rng.randomize()
	variant = clampi(variant, 0, COATS.size() - 1)
	coat = COATS[variant]
	size_k = float(coat["scale"]) * _rng.randf_range(0.97, 1.03)
	_death_side = -1.0 if _rng.randf() < 0.5 else 1.0
	q = Quadruped.new(SPEC)
	q.torso_samples(TORSO, 2.2, 12, NECK, LEG_FRONT, LEG_HIND)
	# the ruff at the neck base (its tufts reach ~0.1 m out from the neck surface)
	var nb: Transform3D = q.rest[q.B_NECK0]
	q.add_clamp_ring(nb.origin, nb.basis.x, nb.basis.y, 0.182, 0.172, 0.194, PackedFloat32Array([q.B_NECK0, 1.0]))
	var key := "wolf_%d" % variant
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _build_mesh(q, coat)
	q.attach(self, _mesh_cache[key], size_k, AABB(Vector3(-1.1, -0.1, -1.5), Vector3(2.2, 1.9, 2.8)))
	q.ground_fn = ground_fn
	q.idle_seed = _rng.randf() * 100.0
	q.head_pts = Quadruped.head_samples(HEAD)
	for s in [-1.0, 1.0]:
		for k in 3:
			var base := Vector3(0.1 * s, 0.012 - 0.03 * k, -0.02 + 0.03 * k)
			q.head_pts.append(base + Vector3(0.055 * s, -0.03 - 0.012 * k, 0.065 + 0.01 * k))
	for ex in q.ear_local:
		for p in [Vector3(-0.041, 0, -0.016), Vector3(0.041, 0, -0.016), Vector3(0, 0, 0.03), Vector3(0, 0.04, 0)]:
			q.head_pts.append(ex * p)
	parts["head"] = q.marker(&"head")
	for s in [-1.0, 1.0]:
		var e: Vector3 = SPEC["eye"] + Vector3(EYE_X * s, 0.0, 0.0)
		var en := Vector3(EYE_N.x * s, EYE_N.y, EYE_N.z).normalized()
		var h := add_glow("head", e + en * 0.006, coat["eye"], 0.07, 0.45)
		Materials.set_param(h, &"pull", 0.06)
		h.set_meta(&"n", en)
		_halos.append(h)
	_define_actions()
	q.solve(0.0)
	q.apply()


# --- public API --------------------------------------------------------------------------------------------

func play(a: String) -> float:
	if _dead and a != "death":
		return 0.0
	if not actions.has(a):
		return 0.0
	q.push_prev(action, action_t, actions.get(action, []))
	super.play(a)
	if a == "death":
		_dead = true
	var def: Array = actions[a]
	return float(def[0])


func _action_length(a: String) -> float:
	var def: Array = actions.get(a, [])
	if def.is_empty():
		return 0.4
	return INF if bool(def[1]) else float(def[0])


## Ends a looping action (and fades it out). Wolves have no loops; kept for API symmetry with the boar and lion.
func stop() -> void:
	if action != "":
		q.push_prev(action, action_t, actions.get(action, []))
		action = ""


func is_dead() -> bool:
	return _dead


## 0 relaxed .. 1 menacing (head low, ears pinned, tail stiff): for pack members circling the hero.
func set_alert(k: float) -> void:
	alert = clampf(k, 0.0, 1.0)


func set_look_target(world_pos: Vector3, weight: float = 1.0) -> void:
	q.look_target = world_pos
	q.look_w_target = weight


func clear_look() -> void:
	q.look_w_target = 0.0


## Direction the next hit comes from (world space, pointing from the attacker to the wolf).
func set_hit_dir(world_dir: Vector3) -> void:
	var l := global_transform.basis.inverse() * world_dir
	_hit_side = 1.0 if l.x >= 0.0 else -1.0
	_death_side = _hit_side


func head() -> Node3D:
	return q.marker(&"head")


func muzzle() -> Node3D:
	return q.marker(&"muzzle")


func neck() -> Node3D:
	return q.marker(&"neck")


func chest() -> Node3D:
	return q.marker(&"chest")


func paw(i: int) -> Node3D:
	return q.marker(Quadruped.PAW_NAMES[i])


func lock_point() -> Vector3:
	return q.marker(&"chest").global_position + Vector3(0, 0.12 * size_k, 0)


## Capsule cores of the body parts for tools/clip_check_beasts.gd (see Quadruped.volumes()).
func clip_volumes() -> Array:
	return q.volumes(TORSO, NECK, HEAD, LEG_FRONT, LEG_HIND, PAW, SPEC["tail_r"])


## Previews and the clip checker: pose the rig at `time` seconds into `a` (or locomotion when a == "").
func debug_seek(a: String, time: float, move_speed: float = 0.0) -> void:
	q.always_pose = true
	set_locomotion(move_speed, 8.0)
	if a != "":
		play(a)
	var dt := 1.0 / 60.0
	var n := int(ceil(time / dt))
	for i in n:
		_process(dt)
	if a != "" and actions.has(a) and not bool(actions[a][1]):
		action = a
		action_t = minf(time, float(actions[a][0]) * 0.999)
		_animate(0.0)


# --- animation ---------------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if _frozen:
		return
	var c := q.begin(delta)
	var tt := t
	_alert_s = lerpf(_alert_s, 0.0 if _dead else alert, 1.0 - exp(-delta * 4.0))
	var al := _alert_s
	# Idle life: breathing, a slow look around, ears that twitch, a tail that sways (all fade out in death).
	_life = move_toward(_life, 0.0 if _dead else 1.0, delta * 1.5)
	q.twitch = not _dead
	c[Quadruped.BREATH] = sin(tt * 2.1) * 0.022 * _life
	c[Quadruped.NECK_P] += sin(tt * 0.31 + q.idle_seed) * 0.04 * _life - al * 0.42
	c[Quadruped.HEAD_P] += al * 0.3
	c[Quadruped.NECK_Y] += sin(tt * 0.23 + q.idle_seed * 2.0) * 0.12 * (1.0 - al) * _life
	c[Quadruped.Y_FRONT] -= al * 0.07
	c[Quadruped.Y_REAR] -= al * 0.03
	c[Quadruped.EARS] = 0.35 - al * 1.35
	c[Quadruped.TAIL_P] += al * 0.12
	c[Quadruped.TAIL_SWAY] = (0.1 * (1.0 - al) + 0.02) * _life
	c[Quadruped.GLOW] = 1.0 + al * 0.35
	c[Quadruped.STAB] = 0.75
	# Actions (with a short crossfade from the previous one).
	q.run_actions(self, actions, _dead, _proc, delta)
	q.solve(delta)
	q.apply()
	q.update_halos(_halos, 0.45 * clampf(c[Quadruped.GLOW], 0.0, 3.0) * clampf(c[Quadruped.EYES], 0.0, 1.0))
	# the eyes flare before an attack (wind-up glow keys): bigger halos read from 10 m, where an eye is ~3 px
	var flare := clampf(1.0 + (c[Quadruped.GLOW] - 1.0) * 0.8, 1.0, 2.0)
	for h in _halos:
		h.scale = Vector3.ONE * flare
	if _dead and action == "":
		_frozen = true


## Procedural parts of the actions (shakes, side-dependent motion) on top of their keys.
func _proc(a: String, p: float, at: float, w: float) -> void:
	var c := q.ch
	match a:
		"bite":
			# a short shake of the head after the snap
			var kb := Rig.smooth((p - 0.5) / 0.05) * (1.0 - Rig.smooth((p - 0.62) / 0.1)) * w
			c[Quadruped.HEAD_R] += sin(at * 38.0) * 0.16 * kb
			c[Quadruped.NECK_Y] += sin(at * 38.0 + 1.0) * 0.08 * kb
		"hit":
			var k := sin(p * PI) * w
			c[Quadruped.X_SHIFT] += 0.05 * _hit_side * k
			c[Quadruped.ROLL] -= 0.14 * _hit_side * k
			c[Quadruped.HEAD_Y] -= 0.35 * _hit_side * k
			c[Quadruped.BEND] += 0.05 * _hit_side * k
		"stagger":
			var k2 := sin(clampf(p * 1.25, 0.0, 1.0) * PI) * w
			c[Quadruped.X_SHIFT] += 0.12 * _hit_side * k2
			c[Quadruped.ROLL] -= 0.22 * _hit_side * k2
			c[Quadruped.BEND] += 0.07 * _hit_side * k2
			c[Quadruped.HEAD_R] += sin(at * 22.0) * 0.18 * k2
			c[Quadruped.HEAD_Y] += -0.3 * _hit_side * k2
			# stumbling steps: the legs on the far side cross under the body
			for i in 4:
				var ph := p * 3.0 + float(i) * 0.37
				var lift := maxf(0.0, sin(ph * TAU)) * 0.07 * k2
				c[Quadruped.leg(i, Quadruped.LY)] += lift
				c[Quadruped.leg(i, Quadruped.LX)] += 0.09 * _hit_side * k2
		"howl":
			var k3 := Rig.smooth((p - 0.25) / 0.1) * (1.0 - Rig.smooth((p - 0.8) / 0.1)) * w
			c[Quadruped.HEAD_P] += sin(at * 9.0) * 0.025 * k3
			c[Quadruped.BREATH] += sin(at * 3.0) * 0.03 * k3
		"death":
			var k4 := Rig.smooth((p - 0.22) / 0.4) * w
			c[Quadruped.ROLL] -= 1.42 * _death_side * k4
			c[Quadruped.X_SHIFT] += 0.12 * _death_side * k4
			c[Quadruped.HEAD_R] -= 0.45 * _death_side * k4
			c[Quadruped.BEND] += -0.06 * _death_side * k4
			c[Quadruped.TAIL_Y] += 0.15 * _death_side * k4
			for i in 4:
				c[Quadruped.leg(i, Quadruped.LX)] -= q.leg_side[i] * (0.015 if i < 2 else 0.05) * k4


func _define_actions() -> void:
	var Y_REAR := Quadruped.Y_REAR
	var Y_FRONT := Quadruped.Y_FRONT
	var Z := Quadruped.Z_SHIFT
	var NP := Quadruped.NECK_P
	var HP := Quadruped.HEAD_P
	var EARS := Quadruped.EARS
	var EYES := Quadruped.EYES
	var GLOW := Quadruped.GLOW
	var TP := Quadruped.TAIL_P
	var FLEX := Quadruped.FLEX
	var GAIT := Quadruped.GAIT
	var STAB := Quadruped.STAB
	var K := func(a: Array) -> PackedFloat32Array: return PackedFloat32Array(a)
	actions = {
		"bite": [0.8, false, {
			Y_FRONT: K.call([0.0, 0.0, 0, 0.42, -0.1, 0, 0.5, -0.03, 1, 0.66, -0.03, 0, 1.0, 0.0, 0]),
			Y_REAR: K.call([0.0, 0.0, 0, 0.42, -0.05, 0, 0.5, 0.0, 1, 1.0, 0.0, 0]),
			Z: K.call([0.0, 0.0, 0, 0.42, 0.1, 0, 0.5, -0.17, 1, 0.66, -0.14, 0, 1.0, 0.0, 0]),
			NP: K.call([0.0, 0.0, 0, 0.42, -0.22, 0, 0.5, -0.62, 1, 0.66, -0.5, 0, 1.0, 0.0, 0]),
			HP: K.call([0.0, 0.0, 0, 0.42, 0.34, 0, 0.5, 0.26, 1, 0.6, 0.16, 0, 1.0, 0.0, 0]),
			EARS: K.call([0.0, 0.0, 0, 0.3, -1.5, 0, 0.8, -1.2, 0, 1.0, 0.0, 0]),
			EYES: K.call([0.0, 0.0, 0, 0.4, -0.4, 0, 0.5, -0.15, 1, 1.0, 0.0, 0]),
			GLOW: K.call([0.0, 0.0, 0, 0.38, 1.2, 0, 0.6, 0.4, 0, 1.0, 0.0, 0]),
			STAB: K.call([0.0, 0.0, 0, 0.3, -0.5, 0, 0.8, -0.5, 0, 1.0, 0.0, 0]),
			FLEX: K.call([0.0, 0.0, 0, 0.42, 0.045, 0, 0.5, -0.025, 1, 1.0, 0.0, 0]),
			TP: K.call([0.0, 0.0, 0, 0.42, 0.25, 0, 1.0, 0.0, 0]),
		}, {"impact": 0.5}],
		"lunge": [LUNGE_LEN, false, {
			Y_REAR: K.call([0.0, 0.0, 0, 0.3, -0.14, 0, 0.36, -0.12, 1, 0.5, 0.42, 1, 0.62, 0.38, 0, 0.74, 0.05, 2, 0.8, -0.1, 0, 0.92, -0.02, 0, 1.0, 0.0, 0]),
			Y_FRONT: K.call([0.0, 0.0, 0, 0.3, -0.19, 0, 0.36, -0.08, 1, 0.48, 0.52, 1, 0.6, 0.36, 0, 0.72, 0.0, 2, 0.78, -0.12, 0, 0.92, -0.02, 0, 1.0, 0.0, 0]),
			Z: K.call([0.0, 0.0, 0, 0.3, 0.1, 0, 0.36, 0.0, 1, 0.55, -0.08, 0, 0.8, -0.04, 0, 1.0, 0.0, 0]),
			NP: K.call([0.0, 0.0, 0, 0.3, -0.38, 0, 0.42, -0.1, 1, 0.52, -0.45, 1, 0.7, -0.15, 0, 0.8, -0.3, 0, 1.0, 0.0, 0]),
			HP: K.call([0.0, 0.0, 0, 0.3, 0.32, 0, 0.42, 0.1, 0, 0.52, 0.25, 1, 0.8, 0.1, 0, 1.0, 0.0, 0]),
			FLEX: K.call([0.0, 0.0, 0, 0.3, 0.05, 0, 0.42, -0.05, 1, 0.6, -0.03, 0, 0.72, 0.03, 0, 1.0, 0.0, 0]),
			EARS: K.call([0.0, 0.0, 0, 0.2, -1.4, 0, 0.85, -1.2, 0, 1.0, 0.0, 0]),
			GLOW: K.call([0.0, 0.0, 0, 0.3, 1.0, 0, 0.6, 0.5, 0, 1.0, 0.0, 0]),
			TP: K.call([0.0, 0.0, 0, 0.3, 0.05, 0, 0.42, 0.55, 1, 0.75, 0.2, 0, 1.0, 0.0, 0]),
			STAB: K.call([0.0, 0.0, 0, 0.3, -0.6, 0, 0.85, -0.6, 0, 1.0, 0.0, 0]),
			GAIT: K.call([0.0, 0.0, 0, 0.12, -1.0, 0, 0.9, -1.0, 0, 1.0, 0.0, 0]),
			# legs: crouched on the ground, then tucked to the body in the air (front reach, hind trail)
			Quadruped.leg(0, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.41, 1.0, 1, 0.72, 1.0, 0, 0.76, 0.0, 0]),
			Quadruped.leg(1, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.41, 1.0, 1, 0.72, 1.0, 0, 0.76, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.42, 1.0, 1, 0.74, 1.0, 0, 0.79, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.42, 1.0, 1, 0.74, 1.0, 0, 0.79, 0.0, 0]),
			Quadruped.leg(0, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, -0.34, 1, 0.66, -0.2, 0, 0.74, 0.0, 0]),
			Quadruped.leg(1, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, -0.30, 1, 0.66, -0.16, 0, 0.74, 0.0, 0]),
			Quadruped.leg(0, Quadruped.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.2, 1, 0.66, 0.08, 0, 0.74, 0.0, 0]),
			Quadruped.leg(1, Quadruped.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.16, 1, 0.66, 0.06, 0, 0.74, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.3, 1, 0.68, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.26, 1, 0.68, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.1, 1, 0.68, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.1, 1, 0.68, 0.0, 0]),
			Quadruped.leg(0, Quadruped.LFLEX): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.45, -0.8, 1, 0.66, 0.0, 0]),
			Quadruped.leg(1, Quadruped.LFLEX): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.45, -0.8, 1, 0.66, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LFLEX): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.45, -0.5, 1, 0.7, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LFLEX): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.45, -0.5, 1, 0.7, 0.0, 0]),
		}, {"leap": LUNGE_LEAP / LUNGE_LEN, "impact": LUNGE_HIT / LUNGE_LEN, "land": LUNGE_LAND / LUNGE_LEN}],
		"howl": [2.8, false, {
			Y_REAR: K.call([0.0, 0.0, 0, 0.18, -0.36, 0, 0.84, -0.36, 0, 0.98, 0.0, 0]),
			Y_FRONT: K.call([0.0, 0.0, 0, 0.18, -0.05, 0, 0.84, -0.05, 0, 0.98, 0.0, 0]),
			Z: K.call([0.0, 0.0, 0, 0.18, -0.12, 0, 0.84, -0.12, 0, 0.98, 0.0, 0]),
			Quadruped.TAIL_Y: K.call([0.0, 0.0, 0, 0.2, 0.12, 0, 0.84, 0.12, 0, 1.0, 0.0, 0]),
			Quadruped.leg(0, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.18, 0.05, 0, 0.84, 0.05, 0, 0.98, 0.0, 0]),
			Quadruped.leg(1, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.18, 0.05, 0, 0.84, 0.05, 0, 0.98, 0.0, 0]),
			NP: K.call([0.0, 0.0, 0, 0.18, 0.1, 0, 0.3, 0.55, 0, 0.8, 0.6, 0, 0.94, 0.0, 0]),
			HP: K.call([0.0, 0.0, 0, 0.2, 0.1, 0, 0.32, 0.95, 0, 0.78, 1.0, 0, 0.92, 0.0, 0]),
			EARS: K.call([0.0, 0.0, 0, 0.3, -0.6, 0, 0.8, -0.6, 0, 1.0, 0.0, 0]),
			EYES: K.call([0.0, 0.0, 0, 0.3, -0.55, 0, 0.8, -0.55, 0, 0.95, 0.0, 0]),
			GLOW: K.call([0.0, 0.0, 0, 0.32, 0.8, 0, 0.8, 0.8, 0, 1.0, 0.0, 0]),
			TP: K.call([0.0, 0.0, 0, 0.18, 0.55, 0, 0.84, 0.55, 0, 1.0, 0.0, 0]),
			STAB: K.call([0.0, 0.0, 0, 0.18, -0.75, 0, 0.84, -0.75, 0, 1.0, 0.0, 0]),
			GAIT: K.call([0.0, 0.0, 0, 0.1, -1.0, 0, 0.9, -1.0, 0, 1.0, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LFLEX): K.call([0.0, 0.0, 0, 0.18, 0.95, 0, 0.84, 0.95, 0, 0.98, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LFLEX): K.call([0.0, 0.0, 0, 0.18, 0.95, 0, 0.84, 0.95, 0, 0.98, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.18, -0.12, 0, 0.84, -0.12, 0, 0.98, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.18, -0.12, 0, 0.84, -0.12, 0, 0.98, 0.0, 0]),
			Quadruped.leg(2, Quadruped.LX): K.call([0.0, 0.0, 0, 0.18, -0.03, 0, 0.84, -0.03, 0, 0.98, 0.0, 0]),
			Quadruped.leg(3, Quadruped.LX): K.call([0.0, 0.0, 0, 0.18, 0.03, 0, 0.84, 0.03, 0, 0.98, 0.0, 0]),
		}, {"howl": 0.3}],
		"hit": [0.34, false, {
			Z: K.call([0.0, 0.0, 0, 0.25, 0.06, 1, 1.0, 0.0, 0]),
			Y_FRONT: K.call([0.0, 0.0, 0, 0.25, -0.02, 1, 1.0, 0.0, 0]),
			NP: K.call([0.0, 0.0, 0, 0.25, 0.22, 1, 1.0, 0.0, 0]),
			HP: K.call([0.0, 0.0, 0, 0.25, 0.2, 1, 1.0, 0.0, 0]),
			EARS: K.call([0.0, 0.0, 0, 0.2, -1.5, 1, 1.0, 0.0, 0]),
			EYES: K.call([0.0, 0.0, 0, 0.2, -0.8, 1, 0.6, -0.5, 0, 1.0, 0.0, 0]),
			TP: K.call([0.0, 0.0, 0, 0.25, -0.12, 1, 1.0, 0.0, 0]),
		}, {}],
		"stagger": [0.9, false, {
			Z: K.call([0.0, 0.0, 0, 0.18, 0.14, 1, 0.5, 0.08, 0, 1.0, 0.0, 0]),
			Y_FRONT: K.call([0.0, 0.0, 0, 0.2, -0.1, 1, 0.55, -0.05, 0, 1.0, 0.0, 0]),
			Y_REAR: K.call([0.0, 0.0, 0, 0.25, -0.06, 1, 1.0, 0.0, 0]),
			NP: K.call([0.0, 0.0, 0, 0.18, -0.25, 1, 0.6, -0.15, 0, 1.0, 0.0, 0]),
			EARS: K.call([0.0, 0.0, 0, 0.15, -1.5, 1, 0.8, -1.0, 0, 1.0, 0.0, 0]),
			EYES: K.call([0.0, 0.0, 0, 0.15, -0.85, 1, 0.6, -0.6, 0, 1.0, 0.0, 0]),
			GLOW: K.call([0.0, 0.0, 0, 0.15, -0.5, 1, 1.0, 0.0, 0]),
			TP: K.call([0.0, 0.0, 0, 0.2, -0.15, 1, 1.0, 0.0, 0]),
			GAIT: K.call([0.0, 0.0, 0, 0.1, -0.8, 0, 0.8, -0.6, 0, 1.0, 0.0, 0]),
		}, {}],
		"death": [1.6, false, {
			# keyed a little below contact: the torso ground clamp lays the body exactly on the ground, then a
			# small rebound (0.75) before it settles
			Y_FRONT: K.call([0.0, 0.0, 0, 0.18, -0.2, 2, 0.32, -0.27, 0, 0.62, -0.5, 2, 0.75, -0.45, 0, 1.0, -0.49, 0]),
			Y_REAR: K.call([0.0, 0.0, 0, 0.22, -0.1, 0, 0.38, -0.2, 2, 0.62, -0.5, 2, 0.75, -0.45, 0, 1.0, -0.49, 0]),
			Z: K.call([0.0, 0.0, 0, 0.3, 0.05, 0, 1.0, 0.05, 0]),
			NP: K.call([0.0, 0.0, 0, 0.18, 0.25, 1, 0.5, -0.5, 2, 0.7, -0.62, 0, 1.0, -0.6, 0]),
			HP: K.call([0.0, 0.0, 0, 0.18, 0.3, 1, 0.6, -0.1, 0, 1.0, -0.15, 0]),
			EARS: K.call([0.0, 0.0, 0, 0.2, -1.4, 0, 1.0, -1.6, 0]),
			EYES: K.call([0.0, 0.0, 0, 0.16, -0.7, 1, 0.55, -0.6, 0, 0.8, -0.97, 0, 1.0, -0.97, 0]),
			GLOW: K.call([0.0, 0.0, 0, 0.3, -0.4, 0, 0.8, -1.0, 0, 1.0, -1.0, 0]),
			TP: K.call([0.0, 0.0, 0, 0.3, -0.1, 0, 1.0, 0.0, 0]),
			FLEX: K.call([0.0, 0.0, 0, 0.3, 0.04, 0, 1.0, 0.02, 0]),
			STAB: K.call([0.0, 0.0, 0, 0.3, -0.75, 0, 1.0, -0.75, 0]),
			GAIT: K.call([0.0, 0.0, 0, 0.12, -1.0, 0, 1.0, -1.0, 0]),
			Quadruped.leg(0, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.3, 0.0, 0, 0.55, 1.0, 0, 1.0, 1.0, 0]),
			Quadruped.leg(1, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.3, 0.0, 0, 0.55, 1.0, 0, 1.0, 1.0, 0]),
			Quadruped.leg(2, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.35, 0.0, 0, 0.6, 1.0, 0, 1.0, 1.0, 0]),
			Quadruped.leg(3, Quadruped.LREL): K.call([0.0, 0.0, 0, 0.35, 0.0, 0, 0.6, 1.0, 0, 1.0, 1.0, 0]),
			Quadruped.leg(0, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.3, -0.1, 0, 0.5, -0.1, 0, 1.0, -0.12, 0]),
			Quadruped.leg(1, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.3, -0.1, 0, 0.5, -0.04, 0, 1.0, -0.04, 0]),
			Quadruped.leg(2, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.5, 0.06, 0, 1.0, 0.1, 0]),
			Quadruped.leg(3, Quadruped.LZ): K.call([0.0, 0.0, 0, 0.5, 0.0, 0, 1.0, 0.03, 0]),
			Quadruped.leg(0, Quadruped.LY): K.call([0.0, 0.0, 0, 0.5, 0.08, 0, 1.0, 0.06, 0]),
			Quadruped.leg(1, Quadruped.LY): K.call([0.0, 0.0, 0, 0.5, 0.12, 0, 1.0, 0.1, 0]),
			Quadruped.leg(2, Quadruped.LY): K.call([0.0, 0.0, 0, 0.5, 0.06, 0, 1.0, 0.05, 0]),
			Quadruped.leg(3, Quadruped.LY): K.call([0.0, 0.0, 0, 0.5, 0.1, 0, 1.0, 0.08, 0]),
		}, {"fall": 0.62}],
	}


# --- mesh --------------------------------------------------------------------------------------------------

static func _build_mesh(qd: Quadruped, cz: Dictionary) -> Array:
	var sm := SkinMesh.new(17)
	var back: Color = cz["back"]
	var side: Color = cz["side"]
	var belly: Color = cz["belly"]
	var saddle: Color = cz["saddle"]
	var dark: Color = cz["dark"]
	# Torso + neck: one continuous loft from the rump to just inside the head.
	sm.body_loft(qd, TORSO, NECK, 16, 0.0, 0.02, 2.2, 2)
	var s0 := 0
	sm.paint(s0, func(p: Vector3, n: Vector3) -> Color:
		if p.z < -0.39 or p.y > 0.82 and p.z < -0.3:
			# neck: pale throat, dark mane on top
			if n.y < -0.25 or (n.z < -0.55 and n.y < 0.3):
				return belly
			if n.y > 0.55:
				return saddle
			return side
		if n.y < -0.42:
			return belly
		if n.y < -0.12:
			return side.lerp(belly, 0.45)
		if n.y > 0.62 and p.z > -0.32 and p.z < 0.3:
			return saddle
		if n.y > 0.35:
			return back
		return side)
	# Neck ruff: shaggy tufts around the top and sides of the neck (hides the head join).
	var ruff_from := sm.size()
	var nb: Transform3D = qd.rest[qd.B_NECK0]
	var n1: Transform3D = qd.rest[qd.B_NECK1]
	for k in 11:
		var a := lerpf(-2.3, 2.3, float(k) / 10.0)
		var at := n1 if absf(a) < 1.2 else nb
		var bone := qd.B_NECK1 if absf(a) < 1.2 else qd.B_NECK0
		var dir_out := (at.basis.x * sin(a) + at.basis.y * cos(a)).normalized()
		var base := at.origin + dir_out * 0.07 + at.basis.z * 0.02
		var tip := base + dir_out * 0.07 + at.basis.z * 0.1 - Vector3(0, 0.02, 0)
		sm.spike(base, base + (tip - base) * 0.5 + dir_out * 0.02, tip, 0.042, 0.032, dir_out.cross(at.basis.z), 6, PackedFloat32Array([bone, 1.0]))
	# scruff: tufts along the top of the neck to the withers
	var hd: Transform3D = qd.rest[qd.B_HEAD]
	var chx: Transform3D = qd.rest[qd.ns - 1]
	for k in 6:
		var f := float(k) / 5.0
		var p0: Vector3 = hd.origin.lerp(chx.origin + Vector3(0, 0.0, 0.02), f) + Vector3(0, lerpf(0.06, 0.15, f), 0)
		var dirb := (chx.origin - hd.origin).normalized()
		var tip := p0 + dirb * 0.1 + Vector3(0, 0.035 - f * 0.02, 0)
		var bone := qd.B_NECK1 if f < 0.34 else (qd.B_NECK0 if f < 0.7 else qd.ns - 1)
		sm.spike(p0, p0.lerp(tip, 0.5) + Vector3(0, 0.02, 0), tip, 0.06 - f * 0.012, 0.03, Vector3.RIGHT, 6, PackedFloat32Array([bone, 1.0]))
	sm.paint(ruff_from, func(_p: Vector3, n: Vector3) -> Color: return side if n.y < 0.2 else (saddle if n.y > 0.7 else back))
	# Legs.
	for i in 4:
		var front := i < 2
		var from := sm.size()
		sm.leg_tube(qd, i, LEG_FRONT if front else LEG_HIND, 10, 0.08)
		sm.paw_loft(qd, i, PAW, 10)
		var sx := qd.leg_side[i]
		sm.paint(from, func(p: Vector3, n: Vector3) -> Color:
			if p.y < 0.045:
				return side.lerp(belly, 0.3)
			var inner := n.x * sx < -0.35
			if p.y < 0.22:
				return side.lerp(belly, 0.7) if inner or n.z > 0.45 else side.lerp(belly, 0.22)
			if inner or (front and n.z > 0.55) or (not front and n.z < -0.45 and p.y < 0.45):
				return side.lerp(belly, 0.75)
			return side)
	# Tail: bushy, pale underneath, dark tip.
	var tail_from := sm.size()
	sm.tail_tube(qd, SPEC["tail_r"], 10)
	var tip_z: float = qd.rest_tail_pts[qd.tail_n].z
	var root_z: float = qd.rest_tail_pts[0].z
	sm.paint(tail_from, func(p: Vector3, n: Vector3) -> Color:
		var u := (p.z - root_z) / maxf(tip_z - root_z, 0.01)
		if u > 0.82:
			return dark
		if n.y < -0.3 and u > 0.15:
			return belly.lerp(side, 0.3)
		return saddle if n.y > 0.4 else back)
	# Head: skull, stop and a long tapered muzzle; ears; glowing almond eyes in a dark mask; black nose.
	var hx: Transform3D = qd.rest[qd.B_HEAD]
	var hinv := hx.affine_inverse()
	var head_from := sm.size()
	sm.head_loft(hx, HEAD, 16, 0.0, 0.024, qd.B_HEAD, 2.2, 2)
	var eye_c: Vector3 = SPEC["eye"]
	sm.paint(head_from, func(p: Vector3, n: Vector3) -> Color:
		var l := hinv * p
		var ln := (hinv.basis * n).normalized()
		var ex := Vector3(absf(l.x), l.y, l.z)
		if ex.distance_to(Vector3(EYE_X, eye_c.y, eye_c.z)) < 0.038:
			return cz["mask"]
		if ln.y < -0.3:
			return belly
		if l.z < -0.125 and ln.y > 0.45:
			return back
		if absf(ln.x) > 0.4 and l.z > -0.13 and l.y < 0.025:
			return cz["ruff"]
		if l.z < -0.125:
			return side.lerp(belly, 0.45)
		return back if ln.y > 0.35 else side)
	# Cheek ruff: pointed tufts sweeping back from the cheeks.
	var cheek_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		for k in 3:
			var base := Vector3(0.1 * s, 0.012 - 0.03 * k, -0.02 + 0.03 * k)
			var tip := base + Vector3(0.055 * s, -0.03 - 0.012 * k, 0.065 + 0.01 * k)
			sm.spike(base, base + (tip - base) * 0.5 + Vector3(0.012 * s, 0.012, 0), tip, 0.036, 0.017, Vector3.UP, 5, PackedFloat32Array([qd.B_HEAD, 1.0]))
	sm.mb.pop()
	sm.paint(cheek_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["ruff"])
	# Nose pad.
	var nose_from := sm.size()
	sm.mb.push(hx)
	sm.ellipsoid(Vector3(0, -0.028, -0.262), Vector3(0.034, 0.025, 0.026), 10, 5)
	sm.mb.pop()
	sm.rigid(qd.B_HEAD)
	sm.paint(nose_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["nose"])
	# Ears (own bones): tall pointed triangles, dark inside.
	for e in 2:
		var ex: Transform3D = qd.rest[qd.B_EAR_L + e]
		var ear_from := sm.size()
		sm.mb.push(ex)
		sm.ear(Vector3.ZERO, 0.082, 0.045, 0.115, 0.0, qd.B_EAR_L + e)
		sm.mb.pop()
		sm.rigid(qd.B_EAR_L + e)
		var einv := ex.affine_inverse()
		sm.paint(ear_from, func(p: Vector3, n: Vector3) -> Color:
			var ln := (einv.basis * n).normalized()
			var lp := einv * p
			if lp.y > 0.085:
				return dark
			if ln.z < -0.55:
				return cz["ruff"]
			return back)
	# Eyes: slanted glowing almonds (self-lit), on the eyelid bone.
	var eye_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		sm.almond(Vector3(EYE_X * s, eye_c.y, eye_c.z), Vector3(EYE_N.x * s, EYE_N.y, EYE_N.z).normalized(), s, 0.022, 0.0095, 0.2, qd.B_EYES, 0.009)
	sm.mb.pop()
	sm.rigid(qd.B_EYES)
	var eye_col: Color = cz["eye"]
	sm.paint(eye_from, func(_p: Vector3, _n: Vector3) -> Color: return Color(eye_col.r, eye_col.g, eye_col.b, 0.5))
	return sm.commit(qd.rest)


# =========================================================================================================
# Quadruped kit (shared with RigBoar and RigLion)
# =========================================================================================================

## A skinned mesh under construction: MeshBuilder geometry plus up to four bone weights per vertex. Shapes made
## with MeshBuilder primitives are bound afterwards with rigid(); lofts and tubes bind ring by ring with blended
## weights so joints bend smoothly. commit() gives [ArrayMesh, Skin] for the rest pose `rest` (bone frames).
class SkinMesh extends RefCounted:
	var mb: MeshBuilder
	var bi := PackedInt32Array()
	var bw := PackedFloat32Array()

	func _init(seed_value: int = 1) -> void:
		mb = MeshBuilder.new(seed_value)

	func size() -> int:
		return mb._v.size()

	func _push(b: PackedFloat32Array) -> void:
		if b.size() > 8:
			b = mix_binds(b, PackedFloat32Array(), 0.0)
		var tot := 0.0
		var k := 1
		while k < b.size():
			tot += b[k]
			k += 2
		for s in 4:
			if s * 2 + 1 < b.size() and tot > 0.0:
				bi.append(int(b[s * 2]))
				bw.append(b[s * 2 + 1] / tot)
			else:
				bi.append(0)
				bw.append(0.0)

	## Everything added since the last binding follows `bone`.
	func rigid(bone: int) -> void:
		var b := PackedFloat32Array([float(bone), 1.0])
		while bi.size() < size() * 4:
			_push(b)

	## Everything added since the last binding: fn.call(vertex) -> PackedFloat32Array [bone, w, bone, w, ...].
	func bind_fn(fn: Callable) -> void:
		while bi.size() < size() * 4:
			_push(fn.call(mb._v[bi.size() / 4]))

	## Triangle turned to face away from `inside`, each corner with its own weights.
	func tri_o(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, wa: PackedFloat32Array, wb: PackedFloat32Array, wc: PackedFloat32Array, col: Color = Color.WHITE) -> void:
		if bi.size() != size() * 4:
			push_error("SkinMesh: unbound vertices before tri_o")
			rigid(0)
		if (b - a).cross(c - a).dot((a + b + c) / 3.0 - inside) < 0.0:
			var tv := b
			b = c
			c = tv
			var tw := wb
			wb = wc
			wc = tw
		var n0 := size()
		mb.tri(a, b, c, col)
		if size() == n0:
			return
		_push(wa)
		_push(wc)
		_push(wb)

	## Recolours the triangles from vertex `from` on: fn.call(centroid, face normal) -> Color (model space).
	func paint(from: int, fn: Callable) -> void:
		var cols := mb._c
		mb._c = PackedColorArray()
		var i := from
		while i + 2 < mb._v.size():
			var cen := (mb._v[i] + mb._v[i + 1] + mb._v[i + 2]) / 3.0
			var col: Color = fn.call(cen, mb._n[i])
			cols[i] = col
			cols[i + 1] = col
			cols[i + 2] = col
			i += 3
		mb._c = cols

	## Nearest hit of the ray (origin, dir) on the triangles built from vertex `from` to vertex `to` (model
	## space): [point, outward face normal], or [] when it misses. Used to seat details on a loft's surface.
	func raycast(from: int, to: int, origin: Vector3, dir: Vector3) -> Array:
		var best := INF
		var out: Array = []
		var i := from
		while i + 2 < mini(to, mb._v.size()):
			var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, mb._v[i], mb._v[i + 1], mb._v[i + 2])
			if hit != null:
				var d := ((hit as Vector3) - origin).length()
				if d < best:
					best = d
					out = [hit, mb._n[i]]
			i += 3
		return out

	## Basis with +Z along `dir` (X kept as horizontal as possible).
	static func frame_z(dir: Vector3) -> Basis:
		var z := dir.normalized()
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT
		x = x.normalized()
		return Basis(x, z.cross(x), z)

	## Superellipse ring around `c` in the plane of x and y (half sizes w, above ht, below hb, exponent e).
	static func ring(c: Vector3, x: Vector3, y: Vector3, w: float, ht: float, hb: float, e: float, sides: int) -> PackedVector3Array:
		var r := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var ca := cos(a)
			var sa := sin(a)
			var px := signf(ca) * pow(absf(ca), 2.0 / e) * w
			var py := signf(sa) * pow(absf(sa), 2.0 / e) * (ht if sa > 0.0 else hb)
			r.append(c + x * px + y * py)
		return r

	## Loft through `cs` (centres, current builder space). dims[k] = Vector4(w, ht, hb, exponent), binds[k] =
	## that ring's weights. Ring frames follow the path (parallel transport from x0). The ends close with fans
	## to points cap0 before the first / cap1 after the last centre (negative = open).
	func loft(cs: PackedVector3Array, dims: Array, binds: Array, sides: int, cap0: float, cap1: float, x0: Vector3 = Vector3.RIGHT, sub: int = 1) -> void:
		if sub > 1:
			var r := refine(cs, dims, binds, sub)
			cs = r[0]
			dims = r[1]
			binds = r[2]
		var n := cs.size()
		var rings: Array[PackedVector3Array] = []
		var tans := PackedVector3Array()
		var x := x0
		for k in n:
			var tg: Vector3
			if k == 0:
				tg = cs[1] - cs[0]
			elif k == n - 1:
				tg = cs[n - 1] - cs[n - 2]
			else:
				tg = (cs[k + 1] - cs[k]).normalized() + (cs[k] - cs[k - 1]).normalized()
			tg = tg.normalized()
			tans.append(tg)
			x = (x - tg * x.dot(tg)).normalized()
			var y := x.cross(tg)
			var d: Vector4 = dims[k]
			rings.append(ring(cs[k], x, y, d.x, d.y, d.z, d.w, sides))
		for k in n - 1:
			var inside := (cs[k] + cs[k + 1]) * 0.5
			var r0 := rings[k]
			var r1 := rings[k + 1]
			var b0: PackedFloat32Array = binds[k]
			var b1: PackedFloat32Array = binds[k + 1]
			for i in sides:
				var j := (i + 1) % sides
				tri_o(r0[i], r1[i], r1[j], inside, b0, b1, b1)
				tri_o(r0[i], r1[j], r0[j], inside, b0, b1, b0)
		if cap0 >= 0.0:
			var tip := cs[0] - tans[0] * cap0
			var ins := cs[0] + tans[0] * 0.02
			var bb: PackedFloat32Array = binds[0]
			for i in sides:
				tri_o(tip, rings[0][i], rings[0][(i + 1) % sides], ins, bb, bb, bb)
		if cap1 >= 0.0:
			var tip2 := cs[n - 1] + tans[n - 1] * cap1
			var ins2 := cs[n - 1] - tans[n - 1] * 0.02
			var be: PackedFloat32Array = binds[n - 1]
			for i in sides:
				tri_o(tip2, rings[n - 1][i], rings[n - 1][(i + 1) % sides], ins2, be, be, be)

	## Inserts sub-1 rings between consecutive rings: Catmull-Rom centres, smooth sizes, blended weights.
	static func refine(cs: PackedVector3Array, dims: Array, binds: Array, sub: int) -> Array:
		var n := cs.size()
		var oc := PackedVector3Array()
		var od: Array = []
		var ob: Array = []
		for k in n:
			oc.append(cs[k])
			od.append(dims[k])
			ob.append(binds[k])
			if k == n - 1:
				break
			var p0 := cs[maxi(k - 1, 0)]
			var p1 := cs[k]
			var p2 := cs[k + 1]
			var p3 := cs[mini(k + 2, n - 1)]
			for j in range(1, sub):
				var u := float(j) / float(sub)
				var u2 := u * u
				var u3 := u2 * u
				var c := 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
				oc.append(c)
				var d0: Vector4 = dims[k]
				var d1: Vector4 = dims[k + 1]
				var us := u * u * (3.0 - 2.0 * u)
				od.append(d0.lerp(d1, lerpf(u, us, 0.5)))
				ob.append(mix_binds(binds[k], binds[k + 1], u))
		return [oc, od, ob]

	## Weights a and b blended (t = 0 -> a), merged by bone, the four strongest kept.
	static func mix_binds(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
		var acc := {}
		var k := 0
		while k + 1 < a.size():
			acc[int(a[k])] = float(acc.get(int(a[k]), 0.0)) + a[k + 1] * (1.0 - t)
			k += 2
		k = 0
		while k + 1 < b.size():
			acc[int(b[k])] = float(acc.get(int(b[k]), 0.0)) + b[k + 1] * t
			k += 2
		var pairs: Array = []
		for bone in acc:
			pairs.append([bone, acc[bone]])
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
		var out := PackedFloat32Array()
		for i in mini(pairs.size(), 4):
			out.append(float(pairs[i][0]))
			out.append(float(pairs[i][1]))
		return out

	## Tapered spike along the quadratic Bezier p0 -> p1 -> p2 (fur tufts, mane locks, bristles, tusks): base
	## half sizes w (across `across`) and d, closing to a point. One binding for the whole spike, or
	## `binds_tip` for a two-bone blend from the root to the tip.
	func spike(p0: Vector3, p1: Vector3, p2: Vector3, w: float, d: float, across: Vector3, sides: int, bind: PackedFloat32Array, binds_tip: PackedFloat32Array = PackedFloat32Array(), steps: int = 3, belly: float = 0.0) -> void:
		var cs := PackedVector3Array()
		var dims: Array = []
		var binds: Array = []
		for k in steps + 1:
			var u := float(k) / float(steps)
			var p := p0.lerp(p1, u).lerp(p1.lerp(p2, u), u)
			cs.append(p)
			# belly > 0 keeps the lock full for longer (a flame / leaf rather than a thorn)
			var r := (1.0 - pow(u, 1.0 + belly * 2.0) * 0.92) * (1.0 + belly * 0.35 * sin(u * PI))
			dims.append(Vector4(w * r, d * r, d * r, 2.0))
			if binds_tip.is_empty():
				binds.append(bind)
			else:
				binds.append(PackedFloat32Array([bind[0], 1.0 - u, binds_tip[0], u]))
		var tg := (p1 - p0).normalized()
		var x0 := (across - tg * across.dot(tg)).normalized()
		loft(cs, dims, binds, sides, 0.0, (p2 - p1).length() * 0.25, x0)

	## Ellipsoid (smooth) centred at c with radii r, aligned to the current builder space. Bind it afterwards.
	func ellipsoid(c: Vector3, r: Vector3, segs: int = 10, rings_n: int = 6) -> void:
		mb.sphere(c, 1.0, Color.WHITE, segs, rings_n, r)

	## Torso + neck loft. torso rows: [z, y, w, ht, hb] (model space, rump first); neck rows: [f, w, ht, hb]
	## along the rest neck (f 0 = neck base, 1 = head pivot). Rings bind to the spine bones by z and to the
	## neck bones / head by f, blended linearly so the back and the neck bend smoothly.
	func body_loft(q: Quadruped, torso: Array, neck: Array, sides: int, cap0: float, cap1: float, e: float = 2.2, sub: int = 1) -> void:
		var cs := PackedVector3Array()
		var dims: Array = []
		var binds: Array = []
		var zs := PackedFloat32Array()
		for k in q.ns:
			zs.append(q.rest[k].origin.z)
		for row in torso:
			var z: float = row[0]
			cs.append(Vector3(0, row[1], z))
			dims.append(Vector4(row[2], row[3], row[4], e))
			binds.append(q.spine_bind(z))
		for row in neck:
			var np: Array = q.neck_point(float(row[0]))
			cs.append(np[0])
			dims.append(Vector4(row[1], row[2], row[3], e))
			binds.append(np[1])
		loft(cs, dims, binds, sides, cap0, cap1, Vector3.RIGHT, sub)

	## Head loft along head-local -Z (rows [z, y, w, ht, hb]), rigid to `bone`.
	func head_loft(hx: Transform3D, rows: Array, sides: int, cap0: float, cap1: float, bone: int, e: float = 2.2, sub: int = 1) -> void:
		var cs := PackedVector3Array()
		var dims: Array = []
		var binds: Array = []
		var b := PackedFloat32Array([bone, 1.0])
		for row in rows:
			cs.append(Vector3(0, row[1], row[0]))
			dims.append(Vector4(row[2], row[3], row[4], e))
			binds.append(b)
		mb.push(hx)
		loft(cs, dims, binds, sides, cap0, cap1, Vector3.RIGHT, sub)
		mb.pop()

	## Leg tube along the rest joints of leg i: radii[] = Vector2(half width, half depth) at u = 0, 0.5, 1, 1.5,
	## 2, 2.5, 3 (u = joint index along the chain; the tube starts `top` above the shoulder/hip joint, inside the
	## body). Rings near a joint blend the two segment bones.
	func leg_tube(q: Quadruped, i: int, radii: Array, sides: int, top: float, blend: float = 0.22) -> void:
		var j: PackedVector3Array = q.rest_joints[i]
		var bone0 := q.B_LEG + i * 4
		var cs := PackedVector3Array()
		var dims: Array = []
		var binds: Array = []
		var up_dir := (j[0] - j[1]).normalized()
		cs.append(j[0] + up_dir * top)
		dims.append(Vector4(radii[0].x * 0.82, radii[0].y * 0.82, radii[0].y * 0.82, 2.0))
		binds.append(PackedFloat32Array([bone0, 1.0]))
		var us := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
		for k in us.size():
			var u: float = us[k]
			var seg := mini(int(floor(u)), 2)
			var f := u - float(seg)
			var p := j[seg].lerp(j[seg + 1], f) if seg < 3 else j[3]
			if u >= 3.0:
				p = j[3]
			cs.append(p)
			var rv: Vector2 = radii[k]
			dims.append(Vector4(rv.x, rv.y, rv.y, 2.0))
			var jn := roundi(u)
			if absf(u - float(jn)) < blend and jn > 0 and jn <= 3:
				var w_after := 0.5 + 0.5 * (u - float(jn)) / blend
				binds.append(PackedFloat32Array([bone0 + jn - 1, 1.0 - w_after, bone0 + mini(jn, 3), w_after]))
			else:
				binds.append(PackedFloat32Array([bone0 + mini(seg, 3), 1.0]))
		loft(cs, dims, binds, sides, 0.0, -1.0, Vector3.RIGHT)

	## Paw of leg i: an ellipsoid (radii r) at the paw joint + offset, plus `toes` bumps at the front; rigid to the
	## paw bone. Its bottom should sit on the ground.
	func paw(q: Quadruped, i: int, r: Vector3, off: Vector3, toes: int, toe_r: float) -> void:
		var j: PackedVector3Array = q.rest_joints[i]
		var c := j[3] + off
		ellipsoid(c, r, 10, 6)
		if toes > 0 and toe_r > 0.0:
			for k in toes:
				var fx := lerpf(-0.62, 0.62, float(k) / float(maxi(toes - 1, 1)))
				var tc := c + Vector3(fx * r.x, -r.y + toe_r * 0.9, -r.z * 0.78 + absf(fx) * r.z * 0.25)
				ellipsoid(tc, Vector3(toe_r * 0.9, toe_r * 0.85, toe_r * 1.1), 8, 4)
		rigid(q.B_LEG + i * 4 + 3)

	## Paw of leg i as a short loft from heel to toes in paw-bone space (rows [z, y, w, ht, hb] relative to the
	## paw joint), rigid to the paw bone. Keep its bottom at -paw height so it rests on the ground.
	func paw_loft(q: Quadruped, i: int, rows: Array, sides: int) -> void:
		var j: PackedVector3Array = q.rest_joints[i]
		var cs := PackedVector3Array()
		var dims: Array = []
		var binds: Array = []
		var b := PackedFloat32Array([q.B_LEG + i * 4 + 3, 1.0])
		for row in rows:
			cs.append(j[3] + Vector3(0, row[1], row[0]))
			dims.append(Vector4(row[2], row[3], row[4], 2.4))
			binds.append(b)
		loft(cs, dims, binds, sides, 0.012, 0.012)

	## Tail tube along the rest tail chain; radii per joint (root .. tip), two rings per segment, blended.
	func tail_tube(q: Quadruped, radii: Array, sides: int) -> void:
		var pts: PackedVector3Array = q.rest_tail_pts
		var cs := PackedVector3Array()
		var dims: Array = []
		var binds: Array = []
		var n := q.tail_n
		for k in n * 2 + 1:
			var u := float(k) * 0.5
			var s := mini(int(floor(u)), n - 1)
			var f := u - float(s)
			var p := pts[s].lerp(pts[s + 1], f)
			cs.append(p)
			var r := lerpf(float(radii[s]), float(radii[mini(s + 1, radii.size() - 1)]), f)
			dims.append(Vector4(r, r, r, 2.0))
			var b0 := q.B_TAIL + s
			if f < 0.01 and s > 0:
				binds.append(PackedFloat32Array([b0 - 1, 0.5, b0, 0.5]))
			elif f > 0.99 and s < n - 1:
				binds.append(PackedFloat32Array([b0, 0.5, b0 + 1, 0.5]))
			else:
				binds.append(PackedFloat32Array([b0, 1.0]))
		# start inside the rump
		var dir0 := (pts[1] - pts[0]).normalized()
		cs.insert(0, pts[0] - dir0 * 0.05)
		dims.insert(0, dims[0] * Vector4(0.8, 0.8, 0.8, 1.0))
		binds.insert(0, PackedFloat32Array([0, 1.0]))
		loft(cs, dims, binds, sides, 0.0, float(radii[radii.size() - 1]) * 2.0 + 0.01, Vector3.RIGHT)

	## Pointed ear in its own bone space: base triangle at y = 0 (width w, depth d), apex `h` up, tip leaning back.
	func ear(c: Vector3, w: float, d: float, h: float, lean: float, bone: int) -> void:
		var a := c + Vector3(-w * 0.5, 0, -d * 0.35)
		var b := c + Vector3(w * 0.5, 0, -d * 0.35)
		var bk := c + Vector3(0, 0, d * 0.65)
		var m := c + Vector3(0, h * 0.45, lean * 0.4)
		var a2 := m + Vector3(-w * 0.36, 0, -d * 0.28)
		var b2 := m + Vector3(w * 0.36, 0, -d * 0.28)
		var bk2 := m + Vector3(0, 0, d * 0.5)
		var apex := c + Vector3(0, h, lean)
		var cen := c + Vector3(0, h * 0.3, 0)
		var one := PackedFloat32Array([bone, 1.0])
		var tri := func(p: Vector3, q2: Vector3, r: Vector3) -> void:
			tri_o(p, q2, r, cen, one, one, one)
		# lower band
		tri.call(a, b, b2)
		tri.call(a, b2, a2)
		tri.call(b, bk, bk2)
		tri.call(b, bk2, b2)
		tri.call(bk, a, a2)
		tri.call(bk, a2, bk2)
		# upper band
		tri.call(a2, b2, apex)
		tri.call(b2, bk2, apex)
		tri.call(bk2, a2, apex)
		# inner ear (dark) as a separate slightly raised face on the front
		var nf := (b - a).cross(apex - a).normalized()
		if nf.z > 0.0:
			nf = -nf
		var g := (a + b + apex) / 3.0
		var k := 0.62
		tri_o(g + (a - g) * k + nf * 0.004 + Vector3(0, 0.006, 0), g + (b - g) * k + nf * 0.004 + Vector3(0, 0.006, 0), g + (apex - g) * k + nf * 0.004, g - nf, one, one, one)

	## Glowing almond eye (lens) lying on the head surface at `c`, facing `n`; `side` = -1 left / +1 right. The
	## outer corner is lifted by `slant` (a stern, slanted look), never a round cute eye.
	func almond(c: Vector3, n: Vector3, side: float, hw: float, hh: float, slant: float, bone: int, lift: float = 0.0) -> void:
		# lift: pushes the whole eye out along its normal (so a curved head surface never swallows it)
		c += n * lift
		var up := Vector3.UP
		var x := up.cross(n).normalized() * -side
		if x.z > 0.0:
			x = -x
		var y := n.cross(x).normalized()
		if y.y < 0.0:
			y = -y
		var pts := PackedVector3Array()
		var segs := 10
		for i2 in segs:
			var u := lerpf(-1.0, 1.0, float(i2) / float(segs))
			pts.append(c + x * (u * hw) + y * (pow(1.0 - u * u, 0.7) * hh - u * slant * hh * 1.2))
		for i2 in segs:
			var u := lerpf(1.0, -1.0, float(i2) / float(segs))
			pts.append(c + x * (u * hw) + y * (-pow(1.0 - u * u, 0.7) * hh * 0.75 - u * slant * hh * 1.2))
		var cen := c + n * 0.004
		var one := PackedFloat32Array([bone, 1.0])
		for i2 in pts.size():
			tri_o(cen, pts[i2], pts[(i2 + 1) % pts.size()], c - n * 0.05, one, one, one)

	## [ArrayMesh, Skin] for bone rest frames `rest` (model space).
	func commit(rest: Array[Transform3D]) -> Array:
		rigid(0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mb._v
		arrays[Mesh.ARRAY_NORMAL] = MeshBuilder.smooth_normals(mb._v, mb._n, 62.0)
		arrays[Mesh.ARRAY_COLOR] = mb._c
		arrays[Mesh.ARRAY_BONES] = bi
		arrays[Mesh.ARRAY_WEIGHTS] = bw
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var skin := Skin.new()
		for b in rest.size():
			skin.add_bind(b, rest[b].affine_inverse())
		return [m, skin]


## Skeleton, pose channels and solver of a procedural quadruped (spine, neck, head, ears, eyelids, four
## three-segment legs with two-bone IK and planted feet, tail chain), plus the gait engine (walk / trot / gallop
## with planted feet, turning and strafing) and the keyframed action player. The beast rigs fill `ch` (idle
## + action offsets) every frame, then call solve() and apply().
class Quadruped extends RefCounted:
	enum { Y_REAR, Y_FRONT, Z_SHIFT, X_SHIFT, ROLL, YAW, FLEX, BEND, NECK_P, NECK_Y, HEAD_P, HEAD_Y, HEAD_R,
		EARS, EYES, GLOW, TAIL_P, TAIL_Y, TAIL_CURL, TAIL_SWAY, MANE, BREATH, STAB, GAIT, LEG }
	enum { LX, LY, LZ, LFLEX, LREL }
	const LEG_N := 5
	const NCH := LEG + 4 * LEG_N
	const PAW_NAMES := [&"paw_fl", &"paw_fr", &"paw_hl", &"paw_hr"]

	var spec: Dictionary
	var ns := 4
	var spine_s := PackedFloat32Array()
	var hip0 := Vector3.ZERO
	var chest0 := Vector3.ZERO
	var spine_v := Vector3.ZERO
	var neck_base_local := Vector3.ZERO
	var neck_len := 0.3
	var neck_pitch := 0.8
	var head_rel := -0.9
	var leg_anchor := PackedVector3Array()
	var leg_l := PackedVector3Array()
	var leg_theta := PackedFloat32Array()
	var leg_neutral := PackedVector3Array()
	var paw_h := PackedFloat32Array()
	var leg_side := PackedFloat32Array()
	var tail_n := 6
	var tail_seg := 0.08
	var tail_root := Vector3.ZERO
	var tail_pitch := -1.0
	var tail_curl := 0.1
	var tail_r := PackedFloat32Array()
	## Optional tail ornament past the last joint (the lion's tuft): Vector2(extra length, radius) from spec "tail_tip".
	var _tail_tip := Vector2.ZERO
	var ear_local: Array[Transform3D] = []
	var eye_local := Vector3.ZERO
	var muzzle_local := Vector3.ZERO
	## Clearance kept between the muzzle / head pivot and the ground (about the jaw's half height).
	var head_clear := 0.05
	## Points on the head surface (head space) kept above the ground (see head_samples()).
	var head_pts := PackedVector3Array()
	## Farthest head_pts sample from the head pivot (computed on first use).
	var _head_reach := -1.0
	## Ear height (ear bone space), for the ear ground clamp.
	var ear_h := 0.11
	## Opt-in torso ground clamp (see torso_samples()): rest-space points on the torso surface and their spine
	## weights. When any of them would go under the ground (lying dead, a deep crouch, a stagger), the whole
	## spine is lifted until it rests on the ground. Empty = no clamp.
	var torso_pts := PackedVector3Array()
	var torso_binds: Array = []
	## Bones the clamp samples follow and, per bone, the farthest sample from its rest origin: a sample can never
	## be lower than (bone height - that reach), so the exact test only runs when the body is near the ground.
	var _clamp_bones := PackedInt32Array()
	var _clamp_reach := PackedFloat32Array()
	## Terrain of this frame (ground_fn valid): root transform and its inverse, for per-foot ground queries.
	var _has_ground := false
	var _gx := Transform3D.IDENTITY
	var _gx_inv := Transform3D.IDENTITY
	var _head_ground := 0.0

	var B_NECK0 := 0
	var B_NECK1 := 0
	var B_HEAD := 0
	var B_EYES := 0
	var B_EAR_L := 0
	var B_EAR_R := 0
	var B_LEG := 0
	var B_TAIL := 0
	var B_EXTRA := 0
	var bone_count := 0

	var ch := PackedFloat32Array()
	var xf: Array[Transform3D] = []
	var rest: Array[Transform3D] = []
	var rest_joints: Array[PackedVector3Array] = []
	var rest_tail_pts := PackedVector3Array()
	var joints: Array[PackedVector3Array] = []
	var tail_pts := PackedVector3Array()
	var head_xf := Transform3D.IDENTITY
	var _paw_rel: Array[Basis] = []
	var _rest_inv_front := Transform3D.IDENTITY
	var _rest_inv_hind := Transform3D.IDENTITY
	var _chest_rest_pitch := 0.0
	var _resting := true

	# scene
	var rig: Node3D
	var root: Node3D
	var skel: Skeleton3D
	var mesh: MeshInstance3D
	var markers := {}
	var _vis: VisibleOnScreenNotifier3D
	var scale_k := 1.0
	var ground_fn: Callable
	var idle_seed := 0.0
	## Pose bones even off screen (previews, checker, cutscenes). Off screen the rig otherwise only keeps time.
	var always_pose := false
	var _posed := false

	# gait
	var gaits: Array = []
	var gait_up := PackedFloat32Array()
	var gait_i := 0
	var _g_from := {}
	var _g_k := 1.0
	var g := {}
	var phase := 0.0
	var walk := 0.0
	var spd := 0.0
	var speed_in := 0.0
	var move_dir := Vector3(0, 0, -1)
	var _meas_dir := Vector3(0, 0, -1)
	var yaw_rate := 0.0
	var _last_pos := Vector3.ZERO
	var _last_yaw := 0.0
	var _has_last := false
	var gait_off := PackedVector3Array()
	var gait_flex := PackedFloat32Array()
	var plant := PackedFloat32Array()
	var _was_stance := PackedByteArray()
	var _ground_h := PackedFloat32Array()
	var steps_enabled := true
	## Random ear twitches (off for a corpse).
	var twitch := true
	## Minimum gait speed (a charging boar gallops even if the encounter forgets set_locomotion).
	var speed_floor := 0.0
	## Step cadence multiplier (< 1: slower, longer, more deliberate steps, e.g. the lion's stalk).
	var cadence_k := 1.0

	# look-at
	var look_target := Vector3.ZERO
	var look_w := 0.0
	var look_w_target := 0.0
	var _look_y := 0.0
	var _look_p := 0.0

	# springs / secondary motion
	var _tail_lag := Vector2.ZERO
	var _ear_twitch := Vector2.ZERO
	var _ear_timer := 1.0
	var t := 0.0

	# action crossfade
	var prev_action := ""
	var prev_t := 0.0
	var prev_def: Array = []
	var _prev_w := 0.0

	func _init(sp: Dictionary) -> void:
		spec = sp
		spine_s = PackedFloat32Array(sp["spine_s"])
		ns = spine_s.size()
		hip0 = sp["hip"]
		chest0 = sp["chest"]
		spine_v = chest0 - hip0
		neck_len = sp["neck_len"]
		neck_pitch = sp["neck_pitch"]
		head_rel = float(sp["head_pitch"]) - neck_pitch
		tail_n = sp["tail_n"]
		tail_seg = float(sp["tail_len"]) / float(tail_n)
		tail_pitch = sp["tail_pitch"]
		tail_curl = sp["tail_curl"]
		var tt: Array = sp.get("tail_tip", [])
		if tt.size() == 2:
			_tail_tip = Vector2(float(tt[0]), float(tt[1]))
		var tr: Array = sp["tail_r"]
		for r in tr:
			tail_r.append(float(r))
		eye_local = sp["eye"]
		muzzle_local = sp["muzzle"]
		head_clear = float(sp.get("head_clear", 0.05))
		gaits = sp["gaits"]
		gait_up = PackedFloat32Array(sp["gait_up"])
		g = gaits[0].duplicate()
		# bones
		B_NECK0 = ns
		B_NECK1 = ns + 1
		B_HEAD = ns + 2
		B_EYES = ns + 3
		B_EAR_L = ns + 4
		B_EAR_R = ns + 5
		B_LEG = ns + 6
		B_TAIL = B_LEG + 16
		B_EXTRA = B_TAIL + tail_n
		bone_count = B_EXTRA
		xf.resize(bone_count)
		rest.resize(bone_count)
		ch.resize(NCH)
		gait_off.resize(4)
		gait_flex.resize(4)
		plant.resize(4)
		plant.fill(1.0)
		_was_stance.resize(4)
		_was_stance.fill(1)
		_ground_h.resize(4)
		tail_pts.resize(tail_n + 1)
		for i in 4:
			joints.append(PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]))
		# ears (head-local): [left base, outward tilt, back tilt]
		var ea: Array = sp.get("ear", [])
		for s in [-1.0, 1.0]:
			if ea.is_empty():
				ear_local.append(Transform3D.IDENTITY)
			else:
				var base: Vector3 = ea[0]
				var eb := Basis(Vector3.BACK, float(ea[1]) * s * -1.0) * Basis(Vector3.RIGHT, float(ea[2]))
				ear_local.append(Transform3D(eb, Vector3(absf(base.x) * s, base.y, base.z)))
		# rest spine (needed for the leg anchors)
		reset_channels()
		_solve_spine()
		var chest_rest := xf[ns - 1]
		var hip_rest := xf[0]
		_chest_rest_pitch = _pitch_of(chest_rest.basis)
		neck_base_local = chest_rest.affine_inverse() * Vector3(sp["neck_base"])
		tail_root = hip_rest.affine_inverse() * Vector3(sp["tail_root"])
		# legs (spec gives the left leg; right legs mirror it)
		for i in 4:
			var front := i < 2
			var jl: Array = sp["front"] if front else sp["hind"]
			var sx := -1.0 if i % 2 == 0 else 1.0
			leg_side.append(sx)
			var jj := PackedVector3Array()
			for p in jl:
				var v: Vector3 = p
				jj.append(Vector3(absf(v.x) * sx, v.y, v.z))
			var sb := chest_rest if front else hip_rest
			leg_anchor.append(sb.affine_inverse() * jj[0])
			leg_l.append(Vector3(jj[0].distance_to(jj[1]), jj[1].distance_to(jj[2]), jj[2].distance_to(jj[3])))
			var dv := jj[2] - jj[3]
			leg_theta.append(atan2(dv.z, dv.y))
			paw_h.append(jj[3].y)
			leg_neutral.append(Vector3(jj[3].x, 0.0, jj[3].z))
		_rest_inv_front = chest_rest.affine_inverse()
		_rest_inv_hind = hip_rest.affine_inverse()
		# full rest pose
		_paw_rel.resize(4)
		for i in 4:
			_paw_rel[i] = Basis.IDENTITY
		solve(0.0)
		for b in bone_count:
			rest[b] = xf[b]
		for i in 4:
			rest_joints.append(joints[i].duplicate())
			var low: Basis = rest[B_LEG + i * 4 + 2].basis
			_paw_rel[i] = low.inverse() * rest[B_LEG + i * 4 + 3].basis
		rest_tail_pts = tail_pts.duplicate()
		_resting = false

	static func leg(i: int, k: int) -> int:
		return LEG + i * LEG_N + k

	## Surface sample points of a head loft table (rows [z, y, w, ht, hb]): sides, bottom and top of each row; with
	## the loft's exponent e > 0, `sides` points around its real superellipse (boxy muzzles have far corners).
	static func head_samples(rows: Array, e: float = 0.0, sides: int = 8) -> PackedVector3Array:
		var out := PackedVector3Array()
		if e > 0.0:
			for k in range(1, rows.size()):
				var rr: Array = rows[k]
				out.append_array(SkinMesh.ring(Vector3(0, rr[1], rr[0]), Vector3.RIGHT, Vector3.UP, float(rr[2]) * 0.96, float(rr[3]) * 0.96, float(rr[4]) * 0.96, e, sides))
			return out
		for k in range(1, rows.size()):
			var r: Array = rows[k]
			var z: float = r[0]
			var y: float = r[1]
			out.append(Vector3(float(r[2]) * 0.92, y, z))
			out.append(Vector3(-float(r[2]) * 0.92, y, z))
			out.append(Vector3(0, y - float(r[4]) * 0.92, z))
			out.append(Vector3(0, y + float(r[3]) * 0.92, z))
		return out

	## Fills torso_pts / torso_binds from a torso loft table (rows [z, y, w, ht, hb], exponent e): `sides` points
	## around each row (the loft's own superellipse), bound to the spine like the mesh rings. Call after _init().
	## Neck rows (rows [f, w, ht, hb], f 0 = neck base .. 1 = head pivot) add rings around the neck, bound like
	## the mesh (neck_point()), so a neck lying on the ground counts too. The check runs after the neck and head
	## are solved.
	func torso_samples(rows: Array, e: float = 2.2, sides: int = 12, neck_rows: Array = [], leg_front: Array = [], leg_hind: Array = []) -> void:
		torso_pts = PackedVector3Array()
		torso_binds = []
		for row in rows:
			if float(row[2]) < 0.05:
				continue
			var z: float = row[0]
			var ring := SkinMesh.ring(Vector3(0, row[1], z), Vector3.RIGHT, Vector3.UP, row[2], row[3], row[4], e, sides)
			for p in ring:
				torso_pts.append(p)
				torso_binds.append(spine_bind(z))
		for row in neck_rows:
			var f: float = row[0]
			if f > 1.0:
				continue
			var np: Array = neck_point(f)
			var tg: Vector3 = (neck_point(f + 0.05)[0] as Vector3) - (neck_point(f - 0.05)[0] as Vector3)
			var x := Vector3.RIGHT
			var y := x.cross(tg.normalized()).normalized()
			if y.y < 0.0:
				y = -y
			var ring := SkinMesh.ring(np[0], x, y, row[1], row[2], row[3], e, sides)
			for p in ring:
				torso_pts.append(p)
				torso_binds.append(np[1])
		# the thigh and shoulder bulk (leg tube rings at u = 0 and 0.5) sticks out past the flanks when lying down
		for i in 4:
			var radii: Array = leg_front if i < 2 else leg_hind
			if radii.size() < 2:
				continue
			var j: PackedVector3Array = rest_joints[i]
			var dir := (j[1] - j[0]).normalized()
			for k in 2:
				var rv: Vector2 = radii[k]
				var y := Vector3.RIGHT.cross(dir).normalized()
				var ring := SkinMesh.ring(j[0].lerp(j[1], 0.5 * float(k)), Vector3.RIGHT, y, rv.x, rv.y, rv.y, 2.0, 8)
				for p in ring:
					torso_pts.append(p)
					torso_binds.append(PackedFloat32Array([B_LEG + i * 4, 1.0]))
		_clamp_prepare()

	## An extra clamp ring (rest model space: centre, ring axes, half sizes) for fur or parts outside the tables.
	func add_clamp_ring(c: Vector3, x: Vector3, y: Vector3, w: float, ht: float, hb: float, bind: PackedFloat32Array, sides: int = 10) -> void:
		for p in SkinMesh.ring(c, x, y, w, ht, hb, 2.0, sides):
			torso_pts.append(p)
			torso_binds.append(bind)
		_clamp_prepare()

	func _clamp_prepare() -> void:
		var reach := {}
		for i in torso_pts.size():
			var b: PackedFloat32Array = torso_binds[i]
			var k := 0
			while k + 1 < b.size():
				var bone := int(b[k])
				reach[bone] = maxf(float(reach.get(bone, 0.0)), torso_pts[i].distance_to(rest[bone].origin))
				k += 2
		_clamp_bones = PackedInt32Array()
		_clamp_reach = PackedFloat32Array()
		for bone in reach:
			_clamp_bones.append(int(bone))
			_clamp_reach.append(float(reach[bone]))

	## Cheap lower bound of the clamp samples (bone heights minus their reach, scaled bones included).
	func _clamp_bound() -> float:
		var lo := INF
		for i in _clamp_bones.size():
			var t := xf[_clamp_bones[i]]
			var sc := t.basis.get_scale()
			lo = minf(lo, t.origin.y - _clamp_reach[i] * maxf(sc.x, maxf(sc.y, sc.z)) * 1.02)
		return lo

	## Rest position and bone weights of the neck path at f (0 = neck base, 0.5 = mid neck, 1 = head pivot;
	## negative = back towards the withers): the binding body_loft gives the neck rings.
	func neck_point(f: float) -> Array:
		var n0: Transform3D = rest[B_NECK0]
		var n1: Transform3D = rest[B_NECK1]
		var hp: Vector3 = rest[B_HEAD].origin
		if f < 0.0:
			return [n0.origin + (n0.origin - n1.origin) * (-f * 2.0), PackedFloat32Array([ns - 1, -f * 2.0, B_NECK0, 1.0 + f * 2.0])]
		if f < 0.5:
			var k0 := f * 2.0
			return [n0.origin.lerp(n1.origin, k0), PackedFloat32Array([ns - 1, maxf(0.0, 0.35 - k0), B_NECK0, 1.0 - k0, B_NECK1, k0])]
		var k1 := clampf((f - 0.5) * 2.0, 0.0, 1.5)
		return [n1.origin.lerp(hp, k1), PackedFloat32Array([B_NECK1, maxf(0.0, 1.0 - k1), B_HEAD, minf(k1, 1.0)])]

	## Lowest point of the posed torso samples (model space) or INF.
	func _torso_low() -> float:
		var low := INF
		var mats := {}
		for i in torso_pts.size():
			var b: PackedFloat32Array = torso_binds[i]
			var p := Vector3.ZERO
			var k := 0
			while k + 1 < b.size():
				var bone := int(b[k])
				if not mats.has(bone):
					mats[bone] = xf[bone] * rest[bone].affine_inverse()
				p += ((mats[bone] as Transform3D) * torso_pts[i]) * b[k + 1]
				k += 2
			low = minf(low, p.y)
		return low

	## Extra bone (mane locks, bristles...) with its rest frame; returns its index. Call before attach().
	func add_extra(rest_xf: Transform3D) -> int:
		xf.append(rest_xf)
		rest.append(rest_xf)
		bone_count += 1
		return bone_count - 1

	func reset_channels() -> void:
		ch.fill(0.0)
		ch[EYES] = 1.0
		ch[GLOW] = 1.0
		ch[GAIT] = 1.0

	## Builds the scene: a scaled root with the Skeleton3D, the skinned mesh and the attachment markers.
	func attach(owner: Node3D, data: Array, scale_v: float, box: AABB) -> void:
		rig = owner
		scale_k = scale_v
		root = Node3D.new()
		root.name = "Body"
		root.scale = Vector3.ONE * scale_v
		owner.add_child(root)
		skel = Skeleton3D.new()
		skel.name = "Skeleton"
		for b in bone_count:
			skel.add_bone("b%d" % b)
		root.add_child(skel)
		mesh = MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = data[0]
		mesh.skin = data[1]
		var own: Material = (owner as Rig)._own_material(Materials.lowpoly())
		mesh.material_override = own
		mesh.set_meta(&"own_material", own)
		mesh.custom_aabb = box
		skel.add_child(mesh)
		mesh.skeleton = NodePath("..")
		(owner as Rig).meshes.append(mesh)
		for nm in [&"head", &"muzzle", &"neck", &"chest", &"paw_fl", &"paw_fr", &"paw_hl", &"paw_hr", &"tail_tip", &"hips"]:
			var m := Node3D.new()
			m.name = String(nm)
			root.add_child(m)
			markers[nm] = m
		_vis = VisibleOnScreenNotifier3D.new()
		_vis.aabb = box
		root.add_child(_vis)

	func marker(nm: StringName) -> Node3D:
		return markers.get(nm)

	## Eye halos (Rig.add_glow quads under the head marker, meta "n" = eye normal in head space): intensity k,
	## faded out when the eye looks away from the camera so a halo never shows beside or through the head.
	func update_halos(halos: Array[MeshInstance3D], k: float) -> void:
		if halos.is_empty() or rig == null or not rig.is_inside_tree():
			return
		var cam := rig.get_viewport().get_camera_3d()
		var hb: Basis = (markers[&"head"] as Node3D).global_transform.basis
		for h in halos:
			var f := 1.0
			if cam:
				var n: Vector3 = (hb * Vector3(h.get_meta(&"n"))).normalized()
				var to_cam := (cam.global_position - h.global_position).normalized()
				f = smoothstep(0.05, 0.45, n.dot(to_cam))
			var v := k * f
			if absf(float(h.get_meta(&"k", -1.0)) - v) > 0.01:
				h.set_meta(&"k", v)
				Materials.set_param(h, &"intensity", v)

	# --- per frame ---------------------------------------------------------------------------------------

	## Starts a frame: measures how the rig moves (direction, turning), advances the gait and returns `ch`
	## reset to neutral for the rig to fill.
	func begin(dt: float) -> PackedFloat32Array:
		t += dt
		reset_channels()
		if rig and rig.is_inside_tree() and dt > 0.0:
			var gx := rig.global_transform
			var yaw := atan2(-gx.basis.z.x, -gx.basis.z.z)
			if _has_last:
				var dp := gx.origin - _last_pos
				dp.y = 0.0
				var dyaw := wrapf(yaw - _last_yaw, -PI, PI)
				if dp.length() < 2.0:
					var lv := gx.basis.inverse() * (dp / dt)
					lv.y = 0.0
					if lv.length() > 0.4:
						_meas_dir = _meas_dir.lerp(lv.normalized(), 1.0 - exp(-dt * 8.0)).normalized()
					else:
						_meas_dir = _meas_dir.lerp(Vector3(0, 0, -1), 1.0 - exp(-dt * 3.0)).normalized()
				if absf(dyaw) < 1.0:
					yaw_rate = lerpf(yaw_rate, dyaw / dt, 1.0 - exp(-dt * 8.0))
			_has_last = true
			_last_pos = gx.origin
			_last_yaw = yaw
		var rig_r: Rig = rig as Rig
		speed_in = rig_r.speed if rig_r else 0.0
		_gait(dt)
		look_w = move_toward(look_w, look_w_target, dt * 2.5)
		# ear twitches
		_ear_timer -= dt
		if _ear_timer <= 0.0 and twitch:
			_ear_timer = randf_range(1.5, 4.5)
			_ear_twitch = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.35
		_ear_twitch = _ear_twitch.lerp(Vector2.ZERO, 1.0 - exp(-dt * 3.0))
		return ch

	func _gait(dt: float) -> void:
		spd = lerpf(spd, maxf(speed_in, speed_floor), 1.0 - exp(-dt * 6.0))
		# gait selection with hysteresis, from where the speed is going (an accelerating beast changes gait
		# early instead of over-striding in the slower gait)
		var want := 0
		var sel := maxf(spd, maxf(speed_in, speed_floor) * 0.9)
		for k in gait_up.size():
			var thr := gait_up[k] + (0.3 if gait_i <= k else -0.3)
			if sel > thr:
				want = k + 1
		if want != gait_i:
			_g_from = g.duplicate()
			gait_i = want
			_g_k = 0.0
		if _g_k < 1.0:
			_g_k = minf(1.0, _g_k + dt / 0.35)
			var kk := _g_k * _g_k * (3.0 - 2.0 * _g_k)
			var to: Dictionary = gaits[gait_i]
			for key in to:
				var a: Variant = _g_from.get(key, to[key])
				if a is float:
					g[key] = lerpf(a, to[key], kk)
				elif a is Array:
					var arr: Array = []
					for j in (a as Array).size():
						arr.append(lerpf(float(a[j]), float(to[key][j]), kk))
					g[key] = arr
		else:
			g = (gaits[gait_i] as Dictionary).duplicate()
		var turn := absf(yaw_rate) * 0.5
		var drive := spd + turn
		walk = lerpf(walk, clampf((drive - 0.08) / 0.35, 0.0, 1.0), 1.0 - exp(-dt * 8.0))
		var ref: float = g["speed"]
		var freq: float = g["freq"] * pow(clampf(maxf(drive, ref * 0.35) / ref, 0.2, 3.0), 0.4) * cadence_k
		var duty: float = g["duty"]
		move_dir = _meas_dir
		var v := move_dir * spd
		# sideways steps (strafing, turning) must not cross the legs: quicker, shorter steps
		var lat := 0.0
		for i in 4:
			var r0 := leg_neutral[i]
			var ux := absf(v.x + yaw_rate * r0.z) * duty / freq
			lat = maxf(lat, ux / maxf(absf(r0.x) * 0.8, 0.05))
		if lat > 1.0:
			freq = minf(freq * lat, float(g["freq"]) * 2.6)
		# never longer strides than the legs can sweep
		var ms: float = spec.get("max_stance", 0.6)
		freq = maxf(freq, minf(drive * duty / ms, float(g["freq"]) * 2.2))
		phase = fposmod(phase + freq * dt * walk, 1.0)
		var stance_t := duty / freq
		var track_f: float = g.get("track_f", 0.0)
		var track_h: float = g.get("track_h", 0.0)
		var zoff_f: float = g.get("zoff_f", 0.0)
		var zoff_h: float = g.get("zoff_h", 0.0)
		# a sidestepping / turning beast widens its stance (spec "turn_widen", "widen_max" for broad beasts)
		var widen := clampf(absf(v.x) * 0.07 + absf(yaw_rate) * float(spec.get("turn_widen", 0.012)), 0.0, float(spec.get("widen_max", 0.07)))
		var offs: Array = g["off"]
		var lift: float = g["lift"] * float(spec.get("lift_scale", 1.0))
		var flex_a: float = g["flex"]
		for i in 4:
			var u := fposmod(phase + float(offs[i]), 1.0)
			var r := leg_neutral[i]
			var w_cross := Vector3(yaw_rate * r.z, 0.0, -yaw_rate * r.x)
			var uvel := -(v + w_cross)
			var dvec := uvel * stance_t
			# hard limit (a foot that would sweep further slides a little instead of overreaching the other legs)
			if dvec.length() > ms * 1.08:
				dvec = dvec.normalized() * ms * 1.08
			var off := Vector3.ZERO
			var fl := 0.0
			var st := 1.0
			if u < duty:
				var s := u / duty
				off = dvec * (s - 0.5)
				fl = -smoothstep(0.75, 1.0, s) * 0.25 * flex_a
				st = 1.0
				if _was_stance[i] == 0:
					_was_stance[i] = 1
					if walk > 0.35 and steps_enabled and rig:
						rig.emit_signal(&"event", "step")
			else:
				_was_stance[i] = 0
				var s2 := (u - duty) / (1.0 - duty)
				var e := s2 * s2 * (3.0 - 2.0 * s2)
				off = dvec * (0.5 - e)
				off.y = sin(PI * pow(s2, 0.8)) * lift
				# the swinging foot arcs slightly outwards, clear of the planted one
				off.x += leg_side[i] * sin(PI * s2) * (0.016 if i < 2 else 0.03)
				fl = -sin(PI * minf(1.0, s2 * 1.25)) * flex_a
				st = 0.0
			off.x += leg_side[i] * ((track_f if i < 2 else track_h) + widen)
			off.z += zoff_f if i < 2 else zoff_h
			gait_off[i] = off * walk
			gait_flex[i] = fl * walk
			plant[i] = lerpf(plant[i], st, 1.0 - exp(-dt * 25.0)) if walk > 0.05 else 1.0

	## Gait body motion (bob, rocking, spine flex), turning dynamics and the look-at, added into `ch`.
	func _gait_body(gw: float) -> void:
		var bm: float = g["bob_m"]
		var ph := TAU * (phase * bm - float(g["bob_ph"]))
		var k := walk * gw
		ch[Y_REAR] += cos(ph) * float(g["bob"]) * k
		ch[Y_FRONT] += cos(ph - TAU * 0.12 * bm) * float(g["bob"]) * k + sin(TAU * phase) * float(g["pitch"]) * k
		ch[Y_REAR] -= sin(TAU * phase) * float(g["pitch"]) * k * 0.5
		ch[FLEX] += cos(TAU * (phase - 0.95)) * float(g["spine"]) * k
		ch[ROLL] += sin(TAU * phase) * float(g["roll"]) * k
		ch[HEAD_P] += sin(ph + 0.6) * float(g["head"]) * k
		# turning: spine curves into the turn, body leans in, head leads
		var yr := clampf(yaw_rate, -4.0, 4.0) * gw
		ch[BEND] += yr * 0.022
		ch[ROLL] += yr * spd * 0.012
		ch[NECK_Y] += yr * 0.09
		ch[TAIL_Y] -= yr * 0.12
		# speed: lower head and longer body at a gallop
		var fast := clampf((spd - 3.0) / 5.0, 0.0, 1.0) * gw
		ch[NECK_P] -= fast * 0.35
		ch[HEAD_P] += fast * 0.25
		ch[EARS] -= fast * 0.8
		ch[TAIL_P] += fast * 0.25
		ch[Y_FRONT] -= fast * 0.025

	func _look() -> void:
		if look_w <= 0.001 or rig == null or not rig.is_inside_tree():
			_look_y = lerpf(_look_y, 0.0, 0.1)
			_look_p = lerpf(_look_p, 0.0, 0.1)
		else:
			var inv := (root.global_transform * xf[B_NECK0]).affine_inverse()
			var l := inv * look_target
			var yaw := clampf(atan2(-l.x, -l.z), -1.3, 1.3)
			var flat := Vector2(l.x, l.z).length()
			var pit := clampf(atan2(l.y, flat), -0.6, 0.6)
			_look_y = lerpf(_look_y, yaw * look_w, 0.15)
			_look_p = lerpf(_look_p, pit * look_w, 0.15)
		ch[NECK_Y] += _look_y * 0.55
		ch[HEAD_Y] += _look_y * 0.45
		ch[HEAD_P] += _look_p * 0.6

	## Evaluates the rig's current action (keyed offsets + proc.call(name, p, t, w) for its procedural part,
	## events at their time, once per cycle for loops), the held last pose when dead, and the fading previous
	## action. actions: name -> [length, loop, {channel: keys}, {event: time fraction}].
	func run_actions(r: Rig, actions: Dictionary, dead: bool, proc: Callable, dt: float) -> void:
		if r.action != "" and actions.has(r.action):
			var def: Array = actions[r.action]
			var len := float(def[0])
			var loop := bool(def[1])
			var p := fposmod(r.action_t / len, 1.0) if loop else clampf(r.action_t / len, 0.0, 1.0)
			apply_keys(def[2], p, loop_in(r.action_t) if loop else 1.0)
			proc.call(r.action, p, r.action_t, loop_in(r.action_t) if loop else 1.0)
			var evs: Dictionary = def[3]
			# event keys may carry a suffix ("scrape#2") so one action can emit the same event twice
			var cyc := int(floor(r.action_t / len)) if loop else 0
			for ev in evs:
				var at := (float(cyc) + float(evs[ev])) * len
				var key := "%s@%d" % [ev, cyc]
				if r.action_t >= at and not r._fired.has(key):
					r._fired[key] = true
					r.event.emit(String(ev).get_slice("#", 0))
		elif dead and actions.has("death"):
			var dd: Array = actions["death"]
			apply_keys(dd[2], 1.0, 1.0)
			proc.call("death", 1.0, float(dd[0]), 1.0)
		var pw := prev_weight(dt)
		if pw > 0.0:
			var pd: Array = prev_def
			var plen := float(pd[0])
			var pp := fposmod(prev_t / plen, 1.0) if bool(pd[1]) else clampf(prev_t / plen, 0.0, 1.0)
			apply_keys(pd[2], pp, pw)
			proc.call(prev_action, pp, prev_t, pw)

	## Loops ease in over their first 0.2 s.
	static func loop_in(at: float) -> float:
		var k := clampf(at / 0.2, 0.0, 1.0)
		return k * k * (3.0 - 2.0 * k)

	## Adds an action's keyed offsets at progress p (0..1), weighted by w.
	func apply_keys(keys: Dictionary, p: float, w: float) -> void:
		for c in keys:
			ch[c] += kf(keys[c], p) * w

	static func kf(k: PackedFloat32Array, p: float) -> float:
		var n := k.size() / 3
		if n == 0:
			return 0.0
		if p <= k[0]:
			return k[1]
		for i in range(1, n):
			var t1 := k[i * 3]
			if p <= t1:
				var t0 := k[i * 3 - 3]
				var v0 := k[i * 3 - 2]
				var v1 := k[i * 3 + 1]
				var u := (p - t0) / maxf(t1 - t0, 1e-5)
				match int(k[i * 3 + 2]):
					1:
						u = 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)
					2:
						u = u * u * u
					3:
						pass
					_:
						u = u * u * (3.0 - 2.0 * u)
				return lerpf(v0, v1, u)
		return k[n * 3 - 2]

	## The previous action keeps playing (fading out over `fade` s) after a new one starts or a loop stops.
	func push_prev(a: String, at: float, def: Array, fade: float = 0.16) -> void:
		if a == "" or def.is_empty():
			return
		prev_action = a
		prev_t = at
		prev_def = def
		_prev_w = 1.0
		_prev_fade = fade

	var _prev_fade := 0.16

	func prev_weight(dt: float) -> float:
		if _prev_w <= 0.0:
			return 0.0
		_prev_w = maxf(0.0, _prev_w - dt / _prev_fade)
		if not bool(prev_def[1]):
			prev_t = minf(prev_t + dt, float(prev_def[0]))
		else:
			prev_t += dt
		var w := _prev_w
		return w * w * (3.0 - 2.0 * w)

	# --- solver ------------------------------------------------------------------------------------------

	static func _pitch_of(b: Basis) -> float:
		var f := -b.z
		return atan2(f.y, Vector2(f.x, f.z).length())

	static func _yaw_of(b: Basis) -> float:
		return atan2(-b.z.x, -b.z.z)

	static func seg_frame(top: Vector3, bottom: Vector3, lat: Vector3) -> Basis:
		var y := (top - bottom).normalized()
		var x := (lat - y * lat.dot(y))
		if x.length_squared() < 1e-8:
			x = Vector3.RIGHT
		x = x.normalized()
		return Basis(x, y, x.cross(y))

	static func ik2(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
		var d := target - a
		var dist := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.0005)
		var dir := d.normalized() if d.length_squared() > 1e-10 else Vector3.DOWN
		var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
		var sa := sqrt(1.0 - ca * ca)
		var p := pole - dir * pole.dot(dir)
		if p.length_squared() < 1e-8:
			p = Vector3.FORWARD
		p = p.normalized()
		return a + dir * (l1 * ca) + p * (l1 * sa)

	func _solve_spine() -> void:
		var c := ch
		var rear := hip0 + Vector3(c[X_SHIFT], c[Y_REAR], c[Z_SHIFT])
		var A := spine_v.y
		var B := -spine_v.z
		var R := sqrt(A * A + B * B)
		var front_dy := (chest0.y + c[Y_FRONT]) - rear.y
		var pitch := asin(clampf(front_dy / R, -0.97, 0.97)) - atan2(A, B)
		var bb := Basis(Vector3.UP, c[YAW]) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, c[ROLL])
		var front := rear + bb * spine_v
		var up := bb.y
		var right := bb.x
		var d := front - rear
		var bend_v := up * c[FLEX] + right * c[BEND]
		for k in ns:
			var s := spine_s[k]
			var bump := 4.0 * s * (1.0 - s)
			var pos := rear + d * s + bend_v * bump
			var tg := d + bend_v * (4.0 - 8.0 * s)
			var z := -tg.normalized()
			var x := up.cross(z).normalized()
			var bs := Basis(x, z.cross(x), z)
			xf[k] = Transform3D(bs, pos)

	func solve(dt: float) -> void:
		var gw := clampf(ch[GAIT], 0.0, 1.0)
		if not _resting:
			_gait_body(gw)
			_look()
			_terrain(gw)
		var c := ch
		_solve_body(c)
		for i in 4:
			_solve_leg(i, gw)
		# the body never sinks into the ground: lift the whole spine onto it (death, crouches, staggers) and
		# solve the body and the legs again
		if not _resting and not torso_pts.is_empty():
			var gmin := minf(minf(_ground_h[0], _ground_h[1]), minf(_ground_h[2], _ground_h[3])) + 0.008
			var low := _torso_low() if _clamp_bound() < gmin else INF
			if low < gmin:
				c[Y_REAR] += gmin - low
				c[Y_FRONT] += gmin - low
				_solve_body(c)
				for i in 4:
					_solve_leg(i, gw)
		# tail
		_solve_tail(dt)

	## Spine (+ breathing), neck, head (+ its ground clamp), eyelids and ears from the channels in `c`.
	func _solve_body(c: PackedFloat32Array) -> void:
		_solve_spine()
		# breathing: the rib cage swells
		var br := 1.0 + c[BREATH]
		for k in [ns - 1, ns - 2]:
			xf[k] = Transform3D(xf[k].basis * Basis.from_scale(Vector3(br, br, 1.0)), xf[k].origin)
		# neck and head
		var chest := xf[ns - 1]
		var cp := (_pitch_of(chest.basis) - _chest_rest_pitch) * c[STAB]
		var nb0 := chest * neck_base_local
		var b0 := chest.basis * Basis(Vector3.UP, c[NECK_Y] * 0.5) * Basis(Vector3.RIGHT, neck_pitch + (c[NECK_P] - cp) * 0.5)
		b0 = b0.orthonormalized()
		xf[B_NECK0] = Transform3D(b0, nb0)
		var p1 := nb0 + (-b0.z) * (neck_len * 0.5)
		var b1 := (chest.basis * Basis(Vector3.UP, c[NECK_Y]) * Basis(Vector3.RIGHT, neck_pitch + c[NECK_P] - cp)).orthonormalized()
		xf[B_NECK1] = Transform3D(b1, p1)
		var hp := p1 + (-b1.z) * (neck_len * 0.5)
		var hb := b1 * Basis(Vector3.UP, c[HEAD_Y]) * Basis(Vector3.RIGHT, head_rel + c[HEAD_P]) * Basis(Vector3.BACK, c[HEAD_R])
		head_xf = Transform3D(hb, hp)
		# keep the head above the ground: swing the neck up as much as needed (biting low, lying dead)
		if _head_reach < 0.0 and not head_pts.is_empty():
			_head_reach = 0.0
			for hpt in head_pts:
				_head_reach = maxf(_head_reach, hpt.length())
		# (skipped while the whole head is higher than its own reach above the ground: the usual case)
		if not _resting and not head_pts.is_empty() and head_xf.origin.y - _head_reach * 1.05 < maxf(minf(_ground_h[0], _ground_h[1]), ground_at(head_xf.origin)) + 0.02:
			# ground under the head: the higher of the pivot's and the muzzle's (uphill), or the front feet's
			_head_ground = minf(_ground_h[0], _ground_h[1])
			if _has_ground:
				_head_ground = maxf(ground_at(head_xf.origin), ground_at(head_xf * muzzle_local))
			var gmin := _head_ground + 0.012
			for it in 5:
				var low := INF
				var lowp := Vector3.ZERO
				for hpt in head_pts:
					var wp := head_xf * hpt
					if wp.y < low:
						low = wp.y
						lowp = wp
				if low >= gmin:
					break
				# pitch the neck up about the horizontal axis across it (from the head pivot's direction, never from
				# the low point's: a point far to the side, like a lion's ruff, would turn this into a roll)
				var ndir := (lowp - nb0)
				var hdir := hp - nb0
				var axis := hdir.cross(Vector3.UP)
				if axis.length_squared() < 1e-6:
					break
				axis = axis.normalized()
				var arm := maxf(Vector2(ndir.x, ndir.z).length(), 0.1)
				var ang := clampf((gmin - low) / arm * 1.1, 0.0, 0.8)
				var rot := Basis(axis, ang)
				b0 = (rot * b0).orthonormalized()
				b1 = (rot * b1).orthonormalized()
				xf[B_NECK0] = Transform3D(b0, nb0)
				p1 = nb0 + rot * (p1 - nb0)
				xf[B_NECK1] = Transform3D(b1, p1)
				hp = nb0 + rot * (hp - nb0)
				head_xf = Transform3D((rot * head_xf.basis).orthonormalized(), hp)
		xf[B_HEAD] = head_xf
		xf[B_EYES] = head_xf * Transform3D(Basis.from_scale(Vector3(1.0, clampf(c[EYES], 0.04, 1.2), 1.0)), eye_local)
		for s in 2:
			var tw := _ear_twitch.x if s == 0 else _ear_twitch.y
			var e := clampf(c[EARS] + tw * (1.0 - absf(c[EARS]) * 0.5), -1.6, 1.0)
			var sd := -1.0 if s == 0 else 1.0
			var eb := Basis(Vector3.RIGHT, -e * 0.55) * Basis(Vector3.BACK, sd * minf(e, 0.0) * 0.35)
			xf[B_EAR_L + s] = head_xf * ear_local[s] * Transform3D(eb, Vector3.ZERO)
			# an ear never digs into the ground: swing it up about its base until the tip clears
			if not _resting:
				var ex := xf[B_EAR_L + s]
				var gy := _head_ground + 0.02
				for it in 3:
					var tip := ex * Vector3(0, ear_h, 0)
					if tip.y >= gy:
						break
					var ax := (tip - ex.origin).cross(Vector3.UP)
					if ax.length_squared() < 1e-6:
						break
					var ang := asin(clampf((gy - tip.y) / ear_h, 0.0, 1.0)) * 1.1
					ex = Transform3D((Basis(ax.normalized(), ang) * ex.basis).orthonormalized(), ex.origin)
				xf[B_EAR_L + s] = ex

	## Ground height (model space) under a model-space point: the terrain when ground_fn is set, else 0.
	func ground_at(p: Vector3) -> float:
		if not _has_ground:
			return 0.0
		var wp := _gx * Vector3(p.x, 0.0, p.z)
		var h: float = ground_fn.call(wp.x, wp.z)
		return clampf((_gx_inv * Vector3(wp.x, h, wp.z)).y, -2.0, 2.0)

	## Terrain normal (model space) under a model-space point.
	func ground_normal(p: Vector3) -> Vector3:
		if not _has_ground:
			return Vector3.UP
		var wp := _gx * Vector3(p.x, 0.0, p.z)
		var e := 0.12
		var h0: float = ground_fn.call(wp.x, wp.z)
		var hx: float = ground_fn.call(wp.x + e, wp.z)
		var hz: float = ground_fn.call(wp.x, wp.z + e)
		return (_gx.basis.inverse() * Vector3(h0 - hx, e, h0 - hz)).normalized()

	func _terrain(gw: float = 1.0) -> void:
		_ground_h.fill(0.0)
		_has_ground = false
		if not ground_fn.is_valid() or root == null or not root.is_inside_tree():
			return
		var gx := root.global_transform
		var inv := gx.affine_inverse()
		_has_ground = true
		_gx = gx
		_gx_inv = inv
		for i in 4:
			# under the foot where it is this frame (a planted foot at the end of its stride, downhill, is lower)
			var fp := leg_neutral[i] + Vector3(gait_off[i].x, 0.0, gait_off[i].z) * gw
			var wp := gx * fp
			var h: float = ground_fn.call(wp.x, wp.z)
			var lp := inv * Vector3(wp.x, h, wp.z)
			_ground_h[i] = clampf(lp.y, -1.0, 1.0)
		# each end of the body sits nearer its lower foot (cross-slopes): the downhill leg can still reach the
		# ground, the uphill one flexes
		var lowk: float = spec.get("slope_low", 0.6)
		var front := lerpf((_ground_h[0] + _ground_h[1]) * 0.5, minf(_ground_h[0], _ground_h[1]), lowk)
		var hind := lerpf((_ground_h[2] + _ground_h[3]) * 0.5, minf(_ground_h[2], _ground_h[3]), lowk)
		ch[Y_FRONT] += front
		ch[Y_REAR] += hind

	func _solve_leg(i: int, gw: float) -> void:
		var c := ch
		var front := i < 2
		var sb := xf[ns - 1] if front else xf[0]
		var o := LEG + i * LEG_N
		var rel := clampf(c[o + LREL], 0.0, 1.0)
		var off := Vector3(c[o + LX], c[o + LY], c[o + LZ])
		var target := leg_neutral[i] + off + gait_off[i] * gw
		# the ground under where this foot actually goes (a striding foot is far from its neutral spot on a slope)
		var gnd := ground_at(target) if _has_ground and not _resting else _ground_h[i]
		target.y += gnd
		if rel > 0.0:
			var ri := _rest_inv_front if front else _rest_inv_hind
			var rt := sb * (ri * (leg_neutral[i] + off))
			target = target.lerp(rt, rel)
			if _has_ground and not _resting:
				gnd = ground_at(target)
		target.y = maxf(target.y, gnd)
		var upv := Vector3.UP.lerp(sb.basis.y, rel).normalized()
		var bk := sb.basis.z - upv * sb.basis.z.dot(upv)
		bk = bk.normalized()
		var l := leg_l[i]
		var F := target + upv * paw_h[i]
		# a body-relative paw (falling, lying) may turn on its side: keep its half-width (spec "paw_r") clear too
		var pr := maxf(paw_h[i], float(spec.get("paw_r", 0.0)))
		F.y = maxf(F.y, gnd + lerpf(paw_h[i], pr, rel) + 0.06 * rel)
		var th := leg_theta[i] + c[o + LFLEX] + gait_flex[i] * gw
		# the shoulder blade / pelvis swing with the leg (more reach at the ends of a stride)
		var slide := clampf(gait_off[i].z * gw * (0.22 if front else 0.12), -0.07, 0.07)
		var A := sb * (leg_anchor[i] + Vector3(0, 0, slide))
		var W := F + (upv * cos(th) + bk * sin(th)) * l.z
		# out of reach: roll the pastern / metatarsus (heel lifts, toes stay down) before the paw leaves the ground
		var reach := (l.x + l.y) * 0.995
		if not _resting and W.distance_to(A) > reach:
			var D := A - F
			var du := D.dot(upv)
			var db := D.dot(bk)
			var rho := sqrt(du * du + db * db)
			if rho > 1e-5:
				var K := (l.z * l.z + D.length_squared() - reach * reach) / (2.0 * l.z)
				var phi := atan2(db, du)
				var th2 := phi
				if absf(K / rho) <= 1.0:
					var ac := acos(K / rho)
					th2 = phi + ac if absf(phi + ac - th) < absf(phi - ac - th) else phi - ac
				th = clampf(th2, leg_theta[i] - 1.3, leg_theta[i] + 1.5)
				W = F + (upv * cos(th) + bk * sin(th)) * l.z
		var pole := (bk if front else -bk) + sb.basis.x * (0.3 * leg_side[i])
		var M := ik2(A, W, l.x, l.y, pole)
		# where the IK could not reach, the lower segments follow
		var wreal := M + (W - M).normalized() * l.y
		var freal := F + (wreal - W)
		var lat := sb.basis.x
		var bi0 := B_LEG + i * 4
		xf[bi0] = Transform3D(seg_frame(A, M, lat), A)
		xf[bi0 + 1] = Transform3D(seg_frame(M, wreal, lat), M)
		xf[bi0 + 2] = Transform3D(seg_frame(wreal, freal, lat), wreal)
		# the paw follows the swinging leg only once it is clear of the ground (else its toes would dig in)
		var clear := smoothstep(0.0, maxf(0.05, paw_h[i] * 1.3), freal.y - paw_h[i] - gnd)
		var follow_k := 1.0 if _resting else clampf((1.0 - plant[i]) * gw * clear + rel, 0.0, 1.0)
		var flat := Basis(Vector3.UP, _yaw_of(sb.basis))
		# a planted paw lies on the slope (heel and toes on the ground)
		if _has_ground and not _resting:
			var nrm := ground_normal(freal)
			var ang := Vector3.UP.angle_to(nrm)
			if ang > 0.01:
				flat = Basis(Vector3.UP.cross(nrm).normalized(), minf(ang, 0.6)) * flat
		var pb := flat
		if follow_k > 0.001 and not _resting:
			var fol := (xf[bi0 + 2].basis * _paw_rel[i]).orthonormalized()
			pb = flat.slerp(fol, follow_k)
		if _resting:
			pb = Basis.IDENTITY
		xf[bi0 + 3] = Transform3D(pb, freal)
		var jj := joints[i]
		jj[0] = A
		jj[1] = M
		jj[2] = wreal
		jj[3] = freal
		joints[i] = jj

	func _solve_tail(dt: float) -> void:
		var c := ch
		var pel := xf[0]
		var p := pel * tail_root
		tail_pts[0] = p
		# secondary motion: the tail lags behind turns and bounces with the body
		if not _resting and dt > 0.0:
			_tail_lag = _tail_lag.lerp(Vector2(-yaw_rate * 0.12, 0.0), 1.0 - exp(-dt * 4.0))
		var sway_t := t * (2.2 + c[TAIL_SWAY] * 3.0)
		var x_ref := pel.basis.x
		var yaw0 := c[TAIL_Y] + _tail_lag.x + (sin(sway_t + idle_seed) * c[TAIL_SWAY] if not _resting else 0.0)
		var pitch0 := tail_pitch + c[TAIL_P] + _tail_lag.y
		var dirs := PackedVector3Array()
		for k in tail_n:
			var pk := pitch0 + (tail_curl + c[TAIL_CURL]) * float(k)
			var yk := yaw0
			if not _resting:
				yk += sin(sway_t - float(k) * 0.6 + idle_seed) * c[TAIL_SWAY] * 0.5 * float(k) / float(tail_n)
			var d := pel.basis * (Basis(Vector3.UP, yk) * Vector3(0, sin(pk), cos(pk)))
			# keep above the ground (the last segment also carries the tip ornament, spec "tail_tip": [length, radius])
			var r := tail_r[mini(k + 1, tail_r.size() - 1)] + 0.025
			var seg := tail_seg
			if k == tail_n - 1 and _tail_tip.x > 0.0:
				seg += _tail_tip.x
				r = maxf(r, _tail_tip.y + 0.02)
			# the ground under the END of this segment (on a slope rising behind the beast it is higher than at
			# its start)
			var gnd := 0.0
			if _has_ground and not _resting:
				gnd = maxf(ground_at(p), ground_at(p + d * seg))
			var ny := p.y + d.y * seg
			if ny < r + gnd:
				var dy := clampf((r + gnd - p.y) / seg, -1.0, 1.0)
				var hz := Vector2(d.x, d.z)
				var hl := hz.length()
				var nh := sqrt(maxf(0.0, 1.0 - dy * dy))
				if hl > 1e-5:
					hz = hz / hl * nh
				else:
					hz = Vector2(0, nh)
				d = Vector3(hz.x, dy, hz.y)
			dirs.append(d)
			p += d * tail_seg
			tail_pts[k + 1] = p
		var x := x_ref
		for k in tail_n:
			var d2 := dirs[k]
			# joints average the two segment directions (smooth bends); the last bone keeps its own, clamped
			# direction so a rigid tip ornament (the lion's tuft) stays where the ground clamp put it
			if k > 0 and k < tail_n - 1:
				d2 = (dirs[k] + dirs[k - 1]).normalized()
			x = (x - d2 * x.dot(d2))
			if x.length_squared() < 1e-6:
				x = Vector3.RIGHT
			x = x.normalized()
			var bs := Basis(x, d2.cross(x), d2)
			xf[B_TAIL + k] = Transform3D(bs, tail_pts[k])

	## Pushes the pose to the markers (always: encounters aim bites and hits with them even when the beast is
	## behind the camera) and to the skeleton (skipped off screen unless always_pose).
	func apply() -> void:
		if skel == null:
			return
		if not _posed or always_pose or _vis == null or not rig.is_inside_tree() or _vis.is_on_screen():
			_posed = true
			for b in bone_count:
				skel.set_bone_pose(b, xf[b])
		(markers[&"head"] as Node3D).transform = head_xf
		(markers[&"muzzle"] as Node3D).transform = head_xf * Transform3D(Basis.IDENTITY, muzzle_local)
		(markers[&"neck"] as Node3D).transform = xf[B_NECK1]
		(markers[&"chest"] as Node3D).transform = xf[ns - 1] * Transform3D(Basis.IDENTITY, Vector3(0, -0.05, -0.08))
		(markers[&"hips"] as Node3D).transform = xf[0]
		for i in 4:
			(markers[PAW_NAMES[i]] as Node3D).transform = xf[B_LEG + i * 4 + 3]
		(markers[&"tail_tip"] as Node3D).position = tail_pts[tail_n]

	## Capsule cores of every part, from the construction tables: Array of {part, a, b (rest model space),
	## wa, wb (bone weights of each end), r}. part: "torso", "neck", "head", "leg<i>_<seg>" (seg 0 upper,
	## 1 mid, 2 low, 3 paw), "tail<k>", plus whatever a rig appends (mane, tusks...). Radii are shrunk to
	## the solid core so touching surfaces do not count, only real passes through.
	func volumes(torso: Array, neck: Array, head: Array, leg_f: Array, leg_h: Array, paw_rows: Array, tail_radii: Array, core: float = 0.8, skull: bool = true) -> Array:
		var out: Array = []
		var z_end := float(torso[0][0])
		var first := true
		for k in torso.size() - 1:
			var r0: Array = torso[k]
			var r1: Array = torso[k + 1]
			var r := minf(minf(float(r0[2]), minf(float(r0[3]), float(r0[4]))), minf(float(r1[2]), minf(float(r1[3]), float(r1[4]))))
			if r < 0.04:
				continue
			var a := Vector3(0, r0[1], r0[0])
			var b := Vector3(0, r1[1], r1[0])
			if first:
				# the core's rounded end must not stick out behind the real rump
				first = false
				a.z = minf(a.z, maxf(z_end - r * core, b.z))
			out.append({"part": "torso", "a": a, "b": b,
				"wa": spine_bind(a.z), "wb": spine_bind(float(r1[0])), "r": r * core})
		var n0 := rest[B_NECK0].origin
		var hp := rest[B_HEAD].origin
		var nr := float(neck[0][1])
		for row in neck:
			nr = minf(nr, minf(float(row[1]), minf(float(row[2]), float(row[3]))) if float(row[0]) <= 1.0 else nr)
		out.append({"part": "neck", "a": n0, "b": hp, "wa": PackedFloat32Array([B_NECK0, 1.0]),
			"wb": PackedFloat32Array([B_NECK1, 0.5, B_HEAD, 0.5]), "r": nr * core})
		# head: from the back of the skull to the muzzle, radius of the muzzle
		var hx := rest[B_HEAD]
		var hz0 := float(head[1][0]) if skull else float(head[head.size() / 2][0])
		var hz1 := float(head[head.size() - 2][0])
		var hr := minf(float(head[head.size() - 3][2]), float(head[head.size() - 3][3]))
		var hm := PackedFloat32Array([B_HEAD, 1.0])
		out.append({"part": "head", "a": hx * Vector3(0, float(head[2][1]), hz0), "b": hx * Vector3(0, float(head[head.size() - 2][1]), hz1),
			"wa": hm, "wb": hm, "r": hr * core})
		if skull:
			var skull_r := minf(float(head[2][2]), minf(float(head[2][3]), float(head[2][4])))
			out.append({"part": "head", "a": hx * Vector3(0, float(head[2][1]), float(head[2][0])), "b": hx * Vector3(0, float(head[4][1]), float(head[4][0])),
				"wa": hm, "wb": hm, "r": skull_r * core})
		for i in 4:
			var rad: Array = leg_f if i < 2 else leg_h
			var j: PackedVector3Array = rest_joints[i]
			for sgi in 3:
				var ra: Vector2 = rad[sgi * 2]
				var rb: Vector2 = rad[sgi * 2 + 2]
				var rr := minf(minf(ra.x, ra.y), minf(rb.x, rb.y))
				var bw := PackedFloat32Array([B_LEG + i * 4 + sgi, 1.0])
				out.append({"part": "leg%d_%d" % [i, sgi], "a": j[sgi], "b": j[sgi + 1], "wa": bw, "wb": bw, "r": rr * core})
			var pr: Array = paw_rows[1]
			var pb := PackedFloat32Array([B_LEG + i * 4 + 3, 1.0])
			var pf: Array = paw_rows[0]
			var pt: Array = paw_rows[paw_rows.size() - 1]
			out.append({"part": "leg%d_3" % i, "a": j[3] + Vector3(0, pf[1], pf[0]), "b": j[3] + Vector3(0, pt[1], pt[0]),
				"wa": pb, "wb": pb, "r": minf(float(pr[2]), float(pr[3])) * core})
		for k in tail_n:
			var ta: float = tail_radii[k]
			var tb: float = tail_radii[mini(k + 1, tail_radii.size() - 1)]
			var tw := PackedFloat32Array([B_TAIL + k, 1.0])
			out.append({"part": "tail%d" % k, "a": rest_tail_pts[k], "b": rest_tail_pts[k + 1], "wa": tw, "wb": tw, "r": minf(ta, tb) * core})
		return out

	## Rest-space spine binding for a torso ring at z (blend of the two nearest spine bones).
	func spine_bind(z: float) -> PackedFloat32Array:
		var z0 := rest[0].origin.z
		if z >= z0:
			return PackedFloat32Array([0, 1.0])
		for k in range(1, ns):
			var zk := rest[k].origin.z
			if z >= zk:
				var f := (z0 - z) / maxf(z0 - zk, 1e-4)
				return PackedFloat32Array([k - 1, 1.0 - f, k, f])
			z0 = zk
		# in front of the chest bone: blend towards the neck base
		var zc := rest[ns - 1].origin.z
		var zn := rest[B_NECK0].origin.z
		var f2 := clampf((zc - z) / maxf(zc - zn, 1e-4), 0.0, 1.0) * 0.6
		return PackedFloat32Array([ns - 1, 1.0 - f2, B_NECK0, f2])
