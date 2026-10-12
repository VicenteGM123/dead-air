class_name WheatField
extends Node3D
## The golden wheat field of Nemea ("Gladiator"): waist-high wheat on the west ramp, where the main road climbs from
## the forest's west edge to the plateau above the sea, so everyone walks through it, westwards, into the sunset.
## Built the smart way (no 100k stalks), with the meadow's principles (Trung Duy Nguyen's method, see
## shaders/meadow_lib.gdshaderinc and shaders/wheat_lib.gdshaderinc):
##
##  1. The ground under the wheat: the terrain painted as the field's shaded depths (dark olive gold), with the
##     field's bigger, softer mounds (terrain.gdshader, field_tex).
##  2. The ear CANOPY (shaders/wheat_canopy.gdshader): one mesh following the terrain over the field, lifted ~1 m,
##     painted with ears and awns (MeadowPaint.wheat_top), two golds mixed by the mound pattern plus a few greener
##     patches, lowered towards the field's edges, swayed and rolled by the big slow wind waves (lighter sheen on the
##     crests, darker troughs), pushed down and aside round the hero and the beasts, glowing when backlit.
##  3. EAR CLUMPS (MeadowKit.wheat_clump, shaders/wheat_ears.gdshader): 3D stalks with nodding ears and awns rising
##     out of the canopy near the camera (GPU rings on a fixed world grid like the meadow, density falling with
##     distance), parting round the hero, turning about their roots with the same wave.
##  4. EDGE CARDS (shaders/wheat_ears.gdshader, card mode): painted stands of wheat (MeadowPaint's wheat tiles) along
##     the field's border and the road's verges: the field's silhouette against the road, the sky and the meadow.
##  5. Around it: red poppies along the edges (AnimeMeadow reads edge_poppies()), a threshing floor and sheaves at
##     the north-west corner by the road, a low dry-stone wall on the south bank, a lone olive and two cypresses where
##     the road enters the field.
## Everything is drawn in the alpha list with stencil 32 (no ink lines), like the grass.
##
##   var f := WheatField.new(); f.setup(terrain)          # right after the terrain is generated (field map)
##   f.reserve(props); f.place_props(props)                # before props.build(): keep the scatter out, add the farm
##   add_child(f); f.build(world, meadow)                  # after the terrain textures exist
## Debug args: wheat=0 nothing, wheatears=0, wheatcards=0, canopy=0.

const L := preload("res://scripts/world/nemea_layout.gd")
const NemeaTerrain := preload("res://scripts/world/nemea_terrain.gd")
const TEXEL := 0.5 # field map resolution (m)
const MARGIN := 6.0
## The canopy (the layer of upper stalks and shaded ears) at CANOPY_H; the ears of the 3D clumps and of the cards
## stand 10-30 cm out of it: waist-high wheat (1.0-1.15 m) on the 1.9 m hero.
const CANOPY_H := 0.9
## Render order inside the alpha list (lower first: front to back, so the depth test rejects what is hidden):
## the 3D ear clumps, the canopy, the cards.
const EAR_RINGS := [
	# mode 0: 3D ear clumps near the camera (full size right to the field's edge)
	# (FIXER-2, density: 6 stalks a clump instead of 4, on a 5 x 5 grid of 5.76 m chunks instead of 7 x 7 of 4.8 m, which
	# still covers 11.5 m round the camera in every direction: 1.5x the ears for about the same triangles submitted)
	{"name": "WheatNear", "mode": 0, "cell": 0.24, "cells": 24, "grid": 5, "ring": Vector4(0.0, 0.0, 8.5, 12.0), "prio": -18, "dens_far": 0.6, "stalks": 6},
	# mode 2: camera-facing painted stands over the middle ring (the ears all over the field's top). FIXER (overdraw:
	# 4.5 fragments per pixel in the field): 0.55 -> 0.8 m cells with wider cards (1.35 m), from 10 m (where the 3D
	# clumps fade) instead of 7.5 m, and each card cropped to the band above the canopy (wheat_ears.gdshader)
	{"name": "WheatCards", "mode": 2, "cell": 0.9, "cells": 14, "grid": 9, "ring": Vector4(10.0, 12.0, 32.0, 40.0), "prio": -11, "dens_far": 0.5, "card_w": 1.35},
]

