extends RefCounted
## Nemea's flora and rocks, zone by zone: the holm-oak and pine forest of the palm (with undergrowth, rocks and
## clearings), olive and almond rows on the east hill's benches, wind-bent pines, junipers and phrygana on the dry
## thumb and west plateau, scattered oaks on the ridge meadow, layered limestone at the foot of every cliff and on
## the spurs, tamarisks, palms, drift-wood and wet rocks along the coast, a few trees on the islets.
##
## Drawing (WebGL 2: few draw calls): trees are instanced per (species, variant, 64 m region) as a LOD pair (the
## toon-smoothed crowns within NEAR_RANGE of the region, the plain low-poly ones beyond, without shadows);
## rocks, ruins, fences, drift-wood and the terrace walls are merged into one static mesh per region; the stiff
## shrubs (bushes, cistus, thyme, broom, sea lilies) into one non-swaying foliage mesh per region that fades out
## at SHRUB_RANGE. Collision (layer 1): a cylinder per trunk (and per juniper / broom), a convex hull per rock.
## Ground map: contact AO under everything, no grass under trunks, rocks and shrubs.
##
## Also records what the ambient fauna needs: trees (positions), solids ([x, z, r, height]) and flowers.

const L := preload("res://scripts/world/nemea_layout.gd")
const REGION := 64.0
## Trees whose region centre is nearer than this draw their toon-smoothed crowns; farther, the plain ones.
const NEAR_RANGE := 80.0
const SHRUB_RANGE := 150.0
## Models built without the toon subdivision (cheaper, they read fine faceted): shrubs and small rocks.
const LOW_POLY := ["bush", "cistus_shrub", "thyme_cushion", "broom_shrub", "rock_small", "rock_large", "beach_rock", "juniper"]
const TREES := ["holm_oak", "aleppo_pine", "stone_pine", "olive_tree", "almond_tree", "cypress", "plane_tree", "fig_tree",
	"laurel_tree", "juniper", "tamarisk", "date_palm", "pomegranate", "oleander"]
const SHRUBS := ["bush", "cistus_shrub", "thyme_cushion", "broom_shrub", "sea_lily", "flowers_lavender", "flowers_poppy",
	"flowers_daisy", "flowers_anemone"]
## Mesh variants kept per model (the placement picks one at random; fewer variants = fewer batches).
const VARIANTS := {"holm_oak": 2, "aleppo_pine": 2, "olive_tree": 2, "juniper": 2, "cypress": 2, "cliff_rock": 3,
	"wood_fence": 3, "retaining_wall": 3, "bush": 2, "cistus_shrub": 2, "thyme_cushion": 2, "rock_small": 2,
	"rock_large": 2, "beach_rock": 2, "driftwood": 2}
## Shrubs tall enough to block the hero (a trunk-like cylinder).
const SOLID_SHRUBS := {"broom_shrub": 0.35, "juniper": 0.4}

var world: Node3D
var t: RefCounted # NemeaTerrain
var rng := RandomNumberGenerator.new()
var body: StaticBody3D
var counts := {}
var trees := PackedVector3Array()
var flowers := PackedVector3Array()
## [x, z, radius, height] of everything solid an animal must walk round.
var solids: Array = []

var _nature: Script
var _batches := {} # trees: "fn#variant@region" -> {fn, variant, xforms}
var _merged := {} # "rocks@region" / "shrubs@region" -> SurfaceTool
var _mesh_cache := {}
var _hull_cache := {}
var _occ := {}
var _reserved: Array = [] # [Vector2, r]
var _n_clear := FastNoiseLite.new()
var _n_mix := FastNoiseLite.new()


func _init() -> void:
	_n_clear.seed = 2024
	_n_clear.frequency = 0.035
	_n_clear.fractal_octaves = 2
	_n_mix.seed = 77
	_n_mix.frequency = 0.02


func setup(w: Node3D, terrain: RefCounted, seed_value: int) -> void:
	world = w
	t = terrain
	rng.seed = seed_value
	_nature = load("res://scripts/gfx/models_nature.gd")
	body = StaticBody3D.new()
	body.name = "PropsBody"
	body.collision_layer = 1
	body.collision_mask = 0
	world.add_child(body)


## A disc nothing is scattered in (houses, the plaza, the pier, altars, the cave, the passage rims).
func reserve(p: Vector2, r: float) -> void:
	_reserved.append([p, r])


func build() -> void:
	var t0 := Time.get_ticks_usec()
	_cliffs()
	_forest()
	_olive_benches()
	_dry_west()
	_ridge_meadow()
	_massif_and_spurs()
	_meadows_south()
	_flower_drifts()
	_coast()
	_islets()
	_commit()
	counts["ms"] = (Time.get_ticks_usec() - t0) / 1000


