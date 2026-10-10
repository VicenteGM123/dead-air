class_name AmbientBugs
extends Node3D
## Butterflies (day) and fireflies (night), each drawn as a single MultiMesh updated from code.
## Butterflies flutter along looping paths over the flower patches Props scattered (meadows, hollows, the
## sanctuary) and the house gardens, landing now and then with their wings folded. Fireflies drift slowly round
## the trees of the village ring, pulsing a soft warm green.

const BUTTERFLIES := 10
const FIREFLIES := 40
const FF_CLUSTERS := 13

var amb: Ambient
var rng := RandomNumberGenerator.new()
var t := 0.0
var day_k := 1.0
var night_k := 0.0

var bf_mm: MultiMesh
var bf_mmi: MultiMeshInstance3D
var bf_anchor := PackedVector3Array()
var bf_par := PackedFloat32Array() # 8 per butterfly: 4 frequencies, 4 phases
var bf_clock := PackedFloat32Array()
var bf_land := PackedFloat32Array() # 0 flying .. 1 landed
var bf_timer := PackedFloat32Array()
var bf_landed := PackedByteArray()
var bf_pos := PackedVector3Array()
var bf_yaw := PackedFloat32Array()
var bf_size := PackedFloat32Array()
var bf_lift := PackedFloat32Array() # 0 .. 1 while crossing over a low prop

var ff_mm: MultiMesh
var ff_mmi: MultiMeshInstance3D
var ff_anchor := PackedVector3Array()
var ff_par := PackedFloat32Array() # 8 per firefly


func setup(ambient: Ambient) -> void:
	amb = ambient
	rng.seed = ambient.rng.randi()
	_setup_butterflies()
	_setup_fireflies()
	day_k = 1.0 - smoothstep(0.15, 0.5, amb.night)
	night_k = smoothstep(0.45, 0.85, amb.night)
	_update(0.0)


# --- placement ---------------------------------------------------------------------------------------------

func _meadow_ok(p: Vector3) -> bool:
	var h := amb.island.height_at(p.x, p.z)
	if h < 0.7 or not amb.free_at(p.x, p.z, 0.3, 0.6):
		return false
	var ang := Ambient.angle_of(p.x, p.z)
	return amb.island.coast_at(ang) - Vector2(p.x, p.z).length() > 4.0


## Random valid point around `c` between r0 and r1 metres (or INF).
func _around(c: Vector3, r0: float, r1: float) -> Vector3:
	for tries in 20:
		var a := rng.randf() * TAU
		var p := amb.ground(c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(r0, r1))
		if _meadow_ok(p):
			return p
	return Vector3.INF


func _random_meadow(rmin: float, rmax: float) -> Vector3:
	return _around(amb.focus, rmin, rmax)


