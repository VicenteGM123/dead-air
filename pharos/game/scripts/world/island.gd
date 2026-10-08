class_name Island
extends Node3D
## Delos: procedural heightfield island with four landing beaches, cliffs elsewhere, dirt paths (the lanes the
## creatures of Nyx walk) converging on the lighthouse plaza, and the fixed build spots.
##
## The ground is laid out in concentric rings (see Landscape): plaza, village meadow, terraced fields with
## dry-stone risers, golden phrygana hills with hummocks and hollows, cliffs, dunes and beaches, plus one lush
## gully running from a spring down to a pebble cove. Island precomputes per-cell fields on its 1 m grid
## (smoothed height, lane / spot distance, terrace weight, zone, dryness, curvature) that Props and Grass read.
##
## Coordinates: X east, Z south, Y up. The lighthouse stands at the origin on top of a hill.

const GRID := 1.0 # heightfield resolution (m)
const EXTENT := 100.0 # heightfield covers [-EXTENT, EXTENT]^2
const MESH_CELL := 1.25
const PLAZA_R := 7.5
const PLAZA_H := 4.2
const LANE_W := 1.5 # half width of the dirt paths
const S := Landscape.TERRACE_STEP
const DL_MAX := 9.0
const DS_MAX := 9.0
## Field window: per-cell landscape fields are computed for |x|, |z| <= FIELD_EXT (the whole island).
const FIELD_EXT := 74.0
## Ground map: RGBA8 over [-GM_EXT, GM_EXT]^2. R = contact AO, G = bare soil / wear.
const GM_N := 512
const GM_EXT := 72.0

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

## Half extents (outline half + margin) of each spot type, in the spot's local X / Z. Towers are circles.
const SPOT_HALF := {
	"house": Vector2(2.8, 2.5), "barracks": Vector2(3.3, 2.9), "farm": Vector2(5.4, 5.4),
	"wall": Vector2(4.4, 0.9), "dock": Vector2(2.0, 1.6),
}
const TOWER_R := 2.1

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

## Landscape fields on the heightfield grid (same indexing as heights).
var hs := PackedFloat32Array() # smoothed base height
var grad := PackedFloat32Array() # |gradient(hs)|
var dl := PackedFloat32Array() # distance to the nearest lane centreline (clamped at DL_MAX)
var ds := PackedFloat32Array() # signed distance to the nearest spot box (clamped at DS_MAX)
var gully_d := PackedFloat32Array()
var gully_s := PackedFloat32Array()
var temenos_d := PackedFloat32Array()
var landmark_d := PackedFloat32Array()
var terrace_w := PackedFloat32Array()
var dryness := PackedFloat32Array()
var lap := PackedFloat32Array() # curvature of the final heights (>0 concave)
var slope := PackedFloat32Array() # 1 - normal.y of the final heights
var zone := PackedByteArray()
var crop := PackedByteArray() # Landscape.CROP_* on terraced cells
var block := PackedByteArray() # Landscape block id + 1 (0 = none)
var hummocks: Array = [] # {pos: Vector2, r, h}
var hollows: Array = [] # {pos: Vector2, r, h}
var block_lowest := {} # block -> lowest terraced bench level
var block_highest := {}

var _bw := PackedFloat32Array() # beach weight per degree (fast lookup for shading)
var _lane_near := PackedInt32Array() # nearest lane segment (li * 4096 + k)
var _lane_t := PackedFloat32Array()
var _n_patch := PackedFloat32Array()
var _n_dry := PackedFloat32Array()
var _n_grus := PackedFloat32Array()
var _cell_col := PackedColorArray()
var _facet_col := PackedColorArray()
var _facet_nrm := PackedVector3Array()
var _facet_d := PackedFloat32Array() # plane offset: n . p = d
var _mesh_n := 0
var _mesh_ext := 0.0
var _iso_cache := {}
var _zones_debug := false

var _gm := PackedByteArray()
var _gm_base := PackedByteArray()
var _gm_tex: ImageTexture
var _bld := {} # building key -> [Vector2 pos, radius]
var _bld_t := 0.0


func generate(seed_value: int = 7) -> void:
	var t0 := Time.get_ticks_usec()
	_zones_debug = "zones=1" in OS.get_cmdline_user_args() or "--zones=1" in OS.get_cmdline_user_args()
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	noise2.seed = seed_value + 11
	noise2.frequency = 0.11
	noise2.fractal_octaves = 2
	_build_coast()
	_bw.resize(361)
	for d in 361:
		_bw[d] = beach_weight(float(d))
	_build_lanes()
	_build_spots()
	var t1 := Time.get_ticks_usec()
	_build_heightfield()
	var t2 := Time.get_ticks_usec()
	_flatten_spots()
	_build_fields()
	var t3 := Time.get_ticks_usec()
	_build_terrain_mesh()
	var t4 := Time.get_ticks_usec()
	_build_paths_and_plaza()
	_build_ground_map()
	_build_water_texture()
	var t5 := Time.get_ticks_usec()
	print("Island: %d terrain tris, %d m2 terraced, %d hummocks, %d hollows | shape %d ms, heights %d ms, fields %d ms, mesh %d ms, rest %d ms" % [terrain.mesh.get_faces().size() / 3, _count_terraced(), hummocks.size(), hollows.size(), (t1 - t0) / 1000, (t2 - t1) / 1000, (t3 - t2) / 1000, (t4 - t3) / 1000, (t5 - t4) / 1000])


func _count_terraced() -> int:
	var n := 0
	for w in terrace_w:
		if w > 0.5:
			n += 1
	return n


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


func _bw_at(angle_deg: float) -> float:
	var i := int(angle_deg)
	return lerpf(_bw[i], _bw[mini(i + 1, 360)], angle_deg - float(i))


## Analytic height before paths and spots are carved in. `roll` keeps the small noise2 bumps of the original
## shape (the build spots are placed on it); the heightfield replaces them with the rolling-ground term.
func _base_height(x: float, z: float, roll: bool = true) -> float:
	var r := sqrt(x * x + z * z)
	var ang := angle_of(x, z)
	var R := coast_at(ang)
	var d := R - r # >0 inland
	var b := beach_weight(ang)
	var h: float
	if d < 0.0:
		var sl := lerpf(0.42, 0.13, b)
		h = -0.35 + d * sl
	else:
		var beach := d * 0.055 + smoothstep(9.0, 26.0, d) * 1.6
		var cliff := smoothstep(0.0, 3.2, d) * 2.6 + smoothstep(3.0, 20.0, d) * 0.6
		h = lerpf(cliff, beach, b) - 0.35 * (1.0 - smoothstep(0.0, 1.5, d)) * b
		h += noise.get_noise_2d(x, z) * 0.7 * smoothstep(4.0, 16.0, d)
		if roll:
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


## Nearest grid cell index (clamped).
func _ci(x: float, z: float) -> int:
	var ix := clampi(int(round((x + EXTENT) / GRID)), 0, n_cells - 1)
	var iz := clampi(int(round((z + EXTENT) / GRID)), 0, n_cells - 1)
	return iz * n_cells + ix


