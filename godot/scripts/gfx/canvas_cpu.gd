# DACanvasCPU: software rasteriser behind DACanvas canvases created with getContext("2d", {"willReadFrequently":
# true}) (no JS counterpart; engine glue). Chrome also switches such canvases to its CPU backend. Used for small
# canvases whose pixels are read back every frame (Telly's 64x48 dot-matrix mask). Pixels are premultiplied float
# RGBA (canvas._px). Coverage: nonzero/evenodd scanline rasteriser with 4 sub-scanlines per pixel row and exact
# horizontal span coverage. Paints: solid, gradients (ramp), radial/conic, images, patterns. All composite ops.
class_name DACanvasCPU
extends RefCounted

const SUB := 4

# Coverage of polygons over the canvas: returns [x0, y0, w, h, PackedFloat32Array] (empty w/h = nothing).
static func coverage(P: PackedVector2Array, S: PackedInt32Array, evenodd: bool, cw: int, ch: int) -> Array:
	var box := DACanvasGeom.bbox(P)
	var x0 := maxi(0, int(floor(box.position.x)))
	var y0 := maxi(0, int(floor(box.position.y)))
	var x1 := mini(cw, int(ceil(box.end.x)))
	var y1 := mini(ch, int(ceil(box.end.y)))
	var bw := x1 - x0
	var bh := y1 - y0
	var cov := PackedFloat32Array()
	if bw <= 0 or bh <= 0:
		return [0, 0, 0, 0, cov]
	cov.resize(bw * bh)
	# edges
	var ex0 := PackedFloat64Array()
	var ey0 := PackedFloat64Array()
	var ey1 := PackedFloat64Array()
	var esl := PackedFloat64Array()
	var ed := PackedInt32Array()
	var np := S.size()
	for k in np:
		var a := S[k]
		var b := S[k + 1] if k + 1 < np else P.size()
		if b - a < 2:
			continue
		var prev := P[b - 1]
		for i in range(a, b):
			var q := P[i]
			if prev.y != q.y:
				var top := prev if prev.y < q.y else q
				var bot := q if prev.y < q.y else prev
				if bot.y > y0 and top.y < y1:
					ex0.append(top.x)
					ey0.append(top.y)
					ey1.append(bot.y)
					esl.append((bot.x - top.x) / (bot.y - top.y))
					ed.append(1 if prev.y < q.y else -1)
			prev = q
	var ne := ed.size()
	if ne < 2:
		return [0, 0, 0, 0, PackedFloat32Array()]
	var keys := PackedVector2Array()
	keys.resize(ne)
	for i in ne:
		keys[i] = Vector2(ey0[i], i)
	keys.sort()
	var ei := 0
	var active := PackedInt32Array()
	var xs := PackedVector2Array()
	var wsub := 1.0 / SUB
	for py in range(y0, y1):
		var rowOff := (py - y0) * bw
		for s in SUB:
			var sy := py + (s + 0.5) * wsub
			while ei < ne and keys[ei].x <= sy:
				active.append(int(keys[ei].y))
				ei += 1
			var keep := PackedInt32Array()
			xs.resize(0)
			for e in active:
				if ey1[e] > sy:
					keep.append(e)
					if ey0[e] <= sy:
						xs.append(Vector2(ex0[e] + (sy - ey0[e]) * esl[e], ed[e]))
			active = keep
			if xs.size() < 2:
				continue
			xs.sort()
			var w := 0
			var inside := false
			var xa := 0.0
			for c in xs:
				w += int(c.y)
				var now := (w & 1) == 1 if evenodd else w != 0
				if now and not inside:
					xa = c.x
				elif inside and not now:
					_span(cov, rowOff, x0, bw, xa, c.x, wsub)
				inside = now
	return [x0, y0, bw, bh, cov]

static func _span(cov: PackedFloat32Array, rowOff: int, x0: int, bw: int, xa: float, xb: float, wt: float) -> void:
	xa = clampf(xa - x0, 0.0, bw)
	xb = clampf(xb - x0, 0.0, bw)
	if xb <= xa:
		return
	var ia := int(floor(xa))
	var ib := int(floor(xb))
	if ia == ib:
		if ia < bw:
			cov[rowOff + ia] += (xb - xa) * wt
		return
	cov[rowOff + ia] += (ia + 1 - xa) * wt
	for i in range(ia + 1, ib):
		cov[rowOff + i] += wt
	if ib < bw:
		cov[rowOff + ib] += (xb - ib) * wt

