class_name RigBoar
extends Rig
## BOAR of Nemea (bestiary): a dark brown wild boar, ~1.4 m from snout to rump, 0.9 m at the shoulder hump,
## a deep heavy barrel on short thin legs, the front heavier than the rear, a wedge-shaped head carried low, a dense
## crest of bristles in two rows from the crown to mid-back (it stands up when the boar is angry), pale curved
## tusks, small red-amber glowing eyes (they flare during wind-ups), dark cloven hooves, a thin tufted tail that
## shoots straight up as an alarm signal.
##
## Contract (BRIEF "Bestiary rigs"): set_locomotion(speed, max_speed), play(action) -> length.
##   charge_windup  head down, paws the ground twice, rocks back, tail up   events scrape (x2), charge (end)
##   charge         LOOP: head-down gallop (gallops even at speed 0)        events step
##   gore           tusk toss: head down then up and sideways               event impact
##   stunned        LOOP: dazed wobble, head lolling, legs splayed
##   hit, death (topples onto its side away from the hit: set_hit_dir() first; stays down; event fall)
## Loops play until another play() or stop(); play() returns one cycle's length for them.
## Locomotion: walk (~1.2 m/s), trot (~3 m/s), gallop (~7 m/s). Extras as RigWolf: set_alert(0..1) (head
## low, bristles up, tail up), set_look_target(), set_hit_dir(), head()/muzzle()/neck()/chest()/paw(i),
## tusks() (gore point), ground_fn, events step, stop(), is_dead(). CHARGE_SPEED (7 m/s) is the gallop the
## charge loop shows. Built with the quadruped kit in rig_wolf.gd.

const Q := RigWolf.Quadruped
const SM := RigWolf.SkinMesh

const COAT := {"back": Color("3B2A22"), "side": Color("4F3B2D"), "belly": Color("66503F"), "cheek": Color("8C6E58"),
	"bristle": Color("261B16"), "tip": Color("6E5646"), "snout": Color("5E443A"), "disc": Color("3A2A26"),
	"tusk": Color("F0E6CC"), "hoof": Color("2A201C"), "eye": Color("FF6A2E"), "ear_in": Color("5E443A")}

const SPEC := {
	"spine_s": [0.0, 0.34, 0.68, 1.0],
	"hip": Vector3(0, 0.56, 0.36),
	"chest": Vector3(0, 0.63, -0.22),
	"neck_base": Vector3(0, 0.635, -0.42),
	"neck_len": 0.18,
	"neck_pitch": -0.24,
	"head_pitch": -0.44,
	"front": [Vector3(-0.14, 0.47, -0.23), Vector3(-0.145, 0.33, -0.17), Vector3(-0.135, 0.13, -0.2), Vector3(-0.135, 0.045, -0.225)],
	"hind": [Vector3(-0.13, 0.49, 0.37), Vector3(-0.15, 0.33, 0.27), Vector3(-0.135, 0.17, 0.41), Vector3(-0.135, 0.045, 0.375)],
	"tail_root": Vector3(0, 0.632, 0.556),
	"tail_n": 6,
	"tail_len": 0.26,
	"tail_pitch": -0.5,
	"tail_curl": -0.13,
	"tail_r": [0.026, 0.021, 0.017, 0.014, 0.014, 0.034, 0.016],
	"ear": [Vector3(-0.1, 0.165, 0.06), -0.7, -0.3],
	"eye": Vector3(0, 0.096, -0.1),
	"muzzle": Vector3(0, -0.03, -0.445),
	"head_clear": 0.06,
	"lift_scale": 1.0,
	"gaits": [
		{"speed": 1.2, "freq": 1.9, "duty": 0.62, "off": [0.75, 0.25, 0.0, 0.5], "lift": 0.06, "flex": 0.8,
			"bob": 0.012, "bob_m": 2.0, "bob_ph": 0.1, "pitch": 0.006, "spine": 0.0, "roll": 0.03, "head": 0.03,
			"track_f": -0.02, "track_h": 0.035, "zoff_h": 0.03},
		{"speed": 3.0, "freq": 3.0, "duty": 0.45, "off": [0.5, 0.0, 0.0, 0.5], "lift": 0.085, "flex": 1.1,
			"bob": 0.02, "bob_m": 2.0, "bob_ph": 0.15, "pitch": 0.01, "spine": 0.0, "roll": 0.035, "head": 0.04,
			"track_f": -0.03, "track_h": 0.045, "zoff_h": 0.025},
		{"speed": 7.0, "freq": 3.4, "duty": 0.3, "off": [0.5, 0.4, 0.0, 0.9], "lift": 0.11, "flex": 1.3,
			"bob": 0.04, "bob_m": 1.0, "bob_ph": 0.9, "pitch": 0.05, "spine": 0.03, "roll": 0.02, "head": 0.05,
			"track_f": -0.026, "track_h": 0.085, "zoff_f": 0.05, "zoff_h": -0.03},
	],
	"gait_up": [1.8, 4.4],
	"max_stance": 0.48,
	# low belly, short legs: on cross-slopes the body stays nearer the average foot height (the uphill leg folds less)
	"slope_low": 0.4,
}

