# DEAD AIR — in-game HUD. GDD §14 (minimal UI, NO hints), ARCHITECTURE §10. Port of src/ui/hud.js.
# Laid out on a 1920x1080 reference stage scaled by viewport height / 1080 (the stage widens with the aspect ratio),
# with a 40 px safe margin. Only these elements exist: crosshair (cream dot + 4 ticks at the real spread cone,
# hitmarker X: white body / gold head / orange kill, tiny star on a headshot kill), telethon TOTE BOARD points (6 amber
# split-flap digits, "+50" labels, red flash on spend, gold during SWEEPS WEEK), TAPE-DECK ammo counter (magazine
# drums big, reserve small, low-magazine red pulse, no weapon names), equipment (4 vacuum tubes = grenades, 3 tiny
# orange TVs = Tiny Teles, grey when empty), WZTV badge ROUND DIAL (spins like a knob and clicks to the new number,
# "–" during the boss), active power-up icons with draining rings (blink the last 5 s), the DYMO-LABEL interact prompt
# ([E], [E] 950, [E] + plug, hold ring, red cost + shake when unaffordable; a round Xbox [X] while playing with the
# pad), the Uplink CHYRON, the Instant Replay bug and the rare flash. "Signal loss": render.post.damage (player.gd
# eases 1 - HP/max; the HUD adds hit pulses), roll / static / chroma hit pulses, an off-screen hit shows a static
# TEAR on that screen edge, and the Big Shot whiteout.
#
# API (game.hud):
#   show() / hide()                  whole HUD (debug cameras)          suppress(key, on)  hide while any key is on
#   flash(text, style)               RARE big moments only              pointsPopup(delta) "+50" / red spend flash
#   hitmarker(head, kill)            X flash + tick                     setPrompt(obj|null) Dymo label (interact.gd)
#        obj = { key:'E'|'X', cost?, plug?, hold?, progress 0..1, denied? }  ('X'/'A'/'B'/'Y' = Xbox glyph)
#   chyron(name, sub?)               Uplink lower third, 2.5 s          replayBug(on)  ◀◀ 13 bug (aliases setReplay(on),
#                                                                        showReplayBug(), hideReplayBug())
#   whiteout(seconds = 1.5, amount = 1)   Big Shot flash via render.post.whiteout, fading over `seconds`
#   glitch(amount = 0.5, seconds = 0.3)   generic signal hit (static + roll + chroma pulse)
#   tear(edge | Vector3)             static tear on 'left'|'right'|'top'|'bottom' (or the edge toward a world position)
#   setCrt(on)                       very light CRT vignette with rounded corners (pause-menu option)
#   reset(), update(dt) (real dt, every state)
# Automatic hookups (callers need nothing else): points:change (popups), points:denied (label shake), zombie:hit /
#   zombie:kill (hitmarkers; duplicates with hitmarker() in the same frame merge), player:hurt (pulse + tear),
#   weapon:fire (crosshair kick), round:start / machine:boss_start (dial), machine:commercial_start/_end (hidden),
#   machine:uplink_take (chyron fallback with the upgraded name if nobody called chyron()), replay events
#   ('perk:replay' {on}, 'replay:start' / 'replay:end'), state (visible only while playing / down).
# Sounds: ticks, flips, prompt click and bzzt are voiced by audio.gd's event hookups; the HUD plays ui_round_dial and
#   the tick for hitmarker() calls without a zombie event (identical plays within 30 ms merge).
# Exports FlipBoard (split-flap digits) and Roller (tape-counter drums) for menu.gd (preload this script).
#
# Godot port notes (engine plumbing, not behaviour): the DOM/CSS tree is a CanvasLayer (layer 10 = the CSS z-index)
# of Controls on the reference stage; every CSS-decorated static box (gradients, rounded corners, inset / drop
# shadows, the inline SVG icons) is rasterized once through Godot's SVG rasterizer from an SVG transcription of its
# CSS (svgTexture(), re-rasterized when the window's pixel density changes); text is drawn with the bundled fonts
# (fonts.gd) and the CSS text-shadows are layered copies; CSS transitions / keyframe animations are evaluated in
# update() with the same durations and cubic-bezier timing functions. The static tear canvas (160x90, putImageData)
# is an ImageTexture updated from a byte buffer; the CRT vignette and the chyron shine are small canvas_item shaders.
# Renames (GDScript built-ins): FlipBoard.set -> set_, Roller.set -> set_.
extends RefCounted

const FontsScript = preload("res://scripts/ui/fonts.gd")
const Hud_ = preload("res://scripts/ui/hud.gd")   # self: inner classes reach the static helpers through it

const REF_H := 1080.0
const M := 40.0 # safe margin (reference px)
const WORLD := ["playing", "down"]
const PU_GLOW := {"cancelled": "#E3662B", "full_reel": "#FFC23A", "one_take": "#FF3B30", "sweeps_week": "#FF4FA0", "gaffer_tape": "#DDE3EA", "please_stand_by": "#EDEDED"}
const HIT_COL := ["#FFFFFF", "#FFFFFF", "#FFD23A", "#FF8A2A", "#FF8A2A"]
const RING_R := 27.0
const PAD_KEYS := ["A", "B", "X", "Y"] # Xbox face buttons the prompt can show
const RING_C := 2.0 * PI * RING_R
const PU_R := 26.0
const PU_C := 2.0 * PI * PU_R
const CREAM := "#F6E7C8" # PAL.cream

static func PU_TOTAL() -> Dictionary:
	return {"one_take": float(Config.T.drops.timed), "sweeps_week": float(Config.T.drops.timed), "please_stand_by": float(Config.T.drops.freeze)}

static func clamp_(x: float, a: float, b: float) -> float:
	return a if x < a else (b if x > b else x)

static func easeOutBack(x: float, k: float = 1.7) -> float:
	return 1.0 + (k + 1.0) * pow(x - 1.0, 3.0) + k * pow(x - 1.0, 2.0)

static func easeOut(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

static func easeIn(x: float) -> float:
	return x * x

# ================================================================================================ CSS helpers
# CSS cubic-bezier(x1, y1, x2, y2) timing function evaluated at progress x (0..1).
static func cubicBezier(x1: float, y1: float, x2: float, y2: float, x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var t := x
	for i in 8:
		var bx := 3.0 * x1 * t * (1.0 - t) * (1.0 - t) + 3.0 * x2 * t * t * (1.0 - t) + t * t * t - x
		var d := 3.0 * x1 * (1.0 - t) * (1.0 - t) + 6.0 * (x2 - x1) * t * (1.0 - t) + 3.0 * (1.0 - x2) * t * t
		if absf(bx) < 1e-5:
			break
		if absf(d) < 1e-6:
			break
		t = clampf(t - bx / d, 0.0, 1.0)
	return 3.0 * y1 * t * (1.0 - t) * (1.0 - t) + 3.0 * y2 * t * t * (1.0 - t) + t * t * t

static func cssEase(x: float) -> float:        # 'ease'
	return cubicBezier(0.25, 0.1, 0.25, 1.0, x)

static func cssEaseInOut(x: float) -> float:   # 'ease-in-out'
	return cubicBezier(0.42, 0.0, 0.58, 1.0, x)

static func cssEaseOut(x: float) -> float:     # 'ease-out'
	return cubicBezier(0.0, 0.0, 0.58, 1.0, x)

# CSS keyframes 0%/100% at `a`, `mid` at `at` (0..1), per-segment timing `fn` (Callable of progress), time t in periods.
static func keyframe2(p: float, a: float, mid: float, at: float, fn: Callable) -> float:
	p = p - floorf(p)
	if p < at:
		return lerpf(a, mid, fn.call(p / at))
	return lerpf(mid, a, fn.call((p - at) / (1.0 - at)))

# `animation: <name> <period> steps(2) infinite` with keyframes { 50% { opacity: lo } } (dhblink).
static func stepsBlink(t: float, period: float, lo: float) -> float:
	var p := fmod(t, period) / period
	if p < 0.5:
		return lerpf(1.0, lo, floorf(p / 0.5 * 2.0) / 2.0)
	return lerpf(lo, 1.0, floorf((p - 0.5) / 0.5 * 2.0) / 2.0)

# ------------------------------------------------------------------------------------------------ SVG rasterizing
static var svgScale := 1.0              # device pixels per reference px (re-rasterize when it changes)
static var _svgCache := {}

static func setSvgScale(k: float) -> bool:
	k = clampf(snappedf(k, 0.25), 1.0, 4.0)
	if is_equal_approx(k, svgScale):
		return false
	svgScale = k
	_svgCache.clear()
	return true

# SVG markup -> texture (cached per markup and scale). The SVG is authored in CSS px (width/height/viewBox).
static func svgTexture(svg: String) -> Texture2D:
	if _svgCache.has(svg):
		return _svgCache[svg]
	var img := Image.new()
	var err := img.load_svg_from_string(svg, svgScale)
	var tex: Texture2D = null
	if err == OK and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
	_svgCache[svg] = tex
	return tex

static func n_(v: float) -> String:
	return String.num(v, 3)

# A document covering (x0, y0, w, h) in CSS px.
static func svgDoc(x0: float, y0: float, w: float, h: float, body: String, defs: String = "") -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%s %s %s %s"><defs>%s</defs>%s</svg>' % [n_(w), n_(h), n_(x0), n_(y0), n_(w), n_(h), defs, body]

# CSS colour -> [hex, alpha] for stop-color / fill + *-opacity.
static func cssCol(c: String) -> Array:
	var col := DAU.color(c)
	return ["#" + col.to_html(false), col.a]

static func fillAttr(c: String, attr: String = "fill") -> String:
	var cc := cssCol(c)
	return '%s="%s" %s-opacity="%s"' % [attr, cc[0], attr, n_(cc[1])]

# Rounded rect path; r = float or [tl, tr, br, bl] (CSS radii, clamped like CSS when they do not fit).
static func rrd(x: float, y: float, w: float, h: float, r) -> String:
	var tl: float
	var tr: float
	var br: float
	var bl: float
	if r is Array:
		tl = r[0]; tr = r[1]; br = r[2]; bl = r[3]
	else:
		tl = float(r); tr = tl; br = tl; bl = tl
	tl = maxf(0.0, tl); tr = maxf(0.0, tr); br = maxf(0.0, br); bl = maxf(0.0, bl)
	var f := 1.0
	if tl + tr > w: f = minf(f, w / (tl + tr))
	if bl + br > w: f = minf(f, w / (bl + br))
	if tl + bl > h: f = minf(f, h / (tl + bl))
	if tr + br > h: f = minf(f, h / (tr + br))
	tl *= f; tr *= f; br *= f; bl *= f
	var s := "M%s %sH%s" % [n_(x + tl), n_(y), n_(x + w - tr)]
	if tr > 0.0: s += "A%s %s 0 0 1 %s %s" % [n_(tr), n_(tr), n_(x + w), n_(y + tr)]
	s += "V%s" % n_(y + h - br)
	if br > 0.0: s += "A%s %s 0 0 1 %s %s" % [n_(br), n_(br), n_(x + w - br), n_(y + h)]
	s += "H%s" % n_(x + bl)
	if bl > 0.0: s += "A%s %s 0 0 1 %s %s" % [n_(bl), n_(bl), n_(x), n_(y + h - bl)]
	s += "V%s" % n_(y + tl)
	if tl > 0.0: s += "A%s %s 0 0 1 %s %s" % [n_(tl), n_(tl), n_(x + tl), n_(y)]
	return s + "Z"

static func _shrinkR(r, d: float):
	if r is Array:
		return [maxf(0.0, r[0] - d), maxf(0.0, r[1] - d), maxf(0.0, r[2] - d), maxf(0.0, r[3] - d)]
	return maxf(0.0, float(r) - d)

static func _stops(stops: Array) -> String:
	# stops: [[css colour | 'transparent', offset 0..1], ...]; 'transparent' takes the neighbour's colour at alpha 0
	var s := ""
	for i in stops.size():
		var c: String = stops[i][0]
		var hexc: String
		var a: float
		if c == "transparent":
			var nb: String = stops[i + 1][0] if i + 1 < stops.size() else (stops[i - 1][0] if i > 0 else "#000")
			hexc = cssCol(nb)[0]
			a = 0.0
		else:
			var cc := cssCol(c)
			hexc = cc[0]
			a = cc[1]
		s += '<stop offset="%s" stop-color="%s" stop-opacity="%s"/>' % [n_(stops[i][1]), hexc, n_(a)]
	return s

# CSS linear-gradient(<angle>deg, stops) over the box (x, y, w, h).
static func linGrad(id: String, x: float, y: float, w: float, h: float, angleDeg: float, stops: Array) -> String:
	var a := deg_to_rad(angleDeg)
	var d := Vector2(sin(a), -cos(a))
	var L := absf(w * sin(a)) + absf(h * cos(a))
	var c := Vector2(x + w / 2.0, y + h / 2.0)
	var p1 := c - d * L / 2.0
	var p2 := c + d * L / 2.0
	return '<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>' % [id, n_(p1.x), n_(p1.y), n_(p2.x), n_(p2.y), _stops(stops)]

# CSS radial-gradient(circle at cx cy, stops) with the circle's radius r (farthest-corner by default: see farCorner).
static func radGrad(id: String, cx: float, cy: float, r: float, stops: Array) -> String:
	return '<radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s" fx="%s" fy="%s">%s</radialGradient>' % [id, n_(cx), n_(cy), n_(r), n_(cx), n_(cy), _stops(stops)]

static func farCorner(x: float, y: float, w: float, h: float, cx: float, cy: float) -> float:
	var m := 0.0
	for p in [Vector2(x, y), Vector2(x + w, y), Vector2(x, y + h), Vector2(x + w, y + h)]:
		m = maxf(m, Vector2(cx, cy).distance_to(p))
	return m

static func blurFilter(id: String, blurPx: float) -> String:
	return '<filter id="%s" x="-1" y="-1" width="3" height="3"><feGaussianBlur stdDeviation="%s"/></filter>' % [id, n_(blurPx / 2.0)]

# CSS outer box-shadow (dx dy blur spread colour) of the rounded box -> SVG element (+ defs appended to out_defs).
static func boxShadow(defs: Array, id: String, x: float, y: float, w: float, h: float, r, dx: float, dy: float, blur: float, spread: float, col: String) -> String:
	var d := rrd(x + dx - spread, y + dy - spread, w + spread * 2.0, h + spread * 2.0, _shrinkR(r, -spread))
	if blur > 0.0:
		defs.append(blurFilter(id, blur))
		return '<path d="%s" %s filter="url(#%s)"/>' % [d, fillAttr(col), id]
	return '<path d="%s" %s/>' % [d, fillAttr(col)]

# CSS inset box-shadow inside the rounded box (clip id must hold the box path).
static func insetShadow(defs: Array, id: String, clipId: String, x: float, y: float, w: float, h: float, r, dx: float, dy: float, blur: float, spread: float, col: String) -> String:
	var big := 20.0 + blur * 2.0
	var hole := rrd(x + dx + spread, y + dy + spread, maxf(0.0, w - spread * 2.0), maxf(0.0, h - spread * 2.0), _shrinkR(r, spread))
	var d := "M%s %sH%sV%sH%sZ %s" % [n_(x - big), n_(y - big), n_(x + w + big), n_(y + h + big), n_(x - big), hole]
	var f := ""
	if blur > 0.0:
		defs.append(blurFilter(id, blur))
		f = ' filter="url(#%s)"' % id
	return '<g clip-path="url(#%s)"><path fill-rule="evenodd" d="%s" %s%s/></g>' % [clipId, d, fillAttr(col), f]

static func clipDef(id: String, d: String) -> String:
	return '<clipPath id="%s"><path d="%s"/></clipPath>' % [id, d]

# preserveAspectRatio xMidYMid meet of a viewBox (vw, vh) into a (w, h) box at (x, y).
static func fitTf(vw: float, vh: float, x: float, y: float, w: float, h: float) -> String:
	var k := minf(w / vw, h / vh)
	return "translate(%s %s) scale(%s)" % [n_(x + (w - vw * k) / 2.0), n_(y + (h - vh * k) / 2.0), n_(k)]

# A CSS box (w x h) as SVG: spec = { r: radius | [tl, tr, br, bl], bg: colour | {lin: deg, stops} |
# {rad: [cx, cy] (fractions), stops, shape: 'circle' | 'ellipse'} | [layers, first on top], shadows: [[dx, dy, blur,
# spread, colour], ...] (outer, CSS order), insets: [[dx, dy, blur, spread, colour], ...], extra: svg drawn on top,
# extraDefs }. Returns [svg, pad]: draw the texture at (x - pad, y - pad, w + 2 pad, h + 2 pad).
static func cssBoxSvg(w: float, h: float, spec: Dictionary) -> Array:
	var r = spec.get("r", 0.0)
	var pad := 2.0
	for s in spec.get("shadows", []):
		pad = maxf(pad, absf(s[0]) + absf(s[1]) + s[2] * 1.5 + maxf(0.0, s[3]) + 2.0)
	pad = ceilf(pad)
	var defs: Array = []
	var d := rrd(0, 0, w, h, r)
	defs.append(clipDef("bx", d))
	var body := ""
	var sh: Array = spec.get("shadows", [])
	for i in range(sh.size() - 1, -1, -1):
		var s: Array = sh[i]
		body += boxShadow(defs, "os%d" % i, 0, 0, w, h, r, s[0], s[1], s[2], s[3], s[4])
	var bgs = spec.get("bg")
	if bgs != null:
		if not (bgs is Array):
			bgs = [bgs]
		for i in range(bgs.size() - 1, -1, -1):
			var bg = bgs[i]
			if bg is String:
				body += '<path d="%s" %s/>' % [d, fillAttr(bg)]
			elif bg is Dictionary and bg.has("lin"):
				defs.append(linGrad("bg%d" % i, 0, 0, w, h, float(bg.lin), bg.stops))
				body += '<path d="%s" fill="url(#bg%d)"/>' % [d, i]
			elif bg is Dictionary and bg.has("rad"):
				var cx: float = float(bg.rad[0]) * w
				var cy: float = float(bg.rad[1]) * h
				if bg.get("shape", "circle") == "ellipse":
					# farthest-corner ellipse with the closest-side aspect ratio
					var csx := minf(cx, w - cx)
					var csy := minf(cy, h - cy)
					var fx := maxf(cx, w - cx)
					var fy := maxf(cy, h - cy)
					var k := sqrt(pow(fx / maxf(1e-3, csx), 2.0) + pow(fy / maxf(1e-3, csy), 2.0))
					var rx := csx * k
					var ry := csy * k
					defs.append('<radialGradient id="bg%d" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s" fx="%s" fy="%s" gradientTransform="translate(%s %s) scale(1 %s) translate(%s %s)">%s</radialGradient>' % [i, n_(cx), n_(cy), n_(rx), n_(cx), n_(cy), n_(cx), n_(cy), n_(ry / rx), n_(-cx), n_(-cy), _stops(bg.stops)])
				else:
					defs.append(radGrad("bg%d" % i, cx, cy, float(bg.get("radius", farCorner(0, 0, w, h, cx, cy))), bg.stops))
				body += '<path d="%s" fill="url(#bg%d)"/>' % [d, i]
	var ins: Array = spec.get("insets", [])
	for i in range(ins.size() - 1, -1, -1):
		var s: Array = ins[i]
		body += insetShadow(defs, "is%d" % i, "bx", 0, 0, w, h, r, s[0], s[1], s[2], s[3], s[4])
	body += spec.get("extra", "")
	return [svgDoc(-pad, -pad, w + pad * 2.0, h + pad * 2.0, body, "".join(defs) + spec.get("extraDefs", "")), pad]

# ------------------------------------------------------------------------------------------------ text
static func font(css: String) -> Font:
	return FontsScript.family(css)

# Baseline for text whose line box is vertically centred on cy (flex centring; any line-height).
static func baselineAt(f: Font, size: float, cy: float) -> float:
	return cy + (f.get_ascent(int(size)) - f.get_descent(int(size))) / 2.0

# Advance width with CSS letter-spacing (applied after every character, the last one included).
static func textWidth(f: Font, s: String, size: float, spacing: float = 0.0) -> float:
	if spacing == 0.0:
		return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
	var w := 0.0
	for i in s.length():
		w += f.get_char_size(s.unicode_at(i), int(size)).x + spacing
	return w

# Draws text at (x, baseline) with letter-spacing and CSS text-shadows [[dx, dy, blur, colour], ...] (first = top).
static func drawText(ci: CanvasItem, f: Font, x: float, baseline: float, s: String, size: float, col: Color, spacing: float = 0.0, shadows: Array = []) -> void:
	for i in range(shadows.size() - 1, -1, -1):
		var sh: Array = shadows[i]
		var sc: Color = sh[3] if sh[3] is Color else DAU.color(sh[3])
		var sc2 := Color(sc.r, sc.g, sc.b, sc.a * col.a)
		var blur: float = sh[2]
		if blur > 0.0:
			# blurred shadow: a soft outline halo + a faint core
			_drawRun(ci, f, x + sh[0], baseline + sh[1], s, size, Color(sc2.r, sc2.g, sc2.b, sc2.a * 0.22), spacing, int(ceil(blur * 1.2)))
			_drawRun(ci, f, x + sh[0], baseline + sh[1], s, size, Color(sc2.r, sc2.g, sc2.b, sc2.a * 0.3), spacing, int(ceil(blur * 0.5)))
		else:
			_drawRun(ci, f, x + sh[0], baseline + sh[1], s, size, sc2, spacing, 0)
	_drawRun(ci, f, x, baseline, s, size, col, spacing, 0)

static func _drawRun(ci: CanvasItem, f: Font, x: float, baseline: float, s: String, size: float, col: Color, spacing: float, outline: int) -> void:
	if spacing == 0.0:
		if outline > 0:
			ci.draw_string_outline(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), outline, col)
			ci.draw_string(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), col)
		else:
			ci.draw_string(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), col)
		return
	var px := x
	for i in s.length():
		var ch := s.substr(i, 1)
		if outline > 0:
			ci.draw_char_outline(f, Vector2(px, baseline), ch, int(size), outline, col)
		ci.draw_char(f, Vector2(px, baseline), ch, int(size), col)
		px += f.get_char_size(s.unicode_at(i), int(size)).x + spacing