# --- bookkeeping -------------------------------------------------------------------------------------------

func _occ_key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 4.0)), int(floor(p.y / 4.0)))


func _occ_add(p: Vector2, r: float) -> void:
	var k := _occ_key(p)
	if not _occ.has(k):
		_occ[k] = []
	(_occ[k] as Array).append([p, r])


## True when a circle (p, r) keeps dist >= k * (r + r2) + pad from everything placed so far.
func _occ_free(p: Vector2, r: float, k: float = 0.6, pad: float = 0.2) -> bool:
	var c := _occ_key(p)
	var reach := int(ceil((r * 2.0 + 4.0) / 4.0))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell: Variant = _occ.get(Vector2i(c.x + dx, c.y + dz))
			if cell == null:
				continue
			for o in cell:
				if p.distance_to(o[0]) < k * (r + float(o[1])) + pad:
					return false
	return true


func _reserved_free(p: Vector2, r: float) -> bool:
	for rv in _reserved:
		if p.distance_to(rv[0]) < float(rv[1]) + r:
			return false
	return true


## Ground a plant of radius r may grow on: dry land, gentle, off paths, pads, the cave and reserved places.
func _ground_ok(x: float, z: float, r: float, max_slope: float = 0.22, min_h: float = 1.0, path_gap: float = 1.2) -> bool:
	var y: float = t.height_at(x, z)
	if y < min_h:
		return false
	if t.normal_at(x, z).y < 1.0 - max_slope:
		return false
	if t.field(t.cave_w, x, z) > 0.02 or t.field(t.pad_w, x, z) > 0.2:
		return false
	if t.field(t.path_d, x, z) < r + path_gap:
		return false
	return _reserved_free(Vector2(x, z), r)


func _count(fn: String) -> void:
	counts[fn] = int(counts.get(fn, 0)) + 1


func _mesh(fn: String, variant: int, plain: bool = false) -> Mesh:
	var key := "%s#%d%s" % [fn, variant, "p" if plain else ""]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var keep: Variant = Game.args.get("toonsub", null)
	if fn in LOW_POLY or plain:
		Game.args["toonsub"] = "0"
	var m: Mesh = _nature.call(fn, 61 * variant + 60)
	if keep == null:
		Game.args.erase("toonsub")
	else:
		Game.args["toonsub"] = keep
	_mesh_cache[key] = m
	return m


func _material(fn: String) -> Material:
	return _nature.call("material_for", fn)


func _region(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x + 192.0) / REGION)), int(floor((p.z + 192.0) / REGION)))


func _add(fn: String, variant: int, xf: Transform3D) -> void:
	var v := posmod(variant, int(VARIANTS.get(fn, 1)))
	var rg := _region(xf.origin)
	if fn in TREES:
		var key := "%s#%d@%d_%d" % [fn, v, rg.x, rg.y]
		if not _batches.has(key):
			_batches[key] = {"fn": fn, "variant": v, "xforms": []}
		(_batches[key]["xforms"] as Array).append(xf)
	else:
		var key := "%s@%d_%d" % ["shrubs" if fn in SHRUBS else "rocks", rg.x, rg.y]
		if not _merged.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_merged[key] = st
		var m := _mesh(fn, v)
		for si in m.get_surface_count():
			(_merged[key] as SurfaceTool).append_from(m, si, xf)
	_count(fn)


func _xf(x: float, z: float, yaw: float, sc: Vector3, sink: float = 0.06, tilt: Vector3 = Vector3.ZERO) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis.from_euler(tilt) * Basis.from_scale(sc)
	return Transform3D(b, Vector3(x, t.height_at(x, z) - sink, z))


func _info(fn: String) -> Dictionary:
	return _nature.call("info", fn)


# --- placement primitives ----------------------------------------------------------------------------------

