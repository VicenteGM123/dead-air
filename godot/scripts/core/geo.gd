# Geometry helpers (runtime half of src/core/geo.js; ARCHITECTURE §6): cached primitive builders that reproduce
# three.js's generators vertex for vertex (positions, normals, uvs in three's convention, same index order), fake-AO
# baking (withAO) and the mesh() convenience factory. Use them for meshes the game builds at runtime (FX particles,
# deforming/animated parts); static assets come from Blender (SPEC §4).
# Cached meshes are SHARED: never mutate one you got from here (duplicate it first).
#   roundedBox(w, h, d, r = 0.05, seg = 3)   three/addons RoundedBoxGeometry(w, h, d, seg, r)
#   box(w, h, d)                             BoxGeometry
#   capsule(r, len, cap = 8, rad = 12)       CapsuleGeometry (along Y; total height = len + 2r)
#   cylinder(rt, rb, h, seg = 16)            CylinderGeometry
#   sphere(r, ws = 20, hs = 14)              SphereGeometry
#   torus(r, tube, rs = 10, ts = 24, arc = TAU)  TorusGeometry
#   plane(w, h, sx = 1, sy = 1)              PlaneGeometry (XY plane facing +Z)
#   lathe(points, seg = 24)                  LatheGeometry; points [[radius, y], ...] or Vector2s (bottom to top)
#   tube(points, r, seg = 24, radial = 8, closed = false)  TubeGeometry along a centripetal CatmullRomCurve3
#   withAO(mesh, {y0, y1, strength = 0.45, tint = '#3A2A5A'}) -> cached copy with vertex colours darkening the bottom
#   mesh(geo, mat, {pos, rot, scale, cast = true, receive = true, name}) -> MeshInstance3D (XYZ Euler order)
# Returned meshes are ArrayMesh (one surface). Godot's front faces are clockwise: indices are emitted with the
# second and third vertex swapped so the same triangles face the same way as in three.js.
# Not ported: extrudeShape (static shapes: build them in Blender), mergeByMaterial / mergeRig / skinRig (draw-call
# merging, SPEC §0.2 engine plumbing).
class_name DAGeo

static var _cache := {}

static func _r3(n: float) -> float:
	return roundf(n * 1000.0) / 1000.0

static func _cached(key: String, make: Callable) -> ArrayMesh:
	var g = _cache.get(key)
	if g == null:
		g = make.call()
		g.resource_name = key
		_cache[key] = g
	return g

# three arrays (CCW) -> ArrayMesh (Godot winding).
static func build(pos: PackedVector3Array, nor: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array,
		col: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_TEX_UV] = uv
	if col.size() == pos.size():
		arr[Mesh.ARRAY_COLOR] = col
	if idx.size() > 0:
		var w := PackedInt32Array()
		w.resize(idx.size())
		for i in range(0, idx.size(), 3):
			w[i] = idx[i]
			w[i + 1] = idx[i + 2]
			w[i + 2] = idx[i + 1]
		arr[Mesh.ARRAY_INDEX] = w
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# Non-indexed three triangle list (vertex order a, b, c per triangle, CCW) -> ArrayMesh.
static func _buildTris(pos: PackedVector3Array, nor: PackedVector3Array, uv: PackedVector2Array) -> ArrayMesh:
	var idx := PackedInt32Array()
	idx.resize(pos.size())
	for i in pos.size():
		idx[i] = i
	return build(pos, nor, uv, idx)

# ------------------------------------------------------------------------------------------------ primitives
static func roundedBox(w: float, h: float, d: float, r := 0.05, seg := 3) -> ArrayMesh:
	return _cached("rbox|%s|%s|%s|%s|%d" % [_r3(w), _r3(h), _r3(d), _r3(r), seg], func(): return _roundedBoxGeo(w, h, d, seg, r))

static func box(w: float, h: float, d: float) -> ArrayMesh:
	return _cached("box|%s|%s|%s" % [_r3(w), _r3(h), _r3(d)], func():
		var g := _boxArrays(w, h, d, 1, 1, 1)
		return build(g.pos, g.nor, g.uv, g.idx))

