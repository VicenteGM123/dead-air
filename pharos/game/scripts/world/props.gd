class_name Props
extends Node3D
## Lays out the island's vegetation, rocks, walls and ruins zone by zone (see Landscape), the way an ancient
## Cycladic island was ordered: landmarks at fixed places (the great plane tree by the well, the sanctuary's
## cypress grove, the spring), crops in rows along the terrace benches behind dry-stone risers, field walls round
## the terraced blocks, phrygana drifts and granite outcrops on the wild hills, tamarisks behind the beaches.
##
## Each model variant is one MultiMesh (one draw call); single non-swaying landmarks (well, threshing floor,
## basins, beehives) are merged into one mesh. Props also splats contact AO and bare soil into the island's
## ground map and writes the grass mask (exclusion under trunks, rocks, walls and crops; denser skirts around
## trees, rocks and walls) that Grass reads.

const LANE_W := Island.LANE_W
const TAN52 := 0.78 # gameplay camera (pitch 52, looking north): ground hidden per metre of height
## Grass mask: 0.5 m texels over [-72, 72]^2. excl 255 = no grass, 128 = half; boost adds clumps.
const GM_RES := 0.5
const GM_N := 288
const GM_EXT := 72.0

## Stand-ins while a species is not modelled yet: [existing model, scale].
const FALLBACK := {
	"holm_oak": ["olive_tree", 1.45], "plane_tree": ["olive_tree", 2.3], "aleppo_pine": ["stone_pine", 1.0],
	"fig_tree": ["olive_tree", 1.15], "almond_tree": ["olive_tree", 1.1], "pomegranate": ["bush", 1.2],
	"laurel_tree": ["cypress", 0.65], "date_palm": ["stone_pine", 1.0], "tamarisk": ["olive_tree", 1.3],
	"juniper": ["bush", 1.25], "oleander": ["bush", 1.15], "broom_shrub": ["bush", 0.8], "cistus_shrub": ["bush", 0.65],
	"thyme_cushion": ["bush", 0.38], "giant_reed": ["grass_tuft", 4.5], "sea_lily": ["flowers_daisy", 0.7],
	"flowers_anemone": ["flowers_poppy", 0.9], "terrace_wall": ["stone_fence", 1.0],
}
const NO_SHADOW := ["thyme_cushion", "sea_lily", "wheat_patch", "grass_tuft", "grass_clump", "flowers_poppy", "flowers_daisy", "flowers_lavender", "flowers_anemone"]
const RANDOM := -100.0 # random yaw
const MERGED := ["well", "threshing_floor", "beehives", "spring_basin"]

var island: Island
var rng := RandomNumberGenerator.new()
var counts := {}
var grass_excl := PackedByteArray()
var grass_boost := PackedByteArray()
var outcrops: Array = [] # Vector2 centres of the granite outcrops (goats like them)
## Sown wheat / barley beds for Grass, which grows them as rows of tall swaying stalks:
## {c: Vector2 centre, yaw, hx, hz (half extents along the contour / across it), barley: bool}.
var wheat_beds: Array = []

var _batches := {} # key -> {mesh, material, xforms: Array[Transform3D], shadow}
var _nature: Script
var _methods := {}
var _mesh_cache := {}
var _reserved: Array = [] # [Vector2 centre, radius]
var _trees: Array = [] # {p: Vector2, r, H, h0, fn}
var _hash := {} # Vector2i -> Array of [Vector2, r]
var _static_v := PackedVector3Array()
var _static_n := PackedVector3Array()
var _static_c := PackedColorArray()


func build(isl: Island, seed_value: int = 99) -> void:
	var t0 := Time.get_ticks_usec()
	island = isl
	rng.seed = seed_value
	_nature = load("res://scripts/gfx/models_nature.gd")
	for m in _nature.get_script_method_list():
		_methods[m["name"]] = true
	grass_excl.resize(GM_N * GM_N)
	grass_excl.fill(0)
	grass_boost.resize(GM_N * GM_N)
	grass_boost.fill(0)
	_reserve()
	_landmarks()
	_ruins()
	_temenos()
	_terraces()
	_field_walls()
	_village()
	_gully()
	_coast()
	_cliffs()
	_wild()
	_islet()
	_flowers()
	_place_beached_boats()
	island.commit_ground_map()
	_commit()
	_report(t0)


# --- bookkeeping -------------------------------------------------------------------------------------------

func _reserve() -> void:
	for fp in Landscape.FOOTPRINTS:
		_reserved.append([fp[0], fp[1]])
	_reserved.append([Landscape.HORN, 2.0])
	# The south pocket stays open meadow: night horn and spawn area.
	_reserved.append([Vector2(-4.5, 13.5), 3.0])


func _free_spot(x: float, z: float, extra: float = 0.0) -> bool:
	for r in _reserved:
		if Vector2(x, z).distance_to(r[0]) < r[1] + extra:
			return false
	return island.spot_sd_at(x, z) > 0.8 + extra and Vector2(x, z).length() > 9.0


func _lane_clear(x: float, z: float, margin: float) -> bool:
	return island.lane_dist_at(x, z) > LANE_W + 0.5 + margin


func _occ_key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 4.0)), int(floor(p.y / 4.0)))


func _occ_add(p: Vector2, r: float) -> void:
	var k := _occ_key(p)
	if not _hash.has(k):
		_hash[k] = []
	_hash[k].append([p, r])


## True when a circle (p, r) keeps dist >= k * (r + r2) + pad from everything placed.
func _occ_free(p: Vector2, r: float, k: float = 0.55, pad: float = 0.3) -> bool:
	var c := _occ_key(p)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var cell: Variant = _hash.get(Vector2i(c.x + dx, c.y + dz))
			if cell == null:
				continue
			for o in cell:
				if p.distance_to(o[0]) < k * (r + float(o[1])) + pad:
					return false
	return true


func _count(fn: String) -> void:
	counts[fn] = int(counts.get(fn, 0)) + 1


# --- meshes and materials ----------------------------------------------------------------------------------

func _mesh(fn: String, variant: int) -> Mesh:
	var key := "%s#%d" % [fn, variant]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m: Mesh = null
	# Species with kinds take kind = seed % N (N = 2 or 3): this seed makes the kind equal to the variant.
	var seed_value := 61 * variant + 60
	if _methods.has(fn):
		m = _nature.call(fn, seed_value)
	elif FALLBACK.has(fn) and _methods.has(FALLBACK[fn][0]):
		m = _scaled_mesh(_nature.call(FALLBACK[fn][0], seed_value), float(FALLBACK[fn][1]))
	else:
		m = _fallback_mesh(fn, variant)
	_mesh_cache[key] = m
	return m


func _scaled_mesh(src: Mesh, k: float) -> Mesh:
	if src == null or src.get_surface_count() == 0 or is_equal_approx(k, 1.0):
		return src
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] *= k
		arrays[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Simple stand-ins for the structures and crops (used only until the species file provides them).
func _fallback_mesh(fn: String, variant: int) -> Mesh:
	var mb := MeshBuilder.new(variant + 3)
	mb.vary = 0.03
	var r := RandomNumberGenerator.new()
	r.seed = 77 + variant
	match fn:
		"wheat_patch":
			for i in 14:
				var p := Vector3(r.randf_range(-1.4, 1.4), 0.0, r.randf_range(-1.2, 1.2))
				mb.ico(p + Vector3(0, 0.25, 0), 0.42, Pal.GRASS_DRY.lerp(Pal.GOLD, r.randf() * 0.4), 0, 0.15, Vector3(1.0, 0.75, 1.0))
		"grapevine_row":
			for i in 5:
				var x := -2.0 + i * 1.0
				mb.limb(Vector3(x, 0, 0), Vector3(x, 1.0, 0), 0.03, 0.03, 4, Pal.WOOD_DARK, false)
				mb.ico(Vector3(x, 0.7, 0), 0.38, Color("6E9440"), 0, 0.15, Vector3(1.2, 0.8, 0.9))
		"threshing_floor":
			mb.cyl(Vector3(0, -0.1, 0), 0.16, 3.2, 3.2, 18, Pal.LIMESTONE_DARK, true, 0.0, Pal.LIMESTONE)
			for i in 22:
				var a := TAU * i / 22.0
				mb.ico(Vector3(cos(a) * 3.3, 0.05, sin(a) * 3.3), 0.24, Pal.ROCK, 0, 0.15, Vector3(1.2, 0.6, 1.0))
		"well":
			mb.cyl(Vector3.ZERO, 0.75, 0.75, 0.72, 10, Pal.LIMESTONE, true, 0.0, Pal.LIMESTONE_DARK)
			mb.limb(Vector3(-0.7, 0.6, 0), Vector3(-0.7, 1.8, 0), 0.06, 0.06, 4, Pal.WOOD, false)
			mb.limb(Vector3(0.7, 0.6, 0), Vector3(0.7, 1.8, 0), 0.06, 0.06, 4, Pal.WOOD, false)
			mb.limb(Vector3(-0.8, 1.8, 0), Vector3(0.8, 1.8, 0), 0.06, 0.06, 4, Pal.WOOD, false)
		"spring_basin":
			mb.block(Vector3(0, -0.1, 0), Vector3(2.0, 0.55, 1.3), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
			mb.block(Vector3(0, 0.38, 0), Vector3(1.7, 0.08, 1.0), Pal.AEGEAN_LIGHT)
		"beehives":
			mb.block(Vector3(0, 0, 0), Vector3(2.2, 0.35, 0.7), Pal.ROCK_DARK, Pal.ROCK)
			for i in 3:
				mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.7 + i * 0.7, 0.58, -0.4)))
				mb.cyl(Vector3.ZERO, 0.8, 0.24, 0.22, 7, Pal.TERRACOTTA, true)
				mb.pop()
		_:
			mb.ico(Vector3(0, 0.3, 0), 0.4, Pal.ROCK if fn.contains("rock") else Pal.GRASS_DARK, 0, 0.2)
	return mb.commit()


