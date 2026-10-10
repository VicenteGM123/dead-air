extends RefCounted
## The Lion's cave inside the ridge massif. The terrain already carved a flat-floored crater (the arena, 27 m
## across) and two tunnels to the mouths; this closes them into a cave:
##   - the lid: a solid rock dome over the crater whose top is flush with the mesa round it (lit like the mesa)
##     and whose underside is dark cave stone; three glowing cracks pour shafts of light onto the floor;
##   - the tunnel plugs: rock that roofs each tunnel and fills the slot above it back up to the massif's surface;
##   - a rock arch framing each mouth (its jambs hide the carve's walls). Mouth A, the main way in, is 6.6 m wide;
##     mouth B, the back way, is a 2.1 m crack: the boulder (2.6 m across) cannot pass it, so dragged against the
##     arch it seals the cave;
##   - five flowstone pillars from floor to ceiling (the lion is stunned against them), stalagmites along the
##     walls (never in the middle: the floor stays readable), bones in the lion's corner;
##   - warm light: a soft glow in the middle and the three shafts (switched on only while the camera is near,
##     see set_camera());
##   - the boulder on the apron of mouth B, beside the crack, on flat open ground.
## Collision (layer 1): trimesh for the lid, the plugs and the arches; cylinders for pillars and stalagmites.

const L := preload("res://scripts/world/nemea_layout.gd")
const LID_R := 18.2
## Mouth arches: [opening half width, spring height, apex height] (above the floor).
const ARCH_A := [3.3, 3.8, 6.7]
const ARCH_B := [1.05, 2.6, 4.3]
const LIGHTS_ON_DIST := 46.0

var world: Node3D
var t: RefCounted
var props: RefCounted
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var pillars: Array[Vector3] = []
var boulder: Node3D = null
var info := {}
var tris := 0
## The cave's lights (enabled near the cave only).
var lights: Array[Light3D] = []
## Where each mouth's arch stands: {a: [centre on the floor, outward dir], b: ...}.
var mouths := {}
var _n := FastNoiseLite.new()
var _rim := PackedFloat32Array() # mesa height round the lid, per 5 degrees
var _rim_mean := 0.0
var _lights_on := true


func build(w: Node3D, terrain: RefCounted, pr: RefCounted) -> void:
	world = w
	t = terrain
	props = pr
	rng.seed = 6061
	_n.seed = 31
	_n.frequency = 0.18
	body = StaticBody3D.new()
	body.name = "CaveBody"
	body.collision_layer = 1
	body.collision_mask = 0
	world.add_child(body)
	_rim_table()
	_lid()
	_spires()
	_tunnel(L.MOUTH_A, L.TUNNEL_HW, L.TUNNEL_H, 1)
	_tunnel(L.MOUTH_B, L.TUNNEL_B_HW, L.TUNNEL_B_H, 2)
	_pillars()
	_floor_details()
	_light_shafts()
	_boulder()
	var c := Vector3(L.CAVE_C.x, L.CAVE_FLOOR, L.CAVE_C.y)
	var ma: Array = mouths["a"]
	var mb: Array = mouths["b"]
	info = {
		"entrance_a": _floor_at(ma[0]),
		"entrance_b": _floor_at(mb[0]),
		"boulder": boulder,
		"arena_center": c,
		"pillars": pillars,
		"lion_spawn": c + Vector3(0, 0, -6.5),
		# Extras for the encounter: the outward direction of each mouth and the arena's floor radius.
		"dir_a": ma[1],
		"dir_b": mb[1],
		"arena_radius": L.CAVE_R,
	}


func _floor_at(p: Vector3) -> Vector3:
	return Vector3(p.x, t.height_at(p.x, p.z), p.z)


## Switches the cave lights on while the camera is within LIGHTS_ON_DIST of the arena (World calls it per frame).
func set_camera(cam_pos: Vector3) -> void:
	var on := Vector2(cam_pos.x - L.CAVE_C.x, cam_pos.z - L.CAVE_C.y).length() < LIGHTS_ON_DIST
	if on == _lights_on:
		return
	_lights_on = on
	for l in lights:
		l.visible = on


