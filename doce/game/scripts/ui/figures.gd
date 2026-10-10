extends RefCounted
## Black-figure drawings for the labour cards: silhouettes in black glaze with lines incised through to the
## clay, as on an archaic Corinthian or Attic vase. Shapes are closed Catmull-Rom splines through a few control
## points (designed on a 1000 x 560 canvas, ground at y = 540) mapped into the target rectangle.
##   draw_lion(ci, rect, ink, clay)   the Nemean Lion walking right, tail raised
##   draw_hydra(ci, rect, ink, clay)  the Lernaean Hydra: a coiled body and nine necks
##   draw_palmette(ci, base, h, ink, clay), draw_laurel(ci, from, to, ink, leaves), draw_star(ci, c, r, col)

const W := 1000.0
const H := 560.0

## The part of the design canvas mapped into the target rectangle (draw_lion_head narrows it to the head).
static var _view := Rect2(0, 0, 1000, 560)


# --- geometry helpers --------------------------------------------------------------------------------------

## Catmull-Rom through `p` (closed or open), `k` samples per segment.
static func spline(p: PackedVector2Array, closed: bool = true, k: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	if n < 3:
		return p
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = p[(i - 1 + n) % n] if closed or i > 0 else p[0]
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[(i + 1) % n]
		var p3: Vector2 = p[(i + 2) % n] if closed or i + 2 < n else p[n - 1]
		for j in k:
			var t := float(j) / k
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	if not closed:
		out.append(p[n - 1])
	return out


## A tapered stroke along the open spline through `c`: width w0 at the start, w1 at the end. Returns a polygon.
static func stroke(c: PackedVector2Array, w0: float, w1: float, k: int = 8) -> PackedVector2Array:
	var line := spline(c, false, k)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var m := line.size()
	for i in m:
		var a: Vector2 = line[maxi(i - 1, 0)]
		var b: Vector2 = line[mini(i + 1, m - 1)]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		var w := lerpf(w0, w1, float(i) / maxf(1.0, float(m - 1))) * 0.5
		left.append(line[i] + nrm * w)
		right.append(line[i] - nrm * w)
	right.reverse()
	return left + right


static func _map(p: PackedVector2Array, r: Rect2, flip: bool = false) -> PackedVector2Array:
	var s := _scale(r)
	var o := r.position + (r.size - _view.size * s) * 0.5
	var out := PackedVector2Array()
	out.resize(p.size())
	for i in p.size():
		var q: Vector2 = p[i]
		if flip:
			q.x = _view.position.x * 2.0 + _view.size.x - q.x
		out[i] = o + (q - _view.position) * s
	return out


static func _scale(r: Rect2) -> float:
	return minf(r.size.x / _view.size.x, r.size.y / _view.size.y)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3:
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			# A self-touching outline: fall back to its convex parts, drawn as a fan of strips.
			for part in Geometry2D.decompose_polygon_in_convex(pts):
				if (part as PackedVector2Array).size() >= 3:
					ci.draw_colored_polygon(part, col)
			return
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(col)
		ci.draw_polygon(pts, cols)


static func _blob(ci: CanvasItem, r: Rect2, ctrl: Array, col: Color, k: int = 8, flip: bool = false) -> void:
	_poly(ci, _map(spline(PackedVector2Array(ctrl), true, k), r, flip), col)


static func _line(ci: CanvasItem, r: Rect2, ctrl: Array, col: Color, w: float, flip: bool = false) -> void:
	var pts := _map(spline(PackedVector2Array(ctrl), false, 6), r, flip)
	ci.draw_polyline(pts, col, maxf(1.0, w * _scale(r)), true)


## A tapered stroke drawn segment by segment (each quad convex, round joints), so tight curves never fail to
## triangulate.
static func _thick(ci: CanvasItem, r: Rect2, ctrl: Array, w0: float, w1: float, col: Color, flip: bool = false) -> void:
	var line := _map(spline(PackedVector2Array(ctrl), false, 8), r, flip)
	var s := _scale(r)
	var m := line.size()
	var prev_l := Vector2.ZERO
	var prev_r := Vector2.ZERO
	for i in m:
		var a: Vector2 = line[maxi(i - 1, 0)]
		var b: Vector2 = line[mini(i + 1, m - 1)]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		var w := lerpf(w0, w1, float(i) / maxf(1.0, float(m - 1))) * 0.5 * s
		var lp: Vector2 = line[i] + nrm * w
		var rp: Vector2 = line[i] - nrm * w
		if i > 0:
			var cols := PackedColorArray([col, col, col])
			ci.draw_primitive(PackedVector2Array([prev_l, lp, rp]), cols, PackedVector2Array())
			ci.draw_primitive(PackedVector2Array([prev_l, rp, prev_r]), cols, PackedVector2Array())
		ci.draw_circle(line[i], w, col)
		prev_l = lp
		prev_r = rp


# --- the Nemean Lion ---------------------------------------------------------------------------------------

const LION_TORSO := [Vector2(650, 172), Vector2(560, 192), Vector2(470, 196), Vector2(380, 176), Vector2(318, 170),
	Vector2(262, 206), Vector2(252, 270), Vector2(290, 326), Vector2(380, 338), Vector2(470, 326), Vector2(560, 344),
	Vector2(660, 364), Vector2(760, 366), Vector2(800, 320), Vector2(770, 230)]
const LION_MANE := [Vector2(826, 64), Vector2(756, 60), Vector2(694, 90), Vector2(648, 146), Vector2(630, 212),
	Vector2(642, 276), Vector2(684, 334), Vector2(748, 370), Vector2(812, 366), Vector2(852, 324), Vector2(872, 266),
	Vector2(874, 196), Vector2(866, 116)]
## An archaic lion's head: flat crown, heavy brow, a long square muzzle and a deep jaw (no rounded "cartoon" snout).
const LION_HEAD := [Vector2(816, 118), Vector2(850, 92), Vector2(898, 84), Vector2(938, 96), Vector2(962, 118),
	Vector2(984, 134), Vector2(994, 156), Vector2(990, 178), Vector2(966, 194), Vector2(944, 214), Vector2(902, 232),
	Vector2(858, 236), Vector2(822, 214), Vector2(806, 168)]
const LION_EAR := [Vector2(826, 106), Vector2(830, 74), Vector2(860, 78), Vector2(860, 104)]
# legs (closed outlines; far legs are drawn first, behind the body)
const LION_LEG_FAR_FRONT := [Vector2(682, 300), Vector2(734, 304), Vector2(732, 400), Vector2(724, 494), Vector2(748, 518),
	Vector2(748, 541), Vector2(684, 541), Vector2(684, 500), Vector2(680, 400)]
const LION_LEG_NEAR_FRONT := [Vector2(736, 300), Vector2(804, 310), Vector2(812, 384), Vector2(816, 470), Vector2(848, 504),
	Vector2(870, 526), Vector2(864, 541), Vector2(790, 541), Vector2(782, 500), Vector2(766, 422), Vector2(742, 380)]
const LION_LEG_FAR_HIND := [Vector2(300, 262), Vector2(344, 272), Vector2(334, 352), Vector2(286, 440), Vector2(274, 508),
	Vector2(294, 528), Vector2(288, 541), Vector2(228, 541), Vector2(234, 500), Vector2(246, 440), Vector2(288, 354)]
const LION_LEG_NEAR_HIND := [Vector2(256, 236), Vector2(318, 192), Vector2(402, 222), Vector2(424, 302), Vector2(396, 362),
	Vector2(366, 440), Vector2(390, 508), Vector2(408, 526), Vector2(402, 541), Vector2(332, 541), Vector2(326, 500),
	Vector2(330, 440), Vector2(302, 380), Vector2(262, 304)]
const LION_TAIL := [Vector2(272, 200), Vector2(212, 198), Vector2(166, 162), Vector2(150, 106), Vector2(170, 60),
	Vector2(206, 44)]
const LION_TUFT := [Vector2(194, 52), Vector2(214, 22), Vector2(248, 14), Vector2(242, 40), Vector2(216, 62)]
const LION_MANE_C := Vector2(800, 214)


## The mane outline as a ruff of rounded locks: the base spline pushed outwards in `m` scallops.
static func _ruff(scale_k: float, amp: float, m: int) -> PackedVector2Array:
	var base := spline(PackedVector2Array(LION_MANE), true, 10)
	var out := PackedVector2Array()
	var n := base.size()
	for i in n:
		var q: Vector2 = LION_MANE_C + (base[i] - LION_MANE_C) * scale_k
		var radial := (q - LION_MANE_C).normalized()
		var tang: Vector2 = (base[(i + 1) % n] - base[(i - 1 + n) % n]).normalized()
		var u := fposmod(float(i) / n * m, 1.0)
		# one lock: rises slowly, peaks late and drops sharply, like a flame leaning along the ruff
		var lock := pow(u / 0.8, 1.5) if u < 0.8 else (1.0 - u) / 0.2
		out.append(q + radial * amp * lock + tang * amp * 0.4 * lock)
	return out


static func draw_lion(ci: CanvasItem, r: Rect2, ink: Color, clay: Color, flip: bool = false) -> void:
	var s := _scale(r)
	_blob(ci, r, LION_LEG_FAR_FRONT, ink, 6, flip)
	_blob(ci, r, LION_LEG_FAR_HIND, ink, 6, flip)
	_thick(ci, r, LION_TAIL, 26.0, 10.0, ink, flip)
	_blob(ci, r, LION_TUFT, ink, 6, flip)
	_blob(ci, r, LION_TORSO, ink, 8, flip)
	_blob(ci, r, LION_LEG_NEAR_HIND, ink, 6, flip)
	_blob(ci, r, LION_LEG_NEAR_FRONT, ink, 6, flip)
	_poly(ci, _map(_ruff(1.0, 22.0, 15), r, flip), ink)
	_blob(ci, r, LION_HEAD, ink, 8, flip)
	_blob(ci, r, LION_EAR, ink, 4, flip)
	# --- incisions (through the glaze to the clay) ---
	var lw := 2.4
	var inc := Color(clay, 0.95)
	# layered locks: two scalloped lines inside the ruff, behind the head only
	for layer in 2:
		var ring := _ruff(0.8 - 0.2 * layer, 18.0, 13 - 2 * layer)
		var seg := PackedVector2Array()
		for q in ring:
			if q.x < 836.0 - 10.0 * layer and q.y > 70.0:
				seg.append(q)
			elif seg.size() > 1:
				ci.draw_polyline(_map(seg, r, flip), inc, maxf(1.0, lw * 0.85 * s), true)
				seg = PackedVector2Array()
			else:
				seg = PackedVector2Array()
		if seg.size() > 1:
			ci.draw_polyline(_map(seg, r, flip), inc, maxf(1.0, lw * 0.85 * s), true)
	# short strokes down the middle of each outer lock
	var outer := _ruff(1.0, 22.0, 15)
	var nn := outer.size()
	for j in 15:
		var i := int((float(j) + 0.62) / 15.0 * nn) % nn
		var q: Vector2 = outer[i]
		if q.x > 846.0:
			continue
		var dirv := (q - LION_MANE_C).normalized()
		_line(ci, r, [q - dirv * 8.0, q - dirv * 26.0, q - dirv * 40.0 + Vector2(-dirv.y, dirv.x) * 4.0], inc, lw * 0.75, flip)
	# shoulder (the edge of the mane against the body)
	_line(ci, r, [Vector2(690, 100), Vector2(652, 160), Vector2(644, 226), Vector2(664, 292), Vector2(712, 346), Vector2(770, 368)], inc, lw, flip)
	# ribs and belly
	for i in 4:
		var x := 476.0 + i * 34.0
		_line(ci, r, [Vector2(x + 10, 226), Vector2(x, 262), Vector2(x + 8, 300)], inc, lw * 0.8, flip)
	_line(ci, r, [Vector2(420, 324), Vector2(500, 318), Vector2(580, 340), Vector2(650, 352)], inc, lw * 0.8, flip)
	# hind thigh and haunch
	_line(ci, r, [Vector2(398, 232), Vector2(410, 290), Vector2(386, 348), Vector2(360, 384)], inc, lw, flip)
	_line(ci, r, [Vector2(286, 214), Vector2(330, 214), Vector2(362, 244)], inc, lw * 0.8, flip)
	# forearm
	_line(ci, r, [Vector2(784, 330), Vector2(796, 400), Vector2(806, 462)], inc, lw * 0.8, flip)
	# paws: toes
	for paw: Vector2 in [Vector2(832, 541), Vector2(366, 541)]:
		for t in 3:
			var x0: float = paw.x - 14.0 + t * 12.0
			_line(ci, r, [Vector2(x0, paw.y - 22), Vector2(x0 + 2, paw.y - 10), Vector2(x0 + 1, paw.y - 2)], inc, lw * 0.7, flip)
	_lion_face(ci, r, ink, inc, lw, flip)
	_line(ci, r, [Vector2(846, 216), Vector2(872, 226), Vector2(900, 228)], inc, lw * 0.7, flip)
	# tail: a line along it, and the tuft's strands
	_line(ci, r, [Vector2(240, 196), Vector2(190, 176), Vector2(166, 128), Vector2(176, 78)], inc, lw * 0.7, flip)
	_line(ci, r, [Vector2(212, 48), Vector2(236, 28)], inc, lw * 0.7, flip)


## The lion's head and mane alone (a protome, as on a shield or a coin), filling `r`.
static func draw_lion_head(ci: CanvasItem, r: Rect2, ink: Color, clay: Color, flip: bool = false) -> void:
	_view = Rect2(600, 30, 400, 380)
	var s := _scale(r)
	_poly(ci, _map(_ruff(1.0, 22.0, 15), r, flip), ink)
	_blob(ci, r, LION_HEAD, ink, 8, flip)
	_blob(ci, r, LION_EAR, ink, 4, flip)
	var lw := 2.4
	var inc := Color(clay, 0.95)
	for layer in 2:
		var ring := _ruff(0.8 - 0.2 * layer, 18.0, 13 - 2 * layer)
		var seg := PackedVector2Array()
		for q in ring:
			if q.x < 836.0 - 10.0 * layer and q.y > 70.0:
				seg.append(q)
			elif seg.size() > 1:
				ci.draw_polyline(_map(seg, r, flip), inc, maxf(1.0, lw * 0.85 * s), true)
				seg = PackedVector2Array()
			else:
				seg = PackedVector2Array()
		if seg.size() > 1:
			ci.draw_polyline(_map(seg, r, flip), inc, maxf(1.0, lw * 0.85 * s), true)
	_lion_face(ci, r, ink, inc, lw, flip)
	_view = Rect2(0, 0, W, H)


## The face, incised: an almond eye under a heavy brow (the pupil left in glaze), the bridge and the nostril,
## a cheek fold, the closed jaw as one stern line that turns down at its corner, and a few whisker dots.
## Deliberately no curl at the mouth: nothing that could read as a smile.
static func _lion_face(ci: CanvasItem, r: Rect2, ink: Color, inc: Color, lw: float, flip: bool) -> void:
	var s := _scale(r)
	var lid_top := spline(PackedVector2Array([Vector2(890, 136), Vector2(908, 124), Vector2(934, 126)]), false, 6)
	var lid_bot := spline(PackedVector2Array([Vector2(934, 126), Vector2(916, 140), Vector2(890, 136)]), false, 6)
	var almond := PackedVector2Array()
	almond.append_array(lid_top)
	almond.append_array(lid_bot.slice(1))
	_poly(ci, _map(almond, r, flip), inc)
	ci.draw_circle(_map(PackedVector2Array([Vector2(916, 131)]), r, flip)[0], 4.6 * s, ink)
	# brow: a heavy incised ridge, and the line down the bridge of the nose to the nostril
	_line(ci, r, [Vector2(876, 122), Vector2(904, 108), Vector2(940, 110), Vector2(956, 124)], inc, lw * 1.05, flip)
	_line(ci, r, [Vector2(956, 124), Vector2(974, 140), Vector2(986, 150)], inc, lw * 0.8, flip)
	_line(ci, r, [Vector2(978, 150), Vector2(988, 156), Vector2(986, 166)], inc, lw * 0.8, flip)
	# cheek fold under the eye
	_line(ci, r, [Vector2(884, 150), Vector2(880, 178), Vector2(892, 204)], inc, lw * 0.75, flip)
	# the closed jaw: straight back from the lip, a short downward turn at the corner
	_line(ci, r, [Vector2(988, 180), Vector2(962, 186), Vector2(934, 190), Vector2(920, 198)], inc, lw, flip)
	for d: Vector2 in [Vector2(958, 168), Vector2(944, 164), Vector2(970, 170)]:
		ci.draw_circle(_map(PackedVector2Array([d]), r, flip)[0], 2.2 * s, inc)


# --- the Lernaean Hydra ------------------------------------------------------------------------------------

static func draw_hydra(ci: CanvasItem, r: Rect2, ink: Color, clay: Color, flip: bool = false) -> void:
	var s := _scale(r)
	var inc := Color(clay, 0.95)
	# the tail coiling away to the left, the heavy body low on the ground
	_thick(ci, r, [Vector2(520, 522), Vector2(380, 532), Vector2(250, 520), Vector2(168, 470), Vector2(186, 410),
		Vector2(250, 420)], 66.0, 10.0, ink, flip)
	_blob(ci, r, [Vector2(330, 522), Vector2(372, 448), Vector2(492, 404), Vector2(640, 412), Vector2(744, 470),
		Vector2(770, 540), Vector2(560, 546)], ink, 8, flip)
	# scales: rows of small arcs incised on the body
	for row in 3:
		for i in 9:
			var cx := 400.0 + i * 42.0 + (21.0 if row % 2 else 0.0)
			var cy := 462.0 + row * 24.0
			if cx > 730.0 or (row == 0 and (cx < 430.0 or cx > 690.0)):
				continue
			var a0 := _map(PackedVector2Array([Vector2(cx, cy)]), r, flip)[0]
			ci.draw_arc(a0, 14.0 * s, PI * 0.15, PI * 0.85, 8, inc, maxf(1.0, 2.0 * s), true)
	# nine necks fanning out in S-curves, each ending in a wedge-shaped head with an incised eye
	var tips := [Vector2(150, 220), Vector2(232, 122), Vector2(338, 60), Vector2(456, 30), Vector2(574, 36),
		Vector2(690, 66), Vector2(796, 124), Vector2(880, 214), Vector2(512, 176)]
	var roots := [Vector2(420, 446), Vector2(452, 428), Vector2(482, 416), Vector2(512, 410), Vector2(546, 410),
		Vector2(582, 416), Vector2(616, 426), Vector2(652, 442), Vector2(532, 414)]
	for i in tips.size():
		var root: Vector2 = roots[i]
		var tip: Vector2 = tips[i]
		var d := tip - root
		var nrm := Vector2(-d.y, d.x).normalized()
		var bend := (34.0 if i % 2 == 0 else -34.0) * (0.6 if i == 8 else 1.0)
		var c1 := root + d * 0.33 + nrm * bend
		var c2 := root + d * 0.68 - nrm * bend
		_thick(ci, r, [root, c1, c2, tip], 30.0, 15.0, ink, flip)
		var dir := (tip - c2).normalized()
		var n2 := Vector2(-dir.y, dir.x)
		var head := [tip - dir * 8.0 + n2 * 12.0, tip + dir * 18.0 + n2 * 12.0, tip + dir * 40.0 + n2 * 3.0,
			tip + dir * 42.0, tip + dir * 40.0 - n2 * 3.0, tip + dir * 18.0 - n2 * 12.0, tip - dir * 8.0 - n2 * 12.0]
		_poly(ci, _map(PackedVector2Array(head), r, flip), ink)
		var eye := _map(PackedVector2Array([tip + dir * 16.0 + n2 * 4.5]), r, flip)[0]
		ci.draw_circle(eye, 3.6 * s, inc)
		ci.draw_circle(eye, 1.4 * s, ink)
		# a line incised along the neck
		_line(ci, r, [root + d * 0.12 + nrm * bend * 0.3, c1, c2, tip - dir * 10.0], Color(inc, 0.7), 1.4, flip)


# --- ornaments ---------------------------------------------------------------------------------------------

## A palmette (anthemion): a fan of teardrop petals over two volutes, `h` px tall, standing on `base`.
static func draw_palmette(ci: CanvasItem, base: Vector2, h: float, ink: Color, clay: Color) -> void:
	var petals := 9
	var core := base + Vector2(0, -h * 0.24)
	for i in petals:
		var u := float(i) / (petals - 1)
		var a := lerpf(-PI * 0.92, -PI * 0.08, u)
		var len := h * (0.7 - 0.22 * pow(absf(u - 0.5) * 2.0, 1.5))
		var dir := Vector2(cos(a), sin(a))
		var nrm := Vector2(-dir.y, dir.x)
		var wmax := h * 0.062
		var pts := PackedVector2Array()
		for k in 8:
			var t := float(k) / 7.0
			pts.append(core + dir * (h * 0.1 + len * 0.82 * t) + nrm * wmax * (0.25 + 0.75 * t))
		var tip := core + dir * (h * 0.1 + len * 0.82)
		for k in 9:
			var aa := float(k) / 8.0 * PI
			pts.append(tip + dir * sin(aa) * wmax + nrm * cos(aa) * wmax)
		for k in range(7, -1, -1):
			var t := float(k) / 7.0
			pts.append(core + dir * (h * 0.1 + len * 0.82 * t) - nrm * wmax * (0.25 + 0.75 * t))
		ci.draw_colored_polygon(pts, ink)
	# the heart and two volutes
	ci.draw_circle(core, h * 0.11, ink)
	ci.draw_circle(core, h * 0.045, clay)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for k in 22:
			var t := float(k) / 21.0
			var ang := -PI * 0.5 + side * PI * 1.7 * t
			var rr := h * (0.16 - 0.1 * t)
			pts.append(base + Vector2(side * h * 0.16, -h * 0.1) + Vector2(cos(ang) * rr * side, sin(ang) * rr))
		ci.draw_polyline(pts, ink, maxf(1.5, h * 0.034), true)
	ci.draw_line(base + Vector2(-h * 0.05, 0), base + Vector2(h * 0.05, 0), ink, maxf(1.5, h * 0.05), true)


## A laurel sprig from `a` to `b` with paired leaves (victory). `leaves` pairs along the stem.
static func draw_laurel(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, leaves: int = 7, size: float = 14.0) -> void:
	var d := (b - a)
	var len := d.length()
	if len < 1.0:
		return
	var dir := d / len
	var nrm := Vector2(-dir.y, dir.x)
	ci.draw_line(a, b, col, maxf(1.2, size * 0.14), true)
	for i in leaves:
		var t := (float(i) + 0.4) / float(leaves)
		var p := a + d * t
		var sz := size * (1.15 - 0.4 * t)
		for side: float in [-1.0, 1.0]:
			var ax := (dir * 0.8 + nrm * side * 0.6).normalized()
			var ay := Vector2(-ax.y, ax.x)
			var pts := PackedVector2Array()
			for k in 14:
				var u := float(k) / 13.0
				pts.append(p + ax * (sz * 2.4 * u) + ay * sz * 0.5 * sin(PI * u))
			for k in range(12, 0, -1):
				var u := float(k) / 13.0
				pts.append(p + ax * (sz * 2.4 * u) - ay * sz * 0.5 * sin(PI * u))
			ci.draw_colored_polygon(pts, col)
	var tip := PackedVector2Array()
	for k in 14:
		var u := float(k) / 13.0
		tip.append(b + dir * (size * 2.2 * u) + nrm * size * 0.45 * sin(PI * u))
	for k in range(12, 0, -1):
		var u := float(k) / 13.0
		tip.append(b + dir * (size * 2.2 * u) - nrm * size * 0.45 * sin(PI * u))
	ci.draw_colored_polygon(tip, col)


## Four-pointed star / sparkle (rosette filler between figures, as on Corinthian ware).
static func draw_rosette(ci: CanvasItem, c: Vector2, rad: float, ink: Color, clay: Color) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		var nrm := Vector2(-dir.y, dir.x)
		ci.draw_colored_polygon(PackedVector2Array([c + nrm * rad * 0.16, c + dir * rad, c - nrm * rad * 0.16]), ink)
	ci.draw_circle(c, rad * 0.3, ink)
	ci.draw_circle(c, rad * 0.12, clay)