## A tree (checked unless `force`): trunk collision, AO under the crown, no grass at the trunk.
func tree(fn: String, x: float, z: float, sc: float, variant: int = -1, force: bool = false, lean: float = 0.0, lean_dir: Vector2 = Vector2.ZERO, pack: float = 0.62) -> bool:
	var inf := _info(fn)
	var r: float = float(inf["r"]) * sc
	var p := Vector2(x, z)
	if not force:
		if not _ground_ok(x, z, r * 0.6, 0.24, 1.0, 1.0 + r * 0.4):
			return false
		if not _occ_free(p, r, pack, 0.3):
			return false
	var v := variant if variant >= 0 else rng.randi() % 2
	var tilt := Vector3.ZERO
	var yaw := rng.randf() * TAU
	if lean > 0.0 and lean_dir.length_squared() > 0.0:
		# Lean towards lean_dir (world XZ): tilt about the axis perpendicular to it.
		var axis := Vector3.UP.cross(Vector3(lean_dir.x, 0, lean_dir.y)).normalized()
		var b := Basis(axis, lean) * Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * sc)
		_add(fn, v, Transform3D(b, Vector3(x, t.height_at(x, z) - 0.08, z)))
	else:
		_add(fn, v, _xf(x, z, yaw, Vector3.ONE * sc, 0.08))
	_occ_add(p, r)
	trees.append(Vector3(x, t.height_at(x, z), z))
	var ob: float = maxf(float(inf["obstacle"]), float(SOLID_SHRUBS.get(fn, 0.0))) * clampf(sc, 0.8, 1.4)
	if ob > 0.0:
		_trunk(Vector3(x, t.height_at(x, z), z), maxf(ob, 0.22))
		solids.append([x, z, ob + 0.1, 99.0])
	t.splat_ao(p, r * 1.05, float(inf["ao"]))
	t.splat_nograss(p, maxf(ob, 0.3) + 0.25)
	return true


func shrub(fn: String, x: float, z: float, sc: float, variant: int = -1, check: bool = true, pack: float = 0.75, variants: int = 3) -> bool:
	var inf := _info(fn)
	var r: float = float(inf["r"]) * sc
	var p := Vector2(x, z)
	if check:
		if not _ground_ok(x, z, r, 0.3, 0.6, 0.6):
			return false
		if not _occ_free(p, r, pack, 0.05):
			return false
	var v := variant if variant >= 0 else rng.randi() % variants
	_add(fn, v, _xf(x, z, rng.randf() * TAU, Vector3.ONE * sc, 0.05))
	_occ_add(p, r)
	if SOLID_SHRUBS.has(fn):
		_trunk(Vector3(x, t.height_at(x, z), z), float(SOLID_SHRUBS[fn]) * sc)
	if not fn.begins_with("flowers") and fn != "sea_lily":
		t.splat_ao(p, r * 1.2, 0.28)
		t.splat_nograss(p, r * 0.75)
		solids.append([x, z, r * 0.8, float(inf["h"]) * sc])
	else:
		flowers.append(Vector3(x, t.height_at(x, z), z))
	return true


## A rock: convex-hull collision (scaled per instance), AO ring, no grass under it.
func rock(fn: String, x: float, z: float, sc: float, sink: float = 0.15, tilt: Vector3 = Vector3.ZERO, variant: int = -1, collide: bool = true, yaw: float = NAN) -> void:
	var v := variant if variant >= 0 else rng.randi() % 3
	var yw := rng.randf() * TAU if is_nan(yaw) else yaw
	var xf := _xf(x, z, yw, Vector3.ONE * sc, sink, tilt)
	_add(fn, v, xf)
	var ab := _mesh(fn, v).get_aabb()
	var r := maxf(ab.size.x, ab.size.z) * 0.5 * sc
	var p := Vector2(x, z)
	_occ_add(p, r * 0.8)
	t.splat_ao(p, r * 1.15, 0.45)
	t.splat_nograss(p, r * 0.85)
	solids.append([x, z, r * 0.85, ab.size.y * sc])
	if collide and ab.size.y * sc > 0.25:
		_hull(fn, v, xf)


func _trunk(base: Vector3, r: float) -> void:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = 4.0
	cs.shape = cy
	cs.position = base + Vector3(0, 1.6, 0)
	body.add_child(cs)


func _hull(fn: String, v: int, xf: Transform3D) -> void:
	var key := "%s#%d" % [fn, v]
	if not _hull_cache.has(key):
		var cs0 := _mesh(fn, v).create_convex_shape(true, true) as ConvexPolygonShape3D
		_hull_cache[key] = cs0.points if cs0 != null else PackedVector3Array()
	var pts: PackedVector3Array = _hull_cache[key]
	if pts.is_empty():
		return
	var sc := xf.basis.get_scale()
	var scaled := PackedVector3Array()
	scaled.resize(pts.size())
	for i in pts.size():
		scaled[i] = pts[i] * sc
	var shape := ConvexPolygonShape3D.new()
	shape.points = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	body.add_child(cs)


## Static decorative mesh with optional convex collision (used by the village and the cave too).
func place_mesh(fn: String, variant: int, xf: Transform3D, collide: bool) -> void:
	_add(fn, variant, xf)
	if collide:
		_hull(fn, variant, xf)


# --- zones -------------------------------------------------------------------------------------------------

