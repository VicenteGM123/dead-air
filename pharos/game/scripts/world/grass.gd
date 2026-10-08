class_name Grass
extends Node3D
## Instanced grass: one 7-triangle clump mesh (5 blades + 2 seed heads) scattered in MultiMesh chunks of
## 16 x 16 m. Density, height and colour come from the island's zones (Landscape): green and short in the
## village, thick in the open meadows and on the gully banks, golden and taller on the wild hills, none on the
## lanes, plaza, spots, sand, rock faces or terrace risers. A darker fringe of grass frames each lane, it stays
## short near the lanes (<= 0.35 m) and the build spots (<= 0.245 m) so gameplay always reads.
##
## Each clump is lit like the terrain facet it grows on (same colour family, same normal), so grass reads as
## texture rather than clutter. No shadows; waves of wind roll south with the meltemi (shaders/grass.gdshader).

const CHUNK := 16.0
const GRID := 9
const ORIGIN := -72.0
const CAP := 24000
const STRIDE := 20
const ZERO_ZONES := [Landscape.SEA, Landscape.BEACH, Landscape.PLAZA, Landscape.LANE, Landscape.SPOT]

var island: Island
var props: Props
var total := 0
var per_zone := {}
var _chunks: Array[MultiMeshInstance3D] = []
var _mesh: ArrayMesh
var _vn := FastNoiseLite.new()
var _quality := -1
var _q_t := 0.0
var _perf := false
var _perf_t := 0.0


func build(isl: Island, pr: Props = null) -> void:
	island = isl
	props = pr
	var args := OS.get_cmdline_user_args()
	_perf = "perf=1" in args
	if "grass=0" in args or "--grass=0" in args:
		return
	var t0 := Time.get_ticks_usec()
	_vn.noise_type = FastNoiseLite.TYPE_VALUE
	_vn.frequency = 1.0
	_vn.seed = 4517
	_mesh = _species_clump()
	if _mesh == null:
		_mesh = _clump_mesh()
	var bufs: Array = []
	var scale := 1.0
	for attempt in 2:
		bufs.clear()
		total = 0
		per_zone.clear()
		for cz in GRID:
			for cx in GRID:
				var b := _chunk(cx, cz, scale)
				bufs.append(b)
				total += b.size() / STRIDE
		if total <= CAP:
			break
		scale *= float(CAP) / float(total) * 0.98
	var mat := Materials.grass()
	for k in bufs.size():
		var buf: PackedFloat32Array = bufs[k]
		var n := buf.size() / STRIDE
		if n == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _mesh
		mm.instance_count = n
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d" % k
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 80.0
		add_child(mmi)
		_chunks.append(mmi)
	_apply_quality()
	var parts: Array = []
	for z in per_zone:
		parts.append("%s=%d" % [Landscape.ZONE_NAMES[z], per_zone[z]])
	print("Grass: %d clumps in %d chunks (%d tris), %d ms | %s" % [total, _chunks.size(), total * 7, (Time.get_ticks_usec() - t0) / 1000, ", ".join(parts)])


