class_name Props
extends Node3D
## Scatters the island's vegetation, rocks and ruins. Each model variant is one MultiMesh (one draw call).

var island: Island
var rng := RandomNumberGenerator.new()
var _batches := {} # key -> {mesh, material, xforms: Array[Transform3D]}
var _nature: Script
var _methods := {}
var _reserved: Array = [] # [Vector2 centre, radius]


func build(isl: Island, seed_value: int = 99) -> void:
	island = isl
	rng.seed = seed_value
	_nature = load("res://scripts/gfx/models_nature.gd")
	for m in _nature.get_script_method_list():
		_methods[m["name"]] = true
	_reserve_spots()
	_ruins()
	_cypress_avenues()
	_cluster("olive_tree", 4, 8, 4, 9, _grass_ok, 3.4, 0.4, 0.85, 1.2)
	_cluster("cypress", 3, 7, 2, 4, _cypress_ok, 2.4, 0.35, 0.85, 1.25)
	_scatter("stone_pine", 2, 7, _hill_ok, 0.9, 1.15, 9.0, 0.45)
	_cluster("bush", 4, 26, 2, 5, _bush_ok, 1.5, 0.0, 0.7, 1.3)
	_scatter("rock_large", 3, 40, _cliff_ok, 0.8, 1.5, 3.0, 1.0)
	_cluster("rock_small", 3, 22, 2, 4, _rocky_ok, 1.2, 0.0, 0.6, 1.4)
	_scatter("beach_rock", 2, 20, _beach_ok, 0.7, 1.3, 2.4, 0.0)
	_scatter("driftwood", 2, 9, _beach_ok, 0.9, 1.2, 3.0, 0.0)
	# Meadows: flowers grow in patches, not everywhere.
	_cluster("flowers_lavender", 2, 7, 4, 8, _flower_ok, 1.1, 0.0, 0.8, 1.2)
	_cluster("flowers_poppy", 2, 8, 5, 10, _flower_ok, 1.0, 0.0, 0.8, 1.2)
	_cluster("flowers_daisy", 2, 6, 4, 8, _flower_ok, 1.0, 0.0, 0.8, 1.2)
	_scatter("grass_tuft", 3, 220, _grass_ok, 0.7, 1.3, 0.6, 0.0)
	_place_beached_boats()
	_commit()


func _reserve_spots() -> void:
	for sp in island.spots:
		var p: Vector3 = sp["pos"]
		var r := 4.6
		match sp["type"]:
			"pharos":
				r = 12.0
			"farm":
				r = 7.0
			"wall":
				r = 5.0
			"dock":
				r = 6.0
			"barracks":
				r = 6.5
		_reserved.append([Vector2(p.x, p.z), r])
	_reserved.append([Vector2(-4.5, 6.0), 2.0]) # night horn


func _free_spot(x: float, z: float, extra: float = 0.0) -> bool:
	for r in _reserved:
		if Vector2(x, z).distance_to(r[0]) < r[1] + extra:
			return false
	return true


