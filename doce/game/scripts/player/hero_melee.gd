class_name HeroMelee
extends RefCounted
## The hero's sword (CORE): the 3-hit combo, the charged heavy blow, magnetism, the blade sweep and the feel of a
## blow landing. Driven by Hero (states ATTACK, CHARGE, HEAVY); numbers in docs/COMBAT.md.
##
## A press of attack starts the next light blow at once, at full speed, however long the button stays down (a
## firm tap never waits). Still held when the blow's active frames are over and CHARGE_HOLD s after the press, the
## heavy blow winds up from the follow-through (CHARGE: slow walk, the body coils, the blade trembles; the Zelda
## spin attack); CHARGE_TIME s later a glint and a ring say it is charged; released then: the spin slash; released
## before: the coil relaxes (the combo goes on from the last light blow). Attack held in MOVE (through a recoil, a
## roll) coils too. Hits: the blade (root to tip, RigHeracles.blade_segment) is swept
## between the rig's posed frames through the active window (act0..act1, clipped exactly inside the frame that
## straddles each end) against every foe's hurt volumes (Combat.hurt_volumes), top-down with a generous vertical
## band; each point of the blade travels an arc round the hero between two frames (sub-steps of 12 degrees), so a
## fast swing at 24 fps hits what it hits at 144 fps; each foe at most once per blow.

enum { RUNNING, DONE }

## Light blows. Times are the rig action's own seconds (RigHeracles keys); `speed` scales them. act0..act1: active
## frames (the blade sweeps); open: the combo window opens; cancel: the recovery can be cancelled (dodge, guard,
## throw) from here; move: a push of the stick (> 0.6) ends it from here (into the run); rearm: a press starts a
## new combo from here (the finisher and the heavy, which have no combo window). hold: the heavy's coil key.
const LIGHT := [
	{"name": &"attack1", "anim": "attack1", "speed": 1.05, "hold": 0.11, "act0": 0.125, "act1": 0.29, "open": 0.29, "cancel": 0.3, "move": 0.38,
		"amount": 10.0, "knockback": 3.8, "stagger": 0.35, "hitstop": 0.07, "shake": 0.35, "nudge": 0.18, "power": 0.7,
		"lunge": 1.4, "swing": "swing_1", "hit": "hit_1"},
	{"name": &"attack2", "anim": "attack2", "speed": 1.05, "hold": 0.1, "act0": 0.115, "act1": 0.28, "open": 0.28, "cancel": 0.29, "move": 0.37,
		"amount": 10.0, "knockback": 3.8, "stagger": 0.35, "hitstop": 0.07, "shake": 0.35, "nudge": 0.18, "power": 0.7,
		"lunge": 1.4, "swing": "swing_2", "hit": "hit_2"},
	{"name": &"attack3", "anim": "attack3", "speed": 1.0, "hold": 0.22, "act0": 0.262, "act1": 0.42, "open": 99.0, "cancel": 0.5, "move": 0.58, "rearm": 0.55,
		"amount": 18.0, "knockback": 8.5, "stagger": 0.75, "hitstop": 0.11, "shake": 0.47, "nudge": 0.4, "power": 1.1,
		"lunge": 1.5, "swing": "swing_3", "hit": "hit_3", "finisher": true},
]
const HEAVY := {"name": &"heavy", "anim": "heavy", "speed": 1.0, "hold": 0.3, "act0": 0.37, "act1": 0.68, "open": 99.0, "cancel": 0.8, "move": 0.88, "rearm": 0.85,
	"amount": 30.0, "knockback": 11.0, "stagger": 1.1, "hitstop": 0.16, "shake": 0.62, "nudge": 0.36, "power": 1.6,
	"lunge": 0.6, "swing": "swing_heavy", "hit": "hit_heavy", "guard_break": true}