# ------------------------------------------------------------------------------------------------ Controls
# A Control whose _draw() calls draw_fn(self) (the DOM element's paint).
class DrawCtl extends Control:
	var draw_fn: Callable
	func _init(fn: Callable = Callable(), nm: String = "") -> void:
		draw_fn = fn
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if nm != "":
			name = nm
	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)

# ================================================================================================ split-flap digits
# FlipBoard(parent, count, { cls, onFlip, speed }) builds `count` split-flap cards inside parent (a Container: the flex
# row of the JS). set_(str) aims each card at str[i] (' ' = blank); update(dt) animates: every card steps one flap at a
# time toward its target (0..9 in order, blank flips straight), faster when it has far to go. set_(str, true) jumps
# without animating. cls picks the card look: 'tote' (HUD tote board) or 'board' (menu game-over board);
# setInk(color, glows) recolours the digits (the .gold / .spend classes of the tote).
const FLIP_STYLES := {
	"tote": {"w": 26.0, "h": 40.0, "r": 5.0, "size": 31.0, "color": "#FFB347", "glow": [[0.0, 0.0, 7.0, "rgba(255,150,40,.75)"]], "inset": 1.0},
	"board": {"w": 132.0, "h": 196.0, "r": 14.0, "size": 170.0, "color": "#FFB347", "glow": [[0.0, 0.0, 22.0, "rgba(255,150,40,.75)"]], "inset": 2.0},
}

class FlipHalf extends Control:
	# One half of a card (static half or flipping leaf): gradient background + the half of the glyph it shows.
	var card: Control
	var top := true
	var txt := ""
	var bright := 1.0
	func _init(c: Control, is_top: bool) -> void:
		card = c
		top = is_top
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
	func _draw() -> void:
		var st: Dictionary = card.st
		var w: float = st.w
		var h: float = st.h
		var tex: Texture2D = card.halfTex(top)
		if tex:
			draw_texture_rect(tex, Rect2(0, 0, w, h / 2.0), false, Color(bright, bright, bright, 1))
		if txt != "":
			var f: Font = card.fnt
			var size: float = st.size
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
			var yoff := 0.0 if top else -h / 2.0
			var base := yoff + h / 2.0 + (f.get_ascent(int(size)) - f.get_descent(int(size))) / 2.0
			var ink: Color = card.ink
			var glows: Array = card.glows
			var c := Color(ink.r * bright, ink.g * bright, ink.b * bright, ink.a)
			var sh: Array = []
			for g in glows:
				var gc: Color = DAU.color(g[3])
				sh.append([g[0], g[1], g[2], Color(gc.r * bright, gc.g * bright, gc.b * bright, gc.a)])
			Hud_.drawText(self, f, (w - tw) / 2.0, base, txt, size, c, 0.0, sh)

class FlipCard extends Control:
	var st: Dictionary
	var fnt: Font
	var ink: Color
	var glows: Array
	var top: FlipHalf
	var bot: FlipHalf
	var leafT: FlipHalf
	var leafB: FlipHalf
	var _tex := {}
	func _init(style: Dictionary) -> void:
		st = style
		fnt = Hud_.font(FontsScript.FONTS.hud)
		ink = DAU.color(style.color)
		glows = style.glow
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(style.w, style.h)
		size = custom_minimum_size
		top = FlipHalf.new(self, true)
		bot = FlipHalf.new(self, false)
		leafT = FlipHalf.new(self, true)
		leafB = FlipHalf.new(self, false)
		for hf in [top, bot, leafT, leafB]:
			hf.size = Vector2(style.w, style.h / 2.0)
			add_child(hf)
		top.position = Vector2.ZERO
		leafT.position = Vector2.ZERO
		bot.position = Vector2(0, style.h / 2.0)
		leafB.position = Vector2(0, style.h / 2.0)
		leafT.pivot_offset = Vector2(style.w / 2.0, style.h / 2.0)   # transform-origin 50% 100%
		leafB.pivot_offset = Vector2(style.w / 2.0, 0.0)             # transform-origin 50% 0
		leafT.visible = false
		leafB.visible = false
	# .ft: radius r r 0 0, linear-gradient(#2E1C12, #22140D); .fb: radius 0 0 r r, linear-gradient(#1A0F09, #22140D),
	# box-shadow inset 0 1px 0 rgba(0,0,0,.8) (board: inset 0 2px 0).
	func halfTex(is_top: bool) -> Texture2D:
		var key := "%s|%s" % [is_top, Hud_.svgScale]
		if _tex.has(key) and _tex[key] != null:
			return _tex[key]
		var w: float = st.w
		var h: float = st.h / 2.0
		var r: float = st.r
		var defs: Array = []
		var body := ""
		if is_top:
			defs.append(Hud_.linGrad("g", 0, 0, w, h, 180, [["#2E1C12", 0.0], ["#22140D", 1.0]]))
			body = '<path d="%s" fill="url(#g)"/>' % Hud_.rrd(0, 0, w, h, [r, r, 0, 0])
		else:
			var d := Hud_.rrd(0, 0, w, h, [0, 0, r, r])
			defs.append(Hud_.linGrad("g", 0, 0, w, h, 180, [["#1A0F09", 0.0], ["#22140D", 1.0]]))
			defs.append(Hud_.clipDef("c", d))
			body = '<path d="%s" fill="url(#g)"/>' % d
			body += Hud_.insetShadow(defs, "i", "c", 0, 0, w, h, [0, 0, r, r], 0, st.inset, 0, 0, "rgba(0,0,0,.8)")
		var t := Hud_.svgTexture(Hud_.svgDoc(0, 0, w, h, body, "".join(defs)))
		_tex[key] = t
		return t
	func redraw() -> void:
		for hf in [top, bot, leafT, leafB]:
			hf.queue_redraw()

class FlipBoard extends RefCounted:
	var cards: Array = []
	var onFlip: Callable
	var speed := 1.0
	var busy: bool:
		get: return cards.any(func(c): return c.t >= 0.0 or c.cur != c.target)
	func _init(parent: Control, count: int, opts: Dictionary = {}) -> void:
		onFlip = opts.get("onFlip", Callable())
		speed = float(opts.get("speed", 1.0))
		var style: Dictionary = FLIP_STYLES.get(opts.get("cls", "tote"), FLIP_STYLES.tote).duplicate()
		for i in count:
			var el := FlipCard.new(style)
			parent.add_child(el)
			cards.append({"el": el, "cur": " ", "next": " ", "target": " ", "t": -1.0, "dur": 0.08})

	func set_(s: String, instant: bool = false) -> void:
		for i in cards.size():
			var c: Dictionary = cards[i]
			var ch := s.substr(i, 1) if i < s.length() else " "
			c.target = ch
			if instant:
				c.cur = ch
				c.next = ch
				c.t = -1.0
				var el: FlipCard = c.el
				el.top.txt = ch.strip_edges()
				el.bot.txt = ch.strip_edges()
				el.leafT.visible = false
				el.leafB.visible = false
				el.redraw()

	# Digit ink (the tote's .gold / .spend classes).
	func setInk(color: String, glows: Array) -> void:
		for c in cards:
			var el: FlipCard = c.el
			el.ink = DAU.color(color)
			el.glows = glows
			el.redraw()

	func _isDigit(s: String) -> bool:
		return s.length() == 1 and s >= "0" and s <= "9"

	func _stepOf(cur: String, target: String):
		if cur == target:
			return null
		if target == " " or cur == " " or not _isDigit(cur) or not _isDigit(target):
			return target
		return str((int(cur) + 1) % 10)

	func _steps(cur: String, target: String) -> int:
		if cur == target:
			return 0
		if target == " " or cur == " " or not _isDigit(cur) or not _isDigit(target):
			return 1
		return (int(target) - int(cur) + 10) % 10

	func update(dt: float) -> void:
		for i in cards.size():
			var c: Dictionary = cards[i]
			var el: FlipCard = c.el
			if c.t < 0.0:
				var nx = _stepOf(c.cur, c.target)
				if nx == null:
					continue
				c.next = nx
				c.dur = Hud_.clamp_(0.34 / maxf(1.0, float(_steps(c.cur, c.target))), 0.036, 0.085) / speed
				c.t = 0.0
				el.top.txt = String(nx).strip_edges()
				el.bot.txt = String(c.cur).strip_edges()
				el.leafT.txt = String(c.cur).strip_edges()
				el.leafB.txt = String(nx).strip_edges()
				el.leafT.visible = true
				el.leafB.visible = false
				_leaf(el.leafT, 0.0, el)
				_leaf(el.leafB, 90.0, el)
				el.leafT.bright = 1.0
				el.redraw()
				if onFlip.is_valid():
					onFlip.call(i)
			c.t += dt
			var half: float = c.dur * 0.5
			if c.t < half:
				var p := Hud_.easeIn(c.t / half)
				_leaf(el.leafT, -90.0 * p, el)
				el.leafT.bright = 1.0 - 0.45 * p
				el.leafT.queue_redraw()
			elif c.t < c.dur:
				el.leafT.visible = false
				el.leafB.visible = true
				var p2: float = (c.t - half) / half
				_leaf(el.leafB, 90.0 * (1.0 - Hud_.easeOut(p2)), el)
			else:
				c.cur = c.next
				el.bot.txt = String(c.cur).strip_edges()
				el.bot.queue_redraw()
				el.leafB.visible = false
				c.t = -1.0

	# rotateX(deg) about the hinge under `perspective: 220px`: the leaf's projected height (cos) and the mean widening
	# of its free edge (the affine part of the projection).
	func _leaf(leaf: FlipHalf, deg: float, el: FlipCard) -> void:
		var a := deg_to_rad(deg)
		var hh: float = el.st.h / 2.0
		var z := absf(sin(a)) * hh   # both leaves swing their free edge toward the viewer
		var persp := 220.0
		var edge := persp / maxf(1.0, persp - z)
		var sy := absf(cos(a)) * edge
		leaf.scale = Vector2((1.0 + edge) / 2.0, maxf(0.0001, sy))

