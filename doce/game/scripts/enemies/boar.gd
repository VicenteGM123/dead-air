class_name Boar
extends Enemy
## A wild boar of Nemea (ENCOUNTERS, lane P; docs/ENCOUNTERS.md). GDD: "embisten en línea recta tras un aviso; se
## esquivan o se paran con el escudo en el momento justo; si chocan contra una roca quedan aturdidos". 1-2 per
## clearing (World.spawn_groups(): WORLD rings each boar clearing with standing rocks to charge into); the herd shares
## a BeastPack (pack.gd: alert, leash, reset when the hero falls, one charge at a time).
##
##   IDLE        roots about its home spot, snorting now and then; frozen far from the camera
##   NOTICE      the herd noticed the hero: it turns to him, bristles up, a loud snort
##   READY       faces him (a heavy beast: it turns slowly), keeps its distance; with the herd's token: a charge
##   REPOSITION  a rock between it and the hero: it shuffles sideways for a clear line (then charges anyway)
##   WINDUP      the telegraph (COMBAT.md 6.4): rig charge_windup (1.3 s: head down, paws the ground twice with dust,
##               rocks back, tail up, the eyes flaring), boar_charge (the squeal, then hooves), a gold glint at the
##               tusks; it tracks the hero for the first 75 % and then the line is set
##   CHARGE      straight along that line at CHARGE_SPEED (steering only a little in its first STEER_TIME s), dust
##               flying; a glint at the tusks ~0.35 s before it reaches him (the parry cue). Contact: hurt (heavy hit,
##               knocked back), blocked (the shield holds: much stamina, he is pushed back, the boar is stopped),
##               parried (the charge breaks: stagger 1.8 s, sparks), dodged (it goes on). A rock, a trunk, a wall or
##               the boulder in its way (layer 1 / 4) at speed: CRASH - stunned STUN s (stars, boar_crash, shake),
##               open to every blow (damage x1.25 while stunned). Past the hero by OVERSHOOT m, too long, or a drop /
##               the sea ahead: it skids to a stop (an opening while it turns round)
##   GORE        close range (the hero within GORE_RANGE in front): the tusk toss, telegraphed (the gore's head-down
##               anticipation held, a glint, a snort): blockable, parryable
##   RECOVER     after a charge or a gore: the opening
##   RETURN      leash or the hero fell: walks home, healing
## Poise 0.7: light blows do not interrupt it (the finisher, the heavy blow, a parry, a crash do). Chain kind &"beast": a yank
## slides it 2.2 m towards the hero (stunned if it slams into a rock on the way: the lion's rule), breaks a wind-up
## and turns it to face him. Heavy: 120 hp, knockback resist 0.65. Death: topples, boar_die, dust, a shake.

enum { IDLE, NOTICE, READY, REPOSITION, WINDUP, CHARGE, SKID, GORE, RECOVER, RETURN }
const ST_NAMES: Array[StringName] = [&"idle", &"notice", &"ready", &"reposition", &"windup", &"charge", &"skid", &"gore",
	&"recover", &"return"]

const WALK := 1.1
const TROT := 3.0
const TURN := 2.4
## The charge.
const WINDUP_T := 1.3
const CHARGE_SPEED := 10.5
const CHARGE_ACCEL := 30.0
const CHARGE_MIN := 4.5
const CHARGE_MAX := 17.0
const CHARGE_TIME := 2.6
const CHARGE_DIST := 24.0
const OVERSHOOT := 3.5
const STEER_TIME := 0.3
const STEER_RATE := 0.5
const SKID_DECEL := 15.0
## Faster than this (m/s) into the world: a crash.
const CRASH_SPEED := 4.0
const STUN := 3.0
const CHARGE_DMG := 28.0
const CHARGE_KNOCK := 10.0
const CHARGE_STAGGER := 0.7
## Root to the hero's surface (m) where the tusks meet him; half-width of the charge's path (m).
const HIT_REACH := 1.15
const HIT_LANE := 0.8
## The gore (close range).
const GORE_RANGE := 2.5
const GORE_HOLD := Vector2(0.12, 0.22)
const GORE_DMG := 18.0
const GORE_KNOCK := 7.0
const GORE_STAGGER := 0.6
const GORE_REACH := 1.3
## Speed (m/s) of the short lunge between the held anticipation and the toss.
const GORE_LUNGE := 7.0
const GORE_CD := 2.2
const STUNNED_DAMAGE := 1.25
## (ENCOUNTERS merge) No juggling: blows that keep a boar staggered (each combo finisher, stagger 0.75 >= poise 0.7,
## re-staggered it before it recovered: a parried boar was cut down in ~4 s without ever getting up) stop staggering
## it once it has been helpless HELPLESS_MAX s in a row: it shrugs them off (poise ARMOR_POISE) until it has charged
## or gored again, or ARMOR_T s have passed. A crash's stun (3 s, blows x1.25) is not counted.
const HELPLESS_MAX := 2.6
const ARMOR_T := 2.0
const ARMOR_POISE := 99.0

