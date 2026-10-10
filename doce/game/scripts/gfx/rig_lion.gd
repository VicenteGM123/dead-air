class_name RigLion
extends Rig
## NEMEAN LION (bestiary boss): ~3.2 m from nose to rump (+1.1 m of tufted tail), 1.4 m at the withers. Golden
## ochre with a deep brown flowing mane, pale muzzle and belly, heavy paws, amber eyes glowing under a heavy
## brow. Regal and threatening: no teeth and never an open mouth; the roar is the head thrown back and the mane
## flaring out (three spring-driven mane bones lag behind every head move).
##
## Contract (BRIEF "Bestiary rigs"): set_locomotion(speed, max_speed), play(action) -> length.
##   swipe      rears a little, right paw raised high, sweeps forward and across   event impact
##   pounce     crouch (tail lashing), leap, flight, land                            events leap, land, impact (at land)
##              The rig lifts the body along the arc between leap and land; the encounter moves the root
##              horizontally (leap at POUNCE_LEAP s, land at POUNCE_LAND s).
##   roar       head raised and thrown back (chin up, eyes blazing at the target), mane flaring, chest out
##              (mouth closed)                                                     event roar_wave
##   bite       head pulls back then lunges, mouth closed                           event impact
##   stunned    LOOP: dazed, head low and swaying, legs splayed, eyes half shut
##   grappled   LOOP: thrashing while held at the neck (neck() is the hold point)
##   thrash     a violent buck and twist (throws a grappler off)                    event impact
##   spark      quick flinch when a blade bounces off
##   hit, death (collapses onto its side and stays down; event fall)
## Locomotion: walk (~1.5 m/s), trot (~4 m/s), run (~9 m/s); set_stalk(true) / set_alert(1) gives the low,
## deliberate stalk. Extras as RigWolf: set_look_target(), set_hit_dir(), head()/muzzle()/neck()/chest()/paw(i),
## ground_fn, events step. Built with the quadruped kit in rig_wolf.gd.

const Q := RigWolf.Quadruped
const SM := RigWolf.SkinMesh

const COAT := {"gold": Color("B2935A"), "back": Color("9C7C45"), "pale": Color("DCC497"), "muzzle": Color("D6BE90"),
	"nose": Color("6B4136"), "mark": Color("5A3A28"), "mane0": Color("432A1A"), "mane1": Color("4A2D1C"),
	"mane2": Color("63402A"), "tuft": Color("3A2416"), "eye": Color("FFB43A"), "paw": Color("BC9D62"),
	"ear_in": Color("6E4A30"), "ruff": Color("8A5F33")}

const SPEC := {
	"spine_s": [0.0, 0.34, 0.68, 1.0],
	"hip": Vector3(0, 1.02, 0.8),
	"chest": Vector3(0, 1.08, -0.6),
	"neck_base": Vector3(0, 1.22, -0.84),
	"neck_len": 0.52,
	"neck_pitch": 0.42,
	"head_pitch": -0.12,
	"front": [Vector3(-0.25, 0.92, -0.56), Vector3(-0.27, 0.6, -0.4), Vector3(-0.25, 0.22, -0.48), Vector3(-0.25, 0.075, -0.56)],
	"hind": [Vector3(-0.23, 0.98, 0.88), Vector3(-0.28, 0.62, 0.64), Vector3(-0.25, 0.3, 0.98), Vector3(-0.25, 0.075, 0.85)],
	"tail_root": Vector3(0, 1.13, 1.155),
	"tail_n": 8,
	"tail_len": 1.1,
	"tail_pitch": -0.8,
	"tail_curl": 0.16,
	"tail_r": [0.07, 0.06, 0.053, 0.047, 0.043, 0.041, 0.04, 0.04, 0.03],
	"ear": [Vector3(-0.2, 0.25, -0.08), -0.5, -0.35],
	"eye": Vector3(0, 0.15, -0.3),
	"muzzle": Vector3(0, -0.03, -0.62),
	"head_clear": 0.14,
	"lift_scale": 1.0,
	"gaits": [
		{"speed": 1.5, "freq": 0.95, "duty": 0.66, "off": [0.75, 0.25, 0.0, 0.5], "lift": 0.12, "flex": 0.9,
			"bob": 0.02, "bob_m": 2.0, "bob_ph": 0.1, "pitch": 0.008, "spine": 0.0, "roll": 0.035, "head": 0.03,
			"track_f": -0.015, "track_h": 0.1, "zoff_h": 0.06},
		{"speed": 4.0, "freq": 1.6, "duty": 0.46, "off": [0.5, 0.0, 0.0, 0.5], "lift": 0.18, "flex": 1.1,
			"bob": 0.04, "bob_m": 2.0, "bob_ph": 0.15, "pitch": 0.012, "spine": 0.0, "roll": 0.04, "head": 0.04,
			"track_f": -0.06, "track_h": 0.15, "zoff_h": 0.05},
		{"speed": 9.0, "freq": 1.9, "duty": 0.3, "off": [0.45, -0.45, 0.0, 0.9], "lift": 0.28, "flex": 1.4,
			"bob": 0.1, "bob_m": 1.0, "bob_ph": 0.9, "pitch": 0.1, "spine": 0.12, "roll": 0.02, "head": 0.05,
			"track_f": -0.05, "track_h": 0.2, "zoff_f": 0.18, "zoff_h": -0.08},
	],
	"gait_up": [2.6, 6.2],
	"max_stance": 0.8,
	"turn_widen": 0.04,
	"widen_max": 0.12,
	"paw_r": 0.17,
	"slope_low": 0.45,
}

const TORSO := [
	[1.185, 1.02, 0.06, 0.06, 0.06],
	[1.155, 1.02, 0.2, 0.19, 0.2],
	[1.06, 1.02, 0.29, 0.25, 0.29],
	[0.9, 1.02, 0.33, 0.27, 0.33],
	[0.68, 1.03, 0.32, 0.26, 0.28],
	[0.44, 1.04, 0.31, 0.26, 0.25],
	[0.18, 1.05, 0.34, 0.28, 0.33],
	[-0.08, 1.07, 0.37, 0.3, 0.41],
	[-0.34, 1.09, 0.39, 0.32, 0.47],
	[-0.58, 1.11, 0.38, 0.32, 0.45],
	[-0.76, 1.14, 0.33, 0.3, 0.38],
]
const NECK := [[0.06, 0.32, 0.3, 0.36], [0.38, 0.28, 0.27, 0.31], [0.7, 0.25, 0.24, 0.26], [0.98, 0.21, 0.2, 0.21], [1.1, 0.13, 0.13, 0.13]]
## Head (head space, -Z forward, rows [z, y, w, ht, hb]). A broad skull (cheekbones at z ~ -0.08) whose rounded
## front carries the eyes under a heavy frowning brow; a broad, squared muzzle set under the eyes juts forward to
## the nose; a raised bridge runs from between the brows down to the nose pad. The mouth is never modelled: pale
## whisker pads and the chin close the muzzle (no lips, no mouth line, nothing that could read as open).
const SKULL := [
	[0.17, 0.05, 0.08, 0.08, 0.08],
	[0.12, 0.05, 0.22, 0.21, 0.21],
	[0.03, 0.05, 0.29, 0.25, 0.25],
	[-0.08, 0.045, 0.3, 0.25, 0.25],
	[-0.18, 0.04, 0.295, 0.235, 0.235],
	[-0.25, 0.035, 0.27, 0.215, 0.215],
	[-0.29, 0.035, 0.235, 0.185, 0.19],
	[-0.315, 0.04, 0.17, 0.13, 0.14],
]
const MUZZLE := [
	[-0.1, -0.02, 0.17, 0.14, 0.14],
	[-0.26, -0.03, 0.195, 0.15, 0.15],
	[-0.37, -0.035, 0.2, 0.145, 0.14],
	[-0.46, -0.035, 0.195, 0.135, 0.13],
	[-0.53, -0.03, 0.18, 0.12, 0.115],
	[-0.575, -0.025, 0.15, 0.095, 0.09],
	[-0.6, -0.025, 0.085, 0.05, 0.05],
]
const BRIDGE := [
	[-0.2, 0.175, 0.09, 0.06, 0.08],
	[-0.3, 0.16, 0.092, 0.05, 0.08],
	[-0.39, 0.115, 0.092, 0.035, 0.07],
	[-0.47, 0.098, 0.092, 0.028, 0.06],
	[-0.54, 0.088, 0.088, 0.022, 0.05],
	[-0.575, 0.08, 0.072, 0.017, 0.035],
]
## One back-to-front table of the whole head for the kit (Quadruped.head_samples() keeps these points above the
## ground; Quadruped.volumes() reads [1] back z, [2]..[4] skull core, [size-3] muzzle radius, [size-2] muzzle front).
const HEAD := [
	[0.17, 0.05, 0.1, 0.1, 0.1],
	[0.02, 0.05, 0.29, 0.25, 0.25],
	[0.03, 0.05, 0.29, 0.25, 0.25],
	[-0.06, 0.045, 0.3, 0.25, 0.25],
	[-0.12, 0.04, 0.29, 0.24, 0.24],
	[-0.3, 0.02, 0.2, 0.17, 0.19],
	[-0.42, -0.03, 0.195, 0.14, 0.14],
	[-0.52, -0.03, 0.18, 0.12, 0.115],
	[-0.6, -0.025, 0.09, 0.06, 0.06],
]
const LEG_FRONT := [Vector2(0.21, 0.28), Vector2(0.19, 0.24), Vector2(0.165, 0.18), Vector2(0.14, 0.15), Vector2(0.122, 0.13), Vector2(0.112, 0.12), Vector2(0.11, 0.118)]
const LEG_HIND := [Vector2(0.23, 0.36), Vector2(0.2, 0.3), Vector2(0.145, 0.18), Vector2(0.12, 0.135), Vector2(0.105, 0.112), Vector2(0.1, 0.106), Vector2(0.1, 0.106)]
const PAW := [[0.07, -0.005, 0.115, 0.07, 0.07], [-0.02, -0.02, 0.16, 0.085, 0.055], [-0.11, -0.032, 0.165, 0.068, 0.043], [-0.185, -0.047, 0.125, 0.042, 0.028]]
## Eyes (head space): narrow glowing slits on the front of the skull, under the brows, either side of the bridge
## (seated on the surface when the mesh is built; _eye_seat keeps where they landed for the halos).
const EYE_X := 0.14
const EYE_Y := 0.15
const POUNCE_LEN := 2.0
const POUNCE_LEAP := 0.72
const POUNCE_LAND := 1.36

