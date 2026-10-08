class_name Island
extends Node3D
## Delos: procedural heightfield island with four landing beaches, cliffs elsewhere, dirt paths (the lanes the
## creatures of Nyx walk) converging on the lighthouse plaza, and the fixed build spots.
##
## Coordinates: X east, Z south, Y up. The lighthouse stands at the origin on top of a hill.

const GRID := 1.0 # heightfield resolution (m)
const EXTENT := 100.0 # heightfield covers [-EXTENT, EXTENT]^2
const MESH_CELL := 1.7
const PLAZA_R := 7.5
const PLAZA_H := 4.2
const LANE_W := 1.5 # half width of the dirt paths

## Lanes, in the order beaches open over the nights: south, east, west, north.
const LANE_DEFS := [
	{"name": "sur", "label": "Playa del Sur", "angle": 10.0, "wiggle": 0.20, "phase": 0.3},
	{"name": "este", "label": "Cala del Este", "angle": 84.0, "wiggle": 0.24, "phase": 2.2},
	{"name": "oeste", "label": "Playa del Oeste", "angle": -101.0, "wiggle": 0.22, "phase": 4.1},
	{"name": "norte", "label": "Playa del Norte", "angle": 196.0, "wiggle": 0.18, "phase": 1.1},
]

## Build spots. "lane"/"r"/"off": placed relative to a lane (r = distance from the lighthouse, off = lateral
## metres, + is to the right walking inward). "at": absolute XZ. ring = lighthouse level needed (1..3).
const SPOT_DEFS := [
	{"type": "pharos", "at": Vector2(0, 0), "ring": 1},
	{"type": "house", "at": Vector2(10.5, 6.5), "ring": 1},
	{"type": "house", "at": Vector2(-10.0, 7.5), "ring": 1},
	{"type": "tower", "lane": 0, "r": 19.0, "off": -5.0, "ring": 1},
	{"type": "wall", "lane": 0, "r": 26.0, "off": 0.0, "ring": 1},
	{"type": "barracks", "lane": 0, "r": 13.5, "off": 7.0, "ring": 1},
	{"type": "farm", "at": Vector2(-19.0, 17.0), "ring": 1},
	{"type": "house", "at": Vector2(9.5, -9.0), "ring": 1},

	{"type": "tower", "lane": 1, "r": 20.0, "off": -5.0, "ring": 2},
	{"type": "wall", "lane": 1, "r": 28.0, "off": 0.0, "ring": 2},
	{"type": "tower", "lane": 2, "r": 20.0, "off": 5.0, "ring": 2},
	{"type": "wall", "lane": 2, "r": 28.0, "off": 0.0, "ring": 2},
	{"type": "dock", "lane": 1, "coast": true, "off": 11.0, "ring": 2},
	{"type": "dock", "lane": 0, "coast": true, "off": -13.0, "ring": 2},
	{"type": "house", "at": Vector2(-9.5, -9.0), "ring": 2},
	{"type": "house", "at": Vector2(17.5, 15.0), "ring": 2},
	{"type": "farm", "at": Vector2(19.0, -16.0), "ring": 2},
	{"type": "barracks", "lane": 1, "r": 15.0, "off": 7.0, "ring": 2},

	{"type": "tower", "lane": 3, "r": 19.0, "off": 5.0, "ring": 3},
	{"type": "wall", "lane": 3, "r": 27.0, "off": 0.0, "ring": 3},
	{"type": "tower", "lane": 0, "r": 35.0, "off": 6.0, "ring": 3},
	{"type": "tower", "lane": 1, "r": 38.0, "off": 6.0, "ring": 3},
	{"type": "tower", "lane": 2, "r": 38.0, "off": -6.0, "ring": 3},
	{"type": "farm", "at": Vector2(-20.0, -15.0), "ring": 3},
	{"type": "house", "at": Vector2(-17.0, 26.0), "ring": 3},
	{"type": "barracks", "lane": 2, "r": 15.0, "off": -7.0, "ring": 3},
	{"type": "dock", "lane": 2, "coast": true, "off": 12.0, "ring": 3},
]

var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var heights := PackedFloat32Array()
var lane_mask := PackedFloat32Array() # 0..1 path weight
var plaza_mask := PackedFloat32Array()
var n_cells := 0

