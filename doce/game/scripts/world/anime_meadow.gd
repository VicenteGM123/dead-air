class_name AnimeMeadow
extends Node3D
## The anime meadow of Nemea (DOCE), after Trung Duy Nguyen's "Anime Grass" method (the client's reference):
##
##  1. SCATTER: low-poly grass clumps (MeadowKit.grass_clump, 20 triangles, pivot at the root) over the ground where
##     the grass mask is on (the terrain's grassiness, its ground map: paths, props, bare soil, and the meadow map),
##     random yaw, random scale MULTIPLIED by the mask through a smooth ramp, density falling off with the distance
##     from the camera, and 2-triangle camera-facing billboard clumps beyond. All on the GPU: three rings of
##     MultiMesh chunks on a fixed world grid round the camera (shaders/meadow_grass.gdshader; the billboards use the
##     same source built with MEADOW_CARDS); nothing is generated on the CPU after build(). (RINGS below.)
##       near   0.22 m cells, 5.3 m chunks, out to ~15 m      4 broad curved blades, 3 segments (20 triangles)
##       mid    0.45 m cells, 10.8 m chunks, ~8.5 -> ~40 m   billboards (2 triangles) painted with 26-40 blade clumps
##       far    1.0 m cells, 24 m chunks, ~31 -> ~80 m       the same billboards, wider
##     Beyond (and between the clumps) the ground itself is painted as the same grass (terrain.gdshader): the shaded
##     depth of the stand, darker where the view grazes it, with painted blade strokes (MeadowKit.ground_strokes).
##  2. THE KEY, "transfer vertex normal": the mound field (MeadowKit.mound_texture: cloud noise cut out into blobs,
##     blurred) tilts the normal of every clump AT ITS ROOT and of the ground under it, so grass and ground shade as
##     one surface with big hand-painted shadow shapes that follow the sun (shaders/meadow_lib.gdshaderinc).
##  3. Colour + value: two greens by the same blob pattern, the zone colour of the ground at the root, a cel ramp with
##     a chosen deep cool shadow colour, backlit tips.
##  4. Wind: one noise at the root (slow wave + fast noise, the shared wind of scripts/world/wind.gd) turns each clump
##     about its root and darkens it a little where it bends; the pushers (hero, beasts) part it.
##  5. Flowers: drifts of pink campion (the reference), red poppies on the dry margins and along the wheat field,
##     white chamomile and purple anemones (MeadowKit.flower_cluster, shaders/meadow_bloom.gdshader), raised to sit
##     on the grass, shaded and swayed like the clump they grow in; the drifts are also painted into the ground so
##     they still read where the flower instances have faded.
## The grass is drawn in the alpha list and writes stencil 32 so the toon ink lines stay off it.
##
## The meadow map (RGBA8, 2 m texels): R grass height (x MAX_HEIGHT), G density, B flower drift, A species
## (0 pink campion, 1/3 poppy, 2/3 chamomile, 1 anemone).
##
##   var m := AnimeMeadow.new(); add_child(m); m.build(world)     # world: World (terrain textures and fields)
## Debug args: grass=0 nothing, clumps=0 ground only, flowers=0, mound=0 (no mound normal), meadowk=<intensity>.

const L := preload("res://scripts/world/nemea_layout.gd")
const STENCIL := 32
const MAX_HEIGHT := 1.0
const MOUND_TILE := 40.0
const MOUND_K := 1.3

