class_name World
extends Node3D
## PLACEHOLDER island of Nemea, so every other stream can run, play and render before the real island exists.
## The WORLD stream replaces this file (keeping the API below); nothing outside scripts/world/ may depend on its
## internals.
##
## About 300 x 300 m of land: sandy beaches all round, gentle hills, a holm-oak and pine forest in the centre, an
## olive grove to the east, a flat village by the southern beach with a wooden pier, and in the north a plateau
## that drops to the sea in cliffs, crowned by a ridge. In the ridge an open crater (stand-in for the lion's cave)
## with two passes, four stone pillars and a boulder by the southern pass. Three bronze rings on standing stones,
## one altar on a hilltop. North is -Z, east +X; the sun sets in the west (-X).
##
## World API (docs/ARCHITECTURE.md; units m, +Y up):
##   build(seed)                         generate everything (call once, after adding the node to the tree)
##   height_at(x, z) -> float            exact height of the walkable ground (= the collision triangles)
##   ground(p) -> Vector3                p dropped onto the ground
##   normal_at(x, z) -> Vector3          smoothed ground normal
##   is_water(x, z) -> bool              the ground there is below sea_level (the hero swims where it is deep)
##   sea_level: float                    0.0
##   player_start() -> Transform3D       on the pier's beach end, facing inland (north)
##   altars() -> Array                   Altar nodes (Interactables, checkpoints)
##   spawn_groups() -> Array             [{kind: &"wolf"|&"boar", center: Vector3, radius: float, count: int}]
##   cave() -> Dictionary                {entrance_a, entrance_b: Vector3, boulder: Node3D, arena_center: Vector3,
##                                        pillars: Array[Vector3], lion_spawn: Vector3}
##   anchors() -> Array                  bronze rings (ChainRing; also in group "chain_anchor")
##   boat_dock() -> Vector3              the pier's sea end, on the deck
##   bounds() -> Rect2                   XZ rectangle the island data covers
## Extras used by Grass / tools: ground_color_at(x, z), grass_params(x, z), coast_distance(x, z).
## Collision (layer 1 "world"): HeightMapShape3D terrain with the same triangles as the mesh, convex rocks,
## trunk cylinders, house boxes, pillars, the pier deck.

const HALF := 192.0 # the heightfield covers [-HALF, HALF]^2
const STEP := 2.0 # grid cell (m): mesh, collision and height_at() share it
const N := 193 # samples per side (2 * HALF / STEP + 1)
const LAND_R := 150.0 # mean coast radius
const OUTSIDE := -12.0 # height outside the heightfield (open sea)
const CRATER := Vector2(0.0, -108.0) # lion's crater centre (XZ)
const CRATER_FLOOR := 24.0
const CRATER_R := 17.0
const VILLAGE := Vector2(0.0, 92.0)
const VILLAGE_H := 2.6

const SAND := Color("EED9A8")
const SAND_WET := Color("D6BC8C")
const MEADOW := Color("9AAE62")
const MEADOW_LIGHT := Color("B2C177")
const MEADOW_DARK := Color("7F9654")
const LUSH := Color("7E9A4A")
const LUSH_DARK := Color("5E7A3A")
const STRAW := Color("CDBB7C")
const GARRIGUE := Color("A0A07A")
const ROCK := Color("B7A792")
const ROCK_DARK := Color("8E7F6C")
const DUST := Color("C9AE84")

var sea_level := 0.0
var seed_value := 7
var heights := PackedFloat32Array()
var colors := PackedColorArray() # per grid vertex: rgb ground, a = grassiness
var normals := PackedVector3Array()
var terrain: MeshInstance3D
var terrain_body: StaticBody3D
var props_body: StaticBody3D

var _hills := FastNoiseLite.new()
var _cn := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var _altars: Array = []
var _anchors: Array = []
var _spawn_groups: Array = []
var _cave := {}
var _start := Transform3D.IDENTITY
var _dock := Vector3.ZERO
var _pier := {} # {x, z0, z1, deck}
var _altar_spot := Vector3.ZERO
var _channels: Array = [] # [[a: Vector2, b: Vector2, floor_a: float, floor_b: float]]
var _trees: Array = [] # [species, Vector3, scale, yaw]
var _clear := {} # spatial hash (8 m cells) of [centre: Vector2, radius] discs that trees, rocks and grass avoid


# --- public API ----------------------------------------------------------------------------------------------

