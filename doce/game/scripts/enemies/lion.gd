class_name Lion
extends Enemy
## THE NEMEAN LION (ENCOUNTERS lane L; docs/ENCOUNTERS.md, "El León de Nemea"): the boss of Trabajo I.
## The rule: no blade hurts it (docs/COMBAT.md 6.2: the blow is deflected, sparks fly, the hero recoils). It is hurt
## only in the wrestle, and it can only be wrestled while it is stunned:
##   - dodge its POUNCE so it flies on into a pillar, a stalagmite, a rock or the cave wall (the slam stuns it);
##   - YANK it on the chain spear (kind &"beast", COMBAT.md 6.5) into a pillar or a wall, or off its rock perch;
##   - stunned: interact (E) to wrestle it (COMBAT.md 6.6): squeeze in the windows, hold guard through the thrashes.
## Moves: swipe (fast, short reach), bite (close), pounce (crouch, eye flare and a growl, then a long committed leap
## at where the hero stood when it left the ground), roar (an inhale, then a shockwave that shoves the hero back:
## unblockable, no damage). Every attack has a telegraph (Enemy.telegraph: glint, flash, sound) of >= 0.45 s.
## Phases by health: 100-66 % swipe / bite / pounce; at 66 % a roar, then it also bounds up onto the rock perches by
## the walls and pounces from above; at 33 % a roar and it is enraged: faster, swipe-swipe-pounce chains, more roars.
## Each phase takes about three wrestles (SQUEEZE_DMG); crossing a phase threshold ends the wrestle with that roar.
## Mouth B open (the boulder not hauled into the crack: Boulder.is_blocking(cave().seal_b, 1.2)) at <= 50 %: it
## breaks off, flees out through mouth B and comes back in through mouth A behind the hero with a surprise pounce
## and ESCAPE_HEAL of its health back (once; a stun on the way out stops it for good).
## The encounter (scripts/encounters/lion_encounter.gd) owns it: wakes it, starts and resets the fight, says the
## rule, runs the victory. Debug: force(&"pounce" | &"swipe" | &"bite" | &"roar" | &"perch" | &"escape").
## Physics: three vertical capsules along the body, turned with `facing` (the body's own rotation); enemies layer.

signal blade_bounced
signal phase_entered(phase: int)
signal lion_state(state_name: StringName)
signal slammed(kind: StringName)
signal wrestle_over(won: bool)

enum S { DEN, INTRO, PROWL, SWIPE, BITE, POUNCE, ROAR, LEAP, PERCHED, FALL, STUNNED, RECOVER, GRAPPLED, DOWNED, ESCAPE, AWAY, AMBUSH, DEAD }
const S_NAMES: Array[StringName] = [&"den", &"intro", &"prowl", &"swipe", &"bite", &"pounce", &"roar", &"leap", &"perched", &"fall",
	&"stunned", &"recover", &"grappled", &"downed", &"escape", &"away", &"ambush", &"dead"]
## Pounce sub-phases: the crouch (telegraphed), the flight, the skid on landing, the recovery.
enum P { WIND, AIR, SKID, REC }

const MAX_HP := 300.0
## A good squeeze in the wrestle (kind &"grapple"): 3 squeezes = 13.5 % of its health, so a phase (a third) takes
## about three wrestles, the whole fight nine (23 squeezes; a squeeze that crosses a phase ends its wrestle).
const SQUEEZE_DMG := 13.5
const SQUEEZES := 3
const MISSES := 3
const WRESTLE_MAX := 14.0
const THRASH_WARN := 0.5
## Health fractions where the next phase starts.
const PHASE_AT := [0.66, 0.33]
const ESCAPE_AT := 0.5
const ESCAPE_HEAL := 0.1

## Per phase: attack cooldown range (s), pounce wind-up (s) and leap speed (m/s), swipe playback speed, stun (s) after
## a slam, gait speed factor, the wrestle's beat / window / thrash period / thrash cost, roar and perch cooldowns.
const PH := [
	{"cool": Vector2(1.5, 2.3), "pounce_wind": 1.0, "leap": 13.5, "swipe": 1.0, "stun": 4.2, "move": 1.0,
		"beat": 1.3, "window": 0.5, "thrash": 2.6, "thrash_cost": 24.0, "roar_cd": 1000.0, "perch_cd": 1000.0},
	{"cool": Vector2(1.2, 1.9), "pounce_wind": 0.9, "leap": 14.0, "swipe": 1.06, "stun": 3.8, "move": 1.1,
		"beat": 1.2, "window": 0.46, "thrash": 2.3, "thrash_cost": 26.0, "roar_cd": 14.0, "perch_cd": 4.0},
	{"cool": Vector2(0.7, 1.2), "pounce_wind": 0.82, "leap": 15.0, "swipe": 1.2, "stun": 3.4, "move": 1.25,
		"beat": 1.1, "window": 0.42, "thrash": 2.0, "thrash_cost": 28.0, "roar_cd": 9.0, "perch_cd": 10.0},
]

## Gaits (m/s) and how it turns (rad/s).
const WALK := 1.6
const TROT := 4.2
const RUN := 8.5
const TURN := 6.0
## Melee reach: the hero within this many metres of its origin (the body is 3.2 m long) draws a swipe or a bite.
const MELEE_RANGE := 3.5
const POUNCE_MIN := 5.0
const POUNCE_MAX := 13.5
## A hero who keeps just out of reach (this far or more, under POUNCE_MIN) draws a short spring: a quicker crouch
## (still >= 0.62 s), a lower, shorter leap.
const SHORT_POUNCE := 3.4
const SHORT_LEAP := 11.0
## Its lair: it moves within this many metres of the arena's centre (the floor is 13.5 m round); a hero further
## than LAIR_R + 4 m (deep in a tunnel, outside) is not followed: it guards the arena (the encounter's leash ends
## the fight when he leaves the cave).
const LAIR_R := 15.5
## Swipe playback speed cap: the paw lands 0.598 s / speed after the wind-up starts, never under 0.45 s.
const SWIPE_SPEED_MAX := 1.3
## Skid after a pounce lands (m/s^2): from 13.5 m/s it carries on ~3.5 m (a pillar 1-3 m behind the hero is hit).
const SKID_DECEL := 26.0
## Horizontal speed it must still have to be stunned by what it flies into (m/s).
const SLAM_MIN := 4.0
## The pounce strikes the hero within this many metres of its chest (horizontal).
const POUNCE_REACH := 1.25
const ROAR_RANGE := 9.5
const ROAR_PUSH := 15.0
## A fall from its perch longer than this (m) stuns it (yanked off the rock).
const FALL_STUN := 1.4
## Playback speed of the death (RigLion.action_speed): in the victory's slow motion the legs buckle and it rolls
## onto its side (~1.9 s of real time to lie still) before Heracles takes the pelt.
const DEATH_SPEED := 2.4
const DEN_PACE := 4.0

# --- tuning of the hits (amount, kind, knockback, stagger) ---
const SWIPE_HIT := [14.0, &"blade", 5.5, 0.45]
const BITE_HIT := [18.0, &"blade", 4.5, 0.55]
const POUNCE_HIT := [22.0, &"blunt", 9.0, 0.8]

var encounter: Node = null
var state := S.DEN
var state_t := 0.0
var phase := 0
## Counters (tests, docs): slams by cause, wrestles, attacks.
var slams := 0
var pounce_slams := 0
var yank_slams := 0
var fall_stuns := 0
var wrestles_won := 0
var wrestles_lost := 0
var squeezes := 0
var misses := 0
var pounces := 0
var swipes := 0
var bites := 0
var roars := 0
var perches := 0
var bounces := 0
var escaped := false
var ambushes := 0
var grappled := false
## The last pounce: dodged / hit / blocked / missed (tests).
var last_pounce := &""

var _r: RigLion
var _world = null
var _cave := {}
var _outcrops: Array = [] # [{center: Vector3 (on the floor), top: float (y), r: float, launch: ...}]
var _hero: Hero = null
var _pp := P.WIND
var _cool := 1.5
var _intent := &""
var _intent_t := 0.0
var _lane_t := 0.0
var _chain_left := 0
var _roar_cd := 0.0
var _perch_cd := 0.0
var _perch := -1
var _perch_hops := 0
var _circle := 1.0
var _circle_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _spd := 0.0
var _hit_done := false
var _provoked := false
var _strike_dir := Vector3.FORWARD
# flight
var _fl_dir := Vector3.FORWARD
var _fl_vh := 0.0
var _fl_vy := 0.0
var _fl_t := 0.0
var _fl_T := 0.5
var _fl_phys := false
var _fl_attack := false
var _fl_land := Vector3.ZERO
var _fl_kind := &"pounce" # &"pounce" | &"perch_up" | &"perch_down"
var _fl_from_y := 0.0
var _fl_land_y := 0.0
var _skid_v := 0.0
var _windup := 1.0
var _hit_dir := Vector3.FORWARD
# fall off the perch
var _fall_from := 0.0
# wrestle
var _beat_t := 0.0
var _thrash_t := 0.0
var _warned := false
var _wrestle_t := 0.0
var _anchor_set := false
var _anchor_dir := Vector3.LEFT
var _anchor_neck := Vector3.ZERO
var _thrashing := 0.0
var _phase_roar_pending := false
var _down_t := 0.0
# escape / ambush
var _route: Array[Vector3] = []
var _route_i := 0
var _away_t := 0.0
var _blocked_t := 0.0
var _esc_best := INF
var _esc_stuck := 0
var _ambush_growl := false
var _escape_done := false
# den
var _den_a := Vector3.ZERO
var _den_b := Vector3.ZERO
var _den_goal := Vector3.ZERO
var _den_wait := 0.0
var _den_yaw := 0.0
var _den_perch := -1
# shapes
var _caps: Array[CollisionShape3D] = []
var _ray: PhysicsRayQueryParameters3D = null


func _init() -> void:
	display_name = "El León de Nemea"
	max_hp = MAX_HP
	radius = 1.0
	height = 1.5
	lock_height = 1.3
	chain_weight = &"beast"
	knockback_resist = 0.85
	poise = 99.0
	corpse_time = -1.0
	chain_slide = 3.6
	stun_on_slam = 4.2
	parry_stagger = 0.75
	yank_stagger = 0.5


func _build() -> void:
	_r = RigLion.new()
	rig = _r
	add_child(rig)
	# the body: three vertical capsules along it (chest and head, middle, haunches), 1.1 m wide, 1.5 m high
	for z in [-1.12, -0.1, 0.88]:
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.55
		cap.height = 1.5
		cs.shape = cap
		cs.position = Vector3(0, 0.75, z)
		add_child(cs)
		_caps.append(cs)
	# the head and muzzle, ahead of the chest (the slam stops it head first, never with its face inside the stone)
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.34
	hs.shape = sph
	hs.position = Vector3(0, 1.08, -1.72)
	add_child(hs)
	_caps.append(hs)
	add_to_group("grapplable")
	add_to_group("lion")