## FIXER: render order inside the alpha list goes FRONT TO BACK by ring ("prio" for the 3x3 chunks round the camera,
## "prio" + 1 for the outer ones; Godot sorts each priority back to front): the nearest grass is drawn first and the
## depth test rejects what it hides before it is shaded (the clumps have no discard: early depth rejection works).
const RINGS := [
	# FIXER (density): 0.25 -> 0.22 m cells and fuller clumps (4 broad, curved 3-segment blades: 20 triangles)
	{"name": "MeadowNear", "cell": 0.22, "cells": 24, "grid": 7, "lod": 0, "ring": Vector4(0.0, 0.0, 11.0, 15.0), "prio": -18, "width": 1.0, "dens_far": 0.75, "clump": [11, 4, 0.2, 0.5, 3, 0.16]},
	# FIXER (density): mid billboards denser (0.5 -> 0.45 m cells), a little wider, fading in from 8.5 m
	{"name": "MeadowMid", "cell": 0.45, "cells": 24, "grid": 7, "lod": 2, "ring": Vector4(8.5, 12.5, 33.0, 40.0), "prio": -16, "width": 1.25, "dens_far": 0.65},
	{"name": "MeadowFar", "cell": 1.0, "cells": 24, "grid": 7, "lod": 2, "ring": Vector4(31.0, 38.0, 68.0, 80.0), "prio": -14, "width": 1.6, "dens_far": 0.5},
]
## Flowers are baked (only real flowers are drawn): clusters scattered over the meadow map's drifts, grouped in
## static 24 m regions that fade out between 26 and 33 m (shader) and are culled beyond (visibility range).
const FLOWER_REGION := 24.0
const FLOWER_RING := Vector4(0.0, 0.0, 26.0, 33.0)
const FLOWER_DENSITY := 1.5 # clusters per m2 in a full drift

var world: Node3D
var terrain: RefCounted
var meadow_tex: ImageTexture
var meadow_img: Image
var mound_tex: ImageTexture
var instances := 0
var stats := {}
## Optional object with edge_poppies(x, z) -> float and in_field(x, z) -> float (the wheat field): poppies along its
## edges, no meadow grass inside it.
var field: Object = null

var _rings: Array = [] # [{def, size, nodes: Array[MultiMeshInstance3D], mat, cc: Vector2i}]
var _aabb_cache := {}
var _mats: Array[ShaderMaterial] = []


func build(w: Node3D) -> void:
	world = w
	if Game.arg("grass", "1") == "0":
		return
	terrain = w.get("terrain")
	if terrain == null:
		return
	var t0 := Time.get_ticks_usec()
	meadow_tex = _meadow_map()
	stats["meadow_map_ms"] = (Time.get_ticks_usec() - t0) / 1000
	var t1 := Time.get_ticks_usec()
	mound_tex = MeadowKit.mound_texture()
	stats["mound_ms"] = (Time.get_ticks_usec() - t1) / 1000
	_bind_terrain_material()
	if Game.arg("clumps", "1") != "0":
		# FIXER: the 3D clumps' program has no discard; the billboards' is built from the same source with MEADOW_CARDS
		var defs := PackedStringArray()
		if Game.arg("grassopaque", "0") == "1":
			defs.append("MEADOW_OPAQUE")
		var shader: Shader = MeadowKit.shader_variant("res://shaders/meadow_grass.gdshader", defs)
		var defs_bb := defs.duplicate()
		defs_bb.append("MEADOW_CARDS")
		var shader_bb: Shader = MeadowKit.shader_variant("res://shaders/meadow_grass.gdshader", defs_bb)
		var bb := MeadowKit.billboard_texture()
		for def0 in RINGS:
			var def := _ring_def(def0)
			var mesh: Mesh
			match int(def["lod"]):
				0:
					var cp: Array = def.get("clump", [11, 5, 0.13, 0.42, 2, 0.11])
					mesh = MeadowKit.grass_clump(int(cp[0]), int(cp[1]), float(cp[2]), float(cp[3]), int(cp[4]), float(cp[5]))
				1:
					mesh = MeadowKit.grass_clump(12, 3, 0.16, 0.42, 2, 0.12)
				_:
					# Trung: 2D billboard clumps beyond the near ring ("greatly improves performance")
					mesh = MeadowKit.billboard()
			var mat := ShaderMaterial.new()
			mat.shader = shader if int(def["lod"]) < 2 else shader_bb
			mat.render_priority = int(def["prio"])
			mat.set_shader_parameter("lod", float(def["lod"]))
			mat.set_shader_parameter("width_k", float(def["width"]))
			mat.set_shader_parameter("density_far", float(def["dens_far"]))
			mat.set_shader_parameter("bb_tex", bb)
			_add_ring(def, mesh, mat)
			stats["tris_" + String(def["name"])] = MeadowKit.tris(mesh)
	if Game.arg("flowers", "1") != "0":
		_build_flowers()
	_apply_quality()
	stats["instances"] = instances
	stats["build_ms"] = (Time.get_ticks_usec() - t0) / 1000


