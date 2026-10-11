extends Node3D
## The combat test arena's "world" (tools/arena.tscn): a round paved platform 32 m in radius standing out of the sea,
## implementing the World API (scripts/world/world.gd) so the hero, the camera and the sea work as on the island.
## Zones (north = -Z):
##   centre      the hero's start (0, 14) and the training ground: three straw posts, the sparring post (arena.gd)
##   west        a cliff block 3.8 m high with a bronze ring on its face: zip up and climb onto the ledge
##   north       a 16 m sea gap: a tall sea stack with ring A (on its east face), the far cliff with ring B: ring to
##               ring, then onto the far cliff's top
##   east        a ruined wall with a doorway narrower than the boulder: drag the boulder into it to seal it
##   south-west  a row of three pillars: yank the beast dummy into one (it is stunned), then wrestle it
##   south-east  a terrace with ramps of 15, 30, 45 and 58 degrees (the last one too steep to climb)
##   stairs      down into the sea on the south and the north side (climb out after a swim)
## spots() returns the named places the arena script and the bot use.

const FLOOR_R := 32.0
const FLOOR_Y := 1.2
const SEABED := -3.5
const STAIRS_HALF_W := 3.0
const STEP_RISE := 0.4
const STEP_RUN := 0.7
const STEPS := 7 # from the floor down to 1.6 m under the sea
## West cliff block (x0, x1, z0, z1, top) and its ring.
const WEST := Rect2(-31.0, -6.0, 8.0, 12.0)
const WEST_TOP := 5.0
## North: the sea stack (centre, radius, top) and the far cliff.
const STACK := Vector3(-3.0, 0.0, -40.0)
const STACK_R := 1.5
const STACK_TOP := 8.5
const FAR := Rect2(-10.0, -60.0, 20.0, 12.0)
const FAR_TOP := 5.2
## East: the wall (x of its west face, thickness, z extent), the doorway (half width, height).
const WALL_X := 21.0
const WALL_T := 0.8
const WALL_Z := 7.0
const WALL_H := 3.6
const DOOR_HW := 1.15
const DOOR_H := 2.8
## South-west: the pillar row.
const PILLARS: Array[Vector3] = [Vector3(-16.0, 0.0, 15.0), Vector3(-12.0, 0.0, 15.0), Vector3(-8.0, 0.0, 15.0)]
const PILLAR_R := 0.8
## South-east: the terrace and its ramps (degrees).
const TERRACE := Rect2(12.0, 16.0, 10.0, 9.5)
const TERRACE_H := 1.6
const RAMPS: Array[float] = [15.0, 30.0, 45.0, 58.0]

var sea_level := 0.0
var props_body: StaticBody3D
var terrain_body: StaticBody3D
var _anchors: Array = []
var _boulder: Boulder
var _rocks := MeshBuilder.new(23)


func build(_seed: int = 7) -> void:
	terrain_body = StaticBody3D.new()
	terrain_body.name = "Platform"
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 0
	add_child(terrain_body)
	props_body = StaticBody3D.new()
	props_body.name = "Props"
	props_body.collision_layer = 1
	props_body.collision_mask = 0
	add_child(props_body)
	_rocks.vary = 0.04
	_build_platform()
	_build_stairs(1.0)
	_build_stairs(-1.0)
	_build_seabed()
	_build_west()
	_build_north()
	_build_east()
	_build_pillars()
	_build_terrace()
	_build_decor()
	var mi := MeshInstance3D.new()
	mi.name = "Rocks"
	mi.mesh = _rocks.commit()
	mi.material_override = Materials.lowpoly()
	add_child(mi)
	_build_water_texture()


# --- helpers ---------------------------------------------------------------------------------------------------

