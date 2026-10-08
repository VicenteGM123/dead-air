class_name Enemy
extends Unit
## A creature of Nyx. Rises from the sea at its beach, walks the lane toward the lighthouse, breaks walls in
## its way and attacks whatever of Delos comes close.

enum S { SPAWN, WALK, CHASE, ATTACK, DEAD }

var type := "shade"
var data: Dictionary
var lane := 0
var s := 0.0
var lateral := 0.0
var state := S.SPAWN
var target: Unit = null
var attack_cd := 0.0
var _retarget := 0.0
var _vel := Vector3.ZERO
var facing := 0.0
var speed := 2.0
var hover := 0.0
var _t := 0.0
var _dead_t := 0.0
var _leash_from := Vector3.ZERO
var _blocking_wall: Unit = null


func setup(t: String, lane_index: int, lateral_offset: float) -> void:
	type = t
	data = Data.ENEMIES[t]
	lane = lane_index
	lateral = lateral_offset
	team = 1
	display_name = data["name"]
	max_hp = data["hp"] * Game.main.difficulty_hp_mult()
	hp = max_hp
	radius = data["radius"]
	speed = data["speed"] * randf_range(0.92, 1.08)
	is_flying = data.get("flying", false)
	is_heavy = data.get("heavy", false)


func _ready() -> void:
	rig = ModelsCreatures.make(type)
	add_child(rig)
	rig.event.connect(_on_rig_event)
	var spawn_pos := _lane_point(0.0)
	global_position = spawn_pos
	state = S.SPAWN
	invuln = 0.9
	rig.play("spawn")
	rig.set_dissolve(0.85)
	if Game.has_blessing("poseidon"):
		apply_slow(0.45, 6.0)
	if Game.fx:
		Game.fx.splash(Vector3(global_position.x, 0.0, global_position.z), 1.0 + radius)
	if randf() < 0.5 or is_heavy:
		Sfx.play("enemy_spawn", global_position, -6.0 if not is_heavy else 0.0, randf_range(0.85, 1.1))


func _lane_point(at_s: float) -> Vector3:
	var p: Vector3 = Game.island.lane_sample(lane, at_s)
	var p2: Vector3 = Game.island.lane_sample(lane, at_s + 1.0)
	var fwd := p2 - p
	fwd.y = 0.0
	if fwd.length() > 0.001:
		fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var q := p + right * lateral
	q.y = Game.island.height_at(q.x, q.z)
	return q


func _modify_damage(amount: float, kind: String, _from: Node3D) -> float:
	if kind == "arrow" and data.has("arrow_resist"):
		return amount * (1.0 - float(data["arrow_resist"]))
	return amount