func _add_mesh(m: ArrayMesh, name: String, collide: bool, shadow: bool = true, rock: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	if rock:
		# Rock surfaces shaded like the cliffs round them (terrain material: strata on steep faces, the cave's
		# darkness from the ground map). Vertex alpha 0 = no grass tint.
		var arrays := m.surface_get_arrays(0)
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in cols.size():
			cols[i].a = 0.0
		arrays[Mesh.ARRAY_COLOR] = cols
		m = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = m
		mi.material_override = Materials.terrain()
	else:
		mi.mesh = m
		mi.material_override = Materials.lowpoly()
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.shape = m.create_trimesh_shape()
		body.add_child(cs)
	for s in m.get_surface_count():
		tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return mi


func _cyl(r: float, h: float, base: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	cs.position = base + Vector3(0, h * 0.5, 0)
	body.add_child(cs)


## Quad whose face looks along `want` (vertex order fixed up as needed).
static func _qn(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(want) < 0.0:
		mb.quad(a, d, c, b, col)
	else:
		mb.quad(a, b, c, d, col)


# --- lid ---------------------------------------------------------------------------------------------------

## Height of the lid's underside at distance r from the arena centre.
func lid_under(r: float, a: float) -> float:
	var k := clampf(r / LID_R, 0.0, 1.0)
	return L.CAVE_FLOOR + L.LID_EDGE + (L.LID_TOP - L.LID_EDGE) * (1.0 - k * k) + _n.get_noise_2d(cos(a) * r, sin(a) * r) * 0.7


## The mesa's height just outside the lid, every 5 degrees (the tunnels' slots are bridged: the plugs fill them),
## smoothed round the ring.
func _rim_table() -> void:
	var c := L.CAVE_C
	var raw := PackedFloat32Array()
	raw.resize(72)
	var floor_min := L.CAVE_FLOOR + L.LID_TOP + 4.0
	for j in 72:
		var a := TAU * float(j) / 72.0
		var best := -INF
		for dr in [1.5, 3.0, 4.5]:
			var q := c + Vector2(cos(a), sin(a)) * (LID_R + float(dr))
			best = maxf(best, t.height_at(q.x, q.y))
		raw[j] = maxf(best, floor_min)
	_rim.resize(72)
	_rim_mean = 0.0
	for j in 72:
		var acc := 0.0
		for k in range(-3, 4):
			acc += raw[posmod(j + k, 72)]
		_rim[j] = acc / 7.0
		_rim_mean += _rim[j] / 72.0


func _rim_at(a: float) -> float:
	var f := fposmod(a, TAU) / TAU * 72.0
	var j := int(f) % 72
	return lerpf(_rim[j], _rim[(j + 1) % 72], f - floorf(f))


## Height of the lid's top (flush with the mesa at its rim, a low dome in the middle).
func lid_top(r: float, a: float) -> float:
	var k := clampf(r / LID_R, 0.0, 1.0)
	var y := lerpf(_rim_mean + 1.4, _rim_at(a) + 0.2, k * k) + _n.get_noise_2d(cos(a) * r * 0.7 + 50.0, sin(a) * r * 0.7) * 0.6
	return maxf(y, lid_under(r, a) + 2.5)


func _lid() -> void:
	var c := L.CAVE_C
	var nr := 12
	var ns := 48
	var under_mb := MeshBuilder.new(901)
	under_mb.vary = 0.04
	var top_mb := MeshBuilder.new(902)
	top_mb.vary = 0.03
	var under: Array = []
	var over: Array = []
	var top_cols: Array = []
	for k in nr + 1:
		var r := (LID_R + 0.6) * float(k) / nr
		var ru: Array[Vector3] = []
		var ro: Array[Vector3] = []
		var rc: Array[Color] = []
		for j in ns:
			var a := TAU * float(j) / ns
			var x := c.x + cos(a) * r
			var z := c.y + sin(a) * r
			ru.append(Vector3(x, lid_under(minf(r, LID_R), a), z))
			ro.append(Vector3(x, lid_top(r, a), z))
			# The top takes the mesa's colour just outside the rim (so the seam disappears).
			var q := c + Vector2(cos(a), sin(a)) * (LID_R + 3.0)
			var tc: Color = t.color_at(q.x, q.y)
			rc.append(Color(tc.r, tc.g, tc.b).lerp(ModelsNature.LIME, 0.25 + 0.2 * (float((k * 7 + j * 3) % 5) / 4.0)))
		under.append(ru)
		over.append(ro)
		top_cols.append(rc)
	for k in nr:
		for j in ns:
			var j2 := (j + 1) % ns
			var a0: Vector3 = under[k][j]
			var a1: Vector3 = under[k][j2]
			var b0: Vector3 = under[k + 1][j]
			var b1: Vector3 = under[k + 1][j2]
			var shade := ModelsNature.CAVE_ROCK_LOW if (k + j) % 3 != 0 else ModelsNature.CAVE_ROCK_LOW.lerp(ModelsNature.CAVE_ROCK, 0.4)
			_qn(under_mb, a0, b0, b1, a1, Vector3.DOWN, shade)
			var o0: Vector3 = over[k][j]
			var o1: Vector3 = over[k][j2]
			var p0: Vector3 = over[k + 1][j]
			var p1: Vector3 = over[k + 1][j2]
			_qn(top_mb, o0, o1, p1, p0, Vector3.UP, top_cols[k][j])
	# The rim wall between the underside and the top (sunk in the crater wall; closes the shell).
	for j in ns:
		var j2 := (j + 1) % ns
		var a := TAU * (float(j) + 0.5) / ns
		_qn(under_mb, under[nr][j], under[nr][j2], over[nr][j2], over[nr][j], Vector3(cos(a), 0, sin(a)), ModelsNature.CAVE_ROCK_LOW)
	# Stalactites hanging from the ceiling (away from the pillars' heads).
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, LID_R - 3.0)
		var p := Vector3(c.x + cos(a) * r, lid_under(r, a) + 0.4, c.y + sin(a) * r)
		var len := rng.randf_range(0.8, 2.4)
		under_mb.push(Transform3D(Basis(Vector3.RIGHT, PI), p))
		under_mb.cyl(Vector3.ZERO, len, rng.randf_range(0.25, 0.5), 0.0, 5, ModelsNature.CAVE_ROCK, false, rng.randf() * TAU)
		under_mb.pop()
	_add_mesh(under_mb.commit(), "CaveLidUnder", true, true, true)
	_add_mesh(top_mb.commit(), "CaveLidTop", true, true, false)


## Top of the rock at (x, z): the mesa, or the lid over the crater.
func surface_at(x: float, z: float) -> float:
	var y: float = t.height_at(x, z)
	var d := Vector2(x - L.CAVE_C.x, z - L.CAVE_C.y)
	if d.length() < LID_R + 0.6:
		y = maxf(y, lid_top(d.length(), d.angle()))
	return y


## The crest spires (L.SPIRES): the ridge's crown, seen from the village and the sea. One static mesh, a
## cylinder each for the camera and the chain.
func _spires() -> void:
	var mb := MeshBuilder.new(970)
	mb.vary = 0.04
	for sp in L.SPIRES:
		var p2: Vector2 = sp[0]
		var h: float = sp[1]
		var r: float = sp[2]
		var y := INF
		for k in 7:
			var a := TAU * float(k) / 6.0
			var q := p2 + (Vector2(cos(a), sin(a)) * r * 0.8 if k < 6 else Vector2.ZERO)
			y = minf(y, surface_at(q.x, q.y))
		var base := Vector3(p2.x, y, p2.y)
		mb.push(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), base))
		ModelsNature.add_spire(mb, rng, r, h)
		mb.pop()
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r * 0.75
		cy.height = h * 0.8 + 2.5
		cs.shape = cy
		cs.position = base + Vector3(0, cy.height * 0.5 - 2.5, 0)
		body.add_child(cs)
	_add_mesh(mb.commit(), "CrestSpires", false)