# ================================================================================================ tape-counter drums
# Roller(parent, count, { cls }) = odometer drums; set_(n) rolls every drum to its digit (leading zeros dimmed).
# cls: 'mag' (30x48, 56 px) | 'res' (19x34, 34 px). Drums are laid out left to right with the CSS .rd+.rd 2 px gap.
const ROLL_STYLES := {
	"mag": {"w": 30.0, "h": 48.0, "size": 56.0, "color": "#F6F6F2", "lead": "#5A5A64"},
	"res": {"w": 19.0, "h": 34.0, "size": 34.0, "color": "#C8C4D0", "lead": "#4A4A54"},
}

class Drum extends Control:
	var st: Dictionary
	var fnt: Font
	var d := -1
	var lead := false
	var ink = null            # colour override (low-magazine pulse)
	var y0 := 0.0             # strip offset in drum heights (animated like the CSS transition)
	var yFrom := 0.0
	var yTo := 0.0
	var yt := -1.0
	func _init(style: Dictionary) -> void:
		st = style
		fnt = Hud_.font(FontsScript.FONTS.tape)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		size = Vector2(style.w, style.h)
	func roll(to: float) -> void:
		yFrom = y0
		yTo = to
		yt = 0.0
	func tick(dt: float) -> void:
		if yt < 0.0:
			return
		yt += dt
		var p := clampf(yt / 0.12, 0.0, 1.0)
		y0 = lerpf(yFrom, yTo, Hud_.cubicBezier(0.3, 1.4, 0.6, 1.0, p))
		if p >= 1.0:
			yt = -1.0
		queue_redraw()
	func _draw() -> void:
		var w: float = st.w
		var h: float = st.h
		var tex := Hud_.svgTexture(Hud_.svgDoc(0, 0, w, h, '<rect width="%s" height="%s" fill="url(#g)"/>' % [Hud_.n_(w), Hud_.n_(h)],
			Hud_.linGrad("g", 0, 0, w, h, 180, [["#000", 0.0], ["#26262C", 0.22], ["#34343A", 0.5], ["#26262C", 0.78], ["#000", 1.0]])))
		if tex:
			draw_texture_rect(tex, Rect2(0, 0, w, h), false)
		var col: Color = DAU.color(st.lead if lead else st.color)
		if ink != null and not lead:
			col = ink
		var size: float = st.size
		var asc := fnt.get_ascent(int(size))
		var desc := fnt.get_descent(int(size))
		# only the digits near the window are drawn
		var first := int(floorf(-y0)) - 1
		for i in range(maxi(0, first), mini(10, first + 4)):
			var cy := (float(i) + y0) * h + h / 2.0
			var s := str(i)
			var tw := fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
			draw_string(fnt, Vector2((w - tw) / 2.0, cy + (asc - desc) / 2.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), col)

class Roller extends RefCounted:
	var drums: Array = []
	var value := -1
	func _init(parent: Control, count: int, opts: Dictionary = {}) -> void:
		var style: Dictionary = ROLL_STYLES.get(opts.get("cls", "mag"), ROLL_STYLES.mag)
		var x: float = float(opts.get("x", 0.0))
		var y: float = float(opts.get("y", 0.0))
		for i in count:
			var el := Drum.new(style)
			el.position = Vector2(x + i * (style.w + 2.0), y)
			parent.add_child(el)
			drums.append({"el": el, "d": -1})

	func set_(n: float) -> void:
		var v := int(maxf(0.0, floorf(n)))
		if v == value:
			return
		value = v
		var cap := int(pow(10, drums.size())) - 1
		var s := str(mini(v, cap)).pad_zeros(drums.size())
		var lead := s.length() - str(v).length()
		for i in drums.size():
			var dr: Dictionary = drums[i]
			var d := int(s.substr(i, 1))
			var el: Drum = dr.el
			if d != dr.d:
				dr.d = d
				el.roll(-float(d))
			el.lead = i < lead
			el.queue_redraw()

	func tick(dt: float) -> void:
		for dr in drums:
			(dr.el as Drum).tick(dt)

# ================================================================================================ post knob mixing
# Several systems may write the same render.post knob. A Knob remembers what the HUD wrote last frame: a different
# value means someone else wrote it (their value becomes `ext`), and the HUD combines its own contribution with it.
class Knob extends RefCounted:
	var name := ""
	var ext := 0.0
	var wrote = null
	var still := 0.0
	func _init(n: String) -> void:
		name = n
	func apply(post: Dictionary, mine: float, mode: String, dt: float) -> void:
		var cur: float = float(post.get(name, 0.0))
		if wrote == null or cur != wrote:
			ext = cur
			still = 0.0
		else:
			still += dt
		var out := ext + mine if mode == "add" else maxf(ext, mine)
		if name == "damage":
			out = minf(1.0, out)
		post[name] = out
		wrote = out
	func release(post: Dictionary) -> void:
		if wrote != null and float(post.get(name, 0.0)) == wrote:
			post[name] = ext
		wrote = null

# ================================================================================================ icons (SVG, as the JS)
const PLUG_SVG := '<path d="M2 30c8 0 8-10 16-10h6" fill="none" stroke="#F4F1E8" stroke-width="4" stroke-linecap="round"/><rect x="22" y="9" width="22" height="22" rx="6" fill="#F4F1E8"/><rect x="26" y="13" width="14" height="4" rx="2" fill="#B8B2A8"/><path d="M44 14h14M44 26h14" stroke="#F4F1E8" stroke-width="4.5" stroke-linecap="round"/>'

# TUBE_SVG / TELE_SVG with the .dh .eq class styles inlined (on / off states).
static func TUBE_SVG(on: bool) -> String:
	var gl := 'fill="#FFBE6E" fill-opacity=".45" stroke="#F4F1E8"' if on else 'fill="#787882" fill-opacity=".25" stroke="#8A8690"'
	var fi := 'stroke="#FFE08A"' if on else 'stroke="#6A6670"'
	var ba := 'stroke="#F4F1E8"' if on else 'stroke="#8A8690"'
	var s := '<path %s stroke-width="1.6" d="M4 30V11a7 7 0 0 1 14 0v19z"/>' % gl
	if on:   # .tube.on .fi: filter drop-shadow(0 0 3px #FF9A2A)
		s += '<path fill="none" stroke="#FF9A2A" stroke-opacity=".9" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" filter="url(#fg)" d="M8 27V15l3-3 3 3v12"/>'
	s += '<path fill="none" %s stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M8 27V15l3-3 3 3v12"/>' % fi
	s += '<rect fill="#2A2230" %s stroke-width="1.2" x="3" y="29" width="16" height="7" rx="2"/>' % ba
	s += '<path stroke="#C8963C" stroke-width="1.4" d="M7 36v3M11 36v3M15 36v3"/>'
	s += '<path stroke="#FFFFFF" stroke-opacity=".7" stroke-width="1.4" stroke-linecap="round" d="M7 12v12"/>'
	return s

static func TELE_SVG(on: bool) -> String:
	var ca := 'fill="#E3662B" stroke="#F4F1E8"' if on else 'fill="#6A6670" stroke="#9A96A0"'
	var sc := "#7FE7FF" if on else "#3A3A44"
	return '<path stroke="#F4F1E8" stroke-width="1.6" stroke-linecap="round" d="M15 9l-6-7M15 9l6-7"/><rect %s stroke-width="1.2" x="2" y="8" width="26" height="18" rx="5"/><rect fill="%s" x="5.5" y="11" width="14" height="11" rx="3"/><circle fill="#F4F1E8" cx="23.5" cy="14" r="1.8"/><circle fill="#F4F1E8" cx="23.5" cy="19.5" r="1.8"/>' % [ca, sc]

const PU_ICON := {
	"one_take": '<rect x="8" y="20" width="32" height="20" rx="3" fill="#2A2230"/><path d="M8 20h32" stroke="#F4F1E8" stroke-width="1.5"/><g transform="rotate(-18 9 19)"><rect x="7" y="12" width="33" height="8" rx="2" fill="#F4F1E8"/><path d="M12 12l5 8M20 12l5 8M28 12l5 8M36 12l4 6" stroke="#2A2230" stroke-width="3"/></g><circle cx="9" cy="19" r="2.2" fill="#FF3B30"/><path d="M13 27h14M13 33h9" stroke="#F4F1E8" stroke-width="2" stroke-linecap="round"/>',
	"sweeps_week": '<path d="M24 12l-6-7M24 12l6-7" stroke="#F4F1E8" stroke-width="2" stroke-linecap="round"/><rect x="7" y="11" width="34" height="27" rx="7" fill="#FF4FA0"/><rect x="11" y="15" width="21" height="19" rx="4" fill="#2A1830"/><circle cx="36.5" cy="20" r="2" fill="#FFE14D"/><circle cx="36.5" cy="28" r="2" fill="#2A1830"/>',
	"please_stand_by": '<path d="M24 12l-6-7M24 12l6-7" stroke="#F4F1E8" stroke-width="2" stroke-linecap="round"/><rect x="7" y="11" width="34" height="27" rx="7" fill="#EDEDED"/><rect x="11" y="15" width="21" height="19" rx="4" fill="#5A5A6A"/><circle cx="21.5" cy="24.5" r="7" fill="#9ED8FF" stroke="#F4F1E8" stroke-width="1.5"/><path d="M14.5 21h14" stroke="#F4E03A" stroke-width="3"/><circle cx="36.5" cy="20" r="2" fill="#3A58E4"/><circle cx="36.5" cy="28" r="2" fill="#E4473A"/>',
	"full_reel": '<circle cx="24" cy="24" r="15" fill="#C8CED8" stroke="#FFC23A" stroke-width="2"/><circle cx="24" cy="24" r="4" fill="#2A2230"/><circle cx="24" cy="15" r="4" fill="#2A2230"/><circle cx="31.8" cy="28.5" r="4" fill="#2A2230"/><circle cx="16.2" cy="28.5" r="4" fill="#2A2230"/>',
	"cancelled": '<rect x="15" y="8" width="18" height="16" rx="5" fill="#8A4A2A"/><rect x="10" y="24" width="28" height="7" rx="2" fill="#E3662B"/><path d="M14 35l20 6M34 35l-20 6" stroke="#FF3B30" stroke-width="4" stroke-linecap="round"/>',
	"gaffer_tape": '<circle cx="24" cy="24" r="15" fill="#DDE3EA"/><circle cx="24" cy="24" r="7" fill="#2A2230"/><path d="M36 30l8 6" stroke="#DDE3EA" stroke-width="7"/>',
}
# the sweeps_week icon's <text> (the SVG rasterizer has no fonts: drawn with Titan One on top)
const PU_ICON_TEXT := {"sweeps_week": ["×2", 21.5, 30.5, 12.0, "#FFE14D"]}

const STAR_PATH := '<path d="M20 2l5 12 13 1-10 8 3 13-11-7-11 7 3-13-10-8 13-1z" %s stroke-width="2.5" stroke-linejoin="round"/>'
const RB_PATH := '<path d="M30 4L4 18l26 14z M60 4L34 18l26 14z" %s stroke-width="3" stroke-linejoin="round"/>'

# A small SVG graphic `inner` (viewBox vw x vh) fitted into w x h with CSS drop-shadows [[dx, dy, blur, colour], ...]
# (filter: drop-shadow() chain; the shadow is the whole graphic's alpha, offset and blurred, painted underneath).
static func iconSvg(inner: String, vw: float, vh: float, w: float, h: float, drops: Array = [], extraDefs: String = "", pad: float = 8.0) -> String:
	var tf := fitTf(vw, vh, 0, 0, w, h)
	var defs := extraDefs + '<g id="ic">%s</g>' % inner
	var body := ""
	var i := 0
	for d in drops:
		var id := "ds%d" % i
		i += 1
		var cc := cssCol(d[3])
		var f := ""
		if d[2] > 0.0:
			defs += '<filter id="%s" x="-1" y="-1" width="3" height="3"><feGaussianBlur stdDeviation="%s"/></filter>' % [id, n_(d[2] / 2.0)]
			f = ' filter="url(#%s)"' % id
		# a silhouette copy: every paint forced to the shadow colour through a flood-like re-fill
		body += '<g transform="translate(%s %s) %s" opacity="%s"%s>%s</g>' % [n_(d[0]), n_(d[1]), tf, n_(cc[1]), f, _silhouette(inner, cc[0])]
	body += '<g transform="%s">%s</g>' % [tf, inner]
	return svgDoc(-pad, -pad, w + pad * 2.0, h + pad * 2.0, body, defs)

# Recolours every fill / stroke of an SVG fragment (drop-shadow silhouettes).
static func _silhouette(inner: String, hexc: String) -> String:
	var re := RegEx.new()
	re.compile('(fill|stroke)="(?!none)[^"]*"')
	var s := re.sub(inner, '$1="%s"' % hexc, true)
	# the paints' own opacities stay: a CSS drop-shadow follows the rendered alpha (translucent glass casts a faint shadow)
	return s.replace('fill="url(#', 'data-x="').replace('filter="url(#fg)"', "")