var home_spot := Vector3.ZERO
var pack: BeastPack = null
var st := IDLE
var st_t := 0.0
## Tests and tuning.
var charges := 0
var crashes := 0
var gores := 0
var hits_landed := 0
var parried_count := 0
var blocked_count := 0
var last_charge_result := &""
var _ch_dir := Vector3.FORWARD
var _ch_speed := 0.0
var _ch_from := Vector3.ZERO
var _ch_resolved := false
var _ch_glint := false
var _token := false
var _gore_cd := 0.0
var _hold := 0.15
var _released := false
var _gore_done := false
var _rec_len := 0.8
var _was_stunned := false
var _snort_t := 4.0
var _wander_to := Vector3.INF
var _wander_t := 2.0
var _repos_dir := 1.0
var nav: PackNav
var _dust_tick := 0
var _lod_t := 0.0
var _rig_awake := true
var _cs_feet: CollisionShape3D
var _cs_body: CollisionShape3D
var _rng := RandomNumberGenerator.new()
var _helpless_t := 0.0
var _armor_t := 0.0
var _poise_base := 0.7


func _init() -> void:
	display_name = "Jabalí"
	max_hp = 150.0
	radius = 0.55
	height = 0.95
	lock_height = 0.75
	chain_weight = &"beast"
	knockback_resist = 0.65
	poise = 0.7
	corpse_time = 6.0
	parry_stagger = 1.8
	chain_slide = 2.2
	stun_on_slam = 3.0
	_rng.randomize()
	nav = PackNav.new(self, 1.9)


func _build() -> void:
	var r := RigBoar.new()
	add_child(r)
	rig = r
	var k := r.size_k
	_cs_feet = CollisionShape3D.new()
	var feet := CapsuleShape3D.new()
	feet.radius = 0.3 * k
	feet.height = 0.86 * k
	_cs_feet.shape = feet
	_cs_feet.position = Vector3(0, feet.height * 0.5, 0.0)
	add_child(_cs_feet)
	_cs_body = CollisionShape3D.new()
	var body := CapsuleShape3D.new()
	body.radius = 0.3 * k
	body.height = 1.56 * k
	_cs_body.shape = body
	# along the body: the snout 1.0 m ahead, the rump 0.56 m behind (the node turns with `facing`)
	_cs_body.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.55 * k, -0.22 * k))
	add_child(_cs_body)
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("height_at"):
		r.ground_fn = Callable(nav, "ground_y") # the terrain, or the top of a rock it stands against
	r.event.connect(_on_rig_event)


func boar_rig() -> RigBoar:
	return rig as RigBoar


func _ready() -> void:
	if not BeastPack.enabled():
		# (enemies=0, or CORE's island bot: the slice walk does not fight) no tick before it goes
		set_physics_process(false)
		set_process(false)
		queue_free()
		return
	super._ready()


func teleport(p: Vector3, yaw: float = facing) -> void:
	super.teleport(p, yaw)
	rotation = Vector3(0.0, facing, 0.0)
	if pack == null and is_inside_tree() and not is_queued_for_deletion():
		home_spot = global_position
		pack = BeastPack.join(self, &"boar")


func pack_size_k() -> float:
	return (rig as RigBoar).size_k