## Attack held this long (s, from its press) and the blow's active frames over: the heavy blow starts to coil.
const CHARGE_HOLD := 0.28
## Seconds of coil until the heavy blow is charged.
const CHARGE_TIME := 0.24
## The heavy's wind-up starts this far into its coil when it grows out of a light blow's follow-through.
const COIL_FROM_BLOW := 0.1
## A stick push past this (0..1) ends a blow's recovery from its `move` key.
const MOVE_OUT := 0.6
## After a blow ends, a press still continues the combo for this long (s of game time).
const COMBO_GRACE := 0.25
## Half-thickness of the blade's sweep (m) and how far past the visible tip it still counts (m): generous on
## purpose (a blow that looks like it touched, touched).
const BLADE_R := 0.12
const TIP_EXTRA := 0.12
## Magnetism: a foe in this cone (half-angle, degrees) within this distance (m, to its surface) draws the blow.
const MAGNET_ANGLE := 35.0
const MAGNET_RANGE := 2.5
const MAGNET_RANGE_LOCKED := 4.5
## The lunge stops this far from the foe's surface (m): inside the xiphos' reach (0.85 m straight ahead, 1.2-1.4 m
## at the ends of the arcs; tools: the arc dump in docs/COMBAT.md).
const STRIKE_GAP := 0.5
## The lunge starts this long (s) into the blow; with no foe in reach the blow still steps LUNGE_STEP m.
const LUNGE_T0 := 0.02
const LUNGE_STEP := 0.3
## A blow out of a run (faster than CARRY_MIN m/s) with no foe to lunge at carries the run on, slowing at
## CARRY_DECEL m/s^2 (1.5 m from 6.2 m/s), instead of stopping dead.
const CARRY_MIN := 3.0
const CARRY_DECEL := 13.0

var hero: Hero
var rig: RigHeracles
var trail: BladeTrail
## Index (1..3) of the current / last light blow; 0 after the finisher or when the combo lapsed.
var combo := 0
var cur: Dictionary = {}
var charging := false
var charged := false
var _t := 0.0
## Seconds the heavy blow has been coiling (CHARGE).
var _charge_t := 0.0
var _swing_played := false
var _hit := {}
var _foes: Array[Node3D] = []
var _r0 := Vector3.ZERO
var _t0 := Vector3.ZERO
var _c0 := Vector3.ZERO
var _rt0 := 0.0
var _have := false
var _stopped := false
var _face_dir := Vector3.ZERO
var _lunge_dir := Vector3.ZERO
## The lunge's length (m) and its end (s of the blow); _lunge_vel is this tick's velocity along its curve.
var _lunge_dist := 0.0
var _lunge_end := 0.0
var _lunge_vel := Vector3.ZERO
## The run carried into a blow with no foe (see CARRY_MIN).
var _carry := Vector3.ZERO
## When the last blow ended (Hero._clock: game seconds, so the grace is the same at any frame rate or speed).
var _end_t := -100.0
## Until when (Hero._clock) the camera's soft framing turns to the foe at once (a blow was just aimed or landed).
var engaged_until := -1.0
var _pts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _debug := false
## The foe the blows are aimed at (magnetism) and until when (Hero._clock) the camera keeps it framed beside the
## hero (Hero.camera_interest: a soft lock while fighting without the lock-on).
var focus: Node3D = null
var _focus_until := -1.0
## Seconds the camera keeps framing the last foe aimed at or hit.
const FOCUS_HOLD := 1.6
## For this long (s) after a blow is aimed at a foe or lands, the camera's soft framing turns to it at once
## (without waiting for the look input to rest): the first blows of a fight are framed too.
const ENGAGED_HOLD := 0.6
## A killing blow: this much more hit-stop (s), then slow motion (time scale, seconds).
const KILL_HITSTOP := 0.05
const KILL_SLOWMO := Vector2(0.35, 0.3)


func _init(h: Hero) -> void:
	hero = h
	rig = h.rig
	trail = BladeTrail.new()
	trail.name = "BladeTrail"
	trail.rig = rig
	trail.process_priority = 20
	h.add_child(trail)
	_debug = Game.arg_on("meleedebug")


