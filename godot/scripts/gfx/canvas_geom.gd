# DACanvasGeom: device-space geometry for the Canvas 2D emulation (no JS counterpart; engine glue for
# scripts/gfx/canvas2d.gd). Everything here is pure CPU math on PackedVector2Array:
#   * "Geo" = polygon list: pts (all vertices, concatenated) + starts (first vertex index of every polygon; the
#     polygon runs to the next start / end of pts). Polygons are implicitly closed.
#   * classify(): convex / simple / complex polygon test (turning number).
#   * stroke(): canvas-exact stroke geometry (butt|round|square caps, miter|round|bevel joins, miterLimit) as a
#     list of convex pieces that all share one orientation (so their nonzero union is the stroke).
#   * dash(): setLineDash splitting.
#   * triangulate(): fan / ear clipping / sweep (trapezoid decomposition with nonzero or evenodd winding,
#     self-intersections and holes) -> [points, indices].
class_name DACanvasGeom
extends RefCounted

const TAU_ := PI * 2.0
const EPS := 1e-9

enum { DEGEN = 0, CONVEX = 1, SIMPLE = 2, COMPLEX = 3 }
enum { CAP_BUTT = 0, CAP_ROUND = 1, CAP_SQUARE = 2 }
enum { JOIN_MITER = 0, JOIN_ROUND = 1, JOIN_BEVEL = 2 }

# ---------------------------------------------------------------------------------------------------- polygons
static func signedArea(p: PackedVector2Array, a: int = 0, b: int = -1) -> float:
	if b < 0:
		b = p.size()
	var n := b - a
	if n < 3:
		return 0.0
	var s := 0.0
	var prev := p[b - 1]
	for i in range(a, b):
		var q := p[i]
		s += prev.x * q.y - q.x * prev.y
		prev = q
	return s * 0.5

# Convex, simple (turning number +-1) or complex (self-intersecting / multiply wound) polygon p[a..b).
static func classify(p: PackedVector2Array, a: int = 0, b: int = -1) -> int:
	if b < 0:
		b = p.size()
	var n := b - a
	if n < 3:
		return DEGEN
	# non-degenerate edge vectors
	var ev := PackedVector2Array()
	for k in n:
		var i := a + k
		var j := a + ((k + 1) % n)
		var d := p[j] - p[i]
		if d.x * d.x + d.y * d.y >= 1e-14:
			ev.append(d)
	var m := ev.size()
	if m < 3:
		return DEGEN
	var turn := 0.0
	var sgn := 0
	var convex := true
	var prevd := ev[m - 1]
	for k in m:
		var d := ev[k]
		var cr := prevd.x * d.y - prevd.y * d.x
		var dt := prevd.x * d.x + prevd.y * d.y
		turn += atan2(cr, dt)
		if absf(cr) > 1e-9 * sqrt((prevd.x * prevd.x + prevd.y * prevd.y) * (d.x * d.x + d.y * d.y)):
			var s := 1 if cr > 0.0 else -1
			if sgn == 0:
				sgn = s
			elif s != sgn:
				convex = false
		elif dt < 0.0:
			convex = false
		prevd = d
	var w := absf(turn) / TAU_
	if w < 0.5:
		return COMPLEX if absf(signedArea(p, a, b)) > 1e-9 else DEGEN
	if absf(w - 1.0) > 0.25:
		return COMPLEX
	return CONVEX if convex else SIMPLE

static func bbox(p: PackedVector2Array, a: int = 0, b: int = -1) -> Rect2:
	if b < 0:
		b = p.size()
	if b <= a:
		return Rect2()
	var mn := p[a]
	var mx := p[a]
	for i in range(a + 1, b):
		var q := p[i]
		if q.x < mn.x: mn.x = q.x
		if q.y < mn.y: mn.y = q.y
		if q.x > mx.x: mx.x = q.x
		if q.y > mx.y: mx.y = q.y
	return Rect2(mn, mx - mn)

