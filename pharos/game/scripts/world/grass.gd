class_name Grass
extends Node3D
## Instanced meadow: grass tufts (ModelsNature.grass_clump, 10 triangles) and meadow flowers
## (ModelsNature.grass_flowers, 11 triangles) scattered in MultiMesh chunks of 16 x 16 m.
##
## Density, height and colour come from the island's zones (Landscape): a thick, short carpet in the village and
## the open meadows, thick and lush on the gully banks, golden and taller on the wild hills, thinner between the
## vine rows, none on the lanes, plaza, spots, sand, rock faces or terrace risers. Tufts gather in patches
## (cluster noise) with short gaps between them, thicken at the foot of walls, trees and rocks (the props' grass
## mask) and frame each lane with a darker fringe; they stay short near the lanes (<= 0.32 m) and the build
## spots (<= 0.22 m) so gameplay always reads. Flowers come in drifts of one or two species (chamomile, crown
## daisy, poppy, anemone, Silene, borage), as a Cycladic meadow in May.
##
## Each tuft takes the ground colour under it (dark root, lighter tip) and is lit like the smoothed ground, so the
## grass reads as the texture of the ground rather than as clutter. No shadows; waves of wind roll south with the
## meltemi (shaders/grass.gdshader). Far chunks are thinned by camera distance, and the quality setting thins
## everything.

const CHUNK := 16.0
const GRID := 9
const ORIGIN := -72.0
const CAP := 40000
const STRIDE := 20
const ZERO_ZONES := [Landscape.SEA, Landscape.BEACH, Landscape.PLAZA, Landscape.LANE, Landscape.SPOT]
const MESH_H := 0.32 # tallest blade of the tuft mesh (m)

var island: Island
var props: Props
var total := 0
var flowers := 0
var per_zone := {}
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
	_fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_fn.frequency = 1.0
	_fn.seed = 811
	var nature: Script = load("res://scripts/gfx/models_nature.gd")
	_mesh = nature.call("grass_clump", 7)
	_fmesh = nature.call("grass_flowers", 3)
	var bufs: Array = []
	var fbufs: Array = []
	var scale := 1.0
	for attempt in 2:
		bufs.clear()
		fbufs.clear()
		total = 0
		flowers = 0
		per_zone.clear()
		var wheat := _wheat_buffers()
		for cz in GRID:
			for cx in GRID:
				var pair := _chunk(cx, cz, scale, wheat[cz * GRID + cx])
				bufs.append(pair[0])
				fbufs.append(pair[1])
				total += (pair[0] as PackedFloat32Array).size() / STRIDE
				flowers += (pair[1] as PackedFloat32Array).size() / STRIDE
		if total <= CAP:
			break
		scale *= float(CAP) / float(total) * 0.98
	var mat := Materials.grass()
	for k in bufs.size():
		var c := Vector3(ORIGIN + (k % GRID + 0.5) * CHUNK, 0.0, ORIGIN + (k / GRID + 0.5) * CHUNK)
		c.y = maxf(island.height_at(c.x, c.z), 0.0)
		_add_mmi("Grass_%d" % k, _mesh, bufs[k], mat, c)
		_add_mmi("Flowers_%d" % k, _fmesh, fbufs[k], mat, c)
	_apply_quality()
	var parts: Array = []
	for z in per_zone:
		parts.append("%s=%d" % [Landscape.ZONE_NAMES[z], per_zone[z]])
	print("Grass: %d tufts + %d flower sprigs in %d chunks (%d tris), %d ms | %s" % [total, flowers, _chunks.size(), total * 10 + flowers * 11, (Time.get_ticks_usec() - t0) / 1000, ", ".join(parts)])


func _add_mmi(nm: String, mesh: ArrayMesh, buf: PackedFloat32Array, mat: Material, centre: Vector3) -> void:
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
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 84.0
	add_child(mmi)
	_chunks.append(mmi)
	_counts.append(n)
	_centres.append(centre)


