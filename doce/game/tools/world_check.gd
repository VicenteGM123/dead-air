extends "res://scripts/main.gd"
## World API check (integration test of scripts/world/world.gd against docs/ARCHITECTURE.md section 5.5), run in
## the real game scene (hero, camera, physics):
##   godot --headless --path . res://tools/world_check.tscn --quit-after 20000 -- noui=1
## Prints "WORLDCHECK PASS|FAIL|INFO <check> <details>" lines and "WORLDCHECK SUMMARY fails=N".
##
## Checks: height_at / ground / normal_at / is_water consistent (and with the terrain collision); player_start on
## the pier facing inland; altars on the ground on high viewpoints; every spawn group on walkable land with room
## to fight; cave() complete, pillars inside the arena, both entrances reachable on foot; every ring reachable (a
## standing spot within 18 m with a line of sight) and the broken passage NOT crossable on foot (nor by swimming
## round); boat_dock on the pier; bounds sane.
##
## Reachability is a flood fill over a 1 m grid of the terrain: a cell is walkable when its slope is under the
## hero's 46 deg, nothing solid (layer 1, terrain excluded) stands in a 0.3 m cylinder from 0.45 to 1.65 m above
## it, and its neighbour is within 1 m of height; water deeper than 1.3 m is swum (any slope), and the swimmer can
## climb out where the next cell is walkable and at most 1 m above the water (or the sea floor it stands on).

const RING_RANGE := 18.0
const SLOPE_Y := 0.69 # cos(46 deg)
const STEP_H := 1.0
const SWIM_DEPTH := 1.3

var fails := 0
var _n := 0
var _ext := 0.0
var _h := PackedFloat32Array()
var _ny := PackedFloat32Array()
var _blocked := PackedByteArray()


func _wants_title() -> bool:
	return false


func _ready() -> void:
	super._ready()
	hero.input_enabled = false
	_run.call_deferred()


func _out(kind: String, what: String, info: String = "") -> void:
	print("WORLDCHECK %s %s %s" % [kind, what, info])


func _check(what: String, ok: bool, info: String = "") -> void:
	_out("PASS" if ok else "FAIL", what, info)
	if not ok:
		fails += 1


func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


