class_name Hero
extends CharacterBody3D
## Heracles. The movement skeleton the CORE stream builds the combat and the chain spear on:
##  - movement relative to the camera, with acceleration, deceleration and smooth turning; walk (half stick), run,
##    sprint (hold Shift / B, or click L3) that spends stamina; a dodge roll on a tap of Shift / B;
##  - jump with coyote time, jump buffering, a shorter hop when released early and a heavier fall; landing (dust,
##    a short recovery after a big fall);
##  - slopes up to 46 degrees, ground snapping down slopes and small steps, step-ups onto ledges <= 0.4 m;
##  - wading in shallow water (slower) and swimming at the sea surface where World.is_water() and the sea is deep:
##    slower, no sinking, no jumping;
##  - interaction (E / pad Y) through Interactables: press or hold;
##  - the damageable contract (team 0) and a PLACEHOLDER attack (one swing on the attack button, hits damageables
##    of team 1 in an arc) so the combat contracts can be tested end to end; CORE replaces it.
## Physics: hero layer 2, a capsule 1.8 m tall (radius 0.36) with its origin at the feet; collides with the world,
## enemies and movable props. The visual (`rig`, top level) is drawn interpolated between physics ticks.
## Rig: res://scripts/gfx/rig_heracles.gd when it exists (HERO stream), else RigHeroStandIn; it is fed through the
## RigHeracles API (set_locomotion, set_motion_state, set_vertical_speed, play...).

signal interact_target_changed(target: Node)
signal hurt(hit: Dictionary)
signal died
signal landed(fall_speed: float)

const RIG_PATH := "res://scripts/gfx/rig_heracles.gd"

# --- tuning (first pass; CORE owns the feel) --------------------------------------------------------------------
const WALK_SPEED := 2.2
const RUN_SPEED := 6.2
const SPRINT_SPEED := 9.0
const SWIM_SPEED := 2.8
const SWIM_SPRINT_SPEED := 4.2
const ACCEL := 40.0
const DECEL := 48.0
const AIR_ACCEL := 11.0
const TURN_RATE := 13.0 # rad/s while running; quicker standing still
const GRAVITY := 24.0
const FALL_MULT := 1.55
const MAX_FALL := 45.0
const JUMP_SPEED := 8.0
const JUMP_CUT := 0.45
const COYOTE := 0.12
const JUMP_BUFFER := 0.14
const STEP_HEIGHT := 0.42
const HARD_LANDING := 13.0
const DODGE_TAP := 0.2 # a press of Shift / B shorter than this is a dodge, longer is sprint
const DODGE_TIME := 0.45
const DODGE_SPEED := 10.0
const DODGE_COST := 22.0
const SPRINT_COST := 16.0 # stamina per second
const STAMINA_REGEN := 34.0
const STAMINA_DELAY := 0.7
## Water depth (m) where the hero starts swimming, and how deep the feet hang while swimming.
const SWIM_DEPTH := 1.3
const SWIM_FLOAT := 1.2
const CAPSULE_R := 0.36
const CAPSULE_H := 1.8

# --- contract fields -------------------------------------------------------------------------------------------
var team := 0
var max_hp := 100.0
var hp := 100.0
var max_stamina := 100.0
var stamina := 100.0
var interact_target: Node = null
var alive := true

# --- state -----------------------------------------------------------------------------------------------------
var input_enabled := true
var rig: Rig
## Yaw the hero faces (model forward = -Z rotated by facing).
var facing := 0.0
## &"ground", &"air", &"swim" or &"zip" (fed to the rig; CORE sets &"zip" while the chain pulls the hero).
var motion_state: StringName = &"ground"
var sprinting := false
var dodging := false
var invulnerable := 0.0
## Debug / test input: when non-zero it replaces the stick (x right, y back), e.g. phystest auto-walk.
var debug_move := Vector2.ZERO