func build(seed_in: int = 7) -> void:
	seed_value = seed_in
	var t0 := Time.get_ticks_msec()
	_hills.seed = seed_value
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0085
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 3
	_cn.seed = seed_value + 11
	_cn.frequency = 1.6
	_patch.seed = seed_value + 23
	_patch.frequency = 0.045
	_heightfield()
	_carve_crater()
	_pick_altar_spot()
	_finish_grid()
	_build_terrain_mesh()
	_build_terrain_collision()
	_build_water_texture()
	_build_detail_texture()
	props_body = StaticBody3D.new()
	props_body.name = "Props"
	props_body.collision_layer = 1
	props_body.collision_mask = 0
	add_child(props_body)
	_build_village()
	_build_pier()
	_build_cave_props()
	_build_altar()
	_build_rings()
	_scatter_trees()
	_scatter_rocks()
	var grass := Grass.new()
	grass.name = "Grass"
	add_child(grass)
	grass.build(self)
	_spawn_groups = [
		{"kind": &"wolf", "center": ground(Vector3(-28, 0, -14)), "radius": 14.0, "count": 4},
		{"kind": &"wolf", "center": ground(Vector3(-52, 0, -58)), "radius": 12.0, "count": 3},
		{"kind": &"boar", "center": ground(Vector3(58, 0, -42)), "radius": 16.0, "count": 2},
	]
	print("World (placeholder): built in %d ms" % (Time.get_ticks_msec() - t0))


func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= N - 1 or fz >= N - 1:
		return OUTSIDE
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - ix
	var v := fz - iz
	var i := iz * N + ix
	# Same triangles as HeightMapShape3D (diagonal from (x+1, z) to (x, z+1)) and the terrain mesh.
	if u + v <= 1.0:
		return heights[i] + (heights[i + 1] - heights[i]) * u + (heights[i + N] - heights[i]) * v
	var h11 := heights[i + N + 1]
	return h11 + (heights[i + N] - h11) * (1.0 - u) + (heights[i + 1] - h11) * (1.0 - v)


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < sea_level


func player_start() -> Transform3D:
	return _start


func altars() -> Array:
	return _altars


func spawn_groups() -> Array:
	return _spawn_groups


func cave() -> Dictionary:
	return _cave


func anchors() -> Array:
	return _anchors


func boat_dock() -> Vector3:
	return _dock


func bounds() -> Rect2:
	return Rect2(-HALF, -HALF, 2.0 * HALF, 2.0 * HALF)