const TORSO := [
	[0.56, 0.56, 0.03, 0.03, 0.03],
	[0.54, 0.56, 0.11, 0.11, 0.12],
	[0.48, 0.56, 0.17, 0.15, 0.19],
	[0.38, 0.565, 0.2, 0.17, 0.225],
	[0.24, 0.575, 0.215, 0.185, 0.25],
	[0.08, 0.59, 0.235, 0.21, 0.275],
	[-0.08, 0.61, 0.25, 0.24, 0.29],
	[-0.2, 0.625, 0.255, 0.26, 0.295],
	[-0.3, 0.625, 0.245, 0.255, 0.28],
	[-0.38, 0.615, 0.22, 0.235, 0.25],
]
const NECK := [[0.0, 0.225, 0.23, 0.26], [0.5, 0.2, 0.2, 0.22], [1.0, 0.15, 0.15, 0.15], [1.15, 0.09, 0.09, 0.09]]
const HEAD := [
	[0.12, 0.07, 0.06, 0.06, 0.06],
	[0.08, 0.07, 0.15, 0.17, 0.15],
	[0.02, 0.06, 0.17, 0.18, 0.16],
	[-0.07, 0.035, 0.15, 0.15, 0.145],
	[-0.16, 0.012, 0.118, 0.112, 0.122],
	[-0.25, -0.01, 0.09, 0.085, 0.095],
	[-0.33, -0.02, 0.074, 0.07, 0.076],
	[-0.4, -0.026, 0.068, 0.064, 0.068],
	[-0.43, -0.026, 0.066, 0.062, 0.066],
]
const LEG_FRONT := [Vector2(0.09, 0.115), Vector2(0.078, 0.098), Vector2(0.058, 0.064), Vector2(0.045, 0.048), Vector2(0.036, 0.038), Vector2(0.032, 0.034), Vector2(0.032, 0.033)]
const LEG_HIND := [Vector2(0.105, 0.145), Vector2(0.09, 0.12), Vector2(0.06, 0.068), Vector2(0.047, 0.052), Vector2(0.037, 0.039), Vector2(0.032, 0.034), Vector2(0.032, 0.033)]
const HOOF := [[0.02, -0.01, 0.03, 0.025, 0.025], [-0.008, -0.02, 0.036, 0.028, 0.025], [-0.035, -0.03, 0.032, 0.016, 0.015], [-0.05, -0.034, 0.02, 0.008, 0.011]]
## Eyes (head space): x offset from the eyelid bone and the normal. Tusks: [root, control, tip] (right side).
const EYE_X := 0.12
const EYE_N := Vector3(0.82, 0.48, -0.3)
const TUSK := [Vector3(0.058, -0.055, -0.34), Vector3(0.125, -0.025, -0.38), Vector3(0.118, 0.085, -0.31)]
const CHARGE_SPEED := 7.0

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
## Once the death has played out the corpse holds its last pose: no solver, no skeleton update (it costs nothing).
var _frozen := false
var _life := 1.0
var _hit_side := 1.0
var _death_side := 1.0
var _ridge: Array[int] = []
var _ridge_local: Array[Transform3D] = []
var _ridge_parent: Array[int] = []

static var _mesh_cache := {}


func _init(_variant: int = 0) -> void:
	pass