func _material(fn: String) -> Material:
	var name := fn
	if not _methods.has(fn) and FALLBACK.has(fn):
		name = FALLBACK[fn][0]
	if not _methods.has(fn) and fn in ["grapevine_row", "wheat_patch"]:
		return Materials.static_twin(Materials.foliage(0.03))
	if _methods.has("material_for"):
		return Materials.static_twin(_nature.call("material_for", name))
	return Materials.static_twin(Materials.lowpoly())


func _casts_shadow(fn: String) -> bool:
	if _methods.has("casts_shadow") and _methods.has(fn):
		return _nature.call("casts_shadow", fn)
	return not (fn in NO_SHADOW)


func _add(fn: String, variant: int, xf: Transform3D) -> void:
	var key := "%s#%d" % [fn, variant]
	if not _batches.has(key):
		_batches[key] = {"mesh": _mesh(fn, variant), "material": _material(fn), "xforms": [], "shadow": _casts_shadow(fn)}
	_batches[key]["xforms"].append(xf)
	_count(fn)


## Ground transform: yaw, scale, optional lean (radians toward a world XZ direction) and extra tilt.
func _xf(x: float, z: float, yaw: float, sc: Vector3, lean_dir: Vector2 = Vector2.ZERO, lean: float = 0.0, sink: float = 0.05, tilt: Vector3 = Vector3.ZERO) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis.from_euler(tilt) * Basis.from_scale(sc)
	if lean != 0.0 and lean_dir.length_squared() > 0.0:
		var axis := Vector3.UP.cross(Vector3(lean_dir.x, 0, lean_dir.y)).normalized()
		b = Basis(axis, lean) * b
	return Transform3D(b, Vector3(x, island.height_at(x, z) - sink, z))


## Merges a single non-swaying landmark into the static mesh.
func _static(fn: String, variant: int, x: float, z: float, yaw: float, sc: float = 1.0, sink: float = 0.03) -> void:
	var m := _mesh(fn, variant)
	_count(fn)
	if m == null:
		return
	var xf := _xf(x, z, yaw, Vector3.ONE * sc, Vector2.ZERO, 0.0, sink)
	for s in m.get_surface_count():
		var arrays := m.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var col: Variant = arrays[Mesh.ARRAY_COLOR]
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var order := PackedInt32Array()
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			order = idx
		else:
			order.resize(v.size())
			for i in v.size():
				order[i] = i
		for i in order:
			_static_v.append(xf * v[i])
			_static_n.append((xf.basis * nrm[i]).normalized() if nrm.size() > i else Vector3.UP)
			_static_c.append((col as PackedColorArray)[i] if col is PackedColorArray and (col as PackedColorArray).size() > i else Color.WHITE)


# --- ground map and grass mask -----------------------------------------------------------------------------

func _gm_splat(excl: bool, a: Vector2, b: Vector2, R: float, v: int, r_in: float = -1.0) -> void:
	if R <= 0.0 or v <= 0:
		return
	var tx0 := maxi(0, int(floor((minf(a.x, b.x) - R + GM_EXT) / GM_RES)))
	var tx1 := mini(GM_N - 1, int(ceil((maxf(a.x, b.x) + R + GM_EXT) / GM_RES)))
	var tz0 := maxi(0, int(floor((minf(a.y, b.y) - R + GM_EXT) / GM_RES)))
	var tz1 := mini(GM_N - 1, int(ceil((maxf(a.y, b.y) + R + GM_EXT) / GM_RES)))
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 1e-6)
	for tz in range(tz0, tz1 + 1):
		var pz := (tz + 0.5) * GM_RES - GM_EXT
		for tx in range(tx0, tx1 + 1):
			var px := (tx + 0.5) * GM_RES - GM_EXT
			var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / l2, 0.0, 1.0)
			var d := Vector2(px - a.x - ab.x * t, pz - a.y - ab.y * t).length()
			if d > R or d < r_in:
				continue
			var i := tz * GM_N + tx
			if excl:
				if v > grass_excl[i]:
					grass_excl[i] = v
			elif v > grass_boost[i]:
				grass_boost[i] = v


## Grass mask at a point: x = exclusion (0..1), y = boost (0..1).
func grass_mask_at(x: float, z: float) -> Vector2:
	var tx := int(floor((x + GM_EXT) / GM_RES))
	var tz := int(floor((z + GM_EXT) / GM_RES))
	if tx < 0 or tz < 0 or tx >= GM_N or tz >= GM_N:
		return Vector2.ZERO
	var i := tz * GM_N + tx
	return Vector2(grass_excl[i] / 255.0, grass_boost[i] / 255.0)


# --- generic placement -------------------------------------------------------------------------------------

## [canopy radius, height, crown base, trunk obstacle, AO strength] at scale 1: measured by the species file when
## it has the model (ModelsNature.info), else the landscape spec's nominal sizes.
func _dims(fn: String) -> Array:
	if _methods.has("info") and _methods.has(fn):
		var d: Dictionary = _nature.call("info", fn)
		return [float(d.get("r", 1.0)), float(d.get("h", 2.0)), float(d.get("h0", 0.5)), float(d.get("obstacle", 0.3)), float(d.get("ao", 0.35))]
	var t: Array = Landscape.TREES.get(fn, [1.5, 3.0, 1.0, 0.4])
	return [t[0], t[1], t[2], t[3], 0.45 if fn == "plane_tree" else 0.35]


func _shrub_r(fn: String) -> float:
	if _methods.has("info") and _methods.has(fn):
		return float((_nature.call("info", fn) as Dictionary).get("r", 0.5))
	return float(Landscape.SHRUBS.get(fn, 0.5))


## Gameplay-camera occlusion: a tall tree hides the ground north of it from the camera. That strip must not
## contain a lane, a build spot or the plaza.
func _occludes(x: float, z: float, r: float, H: float, h0: float) -> String:
	var xx := x - r
	while xx <= x + r + 0.01:
		var zz := z - r - TAN52 * H
		while zz <= z + r - TAN52 * h0 + 0.01:
			if island.lane_dist_at(xx, zz) < 2.1:
				return "lane"
			if island.spot_sd_at(xx, zz) < 0.0:
				return "spot"
			if xx * xx + zz * zz < 7.5 * 7.5:
				return "plaza"
			zz += 0.5
		xx += 0.5
	return ""


func _tree_ok(fn: String, x: float, z: float, sc: float, beach: bool = false) -> bool:
	var dim := _dims(fn)
	var r: float = dim[0] * sc
	if island.lane_dist_at(x, z) < r + 1.6 or island.spot_sd_at(x, z) < 0.6 * r:
		return false
	if island.height_at(x, z) < (0.35 if beach else 1.2) or Vector2(x, z).length() < 8.8:
		return false
	if island.slope_at(x, z) > 0.3:
		return false
	if not _occ_free(Vector2(x, z), r, 0.55, 0.3) or not _free_spot(x, z, -0.6):
		return false
	if float(dim[1]) * sc > 2.5 and _occludes(x, z, r, float(dim[1]) * sc, float(dim[2]) * sc) != "":
		return false
	return true


## Places a tree (checked against the rules unless `force`): AO under the canopy, grass skirt around it.
func _tree(fn: String, x: float, z: float, sc: float, force: bool = false, yaw: float = RANDOM, lean_deg: float = 0.0, lean_dir: Vector2 = Vector2(0, 1), beach: bool = false, variants: int = 2, variant: int = -1) -> bool:
	if not force and not _tree_ok(fn, x, z, sc, beach):
		return false
	var dim := _dims(fn)
	var r: float = dim[0] * sc
	var yw := yaw if yaw > RANDOM + 1.0 else rng.randf() * TAU
	_add(fn, variant if variant >= 0 else rng.randi() % variants, _xf(x, z, yw, Vector3.ONE * sc, lean_dir, deg_to_rad(lean_deg), 0.06))
	var p := Vector2(x, z)
	_trees.append({"p": p, "r": r, "H": float(dim[1]) * sc, "h0": float(dim[2]) * sc, "fn": fn})
	_occ_add(p, r)
	if float(dim[3]) > 0.0:
		Obstacles.add(Vector3(x, island.height_at(x, z), z), float(dim[3]) * clampf(sc, 0.85, 1.3), self)
	island.splat_ao(p, r * 1.1, dim[4])
	_gm_splat(true, p, p, 0.6 * r, 128)
	_gm_splat(true, p, p, 0.45, 255)
	_gm_splat(false, p, p, r + 1.2, 255, r + 0.2)
	return true