func _spots(type: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for sp in amb.island.spots:
		if sp["type"] == type:
			out.append(sp["pos"])
	return out


## Up to n points from `pts`, at least `gap` metres apart, preferring those within `near` metres of the
## lighthouse (where the player spends the day).
func _spread(pts: PackedVector3Array, n: int, gap: float, near: float) -> Array[Vector3]:
	var order := range(pts.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out: Array[Vector3] = []
	for pass_i in 2:
		for k in order:
			if out.size() >= n:
				return out
			var p := pts[k]
			if pass_i == 0 and Vector2(p.x - amb.focus.x, p.z - amb.focus.z).length() > near:
				continue
			var ok := true
			for q in out:
				if Vector2(p.x - q.x, p.z - q.z).length() < gap:
					ok = false
					break
			if ok:
				out.append(p)
	return out


func _setup_butterflies() -> void:
	# Over the flower patches scattered by Props (those clear of the build spots: a butterfly's loops reach 3.3 m
	# from its patch); farms, gardens and meadows if there are none.
	var open := PackedVector3Array()
	for f in amb.flowers:
		open.append(f)
	var flowers := _spread(open, BUTTERFLIES, 6.0, 70.0)
	var farms := _spots("farm")
	var houses := _spots("house")
	for i in BUTTERFLIES:
		var p := Vector3.INF
		if i < flowers.size():
			p = amb.ground(flowers[i])
		elif i < 3 and i < farms.size():
			p = _around(farms[i], 5.5, 9.0)
		elif i < 6 and houses.size() > 0:
			p = _around(houses[(i - 3) % houses.size()], 3.8, 7.0)
		if not p.is_finite():
			p = _random_meadow(12.0, 40.0)
		if not p.is_finite():
			p = amb.ground(Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(10, 25)))
		bf_anchor.append(p)
		for k in 4:
			bf_par.append(rng.randf_range(0.18, 0.42) * (1.0 if k < 2 else 1.7))
		for k in 4:
			bf_par.append(rng.randf() * TAU)
		bf_clock.append(rng.randf() * 100.0)
		bf_land.append(0.0)
		bf_timer.append(rng.randf_range(3.0, 14.0))
		bf_landed.append(0)
		bf_pos.append(p)
		bf_yaw.append(rng.randf() * TAU)
		bf_size.append(rng.randf_range(1.0, 1.25)) # a touch larger than life, like the cats
		bf_lift.append(0.0)
	bf_mm = MultiMesh.new()
	bf_mm.transform_format = MultiMesh.TRANSFORM_3D
	bf_mm.use_colors = true
	bf_mm.mesh = ModelsAnimals.butterfly_wing()
	bf_mm.instance_count = BUTTERFLIES * 2
	for i in BUTTERFLIES:
		var c: Color = ModelsAnimals.BUTTERFLY_COLORS[rng.randi() % ModelsAnimals.BUTTERFLY_COLORS.size()]
		bf_mm.set_instance_color(i * 2, c)
		bf_mm.set_instance_color(i * 2 + 1, c)
	bf_mmi = MultiMeshInstance3D.new()
	bf_mmi.name = "Butterflies"
	bf_mmi.multimesh = bf_mm
	bf_mmi.material_override = Materials.lowpoly()
	bf_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bf_mmi.custom_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 40, 240))
	add_child(bf_mmi)


func _setup_fireflies() -> void:
	# Clusters round the trees scattered by Props (nearest the lighthouse first), then the farms, the house
	# gardens and open meadows.
	var centers: Array[Vector3] = _spread(amb.trees, FF_CLUSTERS, 6.0, 28.0)
	for f in _spots("farm"):
		if centers.size() >= FF_CLUSTERS:
			break
		centers.append(f)
	var houses := _spots("house")
	for i in mini(2, houses.size()):
		if centers.size() >= FF_CLUSTERS:
			break
		centers.append(houses[i])
	while centers.size() < FF_CLUSTERS:
		var m := _random_meadow(12.0, 38.0)
		if not m.is_finite():
			break
		centers.append(m)
	for i in FIREFLIES:
		var c := amb.ground(centers[i % centers.size()]) if centers.size() > 0 else Vector3.ZERO
		var p := _around(c, 1.0, 4.5)
		if not p.is_finite():
			p = amb.ground(c + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)))
		p.y += rng.randf_range(0.5, 2.1)
		ff_anchor.append(p)
		for k in 4:
			ff_par.append(rng.randf_range(0.12, 0.38))
		ff_par.append(rng.randf() * TAU)
		ff_par.append(rng.randf() * TAU)
		ff_par.append(rng.randf_range(0.7, 1.6)) # pulse speed
		ff_par.append(rng.randf() * TAU) # pulse phase
	ff_mm = MultiMesh.new()
	ff_mm.transform_format = MultiMesh.TRANSFORM_3D
	ff_mm.use_colors = true
	ff_mm.mesh = ModelsAnimals.quad_mesh()
	ff_mm.instance_count = FIREFLIES
	ff_mmi = MultiMeshInstance3D.new()
	ff_mmi.name = "Fireflies"
	ff_mmi.multimesh = ff_mm
	ff_mmi.material_override = Materials.glow_add()
	ff_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ff_mmi.custom_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 40, 240))
	add_child(ff_mmi)


# --- update ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update(minf(delta, 0.1))


func _update(dt: float) -> void:
	t += dt
	day_k = move_toward(day_k, 1.0 - smoothstep(0.15, 0.5, amb.night), dt * 0.25)
	night_k = move_toward(night_k, smoothstep(0.45, 0.85, amb.night), dt * 0.2)
	bf_mmi.visible = day_k > 0.001
	ff_mmi.visible = night_k > 0.001
	if bf_mmi.visible:
		_update_butterflies(dt)
	if ff_mmi.visible:
		_update_fireflies()