var actions := {}
var coat := COAT
var size_k := 1.0
var q: Q
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
var _frozen := false
var _life := 1.0
var _hit_side := 1.0
var _death_side := 1.0
## Mane bones: [extra bone index, parent bone, local rest offset]; lagged orientations for the spring.
var _mane: Array[int] = []
var _mane_parent: Array[int] = []
var _mane_local: Array[Transform3D] = []
var _mane_lag: Array[Quaternion] = []

static var _mesh_cache := {}


func _init(_variant: int = 0) -> void:
	pass


func _ready() -> void:
	_rng.randomize()
	size_k = _rng.randf_range(0.98, 1.02)
	_death_side = -1.0 if _rng.randf() < 0.5 else 1.0
	q = Q.new(SPEC)
	q.torso_samples(TORSO, 2.2, 12, NECK, LEG_FRONT, LEG_HIND)
	for row in MANE_MASS:
		var mf: float = row[0]
		if mf < 0.0 or mf > 1.0:
			continue
		var np: Array = q.neck_point(mf)
		var tg: Vector3 = (q.neck_point(mf + 0.05)[0] as Vector3) - (q.neck_point(mf - 0.05)[0] as Vector3)
		var my := Vector3.RIGHT.cross(tg.normalized()).normalized()
		q.add_clamp_ring((np[0] as Vector3) + Vector3(0, 0.03, 0), Vector3.RIGHT, my if my.y > 0.0 else -my,
			float(row[1]) * 0.82, float(row[2]) * 0.82, float(row[3]) * 0.82, np[1])
	_add_mane_bones()
	if not _mesh_cache.has("lion"):
		_mesh_cache["lion"] = _build_mesh(q, coat, _mane)
	q.attach(self, _mesh_cache["lion"], size_k, AABB(Vector3(-2.2, -0.1, -3.2), Vector3(4.4, 4.2, 6.0)))
	q.ground_fn = ground_fn
	q.idle_seed = _rng.randf() * 100.0
	# the head's ground clamp samples the tables the head mesh is built from (skull, muzzle box, bridge)
	q.head_pts = Q.head_samples(SKULL, 2.4)
	q.head_pts.append_array(Q.head_samples(MUZZLE, 3.0))
	q.head_pts.append_array(Q.head_samples(BRIDGE, 2.4, 6))
	# the ruff's roots on the head reach ~0.52 m out at the cheeks (measured on the built mesh): a lion lying on its
	# side rests on them
	for s in [-1.0, 1.0]:
		for rp in [Vector3(0.53, 0.2, 0.18), Vector3(0.5, 0.05, 0.17), Vector3(0.48, 0.35, 0.17)]:
			q.head_pts.append(Vector3(rp.x * s, rp.y, rp.z))
	# the beard locks of the ruff hang well below the jaw: keep their reach above the ground too (crouch, death)
	for bp in [Vector3(0, -0.56, 0.36), Vector3(0.24, -0.58, 0.4), Vector3(-0.24, -0.58, 0.4)]:
		q.head_pts.append(bp)
	q.ear_h = 0.11
	parts["head"] = q.marker(&"head")
	var seat: Array = _mesh_cache["lion_eye"]
	for s in [-1.0, 1.0]:
		var e := Vector3((seat[0] as Vector3).x * s, (seat[0] as Vector3).y, (seat[0] as Vector3).z)
		var en := Vector3((seat[1] as Vector3).x * s, (seat[1] as Vector3).y, (seat[1] as Vector3).z).normalized()
		var h := add_glow("head", e + en * 0.02, coat["eye"], 0.1, 0.42)
		Materials.set_param(h, &"pull", 0.05)
		h.set_meta(&"n", en)
		_halos.append(h)
	_define_actions()
	q.solve(0.0)
	_pose_mane(0.0)
	q.apply()


# --- public API --------------------------------------------------------------------------------------------

func play(a: String) -> float:
	if _dead and a != "death":
		return 0.0
	if not actions.has(a):
		return 0.0
	q.push_prev(action, action_t, actions.get(action, []), 0.22)
	super.play(a)
	if a == "death":
		_dead = true
	return float(actions[a][0])


func _action_length(a: String) -> float:
	var def: Array = actions.get(a, [])
	if def.is_empty():
		return 0.4
	return INF if bool(def[1]) else float(def[0])


## Ends a loop (stunned, grappled) with a blend back to locomotion.
func stop() -> void:
	if action != "":
		q.push_prev(action, action_t, actions.get(action, []), 0.35)
		action = ""


func is_dead() -> bool:
	return _dead


func set_alert(k: float) -> void:
	alert = clampf(k, 0.0, 1.0)


## The low, deliberate stalk (same as set_alert(1 / 0)).
func set_stalk(on: bool) -> void:
	alert = 1.0 if on else 0.0


func set_look_target(world_pos: Vector3, weight: float = 1.0) -> void:
	q.look_target = world_pos
	q.look_w_target = weight


func clear_look() -> void:
	q.look_w_target = 0.0


func set_hit_dir(world_dir: Vector3) -> void:
	var l := global_transform.basis.inverse() * world_dir
	_hit_side = 1.0 if l.x >= 0.0 else -1.0
	_death_side = _hit_side


func head() -> Node3D:
	return q.marker(&"head")


func muzzle() -> Node3D:
	return q.marker(&"muzzle")


## Where the hero holds on while grappling (top of the neck, inside the mane).
func neck() -> Node3D:
	return q.marker(&"neck")


func chest() -> Node3D:
	return q.marker(&"chest")


func paw(i: int) -> Node3D:
	return q.marker(Q.PAW_NAMES[i])


func lock_point() -> Vector3:
	return q.marker(&"chest").global_position + Vector3(0, 0.3 * size_k, 0)