var _coyote := 0.0
var _jump_buf := 0.0
var _jump_held := false
var _air_time := 0.0
var _fall_speed := 0.0
var _land_lock := 0.0
var _dodge_t := 0.0
var _dodge_dir := Vector3.ZERO
var _dodge_press := -1.0
var _sprint_toggle := false
var _stamina_wait := 0.0
var _exhausted := false
var _interacting := false
var _attack_t := 0.0
var _swing_hits := {}
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _vis_yaw := 0.0
var _step_t := 0.0
var _ripple_t := 0.0
var _world = null


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	max_slides = 6
	add_to_group("hero")
	add_to_group("damageable")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_R
	cap.height = CAPSULE_H
	cs.shape = cap
	cs.position = Vector3(0, CAPSULE_H * 0.5, 0)
	add_child(cs)
	if ResourceLoader.exists(RIG_PATH):
		rig = (load(RIG_PATH) as Script).new()
	else:
		rig = RigHeroStandIn.new()
	rig.name = "Rig"
	add_child(rig)
	rig.top_level = true
	rig.event.connect(_on_rig_event)
	_curr_pos = global_position
	_prev_pos = _curr_pos


## Places the hero (start, respawn) without interpolating the jump; resets motion.
func teleport(xf: Transform3D) -> void:
	global_position = xf.origin
	var f := -xf.basis.z
	facing = atan2(-f.x, -f.z)
	_vis_yaw = facing
	velocity = Vector3.ZERO
	_prev_pos = xf.origin
	_curr_pos = xf.origin
	motion_state = &"ground"
	_sync_visual(1.0)


## Where the hero is drawn this frame (interpolated); the camera follows this.
func visual_position() -> Vector3:
	return _prev_pos.lerp(_curr_pos, Engine.get_physics_interpolation_fraction())


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func is_alive() -> bool:
	return alive


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	stamina = max_stamina


## Back on its feet at `xf` with full health (respawn at an altar).
func revive(xf: Transform3D) -> void:
	alive = true
	hp = max_hp
	stamina = max_stamina
	invulnerable = 1.5
	dodging = false
	teleport(xf)
	if rig.has_method("play"):
		rig.action = ""


# --- damage contract -------------------------------------------------------------------------------------------

func take_hit(hit: Dictionary) -> bool:
	if not alive or invulnerable > 0.0:
		return false
	var amount := float(hit.get("amount", 0.0))
	if amount <= 0.0:
		return false
	hp = maxf(0.0, hp - amount)
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	dir.y = 0.0
	if dir.length_squared() > 1e-6:
		var kb := float(hit.get("knockback", 0.0))
		velocity.x = dir.normalized().x * kb
		velocity.z = dir.normalized().z * kb
	var heavy := float(hit.get("stagger", 0.0)) >= 0.5 or amount >= 25.0
	rig.hit_flash(1.0)
	rig.play("hit_heavy" if heavy else "hit")
	_land_lock = maxf(_land_lock, float(hit.get("stagger", 0.2)))
	invulnerable = 0.35
	Game.shake(0.45 if heavy else 0.25)
	Game.hitstop(0.08 if heavy else 0.05)
	Sfx.play("hero_hurt", global_position, -2.0)
	hurt.emit(hit)
	if hp <= 0.0:
		_die()
	return true


func _die() -> void:
	alive = false
	_release_interaction()
	rig.play("death")
	Sfx.play("hero_down", global_position)
	died.emit()
	Game.hero_died.emit()


# --- per physics tick ------------------------------------------------------------------------------------------

func _can_act() -> bool:
	return alive and input_enabled and Game.is_playing() and not (Game.camera != null and Game.camera.is_fly())


func _input_vector() -> Vector2:
	if debug_move != Vector2.ZERO:
		return debug_move.limit_length(1.0)
	if not _can_act():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.2)


## Input in world space (XZ), relative to the camera's yaw; length 0..1.
func _move_dir(iv: Vector2) -> Vector3:
	var b: Basis = Game.camera.yaw_basis() if Game.camera != null else Basis.IDENTITY
	var d := b.x * iv.x + b.z * iv.y
	d.y = 0.0
	return d