# Clip coverage over the whole canvas (w*h), multiplied by the parent clip.
static func clipMask(cv, P: PackedVector2Array, S: PackedInt32Array, evenodd: bool, parent) -> PackedFloat32Array:
	var w: int = cv._w
	var h: int = cv._h
	var m := PackedFloat32Array()
	m.resize(w * h)
	var c := coverage(P, S, evenodd, w, h)
	var bw: int = c[2]
	var bh: int = c[3]
	var cc: PackedFloat32Array = c[4]
	for j in bh:
		for i in bw:
			m[(c[1] + j) * w + c[0] + i] = minf(1.0, cc[j * bw + i])
	if parent != null and not parent.cpu.is_empty():
		for i in w * h:
			m[i] *= parent.cpu[i]
	return m

static func clear(cv, st, P: PackedVector2Array, paint) -> void:
	var c := coverage(P, PackedInt32Array([0]), false, cv._w, cv._h)
	_composite(cv, st, c, paint, 1.0, 6)

static func fill(cv, st, P: PackedVector2Array, S: PackedInt32Array, evenodd: bool, paint) -> void:
	var op: int = st.op
	if op == 0 and S.size() == 1 and P.size() == 4 and int(paint.kind) == 0 and (st.clip == null) and paint.color.a == 1.0 \
			and st.globalAlpha == 1.0 and _coversAll(P, cv._w, cv._h):
		# perf: an opaque solid source-over rect over the whole canvas (the dot-matrix mask clear): every pixel gets
		# coverage 1, so the composite below writes the colour itself (S + d * 0)
		var col: Color = paint.color
		var row := PackedColorArray()
		row.resize(cv._w * cv._h)
		row.fill(Color(col.r, col.g, col.b, 1.0))
		cv._px = row.to_byte_array().to_float32_array()
		cv._hasContent = true
		cv._cpuDirty = true
		DACanvasGPU.markDirty(cv)
		return
	var c := coverage(P, S, evenodd, cv._w, cv._h)
	if DACanvasGPU.NONLOCAL.has(op):
		# non-local ops touch the whole (clipped) canvas: extend the coverage window to the canvas
		var full := PackedFloat32Array()
		full.resize(cv._w * cv._h)
		var bw0: int = c[2]
		for j in int(c[3]):
			for i in bw0:
				full[(c[1] + j) * cv._w + c[0] + i] = c[4][j * bw0 + i]
		c = [0, 0, cv._w, cv._h, full]
	_composite(cv, st, c, paint, st.globalAlpha, op)

# Blends paint over the coverage window with composite op `op` (clip from st).
# P is exactly the axis-aligned rect (0, 0)-(w, h) (any vertex order).
static func _coversAll(P: PackedVector2Array, w: int, h: int) -> bool:
	var fw := float(w)
	var fh := float(h)
	var c0 := 0
	var c1 := 0
	var c2 := 0
	var c3 := 0
	for q in P:
		if q.x == 0.0 and q.y == 0.0:
			c0 += 1
		elif q.x == fw and q.y == 0.0:
			c1 += 1
		elif q.x == fw and q.y == fh:
			c2 += 1
		elif q.x == 0.0 and q.y == fh:
			c3 += 1
		else:
			return false
	return c0 == 1 and c1 == 1 and c2 == 1 and c3 == 1

static func _composite(cv, st, c: Array, paint, alpha: float, op: int) -> void:
	var bx: int = c[0]
	var by: int = c[1]
	var bw: int = c[2]
	var bh: int = c[3]
	if bw <= 0 or bh <= 0:
		return
	var cov: PackedFloat32Array = c[4]
	var W: int = cv._w
	var px: PackedFloat32Array = cv._px
	var clipM := PackedFloat32Array()
	if st.clip != null:
		if st.clip.empty:
			return
		clipM = st.clip.cpu
	var nonlocal := DACanvasGPU.NONLOCAL.has(op)
	if op == 0 and int(paint.kind) == 0 and clipM.is_empty():
		# fast path (solid source-over, no clip: the dot-matrix masks): the loop below with the sampler and _pd
		# inlined, same arithmetic (the premultiplied source is rounded through a Color exactly as there)
		var col: Color = paint.color
		for j in bh:
			var y2 := by + j
			var row := j * bw
			for i in bw:
				var cvv := minf(1.0, cov[row + i])
				if cvv <= 0.0:
					continue
				var sa := col.a * alpha * cvv
				var S := Color(col.r * sa, col.g * sa, col.b * sa, sa)
				var o := ((y2 * W) + bx + i) * 4
				var ia := 1.0 - S.a
				px[o] = S.r + px[o] * ia
				px[o + 1] = S.g + px[o + 1] * ia
				px[o + 2] = S.b + px[o + 2] * ia
				px[o + 3] = S.a + px[o + 3] * ia
		cv._px = px
		cv._hasContent = true
		cv._cpuDirty = true
		DACanvasGPU.markDirty(cv)
		return
	var src := _sampler(paint)
	for j in bh:
		var y := by + j
		for i in bw:
			var cvv := minf(1.0, cov[j * bw + i])
			if cvv <= 0.0 and not nonlocal:
				continue
			var x := bx + i
			var pi := y * W + x
			var cm := 1.0
			if not clipM.is_empty():
				cm = clipM[pi]
				if cm <= 0.0:
					continue
			var s: Color = src.call(Vector2(x + 0.5, y + 0.5)) if cvv > 0.0 else Color(0, 0, 0, 0)
			var sa := s.a * alpha * cvv
			# premultiplied source
			var sr := s.r * sa
			var sg := s.g * sa
			var sb := s.b * sa
			var o := pi * 4
			var dr := px[o]
			var dg := px[o + 1]
			var db := px[o + 2]
			var da := px[o + 3]
			var r := _pd(op, Color(sr, sg, sb, sa), Color(dr, dg, db, da))
			if cm < 1.0:
				r = Color(dr, dg, db, da).lerp(r, cm)
			px[o] = r.r
			px[o + 1] = r.g
			px[o + 2] = r.b
			px[o + 3] = r.a
	cv._px = px
	cv._hasContent = true
	cv._cpuDirty = true
	DACanvasGPU.markDirty(cv)

