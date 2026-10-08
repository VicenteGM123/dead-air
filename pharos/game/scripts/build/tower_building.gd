class_name TowerBuilding
extends Building
## Archer tower: shoots homing arrows at the nearest creature in range (night only).

var cd := 0.5
var archer: Node3D = null
var _aim_yaw := 0.0


func _on_model_changed() -> void:
	if archer == null:
		archer = ModelsUnits.archer()
		add_child(archer)
	archer.position = anchors.get("archer", Vector3(0, height, 0))


func range_stat() -> float:
	return float(Data.building_level(type, level)["range"]) + (2.0 if Game.has_blessing("artemis") else 0.0)


func rate_stat() -> float:
	return float(Data.building_level(type, level)["rate"]) * (0.8 if Game.has_blessing("artemis") else 1.0)


func dmg_stat() -> float:
	return float(Data.building_level(type, level)["dmg"]) * (1.2 if Game.has_blessing("hephaestus") else 1.0)


func _physics_process(delta: float) -> void:
	if archer:
		archer.visible = alive
	if not alive or Game.phase != Game.Phase.NIGHT:
		return
	cd -= delta
	if cd > 0.0:
		return
	var shots := int(Data.building_level(type, level)["shots"])
	# Creatures still rising from the sea cannot be hurt yet: do not waste arrows on them.
	var targets := Game.query(1, global_position, range_stat(), false).filter(func(u): return u.invuln <= 0.0)
	if targets.is_empty():
		cd = 0.15
		return
	# Nearest first, but Keres (they fly over the walls) go to the front of the queue.
	targets.sort_custom(func(a, b): return _priority(a) < _priority(b))
	cd = rate_stat()
	var muzzle := anchor("muzzle", Vector3(0, height + 1.2, 0))
	# Level 3 always looses two arrows: at two creatures, or both at a lone one.
	for i in shots:
		var t: Unit = targets[i % targets.size()]
		Game.projectiles.arrow(muzzle + Vector3(0, 0.12 * float(i), 0), t, dmg_stat(), self)
	var d: Vector3 = targets[0].global_position - global_position
	_aim_yaw = Unit.yaw_to(d)
	if archer:
		archer.rotation.y = _aim_yaw
		if archer.has_method("play"):
			archer.call("play", "shoot")
	Sfx.play("arrow_shoot", muzzle, -8.0, randf_range(0.9, 1.1))


func _priority(u: Unit) -> float:
	return u.flat_dist(global_position) - (6.0 if u.is_flying else 0.0)