var terrain: RefCounted
var field_img: Image
var field_tex: ImageTexture
## Field map rect (x, z, width, depth) in metres.
var field_rect := Vector4.ZERO
var stats := {}
var instances := 0

var _w := 0
var _h := 0
var _data := PackedByteArray()
var _rings: Array = []
var _aabb_cache := {}
var _mats: Array[ShaderMaterial] = []
var _edge_noise := FastNoiseLite.new()
var _sheaf_spots: Array[Vector2] = []
## The stook of three sheaves leaning together, on the meadow just outside the field's north-west corner (clear of
## the road and of the wheat).
const STOOK := Vector2(-106.5, 31.0)


# --- layout (field map) ------------------------------------------------------------------------------------------

## The field map (RGBA8, TEXEL m) over the field's bounding box:
##   R  wheat weight 0..1 (a ragged edge; 0 on the road and its verges)
##   G  depth inside the field 0..1 (0 at the edge .. 1 at 6 m in): the canopy rises over the first metres
##   B  the road through the field (1 on the packed earth)
##   A  greener patches 0..1 (a few, soft)
func setup(t: RefCounted) -> void:
	terrain = t
	var t0 := Time.get_ticks_usec()
	_edge_noise.seed = 6061
	_edge_noise.frequency = 0.22
	_edge_noise.fractal_octaves = 2
	var green := FastNoiseLite.new()
	green.seed = 6062
	green.frequency = 0.045
	green.fractal_octaves = 2
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in L.WHEAT_FIELD:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lo -= Vector2(MARGIN, MARGIN)
	hi += Vector2(MARGIN, MARGIN)
	_w = int(ceil((hi.x - lo.x) / TEXEL))
	_h = int(ceil((hi.y - lo.y) / TEXEL))
	field_rect = Vector4(lo.x, lo.y, _w * TEXEL, _h * TEXEL)
	_data.resize(_w * _h * 4)
	var poly: Array = L.WHEAT_FIELD
	for iy in _h:
		var z := lo.y + (iy + 0.5) * TEXEL
		for ix in _w:
			var x := lo.x + (ix + 0.5) * TEXEL
			var sd := NemeaTerrain.poly_sd(x, z, poly) + _edge_noise.get_noise_2d(x, z) * 1.1
			var pd: float = t.field(t.path_d, x, z)
			var pw: float = t.field(t.path_w, x, z)
			var road := smoothstep(0.55, 0.85, pw)
			var w := smoothstep(0.45, -0.45, sd) * smoothstep(0.15, 0.75, pd + _edge_noise.get_noise_2d(x * 1.7, z * 1.7) * 0.25)
			var depth := clampf(-sd / 6.0, 0.0, 1.0) * smoothstep(0.0, 3.0, pd)
			var g := smoothstep(0.25, 0.65, green.get_noise_2d(x, z))
			var o := (iy * _w + ix) * 4
			_data[o] = int(clampf(w, 0.0, 1.0) * 255.0)
			_data[o + 1] = int(clampf(depth, 0.0, 1.0) * 255.0)
			_data[o + 2] = int(road * 255.0)
			_data[o + 3] = int(g * 255.0)
	field_img = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, _data)
	field_tex = ImageTexture.create_from_image(field_img)
	stats["field_map_ms"] = (Time.get_ticks_usec() - t0) / 1000
	stats["field_map"] = Vector2i(_w, _h)


## Wheat weight at (x, z), 0..1 (bilinear on the field map).
func in_field(x: float, z: float) -> float:
	return _sample(x, z, 0)


## FINAL: the height of the ears' tops above the ground at (x, z), m (0 off the field): the stalks' height
## (wheat_lib.gdshaderinc wheat_stalk_h) x the 3D clumps' mean scale (wheat_ears.gdshader: 1.12-1.3, ears included).
## Hero._feed_brush puts the free hand there.
func ear_top(x: float, z: float) -> float:
	var w := _sample(x, z, 0)
	var depth := _sample(x, z, 1)
	return CANOPY_H * lerpf(0.86, 1.0, smoothstep(0.0, 0.25, depth)) * smoothstep(0.4, 0.55, w) * 1.18