# --- tunnels -------------------------------------------------------------------------------------------------

## Rock plug over a tunnel: roofs it at floor + h and fills the slot the carve left up to the massif's surface
## (its top lit like the mesa, its underside dark like the cave), stalactites under it, then the mouth's arch.
func _tunnel(mouth: Vector2, hw: float, h: float, which: int) -> void:
	var c := L.CAVE_C
	var dir := (mouth - c).normalized()
	var side := Vector2(-dir.y, dir.x)
	var total := c.distance_to(mouth) + 3.0
	var fl := L.CAVE_FLOOR
	var wide := hw + 3.6
	# Where the roof starts at the mouth: the first point (walking in) where both side walls stand above the roof.
	var s_mouth := total
	var s := total
	while s > L.CAVE_R + 2.0:
		var p := c + dir * s
		var ql := p + side * (hw + 2.6)
		var qr := p - side * (hw + 2.6)
		if t.height_at(ql.x, ql.y) > fl + h + 1.2 and t.height_at(qr.x, qr.y) > fl + h + 1.2:
			s_mouth = s
			break
		s -= 0.5
	var s_in := L.CAVE_R - 0.6
	var under_mb := MeshBuilder.new(910 + which)
	under_mb.vary = 0.04
	var top_mb := MeshBuilder.new(915 + which)
	top_mb.vary = 0.03
	var rows: Array = []
	var n := maxi(2, int(ceil((s_mouth - s_in) / 1.0)))
	for k in n + 1:
		var sk := lerpf(s_in, s_mouth, float(k) / n)
		var p := c + dir * sk
		var row: Array[Vector3] = []
		# Underside points across the width (flat roof, a little lumpy), then the top following the terrain.
		for u in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var q: Vector2 = p + side * (wide * float(u))
			var yu := fl + h + _n.get_noise_2d(q.x * 1.3, q.y * 1.3) * 0.35
			row.append(Vector3(q.x, yu, q.y))
		var tl: Vector2 = p - side * wide
		var tr: Vector2 = p + side * wide
		var y_l: float = maxf(t.height_at(tl.x, tl.y), fl + h + 1.6) + 0.35
		var y_r: float = maxf(t.height_at(tr.x, tr.y), fl + h + 1.6) + 0.35
		var y_c := maxf((y_l + y_r) * 0.5, fl + h + 2.2)
		if sk < LID_R + 1.0:
			var a := dir.angle()
			var yl := lid_top(sk, a)
			y_l = maxf(y_l, yl)
			y_r = maxf(y_r, yl)
			y_c = maxf(y_c, yl)
		# Near the mouth the plug's top leans back like the cliff (a cleft above the cave mouth).
		var lean := fl + h + 1.8 + (s_mouth - sk) * 2.6
		y_l = minf(y_l, lean)
		y_r = minf(y_r, lean)
		y_c = minf(y_c, lean)
		var tops := [y_l, y_c, y_r]
		for ui in 3:
			var q2: Vector2 = p + side * (wide * float(ui - 1))
			row.append(Vector3(q2.x, float(tops[ui]) + _n.get_noise_2d(q2.x * 0.8, q2.y * 0.8) * 0.4, q2.y))
		rows.append(row)
	var roof_col := ModelsNature.CAVE_ROCK_LOW
	for k in n:
		var r0: Array = rows[k]
		var r1: Array = rows[k + 1]
		for u in 4:
			_qn(under_mb, r0[u], r1[u], r1[u + 1], r0[u + 1], Vector3.DOWN, roof_col if (k + u) % 2 == 0 else roof_col.lerp(ModelsNature.CAVE_ROCK, 0.3))
		for u in 2:
			var q3: Vector3 = r0[5 + u]
			var tc: Color = t.color_at(q3.x + side.x * wide * 1.6, q3.z + side.y * wide * 1.6)
			_qn(top_mb, r0[5 + u], r0[6 + u], r1[6 + u], r1[5 + u], Vector3.UP, Color(tc.r, tc.g, tc.b).lerp(ModelsNature.LIME, 0.35))
		# sides (sunk in the walls, closing the plug)
		var sd3 := Vector3(side.x, 0, side.y)
		_qn(under_mb, r0[0], r0[5], r1[5], r1[0], -sd3, roof_col)
		_qn(under_mb, r0[4], r1[4], r1[7], r0[7], sd3, roof_col)
	# End faces: over the mouth (faces out, behind the arch) and above the arena opening (faces in).
	var e0: Array = rows[0]
	var e1: Array = rows[n]
	var d3 := Vector3(dir.x, 0, dir.y)
	_qn(under_mb, e0[0], e0[4], e0[7], e0[5], -d3, ModelsNature.CAVE_ROCK_LOW)
	_qn(under_mb, e1[0], e1[5], e1[7], e1[4], d3, ModelsNature.LIME_LOW)
	# Stalactites under the roof.
	for i in int((s_mouth - s_in) / 2.5):
		var q: Vector2 = c + dir * rng.randf_range(s_in + 1.0, s_mouth - 2.5) + side * rng.randf_range(-hw * 0.8, hw * 0.8)
		under_mb.push(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(q.x, fl + h + 0.3, q.y)))
		under_mb.cyl(Vector3.ZERO, rng.randf_range(0.4, 1.0), rng.randf_range(0.15, 0.3), 0.0, 5, ModelsNature.CAVE_ROCK, false, rng.randf() * TAU)
		under_mb.pop()
	_add_mesh(under_mb.commit(), "TunnelPlug%s" % ("A" if which == 1 else "B"), true, true, true)
	_add_mesh(top_mb.commit(), "TunnelTop%s" % ("A" if which == 1 else "B"), true, true, false)
	# The arch over the mouth, its front a metre proud of the roof's start.
	var arch: Array = ARCH_A if which == 1 else ARCH_B
	var am := c + dir * (s_mouth + 0.6)
	_mouth_arch(am, dir, float(arch[0]), float(arch[1]), float(arch[2]), which, hw)
	mouths["a" if which == 1 else "b"] = [Vector3(am.x, fl, am.y) + Vector3(dir.x, 0, dir.y) * 0.9, Vector3(dir.x, 0, dir.y)]
	props.reserve(am + dir * 2.0, float(arch[0]) + 4.5)
	t.splat_ao(am, float(arch[0]) + 1.5, 0.45, c + dir * s_in)