func _shrub_ok(fn: String, x: float, z: float, sc: float, pack: float = 0.8) -> bool:
	var r: float = _shrub_r(fn) * sc
	if island.lane_dist_at(x, z) < LANE_W + 1.2 + r or island.spot_sd_at(x, z) < 0.6 + r:
		return false
	if island.height_at(x, z) < 0.3 or island.slope_at(x, z) > 0.35 or Vector2(x, z).length() < 9.0:
		return false
	return _occ_free(Vector2(x, z), r, pack, 0.05) and _free_spot(x, z, -0.5)


## Shrubs, cushions, flower patches: AO by kind, grass excluded under the cushion. `pack` < 0.8 lets cushions
## touch (phrygana grows as a mosaic of cushions, not as evenly spaced dots).
func _shrub(fn: String, x: float, z: float, sc: float, variant: int = -1, check: bool = true, variants: int = 3, pack: float = 0.8) -> bool:
	if check and not _shrub_ok(fn, x, z, sc, pack):
		return false
	var r: float = _shrub_r(fn) * sc
	var v := variant if variant >= 0 else rng.randi() % variants
	_add(fn, v, _xf(x, z, rng.randf() * TAU, Vector3.ONE * sc, Vector2.ZERO, 0.0, 0.04))
	var p := Vector2(x, z)
	_occ_add(p, r)
	if fn == "thyme_cushion":
		island.splat_ao(p, r * 1.3, 0.25)
	elif not fn.begins_with("flowers") and fn != "sea_lily" and fn != "grass_tuft":
		island.splat_ao(p, r * 1.15, 0.30)
	if not fn.begins_with("flowers") and fn != "grass_tuft":
		_gm_splat(true, p, p, 0.8 * r, 255)
	return true


func _rock(fn: String, x: float, z: float, sc: float, sink: float = 0.05, tilt: Vector3 = Vector3.ZERO, obstacle: float = 0.0) -> void:
	var r := (0.95 if fn == "rock_large" else 0.45) * sc
	_add(fn, rng.randi() % 3, _xf(x, z, rng.randf() * TAU, Vector3.ONE * sc, Vector2.ZERO, 0.0, sink, tilt))
	var p := Vector2(x, z)
	_occ_add(p, r)
	island.splat_ao(p, r + 0.4, 0.5)
	_gm_splat(true, p, p, r + 0.05, 255)
	_gm_splat(false, p, p, r + 0.8, 255, r)
	if obstacle > 0.0:
		Obstacles.add(Vector3(x, island.height_at(x, z), z), obstacle, self)


## A wall segment of `length` metres centred on p along the unit tangent t; its front (+Z) faces `front`.
## Follows the ground along its length (roll) and gets AO in front, no grass under it, a grass skirt before it.
func _wall(fn: String, p: Vector2, t: Vector2, front: Vector2, length: float, nominal: float, sy: float = 1.0, base_y: float = NAN) -> void:
	var yaw := atan2(-t.y, t.x)
	var fz := Vector2(sin(yaw), cos(yaw))
	if fz.dot(front) < 0.0:
		yaw += PI
	var a := p - t * length * 0.5
	var b := p + t * length * 0.5
	var ha := island.height_at(a.x, a.y)
	var hb := island.height_at(b.x, b.y)
	var y := island.height_at(p.x, p.y) - 0.08 if is_nan(base_y) else base_y
	var lx := Vector2(cos(yaw), -sin(yaw))
	var roll := atan2(hb - ha, length) * (1.0 if lx.dot(t) > 0.0 else -1.0)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll) * Basis.from_scale(Vector3(length / nominal, sy, 1.0))
	_add(fn, rng.randi() % 3, Transform3D(basis, Vector3(p.x, y, p.y)))
	var off := front.normalized() * 0.35
	island.splat_ao(a + off, 0.75, 0.45, b + off)
	_gm_splat(true, a, b, 0.4, 255)
	var f2 := front.normalized() * 0.9
	_gm_splat(false, a + f2, b + f2, 0.55, 255)


## Points every `step` (+- jitter) metres along a polyline, starting `start` metres in: [[p, tangent], ...].
func _walk(pts: PackedVector2Array, step: float, jitter: float, start: float) -> Array:
	var out: Array = []
	var next := start
	var acc := 0.0
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var b := pts[k]
		var l := a.distance_to(b)
		if l < 1e-4:
			continue
		while next <= acc + l:
			var t := (next - acc) / l
			out.append([a.lerp(b, t), (b - a) / l])
			next += step + rng.randf_range(-jitter, jitter)
		acc += l
	return out


## Point at arc length s on a polyline and the chord direction over `span` metres around it.
func _at_s(pts: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for k in range(1, pts.size()):
		var l := pts[k - 1].distance_to(pts[k])
		if s <= acc + l:
			return pts[k - 1].lerp(pts[k], (s - acc) / maxf(l, 1e-4))
		acc += l
	return pts[pts.size() - 1]


# --- landmarks ---------------------------------------------------------------------------------------------

func _landmarks() -> void:
	# Village: the great plane tree shading the well, cypress N marker, fig at the herm corner.
	_tree("plane_tree", 2.8, -14.2, 1.0, true, 0.6, 0.0, Vector2.ZERO, false, 1)
	var w := Landscape.WELL
	_static("well", 0, w.x, w.y, atan2(-w.x, -w.y))
	Obstacles.add(Vector3(w.x, island.height_at(w.x, w.y), w.y), 0.8, self)
	island.splat_wear(w, 1.6, 0.45)
	island.splat_ao(w, 1.3, 0.35)
	_gm_splat(true, w, w, 1.6, 255)
	_tree("oleander", 3.9, -10.6, 0.9, true)
	_tree("cypress", -2.7, -15.7, 1.0, true)
	_tree("fig_tree", -7.0, 16.0, 1.0, true, RANDOM, 0.0, Vector2.ZERO, false, 1)
	_tree("cypress", -8.7, 20.0, 0.95, true)
	_tree("pomegranate", Landscape.POMEGRANATE_W.x, Landscape.POMEGRANATE_W.y, 1.0, true, RANDOM, 0.0, Vector2.ZERO, false, 1)
	# Lane markers.
	_tree("cypress", 20.3, -0.4, 1.0, true)
	_tree("cypress", Landscape.CYPRESS_S.x, Landscape.CYPRESS_S.y, 1.0, true)
	# The spring: basin, a plane tree overhanging it, beehives with a windbreak.
	var sp := Landscape.SPRING
	_static("spring_basin", 0, sp.x, sp.y, 0.95)
	island.splat_wear(sp, 1.6, 0.45)
	_gm_splat(true, sp, sp, 1.5, 255)
	Obstacles.add(Vector3(sp.x, island.height_at(sp.x, sp.y), sp.y), 0.9, self)
	_tree("plane_tree", Landscape.SPRING_PLANE.x, Landscape.SPRING_PLANE.y, 0.8, true, 2.2, 0.0, Vector2.ZERO, false, 1)
	var bh := Landscape.BEEHIVES
	_static("beehives", 0, bh.x, bh.y, 0.52)
	island.splat_wear(bh, 1.2, 0.3)
	island.splat_ao(bh, 1.3, 0.3)
	_gm_splat(true, bh, bh, 1.5, 255)
	var wb := bh + Vector2(0, -1.2)
	var tng := Vector2(cos(0.52), -sin(0.52))
	_wall("stone_fence", wb, tng, Vector2(0, 1), 1.6, 3.0)
	# Threshing floor (aloni) on the NW shoulder, an almond towards the plaza.
	var th := Landscape.THRESHING
	_static("threshing_floor", 0, th.x, th.y, rng.randf() * TAU)
	for k in 28:
		var a := TAU * k / 28.0
		island.splat_wear(th + Vector2.from_angle(a) * 3.6, 0.7, 0.35)
	island.splat_ao(th, 3.4, 0.12)
	_gm_splat(true, th, th, 3.6, 255)
	var al := th + (-th).normalized() * 4.5
	_tree("almond_tree", al.x, al.y, 1.0)
	# Specimen old olives.
	for p in [Vector2(3.0, -32.0), Vector2(32.0, -7.0), Vector2(-30.0, 6.0), Vector2(-23.0, 33.5)]:
		_tree("olive_tree", p.x, p.y, rng.randf_range(1.35, 1.45), true, RANDOM, 0.0, Vector2.ZERO, false, 3)
	# Holm oaks.
	for p in [Vector2(-33, -33), Vector2(-40, -22), Vector2(35, -14), Vector2(-30, 26)]:
		_tree("holm_oak", p.x, p.y, rng.randf_range(0.95, 1.1), true)
	# Aleppo pines on the headlands, leaning with the meltemi.
	for p in [Vector2(-40, -39), Vector2(7, -42), Vector2(-32, 18)]:
		_tree("aleppo_pine", p.x, p.y, rng.randf_range(0.95, 1.1), true, rng.randf_range(-0.3, 0.3), rng.randf_range(8.0, 14.0))
	# Tamarisks behind the beaches.
	for p in [Vector2(-2.0, 47.8), Vector2(15.0, 44.8), Vector2(18.6, 44.2), Vector2(36.9, 1.0), Vector2(36.3, -3.6), Vector2(-31.9, 0.9), Vector2(-34.5, -14.8), Vector2(-48.5, -24.5), Vector2(-2.2, -39.4), Vector2(-16.4, -36.4), Vector2(-20.6, -38.6)]:
		# The mesh already leans 5-8 deg towards +Z: keep the yaw near 0 so all of them lean south.
		_tree("tamarisk", p.x, p.y, rng.randf_range(0.9, 1.1), true, rng.randf_range(-0.35, 0.35), 0.0 if _methods.has("tamarisk") else 5.0, Vector2(0, 1), true)


func _ruins() -> void:
	# The fallen temple in the sanctuary, a toppled column on the west hill and the roadside herm.
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
	var hm := Landscape.HERM
	if island.height_at(hm.x, hm.y) > 1.0:
		_place_at("herm_shrine", 0, hm.x, hm.y, 0.2, 1.0, 0.5)


func _place_at(fn: String, variant: int, x: float, z: float, yaw: float, sc: float = 1.0, obstacle_r: float = 0.0) -> void:
	var y := island.height_at(x, z)
	_add(fn, variant, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(x, y - 0.05, z)))
	var p := Vector2(x, z)
	_reserved.append([p, maxf(obstacle_r, 1.0) + 0.6])
	_occ_add(p, maxf(obstacle_r, 0.8))
	if fn.begins_with("ruin"):
		island.splat_ao(p, maxf(obstacle_r, 1.0) + 0.6, 0.4)
		_gm_splat(true, p, p, maxf(obstacle_r, 0.8), 255)
	if obstacle_r > 0.0:
		Obstacles.add(Vector3(x, y, z), obstacle_r, self)


