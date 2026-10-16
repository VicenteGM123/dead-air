extends Node3D
## Objective animation metrics for RigHeracles (the acceptance numbers of docs/ANIMATION.md section 6).
## No window needed:
##   godot --headless --path . res://tools/anim_check.tscn [-- mode=loco|trans|strike|combo|ranges|pops|swap|perf|all gaits=run,sprint fps=60
##       csv=<abs dir> quiet=1]
## The rig is driven the way the hero drives it: moved along the world every step (rig.global_position and yaw),
## set_locomotion(speed, 6.2) and advance(dt), no velocity_hint, so its own velocity, acceleration and yaw-rate tracking
## sees real motion. Prints one line per check
##   ANIM <group> <gait> <metric> <value> <unit> [lo .. hi] PASS|FAIL|info
## and a summary "ANIM summary checks=N fail=M result=PASS|FAIL".
## Groups: loco (steady gaits: lean, counter-rotation, arms, head, bob, feet, joint ranges), trans (start, stop, turn,
## strafe: pops and foot sliding), strike (kinetic chain order of the blows), combo, ranges (joint limits over every action),
## pops (every state transition driven the way the hero drives it: joint rates and snaps, hand / foot / tip speeds; step 3).

const RUN_MAX := 6.2
const ACCEL := 40.0
const DECEL := 48.0
## A sole point under this height (m) is in contact with the ground.
const CONTACT_Y := 0.004
const HEEL := Vector3(0.0, -0.093, 0.075)
const TOE := Vector3(0.0, -0.093, -0.22)
const IMPACT_FPS := 30.0

var rig: RigHeracles
var dt := 1.0 / 60.0
var _checks := 0
var _fails := 0
var _quiet := false
var _csv := ""
var _step_t: Array[float] = []
var _clock := 0.0

## Acceptance targets: gait -> metric -> [lo, hi]. The same numbers are in docs/ANIMATION.md section 6.
var SPEC := {
	"idle": {"lean": [-3.0, 4.0], "bob_cm": [0.0, 2.0], "pel_yaw_amp": [0.0, 1.5], "slide_cm": [0.0, 1.0],
		"head_pitch_p2p": [0.0, 3.0]},
	"walk": {"lean": [2.0, 7.0], "pel_yaw_amp": [2.5, 6.5], "chest_ratio": [1.0, 3.0], "chest_corr": [-1.0, -0.6],
		"arm_amp": [14.0, 32.0], "arm_opp": [-1.0, -0.6], "shield_amp": [3.0, 16.0], "elbow_mean": [20.0, 60.0],
		"bob_cm": [1.5, 5.0], "bob_harm": [1.5, 1000000.0], "knee_peak": [45.0, 80.0], "slide_cm": [0.0, 2.0],
		"head_pitch_p2p": [0.0, 3.5], "head_yaw_p2p": [0.0, 5.0], "unreach_pct": [0.0, 3.0], "step_lag": [0.0, 0.05]},
	"run": {"lean": [8.0, 13.0], "pel_yaw_amp": [5.0, 9.5], "chest_ratio": [1.1, 3.0], "chest_corr": [-1.0, -0.6],
		"arm_amp": [28.0, 55.0], "arm_opp": [-1.0, -0.6], "shield_amp": [5.0, 18.0], "elbow_mean": [80.0, 108.0],
		"bob_cm": [3.0, 9.0], "bob_harm": [1.5, 1000000.0], "knee_peak": [85.0, 125.0], "slide_cm": [0.0, 2.0],
		"head_pitch_p2p": [0.0, 4.0], "head_yaw_p2p": [0.0, 6.0], "unreach_pct": [0.0, 3.0], "step_lag": [0.0, 0.05]},
	"sprint": {"lean": [18.0, 25.0], "pel_yaw_amp": [6.5, 11.5], "chest_ratio": [1.1, 3.0], "chest_corr": [-1.0, -0.6],
		"arm_amp": [36.0, 65.0], "arm_opp": [-1.0, -0.6], "shield_amp": [6.0, 20.0], "elbow_mean": [78.0, 105.0],
		"bob_cm": [3.5, 10.0], "bob_harm": [1.5, 1000000.0], "knee_peak": [105.0, 140.0], "slide_cm": [0.0, 2.0],
		"head_pitch_p2p": [0.0, 5.0], "head_yaw_p2p": [0.0, 7.0], "unreach_pct": [0.0, 3.0], "step_lag": [0.0, 0.05]},
}
## Speeds (m/s) of the gaits: walk / run (the keyboard's normal pace) / sprint, as in Hero.
const GAIT_SPEED := {"idle": 0.0, "walk": 2.2, "run": 6.2, "sprint": 9.0}
## Anatomical limits (degrees) every pose of every action must respect.
const LIMIT_ELBOW := [0.0, 150.0]
const LIMIT_WRIST_EXT := [-60.0, 70.0]
const LIMIT_WRIST_DEV := [-70.0, 30.0]
## The sword can not be pointed closer to the forearm's line than this (degrees): the oblique grip gives 25 and the ulnar
## deviation of the wrist 35, so 90 - 60 = 30 (a hand cannot do better); 2 degrees of measuring tolerance.
const LIMIT_BLADE_FOREARM := 28.0


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == k:
			return kv[1] if kv.size() > 1 else "1"
	return d


