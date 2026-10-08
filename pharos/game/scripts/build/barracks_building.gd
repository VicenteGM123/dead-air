class_name BarracksBuilding
extends Building
## Hoplite barracks: keeps a squad of soldiers guarding the area in front of it.

var soldiers: Array = []


func _on_model_changed() -> void:
	if not is_inside_tree():
		return
	call_deferred("_sync_squad")


func rally_point() -> Vector3:
	return anchor("rally", Vector3(0, 0, 4.0))


func _sync_squad() -> void:
	var lv := Data.building_level(type, level)
	var n := int(lv["soldiers"])
	while soldiers.size() < n:
		var s := Soldier.new()
		s.barracks = self
		s.slot = soldiers.size()
		Game.main.units_root.add_child(s)
		s.global_position = Game.island.ground(rally_point() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
		soldiers.append(s)
	for s in soldiers:
		s.apply_stats(float(lv["s_hp"]), float(lv["s_dmg"]))


## Dawn: dead soldiers come back.
func revive_squad() -> void:
	for s in soldiers:
		if is_instance_valid(s):
			s.revive(rally_point())


func _on_restored() -> void:
	revive_squad()