func _update_butterflies(dt: float) -> void:
	var isl := amb.island
	for i in BUTTERFLIES:
		var j := i * 8
		# Land now and then (only on dry ground), take off again later.
		bf_timer[i] -= dt
		if bf_timer[i] <= 0.0:
			if bf_landed[i] == 1:
				bf_landed[i] = 0
				bf_timer[i] = rng.randf_range(7.0, 16.0)
			else:
				var gp := bf_pos[i]
				if isl.height_at(gp.x, gp.z) > 0.5 and bf_lift[i] < 0.05:
					bf_landed[i] = 1
					bf_timer[i] = rng.randf_range(2.5, 6.0)
				else:
					bf_timer[i] = 2.0
		bf_land[i] = move_toward(bf_land[i], float(bf_landed[i]), dt * 0.9)
		var land := bf_land[i] * bf_land[i] * (3.0 - 2.0 * bf_land[i])
		bf_clock[i] += dt * (1.0 - land)
		var c := bf_clock[i]
		var a := bf_anchor[i]
		var x := a.x + sin(c * bf_par[j] + bf_par[j + 4]) * 2.4 + sin(c * bf_par[j + 2] + bf_par[j + 6]) * 0.9
		var z := a.z + cos(c * bf_par[j + 1] + bf_par[j + 5]) * 2.4 + sin(c * bf_par[j + 3] + bf_par[j + 7]) * 0.9
		var gh := isl.height_at(x, z)
		# Over a shrub, a wall, a vine row or the wheat the butterfly rises clear of it.
		var over := 1.0 if (bf_landed[i] == 0 and amb.low_prop_at(x, z, 0.6)) else 0.0
		bf_lift[i] = move_toward(bf_lift[i], over, dt * 1.6)
		var fly := 0.8 + 0.35 * sin(c * 0.8 + bf_par[j + 4]) + 0.09 * sin(t * 6.5 + bf_par[j + 5]) + 0.95 * bf_lift[i]
		var p := Vector3(x, gh + lerpf(fly, 0.05, land), z)
		var v := p - bf_pos[i]
		if v.x * v.x + v.z * v.z > 1e-7:
			bf_yaw[i] = lerp_angle(bf_yaw[i], atan2(v.x, v.z), 1.0 - exp(-dt * 8.0))
		bf_pos[i] = p
		var flap := ModelsAnimals.butterfly_flap(t + bf_par[j + 6])
		var rest := 1.25 - 0.55 * smoothstep(0.6, 1.0, sin(t * 1.3 + bf_par[j + 7]) * 0.5 + 0.5)
		var ang := lerpf(flap, rest, land)
		var s := bf_size[i] * day_k
		var yb := Basis(Vector3.UP, bf_yaw[i]) * Basis(Vector3.RIGHT, -0.15 * (1.0 - land))
		bf_mm.set_instance_transform(i * 2, Transform3D(yb * Basis(Vector3.BACK, ang) * Basis.from_scale(Vector3.ONE * s), p))
		bf_mm.set_instance_transform(i * 2 + 1, Transform3D(yb * Basis(Vector3.BACK, PI - ang) * Basis.from_scale(Vector3.ONE * s), p))


func _update_fireflies() -> void:
	var col := ModelsAnimals.FIREFLY
	for i in FIREFLIES:
		var j := i * 8
		var a := ff_anchor[i]
		var p := a + Vector3(
			sin(t * ff_par[j] + ff_par[j + 4]) * 1.3 + sin(t * ff_par[j + 2] * 2.1 + ff_par[j + 5]) * 0.5,
			sin(t * ff_par[j + 1] * 1.4 + ff_par[j + 5]) * 0.35,
			cos(t * ff_par[j + 1] + ff_par[j + 4]) * 1.3 + sin(t * ff_par[j + 3] * 1.9 + ff_par[j + 4]) * 0.5)
		var pulse := sin(t * ff_par[j + 6] + ff_par[j + 7]) * 0.5 + 0.5
		var glow := pulse * pulse
		var inten := night_k * (0.32 + 1.3 * glow)
		var s := 0.55 + 0.42 * glow
		ff_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), p))
		ff_mm.set_instance_color(i, Color(col.r, col.g, col.b, inten))
