class_name AmbientCat
extends RefCounted
## One cat's behaviour (drives a ModelsAnimals.CatRig). It lives around a sunny home spot by a house, the well or
## the plaza edge: sits (tail sway, head turns), loafs, stretches, wanders a few metres, glances at the hero and
## now and then trots up to greet them, purrs with hearts when petted, and sleeps curled up at night in a bed spot
## away from the lanes (scampering off if a creature of Nyx comes close). House cats move in by a new house.

enum { SIT, LOAF, STRETCH, WALK, APPROACH, GREET, PET, BED, SLEEP, WAKE }

const WALK_SPEED := 0.5
const TROT_SPEED := 1.0
const SCAMPER_SPEED := 2.6
const TURN_RATE := 4.2
const WANDER_R := 2.8
const PURR_TIME := 3.4
## A hero closer than this makes a resting cat get up and move aside (nobody walks through cats).
const DODGE_R := 0.8
## A creature of Nyx closer than this wakes a sleeping cat, which runs off.
const THREAT_R := 3.6
## Cats are drawn larger than life so they read from the high game camera.
const SCALE := 1.75
## Holding Interact this long pets the cat.
const PET_HOLD := 0.5
const PET_RANGE := 1.5
const NAMES := {"orange": "Zorba", "calico": "Melina", "tuxedo": "Sócrates", "grey": "Nefeli", "white": "Ariadna", "black": "Hécate"}
## Prompt lines per state ("%s" = the cat's name).
const LINES := {
	SIT: ["%s toma el sol.", "%s vigila el mar.", "%s se lame una pata.", "%s te mira de reojo."],
	LOAF: ["%s se ha hecho una hogaza.", "%s dormita al sol.", "%s ronronea bajito."],
	STRETCH: ["%s se despereza.", "%s estira las patas."],
	WALK: ["%s pasea con la cola en alto.", "%s ronda por la aldea."],
	APPROACH: ["%s viene a saludarte."],
	GREET: ["%s te saluda con la cola.", "%s se frota contra tu pierna."],
	WAKE: ["%s bosteza y se despereza."],
	BED: ["%s busca dónde dormir."],
}

var amb: Ambient
var rig: ModelsAnimals.CatRig
var rng := RandomNumberGenerator.new()
var home := Vector3.ZERO
var bed := Vector3.ZERO
## The house this cat lives by (null: the well, the plaza or a village site).
var home_house: Node3D = null
## House cats move in by the houses as they are built; the lighthouse and well cats stay put.
var house_cat := false
var pos := Vector3.ZERO
var yaw := 0.0
var state := SIT
var timer := 0.0
var target := Vector3.ZERO
var via := Vector3.INF # waypoint before `target` (walks round an obstacle)
var after_walk := SIT
var walk_speed := WALK_SPEED
var cur_speed := 0.0
var look_timer := 0.0
var watching := false
var heart_timer := 0.0
var purring := false
var approach_cd := 10.0
var dodge_cd := 0.0
var threat_cd := 0.0
var hold := 0.0
var cat_name := ""
var _line := 0
var _hold_fired := false
var _moving_home := false
var _purr_spot := Vector3.INF
var _purr_pending := false
var _purr_sfx := 0.0
var _tilt := Vector2.ZERO
var _tilt_want := Vector2.ZERO
var _placed := Vector3.INF
var _checked := Vector3.INF


func _init(ambient: Ambient, coat: String, at: Vector3, seed_value: int) -> void:
	amb = ambient
	rng.seed = seed_value
	rig = ModelsAnimals.CatRig.new(coat, seed_value)
	rig.driven = true
	rig.brain = self
	rig.scale = Vector3.ONE * SCALE * rng.randf_range(0.95, 1.06)
	cat_name = NAMES.get(coat, "Gato")
	amb.add_child(rig)
	home = at
	bed = _find_bed(at)
	pos = at
	yaw = Ambient.sun_angle() + PI + rng.randf_range(-1.2, 1.2)
	approach_cd = rng.randf_range(6.0, 20.0)
	_enter(SIT if rng.randf() < 0.6 else LOAF)
	_place(1.0)