func _ready() -> void:
	_rng.randomize()
	size_k = _rng.randf_range(0.97, 1.04)
	_death_side = -1.0 if _rng.randf() < 0.5 else 1.0
	q = Q.new(SPEC)
	q.torso_samples(TORSO, 2.4, 12, NECK, LEG_FRONT, LEG_HIND)
	_add_ridge_bones()
	if not _mesh_cache.has("boar"):
		_mesh_cache["boar"] = _build_mesh(q, coat)
	q.attach(self, _mesh_cache["boar"], size_k, AABB(Vector3(-1.1, -0.1, -1.4), Vector3(2.2, 1.8, 2.8)))
	q.ground_fn = ground_fn
	q.idle_seed = _rng.randf() * 100.0
	q.head_pts = Q.head_samples(HEAD)
	for s in [-1.0, 1.0]:
		q.head_pts.append(Vector3(TUSK[2].x * s, TUSK[2].y, TUSK[2].z))
		q.head_pts.append(Vector3(TUSK[1].x * s, TUSK[1].y, TUSK[1].z))
	q.ear_h = 0.11
	parts["head"] = q.marker(&"head")
	var tm := Node3D.new()
	tm.name = "tusks"
	tm.position = Vector3(0, 0.0, -0.36)
	q.marker(&"head").add_child(tm)
	q.markers[&"tusks"] = tm
	for s in [-1.0, 1.0]:
		var e: Vector3 = SPEC["eye"] + Vector3(EYE_X * s, 0.0, 0.0)
		var en := Vector3(EYE_N.x * s, EYE_N.y, EYE_N.z).normalized()
		var h := add_glow("head", e + en * 0.006, coat["eye"], 0.06, 0.42)
		Materials.set_param(h, &"pull", 0.06)
		h.set_meta(&"n", en)
		_halos.append(h)
	_define_actions()
	q.solve(0.0)
	_pose_ridge()
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
	return float(actions[a][0])


func _action_length(a: String) -> float:
	var def: Array = actions.get(a, [])
	if def.is_empty():
		return 0.4
	return INF if bool(def[1]) else float(def[0])


## Ends a loop (charge, stunned) with a short blend back to locomotion.
func stop() -> void:
	if action != "":
		q.push_prev(action, action_t, actions.get(action, []), 0.25)
		action = ""


func is_dead() -> bool:
	return _dead


func set_alert(k: float) -> void:
	alert = clampf(k, 0.0, 1.0)


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


## Between the tusks (where a gore connects).
func tusks() -> Node3D:
	return q.marker(&"tusks")


func neck() -> Node3D:
	return q.marker(&"neck")


func chest() -> Node3D:
	return q.marker(&"chest")


func paw(i: int) -> Node3D:
	return q.marker(Q.PAW_NAMES[i])


func lock_point() -> Vector3:
	return q.marker(&"chest").global_position + Vector3(0, 0.12 * size_k, 0)


func clip_volumes() -> Array:
	var v := q.volumes(TORSO, NECK, HEAD, LEG_FRONT, LEG_HIND, HOOF, SPEC["tail_r"], 0.8, false)
	var hm := PackedFloat32Array([q.B_HEAD, 1.0])
	var hx: Transform3D = q.rest[q.B_HEAD]
	for s in [-1.0, 1.0]:
		var a: Vector3 = TUSK[0]
		var b: Vector3 = TUSK[2]
		v.append({"part": "tusk", "a": hx * Vector3(a.x * s, a.y, a.z), "b": hx * Vector3(b.x * s, b.y, b.z), "wa": hm, "wb": hm, "r": 0.012})
	return v