# ------------------------------------------------------------------------------------------------ CRT + shine shaders
const CRT_SHADER := """
shader_type canvas_item;
// .dh-crt: border-radius 3.2vh; box-shadow inset 0 0 14vh 2vh rgba(12,6,22,.42), 0 0 0 6vh rgba(8,4,14,.55);
// ::after repeating-linear-gradient(0deg, rgba(0,0,0,.05) 0 1px, transparent 1px 3px)
uniform vec2 size_px = vec2(1920.0, 1080.0);
float rbox(vec2 p, vec2 b, float r) { vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
void fragment() {
	vec2 p = UV * size_px;
	float vh = size_px.y / 100.0;
	float d = rbox(p - size_px * 0.5, size_px * 0.5, 3.2 * vh);
	// outside the rounded screen: the 6vh ring
	float outside = step(0.0, d);
	// inset shadow: 2vh spread, 14vh blur (gaussian falloff from the inner edge)
	float inner = -d - 2.0 * vh;
	float sh = inner <= 0.0 ? 1.0 : exp(-0.5 * pow(inner / (7.0 * vh), 2.0));
	vec4 col = vec4(12.0 / 255.0, 6.0 / 255.0, 22.0 / 255.0, 0.42 * sh);
	float line = mod(floor((size_px.y - p.y)), 3.0) < 1.0 ? 0.05 : 0.0;
	col.rgb = mix(col.rgb, vec3(0.0), line / max(0.001, col.a + line));
	col.a = col.a + line * (1.0 - col.a);
	vec4 ring = vec4(8.0 / 255.0, 4.0 / 255.0, 14.0 / 255.0, 0.55);
	COLOR = mix(col, ring, outside);
}
"""

const SHINE_SHADER := """
shader_type canvas_item;
// .chy .shine (566x56, border-radius 0 28px 28px 0, overflow hidden) ::before: 60 px skewX(-20deg) white sweep
uniform float left_px = -80.0;
uniform vec2 size_px = vec2(566.0, 56.0);
void fragment() {
	vec2 p = UV * size_px;
	float r = 28.0;
	vec2 c = vec2(size_px.x - r, clamp(p.y, r, size_px.y - r));
	float inside = p.x < size_px.x - r ? 1.0 : step(distance(p, c), r);
	float x = p.x - (left_px + 30.0) + 0.36397 * (p.y - 28.0);
	float t = clamp((x + 30.0) / 60.0, 0.0, 1.0);
	float a = 0.55 * (1.0 - abs(2.0 * t - 1.0)) * step(-30.0, x) * step(x, 30.0);
	COLOR = vec4(1.0, 1.0, 1.0, a * inside);
}
"""

# ================================================================================================ Hud
var game
var visible := false
var _supp := {}
var _shown := {"points": -1, "gold": null, "mag": -1, "res": -1, "low": null, "noAmmo": null, "gren": -1, "tele": -1, "teleRow": null, "spread": -1, "dim": null, "want": null}
var _prompt := {"on": false, "key": "E", "cost": -1, "denied": null, "plug": null, "hold": null, "prog": -1.0, "t": 0.0}
var _hm := 0
var _hmT := -1.0
var _starT := -1.0
var _hmLevel := 0
var _kick := 0.0
var _spendT := 0.0
var _pops: Array = []
var _dedupe := {}
var _frame := -1
var _flashT := -1.0
var _chy := {"t": -1.0, "name": "", "sub": "", "lastAt": -1e9}
var _dial := {"shown": null, "target": null, "t": -1.0, "from": 0.0, "spin": 0.0, "clicked": false}
var _pu := {}
var _hadTele := false
var _pulse := {"static": 0.0, "roll": 0.0, "chroma": 0.0, "damage": 0.0}
var _pulseDecay := 0.0
var _white := {"t": -1.0, "dur": 1.5, "amount": 1.0}
var _knobs := {"damage": Knob.new("damage"), "static": Knob.new("static"), "roll": Knob.new("roll"), "chroma": Knob.new("chroma"), "whiteout": Knob.new("whiteout")}
var _knobsOn := false
var _tear := {"t": -1.0, "edge": "left", "acc": 0.0, "seed": 0.0}
var _shakeT := 0.0
var _replay := false
var _dyScale := 1.0
var _timers: Array = []
var _time := 0.0            # real seconds since construction (CSS animation clocks)
var scale := 1.0
var stageW := 1920.0

# nodes (the DOM of the JS)
var layer: CanvasLayer
var root: Control
var stage: Control
var el := {}
var tote: FlipBoard
var magDrums: Roller
var resDrums: Roller
var tubes: Array = []
var teles: Array = []
var _tearImg: Image
var _tearTex: ImageTexture
var _tearData := PackedByteArray()
var _fonts := {}
var _stageAlpha := 0.0      # .dh-s transition: opacity .18s
var _xhAlpha := 1.0         # .xh transition: opacity .15s
var _hmState := {"opacity": 0.0, "gap": 10.0, "sx": 1.0, "len": 1.0, "col": "#FFFFFF"}
var _starState := {"opacity": 0.0, "ty": 0.0, "rot": 0.0, "s": 0.0}
var _dyOpacity := 0.0
var _dyDx := 0.0
var _lowT := 0.0
var _dialNum := {"text": "", "small": false, "opacity": 1.0, "sx": 1.0, "sy": 1.0, "rot": 0.0}
var _chyX := -120.0
var _chyO := 0.0
var _shineT := -1.0
var _flash := {"text": "", "opacity": 0.0, "s": 1.0}
var _crtOn := false

func _init(g) -> void:
	game = g
	FontsScript.loadFonts()
	_fonts = {"hud": font(FontsScript.FONTS.hud), "tape": font(FontsScript.FONTS.tape), "logo": font(FontsScript.FONTS.logo), "sign": font(FontsScript.FONTS.sign)}
	_build()
	_resize()

