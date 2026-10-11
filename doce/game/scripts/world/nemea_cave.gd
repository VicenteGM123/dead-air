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
##   - the boulder on the apron of mouth B, out in front of the crack on its axis, on flat open ground: hooked with
##     the chain from the crack and hauled straight in, it comes to rest against the face over the opening (where
##     the build measured it would: cave()["seal_b"]) and seals it (integration fix: beside the crack it wedged
##     between the cliff foot and a rise of the apron before it reached the opening).
## cave() entrance_a / entrance_b are the floor points just inside each opening's outer face (where a boulder
## sealing it touches); inner_a / inner_b the old points behind the arch (0.9 m out from where the roof starts).
## Collision (layer 1): trimesh for the lid, the plugs and the arches; cylinders for pillars and stalagmites.

const L := preload("res://scripts/world/nemea_layout.gd")
const LID_R := 18.2
## Mouth arches: [opening half width, spring height, apex height] (above the floor).
const ARCH_A := [3.3, 3.8, 6.7]
## (merge: mouth B's arch lowered from 2.6 / 4.3 m so the boulder, 2.6 m across, plugs most of it; the hero, 1.9 m,
## still walks through under its 2.25 m jambs)
const ARCH_B := [1.05, 2.25, 3.3]
const LIGHTS_ON_DIST := 46.0
## The boulder (scripts/props/boulder.gd RADIUS, its centre RADIUS * 0.95 over its origin) for the seal spot.
const BOULDER_R := 1.3
## How far out from its seal spot the boulder waits (centre to centre, along the mouth's axis).
const BOULDER_RUN := [5.5, 6.0, 5.0, 6.5, 4.6]

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
## Per mouth ("a" / "b"): [outer face point on the floor, boulder seal point] (see _measure_mouth).
var _faces := {}


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
	_perch_layout()
	_floor_details()
	_light_shafts()
	_boulder()
	_dress()
	var c := Vector3(L.CAVE_C.x, L.CAVE_FLOOR, L.CAVE_C.y)
	var ma: Array = mouths["a"]
	var mb: Array = mouths["b"]
	info = {
		"entrance_a": _floor_at(ma[2]),
		"entrance_b": _floor_at(mb[2]),
		"inner_a": _floor_at(ma[0]),
		"inner_b": _floor_at(mb[0]),
		# where the boulder's origin rests when it seals mouth B (Boulder.is_blocking(seal_b, 1.2))
		"seal_b": _floor_at(mb[3]),
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


## Like _qn, but each of the two triangles is turned towards `want` on its own, so a strongly folded quad never
## leaves a back-facing (culled) hole. Same shading draw as quad().
static func _qn_up(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
	var sc := mb._shade(col)
	var keep := mb.vary
	mb.vary = 0.0
	for tr: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tr[0]
		var p1: Vector3 = tr[1]
		var p2: Vector3 = tr[2]
		if (p1 - p0).cross(p2 - p0).dot(want) < 0.0:
			mb.tri(p0, p2, p1, sc)
		else:
			mb.tri(p0, p1, p2, sc)
	mb.vary = keep


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
			var sx: float = q3.x + side.x * wide * 1.6
			var sz: float = q3.z + side.y * wide * 1.6
			var tc: Color = t.color_at(sx, sz)
			# Integration fix: where the top is not flush with the ground it was coloured from (the cleft over
			# mouth B, whose sample lands on the meadow 6 m below), it is bare rock like the cliff, not a patch
			# of meadow halfway up the cliff; and each triangle faces up on its own (the leaning rows fold).
			var bare := smoothstep(1.0, 3.0, absf(q3.y - float(t.height_at(sx, sz))))
			_qn_up(top_mb, r0[5 + u], r0[6 + u], r1[6 + u], r1[5 + u], Vector3.UP, Color(tc.r, tc.g, tc.b).lerp(ModelsNature.LIME, lerpf(0.35, 1.0, bare)))
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
	var key := "a" if which == 1 else "b"
	var fs: Array = _faces[key]
	# [inner point (behind the arch), outward dir, outer face point, boulder seal point]
	mouths[key] = [Vector3(am.x, fl, am.y) + Vector3(dir.x, 0, dir.y) * 0.9, Vector3(dir.x, 0, dir.y), fs[0], fs[1]]
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
	_measure_mouth(which, cen3, d3, s3, grid, pts, spring)
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


## The opening's outer face and, for a boulder of BOULDER_R hauled straight in along the axis, where it stops
## against the face: for each lateral offset within the opening the deepest the sphere gets before it touches a
## point of the face (the opening's rim and the rock round it), the deepest offset winning (a little preference
## for the middle). Stores [face point, seal point] (floor level, the seal point = the boulder's origin).
func _measure_mouth(which: int, cen3: Vector3, d3: Vector3, s3: Vector3, grid: Array, pts: Array[Vector2], spring: float) -> void:
	var face_sum := 0.0
	var face_n := 0
	for k in pts.size():
		if pts[k].y > 0.0 and pts[k].y < spring:
			var row: Array = grid[k]
			face_sum += ((row[0] as Vector3) - cen3).dot(d3)
			face_n += 1
	var face_s := face_sum / maxf(1.0, float(face_n))
	var cy := BOULDER_R * 0.95
	var best := INF
	var best_s := face_s + BOULDER_R
	var best_lat := 0.0
	for li in 21:
		var lat0 := lerpf(-1.0, 1.0, float(li) / 20.0)
		var stop := -INF
		for row: Array in grid:
			for q: Vector3 in row:
				var rel := q - cen3
				var dl := rel.dot(s3) - lat0
				var dy := rel.y - cy
				var r2 := BOULDER_R * BOULDER_R - dl * dl - dy * dy
				if r2 > 0.0:
					stop = maxf(stop, rel.dot(d3) + sqrt(r2))
		if stop == -INF:
			continue
		var score := stop + absf(lat0) * 0.15
		if score < best:
			best = score
			best_s = stop
			best_lat = lat0
	var face := cen3 + d3 * (face_s - 0.3)
	var seal := cen3 + d3 * (best_s + 0.05) + s3 * best_lat
	_faces["a" if which == 1 else "b"] = [face, seal]


# --- inside ----------------------------------------------------------------------------------------------------

func _pillars() -> void:
	var c := L.CAVE_C
	var angles := [0.35, 1.55, 2.75, 3.95, 5.2]
	var radii := [7.2, 8.0, 6.8, 7.8, 7.4]
	var mb := MeshBuilder.new(930)
	mb.vary = 0.0 # (lane L: the rock colour varies smoothly by itself; per-face jitter read as a checkerboard)
	for i in angles.size():
		var a: float = angles[i] + rng.randf_range(-0.12, 0.12)
		var r: float = radii[i]
		var p := Vector3(c.x + cos(a) * r, L.CAVE_FLOOR, c.y + sin(a) * r)
		var pr := rng.randf_range(0.7, 0.84)
		var top := lid_under(r, a) - L.CAVE_FLOOR + 0.8
		var yaw := rng.randf() * TAU
		# (lane L) the same column (its profile comes from the same random numbers, which advance exactly as
		# before, so nothing after it moves), dressed as fluted flowstone rock with strata and cracks
		var prof_rng := RandomNumberGenerator.new()
		prof_rng.seed = rng.seed
		prof_rng.state = rng.state
		ModelsNature.add_cave_pillar(MeshBuilder.new(1), rng, pr, top)
		mb.push_at(p, yaw)
		_rock_pillar(mb, prof_rng, pr, top, i)
		mb.pop()
		pillars.append(p)
		pillar_cols[i]["yaw"] = yaw
		pillar_cols[i]["pos"] = p
		# Collision: the flared foot in steps that follow the column (0.5 m each, up to 3 m), then the shaft.
		var pc: Dictionary = pillar_cols[i]
		var y0 := -0.3
		while y0 < 3.0:
			var y1 := y0 + 0.5
			_cyl(maxf(_prof_r(pc, y0), _prof_r(pc, y1)) * 1.08, y1 - y0, p + Vector3(0, y0, 0))
			y0 = y1
		_cyl(pr * 1.02, top, p + Vector3(0, -0.3, 0))
		t.splat_ao(Vector2(p.x, p.z), pr * 2.2, 0.55)
	# the camera cuts them away (a screen door, lowpoly cut_*) where they stand between the lens and the hero or a
	# wrestle (CameraRig, group "camera_cut")
	_add_mesh(mb.commit(), "CavePillars", false).add_to_group("camera_cut")


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
		for o: Dictionary in outcrops:
			var oc: Vector3 = o["center"]
			if Vector2(oc.x - p.x, oc.z - p.z).length() < PERCH_R + 1.6:
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
		# (lane L) in front of the den rock, clear of the pillars either side
		var a := -PI * 0.5 + rng.randf_range(-0.5, 0.5) * 0.35
		var r := rng.randf_range(6.0, 7.2)
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


## The boulder on mouth B's apron, out in front of the crack on its axis (in line with where it seals the opening:
## hauled straight in from the crack it rolls up to the face and stops there, see _measure_mouth), on flat open
## ground with a flat run to the seal spot, the hero's way round it on either side.
func _boulder() -> void:
	var mb: Array = mouths["b"]
	var out: Vector3 = mb[1]
	var seal: Vector3 = mb[3]
	var side := Vector3(-out.z, 0, out.x)
	var best := Vector3.INF
	for run in BOULDER_RUN:
		var q: Vector3 = seal + out * float(run)
		var ok := true
		# flat ground under it and on its way in (a band as wide as the boulder)
		for k in 8:
			var u := float(k) / 7.0
			for lat in [-1.0, 0.0, 1.0]:
				var sp: Vector3 = q.lerp(seal, u) + side * float(lat)
				if t.normal_at(sp.x, sp.z).y < 0.94 or absf(t.height_at(sp.x, sp.z) - (L.CAVE_FLOOR + 0.3)) > 0.6:
					ok = false
		if ok:
			best = q
			break
	if not best.is_finite():
		push_warning("NemeaCave: no flat run for the boulder in front of mouth B")
		best = seal + out * float(BOULDER_RUN[0])
	var p := Vector3(best.x, t.height_at(best.x, best.z) + 0.05, best.z)
	if ResourceLoader.exists("res://scripts/props/boulder.gd"):
		boulder = load("res://scripts/props/boulder.gd").new()
	else:
		boulder = Node3D.new()
	boulder.name = "CaveBoulder"
	world.add_child(boulder)
	boulder.global_position = p
	# keep the scatter off the boulder, its run in and the apron in front of the crack
	props.reserve(Vector2(best.x, best.z), 3.4)
	props.reserve(Vector2(seal.x, seal.z).lerp(Vector2(best.x, best.z), 0.5), 3.2)
	props.reserve(Vector2(seal.x, seal.z), 3.0)


# --- (ENCOUNTERS lane L) the lion's arena dressed: rock pillars, perches, cracks, rubble, the den --------------------
# Nothing here moves the pillars, the floor or World.cave()'s keys: the columns keep their places and profiles (only
# their surface and their collision steps change), the rest is added round the walls.

## The lion's perches: flat-topped tors of layered cave rock by the walls, [angle (degrees, atan2(z, x) round the
## arena centre), distance (m)]; the third is its den rock (north, over the bones). Tops PERCH_H over the floor,
## collision radius PERCH_R (a cylinder: the sides are walls the lion is stunned against).
const PERCH_AT := [[115.0, 11.0], [197.0, 11.0], [265.0, 11.0], [335.0, 11.0]]
const PERCH_H := 2.3
const PERCH_R := 2.25
## The flat top (m from the tor's centre): the lion stands there.
const PERCH_TOP_R := 1.75
const CRACK_COL := Color("2E2420")

## Per pillar: {y, r (profile rings), ph (flute phase), k (index), pos, yaw} (the rock surface: col_radius()).
var pillar_cols: Array = []
## The perches (see perches()).
var outcrops: Array = []
## Cracks grown by the lion's slams, per pillar (0..4).
var pillar_damage := PackedInt32Array()
var _pn := FastNoiseLite.new()


## The lion's perches for the encounter: [{center (on the floor), top (y), r (flat top radius), spot (where it
## lands on top), launch (where it takes off from the floor), ang (degrees), den (bool)}].
func perches() -> Array:
	return outcrops


func _perch_layout() -> void:
	var c := L.CAVE_C
	for k in PERCH_AT.size():
		var a := deg_to_rad(float(PERCH_AT[k][0]))
		var dist: float = PERCH_AT[k][1]
		var p2 := c + Vector2(cos(a), sin(a)) * dist
		var center := Vector3(p2.x, t.height_at(p2.x, p2.y), p2.y)
		var inward := Vector3(-cos(a), 0, -sin(a))
		var top := center.y + PERCH_H
		var spot := Vector3(center.x, top, center.z) + inward * 0.3
		var lp := center + inward * (PERCH_R + 5.0)
		outcrops.append({"center": center, "top": top, "r": PERCH_TOP_R, "spot": spot,
			"launch": Vector3(lp.x, t.height_at(lp.x, lp.z), lp.z), "ang": float(PERCH_AT[k][0]), "den": k == 2})
		props.reserve(p2, PERCH_R + 0.5)


## A flowstone column on the profile of ModelsNature.add_cave_pillar (the same random numbers: `prof_rng` is a copy
## of the cave's generator at that point), with fluting (five shallow ribs), lumps, strata bands in the colour, a
## damp foot and two or three old cracks. Origin at the floor, in the column's own turned frame (push_at).
func _rock_pillar(mb: MeshBuilder, prof_rng: RandomNumberGenerator, r: float, h: float, idx: int) -> void:
	if pillar_cols.is_empty():
		_pn.seed = 4242
		_pn.frequency = 0.9
	var n := 9
	var ys := PackedFloat32Array()
	var rs := PackedFloat32Array()
	for i in n + 1:
		var tt := float(i) / float(n)
		var w := 1.0 + 0.75 * pow(1.0 - tt, 4.0) + 0.6 * pow(tt, 5.0) - 0.18 * sin(tt * PI)
		w *= prof_rng.randf_range(0.9, 1.08)
		ys.append(-0.3 + (h + 0.6) * tt)
		rs.append(r * w)
	var fy := PackedFloat32Array()
	var fr := PackedFloat32Array()
	for i in n:
		for sub in 3:
			var u := float(sub) / 3.0
			fy.append(lerpf(ys[i], ys[i + 1], u))
			fr.append(_catmull(rs[maxi(i - 1, 0)], rs[i], rs[i + 1], rs[mini(i + 2, n)], u))
	fy.append(ys[n])
	fr.append(rs[n])
	var col := {"y": fy, "r": fr, "ph": float(idx) * 1.7 + 0.4, "k": idx, "pos": Vector3.ZERO, "yaw": 0.0}
	pillar_cols.append(col)
	pillar_damage.append(0)
	var sides := 14
	var grid: Array = []
	for j in fy.size():
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var rad := col_radius(col, a, fy[j])
			ring.append(Vector3(cos(a) * rad, fy[j], sin(a) * rad))
		grid.append(ring)
	for j in fy.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var a0: Vector3 = grid[j][k]
			var a1: Vector3 = grid[j][k2]
			var b0: Vector3 = grid[j + 1][k]
			var b1: Vector3 = grid[j + 1][k2]
			var fc := (a0 + a1 + b0 + b1) * 0.25
			var ang := atan2(fc.z, fc.x)
			_qn(mb, a0, b0, b1, a1, Vector3(fc.x, 0, fc.z), _rock_col(col, ang, fc.y))
	# old cracks: two or three jagged lines down the shaft
	var crng := RandomNumberGenerator.new()
	crng.seed = 9100 + idx
	for c in 2 + crng.randi() % 2:
		var a := crng.randf() * TAU
		var y := crng.randf_range(0.5, 2.2)
		_crack_line(mb, col, a, y, crng.randf_range(1.2, 2.6), 0.03, crng, Vector2(0.0, 1.0), 2)


## Surface radius of a column at local angle `a` (radians, the column's own frame) and height `y` over the floor.
func col_radius(col: Dictionary, a: float, y: float) -> float:
	var fy: PackedFloat32Array = col["y"]
	var fr: PackedFloat32Array = col["r"]
	var base := _prof_r(col, y)
	var rib := pow(maxf(0.0, sin(a * 5.0 + float(col["ph"]))), 2.0) * 0.075
	var lump := _pn.get_noise_3d(cos(a) * 1.3, y * 0.8 + float(col["k"]) * 17.0, sin(a) * 1.3) * 0.03
	return base * (1.0 + rib + lump)


## The profile's radius at height y (linear between the fine rings).
func _prof_r(col: Dictionary, y: float) -> float:
	var fy: PackedFloat32Array = col["y"]
	var fr: PackedFloat32Array = col["r"]
	if y <= fy[0]:
		return fr[0]
	for j in fy.size() - 1:
		if y <= fy[j + 1]:
			return lerpf(fr[j], fr[j + 1], (y - fy[j]) / maxf(fy[j + 1] - fy[j], 1e-4))
	return fr[fr.size() - 1]


static func _catmull(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


## Smooth, low-contrast colour of the rock (no per-face noise: neighbouring faces differ only a little): broad
## strata bands, the flutes' grooves a shade darker, a damp foot.
func _rock_col(col: Dictionary, a: float, y: float) -> Color:
	# strata: broad horizontal bands, one tone per ring of faces (a colour that changed round the column, face by
	# face, read as a checkerboard under the toon light); their heights wander a little from column to column
	var nz := _pn.get_noise_2d(y * 0.35, float(col["k"]) * 9.0)
	var st := fposmod(y * 0.85 + nz * 1.2 + float(col["k"]) * 0.37, 3.0)
	var c := ModelsNature.CAVE_ROCK
	if st >= 1.3 and st < 2.2:
		c = ModelsNature.CAVE_ROCK.lerp(ModelsNature.CAVE_ROCK_TOP, 0.4)
	elif st >= 2.2:
		c = ModelsNature.CAVE_ROCK.lerp(ModelsNature.CAVE_ROCK_LOW, 0.22)
	# the damp foot
	return c.lerp(Color("6A5C55"), (1.0 - smoothstep(0.1, 0.7, y)) * 0.35)


## A jagged crack drawn on a column's surface: from (a, y) along `dir` (Vector2(angle-ish, up): metres along the
## surface), `len` m in steps, `w` wide, with `branches` side cracks. A dark strip 1.2 cm proud of the rock.
func _crack_line(mb: MeshBuilder, col: Dictionary, a: float, y: float, length: float, w: float, rng2: RandomNumberGenerator, dir: Vector2, branches: int) -> void:
	var pts: Array[Vector2] = [Vector2(a, y)]
	var d := dir.normalized()
	var made := 0.0
	while made < length:
		var step := rng2.randf_range(0.12, 0.26)
		d = d.rotated(rng2.randf_range(-0.6, 0.6)).lerp(dir.normalized(), 0.35).normalized()
		var last: Vector2 = pts[pts.size() - 1]
		var rad := _prof_r(col, last.y)
		pts.append(last + Vector2(d.x * step / maxf(rad, 0.3), d.y * step))
		made += step
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var k := 1.0 - float(i) / float(pts.size())
		var hw := w * (0.35 + 0.65 * k)
		_crack_seg(mb, col, p0, p1, hw)
		if branches > 0 and i > 0 and rng2.randf() < 0.3:
			branches -= 1
			var side := Vector2(-d.y, d.x) * (1.0 if rng2.randf() < 0.5 else -1.0)
			_crack_line(mb, col, p0.x, p0.y, length * 0.3, w * 0.6, rng2, (dir.normalized() * 0.4 + side).normalized(), 0)


func _surf(col: Dictionary, a: float, y: float, out: float) -> Vector3:
	var rad := col_radius(col, a, y) + out
	return Vector3(cos(a) * rad, y, sin(a) * rad)


func _crack_seg(mb: MeshBuilder, col: Dictionary, p0: Vector2, p1: Vector2, hw: float) -> void:
	var d := p1 - p0
	var rad := _prof_r(col, p0.y)
	var dm := Vector2(d.x * rad, d.y) # metres on the surface
	if dm.length() < 1e-4:
		return
	var nrm := Vector2(-dm.y, dm.x).normalized() * hw
	var na := Vector2(nrm.x / maxf(rad, 0.3), nrm.y)
	var a0 := _surf(col, p0.x + na.x, p0.y + na.y, 0.012)
	var b0 := _surf(col, p0.x - na.x, p0.y - na.y, 0.012)
	var a1 := _surf(col, p1.x + na.x * 0.8, p1.y + na.y * 0.8, 0.012)
	var b1 := _surf(col, p1.x - na.x * 0.8, p1.y - na.y * 0.8, 0.012)
	var mid := (a0 + b1) * 0.5
	_qn(mb, a0, a1, b1, b0, Vector3(mid.x, 0, mid.z), CRACK_COL)


## (lane L) The lion slammed into something at `point` (its head, ~1 m up), coming from `normal` (from the surface
## towards the lion): a column there cracks a little more each time (a star of cracks round the blow, up to four
## times), chips and dust fall and a few stones stay at its foot. Elsewhere (the walls, a perch) only the dust.
func crack_at(point: Vector3, normal: Vector3, power: float) -> void:
	var best := -1
	var best_d := 1.0
	for i in pillars.size():
		if i >= pillar_cols.size():
			break
		var col: Dictionary = pillar_cols[i]
		var p: Vector3 = pillars[i]
		var d := Vector2(point.x - p.x, point.z - p.z)
		var gap := absf(d.length() - _prof_r(col, clampf(point.y - p.y, 0.0, 3.0)))
		if gap < best_d:
			best_d = gap
			best = i
	if Game.fx:
		Game.fx.call("dust", point + normal * 0.3, 10, 0.9)
		Game.fx.call("smoke", point + normal * 0.2, 3, Color(0.6, 0.55, 0.5))
	if best < 0:
		return
	var stage := mini(pillar_damage[best] + 1, 4)
	if pillar_damage[best] >= 4:
		return
	pillar_damage[best] = stage
	var col2: Dictionary = pillar_cols[best]
	var pp: Vector3 = pillars[best]
	var world_ang := atan2(point.z - pp.z, point.x - pp.x)
	var la := world_ang + float(col2["yaw"])
	var y := clampf(point.y - pp.y, 0.5, 2.6)
	var crng := RandomNumberGenerator.new()
	crng.seed = 7000 + best * 31 + stage * 7
	var mb := MeshBuilder.new(8000 + best * 10 + stage)
	var arms := 4 + stage * 2
	var length := (0.35 + 0.28 * float(stage)) * (0.7 + 0.5 * clampf(power, 0.0, 1.0))
	for k in arms:
		var ang := TAU * float(k) / float(arms) + crng.randf_range(-0.3, 0.3)
		_crack_line(mb, col2, la, y, length * crng.randf_range(0.6, 1.2), 0.035 + 0.01 * stage, crng, Vector2(cos(ang), sin(ang)), 1)
	# the dent: a dark star at the centre
	_crack_line(mb, col2, la, y, 0.12, 0.09, crng, Vector2(1, 0), 0)
	_crack_line(mb, col2, la, y, 0.12, 0.09, crng, Vector2(-1, 0), 0)
	var mi := MeshInstance3D.new()
	mi.name = "PillarCrack%d_%d" % [best, stage]
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, float(col2["yaw"])), pp)
	mi.add_to_group("camera_cut")
	# chips at its foot (no collision: flat stones)
	var rb := MeshBuilder.new(8500 + best * 10 + stage)
	rb.vary = 0.05
	var foot := _prof_r(col2, 0.0)
	for k in 2 + stage:
		var a2 := world_ang + crng.randf_range(-0.6, 0.6)
		var rr := crng.randf_range(0.08, 0.16) * (1.0 + 0.2 * stage)
		var q := pp + Vector3(cos(a2), 0, sin(a2)) * (foot + crng.randf_range(0.15, 0.9))
		q.y = t.height_at(q.x, q.z) - rr * 0.35
		ModelsNature.chunk(rb, crng, q, rr, rr * 0.7, 5, ModelsNature.CAVE_ROCK, ModelsNature.CAVE_ROCK_LOW, ModelsNature.CAVE_ROCK_TOP)
	var rm := MeshInstance3D.new()
	rm.name = "PillarChips%d_%d" % [best, stage]
	rm.mesh = rb.commit()
	rm.material_override = Materials.lowpoly()
	world.add_child(rm)


## The rest of the dressing: the perches (tors), rubble along the walls and round the columns' feet, more bones,
## the gear of a hunter who came before Heracles, small stalagmites at the foot of the walls, a shaft of light on
## the den rock.
func _dress() -> void:
	var c := L.CAVE_C
	for i in pillars.size():
		if i < pillar_cols.size():
			# (the columns were built in their own turned frame: keep it for the cracks)
			pillar_cols[i]["pos"] = pillars[i]
	var drng := RandomNumberGenerator.new()
	drng.seed = 5150
	# the tors
	var mb := MeshBuilder.new(5151)
	mb.vary = 0.0
	for o: Dictionary in outcrops:
		var center: Vector3 = o["center"]
		var one := MeshBuilder.new(5155)
		var inward := Vector3(c.x - center.x, 0.0, c.y - center.z).normalized()
		_tor(one, drng, PERCH_R, PERCH_H, inward)
		var hull := one.commit()
		var cs := CollisionShape3D.new()
		cs.shape = hull.create_convex_shape(true, false)
		cs.position = center
		body.add_child(cs)
		mb.push_at(center, 0.0)
		mb.append_builder(one)
		mb.pop()
		t.splat_ao(Vector2(center.x, center.z), PERCH_R + 1.4, 0.5)
	# (the camera cuts them away too where they stand between the lens and the hero: they are big and near the walls,
	# where the arm often ends up behind one)
	_add_mesh(mb.commit(), "LionPerches", false).add_to_group("camera_cut")
	# the lion's marks: claws raked down the two columns by its den (on the side it passes) and on the floor before it
	var cm := MeshBuilder.new(5157)
	cm.vary = 0.0
	var den: Vector3 = (outcrops[2] as Dictionary)["center"] if outcrops.size() > 2 else Vector3(c.x, L.CAVE_FLOOR, c.y - 11.0)
	var by_den: Array = []
	for i in pillars.size():
		by_den.append([Vector2(pillars[i].x - den.x, pillars[i].z - den.z).length(), i])
	by_den.sort()
	for k in mini(2, by_den.size()):
		var i: int = by_den[k][1]
		if i >= pillar_cols.size():
			continue
		var pc: Dictionary = pillar_cols[i]
		var pp: Vector3 = pillars[i]
		# facing the arena's middle, a little round towards the den
		var wa := atan2(c.y - pp.z, c.x - pp.x) + (0.35 if k == 0 else -0.35)
		cm.push_at(pp, float(pc["yaw"]))
		_claw_marks(cm, pc, wa + float(pc["yaw"]), 1.75 + 0.15 * float(k))
		_claw_marks(cm, pc, wa + float(pc["yaw"]) + 0.5, 1.45)
		cm.pop()
	var claws := _add_mesh(cm.commit(), "PillarClaws", false, false)
	claws.add_to_group("camera_cut")
	var fm := MeshBuilder.new(5158)
	fm.vary = 0.0
	var to_c := Vector3(c.x - den.x, 0.0, c.y - den.z).normalized()
	var sd := Vector3(-to_c.z, 0.0, to_c.x)
	for fc in [[3.6, 0.9, 0.3], [4.4, -1.1, -0.25], [5.6, 0.2, 0.1]]:
		var at := den + to_c * float(fc[0]) + sd * float(fc[1])
		_floor_claws(fm, at, to_c.rotated(Vector3.UP, float(fc[2])), 0.9)
	_add_mesh(fm.commit(), "FloorClaws", false, false)
	# rubble: flat stones (no collision) along the walls, round the columns' feet and the tors
	var rb := MeshBuilder.new(5152)
	rb.vary = 0.05
	var da := (L.MOUTH_A - c).angle()
	var db := (L.MOUTH_B - c).angle()
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 400:
		tries += 1
		var a := drng.randf() * TAU
		var r := drng.randf_range(11.6, 13.5) if drng.randf() < 0.7 else drng.randf_range(5.0, 11.0)
		if absf(angle_difference(a, da)) < 0.32 or absf(angle_difference(a, db)) < 0.2:
			continue
		var p := Vector3(c.x + cos(a) * r, 0.0, c.y + sin(a) * r)
		if not _clear_of_solids(p, 0.5):
			continue
		var s := drng.randf_range(0.07, 0.2) * (1.0 if r > 11.0 else 0.7)
		p.y = t.height_at(p.x, p.z) - s * 0.3
		ModelsNature.chunk(rb, drng, p, s, s * drng.randf_range(0.45, 0.7), 5, ModelsNature.CAVE_ROCK, ModelsNature.CAVE_ROCK_LOW, ModelsNature.CAVE_ROCK_TOP)
		placed += 1
	for i in pillars.size():
		var pp: Vector3 = pillars[i]
		for k in 3:
			var a := drng.randf() * TAU
			var q := pp + Vector3(cos(a), 0, sin(a)) * (_prof_r(pillar_cols[i], 0.0) + drng.randf_range(0.2, 0.7))
			var s := drng.randf_range(0.06, 0.13)
			q.y = t.height_at(q.x, q.z) - s * 0.3
			ModelsNature.chunk(rb, drng, q, s, s * 0.6, 5, ModelsNature.CAVE_ROCK, ModelsNature.CAVE_ROCK_LOW, ModelsNature.CAVE_ROCK_TOP)
	_add_mesh(rb.commit(), "CaveRubble", false, false)
	# bones: a second skull and scattered bones in front of the den rock and by the west tor; the old hunter's gear
	var bm := MeshBuilder.new(5153)
	bm.vary = 0.03
	for b in [[268.0, 8.0, true], [255.0, 8.4, false], [282.0, 8.2, false], [205.0, 8.4, true], [128.0, 8.3, false]]:
		var a := deg_to_rad(float(b[0]))
		var q := Vector3(c.x + cos(a) * float(b[1]), L.CAVE_FLOOR + 0.02, c.y + sin(a) * float(b[1]))
		if not _clear_of_solids(q, 0.6):
			continue
		q.y = t.height_at(q.x, q.z) + 0.02
		bm.push_at(q, drng.randf() * TAU)
		ModelsNature.add_bones(bm, drng, bool(b[2]))
		bm.pop()
	# a bronze shield face-down in the dust and a broken spear: someone came for the lion before Heracles
	var ga := deg_to_rad(188.0)
	var gq := Vector3(c.x + cos(ga) * 8.0, 0.0, c.y + sin(ga) * 8.0)
	gq.y = t.height_at(gq.x, gq.z)
	# (an old aspis lying on its back, tilted on a stone: dull green-brown patina, a darker rim, a dent of rust)
	var patina := Pal.BRONZE_DARK.lerp(Color("5E7458"), 0.45)
	bm.push(Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, -0.22), gq + Vector3(0, 0.1, 0)))
	bm.cyl(Vector3(0, -0.04, 0), 0.07, 0.47, 0.44, 16, patina.darkened(0.25), true, 0.0, patina)
	bm.cyl(Vector3(0, 0.03, 0), 0.08, 0.4, 0.2, 16, patina, true, 0.0, patina.lightened(0.08))
	bm.ring(Vector3(0, 0.035, 0), 0.47, 0.41, 0.035, 16, Pal.BRONZE_DARK.darkened(0.2))
	bm.pop()
	var sp0 := gq + Vector3(0.9, 0.05, -0.5)
	bm.limb(sp0, sp0 + Vector3(1.3, 0.02, 0.35), 0.025, 0.022, 5, Pal.WOOD_DARK)
	bm.limb(sp0 + Vector3(1.55, 0.0, 0.7), sp0 + Vector3(2.3, 0.03, 1.15), 0.024, 0.02, 5, Pal.WOOD_DARK)
	bm.cyl(sp0 + Vector3(2.3, 0.03, 1.15), 0.22, 0.04, 0.0, 4, Pal.BRONZE_DARK)
	_add_mesh(bm.commit(), "CaveBones", false)
	# small stalagmites at the foot of the walls (they are part of the wall: solid)
	var sm := MeshBuilder.new(5154)
	sm.vary = 0.04
	placed = 0
	tries = 0
	while placed < 10 and tries < 200:
		tries += 1
		var a := drng.randf() * TAU
		if absf(angle_difference(a, da)) < 0.45 or absf(angle_difference(a, db)) < 0.32:
			continue
		var r := drng.randf_range(12.9, 13.4)
		var p := Vector3(c.x + cos(a) * r, 0.0, c.y + sin(a) * r)
		if not _clear_of_solids(p, 1.3):
			continue
		p.y = t.height_at(p.x, p.z)
		var s := drng.randf_range(0.4, 0.65)
		sm.push_at(p, drng.randf() * TAU, Vector3.ONE * s)
		ModelsNature.add_stalagmite(sm, drng, 1.0)
		sm.pop()
		_cyl(0.75 * s, 2.0 * s, p)
		placed += 1
	_add_mesh(sm.commit(), "CaveWallStalagmites", false)
	# a shaft of light on the den rock (the lion's throne)
	_den_shaft(outcrops[2] if outcrops.size() > 2 else {})