func _physics_process(delta: float) -> void:
	_prev_pos = _curr_pos
	_world = Game.world
	invulnerable = maxf(0.0, invulnerable - delta)
	_land_lock = maxf(0.0, _land_lock - delta)
	if not alive:
		_physics_dead(delta)
		return
	var iv := _input_vector()
	var dir := _move_dir(iv)
	var mag := minf(dir.length(), 1.0)
	_update_sprint(delta, mag)
	_update_water()
	match motion_state:
		&"swim":
			_physics_swim(delta, dir, mag)
		_:
			_physics_land(delta, dir, mag)
	_update_stamina(delta)
	_update_interaction(delta)
	_update_attack(delta)
	_update_ripples(delta)
	_curr_pos = global_position
	_feed_rig()


func _physics_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
	velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)
	velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	move_and_slide()
	_curr_pos = global_position
	rig.set_locomotion(0.0, RUN_SPEED)


func _update_sprint(delta: float, mag: float) -> void:
	if not _can_act():
		sprinting = false
		_dodge_press = -1.0
		return
	if Input.is_action_just_pressed("sprint_toggle"):
		_sprint_toggle = true
	if mag < 0.2:
		_sprint_toggle = false
	# Shift / B: a tap rolls, holding sprints.
	if Input.is_action_just_pressed("dodge"):
		_dodge_press = 0.0
	if _dodge_press >= 0.0:
		_dodge_press += delta
		if Input.is_action_just_released("dodge"):
			if _dodge_press < DODGE_TAP:
				_start_dodge()
			_dodge_press = -1.0
	var held := Input.is_action_pressed("sprint") and (_dodge_press < 0.0 or _dodge_press >= DODGE_TAP)
	var want := (held or _sprint_toggle) and mag > 0.5 and motion_state != &"air" and not dodging
	if _exhausted and stamina > max_stamina * 0.3:
		_exhausted = false
	sprinting = want and not _exhausted and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_COST * delta)
		_stamina_wait = STAMINA_DELAY
		if stamina <= 0.0:
			_exhausted = true


func _update_stamina(delta: float) -> void:
	if _stamina_wait > 0.0:
		_stamina_wait -= delta
	elif stamina < max_stamina:
		stamina = minf(max_stamina, stamina + STAMINA_REGEN * delta)


func _start_dodge() -> void:
	if dodging or motion_state != &"ground" or stamina < DODGE_COST * 0.5 or _attack_t > 0.0:
		return
	stamina = maxf(0.0, stamina - DODGE_COST)
	_stamina_wait = STAMINA_DELAY
	var d := _move_dir(_input_vector())
	_dodge_dir = d.normalized() if d.length() > 0.2 else forward()
	facing = atan2(-_dodge_dir.x, -_dodge_dir.z)
	dodging = true
	_dodge_t = 0.0
	invulnerable = maxf(invulnerable, DODGE_TIME * 0.7)
	rig.play("dodge")
	Sfx.play("dodge", global_position, -3.0)


## Swimming starts where the sea is deeper than SWIM_DEPTH and the hero's feet are down at floating depth; it
## ends where the ground comes back up (wading out).
func _update_water() -> void:
	if _world == null:
		return
	var sea: float = _world.sea_level
	var depth: float = sea - float(_world.height_at(global_position.x, global_position.z))
	if motion_state == &"swim":
		if depth < SWIM_DEPTH - 0.25:
			motion_state = &"ground"
	elif depth > SWIM_DEPTH and global_position.y < sea - SWIM_FLOAT + 0.3 and motion_state != &"zip":
		if motion_state == &"air" and _fall_speed > 6.0 and Game.fx:
			Game.fx.call("splash", Vector3(global_position.x, sea, global_position.z), 1.2)
			Sfx.play("splash", global_position, -2.0)
		motion_state = &"swim"
		dodging = false
		velocity.y = minf(velocity.y, 0.0) * 0.2


## The sea surface over the hero right now (waves included); sea_level when there is no Sea.
func _surface_y() -> float:
	var level: float = _world.sea_level
	if Game.sea == null or not is_instance_valid(Game.sea):
		return level
	var depth: float = level - float(_world.height_at(global_position.x, global_position.z))
	return Game.sea.surface_y(global_position.x, global_position.z, depth)