# --- homes -------------------------------------------------------------------------------------------------

## New home spot. `instant` moves the cat there at once (off screen, new game); otherwise it walks over when it
## next gets up (or hops there unseen if no straight path exists).
func set_home(p: Vector3, instant: bool) -> void:
	home = p
	bed = _find_bed(p)
	if instant:
		reset_at_home()
	else:
		_moving_home = true


## Puts the cat at home (or in bed at night), resting.
func reset_at_home() -> void:
	_moving_home = false
	via = Vector3.INF
	purring = false
	hold = 0.0
	if amb.night > 0.6:
		pos = bed
		_enter(SLEEP)
		rig.play("sleep", 0.0)
	else:
		pos = home
		var s := SIT if rng.randf() < 0.6 else LOAF
		_enter(s)
		rig.play("sit" if s == SIT else "loaf", 0.0)
	yaw = Ambient.sun_angle() + PI + rng.randf_range(-1.0, 1.0)
	_placed = Vector3.INF
	_place(1.0)


## Nearest spot to `p` (within 6 m) where a cat can sleep safely; `p` itself if there is none.
func _find_bed(p: Vector3) -> Vector3:
	if amb.cat_bed_ok(p):
		return p
	var best := p
	var best_d := INF
	for k in 40:
		var a := rng.randf() * TAU
		var q := amb.ground(p + Vector3(sin(a), 0, cos(a)) * rng.randf_range(1.0, 6.0))
		var d := q.distance_to(p)
		if d < best_d and amb.cat_bed_ok(q) and amb.path_ok(p, q, amb.cat_ok):
			best_d = d
			best = q
	return best


# --- petting API (forwarded by the rig) --------------------------------------------------------------------

func pet() -> void:
	if state == PET:
		timer = maxf(timer, PURR_TIME * 0.8) # petting again keeps it purring
		return
	Game.stats["cats"] = int(Game.stats.get("cats", 0)) + 1
	state = PET
	purring = false
	timer = 1.6 # time allowed to come round before purring anyway
	via = Vector3.INF
	_purr_spot = Vector3.INF
	_purr_pending = true
	rig.look(0.0, 0.3)
	# Instant reward: the purr starts and a first heart pops while the cat comes round.
	Sfx.play("cat_purr", pos)
	_purr_sfx = 1.85
	amb.fx.hearts(rig.head_position() + Vector3(0, 0.2, 0))


func is_pettable() -> bool:
	return state != PET and state != SLEEP and state != BED


# --- Interactables (the hero holds Interact next to the cat) -----------------------------------------------

## Daytime and dusk only, and not while it is being petted (or asleep). Never steals Interact from what Fanós is
## already holding it on (paying for a building, blowing the horn).
func can_interact(hero: Node) -> bool:
	var ph: int = Game.phase
	if ph != Game.Phase.DAY and ph != Game.Phase.DUSK:
		return false
	if hero != null and hero.get("_interacting") == true:
		var cur: Variant = hero.get("interact_target")
		if cur != null and cur != rig:
			return false
	return is_pettable() and rig.is_visible_in_tree()


func interact_range() -> float:
	return PET_RANGE


func interact_info() -> Dictionary:
	var lines: Array = LINES.get(state, LINES[SIT])
	var line: String = lines[_line % lines.size()]
	return {"title": "Gato", "verb": "Acariciar", "desc": line % cat_name, "cost": 0, "paid": 0, "afford": true,
		"progress": clampf(hold / PET_HOLD, 0.0, 1.0), "denied": false,
		"anchor": rig.global_position + Vector3(0, 1.05, 0), "kind": "cat"}


func interact_hold(delta: float, hero: Node) -> void:
	hold += delta
	# Fanós turns to the cat while reaching for it.
	var hn := hero as Node3D
	if hn != null and "facing" in hn:
		var to := pos - hn.global_position
		if to.x * to.x + to.z * to.z > 0.01:
			hn.set("facing", rotate_toward(float(hn.get("facing")), atan2(-to.x, -to.z), 8.0 * delta))
	if hold >= PET_HOLD and not _hold_fired:
		_hold_fired = true
		pet()