func _bilerp(a: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + EXTENT) / GRID, 0.0, n_cells - 1.001)
	var fz := clampf((z + EXTENT) / GRID, 0.0, n_cells - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n_cells + ix
	return lerpf(lerpf(a[i], a[i + 1], tx), lerpf(a[i + n_cells], a[i + n_cells + 1], tx), tz)


func _win() -> Vector2i:
	var lo := int(round((-FIELD_EXT + EXTENT) / GRID))
	var hi := int(round((FIELD_EXT + EXTENT) / GRID))
	return Vector2i(lo, hi)


# --- heightfield -------------------------------------------------------------------------------------------

func _build_heightfield() -> void:
	n_cells = int(EXTENT * 2.0 / GRID) + 1
	var N := n_cells * n_cells
	heights.resize(N)
	lane_mask.resize(N)
	plaza_mask.resize(N)
	lane_mask.fill(0.0)
	plaza_mask.fill(0.0)
	var h0 := PackedFloat32Array()
	h0.resize(N)
	var nv := PackedFloat32Array()
	nv.resize(N)
	for iz in n_cells:
		var z := -EXTENT + iz * GRID
		for ix in n_cells:
			var x := -EXTENT + ix * GRID
			var i := iz * n_cells + ix
			h0[i] = _base_height(x, z, false)
			if absf(x) <= FIELD_EXT and absf(z) <= FIELD_EXT:
				nv[i] = noise2.get_noise_2d(x, z)
	hs = _blur(h0, 3, 3)
	_compute_grad()
	_lane_distance()
	_spot_distance()
	_feature_fields()
	_terrace_weights()
	# Rolling ground plus terraces (pezoules): benches 0.5 m apart, the smooth slope replaced by steps.
	var w := _win()
	heights = h0.duplicate()
	for iz in range(w.x, w.y + 1):
		var z := -EXTENT + iz * GRID
		for ix in range(w.x, w.y + 1):
			var x := -EXTENT + ix * GRID
			var i := iz * n_cells + ix
			var r := sqrt(x * x + z * z)
			var dco := coast_at(angle_of(x, z)) - r
			if dco < 2.0:
				continue
			var wt := terrace_w[i]
			var amp := lerpf(0.12, 0.30, smoothstep(24.0, 40.0, r)) * smoothstep(2.0, 8.0, dco) * (1.0 - 0.7 * wt)
			var h := h0[i] + nv[i] * amp
			if wt > 0.0:
				var q := hs[i] / S
				var fq := floorf(q)
				var ht := S * (fq + smoothstep(0.78, 1.0, q - fq))
				h += wt * (ht - hs[i])
			heights[i] = h
	_relief_features()
	_carve_gully()
	_lane_blend()
	_sunken_lanes()
	# Plaza: flat terrace around the lighthouse.
	for iz in range(int(EXTENT - PLAZA_R - 7.0), int(EXTENT + PLAZA_R + 8.0)):
		var z := -EXTENT + iz * GRID
		for ix in range(int(EXTENT - PLAZA_R - 7.0), int(EXTENT + PLAZA_R + 8.0)):
			var x := -EXTENT + ix * GRID
			var r := sqrt(x * x + z * z)
			if r < PLAZA_R + 6.0:
				var wp := 1.0 - smoothstep(PLAZA_R, PLAZA_R + 5.0, r)
				var i := _idx(ix, iz)
				heights[i] = lerpf(heights[i], PLAZA_H, wp)
				plaza_mask[i] = 1.0 - smoothstep(PLAZA_R - 0.6, PLAZA_R + 0.2, r)


## Separable box blur (edge clamped), `passes` times.
func _blur(src: PackedFloat32Array, rad: int, passes: int) -> PackedFloat32Array:
	var n := n_cells
	var a := src.duplicate()
	var tmp := PackedFloat32Array()
	tmp.resize(a.size())
	var inv := 1.0 / float(2 * rad + 1)
	for p in passes:
		for iz in n:
			var row := iz * n
			var acc := 0.0
			for j in range(-rad, rad + 1):
				acc += a[row + clampi(j, 0, n - 1)]
			for ix in n:
				tmp[row + ix] = acc * inv
				acc += a[row + mini(ix + rad + 1, n - 1)] - a[row + maxi(ix - rad, 0)]
		for ix in n:
			var acc := 0.0
			for j in range(-rad, rad + 1):
				acc += tmp[clampi(j, 0, n - 1) * n + ix]
			for iz in n:
				a[iz * n + ix] = acc * inv
				acc += tmp[mini(iz + rad + 1, n - 1) * n + ix] - tmp[maxi(iz - rad, 0) * n + ix]
	return a


func _compute_grad() -> void:
	var n := n_cells
	grad.resize(n * n)
	grad.fill(0.0)
	for iz in range(1, n - 1):
		for ix in range(1, n - 1):
			var i := iz * n + ix
			var gx := (hs[i + 1] - hs[i - 1]) * 0.5
			var gz := (hs[i + n] - hs[i - n]) * 0.5
			grad[i] = sqrt(gx * gx + gz * gz)


## Distance to the lane centrelines (exact segment distance within DL_MAX) and the nearest segment, which the
## lane blend uses for its target height.
func _lane_distance() -> void:
	var N := n_cells * n_cells
	dl.resize(N)
	dl.fill(DL_MAX)
	_lane_near.resize(N)
	_lane_near.fill(-1)
	_lane_t.resize(N)
	_lane_t.fill(0.0)
	var n := n_cells
	for li in lanes.size():
		var pts: PackedVector3Array = lanes[li]
		for k in pts.size() - 1:
			var ax := pts[k].x
			var az := pts[k].z
			var bx := pts[k + 1].x
			var bz := pts[k + 1].z
			var abx := bx - ax
			var abz := bz - az
			var l2 := maxf(abx * abx + abz * abz, 1e-6)
			var minx := maxi(0, int(floor(minf(ax, bx) - DL_MAX + EXTENT)))
			var maxx := mini(n - 1, int(ceil(maxf(ax, bx) + DL_MAX + EXTENT)))
			var minz := maxi(0, int(floor(minf(az, bz) - DL_MAX + EXTENT)))
			var maxz := mini(n - 1, int(ceil(maxf(az, bz) + DL_MAX + EXTENT)))
			var code := li * 4096 + k
			for iz in range(minz, maxz + 1):
				var pz := -EXTENT + iz
				var row := iz * n
				var dz0 := pz - az
				for ix in range(minx, maxx + 1):
					var px := -EXTENT + ix
					var dx0 := px - ax
					var t := clampf((dx0 * abx + dz0 * abz) / l2, 0.0, 1.0)
					var dx := dx0 - abx * t
					var dz := dz0 - abz * t
					var d2 := dx * dx + dz * dz
					var i := row + ix
					var cur := dl[i]
					if d2 < cur * cur:
						dl[i] = sqrt(d2)
						_lane_near[i] = code
						_lane_t[i] = t
	for i in N:
		lane_mask[i] = 1.0 - smoothstep(LANE_W - 0.4, LANE_W + 0.5, dl[i])


static func spot_box_sd(sp: Dictionary, x: float, z: float) -> float:
	var t: String = sp["type"]
	var p: Vector3 = sp["pos"]
	var dx := x - p.x
	var dz := z - p.z
	if t == "tower":
		return sqrt(dx * dx + dz * dz) - TOWER_R
	if not SPOT_HALF.has(t):
		return INF
	var half: Vector2 = SPOT_HALF[t]
	var yaw: float = sp["yaw"]
	var c := cos(yaw)
	var s := sin(yaw)
	var lx := dx * c - dz * s
	var lz := dx * s + dz * c
	var qx := absf(lx) - half.x
	var qz := absf(lz) - half.y
	return Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0)


func _spot_distance() -> void:
	var n := n_cells
	ds.resize(n * n)
	ds.fill(DS_MAX)
	for sp in spots:
		var t: String = sp["type"]
		if t == "pharos":
			continue
		var p: Vector3 = sp["pos"]
		var tower := t == "tower"
		var half: Vector2 = SPOT_HALF.get(t, Vector2(TOWER_R, TOWER_R))
		var yaw: float = sp["yaw"]
		var c := cos(yaw)
		var sn := sin(yaw)
		var reach := DS_MAX + half.length()
		var x0 := maxi(0, int(floor(p.x - reach + EXTENT)))
		var x1 := mini(n - 1, int(ceil(p.x + reach + EXTENT)))
		var z0 := maxi(0, int(floor(p.z - reach + EXTENT)))
		var z1 := mini(n - 1, int(ceil(p.z + reach + EXTENT)))
		for iz in range(z0, z1 + 1):
			var dz := -EXTENT + iz - p.z
			for ix in range(x0, x1 + 1):
				var dx := -EXTENT + ix - p.x
				var d: float
				if tower:
					d = sqrt(dx * dx + dz * dz) - TOWER_R
				else:
					var qx := absf(dx * c - dz * sn) - half.x
					var qz := absf(dx * sn + dz * c) - half.y
					var ox := maxf(qx, 0.0)
					var oz := maxf(qz, 0.0)
					d = sqrt(ox * ox + oz * oz) + minf(maxf(qx, qz), 0.0)
				var i := iz * n + ix
				if d < ds[i]:
					ds[i] = d