func clip_volumes() -> Array:
	var v := q.volumes(TORSO, NECK, HEAD, LEG_FRONT, LEG_HIND, PAW, SPEC["tail_r"])
	# the mane's solid core around the neck (paws must not sweep through it)
	var n0: Transform3D = q.rest[q.B_NECK0]
	var hp: Vector3 = q.rest[q.B_HEAD].origin
	v.append({"part": "mane", "a": n0.origin, "b": hp, "wa": PackedFloat32Array([q.B_NECK0, 1.0]), "wb": PackedFloat32Array([q.B_HEAD, 1.0]), "r": 0.3})
	return v


func debug_seek(a: String, time: float, move_speed: float = 0.0) -> void:
	q.always_pose = true
	set_locomotion(move_speed, 9.0)
	if a != "":
		play(a)
	var dt := 1.0 / 60.0
	for i in int(ceil(time / dt)):
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
	_alert_s = lerpf(_alert_s, 0.0 if _dead else alert, 1.0 - exp(-delta * 3.0))
	var al := _alert_s
	# Idle: deep breathing, a slow swish of the tail, an unhurried look around; the stalk lowers everything.
	# All of it fades out in death (no breathing corpse, no head sway into the ground).
	_life = move_toward(_life, 0.0 if _dead else 1.0, delta * 1.5)
	q.twitch = not _dead
	c[Q.BREATH] = sin(tt * 1.5) * 0.02 * _life
	c[Q.NECK_P] += sin(tt * 0.21 + q.idle_seed) * 0.04 * _life - al * 0.42
	c[Q.HEAD_P] += al * 0.3 + sin(tt * 0.33 + q.idle_seed) * 0.03 * _life
	c[Q.NECK_Y] += sin(tt * 0.17 + q.idle_seed * 2.0) * 0.14 * (1.0 - al) * _life
	c[Q.Y_FRONT] -= al * 0.16
	c[Q.Y_REAR] -= al * 0.1
	c[Q.FLEX] -= al * 0.03
	c[Q.EARS] = 0.1 - al * 0.8
	c[Q.TAIL_P] += -0.1 + al * 0.25
	c[Q.TAIL_CURL] += al * 0.04
	c[Q.TAIL_SWAY] = (0.16 + al * 0.18) * _life
	c[Q.GLOW] = 1.15 + al * 0.4
	c[Q.STAB] = 0.8
	q.cadence_k = lerpf(1.0, 0.72, al)
	q.run_actions(self, actions, _dead, _proc, delta)
	q.solve(delta)
	_pose_mane(delta)
	q.apply()
	q.update_halos(_halos, 0.42 * clampf(c[Q.GLOW], 0.0, 3.0) * clampf(c[Q.EYES], 0.0, 1.0))
	# the corpse holds its last pose once the death has played out (no solver, no skeleton update)
	if _dead and action == "":
		_frozen = true


## Three mane bones: the ruff around the face (follows the head), the neck mane (neck) and the shoulder mane /
## bib (neck base). Each lags behind its parent's rotation (springy, flowing) and flares with the MANE channel.
func _add_mane_bones() -> void:
	var specs := [[q.B_HEAD, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0.1))],
		[q.B_NECK1, Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0.0))],
		[q.B_NECK0, Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0.05))]]
	for sp in specs:
		var parent: int = sp[0]
		var off: Transform3D = sp[1]
		_mane_parent.append(parent)
		_mane_local.append(off)
		_mane.append(q.add_extra(q.rest[parent] * off))
		_mane_lag.append(Quaternion(q.rest[parent].basis.orthonormalized()))


func _pose_mane(dt: float) -> void:
	# MANE > 0 flares the mane; < 0 compresses it (the dead lion lying on its mane)
	var flare := clampf(q.ch[Q.MANE], -0.8, 1.6)
	for k in _mane.size():
		var px: Transform3D = q.xf[_mane_parent[k]]
		var target := Quaternion(px.basis.orthonormalized())
		if dt > 0.0:
			_mane_lag[k] = _mane_lag[k].slerp(target, 1.0 - exp(-dt * (9.0 - 2.0 * float(k))))
		else:
			_mane_lag[k] = target
		var lag_b := Basis(_mane_lag[k])
		var origin := px * _mane_local[k].origin
		var breath := 1.0 + q.ch[Q.BREATH] * 0.8
		var sc := Vector3(1.0 + flare * 0.26, 1.0 + flare * 0.26, 1.0 + flare * 0.1) * breath
		if flare < 0.0:
			sc = Vector3.ONE * (1.0 + flare * 0.45) * breath
		q.xf[_mane[k]] = Transform3D(lag_b * Basis.from_scale(sc), origin)


func _proc(a: String, p: float, at: float, w: float) -> void:
	var c := q.ch
	match a:
		"pounce":
			# the tail lashes while it gathers itself
			var kc := (1.0 - Rig.smooth((p - 0.3) / 0.08)) * w
			c[Q.TAIL_SWAY] += 0.55 * kc
			c[Q.TAIL_Y] += sin(at * 7.0) * 0.25 * kc
		"roar":
			var kr := Rig.smooth((p - 0.27) / 0.05) * (1.0 - Rig.smooth((p - 0.7) / 0.15)) * w
			c[Q.HEAD_R] += sin(at * 31.0) * 0.035 * kr
			c[Q.NECK_Y] += sin(at * 23.0 + 1.0) * 0.025 * kr
			c[Q.MANE] += sin(at * 17.0) * 0.12 * kr
		"stunned":
			c[Q.ROLL] += sin(at * 1.9) * 0.08 * w
			c[Q.X_SHIFT] += sin(at * 1.9) * 0.06 * w
			c[Q.NECK_Y] += sin(at * 1.3) * 0.4 * w
			c[Q.HEAD_R] += sin(at * 1.3 + 0.9) * 0.28 * w
			c[Q.HEAD_P] += sin(at * 2.6) * 0.07 * w
			c[Q.BEND] += sin(at * 0.95) * 0.06 * w
			for i in 4:
				c[Q.leg(i, Q.LX)] += q.leg_side[i] * 0.08 * w
		"grappled":
			var s1 := sin(at * TAU * 1.0)
			var s2 := sin(at * TAU * 2.0 + 0.6)
			c[Q.BEND] += s1 * 0.16 * w
			c[Q.ROLL] += s2 * 0.1 * w
			c[Q.YAW] += s1 * 0.12 * w
			c[Q.X_SHIFT] += s1 * 0.07 * w
			c[Q.NECK_Y] += -s1 * 0.25 * w
			c[Q.HEAD_R] += s2 * 0.25 * w
			c[Q.Y_FRONT] += absf(s2) * 0.03 * w
			c[Q.TAIL_Y] += sin(at * 11.0) * 0.7 * w
			for i in 2:
				var lift := maxf(0.0, sin(at * TAU * 2.0 + PI * float(i))) * 0.16 * w
				c[Q.leg(i, Q.LY)] += lift
				c[Q.leg(i, Q.LZ)] += -lift * 0.6
			for i in range(2, 4):
				c[Q.leg(i, Q.LZ)] += sin(at * TAU * 2.0 + PI * float(i)) * 0.08 * w
		"thrash":
			var kt := sin(clampf(p / 0.8, 0.0, 1.0) * PI) * w
			c[Q.BEND] += sin(at * 10.0) * 0.18 * kt * _hit_side
			c[Q.ROLL] += sin(at * 10.0 + 0.7) * 0.14 * kt
			c[Q.NECK_Y] += sin(at * 10.0 + 1.4) * 0.45 * kt
			c[Q.HEAD_R] += sin(at * 13.0) * 0.3 * kt
			c[Q.TAIL_Y] += sin(at * 12.0) * 0.8 * kt
		"spark":
			var ks := sin(clampf(p / 0.6, 0.0, 1.0) * PI) * w
			c[Q.HEAD_Y] -= 0.35 * _hit_side * ks
			c[Q.HEAD_R] += 0.12 * _hit_side * ks
		"hit":
			var kh := sin(p * PI) * w
			c[Q.X_SHIFT] += 0.06 * _hit_side * kh
			c[Q.ROLL] -= 0.08 * _hit_side * kh
			c[Q.HEAD_Y] -= 0.3 * _hit_side * kh
		"death":
			var k4 := Rig.smooth((p - 0.3) / 0.36) * w
			c[Q.ROLL] -= 1.45 * _death_side * k4
			c[Q.X_SHIFT] += 0.3 * _death_side * k4
			c[Q.HEAD_R] -= 0.35 * _death_side * k4
			# the legs on the side it falls on stretch out along the ground (front forward, hind back); the upper
			# legs stay stiff and lift a little: nothing folds into the body or crosses
			var kl := Rig.smooth((p - 0.32) / 0.3) * w
			for i in 4:
				var fr := i < 2
				if q.leg_side[i] * _death_side > 0.0:
					c[Q.leg(i, Q.LZ)] += (-0.2 if fr else 0.2) * kl
					c[Q.leg(i, Q.LX)] += q.leg_side[i] * 0.04 * kl
				else:
					c[Q.leg(i, Q.LY)] += 0.08 * kl
					c[Q.leg(i, Q.LX)] += q.leg_side[i] * 0.08 * kl
					c[Q.leg(i, Q.LZ)] += (0.06 if fr else -0.06) * kl


