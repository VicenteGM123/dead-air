class_name Wolf
extends Enemy
## A wolf of Nemea (ENCOUNTERS, lane P; docs/ENCOUNTERS.md). Fast, in packs of 3 to 5 (GDD: "rodean, uno ataca
## mientras los otros esperan; enseñan el combo y la voltereta"). main.spawn_encounters() creates one per member of
## a World.spawn_groups() entry and teleports it: the first teleport joins the spawn group's BeastPack (pack.gd),
## which holds the pack's state (idle, alert, hunt, return), the ring round the hero and the attack tokens.
##
## A member's states:
##   IDLE      wanders round its home spot (where it spawned), sniffing about; frozen far from the camera
##   HOWL      the alpha's howl when the pack notices the hero (rig howl, wolf_howl), then it joins the ring
##   CIRCLE    its slot on the ring round the hero (4.4-5.8 m, 7.6 m when badly hurt), strafing to face him, the
##             ring turning; now and then a FEINT (a snap forward without a telegraph: only a glint means a bite)
##   APPROACH  it holds an attack token: closes to LUNGE_FROM m, facing him
##   WINDUP    the telegraph (COMBAT.md 6.4): the rig's lunge crouch held (CROUCH_T + 0.08-0.26 s), the growl, a gold
##             glint at the jaws and the eyes flaring; the bite lands exactly as telegraph_left() reaches 0
##   LUNGE     the leap: committed along the line to where the hero was (a little lead), the jaws meet him 0.35 s after
##             the crouch lets go (the rig's impact); parried -> on_parried (stagger 1.2 s, yelp); blocked -> bounced
##             off the shield; hurt -> it drops in front of him; dodged / missed -> it flies on and lands past
##   RECOVER   an opening after the landing (0.62-0.78 s after a miss, 0.3 s after a bite): punish it
##   BACKOFF   back to the ring, facing him
##   RETURN    the pack gave up (leash) or the hero fell: trots home, healing
## Every blow staggers it (poise 0.3: the combo's three blows each interrupt it; a full combo kills a grey wolf);
## the finisher and the heavy knock it back (rig stagger); chain kind &"light": yanked to land staggered in front of
## the hero (Enemy base) - a set-up for the combo. Badly hurt wolves keep further out and only attack when they are
## the last ones. Death: the rig falls on its side, wolf_die, dust, dissolve after corpse_time.
## Collision: a vertical capsule (feet) and a horizontal one from nose to rump that turns with the body (the body
## node is turned to `facing` every tick), so the head never pokes into the hero, a trunk or another wolf.

enum { IDLE, HOWL, CIRCLE, APPROACH, WINDUP, LUNGE, RECOVER, FEINT, BACKOFF, RETURN, EVADE }
const ST_NAMES: Array[StringName] = [&"idle", &"howl", &"circle", &"approach", &"windup", &"lunge", &"recover",
	&"feint", &"backoff", &"return", &"evade"]

## Coats: [rig variant, max hp, bite damage]. The first member of a pack is the alpha (dark, bigger).
const COAT_ALPHA := [1, 46.0, 19.0]
const COAT_GREY := [0, 36.0, 17.0]
const COAT_PALE := [2, 30.0, 15.0]

const WALK := 1.25
const TROT := 3.6
const RUN := 7.6
## Ring radius round the hero (m): each wolf keeps its own between RING_MIN and RING_MAX; badly hurt ones RING_HURT.
const RING_MIN := 4.4
const RING_MAX := 5.8
const RING_HURT := 7.6
const LOW_HP := 0.34
## The attack: the wind-up starts this far from the hero's centre (m).
const LUNGE_FROM := 3.0
## Rig time (s) of the lunge's deepest crouch: held there for HOLD_MIN..HOLD_MAX s (the readable part).
const CROUCH_T := 0.3
const HOLD_MIN := 0.08
const HOLD_MAX := 0.26
## Root to the hero's centre (m) where the jaws meet him (the flight is planned so it is there at the bite).
const CONTACT := 1.3
const BITE_REACH := 1.5
const BITE_ANGLE := 40.0
const BITE_KNOCK := 4.5
const BITE_STAGGER := 0.3
## Recovery after a miss (s): the opening.
const MISS_OPEN := Vector2(0.62, 0.78)
## Per-wolf pause after its own attack before it may take the token again (s).
const OWN_CD := 1.6
## Poise while committed to a bite (the wind-up and the leap until the jaws close): a light blow only flashes and
## pushes it, the bite still comes (answer it with the guard, a parry or a roll; the finisher or the heavy blow
## break it). Otherwise every blow staggers it (POISE).
const POISE := 0.3
const COMMIT_POISE := 0.55
## The hop back out of a swing: chance by state (the ring, backing off, feinting, closing in), speed, cooldown.
const EVADE_CHANCE := {CIRCLE: 0.75, BACKOFF: 0.7, FEINT: 0.5, APPROACH: 0.4}
const EVADE_SPEED := 9.5
const EVADE_CD := 1.1