var lanes: Array = [] # Array[PackedVector3Array]: from the sea spawn to the plaza edge, ~1 m apart
var lane_len: Array = [] # cumulative lengths per lane
var beaches: Array = [] # {name, label, lane, spawn: Vector3, landing: Vector3, angle}
var spots: Array = [] # {type, ring, pos: Vector3, yaw: float, lane: int}
var coast_r := PackedFloat32Array() # coastline radius per degree
var terrain: MeshInstance3D
var water_image: Image


func generate(seed_value: int = 7) -> void:
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	noise2.seed = seed_value + 11
	noise2.frequency = 0.11
	noise2.fractal_octaves = 2
	_build_coast()
	_build_lanes()
	_build_heightfield()
	_build_spots()
	_flatten_spots()
	_build_terrain_mesh()
	_build_paths_and_plaza()
	_build_water_texture()


# --- shape -------------------------------------------------------------------------------------------------

func _build_coast() -> void:
	coast_r.resize(360)
	for d in 360:
		var a := deg_to_rad(float(d))
		var r := 53.0 + 6.0 * sin(2.0 * a + 0.6) + 4.0 * sin(3.0 * a + 1.9) + 2.5 * sin(5.0 * a + 0.4)
		r += 4.0 * noise.get_noise_2d(cos(a) * 40.0, sin(a) * 40.0)
		coast_r[d] = r
	# Smooth the outline a little.
	var sm := coast_r.duplicate()
	for d in 360:
		var acc := 0.0
		for k in range(-3, 4):
			acc += coast_r[(d + k + 360) % 360]
		sm[d] = acc / 7.0
	coast_r = sm


## Angle convention: 0 deg = +Z (south), 90 deg = +X (east).
static func angle_of(x: float, z: float) -> float:
	return fposmod(rad_to_deg(atan2(x, z)), 360.0)


func coast_at(angle_deg: float) -> float:
	var a := fposmod(angle_deg, 360.0)
	var i := int(floor(a))
	var f := a - float(i)
	return lerpf(coast_r[i % 360], coast_r[(i + 1) % 360], f)


func beach_weight(angle_deg: float) -> float:
	var w := 0.0
	for ld in LANE_DEFS:
		var diff := absf(angle_difference(deg_to_rad(angle_deg), deg_to_rad(ld["angle"])))
		w = maxf(w, smoothstep(0.42, 0.16, diff))
	return w


## Analytic height before paths and spots are carved in.
func _base_height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var ang := angle_of(x, z)
	var R := coast_at(ang)
	var d := R - r # >0 inland
	var b := beach_weight(ang)
	var h: float
	if d < 0.0:
		var slope := lerpf(0.42, 0.13, b)
		h = -0.35 + d * slope
	else:
		var beach := d * 0.055 + smoothstep(9.0, 26.0, d) * 1.6
		var cliff := smoothstep(0.0, 3.2, d) * 2.6 + smoothstep(3.0, 20.0, d) * 0.6
		h = lerpf(cliff, beach, b) - 0.35 * (1.0 - smoothstep(0.0, 1.5, d)) * b
		h += noise.get_noise_2d(x, z) * 0.7 * smoothstep(4.0, 16.0, d)
		h += noise2.get_noise_2d(x, z) * 0.07 * smoothstep(2.0, 8.0, d)
	# Lighthouse hill.
	h += 2.4 * (1.0 - smoothstep(0.0, 34.0, r))
	# Rocky islet to the south-east.
	var ix := x - 47.0
	var iz := z - 44.0
	var ir := sqrt(ix * ix + iz * iz)
	h = maxf(h, 2.6 - ir * 0.42 + noise2.get_noise_2d(x * 2.0, z * 2.0) * 0.5)
	return clampf(h, -7.0, 9.0)


