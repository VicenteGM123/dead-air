class_name WallBuilding
extends Building
## Wall across a lane. Walking creatures on that lane must destroy it to pass.

static var by_lane := {}


static func clear_registry() -> void:
	by_lane.clear()


func _ready() -> void:
	super()
	if lane >= 0:
		lane_s = Game.island.lane_project(lane, global_position)
		if not by_lane.has(lane):
			by_lane[lane] = []
		by_lane[lane].append(self)


func _exit_tree() -> void:
	super()
	if by_lane.has(lane):
		by_lane[lane].erase(self)


## First living wall on `ln` whose position lies in (s_from, s_to].
static func blocking(ln: int, s_from: float, s_to: float) -> WallBuilding:
	if not by_lane.has(ln):
		return null
	var best: WallBuilding = null
	for w in by_lane[ln]:
		if not is_instance_valid(w) or not w.alive:
			continue
		if w.lane_s > s_from and w.lane_s <= s_to:
			if best == null or w.lane_s < best.lane_s:
				best = w
	return best
