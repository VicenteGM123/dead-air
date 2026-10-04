# DAPath2D: the JS Path2D object for the Canvas 2D emulation (scripts/gfx/canvas2d.gd).
#   var p := DAPath2D.new()                          # new Path2D()
#   var p := DAPath2D.new("M40 60 C120 30 ... Z")    # new Path2D(svgPathData)   (full SVG path grammar)
#   var p := DAPath2D.new(other)                     # new Path2D(otherPath)
#   p.moveTo/lineTo/closePath/quadraticCurveTo/bezierCurveTo/arc/arcTo/ellipse/rect/roundRect/addPath(p2, m?)
#   ctx.fill(p) / ctx.fill(p, "evenodd") / ctx.stroke(p) / ctx.clip(p)
# A Path2D records its commands in its own coordinates; the context replays them through its current transform
# when the path is used (like the JS). DAPath2D.Builder is the device-space flattener shared with the context's
# own current path (points are transformed by the transform current when each command is issued).
class_name DAPath2D
extends RefCounted

enum { M, L, Q, C, ARC, ARCTO, ELL, RECT, RRECT, Z, SUB }

var cmds: Array = []

func _init(src = null) -> void:
	if src is String:
		_parseSvg(src)
	elif src is DAPath2D:
		cmds = src.cmds.duplicate(true)

func moveTo(x: float, y: float) -> void: cmds.append([M, x, y])
func lineTo(x: float, y: float) -> void: cmds.append([L, x, y])
func closePath() -> void: cmds.append([Z])
func quadraticCurveTo(cx: float, cy: float, x: float, y: float) -> void: cmds.append([Q, cx, cy, x, y])
func bezierCurveTo(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> void: cmds.append([C, c1x, c1y, c2x, c2y, x, y])
func arc(x: float, y: float, r: float, a0: float, a1: float, ccw: bool = false) -> void: cmds.append([ARC, x, y, r, a0, a1, ccw])
func arcTo(x1: float, y1: float, x2: float, y2: float, r: float) -> void: cmds.append([ARCTO, x1, y1, x2, y2, r])
func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: bool = false) -> void: cmds.append([ELL, x, y, rx, ry, rot, a0, a1, ccw])
func rect(x: float, y: float, w: float, h: float) -> void: cmds.append([RECT, x, y, w, h])
func roundRect(x: float, y: float, w: float, h: float, radii = 0.0) -> void: cmds.append([RRECT, x, y, w, h, radii])
# addPath(path, transform?) transform: Transform2D or a DOMMatrix-like {a,b,c,d,e,f}.
func addPath(p: DAPath2D, m = null) -> void: cmds.append([SUB, p, DACanvas.toXform(m) if m != null else Transform2D.IDENTITY])