func _feature_fields() -> void:
	var n := n_cells
	var N := n * n
	gully_d.resize(N)
	gully_d.fill(99.0)
	gully_s.resize(N)
	gully_s.fill(-99.0)
	temenos_d.resize(N)
	temenos_d.fill(99.0)
	landmark_d.resize(N)
	landmark_d.fill(99.0)
	# Gully.
	for iz in range(int(EXTENT + 10.0), int(EXTENT + 42.0)):
		for ix in range(int(EXTENT + 13.0), int(EXTENT + 50.0)):
			var g := Landscape.polyline_dist(Landscape.GULLY_PTS, Vector2(-EXTENT + ix, -EXTENT + iz))
			var i := iz * n + ix
			gully_d[i] = g.x
			gully_s[i] = g.y
	# Temenos.
	var tc := Landscape.TEMENOS_C
	for iz in range(int(tc.y - 20.0 + EXTENT), int(tc.y + 20.0 + EXTENT)):
		for ix in range(int(tc.x - 20.0 + EXTENT), int(tc.x + 20.0 + EXTENT)):
			temenos_d[iz * n + ix] = Landscape.temenos_sd(Vector2(-EXTENT + ix, -EXTENT + iz))
	# Landmark footprints.
	for fp in Landscape.FOOTPRINTS:
		var c: Vector2 = fp[0]
		var r: float = fp[1]
		var reach := r + 10.0
		for iz in range(int(floor(c.y - reach + EXTENT)), int(ceil(c.y + reach + EXTENT)) + 1):
			for ix in range(int(floor(c.x - reach + EXTENT)), int(ceil(c.x + reach + EXTENT)) + 1):
				var i := iz * n + ix
				var d := Vector2(-EXTENT + ix, -EXTENT + iz).distance_to(c) - r
				if d < landmark_d[i]:
					landmark_d[i] = d


func _terrace_weights() -> void:
	var n := n_cells
	terrace_w.resize(n * n)
	terrace_w.fill(0.0)
	var lo := int(EXTENT - 46.0)
	var hi := int(EXTENT + 46.0)
	for iz in range(lo, hi + 1):
		var z := -EXTENT + iz
		for ix in range(lo, hi + 1):
			var x := -EXTENT + ix
			var r := sqrt(x * x + z * z)
			if r < 13.0:
				continue
			var ang := angle_of(x, z)
			var co := coast_at(ang)
			var rout := Landscape.r_out(ang, co)
			if r > rout:
				continue
			var i := iz * n + ix
			var w := smoothstep(13.0, 16.0, r) * (1.0 - smoothstep(rout - 3.0, rout, r))
			w *= smoothstep(3.2, 5.0, dl[i]) * smoothstep(0.8, 2.5, ds[i]) * (1.0 - smoothstep(0.22, 0.30, grad[i]))
			w *= smoothstep(3.0, 6.0, gully_d[i]) * smoothstep(2.0, 5.0, temenos_d[i]) * smoothstep(1.0, 3.0, landmark_d[i])
			var b := _bw_at(ang)
			w *= 1.0 - smoothstep(0.15, 0.25, b) * (1.0 - smoothstep(17.0, 20.0, co - r))
			terrace_w[i] = w


## Pre-classification of the wild hills (before the final zones exist) for hummocks.
func _wildish(i: int, x: float, z: float) -> bool:
	var r := sqrt(x * x + z * z)
	var ang := angle_of(x, z)
	var co := coast_at(ang)
	var dco := co - r
	if r < 16.0 or dco < 6.0 or hs[i] < 1.2:
		return false
	if _bw_at(ang) > 0.2 and dco < 19.0:
		return false
	return r >= Landscape.r_out(ang, co) or grad[i] >= 0.25


## Hummocks (granite knolls) in the wild hills and hollows (damp dips) in meadows: what breaks "el piso plano".
func _relief_features() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7701
	hummocks.clear()
	hollows.clear()
	var tries := 0
	while hollows.size() < 8 and tries < 6000:
		tries += 1
		var a := rng.randf() * TAU
		var rr := rng.randf_range(18.0, 42.0)
		var x := sin(a) * rr
		var z := cos(a) * rr
		var i := _ci(x, z)
		var co := coast_at(angle_of(x, z))
		if co - rr < 9.0 or hs[i] < 1.4 or dl[i] < 4.5 or ds[i] < 2.5 or landmark_d[i] < 2.5 or gully_d[i] < 5.0 or temenos_d[i] < 2.0:
			continue
		var R := rng.randf_range(3.0, 4.5)
		var ok := terrace_w[i] < 0.15
		for k in 8:
			var q := Vector2(x, z) + Vector2.from_angle(TAU * k / 8.0) * R
			if terrace_w[_ci(q.x, q.y)] > 0.4:
				ok = false
		for hm in hummocks + hollows:
			if (hm["pos"] as Vector2).distance_to(Vector2(x, z)) < R + float(hm["r"]) + 1.0:
				ok = false
		if not ok:
			continue
		hollows.append({"pos": Vector2(x, z), "r": R, "h": -rng.randf_range(0.25, 0.35)})
	tries = 0
	while hummocks.size() < 32 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-62.0, 62.0)
		var z := rng.randf_range(-62.0, 62.0)
		var i := _ci(x, z)
		if not _wildish(i, x, z):
			continue
		if dl[i] < 5.5 or ds[i] < 3.5 or landmark_d[i] < 4.0 or gully_d[i] < 6.0 or temenos_d[i] < 2.0:
			continue
		var ok := true
		for hm in hummocks + hollows:
			if (hm["pos"] as Vector2).distance_to(Vector2(x, z)) < 7.0:
				ok = false
				break
		if not ok:
			continue
		var R := rng.randf_range(2.5, 5.0)
		var hh := clampf(0.14 * R + rng.randf_range(-0.1, 0.1), 0.3, 0.7)
		hummocks.append({"pos": Vector2(x, z), "r": R, "h": hh})
	for f in hummocks + hollows:
		var c: Vector2 = f["pos"]
		var R: float = f["r"]
		var hh: float = f["h"]
		for iz in range(int(floor(c.y - R + EXTENT)), int(ceil(c.y + R + EXTENT)) + 1):
			for ix in range(int(floor(c.x - R + EXTENT)), int(ceil(c.x + R + EXTENT)) + 1):
				var d := Vector2(-EXTENT + ix, -EXTENT + iz).distance_to(c)
				if d < R:
					var i := iz * n_cells + ix
					heights[i] += hh * 0.5 * (1.0 + cos(PI * d / R)) * (1.0 - terrace_w[i])


## The spring gully: a flat gravel bed with steep banks, deepening into a ravine through the cliff.
func _carve_gully() -> void:
	var glen := Landscape.gully_length()
	var n := n_cells
	for iz in range(int(EXTENT + 10.0), int(EXTENT + 42.0)):
		for ix in range(int(EXTENT + 13.0), int(EXTENT + 50.0)):
			var i := iz * n + ix
			var gd := gully_d[i]
			if gd >= 6.0:
				continue
			var bed := Landscape.gully_bed(clampf(gully_s[i], 0.0, glen))
			var h := heights[i]
			var target := minf(h, bed + 0.7 * maxf(0.0, gd - 0.7))
			heights[i] = lerpf(h, target, 1.0 - smoothstep(5.0, 6.0, gd))
	var sp := Landscape.SPRING
	for iz in range(int(sp.y - 2.0 + EXTENT), int(sp.y + 3.0 + EXTENT)):
		for ix in range(int(sp.x - 2.0 + EXTENT), int(sp.x + 3.0 + EXTENT)):
			if Vector2(-EXTENT + ix, -EXTENT + iz).distance_to(sp) < 1.3:
				var i := iz * n + ix
				heights[i] = minf(heights[i], 2.62)