# --- the pack's calls -------------------------------------------------------------------------------------------

func wants_slot() -> bool:
	return false


func member_ready() -> bool:
	if not alive or st != READY or stagger > 0.0 or stun > 0.0 or is_sliding():
		return false
	var h = Game.hero
	var d := Combat.flat(h.global_position - global_position).length()
	return d >= CHARGE_MIN and d <= CHARGE_MAX + 2.0 and absf(h.global_position.y - global_position.y) < 3.0


func begin_attack() -> void:
	_token = true
	if _clear_to(Game.hero):
		_start_windup()
	else:
		_set_st(REPOSITION)
		_repos_dir = -1.0 if _rng.randf() < 0.5 else 1.0


func attack_phase() -> int:
	match st:
		WINDUP:
			return 1
		CHARGE:
			return 2 if _ch_resolved else 1
		SKID, RECOVER:
			return 2
	return 0


func pack_alerted(_howl: bool) -> void:
	if alive and st in [IDLE, RETURN]:
		_set_st(NOTICE)
		Sfx.play("boar_snort", lock_point(), -2.0, _rng.randf_range(0.9, 1.05))
		if Game.fx:
			Game.fx.call("dust", global_position + forward() * 0.9, 2, 0.2)


func pack_return() -> void:
	if not alive:
		return
	_end_attack(1.0)
	_set_st(RETURN)


func pack_reset() -> void:
	if not alive:
		return
	_end_attack(1.0)
	teleport(home_spot, _rng.randf() * TAU)
	hp = max_hp
	stagger = 0.0
	stun = 0.0
	telegraph_t = 0.0
	_set_st(IDLE)
	var r := rig as RigBoar
	r.stop()
	r.hold_t = -1.0
	r.set_alert(0.0)
	r.clear_look()


func is_home() -> bool:
	return not alive or st == IDLE or Combat.flat(home_spot - global_position).length() < 1.5


# --- contracts --------------------------------------------------------------------------------------------------

func lock_point() -> Vector3:
	return (rig as RigBoar).lock_point() if rig != null else super.lock_point()


func chain_point() -> Vector3:
	return (rig as RigBoar).chest().global_position + Vector3(0, 0.12, 0) if rig != null else super.chain_point()


func hurt_volumes() -> Array:
	var r := rig as RigBoar
	var k := r.size_k
	var hips := r.q.marker(&"hips").global_position
	var chest := r.chest().global_position
	var neck := r.neck().global_position
	var muzzle := r.muzzle().global_position
	return [[hips, chest.lerp(neck, 0.5), 0.36 * k], [neck, muzzle, 0.17 * k]]


## Dazed, it takes every blow in full and a quarter more (the reward for crashing it into a rock).
func _modify_damage(_hit: Dictionary, amount: float) -> float:
	return amount * (STUNNED_DAMAGE if stun > 0.0 else 1.0)


func on_chain_attach(hero: Node) -> void:
	super.on_chain_attach(hero)
	_end_attack(1.0)
	if st in [WINDUP, CHARGE, GORE, SKID, REPOSITION]:
		_set_st(RECOVER)
		_rec_len = 0.5
	if pack != null:
		pack.alert(self)


## The yank drags it towards the hero (Enemy base: chain_slide, slammed into a rock = stunned) and turns it to him.
func on_chain_pull(hero: Node, dir: Vector3) -> void:
	super.on_chain_pull(hero, dir)
	if hero is Node3D:
		facing = _yaw_to((hero as Node3D).global_position)
	Sfx.play("boar_snort", lock_point(), -1.0, 1.3)
	(rig as RigBoar).play("hit")


# --- hooks ------------------------------------------------------------------------------------------------------

func _on_hurt(hit: Dictionary) -> void:
	if hp > 0.0:
		Sfx.play("boar_snort", lock_point(), -5.0, _rng.randf_range(1.25, 1.45)) # a squeal
	if float(hit.get("stagger", 0.0)) >= poise:
		_end_attack(0.8)
		if st in [WINDUP, CHARGE, GORE, SKID, REPOSITION]:
			_set_st(RECOVER)
			_rec_len = 0.4
	if pack != null:
		pack.alert(self)
	if st == IDLE:
		_set_st(NOTICE)