func debug_seek(a: String, time: float, move_speed: float = 0.0) -> void:
	q.always_pose = true
	set_locomotion(move_speed, 8.0)
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
	q.speed_floor = CHARGE_SPEED if action == "charge" else 0.0
	var c := q.begin(delta)
	var tt := t
	_alert_s = lerpf(_alert_s, 0.0 if _dead else alert, 1.0 - exp(-delta * 4.0))
	var al := _alert_s
	# idle life fades out in death (no breathing, no looking around)
	_life = move_toward(_life, 0.0 if _dead else 1.0, delta * 1.5)
	q.twitch = not _dead
	c[Q.BREATH] = sin(tt * 2.6) * 0.02 * _life
	c[Q.NECK_P] += sin(tt * 0.37 + q.idle_seed) * 0.05 * _life - al * 0.18
	c[Q.HEAD_P] += sin(tt * 0.5 + q.idle_seed * 3.0) * 0.04 * _life - al * 0.12
	c[Q.NECK_Y] += sin(tt * 0.27 + q.idle_seed * 2.0) * 0.1 * (1.0 - al) * _life
	c[Q.HEAD_R] += sin(tt * 0.9 + q.idle_seed) * 0.03 * _life
	c[Q.Y_FRONT] -= al * 0.03
	c[Q.EARS] = 0.2 - al * 1.0
	c[Q.TAIL_P] += al * 1.15
	c[Q.TAIL_SWAY] = (0.18 * (1.0 - al) + 0.05) * _life
	c[Q.MANE] = al * 0.7
	c[Q.GLOW] = 1.0 + al * 0.4
	c[Q.STAB] = 0.6
	q.run_actions(self, actions, _dead, _proc, delta)
	q.solve(delta)
	_pose_ridge()
	q.apply()
	q.update_halos(_halos, 0.42 * clampf(c[Q.GLOW], 0.0, 3.0) * clampf(c[Q.EYES], 0.0, 1.0))
	# the eyes flare before an attack (wind-up glow keys): bigger halos read from 10 m, where an eye is ~3 px
	var flare := clampf(1.0 + (c[Q.GLOW] - 1.0) * 0.8, 1.0, 2.0)
	for h in _halos:
		h.scale = Vector3.ONE * flare
	if _dead and action == "":
		_frozen = true


## Hackle bones: the bristle ridge stands up with the MANE channel (bristles stretch up from their roots).
func _add_ridge_bones() -> void:
	var tops := [[q.B_HEAD, Vector3(0, 0.2, 0.06)], [q.B_NECK1, Vector3(0, 0.17, 0.0)], [q.ns - 1, Vector3(0, 0.21, 0.0)], [q.ns - 2, Vector3(0, 0.19, 0.0)], [1, Vector3(0, 0.17, 0.0)]]
	for tp in tops:
		var parent: int = tp[0]
		var off := Transform3D(Basis.IDENTITY, tp[1])
		_ridge_parent.append(parent)
		_ridge_local.append(off)
		_ridge.append(q.add_extra(q.rest[parent] * off))


func _pose_ridge() -> void:
	var raise := clampf(q.ch[Q.MANE], 0.0, 1.5)
	for k in _ridge.size():
		var px: Transform3D = q.xf[_ridge_parent[k]]
		q.xf[_ridge[k]] = px * _ridge_local[k] * Transform3D(Basis.from_scale(Vector3(1.0, 1.0 + raise * 0.55, 1.0 + raise * 0.1)), Vector3.ZERO)


func _proc(a: String, p: float, at: float, w: float) -> void:
	var c := q.ch
	match a:
		"charge_windup":
			# two scrapes of the front right hoof: lift, then drag back along the ground
			for k in 2:
				var s0 := 0.18 + 0.27 * float(k)
				var u := clampf((p - s0) / 0.22, 0.0, 1.0)
				if u > 0.0 and u < 1.0:
					var lift := sin(clampf(u / 0.45, 0.0, 1.0) * PI * 0.5) * (1.0 - Rig.smooth((u - 0.45) / 0.2))
					c[Q.leg(1, Q.LY)] += 0.09 * lift * w
					c[Q.leg(1, Q.LZ)] += lerpf(-0.12, 0.14, Rig.smooth((u - 0.4) / 0.5)) * sin(u * PI) * w
			c[Q.TAIL_SWAY] += 0.25 * w
		"charge":
			c[Q.HEAD_R] += sin(at * 9.0) * 0.04 * w
		"gore":
			c[Q.HEAD_Y] += -0.45 * _hit_side * Rig.smooth((p - 0.38) / 0.12) * (1.0 - Rig.smooth((p - 0.6) / 0.35)) * w
			c[Q.HEAD_R] += 0.35 * _hit_side * Rig.smooth((p - 0.38) / 0.12) * (1.0 - Rig.smooth((p - 0.6) / 0.35)) * w
		"stunned":
			var k3 := w
			c[Q.ROLL] += sin(at * 2.4) * 0.11 * k3
			c[Q.X_SHIFT] += sin(at * 2.4) * 0.035 * k3
			c[Q.NECK_Y] += sin(at * 1.7) * 0.35 * k3
			c[Q.HEAD_R] += sin(at * 1.7 + 0.8) * 0.3 * k3
			c[Q.HEAD_P] += sin(at * 3.1) * 0.08 * k3
			c[Q.BEND] += sin(at * 1.2) * 0.03 * k3
			for i in 4:
				c[Q.leg(i, Q.LX)] += q.leg_side[i] * 0.05 * k3
		"hit":
			var kh := sin(p * PI) * w
			c[Q.X_SHIFT] += 0.04 * _hit_side * kh
			c[Q.ROLL] -= 0.12 * _hit_side * kh
			c[Q.HEAD_Y] -= 0.3 * _hit_side * kh
		"death":
			var k4 := Rig.smooth((p - 0.25) / 0.38) * w
			c[Q.ROLL] -= 1.45 * _death_side * k4
			c[Q.X_SHIFT] += 0.12 * _death_side * k4
			c[Q.HEAD_R] -= 0.3 * _death_side * k4
			# the legs on the side it falls on stretch out along the ground (front ones forward, hind ones back),
			# the upper legs stay stiff and lift a little: nothing folds into the heavy barrel
			var kl := Rig.smooth((p - 0.24) / 0.3) * w
			for i in 4:
				var front := i < 2
				if q.leg_side[i] * _death_side > 0.0:
					c[Q.leg(i, Q.LZ)] += (-0.12 if front else 0.12) * kl
					c[Q.leg(i, Q.LX)] += q.leg_side[i] * 0.02 * kl
				else:
					c[Q.leg(i, Q.LY)] += 0.05 * kl
					c[Q.leg(i, Q.LZ)] += (-0.04 if front else 0.04) * kl