## Ripple rings on the water round the legs while wading and round the body while swimming: about one a second
## standing still, more often on the move.
func _update_ripples(delta: float) -> void:
	if _world == null or Game.fx == null or motion_state == &"air" or not alive:
		return
	var surf := _surface_y()
	var depth := surf - global_position.y
	if depth < 0.06 or depth > 2.5:
		_ripple_t = minf(_ripple_t, 0.15)
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	_ripple_t -= delta * (1.0 + hs * 0.8)
	if _ripple_t <= 0.0:
		_ripple_t = 1.0
		var r := 1.15 if motion_state == &"swim" else 0.8
		# Fx.ring lifts the ring 8 cm: it floats just over the swell.
		Game.fx.call("ring", Vector3(global_position.x, surf - 0.05, global_position.z), r, Color(1.0, 1.0, 1.0, 0.5), 1.1)


func _physics_swim(delta: float, dir: Vector3, mag: float) -> void:
	var top := SWIM_SPRINT_SPEED if sprinting else SWIM_SPEED
	var want := dir.normalized() * top * mag if mag > 0.01 else Vector3.ZERO
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.move_toward(want, (ACCEL * 0.35 if want != Vector3.ZERO else DECEL * 0.25) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	var sea: float = _world.sea_level
	# Float with the swell (Sea.surface_y follows the water shader's waves).
	var target_y := _surface_y() - SWIM_FLOAT
	velocity.y = clampf((target_y - global_position.y) * 6.0, -3.0, 3.0)
	if mag > 0.05:
		facing = lerp_angle(facing, atan2(-dir.x, -dir.z), 1.0 - exp(-delta * TURN_RATE * 0.5))
	_jump_buf = 0.0
	move_and_slide()
	_step_t -= delta * hv.length()
	if _step_t <= 0.0 and hv.length() > 0.5:
		_step_t = 2.2
		if Game.fx:
			Game.fx.call("splash", Vector3(global_position.x, sea, global_position.z) + forward() * 0.4, 0.35)


func _physics_land(delta: float, dir: Vector3, mag: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE
	else:
		_coyote -= delta
	# Jump input (buffered).
	if _can_act() and Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER
	else:
		_jump_buf -= delta
	if _can_act() and Input.is_action_pressed("jump"):
		_jump_held = true
	elif _jump_held:
		_jump_held = false
		if velocity.y > 0.0 and motion_state == &"air":
			velocity.y *= JUMP_CUT
	# Wading slows the hero down: how deep the feet are under the surface (not the seabed under a pier).
	var wade := 1.0
	if _world != null:
		var depth: float = float(_world.sea_level) - global_position.y
		wade = lerpf(1.0, 0.55, clampf(depth / SWIM_DEPTH, 0.0, 1.0))
	# Horizontal.
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if dodging:
		_dodge_t += delta
		var k := 1.0 - smoothstep(0.55, 1.0, _dodge_t / DODGE_TIME)
		hv = _dodge_dir * DODGE_SPEED * k * wade
		if _dodge_t >= DODGE_TIME:
			dodging = false
	else:
		var top := (SPRINT_SPEED if sprinting else RUN_SPEED) * wade
		if mag < 0.55:
			top = lerpf(0.0, WALK_SPEED, mag / 0.55) * wade
		if _land_lock > 0.0 or _attack_t > 0.0:
			top *= 0.25
		var want := dir.normalized() * top if mag > 0.01 else Vector3.ZERO
		var a := ACCEL if want.length() > hv.length() else DECEL
		if not on_floor:
			a = AIR_ACCEL
		hv = hv.move_toward(want, a * delta)
		# Turning: toward the input, or the lock-on target.
		var lock: Node3D = Game.camera.lock_target if Game.camera != null else null
		if lock != null and is_instance_valid(lock):
			var to := lock.global_position - global_position
			facing = lerp_angle(facing, atan2(-to.x, -to.z), 1.0 - exp(-delta * TURN_RATE))
		elif mag > 0.05 and _attack_t <= 0.0:
			var want_yaw := atan2(-dir.x, -dir.z)
			var rate := TURN_RATE * lerpf(1.6, 1.0, clampf(hv.length() / RUN_SPEED, 0.0, 1.0))
			if sprinting:
				rate *= 0.6
			facing = lerp_angle(facing, want_yaw, 1.0 - exp(-delta * rate))
	velocity.x = hv.x
	velocity.z = hv.z
	# Vertical.
	if _jump_buf > 0.0 and _coyote > 0.0 and not dodging and _land_lock <= 0.0:
		velocity.y = JUMP_SPEED
		_jump_buf = 0.0
		_coyote = 0.0
		_jump_held = true
		motion_state = &"air"
		on_floor = false
		rig.play("jump")
	elif not on_floor:
		var g := GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -MAX_FALL)
	var was_air := motion_state == &"air"
	if not on_floor:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	var pre_vel := velocity
	move_and_slide()
	if is_on_floor() or (on_floor and velocity.y <= 0.0):
		_try_step(pre_vel, delta)
	if is_on_floor():
		if was_air or _air_time > 0.15:
			_on_landed(_fall_speed)
		_air_time = 0.0
		_fall_speed = 0.0
		if motion_state != &"zip":
			motion_state = &"ground"
	else:
		_air_time += delta
		if _air_time > 0.12 and motion_state == &"ground":
			motion_state = &"air"
	_slide_off_creatures()
	# Footsteps (dust on soft ground) when the rig does not send its own step events.
	if is_on_floor() and hv.length() > 1.0:
		_step_t -= delta * hv.length()
		if _step_t <= 0.0:
			_step_t = 1.7
			_footstep(wade < 0.95)


## Step-up: after a slide into a low wall while moving, try raising the capsule STEP_HEIGHT, moving on and dropping
## back onto a walkable surface.
func _try_step(pre_vel: Vector3, delta: float) -> void:
	if not is_on_wall():
		return
	var hmove := Vector3(pre_vel.x, 0.0, pre_vel.z)
	if hmove.length() < 0.5:
		return
	var wall_n := get_wall_normal()
	if wall_n.dot(hmove.normalized()) > -0.2:
		return
	var fwd := hmove.normalized() * maxf(hmove.length() * delta, 0.12)
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP_HEIGHT):
		return
	var up_xf := xf.translated(Vector3.UP * STEP_HEIGHT)
	if test_move(up_xf, fwd):
		return
	var fwd_xf := up_xf.translated(fwd)
	var col := KinematicCollision3D.new()
	if not test_move(fwd_xf, Vector3.DOWN * (STEP_HEIGHT + 0.05), col):
		return
	if col.get_normal().y < cos(floor_max_angle):
		return
	global_position = fwd_xf.origin + col.get_travel()
	velocity.y = 0.0


