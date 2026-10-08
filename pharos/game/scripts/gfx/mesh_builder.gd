class_name MeshBuilder
extends RefCounted
## Low-poly mesh construction kit. Every triangle gets its own flat normal and a vertex colour, so all models
## share one material (shaders/lowpoly.gdshader). Primitives take an outward-facing CCW description and are
## emitted clockwise, which is Godot's front face. A transform stack lets models be assembled like a hierarchy.
##
## Colour alpha is the material flag documented in lowpoly.gdshader (1 regular, 0.5 self-lit, 0 window).

const SELF_LIT := 0.5
const WINDOW := 0.0

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _xf := Transform3D.IDENTITY
var _stack: Array[Transform3D] = []
var rng := RandomNumberGenerator.new()
## Random per-face brightness variation (0.04 = ±4 %), gives a hand-painted feel.
var vary := 0.0


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


func push(t: Transform3D) -> void:
	_stack.push_back(_xf)
	_xf = _xf * t


func push_at(pos: Vector3, yaw: float = 0.0, scale: Vector3 = Vector3.ONE) -> void:
	push(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), pos))


func pop() -> void:
	_xf = _stack.pop_back()


func is_empty() -> bool:
	return _v.is_empty()


func tri_count() -> int:
	return _v.size() / 3


func _shade(col: Color) -> Color:
	if vary <= 0.0:
		return col
	var k := 1.0 + rng.randf_range(-vary, vary)
	return Color(clampf(col.r * k, 0.0, 1.0), clampf(col.g * k, 0.0, 1.0), clampf(col.b * k, 0.0, 1.0), col.a)


## Triangle a,b,c counter-clockwise when seen from its front.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	a = _xf * a
	b = _xf * b
	c = _xf * c
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var sc := _shade(col)
	_v.append(a)
	_v.append(c)
	_v.append(b)
	for i in 3:
		_n.append(n)
		_c.append(sc)