## Parameters every meadow material shares (terrain textures, meadow map, mound field).
func bind(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("height_tex", terrain.height_tex)
	mat.set_shader_parameter("color_tex", terrain.color_tex)
	mat.set_shader_parameter("ground_tex", terrain.ground_tex)
	mat.set_shader_parameter("meadow_tex", meadow_tex)
	var ext: float = terrain.EXT
	var gm_ext: float = terrain.GM_EXT
	mat.set_shader_parameter("grid", Vector4(-ext, -ext, float(terrain.CELL), float(terrain.N)))
	mat.set_shader_parameter("ground_rect", Vector4(-gm_ext, -gm_ext, gm_ext * 2.0, gm_ext * 2.0))
	mat.set_shader_parameter("meadow_rect", Vector4(-ext - 1.0, -ext - 1.0, ext * 2.0 + 2.0, ext * 2.0 + 2.0))
	mat.set_shader_parameter("max_height", MAX_HEIGHT)
	_bind_mound(mat)
	if not _mats.has(mat):
		_mats.append(mat)


func _bind_mound(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("mound_tex", mound_tex)
	mat.set_shader_parameter("mound_tile", MOUND_TILE)
	var k := float(Game.arg("meadowk", str(MOUND_K)))
	if Game.arg("mound", "1") == "0":
		k = 0.0
	mat.set_shader_parameter("mound_k", k)
	if Game.arg("mtile", "") != "":
		mat.set_shader_parameter("mound_tile", float(Game.arg("mtile")))
	if Game.arg("celmid", "") != "":
		mat.set_shader_parameter("cel_mid", float(Game.arg("celmid")))


## Lab overrides of a ring definition (look development): args r<n|m|f>_<key>=v, e.g. rn_cell=0.2, rm_ring=8,11,33,40,
## rn_clump=11,4,0.2,0.5,3,0.16 (seed, blades, width, comb, segs, spread).
func _ring_def(def0: Dictionary) -> Dictionary:
	var def := def0.duplicate()
	var pre := "r" + String(def["name"]).substr(6, 1).to_lower() + "_"
	for k in ["cell", "width", "dens_far"]:
		if Game.arg(pre + k, "") != "":
			def[k] = float(Game.arg(pre + k))
	for k in ["cells", "grid", "prio"]:
		if Game.arg(pre + k, "") != "":
			def[k] = int(Game.arg(pre + k))
	if Game.arg(pre + "ring", "") != "":
		var v := String(Game.arg(pre + "ring")).split(",")
		def["ring"] = Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	if Game.arg(pre + "clump", "") != "":
		var v := String(Game.arg(pre + "clump")).split(",")
		def["clump"] = [int(v[0]), int(v[1]), float(v[2]), float(v[3]), int(v[4]), float(v[5])]
	return def


## The ground under the meadow is painted as the same grass (terrain.gdshader's meadow path), with blade strokes.
func _bind_terrain_material() -> void:
	var tm := Materials.terrain()
	_bind_mound(tm)
	var t0 := Time.get_ticks_usec()
	tm.set_shader_parameter("stroke_tex", MeadowKit.ground_strokes())
	stats["strokes_ms"] = (Time.get_ticks_usec() - t0) / 1000
	tm.set_shader_parameter("meadow_tex", meadow_tex)
	var ext: float = terrain.EXT
	tm.set_shader_parameter("meadow_rect", Vector4(-ext - 1.0, -ext - 1.0, ext * 2.0 + 2.0, ext * 2.0 + 2.0))
	tm.set_shader_parameter("trung", 1.0)


func _add_ring(def: Dictionary, mesh: Mesh, mat: ShaderMaterial) -> void:
	var cell: float = def["cell"]
	var cells: int = def["cells"]
	var size := cell * cells
	var buf := PackedFloat32Array()
	buf.resize(cells * cells * 12)
	var k := 0
	for iz in cells:
		for ix in cells:
			var o := k * 12
			buf[o] = 1.0
			buf[o + 3] = (ix + 0.5) * cell
			buf[o + 5] = 1.0
			buf[o + 10] = 1.0
			buf[o + 11] = (iz + 0.5) * cell
			k += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cells * cells
	mm.buffer = buf
	bind(mat)
	mat.set_shader_parameter("spacing", cell)
	mat.set_shader_parameter("ring", def["ring"])
	# FIXER: the outer chunks draw after the inner 3x3 (front to back between groups, see RINGS)
	var mat_out := mat.duplicate() as ShaderMaterial
	mat_out.render_priority = mat.render_priority + 1
	bind(mat_out)
	var rv: Vector4 = def["ring"]
	var half_diag := size * 0.7072
	var nodes: Array[MultiMeshInstance3D] = []
	var g: int = def["grid"]
	var h := (g - 1) / 2
	for i in g * g:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [def["name"], i]
		mmi.multimesh = mm
		# grid index i = (dz + h) * g + (dx + h), as placed in _process()
		var inner := absi(i % g - h) <= 1 and absi(i / g - h) <= 1
		mmi.material_override = mat if inner else mat_out
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = rv.w + half_diag + 1.0
		mmi.visibility_range_end_margin = 2.0
		if rv.x - half_diag - 4.0 > 0.0:
			mmi.visibility_range_begin = rv.x - half_diag - 4.0
		add_child(mmi)
		nodes.append(mmi)
		instances += cells * cells
	_rings.append({"def": def, "size": size, "nodes": nodes, "mat": mat, "cc": Vector2i(1 << 20, 0)})


## Scatters flower clusters over the drifts of the meadow map (B strength, A species), skipping paths and the ground
## under props, and commits them as one static MultiMesh per 24 m region (custom data: species, random).
func _build_flowers() -> void:
	var t := terrain
	var img := meadow_img
	var n := img.get_width()
	var data := img.get_data()
	var gm: PackedByteArray = t.gm
	var gm_n: int = t.GM_N
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	var regions := {}
	var count := 0
	for iz in n:
		for ix in n:
			var o := (iz * n + ix) * 4
			var drift := data[o + 2] / 255.0
			if drift < 0.08 or data[o + 1] == 0:
				continue
			var k := drift * drift * FLOWER_DENSITY * 4.0
			var m := int(k) + (1 if rng.randf() < k - floorf(k) else 0)
			var species := float(data[o + 3]) / 255.0
			for j in m:
				var x := -192.0 + ix * 2.0 + rng.randf_range(-1.0, 1.0)
				var z := -192.0 + iz * 2.0 + rng.randf_range(-1.0, 1.0)
				if absf(x) > 190.0 or absf(z) > 190.0:
					continue
				if t.color_at(x, z).a < 0.35 or t.field(t.path_d, x, z) < 0.45:
					continue
				var gx := clampi(int((x + 192.0) * gm_n / 384.0), 0, gm_n - 1)
				var gz := clampi(int((z + 192.0) * gm_n / 384.0), 0, gm_n - 1)
				var go := (gz * gm_n + gx) * 4
				if gm[go + 3] > 90 or gm[go + 2] > 70:
					continue
				if field != null and float(field.call("in_field", x, z)) > 0.3:
					continue
				var rk := Vector2i(int(floor(x / FLOWER_REGION)), int(floor(z / FLOWER_REGION)))
				if not regions.has(rk):
					regions[rk] = PackedFloat32Array()
				var y: float = t.height_at(x, z)
				var buf: PackedFloat32Array = regions[rk]
				var yaw := rng.randf() * TAU
				var sc := rng.randf_range(0.85, 1.15)
				# identity basis (the shader turns and scales the cluster from the custom data: species, random, yaw, scale)
				buf.append_array([1.0, 0.0, 0.0, x - rk.x * FLOWER_REGION, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z - rk.y * FLOWER_REGION, species, rng.randf(), yaw / TAU, sc])
				regions[rk] = buf
				count += 1
	var mat := ShaderMaterial.new()
	mat.shader = MeadowKit.shader_variant("res://shaders/meadow_bloom.gdshader", PackedStringArray(["MEADOW_OPAQUE"]) if Game.arg("grassopaque", "0") == "1" else PackedStringArray())
	mat.render_priority = -19
	bind(mat)
	mat.set_shader_parameter("ring", FLOWER_RING)
	# FIXER: 9 bigger heads in a tight heap (was 16 small ones over 0.26 m: confetti)
	var mesh := MeadowKit.flower_cluster(11, 9, 0.17)
	stats["tris_flower"] = MeadowKit.tris(mesh)
	for rk in regions:
		var buf: PackedFloat32Array = regions[rk]
		var cnt := buf.size() / 16
		var lo := INF
		var hi := -INF
		for i in cnt:
			lo = minf(lo, buf[i * 16 + 7])
			hi = maxf(hi, buf[i * 16 + 7])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = cnt
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flowers_%d_%d" % [rk.x, rk.y]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.position = Vector3(rk.x * FLOWER_REGION, 0.0, rk.y * FLOWER_REGION)
		mmi.custom_aabb = AABB(Vector3(-1.0, lo - 1.0, -1.0), Vector3(FLOWER_REGION + 2.0, hi - lo + 3.0, FLOWER_REGION + 2.0))
		mmi.visibility_range_end = FLOWER_RING.w + FLOWER_REGION * 0.72 + 4.0
		mmi.visibility_range_end_margin = 2.0
		add_child(mmi)
	stats["flowers"] = count
	stats["flower_regions"] = regions.size()


func _apply_quality() -> void:
	var q := int(Settings.get_v("quality"))
	var k := 0.6 if q <= 0 else (0.85 if q == 1 else 1.0)
	for m in _mats:
		m.set_shader_parameter("density", k)


func _process(_delta: float) -> void:
	if _rings.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	for r in _rings:
		var size: float = r["size"]
		var cc := Vector2i(int(floor(cp.x / size)), int(floor(cp.z / size)))
		if cc == r["cc"]:
			continue
		r["cc"] = cc
		var g: int = (r["def"] as Dictionary)["grid"]
		var h := (g - 1) / 2
		var nodes: Array = r["nodes"]
		var k := 0
		for dz in range(-h, h + 1):
			for dx in range(-h, h + 1):
				var c := Vector2i(cc.x + dx, cc.y + dz)
				var mmi: MultiMeshInstance3D = nodes[k]
				k += 1
				var info := _chunk_info(c, size)
				mmi.visible = bool(info[1])
				mmi.position = Vector3(c.x * size, 0.0, c.y * size)
				mmi.custom_aabb = info[0]


## [local AABB, has grass] of the chunk at chunk coords c (cached).
func _chunk_info(c: Vector2i, size: float) -> Array:
	var key := Vector3i(c.x, c.y, int(size * 10.0))
	if _aabb_cache.has(key):
		return _aabb_cache[key]
	var x0 := c.x * size
	var z0 := c.y * size
	var n := clampi(int(ceil(size / 3.0)), 3, 20)
	var lo := INF
	var hi := -INF
	var grass := 0.0
	for j in n + 1:
		for i in n + 1:
			var x := x0 + size * float(i) / float(n)
			var z := z0 + size * float(j) / float(n)
			if absf(x) > 191.0 or absf(z) > 191.0:
				continue
			var y: float = terrain.height_at(x, z)
			lo = minf(lo, y)
			hi = maxf(hi, y)
			grass = maxf(grass, terrain.color_at(x, z).a)
	if lo == INF:
		lo = -1.0
		hi = 0.0
	var out := [AABB(Vector3(-1.5, lo - 1.5, -1.5), Vector3(size + 3.0, hi - lo + 4.0, size + 3.0)), grass > 0.02]
	_aabb_cache[key] = out
	return out


# --- the meadow map ----------------------------------------------------------------------------------------------

func _meadow_map() -> ImageTexture:
	var t := terrain
	var N: int = t.N
	var n := (N - 1) / 2 + 1 # 2 m texels on the terrain grid (vertex 2i)
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var nh := FastNoiseLite.new()
	nh.seed = 4101
	nh.frequency = 0.07
	nh.fractal_octaves = 2
	var nw := FastNoiseLite.new()
	nw.seed = 4102
	nw.frequency = 0.028
	nw.fractal_octaves = 2
	var nd := FastNoiseLite.new()
	nd.seed = 4103
	nd.frequency = 0.045
	nd.fractal_octaves = 3
	var ns := FastNoiseLite.new()
	ns.seed = 4104
	ns.frequency = 0.012
	ns.fractal_octaves = 1
	var col: PackedColorArray = t.col
	var fw: PackedFloat32Array = t.forest_w
	var dry: PackedFloat32Array = t.dry
	var pd: PackedFloat32Array = t.path_d
	var plaza: Vector2 = L.PLAZA
	for iz in n:
		var z := -192.0 + iz * 2.0
		for ix in n:
			var x := -192.0 + ix * 2.0
			var i := (iz * 2) * N + ix * 2
			var o := (iz * n + ix) * 4
			var g := col[i].a
			if g <= 0.0:
				data[o] = 90
				data[o + 1] = 0
				data[o + 2] = 0
				data[o + 3] = 0
				continue
			var f := fw[i]
			var dr := dry[i]
			var vil := smoothstep(54.0, 40.0, Vector2(x - plaza.x, (z - plaza.y) * 1.25).length())
			var near_path := 1.0 - smoothstep(0.5, 4.0, pd[i])
			# Height: a meadow of 35-55 cm, wild patches up to ~80 cm, short lawn in the village and along its lanes.
			var h := 0.5 + 0.09 * nh.get_noise_2d(x, z)
			var wild := smoothstep(0.18, 0.5, nw.get_noise_2d(x, z)) * (1.0 - vil) * (1.0 - f * 0.6) * (1.0 - near_path * 0.7)
			h = lerpf(h, 0.82, wild)
			h *= lerpf(1.0, 0.85, f)
			h = lerpf(h, 0.38, smoothstep(0.4, 0.85, dr))
			h = lerpf(h, 0.3, vil)
			h = lerpf(h, 0.22, vil * near_path)
			# Density: thinner in the forest's shade and on the stony garrigue.
			var dens := lerpf(1.0, 0.75, f) * lerpf(1.0, 0.72, smoothstep(0.5, 0.9, dr))
			# Flower drifts: pink campion in the green meadows, chamomile in the sunny patches, anemones at the forest
			# edges, poppies on the dry margins (and along the wheat field).
			var dv := nd.get_noise_2d(x, z)
			var drift := smoothstep(0.05, 0.36, dv) * (1.0 - f * 0.75) * (1.0 - vil * 0.5) * (1.0 - near_path * 0.3)
			var sv := ns.get_noise_2d(x + 300.0, z)
			# pink campion (the reference) is the meadows' flower; chamomile in a few sunny patches, anemones at the
			# forest edges, poppies on the dry margins
			# FIXER: pink campion dominates the green meadow (fewer anemones and chamomile patches)
			var species := 0
			if dr > 0.45 and dr < 0.75:
				species = 1
			elif f > 0.3 and f < 0.65 and sv < -0.12:
				species = 3
			elif sv > 0.46:
				species = 2
			if field != null:
				var inf: float = field.call("in_field", x, z)
				if inf > 0.0:
					# The wheat field: no meadow grass inside it (the wheat takes the ground).
					# (FIXER: the meadow grows right up to the wheat's edge, hiding the foot of the stand)
					dens *= 1.0 - smoothstep(0.42, 0.66, inf)
					drift *= 1.0 - inf
				var pp: float = field.call("edge_poppies", x, z)
				if pp > 0.05:
					species = 1
					drift = maxf(drift, pp)
			data[o] = int(clampf(h / MAX_HEIGHT, 0.0, 1.0) * 255.0)
			data[o + 1] = int(clampf(dens, 0.0, 1.0) * 255.0)
			data[o + 2] = int(clampf(drift, 0.0, 1.0) * 255.0)
			data[o + 3] = int(species * 85)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	meadow_img = img
	return ImageTexture.create_from_image(img)