## Lanes: low-passed height profile along each lane, blended into the ground around it.
func _lane_blend() -> void:
	var lane_h: Array = []
	for li in lanes.size():
		var pts: PackedVector3Array = lanes[li]
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
	var reach := LANE_W + 2.6
	for i in heights.size():
		var d := dl[i]
		if d >= reach:
			continue
		var code := _lane_near[i]
		if code < 0:
			continue
		var w := 1.0 - smoothstep(LANE_W * 0.8, reach, d)
		var lh: PackedFloat32Array = lane_h[code / 4096]
		var k := code % 4096
		heights[i] = lerpf(heights[i], lerpf(lh[k], lh[k + 1], _lane_t[i]), w * 0.85)


## Sunken lanes: the path sits 12 cm into the ground with a crisp lip at its edge.
func _sunken_lanes() -> void:
	var reach := LANE_W + 1.4
	var n := n_cells
	for i in heights.size():
		var d := dl[i]
		if d >= reach:
			continue
		var x := -EXTENT + float(i % n)
		var z := -EXTENT + float(i / n)
		var r := sqrt(x * x + z * z)
		var inland := coast_at(angle_of(x, z)) - r
		var k := smoothstep(9.0, 11.0, inland) * smoothstep(PLAZA_R + 1.0, PLAZA_R + 3.0, r)
		if k <= 0.0:
			continue
		heights[i] += k * (-0.12 * lane_mask[i] + 0.08 * (smoothstep(LANE_W + 0.3, LANE_W + 0.6, d) - smoothstep(LANE_W + 0.9, LANE_W + 1.4, d)))


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


# --- landscape queries -------------------------------------------------------------------------------------

func zone_at(x: float, z: float) -> int:
	if absf(x) >= EXTENT - 1.0 or absf(z) >= EXTENT - 1.0:
		return Landscape.SEA
	return zone[_ci(x, z)]


func terrace_w_at(x: float, z: float) -> float:
	return _bilerp(terrace_w, x, z)


func dryness_at(x: float, z: float) -> float:
	return _bilerp(dryness, x, z)


func lane_dist_at(x: float, z: float) -> float:
	return _bilerp(dl, x, z)


func spot_sd_at(x: float, z: float) -> float:
	return _bilerp(ds, x, z)


func hs_at(x: float, z: float) -> float:
	return _bilerp(hs, x, z)


func grad_at(x: float, z: float) -> float:
	return _bilerp(grad, x, z)


func slope_at(x: float, z: float) -> float:
	return slope[_ci(x, z)]


func gully_at(x: float, z: float) -> Vector2:
	var i := _ci(x, z)
	return Vector2(gully_d[i], gully_s[i])


func temenos_at(x: float, z: float) -> float:
	return temenos_d[_ci(x, z)]


func landmark_at(x: float, z: float) -> float:
	return landmark_d[_ci(x, z)]


func crop_at(x: float, z: float) -> int:
	return crop[_ci(x, z)]


func block_at(x: float, z: float) -> int:
	return int(block[_ci(x, z)]) - 1


## Bench level k of a terrace point (bench floor height k * S).
func bench_level_at(x: float, z: float) -> int:
	return int(floor(hs_at(x, z) / S))


## Downhill direction of the smoothed slope (unit XZ).
func downhill_at(x: float, z: float) -> Vector2:
	var gx := hs_at(x + 0.7, z) - hs_at(x - 0.7, z)
	var gz := hs_at(x, z + 0.7) - hs_at(x, z - 0.7)
	var g := Vector2(-gx, -gz)
	if g.length_squared() < 1e-8:
		var r := Vector2(x, z)
		return r.normalized() if r.length_squared() > 0.01 else Vector2(0, 1)
	return g.normalized()


func r_out_at(x: float, z: float) -> float:
	var ang := angle_of(x, z)
	return Landscape.r_out(ang, coast_at(ang))


## Colour (rgb, a = grassiness) and normal of the terrain triangle under (x, z).
func facet_color_at(x: float, z: float) -> Color:
	var t := _facet_index(x, z)
	return _facet_col[t] if t >= 0 else Pal.SAND_WET


func facet_normal_at(x: float, z: float) -> Vector3:
	var t := _facet_index(x, z)
	return _facet_nrm[t] if t >= 0 else Vector3.UP


## Height of the actual terrain triangle under (x, z) (height_at is the smooth grid; facets are jittered).
func facet_height_at(x: float, z: float) -> float:
	var t := _facet_index(x, z)
	if t < 0:
		return height_at(x, z)
	var nr := _facet_nrm[t]
	if nr.y < 0.2:
		return height_at(x, z)
	return (_facet_d[t] - nr.x * x - nr.z * z) / nr.y


func cell_index(x: float, z: float) -> int:
	return _ci(x, z)


func _facet_index(x: float, z: float) -> int:
	var fx := (x + _mesh_ext) / MESH_CELL
	var fz := (z + _mesh_ext) / MESH_CELL
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= _mesh_n - 1 or iz >= _mesh_n - 1:
		return -1
	var tx := fx - ix
	var tz := fz - iz
	var q := (iz * (_mesh_n - 1) + ix) * 2
	if (ix + iz) % 2 == 0:
		return q if tz > tx else q + 1
	return q if tx + tz < 1.0 else q + 1


# --- terrace contours --------------------------------------------------------------------------------------

## Iso-lines where floor(v) changes, through the cells whose four corners are in `mask`. Returns polylines
## ({pts: PackedVector2Array, level: int}), chained across cells.
func _iso_lines(v: PackedFloat32Array, mask: PackedByteArray, lo: int, hi: int) -> Array:
	var n := n_cells
	var pos := {}
	var adj := {}
	for iz in range(lo, hi):
		for ix in range(lo, hi):
			var i00 := iz * n + ix
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			if mask[i00] == 0 or mask[i10] == 0 or mask[i01] == 0 or mask[i11] == 0:
				continue
			var v0 := v[i00]
			var v1 := v[i10]
			var v2 := v[i11]
			var v3 := v[i01]
			var fmax := floorf(maxf(maxf(v0, v1), maxf(v2, v3)))
			var fmin := floorf(minf(minf(v0, v1), minf(v2, v3)))
			if fmax == fmin:
				continue
			var L := fmax
			var c0 := v0 >= L
			var c1 := v1 >= L
			var c2 := v2 >= L
			var c3 := v3 >= L
			var x0 := -EXTENT + ix
			var z0 := -EXTENT + iz
			var lev := int(L) + 32
			# Edge keys: bottom (00-10), right (10-11), top (01-11), left (00-01).
			var e := [((iz * n + ix) * 2) * 64 + lev, ((iz * n + ix + 1) * 2 + 1) * 64 + lev, (((iz + 1) * n + ix) * 2) * 64 + lev, ((iz * n + ix) * 2 + 1) * 64 + lev]
			var cross: Array[int] = []
			if c0 != c1:
				cross.append(0)
				pos[e[0]] = Vector2(x0 + (L - v0) / (v1 - v0), z0)
			if c1 != c2:
				cross.append(1)
				pos[e[1]] = Vector2(x0 + 1.0, z0 + (L - v1) / (v2 - v1))
			if c3 != c2:
				cross.append(2)
				pos[e[2]] = Vector2(x0 + (L - v3) / (v2 - v3), z0 + 1.0)
			if c0 != c3:
				cross.append(3)
				pos[e[3]] = Vector2(x0, z0 + (L - v0) / (v3 - v0))
			var pairs: Array = []
			if cross.size() == 2:
				pairs.append([cross[0], cross[1]])
			elif cross.size() == 4:
				var centre := (v0 + v1 + v2 + v3) * 0.25 >= L
				if centre == c0:
					pairs.append([0, 1])
					pairs.append([2, 3])
				else:
					pairs.append([3, 0])
					pairs.append([1, 2])
			for pr in pairs:
				var ka: int = e[pr[0]]
				var kb: int = e[pr[1]]
				if not adj.has(ka):
					adj[ka] = []
				if not adj.has(kb):
					adj[kb] = []
				adj[ka].append(kb)
				adj[kb].append(ka)
	# Chain: start from the open ends, then the loops.
	var used := {}
	var out: Array = []
	var starts: Array = []
	for k in adj:
		if (adj[k] as Array).size() == 1:
			starts.append(k)
	for k in adj:
		if (adj[k] as Array).size() != 1:
			starts.append(k)
	for k0 in starts:
		if used.has(k0):
			continue
		var line := PackedVector2Array()
		var cur: int = k0
		var prev := -1
		while true:
			used[cur] = true
			line.append(pos[cur])
			var nxt := -1
			for k2 in adj[cur]:
				if k2 != prev and not used.has(k2):
					nxt = k2
					break
			if nxt < 0:
				# Close loops.
				for k2 in adj[cur]:
					if k2 == k0 and line.size() > 2:
						line.append(pos[k0])
				break
			prev = cur
			cur = nxt
		if line.size() >= 2:
			out.append({"pts": line, "level": (k0 % 64) - 32})
	return out