# Replays the commands into a Builder under transform xf.
func replay(b, xf: Transform2D) -> void:
	var saved: Transform2D = b.xf
	b.setXf(xf)
	for c in cmds:
		match int(c[0]):
			M: b.moveTo(c[1], c[2])
			L: b.lineTo(c[1], c[2])
			Q: b.quadraticCurveTo(c[1], c[2], c[3], c[4])
			C: b.bezierCurveTo(c[1], c[2], c[3], c[4], c[5], c[6])
			ARC: b.arc(c[1], c[2], c[3], c[4], c[5], c[6])
			ARCTO: b.arcTo(c[1], c[2], c[3], c[4], c[5])
			ELL: b.ellipse(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
			RECT: b.rect(c[1], c[2], c[3], c[4])
			RRECT: b.roundRect(c[1], c[2], c[3], c[4], c[5])
			Z: b.closePath()
			SUB:
				c[1].replay(b, xf * c[2])
				b.setXf(xf)
	b.setXf(saved)

# ------------------------------------------------------------------------------------------------ SVG path data
func _parseSvg(d: String) -> void:
	var toks := _tokens(d)
	var i := 0
	var cmd := ""
	var cx := 0.0
	var cy := 0.0
	var sx := 0.0
	var sy := 0.0
	var lcx := 0.0   # last control point (for S/T)
	var lcy := 0.0
	var lastCmd := ""
	while i < toks.size():
		var t = toks[i]
		if t is String:
			cmd = t
			i += 1
			if cmd == "Z" or cmd == "z":
				closePath()
				cx = sx
				cy = sy
				lastCmd = cmd
				continue
		elif cmd == "":
			i += 1
			continue
		var rel := cmd == cmd.to_lower()
		var C_ := cmd.to_upper()
		var ox := cx if rel else 0.0
		var oy := cy if rel else 0.0
		match C_:
			"M":
				cx = ox + toks[i]; cy = oy + toks[i + 1]; i += 2
				moveTo(cx, cy)
				sx = cx; sy = cy
				cmd = "l" if rel else "L"   # further pairs are implicit lineTo
			"L":
				cx = ox + toks[i]; cy = oy + toks[i + 1]; i += 2
				lineTo(cx, cy)
			"H":
				cx = ox + toks[i]; i += 1
				lineTo(cx, cy)
			"V":
				cy = oy + toks[i]; i += 1
				lineTo(cx, cy)
			"C":
				var x1: float = ox + toks[i]; var y1: float = oy + toks[i + 1]
				var x2: float = ox + toks[i + 2]; var y2: float = oy + toks[i + 3]
				cx = ox + toks[i + 4]; cy = oy + toks[i + 5]; i += 6
				bezierCurveTo(x1, y1, x2, y2, cx, cy)
				lcx = x2; lcy = y2
			"S":
				var rx1 := cx
				var ry1 := cy
				if lastCmd.to_upper() == "C" or lastCmd.to_upper() == "S":
					rx1 = 2.0 * cx - lcx; ry1 = 2.0 * cy - lcy
				var x2b: float = ox + toks[i]; var y2b: float = oy + toks[i + 1]
				cx = ox + toks[i + 2]; cy = oy + toks[i + 3]; i += 4
				bezierCurveTo(rx1, ry1, x2b, y2b, cx, cy)
				lcx = x2b; lcy = y2b
			"Q":
				var qx: float = ox + toks[i]; var qy: float = oy + toks[i + 1]
				cx = ox + toks[i + 2]; cy = oy + toks[i + 3]; i += 4
				quadraticCurveTo(qx, qy, cx, cy)
				lcx = qx; lcy = qy
			"T":
				var tx := cx
				var ty := cy
				if lastCmd.to_upper() == "Q" or lastCmd.to_upper() == "T":
					tx = 2.0 * cx - lcx; ty = 2.0 * cy - lcy
				cx = ox + toks[i]; cy = oy + toks[i + 1]; i += 2
				quadraticCurveTo(tx, ty, cx, cy)
				lcx = tx; lcy = ty
			"A":
				var arx: float = absf(toks[i]); var ary: float = absf(toks[i + 1]); var phi: float = deg_to_rad(toks[i + 2])
				var fa: bool = toks[i + 3] != 0.0; var fs: bool = toks[i + 4] != 0.0
				var ex: float = ox + toks[i + 5]; var ey: float = oy + toks[i + 6]; i += 7
				_svgArc(cx, cy, arx, ary, phi, fa, fs, ex, ey)
				cx = ex; cy = ey
			_:
				i += 1
		lastCmd = cmd

func _svgArc(x1: float, y1: float, rx: float, ry: float, phi: float, fa: bool, fs: bool, x2: float, y2: float) -> void:
	if (x1 == x2 and y1 == y2):
		return
	if rx == 0.0 or ry == 0.0:
		lineTo(x2, y2)
		return
	var cp := cos(phi)
	var sp := sin(phi)
	var dx := (x1 - x2) / 2.0
	var dy := (y1 - y2) / 2.0
	var x1p := cp * dx + sp * dy
	var y1p := -sp * dx + cp * dy
	var lam := (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lam > 1.0:
		rx *= sqrt(lam)
		ry *= sqrt(lam)
	var num := rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	var den := rx * rx * y1p * y1p + ry * ry * x1p * x1p
	var co := sqrt(maxf(0.0, num / den)) if den > 0.0 else 0.0
	if fa == fs:
		co = -co
	var cxp := co * rx * y1p / ry
	var cyp := -co * ry * x1p / rx
	var ccx := cp * cxp - sp * cyp + (x1 + x2) / 2.0
	var ccy := sp * cxp + cp * cyp + (y1 + y2) / 2.0
	var th1 := atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
	var th2 := atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
	var dth := th2 - th1
	if fs and dth < 0.0:
		dth += TAU
	elif not fs and dth > 0.0:
		dth -= TAU
	ellipse(ccx, ccy, rx, ry, phi, th1, th1 + dth, not fs)

static func _tokens(d: String) -> Array:
	var out: Array = []
	var i := 0
	var n := d.length()
	while i < n:
		var ch := d[i]
		if "MmLlHhVvCcSsQqTtAaZz".contains(ch):
			out.append(ch)
			i += 1
		elif ch == "-" or ch == "+" or ch == "." or (ch >= "0" and ch <= "9"):
			var j := i
			if ch == "-" or ch == "+":
				j += 1
			var dot := false
			var expo := false
			while j < n:
				var c2 := d[j]
				if c2 >= "0" and c2 <= "9":
					j += 1
				elif c2 == "." and not dot and not expo:
					dot = true
					j += 1
				elif (c2 == "e" or c2 == "E") and not expo:
					expo = true
					j += 1
					if j < n and (d[j] == "-" or d[j] == "+"):
						j += 1
				else:
					break
			out.append(float(d.substr(i, j - i)))
			i = j
		else:
			i += 1
	return out


# ================================================================================================ Builder
# Flattens path commands into device-space polylines. xf = transform applied to incoming points; tol = device
# flattening tolerance (px).
class Builder:
	extends RefCounted
	var subs: Array = []           # finished subpaths (PackedVector2Array, device space)
	var closed: Array = []         # bool per finished subpath
	var cur := PackedVector2Array()
	var has := false               # a current subpath exists
	var pending := false           # closePath/rect/roundRect left a start point for the next segment
	var pendingPt := Vector2.ZERO  # (device)
	var startPt := Vector2.ZERO    # device start of the current subpath
	var xf := Transform2D.IDENTITY
	var sc := 1.0                  # max device scale of xf
	var tol := 0.2

	func setXf(t: Transform2D) -> void:
		xf = t
		sc = maxf(t.x.length(), t.y.length())
		if sc <= 0.0:
			sc = 1e-6

	func clear() -> void:
		subs = []
		closed = []
		cur = PackedVector2Array()
		has = false
		pending = false

	func _end() -> void:
		if has and cur.size() > 0:
			subs.append(cur)
			closed.append(false)
		cur = PackedVector2Array()
		has = false

	func _addDev(p: Vector2) -> void:
		var n := cur.size()
		if n > 0:
			var l := cur[n - 1]
			if absf(l.x - p.x) < 1e-7 and absf(l.y - p.y) < 1e-7:
				return
		cur.append(p)

	# Makes sure a subpath exists (starting at user point (x, y) if none and nothing is pending).
	func _ensure(x: float, y: float) -> void:
		if has:
			return
		if pending:
			pending = false
			has = true
			cur = PackedVector2Array([pendingPt])
			startPt = pendingPt
			return
		var p := xf * Vector2(x, y)
		has = true
		cur = PackedVector2Array([p])
		startPt = p

	func moveTo(x: float, y: float) -> void:
		_end()
		pending = false
		var p := xf * Vector2(x, y)
		cur = PackedVector2Array([p])
		has = true
		startPt = p

	func lineTo(x: float, y: float) -> void:
		if not has and not pending:
			moveTo(x, y)
			return
		_ensure(x, y)
		_addDev(xf * Vector2(x, y))

	func closePath() -> void:
		if not has:
			return
		subs.append(cur)
		closed.append(true)
		cur = PackedVector2Array()
		has = false
		pending = true
		pendingPt = startPt

	func lastDev() -> Vector2:
		if has and cur.size() > 0:
			return cur[cur.size() - 1]
		if pending:
			return pendingPt
		return Vector2.ZERO

	func hasPoint() -> bool:
		return (has and cur.size() > 0) or pending

	func quadraticCurveTo(cx: float, cy: float, x: float, y: float) -> void:
		_ensure(cx, cy)
		var p0 := cur[cur.size() - 1]
		var p1 := xf * Vector2(cx, cy)
		var p2 := xf * Vector2(x, y)
		var n := DACanvasGeom.quadSegs(p0, p1, p2, tol)
		for i in range(1, n + 1):
			var t := float(i) / n
			var u := 1.0 - t
			_addDev(p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t))

	func bezierCurveTo(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> void:
		_ensure(c1x, c1y)
		var p0 := cur[cur.size() - 1]
		var p1 := xf * Vector2(c1x, c1y)
		var p2 := xf * Vector2(c2x, c2y)
		var p3 := xf * Vector2(x, y)
		var n := DACanvasGeom.cubicSegs(p0, p1, p2, p3, tol)
		for i in range(1, n + 1):
			var t := float(i) / n
			var u := 1.0 - t
			_addDev(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))

	func arc(x: float, y: float, r: float, a0: float, a1: float, ccw: bool = false) -> void:
		ellipse(x, y, r, r, 0.0, a0, a1, ccw)

	func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw: bool = false) -> void:
		if not (is_finite(x) and is_finite(y) and is_finite(rx) and is_finite(ry) and is_finite(a0) and is_finite(a1)):
			return
		if rx < 0.0 or ry < 0.0:
			push_error("[canvas] IndexSizeError: negative radius")
			return
		var sweepA: float
		if not ccw and a1 - a0 >= TAU:
			sweepA = TAU
		elif ccw and a0 - a1 >= TAU:
			sweepA = -TAU
		elif not ccw:
			sweepA = fmod(a1 - a0, TAU)
			if sweepA < 0.0:
				sweepA += TAU
		else:
			sweepA = -fmod(a0 - a1, TAU)
			if sweepA > 0.0:
				sweepA -= TAU
		var cr := cos(rot)
		var sr := sin(rot)
		var c := Vector2(x, y)
		var p0 := xf * (c + Vector2(cr * rx * cos(a0) - sr * ry * sin(a0), sr * rx * cos(a0) + cr * ry * sin(a0)))
		if has or pending:
			_ensure(0.0, 0.0)
			_addDev(p0)
		else:
			has = true
			cur = PackedVector2Array([p0])
			startPt = p0
		var rdev := maxf(rx, ry) * sc
		var step := DACanvasGeom._arcStep(rdev, tol)
		var n := int(ceil(absf(sweepA) / step))
		if absf(sweepA) >= TAU - 1e-9:
			n = maxi(n, 8)
		if rot == 0.0 and absf(sweepA) >= TAU - 1e-9 and minf(rx, ry) * absf(xf.determinant()) / sc >= 0.3 \
				and (xf * c).length() < 4096.0:
			# fast path (dot matrices draw thousands of circles): the same points as the loop below, built with
			# native array transforms. Full circles only: n >= 8 steps of >= 0.0499 rad on a radius >= 0.3 device px
			# put consecutive points >= 0.015 px apart (far above the f32 spacing at < 4096 px), so _addDev would
			# skip none of them.
			cur.append_array(xf * (Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), c) * _arcOffsets(a0, sweepA, n, rx, ry)))
			return
		for i in range(1, n + 1):
			var a := a0 + sweepA * float(i) / n
			var ca := cos(a) * rx
			var sa := sin(a) * ry
			_addDev(xf * (c + Vector2(cr * ca - sr * sa, sr * ca + cr * sa)))

	# Offsets (cos(a) * rx, sin(a) * ry) of the arc points i = 1..n (a = a0 + sweepA * i / n), cached per arc (the
	# same double expressions as the loop in ellipse(), rounded to Vector2 once).
	static var _offCache := {}
	static func _arcOffsets(a0: float, sweepA: float, n: int, rx: float, ry: float) -> PackedVector2Array:
		var k2 := [a0, sweepA, rx, ry]
		var byN = _offCache.get(n)
		if byN == null:
			byN = {}
			_offCache[n] = byN
		var hit = byN.get(k2)
		if hit != null:
			return hit
		var out := PackedVector2Array()
		out.resize(n)
		for i in range(1, n + 1):
			var a := a0 + sweepA * float(i) / n
			out[i - 1] = Vector2(cos(a) * rx, sin(a) * ry)
		if byN.size() > 4096:
			byN.clear()
		byN[k2] = out
		return out

	func arcTo(x1: float, y1: float, x2: float, y2: float, r: float) -> void:
		if r < 0.0:
			push_error("[canvas] IndexSizeError: negative radius")
			return
		if not hasPoint():
			moveTo(x1, y1)
		var inv := xf.affine_inverse()
		var p0 := inv * lastDev()
		var p1 := Vector2(x1, y1)
		var p2 := Vector2(x2, y2)
		var d0 := p0 - p1
		var d2 := p2 - p1
		var cr0 := d0.x * d2.y - d0.y * d2.x
		if p0.is_equal_approx(p1) or p1.is_equal_approx(p2) or r == 0.0 or absf(cr0) < 1e-12:
			lineTo(x1, y1)
			return
		var l0 := d0.length()
		var l2 := d2.length()
		var u0 := d0 / l0
		var u2 := d2 / l2
		var ang := acos(clampf(u0.dot(u2), -1.0, 1.0))
		var dist := r / tan(ang / 2.0)
		var t0 := p1 + u0 * dist
		var t2 := p1 + u2 * dist
		var bis := (u0 + u2).normalized()
		var cen := p1 + bis * (r / sin(ang / 2.0))
		var aStart := atan2(t0.y - cen.y, t0.x - cen.x)
		var aEnd := atan2(t2.y - cen.y, t2.x - cen.x)
		lineTo(t0.x, t0.y)
		arc(cen.x, cen.y, r, aStart, aEnd, cr0 > 0.0)

	func rect(x: float, y: float, w: float, h: float) -> void:
		moveTo(x, y)
		_addDev(xf * Vector2(x + w, y))
		_addDev(xf * Vector2(x + w, y + h))
		_addDev(xf * Vector2(x, y + h))
		closePath()

	func roundRect(x: float, y: float, w: float, h: float, radii = 0.0) -> void:
		var rs: Array = []
		if radii is Array or radii is PackedFloat32Array or radii is PackedFloat64Array:
			for r in radii:
				rs.append(r)
		else:
			rs.append(radii)
		if rs.is_empty() or rs.size() > 4:
			push_error("[canvas] RangeError: roundRect radii")
			return
		var R: Array = []   # Vector2 per corner: tl tr br bl
		for r in rs:
			if r is Dictionary:
				R.append(Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0))))
			elif r is Vector2:
				R.append(r)
			else:
				R.append(Vector2(float(r), float(r)))
		var tl: Vector2
		var tr: Vector2
		var br: Vector2
		var bl: Vector2
		match R.size():
			1:
				tl = R[0]; tr = R[0]; br = R[0]; bl = R[0]
			2:
				tl = R[0]; br = R[0]; tr = R[1]; bl = R[1]
			3:
				tl = R[0]; tr = R[1]; bl = R[1]; br = R[2]
			_:
				tl = R[0]; tr = R[1]; br = R[2]; bl = R[3]
		for v in [tl, tr, br, bl]:
			if v.x < 0.0 or v.y < 0.0:
				push_error("[canvas] RangeError: negative roundRect radius")
				return
		# negative width/height: mirror the corners (spec steps)
		if w < 0.0:
			x += w
			w = -w
			var t1 := tl; tl = tr; tr = t1
			var t2 := bl; bl = br; br = t2
		if h < 0.0:
			y += h
			h = -h
			var t3 := tl; tl = bl; bl = t3
			var t4 := tr; tr = br; br = t4
		var top := tl.x + tr.x
		var right := tr.y + br.y
		var bottom := br.x + bl.x
		var left := tl.y + bl.y
		var sc2 := 1.0
		if top > w: sc2 = minf(sc2, w / top)
		if right > h: sc2 = minf(sc2, h / right)
		if bottom > w: sc2 = minf(sc2, w / bottom)
		if left > h: sc2 = minf(sc2, h / left)
		if sc2 < 1.0:
			tl *= sc2; tr *= sc2; br *= sc2; bl *= sc2
		moveTo(x + tl.x, y)
		lineTo(x + w - tr.x, y)
		if tr.x > 0.0 and tr.y > 0.0:
			ellipse(x + w - tr.x, y + tr.y, tr.x, tr.y, 0.0, -PI / 2.0, 0.0, false)
		lineTo(x + w, y + h - br.y)
		if br.x > 0.0 and br.y > 0.0:
			ellipse(x + w - br.x, y + h - br.y, br.x, br.y, 0.0, 0.0, PI / 2.0, false)
		lineTo(x + bl.x, y + h)
		if bl.x > 0.0 and bl.y > 0.0:
			ellipse(x + bl.x, y + h - bl.y, bl.x, bl.y, 0.0, PI / 2.0, PI, false)
		lineTo(x, y + tl.y)
		if tl.x > 0.0 and tl.y > 0.0:
			ellipse(x + tl.x, y + tl.y, tl.x, tl.y, 0.0, PI, PI * 1.5, false)
		closePath()
		pendingPt = xf * Vector2(x, y)

	# All subpaths (finished + current) -> [subs, closedFlags]
	func polylines() -> Array:
		var s := subs.duplicate()
		var c := closed.duplicate()
		if has and cur.size() > 0:
			s.append(cur)
			c.append(false)
		return [s, c]

	# Fill geometry: [pts, starts] of every subpath with >= 3 points.
	func geo() -> Array:
		var P := PackedVector2Array()
		var S := PackedInt32Array()
		for sp in subs:
			var p: PackedVector2Array = sp
			if p.size() >= 3:
				S.append(P.size())
				P.append_array(p)
		if has and cur.size() >= 3:
			S.append(P.size())
			P.append_array(cur)
		return [P, S]

	func isEmpty() -> bool:
		return subs.is_empty() and not (has and cur.size() > 0)