## Red poppies along the field's outer edge (a ragged band 0.5-3 m outside) and on the road's verges inside.
func edge_poppies(x: float, z: float) -> float:
	if field_rect.z == 0.0:
		return 0.0
	if x < field_rect.x - 4.0 or z < field_rect.y - 4.0 or x > field_rect.x + field_rect.z + 4.0 or z > field_rect.y + field_rect.w + 4.0:
		return 0.0
	var sd := NemeaTerrain.poly_sd(x, z, L.WHEAT_FIELD)
	var band := smoothstep(0.0, 1.0, sd) * smoothstep(4.5, 2.0, sd)
	var n := _edge_noise.get_noise_2d(x * 0.6 + 40.0, z * 0.6)
	return clampf(band * smoothstep(-0.2, 0.3, n), 0.0, 1.0)


func _sample(x: float, z: float, ch: int) -> float:
	if _w == 0:
		return 0.0
	var fx := (x - field_rect.x) / TEXEL - 0.5
	var fz := (z - field_rect.y) / TEXEL - 0.5
	if fx < 0.0 or fz < 0.0 or fx > _w - 1.0 or fz > _h - 1.0:
		return 0.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var ix1 := mini(ix + 1, _w - 1)
	var iz1 := mini(iz + 1, _h - 1)
	var a := _data[(iz * _w + ix) * 4 + ch]
	var b := _data[(iz * _w + ix1) * 4 + ch]
	var c := _data[(iz1 * _w + ix) * 4 + ch]
	var d := _data[(iz1 * _w + ix1) * 4 + ch]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz) / 255.0


# --- the farm (props) --------------------------------------------------------------------------------------------

## Keeps the scatter (trees, shrubs, rocks) out of the field: discs over its polygon.
func reserve(props: RefCounted) -> void:
	var poly: Array = L.WHEAT_FIELD
	var lo := Vector2(field_rect.x, field_rect.y)
	var hi := lo + Vector2(field_rect.z, field_rect.w)
	var z := lo.y
	var n := 0
	while z <= hi.y:
		var x := lo.x
		while x <= hi.x:
			if NemeaTerrain.poly_sd(x, z, poly) < 1.5:
				props.call("reserve", Vector2(x, z), 3.6)
				n += 1
			x += 4.5
		z += 4.5
	stats["reserved_discs"] = n


## The threshing floor and sheaves, the dry-stone wall on the south bank, the lone olive, two cypresses at the road's
## entry. Through the props (NemeaProps): collision, AO and the occlusion rules come with them.
func place_props(props: RefCounted) -> void:
	var t := terrain
	# threshing floor on the plateau by the road (flat ground), facing the field
	var tp: Vector2 = L.THRESHING
	var xf := Transform3D(Basis(Vector3.UP, 0.4), Vector3(tp.x, t.height_at(tp.x, tp.y) - 0.05, tp.y))
	props.call("place_mesh", "threshing_floor", 0, xf, false)
	props.call("reserve", tp, 4.2)
	# Its collision is its own triangles: the curb stones (0.2-0.3 m), the straw heap and the propped fork block, the
	# 6 cm floor stays walkable (a convex hull would lift the hero onto a 0.3 m disc). Physics layer 1 (the world).
	var fm: Variant = props.call("_mesh", "threshing_floor", 0)
	if fm is Mesh:
		var fb := StaticBody3D.new()
		fb.name = "ThreshingFloorBody"
		fb.collision_layer = 1
		fb.collision_mask = 0
		fb.transform = xf
		var fcs := CollisionShape3D.new()
		fcs.shape = (fm as Mesh).create_trimesh_shape()
		fb.add_child(fcs)
		add_child(fb)
	# a lone olive in the field (the wheat parts round it) and two cypresses where the road enters
	var ol: Vector2 = L.WHEAT_OLIVE
	props.call("tree", "olive_tree", ol.x, ol.y, 1.35, 0, true)
	for c: Vector2 in L.WHEAT_CYPRESSES:
		props.call("tree", "cypress", c.x, c.y, 1.15, -1, true)
	# a low dry-stone wall along the south bank (where the field drops towards the coast), in pieces
	var poly: Array = L.WHEAT_FIELD
	var walls := 0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var mid := (a + b) * 0.5
		if mid.y < 38.0:
			continue
		var seg := b - a
		var l := seg.length()
		var dir := seg / l
		var out := Vector2(dir.y, -dir.x)
		if NemeaTerrain.poly_sd(mid.x + out.x, mid.y + out.y, poly) < 0.0:
			out = -out
		var k := 0.0
		while k + 3.0 <= l:
			var p := a + dir * (k + 1.5) + out * 1.6
			# gaps: a ruined wall
			if fmod(k * 0.37 + float(i) * 1.3, 1.0) > 0.22:
				var yaw := atan2(-dir.y, dir.x)
				var wx := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, t.height_at(p.x, p.y) - 0.08, p.y))
				props.call("place_mesh", "terrace_wall", walls % 3, wx, true)
				walls += 1
			k += 3.0
	stats["walls"] = walls
	# the sheaves round the threshing floor and the stook: their spots now, so the ground map (no grass, contact
	# shade) is painted before the terrain textures are committed; the meshes are built in build()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6080
	_sheaf_spots.clear()
	for k in 7:
		var a := 0.6 + float(k) * 0.55 + rng.randf_range(-0.1, 0.1)
		_sheaf_spots.append(tp + Vector2(cos(a), sin(a)) * rng.randf_range(4.2, 5.4))
	for k in 3:
		_sheaf_spots.append(STOOK + Vector2(cos(k * 2.1), sin(k * 2.1)) * 0.35)
	for p: Vector2 in _sheaf_spots:
		t.splat_nograss(p, 0.42)
		t.splat_ao(p, 0.7, 0.3)
	props.call("reserve", STOOK, 1.6)