func _build_lanes() -> void:
	lanes.clear()
	lane_len.clear()
	beaches.clear()
	for i in LANE_DEFS.size():
		var ld: Dictionary = LANE_DEFS[i]
		var a0 := float(ld["angle"])
		var coast := coast_at(a0)
		var r_end := PLAZA_R - 0.5
		var r_start := coast + 15.0
		var pts := PackedVector3Array()
		var r := r_start
		while r > r_end:
			var wig := sin(r * 0.06 + float(ld["phase"])) * float(ld["wiggle"]) * smoothstep(PLAZA_R, PLAZA_R + 14.0, r)
			var a := deg_to_rad(a0) + wig
			pts.append(Vector3(sin(a) * r, 0.0, cos(a) * r))
			r -= 1.0
		var cum := PackedFloat32Array()
		var acc := 0.0
		for k in pts.size():
			if k > 0:
				acc += pts[k].distance_to(pts[k - 1])
			cum.append(acc)
		lanes.append(pts)
		lane_len.append(cum)
		var landing := lane_point_at_radius(i, coast + 1.5)
		var spawn := pts[0]
		beaches.append({"name": ld["name"], "label": ld["label"], "lane": i, "spawn": spawn, "landing": landing, "angle": a0})


func _idx(ix: int, iz: int) -> int:
	return iz * n_cells + ix


func _build_heightfield() -> void:
	n_cells = int(EXTENT * 2.0 / GRID) + 1
	heights.resize(n_cells * n_cells)
	lane_mask.resize(n_cells * n_cells)
	plaza_mask.resize(n_cells * n_cells)
	lane_mask.fill(0.0)
	plaza_mask.fill(0.0)
	for iz in n_cells:
		var z := -EXTENT + iz * GRID
		for ix in n_cells:
			var x := -EXTENT + ix * GRID
			heights[_idx(ix, iz)] = _base_height(x, z)
	# Lane distance mask (rasterise each segment into nearby cells).
	var lane_h: Array = []
	for li in lanes.size():
		var pts: PackedVector3Array = lanes[li]
		# Smooth lane height profile: base height without bumps, low-passed along the lane.
		var raw := PackedFloat32Array()
		for p in pts:
			raw.append(_sample_raw(p.x, p.z))
		var smooth := raw.duplicate()
		for k in pts.size():
			var acc := 0.0
			var cnt := 0.0
			for j in range(maxi(0, k - 4), mini(pts.size(), k + 5)):
				acc += raw[j]
				cnt += 1.0
			smooth[k] = acc / cnt
		lane_h.append(smooth)
	var target := heights.duplicate()
	var weight := PackedFloat32Array()
	weight.resize(heights.size())
	weight.fill(0.0)
	for li in lanes.size():
		var pts: PackedVector3Array = lanes[li]
		var lh: PackedFloat32Array = lane_h[li]
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var minx := int(floor((minf(a.x, b.x) - 4.0 + EXTENT) / GRID))
			var maxx := int(ceil((maxf(a.x, b.x) + 4.0 + EXTENT) / GRID))
			var minz := int(floor((minf(a.z, b.z) - 4.0 + EXTENT) / GRID))
			var maxz := int(ceil((maxf(a.z, b.z) + 4.0 + EXTENT) / GRID))
			for iz in range(maxi(0, minz), mini(n_cells, maxz + 1)):
				for ix in range(maxi(0, minx), mini(n_cells, maxx + 1)):
					var p := Vector3(-EXTENT + ix * GRID, 0.0, -EXTENT + iz * GRID)
					var ab := b - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var q := a + ab * t
					var dist := Vector2(p.x - q.x, p.z - q.z).length()
					var w := 1.0 - smoothstep(LANE_W * 0.8, LANE_W + 2.6, dist)
					var i := _idx(ix, iz)
					if w > weight[i]:
						weight[i] = w
						target[i] = lerpf(lh[k], lh[k + 1], t)
					var m := 1.0 - smoothstep(LANE_W - 0.4, LANE_W + 0.5, dist)
					if m > lane_mask[i]:
						lane_mask[i] = m
	for i in heights.size():
		if weight[i] > 0.0:
			heights[i] = lerpf(heights[i], target[i], weight[i] * 0.85)
	# Plaza: flat terrace around the lighthouse.
	for iz in n_cells:
		var z := -EXTENT + iz * GRID
		for ix in n_cells:
			var x := -EXTENT + ix * GRID
			var r := sqrt(x * x + z * z)
			if r < PLAZA_R + 6.0:
				var w := 1.0 - smoothstep(PLAZA_R, PLAZA_R + 5.0, r)
				var i := _idx(ix, iz)
				heights[i] = lerpf(heights[i], PLAZA_H, w)
				plaza_mask[i] = 1.0 - smoothstep(PLAZA_R - 0.6, PLAZA_R + 0.2, r)