var coat: Array = COAT_GREY
var bite_damage := 17.0
var home_spot := Vector3.ZERO
var pack: BeastPack = null
var st := IDLE
var st_t := 0.0
## Bites that hurt the hero, attacks begun (tests, tuning).
var bites := 0
var lunges := 0
var parried_count := 0
var _ring_r := 5.0
var _ring_wob := 0.0
var _wander_to := Vector3.INF
var _wander_t := 0.0
var _feint_t := 4.0
var _growl_t := 3.0
var _own_cd := 0.0
var _hold := 0.15
var _released := false
var _fl_from := Vector3.ZERO
var _fl_dir := Vector3.FORWARD
var _fl_len := 0.0
var _fl_t := -1.0
var _bit := false
var _bite_hit := false
var _rec_len := 0.6
var nav: PackNav
var _stuck_t := 0.0
var _lod_t := 0.0
var _rig_awake := true
var _evade_cd := 0.0
var _evade_dir := Vector3.BACK
var _howl_home := false
## Hops back out of a swing (tests, tuning).
var evades := 0
var _cs_feet: CollisionShape3D
var _cs_body: CollisionShape3D
var _rng := RandomNumberGenerator.new()
var _debug := false


func _init() -> void:
	display_name = "Lobo"
	_debug = Game.arg_on("wolfdebug")
	max_hp = 36.0
	radius = 0.45
	height = 0.85
	lock_height = 0.7
	chain_weight = &"light"
	knockback_resist = 0.0
	poise = 0.3
	corpse_time = 5.0
	parry_stagger = 1.2
	yank_stagger = 1.1
	_rng.randomize()
	nav = PackNav.new(self, 1.8)
	_ring_r = _rng.randf_range(RING_MIN, RING_MAX)
	_ring_wob = _rng.randf() * TAU
	_feint_t = _rng.randf_range(3.0, 7.0)


func _build() -> void:
	_cs_feet = CollisionShape3D.new()
	_cs_feet.shape = CapsuleShape3D.new()
	add_child(_cs_feet)
	_cs_body = CollisionShape3D.new()
	_cs_body.shape = CapsuleShape3D.new()
	add_child(_cs_body)
	_fit_shapes(1.0)


## The two capsules for a wolf of size k (RigWolf.size_k / 1.04: the grey wolf's).
func _fit_shapes(k: float) -> void:
	var feet := _cs_feet.shape as CapsuleShape3D
	feet.radius = 0.24 * k
	feet.height = 0.82 * k
	_cs_feet.position = Vector3(0, feet.height * 0.5, 0.0)
	var body := _cs_body.shape as CapsuleShape3D
	body.radius = 0.21 * k
	body.height = 1.46 * k
	# lying along the body (local -Z is the wolf's forward: the node turns with `facing`): nose 1.0 m ahead, rump 0.46
	_cs_body.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.62 * k, -0.27 * k))
	radius = 0.45 * k


## The rig for this coat (built when the wolf joins its pack: the first one is the alpha).
func _make_rig(c: Array) -> void:
	if rig != null:
		rig.queue_free()
	coat = c
	var r := RigWolf.new(int(c[0]))
	add_child(r)
	r.top_level = true
	rig = r
	max_hp = float(c[1])
	hp = max_hp
	bite_damage = float(c[2])
	var k := r.size_k / 1.04
	_fit_shapes(k)
	lock_height = 0.7 * k
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("height_at"):
		r.ground_fn = Callable(nav, "ground_y") # the terrain, or the top of a rock it stands against
	r.event.connect(_on_rig_event)
	display_name = "Lobo" if int(c[0]) != 1 else "Lobo alfa"
	_sync_visual(1.0)


func wolf_rig() -> RigWolf:
	return rig as RigWolf


## main.spawn_encounters() teleports each new wolf to its spawn spot: the first teleport joins the pack there.
func teleport(p: Vector3, yaw: float = facing) -> void:
	super.teleport(p, yaw)
	rotation = Vector3(0.0, facing, 0.0)
	if pack == null and is_inside_tree():
		_join()


func _ready() -> void:
	if not BeastPack.enabled():
		# (enemies=0, or CORE's island bot: the slice walk does not fight) no tick before it goes
		set_physics_process(false)
		set_process(false)
		queue_free()
		return
	super._ready()


func _join() -> void:
	if is_queued_for_deletion():
		return
	home_spot = global_position
	pack = BeastPack.join(self, &"wolf")
	var idx := pack.members.find(self)
	var c: Array = COAT_ALPHA if idx == 0 else (COAT_GREY if idx % 2 == 1 else COAT_PALE)
	_make_rig(c)
	_wander_t = _rng.randf_range(0.5, 3.0)