func _lane_clear(x: float, z: float, margin: float) -> bool:
	# lane_at is a mask; sample around for clearance.
	if island.lane_at(x, z) > 0.0:
		return false
	for o in [Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
		if island.lane_at(x + o.x, z + o.y) > 0.0:
			return false
	return true


# --- placement rules ---------------------------------------------------------------------------------------

func _slope(x: float, z: float) -> float:
	return 1.0 - island.normal_at(x, z).y


func _grass_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	return h > 1.3 and _slope(x, z) < 0.22 and _free_spot(x, z) and _lane_clear(x, z, 2.8)


func _cypress_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	if h < 1.2 or _slope(x, z) > 0.25 or not _free_spot(x, z) or not _lane_clear(x, z, 2.6):
		return false
	# Cypresses like to line paths and frame the village.
	return _lane_clear(x, z, 2.6) and not _lane_clear(x, z, 7.0) or rng.randf() < 0.35


func _hill_ok(x: float, z: float) -> bool:
	return island.height_at(x, z) > 2.4 and _slope(x, z) < 0.2 and _free_spot(x, z, 2.0) and _lane_clear(x, z, 4.0)


func _bush_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	return h > 0.9 and _slope(x, z) < 0.35 and _free_spot(x, z) and _lane_clear(x, z, 2.0)


func _cliff_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	var ang := Island.angle_of(x, z)
	return h > -0.6 and h < 3.0 and island.beach_weight(ang) < 0.2 and _slope(x, z) > 0.18 and _free_spot(x, z) and _lane_clear(x, z, 3.0)


func _rocky_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	return h > 0.2 and (_slope(x, z) > 0.15 or rng.randf() < 0.25) and _free_spot(x, z) and _lane_clear(x, z, 2.0)


func _beach_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	var ang := Island.angle_of(x, z)
	return h > 0.1 and h < 0.9 and island.beach_weight(ang) > 0.4 and _free_spot(x, z) and _lane_clear(x, z, 3.5)


func _flower_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	return h > 1.4 and _slope(x, z) < 0.2 and _free_spot(x, z, -1.5) and _lane_clear(x, z, 1.6)


# --- placement ---------------------------------------------------------------------------------------------

func _mesh(fn: String, variant: int) -> Mesh:
	if _methods.has(fn):
		return _nature.call(fn, 1000 + variant * 17 + fn.length())
	var mb := MeshBuilder.new(variant)
	mb.ico(Vector3(0, 0.3, 0), 0.4, Pal.ROCK if fn.contains("rock") else Pal.GRASS_DARK, 0, 0.2)
	return mb.commit()


func _material(fn: String) -> Material:
	if _methods.has("material_for"):
		return _nature.call("material_for", fn)
	return Materials.lowpoly()


func _add(fn: String, variant: int, xf: Transform3D) -> void:
	var key := "%s#%d" % [fn, variant]
	if not _batches.has(key):
		_batches[key] = {"mesh": _mesh(fn, variant), "material": _material(fn), "xforms": [], "shadow": not fn.begins_with("grass") and not fn.begins_with("flowers")}
	_batches[key]["xforms"].append(xf)


func _scatter(fn: String, variants: int, count: int, ok: Callable, smin: float, smax: float, spacing: float, obstacle_r: float) -> void:
	var placed: Array[Vector2] = []
	var tries := count * 30
	var ext := Island.EXTENT - 8.0
	while placed.size() < count and tries > 0:
		tries -= 1
		var x := rng.randf_range(-ext, ext)
		var z := rng.randf_range(-ext, ext)
		if not ok.call(x, z):
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(Vector2(x, z)) < spacing:
				too_close = true
				break
		if too_close:
			continue
		placed.append(Vector2(x, z))
		var sc := rng.randf_range(smin, smax)
		var y := island.height_at(x, z)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
		_add(fn, rng.randi() % variants, Transform3D(basis, Vector3(x, y - 0.05, z)))
		if obstacle_r > 0.0:
			Obstacles.add(Vector3(x, y, z), obstacle_r * sc, self)


## Clusters: groves, clumps and flower patches read much better than an even sprinkle.
func _cluster(fn: String, variants: int, clusters: int, min_per: int, max_per: int, ok: Callable, spacing: float, obstacle_r: float, smin: float, smax: float) -> void:
	var placed: Array[Vector2] = []
	var ext := Island.EXTENT - 10.0
	var made := 0
	var tries := clusters * 60
	while made < clusters and tries > 0:
		tries -= 1
		var cx := rng.randf_range(-ext, ext)
		var cz := rng.randf_range(-ext, ext)
		if not ok.call(cx, cz):
			continue
		var far := true
		for q in placed:
			if q.distance_to(Vector2(cx, cz)) < spacing * 4.0:
				far = false
				break
		if not far:
			continue
		made += 1
		var count := rng.randi_range(min_per, max_per)
		var radius := spacing * sqrt(float(count)) * 0.75
		var local := 0
		var t2 := count * 25
		while local < count and t2 > 0:
			t2 -= 1
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * radius
			var x := cx + cos(a) * rr
			var z := cz + sin(a) * rr
			if not ok.call(x, z):
				continue
			var close := false
			for q in placed:
				if q.distance_to(Vector2(x, z)) < spacing:
					close = true
					break
			if close:
				continue
			placed.append(Vector2(x, z))
			local += 1
			var sc := rng.randf_range(smin, smax)
			var y := island.height_at(x, z)
			_add(fn, rng.randi() % variants, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, y - 0.05, z)))
			if obstacle_r > 0.0:
				Obstacles.add(Vector3(x, y, z), obstacle_r * sc, self)