func _define_actions() -> void:
	var K := func(a: Array) -> PackedFloat32Array: return PackedFloat32Array(a)
	var LREL_AIR: PackedFloat32Array = K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.4, 1.0, 1, 0.66, 1.0, 0, 0.7, 0.0, 0])
	actions = {
		"swipe": [1.15, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.42, 0.06, 0, 0.52, 0.0, 1, 0.7, 0.0, 0, 1.0, 0.0, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.42, -0.06, 0, 0.52, -0.02, 1, 1.0, 0.0, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.42, 0.14, 0, 0.52, -0.16, 1, 0.7, -0.12, 0, 1.0, 0.0, 0]),
			Q.ROLL: K.call([0.0, 0.0, 0, 0.42, 0.1, 0, 0.52, -0.04, 1, 0.75, 0.0, 0]),
			Q.BEND: K.call([0.0, 0.0, 0, 0.42, -0.06, 0, 0.52, 0.08, 1, 0.8, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.42, -0.12, 0, 0.52, -0.25, 1, 1.0, 0.0, 0]),
			Q.NECK_Y: K.call([0.0, 0.0, 0, 0.42, 0.12, 0, 0.52, -0.1, 1, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.42, 0.2, 0, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.3, -1.3, 0, 0.8, -1.0, 0, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.4, -0.3, 0, 1.0, 0.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.4, 1.3, 0, 0.6, 0.6, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.42, 0.4, 0, 0.6, 0.2, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.3, -0.4, 0, 0.9, -0.4, 0, 1.0, 0.0, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.1, -1.0, 0, 0.9, -1.0, 0, 1.0, 0.0, 0]),
			# right forepaw: raised high and back, then swept forward and across
			Q.leg(1, Q.LREL): K.call([0.0, 0.0, 0, 0.15, 1.0, 0, 0.78, 1.0, 0, 0.9, 0.0, 0]),
			Q.leg(1, Q.LY): K.call([0.0, 0.0, 0, 0.42, 0.62, 0, 0.52, 0.3, 1, 0.66, 0.2, 0, 0.88, 0.05, 0, 0.94, 0.0, 0]),
			Q.leg(1, Q.LZ): K.call([0.0, 0.0, 0, 0.42, -0.1, 0, 0.52, -0.62, 1, 0.66, -0.42, 0, 0.9, -0.1, 0, 1.0, 0.0, 0]),
			Q.leg(1, Q.LX): K.call([0.0, 0.0, 0, 0.42, 0.32, 0, 0.52, -0.3, 1, 0.66, -0.22, 0, 0.9, 0.0, 0]),
			Q.leg(1, Q.LFLEX): K.call([0.0, 0.0, 0, 0.42, -0.9, 0, 0.52, 0.3, 1, 0.8, 0.0, 0]),
			Q.leg(0, Q.LX): K.call([0.0, 0.0, 0, 0.42, 0.08, 0, 0.8, 0.04, 0, 1.0, 0.0, 0]),
		}, {"impact": 0.52}],
		"pounce": [POUNCE_LEN, false, {
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.3, -0.34, 0, 0.36, -0.3, 1, 0.42, 0.25, 1, 0.52, 0.85, 0, 0.6, 0.6, 2, 0.68, 0.02, 2, 0.74, -0.18, 0, 0.86, -0.04, 0, 1.0, 0.0, 0]),
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.3, -0.42, 0, 0.36, -0.25, 1, 0.42, 0.5, 1, 0.5, 0.95, 0, 0.6, 0.55, 2, 0.67, -0.02, 2, 0.72, -0.26, 0, 0.86, -0.05, 0, 1.0, 0.0, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.3, 0.16, 0, 0.36, 0.0, 1, 0.55, -0.15, 0, 0.75, -0.08, 0, 1.0, 0.0, 0]),
			Q.FLEX: K.call([0.0, 0.0, 0, 0.3, 0.1, 0, 0.42, -0.1, 1, 0.6, -0.05, 0, 0.7, 0.08, 0, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.3, -0.5, 0, 0.42, -0.1, 1, 0.6, -0.3, 0, 0.74, -0.45, 0, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.3, 0.35, 0, 0.6, 0.15, 0, 0.74, 0.25, 0, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.3, 0, 0.9, -1.1, 0, 1.0, 0.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.3, 1.6, 0, 0.7, 0.8, 0, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.3, -0.35, 0, 0.5, 0.0, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.3, 0.3, 0, 0.5, 0.7, 0, 0.75, 0.2, 0, 1.0, 0.0, 0]),
			Q.TAIL_P: K.call([0.0, 0.0, 0, 0.3, 0.42, 0, 0.45, 0.55, 0, 0.7, 0.2, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.3, -0.6, 0, 0.9, -0.6, 0, 1.0, 0.0, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.08, -1.0, 0, 0.92, -1.0, 0, 1.0, 0.0, 0]),
			Q.leg(0, Q.LREL): LREL_AIR,
			Q.leg(1, Q.LREL): LREL_AIR,
			Q.leg(2, Q.LREL): K.call([0.0, 0.0, 0, 0.37, 0.0, 0, 0.42, 1.0, 1, 0.68, 1.0, 0, 0.73, 0.0, 0]),
			Q.leg(3, Q.LREL): K.call([0.0, 0.0, 0, 0.37, 0.0, 0, 0.42, 1.0, 1, 0.68, 1.0, 0, 0.73, 0.0, 0]),
			Q.leg(0, Q.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, -0.7, 1, 0.64, -0.35, 0, 0.7, 0.0, 0]),
			Q.leg(1, Q.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, -0.62, 1, 0.64, -0.3, 0, 0.7, 0.0, 0]),
			Q.leg(0, Q.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.42, 1, 0.64, 0.12, 0, 0.7, 0.0, 0]),
			Q.leg(1, Q.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.36, 1, 0.64, 0.1, 0, 0.7, 0.0, 0]),
			Q.leg(2, Q.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.55, 1, 0.66, 0.1, 0, 0.72, 0.0, 0]),
			Q.leg(3, Q.LZ): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.5, 1, 0.66, 0.1, 0, 0.72, 0.0, 0]),
			Q.leg(2, Q.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.2, 1, 0.66, 0.05, 0, 0.72, 0.0, 0]),
			Q.leg(3, Q.LY): K.call([0.0, 0.0, 0, 0.38, 0.0, 0, 0.5, 0.2, 1, 0.66, 0.05, 0, 0.72, 0.0, 0]),
			Q.leg(0, Q.LFLEX): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.45, -0.7, 1, 0.62, -0.2, 0, 0.68, 0.0, 0]),
			Q.leg(1, Q.LFLEX): K.call([0.0, 0.0, 0, 0.36, 0.0, 0, 0.45, -0.7, 1, 0.62, -0.2, 0, 0.68, 0.0, 0]),
			Q.leg(2, Q.LFLEX): K.call([0.0, 0.0, 0, 0.3, 0.25, 0, 0.42, -0.5, 1, 0.66, 0.0, 0]),
			Q.leg(3, Q.LFLEX): K.call([0.0, 0.0, 0, 0.3, 0.25, 0, 0.42, -0.5, 1, 0.66, 0.0, 0]),
		}, {"leap": POUNCE_LEAP / POUNCE_LEN, "land": POUNCE_LAND / POUNCE_LEN, "impact": POUNCE_LAND / POUNCE_LEN + 0.01}],
		"roar": [2.6, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.2, -0.08, 0, 0.3, 0.04, 1, 0.72, 0.03, 0, 0.9, 0.0, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.2, -0.04, 0, 0.3, -0.06, 1, 0.72, -0.06, 0, 0.9, 0.0, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.2, 0.06, 0, 0.3, -0.08, 1, 0.72, -0.06, 0, 0.9, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.2, -0.35, 0, 0.3, 0.38, 1, 0.72, 0.35, 0, 0.9, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.2, -0.1, 0, 0.3, -0.2, 1, 0.72, -0.22, 0, 0.9, 0.0, 0]),
			Q.FLEX: K.call([0.0, 0.0, 0, 0.2, 0.05, 0, 0.3, -0.06, 1, 0.72, -0.05, 0, 0.9, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.2, 0.2, 0, 0.3, 1.25, 1, 0.72, 1.0, 0, 0.92, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.25, -1.4, 0, 0.8, -1.2, 0, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.25, -0.4, 0, 0.75, -0.4, 0, 0.9, 0.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.25, 1.0, 0, 0.32, 2.0, 1, 0.75, 1.4, 0, 0.95, 0.0, 0]),
			Q.TAIL_P: K.call([0.0, 0.0, 0, 0.3, 0.45, 1, 0.75, 0.35, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.2, -0.7, 0, 0.9, -0.7, 0, 1.0, 0.0, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.1, -1.0, 0, 0.9, -1.0, 0, 1.0, 0.0, 0]),
			Q.leg(0, Q.LX): K.call([0.0, 0.0, 0, 0.3, -0.06, 0, 0.8, -0.06, 0, 1.0, 0.0, 0]),
			Q.leg(1, Q.LX): K.call([0.0, 0.0, 0, 0.3, 0.06, 0, 0.8, 0.06, 0, 1.0, 0.0, 0]),
		}, {"roar_wave": 0.3}],
		"bite": [1.1, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.4, -0.14, 0, 0.5, -0.08, 1, 0.65, -0.06, 0, 1.0, 0.0, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.4, -0.06, 0, 0.5, 0.0, 1, 1.0, 0.0, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.4, 0.14, 0, 0.5, -0.32, 1, 0.65, -0.26, 0, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.4, 0.15, 0, 0.5, -0.5, 1, 0.65, -0.4, 0, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.4, 0.2, 0, 0.5, -0.15, 1, 0.65, -0.1, 0, 1.0, 0.0, 0]),
			Q.FLEX: K.call([0.0, 0.0, 0, 0.4, 0.06, 0, 0.5, -0.05, 1, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.3, -1.4, 0, 0.8, -1.1, 0, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.4, -0.35, 0, 0.55, -0.1, 1, 1.0, 0.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.38, 1.4, 0, 0.6, 0.5, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.4, 0.35, 0, 0.55, 0.15, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.3, -0.6, 0, 0.9, -0.6, 0, 1.0, 0.0, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.1, -0.8, 0, 0.9, -0.8, 0, 1.0, 0.0, 0]),
		}, {"impact": 0.5}],
		"stunned": [2.2, true, {
			Q.Y_FRONT: K.call([0.0, -0.1, 0, 0.5, -0.14, 0, 1.0, -0.1, 0]),
			Q.Y_REAR: K.call([0.0, -0.05, 0, 0.5, -0.03, 0, 1.0, -0.05, 0]),
			Q.NECK_P: K.call([0.0, -0.45, 0, 0.5, -0.55, 0, 1.0, -0.45, 0]),
			Q.EARS: K.call([0.0, -0.9, 0, 1.0, -0.9, 0]),
			Q.EYES: K.call([0.0, -0.62, 0, 0.45, -0.78, 0, 1.0, -0.62, 0]),
			Q.GLOW: K.call([0.0, -0.45, 0, 1.0, -0.45, 0]),
			Q.TAIL_P: K.call([0.0, -0.04, 0, 1.0, -0.04, 0]),
			Q.TAIL_SWAY: K.call([0.0, -0.12, 0, 1.0, -0.12, 0]),
			Q.MANE: K.call([0.0, -0.1, 0, 1.0, -0.1, 0]),
			Q.STAB: K.call([0.0, -0.6, 0, 1.0, -0.6, 0]),
			Q.GAIT: K.call([0.0, -0.8, 0, 1.0, -0.8, 0]),
		}, {}],
		"grappled": [1.0, true, {
			Q.Y_FRONT: K.call([0.0, -0.02, 0, 1.0, -0.02, 0]),
			Q.NECK_P: K.call([0.0, -0.18, 0, 1.0, -0.18, 0]),
			Q.EARS: K.call([0.0, -1.4, 0, 1.0, -1.4, 0]),
			Q.EYES: K.call([0.0, -0.3, 0, 1.0, -0.3, 0]),
			Q.GLOW: K.call([0.0, 0.8, 0, 1.0, 0.8, 0]),
			Q.MANE: K.call([0.0, 0.4, 0, 1.0, 0.4, 0]),
			Q.TAIL_SWAY: K.call([0.0, 0.3, 0, 1.0, 0.3, 0]),
			Q.STAB: K.call([0.0, -0.5, 0, 1.0, -0.5, 0]),
			Q.GAIT: K.call([0.0, -1.0, 0, 1.0, -1.0, 0]),
		}, {}],
		"thrash": [1.3, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.18, -0.08, 0, 0.42, 0.22, 1, 0.6, 0.08, 0, 1.0, 0.0, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.18, -0.04, 0, 0.42, -0.06, 1, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.18, -0.2, 0, 0.42, 0.35, 1, 0.65, 0.1, 0, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.42, 0.3, 1, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.42, 1.0, 1, 0.8, 0.3, 0, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.4, 0, 0.9, -1.0, 0, 1.0, 0.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.3, 1.5, 0, 0.8, 0.5, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.2, -0.6, 0, 0.9, -0.6, 0, 1.0, 0.0, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.1, -1.0, 0, 0.9, -1.0, 0, 1.0, 0.0, 0]),
			Q.leg(0, Q.LREL): K.call([0.0, 0.0, 0, 0.14, 0.0, 0, 0.24, 1.0, 1, 0.56, 1.0, 0, 0.68, 0.0, 0]),
			Q.leg(1, Q.LREL): K.call([0.0, 0.0, 0, 0.14, 0.0, 0, 0.24, 1.0, 1, 0.56, 1.0, 0, 0.68, 0.0, 0]),
			Q.leg(0, Q.LFLEX): K.call([0.0, 0.0, 0, 0.3, 0.0, 0, 0.42, -0.5, 1, 0.6, -0.1, 0, 0.68, 0.0, 0]),
			Q.leg(1, Q.LFLEX): K.call([0.0, 0.0, 0, 0.3, 0.0, 0, 0.42, -0.5, 1, 0.6, -0.1, 0, 0.68, 0.0, 0]),
		}, {"impact": 0.45}],
		"spark": [0.42, false, {
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.3, 0.06, 1, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.3, 0.16, 1, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.5, 1, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.2, -0.75, 1, 0.7, -0.3, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.25, 0.35, 1, 1.0, 0.0, 0]),
		}, {}],
		"hit": [0.45, false, {
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.25, 0.08, 1, 1.0, 0.0, 0]),
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.25, -0.04, 1, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.25, 0.2, 1, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.25, 0.15, 1, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.4, 1, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.2, -0.8, 1, 0.6, -0.4, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.2, 0.4, 1, 1.0, 0.0, 0]),
		}, {}],
		"death": [2.6, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.15, -0.1, 0, 0.3, -0.42, 2, 0.42, -0.4, 0, 0.62, -0.78, 2, 0.72, -0.74, 0, 1.0, -0.76, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.3, -0.12, 0, 0.45, -0.3, 2, 0.62, -0.74, 2, 0.72, -0.7, 0, 1.0, -0.72, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.3, 0.06, 0, 1.0, 0.06, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.15, 0.3, 1, 0.45, -0.3, 2, 0.75, -0.42, 0, 1.0, -0.42, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.15, 0.35, 1, 0.6, -0.05, 0, 1.0, -0.08, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.2, 0, 1.0, -1.5, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.15, -0.5, 1, 0.5, -0.6, 0, 0.8, -0.97, 0, 1.0, -0.97, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.3, -0.3, 0, 0.85, -1.0, 0, 1.0, -1.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.12, 0.35, 1, 0.3, -0.5, 0, 0.55, -0.8, 0, 1.0, -0.8, 0]),
			Q.TAIL_P: K.call([0.0, 0.0, 0, 0.3, 0.2, 0, 0.7, 0.0, 0, 1.0, 0.0, 0]),
			Q.TAIL_SWAY: K.call([0.0, 0.0, 0, 0.5, -0.2, 0, 1.0, -0.2, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.3, -0.75, 0, 1.0, -0.75, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.1, -1.0, 0, 1.0, -1.0, 0]),
			Q.leg(0, Q.LREL): K.call([0.0, 0.0, 0, 0.42, 0.0, 0, 0.62, 1.0, 0, 1.0, 1.0, 0]),
			Q.leg(1, Q.LREL): K.call([0.0, 0.0, 0, 0.42, 0.0, 0, 0.62, 1.0, 0, 1.0, 1.0, 0]),
			Q.leg(2, Q.LREL): K.call([0.0, 0.0, 0, 0.45, 0.0, 0, 0.66, 1.0, 0, 1.0, 1.0, 0]),
			Q.leg(3, Q.LREL): K.call([0.0, 0.0, 0, 0.45, 0.0, 0, 0.66, 1.0, 0, 1.0, 1.0, 0]),
		}, {"fall": 0.62}],
	}