func _on_parried(hero: Node) -> void:
	parried_count += 1
	last_charge_result = &"parried"
	_end_attack(1.3)
	_ch_speed = 0.0
	_set_st(RECOVER)
	_rec_len = 0.3
	Sfx.play("boar_snort", lock_point(), 0.0, 1.45)
	if Game.fx:
		var t := (rig as RigBoar).tusks().global_position
		Game.fx.call("hit_spark", t, Combat.flat(global_position - (hero as Node3D).global_position).normalized(), 1.3)


## Crashed into the world on the chain (Enemy base slam) or in a charge: stunned, the same show.
func _on_slam(collider: Object, speed: float) -> void:
	_crash(collider, speed)


func _on_stunned(_seconds: float) -> void:
	_was_stunned = true
	(rig as RigBoar).set_alert(0.0)


func _on_death(_hit: Dictionary) -> void:
	_end_attack(1.0)
	Sfx.play("boar_die", global_position + Vector3(0, 0.6, 0))
	Game.shake(0.25)
	var r := rig as RigBoar
	r.hold_t = -1.0
	r.clear_look()
	r.set_alert(0.0)
	r.set_process(true)
	if pack != null:
		pack.on_member_died(self)


func _on_rig_event(ev: String) -> void:
	match ev:
		"scrape":
			if Game.fx:
				Game.fx.call("dust", (rig as RigBoar).paw(1).global_position, 3, 0.25)
			Sfx.play("step_grass_%d" % _rng.randi_range(1, 3), global_position, -8.0, 0.7)
		"fall":
			if Game.fx:
				Game.fx.call("dust", global_position, 9, 0.9)
			Sfx.play("body_fall", global_position, -2.0, 0.75)


# --- the brain --------------------------------------------------------------------------------------------------

func _set_st(s: int) -> void:
	st = s
	st_t = 0.0


func state_name() -> StringName:
	return ST_NAMES[st]


## The charge or gore in progress is over: the herd's token back, the held pose released.
func _end_attack(cd_scale: float) -> void:
	if rig != null:
		(rig as RigBoar).hold_t = -1.0
	telegraph_t = 0.0
	if _token:
		_token = false
		if pack != null:
			pack.release(self, cd_scale)


func _yaw_to(p: Vector3) -> float:
	var d := Combat.flat(p - global_position)
	return atan2(-d.x, -d.z) if d.length_squared() > 1e-6 else facing


var _los_q: PhysicsRayQueryParameters3D = null


## A clear run at the hero: no rock, trunk, wall or the boulder between its shoulders and his chest. The ground
## between them (a bump, a rise) does not count: the charge follows the ground.
func _clear_to(h: Node3D) -> bool:
	if h == null:
		return false
	if _los_q == null:
		_los_q = PhysicsRayQueryParameters3D.new()
		_los_q.collision_mask = 1 | 8
		_los_q.exclude = [get_rid()]
	_los_q.from = global_position + Vector3(0, 0.65, 0)
	_los_q.to = h.global_position + Vector3(0, 0.85, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_los_q)
	if hit.is_empty():
		return true
	return (hit["normal"] as Vector3).y > 0.6 or (hit["position"] as Vector3).distance_to(_los_q.to) < 0.4


func _hero() -> Node3D:
	var h = Game.hero
	return h if h != null and is_instance_valid(h) else null


func _physics_process(delta: float) -> void:
	if alive and absf(wrapf(rotation.y - facing, -PI, PI)) > 0.004:
		rotation = Vector3(0.0, facing, 0.0)
	_gore_cd = maxf(0.0, _gore_cd - delta)
	_no_juggle(delta)
	super._physics_process(delta)
	nav.after_move(delta)
	if _rig_awake:
		nav.scan_rocks()
	if not alive or rig == null:
		return
	var r := rig as RigBoar
	if st == CHARGE:
		r.set_locomotion(_ch_speed, CHARGE_SPEED)
		_check_crash()
	else:
		r.set_locomotion(Vector2(velocity.x, velocity.z).length(), CHARGE_SPEED)