func pack_size_k() -> float:
	return (rig as RigWolf).size_k if rig != null else 1.0


# --- the pack's calls -----------------------------------------------------------------------------------------------

func wants_slot() -> bool:
	return alive and st in [CIRCLE, FEINT, BACKOFF, HOWL, RECOVER, EVADE] and not is_yanked()


func member_ready() -> bool:
	if not alive or st != CIRCLE or stagger > 0.0 or stun > 0.0 or is_yanked() or _own_cd > 0.0:
		return false
	var h = Game.hero
	if Combat.flat(h.global_position - global_position).length() > 10.0:
		return false
	# badly hurt: only when no healthier wolf is left
	if hp < max_hp * LOW_HP:
		for m in pack.members:
			if m != self and is_instance_valid(m) and (m as Wolf).alive and (m as Wolf).hp >= (m as Wolf).max_hp * LOW_HP:
				return false
	return true


func begin_attack() -> void:
	_set_st(APPROACH)
	_side = 0.0
	lunges += 1


## 0 none, 1 approaching or winding up (the bite still to come), 2 struck or recovering.
func attack_phase() -> int:
	match st:
		APPROACH, WINDUP:
			return 1
		LUNGE:
			return 2 if _bit else 1
		RECOVER:
			return 2
	return 0


func pack_alerted(howl: bool) -> void:
	if not alive:
		return
	if howl:
		_set_st(HOWL)
		facing = _yaw_to(Game.hero.global_position)
		(rig as RigWolf).play("howl")
	elif st in [IDLE, RETURN]:
		_set_st(CIRCLE)


func pack_return() -> void:
	if not alive:
		return
	_abort_attack(1.0)
	_set_st(RETURN)


## The hero fell: the alpha sits back and howls (then trots home with the others).
func victory_howl() -> void:
	if not alive or stagger > 0.0 or is_yanked():
		return
	_set_st(HOWL)
	_howl_home = true
	(rig as RigWolf).play("howl")


## At rest, the hero within earshot: a howl across the forest (it stays where it is).
func idle_howl() -> void:
	if not alive or st != IDLE:
		return
	_wander_to = Vector3.INF
	_wander_t = 3.5
	(rig as RigWolf).play("howl")


func pack_reset() -> void:
	if not alive:
		return
	_abort_attack(1.0)
	_howl_home = false
	teleport(home_spot, _rng.randf() * TAU)
	hp = max_hp
	stagger = 0.0
	stun = 0.0
	telegraph_t = 0.0
	_set_st(IDLE)
	var r := rig as RigWolf
	r.stop()
	r.hold_t = -1.0
	r.set_alert(0.0)
	r.clear_look()


func is_home() -> bool:
	return not alive or st == IDLE or Combat.flat(home_spot - global_position).length() < 1.5


# --- contracts ------------------------------------------------------------------------------------------------------

func lock_point() -> Vector3:
	if rig != null:
		return (rig as RigWolf).lock_point()
	return super.lock_point()


func chain_point() -> Vector3:
	if rig != null:
		return (rig as RigWolf).chest().global_position + Vector3(0, 0.08, 0)
	return super.chain_point()


## Two capsules for the blade: the body (hips to shoulders) and the head, from the rig's markers (they follow the
## lunge's leap, the stagger, the fall).
func hurt_volumes() -> Array:
	if rig == null:
		return super.hurt_volumes()
	var r := rig as RigWolf
	var k := r.size_k / 1.04
	var hips := r.q.marker(&"hips").global_position
	var chest := r.chest().global_position
	var neck := r.neck().global_position
	var muzzle := r.muzzle().global_position
	return [[hips, chest.lerp(neck, 0.5), 0.27 * k], [neck, muzzle, 0.14 * k]]


func on_chain_attach(hero: Node) -> void:
	super.on_chain_attach(hero)
	_abort_attack(1.0)
	if pack != null:
		pack.alert(self)


## Yanked head first: the chain bites its chest, so it comes facing the hero (the base turns it the other way).
func on_chain_pull(hero: Node, dir: Vector3) -> void:
	super.on_chain_pull(hero, dir)
	if is_yanked() and hero is Node3D:
		facing = _yaw_to((hero as Node3D).global_position)
		Sfx.play("wolf_yelp", lock_point(), -1.0, _voice_pitch() * 1.05)


# --- hooks ----------------------------------------------------------------------------------------------------------