func is_busy() -> bool:
	return not cur.is_empty()


## The foe the sword is busy with (aimed at or hit in the last FOCUS_HOLD s, alive, within 7 m), or null.
func focus_target() -> Node3D:
	if focus == null or hero._clock > _focus_until or not Combat.is_alive(focus):
		return null
	if Combat.flat(focus.global_position - hero.global_position).length() > 7.0:
		return null
	return focus


## The next blow of the combo (or blow `n` 1..3, e.g. a strike on arriving at the end of the chain).
func start_light(n: int = 0) -> void:
	if n <= 0:
		var lapsed := hero._clock - _end_t > COMBO_GRACE and cur.is_empty()
		n = 1 if (combo <= 0 or combo >= 3 or lapsed) else combo + 1
	combo = clampi(n, 1, 3)
	_begin(LIGHT[combo - 1], Hero.St.ATTACK)


func _begin(def: Dictionary, st: int) -> void:
	cur = def
	charging = false
	charged = false
	rig.charge = 0.0
	hero._set_state(st)
	rig.play_at(def["anim"], float(def["speed"]), false)
	rig.action_hold = -1.0
	_t = 0.0
	_swing_played = false
	_hit.clear()
	_foes = Combat.foes(hero.get_tree(), hero.team)
	_have = false
	_stopped = false
	_aim(def)
	trail.clear()
	trail.active = false
	trail.heavy = def["name"] == &"heavy"


## Magnetism: turn to the foe the blow is meant for and lunge to striking distance (stronger when locked on).
func _aim(def: Dictionary) -> void:
	var from := hero.global_position
	var iv := hero._input_vector()
	var aim := hero._move_dir(iv)
	if aim.length() < 0.2:
		aim = hero.forward()
	aim = aim.normalized()
	var lock := hero.lock_target()
	var t: Node3D = null
	var reach := float(def["lunge"])
	if lock and Combat.flat(lock.global_position - from).length() - Combat.body_radius(lock) <= MAGNET_RANGE_LOCKED:
		t = lock
		reach += 0.5
	else:
		t = Combat.best_in_cone(_foes, from, aim, MAGNET_RANGE, MAGNET_ANGLE)
	var spd := float(def["speed"])
	# the lunge runs from the start to the first active frame
	_lunge_end = maxf(float(def["act0"]) / spd + 0.04, 0.08)
	if t:
		focus = t
		_focus_until = hero._clock + FOCUS_HOLD
		engaged_until = hero._clock + ENGAGED_HOLD
		var d := Combat.flat(t.global_position - from)
		_face_dir = d.normalized() if d.length() > 0.05 else aim
		var gap := d.length() - Combat.body_radius(t) - STRIKE_GAP
		_lunge_dist = clampf(gap, 0.0, reach)
		_lunge_dir = _face_dir
	else:
		_face_dir = aim
		_lunge_dir = aim
		_lunge_dist = LUNGE_STEP # a step into the blow
	_carry = Vector3.ZERO
	var run := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	if t == null and run.length() > CARRY_MIN and def["name"] != &"heavy":
		# out of a run at nothing: the run carries on into the blow and slows down (no dead stop)
		_carry = run
		_lunge_dist = 0.0
	_lunge_vel = Vector3.ZERO


