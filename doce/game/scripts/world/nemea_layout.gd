extends RefCounted
## The island of Nemea (DOCE, first slice): every place, path and level the World is built from.
##
## Metres; X east, Z south, Y up; sea level 0. The island is a left hand lying palm down with the fingers to the
## north: the village of Nemea and its beach and pier at the wrist (south), the forest of holm oaks and pines in
## the palm, olive terraces on the east hill, the thumb to the west-north-west (golden cliffs, cut off from the
## palm by a narrow sea inlet that the broken passage crosses with the chain spear), and the Lion's ridge where the
## fingers start (north): a rock massif with the cave inside and three spurs running down to the sea.
##
## The critical path: pier -> village -> north gate -> forest (wolves) -> west ramp -> broken passage (rings) ->
## the thumb (boars, altar on the headland) -> the ridge meadow (altar) -> the two cave mouths. The ridge meadow
## sits on an escarpment above the forest and can only be reached across the passage; the east hill (olive
## terraces, altar) is an optional detour from the village.

# --- heightfield grid ----------------------------------------------------------------------------------------
const EXT := 192.0 # the grid covers [-EXT, EXT]^2
const CELL := 1.0
const N := 385 # vertices per side

# --- levels --------------------------------------------------------------------------------------------------
const FOREST_H := 12.0
const UPPER_H := 22.0 # ridge meadow and the thumb, above the escarpment
const WEST_H := 20.0 # the palm's west plateau, south of the inlet
const MASSIF_H := 40.0
const CAVE_FLOOR := 21.0
const PIER_DECK := 1.55

# --- coast ---------------------------------------------------------------------------------------------------
const PALM_R := 126.0
## Fingers and thumb: tapered capsules [a, b, radius at a, radius at b].
const FINGERS := [
	[Vector2(0, -104), Vector2(0, -156), 21.0, 14.0],
	[Vector2(42, -100), Vector2(76, -146), 18.0, 12.0],
	[Vector2(-44, -102), Vector2(-80, -142), 18.0, 12.0],
]
const THUMB := [Vector2(-86, -46), Vector2(-148, -62), 24.0, 17.0]
## The sea inlet between the thumb and the palm: [a (at sea), b (head), radius at a, radius at b].
const INLET := [Vector2(-196, -13), Vector2(-97, -13), 12.0, 8.5]
## Islets: [centre, radii (x, z), height].
const ISLETS := [
	[Vector2(98, 152), Vector2(19, 14), 11.0],
	[Vector2(-116, 126), Vector2(11, 9), 7.0],
	[Vector2(-38, -176), Vector2(10, 8), 9.0],
	[Vector2(122, -126), Vector2(12, 10), 10.0],
	[Vector2(156, 34), Vector2(9, 8), 6.0],
]
## Sea stacks (rock pillars, built as props): [centre, radius, height].
const STACKS := [
	[Vector2(-146, 10), 4.5, 15.0],
	[Vector2(-162, -32), 3.8, 12.0],
	[Vector2(-58, -168), 3.5, 10.0],
	[Vector2(144, -60), 4.0, 9.0],
]

# --- regions -------------------------------------------------------------------------------------------------
## The escarpment between the forest (south-east of the line) and the upper level (north-west of it).
const ESCARPMENT := [
	Vector2(-96, -22), Vector2(-86, -36), Vector2(-72, -51), Vector2(-50, -59), Vector2(-22, -58),
	Vector2(8, -61), Vector2(32, -66), Vector2(50, -78), Vector2(62, -96), Vector2(68, -120), Vector2(72, -150),
]
## The ridge massif (rounded rectangle): centre, half size, corner radius.
const MASSIF_C := Vector2(0, -117)
const MASSIF_HALF := Vector2(52, 18.5)
const MASSIF_CORNER := 16.0
const MASSIF_PEAK := Vector2(-6, -124)
## Limestone spires on the massif's crest (the ridge's silhouette from the village): [xz, height, radius].
## The tallest pair stands over the cave like a crown, the goal on the horizon.
const SPIRES := [
	[Vector2(-10, -126), 25.0, 6.2],
	[Vector2(13, -128), 21.0, 5.6],
	[Vector2(-25, -121), 15.0, 5.0],
	[Vector2(28, -122), 13.0, 4.6],
	[Vector2(-39, -113), 10.0, 4.2],
	[Vector2(43, -111), 9.0, 4.0],
	[Vector2(1, -135), 17.0, 5.0],
]
const EAST_HILL := Vector2(86, 8)
const EAST_HILL_R := 58.0
const EAST_HILL_H := 27.0