## World-space triangle (ignores the transform stack). Used by the terrain.
func tri_raw(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	_v.append(a)
	_v.append(c)
	_v.append(b)
	for i in 3:
		_n.append(n)
		_c.append(col)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var sc := _shade(col)
	var keep := vary
	vary = 0.0
	tri(a, b, c, sc)
	tri(a, c, d, sc)
	vary = keep


## Axis-aligned box centred on `c`.
func box(c: Vector3, size: Vector3, col: Color, top_col: Variant = null) -> void:
	var h := size * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var tc: Color = col if top_col == null else top_col
	quad(p[4], p[7], p[6], p[5], tc) # top (+y)
	quad(p[0], p[1], p[2], p[3], col) # bottom (-y)
	quad(p[3], p[2], p[6], p[7], col) # +z
	quad(p[1], p[0], p[4], p[5], col) # -z
	quad(p[2], p[1], p[5], p[6], col) # +x
	quad(p[0], p[3], p[7], p[4], col) # -x


## Box with the bottom at `base` (handy for buildings).
func block(base: Vector3, size: Vector3, col: Color, top_col: Variant = null) -> void:
	box(base + Vector3(0, size.y * 0.5, 0), size, col, top_col)


## Prism / frustum / cone along +Y. r1 = 0 makes a cone.
func cyl(base: Vector3, h: float, r0: float, r1: float, sides: int, col: Color, caps: bool = true, rot: float = 0.0, top_col: Variant = null) -> void:
	var tc: Color = col if top_col == null else top_col
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var a := rot + TAU * float(i) / float(sides)
		var d := Vector3(cos(a), 0, sin(a))
		bot.append(base + d * r0)
		top.append(base + Vector3(0, h, 0) + d * r1)
	for i in sides:
		var j := (i + 1) % sides
		if r1 <= 0.0001:
			tri(bot[i], base + Vector3(0, h, 0), bot[j], col)
		else:
			quad(bot[i], top[i], top[j], bot[j], col)
	if caps:
		var cb := base
		var ct := base + Vector3(0, h, 0)
		for i in sides:
			var j := (i + 1) % sides
			tri(cb, bot[i], bot[j], col)
			if r1 > 0.0001:
				tri(ct, top[j], top[i], tc)


## Surface of revolution around +Y. `profile` entries are Vector2(radius, y) or Vector3(radius, y, z_offset)
## from bottom to top (the ring centre can drift along Z, e.g. a hood tip falling back). `col` is a Color, or a
## Callable(face_centre: Vector3, ring: int, side: int) -> Color for painted regions.
func lathe(profile: Array, sides: int, col: Variant, rot: float = 0.0, cap_bottom: bool = false, cap_top: bool = false) -> void:
	var rings: Array = []
	for e in profile:
		var r: float = e.x
		var y: float = e.y
		var zo: float = e.z if e is Vector3 else 0.0
		var ring: Array[Vector3] = []
		for i in sides:
			var a := rot + TAU * float(i) / float(sides)
			ring.append(Vector3(cos(a) * r, y, sin(a) * r + zo))
		rings.append(ring)
	for j in rings.size() - 1:
		for i in sides:
			var k := (i + 1) % sides
			var a: Vector3 = rings[j][i]
			var b: Vector3 = rings[j + 1][i]
			var c: Vector3 = rings[j + 1][k]
			var d: Vector3 = rings[j][k]
			var fc: Color = col.call((a + b + c + d) * 0.25, j, i) if col is Callable else col
			if a.distance_to(d) < 0.0001:
				tri(a, b, c, fc)
			elif b.distance_to(c) < 0.0001:
				tri(a, b, d, fc)
			else:
				quad(a, b, c, d, fc)
	if cap_bottom:
		var c0: Vector3 = Vector3(0, profile[0].y, profile[0].z if profile[0] is Vector3 else 0.0)
		for i in sides:
			var fc: Color = col.call(c0, -1, i) if col is Callable else col
			tri(c0, rings[0][i], rings[0][(i + 1) % sides], fc)
	if cap_top:
		var last: Variant = profile[profile.size() - 1]
		var c1: Vector3 = Vector3(0, last.y, last.z if last is Vector3 else 0.0)
		var lr: Array = rings[rings.size() - 1]
		for i in sides:
			var fc: Color = col.call(c1, rings.size(), i) if col is Callable else col
			tri(c1, lr[(i + 1) % sides], lr[i], fc)


## Smooth tube along a polyline (sleeves, tails, necks): radii interpolate from r0 to r1.
func tube(points: Array, r0: float, r1: float, sides: int, col: Variant, cap_end: bool = true) -> void:
	var n := points.size()
	if n < 2:
		return
	var prev_ring: Array[Vector3] = []
	var up_hint := Vector3.UP
	for k in n:
		var p: Vector3 = points[k]
		var dir: Vector3
		if k == 0:
			dir = (points[1] - p).normalized()
		elif k == n - 1:
			dir = (p - points[k - 1]).normalized()
		else:
			dir = (points[k + 1] - points[k - 1]).normalized()
		if absf(dir.dot(up_hint)) > 0.95:
			up_hint = Vector3.FORWARD
		var x := dir.cross(up_hint).normalized()
		var z := x.cross(dir).normalized()
		var r := lerpf(r0, r1, float(k) / float(n - 1))
		var ring: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			ring.append(p + (x * cos(a) + z * sin(a)) * r)
		if k > 0:
			var t := float(k) / float(n - 1)
			var fc: Color = col.call(t) if col is Callable else col
			for i in sides:
				var j := (i + 1) % sides
				quad(prev_ring[i], ring[i], ring[j], prev_ring[j], fc)
		prev_ring = ring
	if cap_end and r1 > 0.0001:
		var e: Vector3 = points[n - 1]
		var fc2: Color = col.call(1.0) if col is Callable else col
		for i in sides:
			tri(e, prev_ring[(i + 1) % sides], prev_ring[i], fc2)


## Cylinder between two arbitrary points.
func limb(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, caps: bool = true) -> void:
	var dir := b - a
	var l := dir.length()
	if l < 0.0001:
		return
	var y := dir / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	push(Transform3D(Basis(x, y, z), a))
	cyl(Vector3.ZERO, l, r0, r1, sides, col, caps)
	pop()


## Low-poly sphere (UV) — `rings` >= 2. Squash scales it.
func sphere(c: Vector3, r: float, col: Color, segs: int = 8, rings: int = 5, squash: Vector3 = Vector3.ONE) -> void:
	var pts: Array = []
	for j in rings + 1:
		var row: Array[Vector3] = []
		var phi := PI * float(j) / float(rings)
		for i in segs:
			var th := TAU * float(i) / float(segs)
			row.append(c + Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * r * squash)
		pts.append(row)
	for j in rings:
		for i in segs:
			var k := (i + 1) % segs
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][k]
			var cc: Vector3 = pts[j + 1][k]
			var d: Vector3 = pts[j + 1][i]
			if j == 0:
				tri(a, cc, d, col)
			elif j == rings - 1:
				tri(a, b, d, col)
			else:
				quad(a, b, cc, d, col)