func _on_hurt(hit: Dictionary) -> void:
	var st_k := float(hit.get("stagger", 0.0))
	if hp > 0.0:
		Sfx.play("wolf_yelp", lock_point(), -2.0, _voice_pitch() * _rng.randf_range(0.95, 1.08))
	if st_k >= poise:
		# a real blow breaks the wind-up, the leap or the howl
		_abort_attack(0.8)
		if st == HOWL:
			(rig as RigWolf).stop()
			_set_st(CIRCLE)
		elif st == FEINT:
			_set_st(CIRCLE)
	if pack != null:
		pack.alert(self)
	if st == IDLE:
		_set_st(CIRCLE)
	if hp < max_hp * LOW_HP:
		_ring_r = RING_HURT


func _on_parried(hero: Node) -> void:
	parried_count += 1
	_abort_attack(1.25)
	Sfx.play("wolf_yelp", lock_point(), 0.0, _voice_pitch() * 1.12)
	if Game.fx and rig != null:
		var m := (rig as RigWolf).muzzle().global_position
		Game.fx.call("hit_spark", m, Combat.flat(global_position - (hero as Node3D).global_position).normalized(), 1.0)
	_set_st(RECOVER)
	_rec_len = 0.25


func _on_yank_landed() -> void:
	_set_st(RECOVER)
	_rec_len = 0.2


func _on_death(_hit: Dictionary) -> void:
	_abort_attack(1.0)
	Sfx.play("wolf_die", global_position + Vector3(0, 0.5, 0), 0.0, _voice_pitch())
	if rig != null:
		(rig as RigWolf).clear_look()
		(rig as RigWolf).set_alert(0.0)
		rig.set_process(true)
	if pack != null:
		pack.on_member_died(self)


func _on_rig_event(ev: String) -> void:
	match ev:
		"howl":
			Sfx.play("wolf_howl", lock_point() + Vector3(0, 0.4, 0), 0.0, _voice_pitch() * 0.97)
		"fall":
			if Game.fx:
				Game.fx.call("dust", global_position, 6, 0.7)


func _voice_pitch() -> float:
	return clampf(1.05 / maxf(pack_size_k(), 0.5), 0.85, 1.2)


# --- the brain --------------------------------------------------------------------------------------------------

func _set_st(s: int) -> void:
	st = s
	st_t = 0.0
	_stuck_t = 0.0
	poise = COMMIT_POISE if s == WINDUP or s == LUNGE else POISE
	if rig != null:
		# a feint snaps like a bite but its eyes do not flare: only a real wind-up glints
		(rig as RigWolf).glow_cap = 1.35 if s == FEINT else -1.0


func state_name() -> StringName:
	return ST_NAMES[st]


## Ends the attack in progress (token back to the pack, the crouch released, the leap stopped).
func _abort_attack(cd_scale: float) -> void:
	if _debug and st in [APPROACH, WINDUP, LUNGE]:
		var h := _hero()
		print("WOLF %s abort st=%s st_t=%.2f dist=%.2f stagger=%.2f hp=%.0f" % [name, state_name(), st_t,
			Combat.flat(h.global_position - global_position).length() if h else -1.0, stagger, hp])
	if st in [APPROACH, WINDUP, LUNGE]:
		if rig != null:
			(rig as RigWolf).hold_t = -1.0
		telegraph_t = 0.0
		_fl_t = -1.0
		_own_cd = OWN_CD
		if st != RECOVER:
			_set_st(RECOVER)
			_rec_len = 0.3
	if pack != null:
		pack.release(self, cd_scale)


func _yaw_to(p: Vector3) -> float:
	var d := Combat.flat(p - global_position)
	return atan2(-d.x, -d.z) if d.length_squared() > 1e-6 else facing


func _hero() -> Node3D:
	var h = Game.hero
	return h if h != null and is_instance_valid(h) else null


func _physics_process(delta: float) -> void:
	if alive and absf(wrapf(rotation.y - facing, -PI, PI)) > 0.004:
		rotation = Vector3(0.0, facing, 0.0)
	_own_cd = maxf(0.0, _own_cd - delta)
	super._physics_process(delta)
	nav.after_move(delta)
	if _rig_awake:
		nav.scan_rocks()
	if rig != null and alive:
		var r := rig as RigWolf
		var v := Vector2(velocity.x, velocity.z).length()
		r.set_locomotion(v, RUN)


