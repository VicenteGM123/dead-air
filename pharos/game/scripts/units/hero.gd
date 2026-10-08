class_name Hero
extends Unit
## The Keeper. Moves with WASD / stick, 3-hit spear combo, shield bash, dodge roll with i-frames, Zeus' bolt.

signal favor_changed(v: float, maxv: float)
signal respawn_tick(seconds_left: float)
signal interact_target_changed(target: Node)

enum S { NORMAL, ATTACK, BASH, DODGE, CAST, DEAD }

var state := S.NORMAL
var facing := 0.0 # yaw
var vel := Vector3.ZERO
var combo := 0
var combo_queued := false
var combo_reset_t := 0.0
var bash_cd := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector3.ZERO
var favor := 0.0
var respawn_t := 0.0
var interact_target: Node = null
var _interacting := false
var _step_t := 0.0
var _light: OmniLight3D
var _hit_this_swing := {}
var _attack_dir := Vector3.FORWARD
var spawn_point := Vector3(0, 0, 9.5)
var input_enabled := true
var touch_move := Vector2.ZERO


func _ready() -> void:
	team = 0
	display_name = "Fanós"
	radius = 0.5
	max_hp = Data.HERO["hp"]
	hp = max_hp
	rig = RigHero.new()
	add_child(rig)
	rig.event.connect(_on_rig_event)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 2.3, 0)
	_light.light_color = Color(1.0, 0.78, 0.5)
	_light.omni_range = 8.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func speed_stat() -> float:
	return Data.HERO["speed"] * (1.2 if Game.has_blessing("hermes") else 1.0)


func dmg_mult() -> float:
	return 1.3 if Game.has_blessing("ares") else 1.0


func max_hp_stat() -> float:
	return Data.HERO["hp"] + (40.0 if Game.has_blessing("apollo") else 0.0)


func favor_max() -> float:
	return Data.HERO["favor_max"]


func refresh_stats() -> void:
	var r := hp_ratio()
	max_hp = max_hp_stat()
	hp = max_hp * r


func add_favor(v: float) -> void:
	if state == S.DEAD:
		return
	var before := favor
	favor = minf(favor_max(), favor + v * (1.35 if Game.has_blessing("zeus") else 1.0))
	if before < favor_max() and favor >= favor_max():
		Sfx.play("favor_ready")
		Game.say("", "El Haz del Faro está listo  ·  Q", "favor")
	favor_changed.emit(favor, favor_max())


func _input_vector() -> Vector3:
	if not input_enabled:
		return Vector3.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.2)
	if touch_move.length() > 0.1:
		v = touch_move
	return Vector3(v.x, 0, v.y)


