class_name Enemy
extends CharacterBody3D
## Base class for everything the hero fights (wolves, boars, the lion, the training dummies). Implements the
## combat contracts of docs/ARCHITECTURE.md and docs/COMBAT.md so subclasses only add a body, a rig and a brain:
##   damageable  group "damageable", take_hit(hit) -> bool, is_alive() -> bool, team (1)
##   lockable    group "lockable", lock_point() -> Vector3
##   chain       group "chain_anchor", chain_point(), chain_kind() (chain_weight), on_chain_attach / pull / release:
##               &"light"  yanked through the air to land staggered in front of the hero (a combo set-up)
##               &"heavy"  stays put: the hero is pulled to it
##               &"beast"  slides chain_slide m along the pull; slamming into the world or a boulder on the way
##                         stuns it for stun_on_slam s (_on_slam hook): the Nemean Lion's pillar trick
## hit = {amount, kind, dir, knockback, stagger, source} (+ optional keys: Combat header / COMBAT.md)
##
## Helpers for subclasses (ENCOUNTERS):
##   telegraph(seconds, cue_point, sound)   a readable wind-up: a glint at the cue point, a flash, a sound;
##                                          telegraph_left() counts down, _on_telegraph_done() fires at the end
##   attack_check(reach, half_angle, hit)   strikes every foe in a cone in front: returns how many it hurt and
##                                          copies the target's verdict (parried / blocked / dodged) into `hit`
##   on_parried(hero)                       the hero parried our blow: thrown open (stagger parry_stagger s)
##   stun_for(seconds), is_stunned()        dazed (stars over the head): no thinking, no attacks
##   steer_to(goal, speed, arrive)          seek + keep apart from other enemies + step round obstacles
##   face_towards(p, delta, rate), forward(), hurt_volumes()
## Physics: enemies layer 3, colliding with the world, the hero, other enemies and movable props. The visual
## (`rig`, any Node3D, usually a Rig) is top-level and drawn interpolated between physics ticks.
##
## Subclass hooks (override what you need):
##   _build()                  add the rig (set `rig`) and, if the default capsule does not fit, the collision
##   _think(delta) -> Vector3  desired horizontal velocity this tick (AI); not called while staggered, stunned,
##                             yanked or sliding, or dead
##   _modify_damage(hit, amount) -> float   e.g. the lion: 0 for blades, and set hit["deflected"] = true
##   _on_hurt(hit), _on_blocked(hit), _on_death(hit)
##   _on_telegraph_done(), _on_parried(hero), _on_stunned(seconds), _on_slam(collider, speed), _on_yank_landed()
##   corpse_time               seconds the body stays after death (0 = remove at once, < 0 = keep)

signal hurt(hit: Dictionary)
signal died(enemy: Enemy)

const GRAVITY := 24.0
const KNOCKBACK_DECAY := 18.0
const CHAIN_PULL_SPEED := 9.0
## Deceleration of a beast sliding on the chain (m/s^2).
const SLIDE_DECEL := 16.0
## Speed (m/s) a sliding beast must still have to be stunned by what it hits.
const SLAM_SPEED := 2.5

var team := 1
var display_name := "Enemigo"
var max_hp := 30.0
var hp := 30.0
var alive := true
## Capsule size used by the default collision and hurt volume (m).
var radius := 0.45
var height := 1.2
## lock_point() height above the origin (m).
var lock_height := 0.9
## chain_kind(): &"light" (pulled to the hero), &"heavy" (the hero is pulled to it), &"beast" (dragged, slams).
var chain_weight: StringName = &"light"
## 0 = full knockback, 1 = immovable.
var knockback_resist := 0.0
var corpse_time := 4.0
## Seconds left of stagger (no thinking, no attacks).
var stagger := 0.0
## Seconds left during which hits are ignored.
var invulnerable := 0.0
## Yaw the visual faces (model forward = -Z).
var facing := 0.0
var rig: Node3D = null
## Seconds left stunned (dazed: stars over the head).
var stun := 0.0
## Tuning for the chain and the parry (subclasses set them in _init).
var parry_stagger := 1.2
var yank_stagger := 1.1
var chain_slide := 3.5
var stun_on_slam := 3.0
## Seconds left of the current telegraphed wind-up (0 = none).
var telegraph_t := 0.0
## The face it last slammed into on the chain (its normal: from the pillar towards the beast; ZERO before any
## slam). A wrestle anchor should be picked on this side of the head, away from the pillar (room for the hero and
## the camera).
var slam_normal := Vector3.ZERO
## Poise: a blow staggers (and breaks a wind-up) only when its `stagger` reaches this (wolf 0.3: every blow;
## boar 0.8: only the heavy blow, or a parry; lion 99: never - the chain and the pillars do it). Below it the
## body only flashes and is pushed (knockback_resist still applies).
var poise := 0.3