## A cave mouth in the cliff: the opening (half width w, vertical jambs up to `spring`, a rough round arch up to
## `apex`, above the floor) cut through a rock face that follows the real cliff on both sides of the carved slot
## (the cliff's profile is sampled just outside the slot walls and interpolated across), so the slot disappears
## and the mouth reads as a hole in one continuous cliff. A lip of rock rims the opening; its soffit runs into
## the tunnel and a back face closes the gap to the tunnel's walls and roof. `tunnel_hw`: the carved half width.
func _mouth_arch(centre: Vector2, dir: Vector2, w: float, spring: float, apex: float, which: int, tunnel_hw: float = 3.6) -> void:
	var side := Vector2(-dir.y, dir.x)
	var fl := L.CAVE_FLOOR
	var d3 := Vector3(dir.x, 0, dir.y)
	var s3 := Vector3(side.x, 0, side.y)
	# The opening outline (lateral, height) from the left foot over the apex to the right foot, with its normal.
	var pts: Array[Vector2] = []
	var nrm: Array[Vector2] = []
	var foot := -0.8
	for k in 3:
		pts.append(Vector2(-w, lerpf(foot, spring, float(k) / 3.0)))
		nrm.append(Vector2(-1, 0))
	var arch_n := 12
	for k in arch_n + 1:
		var th := PI * (1.0 - float(k) / arch_n)
		pts.append(Vector2(w * cos(th), spring + (apex - spring) * sin(th)))
		nrm.append(Vector2(cos(th) / w, sin(th) / maxf(apex - spring, 0.1)).normalized())
	for k in range(1, 4):
		pts.append(Vector2(w, lerpf(spring, foot, float(k) / 3.0)))
		nrm.append(Vector2(1, 0))
	for k in pts.size():
		# A rough, natural opening (only ever narrower: the boulder must not fit through mouth B).
		var jit := _n.get_noise_2d(pts[k].x * 4.1 + which * 11.0, pts[k].y * 4.1) * 0.32
		pts[k] = pts[k] - nrm[k] * absf(jit) * (0.5 if pts[k].y < spring else 1.0)
	# The cliff's profile on each side, just outside the slot: for a height y, how far out (along dir) the rock
	# still stands that high.
	var W := tunnel_hw + 4.8
	var cen3 := Vector3(centre.x, fl, centre.y)
	var prof: Array = [] # per side: PackedFloat32Array of heights at s = -14 .. +16 (step 0.5)
	var tops := PackedFloat32Array()
	for sgn in [-1.0, 1.0]:
		var hs := PackedFloat32Array()
		var top := -INF
		var s := -14.0
		while s <= 16.0:
			var q: Vector2 = centre + side * float(sgn) * W + dir * s
			var hh: float = t.height_at(q.x, q.y)
			hs.append(hh)
			top = maxf(top, hh)
			s += 0.5
		prof.append(hs)
		tops.append(top)
	# (heights below are relative to the floor, like the outline)
	var ax_at := func(sd: int, y: float) -> float:
		var hs: PackedFloat32Array = prof[sd]
		var yy := fl + clampf(y, 1.4, tops[sd] - fl - 0.6)
		var best := -14.0
		for k in hs.size():
			if hs[k] >= yy:
				best = -14.0 + 0.5 * k
		return best
	var y_top := func(lat: float) -> float:
		return minf(tops[0], tops[1]) - fl - 0.6 + absf(tops[0] - tops[1]) * 0.0 * lat
	var surf := func(lat: float, y: float) -> float:
		var u := clampf((lat + W) / (2.0 * W), 0.0, 1.0)
		return lerpf(ax_at.call(0, y), ax_at.call(1, y), u)
	var to_w := func(lat: float, y: float, ax: float) -> Vector3:
		return cen3 + s3 * lat + Vector3.UP * y + d3 * ax
	# Rays from each outline point out to the face's edge (the slot's sides, the top, under the ground).
	var M := 6
	var grid: Array = [] # [k][j] -> Vector3
	var front: Array[Vector3] = []
	for k in pts.size():
		var p := pts[k]
		var n := nrm[k]
		var tmax := 40.0
		if absf(n.x) > 1e-4:
			tmax = minf(tmax, ((W if n.x > 0.0 else -W) - p.x) / n.x)
		if n.y > 1e-4:
			# the top edge (iterate: it slopes with the lateral position)
			var tt := tmax
			for it in 4:
				var q := p + n * tt
				tt = minf(tmax, (float(y_top.call(q.x)) - p.y) / n.y)
			tmax = tt
		elif n.y < -1e-4:
			tmax = minf(tmax, (foot - p.y) / n.y)
		tmax = maxf(tmax, 0.5)
		var row: Array[Vector3] = []
		for j in M + 1:
			var f := float(j) / M
			var q := p + n * tmax * f * f * (3.0 - 2.0 * f) * 0.5 + n * tmax * f * 0.5
			var ax: float = surf.call(q.x, q.y)
			# The lip: rock bulging out round the opening; rough in the middle of the face, exact at its edge.
			var lip := (1.0 - smoothstep(0.0, 0.45, f)) * 0.9
			var rough := _n.get_noise_2d(q.x * 1.3 + which * 31.0, q.y * 1.3) * 0.5 * (1.0 - f)
			row.append(to_w.call(q.x, q.y, ax + lip + rough))
		grid.append(row)
		front.append(row[0])
	var mb := MeshBuilder.new(960 + which)
	mb.vary = 0.04
	for k in pts.size() - 1:
		var r0: Array = grid[k]
		var r1: Array = grid[k + 1]
		for j in M:
			var col := ModelsNature.LIME if (k + j) % 4 != 1 else ModelsNature.LIME.lerp(ModelsNature.LIME_LOW, 0.3)
			_qn(mb, r0[j], r0[j + 1], r1[j + 1], r1[j], d3, col)
	# Soffit into the tunnel, and the back face that closes the frame against the tunnel.
	var back: Array[Vector3] = []
	var back_out: Array[Vector3] = []
	for k in pts.size():
		var p := pts[k]
		var ax_f: float = (front[k] - cen3).dot(d3)
		var ax_b := minf(ax_f - 3.2, -1.6)
		back.append(to_w.call(p.x, p.y, ax_b))
		back_out.append(to_w.call(p.x + nrm[k].x * 3.4, p.y + nrm[k].y * 3.4, ax_b))
	for k in pts.size() - 1:
		var inward := -(s3 * (nrm[k].x + nrm[k + 1].x) + Vector3.UP * (nrm[k].y + nrm[k + 1].y))
		_qn(mb, front[k], front[k + 1], back[k + 1], back[k], inward, ModelsNature.LIME_LOW.lerp(ModelsNature.CAVE_ROCK, 0.45))
		_qn(mb, back[k], back[k + 1], back_out[k + 1], back_out[k], -d3, ModelsNature.CAVE_ROCK_LOW)
	# A few loose blocks at the jambs' feet.
	for sgn in [-1.0, 1.0]:
		var lat: float = float(sgn) * (w + 1.6)
		var bp: Vector3 = to_w.call(lat, 0.0, float(surf.call(lat, 1.5)) + 0.8)
		bp.y = t.height_at(bp.x, bp.z) - 0.25
		mb.push(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), bp))
		ModelsNature.add_cliff_rock(mb, rng, 0.42 if which == 1 else 0.3)
		mb.pop()
	_add_mesh(mb.commit(), "MouthArch%s" % ("A" if which == 1 else "B"), true, true, true)