# --- build -------------------------------------------------------------------------------------------------------

func build(w: Node3D, meadow: Object) -> void:
	if Game.arg("wheat", "1") == "0" or _w == 0:
		return
	var t0 := Time.get_ticks_usec()
	var tp := Time.get_ticks_usec()
	MeadowPaint.card_atlas()
	MeadowPaint.wheat_top()
	stats["paint_ms"] = (Time.get_ticks_usec() - tp) / 1000
	_bind_terrain_material(meadow)
	if Game.arg("canopy", "1") != "0":
		_build_canopy(meadow)
	if Game.arg("wheatears", "1") != "0":
		_build_ear_rings(meadow)
	if Game.arg("wheatcards", "1") != "0":
		_build_edge_cards(meadow)
	_build_sheaves()
	# FIXER-2: the quality setting thins the wheat's clumps and cards too (a little less than the meadow: the canopy
	# under them keeps the field full); AnimeMeadow._apply_quality() ran before these materials existed.
	var q := int(Settings.get_v("quality"))
	var dk := 0.75 if q <= 0 else (0.9 if q == 1 else 1.0)
	for m in _mats:
		m.set_shader_parameter("density", dk)
	stats["build_ms"] = (Time.get_ticks_usec() - t0) / 1000


## FIXER-2: a wheat program with `defines` (MeadowKit.shader_variant); the lab / integration switch grassopaque=1 adds
## MEADOW_OPAQUE (the opaque render list instead of the alpha list, for A/B timing on real devices; see AnimeMeadow).
func _shader(path: String, defines: Array) -> Shader:
	var d := PackedStringArray(defines)
	if Game.arg("grassopaque", "0") == "1":
		d.append("MEADOW_OPAQUE")
	return MeadowKit.shader_variant(path, d)


func _bind(mat: ShaderMaterial, meadow: Object) -> void:
	if meadow != null and meadow.has_method("bind"):
		meadow.call("bind", mat)
	else:
		mat.set_shader_parameter("height_tex", terrain.height_tex)
		mat.set_shader_parameter("color_tex", terrain.color_tex)
		mat.set_shader_parameter("ground_tex", terrain.ground_tex)
		var ext: float = terrain.EXT
		var gm_ext: float = terrain.GM_EXT
		mat.set_shader_parameter("grid", Vector4(-ext, -ext, float(terrain.CELL), float(terrain.N)))
		mat.set_shader_parameter("ground_rect", Vector4(-gm_ext, -gm_ext, gm_ext * 2.0, gm_ext * 2.0))
		mat.set_shader_parameter("mound_tex", MeadowKit.mound_texture())
	mat.set_shader_parameter("field_tex", field_tex)
	mat.set_shader_parameter("field_rect", field_rect)
	mat.set_shader_parameter("canopy_h", CANOPY_H)
	mat.set_shader_parameter("wheat_top", MeadowPaint.wheat_top())
	_mats.append(mat)