## Sanctuary: a cypress grove behind the temple, the sacred basin with Leto's palm, laurels and the ruined
## enclosure wall (peribolos).
func _temenos() -> void:
	for p in [Vector2(18.0, -32.1), Vector2(19.0, -29.0), Vector2(22.0, -33.3), Vector2(23.0, -30.2), Vector2(26.1, -34.5), Vector2(27.0, -31.5)]:
		_tree("cypress", p.x, p.y, rng.randf_range(0.95, 1.12), true)
	var sb := Landscape.SACRED_BASIN
	_static("spring_basin", 1, sb.x, sb.y, 0.3, 1.3)
	island.splat_wear(sb, 1.8, 0.35)
	_gm_splat(true, sb, sb, 1.8, 255)
	Obstacles.add(Vector3(sb.x, island.height_at(sb.x, sb.y), sb.y), 1.1, self)
	var palm := Vector2(30.4, -24.0)
	# The palm's mesh leans 6 deg towards +Z: yaw it towards the sacred basin.
	var to_b := (sb - palm).normalized()
	_tree("date_palm", palm.x, palm.y, 1.0, true, atan2(to_b.x, to_b.y), 0.0 if _methods.has("date_palm") else 6.0, to_b, false, 1)
	for p in [Vector2(32.5, -27.0), Vector2(14.5, -28.5), Vector2(18.5, -36.5)]:
		_tree("laurel_tree", p.x, p.y, rng.randf_range(0.9, 1.05), true)
	# Peribolos: 3 m segments along the rectangle, kept only on good ground (a ruined enclosure).
	var hx := Landscape.TEMENOS_HALF.x
	var hz := Landscape.TEMENOS_HALF.y
	var sides := [[Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(0, -1)], [Vector2(-hx, hz), Vector2(hx, hz), Vector2(0, 1)], [Vector2(-hx, -hz), Vector2(-hx, hz), Vector2(-1, 0)], [Vector2(hx, -hz), Vector2(hx, hz), Vector2(1, 0)]]
	var c := cos(Landscape.TEMENOS_YAW)
	var s := sin(Landscape.TEMENOS_YAW)
	var walls := 0
	for side in sides:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var out: Vector2 = side[2]
		var L := a.distance_to(b)
		var n := int(floor(L / 3.0))
		for k in n:
			var lp := a.lerp(b, (k + 0.5) / n)
			var p := Landscape.temenos_point(lp.x, lp.y)
			var ang := Island.angle_of(p.x, p.y)
			var dco := island.coast_at(ang) - p.length()
			if island.spot_sd_at(p.x, p.y) <= 2.5 or dco <= 3.5 or island.height_at(p.x, p.y) <= 1.2:
				continue
			var t := (b - a).normalized()
			var wt := Vector2(c * t.x + s * t.y, -s * t.x + c * t.y)
			var wo := Vector2(c * out.x + s * out.y, -s * out.x + c * out.y)
			_wall("stone_fence", p, wt, wo, L / n - 0.15, 3.0, 0.85)
			walls += 1
			# Thyme at the wall foot.
			for j in 1 + rng.randi() % 2:
				var q := p + wt * rng.randf_range(-1.2, 1.2) - wo * rng.randf_range(0.7, 1.1)
				_shrub("thyme_cushion", q.x, q.y, rng.randf_range(0.8, 1.1), _thyme_variant())
	counts["temenos_walls"] = walls


func _thyme_variant() -> int:
	var u := rng.randf()
	return 0 if u < 0.55 else (1 if u < 0.85 else 2)


# --- terraces ----------------------------------------------------------------------------------------------

func _terraces() -> void:
	var walls := 0
	# Dry-stone risers: a 3 m segment every 3 m along each run, front facing downhill.
	for pts in island.riser_runs():
		var L := Island.polyline_length(pts)
		var s := 0.0
		while s < L - 0.4:
			var seg := minf(3.0, L - s)
			if seg < 1.5:
				break
			var a := _at_s(pts, s)
			var b := _at_s(pts, s + seg)
			var p := (a + b) * 0.5
			var t := (b - a).normalized()
			if t.length_squared() < 0.5:
				s += seg
				continue
			var down := island.downhill_at(p.x, p.y)
			var base_y := island.height_at(p.x + down.x * 0.5, p.y + down.y * 0.5) - 0.12
			var top_y := island.height_at(p.x - down.x * 0.6, p.y - down.y * 0.6) + 0.10
			var nominal := _mesh("terrace_wall", 0).get_aabb().size
			var nom_h := nominal.y if _methods.has("terrace_wall") else 0.75
			var sy := clampf((top_y - base_y) / maxf(nom_h, 0.3), 0.6, 1.5)
			_wall("terrace_wall", p, t, down, seg, 3.0 if not _methods.has("terrace_wall") else maxf(nominal.x, 1.0), sy, base_y)
			walls += 1
			s += 3.0
	counts["terrace_wall_segments"] = walls
	# T_N: olive rows, one per bench, ~6 m apart, each tree on a soil basin.
	_olive_rows(Landscape.T_N, 9, 6.0)
	# T_E: vineyard on the benches, wheat on the lowest.
	_vine_rows(Landscape.T_E, 8)
	_wheat(Landscape.T_E, 3, true)
	# T_W: wheat and barley strips, a few olives on the downhill edges, the old olive in the wheat.
	_wheat(Landscape.T_W, 12, false)
	var olives_w := 0
	for pts in island.bench_lines(Landscape.T_W, 0.08):
		for pt in _walk(pts, 9.0, 1.0, 3.0):
			var p: Vector2 = pt[0]
			if olives_w < 3 and _tree("olive_tree", p.x, p.y, rng.randf_range(0.85, 1.05), false, RANDOM, 0.0, Vector2.ZERO, false, 3):
				island.splat_wear(p, 1.0, 0.8)
				olives_w += 1
	# T_SW: vines high up, olives in the middle, barley on the lowest bench.
	_vine_rows(Landscape.T_SW, 10)
	_wheat(Landscape.T_SW, 4, false)
	_olive_rows(Landscape.T_SW, 4, 6.0)
	# T_SE: the kepos (orchard) fed by the spring: fig, almond, pomegranate repeating along the benches.
	var seq := ["fig_tree", "almond_tree", "pomegranate"]
	var caps := {"fig_tree": 3, "almond_tree": 3, "pomegranate": 2}
	var placed := {"fig_tree": 0, "almond_tree": 0, "pomegranate": 0}
	var orchard: Array[Vector2] = []
	var si := 0
	# The SE fields are crowded with build spots, so scan the contour rows densely and keep every legal spot.
	for frac in [0.39, 0.89]:
		for pts in island.bench_lines(Landscape.T_SE, frac, 0.0):
			for pt in _walk(pts, 1.0, 0.0, 0.5):
				var p: Vector2 = pt[0]
				var near := false
				for q in orchard:
					if q.distance_to(p) < 4.5:
						near = true
				if near:
					continue
				for tries in 3:
					var fn: String = seq[si % 3]
					si += 1
					if placed[fn] >= caps[fn]:
						continue
					if _tree(fn, p.x, p.y, rng.randf_range(0.85, 1.05), false, RANDOM, 0.0, Vector2.ZERO, false, 2):
						island.splat_wear(p, 1.0, 0.6)
						placed[fn] += 1
						orchard.append(p)
						break
	counts["orchard_trees"] = orchard.size()
	_wheat(Landscape.T_SE, 2, false, true)
	# T_N top bench by the well: a small garden.
	_tree("fig_tree", 6.5, -17.5, 1.0, true, RANDOM, 0.0, Vector2.ZERO, false, 1)
	_tree("almond_tree", -1.5, -19.5, 1.0, true, RANDOM, 0.0, Vector2.ZERO, false, 1)
	# Flowers: poppies along the downhill edge of the wheat benches, anemones between the olives.
	var drifts := 0
	for pts in island.bench_lines(Landscape.T_W, 0.10):
		for pt in _walk(pts, 7.0, 2.0, 2.5):
			var p: Vector2 = pt[0]
			if drifts < 8 and _drift("flowers_poppy", p, rng.randi_range(3, 5), 1.2, 0.9):
				drifts += 1
	drifts = 0
	for pts in island.bench_lines(Landscape.T_N, 0.39):
		for pt in _walk(pts, 6.0, 0.4, 5.0):
			var p: Vector2 = pt[0]
			if drifts < 4 and _drift("flowers_anemone", p, rng.randi_range(3, 5), 1.0, 0.8):
				drifts += 1