var _kb := Vector3.ZERO
var _chain_pull := Vector3.ZERO
var _chain_hero: Node = null
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _vis_yaw := 0.0
var _death_t := 0.0
var _yank_t := -1.0
var _yank_dur := 0.4
var _yank_from := Vector3.ZERO
var _yank_to := Vector3.ZERO
var _yank_h := 0.6
var _yank_stuck := 0
var _slide_v := Vector3.ZERO
var _telegraph_len := 0.0
## Physics ticks at rest on the floor; past REST_TICKS the body stops sweeping its capsule until it moves again.
var _rest_ticks := 0
const REST_TICKS := 8

static var _all_enemies: Array[Node] = []
static var _all_frame := -1


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("enemy")
	add_to_group("damageable")
	add_to_group("lockable")
	add_to_group("chain_anchor")
	hp = max_hp
	_build()
	if not _has_shape():
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(height, radius * 2.0)
		cs.shape = cap
		cs.position = Vector3(0, cap.height * 0.5, 0)
		add_child(cs)
	if rig:
		rig.top_level = true
	_curr_pos = global_position
	_prev_pos = _curr_pos
	_vis_yaw = facing


func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return true
	return false


## Moves the enemy (and its visual) without interpolating the jump.
func teleport(p: Vector3, yaw: float = facing) -> void:
	global_position = p
	facing = yaw
	_vis_yaw = yaw
	_prev_pos = p
	_curr_pos = p
	velocity = Vector3.ZERO
	_kb = Vector3.ZERO
	_chain_pull = Vector3.ZERO
	_yank_t = -1.0
	_slide_v = Vector3.ZERO
	_rest_ticks = 0
	_sync_visual(1.0)


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


# --- contracts -----------------------------------------------------------------------------------------------

func take_hit(hit: Dictionary) -> bool:
	if not alive or invulnerable > 0.0:
		return false
	var amount := _modify_damage(hit, float(hit.get("amount", 0.0)))
	if amount <= 0.0:
		_on_blocked(hit)
		return false
	hp = maxf(0.0, hp - amount)
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	dir.y = 0.0
	if dir.length_squared() > 1e-6 and _yank_t < 0.0:
		_kb = dir.normalized() * float(hit.get("knockback", 0.0)) * (1.0 - knockback_resist)
	var st := float(hit.get("stagger", 0.0))
	var staggers := st >= poise
	if staggers:
		stagger = maxf(stagger, st)
		telegraph_t = 0.0 # a real blow interrupts the wind-up
	if rig and rig.has_method("hit_flash"):
		# a strong flash, not a white silhouette: the body's reaction must still read through it
		rig.call("hit_flash", Rig.FLASH_HEAVY if st >= 0.5 else Rig.FLASH_LIGHT)
	hurt.emit(hit)
	if staggers and hp > 0.0:
		_flinch(hit)
	_on_hurt(hit)
	if hp <= 0.0:
		die(hit)
	return true


## The body's reaction to a blow that staggers it: the rig's `stagger` (stagger >= 0.6) or `hit` action when it
## has them (after set_hit_dir(dir) when the rig takes it), never while stunned, yanked or sliding. Override for
## your own reaction (call super or not).
func _flinch(hit: Dictionary) -> void:
	if rig == null or stun > 0.0 or _yank_t >= 0.0 or is_sliding() or not rig.has_method("play"):
		return
	var heavy := float(hit.get("stagger", 0.0)) >= 0.6
	var act := ""
	if heavy and _rig_action(&"stagger"):
		act = "stagger"
	elif _rig_action(&"hit"):
		act = "hit"
	if act == "":
		return
	if rig.has_method("set_hit_dir"):
		rig.call("set_hit_dir", hit.get("dir", -forward()))
	rig.call("play", act)


## Whether the rig defines action `a` (a dictionary `actions` / ACTIONS, or action_length() > 0); false for rigs
## without such a table (the training dummies wobble instead).
func _rig_action(a: StringName) -> bool:
	if rig == null:
		return false
	for key in ["actions", "ACTIONS"]:
		if key in rig:
			var acts = rig.get(key)
			if acts is Dictionary and not (acts as Dictionary).is_empty():
				return (acts as Dictionary).has(String(a))
	if rig.has_method("action_length"):
		return float(rig.call("action_length", String(a))) > 0.0
	return false