# -------------------------------------------------------------------------------------------- DOM
func _build() -> void:
	layer = CanvasLayer.new()
	layer.name = "Hud"
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "dh"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	# static tear canvas (160x90, pixelated, full screen)
	var tear := TextureRect.new()
	tear.name = "tear"
	tear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tear.set_anchors_preset(Control.PRESET_FULL_RECT)
	tear.stretch_mode = TextureRect.STRETCH_SCALE
	tear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tear.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tearImg = Image.create(160, 90, false, Image.FORMAT_RGBA8)
	_tearTex = ImageTexture.create_from_image(_tearImg)
	_tearData.resize(160 * 90 * 4)
	tear.texture = _tearTex
	tear.visible = false
	root.add_child(tear)
	# CRT vignette
	var crt := ColorRect.new()
	crt.name = "crt"
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CRT_SHADER
	sm.shader = sh
	crt.material = sm
	crt.visible = false
	root.add_child(crt)
	# the stage
	stage = Control.new()
	stage.name = "dh-s"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.modulate.a = 0.0
	stage.visible = false
	root.add_child(stage)
	var xh := DrawCtl.new(_drawCrosshair, "xh")
	var pr := DrawCtl.new(_drawPrompt, "pr")
	var pops := DrawCtl.new(_drawPops, "pops")
	var toteBox := DrawCtl.new(_drawToteBg, "tote")
	toteBox.size = Vector2(200, 52)
	var toteRow := HBoxContainer.new()
	toteRow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toteRow.alignment = BoxContainer.ALIGNMENT_CENTER
	toteRow.add_theme_constant_override("separation", 4)
	toteRow.set_anchors_preset(Control.PRESET_FULL_RECT)
	toteBox.add_child(toteRow)
	var ammo := DrawCtl.new(_drawAmmoBg, "ammo")
	ammo.size = Vector2(215, 64)
	var eq := DrawCtl.new(_drawEquipment, "eq")
	var dial := DrawCtl.new(_drawDial, "dial")
	dial.size = Vector2(84, 84)
	var chy := Control.new()
	chy.name = "chy"
	chy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chy.size = Vector2(620, 92)
	var chyBar := DrawCtl.new(_drawChyBar, "bar")
	chy.add_child(chyBar)
	var shine := ColorRect.new()
	shine.name = "shine"
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.position = Vector2(54, 10)
	shine.size = Vector2(566, 56)
	var shm := ShaderMaterial.new()
	var shs := Shader.new()
	shs.code = SHINE_SHADER
	shm.shader = shs
	shine.material = shm
	shine.visible = false
	chy.add_child(shine)
	var chyTop := DrawCtl.new(_drawChyTop, "top")
	chy.add_child(chyTop)
	var pu := DrawCtl.new(_drawPowerups, "pu")
	var rb := DrawCtl.new(_drawReplayBug, "rb")
	var fl := DrawCtl.new(_drawFlash, "fl")
	for c in [xh, pr, pops, toteBox, ammo, eq, dial, chy, pu, rb, fl]:
		stage.add_child(c)
	el = {"xh": xh, "pr": pr, "pops": pops, "tote": toteBox, "toteRow": toteRow, "ammo": ammo, "eq": eq, "dial": dial,
		"chy": chy, "chyBar": chyBar, "shine": shine, "chyTop": chyTop, "pu": pu, "rb": rb, "fl": fl, "tear": tear, "crt": crt}
	tote = FlipBoard.new(toteRow, 6, {})
	for c in tote.cards:   # .tote align-items:center (the 40 px cards sit centred in the 52 px board, not stretched to it)
		(c.el as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	magDrums = Roller.new(ammo, 3, {"cls": "mag", "x": 15.0, "y": 8.0})
	resDrums = Roller.new(ammo, 3, {"cls": "res", "x": 139.0, "y": 15.0})
	for i in int(Config.T.player.grenadesMax):
		tubes.append(false)
	for i in int(Config.T.player.teleMax):
		teles.append(false)
	game.add_child(layer)
	var vp: Viewport = game.get_viewport()
	if vp:
		vp.size_changed.connect(_resize)

func _resize() -> void:
	var vp: Viewport = game.get_viewport() if game and game.is_inside_tree() else null
	var vis := Vector2(1920, 1080)
	if vp:
		vis = vp.get_visible_rect().size
	var s := vis.y / REF_H
	scale = s
	stageW = vis.x / s
	stage.scale = Vector2(s, s)
	stage.size = Vector2(stageW, REF_H)
	# device pixels per reference px (SVG rasterizing density)
	var dev := 1.0
	if vp:
		dev = vp.get_final_transform().get_scale().y * s
	if setSvgScale(dev):
		_redrawAll()
	_layout()
	var crt: ColorRect = el.crt
	(crt.material as ShaderMaterial).set_shader_parameter("size_px", vis)

func _layout() -> void:
	var W := stageW
	el.xh.position = Vector2(W / 2.0, REF_H / 2.0)
	el.pr.position = Vector2(W / 2.0, REF_H / 2.0 + 90.0)
	el.pops.position = Vector2(W - (M + 60.0), REF_H - (M + 136.0))
	el.tote.position = Vector2(W - M - 200.0, REF_H - (M + 78.0) - 52.0)
	el.ammo.position = Vector2(W - M - 215.0, REF_H - M - 64.0)
	el.eq.position = Vector2(W - (M + 222.0), REF_H - (M + 4.0))
	el.dial.position = Vector2(M, REF_H - M - 84.0)
	el.chy.position = Vector2(M - 6.0 + _chyX / 100.0 * 620.0, REF_H - (M + 108.0) - 92.0)
	el.pu.position = Vector2(W / 2.0, REF_H - M)
	el.rb.position = Vector2(M, M)
	el.fl.position = Vector2(W / 2.0, REF_H * 0.28)

func _redrawAll() -> void:
	for k in el:
		var c = el[k]
		if c is CanvasItem:
			c.queue_redraw()
	for c in tote.cards:
		(c.el as FlipCard).redraw()
	for r in [magDrums, resDrums]:
		for dr in r.drums:
			(dr.el as Drum).queue_redraw()

func init() -> void:
	var ev = game.events
	ev.on("points:change", func(p): if p and p.get("delta"): _popupFrom("ev", p.delta))
	ev.on("points:denied", func(_p): _shakeT = 0.32)
	ev.on("zombie:hit", func(p): _mark(2 if p and p.get("head") else 1, false))
	ev.on("zombie:kill", func(p): _mark(4 if p and p.get("head") else 3, false))
	ev.on("player:hurt", func(p): _hurt(p if p else {}))
	ev.on("weapon:fire", func(_p): _kick = minf(1.0, _kick + 0.55))
	ev.on("weapon:acquire", func(p): if p and p.get("weaponId") == "tiny_tele": _hadTele = true)
	ev.on("machine:commercial_start", func(_p): suppress("commercial", true))
	ev.on("machine:commercial_end", func(_p): suppress("commercial", false))
	ev.on("machine:uplink_take", func(p): _uplinkFallback(p if p else {}))
	ev.on("perk:replay", func(p): replayBug(bool(p and (p.get("on") if p.get("on") != null else true))))
	ev.on("replay:start", func(_p): replayBug(true))
	ev.on("replay:end", func(_p): replayBug(false))
	ev.on("player:revive", func(p): if p and p.get("selfRevive"): _later(1.2, func(): replayBug(false)))
	ev.on("state", func(p): if p and not WORLD.has(p.get("to")): _releaseKnobs())

func reset() -> void:
	_dial.shown = null
	_dial.target = null
	_dial.t = -1.0
	_dialNum.text = ""
	_dialNum.rot = 0.0
	_hadTele = false
	_supp.clear()
	_pulse.static = 0.0
	_pulse.roll = 0.0
	_pulse.chroma = 0.0
	_pulse.damage = 0.0
	_white.t = -1.0
	_tear.t = -1.0
	el.tear.visible = false
	_chy.t = -1.0
	_chy.lastAt = -1e9
	_chyO = 0.0
	replayBug(false)
	_pu.clear()
	_pops.clear()
	tote.set_("      ", true)
	_shown.points = -1
	_knobs.damage.wrote = null
	setPrompt(null)
	show()

func show() -> void:
	visible = true

func hide() -> void:
	visible = false
	_applyVisibility()

func suppress(key: String, on: bool) -> void:
	if on:
		_supp[key] = true
	else:
		_supp.erase(key)
	_applyVisibility()

func setCrt(on) -> void:
	_crtOn = bool(on)
	el.crt.visible = _crtOn

func _applyVisibility() -> void:
	var st: String = game.state
	var want: bool = visible and _supp.is_empty() and (WORLD.has(st) or st == "boot")
	if want == _shown.want:
		return
	_shown.want = want
	# .dh.off: the stage and the tear hide at once (visibility), showing fades the stage in over .18 s
	stage.visible = want
	if not want:
		_stageAlpha = 0.0
		stage.modulate.a = 0.0
		el.tear.modulate.a = 0.0
	else:
		el.tear.modulate.a = 1.0

func _later(sec: float, fn: Callable) -> void:
	_timers.append({"t": sec, "fn": fn})

# -------------------------------------------------------------------------------------------- public API
# Rare, big moments only (GDD §14: no hints).
func flash(text, style: String = "default") -> void:
	_flash.text = str(text)
	_flash.style = style
	_flashT = 0.0

func pointsPopup(delta) -> void:
	if delta:
		_popupFrom("api", delta)

func hitmarker(head: bool = false, kill: bool = false) -> void:
	_mark((4 if head else 3) if kill else (2 if head else 1), true)

# obj: { key:'E', cost?, plug?, hold?, progress 0..1, denied? } | null. Called every frame by interact.gd.
func setPrompt(obj) -> void:
	var P := _prompt
	var on := obj != null and obj is Dictionary
	if on != P.on:
		P.on = on
		P.t = 0.0 if on else -1.0
		if not on:
			_dyOpacity = 0.0
			el.pr.queue_redraw()
	if not on:
		return
	# key glyph: 'E' (keyboard) or an Xbox face button ('X' / 'A' / 'B' / 'Y': round, tinted like the pad's letters)
	var k = obj.get("key")
	var key: String = String(k).substr(0, 2).to_upper() if k is String and k != "" else "E"
	var changed := false
	if key != P.key:
		P.key = key
		changed = true
	var plug := _tb(obj.get("plug"))
	var c = obj.get("cost")
	var cost := -1
	if not plug and (c is int or c is float) and is_finite(float(c)) and float(c) > 0.0:
		cost = int(floorf(float(c) + 0.5))
	if cost != P.cost:
		P.cost = cost
		changed = true
	var denied: bool = cost >= 0 and _tb(obj.get("denied"))
	if denied != P.denied:
		P.denied = denied
		changed = true
	if plug != P.plug:
		P.plug = plug
		changed = true
	var hold := _tb(obj.get("hold"))
	if hold != P.hold:
		P.hold = hold
		changed = true
	var prog := floorf(clamp_(float(obj.get("progress", 0.0) if obj.get("progress") != null else 0.0), 0.0, 1.0) * 200.0 + 0.5) / 200.0 if hold else 0.0
	if prog != P.prog:
		P.prog = prog
		changed = true
	if changed:
		el.pr.queue_redraw()

func chyron(nm, sub = "") -> void:
	if not nm:
		return
	var now: float = game.time.realNow
	var C := _chy
	if C.t >= 0.0 and C.name == str(nm) and C.t < 2.5:
		return
	C.name = str(nm)
	C.t = 0.0
	C.lastAt = now
	C.sub = str(sub) if sub else ""
	# restart the shine animation (.go)
	_shineT = 0.0
	el.chyTop.queue_redraw()
	el.chyBar.queue_redraw()

func replayBug(on) -> void:
	_replay = bool(on)
	el.rb.queue_redraw()

func setReplay(on) -> void:
	replayBug(on)

func showReplayBug() -> void:
	replayBug(true)

func hideReplayBug() -> void:
	replayBug(false)

func whiteout(seconds = null, amount: float = 1.0) -> void:
	var sec: float = float(Config.T.zombies.bigShot.flash.white) if seconds == null else float(seconds)
	_white.t = 0.0
	_white.dur = maxf(0.1, sec)
	_white.amount = clamp_(amount, 0.0, 1.0)

func glitch(amount: float = 0.5, seconds: float = 0.3) -> void:
	var a := clamp_(amount, 0.0, 1.0)
	_pulse.static = maxf(_pulse.static, 0.35 * a)
	_pulse.roll = maxf(_pulse.roll, 0.5 * a)
	_pulse.chroma = maxf(_pulse.chroma, 4.0 * a)
	_pulseDecay = 1.0 / maxf(0.05, seconds)

func tear(edgeOrPos) -> void:
	var edge = edgeOrPos
	if edgeOrPos is Vector3:
		edge = _edgeToward(edgeOrPos)
	if not (edge is String) or not ["left", "right", "top", "bottom"].has(edge):
		return
	_tear.edge = edge
	_tear.t = 0.0
	_tear.acc = 1.0
	_tear.seed = randf() * 1000.0
	el.tear.visible = true

# -------------------------------------------------------------------------------------------- internals
func _dup(kind: String, key, from: String) -> bool:
	var f: int = game.time.frame
	if f != _frame:
		_frame = f
		_dedupe.clear()
	var k := "%s|%s" % [kind, key]
	var e = _dedupe.get(k)
	if e == null:
		e = {"ev": 0, "api": 0}
		_dedupe[k] = e
	e[from] += 1
	var other := "api" if from == "ev" else "ev"
	return e[from] <= e[other]

func _popupFrom(from: String, delta) -> void:
	if _dup("pts", delta, from):
		return
	if delta < 0:
		_spendT = 0.2
		_toteInk()
		return
	var now: float = game.time.realNow
	var last = _pops.back() if not _pops.is_empty() else null
	if last and now - last.born < 0.14:
		last.value += delta
		last.text = "+%s" % _num(last.value)
		return
	var gold := _gold()
	_pops.append({"born": now, "value": delta, "text": "+%s" % _num(delta), "gold": gold, "right": float(_pops.size() % 3) * 14.0})

static func _num(v) -> String:
	if v is float and v == floorf(v):
		return str(int(v))
	return str(v)

func _gold() -> bool:
	var g = game
	var eco = g.economy
	if eco and eco.get("multiplier") != null and float(eco.multiplier) > 1.0:
		return true
	var pu = g.powerups
	if pu and pu.get("active") is Dictionary:
		var sw = pu.active.get("sweeps_week")
		return sw != null and float(sw) > 0.0
	return false

func _mark(level: int, fromApi: bool) -> void:
	if fromApi:
		# hitmarker() calls without a zombie event this frame still tick.
		var id := "ui_kill" if level >= 3 else ("ui_hit_head" if level == 2 else "ui_hit")
		_play(id)
	if level > _hm:
		_hm = level

func _play(id: String, opts: Dictionary = {}) -> void:
	var a = game.audio
	if a and a.has_method("play"):
		a.play(id, opts)

func _hurt(p: Dictionary) -> void:
	var pl = game.player
	var max_h := 150.0
	if pl and pl.get("maxHealth"):
		max_h = float(pl.maxHealth)
	# GDD §14 "signal loss": edge static, chroma up to 4 px, a SLIGHT roll; the edge static itself follows HP
	# (player.gd drives post.damage), a hit only adds a short kick on top.
	var dmg: float = float(p.get("dmg")) if p.get("dmg") else 20.0
	var k := clamp_(dmg / max_h, 0.08, 0.6)
	_pulse.static = maxf(_pulse.static, 0.015 + k * 0.08)
	_pulse.roll = maxf(_pulse.roll, 0.05 + k * 0.18)
	_pulse.chroma = maxf(_pulse.chroma, 1.5 + k * 4.0)
	_pulse.damage = maxf(_pulse.damage, 0.04 + k * 0.15)
	_pulseDecay = 3.2
	if p.get("from") is Vector3:
		var edge = _edgeToward(p.from)
		if edge:
			tear(edge)

# The screen edge toward a world position, or null when it is inside the view.
func _edgeToward(pos: Vector3):
	var cam: Camera3D = game.camera
	if cam == null:
		return null
	var v: Vector3 = cam.global_transform.basis.inverse() * (pos - cam.global_position) # camera space: x right, y up, -z forward
	var front := v.z < 0.0
	if front:
		var vp_size := cam.get_viewport().get_visible_rect().size if cam.get_viewport() else Vector2(16, 9)
		var aspect := vp_size.x / maxf(1.0, vp_size.y)
		var tanV := tan(deg_to_rad(cam.fov) / 2.0)
		var tanH := tanV * aspect
		var nx := v.x / (-v.z * tanH)
		var ny := v.y / (-v.z * tanV)
		if absf(nx) < 0.92 and absf(ny) < 0.92:
			return null
		if absf(nx) >= absf(ny):
			return "left" if nx < 0.0 else "right"
		return "bottom" if ny < 0.0 else "top"
	# Behind: left/right by side, straight behind reads as the bottom edge.
	if absf(v.x) < absf(v.z) * 0.35:
		return "bottom"
	return "left" if v.x < 0.0 else "right"

func _releaseKnobs() -> void:
	if not _knobsOn:
		return
	_knobsOn = false
	var post = game.render.get("post") if game.render else null
	if not (post is Dictionary):
		return
	for k in _knobs:
		_knobs[k].release(post)

func _uplinkFallback(p: Dictionary) -> void:
	var now: float = game.time.realNow
	if now - _chy.lastAt < 20.0:
		return
	var defs = game.weapons.get("defs") if game.weapons else null
	var d = defs.get(p.get("weaponId")) if defs is Dictionary and p.get("weaponId") else null
	if d is Dictionary and d.get("upgradedName"):
		chyron(d.upgradedName)

# -------------------------------------------------------------------------------------------- per frame
func update(dt: float) -> void:
	var g = game
	_time += dt
	for i in range(_timers.size() - 1, -1, -1):
		_timers[i].t -= dt
		if _timers[i].t <= 0.0:
			var fn: Callable = _timers[i].fn
			_timers.remove_at(i)
			fn.call()
	_applyVisibility()
	if stage.visible and _stageAlpha < 1.0:
		_stageAlpha = minf(1.0, _stageAlpha + dt / 0.18)
		stage.modulate.a = cssEase(_stageAlpha)
	_updatePost(dt)
	_updateTear(dt)
	_updateFlash(dt)
	if _shown.want == false and not WORLD.has(g.state):
		return
	_updateCrosshair(dt)
	_updatePrompt(dt)
	_updatePoints(dt)
	_updateAmmo(dt)
	_updateEquipment()
	_updateDial(dt)
	_updateChyron(dt)
	_updatePowerups(dt)
	if _replay:
		el.rb.queue_redraw()

func _updatePost(dt: float) -> void:
	var g = game
	var post = g.render.get("post") if g.render else null
	var P := _pulse
	var W := _white
	var decay := exp(-dt * (_pulseDecay if _pulseDecay else 3.2))
	P.static *= decay
	P.roll *= decay
	P.chroma *= decay
	P.damage *= exp(-dt * 2.6)
	if P.static < 0.002: P.static = 0.0
	if P.roll < 0.002: P.roll = 0.0
	if P.chroma < 0.01: P.chroma = 0.0
	if P.damage < 0.002: P.damage = 0.0
	var white := 0.0
	if W.t >= 0.0:
		W.t += dt
		var hold := 0.08
		white = W.amount if W.t < hold else W.amount * (1.0 - easeOut(clamp_((W.t - hold) / W.dur, 0.0, 1.0)))
		if W.t > W.dur + hold:
			W.t = -1.0
	if not (post is Dictionary) or not WORLD.has(g.state):
		return
	_knobsOn = true
	var K := _knobs
	K.damage.apply(post, P.damage, "add", dt)
	K.static.apply(post, P.static, "max", dt)
	K.roll.apply(post, P.roll, "max", dt)
	K.chroma.apply(post, P.chroma, "max", dt)
	# Whiteout never sticks: an external flash nobody fades decays by itself over the Big Shot's 1.5 s.
	var kw: Knob = K.whiteout
	if kw.wrote != null and float(post.get("whiteout", 0.0)) == kw.wrote and kw.ext > 0.0 and kw.still > 0.2:
		kw.ext = maxf(0.0, kw.ext - dt / float(Config.T.zombies.bigShot.flash.white))
	kw.apply(post, white, "max", dt)

func _updateTear(dt: float) -> void:
	var tr := _tear
	if tr.t < 0.0:
		return
	tr.t += dt
	var life := 0.38
	if tr.t >= life:
		tr.t = -1.0
		el.tear.visible = false
		return
	tr.acc += dt
	if tr.acc < 1.0 / 30.0:
		return
	tr.acc = 0.0
	var W := 160
	var H := 90
	var d := _tearData
	var k: float = 1.0 - tr.t / life
	var horiz: bool = tr.edge == "left" or tr.edge == "right"
	var lines := H if horiz else W
	var span := W if horiz else H
	var base := (0.2 if horiz else 0.26) * span * (0.45 + 0.55 * k)
	d.fill(0)
	var jag := 0.0
	for l in lines:
		if (l & 3) == 0:
			jag = (randf() - 0.3) * base * 0.8
		var streak := base * (0.8 + randf()) if randf() < 0.05 else 0.0
		var depth := maxf(0.0, base * (0.55 + 0.45 * sin(l * 0.37 + tr.seed)) + jag + streak)
		var n := mini(span, int(ceil(depth)))
		for s in n:
			var x: int = (s if tr.edge == "left" else W - 1 - s) if horiz else l
			var y: int = l if horiz else (s if tr.edge == "top" else H - 1 - s)
			var i := (y * W + x) * 4
			var v := randf()
			var c := 60.0 + v * v * 195.0
			d[i] = int(c)
			d[i + 1] = int(minf(255.0, c * 1.02))
			d[i + 2] = int(minf(255.0, c * 1.12))
			d[i + 3] = int(clampf(255.0 * k * clamp_(1.15 - s / (depth + 1.0), 0.0, 1.0) * (0.55 + 0.45 * v), 0.0, 255.0))
	_tearImg.set_data(W, H, false, Image.FORMAT_RGBA8, d)
	_tearTex.update(_tearImg)

func _updateFlash(dt: float) -> void:
	if _flashT < 0.0:
		return
	_flashT += dt
	var t := _flashT
	if t > 2.4:
		_flash.opacity = 0.0
		_flashT = -1.0
		el.fl.queue_redraw()
		return
	var s := 0.4 + 0.6 * easeOutBack(t / 0.25, 2.4) if t < 0.25 else 1.0
	var o := t / 0.1 if t < 0.1 else (1.0 - (t - 2.0) / 0.4 if t > 2.0 else 1.0)
	_flash.opacity = o
	_flash.s = s
	el.fl.queue_redraw()

func _updateCrosshair(dt: float) -> void:
	var g = game
	var S := _shown
	var w = g.weapons
	var pl = g.player
	var deg := 1.5
	var def = w.currentDef() if w and w.has_method("currentDef") else null
	if w and w.has_method("currentSpread"):
		deg = float(w.currentSpread())
	elif def is Dictionary and def.get("spread"):
		deg = float(def.spread[1 if pl and pl.get("ads") else 0])
	_kick *= exp(-dt * 11.0)
	var fovDeg := 70.0
	if g.camera and g.camera.fov:
		fovDeg = g.camera.fov
	var fov := deg_to_rad(fovDeg)
	var cone := tan(deg_to_rad(deg)) / tan(fov / 2.0) * (REF_H / 2.0)
	var spread := int(floorf(clamp_(cone, 5.0, 150.0) + _kick * 9.0 + 0.5))
	if spread != S.spread:
		S.spread = spread
	var dim: bool = pl != null and bool(pl.get("sprinting"))
	if dim != S.dim:
		S.dim = dim
	# .xh transition: opacity .15s
	var want := 0.3 if dim else 1.0
	if _xhAlpha != want:
		var step := dt / 0.15 * 0.7
		_xhAlpha = minf(want, _xhAlpha + step) if want > _xhAlpha else maxf(want, _xhAlpha - step)
	el.xh.modulate.a = _xhAlpha

	# Hitmarker: the strongest hit this frame restarts the X; kills are bigger, headshot kills pop a star.
	if _hm > 0:
		var lv := _hm
		_hm = 0
		if lv >= _hmLevel or _hmT > 0.08 or _hmT < 0.0:
			_hmLevel = lv
			_hmT = 0.0
			_hmState.col = HIT_COL[lv]
			if lv == 4:
				_starT = 0.0
	if _hmT >= 0.0:
		_hmT += dt
		var t := _hmT
		var kill := _hmLevel >= 3
		var life := 0.3 if kill else 0.2
		var pop := 1.35 - (t / 0.06) * 0.35 if t < 0.06 else 1.0
		var gap := (13.0 if kill else 10.0) * pop
		var ln := 1.25 if kill else 1.0
		_hmState.opacity = 1.0 if t < life * 0.6 else clamp_(1.0 - (t - life * 0.6) / (life * 0.4), 0.0, 1.0)
		_hmState.gap = gap
		_hmState.sx = 1.25 if kill else 1.0
		_hmState.len = ln
		if t > life:
			_hmT = -1.0
			_hmLevel = 0
			_hmState.opacity = 0.0
	if _starT >= 0.0:
		_starT += dt
		var t2 := _starT
		var s := easeOutBack(t2 / 0.18, 3.0) * 1.1 if t2 < 0.18 else 1.1 - (t2 - 0.18) * 0.3
		_starState.opacity = 1.0 if t2 < 0.35 else clamp_(1.0 - (t2 - 0.35) / 0.2, 0.0, 1.0)
		_starState.ty = -t2 * 30.0
		_starState.rot = t2 * 220.0
		_starState.s = maxf(0.0, s)
		if t2 > 0.55:
			_starT = -1.0
			_starState.opacity = 0.0
	el.xh.queue_redraw()

func _updatePrompt(dt: float) -> void:
	var P := _prompt
	if not P.on:
		return
	if P.t >= 0.0 and P.t < 1.0:
		P.t += dt
		var t := clamp_(P.t / 0.18, 0.0, 1.0)
		_dyOpacity = clamp_(P.t / 0.06, 0.0, 1.0)
		_dyScale = 0.62 + 0.38 * easeOutBack(t, 2.6)
	var dx := 0.0
	if _shakeT > 0.0:
		_shakeT = maxf(0.0, _shakeT - dt)
		dx = sin(_shakeT * 70.0) * 9.0 * (_shakeT / 0.32)
	_dyDx = snappedf(dx, 0.1)
	el.pr.queue_redraw()

func _updatePoints(dt: float) -> void:
	var g = game
	var S := _shown
	var eco = g.economy
	var pts := int(clamp_(floorf(float(eco.get("points") if eco.get("points") else 0)), 0.0, 999999.0)) if eco else 0
	if pts != S.points:
		var first: bool = S.points < 0
		S.points = pts
		tote.set_(str(pts).lpad(6, " "), first)
	tote.update(dt)
	var gold := _gold()
	if gold != S.gold:
		S.gold = gold
		_toteInk()
	if _spendT > 0.0:
		_spendT -= dt
		if _spendT <= 0.0:
			_toteInk()
	var now: float = g.time.realNow
	while not _pops.is_empty() and now - _pops[0].born > 0.62:
		_pops.pop_front()
	el.pops.queue_redraw()

# .tote.gold / .tote.spend digit inks (spend wins: it is declared last in the CSS)
func _toteInk() -> void:
	if _spendT > 0.0:
		tote.setInk("#FF4A3A", [[0.0, 0.0, 9.0, "rgba(255,50,30,.9)"]])
	elif _shown.gold:
		tote.setInk("#FFE66A", [[0.0, 0.0, 9.0, "rgba(255,210,60,.95)"], [0.0, 0.0, 2.0, "#fff"]])
	else:
		tote.setInk("#FFB347", [[0.0, 0.0, 7.0, "rgba(255,150,40,.75)"]])

func _updateAmmo(dt: float) -> void:
	var g = game
	var S := _shown
	var w = g.weapons
	var slot = null
	if w and w.get("slots") != null and w.get("current") != null:
		var slots = w.slots
		var cur = w.current
		if slots is Array and cur is int and cur >= 0 and cur < slots.size():
			slot = slots[cur]
		elif slots is Dictionary:
			slot = slots.get(cur)
	var def = w.currentDef() if w and w.has_method("currentDef") else null
	var has: bool = slot is Dictionary and def is Dictionary and float(def.get("mag", 0)) > 0.0 and (slot.get("mag") is int or slot.get("mag") is float) and is_finite(float(slot.mag))
	if (not has) != S.noAmmo:
		S.noAmmo = not has
		el.ammo.visible = has
	if not has:
		return
	var mag: float = float(slot.mag)
	var r = slot.get("reserve")
	var res: float = float(r) if (r is int or r is float) and is_finite(float(r)) else 0.0
	if mag != S.mag:
		S.mag = mag
		magDrums.set_(mag)
	if res != S.res:
		S.res = res
		resDrums.set_(res)
	var low: bool = mag <= ceilf(float(def.mag) * 0.25)
	if low != S.low:
		S.low = low
		_lowT = 0.0
	magDrums.tick(dt)
	resDrums.tick(dt)
	# .ammo.low .mag .rd:not(.lead): color #FF4A3A -> #7A1A14, .45s ease-in-out infinite alternate
	var ink = null
	if S.low:
		_lowT += dt
		var cyc := _lowT / 0.45
		var p := fmod(cyc, 1.0)
		if int(floorf(cyc)) % 2 == 1:
			p = 1.0 - p
		ink = DAU.color("#FF4A3A").lerp(DAU.color("#7A1A14"), cssEaseInOut(p))
	for dr in magDrums.drums:
		var d: Drum = dr.el
		if ink != d.ink:
			d.ink = ink
			d.queue_redraw()

func _updateEquipment() -> void:
	var w = game.weapons
	var S := _shown
	if not w:
		return
	var eqp = w.get("equipment")
	var gv = w.get("grenades")
	if gv == null and eqp is Dictionary:
		gv = eqp.get("grenades")
	var gren := int(clamp_(floorf(float(gv if gv != null else 0)), 0.0, float(tubes.size())))
	if gren != S.gren:
		S.gren = gren
		for i in tubes.size():
			tubes[i] = i < gren
		el.eq.queue_redraw()
	var tv = w.get("teles")
	if tv == null and eqp is Dictionary:
		tv = eqp.get("teles")
	var tele := int(clamp_(floorf(float(tv if tv != null else 0)), 0.0, float(teles.size())))
	if tele > 0:
		_hadTele = true
	if tele != S.tele:
		S.tele = tele
		for i in teles.size():
			teles[i] = i < tele
		el.eq.queue_redraw()
	var row := _hadTele
	if row != S.teleRow:
		S.teleRow = row
		el.eq.queue_redraw()

func _updateDial(dt: float) -> void:
	var g = game
	var D := _dial
	var boss: bool = g.boss != null and bool(g.boss.get("active"))
	var rnd: int = int(g.rounds.get("round")) if g.rounds and g.rounds.get("round") != null else 0
	var want := "–" if boss else (str(rnd) if rnd > 0 else "")
	if want != D.target:
		D.target = want
		if D.shown == null and want == "":
			D.shown = ""
			_dialNum.text = ""
			el.dial.queue_redraw()
		else:
			D.t = 0.0
			D.from = fmod(D.spin, 360.0)
			D.spin = D.from
	if D.t < 0.0:
		return
	D.t += dt
	var dur := 0.85
	var t := clamp_(D.t / dur, 0.0, 1.0)
	# Knob: 1.25 turns with an overshoot, clicking into the detent; the number swaps mid-spin.
	var ang: float = D.from + 450.0 * easeOutBack(t, 1.4)
	D.spin = ang
	_dialNum.rot = snappedf(ang, 0.1)
	var blur := clamp_((t - 0.05) / 0.2, 0.0, 1.0) if t < 0.55 else clamp_(1.0 - (t - 0.55) / 0.12, 0.0, 1.0)
	if t >= 0.55 and D.shown != D.target:
		D.shown = D.target
		_dialNum.text = D.shown
		_dialNum.small = String(D.shown).length() > 2
	var squash := sin(((t - 0.55) / 0.3) * PI) * 0.22 if t > 0.55 and t < 0.85 else 0.0
	_dialNum.opacity = 1.0 - blur * 0.85
	_dialNum.sx = 1.0 + squash
	_dialNum.sy = 1.0 - squash * 0.7 - blur * 0.35
	if t >= 0.62 and not D.clicked:
		D.clicked = true
		_play("ui_round_dial")
	if t >= 1.0:
		D.t = -1.0
		D.clicked = false
		_dialNum.sx = 1.0
		_dialNum.sy = 1.0
		_dialNum.opacity = 1.0
	el.dial.queue_redraw()

func _updateChyron(dt: float) -> void:
	var C := _chy
	if _shineT >= 0.0:
		_shineT += dt
		# .chy.go .shine::before: animation dhshine .9s .25s ease-out (left -80px -> 110%)
		var p := clamp_((_shineT - 0.25) / 0.9, 0.0, 1.0)
		var shine: ColorRect = el.shine
		shine.visible = _shineT >= 0.25 and p < 1.0
		(shine.material as ShaderMaterial).set_shader_parameter("left_px", lerpf(-80.0, 566.0 * 1.1, cssEaseOut(p)))
		if p >= 1.0:
			_shineT = -1.0
			shine.visible = false
	if C.t < 0.0:
		return
	C.t += dt
	var t: float = C.t
	var inT := 0.4
	var hold := 2.5
	var outT := 0.35
	var x := 0.0
	var o := 1.0
	if t < inT:
		x = -120.0 + 120.0 * easeOutBack(t / inT, 1.2)
	elif t < inT + hold:
		x = 0.0
	elif t < inT + hold + outT:
		var p2 := (t - inT - hold) / outT
		x = -120.0 * easeIn(p2)
		o = 1.0 - p2 * 0.5
	else:
		C.t = -1.0
		_chyO = 0.0
		el.chy.modulate.a = 0.0
		return
	_chyO = o
	_chyX = snappedf(x, 0.1)
	el.chy.modulate.a = o
	el.chy.position.x = M - 6.0 + _chyX / 100.0 * 620.0

func _updatePowerups(dt: float) -> void:
	var pu = game.powerups
	var act = pu.get("active") if pu else null
	var seen := {}
	if act is Dictionary:
		for type in act:
			var left = act[type]
			if not ((left is float or left is int) and float(left) > 0.0):
				continue
			seen[type] = true
			var it = _pu.get(type)
			if it == null:
				var total := maxf(float(PU_TOTAL().get(type, left)), float(left))
				# class 'in' removed on the next frame: transition scale 0 -> 1 (.2s cubic-bezier(.3,1.6,.5,1)), opacity (.2s ease)
				it = {"type": type, "total": total, "blink": null, "off": -1.0, "k": 0.0, "dir": 1, "born": _time, "gone": false}
				_pu[type] = it
			if float(left) > it.total:
				it.total = float(left)
			var off := snappedf(PU_C * (1.0 - float(left) / it.total), 0.1)
			it.off = off
			it.blink = float(left) <= 5.0
	for type in _pu.keys():
		var it2: Dictionary = _pu[type]
		if not seen.has(type) and not it2.gone:
			it2.gone = true
			it2.dir = -1
			it2.goneAt = _time
		# transition clock
		if it2.dir > 0 and _time - it2.born > 0.0:
			it2.k = minf(1.0, it2.k + dt / 0.2)
		elif it2.dir < 0:
			it2.k = maxf(0.0, it2.k - dt / 0.2)
			if _time - it2.goneAt >= 0.22:
				_pu.erase(type)
	el.pu.queue_redraw()

# ================================================================================================ painting
func _tx(key: String, svg_fn: Callable) -> Texture2D:
	var k := "%s@%s" % [key, svgScale]
	if _svgCache.has(k):
		return _svgCache[k]
	var t: Texture2D = svg_fn.call()
	_svgCache[k] = t
	return t

# ---- crosshair
func _drawCrosshair(ci: Control) -> void:
	var spread: float = float(_shown.spread) if _shown.spread != null and _shown.spread >= 0 else 5.0
	var dot := _tx("dot", func(): return svgTexture(svgDoc(-4, -4, 8, 8, '<circle r="4" %s/><circle r="2.5" %s/>' % [fillAttr("rgba(40,22,48,.75)"), fillAttr(CREAM)])))
	if dot:
		ci.draw_texture_rect(dot, Rect2(-4, -4, 8, 8), false)
	var tv := _tx("tkv", func(): return svgTexture(svgDoc(-1.5, -1.5, 6, 14, '<path d="%s" %s/><path d="%s" %s/>' % [rrd(-1.5, -1.5, 6, 14, 3.5), fillAttr("rgba(40,22,48,.7)"), rrd(0, 0, 3, 11, 2), fillAttr(CREAM)])))
	var th := _tx("tkh", func(): return svgTexture(svgDoc(-1.5, -1.5, 14, 6, '<path d="%s" %s/><path d="%s" %s/>' % [rrd(-1.5, -1.5, 14, 6, 3.5), fillAttr("rgba(40,22,48,.7)"), rrd(0, 0, 11, 3, 2), fillAttr(CREAM)])))
	if tv:
		ci.draw_texture_rect(tv, Rect2(-1.5 - 1.5, -spread - 11.0 - 1.5, 6, 14), false)
		ci.draw_texture_rect(tv, Rect2(-1.5 - 1.5, spread - 1.5, 6, 14), false)
	if th:
		ci.draw_texture_rect(th, Rect2(-spread - 11.0 - 1.5, -1.5 - 1.5, 14, 6), false)
		ci.draw_texture_rect(th, Rect2(spread - 1.5, -1.5 - 1.5, 14, 6), false)
	# hitmarker bars
	if _hmState.opacity > 0.0:
		var col: String = _hmState.col
		var bar := _tx("hm" + col, func(): return svgTexture(svgDoc(-3.5, -8, 7, 16, '<path d="%s" %s/><path d="%s" %s/>' % [rrd(-3.5, -8, 7, 16, 3.5), fillAttr("rgba(40,18,24,.7)"), rrd(-2, -6.5, 4, 13, 2), fillAttr(col)])))
		for i in 4:
			var a := deg_to_rad(45.0 + i * 90.0)
			var gap: float = _hmState.gap
			# rotate(a) translateY(-gap-6) scale(sx, len), origin = the bar centre
			var xf := Transform2D(a, Vector2.ZERO) * Transform2D(0.0, Vector2(0, -gap - 6.0)) * Transform2D(0.0, Vector2(_hmState.sx, _hmState.len), 0.0, Vector2.ZERO)
			ci.draw_set_transform_matrix(xf)
			if bar:
				ci.draw_texture_rect(bar, Rect2(-3.5, -8, 7, 16), false, Color(1, 1, 1, _hmState.opacity))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if _starState.opacity > 0.0:
		var star := _tx("star", func(): return svgTexture(iconSvg(STAR_PATH % 'fill="#FFD23A" stroke="#7A3A12"', 40, 40, 30, 30, [[0.0, 2.0, 0.0, "rgba(60,20,10,.6)"]])))
		var xf2 := Transform2D(0.0, Vector2(0, -47.0 + _starState.ty)) * Transform2D(deg_to_rad(_starState.rot), Vector2.ZERO) * Transform2D(0.0, Vector2(_starState.s, _starState.s), 0.0, Vector2.ZERO)
		ci.draw_set_transform_matrix(xf2)
		if star:
			ci.draw_texture_rect(star, Rect2(-15 - 8, -15 - 8, 46, 46), false, Color(1, 1, 1, _starState.opacity))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- dymo prompt
func _costWidth(cost: String) -> float:
	var f: Font = _fonts.hud
	return textWidth(f, cost, 34.0, 34.0 * 0.07)

func _dymoSvg(w: float, h: float) -> String:
	# jagged clip-path polygon, gradient, ::before highlight strip, filter drop-shadow(0 5px 6px rgba(0,0,0,.45))
	var pts := [[0, 8], [1.2, 0], [98.8, 0], [100, 9], [99.2, 22], [100, 36], [99.2, 50], [100, 64], [99.2, 78], [100, 91], [98.8, 100], [1.2, 100], [0, 92], [0.8, 78], [0, 64], [0.8, 50], [0, 36], [0.8, 22]]
	var d := "M"
	for i in pts.size():
		d += "%s %s%s" % [n_(pts[i][0] / 100.0 * w), n_(pts[i][1] / 100.0 * h), "L" if i < pts.size() - 1 else "Z"]
	var defs := linGrad("g", 0, 0, w, h, 180, [["#3A3A40", 0.0], ["#1C1C21", 0.16], ["#121216", 0.55], ["#1E1E24", 0.88], ["#34343C", 1.0]])
	defs += linGrad("hl", 0, 5, w, 5, 90, [["transparent", 0.0], ["rgba(255,255,255,.14)", 0.2], ["rgba(255,255,255,.06)", 0.7], ["transparent", 1.0]])
	defs += clipDef("c", d) + blurFilter("sh", 6.0)
	var body := '<path d="%s" fill="#000" fill-opacity=".45" transform="translate(0 5)" filter="url(#sh)"/>' % d
	body += '<path d="%s" fill="url(#g)"/>' % d
	body += '<g clip-path="url(#c)"><rect x="0" y="5" width="%s" height="5" fill="url(#hl)"/></g>' % n_(w)
	return svgDoc(-14, -10, w + 28, h + 30, body, defs)

func _keySvg(pad: bool) -> String:
	# .key: 40x40 r9 (pad: round + radial gradient), inset 0 0 0 3px rgba(242,240,234,.9), inset 0 3px 0 3px rgba(0,0,0,.35),
	# 0 1px 0 rgba(255,255,255,.3)
	var r = 20.0 if pad else 9.0
	var defs: Array = []
	var d := rrd(0, 0, 40, 40, r)
	defs.append(clipDef("c", d))
	var body := boxShadow(defs, "o", 0, 0, 40, 40, r, 0, 1, 0, 0, "rgba(255,255,255,.3)")
	if pad:
		defs.append(radGrad("rg", 16.8, 13.6, farCorner(0, 0, 40, 40, 16.8, 13.6), [["#34343C", 0.0], ["#18181D", 0.7]]))
		body += '<path d="%s" fill="url(#rg)"/>' % d
	else:
		# the key face itself is transparent (the label shows through); cover the 1px outer shadow under it
		body = '<g clip-path="url(#nc)">%s</g>' % body
		defs.append('<clipPath id="nc"><path fill-rule="evenodd" d="M-5 -5H45V46H-5Z %s"/></clipPath>' % d)
	body += insetShadow(defs, "i2", "c", 0, 0, 40, 40, r, 0, 3, 0, 3, "rgba(0,0,0,.35)")
	body += insetShadow(defs, "i1", "c", 0, 0, 40, 40, r, 0, 0, 0, 3, "rgba(242,240,234,.9)")
	return svgDoc(-2, -2, 44, 44, body, "".join(defs))

func _drawPrompt(ci: Control) -> void:
	var P := _prompt
	if not P.on or _dyOpacity <= 0.0:
		return
	var f: Font = _fonts.hud
	var costS: String = str(P.cost) if P.cost >= 0 else ""
	var w := 16.0 + 40.0
	if costS != "":
		w += 14.0 + _costWidth(costS)
	if P.plug:
		w += 14.0 + 58.0
	w += 22.0
	var h := 54.0
	w = ceilf(w)
	# translate(calc(-50% + dx), 0) rotate(-2.5deg) scale(s), origin 50% 50%
	var c := Vector2(-w / 2.0 + _dyDx + w / 2.0, h / 2.0)
	var xf := Transform2D(0.0, c) * Transform2D(deg_to_rad(-2.5), Vector2.ZERO) * Transform2D(0.0, Vector2(_dyScale, _dyScale), 0.0, Vector2.ZERO) * Transform2D(0.0, Vector2(-w / 2.0, -h / 2.0))
	ci.draw_set_transform_matrix(xf)
	var a := _dyOpacity
	var bg := _tx("dymo%d" % int(w), func(): return svgTexture(_dymoSvg(w, h)))
	if bg:
		ci.draw_texture_rect(bg, Rect2(-14, -10, w + 28, h + 30), false, Color(1, 1, 1, a))
	var x := 16.0
	var pad: bool = PAD_KEYS.has(P.key) and P.key != "E"
	var keyTex := _tx("key%s" % pad, func(): return svgTexture(_keySvg(pad)))
	var ky := (h - 40.0) / 2.0
	if keyTex:
		ci.draw_texture_rect(keyTex, Rect2(x - 2, ky - 2, 44, 44), false, Color(1, 1, 1, a))
	# key letter (26 px; pad: 25 px, tinted with a glow, nudged 1 px down)
	var emb := [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 1.0, 0.0, "rgba(255,255,255,.35)"], [0.0, 2.0, 3.0, "rgba(0,0,0,.5)"]]
	var ksize := 25.0 if pad else 26.0
	var kcol := DAU.color("#F2F0EA")
	var ksh := emb
	if pad:
		var PADC := {"X": ["#6FA8FF", "rgba(80,150,255,.55)"], "A": ["#7EDB5A", "rgba(110,220,80,.5)"], "B": ["#FF6A5C", "rgba(255,90,70,.5)"], "Y": ["#FFD24A", "rgba(255,210,70,.5)"]}
		var pc: Array = PADC[P.key]
		kcol = DAU.color(pc[0])
		ksh = [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 0.0, 8.0, pc[1]]]
	var kls := ksize * 0.07
	var kw := textWidth(f, P.key, ksize, kls)
	kcol.a *= a
	drawText(ci, f, x + (40.0 - kw) / 2.0, baselineAt(f, ksize, ky + 20.0 + (1.0 if pad else 0.0)), P.key, ksize, kcol, kls, ksh)
	# hold ring (svg.ring 64x64 at -12,-12 of the key, rotate(-90deg))
	if P.hold:
		var kc := Vector2(x + 20.0, ky + 20.0)
		ci.draw_arc(kc, RING_R, 0.0, TAU, 64, Color(1, 1, 1, 0.14 * a), 5.0, true)
		if P.prog > 0.0:
			var endA: float = -PI / 2.0 + TAU * P.prog
			ci.draw_arc(kc, RING_R, -PI / 2.0, endA, maxi(4, int(64 * P.prog)), Color(DAU.color("#FFD23A"), a), 5.0, true)
			for pa in [-PI / 2.0, endA]:
				ci.draw_circle(kc + Vector2(cos(pa), sin(pa)) * RING_R, 2.5, Color(DAU.color("#FFD23A"), a))
	x += 40.0
	if costS != "":
		x += 14.0
		var ls := 34.0 * 0.07
		var col := DAU.color("#FF5A46" if P.denied else "#F2F0EA")
		col.a *= a
		var sh: Array = [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 1.0, 0.0, "rgba(255,160,140,.35)"], [0.0, 0.0, 10.0, "rgba(255,60,40,.45)"]] if P.denied else emb
		var base := baselineAt(f, 34.0, h / 2.0)
		for i in costS.length():
			var ch := costS.substr(i, 1)
			var cw := f.get_char_size(ch.unicode_at(0), 34).x + ls
			# span: translateY(((i*7)%3)-1 px) rotate(((i*5)%3-1)*1.5deg), origin = the span's centre
			var ty := float(((i * 7) % 3) - 1)
			var rot := deg_to_rad(float(((i * 5) % 3) - 1) * 1.5)
			var sc := Vector2(x + cw / 2.0, h / 2.0)
			ci.draw_set_transform_matrix(xf * Transform2D(0.0, sc + Vector2(0, ty)) * Transform2D(rot, Vector2.ZERO) * Transform2D(0.0, -sc))
			drawText(ci, f, x, base, ch, 34.0, col, ls, sh)
			x += cw
		ci.draw_set_transform_matrix(xf)
	if P.plug:
		x += 14.0
		var plug := _tx("plug", func(): return svgTexture(iconSvg(PLUG_SVG, 64, 40, 58, 36, [[0.0, 1.0, 0.0, "rgba(255,255,255,.3)"], [0.0, -1.0, 0.0, "rgba(0,0,0,.9)"]])))
		if plug:
			ci.draw_texture_rect(plug, Rect2(x - 8, (h - 36.0) / 2.0 - 8, 58 + 16, 36 + 16), false, Color(1, 1, 1, a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- points
func _drawToteBg(ci: Control) -> void:
	var t := _tx("tote", func():
		var defs: Array = []
		var d := rrd(0, 0, 200, 52, 13)
		defs.append(linGrad("g", 0, 0, 200, 52, 180, [["#6A4428", 0.0], ["#4A2E1A", 0.45], ["#3A2214", 1.0]]))
		defs.append(clipDef("c", d))
		var body := boxShadow(defs, "s2", 0, 0, 200, 52, 13, 0, 0, 0, 2, "#2A170E")
		body += boxShadow(defs, "s1", 0, 0, 200, 52, 13, 0, 5, 12, 0, "rgba(0,0,0,.45)")
		body += '<path d="%s" fill="url(#g)"/>' % d
		body += insetShadow(defs, "i1", "c", 0, 0, 200, 52, 13, 0, 2, 0, 0, "rgba(255,220,170,.18)")
		body += insetShadow(defs, "i2", "c", 0, 0, 200, 52, 13, 0, -3, 0, 0, "rgba(0,0,0,.35)")
		for cx in [9.0, 191.0]:
			defs.append(clipDef("d%d" % int(cx), rrd(cx - 3, 23, 6, 6, 3)))
			body += '<circle cx="%s" cy="26" r="3" fill="#C8963C"/>' % n_(cx)
			body += insetShadow(defs, "di%d" % int(cx), "d%d" % int(cx), cx - 3, 23, 6, 6, 3, 0, -1, 0, 0, "rgba(0,0,0,.4)")
		return svgTexture(svgDoc(-20, -20, 240, 100, body, "".join(defs))))
	if t:
		ci.draw_texture_rect(t, Rect2(-20, -20, 240, 100), false)

func _drawPops(ci: Control) -> void:
	var f: Font = _fonts.hud
	var now: float = game.time.realNow
	for p in _pops:
		var t := clampf((now - p.born) / 0.6, 0.0, 1.0)
		# @keyframes dhpop (cubic-bezier(.2,.9,.3,1) per segment, fill forwards)
		var ty := 0.0
		var s := 1.0
		var o := 1.0
		var E := func(x: float) -> float: return cubicBezier(0.2, 0.9, 0.3, 1.0, x)
		# CSS eases each property between ITS OWN keyframes: transform 0% -> 18% -> 100% (65% sets only opacity),
		# opacity 0% -> 18% -> 65% -> 100%
		if t < 0.18:
			var q: float = E.call(t / 0.18)
			ty = lerpf(8.0, -6.0, q); s = lerpf(0.6, 1.12, q); o = lerpf(0.0, 1.0, q)
		else:
			var q2: float = E.call((t - 0.18) / 0.82)
			ty = lerpf(-6.0, -58.0, q2); s = lerpf(1.12, 0.95, q2)
			o = 1.0 if t < 0.65 else lerpf(1.0, 0.0, E.call((t - 0.65) / 0.35))
		var txt: String = p.text
		var tw := textWidth(f, txt, 30.0)
		var lh := f.get_ascent(30) + f.get_descent(30)
		var cx: float = -p.right - tw / 2.0
		var cy := -lh / 2.0
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(cx, cy + ty)) * Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO))
		var col := DAU.color("#FFF1A0" if p.gold else "#FFD23A")
		col.a = o
		var dk := "#6A3A12"
		drawText(ci, f, -tw / 2.0, baselineAt(f, 30.0, 0.0), txt, 30.0, col, 0.0,
			[[0.0, 2.0, 0.0, dk], [0.0, -1.0, 0.0, dk], [2.0, 0.0, 0.0, dk], [-2.0, 0.0, 0.0, dk], [0.0, 4.0, 6.0, "rgba(0,0,0,.4)"]])
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- ammo
func _drawAmmoBg(ci: Control) -> void:
	var t := _tx("ammo", func():
		var defs: Array = []
		var d := rrd(0, 0, 215, 64, 12)
		defs.append(linGrad("g", 0, 0, 215, 64, 180, [["#E8ECF2", 0.0], ["#A8B0BC", 0.45], ["#8A929E", 0.55], ["#C8D0DA", 1.0]]))
		defs.append(clipDef("c", d))
		var body := boxShadow(defs, "s1", 0, 0, 215, 64, 12, 0, 5, 12, 0, "rgba(0,0,0,.45)")
		body += '<path d="%s" fill="url(#g)"/>' % d
		body += insetShadow(defs, "i1", "c", 0, 0, 215, 64, 12, 0, 1, 0, 0, "#fff")
		body += insetShadow(defs, "i2", "c", 0, 0, 215, 64, 12, 0, -2, 0, 0, "rgba(0,0,0,.25)")
		# windows (.win: #0A0A0E r6, inset 0 2px 5px rgba(0,0,0,.9), 0 1px 0 rgba(255,255,255,.6))
		for wn in [[10.0, 8.0, 104.0, 48.0, "w1"], [134.0, 15.0, 71.0, 34.0, "w2"]]:
			var wd := rrd(wn[0], wn[1], wn[2], wn[3], 6)
			defs.append(clipDef(wn[4], wd))
			body += boxShadow(defs, wn[4] + "o", wn[0], wn[1], wn[2], wn[3], 6, 0, 1, 0, 0, "rgba(255,255,255,.6)")
			body += '<path d="%s" fill="#0A0A0E"/>' % wd
			body += insetShadow(defs, wn[4] + "i", wn[4], wn[0], wn[1], wn[2], wn[3], 6, 0, 2, 5, 0, "rgba(0,0,0,.9)")
		# .sep 4x40, r2, linear-gradient(90deg, #6A727E, #F0F4F8, #6A727E)
		defs.append(linGrad("sg", 122, 12, 4, 40, 90, [["#6A727E", 0.0], ["#F0F4F8", 0.5], ["#6A727E", 1.0]]))
		body += '<path d="%s" fill="url(#sg)"/>' % rrd(122, 12, 4, 40, 2)
		return svgTexture(svgDoc(-20, -20, 255, 104, body, "".join(defs))))
	if t:
		ci.draw_texture_rect(t, Rect2(-20, -20, 255, 104), false)