func _olive_rows(blk: int, target: int, step: float) -> void:
	var n := 0
	for pts in island.bench_lines(blk, 0.39):
		if Island.polyline_length(pts) < 4.0:
			continue
		for pt in _walk(pts, step, 0.6, 2.0 + rng.randf() * 2.0):
			var p: Vector2 = pt[0]
			if n >= target or island.crop_at(p.x, p.y) != Landscape.CROP_OLIVE:
				continue
			if _tree("olive_tree", p.x, p.y, rng.randf_range(0.85, 1.1), false, RANDOM, 0.0, Vector2.ZERO, false, 3):
				island.splat_wear(p, 1.0, 0.8)
				n += 1
	counts["olive_rows_%s" % Landscape.BLOCK_NAMES[blk]] = n


## Bush vines on stakes in two rows per bench, tiled along the contour with small gaps.
func _vine_rows(blk: int, target: int) -> void:
	var n := 0
	var seg_len := 4.0
	if _methods.has("grapevine_row"):
		seg_len = maxf(_mesh("grapevine_row", 0).get_aabb().size.x, 1.5)
	for frac in [0.18, 0.60]:
		for pts in island.bench_lines(blk, frac):
			var L := Island.polyline_length(pts)
			var s := 0.6
			while s + seg_len <= L and n < target:
				var a := _at_s(pts, s)
				var b := _at_s(pts, s + seg_len)
				var p := (a + b) * 0.5
				var ok := true
				for q in [a, p, b]:
					if island.crop_at(q.x, q.y) != Landscape.CROP_VINE or island.lane_dist_at(q.x, q.y) < 4.0 or island.spot_sd_at(q.x, q.y) < 1.5 or island.terrace_w_at(q.x, q.y) < 0.5:
						ok = false
				if ok and _occ_free(p, 0.5, 1.0, 0.0):
					var t := (b - a).normalized()
					var down := island.downhill_at(p.x, p.y)
					var yaw := atan2(-t.y, t.x)
					if Vector2(sin(yaw), cos(yaw)).dot(down) < 0.0:
						yaw += PI
					_add("grapevine_row", [0, 0, 1, 2][rng.randi() % 4], _xf(p.x, p.y, yaw, Vector3(a.distance_to(b) / seg_len, 1.0, 1.0), Vector2.ZERO, 0.0, 0.04))
					island.splat_wear(a, 0.25, 0.7, b)
					island.splat_ao(a, 0.55, 0.2, b)
					_gm_splat(true, a, b, 0.4, 255)
					n += 1
					s += seg_len + 0.4
				else:
					s += 1.0
	counts["vine_rows_%s" % Landscape.BLOCK_NAMES[blk]] = n


## Wheat / barley patches along the bench centre lines (3 m pitch) where the bench is wide enough.
func _wheat(blk: int, target: int, lowest_only: bool, widest_only: bool = false) -> void:
	var n := 0
	var lines: Array = island.bench_lines(blk, 0.39)
	if widest_only:
		var best: Variant = null
		var best_g := INF
		for pts in lines:
			if Island.polyline_length(pts) < 6.0:
				continue
			var g := 0.0
			for q in pts:
				g += island.grad_at(q.x, q.y)
			g /= pts.size()
			if g < best_g:
				best_g = g
				best = pts
		lines = [] if best == null else [best]
	var lowest := int(island.block_lowest.get(blk, -99))
	for pts in lines:
		var L := Island.polyline_length(pts)
		var s := 1.5
		while s + 1.5 <= L and n < target:
			var p := _at_s(pts, s)
			var a := _at_s(pts, s - 1.4)
			var b := _at_s(pts, s + 1.4)
			var g := island.grad_at(p.x, p.y)
			var ok := g <= 0.17 and island.lane_dist_at(p.x, p.y) > 5.5 and island.spot_sd_at(p.x, p.y) > 2.5
			if lowest_only and island.bench_level_at(p.x, p.y) > lowest + 1:
				ok = false
			if not lowest_only and blk != Landscape.T_SE and island.crop_at(p.x, p.y) != Landscape.CROP_WHEAT:
				ok = false
			for q in [a, b]:
				if island.terrace_w_at(q.x, q.y) < 0.5 or island.lane_dist_at(q.x, q.y) < 5.0:
					ok = false
			if ok and _occ_free(p, 1.2, 1.0, 0.0):
				var t := (b - a).normalized()
				var yaw := atan2(-t.y, t.x) + deg_to_rad(rng.randf_range(-3.0, 3.0))
				# Fit the bed to the bench: 0.39 m of height per bench, 0.8 m clear of the walls.
				var avail := 0.78 * Landscape.TERRACE_STEP / maxf(g, 0.03) - 1.0
				var sz := clampf(avail / 2.5, 0.55, 1.0)
				_sow(p, yaw, 1.45, 1.2 * sz, blk == Landscape.T_SW or rng.randf() < 0.3)
				n += 1
				s += 3.0
			else:
				s += 1.0
	counts["wheat_%s" % Landscape.BLOCK_NAMES[blk]] = int(counts.get("wheat_%s" % Landscape.BLOCK_NAMES[blk], 0)) + n


## A sown bed (wheat or barley) for Grass: centre, contour yaw and half extents. Splats soil and a little AO and
## keeps the meadow grass out of it.
func _sow(p: Vector2, yaw: float, hx: float, hz: float, barley: bool) -> void:
	var t := Vector2(cos(yaw), -sin(yaw))
	var a := p - t * (hx - hz * 0.5)
	var b := p + t * (hx - hz * 0.5)
	wheat_beds.append({"c": p, "yaw": yaw, "hx": hx, "hz": hz, "barley": barley})
	_count("wheat_patch")
	# A footprint-only batch, so code that reads the layout from _batches (the ambient animals) still sees the
	# beds; Grass draws them, _commit skips it.
	if not _batches.has("wheat_patch#0"):
		var box := BoxMesh.new()
		box.size = Vector3(2.0 * hx, 0.6, 2.4)
		_batches["wheat_patch#0"] = {"mesh": box, "material": null, "xforms": [], "shadow": false, "virtual": true}
	_batches["wheat_patch#0"]["xforms"].append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 1.0, hz / 1.2)), Vector3(p.x, island.height_at(p.x, p.y), p.y)))
	_occ_add(p, minf(hx, 1.4))
	island.splat_ao(a, hz * 1.05, 0.12, b)
	island.splat_field(a, hz * 1.15, 0.9, b)
	_gm_splat(true, a, b, hz * 1.08, 255)


## Field walls round the outer edge of the terraced blocks (they keep the goats out), with gates.
func _field_walls() -> void:
	var n := 0
	for pts: PackedVector2Array in island.terrace_edge_lines(0.5):
		# Split into runs on the outer boundary, away from lanes and spots.
		var runs: Array = []
		var cur := PackedVector2Array()
		for q in pts:
			var radial := q.normalized()
			var outer := island.terrace_w_at(q.x + radial.x, q.y + radial.y) < island.terrace_w_at(q.x - radial.x, q.y - radial.y)
			var ok := outer and island.lane_dist_at(q.x, q.y) > 4.0 and island.spot_sd_at(q.x, q.y) > 1.5 and island.slope_at(q.x, q.y) < 0.22
			if ok:
				cur.append(q)
			else:
				if cur.size() > 1:
					runs.append(cur)
				cur = PackedVector2Array()
		if cur.size() > 1:
			runs.append(cur)
		for run in runs:
			var L := Island.polyline_length(run)
			if L < 6.0:
				continue
			var s := 0.3
			var since_gate := rng.randf_range(4.0, 10.0)
			while s + 1.5 <= L and n < 24:
				if since_gate >= 15.0:
					s += 1.5
					since_gate = 0.0
					continue
				var seg := minf(3.0, L - s)
				if seg < 1.5:
					break
				var a := _at_s(run, s)
				var b := _at_s(run, s + seg)
				var p := (a + b) * 0.5
				var t := (b - a).normalized()
				if t.length_squared() > 0.5:
					_wall("stone_fence", p, t, p.normalized(), a.distance_to(b), 3.0)
					n += 1
				s += seg
				since_gate += seg
	counts["field_wall_segments"] = n