## Icosahedron-based blob: subdiv 0 = 20 faces, 1 = 80 faces. Jitter displaces vertices (rocks, foliage).
func ico(c: Vector3, r: float, col: Color, subdiv: int = 0, jitter: float = 0.0, squash: Vector3 = Vector3.ONE, col_bottom: Variant = null) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	for s in subdiv:
		var cache := {}
		var nf: Array = []
		for f in faces:
			var m: Array[int] = []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					cache[key] = verts.size() - 1
				m.append(cache[key])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		faces = nf
	var pos: Array[Vector3] = []
	for v in verts:
		var k := 1.0 + (rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0)
		pos.append(c + v * r * k * squash)
	for f in faces:
		var a: Vector3 = pos[f[0]]
		var b: Vector3 = pos[f[1]]
		var cc: Vector3 = pos[f[2]]
		var fc := col
		if col_bottom != null and (a.y + b.y + cc.y) / 3.0 < c.y - r * squash.y * 0.25:
			fc = col_bottom
		# icosahedron faces are listed counter-clockwise from outside
		tri(a, b, cc, fc)


## Gable roof: ridge along X. `base` is the centre of the eaves rectangle.
func roof_gable(base: Vector3, w: float, d: float, h: float, col: Color, end_col: Variant = null, thick: float = 0.0) -> void:
	var ec: Color = col if end_col == null else end_col
	var hw := w * 0.5
	var hd := d * 0.5
	var a := base + Vector3(-hw, 0, -hd)
	var b := base + Vector3(hw, 0, -hd)
	var c := base + Vector3(hw, 0, hd)
	var dd := base + Vector3(-hw, 0, hd)
	var r0 := base + Vector3(-hw, h, 0)
	var r1 := base + Vector3(hw, h, 0)
	quad(dd, c, r1, r0, col) # +z slope
	quad(b, a, r0, r1, col) # -z slope
	tri(a, dd, r0, ec) # -x gable
	tri(c, b, r1, ec) # +x gable
	if thick > 0.0:
		quad(a, b, c, dd, col.darkened(0.25))


## Pyramid roof over a square/rectangle.
func roof_pyramid(base: Vector3, w: float, d: float, h: float, col: Color) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var a := base + Vector3(-hw, 0, -hd)
	var b := base + Vector3(hw, 0, -hd)
	var c := base + Vector3(hw, 0, hd)
	var dd := base + Vector3(-hw, 0, hd)
	var apex := base + Vector3(0, h, 0)
	tri(dd, c, apex, col)
	tri(c, b, apex, col)
	tri(b, a, apex, col)
	tri(a, dd, apex, col)
	quad(a, b, c, dd, col.darkened(0.2))


## Flat disc (facing +Y) — n sides.
func disc(c: Vector3, r: float, sides: int, col: Color) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		tri(c, c + Vector3(cos(a1), 0, sin(a1)) * r, c + Vector3(cos(a0), 0, sin(a0)) * r, col)


## Thin plate in the XY plane facing +Z, both sides (banners, wings, fins).
func plate(points: Array, col: Color, double_sided: bool = true) -> void:
	for i in range(1, points.size() - 1):
		tri(points[0], points[i], points[i + 1], col)
		if double_sided:
			tri(points[0], points[i + 1], points[i], col)


## Torus-like ring around +Y (shields' rims, coins).
func ring(c: Vector3, r_out: float, r_in: float, h: float, sides: int, col: Color) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var top := Vector3(0, h, 0)
		quad(c + d0 * r_out, c + d0 * r_out + top, c + d1 * r_out + top, c + d1 * r_out, col)
		quad(c + d1 * r_in, c + d1 * r_in + top, c + d0 * r_in + top, c + d0 * r_in, col)
		quad(c + d0 * r_in + top, c + d1 * r_in + top, c + d1 * r_out + top, c + d0 * r_out + top, col)


func append_builder(other: MeshBuilder) -> void:
	for i in other._v.size():
		_v.append(_xf * other._v[i])
		_n.append((_xf.basis * other._n[i]).normalized())
		_c.append(other._c[i])


func commit(existing: ArrayMesh = null) -> ArrayMesh:
	var m := existing if existing != null else ArrayMesh.new()
	if _v.is_empty():
		return m
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func clear() -> void:
	_v.clear()
	_n.clear()
	_c.clear()
	_xf = Transform3D.IDENTITY
	_stack.clear()
