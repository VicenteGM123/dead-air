class_name AmbientGoat
extends RefCounted
## One goat's behaviour (drives a ModelsAnimals.GoatRig). Goats keep to their herd's patch of wild hillside:
## graze with the head down (shuffling forward now and then), look up and around, amble to a new spot, lie down
## for a rest. Kids stay close to their mother and hop about. Everyone steps away from a hero who comes too
## close (and from the creatures of Nyx), and the herd lies down to sleep at night.

enum { GRAZE, LOOK, WALK, LIE, SLEEP }

const WALK_SPEED := 0.42
const TURN_RATE := 2.6
const HERD_R := 7.0
const SCALE := 1.3
const SHY_R := 2.4
const BODY_R := 0.95 # hero radius 0.5 + the goat's
const THREAT_R := 4.5

var amb: Ambient
var rig: ModelsAnimals.GoatRig
var rng := RandomNumberGenerator.new()
var center := Vector3.ZERO
var mother: AmbientGoat = null
var kid := false
var pos := Vector3.ZERO
var yaw := 0.0
var state := GRAZE
var timer := 0.0
var target := Vector3.ZERO
var walk_speed := WALK_SPEED
var after_walk := GRAZE
var cur_speed := 0.0
var shuffle := 0.0
var shuffle_timer := 0.0
var look_timer := 0.0
var graze_yaw := 0.0
var flee_cd := 0.0
var _ok_fn: Callable
var _tilt := Vector2.ZERO
var _tilt_want := Vector2.ZERO
var _placed := Vector3.INF
var _checked := Vector3.INF


func _init(ambient: Ambient, coat: String, at: Vector3, herd_center: Vector3, seed_value: int, is_kid: bool) -> void:
	amb = ambient
	rng.seed = seed_value
	kid = is_kid
	center = herd_center
	rig = ModelsAnimals.GoatRig.new(coat, seed_value, kid)
	rig.driven = true
	rig.brain = self
	rig.scale *= SCALE * (rng.randf_range(0.94, 1.06) if not kid else 1.0)
	amb.add_child(rig)
	pos = at
	yaw = rng.randf() * TAU
	graze_yaw = yaw
	_ok_fn = amb.goat_ok
	_enter(GRAZE if rng.randf() < 0.7 else LOOK)
	timer *= rng.randf()
	_place(1.0)


func tick(dt: float) -> void:
	timer -= dt
	flee_cd -= dt
	var night_mode := amb.night > 0.6
	# Nobody walks through a goat: one in the way of a running Fanós is nudged aside.
	var hb := amb.hero_pos()
	if hb.is_finite() and _flat(hb - pos).length() < BODY_R:
		var away := _flat(pos - hb)
		var np := hb + (away.normalized() if away.length() > 0.01 else Vector3(sin(yaw), 0, cos(yaw))) * BODY_R
		np = amb.ground(np)
		if amb.goat_ok(np):
			pos = np
	if flee_cd <= 0.0 and state != WALK:
		flee_cd = 0.4
		# Shy: step away from a hero who walks right up, and from any creature of Nyx.
		var h := amb.hero_pos()
		var th := amb.threat_near(pos, THREAT_R)
		if th.is_finite():
			flee_cd = 1.0
			if _flee(th, 3.0, 5.0):
				return
		elif state != SLEEP and h.is_finite() and _flat(h - pos).length() < SHY_R:
			flee_cd = 0.6
			if _flee(h, 2.0, 3.2):
				return
	match state:
		GRAZE:
			if night_mode:
				_enter(LIE)
			else:
				_graze_shuffle(dt)
				if timer <= 0.0:
					_decide()
		LOOK:
			_look_around(dt)
			if night_mode:
				_enter(LIE)
			elif timer <= 0.0:
				_decide()
		WALK:
			if _walk(dt, target, walk_speed):
				_enter(LIE if night_mode else after_walk)
		LIE:
			if night_mode:
				if timer <= 0.0:
					_enter(SLEEP)
			elif timer <= 0.0:
				_enter(LOOK)
		SLEEP:
			if amb.night < 0.35:
				_enter(LOOK)
	if kid and mother != null and (state == GRAZE or state == LOOK) and not night_mode:
		if _flat(mother.pos - pos).length() > 3.2:
			_follow_mother()
	_place(dt)