## Tuft density (per m2), y-scale range, tip colour, whether it may go to seed, zone id and flower density (drift
## cores, per m2) for a grid cell; [] for no grass.
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
	var fl := 0.5
	match zid:
		Landscape.DUNE:
			p = Landscape.GRASS_DUNE
			tip = Landscape.TIP_DUNE
			seedable = true
			fl = 0.25
		Landscape.GULLY:
			if island.gully_d[i] < 0.9:
				return []
			p = Landscape.GRASS_GULLY
			tip = Landscape.TIP_LUSH
			fl = 1.6
		Landscape.TEMENOS:
			p = Landscape.GRASS_TEMENOS
			tip = Landscape.TIP_LUSH
			fl = 1.4
		Landscape.CLIFF:
			if island.slope[i] >= 0.12:
				return []
			p = Landscape.GRASS_CLIFF
			tip = Landscape.TIP_CLIFF
			seedable = true
			fl = 0.3
		Landscape.VILLAGE:
			p = Landscape.GRASS_VILLAGE
			tip = Landscape.TIP_MEADOW
			fl = 1.0
		Landscape.FIELDS:
			tip = Landscape.TIP_MEADOW
			if wt <= 0.5:
				p = Landscape.GRASS_MEADOW
				seedable = true
				fl = 1.5
			else:
				match int(island.crop[i]):
					Landscape.CROP_VINE:
						p = Landscape.GRASS_VINE
						fl = 0.4
					Landscape.CROP_WHEAT:
						p = Landscape.GRASS_WHEAT
						fl = 1.2
					_:
						p = Landscape.GRASS_OLIVE
						fl = 1.0
		Landscape.WILD:
			seedable = true
			fl = 0.45
	var dens: float = p[0]
	var hw := island.hollow_at(x, z)
	if hw > 0.0:
		dens *= 1.0 + 0.3 * hw
		tip = tip.lerp(Landscape.TIP_LUSH, hw)
		fl *= 1.0 + hw
	return [dens, p[1], p[2], tip, seedable, zid, fl]


## Flower species (palette index 0..7 of the shader) for a drift, by zone: chamomile 0, crown daisy 1, poppy 2,
## anemone violet 3, anemone pink 4, Silene 5, borage 6, horned poppy 7.
func _flower_species(zid: int, u: float, wheat: bool) -> int:
	if wheat:
		return 2 if u < 0.6 else (0 if u < 0.85 else 6)
	match zid:
		Landscape.DUNE:
			return 7 if u < 0.7 else 0
		Landscape.WILD, Landscape.CLIFF:
			return [1, 5, 1, 0, 3, 6][int(u * 5.999)]
		Landscape.GULLY, Landscape.TEMENOS:
			return [3, 4, 0, 2, 3, 6][int(u * 5.999)]
		Landscape.VILLAGE:
			return [0, 1, 0, 2, 5][int(u * 4.999)]
	return [0, 1, 2, 3, 0, 1, 5, 4, 6][int(u * 8.999)]


## Rows of tall, upright stalks with ears for the sown beds Props lays out on the wheat terraces, per chunk
## (they go first in each chunk's buffer, so distance thinning never removes a field).
func _wheat_buffers() -> Array:
	var out: Array = []
	out.resize(GRID * GRID)
	for k in out.size():
		out[k] = PackedFloat32Array()
	if props == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for bed: Dictionary in props.wheat_beds:
		var c: Vector2 = bed["c"]
		var yaw: float = bed["yaw"]
		var hx: float = bed["hx"]
		var hz: float = bed["hz"]
		var barley: bool = bed["barley"]
		var lx := Vector2(cos(yaw), -sin(yaw))
		var lz := Vector2(sin(yaw), cos(yaw))
		var k := clampi(int((c.y - ORIGIN) / CHUNK), 0, GRID - 1) * GRID + clampi(int((c.x - ORIGIN) / CHUNK), 0, GRID - 1)
		var buf: PackedFloat32Array = out[k]
		var tip := Landscape.BARLEY_TIP if barley else Landscape.WHEAT_TIP
		var rows := maxi(2, int(round(hz * 2.0 / 0.42)))
		for r in rows:
			var vz := lerpf(-hz + 0.2, hz - 0.2, float(r) / float(maxi(rows - 1, 1)))
			var vx := -hx + 0.08
			while vx < hx - 0.08:
				var q := c + lx * (vx + rng.randf_range(-0.05, 0.05)) + lz * (vz + rng.randf_range(-0.07, 0.07))
				var y := island.facet_height_at(q.x, q.y)
				# Lower towards the bed's ends and edges, so the field has a soft, rounded silhouette.
				var edge := minf(hx - absf(vx), hz - absf(vz))
				var sy := rng.randf_range(1.7, 2.0) * lerpf(0.78, 1.0, smoothstep(0.0, 0.45, edge))
				var sxz := rng.randf_range(0.42, 0.55)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sxz, sy, sxz))
				var o := buf.size()
				buf.resize(o + STRIDE)
				_write_xf(buf, o, b, q.x, y - 0.02, q.y)
				var kv := rng.randf_range(0.94, 1.06)
				buf[o + 12] = tip.r * kv
				buf[o + 13] = tip.g * kv
				buf[o + 14] = tip.b * kv
				buf[o + 15] = 0.0
				buf[o + 16] = Landscape.STALK_ROOT.r
				buf[o + 17] = Landscape.STALK_ROOT.g
				buf[o + 18] = Landscape.STALK_ROOT.b
				buf[o + 19] = 0.6
				vx += rng.randf_range(0.14, 0.19)
		out[k] = buf
	return out