func _define_actions() -> void:
	var K := func(a: Array) -> PackedFloat32Array: return PackedFloat32Array(a)
	actions = {
		"charge_windup": [1.3, false, {
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.15, -0.07, 0, 0.88, -0.08, 0, 1.0, -0.02, 0]),
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.15, -0.05, 0, 0.88, -0.07, 0, 1.0, -0.04, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.15, 0.08, 0, 0.85, 0.1, 0, 1.0, -0.02, 1]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.15, -0.3, 0, 0.9, -0.34, 0, 1.0, -0.3, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.15, -0.16, 0, 0.9, -0.2, 0, 1.0, -0.15, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.12, -1.3, 0, 1.0, -1.3, 0]),
			Q.TAIL_P: K.call([0.0, 0.0, 0, 0.12, 1.45, 1, 1.0, 1.45, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.15, 1.0, 1, 1.0, 1.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.2, 1.3, 0, 1.0, 1.5, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.2, -0.3, 0, 1.0, -0.3, 0]),
			Q.FLEX: K.call([0.0, 0.0, 0, 0.15, 0.03, 0, 1.0, 0.03, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.15, -0.4, 0, 1.0, -0.4, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.1, -1.0, 0, 0.95, -1.0, 0, 1.0, 0.0, 0]),
		}, {"scrape": 0.32, "scrape#2": 0.59, "charge": 0.98}],
		"charge": [0.3, true, {
			Q.NECK_P: K.call([0.0, -0.3, 0, 1.0, -0.3, 0]),
			Q.HEAD_P: K.call([0.0, -0.16, 0, 1.0, -0.16, 0]),
			Q.EARS: K.call([0.0, -1.4, 0, 1.0, -1.4, 0]),
			Q.TAIL_P: K.call([0.0, 1.35, 0, 1.0, 1.35, 0]),
			Q.MANE: K.call([0.0, 1.0, 0, 1.0, 1.0, 0]),
			Q.GLOW: K.call([0.0, 1.2, 0, 1.0, 1.2, 0]),
			Q.Y_FRONT: K.call([0.0, -0.03, 0, 1.0, -0.03, 0]),
			Q.STAB: K.call([0.0, 0.2, 0, 1.0, 0.2, 0]),
		}, {}],
		"gore": [0.85, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.38, -0.08, 0, 0.48, 0.02, 1, 0.65, 0.01, 0, 1.0, 0.0, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.38, -0.03, 0, 0.48, 0.02, 1, 1.0, 0.0, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.38, 0.06, 0, 0.48, -0.12, 1, 0.7, -0.06, 0, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.38, -0.32, 0, 0.48, 0.42, 1, 0.62, 0.3, 0, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.38, -0.28, 0, 0.48, 0.55, 1, 0.62, 0.4, 0, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.3, -1.4, 0, 0.8, -1.0, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.3, 1.0, 0, 0.8, 0.8, 0, 1.0, 0.0, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.35, 1.3, 0, 0.6, 0.5, 0, 1.0, 0.0, 0]),
			Q.TAIL_P: K.call([0.0, 0.0, 0, 0.3, 1.2, 1, 0.8, 1.0, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.3, -0.5, 0, 0.8, -0.5, 0, 1.0, 0.0, 0]),
		}, {"impact": 0.48}],
		"stunned": [1.6, true, {
			Q.Y_FRONT: K.call([0.0, -0.05, 0, 0.5, -0.07, 0, 1.0, -0.05, 0]),
			Q.Y_REAR: K.call([0.0, -0.04, 0, 0.5, -0.02, 0, 1.0, -0.04, 0]),
			Q.NECK_P: K.call([0.0, -0.28, 0, 0.5, -0.36, 0, 1.0, -0.28, 0]),
			Q.EARS: K.call([0.0, -0.8, 0, 1.0, -0.8, 0]),
			Q.EYES: K.call([0.0, -0.6, 0, 0.45, -0.75, 0, 1.0, -0.6, 0]),
			Q.GLOW: K.call([0.0, -0.4, 0, 1.0, -0.4, 0]),
			Q.TAIL_P: K.call([0.0, 0.12, 0, 1.0, 0.12, 0]),
			Q.TAIL_SWAY: K.call([0.0, -0.15, 0, 1.0, -0.15, 0]),
			Q.STAB: K.call([0.0, -0.5, 0, 1.0, -0.5, 0]),
			Q.GAIT: K.call([0.0, -0.7, 0, 1.0, -0.7, 0]),
		}, {}],
		"hit": [0.36, false, {
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.25, 0.06, 1, 1.0, 0.0, 0]),
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.25, -0.02, 1, 1.0, 0.0, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.25, 0.2, 1, 1.0, 0.0, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.25, 0.18, 1, 1.0, 0.0, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.4, 1, 1.0, 0.0, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.2, -0.8, 1, 0.6, -0.5, 0, 1.0, 0.0, 0]),
			Q.MANE: K.call([0.0, 0.0, 0, 0.2, 0.6, 1, 1.0, 0.0, 0]),
		}, {}],
		"death": [1.5, false, {
			Q.Y_FRONT: K.call([0.0, 0.0, 0, 0.2, -0.16, 2, 0.32, -0.22, 0, 0.62, -0.385, 2, 0.75, -0.36, 0, 1.0, -0.365, 0]),
			Q.Y_REAR: K.call([0.0, 0.0, 0, 0.25, -0.08, 0, 0.4, -0.16, 2, 0.62, -0.35, 2, 0.75, -0.325, 0, 1.0, -0.33, 0]),
			Q.Z_SHIFT: K.call([0.0, 0.0, 0, 0.3, 0.04, 0, 1.0, 0.04, 0]),
			Q.NECK_P: K.call([0.0, 0.0, 0, 0.2, 0.15, 1, 0.55, -0.2, 2, 1.0, -0.2, 0]),
			Q.HEAD_P: K.call([0.0, 0.0, 0, 0.2, 0.25, 1, 0.6, -0.05, 0, 1.0, -0.05, 0]),
			Q.EARS: K.call([0.0, 0.0, 0, 0.2, -1.2, 0, 1.0, -1.4, 0]),
			Q.EYES: K.call([0.0, 0.0, 0, 0.16, -0.7, 1, 0.55, -0.6, 0, 0.8, -0.97, 0, 1.0, -0.97, 0]),
			Q.GLOW: K.call([0.0, 0.0, 0, 0.3, -0.4, 0, 0.8, -1.0, 0, 1.0, -1.0, 0]),
			Q.TAIL_P: K.call([0.0, 0.0, 0, 0.2, 0.5, 0, 0.6, 0.0, 0, 1.0, 0.0, 0]),
			Q.STAB: K.call([0.0, 0.0, 0, 0.3, -0.6, 0, 1.0, -0.6, 0]),
			Q.GAIT: K.call([0.0, 0.0, 0, 0.12, -1.0, 0, 1.0, -1.0, 0]),
			Q.leg(0, Q.LREL): K.call([0.0, 0.0, 0, 0.3, 0.0, 0, 0.55, 1.0, 0, 1.0, 1.0, 0]),
			Q.leg(1, Q.LREL): K.call([0.0, 0.0, 0, 0.3, 0.0, 0, 0.55, 1.0, 0, 1.0, 1.0, 0]),
			Q.leg(2, Q.LREL): K.call([0.0, 0.0, 0, 0.35, 0.0, 0, 0.6, 1.0, 0, 1.0, 1.0, 0]),
			Q.leg(3, Q.LREL): K.call([0.0, 0.0, 0, 0.35, 0.0, 0, 0.6, 1.0, 0, 1.0, 1.0, 0]),
		}, {"fall": 0.62}],
	}