## One physics tick of the blow; DONE when it is over.
func tick(delta: float, dir: Vector3, mag: float) -> int:
	if cur.is_empty():
		return DONE
	_t += delta
	if rig.action != String(cur["anim"]):
		_finish()
		return DONE
	# the lunge follows a displacement curve: exactly _lunge_dist from LUNGE_T0 to _lunge_end, quick out of the
	# blocks and planted at the end (a velocity ramp would overshoot into the foe)
	_lunge_vel = Vector3.ZERO
	if _lunge_end > LUNGE_T0 and _t > LUNGE_T0 and _t - delta < _lunge_end and delta > 0.0:
		var s1 := _lunge_s(_t)
		var s0 := _lunge_s(_t - delta)
		_lunge_vel = _lunge_dir * ((s1 - s0) * _lunge_dist / delta)
	var rt := rig.action_t
	if charging:
		return _tick_charge(delta)
	var a0 := float(cur["act0"])
	var a1 := float(cur["act1"])
	# held on past the active frames: the heavy blow coils out of the follow-through (the blade never stops
	# mid-swing for it, and a tap never waits for it)
	if hero.state == Hero.St.ATTACK and rt >= a1 and wants_charge():
		start_charge(true)
		return RUNNING
	# face the target during the wind-up (committed after)
	if rt < a0:
		hero._turn_to(_face_dir, delta, 26.0)
	elif hero.lock_target() and rt > float(cur["cancel"]):
		hero._turn_to(hero.lock_target().global_position - hero.global_position, delta, 8.0)
	# the blade
	trail.active = rt >= a0 - 0.03 and rt <= a1 + 0.02
	_sweep(rt, a0, a1)
	if cur.is_empty():
		return DONE # a deflect ended the blow
	if not _swing_played and rt >= a0 - 0.01:
		_play_swing()
	# the combo window: a buffered press flows into the next blow
	if hero.state == Hero.St.ATTACK and rt >= float(cur["open"]) and combo < 3 and hero._buf_attack > 0.0:
		hero._buf_attack = 0.0
		start_light()
		return RUNNING
	# the finisher's and the heavy's recovery: a buffered press starts a new combo
	if rt >= float(cur.get("rearm", 99.0)) and hero._buf_attack > 0.0:
		hero._buf_attack = 0.0
		combo = 0
		start_light(1)
		return RUNNING
	return RUNNING


## The attack button held long enough (and the stamina for it) to coil the heavy blow.
func wants_charge() -> bool:
	return hero.inp.is_held(&"attack") and hero.inp.hold_time(&"attack") >= CHARGE_HOLD and not hero.exhausted \
		and hero.stamina >= Hero.HEAVY_COST * 0.5


## Fraction (0..1) of the lunge covered `t` s into the blow: a sine ease-out (quick out of the blocks, peak
## speed 1.57 x the mean, planted softly at the end).
func _lunge_s(t: float) -> float:
	var u := clampf((t - LUNGE_T0) / maxf(_lunge_end - LUNGE_T0, 0.05), 0.0, 1.0)
	return sin(u * PI * 0.5)


## Movement the blow wants: the lunge during the wind-up, a slow drift in the recovery, the charge walk.
func want_velocity(dir: Vector3, mag: float) -> Vector3:
	if cur.is_empty():
		return Vector3.ZERO
	if charging:
		return dir.normalized() * Hero.CHARGE_SPEED * mag if mag > 0.05 else Vector3.ZERO
	if _carry != Vector3.ZERO:
		var v := _carry.length() - CARRY_DECEL * _t
		if v > 0.0:
			return _carry / _carry.length() * v
	if _t > LUNGE_T0 and _t < _lunge_end + 0.02:
		return _lunge_vel
	if rig.action_t > float(cur["cancel"]) and mag > 0.05:
		return dir.normalized() * 1.2 * mag
	return Vector3.ZERO


func accel() -> float:
	if charging:
		return 20.0
	if _carry != Vector3.ZERO:
		return 45.0
	# the lunge is followed exactly (its curve already eases); then the feet plant quickly
	return 4000.0 if _t < _lunge_end + 0.02 else 45.0


## The recovery may be cancelled (dodge, guard, throw); never the wind-up or the active frames.
func can_cancel() -> bool:
	return not cur.is_empty() and not charging and rig.action == String(cur["anim"]) and rig.action_t >= float(cur["cancel"])


## A push of the stick (`mag` past MOVE_OUT) may end the blow's recovery from its `move` key (into the run).
func can_move_out(mag: float) -> bool:
	return mag > MOVE_OUT and can_cancel() and rig.action_t >= float(cur.get("move", 99.0))