static func polyline_length(pts: PackedVector2Array) -> float:
	var acc := 0.0
	for k in range(1, pts.size()):
		acc += pts[k].distance_to(pts[k - 1])
	return acc


## Terrace riser runs (dry-stone retaining walls): contours at (k + 0.89) * S on well-terraced ground, kept when
## at least 6 m long.
func riser_runs() -> Array:
	if _iso_cache.has("riser"):
		return _iso_cache["riser"]
	var n := n_cells
	var v := PackedFloat32Array()
	v.resize(n * n)
	var mask := PackedByteArray()
	mask.resize(n * n)
	mask.fill(0)
	var lo := int(EXTENT - 46.0)
	var hi := int(EXTENT + 46.0)
	for iz in range(lo, hi + 1):
		for ix in range(lo, hi + 1):
			var i := iz * n + ix
			v[i] = hs[i] / S - 0.89
			if terrace_w[i] >= 0.5 and ds[i] > 1.0 and dl[i] > 3.5:
				mask[i] = 1
	var out: Array = []
	for l in _iso_lines(v, mask, lo, hi):
		var pts: PackedVector2Array = l["pts"]
		if polyline_length(pts) >= 4.5:
			out.append(pts)
	_iso_cache["riser"] = out
	return out


## Lines along the benches of a terrace block at height (k + level_frac) * S (bench centre = 0.39).
func bench_lines(blk: int, level_frac: float, min_wt: float = 0.5) -> Array:
	var key := "bench_%d_%.2f_%.2f" % [blk, level_frac, min_wt]
	if _iso_cache.has(key):
		return _iso_cache[key]
	var n := n_cells
	var v := PackedFloat32Array()
	v.resize(n * n)
	var mask := PackedByteArray()
	mask.resize(n * n)
	mask.fill(0)
	var lo := int(EXTENT - 46.0)
	var hi := int(EXTENT + 46.0)
	for iz in range(lo, hi + 1):
		for ix in range(lo, hi + 1):
			var i := iz * n + ix
			v[i] = hs[i] / S - level_frac
			if ds[i] <= 1.0 or dl[i] <= 3.5:
				continue
			if min_wt > 0.0:
				if terrace_w[i] >= min_wt and int(block[i]) - 1 == blk:
					mask[i] = 1
			elif zone[i] == Landscape.FIELDS and Landscape.block_of(angle_of(-EXTENT + ix, -EXTENT + iz)) == blk:
				mask[i] = 1
	var out: Array = []
	for l in _iso_lines(v, mask, lo, hi):
		out.append(l["pts"])
	_iso_cache[key] = out
	return out


## Iso-line of the terrace weight (wT = level), e.g. 0.5 for the field walls around terraced blocks.
func terrace_edge_lines(level: float = 0.5) -> Array:
	var n := n_cells
	var v := PackedFloat32Array()
	v.resize(n * n)
	var mask := PackedByteArray()
	mask.resize(n * n)
	mask.fill(0)
	var lo := int(EXTENT - 46.0)
	var hi := int(EXTENT + 46.0)
	for iz in range(lo, hi + 1):
		for ix in range(lo, hi + 1):
			var i := iz * n + ix
			v[i] = terrace_w[i] - level
			mask[i] = 1
	var out: Array = []
	for l in _iso_lines(v, mask, lo, hi):
		out.append(l["pts"])
	return out


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


func _flatten_disc(p: Vector2, rad: float, fade: float, h: float) -> void:
	var ix0 := int(floor(p.x - rad - fade + EXTENT))
	var iz0 := int(floor(p.y - rad - fade + EXTENT))
	var ix1 := int(ceil(p.x + rad + fade + EXTENT))
	var iz1 := int(ceil(p.y + rad + fade + EXTENT))
	for iz in range(maxi(0, iz0), mini(n_cells, iz1 + 1)):
		for ix in range(maxi(0, ix0), mini(n_cells, ix1 + 1)):
			var d := Vector2(-EXTENT + ix - p.x, -EXTENT + iz - p.y).length()
			var w := 1.0 - smoothstep(rad, rad + fade, d)
			if w > 0.0:
				var i := _idx(ix, iz)
				heights[i] = lerpf(heights[i], h, w)


func _flatten_spots() -> void:
	for sp in spots:
		var t: String = sp["type"]
		if t == "pharos" or t == "dock":
			continue
		var p: Vector3 = sp["pos"]
		var rad := 3.4 if t != "farm" else 5.2
		if t == "wall":
			rad = 2.5
		_flatten_disc(Vector2(p.x, p.z), rad, 3.0, height_at(p.x, p.z))
	# Landmarks that need level ground.
	var flat := [[Landscape.THRESHING, 3.4, 2.0], [Landscape.WELL, 1.2, 1.5], [Landscape.BEEHIVES, 1.5, 1.5], [Landscape.SPRING, 1.4, 1.0], [Landscape.SACRED_BASIN, 1.7, 1.5]]
	for f in flat:
		var c: Vector2 = f[0]
		_flatten_disc(c, f[1], f[2], height_at(c.x, c.y))
	for sp in spots:
		var p: Vector3 = sp["pos"]
		if sp["type"] == "dock":
			sp["pos"] = Vector3(p.x, 0.0, p.z)
		else:
			sp["pos"] = ground(p)


# --- zones, dryness, curvature -----------------------------------------------------------------------------