# --- mesh --------------------------------------------------------------------------------------------------

static func _build_mesh(qd: Q, cz: Dictionary, mane: Array[int]) -> Array:
	var sm := SM.new(37)
	var gold: Color = cz["gold"]
	var back: Color = cz["back"]
	var pale: Color = cz["pale"]
	sm.body_loft(qd, TORSO, NECK, 20, 0.0, 0.03, 2.2, 2)
	sm.paint(0, func(p: Vector3, n: Vector3) -> Color:
		if p.z < -0.72:
			return cz["mane0"]
		if n.y < -0.5:
			return pale
		if n.y < -0.2:
			return gold.lerp(pale, 0.45)
		if n.y > 0.62 and p.z > -0.7:
			return back
		return gold)
	# Legs: massive forelegs, strong haunches; heavy paws with four toes.
	for i in 4:
		var front := i < 2
		var from := sm.size()
		sm.leg_tube(qd, i, LEG_FRONT if front else LEG_HIND, 14, 0.16)
		sm.paw_loft(qd, i, PAW, 14)
		var j: PackedVector3Array = qd.rest_joints[i]
		sm.mb.push(Transform3D(Basis.IDENTITY, j[3]))
		for k in 4:
			var fx := lerpf(-0.105, 0.105, float(k) / 3.0)
			sm.ellipsoid(Vector3(fx, -0.045, -0.165 + absf(fx) * 0.35), Vector3(0.05, 0.03, 0.055), 8, 5)
		sm.mb.pop()
		sm.rigid(qd.B_LEG + i * 4 + 3)
		var sx := qd.leg_side[i]
		sm.paint(from, func(p: Vector3, n: Vector3) -> Color:
			if p.y < 0.13:
				return cz["paw"]
			if n.x * sx < -0.4 or (not front and n.z < -0.5 and p.y < 0.75):
				return gold.lerp(pale, 0.55)
			return gold)
	# Tail: an S that ends in a dark tuft.
	var tail_from := sm.size()
	sm.tail_tube(qd, SPEC["tail_r"], 10)
	var tip: Vector3 = qd.rest_tail_pts[qd.tail_n]
	var tdir := (qd.rest_tail_pts[qd.tail_n] - qd.rest_tail_pts[qd.tail_n - 1]).normalized()
	var tuft_from := sm.size()
	sm.mb.push(Transform3D(SM.frame_z(tdir), tip + tdir * 0.05))
	sm.ellipsoid(Vector3.ZERO, Vector3(0.095, 0.095, 0.16), 10, 7)
	sm.mb.pop()
	sm.rigid(qd.B_TAIL + qd.tail_n - 1)
	sm.paint(tail_from, func(p: Vector3, n: Vector3) -> Color:
		return cz["tuft"] if p.distance_to(tip) < 0.14 else (back if n.y > 0.4 else gold))
	sm.paint(tuft_from, func(_p: Vector3, n: Vector3) -> Color: return cz["tuft"] if n.y < 0.6 else cz["mane1"])
	# Head: a broad skull, a heavy frowning brow over narrow glowing eyes, a broad squared muzzle with a raised
	# bridge, an inverted-triangle nose pad on top of the muzzle tip, pale whisker pads and chin. Closed: no mouth.
	_build_head(sm, qd, cz)
	# Mane: layered locks, rooted on the head / neck (root weights) and flowing on the mane bones (tip weights).
	_build_mane(sm, qd, mane, cz)
	return sm.commit(qd.rest)