func _bind_terrain_material(meadow: Object) -> void:
	var tm := Materials.terrain()
	tm.set_shader_parameter("field_tex", field_tex)
	tm.set_shader_parameter("field_rect", field_rect)
	if meadow == null:
		tm.set_shader_parameter("mound_tex", MeadowKit.mound_texture())


## The ear canopy: a grid (0.5 m) over the field's cells, at ground height (the shader lifts it), only where the
## field map has wheat (plus a cell of margin for the ragged edge).
func _build_canopy(meadow: Object) -> void:
	var t := terrain
	var step := 0.5
	var nx := int(field_rect.z / step) + 1
	var nz := int(field_rect.w / step) + 1
	var v := PackedVector3Array()
	v.resize(nx * nz)
	var keep := PackedByteArray()
	keep.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := field_rect.x + i * step
			var z := field_rect.y + j * step
			v[j * nx + i] = Vector3(x, t.height_at(x, z), z)
			keep[j * nx + i] = 1 if in_field(x, z) > 0.2 else 0
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx + 1
			var d := a + nx
			# FIXER: every cell with wheat at one corner at least (the ragged edge is cut per pixel in the shader, the
			# canopy ramps down to the ground there): no 0.5 m stair steps along the verges
			if keep[a] + keep[b] + keep[c] + keep[d] < 1:
				continue
			idx.append_array([a, b, c, a, c, d])
	var nn := PackedVector3Array()
	nn.resize(v.size())
	nn.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nn
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = _shader("res://shaders/wheat_canopy.gdshader", [])
	mat.render_priority = -12
	_bind(mat, meadow)
	var mi := MeshInstance3D.new()
	mi.name = "WheatCanopy"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	add_child(mi)
	stats["canopy_tris"] = idx.size() / 3


func _build_ear_rings(meadow: Object) -> void:
	var shader: Shader = _shader("res://shaders/wheat_ears.gdshader", [])
	# FIXER: the cards' program (discard) is separate from the 3D clumps' (none)
	var shader_cards: Shader = _shader("res://shaders/wheat_ears.gdshader", ["WHEAT_CARDS"])
	# (FIXER-2: low quality keeps the lighter 4-stalk clump)
	var stalks := int(EAR_RINGS[0].get("stalks", 4)) if int(Settings.get_v("quality")) >= 1 else 4
	var clump := MeadowKit.wheat_clump(21, stalks, 2, 1)
	stats["tris_ear_clump"] = MeadowKit.tris(clump)
	for def in EAR_RINGS:
		var mode: int = def["mode"]
		if mode == 2 and Game.arg("wheatring", "1") == "0":
			continue
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
		mm.mesh = clump if mode == 0 else MeadowKit.billboard()
		mm.instance_count = cells * cells
		mm.buffer = buf
		var mat := ShaderMaterial.new()
		mat.shader = shader if mode == 0 else shader_cards
		mat.render_priority = int(def["prio"])
		_bind(mat, meadow)
		if def.has("card_w"):
			mat.set_shader_parameter("card_w", float(def["card_w"]))
		mat.set_shader_parameter("spacing", cell)
		mat.set_shader_parameter("ring", def["ring"])
		mat.set_shader_parameter("mode", float(mode))
		mat.set_shader_parameter("density_far", float(def["dens_far"]))
		if mode == 2:
			mat.set_shader_parameter("atlas", MeadowPaint.card_atlas())
			mat.set_shader_parameter("tile_a", MeadowPaint.tile_uv(4))
			mat.set_shader_parameter("tile_b", MeadowPaint.tile_uv(5))
			mat.set_shader_parameter("tile_c", MeadowPaint.tile_uv(5))
		var rv: Vector4 = def["ring"]
		var nodes: Array[MultiMeshInstance3D] = []
		var g: int = def["grid"]
		for i in g * g:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d" % [def["name"], i]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = rv.w + size * 0.7072 + 1.0
			mmi.visibility_range_end_margin = 2.0
			if rv.x - size * 0.7072 - 4.0 > 0.0:
				mmi.visibility_range_begin = rv.x - size * 0.7072 - 4.0
			add_child(mmi)
			nodes.append(mmi)
			instances += cells * cells
		stats["tris_" + String(def["name"])] = MeadowKit.tris(mm.mesh)
		_rings.append({"def": def, "size": size, "nodes": nodes, "mat": mat, "cc": Vector2i(1 << 20, 0)})