## Smooth ground colour (rgb) and grassiness (a) at (x, z).
func ground_color_at(x: float, z: float) -> Color:
	var fx := clampf((x + HALF) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return colors[i].lerp(colors[i + 1], tx).lerp(colors[i + N].lerp(colors[i + N + 1], tx), tz)


## Grass for scripts/world/grass.gd: [] or [tufts/m2, y min, y max, tip, seedable, flowers/m2].
func grass_params(x: float, z: float) -> Array:
	var h := height_at(x, z)
	if h < 1.5:
		return []
	var c := ground_color_at(x, z)
	if c.a < 0.45:
		return []
	var n := normal_at(x, z)
	if n.y < 0.8:
		return []
	if not _clear_at(Vector2(x, z), -1.0):
		return []
	var village := 1.0 - smoothstep(20.0, 40.0, Vector2(x, z).distance_to(VILLAGE))
	if village > 0.5:
		return [1.6, 0.6, 0.9, Color("A8BF62"), false, 0.25]
	var forest := _forest_w(x, z)
	if forest > 0.5:
		return [0.9, 0.85, 1.15, Color("9DB45E"), false, 0.08]
	if h > 20.0:
		return [0.9, 0.9, 1.2, Color("BDB77A"), true, 0.06]
	return [1.8, 0.8, 1.15, Color("A8BF62"), true, 0.35]


## Distance (m) from (x, z) to the coastline, positive inland.
func coast_distance(x: float, z: float) -> float:
	return _coast(atan2(z, x)) - Vector2(x, z).length()


# --- heightfield ---------------------------------------------------------------------------------------------

func _coast(ang: float) -> float:
	var r := LAND_R * (1.0 + 0.07 * sin(3.0 * ang + 0.7) + 0.045 * sin(5.0 * ang + 2.1) + 0.03 * sin(8.0 * ang + 0.3))
	return r + 7.0 * _cn.get_noise_2d(cos(ang), sin(ang))


func _north(z: float) -> float:
	return smoothstep(-30.0, -95.0, z)


func _forest_w(x: float, z: float) -> float:
	return 1.0 - smoothstep(48.0, 66.0, Vector2(x, z * 1.15).distance_to(Vector2(-6.0, -14.0)))


func _raw_height(x: float, z: float) -> float:
	var d := coast_distance(x, z)
	var north := _north(z)
	var cliff := north * (1.0 - smoothstep(60.0, 120.0, absf(x)))
	# Shore: seabed rising to the beach (steeper under the northern cliffs).
	var shore := -0.3 + d * (lerpf(0.16, 0.35, cliff) if d < 0.0 else 0.085)
	shore = maxf(shore, -9.0)
	# Inland: hills, the northern plateau and ridge, the flat village.
	var hn := clampf(_hills.get_noise_2d(x, z) * 0.62 + 0.5, 0.0, 1.0)
	var land := 1.4 + 15.0 * pow(hn, 1.6) * smoothstep(10.0, 70.0, d)
	land += 13.0 * north
	var zr := -112.0 + 9.0 * sin(x * 0.024 + 0.5)
	var dz := z - zr
	var w := 30.0 if dz > 0.0 else 20.0
	land += 26.0 * exp(-(dz / w) * (dz / w)) * (1.0 - smoothstep(70.0, 135.0, absf(x)))
	var vd := Vector2(x, z).distance_to(VILLAGE)
	land = lerpf(land, VILLAGE_H, 1.0 - smoothstep(26.0, 46.0, vd))
	var k := smoothstep(lerpf(6.0, 1.5, cliff), lerpf(30.0, 9.0, cliff), d)
	return lerpf(shore, land, k)


func _heightfield() -> void:
	heights.resize(N * N)
	for iz in N:
		var z := -HALF + iz * STEP
		for ix in N:
			var x := -HALF + ix * STEP
			heights[iz * N + ix] = _raw_height(x, z)


## The lion's crater: a flat floor walled by rock, open to the sky, with two passes (south-west and north-east)
## ramping down to the ground outside.
func _carve_crater() -> void:
	var pa := Vector2(-30.0, -72.0)
	var pb := Vector2(30.0, -140.0)
	_channels = [
		[CRATER, pa, CRATER_FLOOR, _sample(pa.x, pa.y) - 0.3],
		[CRATER, pb, CRATER_FLOOR, _sample(pb.x, pb.y) - 0.3],
	]
	for iz in N:
		var z := -HALF + iz * STEP
		if absf(z - CRATER.y) > 60.0:
			continue
		for ix in N:
			var x := -HALF + ix * STEP
			if absf(x - CRATER.x) > 60.0:
				continue
			var i := iz * N + ix
			var h := heights[i]
			var r := Vector2(x, z).distance_to(CRATER)
			h = minf(h, lerpf(CRATER_FLOOR, h, smoothstep(CRATER_R, CRATER_R + 9.0, r)))
			for ch in _channels:
				var a: Vector2 = ch[0]
				var b: Vector2 = ch[1]
				var ab := b - a
				var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var dist := Vector2(x, z).distance_to(a + ab * t)
				var fl := lerpf(float(ch[2]), float(ch[3]), smoothstep(CRATER_R / ab.length(), 1.0, t))
				h = minf(h, lerpf(fl, h, smoothstep(3.5, 8.0, dist)))
			heights[i] = h


func _sample(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var i := iz * N + ix
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + N], heights[i + N + 1], tx), tz)


## The altar stands on the highest hilltop of the east-centre, on a small levelled pad.
func _pick_altar_spot() -> void:
	var best := Vector2(40.0, 10.0)
	var best_h := -100.0
	for z in range(-30, 50, 4):
		for x in range(20, 100, 4):
			var h := _sample(x, z)
			if h > best_h and coast_distance(x, z) > 25.0:
				best_h = h
				best = Vector2(x, z)
	_altar_spot = Vector3(best.x, best_h, best.y)
	_flatten(best, 4.0, 9.0, best_h)


## Levels the ground to `h` within `r` m of `c`, blending back to the terrain by `r_out`.
func _flatten(c: Vector2, r: float, r_out: float, h: float) -> void:
	var i0 := clampi(int((c.x - r_out + HALF) / STEP), 0, N - 1)
	var i1 := clampi(int((c.x + r_out + HALF) / STEP) + 1, 0, N - 1)
	var j0 := clampi(int((c.y - r_out + HALF) / STEP), 0, N - 1)
	var j1 := clampi(int((c.y + r_out + HALF) / STEP) + 1, 0, N - 1)
	for iz in range(j0, j1 + 1):
		for ix in range(i0, i1 + 1):
			var p := Vector2(-HALF + ix * STEP, -HALF + iz * STEP)
			var k := 1.0 - smoothstep(r, r_out, p.distance_to(c))
			var i := iz * N + ix
			heights[i] = lerpf(heights[i], h, k)