## The species file's grass clump, if it has one with the UV layout this shader expects.
func _species_clump() -> ArrayMesh:
	var nature: Script = load("res://scripts/gfx/models_nature.gd")
	for m in nature.get_script_method_list():
		if m["name"] == "grass_clump":
			var mesh: Variant = nature.call("grass_clump", 7)
			if mesh is ArrayMesh and (mesh as ArrayMesh).get_surface_count() > 0:
				var a := (mesh as ArrayMesh).surface_get_arrays(0)
				if a[Mesh.ARRAY_TEX_UV] is PackedVector2Array and (a[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0:
					return mesh
	return null


## One clump: five splayed blades (single triangles, UV.y = height fraction) and two seed heads (UV.x = 1)
## that the shader collapses unless the instance is flagged as gone to seed. Height <= 0.35 m.
func _clump_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var r := RandomNumberGenerator.new()
	r.seed = 31
	var tips: Array[Vector3] = []
	for k in 5:
		var a := TAU * k / 5.0 + r.randf_range(-0.35, 0.35)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var base := out * 0.035
		var h: float = [0.33, 0.25, 0.35, 0.22, 0.29][k]
		var tip := base + out * r.randf_range(0.10, 0.17) + Vector3(0, h, 0)
		var w := 0.048
		# Clockwise from the outside (Godot front face); the material is double sided anyway.
		v.append_array([base - side * w, tip, base + side * w])
		uv.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(0, 0)])
		tips.append(tip)
	for k in [0, 2]:
		var tip: Vector3 = tips[k]
		var dir := Vector3(tip.x, 0, tip.z).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var lo := tip - Vector3(0, 0.075, 0) - dir * 0.02
		var hi := tip + Vector3(0, 0.035, 0) + dir * 0.015
		v.append_array([lo - side * 0.022, hi, lo + side * 0.022])
		uv.append_array([Vector2(1, 0.8), Vector2(1, 1), Vector2(1, 0.8)])
	for i in v.size():
		nrm.append(Vector3.UP)
		col.append(Color.WHITE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Density (clumps / m2), y-scale range, tip colour and whether it may go to seed, for a grid cell.
func _cell_params(i: int, x: float, z: float) -> Array:
	var zid := int(island.zone[i])
	if zid in ZERO_ZONES:
		return []
	if island.slope[i] > 0.24:
		return []
	var wt := island.terrace_w[i]
	if wt > 0.5:
		var q := island.hs[i] / Landscape.TERRACE_STEP
		if q - floorf(q) >= 0.80:
			return [] # riser
	var p: Array = Landscape.GRASS_WILD
	var tip := Landscape.TIP_WILD
	var seedable := false
	match zid:
		Landscape.DUNE:
			p = Landscape.GRASS_DUNE
			tip = Landscape.TIP_DUNE
			seedable = true
		Landscape.GULLY:
			var gd := island.gully_d[i]
			if gd < 0.9:
				return []
			p = Landscape.GRASS_GULLY
			tip = Landscape.TIP_LUSH
		Landscape.TEMENOS:
			p = Landscape.GRASS_TEMENOS
			tip = Landscape.TIP_LUSH
		Landscape.CLIFF:
			if island.slope[i] >= 0.12:
				return []
			p = Landscape.GRASS_CLIFF
			tip = Landscape.TIP_CLIFF
			seedable = true
		Landscape.VILLAGE:
			p = Landscape.GRASS_VILLAGE
			tip = Landscape.TIP_MEADOW
		Landscape.FIELDS:
			tip = Landscape.TIP_MEADOW
			if wt <= 0.5:
				p = Landscape.GRASS_MEADOW
				seedable = true
			else:
				match int(island.crop[i]):
					Landscape.CROP_VINE:
						p = Landscape.GRASS_VINE
					Landscape.CROP_WHEAT:
						p = Landscape.GRASS_WHEAT
					_:
						p = Landscape.GRASS_OLIVE
		Landscape.WILD:
			seedable = true
	var dens: float = p[0]
	var hw := island.hollow_at(x, z)
	if hw > 0.0:
		dens *= 1.0 + 0.3 * hw
		tip = tip.lerp(Landscape.TIP_LUSH, hw)
	return [dens, p[1], p[2], tip, seedable, zid]


func _chunk(cx: int, cz: int, dscale: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + cx * 31 + cz * 977
	var x0 := ORIGIN + cx * CHUNK
	var z0 := ORIGIN + cz * CHUNK
	var buf := PackedFloat32Array()
	var cap := 2048
	buf.resize(cap * STRIDE)
	var n := 0
	# Cells in random order, so a reduced visible_instance_count thins the grass evenly.
	var order := PackedInt32Array()
	order.resize(256)
	for k in 256:
		order[k] = k
	for k in range(255, 0, -1):
		var j := rng.randi() % (k + 1)
		var tmp := order[k]
		order[k] = order[j]
		order[j] = tmp
	var lw := Island.LANE_W
	for cell in order:
		var cxw := x0 + float(cell % 16) + 0.5
		var czw := z0 + float(cell / 16) + 0.5
		var i := island.cell_index(cxw, czw)
		var prm := _cell_params(i, cxw, czw)
		var e_c := island.dl[i] - lw
		var fringe := e_c >= 0.6 and e_c < 1.8 and not prm.is_empty()
		if prm.is_empty():
			continue
		var dens: float = prm[0]
		var y0: float = prm[1]
		var y1: float = prm[2]
		if fringe:
			dens = maxf(dens, 5.5)
			y0 = 0.95
			y1 = 1.0
		if props != null:
			var gmk := props.grass_mask_at(cxw, czw)
			dens += 3.0 * gmk.y
		var cluster := 0.55 + 0.9 * (_vn.get_noise_2d(cxw * 0.45, czw * 0.45) * 0.5 + 0.5)
		var cnt := int(floor(dens * cluster * dscale + rng.randf()))
		if cnt <= 0:
			continue
		var tip: Color = prm[3]
		var seedable: bool = prm[4]
		var zid: int = prm[5]
		var dry := island.dryness[i]
		var seed_flag := 1.0 if seedable and dry > 0.55 else 0.0
		var upright := zid == Landscape.DUNE
		var seeds := [Vector2(cxw + rng.randf_range(-0.5, 0.5), czw + rng.randf_range(-0.5, 0.5))]
		if cnt > 2:
			seeds.append(Vector2(cxw + rng.randf_range(-0.5, 0.5), czw + rng.randf_range(-0.5, 0.5)))
		for k in cnt:
			var sp: Vector2 = seeds[k % seeds.size()]
			var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.35
			var px := sp.x + off.x
			var pz := sp.y + off.y
			var d_l := island.lane_dist_at(px, pz)
			var e := d_l - lw
			if e < 0.6:
				continue
			var d_s := island.spot_sd_at(px, pz)
			if d_s < 0.6:
				continue
			if d_s < 2.0 and rng.randf() > smoothstep(0.6, 2.0, d_s):
				continue
			if px * px + pz * pz < 8.3 * 8.3:
				continue
			if props != null:
				var gm := props.grass_mask_at(px, pz)
				if gm.x > 0.0 and rng.randf() < gm.x:
					continue
			var fc := island.facet_color_at(px, pz)
			if fc.a < 0.05:
				continue # sand, rock, risers, paths
			var nr := island.facet_normal_at(px, pz)
			if nr.y < 0.76:
				continue
			var y := island.facet_height_at(px, pz)
			if y < 0.16:
				continue
			var sy := rng.randf_range(y0, y1)
			if e < 3.0:
				sy = minf(sy, 1.0)
			if d_s < 2.0:
				sy = minf(sy, 0.70)
			sy = minf(sy, 1.2)
			var sxz := rng.randf_range(0.85, 1.2) * (0.6 if upright else 1.0)
			var b := Basis(Quaternion(Vector3.UP, nr)) * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sxz, sy, sxz))
			if n >= cap:
				cap *= 2
				buf.resize(cap * STRIDE)
			var o := n * STRIDE
			buf[o] = b.x.x
			buf[o + 1] = b.y.x
			buf[o + 2] = b.z.x
			buf[o + 3] = px
			buf[o + 4] = b.x.y
			buf[o + 5] = b.y.y
			buf[o + 6] = b.z.y
			buf[o + 7] = y - 0.02
			buf[o + 8] = b.x.z
			buf[o + 9] = b.y.z
			buf[o + 10] = b.z.z
			buf[o + 11] = pz
			var t := Color(fc.r, fc.g, fc.b).lerp(tip, 0.55).lerp(Landscape.STRAW_TIP, dry * 0.65)
			var rk := 0.92 if upright else 0.88
			buf[o + 12] = t.r
			buf[o + 13] = t.g
			buf[o + 14] = t.b
			buf[o + 15] = 1.0
			buf[o + 16] = fc.r * rk
			buf[o + 17] = fc.g * rk
			buf[o + 18] = fc.b * rk
			buf[o + 19] = seed_flag
			n += 1
			per_zone[zid] = int(per_zone.get(zid, 0)) + 1
	buf.resize(n * STRIDE)
	return buf


