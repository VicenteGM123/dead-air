class_name BarracksBuilding
extends Building
## Hoplite barracks: keeps a squad of soldiers guarding the area in front of it.

var soldiers: Array = []


func _on_model_changed() -> void:
	if not is_inside_tree():
		return
	call_deferred("_sync_squad")


var _rally := Vector3.INF
var _side := Vector3.RIGHT

## How far behind the lane's wall plot the squad forms up (toward the lighthouse).
const WALL_BACK := 2.5


## Where the squad stands guard: just behind its lane's wall plot, under the tower's cover, so the hoplites hold
## the wall (and spear what attacks it) or, while the plot is empty, the road where the wall would be. Lanes
## without a wall plot keep the road in front of the barracks; plots off the lanes use the model's rally anchor.
func rally_point() -> Vector3:
	if lane < 0 or Game.island == null or not is_inside_tree():
		return anchor("rally", Vector3(0, 0, 4.0))
	if not _rally.is_finite():
		var isl: Island = Game.island
		var s := isl.lane_project(lane, global_position) - 1.0
		var wall_s := _wall_plot_s()
		if wall_s >= 0.0:
			s = wall_s + WALL_BACK
		var p := isl.lane_sample(lane, s)
		var fwd := isl.lane_sample(lane, s + 1.0) - isl.lane_sample(lane, s - 2.0)
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		_side = Vector3(-fwd.z, 0, fwd.x)
		if wall_s < 0.0:
			var to_b := global_position - p
			to_b.y = 0.0
			if to_b.length() > 0.01:
				p += to_b.normalized() * 1.2
		_rally = isl.ground(p)
	return _rally


## Lane distance of this lane's wall plot (built or not), or -1 when the lane has none.
func _wall_plot_s() -> float:
	if Game.main == null or not ("spots" in Game.main):
		return -1.0
	for sp in Game.main.spots:
		if sp.type == "wall" and sp.lane == lane:
			return Game.island.lane_project(lane, sp.global_position)
	return -1.0


## Direction along which the squad spreads out (across the road).
func rally_side() -> Vector3:
	if lane >= 0 and _rally.is_finite():
		return _side
	return global_transform.basis.x.normalized()


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