## Cypresses lining the roads into the village, in loose pairs.
func _cypress_avenues() -> void:
	for li in island.lanes.size():
		var pts: PackedVector3Array = island.lanes[li]
		var next_r := 13.0 + rng.randf() * 3.0
		for k in range(pts.size() - 1, 1, -1):
			var p := pts[k]
			var r := Vector2(p.x, p.z).length()
			if r < next_r:
				continue
			if r > 42.0:
				break
			next_r = r + rng.randf_range(6.5, 9.0)
			var dir := (pts[k - 1] - pts[mini(k + 1, pts.size() - 1)])
			dir.y = 0.0
			dir = dir.normalized()
			var right := Vector3(-dir.z, 0, dir.x)
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.22:
					continue
				var q: Vector3 = p + right * side * rng.randf_range(3.2, 3.8)
				if island.height_at(q.x, q.z) < 1.3 or not _free_spot(q.x, q.z, -1.0) or not _lane_clear(q.x, q.z, 2.3):
					continue
				var sc := rng.randf_range(0.9, 1.15)
				_add("cypress", rng.randi() % 3, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(q.x, island.height_at(q.x, q.z) - 0.05, q.z)))
				Obstacles.add(Vector3(q.x, 0, q.z), 0.35 * sc, self)


func _place_at(fn: String, variant: int, x: float, z: float, yaw: float, sc: float = 1.0, obstacle_r: float = 0.0) -> void:
	var y := island.height_at(x, z)
	_add(fn, variant, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(x, y - 0.05, z)))
	_reserved.append([Vector2(x, z), maxf(obstacle_r, 1.0) + 0.6])
	if obstacle_r > 0.0:
		Obstacles.add(Vector3(x, y, z), obstacle_r, self)


func _ruins() -> void:
	# A fallen temple on the north-east hill, a toppled column by the west path and a roadside herm.
	var c := Vector2(24.0, -27.0)
	if island.height_at(c.x, c.y) > 1.0:
		_place_at("ruin_base", 0, c.x, c.y, 0.3, 1.0, 2.2)
		_place_at("ruin_column", 0, c.x - 3.5, c.y + 1.2, 0.0, 1.0, 0.6)
		_place_at("ruin_column", 1, c.x + 3.4, c.y - 1.0, 1.2, 0.9, 0.6)
		_place_at("ruin_fallen", 0, c.x + 1.0, c.y + 3.8, 0.8, 1.0, 1.0)
	var w := Vector2(-31.0, -14.0)
	if island.height_at(w.x, w.y) > 1.0:
		_place_at("ruin_fallen", 1, w.x, w.y, 2.1, 1.0, 1.0)
		_place_at("ruin_column", 2, w.x + 2.5, w.y - 2.0, 0.4, 0.8, 0.6)
	var hm := Vector2(-6.5, 20.5)
	if island.height_at(hm.x, hm.y) > 1.0 and _free_spot(hm.x, hm.y):
		_place_at("herm_shrine", 0, hm.x, hm.y, 0.2, 1.0, 0.5)
	for p in [Vector2(30, 33), Vector2(-28, 28), Vector2(14, -38)]:
		if island.height_at(p.x, p.y) > 1.2 and _free_spot(p.x, p.y) and _lane_clear(p.x, p.y, 3.0):
			_place_at("stone_fence", 0, p.x, p.y, rng.randf() * PI, 1.0, 0.0)
			_place_at("stone_fence", 1, p.x + 2.9, p.y + 0.6, rng.randf() * 0.3, 1.0, 0.0)


func _place_beached_boats() -> void:
	var b: Dictionary = island.beaches[0]
	var land: Vector3 = b["landing"]
	for i in 2:
		var x := land.x + (6.0 + 3.0 * i) * (1.0 if i == 0 else -1.4)
		var z := land.z - 1.0
		if island.height_at(x, z) > 0.0 and _free_spot(x, z):
			_place_at("boat_small", i, x, z, 0.6 + i * 2.4, 1.0, 1.0)
	for i in 3:
		var bb: Dictionary = island.beaches[i % island.beaches.size()]
		var l2: Vector3 = bb["landing"]
		var x2 := l2.x + rng.randf_range(-9, 9)
		var z2 := l2.z + rng.randf_range(-6, 2)
		if island.height_at(x2, z2) > 0.3 and _free_spot(x2, z2) and _lane_clear(x2, z2, 3.0):
			_place_at("amphora", i, x2, z2, rng.randf() * TAU, 1.0, 0.0)


func _commit() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var xfs: Array = b["xforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = b["material"]
		if not b["shadow"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