func abort() -> void:
	if not cur.is_empty():
		_end_t = hero._clock
	cur = {}
	charging = false
	charged = false
	trail.active = false
	rig.action_hold = -1.0
	rig.charge = 0.0


func _finish() -> void:
	if cur.get("finisher", false) or cur.get("name", &"") == &"heavy":
		combo = 0
	abort()


func on_rig_event(ev: String) -> void:
	if ev == "swing" and not cur.is_empty() and not _swing_played and not charging:
		_play_swing()


func _play_swing() -> void:
	_swing_played = true
	var heavy: bool = cur.get("name", &"") == &"heavy"
	Sfx.play(String(cur["swing"]), hero.global_position + Vector3(0, 1.2, 0), -2.0 if heavy else -4.0, randf_range(0.95, 1.06))


# --- the heavy blow's charge ---------------------------------------------------------------------------------

## The heavy blow coils (state CHARGE): out of a light blow's follow-through (`from_blow`: straight into the
## coil, no pass through the guard stance) or from the stance (attack held through a recoil or a roll).
func start_charge(from_blow: bool = false) -> void:
	if not cur.is_empty():
		_end_t = hero._clock
	cur = HEAVY
	charging = true
	charged = false
	_charge_t = 0.0
	hero._set_state(Hero.St.CHARGE)
	rig.play_at("heavy", 1.0, true)
	if from_blow:
		rig.action_t = COIL_FROM_BLOW
	rig.action_hold = float(HEAVY["hold"])
	trail.active = false
	Sfx.play("chain_taut", hero.global_position + Vector3(0, 1.2, 0), -14.0, 1.4)


func _tick_charge(delta: float) -> int:
	_charge_t += delta
	var held := hero.inp.is_held(&"attack")
	rig.charge = clampf(_charge_t / CHARGE_TIME, 0.0, 1.0) * 0.5 + (0.5 if charged else 0.0)
	var lock := hero.lock_target()
	if lock:
		hero._turn_to(lock.global_position - hero.global_position, delta, 8.0)
	else:
		var d := hero._move_dir(hero._input_vector())
		if d.length() > 0.2:
			hero._turn_to(d, delta, 6.0)
	if not charged and held and _charge_t >= CHARGE_TIME:
		charged = true
		var tip: Vector3 = rig.blade_segment()[1]
		if Game.fx:
			Game.fx.call("glint", tip, 1.4, Color(1.0, 0.95, 0.75), 0.4)
			Game.fx.call("ring", hero.global_position, 1.4, Color(1.0, 0.85, 0.5, 0.7), 0.35)
		if ResourceLoader.exists("res://assets/audio/sfx/charge_ready.ogg"):
			Sfx.play("charge_ready", tip, -4.0)
		else:
			Sfx.play("parry", tip, -13.0, 1.6)
	if not held:
		if charged:
			_release_heavy()
			return RUNNING
		# let go before it was charged: the coil relaxes into the stance (a press now goes on with the combo)
		charging = false
		cur = {}
		rig.charge = 0.0
		rig.action_hold = -1.0
		rig.stop_action(0.18)
		_end_t = hero._clock
		return DONE
	return RUNNING


func _release_heavy() -> void:
	hero._spend(Hero.HEAVY_COST)
	charging = false
	charged = false
	rig.charge = 0.0
	_begin(HEAVY, Hero.St.HEAVY)
	rig.action_t = float(HEAVY["hold"])
	_t = float(HEAVY["hold"])
	_lunge_end = 0.0
	combo = 0


# --- hits --------------------------------------------------------------------------------------------------------

