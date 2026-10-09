extends Node3D
## The combat test arena's "world" (tools/arena.tscn): a round paved stone platform 20 m in radius standing 1.2 m
## out of the sea, with steps down into the water on the south side, three bronze rings on standing stones, a
## boulder, a broken pillar and three training dummies (placed by tools/arena.gd). Implements the World API
## (scripts/world/world.gd) so the hero, the camera and the sea work exactly as on the island.

const FLOOR_R := 20.0
const FLOOR_Y := 1.2
const SEABED := -3.5
const STAIRS_HALF_W := 3.0
const STEP_RISE := 0.4
const STEP_RUN := 0.7
const STEPS := 7 # from the floor down to 1.6 m under the sea

var sea_level := 0.0
var props_body: StaticBody3D
var terrain_body: StaticBody3D
var _anchors: Array = []
var _boulder: Boulder
var _pillar := Vector3(7.0, FLOOR_Y, -5.0)


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
	_build_platform()
	_build_stairs()
	_build_seabed()
	_build_water_texture()
	# Three rings on standing stones round the edge, a pillar and the boulder.
	for k in 3:
		var a := deg_to_rad(200.0 + k * 70.0)
		var p := Vector3(cos(a), 0.0, sin(a)) * 16.5
		var ring := ChainRing.new(3.2 + k * 0.5)
		ring.name = "Ring_%d" % k
		add_child(ring)
		var to_c := -Vector2(p.x, p.z).normalized()
		ring.global_transform = Transform3D(Basis(Vector3.UP, atan2(to_c.x, to_c.y)), Vector3(p.x, FLOOR_Y, p.z))
		_anchors.append(ring)
	var mb := MeshBuilder.new(17)
	mb.vary = 0.03
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	mb.cyl(Vector3(0, -0.1, 0), 0.5, 1.25, 1.15, 8, Pal.LIMESTONE_DARK, true, 0.0, Pal.LIMESTONE)
	ModelsNature.fluted_shaft(mb, rng, Vector3(0, 0.4, 0), 5.2, 0.85, 0.75, 10, Pal.MARBLE_SHADE, Pal.LIMESTONE, 0.4)
	var pm := MeshInstance3D.new()
	pm.mesh = mb.commit()
	pm.material_override = Materials.lowpoly()
	pm.position = _pillar
	add_child(pm)
	pm.add_to_group("pillar")
	_add_cyl(1.0, 5.6, _pillar + Vector3(0, -0.1, 0), props_body)
	_boulder = Boulder.new()
	_boulder.name = "Boulder"
	add_child(_boulder)
	_boulder.global_position = Vector3(-9.0, FLOOR_Y + 0.02, 4.0)


func _add_cyl(r: float, h: float, base: Vector3, body: StaticBody3D = null) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = base + Vector3(0, h * 0.5, 0)
	(body if body else terrain_body).add_child(cs)