# ---------------------------------------------------------------------------------------------------- triangles
# Appends fan triangles of polygon p[a..b) (already offset into the caller's vertex buffer at `base`).
static func fanIndices(idx: PackedInt32Array, base: int, n: int) -> void:
	for i in range(1, n - 1):
		idx.append(base)
		idx.append(base + i)
		idx.append(base + i + 1)

# Triangulates a Geo with the fill rule. Returns [points, indices]. `overlapOk` = the caller does not care if
# triangles of different polygons overlap (opaque paint, overdraw-safe op): every polygon is then triangulated on
# its own (fast) unless the geometry needs winding (holes / evenodd / self-intersection).
static func triangulate(pts: PackedVector2Array, starts: PackedInt32Array, evenodd: bool, overlapOk: bool) -> Array:
	var np := starts.size()
	var outP := PackedVector2Array()
	var outI := PackedInt32Array()
	if np == 0:
		return [outP, outI]
	var needSweep := evenodd and np > 1
	var kinds := PackedInt32Array()
	kinds.resize(np)
	var areaSign := 0
	if not needSweep:
		for k in np:
			var a := starts[k]
			var b := starts[k + 1] if k + 1 < np else pts.size()
			var c := classify(pts, a, b)
			kinds[k] = c
			if c == COMPLEX:
				needSweep = true
				break
			if c != DEGEN and np > 1:
				var s := 1 if signedArea(pts, a, b) > 0.0 else -1
				if areaSign == 0:
					areaSign = s
				elif s != areaSign:
					needSweep = true   # opposite orientations: holes under nonzero
					break
		if not needSweep and np > 1 and not overlapOk:
			if _anyOverlap(pts, starts):
				needSweep = true
	if needSweep:
		var polys: Array = []
		for k in np:
			var a2 := starts[k]
			var b2 := starts[k + 1] if k + 1 < np else pts.size()
			if b2 - a2 >= 3:
				polys.append(pts.slice(a2, b2))
		return sweep(polys, evenodd)
	for k in np:
		var a := starts[k]
		var b := starts[k + 1] if k + 1 < np else pts.size()
		var n := b - a
		if n < 3 or kinds[k] == DEGEN:
			continue
		var base := outP.size()
		if kinds[k] == CONVEX:
			outP.append_array(pts.slice(a, b))
			fanIndices(outI, base, n)
		else:
			var poly := pts.slice(a, b)
			var tri := Geometry2D.triangulate_polygon(poly)
			if tri.is_empty():
				var sw := sweep([poly], false)
				_appendTris(outP, outI, sw[0], sw[1])
				continue
			outP.append_array(poly)
			for t in tri:
				outI.append(base + t)
	return [outP, outI]

static func _appendTris(outP: PackedVector2Array, outI: PackedInt32Array, p: PackedVector2Array, idx: PackedInt32Array) -> void:
	var base := outP.size()
	outP.append_array(p)
	if base == 0:
		outI.append_array(idx)
		return
	for t in idx:
		outI.append(base + t)

# Fan-triangulates every polygon (all known convex: stroke pieces, rects).
static func fanAll(pts: PackedVector2Array, starts: PackedInt32Array) -> Array:
	var outI := PackedInt32Array()
	var np := starts.size()
	for k in np:
		var a := starts[k]
		var b := starts[k + 1] if k + 1 < np else pts.size()
		if b - a >= 3:
			fanIndices(outI, a, b - a)
	return [pts, outI]

# True when the bounding boxes of two polygons of the Geo intersect (sort-and-sweep on x).
static func _anyOverlap(pts: PackedVector2Array, starts: PackedInt32Array) -> bool:
	var np := starts.size()
	if np < 2:
		return false
	var boxes: Array = []
	var keys := PackedVector2Array()
	for k in np:
		var a := starts[k]
		var b := starts[k + 1] if k + 1 < np else pts.size()
		var r := bbox(pts, a, b)
		boxes.append(r)
		keys.append(Vector2(r.position.x, k))
	keys.sort()
	var active: Array = []
	for kv in keys:
		var r: Rect2 = boxes[int(kv.y)]
		var keep: Array = []
		for o in active:
			var q: Rect2 = o
			if q.end.x > r.position.x:
				keep.append(q)
				if q.position.y < r.end.y and r.position.y < q.end.y:
					return true
		keep.append(r)
		active = keep
	return false