func _ready() -> void:
	super._ready()
	_world = Game.world
	_r.ground_fn = Callable(self, "_ground_y")
	_r.event.connect(_on_rig_event)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = 1 | 8
	_last_pos = global_position


## The encounter hands over the cave (World.cave()) and the perches (the cave builder's rock outcrops).
func setup(enc: Node, cave: Dictionary, outcrops: Array) -> void:
	encounter = enc
	_cave = cave
	_outcrops = outcrops
	var c: Vector3 = cave.get("arena_center", global_position)
	var spawn: Vector3 = cave.get("lion_spawn", c + Vector3(0, 0, -6.5))
	var away := Combat.flat(spawn - c).normalized()
	if away.length_squared() < 0.5:
		away = Vector3(0, 0, -1)
	var side := Vector3(-away.z, 0.0, away.x)
	_den_a = _floor(c + away * 8.6 + side * 2.6)
	_den_b = _floor(c + away * 8.6 - side * 2.6)
	_den_goal = _den_a
	var look := Combat.flat(c - _den_a).normalized()
	_den_yaw = atan2(-look.x, -look.z)
	# its den: the rock over the bones (a perch of the cave builder), else pacing at the back of the cave
	_den_perch = -1
	for i in _outcrops.size():
		if bool((_outcrops[i] as Dictionary).get("den", false)):
			_den_perch = i


# --- queries -------------------------------------------------------------------------------------------------

func state_name() -> StringName:
	return S_NAMES[state]


func hp_frac() -> float:
	return hp / max_hp


func is_fighting() -> bool:
	return alive and state != S.DEN and state != S.INTRO and state != S.AWAY


func in_pounce_flight() -> bool:
	return state == S.POUNCE and _pp == P.AIR


func pounce_phase() -> int:
	return _pp if state == S.POUNCE else -1


## Where the lion stands on the floor of the arena (its origin) and which way it looks.
func arena_center() -> Vector3:
	return _cave.get("arena_center", Vector3.ZERO)


func lock_point() -> Vector3:
	if _r != null and _r.q != null and visible_body():
		return _r.lock_point()
	return global_position + Vector3(0, lock_height, 0) + forward() * 0.6


func visible_body() -> bool:
	return _r != null and _r.visible


func chain_point() -> Vector3:
	return global_position + Vector3(0, 1.15, 0) + forward() * 0.85


## Blades test these: the neck and head, and the torso.
func hurt_volumes() -> Array:
	var f := forward()
	var p := global_position
	return [[p + f * 0.95 + Vector3(0, 1.15, 0), p + f * 1.7 + Vector3(0, 1.15, 0), 0.45],
		[p + f * 0.8 + Vector3(0, 0.95, 0), p - f * 0.95 + Vector3(0, 0.95, 0), 0.52]]


## The rig's ground: the island's floor, or the top of the rock it stands on.
func _ground_y(x: float, z: float) -> float:
	var y: float = _world.height_at(x, z) if _world != null else 0.0
	var gy := global_position.y
	for o: Dictionary in _outcrops:
		var top: float = o["top"]
		if gy > top - 1.0:
			var c: Vector3 = o["center"]
			var r: float = o["r"]
			if (x - c.x) * (x - c.x) + (z - c.z) * (z - c.z) < r * r:
				y = maxf(y, top)
	return y


func _floor(p: Vector3) -> Vector3:
	if _world != null and _world.has_method("height_at"):
		return Vector3(p.x, float(_world.height_at(p.x, p.z)), p.z)
	return p


func _hero_ok() -> bool:
	if _hero == null or not is_instance_valid(_hero):
		_hero = Game.hero as Hero
	return _hero != null and is_instance_valid(_hero) and _hero.is_alive()


func _to_hero() -> Vector3:
	return Combat.flat(_hero.global_position - global_position)


func _ph() -> Dictionary:
	return PH[clampi(phase, 0, 2)]


# --- control from the encounter ------------------------------------------------------------------------------

## The hero walked into the arena: it looks up, growls and stalks closer (no attacks: the labour card shows).
func wake(hero: Node) -> void:
	_hero = hero as Hero
	if state == S.DEN:
		_set_state(S.INTRO)
		Sfx.play("lion_growl", lock_point(), -2.0, 0.9)
		if _r:
			_r.set_alert(1.0)


## The fight starts: the intro roar (it shoves only a hero within reach), then it hunts.
func begin_fight() -> void:
	if not alive:
		return
	_cool = 1.2
	_fight_pending = true
	if state == S.DEN:
		_set_state(S.INTRO)


var _fight_pending := false


## The intro roar (on the ground): the fight is on.
func _fight_roar() -> void:
	_fight_pending = false
	_start_roar(0.75)
	_no_shove = true


## Back in its den at full health (the hero fell), or only up to the start of its phase (the hero left the cave).
func reset_to_den(full: bool) -> void:
	if not alive:
		return
	if grappled and _hero_ok():
		_hero.grapple_release(false)
	_end_wrestle_state()
	_show(true)
	telegraph_t = 0.0
	stun = 0.0
	stagger = 0.0
	_slide_v = Vector3.ZERO
	_kb = Vector3.ZERO
	escaped = false
	_escape_done = false
	_escape_strike = false
	_escape_pending = false
	_phase_roar_pending = false
	_route.clear()
	if full:
		hp = max_hp
		phase = 0
		if _r:
			_r.enrage = 0.0
	else:
		hp = maxf(hp, max_hp * ([1.0, 0.66, 0.33][clampi(phase, 0, 2)] as float))
	if _r:
		_r.stop()
		_r.set_alert(0.0)
		_r.clear_look()
	_perch_hops = 0
	_fight_pending = false
	if _den_perch >= 0:
		# on its rock over the bones, looking out over the arena
		var o: Dictionary = _outcrops[_den_perch]
		var spot: Vector3 = o["spot"]
		var inward := Combat.flat(arena_center() - spot).normalized()
		_perch = _den_perch
		teleport(spot + Vector3(0, 0.05, 0), atan2(-inward.x, -inward.z))
	else:
		teleport(_den_a, _den_yaw)
	rotation.y = facing
	_den_goal = _den_b
	_set_state(S.DEN)


## Tests: hold still (no moves, no attacks) while `on`.
var debug_hold := false


## Tests: in the fight at `p` (on the floor) facing `yaw`, hunting (no intro roar), its next attack in `cool` s.
func debug_place(p: Vector3, yaw: float, cool: float = 2.5) -> void:
	if not alive:
		return
	if grappled and _hero_ok():
		_hero.grapple_release(false)
	_end_wrestle_state()
	_show(true)
	_fight_pending = false
	telegraph_t = 0.0
	stun = 0.0
	stagger = 0.0
	_slide_v = Vector3.ZERO
	_kb = Vector3.ZERO
	_intent = &""
	_chain_left = 0
	_after_chain = false
	_escape_strike = false
	_escape_pending = false
	_route.clear()
	if _r:
		_r.stop()
		_r.set_alert(0.0)
	teleport(_floor(p) + Vector3(0, 0.05, 0), yaw)
	rotation.y = facing
	_cool = cool
	_set_state(S.PROWL)


## Tests: stunned now for `seconds` (as after a slam).
func debug_stun(seconds: float) -> void:
	if alive:
		_stun(seconds)


## Debug and tests: start an attack now (`what`: pounce, swipe, bite, roar, perch, escape).
func force(what: StringName) -> void:
	_hero_ok()
	if not alive:
		return
	match what:
		&"pounce":
			_start_pounce(_ph()["pounce_wind"], false)
		&"swipe":
			_start_swipe(1.0)
		&"bite":
			_start_bite()
		&"roar":
			_start_roar(0.75)
		&"perch":
			_perch_cd = 0.0
			_start_perch_run()
		&"escape":
			_start_escape()


# --- the damage contract ---------------------------------------------------------------------------------------

## No weapon cuts it: every blow but its own wrestle's squeeze bounces off (deflected).
func _modify_damage(hit: Dictionary, amount: float) -> float:
	if hit.get("kind", &"") == &"grapple":
		return amount
	hit["deflected"] = true
	return 0.0


func _on_blocked(hit: Dictionary) -> void:
	if not alive or hit.get("kind", &"") != &"blade":
		return
	bounces += 1
	if _r:
		var d: Vector3 = hit.get("dir", -forward())
		_r.set_hit_dir(d)
		_r.hit_flash(0.25)
		# a flinch of the head when it is not in the middle of something (it would cut the attack's pose)
		if state in [S.PROWL, S.DEN, S.INTRO] and (_r.action == "" or _r.action == "spark"):
			_r.play("spark")
	if state == S.DEN or state == S.INTRO:
		_wake_by_hit()
	blade_bounced.emit()


func _wake_by_hit() -> void:
	if encounter != null and encounter.has_method("lion_provoked"):
		encounter.call("lion_provoked")


func _on_hurt(_hit: Dictionary) -> void:
	Sfx.play("lion_pain", lock_point(), -2.0, randf_range(0.95, 1.05))


func _on_death(_hit: Dictionary) -> void:
	telegraph_t = 0.0
	_set_state(S.DEAD)
	if _r:
		_r.clear_look()
		_r.set_alert(0.0)
		# it falls onto its side away from him (he holds its neck: it never rolls onto him; the body does not block)
		if _hero_ok():
			var away := Combat.flat(global_position - _hero.global_position)
			if away.length_squared() > 1e-4:
				_r.set_hit_dir(away)
		# the collapse plays inside the victory's slow motion (x0.3 for 1.6 s): at the authored speed only the first
		# buckle of the legs would fit in it, the body still standing
		_r.action_speed = DEATH_SPEED


func _on_parried(_h: Node) -> void:
	# thrown open by a perfect parry: it reels back for a moment, then hunts again (or runs on, escaping)
	_hit_done = true
	if state in [S.SWIPE, S.BITE]:
		_cool = maxf(_cool, 0.9)
		_chain_left = 0
		_after_chain = false
		if _escape_strike:
			_escape_strike = false
			_set_state(S.ESCAPE)
		else:
			_set_state(S.PROWL)


# --- the chain: the beast's slide (COMBAT.md 6.5) ------------------------------------------------------------------

func on_chain_attach(hero: Node) -> void:
	_chain_hero = hero
	_hero = hero as Hero
	if state == S.DEN or state == S.INTRO:
		_wake_by_hit()