# ---- equipment
func _drawEquipment(ci: Control) -> void:
	# tubes row: right-aligned at the anchor, bottom at 0; teles row above (gap 6) once a Tiny Tele was held
	var n := tubes.size()
	var rowW := n * 20.0 + (n - 1) * 5.0
	for i in n:
		var on: bool = tubes[i]
		var t := _tx("tube%s" % on, func(): return svgTexture(iconSvg(TUBE_SVG(on), 22, 40, 20, 36, [[0.0, 2.0, 2.0, "rgba(0,0,0,.5)"]], blurFilter("fg", 3.0))))
		if t:
			ci.draw_texture_rect(t, Rect2(-rowW + i * 25.0 - 8, -36.0 - 8, 36, 52), false)
	if _hadTele:
		var m := teles.size()
		var rw := m * 28.0 + (m - 1) * 5.0
		for j in m:
			var on2: bool = teles[j]
			var t2 := _tx("tele%s" % on2, func(): return svgTexture(iconSvg(TELE_SVG(on2), 30, 28, 28, 26, [[0.0, 2.0, 2.0, "rgba(0,0,0,.5)"]])))
			if t2:
				ci.draw_texture_rect(t2, Rect2(-rw + j * 33.0 - 8, -36.0 - 6.0 - 26.0 - 8, 44, 42), false)

