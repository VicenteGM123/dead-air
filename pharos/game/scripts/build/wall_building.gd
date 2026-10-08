class_name WallBuilding
extends Building
## Wall across a lane. Walking creatures on that lane must destroy it to pass.

## Half the length of the wall's line (the model is 8 m long, end piers included).
const HALF := 3.6

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


## A wall is a line, not a disc: a chain of small circles along it (nudged to the inner side, where the palisade
## has its props) keeps Fanós, the hoplites and the walkers on their own side until it falls.
func _add_obstacles() -> void:
	var n := 8
	for i in n:
		var x := lerpf(-HALF + 0.1, HALF - 0.1, float(i) / float(n - 1))
		Obstacles.add(global_transform * Vector3(x, 0, 0.2), 0.65, self)


## Distance from `p` to the wall's line on the ground: creatures strike it anywhere along its length.
func line_dist(p: Vector3) -> float:
	var l := global_transform.affine_inverse() * p
	return Vector2(maxf(absf(l.x) - HALF, 0.0), l.z).length()


## The point of the wall's line nearest to `p`.
func closest_point(p: Vector3) -> Vector3:
	var l := global_transform.affine_inverse() * p
	return global_transform * Vector3(clampf(l.x, -HALF, HALF), 0.0, 0.0)


## Which side of the wall `p` is on: > 0 inside (toward the lighthouse), < 0 outside (toward the sea).
func side_of(p: Vector3) -> float:
	return (global_transform.affine_inverse() * p).z


## A living wall on `ln` whose outer face `p` stands within `dist` of (seen from the sea side), or null.
static func facing(ln: int, p: Vector3, dist: float) -> WallBuilding:
	if not by_lane.has(ln):
		return null
	for w in by_lane[ln]:
		if is_instance_valid(w) and w.alive and w.side_of(p) < 0.0 and w.line_dist(p) <= dist:
			return w
	return null


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