# Capsule along Y; total height = len + 2r.
static func capsule(r: float, len: float, cap := 8, rad := 12) -> ArrayMesh:
	return _cached("caps|%s|%s|%d|%d" % [_r3(r), _r3(len), cap, rad], func(): return _capsuleGeo(r, len, cap, rad, 1))

static func cylinder(rt: float, rb: float, h: float, seg := 16) -> ArrayMesh:
	return _cached("cyl|%s|%s|%s|%d" % [_r3(rt), _r3(rb), _r3(h), seg], func(): return _cylinderGeo(rt, rb, h, seg, 1, false, 0.0, TAU))

static func sphere(r: float, ws := 20, hs := 14) -> ArrayMesh:
	return _cached("sph|%s|%d|%d" % [_r3(r), ws, hs], func(): return _sphereGeo(r, ws, hs, 0.0, TAU, 0.0, PI))

static func torus(r: float, tube_r: float, rs := 10, ts := 24, arc := TAU) -> ArrayMesh:
	return _cached("tor|%s|%s|%d|%d|%s" % [_r3(r), _r3(tube_r), rs, ts, _r3(arc)], func(): return _torusGeo(r, tube_r, rs, ts, arc, 0.0, TAU))

static func plane(w: float, h: float, sx := 1, sy := 1) -> ArrayMesh:
	return _cached("plane|%s|%s|%d|%d" % [_r3(w), _r3(h), sx, sy], func(): return _planeGeo(w, h, sx, sy))

# Lathe around Y. points: [[radius, y], ...] or Vector2[] (bottom to top).
static func lathe(points: Array, seg := 24) -> ArrayMesh:
	var pts: Array = []
	for p in points:
		pts.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	var ka: Array = []
	for p in pts:
		ka.append([p.x, p.y])
	return _cached("lathe|%s|%d" % [JSON.stringify(ka), seg], func(): return _latheGeo(pts, seg, 0.0, TAU))

# Tube through points ([[x,y,z], ...] or Vector3[]) along a Catmull-Rom curve.
static func tube(points: Array, r: float, seg := 24, radial := 8, closed := false) -> ArrayMesh:
	var pts: Array = []
	for p in points:
		pts.append(DAU.v3(p))
	var ka: Array = []
	for p in pts:
		ka.append([p.x, p.y, p.z])
	return _cached("tube|%s|%s|%d|%d|%s" % [JSON.stringify(ka), _r3(r), seg, radial, closed], func(): return _tubeGeo(pts, closed, seg, r, radial))

# ------------------------------------------------------------------------------------------------ fake AO
# Fake AO (GDD §3.5): returns a cached copy of `geometry` with vertex colors darkening its bottom part.
# Use with a material created with { vertexColors:true }. y0/y1 are local heights of the fade band.
static func withAO(geometry: Mesh, opts := {}) -> ArrayMesh:
	var y0 = opts.get("y0")
	var y1 = opts.get("y1")
	var strength := float(opts.get("strength", 0.45))
	var tint = opts.get("tint", "#3A2A5A")
	return _cached("ao|%d|%s|%s|%s|%s" % [geometry.get_instance_id(), y0, y1, strength, tint], func():
		var arr := geometry.surface_get_arrays(0)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bb := geometry.get_aabb()
		var a: float = float(y0) if y0 != null else bb.position.y
		var b: float = float(y1) if y1 != null else bb.position.y + bb.size.y * 0.3
		# THREE.Color lerp happens in linear space; vertex colours are linear
		var t := DAU.color(tint).srgb_to_linear()
		var col := PackedColorArray()
		col.resize(pos.size())
		for i in pos.size():
			var k := 1.0 - DAU.smoothstep3(pos[i].y, a, b)
			var f := k * strength
			col[i] = Color(1.0 + (t.r - 1.0) * f, 1.0 + (t.g - 1.0) * f, 1.0 + (t.b - 1.0) * f, 1.0)
		arr[Mesh.ARRAY_COLOR] = col
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m)