## Layered limestone at the foot and on the face of steep ground: the escarpment, the massif, the sea cliffs,
## the inlet and the spurs. Walks a grid and drops a rock where the slope turns steep.
func _cliffs() -> void:
	var step := 5.0
	var z := -186.0
	while z < 186.0:
		var x := -186.0
		while x < 186.0:
			var px := x + rng.randf_range(-2.0, 2.0)
			var pz := z + rng.randf_range(-2.0, 2.0)
			x += step
			var y: float = t.height_at(px, pz)
			if y < -1.5 or y > 60.0:
				continue
			var ny: float = t.normal_at(px, pz).y
			if ny > 0.72 or ny < 0.12:
				continue
			if t.field(t.cave_w, px, pz) > 0.0 or t.field(t.path_d, px, pz) < 2.5:
				continue
			var p := Vector2(px, pz)
			if not _reserved_free(p, 3.0) or not _occ_free(p, 1.8, 0.5, 0.0):
				continue
			if rng.randf() > 0.55:
				continue
			var sc := rng.randf_range(0.8, 1.6) * (1.25 if y > 18.0 else 1.0)
			var tilt := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
			var sea := y < 3.0
			rock("cliff_rock", px, pz, sc, 0.9 * sc, tilt, rng.randi() % 4)
			if sea and rng.randf() < 0.5:
				rock("beach_rock", px + rng.randf_range(-3, 3), pz + rng.randf_range(-3, 3), rng.randf_range(0.8, 1.4), 0.2)
		z += step


## The palm's forest: holm oaks and Aleppo pines in groves with clearings, stone pines as landmarks, laurels and
## figs at the edges, a maquis undergrowth and mossy rocks.
func _forest() -> void:
	var step := 3.9
	var z := -60.0
	while z < 52.0:
		var x := -100.0
		while x < 70.0:
			var px := x + rng.randf_range(-1.9, 1.9)
			var pz := z + rng.randf_range(-1.9, 1.9)
			x += step
			var fw: float = t.field(t.forest_w, px, pz)
			if fw < 0.15:
				continue
			# Clearings: meadows inside the forest (flowers and grass take them).
			var cl := _n_clear.get_noise_2d(px, pz)
			if cl > 0.34:
				if rng.randf() < 0.06:
					rock("rock_large" if rng.randf() < 0.4 else "rock_small", px, pz, rng.randf_range(0.8, 1.3))
				continue
			var dens := fw * smoothstep(0.38, 0.1, cl)
			if rng.randf() > dens:
				# Undergrowth where no tree goes.
				if rng.randf() < 0.45 * fw:
					shrub("bush", px, pz, rng.randf_range(0.9, 1.4))
				elif rng.randf() < 0.08:
					rock("rock_small", px, pz, rng.randf_range(0.8, 1.4))
				continue
			var mix := _n_mix.get_noise_2d(px, pz) * 0.5 + 0.5
			var u := rng.randf()
			var edge := fw < 0.55
			var fn := "holm_oak"
			if u < 0.04:
				fn = "stone_pine"
			elif u < 0.36 + mix * 0.25:
				fn = "aleppo_pine"
			elif edge and u < 0.75:
				fn = ["laurel_tree", "fig_tree", "cypress", "holm_oak"][rng.randi() % 4]
			var sc := rng.randf_range(1.0, 1.45)
			if fn == "stone_pine":
				sc = rng.randf_range(1.1, 1.3)
			var ok := tree(fn, px, pz, sc, -1, false, deg_to_rad(rng.randf_range(0.0, 5.0)) if fn == "aleppo_pine" else 0.0, Vector2(0.3, 1.0))
			if ok and rng.randf() < 0.5:
				# A bush or two in the tree's lee.
				var a := rng.randf() * TAU
				var d := rng.randf_range(2.6, 4.0)
				shrub("bush" if rng.randf() < 0.75 else "cistus_shrub", px + cos(a) * d, pz + sin(a) * d, rng.randf_range(0.8, 1.2))
		z += step