## (ENCOUNTERS merge) See HELPLESS_MAX.
func _no_juggle(delta: float) -> void:
	if not alive:
		return
	if stagger > 0.0 and stun <= 0.0:
		_helpless_t += delta
		if _helpless_t > HELPLESS_MAX and _armor_t <= 0.0:
			_armor_t = ARMOR_T
			_poise_base = poise
			poise = ARMOR_POISE
	else:
		_helpless_t = 0.0
	if _armor_t > 0.0:
		_armor_t -= delta
		if _armor_t <= 0.0 or st == CHARGE or st == GORE:
			_armor_t = 0.0
			poise = _poise_base


## A charge that ran into the world (a rock, a trunk, a wall, a bank too steep, the boulder) at speed: CRASH.
func _check_crash() -> void:
	if st != CHARGE or _ch_speed < CRASH_SPEED:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if not (col is CollisionObject3D):
			continue
		var layer := (col as CollisionObject3D).collision_layer
		var n := c.get_normal()
		var nf := Vector3(n.x, 0.0, n.z)
		if n.y > 0.6 or nf.length() < 0.1 or nf.normalized().dot(-_ch_dir) < 0.5:
			continue
		if (layer & (1 | 8)) != 0:
			_crash(col, _ch_speed)
			return
		if (layer & 4) != 0:
			# another beast in the way: both stop (no stun)
			if col is Enemy:
				(col as Enemy).set("_kb", _ch_dir * 3.0)
			_skid()
			return


func _crash(_collider: Object, speed: float) -> void:
	crashes += 1
	last_charge_result = &"crash"
	_end_attack(1.4)
	_ch_speed = 0.0
	velocity = Vector3.ZERO
	_kb = -forward() * 2.2
	stun_for(STUN)
	var head := (rig as RigBoar).head().global_position
	Sfx.play("boar_crash", head, 0.0, _rng.randf_range(0.95, 1.05))
	Game.shake(clampf(0.25 + speed * 0.025, 0.3, 0.55))
	Game.hitstop(0.07)
	if Game.fx:
		Game.fx.call("impact", head + forward() * 0.35, -forward(), 1.3, Color(1.0, 0.92, 0.75))
		Game.fx.call("dust", head + forward() * 0.4, 10, 0.9)
		Game.fx.call("smoke", head + forward() * 0.4, 3, Color(0.75, 0.68, 0.55))
	_set_st(RECOVER)
	_rec_len = 0.6


func _think(delta: float) -> Vector3:
	st_t += delta
	var r := rig as RigBoar
	var h := _hero()
	if _was_stunned:
		# the stars are gone: a shake of the head, a snort, back to it
		_was_stunned = false
		r.stop()
		Sfx.play("boar_snort", lock_point(), -3.0, 0.9)
		if st != RETURN:
			_set_st(RECOVER)
			_rec_len = 0.35
	match st:
		IDLE:
			return _idle(delta, r)
		NOTICE:
			if h:
				face_towards(h.global_position, delta, TURN * 1.4)
				r.set_look_target(h.global_position + Vector3(0, 1.0, 0), 1.0)
			r.set_alert(1.0)
			if st_t > 0.75:
				_set_st(READY)
			return Vector3.ZERO
		READY:
			return _ready_think(delta, r, h)
		REPOSITION:
			return _reposition(delta, r, h)
		WINDUP:
			return _windup(delta, r, h)
		CHARGE:
			return _charge(delta, r, h)
		SKID:
			_ch_speed = move_toward(_ch_speed, 0.0, SKID_DECEL * delta)
			_dust(2)
			if _ch_speed <= 0.3:
				r.stop()
				_set_st(RECOVER)
				_rec_len = _rng.randf_range(0.7, 1.0)
			return _ch_dir * _ch_speed
		GORE:
			return _gore(delta, r, h)
		RECOVER:
			if h:
				face_towards(h.global_position, delta, TURN * 0.8)
			r.set_alert(0.7)
			if st_t >= _rec_len:
				_set_st(READY)
			return Vector3.ZERO
		RETURN:
			return _return_home(delta, r)
	return Vector3.ZERO