## Sweeps the blade from its last sample to its current pose against every foe not hit yet in this blow.
## One frame of the blade: the rig poses once per drawn frame, so a new sample only when its action time moved.
func _sweep(rt: float, a0: float, a1: float) -> void:
	if _have and rt <= _rt0:
		return
	var seg := rig.blade_segment()
	var r1 := seg[0]
	var t1 := seg[1] + (seg[1] - seg[0]).normalized() * TIP_EXTRA
	var c1 := hero.global_position
	if _have and rt > a0 and _rt0 < a1:
		var span := rt - _rt0
		_test(r1, t1, c1, clampf((a0 - _rt0) / span, 0.0, 1.0), clampf((a1 - _rt0) / span, 0.0, 1.0))
	_r0 = r1
	_t0 = t1
	_c0 = c1
	_rt0 = rt
	_have = true


## Sub-steps (radians) of a blade point's arc between two frames.
const ARC_STEP := 0.21


## The blade from the last sample (_r0, _t0 round _c0) to this one (r1, t1 round c1), between the fractions f0
## and f1 of that move, against every foe not yet hit by this blow.
func _test(r1: Vector3, t1: Vector3, c1: Vector3, f0: float, f1: float) -> void:
	for foe in _foes:
		if cur.is_empty():
			return
		if not Combat.is_alive(foe) or _hit.has(foe.get_instance_id()):
			continue
		for vol in Combat.hurt_volumes(foe):
			var a: Vector3 = vol[0]
			var b: Vector3 = vol[1]
			var r: float = vol[2]
			var rr := r + BLADE_R
			var a2 := Vector3(a.x, 0.0, a.z)
			var b2 := Vector3(b.x, 0.0, b.z)
			var hit_p := Vector3.INF
			var best := INF
			for k in 4:
				var u := 0.28 + 0.24 * float(k)
				var p0 := _r0.lerp(_t0, u)
				var p1 := r1.lerp(t1, u)
				# vertical band: the blade covers what is a little under it (wolves under a chest-high cut)
				var lo := minf(p0.y, p1.y) - 0.9
				var hi := maxf(p0.y, p1.y) + 0.35
				if hi < minf(a.y, b.y) - r or lo > maxf(a.y, b.y) + r:
					continue
				# the point's path: an arc round the hero (a chord would cut inside a fast swing at a low frame rate)
				var v0 := Vector3(p0.x - _c0.x, 0.0, p0.z - _c0.z)
				var v1 := Vector3(p1.x - c1.x, 0.0, p1.z - c1.z)
				var g0 := atan2(v0.x, v0.z)
				var dg := wrapf(atan2(v1.x, v1.z) - g0, -PI, PI)
				var l0 := v0.length()
				var l1 := v1.length()
				var n := clampi(ceili(absf(dg) * (f1 - f0) / ARC_STEP), 1, 12)
				var q0 := _arc(g0, dg, l0, l1, c1, f0)
				for i in n:
					var sf := lerpf(f0, f1, float(i + 1) / float(n))
					var q1 := _arc(g0, dg, l0, l1, c1, sf)
					var d2 := Combat.seg_seg_dist2(q0, q1, a2, b2, _pts)
					best = minf(best, d2)
					if d2 <= rr * rr:
						hit_p = Vector3(_pts[0].x, lerpf(p0.y, p1.y, sf), _pts[0].z)
						break
					q0 = q1
				if hit_p != Vector3.INF:
					break
			if _debug:
				print("MELEE %s rt=%.3f f=%.2f..%.2f foe=%s closest=%.3f reach=%.3f" % [cur["name"], _rt0, f0, f1, foe.name, sqrt(best), rr])
			if hit_p != Vector3.INF:
				# contact on the volume's surface, at the blade's height
				Combat.seg_seg_dist2(hit_p, hit_p, a, b, _pts)
				var axis_p := _pts[1]
				var off := hit_p - axis_p
				var point := axis_p + (off.normalized() * r if off.length() > 0.01 else Vector3.ZERO)
				point.y = clampf(hit_p.y, minf(a.y, b.y) - r * 0.5, maxf(a.y, b.y) + r * 0.5)
				_contact(foe, point, Combat.flat(t1 - _t0))
				break