## Paving: concentric rings of slabs (alternating limestone and marble tones) on a rock plinth.
func _build_platform() -> void:
	var mb := MeshBuilder.new(3)
	mb.vary = 0.035
	var rings := 8
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
	# Grout under the slabs and the plinth's side down to the seabed.
	mb.cyl(Vector3(0, SEABED, 0), FLOOR_Y - 0.02 - SEABED, FLOOR_R + 0.6, FLOOR_R, 48, PalExtra.ROCK_WET, false)
	mb.disc(Vector3(0, FLOOR_Y - 0.02, 0), FLOOR_R, 48, Pal.ROCK_DARK)
	# A low marble kerb round the edge, broken where the stairs go down.
	for si in 48:
		var a0 := TAU * float(si) / 48.0
		var a1 := TAU * float(si + 1) / 48.0
		var mid := (a0 + a1) * 0.5
		if absf(wrapf(mid - PI * 0.5, -PI, PI)) < 0.17:
			continue
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var inner := FLOOR_R - 0.45
		var lo := Vector3(0, FLOOR_Y, 0)
		var hi := Vector3(0, FLOOR_Y + 0.3, 0)
		mb.quad(p0 * FLOOR_R + lo, p0 * FLOOR_R + hi, p1 * FLOOR_R + hi, p1 * FLOOR_R + lo, Pal.MARBLE_SHADE) # outer face
		mb.quad(p0 * inner + hi, p0 * inner + lo, p1 * inner + lo, p1 * inner + hi, Pal.MARBLE_SHADE) # inner face
		mb.quad(p0 * inner + hi, p1 * inner + hi, p1 * FLOOR_R + hi, p0 * FLOOR_R + hi, Pal.MARBLE) # top
	var mi := MeshInstance3D.new()
	mi.name = "Paving"
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	add_child(mi)
	# Collision: the platform (a cylinder whose top is the floor) and the kerb (thin boxes round the edge).
	_add_cyl(FLOOR_R, FLOOR_Y - SEABED, Vector3(0, SEABED, 0))
	for si in 48:
		var mid := TAU * (float(si) + 0.5) / 48.0
		if absf(wrapf(mid - PI * 0.5, -PI, PI)) < 0.17:
			continue
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.45, 0.3, TAU * FLOOR_R / 48.0 + 0.05)
		cs.shape = b
		var c := Vector3(cos(mid), 0, sin(mid)) * (FLOOR_R - 0.225) + Vector3(0, FLOOR_Y + 0.15, 0)
		cs.transform = Transform3D(Basis(Vector3.UP, -mid), c)
		props_body.add_child(cs)


## Steps down into the sea on the south side (+Z), so a hero who swims back can climb out.
func _build_stairs() -> void:
	var mb := MeshBuilder.new(9)
	mb.vary = 0.03
	for i in STEPS:
		var top := FLOOR_Y - STEP_RISE * (i + 1)
		var z0 := FLOOR_R - 0.2 + STEP_RUN * i
		var z1 := z0 + STEP_RUN
		mb.block(Vector3(0, SEABED, (z0 + z1) * 0.5), Vector3(STAIRS_HALF_W * 2.0, top - SEABED, z1 - z0), PalExtra.ROCK_MID, Pal.LIMESTONE)
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(STAIRS_HALF_W * 2.0, top - SEABED, z1 - z0)
		cs.shape = b
		cs.position = Vector3(0, (top + SEABED) * 0.5, (z0 + z1) * 0.5)
		terrain_body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Stairs"
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	add_child(mi)


func _build_seabed() -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(400, 2, 400)
	cs.shape = b
	cs.position = Vector3(0, SEABED - 1.0, 0)
	terrain_body.add_child(cs)


func _build_water_texture() -> void:
	var n := 160
	var span := 80.0
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
	if Vector2(x, z).length() <= FLOOR_R:
		return FLOOR_Y
	if absf(x) <= STAIRS_HALF_W and z > FLOOR_R - 0.2:
		var i := int(floor((z - (FLOOR_R - 0.2)) / STEP_RUN))
		if i < STEPS:
			return FLOOR_Y - STEP_RISE * (i + 1)
	return SEABED


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func normal_at(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < sea_level


func player_start() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, FLOOR_Y, 9.0))


func altars() -> Array:
	return []


func spawn_groups() -> Array:
	return []


func cave() -> Dictionary:
	return {"entrance_a": Vector3(-FLOOR_R, FLOOR_Y, 0), "entrance_b": Vector3(FLOOR_R, FLOOR_Y, 0), "boulder": _boulder,
		"arena_center": Vector3(0, FLOOR_Y, 0), "pillars": [_pillar], "lion_spawn": Vector3(0, FLOOR_Y, -10)}


func anchors() -> Array:
	return _anchors


func boat_dock() -> Vector3:
	return Vector3(0, FLOOR_Y, FLOOR_R)


func bounds() -> Rect2:
	return Rect2(-40, -40, 80, 80)