# --- inside ----------------------------------------------------------------------------------------------------

func _pillars() -> void:
	var c := L.CAVE_C
	var angles := [0.35, 1.55, 2.75, 3.95, 5.2]
	var radii := [7.2, 8.0, 6.8, 7.8, 7.4]
	var mb := MeshBuilder.new(930)
	mb.vary = 0.04
	for i in angles.size():
		var a: float = angles[i] + rng.randf_range(-0.12, 0.12)
		var r: float = radii[i]
		var p := Vector3(c.x + cos(a) * r, L.CAVE_FLOOR, c.y + sin(a) * r)
		var pr := rng.randf_range(0.7, 0.84)
		var top := lid_under(r, a) - L.CAVE_FLOOR + 0.8
		mb.push_at(p, rng.randf() * TAU)
		ModelsNature.add_cave_pillar(mb, rng, pr, top)
		mb.pop()
		pillars.append(p)
		# Collision: the flared foot in two steps, then the shaft.
		_cyl(pr * 1.62, 0.9, p + Vector3(0, -0.3, 0))
		_cyl(pr * 1.3, 2.2, p + Vector3(0, -0.3, 0))
		_cyl(pr * 1.02, top, p + Vector3(0, -0.3, 0))
		t.splat_ao(Vector2(p.x, p.z), pr * 2.2, 0.55)
	_add_mesh(mb.commit(), "CavePillars", false)