## Yanked: it slides chain_slide m along the pull (the base slide), and slams into what it meets (stunned); off
## its perch it falls and lands hard (stunned). In the air (a leap) or held down nothing happens.
func on_chain_pull(hero: Node, dir: Vector3) -> void:
	if not alive:
		return
	match state:
		S.POUNCE:
			if _pp == P.AIR or _pp == P.SKID:
				return
		S.LEAP, S.FALL, S.GRAPPLED, S.DOWNED, S.AWAY, S.DEAD:
			return
	var was := state
	# up on a rock (perched, or crouched to pounce from it): yanked off, it falls
	var perched := _on_high_ground()
	_r.stop()
	super.on_chain_pull(hero, dir)
	telegraph_t = 0.0
	_slide_slammed = false
	if perched:
		_fall_from = global_position.y
		_set_state(S.FALL)
	elif was != S.STUNNED:
		_set_state(S.PROWL)
		_provoked = true
	Sfx.play("lion_growl", lock_point(), -4.0, 1.15)


var _slide_slammed := false


## Standing up on a rock (a perch's top), more than a metre over the cave floor under it.
func _on_high_ground() -> bool:
	return global_position.y > _floor(global_position).y + 1.0


## Slammed into the world or the boulder at `speed` m/s (the chain's slide, or its own leap): stunned.
func _on_slam(collider: Object, speed: float) -> void:
	_slide_slammed = true
	_slam(collider, speed, &"yank")


func _slam(_collider: Object, speed: float, why: StringName) -> void:
	slams += 1
	if why == &"yank":
		yank_slams += 1
	else:
		pounce_slams += 1
	if state == S.ESCAPE or _route.size() > 0 or _escape_strike:
		_escape_done = true # stopped on the way out: it stays
		_route.clear()
		_escape_strike = false
	_slide_v = Vector3.ZERO
	_skid_v = 0.0
	velocity = Vector3.ZERO
	_kb = slam_normal * 2.5
	var front := global_position + forward() * 1.6 + Vector3(0, 1.0, 0)
	Game.shake(clampf(0.3 + speed * 0.03, 0.35, 0.65))
	Game.hitstop(0.09)
	if Game.fx:
		Game.fx.call("impact", front, slam_normal, 1.4, Color(1.0, 0.88, 0.62))
		Game.fx.call("dust", front - slam_normal * 0.3, 12, 1.0)
		Game.fx.call("smoke", front, 4, Color(0.62, 0.56, 0.52))
	Sfx.play("lion_thud", front, 0.0, randf_range(0.95, 1.05))
	Sfx.play("lion_pain", front, -5.0, 0.9)
	# the pillar it hit cracks (the cave builder grows a crack where it struck)
	if _world != null and _world.get("cave_builder") != null and _world.cave_builder.has_method("crack_at"):
		_world.cave_builder.call("crack_at", front - slam_normal * 0.5, slam_normal, clampf(speed / 12.0, 0.3, 1.0))
	slammed.emit(why)
	_stun(float(_ph()["stun"]))


func _stun(seconds: float) -> void:
	_set_state(S.STUNNED)
	stun_for(seconds)
	if _r:
		_r.clear_look()
		_r.set_alert(0.0)


## Dazed (Enemy.stun_for, but the stars circle a proxy node over its head instead of the lion itself: Fx.daze follows
## a node for a fixed time and cannot be told to stop, so taking the proxy out of the tree ends them at once - when
## the wrestle starts, when it recovers early, when it dies - and the lion can be freed without Fx holding it).
func stun_for(seconds: float) -> void:
	if not alive:
		return
	stun = maxf(stun, seconds)
	stagger = maxf(stagger, seconds)
	telegraph_t = 0.0
	_daze_on(seconds)
	if _r:
		_r.play("stunned")
	_on_stunned(seconds)


var _daze: Node3D = null


func _daze_on(seconds: float) -> void:
	if _daze == null:
		_daze = Node3D.new()
		_daze.name = "DazeStars"
		_daze.top_level = true
	if not _daze.is_inside_tree():
		add_child(_daze)
	_daze_follow()
	if Game.fx:
		Game.fx.call("daze", _daze, 0.5, seconds, 0.5)


func _daze_off() -> void:
	if _daze != null and _daze.is_inside_tree():
		remove_child(_daze)


func _daze_follow() -> void:
	if _daze == null or not _daze.is_inside_tree():
		return
	var h: Node3D = _r.head() if _r != null and _r.q != null else null
	_daze.global_position = h.global_position if h != null and h.is_inside_tree() else global_position + forward() * 1.5 + Vector3(0, 1.0, 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _daze != null and is_instance_valid(_daze) and not _daze.is_inside_tree():
		_daze.free()


# --- the wrestle: the grapple protocol (COMBAT.md 6.6), the target's side -------------------------------------------

func can_grapple(_h: Node) -> bool:
	return alive and state == S.STUNNED and not grappled and stun > 0.25


## Where the hero stands: at the side of its neck, his arms locked round it inside the mane (RigHeracles.GRAPPLE_HOLD
## on the neck), facing it; the side picked once per wrestle (a free spot, the one away from the pillar it hit).
func grapple_anchor(_h: Node) -> Transform3D:
	if not _anchor_set:
		_anchor_set = true
		_anchor_dir = _pick_anchor_dir()
		_anchor_neck = _neck_pos()
	_anchor_neck = _anchor_neck.lerp(_neck_pos(), 0.25)
	var at := _anchor_neck + _anchor_dir * 0.78
	at.y = global_position.y
	var z := _anchor_dir # the hero faces -Z of the basis: the neck
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), at)


## The wrestle's camera (CameraRig._frame_score asks the beast he holds, if it can say): its head and mane where they
## stand in the struggle (centre xyz, radius w), a solid thing in the view: an angle that looks at him past them is a
## poor one (the head swings ~0.4 m either way; this is where it swings round).
func wrestle_view_block() -> Vector4:
	var c := global_position + forward() * 1.3 + Vector3(0, 1.37, 0)
	return Vector4(c.x, c.y, c.z, 0.7)


func _neck_pos() -> Vector3:
	var n := global_position + forward() * 1.2 + Vector3(0, 1.1, 0)
	if _r != null and _r.q != null:
		var m := _r.neck()
		if m != null and m.is_inside_tree():
			n = m.global_position
	return n


const ANCHOR_ANGLES: Array[float] = [42.0, -42.0, 55.0, -55.0, 30.0, -30.0, 70.0, -70.0, 85.0, -85.0, 100.0, -100.0, 115.0, -115.0]
## The angle round its neck (from straight ahead) the hold is best at: beside its head, a little in front of its
## shoulder. The wrestle's camera (CameraRig._pick_grapple_offset) frames the hero from his front, which puts the lens
## nearly straight ahead of the lion; a hold further back (65 degrees and more) has the lion's head, swinging in the
## struggle, between the lens and him (hidden ~20 % of the frames, measured by the bot); here he stands beside it.
const ANCHOR_PREF := 42.0


func _pick_anchor_dir() -> Vector3:
	var f := forward()
	var left := f.rotated(Vector3.UP, PI * 0.5)
	var neck := Combat.flat(_neck_pos()) + Vector3(0, global_position.y, 0)
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1 | 8
	var best := left
	var best_s := -INF
	# the side of its head the camera is on (it frames him from round there: on the far side it would swing round past
	# the lion's head, or look at him across it)
	var cam_side := 0.0
	var cam = Game.camera
	if cam != null and is_instance_valid(cam) and ("cam" in cam) and cam.cam != null:
		cam_side = signf(((cam.cam as Camera3D).global_position - neck).dot(left))
	for ang: float in ANCHOR_ANGLES:
		var d := f.rotated(Vector3.UP, deg_to_rad(ang))
		var at := neck + d * 0.78
		at.y = global_position.y + 0.95
		q.transform = Transform3D(Basis.IDENTITY, at)
		var free := space.intersect_shape(q, 1).is_empty()
		var sc := 0.0 if free else -10.0
		sc -= absf(absf(ang) - ANCHOR_PREF) / 90.0 * 0.5
		# the side of its head away from the stone it hit (room for him and the camera): the slam normal picks the
		# side; how far round is the preference's (the haul off the stone, DRAG_OFF, makes room before its face)
		if slam_normal != Vector3.ZERO:
			sc += signf(ang) * slam_normal.dot(left) * 0.6
		# else the side he comes from, and the camera's
		if _hero != null:
			sc += d.dot(Combat.flat(_hero.global_position - neck).normalized()) * 0.3
		sc += signf(ang) * cam_side * 0.4
		if sc > best_s:
			best_s = sc
			best = d
	return best


## A beast stunned against a pillar is hauled DRAG_OFF m off it as the wrestle starts (room for the hold and the
## camera), like the arena's straw bull.
const DRAG_OFF := 1.3


func grapple_begin(hero_node: Node) -> void:
	_hero = hero_node as Hero
	if slam_normal != Vector3.ZERO and state == S.STUNNED:
		_kb = slam_normal * sqrt(2.0 * KNOCKBACK_DECAY * DRAG_OFF)
	collision_mask &= ~2
	grappled = true
	squeezes = 0
	misses = 0
	_beat_t = 0.75
	_thrash_t = float(_ph()["thrash"])
	_warned = false
	_wrestle_t = 0.0
	_thrashing = 0.0
	stun = maxf(stun, WRESTLE_MAX + 1.0)
	stagger = maxf(stagger, WRESTLE_MAX + 1.0)
	_set_state(S.GRAPPLED)
	if _r:
		_r.play("grappled")
		_r.clear_look()
	Sfx.play("lion_growl", lock_point(), -2.0, 0.8)


func grapple_input(_h: Node, timing_ok: bool) -> void:
	if not grappled or not alive:
		return
	if timing_ok:
		squeezes += 1
		Sfx.play("wrestle_squeeze", _neck_pos(), -1.0, randf_range(0.95, 1.05))
		Game.shake(0.18)
		Game.hitstop(0.05)
		var before := hp
		take_hit(Combat.make_hit(SQUEEZE_DMG, &"grapple", -forward(), 0.0, 0.0, _hero, {"attack": &"grapple"}))
		if _r:
			_r.hit_flash(0.5)
		if hp <= 0.0:
			# the last squeeze: he lets go of a dead lion
			if _hero_ok() and _hero.is_grappling():
				_hero.grapple_release(true)
			return
		var crossed := _phase_for(hp) > _phase_for(before)
		if crossed:
			_phase_roar_pending = true
			_hero.grapple_release(true)
		elif _can_escape() and before / max_hp > ESCAPE_AT:
			# this squeeze took it under half: it tears free and bolts for the crack
			_escape_pending = true
			_hero.grapple_release(true)
		elif squeezes >= SQUEEZES:
			_hero.grapple_release(true)
	else:
		misses += 1
		Sfx.play("wrestle_strain", _neck_pos(), -5.0, 0.85)
		if misses >= MISSES:
			_hero.grapple_release(false)