# --- village -------------------------------------------------------------------------------------------------
const PLAZA := Vector2(0, 76)
const PLAZA_R := 9.0
const WELL := Vector2(-2.5, 74.5)
const PLANE_TREE := Vector2(6.0, 70.5)
const SHRINE := Vector2(-7.5, 69.0)
const NORTH_GATE := Vector2(-4, 54)
const GOAT_PEN := Vector2(26, 31)
## Houses: [centre, yaw (unused: each house turns to the plaza or its nearest lane), kind (0 small, 1 two-storey),
## scale]. Checked against the roads (pads clear every road edge by 1 m), the plaza, the fence and each other.
const HOUSES := [
	[Vector2(-16, 67), 0.0, 1, 1.25],
	[Vector2(-20, 80), 0.0, 0, 1.25],
	[Vector2(-9, 93), 0.0, 0, 1.25],
	[Vector2(19, 85), 0.0, 1, 1.25],
	[Vector2(27, 76), 0.0, 0, 1.2],
	[Vector2(-33, 75), 0.0, 0, 1.2],
	[Vector2(30, 93), 0.0, 0, 1.2],
	[Vector2(-30, 64), 0.0, 1, 1.2],
	[Vector2(12, 62), 0.0, 0, 1.2],
	[Vector2(-43, 86), 0.0, 1, 1.2],
	[Vector2(39, 82), 0.0, 1, 1.2],
	[Vector2(-1, 98), 0.0, 0, 1.15],
	[Vector2(-22, 99), 0.0, 0, 1.15],
]
const PIER_A := Vector2(14, 103) # on the sand
const PIER_B := Vector2(14, 142) # the end, over 3 m of water
const PIER_HALF_W := 1.7
const BOAT_HERACLES := Vector3(18.6, 0.0, 135.0)
const BOAT_LERNA := Vector3(8.6, 0.0, 132.0)
const START := Vector3(14.0, PIER_DECK, 130.0)
## On the pier deck (west edge) beside the Lerna ship's stern: where the hero stands to board it.
const BOAT_DOCK := Vector3(12.9, PIER_DECK, 134.5)

# --- the broken passage --------------------------------------------------------------------------------------
const PASS_X := -114.0
const PASS_SOUTH := Vector2(-114, 3.5) # landing on the south rim (its edge is ~4 m north)
const PASS_NORTH := Vector2(-114, -28.5) # landing on the north rim (its edge is ~4 m south)
const PASS_STACK := Vector2(-114, -13.5)
const PASS_STACK_TOP := 18.6

# --- altars (checkpoints on viewpoints) ----------------------------------------------------------------------
## [position xz, yaw (the altar's front, +Z, turns to the approach: the hero respawns there), name].
const ALTARS := [
	[Vector2(-148, -60), 1.57, "Altar del Promontorio"],
	[Vector2(86, 7), -0.64, "Altar de los Olivos"],
	[Vector2(-4, -67), -2.67, "Altar de la Sierra"],
]

# --- cave ----------------------------------------------------------------------------------------------------
const CAVE_C := Vector2(2, -114)
const CAVE_R := 13.5 # flat floor radius
const CAVE_WALL := 3.2 # the walls rise to the massif within this many metres
const MOUTH_A := Vector2(-27, -91.5)
const MOUTH_B := Vector2(33, -92.5)
const TUNNEL_HW := 3.6 # half width of the main tunnel (mouth A)
const TUNNEL_H := 7.0 # its height
const TUNNEL_B_HW := 1.75 # the back way (mouth B) is a narrow crack the boulder can plug
const TUNNEL_B_H := 4.6
const LID_EDGE := 12.0 # lid height above the floor at its rim
const LID_TOP := 15.0 # lid height above the floor at its centre