func interact_release(_hero: Node) -> void:
	hold = 0.0
	_hold_fired = false


# --- behaviour ---------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	timer -= dt
	approach_cd -= dt
	dodge_cd -= dt
	threat_cd -= dt
	var want_sleep := amb.night > 0.6
	var h := amb.hero_pos()
	if dodge_cd <= 0.0 and (state == SIT or state == LOAF or state == GREET or state == STRETCH or state == SLEEP or state == WAKE):
		dodge_cd = 0.15
		var w := amb.walker_near(pos, DODGE_R)
		if w.is_finite() and hold <= 0.0:
			dodge_cd = 1.2
			_dodge(w, want_sleep)
	if threat_cd <= 0.0 and state != WALK:
		threat_cd = 0.3
		var th := amb.threat_near(pos, THREAT_R)
		if th.is_finite():
			threat_cd = 1.5
			_flee(th)
	# Being reached for: look up at the hero.
	if hold > 0.0 and h.is_finite() and (state == SIT or state == LOAF or state == GREET):
		var to := _flat(h - pos)
		var rel := angle_difference(yaw, atan2(to.x, to.z))
		rig.look(clampf(rel, -1.1, 1.1), 0.35)
		if absf(rel) > 1.1:
			yaw = rotate_toward(yaw, yaw + rel, 1.5 * dt)
	match state:
		SIT, LOAF, GREET:
			if want_sleep:
				_go_to_bed()
			elif hold <= 0.0:
				_idle_look(dt)
				if timer <= 0.0:
					_decide()
		STRETCH:
			if timer <= 0.0:
				if want_sleep:
					_go_to_bed()
				elif rng.randf() < 0.6:
					_start_wander()
				else:
					_enter(SIT)
		WALK:
			if _walk_path(dt):
				_enter(after_walk)
		APPROACH:
			_approach(dt, want_sleep)
		PET:
			_pet_tick(dt, h)
		BED:
			if _walk_path(dt):
				_enter(SLEEP)
		SLEEP:
			if amb.night < 0.35:
				_enter(WAKE)
		WAKE:
			if timer <= 0.0:
				if _flat(pos - home).length() > 0.6:
					_walk_to(home, SIT)
				else:
					_enter(SIT)
	_place(dt)


func _enter(s: int) -> void:
	state = s
	_line = rng.randi() % 4
	match s:
		SIT:
			rig.play("sit")
			timer = rng.randf_range(6.0, 14.0)
		LOAF:
			rig.play("loaf")
			timer = rng.randf_range(9.0, 20.0)
		STRETCH, WAKE:
			rig.play("stretch", 0.7)
			rig.look(0.0, 0.0)
			timer = 2.1
		WALK, APPROACH, BED:
			rig.play("stand", 0.4)
		GREET:
			rig.play("sit")
			timer = rng.randf_range(4.0, 7.5)
			if Ambient.EXTRA_SFX and rng.randf() < 0.6:
				Sfx.play("cat_meow", pos, -4.0, rng.randf_range(0.9, 1.2))
		SLEEP:
			rig.play("sleep", 0.9)
			rig.look(0.0, 0.0)
	if s != WALK and s != APPROACH and s != BED:
		cur_speed = 0.0
		rig.set_locomotion(0.0)


func _decide() -> void:
	if _moving_home and _flat(pos - home).length() > 0.5:
		if _route_to(home, SIT, WALK_SPEED * (1.5 if _flat(pos - home).length() > 6.0 else 1.0)):
			_moving_home = false
			return
		if not amb.on_screen(pos) and not amb.on_screen(home):
			reset_at_home()
			return
	var h := amb.hero_pos()
	if h.is_finite() and approach_cd <= 0.0 and _flat(h - pos).length() < 9.0 and rng.randf() < 0.4:
		approach_cd = rng.randf_range(25.0, 50.0)
		_enter(APPROACH)
		return
	if _flat(pos - home).length() > WANDER_R + 1.0:
		if _route_to(home, SIT, WALK_SPEED):
			return
	var r := rng.randf()
	if state == LOAF:
		if r < 0.45:
			_enter(STRETCH)
		elif r < 0.75:
			_enter(SIT)
		else:
			_start_wander()
	else:
		if r < 0.3:
			_enter(LOAF)
		elif r < 0.65:
			_start_wander()
		elif r < 0.8:
			_enter(STRETCH)
		else:
			_enter(SIT)