static func anyOverlap(pts: PackedVector2Array, starts: PackedInt32Array) -> bool:
	return _anyOverlap(pts, starts)

# ---------------------------------------------------------------------------------------------------- sweep
# Trapezoid decomposition of polygons under the nonzero (or evenodd) rule. Handles holes, overlaps and
# self-intersections. Returns [points, indices] (non-overlapping triangles).
static func sweep(polys: Array, evenodd: bool) -> Array:
	var ex0 := PackedFloat64Array()
	var ey0 := PackedFloat64Array()
	var ex1 := PackedFloat64Array()
	var ey1 := PackedFloat64Array()
	var ew := PackedInt32Array()
	var ys := PackedFloat64Array()
	for poly in polys:
		var p: PackedVector2Array = poly
		var n := p.size()
		if n < 3:
			continue
		var prev := p[n - 1]
		for i in n:
			var q := p[i]
			if prev.y != q.y:
				if prev.y < q.y:
					ex0.append(prev.x); ey0.append(prev.y); ex1.append(q.x); ey1.append(q.y); ew.append(1)
				else:
					ex0.append(q.x); ey0.append(q.y); ex1.append(prev.x); ey1.append(prev.y); ew.append(-1)
				ys.append(q.y)
			prev = q
	var outP := PackedVector2Array()
	var outI := PackedInt32Array()
	var ne := ew.size()
	if ne < 2:
		return [outP, outI]
	ys.sort()
	var uys := PackedFloat64Array()
	for y in ys:
		if uys.is_empty() or y - uys[uys.size() - 1] > 1e-7:
			uys.append(y)
	# edges ordered by top y
	var keys := PackedVector2Array()
	keys.resize(ne)
	for i in ne:
		keys[i] = Vector2(ey0[i], i)
	keys.sort()
	var order := PackedInt32Array()
	order.resize(ne)
	for i in ne:
		order[i] = int(keys[i].y)
	var active := PackedInt32Array()
	var ei := 0
	var yi := 0
	var ya := uys[0]
	var ny := uys.size()
	var xa := PackedFloat64Array()
	var xb := PackedFloat64Array()
	var srt := PackedVector2Array()
	var guard := 0
	while yi < ny - 1:
		guard += 1
		if guard > 200000:
			push_warning("[canvas] sweep guard hit")
			break
		# next event strictly below ya
		while yi < ny and uys[yi] <= ya + 1e-9:
			yi += 1
		if yi >= ny:
			break
		var yb := uys[yi]
		while ei < ne and ey0[order[ei]] <= ya + 1e-9:
			active.append(order[ei])
			ei += 1
		# drop finished edges
		var keep := PackedInt32Array()
		for e in active:
			if ey1[e] > ya + 1e-9:
				keep.append(e)
		active = keep
		var na := active.size()
		if na < 2:
			ya = yb
			continue
		# resolve crossings inside (ya, yb)
		var ok := false
		var tries := 0
		while not ok:
			tries += 1
			xa.resize(na)
			xb.resize(na)
			srt.resize(na)
			for k in na:
				var e := active[k]
				var dy := ey1[e] - ey0[e]
				var sl := (ex1[e] - ex0[e]) / dy
				var x0 := ex0[e] + (ya - ey0[e]) * sl
				var x1 := ex0[e] + (yb - ey0[e]) * sl
				xa[k] = x0
				xb[k] = x1
				srt[k] = Vector2(x0 + x1, k)
			srt.sort()
			ok = true
			if tries > 64:
				break
			var ymin := yb
			for k in range(na - 1):
				var i1 := int(srt[k].y)
				var i2 := int(srt[k + 1].y)
				var da := xa[i1] - xa[i2]
				var db := xb[i1] - xb[i2]
				if da > 1e-7 or db > 1e-7:
					var t := da / (da - db) if absf(da - db) > 1e-15 else 0.5
					var yc := ya + clampf(t, 0.0, 1.0) * (yb - ya)
					if yc > ya + 1e-7 and yc < ymin - 1e-7:
						ymin = yc
			if ymin < yb:
				yb = ymin
				ok = false
		# emit spans
		var w := 0
		var inside := false
		var lk := -1
		for k in na:
			var i3 := int(srt[k].y)
			var e3 := active[i3]
			w += ew[e3]
			var now := (w & 1) == 1 if evenodd else w != 0
			if now and not inside:
				lk = i3
			elif inside and not now:
				var la := xa[lk]
				var lb := xb[lk]
				var ra := xa[i3]
				var rb := xb[i3]
				if ra - la > 1e-9 or rb - lb > 1e-9:
					var base := outP.size()
					outP.append(Vector2(la, ya))
					outP.append(Vector2(ra, ya))
					outP.append(Vector2(rb, yb))
					outP.append(Vector2(lb, yb))
					outI.append(base); outI.append(base + 1); outI.append(base + 2)
					outI.append(base); outI.append(base + 2); outI.append(base + 3)
			inside = now
		ya = yb
	return [outP, outI]