var _escape_pending := false
var _ghost_t := 0.0


## Off the enemies layer for `seconds` (nothing collides with it; it still collides with the world).
func _ghost(seconds: float) -> void:
	_ghost_t = maxf(_ghost_t, seconds)
	collision_layer = 0


func grapple_progress() -> float:
	return float(squeezes) / float(SQUEEZES)


func grapple_end(_h: Node, won: bool) -> void:
	if not grappled:
		return
	_end_wrestle_state()
	if won:
		wrestles_won += 1
	else:
		wrestles_lost += 1
	wrestle_over.emit(won)
	if not alive:
		return
	stun = 0.0
	stagger = 0.0
	if won:
		if _phase_roar_pending:
			_phase_roar_pending = false
			_enter_phase(_phase_for(hp))
		elif _escape_pending:
			_escape_pending = false
			if _r:
				_r.play("thrash")
			Sfx.play("lion_thrash", global_position, -2.0, 1.1)
			Game.shake(0.3)
			_start_escape()
		else:
			_set_state(S.DOWNED)
			_down_t = 1.9
			if _r:
				if _hero_ok():
					_r.set_hit_dir(Combat.flat(global_position - _hero.global_position))
				_r.play("downed")
			# thrown down away from him (his shield and sword come back to his hands right beside its mane)
			if _hero_ok():
				var away := Combat.flat(global_position - _hero.global_position)
				if away.length_squared() > 1e-4:
					_kb = away.normalized() * sqrt(2.0 * KNOCKBACK_DECAY * 1.1)
			Game.shake(0.35)
			Sfx.play("body_fall", global_position, -1.0, 0.75)
			if Game.fx:
				Game.fx.call("dust", global_position, 10, 1.2)
	else:
		# it throws him off (the hero was released or ran out of stamina): a buck and a roar-less shove
		if _r:
			_r.play("thrash")
		Sfx.play("lion_thrash", global_position, -2.0, 1.0)
		if _hero_ok():
			# away from its neck, where he held it (not from its middle: he stands by its head)
			var away := Combat.flat(_hero.global_position - _neck_pos()).normalized()
			if away.length_squared() < 0.5:
				away = -forward()
			_hero.invulnerable = 0.0
			_hero.take_hit(Combat.make_hit(8.0, &"blunt", away, 7.5, 0.6, self, {"attack": &"throw_off", "unblockable": true}))
		_cool = 1.0
		_set_state(S.RECOVER)


func _end_wrestle_state() -> void:
	if not grappled:
		return
	grappled = false
	if alive:
		collision_mask |= 2
		# he stood inside its reach while he held it: for a moment its body lets him go free (thrown off, or
		# stepping back from it thrown down) instead of the physics prying the two capsules apart
		_ghost(0.45)
	_anchor_set = false
	telegraph_t = 0.0
	if _r and (_r.action == "grappled" or _r.action == "thrash"):
		_r.stop()


func _phase_for(h: float) -> int:
	var f := h / max_hp
	if f <= float(PHASE_AT[1]):
		return 2
	if f <= float(PHASE_AT[0]):
		return 1
	return 0


func _enter_phase(p: int) -> void:
	if p <= phase:
		return
	phase = p
	if _r:
		_r.enrage = 1.0 if p >= 2 else 0.0
	phase_entered.emit(p)
	_cool = 0.6
	_roar_cd = 3.0
	_perch_cd = 1.5 if p == 1 else float(PH[p]["perch_cd"]) * 0.5
	_start_roar(0.7, true)


# --- simulation ------------------------------------------------------------------------------------------------

func _set_state(s: int) -> void:
	if s == state:
		state_t = 0.0
		return
	_ev_impact = false
	_ev_wave = false
	_detour_t = 0.0
	_stuck_t = 0.0
	state = s
	state_t = 0.0
	lion_state.emit(S_NAMES[s])


func _physics_process(delta: float) -> void:
	_prev_pos = _curr_pos
	invulnerable = maxf(0.0, invulnerable - delta)
	stagger = maxf(0.0, stagger - delta)
	stun = maxf(0.0, stun - delta)
	telegraph_t = maxf(0.0, telegraph_t - delta)
	state_t += delta
	_roar_cd -= delta
	_perch_cd -= delta
	if alive and _slide_v.length_squared() > 0.01:
		_rest_ticks = 0
		_physics_slide(delta)
		if _slide_v.length_squared() <= 0.01 and not _slide_slammed:
			_on_slide_end()
	elif alive:
		_tick(delta)
	else:
		_tick_dead(delta)
	_kb = _kb.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	if _ghost_t > 0.0:
		_ghost_t -= delta
		if _ghost_t <= 0.0 and alive and state != S.AWAY:
			collision_layer = 4
	rotation.y = facing
	_curr_pos = global_position
	var sp := Combat.flat(_curr_pos - _prev_pos).length() / maxf(delta, 1e-4)
	_spd = lerpf(_spd, sp, 1.0 - exp(-delta * 10.0))
	if _r:
		_r.set_locomotion(_spd, RUN)
	# the stars over its head only while it is dazed (not in the wrestle, not once it shakes it off or dies)
	if _daze != null and _daze.is_inside_tree():
		if alive and state == S.STUNNED:
			_daze_follow()
		else:
			_daze_off()


## The chain's slide ended without a slam: annoyed, it comes straight back at him.
func _on_slide_end() -> void:
	if state == S.FALL:
		return
	if state == S.STUNNED:
		return
	_provoked = true
	_cool = 0.35
	_set_state(S.PROWL)


func _tick(delta: float) -> void:
	_rig_events()
	match state:
		S.DEN:
			_st_den(delta)
		S.INTRO:
			_st_intro(delta)
		S.PROWL:
			_st_prowl(delta)
		S.SWIPE, S.BITE:
			_st_strike(delta)
		S.POUNCE:
			_st_pounce(delta)
		S.ROAR:
			_st_roar(delta)
		S.LEAP:
			_st_leap(delta)
		S.PERCHED:
			_st_perched(delta)
		S.FALL:
			_st_fall(delta)
		S.STUNNED:
			_st_stunned(delta)
		S.RECOVER:
			_st_recover(delta)
		S.GRAPPLED:
			_st_grappled(delta)
		S.DOWNED:
			_st_downed(delta)
		S.ESCAPE:
			_st_escape(delta)
		S.AWAY:
			_st_away(delta)
		S.AMBUSH:
			_st_ambush(delta)