# --- paths ---------------------------------------------------------------------------------------------------
## [points, half width]. The first one is the main road from the pier to the passage.
const PATHS := [
	# 0 main road: pier -> plaza -> north gate -> forest -> west ramp -> passage (south rim)
	[[Vector2(14, 106), Vector2(12, 98), Vector2(7, 90), Vector2(2, 83), Vector2(-2, 68), Vector2(-4, 58),
		Vector2(-7, 46), Vector2(-14, 33), Vector2(-22, 20), Vector2(-33, 9), Vector2(-48, 3), Vector2(-62, 1),
		Vector2(-76, -1), Vector2(-90, 2), Vector2(-102, 4), Vector2(-113, 4.0)], 1.9],
	# 1 thumb: passage (north rim) -> boar clearing -> ridge meadow -> altar
	[[Vector2(-114, -29.5), Vector2(-112, -38), Vector2(-106, -48), Vector2(-96, -60), Vector2(-84, -70),
		Vector2(-70, -77), Vector2(-52, -80), Vector2(-34, -79), Vector2(-18, -75), Vector2(-6, -71)], 1.7],
	# 2 meadow -> cave mouth A
	[[Vector2(-18, -75), Vector2(-22, -82), Vector2(-26, -88), Vector2(-27, -91)], 1.5],
	# 3 meadow -> cave mouth B
	[[Vector2(-6, -71), Vector2(8, -77), Vector2(22, -84), Vector2(31, -89), Vector2(33, -92)], 1.5],
	# 4 thumb headland altar
	[[Vector2(-106, -48), Vector2(-120, -53), Vector2(-134, -57), Vector2(-145, -59)], 1.4],
	# 5 east road: plaza -> olive terraces -> hill top altar
	[[Vector2(4, 78), Vector2(16, 72), Vector2(30, 64), Vector2(44, 56), Vector2(56, 47), Vector2(64, 38),
		Vector2(70, 30), Vector2(74, 22), Vector2(80, 15), Vector2(85, 10)], 1.6],
	# 6 west lane: plaza -> south-west cove
	[[Vector2(-4, 80), Vector2(-16, 86), Vector2(-32, 92), Vector2(-50, 97), Vector2(-66, 101)], 1.3],
	# 7 forest trail: wolf clearing -> north meadow (where the paw prints meet the escarpment)
	[[Vector2(-22, 20), Vector2(-12, 6), Vector2(-2, -8), Vector2(6, -22), Vector2(8, -36), Vector2(4, -50)], 1.2],
	# 8 goat pen lane: main road -> broken pen
	[[Vector2(-6, 50), Vector2(6, 44), Vector2(18, 37), Vector2(26, 32)], 1.1],
]

# --- encounters ----------------------------------------------------------------------------------------------
const SPAWNS := [
	{"kind": &"wolf", "at": Vector2(-24, 14), "radius": 9.0, "count": 3},
	{"kind": &"wolf", "at": Vector2(6, -30), "radius": 11.0, "count": 4},
	{"kind": &"boar", "at": Vector2(-104, -47), "radius": 11.0, "count": 1},
	{"kind": &"boar", "at": Vector2(-78, -72), "radius": 12.0, "count": 2},
	{"kind": &"boar", "at": Vector2(60, 34), "radius": 10.0, "count": 1},
]

## The lion's paw prints: from the broken goat pen through the forest to the foot of the escarpment, then on
## the meadow above to cave mouth A.
const PAW_TRAIL := [
	[Vector2(24, 29), Vector2(18, 18), Vector2(13, 4), Vector2(10, -12), Vector2(8, -28), Vector2(5, -44), Vector2(3, -56)],
	[Vector2(0, -64), Vector2(-8, -72), Vector2(-17, -80), Vector2(-24, -88)],
]