## The head (rigid to the head bone; the glowing eyes on the eyelid bone). Seats the eyes and the nose on the
## lofted surfaces and records where the eyes landed in _mesh_cache["lion_eye"] (right eye: [point, normal]).
static func _build_head(sm: SM, qd: Q, cz: Dictionary) -> void:
	var gold: Color = cz["gold"]
	var pale: Color = cz["pale"]
	var cream: Color = cz["muzzle"]
	var hx: Transform3D = qd.rest[qd.B_HEAD]
	var hinv := hx.affine_inverse()
	var hb: int = qd.B_HEAD
	var local := func(p: Vector3) -> Vector3: return hinv * p
	var lnorm := func(n: Vector3) -> Vector3: return (hinv.basis * n).normalized()
	# skull: gold, the crown a shade darker, pale under the eyes; behind the cheeks it is hidden by the mane
	var skull_from := sm.size()
	sm.head_loft(hx, SKULL, 20, 0.0, 0.02, hb, 2.4, 2)
	sm.paint(skull_from, func(p: Vector3, n: Vector3) -> Color:
		var l: Vector3 = local.call(p)
		if l.z > -0.02:
			return cz["mane0"]
		if _under_eye(l):
			return pale
		if (lnorm.call(n) as Vector3).y > 0.6 and l.z < -0.1:
			return cz["back"]
		return gold)
	# muzzle: a broad box under the eyes; its lower half (whisker level), front and underside are cream
	var muzzle_from := sm.size()
	sm.head_loft(hx, MUZZLE, 18, 0.03, 0.015, hb, 3.0, 2)
	sm.paint(muzzle_from, func(p: Vector3, n: Vector3) -> Color:
		var l: Vector3 = local.call(p)
		if (l.y < 0.035 and l.z < -0.27) or (lnorm.call(n) as Vector3).y < -0.35:
			return cream
		if _under_eye(l):
			return pale
		return gold)
	# the bridge: from the forehead between the brows down to the nose
	var bridge_from := sm.size()
	sm.head_loft(hx, BRIDGE, 12, 0.03, 0.01, hb, 2.4, 2)
	sm.paint(bridge_from, func(_p: Vector3, _n: Vector3) -> Color: return gold.lightened(0.04))
	var face_to := sm.size()
	# eyes: seated on the front of the skull (looking forward, a little outward)
	var es := _seat(sm, skull_from, face_to, hx, Vector3(EYE_X, EYE_Y, -1.0), Vector3(0, 0, 1))
	var ec: Vector3 = (es[0] as Vector3) if not es.is_empty() else Vector3(EYE_X, EYE_Y, -0.3)
	var en: Vector3 = ((es[1] as Vector3) if not es.is_empty() else Vector3(0, 0, -1)) + Vector3(0.22, 0.12, 0.0)
	en = en.normalized()
	_mesh_cache["lion_eye"] = [ec, en]
	# brows: one heavy ridge over each eye in a frowning V (inner ends low over the bridge), overhanging the eye
	var brow_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		var bc := Vector3((EYE_X - 0.01) * s, EYE_Y + 0.062, ec.z + 0.012)
		sm.mb.push(Transform3D(Basis(Vector3.BACK, 0.38 * s) * Basis(Vector3.UP, -0.25 * s) * Basis(Vector3.RIGHT, -0.18), bc))
		sm.ellipsoid(Vector3.ZERO, Vector3(0.1, 0.034, 0.055), 12, 7)
		sm.mb.pop()
	sm.mb.pop()
	sm.rigid(hb)
	sm.paint(brow_from, func(_p: Vector3, n: Vector3) -> Color:
		return cz["back"] if (lnorm.call(n) as Vector3).y > 0.25 else gold.darkened(0.1))
	# whisker pads: full and pale, with a filler between them under the nose so no notch or pocket shows from
	# below (the muzzle box itself is the chin); with the nose above them they read as a closed muzzle
	var pads_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		sm.ellipsoid(Vector3(0.08 * s, -0.06, -0.52), Vector3(0.095, 0.072, 0.075), 12, 7)
	sm.ellipsoid(Vector3(0, -0.055, -0.54), Vector3(0.07, 0.07, 0.07), 10, 6)
	sm.mb.pop()
	sm.rigid(hb)
	sm.paint(pads_from, func(_p: Vector3, _n: Vector3) -> Color: return cream)
	var pads_to := sm.size()
	# dark rims around the eyes (lion "eyeliner"), on the head bone so they stay when the lids close
	var rim_from := sm.size()
	for s in [-1.0, 1.0]:
		_patch(sm, skull_from, face_to, hx, Vector3(ec.x * s, ec.y, ec.z), Vector3(en.x * s, en.y, en.z), Vector3(s, 0, 0),
			_almond_outline(0.08, 0.03, 0.5), 0.004, hb)
	sm.paint(rim_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["mark"])
	# the nose: a broad inverted triangle on the top of the muzzle tip (wide above, pointed below); seen from the
	# front it sits above the pale pads, so the face never shows a dark round shape that could read as a mouth
	var nn := Vector3(0, 0.55, -0.835).normalized()
	var nose_from := sm.size()
	var ns := _seat(sm, muzzle_from, face_to, hx, Vector3(0, 0.065, -0.585) + nn * 0.4, -nn)
	var nc: Vector3 = (ns[0] as Vector3) if not ns.is_empty() else Vector3(0, 0.065, -0.585)
	_patch(sm, muzzle_from, pads_to, hx, nc, nn, Vector3.RIGHT, _nose_outline(0.088, 0.1), 0.012, hb)
	sm.paint(nose_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["nose"])
	# ears: short feline ears set wide on the crown and swept back, half sunk in the ruff: gold, a warm brown
	# hollow in front (never dark horns, never round teddy ears)
	for e in 2:
		var ex2: Transform3D = qd.rest[qd.B_EAR_L + e]
		var ear_from := sm.size()
		sm.mb.push(ex2)
		sm.ear(Vector3.ZERO, 0.135, 0.06, 0.105, 0.035, qd.B_EAR_L + e)
		sm.mb.pop()
		var einv := ex2.affine_inverse()
		sm.paint(ear_from, func(p: Vector3, n: Vector3) -> Color:
			if (einv.basis * n).normalized().z < -0.55:
				return cz["ear_in"]
			return gold.darkened(0.12) if (einv * p).y > 0.08 else gold)
	# the glowing eyes: narrow slanted slits on the eyelid bone, just above the rims
	var eye_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		var n := Vector3(en.x * s, en.y, en.z)
		sm.almond(Vector3(ec.x * s, ec.y, ec.z) + n * 0.007, n, s, 0.062, 0.015, 0.45, qd.B_EYES)
	sm.mb.pop()
	var eyc: Color = cz["eye"]
	sm.paint(eye_from, func(_p: Vector3, _n: Vector3) -> Color: return Color(eyc.r, eyc.g, eyc.b, 0.5))