func _physics_process(delta: float) -> void:
	_t += delta
	if state == S.DEAD:
		_dead_t += delta
		rig.set_dissolve(clampf(_dead_t / 0.7, 0.0, 1.0))
		if _dead_t > 0.8:
			queue_free()
		return
	var smul := tick_status(delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	if state == S.SPAWN:
		var k := clampf(_t / 1.0, 0.0, 1.0)
		rig.set_dissolve(0.85 * (1.0 - k))
		s += speed * delta * 0.5
		_step_to(_lane_point(s), delta, smul * 0.5)
		if _t >= 1.0:
			state = S.WALK
			rig.set_dissolve(0.0)
		_finish_frame(delta)
		return
	if stun > 0.0:
		_vel = _vel.lerp(Vector3.ZERO, 1.0 - exp(-delta * 10.0))
		_finish_frame(delta)
		return
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.3 + randf() * 0.15
		_think()
	match state:
		S.WALK:
			var goal := _lane_point(s + 1.6)
			var d := goal - global_position
			d.y = 0.0
			if d.length() < 3.0:
				s += speed * smul * delta
			_step_to(goal, delta, smul)
			if s >= Game.island.lane_length(lane) - 0.5:
				target = Game.pharos
				state = S.CHASE
		S.CHASE:
			if not _target_ok():
				target = null
				state = S.WALK
			else:
				var reach := _reach(target)
				var dist := flat_dist(target.global_position)
				if dist <= reach:
					state = S.ATTACK
				else:
					var gp := target.global_position
					if data.get("ranged", false):
						# Keep shooting distance.
						gp = target.global_position + (global_position - target.global_position).normalized() * (reach * 0.85)
					_step_to(gp, delta, smul)
		S.ATTACK:
			if not _target_ok():
				target = null
				state = S.WALK
			else:
				var dir := target.global_position - global_position
				dir.y = 0.0
				facing = lerp_angle(facing, Unit.yaw_to(dir), 1.0 - exp(-delta * 10.0))
				_vel = _vel.lerp(Vector3.ZERO, 1.0 - exp(-delta * 10.0))
				if flat_dist(target.global_position) > _reach(target) + 0.6 and not rig.is_busy():
					state = S.CHASE
				elif attack_cd <= 0.0 and not rig.is_busy():
					attack_cd = data["rate"] * randf_range(0.9, 1.1)
					rig.play(_attack_anim())
	_finish_frame(delta)


func _attack_anim() -> String:
	return "attack"


func _finish_frame(delta: float) -> void:
	if _vel.length() > 0.2 and state != S.ATTACK:
		facing = lerp_angle(facing, Unit.yaw_to(_vel), 1.0 - exp(-delta * 8.0))
	rig.rotation.y = facing
	rig.set_locomotion(_vel.length(), speed)
	var p := global_position
	p = Separation.apply(self, p, 1, 0.35)
	if not is_flying:
		p = Obstacles.push_out(p, radius * 0.8)
	var h := Game.island.height_at(p.x, p.z)
	hover = lerpf(hover, 2.2 + sin(_t * 2.5) * 0.25 if is_flying and state != S.SPAWN else 0.0, 1.0 - exp(-delta * 3.0))
	global_position = Vector3(p.x, maxf(h, -2.2) + hover, p.z)


func _step_to(goal: Vector3, delta: float, smul: float) -> void:
	var d := goal - global_position
	d.y = 0.0
	var want := Vector3.ZERO
	if d.length() > 0.15:
		want = d.normalized() * speed * smul
	_vel = _vel.lerp(want, 1.0 - exp(-delta * 6.0))
	global_position += _vel * delta


func _apply_knock(step: Vector3) -> void:
	global_position += step


func _reach(t: Unit) -> float:
	return radius + t.radius + float(data["range"])


func _target_ok() -> bool:
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	# Leash: give up chasing mobile targets that run far away.
	if not target.is_building and flat_dist(target.global_position) > float(data["aggro"]) * 2.4 + 2.0:
		return false
	return true


func _think() -> void:
	if state == S.ATTACK and _target_ok() and target.is_building:
		return
	# Walls on our lane hold the line for walkers.
	if not is_flying:
		var w := WallBuilding.blocking(lane, s - 1.0, s + 2.6)
		if w:
			target = w
			state = S.CHASE if state != S.ATTACK else state
			return
	var aggro := float(data["aggro"])
	var best: Unit = null
	var best_score := INF
	var prefer_buildings: bool = data.get("heavy", false) or is_flying
	for u in Game.units[0]:
		if not is_instance_valid(u) or not u.alive:
			continue
		if u is WallBuilding and (is_flying or not _wall_relevant(u)):
			continue
		if u is Building and u.type == "dock":
			continue
		var d: float = u.flat_dist(global_position) - u.radius
		var limit := aggro + (2.0 if u.is_building else 0.0)
		if d > limit:
			continue
		var score := d
		if prefer_buildings:
			score += 0.0 if u.is_building else 3.0
		else:
			score += 1.5 if u.is_building else 0.0
		if u is PharosBuilding:
			score -= 1.0
		if score < best_score:
			best_score = score
			best = u
	if best and best != target:
		target = best
		if state != S.ATTACK:
			state = S.CHASE
	elif best == null and state == S.CHASE and not _target_ok():
		state = S.WALK
		target = null


func _wall_relevant(w: Unit) -> bool:
	return w.lane == lane and absf(w.lane_s - s) < 4.0


func _on_rig_event(ev: String) -> void:
	if state == S.DEAD:
		return
	match ev:
		"impact":
			if data.get("ranged", false):
				_do_release()
			else:
				_do_impact()
		"release":
			_do_release()


func _do_impact() -> void:
	if not _target_ok():
		return
	var mult := float(data.get("building_mult", 1.0)) if target.is_building else 1.0
	if data.has("aoe"):
		var center := global_position + Unit.dir_of_yaw(facing) * (radius + 0.8)
		for u in Game.query(0, center, float(data["aoe"])):
			var m := float(data.get("building_mult", 1.0)) if u.is_building else 1.0
			u.take_damage(float(data["dmg"]) * m, self, 3.0, "smash")
		Sfx.play("cyclops_stomp", center, 0.0, randf_range(0.9, 1.05))
		Game.shake(0.35)
		if Game.fx:
			Game.fx.ring(center, float(data["aoe"]), Color(0.6, 0.5, 1.0, 0.7), 0.4)
			Game.fx.dust(center, 10, 1.5)
		return
	if flat_dist(target.global_position) <= _reach(target) + 0.8:
		target.take_damage(float(data["dmg"]) * mult, self, 0.6, "claw")


func _do_release() -> void:
	if not _target_ok():
		return
	var from := global_position + Vector3(0, 1.3 + hover * 0.2, 0) + Unit.dir_of_yaw(facing) * 0.5
	Game.projectiles.orb(from, target, float(data["dmg"]), self)


func _on_death() -> void:
	state = S.DEAD
	_dead_t = 0.0
	rig.play("death")
	Game.unregister(self, team)
	Game.stats["kills"] += 1
	Sfx.play("enemy_die", global_position, -4.0, randf_range(0.85, 1.15))
	if Game.fx:
		Game.fx.smoke(global_position + Vector3(0, 0.8 + hover, 0), 4 if not is_heavy else 10, Color(0.25, 0.2, 0.45, 0.8))
		Game.fx.motes(global_position + Vector3(0, 1.0 + hover, 0), 6, Pal.NYX_GLOW)
	if Game.main and Game.main.has_method("on_enemy_killed"):
		Game.main.on_enemy_killed(self)