func _start_wander() -> void:
	var sun := Ambient.sun_angle()
	for tries in 10:
		# Biased towards the sunny side of home.
		var a := sun + rng.randf_range(-1.6, 1.6) if rng.randf() < 0.7 else rng.randf() * TAU
		var p := amb.ground(home + Vector3(sin(a), 0, cos(a)) * rng.randf_range(0.3, WANDER_R))
		if _flat(p - pos).length() > 0.8 and amb.cat_rest_ok(p) and not amb.cat_crowded(p, 1.4, self) and amb.path_ok(pos, p, amb.cat_ok):
			_walk_to(p, LOAF if rng.randf() < 0.35 else SIT)
			return
	_enter(SIT)


func _walk_to(p: Vector3, then: int, spd: float = WALK_SPEED) -> void:
	target = p
	via = Vector3.INF
	after_walk = then
	walk_speed = spd
	_enter(WALK)


## Walks to p straight, or round an obstacle through one waypoint. False when there is no such route.
func _route_to(p: Vector3, then: int, spd: float, night_safe: bool = false) -> bool:
	var ok: Callable = amb.cat_night_ok if night_safe else amb.cat_ok
	if amb.path_ok(pos, p, ok):
		_walk_to(p, then, spd)
		return true
	var mid := (pos + p) * 0.5
	var side := _flat(p - pos).cross(Vector3.UP).normalized()
	for off in [2.5, -2.5, 5.0, -5.0, 8.0, -8.0]:
		var w := amb.ground(mid + side * float(off))
		if ok.call(w) and amb.path_ok(pos, w, ok) and amb.path_ok(w, p, ok):
			_walk_to(p, then, spd)
			via = w
			return true
	return false


## Steps out of the hero's way (a resting cat being walked into).
func _dodge(h: Vector3, sleepy: bool) -> void:
	var away := _flat(pos - h)
	var base := atan2(away.x, away.z) if away.length() > 0.01 else rng.randf() * TAU
	var ok: Callable = amb.cat_night_ok if sleepy else amb.cat_ok
	for tries in 8:
		var a := base + rng.randf_range(-1.1, 1.1)
		var p := amb.ground(pos + Vector3(sin(a), 0, cos(a)) * rng.randf_range(0.9, 1.4))
		if ok.call(p) and amb.path_ok(pos, p, ok):
			_walk_to(p, SLEEP if sleepy else SIT, TROT_SPEED)
			return


## Runs off from a creature of Nyx (or anything that looms at night) and curls up again further away.
func _flee(from: Vector3) -> void:
	if state == PET:
		return
	var away := _flat(pos - from)
	var base := atan2(away.x, away.z) if away.length() > 0.01 else rng.randf() * TAU
	for tries in 12:
		var a := base + rng.randf_range(-0.9, 0.9)
		var p := amb.ground(pos + Vector3(sin(a), 0, cos(a)) * rng.randf_range(4.0, 7.0))
		if amb.cat_night_ok(p) and amb.path_ok(pos, p, amb.cat_night_ok):
			_walk_to(p, SLEEP if amb.night > 0.6 else SIT, SCAMPER_SPEED)
			return


func _go_to_bed() -> void:
	if _flat(pos - bed).length() < 0.4:
		_enter(SLEEP)
	elif _route_to(bed, SLEEP, WALK_SPEED * 1.5):
		state = BED
		_line = rng.randi() % 4
	else:
		_enter(SLEEP)


func _approach(dt: float, want_sleep: bool) -> void:
	var h := amb.hero_pos()
	if not h.is_finite() or want_sleep or _flat(h - home).length() > 12.0:
		if not _route_to(home, SIT, WALK_SPEED):
			_enter(SIT)
		return
	var to := _flat(h - pos)
	var d := to.length()
	if d < 1.1:
		_enter(GREET)
		return
	var goal := h - to.normalized() * 0.95
	if not amb.cat_ok(goal) or not amb.path_ok(pos, goal, amb.cat_ok):
		_enter(SIT)
		return
	if _walk(dt, goal, TROT_SPEED * clampf(d / 3.0, 0.55, 1.0)):
		_enter(GREET)