# ---------------------------------------------------------------------------------------------------- dashes
# Splits polylines by a dash pattern (lengths in the same units as the points). Returns [subs, closedFlags]
# with every dash as an open polyline.
static func dash(subs: Array, closed: Array, pattern: PackedFloat64Array, offset: float) -> Array:
	var outS: Array = []
	var outC: Array = []
	var total := 0.0
	for d in pattern:
		total += d
	if total <= 0.0:
		return [subs, closed]
	for si in subs.size():
		var p: PackedVector2Array = subs[si]
		if p.size() < 2:
			continue
		var q := p
		if closed[si]:
			q = p.duplicate()
			q.append(p[0])
		# phase
		var pos := fmod(offset, total)
		if pos < 0.0:
			pos += total
		var di := 0
		while pos >= pattern[di]:
			pos -= pattern[di]
			di = (di + 1) % pattern.size()
		var left := pattern[di] - pos
		var on := (di % 2) == 0
		var cur := PackedVector2Array()
		if on:
			cur.append(q[0])
		for i in range(q.size() - 1):
			var a := q[i]
			var b := q[i + 1]
			var seg := a.distance_to(b)
			var t := 0.0
			while seg - t > left:
				t += left
				var m := a.lerp(b, t / seg) if seg > 0.0 else a
				if on:
					cur.append(m)
					if cur.size() >= 2:
						outS.append(cur)
						outC.append(false)
					cur = PackedVector2Array()
				else:
					cur = PackedVector2Array([m])
				on = not on
				di = (di + 1) % pattern.size()
				left = pattern[di]
			left -= seg - t
			if on:
				cur.append(b)
		if on and cur.size() >= 2:
			outS.append(cur)
			outC.append(false)
	return [outS, outC]

