class_name Soldier
extends Unit
## Allied hoplite. Guards a post in front of its barracks and engages creatures that come close.

const GUARD_RADIUS := 7.0

var barracks: Node3D = null
var slot := 0
var dmg := 8.0
var speed := 3.6
var target: Unit = null
var attack_cd := 0.0
var _retarget := 0.0
var _vel := Vector3.ZERO
var facing := 0.0
var _dead_t := 0.0


func _ready() -> void:
	team = 0
	radius = 0.42
	display_name = "Hoplita"
	rig = RigHoplite.new(true)
	add_child(rig)
	rig.event.connect(_on_rig_event)
	facing = PI


func apply_stats(hp_v: float, dmg_v: float) -> void:
	max_hp = hp_v
	if alive:
		hp = max_hp
	dmg = dmg_v


func post() -> Vector3:
	if not is_instance_valid(barracks):
		return global_position
	var rp: Vector3 = barracks.rally_point()
	var count: int = maxi(1, barracks.soldiers.size())
	var a := (float(slot) - float(count - 1) * 0.5) * 1.6
	var side: Vector3 = barracks.rally_side() if barracks.has_method("rally_side") else barracks.global_transform.basis.x.normalized()
	return rp + side * a


func revive(at: Vector3) -> void:
	if alive:
		hp = max_hp
		return
	alive = true
	hp = max_hp
	visible = true
	rig.action = ""
	rig.set_dissolve(0.0)
	rig.rotation = Vector3.ZERO
	global_position = Game.island.ground(at)
	Game.register(self, team)


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		if _dead_t > 1.0:
			rig.set_dissolve(clampf((_dead_t - 1.0) / 0.8, 0.0, 1.0))
			if _dead_t > 1.9:
				visible = false
		return
	var smul := tick_status(delta)
	poll_events()
	attack_cd = maxf(0.0, attack_cd - delta)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.3
		_pick_target()
	var goal := post()
	var move := Vector3.ZERO
	if stun > 0.0:
		pass
	elif target and is_instance_valid(target) and target.alive:
		var d := target.global_position - global_position
		d.y = 0.0
		var reach := radius + target.radius + 0.9
		if d.length() > reach:
			move = d.normalized() * speed
		else:
			facing = lerp_angle(facing, Unit.yaw_to(d), 1.0 - exp(-delta * 12.0))
			if attack_cd <= 0.0 and not rig.is_busy():
				attack_cd = 1.0
				rig.play("attack%d" % (randi() % 2 + 1))
				expect_event("impact", 0.38)
	else:
		var d := goal - global_position
		d.y = 0.0
		if d.length() > 0.4:
			move = d.normalized() * speed * clampf(d.length() / 2.0, 0.3, 1.0)
	move *= smul
	_vel = _vel.lerp(move, 1.0 - exp(-delta * 10.0))
	if _vel.length() > 0.3:
		facing = lerp_angle(facing, Unit.yaw_to(_vel), 1.0 - exp(-delta * 10.0))
	var p := global_position + _vel * delta
	p = Separation.apply(self, p, 0)
	p = Obstacles.push_out(p, radius)
	if Game.island.is_walkable(p.x, p.z):
		global_position = Vector3(p.x, Game.island.height_at(p.x, p.z), p.z)
	rig.rotation.y = facing
	rig.set_locomotion(_vel.length(), speed)
	if not Game.is_night() and hp < max_hp:
		heal(delta * 20.0)


func _pick_target() -> void:
	if target and is_instance_valid(target) and target.alive and target.flat_dist(post()) < GUARD_RADIUS + 3.0:
		return
	target = null
	var best_d := GUARD_RADIUS
	var at := post()
	for e in Game.units[1]:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = e.flat_dist(at)
		# Keres fly over the squad: the hoplites only raise their spears at those that swoop in close.
		if e.is_flying and d > 4.5:
			continue
		if d < best_d:
			best_d = d
			target = e


func _rig_event_fallback(ev: String) -> void:
	_on_rig_event(ev)


func _on_rig_event(ev: String) -> void:
	if ev != "impact" or not alive or not accept_event(ev):
		return
	if target and is_instance_valid(target) and target.alive:
		if flat_dist(target.global_position) <= radius + target.radius + 1.4:
			target.take_damage(dmg, self, 0.5, "melee")
			Sfx.play("soldier_hit", global_position, -10.0, randf_range(0.9, 1.15))
			if Game.fx:
				Game.fx.hit_spark(target.global_position + Vector3(0, 1.0, 0), Unit.dir_of_yaw(facing), 0.6)


func _on_hurt(_amount: float, _from: Node3D, _kind: String) -> void:
	if not rig.is_busy():
		rig.play("hit")


func _on_death() -> void:
	_dead_t = 0.0
	rig.play("death")
	Game.unregister(self, team)
	Sfx.play("soldier_hit", global_position, -4.0, 0.7)