func _pet_tick(dt: float, h: Vector3) -> void:
	if not purring:
		# Come round to the camera side of Fanós (south of him, where his body and lens do not hide the cat),
		# then sit and purr.
		if h.is_finite() and timer > 0.0:
			if _purr_pending:
				_purr_pending = false
				_choose_purr_spot(h)
			if _purr_spot.is_finite() and not _walk_path(dt):
				return
		purring = true
		_purr_spot = Vector3.INF
		via = Vector3.INF
		timer = PURR_TIME
		heart_timer = 0.5
		cur_speed = 0.0
		rig.set_locomotion(0.0)
		rig.play("pet", 0.4)
		amb.fx.hearts(rig.head_position() + Vector3(0, 0.2, 0), 2)
		var u := amb.hero as Unit
		if u != null and u.rig != null and not u.rig.is_busy() and h.is_finite() and _flat(h - pos).length() < 1.6:
			u.rig.play("build") # a little bow to pat the cat
	if h.is_finite():
		var to := _flat(h - pos)
		var d := to.length()
		if d > 0.05:
			yaw = rotate_toward(yaw, atan2(to.x, to.z), 3.0 * dt)
		if d > 2.6:
			timer = minf(timer, 0.3) # Fanós walked off
		elif d < 1.6:
			_turn_hero_to_me(dt)
	rig.look(0.0, 0.0)
	_purr_sfx -= dt
	if _purr_sfx <= 0.0 and timer > 1.2:
		_purr_sfx = 1.85
		Sfx.play("cat_purr", pos, -1.5)
	heart_timer -= dt
	if heart_timer <= 0.0 and timer > 0.6:
		heart_timer = rng.randf_range(0.42, 0.6)
		amb.fx.hearts(rig.head_position() + Vector3(0, 0.2, 0))
	if timer <= 0.0:
		purring = false
		if amb.night > 0.6:
			_go_to_bed()
		else:
			_enter(GREET)


## Picks where to purr: 0.95 m from the hero on his camera side (south), on the side the cat is already on,
## reached without walking through him. Leaves _purr_spot INF to purr where it is.
func _choose_purr_spot(h: Vector3) -> void:
	_purr_spot = Vector3.INF
	var side := 1.0 if pos.x >= h.x else -1.0
	var here := _flat(pos - h)
	if here.z > 0.25 and here.length() > 0.7 and here.length() < 1.25:
		return # already in view, close enough
	for deg in [45.0, 25.0, 70.0, -45.0, -25.0, -70.0, 0.0, 95.0, -95.0]:
		var a := deg_to_rad(float(deg)) * side
		var p := amb.ground(h + Vector3(sin(a), 0, cos(a)) * 0.95)
		if not amb.cat_ok(p) or _flat(p - pos).length() > 3.0:
			continue
		# Round the hero's side if the straight line would brush him.
		var w := Vector3.INF
		if _seg_dist(h, pos, p) < 0.6:
			var s2 := 1.0 if p.x >= h.x else -1.0
			w = amb.ground(h + Vector3(s2 * 1.05, 0, 0.0))
			if not amb.cat_ok(w) or not amb.path_ok(pos, w, amb.cat_ok) or not amb.path_ok(w, p, amb.cat_ok):
				continue
		elif not amb.path_ok(pos, p, amb.cat_ok):
			continue
		_purr_spot = p
		target = p
		via = w
		walk_speed = TROT_SPEED * 1.3
		rig.play("stand", 0.3)
		return


## Fanós (standing still) turns towards the purring cat.
func _turn_hero_to_me(dt: float) -> void:
	var hn := amb.hero
	if hn == null or not is_instance_valid(hn) or not ("facing" in hn) or not ("vel" in hn):
		return
	var v: Vector3 = hn.get("vel")
	if v.x * v.x + v.z * v.z > 0.04:
		return
	var to := pos - hn.global_position
	if to.x * to.x + to.z * to.z > 0.01:
		hn.set("facing", rotate_toward(float(hn.get("facing")), atan2(-to.x, -to.z), 5.0 * dt))