## Cards along the field's border and the road's verges: [root xz, outward normal xz] every ~0.45 m.
func _build_edge_cards(meadow: Object) -> void:
	var t := terrain
	var pts: Array = []
	var poly: Array = L.WHEAT_FIELD
	var rng := RandomNumberGenerator.new()
	rng.seed = 6071
	# The border: walk the field map's 0.5 iso-line by marching over the texels (cells with an edge crossing).
	for iy in _h - 1:
		for ix in _w - 1:
			var a := _data[(iy * _w + ix) * 4] / 255.0
			var b := _data[(iy * _w + ix + 1) * 4] / 255.0
			var c := _data[((iy + 1) * _w + ix) * 4] / 255.0
			var mn := minf(a, minf(b, c))
			var mx := maxf(a, maxf(b, c))
			if mn > 0.5 or mx < 0.5:
				continue
			if rng.randf() > 0.85:
				continue
			var x := field_rect.x + (ix + 0.5 + rng.randf()) * TEXEL
			var z := field_rect.y + (iy + 0.5 + rng.randf()) * TEXEL
			# outward = down the field weight's gradient
			var gx := (b - a)
			var gz := (c - a)
			var gl := sqrt(gx * gx + gz * gz)
			var out := Vector2(-gx, -gz) / gl if gl > 1e-4 else Vector2(1, 0)
			# set the card a little inside the field so its stalks stand on wheat ground
			var p := Vector2(x, z) - out * 0.25
			pts.append([p, out])
	var buf := PackedFloat32Array()
	var n_cards := 0
	for e in pts:
		var p: Vector2 = e[0]
		var out: Vector2 = e[1]
		var y: float = t.height_at(p.x, p.y)
		# FIXER: two crossed cards per spot (+-35 degrees off the outward normal: 70 degrees between them), so the edge
		# has depth seen obliquely; each with its own painted stand, mirror and height (custom data r, b, g)
		for k in 2:
			var a := (0.61 if k == 0 else -0.61) + rng.randf_range(-0.12, 0.12)
			var o2 := out.rotated(a)
			var zf := Vector3(o2.x, 0, o2.y)
			var xf := Vector3.UP.cross(zf).normalized()
			var sc := rng.randf_range(0.8, 1.2)
			var q := p + o2 * rng.randf_range(-0.12, 0.12)
			buf.append_array([xf.x, 0.0, zf.x, q.x, xf.y, 1.0, zf.y, y, xf.z, 0.0, zf.z, q.y, rng.randf(), sc, rng.randf(), 0.0])
			n_cards += 1
	if pts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeadowKit.billboard()
	mm.instance_count = n_cards
	mm.buffer = buf
	var mat := ShaderMaterial.new()
	mat.shader = _shader("res://shaders/wheat_ears.gdshader", ["WHEAT_CARDS"])
	mat.render_priority = -11
	_bind(mat, meadow)
	mat.set_shader_parameter("mode", 1.0)
	mat.set_shader_parameter("card_w", 1.05)
	mat.set_shader_parameter("atlas", MeadowPaint.card_atlas())
	mat.set_shader_parameter("tile_a", MeadowPaint.tile_uv(4))
	mat.set_shader_parameter("tile_b", MeadowPaint.tile_uv(5))
	mat.set_shader_parameter("tile_c", MeadowPaint.tile_uv(7))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "WheatEdgeCards"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 160.0
	add_child(mmi)
	stats["edge_cards"] = n_cards


