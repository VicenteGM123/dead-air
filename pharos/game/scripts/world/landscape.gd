class_name Landscape
## Delos landscape layout (seed 7): zones, terrace blocks, landmarks, palette and grass densities. Pure data and
## pure functions, shared by Island (relief and ground colour), Props (vegetation) and Grass, so the three agree.
##
## Coordinates are world metres: X east, Z south. Angles follow Island.angle_of (0 = +Z south, 90 = +X east,
## 180 = north). The concentric order seen from the plaza out: limestone plaza, green village meadow, terraced
## fields (olive, vine, wheat, orchard), golden-grey phrygana hills, rock cliffs, sand and the sea.

# --- zones (ids of Island.zone) -------------------------------------------------------------------------------

const SEA := 0
const PLAZA := 1
const LANE := 2
const SPOT := 3
const BEACH := 4
const DUNE := 5
const GULLY := 6
const TEMENOS := 7
const CLIFF := 8
const VILLAGE := 9
const FIELDS := 10
const WILD := 11
const ZONE_NAMES := ["sea", "plaza", "lane", "spot", "beach", "dune", "gully", "temenos", "cliff", "village", "fields", "wild"]

## Debug colours for --zones=1.
const ZONE_DEBUG := [
	Color("2B5D86"), Color("E3D3B4"), Color("D2B183"), Color("FFFFFF"), Color("EED9A8"), Color("C8C896"),
	Color("3C8C5A"), Color("5A5AA0"), Color("8C7F6C"), Color("AABE6E"), Color("CDB964"), Color("8A8A5C"),
]

# --- terrace blocks ------------------------------------------------------------------------------------------

const TERRACE_STEP := 0.5
const BLOCK_NONE := -1
const T_SE := 0 # [10, 84): kepos orchard (fig, almond, pomegranate), irrigated by the spring
const T_E := 1 # [84, 140): vineyard, lowest bench wheat
const T_N := 2 # [140, 196): olive terraces
const T_NW := 3 # [196, 259): no crops, open meadow around farm 3
const T_W := 4 # [259, 305): wheat and barley strips
const T_SW := 5 # [305, 370): vines high up, olives lower down
const BLOCK_NAMES := ["T_SE", "T_E", "T_N", "T_NW", "T_W", "T_SW"]

## Bench crops.
const CROP_NONE := 0
const CROP_OLIVE := 1
const CROP_VINE := 2
const CROP_WHEAT := 3
const CROP_ORCHARD := 4


static func block_of(ang: float) -> int:
	var a := ang if ang >= 10.0 else ang + 360.0
	if a < 84.0:
		return T_SE
	if a < 140.0:
		return T_E
	if a < 196.0:
		return T_N
	if a < 259.0:
		return T_NW
	if a < 305.0:
		return T_W
	return T_SW


## Outer radius of the cultivated ring in this direction (capped 11 m inside the coast).
static func r_out(ang: float, coast: float) -> float:
	var a := ang if ang >= 10.0 else ang + 360.0
	var r := 33.0
	if a < 84.0:
		r = 36.0
	elif a >= 259.0:
		r = 40.0
	return minf(r, coast - 11.0)


## Crop of a bench at level k (bench height k * TERRACE_STEP) in a block whose benches span lowest..highest.
static func crop_of(block: int, k: int, lowest: int, highest: int = 99) -> int:
	match block:
		T_N:
			return CROP_OLIVE
		T_E:
			# The lowest full bench (the lowest cells are often only a fringe) grows wheat.
			return CROP_WHEAT if k <= lowest + 1 else CROP_VINE
		T_W:
			return CROP_WHEAT
		T_SW:
			# Vines on the upper benches, olives lower down.
			return CROP_VINE if k >= int(ceil((lowest + highest) * 0.5)) else CROP_OLIVE
		T_SE:
			return CROP_ORCHARD
	return CROP_NONE


# --- features ------------------------------------------------------------------------------------------------

## The one lush strip: a stream bed from the spring (SE) down to a pebble cove facing the islet.
const GULLY_PTS := [Vector2(23.0, 21.5), Vector2(26.5, 24.0), Vector2(30.0, 26.0), Vector2(34.0, 28.2), Vector2(37.5, 30.2), Vector2(40.5, 32.0)]
## Bed height along the gully (arc length s -> height).
const GULLY_BED := [Vector2(0.0, 2.70), Vector2(4.0, 2.45), Vector2(10.0, 2.25), Vector2(14.0, 1.85), Vector2(17.0, 1.00), Vector2(19.5, 0.15), Vector2(20.4, -0.30)]