# Porter-Duff / blend on premultiplied colours.
static func _pd(op: int, s: Color, d: Color) -> Color:
	var sa := s.a
	var da := d.a
	match op:
		0:
			return Color(s.r + d.r * (1.0 - sa), s.g + d.g * (1.0 - sa), s.b + d.b * (1.0 - sa), sa + da * (1.0 - sa))
		1:
			return s * da
		2:
			return s * (1.0 - da)
		3:
			return Color(s.r * da + d.r * (1.0 - sa), s.g * da + d.g * (1.0 - sa), s.b * da + d.b * (1.0 - sa), da)
		4:
			return Color(s.r * (1.0 - da) + d.r, s.g * (1.0 - da) + d.g, s.b * (1.0 - da) + d.b, sa * (1.0 - da) + da)
		5:
			return d * sa
		6:
			return d * (1.0 - sa)
		7:
			return Color(s.r * (1.0 - da) + d.r * sa, s.g * (1.0 - da) + d.g * sa, s.b * (1.0 - da) + d.b * sa, sa)
		8:
			return Color(minf(1.0, s.r + d.r), minf(1.0, s.g + d.g), minf(1.0, s.b + d.b), minf(1.0, sa + da))
		9:
			return s
		10:
			return Color(s.r * (1.0 - da) + d.r * (1.0 - sa), s.g * (1.0 - da) + d.g * (1.0 - sa), s.b * (1.0 - da) + d.b * (1.0 - sa), sa * (1.0 - da) + da * (1.0 - sa))
	# separable blend modes (multiply, screen, overlay, darken, lighten, difference, exclusion…)
	var cs := Color(s.r / sa, s.g / sa, s.b / sa) if sa > 0.0 else Color(0, 0, 0)
	var cb := Color(d.r / da, d.g / da, d.b / da) if da > 0.0 else Color(0, 0, 0)
	var B := Color(_bl(op, cb.r, cs.r), _bl(op, cb.g, cs.g), _bl(op, cb.b, cs.b))
	return Color((1.0 - da) * s.r + (1.0 - sa) * d.r + sa * da * B.r, (1.0 - da) * s.g + (1.0 - sa) * d.g + sa * da * B.g, (1.0 - da) * s.b + (1.0 - sa) * d.b + sa * da * B.b, sa + da - sa * da)

static func _bl(op: int, b: float, s: float) -> float:
	match op:
		11:
			return b * s
		12:
			return b + s - b * s
		13:
			return 2.0 * s * b if b <= 0.5 else 1.0 - 2.0 * (1.0 - s) * (1.0 - b)
		14:
			return minf(b, s)
		15:
			return maxf(b, s)
		16:
			return 0.0 if b == 0.0 else (1.0 if s >= 1.0 else minf(1.0, b / (1.0 - s)))
		17:
			return 1.0 if b >= 1.0 else (0.0 if s <= 0.0 else 1.0 - minf(1.0, (1.0 - b) / s))
		18:
			return 2.0 * s * b if s <= 0.5 else 1.0 - 2.0 * (1.0 - s) * (1.0 - b)
		19:
			if s <= 0.5:
				return b - (1.0 - 2.0 * s) * b * (1.0 - b)
			var dd := ((16.0 * b - 12.0) * b + 4.0) * b if b <= 0.25 else sqrt(b)
			return b + (2.0 * s - 1.0) * (dd - b)
		20:
			return absf(b - s)
		21:
			return b + s - 2.0 * b * s
	return s