func _think(delta: float) -> Vector3:
	if rig == null:
		if pack == null and is_inside_tree():
			_join()
		return Vector3.ZERO
	st_t += delta
	var r := rig as RigWolf
	var h := _hero()
	_evade_cd = maxf(0.0, _evade_cd - delta)
	if h != null and EVADE_CHANCE.has(st) and _evade_cd <= 0.0 and _wants_evade(h):
		return Vector3.ZERO
	match st:
		IDLE:
			return _idle(delta, r)
		EVADE:
			return _evade(delta, r, h)
		HOWL:
			if h and not _howl_home:
				face_towards(h.global_position, delta, 6.0)
				r.set_look_target(h.global_position + Vector3(0, 1.5, 0), 0.6)
			r.set_alert(0.5)
			if st_t >= (2.4 if _howl_home else 1.75):
				r.stop()
				_set_st(RETURN if _howl_home else CIRCLE)
				_howl_home = false
			return Vector3.ZERO
		CIRCLE:
			return _circle(delta, r, h)
		FEINT:
			return _feint(delta, r, h)
		APPROACH:
			return _approach(delta, r, h)
		WINDUP:
			return _windup(delta, r, h)
		LUNGE:
			return _lunge(delta, r, h)
		RECOVER:
			if h:
				face_towards(h.global_position, delta, 2.5)
			r.set_alert(0.4)
			if st_t >= _rec_len:
				_set_st(BACKOFF)
			return Vector3.ZERO
		BACKOFF:
			return _backoff(delta, r, h)
		RETURN:
			return _return_home(delta, r)
	return Vector3.ZERO


func _idle(delta: float, r: RigWolf) -> Vector3:
	r.set_alert(0.0)
	var h := _hero()
	if h != null and Combat.flat(h.global_position - home_spot).length() > 110.0:
		return Vector3.ZERO # nobody near: it rests (no physics at all)
	_wander_t -= delta
	if _wander_to == Vector3.INF:
		r.clear_look()
		if _wander_t <= 0.0:
			var a := _rng.randf() * TAU
			_wander_to = home_spot + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.0, 4.0)
			_wander_t = 7.0
		return Vector3.ZERO
	var d := Combat.flat(_wander_to - global_position)
	if d.length() < 0.5 or _wander_t <= 0.0:
		_wander_to = Vector3.INF
		_wander_t = _rng.randf_range(2.5, 6.0)
		# a look round while it stands
		var la := _rng.randf() * TAU
		r.set_look_target(global_position + Vector3(cos(la) * 4.0, 0.4, sin(la) * 4.0), 0.5)
		return Vector3.ZERO
	face_towards(_wander_to, delta, 4.0)
	return _steer(_wander_to, WALK, 1.0)