func _tick_dead(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
		move_and_slide()


## Walks / runs at `want` (horizontal m/s) on the ground, with gravity and the knockback.
func _walk(want: Vector3, delta: float) -> void:
	velocity.x = want.x + _kb.x
	velocity.z = want.z + _kb.z
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -1.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
	move_and_slide()


func _look_at_hero(w: float = 1.0) -> void:
	if _r and _hero_ok():
		_r.set_look_target(_hero.global_position + Vector3(0, 1.4, 0), w)


# --- den, intro --------------------------------------------------------------------------------------------------

func _on_den_rock() -> bool:
	return _den_perch >= 0 and global_position.y > float((_outcrops[_den_perch] as Dictionary)["top"]) - 0.6


func _st_den(delta: float) -> void:
	if _on_den_rock():
		# lying in wait on its rock: still, the head turning slowly (the rig's idle)
		_walk(Vector3.ZERO, delta)
		return
	# pacing up and down at the back of its den, a look round at each end
	var to := Combat.flat(_den_goal - global_position)
	if _den_wait > 0.0:
		_den_wait -= delta
		_walk(Vector3.ZERO, delta)
		return
	if to.length() < 0.6:
		_den_wait = randf_range(1.5, 3.5)
		_den_goal = _den_b if _den_goal.distance_to(_den_a) < 0.5 else _den_a
		return
	face_towards(_den_goal, delta, 3.0)
	_walk(forward() * WALK * clampf(to.length(), 0.3, 1.0), delta)


func _st_intro(delta: float) -> void:
	if not _hero_ok():
		_walk(Vector3.ZERO, delta)
		return
	if _on_den_rock():
		# it rises on its rock, eyes on him, then bounds down into the arena
		face_towards(_hero.global_position, delta, 2.5)
		_look_at_hero()
		_walk(Vector3.ZERO, delta)
		if state_t > 1.1:
			_jump_down(false)
			_fl_kind = &"intro_down"
		return
	if _fight_pending and is_on_floor():
		_fight_roar()
		return
	# it comes out of the den, low and slow, keeping its distance, eyes on him
	var to := _to_hero()
	var d := to.length()
	face_towards(_hero.global_position, delta, 3.5)
	_look_at_hero()
	var want := Vector3.ZERO
	if d > 10.0:
		want = steer_to(_hero.global_position, WALK * 1.2, 2.0)
	elif d < 7.0:
		want = -to.normalized() * WALK
	_walk(want, delta)


# --- prowl: the brain ------------------------------------------------------------------------------------------------

func _st_prowl(delta: float) -> void:
	if debug_hold:
		_walk(Vector3.ZERO, delta)
		return
	if not _hero_ok():
		_walk(steer_to(_den_a, WALK, 1.5), delta)
		face_towards(_den_a, delta, 3.0)
		return
	var to := _to_hero()
	var d := to.length()
	var spd_k: float = _ph()["move"]
	_look_at_hero()
	if _r:
		_r.set_alert(0.6 if d > 5.0 else 0.2)
	# badly hurt with mouth B open: it runs for the crack (normally this starts in the wrestle that takes it there)
	if _can_escape():
		_start_escape()
		return
	# the hero out of its lair (deep in a tunnel, outside): it will not be drawn out of the cave; it guards the arena
	if not _in_lair(_hero.global_position, LAIR_R + 4.0):
		_guard(delta)
		return
	_cool -= delta
	# boxed in (a column between it and him, its whiskers cancelling out, or a nook by a rock): a few steps aside,
	# round the stone, then the hunt goes on
	if _detour_t > 0.0:
		_detour_t -= delta
		face_towards(global_position + _detour, delta, TURN)
		_walk(steer_to(global_position + _detour * 3.0, TROT * spd_k, 0.5), delta)
		return
	if _spd < 0.35 and state_t > 0.6:
		_stuck_t += delta
		if _stuck_t > 0.9:
			_stuck_t = 0.0
			_start_detour(to)
			return
	else:
		_stuck_t = 0.0
	if _provoked:
		_provoked = false
		_cool = minf(_cool, 0.2)
		_intent = &"pounce" if d >= POUNCE_MIN else &"melee"
		_intent_t = 0.0
	_intent_t += delta
	# a hero who stays under its nose between attacks gets swatted (it never stands still under the sword)
	if _intent == &"" and d < 2.8 and _cool > 0.3:
		_hug_t += delta
		if _hug_t > 0.9:
			_cool = 0.0
	else:
		_hug_t = 0.0
	if _cool <= 0.0 and _intent == &"":
		_intent = _pick_intent(d)
		_intent_t = 0.0
	# act on the intent
	match _intent:
		&"melee":
			if d < MELEE_RANGE:
				_intent = &""
				_strike(d)
				return
			# he keeps just out of reach: a short spring at him
			if d >= SHORT_POUNCE and d < POUNCE_MIN and _intent_t > 0.45:
				_lane_t -= delta
				if _lane_t <= 0.0:
					_lane_t = 0.15
					if _lane_clear(_hero.global_position):
						_intent = &""
						_start_pounce(maxf(float(_ph()["pounce_wind"]) * 0.72, 0.62), false, true)
						return
			# closing in: a run from afar, a trot near him
			face_towards(_hero.global_position, delta, TURN)
			var spd: float = (RUN * 0.85 if d > 6.0 else TROT * 1.3) * spd_k
			_walk(steer_to(_lair_clamp(_hero.global_position - to.normalized() * 2.4), spd, 0.8), delta)
			if _intent_t > 3.0:
				_intent = &"pounce" if d >= POUNCE_MIN else &""
				_intent_t = 0.0
				_cool = minf(_cool, 0.3)
			return
		&"pounce":
			_lane_t -= delta
			if d >= POUNCE_MIN and d <= POUNCE_MAX and _lane_t <= 0.0:
				_lane_t = 0.15
				if _lane_clear(_hero.global_position):
					_intent = &""
					_start_pounce(float(_ph()["pounce_wind"]), false)
					return
			if _intent_t > 4.0 or (d < SHORT_POUNCE and _intent_t > 1.2):
				_intent = &"melee"
				_intent_t = 0.0
				return
			# back off (or close in) to a pouncing distance, circling round a pillar in the way
			var want_d := 7.5
			_circle_t -= delta
			if _circle_t <= 0.0:
				_circle_t = randf_range(1.0, 2.2)
				if randf() < 0.3:
					_circle = -_circle
			var radial := -to.normalized() * clampf((want_d - d) * 0.8, -1.0, 1.0)
			var tang := Vector3(-to.z, 0.0, to.x).normalized() * _circle * 0.7
			var goal := _lair_clamp(global_position + (radial + tang) * 3.0)
			face_towards(_hero.global_position, delta, TURN * 0.8)
			_walk(steer_to(goal, (TROT * 1.15 if d > POUNCE_MAX else TROT) * spd_k, 1.0), delta)
			return
		&"perch":
			_intent = &""
			if not _start_perch_run():
				_cool = 0.3
			return
		&"roar":
			_intent = &""
			_start_roar(0.75)
			return
	# no intent yet: circle him at a wary distance, facing him
	_circle_t -= delta
	if _circle_t <= 0.0:
		_circle_t = randf_range(1.2, 2.6)
		if randf() < 0.35:
			_circle = -_circle
	var keep := 7.0 if phase == 0 else 6.0
	var radial2 := -to.normalized() * clampf((keep - d) * 0.6, -1.0, 1.0)
	var tang2 := Vector3(-to.z, 0.0, to.x).normalized() * _circle
	face_towards(_hero.global_position, delta, TURN * 0.7)
	_walk(steer_to(_lair_clamp(global_position + (radial2 + tang2) * 3.0), WALK * 1.4 * spd_k, 1.0), delta)


var _hug_t := 0.0
var _growl_t := 0.0
var _detour_t := 0.0
var _detour := Vector3.ZERO
var _detours := 0


## Steps aside from whatever boxes it in: of the ways round (60-120 degrees off the line to him, either side, or back),
## the one with the most room at chest height; the side it circles first, then the other one.
func _start_detour(to: Vector3) -> void:
	_detours += 1
	var fwd := to.normalized() if to.length() > 0.1 else forward()
	var space := get_world_3d().direct_space_state
	_ray.exclude = _exclude_both()
	var best := -fwd
	var best_s := -INF
	for ang: float in [70.0, -70.0, 100.0, -100.0, 45.0, -45.0, 135.0, -135.0, 180.0]:
		var dd := fwd.rotated(Vector3.UP, deg_to_rad(ang))
		_ray.from = global_position + Vector3(0, 0.9, 0)
		_ray.to = _ray.from + dd * 4.0
		var hit := space.intersect_ray(_ray)
		var room := 4.0 if hit.is_empty() else ((hit["position"] as Vector3) - _ray.from).length()
		# room first; then towards him (round the stone, not away), then the side it was circling
		var sc := minf(room, 3.0) + 0.3 * cos(deg_to_rad(ang)) + (0.25 if signf(ang) == _circle else 0.0)
		if sc > best_s:
			best_s = sc
			best = dd
	_detour = best
	_detour_t = 1.1
	_circle = -_circle
	_intent = &""
	_cool = minf(_cool, 0.4)


## Swipe or bite at a hero within reach (enraged: often a swipe-swipe chain that ends in a pounce).
func _strike(d: float) -> void:
	if phase >= 2 and randf() < 0.55:
		_chain_left = 1
		_start_swipe(float(_ph()["swipe"]))
	elif d < 3.0 and randf() < 0.45:
		_start_bite()
	else:
		_start_swipe(float(_ph()["swipe"]))


func _pick_intent(d: float) -> StringName:
	if phase >= 1 and _perch_cd <= 0.0 and not _outcrops.is_empty() and randf() < 0.4:
		return &"perch"
	if phase >= 1 and _roar_cd <= 0.0 and d < 8.5 and randf() < (0.5 if phase >= 2 else 0.35):
		return &"roar"
	if d < MELEE_RANGE + 0.1:
		return &"melee"
	if d < POUNCE_MIN:
		return &"melee" if randf() < 0.6 else &"pounce"
	return &"pounce" if randf() < 0.75 else &"melee"


## Mouth B is open and it is hurt badly enough to run for it (once per fight; a stun on the way out ends it).
func _can_escape() -> bool:
	return not escaped and not _escape_done and alive and hp_frac() <= ESCAPE_AT and _mouth_b_open()


## Within `r` m (on the floor plan) of the arena's centre.
func _in_lair(p: Vector3, r: float) -> bool:
	return Combat.flat(p - arena_center()).length() <= r


## A goal kept inside its lair (LAIR_R m round the arena's centre).
func _lair_clamp(p: Vector3) -> Vector3:
	var c := arena_center()
	var off := Combat.flat(p - c)
	if off.length() <= LAIR_R:
		return p
	var q := c + off.normalized() * LAIR_R
	return Vector3(q.x, p.y, q.z)


## The hero is out of its lair: it stays in the arena on his side, facing the way he went, and growls now and then.
func _guard(delta: float) -> void:
	_intent = &""
	_cool = maxf(_cool, 0.8)
	var c := arena_center()
	var toward := Combat.flat(_hero.global_position - c).normalized()
	var goal := _floor(c + toward * (float(_cave.get("arena_radius", 13.5)) - 3.5))
	face_towards(_hero.global_position, delta, TURN * 0.6)
	var g := Combat.flat(goal - global_position)
	_walk(steer_to(goal, TROT * 0.8, 1.5) if g.length() > 1.0 else Vector3.ZERO, delta)
	_growl_t -= delta
	if _growl_t <= 0.0:
		_growl_t = randf_range(3.0, 5.0)
		Sfx.play("lion_growl", lock_point(), -2.0, randf_range(0.85, 1.0))


func _mouth_b_open() -> bool:
	if encounter != null and encounter.has_method("mouth_b_open"):
		return bool(encounter.call("mouth_b_open"))
	return false


var _ex_both: Array[RID] = []
var _ex_hero: Node = null


## The lion and the hero (rays that look for stone between them), built once per hero.
func _exclude_both() -> Array[RID]:
	if _ex_both.is_empty() or _ex_hero != _hero:
		_ex_both = [get_rid()]
		_ex_hero = _hero
		if _hero != null and is_instance_valid(_hero):
			_ex_both.append(_hero.get_rid())
	return _ex_both


## No pillar, rock or boulder between it and `to` (three rays across its width at chest height).
func _lane_clear(to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var a := global_position + Vector3(0, 0.9, 0)
	var b := Vector3(to.x, a.y, to.z)
	var d := Combat.flat(b - a)
	if d.length() < 0.5:
		return true
	var side := Vector3(-d.z, 0.0, d.x).normalized() * 0.5
	_ray.exclude = _exclude_both()
	for k in 3:
		var o := side * float(k - 1)
		_ray.from = a + o
		_ray.to = b + o - d.normalized() * 0.6
		if not space.intersect_ray(_ray).is_empty():
			return false
	return true


# --- swipe and bite ---------------------------------------------------------------------------------------------------

func _start_swipe(spd: float) -> void:
	spd = minf(spd, SWIPE_SPEED_MAX)
	_set_state(S.SWIPE)
	swipes += 1
	_hit_done = false
	_r.play("swipe")
	_r.action_speed = spd
	# the paw lands at the swipe's impact key (0.52 of 1.15 s): the telegraph ends there
	var wind := 0.598 / spd
	telegraph(wind, global_position + forward() * 1.5 + Vector3(0.35, 1.5, 0), "lion_growl", 1.0)
	_cool = randf_range(_ph()["cool"].x, _ph()["cool"].y)


func _start_bite() -> void:
	_set_state(S.BITE)
	bites += 1
	_hit_done = false
	_r.play("bite")
	telegraph(0.55, global_position + forward() * 1.9 + Vector3(0, 1.1, 0), "lion_growl", 1.0)
	_cool = randf_range(_ph()["cool"].x, _ph()["cool"].y)


func _st_strike(delta: float) -> void:
	var wind_left := telegraph_t
	if _hero_ok() and wind_left > 0.18:
		# it tracks him through most of the wind-up, then commits
		face_towards(_hero.global_position, delta, TURN * 1.2)
	var lunge := Vector3.ZERO
	if state == S.BITE and _r.action == "bite" and _r.ap() > 0.38 and _r.ap() < 0.58:
		lunge = forward() * 3.5
	elif state == S.SWIPE and _r.action == "swipe" and _r.ap() > 0.4 and _r.ap() < 0.55:
		lunge = forward() * 1.6
	_walk(lunge, delta)
	if _r.action != "swipe" and _r.action != "bite":
		if _chain_left > 0 and _hero_ok():
			_chain_left -= 1
			var d := _to_hero().length()
			if d < MELEE_RANGE + 0.5:
				_start_swipe(float(_ph()["swipe"]) * 1.25)
				_chain_left = 0
				_after_chain = true
				return
		if _after_chain:
			_after_chain = false
			_start_backhop()
			return
		if _escape_strike:
			_escape_strike = false
			_set_state(S.ESCAPE)
			return
		_set_state(S.PROWL)


var _after_chain := false
## The current pounce is a short spring (SHORT_POUNCE).
var _short := false


## The rig's keys (frame time) only flag the blow; it lands on the next physics tick (hits, hit-stops and the
## hero's reactions all happen in the physics step, the same at any frame rate).
func _on_rig_event(ev: String) -> void:
	match ev:
		"impact":
			if (state == S.SWIPE or state == S.BITE) and not _hit_done:
				_ev_impact = true
		"roar_wave":
			if state == S.ROAR:
				_ev_wave = true


var _ev_impact := false
var _ev_wave := false


func _rig_events() -> void:
	if _ev_impact:
		_ev_impact = false
		if state == S.SWIPE and not _hit_done:
			_hit_done = true
			_swipe_hit()
		elif state == S.BITE and not _hit_done:
			_hit_done = true
			_bite_hit()
	if _ev_wave:
		_ev_wave = false
		if state == S.ROAR and not _hit_done:
			_roar_wave()


func _swipe_hit() -> void:
	var f := forward()
	var origin := global_position + f * 1.0
	var h := Combat.make_hit(SWIPE_HIT[0], SWIPE_HIT[1], Vector3.ZERO, SWIPE_HIT[2], SWIPE_HIT[3], self,
		{"attack": &"swipe", "point": origin + f * 1.2 + Vector3(0, 1.1, 0)})
	Sfx.play("lion_swipe", origin + Vector3(0, 1.2, 0), -1.0, randf_range(0.95, 1.05))
	var n := attack_check(2.0, 70.0, h, origin, f)
	if n > 0:
		Game.shake(0.3)
	if Game.fx:
		Game.fx.call("dust", origin + f * 1.4, 3, 0.5)


func _bite_hit() -> void:
	var f := forward()
	var origin := global_position + f * 1.7
	var h := Combat.make_hit(BITE_HIT[0], BITE_HIT[1], Vector3.ZERO, BITE_HIT[2], BITE_HIT[3], self,
		{"attack": &"bite", "point": origin + Vector3(0, 1.1, 0)})
	Sfx.play("lion_bite", origin + Vector3(0, 1.1, 0), -1.0, randf_range(0.95, 1.05))
	if attack_check(1.25, 40.0, h, origin, f) > 0:
		Game.shake(0.3)


## After a swipe-swipe chain (enraged): a bound back to make room, then the pounce.
func _start_backhop() -> void:
	if not _hero_ok():
		_set_state(S.PROWL)
		return
	var away := -_to_hero().normalized()
	_kb = away * 9.0
	Sfx.play("lion_growl", lock_point(), -4.0, 1.1)
	_start_pounce(float(_ph()["pounce_wind"]), false)


# --- the pounce ------------------------------------------------------------------------------------------------------

## The crouch: tail lashing, eyes flaring, a growl; it tracks him until just before it leaves the ground.
func _start_pounce(wind: float, from_perch: bool, short: bool = false) -> void:
	_set_state(S.POUNCE)
	pounces += 1
	_pp = P.WIND
	_windup = wind
	_short = short
	_hit_done = false
	_fl_attack = true
	_fl_kind = &"perch_down" if from_perch else &"pounce"
	last_pounce = &"pending"
	_r.play("pounce")
	_r.action_speed = RigLion.POUNCE_LEAP / wind
	_r.set_alert(0.0)
	telegraph(wind, global_position + forward() * 1.7 + Vector3(0, 1.45, 0), "lion_growl", 1.4)
	Sfx.play("lion_growl", lock_point(), 0.0, 0.85)
	_cool = randf_range(_ph()["cool"].x, _ph()["cool"].y)


func _st_pounce(delta: float) -> void:
	match _pp:
		P.WIND:
			if _hero_ok() and telegraph_t > 0.15:
				face_towards(_hero.global_position, delta, TURN * (0.8 if _fl_kind == &"perch_down" else 1.2))
				_look_at_hero()
			_walk(Vector3.ZERO, delta) # (the back-hop's shove rides on _kb)
			if state_t >= _windup:
				_launch()
		P.AIR:
			_fly(delta)
		P.SKID:
			_skid(delta)
		P.REC:
			_walk(Vector3.ZERO, delta)
			if state_t > 0.55 or _r.action != "pounce":
				_set_state(S.PROWL)


## Leaves the ground towards where the hero stands now (committed: no more tracking).
func _launch() -> void:
	var target := global_position + forward() * 8.0
	if _hero_ok():
		target = _hero.global_position
	var d := Combat.flat(target - global_position)
	var dist := clampf(d.length(), 3.0 if _short else 4.0, 15.0)
	var dir := d.normalized() if d.length() > 0.1 else forward()
	_begin_flight(dir, dist, SHORT_LEAP if _short else float(_ph()["leap"]), _floor(global_position + dir * dist).y, true)
	Sfx.play("lion_swipe", global_position + Vector3(0, 1.0, 0), -3.0, 0.7)


## The flight (a pounce, a bound up onto a rock or down from it): `dist` m along `dir` at `vh` m/s to land at
## height `land_y`. Floor to floor the body stays on the ground (the rig lifts it along the arc); otherwise it flies
## a real ballistic arc. The rig's flight pose is stretched over the flight.
func _begin_flight(dir: Vector3, dist: float, vh: float, land_y: float, attack: bool) -> void:
	_pp = P.AIR
	_fl_dir = dir
	_fl_attack = attack
	_fl_vh = vh
	_fl_t = 0.0
	_fl_T = maxf(dist / vh, 0.3)
	_fl_from_y = global_position.y
	_fl_land_y = land_y
	var dy := land_y - global_position.y
	# (off a rock it is always a real arc: the body leaves the top)
	_fl_phys = absf(dy) > 0.6 or _on_high_ground()
	if _fl_phys:
		_fl_vy = (dy + 0.5 * GRAVITY * _fl_T * _fl_T) / _fl_T
	else:
		_fl_vy = 0.0
	facing = atan2(-dir.x, -dir.z)
	state_t = 0.0
	if _r:
		_r.action_speed = (RigLion.POUNCE_LAND - RigLion.POUNCE_LEAP) / _fl_T
		_r.clear_look()


func _fly(delta: float) -> void:
	_fl_t += delta
	velocity.x = _fl_dir.x * _fl_vh
	velocity.z = _fl_dir.z * _fl_vh
	if _fl_phys:
		_fl_vy -= GRAVITY * delta
		velocity.y = _fl_vy
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
	move_and_slide()
	if _fl_attack:
		_pounce_contact()
	if _check_slam(_fl_vh, _fl_dir):
		return
	var landed := false
	if _fl_phys:
		# down on what it aimed for (not on the rock it is bounding off, not on a ledge on the way up)
		landed = _fl_vy < 0.0 and is_on_floor() and global_position.y < _fl_land_y + 0.45 and global_position.y > _fl_land_y - 0.6
		if _fl_t > _fl_T + 1.2 and is_on_floor():
			landed = true
		# (resting on something steep it cannot stand on: it comes down anyway)
		if _fl_t > _fl_T + 2.5:
			landed = true
	else:
		landed = _fl_t >= _fl_T
	if landed:
		_land()


## A pounce meets the hero (once): the blow resolves against his roll, guard and parry.
func _pounce_contact() -> void:
	if _hit_done or not _hero_ok():
		return
	var chest := global_position + _fl_dir * 1.3
	var hp3 := _hero.global_position
	var dxz := Combat.flat(hp3 - chest).length()
	if dxz > POUNCE_REACH or absf(hp3.y - global_position.y) > 2.2:
		return
	_hit_done = true
	# (not parryable: a lion in the air is no club; a raised shield takes it, at a heavy cost in stamina)
	var h := Combat.make_hit(POUNCE_HIT[0], POUNCE_HIT[1], _fl_dir, POUNCE_HIT[2], POUNCE_HIT[3], self,
		{"attack": &"pounce", "parryable": false, "point": hp3 + Vector3(0, 1.2, 0)})
	var hurt := _hero.take_hit(h)
	if hurt:
		last_pounce = &"hit"
		_fl_vh *= 0.3
		Game.shake(0.5)
		Sfx.play("lion_bite", hp3 + Vector3(0, 1.2, 0), -2.0, 0.9)
	elif bool(h.get("dodged", false)):
		last_pounce = &"dodged"
	elif bool(h.get("blocked", false)):
		last_pounce = &"blocked"
		_fl_vh *= 0.4
	else:
		last_pounce = &"missed"


## A collision with the world or the boulder that takes it square on, while still fast: the slam (stunned).
func _check_slam(speed: float, dir: Vector3) -> bool:
	if speed < SLAM_MIN:
		return false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if not (col is CollisionObject3D) or ((col as CollisionObject3D).collision_layer & (1 | 8)) == 0:
			continue
		var n := c.get_normal()
		var nf := Vector3(n.x, 0.0, n.z)
		if n.y < 0.6 and nf.length() > 0.1 and nf.normalized().dot(-dir) > 0.45:
			if not _fl_attack and state == S.LEAP:
				# a bound that bumps into something (not an attack): it drops and goes on
				_fl_vh = 0.0
				return false
			slam_normal = nf.normalized()
			if last_pounce == &"pending":
				last_pounce = &"slammed"
			_r.stop()
			_slam(col, speed, &"pounce")
			return true
	return false


func _land() -> void:
	velocity.y = 0.0
	if _r:
		_r.action_speed = 1.0
	if Game.fx:
		Game.fx.call("dust", global_position + _fl_dir * 1.2, 6, 0.8)
	Sfx.play("lion_land", global_position, -1.0, randf_range(0.95, 1.05))
	Game.shake(0.18)
	if state == S.LEAP:
		_leap_landed()
		return
	if last_pounce == &"pending":
		last_pounce = &"missed"
	_pp = P.SKID
	_skid_v = _fl_vh
	state_t = 0.0


func _skid(delta: float) -> void:
	_skid_v = maxf(0.0, _skid_v - SKID_DECEL * delta)
	_walk(_fl_dir * _skid_v, delta)
	if _fl_attack:
		_pounce_contact()
	if _check_slam(_skid_v, _fl_dir):
		return
	if _skid_v <= 0.0:
		_pp = P.REC
		state_t = 0.0


# --- the roar --------------------------------------------------------------------------------------------------------

## The inhale (head down, chest swelling; a big glint and a growl), then the roar and its shockwave. `inhale` s.
func _start_roar(inhale: float, phase_roar: bool = false) -> void:
	_set_state(S.ROAR)
	last_roar_shoved = false
	roars += 1
	_hit_done = false
	_r.play("roar")
	var wave_at := 2.6 * 0.3
	_r.action_speed = wave_at / maxf(inhale, 0.3)
	telegraph(inhale, lock_point() + Vector3(0, 0.8, 0), "lion_growl", 1.6)
	_roar_cd = float(_ph()["roar_cd"])
	_phase_roar = phase_roar


var _phase_roar := false
## The intro roar only shows its strength (no shove).
var _no_shove := false


func _st_roar(delta: float) -> void:
	if _hero_ok() and not _hit_done:
		face_towards(_hero.global_position, delta, TURN * 0.6)
		_look_at_hero(0.6)
	_walk(Vector3.ZERO, delta)
	if _hit_done and _r.action_speed < 1.0:
		_r.action_speed = 1.0
	if _r.action != "roar" or state_t > 4.0:
		_set_state(S.PROWL)
		# (from the second phase) the roar threw him back off balance: it springs after him
		if phase >= 1 and last_roar_shoved and _hero_ok():
			var d := _to_hero().length()
			if d >= POUNCE_MIN and d <= POUNCE_MAX:
				_intent = &"pounce"
				_intent_t = 0.0
				_cool = 0.0


func _roar_wave() -> void:
	_hit_done = true
	Sfx.play("lion_roar", lock_point(), 2.0)
	Game.shake(0.65)
	if Game.fx:
		Game.fx.call("ring", global_position + Vector3(0, 0.3, 0), ROAR_RANGE, Color(1.0, 0.85, 0.6, 0.85), 0.55)
		Game.fx.call("ring", global_position + Vector3(0, 1.2, 0), ROAR_RANGE * 0.7, Color(1.0, 0.92, 0.75, 0.6), 0.4)
		Game.fx.call("dust", global_position, 14, 2.4)
	if not _hero_ok() or _no_shove:
		_no_shove = false
		return
	var to := _to_hero()
	var d := to.length()
	if d > ROAR_RANGE:
		return
	var k := 1.0 - 0.5 * d / ROAR_RANGE
	var h := Combat.make_hit(0.0, &"blunt", to.normalized() if d > 0.1 else forward(), ROAR_PUSH * k, 0.5, self,
		{"attack": &"roar", "unblockable": true, "parryable": false})
	_hero.take_hit(h)
	last_roar_shoved = bool(h.get("shoved", false))


var last_roar_shoved := false


# --- perches: the rocks by the walls (phase 2 on) ------------------------------------------------------------------------

var _perch_launch := Vector3.ZERO


## Runs to the foot of a rock perch (one not too near the hero) and bounds up onto it. False when none suits.
func _start_perch_run() -> bool:
	if _outcrops.is_empty() or not _hero_ok():
		return false
	var best := -1
	var best_s := INF
	for i in _outcrops.size():
		if i == _perch and _on_high_ground():
			continue
		var o: Dictionary = _outcrops[i]
		var c: Vector3 = o["center"]
		var hd := Combat.flat(_hero.global_position - c).length()
		if hd < 4.5:
			continue
		var s := Combat.flat(c - global_position).length() + randf() * 4.0
		if s < best_s:
			best_s = s
			best = i
	if best < 0:
		return false
	_perch = best
	var o2: Dictionary = _outcrops[best]
	_perch_launch = o2["launch"]
	_perch_cd = float(_ph()["perch_cd"])
	_set_state(S.LEAP)
	_pp = P.WIND
	_leap_mode = &"run"
	_leap_best = INF
	_leap_stall = 0.0
	_leap_vh = 8.0
	_r.set_alert(0.2)
	return true


var _leap_mode := &"run" # &"run" (to the launch point) | &"crouch" | &"air"
var _leap_best := INF
var _leap_stall := 0.0
## Horizontal speed of the next bound (m/s): 8 from the floor onto a rock, faster from rock to rock.
var _leap_vh := 8.0


func _st_leap(delta: float) -> void:
	match _leap_mode:
		&"run":
			var o: Dictionary = _outcrops[_perch]
			var spot: Vector3 = o["spot"]
			var to := Combat.flat(_perch_launch - global_position)
			var to_spot := Combat.flat(spot - global_position).length()
			# at the launch point, or near enough with a clear bound up: crouch and spring
			var ready := to.length() < 0.7 or (state_t > 0.3 and to_spot > 4.0 and to_spot < 8.0 and _arc_clear(global_position, spot))
			# no progress (a pillar or the hero in the way): spring from here if it can, else give up the rock
			if to.length() < _leap_best - 0.3:
				_leap_best = to.length()
				_leap_stall = 0.0
			else:
				_leap_stall += delta
			if not ready and (_leap_stall > 1.0 or state_t > 5.0):
				if to_spot > 3.5 and to_spot < 9.5 and _arc_clear(global_position, spot):
					ready = true
				else:
					_perch_cd = 3.0
					_cool = 0.4
					_set_state(S.PROWL)
					return
			if ready:
				_leap_mode = &"crouch"
				_leap_vh = 8.0
				state_t = 0.0
				_r.play("pounce")
				_r.action_speed = RigLion.POUNCE_LEAP / 0.38
				return
			face_towards(_perch_launch, delta, TURN)
			_walk(steer_to(_perch_launch, RUN * 0.9 * float(_ph()["move"]), 1.5), delta)
		&"crouch":
			var o: Dictionary = _outcrops[_perch]
			var land: Vector3 = o["spot"]
			face_towards(land, delta, TURN * 2.0)
			_walk(Vector3.ZERO, delta)
			if state_t >= 0.38:
				var top: float = o["top"]
				var d := Combat.flat(land - global_position)
				_leap_mode = &"air"
				_begin_flight(d.normalized(), d.length(), maxf(_leap_vh, d.length() / 1.25), top, false)
				_fl_kind = &"perch_up"
				Sfx.play("lion_growl", lock_point(), -6.0, 1.2)
		&"air":
			_fly(delta)


## A bound from `from` to the top at `spot` is clear: no pillar or wall across its line at the body's height and at
## the top of its arc.
func _arc_clear(from: Vector3, spot: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	_ray.exclude = _exclude_both()
	for h in [1.0, 2.4]:
		_ray.from = from + Vector3(0, h, 0)
		_ray.to = spot + Vector3(0, h, 0)
		if not space.intersect_ray(_ray).is_empty():
			return false
	return true


func _leap_landed() -> void:
	if _fl_kind == &"intro_down":
		_set_state(S.INTRO)
		state_t = 2.0
		return
	if _fl_kind == &"perch_up":
		var o: Dictionary = _outcrops[_perch]
		if global_position.y > float(o["top"]) - 0.5:
			perches += 1
			_set_state(S.PERCHED)
			_perch_wait = randf_range(0.5, 0.9)
			# from rock to rock across the arena (phase 2 on, now and then), else the pounce from above
			_perch_plan = &"hop" if (_perch_hops < 2 and _outcrops.size() > 1 and randf() < (0.45 if _perch_hops == 0 else 0.25)) else &"pounce"
			_r.set_alert(1.0)
			Sfx.play("lion_growl", lock_point(), -1.0, 0.95)
			return
	if _fl_kind == &"perch_relocate" and _start_perch_run():
		return
	# a bound down (or a bound that fell short): back to the hunt
	_perch_hops = 0
	_set_state(S.PROWL)
	_cool = 0.6


var _perch_wait := 0.6
var _perch_plan := &"pounce"


func _st_perched(delta: float) -> void:
	_walk(Vector3.ZERO, delta)
	if not _hero_ok():
		return
	face_towards(_hero.global_position, delta, 2.5)
	_look_at_hero()
	if state_t < _perch_wait:
		return
	var d := _to_hero().length()
	if _perch_plan == &"hop":
		_perch_hops += 1
		_perch_plan = &"pounce"
		var nxt := _next_perch()
		if nxt >= 0:
			# straight across to the next rock: a long bound over the arena
			_perch = nxt
			_set_state(S.LEAP)
			_leap_mode = &"crouch"
			_leap_vh = 9.0
			_r.play("pounce")
			_r.action_speed = RigLion.POUNCE_LEAP / 0.38
			Sfx.play("lion_growl", lock_point(), -3.0, 1.1)
			return
		_jump_down(true)
		return
	_perch_hops = 0
	if d < 2.0 or d > 16.0 or not _lane_clear(_hero.global_position):
		if state_t > 2.5:
			_jump_down(false)
		return
	_start_pounce(float(_ph()["pounce_wind"]) * 1.05, true)


## Another rock it can bound to straight from this one (a clear arc, 6-16 m away, not next to the hero), or -1.
func _next_perch() -> int:
	var best := -1
	var best_s := INF
	for i in _outcrops.size():
		if i == _perch:
			continue
		var o: Dictionary = _outcrops[i]
		var spot: Vector3 = o["spot"]
		var dd := Combat.flat(spot - global_position).length()
		if dd < 6.0 or dd > 16.0:
			continue
		if _hero_ok() and Combat.flat(_hero.global_position - spot).length() < 4.0:
			continue
		if not _arc_clear(global_position, spot):
			continue
		var sc := dd + randf() * 3.0
		if sc < best_s:
			best_s = sc
			best = i
	return best


## Bounds down off the rock (towards the arena, or on to the next rock when `relocate`).
func _jump_down(relocate: bool) -> void:
	var o: Dictionary = _outcrops[_perch]
	var c: Vector3 = o["center"]
	var inward := Combat.flat(arena_center() - c).normalized()
	var land := _floor(c + inward * (float(o["r"]) + 3.2))
	var d := Combat.flat(land - global_position)
	_set_state(S.LEAP)
	_leap_mode = &"air"
	# a quick hop: the rig starts at the end of its crouch
	_r.play("pounce")
	_r.action_t = RigLion.POUNCE_LEAP - 0.12
	_begin_flight(d.normalized(), d.length(), 8.5, land.y, false)
	_fl_kind = &"perch_relocate" if relocate else &"perch_down"


# --- falls, stun, recovery, downed ------------------------------------------------------------------------------

func _st_fall(delta: float) -> void:
	if not is_on_floor() and state_t < 3.0:
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
		move_and_slide()
		return
	var fell := _fall_from - global_position.y
	if fell >= FALL_STUN:
		fall_stuns += 1
		slams += 1
		slam_normal = Vector3.ZERO
		Game.shake(0.45)
		Sfx.play("lion_thud", global_position, 0.0, 0.85)
		if Game.fx:
			Game.fx.call("dust", global_position, 14, 1.6)
		slammed.emit(&"fall")
		_stun(float(_ph()["stun"]) * 0.8)
	else:
		_set_state(S.PROWL)


func _st_stunned(delta: float) -> void:
	_walk(Vector3.ZERO, delta)
	if stun <= 0.0 and not grappled:
		_set_state(S.RECOVER)
		if _r:
			_r.stop()
			_r.play("hit")
		Sfx.play("lion_growl", lock_point(), -2.0, 1.0)


func _st_recover(delta: float) -> void:
	_walk(Vector3.ZERO, delta)
	if state_t > 0.6:
		_set_state(S.PROWL)
		_cool = minf(_cool, 0.7)
		if _hero_ok() and _to_hero().length() < MELEE_RANGE + 1.0:
			_intent = &"melee"


func _st_grappled(delta: float) -> void:
	_walk(Vector3.ZERO, delta)
	if not grappled or not _hero_ok():
		return
	_wrestle_t += delta
	_beat_t -= delta
	_thrash_t -= delta
	var ph := _ph()
	if _beat_t <= 0.0:
		_beat_t = float(ph["beat"])
		_hero.grapple_cue(float(ph["window"]))
		Sfx.play("wrestle_strain", _neck_pos(), -6.0, randf_range(1.0, 1.12))
	if not _warned and _thrash_t <= THRASH_WARN:
		_warned = true
		telegraph(THRASH_WARN, _neck_pos() + Vector3(0, 0.6, 0), "lion_growl", 1.2)
	if _thrash_t <= 0.0:
		_thrash_t = float(ph["thrash"])
		_warned = false
		_r.play("thrash")
		_thrashing = 1.3
		Sfx.play("lion_thrash", global_position, -2.0, randf_range(0.95, 1.05))
		_hero.grapple_thrash(float(ph["thrash_cost"]))
		if not grappled:
			return
	if _thrashing > 0.0:
		_thrashing -= delta
		if _thrashing <= 0.0 and grappled:
			_r.play("grappled")
	if _wrestle_t >= WRESTLE_MAX:
		_hero.grapple_release(false)


func _st_downed(delta: float) -> void:
	_walk(Vector3.ZERO, delta)
	_down_t -= delta
	if _down_t <= 0.0:
		_set_state(S.PROWL)
		_cool = 0.4
		Sfx.play("lion_growl", lock_point(), -1.0, 0.9)


# --- the escape through mouth B and the ambush through mouth A --------------------------------------------------------

## An escape that takes longer than this (s: the boulder half in the crack, the hero standing in it) is given up.
const ESCAPE_MAX := 14.0
## Seconds it stays out on the ridge (hidden) before it can come back in.
const AWAY_MIN := 4.0
## After this long away it comes back in whatever the hero does (and guards the arena if he is not in it).
const AWAY_MAX := 30.0

var _escape_t := 0.0
## A swipe at a hero in its way out: back to the escape afterwards.
var _escape_strike := false


func _start_escape() -> void:
	if _cave.is_empty():
		return
	escaped = true
	_escape_t = 0.0
	_escape_strike = false
	_set_state(S.ESCAPE)
	_route.clear()
	var c := arena_center()
	var dir_b: Vector3 = Combat.flat(_cave.get("dir_b", Vector3.RIGHT)).normalized()
	var inner_b: Vector3 = _cave.get("inner_b", c + dir_b * 14.0)
	var ent_b: Vector3 = _cave.get("entrance_b", inner_b + dir_b * 3.0)
	var side := Vector3(-dir_b.z, 0.0, dir_b.x)
	_route.append(_floor(c + Combat.flat(inner_b - c).normalized() * (float(_cave.get("arena_radius", 13.5)) - 1.0)))
	_route.append(_floor(inner_b))
	_route.append(_floor(ent_b))
	var out1 := ent_b + dir_b * 3.0
	# round the boulder when it waits on the apron in front of the crack
	var bo: Node3D = _cave.get("boulder")
	var lat := 0.0
	if bo != null and is_instance_valid(bo):
		var rel := Combat.flat(bo.global_position - ent_b)
		if rel.dot(dir_b) > 0.0 and absf(rel.dot(side)) < 3.5:
			lat = -4.0 if rel.dot(side) >= 0.0 else 4.0
	_route.append(_floor(out1 + side * lat * 0.6))
	_route.append(_floor(ent_b + dir_b * 10.0 + side * lat))
	_route_i = 0
	_blocked_t = 0.0
	_esc_best = INF
	_esc_stuck = 0
	Sfx.play("lion_growl", lock_point(), 0.0, 1.2)
	if _r:
		_r.clear_look()
		_r.set_alert(0.0)
	if encounter != null and encounter.has_method("lion_escaping"):
		encounter.call("lion_escaping")


func _st_escape(delta: float) -> void:
	_escape_t += delta
	if _escape_t > ESCAPE_MAX:
		# it could not get out: it turns on him instead (no second try this fight)
		_escape_done = true
		_route.clear()
		_cool = 0.3
		_set_state(S.PROWL)
		return
	if _route_i >= _route.size():
		_go_away()
		return
	var goal := _route[_route_i]
	var to := Combat.flat(goal - global_position)
	if to.length() < 1.2:
		_route_i += 1
		_blocked_t = 0.0
		_esc_best = INF
		return
	# a column (or the hero) in the way: no headway towards the next point for a moment (its whiskers can hold it
	# still against a column, jittering on the spot)
	if to.length() < _esc_best - 0.25:
		_esc_best = to.length()
		_blocked_t = 0.0
	else:
		_blocked_t += delta
	if _detour_t > 0.0:
		_detour_t -= delta
		face_towards(global_position + _detour, delta, TURN * 1.3)
		_walk(steer_to(global_position + _detour * 3.0, RUN * 0.7 * float(_ph()["move"]), 0.5), delta)
		return
	if _blocked_t > 0.6:
		_blocked_t = 0.0
		_esc_best = INF
		# the hero in its way: a swipe at him, then on
		if _hero_ok() and _to_hero().length() < MELEE_RANGE and _hero.is_alive():
			_escape_strike = true
			_start_swipe(1.0)
			return
		# else round the stone (a step aside), then on; still stuck after that: the next point
		_esc_stuck += 1
		if _esc_stuck > 2:
			_esc_stuck = 0
			_route_i += 1
			return
		_start_detour(to)
		_detour_t = 0.8
		return
	face_towards(goal, delta, TURN * 1.3)
	_walk(steer_to(goal, RUN * float(_ph()["move"]), 0.5), delta)
	# out past the opening and out of his sight (or far from him): gone
	if _route_i >= 3 and (not _hero_ok() or _to_hero().length() > 22.0 or _hidden_from_view()):
		_go_away()


## Nothing of it can be seen: off the camera's view, or the rock between the lens and its body.
func _hidden_from_view() -> bool:
	var cam = Game.camera
	if cam == null or not is_instance_valid(cam) or not ("cam" in cam) or cam.cam == null:
		return true
	var c3: Camera3D = cam.cam
	var chest := global_position + Vector3(0, 1.0, 0)
	if not c3.is_position_in_frustum(chest) and not c3.is_position_in_frustum(chest + forward() * 1.6) \
			and not c3.is_position_in_frustum(chest - forward() * 1.4):
		return true
	var space := get_world_3d().direct_space_state
	_ray.exclude = _exclude_both()
	for p in [chest, chest + forward() * 1.4, chest - forward() * 1.2]:
		_ray.from = c3.global_position
		_ray.to = p
		if space.intersect_ray(_ray).is_empty():
			return false
	return true


func _go_away() -> void:
	_set_state(S.AWAY)
	_away_t = 0.0
	_show(false)
	hp = minf(max_hp * float(PHASE_AT[0]), hp + max_hp * ESCAPE_HEAL)
	_route.clear()
	# out of the way on the ridge beyond mouth B (no body, no lock, no chain while it is away)
	var dir_b: Vector3 = Combat.flat(_cave.get("dir_b", Vector3.RIGHT)).normalized()
	var ent_b: Vector3 = _cave.get("entrance_b", global_position)
	teleport(_floor(ent_b + dir_b * 12.0), facing)


## Hidden or shown again (out on the ridge between the escape and the ambush): no body, no lock, no chain.
func _show(on: bool) -> void:
	if _r:
		_r.visible = on
	if on:
		collision_layer = 4
		collision_mask = 1 | 2 | 4 | 8
		for g in ["lockable", "chain_anchor", "damageable"]:
			if not is_in_group(g):
				add_to_group(g)
	else:
		collision_layer = 0
		collision_mask = 0
		for g in ["lockable", "chain_anchor", "damageable"]:
			if is_in_group(g):
				remove_from_group(g)


func _st_away(delta: float) -> void:
	_away_t += delta
	velocity = Vector3.ZERO
	if _away_t < AWAY_MIN or not _hero_ok():
		return
	# back in when he is in the arena (it comes in behind him, through mouth A; through B if he waits by A)
	var c := arena_center()
	if not _in_lair(_hero.global_position, float(_cave.get("arena_radius", 13.5)) + 1.0) and _away_t < AWAY_MAX:
		return
	var key := "a"
	var inner_a: Vector3 = _cave.get("inner_a", c)
	if Combat.flat(_hero.global_position - inner_a).length() < 12.0:
		key = "b"
	var dir: Vector3 = Combat.flat(_cave.get("dir_" + key, Vector3.LEFT)).normalized()
	var ent: Vector3 = _cave.get("entrance_" + key, c + dir * 20.0)
	var inner: Vector3 = _cave.get("inner_" + key, c + dir * 14.0)
	# just inside the mouth, out of sight down the tunnel
	var start := _floor(ent.lerp(inner, 0.25))
	teleport(start + Vector3(0, 0.05, 0), atan2(dir.x, dir.z))
	rotation.y = facing
	_show(true)
	_route.clear()
	_route.append(_floor(inner))
	_route_i = 0
	_set_state(S.AMBUSH)
	_ambush_growl = false
	ambushes += 1


func _st_ambush(delta: float) -> void:
	if not _hero_ok():
		_set_state(S.PROWL)
		return
	var to := _to_hero()
	var d := to.length()
	if not _ambush_growl and d < 18.0:
		_ambush_growl = true
		# a growl from the tunnel behind him: the only warning before the crouch
		Sfx.play("lion_growl", lock_point(), 4.0, 0.8)
	if d <= 12.0 and d >= POUNCE_MIN and _lane_clear(_hero.global_position):
		_start_pounce(1.05, false)
		return
	if d < POUNCE_MIN or state_t > 9.0:
		_set_state(S.PROWL)
		return
	# down the tunnel at a run, then straight at him
	var goal := _hero.global_position
	if _route_i < _route.size():
		goal = _route[_route_i]
		if Combat.flat(goal - global_position).length() < 1.5:
			_route_i += 1
	face_towards(goal, delta, TURN)
	_walk(steer_to(goal, RUN * 0.85, 1.0), delta)