## True when (x, z) of `p` is `margin` m clear of the columns, the tors and the stalagmites' collision (rough).
func _clear_of_solids(p: Vector3, margin: float) -> bool:
	for i in pillars.size():
		var q: Vector3 = pillars[i]
		if Vector2(p.x - q.x, p.z - q.z).length() < _prof_r(pillar_cols[i], 0.0) + margin:
			return false
	for o: Dictionary in outcrops:
		var oc: Vector3 = o["center"]
		if Vector2(p.x - oc.x, p.z - oc.z).length() < PERCH_R + margin:
			return false
	for cs in body.get_children():
		var sh := (cs as CollisionShape3D).shape if cs is CollisionShape3D else null
		if sh is CylinderShape3D and (sh as CylinderShape3D).height < 3.0:
			var q2 := (cs as CollisionShape3D).position
			if Vector2(p.x - q2.x, p.z - q2.z).length() < (sh as CylinderShape3D).radius + margin * 0.6:
				return false
	return true


## A tor: an outcrop of cave rock by the wall, its outline irregular (a smooth noise round it, the same on every
## course, so its joints run down it like cleavage), stepped in three courses with small ledges, a rounded shoulder
## and a flat top at `h` (the lion stands on it, at least PERCH_TOP_R m round); a few stones fallen at its foot.
## One tone per course (no face-by-face patches). Every part of it is inside the convex hull the collision is built
## from (the sides are walls the lion is stunned against).
func _tor(mb: MeshBuilder, rng2: RandomNumberGenerator, rr: float, h: float, inward: Vector3 = Vector3.RIGHT) -> void:
	var sides := 10
	# (its long axis points into the arena: the lion stands on it facing that way)
	var rot := atan2(-inward.z, inward.x)
	var ph1 := rng2.randf() * TAU
	var ph2 := rng2.randf() * TAU
	# an elongated, angular footprint (a block of rock, not a drum)
	var ex := rng2.randf_range(1.05, 1.1)
	var ang := PackedFloat32Array()
	var rad := PackedFloat32Array()
	for i in sides:
		var aa := TAU * float(i) / float(sides) + rng2.randf_range(-0.16, 0.16)
		ang.append(aa)
		rad.append(1.0 + 0.08 * sin(aa * 2.0 + ph1) + 0.06 * sin(aa * 3.0 + ph2) + rng2.randf_range(-0.07, 0.07))
	# [y, radius factor, tone]: the foot, three courses (each set off a little from the one under it, a ledge at each
	# joint), the shoulder, the top's edge
	var rings := [[-0.35, 1.0, 0], [0.3, 1.03, 0], [0.8, 0.99, 0], [0.84, 1.04, 1], [1.48, 0.99, 1], [1.52, 1.02, 2],
		[h - 0.3, 0.98, 2], [h - 0.1, 0.92, 2], [h, 0.86, 2]]
	var offs := [Vector3.ZERO, Vector3(rng2.randf_range(-0.12, 0.12), 0, rng2.randf_range(-0.12, 0.12)),
		Vector3(rng2.randf_range(-0.12, 0.12), 0, rng2.randf_range(-0.12, 0.12))]
	var tones := [ModelsNature.CAVE_ROCK.lerp(ModelsNature.CAVE_ROCK_LOW, 0.25), ModelsNature.CAVE_ROCK,
		ModelsNature.CAVE_ROCK.lerp(ModelsNature.CAVE_ROCK_TOP, 0.3)]
	var basis := Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(ex, 1.0, 1.0 / ex))
	var pts: Array = []
	for rg: Array in rings:
		var row: Array[Vector3] = []
		var wob := rng2.randf_range(-0.02, 0.02)
		var off: Vector3 = offs[int(rg[2])]
		for i in sides:
			var r: float = rr * float(rg[1]) * (rad[i] + wob)
			row.append(basis * Vector3(cos(ang[i]) * r, 0.0, sin(ang[i]) * r) + off + Vector3(0, float(rg[0]), 0))
		pts.append(row)
	for j in rings.size() - 1:
		var tone: Color = tones[int(rings[j + 1][2])]
		for i in sides:
			var i2 := (i + 1) % sides
			var a0: Vector3 = pts[j][i]
			var a1: Vector3 = pts[j][i2]
			var b0: Vector3 = pts[j + 1][i]
			var b1: Vector3 = pts[j + 1][i2]
			var mid := (a0 + a1 + b0 + b1) * 0.25
			_qn(mb, a0, b0, b1, a1, Vector3(mid.x, 0.0, mid.z), tone)
	# the flat top
	var top: Array = pts[rings.size() - 1]
	var ctop := Vector3(0, h, 0) + (offs[2] as Vector3)
	var top_col := ModelsNature.CAVE_ROCK_TOP.lerp(ModelsNature.LIME_TOP, 0.2)
	for i in sides:
		mb.tri(ctop, top[(i + 1) % sides], top[i], top_col)
	# joints: two dark cracks down the courses
	for k in 2:
		var i := (rng2.randi() % sides)
		var t0: Vector3 = pts[rings.size() - 3][i]
		var b0: Vector3 = pts[1][i]
		var out := Vector3(t0.x, 0, t0.z).normalized() * 0.025
		var sd := Vector3(-out.z, 0, out.x).normalized() * 0.035
		_qn(mb, b0 + out - sd, t0 + out - sd, t0 + out + sd, b0 + out + sd, out, CRACK_COL)
	# stones fallen at its foot, half sunk
	for i in 4:
		var aa := TAU * float(i) / 4.0 + rng2.randf_range(-0.4, 0.4)
		var q := basis * (Vector3(cos(aa), 0.0, sin(aa)) * rr * rng2.randf_range(1.04, 1.12))
		var sr := rng2.randf_range(0.26, 0.4)
		ModelsNature.chunk(mb, rng2, q + Vector3(0, -0.1, 0), sr, sr * 0.8, 6, ModelsNature.CAVE_ROCK, ModelsNature.CAVE_ROCK_LOW, ModelsNature.CAVE_ROCK_TOP)