## Pale fur under the eyes (head space).
static func _under_eye(l: Vector3) -> bool:
	var ax := absf(l.x)
	return l.z < -0.21 and l.z > -0.36 and ax > 0.075 and ax < 0.2 and l.y > 0.06 and l.y < 0.13


## [point, outward normal] (head space) where the ray from head-space `o` along `dir` first meets the triangles
## from..to of `sm`; [] when it misses.
static func _seat(sm: SM, from: int, to: int, hx: Transform3D, o: Vector3, dir: Vector3) -> Array:
	var hit := sm.raycast(from, to, hx * o, (hx.basis * dir).normalized())
	if hit.is_empty():
		return []
	var hinv := hx.affine_inverse()
	return [hinv * (hit[0] as Vector3), (hinv.basis * (hit[1] as Vector3)).normalized()]


## A low domed patch seated on the triangles from..to of `sm`: `outline` (metres, x along `xdir`, y up) is laid on
## the plane through c facing n, projected onto that surface along -n (rim tucked in, middle raised by `lift`).
## c, n and xdir are in head space; bound to `bone`.
static func _patch(sm: SM, from: int, to: int, hx: Transform3D, c: Vector3, n: Vector3, xdir: Vector3, outline: PackedVector2Array, lift: float, bone: int) -> void:
	var nn := n.normalized()
	var xv := (xdir - nn * xdir.dot(nn)).normalized()
	var yv := xv.cross(nn).normalized()
	if yv.y < 0.0:
		yv = -yv
	var hinv := hx.affine_inverse()
	var onto := func(p2: Vector2) -> Vector3:
		var q0 := c + xv * p2.x + yv * p2.y
		var hit := sm.raycast(from, to, hx * (q0 + nn * 0.15), (hx.basis * -nn).normalized())
		return (hinv * (hit[0] as Vector3)) if not hit.is_empty() else q0
	var m := outline.size()
	var rim := PackedVector3Array()
	var mid := PackedVector3Array()
	for p2 in outline:
		rim.append((onto.call(p2) as Vector3) - nn * 0.003)
		mid.append((onto.call(p2 * 0.55) as Vector3) + nn * lift * 0.75)
	var top: Vector3 = (onto.call(Vector2.ZERO) as Vector3) + nn * lift
	var inside := c - nn * 0.12
	var one := PackedFloat32Array([bone, 1.0])
	sm.mb.push(hx)
	for i in m:
		var j := (i + 1) % m
		sm.tri_o(rim[i], rim[j], mid[j], inside, one, one, one)
		sm.tri_o(rim[i], mid[j], mid[i], inside, one, one, one)
		sm.tri_o(mid[i], mid[j], top, inside, one, one, one)
	sm.mb.pop()


## Almond outline (x outward, y up): half width hw, half height hh, the outer corner lifted by `slant`.
static func _almond_outline(hw: float, hh: float, slant: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var segs := 10
	for i in segs:
		var u := lerpf(-1.0, 1.0, float(i) / float(segs))
		out.append(Vector2(u * hw, pow(1.0 - u * u, 0.7) * hh + u * slant * hh * 1.2))
	for i in segs:
		var u := lerpf(1.0, -1.0, float(i) / float(segs))
		out.append(Vector2(u * hw, -pow(1.0 - u * u, 0.7) * hh * 0.8 + u * slant * hh * 1.2))
	return out


## Nose outline: a rounded inverted triangle, half width w at the top (gently arched), height h, pointed below.
static func _nose_outline(w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-w, h * 0.3), Vector2(0, h * 0.42), Vector2(w, h * 0.3), Vector2(w * 0.35, -h * 0.25), Vector2(0, -h * 0.58), Vector2(-w * 0.35, -h * 0.25)])
	for it in 2:
		var sm2 := PackedVector2Array()
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			sm2.append(a.lerp(b, 0.25))
			sm2.append(a.lerp(b, 0.75))
		pts = sm2
	return pts