func _idle(delta: float, r: RigBoar) -> Vector3:
	r.set_alert(0.0)
	var h := _hero()
	if h != null and Combat.flat(h.global_position - home_spot).length() > 110.0:
		return Vector3.ZERO
	_snort_t -= delta
	if _snort_t <= 0.0:
		_snort_t = _rng.randf_range(6.0, 12.0)
		Sfx.play("boar_snort", lock_point(), -9.0, _rng.randf_range(0.9, 1.1))
	_wander_t -= delta
	if _wander_to == Vector3.INF:
		if _wander_t <= 0.0:
			var a := _rng.randf() * TAU
			_wander_to = home_spot + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.0, 4.0)
			_wander_t = 8.0
			r.clear_look()
		return Vector3.ZERO
	var d := Combat.flat(_wander_to - global_position)
	if d.length() < 0.5 or _wander_t <= 0.0:
		_wander_to = Vector3.INF
		_wander_t = _rng.randf_range(3.0, 7.0)
		# rooting: the snout to the ground in front
		r.set_look_target(global_position + forward() * 1.4 + Vector3(0, -0.6, 0), 0.9)
		return Vector3.ZERO
	face_towards(_wander_to, delta, 2.5)
	return _steer(_wander_to, WALK, 1.0)


func _ready_think(delta: float, r: RigBoar, h: Node3D) -> Vector3:
	if h == null:
		return Vector3.ZERO
	r.set_alert(1.0)
	var hp_ := h.global_position
	var to_h := Combat.flat(hp_ - global_position)
	var dist := to_h.length()
	face_towards(hp_, delta, TURN)
	r.set_look_target(hp_ + Vector3(0, 1.0, 0), 1.0)
	var front := dist > 0.05 and forward().dot(to_h / dist) > 0.7
	# right in front of the tusks: the gore (its own, no token needed)
	if dist < GORE_RANGE and front and _gore_cd <= 0.0 and absf(hp_.y - global_position.y) < 1.5:
		_start_gore(r, h)
		return Vector3.ZERO
	_snort_t -= delta
	if _snort_t <= 0.0:
		_snort_t = _rng.randf_range(3.0, 6.0)
		Sfx.play("boar_snort", lock_point(), -6.0, _rng.randf_range(0.9, 1.1))
	if dist > CHARGE_MAX:
		return _steer(hp_, TROT, 2.0)
	# (ENCOUNTERS merge: it backed off only to CHARGE_MIN - 0.5, while a charge needs CHARGE_MIN (member_ready): a
	# boar 4.0-4.5 m in front of a hero who stood still never attacked again; now it backs off to its run-up)
	if dist < CHARGE_MIN + 0.2 and not front:
		return Vector3.ZERO # turning to face him
	if dist < CHARGE_MIN + 0.2:
		# too close for a run-up and not quite in reach: it backs off a little (heavily)
		return -to_h.normalized() * 1.2
	return Vector3.ZERO


func _reposition(delta: float, r: RigBoar, h: Node3D) -> Vector3:
	if h == null:
		_end_attack(1.0)
		_set_st(READY)
		return Vector3.ZERO
	face_towards(h.global_position, delta, TURN)
	if st_t > 0.4 and int(st_t * 10.0) % 3 == 0 and _clear_to(h):
		_start_windup()
		return Vector3.ZERO
	if st_t > 2.2:
		_start_windup() # then into the rock it goes
		return Vector3.ZERO
	var to_h := Combat.flat(h.global_position - global_position).normalized()
	var side := Vector3(-to_h.z, 0.0, to_h.x) * _repos_dir
	return _steer(global_position + side * 3.0, TROT * 0.8, 0.5)


func _start_windup() -> void:
	_set_st(WINDUP)
	charges += 1
	last_charge_result = &""
	var r := rig as RigBoar
	r.hold_t = -1.0
	r.play("charge_windup")
	telegraph(WINDUP_T, r.tusks().global_position + Vector3(0, 0.15, 0), "boar_charge", 1.3)
	BeastPack.hint(&"boar_windup")