## Four parallel gouges raked down a column at a lion's shoulder height (it sharpens its claws there): `a` the angle
## round the column (its own frame), `y` the top of the strokes.
func _claw_marks(mb: MeshBuilder, col: Dictionary, a: float, y: float) -> void:
	var rad := _prof_r(col, y)
	for i in 4:
		var off := (float(i) - 1.5) * 0.08 / rad
		var len_k := 1.0 - absf(float(i) - 1.5) * 0.12
		var p0 := Vector2(a + off, y - absf(float(i) - 1.5) * 0.04)
		var p1 := Vector2(a + off + 0.16 / rad, y - 0.62 * len_k)
		var pm := (p0 + p1) * 0.5 + Vector2(0.035 / rad, 0.0)
		_crack_seg(mb, col, p0, pm, 0.02)
		_crack_seg(mb, col, pm, p1, 0.014)


## Claw scratches on the floor: four parallel gouges `length` m along `dir` from `at` (on the floor).
func _floor_claws(mb: MeshBuilder, at: Vector3, dir: Vector3, length: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3(-d.z, 0.0, d.x)
	var gouge := Color("4E413C")
	for i in 4:
		var o := side * (float(i) - 1.5) * 0.1
		var ln := length * (1.0 - absf(float(i) - 1.5) * 0.1)
		var a0 := at + o
		var a1 := at + o + d * ln * 0.5 + side * 0.03
		var a2 := at + o + d * ln
		for seg in [[a0, a1, 0.022], [a1, a2, 0.014]]:
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			var hw: float = seg[2]
			var y0: float = t.height_at(p0.x, p0.z) + 0.012
			var y1: float = t.height_at(p1.x, p1.z) + 0.012
			var q0 := Vector3(p0.x, y0, p0.z)
			var q1 := Vector3(p1.x, y1, p1.z)
			_qn(mb, q0 - side * hw, q1 - side * hw * 0.6, q1 + side * hw * 0.6, q0 + side * hw, Vector3.UP, gouge)


func _den_shaft(o: Dictionary) -> void:
	if o.is_empty():
		return
	var spot: Vector3 = o["spot"]
	var c := L.CAVE_C
	var off := Vector2(spot.x - c.x, spot.z - c.y)
	var yc := lid_under(off.length(), off.angle()) - 0.05
	var top := Vector3(spot.x, yc, spot.z)
	var length := yc - spot.y + 0.4
	var beam := MeshInstance3D.new()
	beam.name = "DenShaft"
	beam.mesh = Materials.cone_mesh(length, 0.8, 2.0, 12)
	beam.material_override = Materials.beam_cone(length, Color(1.0, 0.9, 0.68))
	Materials.set_param(beam, &"intensity", 1.8)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = top
	beam.rotation = Vector3(PI * 0.5, 0, 0)
	world.add_child(beam)
	var mb := MeshBuilder.new(5160)
	var glow := Color(1.0, 0.93, 0.72, 0.5)
	var pts: Array[Vector3] = []
	for k in 6:
		var u := -1.8 + 3.6 * float(k) / 5.0
		pts.append(top + Vector3(u, 0, (0.16 + rng.randf_range(0.0, 0.14)) * (1.0 - absf(u) / 2.2)))
	for k in 6:
		var u := 1.8 - 3.6 * float(k) / 5.0
		pts.append(top + Vector3(u, 0, -(0.16 + rng.randf_range(0.0, 0.14)) * (1.0 - absf(u) / 2.2)))
	for k in range(1, pts.size() - 1):
		mb.tri(pts[0], pts[k + 1], pts[k], glow)
		mb.tri(pts[0], pts[k], pts[k + 1], glow)
	_add_mesh(mb.commit(), "DenCrack", false, false)
	var spot_l := SpotLight3D.new()
	spot_l.name = "DenLight"
	spot_l.light_color = Color(1.0, 0.86, 0.62)
	spot_l.light_energy = 2.4
	spot_l.spot_range = length + 5.0
	spot_l.spot_angle = 11.0
	spot_l.spot_attenuation = 0.0
	spot_l.shadow_enabled = false
	spot_l.light_specular = 0.0
	spot_l.position = top + Vector3(0, -0.3, 0)
	spot_l.rotation = Vector3(-PI * 0.5, 0, 0)
	world.add_child(spot_l)
	lights.append(spot_l)