func _enter(s: int) -> void:
	state = s
	match s:
		GRAZE:
			rig.play("graze", 0.8)
			timer = rng.randf_range(5.0, 12.0) * (0.6 if kid else 1.0)
			shuffle_timer = rng.randf_range(1.0, 3.0)
			graze_yaw = yaw
		LOOK:
			rig.play("stand", 0.7)
			timer = rng.randf_range(2.5, 5.0)
			look_timer = 0.0
			# Optional sound: plays once someone adds assets/audio/sfx/goat_bleat.ogg (Sfx skips missing files).
			if Ambient.EXTRA_SFX and rng.randf() < 0.1:
				Sfx.play("goat_bleat", pos, -8.0, rng.randf_range(1.15, 1.35) if kid else rng.randf_range(0.9, 1.05))
		WALK:
			rig.play("stand", 0.5)
			rig.look(0.0, 0.0)
		LIE:
			rig.play("lie", 1.1)
			rig.look(0.0, 0.0)
			timer = rng.randf_range(2.0, 4.0) if amb.night > 0.6 else rng.randf_range(12.0, 25.0)
		SLEEP:
			rig.play("sleep", 1.2)
	if s != WALK:
		cur_speed = 0.0
		rig.set_locomotion(0.0)


func _decide() -> void:
	var r := rng.randf()
	if kid and rng.randf() < 0.3:
		rig.play("hop")
	if state == GRAZE:
		if r < 0.35:
			_enter(LOOK)
		elif r < 0.8:
			_wander()
		elif r < 0.92 or kid:
			_enter(GRAZE)
		else:
			_enter(LIE)
	else:
		if r < 0.55:
			_enter(GRAZE)
		else:
			_wander()


func _wander() -> void:
	var base := center
	var rad := HERD_R
	if kid and mother != null:
		base = mother.pos
		rad = 2.5
	for tries in 10:
		var a := rng.randf() * TAU
		var p := amb.ground(base + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, rad))
		var d := _flat(p - pos).length()
		if d < 1.2 or d > 6.0 or not amb.goat_ok(p) or _crowded(p):
			continue
		if amb.path_ok(pos, p, _ok_fn):
			target = p
			walk_speed = WALK_SPEED * rng.randf_range(0.85, 1.1)
			after_walk = GRAZE
			_enter(WALK)
			return
	_enter(GRAZE)


func _follow_mother() -> void:
	for tries in 6:
		var a := rng.randf() * TAU
		var p := amb.ground(mother.pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.0, 1.8))
		if amb.goat_ok(p) and amb.path_ok(pos, p, _ok_fn):
			target = p
			walk_speed = 0.85
			after_walk = LOOK if rng.randf() < 0.5 else GRAZE
			_enter(WALK)
			return


func _flee(from: Vector3, dmin: float, dmax: float) -> bool:
	var away := _flat(pos - from)
	if away.length() < 0.1:
		away = Vector3(sin(yaw), 0, cos(yaw))
	away = away.normalized()
	for tries in 8:
		var a := atan2(away.x, away.z) + rng.randf_range(-0.9, 0.9)
		var p := amb.ground(pos + Vector3(sin(a), 0, cos(a)) * rng.randf_range(dmin, dmax))
		if amb.goat_ok(p) and amb.path_ok(pos, p, _ok_fn) and not _crowded(p):
			target = p
			walk_speed = 1.1
			after_walk = LOOK
			_enter(WALK)
			if kid:
				rig.play("hop")
			return true
	return false