func _finish_grid() -> void:
	normals.resize(N * N)
	colors.resize(N * N)
	for iz in N:
		for ix in N:
			var i := iz * N + ix
			var hl := heights[iz * N + maxi(ix - 1, 0)]
			var hr := heights[iz * N + mini(ix + 1, N - 1)]
			var hd := heights[maxi(iz - 1, 0) * N + ix]
			var hu := heights[mini(iz + 1, N - 1) * N + ix]
			normals[i] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
	for iz in N:
		var z := -HALF + iz * STEP
		for ix in N:
			var x := -HALF + ix * STEP
			var i := iz * N + ix
			colors[i] = _ground_color(x, z, heights[i], normals[i])


func _ground_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var slope := 1.0 - n.y
	var d := coast_distance(x, z)
	var cliff := _north(z) * (1.0 - smoothstep(60.0, 120.0, absf(x)))
	var pn := _patch.get_noise_2d(x, z)
	if h < 0.35:
		return Color(SAND_WET.r, SAND_WET.g, SAND_WET.b, 0.0)
	var col: Color
	var g := 1.0
	if h < 1.35 and d < 30.0 and cliff < 0.5:
		col = SAND.lerp(SAND_WET, smoothstep(0.9, 0.35, h) * 0.6)
		g = 0.0
	else:
		col = MEADOW_DARK.lerp(MEADOW, smoothstep(-0.45, 0.05, pn)).lerp(MEADOW_LIGHT, smoothstep(0.15, 0.6, pn) * 0.8)
		# Dry golden grass up on the plateau and the ridge.
		col = col.lerp(STRAW.lerp(GARRIGUE, 0.4), smoothstep(14.0, 30.0, h) * 0.7)
		# The forest floor: deep green.
		var fw := _forest_w(x, z)
		col = col.lerp(LUSH_DARK.lerp(LUSH, 0.5 + 0.5 * pn), fw * 0.75)
		g = lerpf(1.0, 0.7, fw)
		# A sandy fringe behind the beach.
		var fringe := 1.0 - smoothstep(1.35, 2.0, h)
		if d < 34.0 and cliff < 0.5:
			col = col.lerp(SAND.lerp(STRAW, 0.5), fringe * 0.6)
			g *= 1.0 - fringe * 0.7
		# The crater floor and its passes: trodden dust.
		var cr := Vector2(x, z).distance_to(CRATER)
		var dusty := 1.0 - smoothstep(CRATER_R - 1.0, CRATER_R + 3.0, cr)
		for ch in _channels:
			var a: Vector2 = ch[0]
			var b: Vector2 = ch[1]
			var ab := b - a
			var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			dusty = maxf(dusty, 1.0 - smoothstep(2.5, 4.5, Vector2(x, z).distance_to(a + ab * t)))
		col = col.lerp(DUST.lerp(ROCK, 0.25 + 0.2 * pn), dusty * 0.85)
		g *= 1.0 - dusty * 0.8
	# Rock on steep ground.
	var rk := smoothstep(0.24, 0.36, slope)
	if rk > 0.0:
		col = col.lerp(ROCK.lerp(ROCK_DARK, clampf(0.5 + pn * 0.8 + (slope - 0.36) * 1.5, 0.0, 1.0)), rk)
		g *= 1.0 - rk
	return Color(col.r, col.g, col.b, g)


# --- terrain mesh, collision, water and detail textures --------------------------------------------------------