func _floor_details() -> void:
	var c := L.CAVE_C
	var mb := MeshBuilder.new(940)
	mb.vary = 0.04
	# Stalagmites along the walls, leaving the tunnel openings clear.
	var da := (L.MOUTH_A - c).angle()
	var db := (L.MOUTH_B - c).angle()
	var placed := 0
	var tries := 0
	while placed < 12 and tries < 200:
		tries += 1
		var a := rng.randf() * TAU
		if absf(angle_difference(a, da)) < 0.45 or absf(angle_difference(a, db)) < 0.3:
			continue
		var r := rng.randf_range(10.8, 12.6)
		var p := Vector3(c.x + cos(a) * r, L.CAVE_FLOOR, c.y + sin(a) * r)
		var ok := true
		for q in pillars:
			if Vector2(q.x - p.x, q.z - p.z).length() < 3.2:
				ok = false
		if not ok:
			continue
		var s := rng.randf_range(0.8, 1.3)
		mb.push_at(p, rng.randf() * TAU, Vector3.ONE * s)
		ModelsNature.add_stalagmite(mb, rng, 1.0)
		mb.pop()
		_cyl(0.85 * s, 2.0 * s, p)
		placed += 1
	# The lion's corner: bones and a goat skull by the north wall.
	for i in 3:
		var a := -PI * 0.5 + rng.randf_range(-0.5, 0.5)
		var r := rng.randf_range(9.0, 11.5)
		var p := Vector3(c.x + cos(a) * r, L.CAVE_FLOOR + 0.02, c.y + sin(a) * r)
		mb.push_at(p, rng.randf() * TAU)
		ModelsNature.add_bones(mb, rng, i == 0)
		mb.pop()
	_add_mesh(mb.commit(), "CaveFloor", false)