## Point on the rest neck path: f 0 = neck base, 0.5 = mid neck, 1 = head pivot (extrapolated beyond).
static func _neck_at(qd: Q, f: float) -> Vector3:
	var a: Vector3 = qd.rest[qd.B_NECK0].origin
	var b: Vector3 = qd.rest[qd.B_NECK1].origin
	var c: Vector3 = qd.rest[qd.B_HEAD].origin
	if f < 0.0:
		return a + (a - b) * (-f * 2.0)
	if f <= 0.5:
		return a.lerp(b, f * 2.0)
	if f <= 1.0:
		return b.lerp(c, (f - 0.5) * 2.0)
	return c + (c - b) * ((f - 1.0) * 2.0)


## Bone weights along the neck: root bone (neck / head) and the mane bone of that region.
static func _neck_bind(qd: Q, mane: Array[int], f: float, root_w: float) -> PackedFloat32Array:
	if f < 0.4:
		return PackedFloat32Array([qd.B_NECK0, root_w, mane[2], 1.0 - root_w])
	if f < 0.85:
		return PackedFloat32Array([qd.B_NECK1, root_w, mane[1], 1.0 - root_w])
	return PackedFloat32Array([qd.B_HEAD, root_w, mane[0], 1.0 - root_w])


## Mane: [f, half width, half height above, below] of the solid mass around the neck.
const MANE_MASS := [[-0.32, 0.25, 0.24, 0.25], [-0.12, 0.36, 0.38, 0.4], [0.22, 0.44, 0.46, 0.49], [0.58, 0.48, 0.5, 0.52], [0.88, 0.48, 0.5, 0.5], [1.04, 0.4, 0.42, 0.42], [1.14, 0.22, 0.22, 0.22]]


static func _build_mane(sm: SM, qd: Q, mane: Array[int], cz: Dictionary) -> void:
	var hx: Transform3D = qd.rest[qd.B_HEAD]
	var hinv := hx.affine_inverse()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 1) the solid mass: a fat loft around the neck that swallows the back of the skull (warmer next to the face,
	# so no black ring shows between the face and the ruff)
	var mass_from := sm.size()
	var cs := PackedVector3Array()
	var dims: Array = []
	var binds: Array = []
	for row in MANE_MASS:
		var f: float = row[0]
		cs.append(_neck_at(qd, f) + Vector3(0, 0.03, 0))
		dims.append(Vector4(row[1], row[2], row[3], 2.0))
		binds.append(_neck_bind(qd, mane, f, 0.55))
	sm.loft(cs, dims, binds, 18, 0.05, 0.03, Vector3.RIGHT, 2)
	sm.paint(mass_from, func(p: Vector3, _n: Vector3) -> Color:
		return cz["mane2"] if (hinv * p).z < 0.12 else cz["mane0"])
	# 2) the ruff framing the face: three layers of chunky locks streaming back from the face, lighter in front.
	# The crown locks are short and lie back (a smooth rounded crown from the front, no crest); the cheek locks
	# sweep back and fall; the beard locks under the jaw are the longest and hang. From the front the locks fall
	# outward and down like hair; they never radiate like petals. The first layer grows out of the cheeks.
	var ruff_cols: Array = [cz["ruff"], cz["mane2"], cz["mane1"]]
	for layer in 3:
		var count: int = [13, 14, 13][layer]
		var r0: float = [0.29, 0.35, 0.41][layer]
		var z0: float = [-0.05, 0.05, 0.15][layer]
		var len0: float = [0.24, 0.36, 0.44][layer]
		var layer_from := sm.size()
		for k in count:
			var u := (float(k) + 0.5 * float(layer % 2)) / float(count - 1)
			var a := lerpf(-2.65, 2.65, clampf(u, 0.0, 1.0))
			var dir := Vector3(sin(a), cos(a), 0.0)
			var crown := clampf(1.0 - absf(a) / 1.2, 0.0, 1.0)
			var low := clampf((absf(a) - 1.75) / 0.9, 0.0, 1.0)
			var root := Vector3(dir.x * r0 * (1.0 + 0.05 * low), 0.04 + dir.y * r0 * 0.92, z0)
			var lenk := len0 * (1.0 - 0.4 * crown + 0.15 * low) * rng.randf_range(0.88, 1.12)
			var fall := (0.3 + 0.5 * absf(dir.x) + 0.15 * low) * (1.0 - 0.85 * crown)
			var tipd := (dir * (0.4 - 0.15 * crown) + Vector3(0, -fall, 0) + Vector3(0, 0, 0.75 + 0.3 * crown)).normalized()
			var tip := root + tipd * lenk
			var ctrl := root + (dir * 0.75 + Vector3(0, 0.0, 0.45)).normalized() * lenk * 0.42
			sm.spike(hx * root, hx * ctrl, hx * tip, [0.115, 0.125, 0.13][layer], 0.075, hx.basis * Vector3(-dir.y, dir.x, 0), 7,
				PackedFloat32Array([qd.B_HEAD, 1.0]), PackedFloat32Array([mane[0], 1.0]), 4, 0.6)
		var lc: Color = ruff_cols[layer]
		sm.paint(layer_from, func(_p: Vector3, n: Vector3) -> Color: return lc.darkened(0.12) if n.y < -0.6 else lc)
	# 3) locks over the mass along the neck, flowing back and falling
	var neck_from := sm.size()
	for ring in 3:
		var f := 0.2 + 0.3 * float(ring)
		var c := _neck_at(qd, f) + Vector3(0, 0.03, 0)
		var fwd := (_neck_at(qd, f + 0.05) - _neck_at(qd, f - 0.05)).normalized()
		var basis := SM.frame_z(-fwd)
		var cnt := 9
		for k in cnt:
			var a := lerpf(-2.3, 2.3, (float(k) + 0.5 * float(ring % 2)) / float(cnt - 1))
			var dir := basis * Vector3(sin(a), cos(a), 0.0)
			var rr := 0.4
			var root := c + dir * rr
			var back := basis.z
			var lenk := (0.42 + 0.06 * float(ring)) * rng.randf_range(0.85, 1.15)
			var tip := root + (dir * 0.5 + back * 0.8 + Vector3(0, -0.3, 0)).normalized() * lenk
			var ctrl := root + dir * lenk * 0.3 + back * lenk * 0.3
			var rb := _neck_bind(qd, mane, f, 1.0)
			sm.spike(root - dir * 0.06, ctrl, tip, 0.15, 0.065, dir.cross(back), 7, PackedFloat32Array([rb[0], 1.0]), PackedFloat32Array([rb[2], 1.0]), 4, 0.6)
	sm.paint(neck_from, func(_p: Vector3, n: Vector3) -> Color: return cz["mane1"] if n.y > -0.3 else cz["mane0"])
	# 4) the bib: long locks hanging from the throat down the chest, between the forelegs
	var bib_from := sm.size()
	for k in 7:
		var x := lerpf(-0.22, 0.22, float(k) / 6.0)
		var f := 0.15 + 0.12 * float(k % 3)
		var c := _neck_at(qd, f)
		var root := c + Vector3(x, -0.36, -0.02)
		var tip := root + Vector3(x * 0.3, -0.3 - 0.05 * float(k % 2), 0.14)
		var ctrl := root + Vector3(x * 0.15, -0.16, -0.05)
		sm.spike(root, ctrl, tip, 0.12, 0.06, Vector3.RIGHT, 7, PackedFloat32Array([qd.B_NECK0, 1.0]), PackedFloat32Array([mane[2], 1.0]), 4, 0.5)
	sm.paint(bib_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["mane2"])
	# 5) a fringe over the withers
	var fringe_from := sm.size()
	var chx: Transform3D = qd.rest[qd.ns - 1]
	for k in 5:
		var x := lerpf(-0.2, 0.2, float(k) / 4.0)
		var root := chx * Vector3(x, 0.24, -0.16)
		var tip := root + Vector3(x * 0.6, -0.04, 0.42)
		sm.spike(root, root + Vector3(x * 0.3, 0.09, 0.16), tip, 0.12, 0.05, Vector3.RIGHT, 7, PackedFloat32Array([qd.ns - 1, 1.0]), PackedFloat32Array([mane[2], 1.0]), 4, 0.5)
	sm.paint(fringe_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["mane1"])