func _apply_quality() -> void:
	var q := int(Settings.get_v("quality"))
	if q == _quality:
		return
	_quality = q
	var frac := 1.0
	if q <= 0:
		frac = 0.45
	elif q == 1:
		frac = 0.75
	for mmi in _chunks:
		var mm := mmi.multimesh
		mm.visible_instance_count = -1 if frac >= 1.0 else int(mm.instance_count * frac)
	var mat := Materials.grass()
	mat.set_shader_parameter("fade_near", 34.0 if q <= 0 else 52.0)
	mat.set_shader_parameter("fade_far", 48.0 if q <= 0 else 72.0)


func _process(delta: float) -> void:
	if _perf:
		_perf_t += delta
		if _perf_t >= 2.0:
			_perf_t = 0.0
			var vis := 0
			for mmi in _chunks:
				if mmi.is_visible_in_tree():
					vis += 1
			print("perf: %.1f fps, %d draw calls, %d primitives, %d objects, %d grass chunks" % [Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), vis])
	if _chunks.is_empty():
		return
	var mat := Materials.grass()
	var h: Node3D = Game.hero
	if h != null and is_instance_valid(h) and h.visible:
		mat.set_shader_parameter("hero_pos", h.global_position)
	else:
		mat.set_shader_parameter("hero_pos", Vector3(0, -100, 0))
	_q_t -= delta
	if _q_t <= 0.0:
		_q_t = 1.0
		_apply_quality()