## Never stand on an enemy's head: slip off sideways.
func _slide_off_creatures() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider()
		if o is CollisionObject3D and ((o as CollisionObject3D).collision_layer & 4) != 0 and c.get_normal().y > 0.5:
			var away := global_position - (o as Node3D).global_position
			away.y = 0.0
			if away.length_squared() < 1e-4:
				away = Vector3.RIGHT
			velocity += away.normalized() * 4.0
			velocity.y = minf(velocity.y, -2.0)


func _on_landed(fall: float) -> void:
	landed.emit(fall)
	if fall > 4.0:
		if Game.fx:
			Game.fx.call("dust", global_position, int(clampf(fall * 0.6, 3.0, 12.0)), 0.5 + fall * 0.04)
		Sfx.play("footstep", global_position, -2.0 + minf(fall * 0.3, 6.0), 0.8)
	if fall > 9.0:
		rig.play("land")
	if fall > HARD_LANDING:
		_land_lock = 0.3
		Game.shake(clampf((fall - HARD_LANDING) * 0.04, 0.1, 0.35))


func _footstep(wet: bool) -> void:
	if wet and Game.fx:
		Game.fx.call("splash", global_position + forward() * 0.3, 0.3)
	Sfx.play("footstep", global_position, -14.0, randf_range(0.9, 1.1))