static func _seg_dist(c: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var t := clampf(ac.dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (ac - ab * t).length()


## Head turns while idle; tracks the hero for a while when they are close.
func _idle_look(dt: float) -> void:
	look_timer -= dt
	var h := amb.hero_pos()
	var near := h.is_finite() and _flat(h - pos).length() < 7.5
	if look_timer <= 0.0:
		look_timer = rng.randf_range(1.8, 4.5)
		watching = near and (rng.randf() < 0.7 or state == GREET)
		if not watching:
			if rng.randf() < 0.35:
				rig.look(0.0, 0.0)
			else:
				rig.look(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.1, 0.22))
	if watching:
		if not near:
			watching = false
			rig.look(0.0, 0.0)
			return
		var to := _flat(h - pos)
		var rel := angle_difference(yaw, atan2(to.x, to.z))
		if absf(rel) > 1.15 or state == GREET:
			# Shuffle round to face the hero (slowly while sitting).
			yaw = rotate_toward(yaw, yaw + rel, (1.6 if state == GREET else 0.7) * dt)
		var up := clampf(0.5 / maxf(to.length(), 0.6), 0.05, 0.45)
		rig.look(clampf(rel, -1.15, 1.15), up)


## Follows the current route (waypoint, then target); true on arrival.
func _walk_path(dt: float) -> bool:
	if via.is_finite():
		if _walk(dt, via, walk_speed, false):
			via = Vector3.INF
		return false
	return _walk(dt, target, walk_speed)


## Steers towards p; returns true on arrival. Slows down for sharp turns and near the goal (unless `stop` is
## false: a waypoint is passed at speed).
func _walk(dt: float, p: Vector3, spd: float, stop: bool = true) -> bool:
	var to := _flat(p - pos)
	var d := to.length()
	if d < (0.1 if stop else 0.35):
		if stop:
			cur_speed = 0.0
			rig.set_locomotion(0.0)
		return true
	var want := atan2(to.x, to.z)
	var diff := angle_difference(yaw, want)
	yaw = rotate_toward(yaw, want, TURN_RATE * (1.6 if spd > 2.0 else 1.0) * dt)
	var goal_speed := spd * (clampf(d / 0.6, 0.3, 1.0) if stop else 1.0) * clampf(cos(diff), 0.12, 1.0)
	cur_speed = move_toward(cur_speed, goal_speed, dt * (5.0 if spd > 2.0 else (3.5 if spd >= 1.0 else 2.2)))
	var np := pos + Vector3(sin(yaw), 0, cos(yaw)) * minf(cur_speed * dt, d)
	# Routes are checked before setting off; re-check the ground every 0.25 m (a building may have risen).
	if _flat(np - _checked).length() > 0.25:
		if not amb.cat_ok(np):
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
		pos = amb.push_out(pos, 0.22)
		pos.y = amb.ground_y(pos.x, pos.z)
		var f := Vector3(sin(yaw), 0, cos(yaw)) * 0.28
		var r := Vector3(f.z, 0, -f.x) * 0.6
		var hf := amb.ground_y(pos.x + f.x, pos.z + f.z)
		var hb := amb.ground_y(pos.x - f.x, pos.z - f.z)
		var hr := amb.ground_y(pos.x + r.x, pos.z + r.z)
		var hl := amb.ground_y(pos.x - r.x, pos.z - r.z)
		_tilt_want = Vector2(-atan2(hf - hb, 0.56) * 0.85, atan2(hr - hl, 0.34) * 0.7)
	elif _tilt.distance_squared_to(_tilt_want) < 1e-7:
		return
	_tilt = _tilt.lerp(_tilt_want, 1.0 - exp(-dt * 8.0)) if dt < 1.0 else _tilt_want
	rig.position = pos
	rig.rotation = Vector3(_tilt.x, yaw, _tilt.y)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