# ------------------------------------------------------------------------------------------------ mesh factory
# Mesh factory. opts: { pos:[x,y,z], rot:[x,y,z], scale:number|[x,y,z], cast=true, receive=true, name }
static func mesh(geo: Mesh, mat: Material, opts := {}) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.rotation_order = EULER_ORDER_XYZ
	m.mesh = geo
	if mat != null:
		m.material_override = mat
	var pos = opts.get("pos")
	var rot = opts.get("rot")
	var sc = opts.get("scale")
	if pos != null:
		m.position = DAU.v3(pos)
	if rot != null:
		m.rotation = DAU.v3(rot)
	if sc != null:
		if sc is float or sc is int:
			m.scale = Vector3.ONE * float(sc)
		else:
			m.scale = DAU.v3(sc)
	var cast = opts.get("cast", true)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# receiveShadow: no per-instance switch in Godot (kept as userData for code that reads it)
	DAU.ud(m)["receiveShadow"] = opts.get("receive", true)
	if opts.get("name") != null:
		m.name = str(opts.name)
	return m

# ================================================================================================ three generators
static func _planeGeo(width: float, height: float, wseg: int, hseg: int) -> ArrayMesh:
	var wh := width / 2.0
	var hh := height / 2.0
	var gx := int(floor(wseg))
	var gy := int(floor(hseg))
	var gx1 := gx + 1
	var gy1 := gy + 1
	var sw := width / gx
	var sh := height / gy
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for iy in gy1:
		var y := iy * sh - hh
		for ix in gx1:
			var x := ix * sw - wh
			pos.append(Vector3(x, -y, 0))
			nor.append(Vector3(0, 0, 1))
			uv.append(Vector2(float(ix) / gx, 1.0 - float(iy) / gy))
	for iy in gy:
		for ix in gx:
			var a := ix + gx1 * iy
			var b := ix + gx1 * (iy + 1)
			var c := (ix + 1) + gx1 * (iy + 1)
			var d := (ix + 1) + gx1 * iy
			idx.append_array([a, b, d, b, c, d])
	return build(pos, nor, uv, idx)