## A point of the arc (top-down) at the fraction s of the move: round the hero's (moving) centre.
func _arc(g0: float, dg: float, l0: float, l1: float, c1: Vector3, s: float) -> Vector3:
	var c := _c0.lerp(c1, s)
	var g := g0 + dg * s
	var l := lerpf(l0, l1, s)
	return Vector3(c.x + sin(g) * l, 0.0, c.z + cos(g) * l)


func _contact(foe: Node3D, point: Vector3, motion: Vector3) -> void:
	_hit[foe.get_instance_id()] = true
	var away := Combat.flat(foe.global_position - hero.global_position)
	away = away.normalized() if away.length() > 0.05 else hero.forward()
	var kdir := away
	if cur["name"] != &"heavy" and motion.length() > 0.05:
		kdir = (away + motion.normalized() * 0.45).normalized()
	var finisher := bool(cur.get("finisher", false))
	var heavy: bool = cur["name"] == &"heavy"
	var h := Combat.make_hit(float(cur["amount"]), &"blade", kdir, float(cur["knockback"]), float(cur["stagger"]), hero,
		{"point": point, "attack": cur["name"], "guard_break": bool(cur.get("guard_break", false))})
	var hurt := bool(foe.call("take_hit", h))
	if _debug:
		print("MELEE HIT %s blow_t=%.3f rig_t=%.3f dist=%.2f hurt=%s" % [cur["name"], _t, rig.action_t,
			Combat.flat(foe.global_position - hero.global_position).length(), str(hurt)])
	focus = foe
	_focus_until = hero._clock + FOCUS_HOLD
	engaged_until = hero._clock + ENGAGED_HOLD
	if hurt:
		if Game.fx:
			Game.fx.call("impact", point, kdir, float(cur["power"]))
			if heavy or finisher:
				Game.fx.call("dust", foe.global_position, 5 if heavy else 3, 0.5)
		Sfx.play(String(cur["hit"]), point, -1.0, randf_range(0.92, 1.08))
		var killed := not Combat.is_alive(foe)
		if not _stopped:
			_stopped = true
			Game.hitstop(float(cur["hitstop"]) + (KILL_HITSTOP if killed else 0.0))
		if killed:
			# the blow that ends a fight: a longer freeze, then a beat of slow motion as the body goes down (the
			# slow motion's clock starts now, under the freeze: it lasts the freeze plus KILL_SLOWMO.y)
			Game.slowmo(KILL_SLOWMO.x, float(cur["hitstop"]) + KILL_HITSTOP + KILL_SLOWMO.y)
			if Game.fx:
				Game.fx.call("impact", point + Vector3(0, 0.1, 0), kdir, float(cur["power"]) + 0.5, Color(1.0, 0.93, 0.8))
		Game.shake(float(cur["shake"]) + (0.15 if killed else 0.0))
		if Game.camera and is_instance_valid(Game.camera) and Game.camera.has_method("nudge"):
			Game.camera.call("nudge", kdir, float(cur["nudge"]))
		hero.blow_landed.emit(foe, h)
	elif bool(h.get("deflected", false)):
		# the blade cannot bite (the Nemean Lion): it bounces off with sparks and a clang, the arm flies back
		if Game.fx:
			Game.fx.call("hit_spark", point, -kdir, 1.6)
			Game.fx.call("impact", point, -kdir, 0.8, Color(1.0, 0.85, 0.55))
		if not bool(h.get("sound_done", false)):
			Sfx.play("blade_bounce", point, 0.0, randf_range(0.95, 1.05))
		Game.hitstop(0.07)
		Game.shake(0.22)
		hero.recoil(point, heavy or finisher)
	elif bool(h.get("blocked", false)):
		if Game.fx:
			Game.fx.call("hit_spark", point, -kdir, 1.0)
		if not bool(h.get("sound_done", false)):
			Sfx.play("shield_block", point, -1.0)
		Game.hitstop(0.05)
		Game.shake(0.12)
		if not heavy:
			hero.recoil(point, false)