func is_alive() -> bool:
	return alive


func lock_point() -> Vector3:
	return global_position + Vector3(0, lock_height, 0)


func chain_point() -> Vector3:
	return global_position + Vector3(0, height * 0.6, 0)


func chain_kind() -> StringName:
	return chain_weight


func on_chain_attach(hero: Node) -> void:
	_chain_hero = hero
	stagger = maxf(stagger, 0.35)
	telegraph_t = 0.0


## The hero pulls (dir: towards the hero). Light enemies are yanked to land staggered in front of the hero; beasts
## slide chain_slide m along dir and are stunned if they slam into something; heavy ones stay put.
func on_chain_pull(hero: Node, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-6:
		return
	d = d.normalized()
	match chain_weight:
		&"light":
			_start_yank(hero as Node3D, d)
		&"beast":
			_slide_v = _slam_aim(d) * sqrt(2.0 * SLIDE_DECEL * chain_slide)
			stagger = maxf(stagger, 0.7)
			telegraph_t = 0.0


func on_chain_release(_hero: Node) -> void:
	_chain_hero = null


## Slam magnetism (a beast yanked on the chain): a pillar, a rock or the boulder within reach of the slide and
## up to SLAM_BEND degrees off its line draws it (the nearest angle wins), so the line need not graze the pillar
## exactly to stun the beast against it. Returns the (possibly bent) horizontal direction.
const SLAM_BEND := 25.0
var _slam_q: PhysicsRayQueryParameters3D = null


func _slam_aim(d: Vector3) -> Vector3:
	if not is_inside_tree():
		return d
	var space := get_world_3d().direct_space_state
	if _slam_q == null:
		_slam_q = PhysicsRayQueryParameters3D.new()
		_slam_q.collision_mask = 1 | 8
	var ex: Array[RID] = [get_rid()]
	if _chain_hero is CollisionObject3D:
		ex.append((_chain_hero as CollisionObject3D).get_rid())
	_slam_q.exclude = ex
	var from := global_position + Vector3(0, clampf(height * 0.5, 0.3, 0.9), 0)
	var reach := chain_slide + radius + 0.2
	for k in 11:
		# 0, +5, -5, +10, -10 ... +25, -25 degrees
		var ang := deg_to_rad(5.0 * float((k + 1) >> 1) * (1.0 if k % 2 == 1 else -1.0))
		if absf(rad_to_deg(ang)) > SLAM_BEND + 0.1:
			break
		var dir := d.rotated(Vector3.UP, ang)
		_slam_q.from = from
		_slam_q.to = from + dir * reach
		var hit := space.intersect_ray(_slam_q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		var nf := Vector3(n.x, 0.0, n.z)
		# a face that takes the beast square on (not the ground, not a wall it would only scrape along)
		if n.y < 0.6 and nf.length() > 0.1 and nf.normalized().dot(-dir) > 0.6:
			return dir
	return d


func die(hit: Dictionary = {}) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	telegraph_t = 0.0
	remove_from_group("lockable")
	remove_from_group("chain_anchor")
	remove_from_group("damageable")
	# Corpses do not block the hero.
	collision_layer = 0
	collision_mask = 1
	if rig and rig.has_method("play"):
		rig.call("play", "death")
	_on_death(hit)
	died.emit(self)


## Capsules [a, b, r] (world) the hero's blade is tested against: one vertical capsule by default.
func hurt_volumes() -> Array:
	var p := global_position
	return [[p + Vector3(0, radius, 0), p + Vector3(0, maxf(height - radius, radius), 0), radius]]


# --- helpers for subclasses ------------------------------------------------------------------------------------

## A readable wind-up of `seconds`: a gold glint at `cue_point` (default: over the lock point), a flash on the rig
## and `sound`. telegraph_left() counts down; _on_telegraph_done() fires at the end (strike there).
func telegraph(seconds: float, cue_point: Vector3 = Vector3.INF, sound: String = "", strength: float = 1.0) -> void:
	telegraph_t = maxf(seconds, 0.01)
	_telegraph_len = telegraph_t
	var p := cue_point if cue_point != Vector3.INF else lock_point() + Vector3(0, 0.35, 0)
	if Game.fx:
		Game.fx.call("glint", p, 0.9 * strength + 0.3, Color(1.0, 0.82, 0.45), minf(0.45, seconds))
	if rig and rig.has_method("hit_flash"):
		rig.call("hit_flash", 0.4)
	if sound != "":
		Sfx.play(sound, p, -3.0)


func telegraph_left() -> float:
	return telegraph_t


## Strikes every damageable of another team inside a cone of `half_angle` degrees and `reach` m (to their
## surface) in front of `origin` (default: here, facing `forward()`): calls take_hit with a copy of `hit` (dir
## and source filled in when missing). Returns how many it hurt; the target's verdict (parried, blocked, dodged,
## deflected) is copied back into `hit`.
func attack_check(reach: float, half_angle: float, hit: Dictionary, origin: Vector3 = Vector3.INF, fwd: Vector3 = Vector3.ZERO) -> int:
	var o := global_position if origin == Vector3.INF else origin
	var f := forward() if fwd == Vector3.ZERO else Combat.flat(fwd).normalized()
	var n := 0
	for t in get_tree().get_nodes_in_group("damageable"):
		var t3 := t as Node3D
		if t3 == null or t3 == self or not Combat.is_alive(t3):
			continue
		if "team" in t3 and int(t3.get("team")) == team:
			continue
		var d := Combat.flat(t3.global_position - o)
		if d.length() - Combat.body_radius(t3) > reach:
			continue
		if absf(t3.global_position.y - o.y) > 2.0:
			continue
		if d.length() > 0.35 and not Combat.in_front(o, f, t3.global_position, half_angle):
			continue
		var h := hit.duplicate()
		if not h.has("dir") or (h["dir"] as Vector3) == Vector3.ZERO:
			h["dir"] = d.normalized() if d.length() > 0.01 else f
		if not h.has("source"):
			h["source"] = self
		if bool(t3.call("take_hit", h)):
			n += 1
		for k in ["parried", "blocked", "dodged", "deflected"]:
			if h.has(k):
				hit[k] = h[k]
	return n


## The hero parried our blow (Hero calls it): thrown open for parry_stagger s.
func on_parried(hero: Node) -> void:
	telegraph_t = 0.0
	stagger = maxf(stagger, parry_stagger)
	var away := Combat.flat(global_position - (hero as Node3D).global_position)
	if away.length_squared() > 1e-4:
		_kb = away.normalized() * 3.0 * (1.0 - knockback_resist)
	if rig and rig.has_method("play"):
		rig.call("play", "stagger" if _rig_has(&"stagger") else "hit")
	_on_parried(hero)


## Dazed for `seconds`: no thinking, no attacks, little stars circling over the head.
func stun_for(seconds: float) -> void:
	if not alive:
		return
	stun = maxf(stun, seconds)
	stagger = maxf(stagger, seconds)
	telegraph_t = 0.0
	if Game.fx:
		Game.fx.call("daze", self, height + 0.35, seconds, maxf(radius * 0.8, 0.3))
	if rig and rig.has_method("play") and _rig_has(&"stunned"):
		rig.call("play", "stunned")
	_on_stunned(seconds)


func is_stunned() -> bool:
	return alive and stun > 0.0


## The UI's prompt over a stunned beast the hero can wrestle (Hero offers it as interact_target while
## can_grapple() says yes): "Agarrar" (interact). Only grapplable beasts ever become the hero's interact target.
func interact_info() -> Dictionary:
	return {"title": display_name, "verb": "Agarrar", "desc": "", "progress": -1.0,
		"anchor": lock_point() + Vector3(0, 1.0, 0)}


## How far the wrestle has got for the hero (0..1: good squeezes of the ones it takes), or < 0 when the beast does
## not say: the UI's wrestle prompt fills its ring with it (grapple protocol, docs/COMBAT.md 6.6). Override.
func grapple_progress() -> float:
	return -1.0


## Desired horizontal velocity towards `goal` at `speed`, easing in within `arrive` m, kept apart from other
## enemies and stepping round obstacles ahead (two feelers on the world layer).
func steer_to(goal: Vector3, speed: float, arrive: float = 1.0) -> Vector3:
	var d := Combat.flat(goal - global_position)
	var dist := d.length()
	var v := Vector3.ZERO
	if dist > 0.01:
		v = d / dist * speed * clampf(dist / maxf(arrive, 0.01), 0.0, 1.0)
	v += separation(radius * 2.0 + 0.7) * speed * 0.9
	if v.length() > 0.2:
		v += _avoid(v) * speed
	return v.limit_length(speed)


## Unit-ish push away from other enemies closer than `r` (m).
func separation(r: float) -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame != _all_frame:
		_all_frame = frame
		_all_enemies = get_tree().get_nodes_in_group("enemy")
	var push := Vector3.ZERO
	for e in _all_enemies:
		if e == self or not is_instance_valid(e):
			continue
		var e3 := e as Node3D
		var d := Combat.flat(global_position - e3.global_position)
		var l := d.length()
		if l < r and l > 0.001:
			push += d / l * (1.0 - l / r)
	return push.limit_length(1.0)


var _avoid_q: PhysicsRayQueryParameters3D = null


func _avoid(v: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var dir := v.normalized()
	var from := global_position + Vector3(0, minf(height * 0.5, 0.8), 0)
	var out := Vector3.ZERO
	if _avoid_q == null:
		_avoid_q = PhysicsRayQueryParameters3D.new()
		_avoid_q.collision_mask = 1
		_avoid_q.exclude = [get_rid()]
	for i in 2:
		var f := dir.rotated(Vector3.UP, -0.45 if i == 0 else 0.45)
		_avoid_q.from = from
		_avoid_q.to = from + f * (radius + 1.4)
		var hit := space.intersect_ray(_avoid_q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			n.y = 0.0
			out += n.normalized() * 0.8 - f * 0.3
	return out


## Turns `facing` towards `p` at `rate` rad/s.
func face_towards(p: Vector3, delta: float, rate: float = 8.0) -> void:
	var d := Combat.flat(p - global_position)
	if d.length_squared() > 1e-4:
		facing = lerp_angle(facing, atan2(-d.x, -d.z), 1.0 - exp(-delta * rate))


func is_yanked() -> bool:
	return _yank_t >= 0.0


func is_sliding() -> bool:
	return _slide_v.length_squared() > 0.01


func _rig_has(action: StringName) -> bool:
	if rig == null:
		return false
	if "ACTIONS" in rig:
		var acts = rig.get("ACTIONS")
		if acts is Dictionary:
			return (acts as Dictionary).has(String(action))
	if rig.has_method("action_length"):
		return float(rig.call("action_length", String(action))) > 0.0
	return true


# --- hooks ---------------------------------------------------------------------------------------------------

func _build() -> void:
	pass


func _think(_delta: float) -> Vector3:
	return Vector3.ZERO


func _modify_damage(_hit: Dictionary, amount: float) -> float:
	return amount


func _on_hurt(_hit: Dictionary) -> void:
	pass


func _on_blocked(_hit: Dictionary) -> void:
	pass


func _on_death(_hit: Dictionary) -> void:
	pass


func _on_telegraph_done() -> void:
	pass


func _on_parried(_hero: Node) -> void:
	pass


func _on_stunned(_seconds: float) -> void:
	pass


## A beast sliding on the chain slammed into `collider` at `speed` m/s (default: stunned, dust, a thud).
func _on_slam(_collider: Object, speed: float) -> void:
	stun_for(stun_on_slam)
	Game.shake(clampf(speed * 0.05, 0.2, 0.5))
	if Game.fx:
		Game.fx.call("dust", global_position + forward() * radius, 8, 0.8)
		Game.fx.call("impact", lock_point(), -forward(), 1.0, Color(1.0, 0.9, 0.7))
	Sfx.play("boulder_thud", global_position, -1.0, 1.1)


func _on_yank_landed() -> void:
	pass


# --- chain: the light yank and the beast slide ---------------------------------------------------------------

func _start_yank(hero: Node3D, d: Vector3) -> void:
	if hero == null:
		_chain_pull = d * CHAIN_PULL_SPEED * (1.0 - knockback_resist)
		stagger = maxf(stagger, 0.3)
		return
	var hp_ := hero.global_position
	var land := hp_ - d * (1.2 + radius + 0.36)
	if Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("height_at"):
		land.y = maxf(float(Game.world.height_at(land.x, land.z)), hp_.y - 1.5)
	else:
		land.y = hp_.y
	_yank_from = global_position
	_yank_to = land
	var dist := _yank_from.distance_to(_yank_to)
	_yank_dur = clampf(dist / 15.0, 0.25, 0.65)
	_yank_h = 0.45 + dist * 0.05
	_yank_t = 0.0
	_yank_stuck = 0
	_kb = Vector3.ZERO
	telegraph_t = 0.0
	stagger = maxf(stagger, _yank_dur + yank_stagger)
	facing = atan2(d.x, d.z) # looking at the hero (d points to the hero)
	if rig and rig.has_method("play"):
		rig.call("play", "hit")


func _physics_yank(delta: float) -> void:
	_yank_t += delta
	var u := clampf(_yank_t / _yank_dur, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var p := _yank_from.lerp(_yank_to, e)
	p.y += sin(PI * u) * _yank_h
	var before := global_position
	velocity = (p - before) / maxf(delta, 1e-4)
	move_and_slide()
	var expected := before.distance_to(p)
	if expected > 0.03 and before.distance_to(global_position) < expected * 0.3:
		_yank_stuck += 1
	else:
		_yank_stuck = 0
	if u >= 1.0 or _yank_stuck >= 4:
		_yank_t = -1.0
		velocity = Vector3.ZERO
		stagger = maxf(stagger, yank_stagger)
		if Game.fx:
			Game.fx.call("dust", global_position, 5, 0.45)
		Sfx.play("body_fall", global_position, -8.0, randf_range(1.0, 1.15))
		_on_yank_landed()


func _physics_slide(delta: float) -> void:
	var spd := _slide_v.length()
	velocity.x = _slide_v.x
	velocity.z = _slide_v.z
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -1.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
	move_and_slide()
	var dir := _slide_v / maxf(spd, 1e-4)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & (1 | 8)) != 0:
			var n := c.get_normal()
			if n.y < 0.6 and Vector3(n.x, 0.0, n.z).normalized().dot(-dir) > 0.45 and spd > SLAM_SPEED:
				_slide_v = Vector3.ZERO
				slam_normal = Vector3(n.x, 0.0, n.z).normalized()
				_on_slam(col, spd)
				return
	_slide_v = _slide_v.move_toward(Vector3.ZERO, SLIDE_DECEL * delta)
	if Game.fx and spd > 2.0 and Engine.get_physics_frames() % 4 == 0:
		Game.fx.call("dust", global_position - dir * radius, 1, 0.3)


# --- simulation ----------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_prev_pos = _curr_pos
	invulnerable = maxf(0.0, invulnerable - delta)
	stagger = maxf(0.0, stagger - delta)
	stun = maxf(0.0, stun - delta)
	if telegraph_t > 0.0:
		telegraph_t -= delta
		if telegraph_t <= 0.0:
			telegraph_t = 0.0
			if alive and stagger <= 0.0:
				_on_telegraph_done()
	if _yank_t >= 0.0 and alive:
		_rest_ticks = 0
		_physics_yank(delta)
	elif _slide_v.length_squared() > 0.01 and alive:
		_rest_ticks = 0
		_physics_slide(delta)
	else:
		var want := Vector3.ZERO
		if alive and stagger <= 0.0 and stun <= 0.0:
			want = _think(delta)
		velocity.x = want.x + _kb.x + _chain_pull.x
		velocity.z = want.z + _kb.z + _chain_pull.z
		# at rest on the floor (a waiting wolf, a training post): no capsule sweep every tick
		if is_on_floor() and absf(velocity.x) + absf(velocity.z) < 1e-4:
			_rest_ticks += 1
		else:
			_rest_ticks = 0
		if _rest_ticks > REST_TICKS:
			velocity = Vector3.ZERO
		else:
			if is_on_floor() and velocity.y <= 0.0:
				velocity.y = -1.0
			else:
				velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
			move_and_slide()
	_kb = _kb.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	_chain_pull = _chain_pull.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * 0.6 * delta)
	_curr_pos = global_position
	if not alive and corpse_time >= 0.0:
		_death_t += delta
		var fade := 0.8
		if corpse_time > fade and _death_t > corpse_time - fade and rig and rig.has_method("set_dissolve"):
			rig.call("set_dissolve", clampf((_death_t - (corpse_time - fade)) / fade, 0.0, 1.0))
		if _death_t >= corpse_time:
			queue_free()


func _process(delta: float) -> void:
	_vis_yaw = lerp_angle(_vis_yaw, facing, 1.0 - exp(-delta * 14.0))
	_sync_visual(Engine.get_physics_interpolation_fraction())


func _sync_visual(frac: float) -> void:
	if rig == null:
		return
	rig.global_position = _prev_pos.lerp(_curr_pos, frac)
	rig.global_rotation = Vector3(0.0, _vis_yaw, 0.0)