# --- village, gully, coast, cliffs, wild -------------------------------------------------------------------

func _flower_ok(x: float, z: float) -> bool:
	return island.spot_sd_at(x, z) >= 2.0 and island.lane_dist_at(x, z) >= LANE_W + 2.5 and island.height_at(x, z) > 1.2 and island.slope_at(x, z) < 0.22 and _free_spot(x, z, -0.5)


## A drift of `count` patches around c (radius grows with the count), spaced `spacing` apart.
func _drift(fn: String, c: Vector2, count: int, spacing: float, sc: float = 1.0, ok: Callable = Callable()) -> bool:
	var check := ok if ok.is_valid() else _flower_ok
	if not check.call(c.x, c.y):
		return false
	var radius := spacing * sqrt(float(count)) * 0.7
	var made := 0
	var tries := count * 12
	while made < count and tries > 0:
		tries -= 1
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		if not check.call(p.x, p.y):
			continue
		var r: float = _shrub_r(fn) * sc
		if not _occ_free(p, r, 0.8, 0.0):
			continue
		_shrub(fn, p.x, p.y, sc * rng.randf_range(0.85, 1.15), -1, false)
		made += 1
	return made > 0


func _zone_points(zone_id: int, n: int, ok: Callable, ext: float = 64.0) -> Array:
	var out: Array = []
	var tries := n * 80
	while out.size() < n and tries > 0:
		tries -= 1
		var p := Vector2(rng.randf_range(-ext, ext), rng.randf_range(-ext, ext))
		if island.zone_at(p.x, p.y) != zone_id:
			continue
		if ok.is_valid() and not ok.call(p.x, p.y):
			continue
		out.append(p)
	return out


func _village() -> void:
	var v_ok := func(x: float, z: float) -> bool: return Vector2(x, z).length() < 15.5 and Vector2(x, z).length() > 9.5
	var d := 0
	for p in _zone_points(Landscape.VILLAGE, 30, v_ok):
		if d < 3 and _drift("flowers_daisy", p, rng.randi_range(3, 5), 1.0):
			d += 1
	for p in _zone_points(Landscape.VILLAGE, 20, v_ok):
		if _drift("flowers_poppy", p, rng.randi_range(3, 5), 1.0):
			break


func _gully() -> void:
	var glen := Landscape.gully_length()
	# Oleanders in a chain along the stream, alternating banks.
	var s := 2.5
	var side := 1.0
	var n := 0
	while s <= 19.0 and n < 14:
		var g: Array = Landscape.gully_point(s)
		var c: Vector2 = g[0]
		var dir: Vector2 = g[1]
		var right := Vector2(-dir.y, dir.x)
		var p := c + right * side * rng.randf_range(1.6, 2.2)
		if island.slope_at(p.x, p.y) <= 0.3 and _occ_free(p, 0.8, 0.6, 0.1):
			_tree("oleander", p.x, p.y, rng.randf_range(0.8, 1.05), true)
			n += 1
		side = -side
		s += 2.4 + rng.randf_range(-0.4, 0.4)
	# Figs on the banks and a pomegranate by the basin.
	for f in [[4.0, 1.0], [8.5, -1.0]]:
		var g: Array = Landscape.gully_point(f[0])
		var p: Vector2 = (g[0] as Vector2) + Vector2(-(g[1] as Vector2).y, (g[1] as Vector2).x) * float(f[1]) * 2.6
		if not _tree("fig_tree", p.x, p.y, rng.randf_range(0.9, 1.05)):
			_tree("fig_tree", p.x, p.y, 0.9, true)
	var pg := Landscape.SPRING + Vector2(-2.2, 1.4)
	_tree("pomegranate", pg.x, pg.y, 0.9, not _tree_ok("pomegranate", pg.x, pg.y, 0.9))
	# Giant reeds on the inside of the bends, low down.
	var k := 0
	for sr in [12.5, 14.4, 16.6, 18.4]:
		var g: Array = Landscape.gully_point(sr)
		var g2: Array = Landscape.gully_point(minf(sr + 1.5, glen))
		var d1: Vector2 = g[1]
		var d2: Vector2 = g2[1]
		var turn := 1.0 if d1.x * d2.y - d1.y * d2.x >= 0.0 else -1.0
		var p: Vector2 = (g[0] as Vector2) + Vector2(-d1.y, d1.x) * turn * rng.randf_range(1.0, 1.4)
		_add("giant_reed", k % 2, _xf(p.x, p.y, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.85, 1.1), Vector2.ZERO, 0.0, 0.05))
		_occ_add(p, 0.5)
		_gm_splat(true, p, p, 0.5, 255)
		k += 1
	# Flowers on the banks.
	var bank_ok := func(x: float, z: float) -> bool:
		var gs := island.gully_at(x, z)
		return gs.x > 1.2 and gs.x < 3.6 and island.slope_at(x, z) < 0.3
	for f in [["flowers_anemone", 5.5], ["flowers_anemone", 11.0], ["flowers_poppy", 2.0]]:
		var g: Array = Landscape.gully_point(f[1])
		var dir: Vector2 = g[1]
		var p: Vector2 = (g[0] as Vector2) + Vector2(-dir.y, dir.x) * (2.8 if rng.randf() < 0.5 else -2.8)
		_drift(f[0], p, 3, 0.8, 0.9, bank_ok)
	# The pebble cove at the mouth.
	for j in 3:
		var g: Array = Landscape.gully_point(glen - 0.8 - j * 0.9)
		var dir: Vector2 = g[1]
		var p: Vector2 = (g[0] as Vector2) + Vector2(-dir.y, dir.x) * (1.8 if j % 2 == 0 else -2.0)
		if j < 2:
			_rock("beach_rock", p.x, p.y, rng.randf_range(0.7, 0.95), 0.08)
		else:
			_add("driftwood", 0, _xf(p.x, p.y, rng.randf() * TAU, Vector3.ONE, Vector2.ZERO, 0.0, 0.05))


func _beach_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	var ang := Island.angle_of(x, z)
	return h > 0.1 and h < 0.9 and island.beach_weight(ang) > 0.4 and island.spot_sd_at(x, z) > 1.5


func _coast() -> void:
	# Junipers beside the tamarisks, one or two per beach, clear of the landing.
	var groups := [[Vector2(-2.0, 47.8), 1], [Vector2(36.6, -1.3), 1], [Vector2(-33.2, -7.0), 2], [Vector2(-18.5, -37.5), 1]]
	for g in groups:
		var c: Vector2 = g[0]
		var made := 0
		for t in 60:
			if made >= int(g[1]):
				break
			var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.5, 6.0)
			if island.lane_dist_at(p.x, p.y) > 5.0 and _juniper(p, true):
				made += 1
	# Sea lilies on the sand in small groups.
	var lily_ok := func(x: float, z: float) -> bool:
		var h := island.height_at(x, z)
		return h > 0.5 and h < 1.1 and island.lane_dist_at(x, z) > 4.0 and island.zone_at(x, z) in [Landscape.BEACH, Landscape.DUNE] and island.spot_sd_at(x, z) > 1.5
	var lilies := 0
	var groups_made := 0
	for p in _zone_points(Landscape.BEACH, 40, lily_ok, 64.0):
		if lilies >= 30:
			break
		var k := rng.randi_range(3, 6)
		for j in k:
			var q: Vector2 = p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.6)
			if lily_ok.call(q.x, q.y) and _occ_free(q, 0.3, 0.8, 0.0):
				_shrub("sea_lily", q.x, q.y, rng.randf_range(0.85, 1.15), -1, false, 2)
				lilies += 1
		groups_made += 1
	# Beach rocks, keeping the landings open.
	var placed := 0
	var tries := 0
	while placed < 20 and tries < 2000:
		tries += 1
		var x := rng.randf_range(-66, 66)
		var z := rng.randf_range(-66, 66)
		if not _beach_ok(x, z) or island.lane_dist_at(x, z) < 5.0 or not _occ_free(Vector2(x, z), 0.8, 1.0, 1.0):
			continue
		_rock("beach_rock", x, z, rng.randf_range(0.7, 1.3), 0.08)
		placed += 1
	placed = 0
	tries = 0
	while placed < 9 and tries < 2000:
		tries += 1
		var x := rng.randf_range(-66, 66)
		var z := rng.randf_range(-66, 66)
		if not _beach_ok(x, z) or island.lane_dist_at(x, z) < 2.8 or not _occ_free(Vector2(x, z), 1.0, 1.0, 1.5):
			continue
		_add("driftwood", rng.randi() % 2, _xf(x, z, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.9, 1.2), Vector2.ZERO, 0.0, 0.05))
		_occ_add(Vector2(x, z), 1.0)
		placed += 1


## Wind-clipped juniper streaming south (yaw +-25 deg around the meltemi).
func _juniper(p: Vector2, beach: bool = false) -> bool:
	var sc := rng.randf_range(0.85, 1.15)
	if not _tree_ok("juniper", p.x, p.y, sc, beach):
		return false
	return _tree("juniper", p.x, p.y, sc, true, deg_to_rad(rng.randf_range(-25.0, 25.0)), 0.0, Vector2.ZERO, beach, 2, 2 if beach else rng.randi() % 2)


