class_name Grass
extends Node3D
## Instanced meadow: grass tufts (ModelsNature.grass_clump, 10 triangles) and meadow flowers
## (ModelsNature.grass_flowers, 11 triangles) scattered in MultiMesh chunks of CHUNK x CHUNK m over the world's
## bounds. Lit like the ground they grow on, wind waves and the hero's wake in shaders/grass.gdshader; chunks fade
## out past ~70 m (visibility range) and far chunks are thinned. No shadows.
##
## Generic port of the PHAROS grass: what grows where comes from the world (duck-typed `src`):
##   grass_params(x, z) -> Array      [] for bare ground, else [tufts per m2, y_scale_min, y_scale_max,
##                                     tip: Color, seedable: bool, flowers per m2]
##   height_at(x, z) -> float, normal_at(x, z) -> Vector3, ground_color_at(x, z) -> Color (rgb ground, a = grassy)
##   bounds() -> Rect2
## Debug: grass=0 builds nothing.

const CHUNK := 16.0
const CELL := 2.0 # grass_params() is sampled every CELL m
const CAP := 60000
const STRIDE := 20
const TIP_COOL := Color("7F9F5C")
const STRAW_TIP := Color("D9C88E")

var src: Object
var total := 0
var flowers := 0
var _chunks: Array[MultiMeshInstance3D] = []
var _counts := PackedInt32Array()
var _centres := PackedVector3Array()
var _mesh: ArrayMesh
var _fmesh: ArrayMesh
var _vn := FastNoiseLite.new()
var _fn := FastNoiseLite.new()
var _quality := -1
var _frac := 1.0
var _q_t := 0.0
var _d_t := 0.0


func build(source: Object) -> void:
	src = source
	if Game.arg("grass", "1") == "0":
		return
	var t0 := Time.get_ticks_usec()
	_vn.noise_type = FastNoiseLite.TYPE_VALUE
	_vn.frequency = 1.0
	_vn.seed = 4517
	_fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_fn.frequency = 1.0
	_fn.seed = 811
	_mesh = ModelsNature.grass_clump(7)
	_fmesh = ModelsNature.grass_flowers(3)
	var b: Rect2 = src.call("bounds")
	var nx := int(ceil(b.size.x / CHUNK))
	var nz := int(ceil(b.size.y / CHUNK))
	var mat := Materials.grass()
	var scale := 1.0
	var bufs: Array = []
	for attempt in 2:
		bufs.clear()
		total = 0
		flowers = 0
		for cz in nz:
			for cx in nx:
				var o := b.position + Vector2(cx * CHUNK, cz * CHUNK)
				var pair := _chunk(o, scale, cx * 977 + cz * 31)
				bufs.append([o, pair[0], pair[1]])
				total += (pair[0] as PackedFloat32Array).size() / STRIDE
				flowers += (pair[1] as PackedFloat32Array).size() / STRIDE
		if total <= CAP:
			break
		scale *= float(CAP) / float(total) * 0.98
	for e in bufs:
		var o: Vector2 = e[0]
		var c := Vector3(o.x + CHUNK * 0.5, 0.0, o.y + CHUNK * 0.5)
		c.y = float(src.call("height_at", c.x, c.z))
		_add_mmi(_mesh, e[1], mat, c)
		_add_mmi(_fmesh, e[2], mat, c)
	_apply_quality()
	print("Grass: %d tufts + %d flowers in %d chunks, %d ms" % [total, flowers, _chunks.size(), (Time.get_ticks_usec() - t0) / 1000])


func _add_mmi(mesh: ArrayMesh, buf: PackedFloat32Array, mat: Material, centre: Vector3) -> void:
	var n := buf.size() / STRIDE
	if n == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 84.0
	add_child(mmi)
	_chunks.append(mmi)
	_counts.append(n)
	_centres.append(centre)