## Olive and almond rows on the east hill's benches, cypresses on the crest, thyme on the risers, low dry-stone
## walls along the bench edges.
func _olive_benches() -> void:
	var c := L.EAST_HILL
	for ring in range(0, 20):
		var rr := 14.0 + ring * 2.2
		var n := int(TAU * rr / 5.2)
		for k in n:
			var a := TAU * float(k) / float(n) + ring * 0.37
			var px := c.x + cos(a) * rr + rng.randf_range(-0.5, 0.5)
			var pz := c.y + sin(a) * rr + rng.randf_range(-0.5, 0.5)
			var b: float = t.field(t.bench, px, pz)
			if b < 0.55:
				continue
			# On the tread, not on the riser: the ground must be nearly flat.
			if t.normal_at(px, pz).y < 0.93:
				if rng.randf() < 0.25:
					shrub("thyme_cushion", px, pz, rng.randf_range(0.8, 1.2), -1, true, 0.6, 2)
				continue
			if rng.randf() < 0.12:
				continue
			var fn := "olive_tree" if rng.randf() < 0.82 else "almond_tree"
			tree(fn, px, pz, rng.randf_range(0.9, 1.2), -1, false, 0.0, Vector2.ZERO, 0.5)
	_bench_walls()
	# The crest: cypresses round the altar.
	for k in 7:
		var a := TAU * float(k) / 7.0 + 0.4
		tree("cypress", c.x + cos(a) * rng.randf_range(8.0, 11.0), c.y + sin(a) * rng.randf_range(8.0, 11.0), rng.randf_range(0.9, 1.15))
	# The hill's wild back (east and north): oaks, pines and phrygana.
	for i in 140:
		var a := rng.randf() * TAU
		var d := rng.randf_range(10.0, L.EAST_HILL_R)
		var px := c.x + cos(a) * d
		var pz := c.y + sin(a) * d
		if t.field(t.bench, px, pz) > 0.2 or t.field(t.forest_w, px, pz) > 0.3:
			continue
		var u := rng.randf()
		if u < 0.22:
			tree("holm_oak" if rng.randf() < 0.6 else "aleppo_pine", px, pz, rng.randf_range(0.9, 1.2))
		elif u < 0.7:
			shrub(["thyme_cushion", "cistus_shrub", "broom_shrub", "bush"][rng.randi() % 4], px, pz, rng.randf_range(0.9, 1.3))
		else:
			rock("rock_large" if rng.randf() < 0.3 else "rock_small", px, pz, rng.randf_range(0.8, 1.3))


## Dry-stone walls along every bench riser: marching squares on the hill's pre-cut height at each riser's foot
## level; one short wall block per contour segment, its face on the foot line (the terrain riser rises behind
## it, so nothing walks into the stones).
func _bench_walls() -> void:
	var step: float = t.BENCH_STEP
	var N: int = t.N
	var x0 := int(34.0 + 192.0)
	var x1 := int(122.0 + 192.0)
	var z0 := int(-44.0 + 192.0)
	var z1 := int(68.0 + 192.0)
	var hb: PackedFloat32Array = t.bench_h0
	var bw: PackedFloat32Array = t.bench
	for iz in range(z0, z1):
		for ix in range(x0, x1):
			var i := iz * N + ix
			if bw[i] < 0.95 or bw[i + 1] < 0.95 or bw[i + N] < 0.95 or bw[i + N + 1] < 0.95:
				continue
			var ha := hb[i]
			var hbx := hb[i + 1]
			var hc := hb[i + N + 1]
			var hd := hb[i + N]
			var lo := minf(minf(ha, hbx), minf(hc, hd))
			var hi := maxf(maxf(ha, hbx), maxf(hc, hd))
			var k0 := int(ceil((lo - 8.0) / step - 0.78))
			var k1 := int(floor((hi - 8.0) / step - 0.78))
			for k in range(maxi(k0, 0), k1 + 1):
				var lv := 8.0 + step * (float(k) + 0.78)
				var pts: Array[Vector2] = []
				var cx := -192.0 + ix
				var cz := -192.0 + iz
				# Edges a-b (z = cz), b-c (x = cx+1), d-c (z = cz+1), a-d (x = cx).
				if (ha - lv) * (hbx - lv) < 0.0:
					pts.append(Vector2(cx + (lv - ha) / (hbx - ha), cz))
				if (hbx - lv) * (hc - lv) < 0.0:
					pts.append(Vector2(cx + 1.0, cz + (lv - hbx) / (hc - hbx)))
				if (hd - lv) * (hc - lv) < 0.0:
					pts.append(Vector2(cx + (lv - hd) / (hc - hd), cz + 1.0))
				if (ha - lv) * (hd - lv) < 0.0:
					pts.append(Vector2(cx, cz + (lv - ha) / (hd - ha)))
				if pts.size() != 2:
					continue
				var a := pts[0]
				var b := pts[1]
				var mid := (a + b) * 0.5
				var seg := b - a
				var l := seg.length()
				if l < 0.15:
					continue
				if t.field(t.path_d, mid.x, mid.y) < 0.6:
					continue # the road ramps through the benches here
				# Outward = downhill on the uncut hill.
				var g := Vector2((hbx + hc - ha - hd) * 0.5, (hd + hc - ha - hbx) * 0.5)
				var out := -g.normalized()
				var along := seg / l
				# Right-handed frame: Z = X x Y = (-along.y, 0, along.x) must point out (downhill).
				if Vector2(-along.y, along.x).dot(out) < 0.0:
					along = -along
				var zf := Vector3(-along.y, 0, along.x)
				var xf_axis := Vector3(along.x, 0, along.y)
				var foot := 8.0 + step * float(k)
				var basis := Basis(xf_axis * (l * 1.12), Vector3(0, step + 0.55, 0), zf)
				_add("retaining_wall", rng.randi() % 3, Transform3D(basis, Vector3(mid.x, foot - 0.3, mid.y)))