# ---- round dial
func _knobSvg() -> String:
	var defs: Array = []
	var body := ""
	# box-shadow 0 5px 12px rgba(0,0,0,.5) (rotates with the knob)
	body += boxShadow(defs, "s", 0, 0, 84, 84, 42, 0, 5, 12, 0, "rgba(0,0,0,.5)")
	defs.append(clipDef("c", rrd(0, 0, 84, 84, 42)))
	# repeating-conic-gradient(from 0deg, #C42A2A 0deg 7deg, #8A1616 7deg 13.85deg)
	var g := '<g clip-path="url(#c)">'
	var a0 := 0.0
	var k := 0
	while a0 < 360.0:
		var a1 := minf(360.0, a0 + (7.0 if k % 2 == 0 else 6.85))
		var r := 80.0
		var p0 := Vector2(42, 42) + Vector2(sin(deg_to_rad(a0)), -cos(deg_to_rad(a0))) * r
		var p1 := Vector2(42, 42) + Vector2(sin(deg_to_rad(a1)), -cos(deg_to_rad(a1))) * r
		g += '<path d="M42 42L%s %sA80 80 0 0 1 %s %sZ" fill="%s"/>' % [n_(p0.x), n_(p0.y), n_(p1.x), n_(p1.y), "#C42A2A" if k % 2 == 0 else "#8A1616"]
		a0 = a1
		k += 1
	# radial-gradient(circle at 50% 50%, transparent 57%, #9A1E1E 58%, #E23B3B 61%, #FF6A5A 66%, #E23B3B 72%, #8A1A1A 74%, transparent 75%)
	var R := farCorner(0, 0, 84, 84, 42, 42)
	defs.append(radGrad("rg", 42, 42, R, [["transparent", 0.57], ["#9A1E1E", 0.58], ["#E23B3B", 0.61], ["#FF6A5A", 0.66], ["#E23B3B", 0.72], ["#8A1A1A", 0.74], ["transparent", 0.75]]))
	g += '<rect width="84" height="84" fill="url(#rg)"/></g>'
	body += g
	body += insetShadow(defs, "i", "c", 0, 0, 84, 84, 42, 0, 2, 0, 0, "rgba(255,200,190,.35)")
	# ::after pointer: 6x11 at top 3, r3, #F4F1E8, 0 1px 0 rgba(0,0,0,.4)
	body += '<path d="%s" fill="#000" fill-opacity=".4"/>' % rrd(39, 4, 6, 11, 3)
	body += '<path d="%s" fill="#F4F1E8"/>' % rrd(39, 3, 6, 11, 3)
	return svgDoc(-20, -20, 124, 124, body, "".join(defs))