func _physics_process(delta: float) -> void:
	if Game.paused:
		return
	var smul := tick_status(delta)
	bash_cd = maxf(0.0, bash_cd - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	_update_light(delta)
	if state == S.DEAD:
		respawn_t -= delta
		respawn_tick.emit(respawn_t)
		if respawn_t <= 0.0:
			_respawn()
		return
	var inp := _input_vector()
	var spd := speed_stat() * smul
	_regen(delta)
	match state:
		S.NORMAL:
			_move(inp * spd, delta, 14.0)
			if inp.length() > 0.1:
				_face(inp, delta, 14.0)
			_read_actions(inp)
			if combo_reset_t > 0.0:
				combo_reset_t -= delta
				if combo_reset_t <= 0.0:
					combo = 0
		S.ATTACK:
			_move(inp * spd * 0.25 + _attack_dir * _lunge_speed(), delta, 20.0)
			if rig.ap() > 0.4 and Input.is_action_just_pressed("attack"):
				combo_queued = true
			if Input.is_action_just_pressed("dodge") and rig.ap() > 0.55:
				_start_dodge(inp)
			elif not rig.is_busy() or (combo_queued and rig.ap() > 0.68):
				if combo_queued and combo < 3:
					_start_attack(inp)
				else:
					state = S.NORMAL
					combo_reset_t = 0.35
					if combo >= 3:
						combo = 0
		S.BASH:
			_move(_attack_dir * (5.0 if rig.ap() < 0.5 else 0.0), delta, 20.0)
			if not rig.is_busy():
				state = S.NORMAL
		S.DODGE:
			var p := rig.ap()
			var sp := lerpf(14.0, 4.0, p)
			_move(dodge_dir * sp, delta, 40.0)
			invuln = maxf(invuln, 0.02) if p < 0.8 else invuln
			if not rig.is_busy():
				state = S.NORMAL
		S.CAST:
			_move(Vector3.ZERO, delta, 20.0)
			_beam_tick()
			if not rig.is_busy():
				state = S.NORMAL
	rig.set_locomotion(Vector2(vel.x, vel.z).length(), speed_stat())
	(rig as RigHero).flame_power = hp_ratio()
	rig.rotation.y = facing
	global_position.y = Game.island.height_at(global_position.x, global_position.z)
	_update_interaction(delta)


func _lunge_speed() -> float:
	var p := rig.ap()
	if combo < 3 and p > 0.3 and p < 0.55:
		return 2.6
	if combo == 3 and p > 0.42 and p < 0.56:
		return 3.0
	return 0.0


func _read_actions(inp: Vector3) -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0.0:
		_start_dodge(inp)
	elif Input.is_action_just_pressed("attack") and not _interacting:
		_start_attack(inp)
	elif Input.is_action_just_pressed("bash") and bash_cd <= 0.0:
		_start_bash(inp)
	elif Input.is_action_just_pressed("power") and favor >= favor_max():
		_start_cast()


func _aim(inp: Vector3, max_dist: float = 4.5, cone_deg: float = 75.0) -> Vector3:
	var fwd := inp.normalized() if inp.length() > 0.1 else Unit.dir_of_yaw(facing)
	var best: Node3D = null
	var best_score := INF
	for e in Game.query(1, global_position, max_dist, false):
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		var ang := rad_to_deg(fwd.angle_to(d.normalized()))
		if ang > cone_deg:
			continue
		var score := d.length() + ang * 0.03
		if score < best_score:
			best_score = score
			best = e
	if best:
		var d2: Vector3 = best.global_position - global_position
		d2.y = 0.0
		if d2.length() > 0.05:
			return d2.normalized()
	return fwd


func _start_attack(inp: Vector3) -> void:
	combo_queued = false
	combo = combo % 3 + 1
	_attack_dir = _aim(inp)
	facing = Unit.yaw_to(_attack_dir)
	state = S.ATTACK
	_hit_this_swing.clear()
	rig.play("attack%d" % combo)
	Sfx.play("swing_%d" % combo, global_position, -2.0, randf_range(0.95, 1.05))


func _start_bash(inp: Vector3) -> void:
	_attack_dir = _aim(inp, 4.0, 80.0)
	facing = Unit.yaw_to(_attack_dir)
	state = S.BASH
	bash_cd = Data.HERO["bash_cd"]
	rig.play("bash")


func _start_dodge(inp: Vector3) -> void:
	dodge_dir = inp.normalized() if inp.length() > 0.1 else Unit.dir_of_yaw(facing)
	facing = Unit.yaw_to(dodge_dir)
	state = S.DODGE
	combo = 0
	combo_queued = false
	dodge_cd = Data.HERO["dodge_cd"] * (0.6 if Game.has_blessing("hermes") else 1.0)
	invuln = 0.32
	rig.play("dodge")
	Sfx.play("dodge", global_position, -3.0, randf_range(0.95, 1.08))
	if Game.fx:
		Game.fx.dust(global_position, 6, 0.6)


func _start_cast() -> void:
	state = S.CAST
	favor = 0.0
	favor_changed.emit(favor, favor_max())
	invuln = 1.5
	_beam_hit.clear()
	Game.stats["bolts"] += 1
	rig.play("cast")
	Sfx.play("blessing", global_position, -2.0, 1.2)
	Sfx.play("lightning", global_position, -6.0, 1.4)
	Game.shake(0.3)
	if Game.fx:
		Game.fx.ring(global_position, Data.HERO["beam_radius"], Color(1.0, 0.85, 0.55, 0.7), 0.7)
		Game.fx.flash_screen(Color(1.0, 0.9, 0.7), 0.3)


func _on_rig_event(ev: String) -> void:
	if ev != "impact":
		return
	match state:
		S.ATTACK:
			var dmg: float = Data.HERO["combo"][combo - 1] * dmg_mult()
			if combo == 3:
				_slam(dmg)
			else:
				_strike(3.1, 78.0, dmg, 1.4, 0.0, "swing")
		S.BASH:
			_flash()


func _strike(reach: float, half_angle: float, dmg: float, knockback: float, stun_s: float, kind: String, origin: Vector3 = Vector3.INF) -> int:
	var hits := 0
	var from := global_position if not origin.is_finite() else origin
	var fwd := _attack_dir
	for e in Game.query(1, from, reach, false):
		if _hit_this_swing.has(e):
			continue
		var d: Vector3 = e.global_position - from
		d.y = 0.0
		if half_angle < 180.0 and d.length() > 0.3 and rad_to_deg(fwd.angle_to(d.normalized())) > half_angle:
			continue
		_hit_this_swing[e] = true
		var dealt: float = e.take_damage(dmg, self, knockback, kind)
		if stun_s > 0.0:
			e.stun = maxf(e.stun, stun_s)
		if dealt > 0.0:
			hits += 1
			add_favor(dealt * 0.55)
			if Game.fx:
				Game.fx.hit_spark(e.global_position + Vector3(0, 1.0, 0), fwd)
	if hits > 0:
		Game.hitstop(0.05 if kind != "slam" else 0.08)
		Sfx.play("hit_%d" % (randi() % 3 + 1), global_position, -1.0, randf_range(0.85, 1.0))
		Game.shake(0.14)
	return hits


## Third blow: the anchor comes down and the ground shakes.
func _slam(dmg: float) -> void:
	var at := global_position + _attack_dir * 1.7
	_strike(3.2, 180.0, dmg, 2.6, 0.35, "slam", at)
	Sfx.play("cyclops_stomp", at, 0.0, 1.25)
	Game.shake(0.32)
	if Game.fx:
		var g := Game.island.ground(at)
		Game.fx.ring(g, 3.2, Color(1.0, 0.85, 0.6, 0.8), 0.45)
		Game.fx.dust(g, 14, 1.4)


## The lens flares: blinding light in a cone, creatures reel back stunned.
func _flash() -> void:
	var hits := _strike(4.2, 62.0, Data.HERO["bash_dmg"] * dmg_mult(), 3.6, 1.4, "flash")
	Sfx.play("bash", global_position, -2.0, 1.1)
	Sfx.play("favor_ready", global_position, -8.0, 1.6)
	Game.shake(0.22 if hits > 0 else 0.1)
	if Game.fx:
		var at := global_position + _attack_dir * 1.2 + Vector3(0, 1.1, 0)
		Game.fx.hit_spark(at, _attack_dir, 2.2)
		Game.fx.ring(Game.island.ground(global_position + _attack_dir * 2.2), 2.4, Color(1.0, 0.92, 0.7, 0.8), 0.35)


var _beam_hit := {}


## Special: Fanós becomes the lighthouse; the beam sweeps all around and burns what it touches.
func _beam_tick() -> void:
	var r: RigHero = rig
	if not r.beam_active():
		return
	var yaw := r.beam_yaw()
	var dir := Unit.dir_of_yaw(yaw)
	var dmg: float = Data.HERO["beam_dmg"] * (1.5 if Game.has_blessing("zeus") else 1.0)
	for e in Game.query(1, global_position, Data.HERO["beam_radius"], false):
		if _beam_hit.has(e):
			continue
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		if d.length() > 0.6 and rad_to_deg(dir.angle_to(d.normalized())) > 16.0:
			continue
		_beam_hit[e] = true
		e.take_damage(dmg, self, 2.5, "beam")
		e.stun = maxf(e.stun, 1.5)
		Sfx.play("zap", e.global_position, -6.0, randf_range(0.9, 1.2))
		if Game.fx:
			Game.fx.hit_spark(e.global_position + Vector3(0, 1.0, 0), dir, 1.4)
			Game.fx.motes(e.global_position + Vector3(0, 1.0, 0), 6, Color(1.0, 0.85, 0.5))


func _move(target_vel: Vector3, delta: float, accel: float) -> void:
	vel = vel.lerp(target_vel, 1.0 - exp(-accel * delta))
	if knock.length_squared() > 0.001:
		pass
	var step := vel * delta
	_try_move(step)
	if vel.length() > 2.0 and state == S.NORMAL:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.28
			Sfx.play("footstep", global_position, -14.0, randf_range(0.85, 1.15))
			if Game.fx and randf() < 0.5:
				Game.fx.dust(global_position, 1, 0.25)


func _apply_knock(step: Vector3) -> void:
	_try_move(step)


func _try_move(step: Vector3) -> void:
	var isl := Game.island
	var p := global_position + step
	if not isl.is_walkable(p.x, p.z):
		# Slide along the coast.
		var px := global_position + Vector3(step.x, 0, 0)
		var pz := global_position + Vector3(0, 0, step.z)
		if isl.is_walkable(px.x, px.z):
			p = px
		elif isl.is_walkable(pz.x, pz.z):
			p = pz
		else:
			return
	p = Obstacles.push_out(p, radius)
	global_position = Vector3(p.x, global_position.y, p.z)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	var target := Unit.yaw_to(dir)
	facing = lerp_angle(facing, target, 1.0 - exp(-rate * delta))


func _regen(delta: float) -> void:
	var idle := now() - last_hit
	if not Game.is_night():
		heal(delta * 25.0)
	elif idle > 4.0:
		heal(delta * (12.0 if Game.has_blessing("apollo") else 4.0))


func _on_hurt(amount: float, _from: Node3D, _kind: String) -> void:
	Sfx.play("hero_hurt", global_position, -2.0, randf_range(0.95, 1.05))
	Game.shake(clampf(amount / 30.0, 0.1, 0.45))
	if Game.hud and Game.hud.has_method("hurt_flash"):
		Game.hud.hurt_flash(amount / max_hp)
	if state == S.NORMAL and amount >= 8.0:
		rig.play("hit")


func _on_death() -> void:
	state = S.DEAD
	Game.stats["deaths"] += 1
	rig.play("death")
	(rig as RigHero).lit = false
	Sfx.play("hero_down", global_position)
	respawn_t = Data.HERO_RESPAWN
	Game.say("La llama de Fanós se ha apagado", "El Faro volverá a encenderla", "danger")
	_release_interaction()


func _respawn() -> void:
	alive = true
	max_hp = max_hp_stat()
	hp = max_hp
	state = S.NORMAL
	invuln = 2.0
	var p := Game.island.ground(spawn_point)
	global_position = p
	vel = Vector3.ZERO
	knock = Vector3.ZERO
	facing = PI
	rig.set_dissolve(0.0)
	(rig as RigHero).lit = true
	rig.play("relight")
	if Game.fx:
		Game.fx.lightning(global_position, false, Color(1.0, 0.8, 0.5))
		Game.fx.ring(global_position, 3.0, Color(1.0, 0.8, 0.5, 0.7), 0.5)
		if Game.pharos and is_instance_valid(Game.pharos):
			Game.fx.coin_fly(Game.pharos.anchor("fire", Vector3(0, 9, 0)), global_position + Vector3(0, 2.0, 0))
	Sfx.play("blessing", global_position, -6.0)
	Game.register(self, team)


func teleport(p: Vector3) -> void:
	global_position = Game.island.ground(p)
	vel = Vector3.ZERO


func _update_light(delta: float) -> void:
	var target := 0.0
	if Game.main and Game.main.tod:
		target = Game.main.tod.night_amount() * 0.9
	_light.light_energy = lerpf(_light.light_energy, target, 1.0 - exp(-delta * 2.0))
	_light.visible = _light.light_energy > 0.02


# --- interaction (build spots, the night horn, cats) -------------------------------------------------------

func _update_interaction(delta: float) -> void:
	var best: Node = null
	if state == S.NORMAL or state == S.ATTACK:
		var best_d := INF
		for it in Interactables.list:
			if not is_instance_valid(it) or not it.can_interact(self):
				continue
			var d := flat_dist(it.interact_position())
			if d < it.interact_range() and d < best_d:
				best_d = d
				best = it
	if best != interact_target:
		_release_interaction()
		interact_target = best
		interact_target_changed.emit(best)
	if interact_target and input_enabled and Input.is_action_pressed("interact") and state == S.NORMAL:
		_interacting = true
		interact_target.interact_hold(delta, self)
	elif _interacting:
		_release_interaction()


func _release_interaction() -> void:
	if _interacting and is_instance_valid(interact_target):
		interact_target.interact_release(self)
	_interacting = false