func _build_fields() -> void:
	var n := n_cells
	var N := n * n
	zone.resize(N)
	zone.fill(Landscape.SEA)
	crop.resize(N)
	crop.fill(0)
	block.resize(N)
	block.fill(0)
	dryness.resize(N)
	dryness.fill(0.0)
	lap.resize(N)
	lap.fill(0.0)
	slope.resize(N)
	slope.fill(0.0)
	_n_patch.resize(N)
	_n_dry.resize(N)
	_n_grus.resize(N)
	var w := _win()
	var glen := Landscape.gully_length()
	block_lowest.clear()
	block_highest.clear()
	for iz in range(w.x, w.y + 1):
		var z := -EXTENT + iz
		for ix in range(w.x, w.y + 1):
			var x := -EXTENT + ix
			var i := iz * n + ix
			var h := heights[i]
			var hx := heights[i + 1] - heights[i - 1]
			var hz := heights[i + n] - heights[i - n]
			slope[i] = 1.0 - 2.0 / sqrt(hx * hx + 4.0 + hz * hz)
			lap[i] = (heights[mini(i + 2, N - 1)] + heights[maxi(i - 2, 0)] + heights[mini(i + 2 * n, N - 1)] + heights[maxi(i - 2 * n, 0)] - 4.0 * h) * 0.25
			_n_patch[i] = noise.get_noise_2d(x * 0.8 + 13.0, z * 0.8 - 7.0)
			_n_dry[i] = noise.get_noise_2d(x * 0.55 + 40.0, z * 0.55 + 9.0)
			_n_grus[i] = noise2.get_noise_2d(x * 0.9 - 21.0, z * 0.9 + 33.0)
			var r := sqrt(x * x + z * z)
			var ang := angle_of(x, z)
			var co := coast_at(ang)
			var dco := co - r
			var b := _bw_at(ang)
			var zid := Landscape.WILD
			if h < 0.16:
				zid = Landscape.SEA
			elif r < 8.3:
				zid = Landscape.PLAZA
			elif dl[i] < 2.1:
				zid = Landscape.LANE
			elif ds[i] < 0.0:
				zid = Landscape.SPOT
			elif b > 0.35 and dco < 15.0 and h < 1.2:
				zid = Landscape.BEACH
			elif b > 0.2 and dco < 19.0 and h < 1.9:
				zid = Landscape.DUNE
			elif gully_d[i] < 3.6 and gully_s[i] > -1.5 and gully_s[i] < 21.0:
				zid = Landscape.GULLY
			elif temenos_d[i] < 2.0:
				zid = Landscape.TEMENOS
			elif (dco < 5.0 and b < 0.35) or slope[i] > 0.24:
				zid = Landscape.CLIFF
			elif r < 16.0:
				zid = Landscape.VILLAGE
			elif r < Landscape.r_out(ang, co) and grad[i] < 0.25:
				zid = Landscape.FIELDS
			zone[i] = zid
			if terrace_w[i] > 0.05:
				var blk := Landscape.block_of(ang)
				block[i] = blk + 1
				if terrace_w[i] > 0.5:
					var k := int(floor(hs[i] / S))
					block_lowest[blk] = mini(int(block_lowest.get(blk, 999)), k)
					block_highest[blk] = maxi(int(block_highest.get(blk, -999)), k)
			# Dryness: drier outwards and on convex ground, damp by water and in hollows.
			var dw := 99.0
			if gully_s[i] > -1.5 and gully_s[i] < glen + 1.0:
				dw = gully_d[i]
			for wp in Landscape.WATER_PTS:
				dw = minf(dw, Vector2(x, z).distance_to(wp))
			var wet := 1.0 - smoothstep(2.0, 8.0, dw)
			for ho in hollows:
				var hd := Vector2(x, z).distance_to(ho["pos"])
				if hd < float(ho["r"]):
					wet = maxf(wet, 0.6 * (1.0 - smoothstep(float(ho["r"]) * 0.6, float(ho["r"]), hd)))
			var lp := lap[i]
			dryness[i] = clampf(0.20 + 0.30 * smoothstep(16.0, 42.0, r) + 0.45 * smoothstep(0.05, 0.45, _n_dry[i]) + 2.5 * maxf(0.0, -lp) - 3.0 * maxf(0.0, lp) - 0.8 * wet, 0.0, 1.0)
	for iz in range(w.x, w.y + 1):
		for ix in range(w.x, w.y + 1):
			var i := iz * n + ix
			if block[i] > 0:
				var blk := int(block[i]) - 1
				crop[i] = Landscape.crop_of(blk, int(floor(hs[i] / S)), int(block_lowest.get(blk, 0)), int(block_highest.get(blk, 0)))


func _hollow_w(x: float, z: float) -> float:
	var w := 0.0
	for ho in hollows:
		var hd := Vector2(x, z).distance_to(ho["pos"])
		var R: float = ho["r"]
		if hd < R:
			w = maxf(w, 1.0 - smoothstep(R * 0.5, R, hd))
	return w


func hollow_at(x: float, z: float) -> float:
	return _hollow_w(x, z)


# --- terrain colour ----------------------------------------------------------------------------------------

## Ground colour of a land cell (rgb) and its grassiness (a), before the per-triangle rules (sand line, rock
## slopes, lanes, plaza, path guard, variation).
func _land_color(i: int, x: float, z: float) -> Color:
	var r := sqrt(x * x + z * z)
	var ang := angle_of(x, z)
	var co := coast_at(ang)
	var rout := Landscape.r_out(ang, co)
	var d_l := dl[i]
	var path_k := 0.5 + 0.5 * smoothstep(3.0, 6.0, d_l)
	var grass := 1.0
	# Village and fields: green meadow in soft patches.
	var g := _n_patch[i]
	var col := Landscape.MEADOW_DARK.lerp(Landscape.MEADOW, smoothstep(-0.45, 0.05, g))
	col = col.lerp(Landscape.MEADOW_LIGHT, smoothstep(0.1, 0.55, g) * path_k)
	# Wild hills: grey-green garrigue, golden dry grass, bare granite grus.
	var wild := Landscape.GARRIGUE.lerp(Landscape.STRAW_DEEP, 0.7 * smoothstep(0.1, 0.4, _n_dry[i]))
	wild = wild.lerp(Landscape.GRUS, 0.8 * smoothstep(0.35, 0.55, _n_grus[i]))
	var w_wild := maxf(smoothstep(rout - 3.0, rout + 1.0, r), smoothstep(0.22, 0.30, grad[i])) * smoothstep(14.0, 17.0, r)
	col = col.lerp(wild, w_wild)
	var kd := lerpf(lerpf(0.35, 0.6, smoothstep(14.0, 17.0, r)), 0.8, w_wild)
	# Terrace benches and risers.
	var wt := terrace_w[i]
	if wt > 0.3:
		var wb := smoothstep(0.3, 0.6, wt)
		var bc := col
		match int(crop[i]):
			Landscape.CROP_OLIVE:
				bc = col.lerp(Landscape.STRAW, 0.35)
			Landscape.CROP_VINE:
				bc = Landscape.MEADOW_DARK
			Landscape.CROP_WHEAT:
				bc = Landscape.STRAW
			Landscape.CROP_ORCHARD:
				bc = col.lerp(Landscape.LUSH, 0.3)
		col = col.lerp(bc, wb)
		kd = lerpf(kd, 0.45, wb)
		var q := hs[i] / S
		var f := q - floorf(q)
		# Riser: a darker earth bank under the dry-stone wall (the wall mesh carries the stone).
		var wr := smoothstep(0.55, 0.7, wt) * smoothstep(0.78, 0.84, f)
		col = col.lerp(Landscape.RISER.lerp(Landscape.MEADOW_DARK, 0.45).darkened(0.08), wr * 0.6)
		grass *= 1.0 - wr
	# The spring gully: gravel bed, lush banks.
	var gd := gully_d[i]
	var in_gully := false
	if gd < 4.2 and gully_s[i] > -1.5 and gully_s[i] < 21.0:
		var wg := 1.0 - smoothstep(3.0, 4.2, gd)
		var gc: Color
		if gd < 0.9:
			gc = Landscape.GRAVEL
			grass *= 1.0 - wg
		else:
			gc = Landscape.LUSH_DARK.lerp(Landscape.LUSH, smoothstep(0.9, 2.2, gd)).lerp(Landscape.MEADOW, smoothstep(2.2, 3.6, gd))
		col = col.lerp(gc, wg)
		kd *= 1.0 - wg
		in_gully = wg > 0.5
	# Sanctuary: a greener, cared-for enclosure.
	var tsd := temenos_d[i]
	var wtm := 1.0 - smoothstep(1.0, 3.0, tsd)
	if wtm > 0.0:
		var tcol := Landscape.MEADOW_DARK.lerp(Landscape.LUSH, 0.5 + 0.5 * g)
		if Vector2(x, z).distance_to(Landscape.SACRED_BASIN) < 3.0:
			tcol = Landscape.LUSH
		col = col.lerp(tcol, wtm)
		kd = lerpf(kd, 0.3, wtm)
	# Dryness.
	col = col.lerp(Landscape.STRAW.lerp(Landscape.STRAW_DEEP, smoothstep(26.0, 36.0, r)), dryness[i] * kd * path_k)
	# Curvature: dark green in dips and at the foot of risers, straw on knolls and terrace lips.
	var lp := lap[i]
	if lp > 0.0:
		col = col.lerp(Landscape.LUSH if in_gully else Landscape.MEADOW_DARK, clampf(lp / 0.12, 0.0, 1.0) * 0.40)
	else:
		col = col.lerp(Landscape.STRAW, clampf(-lp / 0.12, 0.0, 1.0) * 0.35)
	return Color(col.r, col.g, col.b, grass)