# ---------------------------------------------------------------------------------------------------- stroke
# Stroke geometry of polylines (already flattened) with half width hw. Returns [pts, starts]: convex pieces
# (segment quads, join wedges, caps) that all have NEGATIVE signed area, so the nonzero union of the pieces is
# exactly the stroked area. `tol` = flattening tolerance for round joins/caps (same units as the points).
static func stroke(subs: Array, closed: Array, hw: float, cap: int, join: int, miterLimit: float, tol: float) -> Array:
	var P := PackedVector2Array()
	var S := PackedInt32Array()
	if hw <= 0.0:
		return [P, S]
	var rstep := _arcStep(hw, tol)
	var bevelBelow := sqrt(maxf(0.0, 8.0 * minf(tol, 0.25) / hw))   # joins flatter than this: a bevel is exact enough
	for si in subs.size():
		var p: PackedVector2Array = subs[si]
		var isClosed: bool = closed[si]
		var n := p.size()
		if isClosed and n > 1 and p[0].distance_squared_to(p[n - 1]) < 1e-12:
			p = p.slice(0, n - 1)
			n -= 1
		if n == 0:
			continue
		# zero-length subpath: a dot for round/square caps
		var allSame := true
		for i in range(1, n):
			if p[i].distance_squared_to(p[0]) > 1e-12:
				allSame = false
				break
		if allSame:
			if isClosed:
				continue
			if cap == CAP_ROUND:
				S.append(P.size())
				_circle(P, p[0], hw, rstep)
			elif cap == CAP_SQUARE:
				S.append(P.size())
				P.append(p[0] + Vector2(-hw, -hw)); P.append(p[0] + Vector2(-hw, hw))
				P.append(p[0] + Vector2(hw, hw)); P.append(p[0] + Vector2(hw, -hw))
			continue
		var segs := n if isClosed else n - 1
		var dirs := PackedVector2Array()
		dirs.resize(segs)
		for i in segs:
			var a := p[i]
			var b := p[(i + 1) % n]
			var d := b - a
			var l := d.length()
			dirs[i] = d / l if l > 1e-12 else Vector2.ZERO
		# fill zero-length segment directions from neighbours
		for i in segs:
			if dirs[i] == Vector2.ZERO:
				for k in range(1, segs):
					var j := (i + k) % segs if isClosed else i + k
					if j >= segs:
						break
					if dirs[j] != Vector2.ZERO:
						dirs[i] = dirs[j]
						break
				if dirs[i] == Vector2.ZERO:
					for k in range(1, segs):
						var j2 := i - k
						if j2 < 0:
							break
						if dirs[j2] != Vector2.ZERO:
							dirs[i] = dirs[j2]
							break
		for i in segs:
			var a := p[i]
			var b := p[(i + 1) % n]
			var d := dirs[i]
			var nr := Vector2(-d.y, d.x) * hw
			if a.distance_squared_to(b) > 1e-14:
				S.append(P.size())
				P.append(a + nr); P.append(b + nr); P.append(b - nr); P.append(a - nr)
		# joins
		var jfrom := 0 if isClosed else 1
		var jto := n if isClosed else n - 1
		for v in range(jfrom, jto):
			var d0 := dirs[(v - 1 + segs) % segs]
			var d1 := dirs[v % segs]
			_join(P, S, p[v], d0, d1, hw, join, miterLimit, rstep, bevelBelow)
		# caps
		if not isClosed and cap != CAP_BUTT:
			_cap(P, S, p[0], -dirs[0], hw, cap, rstep)
			_cap(P, S, p[n - 1], dirs[segs - 1], hw, cap, rstep)
	return [P, S]

static func _arcStep(r: float, tol: float) -> float:
	if r <= tol:
		return PI / 2.0
	return clampf(2.0 * acos(clampf(1.0 - tol / r, -1.0, 1.0)), 0.05, PI / 2.0)

# Circle with negative orientation (decreasing angle).
static func _circle(P: PackedVector2Array, c: Vector2, r: float, step: float) -> void:
	var n := maxi(8, int(ceil(TAU_ / step)))
	for i in n:
		var a := -TAU_ * float(i) / n
		P.append(c + Vector2(cos(a), sin(a)) * r)