## The thumb and the west plateau: golden garrigue, wind-bent Aleppo pines leaning away from the west wind,
## junipers, thyme, cistus and broom, and limestone outcrops (the boars' clearings keep rocks to stun them on).
func _dry_west() -> void:
	for i in 1500:
		var px := rng.randf_range(-178.0, -52.0)
		var pz := rng.randf_range(-92.0, 62.0)
		var dr: float = t.field(t.dry, px, pz)
		if dr < 0.45 or t.height_at(px, pz) < 6.0:
			continue
		if t.field(t.forest_w, px, pz) > 0.4:
			continue
		var u := rng.randf()
		if u < 0.07:
			tree("aleppo_pine", px, pz, rng.randf_range(0.85, 1.15), -1, false, deg_to_rad(rng.randf_range(6.0, 14.0)), Vector2(1.0, 0.25))
		elif u < 0.15:
			tree("juniper", px, pz, rng.randf_range(0.8, 1.2), -1, false, 0.0, Vector2.ZERO, 0.7)
		elif u < 0.5:
			shrub("thyme_cushion", px, pz, rng.randf_range(0.8, 1.3), -1, true, 0.55, 2)
		elif u < 0.68:
			shrub("cistus_shrub", px, pz, rng.randf_range(0.9, 1.3))
		elif u < 0.78:
			shrub("broom_shrub", px, pz, rng.randf_range(0.9, 1.25), -1, true, 0.75, 1)
		elif u < 0.86:
			if _ground_ok(px, pz, 2.0, 0.25, 4.0, 2.0) and _occ_free(Vector2(px, pz), 2.0, 0.7, 0.5):
				rock("cliff_rock", px, pz, rng.randf_range(0.6, 1.0), 0.6, Vector3.ZERO, rng.randi() % 4)
		else:
			if _ground_ok(px, pz, 1.0, 0.25, 2.0, 1.5):
				rock("rock_large" if rng.randf() < 0.5 else "rock_small", px, pz, rng.randf_range(0.8, 1.4))
	# Boar clearings: a ring of standing rocks to charge into.
	for s in L.SPAWNS:
		if s["kind"] != &"boar":
			continue
		var c: Vector2 = s["at"]
		var R: float = s["radius"]
		for k in 4:
			var a := TAU * float(k) / 4.0 + rng.randf_range(-0.4, 0.4)
			var px := c.x + cos(a) * (R + rng.randf_range(1.0, 3.0))
			var pz := c.y + sin(a) * (R + rng.randf_range(1.0, 3.0))
			if _ground_ok(px, pz, 1.5, 0.3, 1.0, 1.0):
				rock("cliff_rock", px, pz, rng.randf_range(0.55, 0.75), 0.5, Vector3.ZERO, rng.randi() % 4)


## The ridge meadow: green and open (the view south stays clear), with a few holm oaks, pines and rocks.
func _ridge_meadow() -> void:
	for i in 260:
		var px := rng.randf_range(-80.0, 60.0)
		var pz := rng.randf_range(-98.0, -56.0)
		if t.field(t.upw, px, pz) < 0.9 or t.height_at(px, pz) > 30.0:
			continue
		# Keep the escarpment edge (the viewpoint) and the mouths' aprons open.
		if t.field(t.path_d, px, pz) < 3.0:
			continue
		var u := rng.randf()
		if u < 0.16:
			tree("holm_oak" if rng.randf() < 0.65 else "aleppo_pine", px, pz, rng.randf_range(0.95, 1.3), -1, false, 0.0, Vector2.ZERO, 0.8)
		elif u < 0.3:
			shrub("bush", px, pz, rng.randf_range(0.9, 1.3))
		elif u < 0.4:
			rock("rock_large" if rng.randf() < 0.5 else "rock_small", px, pz, rng.randf_range(0.8, 1.5))