func _terrain_color(c: Vector3, nrm: Vector3, rng: RandomNumberGenerator) -> Color:
	var h := c.y
	var sl := 1.0 - nrm.y
	var i := _ci(c.x, c.z)
	if _zones_debug:
		var zc: Color = Landscape.ZONE_DEBUG[zone[i]]
		if terrace_w[i] > 0.5:
			var q := hs[i] / S
			zc = zc.darkened(0.25 if q - floorf(q) > 0.78 else 0.0)
		return Color(zc.r, zc.g, zc.b, 0.0)
	var ang := angle_of(c.x, c.z)
	var b := _bw_at(ang)
	var r := sqrt(c.x * c.x + c.z * c.z)
	var d_coast := coast_at(ang) - r
	var col: Color
	var grass := 0.0
	var land := false
	if h < 0.16:
		col = Pal.SAND_WET.darkened(0.05)
	elif h < 1.2 and b > 0.35 and d_coast < 15.0:
		col = Pal.SAND.lerp(Pal.SAND_WET, smoothstep(0.65, 0.18, h) * 0.6)
	elif gully_d[i] < 4.0 and d_coast < 4.0 and h < 1.0:
		# Pebble cove at the gully mouth.
		col = Pal.SAND.lerp(Landscape.GRAVEL, 0.35)
	else:
		land = true
		var lc := _cell_col[i]
		col = Color(lc.r, lc.g, lc.b)
		grass = lc.a
		# Dunes behind the beaches.
		var w_dune := smoothstep(0.15, 0.25, b) * (1.0 - smoothstep(17.0, 20.0, d_coast)) * (1.0 - smoothstep(1.6, 2.1, h))
		if w_dune > 0.0:
			var dcol := Pal.SAND.lerp(Landscape.DUNE_SAND, smoothstep(0.9, 1.6, h))
			if rng.randf() < 0.25:
				dcol = dcol.lerp(Landscape.MEADOW_DARK, 0.2)
			col = col.lerp(dcol, w_dune)
			grass = lerpf(grass, 0.3, w_dune)
	var var_n := noise2.get_noise_2d(c.x * 1.3, c.z * 1.3)
	if sl > 0.34:
		col = Pal.ROCK.lerp(Pal.ROCK_DARK, clampf((sl - 0.34) * 2.2 + var_n * 0.25, 0.0, 1.0))
		grass = 0.0
	elif sl > 0.24 and h > 0.3:
		col = col.lerp(Pal.ROCK, (sl - 0.24) / 0.1 * 0.6)
		grass *= 1.0 - (sl - 0.24) / 0.1
	var lane := lane_mask[i]
	if lane > 0.05 and h > 0.12:
		# The road itself is a ribbon mesh; underneath, the grass is just trodden a little.
		col = col.lerp(Pal.GRASS_DRY.lerp(Pal.PATH, 0.4), smoothstep(0.5, 1.0, lane) * 0.5)
		grass *= 1.0 - smoothstep(0.3, 0.8, lane)
	var pz := plaza_mask[i]
	if pz > 0.0:
		var edge := smoothstep(PLAZA_R - 1.6, PLAZA_R - 0.9, r)
		var stone := Pal.LIMESTONE.lerp(Pal.LIMESTONE_DARK, edge * 0.8)
		col = col.lerp(stone, pz)
		grass *= 1.0 - pz
	elif land:
		# Path guard: the dirt road stays the lightest band of ground.
		var gw := 1.0 - smoothstep(3.5, 6.0, dl[i])
		if gw > 0.0:
			var y := Landscape.luma(col)
			if y > 0.42:
				var k := pow(0.42 / y, 1.0 / 2.2)
				col = col.lerp(Color(col.r * k, col.g * k, col.b * k), gw)
	var kv := 1.0 + rng.randf_range(-0.03, 0.03)
	var hv := rng.randf_range(-0.02, 0.02)
	return Color(clampf(col.r * kv * (1.0 + hv), 0.0, 1.0), clampf(col.g * kv, 0.0, 1.0), clampf(col.b * kv * (1.0 - hv), 0.0, 1.0), grass)


func _build_terrain_mesh() -> void:
	var n := n_cells
	_cell_col.resize(n * n)
	var w := _win()
	for iz in range(w.x, w.y + 1):
		for ix in range(w.x, w.y + 1):
			var i := iz * n + ix
			if heights[i] > -1.5:
				_cell_col[i] = _land_color(i, -EXTENT + ix, -EXTENT + iz)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_mesh_ext = EXTENT - 4.0
	var m := int(_mesh_ext * 2.0 / MESH_CELL) + 1
	_mesh_n = m
	var vx := PackedVector3Array()
	vx.resize(m * m)
	for iz in m:
		for ix in m:
			var x := -_mesh_ext + ix * MESH_CELL
			var z := -_mesh_ext + iz * MESH_CELL
			if ix > 0 and ix < m - 1 and iz > 0 and iz < m - 1:
				# Jitter, but keep the vertices of paths, plaza and terrace risers tidy.
				var ci := _ci(x, z)
				var j := 0.32 * (1.0 - lane_mask[ci] * 0.6) * (1.0 - plaza_mask[ci]) * (1.0 - 0.5 * terrace_w[ci])
				x += rng.randf_range(-j, j) * MESH_CELL
				z += rng.randf_range(-j, j) * MESH_CELL
			vx[iz * m + ix] = Vector3(x, height_at(x, z), z)
	var nq := (m - 1) * (m - 1)
	_facet_col.resize(nq * 2)
	_facet_nrm.resize(nq * 2)
	_facet_d.resize(nq * 2)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nq * 6)
	norms.resize(nq * 6)
	cols.resize(nq * 6)
	var nv := 0
	var sea := Color(Pal.SAND_WET.r, Pal.SAND_WET.g, Pal.SAND_WET.b, 0.0)
	for iz in m - 1:
		for ix in m - 1:
			var q := (iz * (m - 1) + ix) * 2
			var a := vx[iz * m + ix]
			var b := vx[iz * m + ix + 1]
			var c := vx[(iz + 1) * m + ix + 1]
			var d := vx[(iz + 1) * m + ix]
			if maxf(maxf(a.y, b.y), maxf(c.y, d.y)) < -0.9:
				_facet_col[q] = sea
				_facet_col[q + 1] = sea
				_facet_nrm[q] = Vector3.UP
				_facet_nrm[q + 1] = Vector3.UP
				_facet_d[q] = a.y
				_facet_d[q + 1] = a.y
				continue
			# Alternate the diagonal for a less regular pattern.
			var tris: Array
			if (ix + iz) % 2 == 0:
				tris = [[a, d, c], [a, c, b]]
			else:
				tris = [[a, d, b], [b, d, c]]
			for t in 2:
				var p0: Vector3 = tris[t][0]
				var p1: Vector3 = tris[t][1]
				var p2: Vector3 = tris[t][2]
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
					var tmp := p1
					p1 = p2
					p2 = tmp
				var col := _terrain_color((p0 + p1 + p2) / 3.0, nrm, rng)
				_facet_col[q + t] = col
				_facet_nrm[q + t] = nrm
				_facet_d[q + t] = nrm.dot(p0)
				# Godot's front face is clockwise: emit p0, p2, p1.
				verts[nv] = p0
				verts[nv + 1] = p2
				verts[nv + 2] = p1
				for k in 3:
					norms[nv + k] = nrm
					cols[nv + k] = col
				nv += 3
	verts.resize(nv)
	norms.resize(nv)
	cols.resize(nv)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	terrain.material_override = Materials.terrain()
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
	mi.material_override = Materials.static_twin(Materials.lowpoly())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- ground map (contact AO and bare soil) -----------------------------------------------------------------