func _chunk(cx: int, cz: int, dscale: float, pre: PackedFloat32Array = PackedFloat32Array()) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + cx * 31 + cz * 977
	var x0 := ORIGIN + cx * CHUNK
	var z0 := ORIGIN + cz * CHUNK
	var buf := PackedFloat32Array()
	var fbuf := PackedFloat32Array()
	# Wheat fields first (never thinned).
	var n := pre.size() / STRIDE
	var cap := maxi(4096, n * 2)
	var fcap := 512
	buf.resize(cap * STRIDE)
	fbuf.resize(fcap * STRIDE)
	for k in pre.size():
		buf[k] = pre[k]
	if n > 0:
		per_zone[Landscape.FIELDS] = int(per_zone.get(Landscape.FIELDS, 0)) + n
	var nf := 0
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
		if prm.is_empty():
			continue
		var dens: float = prm[0]
		var y0: float = prm[1]
		var y1: float = prm[2]
		var e_c := island.dl[i] - lw
		if e_c >= 0.6 and e_c < 1.8:
			# A darker, denser fringe frames the lane.
			dens = maxf(dens, Landscape.GRASS_FRINGE)
			y0 = 0.85
			y1 = 0.95
		var boost := 0.0
		if props != null:
			boost = props.grass_mask_at(cxw, czw).y
			dens += Landscape.GRASS_SKIRT * boost
		# Patches: clumpy noise, so tufts gather with short gaps between them.
		var cluster := 0.35 + 1.25 * (_vn.get_noise_2d(cxw * 0.42, czw * 0.42) * 0.5 + 0.5)
		var cnt := int(floor(dens * cluster * dscale + rng.randf()))
		var tip: Color = prm[3]
		var seedable: bool = prm[4]
		var zid: int = prm[5]
		var dry := island.dryness[i]
		var gc := island.ground_color_at(cxw, czw)
		var nr := island.normal_at(cxw, czw)
		var up := Basis(Quaternion(Vector3.UP, nr))
		var near_edge := island.dl[i] < lw + 3.2 or island.ds[i] < 3.0 or cxw * cxw + czw * czw < 10.0 * 10.0
		var upright := zid == Landscape.DUNE
		# The green core keeps green tips; the wild ring and the dunes go golden with dryness.
		var golden := zid == Landscape.WILD or zid == Landscape.CLIFF or zid == Landscape.DUNE
		var base_tip := Color(gc.r, gc.g, gc.b).lerp(tip, 0.55).lerp(Landscape.STRAW_TIP, dry * (0.6 if golden else 0.25))
		for k in cnt:
			var px := cxw + rng.randf_range(-0.5, 0.5)
			var pz := czw + rng.randf_range(-0.5, 0.5)
			var e := e_c
			var d_s := 9.0
			if near_edge:
				e = island.lane_dist_at(px, pz) - lw
				if e < 0.6:
					continue
				d_s = island.spot_sd_at(px, pz)
				if d_s < 0.6:
					continue
				if d_s < 2.0 and rng.randf() > smoothstep(0.6, 2.0, d_s):
					continue
				if px * px + pz * pz < 8.4 * 8.4:
					continue
			if props != null:
				var gm := props.grass_mask_at(px, pz)
				if gm.x > 0.0 and rng.randf() < gm.x:
					continue
			var fc := island.facet_color_at(px, pz)
			if fc.a < 0.05:
				continue # sand, rock, risers, paths
			var y := island.facet_height_at(px, pz)
			if y < 0.16:
				continue
			var sy := rng.randf_range(y0, y1)
			if e < 3.0:
				sy = minf(sy, 1.0)
			if d_s < 2.0:
				sy = minf(sy, 0.7)
			var sxz := rng.randf_range(0.85, 1.25) * (0.65 if upright else 1.0)
			var b := up * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sxz, sy, sxz))
			if n >= cap:
				cap *= 2
				buf.resize(cap * STRIDE)
			var o := n * STRIDE
			_write_xf(buf, o, b, px, y - 0.01, pz)
			# Each tuft varies a little in hue and value: some bluer and darker, some yellower.
			var hv := rng.randf()
			var t := base_tip.lerp(Landscape.TIP_COOL, 0.45 * (1.0 - hv) * (1.0 - dry)).lerp(Landscape.STRAW_TIP, 0.25 * hv * hv)
			var rk := rng.randf_range(0.84, 0.9)
			buf[o + 12] = t.r
			buf[o + 13] = t.g
			buf[o + 14] = t.b
			buf[o + 15] = 0.0
			buf[o + 16] = gc.r * rk
			buf[o + 17] = gc.g * rk
			buf[o + 18] = gc.b * rk
			buf[o + 19] = 0.5 if seedable and dry > 0.5 and rng.randf() < 0.55 else 0.0
			n += 1
			per_zone[zid] = int(per_zone.get(zid, 0)) + 1
		# Flowers in drifts: a slow noise decides where the drifts are, a slower one which species.
		var fl: float = prm[6]
		if fl <= 0.0:
			continue
		var drift := smoothstep(0.05, 0.4, _fn.get_noise_2d(cxw * 0.16, czw * 0.16) + 0.3 * boost)
		var fcnt := int(floor(fl * drift * 2.2 * dscale + rng.randf()))
		if fcnt <= 0:
			continue
		var su := clampf(_fn.get_noise_2d(cxw * 0.05 + 70.0, czw * 0.05 - 30.0) * 0.5 + 0.5, 0.0, 0.999)
		var wheat := int(island.crop[i]) == Landscape.CROP_WHEAT and island.terrace_w[i] > 0.5
		for k in fcnt:
			var px := cxw + rng.randf_range(-0.5, 0.5)
			var pz := czw + rng.randf_range(-0.5, 0.5)
			if island.lane_dist_at(px, pz) - lw < 1.0 or island.spot_sd_at(px, pz) < 1.5 or px * px + pz * pz < 9.0 * 9.0:
				continue
			if props != null and props.grass_mask_at(px, pz).x > 0.3:
				continue
			if island.facet_color_at(px, pz).a < 0.3:
				continue
			var y := island.facet_height_at(px, pz)
			if y < 0.3:
				continue
			# Mostly the drift's species, now and then its neighbour.
			var sp := _flower_species(zid, su if rng.randf() < 0.8 else rng.randf() * 0.999, wheat)
			var s2 := rng.randf_range(0.85, 1.2)
			var b := up * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s2, s2 * rng.randf_range(0.8, 1.1), s2))
			if nf >= fcap:
				fcap *= 2
				fbuf.resize(fcap * STRIDE)
			var o := nf * STRIDE
			_write_xf(fbuf, o, b, px, y - 0.01, pz)
			var stem := Color(gc.r, gc.g, gc.b).lerp(Landscape.TIP_LUSH, 0.5)
			fbuf[o + 12] = stem.r
			fbuf[o + 13] = stem.g
			fbuf[o + 14] = stem.b
			fbuf[o + 15] = float(sp) / 7.0
			fbuf[o + 16] = gc.r * 0.8
			fbuf[o + 17] = gc.g * 0.8
			fbuf[o + 18] = gc.b * 0.8
			fbuf[o + 19] = 1.0
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
	_d_t -= delta
	if _d_t <= 0.0:
		_d_t = 0.25
		_update_counts()