func _discSvg() -> String:
	var defs: Array = []
	var d := rrd(14, 14, 56, 56, 28)
	defs.append(clipDef("c", d))
	defs.append(radGrad("g", 14 + 0.36 * 56, 14 + 0.3 * 56, farCorner(14, 14, 56, 56, 14 + 0.36 * 56, 14 + 0.3 * 56), [["#6A92FA", 0.0], ["#2F5BD3", 0.55], ["#1C3690", 1.0]]))
	var body := boxShadow(defs, "o", 14, 14, 56, 56, 28, 0, 0, 0, 2, "#F4F1E8")
	body += '<path d="%s" fill="url(#g)"/>' % d
	body += insetShadow(defs, "i1", "c", 14, 14, 56, 56, 28, 0, -3, 0, 0, "rgba(0,0,0,.3)")
	body += insetShadow(defs, "i2", "c", 14, 14, 56, 56, 28, 0, 2, 0, 0, "rgba(255,255,255,.3)")
	return svgDoc(0, 0, 84, 84, body, "".join(defs))

func _drawDial(ci: Control) -> void:
	var knob := _tx("knob", func(): return svgTexture(_knobSvg()))
	if knob:
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(42, 42)) * Transform2D(deg_to_rad(_dialNum.rot), Vector2.ZERO))
		ci.draw_texture_rect(knob, Rect2(-62, -62, 124, 124), false)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var disc := _tx("disc", func(): return svgTexture(_discSvg()))
	if disc:
		ci.draw_texture_rect(disc, Rect2(0, 0, 84, 84), false)
	var txt: String = _dialNum.text
	if txt != "":
		var f: Font = _fonts.hud
		var size := 28.0 if _dialNum.small else 36.0
		var tw := textWidth(f, txt, size)
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(42, 42)) * Transform2D(0.0, Vector2(_dialNum.sx, _dialNum.sy), 0.0, Vector2.ZERO))
		drawText(ci, f, -tw / 2.0, baselineAt(f, size, 0.0), txt, size, Color(1, 1, 1, _dialNum.opacity), 0.0,
			[[0.0, 2.0, 0.0, "#14246A"], [0.0, 0.0, 1.0, "#14246A"]])
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- chyron
func _drawChyBar(ci: Control) -> void:
	var t := _tx("chybar", func():
		var defs: Array = []
		var r := [0.0, 28.0, 28.0, 0.0]
		var d := rrd(54, 10, 566, 56, r)
		defs.append(linGrad("g", 54, 10, 566, 56, 180, [["#F59A48", 0.0], ["#D9602B", 0.5], ["#A8401E", 1.0]]))
		defs.append(clipDef("c", d))
		var body := boxShadow(defs, "s", 54, 10, 566, 56, r, 0, 4, 10, 0, "rgba(30,10,6,.45)")
		body += '<path d="%s" fill="url(#g)"/>' % d
		body += insetShadow(defs, "i", "c", 54, 10, 566, 56, r, 0, 3, 0, 0, "rgba(255,255,255,.28)")
		# ::after: left 30 right 34 bottom 8 height 3 #E8A92E, box-shadow 0 5px 0 -1px #D9A520
		body += '<rect x="%s" y="%s" width="%s" height="1" fill="#D9A520"/>' % [n_(54 + 31), n_(10 + 45 + 6), n_(566 - 64 - 2)]
		body += '<rect x="%s" y="%s" width="%s" height="3" fill="#E8A92E"/>' % [n_(54 + 30), n_(10 + 45), n_(566 - 64)]
		return svgTexture(svgDoc(30, -10, 610, 110, body, "".join(defs))))
	if t:
		ci.draw_texture_rect(t, Rect2(30, -10, 610, 110), false)

func _drawChyTop(ci: Control) -> void:
	var C := _chy
	# sub label
	if C.sub != "":
		var fs: Font = _fonts.sign
		var ls := 15.0 * 0.06
		var sw := ceilf(16.0 + textWidth(fs, C.sub, 15.0, ls) + 22.0)
		var st := _tx("chysub%d" % int(sw), func():
			var defs: Array = [linGrad("g", 84, 62, sw, 26, 180, [["#6A3A22", 0.0], ["#4A2616", 1.0]])]
			return svgTexture(svgDoc(84, 62, sw, 26, '<path d="%s" fill="url(#g)"/>' % rrd(84, 62, sw, 26, [0, 0, 14, 14]), "".join(defs))))
		if st:
			ci.draw_texture_rect(st, Rect2(84, 62, sw, 26), false)
		drawText(ci, fs, 84 + 16, baselineAt(fs, 15.0, 62 + 13), C.sub, 15.0, DAU.color("#FFD27A"), ls)
	# badge
	var b := _tx("chybadge", func():
		var defs: Array = []
		var body := boxShadow(defs, "s", 0, 0, 80, 80, 40, 0, 4, 10, 0, "rgba(0,0,0,.5)")
		body += boxShadow(defs, "o", 0, 0, 80, 80, 40, 0, 0, 0, 4, "#E8A92E")
		defs.append(radGrad("g", 32, 28, farCorner(0, 0, 80, 80, 32, 28), [["#8A5A36", 0.0], ["#5A3A22", 1.0]]))
		body += '<circle cx="40" cy="40" r="40" fill="url(#g)"/>'
		defs.append(clipDef("ci", rrd(12, 12, 56, 56, 28)))
		body += '<circle cx="40" cy="40" r="28" fill="#F4F1E8"/>'
		body += insetShadow(defs, "ii", "ci", 12, 12, 56, 56, 28, 0, 0, 0, 5, "#E23B3B")
		return svgTexture(svgDoc(-20, -20, 120, 120, body, "".join(defs))))
	if b:
		ci.draw_texture_rect(b, Rect2(-20, -20, 120, 120), false)
	var f: Font = _fonts.hud
	var tw := textWidth(f, "13", 26.0)
	drawText(ci, f, 40 - tw / 2.0, baselineAt(f, 26.0, 40), "13", 26.0, DAU.color("#2F5BD3"), 0.0, [[0.0, 1.0, 0.0, "#14246A"]])
	# name
	var fl: Font = _fonts.logo
	var dk := "#5A2210"
	drawText(ci, fl, 100, baselineAt(fl, 38.0, 14 + 25), C.name, 38.0, DAU.color("#FFFBEA"), 0.0,
		[[0.0, 3.0, 0.0, dk], [2.0, 0.0, 0.0, dk], [-2.0, 0.0, 0.0, dk], [0.0, -2.0, 0.0, dk], [2.0, 2.0, 0.0, dk], [-2.0, 2.0, 0.0, dk]])

# ---- power-ups
func _drawPowerups(ci: Control) -> void:
	var items: Array = _pu.values()
	var n := items.size()
	if n == 0:
		return
	var total := n * 58.0 + (n - 1) * 14.0
	var x0 := -total / 2.0
	var f: Font = _fonts.hud
	for i in n:
		var it: Dictionary = items[i]
		var k: float = it.k
		var s := cubicBezier(0.3, 1.6, 0.5, 1.0, k) if it.dir > 0 else cubicBezier(0.3, 1.6, 0.5, 1.0, k)
		var o := cssEase(k)
		var cx := x0 + i * 72.0 + 29.0
		var cy := -29.0
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(cx, cy)) * Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO))
		var type: String = it.type
		var glowS: String = PU_GLOW.get(type, "#FFC23A")
		var glow := DAU.color(glowS)
		# ring svg (rotated -90deg): disc + faint track, the draining arc with drop-shadow(0 0 3px glow)
		var disc := _tx("pudisc", func(): return svgTexture(svgDoc(0, 0, 58, 58, '<circle cx="29" cy="29" r="26" %s stroke="#FFFFFF" stroke-opacity=".14" stroke-width="4"/>' % fillAttr("rgba(20,12,28,.72)"))))
		if disc:
			ci.draw_texture_rect(disc, Rect2(-29, -29, 58, 58), false, Color(1, 1, 1, o))
		var frac: float = 1.0 - float(it.off) / PU_C
		if frac > 0.0:
			var a0 := -PI / 2.0
			var a1 := a0 + TAU * frac
			var segs := maxi(4, int(64 * frac))
			ci.draw_arc(Vector2.ZERO, PU_R, a0, a1, segs, Color(glow, 0.35 * o), 8.0, true)
			ci.draw_arc(Vector2.ZERO, PU_R, a0, a1, segs, Color(glow, o), 4.5, true)
			for pa in [a0, a1]:
				ci.draw_circle(Vector2(cos(pa), sin(pa)) * PU_R, 2.25, Color(glow, o))
		var bl := 1.0
		if it.blink:
			bl = stepsBlink(_time, 0.25, 0.25)
		var inner: String = PU_ICON.get(type, '<circle cx="24" cy="24" r="12" fill="%s"/>' % glowS)
		var ic := _tx("pu_" + type, func(): return svgTexture(iconSvg(inner, 48, 48, 48, 48, [[0.0, 2.0, 2.0, "rgba(0,0,0,.55)"]])))
		if ic:
			ci.draw_texture_rect(ic, Rect2(-24 - 8, -24 - 8, 64, 64), false, Color(1, 1, 1, o * bl))
		if PU_ICON_TEXT.has(type):
			var tt: Array = PU_ICON_TEXT[type]
			var tw := textWidth(f, tt[0], tt[3])
			drawText(ci, f, -24 + tt[1] - tw / 2.0, -24 + tt[2], tt[0], tt[3], Color(DAU.color(tt[4]), o * bl))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- replay bug
func _drawReplayBug(ci: Control) -> void:
	if not _replay:
		return
	var a := stepsBlink(_time, 0.5, 0.25)
	var rb := _tx("rbsvg", func(): return svgTexture(iconSvg(RB_PATH % 'fill="#FFE14D" stroke="#5A3A10"', 64, 36, 72, 40, [[0.0, 3.0, 0.0, "rgba(60,30,0,.45)"]])))
	if rb:
		ci.draw_texture_rect(rb, Rect2(-8, 2 - 8, 88, 56), false, Color(1, 1, 1, a))
	var bd := _tx("rbbadge", func():
		var defs: Array = []
		defs.append(clipDef("c", rrd(0, 0, 44, 44, 22)))
		var body := boxShadow(defs, "o", 0, 0, 44, 44, 22, 0, 3, 0, 0, "rgba(0,0,0,.35)")
		body += '<circle cx="22" cy="22" r="22" fill="#F4F1E8"/>'
		body += insetShadow(defs, "i", "c", 0, 0, 44, 44, 22, 0, 0, 0, 5, "#E23B3B")
		return svgTexture(svgDoc(-4, -4, 52, 52, body, "".join(defs))))
	if bd:
		ci.draw_texture_rect(bd, Rect2(122 - 40 - 4, -4, 52, 52), false, Color(1, 1, 1, a))
	var f: Font = _fonts.hud
	var tw := textWidth(f, "13", 21.0)
	drawText(ci, f, 82 + 22 - tw / 2.0, baselineAt(f, 21.0, 22), "13", 21.0, Color(DAU.color("#2F5BD3"), a))

# ---- flash
func _drawFlash(ci: Control) -> void:
	if _flash.opacity <= 0.0 or _flash.text == "":
		return
	var f: Font = _fonts.logo
	var tw := textWidth(f, _flash.text, 104.0)
	ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(_flash.s, _flash.s), 0.0, Vector2.ZERO))
	var col := DAU.color("#FFE14D")
	col.a = _flash.opacity
	drawText(ci, f, -tw / 2.0, baselineAt(f, 104.0, 0.0), _flash.text, 104.0, col, 0.0,
		[[0.0, 6.0, 0.0, "#B5472A"], [0.0, 12.0, 18.0, "rgba(0,0,0,.5)"]])
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# JS truthiness for prompt fields (interact passes hold: null when an item has no hold; bool(null) is invalid in GDScript).
static func _tb(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0 and not is_nan(float(v))
	if v is String or v is StringName:
		return v != ""
	return true