## Three cracks in the ceiling glowing with daylight, a shaft of light from each down to the floor and a warm
## pool where it lands (posterised by the toon light), plus a soft warm glow filling the arena.
func _light_shafts() -> void:
	var c := L.CAVE_C
	var cracks := [[Vector2(-3.0, -2.5), 0.4], [Vector2(4.5, 3.5), 1.3], [Vector2(-1.0, 5.5), 2.4]]
	var mb := MeshBuilder.new(950)
	var glow := Color(1.0, 0.93, 0.72, 0.5)
	for cr in cracks:
		var off: Vector2 = cr[0]
		var ang: float = cr[1]
		var p2 := c + off
		var r := off.length()
		var yc := lid_under(r, off.angle()) - 0.05
		var top := Vector3(p2.x, yc, p2.y)
		# The slit: a jagged self-lit sliver just under the ceiling.
		var d := Vector3(cos(ang), 0, sin(ang))
		var nrm := Vector3(-d.z, 0, d.x)
		var pts: Array[Vector3] = []
		for k in 7:
			var u := -2.6 + 5.2 * float(k) / 6.0
			pts.append(top + d * u + nrm * (0.18 + rng.randf_range(0.0, 0.2)) * (1.0 - absf(u) / 3.0))
		for k in 7:
			var u := 2.6 - 5.2 * float(k) / 6.0
			pts.append(top + d * u - nrm * (0.18 + rng.randf_range(0.0, 0.2)) * (1.0 - absf(u) / 3.0))
		for k in range(1, pts.size() - 1):
			mb.tri(pts[0], pts[k + 1], pts[k], glow)
			mb.tri(pts[0], pts[k], pts[k + 1], glow)
		# The shaft: a soft additive cone from the crack to the floor.
		var length := yc - L.CAVE_FLOOR + 0.5
		var beam := MeshInstance3D.new()
		beam.name = "LightShaft"
		beam.mesh = Materials.cone_mesh(length, 1.0, 2.4, 12)
		beam.material_override = Materials.beam_cone(length, Color(1.0, 0.9, 0.68))
		Materials.set_param(beam, &"intensity", 2.2)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = top
		beam.rotation = Vector3(PI * 0.5, 0, 0)
		world.add_child(beam)
		# The pool of light on the floor.
		var spot := SpotLight3D.new()
		spot.name = "ShaftLight"
		spot.light_color = Color(1.0, 0.86, 0.62)
		spot.light_energy = 3.0
		spot.spot_range = length + 6.0
		spot.spot_angle = 12.0
		spot.spot_attenuation = 0.0 # no distance decay: the toon pool bands come from the range falloff
		spot.shadow_enabled = false
		spot.light_specular = 0.0
		spot.position = top + Vector3(0, -0.3, 0)
		spot.rotation = Vector3(-PI * 0.5, 0, 0)
		world.add_child(spot)
		lights.append(spot)
	_add_mesh(mb.commit(), "CaveCracks", false, false)
	# The warm glow: daylight bouncing off the sunlit floor under the cracks fills the arena.
	var fill := OmniLight3D.new()
	fill.name = "CaveGlow"
	fill.light_color = Color(1.0, 0.74, 0.48)
	fill.light_energy = 1.7
	fill.omni_range = L.CAVE_R + 11.0
	fill.omni_attenuation = 0.0
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	fill.position = Vector3(c.x, L.CAVE_FLOOR + 7.5, c.y)
	world.add_child(fill)
	lights.append(fill)