func _circle(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if h == null or pack == null:
		return Vector3.ZERO
	var hp_ := h.global_position
	var to_h := Combat.flat(hp_ - global_position)
	var dist := to_h.length()
	_ring_wob += delta * 0.7
	var rr := _ring_r + sin(_ring_wob) * 0.45
	if hp < max_hp * LOW_HP and pack.alive_count() > 1:
		rr = RING_HURT
	var goal := _safe_slot(pack.slot_for(self, rr), hp_)
	var gd := Combat.flat(goal - global_position).length()
	var spd := clampf(gd * 1.7, 0.0, RUN if gd > 5.0 else TROT * 1.15)
	if dist < 3.6:
		spd = minf(maxf(spd, TROT * 0.8), TROT) # pressed: backs away, no faster than a trot (he can catch it)
	if dist < 10.0:
		face_towards(hp_, delta, 9.0)
		r.set_look_target(hp_ + Vector3(0, 1.4, 0), 1.0)
		r.set_alert(1.0)
	else:
		var v0 := _steer(goal, spd, 1.2)
		if v0.length() > 0.5:
			face_towards(global_position + v0, delta, 8.0)
		r.set_alert(0.6)
		return v0
	# the odd growl, the odd feint
	_growl_t -= delta
	if _growl_t <= 0.0:
		_growl_t = _rng.randf_range(4.0, 8.0)
		Sfx.play("wolf_growl", lock_point(), -11.0, _voice_pitch() * _rng.randf_range(0.95, 1.05))
	_feint_t -= delta
	if _feint_t <= 0.0:
		_feint_t = _rng.randf_range(3.5, 7.5)
		if dist < 6.8 and dist > 3.2 and not _pack_striking() and hp >= max_hp * LOW_HP:
			_set_st(FEINT)
			r.play("bite")
			Sfx.play("wolf_growl", lock_point(), -7.0, _voice_pitch() * 1.12)
			return Vector3.ZERO
	return _steer(goal, spd, 1.0)


## Is any pack member winding up or leaping right now (no feints then: only one thing to read at a time)?
func _pack_striking() -> bool:
	for m in pack.members:
		if m != self and is_instance_valid(m) and (m as Wolf).alive and (m as Wolf).st in [WINDUP, LUNGE]:
			return true
	return false


## A slot that is dry, near the hero's level and not inside a trunk or a rock; else nearer him, else where it is.
func _safe_slot(p: Vector3, hp_: Vector3) -> Vector3:
	var w = Game.world
	if w == null or not is_instance_valid(w):
		return p
	for k in 3:
		var q := hp_.lerp(p, 1.0 - 0.25 * float(k))
		var gy := float(w.call("height_at", q.x, q.z))
		var dry: bool = not w.has_method("is_water") or not bool(w.call("is_water", q.x, q.z))
		if dry and absf(gy - hp_.y) < 2.2:
			return Vector3(q.x, gy, q.z)
	return global_position


func _feint(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if h == null:
		_set_st(CIRCLE)
		return Vector3.ZERO
	face_towards(h.global_position, delta, 10.0)
	var dir := Combat.flat(h.global_position - global_position).normalized()
	if st_t < 0.32:
		return dir * 3.0 # a hop in with the snap
	if st_t < 0.75:
		return -dir * 2.2
	_set_st(CIRCLE)
	return Vector3.ZERO


## The hero swings at it (a blow starting, it in front of him within reach): it may hop back out of the way.
func _wants_evade(h: Node3D) -> bool:
	var hs := int(h.get("state"))
	if hs != Hero.St.ATTACK and hs != Hero.St.HEAVY:
		return false
	var d := Combat.flat(global_position - h.global_position)
	var dist := d.length()
	if dist > 3.4 or dist < 0.05:
		return false
	if (h as Hero).forward().dot(d / dist) < 0.55:
		return false
	_evade_cd = 0.45 # one roll of the dice per blow
	if _rng.randf() > float(EVADE_CHANCE[st]):
		return false
	# back and a little to one side, onto dry, level ground
	var away := d / dist
	for k in 3:
		var ang := (_rng.randf_range(0.15, 0.5) * (-1.0 if _rng.randf() < 0.5 else 1.0)) if k < 2 else 0.0
		var dir := away.rotated(Vector3.UP, ang)
		var land := global_position + dir * 2.0
		var w = Game.world
		if w != null and is_instance_valid(w):
			var gy := float(w.call("height_at", land.x, land.z))
			if absf(gy - global_position.y) > 1.0 or (w.has_method("is_water") and bool(w.call("is_water", land.x, land.z))):
				continue
		_evade_dir = dir
		_abort_attack(0.6)
		_set_st(EVADE)
		_evade_cd = EVADE_CD
		evades += 1
		if pack != null:
			pack.evades += 1
		(rig as RigWolf).play("evade")
		return true
	return false


func _evade(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if h != null:
		face_towards(h.global_position, delta, 7.0)
	r.set_alert(1.0)
	if st_t < 0.26:
		return _evade_dir * EVADE_SPEED
	if st_t < 0.42:
		return _evade_dir * 2.5
	_set_st(BACKOFF)
	return Vector3.ZERO


func _approach(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if h == null or not h.is_alive():
		_abort_attack(1.0)
		return Vector3.ZERO
	var hp_ := h.global_position
	var to_h := Combat.flat(hp_ - global_position)
	var dist := to_h.length()
	face_towards(hp_, delta, 10.0)
	r.set_look_target(hp_ + Vector3(0, 1.3, 0), 1.0)
	r.set_alert(1.0)
	if st_t > 3.5 or absf(hp_.y - global_position.y) > 2.0:
		if _debug:
			print("WOLF %s approach abort t=%.1f dist=%.2f dy=%.2f facing=%.2f clear=%s pos=%s" % [name, st_t, dist,
				hp_.y - global_position.y, forward().dot(to_h.normalized()), str(_clear_to(h)), str(global_position)])
		_abort_attack(0.6)
		return Vector3.ZERO
	var facing_ok := forward().dot(to_h.normalized()) > 0.87
	var back := -to_h.normalized()
	if dist <= LUNGE_FROM + 0.45:
		if _clear_to(h):
			if facing_ok:
				_start_windup(r, h)
				return Vector3.ZERO
		else:
			# a trunk or a rock between them: it circles round him for a clear line
			if _side == 0.0:
				_side = -1.0 if _rng.randf() < 0.5 else 1.0
			back = back.rotated(Vector3.UP, _side * 0.9)
	var goal := hp_ + back * LUNGE_FROM
	var spd := RUN if dist > 5.0 else TROT * 1.2
	return _steer(goal, spd, 0.8)


var _los_q: PhysicsRayQueryParameters3D = null
var _side := 0.0


## A clear line for the leap: no trunk, rock or wall between its chest and the hero's. The ground between them (a
## bump, the rise he stands on) does not count: the leap clears it.
func _clear_to(h: Node3D) -> bool:
	if _los_q == null:
		_los_q = PhysicsRayQueryParameters3D.new()
		_los_q.collision_mask = 1
		_los_q.exclude = [get_rid()]
	_los_q.from = global_position + Vector3(0, 0.7, 0)
	_los_q.to = h.global_position + Vector3(0, 0.95, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_los_q)
	if hit.is_empty():
		return true
	return (hit["normal"] as Vector3).y > 0.6 or (hit["position"] as Vector3).distance_to(_los_q.to) < 0.3


func _start_windup(r: RigWolf, h: Node3D) -> void:
	_set_st(WINDUP)
	_hold = _rng.randf_range(HOLD_MIN, HOLD_MAX)
	_released = false
	_bit = false
	_bite_hit = false
	r.play("lunge")
	r.hold_t = CROUCH_T
	if pack != null:
		pack.windups += 1
	BeastPack.hint(&"wolf_windup")
	# the bite lands when the telegraph ends: the crouch, the hold, then 0.35 s from the release to the jaws
	var t_bite := CROUCH_T + _hold + (RigWolf.LUNGE_HIT - CROUCH_T)
	telegraph(t_bite, r.muzzle().global_position + Vector3(0, 0.1, 0), "wolf_growl", 1.0)


func _windup(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if h == null:
		_abort_attack(1.0)
		return Vector3.ZERO
	var hp_ := h.global_position
	var rel := CROUCH_T + _hold
	if not _released:
		face_towards(hp_, delta, 9.0)
		r.set_look_target(hp_ + Vector3(0, 1.2, 0), 1.0)
		if st_t >= rel:
			_released = true
			r.hold_t = -1.0
	# the leap: when the rig's lunge takes off
	if st_t >= rel + (RigWolf.LUNGE_LEAP - CROUCH_T):
		_leap(h)
		return _lunge(0.0, r, h)
	var dist := Combat.flat(hp_ - global_position).length()
	if not _released and dist > LUNGE_FROM + 0.6:
		return Combat.flat(hp_ - global_position).normalized() * 1.1 # creeps in
	return Vector3.ZERO


func _leap(h: Node3D) -> void:
	_set_st(LUNGE)
	var hp_ := h.global_position
	var hv := Vector3.ZERO
	if "velocity" in h:
		hv = Combat.flat(h.get("velocity"))
	var aim := hp_ + hv.limit_length(6.0) * 0.18
	var d := Combat.flat(aim - global_position)
	if d.length() < 0.05:
		d = forward()
	_fl_dir = d.normalized()
	facing = atan2(-_fl_dir.x, -_fl_dir.z)
	_fl_from = global_position
	# planned so the root is CONTACT m from him at the bite (u = BITE_U of the flight), then on to the landing
	_fl_len = clampf((d.length() - CONTACT) / _ease(BITE_U), 0.3, 3.8)
	_fl_t = 0.0


## The flight: from the rig's leap to its landing (0.45 s), a fast-out curve (it bites at 77 % of the way).
const FLIGHT := 0.45
const BITE_U := (0.65 - 0.475) / 0.45


static func _ease(u: float) -> float:
	var w := 1.0 - clampf(u, 0.0, 1.0)
	return 1.0 - w * w * w


func _lunge(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if _fl_t < 0.0:
		_set_st(RECOVER)
		_rec_len = 0.3
		return Vector3.ZERO
	var u0 := _fl_t / FLIGHT
	_fl_t += delta
	var u1 := _fl_t / FLIGHT
	if not _bit and u1 >= BITE_U:
		_bite(h)
	if _fl_t < 0.0 or st != LUNGE:
		return Vector3.ZERO
	if u1 >= 1.0:
		_fl_t = -1.0
		_set_st(RECOVER)
		_rec_len = 0.3 if _bite_hit else _rng.randf_range(MISS_OPEN.x, MISS_OPEN.y)
		if not _bite_hit:
			BeastPack.hint(&"wolf_open")
		if Game.fx:
			Game.fx.call("dust", global_position + _fl_dir * 0.3, 4, 0.45)
		return Vector3.ZERO
	if delta <= 0.0:
		return Vector3.ZERO
	if _mate_ahead():
		# a packmate in the way: it drops short (dust, the opening) rather than leaping into its back
		_fl_t = -1.0
		if not _bit:
			_bit = true
			poise = POISE
			_release_token(1.0)
		_set_st(RECOVER)
		_rec_len = _rng.randf_range(MISS_OPEN.x, MISS_OPEN.y)
		if Game.fx:
			Game.fx.call("dust", global_position + _fl_dir * 0.4, 4, 0.45)
		return Vector3.ZERO
	var want := _fl_dir * (_ease(u1) - _ease(u0)) * _fl_len / delta
	return want.limit_length(22.0)


## Is a packmate's body right in front of the leap (within reach of the forepaws and the jaws)?
func _mate_ahead() -> bool:
	if pack == null:
		return false
	var front := global_position + _fl_dir * 0.85 + Vector3(0, 0.45, 0)
	for m in pack.members:
		if m == self or not is_instance_valid(m) or not (m as Wolf).alive:
			continue
		var w := m as Wolf
		if Combat.flat(w.global_position - global_position).dot(_fl_dir) < 0.0:
			continue
		for v in w.hurt_volumes():
			var a: Vector3 = v[0]
			var b: Vector3 = v[1]
			var ab := b - a
			var t := clampf((front - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if front.distance_to(a + ab * t) < float(v[2]) + 0.42:
				return true
	return false


func _bite(h: Node3D) -> void:
	_bit = true
	poise = POISE
	var r := rig as RigWolf
	var muz := r.muzzle().global_position
	var hit := Combat.make_hit(bite_damage, &"blunt", Vector3.ZERO, BITE_KNOCK, BITE_STAGGER, self,
		{"attack": &"bite", "point": muz})
	var n := 0
	if h != null:
		n = attack_check(BITE_REACH, BITE_ANGLE, hit, global_position, _fl_dir)
	Sfx.play("wolf_bite", muz, -1.0 if n > 0 else -6.0, _voice_pitch() * _rng.randf_range(0.95, 1.08))
	if bool(hit.get("parried", false)):
		return # on_parried already threw it back
	if n > 0:
		bites += 1
		_bite_hit = true
		if pack != null:
			pack.hits += 1
		if Game.fx:
			Game.fx.call("impact", h.global_position + Vector3(0, 1.0, 0) - _fl_dir * 0.3, _fl_dir, 0.7, Color(1.0, 0.9, 0.82))
		if Game.camera and is_instance_valid(Game.camera) and Game.camera.has_method("nudge"):
			Game.camera.call("nudge", _fl_dir, 0.25)
		# it drops where it bit (no flying through him) and springs back out of his reach
		_fl_t = -1.0
		_release_token(1.0)
		_evade_dir = -_fl_dir
		_set_st(EVADE)
		(rig as RigWolf).play("evade")
	elif bool(hit.get("blocked", false)):
		# bounced off the shield
		_fl_t = -1.0
		_kb = -_fl_dir * 3.5
		stagger = maxf(stagger, 0.45)
		r.play("hit")
		_set_st(RECOVER)
		_rec_len = 0.3
		_release_token(1.0)
	else:
		# a miss (dodged or gone): it flies on and lands past - the opening
		_release_token(1.0)


func _release_token(cd: float) -> void:
	_own_cd = OWN_CD
	if pack != null:
		pack.release(self, cd)


func _backoff(delta: float, r: RigWolf, h: Node3D) -> Vector3:
	if h == null:
		_set_st(CIRCLE)
		return Vector3.ZERO
	r.set_alert(0.7)
	face_towards(h.global_position, delta, 6.0)
	var away := Combat.flat(global_position - h.global_position)
	var dist := away.length()
	if dist >= RING_MIN - 0.3 or st_t > 1.6:
		_set_st(CIRCLE)
		return Vector3.ZERO
	away = away.normalized() if dist > 0.05 else -forward()
	return _steer(global_position + away * 3.0, TROT, 0.5)


func _return_home(delta: float, r: RigWolf) -> Vector3:
	r.set_alert(0.0)
	r.clear_look()
	hp = minf(max_hp, hp + 12.0 * delta)
	var d := Combat.flat(home_spot - global_position)
	if st_t > RETURN_GIVE_UP and not _seen():
		teleport(home_spot, facing) # lost its way out of sight: it is simply home (never on camera)
		d = Vector3.ZERO
	if d.length() < 1.2:
		hp = max_hp
		_set_st(IDLE)
		_wander_t = _rng.randf_range(1.0, 3.0)
		return Vector3.ZERO
	var v := _steer(home_spot, TROT, 1.5)
	if v.length() > 0.3:
		face_towards(global_position + v, delta, 6.0)
	return v


## Seek `goal` at `speed` (easing in within `arrive` m), apart from the other beasts, round trunks and rocks (two
## feelers, every third tick), never into the sea.
## After this long on its way home (s), a beast out of the camera's sight is put home (a last resort: never seen).
const RETURN_GIVE_UP := 14.0


## Within 40 m of the camera and in front of it (the view could show it).
func _seen() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to := global_position - cam.global_position
	return to.length() < 40.0 and to.normalized().dot(-cam.global_transform.basis.z) > 0.3


func _steer(goal: Vector3, speed: float, arrive: float) -> Vector3:
	return nav.steer(goal, speed, arrive)


func _process(delta: float) -> void:
	super._process(delta)
	# far from the camera and idle: the rig holds its pose (no solver, no skeleton)
	_lod_t -= delta
	if _lod_t <= 0.0 and rig != null:
		_lod_t = 0.5
		var cam := get_viewport().get_camera_3d()
		var far := cam != null and cam.global_position.distance_to(global_position) > 95.0 and st == IDLE and alive
		if far == _rig_awake:
			_rig_awake = not far
			rig.set_process(_rig_awake)