func _chunk(o: Vector2, dscale: float, salt: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + salt
	var buf := PackedFloat32Array()
	var fbuf := PackedFloat32Array()
	var cap := 1024
	var fcap := 256
	buf.resize(cap * STRIDE)
	fbuf.resize(fcap * STRIDE)
	var n := 0
	var nf := 0
	var cells := int(CHUNK / CELL)
	# Cells in random order, so a reduced visible_instance_count thins the grass evenly.
	var order := PackedInt32Array()
	order.resize(cells * cells)
	for k in order.size():
		order[k] = k
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var tmp := order[k]
		order[k] = order[j]
		order[j] = tmp
	for cell in order:
		var cx := o.x + (float(cell % cells) + 0.5) * CELL
		var cz := o.y + (float(cell / cells) + 0.5) * CELL
		var prm: Array = src.call("grass_params", cx, cz)
		if prm.is_empty():
			continue
		var cluster := 0.35 + 1.25 * (_vn.get_noise_2d(cx * 0.42, cz * 0.42) * 0.5 + 0.5)
		var cnt := int(floor(float(prm[0]) * CELL * CELL * cluster * dscale + rng.randf()))
		var tip: Color = prm[3]
		var seedable: bool = prm[4]
		var gc: Color = src.call("ground_color_at", cx, cz)
		var nr: Vector3 = src.call("normal_at", cx, cz)
		var up := Basis(Quaternion(Vector3.UP, nr))
		var base_tip := Color(gc.r, gc.g, gc.b).lerp(tip, 0.55)
		for k in cnt:
			var px := cx + rng.randf_range(-0.5, 0.5) * CELL
			var pz := cz + rng.randf_range(-0.5, 0.5) * CELL
			var y: float = src.call("height_at", px, pz)
			var sy := rng.randf_range(float(prm[1]), float(prm[2]))
			var sxz := rng.randf_range(0.85, 1.25)
			var b := up * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sxz, sy, sxz))
			if n >= cap:
				cap *= 2
				buf.resize(cap * STRIDE)
			var oo := n * STRIDE
			_write_xf(buf, oo, b, px, y - 0.01, pz)
			var hv := rng.randf()
			var t := base_tip.lerp(TIP_COOL, 0.45 * (1.0 - hv)).lerp(STRAW_TIP, 0.25 * hv * hv)
			var rk := rng.randf_range(0.84, 0.9)
			buf[oo + 12] = t.r
			buf[oo + 13] = t.g
			buf[oo + 14] = t.b
			buf[oo + 15] = 0.0
			buf[oo + 16] = gc.r * rk
			buf[oo + 17] = gc.g * rk
			buf[oo + 18] = gc.b * rk
			buf[oo + 19] = 0.5 if seedable and rng.randf() < 0.3 else 0.0
			n += 1
		# Flowers in drifts: a slow noise decides where the drifts are, a slower one which species.
		var fl: float = float(prm[5]) if prm.size() > 5 else 0.0
		if fl <= 0.0:
			continue
		var drift := smoothstep(0.05, 0.4, _fn.get_noise_2d(cx * 0.16, cz * 0.16) + 0.1)
		var fcnt := int(floor(fl * CELL * CELL * drift * dscale + rng.randf()))
		var su := clampf(_fn.get_noise_2d(cx * 0.05 + 70.0, cz * 0.05 - 30.0) * 0.5 + 0.5, 0.0, 0.999)
		for k in fcnt:
			var px := cx + rng.randf_range(-0.5, 0.5) * CELL
			var pz := cz + rng.randf_range(-0.5, 0.5) * CELL
			var y: float = src.call("height_at", px, pz)
			# Mostly the drift's species, now and then another.
			var sp := int((su if rng.randf() < 0.8 else rng.randf()) * 6.999)
			sp = [0, 1, 2, 3, 4, 5, 6][sp]
			var s2 := rng.randf_range(0.85, 1.2)
			var b := up * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s2, s2 * rng.randf_range(0.8, 1.1), s2))
			if nf >= fcap:
				fcap *= 2
				fbuf.resize(fcap * STRIDE)
			var oo := nf * STRIDE
			_write_xf(fbuf, oo, b, px, y - 0.01, pz)
			var stem := Color(gc.r, gc.g, gc.b).lerp(Color("9DB45E"), 0.5)
			fbuf[oo + 12] = stem.r
			fbuf[oo + 13] = stem.g
			fbuf[oo + 14] = stem.b
			fbuf[oo + 15] = float(sp) / 7.0
			fbuf[oo + 16] = gc.r * 0.8
			fbuf[oo + 17] = gc.g * 0.8
			fbuf[oo + 18] = gc.b * 0.8
			fbuf[oo + 19] = 1.0
			nf += 1
	buf.resize(n * STRIDE)
	fbuf.resize(nf * STRIDE)
	return [buf, fbuf]


## MultiMesh buffer transform: 12 floats, row-major 3x4.
static func _write_xf(buf: PackedFloat32Array, o: int, b: Basis, x: float, y: float, z: float) -> void:
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = z


func _apply_quality() -> void:
	var q := int(Settings.get_v("quality"))
	if q == _quality:
		return
	_quality = q
	_frac = 1.0
	if q <= 0:
		_frac = 0.4
	elif q == 1:
		_frac = 0.75
	var mat := Materials.grass()
	mat.set_shader_parameter("fade_near", 34.0 if q <= 0 else 50.0)
	mat.set_shader_parameter("fade_far", 48.0 if q <= 0 else 70.0)
	_update_counts()


## Thins far chunks (instances are stored in random cell order, so cutting the count thins evenly).
func _update_counts() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cp := cam.global_position if cam != null else Vector3(0, 30, 30)
	var far := 48.0 if _quality <= 0 else 70.0
	for k in _chunks.size():
		var d := cp.distance_to(_centres[k])
		var f := _frac * lerpf(1.0, 0.25, smoothstep(28.0, far, d))
		var mm := _chunks[k].multimesh
		var want := -1 if f >= 0.999 else int(_counts[k] * f)
		if mm.visible_instance_count != want:
			mm.visible_instance_count = want


func _process(delta: float) -> void:
	if _chunks.is_empty():
		return
	var mat := Materials.grass()
	var h: Node3D = Game.hero
	if h != null and is_instance_valid(h) and h.is_inside_tree() and h.visible:
		mat.set_shader_parameter("hero_pos", h.global_position)
	else:
		mat.set_shader_parameter("hero_pos", Vector3(0, -100, 0))
	_q_t -= delta
	if _q_t <= 0.0:
		_q_t = 1.0
		_apply_quality()
	_d_t -= delta
	if _d_t <= 0.0:
		_d_t = 0.25
		_update_counts()