func _sample_raw(x: float, z: float) -> float:
	var fx := clampf((x + EXTENT) / GRID, 0.0, n_cells - 1.001)
	var fz := clampf((z + EXTENT) / GRID, 0.0, n_cells - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[_idx(ix, iz)]
	var h10 := heights[_idx(ix + 1, iz)]
	var h01 := heights[_idx(ix, iz + 1)]
	var h11 := heights[_idx(ix + 1, iz + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func height_at(x: float, z: float) -> float:
	if absf(x) >= EXTENT - 1.0 or absf(z) >= EXTENT - 1.0:
		return -7.0
	return _sample_raw(x, z)


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func lane_at(x: float, z: float) -> float:
	if absf(x) >= EXTENT - 1.0 or absf(z) >= EXTENT - 1.0:
		return 0.0
	var ix := clampi(int(round((x + EXTENT) / GRID)), 0, n_cells - 1)
	var iz := clampi(int(round((z + EXTENT) / GRID)), 0, n_cells - 1)
	return lane_mask[_idx(ix, iz)]


func plaza_at(x: float, z: float) -> float:
	var ix := clampi(int(round((x + EXTENT) / GRID)), 0, n_cells - 1)
	var iz := clampi(int(round((z + EXTENT) / GRID)), 0, n_cells - 1)
	return plaza_mask[_idx(ix, iz)]


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.6
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func is_walkable(x: float, z: float) -> bool:
	return height_at(x, z) > -0.55


# --- lanes -------------------------------------------------------------------------------------------------

func lane_point_at_radius(li: int, r: float) -> Vector3:
	var pts: PackedVector3Array = lanes[li]
	var best := pts[pts.size() - 1]
	var best_d := INF
	for p in pts:
		var d := absf(Vector2(p.x, p.z).length() - r)
		if d < best_d:
			best_d = d
			best = p
	return best


func lane_dir_at_radius(li: int, r: float) -> Vector3:
	var pts: PackedVector3Array = lanes[li]
	var best_k := 0
	var best_d := INF
	for k in pts.size():
		var d := absf(Vector2(pts[k].x, pts[k].z).length() - r)
		if d < best_d:
			best_d = d
			best_k = k
	var a := pts[maxi(0, best_k - 2)]
	var b := pts[mini(pts.size() - 1, best_k + 2)]
	return (b - a).normalized() # pointing inward (towards the lighthouse)


## Point at distance s along lane li (0 = sea spawn), on the ground.
func lane_sample(li: int, s: float) -> Vector3:
	var pts: PackedVector3Array = lanes[li]
	var cum: PackedFloat32Array = lane_len[li]
	if s <= 0.0:
		return ground(pts[0])
	if s >= cum[cum.size() - 1]:
		return ground(pts[pts.size() - 1])
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var t := (s - cum[lo]) / maxf(cum[hi] - cum[lo], 1e-5)
	var p := pts[lo].lerp(pts[hi], t)
	return ground(p)


func lane_length(li: int) -> float:
	var cum: PackedFloat32Array = lane_len[li]
	return cum[cum.size() - 1]


## Distance along the lane of the point closest to p.
func lane_project(li: int, p: Vector3) -> float:
	var pts: PackedVector3Array = lanes[li]
	var cum: PackedFloat32Array = lane_len[li]
	var best_s := 0.0
	var best_d := INF
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := q.distance_squared_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_s = lerpf(cum[k], cum[k + 1], t)
	return best_s


# --- build spots -------------------------------------------------------------------------------------------

func _build_spots() -> void:
	spots.clear()
	for sd in SPOT_DEFS:
		var pos: Vector3
		var yaw := 0.0
		var lane := -1
		if sd.has("at"):
			var at: Vector2 = sd["at"]
			pos = Vector3(at.x, 0, at.y)
			# Face the plaza.
			yaw = atan2(-pos.x, -pos.z) if pos.length() > 0.1 else 0.0
		elif sd.get("coast", false):
			lane = int(sd["lane"])
			var ang := float(LANE_DEFS[lane]["angle"])
			var c := coast_at(ang)
			var p := lane_point_at_radius(lane, c)
			var inward := lane_dir_at_radius(lane, c)
			var right := Vector3(-inward.z, 0, inward.x)
			pos = p + right * float(sd["off"])
			# Slide along the coast normal until the spot sits on the waterline.
			var out := Vector3(pos.x, 0, pos.z).normalized()
			for k in 40:
				var h := _base_height(pos.x, pos.z)
				if h > 0.4:
					pos += out * 0.5
				elif h < -0.2:
					pos -= out * 0.5
				else:
					break
			yaw = atan2(out.x, out.z) # dock points out to sea
		else:
			lane = int(sd["lane"])
			var r := float(sd["r"])
			var p := lane_point_at_radius(lane, r)
			var inward := lane_dir_at_radius(lane, r)
			var right := Vector3(-inward.z, 0, inward.x)
			pos = p + right * float(sd["off"])
			yaw = atan2(inward.x, inward.z) # walls lie across the lane
		spots.append({"type": sd["type"], "ring": int(sd["ring"]), "pos": pos, "yaw": yaw, "lane": lane, "r": float(sd.get("r", 0.0))})


func _flatten_spots() -> void:
	for sp in spots:
		var t: String = sp["type"]
		if t == "pharos" or t == "dock":
			continue
		var p: Vector3 = sp["pos"]
		var rad := 3.4 if t != "farm" else 5.2
		if t == "wall":
			rad = 2.5
		var h := height_at(p.x, p.z)
		var ix0 := int(floor((p.x - rad - 3.0 + EXTENT) / GRID))
		var iz0 := int(floor((p.z - rad - 3.0 + EXTENT) / GRID))
		var ix1 := int(ceil((p.x + rad + 3.0 + EXTENT) / GRID))
		var iz1 := int(ceil((p.z + rad + 3.0 + EXTENT) / GRID))
		for iz in range(maxi(0, iz0), mini(n_cells, iz1 + 1)):
			for ix in range(maxi(0, ix0), mini(n_cells, ix1 + 1)):
				var x := -EXTENT + ix * GRID
				var z := -EXTENT + iz * GRID
				var d := Vector2(x - p.x, z - p.z).length()
				var w := 1.0 - smoothstep(rad, rad + 3.0, d)
				if w > 0.0:
					var i := _idx(ix, iz)
					heights[i] = lerpf(heights[i], h, w)
	for sp in spots:
		var p: Vector3 = sp["pos"]
		if sp["type"] == "dock":
			sp["pos"] = Vector3(p.x, 0.0, p.z)
		else:
			sp["pos"] = ground(p)


# --- terrain mesh ------------------------------------------------------------------------------------------

func _terrain_color(c: Vector3, n: Vector3, rng: RandomNumberGenerator) -> Color:
	var h := c.y
	var slope := 1.0 - n.y
	var ang := angle_of(c.x, c.z)
	var b := beach_weight(ang)
	var r := Vector2(c.x, c.z).length()
	var d_coast := coast_at(ang) - r
	var var_n := noise2.get_noise_2d(c.x * 1.3, c.z * 1.3)
	var col: Color
	if h < 0.16:
		col = Pal.SAND_WET.darkened(0.05)
	elif h < 1.2 and b > 0.35 and d_coast < 15.0:
		col = Pal.SAND.lerp(Pal.SAND_WET, smoothstep(0.65, 0.18, h) * 0.6)
	else:
		var g := noise.get_noise_2d(c.x * 0.8 + 13.0, c.z * 0.8 - 7.0)
		col = Pal.GRASS_DARK.lerp(Pal.GRASS, smoothstep(-0.45, 0.05, g))
		col = col.lerp(Pal.GRASS_LIGHT, smoothstep(0.1, 0.55, g))
		var dry := noise.get_noise_2d(c.x * 0.55 + 40.0, c.z * 0.55 + 9.0)
		col = col.lerp(Pal.GRASS_DRY, smoothstep(0.18, 0.5, dry) * 0.75)
		# Near the beaches the grass thins into sand.
		col = col.lerp(Pal.SAND, (1.0 - smoothstep(1.1, 2.0, h)) * b * 0.65)
	if slope > 0.34:
		col = Pal.ROCK.lerp(Pal.ROCK_DARK, clampf((slope - 0.34) * 2.2 + var_n * 0.25, 0.0, 1.0))
	elif slope > 0.24 and h > 0.3:
		col = col.lerp(Pal.ROCK, (slope - 0.24) / 0.1 * 0.6)
	var lane := lane_at(c.x, c.z)
	if lane > 0.05 and h > 0.12:
		# The road itself is a ribbon mesh; underneath, the grass is just trodden a little.
		col = col.lerp(Pal.GRASS_DRY.lerp(Pal.PATH, 0.4), smoothstep(0.5, 1.0, lane) * 0.5)
	var pz := plaza_at(c.x, c.z)
	if pz > 0.0:
		var edge := smoothstep(PLAZA_R - 1.6, PLAZA_R - 0.9, r)
		var stone := Pal.LIMESTONE.lerp(Pal.LIMESTONE_DARK, edge * 0.8)
		col = col.lerp(stone, pz)
	var k := 1.0 + rng.randf_range(-0.018, 0.018)
	return Color(col.r * k, col.g * k, col.b * k, 1.0)


func _build_terrain_mesh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ext := EXTENT - 4.0
	var n := int(ext * 2.0 / MESH_CELL) + 1
	var vx := PackedVector3Array()
	vx.resize(n * n)
	for iz in n:
		for ix in n:
			var x := -ext + ix * MESH_CELL
			var z := -ext + iz * MESH_CELL
			if ix > 0 and ix < n - 1 and iz > 0 and iz < n - 1:
				# Jitter, but keep the vertices of paths/plaza tidy.
				var j := 0.32 * (1.0 - lane_at(x, z) * 0.6) * (1.0 - plaza_at(x, z))
				x += rng.randf_range(-j, j) * MESH_CELL
				z += rng.randf_range(-j, j) * MESH_CELL
			vx[iz * n + ix] = Vector3(x, height_at(x, z), z)
	var mb := MeshBuilder.new()
	for iz in n - 1:
		for ix in n - 1:
			var a := vx[iz * n + ix]
			var b := vx[iz * n + ix + 1]
			var c := vx[(iz + 1) * n + ix + 1]
			var d := vx[(iz + 1) * n + ix]
			if maxf(maxf(a.y, b.y), maxf(c.y, d.y)) < -0.9:
				continue
			# Alternate the diagonal for a less regular pattern.
			var tris: Array
			if (ix + iz) % 2 == 0:
				tris = [[a, d, c], [a, c, b]]
			else:
				tris = [[a, d, b], [b, d, c]]
			for t in tris:
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				var cen := (p0 + p1 + p2) / 3.0
				mb.tri_raw(p0, p1, p2, _terrain_color(cen, nrm, rng))
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mb.commit()
	terrain.material_override = Materials.lowpoly()
	add_child(terrain)


# --- paths and plaza ---------------------------------------------------------------------------------------

## Dirt roads as ribbons laid on the terrain (crisp edges instead of jagged triangle colouring) and a paved
## plaza of concentric stone courses around the lighthouse.
func _build_paths_and_plaza() -> void:
	var mb := MeshBuilder.new(515)
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	for li in lanes.size():
		var pts: PackedVector3Array = lanes[li]
		var n := pts.size()
		var have := false
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in n:
			var p := pts[k]
			var ang := angle_of(p.x, p.z)
			var inland := coast_at(ang) - Vector2(p.x, p.z).length()
			if inland < 9.0 or Vector2(p.x, p.z).length() < PLAZA_R - 1.0:
				have = false
				continue
			var dir := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)])
			dir.y = 0.0
			dir = dir.normalized()
			var right := Vector3(-dir.z, 0, dir.x)
			# Width breathes a little; the road narrows towards the beach.
			var w := LANE_W * (0.92 + 0.12 * noise2.get_noise_2d(p.x * 3.0, p.z * 3.0)) * clampf((inland - 9.0) / 6.0 + 0.55, 0.55, 1.0)
			var l := p - right * w
			var r := p + right * w
			l.y = height_at(l.x, l.z) + 0.05
			r.y = height_at(r.x, r.z) + 0.05
			if have:
				var c := Pal.PATH.lerp(Pal.PATH_DARK, clampf(0.35 + noise2.get_noise_2d(p.x, p.z) * 0.6, 0.0, 1.0))
				var k2 := 1.0 + rng.randf_range(-0.025, 0.025)
				c = Color(c.r * k2, c.g * k2, c.b * k2)
				var mid_prev := (prev_l + prev_r) * 0.5 + Vector3(0, 0.005, 0)
				var mid := (l + r) * 0.5 + Vector3(0, 0.005, 0)
				# Two halves so the crown of the road catches the light slightly differently.
				mb.quad(prev_l, mid_prev, mid, l, c)
				mb.quad(mid_prev, prev_r, r, mid, c.darkened(0.03))
				# Pebbles along the verge.
				if rng.randf() < 0.35:
					var side := -1.0 if rng.randf() < 0.5 else 1.0
					var q := p + right * side * (w + rng.randf_range(0.05, 0.3))
					q.y = height_at(q.x, q.z)
					mb.ico(q + Vector3(0, 0.05, 0), rng.randf_range(0.08, 0.16), Pal.ROCK.lerp(Pal.LIMESTONE, rng.randf()), 0, 0.15, Vector3(1.0, 0.55, 1.0))
			prev_l = l
			prev_r = r
			have = true
	# Plaza: concentric courses of limestone slabs with thin joints.
	var y := PLAZA_H + 0.04
	var r0 := 0.0
	var ring := 0
	while r0 < PLAZA_R - 0.05:
		var r1 := minf(PLAZA_R, r0 + (1.4 if ring == 0 else 1.05))
		var circ := TAU * (r0 + r1) * 0.5
		var segs := maxi(6, int(circ / 1.25))
		var off := rng.randf() * TAU
		for i in segs:
			var a0 := off + TAU * float(i) / segs + 0.012
			var a1 := off + TAU * float(i + 1) / segs - 0.012
			var ri := r0 + 0.04
			var ro := r1 - 0.04
			var c := Pal.LIMESTONE if rng.randf() > 0.35 else Pal.LIMESTONE.lerp(Pal.LIMESTONE_DARK, 0.45)
			if r1 >= PLAZA_R - 0.01:
				c = Pal.LIMESTONE_DARK
			var k3 := 1.0 + rng.randf_range(-0.03, 0.03)
			c = Color(c.r * k3, c.g * k3, c.b * k3)
			var p0 := Vector3(cos(a0) * ri, y, sin(a0) * ri)
			var p1 := Vector3(cos(a1) * ri, y, sin(a1) * ri)
			var p2 := Vector3(cos(a1) * ro, y, sin(a1) * ro)
			var p3 := Vector3(cos(a0) * ro, y, sin(a0) * ro)
			if ri < 0.1:
				mb.tri(Vector3(0, y, 0), p2, p3, c)
			else:
				mb.quad(p0, p1, p2, p3, c)
		r0 = r1
		ring += 1
	# Joint colour underneath the slabs.
	mb.cyl(Vector3(0, y - 0.03, 0), 0.02, PLAZA_R, PLAZA_R, 40, Pal.LIMESTONE_DARK.darkened(0.25), true)
	var mi := MeshInstance3D.new()
	mi.name = "PathsPlaza"
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- water depth texture -----------------------------------------------------------------------------------

func _build_water_texture() -> void:
	var size := 256
	var span := 220.0
	water_image = Image.create(size, size, false, Image.FORMAT_L8)
	for iy in size:
		for ix in size:
			var x := -span * 0.5 + (ix + 0.5) * span / size
			var z := -span * 0.5 + (iy + 0.5) * span / size
			var h := height_at(x, z) if (absf(x) < EXTENT - 1.0 and absf(z) < EXTENT - 1.0) else -7.0
			var d := clampf(-h / 6.0, 0.0, 1.0)
			water_image.set_pixel(ix, iy, Color(d, d, d))
	var tex := ImageTexture.create_from_image(water_image)
	RenderingServer.global_shader_parameter_set("g_water_tex", tex)
	RenderingServer.global_shader_parameter_set("g_water_rect", Vector4(-span * 0.5, -span * 0.5, span, span))


func spots_of(type: String) -> Array:
	var out: Array = []
	for s in spots:
		if s["type"] == type:
			out.append(s)
	return out