func _cliff_ok(x: float, z: float) -> bool:
	var h := island.height_at(x, z)
	var ang := Island.angle_of(x, z)
	return h > -0.6 and h < 3.0 and island.beach_weight(ang) < 0.2 and island.slope_at(x, z) > 0.18 and _free_spot(x, z) and _lane_clear(x, z, 3.0)


func _cliff_top_ok(x: float, z: float) -> bool:
	var ang := Island.angle_of(x, z)
	var dco := island.coast_at(ang) - Vector2(x, z).length()
	return dco > 3.0 and dco < 9.0 and island.slope_at(x, z) < 0.2 and island.lane_dist_at(x, z) > 6.0 and island.beach_weight(ang) < 0.3 and island.height_at(x, z) > 1.0


func _cliffs() -> void:
	# Boulders on the cliffs in small groups (one big, one or two smaller leaning on it), with bare rock between.
	var placed := 0
	var tries := 0
	while placed < 30 and tries < 3000:
		tries += 1
		var x := rng.randf_range(-66, 66)
		var z := rng.randf_range(-66, 66)
		if not _cliff_ok(x, z) or not _occ_free(Vector2(x, z), 1.0, 1.0, 2.5):
			continue
		var sc := rng.randf_range(1.0, 1.5)
		_rock("rock_large", x, z, sc, 0.1, Vector3.ZERO, 1.0 * sc)
		placed += 1
		for j in rng.randi_range(1, 2):
			var q := Vector2(x, z) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.3, 1.9) * sc
			var s2 := sc * rng.randf_range(0.45, 0.7)
			if _cliff_ok(q.x, q.y) and _occ_free(q, 0.95 * s2, 0.7, 0.0):
				_rock("rock_large", q.x, q.y, s2, 0.1, Vector3.ZERO, 0.9 * s2)
				placed += 1
	# Junipers on the cliff tops, headlands first, singles or pairs at least 12 m apart.
	var junipers: Array[Vector2] = []
	var cands: Array[Vector2] = []
	for a: float in [160.0, 231.0]:
		for k in 30:
			var ang := a + rng.randf_range(-8.0, 8.0)
			var r := island.coast_at(ang) - rng.randf_range(3.5, 8.0)
			cands.append(Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang))) * r)
	for k in 400:
		var ang := rng.randf() * 360.0
		var r := island.coast_at(ang) - rng.randf_range(3.5, 8.5)
		cands.append(Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang))) * r)
	for p in cands:
		if junipers.size() >= 8:
			break
		if not _cliff_top_ok(p.x, p.y):
			continue
		var far := true
		for q in junipers:
			if q.distance_to(p) < 12.0:
				far = false
		if not far:
			continue
		if _juniper(p):
			junipers.append(p)
			if rng.randf() < 0.4:
				var p2 := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.2, 3.0)
				if _cliff_top_ok(p2.x, p2.y):
					_juniper(p2)
	# Thyme on the flat cliff tops, in wind-pressed clumps of three to six.
	var thyme := 0
	tries = 0
	while thyme < 40 and tries < 3000:
		tries += 1
		var ang := rng.randf() * 360.0
		var r := island.coast_at(ang) - rng.randf_range(3.0, 9.0)
		var c := Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang))) * r
		if not _cliff_top_ok(c.x, c.y):
			continue
		var lead := _thyme_variant()
		for j in rng.randi_range(3, 6):
			var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 1.4)
			if _cliff_top_ok(p.x, p.y) and _shrub("thyme_cushion", p.x, p.y, rng.randf_range(0.7, 1.15), lead, true, 3, 0.62):
				thyme += 1


func _wild_ok(x: float, z: float) -> bool:
	return island.zone_at(x, z) == Landscape.WILD and island.lane_dist_at(x, z) > 4.0 and island.spot_sd_at(x, z) > 2.0


func _wild() -> void:
	# Granite outcrops on the 10 largest hummocks, half buried, with satellites.
	var hm: Array = island.hummocks.duplicate()
	hm.sort_custom(func(a, b): return float(a["r"]) * float(a["h"]) > float(b["r"]) * float(b["h"]))
	var drift_sites: Array = []
	for i in hm.size():
		var c: Vector2 = hm[i]["pos"]
		if i < 10:
			var sc := rng.randf_range(1.05, 1.5)
			var tilt := Vector3(deg_to_rad(rng.randf_range(-10, 10)), 0, deg_to_rad(rng.randf_range(-10, 10)))
			_rock("rock_large", c.x, c.y, sc, 0.35 * 1.45 * sc, tilt, 1.0 * sc)
			outcrops.append(c)
			for j in rng.randi_range(2, 4):
				var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.6, 2.8) * sc
				if island.lane_dist_at(p.x, p.y) > 3.5 and island.spot_sd_at(p.x, p.y) > 1.0:
					_rock("rock_small", p.x, p.y, rng.randf_range(0.7, 1.3), 0.08)
					_count("rock_small_satellite")
			# The lee (south) of an outcrop shelters a drift.
			drift_sites.append(c + Vector2(rng.randf_range(-1.0, 1.0), 3.8 * sc))
		else:
			drift_sites.append(c)
	# Phrygana: thyme / burnet / sage cushions in drifts on the hummocks and in the lee of outcrops. A drift is a
	# mosaic: big cushions packed in its core, smaller ones thinning out at the rim, one species leading, on a
	# patch of bare granite grit; open grassland between drifts.
	var thyme_drifts := 0
	for site in drift_sites:
		if thyme_drifts >= 12:
			break
		var n := rng.randi_range(12, 24)
		var made := 0
		var tries := n * 14
		var radius := rng.randf_range(2.6, 4.0)
		var lead := _thyme_variant()
		var flat := rng.randf_range(0.6, 0.9)
		var turn := rng.randf() * PI
		while made < n and tries > 0:
			tries -= 1
			var u := pow(rng.randf(), 0.8)
			var off := Vector2.from_angle(rng.randf() * TAU) * u * radius
			var p: Vector2 = site + Vector2(off.x, off.y * flat).rotated(turn)
			if not _wild_ok(p.x, p.y) and not _cliff_top_ok(p.x, p.y):
				continue
			var sc := lerpf(1.3, 0.62, u) * rng.randf_range(0.88, 1.12)
			var v := lead if rng.randf() < 0.7 else _thyme_variant()
			if _shrub("thyme_cushion", p.x, p.y, sc, v, true, 3, 0.62):
				made += 1
		if made > 0:
			thyme_drifts += 1
			island.splat_wear(site, radius * 0.75, 0.22)
			# Lavender next to some thyme drifts.
			if int(counts.get("lavender_drifts", 0)) < 6 and rng.randf() < 0.6:
				var lp: Vector2 = site + Vector2.from_angle(rng.randf() * TAU) * (radius + 1.0)
				if _drift("flowers_lavender", lp, rng.randi_range(3, 5), 1.0, 1.0, _wild_ok):
					counts["lavender_drifts"] = int(counts.get("lavender_drifts", 0)) + 1
	counts["thyme_drifts"] = thyme_drifts
	# Cistus along the fields-to-wild edge.
	var cistus_sites: Array[Vector2] = []
	var tries2 := 0
	while cistus_sites.size() < 9 and tries2 < 600:
		tries2 += 1
		var ang := rng.randf() * 360.0
		var rr := Landscape.r_out(ang, island.coast_at(ang)) + rng.randf_range(-1.0, 4.0)
		var c := Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang))) * rr
		var far := true
		for q in cistus_sites:
			if q.distance_to(c) < 10.0:
				far = false
		if not far or island.lane_dist_at(c.x, c.y) < 4.0 or island.spot_sd_at(c.x, c.y) < 2.5 or island.height_at(c.x, c.y) < 1.2:
			continue
		var k := rng.randi_range(3, 7)
		var made := 0
		for j in k * 6:
			if made >= k:
				break
			var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 2.6
			if island.terrace_w_at(p.x, p.y) > 0.3:
				continue
			if _shrub("cistus_shrub", p.x, p.y, rng.randf_range(0.8, 1.2), 0 if rng.randf() < 0.6 else 1):
				made += 1
		if made > 0:
			cistus_sites.append(c)
	# Spanish broom on south- or east-facing wild slopes, and two by the threshing floor.
	var broom_clumps := 0
	tries2 = 0
	while broom_clumps < 7 and tries2 < 1500:
		tries2 += 1
		var p := Vector2(rng.randf_range(-62, 62), rng.randf_range(-62, 62))
		if p.length() < 34.0 or not _wild_ok(p.x, p.y):
			continue
		var gz := island.hs_at(p.x, p.y + 0.7) - island.hs_at(p.x, p.y - 0.7)
		var gx := island.hs_at(p.x + 0.7, p.y) - island.hs_at(p.x - 0.7, p.y)
		if gz / 1.4 > -0.03 and gx / 1.4 > -0.03:
			continue
		var made := 0
		for j in 16:
			if made >= rng.randi_range(2, 4):
				break
			var q := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.2)
			if _wild_ok(q.x, q.y) and _shrub("broom_shrub", q.x, q.y, rng.randf_range(0.85, 1.2)):
				made += 1
		if made > 0:
			broom_clumps += 1
	for k in 2:
		var p := Landscape.THRESHING + Vector2.from_angle(rng.randf_range(2.0, 4.0) + k * 1.4) * 5.0
		_shrub("broom_shrub", p.x, p.y, 1.0)
	# Maquis: lentisk, myrtle and kermes domes in clumps on the headlands, and at each holm oak.
	var sectors := [[205.0, 250.0, 40.0, 4], [100.0, 125.0, 38.0, 2], [290.0, 345.0, 38.0, 2]]
	for sec in sectors:
		var clumps := 0
		for t in 300:
			if clumps >= int(sec[3]):
				break
			var ang := rng.randf_range(sec[0], sec[1])
			var rr := rng.randf_range(sec[2], island.coast_at(ang) - 3.0)
			var c := Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang))) * rr
			if not _wild_ok(c.x, c.y) and not _cliff_top_ok(c.x, c.y):
				continue
			var made := 0
			for j in 20:
				if made >= rng.randi_range(3, 5):
					break
				var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.6)
				if _shrub("bush", q.x, q.y, rng.randf_range(0.8, 1.2)):
					made += 1
			if made > 0:
				clumps += 1
	for p in [Vector2(-33, -33), Vector2(-40, -22), Vector2(35, -14), Vector2(-30, 26)]:
		for j in rng.randi_range(1, 2):
			var q: Vector2 = p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.8, 3.6)
			_shrub("bush", q.x, q.y, rng.randf_range(0.8, 1.0))
	# Loose stones in small clusters across the hills.
	var clusters := 0
	tries2 = 0
	while clusters < 9 and tries2 < 1500:
		tries2 += 1
		var c := Vector2(rng.randf_range(-62, 62), rng.randf_range(-62, 62))
		if not _wild_ok(c.x, c.y) or not _occ_free(c, 1.0, 1.0, 1.5):
			continue
		for j in rng.randi_range(2, 4):
			var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.6, 1.8)
			if _wild_ok(q.x, q.y):
				_rock("rock_small", q.x, q.y, rng.randf_range(0.6, 1.3), 0.08)
		clusters += 1
	# Tufts at rock bases and on cliff tops.
	var tufts := 0
	tries2 = 0
	while tufts < 60 and tries2 < 2000:
		tries2 += 1
		var p: Vector2
		if outcrops.size() > 0 and rng.randf() < 0.6:
			p = outcrops[rng.randi() % outcrops.size()] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.3, 2.6)
		else:
			var ang := rng.randf() * 360.0
			p = Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang))) * (island.coast_at(ang) - rng.randf_range(3.0, 8.0))
			if not _cliff_top_ok(p.x, p.y):
				continue
		if island.lane_dist_at(p.x, p.y) < 4.0 or island.spot_sd_at(p.x, p.y) < 2.0 or not _occ_free(p, 0.25, 1.0, 0.0):
			continue
		_add("grass_tuft", rng.randi() % 3, _xf(p.x, p.y, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.6, 0.8), Vector2.ZERO, 0.0, 0.03))
		_occ_add(p, 0.25)
		tufts += 1