func _ray(a: Vector3, b: Vector3, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = exclude
	return _space().intersect_ray(q)


func _run() -> void:
	for i in 4:
		await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	_consistency()
	_start_and_dock()
	_bounds()
	_build_grid()
	_out("INFO", "grid", "%d x %d cells of 1 m, blocked/walkable flags in %d ms" % [_n, _n, Time.get_ticks_msec() - t0])
	var south := _cell_of(world.ground(Vector3(14.0, 0.0, 100.0))) # the beach end of the pier
	var places: Dictionary = world.call("places") if world.has_method("places") else {}
	var north_p: Vector3 = places.get("passage_north", Vector3.INF)
	var walk_s := _flood(south, false)
	var swim_s := _flood(south, true)
	var walk_n := _flood(_cell_of(north_p), false) if north_p.is_finite() else PackedByteArray()
	_passage(walk_s, swim_s, north_p, places)
	_altars(walk_s, walk_n)
	_spawns(walk_s, walk_n)
	_cave(walk_n)
	_rings(walk_s, walk_n)
	if String(Game.arg("map", "")) != "":
		_save_map(String(Game.arg("map")), walk_s, walk_n)
	print("WORLDCHECK SUMMARY fails=%d (%d ms)" % [fails, Time.get_ticks_msec() - t0])
	get_tree().quit()


# --- 1. the height queries agree with each other and with the collision -------------------------------------

func _consistency() -> void:
	var b: Rect2 = world.bounds()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var body: Object = world.get("terrain_body")
	var g_err := 0.0
	var w_bad := 0
	var r_err := 0.0
	var r_n := 0
	var n_max := 0.0
	var n_sum := 0.0
	var n_cnt := 0
	for i in 3000:
		var x := rng.randf_range(b.position.x + 1.0, b.end.x - 1.0)
		var z := rng.randf_range(b.position.y + 1.0, b.end.y - 1.0)
		var h: float = world.height_at(x, z)
		var g: Vector3 = world.ground(Vector3(x, 37.0, z))
		g_err = maxf(g_err, absf(g.y - h) + absf(g.x - x) + absf(g.z - z))
		if bool(world.is_water(x, z)) != (h < float(world.sea_level)):
			w_bad += 1
		# smooth normal vs the ground's actual slope (finite differences over 0.5 m)
		var e := 0.5
		var dx: float = world.height_at(x + e, z) - world.height_at(x - e, z)
		var dz: float = world.height_at(x, z + e) - world.height_at(x, z - e)
		var fn := Vector3(-dx, 2.0 * e, -dz).normalized()
		var nn: Vector3 = world.normal_at(x, z)
		var ang := rad_to_deg(fn.angle_to(nn))
		if h > 0.0:
			n_max = maxf(n_max, ang)
			n_sum += ang
			n_cnt += 1
		if i < 600:
			var hit := _ray(Vector3(x, 300.0, z), Vector3(x, -60.0, z))
			if not hit.is_empty() and hit["collider"] == body:
				r_err = maxf(r_err, absf(float(hit["position"].y) - h))
				r_n += 1
	_check("ground(p) == (p.x, height_at, p.z)", g_err < 0.001, "max err %.4f m over 3000 samples" % g_err)
	_check("is_water == height_at < sea_level", w_bad == 0, "%d mismatches" % w_bad)
	_check("terrain collision == height_at", r_n > 100 and r_err < 0.02, "max err %.3f m over %d rays" % [r_err, r_n])
	_check("normal_at follows the slope", n_cnt > 0 and n_sum / n_cnt < 8.0, "mean %.1f deg, max %.1f deg from the finite-difference normal (land)" % [n_sum / maxf(1.0, n_cnt), n_max])


# --- 2. start on the pier facing inland; the boat dock on the pier --------------------------------------------

func _deck_under(p: Vector3) -> Dictionary:
	var body: Object = world.get("terrain_body")
	var hit := _ray(p + Vector3(0, 1.5, 0), p - Vector3(0, 3.0, 0))
	if hit.is_empty():
		return {}
	return {"y": float(hit["position"].y), "terrain": hit["collider"] == body, "name": String((hit["collider"] as Node).name)}


func _start_and_dock() -> void:
	var xf: Transform3D = world.player_start()
	var p := xf.origin
	var d := _deck_under(p)
	_check("player_start stands on the pier deck", not d.is_empty() and not bool(d["terrain"]) and absf(float(d["y"]) - p.y) < 0.25 and p.y > float(world.sea_level),
		"start %s, solid under it: %s" % [str(p), str(d)])
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var land_at := -1.0
	for k in 80:
		var q := p + fwd * float(k)
		if float(world.height_at(q.x, q.z)) > 0.3:
			land_at = float(k)
			break
	var back_land := false
	for k in range(1, 40):
		var q := p - fwd * float(k)
		if float(world.height_at(q.x, q.z)) > 0.3:
			back_land = true
	_check("player_start faces inland", land_at >= 0.0 and land_at < 60.0 and not back_land,
		"facing %s: land %.0f m ahead, open sea behind: %s" % [str(fwd.snapped(Vector3.ONE * 0.01)), land_at, str(not back_land)])
	var dock: Vector3 = world.boat_dock()
	var dd := _deck_under(dock)
	_check("boat_dock is on the pier deck", not dd.is_empty() and not bool(dd["terrain"]) and absf(float(dd["y"]) - dock.y) < 0.25,
		"dock %s, solid under it: %s" % [str(dock), str(dd)])


func _bounds() -> void:
	var b: Rect2 = world.bounds()
	var land_out := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var x := -260.0
	while x <= 260.0:
		var z := -260.0
		while z <= 260.0:
			if float(world.height_at(x, z)) > 0.0:
				lo = Vector2(minf(lo.x, x), minf(lo.y, z))
				hi = Vector2(maxf(hi.x, x), maxf(hi.y, z))
				if not b.has_point(Vector2(x, z)):
					land_out += 1
			z += 2.0
		x += 2.0
	var edge_h: float = world.height_at(b.position.x + 0.5, b.position.y + 0.5)
	_check("bounds() holds all the land", land_out == 0 and b.size.x > 100.0 and b.size.y > 100.0,
		"bounds %s, land spans x %.0f..%.0f z %.0f..%.0f, land outside %d, corner height %.1f" % [str(b), lo.x, hi.x, lo.y, hi.y, land_out, edge_h])


# --- reachability grid -----------------------------------------------------------------------------------------

func _build_grid() -> void:
	var b: Rect2 = world.bounds()
	_ext = b.size.x * 0.5
	_n = int(b.size.x) + 1
	_h.resize(_n * _n)
	_ny.resize(_n * _n)
	_blocked.resize(_n * _n)
	var body: Object = world.get("terrain_body")
	var ex: Array[RID] = []
	if body != null:
		ex.append((body as CollisionObject3D).get_rid())
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = ex
	var sp := _space()
	for iz in _n:
		for ix in _n:
			var i := iz * _n + ix
			var x := float(ix) - _ext
			var z := float(iz) - _ext
			var h: float = world.height_at(x, z)
			_h[i] = h
			_ny[i] = (world.normal_at(x, z) as Vector3).y
			_blocked[i] = 0
			if h > -SWIM_DEPTH - 0.4:
				q.transform = Transform3D(Basis.IDENTITY, Vector3(x, maxf(h, -0.2) + 1.05, z))
				if not sp.intersect_shape(q, 1).is_empty():
					_blocked[i] = 1


func _cell_of(p: Vector3) -> int:
	var ix := clampi(int(round(p.x + _ext)), 0, _n - 1)
	var iz := clampi(int(round(p.z + _ext)), 0, _n - 1)
	return iz * _n + ix


func _pos_of(i: int) -> Vector3:
	var x := float(i % _n) - _ext
	var z := float(i / _n) - _ext
	return Vector3(x, _h[i], z)


func _swim(i: int) -> bool:
	return _h[i] < -SWIM_DEPTH


func _walk(i: int) -> bool:
	return _blocked[i] == 0 and _ny[i] >= SLOPE_Y and not _swim(i)


var _parent := PackedInt32Array()


## Flood fill from cell `s`: 1 for every cell reached (walking; swimming too when `swim`). The last fill's
## parents are kept in _parent (for _path_to()).
func _flood(s: int, swim: bool) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(_n * _n)
	_parent.resize(_n * _n)
	_parent.fill(-1)
	if not _walk(s) and not (swim and _swim(s)):
		# start on the nearest walkable cell within 3 m
		var best := -1
		var bd := INF
		var sx := s % _n
		var sz := s / _n
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var x := sx + dx
				var z := sz + dz
				if x < 0 or z < 0 or x >= _n or z >= _n:
					continue
				var j := z * _n + x
				if _walk(j) and dx * dx + dz * dz < bd:
					bd = dx * dx + dz * dz
					best = j
		if best < 0:
			return seen
		s = best
	var queue := PackedInt32Array([s])
	seen[s] = 1
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var i := queue[head]
		head += 1
		var ix := i % _n
		var iz := i / _n
		var from_swim := _swim(i)
		for d: Vector2i in dirs:
			var jx := ix + d.x
			var jz := iz + d.y
			if jx < 0 or jz < 0 or jx >= _n or jz >= _n:
				continue
			var j := jz * _n + jx
			if seen[j] == 1:
				continue
			var ok := false
			if _swim(j):
				ok = swim
			elif _walk(j):
				var from_h := maxf(_h[i], -SWIM_DEPTH) if from_swim else _h[i]
				ok = absf(_h[j] - from_h) <= STEP_H
			if ok:
				seen[j] = 1
				_parent[j] = i
				queue.append(j)
	return seen


## The route the last flood took to the cell nearest `p` (for a failed "not reachable" check): where it climbs.
func _path_to(reach: PackedByteArray, p: Vector3) -> String:
	var c := _cell_of(p)
	var best := -1
	var bd := INF
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var j := c + dz * _n + dx
			if j >= 0 and j < _n * _n and reach[j] == 1 and dx * dx + dz * dz < bd:
				bd = dx * dx + dz * dz
				best = j
	if best < 0:
		return "no route"
	var pts: Array[Vector3] = []
	var j := best
	var guard := 0
	while j >= 0 and guard < 200000:
		pts.append(_pos_of(j))
		j = _parent[j]
		guard += 1
	pts.reverse()
	# report the steepest stretches of the route (where it climbs from the forest to the upper level)
	var out := "route %d cells;" % pts.size()
	var k := 0
	while k < pts.size():
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[mini(k + 8, pts.size() - 1)]
		var rise := b.y - a.y
		if absf(rise) > 3.0:
			out += " %s->%s (%+.1f m over 8 m, slope_y %.2f)" % [str(Vector2(a.x, a.z)), str(Vector2(b.x, b.z)), rise, _ny[_cell_of(a)]]
			k += 8
		else:
			k += 1
	return out


func _reached_near(reach: PackedByteArray, p: Vector3, r: float) -> bool:
	if reach.is_empty():
		return false
	var c := _cell_of(p)
	var cx := c % _n
	var cz := c / _n
	var ri := int(ceil(r))
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dz * dz > r * r:
				continue
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= _n or z >= _n:
				continue
			if reach[z * _n + x] == 1:
				return true
	return false


func _count(reach: PackedByteArray) -> int:
	var n := 0
	for v in reach:
		n += v
	return n


# --- 3. the passage: not crossable on foot (nor swimming round) ---------------------------------------------------

func _passage(walk_s: PackedByteArray, swim_s: PackedByteArray, north_p: Vector3, places: Dictionary) -> void:
	_out("INFO", "reach from the village", "%d m2 on foot, %d m2 with swimming" % [_count(walk_s), _count(swim_s)])
	if not north_p.is_finite():
		_check("places() has passage_north", false)
		return
	var targets := {"passage north rim": north_p}
	for k in ["cave_a", "cave_b", "altar_2"]:
		if places.has(k):
			targets[k] = places[k]
	var dbg := _flood(_cell_of(world.ground(Vector3(14.0, 0.0, 100.0))), false)
	for k in targets:
		var p: Vector3 = targets[k]
		_check("%s NOT reachable on foot from the village" % k, not _reached_near(walk_s, p, 2.0), str(p.snapped(Vector3.ONE * 0.1)))
		if _reached_near(dbg, p, 2.0) and k == "passage north rim":
			_out("INFO", "on-foot route to the north rim", _path_to(dbg, p))
		_check("%s NOT reachable by swimming round" % k, not _reached_near(swim_s, p, 2.0), str(p.snapped(Vector3.ONE * 0.1)))
	var south_p: Vector3 = places.get("passage_south", Vector3.INF)
	if south_p.is_finite():
		_check("passage south rim reachable on foot from the village", _reached_near(walk_s, south_p, 2.5), str(south_p.snapped(Vector3.ONE * 0.1)))


# --- 4. altars ----------------------------------------------------------------------------------------------------

func _altars(walk_s: PackedByteArray, walk_n: PackedByteArray) -> void:
	var list: Array = world.altars()
	_check("altars() returns Altar nodes", list.size() >= 2 and list.all(func(a) -> bool: return a is Node3D and a.has_method("respawn_transform")), "%d altars" % list.size())
	for a: Node3D in list:
		var p := a.global_position
		var worst := 0.0
		for o in [Vector3(0.8, 0, 0.6), Vector3(-0.8, 0, 0.6), Vector3(0.8, 0, -0.6), Vector3(-0.8, 0, -0.6), Vector3.ZERO]:
			var q: Vector3 = a.global_transform * o
			worst = maxf(worst, absf(float(world.height_at(q.x, q.z)) - p.y))
		var mean := 0.0
		var cnt := 0
		var r := 8.0
		while r <= 40.0:
			for k in 16:
				var ang := TAU * k / 16.0
				mean += float(world.height_at(p.x + cos(ang) * r, p.z + sin(ang) * r))
				cnt += 1
			r += 8.0
		mean /= cnt
		var title: String = String(a.get("title")) if "title" in a else String(a.name)
		_check("altar '%s' sits on the ground" % title, worst < 0.3, "pos %s, footprint off the ground by up to %.2f m" % [str(p.snapped(Vector3.ONE * 0.1)), worst])
		_check("altar '%s' is a high viewpoint" % title, p.y >= 10.0 and p.y - mean >= 1.0, "%.1f m above the sea, %.1f m above the mean ground within 40 m" % [p.y, p.y - mean])
		_check("altar '%s' reachable on foot" % title, _reached_near(walk_s, p, 3.0) or _reached_near(walk_n, p, 3.0),
			"from the village: %s, from the north rim: %s" % [_reached_near(walk_s, p, 3.0), _reached_near(walk_n, p, 3.0)])
		var rx: Transform3D = a.call("respawn_transform")
		_check("altar '%s' respawn point on the ground" % title, absf(rx.origin.y - float(world.height_at(rx.origin.x, rx.origin.z))) < 0.3 and not bool(world.is_water(rx.origin.x, rx.origin.z)), str(rx.origin.snapped(Vector3.ONE * 0.1)))


# --- 5. spawn groups ----------------------------------------------------------------------------------------------

func _spawns(walk_s: PackedByteArray, walk_n: PackedByteArray) -> void:
	var groups: Array = world.spawn_groups()
	_check("spawn_groups() has wolves and boars", groups.any(func(g) -> bool: return g["kind"] == &"wolf") and groups.any(func(g) -> bool: return g["kind"] == &"boar"), "%d groups" % groups.size())
	for g: Dictionary in groups:
		var c: Vector3 = g["center"]
		var r: float = g["radius"]
		var reach := _flood(_cell_of(c), false)
		var inside := 0
		var good := 0
		var cc := _cell_of(c)
		var ri := int(ceil(r))
		for dz in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var x := cc % _n + dx
				var z := cc / _n + dz
				if x < 0 or z < 0 or x >= _n or z >= _n:
					continue
				inside += 1
				if reach[z * _n + x] == 1:
					good += 1
		var frac := float(good) / maxf(1.0, float(inside))
		var on_land: bool = float(world.height_at(c.x, c.z)) > 0.3 and _walk(cc)
		var from := "village" if _reached_near(walk_s, c, 2.0) else ("north rim" if _reached_near(walk_n, c, 2.0) else "NOWHERE")
		_check("spawn %s x%d at %s r %.0f: walkable land with room" % [g["kind"], g["count"], str(Vector2(c.x, c.z).snapped(Vector2.ONE)), r],
			on_land and frac >= 0.7 and good >= 120 and from != "NOWHERE", "%.0f %% of the circle walkable and connected (%d m2), reached from the %s" % [frac * 100.0, good, from])


# --- 6. cave ------------------------------------------------------------------------------------------------------

func _cave(walk_n: PackedByteArray) -> void:
	var c: Dictionary = world.cave()
	var keys := ["entrance_a", "entrance_b", "boulder", "arena_center", "pillars", "lion_spawn"]
	var missing := keys.filter(func(k) -> bool: return not c.has(k))
	_check("cave() has every key", missing.is_empty(), "missing %s" % str(missing))
	if not missing.is_empty():
		return
	var bo: Node = c["boulder"]
	_check("cave().boulder is the real Boulder", bo != null and bo.get_script() != null and (bo.get_script() as Script).resource_path == "res://scripts/props/boulder.gd" and bo.is_in_group("chain_anchor"),
		"%s" % (str(bo.get_script().resource_path) if bo and bo.get_script() else "none"))
	var ac: Vector3 = c["arena_center"]
	var ar := float(c.get("arena_radius", 13.5))
	var pil: Array = c["pillars"]
	var worst := 0.0
	for p: Vector3 in pil:
		worst = maxf(worst, Vector2(p.x - ac.x, p.z - ac.z).length())
	_check("pillars inside the arena", pil.size() >= 3 and worst < ar - 1.0, "%d pillars, farthest %.1f m from the centre (floor radius %.1f)" % [pil.size(), worst, ar])
	var ls: Vector3 = c["lion_spawn"]
	var near_p := INF
	for p: Vector3 in pil:
		near_p = minf(near_p, Vector2(p.x - ls.x, p.z - ls.z).length())
	_check("lion_spawn on the arena floor, clear of the pillars", Vector2(ls.x - ac.x, ls.z - ac.z).length() < ar - 2.0 and near_p > 2.5 and absf(ls.y - float(world.height_at(ls.x, ls.z))) < 0.3,
		"%.1f m from the centre, %.1f m from the nearest pillar" % [Vector2(ls.x - ac.x, ls.z - ac.z).length(), near_p])
	# The lid over the floor (rays a little off the exact centre, where 48 triangles meet in one vertex).
	var lid_hits := 0
	var lid_lo := INF
	for rr in [1.5, 5.0, 9.0]:
		for k in 8:
			var o := Vector3(cos(TAU * k / 8.0 + 0.064) * rr, 1.0, sin(TAU * k / 8.0 + 0.064) * rr) # off the 7.5 deg seams
			var lid := _ray(ac + o, ac + o + Vector3(0, 40.0, 0))
			if not lid.is_empty():
				lid_hits += 1
				lid_lo = minf(lid_lo, float(lid["position"].y) - ac.y)
	_check("the arena has a roof (cave lid) with collision", lid_hits == 24, "%d / 24 rays up hit it, lowest %.1f m above the floor" % [lid_hits, lid_lo])
	for k in ["entrance_a", "entrance_b"]:
		var e: Vector3 = c[k]
		_check("cave %s reachable on foot from the passage's north rim" % k, _reached_near(walk_n, e, 2.0), str(e.snapped(Vector3.ONE * 0.1)))
	var arena_reach := _flood(_cell_of(ac), false)
	_check("arena floor connected to both mouths on foot", _reached_near(arena_reach, c["entrance_a"], 2.0) and _reached_near(arena_reach, c["entrance_b"], 2.0), "arena flood %d m2" % _count(arena_reach))
	var bp := (bo as Node3D).global_position
	_check("boulder rests on the ground by mouth B", absf(bp.y - float(world.height_at(bp.x, bp.z))) < 0.4 and Vector2(bp.x - (c["entrance_b"] as Vector3).x, bp.z - (c["entrance_b"] as Vector3).z).length() < 12.0,
		"%s, %.1f m from entrance_b" % [str(bp.snapped(Vector3.ONE * 0.1)), Vector2(bp.x - (c["entrance_b"] as Vector3).x, bp.z - (c["entrance_b"] as Vector3).z).length()])


# --- 7. rings -----------------------------------------------------------------------------------------------------

## True when the spear thrown from `from` can bite ring `r`: the ray reaches its chain point (or the ring's own
## stone within 0.6 m of it) without hitting anything else.
func _sees(from: Vector3, r: Node3D) -> bool:
	var cp: Vector3 = r.call("chain_point")
	var hit := _ray(from, cp)
	if hit.is_empty():
		return true
	return hit["collider"] == r and (hit["position"] as Vector3).distance_to(cp) < 0.6


## Nearest standing spot (cells of `reach`, chest at 1.4 m) within RING_RANGE that sees ring `r`: [dist, spot].
func _best_spot(reach: PackedByteArray, r: Node3D) -> Array:
	if reach.is_empty():
		return [INF, Vector3.INF]
	var cp: Vector3 = r.call("chain_point")
	var cc := _cell_of(cp)
	var ri := int(RING_RANGE) + 1
	var best := INF
	var spot := Vector3.INF
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := cc % _n + dx
			var z := cc / _n + dz
			if x < 0 or z < 0 or x >= _n or z >= _n or reach[z * _n + x] == 0:
				continue
			var chest := _pos_of(z * _n + x) + Vector3(0, 1.4, 0)
			var d := chest.distance_to(cp)
			if d > RING_RANGE or d >= best:
				continue
			if _sees(chest, r):
				best = d
				spot = chest
	return [best, spot]


## Standing spots on top of the sea stack (found with rays: it is a prop, not terrain).
func _stack_spots(stack_ring: Node3D) -> Array:
	var out: Array = []
	var c := stack_ring.global_position
	for rr in [1.2, 2.0, 2.6]:
		for k in 12:
			var a := TAU * k / 12.0
			var q := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			var hit := _ray(q + Vector3(0, 4.0, 0), q - Vector3(0, 6.0, 0))
			if not hit.is_empty() and absf(float(hit["position"].y) - c.y) < 0.6 and (hit["normal"] as Vector3).y > 0.8:
				out.append((hit["position"] as Vector3) + Vector3(0, 1.4, 0))
	return out


func _rings(walk_s: PackedByteArray, walk_n: PackedByteArray) -> void:
	var list: Array = world.anchors()
	_check("anchors() are ChainRing nodes in group chain_anchor", list.size() >= 2 and list.all(func(r) -> bool: return r is ChainRing and r.is_in_group("chain_anchor") and String(r.call("chain_kind")) == "ring"), "%d rings" % list.size())
	for r: Node3D in list:
		var a := _best_spot(walk_s, r)
		var b := _best_spot(walk_n, r)
		_check("ring %s reachable (a standing spot within %.0f m that sees it)" % [r.name, RING_RANGE], a[0] < INF or b[0] < INF,
			"chain point %s: village side %s, north side %s" % [str((r.call("chain_point") as Vector3).snapped(Vector3.ONE * 0.1)),
			("%.1f m" % a[0]) if a[0] < INF else "none", ("%.1f m" % b[0]) if b[0] < INF else "none"])
	var places: Dictionary = world.call("places") if world.has_method("places") else {}
	if list.size() != 3 or not places.has("passage_south") or not places.has("passage_north"):
		return
	# The crossing: south rim -> stack -> north rim, and back.
	var south: Node3D = null
	var north: Node3D = null
	var bs := INF
	var bn := INF
	for r: Node3D in list:
		var ds := r.global_position.distance_to(places["passage_south"])
		var dn := r.global_position.distance_to(places["passage_north"])
		if ds < bs:
			bs = ds
			south = r
		if dn < bn:
			bn = dn
			north = r
	var stack: Node3D = null
	for r: Node3D in list:
		if r != south and r != north:
			stack = r
	if stack == null:
		return
	var top := _stack_spots(stack)
	_out("INFO", "stack top", "%d standing spots found by rays round %s" % [top.size(), str(stack.global_position.snapped(Vector3.ONE * 0.1))])
	var legs := [["south rim -> stack ring", _best_spot(walk_s, stack)[0]],
		["stack top -> north ring", _best_from(top, north)]]
	for l in legs:
		_check("passage leg %s" % l[0], float(l[1]) < RING_RANGE, ("%.1f m" % float(l[1])) if float(l[1]) < INF else "no spot sees the ring")
	# The way back is not required (the hero can drop off the escarpment into the forest): reported only.
	var back := [["north rim -> stack ring", _best_spot(walk_n, stack)[0]], ["stack top -> south ring", _best_from(top, south)]]
	for l in back:
		_out("INFO", "way back by the rings: %s" % l[0], ("%.1f m" % float(l[1])) if float(l[1]) < INF else "no spot sees the ring (its face turns away)")
	var drops := 0
	for i in walk_n.size():
		if walk_n[i] == 0:
			continue
		var found := false
		for dir in [1, -1, _n, -_n]:
			for step in range(1, 9):
				var j: int = i + int(dir) * step
				if j < 0 or j >= walk_s.size():
					break
				if walk_s[j] == 1:
					if _h[i] - _h[j] > STEP_H:
						found = true
					break
			if found:
				break
		if found:
			drops += 1
	_check("the north side has a way back down (a drop into the village side)", drops > 0, "%d edge cells of the north side drop (over at most 8 m of cliff) onto walkable village-side ground" % drops)


func _best_from(spots: Array, r: Node3D) -> float:
	var cp: Vector3 = r.call("chain_point")
	var best := INF
	for s: Vector3 in spots:
		var d := s.distance_to(cp)
		if d <= RING_RANGE and d < best and _sees(s, r):
			best = d
	return best


## Debug map (map=<file.png>, 1 px = 1 m, north up): deep water blue, shallow water cyan, too steep brown, blocked by
## a prop black, walkable reached on foot from the village green, from the passage's north rim orange, from both
## red (a leak), walkable but unreached light grey.
func _save_map(path: String, walk_s: PackedByteArray, walk_n: PackedByteArray) -> void:
	var img := Image.create(_n, _n, false, Image.FORMAT_RGB8)
	for iz in _n:
		for ix in _n:
			var i := iz * _n + ix
			var c := Color(0.85, 0.85, 0.85)
			if _h[i] < -SWIM_DEPTH:
				c = Color(0.15, 0.3, 0.7)
			elif _h[i] < 0.0:
				c = Color(0.4, 0.75, 0.85)
			elif _blocked[i] == 1:
				c = Color(0.05, 0.05, 0.05)
			elif _ny[i] < SLOPE_Y:
				c = Color(0.45, 0.3, 0.2)
			var a := walk_s[i] == 1
			var b := not walk_n.is_empty() and walk_n[i] == 1
			if a and b:
				c = Color(0.9, 0.1, 0.1)
			elif a:
				c = Color(0.3, 0.75, 0.3)
			elif b:
				c = Color(0.95, 0.6, 0.15)
			var shade := clampf(0.75 + _h[i] / 120.0, 0.6, 1.1) if _h[i] > 0.0 else 1.0
			img.set_pixel(ix, iz, Color(c.r * shade, c.g * shade, c.b * shade))
	img.save_png(path)
	_out("INFO", "map", path)