func _build_terrain_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(N * N)
	norms.resize(N * N)
	cols.resize(N * N)
	for iz in N:
		for ix in N:
			var i := iz * N + ix
			verts[i] = Vector3(-HALF + ix * STEP, heights[i], -HALF + iz * STEP)
			norms[i] = normals[i]
			cols[i] = colors[i]
	var idx := PackedInt32Array()
	idx.resize((N - 1) * (N - 1) * 6)
	var k := 0
	for iz in N - 1:
		for ix in N - 1:
			var i := iz * N + ix
			if maxf(maxf(heights[i], heights[i + 1]), maxf(heights[i + N], heights[i + N + 1])) < -3.5:
				continue # deep under the (opaque) sea
			# Clockwise from above = Godot's front face; diagonal (x+1, z)-(x, z+1) like HeightMapShape3D.
			idx[k] = i
			idx[k + 1] = i + 1
			idx[k + 2] = i + N
			idx[k + 3] = i + 1
			idx[k + 4] = i + N + 1
			idx[k + 5] = i + N
			k += 6
	idx.resize(k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	terrain.material_override = Materials.terrain()
	add_child(terrain)


func _build_terrain_collision() -> void:
	terrain_body = StaticBody3D.new()
	terrain_body.name = "TerrainBody"
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 0
	add_child(terrain_body)
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# HeightMapShape3D samples are 1 unit apart and centred on the node: scale X and Z to the grid step.
	cs.scale = Vector3(STEP, 1.0, STEP)
	terrain_body.add_child(cs)


## Depth under the sea for shaders/water.gdshader: R = 0 at the shoreline .. 1 at 6 m and deeper.
func _build_water_texture() -> void:
	var img := Image.create(N, N, false, Image.FORMAT_L8)
	for iz in N:
		for ix in N:
			var d := clampf(-heights[iz * N + ix] / 6.0, 0.0, 1.0)
			img.set_pixel(ix, iz, Color(d, d, d))
	# Upsampled x4 with cubic filtering (0.5 m texels): the foam rings and colour bands follow iso-depth lines,
	# which would show the 2 m grid as staircases along diagonal coasts.
	img.resize(N * 4, N * 4, Image.INTERPOLATE_CUBIC)
	var tex := ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("g_water_tex", tex)
	# The image spans the grid samples plus half a source texel on each side.
	var half_t := STEP * 0.5
	RenderingServer.global_shader_parameter_set("g_water_rect", Vector4(-HALF - half_t, -HALF - half_t, 2.0 * HALF + STEP, 2.0 * HALF + STEP))


## Painted meadow patches for shaders/terrain.gdshader (and the ground rect the grass shares).
func _build_detail_texture() -> void:
	var dn := FastNoiseLite.new()
	dn.seed = 917
	dn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dn.frequency = 0.16
	dn.fractal_type = FastNoiseLite.FRACTAL_FBM
	dn.fractal_octaves = 3
	dn.fractal_lacunarity = 2.3
	dn.fractal_gain = 0.45
	dn.domain_warp_enabled = true
	dn.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	dn.domain_warp_amplitude = 14.0
	dn.domain_warp_frequency = 0.06
	var img := dn.get_image(512, 512, false, false, true)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var rect := Vector4(-HALF, -HALF, 2.0 * HALF, 2.0 * HALF)
	Materials.terrain().set_shader_parameter("detail_tex", tex)
	Materials.terrain().set_shader_parameter("ground_rect", rect)
	Materials.grass().set_shader_parameter("ground_rect", rect)


# --- props -------------------------------------------------------------------------------------------------------

func _add_mesh(mesh: Mesh, xf: Transform3D, mat: Material = null, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat else Materials.lowpoly()
	mi.transform = xf
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add_shape(shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	props_body.add_child(cs)


func _box(size: Vector3, xf: Transform3D) -> void:
	var b := BoxShape3D.new()
	b.size = size
	_add_shape(b, xf)


func _cyl(r: float, h: float, base: Vector3) -> void:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	_add_shape(c, Transform3D(Basis.IDENTITY, base + Vector3(0, h * 0.5, 0)))


## White houses round the village square (facing it), a well in the middle.
func _build_village() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	var spots := [[-150.0, 15.0], [-115.0, 17.0], [-70.0, 16.0], [-20.0, 18.0], [25.0, 15.0], [160.0, 16.0], [200.0, 18.0]]
	var n := 0
	for sp in spots:
		var a := deg_to_rad(float(sp[0]))
		var p2 := VILLAGE + Vector2(cos(a), sin(a)) * float(sp[1])
		var b: Dictionary = ModelsBuildings.building("house", 1 + (n % 2), 300 + n * 17)
		var mesh: Mesh = b["mesh"]
		var pos := ground(Vector3(p2.x, 0, p2.y))
		pos.y = minf(pos.y, height_at(p2.x + 2.0, p2.y + 2.0))
		# Front (+Z) towards the square.
		var to_c := (VILLAGE - p2).normalized()
		var yaw := atan2(to_c.x, to_c.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		_add_mesh(mesh, xf)
		var bb := mesh.get_aabb()
		var size := Vector3(maxf(bb.size.x - 0.6, 1.0), bb.size.y, maxf(bb.size.z - 0.6, 1.0))
		_box(size, xf * Transform3D(Basis.IDENTITY, bb.get_center()))
		_clear_add(p2, maxf(bb.size.x, bb.size.z) * 0.6 + 1.5)
		n += 1
	var well := ModelsNature.well(5)
	var wp := ground(Vector3(VILLAGE.x, 0, VILLAGE.y))
	_add_mesh(well, Transform3D(Basis.IDENTITY, wp))
	_cyl(0.95, 1.2, wp)
	_clear_add(VILLAGE, 3.0)
	# A few cypresses at the edge of the village.
	for i in 6:
		var a := deg_to_rad(-60.0 + i * 50.0 + rng.randf_range(-10, 10))
		var p := VILLAGE + Vector2(cos(a), sin(a)) * rng.randf_range(27.0, 32.0)
		_trees.append(["cypress", ground(Vector3(p.x, 0, p.y)), rng.randf_range(0.9, 1.15), rng.randf() * TAU])


## A wooden pier from the southern beach out to sea, with a boat moored at its end. The hero starts on it.
func _build_pier() -> void:
	var x := 14.0
	var deck := 1.2
	var z_land := 0.0
	# Walk south from the village until the sand drops under the deck: the pier starts there, on the sand.
	for zi in range(int(VILLAGE.y) * 2, 400):
		if height_at(x, zi * 0.5) < deck - 0.08:
			z_land = zi * 0.5
			break
	var z0 := z_land - 0.6
	var z1 := z_land + 26.0
	_pier = {"x": x, "z0": z0, "z1": z1, "deck": deck}
	var mb := MeshBuilder.new(91)
	mb.vary = 0.04
	var length := z1 - z0
	var planks := int(length / 0.55)
	for i in planks:
		var zc := z0 + (i + 0.5) * length / planks
		var c := Pal.WOOD_LIGHT if i % 3 != 0 else Pal.WOOD
		mb.block(Vector3(x + (0.04 if i % 2 == 0 else -0.04), deck - 0.12, zc), Vector3(3.0, 0.12, length / planks - 0.05), c)
	for zc in range(int(z0) + 1, int(z1) + 1, 3):
		for sx in [-1.35, 1.35]:
			var y0 := height_at(x + sx, zc) - 1.0
			mb.limb(Vector3(x + sx, y0, zc), Vector3(x + sx, deck + 0.35, zc), 0.13, 0.12, 6, Pal.WOOD_DARK)
	_add_mesh(mb.commit(), Transform3D.IDENTITY)
	_box(Vector3(3.0, 0.4, length), Transform3D(Basis.IDENTITY, Vector3(x, deck - 0.2, (z0 + z1) * 0.5)))
	# The land end starts where the sand reaches the deck (no steps needed); the boat moors at the sea end.
	_dock = Vector3(x, deck, z1 - 1.0)
	var boat := ModelsNature.boat_small(4)
	_add_mesh(boat, Transform3D(Basis(Vector3.UP, 0.08), Vector3(x + 3.4, -0.05, z1 - 4.0)))
	_box(Vector3(1.8, 1.0, 5.0), Transform3D(Basis(Vector3.UP, 0.08), Vector3(x + 3.4, 0.2, z1 - 4.0)))
	_clear_add(Vector2(x, z_land), 6.0)
	# The hero arrives by boat: on the deck near the sea end, beside the boat, facing the island (north, -Z).
	_start = Transform3D(Basis.IDENTITY, Vector3(x, deck, z1 - 6.0))


## Four broken columns in the crater and the boulder by the southern pass.
func _build_cave_props() -> void:
	var c3 := Vector3(CRATER.x, CRATER_FLOOR, CRATER.y)
	var pillars: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var p := ground(c3 + Vector3(cos(a), 0, sin(a)) * 9.5)
		pillars.append(p)
		var mb := MeshBuilder.new(500 + k)
		mb.vary = 0.03
		mb.cyl(Vector3(0, -0.4, 0), 0.7, 1.25, 1.15, 8, Pal.LIMESTONE_DARK, true, 0.0, Pal.LIMESTONE)
		ModelsNature.fluted_shaft(mb, rng, Vector3(0, 0.3, 0), 6.2 - k * 0.6, 0.85, 0.75, 10, Pal.MARBLE_SHADE, Pal.LIMESTONE, 0.4)
		_add_mesh(mb.commit(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		_cyl(0.9, 6.5 - k * 0.6, p + Vector3(0, -0.4, 0))
		_clear_add(Vector2(p.x, p.z), 2.0)
	var dir_a := (Vector2(_channels[0][1]) - CRATER).normalized()
	var dir_b := (Vector2(_channels[1][1]) - CRATER).normalized()
	var ea := CRATER + dir_a * (CRATER_R + 1.0)
	var eb := CRATER + dir_b * (CRATER_R + 1.0)
	var bpos := CRATER + dir_a * (CRATER_R + 9.0) + Vector2(-dir_a.y, dir_a.x) * 2.5
	var boulder := Boulder.new()
	boulder.name = "CaveBoulder"
	add_child(boulder)
	boulder.global_position = ground(Vector3(bpos.x, 0, bpos.y)) + Vector3(0, 0.05, 0)
	_clear_add(CRATER, CRATER_R + 4.0)
	_cave = {
		"entrance_a": ground(Vector3(ea.x, 0, ea.y)),
		"entrance_b": ground(Vector3(eb.x, 0, eb.y)),
		"boulder": boulder,
		"arena_center": c3,
		"pillars": pillars,
		"lion_spawn": ground(c3 + Vector3(0, 0, -6.0)),
	}


func _build_altar() -> void:
	var altar := Altar.new()
	altar.name = "AltarHill"
	add_child(altar)
	# Facing the village (south-west), so its respawn point is on the way down.
	var to_v := (VILLAGE - Vector2(_altar_spot.x, _altar_spot.z)).normalized()
	altar.global_transform = Transform3D(Basis(Vector3.UP, atan2(to_v.x, to_v.y)), _altar_spot)
	_altars.append(altar)
	_clear_add(Vector2(_altar_spot.x, _altar_spot.z), 6.0)


## Three bronze rings on standing stones: by the village, at the forest edge and on the ridge's southern face.
func _build_rings() -> void:
	var defs := [[Vector2(-22.0, 58.0), 3.2], [Vector2(36.0, -22.0), 3.6], [Vector2(-46.0, -80.0), 4.2]]
	for d in defs:
		var p2: Vector2 = d[0]
		var ring := ChainRing.new(float(d[1]))
		ring.name = "Ring_%d" % _anchors.size()
		add_child(ring)
		var to_v := (VILLAGE - p2).normalized()
		ring.global_transform = Transform3D(Basis(Vector3.UP, atan2(to_v.x, to_v.y)), ground(Vector3(p2.x, 0, p2.y)))
		_anchors.append(ring)
		_clear_add(p2, 2.5)


const CLEAR_CELL := 8.0
const CLEAR_PAD := 4.0 # largest `extra` _clear_at() is asked for


## Marks a disc that trees, rocks and grass keep out of.
func _clear_add(p: Vector2, r: float) -> void:
	var reach := r + CLEAR_PAD
	for cz in range(int(floor((p.y - reach) / CLEAR_CELL)), int(floor((p.y + reach) / CLEAR_CELL)) + 1):
		for cx in range(int(floor((p.x - reach) / CLEAR_CELL)), int(floor((p.x + reach) / CLEAR_CELL)) + 1):
			var key := Vector2i(cx, cz)
			if not _clear.has(key):
				_clear[key] = []
			(_clear[key] as Array).append([p, r])


## True when `p` is outside every cleared disc (grown by `extra` m, at most CLEAR_PAD).
func _clear_at(p: Vector2, extra: float = 0.0) -> bool:
	var key := Vector2i(int(floor(p.x / CLEAR_CELL)), int(floor(p.y / CLEAR_CELL)))
	if not _clear.has(key):
		return true
	for cl in _clear[key]:
		if p.distance_to(cl[0]) < float(cl[1]) + extra:
			return false
	return true


## Forest in the centre, an olive grove to the east, pines on the ridge. Drawn as one MultiMesh per species and
## variant; trunks get collision cylinders.
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 1
	# Forest.
	for gz in range(-80, 50, 6):
		for gx in range(-75, 65, 6):
			var p := Vector2(gx + rng.randf_range(-2.5, 2.5), gz + rng.randf_range(-2.5, 2.5))
			var fw := _forest_w(p.x, p.y)
			if fw < 0.2 or rng.randf() > fw * 0.85:
				continue
			if _patch.get_noise_2d(p.x * 0.7, p.y * 0.7) > 0.32:
				continue # clearings
			var h := height_at(p.x, p.y)
			if h < 2.5 or normal_at(p.x, p.y).y < 0.86 or not _clear_at(p, 2.0):
				continue
			var u := rng.randf()
			var sp := "holm_oak" if u < 0.5 else ("aleppo_pine" if u < 0.85 else "cypress")
			_trees.append([sp, Vector3(p.x, h, p.y), rng.randf_range(0.85, 1.25), rng.randf() * TAU])
	# Olive grove (rows) to the east.
	for gz in range(-24, 60, 8):
		for gx in range(62, 122, 8):
			var p := Vector2(gx + rng.randf_range(-1.2, 1.2), gz + rng.randf_range(-1.2, 1.2))
			var h := height_at(p.x, p.y)
			if h < 2.5 or coast_distance(p.x, p.y) < 18.0 or normal_at(p.x, p.y).y < 0.9 or not _clear_at(p, 2.0):
				continue
			_trees.append(["olive_tree", Vector3(p.x, h, p.y), rng.randf_range(0.9, 1.2), rng.randf() * TAU])
	# Pines along the ridge.
	for i in 40:
		var p := Vector2(rng.randf_range(-110.0, 110.0), rng.randf_range(-135.0, -75.0))
		var h := height_at(p.x, p.y)
		if h < 12.0 or normal_at(p.x, p.y).y < 0.85 or not _clear_at(p, 4.0):
			continue
		_trees.append(["aleppo_pine", Vector3(p.x, h, p.y), rng.randf_range(0.8, 1.1), rng.randf() * TAU])
	# One MultiMesh per species and variant.
	var groups := {}
	for t in _trees:
		var key := "%s:%d" % [t[0], int(absf(t[1].x * 13.0 + t[1].z * 7.0)) % 2]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
	var nature: Script = load("res://scripts/gfx/models_nature.gd")
	for key in groups:
		var parts := String(key).split(":")
		var species := parts[0]
		var variant := int(parts[1])
		var mesh: Mesh = nature.call(species, 11 + variant * 7)
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in list.size():
			var t: Array = list[j]
			var s: float = t[2]
			mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, t[3]) * Basis.from_scale(Vector3.ONE * s), t[1] - Vector3(0, 0.05, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_" + String(key).replace(":", "_")
		mmi.multimesh = mm
		mmi.material_override = ModelsNature.material_for(species)
		add_child(mmi)
	for t in _trees:
		var r: float = float(ModelsNature.info(t[0])["obstacle"]) * float(t[2])
		if r > 0.0:
			_cyl(maxf(r, 0.25), 3.2, t[1] - Vector3(0, 0.3, 0))


## Big rocks on the slopes and the ridge, rounded rocks along the shore; each with a convex collision hull.
func _scatter_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 13 + 3
	var big: Array = []
	var shore: Array = []
	for v in 4:
		var m: ArrayMesh = ModelsNature.rock_large(70 + v * 9)
		big.append([m, m.create_convex_shape(true, true)])
		var s: ArrayMesh = ModelsNature.beach_rock(90 + v * 5)
		shore.append([s, s.create_convex_shape(true, true)])
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 3000:
		tries += 1
		var p := Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-160.0, 150.0))
		var h := height_at(p.x, p.y)
		var n := normal_at(p.x, p.y)
		if h < 3.0 or n.y > 0.97 or n.y < 0.55 or not _clear_at(p, 3.0):
			continue
		if Vector2(p.x, p.y).distance_to(VILLAGE) < 40.0:
			continue
		var e: Array = big[placed % big.size()]
		_place_rock(e, Vector3(p.x, h, p.y), rng.randf_range(0.9, 1.7), rng.randf() * TAU)
		_clear_add(p, 2.5)
		placed += 1
	placed = 0
	tries = 0
	while placed < 26 and tries < 3000:
		tries += 1
		var a := rng.randf() * TAU
		var r := _coast(a) - rng.randf_range(2.0, 7.0)
		var p := Vector2(cos(a), sin(a)) * r
		var h := height_at(p.x, p.y)
		if h < -0.4 or h > 0.9 or not _clear_at(p, 3.0):
			continue
		var e: Array = shore[placed % shore.size()]
		_place_rock(e, Vector3(p.x, h, p.y), rng.randf_range(0.9, 1.6), rng.randf() * TAU)
		_clear_add(p, 2.0)
		placed += 1


func _place_rock(e: Array, pos: Vector3, s: float, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * s), pos - Vector3(0, 0.08 * s, 0))
	_add_mesh(e[0], xf)
	var src: ConvexPolygonShape3D = e[1]
	var hull := ConvexPolygonShape3D.new()
	var pts := src.points.duplicate()
	for i in pts.size():
		pts[i] *= s
	hull.points = pts
	_add_shape(hull, Transform3D(Basis(Vector3.UP, yaw), xf.origin))