## The boulder on mouth B's apron: beside the crack (on the open side), on flat ground, with a clear run to the
## arch (drag it towards the hero standing in the crack and it stops against the arch, sealing it).
func _boulder() -> void:
	var mb: Array = mouths["b"]
	var mp: Vector3 = mb[0]
	var out: Vector3 = mb[1]
	var side := Vector3(-out.z, 0, out.x)
	var best := Vector3.INF
	var best_score := INF
	for sgn in [1.0, -1.0]:
		for lat in [4.6, 5.2, 4.0, 5.8]:
			for ax in [3.2, 3.8, 2.6, 4.4]:
				var q: Vector3 = mp + out * float(ax) + side * float(sgn) * float(lat)
				var ok := true
				# Flat, open ground under it and on the way to the arch.
				for k in 6:
					var u := float(k) / 5.0
					var s: Vector3 = q.lerp(mp + out * 1.4, u)
					if t.normal_at(s.x, s.z).y < 0.95 or absf(t.height_at(s.x, s.z) - (L.CAVE_FLOOR + 0.35)) > 0.7:
						ok = false
						break
				if not ok:
					continue
				var score := absf(float(lat) - 4.8) + absf(float(ax) - 3.4)
				if score < best_score:
					best_score = score
					best = q
	if not best.is_finite():
		best = mp + out * 3.4 + side * 4.8
	var p := Vector3(best.x, t.height_at(best.x, best.z) + 0.05, best.z)
	if ResourceLoader.exists("res://scripts/props/boulder.gd"):
		boulder = load("res://scripts/props/boulder.gd").new()
	else:
		boulder = Node3D.new()
	boulder.name = "CaveBoulder"
	world.add_child(boulder)
	boulder.global_position = p
	props.reserve(Vector2(best.x, best.z), 3.2)
	props.reserve(Vector2(mp.x, mp.z) + Vector2(out.x, out.z) * 2.0, 5.5)