## A few sheaves by the threshing floor: bundles of straw tied at the waist with a crown of ears (one merged mesh,
## vertex colours, the lowpoly material so they light like every prop).
func _build_sheaves() -> void:
	var t := terrain
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6081
	var spots := _sheaf_spots
	if spots.is_empty():
		return
	# the last three: the stook, leaning together
	var corner := STOOK
	var straw := Color("D9B45A")
	var straw_dark := Color("A9822F")
	var ears := Color("EBCB78")
	var tie := Color("7A5A2A")
	for i in spots.size():
		var p: Vector2 = spots[i]
		var y: float = t.height_at(p.x, p.y)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized()
		if i >= spots.size() - 3:
			lean = (Vector3(corner.x - p.x, 0.0, corner.y - p.y) * 1.2 + Vector3.UP).normalized()
		var base := Vector3(p.x, y - 0.05, p.y)
		_sheaf(st, base, lean, rng.randf_range(0.95, 1.15), rng.randf() * TAU, straw, straw_dark, ears, tie)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Sheaves"
	mi.mesh = st.commit()
	mi.material_override = Materials.lowpoly()
	add_child(mi)
	# Collision (physics layer 1, the world): nothing walks through a sheaf.
	var body := StaticBody3D.new()
	body.name = "SheavesBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for p: Vector2 in spots:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.24
		cyl.height = 1.1
		cs.shape = cyl
		cs.position = Vector3(p.x, t.height_at(p.x, p.y) + 0.5, p.y)
		body.add_child(cs)


func _sheaf(st: SurfaceTool, base: Vector3, up: Vector3, s: float, rot: float, straw: Color, dark: Color, ears: Color, tie: Color) -> void:
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := up.cross(side).normalized()
	# profile: radius at heights (a waist where it is tied, flaring at the foot and the crown)
	var prof := [[0.0, 0.2], [0.35, 0.13], [0.45, 0.1], [0.55, 0.12], [0.85, 0.2], [1.0, 0.16], [1.12, 0.05]]
	var cols := [dark, straw, tie, straw, ears, ears, ears]
	var n := 7
	var rings: Array = []
	for r in prof:
		var ring: Array[Vector3] = []
		for k in n:
			var a := rot + TAU * float(k) / float(n)
			var rr: float = float(r[1]) * s * (1.0 + 0.12 * sin(a * 3.0 + rot))
			ring.append(base + up * float(r[0]) * s + (side * cos(a) + fwd * sin(a)) * rr)
		rings.append(ring)
	for j in rings.size() - 1:
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		var c: Color = cols[j]
		c.a = 1.0
		for k in n:
			var k1 := (k + 1) % n
			st.set_color(c)
			st.add_vertex(r0[k])
			st.set_color(c)
			st.add_vertex(r1[k])
			st.set_color(c)
			st.add_vertex(r1[k1])
			st.set_color(c)
			st.add_vertex(r0[k])
			st.set_color(c)
			st.add_vertex(r1[k1])
			st.set_color(c)
			st.add_vertex(r0[k1])


# --- the rings follow the camera ---------------------------------------------------------------------------------

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


func _chunk_info(c: Vector2i, size: float) -> Array:
	var key := Vector3i(c.x, c.y, int(size * 10.0))
	if _aabb_cache.has(key):
		return _aabb_cache[key]
	var x0 := c.x * size
	var z0 := c.y * size
	var n := clampi(int(ceil(size / 2.0)), 3, 20)
	var lo := INF
	var hi := -INF
	var wheat := 0.0
	for j in n + 1:
		for i in n + 1:
			var x := x0 + size * float(i) / float(n)
			var z := z0 + size * float(j) / float(n)
			if absf(x) > 191.0 or absf(z) > 191.0:
				continue
			var y: float = terrain.height_at(x, z)
			lo = minf(lo, y)
			hi = maxf(hi, y)
			wheat = maxf(wheat, in_field(x, z))
	if lo == INF:
		lo = -1.0
		hi = 0.0
	var out := [AABB(Vector3(-1.0, lo - 1.0, -1.0), Vector3(size + 2.0, hi - lo + 3.5, size + 2.0)), wheat > 0.02]
	_aabb_cache[key] = out
	return out