## The massif's top and the spurs: limestone outcrops and junipers.
func _massif_and_spurs() -> void:
	for i in 700:
		var px := rng.randf_range(-100.0, 100.0)
		var pz := rng.randf_range(-180.0, -96.0)
		var y: float = t.height_at(px, pz)
		if y < 14.0 or t.field(t.cave_w, px, pz) > 0.0:
			continue
		if t.normal_at(px, pz).y < 0.75:
			continue
		var u := rng.randf()
		if u < 0.2:
			if _occ_free(Vector2(px, pz), 2.2, 0.6, 0.3):
				rock("cliff_rock", px, pz, rng.randf_range(0.7, 1.3), 0.6, Vector3.ZERO, rng.randi() % 4)
		elif u < 0.32:
			tree("juniper", px, pz, rng.randf_range(0.8, 1.2), -1, false, 0.0, Vector2.ZERO, 0.7)
		elif u < 0.38:
			tree("aleppo_pine", px, pz, rng.randf_range(0.8, 1.1), -1, false, deg_to_rad(rng.randf_range(4.0, 10.0)), Vector2(0.4, 1.0))
		elif u < 0.6:
			shrub("thyme_cushion", px, pz, rng.randf_range(0.8, 1.2), -1, true, 0.55, 2)


## Meadows between the forest and the village: solitary oaks and olive trees, cypress pairs along the roads.
func _meadows_south() -> void:
	for i in 500:
		var px := rng.randf_range(-100.0, 110.0)
		var pz := rng.randf_range(20.0, 104.0)
		if t.field(t.forest_w, px, pz) > 0.25 or t.field(t.bench, px, pz) > 0.2 or t.field(t.dry, px, pz) > 0.6:
			continue
		if t.height_at(px, pz) < 2.6:
			continue
		var u := rng.randf()
		if u < 0.06:
			tree("olive_tree", px, pz, rng.randf_range(0.9, 1.2))
		elif u < 0.1:
			tree("holm_oak", px, pz, rng.randf_range(1.0, 1.3))
		elif u < 0.15:
			shrub("bush", px, pz, rng.randf_range(0.9, 1.3))
		elif u < 0.18:
			rock("rock_small", px, pz, rng.randf_range(0.8, 1.2))
	# Cypress pairs along the main road north of the village (a Greek road).
	var road: Dictionary = t.paths[0]
	var pts: PackedVector2Array = road["pts"]
	var k := 30
	while k < pts.size() - 1:
		var a := pts[k]
		var b := pts[mini(k + 1, pts.size() - 1)]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		if a.y < 64.0 and a.y > 10.0:
			for s in [-1.0, 1.0]:
				var q: Vector2 = a + side * float(s) * rng.randf_range(4.2, 5.0)
				tree("cypress", q.x, q.y, rng.randf_range(0.95, 1.2), -1, false, 0.0, Vector2.ZERO, 0.4)
		k += 13


## Drifts of wild flowers (one species each, a dozen patches scaled up so they read as colour from afar):
## poppies, crown daisies and anemones in the green meadows and the forest clearings, lavender on the golden
## garrigue of the thumb and the west plateau.
func _flower_drifts() -> void:
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 900:
		tries += 1
		var cx := rng.randf_range(-175.0, 130.0)
		var cz := rng.randf_range(-100.0, 100.0)
		var y: float = t.height_at(cx, cz)
		if y < 2.5 or t.normal_at(cx, cz).y < 0.9:
			continue
		if t.color_at(cx, cz).a < 0.7 or t.field(t.path_d, cx, cz) < 2.5 or t.field(t.pad_w, cx, cz) > 0.1:
			continue
		if not _reserved_free(Vector2(cx, cz), 4.0):
			continue
		var fw: float = t.field(t.forest_w, cx, cz)
		if fw > 0.3 and _n_clear.get_noise_2d(cx, cz) < 0.36:
			continue # under the trees (clearings only)
		var dr: float = t.field(t.dry, cx, cz)
		var fn := "flowers_lavender"
		if dr < 0.45:
			fn = ["flowers_poppy", "flowers_daisy", "flowers_anemone", "flowers_poppy"][rng.randi() % 4]
		elif dr < 0.6:
			continue
		var n := 9 + rng.randi() % 9
		var R := rng.randf_range(2.6, 4.6)
		for k in n:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * R
			shrub(fn, cx + cos(a) * d, cz + sin(a) * d, rng.randf_range(1.4, 2.0), -1, true, 0.35, 1)
		placed += 1
	counts["flower_drifts"] = placed