static func _join(P: PackedVector2Array, S: PackedInt32Array, c: Vector2, d0: Vector2, d1: Vector2, hw: float, join: int, miterLimit: float, rstep: float, bevelBelow: float) -> void:
	var cr := d0.x * d1.y - d0.y * d1.x
	var dt := d0.x * d1.x + d0.y * d1.y
	if absf(cr) < 1e-12 and dt > 0.0:
		return
	var n0 := Vector2(-d0.y, d0.x)
	var n1 := Vector2(-d1.y, d1.x)
	var side := -1.0 if cr > 0.0 else 1.0
	var o0 := n0 * side
	var o1 := n1 * side
	var ang := acos(clampf(dt, -1.0, 1.0))   # turn angle
	var jn := join
	if ang < bevelBelow:
		jn = JOIN_BEVEL
	if jn == JOIN_MITER:
		var den := 1.0 + (o0.x * o1.x + o0.y * o1.y)
		if den < 1e-9:
			jn = JOIN_BEVEL
		else:
			var m := (o0 + o1) / den
			if m.length() > miterLimit:
				jn = JOIN_BEVEL
			else:
				S.append(P.size())
				var q0 := c + o0 * hw
				var q1 := c + m * hw
				var q2 := c + o1 * hw
				_polyNeg(P, [c, q0, q1, q2])
				return
	if jn == JOIN_BEVEL:
		S.append(P.size())
		_polyNeg(P, [c, c + o0 * hw, c + o1 * hw])
		return
	# round: pie wedge from o0 to o1 on the outer side
	var a0 := atan2(o0.y, o0.x)
	# direction from o0 to o1: sign of cross(o0, o1)
	var cz := o0.x * o1.y - o0.y * o1.x
	var sweepA := ang if cz >= 0.0 else -ang
	var cnt := maxi(1, int(ceil(ang / rstep)))
	var arr: Array = [c]
	for i in cnt + 1:
		var a := a0 + sweepA * float(i) / cnt
		arr.append(c + Vector2(cos(a), sin(a)) * hw)
	S.append(P.size())
	_polyNeg(P, arr)

static func _cap(P: PackedVector2Array, S: PackedInt32Array, e: Vector2, d: Vector2, hw: float, cap: int, rstep: float) -> void:
	var nr := Vector2(-d.y, d.x) * hw
	if cap == CAP_SQUARE:
		S.append(P.size())
		_polyNeg(P, [e + nr, e + nr + d * hw, e - nr + d * hw, e - nr])
		return
	# round: half disc on the outward side (from +n through d to -n)
	var a0 := atan2(nr.y, nr.x)
	var ad := atan2(d.y, d.x)
	var sw := PI if _angDiff(ad, a0) > 0.0 else -PI
	var cnt := maxi(2, int(ceil(PI / rstep)))
	var arr: Array = []
	for i in cnt + 1:
		var a := a0 + sw * float(i) / cnt
		arr.append(e + Vector2(cos(a), sin(a)) * hw)
	S.append(P.size())
	_polyNeg(P, arr)

static func _angDiff(a: float, b: float) -> float:
	var d := fmod(a - b, TAU_)
	if d > PI:
		d -= TAU_
	elif d < -PI:
		d += TAU_
	return d

# Appends the polygon with negative signed area.
static func _polyNeg(P: PackedVector2Array, arr: Array) -> void:
	var s := 0.0
	var n := arr.size()
	var prev: Vector2 = arr[n - 1]
	for q in arr:
		s += prev.x * q.y - q.x * prev.y
		prev = q
	if s > 0.0:
		for i in range(n - 1, -1, -1):
			P.append(arr[i])
	else:
		for q in arr:
			P.append(q)

# ---------------------------------------------------------------------------------------------------- curves
# Number of line segments for a quadratic / cubic Bezier (Wang's formula) at tolerance tol.
static func quadSegs(p0: Vector2, p1: Vector2, p2: Vector2, tol: float) -> int:
	var dd := (p0 - p1 * 2.0 + p2).length()
	return clampi(int(ceil(sqrt(dd / (4.0 * tol)))), 1, 256)

static func cubicSegs(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, tol: float) -> int:
	var d1 := (p0 - p1 * 2.0 + p2).length()
	var d2 := (p1 - p2 * 2.0 + p3).length()
	var dd := maxf(d1, d2)
	return clampi(int(ceil(sqrt(0.75 * dd / tol))), 1, 256)