func _graze_shuffle(dt: float) -> void:
	# Every few seconds a couple of slow steps forward while munching (the end of the shuffle is checked once).
	shuffle_timer -= dt
	if shuffle_timer <= 0.0:
		shuffle_timer = rng.randf_range(2.0, 4.5)
		shuffle = rng.randf_range(0.7, 1.3)
		graze_yaw = yaw + rng.randf_range(-0.6, 0.6)
		var end := amb.ground(pos + Vector3(sin(graze_yaw), 0, cos(graze_yaw)) * 0.3)
		if not amb.goat_ok(end) or _flat(end - center).length() > HERD_R + 2.0 or _crowded(end):
			shuffle = 0.0
			graze_yaw = yaw + PI * 0.6
			shuffle_timer = 0.8
	if shuffle > 0.0:
		shuffle -= dt
		yaw = rotate_toward(yaw, graze_yaw, 0.9 * dt)
		var v := 0.14 * clampf(shuffle * 3.0, 0.0, 1.0)
		pos += Vector3(sin(yaw), 0, cos(yaw)) * v * dt
		rig.set_locomotion(v)
	else:
		rig.set_locomotion(0.0)


func _look_around(dt: float) -> void:
	look_timer -= dt
	if look_timer <= 0.0:
		look_timer = rng.randf_range(1.2, 2.6)
		var h := amb.hero_pos()
		if h.is_finite() and _flat(h - pos).length() < 8.0 and rng.randf() < 0.6:
			var to := _flat(h - pos)
			rig.look(clampf(angle_difference(yaw, atan2(to.x, to.z)), -1.0, 1.0), 0.1)
		else:
			rig.look(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.2))


func _crowded(p: Vector3) -> bool:
	for g in amb.goats:
		if g != self and (_flat(g.pos - p).length() < 1.5 or (g.state == WALK and _flat(g.target - p).length() < 1.5)):
			return true
	return false


func _walk(dt: float, p: Vector3, spd: float) -> bool:
	var to := _flat(p - pos)
	var d := to.length()
	if d < 0.12:
		cur_speed = 0.0
		rig.set_locomotion(0.0)
		return true
	var want := atan2(to.x, to.z)
	var diff := angle_difference(yaw, want)
	yaw = rotate_toward(yaw, want, TURN_RATE * dt)
	var goal_speed := spd * clampf(d / 0.8, 0.3, 1.0) * clampf(cos(diff), 0.15, 1.0)
	cur_speed = move_toward(cur_speed, goal_speed, dt * 1.5)
	var np := pos + Vector3(sin(yaw), 0, cos(yaw)) * minf(cur_speed * dt, d)
	# Routes are checked before setting off; re-check the ground every 0.3 m.
	if _flat(np - _checked).length() > 0.3:
		if not amb.goat_ok(np):
			cur_speed = 0.0
			rig.set_locomotion(0.0)
			return true
		_checked = np
	pos = np
	rig.set_locomotion(cur_speed)
	return false


## Puts the rig on the ground, its body following the slope (pitch and roll).
func _place(dt: float) -> void:
	var key := Vector3(pos.x, pos.z, yaw)
	if key != _placed or dt >= 1.0:
		_placed = key
		pos = amb.push_out(pos, 0.4)
		pos.y = amb.ground_y(pos.x, pos.z)
		var f := Vector3(sin(yaw), 0, cos(yaw)) * 0.42
		var r := Vector3(f.z, 0, -f.x) * 0.45
		var hf := amb.ground_y(pos.x + f.x, pos.z + f.z)
		var hb := amb.ground_y(pos.x - f.x, pos.z - f.z)
		var hr := amb.ground_y(pos.x + r.x, pos.z + r.z)
		var hl := amb.ground_y(pos.x - r.x, pos.z - r.z)
		_tilt_want = Vector2(-atan2(hf - hb, 0.84) * 0.85, atan2(hr - hl, 0.38) * 0.7)
	elif _tilt.distance_squared_to(_tilt_want) < 1e-7:
		return
	_tilt = _tilt.lerp(_tilt_want, 1.0 - exp(-dt * 5.0)) if dt < 1.0 else _tilt_want
	rig.position = pos
	rig.rotation = Vector3(_tilt.x, yaw, _tilt.y)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