func _windup(delta: float, r: RigBoar, h: Node3D) -> Vector3:
	if h == null:
		_end_attack(1.0)
		_set_st(READY)
		return Vector3.ZERO
	r.set_alert(1.0)
	if st_t < WINDUP_T * 0.75:
		face_towards(h.global_position, delta, TURN * 1.6)
		r.set_look_target(h.global_position + Vector3(0, 0.9, 0), 1.0)
	if st_t >= WINDUP_T:
		_start_charge(r)
	return Vector3.ZERO


func _start_charge(r: RigBoar) -> void:
	_set_st(CHARGE)
	_ch_dir = forward()
	_ch_speed = 2.0
	_ch_from = global_position
	_ch_resolved = false
	_ch_glint = false
	r.play("charge")
	r.clear_look()


func _charge(delta: float, r: RigBoar, h: Node3D) -> Vector3:
	_ch_speed = move_toward(_ch_speed, CHARGE_SPEED, CHARGE_ACCEL * delta)
	# committed: only a touch of steering at the start
	if h != null and st_t < STEER_TIME:
		var want := Combat.flat(h.global_position - global_position)
		if want.length() > 0.5:
			var ang := _ch_dir.signed_angle_to(want.normalized(), Vector3.UP)
			_ch_dir = _ch_dir.rotated(Vector3.UP, clampf(ang, -STEER_RATE * delta, STEER_RATE * delta))
			facing = atan2(-_ch_dir.x, -_ch_dir.z)
	_dust(3)
	if h != null and not _ch_resolved and Combat.is_alive(h):
		var d := Combat.flat(h.global_position - global_position)
		var along := d.dot(_ch_dir)
		var lat := (d - _ch_dir * along).length()
		var surf := along - Combat.body_radius(h)
		if along > 0.0 and lat < HIT_LANE + 0.4 and absf(h.global_position.y - global_position.y) < 2.0:
			# the parry cue: a glint at the tusks just before they reach him
			var ttc := (surf - HIT_REACH) / maxf(_ch_speed, 1.0)
			if not _ch_glint and ttc < 0.38:
				_ch_glint = true
				telegraph(maxf(ttc, 0.05), r.tusks().global_position + Vector3(0, 0.2, 0), "", 0.9)
			if surf <= HIT_REACH and lat < HIT_LANE:
				_contact(h)
				if st != CHARGE:
					return Vector3.ZERO
		if along < -OVERSHOOT:
			_skid()
			return _ch_dir * _ch_speed
	if st_t > CHARGE_TIME or global_position.distance_to(_ch_from) > CHARGE_DIST or _edge_ahead():
		_skid()
	return _ch_dir * _ch_speed


## Resolves the charge reaching the hero: hurt, blocked, parried or dodged.
func _contact(h: Node3D) -> void:
	_ch_resolved = true
	var hit := Combat.make_hit(CHARGE_DMG, &"blunt", _ch_dir, CHARGE_KNOCK, CHARGE_STAGGER, self,
		{"attack": &"charge", "point": (rig as RigBoar).tusks().global_position})
	var n := attack_check(HIT_REACH + 0.35, 70.0, hit, global_position, _ch_dir)
	if bool(hit.get("parried", false)):
		return # on_parried broke the charge
	if bool(hit.get("dodged", false)):
		last_charge_result = &"dodged"
		return # through his roll: it runs on
	if n > 0:
		hits_landed += 1
		last_charge_result = &"hit"
		Sfx.play("boar_gore", (rig as RigBoar).tusks().global_position, 0.0, _rng.randf_range(0.95, 1.05))
		if Game.fx:
			Game.fx.call("dust", global_position + _ch_dir * 0.8, 5, 0.5)
		_end_attack(1.0)
		_ch_speed = 0.0
		# the tusk toss to finish it
		(rig as RigBoar).play("gore")
		(rig as RigBoar).action_t = 0.4
		_set_st(RECOVER)
		_rec_len = 0.75
	elif bool(hit.get("blocked", false)):
		blocked_count += 1
		last_charge_result = &"blocked"
		_end_attack(1.0)
		_ch_speed = 0.0
		_kb = -_ch_dir * 3.0
		stagger = maxf(stagger, 0.55)
		(rig as RigBoar).play("hit")
		_set_st(RECOVER)
		_rec_len = 0.45
	else:
		last_charge_result = &"miss"


