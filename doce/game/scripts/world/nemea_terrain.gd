extends RefCounted
## Nemea's ground: a 1 m heightfield over [-192, 192]^2 shaped by art-directed fields (the hand-shaped coast, the
## levels of the forest, the escarpment, the thumb, the ridge massif, the east hill), carved by the cave, the
## paths, the house pads and the olive benches; then meshed in 128 m chunks (indexed, smooth normals, vertex colour =
## ground colour + grassiness) with trimesh collision built from the very same triangles, so height_at(), the
## physics floor and what you see always agree.
##
## Triangulation (shared by the mesh, height_at() and the grass shader): quad (ix, iz) with corners a=(ix,iz),
## b=(ix+1,iz), c=(ix+1,iz+1), d=(ix,iz+1) is split along a-c when (ix + iz) is even, along b-d when odd.
##
## Textures produced for the shaders: the ground map (RGBA8 over GM_RECT: R contact AO / cave dark, G bare soil,
## B packed-earth path, A grass exclusion), the ground colour map (RGBA8, the vertex colours: a = grassiness), the
## height map (RF, the vertex heights) and the sea depth map (g_water_tex).

const L := preload("res://scripts/world/nemea_layout.gd")
const N := L.N
const EXT := L.EXT
const CELL := L.CELL
const CHUNK := 128 # cells per chunk side (3 x 3 chunks: few draw calls)
## Terrain chunks whose centre is farther than this from the camera draw their 2 m version.
const LOD_RANGE := 175.0
const GM_N := 768
const GM_EXT := 192.0
const DEEP := -11.0

# Ground colours (sRGB, before the toon shader's saturation boost).
const C_MEADOW := Color("8FB25A")
const C_MEADOW_LIGHT := Color("A9C26A")
const C_MEADOW_DARK := Color("6E9A4A")
const C_LUSH := Color("75A04A")
const C_FOREST := Color("5F8A44")
const C_FOREST_DARK := Color("4E7539")
const C_STRAW := Color("CDB872")
const C_STRAW_DEEP := Color("BFA35E")
const C_GARRIGUE := Color("A3A26E")
const C_SAND := Color("EED9A8")
const C_SAND_WET := Color("D2B888")
const C_SAND_DUNE := Color("E2D29C")
const C_ROCK := Color("B4A390")
const C_ROCK_DARK := Color("8C7D6E")
const C_ROCK_WARM := Color("C2A688")
const C_ROCK_SEA := Color("756A62")
const C_SOIL := Color("A98361")
const C_CAVE_FLOOR := Color("A49CA6")
const C_CAVE_WALL := Color("6E6470")
const C_VILLAGE := Color("A7B866")

var h := PackedFloat32Array() # final heights
var sd := PackedFloat32Array() # signed coast distance (+ inland), metres
var cliff := PackedFloat32Array() # coast cliffness 0 (beach) .. 1 (sea cliff)
var upw := PackedFloat32Array() # 1 on the upper level (thumb, meadow, ridge)
var dry := PackedFloat32Array() # dryness 0..1 (golden garrigue)
var forest_w := PackedFloat32Array() # 1 in the forest
var cave_w := PackedFloat32Array() # 1 inside the cave (floor and walls under the lid)
var path_w := PackedFloat32Array() # 1 on a path, fading 1 m beyond its edge
var pad_w := PackedFloat32Array() # 1 on a flattened pad (houses, plaza, altars)
var path_d := PackedFloat32Array() # distance from the nearest path edge (m, clamped at 6)
var bench := PackedFloat32Array() # olive bench weight (east hill)
var bench_h0 := PackedFloat32Array() # the hill's height before it was cut into benches (riser contours)
var nrm := PackedVector3Array()
var col := PackedColorArray()

var gm := PackedByteArray() # ground map RGBA8 (GM_N^2)
var ground_tex: ImageTexture
var color_tex: ImageTexture
var height_tex: ImageTexture
var detail_tex: ImageTexture
var water_tex: ImageTexture

var paths: Array = [] # [{pts: PackedVector2Array, hw: float, ys: PackedFloat32Array (heights at pts)}]
var chunks: Array = [] # MeshInstance3D
var body: StaticBody3D = null # the terrain's collision (layer 1)
var timings := {}

var _n_roll := FastNoiseLite.new()
var _n_fine := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_patch := FastNoiseLite.new()
var _n_rock := FastNoiseLite.new()
var _palm_r := PackedFloat32Array()


func _init() -> void:
	_n_roll.seed = 1301
	_n_roll.frequency = 0.017
	_n_roll.fractal_octaves = 3
	_n_fine.seed = 77
	_n_fine.frequency = 0.08
	_n_fine.fractal_octaves = 2
	_n_coast.seed = 4242
	_n_coast.frequency = 0.028
	_n_coast.fractal_octaves = 2
	_n_patch.seed = 555
	_n_patch.frequency = 0.045
	_n_patch.fractal_octaves = 2
	_n_rock.seed = 919
	_n_rock.frequency = 0.11
	_n_rock.fractal_octaves = 2


# --- small helpers -------------------------------------------------------------------------------------------

static func idx(ix: int, iz: int) -> int:
	return iz * N + ix


static func gx(ix: int) -> float:
	return -EXT + float(ix) * CELL


## Smooth maximum (union of positive-inside fields with a fillet of size k).
static func smax(a: float, b: float, k: float) -> float:
	var t := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + t * t * k * 0.25


static func smin(a: float, b: float, k: float) -> float:
	var t := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - t * t * k * 0.25


## Inside-ness of a tapered capsule: radius at the nearest point minus the distance (positive inside).
static func capsule_in(px: float, pz: float, a: Vector2, b: Vector2, ra: float, rb: float) -> float:
	var abx := b.x - a.x
	var abz := b.y - a.y
	var t := clampf(((px - a.x) * abx + (pz - a.y) * abz) / (abx * abx + abz * abz), 0.0, 1.0)
	var dx := px - a.x - abx * t
	var dz := pz - a.y - abz * t
	return lerpf(ra, rb, t) - sqrt(dx * dx + dz * dz)


## [distance, t, segment index, signed side (+ left of travel)] from p to a polyline.
static func polyline_d(px: float, pz: float, pts: Array) -> Array:
	var best := INF
	var bt := 0.0
	var bk := 0
	var side := 1.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var abx := b.x - a.x
		var abz := b.y - a.y
		var l2 := abx * abx + abz * abz
		var t := clampf(((px - a.x) * abx + (pz - a.y) * abz) / l2, 0.0, 1.0)
		var dx := px - a.x - abx * t
		var dz := pz - a.y - abz * t
		var d := dx * dx + dz * dz
		if d < best:
			best = d
			bt = t
			bk = k
			side = -1.0 if abx * (pz - a.y) - abz * (px - a.x) < 0.0 else 1.0
	return [sqrt(best), bt, bk, side]