func _add_box(c: Vector3, size: Vector3, body: StaticBody3D = null, basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(basis, c)
	(body if body else props_body).add_child(cs)


func _add_cyl(r: float, h: float, base: Vector3, body: StaticBody3D = null) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = base + Vector3(0, h * 0.5, 0)
	(body if body else terrain_body).add_child(cs)


func _mesh(mb: MeshBuilder, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	add_child(mi)
	return mi


func _ring(p: Vector3, normal: Vector3, nm: String) -> ChainRing:
	var r := ChainRing.new(0.0, true)
	r.name = nm
	add_child(r)
	var z := normal.normalized()
	var x := Vector3.UP.cross(z).normalized()
	r.global_transform = Transform3D(Basis(x, Vector3.UP, z), p)
	_anchors.append(r)
	return r


## A rough rock face (cliff block): a box of stone courses with a rocky crown, collision included.
func _cliff(rect: Rect2, bottom: float, top: float, nm: String, seed_value: int) -> void:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = 0.05
	var c := Vector3(rect.position.x + rect.size.x * 0.5, bottom, rect.position.y + rect.size.y * 0.5)
	var h := top - bottom
	# courses of big stones, alternating tones
	var courses := maxi(2, int(h / 0.9))
	for i in courses:
		var y0 := bottom + h * float(i) / courses
		var y1 := bottom + h * float(i + 1) / courses
		var inset := 0.04 * float(i % 2)
		var col := PalExtra.ROCK_MID if i % 2 == 0 else Pal.ROCK
		mb.block(Vector3(c.x, y0, c.z), Vector3(rect.size.x - inset, y1 - y0 - 0.02, rect.size.y - inset), col, Pal.LIMESTONE_DARK)
	# the top: limestone slabs with a little grass
	mb.block(Vector3(c.x, top - 0.12, c.z), Vector3(rect.size.x + 0.15, 0.14, rect.size.y + 0.15), Pal.LIMESTONE, Pal.GRASS)
	_mesh(mb, nm)
	_add_box(Vector3(c.x, (bottom + top) * 0.5, c.z), Vector3(rect.size.x, h, rect.size.y), terrain_body)


# --- the platform ------------------------------------------------------------------------------------------------

## Paving: concentric rings of slabs (alternating limestone and marble tones) on a rock plinth.
func _build_platform() -> void:
	var mb := MeshBuilder.new(3)
	mb.vary = 0.035
	var rings := 12
	for ri in rings:
		var r0 := FLOOR_R * float(ri) / rings
		var r1 := FLOOR_R * float(ri + 1) / rings
		var n := maxi(6, int(TAU * (r0 + r1) * 0.5 / 2.4))
		for si in n:
			var a0 := TAU * float(si) / n + ri * 0.21
			var a1 := TAU * float(si + 1) / n + ri * 0.21
			var g := 0.05 # grout gap (m)
			var c := Pal.LIMESTONE if (si + ri) % 3 != 0 else Pal.MARBLE_SHADE
			if (si * 7 + ri * 3) % 11 == 0:
				c = PalExtra.ROCK_MID
			var ri0 := r0 + (g if ri > 0 else 0.0)
			var ri1 := r1 - g
			var da := g / maxf(r1, 0.5)
			var p := [Vector3(cos(a0 + da) * ri0, FLOOR_Y, sin(a0 + da) * ri0), Vector3(cos(a1 - da) * ri0, FLOOR_Y, sin(a1 - da) * ri0),
				Vector3(cos(a1 - da) * ri1, FLOOR_Y, sin(a1 - da) * ri1), Vector3(cos(a0 + da) * ri1, FLOOR_Y, sin(a0 + da) * ri1)]
			mb.quad(p[0], p[1], p[2], p[3], c)
	mb.cyl(Vector3(0, SEABED, 0), FLOOR_Y - 0.02 - SEABED, FLOOR_R + 0.8, FLOOR_R, 64, PalExtra.ROCK_WET, false)
	mb.disc(Vector3(0, FLOOR_Y - 0.02, 0), FLOOR_R, 64, Pal.ROCK_DARK)
	# a low marble kerb round the edge, broken where the stairs go down
	for si in 64:
		var a0 := TAU * float(si) / 64.0
		var a1 := TAU * float(si + 1) / 64.0
		var mid := (a0 + a1) * 0.5
		if _stair_gap(mid):
			continue
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var inner := FLOOR_R - 0.45
		var lo := Vector3(0, FLOOR_Y, 0)
		var hi := Vector3(0, FLOOR_Y + 0.3, 0)
		mb.quad(p0 * FLOOR_R + lo, p0 * FLOOR_R + hi, p1 * FLOOR_R + hi, p1 * FLOOR_R + lo, Pal.MARBLE_SHADE)
		mb.quad(p0 * inner + hi, p0 * inner + lo, p1 * inner + lo, p1 * inner + hi, Pal.MARBLE_SHADE)
		mb.quad(p0 * inner + hi, p1 * inner + hi, p1 * FLOOR_R + hi, p0 * FLOOR_R + hi, Pal.MARBLE)
	_mesh(mb, "Paving")
	_add_cyl(FLOOR_R, FLOOR_Y - SEABED, Vector3(0, SEABED, 0))
	for si in 64:
		var mid := TAU * (float(si) + 0.5) / 64.0
		if _stair_gap(mid):
			continue
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.45, 0.3, TAU * FLOOR_R / 64.0 + 0.05)
		cs.shape = b
		var c := Vector3(cos(mid), 0, sin(mid)) * (FLOOR_R - 0.225) + Vector3(0, FLOOR_Y + 0.15, 0)
		cs.transform = Transform3D(Basis(Vector3.UP, -mid), c)
		props_body.add_child(cs)


func _stair_gap(angle: float) -> bool:
	return absf(wrapf(angle - PI * 0.5, -PI, PI)) < 0.11 or absf(wrapf(angle + PI * 0.5, -PI, PI)) < 0.11


## Steps down into the sea on the south (side 1, +Z) or the north (side -1).
func _build_stairs(side: float) -> void:
	var mb := MeshBuilder.new(9 if side > 0.0 else 10)
	mb.vary = 0.03
	for i in STEPS:
		var top := FLOOR_Y - STEP_RISE * (i + 1)
		var z0 := FLOOR_R - 0.2 + STEP_RUN * i
		var z1 := z0 + STEP_RUN
		var zc := (z0 + z1) * 0.5 * side
		mb.block(Vector3(0, SEABED, zc), Vector3(STAIRS_HALF_W * 2.0, top - SEABED, z1 - z0), PalExtra.ROCK_MID, Pal.LIMESTONE)
		_add_box(Vector3(0, (top + SEABED) * 0.5, zc), Vector3(STAIRS_HALF_W * 2.0, top - SEABED, z1 - z0), terrain_body)
	_mesh(mb, "Stairs")


func _build_seabed() -> void:
	_add_box(Vector3(0, SEABED - 1.0, 0), Vector3(400, 2, 400), terrain_body)


# --- the zones ---------------------------------------------------------------------------------------------------

## West: a cliff block with a ring on its east face, under the lip of its top.
func _build_west() -> void:
	_cliff(WEST, FLOOR_Y - 0.3, WEST_TOP, "WestCliff", 41)
	var face_x := WEST.position.x + WEST.size.x
	_ring(Vector3(face_x, WEST_TOP - 0.75, 0.0), Vector3.RIGHT, "RingLedge")


## North: the sea stack (ring A on its south face) and the far cliff (ring B on its south face, a ledge above it).
func _build_north() -> void:
	var mb := MeshBuilder.new(44)
	mb.vary = 0.05
	var prof := []
	for i in 9:
		var k := float(i) / 8.0
		var r := STACK_R * (1.15 - 0.25 * k) + sin(k * 9.0) * 0.08
		prof.append(Vector2(r, lerpf(SEABED, STACK_TOP, k)))
	prof.append(Vector2(0.4, STACK_TOP + 0.25))
	mb.lathe(prof, 9, func(c: Vector3, ring: int, _side: int) -> Color:
		return PalExtra.ROCK_WET if c.y < 0.4 else (Pal.ROCK if ring % 2 == 0 else PalExtra.ROCK_MID))
	_mesh(mb, "SeaStack").add_to_group("camera_cut")
	_add_cyl(STACK_R * 1.05, STACK_TOP - SEABED, Vector3(STACK.x, SEABED, STACK.z))
	(get_node("SeaStack") as Node3D).position = Vector3(STACK.x, 0, STACK.z)
	# ring A on the stack's east face: from under it the far ring is in sight past the stack
	_ring(Vector3(STACK.x + STACK_R * 0.98, 4.4, STACK.z), Vector3.RIGHT, "RingStack")
	_cliff(FAR, SEABED, FAR_TOP, "FarCliff", 45)
	_ring(Vector3(0.0, FAR_TOP - 0.85, FAR.position.y + FAR.size.y), Vector3.BACK, "RingFar")


## East: a ruined wall with a doorway 2.3 m wide (the boulder is 2.5 m across: it jams in it and seals it).
func _build_east() -> void:
	var mb := MeshBuilder.new(46)
	mb.vary = 0.04
	var x0 := WALL_X
	var xc := WALL_X + WALL_T * 0.5
	for side in [-1.0, 1.0]:
		var z0: float = DOOR_HW * side
		var z1: float = WALL_Z * side
		var zc := (z0 + z1) * 0.5
		var zl := absf(z1 - z0)
		var courses := 4
		for i in courses:
			var y0 := FLOOR_Y + WALL_H * float(i) / courses
			var y1 := FLOOR_Y + WALL_H * float(i + 1) / courses
			mb.block(Vector3(xc, y0, zc), Vector3(WALL_T - 0.03 * (i % 2), y1 - y0 - 0.02, zl), Pal.LIMESTONE if i % 2 == 0 else Pal.MARBLE_SHADE, Pal.LIMESTONE_DARK)
		_add_box(Vector3(xc, FLOOR_Y + WALL_H * 0.5, zc), Vector3(WALL_T, WALL_H, zl), props_body)
	# the lintel and the door posts' bronze-capped sills
	mb.block(Vector3(xc, FLOOR_Y + DOOR_H, 0.0), Vector3(WALL_T + 0.1, WALL_H - DOOR_H + 0.15, DOOR_HW * 2.0 + 0.6), Pal.MARBLE, Pal.LIMESTONE)
	_add_box(Vector3(xc, FLOOR_Y + DOOR_H + (WALL_H - DOOR_H) * 0.5, 0.0), Vector3(WALL_T, WALL_H - DOOR_H, DOOR_HW * 2.0), props_body)
	mb.block(Vector3(xc, FLOOR_Y, 0.0), Vector3(WALL_T + 0.1, 0.06, DOOR_HW * 2.0), Pal.MARBLE_SHADE)
	_mesh(mb, "Wall")
	_boulder = Boulder.new()
	_boulder.name = "Boulder"
	add_child(_boulder)
	_boulder.global_position = Vector3(x0 - 7.5, FLOOR_Y + 0.02, 0.0)


func door_point() -> Vector3:
	return Vector3(WALL_X + WALL_T * 0.5, FLOOR_Y, 0.0)


## South-west: three fluted marble pillars in a row.
func _build_pillars() -> void:
	var mb := MeshBuilder.new(17)
	mb.vary = 0.03
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for p in PILLARS:
		var base := Vector3(p.x, FLOOR_Y, p.z)
		mb.cyl(base + Vector3(0, -0.1, 0), 0.45, 1.15, 1.05, 8, Pal.LIMESTONE_DARK, true, 0.0, Pal.LIMESTONE)
		ModelsNature.fluted_shaft(mb, rng, base + Vector3(0, 0.35, 0), 4.6, PILLAR_R, PILLAR_R * 0.9, 10, Pal.MARBLE_SHADE, Pal.LIMESTONE, 0.0)
		mb.cyl(base + Vector3(0, 4.95, 0), 0.35, PILLAR_R * 1.05, PILLAR_R * 1.3, 8, Pal.MARBLE, true, 0.0, Pal.MARBLE)
		_add_cyl(PILLAR_R + 0.02, 5.4, base + Vector3(0, -0.1, 0), props_body)
	var mi := _mesh(mb, "Pillars")
	mi.add_to_group("pillar")
	mi.add_to_group("camera_cut") # (CameraRig cuts them away between the lens and the hero / the wrestle)


## South-east: a terrace 1.6 m high with four ramps down its west side (15, 30, 45, 58 degrees).
func _build_terrace() -> void:
	var mb := MeshBuilder.new(19)
	mb.vary = 0.03
	var t := TERRACE
	var top := FLOOR_Y + TERRACE_H
	mb.block(Vector3(t.position.x + t.size.x * 0.5, FLOOR_Y - 0.05, t.position.y + t.size.y * 0.5), Vector3(t.size.x, TERRACE_H + 0.05, t.size.y), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	_add_box(Vector3(t.position.x + t.size.x * 0.5, FLOOR_Y + TERRACE_H * 0.5, t.position.y + t.size.y * 0.5), Vector3(t.size.x, TERRACE_H, t.size.y), props_body)
	var w := 2.0
	for i in RAMPS.size():
		var ang := deg_to_rad(RAMPS[i])
		var run := TERRACE_H / tan(ang)
		var z0 := t.position.y + 0.3 + float(i) * 2.35
		var z1 := z0 + w
		var x1 := t.position.x
		var x0 := x1 - run
		var a := Vector3(x0, FLOOR_Y, z0)
		var b := Vector3(x1, top, z0)
		var c := Vector3(x1, top, z1)
		var d := Vector3(x0, FLOOR_Y, z1)
		var col := Pal.MARBLE_SHADE if i % 2 == 0 else Pal.LIMESTONE
		mb.quad(a, d, c, b, col) # the slope
		mb.tri(a, b, Vector3(x1, FLOOR_Y, z0), PalExtra.ROCK_MID) # the sides
		mb.tri(d, Vector3(x1, FLOOR_Y, z1), c, PalExtra.ROCK_MID)
		var cs := CollisionShape3D.new()
		var cp := ConvexPolygonShape3D.new()
		cp.points = PackedVector3Array([a, Vector3(x1, FLOOR_Y, z0), b, d, Vector3(x1, FLOOR_Y, z1), c])
		cs.shape = cp
		props_body.add_child(cs)
	_mesh(mb, "Terrace")


## A few olive trees and rocks round the edge (trunks collide).
func _build_decor() -> void:
	var spots := [Vector3(-24.0, 0, 18.0), Vector3(24.0, 0, -16.0), Vector3(-20.0, 0, -22.0), Vector3(26.0, 0, 12.0)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var mi := MeshInstance3D.new()
		mi.mesh = ModelsNature.olive_tree(31 + i * 7)
		mi.material_override = Materials.foliage(0.03)
		mi.position = Vector3(p.x, FLOOR_Y, p.z)
		mi.rotation.y = float(i) * 1.7
		add_child(mi)
		_add_cyl(0.28, 2.2, Vector3(p.x, FLOOR_Y, p.z), props_body)
	for p in [Vector3(-27.0, 0, -12.0), Vector3(28.0, 0, 4.0), Vector3(-6.0, 0, -29.0)]:
		_rocks.ico(Vector3(p.x, FLOOR_Y + 0.25, p.z), 0.7, Pal.ROCK, 1, 0.12, Vector3(1.2, 0.7, 1.0), Pal.ROCK_DARK)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.65
		cs.shape = sp
		cs.position = Vector3(p.x, FLOOR_Y + 0.2, p.z)
		props_body.add_child(cs)


func _build_water_texture() -> void:
	var n := 220
	var span := 150.0
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	for iz in n:
		for ix in n:
			var x := -span * 0.5 + (ix + 0.5) * span / n
			var z := -span * 0.5 + (iz + 0.5) * span / n
			var d := clampf(-height_at(x, z) / 6.0, 0.0, 1.0)
			img.set_pixel(ix, iz, Color(d, d, d))
	RenderingServer.global_shader_parameter_set("g_water_tex", ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_set("g_water_rect", Vector4(-span * 0.5, -span * 0.5, span, span))


# --- World API ---------------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	if FAR.has_point(Vector2(x, z)):
		return FAR_TOP
	if Vector2(x - STACK.x, z - STACK.z).length() <= STACK_R:
		return STACK_TOP
	if WEST.has_point(Vector2(x, z)):
		return WEST_TOP
	if TERRACE.has_point(Vector2(x, z)):
		return FLOOR_Y + TERRACE_H
	if Vector2(x, z).length() <= FLOOR_R:
		return FLOOR_Y
	if absf(x) <= STAIRS_HALF_W and absf(z) > FLOOR_R - 0.2:
		var i := int(floor((absf(z) - (FLOOR_R - 0.2)) / STEP_RUN))
		if i < STEPS:
			return FLOOR_Y - STEP_RISE * (i + 1)
	return SEABED


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func normal_at(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < sea_level


## Footstep surface (the hero's step sounds): stone everywhere here.
func surface_at(_p: Vector3) -> String:
	return "stone"


func player_start() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, FLOOR_Y, 14.0))


func altars() -> Array:
	return []


func spawn_groups() -> Array:
	return []


func cave() -> Dictionary:
	return {"entrance_a": Vector3(-FLOOR_R, FLOOR_Y, 0), "entrance_b": door_point(), "boulder": _boulder,
		"arena_center": Vector3(0, FLOOR_Y, 0), "pillars": PILLARS.map(func(p: Vector3) -> Vector3: return Vector3(p.x, FLOOR_Y, p.z)),
		"lion_spawn": Vector3(-12.0, FLOOR_Y, 19.0)}


func anchors() -> Array:
	return _anchors


func boat_dock() -> Vector3:
	return Vector3(0, FLOOR_Y, FLOOR_R)


func bounds() -> Rect2:
	return Rect2(-75, -75, 150, 150)


## Named places for tools/arena.gd and the bot.
func spots() -> Dictionary:
	return {
		"start": Vector3(0, FLOOR_Y, 14.0),
		"posts": [Vector3(-3.0, FLOOR_Y, 6.0), Vector3(0.0, FLOOR_Y, 4.5), Vector3(3.0, FLOOR_Y, 6.0)],
		"sparring": Vector3(7.0, FLOOR_Y, 9.0),
		"straw": [Vector3(6.5, FLOOR_Y, 2.5), Vector3(9.5, FLOOR_Y, 3.5)],
		"sacks": [Vector3(-8.0, FLOOR_Y, -6.0), Vector3(-13.0, FLOOR_Y, -11.0)],
		"beast": Vector3(-12.0, FLOOR_Y, 19.0),
		"beast_throw": Vector3(-9.8, FLOOR_Y, 9.5),
		"ledge_throw": Vector3(-13.0, FLOOR_Y, 0.0),
		"ledge_top": Vector3(-27.0, WEST_TOP, 0.0),
		"gap_throw": Vector3(0.0, FLOOR_Y, -29.5),
		"far_top": Vector3(0.0, FAR_TOP, -54.0),
		"door": door_point(),
		"door_throw": Vector3(27.0, FLOOR_Y, 0.0),
		"boulder": Vector3(WALL_X - 7.5, FLOOR_Y, 0.0),
	}
