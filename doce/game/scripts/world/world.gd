class_name World
extends Node3D
## The island of Nemea (see nemea_layout.gd for the map). build() generates everything: the ground (NemeaTerrain),
## the flora, rocks and cliffs (NemeaProps), the village, pier and boats (NemeaVillage), the Lion's cave
## (NemeaCave), the broken passage and its bronze rings, the altars, the grass and the ambient fauna.
##
## API (the DOCE team contract):
##   build(seed)                 generate (once)
##   height_at(x, z) -> float    height of the rendered / collision ground triangle
##   ground(p) -> Vector3        p dropped onto the ground
##   normal_at(x, z) -> Vector3  smooth ground normal
##   is_water(x, z) -> bool      the ground there is under the sea (swim where the hero is below sea_level)
##   sea_level                   0.0
##   player_start() -> Transform3D   on the pier by Heracles' boat, facing north (the ridge on the horizon)
##   altars() -> Array           the altar nodes (Interactables: pray = heal + checkpoint), see NemeaAltar
##   spawn_groups() -> Array     [{kind: &"wolf"|&"boar", center: Vector3, radius: float, count: int}]
##   cave() -> Dictionary        {entrance_a, entrance_b, boulder, arena_center, pillars: Array[Vector3], lion_spawn}
##   anchors() -> Array          the bronze rings (also in group "chain_anchor")
##   boat_dock() -> Vector3      where the hero stands to board the boat to Lerna
##   bounds() -> Rect2           the playable area (XZ)
## Extras: water_depth(x, z), slope_at(x, z), is_walkable(x, z), places() (named points for tools and tests),
## boat() (the Lerna boat interactable), ambient (the fauna node), stats (build timings and counts),
## terrain_body (the terrain's StaticBody3D), and for the audio / UI: coast_distance(x, z) (m to the coastline,
## + inland), ground_color_at(x, z) (rgb ground, a = grassiness), cave_amount(pos) (0..1, 1 inside the Lion's cave).
##
## Collision: everything solid is a StaticBody3D on layer 1 (terrain trimesh per chunk, simple shapes for trunks,
## rocks, houses, walls and fences, trimesh for the cave lid and tunnel roofs). The boulder is on layer 4.

const L := preload("res://scripts/world/nemea_layout.gd")
const NemeaTerrain := preload("res://scripts/world/nemea_terrain.gd")
const NemeaProps := preload("res://scripts/world/nemea_props.gd")
const NemeaVillage := preload("res://scripts/world/nemea_village.gd")
const NemeaCave := preload("res://scripts/world/nemea_cave.gd")
const NemeaPassage := preload("res://scripts/world/nemea_passage.gd")
const NemeaStory := preload("res://scripts/world/nemea_story.gd")

var sea_level := 0.0
var terrain: RefCounted = null
var props: RefCounted = null
var village: RefCounted = null
var cave_builder: RefCounted = null
var passage: RefCounted = null
var stats := {}
var ambient: Node3D = null
## The terrain's StaticBody3D (layer 1; tools/phys_test.gd compares its ray hits with height_at()).
var terrain_body: StaticBody3D = null

var _altars: Array = []
var _anchors: Array = []
var _cave := {}
var _boat: Node3D = null
var _built := false
var _grass: Node3D = null


func build(seed_value: int = 1) -> void:
	if _built:
		return
	_built = true
	var t0 := Time.get_ticks_usec()
	terrain = NemeaTerrain.new()
	terrain.generate()
	terrain.init_ground_map()
	props = NemeaProps.new()
	props.setup(self, terrain, seed_value * 7919 + 13)
	_reserve_places()
	village = NemeaVillage.new()
	village.build(self, terrain, props)
	_boat = village.lerna_boat
	cave_builder = NemeaCave.new()
	cave_builder.build(self, terrain, props)
	_cave = cave_builder.info
	passage = NemeaPassage.new()
	passage.build(self, terrain, props)
	_anchors = passage.rings
	_altars = passage.altars
	var story := NemeaStory.new()
	story.build(self, terrain, props)
	stats["paw_prints"] = story.prints
	props.build()
	terrain.commit_textures()
	terrain.build_meshes(self, Materials.terrain())
	terrain_body = terrain.body
	terrain.build_water_texture()
	_apply_terrain_material()
	var grass := Grass.new()
	grass.name = "Grass"
	add_child(grass)
	grass.build(self)
	_grass = grass
	stats["grass_instances"] = grass.instances
	if Game.arg("fauna", "1") != "0":
		ambient = Ambient.new()
		add_child(ambient)
		ambient.setup(self, seed_value * 31 + 7)
		stats["cats"] = ambient.cats.size()
		stats["goats"] = ambient.goats.size()
	stats["terrain"] = terrain.timings
	stats["props"] = props.counts
	stats["total_ms"] = (Time.get_ticks_usec() - t0) / 1000
	print("Nemea world: %d ms | terrain %s" % [stats["total_ms"], str(terrain.timings)])
	print("Nemea props: %s | village %d tris, %d houses" % [str(props.counts), village.tris, village.houses.size()])
	print("Nemea life: %d paw prints, %d cats, %d goats" % [int(stats.get("paw_prints", 0)), int(stats.get("cats", 0)), int(stats.get("goats", 0))])