# Callable(Vector2 devicePos) -> straight Color of the paint.
static func _sampler(paint) -> Callable:
	match int(paint.kind):
		0:
			var col: Color = paint.color
			return func(_p: Vector2) -> Color: return col
		1:
			if paint.img != null:
				var ramp: Image = paint.img
				var xf: Transform2D = paint.xf
				return func(p: Vector2) -> Color:
					var u: float = (xf * p).x
					return ramp.get_pixel(clampi(int((u - 0.5 / 256.0) * 256.0 + 0.5), 0, 255), 0)
			var im := _imageOf(paint)
			var xf2: Transform2D = paint.xf
			var smooth: bool = paint.smooth
			return func(p: Vector2) -> Color:
				var uv := xf2 * p
				if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
					return Color(0, 0, 0, 0)
				return _sample(im, uv, smooth, false)
		2:
			var ramp2: Image = paint.img
			var xf3: Transform2D = paint.xf
			var a: Vector4 = paint.a
			var b: Vector4 = paint.b
			return func(p: Vector2) -> Color:
				var q := xf3 * p
				var cd := Vector2(b.x - a.x, b.y - a.y)
				var pd := Vector2(q.x - a.x, q.y - a.y)
				var dr := b.z - a.z
				var A := cd.dot(cd) - dr * dr
				var B := pd.dot(cd) + a.z * dr
				var C := pd.dot(pd) - a.z * a.z
				var w := 0.0
				if absf(A) < 1e-9:
					if absf(B) < 1e-12:
						return Color(0, 0, 0, 0)
					w = C / (2.0 * B)
					if a.z + w * dr < 0.0:
						return Color(0, 0, 0, 0)
				else:
					var D := B * B - A * C
					if D < 0.0:
						return Color(0, 0, 0, 0)
					var sq := sqrt(D)
					var t1 := (B + sq) / A
					var t2 := (B - sq) / A
					var hi := maxf(t1, t2)
					var lo := minf(t1, t2)
					if a.z + hi * dr >= 0.0:
						w = hi
					elif a.z + lo * dr >= 0.0:
						w = lo
					else:
						return Color(0, 0, 0, 0)
				return ramp2.get_pixel(clampi(int(clampf(w, 0.0, 1.0) * 255.0 + 0.5), 0, 255), 0)
		3:
			var ramp3: Image = paint.img
			var xf4: Transform2D = paint.xf
			var a3: Vector4 = paint.a
			return func(p: Vector2) -> Color:
				var q := xf4 * p
				var ang := atan2(q.y - a3.y, q.x - a3.x) - a3.z
				var t := fposmod(ang / TAU, 1.0)
				return ramp3.get_pixel(clampi(int(t * 255.0 + 0.5), 0, 255), 0)
		4:
			var im2 := _imageOf(paint)
			var xf5: Transform2D = paint.xf
			var rep: int = paint.rep
			var sm: bool = paint.smooth
			return func(p: Vector2) -> Color:
				var uv := xf5 * p
				if ((rep & 1) == 0 and (uv.x < 0.0 or uv.x > 1.0)) or ((rep & 2) == 0 and (uv.y < 0.0 or uv.y > 1.0)):
					return Color(0, 0, 0, 0)
				if rep & 1:
					uv.x = fposmod(uv.x, 1.0)
				if rep & 2:
					uv.y = fposmod(uv.y, 1.0)
				return _sample(im2, uv, sm, true)
	var none := Color(0, 0, 0, 0)
	return func(_p: Vector2) -> Color: return none

static func _imageOf(paint) -> Image:
	var src = paint.get_meta("src") if paint.has_meta("src") else null
	var im: Image = null
	if src is DACanvas:
		im = (src as DACanvas).toImage()
	elif src is Image:
		im = src
	elif src is Texture2D:
		if src is DACanvas.CanvasTex:
			im = (src as DACanvas.CanvasTex).canvas.toImage()
		else:
			im = (src as Texture2D).get_image()
	if im == null:
		im = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	if im.is_compressed():
		im = im.duplicate()
		im.decompress()
	return im

static func _sample(im: Image, uv: Vector2, smooth: bool, wrap: bool) -> Color:
	var w := im.get_width()
	var h := im.get_height()
	var fx := uv.x * w - 0.5
	var fy := uv.y * h - 0.5
	if not smooth:
		return im.get_pixel(clampi(int(floor(uv.x * w)), 0, w - 1), clampi(int(floor(uv.y * h)), 0, h - 1))
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	var x1 := x0 + 1
	var y1 := y0 + 1
	if wrap:
		x0 = posmod(x0, w); x1 = posmod(x1, w); y0 = posmod(y0, h); y1 = posmod(y1, h)
	else:
		x0 = clampi(x0, 0, w - 1); x1 = clampi(x1, 0, w - 1); y0 = clampi(y0, 0, h - 1); y1 = clampi(y1, 0, h - 1)
	var c00 := im.get_pixel(x0, y0)
	var c10 := im.get_pixel(x1, y0)
	var c01 := im.get_pixel(x0, y1)
	var c11 := im.get_pixel(x1, y1)
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)
