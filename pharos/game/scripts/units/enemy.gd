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
var _land_s := 0.0 # lane distance of the beach landing: before it, a walker is still wading ashore
var _landed := false
var spawn_time := 1.0 # seconds rising from the sea (or from the ground, for the Hydra's brood)
var hold := 0.0 # seconds standing still on purpose (the Hydra's roar)


func setup(t: String, lane_index: int, lateral_offset: float) -> void:
	type = t
	data = Data.ENEMIES[t]
	lane = lane_index
	lateral = lateral_offset
	team = 1
	display_name = data["name"]
	max_hp = data["hp"] * Game.main.difficulty_hp_mult() * (1.0 if data.get("boss", false) else Data.night_hp_mult(Game.night))
	hp = max_hp
	radius = data["radius"]
	speed = data["speed"] * randf_range(0.92, 1.08)
	is_flying = data.get("flying", false)
	is_heavy = data.get("heavy", false)
	if Game.island and lane < Game.island.beaches.size():
		_land_s = Game.island.lane_project(lane, Game.island.beaches[lane]["landing"]) + radius


func _ready() -> void:
	rig = ModelsCreatures.make(type)
	add_child(rig)
	rig.event.connect(_on_rig_event)
	# Usually at the sea end of the lane; the Hydra's brood starts further in (s set before add_child).
	var spawn_pos := _lane_point(s)
	global_position = spawn_pos
	state = S.SPAWN
	invuln = 0.9
	rig.play("spawn")
	rig.set_dissolve(0.85)
	if not _on_land(spawn_pos):
		if Game.fx:
			Game.fx.splash(Vector3(global_position.x, 0.0, global_position.z), 1.0 + radius)
		if randf() < 0.5 or is_heavy:
			Sfx.play("enemy_spawn", global_position, -6.0 if not is_heavy else 0.0, randf_range(0.85, 1.1))
	elif Game.fx:
		# Called up on land: the creature condenses out of a puff of night.
		Game.fx.smoke(spawn_pos + Vector3(0, 0.6, 0), 5, Color(0.25, 0.2, 0.45, 0.8))
		Game.fx.motes(spawn_pos + Vector3(0, 0.9, 0), 5, Pal.NYX_GLOW)


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
	poll_events()
	attack_cd = maxf(0.0, attack_cd - delta)
	if state == S.SPAWN:
		var k := clampf(_t / 1.0, 0.0, 1.0)
		rig.set_dissolve(0.85 * (1.0 - k))
		s += speed * delta * 0.5
		_step_to(_lane_point(s), delta, smul * 0.5)
		if _t >= spawn_time:
			state = S.WALK
			rig.set_dissolve(0.0)
			_on_spawned()
		_finish_frame(delta)
		return
	if not _landed and (s >= _land_s or _on_land(global_position)):
		_landed = true
		# Poseidon: the creatures that come out of the sea are slowed as they set foot on the beach.
		if Game.has_blessing("poseidon"):
			apply_slow(0.45, 6.0)
	if stun > 0.0 or hold > 0.0:
		hold = maxf(0.0, hold - delta)
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
				var dist := _dist_to(target)
				if dist <= reach:
					state = S.ATTACK
				else:
					var aim := _aim_point(target)
					var gp := aim
					if data.get("ranged", false):
						# Keep shooting distance (but never back off into the sea).
						gp = aim + (global_position - aim).normalized() * (reach * 0.85)
						if not _on_land(gp):
							gp = aim
					_step_to(gp, delta, smul)
		S.ATTACK:
			if not _target_ok():
				target = null
				state = S.WALK
			else:
				var dir := _aim_point(target) - global_position
				dir.y = 0.0
				facing = lerp_angle(facing, Unit.yaw_to(dir), 1.0 - exp(-delta * 10.0))
				_vel = _vel.lerp(Vector3.ZERO, 1.0 - exp(-delta * 10.0))
				if _dist_to(target) > _reach(target) + 0.6 and not rig.is_busy():
					state = S.CHASE
				elif attack_cd <= 0.0 and not rig.is_busy():
					attack_cd = data["rate"] * randf_range(0.9, 1.1)
					rig.play(_attack_anim())
					# Ranged creatures loose their orb on "release" (a rig may also call it "impact": both count once).
					expect_event("release" if data.get("ranged", false) else "impact", 0.56)
					_on_attack_started()
	_finish_frame(delta)


func _attack_anim() -> String:
	return "attack"