# --- mesh --------------------------------------------------------------------------------------------------

static func _build_mesh(qd: Q, cz: Dictionary) -> Array:
	var sm := SM.new(23)
	var back: Color = cz["back"]
	var side: Color = cz["side"]
	var belly: Color = cz["belly"]
	sm.body_loft(qd, TORSO, NECK, 16, 0.0, 0.02, 2.4, 2)
	sm.paint(0, func(p: Vector3, n: Vector3) -> Color:
		if n.y < -0.45:
			return belly
		if p.z < -0.3 and n.y < -0.1:
			return cz["cheek"].lerp(side, 0.5)
		if n.y > 0.55:
			return back
		return side)
	# Bristle crest: a dense mane of stiff bristles in two staggered rows from the crown along the hump to mid-back,
	# lying back along the spine; the hackle bones stand it up when the boar is angry (MANE channel).
	var ridge_from := sm.size()
	var hx: Transform3D = qd.rest[qd.B_HEAD]
	var pts: Array = []
	for k in 5:
		pts.append([hx * Vector3(0, 0.19 + 0.01 * k, 0.17 - 0.05 * k), qd.B_EXTRA + 0, 0.0])
	var nk: Transform3D = qd.rest[qd.B_NECK1]
	for k in 3:
		pts.append([nk * Vector3(0, 0.15 + 0.005 * k, -0.04 + 0.05 * k), qd.B_EXTRA + 1, 0.3])
	for k in 14:
		var z := lerpf(-0.37, 0.22, float(k) / 13.0)
		var bone := qd.B_EXTRA + (2 if z < -0.12 else (3 if z < 0.05 else 4))
		pts.append([Vector3(0, _top_y(z) - 0.014, z), bone, 0.3 + 0.7 * sin(PI * clampf((z + 0.37) / 0.75, 0.0, 1.0))])
	for k in pts.size():
		var base: Vector3 = pts[k][0]
		var bone: int = pts[k][1]
		var hump: float = pts[k][2]
		var u := float(k) / float(pts.size() - 1)
		for row in 2:
			var sx := (-1.0 if (k + row) % 2 == 0 else 1.0) * (0.016 + 0.012 * float(row))
			var hgt := (0.075 + 0.045 * hump) * (1.0 - 0.3 * float(row)) * (1.0 - 0.45 * smoothstep(0.85, 1.0, u))
			var lean := Vector3(sx * 1.6, hgt, 0.06 + 0.04 * hump)
			var b0 := base + Vector3(sx, -0.025 - 0.01 * float(row), 0.012 * float(row))
			sm.spike(b0, b0 + lean * 0.5 + Vector3(0, 0.012, -0.012), b0 + lean, 0.042 - 0.008 * float(row), 0.02, Vector3.FORWARD, 5, PackedFloat32Array([bone, 1.0]))
	sm.paint(ridge_from, func(p: Vector3, _n: Vector3) -> Color:
		return cz["tip"] if p.y > _top_y(clampf(p.z, -0.38, 0.22)) + 0.06 else cz["bristle"])
	# Legs and cloven hooves.
	for i in 4:
		var front := i < 2
		var from := sm.size()
		sm.leg_tube(qd, i, LEG_FRONT if front else LEG_HIND, 10, 0.09)
		var hoof_from := sm.size()
		sm.paw_loft(qd, i, HOOF, 10)
		var sx := qd.leg_side[i]
		sm.paint(from, func(p: Vector3, n: Vector3) -> Color:
			if p.y < 0.075:
				return cz["hoof"]
			if n.x * sx < -0.4 and p.y > 0.25:
				return belly
			return side.darkened(0.15) if p.y < 0.3 else side)
		sm.paint(hoof_from, func(p: Vector3, _n: Vector3) -> Color:
			var j: PackedVector3Array = qd.rest_joints[i]
			return cz["hoof"].darkened(0.35) if absf(p.x - j[3].x) < 0.006 and p.z < j[3].z - 0.01 else cz["hoof"])
	# Tail with a tuft.
	var tail_from := sm.size()
	sm.tail_tube(qd, SPEC["tail_r"], 8)
	var tip_z: float = qd.rest_tail_pts[qd.tail_n].z
	var root_z: float = qd.rest_tail_pts[0].z
	sm.paint(tail_from, func(p: Vector3, _n: Vector3) -> Color:
		var u := (p.z - root_z) / maxf(tip_z - root_z, 0.01)
		return cz["bristle"] if u > 0.62 else side)
	# Head: wedge skull, pale cheek band, snout disc with nostrils, tusks, small ears, glowing eyes.
	var hinv := hx.affine_inverse()
	var head_from := sm.size()
	sm.head_loft(hx, HEAD, 16, 0.0, 0.01, qd.B_HEAD, 2.3, 2)
	var eye_c: Vector3 = SPEC["eye"]
	sm.paint(head_from, func(p: Vector3, n: Vector3) -> Color:
		var l := hinv * p
		var ln := (hinv.basis * n).normalized()
		if Vector3(absf(l.x), l.y, l.z).distance_to(Vector3(EYE_X, eye_c.y, eye_c.z)) < 0.032:
			return back
		if l.z < -0.34:
			return cz["snout"]
		if absf(ln.x) > 0.5 and l.y < 0.0 and l.z > -0.27:
			return cz["cheek"]
		if ln.y < -0.4:
			return belly
		return back if ln.y > 0.45 else side)
	var disc_from := sm.size()
	sm.mb.push(hx)
	sm.ellipsoid(Vector3(0, -0.026, -0.432), Vector3(0.068, 0.062, 0.02), 12, 5)
	sm.mb.pop()
	sm.rigid(qd.B_HEAD)
	sm.paint(disc_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["disc"])
	var nos_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		sm.ellipsoid(Vector3(0.024 * s, -0.032, -0.448), Vector3(0.013, 0.018, 0.007), 8, 4)
	sm.mb.pop()
	sm.rigid(qd.B_HEAD)
	sm.paint(nos_from, func(_p: Vector3, _n: Vector3) -> Color: return Color("140E0C"))
	var tusk_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		var a: Vector3 = TUSK[0]
		var b: Vector3 = TUSK[1]
		var c: Vector3 = TUSK[2]
		sm.spike(Vector3(a.x * s, a.y, a.z), Vector3(b.x * s, b.y, b.z), Vector3(c.x * s, c.y, c.z), 0.026, 0.02, Vector3.UP, 8, PackedFloat32Array([qd.B_HEAD, 1.0]), PackedFloat32Array(), 6)
	sm.mb.pop()
	sm.paint(tusk_from, func(_p: Vector3, _n: Vector3) -> Color: return cz["tusk"])
	for e in 2:
		var ex: Transform3D = qd.rest[qd.B_EAR_L + e]
		var ear_from := sm.size()
		sm.mb.push(ex)
		sm.ear(Vector3.ZERO, 0.09, 0.036, 0.11, 0.02, qd.B_EAR_L + e)
		sm.mb.pop()
		var einv := ex.affine_inverse()
		sm.paint(ear_from, func(_p: Vector3, n: Vector3) -> Color:
			return cz["ear_in"] if (einv.basis * n).normalized().z < -0.55 else back)
	var eye_from := sm.size()
	sm.mb.push(hx)
	for s in [-1.0, 1.0]:
		sm.almond(Vector3(EYE_X * s, eye_c.y, eye_c.z), Vector3(EYE_N.x * s, EYE_N.y, EYE_N.z).normalized(), s, 0.016, 0.0075, 0.15, qd.B_EYES, 0.008)
	sm.mb.pop()
	var ec: Color = cz["eye"]
	sm.paint(eye_from, func(_p: Vector3, _n: Vector3) -> Color: return Color(ec.r, ec.g, ec.b, 0.5))
	return sm.commit(qd.rest)


## Height of the back's top line at z (rest).
static func _top_y(z: float) -> float:
	for k in TORSO.size() - 1:
		var a: Array = TORSO[k]
		var b: Array = TORSO[k + 1]
		if z <= float(a[0]) and z >= float(b[0]):
			var f := (float(a[0]) - z) / maxf(float(a[0]) - float(b[0]), 1e-4)
			return lerpf(float(a[1]) + float(a[3]), float(b[1]) + float(b[3]), f)
	return 0.85