func _on_rig_event(ev_name: String) -> void:
	match ev_name:
		"step":
			_step_t = 99.0 # the rig drives footsteps from now on
			if is_on_floor():
				var wet := _world != null and global_position.y < float(_world.sea_level) - 0.05
				_footstep(wet)
		"impact":
			_swing_impact()


# --- interaction -----------------------------------------------------------------------------------------------

func _update_interaction(delta: float) -> void:
	var it: Object = null
	if _can_act() and motion_state == &"ground" and not dodging:
		it = Interactables.pick(self, global_position, forward())
	if it != interact_target:
		_release_interaction()
		interact_target = it as Node
		interact_target_changed.emit(interact_target)
	if interact_target == null or not _can_act():
		_release_interaction()
		return
	if Input.is_action_just_pressed("interact") and interact_target.has_method("interact_press"):
		interact_target.call("interact_press", self)
		var to := (interact_target as Node3D).global_position - global_position if interact_target is Node3D else forward()
		facing = atan2(-to.x, -to.z)
		rig.play("interact")
	elif Input.is_action_pressed("interact") and interact_target.has_method("interact_hold"):
		_interacting = true
		interact_target.call("interact_hold", delta, self)
	elif _interacting:
		_release_interaction()


func _release_interaction() -> void:
	if _interacting and interact_target != null and is_instance_valid(interact_target) and interact_target.has_method("interact_release"):
		interact_target.call("interact_release", self)
	_interacting = false


# --- PLACEHOLDER attack (CORE replaces it with the real combat) -------------------------------------------------

func _update_attack(delta: float) -> void:
	if _attack_t > 0.0:
		_attack_t -= delta
		return
	if not _can_act() or motion_state != &"ground" or dodging:
		return
	if Input.is_action_just_pressed("attack") and Time.get_ticks_msec() - Game.capture_msec > 200:
		attack()


## One swing; the rig's "impact" event (or a timer fallback) deals the hit.
func attack() -> void:
	_attack_t = rig.play("attack1")
	_swing_hits.clear()
	Sfx.play("swing_%d" % randi_range(1, 3), global_position, -4.0)
	var lock: Node3D = Game.camera.lock_target if Game.camera != null else null
	if lock != null and is_instance_valid(lock):
		var to := lock.global_position - global_position
		facing = atan2(-to.x, -to.z)


func _swing_impact() -> void:
	var origin := global_position + Vector3(0, 1.0, 0)
	var any := false
	for n in get_tree().get_nodes_in_group("damageable"):
		if n == self or not (n is Node3D) or _swing_hits.has(n):
			continue
		if int(n.get("team")) == team:
			continue
		var p := (n as Node3D).global_position + Vector3(0, 1.0, 0)
		var d := p - origin
		d.y *= 0.5
		var dist := d.length()
		if dist > 2.3:
			continue
		var flat := Vector3(d.x, 0.0, d.z).normalized()
		if dist > 0.6 and flat.dot(forward()) < 0.25:
			continue
		var hit := {"amount": 10.0, "kind": &"blade", "dir": forward(), "knockback": 3.5, "stagger": 0.3, "source": self}
		if bool(n.call("take_hit", hit)):
			_swing_hits[n] = true
			any = true
	if any:
		Game.hitstop(0.06)
		Game.shake(0.18)


# --- rig and visual ----------------------------------------------------------------------------------------------

func _feed_rig() -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	rig.set_locomotion(hs, RUN_SPEED)
	if rig.has_method("set_motion_state"):
		rig.call("set_motion_state", motion_state)
	if rig.has_method("set_vertical_speed"):
		rig.call("set_vertical_speed", velocity.y)


func _process(delta: float) -> void:
	_vis_yaw = lerp_angle(_vis_yaw, facing, 1.0 - exp(-delta * 18.0))
	_sync_visual(Engine.get_physics_interpolation_fraction())


func _sync_visual(frac: float) -> void:
	if rig == null:
		return
	rig.global_position = _prev_pos.lerp(_curr_pos, frac)
	rig.global_rotation = Vector3(0.0, _vis_yaw, 0.0)