## Hooks for special creatures (the Hydra): right after an attack starts, and when the creature has risen.
func _on_attack_started() -> void:
	pass


func _on_spawned() -> void:
	pass


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
	# Keres swerve around Fanós' lantern on their way to the village (he has to chase them, or let a tower shoot).
	if is_flying and state != S.ATTACK and is_instance_valid(Game.hero) and Game.hero.alive and not (target is Hero):
		var away: Vector3 = global_position - Game.hero.global_position
		away.y = 0.0
		var dd := away.length()
		if dd < 4.5 and dd > 0.01:
			want += away / dd * speed * smul * (1.0 - dd / 4.5) * 1.3
			want = want.limit_length(speed * smul * 1.15)
	_vel = _vel.lerp(want, 1.0 - exp(-delta * 6.0))
	global_position += _vel * delta


func _apply_knock(step: Vector3) -> void:
	global_position += step


func _reach(t: Unit) -> float:
	if t is WallBuilding:
		# Walls are struck anywhere along their line, from close up (claws on the palisade, not at arm's length).
		return radius + 0.25 + float(data["range"]) * 0.6
	return radius + t.radius + float(data["range"])


## Where to go for (and face) a target: the nearest point of a wall's line, the centre of anything else.
func _aim_point(t: Unit) -> Vector3:
	if t is WallBuilding:
		return (t as WallBuilding).closest_point(global_position)
	return t.global_position


## Distance to a target as _reach() counts it: to a wall's line, to anything else's centre.
func _dist_to(t: Unit) -> float:
	if t is WallBuilding:
		return (t as WallBuilding).line_dist(global_position)
	return flat_dist(t.global_position)


func _target_ok() -> bool:
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	# Leash: give up chasing mobile targets that run far away.
	if not target.is_building and flat_dist(target.global_position) > float(data["aggro"]) * 2.4 + 2.0:
		return false
	return true


func _think() -> void:
	# Creatures come ashore before they fight (and archers never shoot from the water): out there nobody could
	# ever reach them.
	if not is_flying and not _on_land(global_position) and (data.get("ranged", false) or s < _land_s):
		if state != S.WALK:
			state = S.WALK
			target = null
		return
	if state == S.ATTACK and _target_ok() and target.is_building:
		return
	# Walls on our lane hold the line for walkers (also when we reach one off the lane's line, say after biting a
	# tower beside the road: then our lane position lags behind where we really are).
	if not is_flying:
		var w := WallBuilding.blocking(lane, s - 1.0, s + 2.6)
		if w == null:
			w = WallBuilding.facing(lane, global_position, radius + 2.0)
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
		# Piers stand in the water: walkers leave them alone, Keres do not.
		if u is Building and u.type == "dock" and not is_flying:
			continue
		var d: float = u.flat_dist(global_position) - u.radius
		var limit := _aggro_for(u, aggro)
		if d > limit:
			continue
		var score := d
		if prefer_buildings:
			score += 0.0 if u.is_building else 3.0
		else:
			score += 1.5 if u.is_building else 0.0
		if u is PharosBuilding:
			score -= 1.0
		if is_flying and _is_hearth(u):
			score -= 6.0
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


## How far this creature looks for `u` (buildings draw them from a little further away). Keres fly over Fanós and
## the hoplites to dive at the village: they only turn on someone who gets right in their way.
func _aggro_for(u: Unit, aggro: float) -> float:
	if is_flying and _is_hearth(u):
		return HEARTH_SENSE
	if u.is_building:
		return aggro + 2.0
	if is_flying:
		return minf(aggro, 1.5)
	return aggro


## Keres are drawn to the hearths of Delos (houses, olive groves, piers) from this far off, over walls and past
## Fanós: the towers (and Fanós, if he gives chase) are what keeps them from the village's income.
const HEARTH_SENSE := 14.0


static func _is_hearth(u: Unit) -> bool:
	return u is Building and (u.type == "house" or u.type == "farm" or u.type == "dock")


func _on_land(p: Vector3) -> bool:
	return Game.island.height_at(p.x, p.z) > -0.3


func _wall_relevant(w: Unit) -> bool:
	return w.lane == lane and absf(w.lane_s - s) < 4.0


func _rig_event_fallback(ev: String) -> void:
	_on_rig_event(ev)


func _on_rig_event(ev: String) -> void:
	if data.get("ranged", false) and ev == "impact":
		ev = "release"
	if state == S.DEAD or not accept_event(ev):
		return
	match ev:
		"impact":
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
	if _dist_to(target) <= _reach(target) + 0.8:
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