func _skid() -> void:
	if st != CHARGE:
		return
	if last_charge_result == &"":
		last_charge_result = &"miss"
	_end_attack(1.0)
	_set_st(SKID)
	Sfx.play("step_stone_%d" % _rng.randi_range(1, 3), global_position, -4.0, 0.6)


## A drop of more than 1.4 m or the sea within 2 m ahead: the charge stops short of it.
func _edge_ahead() -> bool:
	var w = Game.world
	if w == null or not is_instance_valid(w):
		return false
	var p := global_position + _ch_dir * 2.0
	if w.has_method("is_water") and bool(w.call("is_water", p.x, p.z)):
		return true
	return float(w.call("height_at", p.x, p.z)) < global_position.y - 1.4


func _start_gore(r: RigBoar, _h: Node3D) -> void:
	_set_st(GORE)
	gores += 1
	_gore_cd = GORE_CD
	_hold = _rng.randf_range(GORE_HOLD.x, GORE_HOLD.y)
	_released = false
	_gore_done = false
	r.play("gore")
	r.hold_t = 0.3
	# the toss lands at the rig's impact (0.408 s into the gore): the anticipation, the hold, then 0.108 s
	telegraph(0.408 + _hold, r.tusks().global_position + Vector3(0, 0.15, 0), "boar_snort", 1.0)


func _gore(delta: float, r: RigBoar, h: Node3D) -> Vector3:
	if not _released:
		if h:
			face_towards(h.global_position, delta, TURN * 1.5)
		if st_t >= 0.3 + _hold:
			_released = true
			r.hold_t = -1.0
	if not _gore_done and st_t >= 0.408 + _hold:
		_gore_done = true
		var hit := Combat.make_hit(GORE_DMG, &"blunt", Vector3.ZERO, GORE_KNOCK, GORE_STAGGER, self,
			{"attack": &"gore", "point": r.tusks().global_position})
		var n := attack_check(GORE_REACH, 55.0, hit)
		if bool(hit.get("parried", false)):
			return Vector3.ZERO
		if n > 0:
			hits_landed += 1
			Sfx.play("boar_gore", r.tusks().global_position, -1.0)
		elif bool(hit.get("blocked", false)):
			blocked_count += 1
			_kb = -forward() * 2.0
	if st_t >= 0.408 + _hold + 0.45:
		_set_st(RECOVER)
		_rec_len = 0.5
	if not _released or _gore_done:
		return Vector3.ZERO
	return forward() * GORE_LUNGE # the lunge into the toss (0.11 s, ~0.75 m; his body stops it)


func _return_home(delta: float, r: RigBoar) -> Vector3:
	r.set_alert(0.0)
	r.clear_look()
	hp = minf(max_hp, hp + 15.0 * delta)
	var d := Combat.flat(home_spot - global_position)
	if st_t > RETURN_GIVE_UP and not _seen():
		teleport(home_spot, facing) # lost its way out of sight: it is simply home (never on camera)
		d = Vector3.ZERO
	if d.length() < 1.2:
		hp = max_hp
		_set_st(IDLE)
		return Vector3.ZERO
	var v := _steer(home_spot, TROT * 0.8, 1.5)
	if v.length() > 0.3:
		face_towards(global_position + v, delta, TURN)
	return v


func _dust(every: int) -> void:
	_dust_tick += 1
	if _dust_tick >= every and Game.fx:
		_dust_tick = 0
		Game.fx.call("dust", global_position - _ch_dir * 0.3, 1, 0.35)


## After this long on its way home (s), a beast out of the camera's sight is put home (a last resort: never seen).
const RETURN_GIVE_UP := 18.0


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
	_lod_t -= delta
	if _lod_t <= 0.0 and rig != null:
		_lod_t = 0.5
		var cam := get_viewport().get_camera_3d()
		var far := cam != null and cam.global_position.distance_to(global_position) > 95.0 and st == IDLE and alive
		if far == _rig_awake:
			_rig_awake = not far
			rig.set_process(_rig_awake)