## Places the scatter keeps clear: the plaza, the pier, the passage rims, the cave mouths.
func _reserve_places() -> void:
	props.reserve(L.PLAZA, L.PLAZA_R + 3.0)
	props.reserve(L.PIER_A, 5.0)
	props.reserve(L.PASS_SOUTH, 5.0)
	props.reserve(L.PASS_NORTH, 5.0)
	props.reserve(L.MOUTH_A, 8.0)
	props.reserve(L.MOUTH_B, 8.0)
	props.reserve(L.GOAT_PEN, 7.0)
	for al in L.ALTARS:
		props.reserve(al[0], 5.5)


func _apply_terrain_material() -> void:
	var rect := Vector4(-NemeaTerrain.GM_EXT, -NemeaTerrain.GM_EXT, 2.0 * NemeaTerrain.GM_EXT, 2.0 * NemeaTerrain.GM_EXT)
	var tm := Materials.terrain()
	tm.set_shader_parameter("ground_tex", terrain.ground_tex)
	tm.set_shader_parameter("ground_rect", rect)
	tm.set_shader_parameter("detail_tex", terrain.detail_tex)


func _process(_delta: float) -> void:
	if cave_builder == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cave_builder.set_camera(cam.global_position)
		# No meadow inside the Lion's cave: the grass grids follow the camera and would cost ~250k vertices there.
		if _grass != null:
			_grass.visible = cave_amount(cam.global_position) < 0.6


# --- API -----------------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)


func normal_at(x: float, z: float) -> Vector3:
	return terrain.normal_at(x, z)


func is_water(x: float, z: float) -> bool:
	return terrain.height_at(x, z) < sea_level


func water_depth(x: float, z: float) -> float:
	return maxf(0.0, sea_level - terrain.height_at(x, z))


func slope_at(x: float, z: float) -> float:
	return terrain.slope_at(x, z)


## Distance (m) from (x, z) to the coastline, positive inland, negative out at sea (Sfx's sea bed).
func coast_distance(x: float, z: float) -> float:
	return terrain.field(terrain.sd, x, z)


## Smooth ground colour (rgb) and grassiness (a) at (x, z).
func ground_color_at(x: float, z: float) -> Color:
	return terrain.color_at(x, z)


## How much `pos` is inside the Lion's cave: 1 on the floor under the lid and in the tunnels, fading out over the
## last metres before each mouth; 0 outside and on top of the massif (Sfx's cave bed, the UI's labour card).
func cave_amount(pos: Vector3) -> float:
	var k: float = terrain.field(terrain.cave_w, pos.x, pos.z)
	if k <= 0.0:
		return 0.0
	return clampf(k, 0.0, 1.0) * (1.0 - smoothstep(L.CAVE_FLOOR + 8.0, L.CAVE_FLOOR + 11.0, pos.y))


## Gentle (< ~35 degrees), dry ground.
func is_walkable(x: float, z: float) -> bool:
	return terrain.height_at(x, z) > sea_level + 0.05 and terrain.normal_at(x, z).y > 0.82


func player_start() -> Transform3D:
	return Transform3D(Basis.IDENTITY, L.START)


func altars() -> Array:
	return _altars


func spawn_groups() -> Array:
	var out: Array = []
	for s in L.SPAWNS:
		var c: Vector2 = s["at"]
		out.append({"kind": s["kind"], "center": ground(Vector3(c.x, 0, c.y)), "radius": float(s["radius"]), "count": int(s["count"])})
	return out


func cave() -> Dictionary:
	return _cave


func anchors() -> Array:
	return _anchors


func boat_dock() -> Vector3:
	return L.BOAT_DOCK


func boat() -> Node3D:
	return _boat


## The XZ area the world data covers (the heightfield: the island, its islets and the sea round them).
func bounds() -> Rect2:
	return Rect2(-L.EXT, -L.EXT, 2.0 * L.EXT, 2.0 * L.EXT)


## Named places (tools, tests and the camera shots).
func places() -> Dictionary:
	var d := {
		"pier": L.START,
		"plaza": ground(Vector3(L.PLAZA.x, 0, L.PLAZA.y)),
		"north_gate": ground(Vector3(L.NORTH_GATE.x, 0, L.NORTH_GATE.y)),
		"passage_south": ground(Vector3(L.PASS_SOUTH.x, 0, L.PASS_SOUTH.y)),
		"passage_north": ground(Vector3(L.PASS_NORTH.x, 0, L.PASS_NORTH.y)),
		"cave_a": ground(Vector3(L.MOUTH_A.x, 0, L.MOUTH_A.y)),
		"cave_b": ground(Vector3(L.MOUTH_B.x, 0, L.MOUTH_B.y)),
		"arena": ground(Vector3(L.CAVE_C.x, 0, L.CAVE_C.y)),
	}
	for i in L.ALTARS.size():
		var a: Vector2 = L.ALTARS[i][0]
		d["altar_%d" % i] = ground(Vector3(a.x, 0, a.y))
	return d