func _ready() -> void:
	_quiet = _arg("quiet", "0") == "1"
	_csv = _arg("csv", "")
	dt = 1.0 / float(_arg("fps", "60"))
	var mode := _arg("mode", "loco")
	var gaits := _arg("gaits", "idle,walk,run,sprint").split(",", false)
	await get_tree().process_frame
	if mode == "loco" or mode == "all":
		for g in gaits:
			_gait_check(g)
		_gait_extras()
		_gait_between()
	if mode == "trans" or mode == "all":
		_transitions()
	if mode == "strike" or mode == "all":
		_strikes()
	if mode == "combo" or mode == "all":
		_combo()
	if mode == "ranges" or mode == "all":
		_ranges()
	if mode == "pops" or mode == "all":
		_pops_all()
	if mode == "swap" or mode == "all":
		_swap()
	if mode == "perf":
		_perf()
	print("ANIM summary checks=%d fail=%d result=%s" % [_checks, _fails, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit()


# --- the rig ----------------------------------------------------------------------------------------------------

func _new_rig(outfit: StringName = &"helmet") -> void:
	if rig != null:
		rig.free()
	rig = RigHeracles.new()
	add_child(rig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.t = 0.0 # (a rig starts at a random time: the idle's breathing would differ from run to run)
	rig.cape_world = false
	rig.set_outfit(outfit)
	_step_t.clear()
	_clock = 0.0
	rig.event.connect(func(n: String) -> void:
		if n == "step":
			_step_t.append(_clock))


## One simulated stretch: segments [{t, v, a, turn, face, strafe, guard, state}]:
## t seconds, v the speed to reach (m/s) at `a` m/s^2 (default ACCEL up, DECEL down), turn = yaw rate (rad/s) applied to
## the facing AND the heading (a turn while running), face = yaw rate of the facing only (strafing round a target),
## strafe = the heading's angle to the facing (rad, + to the left; PI = back-pedalling), vy / vy_end = the vertical speed
## fed to the rig over the segment (a jump).
## Returns the recorded series (from `skip` seconds on).
func _simulate(segs: Array, skip: float = 0.0, guard: bool = false, outfit: StringName = &"helmet") -> Dictionary:
	_new_rig(outfit)
	rig.set_guard(guard)
	var S := {}
	var pos := Vector3.ZERO
	var facing := 0.0
	var head := 0.0 # heading of travel relative to the facing
	var heading_world := 0.0
	var speed := 0.0
	var cur_i := 0
	rig.global_position = pos
	rig.global_rotation = Vector3(0.0, facing, 0.0)
	rig.set_locomotion(0.0, RUN_MAX)
	# settle an idle rig first (as in game: it has stood for a while)
	for i in int(1.5 / dt):
		rig.advance(dt)
		_clock += dt
	_step_t.clear()
	_clock = 0.0
	var t_all := 0.0
	for seg in segs:
		var tt: float = seg["t"]
		var vt: float = seg["v"]
		var turn: float = seg.get("turn", 0.0)
		var face: float = seg.get("face", 0.0)
		var strafe: float = seg.get("strafe", 0.0)
		var acc: float = seg.get("a", ACCEL if vt > speed else DECEL)
		var st: StringName = seg.get("state", &"ground")
		if seg.has("guard"):
			rig.set_guard(seg["guard"])
		rig.set_motion_state(st)
		var vy0: float = seg.get("vy", 0.0)
		var vy1: float = seg.get("vy_end", vy0)
		var n := int(round(tt / dt))
		for k in n:
			rig.set_vertical_speed(lerpf(vy0, vy1, float(k) / float(maxi(n - 1, 1))))
			speed = move_toward(speed, vt, acc * dt)
			facing += (turn + face) * dt
			heading_world += turn * dt
			var dirv := Vector3(-sin(facing + strafe), 0.0, -cos(facing + strafe))
			if turn != 0.0 and absf(strafe) < 0.001:
				dirv = Vector3(-sin(facing), 0.0, -cos(facing))
			pos += dirv * speed * dt
			rig.global_position = pos
			rig.global_rotation = Vector3(0.0, facing, 0.0)
			rig.set_locomotion(speed, RUN_MAX)
			rig.advance(dt)
			_clock += dt
			t_all += dt
			if t_all >= skip:
				_record(S, speed)
			cur_i += 1
	return S


func _push(S: Dictionary, k: String, v: float) -> void:
	# (packed arrays are values: take it out of the dictionary so the append is in place)
	var a: PackedFloat32Array = S[k] if S.has(k) else PackedFloat32Array()
	S[k] = null
	a.append(v)
	S[k] = a


static func _yaw_of(b: Basis) -> float:
	var f := b * Vector3(0.0, 0.0, -1.0)
	return atan2(-f.x, -f.z)


## Forward lean of a bone's up axis (+ leaning forward).
static func _lean_of(b: Basis) -> float:
	var u := b * Vector3.UP
	return atan2(-u.z, u.y)


## Roll of a bone (+ right side up).
static func _roll_of(b: Basis) -> float:
	var r := b * Vector3.RIGHT
	return atan2(r.y, r.x)


static func _ang(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))


## Angle of rotation (rad, 0..PI) between two bases.
static func _rot_angle(a: Basis, b: Basis) -> float:
	var q := (b * a.inverse()).get_rotation_quaternion()
	var ang := q.get_angle()
	return minf(ang, TAU - ang)


## Right/left wrist extension and radial deviation (rad) and the twist about the forearm: the hand's rotation relative to
## the forearm in the rest frame (both bones are rotations from rest; zero = the rest wrist).
func _wrist(side: int) -> Vector3:
	var o := 0 if side == 0 else 4
	var fa: Basis = rig._bx[RigHeracles.FARM_R + o].basis
	var hd: Basis = rig._bx[RigHeracles.HAND_R + o].basis
	var rel := fa.inverse() * hd
	var s := 1.0 if side == 0 else -1.0
	var yf := (RigHeracles.mx(RigHeracles.P_WRIST, s) - RigHeracles.mx(RigHeracles.P_ELBOW, s)).normalized()
	var q := rel.get_rotation_quaternion()
	# swing-twist about the forearm axis
	var v := Vector3(q.x, q.y, q.z)
	var proj := yf * v.dot(yf)
	var tw := Quaternion(proj.x, proj.y, proj.z, q.w)
	var twist := 0.0
	if tw.length() > 1e-6:
		tw = tw.normalized()
		twist = tw.get_angle() * (1.0 if tw.get_axis().dot(yf) >= 0.0 else -1.0)
		if twist > PI:
			twist -= TAU
	var sw := q * tw.inverse() if tw.length() > 1e-6 else q
	var rv := sw.get_axis() * sw.get_angle() if sw.get_angle() < PI else sw.get_axis() * (sw.get_angle() - TAU)
	var bhat := RigHeracles.perp(Vector3(s, 0.0, 0.0), yf).normalized()
	var that := Vector3(0.0, 0.0, -1.0)
	that = RigHeracles.perp(that, yf).normalized()
	var a_fe := yf.cross(bhat).normalized()
	var a_dv := yf.cross(that).normalized()
	return Vector3(rv.dot(a_fe), rv.dot(a_dv), twist)


## Angle (rad) between the blade and the forearm's line (elbow to wrist) of the sword arm.
func _blade_forearm_angle(bl: PackedVector3Array) -> float:
	var bx: Array[Transform3D] = rig._bx
	var fa: Vector3 = bx[RigHeracles.HAND_R].origin - bx[RigHeracles.FARM_R].origin
	var bd: Vector3 = bl[1] - bl[0]
	if fa.length() < 1e-4 or bd.length() < 1e-4:
		return PI
	return acos(clampf(bd.normalized().dot(fa.normalized()), -1.0, 1.0))


func _record(S: Dictionary, speed: float) -> void:
	var bx: Array[Transform3D] = rig._bx
	var gt := rig.global_transform
	var pel: Transform3D = bx[RigHeracles.PELVIS]
	var chs: Transform3D = bx[RigHeracles.CHEST]
	var hdb: Transform3D = bx[RigHeracles.HEAD]
	var neck: Transform3D = bx[RigHeracles.NECK]
	_push(S, "t", _clock)
	_push(S, "speed", speed)
	_push(S, "pel_x", pel.origin.x)
	_push(S, "pel_y", pel.origin.y)
	_push(S, "pel_z", pel.origin.z)
	_push(S, "pel_yaw", _yaw_of(pel.basis))
	_push(S, "pel_roll", _roll_of(pel.basis))
	_push(S, "pel_lean", _lean_of(pel.basis))
	_push(S, "chs_yaw", _yaw_of(chs.basis))
	_push(S, "chs_roll", _roll_of(chs.basis))
	_push(S, "chs_lean", _lean_of(chs.basis))
	var tv := neck.origin - pel.origin
	_push(S, "trunk_lean", atan2(-tv.z, tv.y))
	var hc := hdb.origin + hdb.basis * (RigHeracles.HEAD_C - RigHeracles.P_HEAD)
	_push(S, "head_y", hc.y)
	_push(S, "head_z", hc.z)
	var hf := hdb.basis * Vector3(0.0, 0.0, -1.0)
	_push(S, "head_pitch", -asin(clampf(hf.y, -1.0, 1.0)))
	_push(S, "head_yaw", _yaw_of(hdb.basis))
	_push(S, "head_roll", _roll_of(hdb.basis))
	for side in 2:
		var o := 0 if side == 0 else 4
		var lo := 0 if side == 0 else 3
		var tag := "r" if side == 0 else "l"
		var S0: Vector3 = bx[RigHeracles.UARM_R + o].origin
		var E: Vector3 = bx[RigHeracles.FARM_R + o].origin
		var W: Vector3 = bx[RigHeracles.HAND_R + o].origin
		_push(S, "wr_%s_y" % tag, W.y)
		_push(S, "wr_%s_z" % tag, W.z)
		_push(S, "wr_%s_x" % tag, W.x)
		var d := chs.basis.inverse() * (E - S0)
		_push(S, "sh_%s" % tag, atan2(-d.z, -d.y))
		_push(S, "sh_ab_%s" % tag, atan2(d.x * (1.0 if side == 0 else -1.0), -d.y))
		_push(S, "el_%s" % tag, PI - _ang(S0 - E, W - E))
		var w := _wrist(side)
		_push(S, "wx_%s" % tag, w.x)
		_push(S, "wd_%s" % tag, w.y)
		_push(S, "wt_%s" % tag, w.z)
		var H: Vector3 = bx[RigHeracles.THIGH_R + lo].origin
		var K: Vector3 = bx[RigHeracles.SHIN_R + lo].origin
		var A: Vector3 = bx[RigHeracles.FOOT_R + lo].origin
		var fb: Basis = bx[RigHeracles.FOOT_R + lo].basis
		_push(S, "kn_%s" % tag, PI - _ang(H - K, A - K))
		var hd2 := pel.basis.inverse() * (K - H)
		_push(S, "hip_%s" % tag, atan2(-hd2.z, -hd2.y))
		var ff := fb * Vector3(0.0, 0.0, -1.0)
		_push(S, "fpitch_%s" % tag, asin(clampf(ff.y, -1.0, 1.0)))
		_push(S, "ank_%s_y" % tag, A.y)
		_push(S, "ank_%s_z" % tag, A.z)
		_push(S, "ank_%s_x" % tag, A.x)
		var hl := gt * (A + fb * HEEL)
		var tt := gt * (A + fb * TOE)
		_push(S, "heel_%s_x" % tag, hl.x)
		_push(S, "heel_%s_y" % tag, hl.y)
		_push(S, "heel_%s_z" % tag, hl.z)
		_push(S, "toe_%s_x" % tag, tt.x)
		_push(S, "toe_%s_y" % tag, tt.y)
		_push(S, "toe_%s_z" % tag, tt.z)
		_push(S, "cont_%s" % tag, 1.0 if minf(hl.y, tt.y) < CONTACT_Y else 0.0)
		# the ankle target of the pose vs the foot the solver reached: unreachable targets show here
		var tgt := Vector3(rig._pose[RigHeracles.C_FR if side == 0 else RigHeracles.C_FL],
			rig._pose[(RigHeracles.C_FR if side == 0 else RigHeracles.C_FL) + 1],
			rig._pose[(RigHeracles.C_FR if side == 0 else RigHeracles.C_FL) + 2])
		var fb0 := RigHeracles.eul(Vector3(rig._pose[(RigHeracles.C_FRR if side == 0 else RigHeracles.C_FLR)], rig._pose[(RigHeracles.C_FRR if side == 0 else RigHeracles.C_FLR) + 1], 0.0))
		var low0 := minf((fb0 * HEEL).y, (fb0 * TOE).y)
		tgt.y = maxf(tgt.y, -low0)
		_push(S, "unreach_%s" % tag, 1.0 if A.distance_to(tgt) > 0.012 and rig.action == "" else 0.0)
		_push(S, "short_%s" % tag, A.distance_to(tgt) if rig.action == "" else 0.0)
		_push(S, "lowest_%s" % tag, minf(hl.y, tt.y))
		var fs: Variant = rig.get("_ft_st")
		if fs != null:
			_push(S, "fst_%s" % tag, float(fs[side]))
			_push(S, "fkind_%s" % tag, float(rig.get("_ft_kind")[side]))
			_push(S, "fphi_%s" % tag, float(rig.get("_ft_phi")[side]))
	var bl := rig.blade_segment()
	_push(S, "bl_el", atan2(bl[1].y - bl[0].y, Vector2(bl[1].x - bl[0].x, bl[1].z - bl[0].z).length()))
	_push(S, "bl_fa", _blade_forearm_angle(bl))
	_push(S, "tip_x", bl[1].x)
	_push(S, "tip_y", bl[1].y)
	_push(S, "tip_z", bl[1].z)
	_push(S, "tip_rx", rig.global_transform.affine_inverse().basis.get_euler().x)


# --- series helpers ---------------------------------------------------------------------------------------------

static func _mean(a: PackedFloat32Array, i0: int = 0, i1: int = -1) -> float:
	if i1 < 0:
		i1 = a.size()
	var s := 0.0
	for i in range(i0, i1):
		s += a[i]
	return s / float(maxi(i1 - i0, 1))


static func _mn(a: PackedFloat32Array, i0: int = 0, i1: int = -1) -> float:
	if i1 < 0:
		i1 = a.size()
	var m := INF
	for i in range(i0, i1):
		m = minf(m, a[i])
	return m


static func _mx(a: PackedFloat32Array, i0: int = 0, i1: int = -1) -> float:
	if i1 < 0:
		i1 = a.size()
	var m := -INF
	for i in range(i0, i1):
		m = maxf(m, a[i])
	return m


static func _corr(a: PackedFloat32Array, b: PackedFloat32Array, i0: int, i1: int) -> float:
	var ma := _mean(a, i0, i1)
	var mb := _mean(b, i0, i1)
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in range(i0, i1):
		var x := a[i] - ma
		var y := b[i] - mb
		sab += x * y
		saa += x * x
		sbb += y * y
	if saa < 1e-12 or sbb < 1e-12:
		return 0.0
	return sab / sqrt(saa * sbb)


## Amplitude of the k-th harmonic of frequency f (Hz) in a[i0:i1] sampled at 1/dt.
func _harm(a: PackedFloat32Array, f: float, k: int, i0: int, i1: int) -> float:
	var m := _mean(a, i0, i1)
	var sc := 0.0
	var ss := 0.0
	for i in range(i0, i1):
		var ph := TAU * f * float(k) * float(i - i0) * dt
		sc += (a[i] - m) * cos(ph)
		ss += (a[i] - m) * sin(ph)
	return 2.0 * sqrt(sc * sc + ss * ss) / float(maxi(i1 - i0, 1))


static func _touchdowns(c: PackedFloat32Array) -> Array[int]:
	var out: Array[int] = []
	for i in range(1, c.size()):
		if c[i] > 0.5 and c[i - 1] < 0.5:
			out.append(i)
	return out


## Foot sliding: the largest drift (m) of a sole point from where it touched down while it stays under CONTACT_Y.
## Returns [worst, mean, runs]. Runs that touch the ends of the record are skipped.
func _slide(S: Dictionary, tag: String, i0: int = 0, i1: int = -1) -> Array:
	var worst := 0.0
	var total := 0.0
	var runs := 0
	if i1 < 0:
		i1 = (S["t"] as PackedFloat32Array).size()
	for pt in ["heel", "toe"]:
		var xs: PackedFloat32Array = S["%s_%s_x" % [pt, tag]]
		var ys: PackedFloat32Array = S["%s_%s_y" % [pt, tag]]
		var zs: PackedFloat32Array = S["%s_%s_z" % [pt, tag]]
		var i := i0
		while i < i1:
			if ys[i] < CONTACT_Y:
				var j := i
				var run_max := 0.0
				while j < i1 and ys[j] < CONTACT_Y:
					run_max = maxf(run_max, Vector2(xs[j] - xs[i], zs[j] - zs[i]).length())
					j += 1
				if i > i0 and j < i1:
					worst = maxf(worst, run_max)
					total += run_max
					runs += 1
					if _arg("slidelog", "0") == "1" and run_max > 0.015:
						var ex := ""
						if S.has("fst_" + tag):
							ex = " st=%d..%d kind=%d..%d phi=%.2f..%.2f" % [S["fst_" + tag][i], S["fst_" + tag][j - 1], S["fkind_" + tag][i], S["fkind_" + tag][j - 1], S["fphi_" + tag][i], S["fphi_" + tag][j - 1]]
						print("SLIDE %s %s t=%.2f len=%d max=%.1fcm%s" % [tag, pt, S["t"][i], j - i, run_max * 100.0, ex])
				i = j
			else:
				i += 1
	return [worst, total / float(maxi(runs, 1)), runs]


## Frames where a series jumps: |step| far above its typical step (a pop), with an absolute floor.
func _pops(a: PackedFloat32Array, floor_abs: float) -> int:
	var n := a.size()
	if n < 8:
		return 0
	var steps := PackedFloat32Array()
	for i in range(1, n):
		steps.append(absf(a[i] - a[i - 1]))
	var sorted := steps.duplicate()
	sorted.sort()
	var p90 := sorted[int(float(sorted.size()) * 0.9)]
	var c := 0
	for i in range(1, steps.size() - 1):
		var jerk := absf((a[i + 1] - a[i]) - (a[i] - a[i - 1]))
		if jerk > maxf(floor_abs, 3.0 * p90) and steps[i] > floor_abs:
			c += 1
	return c


## Pop count over a record: position series (floor in m) and angle series (floor in rad); logs the series with popslog=1.
func _pop_total(S: Dictionary, tag: String, pos_floor: float, ang_floor: float, big: bool = true) -> int:
	var total := 0
	var pos_keys := ["pel_y", "pel_x", "pel_z", "head_y", "ank_r_y", "ank_r_z", "ank_l_y", "ank_l_z"]
	var ang_keys := ["pel_yaw", "chs_yaw", "trunk_lean", "head_pitch", "head_yaw", "chs_roll", "pel_roll"]
	if big:
		pos_keys.append_array(["wr_r_y", "wr_r_z", "wr_l_y", "wr_l_z"])
		ang_keys.append_array(["sh_r", "sh_l", "el_r", "el_l", "kn_r", "kn_l", "fpitch_r", "fpitch_l"])
	for k in pos_keys:
		var pc := _pops(S[k], pos_floor)
		total += pc
		if pc > 0 and _arg("popslog", "0") == "1":
			print("POPS %s %s %d" % [tag, k, pc])
	for k in ang_keys:
		var pc := _pops(S[k], ang_floor)
		total += pc
		if pc > 0 and _arg("popslog", "0") == "1":
			print("POPS %s %s %d" % [tag, k, pc])
	return total


func _check(group: String, gait: String, metric: String, v: float, lo: float, hi: float, unit: String = "") -> void:
	_checks += 1
	var ok := v >= lo and v <= hi
	if not ok:
		_fails += 1
	if _quiet and ok:
		return
	print("ANIM %-6s %-9s %-16s %9.3f %-4s [%s .. %s] %s" % [group, gait, metric, v, unit, str(lo), str(hi), "PASS" if ok else "FAIL"])


func _info(group: String, gait: String, metric: String, v: float, unit: String = "") -> void:
	if not _quiet:
		print("ANIM %-6s %-9s %-16s %9.3f %-4s info" % [group, gait, metric, v, unit])


func _spec_check(group: String, gait: String, metric: String, v: float, unit: String = "") -> void:
	var sp: Dictionary = SPEC.get(gait, {})
	if sp.has(metric):
		_check(group, gait, metric, v, sp[metric][0], sp[metric][1], unit)
	else:
		_info(group, gait, metric, v, unit)


# --- steady gaits -------------------------------------------------------------------------------------------------

func _gait_segments(gait: String) -> Array:
	var v: float = GAIT_SPEED.get(gait, 0.0)
	return [{"t": 1.6 + (3.0 if v > 0.0 else 3.0), "v": v}]


func _gait_check(gait: String) -> void:
	var v: float = GAIT_SPEED.get(gait, 0.0)
	var S := _simulate(_gait_segments(gait), 1.6, false)
	_analyze_gait(S, gait, v)
	if _csv != "":
		_dump_csv(S, "gait_%s" % gait)


func _analyze_gait(S: Dictionary, gait: String, v: float, group: String = "loco") -> void:
	var n := (S["t"] as PackedFloat32Array).size()
	var cr: PackedFloat32Array = S["cont_r"]
	var cl: PackedFloat32Array = S["cont_l"]
	var tdr := _touchdowns(cr)
	var i0 := 0
	var i1 := n
	var f_cyc := 0.0
	if tdr.size() >= 3:
		i0 = tdr[0]
		i1 = tdr[tdr.size() - 1]
		f_cyc = float(tdr.size() - 1) / (float(i1 - i0) * dt)
	var deg := 180.0 / PI
	# --- posture
	_spec_check(group, gait, "lean", _mean(S["trunk_lean"], i0, i1) * deg, "deg")
	_info(group, gait, "chest_lean", _mean(S["chs_lean"], i0, i1) * deg, "deg")
	_info(group, gait, "pelvis_lean", _mean(S["pel_lean"], i0, i1) * deg, "deg")
	var pya := (_mx(S["pel_yaw"], i0, i1) - _mn(S["pel_yaw"], i0, i1)) * 0.5 * deg
	var cya := (_mx(S["chs_yaw"], i0, i1) - _mn(S["chs_yaw"], i0, i1)) * 0.5 * deg
	_spec_check(group, gait, "pel_yaw_amp", pya, "deg")
	_info(group, gait, "chest_yaw_amp", cya, "deg")
	if pya > 0.5:
		_spec_check(group, gait, "chest_ratio", cya / pya)
		_spec_check(group, gait, "chest_corr", _corr(S["pel_yaw"], S["chs_yaw"], i0, i1))
	_info(group, gait, "pel_roll_amp", (_mx(S["pel_roll"], i0, i1) - _mn(S["pel_roll"], i0, i1)) * 0.5 * deg, "deg")
	_info(group, gait, "chest_roll_amp", (_mx(S["chs_roll"], i0, i1) - _mn(S["chs_roll"], i0, i1)) * 0.5 * deg, "deg")
	# --- head
	_spec_check(group, gait, "head_pitch_p2p", (_mx(S["head_pitch"], i0, i1) - _mn(S["head_pitch"], i0, i1)) * deg, "deg")
	_spec_check(group, gait, "head_yaw_p2p", (_mx(S["head_yaw"], i0, i1) - _mn(S["head_yaw"], i0, i1)) * deg, "deg")
	_info(group, gait, "head_pitch_mean", _mean(S["head_pitch"], i0, i1) * deg, "deg")
	_info(group, gait, "head_y_p2p_cm", (_mx(S["head_y"], i0, i1) - _mn(S["head_y"], i0, i1)) * 100.0, "cm")
	# --- bob
	var bob := (_mx(S["pel_y"], i0, i1) - _mn(S["pel_y"], i0, i1)) * 100.0
	_spec_check(group, gait, "bob_cm", bob, "cm")
	if f_cyc > 0.0:
		var h1 := _harm(S["pel_y"], f_cyc, 1, i0, i1)
		var h2 := _harm(S["pel_y"], f_cyc, 2, i0, i1)
		_spec_check(group, gait, "bob_harm", h2 / maxf(h1, 1e-6))
		_info(group, gait, "cycle_hz", f_cyc, "Hz")
		_info(group, gait, "stride_m", v / f_cyc, "m")
		# duty factor: share of the cycle one foot is in contact
		var cs := 0.0
		for i in range(i0, i1):
			cs += cr[i]
		_info(group, gait, "duty", cs / float(i1 - i0))
		# flight: share of the cycle with no foot in contact
		var fl := 0.0
		for i in range(i0, i1):
			if cr[i] < 0.5 and cl[i] < 0.5:
				fl += 1.0
		_info(group, gait, "flight", fl / float(i1 - i0))
	# --- arms
	var sr: PackedFloat32Array = S["sh_r"]
	var sl: PackedFloat32Array = S["sh_l"]
	var arm_amp := (_mx(sr, i0, i1) - _mn(sr, i0, i1)) * 0.5 * deg
	var sh_amp := (_mx(sl, i0, i1) - _mn(sl, i0, i1)) * 0.5 * deg
	if v > 1.0:
		_spec_check(group, gait, "arm_amp", arm_amp, "deg")
		_spec_check(group, gait, "shield_amp", sh_amp, "deg")
		_spec_check(group, gait, "arm_opp", _corr(S["hip_r"], sr, i0, i1))
		_info(group, gait, "shield_opp", _corr(S["hip_l"], sl, i0, i1))
		_spec_check(group, gait, "elbow_mean", _mean(S["el_r"], i0, i1) * deg, "deg")
		_info(group, gait, "elbow_l_mean", _mean(S["el_l"], i0, i1) * deg, "deg")
		_info(group, gait, "elbow_r_range", (_mx(S["el_r"], i0, i1) - _mn(S["el_r"], i0, i1)) * deg, "deg")
		_info(group, gait, "arm_fwd_max", _mx(sr, i0, i1) * deg, "deg")
		_info(group, gait, "arm_back_max", _mn(sr, i0, i1) * deg, "deg")
		_info(group, gait, "wrist_r_z_amp", (_mx(S["wr_r_z"], i0, i1) - _mn(S["wr_r_z"], i0, i1)) * 50.0, "cm")
		_check(group, gait, "blade_up_max", _mx(S["bl_el"], i0, i1) * deg, -90.0, 52.0, "deg")
		_check(group, gait, "blade_dn_max", _mn(S["bl_el"], i0, i1) * deg, -60.0, 90.0, "deg")
	# --- legs
	var kp := maxf(_mx(S["kn_r"], i0, i1), _mx(S["kn_l"], i0, i1)) * deg
	if v > 1.0:
		_spec_check(group, gait, "knee_peak", kp, "deg")
	else:
		_info(group, gait, "knee_peak", kp, "deg")
	_info(group, gait, "knee_min", minf(_mn(S["kn_r"], i0, i1), _mn(S["kn_l"], i0, i1)) * deg, "deg")
	_info(group, gait, "hip_flex_max", _mx(S["hip_r"], i0, i1) * deg, "deg")
	_info(group, gait, "hip_ext_max", _mn(S["hip_r"], i0, i1) * deg, "deg")
	_info(group, gait, "foot_pitch_td", _mean(S["fpitch_r"], i0, i0 + 1) * deg, "deg")
	_info(group, gait, "foot_pitch_min", _mn(S["fpitch_r"], i0, i1) * deg, "deg")
	# --- feet: sliding, sinking, unreachable targets, step events
	var sl_r := _slide(S, "r", 0, n)
	var sl_l := _slide(S, "l", 0, n)
	var worst: float = maxf(sl_r[0], sl_l[0])
	_spec_check(group, gait, "slide_cm", worst * 100.0, "cm")
	_info(group, gait, "slide_mean_cm", (sl_r[1] + sl_l[1]) * 50.0, "cm")
	_info(group, gait, "contact_runs", float(sl_r[2] + sl_l[2]))
	var low := minf(_mn(S["lowest_r"]), _mn(S["lowest_l"]))
	_check(group, gait, "sole_min_mm", low * 1000.0, -10.0, 1000.0, "mm")
	var un := (_mean(S["unreach_r"], i0, i1) + _mean(S["unreach_l"], i0, i1)) * 50.0
	_spec_check(group, gait, "unreach_pct", un, "%")
	if v > 1.0:
		# every touchdown (either foot) has a step event within ~1.5 frames at 30 fps
		var tdl := _touchdowns(cl)
		var tds: Array[float] = []
		for k in tdr:
			tds.append(float(S["t"][k]))
		for k in tdl:
			tds.append(float(S["t"][k]))
		var worst_lag := 0.0
		var matched := 0
		var tot := 0
		for tdt in tds:
			if tdt < float(S["t"][0]) + 0.3 or tdt > float(S["t"][n - 1]) - 0.3:
				continue
			tot += 1
			var best := 9.0
			for st in _step_t:
				# the step list is on the simulation clock (from the first moving step)
				best = minf(best, absf(st - tdt))
			worst_lag = maxf(worst_lag, best)
			if best <= 0.05:
				matched += 1
		_spec_check(group, gait, "step_lag", worst_lag, "s")
		_info(group, gait, "step_match", float(matched) / float(maxi(tot, 1)))
	# --- joint ranges
	_check(group, gait, "elbow_r_min", _mn(S["el_r"]) * deg, LIMIT_ELBOW[0], LIMIT_ELBOW[1], "deg")
	_check(group, gait, "elbow_r_max", _mx(S["el_r"]) * deg, LIMIT_ELBOW[0], LIMIT_ELBOW[1], "deg")
	_check(group, gait, "elbow_l_max", _mx(S["el_l"]) * deg, LIMIT_ELBOW[0], LIMIT_ELBOW[1], "deg")
	# (the bone measure of the deviation is reported; the rule that is checked is the blade's angle to the forearm, 6.3)
	_info(group, gait, "wrist_r_dev_min", _mn(S["wd_r"]) * deg, "deg")
	_info(group, gait, "wrist_r_dev_max", _mx(S["wd_r"]) * deg, "deg")
	_check(group, gait, "blade_forearm_min", _mn(S["bl_fa"]) * deg, LIMIT_BLADE_FOREARM, 180.0, "deg")
	_check(group, gait, "wrist_r_ext_min", _mn(S["wx_r"]) * deg, LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
	_check(group, gait, "wrist_r_ext_max", _mx(S["wx_r"]) * deg, LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
	_check(group, gait, "wrist_l_ext_min", _mn(S["wx_l"]) * deg, LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
	_check(group, gait, "wrist_l_ext_max", _mx(S["wx_l"]) * deg, LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
	# --- smoothness: no frame pops in what the camera sees
	_check(group, gait, "pops", float(_pop_total(S, gait, 0.012, 0.05)), 0.0, 0.0)


# --- the other gaits and what rides on them ---------------------------------------------------------------------------

## Strafe, back-pedal, guard walk, the locked run, the brush pose: slide and pops only.
func _gait_extras() -> void:
	var cases := [
		["strafe_r", [{"t": 4.6, "v": 2.2, "strafe": -PI * 0.5}], false],
		["strafe_l", [{"t": 4.6, "v": 2.2, "strafe": PI * 0.5}], false],
		["back", [{"t": 4.6, "v": 1.8, "strafe": PI}], false],
		["guard_walk", [{"t": 4.6, "v": 2.6}], true],
		["lock_run", [{"t": 4.6, "v": 5.0}], false],
	]
	for c in cases:
		var S := _simulate(c[1], 1.6, c[2])
		var n := (S["t"] as PackedFloat32Array).size()
		var sr := _slide(S, "r", 0, n)
		var sl := _slide(S, "l", 0, n)
		_check("loco", c[0], "slide_cm", maxf(sr[0], sl[0]) * 100.0, 0.0, 2.0, "cm")
		_check("loco", c[0], "sole_min_mm", minf(_mn(S["lowest_r"]), _mn(S["lowest_l"])) * 1000.0, -10.0, 1000.0, "mm")
		_check("loco", c[0], "pops", float(_pop_total(S, c[0], 0.012, 0.05, false)), 0.0, 0.0)
		_info("loco", c[0], "lean", _mean(S["trunk_lean"]) * 180.0 / PI, "deg")
		if _csv != "":
			_dump_csv(S, "extra_%s" % c[0])
		# a strafing foot never crosses the other leg: lateral ankle distance stays above 8 cm
		var dmin := INF
		for i in n:
			dmin = minf(dmin, Vector2(S["ank_r_x"][i] - S["ank_l_x"][i], S["ank_r_z"][i] - S["ank_l_z"][i]).length())
		_check("loco", c[0], "feet_apart_cm", dmin * 100.0, 10.0, 99.0, "cm")


## The speeds between the gaits (a stick pushed half way): slide, sole, pops and unreachable ankles only.
func _gait_between() -> void:
	for v in [1.0, 1.6, 3.5, 4.5, 5.2, 7.5]:
		var S := _simulate([{"t": 4.6, "v": v}], 1.6, false)
		var n := (S["t"] as PackedFloat32Array).size()
		var tag := "v%s" % str(v).replace(".", "_")
		var sr := _slide(S, "r", 0, n)
		var sl := _slide(S, "l", 0, n)
		_check("loco", tag, "slide_cm", maxf(sr[0], sl[0]) * 100.0, 0.0, 2.0, "cm")
		_check("loco", tag, "sole_min_mm", minf(_mn(S["lowest_r"]), _mn(S["lowest_l"])) * 1000.0, -10.0, 1000.0, "mm")
		_check("loco", tag, "pops", float(_pop_total(S, tag, 0.012, 0.05, false)), 0.0, 0.0)
		var un := 0.0
		for i in n:
			un += S["unreach_r"][i] + S["unreach_l"][i]
		_check("loco", tag, "unreach_pct", un / float(n) * 50.0, 0.0, 3.0, "%")
		_info("loco", tag, "lean", _mean(S["trunk_lean"]) * 180.0 / PI, "deg")
		if _csv != "":
			_dump_csv(S, "between_%s" % tag)


# --- transitions ----------------------------------------------------------------------------------------------------

func _transitions() -> void:
	var deg := 180.0 / PI
	# start: idle -> run
	var S := _simulate([{"t": 0.5, "v": 0.0}, {"t": 2.5, "v": 6.2}], 0.0)
	var n := (S["t"] as PackedFloat32Array).size()
	var i_move := int(0.5 / dt)
	_check("trans", "start", "slide_cm", maxf(_slide(S, "r", 0, n)[0], _slide(S, "l", 0, n)[0]) * 100.0, 0.0, 5.0, "cm")
	# (a start is 0 -> 6.2 m/s in 0.15 s and a 180 degree turn 7.8 rad/s at full speed: beyond what a body does, so up to
	# two single-frame events - a foot's toe-off pitch, a dip of the pelvis - are let through; steady gaits allow none)
	_check("trans", "start", "pops", float(_pop_total(S, "start", 0.015, 0.06)), 0.0, 2.0)
	if _csv != "":
		_dump_csv(S, "start")
	var lean0 := _mean(S["trunk_lean"], 0, i_move)
	var peak := _mx(S["trunk_lean"], i_move, i_move + int(0.6 / dt))
	var steady := _mean(S["trunk_lean"], n - int(0.8 / dt), n)
	_info("trans", "start", "lean_peak", peak * deg, "deg")
	_check("trans", "start", "lean_gain", (peak - steady) * deg, 1.0, 14.0, "deg")
	_check("trans", "start", "lean_steady", steady * deg, 8.0, 13.0, "deg")
	var first_td := -1.0
	var tdr := _touchdowns(S["cont_r"])
	var tdl := _touchdowns(S["cont_l"])
	var cands: Array[int] = []
	for k in tdr:
		if k > i_move:
			cands.append(k)
			break
	for k in tdl:
		if k > i_move:
			cands.append(k)
			break
	if cands.size() > 0:
		cands.sort()
		first_td = float(cands[0] - i_move) * dt
	_check("trans", "start", "first_step_s", first_td, 0.0, 0.45, "s")
	_info("trans", "start", "lean_idle", lean0 * deg, "deg")
	# stop: run -> idle
	S = _simulate([{"t": 2.4, "v": 6.2}, {"t": 2.0, "v": 0.0}], 1.9)
	n = (S["t"] as PackedFloat32Array).size()
	_check("trans", "stop", "slide_cm", maxf(_slide(S, "r", 0, n)[0], _slide(S, "l", 0, n)[0]) * 100.0, 0.0, 5.0, "cm")
	_check("trans", "stop", "pops", float(_pop_total(S, "stop", 0.015, 0.06)), 0.0, 0.0)
	if _csv != "":
		_dump_csv(S, "stop")
	var min_lean := _mn(S["trunk_lean"], int(0.5 / dt), n)
	_info("trans", "stop", "lean_min", min_lean * deg, "deg")
	var end_lean := _mean(S["trunk_lean"], n - int(0.3 / dt), n)
	_check("trans", "stop", "lean_end", end_lean * deg, -4.0, 5.0, "deg")
	# both feet planted level and side by side at the end
	var cr := _mean(S["cont_r"], n - 20, n)
	var cl := _mean(S["cont_l"], n - 20, n)
	_check("trans", "stop", "feet_down", minf(cr, cl), 0.99, 1.0)
	# turn: run and turn 90 degrees (left) in 0.25 s, then 180 degrees in 0.4 s
	for tc in [["turn90", 0.25, PI * 0.5], ["turn180", 0.4, PI]]:
		S = _simulate([{"t": 2.4, "v": 6.2}, {"t": tc[1], "v": 6.2, "turn": tc[2] / tc[1]}, {"t": 1.4, "v": 6.2}], 1.9)
		n = (S["t"] as PackedFloat32Array).size()
		_check("trans", tc[0], "slide_cm", maxf(_slide(S, "r", 0, n)[0], _slide(S, "l", 0, n)[0]) * 100.0, 0.0, 6.0, "cm")
		_check("trans", tc[0], "pops", float(_pop_total(S, tc[0], 0.02, 0.08, false)), 0.0, 2.0 if tc[1] > 0.3 else 1.0)
		# roll into the turn (a left turn leans to the left: the right side up = positive chest roll)
		var i_t := int(0.5 / dt)
		var roll_pk := _mx(S["chs_roll"], i_t, i_t + int((tc[1] + 0.4) / dt))
		var roll_base := _mean(S["chs_roll"], 0, i_t)
		_check("trans", tc[0], "lean_into_deg", (roll_pk - roll_base) * deg, 1.5, 14.0, "deg")
		# head leads the turn: the head's yaw runs ahead of the pelvis's
		var lead := 0.0
		for i in range(i_t, i_t + int((tc[1] + 0.3) / dt)):
			lead = maxf(lead, S["head_yaw"][i] - S["pel_yaw"][i])
		_info("trans", tc[0], "head_lead", lead * deg, "deg")
		if _csv != "":
			_dump_csv(S, tc[0])
	# speed changes: walk -> run -> sprint -> walk (the keyboard's pace changes), and a stutter of short stops and starts
	S = _simulate([{"t": 1.5, "v": 2.2}, {"t": 1.5, "v": 6.2}, {"t": 1.5, "v": 9.0}, {"t": 1.5, "v": 2.2}, {"t": 1.0, "v": 6.2}], 1.0)
	n = (S["t"] as PackedFloat32Array).size()
	_check("trans", "gait_change", "slide_cm", maxf(_slide(S, "r", 0, n)[0], _slide(S, "l", 0, n)[0]) * 100.0, 0.0, 6.0, "cm")
	_check("trans", "gait_change", "pops", float(_pop_total(S, "gait_change", 0.02, 0.08, false)), 0.0, 2.0)
	var shortest := 0.0
	for i in n:
		shortest = maxf(shortest, maxf(S["short_r"][i], S["short_l"][i]))
	_check("trans", "gait_change", "foot_short_cm", shortest * 100.0, 0.0, 4.0, "cm")
	if _csv != "":
		_dump_csv(S, "gait_change")
	var st_segs: Array = []
	for k in 6:
		st_segs.append({"t": 0.35, "v": 6.2})
		st_segs.append({"t": 0.3, "v": 0.0})
	S = _simulate(st_segs, 0.0)
	n = (S["t"] as PackedFloat32Array).size()
	_check("trans", "stutter", "slide_cm", maxf(_slide(S, "r", 0, n)[0], _slide(S, "l", 0, n)[0]) * 100.0, 0.0, 6.0, "cm")
	_check("trans", "stutter", "pops", float(_pop_total(S, "stutter", 0.02, 0.08, false)), 0.0, 6.0)
	shortest = 0.0
	for i in n:
		shortest = maxf(shortest, maxf(S["short_r"][i], S["short_l"][i]))
	_check("trans", "stutter", "foot_short_cm", shortest * 100.0, 0.0, 6.0, "cm")
	if _csv != "":
		_dump_csv(S, "stutter")
	# jump: run, leave the ground, land running; and from standing
	for jc in [["jump_run", 6.2], ["jump_idle", 0.0]]:
		S = _simulate([{"t": 2.0 if jc[1] > 0.0 else 0.6, "v": jc[1]}, {"t": 0.62, "v": jc[1], "state": &"air", "vy": 5.0, "vy_end": -5.0, "a": 0.0},
			{"t": 1.4, "v": jc[1], "a": 0.0}], 1.9 if jc[1] > 0.0 else 0.3)
		n = (S["t"] as PackedFloat32Array).size()
		_check("trans", jc[0], "pops", float(_pop_total(S, jc[0], 0.02, 0.08, false)), 0.0, 3.0)
		var i_land := int(((0.1 if jc[1] > 0.0 else 0.3) + 0.62) / dt)
		var worst_un := 0.0
		for i in range(i_land + int(0.1 / dt), n):
			worst_un = maxf(worst_un, maxf(S["short_r"][i], S["short_l"][i]))
		_check("trans", jc[0], "foot_short_after_land_cm", worst_un * 100.0, 0.0, 4.0, "cm")
		_check("trans", jc[0], "slide_cm", maxf(_slide(S, "r", i_land + int(0.3 / dt), n)[0], _slide(S, "l", i_land + int(0.3 / dt), n)[0]) * 100.0, 0.0, 6.0, "cm")
		if _csv != "":
			_dump_csv(S, jc[0])
	if _csv != "":
		_dump_csv(S, "last_trans")


# --- strikes: the kinetic chain, the blade's arc, the feet -----------------------------------------------------------------------

## The hero's lunge into a blow (HeroMelee): from LUNGE_T0 to the first active frame (+0.04 s), a sine ease-out, `speed`
## times the authored time. The tool moves the rig the same way.
const LUNGE_T0 := 0.02
## HeroMelee.CARRY_DECEL: a blow out of a run with no foe in reach slows the run at this rate (m/s^2).
const CARRY_DECEL := 13.0
const STRIKE := {
	"attack1": {"speed": 1.05, "act0": 0.125, "act1": 0.29, "hips": [6.0, 14.0], "tip": 30.0, "open": 0.29},
	"attack2": {"speed": 1.05, "act0": 0.115, "act1": 0.28, "hips": [6.0, 14.0], "tip": 30.0, "open": 0.28},
	"attack3": {"speed": 1.0, "act0": 0.262, "act1": 0.42, "hips": [6.0, 14.0], "tip": 30.0, "open": 99.0},
	"heavy": {"speed": 1.0, "act0": 0.37, "act1": 0.68, "hips": [8.0, 28.0], "tip": 40.0, "open": 99.0}}
## Azimuth bins (10 degrees, from -180, + to the right) the OLD blows' blade (tip + 0.12 m and the 60 % point, 0.75 m or more
## from the hero, at most COVER_Y high: hero_melee's vertical band reaches 0.9 m under a point, so above 1.9 m nothing a foe
## stands on is touched) swept through in their active window (measured on the live 1bd425e animation, docs/ANIMATION.md 4.8).
const COVER_Y := 1.9
const OLD_COVER := {
	"attack1": [-180, -50, -40, -30, -20, -10], "attack2": [-30, -20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
	"attack3": [-20, -10, 0, 10, 20, 140, 150],
	"heavy": [-180, -170, -160, -150, -140, -130, -120, -110, -100, -90, -80, -70, -60, -50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90,
		100, 110, 120, 130, 140, 150, 160, 170]}
## The old blow's frontal part only matters (a foe behind the head was never aimed at): |azimuth| up to this many degrees.
const COVER_FRONT := 100.0


func _lunge_s(t: float, end: float) -> float:
	var u := clampf((t - LUNGE_T0) / maxf(end - LUNGE_T0, 0.05), 0.0, 1.0)
	return sin(u * PI * 0.5)


## Records one frame of a blow (or a combo) into the series S: blade, hand, pelvis, the chain's joints and their speeds, the
## shield arm, both feet. `prev` is the previous frame's joint orientations (returned updated).
func _sample_frame(S: Dictionary, prev: Dictionary, sdt: float, t_real: float, t_val: float) -> Dictionary:
	var bx: Array[Transform3D] = rig._bx
	var gt := rig.global_transform
	var pel: Basis = bx[RigHeracles.PELVIS].basis
	var chs: Basis = bx[RigHeracles.CHEST].basis
	var ua: Basis = bx[RigHeracles.UARM_R].basis
	var fa: Basis = bx[RigHeracles.FARM_R].basis
	var hd: Basis = bx[RigHeracles.HAND_R].basis
	var bl := rig.blade_segment()
	var tip: Vector3 = bl[1]
	var root: Vector3 = bl[0]
	var elb := PI - _ang(bx[RigHeracles.UARM_R].origin - bx[RigHeracles.FARM_R].origin, bx[RigHeracles.HAND_R].origin - bx[RigHeracles.FARM_R].origin)
	# (the tip's speed is the blade's own: relative to the hero, whose lunge or run carries the whole body along)
	var cur := {"hips": pel, "chest": chs, "shoulder": chs.inverse() * ua, "wrist": fa.inverse() * hd, "elbow": elb, "tip": tip - gt.origin}
	_push(S, "t", t_val)
	_push(S, "tr", t_real)
	_push(S, "tip_x", tip.x)
	_push(S, "tip_y", tip.y)
	_push(S, "tip_z", tip.z)
	_push(S, "root_x", root.x)
	_push(S, "root_y", root.y)
	_push(S, "root_z", root.z)
	# (about the hero: the blade's sweep is judged round him, wherever his lunge has taken him)
	_push(S, "ctip_x", tip.x - gt.origin.x)
	_push(S, "ctip_y", tip.y)
	_push(S, "ctip_z", tip.z - gt.origin.z)
	_push(S, "croot_x", root.x - gt.origin.x)
	_push(S, "croot_y", root.y)
	_push(S, "croot_z", root.z - gt.origin.z)
	var hp: Vector3 = bx[RigHeracles.HAND_R].origin
	var hw := gt * hp
	_push(S, "hand_x", hw.x)
	_push(S, "hand_y", hw.y)
	_push(S, "hand_z", hw.z)
	var cw := gt * bx[RigHeracles.PELVIS].origin
	_push(S, "pel_x", cw.x)
	_push(S, "pel_y", cw.y)
	_push(S, "pel_z", cw.z)
	_push(S, "elb_deg", elb * 180.0 / PI)
	_push(S, "bl_fa", _blade_forearm_angle(bl))
	var w := _wrist(0)
	_push(S, "wx", w.x * 180.0 / PI)
	_push(S, "wd", w.y * 180.0 / PI)
	_push(S, "wt", w.z * 180.0 / PI)
	if not prev.is_empty():
		for kk in ["hips", "chest", "shoulder", "wrist"]:
			_push(S, kk, _rot_angle(prev[kk], cur[kk]) / sdt)
		_push(S, "elbow", absf(cur["elbow"] - prev["elbow"]) / sdt)
		_push(S, "tipv", (cur["tip"] - prev["tip"]).length() / sdt)
	else:
		for kk in ["hips", "chest", "shoulder", "wrist", "elbow", "tipv"]:
			_push(S, kk, 0.0)
	# the shield arm: the direction of its upper arm in the chest's frame and how fast it turns (a counterweight, never frozen)
	var shd: Vector3 = (chs.inverse() * (bx[RigHeracles.FARM_L].origin - bx[RigHeracles.UARM_L].origin)).normalized()
	_push(S, "sh_x", shd.x)
	_push(S, "sh_y", shd.y)
	_push(S, "sh_z", shd.z)
	_push(S, "shv", _ang(prev["shd"], shd) / sdt if prev.has("shd") else 0.0)
	cur["shd"] = shd
	prev = cur
	# feet: the sole's lowest point, whether it is in contact, and the ankle the pose asked for against the one reached
	for side in 2:
		var o := 0 if side == 0 else 3
		var tag := "r" if side == 0 else "l"
		var fb: Basis = bx[RigHeracles.FOOT_R + o].basis
		var an: Vector3 = bx[RigHeracles.FOOT_R + o].origin
		var hl := gt * (an + fb * HEEL)
		var tt := gt * (an + fb * TOE)
		_push(S, "heel_%s_x" % tag, hl.x)
		_push(S, "heel_%s_y" % tag, hl.y)
		_push(S, "heel_%s_z" % tag, hl.z)
		_push(S, "toe_%s_x" % tag, tt.x)
		_push(S, "toe_%s_y" % tag, tt.y)
		_push(S, "toe_%s_z" % tag, tt.z)
		_push(S, "lowest_%s" % tag, minf(hl.y, tt.y))
		var oc := RigHeracles.C_FR if side == 0 else RigHeracles.C_FL
		var tg := Vector3(rig._pose[oc], rig._pose[oc + 1], rig._pose[oc + 2])
		var fb0 := RigHeracles.eul(Vector3(rig._pose[oc + 3], rig._pose[oc + 4], 0.0))
		tg.y = maxf(tg.y, -minf((fb0 * HEEL).y, (fb0 * TOE).y))
		# (a blow that turns the whole body, the heavy's spin: the ankle the pose asked for is turned with it)
		var rv := Vector3(rig._pose[RigHeracles.C_ROT], rig._pose[RigHeracles.C_ROT + 1], rig._pose[RigHeracles.C_ROT + 2])
		if rv.length_squared() > 1e-8:
			var rb := Basis(rv.normalized(), rv.length())
			var pv := Vector3(rig._pose[RigHeracles.C_PIV], rig._pose[RigHeracles.C_PIV + 1], rig._pose[RigHeracles.C_PIV + 2])
			tg = rb * tg + pv - rb * pv
		_push(S, "short_%s" % tag, an.distance_to(tg))
	return prev


## One blow as the hero plays it, at 120 Hz: the rig is moved along its lunge, the blow's pose and feet are recorded.
## The heavy is played the way HeroMelee does (charged: legs on the locomotion, held at 0.3 s, then released).
func _strike_series(act: String, lunge: float = 0.0, outfit: StringName = &"helmet", carry: float = 0.0) -> Dictionary:
	_new_rig(outfit)
	var sdt := 1.0 / float(_arg("strike_hz", "120")) # (the chain metrics are made for 120 Hz; strike_hz=30 plays the blow at the game's frame rate: look at the feet then)
	var fwd := Vector3(0.0, 0.0, -1.0)
	var origin := Vector3.ZERO
	rig.global_position = origin
	rig.global_rotation = Vector3.ZERO
	rig.set_locomotion(0.0, RUN_MAX)
	for i in int(1.5 / sdt):
		rig.advance(sdt)
	if carry > 0.0 and act != "heavy":
		# a blow out of a run: the hero runs up to `carry` m/s (the node moved each step, set_locomotion, as the hero does), and the blow
		# starts on the run (HeroMelee: with no foe the run carries on and slows at CARRY_DECEL; with `lunge` a foe is in reach: the
		# run is cut and the lunge curve takes over)
		var sp := 0.0
		for i in int(1.6 / sdt):
			sp = move_toward(sp, carry, ACCEL * sdt)
			origin += fwd * sp * sdt
			rig.global_position = origin
			rig.set_locomotion(sp, RUN_MAX)
			rig.advance(sdt)
	var cfg: Dictionary = STRIKE[act]
	var spd: float = cfg["speed"]
	var def_ev: Dictionary = RigHeracles.act_def(act)["ev"]
	var imp_t: float = float(def_ev["impact"])
	var lunge_end: float = float(cfg["act0"]) / spd + 0.04
	var events: Array = []
	rig.event.connect(func(n: String) -> void: events.append([n, rig.action_t, _clock]))
	if act == "heavy":
		rig.play_at("heavy", 1.0, true)
		rig.action_t = 0.1
		rig.action_hold = 0.3
		for i in int(0.4 / sdt):
			rig.advance(sdt)
		rig.play_at("heavy", 1.0, false)
		rig.action_hold = -1.0
		rig.action_t = 0.3
		lunge_end = 0.0
	else:
		rig.play_at(act, spd, false)
		# (HeroMelee: with no foe in reach a run is carried on and the legs stay on the gait; with one the hero stops and lunges)
		if rig.has_method("set_strike_run"):
			rig.set_strike_run(carry > 0.0 and lunge <= 0.0)
	var S := {}
	var prev := {}
	var t_real := 0.0
	_clock = 0.0
	events.clear()
	var total: float = (rig.action_len - rig.action_t) / spd + 0.12
	var n := int(total / sdt)
	var pos := origin
	var cv := carry if act != "heavy" else 0.0
	for k in n:
		t_real += sdt
		var step := Vector3.ZERO
		if lunge > 0.0 and lunge_end > LUNGE_T0:
			step = fwd * lunge * (_lunge_s(t_real, lunge_end) - _lunge_s(t_real - sdt, lunge_end))
		elif cv > 0.0:
			cv = maxf(cv - CARRY_DECEL * sdt, 0.0)
			step = fwd * cv * sdt
		pos += step
		rig.global_position = pos
		rig.set_locomotion(step.length() / sdt, RUN_MAX)
		rig.advance(sdt)
		_clock += sdt
		prev = _sample_frame(S, prev, sdt, t_real, rig.action_t if rig.action != "" else float(RigHeracles.act_def(act)["len"]))
	S["events"] = events
	S["imp_t"] = imp_t
	S["act"] = act
	return S


## The blade's azimuth bins (10 degrees from -180) covered while the blow is active (tip + 0.12 m and the 60 % point, 0.75 m or
## more from the hero): the same measure as OLD_COVER.
func _cover_bins(S: Dictionary, act: String) -> Array:
	var cfg: Dictionary = STRIKE[act]
	var a0: float = cfg["act0"]
	var a1: float = cfg["act1"]
	var tt: PackedFloat32Array = S["t"]
	var bins := {}
	for i in range(1, tt.size()):
		if tt[i] < a0 or tt[i] > a1:
			continue
		var tip0 := Vector3(S["ctip_x"][i - 1], S["ctip_y"][i - 1], S["ctip_z"][i - 1])
		var root0 := Vector3(S["croot_x"][i - 1], S["croot_y"][i - 1], S["croot_z"][i - 1])
		var tip1 := Vector3(S["ctip_x"][i], S["ctip_y"][i], S["ctip_z"][i])
		var root1 := Vector3(S["croot_x"][i], S["croot_y"][i], S["croot_z"][i])
		# the frame's sweep (the hit test sweeps the segment between two frames): 16 steps between the samples
		for s in 17:
			var u := float(s) / 16.0
			var tip := tip0.lerp(tip1, u)
			var root := root0.lerp(root1, u)
			var d := (tip - root).normalized()
			var ext := tip + d * 0.12
			for p in [ext, root + (ext - root) * 0.6]:
				var r := Vector2(p.x, p.z).length()
				if r >= 0.75 and p.y <= COVER_Y:
					var az := rad_to_deg(atan2(p.x, -p.z))
					bins[int(floor((az + 180.0) / 10.0)) % 36] = true
	var out: Array = []
	for b in bins:
		out.append(int(b) * 10 - 180)
	out.sort()
	return out


func _strikes() -> void:
	var acts := _arg("acts", "attack1,attack2,attack3,heavy").split(",", false)
	var lunge := float(_arg("lunge", "0"))
	var carry := float(_arg("carry", "0"))
	for a in acts:
		var def := RigHeracles.act_def(a)
		if def.is_empty() or not STRIKE.has(a):
			continue
		var cfg: Dictionary = STRIKE[a]
		var t_in: float = float(def["in"])
		var ev: Dictionary = def["ev"]
		var ti: Variant = ev.get("impact", float(def["len"]) * 0.4)
		var t_imp: float = float(ti[0]) if ti is Array else float(ti)
		var S := _strike_series(a, lunge, &"helmet", carry)
		if _csv != "":
			_dump_csv(S, "strike_%s" % a)
		var tt: PackedFloat32Array = S["t"]
		# (the entry blend, the first `in` seconds, carries the previous pose into the blow: it is not the blow)
		# (a rate is the turn between two frames: the window opens two frames after the blend ends, 0.02 s at 120 Hz, 0.033 s at 60 Hz)
		var w0 := maxf(t_imp - 0.2, (t_in + maxf(0.02, 2.0 / float(_arg("strike_hz", "120")))) if a != "heavy" else 0.3)
		var w1 := t_imp + 0.05
		var order := ["hips", "chest", "shoulder", "elbow", "wrist"]
		var peaks := {}
		var peak_v := {}
		for k in order + ["tipv"]:
			var best := -1.0
			var bt := 0.0
			var arr: PackedFloat32Array = S[k]
			for i in tt.size():
				if tt[i] >= w0 and tt[i] <= w1 and arr[i] > best:
					best = arr[i]
					bt = tt[i]
			peaks[k] = bt
			peak_v[k] = best
			_info("strike", a, "peak_%s_f" % k, (bt - t_imp) * IMPACT_FPS, "f")
		var hr: Array = cfg["hips"]
		_check("strike", a, "hips_peak_rads", float(peak_v["hips"]), hr[0], hr[1], "rad/s")
		_check("strike", a, "chest_over_hips", float(peak_v["chest"]) / maxf(float(peak_v["hips"]), 0.01), 1.0, 3.0)
		var viol := 0
		for i in range(1, order.size()):
			if (float(peaks[order[i]]) - float(peaks[order[i - 1]])) * IMPACT_FPS < -1.0:
				viol += 1
		_check("strike", a, "chain_violations", float(viol), 0.0, 0.0)
		var spread: float = (float(peaks["wrist"]) - float(peaks["hips"])) * IMPACT_FPS
		_check("strike", a, "chain_spread_f", spread, 2.0, 9.0, "f")
		# the blade tip's speed over the whole blow, from the end of the entry blend (a sword does not travel faster than a trained cut)
		var i0 := 0
		while i0 < tt.size() and tt[i0] < w0 - 0.0001:
			i0 += 1
		_check("strike", a, "tip_peak_ms", _mx(S["tipv"], i0), 0.0, float(cfg["tip"]), "m/s")
		_info("strike", a, "tip_peak_entry_ms", _mx(S["tipv"], 0, maxi(i0, 1)), "m/s")
		_check("strike", a, "elbow_max", _mx(S["elb_deg"]), LIMIT_ELBOW[0], LIMIT_ELBOW[1], "deg")
		_check("strike", a, "blade_forearm_min", _mn(S["bl_fa"]) * 180.0 / PI, LIMIT_BLADE_FOREARM, 180.0, "deg")
		_check("strike", a, "wrist_ext_min", _mn(S["wx"]), LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
		_check("strike", a, "wrist_ext_max", _mx(S["wx"]), LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
		# no pops: the hand's and the tip's paths have no frame jerk beyond what the arc itself has (the entry blend excluded)
		var pops := 0
		for k in ["tip", "hand", "pel"]:
			for c in ["x", "y", "z"]:
				var arr3: PackedFloat32Array = S["%s_%s" % [k, c]]
				pops += _pops(arr3.slice(i0), 0.05)
		_check("strike", a, "path_pops", float(pops), 0.0, 0.0)
		# the impact event comes on time (the authored second, within a frame at 30 fps)
		var ev_t := -1.0
		for e in S["events"]:
			if e[0] == "impact":
				ev_t = float(e[1])
		_check("strike", a, "impact_event_err_f", absf(ev_t - t_imp) * IMPACT_FPS if ev_t >= 0.0 else 99.0, 0.0, 1.0, "f")
		# the arc: the old blow's frontal azimuth bins are all still swept, and wider
		var cov := _cover_bins(S, a)
		var old_c: Array = OLD_COVER[a]
		var need := 0
		var have := 0
		for b in old_c:
			if a != "heavy" and absf(float(b) + 5.0) > COVER_FRONT:
				continue
			need += 1
			if cov.has(b):
				have += 1
		_check("strike", a, "arc_covered_of_old_pct", 100.0 * float(have) / float(maxi(need, 1)), 85.0, 100.0, "%")
		_info("strike", a, "arc_bins_new", float(cov.size()))
		# feet: no sole below the ground, no planted foot sliding, every ankle reached
		var low := minf(_mn(S["lowest_r"]), _mn(S["lowest_l"]))
		_check("strike", a, "sole_min_mm", low * 1000.0, -10.0, 1000.0, "mm")
		var slide := maxf(_slide(S, "r", i0)[0], _slide(S, "l", i0)[0])
		# (a lunge drags the body 0.8-2 m in 0.15-0.3 s: the rear foot pivots on its toe meanwhile, a few cm; a carried run keeps its legs on the gait)
		_check("strike", a, "slide_cm", slide * 100.0, 0.0, 2.0 if lunge <= 0.0 else 10.0, "cm")
		var unr := 0
		var nn := tt.size()
		for i in range(i0, nn):
			if S["short_r"][i] > 0.025 or S["short_l"][i] > 0.025:
				unr += 1
				if _arg("dbgu", "0") == "1":
					print("UNREACH %s i=%d of %d i0=%d short_r=%.3f short_l=%.3f keys=%s" % [a, i, nn, i0, S["short_r"][i], S["short_l"][i], str(S.keys().slice(0, 14))])
		_check("strike", a, "unreach_pct", 100.0 * float(unr) / float(maxi(nn - i0, 1)), 0.0, 3.0, "%")
		# the shield arm moves against the sword arm: at least 8 degrees either way over the blow, and never still
		var sx_: PackedFloat32Array = S["sh_x"]
		var sy_: PackedFloat32Array = S["sh_y"]
		var sz_: PackedFloat32Array = S["sh_z"]
		var rng_max := 0.0
		for ia in range(i0, nn, 4):
			for ib in range(ia, nn, 4):
				rng_max = maxf(rng_max, _ang(Vector3(sx_[ia], sy_[ia], sz_[ia]), Vector3(sx_[ib], sy_[ib], sz_[ib])))
		_check("strike", a, "shield_range_deg", rng_max * 180.0 / PI, 16.0, 180.0, "deg")
		var still := 0
		var tot := 0
		var last_i := tt.size() - 1
		while last_i > 0 and tt[last_i] >= float(RigHeracles.act_def(a)["len"]) - 0.0001 and tt[last_i - 1] >= float(RigHeracles.act_def(a)["len"]) - 0.0001:
			last_i -= 1
		for i in range(i0, last_i):
			tot += 1
			if S["shv"][i] < 0.06:
				still += 1
		_check("strike", a, "shield_still_pct", 100.0 * float(still) / float(maxi(tot, 1)), 0.0, 10.0, "%")


## The three light blows chained as the hero chains them (HeroMelee.start_light at the combo window: the next blow starts while the
## last one is still in its follow-through): the pelvis, the hand, the tip and the feet must flow from one into the next.
func _combo() -> void:
	var lunge := float(_arg("lunge", "0.4"))
	for lg in [0.0, lunge]:
		_new_rig()
		var sdt := 1.0 / 120.0
		for i in int(1.5 / sdt):
			rig.advance(sdt)
		rig.global_position = Vector3.ZERO
		rig.global_rotation = Vector3.ZERO
		var fwd := Vector3(0.0, 0.0, -1.0)
		var seq := [["attack1", 1.05, 0.29], ["attack2", 1.05, 0.28], ["attack3", 1.0, 99.0]]
		var S := {}
		var prev := {}
		var t_real := 0.0
		var marks: Array[int] = []
		for q in seq:
			var nm: String = q[0]
			var spd: float = q[1]
			var open: float = q[2]
			var cfg: Dictionary = STRIKE[nm]
			rig.play_at(nm, spd, false)
			marks.append((S["t"] as PackedFloat32Array).size() if S.has("t") else 0)
			var from_pos := rig.global_position
			var lunge_end: float = float(cfg["act0"]) / spd + 0.04
			var t_blow := 0.0
			var len := rig.action_len
			while rig.action == nm and rig.action_t < minf(open, len) and t_blow < 3.0:
				t_blow += sdt
				t_real += sdt
				if lg > 0.0:
					rig.global_position = from_pos + fwd * lg * _lunge_s(t_blow, lunge_end)
				rig.advance(sdt)
				prev = _sample_frame(S, prev, sdt, t_real, rig.action_t)
		# the last blow plays out, then 0.12 s of the blend back to the locomotion
		var tail := 0.0
		while tail < 0.12 + 0.01 and rig.action != "":
			t_real += sdt
			rig.advance(sdt)
			prev = _sample_frame(S, prev, sdt, t_real, rig.action_t)
		while tail < 0.12:
			tail += sdt
			t_real += sdt
			rig.advance(sdt)
			prev = _sample_frame(S, prev, sdt, t_real, rig.action_t)
		var tag := "lunge%.1f" % lg
		var tt: PackedFloat32Array = S["t"]
		var n := tt.size()
		var i0 := int(0.09 / sdt)
		var pops := 0
		for k in ["tip", "hand", "pel"]:
			for c in ["x", "y", "z"]:
				var arr3: PackedFloat32Array = S["%s_%s" % [k, c]]
				pops += _pops(arr3.slice(i0), 0.05)
		_check("combo", tag, "path_pops", float(pops), 0.0, 0.0)
		var low := minf(_mn(S["lowest_r"]), _mn(S["lowest_l"]))
		_check("combo", tag, "sole_min_mm", low * 1000.0, -10.0, 1000.0, "mm")
		var unr := 0
		for i in range(i0, n):
			if S["short_r"][i] > 0.015 or S["short_l"][i] > 0.015:
				unr += 1
		_check("combo", tag, "unreach_pct", 100.0 * float(unr) / float(maxi(n - i0, 1)), 0.0, 3.0, "%")
		# planted feet: no slide beyond the lunge's own push (the feet of a lunging blow are dragged along by it)
		var slide := maxf(_slide(S, "r", i0)[0], _slide(S, "l", i0)[0])
		_check("combo", tag, "slide_cm", slide * 100.0, 0.0, 2.0 if lg <= 0.0 else 8.0, "cm")
		# the speed of the hero's pelvis between frames never jumps (a blow flowing into the next one does not hitch)
		var maxstep := 0.0
		var pz: PackedFloat32Array = S["pel_z"]
		var py: PackedFloat32Array = S["pel_y"]
		for i in range(i0 + 1, n):
			maxstep = maxf(maxstep, absf(py[i] - py[i - 1]))
		_info("combo", tag, "pelvis_y_step_mm", maxstep * 1000.0, "mm")
		_info("combo", tag, "frames", float(n))
		if _csv != "":
			_dump_csv(S, "combo_%s" % tag)


# --- joint ranges over every action ---------------------------------------------------------------------------------------

func _ranges() -> void:
	var names := RigHeracles.act_names()
	names.sort()
	var only := _arg("acts", "")
	for a in names:
		if only != "" and not only.split(",").has(a):
			continue
		_new_rig()
		var sdt := 1.0 / 60.0
		for i in int(1.0 / sdt):
			rig.advance(sdt)
		var len := rig.play(a)
		var emin := INF
		var emax := -INF
		var xmin := INF
		var xmax := -INF
		var dmin := INF
		var dmax := -INF
		var bfmin := INF
		var t := 0.0
		while t < len + 0.2:
			# (the wrestle's start is never left to the gait: the hero plays the strain loop when it ends)
			if a == "grapple_start" and t >= len - sdt * 1.5 and rig.action == a:
				rig.play("grapple_loop")
			rig.advance(sdt)
			t += sdt
			bfmin = minf(bfmin, _blade_forearm_angle(rig.blade_segment()))
			var bx: Array[Transform3D] = rig._bx
			for side in 2:
				var o := 0 if side == 0 else 4
				var el := PI - _ang(bx[RigHeracles.UARM_R + o].origin - bx[RigHeracles.FARM_R + o].origin, bx[RigHeracles.HAND_R + o].origin - bx[RigHeracles.FARM_R + o].origin)
				emin = minf(emin, el)
				emax = maxf(emax, el)
				var w := _wrist(side)
				if _arg("verbose", "0") == "1" and (absf(w.x) * 57.3 > 60.0 or absf(w.y) * 57.3 > 70.0):
					print("RANGE %s t=%.3f side=%d wrist ext %.0f dev %.0f twist %.0f deg" % [a, t, side, w.x * 57.3, w.y * 57.3, w.z * 57.3])
				xmin = minf(xmin, w.x)
				xmax = maxf(xmax, w.x)
				dmin = minf(dmin, w.y)
				dmax = maxf(dmax, w.y)
		var deg := 180.0 / PI
		_check("range", a, "elbow_max", emax * deg, LIMIT_ELBOW[0], LIMIT_ELBOW[1], "deg")
		_check("range", a, "wrist_ext_min", xmin * deg, LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
		_check("range", a, "wrist_ext_max", xmax * deg, LIMIT_WRIST_EXT[0], LIMIT_WRIST_EXT[1], "deg")
		_info("range", a, "blade_forearm_min", bfmin * deg, "deg")
		_info("range", a, "wrist_dev_min", dmin * deg, "deg")
		_info("range", a, "wrist_dev_max", dmax * deg, "deg")


# --- pops: every state transition, joint by joint ---------------------------------------------------------------------------
## mode=pops. The rig is driven through scripted sequences of the transitions the hero makes (idle to sprint and back, a run
## into a blow and out of it, a combo, a blow into the guard, the parry, rolls from every speed, jumps and landings, a hit
## in every state, the spear's throw / pull / catch, the wrestle, the small ceremonies, the brush, air / swim / zip / hang)
## with the same calls the hero makes (hero.gd / hero_melee.gd: play, play_at, stop_action, set_guard, set_motion_state,
## set_locomotion every tick, the roll's displacement curve), and every frame of every joint is recorded:
##   * joint rate (rad/s): the angle the bone turns, relative to its parent (so the roll's whole-body spin is not a "fast
##     shoulder"), between two frames, over the frame time. It is compared with a limit per joint (PJ below).
##   * joint snap (rad/s^2): how much the rate changes from one frame to the next, over the frame time. A joint that goes
##     from rest to its limit in less than SNAP_TIME is a pop: the limit is rate limit / SNAP_TIME.
##   * the hands', feet's, head's and blade tip's speed (m/s, in the rig's frame) and their snap (m/s^2), the same way.
## Justification of the numbers (docs/ANIMATION.md 6.7): the limits are 1.2 to 1.5 times the fastest motion that the
## authored strikes and gaits reach on each joint (measured with this same tool on those clips, they pass), and the snap time
## is three frames at 60 Hz: the authored blows take 5-6 frames to go from rest to their peak speed at the shoulder.
## ANIM pops <seq> <metric> <value> <unit> [0 .. limit] PASS|FAIL, plus POPS lines naming the worst joint and the time.

## [name, bone, parent bone (-1: the rig), rate limit rad/s, snap limit rad/s^2]. How the limits were set (docs/ANIMATION.md 6.7):
## `calib=1` plays the four steady gaits and the four authored blows and prints the fastest and sharpest each joint is in them;
## a limit is never below 1.3 times that for the legs (the sprint) and the left arm; the trunk and the head, which the blows hardly
## move, are given the speed a hit may whip them at (15-25 rad/s); the sword arm is held to what a blow does to it. The authored
## interior of a blow (from 0.08 s into attack1/2/3/heavy, until it ends) is not judged here (`mode=strike` does, with the chain,
## the tip speed and the arcs); its entry and its exit are.
const PJ := [
	["pelvis", RigHeracles.PELVIS, -1, 32.0, 1900.0],
	["spine", RigHeracles.SPINE, RigHeracles.PELVIS, 15.0, 600.0],
	["chest", RigHeracles.CHEST, RigHeracles.SPINE, 20.0, 600.0],
	["neck", RigHeracles.NECK, RigHeracles.CHEST, 20.0, 600.0],
	["head", RigHeracles.HEAD, RigHeracles.NECK, 25.0, 900.0],
	["shoulder_r", RigHeracles.UARM_R, RigHeracles.CHEST, 40.0, 1800.0],
	["elbow_r", RigHeracles.FARM_R, RigHeracles.UARM_R, 40.0, 1700.0],
	["wrist_r", RigHeracles.HAND_R, RigHeracles.FARM_R, 40.0, 1400.0],
	["shoulder_l", RigHeracles.UARM_L, RigHeracles.CHEST, 35.0, 1800.0],
	["elbow_l", RigHeracles.FARM_L, RigHeracles.UARM_L, 35.0, 1500.0],
	["wrist_l", RigHeracles.HAND_L, RigHeracles.FARM_L, 40.0, 1400.0],
	["hip_r", RigHeracles.THIGH_R, RigHeracles.PELVIS, 40.0, 1500.0],
	["knee_r", RigHeracles.SHIN_R, RigHeracles.THIGH_R, 45.0, 2100.0],
	["ankle_r", RigHeracles.FOOT_R, RigHeracles.SHIN_R, 45.0, 1500.0],
	["hip_l", RigHeracles.THIGH_L, RigHeracles.PELVIS, 40.0, 1500.0],
	["knee_l", RigHeracles.SHIN_L, RigHeracles.THIGH_L, 45.0, 2100.0],
	["ankle_l", RigHeracles.FOOT_L, RigHeracles.SHIN_L, 45.0, 1500.0],
]
## Tracked points (rig frame): [name, speed limit m/s, snap limit m/s^2]
const PP := [["hand_r", 30.0, 1500.0], ["hand_l", 25.0, 1200.0], ["foot_r", 20.0, 900.0], ["foot_l", 20.0, 900.0], ["tip", 45.0, 2700.0],
	["head", 12.0, 900.0]]
## (calibration: a joint of the authored motion goes from rest to its peak rate in about this long, s; the snap limits above are
## what `calib=1` measures on those clips times 1.3.)
const SNAP_TIME := 0.05
## What a sequence is judged by: a ratio (the fastest joint over its limit, the sharpest over its snap limit) up to 1.0 is within what the
## known-good motion (the gaits and the four blows) does; between 1.0 and POP_CEIL it is an authored explosive motion (a throw's whip, a
## roll's start, a hit's snap-back) and is listed as "fast" (POPS lines, `pops_summary.py`), with its reason in docs/ANIMATION.md 6.7; above
## POP_CEIL it is a pop (a joint that flips, a hand that jumps) and fails. The ceiling is 1.5: the limits are 1.3 times the calibration, so
## 1.5 times a limit is 2 times what the blows and gaits do, where the explosive actions of docs/ANIMATION.md 6.7 peak.
const POP_CEIL := 1.5
## The whole-body rotation (a roll's tumble is 17-20 rad/s, the swim's pitch is slower): its limits.
const BODY_RATE := 26.0
const BODY_SNAP := 1500.0


## One recorded frame: every joint's rotation relative to its parent, the tracked points, what the rig was playing. The whole-body
## rotation (a roll, a fall, the swim and zip pitch: the `rot` channel) is taken out of the joints and the points, which are
## measured in the frame it rotates, and is recorded as a joint of its own ("body").
func _pop_frame(S: Dictionary) -> void:
	var bx: Array[Transform3D] = rig._bx
	var rv := Vector3(rig._pose[RigHeracles.C_ROT], rig._pose[RigHeracles.C_ROT + 1], rig._pose[RigHeracles.C_ROT + 2])
	var pv := Vector3(rig._pose[RigHeracles.C_PIV], rig._pose[RigHeracles.C_PIV + 1], rig._pose[RigHeracles.C_PIV + 2])
	var rb := Basis(rv.normalized(), rv.length()) if rv.length_squared() > 1e-8 else Basis.IDENTITY
	var root := Transform3D(rb, pv - rb * pv)
	var inv_root := root.affine_inverse()
	for j in PJ.size():
		var jd: Array = PJ[j]
		var b: Basis = inv_root.basis * bx[int(jd[1])].basis
		var par: int = int(jd[2])
		(S["q"][j] as Array).append(b if par < 0 else (inv_root.basis * bx[par].basis).inverse() * b)
	(S["body"] as Array).append(rb)
	var inv := rig.global_transform.affine_inverse()
	var bl := rig.blade_segment()
	S["p"]["hand_r"].append(inv_root * bx[RigHeracles.HAND_R].origin)
	S["p"]["hand_l"].append(inv_root * bx[RigHeracles.HAND_L].origin)
	S["p"]["foot_r"].append(inv_root * bx[RigHeracles.FOOT_R].origin)
	S["p"]["foot_l"].append(inv_root * bx[RigHeracles.FOOT_L].origin)
	S["p"]["tip"].append(inv_root * (inv * bl[1]))
	var hd: Transform3D = bx[RigHeracles.HEAD]
	S["p"]["head"].append(inv_root * (hd.origin + hd.basis * (RigHeracles.HEAD_C - RigHeracles.P_HEAD)))
	S["t"].append(_clock)
	S["act"].append(rig.action)
	S["at"].append(rig.action_t)
	S["bl"].append(rig._blend_t)
	S["pos"].append(rig.global_position)
	S["spd"].append(rig._spd)
	S["tw"].append(Vector2(rig._tw_fa[0], rig._tw_fa[1]))
	S["twd"].append(Vector4(rig._dbg_tw.x, rig._dbg_tw.y, rig._dbg_tw.z, rig._dbg_wb))
	S["wb2"].append(rig._dbg_wb2)
	if _arg("dbga", "") != "":
		# the left arm in the chest's frame: elbow, wrist, the elbow's flexion
		var cbx: Transform3D = bx[RigHeracles.CHEST]
		var ci := cbx.affine_inverse()
		var rt := _arg("dbga", "") == "r"
		var shp: Vector3 = ci * bx[RigHeracles.UARM_R if rt else RigHeracles.UARM_L].origin
		var elp: Vector3 = ci * bx[RigHeracles.FARM_R if rt else RigHeracles.FARM_L].origin
		var wrp: Vector3 = ci * bx[RigHeracles.HAND_R if rt else RigHeracles.HAND_L].origin
		var flex := (shp - elp).angle_to(wrp - elp)
		var hb: Basis = ci.basis * (bx[RigHeracles.HAND_R if rt else RigHeracles.HAND_L] as Transform3D).basis
		S["arm"].append([shp, elp, wrp, flex, hb, rig._dbg_wt])
	if _arg("dbgp", "") != "":
		S["pose"].append(rig._pose.duplicate())


## Runs `steps` through the rig. A step is a Dictionary:
##   t       seconds it lasts (at most, with `until`)
##   do      commands run once when the step starts, the hero's calls: [["play_at", act, speed, upper], ["play", act], ["guard", on],
##           ["stop", blend], ["srun", on], ["hold", t], ["atime", t], ["jolt", k], ["brush", k], ["aside", on]]
##   until   the step ends early: ["gone", act] (that action is over) or ["at", t] (the action's own time passed t)
##   v, a    the speed the hero goes to (m/s) and how fast (m/s^2; default ACCEL up, DECEL down)
##   vel     [kind, ...]: the speed over the step, replaces v / a: ["carry", v0, decel], ["lunge", end, dist], ["roll"], ["backstep"],
##           ["kick", v0, knock-back, decel] (a hit: the run slows at 28.8, the knock-back decays at 18), ["sum", a, b], ["zero"]
##   dir     the heading's angle to the facing (rad, PI = backwards)
##   turn    yaw rate (rad/s) of the facing and the heading
##   state, vy, vy_end   the rig's motion state and vertical speed (a jump)
func _pop_do(cmds: Array) -> void:
	for c in cmds:
		match String(c[0]):
			"play_at":
				rig.play_at(String(c[1]), float(c[2]), bool(c[3]))
			"play":
				rig.play(String(c[1]))
			"guard":
				rig.set_guard(bool(c[1]))
			"stop":
				rig.stop_action(float(c[1]))
			"srun":
				rig.set_strike_run(bool(c[1]))
			"hold":
				rig.action_hold = float(c[1])
			"atime":
				rig.action_t = float(c[1])
			"jolt":
				rig.guard_impact(float(c[1]))
			"brush":
				rig.set_brush(float(c[1]), 1.06)
			"aside":
				rig.set_weapons_aside(bool(c[1]))


func _pop_until(sp: Array) -> bool:
	match String(sp[0]):
		"gone":
			return rig.action != String(sp[1])
		"at":
			return rig.action_t >= float(sp[1])
	return false


func _pop_vel(sp: Array, tl: float) -> float:
	match String(sp[0]):
		"carry":
			return maxf(float(sp[1]) - float(sp[2]) * tl, 0.0)
		"lunge":
			return _lunge_speed(tl, float(sp[1]), float(sp[2]))
		"roll":
			return _roll_speed(tl)
		"backstep":
			var ml := Hero.BACKSTEP_TIME * 0.86
			return (Hero._dodge_s(tl / ml) - Hero._dodge_s(maxf(tl - dt, 0.0) / ml)) * Hero.BACKSTEP_DIST / dt
		"kick":
			return maxf(float(sp[1]) - 28.8 * tl, 0.0) - maxf(float(sp[2]) - 18.0 * tl, 0.0)
		"sum":
			return _pop_vel(sp[1], tl) + _pop_vel(sp[2], tl)
	return 0.0


func _pop_drive(steps: Array, outfit: StringName = &"helmet") -> Dictionary:
	_new_rig(outfit)
	# (plain Arrays: a packed array in a dictionary is a value, an append to a cast of it is lost)
	var S := {"t": [], "act": [], "at": [], "bl": [], "q": [], "p": {}, "pos": [], "spd": [], "marks": [], "pose": [], "body": [], "tw": [], "twd": [], "wb2": [], "arm": []}
	for j in PJ.size():
		(S["q"] as Array).append([])
	for pp in PP:
		S["p"][pp[0]] = []
	var pos := Vector3.ZERO
	var facing := 0.0
	var speed := 0.0
	rig.global_position = pos
	rig.global_rotation = Vector3.ZERO
	rig.set_locomotion(0.0, RUN_MAX)
	rig.set_ground(0.0, 0.0, Vector3.UP, false)
	for i in int(1.5 / dt):
		rig.advance(dt)
	_clock = 0.0
	var si := 0
	for st in steps:
		var tt: float = st.get("t", 0.5)
		if st.has("do"):
			_pop_do(st["do"])
		(S["marks"] as Array).append([_clock, str(st.get("name", "step%d" % si)), (S["t"] as Array).size()])
		var vt: float = st.get("v", speed)
		var acc: float = st.get("a", ACCEL if vt > speed else DECEL)
		var turn: float = st.get("turn", 0.0)
		var dir: float = st.get("dir", 0.0)
		var state: StringName = st.get("state", rig.motion_state)
		rig.set_motion_state(state)
		var vy0: float = st.get("vy", 0.0)
		var vy1: float = st.get("vy_end", vy0)
		var n := int(round(tt / dt))
		var tl := 0.0
		for k in n:
			tl += dt
			rig.set_vertical_speed(lerpf(vy0, vy1, float(k) / float(maxi(n - 1, 1))))
			if st.has("vel"):
				speed = _pop_vel(st["vel"], tl)
			else:
				speed = move_toward(speed, vt, acc * dt)
			facing += turn * dt
			var dirv := Vector3(-sin(facing + dir), 0.0, -cos(facing + dir))
			pos += dirv * speed * dt
			rig.global_position = pos
			rig.global_rotation = Vector3(0.0, facing, 0.0)
			rig.set_locomotion(absf(speed), RUN_MAX)
			rig.advance(dt)
			_clock += dt
			_pop_frame(S)
			if st.has("until") and _pop_until(st["until"]):
				break
		si += 1
	return S


## The roll's displacement along its path (Hero._roll_s against the rig's dodge time), as a speed.
func _roll_speed(tl: float) -> float:
	var k := 0.62 / Hero.ROLL_TIME
	var t0 := maxf(tl - dt, 0.0)
	return (Hero._roll_s(tl * k) - Hero._roll_s(t0 * k)) * Hero.ROLL_DIST / dt


## HeroMelee's lunge (a sine ease-out from LUNGE_T0 to `end`) as a speed (m/s) for a lunge of `dist` metres.
func _lunge_speed(tl: float, end: float, dist: float) -> float:
	return (_lunge_s(tl, end) - _lunge_s(tl - dt, end)) * dist / dt


## The sequences. Each is [name, steps]. They mirror what Hero and HeroMelee do (docs/ANIMATION.md 6.7).
func _pop_sequences() -> Array:
	var seqs: Array = []
	var A1_END := 0.125 / 1.05 + 0.04
	var A2_END := 0.115 / 1.05 + 0.04
	var A3_END := 0.262 + 0.04
	var ROLL := {"t": 0.55, "name": "roll", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]}
	# --- the gaits
	seqs.append(["idle_sprint_idle", [{"t": 0.6, "v": 0.0}, {"t": 2.0, "v": 9.0, "name": "sprint"}, {"t": 1.2, "v": 0.0, "name": "stop"}]])
	seqs.append(["walk_run_sprint_walk", [{"t": 1.2, "v": 2.2}, {"t": 1.5, "v": 6.2, "name": "run"}, {"t": 1.5, "v": 9.0, "name": "sprint"},
		{"t": 1.5, "v": 2.2, "name": "walk"}, {"t": 1.0, "v": 0.0, "name": "stop"}]])
	seqs.append(["turn_run", [{"t": 1.6, "v": 6.2}, {"t": 0.4, "v": 6.2, "turn": PI / 0.4, "name": "turn180"}, {"t": 1.2, "v": 6.2}]])
	seqs.append(["strafe_guard", [{"t": 0.4, "v": 0.0}, {"t": 0.3, "do": [["guard", true]], "name": "guard"},
		{"t": 1.5, "v": 2.6, "dir": -PI * 0.5, "name": "guard_strafe"}, {"t": 1.0, "v": 2.6, "dir": PI, "name": "guard_back"},
		{"t": 0.6, "v": 0.0, "do": [["guard", false]], "name": "guard_off"}]])
	# --- blows
	for sp in [["run", 6.2], ["sprint", 9.0]]:
		var v0: float = sp[1]
		seqs.append(["%s_attack1_stick" % sp[0], [{"t": 1.7, "v": v0},
			{"t": 1.2, "name": "attack1", "do": [["play_at", "attack1", 1.05, false], ["srun", true]], "vel": ["carry", v0, 13.0], "until": ["at", 0.38]},
			{"t": 1.5, "v": v0, "name": "stick_out", "do": [["stop", 0.12]]}]])
		seqs.append(["%s_attack1_end" % sp[0], [{"t": 1.7, "v": v0},
			{"t": 1.2, "name": "attack1", "do": [["play_at", "attack1", 1.05, false], ["srun", true]], "vel": ["carry", v0, 13.0], "until": ["gone", "attack1"]},
			{"t": 1.5, "v": v0, "name": "ended"}]])
	seqs.append(["run_attack3_end", [{"t": 1.7, "v": 6.2},
		{"t": 1.5, "name": "attack3", "do": [["play_at", "attack3", 1.0, false], ["srun", true]], "vel": ["carry", 6.2, 13.0], "until": ["gone", "attack3"]},
		{"t": 1.5, "v": 6.2, "name": "ended"}]])
	seqs.append(["idle_attack1_lunge", [{"t": 0.5, "v": 0.0},
		{"t": 1.0, "name": "attack1", "do": [["play_at", "attack1", 1.05, false], ["srun", false]], "vel": ["lunge", A1_END, 0.8], "until": ["gone", "attack1"]},
		{"t": 0.8, "v": 0.0, "name": "ended"}]])
	seqs.append(["combo123_idle", [{"t": 0.5, "v": 0.0},
		{"t": 1.0, "name": "attack1", "do": [["play_at", "attack1", 1.05, false]], "vel": ["lunge", A1_END, 0.6], "until": ["at", 0.29]},
		{"t": 1.0, "name": "attack2", "do": [["play_at", "attack2", 1.05, false]], "vel": ["lunge", A2_END, 0.5], "until": ["at", 0.28]},
		{"t": 1.2, "name": "attack3", "do": [["play_at", "attack3", 1.0, false]], "vel": ["lunge", A3_END, 0.6], "until": ["gone", "attack3"]},
		{"t": 0.8, "v": 0.0, "name": "ended"}]])
	seqs.append(["combo12_run", [{"t": 1.7, "v": 6.2},
		{"t": 1.0, "name": "attack1", "do": [["play_at", "attack1", 1.05, false], ["srun", true]], "vel": ["carry", 6.2, 13.0], "until": ["at", 0.29]},
		{"t": 1.0, "name": "attack2", "do": [["play_at", "attack2", 1.05, false], ["srun", false]],
			"vel": ["sum", ["carry", 2.4, 13.0], ["lunge", A2_END, 0.3]], "until": ["at", 0.37]},
		{"t": 1.5, "v": 6.2, "name": "stick_out", "do": [["stop", 0.12]]}]])
	seqs.append(["strike_guard", [{"t": 0.5, "v": 0.0},
		{"t": 1.0, "name": "attack1", "do": [["play_at", "attack1", 1.05, false]], "vel": ["lunge", A1_END, 0.5], "until": ["at", 0.30]},
		{"t": 1.2, "v": 0.0, "name": "guard", "do": [["guard", true]]},
		{"t": 0.5, "v": 0.0, "name": "guard_off", "do": [["guard", false]]}]])
	seqs.append(["strike3_guard", [{"t": 0.5, "v": 0.0},
		{"t": 1.2, "name": "attack3", "do": [["play_at", "attack3", 1.0, false]], "vel": ["lunge", A3_END, 0.5], "until": ["at", 0.5]},
		{"t": 1.0, "v": 0.0, "name": "guard", "do": [["guard", true]]},
		{"t": 0.5, "v": 0.0, "name": "guard_off", "do": [["guard", false]]}]])
	seqs.append(["heavy_charge_release", [{"t": 0.5, "v": 0.0},
		{"t": 0.7, "name": "charge", "do": [["play_at", "heavy", 1.0, true], ["hold", 0.3], ["atime", 0.1]]},
		{"t": 1.2, "v": 0.0, "name": "release", "do": [["play_at", "heavy", 1.0, false], ["hold", -1.0], ["atime", 0.3]], "until": ["gone", "heavy"]},
		{"t": 0.8, "v": 0.0, "name": "ended"}]])
	# --- guard and parry
	seqs.append(["guard_up_down", [{"t": 0.6, "v": 0.0}, {"t": 1.0, "name": "guard", "do": [["guard", true]]},
		{"t": 0.8, "name": "guard_off", "do": [["guard", false]]}]])
	seqs.append(["guard_walk", [{"t": 0.5, "v": 0.0}, {"t": 0.3, "name": "guard", "do": [["guard", true]]},
		{"t": 1.5, "v": 2.6, "name": "walk"}, {"t": 0.8, "v": 0.0, "name": "stop"},
		{"t": 0.6, "name": "guard_off", "do": [["guard", false]]}]])
	seqs.append(["parry_guard", [{"t": 0.5, "v": 0.0}, {"t": 0.6, "name": "guard", "do": [["guard", true]]},
		{"t": 1.2, "name": "parry", "do": [["play_at", "parry", 1.0, true]]},
		{"t": 0.6, "name": "guard_off", "do": [["guard", false]]}]])
	seqs.append(["parry_walk", [{"t": 0.5, "v": 0.0}, {"t": 1.0, "v": 2.6, "name": "guard_walk", "do": [["guard", true]]},
		{"t": 1.2, "v": 2.6, "name": "parry", "do": [["play_at", "parry", 1.0, true]]},
		{"t": 0.8, "v": 0.0, "name": "stop"}]])
	seqs.append(["guard_block_jolt", [{"t": 0.5, "v": 0.0}, {"t": 0.6, "name": "guard", "do": [["guard", true]]},
		{"t": 0.7, "name": "block", "do": [["jolt", 1.0]]}, {"t": 0.7, "name": "block2", "do": [["jolt", 1.3]]}]])
	# --- rolls and backsteps
	for sp in [["run", 6.2], ["sprint", 9.0]]:
		var v0: float = sp[1]
		seqs.append(["%s_roll_%s" % [sp[0], sp[0]], [{"t": 1.7, "v": v0}, ROLL, {"t": 1.5, "v": v0, "name": "run_again"}]])
	seqs.append(["idle_roll_idle", [{"t": 0.6, "v": 0.0}, ROLL, {"t": 1.0, "v": 0.0, "name": "idle"}]])
	seqs.append(["roll_roll", [{"t": 1.7, "v": 6.2}, {"t": 0.4, "name": "roll", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]},
		{"t": 0.55, "name": "roll2", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]}, {"t": 1.2, "v": 6.2, "name": "run"}]])
	seqs.append(["roll_attack", [{"t": 1.7, "v": 6.2},
		{"t": 0.40, "name": "roll", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]},
		{"t": 1.0, "name": "attack1", "do": [["play_at", "attack1", 1.05, false]], "vel": ["lunge", A1_END, 0.5], "until": ["gone", "attack1"]},
		{"t": 0.8, "v": 0.0, "name": "ended"}]])
	seqs.append(["roll_guard", [{"t": 1.7, "v": 6.2},
		{"t": 0.42, "name": "roll", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]},
		{"t": 0.3, "v": 0.0, "name": "guard", "do": [["guard", true], ["stop", 0.12]]}, {"t": 0.8, "v": 0.0, "name": "hold"}]])
	seqs.append(["backstep_idle", [{"t": 0.6, "v": 0.0},
		{"t": 0.42, "name": "backstep", "do": [["play_at", "backstep", 0.5 / Hero.BACKSTEP_TIME, false]], "dir": PI, "vel": ["backstep"]},
		{"t": 1.0, "v": 0.0, "name": "idle"}]])
	# --- jumps, falls, landings
	for sp in [["idle", 0.0], ["run", 6.2], ["sprint", 9.0]]:
		var v0: float = sp[1]
		seqs.append(["jump_%s" % sp[0], [{"t": 0.6 if v0 == 0.0 else 1.7, "v": v0},
			{"t": 0.66, "name": "air", "v": v0, "a": 0.0, "state": &"air", "do": [["play", "jump"]], "vy": 8.0, "vy_end": -11.0},
			{"t": 1.2, "v": v0, "a": 0.0, "name": "landed", "state": &"ground"}]])
	seqs.append(["fall_hard_land", [{"t": 1.7, "v": 6.2},
		{"t": 1.0, "name": "air", "v": 6.2, "a": 0.0, "state": &"air", "vy": 0.0, "vy_end": -16.0},
		{"t": 1.2, "v": 6.2, "a": 0.0, "name": "landed", "state": &"ground", "do": [["play", "land"]]},
		{"t": 0.6, "v": 6.2, "name": "run"}]])
	seqs.append(["fall_hard_land_idle", [{"t": 0.5, "v": 0.0},
		{"t": 1.0, "name": "air", "v": 0.0, "state": &"air", "vy": 0.0, "vy_end": -16.0},
		{"t": 1.2, "v": 0.0, "name": "landed", "state": &"ground", "do": [["play", "land"]]}]])
	seqs.append(["jump_roll", [{"t": 1.7, "v": 6.2},
		{"t": 0.3, "name": "air", "v": 6.2, "a": 0.0, "state": &"air", "do": [["play", "jump"]], "vy": 8.0, "vy_end": 2.0},
		{"t": 0.55, "name": "land_roll", "state": &"ground", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]},
		{"t": 1.2, "v": 6.2, "name": "run"}]])
	seqs.append(["run_fall_land_run", [{"t": 1.7, "v": 6.2},
		{"t": 0.5, "v": 6.2, "a": 0.0, "name": "air", "state": &"air", "vy": -1.0, "vy_end": -7.0},
		{"t": 1.2, "v": 6.2, "a": 0.0, "name": "landed", "state": &"ground"}]])
	# --- hits, in every state
	for hn in [["hit", 3.5, 0.27], ["hit_heavy", 8.0, 0.53]]:
		var nm: String = hn[0]
		var kb: float = hn[1]
		var ln: float = hn[2]
		for sp in [["idle", 0.0], ["run", 6.2], ["sprint", 9.0]]:
			var v0: float = sp[1]
			seqs.append(["%s_%s" % [nm, sp[0]], [{"t": 0.6 if v0 == 0.0 else 1.7, "v": v0},
				{"t": ln, "name": nm, "do": [["play", nm]], "vel": ["kick", v0, kb, 28.8]},
				{"t": 1.0, "v": 0.0, "name": "idle"}]])
		seqs.append(["%s_guard" % nm, [{"t": 0.5, "v": 0.0}, {"t": 0.6, "name": "guard", "do": [["guard", true]]},
			{"t": ln, "name": nm, "do": [["guard", false], ["play", nm]], "vel": ["kick", 0.0, kb, 28.8]}, {"t": 1.0, "v": 0.0, "name": "idle"}]])
		seqs.append(["%s_in_attack" % nm, [{"t": 0.5, "v": 0.0},
			{"t": 0.5, "name": "attack1", "do": [["play_at", "attack1", 1.05, false]], "vel": ["lunge", A1_END, 0.6], "until": ["at", 0.15]},
			{"t": ln, "name": nm, "do": [["play", nm]], "vel": ["kick", 0.0, kb, 28.8]}, {"t": 1.0, "v": 0.0, "name": "idle"}]])
		seqs.append(["%s_air" % nm, [{"t": 1.7, "v": 6.2},
			{"t": 0.3, "name": "air", "v": 6.2, "a": 0.0, "state": &"air", "do": [["play", "jump"]], "vy": 8.0, "vy_end": 3.0},
			{"t": ln, "name": nm, "v": 6.2, "a": 0.0, "state": &"air", "do": [["play", nm]], "vy": 3.0, "vy_end": -3.0},
			{"t": 0.5, "v": 0.0, "name": "fall", "state": &"air", "vy": -3.0, "vy_end": -8.0},
			{"t": 1.0, "v": 0.0, "name": "landed", "state": &"ground"}]])
	seqs.append(["hit_in_roll_end", [{"t": 1.7, "v": 6.2},
		{"t": 0.4, "name": "roll", "do": [["play_at", "dodge", 0.62 / Hero.ROLL_TIME, false]], "vel": ["roll"]},
		{"t": 0.27, "name": "hit", "do": [["play", "hit"]], "vel": ["kick", 0.0, 3.5, 28.8]}, {"t": 1.0, "v": 0.0, "name": "idle"}]])
	# --- the spear
	seqs.append(["throw_idle", [{"t": 0.6, "v": 0.0},
		{"t": 1.2, "name": "throw", "do": [["play_at", "throw", Hero.THROW_SPEED, false]], "until": ["gone", "throw"]}, {"t": 0.8, "v": 0.0, "name": "idle"}]])
	seqs.append(["throw_run", [{"t": 1.7, "v": 6.2},
		{"t": 1.2, "v": 6.2, "name": "throw", "do": [["play_at", "throw", Hero.THROW_SPEED, true]], "until": ["gone", "throw"]},
		{"t": 0.8, "v": 6.2, "name": "run"}]])
	seqs.append(["throw_catch_run", [{"t": 1.7, "v": 6.2},
		{"t": 1.2, "v": 6.2, "name": "throw", "do": [["play_at", "throw", Hero.THROW_SPEED, true]], "until": ["gone", "throw"]},
		{"t": 0.5, "v": 6.2, "name": "run"},
		{"t": 1.2, "v": 6.2, "name": "catch", "do": [["play_at", "catch", 1.0, true]], "until": ["gone", "catch"]}, {"t": 0.8, "v": 6.2, "name": "run2"}]])
	seqs.append(["throw_idle_then_pull", [{"t": 0.6, "v": 0.0},
		{"t": 1.2, "name": "throw", "do": [["play_at", "throw", Hero.THROW_SPEED, false]], "until": ["gone", "throw"]},
		{"t": 1.2, "v": 0.0, "name": "pull", "do": [["play_at", "pull", 1.15, false]], "until": ["gone", "pull"]}, {"t": 0.8, "v": 0.0, "name": "idle"}]])
	seqs.append(["pull_hold_release", [{"t": 0.6, "v": 0.0},
		{"t": 0.8, "name": "pull", "do": [["play_at", "pull", 1.0, true], ["hold", 0.5]]},
		{"t": 1.2, "v": 0.0, "name": "release", "do": [["hold", -1.0]], "until": ["gone", "pull"]}, {"t": 0.8, "v": 0.0, "name": "idle"}]])
	seqs.append(["recoil", [{"t": 0.6, "v": 0.0},
		{"t": 1.0, "name": "attack1", "do": [["play_at", "attack1", 1.05, false]], "until": ["at", 0.16]},
		{"t": 1.0, "v": 0.0, "name": "recoil", "do": [["play", "recoil"]], "until": ["gone", "recoil"]}, {"t": 0.8, "v": 0.0, "name": "idle"}]])
	# --- the wrestle, everyday and ceremonies
	seqs.append(["grapple", [{"t": 0.6, "v": 0.0},
		{"t": 1.0, "name": "start", "do": [["play", "grapple_start"], ["aside", true]], "until": ["gone", "grapple_start"]},
		{"t": 3.4, "name": "loop", "do": [["play", "grapple_loop"]]},
		{"t": 1.0, "name": "end", "do": [["play", "grapple_end"], ["aside", false]], "until": ["gone", "grapple_end"]},
		{"t": 0.8, "v": 0.0, "name": "idle"}]])
	for nm in ["interact", "pet", "don_skin", "victory"]:
		seqs.append([nm, [{"t": 0.6, "v": 0.0}, {"t": 3.0, "name": nm, "do": [["play", nm]], "until": ["gone", nm]}, {"t": 1.0, "v": 0.0, "name": "idle"}]])
	seqs.append(["interact_walk", [{"t": 1.0, "v": 2.2}, {"t": 0.3, "v": 0.0, "name": "stop"},
		{"t": 1.5, "v": 0.0, "name": "interact", "do": [["play", "interact"]], "until": ["gone", "interact"]}, {"t": 0.8, "v": 0.0, "name": "idle"}]])
	seqs.append(["death_idle", [{"t": 0.6, "v": 0.0}, {"t": 2.4, "v": 0.0, "name": "death", "do": [["play", "death"]]}]])
	seqs.append(["death_run", [{"t": 1.7, "v": 6.2}, {"t": 2.4, "v": 0.0, "name": "death", "do": [["play", "death"]]}]])
	seqs.append(["death_in_attack", [{"t": 0.6, "v": 0.0},
		{"t": 0.5, "name": "attack1", "do": [["play_at", "attack1", 1.05, false]], "until": ["at", 0.15]},
		{"t": 2.4, "v": 0.0, "name": "death", "do": [["play", "death"]]}]])
	# --- the free hand in the wheat
	seqs.append(["brush_walk", [{"t": 1.0, "v": 2.2}, {"t": 1.5, "v": 2.2, "name": "brush_on", "do": [["brush", 1.0]]},
		{"t": 1.2, "v": 6.2, "name": "run_brush"}, {"t": 1.2, "v": 2.2, "name": "walk_brush"},
		{"t": 1.0, "v": 2.2, "name": "brush_off", "do": [["brush", 0.0]]}]])
	seqs.append(["brush_guard", [{"t": 1.0, "v": 2.2}, {"t": 1.2, "v": 2.2, "name": "brush_on", "do": [["brush", 1.0]]},
		{"t": 1.0, "v": 2.2, "name": "guard", "do": [["guard", true]]}, {"t": 1.0, "v": 2.2, "name": "guard_off", "do": [["guard", false]]},
		{"t": 0.6, "v": 0.0, "name": "brush_off", "do": [["brush", 0.0]]}]])
	# --- the motion states: swim, the chain's zip and the hang
	seqs.append(["swim_in_out", [{"t": 1.0, "v": 2.2}, {"t": 1.6, "v": 2.2, "name": "swim", "state": &"swim"},
		{"t": 1.2, "v": 0.0, "name": "treading", "state": &"swim"}, {"t": 1.5, "v": 2.2, "name": "wade_out", "state": &"ground"}]])
	seqs.append(["zip_hang_drop", [{"t": 0.6, "v": 0.0},
		{"t": 0.6, "v": 9.0, "a": 30.0, "name": "zip", "state": &"zip"}, {"t": 0.3, "v": 1.0, "name": "arrive", "state": &"zip", "a": 40.0},
		{"t": 1.5, "v": 0.0, "name": "hang", "state": &"hang"},
		{"t": 0.5, "v": 0.0, "name": "drop", "state": &"air", "vy": -2.0, "vy_end": -5.0},
		{"t": 1.2, "v": 0.0, "name": "landed", "state": &"ground"}]])
	seqs.append(["zip_climb_idle", [{"t": 0.6, "v": 0.0},
		{"t": 0.5, "v": 8.0, "a": 30.0, "name": "zip", "state": &"zip"},
		{"t": 0.58, "v": 0.0, "name": "climb", "state": &"ground", "do": [["play", "climb"]], "until": ["gone", "climb"]}, {"t": 1.0, "v": 0.0, "name": "idle"}]])
	return seqs


## The per-joint rate and snap of a sequence; prints the worst of each as checks and, with verbose=1, every joint.
func _pop_report(name: String, S: Dictionary, table: Array, t_from: float = 0.0) -> void:
	var tt: Array = S["t"]
	var n := tt.size()
	if n < 4:
		return
	var verbose := _arg("verbose", "0") == "1"
	# the authored interior of a blow (see PJ): judged by mode=strike, not here (calib=1 keeps it: that is where the numbers come from)
	var interior := []
	for i in n:
		interior.append(_arg("calib", "0") != "1" and ["attack1", "attack2", "attack3", "heavy"].has(S["act"][i]) and float(S["at"][i]) >= 0.08)
	var w_rate := 0.0
	var w_rate_who := ""
	var w_rate_t := 0.0
	var w_snap := 0.0
	var w_snap_who := ""
	var w_snap_t := 0.0
	var rows := {}
	for j in PJ.size():
		var jd: Array = PJ[j]
		var qs: Array = S["q"][j]
		var lim: float = jd[3]
		var snap_lim: float = jd[4]
		var mx_rate := 0.0
		var mx_rate_t := 0.0
		var mx_snap := 0.0
		var mx_snap_t := 0.0
		var prev_rate := 0.0
		for i in range(1, n):
			if tt[i] < t_from:
				continue
			var rate := _rot_angle(qs[i - 1], qs[i]) / dt
			if interior[i]:
				prev_rate = rate
				continue
			if rate > mx_rate:
				mx_rate = rate
				mx_rate_t = tt[i]
			if i >= 2 and not interior[i - 1]:
				var snap := absf(rate - prev_rate) / dt
				if snap > mx_snap:
					mx_snap = snap
					mx_snap_t = tt[i]
			prev_rate = rate
		rows[jd[0]] = [mx_rate, mx_rate_t, mx_snap, mx_snap_t]
		if mx_rate / lim > w_rate:
			w_rate = mx_rate / lim
			w_rate_who = jd[0]
			w_rate_t = mx_rate_t
		if mx_snap / snap_lim > w_snap:
			w_snap = mx_snap / snap_lim
			w_snap_who = jd[0]
			w_snap_t = mx_snap_t
		if verbose:
			print("POPS %-24s %-11s rate %6.1f rad/s (%.0f deg/frame) @%.2f  snap %7.0f rad/s2 @%.2f" % [name, jd[0], mx_rate, rad_to_deg(mx_rate * dt), mx_rate_t, mx_snap, mx_snap_t])
	# the whole-body rotation (rot): rate and snap of its own
	var bq: Array = S["body"]
	var b_rate := 0.0
	var b_snap := 0.0
	var b_prev := 0.0
	for i in range(1, n):
		if tt[i] < t_from:
			continue
		var br := _rot_angle(bq[i - 1], bq[i]) / dt
		b_rate = maxf(b_rate, br)
		if i >= 2:
			b_snap = maxf(b_snap, absf(br - b_prev) / dt)
		b_prev = br
	rows["body"] = [b_rate, 0.0, b_snap, 0.0]
	if b_rate / BODY_RATE > w_rate:
		w_rate = b_rate / BODY_RATE
		w_rate_who = "body"
	if b_snap / BODY_SNAP > w_snap:
		w_snap = b_snap / BODY_SNAP
		w_snap_who = "body"
	var pw_speed := 0.0
	var pw_speed_who := ""
	var pw_speed_t := 0.0
	var pw_snap := 0.0
	var pw_snap_who := ""
	var pw_snap_t := 0.0
	for pp in PP:
		var ps: Array = S["p"][pp[0]]
		var lim: float = pp[1]
		var snap_lim: float = pp[2]
		var mx_v := 0.0
		var mx_v_t := 0.0
		var mx_s := 0.0
		var mx_s_t := 0.0
		var prev_v := 0.0
		for i in range(1, n):
			if tt[i] < t_from:
				continue
			var v: float = (ps[i] as Vector3).distance_to(ps[i - 1] as Vector3) / dt
			if interior[i]:
				prev_v = v
				continue
			if v > mx_v:
				mx_v = v
				mx_v_t = tt[i]
			if i >= 2 and not interior[i - 1]:
				var sn := absf(v - prev_v) / dt
				if sn > mx_s:
					mx_s = sn
					mx_s_t = tt[i]
			prev_v = v
		rows[pp[0]] = [mx_v, mx_v_t, mx_s, mx_s_t]
		if mx_v / lim > pw_speed:
			pw_speed = mx_v / lim
			pw_speed_who = pp[0]
			pw_speed_t = mx_v_t
		if mx_s / snap_lim > pw_snap:
			pw_snap = mx_s / snap_lim
			pw_snap_who = pp[0]
			pw_snap_t = mx_s_t
		if verbose:
			print("POPS %-24s %-11s speed %6.2f m/s (%.1f cm/frame) @%.2f  snap %7.0f m/s2 @%.2f" % [name, pp[0], mx_v, mx_v * dt * 100.0, mx_v_t, mx_s, mx_s_t])
	table.append([name, rows])
	# dbg=<joint or point>,<t0>,<t1>: every frame of that joint in the window (rate, rad/s, and the angle's axis)
	var dbg := _arg("dbg", "").split(",")
	if dbg.size() == 3:
		var tj := -1
		for j in PJ.size():
			if PJ[j][0] == dbg[0]:
				tj = j
		for i in range(1, n):
			if tt[i] < float(dbg[1]) or tt[i] > float(dbg[2]):
				continue
			if _arg("dbgp", "") != "":
				var parts := PackedStringArray()
				for chn in _arg("dbgp", "").split(","):
					var o: int = RigHeracles.CH[chn]
					var pz: PackedFloat32Array = S["pose"][i]
					var cnt := 1 if chn in ["grip", "ohl", "spr", "hood", "hlx", "hls", "hrs"] else 3
					var vals := PackedStringArray()
					for j in cnt:
						vals.append("%.2f" % pz[o + j])
					parts.append("%s=(%s)" % [chn, " ".join(vals)])
				print("DBGP t=%.3f %s" % [tt[i], " ".join(parts)])
			if tj >= 0:
				var qa: Basis = S["q"][tj][i - 1]
				var qb: Basis = S["q"][tj][i]
				var qd := (qb * qa.inverse()).get_rotation_quaternion()
				var ax := qd.get_axis() if qd.get_angle() > 1e-6 else Vector3.ZERO
				var eu := qb.get_euler() * (180.0 / PI)
				if _arg("dbga", "") != "":
					var am: Array = S["arm"][i]
					var ee: Vector3 = (am[1] as Vector3) - (am[0] as Vector3)
					var ww: Vector3 = (am[2] as Vector3) - (am[0] as Vector3)
					var hbb: Basis = am[4]
					print("  arm: elbow=(%.2f %.2f %.2f) wrist=(%.2f %.2f %.2f) |sw|=%.2f flex=%.0f deg  hand x=(%.2f %.2f %.2f) y=(%.2f %.2f %.2f) z=(%.2f %.2f %.2f) [chest space] target=(%.2f %.2f %.2f)" % [ee.x, ee.y, ee.z, ww.x, ww.y, ww.z, ww.length(), rad_to_deg(float(am[3])), hbb.x.x, hbb.x.y, hbb.x.z, hbb.y.x, hbb.y.y, hbb.y.z, hbb.z.x, hbb.z.y, hbb.z.z, (am[5] as Vector3).x, (am[5] as Vector3).y, (am[5] as Vector3).z])
				var twv: Vector2 = S["tw"][i]
				var tdv: Vector4 = S["twd"][i]
				print("  forearm twist r=%.0f l=%.0f deg  (to shield %.0f w %.2f, to hand %.0f, hand axis off the forearm by %.0f deg; wrist twist raw %.0f tracked %.0f swing %.0f)" % [rad_to_deg(twv.x), rad_to_deg(twv.y), tdv.x, tdv.y, tdv.z, tdv.w, (S["wb2"][i] as Vector3).x, (S["wb2"][i] as Vector3).y, (S["wb2"][i] as Vector3).z])
				print("DBG %s %s t=%.3f rate=%.1f rad/s axis=(%.2f %.2f %.2f) euler=(%.0f %.0f %.0f) action=%s at=%.3f blend=%.2f" % [name, dbg[0], tt[i], _rot_angle(qa, qb) / dt, ax.x, ax.y, ax.z, eu.x, eu.y, eu.z, S["act"][i], S["at"][i], S["bl"][i]])
			else:
				var pa: Vector3 = S["p"][dbg[0]][i - 1]
				var pb: Vector3 = S["p"][dbg[0]][i]
				print("DBG %s %s t=%.3f speed=%.2f m/s delta=(%.3f %.3f %.3f) action=%s at=%.3f blend=%.2f" % [name, dbg[0], tt[i], pa.distance_to(pb) / dt, pb.x - pa.x, pb.y - pa.y, pb.z - pa.z, S["act"][i], S["at"][i], S["bl"][i]])
	# (what the rig was doing at the worst frames, for the log)
	var ctx := func(tw: float) -> String:
		var best := 0
		for i in n:
			if absf(tt[i] - tw) < absf(tt[best] - tw):
				best = i
		var mk := ""
		for m in S["marks"]:
			if float(m[0]) <= tw + 1e-4:
				mk = m[1]
		return "[%s, action %s t=%.2f blend=%.2f]" % [mk, S["act"][best], S["at"][best], S["bl"][best]]
	_check("pops", name, "joint_rate_ratio", w_rate, 0.0, POP_CEIL)
	if w_rate > 1.0 or verbose:
		print("POPS %-24s fastest joint %s @%.2f %s" % [name, w_rate_who, w_rate_t, ctx.call(w_rate_t)])
	_check("pops", name, "joint_snap_ratio", w_snap, 0.0, POP_CEIL)
	if w_snap > 1.0 or verbose:
		print("POPS %-24s sharpest joint %s @%.2f %s" % [name, w_snap_who, w_snap_t, ctx.call(w_snap_t)])
	_check("pops", name, "point_speed_ratio", pw_speed, 0.0, POP_CEIL)
	if pw_speed > 1.0 or verbose:
		print("POPS %-24s fastest point %s @%.2f %s" % [name, pw_speed_who, pw_speed_t, ctx.call(pw_speed_t)])
	_check("pops", name, "point_snap_ratio", pw_snap, 0.0, POP_CEIL)
	if pw_snap > 1.0 or verbose:
		print("POPS %-24s sharpest point %s @%.2f %s" % [name, pw_snap_who, pw_snap_t, ctx.call(pw_snap_t)])


## The known-good motion the limits were calibrated on: the four steady gaits (after the first 1.5 s of the run) and the four
## authored blows played standing (after their entry blend). `calib=1` prints the maxima per joint and point; the limits in PJ and
## PP are 1.2-1.5 times these.
func _pops_calibrate() -> void:
	var table: Array = []
	var sets: Array = [["steady_idle", [{"t": 3.0, "v": 0.0}], 1.5], ["steady_walk", [{"t": 4.0, "v": 2.2}], 2.0],
		["steady_run", [{"t": 4.0, "v": 6.2}], 2.0], ["steady_sprint", [{"t": 4.0, "v": 9.0}], 2.0]]
	for a in [["attack1", 1.05, 0.125 / 1.05 + 0.04, 0.8], ["attack2", 1.05, 0.115 / 1.05 + 0.04, 0.6], ["attack3", 1.0, 0.262 + 0.04, 0.6]]:
		var nm: String = a[0]
		# (from 0.08 s into the blow: the entry blend, 0.06-0.07 s, is a transition and is judged as one)
		sets.append(["blow_" + nm, [{"t": 0.3, "v": 0.0}, {"t": 1.2, "name": nm, "do": [["play_at", nm, float(a[1]), false]], "vel": ["lunge", float(a[2]), float(a[3])], "until": ["gone", nm]}], 0.38])
	sets.append(["blow_heavy", [{"t": 0.3, "v": 0.0}, {"t": 0.6, "name": "charge", "do": [["play_at", "heavy", 1.0, true], ["hold", 0.3], ["atime", 0.1]]},
		{"t": 1.2, "v": 0.0, "name": "release", "do": [["play_at", "heavy", 1.0, false], ["hold", -1.0], ["atime", 0.3]], "until": ["gone", "heavy"]}], 0.98])
	for st in sets:
		var S := _pop_drive(st[1])
		_pop_report("calib_" + st[0], S, table, float(st[2]))
	var worst := {}
	for row in table:
		for k in (row[1] as Dictionary).keys():
			var v: Array = row[1][k]
			if not worst.has(k):
				worst[k] = [0.0, "", 0.0, "", 0.0]
			if float(v[0]) > float(worst[k][0]):
				worst[k][0] = v[0]
				worst[k][1] = row[0]
			if float(v[2]) > float(worst[k][2]):
				worst[k][2] = v[2]
				worst[k][3] = row[0]
	for jd in PJ:
		var w: Array = worst[jd[0]]
		print("CALIB %-11s max rate %6.1f rad/s (%s)  limit %5.1f | max snap %7.0f rad/s2 (%s)  limit %6.0f" % [jd[0], w[0], w[1], jd[3], w[2], w[3], jd[4]])
	for pp in PP:
		var w: Array = worst[pp[0]]
		print("CALIB %-11s max speed %6.2f m/s (%s)  limit %5.1f | max snap %7.0f m/s2 (%s)  limit %6.0f" % [pp[0], w[0], w[1], pp[1], w[2], w[3], pp[2]])


## mode=pops: every sequence, the table of the per-joint maxima (csv=<dir> writes pops_table.csv).
func _pops_all() -> void:
	if _arg("calib", "0") == "1":
		_pops_calibrate()
		return
	var only := _arg("seq", "")
	var table: Array = []
	for sq in _pop_sequences():
		if only != "" and not only.split(",").has(sq[0]):
			continue
		var S := _pop_drive(sq[1])
		_pop_report(sq[0], S, table)
	# the table: max deg per frame of each joint over all the sequences
	var worst := {}
	for row in table:
		for k in (row[1] as Dictionary).keys():
			var v: Array = row[1][k]
			if not worst.has(k) or float(v[0]) > float(worst[k][0]):
				worst[k] = [v[0], row[0], v[1], v[2]]
	for jd in PJ:
		var w: Array = worst.get(jd[0], [0.0, "", 0.0, 0.0])
		_info("pops", "max", "%s_rate" % jd[0], float(w[0]), "rad/s")
		if _arg("verbose", "0") == "1":
			print("POPS max %-11s %6.1f rad/s = %5.1f deg/frame at %.0f Hz (%s @%.2f), snap %.0f rad/s2" % [jd[0], w[0], rad_to_deg(float(w[0]) * dt), 1.0 / dt, w[1], w[2], w[3]])
	for pp in PP:
		var w: Array = worst.get(pp[0], [0.0, "", 0.0, 0.0])
		_info("pops", "max", "%s_speed" % pp[0], float(w[0]), "m/s")
	if _csv != "":
		DirAccess.make_dir_recursive_absolute(_csv)
		var f := FileAccess.open("%s/pops_table.csv" % _csv, FileAccess.WRITE)
		if f != null:
			var head := PackedStringArray(["sequence"])
			var keys: Array = []
			for jd in PJ:
				keys.append(jd[0])
			for pp in PP:
				keys.append(pp[0])
			for k in keys:
				head.append("%s_rate_or_speed" % k)
				head.append("%s_snap" % k)
			f.store_line(",".join(head))
			for row in table:
				var line := PackedStringArray([row[0]])
				for k in keys:
					var v: Array = row[1][k]
					line.append("%.2f" % float(v[0]))
					line.append("%.0f" % float(v[2]))
				f.store_line(",".join(line))
			f.close()


# --- perf: what advance() costs -----------------------------------------------------------------------------------------------
## mode=perf. The mean and the worst cost (ms) of one `advance(1/60)` standing, running, sprinting and in a throw, a blow, a roll, the air
## (headless: the rig's own solve, no drawing; the machine is shared, so look at the order, not the decimals).
func _perf() -> void:
	for st in [["idle", 0.0, ""], ["run", 6.2, ""], ["sprint", 9.0, ""], ["attack1", 0.0, "attack1"], ["throw", 0.0, "throw"], ["dodge", 0.0, "dodge"],
			["hit", 0.0, "hit"], ["air", 6.2, "jump"]]:
		_new_rig()
		rig.set_locomotion(float(st[1]), RUN_MAX)
		var pos := Vector3.ZERO
		for i in 120:
			pos += Vector3(0.0, 0.0, -float(st[1]) * dt)
			rig.global_position = pos
			rig.set_locomotion(float(st[1]), RUN_MAX)
			rig.advance(dt)
		var tot := 0.0
		var worst := 0.0
		var n := 0
		for rep in 6:
			if String(st[2]) != "":
				rig.play(String(st[2]))
				if String(st[0]) == "air":
					rig.set_motion_state(&"air")
			for i in 50:
				pos += Vector3(0.0, 0.0, -float(st[1]) * dt)
				rig.global_position = pos
				rig.set_locomotion(float(st[1]), RUN_MAX)
				var t0 := Time.get_ticks_usec()
				rig.advance(dt)
				var us := float(Time.get_ticks_usec() - t0) / 1000.0
				tot += us
				worst = maxf(worst, us)
				n += 1
			rig.set_motion_state(&"ground")
		_info("perf", String(st[0]), "advance_mean_ms", tot / float(n), "ms")
		_info("perf", String(st[0]), "advance_worst_ms", worst, "ms")


# --- swap: the spear changes hands --------------------------------------------------------------------------------------------
## mode=swap. The spear on the back and the spear in the left fist are two models: the throw swaps them when the hand has closed on the
## shaft (RigHeracles.THROW_GRAB), the catch when it has strapped it on (CATCH_STOW). For the swap not to show, the two must be the same
## spear there: the fist on the shaft's place (<= 2 cm), the same axis (<= 3 degrees) and the same roll about it (<= 6 degrees: the leaf
## head's broad side). Both outfits (the lion's pelt carries the spear lower).
func _swap() -> void:
	for outfit in [&"helmet", &"lion"]:
		for a in [["throw", RigHeracles.THROW_GRAB], ["catch", RigHeracles.CATCH_STOW]]:
			_new_rig(outfit)
			rig.set_locomotion(0.0, RUN_MAX)
			for i in int(1.5 / dt):
				rig.advance(dt)
			rig.play_at(String(a[0]), 1.0, false)
			rig.action_hold = float(a[1])
			for i in int(1.5 / dt):
				rig.advance(dt)
			var hand: Transform3D = rig._spear_hand.global_transform
			var back: Transform3D = rig._spear_back.global_transform
			var dpos := hand.origin.distance_to(back.origin)
			var dax := rad_to_deg(hand.basis.z.angle_to(back.basis.z))
			# the roll: the broad side's direction (x) of both, across the shaft
			var hx := hand.basis.x - back.basis.z * hand.basis.x.dot(back.basis.z)
			var bx := back.basis.x - back.basis.z * back.basis.x.dot(back.basis.z)
			var droll := rad_to_deg(hx.angle_to(bx)) if hx.length() > 1e-3 and bx.length() > 1e-3 else 0.0
			var nm := "%s_%s" % [a[0], outfit]
			if _arg("verbose", "0") == "1":
				# (what the spear's roll direction, RigHeracles.SPEAR_ROLL, would have to be for the roll to match exactly)
				var pv: Node3D = rig._piv["spear_s"]
				var want := pv.global_transform.basis.inverse() * hand.basis.x
				print("SWAP %s the hand's roll direction in the back spear's frame: Vector3(%.2f, %.2f, %.2f)" % [nm, want.x, want.y, want.z])
			_check("swap", nm, "spear_position_cm", dpos * 100.0, 0.0, 2.0)
			_check("swap", nm, "spear_axis_deg", dax, 0.0, 3.0)
			_check("swap", nm, "spear_roll_deg", droll, 0.0, 6.0)


# --- csv ---------------------------------------------------------------------------------------------------------------------

func _dump_csv(S: Dictionary, tag: String) -> void:
	DirAccess.make_dir_recursive_absolute(_csv)
	var f := FileAccess.open("%s/%s.csv" % [_csv, tag], FileAccess.WRITE)
	if f == null:
		return
	var keys: Array = []
	for k in S.keys():
		if S[k] is PackedFloat32Array:
			keys.append(k)
	f.store_line(",".join(keys))
	var n := (S["t"] as PackedFloat32Array).size()
	for i in n:
		var row := PackedStringArray()
		for k in keys:
			row.append("%.5f" % (S[k] as PackedFloat32Array)[i])
		f.store_line(",".join(row))
	f.close()