## Beaches and rocky shores: tamarisks behind the sand, a pair of palms by the village beach, drift-wood, sea
## lilies on the dunes, dark wet rocks in the shallows.
func _coast() -> void:
	for i in 2600:
		var a := rng.randf() * TAU
		var r := rng.randf_range(90.0, 180.0)
		var px := sin(a) * r
		var pz := cos(a) * r
		var s: float = t.field(t.sd, px, pz)
		var y: float = t.height_at(px, pz)
		if s < -12.0 or s > 22.0:
			continue
		var cl: float = t.field(t.cliff, px, pz)
		if s < 2.0 and s > -10.0 and y < 0.3 and y > -2.2:
			if rng.randf() < (0.06 if cl < 0.5 else 0.16) and _occ_free(Vector2(px, pz), 1.2, 0.8, 0.2):
				rock("beach_rock", px, pz, rng.randf_range(0.8, 1.6), 0.25)
			continue
		if cl > 0.5 or y < 0.6:
			continue
		var u := rng.randf()
		if s > 7.0 and s < 20.0 and u < 0.05:
			tree("tamarisk", px, pz, rng.randf_range(0.9, 1.2), -1, false, 0.0, Vector2.ZERO, 0.8)
		elif s < 9.0 and u < 0.09:
			if _ground_ok(px, pz, 1.2, 0.2, 0.6, 1.0) and _occ_free(Vector2(px, pz), 1.2):
				_add("driftwood", rng.randi() % 3, _xf(px, pz, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.9, 1.2), 0.08))
				_occ_add(Vector2(px, pz), 1.2)
		elif s > 4.0 and s < 14.0 and u < 0.2:
			shrub("sea_lily", px, pz, rng.randf_range(0.9, 1.2), -1, true, 0.6, 2)
	# Palms on the village beach.
	for p: Vector2 in [Vector2(-14, 104), Vector2(36, 103), Vector2(-30, 101)]:
		tree("date_palm", p.x, p.y, rng.randf_range(0.95, 1.1), -1, true)


func _islets() -> void:
	for isl in L.ISLETS:
		var c: Vector2 = isl[0]
		var rr: Vector2 = isl[1]
		for k in 14:
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.0, 0.75)
			var px := c.x + cos(a) * rr.x * d
			var pz := c.y + sin(a) * rr.y * d
			var y: float = t.height_at(px, pz)
			if y < 1.5:
				continue
			var u := rng.randf()
			if u < 0.25:
				tree("aleppo_pine" if rng.randf() < 0.6 else "juniper", px, pz, rng.randf_range(0.8, 1.1), -1, false, deg_to_rad(8.0), Vector2(1, 0.2))
			elif u < 0.55:
				shrub("thyme_cushion", px, pz, rng.randf_range(0.9, 1.2), -1, true, 0.6, 2)
			else:
				rock("cliff_rock", px, pz, rng.randf_range(0.5, 0.9), 0.5, Vector3.ZERO, rng.randi() % 4)


# --- commit ------------------------------------------------------------------------------------------------

func _commit() -> void:
	var mmis := 0
	var merged := 0
	var tris := 0
	for key in _batches:
		var b: Dictionary = _batches[key]
		var fn: String = b["fn"]
		var v: int = b["variant"]
		var xfs: Array = b["xforms"]
		var lod := not (fn in LOW_POLY)
		var near := _mmi(String(key), _mesh(fn, v), xfs, _material(fn))
		tris += _tris(_mesh(fn, v)) * xfs.size()
		mmis += 1
		if lod:
			near.visibility_range_end = NEAR_RANGE
			near.visibility_range_end_margin = 8.0
			var far := _mmi(String(key) + "_far", _mesh(fn, v, true), xfs, _material(fn))
			far.visibility_range_begin = NEAR_RANGE
			far.visibility_range_begin_margin = 8.0
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmis += 1
	for key in _merged:
		var st: SurfaceTool = _merged[key]
		var m := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = String(key).replace("@", "_")
		mi.mesh = m
		if String(key).begins_with("shrubs"):
			mi.material_override = Materials.foliage(0.0)
			mi.visibility_range_end = SHRUB_RANGE
			mi.visibility_range_end_margin = 10.0
		else:
			mi.material_override = Materials.lowpoly()
		world.add_child(mi)
		merged += 1
		tris += _tris(m)
	_merged.clear()
	counts["multimeshes"] = mmis
	counts["merged_meshes"] = merged
	counts["tris"] = tris
	counts["colliders"] = body.get_child_count()


func _mmi(name: String, mesh: Mesh, xfs: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name.replace("#", "_").replace("@", "_")
	mmi.multimesh = mm
	mmi.material_override = mat
	world.add_child(mmi)
	return mmi


static func _tris(m: Mesh) -> int:
	var n := 0
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