## Sanctuary enclosure (temenos) around the ruined temple: centre, half extents, yaw (same as ruin_base).
const TEMENOS_C := Vector2(25.5, -28.5)
const TEMENOS_HALF := Vector2(8.5, 6.0)
const TEMENOS_YAW := 0.3

const SPRING := Vector2(23.2, 21.0)
const WELL := Vector2(1.6, -11.0)
const SACRED_BASIN := Vector2(28.7, -23.7)
const THRESHING := Vector2(-25.5, -25.5)
const BEEHIVES := Vector2(27.0, 32.0)
const HERM := Vector2(-6.5, 20.5)
const HORN := Vector2(-4.5, 6.0)
const ISLET := Vector2(47.0, 44.0)

## Landmark footprints [position, fp]: terraces fade out around them and grass is 0 inside fp.
const FOOTPRINTS := [
	[Vector2(2.8, -14.2), 4.5], # great plane tree
	[Vector2(1.6, -11.0), 1.6], # well
	[Vector2(3.9, -10.6), 1.0], # oleander by the well
	[Vector2(-2.7, -15.7), 0.8], # cypress N marker
	[Vector2(-7.0, 16.0), 2.0], # fig at the herm corner
	[Vector2(-8.7, 20.0), 0.8], # cypress behind the herm
	[Vector2(-6.5, 20.5), 1.2], # herm
	[Vector2(-14.0, 3.4), 1.3], # pomegranate W pocket
	[Vector2(20.3, -0.4), 0.8], # cypress E marker
	[Vector2(10.6, 18.3), 0.8], # cypress S marker
	[Vector2(23.2, 21.0), 1.5], # spring basin
	[Vector2(24.6, 19.4), 3.6], # spring plane
	[Vector2(27.0, 32.0), 1.5], # beehives
	[Vector2(-25.5, -25.5), 3.6], # threshing floor
	[Vector2(28.7, -23.7), 1.5], # sacred basin
]

## Places that keep the soil damp (greener ground, no dry patches).
const WATER_PTS := [Vector2(23.2, 21.0), Vector2(1.6, -11.0), Vector2(28.7, -23.7)]

# --- species -------------------------------------------------------------------------------------------------

## Nominal tree dimensions at scale 1: [canopy radius, height, crown base height, trunk obstacle radius].
const TREES := {
	"plane_tree": [4.2, 7.0, 2.6, 0.6],
	"olive_tree": [1.4, 3.1, 0.9, 0.4],
	"cypress": [0.75, 5.5, 0.3, 0.35],
	"fig_tree": [2.0, 3.2, 1.0, 0.4],
	"almond_tree": [1.7, 3.8, 1.4, 0.35],
	"pomegranate": [1.3, 2.5, 0.5, 0.35],
	"holm_oak": [2.3, 5.0, 1.4, 0.5],
	"aleppo_pine": [2.6, 6.5, 2.8, 0.45],
	"tamarisk": [2.0, 4.2, 1.2, 0.4],
	"laurel_tree": [1.6, 3.6, 0.4, 0.4],
	"date_palm": [2.4, 7.0, 5.5, 0.4],
	"oleander": [1.0, 2.2, 0.2, 0.35],
	"juniper": [1.2, 2.0, 0.2, 0.4],
	"giant_reed": [0.6, 2.8, 0.2, 0.0],
	"stone_pine": [2.5, 6.5, 4.0, 0.45],
}

## Shrub radius (m) at scale 1, for spacing, ground AO and grass skirts.
const SHRUBS := {
	"bush": 0.9, "cistus_shrub": 0.6, "broom_shrub": 0.7, "thyme_cushion": 0.35, "flowers_lavender": 0.45,
	"sea_lily": 0.3, "flowers_poppy": 0.45, "flowers_daisy": 0.45, "flowers_anemone": 0.4, "grass_tuft": 0.3,
}

# --- palette (sRGB) ------------------------------------------------------------------------------------------

const MEADOW := Color("9AAE62") # Pal.GRASS
const MEADOW_LIGHT := Color("B2C177") # Pal.GRASS_LIGHT
const MEADOW_DARK := Color("7F9654") # Pal.GRASS_DARK
const STRAW := Color("CDBB7C") # Pal.GRASS_DRY
const SOIL := Color("A98361") # PalExtra.SOIL
const RISER := Color("A3937F") # PalExtra.ROCK_MID
const LUSH := Color("7E9A4A")
const LUSH_DARK := Color("5E7A3A")
const STRAW_DEEP := Color("C2AA62")
const GARRIGUE := Color("A0A07A")
const GRUS := Color("B39A78")
const GRAVEL := Color("BDB3A0")
const DUNE_SAND := Color("D9CC98")
const STRAW_TIP := Color("D9C88E")