## Signed distance of a rounded rectangle (negative inside).
static func roundrect_sd(px: float, pz: float, c: Vector2, half: Vector2, r: float) -> float:
	var qx := absf(px - c.x) - (half.x - r)
	var qz := absf(pz - c.y) - (half.y - r)
	var ox := maxf(qx, 0.0)
	var oz := maxf(qz, 0.0)
	return sqrt(ox * ox + oz * oz) + minf(maxf(qx, qz), 0.0) - r


static func angle_of(x: float, z: float) -> float:
	return fposmod(rad_to_deg(atan2(x, z)), 360.0)


static func g_ang(a: float, c: float, w: float) -> float:
	var d := absf(fposmod(a - c + 180.0, 360.0) - 180.0) / w
	return exp(-d * d)


# --- queries -------------------------------------------------------------------------------------------------

## Height of the rendered (and collision) triangle under (x, z).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + EXT) / CELL, 0.0, N - 1.0001)
	var fz := clampf((z + EXT) / CELL, 0.0, N - 1.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var ha := h[i]
	var hb := h[i + 1]
	var hc := h[i + N + 1]
	var hd := h[i + N]
	if (ix + iz) & 1 == 0:
		if tx >= tz:
			return ha + (hb - ha) * tx + (hc - hb) * tz
		return ha + (hc - hd) * tx + (hd - ha) * tz
	if tx + tz <= 1.0:
		return ha + (hb - ha) * tx + (hd - ha) * tz
	return hc + (hd - hc) * (1.0 - tx) + (hb - hc) * (1.0 - tz)


## Smooth (vertex-interpolated) ground normal.
func normal_at(x: float, z: float) -> Vector3:
	var fx := clampf((x + EXT) / CELL, 0.0, N - 1.0001)
	var fz := clampf((z + EXT) / CELL, 0.0, N - 1.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return (nrm[i].lerp(nrm[i + 1], tx)).lerp(nrm[i + N].lerp(nrm[i + N + 1], tx), tz).normalized()


## Bilinear sample of a per-vertex field.
func field(a: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + EXT) / CELL, 0.0, N - 1.0001)
	var fz := clampf((z + EXT) / CELL, 0.0, N - 1.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return lerpf(lerpf(a[i], a[i + 1], tx), lerpf(a[i + N], a[i + N + 1], tx), tz)


func color_at(x: float, z: float) -> Color:
	var fx := clampf((x + EXT) / CELL, 0.0, N - 1.0001)
	var fz := clampf((z + EXT) / CELL, 0.0, N - 1.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return col[i].lerp(col[i + 1], tx).lerp(col[i + N].lerp(col[i + N + 1], tx), tz)


## Slope as 1 - normal.y (0 flat, 0.18 = 35 degrees).
func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


# --- generation ----------------------------------------------------------------------------------------------

func generate() -> void:
	var t0 := Time.get_ticks_usec()
	var nn := N * N
	for a: PackedFloat32Array in [h, sd, cliff, upw, dry, forest_w, cave_w, path_w, pad_w, bench]:
		a.resize(nn)
		a.fill(0.0)
	path_d.resize(nn)
	path_d.fill(6.0)
	bench_h0.resize(nn)
	bench_h0.fill(0.0)
	_palm_table()
	_coast()
	var t1 := Time.get_ticks_usec()
	_elevation()
	var t2 := Time.get_ticks_usec()
	_ravine()
	_cave_carve()
	_terraces()
	_pads()
	_paths()
	var t3 := Time.get_ticks_usec()
	_normals()
	_colours()
	var t4 := Time.get_ticks_usec()
	timings["coast"] = (t1 - t0) / 1000
	timings["elevation"] = (t2 - t1) / 1000
	timings["carve"] = (t3 - t2) / 1000
	timings["normals_colours"] = (t4 - t3) / 1000


func _palm_table() -> void:
	_palm_r.resize(361)
	for d in 361:
		var a := float(d)
		var r := L.PALM_R - 10.0 * g_ang(a, 0.0, 26.0) + 6.0 * g_ang(a, 92.0, 30.0) - 4.0 * g_ang(a, 300.0, 18.0)
		r += 3.0 * _n_coast.get_noise_1d(a * 2.3)
		_palm_r[d] = r


## Signed coast distance (union of the palm, the fingers, the thumb and the islets, minus the inlet) and the
## cliffness of each stretch of coast.
func _coast() -> void:
	var inlet_pts := [Vector2(-200, -13), Vector2(-108, -13), Vector2(-92, -12)]
	var inlet_r := [13.0, 12.0, 6.0]
	var fa := PackedVector2Array()
	var fb := PackedVector2Array()
	var fra := PackedFloat32Array()
	var frb := PackedFloat32Array()
	for fg in L.FINGERS:
		fa.append(fg[0])
		fb.append(fg[1])
		fra.append(fg[2])
		frb.append(fg[3])
	var ta: Vector2 = L.THUMB[0]
	var tb: Vector2 = L.THUMB[1]
	var tra: float = L.THUMB[2]
	var trb: float = L.THUMB[3]
	var isl_c := PackedVector2Array()
	var isl_r := PackedVector2Array()
	for isl in L.ISLETS:
		isl_c.append(isl[0])
		isl_r.append(isl[1])
	for iz in N:
		var z := gx(iz)
		for ix in N:
			var x := gx(ix)
			var i := iz * N + ix
			var r := sqrt(x * x + z * z)
			var a := fposmod(rad_to_deg(atan2(x, z)), 360.0)
			var ai := int(a)
			var f := lerpf(_palm_r[ai], _palm_r[ai + 1], a - float(ai)) - r
			if r > 80.0:
				if z < -70.0:
					for k in fa.size():
						f = smax(f, capsule_in(x, z, fa[k], fb[k], fra[k], frb[k]), 12.0)
				if x < -55.0 and z < 0.0:
					f = smax(f, capsule_in(x, z, ta, tb, tra, trb), 12.0)
			# The inlet: a polyline capsule cut between the thumb and the palm (its shore is a coast too, so the
			# cut reaches as far inland as the coast profiles do).
			if z > -64.0 and z < 38.0 and x < -40.0:
				var cut := maxf(capsule_in(x, z, inlet_pts[0], inlet_pts[1], inlet_r[0], inlet_r[1]), capsule_in(x, z, inlet_pts[1], inlet_pts[2], inlet_r[1], inlet_r[2]))
				f = smin(f, -cut, 4.0)
			if r > 120.0:
				for k in isl_c.size():
					var c := isl_c[k]
					var rr := isl_r[k]
					var dx := (x - c.x) / rr.x
					var dz := (z - c.y) / rr.y
					if absf(dx) < 2.5 and absf(dz) < 2.5:
						f = maxf(f, (1.0 - sqrt(dx * dx + dz * dz)) * minf(rr.x, rr.y))
			f += _n_coast.get_noise_2d(x, z) * 2.2
			sd[i] = f
			if f < -18.0:
				cliff[i] = 0.5
				continue
			# Cliffness: sea cliffs in the north, on the thumb, on the west plateau and in the inlet; the village
			# bay is a beach; the east coast and the south-west are low and rocky with coves.
			var c2 := 0.4
			c2 = lerpf(c2, 1.0, smoothstep(-48.0, -75.0, z))
			c2 = lerpf(c2, 1.0, smoothstep(-86.0, -104.0, x) * smoothstep(48.0, 30.0, z))
			c2 = lerpf(c2, 0.0, smoothstep(56.0, 80.0, z) * smoothstep(78.0, 58.0, absf(x - 4.0)))
			c2 = lerpf(c2, 0.05, smoothstep(14.0, 4.0, Vector2(x + 70.0, z - 104.0).length() - 10.0))
			c2 = lerpf(c2, 0.55, smoothstep(98.0, 118.0, x) * smoothstep(-50.0, -30.0, z))
			# The inlet head: a pebble beach that leads into the ravine.
			c2 = lerpf(c2, 0.1, smoothstep(-100.0, -94.0, x) * smoothstep(-32.0, -22.0, z) * smoothstep(8.0, -2.0, z))
			if r > 140.0:
				c2 = maxf(c2, 0.75)
			cliff[i] = c2


## Even-odd scanline fill of a polygon on the grid (cell centres): 1 inside, 0 outside.
func _poly_mask(poly: PackedVector2Array) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(N * N)
	m.fill(0.0)
	var n := poly.size()
	for iz in N:
		var z := gx(iz)
		var xs := PackedFloat32Array()
		for k in n:
			var a := poly[k]
			var b := poly[(k + 1) % n]
			if (a.y <= z and b.y > z) or (b.y <= z and a.y > z):
				xs.append(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			var ix0 := maxi(0, int(ceil((xs[j] + EXT) / CELL)))
			var ix1 := mini(N - 1, int(floor((xs[j + 1] + EXT) / CELL)))
			for ix in range(ix0, ix1 + 1):
				m[iz * N + ix] = 1.0
			j += 2
	return m


## Upper-level weight: inside the polygon closed by the escarpment, smoothed into a 2.8 m cliff along the line.
func _upper_mask() -> void:
	var esc := PackedVector2Array(L.ESCARPMENT)
	var poly := PackedVector2Array([Vector2(-260, -14), Vector2(-100, -14)])
	poly.append_array(esc)
	poly.append(Vector2(esc[esc.size() - 1].x, -260))
	poly.append(Vector2(-260, -260))
	var m := _poly_mask(poly)
	# Soft edge along the escarpment: exact signed distance near the line.
	for k in esc.size() - 1:
		var a := esc[k]
		var b := esc[k + 1]
		var x0 := maxi(0, int(floor(minf(a.x, b.x) - 3.0 + EXT)))
		var x1 := mini(N - 1, int(ceil(maxf(a.x, b.x) + 3.0 + EXT)))
		var z0 := maxi(0, int(floor(minf(a.y, b.y) - 3.0 + EXT)))
		var z1 := mini(N - 1, int(ceil(maxf(a.y, b.y) + 3.0 + EXT)))
		for iz in range(z0, z1 + 1):
			var z := gx(iz)
			for ix in range(x0, x1 + 1):
				var x := gx(ix)
				var pd := polyline_d(x, z, L.ESCARPMENT)
				if float(pd[0]) > 2.6:
					continue
				m[iz * N + ix] = smoothstep(-1.4, 1.4, -float(pd[0]) * float(pd[3]))
	upw = m


## Elevation target of the land (before the coast profile): forest, village slope, escarpment and upper level,
## west plateau, east hill, ridge massif and spurs, thumb headland, islets.
func _elevation() -> void:
	_upper_mask()
	var fa := PackedVector2Array()
	var fb := PackedVector2Array()
	var fra := PackedFloat32Array()
	var frb := PackedFloat32Array()
	for fg in L.FINGERS:
		fa.append(fg[0])
		fb.append(fg[1])
		fra.append(fg[2])
		frb.append(fg[3])
	var isl_c := PackedVector2Array()
	var isl_r := PackedVector2Array()
	var isl_h := PackedFloat32Array()
	for isl in L.ISLETS:
		isl_c.append(isl[0])
		isl_r.append(isl[1])
		isl_h.append(isl[2])
	for iz in N:
		var z := gx(iz)
		for ix in N:
			var i := iz * N + ix
			var s := sd[i]
			if s < -16.0:
				h[i] = DEEP
				continue
			var x := gx(ix)
			var roll := _n_roll.get_noise_2d(x, z)
			var fine := _n_fine.get_noise_2d(x, z)
			# Palm interior: the forest's rolling ground, sloping down to the village and the bay.
			var e := L.FOREST_H + roll * 3.2 + fine * 0.35
			# The village slope: a gentle 10-degree rise from the beach to the north fence (the plaza and the
			# house pads sit on it without cliffs between them).
			var vs := 2.8 + 7.4 * smoothstep(102.0, 44.0, z) + roll * 1.4 * smoothstep(84.0, 50.0, z)
			e = lerpf(e, vs, smoothstep(32.0, 56.0, z))
			var fw := (1.0 - smoothstep(36.0, 56.0, z)) * smoothstep(-96.0, -70.0, x) * smoothstep(64.0, 44.0, x)
			# The west plateau (south of the inlet), with a ramp down to the forest.
			var ww := smoothstep(-56.0, -92.0, x) * smoothstep(62.0, 38.0, z)
			e = lerpf(e, L.WEST_H + roll * 1.2, ww)
			fw *= 1.0 - ww
			# Upper level: north-west of the escarpment.
			var u := upw[i]
			if u > 0.0:
				var up := L.UPPER_H + roll * 1.6 + fine * 0.3
				e = lerpf(e, up, u)
				fw *= 1.0 - u
			# East hill: a dome (the olive benches are cut into it later).
			var dh := Vector2(x - L.EAST_HILL.x, z - L.EAST_HILL.y).length()
			if dh < L.EAST_HILL_R:
				var k := 1.0 - (dh / L.EAST_HILL_R) * (dh / L.EAST_HILL_R)
				var hill := 8.0 + (L.EAST_HILL_H - 8.0) * pow(k, 1.25) + roll * 1.0
				if hill > e:
					fw *= 1.0 - smoothstep(13.0, 17.0, hill)
					e = hill
			# Ridge massif: a mesa with cliff sides; the peak a little west of the cave.
			var md := 99.0
			if z < -80.0 and absf(x) < 80.0:
				md = roundrect_sd(x, z, L.MASSIF_C, L.MASSIF_HALF, L.MASSIF_CORNER)
			if md < 12.0:
				var mw := smoothstep(7.5, -1.0, md + _n_rock.get_noise_2d(x * 0.6, z * 0.6) * 2.5)
				var pk := Vector2(x - L.MASSIF_PEAK.x, z - L.MASSIF_PEAK.y).length()
				var top := L.MASSIF_H + 7.0 * exp(-pk * pk / 380.0) + roll * 2.0 + _n_rock.get_noise_2d(x, z) * 1.5
				e = maxf(e, lerpf(e, top, mw))
			# Spurs running north to the sea (the fingers).
			if z < -78.0:
				for k in fa.size():
					var a := fa[k]
					var b := fb[k]
					var abx := b.x - a.x
					var abz := b.y - a.y
					var t := clampf(((x - a.x) * abx + (z - a.y) * abz) / (abx * abx + abz * abz), 0.0, 1.0)
					var dx := x - a.x - abx * t
					var dz := z - a.y - abz * t
					var dd := sqrt(dx * dx + dz * dz)
					var rad := lerpf(fra[k], frb[k], t) * 1.1
					if dd < rad:
						var crest := lerpf(37.0, 17.0, pow(t, 0.85)) + _n_rock.get_noise_2d(x, z) * 1.5
						e = maxf(e, lerpf(L.UPPER_H, crest, smoothstep(rad, rad * 0.2, dd)))
			# The thumb's headland (altar viewpoint) rises a little towards the tip.
			var th := Vector2(x + 146.0, z + 60.0).length()
			if th < 30.0:
				e += 4.5 * smoothstep(30.0, 6.0, th) * u
			# Islets: rocky domes.
			if sqrt(x * x + z * z) > 120.0:
				for k in isl_c.size():
					var c := isl_c[k]
					var rr := isl_r[k]
					var ex := (x - c.x) / rr.x
					var ez := (z - c.y) / rr.y
					var q := ex * ex + ez * ez
					if q < 1.3:
						e = maxf(e, isl_h[k] * pow(maxf(0.0, 1.0 - q), 0.55) + fine * 0.4)
			forest_w[i] = clampf(fw, 0.0, 1.0)
			# Dryness: the thumb, the west plateau, the hill tops and the spurs are golden; the meadow below the
			# massif stays green (sheltered), the forest is shaded.
			var dr := 0.25
			dr = lerpf(dr, 0.85, ww)
			dr = lerpf(dr, 0.85, smoothstep(-80.0, -100.0, x) * u)
			dr = lerpf(dr, 0.75, smoothstep(-120.0, -140.0, z))
			dr = lerpf(dr, 0.25, smoothstep(-48.0, -36.0, x) * smoothstep(-100.0, -92.0, z) * smoothstep(-55.0, -66.0, z) * u)
			dr = lerpf(dr, 0.6, smoothstep(14.0, 24.0, e) * smoothstep(40.0, 80.0, x))
			dr = clampf(dr + _n_patch.get_noise_2d(x * 0.6, z * 0.6) * 0.25, 0.0, 1.0)
			dry[i] = dr * (1.0 - fw * 0.8)
			# Coast profile: beaches rise gently, cliffs keep their full height to the edge. The upper level always
			# meets the sea in a cliff (integration fix: a beach profile on the inlet head's north shore pulled the
			# upper level down into a walkable ramp, so the broken passage could be walked round).
			var c2 := maxf(cliff[i], u)
			var hh: float
			if s >= 0.0:
				var hb := lerpf(0.42 + 0.075 * s, e, smoothstep(9.0, 42.0, s))
				var hc := e * smoothstep(0.0, 2.8, s) + 0.3 * (1.0 - smoothstep(0.0, 2.8, s))
				hh = lerpf(hb, hc, c2)
			else:
				hh = maxf(DEEP, -0.3 + s * lerpf(0.095, 0.9, c2))
			h[i] = hh


## The ravine at the inlet head: a gully from the pebble beach up to the forest floor, so whoever falls into the
## inlet can walk back.
func _ravine() -> void:
	var a := Vector2(-97, -12.5)
	var b := Vector2(-60, -17)
	for iz in range(int(-40.0 + EXT), int(6.0 + EXT)):
		var z := gx(iz)
		for ix in range(int(-106.0 + EXT), int(-50.0 + EXT)):
			var x := gx(ix)
			var i := iz * N + ix
			var abx := b.x - a.x
			var abz := b.y - a.y
			var t := clampf(((x - a.x) * abx + (z - a.y) * abz) / (abx * abx + abz * abz), 0.0, 1.0)
			var d := Vector2(x - a.x - abx * t, z - a.y - abz * t).length()
			if d > 14.0:
				continue
			var floor_y := lerpf(0.55, 12.5, smoothstep(0.0, 1.0, t))
			var w := 1.0 - smoothstep(3.5, 13.0, d)
			if upw[i] > 0.5:
				w *= 1.0 - smoothstep(0.5, 1.0, upw[i]) * smoothstep(5.0, 9.0, d)
			h[i] = lerpf(h[i], minf(h[i], floor_y + maxf(0.0, d - 3.5) * 0.35), w)
			forest_w[i] *= 1.0 - w * 0.7


## The cave: a flat-floored crater under the massif (walls rising straight to the mesa) and two tunnels to the
## mouths; the lid and the tunnel roofs are separate meshes (NemeaCave).
func _cave_carve() -> void:
	var c := L.CAVE_C
	var fl := L.CAVE_FLOOR
	var x0 := int(-50.0 + EXT)
	var x1 := int(56.0 + EXT)
	var z0 := int(-136.0 + EXT)
	var z1 := int(-80.0 + EXT)
	for iz in range(z0, z1):
		var z := gx(iz)
		for ix in range(x0, x1):
			var x := gx(ix)
			var i := iz * N + ix
			# Distance to the floor footprint: the arena disc and the two tunnels (capsules to just past the mouths).
			var dc := Vector2(x - c.x, z - c.y).length() - L.CAVE_R
			var ta := -capsule_in(x, z, c, L.MOUTH_A + (L.MOUTH_A - c).normalized() * 3.0, L.TUNNEL_HW, L.TUNNEL_HW)
			var tb := -capsule_in(x, z, c, L.MOUTH_B + (L.MOUTH_B - c).normalized() * 3.0, L.TUNNEL_B_HW, L.TUNNEL_B_HW)
			var d := minf(dc, minf(ta, tb))
			if d > L.CAVE_WALL + 4.0:
				continue
			var wall := L.CAVE_WALL + _n_rock.get_noise_2d(x * 1.7, z * 1.7) * 0.6
			var k := smoothstep(0.0, wall, d)
			# The walls go up to whatever is above (the mesa); round the arena never lower than the lid needs.
			var top := h[i]
			if dc < 6.0 and h[i] > 28.0:
				top = maxf(h[i], fl + L.LID_TOP + 5.0)
			h[i] = lerpf(fl, top, k * k * (3.0 - 2.0 * k))
			# Under the lid (arena) or the tunnel roofs: dark, walls included.
			var inside := 1.0 - smoothstep(L.CAVE_WALL + 0.5, L.CAVE_WALL + 2.5, d)
			# The mouths open to the meadow: no cave darkness in the last metres of each tunnel.
			var ma := Vector2(x - L.MOUTH_A.x, z - L.MOUTH_A.y).length()
			var mb := Vector2(x - L.MOUTH_B.x, z - L.MOUTH_B.y).length()
			inside *= smoothstep(2.0, 7.0, minf(ma, mb))
			cave_w[i] = maxf(cave_w[i], inside)
	# Aprons: the meadow levels out in front of each mouth.
	for m: Vector2 in [L.MOUTH_A, L.MOUTH_B]:
		var out := (m - c).normalized()
		_flatten(m + out * 7.0, 7.5, 5.0, fl + 0.35)


## Olive benches on the east hill's south and west slopes: steps 1.4 m high, flat treads.
const BENCH_STEP := 1.4


func _terraces() -> void:
	const STEP := BENCH_STEP
	var c := L.EAST_HILL
	for iz in range(int(-40.0 + EXT), int(66.0 + EXT)):
		var z := gx(iz)
		for ix in range(int(36.0 + EXT), int(120.0 + EXT)):
			var x := gx(ix)
			var i := iz * N + ix
			var d := Vector2(x - c.x, z - c.y).length()
			if d > L.EAST_HILL_R - 6.0 or d < 9.0:
				continue
			# Sector: from the south-east round to the north-west (facing the village and the forest).
			var ang := angle_of(x - c.x, z - c.y)
			var sect := smoothstep(0.3, 0.42, g_ang(ang, 300.0, 70.0))
			var w := sect * smoothstep(9.0, 12.0, d) * smoothstep(L.EAST_HILL_R - 6.0, L.EAST_HILL_R - 10.0, d)
			if w < 0.02 or h[i] < 9.0:
				continue
			bench_h0[i] = h[i]
			var q := (h[i] - 8.0) / STEP
			var fq := floorf(q)
			var stepped := 8.0 + STEP * (fq + smoothstep(0.8, 1.0, q - fq))
			h[i] = lerpf(h[i], stepped, w)
			bench[i] = w


## Flattened pads: the houses, the altars, the goat pen, the passage rims, then the plaza (short fade), then
## the houses' floors again (the plaza's fade must not tilt a house next to it).
func _pads() -> void:
	var house_pads: Array = []
	for hs in L.HOUSES:
		var p: Vector2 = hs[0]
		var sc: float = hs[3]
		var r := (4.2 if int(hs[2]) == 1 else 3.4) * sc
		var y := _mean_h(p, r)
		house_pads.append([p, r, y])
		_flatten(p, r, 4.0, y)
	for al in L.ALTARS:
		_flatten(al[0], 5.0, 5.0, NAN)
	_flatten(L.GOAT_PEN, 6.0, 4.0, NAN)
	_flatten(L.PASS_SOUTH + Vector2(0, 1.5), 3.5, 1.5, NAN)
	_flatten(L.PASS_NORTH + Vector2(0, -1.5), 3.5, 1.5, NAN)
	_flatten(L.PLAZA, L.PLAZA_R + 1.0, 8.0, NAN)
	for hp in house_pads:
		_flatten(hp[0], hp[1], 1.2, hp[2])


## Mean ground height within r of p, over solid land only (cells at least 3 m inland): a pad on a cliff rim
## keeps the rim's height instead of sinking towards the sea.
func _mean_h(p: Vector2, r: float) -> float:
	var acc := 0.0
	var n := 0
	var all_acc := 0.0
	var all_n := 0
	for iz in range(maxi(1, int(floor(p.y - r + EXT))), mini(N - 2, int(ceil(p.y + r + EXT))) + 1):
		for ix in range(maxi(1, int(floor(p.x - r + EXT))), mini(N - 2, int(ceil(p.x + r + EXT))) + 1):
			if Vector2(gx(ix) - p.x, gx(iz) - p.y).length() <= r:
				var i := iz * N + ix
				all_acc += h[i]
				all_n += 1
				if sd[i] > 3.0:
					acc += h[i]
					n += 1
	if n == 0:
		return all_acc / maxf(1.0, all_n)
	return acc / n


## Blends the ground towards height `y` (NAN: the mean height inside `r`) within r, fading over `fade` metres.
func _flatten(p: Vector2, r: float, fade: float, y: float) -> void:
	var x0 := maxi(1, int(floor(p.x - r - fade + EXT)))
	var x1 := mini(N - 2, int(ceil(p.x + r + fade + EXT)))
	var z0 := maxi(1, int(floor(p.y - r - fade + EXT)))
	var z1 := mini(N - 2, int(ceil(p.y + r + fade + EXT)))
	if is_nan(y):
		y = _mean_h(p, r)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(gx(ix) - p.x, gx(iz) - p.y).length()
			var w := 1.0 - smoothstep(r, r + fade, d)
			if w <= 0.0:
				continue
			var i := iz * N + ix
			h[i] = lerpf(h[i], y, w)
			pad_w[i] = maxf(pad_w[i], 1.0 - smoothstep(r - 0.5, r + 1.0, d))


## Paths: sample the ground along each centreline, smooth the profile (walkable grade), then level the road
## across its width and blend into the verges. path_w marks the packed earth for colour, grass and the ground map.
func _paths() -> void:
	paths.clear()
	for pd in L.PATHS:
		var src: Array = pd[0]
		var hw: float = pd[1]
		# Resample every 1 m.
		var pts := PackedVector2Array()
		for k in src.size() - 1:
			var a: Vector2 = src[k]
			var b: Vector2 = src[k + 1]
			var n := maxi(1, int(ceil(a.distance_to(b))))
			for j in n:
				pts.append(a.lerp(b, float(j) / float(n)))
		pts.append(src[src.size() - 1])
		var ys := PackedFloat32Array()
		ys.resize(pts.size())
		var fixed := PackedByteArray()
		fixed.resize(pts.size())
		for k in pts.size():
			ys[k] = height_at(pts[k].x, pts[k].y)
			# On a pad (plaza, house fronts, altars) the road keeps the pad's level.
			fixed[k] = 1 if field(pad_w, pts[k].x, pts[k].y) > 0.6 else 0
		# Smooth the profile (moving average, a few passes), keeping the ends and the pads.
		for pass_i in 4:
			var tmp := ys.duplicate()
			for k in range(1, pts.size() - 1):
				if fixed[k] == 1:
					continue
				var acc := 0.0
				var cnt := 0
				for j in range(maxi(0, k - 4), mini(pts.size(), k + 5)):
					acc += tmp[j]
					cnt += 1
				ys[k] = acc / cnt
		paths.append({"pts": pts, "hw": hw, "ys": ys})
	# Carve: every cell near a path takes the profile height of its nearest centreline point (all paths at
	# once: segments are stamped into a nearest-distance buffer).
	var best_d := PackedFloat32Array()
	best_d.resize(N * N)
	best_d.fill(INF)
	var best_y := PackedFloat32Array()
	best_y.resize(N * N)
	var best_hw := PackedFloat32Array()
	best_hw.resize(N * N)
	var touched := PackedInt32Array()
	for p in paths:
		var pts: PackedVector2Array = p["pts"]
		var ys: PackedFloat32Array = p["ys"]
		var hw: float = p["hw"]
		var reach := hw + 3.5
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var abx := b.x - a.x
			var abz := b.y - a.y
			var l2 := maxf(abx * abx + abz * abz, 1e-6)
			var x0 := maxi(1, int(floor(minf(a.x, b.x) - reach + EXT)))
			var x1 := mini(N - 2, int(ceil(maxf(a.x, b.x) + reach + EXT)))
			var z0 := maxi(1, int(floor(minf(a.y, b.y) - reach + EXT)))
			var z1 := mini(N - 2, int(ceil(maxf(a.y, b.y) + reach + EXT)))
			for iz in range(z0, z1 + 1):
				var z := gx(iz)
				for ix in range(x0, x1 + 1):
					var x := gx(ix)
					var t := clampf(((x - a.x) * abx + (z - a.y) * abz) / l2, 0.0, 1.0)
					var dx := x - a.x - abx * t
					var dz := z - a.y - abz * t
					var d := sqrt(dx * dx + dz * dz)
					if d > reach:
						continue
					var i := iz * N + ix
					if d < best_d[i]:
						if best_d[i] == INF:
							touched.append(i)
						best_d[i] = d
						best_y[i] = lerpf(ys[k], ys[k + 1], t)
						best_hw[i] = hw
	for i in touched:
		var d := best_d[i]
		var hw := best_hw[i]
		var w := (1.0 - smoothstep(hw + 0.4, hw + 3.5, d)) * (1.0 - pad_w[i])
		h[i] = lerpf(h[i], best_y[i], w)
		path_w[i] = maxf(path_w[i], 1.0 - smoothstep(hw, hw + 1.0, d))
		path_d[i] = minf(path_d[i], maxf(0.0, d - hw))


func _normals() -> void:
	nrm.resize(N * N)
	for iz in N:
		for ix in N:
			var i := iz * N + ix
			var l := h[i - 1] if ix > 0 else h[i]
			var r := h[i + 1] if ix < N - 1 else h[i]
			var u := h[i - N] if iz > 0 else h[i]
			var d := h[i + N] if iz < N - 1 else h[i]
			nrm[i] = Vector3(l - r, 2.0 * CELL, u - d).normalized()


## Ground colour per vertex (rgb) and grassiness (a): sand on the beaches, wet sand at the water, meadow green,
## shaded forest floor, golden garrigue where it is dry, layered rock on steep ground, the cave's stone.
func _colours() -> void:
	col.resize(N * N)
	for iz in N:
		var z := gx(iz)
		for ix in N:
			var x := gx(ix)
			var i := iz * N + ix
			var y := h[i]
			var s := sd[i]
			var ny := nrm[i].y
			var c: Color
			var g := 0.0
			if y < 0.25 or s < 0.0:
				c = C_SAND_WET if cliff[i] < 0.6 else C_ROCK_SEA
				if y < -1.5:
					c = c.darkened(0.15)
			else:
				var pv := _n_patch.get_noise_2d(x, z)
				# Meadow base with soft painted variation.
				c = C_MEADOW.lerp(C_MEADOW_LIGHT, smoothstep(0.05, 0.45, pv)).lerp(C_MEADOW_DARK, smoothstep(-0.1, -0.45, pv))
				c = c.lerp(C_FOREST.lerp(C_FOREST_DARK, smoothstep(0.0, -0.4, pv)), forest_w[i] * 0.85)
				var dr := dry[i]
				var golden := C_STRAW.lerp(C_GARRIGUE, smoothstep(-0.2, 0.3, pv)).lerp(C_STRAW_DEEP, smoothstep(0.35, 0.6, pv))
				c = c.lerp(golden, smoothstep(0.35, 0.8, dr))
				g = 1.0
				# Village: trodden, a lighter green.
				var vil := smoothstep(52.0, 40.0, Vector2(x - L.PLAZA.x, (z - L.PLAZA.y) * 1.25).length())
				c = c.lerp(C_VILLAGE, vil * 0.5)
				# High ground (the massif, the spur crests): rocky golden garrigue.
				var hi := smoothstep(27.0, 36.0, y)
				if hi > 0.0:
					c = c.lerp(C_GARRIGUE.lerp(C_ROCK_WARM, smoothstep(0.0, 0.5, pv)), hi * 0.85)
					g *= 1.0 - hi * 0.5
				# Olive benches: warm earth between the grass.
				if bench[i] > 0.2:
					c = c.lerp(C_SOIL.lerp(C_STRAW, 0.4), bench[i] * 0.35)
				# Beach sand and dunes.
				var bw := (1.0 - cliff[i]) * (1.0 - smoothstep(9.0, 17.0, s)) * (1.0 - smoothstep(2.6, 3.6, y))
				if bw > 0.0:
					c = c.lerp(C_SAND.lerp(C_SAND_DUNE, smoothstep(6.0, 14.0, s)), bw)
					g *= 1.0 - smoothstep(0.35, 0.8, bw)
				if y < 0.7 and cliff[i] < 0.6:
					c = c.lerp(C_SAND_WET, smoothstep(0.7, 0.3, y))
			# Rock on steep ground: warm limestone, darker low down and near the sea.
			var steep := smoothstep(0.80, 0.70, ny)
			if steep > 0.0:
				var rv := _n_rock.get_noise_2d(x, z)
				var rc := C_ROCK.lerp(C_ROCK_WARM, smoothstep(-0.1, 0.4, rv)).lerp(C_ROCK_DARK, smoothstep(6.0, 0.5, y) * 0.6)
				c = c.lerp(rc, steep)
				g *= 1.0 - steep
			# The cave: pale readable floor, dark walls.
			var cw := cave_w[i]
			if cw > 0.0:
				var floor_k := smoothstep(0.75, 0.9, ny)
				var cc := C_CAVE_WALL.lerp(C_CAVE_FLOOR, floor_k)
				c = c.lerp(cc, cw)
				g *= 1.0 - cw
			# Paths are painted from the ground map; under them the grass thins.
			g *= 1.0 - smoothstep(0.4, 0.9, path_w[i])
			g *= 1.0 - pad_w[i] * 0.6
			col[i] = Color(c.r, c.g, c.b, clampf(g, 0.0, 1.0))


# --- meshes and collision ------------------------------------------------------------------------------------

## Builds the chunk meshes (+ trimesh collision on layer 1) under `parent`.
func build_meshes(parent: Node3D, material: Material) -> void:
	var t0 := Time.get_ticks_usec()
	var cells := N - 1
	var nch := int(ceil(float(cells) / CHUNK))
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var tris := 0
	for cz in nch:
		for cx in nch:
			var ix0 := cx * CHUNK
			var iz0 := cz * CHUNK
			var ix1 := mini(ix0 + CHUNK, cells)
			var iz1 := mini(iz0 + CHUNK, cells)
			# Skip chunks that are all deep sea.
			var any := false
			for iz in range(iz0, iz1 + 1, 2):
				for ix in range(ix0, ix1 + 1, 2):
					if h[iz * N + ix] > -4.5:
						any = true
						break
				if any:
					break
			if not any:
				continue
			var w := ix1 - ix0 + 1
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			verts.resize(w * (iz1 - iz0 + 1))
			norms.resize(verts.size())
			cols.resize(verts.size())
			var k := 0
			for iz in range(iz0, iz1 + 1):
				for ix in range(ix0, ix1 + 1):
					var i := iz * N + ix
					verts[k] = Vector3(gx(ix), h[i], gx(iz))
					norms[k] = nrm[i]
					cols[k] = col[i]
					k += 1
			var ind := PackedInt32Array()
			ind.resize((ix1 - ix0) * (iz1 - iz0) * 6)
			var n := 0
			for iz in range(iz0, iz1):
				for ix in range(ix0, ix1):
					var i := iz * N + ix
					if h[i] < -5.0 and h[i + 1] < -5.0 and h[i + N] < -5.0 and h[i + N + 1] < -5.0:
						continue
					var a := (iz - iz0) * w + (ix - ix0)
					var b := a + 1
					var c := a + w + 1
					var d := a + w
					if (ix + iz) & 1 == 0:
						ind[n] = a
						ind[n + 1] = b
						ind[n + 2] = c
						ind[n + 3] = a
						ind[n + 4] = c
						ind[n + 5] = d
					else:
						ind[n] = a
						ind[n + 1] = b
						ind[n + 2] = d
						ind[n + 3] = b
						ind[n + 4] = c
						ind[n + 5] = d
					n += 6
			if n == 0:
				continue
			ind.resize(n)
			tris += n / 3
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = ind
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Terrain_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.material_override = material
			mi.visibility_range_end = LOD_RANGE
			mi.visibility_range_end_margin = 10.0
			parent.add_child(mi)
			chunks.append(mi)
			# The same chunk at 2 m (a quarter of the triangles, no shadows) for when it is far away.
			var far := MeshInstance3D.new()
			far.name = "TerrainFar_%d_%d" % [cx, cz]
			far.mesh = _lod_mesh(ix0, iz0, ix1, iz1)
			far.material_override = material
			far.visibility_range_begin = LOD_RANGE
			far.visibility_range_begin_margin = 10.0
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(far)
			chunks.append(far)
			var cs := CollisionShape3D.new()
			cs.name = "Ground_%d_%d" % [cx, cz]
			cs.shape = mesh.create_trimesh_shape()
			body.add_child(cs)
	timings["mesh"] = (Time.get_ticks_usec() - t0) / 1000
	timings["terrain_tris"] = tris


## A chunk's mesh at 2 m (every other grid vertex; the 1 m mesh keeps the exact heights and the collision).
func _lod_mesh(ix0: int, iz0: int, ix1: int, iz1: int) -> ArrayMesh:
	var w := (ix1 - ix0) / 2 + 1
	var hgt := (iz1 - iz0) / 2 + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(w * hgt)
	norms.resize(w * hgt)
	cols.resize(w * hgt)
	var k := 0
	for jz in hgt:
		for jx in w:
			var ix := mini(ix0 + jx * 2, ix1)
			var iz := mini(iz0 + jz * 2, iz1)
			var i := iz * N + ix
			verts[k] = Vector3(gx(ix), h[i], gx(iz))
			norms[k] = nrm[i]
			cols[k] = col[i]
			k += 1
	var ind := PackedInt32Array()
	for jz in hgt - 1:
		for jx in w - 1:
			var i := (iz0 + jz * 2) * N + ix0 + jx * 2
			if h[i] < -5.0 and h[mini(i + 2, h.size() - 1)] < -5.0 and h[mini(i + 2 * N, h.size() - 1)] < -5.0:
				continue
			var a := jz * w + jx
			ind.append_array([a, a + 1, a + w + 1, a, a + w + 1, a + w])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = ind
	var mesh := ArrayMesh.new()
	if not ind.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- textures ------------------------------------------------------------------------------------------------

func init_ground_map() -> void:
	gm.resize(GM_N * GM_N * 4)
	gm.fill(0)
	var tpm := GM_N / (2.0 * GM_EXT)
	# Paths (B) with a worn verge (G); cave darkness (R).
	for p in paths:
		var pts: PackedVector2Array = p["pts"]
		var hw: float = p["hw"]
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			_splat(2, a, b, hw + 0.25, 1.0, 0.82)
			_splat(1, a, b, hw + 1.3, 0.45, 0.4)
	# Cave darkness: rasterise cave_w (1 m cells) into R.
	var x0 := int((-50.0 + GM_EXT) * tpm)
	var x1 := int((56.0 + GM_EXT) * tpm)
	var z0 := int((-136.0 + GM_EXT) * tpm)
	var z1 := int((-80.0 + GM_EXT) * tpm)
	for tz in range(z0, z1):
		var pz := (tz + 0.5) / tpm - GM_EXT
		for tx in range(x0, x1):
			var px := (tx + 0.5) / tpm - GM_EXT
			var cw := field(cave_w, px, pz)
			if cw <= 0.0:
				continue
			var o := (tz * GM_N + tx) * 4
			gm[o] = maxi(gm[o], int(cw * 200.0))
			gm[o + 3] = 255


## Soft capsule splat into a ground-map channel: value `s` (0..1) inside radius R, fading from R * inner to R.
func _splat(ch: int, a: Vector2, b: Vector2, R: float, s: float, inner: float = 0.55) -> void:
	var tpm := GM_N / (2.0 * GM_EXT)
	var tx0 := maxi(0, int(floor((minf(a.x, b.x) - R + GM_EXT) * tpm)))
	var tx1 := mini(GM_N - 1, int(ceil((maxf(a.x, b.x) + R + GM_EXT) * tpm)))
	var tz0 := maxi(0, int(floor((minf(a.y, b.y) - R + GM_EXT) * tpm)))
	var tz1 := mini(GM_N - 1, int(ceil((maxf(a.y, b.y) + R + GM_EXT) * tpm)))
	var abx := b.x - a.x
	var abz := b.y - a.y
	var l2 := maxf(abx * abx + abz * abz, 1e-6)
	var inv := 1.0 / tpm
	for tz in range(tz0, tz1 + 1):
		var pz := (tz + 0.5) * inv - GM_EXT
		for tx in range(tx0, tx1 + 1):
			var px := (tx + 0.5) * inv - GM_EXT
			var t := clampf(((px - a.x) * abx + (pz - a.y) * abz) / l2, 0.0, 1.0)
			var dx := px - a.x - abx * t
			var dz := pz - a.y - abz * t
			var d := sqrt(dx * dx + dz * dz)
			if d >= R:
				continue
			var bv := int(s * (1.0 - smoothstep(inner, 1.0, d / R)) * 255.0)
			var o := (tz * GM_N + tx) * 4 + ch
			if bv > gm[o]:
				gm[o] = mini(bv, 255)


## Contact AO under an object (disc, or capsule a -> b).
func splat_ao(a: Vector2, R: float, s: float, b: Variant = null) -> void:
	_splat(0, a, a if b == null else b, R, s)


func splat_soil(a: Vector2, R: float, s: float, b: Variant = null) -> void:
	_splat(1, a, a if b == null else b, R, s)


## No grass within R (a hard disc with a thin soft rim).
func splat_nograss(a: Vector2, R: float, b: Variant = null) -> void:
	_splat(3, a, a if b == null else b, R, 1.0, 0.85)


func commit_textures() -> void:
	var img := Image.create_from_data(GM_N, GM_N, false, Image.FORMAT_RGBA8, gm)
	img.generate_mipmaps()
	ground_tex = ImageTexture.create_from_image(img)
	# Ground colour (a = grassiness) and heights for the grass shader.
	var cb := PackedByteArray()
	cb.resize(N * N * 4)
	for i in N * N:
		var c := col[i]
		cb[i * 4] = int(c.r * 255.0)
		cb[i * 4 + 1] = int(c.g * 255.0)
		cb[i * 4 + 2] = int(c.b * 255.0)
		cb[i * 4 + 3] = int(c.a * 255.0)
	var ci := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, cb)
	color_tex = ImageTexture.create_from_image(ci)
	var hi := Image.create_from_data(N, N, false, Image.FORMAT_RF, h.to_byte_array())
	height_tex = ImageTexture.create_from_image(hi)
	# Painted meadow patches (native noise, mipmapped).
	var dn := FastNoiseLite.new()
	dn.seed = 917
	dn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dn.frequency = 0.07
	dn.fractal_type = FastNoiseLite.FRACTAL_FBM
	dn.fractal_octaves = 3
	dn.fractal_lacunarity = 2.3
	dn.fractal_gain = 0.45
	dn.domain_warp_enabled = true
	dn.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	dn.domain_warp_amplitude = 14.0
	dn.domain_warp_frequency = 0.03
	var di := dn.get_image(512, 512, false, false, true)
	di.generate_mipmaps()
	detail_tex = ImageTexture.create_from_image(di)


## Sea depth for the water shader: R = 0 at the shoreline .. 1 in deep water, over g_water_rect.
func build_water_texture(size: int = 512, span: float = 600.0) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	var data := PackedByteArray()
	data.resize(size * size)
	for iy in size:
		var z := -span * 0.5 + (iy + 0.5) * span / size
		for ix in size:
			var x := -span * 0.5 + (ix + 0.5) * span / size
			var hh := DEEP
			if absf(x) < EXT - 1.0 and absf(z) < EXT - 1.0:
				hh = height_at(x, z)
			data[iy * size + ix] = int(clampf(-hh / 6.0, 0.0, 1.0) * 255.0)
	img = Image.create_from_data(size, size, false, Image.FORMAT_L8, data)
	water_tex = ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("g_water_tex", water_tex)
	RenderingServer.global_shader_parameter_set("g_water_rect", Vector4(-span * 0.5, -span * 0.5, span, span))


## Debug: shaded relief + colour map as a PNG (top = north).
func save_debug_map(path: String) -> void:
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var sun := Vector3(-0.5, 0.7, -0.3).normalized()
	for iz in N:
		for ix in N:
			var i := iz * N + ix
			var c := col[i]
			if h[i] < 0.0:
				var dd := clampf(-h[i] / 8.0, 0.0, 1.0)
				c = Color(0.3, 0.8, 0.8).lerp(Color(0.1, 0.25, 0.6), dd)
			var l := clampf(nrm[i].dot(sun), 0.0, 1.0) * 0.7 + 0.45
			if path_w[i] > 0.5:
				c = Color(0.85, 0.7, 0.5)
			img.set_pixel(ix, iz, Color(c.r * l, c.g * l, c.b * l))
	img.save_png(path)