## Worn verges along the lanes and the cleared plots of the build spots. Props adds the splats of its objects
## and calls commit_ground_map().
func _build_ground_map() -> void:
	_gm.resize(GM_N * GM_N * 4)
	_gm.fill(0)
	for t in GM_N * GM_N:
		_gm[t * 4 + 3] = 255
	var tpm := GM_N / (2.0 * GM_EXT) # texels per metre
	var n := n_cells
	var w := _win()
	# Lane verges: bare and worn from the ribbon edge to 0.9 m beyond it.
	for iz in range(w.x, w.y + 1):
		for ix in range(w.x, w.y + 1):
			var i := iz * n + ix
			if dl[i] > LANE_W + 1.6 or heights[i] < 0.3:
				continue
			var cx := -EXTENT + ix
			var cz := -EXTENT + iz
			var tx0 := int(floor((cx - 0.5 + GM_EXT) * tpm))
			var tz0 := int(floor((cz - 0.5 + GM_EXT) * tpm))
			for tz in range(maxi(tz0, 0), mini(tz0 + 4, GM_N)):
				for tx in range(maxi(tx0, 0), mini(tx0 + 4, GM_N)):
					var px := (tx + 0.5) / tpm - GM_EXT
					var pz := (tz + 0.5) / tpm - GM_EXT
					var d := _bilerp(dl, px, pz)
					var v := 0.45 * (1.0 - smoothstep(LANE_W, LANE_W + 0.9, d))
					var r := sqrt(px * px + pz * pz)
					v *= smoothstep(PLAZA_R, PLAZA_R + 1.0, r)
					var idx := (tz * GM_N + tx) * 4 + 1
					var bv := int(v * 255.0)
					if bv > _gm[idx]:
						_gm[idx] = bv
	# Empty build spots read as a cleared tan plot inside their stone outline.
	for sp in spots:
		var t: String = sp["type"]
		if t == "pharos" or t == "dock":
			continue
		var p: Vector3 = sp["pos"]
		var reach := 6.0
		for tz in range(maxi(0, int((p.z - reach + GM_EXT) * tpm)), mini(GM_N, int((p.z + reach + GM_EXT) * tpm) + 1)):
			for tx in range(maxi(0, int((p.x - reach + GM_EXT) * tpm)), mini(GM_N, int((p.x + reach + GM_EXT) * tpm) + 1)):
				var px := (tx + 0.5) / tpm - GM_EXT
				var pz := (tz + 0.5) / tpm - GM_EXT
				var v := 0.30 * (1.0 - smoothstep(-0.4, 0.15, spot_box_sd(sp, px, pz)))
				var idx := (tz * GM_N + tx) * 4 + 1
				var bv := int(v * 255.0)
				if bv > _gm[idx]:
					_gm[idx] = bv


## Soft disc / capsule splat into a ground-map channel (0 = AO, 1 = soil), combined with max().
func _splat(ch: int, a: Vector2, b: Vector2, R: float, s: float) -> void:
	if _gm.is_empty() or R <= 0.0 or s <= 0.0:
		return
	var tpm := GM_N / (2.0 * GM_EXT)
	var tx0 := maxi(0, int(floor((minf(a.x, b.x) - R + GM_EXT) * tpm)))
	var tx1 := mini(GM_N - 1, int(ceil((maxf(a.x, b.x) + R + GM_EXT) * tpm)))
	var tz0 := maxi(0, int(floor((minf(a.y, b.y) - R + GM_EXT) * tpm)))
	var tz1 := mini(GM_N - 1, int(ceil((maxf(a.y, b.y) + R + GM_EXT) * tpm)))
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 1e-6)
	var inv := 1.0 / tpm
	for tz in range(tz0, tz1 + 1):
		var pz := (tz + 0.5) * inv - GM_EXT
		for tx in range(tx0, tx1 + 1):
			var px := (tx + 0.5) * inv - GM_EXT
			var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / l2, 0.0, 1.0)
			var dx := px - a.x - ab.x * t
			var dz := pz - a.y - ab.y * t
			var d := sqrt(dx * dx + dz * dz)
			if d >= R:
				continue
			var bv := int(s * (1.0 - smoothstep(0.55, 1.0, d / R)) * 255.0)
			var idx := (tz * GM_N + tx) * 4 + ch
			if bv > _gm[idx]:
				_gm[idx] = mini(bv, 255)


## Contact AO under an object (disc, or a capsule from a to b).
func splat_ao(a: Vector2, R: float, s: float, b: Variant = null) -> void:
	_splat(0, a, a if b == null else b, R, s)


## Bare soil / wear (disc, or a capsule from a to b).
func splat_wear(a: Vector2, R: float, s: float, b: Variant = null) -> void:
	_splat(1, a, a if b == null else b, R, s)


func commit_ground_map() -> void:
	_gm_base = _gm.duplicate()
	_upload_ground_map()


func _upload_ground_map() -> void:
	var img := Image.create_from_data(GM_N, GM_N, false, Image.FORMAT_RGBA8, _gm)
	img.generate_mipmaps()
	if _gm_tex == null:
		_gm_tex = ImageTexture.create_from_image(img)
		var rect := Vector4(-GM_EXT, -GM_EXT, 2.0 * GM_EXT, 2.0 * GM_EXT)
		for mat in [Materials.terrain(), Materials.grass()]:
			mat.set_shader_parameter("ground_tex", _gm_tex)
			mat.set_shader_parameter("ground_rect", rect)
	else:
		_gm_tex.update(img)


## Buildings darken the ground around their footprint while they stand.
func splat_building(key: Variant, pos: Vector3, footprint: float) -> void:
	_bld[key] = [Vector2(pos.x, pos.z), footprint + 0.8]
	_refresh_buildings(Vector2(pos.x, pos.z), footprint + 0.8)


func clear_building(key: Variant) -> void:
	if not _bld.has(key):
		return
	var e: Array = _bld[key]
	_bld.erase(key)
	_refresh_buildings(e[0], e[1])


func _refresh_buildings(c: Vector2, R: float) -> void:
	if _gm_base.is_empty():
		return
	var tpm := GM_N / (2.0 * GM_EXT)
	var tx0 := maxi(0, int(floor((c.x - R + GM_EXT) * tpm)))
	var tx1 := mini(GM_N - 1, int(ceil((c.x + R + GM_EXT) * tpm)))
	var tz0 := maxi(0, int(floor((c.y - R + GM_EXT) * tpm)))
	var tz1 := mini(GM_N - 1, int(ceil((c.y + R + GM_EXT) * tpm)))
	for tz in range(tz0, tz1 + 1):
		for tx in range(tx0, tx1 + 1):
			var idx := (tz * GM_N + tx) * 4
			_gm[idx] = _gm_base[idx]
	for k in _bld:
		var e: Array = _bld[k]
		var p: Vector2 = e[0]
		if p.distance_to(c) < float(e[1]) + R:
			_splat(0, p, p, e[1], 0.45)
	_upload_ground_map()


## Keeps the building AO in sync with the build spots (cheap poll, twice a second).
func _process(delta: float) -> void:
	_bld_t -= delta
	if _bld_t > 0.0 or _gm_base.is_empty():
		return
	_bld_t = 0.5
	var game := get_node_or_null("/root/Game")
	var main: Variant = game.get("main") if game != null else null
	if main == null or not is_instance_valid(main):
		return
	var sp_list: Variant = (main as Object).get("spots")
	if not (sp_list is Array):
		return
	for sp in sp_list:
		if not is_instance_valid(sp):
			continue
		var b: Variant = sp.get("building")
		var has := b != null and is_instance_valid(b)
		var key: int = sp.get_instance_id()
		if has and not _bld.has(key):
			var fp: float = b.get("footprint") if b.get("footprint") != null else 2.0
			if sp.get("type") == "pharos" or sp.get("type") == "wall":
				continue
			splat_building(key, (b as Node3D).global_position, fp)
		elif not has and _bld.has(key):
			clear_building(key)


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