## Grass tip colour per zone.
const TIP_MEADOW := Color("B2C177")
const TIP_WILD := Color("BDB77A")
const TIP_LUSH := Color("9DB45E")
const TIP_DUNE := Color("A9B98A")
const TIP_CLIFF := Color("B8B07A")

# --- grass ---------------------------------------------------------------------------------------------------

## Clumps per m2 and instance y-scale range per zone (mesh height 0.35 m; y 1.2 = 0.42 m).
const GRASS_VILLAGE := [3.5, 0.70, 0.90]
const GRASS_MEADOW := [5.0, 0.85, 1.05]
const GRASS_OLIVE := [3.5, 0.80, 1.00]
const GRASS_VINE := [1.0, 0.80, 1.00]
const GRASS_WHEAT := [2.5, 0.80, 1.00]
const GRASS_WILD := [3.5, 0.95, 1.20]
const GRASS_CLIFF := [1.2, 0.85, 1.05]
const GRASS_DUNE := [0.8, 1.05, 1.20]
const GRASS_GULLY := [5.0, 1.00, 1.20]
const GRASS_TEMENOS := [3.5, 0.85, 1.05]


## Linear-light luminance of an sRGB colour.
static func luma(c: Color) -> float:
	return 0.2126 * pow(c.r, 2.2) + 0.7152 * pow(c.g, 2.2) + 0.0722 * pow(c.b, 2.2)


## Point-to-polyline distance and arc length of the closest point.
static func polyline_dist(pts: Array, p: Vector2) -> Vector2:
	var best := INF
	var best_s := 0.0
	var acc := 0.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / maxf(l2, 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		var l := sqrt(l2)
		if d < best:
			best = d
			best_s = acc + t * l
		acc += l
	# Beyond the ends the arc length keeps counting (negative before the spring).
	var a0: Vector2 = pts[0]
	var a1: Vector2 = pts[1]
	if best_s <= 0.0001:
		best_s = (p - a0).dot((a1 - a0).normalized())
	return Vector2(best, best_s)


static func gully_length() -> float:
	var acc := 0.0
	for k in GULLY_PTS.size() - 1:
		acc += (GULLY_PTS[k + 1] as Vector2).distance_to(GULLY_PTS[k])
	return acc


## Point on the gully at arc length s, and the downstream direction there.
static func gully_point(s: float) -> Array:
	var acc := 0.0
	for k in GULLY_PTS.size() - 1:
		var a: Vector2 = GULLY_PTS[k]
		var b: Vector2 = GULLY_PTS[k + 1]
		var l := a.distance_to(b)
		if s <= acc + l or k == GULLY_PTS.size() - 2:
			var t := clampf((s - acc) / l, 0.0, 1.0)
			return [a.lerp(b, t), (b - a) / l]
		acc += l
	return [GULLY_PTS[0], Vector2(0, 1)]


static func gully_bed(s: float) -> float:
	if s <= GULLY_BED[0].x:
		return GULLY_BED[0].y
	for k in GULLY_BED.size() - 1:
		var a: Vector2 = GULLY_BED[k]
		var b: Vector2 = GULLY_BED[k + 1]
		if s <= b.x:
			return lerpf(a.y, b.y, (s - a.x) / (b.x - a.x))
	return GULLY_BED[GULLY_BED.size() - 1].y


## Signed distance to the temenos rectangle (negative inside).
static func temenos_sd(p: Vector2) -> float:
	var d := p - TEMENOS_C
	var c := cos(TEMENOS_YAW)
	var s := sin(TEMENOS_YAW)
	# Godot Basis(UP, yaw): local X = (cos, -sin), local Z = (sin, cos) in (x, z).
	var lx := d.x * c - d.y * s
	var lz := d.x * s + d.y * c
	var qx := absf(lx) - TEMENOS_HALF.x
	var qz := absf(lz) - TEMENOS_HALF.y
	return Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0)


## World position of a point given in temenos-local coordinates.
static func temenos_point(lx: float, lz: float) -> Vector2:
	var c := cos(TEMENOS_YAW)
	var s := sin(TEMENOS_YAW)
	return TEMENOS_C + Vector2(c, -s) * lx + Vector2(s, c) * lz