func _islet() -> void:
	var c := Landscape.ISLET
	for k in 3:
		var p := c + Vector2.from_angle(k * 2.1 + 0.4) * rng.randf_range(1.0, 3.0)
		_rock("rock_large", p.x, p.y, rng.randf_range(0.9, 1.3), 0.15)
	for k in 8:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 4.0)
		if island.height_at(p.x, p.y) > 0.6 and island.slope_at(p.x, p.y) < 0.3:
			_shrub("thyme_cushion", p.x, p.y, rng.randf_range(0.8, 1.1), _thyme_variant(), false)
	var jp := c + Vector2(-1.5, 1.2)
	if island.height_at(jp.x, jp.y) > 0.8:
		_tree("juniper", jp.x, jp.y, 0.8, true, deg_to_rad(rng.randf_range(-25.0, 25.0)), 0.0, Vector2.ZERO, false, 2, 1)


func _flowers() -> void:
	# Open meadow (fields not terraced): daisies, and poppies in the damp hollows.
	var meadow_ok := func(x: float, z: float) -> bool: return _flower_ok(x, z) and island.terrace_w_at(x, z) < 0.3 and island.zone_at(x, z) == Landscape.FIELDS
	var d := 0
	for p in _zone_points(Landscape.FIELDS, 60, meadow_ok):
		if d < 5 and _drift("flowers_daisy", p, rng.randi_range(4, 7), 1.0, 1.0, meadow_ok):
			d += 1
	d = 0
	for ho in island.hollows:
		var c: Vector2 = ho["pos"]
		if d < 3 and _drift("flowers_poppy", c, rng.randi_range(5, 9), 1.0):
			d += 1
	# Sanctuary: anemones and a drift of daisies.
	var tem_ok := func(x: float, z: float) -> bool: return island.temenos_at(x, z) < 0.0 and _flower_ok(x, z)
	d = 0
	for p in _zone_points(Landscape.TEMENOS, 30, tem_ok):
		if d < 3 and _drift("flowers_anemone", p, rng.randi_range(3, 5), 0.9, 1.0, tem_ok):
			d += 1
	for p in _zone_points(Landscape.TEMENOS, 10, tem_ok):
		if _drift("flowers_daisy", p, 4, 1.0, 1.0, tem_ok):
			break


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


# --- commit and report -------------------------------------------------------------------------------------

func _commit() -> void:
	# Everything that neither sways nor flashes (rocks, walls, ruins, boats, jars) is baked into one mesh per
	# region of a 3 x 3 grid: a handful of draw calls instead of one per model variant, and the regions out of
	# view are culled.
	var still := Materials.static_twin(Materials.lowpoly())
	var regions := {} # Vector2i -> Array of [vertex, normal, colour arrays, Transform3D]
	for key in _batches:
		var b: Dictionary = _batches[key]
		if b.get("virtual", false) or b["material"] != still or not b["shadow"]:
			continue
		var m: Mesh = b["mesh"]
		var parts: Array = []
		for sidx in m.get_surface_count():
			var arrays := m.surface_get_arrays(sidx)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: Variant = arrays[Mesh.ARRAY_NORMAL]
			var col: Variant = arrays[Mesh.ARRAY_COLOR]
			if (idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0) or not (nrm is PackedVector3Array) or not (col is PackedColorArray):
				parts.clear()
				break
			if (nrm as PackedVector3Array).size() != v.size() or (col as PackedColorArray).size() != v.size():
				parts.clear()
				break
			parts.append([v, nrm, col])
		if parts.is_empty():
			continue # stays instanced
		for xf: Transform3D in b["xforms"]:
			var rk := Vector2i(clampi(int(floor((xf.origin.x + 16.0) / 32.0)) + 1, 0, 2), clampi(int(floor((xf.origin.z + 16.0) / 32.0)) + 1, 0, 2))
			if not regions.has(rk):
				regions[rk] = []
			for part in parts:
				(regions[rk] as Array).append([part[0], part[1], part[2], xf])
		b["baked"] = true
	for rk in regions:
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var pc := PackedColorArray()
		for e: Array in regions[rk]:
			var xf: Transform3D = e[3]
			pv.append_array(xf * (e[0] as PackedVector3Array))
			pn.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (e[1] as PackedVector3Array))
			pc.append_array(e[2])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pv
		arrays[Mesh.ARRAY_NORMAL] = pn
		arrays[Mesh.ARRAY_COLOR] = pc
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Stone_%d_%d" % [rk.x, rk.y]
		mi.mesh = am
		mi.material_override = still
		add_child(mi)
	for key in _batches:
		var b: Dictionary = _batches[key]
		if b.get("baked", false) or b.get("virtual", false):
			continue
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
	if not _static_v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _static_v
		arrays[Mesh.ARRAY_NORMAL] = _static_n
		arrays[Mesh.ARRAY_COLOR] = _static_c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Landmarks"
		mi.mesh = m
		mi.material_override = Materials.static_twin(Materials.lowpoly())
		add_child(mi)


func _report(t0: int) -> void:
	var tris := 0
	var trees := 0
	for key in _batches:
		var b: Dictionary = _batches[key]
		if b.get("virtual", false):
			continue
		var m: Mesh = b["mesh"]
		var t := 0
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			var idx: Variant = a[Mesh.ARRAY_INDEX]
			t += ((idx as PackedInt32Array).size() if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		tris += t * (b["xforms"] as Array).size()
	tris += _static_v.size() / 3
	var violations: Array = []
	for tr in _trees:
		trees += 1
		if float(tr["H"]) > 2.5:
			var p: Vector2 = tr["p"]
			var why := _occludes(p.x, p.y, tr["r"], tr["H"], tr["h0"])
			if why != "":
				violations.append("%s(%.1f,%.1f):%s" % [tr["fn"], p.x, p.y, why])
	var keys := counts.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [k, counts[k]])
	print("Props: %d trees, %d batches, %d tris, %d ms | %s" % [trees, _batches.size(), tris, (Time.get_ticks_usec() - t0) / 1000, ", ".join(parts)])
	if violations.size() > 0:
		print("Props: camera-occlusion violations: ", ", ".join(violations))