static func _boxArrays(width: float, height: float, depth: float, ws: int, hs: int, ds: int) -> Dictionary:
	var G := {"pos": PackedVector3Array(), "nor": PackedVector3Array(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}
	_boxPlane(G, 2, 1, 0, -1, -1, depth, height, width, ds, hs)     # px
	_boxPlane(G, 2, 1, 0, 1, -1, depth, height, -width, ds, hs)     # nx
	_boxPlane(G, 0, 2, 1, 1, 1, width, depth, height, ws, ds)       # py
	_boxPlane(G, 0, 2, 1, 1, -1, width, depth, -height, ws, ds)     # ny
	_boxPlane(G, 0, 1, 2, 1, -1, width, height, depth, ws, hs)      # pz
	_boxPlane(G, 0, 1, 2, -1, -1, width, height, -depth, ws, hs)    # nz
	return G

static func _boxPlane(G: Dictionary, u: int, v: int, w: int, udir: float, vdir: float, width: float, height: float,
		depth: float, gridX: int, gridY: int) -> void:
	var segW := width / gridX
	var segH := height / gridY
	var wh := width / 2.0
	var hh := height / 2.0
	var dh := depth / 2.0
	var gx1 := gridX + 1
	var gy1 := gridY + 1
	var start: int = G.pos.size()
	for iy in gy1:
		var y := iy * segH - hh
		for ix in gx1:
			var x := ix * segW - wh
			var p := Vector3()
			p[u] = x * udir
			p[v] = y * vdir
			p[w] = dh
			G.pos.append(p)
			var n := Vector3()
			n[w] = 1.0 if depth > 0 else -1.0
			G.nor.append(n)
			G.uv.append(Vector2(float(ix) / gridX, 1.0 - float(iy) / gridY))
	for iy in gridY:
		for ix in gridX:
			var a := start + ix + gx1 * iy
			var b := start + ix + gx1 * (iy + 1)
			var c := start + (ix + 1) + gx1 * (iy + 1)
			var d := start + (ix + 1) + gx1 * iy
			G.idx.append_array([a, b, d, b, c, d])

static func _sphereGeo(radius: float, ws: int, hs: int, phiStart: float, phiLength: float, thetaStart: float, thetaLength: float) -> ArrayMesh:
	ws = maxi(3, ws)
	hs = maxi(2, hs)
	var thetaEnd := minf(thetaStart + thetaLength, PI)
	var index := 0
	var grid: Array = []
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for iy in hs + 1:
		var row: Array = []
		var v := float(iy) / hs
		var uOffset := 0.0
		if iy == 0 and thetaStart == 0.0:
			uOffset = 0.5 / ws
		elif iy == hs and thetaEnd == PI:
			uOffset = -0.5 / ws
		for ix in ws + 1:
			var u := float(ix) / ws
			var p := Vector3(-radius * cos(phiStart + u * phiLength) * sin(thetaStart + v * thetaLength),
				radius * cos(thetaStart + v * thetaLength),
				radius * sin(phiStart + u * phiLength) * sin(thetaStart + v * thetaLength))
			pos.append(p)
			nor.append(p.normalized())
			uv.append(Vector2(u + uOffset, 1.0 - v))
			row.append(index)
			index += 1
		grid.append(row)
	for iy in hs:
		for ix in ws:
			var a: int = grid[iy][ix + 1]
			var b: int = grid[iy][ix]
			var c: int = grid[iy + 1][ix]
			var d: int = grid[iy + 1][ix + 1]
			if iy != 0 or thetaStart > 0.0:
				idx.append_array([a, b, d])
			if iy != hs - 1 or thetaEnd < PI:
				idx.append_array([b, c, d])
	return build(pos, nor, uv, idx)

static func _cylinderGeo(radiusTop: float, radiusBottom: float, height: float, radialSegments: int, heightSegments: int,
		openEnded: bool, thetaStart: float, thetaLength: float) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var index := 0
	var indexArray: Array = []
	var halfHeight := height / 2.0
	var slope := (radiusBottom - radiusTop) / height
	for y in heightSegments + 1:
		var row: Array = []
		var v := float(y) / heightSegments
		var radius := v * (radiusBottom - radiusTop) + radiusTop
		for x in radialSegments + 1:
			var u := float(x) / radialSegments
			var theta := u * thetaLength + thetaStart
			var s := sin(theta)
			var c := cos(theta)
			pos.append(Vector3(radius * s, -v * height + halfHeight, radius * c))
			nor.append(Vector3(s, slope, c).normalized())
			uv.append(Vector2(u, 1.0 - v))
			row.append(index)
			index += 1
		indexArray.append(row)
	for x in radialSegments:
		for y in heightSegments:
			var a: int = indexArray[y][x]
			var b: int = indexArray[y + 1][x]
			var c: int = indexArray[y + 1][x + 1]
			var d: int = indexArray[y][x + 1]
			if radiusTop > 0.0 or y != 0:
				idx.append_array([a, b, d])
			if radiusBottom > 0.0 or y != heightSegments - 1:
				idx.append_array([b, c, d])
	if not openEnded:
		for top in [true, false]:
			var radius: float = radiusTop if top else radiusBottom
			if radius <= 0.0:
				continue
			var sgn := 1.0 if top else -1.0
			var centerStart := index
			for x in range(1, radialSegments + 1):
				pos.append(Vector3(0, halfHeight * sgn, 0))
				nor.append(Vector3(0, sgn, 0))
				uv.append(Vector2(0.5, 0.5))
				index += 1
			var centerEnd := index
			for x in radialSegments + 1:
				var u := float(x) / radialSegments
				var theta := u * thetaLength + thetaStart
				var c := cos(theta)
				var s := sin(theta)
				pos.append(Vector3(radius * s, halfHeight * sgn, radius * c))
				nor.append(Vector3(0, sgn, 0))
				uv.append(Vector2(c * 0.5 + 0.5, s * 0.5 * sgn + 0.5))
				index += 1
			for x in radialSegments:
				var cc := centerStart + x
				var i := centerEnd + x
				if top:
					idx.append_array([i, i + 1, cc])
				else:
					idx.append_array([i + 1, i, cc])
	return build(pos, nor, uv, idx)

static func _capsuleGeo(radius: float, height: float, capSegments: int, radialSegments: int, heightSegments: int) -> ArrayMesh:
	height = maxf(0.0, height)
	capSegments = maxi(1, capSegments)
	radialSegments = maxi(3, radialSegments)
	heightSegments = maxi(1, heightSegments)
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var halfHeight := height / 2.0
	var capArc := (PI / 2.0) * radius
	var total := 2.0 * capArc + height
	var nv := capSegments * 2 + heightSegments
	var vpr := radialSegments + 1
	for iy in nv + 1:
		var arcLen := 0.0
		var profileY := 0.0
		var profileR := 0.0
		var ny := 0.0
		if iy <= capSegments:
			var sp := float(iy) / capSegments
			var ang := (sp * PI) / 2.0
			profileY = -halfHeight - radius * cos(ang)
			profileR = radius * sin(ang)
			ny = -radius * cos(ang)
			arcLen = sp * capArc
		elif iy <= capSegments + heightSegments:
			var sp := float(iy - capSegments) / heightSegments
			profileY = -halfHeight + sp * height
			profileR = radius
			ny = 0.0
			arcLen = capArc + sp * height
		else:
			var sp := float(iy - capSegments - heightSegments) / capSegments
			var ang := (sp * PI) / 2.0
			profileY = halfHeight + radius * sin(ang)
			profileR = radius * cos(ang)
			ny = radius * sin(ang)
			arcLen = capArc + height + sp * capArc
		var v := clampf(arcLen / total, 0.0, 1.0)
		var uOffset := 0.0
		if iy == 0:
			uOffset = 0.5 / radialSegments
		elif iy == nv:
			uOffset = -0.5 / radialSegments
		for ix in radialSegments + 1:
			var u := float(ix) / radialSegments
			var theta := u * PI * 2.0
			var s := sin(theta)
			var c := cos(theta)
			pos.append(Vector3(-profileR * c, profileY, profileR * s))
			nor.append(Vector3(-profileR * c, ny, profileR * s).normalized())
			uv.append(Vector2(u + uOffset, v))
		if iy > 0:
			var prev := (iy - 1) * vpr
			for ix in radialSegments:
				var i1 := prev + ix
				var i2 := prev + ix + 1
				var i3 := iy * vpr + ix
				var i4 := iy * vpr + ix + 1
				idx.append_array([i1, i2, i3, i2, i4, i3])
	return build(pos, nor, uv, idx)

static func _torusGeo(radius: float, tube_r: float, radialSegments: int, tubularSegments: int, arc: float,
		thetaStart: float, thetaLength: float) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in radialSegments + 1:
		var v := thetaStart + (float(j) / radialSegments) * thetaLength
		for i in tubularSegments + 1:
			var u := float(i) / tubularSegments * arc
			var p := Vector3((radius + tube_r * cos(v)) * cos(u), (radius + tube_r * cos(v)) * sin(u), tube_r * sin(v))
			pos.append(p)
			var center := Vector3(radius * cos(u), radius * sin(u), 0.0)
			nor.append((p - center).normalized())
			uv.append(Vector2(float(i) / tubularSegments, float(j) / radialSegments))
	for j in range(1, radialSegments + 1):
		for i in range(1, tubularSegments + 1):
			var a := (tubularSegments + 1) * j + i - 1
			var b := (tubularSegments + 1) * (j - 1) + i - 1
			var c := (tubularSegments + 1) * (j - 1) + i
			var d := (tubularSegments + 1) * j + i
			idx.append_array([a, b, d, b, c, d])
	return build(pos, nor, uv, idx)

static func _latheGeo(points: Array, segments: int, phiStart: float, phiLength: float) -> ArrayMesh:
	phiLength = clampf(phiLength, 0.0, TAU)
	var n := points.size()
	var initN: Array = []
	var prev := Vector3()
	for j in n:
		if j == 0:
			var dx: float = points[1].x - points[0].x
			var dy: float = points[1].y - points[0].y
			var nn := Vector3(dy, -dx, 0.0)
			prev = nn
			initN.append(nn.normalized())
		elif j == n - 1:
			initN.append(prev)
		else:
			var dx: float = points[j + 1].x - points[j].x
			var dy: float = points[j + 1].y - points[j].y
			var nn := Vector3(dy, -dx, 0.0)
			var cur := nn
			nn += prev
			initN.append(nn.normalized())
			prev = cur
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var inv := 1.0 / segments
	for i in segments + 1:
		var phi := phiStart + i * inv * phiLength
		var s := sin(phi)
		var c := cos(phi)
		for j in n:
			pos.append(Vector3(points[j].x * s, points[j].y, points[j].x * c))
			uv.append(Vector2(float(i) / segments, float(j) / (n - 1)))
			var nj: Vector3 = initN[j]
			nor.append(Vector3(nj.x * s, nj.y, nj.x * c))
	for i in segments:
		for j in n - 1:
			var base := j + i * n
			var a := base
			var b := base + n
			var c := base + n + 1
			var d := base + 1
			idx.append_array([a, b, d, c, d, b])
	return build(pos, nor, uv, idx)

# ---- CatmullRomCurve3 (centripetal) + Curve arc-length parametrisation + Frenet frames
static func _crPoint(points: Array, closed: bool, t: float) -> Vector3:
	var l := points.size()
	var p := (l - (0 if closed else 1)) * t
	var intPoint := int(floor(p))
	var weight := p - intPoint
	if closed:
		intPoint += 0 if intPoint > 0 else (int(floor(absi(intPoint) / float(l))) + 1) * l
	elif weight == 0.0 and intPoint == l - 1:
		intPoint = l - 2
		weight = 1.0
	var p0: Vector3
	var p3: Vector3
	if closed or intPoint > 0:
		p0 = points[(intPoint - 1) % l]
	else:
		p0 = points[0] - points[1] + points[0]
	var p1: Vector3 = points[intPoint % l]
	var p2: Vector3 = points[(intPoint + 1) % l]
	if closed or intPoint + 2 < l:
		p3 = points[(intPoint + 2) % l]
	else:
		p3 = points[l - 1] - points[l - 2] + points[l - 1]
	var dt0 := pow(p0.distance_squared_to(p1), 0.25)
	var dt1 := pow(p1.distance_squared_to(p2), 0.25)
	var dt2 := pow(p2.distance_squared_to(p3), 0.25)
	if dt1 < 1e-4:
		dt1 = 1.0
	if dt0 < 1e-4:
		dt0 = dt1
	if dt2 < 1e-4:
		dt2 = dt1
	var out := Vector3()
	for k in 3:
		var x0: float = p0[k]
		var x1: float = p1[k]
		var x2: float = p2[k]
		var x3: float = p3[k]
		var t1 := (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
		var t2 := (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
		t1 *= dt1
		t2 *= dt1
		var c0 := x1
		var c1 := t1
		var c2 := -3.0 * x1 + 3.0 * x2 - 2.0 * t1 - t2
		var c3 := 2.0 * x1 - 2.0 * x2 + t1 + t2
		out[k] = c0 + c1 * weight + c2 * weight * weight + c3 * weight * weight * weight
	return out

static func _crLengths(points: Array, closed: bool, divisions := 200) -> PackedFloat64Array:
	var cache := PackedFloat64Array()
	var last := _crPoint(points, closed, 0.0)
	var sum := 0.0
	cache.append(0.0)
	for p in range(1, divisions + 1):
		var cur := _crPoint(points, closed, float(p) / divisions)
		sum += cur.distance_to(last)
		cache.append(sum)
		last = cur
	return cache

static func _uToT(lengths: PackedFloat64Array, u: float) -> float:
	var il := lengths.size()
	var target := u * lengths[il - 1]
	var low := 0
	var high := il - 1
	var i := 0
	while low <= high:
		i = int(floor(low + (high - low) / 2.0))
		var cmp := lengths[i] - target
		if cmp < 0.0:
			low = i + 1
		elif cmp > 0.0:
			high = i - 1
		else:
			high = i
			break
	i = high
	if lengths[i] == target:
		return float(i) / (il - 1)
	var before := lengths[i]
	var after := lengths[i + 1]
	return (i + (target - before) / (after - before)) / (il - 1)

static func _crTangent(points: Array, closed: bool, t: float) -> Vector3:
	var t1 := maxf(0.0, t - 0.0001)
	var t2 := minf(1.0, t + 0.0001)
	return (_crPoint(points, closed, t2) - _crPoint(points, closed, t1)).normalized()

static func _tubeGeo(points: Array, closed: bool, tubularSegments: int, radius: float, radialSegments: int) -> ArrayMesh:
	var lengths := _crLengths(points, closed)
	var tangents: Array = []
	for i in tubularSegments + 1:
		tangents.append(_crTangent(points, closed, _uToT(lengths, float(i) / tubularSegments)))
	var normals: Array = []
	var binormals: Array = []
	var mn := INF
	var t0: Vector3 = tangents[0]
	var nrm := Vector3()
	if absf(t0.x) <= mn:
		mn = absf(t0.x)
		nrm = Vector3(1, 0, 0)
	if absf(t0.y) <= mn:
		mn = absf(t0.y)
		nrm = Vector3(0, 1, 0)
	if absf(t0.z) <= mn:
		nrm = Vector3(0, 0, 1)
	var vec := t0.cross(nrm).normalized()
	normals.append(t0.cross(vec))
	binormals.append(t0.cross(normals[0]))
	for i in range(1, tubularSegments + 1):
		var n: Vector3 = normals[i - 1]
		vec = (tangents[i - 1] as Vector3).cross(tangents[i])
		if vec.length() > 2.220446049250313e-16:
			vec = vec.normalized()
			var theta := acos(clampf((tangents[i - 1] as Vector3).dot(tangents[i]), -1.0, 1.0))
			n = Basis(vec, theta) * n
		normals.append(n)
		binormals.append((tangents[i] as Vector3).cross(n))
	if closed:
		var theta := acos(clampf((normals[0] as Vector3).dot(normals[tubularSegments]), -1.0, 1.0))
		theta /= tubularSegments
		if (tangents[0] as Vector3).dot((normals[0] as Vector3).cross(normals[tubularSegments])) > 0.0:
			theta = -theta
		for i in range(1, tubularSegments + 1):
			normals[i] = Basis(tangents[i], theta * i) * (normals[i] as Vector3)
			binormals[i] = (tangents[i] as Vector3).cross(normals[i])
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var segs: Array = range(tubularSegments)
	segs.append(tubularSegments if not closed else 0)
	for i in segs:
		var P := _crPoint(points, closed, _uToT(lengths, float(i) / tubularSegments))
		var N: Vector3 = normals[i]
		var B: Vector3 = binormals[i]
		for j in radialSegments + 1:
			var v := float(j) / radialSegments * PI * 2.0
			var s := sin(v)
			var c := -cos(v)
			var nn := (N * c + B * s).normalized()
			nor.append(nn)
			pos.append(P + nn * radius)
	for i in tubularSegments + 1:
		for j in radialSegments + 1:
			uv.append(Vector2(float(i) / tubularSegments, float(j) / radialSegments))
	for j in range(1, tubularSegments + 1):
		for i in range(1, radialSegments + 1):
			var a := (radialSegments + 1) * (j - 1) + (i - 1)
			var b := (radialSegments + 1) * j + (i - 1)
			var c := (radialSegments + 1) * j + i
			var d := (radialSegments + 1) * (j - 1) + i
			idx.append_array([a, b, d, b, c, d])
	return build(pos, nor, uv, idx)

# ---- three/addons RoundedBoxGeometry
static func _rbUv(faceDir: Vector3, normal: Vector3, uvAxis: int, projAxis: int, radius: float, sideLength: float) -> float:
	var totArc := 2.0 * PI * radius / 4.0
	var centerLength := maxf(sideLength - 2.0 * radius, 0.0)
	var halfArc := PI / 4.0
	var tn := normal
	tn[projAxis] = 0.0
	tn = tn.normalized()
	var arcUvRatio := 0.5 * totArc / (totArc + centerLength)
	var ang := acos(clampf(tn.dot(faceDir) / sqrt(tn.length_squared() * faceDir.length_squared()), -1.0, 1.0)) if tn.length_squared() > 0.0 else PI / 2.0
	var arcAngleRatio := 1.0 - (ang / halfArc)
	if signf(tn[uvAxis]) == 1.0:
		return arcAngleRatio * arcUvRatio
	var lenUv := centerLength / (totArc + centerLength)
	return lenUv + arcUvRatio + arcUvRatio * (1.0 - arcAngleRatio)

static func _roundedBoxGeo(width: float, height: float, depth: float, segments: int, radius: float) -> ArrayMesh:
	var total := segments * 2 + 1
	radius = minf(minf(width / 2.0, height / 2.0), minf(depth / 2.0, radius))
	var G := _boxArrays(1, 1, 1, total, total, total)
	if total == 1:
		# three keeps the unit box here (RoundedBoxGeometry with segments 0 returns early)
		return build(G.pos, G.nor, G.uv, G.idx)
	# toNonIndexed()
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var I: PackedInt32Array = G.idx
	for k in I.size():
		pos.append(G.pos[I[k]])
		nor.append(G.nor[I[k]])
		uv.append(G.uv[I[k]])
	var boxv := Vector3(width, height, depth) / 2.0 - Vector3.ONE * radius
	var faceTris := pos.size() * 3 / 6
	var half := 0.5 / total
	for vi in pos.size():
		var p := pos[vi]
		var n := p
		n.x -= signf(n.x) * half
		n.y -= signf(n.y) * half
		n.z -= signf(n.z) * half
		n = n.normalized()
		pos[vi] = Vector3(boxv.x * signf(p.x) + n.x * radius, boxv.y * signf(p.y) + n.y * radius, boxv.z * signf(p.z) + n.z * radius)
		nor[vi] = n
		var side := int(floor(float(vi * 3) / faceTris))
		var u := 0.0
		var v := 0.0
		match side:
			0:
				u = _rbUv(Vector3(1, 0, 0), n, 2, 1, radius, depth)
				v = 1.0 - _rbUv(Vector3(1, 0, 0), n, 1, 2, radius, height)
			1:
				u = 1.0 - _rbUv(Vector3(-1, 0, 0), n, 2, 1, radius, depth)
				v = 1.0 - _rbUv(Vector3(-1, 0, 0), n, 1, 2, radius, height)
			2:
				u = 1.0 - _rbUv(Vector3(0, 1, 0), n, 0, 2, radius, width)
				v = _rbUv(Vector3(0, 1, 0), n, 2, 0, radius, depth)
			3:
				u = 1.0 - _rbUv(Vector3(0, -1, 0), n, 0, 2, radius, width)
				v = 1.0 - _rbUv(Vector3(0, -1, 0), n, 2, 0, radius, depth)
			4:
				u = 1.0 - _rbUv(Vector3(0, 0, 1), n, 0, 1, radius, width)
				v = 1.0 - _rbUv(Vector3(0, 0, 1), n, 1, 0, radius, height)
			5:
				u = _rbUv(Vector3(0, 0, -1), n, 0, 1, radius, width)
				v = 1.0 - _rbUv(Vector3(0, 0, -1), n, 1, 0, radius, height)
		uv[vi] = Vector2(u, v)
	return _buildTris(pos, nor, uv)
