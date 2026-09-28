# DEAD AIR — gfx/cards.gd (port of src/gfx/cards.js)
# Every piece of 2D broadcast artwork the station shows: TV sources (bars, test card, station ID, bumpers,
# Hootie, the Baron, the sign-off film), Telly's dot-matrix face and its nine channel cards, wall-buy and
# sponsor posters, logo cards, neon signs, props with printed graphics (weather map, rundown cards, tote
# digits, badges, tickets...), the title logo and the Chroma-Key stock-footage worlds.
# Pure Canvas 2D (scripts/gfx/canvas2d.gd, DACanvas: the JS canvas API with the JS names), no image files.
#
# API (static; `DACards.cards` is the namespace object installed as game.cards)
#   getCard(id, opts?)      -> Texture2D. Static card, drawn lazily, cached per id + opts, sRGB, mipmapped
#                              (baked once rendered). Animated ids render one frame here (opts.time, seconds).
#   getAnimated(id, opts?)  -> Handle { texture, canvas, opts, tick(time), set_(patch), redraw() }. Cached per
#                              id + opts, so every screen showing a source shares one texture. tick(time)
#                              (seconds) redraws only when the card's own frame index changes (its fps) or after
#                              set_(); returns true if it redrew. set_(patch) merges into this handle's opts
#                              (Telly's expression / gaze...). Handles are shared: add any extra key (e.g.
#                              { owner:'telly' }) for a private one. Timeline cards (signoff_film) expect time since
#                              the source started (loops at 20 s).
#   drawTo(ctx, id, w, h, time = 0, opts?)  draws the card into any DACanvas 2D context at 0,0 scaled to w x h.
#   cardIds()               -> every registered id.
#   cardInfo(id)            -> { w, h, fps, alpha, opts } native size, frame rate (0 = static), transparency and a
#                              short description of the options the id understands.
#   invalidateAll()         -> redraws every cached canvas.
#   cards                   -> the same API as one namespace ({ get_, animated, drawTo, ids, info, invalidateAll })
#                              for engine code that holds a single provider (game.cards is this object;
#                              DACards.install(game) sets it).
#
# Atlases: DAU.ud(getCard('tote_digits')).atlas = { chars, cols, rows, cellW, cellH, uv: Callable(ch) ->
#          [u0,v0,u1,v1] } (v measured from the bottom, as THREE UVs with flipY).
# Fonts:   Shrikhand, Titan One, VT323 and Bungee (res://assets/fonts), with fallbacks (canvas_text.gd).
# Sizes:   TV sources are 4:3 (512x384); posters 384x512; everything is <= 512 px per side.
#
# Renames (SPEC §3.2): module functions `hash` -> hash_, `wrap` -> wrap_ (GDScript globals); the handle's
# `set` -> set_; namespace `get` -> get_; JS helpers clamp/lerp -> clampf/lerpf (same semantics). JS
# `set.has`/`Map` -> Dictionary. Engine plumbing not ported: document.fonts reload hooks (fonts load synchronously).
#
# Catalogue (cardIds() is authoritative; cardInfo(id).opts documents each id's options)
#   TV sources   color_bars test_card stand_by station_id* right_back* hullabaloo* baron* signoff_film* snow*
#                satellite_super telly_face* show_<2|4|5|7|8|9|11|12|13> promo_<heroId>      (* = animated)
#   Posters      poster_<pump_37|mp7|m16a1> {winked} poster_<spooktacular|hootie|precinct13|boogie_down>
#                sponsor_poster_<perkId> sponsor_logo_<perkId> sponsor_sign_<perkId> {lit}
#   Newsroom/MC  weather_map magnet_<sun|cloud|rain|bolt|storm> rundown_header rundown_card_<1..6> {star}
#   Lobby/props  letter_board {signOff} tote_digits dust_rect scenery_board_<1..6> chyron {text, sub}
#                hero_portrait_<heroId> portrait_baron portrait_stormy_stu magazine_tv_weekly perpetua_ad
#                ticket_stub badge_crew cap_13 dressing_room_doors {who} baron_dressing_room
#                sign_see_yourself applause_sign {lit} on_air {lit} clock_face {hands, time} reel_label
#   Overlays     flinch crack_overlay logo_dead_air world_<space|beach|volcano|underwater|desert|moon>
class_name DACards
extends RefCounted

# ---------------------------------------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------------------------------------

const DEG := PI / 180.0

## GDD §3.2 palette (subset used by the 2D art).
const C := {
	"blue": "#2F5BD3", "red": "#E23B3B", "white": "#F4F1E8", "cream": "#F6E7C8",
	"gold": "#E8A92E", "orange": "#E3662B", "avocado": "#8C9A3A", "mustard": "#D9A520", "choc": "#5A3A22",
	"walnut": "#7A4A2A", "teak": "#B07A45", "rust": "#B5472A", "teal": "#2E8C8C", "plum": "#6B3A6E", "shag": "#D9602B",
	"onAir": "#FF3B30", "crt": "#7FE7FF", "tungsten": "#FFC98A", "pink": "#FF5FA2", "marquee": "#FFC23A",
	"magenta": "#FF4FA0", "amber": "#FFB347", "cyan": "#5FE3FF",
	"shadow": "#3A2A5A", "ink": "#2A1D3A", "deep": "#1E1530",
	"nightTop": "#1B1E4A", "nightHz": "#2A2F6B", "moon": "#FFF4D6", "moonlight": "#9FB6FF",
	"dawn": ["#FF7E5F", "#FFB36B", "#FFE3A3"],
	"chroma": "#1E5BFF", "lime": "#39E75F", "perpetua": "#9CFF57",
	"osd": "#5CFF6E", "brass": "#E8B84A",
}
## Cartoonized SMPTE bars, left to right (GDD §3.2).
const BARS := ["#EDEDED", "#F4E03A", "#3FD6E0", "#52D24A", "#D64FD6", "#E4473A", "#3A58E4"]
## Neon logo letters (GDD §3.2).
const NEON := {"W": "#FF3B30", "Z": "#FFD23A", "T": "#52E04A", "V": "#3A7BFF"}

const FONT := {
	"groovy": "Shrikhand, \"Cooper Black\", \"Bookman Old Style\", Georgia, serif",
	"round": "\"Titan One\", \"Arial Rounded MT Bold\", \"Arial Black\", sans-serif",
	"osd": "VT323, \"Lucida Console\", \"Courier New\", monospace",
	"sign": "Bungee, Impact, \"Arial Black\", sans-serif",
	"type": "\"Courier New\", Courier, monospace",
}

const HERO_IDS := ["skip", "roxy", "penny", "duke"]
const PERK_IDS := ["replay_ade", "wobble_up", "jump_cut", "roller_boogie", "double_vision"]

# ---------------------------------------------------------------------------------------------------------
# Math, random, colour
# ---------------------------------------------------------------------------------------------------------

static func fract(x: float) -> float:
	return x - floorf(x)

## JS Math.round (halves toward +infinity).
static func jround(x: float) -> float:
	return floorf(x + 0.5)

## JS `a || b` / `a ?? b` on option values.
static func _or(a, b):
	return a if a else b

static func _nn(a, b):
	return a if a != null else b

## mulberry32: deterministic art randomness (cards must look identical on every redraw). Returns a Callable.
static func rng(seed: int) -> Callable:
	return Rng.mulberry32(seed)

static func hash_(s: String) -> int:
	return Rng.hashStr(s)

static func rgb(hex: String) -> Array:
	var n := ("0x" + hex.substr(1)).hex_to_int()
	return [(n >> 16) & 255, (n >> 8) & 255, n & 255]

static var _mixCache := {}
static func mix(a: String, b: String, t: float) -> String:
	var key := "%s|%s|%s" % [a, b, t]
	var hit = _mixCache.get(key)
	if hit != null:
		return hit
	var x := rgb(a)
	var y := rgb(b)
	var s := "#"
	for i in 3:
		s += "%02x" % int(jround(lerpf(x[i], y[i], t)))
	if _mixCache.size() > 4096:
		_mixCache.clear()
	_mixCache[key] = s
	return s

static func lighten(c: String, t: float) -> String:
	return mix(c, "#ffffff", t)

## Darkens toward the tinted purple shadow: never pure black (GDD §3.2).
static func darken(c: String, t: float) -> String:
	return mix(c, "#1c1228", t)

static func alpha(c: String, a: float) -> String:
	var v := rgb(c)
	return "rgba(%d,%d,%d,%s)" % [v[0], v[1], v[2], _num(a)]

## JS number -> string (template literal formatting for the few numbers that end up in CSS strings).
static func _num(v: float) -> String:
	if v == floorf(v) and absf(v) < 1e15:
		return str(int(v))
	return str(v)

# ---------------------------------------------------------------------------------------------------------
# Canvas primitives
# ---------------------------------------------------------------------------------------------------------

static func makeCanvas(w: int, h: int) -> DACanvas:
	return DACanvas.new(w, h)

static func linear(ctx, x0: float, y0: float, x1: float, y1: float, stops: Array):
	var g = ctx.createLinearGradient(x0, y0, x1, y1)
	for i in stops.size():
		var s = stops[i]
		if s is Array:
			g.addColorStop(s[0], s[1])
		else:
			g.addColorStop(float(i) / (stops.size() - 1), s)
	return g

static func radial(ctx, x: float, y: float, r0: float, r1: float, stops: Array, fx = null, fy = null):
	var g = ctx.createRadialGradient(x if fx == null else fx, y if fy == null else fy, r0, x, y, r1)
	for i in stops.size():
		var s = stops[i]
		if s is Array:
			g.addColorStop(s[0], s[1])
		else:
			g.addColorStop(float(i) / (stops.size() - 1), s)
	return g

static func rr(ctx, x: float, y: float, w: float, h: float, r) -> void:
	ctx.beginPath()
	ctx.roundRect(x, y, w, h, r)

static func circle(ctx, x: float, y: float, r: float) -> void:
	ctx.beginPath()
	ctx.arc(x, y, r, 0, TAU)

static func ellipse(ctx, x: float, y: float, rx: float, ry: float, rot: float = 0.0) -> void:
	ctx.beginPath()
	ctx.ellipse(x, y, maxf(rx, 0.01), maxf(ry, 0.01), rot, 0, TAU)

static func poly(ctx, pts: Array, close: bool = true) -> void:
	ctx.beginPath()
	ctx.moveTo(pts[0], pts[1])
	var i := 2
	while i < pts.size():
		ctx.lineTo(pts[i], pts[i + 1])
		i += 2
	if close:
		ctx.closePath()

static func fill(ctx, style) -> void:
	ctx.fillStyle = style
	ctx.fill()

static func stroke(ctx, style, lw: float) -> void:
	ctx.strokeStyle = style
	ctx.lineWidth = lw
	ctx.stroke()

## Fills the current path, then outlines it (cartoon ink line).
static func inked(ctx, style, lw: float, ink = null) -> void:
	if ink == null:
		ink = C.ink
	ctx.fillStyle = style
	ctx.fill()
	if lw > 0:
		ctx.strokeStyle = ink
		ctx.lineWidth = lw
		ctx.stroke()

static func starPath(ctx, x: float, y: float, ro: float, ri: float, n: int = 5, rot: float = -PI / 2) -> void:
	ctx.beginPath()
	for i in n * 2:
		var r := ri if (i & 1) else ro
		var a := rot + (i * PI) / n
		ctx.lineTo(x + cos(a) * r, y + sin(a) * r)
	ctx.closePath()

## Alternating sunburst wedges over the whole canvas.
static func rays(ctx, cx: float, cy: float, R: float, n: int, color, rot: float = 0.0, duty: float = 0.5) -> void:
	ctx.beginPath()
	for i in n:
		var a0 := rot + (i * TAU) / n
		var a1 := a0 + (TAU / n) * duty
		ctx.moveTo(cx, cy)
		ctx.arc(cx, cy, R, a0, a1)
		ctx.closePath()
	ctx.fillStyle = color
	ctx.fill()

## Puffy cartoon cloud made of circles; returns nothing, fills with `style`, optional ink.
static func cloudPath(ctx, x: float, y: float, w: float, h: float) -> void:
	var bumps := [[-0.36, 0.12, 0.3], [-0.12, -0.12, 0.38], [0.18, -0.2, 0.34], [0.38, 0.06, 0.28], [0, 0.16, 0.34]]
	ctx.beginPath()
	for b in bumps:
		var r: float = b[2] * w * 0.62
		ctx.moveTo(x + b[0] * w + r, y + b[1] * h)
		ctx.arc(x + b[0] * w, y + b[1] * h, r, 0, TAU)
	ctx.roundRect(x - w * 0.46, y - h * 0.02, w * 0.92, h * 0.42, h * 0.2)

static func cloud(ctx, x: float, y: float, w: float, h: float, style, ink = null, lw: float = 0.0) -> void:
	if ink:
		ctx.save()
		cloudPath(ctx, x, y, w, h)
		ctx.strokeStyle = ink
		ctx.lineWidth = lw * 2
		ctx.lineJoin = "round"
		ctx.stroke()
		ctx.restore()
	cloudPath(ctx, x, y, w, h)
	ctx.fillStyle = style
	ctx.fill()

## Thick round-capped segment: outline pass then fill pass gives one inked silhouette.
static func capsule(ctx, x0: float, y0: float, x1: float, y1: float, w: float, style, ink = null, lw: float = 0.0) -> void:
	ctx.lineCap = "round"
	ctx.beginPath()
	ctx.moveTo(x0, y0)
	ctx.lineTo(x1, y1)
	if ink:
		ctx.strokeStyle = ink
		ctx.lineWidth = w + lw * 2
		ctx.stroke()
	ctx.strokeStyle = style
	ctx.lineWidth = w
	ctx.stroke()

# ---------------------------------------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------------------------------------

static func setFont(ctx, px: float, fam: String) -> void:
	ctx.font = "%dpx %s" % [int(maxf(1.0, jround(px))), fam]

## Picks the largest size <= px so `str` fits in maxW.
static func fitFont(ctx, s: String, fam: String, px: float, maxW: float) -> float:
	setFont(ctx, px, fam)
	var m: float = ctx.measureText(s).width
	if m > maxW:
		px = maxf(6.0, floorf((px * maxW) / m))
		setFont(ctx, px, fam)
	return px

## Poster lettering. o: { fam, px, maxW, fill (style or fn(ctx, px)), stroke, lw, depth, depthFill, dx, dy,
## align, base, rot, skew, track, shadow, shadowBlur, glow }
## depth draws a stacked 70s extrusion toward (dx, dy); stroke/lw outline every layer.
static func label(ctx, s: String, x: float, y: float, o: Dictionary = {}) -> float:
	var fam: String = _or(o.get("fam"), FONT.sign)
	ctx.save()
	if o.get("track"):
		ctx.letterSpacing = "%spx" % _num(o.track)
	var px: float
	if o.get("maxW"):
		px = fitFont(ctx, s, fam, _or(o.get("px"), 32), o.maxW)
	else:
		setFont(ctx, _or(o.get("px"), 32), fam)
		px = _or(o.get("px"), 32)
	ctx.textAlign = _or(o.get("align"), "center")
	ctx.textBaseline = _or(o.get("base"), "middle")
	ctx.lineJoin = "round"
	ctx.miterLimit = 2
	ctx.translate(x, y)
	if o.get("rot"):
		ctx.rotate(o.rot)
	if o.get("skew"):
		ctx.transform(1, 0, o.skew, 1, 0, 0)
	var lw: float = _nn(o.get("lw"), px * 0.1)
	var depth: int = int(_or(o.get("depth"), 0))
	var dx: float = _nn(o.get("dx"), 0.7)
	var dy: float = _nn(o.get("dy"), 1)
	if o.get("shadow"):
		ctx.save()
		ctx.shadowColor = o.shadow
		ctx.shadowBlur = _nn(o.get("shadowBlur"), px * 0.25)
		ctx.shadowOffsetY = _nn(o.get("shadowY"), px * 0.06)
		ctx.fillStyle = o.shadow
		ctx.fillText(s, (depth + 1) * dx, (depth + 1) * dy)
		ctx.restore()
	var i := depth
	while i > 0:
		ctx.fillStyle = _or(o.get("depthFill"), C.ink)
		if o.get("stroke"):
			ctx.strokeStyle = _or(o.get("depthStroke"), o.stroke)
			ctx.lineWidth = lw
			ctx.strokeText(s, i * dx, i * dy)
		ctx.fillText(s, i * dx, i * dy)
		i -= 1
	if o.get("stroke"):
		ctx.strokeStyle = o.stroke
		ctx.lineWidth = lw
		ctx.strokeText(s, 0, 0)
	if o.get("glow"):
		ctx.shadowColor = o.glow
		ctx.shadowBlur = _nn(o.get("glowBlur"), px * 0.4)
	var f = o.get("fill")
	ctx.fillStyle = f.call(ctx, px) if f is Callable else _or(f, "#fff")
	ctx.fillText(s, 0, 0)
	ctx.restore()
	return px

## Vertical gradient generator for label fills (spans the glyph box of a centred label).
static func vgrad(stops: Array) -> Callable:
	return func(ctx, px): return linear(ctx, 0, -px * 0.5, 0, px * 0.45, stops)
const CHROME := ["#FFFFFF", "#DDE6F4", "#9AA8C8", "#4E5C82", [0.52, "#F4F7FF"], "#B6C2DC", "#FFFFFF"]
const GOLDEN := ["#FFF6C8", "#FFD45A", "#E8A92E", [0.55, "#FFE38A"], "#C97E1E"]

# ---------------------------------------------------------------------------------------------------------
# Surface effects (cached tiles; cheap enough for animated cards)
# ---------------------------------------------------------------------------------------------------------

static var noiseTile: DACanvas = null
static func getNoiseTile() -> DACanvas:
	if noiseTile == null:
		noiseTile = makeCanvas(256, 256)
		noiseTile.bakeMode = "now"
		var g = noiseTile.getContext("2d")
		var img: Dictionary = g.createImageData(256, 256)
		var d: PackedByteArray = img.data
		var r := Rng.Mulberry32.new(1977)
		var i := 0
		var n := d.size()
		while i < n:
			var v := (r.next() * 0.6 + r.next() * 0.4) * 255.0
			var b := clampi(int(jround(v)), 0, 255)   # Uint8ClampedArray store rounds
			d[i] = b
			d[i + 1] = b
			d[i + 2] = b
			d[i + 3] = 255
			i += 4
		img.data = d
		g.putImageData(img, 0, 0)
	return noiseTile

## Film/paper grain (overlay blend). Only for opaque cards.
static func grain(ctx, w: float, h: float, amt: float = 0.08, seed: int = 0) -> void:
	ctx.save()
	ctx.globalAlpha = amt
	ctx.globalCompositeOperation = "overlay"
	var ox := (seed * 97) % 256
	var oy := (seed * 61) % 256
	ctx.translate(-ox, -oy)
	ctx.fillStyle = ctx.createPattern(getNoiseTile(), "repeat")
	ctx.fillRect(ox, oy, w, h)
	ctx.restore()

static func vignette(ctx, w: float, h: float, a: float = 0.45, col: String = "28,16,46", inner: float = 0.45) -> void:
	ctx.fillStyle = radial(ctx, w / 2, h / 2, minf(w, h) * inner, Vector2(w, h).length() * 0.55,
		["rgba(%s,0)" % col, "rgba(%s,%s)" % [col, _num(a)]])
	ctx.fillRect(0, 0, w, h)

## Halftone dot field; fn(u, v) -> 0..1 dot size over the rect.
static func halftone(ctx, x: float, y: float, w: float, h: float, color, cell: float, fn: Callable) -> void:
	ctx.fillStyle = color
	ctx.beginPath()
	var j := 0
	while j <= h / cell + 1:
		var i := 0
		while i <= w / cell + 1:
			var px := x + i * cell + (cell / 2 if (j & 1) else 0.0)
			var py := y + j * cell
			var r: float = fn.call((px - x) / w, (py - y) / h) * cell * 0.62
			if r > 0.35:
				ctx.moveTo(px + r, py)
				ctx.arc(px, py, r, 0, TAU)
			i += 1
		j += 1
	ctx.fill()

## Printed-paper finish for posters: warm grain, faint edge wear and a vignette.
static func paper(ctx, w: float, h: float, seed: int = 0, amt: float = 0.1) -> void:
	grain(ctx, w, h, amt, seed)
	vignette(ctx, w, h, 0.28, "60,30,20", 0.5)

## Glossy highlight streak across the top of a rounded rect.
static func gloss(ctx, x: float, y: float, w: float, h: float, r, a: float = 0.35) -> void:
	ctx.save()
	rr(ctx, x, y, w, h, r)
	ctx.clip()
	ctx.fillStyle = linear(ctx, 0, y, 0, y + h * 0.5, ["rgba(255,255,255,%s)" % _num(a), "rgba(255,255,255,0)"])
	ctx.fillRect(x, y, w, h * 0.5)
	ctx.restore()

# ---------------------------------------------------------------------------------------------------------
# Registry & public API
# ---------------------------------------------------------------------------------------------------------

class Def:
	extends RefCounted
	var id := ""
	var w := 0
	var h := 0
	var fps := 0.0
	var alpha_ := false
	var opts := ""
	var atlas = null
	var draw: Callable

static var REG := {}
static var staticCache := {}   # key -> { def, canvas, texture, opts }
static var animCache := {}     # key -> handle
static var layerCache := {}    # key -> canvas (static sub-layers of animated cards)
static var warned := {}
static var _registered := false

## Registers a card. spec: { w, h, fps?, alpha?, opts? (doc string), atlas? }. draw(ctx, w, h, t, o).
static func card(id: String, spec: Dictionary, draw: Callable) -> void:
	var d := Def.new()
	d.id = id
	d.w = spec.w
	d.h = spec.h
	d.fps = float(spec.get("fps", 0))
	d.alpha_ = bool(spec.get("alpha", false))
	d.opts = spec.get("opts", "")
	d.atlas = spec.get("atlas")
	d.draw = draw
	REG[id] = d

## Cached sub-layer (drawn once per key; cleared by invalidateAll).
static func layer(key: String, w: int, h: int, paint: Callable) -> DACanvas:
	var c: DACanvas = layerCache.get(key)
	if c == null:
		c = makeCanvas(w, h)
		c.bakeMode = "now"
		paint.call(c.getContext("2d"), float(w), float(h))
		layerCache[key] = c
	return c

static func optKey(o: Dictionary) -> String:
	var ks := o.keys()
	ks.sort()
	var parts := PackedStringArray()
	for k in ks:
		parts.append("%s=%s" % [k, JSON.stringify(o[k])])
	return "&".join(parts)

static func need(id: String) -> Def:
	_ensure()
	var def: Def = REG.get(id)
	if def != null:
		return def
	if not warned.has(id):
		warned[id] = true
		push_warning('[cards] unknown card id "%s", showing snow' % id)
	return REG.get("snow")

static func resetState(ctx) -> void:
	ctx.globalAlpha = 1
	ctx.globalCompositeOperation = "source-over"
	ctx.shadowBlur = 0
	ctx.shadowColor = "rgba(0,0,0,0)"
	ctx.shadowOffsetX = 0
	ctx.shadowOffsetY = 0
	ctx.filter = "none"
	ctx.lineCap = "butt"
	ctx.lineJoin = "miter"
	ctx.setLineDash([])

static func render(def: Def, ctx, t: float, o: Dictionary) -> void:
	ctx.save()
	ctx.setTransform(1, 0, 0, 1, 0, 0)
	resetState(ctx)
	ctx.clearRect(0, 0, def.w, def.h)
	def.draw.call(ctx, float(def.w), float(def.h), t, o)
	ctx.restore()

static func quantize(def: Def, time: float) -> float:
	return floorf(time * def.fps + 1e-6) / def.fps if def.fps else time

## THREE.CanvasTexture wrapper: the DACanvas texture (sRGB content). Static cards bake with mipmaps; animated ones
## keep their live GPU target (JS: generateMipmaps = false).
static func wrap_(canvas: DACanvas, id: String, animated: bool) -> Texture2D:
	canvas.opaque = not REG[id].alpha_ if REG.has(id) else false
	canvas.bakeMode = "never" if animated else "now"
	canvas.mipmaps = not animated
	var tex := canvas.texture
	tex.resource_name = "card:%s" % id
	return tex

## Static card texture (see header).
static func getCard(id: String, opts: Dictionary = {}) -> Texture2D:
	_ensure()
	var key := "%s|%s" % [id, optKey(opts)]
	var hit = staticCache.get(key)
	if hit != null:
		return hit.texture
	var def := need(id)
	var canvas := makeCanvas(def.w, def.h)
	canvas.opaque = not def.alpha_
	render(def, canvas.getContext("2d"), quantize(def, float(_or(opts.get("time"), 0))), opts)
	var texture := wrap_(canvas, def.id, false)
	if def.atlas != null:
		DAU.ud(texture).atlas = def.atlas
	staticCache[key] = {"def": def, "canvas": canvas, "texture": texture, "opts": opts}
	return texture

## Animated card handle (see header). JS `handle.set(patch)` -> set_(patch).
class Handle:
	extends RefCounted
	var texture: Texture2D
	var canvas: DACanvas
	var opts: Dictionary
	var def
	var ctx
	var frame := -1
	var dirty := true
	var last := 0.0
	func tick(time: float) -> bool:
		last = time
		var f := int(floorf(time * def.fps + 1e-6)) if def.fps else 0
		if f == frame and not dirty:
			return false
		frame = f
		dirty = false
		DACards.render(def, ctx, f / def.fps if def.fps else time, opts)
		return true
	func set_(patch: Dictionary) -> void:
		opts.merge(patch, true)
		dirty = true
	func redraw() -> void:
		dirty = true
		tick(last)

static func getAnimated(id: String, opts: Dictionary = {}) -> Handle:
	_ensure()
	var key := "%s|%s" % [id, optKey(opts)]
	var hit = animCache.get(key)
	if hit != null:
		return hit
	var def := need(id)
	var canvas := makeCanvas(def.w, def.h)
	var h := Handle.new()
	h.def = def
	h.canvas = canvas
	h.ctx = canvas.getContext("2d")
	h.texture = wrap_(canvas, def.id, true)
	h.opts = opts.duplicate()
	h.tick(0)
	animCache[key] = h
	return h

## Draws a card into any 2D context at (0,0) scaled to w x h.
static func drawTo(ctx, id: String, w: float, h: float, time: float = 0.0, opts: Dictionary = {}) -> void:
	var def := need(id)
	ctx.save()
	resetState(ctx)
	ctx.scale(w / def.w, h / def.h)
	ctx.beginPath()
	ctx.rect(0, 0, def.w, def.h)
	ctx.clip()
	def.draw.call(ctx, float(def.w), float(def.h), quantize(def, time), opts)
	ctx.restore()

static func cardIds() -> Array:
	_ensure()
	return REG.keys()

static func cardInfo(id: String):
	_ensure()
	var d: Def = REG.get(id)
	return {"w": d.w, "h": d.h, "fps": d.fps, "alpha": d.alpha_, "opts": d.opts} if d != null else null

## Redraws every cached canvas (palette tweak...).
static func invalidateAll() -> void:
	layerCache.clear()
	for e in staticCache.values():
		render(e.def, e.canvas.getContext("2d"), quantize(e.def, float(_or(e.opts.get("time"), 0))), e.opts)
	for h in animCache.values():
		h.redraw()

## Namespace form of the API (see header). JS `cards.get` -> get_.
class Namespace:
	extends RefCounted
	func get_(id: String, opts: Dictionary = {}) -> Texture2D:
		return DACards.getCard(id, opts)
	func animated(id: String, opts: Dictionary = {}):
		return DACards.getAnimated(id, opts)
	func drawTo(ctx, id: String, w: float, h: float, time: float = 0.0, opts: Dictionary = {}) -> void:
		DACards.drawTo(ctx, id, w, h, time, opts)
	func ids() -> Array:
		return DACards.cardIds()
	func info(id: String):
		return DACards.cardInfo(id)
	func invalidateAll() -> void:
		DACards.invalidateAll()

static var cards: Namespace = Namespace.new()

## Installs the namespace as game.cards (DAGame calls DACards.install(self); also done on first use).
static func install(game) -> void:
	if game != null:
		game.cards = cards

static func _static_init() -> void:
	if ClassDB.class_exists("Node") and Engine.get_main_loop() != null:
		var g = DAGame.inst if DAGame.inst != null else null
		if g != null and g.cards == null:
			g.cards = cards

static func _ensure() -> void:
	if _registered:
		return
	_registered = true
	if DAGame.inst != null and DAGame.inst.cards == null:
		DAGame.inst.cards = cards
	_register()

# ---------------------------------------------------------------------------------------------------------
# Telly's face: vector shapes in a 64x48 box, rendered as glowing scanline dots
# ---------------------------------------------------------------------------------------------------------

const TELLY_EXPRS := ["idle", "sleepy", "happy", "o_mouth", "wink", "pout", "glare", "shiver", "zzz", "baron_glitch"]

# (JS closures of tellyFaceShapes as helpers)
static func _openEye(ctx, ink, hole, x: float, y: float, rx: float = 7.5, ry: float = 9.5, pr: float = 3.8, gx: float = 0.0, gy: float = 0.0) -> void:
	ellipse(ctx, x, y, rx, ry)
	fill(ctx, ink)
	var px := x + gx * (rx - pr - 1.2)
	var py := y + 1.2 + gy * (ry - pr - 2)
	circle(ctx, px, py, pr)
	fill(ctx, hole)
	circle(ctx, px - pr * 0.35, py - pr * 0.4, pr * 0.32)
	fill(ctx, ink)

static func _shutEye(ctx, ink, x: float, y: float, up: bool, w: float = 7.0) -> void:
	ctx.beginPath()
	if up:
		ctx.arc(x, y + 4.5, w, PI * 1.15, PI * 1.85)
	else:
		ctx.arc(x, y - 3.5, w, PI * 0.15, PI * 0.85)
	stroke(ctx, ink, 3.4)

static func _flatEye(ctx, ink, x: float, y: float) -> void:
	ctx.beginPath()
	ctx.moveTo(x - 6.5, y + 1)
	ctx.quadraticCurveTo(x, y + 3, x + 6.5, y + 1)
	stroke(ctx, ink, 3.4)

static func _smile(ctx, ink, w: float = 10.0, d: float = 4.5, y: float = 33.0) -> void:
	ctx.beginPath()
	ctx.moveTo(32 - w, y)
	ctx.quadraticCurveTo(32, y + d * 2, 32 + w, y)
	stroke(ctx, ink, 3.4)

static func _Z(ctx, ink, x: float, y: float, s: float) -> void:
	poly(ctx, [x - s, y - s, x + s, y - s, x - s, y + s, x + s, y + s], false)
	stroke(ctx, ink, maxf(1.6, s * 0.5))

## Draws expression `expr` in a 64x48 box. ink = lit, hole = unlit (pupils, lids). look = gaze [-1..1, -1..1].
static func tellyFaceShapes(ctx, expr: String, t: float, look: Array, ink, hole) -> void:
	var lx := clampf(look[0], -1, 1)
	var ly := clampf(look[1], -1, 1)
	ctx.lineCap = "round"
	ctx.lineJoin = "round"
	var L := 21.0
	var R := 43.0
	var EY := 19.0
	var blink := fract(t / 3.7 + 0.13) > 0.955

	match expr:
		"sleepy":
			_shutEye(ctx, ink, L, EY + 2, false)
			_shutEye(ctx, ink, R, EY + 2, false)
			_smile(ctx, ink, 5, 2, 35)
		"happy":
			_shutEye(ctx, ink, L, EY, true)
			_shutEye(ctx, ink, R, EY, true)
			ctx.beginPath()
			ctx.moveTo(20, 30)
			ctx.lineTo(44, 30)
			ctx.quadraticCurveTo(44, 44, 32, 44)
			ctx.quadraticCurveTo(20, 44, 20, 30)
			fill(ctx, ink)
			ctx.beginPath()
			ctx.moveTo(23, 32.5)
			ctx.lineTo(41, 32.5)
			ctx.quadraticCurveTo(41, 41.5, 32, 41.5)
			ctx.quadraticCurveTo(23, 41.5, 23, 32.5)
			fill(ctx, hole)
			ellipse(ctx, 32, 40, 6, 3.2)
			fill(ctx, ink)
		"o_mouth":
			_openEye(ctx, ink, hole, L, EY, 8.5, 10.5, 3.2, lx, ly)
			_openEye(ctx, ink, hole, R, EY, 8.5, 10.5, 3.2, lx, ly)
			ellipse(ctx, 32, 37, 4.5, 5.5)
			stroke(ctx, ink, 3.2)
		"wink":
			_openEye(ctx, ink, hole, L, EY, 7.5, 9.5, 3.8, lx, ly)
			_shutEye(ctx, ink, R, EY, true)
			ctx.beginPath()
			ctx.moveTo(R + 6, EY - 1)
			ctx.lineTo(R + 10, EY - 4)
			stroke(ctx, ink, 2.4)
			_smile(ctx, ink, 11, 5, 32)
			ctx.beginPath()
			ctx.moveTo(34, 38.5)
			ctx.quadraticCurveTo(37, 45, 40, 37.5)
			fill(ctx, ink)
		"pout":
			for x in [L, R]:
				_openEye(ctx, ink, hole, x, EY + 1, 7.5, 9, 3.6, lx * 0.5, 0.8)
				ctx.fillStyle = hole
				ctx.fillRect(x - 9, EY - 12, 18, 10.5)
				ctx.beginPath()
				ctx.moveTo(x - 7.5, EY - 1.5 + (1.5 if x == L else -0.5))
				ctx.lineTo(x + 7.5, EY - 1.5 + (-0.5 if x == L else 1.5))
				stroke(ctx, ink, 2.6)
			ctx.beginPath()
			ctx.moveTo(25, 39)
			ctx.quadraticCurveTo(32, 32, 39, 39)
			stroke(ctx, ink, 3.4)
			ctx.beginPath()
			ctx.moveTo(L - 3, EY + 11)
			ctx.quadraticCurveTo(L - 5.5, EY + 15, L - 3, EY + 16.5)
			ctx.quadraticCurveTo(L - 0.5, EY + 15, L - 3, EY + 11)
			fill(ctx, ink)
		"glare":
			_openEye(ctx, ink, hole, L, EY + 1, 7.5, 9, 3.4, 0, 0.2)
			_openEye(ctx, ink, hole, R, EY + 1, 7.5, 9, 3.4, 0, 0.2)
			poly(ctx, [10, 2, 31, 2, 31, 16, 10, 8])
			fill(ctx, hole)
			poly(ctx, [54, 2, 33, 2, 33, 16, 54, 8])
			fill(ctx, hole)
			ctx.beginPath()
			ctx.moveTo(12, 8)
			ctx.lineTo(29, 14.5)
			ctx.moveTo(52, 8)
			ctx.lineTo(35, 14.5)
			stroke(ctx, ink, 3.6)
			ctx.beginPath()
			ctx.moveTo(24, 37)
			ctx.lineTo(40, 35.5)
			stroke(ctx, ink, 3.4)
		"shiver":
			var j := (1.0 if (int(floorf(t * 24)) & 1) else -1.0) * 0.9
			ctx.save()
			ctx.translate(j, 0)
			_openEye(ctx, ink, hole, L, EY, 8.5, 10.5, 2.3, 0, 0)
			_openEye(ctx, ink, hole, R, EY, 8.5, 10.5, 2.3, 0, 0)
			var zz := []
			for i in 9:
				zz.append(21 + i * 2.75)
				zz.append(32.5 if (i & 1) else 37.0)
			poly(ctx, zz, false)
			stroke(ctx, ink, 2.6)
			ctx.beginPath()
			ctx.moveTo(55, 6)
			ctx.quadraticCurveTo(51, 12, 55, 14)
			ctx.quadraticCurveTo(59, 12, 55, 6)
			fill(ctx, ink)
			ctx.restore()
		"zzz":
			_shutEye(ctx, ink, L, EY + 2, false)
			_shutEye(ctx, ink, R, EY + 2, false)
			ellipse(ctx, 32, 36, 2.8, 2.4)
			stroke(ctx, ink, 2.4)
			for k in 3:
				var p := fract(t * 0.45 + k / 3.0)
				if p > 0.92:
					continue
				_Z(ctx, ink, 49 + p * 9, 16 - p * 15, 2 + p * 3.2)
		"baron_glitch":
			baronDots(ctx, t, ink, hole)
		_:
			if blink:
				_flatEye(ctx, ink, L, EY)
				_flatEye(ctx, ink, R, EY)
			else:
				_openEye(ctx, ink, hole, L, EY, 7.5, 9.5, 3.8, lx, ly)
				_openEye(ctx, ink, hole, R, EY, 7.5, 9.5, 3.8, lx, ly)
			_smile(ctx, ink, 10, 4.5, 33)

## The Baron as dot-matrix line art (Telly glitch, EE step 4).
static func baronDots(ctx, t: float, ink, hole) -> void:
	ctx.lineCap = "round"
	ctx.lineJoin = "round"
	poly(ctx, [6, 12, 20, 3, 32, 13, 44, 3, 58, 12], false)
	stroke(ctx, ink, 3)
	ctx.beginPath()
	ctx.moveTo(11, 13)
	ctx.lineTo(27, 18)
	ctx.moveTo(53, 13)
	ctx.lineTo(37, 18)
	stroke(ctx, ink, 3.6)
	ellipse(ctx, 21, 22, 6, 3.6, 0.2)
	fill(ctx, ink)
	ellipse(ctx, 43, 22, 6, 3.6, -0.2)
	fill(ctx, ink)
	circle(ctx, 21, 22.4, 2)
	fill(ctx, hole)
	circle(ctx, 43, 22.4, 2)
	fill(ctx, hole)
	circle(ctx, 43, 22, 9)
	stroke(ctx, ink, 1.8)
	ctx.beginPath()
	ctx.moveTo(51, 26)
	ctx.quadraticCurveTo(55, 36, 50, 46)
	stroke(ctx, ink, 1.2)
	var open := 2 + absf(sin(t * 9)) * 3
	ctx.beginPath()
	ctx.moveTo(16, 32)
	ctx.quadraticCurveTo(32, 36, 48, 32)
	ctx.quadraticCurveTo(32, 40 + open, 16, 32)
	fill(ctx, ink)
	poly(ctx, [24, 33.4, 27.5, 33.8, 25.6, 38.5])
	fill(ctx, hole)
	poly(ctx, [36.5, 33.8, 40, 33.4, 38.4, 38.5])
	fill(ctx, hole)

static var dotMask: DACanvas = null
static var dotGlow: DACanvas = null
## Renders drawShapes (64x48 space, white on black) as a dot-matrix into (x, y, w, h).
## o: { cols, rows, core, glow, dim, split, seed }
static func dotMatrix(ctx, x: float, y: float, w: float, h: float, drawShapes: Callable, o: Dictionary = {}) -> void:
	var cols := int(_or(o.get("cols"), 64))
	var rows := int(_or(o.get("rows"), 48))
	if dotMask == null:
		dotMask = makeCanvas(64, 48)
		dotMask.userData.ctx = dotMask.getContext("2d", {"willReadFrequently": true})
	if dotMask.width != cols or dotMask.height != rows:
		dotMask.width = cols
		dotMask.height = rows
	var m = dotMask.userData.ctx
	m.setTransform(1, 0, 0, 1, 0, 0)
	m.fillStyle = "#000"
	m.fillRect(0, 0, cols, rows)
	m.scale(cols / 64.0, rows / 48.0)
	drawShapes.call(m)
	var data: PackedByteArray = m.getImageData(0, 0, cols, rows).data
	var sx := w / cols
	var sy := h / rows
	var maxR := minf(sx, sy) * 0.46
	var r := rng(int(_or(o.get("seed"), 1)))
	var shift := PackedFloat32Array()
	shift.resize(rows)
	if o.get("split"):
		for j in rows:
			shift[j] = (r.call() - 0.5) * sx * 6 if r.call() < 0.12 else 0.0
	var dots := DAPath2D.new()
	var halo := DAPath2D.new()
	for j in rows:
		for i in cols:
			var v := data[(j * cols + i) * 4] / 255.0
			if v < 0.14:
				continue
			var cx := x + (i + 0.5) * sx + shift[j]
			var cy := y + (j + 0.5) * sy
			var rad := maxR * (0.5 + 0.5 * v)
			dots.moveTo(cx + rad, cy)
			dots.arc(cx, cy, rad, 0, TAU)
			halo.moveTo(cx + rad * 2.2, cy)
			halo.arc(cx, cy, rad * 2.2, 0, TAU)
	if o.get("dim") != false:
		ctx.fillStyle = layerPattern(ctx, sx, sy, maxR * 0.42, _or(o.get("dim"), "rgba(127,231,255,0.08)"))
		ctx.save()
		ctx.translate(x, y)
		ctx.fillRect(0, 0, w, h)
		ctx.restore()
	# Soft glow: halo dots drawn at quarter scale and upsampled (cheap blur).
	var gw := maxi(8, int(ceil(w / 4)))
	var gh := maxi(8, int(ceil(h / 4)))
	if dotGlow == null:
		dotGlow = makeCanvas(gw, gh)
		dotGlow.bakeMode = "never"
	if dotGlow.width < gw or dotGlow.height < gh:
		dotGlow.width = gw
		dotGlow.height = gh
	var g = dotGlow.getContext("2d")
	g.setTransform(1, 0, 0, 1, 0, 0)
	g.clearRect(0, 0, dotGlow.width, dotGlow.height)
	g.scale(0.25, 0.25)
	g.translate(-x, -y)
	g.fillStyle = _or(o.get("glow"), C.crt)
	g.fill(halo)
	ctx.save()
	ctx.globalCompositeOperation = "lighter"
	ctx.globalAlpha = 0.55
	ctx.imageSmoothingEnabled = true
	ctx.drawImage(dotGlow, 0, 0, gw, gh, x, y, gw * 4, gh * 4)
	ctx.restore()
	if o.get("split"):
		ctx.save()
		ctx.globalCompositeOperation = "lighter"
		ctx.translate(-sx * 0.6, 0)
		ctx.fillStyle = "rgba(255,60,200,0.75)"
		ctx.fill(dots)
		ctx.translate(sx * 1.2, 0)
		ctx.fillStyle = "rgba(80,255,140,0.75)"
		ctx.fill(dots)
		ctx.restore()
	ctx.fillStyle = _or(o.get("core"), "#E6FDFF")
	ctx.fill(dots)

static var dimPatterns := {}
## Pattern of unlit dots (the LED panel look), cached per spacing.
static func layerPattern(ctx, sx: float, sy: float, r: float, color: String):
	var key := "%.2f|%.2f|%.2f|%s" % [sx, sy, r, color]
	var tile: DACanvas = dimPatterns.get(key)
	if tile == null:
		var tw := maxi(1, int(jround(sx * 8)))
		var th := maxi(1, int(jround(sy * 8)))
		tile = makeCanvas(tw, th)
		tile.bakeMode = "now"
		var g = tile.getContext("2d")
		g.fillStyle = color
		g.beginPath()
		for j in 8:
			for i in 8:
				var cx := ((i + 0.5) * tw) / 8
				var cy := ((j + 0.5) * th) / 8
				g.moveTo(cx + r, cy)
				g.arc(cx, cy, r, 0, TAU)
		g.fill()
		dimPatterns[key] = tile
	return ctx.createPattern(tile, "repeat")

## Telly's face on a CRT rectangle (background + dots).
static func tellyScreen(ctx, x: float, y: float, w: float, h: float, expr: String, t: float, look: Array = [0, 0], cols: int = 64) -> void:
	var rows := int(jround(cols * 0.75))
	var glitch := expr == "baron_glitch"
	ctx.fillStyle = radial(ctx, x + w / 2, y + h * 0.45, 0, maxf(w, h) * 0.7,
		["#2A1840", "#150C22"] if glitch else ["#1D4656", "#10283A", "#0B1A28"])
	ctx.fillRect(x, y, w, h)
	dotMatrix(ctx, x + w * 0.04, y + h * 0.04, w * 0.92, h * 0.92,
		func(m): tellyFaceShapes(m, expr, t, look, "#fff", "#000"),
		{"cols": cols, "rows": rows, "split": glitch, "seed": int(floorf(t * 12)) + 3, "core": "#F4E8FF" if glitch else "#E6FDFF", "glow": "#C77DFF" if glitch else C.crt})

# ---------------------------------------------------------------------------------------------------------
# Telly the console TV, the white glove, station logo, "13" badge
# ---------------------------------------------------------------------------------------------------------

## White four-finger cartoon glove, wrist at (x, y), fingers pointing along -y rotated by rot.
static func drawGlove(ctx, x: float, y: float, s: float, rot: float = 0.0, pose: String = "open") -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(rot)
	ctx.scale(s, s)
	var ol := 0.07
	var fingers := [[0.02, -0.52, 0.06, -1.22]] if pose == "point" else [[-0.24, -0.55, -0.4, -1.08], [0, -0.6, 0.02, -1.2], [0.24, -0.55, 0.42, -1.06]]
	var curled := [[-0.2, -0.5, -0.22, -0.72], [0.22, -0.5, 0.25, -0.7]] if pose == "point" else []
	var shapes := func(extra: float, style):
		ctx.fillStyle = style
		ctx.strokeStyle = style
		ctx.lineCap = "round"
		for f in fingers + curled:
			ctx.beginPath(); ctx.moveTo(f[0], f[1]); ctx.lineTo(f[2], f[3])
			ctx.lineWidth = 0.27 + extra; ctx.stroke()
		ctx.beginPath(); ctx.moveTo(-0.28, -0.35); ctx.lineTo(-0.68, -0.62)
		ctx.lineWidth = 0.25 + extra; ctx.stroke()
		ellipse(ctx, 0, -0.42, 0.42 + extra / 2, 0.36 + extra / 2)
		ctx.fill()
		ctx.beginPath()
		ctx.roundRect(-0.34 - extra / 2, -0.16 - extra / 2, 0.68 + extra, 0.34 + extra, 0.12)
		ctx.fill()
	shapes.call(ol * 2, C.ink)
	shapes.call(0.0, "#FFFFFF")
	ctx.fillStyle = "#E4E0F2"
	ellipse(ctx, 0.08, -0.3, 0.3, 0.14)
	ctx.fill()
	ctx.beginPath()
	ctx.roundRect(-0.34, 0.06, 0.68, 0.12, 0.06)
	ctx.fill()
	ctx.strokeStyle = C.ink
	ctx.lineWidth = 0.045
	ctx.beginPath()
	for sx in [-0.14, 0.0, 0.14]:
		ctx.moveTo(sx, -0.62)
		ctx.lineTo(sx * 1.2, -0.4)
	ctx.moveTo(-0.34, 0.0)
	ctx.lineTo(0.34, 0.0)
	ctx.stroke()
	ctx.restore()

## Telly, the walnut console TV mascot. (cx, cy) = cabinet centre, s = cabinet width.
## o: { expr, t, look, wave (glove angle, radians) , hop, cols }
static func drawTelly(ctx, cx: float, cy: float, s: float, o: Dictionary = {}) -> void:
	var t: float = _or(o.get("t"), 0)
	var w := s
	var h := s * 0.74
	var x := cx - w / 2
	var y := cy - h / 2
	var ol := maxf(1.5, s * 0.016)
	ctx.save()
	ctx.lineJoin = "round"
	ctx.lineCap = "round"
	# rabbit ears
	var ax := x + w * 0.42
	var ay := y + s * 0.01
	for side in [-1, 1]:
		var a: float = side * (26 + float(_or(o.get("earTwitch"), 0)) * side) * DEG
		var ln := s * 0.52
		var ex := ax + sin(a) * ln
		var ey := ay - cos(a) * ln
		capsule(ctx, ax, ay, ex, ey, s * 0.02, "#D5DAE8", C.ink, ol * 0.7)
		circle(ctx, ex, ey, s * 0.032)
		inked(ctx, radial(ctx, ex - s * 0.01, ey - s * 0.01, 0, s * 0.04, ["#FFFFFF", "#BFC6DA"]), ol * 0.7)
	ellipse(ctx, ax, ay + s * 0.012, s * 0.08, s * 0.05)
	inked(ctx, linear(ctx, 0, ay - s * 0.04, 0, ay + s * 0.05, ["#6A4A3A", "#3A2630"]), ol)
	# legs
	for leg in [[0.17, -1], [0.83, 1]]:
		var bx: float = x + w * leg[0]
		var by := y + h - ol
		var dir: float = leg[1]
		poly(ctx, [bx - s * 0.035, by, bx + s * 0.035, by, bx + dir * s * 0.075 + s * 0.013, by + s * 0.25, bx + dir * s * 0.075 - s * 0.013, by + s * 0.25])
		inked(ctx, linear(ctx, bx - s * 0.04, 0, bx + s * 0.04, 0, ["#6A3E22", "#4A2A18"]), ol)
		rr(ctx, bx + dir * s * 0.075 - s * 0.018, by + s * 0.22, s * 0.036, s * 0.04, s * 0.01)
		inked(ctx, C.brass, ol * 0.7)
	# cabinet
	rr(ctx, x, y, w, h, s * 0.09)
	inked(ctx, linear(ctx, 0, y, 0, y + h, ["#B27A45", "#8C5630", "#6A3C20"]), ol * 1.3)
	ctx.save()
	rr(ctx, x, y, w, h, s * 0.09)
	ctx.clip()
	var g := rng(42)
	ctx.strokeStyle = "rgba(70,36,18,0.28)"
	ctx.lineWidth = maxf(1, s * 0.006)
	for i in 16:
		var yy: float = y + h * (i + 0.5) / 16 + g.call() * 3
		ctx.beginPath()
		ctx.moveTo(x, yy)
		var c1y: float = yy + (g.call() - 0.5) * s * 0.05
		var c2y: float = yy + (g.call() - 0.5) * s * 0.05
		var ey2: float = yy + (g.call() - 0.5) * 4
		ctx.bezierCurveTo(x + w * 0.3, c1y, x + w * 0.6, c2y, x + w, ey2)
		ctx.stroke()
	ctx.fillStyle = "rgba(255,220,170,0.28)"
	ctx.fillRect(x, y + s * 0.008, w, s * 0.03)
	ctx.restore()
	# screen
	var bx2 := x + w * 0.055
	var by2 := y + h * 0.1
	var bw := w * 0.62
	var bh := h * 0.8
	rr(ctx, bx2, by2, bw, bh, bh * 0.26)
	inked(ctx, linear(ctx, 0, by2, 0, by2 + bh, ["#FBF1D8", "#E3D2AA", "#BCA57A"]), ol)
	var ins := s * 0.028
	var sx := bx2 + ins
	var sy := by2 + ins
	var sw := bw - ins * 2
	var sh := bh - ins * 2
	ctx.save()
	rr(ctx, sx, sy, sw, sh, sh * 0.24)
	ctx.clip()
	tellyScreen(ctx, sx, sy, sw, sh, _or(o.get("expr"), "idle"), t, _or(o.get("look"), [0, 0]), int(_or(o.get("cols"), clampf(jround(sw / 4.2), 20, 64))))
	ctx.fillStyle = linear(ctx, sx, sy, sx + sw * 0.6, sy + sh * 0.6, ["rgba(255,255,255,0.22)", "rgba(255,255,255,0.04)", "rgba(255,255,255,0)"])
	ctx.beginPath()
	ctx.ellipse(sx + sw * 0.28, sy + sh * 0.18, sw * 0.34, sh * 0.16, -0.2, 0, TAU)
	ctx.fill()
	ctx.restore()
	rr(ctx, sx, sy, sw, sh, sh * 0.24)
	stroke(ctx, C.ink, ol)
	# controls
	var kx := x + w * 0.835
	var dr := s * 0.078
	var dy0 := y + h * 0.27
	circle(ctx, kx, dy0, dr * 1.25)
	inked(ctx, "#5A341C", ol * 0.8)
	ctx.strokeStyle = "#F6E7C8"
	ctx.lineWidth = maxf(1, s * 0.006)
	ctx.beginPath()
	for i in 12:
		var a2 := (i / 12.0) * TAU
		ctx.moveTo(kx + cos(a2) * dr * 1.02, dy0 + sin(a2) * dr * 1.02)
		ctx.lineTo(kx + cos(a2) * dr * 1.16, dy0 + sin(a2) * dr * 1.16)
	ctx.stroke()
	circle(ctx, kx, dy0, dr * 0.9)
	inked(ctx, radial(ctx, kx - dr * 0.3, dy0 - dr * 0.3, 0, dr, ["#FFF8E6", "#E8D6B0", "#B89D70"]), ol * 0.8)
	var da: float = float(_nn(o.get("dial"), 0.6)) * TAU
	capsule(ctx, kx, dy0, kx + sin(da) * dr * 0.7, dy0 - cos(da) * dr * 0.7, dr * 0.22, C.red)
	circle(ctx, kx, y + h * 0.49, s * 0.034)
	inked(ctx, radial(ctx, kx, y + h * 0.48, 0, s * 0.04, ["#FFF8E6", "#B89D70"]), ol * 0.8)
	var gy := y + h * 0.74
	var gr := s * 0.095
	ctx.save()
	circle(ctx, kx, gy, gr)
	ctx.clip()
	ctx.fillStyle = "#4A2A18"
	ctx.fillRect(kx - gr, gy - gr, gr * 2, gr * 2)
	rays(ctx, kx, gy, gr, 14, "#C8905A", 0.1, 0.45)
	ctx.restore()
	circle(ctx, kx, gy, gr)
	stroke(ctx, C.ink, ol * 0.8)
	circle(ctx, kx, gy, gr * 0.22)
	inked(ctx, C.brass, ol * 0.6)
	# glove waving out of the screen edge
	if o.has("wave") and o.wave != null:
		var sx0 := bx2 + bw - ins * 0.5
		var sy0 := by2 + bh * 0.45
		var gx := x + w * 1.02 + sin(o.wave) * s * 0.06
		var gyy := y - s * 0.12
		ctx.beginPath()
		ctx.moveTo(sx0, sy0)
		ctx.bezierCurveTo(sx0 + s * 0.22, sy0, gx - s * 0.05, gyy + s * 0.35, gx, gyy + s * 0.04)
		ctx.strokeStyle = C.ink
		ctx.lineWidth = s * 0.075 + ol * 2
		ctx.stroke()
		ctx.strokeStyle = "#F4F2FA"
		ctx.lineWidth = s * 0.075
		ctx.stroke()
		drawGlove(ctx, gx, gyy + s * 0.04, s * 0.26, o.wave, "open")
	ctx.restore()

## Blue disc, red ring, white "13" (colours overridable: the cap badge is white/red/blue).
static func badge13(ctx, x: float, y: float, r: float, o: Dictionary = {}) -> void:
	circle(ctx, x, y, r)
	inked(ctx, _or(o.get("ring"), C.red), _nn(o.get("ol"), r * 0.06))
	circle(ctx, x, y, r * 0.8)
	fill(ctx, _or(o.get("disc"), C.blue))
	if o.get("inner"):
		circle(ctx, x, y, r * 0.8)
		stroke(ctx, o.inner, r * 0.05)
	# Letter in device pixels, so the badge also works inside unit-space drawings (busts).
	var m: Dictionary = ctx.getTransform()
	var k: float = _or(Vector2(m.a, m.b).length(), 1.0)
	ctx.save()
	ctx.translate(x, y + r * 0.06)
	ctx.scale(1 / k, 1 / k)
	label(ctx, "13", 0, 0, {"fam": FONT.round, "px": r * 0.92 * k, "maxW": r * 1.25 * k, "fill": _or(o.get("num"), "#FFFFFF")})
	ctx.restore()
	ctx.save()
	circle(ctx, x, y, r)
	ctx.clip()
	ctx.fillStyle = linear(ctx, 0, y - r, 0, y, ["rgba(255,255,255,0.35)", "rgba(255,255,255,0)"])
	ctx.fillRect(x - r, y - r, r * 2, r)
	ctx.restore()

## WZTV + 13 station logo centred at (cx, cy), cap height h.
## o: { style: 'neon' | 'flat', dead: ['Z','T'], lit: true }
static func drawLogo(ctx, cx: float, cy: float, h: float, o: Dictionary = {}) -> void:
	var letters := ["W", "Z", "T", "V"]
	ctx.save()
	setFont(ctx, h * 1.25, FONT.sign)
	var ws := []
	for l in letters:
		ws.append(ctx.measureText(l).width)
	var gap := h * 0.06
	var disc := h * 1.2
	var total: float = ws[0] + ws[1] + ws[2] + ws[3] + gap * 4 + disc
	var x := cx - total / 2
	ctx.textBaseline = "middle"
	ctx.textAlign = "left"
	ctx.lineJoin = "round"
	for i in letters.size():
		var l: String = letters[i]
		var col: String = NEON[l]
		var dead: bool = (o.get("dead") != null and (o.dead as Array).has(l)) or o.get("lit") == false
		if o.get("style") == "neon":
			ctx.save()
			ctx.lineWidth = h * 0.1
			ctx.strokeStyle = darken(col, 0.45) if dead else col
			if not dead:
				ctx.shadowColor = col
				ctx.shadowBlur = h * 0.5
			ctx.strokeText(l, x, cy)
			ctx.strokeText(l, x, cy)
			ctx.shadowBlur = 0
			ctx.lineWidth = h * 0.035
			ctx.strokeStyle = darken(col, 0.25) if dead else lighten(col, 0.75)
			ctx.strokeText(l, x, cy)
			ctx.restore()
		else:
			var k := int(jround(h * 0.12))
			while k > 0:
				ctx.fillStyle = darken(col, 0.5)
				ctx.fillText(l, x + k * 0.6, cy + k)
				k -= 1
			ctx.lineWidth = h * 0.09
			ctx.strokeStyle = C.ink
			ctx.strokeText(l, x, cy)
			ctx.fillStyle = linear(ctx, 0, cy - h * 0.6, 0, cy + h * 0.6, [lighten(col, 0.35), col, darken(col, 0.15)])
			ctx.fillText(l, x, cy)
		x += ws[i] + gap
	var dr := disc / 2
	if o.get("style") == "neon" and o.get("lit") != false:
		ctx.save()
		ctx.shadowColor = "#7FB0FF"
		ctx.shadowBlur = h * 0.5
		circle(ctx, x + dr, cy, dr)
		fill(ctx, C.red)
		ctx.restore()
	badge13(ctx, x + dr, cy, dr, {"ol": h * 0.05})
	ctx.restore()

# ---------------------------------------------------------------------------------------------------------
# Cartoon busts (portraits, posters, magazine). Unit space: face centre (0,0), head radius 1.
# ---------------------------------------------------------------------------------------------------------

const LW := 0.055
const SKIN := {"skip": "#F2C29B", "roxy": "#8A5A3C", "penny": "#F4C7A6", "duke": "#E6B089", "baron": "#CBC2DD", "stu": "#F0BE96"}

## Text inside a scaled unit-space transform (fonts are specified in device pixels).
static func uText(ctx, s: String, x: float, y: float, px: float, fam: String, style, o: Dictionary = {}) -> void:
	var m: Dictionary = ctx.getTransform()
	var sc := Vector2(m.a, m.b).length()
	ctx.save()
	ctx.translate(x, y)
	if o.get("rot"):
		ctx.rotate(o.rot)
	ctx.scale(1 / sc, 1 / sc)
	var lo := {"fam": fam, "px": px * sc, "fill": style, "stroke": o.get("stroke")}
	if o.get("lw"):
		lo.lw = o.lw * sc
	if o.get("maxW"):
		lo.maxW = o.maxW * sc
	label(ctx, s, 0, 0, lo)
	ctx.restore()

static func headPath(ctx, jaw: float = 1.0, long: float = 1.0) -> void:
	var cw := 0.6 * jaw + 0.1
	var by := 0.98 * long
	ctx.beginPath()
	ctx.moveTo(0, -1)
	ctx.bezierCurveTo(0.62, -1, 0.9, -0.62, 0.9, -0.1)
	ctx.bezierCurveTo(0.9, 0.45 * long, cw, by * 0.96, 0, by)
	ctx.bezierCurveTo(-cw, by * 0.96, -0.9, 0.45 * long, -0.9, -0.1)
	ctx.bezierCurveTo(-0.9, -0.62, -0.62, -1, 0, -1)
	ctx.closePath()

static func faceBase(ctx, skin: String, jaw: float = 1.0, long: float = 1.0, blush: float = 0.26) -> void:
	headPath(ctx, jaw, long)
	inked(ctx, radial(ctx, -0.2, -0.25, 0.05, 1.25, [lighten(skin, 0.16), skin, darken(skin, 0.14)]), LW)
	if blush:
		for s in [-1, 1]:
			ellipse(ctx, s * 0.52, 0.36, 0.19, 0.11)
			fill(ctx, alpha("#FF6B6B", blush))

static func ears(ctx, skin: String, y: float = 0.08, pointed: bool = false) -> void:
	for s in [-1, 1]:
		ctx.beginPath()
		if pointed:
			ctx.moveTo(s * 0.84, -0.12)
			ctx.quadraticCurveTo(s * 1.3, -0.45, s * 1.12, 0.05)
			ctx.quadraticCurveTo(s * 1.05, 0.34, s * 0.84, 0.3)
		else:
			ctx.ellipse(s * 0.9, y, 0.15, 0.21, 0, 0, TAU)
		inked(ctx, skin, LW)
		ctx.beginPath()
		ctx.arc(s * 0.92, y, 0.08, -1.2 if s > 0 else 1.9, 1.2 if s > 0 else 4.3)
		stroke(ctx, darken(skin, 0.25), 0.035)

static func neck(ctx, skin: String, w: float = 0.3) -> void:
	rr(ctx, -w, 0.55, w * 2, 0.75, 0.1)
	inked(ctx, darken(skin, 0.1), LW)
	ellipse(ctx, 0, 0.82, w * 0.9, 0.12)
	fill(ctx, alpha(darken(skin, 0.4), 0.35))

## Pair of big cartoon eyes. o: { y, x, rx, ry, iris, lash, wink, look, lid, squint, tiny }
static func eyes(ctx, skin: String, o: Dictionary = {}) -> void:
	var y: float = _nn(o.get("y"), 0.06)
	var ex0: float = _nn(o.get("x"), 0.34)
	var rx: float = _nn(o.get("rx"), 0.19)
	var ry: float = _nn(o.get("ry"), 0.23)
	var look: Array = _or(o.get("look"), [0.04, 0])
	var iris: String = _or(o.get("iris"), "#6B3A1E")
	for s in [-1, 1]:
		var ex := s * ex0
		if o.get("wink") and s == 1:
			ctx.beginPath()
			ctx.arc(ex, y + ry * 0.55, rx * 1.05, PI * 1.15, PI * 1.85)
			stroke(ctx, C.ink, 0.07)
			if o.get("lash"):
				capsule(ctx, ex + rx * 0.9, y - ry * 0.05, ex + rx * 1.3, y - ry * 0.3, 0.035, C.ink)
			continue
		ellipse(ctx, ex, y, rx, ry)
		inked(ctx, "#FFFDF6", 0.04)
		ctx.save()
		ellipse(ctx, ex, y, rx, ry)
		ctx.clip()
		var ix: float = ex + look[0] * rx * 0.4
		var iy: float = y + ry * 0.12 + look[1] * ry * 0.3
		var ir: float = rx * (0.45 if o.get("tiny") else 0.78)
		circle(ctx, ix, iy, ir)
		fill(ctx, radial(ctx, ix, iy - ir * 0.3, ir * 0.1, ir, [lighten(iris, 0.35), iris, darken(iris, 0.35)]))
		circle(ctx, ix, iy, ir * 0.5)
		fill(ctx, "#1E1428")
		circle(ctx, ix + ir * 0.35, iy - ir * 0.4, ir * 0.3)
		fill(ctx, "#FFFFFF")
		circle(ctx, ix - ir * 0.35, iy + ir * 0.35, ir * 0.13)
		fill(ctx, "#FFFFFF")
		if o.get("lid"):
			ctx.fillStyle = skin
			ctx.fillRect(ex - rx, y - ry, rx * 2, ry * 2 * o.lid)
		if o.get("squint"):
			ctx.fillStyle = skin
			ctx.beginPath()
			ctx.ellipse(ex, y + ry * 1.25, rx * 1.3, ry * 0.7, 0, 0, TAU)
			ctx.fill()
		ctx.restore()
		ctx.beginPath()
		ctx.ellipse(ex, y, rx, ry, 0, PI * 1.02, PI * 1.98)
		stroke(ctx, C.ink, 0.075)
		if o.get("lid"):
			ctx.beginPath()
			ctx.moveTo(ex - rx, y - ry + ry * 2 * o.lid)
			ctx.lineTo(ex + rx, y - ry + ry * 2 * o.lid)
			stroke(ctx, C.ink, 0.06)
		if o.get("lash"):
			capsule(ctx, ex + s * rx * 0.85, y - ry * 0.55, ex + s * rx * 1.28, y - ry * 0.85, 0.035, C.ink)
			capsule(ctx, ex + s * rx * 0.98, y - ry * 0.2, ex + s * rx * 1.38, y - ry * 0.35, 0.035, C.ink)

static func brows(ctx, color, y: float = -0.26, tilt: float = 0.0, thick: float = 0.075, x: float = 0.34, ln: float = 0.2, arch: float = 0.04) -> void:
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(s * (x - ln), y + tilt)
		ctx.quadraticCurveTo(s * x, y - arch - 0.02, s * (x + ln), y - tilt * 0.4)
		ctx.lineCap = "round"
		stroke(ctx, color, thick)

static func nose(ctx, skin: String, y: float = 0.3, w: float = 0.1) -> void:
	ellipse(ctx, 0, y, w, w * 0.78)
	fill(ctx, darken(skin, 0.1))
	ellipse(ctx, -w * 0.25, y - w * 0.25, w * 0.35, w * 0.25)
	fill(ctx, alpha("#FFFFFF", 0.35))

## Mouth. kind: smile | grin (open with teeth) | smirk | line | o
static func mouth(ctx, kind: String = "smile", y: float = 0.58, w: float = 0.24, lip = null) -> void:
	ctx.lineCap = "round"
	if kind == "grin":
		ctx.beginPath()
		ctx.moveTo(-w, y - 0.04)
		ctx.quadraticCurveTo(0, y + 0.04, w, y - 0.04)
		ctx.quadraticCurveTo(w * 0.8, y + 0.26, 0, y + 0.26)
		ctx.quadraticCurveTo(-w * 0.8, y + 0.26, -w, y - 0.04)
		inked(ctx, "#7A2A3A", 0.045)
		ctx.save()
		ctx.clip()
		ctx.fillStyle = "#FFFFFF"
		ctx.fillRect(-w, y - 0.08, w * 2, 0.1)
		ellipse(ctx, 0, y + 0.26, w * 0.55, 0.1)
		fill(ctx, "#E86A7A")
		ctx.restore()
	elif kind == "o":
		ellipse(ctx, 0, y + 0.04, w * 0.35, w * 0.45)
		inked(ctx, "#7A2A3A", 0.045)
	else:
		ctx.beginPath()
		var cur := 0.01 if kind == "line" else (0.06 if kind == "smirk" else 0.14)
		ctx.moveTo(-w, y - (-0.02 if kind == "smirk" else 0.0))
		ctx.quadraticCurveTo(0, y + cur, w, y - (0.07 if kind == "smirk" else 0.0))
		stroke(ctx, _or(lip, C.ink), 0.1 if lip else 0.055)

## Shoulders/torso silhouette path from the neck down past the frame.
static func torsoPath(ctx, wide: float = 1.0) -> void:
	ctx.beginPath()
	ctx.moveTo(-0.36, 0.95)
	ctx.bezierCurveTo(-0.9 * wide, 1.02, -1.5 * wide, 1.22, -1.6 * wide, 1.95)
	ctx.lineTo(-1.7 * wide, 2.9)
	ctx.lineTo(1.7 * wide, 2.9)
	ctx.lineTo(1.6 * wide, 1.95)
	ctx.bezierCurveTo(1.5 * wide, 1.22, 0.9 * wide, 1.02, 0.36, 0.95)
	ctx.closePath()

static func curl(ctx, x: float, y: float, r: float, col: String) -> void:
	circle(ctx, x, y, r)
	inked(ctx, col, LW * 0.9)
	ctx.beginPath()
	ctx.arc(x + r * 0.1, y + r * 0.05, r * 0.55, 0.3, 4.2)
	stroke(ctx, darken(col, 0.35), 0.035)

# Skip Kowalski: crew cap, curls, square glasses, blue shirt, headphones.
static func bustSkip(ctx, o: Dictionary) -> void:
	var skin: String = SKIN.skip
	var hair := "#6B3A1E"
	for s in [-1, 1]:
		for c in [[0.66, -0.5, 0.24], [0.86, -0.2, 0.26], [0.95, 0.12, 0.25], [0.86, 0.42, 0.22], [0.66, 0.58, 0.18]]:
			curl(ctx, s * c[0], c[1], c[2], hair)
	torsoPath(ctx, 0.95)
	inked(ctx, linear(ctx, 0, 1, 0, 2.6, [lighten(C.blue, 0.12), C.blue, darken(C.blue, 0.2)]), LW)
	poly(ctx, [-0.42, 0.98, 0.42, 0.98, 0.3, 2.9, -0.3, 2.9])
	inked(ctx, "#F7F4EC", LW)
	for s in [-1, 1]:
		poly(ctx, [s * 0.34, 0.95, s * 0.78, 1.08, s * 0.52, 1.62])
		inked(ctx, lighten(C.blue, 0.08), LW)
		circle(ctx, s * 0.36, 1.95 + (0.0 if s > 0 else 0.35), 0.05)
		inked(ctx, "#FFFFFF", 0.03)
	rr(ctx, 0.62, 1.62, 0.36, 0.5, 0.05)
	inked(ctx, "#FFFFFF", 0.035)
	ctx.fillStyle = C.blue; ctx.fillRect(0.66, 1.68, 0.28, 0.08)
	ctx.fillStyle = C.red; ctx.fillRect(0.66, 1.78, 0.28, 0.025)
	badge13(ctx, 0.8, 1.93, 0.09, {"ol": 0.015})
	neck(ctx, skin)
	# headphones round the neck
	ctx.beginPath()
	ctx.ellipse(0, 1.0, 0.62, 0.2, 0, 0.1, PI - 0.1)
	stroke(ctx, "#2C2632", 0.09)
	for s in [-1, 1]:
		ellipse(ctx, s * 0.6, 1.06, 0.17, 0.22, s * 0.3)
		inked(ctx, linear(ctx, 0, 0.85, 0, 1.3, ["#4A4452", "#221E2A"]), LW)
		ellipse(ctx, s * 0.6, 1.06, 0.09, 0.12, s * 0.3)
		fill(ctx, "#5E5868")
	ears(ctx, skin)
	faceBase(ctx, skin, 0.95)
	for c in [[-0.42, -0.62, 0.16], [-0.12, -0.7, 0.15], [0.2, -0.68, 0.15], [0.48, -0.6, 0.14]]:
		curl(ctx, c[0], c[1], c[2], hair)
	eyes(ctx, skin, {"iris": "#7A4520", "wink": o.get("wink"), "y": 0.08})
	brows(ctx, hair, -0.3, 0, 0.07)
	nose(ctx, skin, 0.33)
	mouth(ctx, _or(o.get("mouth"), "smile"), 0.6, 0.22)
	# square glasses
	for s in [-1, 1]:
		rr(ctx, s * 0.34 - 0.27, -0.16, 0.54, 0.46, 0.1)
		stroke(ctx, "#1E1824", 0.085)
	capsule(ctx, -0.08, -0.02, 0.08, -0.02, 0.06, "#1E1824")
	for s in [-1, 1]:
		capsule(ctx, s * 0.61, -0.06, s * 0.86, -0.1, 0.06, "#1E1824")
	# cap
	ctx.beginPath()
	ctx.moveTo(-0.98, -0.5)
	ctx.bezierCurveTo(-1.02, -1.7, 1.02, -1.7, 0.98, -0.5)
	ctx.closePath()
	inked(ctx, linear(ctx, 0, -1.45, 0, -0.5, [lighten(C.blue, 0.15), C.blue]), LW)
	ctx.beginPath()
	ctx.moveTo(-0.6, -0.52)
	ctx.bezierCurveTo(-0.62, -1.58, 0.62, -1.58, 0.6, -0.52)
	ctx.closePath()
	inked(ctx, linear(ctx, 0, -1.45, 0, -0.5, ["#FFFFFF", "#E8E2D4"]), LW * 0.8)
	circle(ctx, 0, -1.4, 0.08)
	inked(ctx, C.blue, 0.035)
	badge13(ctx, 0, -0.95, 0.3, {"disc": "#FFFFFF", "ring": C.red, "num": C.blue, "ol": 0.03})
	ctx.beginPath()
	ctx.ellipse(0, -0.5, 1.02, 0.2, 0, 0, TAU)
	inked(ctx, linear(ctx, 0, -0.7, 0, -0.3, [lighten(C.blue, 0.1), darken(C.blue, 0.25)]), LW)

# Roxy Rivers: huge afro, floral headband, gold hoops, flower-print crop shirt.
static func bustRoxy(ctx, o: Dictionary) -> void:
	var skin: String = SKIN.roxy
	var fro := "#3A2418"
	var r := rng(11)
	ellipse(ctx, 0, -0.42, 1.62, 1.5)
	inked(ctx, fro, LW)
	var bumps := []
	for i in 26:
		var a: float = (i / 26.0) * TAU + r.call() * 0.1
		var bx := cos(a) * 1.5
		var by := -0.42 + sin(a) * 1.38
		bumps.append([bx, by, 0.34 + r.call() * 0.1])
	for i in 16:
		var x0: float = (r.call() - 0.5) * 2.2
		var y0: float = -0.42 + (r.call() - 0.5) * 2.0
		bumps.append([x0, y0, 0.3 + r.call() * 0.08])
	for b in bumps:
		var x: float = b[0]
		var y: float = b[1]
		var br: float = b[2]
		circle(ctx, x, y, br)
		inked(ctx, radial(ctx, x - br * 0.35, y - br * 0.4, br * 0.1, br * 1.1, ["#6A4632", "#4A2F20", "#2E1A10"]), 0.03, "#24140C")
	torsoPath(ctx, 0.9)
	inked(ctx, linear(ctx, 0, 1, 0, 2.6, ["#FFFDF6", "#EDE4D0"]), LW)
	for p in [[-1.05, 1.6], [0.9, 1.45], [-0.6, 2.2], [1.25, 2.3], [0.5, 2.5]]:
		flower(ctx, p[0], p[1], 0.2, "#F08A1E", "#FFD23A")
	poly(ctx, [-0.34, 0.96, 0.34, 0.96, 0, 1.75])
	inked(ctx, darken(skin, 0.05), LW)
	for s in [-1, 1]:
		poly(ctx, [s * 0.3, 0.92, s * 0.95, 1.18, s * 0.46, 1.5, s * 0.12, 1.55])
		inked(ctx, "#FFFFFF", LW)
	neck(ctx, skin, 0.28)
	ears(ctx, skin)
	for s in [-1, 1]:
		circle(ctx, s * 0.92, 0.5, 0.2)
		stroke(ctx, C.ink, 0.1)
		circle(ctx, s * 0.92, 0.5, 0.2)
		stroke(ctx, "#F2C14E", 0.065)
	faceBase(ctx, skin, 0.9, 1, 0.18)
	eyes(ctx, skin, {"iris": "#5A3218", "lash": true, "wink": o.get("wink"), "rx": 0.2, "ry": 0.24})
	brows(ctx, "#24140C", -0.27, -0.02, 0.06, 0.34, 0.2, 0.08)
	nose(ctx, skin, 0.32, 0.11)
	ctx.beginPath()
	ctx.moveTo(-0.22, 0.56)
	ctx.quadraticCurveTo(0, 0.74, 0.22, 0.56)
	ctx.quadraticCurveTo(0, 0.62, -0.22, 0.56)
	inked(ctx, "#D9543A", 0.035)
	# floral headband
	ctx.beginPath()
	ctx.moveTo(-0.95, -0.42)
	ctx.bezierCurveTo(-0.7, -1.02, 0.7, -1.02, 0.95, -0.42)
	ctx.lineCap = "round"
	stroke(ctx, C.ink, 0.3)
	stroke(ctx, "#F0801E", 0.22)
	for p in [[-0.62, -0.72], [-0.2, -0.86], [0.24, -0.86], [0.64, -0.7]]:
		flower(ctx, p[0], p[1], 0.1, "#FFD23A", "#E3462B")

static func flower(ctx, x: float, y: float, r: float, petal: String, center: String) -> void:
	ctx.beginPath()
	for i in 5:
		var a := (i / 5.0) * TAU
		ctx.moveTo(x + cos(a) * r * 0.55 + r * 0.45, y + sin(a) * r * 0.55)
		ctx.arc(x + cos(a) * r * 0.55, y + sin(a) * r * 0.55, r * 0.45, 0, TAU)
	inked(ctx, petal, r * 0.12)
	circle(ctx, x, y, r * 0.3)
	fill(ctx, center)

# Penny Watts: long wavy hair, orange headband, round glasses, ribbed turtleneck, medallion.
static func bustPenny(ctx, o: Dictionary) -> void:
	var skin: String = SKIN.penny
	var hair := "#5A3320"
	ctx.beginPath()
	ctx.moveTo(0, -1.2)
	ctx.bezierCurveTo(1.2, -1.2, 1.25, 0, 1.2, 0.8)
	ctx.bezierCurveTo(1.35, 1.3, 1.1, 1.8, 1.25, 2.3)
	ctx.lineTo(-1.25, 2.3)
	ctx.bezierCurveTo(-1.1, 1.8, -1.35, 1.3, -1.2, 0.8)
	ctx.bezierCurveTo(-1.25, 0, -1.2, -1.2, 0, -1.2)
	inked(ctx, linear(ctx, 0, -1.2, 0, 2.3, [lighten(hair, 0.12), hair, darken(hair, 0.2)]), LW)
	torsoPath(ctx, 0.9)
	inked(ctx, linear(ctx, 0, 1, 0, 2.6, ["#FF7A32", "#F0641E", "#C84E14"]), LW)
	ctx.strokeStyle = alpha("#9A3A0E", 0.35)
	ctx.lineWidth = 0.025
	ctx.beginPath()
	var x := -1.5
	while x <= 1.5:
		ctx.moveTo(x, 1.35)
		ctx.lineTo(x * 1.05, 2.9)
		x += 0.1
	ctx.stroke()
	# front locks over the shoulders
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(s * 0.7, 0.2)
		ctx.bezierCurveTo(s * 1.25, 0.9, s * 0.85, 1.4, s * 1.18, 2.1)
		ctx.bezierCurveTo(s * 0.95, 1.9, s * 1.0, 1.7, s * 0.9, 1.5)
		ctx.bezierCurveTo(s * 0.6, 1.1, s * 0.75, 0.7, s * 0.6, 0.35)
		inked(ctx, hair, LW)
	neck(ctx, skin, 0.27)
	rr(ctx, -0.42, 0.9, 0.84, 0.36, 0.16)
	inked(ctx, linear(ctx, 0, 0.9, 0, 1.26, ["#FF8A42", "#E0561A"]), LW)
	ctx.beginPath()
	ctx.moveTo(-0.3, 1.2)
	ctx.quadraticCurveTo(0, 1.9, 0.3, 1.2)
	stroke(ctx, "#C9961E", 0.03)
	circle(ctx, 0, 1.88, 0.14)
	inked(ctx, radial(ctx, -0.04, 1.84, 0.01, 0.16, ["#FFE9A0", "#E8B030", "#B07A16"]), 0.03)
	ears(ctx, skin)
	for s in [-1, 1]:
		circle(ctx, s * 0.9, 0.46, 0.16)
		stroke(ctx, C.ink, 0.09)
		circle(ctx, s * 0.9, 0.46, 0.16)
		stroke(ctx, "#F2C14E", 0.055)
	faceBase(ctx, skin, 0.88)
	eyes(ctx, skin, {"iris": "#6A3A1C", "lash": true, "wink": o.get("wink")})
	brows(ctx, hair, -0.3, 0, 0.06, 0.34, 0.18, 0.05)
	nose(ctx, skin, 0.33, 0.09)
	mouth(ctx, "smile", 0.6, 0.18, "#D9605A")
	for s in [-1, 1]:
		circle(ctx, s * 0.34, 0.06, 0.28)
		stroke(ctx, "#1E1824", 0.075)
	capsule(ctx, -0.07, 0.02, 0.07, 0.02, 0.05, "#1E1824")
	# side-swept fringe + headband
	ctx.beginPath()
	ctx.moveTo(-0.92, -0.2)
	ctx.bezierCurveTo(-1.0, -1.1, 0.4, -1.3, 0.92, -0.5)
	ctx.bezierCurveTo(0.5, -0.72, 0.0, -0.66, -0.35, -0.42)
	ctx.bezierCurveTo(-0.6, -0.3, -0.75, -0.2, -0.92, -0.2)
	inked(ctx, linear(ctx, -0.9, -1.1, 0.8, -0.3, [lighten(hair, 0.18), hair]), LW)
	ctx.beginPath()
	ctx.moveTo(-0.88, -0.62)
	ctx.bezierCurveTo(-0.6, -1.18, 0.6, -1.18, 0.88, -0.62)
	ctx.lineCap = "round"
	stroke(ctx, C.ink, 0.22)
	stroke(ctx, "#F57A1E", 0.15)

## Duke Dalton: feathered hair, chevron mustache, orange aviators, big collar.
## o: { wink, hat: 'cowboy'|'beret'|'headband'|null, outfit: 'disco'|'western'|'tux'|'camo'|'leather' }
static func bustDuke(ctx, o: Dictionary) -> void:
	var skin: String = SKIN.duke
	var hair := "#6B3A1E"
	var outfit: String = _or(o.get("outfit"), "disco")
	# hair mass behind head
	ctx.beginPath()
	ctx.moveTo(-0.95, 0.35)
	ctx.bezierCurveTo(-1.35, 0.1, -1.3, -0.5, -1.05, -0.85)
	ctx.bezierCurveTo(-0.8, -1.45, 0.8, -1.45, 1.05, -0.85)
	ctx.bezierCurveTo(1.3, -0.5, 1.35, 0.1, 0.95, 0.35)
	ctx.closePath()
	inked(ctx, linear(ctx, 0, -1.4, 0, 0.4, [lighten(hair, 0.2), hair, darken(hair, 0.15)]), LW)
	for s in [-1, 1]:
		for yl in [[-0.3, 0.42], [0.0, 0.46], [0.25, 0.38]]:
			var y: float = yl[0]
			var ln: float = yl[1]
			ctx.beginPath()
			ctx.moveTo(s * 0.9, y - 0.1)
			ctx.quadraticCurveTo(s * (1.1 + ln * 0.3), y - 0.05, s * (0.95 + ln * 0.55), y + 0.18)
			ctx.quadraticCurveTo(s * 1.05, y + 0.08, s * 0.9, y + 0.12)
			inked(ctx, lighten(hair, 0.08), LW * 0.8)
	torsoPath(ctx, 1.05)
	if outfit == "tux":
		inked(ctx, linear(ctx, 0, 1, 0, 2.6, ["#2E3150", "#1A1A2E"]), LW)
		poly(ctx, [-0.36, 0.96, 0.36, 0.96, 0.1, 2.9, -0.1, 2.9])
		inked(ctx, "#FFFFFF", LW)
		for s in [-1, 1]:
			poly(ctx, [s * 0.36, 0.96, s * 0.95, 1.2, s * 0.2, 2.2])
			inked(ctx, "#3A3E62", LW)
		poly(ctx, [0, 1.12, -0.3, 0.98, -0.3, 1.28])
		inked(ctx, "#1A1A2E", 0.03)
		poly(ctx, [0, 1.12, 0.3, 0.98, 0.3, 1.28])
		inked(ctx, "#1A1A2E", 0.03)
	elif outfit == "camo":
		inked(ctx, "#6E7A3A", LW)
		ctx.save()
		torsoPath(ctx, 1.05)
		ctx.clip()
		var r := rng(5)
		for i in 40:
			var ex: float = (r.call() - 0.5) * 3.4
			var ey: float = 0.9 + r.call() * 2
			var erx: float = 0.2 + r.call() * 0.2
			var ery: float = 0.1 + r.call() * 0.12
			var erot: float = r.call() * 3
			ellipse(ctx, ex, ey, erx, ery, erot)
			fill(ctx, ["#4A5A2A", "#8C8A4A", "#3A3020"][i % 3])
		ctx.restore()
		ctx.beginPath()
		ctx.moveTo(-0.3, 1.0)
		ctx.quadraticCurveTo(0, 1.8, 0.3, 1.0)
		stroke(ctx, "#C9CED8", 0.03)
		rr(ctx, -0.1, 1.72, 0.2, 0.28, 0.05)
		inked(ctx, "#D8DCE6", 0.03)
	elif outfit == "leather":
		inked(ctx, linear(ctx, 0, 1, 0, 2.6, ["#9A5A30", "#6A3A1C"]), LW)
		poly(ctx, [-0.36, 0.96, 0.36, 0.96, 0.22, 2.9, -0.22, 2.9])
		inked(ctx, "#F7C531", LW)
		for s in [-1, 1]:
			poly(ctx, [s * 0.34, 0.96, s * 1.0, 1.15, s * 0.45, 2.1])
			inked(ctx, "#8A4E28", LW)
	else:
		inked(ctx, "#F7C531", LW)
		ctx.save()
		torsoPath(ctx, 1.05)
		ctx.clip()
		var cols := ["#F07A1E", "#F7C531", "#F6E7C8", "#F7C531"]
		for i in range(-10, 10):
			ctx.fillStyle = cols[(i + 20) % 4]
			ctx.fillRect(i * 0.18, 0.9, 0.18, 2.2)
		ctx.restore()
		torsoPath(ctx, 1.05)
		stroke(ctx, C.ink, LW)
		poly(ctx, [-0.3, 0.96, 0.3, 0.96, 0, 1.55])
		inked(ctx, darken(skin, 0.06), LW)
		ctx.fillStyle = "#4A2A18"
		for i in 7:
			circle(ctx, (i % 3 - 1) * 0.06, 1.18 + i * 0.04, 0.035)
			ctx.fill()
		for s in [-1, 1]:
			poly(ctx, [s * 0.28, 0.92, s * 1.15, 1.3, s * 0.62, 1.52, s * 0.12, 1.45])
			inked(ctx, "#FFD23A", LW)
	if outfit == "western":
		inked(ctx, "#C0763A", LW)
		ctx.beginPath()
		ctx.moveTo(-0.5, 0.98)
		ctx.quadraticCurveTo(0, 1.25, 0.5, 0.98)
		ctx.lineTo(0.12, 1.55)
		ctx.lineTo(0, 1.35)
		ctx.lineTo(-0.12, 1.55)
		ctx.closePath()
		inked(ctx, "#D8322B", LW)
		halftoneDots(ctx, -0.4, 1.0, 0.8, 0.4, "#FFFFFF")
	neck(ctx, skin, 0.3)
	ears(ctx, skin)
	faceBase(ctx, skin, 1.0, 1.04, 0.14)
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(s * 0.9, -0.4)
		ctx.lineTo(s * 0.9, 0.42)
		ctx.quadraticCurveTo(s * 0.8, 0.46, s * 0.74, 0.36)
		ctx.lineTo(s * 0.74, -0.4)
		inked(ctx, darken(hair, 0.1), LW * 0.8)
	eyes(ctx, skin, {"iris": "#5A3218", "wink": o.get("wink"), "y": 0.08, "rx": 0.17, "ry": 0.2})
	brows(ctx, darken(hair, 0.2), -0.24, 0.07, 0.1, 0.34, 0.2, -0.02)
	nose(ctx, skin, 0.32, 0.11)
	mouth(ctx, "smirk", 0.74, 0.16)
	# chevron mustache
	ctx.beginPath()
	ctx.moveTo(0, 0.42)
	ctx.bezierCurveTo(0.22, 0.38, 0.42, 0.46, 0.46, 0.68)
	ctx.bezierCurveTo(0.3, 0.6, 0.16, 0.6, 0, 0.62)
	ctx.bezierCurveTo(-0.16, 0.6, -0.3, 0.6, -0.46, 0.68)
	ctx.bezierCurveTo(-0.42, 0.46, -0.22, 0.38, 0, 0.42)
	inked(ctx, linear(ctx, 0, 0.4, 0, 0.7, ["#5A3220", "#3A2014"]), LW * 0.8)
	# aviators
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(s * 0.08, -0.08)
		ctx.lineTo(s * 0.62, -0.1)
		ctx.bezierCurveTo(s * 0.66, 0.12, s * 0.58, 0.34, s * 0.38, 0.34)
		ctx.bezierCurveTo(s * 0.14, 0.34, s * 0.06, 0.12, s * 0.08, -0.08)
		ctx.fillStyle = linear(ctx, 0, -0.1, 0, 0.34, ["rgba(255,110,40,0.72)", "rgba(255,150,60,0.55)"])
		ctx.fill()
		stroke(ctx, "#C99A2E", 0.04)
		ctx.beginPath()
		ctx.moveTo(s * 0.2, -0.02)
		ctx.lineTo(s * 0.34, 0.12)
		stroke(ctx, "rgba(255,255,255,0.55)", 0.035)
	capsule(ctx, -0.09, -0.06, 0.09, -0.06, 0.035, "#C99A2E")
	for s in [-1, 1]:
		capsule(ctx, s * 0.62, -0.08, s * 0.88, -0.1, 0.035, "#C99A2E")
	# front hair: feathered crown (or the costume hat)
	if o.get("hat") == "cowboy":
		ellipse(ctx, 0, -0.62, 1.55, 0.26, 0)
		inked(ctx, linear(ctx, 0, -0.85, 0, -0.4, ["#C58A4E", "#8A5528"]), LW)
		ctx.beginPath()
		ctx.moveTo(-0.7, -0.66)
		ctx.bezierCurveTo(-0.8, -1.5, -0.3, -1.62, 0, -1.4)
		ctx.bezierCurveTo(0.3, -1.62, 0.8, -1.5, 0.7, -0.66)
		ctx.closePath()
		inked(ctx, linear(ctx, 0, -1.6, 0, -0.66, ["#D69A5C", "#A8693A"]), LW)
		ctx.fillStyle = "#5A3220"
		ctx.fillRect(-0.71, -0.86, 1.42, 0.14)
		ctx.beginPath()
		ctx.moveTo(-0.3, -1.52)
		ctx.quadraticCurveTo(0, -1.25, 0.3, -1.52)
		stroke(ctx, darken("#A8693A", 0.2), 0.04)
	else:
		ctx.beginPath()
		ctx.moveTo(-0.92, -0.3)
		ctx.bezierCurveTo(-1.0, -1.2, -0.3, -1.45, 0.1, -1.3)
		ctx.bezierCurveTo(0.7, -1.35, 1.05, -0.95, 0.92, -0.3)
		ctx.bezierCurveTo(0.7, -0.65, 0.3, -0.72, 0.05, -0.62)
		ctx.bezierCurveTo(-0.35, -0.72, -0.72, -0.62, -0.92, -0.3)
		inked(ctx, linear(ctx, 0, -1.4, 0, -0.4, [lighten(hair, 0.25), hair]), LW)
		ctx.strokeStyle = lighten(hair, 0.35)
		ctx.lineWidth = 0.035
		ctx.beginPath()
		for s in [-1, 1]:
			for k in 3:
				ctx.moveTo(s * 0.1, -1.18 + k * 0.1)
				ctx.quadraticCurveTo(s * 0.55, -1.2 + k * 0.12, s * 0.82, -0.62 + k * 0.08)
		ctx.stroke()
		if o.get("hat") == "headband":
			ctx.beginPath()
			ctx.moveTo(-0.95, -0.42)
			ctx.bezierCurveTo(-0.6, -0.72, 0.6, -0.72, 0.95, -0.42)
			ctx.lineCap = "round"
			stroke(ctx, C.ink, 0.24)
			stroke(ctx, "#D8322B", 0.17)
			capsule(ctx, 0.95, -0.42, 1.35, -0.1, 0.1, "#D8322B", C.ink, 0.03)
			capsule(ctx, 0.95, -0.42, 1.3, -0.5, 0.1, "#D8322B", C.ink, 0.03)
		elif o.get("hat") == "beret":
			ellipse(ctx, 0.2, -1.08, 1.0, 0.38, -0.15)
			inked(ctx, "#2F5A3A", LW)
			circle(ctx, -0.35, -1.0, 0.13)
			inked(ctx, C.gold, 0.03)

static func halftoneDots(ctx, x: float, y: float, w: float, h: float, col: String) -> void:
	ctx.fillStyle = col
	ctx.beginPath()
	for j in 4:
		for i in 8:
			var px := x + (i + (j & 1) * 0.5) * (w / 8)
			var py := y + j * (h / 4)
			ctx.moveTo(px + 0.03, py)
			ctx.arc(px, py, 0.03, 0, TAU)
	ctx.fill()

## Baron Von Static's face (unit space). mood: grin | laugh | angry | frantic | goodnight. m = mouth open 0..1.
static func baronFace(ctx, mood: String = "grin", t: float = 0.0, m: float = 0.4) -> void:
	var skin: String = SKIN.baron
	var frantic := mood == "frantic"
	var angry := mood == "angry"
	var night := mood == "goodnight"
	ears(ctx, skin, 0.05, true)
	faceBase(ctx, skin, 0.62, 1.12, 0.3 if angry else 0.18)
	# under-eye plum shadows
	for s in [-1, 1]:
		ellipse(ctx, s * 0.33, 0.28, 0.2, 0.08)
		fill(ctx, alpha("#7A5C8E", 0.45))
	# slick hair with widow's peak and a silver streak
	ctx.beginPath()
	ctx.moveTo(-0.9, -0.05)
	ctx.bezierCurveTo(-1.0, -0.9, -0.55, -1.18, 0, -1.16)
	ctx.bezierCurveTo(0.55, -1.18, 1.0, -0.9, 0.9, -0.05)
	ctx.bezierCurveTo(0.82, -0.42, 0.6, -0.58, 0.32, -0.62)
	ctx.lineTo(0, -0.34)
	ctx.lineTo(-0.32, -0.62)
	ctx.bezierCurveTo(-0.6, -0.58, -0.82, -0.42, -0.9, -0.05)
	inked(ctx, linear(ctx, 0, -1.2, 0, -0.3, ["#3E3458", "#1E1830"]), LW)
	ctx.beginPath()
	ctx.moveTo(0.22, -1.12)
	ctx.bezierCurveTo(0.5, -1.0, 0.62, -0.8, 0.6, -0.58)
	ctx.lineTo(0.46, -0.6)
	ctx.bezierCurveTo(0.45, -0.8, 0.35, -0.98, 0.12, -1.1)
	fill(ctx, "#D8D4E8")
	if frantic:
		for e in [[-0.5, -1.1, -0.6], [0.1, -1.2, 0.2], [0.6, -1.05, 0.7]]:
			var x: float = e[0]
			var y: float = e[1]
			var a: float = e[2]
			capsule(ctx, x, y, x + sin(a) * 0.3, y - cos(a) * 0.3, 0.08, "#2A2240", C.ink, 0.02)
	# brows
	var bt := 0.16 if angry else (-0.12 if night else (-0.1 if frantic else 0.08))
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(s * 0.12, -0.22 + bt)
		ctx.quadraticCurveTo(s * 0.35, -0.38 - (-0.06 if night else 0.08), s * 0.62, -0.34 - bt * 0.6)
		ctx.lineCap = "round"
		stroke(ctx, "#1E1830", 0.13)
	# eyes
	var shake := sin(t * 60) * 0.02 if frantic else 0.0
	if night:
		for s in [-1, 1]:
			ellipse(ctx, s * 0.33, 0.06, 0.2, 0.22)
			inked(ctx, "#FFFDF6", 0.04)
			circle(ctx, s * 0.33, 0.1, 0.16)
			fill(ctx, "#3A2A5A")
			circle(ctx, s * 0.33 + 0.06, 0.03, 0.06)
			fill(ctx, "#FFFFFF")
			circle(ctx, s * 0.33 - 0.06, 0.15, 0.03)
			fill(ctx, "#FFFFFF")
			ctx.beginPath()
			ctx.moveTo(s * 0.4, 0.26)
			ctx.quadraticCurveTo(s * 0.48, 0.5, s * 0.38, 0.6)
			ctx.quadraticCurveTo(s * 0.3, 0.5, s * 0.4, 0.26)
			fill(ctx, alpha("#8FE3FF", 0.9))
	else:
		var laughSquint := 0.35 + m * 0.3 if mood == "laugh" else 0.0
		for s in [-1, 1]:
			var big := (1.25 if s < 0 else 0.95) if frantic else 1.0
			var ex := s * 0.33 + shake
			var ey := 0.07
			ellipse(ctx, ex, ey, 0.17 * big, (0.13 if angry else 0.19) * big)
			inked(ctx, "#FFF1D0" if angry else "#FFFDF6", 0.04)
			circle(ctx, ex + 0.02, ey + 0.02, (0.04 if frantic else 0.09) * big)
			fill(ctx, "#E0203A" if angry else "#C0284A")
			circle(ctx, ex + 0.02, ey + 0.02, (0.02 if frantic else 0.045) * big)
			fill(ctx, "#1E1428")
			if laughSquint:
				ctx.save()
				ellipse(ctx, ex, ey, 0.18, 0.2)
				ctx.clip()
				ellipse(ctx, ex, ey + 0.3, 0.3, laughSquint)
				fill(ctx, skin)
				ctx.restore()
			if angry:
				ctx.save()
				ellipse(ctx, ex, ey, 0.18, 0.14)
				ctx.clip()
				poly(ctx, [ex - s * 0.2, ey - 0.2, ex + s * 0.2, ey - 0.2, ex + s * 0.2, ey + 0.03])
				fill(ctx, skin)
				ctx.restore()
	# monocle on his left eye (viewer right)
	var mx := 0.33 + shake
	var my := 0.07
	if frantic:
		var sw := sin(t * 7) * 0.4
		ctx.beginPath()
		ctx.moveTo(0.6, 0.2)
		ctx.quadraticCurveTo(0.7, 0.7, 0.55 + sw * 0.3, 1.0)
		stroke(ctx, C.brass, 0.025)
		circle(ctx, 0.55 + sw * 0.3, 1.1, 0.14)
		stroke(ctx, C.ink, 0.07)
		stroke(ctx, C.brass, 0.04)
	else:
		circle(ctx, mx, my, 0.26)
		ctx.fillStyle = "rgba(200,240,255,0.18)"
		ctx.fill()
		stroke(ctx, C.ink, 0.085)
		stroke(ctx, C.brass, 0.05)
		ctx.beginPath()
		ctx.arc(mx, my, 0.18, -2.4, -1.6)
		stroke(ctx, "rgba(255,255,255,0.7)", 0.03)
		ctx.beginPath()
		ctx.moveTo(mx + 0.2, my + 0.18)
		ctx.quadraticCurveTo(0.75, 0.8, 0.55, 1.25)
		stroke(ctx, C.brass, 0.022)
	# long nose
	ctx.beginPath()
	ctx.moveTo(-0.05, 0.02)
	ctx.quadraticCurveTo(0.02, 0.3, 0.12, 0.42)
	ctx.quadraticCurveTo(0.02, 0.48, -0.08, 0.42)
	inked(ctx, darken(skin, 0.1), 0.04)
	# mouth
	var my0 := 0.62
	if night:
		ctx.beginPath()
		ctx.moveTo(-0.2, my0)
		ctx.bezierCurveTo(-0.1, my0 + 0.06, 0.1, my0 + 0.06, 0.2, my0)
		stroke(ctx, C.ink, 0.05)
		poly(ctx, [-0.12, my0 + 0.03, -0.06, my0 + 0.035, -0.09, my0 + 0.12])
		inked(ctx, "#FFFFFF", 0.02)
		poly(ctx, [0.12, my0 + 0.03, 0.06, my0 + 0.035, 0.09, my0 + 0.12])
		inked(ctx, "#FFFFFF", 0.02)
	elif frantic:
		ctx.beginPath()
		ctx.moveTo(-0.32, my0)
		for i in range(1, 9):
			ctx.lineTo(-0.32 + i * 0.08, my0 + (0.08 if (i & 1) else -0.02) + sin(t * 30 + i) * 0.02)
		ctx.lineTo(0.3, my0 + 0.3)
		ctx.lineTo(-0.3, my0 + 0.3)
		ctx.closePath()
		inked(ctx, "#3B2340", 0.045)
		for s in [-1, 1]:
			poly(ctx, [s * 0.2, my0 + 0.02, s * 0.12, my0 + 0.02, s * 0.16, my0 + 0.16])
			inked(ctx, "#FFFFFF", 0.02)
	else:
		var open := 0.12 if angry else 0.06 + m * 0.34
		var w := 0.36 if angry else 0.42
		ctx.beginPath()
		ctx.moveTo(-w, my0 - 0.06)
		ctx.quadraticCurveTo(0, my0 + 0.08, w, my0 - 0.06)
		ctx.quadraticCurveTo(w * 0.7, my0 + open + 0.08, 0, my0 + open + 0.1)
		ctx.quadraticCurveTo(-w * 0.7, my0 + open + 0.08, -w, my0 - 0.06)
		inked(ctx, "#3B2340", 0.05)
		ctx.save()
		ctx.clip()
		ctx.fillStyle = "#FFFFFF"
		ctx.beginPath()
		ctx.moveTo(-w, my0 - 0.1)
		ctx.quadraticCurveTo(0, my0 + 0.12, w, my0 - 0.1)
		ctx.lineTo(w, my0 - 0.2)
		ctx.lineTo(-w, my0 - 0.2)
		ctx.fill()
		if open > 0.15:
			ellipse(ctx, 0, my0 + open + 0.08, w * 0.5, 0.1)
			fill(ctx, "#E0507A")
		if angry:
			ctx.fillStyle = "#FFFFFF"
			ctx.fillRect(-w, my0 + 0.08, w * 2, 0.1)
		ctx.restore()
		for s in [-1, 1]:
			poly(ctx, [s * 0.24, my0 - 0.01, s * 0.12, my0 + 0.02, s * 0.19, my0 + 0.2])
			inked(ctx, "#FFFFFF", 0.025)
	if angry:
		for s in [-1, 1]:
			ctx.beginPath()
			ctx.moveTo(s * 0.66, -0.7)
			ctx.lineTo(s * 0.74, -0.62)
			ctx.moveTo(s * 0.8, -0.72)
			ctx.lineTo(s * 0.72, -0.64)
			stroke(ctx, C.red, 0.05)
	if frantic:
		for p in [[-0.95, -0.3], [0.98, -0.1], [-0.9, 0.4]]:
			var x2: float = p[0]
			var y2: float = p[1]
			ctx.beginPath()
			var yy := y2 + fract(t * 2 + x2) * 0.2
			ctx.moveTo(x2, yy - 0.12)
			ctx.quadraticCurveTo(x2 - 0.08, yy + 0.02, x2, yy + 0.06)
			ctx.quadraticCurveTo(x2 + 0.08, yy + 0.02, x2, yy - 0.12)
			inked(ctx, "#9FE6FF", 0.02)

## Baron bust with cape collar, tux, jabot and medallion.
static func bustBaron(ctx, o: Dictionary) -> void:
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(s * 0.35, 0.95)
		ctx.lineTo(s * 1.55, -1.25)
		ctx.quadraticCurveTo(s * 1.6, 0.2, s * 1.7, 1.2)
		ctx.closePath()
		inked(ctx, linear(ctx, 0, -1.2, 0, 1.2, ["#C0283E", "#7A1428"]), LW)
		ctx.beginPath()
		ctx.moveTo(s * 1.55, -1.25)
		ctx.quadraticCurveTo(s * 1.9, 0.2, s * 1.85, 1.3)
		ctx.lineTo(s * 1.7, 1.2)
		ctx.quadraticCurveTo(s * 1.6, 0.2, s * 1.55, -1.25)
		inked(ctx, "#1E1830", LW)
	torsoPath(ctx, 1.05)
	inked(ctx, linear(ctx, 0, 1, 0, 2.6, ["#2E2E4E", "#1A1A2E"]), LW)
	for s in [-1, 1]:
		poly(ctx, [s * 0.3, 0.98, s * 1.0, 1.25, s * 0.28, 2.3])
		inked(ctx, C.plum, LW)
	poly(ctx, [-0.3, 0.98, 0.3, 0.98, 0.16, 2.3, -0.16, 2.3])
	inked(ctx, "#FFFFFF", LW)
	for i in 4:
		var y := 1.12 + i * 0.2
		ctx.beginPath()
		ctx.ellipse(0, y, 0.3 - i * 0.03, 0.1, 0, 0, PI)
		inked(ctx, "#FFFFFF", 0.03)
	ctx.beginPath()
	ctx.moveTo(-0.45, 1.05)
	ctx.quadraticCurveTo(0, 1.8, 0.45, 1.05)
	stroke(ctx, C.brass, 0.035)
	circle(ctx, 0, 1.9, 0.22)
	inked(ctx, radial(ctx, -0.06, 1.84, 0.02, 0.24, ["#FFF0A8", "#E8B030", "#A87010"]), 0.03)
	uText(ctx, "13", 0, 1.91, 0.2, FONT.round, "#7A4A10")
	neck(ctx, SKIN.baron, 0.24)
	baronFace(ctx, _or(o.get("mood"), "grin"), _or(o.get("t"), 0.0), _nn(o.get("m"), 0.35))

## "Stormy Stu" the weatherman: pompadour, giant grin, loud checked sport coat.
static func bustStu(ctx, _o: Dictionary = {}) -> void:
	var skin: String = SKIN.stu
	var hair := "#4A2A1A"
	torsoPath(ctx, 1.05)
	inked(ctx, "#D9602B", LW)
	ctx.save()
	torsoPath(ctx, 1.05)
	ctx.clip()
	for j in 12:
		for i in range(-10, 10):
			if (i + j) & 1:
				continue
			ctx.fillStyle = "rgba(90,40,20,0.55)"
			ctx.fillRect(i * 0.22, 0.9 + j * 0.22, 0.22, 0.22)
	ctx.strokeStyle = "rgba(246,231,200,0.7)"
	ctx.lineWidth = 0.025
	ctx.beginPath()
	for i in range(-10, 10):
		ctx.moveTo(i * 0.44 + 0.11, 0.9)
		ctx.lineTo(i * 0.44 + 0.11, 3)
	for j in 6:
		ctx.moveTo(-2, 1.01 + j * 0.44)
		ctx.lineTo(2, 1.01 + j * 0.44)
	ctx.stroke()
	ctx.restore()
	poly(ctx, [-0.34, 0.97, 0.34, 0.97, 0.16, 2.9, -0.16, 2.9])
	inked(ctx, C.cream, LW)
	poly(ctx, [-0.1, 1.05, 0.1, 1.05, 0.2, 2.2, 0, 2.4, -0.2, 2.2])
	inked(ctx, C.mustard, LW)
	for s in [-1, 1]:
		poly(ctx, [s * 0.34, 0.97, s * 1.25, 1.3, s * 0.8, 1.6, s * 0.2, 2.4])
		inked(ctx, "#C0501E", LW)
	circle(ctx, 0.9, 1.75, 0.14)
	inked(ctx, "#FFD23A", 0.03)
	neck(ctx, skin, 0.3)
	ears(ctx, skin)
	faceBase(ctx, skin, 1.0, 1.02, 0.3)
	eyes(ctx, skin, {"iris": "#3A6AA8", "y": 0.02, "rx": 0.17, "ry": 0.21})
	brows(ctx, hair, -0.33, -0.04, 0.09, 0.34, 0.2, 0.08)
	nose(ctx, skin, 0.3, 0.12)
	ctx.beginPath()
	ctx.moveTo(-0.5, 0.42)
	ctx.quadraticCurveTo(0, 0.56, 0.5, 0.42)
	ctx.quadraticCurveTo(0.42, 0.9, 0, 0.9)
	ctx.quadraticCurveTo(-0.42, 0.9, -0.5, 0.42)
	inked(ctx, "#7A2A3A", 0.05)
	ctx.save()
	ctx.clip()
	ctx.fillStyle = "#FFFFFF"
	ctx.fillRect(-0.6, 0.38, 1.2, 0.2)
	ctx.fillRect(-0.6, 0.74, 1.2, 0.2)
	ctx.strokeStyle = "#D8D0E0"
	ctx.lineWidth = 0.02
	ctx.beginPath()
	var x := -0.4
	while x <= 0.4:
		ctx.moveTo(x, 0.4)
		ctx.lineTo(x, 0.58)
		ctx.moveTo(x + 0.05, 0.74)
		ctx.lineTo(x + 0.05, 0.92)
		x += 0.1
	ctx.stroke()
	ctx.restore()
	# pompadour
	ctx.beginPath()
	ctx.moveTo(-0.92, -0.2)
	ctx.bezierCurveTo(-1.05, -1.1, -0.5, -1.5, 0.1, -1.55)
	ctx.bezierCurveTo(0.9, -1.75, 1.35, -1.2, 0.95, -0.9)
	ctx.bezierCurveTo(1.05, -0.6, 0.95, -0.4, 0.92, -0.2)
	ctx.bezierCurveTo(0.7, -0.7, 0.2, -0.75, -0.1, -0.7)
	ctx.bezierCurveTo(-0.5, -0.66, -0.8, -0.5, -0.92, -0.2)
	inked(ctx, linear(ctx, 0, -1.7, 0, -0.3, [lighten(hair, 0.35), hair]), LW)
	ctx.beginPath()
	ctx.moveTo(-0.5, -1.2)
	ctx.bezierCurveTo(0, -1.5, 0.7, -1.55, 1.05, -1.12)
	stroke(ctx, "rgba(255,255,255,0.45)", 0.05)

## Draws a bust at (cx, cy) (face centre) with head radius s. who: hero id | 'baron' | 'stu'.
static func drawBust(ctx, who: String, cx: float, cy: float, s: float, o: Dictionary = {}) -> void:
	ctx.save()
	ctx.translate(cx, cy)
	ctx.scale(s, s)
	ctx.lineJoin = "round"
	ctx.lineCap = "round"
	match who:
		"skip": bustSkip(ctx, o)
		"roxy": bustRoxy(ctx, o)
		"penny": bustPenny(ctx, o)
		"duke": bustDuke(ctx, o)
		"baron": bustBaron(ctx, o)
		"stu": bustStu(ctx, o)
	ctx.restore()

# ---------------------------------------------------------------------------------------------------------
# Hootie the owl (kids' show host)
# ---------------------------------------------------------------------------------------------------------

## Hootie at (cx, cy) = body centre, s = body half-height. o: { t, wave, blink }
static func drawHootie(ctx, cx: float, cy: float, s: float, o: Dictionary = {}) -> void:
	var t: float = _or(o.get("t"), 0.0)
	ctx.save()
	ctx.translate(cx, cy)
	ctx.scale(s, s)
	ctx.lineJoin = "round"
	ctx.lineCap = "round"
	var brown := "#8A5A3C"
	var dark := "#5E3A24"
	var belly := "#E9CFA0"
	for sx in [-1, 1]:
		ellipse(ctx, sx * 0.3, 1.02, 0.2, 0.09)
		inked(ctx, "#F0A032", LW)
	# wings (right one may wave)
	var wave: float = _nn(o.get("wave"), 0.0)
	for sx in [-1, 1]:
		ctx.save()
		ctx.translate(sx * 0.72, 0.05)
		ctx.rotate(sx * (0.25 + (wave if sx > 0 else 0.0)))
		ellipse(ctx, sx * 0.12, 0.3, 0.26, 0.55)
		inked(ctx, linear(ctx, 0, -0.2, 0, 0.9, [brown, dark]), LW)
		ctx.strokeStyle = alpha(darken(dark, 0.3), 0.6)
		ctx.lineWidth = 0.035
		for k in 3:
			ctx.beginPath()
			ctx.arc(sx * 0.12, 0.45 + k * 0.16, 0.18, 0.4, 2.7)
			ctx.stroke()
		ctx.restore()
	# ear tufts + body
	for sx in [-1, 1]:
		poly(ctx, [sx * 0.34, -0.72, sx * 0.72, -1.22, sx * 0.72, -0.55])
		inked(ctx, dark, LW)
	ctx.beginPath()
	ctx.ellipse(0, 0.05, 0.8, 0.98, 0, 0, TAU)
	inked(ctx, radial(ctx, -0.2, -0.3, 0.1, 1.1, [lighten(brown, 0.15), brown, dark]), LW)
	ctx.save()
	ellipse(ctx, 0, 0.42, 0.52, 0.55)
	inked(ctx, belly, LW * 0.8)
	ctx.clip()
	ctx.strokeStyle = alpha("#B88A58", 0.8)
	ctx.lineWidth = 0.03
	for j in 5:
		for i in range(-3, 4):
			ctx.beginPath()
			ctx.arc(i * 0.16 + (j & 1) * 0.08, 0.05 + j * 0.16, 0.08, 0.2, PI - 0.2)
			ctx.stroke()
	ctx.restore()
	# facial disc + eyes
	ctx.beginPath()
	ctx.moveTo(0, -0.35)
	ctx.bezierCurveTo(-0.3, -0.75, -0.9, -0.6, -0.72, -0.18)
	ctx.bezierCurveTo(-0.6, 0.18, -0.2, 0.2, 0, 0.12)
	ctx.bezierCurveTo(0.2, 0.2, 0.6, 0.18, 0.72, -0.18)
	ctx.bezierCurveTo(0.9, -0.6, 0.3, -0.75, 0, -0.35)
	inked(ctx, "#D8B484", LW * 0.8)
	var blink: bool = o.get("blink") if o.get("blink") != null else fract(t / 3.1) > 0.94
	for sx in [-1, 1]:
		var ex := sx * 0.33
		var ey := -0.26
		circle(ctx, ex, ey, 0.3)
		inked(ctx, "#F4B63A", LW)
		circle(ctx, ex, ey, 0.24)
		fill(ctx, "#FFFDF6")
		if blink:
			ctx.beginPath()
			ctx.arc(ex, ey - 0.05, 0.2, 0.3, PI - 0.3)
			stroke(ctx, C.ink, 0.06)
		else:
			var px := ex + sin(t * 1.3) * 0.03
			circle(ctx, px, ey + 0.02, 0.15)
			fill(ctx, "#1E1428")
			circle(ctx, px + 0.06, ey - 0.05, 0.05)
			fill(ctx, "#FFFFFF")
	poly(ctx, [-0.09, -0.06, 0.09, -0.06, 0, 0.14])
	inked(ctx, "#F0901E", LW * 0.8)
	# red bow tie
	poly(ctx, [0, 0.3, -0.26, 0.18, -0.26, 0.44])
	inked(ctx, C.red, LW * 0.8)
	poly(ctx, [0, 0.3, 0.26, 0.18, 0.26, 0.44])
	inked(ctx, C.red, LW * 0.8)
	circle(ctx, 0, 0.31, 0.07)
	inked(ctx, darken(C.red, 0.2), LW * 0.6)
	for p in [[-0.18, 0.26], [0.18, 0.36], [-0.2, 0.38], [0.16, 0.24]]:
		circle(ctx, p[0], p[1], 0.025)
		fill(ctx, "#FFFFFF")
	ctx.restore()

# ---------------------------------------------------------------------------------------------------------
# Pictograms (70s Olympic-sign style figures) and marker doodles
# ---------------------------------------------------------------------------------------------------------

## Stick-figure pictogram. (x, y) = hip, s = figure height. Angles in degrees from straight down
## (+ = toward +x). p: { lean, head:[dx,dy], la:[upper, lower], ra, ll, rl }. Returns joint positions.
static func picto(ctx, x: float, y: float, s: float, p: Dictionary, col) -> Dictionary:
	var u := s / 10
	var lw := u * 1.25
	var lean: float = float(_or(p.get("lean"), 0)) * DEG
	var nx := x + sin(lean) * 3.3 * u
	var ny := y - cos(lean) * 3.3 * u
	var seg := func(ax: float, ay: float, a: float, ln: float) -> Array:
		return [ax + sin(a * DEG) * ln * u, ay + cos(a * DEG) * ln * u]
	var limb := func(ax: float, ay: float, ang: Array, l1: float, l2: float) -> Array:
		var m: Array = seg.call(ax, ay, float(ang[0]), l1)
		return [m, seg.call(m[0], m[1], float(ang[1]), l2)]
	var la: Array = limb.call(nx, ny, _or(p.get("la"), [-15, -10]), 1.9, 1.8)
	var ra: Array = limb.call(nx, ny, _or(p.get("ra"), [15, 10]), 1.9, 1.8)
	var ll: Array = limb.call(x, y, _or(p.get("ll"), [-8, -4]), 2.3, 2.3)
	var rl: Array = limb.call(x, y, _or(p.get("rl"), [8, 4]), 2.3, 2.3)
	ctx.save()
	ctx.lineCap = "round"
	ctx.lineJoin = "round"
	ctx.strokeStyle = col
	ctx.lineWidth = lw
	ctx.beginPath()
	ctx.moveTo(x, y); ctx.lineTo(nx, ny)
	for ab in [la, ra]:
		ctx.moveTo(nx, ny); ctx.lineTo(ab[0][0], ab[0][1]); ctx.lineTo(ab[1][0], ab[1][1])
	for ab in [ll, rl]:
		ctx.moveTo(x, y); ctx.lineTo(ab[0][0], ab[0][1]); ctx.lineTo(ab[1][0], ab[1][1])
	ctx.stroke()
	ctx.lineWidth = lw * 1.5
	ctx.beginPath()
	ctx.moveTo(x, y)
	ctx.lineTo(lerpf(x, nx, 0.8), lerpf(y, ny, 0.8))
	ctx.stroke()
	var hd: Array = _or(p.get("head"), [0, 0])
	var hx: float = nx + sin(lean) * 1.45 * u + hd[0] * u
	var hy: float = ny - cos(lean) * 1.45 * u + hd[1] * u
	circle(ctx, hx, hy, u * 1.05)
	fill(ctx, col)
	ctx.restore()
	return {"head": [hx, hy], "neck": [nx, ny], "handL": la[1], "handR": ra[1], "elbowL": la[0], "elbowR": ra[0], "footL": ll[1], "footR": rl[1], "hip": [x, y], "u": u}

## Hand-drawn marker helpers: every stroke gets a deterministic wobble and a streaky second pass.
## Returns { ink(pts, close=false), ring(cx, cy, rx, ry=rx, n=26) -> pts, fillIn(pts, style) } (Callables).
static func marker(ctx, r: Callable, col, lw: float) -> Dictionary:
	var jit := lw * 0.35
	var path := func(pts: Array, close: bool) -> void:
		ctx.beginPath()
		var i := 0
		while i < pts.size():
			var x: float = pts[i] + (r.call() - 0.5) * jit
			var y: float = pts[i + 1] + (r.call() - 0.5) * jit
			if i == 0:
				ctx.moveTo(x, y)
			else:
				ctx.lineTo(x, y)
			i += 2
		if close:
			ctx.closePath()
	var ink := func(pts: Array, close: bool = false) -> void:
		ctx.save()
		ctx.lineCap = "round"
		ctx.lineJoin = "round"
		ctx.strokeStyle = col
		ctx.lineWidth = lw
		ctx.globalAlpha = 0.92
		path.call(pts, close)
		ctx.stroke()
		ctx.globalAlpha = 0.35
		ctx.lineWidth = lw * 0.55
		path.call(pts, close)
		ctx.stroke()
		ctx.restore()
	var ring := func(cx: float, cy: float, rx: float, ry = null, n: int = 26) -> Array:
		if ry == null:
			ry = rx
		var pts := []
		var a0: float = r.call() * TAU
		for i in n + 3:
			var a := a0 + (float(i) / n) * TAU
			var px: float = cx + cos(a) * rx * (1 + (r.call() - 0.5) * 0.06)
			var py: float = cy + sin(a) * ry * (1 + (r.call() - 0.5) * 0.06)
			pts.append(px)
			pts.append(py)
		return pts
	var fillIn := func(pts: Array, style) -> void:
		ctx.save()
		ctx.globalAlpha = 0.55
		ctx.fillStyle = style
		path.call(pts, true)
		ctx.fill()
		ctx.restore()
	return {"ink": ink, "ring": ring, "fillIn": fillIn}

# ---------------------------------------------------------------------------------------------------------
# Products and icons
# ---------------------------------------------------------------------------------------------------------

## Sponsor product illustrations centred at (x, y), height s. (JS PRODUCTS map -> PRODUCTS[id].call(ctx, x, y, s, t))
static func _prod_replay_ade(ctx, x: float, y: float, s: float, _t: float = 0.0) -> void:
	var w := s * 0.42
	var ol := s * 0.02
	rr(ctx, x - w * 0.24, y - s * 0.5, w * 0.48, s * 0.12, s * 0.02)
	inked(ctx, C.blue, ol)
	ctx.beginPath()
	ctx.moveTo(x - w * 0.2, y - s * 0.38)
	ctx.lineTo(x + w * 0.2, y - s * 0.38)
	ctx.quadraticCurveTo(x + w * 0.5, y - s * 0.3, x + w * 0.5, y - s * 0.12)
	ctx.lineTo(x + w * 0.5, y + s * 0.42)
	ctx.quadraticCurveTo(x + w * 0.5, y + s * 0.5, x + w * 0.4, y + s * 0.5)
	ctx.lineTo(x - w * 0.4, y + s * 0.5)
	ctx.quadraticCurveTo(x - w * 0.5, y + s * 0.5, x - w * 0.5, y + s * 0.42)
	ctx.lineTo(x - w * 0.5, y - s * 0.12)
	ctx.quadraticCurveTo(x - w * 0.5, y - s * 0.3, x - w * 0.2, y - s * 0.38)
	inked(ctx, linear(ctx, x - w / 2, 0, x + w / 2, 0, ["#FFE45A", "#F4C81E", "#E0A816"]), ol)
	rr(ctx, x - w * 0.5, y - s * 0.02, w, s * 0.3, 0)
	inked(ctx, C.blue, ol)
	ctx.fillStyle = "#FFE45A"
	for k in [-1.0, 0.15]:
		poly(ctx, [x + k * w * 0.3, y + s * 0.13, x + (k + 0.45) * w * 0.3, y + s * 0.04, x + (k + 0.45) * w * 0.3, y + s * 0.22])
		ctx.fill()
	ctx.fillStyle = "rgba(255,255,255,0.45)"
	rr(ctx, x - w * 0.36, y - s * 0.28, w * 0.1, s * 0.62, w * 0.05)
	ctx.fill()

static func _prod_wobble_up(ctx, x: float, y: float, s: float, t: float = 0.0) -> void:
	var w := s * 0.9
	var ol := s * 0.02
	var wob := sin(t * 9) * 0.04
	ellipse(ctx, x, y + s * 0.38, w * 0.62, s * 0.1)
	inked(ctx, "#F4F1E8", ol)
	ctx.save()
	ctx.translate(x, y + s * 0.35)
	ctx.transform(1, 0, wob, 1, 0, 0)
	ctx.scale(1 + wob, 1 - wob)
	ctx.beginPath()
	ctx.moveTo(-w * 0.5, 0)
	ctx.bezierCurveTo(-w * 0.52, -s * 0.5, -w * 0.3, -s * 0.72, 0, -s * 0.72)
	ctx.bezierCurveTo(w * 0.3, -s * 0.72, w * 0.52, -s * 0.5, w * 0.5, 0)
	ctx.closePath()
	inked(ctx, linear(ctx, 0, -s * 0.72, 0, 0, ["#7CF29A", "#1FB45A", "#0E7A3A"]), ol)
	ctx.strokeStyle = "rgba(10,80,40,0.45)"
	ctx.lineWidth = s * 0.015
	for k in [-0.32, -0.12, 0.12, 0.32]:
		ctx.beginPath()
		ctx.moveTo(k * w, -s * 0.02)
		ctx.quadraticCurveTo(k * w * 0.95, -s * 0.4, k * w * 0.5, -s * 0.66)
		ctx.stroke()
	ellipse(ctx, 0, -s * 0.66, w * 0.14, s * 0.05)
	inked(ctx, "#0E7A3A", ol * 0.8)
	ctx.fillStyle = "rgba(255,255,255,0.55)"
	ellipse(ctx, -w * 0.25, -s * 0.45, w * 0.06, s * 0.14, 0.3)
	ctx.fill()
	ctx.restore()

static func _prod_jump_cut(ctx, x: float, y: float, s: float, _t: float = 0.0) -> void:
	var w := s * 0.62
	var ol := s * 0.02
	ctx.beginPath()
	ctx.arc(x + w * 0.45, y + s * 0.05, s * 0.2, -1.2, 1.2)
	stroke(ctx, C.ink, s * 0.09)
	stroke(ctx, C.orange, s * 0.06)
	ctx.beginPath()
	ctx.moveTo(x - w * 0.3, y - s * 0.22)
	ctx.lineTo(x + w * 0.3, y - s * 0.22)
	ctx.bezierCurveTo(x + w * 0.62, y + s * 0.05, x + w * 0.55, y + s * 0.46, x + w * 0.36, y + s * 0.46)
	ctx.lineTo(x - w * 0.36, y + s * 0.46)
	ctx.bezierCurveTo(x - w * 0.55, y + s * 0.46, x - w * 0.62, y + s * 0.05, x - w * 0.3, y - s * 0.22)
	inked(ctx, "rgba(210,235,255,0.55)", ol)
	ctx.save()
	ctx.clip()
	ctx.fillStyle = linear(ctx, 0, y, 0, y + s * 0.46, ["#8A4A22", "#5A2A12"])
	ctx.fillRect(x - w, y + s * 0.02, w * 2, s * 0.5)
	ctx.restore()
	rr(ctx, x - w * 0.36, y - s * 0.36, w * 0.72, s * 0.16, s * 0.05)
	inked(ctx, C.orange, ol)
	circle(ctx, x, y - s * 0.4, s * 0.05)
	inked(ctx, C.ink, ol * 0.6)
	poly(ctx, [x + s * 0.02, y + s * 0.08, x - s * 0.1, y + s * 0.26, x - s * 0.01, y + s * 0.26, x - s * 0.05, y + s * 0.42, x + s * 0.1, y + s * 0.2, x + s * 0.01, y + s * 0.2])
	inked(ctx, "#FFD23A", ol * 0.6)
	ctx.strokeStyle = "rgba(255,255,255,0.75)"
	ctx.lineWidth = s * 0.03
	for k in [-0.12, 0.02, 0.16]:
		ctx.beginPath()
		ctx.moveTo(x + k * s, y - s * 0.48)
		ctx.bezierCurveTo(x + (k - 0.06) * s, y - s * 0.56, x + (k + 0.06) * s, y - s * 0.62, x + k * s, y - s * 0.7)
		ctx.stroke()

static func _prod_roller_boogie(ctx, x: float, y: float, s: float, _t: float = 0.0) -> void:
	var ol := s * 0.02
	ctx.beginPath()
	ctx.moveTo(x - s * 0.18, y - s * 0.46)
	ctx.lineTo(x + s * 0.12, y - s * 0.46)
	ctx.lineTo(x + s * 0.14, y - s * 0.05)
	ctx.quadraticCurveTo(x + s * 0.42, y - s * 0.02, x + s * 0.44, y + s * 0.14)
	ctx.lineTo(x + s * 0.44, y + s * 0.2)
	ctx.lineTo(x - s * 0.3, y + s * 0.2)
	ctx.lineTo(x - s * 0.3, y - s * 0.02)
	ctx.quadraticCurveTo(x - s * 0.22, y - s * 0.2, x - s * 0.18, y - s * 0.46)
	inked(ctx, linear(ctx, 0, y - s * 0.46, 0, y + s * 0.2, ["#FFFFFF", "#EDE4D0"]), ol)
	ctx.fillStyle = C.red
	ctx.fillRect(x - s * 0.2, y - s * 0.3, s * 0.34, s * 0.05)
	ctx.fillRect(x - s * 0.23, y - s * 0.2, s * 0.37, s * 0.05)
	rr(ctx, x - s * 0.34, y + s * 0.18, s * 0.82, s * 0.07, s * 0.03)
	inked(ctx, "#D8DCE6", ol)
	ellipse(ctx, x + s * 0.5, y + s * 0.2, s * 0.06, s * 0.05)
	inked(ctx, C.pink, ol)
	var wc := ["#E23B3B", "#F4E03A", "#52D24A", "#3A58E4"]
	for i in wc.size():
		circle(ctx, x - s * 0.24 + i * s * 0.22 - 0.0, y + s * 0.33, s * 0.09)
		inked(ctx, wc[i], ol)
		circle(ctx, x - s * 0.24 + i * s * 0.22, y + s * 0.33, s * 0.03)
		fill(ctx, "#F4F1E8")

static func _prod_double_vision(ctx, x: float, y: float, s: float, _t: float = 0.0) -> void:
	var ol := s * 0.02
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(-0.35)
	ctx.beginPath()
	ctx.moveTo(-s * 0.16, -s * 0.46)
	ctx.lineTo(s * 0.16, -s * 0.46)
	ctx.lineTo(s * 0.12, s * 0.3)
	ctx.lineTo(-s * 0.12, s * 0.3)
	ctx.closePath()
	inked(ctx, "#F4F1E8", ol)
	ctx.save()
	ctx.clip()
	var bc := [C.red, "#F4F1E8", C.blue]
	for i in bc.size():
		ctx.fillStyle = bc[i]
		ctx.fillRect(-s * 0.2, -s * 0.34 + i * s * 0.18, s * 0.4, s * 0.1)
	ctx.restore()
	ctx.beginPath()
	ctx.moveTo(-s * 0.16, -s * 0.46)
	ctx.lineTo(s * 0.16, -s * 0.46)
	stroke(ctx, C.ink, ol)
	rr(ctx, -s * 0.07, s * 0.3, s * 0.14, s * 0.1, s * 0.02)
	inked(ctx, C.red, ol)
	ctx.restore()
	ctx.save()
	ctx.translate(x + s * 0.2, y + s * 0.05)
	ctx.rotate(0.5)
	rr(ctx, -s * 0.035, -s * 0.46, s * 0.07, s * 0.62, s * 0.03)
	inked(ctx, C.cyan, ol)
	rr(ctx, -s * 0.05, -s * 0.52, s * 0.1, s * 0.16, s * 0.02)
	inked(ctx, "#FFFFFF", ol * 0.8)
	ctx.fillStyle = C.magenta
	for i in 4:
		ctx.fillRect(-s * 0.04 + i * s * 0.02, -s * 0.52, s * 0.012, s * 0.14)
	ctx.restore()

static var PRODUCTS := {
	"replay_ade": _prod_replay_ade,
	"wobble_up": _prod_wobble_up,
	"jump_cut": _prod_jump_cut,
	"roller_boogie": _prod_roller_boogie,
	"double_vision": _prod_double_vision,
}

static func sunIcon(ctx, x: float, y: float, r: float, face: bool = true, rot: float = 0.0) -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(rot)
	starPath(ctx, 0, 0, r, r * 0.72, 12, 0)
	inked(ctx, "#FFB020", r * 0.08)
	circle(ctx, 0, 0, r * 0.62)
	inked(ctx, radial(ctx, -r * 0.2, -r * 0.2, 0, r * 0.7, ["#FFF3A0", "#FFD23A", "#F4B020"]), r * 0.07)
	ctx.restore()
	if face:
		for s in [-1, 1]:
			circle(ctx, x + s * r * 0.2, y - r * 0.08, r * 0.07)
			fill(ctx, C.ink)
		ctx.beginPath()
		ctx.arc(x, y + r * 0.02, r * 0.26, 0.4, PI - 0.4)
		stroke(ctx, C.ink, r * 0.07)

static func boltPath(ctx, x: float, y: float, s: float) -> void:
	poly(ctx, [x + s * 0.1, y - s * 0.5, x - s * 0.3, y + s * 0.06, x - s * 0.02, y + s * 0.06, x - s * 0.14, y + s * 0.5, x + s * 0.3, y - s * 0.1, x + s * 0.02, y - s * 0.1, x + s * 0.16, y - s * 0.5])

static func towerIcon(ctx, x: float, y: float, h: float, col = null) -> void:
	if col == null:
		col = C.red
	var w := h * 0.36
	ctx.save()
	ctx.lineJoin = "round"
	ctx.lineCap = "round"
	ctx.strokeStyle = col
	ctx.lineWidth = maxf(1.5, h * 0.06)
	ctx.beginPath()
	ctx.moveTo(x - w / 2, y)
	ctx.lineTo(x, y - h)
	ctx.lineTo(x + w / 2, y)
	for k in range(1, 5):
		var yy := y - (h * k) / 5
		var hw := (w / 2) * (1 - k / 5.0)
		ctx.moveTo(x - hw, yy)
		ctx.lineTo(x + hw, yy)
		if k < 4:
			ctx.lineTo(x - (w / 2) * (1 - (k + 1) / 5.0), y - (h * (k + 1)) / 5)
	ctx.stroke()
	for rr0 in [0.18, 0.3]:
		ctx.beginPath()
		ctx.arc(x, y - h, h * rr0, -2.4, -0.74)
		ctx.stroke()
	circle(ctx, x, y - h, h * 0.06)
	fill(ctx, col)
	ctx.restore()

# ---------------------------------------------------------------------------------------------------------
# Broadcast sources (4:3 TV cards)
# ---------------------------------------------------------------------------------------------------------

## Green on-screen channel number, top-right.
static func osd(ctx, w: float, h: float, txt: String, px = null) -> void:
	if px == null:
		px = h * 0.17
	ctx.save()
	setFont(ctx, px, FONT.osd)
	ctx.textAlign = "right"
	ctx.textBaseline = "top"
	var x := w * 0.955
	var y := h * 0.035
	ctx.fillStyle = "rgba(8,24,12,0.7)"
	ctx.fillText(txt, x + px * 0.06, y + px * 0.06)
	ctx.shadowColor = "rgba(92,255,110,0.85)"
	ctx.shadowBlur = px * 0.25
	ctx.fillStyle = C.osd
	ctx.fillText(txt, x, y)
	ctx.shadowBlur = 0
	ctx.fillStyle = "rgba(220,255,225,0.55)"
	ctx.fillText(txt, x, y - px * 0.02)
	ctx.restore()

## Streaky TV snow frame k (256x192, generated with ImageData, cached).
static func snowFrame(k: int) -> DACanvas:
	return layer("snow:%d" % k, 256, 192, func(g, w, h):
		var W := int(w)
		var H := int(h)
		var img: Dictionary = g.createImageData(W, H)
		var d: PackedByteArray = img.data
		var r := Rng.Mulberry32.new(k * 7919 + 3)
		for y in H:
			var gain := 0.7 + r.next() * 0.5 + (0.6 if r.next() < 0.03 else 0.0)
			for x in W:
				var a1 := r.next()
				var a2 := r.next()
				var a3 := r.next()
				var v := minf(255.0, (a1 * a2 * 1.3 + a3 * 0.45) * 255.0 * gain)
				var i := (y * W + x) * 4
				d[i] = clampi(int(jround(v * 0.94 + 10)), 0, 255)
				d[i + 1] = clampi(int(jround(v * 0.96 + 8)), 0, 255)
				d[i + 2] = clampi(int(jround(minf(255.0, v + 22))), 0, 255)
				d[i + 3] = 255
		img.data = d
		g.putImageData(img, 0, 0))

static func drawSnow(ctx, w: float, h: float, k: int) -> void:
	ctx.save()
	ctx.imageSmoothingEnabled = false
	ctx.drawImage(snowFrame(k % 6), 0, 0, w, h)
	ctx.restore()
	vignette(ctx, w, h, 0.35, "20,14,36", 0.5)

static func drawBars(ctx, w: float, h: float, o: Dictionary = {}) -> void:
	var top := jround(h * 0.66)
	var mid := jround(h * 0.08)
	var bw := w / 7
	for i in BARS.size():
		var c: String = BARS[i]
		ctx.fillStyle = linear(ctx, 0, 0, 0, top, [lighten(c, 0.12), c, c, darken(c, 0.08)])
		ctx.fillRect(floorf(i * bw), 0, ceilf(bw) + 1, top)
	var dark := "#241C38"
	var row2 := [BARS[6], dark, BARS[4], dark, BARS[2], dark, BARS[0]]
	for i in row2.size():
		ctx.fillStyle = row2[i]
		ctx.fillRect(floorf(i * bw), top, ceilf(bw) + 1, mid)
	var y2 := top + mid
	var segs := [["#1F3F7A", 1.25], ["#F4F1E8", 1.25], ["#4E2C80", 1.25], [dark, 1.25], ["#1A1428", 1.0 / 3], [dark, 1.0 / 3], ["#3A3252", 1.0 / 3], [dark, 1.0]]
	var x := 0.0
	for sg in segs:
		ctx.fillStyle = sg[0]
		ctx.fillRect(floorf(x), y2, ceilf(sg[1] * bw) + 1, h - y2)
		x += sg[1] * bw
	# painted-card touches: soft seams, gloss, pillow vignette
	ctx.fillStyle = "rgba(30,20,50,0.12)"
	for i in range(1, 7):
		ctx.fillRect(jround(i * bw) - 1, 0, 2, top)
	ctx.fillStyle = linear(ctx, 0, 0, 0, top * 0.35, ["rgba(255,255,255,0.22)", "rgba(255,255,255,0)"])
	ctx.fillRect(0, 0, w, top * 0.35)
	ctx.fillStyle = linear(ctx, 0, top - h * 0.05, 0, top, ["rgba(30,20,50,0)", "rgba(30,20,50,0.18)"])
	ctx.fillRect(0, top - h * 0.05, w, h * 0.05)
	if not o.get("plain"):
		badge13(ctx, w - bw * 0.62, y2 + (h - y2) / 2, (h - y2) * 0.3, {"ol": 1.5})
	vignette(ctx, w, h, 0.28, "28,16,46", 0.55)

## JS String(v) for option values (integral floats print without ".0").
static func _str(v) -> String:
	if v is float:
		return _num(v)
	return str(v)

## The WZTV test card with Telly in the centre circle.
static func drawTestCard(ctx, w: float, h: float, o: Dictionary = {}) -> void:
	var cx := w / 2
	var cy := h / 2
	var R := h * 0.445
	ctx.fillStyle = "#8C8898"
	ctx.fillRect(0, 0, w, h)
	var cell := h / 12
	var off := fmod(w, cell) / 2
	var ncol := int(ceilf(w / cell))
	ctx.fillStyle = "#6E6A7C"
	for j in 12:
		for i in ncol:
			if (i + j) % 2 == 0:
				ctx.fillRect(i * cell + off, j * cell, cell, cell)
	ctx.strokeStyle = "rgba(246,242,232,0.9)"
	ctx.lineWidth = 2
	ctx.beginPath()
	var x := off
	while x <= w:
		ctx.moveTo(jround(x) + 0.5, 0)
		ctx.lineTo(jround(x) + 0.5, h)
		x += cell
	var y := 0.0
	while y <= h:
		ctx.moveTo(0, jround(y) + 0.5)
		ctx.lineTo(w, jround(y) + 0.5)
		y += cell
	ctx.stroke()
	# castellated border
	var chh := h * 0.035
	for i in ncol:
		ctx.fillStyle = "#F4F1E8" if (i & 1) else "#2A2140"
		ctx.fillRect(i * cell + off, 0, cell, chh)
		ctx.fillStyle = "#2A2140" if (i & 1) else "#F4F1E8"
		ctx.fillRect(i * cell + off, h - chh, cell, chh)
	for j in 12:
		ctx.fillStyle = "#F4F1E8" if (j & 1) else "#2A2140"
		ctx.fillRect(0, j * cell, chh, cell)
		ctx.fillStyle = "#2A2140" if (j & 1) else "#F4F1E8"
		ctx.fillRect(w - chh, j * cell, chh, cell)
	# resolution wedges left and right of the circle
	for s in [-1, 1]:
		var wx := cx + s * (R + (w / 2 - R) * 0.48)
		var wy := cy
		ctx.strokeStyle = "#1E1830"
		ctx.lineWidth = 1.4
		ctx.beginPath()
		for k in range(-5, 6):
			ctx.moveTo(wx - s * cell * 1.1, wy + k * cell * 0.26)
			ctx.lineTo(wx + s * cell * 0.9, wy + k * cell * 0.04)
		ctx.stroke()
		for k in [-1, 1]:
			circle(ctx, wx, wy + k * cell * 3.4, cell * 0.72)
			inked(ctx, "#F4F1E8", 2, "#1E1830")
			circle(ctx, wx, wy + k * cell * 3.4, cell * 0.3)
			fill(ctx, "#1E1830")
	# centre circle
	ctx.save()
	circle(ctx, cx, cy, R)
	ctx.clip()
	ctx.fillStyle = linear(ctx, 0, cy - R, 0, cy + R, ["#9ED8FF", "#CDEBFF", "#FFE9C2"])
	ctx.fillRect(cx - R, cy - R, R * 2, R * 2)
	var barH := R * 0.36
	for i in BARS.size():
		ctx.fillStyle = BARS[i]
		ctx.fillRect(cx - R + (i * 2 * R) / 7, cy - R, (2 * R) / 7 + 1, barH)
	ctx.fillStyle = "rgba(30,20,50,0.2)"
	ctx.fillRect(cx - R, cy - R + barH - 3, R * 2, 3)
	var steps := 6
	var gy := cy + R * 0.62
	for i in steps:
		var v := int(jround(40 + (i * 200.0) / (steps - 1)))
		ctx.fillStyle = "rgb(%d,%d,%d)" % [v, v - 4, v + 10]
		ctx.fillRect(cx - R + (i * 2 * R) / steps, gy, (2 * R) / steps + 1, R)
	ctx.strokeStyle = "rgba(40,30,70,0.25)"
	ctx.lineWidth = 1.5
	ctx.beginPath()
	ctx.moveTo(cx - R, cy + R * 0.18); ctx.lineTo(cx + R, cy + R * 0.18)
	ctx.moveTo(cx, cy - R + barH); ctx.lineTo(cx, gy)
	ctx.stroke()
	ellipse(ctx, cx, cy + R * 0.56, R * 0.55, R * 0.08)
	fill(ctx, "rgba(58,42,90,0.25)")
	var sz := R * 0.78
	drawTelly(ctx, cx, cy + R * 0.14, sz, {"expr": _or(o.get("expr"), "idle"), "t": _or(o.get("t"), 0.0), "look": [0, 0.1], "cols": 26, "dial": 0.1})
	ctx.restore()
	circle(ctx, cx, cy, R)
	stroke(ctx, "#F4F1E8", 5)
	circle(ctx, cx, cy, R + 3)
	stroke(ctx, "#2A2140", 2)
	# station box
	var bw := R * 0.9
	var bh := R * 0.2
	var by := cy + R * 0.66
	rr(ctx, cx - bw / 2, by, bw, bh, bh * 0.25)
	inked(ctx, "#1E1830", 2, "#F4F1E8")
	drawLogo(ctx, cx, by + bh / 2 + 1, bh * 0.52, {"style": "flat"})

# Station ID: chrome "13" spinning over colour bars, WZTV logo plate.
static func chromeGlyph(dark: bool) -> DACanvas:
	return layer("chrome13:%s" % ("side" if dark else "face"), 360, 260, func(g, w, h):
		label(g, "13", w / 2, h / 2 + 8, {
			"fam": FONT.round, "px": 230, "maxW": w * 0.92,
			"fill": vgrad(["#8A96B4", "#3E4868", "#2A3050"]) if dark else vgrad(CHROME),
			"stroke": "#1E2240" if dark else "#1E2A5A", "lw": 14,
		})
		if not dark:
			g.globalCompositeOperation = "source-atop"
			g.fillStyle = linear(g, 0, 0, w, h, ["rgba(255,255,255,0)", "rgba(255,255,255,0)", [0.46, "rgba(255,255,255,0.55)"], [0.52, "rgba(255,255,255,0)"], "rgba(255,255,255,0)"])
			g.fillRect(0, 0, w, h))

static func sparkle(ctx, x: float, y: float, r: float, a: float = 1.0) -> void:
	ctx.save()
	ctx.globalAlpha = a
	ctx.fillStyle = "#FFFFFF"
	ctx.shadowColor = "#BFE8FF"
	ctx.shadowBlur = r
	starPath(ctx, x, y, r, r * 0.16, 4, 0)
	ctx.fill()
	ctx.restore()

# Hootie's Hullabaloo intro: owl host, rainbow and bouncing balloon letters.
static func balloonText(ctx, s: String, cx: float, y: float, px: float, t: float, phase: float, maxW = null) -> void:
	var cols := ["#FF4F5E", "#FFC23A", "#3FA9F5", "#52D24A", "#FF7AC8", "#FF8A2A", "#9B6BFF"]
	ctx.save()
	setFont(ctx, px, FONT.round)
	var chars := []
	for i in s.length():
		chars.append(s[i])
	var ws := []
	var total := 0.0
	for c in chars:
		var cw0: float = ctx.measureText(c).width * 1.1
		ws.append(cw0)
		total += cw0
	var sc := maxW / total if maxW and total > maxW else 1.0
	total *= sc
	var x := cx - total / 2
	ctx.textAlign = "center"
	ctx.textBaseline = "alphabetic"
	ctx.lineJoin = "round"
	for i in chars.size():
		var ch: String = chars[i]
		var cw: float = ws[i] * sc
		var lx := x + cw / 2
		x += cw
		if ch == " ":
			continue
		var ph := t * 1.7 + phase + i * 0.42
		var hop := absf(sin(ph * PI))
		var squash := 1 - (0.18 - hop) * 0.9 if hop < 0.18 else 1.0
		var col: String = cols[(i + int(jround(phase * 3))) % cols.size()]
		ctx.save()
		ctx.translate(lx, y - hop * px * 0.22)
		ctx.scale(sc * (2 - squash), sc * squash)
		ctx.rotate(sin(ph * 2) * 0.06)
		ctx.beginPath()
		ctx.moveTo(0, px * 0.05)
		ctx.bezierCurveTo(px * 0.08, px * 0.25, -px * 0.08, px * 0.35, px * 0.02, px * 0.5)
		stroke(ctx, "rgba(60,40,80,0.6)", 1.5)
		ctx.strokeStyle = C.ink
		ctx.lineWidth = px * 0.3
		ctx.strokeText(ch, 0, 0)
		ctx.strokeStyle = col
		ctx.lineWidth = px * 0.16
		ctx.strokeText(ch, 0, 0)
		ctx.fillStyle = col
		ctx.fillText(ch, 0, 0)
		ctx.fillStyle = linear(ctx, 0, -px * 0.8, 0, -px * 0.1, ["rgba(255,255,255,0.75)", "rgba(255,255,255,0)"])
		ctx.fillText(ch, -px * 0.03, -px * 0.03)
		ellipse(ctx, -px * 0.12, -px * 0.55, px * 0.06, px * 0.1, 0.5)
		fill(ctx, "rgba(255,255,255,0.85)")
		ctx.restore()
	ctx.restore()

# The Baron on Channel 0.
static func purpleStatic(ctx, w: float, h: float, k: int, a: float) -> void:
	ctx.save()
	ctx.globalAlpha = a
	ctx.globalCompositeOperation = "screen"
	ctx.imageSmoothingEnabled = false
	ctx.drawImage(snowFrame(k % 6), 0, 0, w, h)
	ctx.restore()

const BARON_BG := {
	"laugh": ["#5A2A8A", "#2A1448", "#140A26"],
	"angry": ["#A8203A", "#5A0E2A", "#240818"],
	"frantic": ["#6A2A9A", "#2A0E48", "#10061E"],
	"goodnight": ["#2A3A8A", "#18204E", "#0C1030"],
}

# Sign-off film: WZTV logo over a waving "13" flag, then the test card (20 s loop, 15 fps).
static func flagImage() -> DACanvas:
	return layer("flag13", 300, 190, func(g, w, h):
		g.fillStyle = linear(g, 0, 0, 0, h, ["#3A6AE8", C.blue, "#2448B0"])
		g.fillRect(0, 0, w, h)
		g.fillStyle = C.red
		g.fillRect(0, 0, w, h * 0.1)
		g.fillRect(0, h * 0.9, w, h * 0.1)
		g.fillStyle = C.white
		g.fillRect(0, h * 0.1, w, h * 0.035)
		g.fillRect(0, h * 0.865, w, h * 0.035)
		badge13(g, w * 0.55, h / 2, h * 0.3, {"disc": C.white, "ring": C.red, "num": C.blue, "ol": 3}))

static func _reg_sources() -> void:
	card("color_bars", {"w": 512, "h": 384, "opts": "plain: no station badge"}, func(ctx, w, h, t, o): drawBars(ctx, w, h, o))

	card("test_card", {"w": 512, "h": 384, "opts": "variant: sleepy"}, func(ctx, w, h, t, o):
		drawTestCard(ctx, w, h, {"expr": "sleepy" if o.get("variant") == "sleepy" else "idle", "t": t}))

	card("stand_by", {"w": 512, "h": 384, "opts": "variant: awake (default sleepy Telly)"}, func(ctx, w, h, t, o):
		drawTestCard(ctx, w, h, {"expr": "idle" if o.get("variant") == "awake" else "sleepy", "t": t})
		var bw: float = w * 0.84
		var bh: float = h * 0.2
		var bx: float = (w - bw) / 2
		var by: float = h * 0.7
		ctx.save()
		ctx.shadowColor = "rgba(20,10,40,0.6)"
		ctx.shadowBlur = 16
		ctx.shadowOffsetY = 5
		rr(ctx, bx, by, bw, bh, bh * 0.28)
		fill(ctx, linear(ctx, 0, by, 0, by + bh, ["#3A58E4", "#2F3FA8"]))
		ctx.restore()
		rr(ctx, bx, by, bw, bh, bh * 0.28)
		stroke(ctx, "#F4F1E8", 4)
		rr(ctx, bx + 7, by + 7, bw - 14, bh - 14, bh * 0.2)
		stroke(ctx, alpha("#F4E03A", 0.9), 2)
		label(ctx, "PLEASE STAND BY", w / 2, by + bh * 0.47, {
			"fam": FONT.groovy, "px": bh * 0.62, "maxW": bw * 0.88, "fill": vgrad(["#FFFBEA", "#FFE28A"]),
			"stroke": C.ink, "lw": bh * 0.07, "depth": 4, "depthFill": "#1E2A6E", "dx": 0.6, "dy": 1,
		}))

	card("station_id", {"w": 512, "h": 384, "fps": 12}, func(ctx, w, h, t, o):
		ctx.drawImage(layer("station_id:bg", int(w), int(h), func(g, _w, _h):
			drawBars(g, w, h, {"plain": true})
			g.fillStyle = radial(g, w / 2, h * 0.42, 0, h * 0.55, ["rgba(22,18,52,0.9)", "rgba(22,18,52,0.72)", "rgba(22,18,52,0)"])
			g.fillRect(0, 0, w, h)
			var pw: float = w * 0.74
			var ph: float = h * 0.19
			var px: float = (w - pw) / 2
			var py: float = h * 0.77
			g.save()
			g.shadowColor = "rgba(10,6,24,0.7)"
			g.shadowBlur = 14
			rr(g, px, py, pw, ph, ph / 2)
			fill(g, linear(g, 0, py, 0, py + ph, ["#2A2466", "#161236"]))
			g.restore()
			rr(g, px, py, pw, ph, ph / 2)
			stroke(g, "#C9D3EA", 3)
			drawLogo(g, w / 2, py + ph / 2 + 1, ph * 0.56, {"style": "neon"})), 0, 0)
		var th: float = (t * TAU) / 6.5
		var cs := cos(th)
		var sn := sin(th)
		var face := chromeGlyph(false)
		var side := chromeGlyph(true)
		var gw := face.width * 0.92
		var gh := face.height * 0.92
		var cx: float = w / 2
		var cy: float = h * 0.4 + sin(t * 1.3) * 3
		var depth := 26.0
		var steps := 12
		var sgn := signf(cs if cs != 0.0 else 1.0)
		ctx.save()
		ctx.translate(cx, cy)
		var k := steps
		while k >= 1:
			ctx.save()
			ctx.translate(sn * depth * (float(k) / steps), 0)
			ctx.scale(maxf(absf(cs), 0.02) * sgn, 1)
			ctx.drawImage(side, -gw / 2, -gh / 2, gw, gh)
			ctx.restore()
			k -= 1
		ctx.scale(maxf(absf(cs), 0.02) * sgn, 1)
		if cs < 0:
			ctx.filter = "brightness(0.8)"
		ctx.drawImage(face, -gw / 2, -gh / 2, gw, gh)
		ctx.restore()
		var front := maxf(0, cs)
		sparkle(ctx, cx - gw * 0.28 * cs, cy - gh * 0.3, 16 + 10 * sin(t * 7), front)
		sparkle(ctx, cx + gw * 0.3 * cs, cy + gh * 0.18, 10 + 6 * sin(t * 5 + 1), front * 0.8))

	card("right_back", {"w": 512, "h": 384, "fps": 12}, func(ctx, w, h, t, o):
		var ox: float = w * 0.3
		var oy: float = h * 0.62
		ctx.fillStyle = radial(ctx, ox, oy, 0, w * 0.9, ["#FFB347", "#E3662B", "#B5472A"])
		ctx.fillRect(0, 0, w, h)
		rays(ctx, ox, oy, w * 1.2, 18, "rgba(255,214,120,0.35)", t * 0.25)
		ctx.fillStyle = radial(ctx, ox, oy, w * 0.1, w * 0.8, ["rgba(255,240,200,0.35)", "rgba(255,240,200,0)"])
		ctx.fillRect(0, 0, w, h)
		ellipse(ctx, ox, oy + w * 0.23, w * 0.2, w * 0.03)
		fill(ctx, "rgba(90,30,20,0.35)")
		var bob := absf(sin(t * TAU * 1.1)) * -6
		drawTelly(ctx, ox, oy + bob, w * 0.3, {"expr": "happy", "t": t, "wave": sin(t * TAU * 1.4) * 0.55, "earTwitch": sin(t * 9) * 4, "cols": 30})
		var lines := ["WE'LL BE", "RIGHT", "BACK"]
		var sizes: Array = [h * 0.12, h * 0.19, h * 0.21]
		var y: float = h * 0.2
		for i in lines.size():
			var b := sin(t * TAU * 1.1 - i * 0.7) * 3
			label(ctx, lines[i], w * 0.71, y + b, {
				"fam": FONT.groovy, "px": sizes[i], "maxW": w * 0.5, "fill": vgrad(["#FFFDF0", "#FFE7A8"]),
				"stroke": C.ink, "lw": sizes[i] * 0.1, "depth": jround(sizes[i] * 0.09), "depthFill": "#7A2A1A", "dx": 0.5, "dy": 1, "rot": -0.05,
			})
			y += sizes[i] * 0.5 + (sizes[i + 1] if i + 1 < sizes.size() else 0.0) * 0.62
		badge13(ctx, w * 0.9, h * 0.88, h * 0.06, {"ol": 2})
		vignette(ctx, w, h, 0.3, "70,20,20", 0.5))

	card("hullabaloo", {"w": 512, "h": 384, "fps": 12}, func(ctx, w, h, t, o):
		ctx.drawImage(layer("hullabaloo:bg", int(w), int(h), func(g, _w, _h):
			g.fillStyle = linear(g, 0, 0, 0, h, ["#6EC8FF", "#BDEBFF", "#E8FAFF"])
			g.fillRect(0, 0, w, h)
			var bands := ["#FF6B6B", "#FFA94D", "#FFE066", "#69DB7C", "#4DABF7", "#9775FA"]
			for i in bands.size():
				g.beginPath()
				g.arc(w / 2, h * 0.95, w * 0.58 - i * w * 0.04, PI, 0)
				stroke(g, bands[i], w * 0.04 + 1)
			g.fillStyle = "#8FD06A"
			g.beginPath()
			g.moveTo(0, h * 0.8)
			g.bezierCurveTo(w * 0.25, h * 0.7, w * 0.4, h * 0.78, w * 0.55, h * 0.82)
			g.bezierCurveTo(w * 0.75, h * 0.72, w * 0.9, h * 0.74, w, h * 0.78)
			g.lineTo(w, h); g.lineTo(0, h)
			g.fill()
			g.fillStyle = "#5DB84E"
			g.beginPath()
			g.moveTo(0, h * 0.9)
			g.bezierCurveTo(w * 0.3, h * 0.82, w * 0.7, h * 0.95, w, h * 0.86)
			g.lineTo(w, h); g.lineTo(0, h)
			g.fill()
			var r := rng(9)
			for i in 16:
				var fx: float = r.call() * w
				var fy: float = h * (0.84 + r.call() * 0.14)
				var fr: float = 6 + r.call() * 3
				flower(g, fx, fy, fr, ["#FFFFFF", "#FFD23A", "#FF8AC8"][i % 3], "#FF8A2A")), 0, 0)
		for i in 3:
			var x: float = fract(t * 0.03 + i * 0.37) * (w + 160) - 80
			cloud(ctx, x, h * (0.12 + i * 0.1), 90 + i * 16, 50 + i * 8, "#FFFFFF", "rgba(90,140,200,0.45)", 2)
		var bob := absf(sin(t * TAU * 0.9)) * -8
		ellipse(ctx, w / 2, h * 0.93, 64, 10)
		fill(ctx, "rgba(40,90,40,0.3)")
		drawHootie(ctx, w / 2, h * 0.72 + bob, h * 0.19, {"t": t, "wave": sin(t * TAU * 1.2) * 0.6 - 0.5})
		balloonText(ctx, "HOOTIE'S", w / 2, h * 0.2, h * 0.13, t, 0, w * 0.6)
		balloonText(ctx, "HULLABALOO", w / 2, h * 0.41, h * 0.17, t, 2.3, w * 0.94))

	card("baron", {"w": 512, "h": 384, "fps": 20, "opts": "variant: angry | frantic | goodnight (default laughing)"}, func(ctx, w, h, t, o):
		var mood: String = o.variant if ["angry", "frantic", "goodnight"].has(o.get("variant")) else "laugh"
		var f := int(jround(t * 20))
		ctx.fillStyle = radial(ctx, w / 2, h * 0.45, 0, w * 0.75, BARON_BG[mood])
		ctx.fillRect(0, 0, w, h)
		if mood == "goodnight":
			var r := rng(4)
			for i in 40:
				var tw := 0.5 + 0.5 * sin(t * 3 + i)
				var sx: float = r.call() * w
				var sy: float = r.call() * h * 0.7
				var sr: float = 0.8 + r.call() * 1.6
				circle(ctx, sx, sy, sr)
				fill(ctx, "rgba(255,244,214,%s)" % _num(0.3 + tw * 0.6))
			circle(ctx, w * 0.84, h * 0.2, 30)
			fill(ctx, C.moon)
			circle(ctx, w * 0.87, h * 0.18, 26)
			fill(ctx, BARON_BG.goodnight[1])
		else:
			ctx.save()
			ctx.translate(w / 2, h / 2)
			ctx.rotate(t * (1.2 if mood == "frantic" else 0.35))
			rays(ctx, 0, 0, w, 16, "rgba(255,90,60,0.12)" if mood == "angry" else "rgba(156,255,87,0.08)", 0)
			ctx.restore()
			purpleStatic(ctx, w, h, f, 0.28 if mood == "frantic" else 0.16)
		var m := 0.35
		var tilt := 0.0
		var bob := 0.0
		var shake := 0.0
		if mood == "laugh":
			m = 0.45 + 0.55 * absf(sin(t * TAU * 1.7))
			tilt = sin(t * TAU * 0.85) * 0.07
			bob = -absf(sin(t * TAU * 1.7)) * 8
		elif mood == "angry":
			shake = sin(t * 70) * 2
			m = 0.2
		elif mood == "frantic":
			shake = sin(t * 90) * 5
			tilt = sin(t * 13) * 0.1
		else:
			tilt = sin(t * 1.5) * 0.05
			bob = sin(t * 2) * 3
		ctx.save()
		ctx.translate(w / 2 + shake, h * 0.54 + bob)
		ctx.rotate(tilt)
		ctx.scale(h * 0.34, h * 0.34)
		ctx.lineJoin = "round"
		ctx.lineCap = "round"
		baronFace(ctx, mood, t, m)
		ctx.restore()
		if mood == "frantic":
			ctx.strokeStyle = "rgba(240,250,255,0.85)"
			ctx.lineWidth = 2
			ctx.beginPath()
			ctx.moveTo(w * 0.62, 0); ctx.lineTo(w * 0.58, h * 0.18); ctx.lineTo(w * 0.66, h * 0.3); ctx.lineTo(w * 0.61, h * 0.45)
			ctx.moveTo(w * 0.58, h * 0.18); ctx.lineTo(w * 0.48, h * 0.24)
			ctx.stroke()
		var band: float = fract(t * 0.35) * (h + 80) - 40
		ctx.fillStyle = linear(ctx, 0, band - 30, 0, band + 30, ["rgba(255,255,255,0)", "rgba(255,255,255,0.07)", "rgba(255,255,255,0)"])
		ctx.fillRect(0, band - 30, w, 60)
		osd(ctx, w, h, "0")
		vignette(ctx, w, h, 0.55, "12,6,24", 0.45))

	card("signoff_film", {"w": 512, "h": 384, "fps": 15, "opts": "time = seconds since the film started (loops at 20 s)"}, func(ctx, w, h, t, o):
		var lt := fmod(t, 20.0)
		var f := int(jround(t * 15))
		var r := rng(f + 11)
		var weaveX: float = (r.call() - 0.5) * 2
		var weaveY: float = (r.call() - 0.5) * 2
		ctx.fillStyle = "#1A1024"
		ctx.fillRect(0, 0, w, h)
		ctx.save()
		ctx.translate(weaveX, weaveY)
		if lt < 16:
			ctx.drawImage(layer("signoff:sky", int(w), int(h), func(g, _w, _h):
				g.fillStyle = linear(g, 0, 0, 0, h, ["#1B1E4A", "#3A3F8A", "#8A7AB8", "#FFB36B"])
				g.fillRect(0, 0, w, h)
				var sr := rng(77)
				for i in 60:
					var sx: float = sr.call() * w
					var sy: float = sr.call() * h * 0.5
					var srr: float = 0.6 + sr.call() * 1.2
					circle(g, sx, sy, srr)
					fill(g, "rgba(255,244,214,%s)" % _num(0.4 + sr.call() * 0.5))
				g.fillStyle = "rgba(255,200,170,0.25)"
				for i in 4:
					var ex: float = sr.call() * w
					var ey: float = h * (0.55 + sr.call() * 0.2)
					var erx: float = 80 + sr.call() * 60
					var ery: float = 10 + sr.call() * 6
					ellipse(g, ex, ey, erx, ery)
					g.fill()
				g.fillStyle = "#2A1E40"
				g.beginPath()
				g.moveTo(0, h)
				var x := 0.0
				while x <= w:
					g.lineTo(x, h * 0.9 - (sin(x * 0.03) * 8 + int(sr.call() * 14)))
					x += 16
				g.lineTo(w, h)
				g.fill()), 0, 0)
			# pole
			var px: float = w * 0.2
			rr(ctx, px - 5, h * 0.12, 10, h * 0.9, 5)
			fill(ctx, linear(ctx, px - 5, 0, px + 5, 0, ["#8A8EA0", "#F4F6FF", "#8A8EA0"]))
			circle(ctx, px, h * 0.11, 11)
			fill(ctx, radial(ctx, px - 3, h * 0.1 - 3, 0, 12, ["#FFF6C8", C.gold, "#A87010"]))
			# waving flag, sliced into strips
			var img := flagImage()
			var fw: float = w * 0.56
			var fh: float = fw * (float(img.height) / img.width)
			var fx: float = px + 4
			var fy: float = h * 0.16
			var strips := 56
			var sw: float = fw / strips
			for i in strips:
				var u := float(i) / strips
				var amp := 4 + u * 20
				var ph := u * 7 - t * 4.2
				var dy := sin(ph) * amp
				var slope := cos(ph)
				var sq := 1 - u * 0.06
				ctx.drawImage(img, u * img.width, 0, float(img.width) / strips + 1, img.height, fx + i * sw, fy + dy + (fh * (1 - sq)) / 2, sw + 1, fh * sq)
				ctx.fillStyle = "rgba(255,255,255,%s)" % _num(slope * 0.16) if slope > 0 else "rgba(20,10,40,%s)" % _num(-slope * 0.3)
				ctx.fillRect(fx + i * sw, fy + dy + (fh * (1 - sq)) / 2, sw + 1, fh * sq)
			var la := clampf((lt - 1.2) / 1.5, 0, 1)
			if la > 0:
				ctx.save()
				ctx.globalAlpha = la
				var ph2: float = h * 0.15
				rr(ctx, w * 0.5 - w * 0.33, h * 0.75, w * 0.66, ph2, ph2 / 2)
				fill(ctx, "rgba(20,14,48,0.8)")
				drawLogo(ctx, w / 2, h * 0.75 + ph2 / 2 + 1, ph2 * 0.55, {"style": "neon"})
				ctx.restore()
		if lt > 15.2:
			ctx.globalAlpha = clampf((lt - 15.2) / 0.8, 0, 1)
			ctx.drawImage(layer("signoff:test", int(w), int(h), func(g, _w, _h): drawTestCard(g, w, h, {"expr": "sleepy"})), 0, 0)
			ctx.globalAlpha = 1
		ctx.restore()
		# film artefacts
		grain(ctx, w, h, 0.22, f)
		ctx.fillStyle = "rgba(255,220,170,%s)" % _num(0.05 + r.call() * 0.05)
		ctx.fillRect(0, 0, w, h)
		ctx.fillStyle = "rgba(30,20,20,0.7)"
		for i in 5:
			var dx0: float = r.call() * w
			var dy0: float = r.call() * h
			var dr0: float = 0.6 + r.call() * 1.8
			circle(ctx, dx0, dy0, dr0)
			ctx.fill()
		if r.call() < 0.35:
			ctx.fillStyle = "rgba(255,250,235,0.35)"
			ctx.fillRect(r.call() * w, 0, 1.2, h)
		vignette(ctx, w, h, 0.65, "20,10,10", 0.4)
		var fade := clampf(lt / 0.8, 0, 1)
		if fade < 1:
			ctx.fillStyle = "rgba(16,10,20,%s)" % _num(1 - fade)
			ctx.fillRect(0, 0, w, h))

	# LIVE VIA SATELLITE super (transparent, full 4:3 frame so it overlays 1:1).
	card("satellite_super", {"w": 512, "h": 384, "alpha": true}, func(ctx, w, h, t, o):
		var y: float = h * 0.74
		var bh: float = h * 0.14
		ctx.save()
		ctx.shadowColor = "rgba(10,8,30,0.55)"
		ctx.shadowBlur = 10
		ctx.shadowOffsetY = 3
		rr(ctx, w * 0.06, y, w * 0.2, bh, [bh * 0.3, 0, 0, bh * 0.3])
		fill(ctx, linear(ctx, 0, y, 0, y + bh, ["#FF5A4A", "#D8242A"]))
		rr(ctx, w * 0.26, y, w * 0.68, bh, [0, bh * 0.3, bh * 0.3, 0])
		fill(ctx, linear(ctx, 0, y, 0, y + bh, ["rgba(40,70,190,0.92)", "rgba(22,34,110,0.92)"]))
		ctx.restore()
		ctx.fillStyle = "rgba(255,255,255,0.18)"
		ctx.fillRect(w * 0.06, y + 3, w * 0.88, bh * 0.3)
		ctx.fillStyle = "#F4E03A"
		ctx.fillRect(w * 0.26, y + bh - 4, w * 0.68, 4)
		circle(ctx, w * 0.085, y + bh / 2, bh * 0.1)
		fill(ctx, "#FFFFFF")
		label(ctx, "LIVE", w * 0.172, y + bh * 0.53, {"fam": FONT.sign, "px": bh * 0.55, "maxW": w * 0.12, "fill": "#FFFFFF", "stroke": "#7A0E14", "lw": 3})
		var sx: float = w * 0.33
		var sy: float = y + bh / 2
		ctx.save()
		ctx.translate(sx, sy)
		ctx.rotate(-0.5)
		rr(ctx, -bh * 0.1, -bh * 0.12, bh * 0.2, bh * 0.24, 2)
		inked(ctx, "#D8DCE6", 1.5)
		for s in [-1, 1]:
			rr(ctx, bh * 0.12 if s > 0 else -bh * 0.4, -bh * 0.07, bh * 0.28, bh * 0.14, 1)
			inked(ctx, "#5FA8FF", 1.5)
		ctx.restore()
		ctx.strokeStyle = "#FFFFFF"
		ctx.lineWidth = 2
		for k in [1, 2]:
			ctx.beginPath()
			ctx.arc(sx - bh * 0.18, sy + bh * 0.18, bh * 0.14 * k + 4, PI * 0.55, PI * 1.0)
			ctx.stroke()
		label(ctx, "VIA SATELLITE", w * 0.63, y + bh * 0.53, {"fam": FONT.sign, "px": bh * 0.52, "maxW": w * 0.52, "fill": "#FFFFFF", "stroke": "#141040", "lw": 4, "track": 1})
		ctx.globalAlpha = 0.85
		badge13(ctx, w * 0.9, h * 0.1, h * 0.055, {"ol": 2}))

	card("telly_face", {"w": 384, "h": 288, "fps": 12, "opts": "expr: %s; look: [x, y] gaze -1..1" % " | ".join(TELLY_EXPRS)}, func(ctx, w, h, t, o):
		tellyScreen(ctx, 0, 0, w, h, o.expr if TELLY_EXPRS.has(o.get("expr")) else "idle", t, _or(o.get("look"), [0, 0]), 64))

	card("snow", {"w": 512, "h": 384, "fps": 20, "opts": "channel: OSD number for snow channels (3, 6, 10)"}, func(ctx, w, h, t, o):
		drawSnow(ctx, w, h, int(jround(t * 20)))
		if o.has("channel") and o.channel != null:
			osd(ctx, w, h, _str(o.channel)))

# ---------------------------------------------------------------------------------------------------------
# Scenery kit (skylines, deserts, space, disco...) shared by show cards, promos, posters and worlds
# ---------------------------------------------------------------------------------------------------------

static func starField(ctx, w: float, h: float, n: int, seed: int, maxY: float = 1.0, col: String = "255,244,214") -> void:
	var r := rng(seed)
	for i in n:
		var x: float = r.call() * w
		var y: float = r.call() * h * maxY
		var s: float = r.call()
		if s > 0.94:
			sparkle(ctx, x, y, 3 + r.call() * 4, 0.9)
		else:
			circle(ctx, x, y, 0.5 + s * 1.3)
			fill(ctx, "rgba(%s,%s)" % [col, _num(0.35 + r.call() * 0.6)])

## City skyline silhouette band with lit windows.
static func skyline(ctx, w: float, base: float, hMin: float, hMax: float, col: String, seed: int, lit: float = 0.35, winCol: String = "#FFD27A") -> void:
	var r := rng(seed)
	var x := -10.0
	while x < w + 10:
		var bw: float = 22 + r.call() * 46
		var bh: float = hMin + r.call() * (hMax - hMin)
		ctx.fillStyle = col
		ctx.fillRect(x, base - bh, bw, bh + 2)
		if r.call() < 0.3:
			ctx.fillRect(x + bw * 0.4, base - bh - 12 - r.call() * 16, 3, 30)
		if r.call() < 0.25:
			ctx.beginPath()
			ctx.moveTo(x, base - bh)
			ctx.lineTo(x + bw / 2, base - bh - bw * 0.35)
			ctx.lineTo(x + bw, base - bh)
			ctx.fill()
		ctx.fillStyle = winCol
		var yy := base - bh + 6
		while yy < base - 6:
			var xx := x + 4
			while xx < x + bw - 5:
				if r.call() < lit:
					ctx.fillRect(xx, yy, 4, 5)
				xx += 8
			yy += 9
		x += bw + r.call() * 4

static func glowBlob(ctx, x: float, y: float, r: float, col: String, a: float = 0.8) -> void:
	ctx.fillStyle = radial(ctx, x, y, 0, r, [alpha(col, a), alpha(col, a * 0.35), alpha(col, 0)])
	ctx.fillRect(x - r, y - r, r * 2, r * 2)

## 70s sunset sun with horizontal slices cut out of its lower half.
static func slicedSun(ctx, x: float, y: float, r: float, top: String, bottom: String, gapCol: String) -> void:
	circle(ctx, x, y, r)
	fill(ctx, linear(ctx, 0, y - r, 0, y + r, [top, bottom]))
	ctx.fillStyle = gapCol
	for i in 5:
		var gy := y + r * (0.1 + i * 0.2)
		var gh := 2 + i * 1.6
		ctx.fillRect(x - r - 2, gy, r * 2 + 4, gh)

static func mesas(ctx, w: float, base: float, col: String, seed: int) -> void:
	var r := rng(seed)
	ctx.fillStyle = col
	ctx.beginPath()
	ctx.moveTo(0, base)
	var x := 0.0
	while x < w:
		var mw: float = 50 + r.call() * 90
		var mh: float = 20 + r.call() * 50
		if r.call() < 0.55:
			ctx.lineTo(x + mw * 0.15, base - mh)
			ctx.lineTo(x + mw * 0.85, base - mh)
			ctx.lineTo(x + mw, base)
		else:
			ctx.lineTo(x + mw, base - r.call() * 8)
		x += mw
	ctx.lineTo(w, base)
	ctx.lineTo(w, base + 400)
	ctx.lineTo(0, base + 400)
	ctx.fill()

static func cactus(ctx, x: float, y: float, h: float, col: String, ink = null) -> void:
	var w := h * 0.2
	var parts := [[x, y, x, y - h, w], [x, y - h * 0.45, x - h * 0.28, y - h * 0.45, w * 0.8], [x - h * 0.28, y - h * 0.44, x - h * 0.28, y - h * 0.78, w * 0.8],
		[x, y - h * 0.6, x + h * 0.26, y - h * 0.6, w * 0.8], [x + h * 0.26, y - h * 0.59, x + h * 0.26, y - h * 0.88, w * 0.8]]
	if ink:
		for p in parts:
			capsule(ctx, p[0], p[1], p[2], p[3], p[4] + 4, ink)
	for p in parts:
		capsule(ctx, p[0], p[1], p[2], p[3], p[4], col)
	if ink:
		ctx.strokeStyle = alpha("#0E3A1E", 0.4)
		ctx.lineWidth = 1.2
		ctx.beginPath()
		ctx.moveTo(x, y - 2)
		ctx.lineTo(x, y - h + w * 0.4)
		ctx.stroke()

static func palm(ctx, x: float, y: float, h: float, trunk, leaf) -> void:
	ctx.beginPath()
	ctx.moveTo(x - h * 0.04, y)
	ctx.quadraticCurveTo(x + h * 0.1, y - h * 0.5, x + h * 0.22, y - h)
	ctx.lineTo(x + h * 0.27, y - h)
	ctx.quadraticCurveTo(x + h * 0.16, y - h * 0.5, x + h * 0.05, y)
	fill(ctx, trunk)
	var tx := x + h * 0.245
	var ty := y - h
	for i in 7:
		var a := -PI + (i / 6.0) * PI + (0.2 if i > 3 else -0.2)
		var ln := h * (0.45 + (i % 2) * 0.1)
		var ex := tx + cos(a) * ln
		var ey := ty + sin(a) * ln * 0.5 + ln * 0.3
		ctx.beginPath()
		ctx.moveTo(tx, ty)
		ctx.quadraticCurveTo((tx + ex) / 2 + sin(a) * 10, ty - ln * 0.3, ex, ey)
		ctx.quadraticCurveTo((tx + ex) / 2, ty - ln * 0.05, tx, ty)
		fill(ctx, leaf)
	for d in [[-4, 4], [4, 5], [0, 8]]:
		circle(ctx, tx + d[0], ty + d[1], h * 0.035)
		fill(ctx, "#6A3E22")

static func ringedPlanet(ctx, x: float, y: float, r: float, c1: String, c2: String, ring: String, tilt: float = -0.35) -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(tilt)
	ctx.beginPath()
	ctx.ellipse(0, 0, r * 2, r * 0.5, 0, PI, TAU)
	stroke(ctx, ring, r * 0.18)
	ctx.restore()
	circle(ctx, x, y, r)
	fill(ctx, linear(ctx, x - r, y - r, x + r, y + r, [lighten(c1, 0.25), c1, c2]))
	ctx.save()
	circle(ctx, x, y, r)
	ctx.clip()
	ctx.translate(x, y)
	ctx.rotate(tilt)
	for i in range(-3, 4):
		ctx.fillStyle = alpha(c2 if (i & 1) else lighten(c1, 0.3), 0.35)
		ctx.fillRect(-r, i * r * 0.28 - r * 0.07, r * 2, r * 0.14)
	ctx.rotate(-tilt)
	ctx.fillStyle = radial(ctx, r * 0.4, r * 0.4, r * 0.2, r * 1.3, ["rgba(20,10,40,0)", "rgba(20,10,40,0.55)"])
	ctx.fillRect(-r, -r, r * 2, r * 2)
	ctx.restore()
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(tilt)
	ctx.beginPath()
	ctx.ellipse(0, 0, r * 2, r * 0.5, 0, 0, PI)
	stroke(ctx, ring, r * 0.18)
	ctx.beginPath()
	ctx.ellipse(0, 0, r * 1.75, r * 0.42, 0, 0, PI)
	stroke(ctx, alpha("#FFFFFF", 0.4), r * 0.04)
	ctx.restore()

static func rocket(ctx, x: float, y: float, s: float, rot: float, t: float = 0.0) -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(rot)
	var fl := 0.8 + sin(t * 30) * 0.15
	ctx.beginPath()
	ctx.moveTo(-s * 0.12, s * 0.45)
	ctx.quadraticCurveTo(0, s * (0.45 + 0.6 * fl), s * 0.12, s * 0.45)
	fill(ctx, linear(ctx, 0, s * 0.45, 0, s * 1.1, ["#FFF3A0", "#FF8A2A", "rgba(255,60,40,0)"]))
	for sd in [-1, 1]:
		poly(ctx, [sd * s * 0.14, s * 0.1, sd * s * 0.34, s * 0.5, sd * s * 0.12, s * 0.42])
		inked(ctx, C.red, s * 0.03)
	ctx.beginPath()
	ctx.moveTo(0, -s * 0.6)
	ctx.bezierCurveTo(s * 0.22, -s * 0.35, s * 0.2, s * 0.2, s * 0.14, s * 0.46)
	ctx.lineTo(-s * 0.14, s * 0.46)
	ctx.bezierCurveTo(-s * 0.2, s * 0.2, -s * 0.22, -s * 0.35, 0, -s * 0.6)
	inked(ctx, linear(ctx, -s * 0.2, 0, s * 0.2, 0, ["#FFFFFF", "#E8E4F0", "#B8B0CC"]), s * 0.03)
	ctx.save()
	ctx.clip()
	ctx.fillStyle = C.red
	ctx.fillRect(-s, -s * 0.62, s * 2, s * 0.22)
	ctx.restore()
	circle(ctx, 0, -s * 0.08, s * 0.09)
	inked(ctx, radial(ctx, -s * 0.03, -s * 0.11, 0, s * 0.1, ["#DFF8FF", "#3FA9F5"]), s * 0.03)
	ctx.restore()

static func mirrorBall(ctx, x: float, y: float, r: float) -> void:
	ctx.beginPath()
	ctx.moveTo(x, 0)
	ctx.lineTo(x, y - r)
	stroke(ctx, "#8A8EA0", 2)
	circle(ctx, x, y, r)
	fill(ctx, radial(ctx, x - r * 0.3, y - r * 0.3, 0, r * 1.1, ["#FFFFFF", "#B8C4DC", "#4A5070"]))
	ctx.save()
	circle(ctx, x, y, r)
	ctx.clip()
	var n := 9
	for j in n:
		var lat := -PI / 2 + ((j + 0.5) / n) * PI
		var yy := y + sin(lat) * r
		var rr0 := cos(lat) * r
		var cells := maxi(3, int(jround(rr0 / 5)))
		for i in cells:
			var u := (i + (j & 1) * 0.5) / cells
			var xx := x - rr0 + u * rr0 * 2
			var b := 0.5 + 0.5 * sin(i * 1.7 + j * 2.3)
			ctx.fillStyle = "rgba(%s,%s,255,%s)" % [_num(200 + b * 55), _num(210 + b * 45), _num(0.5 + b * 0.5)]
			ctx.fillRect(xx, yy - r / n / 2, (rr0 * 2) / cells - 1.2, r / n * 0.9)
	ctx.restore()
	circle(ctx, x, y, r)
	stroke(ctx, alpha(C.ink, 0.6), 1.5)
	sparkle(ctx, x - r * 0.35, y - r * 0.4, r * 0.35)

## Lit disco floor in perspective, from y0 to the bottom.
static func danceFloor(ctx, w: float, h: float, y0: float, cols: Array, t: float = 0.0) -> void:
	var rows := 5
	var n := 8
	for j in rows:
		var v0 := float(j) / rows
		var v1 := float(j + 1) / rows
		var ya := y0 + (h - y0) * v0 * v0
		var yb := y0 + (h - y0) * v1 * v1
		var spreadA := 0.6 + v0 * 0.9
		var spreadB := 0.6 + v1 * 0.9
		for i in n:
			var ua := (float(i) / n - 0.5) * spreadA
			var ub := (float(i + 1) / n - 0.5) * spreadA
			var uc := (float(i + 1) / n - 0.5) * spreadB
			var ud := (float(i) / n - 0.5) * spreadB
			var on := (i + j + int(floorf(t * 2))) % 3 != 0
			poly(ctx, [w / 2 + ua * w, ya, w / 2 + ub * w, ya, w / 2 + uc * w, yb, w / 2 + ud * w, yb])
			inked(ctx, cols[(i * 3 + j * 2) % cols.size()] if on else "#3A2050", 1.5, "#1A0E2A")

## Organic camouflage blobs.
static func camo(ctx, w: float, h: float, seed: int, cols: Array) -> void:
	var r := rng(seed)
	ctx.fillStyle = cols[0]
	ctx.fillRect(0, 0, w, h)
	for k in range(1, cols.size()):
		for i in 18:
			var cx: float = r.call() * w
			var cy: float = r.call() * h
			var rad: float = 20 + r.call() * 44
			var pts := 9
			ctx.beginPath()
			for p in pts + 2:
				var a := (float(p) / pts) * TAU
				var rr0: float = rad * (0.6 + r.call() * 0.6)
				var px := cx + cos(a) * rr0 * 1.4
				var py := cy + sin(a) * rr0 * 0.8
				if p == 0:
					ctx.moveTo(px, py)
				else:
					ctx.quadraticCurveTo(cx + cos(a - 0.35) * rr0 * 1.6, cy + sin(a - 0.35) * rr0, px, py)
			fill(ctx, cols[k])

static func bigRig(ctx, x: float, y: float, s: float) -> void:
	var ol := s * 0.02
	rr(ctx, x - s * 0.5, y - s * 0.95, s, s * 0.95, s * 0.08)
	inked(ctx, linear(ctx, 0, y - s, 0, y, ["#FF5A4A", "#D8242A", "#9A1A20"]), ol)
	rr(ctx, x - s * 0.42, y - s * 0.88, s * 0.84, s * 0.34, s * 0.05)
	inked(ctx, linear(ctx, 0, y - s * 0.88, 0, y - s * 0.54, ["#BFE8FF", "#5FA8D8"]), ol)
	ctx.fillStyle = "rgba(255,255,255,0.5)"
	poly(ctx, [x - s * 0.36, y - s * 0.86, x - s * 0.2, y - s * 0.86, x - s * 0.34, y - s * 0.56, x - s * 0.42, y - s * 0.56])
	ctx.fill()
	ctx.fillRect(x - s * 0.42, y - s * 0.9, s * 0.84, s * 0.05)
	rr(ctx, x - s * 0.3, y - s * 0.48, s * 0.6, s * 0.36, s * 0.04)
	inked(ctx, linear(ctx, 0, y - s * 0.48, 0, y - s * 0.12, ["#FFFFFF", "#9AA4BC", "#E8ECF6", "#7A8098"]), ol)
	ctx.strokeStyle = "#5A6078"
	ctx.lineWidth = s * 0.012
	ctx.beginPath()
	for i in range(1, 10):
		ctx.moveTo(x - s * 0.3 + i * s * 0.06, y - s * 0.46)
		ctx.lineTo(x - s * 0.3 + i * s * 0.06, y - s * 0.14)
	ctx.stroke()
	for sd in [-1, 1]:
		circle(ctx, x + sd * s * 0.4, y - s * 0.3, s * 0.07)
		inked(ctx, radial(ctx, x + sd * s * 0.4, y - s * 0.32, 0, s * 0.08, ["#FFFFFF", "#FFF0A0", "#E8B830"]), ol)
		rr(ctx, x + sd * s * 0.62 - s * 0.05, y - s * 1.35, s * 0.1, s * 1.2, s * 0.05)
		inked(ctx, linear(ctx, x + sd * s * 0.62 - s * 0.05, 0, x + sd * s * 0.62 + s * 0.05, 0, ["#8A8EA0", "#FFFFFF", "#8A8EA0"]), ol)
		rr(ctx, x + sd * s * 0.42 - s * 0.1, y - s * 0.02, s * 0.2, s * 0.22, s * 0.06)
		inked(ctx, "#2A2230", ol)
	rr(ctx, x - s * 0.55, y - s * 0.1, s * 1.1, s * 0.12, s * 0.04)
	inked(ctx, linear(ctx, 0, y - s * 0.1, 0, y + s * 0.02, ["#FFFFFF", "#9AA4BC"]), ol)
	label(ctx, "13", x, y - s * 0.035, {"fam": FONT.sign, "px": s * 0.1, "fill": C.red})

static func perspectiveRoad(ctx, w: float, h: float, hy: float, asphalt: String = "#4A4458") -> void:
	var vx := w / 2
	poly(ctx, [vx - 6, hy, vx + 6, hy, w * 0.95, h, w * 0.05, h])
	fill(ctx, linear(ctx, 0, hy, 0, h, [lighten(asphalt, 0.2), asphalt]))
	ctx.fillStyle = "#F4F1E8"
	poly(ctx, [vx - 6, hy, vx - 4, hy, w * 0.09, h, w * 0.05, h])
	ctx.fill()
	poly(ctx, [vx + 4, hy, vx + 6, hy, w * 0.95, h, w * 0.91, h])
	ctx.fill()
	ctx.fillStyle = "#FFD23A"
	for i in 7:
		var a := pow(i / 7.0, 2)
		var b := pow((i + 0.5) / 7.0, 2)
		var ya := hy + (h - hy) * a
		var yb := hy + (h - hy) * b
		var wa := 1 + a * 10
		var wb := 1 + b * 10
		poly(ctx, [vx - wa / 2, ya, vx + wa / 2, ya, vx + wb / 2, yb, vx - wb / 2, yb])
		ctx.fill()

## Sunset desert: banded sky, sliced sun, mesas and a striped sand floor from the horizon `hz` down.
static func desertScene(ctx, w: float, h: float, hz: float, sunR: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, hz, ["#5A2A6E", "#C2407A", "#FF7E5F", "#FFB36B", "#FFE3A3"])
	ctx.fillRect(0, 0, w, h)
	slicedSun(ctx, w * 0.5, hz - sunR * 0.3, sunR, "#FFF1A0", "#FF8A3A", "#FFB36B")
	mesas(ctx, w, hz, "#8A3A5A", 12)
	ctx.fillStyle = linear(ctx, 0, hz + h * 0.02, 0, h, ["#E08A4A", "#C0602E"])
	ctx.fillRect(0, hz + h * 0.04, w, h)
	ctx.fillStyle = "rgba(120,50,30,0.35)"
	var y := hz + h * 0.08
	while y < h:
		ctx.fillRect(0, y, w, 1.5)
		y += h * 0.04

## Op-art hypno spiral (Agent Thirteen) centred at (cx, cy).
static func opSpiral(ctx, w: float, h: float, cx: float, cy: float) -> void:
	ctx.fillStyle = "#F6E7C8"
	ctx.fillRect(0, 0, w, h)
	var arms := 14
	var R := Vector2(w, h).length()
	ctx.fillStyle = "#2A1D3A"
	var i := 0
	while i < arms:
		ctx.beginPath()
		for k in 41:
			var rr0 := (k / 40.0) * R
			var a := (float(i) / arms) * TAU + rr0 * 0.012
			ctx.lineTo(cx + cos(a) * rr0, cy + sin(a) * rr0)
		for k in range(40, -1, -1):
			var rr1 := (k / 40.0) * R
			var a2 := (float(i + 1) / arms) * TAU + rr1 * 0.012
			ctx.lineTo(cx + cos(a2) * rr1, cy + sin(a2) * rr1)
		ctx.fill()
		i += 2
	for k in 4:
		circle(ctx, cx, cy, 40 + k * 46)
		stroke(ctx, alpha(C.orange, 0.85), 5)
	ctx.fillStyle = radial(ctx, cx, cy, 20, maxf(w, h) * 0.7, ["rgba(246,231,200,0)", "rgba(42,29,58,0.55)"])
	ctx.fillRect(0, 0, w, h)

## Jungle camouflage with corner fronds (Commando Club).
static func jungle(ctx, w: float, h: float) -> void:
	camo(ctx, w, h, 71, ["#6E7A3A", "#4A5A2A", "#A89A5A", "#3A3020"])
	ctx.fillStyle = radial(ctx, w / 2, h / 2, w * 0.2, maxf(w, h) * 0.8, ["rgba(20,24,10,0)", "rgba(20,24,10,0.55)"])
	ctx.fillRect(0, 0, w, h)
	for f in [[0, 0, 0.6], [w, 0, 2.5], [0, h, -0.6], [w, h, -2.5]]:
		frond(ctx, f[0], f[1], 120, f[2])

static func weatherMapArt(ctx, x: float, y: float, w: float, h: float, o: Dictionary = {}) -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.scale(w / 512, h / 341)
	ctx.fillStyle = linear(ctx, 0, 0, 0, 341, ["#3E86D8", "#2F6FC0"])
	ctx.fillRect(0, 0, 512, 341)
	ctx.strokeStyle = "rgba(255,255,255,0.12)"
	ctx.lineWidth = 1
	ctx.beginPath()
	for i in range(1, 12):
		ctx.moveTo(i * 44, 0)
		ctx.lineTo(i * 44, 341)
	for j in range(1, 8):
		ctx.moveTo(0, j * 44)
		ctx.lineTo(512, j * 44)
	ctx.stroke()
	var land := DAPath2D.new("M40 60 C120 30 200 50 260 40 C330 30 420 45 470 70 C495 110 480 160 488 210 C495 260 470 300 420 310 C340 322 260 300 190 312 C120 322 60 300 45 250 C30 200 50 160 36 120 C30 95 32 75 40 60 Z")
	ctx.save()
	ctx.translate(4, 6)
	ctx.fillStyle = "rgba(20,20,60,0.35)"
	ctx.fill(land)
	ctx.restore()
	ctx.fillStyle = "#8CCB6A"
	ctx.fill(land)
	ctx.save()
	ctx.clip(land)
	var counties := [["#A6D873", "M0 0 L200 0 L185 150 L210 341 L0 341 Z"], ["#E9D98A", "M200 0 L350 0 L330 160 L360 341 L210 341 L185 150 Z"], ["#F2B48A", "M350 0 L512 0 L512 341 L360 341 L330 160 Z"]]
	for cd in counties:
		ctx.fillStyle = cd[0]
		ctx.fill(DAPath2D.new(cd[1]))
	ctx.fillStyle = "#5FB0F0"
	ctx.fill(DAPath2D.new("M95 200 C120 180 160 190 165 215 C170 240 130 255 105 245 C85 238 80 215 95 200 Z"))
	ctx.strokeStyle = "#5FB0F0"
	ctx.lineWidth = 6
	ctx.lineCap = "round"
	ctx.stroke(DAPath2D.new("M160 210 C220 230 250 170 300 190 C350 210 380 260 440 250 C470 245 490 260 512 250"))
	ctx.setLineDash([7, 6])
	ctx.strokeStyle = "rgba(60,40,80,0.6)"
	ctx.lineWidth = 3
	ctx.stroke(DAPath2D.new("M200 0 L185 150 L210 341 M350 0 L330 160 L360 341"))
	ctx.setLineDash([])
	var r := rng(3)
	for i in 26:
		var px: float = 60 + r.call() * 400
		var py: float = 70 + r.call() * 220
		poly(ctx, [px - 6, py, px, py - 9, px + 6, py])
		fill(ctx, "rgba(60,110,50,0.35)")
	ctx.restore()
	ctx.lineJoin = "round"
	ctx.strokeStyle = C.ink
	ctx.lineWidth = 4
	ctx.stroke(land)
	if o.get("names") != false:
		for nm in [["WEBB", 100, 110], ["ORVILLE", 268, 100], ["CASS", 420, 120]]:
			label(ctx, nm[0], nm[1], nm[2], {"fam": FONT.sign, "px": 17, "fill": "#FFFDF2", "stroke": "#3A2A5A", "lw": 4})
	var tx := 400.0
	var ty := 238.0
	circle(ctx, tx, ty - 16, 26)
	fill(ctx, "rgba(255,255,255,0.75)")
	towerIcon(ctx, tx, ty, 40, C.red)
	circle(ctx, 250, 225, 7)
	inked(ctx, C.white, 3)
	if o.get("temps"):
		for tt in [["58", 110, 170], ["61", 270, 150], ["55", 440, 190]]:
			label(ctx, tt[0] + "°", tt[1], tt[2], {"fam": FONT.round, "px": 26, "fill": "#FFFFFF", "stroke": "#2A3A8A", "lw": 5})
	ctx.restore()

# ---------------------------------------------------------------------------------------------------------
# Telly's nine channel cards (show_<n>): each a 70s title card with the green OSD number
# ---------------------------------------------------------------------------------------------------------

static func _show2(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#141638", "#2A2F6B", "#6B3A6E"])
	ctx.fillRect(0, 0, w, h)
	starField(ctx, w, h, 50, 21, 0.55)
	circle(ctx, w * 0.91, h * 0.37, 24)
	fill(ctx, C.moon)
	ctx.save()
	ctx.globalCompositeOperation = "lighter"
	for xa in [[0.25, -0.35], [0.7, 0.3]]:
		ctx.save()
		ctx.translate(w * xa[0], h)
		ctx.rotate(xa[1])
		poly(ctx, [-10, 0, 10, 0, 70, -h * 1.2, -70, -h * 1.2])
		fill(ctx, linear(ctx, 0, 0, 0, -h, ["rgba(255,240,200,0.35)", "rgba(255,240,200,0)"]))
		ctx.restore()
	glowBlob(ctx, 0, h * 0.8, w * 0.45, "#FF3B30", 0.55)
	glowBlob(ctx, w, h * 0.8, w * 0.45, "#3A7BFF", 0.6)
	ctx.restore()
	skyline(ctx, w, h * 0.9, 60, 150, "#2A2358", 5, 0.15, "#8A7AD8")
	skyline(ctx, w, h, 50, 120, "#141030", 8, 0.35)
	# title: chrome word + police shield
	label(ctx, "PRECINCT", w * 0.37, h * 0.19, {"fam": FONT.sign, "px": 58, "maxW": w * 0.6, "fill": vgrad(CHROME), "stroke": "#141040", "lw": 7, "depth": 5, "depthFill": "#5A2A8A", "skew": -0.18})
	shield(ctx, w * 0.775, h * 0.215, 40)

static func _show4(ctx, w: float, h: float) -> void:
	desertScene(ctx, w, h, h * 0.7, 92)
	cactus(ctx, w * 0.1, h, h * 0.55, "#2F6A3A", "#12301C")
	cactus(ctx, w * 0.9, h * 1.02, h * 0.45, "#2F6A3A", "#12301C")
	cactus(ctx, w * 0.72, h * 0.8, h * 0.14, "#6A3A4A")
	label(ctx, "Dusty Trails", w * 0.45, h * 0.2, {"fam": FONT.groovy, "px": 72, "maxW": w * 0.74, "fill": vgrad(["#FFF3D0", "#F2C27A", "#D08A3A"]), "stroke": "#4A1E14", "lw": 8, "depth": 6, "depthFill": "#7A2E1E", "rot": -0.04})
	ctx.beginPath()
	ctx.moveTo(w * 0.18, h * 0.33)
	ctx.bezierCurveTo(w * 0.4, h * 0.4, w * 0.6, h * 0.28, w * 0.82, h * 0.34)
	stroke(ctx, "#4A1E14", 5)
	stroke(ctx, "#E8B070", 2.5)

static func _show5(ctx, w: float, h: float) -> void:
	opSpiral(ctx, w, h, w / 2, h * 0.55)
	rr(ctx, 0, 0, w, h * 0.3, 0)
	fill(ctx, "rgba(26,18,40,0.82)")
	label(ctx, "AGENT", w * 0.45, h * 0.09, {"fam": FONT.sign, "px": 26, "fill": C.orange, "track": 12})
	label(ctx, "THIRTEEN", w * 0.45, h * 0.2, {"fam": FONT.sign, "px": 58, "maxW": w * 0.72, "fill": vgrad(["#FFFFFF", "#F6E7C8"]), "stroke": C.red, "lw": 5, "track": 3})

static func _show7(ctx, w: float, h: float) -> void:
	jungle(ctx, w, h)
	var py := h * 0.12
	var ph := h * 0.22
	rr(ctx, w * 0.06, py, w * 0.78, ph, 8)
	inked(ctx, linear(ctx, 0, py, 0, py + ph, ["#5A6A2E", "#3E4A1E"]), 4, "#1E2410")
	for sx in [0.09, 0.81]:
		circle(ctx, w * sx, py + ph / 2, 5)
		inked(ctx, "#C9CED8", 2, "#1E2410")
	stencil(ctx, "COMMANDO CLUB", w * 0.45, py + ph * 0.54, 44, w * 0.64, "#F4E03A")
	starBadge(ctx, w * 0.5, h * 0.86, 30)

static func _show8(ctx, w: float, h: float) -> void:
	var hy := h * 0.52
	ctx.fillStyle = linear(ctx, 0, 0, 0, hy, ["#4AA8F0", "#9ED8FF", "#FFE3A3"])
	ctx.fillRect(0, 0, w, hy)
	sunIcon(ctx, w * 0.16, h * 0.34, 34, false)
	cloud(ctx, w * 0.62, h * 0.36, 110, 40, "#FFFFFF")
	mesas(ctx, w, hy, "#B87A9A", 30)
	ctx.fillStyle = linear(ctx, 0, hy, 0, h, ["#D8B070", "#A8783A"])
	ctx.fillRect(0, hy, w, h - hy)
	perspectiveRoad(ctx, w, h, hy)
	for i in 5:
		var u := pow(i / 5.0, 2)
		var px := w / 2 - 20 - u * w * 0.55
		var py := hy + (h - hy) * u
		var ph := 8 + u * 120
		capsule(ctx, px, py, px, py - ph, 1 + u * 5, "#5A3A2A")
		capsule(ctx, px - ph * 0.15, py - ph * 0.85, px + ph * 0.15, py - ph * 0.85, 1 + u * 3, "#5A3A2A")
	bigRig(ctx, w * 0.74, h * 0.98, 150)
	label(ctx, "TRUCKERS!", w * 0.4, h * 0.17, {"fam": FONT.sign, "px": 64, "maxW": w * 0.72, "fill": vgrad(CHROME), "stroke": "#8A1414", "lw": 8, "depth": 6, "depthFill": "#4A0E14", "skew": -0.22})

static func _show9(ctx, w: float, h: float) -> void:
	ctx.fillStyle = "#FFD23A"
	ctx.fillRect(0, 0, w, h)
	rays(ctx, w / 2, h * 0.62, w, 20, "#FFB020", 0.1)
	halftone(ctx, 0, 0, w, h, "rgba(255,120,60,0.35)", 14, func(u, v): return 0.25 + 0.35 * v)
	cloud(ctx, w * 0.2, h * 0.84, 170, 70, "#FFFFFF", C.ink, 3)
	cloud(ctx, w * 0.82, h * 0.88, 190, 76, "#FFFFFF", C.ink, 3)
	sunIcon(ctx, w * 0.86, h * 0.48, 38, true, 0.2)
	rocket(ctx, w * 0.13, h * 0.5, 64, 0.5)
	for sc in [[0.3, 0.62, "#FF4F5E"], [0.66, 0.66, "#3FA9F5"], [0.5, 0.9, "#52D24A"]]:
		starPath(ctx, w * sc[0], h * sc[1], 16, 7, 5)
		inked(ctx, sc[2], 3)
	balloonText(ctx, "SATURDAY MORNING", w * 0.45, h * 0.19, 40, 0.3, 0.8, w * 0.76)
	balloonText(ctx, "CARTOONS", w * 0.47, h * 0.39, 58, 0.1, 2.2, w * 0.7)

static func _show11(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, w, h, ["#0E0A2A", "#1E1450", "#3A1A5A"])
	ctx.fillRect(0, 0, w, h)
	glowBlob(ctx, w * 0.3, h * 0.6, 180, "#FF4FA0", 0.35)
	glowBlob(ctx, w * 0.75, h * 0.4, 160, "#5FE3FF", 0.3)
	starField(ctx, w, h, 110, 111)
	ringedPlanet(ctx, w * 0.8, h * 0.78, 62, "#FFB36B", "#C2407A", "#FFE3A3")
	circle(ctx, w * 0.12, h * 0.8, 20)
	fill(ctx, linear(ctx, 0, h * 0.75, 0, h * 0.85, ["#E8E4F0", "#8A7AB8"]))
	ctx.strokeStyle = "rgba(255,255,255,0.5)"
	ctx.lineWidth = 2
	ctx.beginPath()
	for i in 5:
		ctx.moveTo(w * 0.12 - i * 14, h * 0.62 + i * 12)
		ctx.lineTo(w * 0.28 - i * 14, h * 0.52 + i * 12)
	ctx.stroke()
	rocket(ctx, w * 0.36, h * 0.52, 80, 1.0)
	label(ctx, "SPACE PATROL", w * 0.44, h * 0.14, {"fam": FONT.sign, "px": 50, "maxW": w * 0.74, "fill": vgrad(CHROME), "stroke": "#141040", "lw": 6, "depth": 5, "depthFill": "#3A1A6A"})
	label(ctx, "3000", w * 0.44, h * 0.3, {"fam": FONT.sign, "px": 52, "fill": vgrad(["#FFFFFF", "#FF9AD0", "#FF4FA0"]), "stroke": "#2A0E3A", "lw": 6, "glow": "#FF4FA0", "track": 8})

static func _show12(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#1A0E2E", "#3A1450", "#5A1A5A"])
	ctx.fillRect(0, 0, w, h)
	ctx.save()
	ctx.globalCompositeOperation = "lighter"
	for xac in [[0.15, 0.5, "#FF4FA0"], [0.5, 0, "#5FE3FF"], [0.85, -0.5, "#FFC23A"], [0.35, 0.25, "#52E04A"], [0.65, -0.25, "#9B6BFF"]]:
		ctx.save()
		ctx.translate(w * xac[0], -10)
		ctx.rotate(xac[1])
		poly(ctx, [-6, 0, 6, 0, 60, h * 1.1, -60, h * 1.1])
		fill(ctx, linear(ctx, 0, 0, 0, h, [alpha(xac[2], 0.55), alpha(xac[2], 0.05)]))
		ctx.restore()
	ctx.restore()
	danceFloor(ctx, w, h, h * 0.72, ["#FF4FA0", "#FFC23A", "#5FE3FF", "#52E04A", "#9B6BFF"])
	mirrorBall(ctx, w / 2, h * 0.42, 34)
	var r := rng(12)
	for i in 14:
		var sx: float = r.call() * w
		var sy: float = r.call() * h * 0.7
		var sr: float = 3 + r.call() * 5
		sparkle(ctx, sx, sy, sr, 0.8)
	label(ctx, "The Groove Hour", w * 0.45, h * 0.17, {"fam": FONT.groovy, "px": 62, "maxW": w * 0.78, "fill": vgrad(["#FFFFFF", "#FFE58A", "#FFB020"]), "stroke": "#2A0A3A", "lw": 7, "depth": 6, "depthFill": "#FF4FA0", "depthStroke": "#2A0A3A", "shadow": "rgba(255,79,160,0.8)", "shadowBlur": 18})

static func _show13(ctx, w: float, h: float) -> void:
	weatherMapArt(ctx, 0, h * 0.18, w, h * 0.82, {"temps": true, "names": false})
	sunIcon(ctx, w * 0.2, h * 0.5, 30, true)
	cloud(ctx, w * 0.58, h * 0.47, 90, 42, "#FFFFFF", C.ink, 2.5)
	cloud(ctx, w * 0.8, h * 0.72, 80, 38, "#DDE3F0", C.ink, 2.5)
	ctx.strokeStyle = "#5FA8FF"
	ctx.lineWidth = 3
	ctx.beginPath()
	for i in 4:
		ctx.moveTo(w * 0.76 + i * 10, h * 0.8)
		ctx.lineTo(w * 0.74 + i * 10, h * 0.87)
	ctx.stroke()
	rr(ctx, 0, 0, w, h * 0.2, 0)
	fill(ctx, linear(ctx, 0, 0, 0, h * 0.2, ["#2A4FB8", "#1B327E"]))
	ctx.fillStyle = C.red
	ctx.fillRect(0, h * 0.2 - 6, w, 6)
	ctx.fillStyle = C.white
	ctx.fillRect(0, h * 0.2 - 9, w, 3)
	badge13(ctx, w * 0.09, h * 0.095, h * 0.068, {"ol": 2})
	label(ctx, "WEATHER WATCH", w * 0.46, h * 0.1, {"fam": FONT.sign, "px": 40, "maxW": w * 0.6, "fill": vgrad(["#FFFFFF", "#DDE6F4"]), "stroke": "#0E1A4A", "lw": 5, "depth": 3, "depthFill": "#0E1A4A", "track": 1})

static var SHOWS := {
	2: ["Precinct 13", _show2],
	4: ["Dusty Trails", _show4],
	5: ["Agent Thirteen", _show5],
	7: ["Commando Club", _show7],
	8: ["Truckers!", _show8],
	9: ["Saturday Morning Cartoons", _show9],
	11: ["Space Patrol 3000", _show11],
	12: ["The Groove Hour", _show12],
	13: ["Weather Watch 13", _show13],
}

static func shield(ctx, x: float, y: float, s: float) -> void:
	starPath(ctx, x, y, s, s * 0.62, 7, -PI / 2)
	inked(ctx, linear(ctx, 0, y - s, 0, y + s, GOLDEN), s * 0.08)
	circle(ctx, x, y, s * 0.5)
	inked(ctx, C.blue, s * 0.05)
	label(ctx, "13", x, y + s * 0.04, {"fam": FONT.round, "px": s * 0.55, "fill": "#FFFFFF"})

static func starBadge(ctx, x: float, y: float, r: float) -> void:
	circle(ctx, x, y, r)
	inked(ctx, "#F4F1E8", r * 0.1, "#1E2410")
	starPath(ctx, x, y, r * 0.78, r * 0.32, 5)
	fill(ctx, "#3E4A1E")

static func frond(ctx, x: float, y: float, ln: float, a: float) -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(a)
	ctx.beginPath()
	ctx.moveTo(0, 0)
	ctx.quadraticCurveTo(ln * 0.5, -ln * 0.1, ln, ln * 0.1)
	stroke(ctx, "#2A4A1E", 4)
	for i in range(1, 9):
		var u := i / 9.0
		var px := ln * u
		var py := -ln * 0.1 * sin(u * PI) + ln * 0.1 * u * u
		for s in [-1, 1]:
			ctx.beginPath()
			ctx.moveTo(px, py)
			ctx.quadraticCurveTo(px + 8, py + s * 18, px + 18, py + s * 30 * (1 - u * 0.5))
			stroke(ctx, "#3E6A2A" if (i & 1) else "#2F5A22", 7 - u * 3)
	ctx.restore()

## Army-stencil lettering: text with bridges cut through each glyph.
static func stencil(ctx, s: String, x: float, y: float, px: float, maxW: float, col: String) -> void:
	var c := layer("stencil:%s:%s:%s" % [s, _num(px), col], int(ceilf(maxW)) + 20, int(ceilf(px * 1.6)), func(g, lw, lh):
		label(g, s, lw / 2, lh / 2, {"fam": FONT.sign, "px": px, "maxW": maxW, "fill": col})
		g.globalCompositeOperation = "destination-out"
		setFont(g, px, FONT.sign)
		g.fillStyle = "#000"
		var tw := minf(maxW, g.measureText(s).width)
		var n := s.length()
		for i in n:
			if s[i] != " ":
				g.fillRect(lw / 2 - tw / 2 + (tw * (i + 0.5)) / n - 1.5, 0, 3, lh))
	ctx.drawImage(c, x - c.width / 2.0, y - c.height / 2.0)

static func _reg_shows() -> void:
	for n in [2, 4, 5, 7, 8, 9, 11, 12, 13]:
		card("show_%d" % n, {"w": 512, "h": 384, "opts": "osd: false hides the channel number"}, func(ctx, w, h, t, o):
			SHOWS[n][1].call(ctx, w, h)
			vignette(ctx, w, h, 0.3, "20,12,36", 0.5)
			if o.get("osd") != false:
				osd(ctx, w, h, str(n)))

# ---------------------------------------------------------------------------------------------------------
# Character-select promo backdrops (channels 2, 4, 5, 7). The 3D hero stands in the middle.
# ---------------------------------------------------------------------------------------------------------

static func _promoSkip(ctx, w: float, h: float) -> void:
	ctx.fillStyle = "#5A2A22"
	ctx.fillRect(0, 0, w, h)
	for j in 24:
		for i in range(-1, 14):
			var bx := i * 40 + (j & 1) * 20
			var by := j * 18
			rr(ctx, bx + 1.5, by + 1.5, 37, 15, 3)
			fill(ctx, mix("#8A3A2A", "#A8503A", float((i * 7 + j * 3) % 5) / 5.0))
	ctx.fillStyle = radial(ctx, w * 0.5, h * 0.35, 30, w * 0.7, ["rgba(255,210,140,0.45)", "rgba(40,16,20,0.75)"])
	ctx.fillRect(0, 0, w, h)
	for x in [0.08, 0.92]:
		ctx.save()
		ctx.globalCompositeOperation = "lighter"
		poly(ctx, [w * x - 12, h * 0.08, w * x + 12, h * 0.08, w * x + (160 if x < 0.5 else -60), h, w * x - (60 if x < 0.5 else 160), h])
		fill(ctx, linear(ctx, 0, h * 0.08, 0, h, ["rgba(255,220,150,0.5)", "rgba(255,220,150,0)"]))
		ctx.restore()
		rr(ctx, w * x - 16, h * 0.04, 32, 24, 6)
		inked(ctx, "#2A2230", 2)
		circle(ctx, w * x, h * 0.1, 8)
		fill(ctx, "#FFF4C8")
	ctx.strokeStyle = "#1E1824"
	ctx.lineWidth = 5
	ctx.beginPath()
	ctx.moveTo(0, h * 0.2)
	ctx.bezierCurveTo(w * 0.3, h * 0.34, w * 0.6, h * 0.1, w, h * 0.26)
	ctx.moveTo(0, h * 0.28)
	ctx.bezierCurveTo(w * 0.4, h * 0.4, w * 0.7, h * 0.22, w, h * 0.34)
	ctx.stroke()
	for cs in [[0.02, 0.66, 0.22, 0.34], [0.2, 0.78, 0.16, 0.22], [0.76, 0.62, 0.24, 0.38]]:
		var x: float = cs[0]
		var y: float = cs[1]
		var cw: float = cs[2]
		var chh: float = cs[3]
		rr(ctx, w * x, h * y, w * cw, h * chh, 6)
		inked(ctx, linear(ctx, 0, h * y, 0, h, ["#4A4A5A", "#2A2A38"]), 3, "#141018")
		ctx.fillStyle = "#C9CED8"
		for k in [0.1, 0.9]:
			ctx.fillRect(w * (x + cw * k) - 4, h * y, 8, h * chh)
		label(ctx, "WZTV 13", w * (x + cw / 2), h * (y + 0.1), {"fam": FONT.sign, "px": 14, "maxW": w * cw * 0.7, "fill": "#F4F1E8"})
	var sy := h * 0.06
	var sh := h * 0.16
	rr(ctx, w * 0.2, sy, w * 0.6, sh, 6)
	fill(ctx, "#1E1824")
	ctx.save()
	rr(ctx, w * 0.2, sy, w * 0.6, sh, 6)
	ctx.clip()
	for i in range(-4, 30):
		poly(ctx, [w * 0.2 + i * 18, sy, w * 0.2 + i * 18 + 9, sy, w * 0.2 + i * 18 - 6, sy + sh, w * 0.2 + i * 18 - 15, sy + sh])
		fill(ctx, "#F4C81E")
	rr(ctx, w * 0.22, sy + 6, w * 0.56, sh - 12, 4)
	fill(ctx, "#1E1824")
	ctx.restore()
	label(ctx, "BEHIND THE SCENES", w / 2, sy + sh / 2 + 1, {"fam": FONT.sign, "px": 30, "maxW": w * 0.52, "fill": "#F4C81E"})

static func _promoRoxy(ctx, w: float, h: float) -> void:
	ctx.fillStyle = radial(ctx, w / 2, h * 0.55, 10, w * 0.8, ["#FFB36B", "#E3462B", "#6B1A4A"])
	ctx.fillRect(0, 0, w, h)
	rays(ctx, w / 2, h * 0.55, w, 24, "rgba(255,79,160,0.45)", 0.05)
	ctx.save()
	ctx.globalCompositeOperation = "lighter"
	glowBlob(ctx, w / 2, h * 0.5, 180, "#FFE3A3", 0.35)
	ctx.restore()
	danceFloor(ctx, w, h, h * 0.7, ["#FF4FA0", "#FFC23A", "#5FE3FF", "#52E04A", "#FF8A2A"])
	mirrorBall(ctx, w * 0.84, h * 0.2, 30)
	var r := rng(44)
	for i in 16:
		var sx: float = r.call() * w
		var sy: float = r.call() * h * 0.65
		var sr: float = 3 + r.call() * 6
		sparkle(ctx, sx, sy, sr, 0.9)
	label(ctx, "Boogie Down", w * 0.42, h * 0.13, {"fam": FONT.groovy, "px": 56, "maxW": w * 0.7, "fill": vgrad(["#FFFFFF", "#FFE0F0", "#FF9AD0"]), "stroke": "#6A1A4A", "lw": 7, "depth": 5, "depthFill": "#3A0E2A", "rot": -0.05})
	label(ctx, "SATURDAY", w * 0.45, h * 0.27, {"fam": FONT.sign, "px": 26, "fill": "#FFE14A", "stroke": "#6A1A4A", "lw": 5, "track": 8, "rot": -0.05})

static func _promoPenny(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#2E62B8", "#234C94"])
	ctx.fillRect(0, 0, w, h)
	ctx.strokeStyle = "rgba(200,230,255,0.22)"
	ctx.lineWidth = 1
	ctx.beginPath()
	var x0 := 0.0
	while x0 < w:
		ctx.moveTo(x0 + 0.5, 0)
		ctx.lineTo(x0 + 0.5, h)
		x0 += 16
	var y0 := 0.0
	while y0 < h:
		ctx.moveTo(0, y0 + 0.5)
		ctx.lineTo(w, y0 + 0.5)
		y0 += 16
	ctx.stroke()
	ctx.strokeStyle = "rgba(220,240,255,0.75)"
	ctx.lineWidth = 2
	ctx.beginPath()
	ctx.moveTo(20, h * 0.5)
	for i in 6:
		ctx.lineTo(30 + i * 8, h * 0.5 + (-8 if (i & 1) else 8))
	ctx.lineTo(90, h * 0.5)
	ctx.lineTo(120, h * 0.5)
	ctx.moveTo(w - 130, h * 0.62)
	ctx.lineTo(w - 20, h * 0.62)
	ctx.stroke()
	for p in [[0.12, 0.72], [0.88, 0.38]]:
		var x: float = p[0]
		var y: float = p[1]
		circle(ctx, w * x, h * y, 26)
		stroke(ctx, "rgba(220,240,255,0.75)", 2)
		ctx.beginPath()
		ctx.moveTo(w * x - 10, h * y + 16); ctx.lineTo(w * x - 10, h * y - 4); ctx.lineTo(w * x + 10, h * y - 4); ctx.lineTo(w * x + 10, h * y + 16)
		ctx.moveTo(w * x - 14, h * y - 12); ctx.lineTo(w * x + 14, h * y - 12)
		ctx.stroke()
	var ox := w * 0.83
	var oy := h * 0.78
	var orr := 44.0
	rr(ctx, ox - orr - 12, oy - orr - 12, orr * 2 + 24, orr * 2 + 24, 10)
	inked(ctx, "#5A5A6A", 3, "#1E1830")
	circle(ctx, ox, oy, orr)
	fill(ctx, "#0E2A1E")
	ctx.strokeStyle = "rgba(92,255,110,0.3)"
	ctx.lineWidth = 1
	ctx.beginPath()
	for k in range(-2, 3):
		ctx.moveTo(ox - orr, oy + k * 16); ctx.lineTo(ox + orr, oy + k * 16)
		ctx.moveTo(ox + k * 16, oy - orr); ctx.lineTo(ox + k * 16, oy + orr)
	ctx.stroke()
	ctx.beginPath()
	for i in 41:
		var u := i / 40.0
		ctx.lineTo(ox - orr + u * orr * 2, oy + sin(u * TAU * 2) * 20)
	ctx.save()
	ctx.shadowColor = C.osd
	ctx.shadowBlur = 8
	stroke(ctx, C.osd, 2.5)
	ctx.restore()
	for x in [0.03, 0.97]:
		var rx := 0.0 if x < 0.5 else w - 40
		rr(ctx, rx, h * 0.12, 40, h * 0.5, 4)
		inked(ctx, "#3A3A4A", 2, "#141018")
		for j in 12:
			for i in 2:
				circle(ctx, rx + 12 + i * 16, h * 0.15 + j * 15, 3.5)
				fill(ctx, "#FF5A3C" if (i + j) % 4 == 0 else (C.osd if (i + j) % 3 == 0 else "#1E1824"))
	rr(ctx, w * 0.2, h * 0.06, w * 0.6, h * 0.17, 4)
	inked(ctx, C.white, 3, "#141018")
	ctx.fillStyle = C.orange
	ctx.fillRect(w * 0.2, h * 0.06, w * 0.04, h * 0.17)
	label(ctx, "ENGINEERING", w * 0.52, h * 0.115, {"fam": FONT.sign, "px": 26, "maxW": w * 0.5, "fill": "#1E3A7A"})
	label(ctx, "REPORT", w * 0.52, h * 0.185, {"fam": FONT.osd, "px": 30, "fill": C.orange, "track": 10})

static func _promoDuke(ctx, w: float, h: float) -> void:
	SHOWS[2][1].call(ctx, w, h)
	ctx.fillStyle = "rgba(20,16,50,0.25)"
	ctx.fillRect(0, h * 0.3, w, h * 0.7)

static var PROMOS := {
	"skip": [2, _promoSkip],
	"roxy": [4, _promoRoxy],
	"penny": [5, _promoPenny],
	"duke": [7, _promoDuke],
}

static func _reg_promos() -> void:
	for hero in HERO_IDS:
		card("promo_%s" % hero, {"w": 512, "h": 384, "opts": "osd: false hides the channel number"}, func(ctx, w, h, t, o):
			PROMOS[hero][1].call(ctx, w, h)
			vignette(ctx, w, h, 0.4, "20,12,36", 0.45)
			if o.get("osd") != false:
				osd(ctx, w, h, str(PROMOS[hero][0])))

# ---------------------------------------------------------------------------------------------------------
# Chroma-Key stock-footage worlds (16:9, sampled in screen space by the keyed shader)
# ---------------------------------------------------------------------------------------------------------

static func _worldSpace(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, w, h, ["#0A0826", "#1A1048", "#2A0E3E"])
	ctx.fillRect(0, 0, w, h)
	glowBlob(ctx, w * 0.25, h * 0.4, 170, "#FF4FA0", 0.3)
	glowBlob(ctx, w * 0.6, h * 0.7, 150, "#5FE3FF", 0.25)
	starField(ctx, w, h, 160, 5)
	ringedPlanet(ctx, w * 0.68, h * 0.46, 64, "#FFB36B", "#B5472A", "#FFE3A3")
	circle(ctx, w * 0.18, h * 0.24, 16)
	fill(ctx, linear(ctx, 0, h * 0.2, 0, h * 0.28, ["#E8E4F0", "#7A6AA8"]))

static func _worldBeach(ctx, w: float, h: float) -> void:
	var hy := h * 0.52
	ctx.fillStyle = linear(ctx, 0, 0, 0, hy, ["#3FB6F5", "#9EE0FF", "#FFE9C2"])
	ctx.fillRect(0, 0, w, hy)
	sunIcon(ctx, w * 0.78, h * 0.2, 30, false)
	cloud(ctx, w * 0.3, h * 0.2, 110, 36, "#FFFFFF")
	ctx.fillStyle = linear(ctx, 0, hy, 0, h * 0.78, ["#1E8CD8", "#2EC4D8", "#6EE6D8"])
	ctx.fillRect(0, hy, w, h * 0.3)
	ctx.strokeStyle = "rgba(255,255,255,0.8)"
	ctx.lineWidth = 3
	for j in 4:
		ctx.beginPath()
		var x := 0.0
		while x <= w:
			ctx.lineTo(x, hy + 14 + j * 16 + sin(x * 0.05 + j) * 3)
			x += 8
		ctx.stroke()
	ctx.fillStyle = linear(ctx, 0, h * 0.74, 0, h, ["#FFE3A3", "#F2C27A"])
	ctx.beginPath()
	ctx.moveTo(0, h * 0.8)
	var x2 := 0.0
	while x2 <= w:
		ctx.lineTo(x2, h * 0.78 + sin(x2 * 0.03) * 5)
		x2 += 16
	ctx.lineTo(w, h)
	ctx.lineTo(0, h)
	ctx.fill()
	palm(ctx, w * 0.1, h, h * 0.8, "#8A5A3C", "#2E9A4A")
	ctx.save()
	ctx.translate(w * 0.72, h * 0.86)
	ctx.beginPath()
	ctx.moveTo(-60, 0)
	ctx.quadraticCurveTo(0, -50, 60, 0)
	ctx.closePath()
	fill(ctx, C.red)
	ctx.save()
	ctx.clip()
	for i in range(-3, 3):
		poly(ctx, [0, -50, i * 20 + 10, 0, i * 20 + 20, 0])
		fill(ctx, "#F4F1E8")
	ctx.restore()
	capsule(ctx, 0, -40, 4, 40, 4, "#E8E4F0")
	ctx.restore()

static func _worldVolcano(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#2A0E2A", "#7A1A2A", "#E3662B"])
	ctx.fillRect(0, 0, w, h)
	var r := rng(8)
	for i in 9:
		var cx: float = w * 0.5 + (r.call() - 0.5) * 160
		var cy: float = h * 0.2 - r.call() * 40
		var cr: float = 30 + r.call() * 30
		circle(ctx, cx, cy, cr)
		fill(ctx, "rgba(60,30,50,%s)" % _num(0.5 + r.call() * 0.3))
	glowBlob(ctx, w * 0.5, h * 0.4, 200, "#FFB347", 0.55)
	poly(ctx, [w * 0.12, h, w * 0.43, h * 0.38, w * 0.57, h * 0.38, w * 0.9, h])
	fill(ctx, linear(ctx, 0, h * 0.38, 0, h, ["#5A2A3A", "#2A1424"]))
	ctx.fillStyle = "#FF8A2A"
	ctx.beginPath()
	ctx.moveTo(w * 0.47, h * 0.4)
	ctx.bezierCurveTo(w * 0.45, h * 0.6, w * 0.38, h * 0.7, w * 0.33, h)
	ctx.lineTo(w * 0.38, h)
	ctx.bezierCurveTo(w * 0.43, h * 0.72, w * 0.5, h * 0.6, w * 0.52, h * 0.4)
	ctx.fill()
	for i in 14:
		var a: float = -PI / 2 + (r.call() - 0.5) * 1.4
		var d: float = 30 + r.call() * 90
		circle(ctx, w * 0.5 + cos(a) * d, h * 0.36 + sin(a) * d, 5 + r.call() * 9)
		fill(ctx, "#FFD23A" if (i & 1) else "#FF5A2A")
	ellipse(ctx, w * 0.5, h * 0.38, w * 0.07, h * 0.03)
	fill(ctx, "#FFF1A0")

static func _worldUnderwater(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#5FD8F0", "#1E8CC8", "#0E3A7A"])
	ctx.fillRect(0, 0, w, h)
	ctx.save()
	ctx.globalCompositeOperation = "lighter"
	for i in 6:
		poly(ctx, [w * (0.1 + i * 0.16), 0, w * (0.16 + i * 0.16), 0, w * (0.26 + i * 0.14), h, w * (0.14 + i * 0.14), h])
		fill(ctx, "rgba(200,250,255,0.07)")
	ctx.restore()
	ctx.fillStyle = "#E8C98A"
	ctx.beginPath()
	ctx.moveTo(0, h * 0.86)
	ctx.quadraticCurveTo(w * 0.5, h * 0.78, w, h * 0.88)
	ctx.lineTo(w, h)
	ctx.lineTo(0, h)
	ctx.fill()
	var r := rng(15)
	for i in 7:
		var x: float = r.call() * w
		ctx.beginPath()
		ctx.moveTo(x, h)
		ctx.bezierCurveTo(x - 20, h * 0.8, x + 20, h * 0.7, x, h * (0.5 + r.call() * 0.2))
		stroke(ctx, "#2E9A4A" if (i & 1) else "#52D24A", 6)
	for fsh in [[0.3, 0.4, 26, "#FF8A2A"], [0.62, 0.3, 20, "#FFD23A"], [0.75, 0.6, 30, "#FF4FA0"], [0.45, 0.62, 16, "#FF8A2A"]]:
		fish(ctx, w * fsh[0], h * fsh[1], fsh[2], fsh[3])
	for i in 18:
		var bx: float = r.call() * w
		var by: float = r.call() * h
		var br: float = 2 + r.call() * 5
		circle(ctx, bx, by, br)
		stroke(ctx, "rgba(255,255,255,0.7)", 1.5)

static func _worldDesert(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h * 0.7, ["#6B3A6E", "#E3662B", "#FFB36B", "#FFE3A3"])
	ctx.fillRect(0, 0, w, h)
	slicedSun(ctx, w * 0.3, h * 0.6, 60, "#FFF1A0", "#FF8A3A", "#FFB36B")
	mesas(ctx, w, h * 0.68, "#8A3A5A", 44)
	ctx.fillStyle = linear(ctx, 0, h * 0.7, 0, h, ["#E08A4A", "#B8582A"])
	ctx.fillRect(0, h * 0.72, w, h)
	cactus(ctx, w * 0.82, h, h * 0.6, "#2F6A3A", "#12301C")
	circle(ctx, w * 0.55, h * 0.88, 16)
	stroke(ctx, "#8A5A2A", 2)
	circle(ctx, w * 0.55, h * 0.88, 10)
	stroke(ctx, "#A8703A", 2)

static func _worldMoon(ctx, w: float, h: float) -> void:
	ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#05061A", "#141838"])
	ctx.fillRect(0, 0, w, h)
	starField(ctx, w, h, 140, 99, 0.7)
	circle(ctx, w * 0.75, h * 0.28, 34)
	fill(ctx, linear(ctx, 0, h * 0.2, 0, h * 0.4, ["#5FB0F0", "#2A6AC0"]))
	ctx.save()
	circle(ctx, w * 0.75, h * 0.28, 34)
	ctx.clip()
	ctx.fillStyle = "#52D24A"
	ellipse(ctx, w * 0.73, h * 0.24, 14, 9, 0.4); ctx.fill()
	ellipse(ctx, w * 0.8, h * 0.34, 9, 7, 0); ctx.fill()
	ctx.restore()
	ctx.fillStyle = linear(ctx, 0, h * 0.62, 0, h, ["#D8D4E8", "#8A86A0"])
	ctx.beginPath()
	ctx.moveTo(0, h * 0.7)
	ctx.bezierCurveTo(w * 0.3, h * 0.6, w * 0.6, h * 0.72, w, h * 0.64)
	ctx.lineTo(w, h)
	ctx.lineTo(0, h)
	ctx.fill()
	var r := rng(23)
	for i in 9:
		var x: float = r.call() * w
		var y: float = h * (0.75 + r.call() * 0.2)
		var rx: float = 10 + r.call() * 24
		ellipse(ctx, x, y, rx, rx * 0.3)
		fill(ctx, "#9A96B0")
		ellipse(ctx, x + 2, y + 1, rx * 0.8, rx * 0.22)
		fill(ctx, "#B8B4CC")
	capsule(ctx, w * 0.28, h * 0.76, w * 0.28, h * 0.48, 3, "#E8E4F0")
	poly(ctx, [w * 0.28, h * 0.48, w * 0.28 + 44, h * 0.5, w * 0.28 + 40, h * 0.56, w * 0.28, h * 0.58])
	fill(ctx, C.blue)
	badge13(ctx, w * 0.28 + 21, h * 0.53, 8, {"ol": 1})

static var WORLDS := {
	"space": _worldSpace,
	"beach": _worldBeach,
	"volcano": _worldVolcano,
	"underwater": _worldUnderwater,
	"desert": _worldDesert,
	"moon": _worldMoon,
}

static func fish(ctx, x: float, y: float, s: float, col: String) -> void:
	poly(ctx, [x - s * 0.8, y, x - s * 1.3, y - s * 0.45, x - s * 1.3, y + s * 0.45])
	inked(ctx, darken(col, 0.1), 2)
	ellipse(ctx, x, y, s, s * 0.6)
	inked(ctx, linear(ctx, 0, y - s * 0.6, 0, y + s * 0.6, [lighten(col, 0.3), col]), 2)
	circle(ctx, x + s * 0.45, y - s * 0.12, s * 0.16)
	fill(ctx, "#FFFFFF")
	circle(ctx, x + s * 0.5, y - s * 0.12, s * 0.08)
	fill(ctx, C.ink)

static func _reg_worlds() -> void:
	for name in WORLDS:
		var paint: Callable = WORLDS[name]
		card("world_%s" % name, {"w": 512, "h": 288}, func(ctx, w, h, t, o):
			paint.call(ctx, w, h)
			vignette(ctx, w, h, 0.25, "20,12,36", 0.55))

# ---------------------------------------------------------------------------------------------------------
# Posters (portrait 384x512): Duke Dalton wall-buy show posters and decor posters
# ---------------------------------------------------------------------------------------------------------

## Printed-poster finish: paper grain, two faint fold creases and a white printed margin.
static func posterFinish(ctx, w: float, h: float, seed: int) -> void:
	paper(ctx, w, h, seed, 0.12)
	ctx.fillStyle = "rgba(255,255,255,0.08)"
	ctx.fillRect(w / 2 - 1.5, 0, 1.5, h)
	ctx.fillRect(0, h / 2 - 1.5, w, 1.5)
	ctx.fillStyle = "rgba(60,30,40,0.08)"
	ctx.fillRect(w / 2, 0, 1.5, h)
	ctx.fillRect(0, h / 2, w, 1.5)
	var m := 9.0
	ctx.strokeStyle = "#F6EEDC"
	ctx.lineWidth = m * 2
	ctx.strokeRect(0, 0, w, h)
	ctx.strokeStyle = "rgba(60,40,30,0.3)"
	ctx.lineWidth = 1
	ctx.strokeRect(m + 0.5, m + 0.5, w - 2 * m - 1, h - 2 * m - 1)

## Tune-in band at the foot of a show poster: station badge, air time and a small tag line.
static func tuneIn(ctx, w: float, h: float, when: String, band: String, ink: String, sub: String = "ONLY ON WZTV CHANNEL 13") -> void:
	var y := h - 86
	var bh := 68.0
	ctx.fillStyle = linear(ctx, 0, y, 0, y + bh, [lighten(band, 0.1), band])
	ctx.fillRect(0, y, w, h - y)
	ctx.fillStyle = "rgba(255,255,255,0.22)"
	ctx.fillRect(0, y, w, 3)
	ctx.fillStyle = alpha(ink, 0.5)
	ctx.fillRect(0, y + 3, w, 2)
	badge13(ctx, 50, y + bh / 2, 24, {"ol": 2})
	label(ctx, when, w * 0.58, y + bh * 0.4, {"fam": FONT.sign, "px": 27, "maxW": w * 0.64, "fill": "#FFFFFF", "stroke": ink, "lw": 4})
	label(ctx, sub, w * 0.58, y + bh * 0.78, {"fam": FONT.round, "px": 12.5, "maxW": w * 0.64, "fill": "#FFE9B0", "track": 1})

## "starring DUKE DALTON" credit line.
static func starring(ctx, x: float, y: float, name: String, col: String, ink: String) -> void:
	label(ctx, "starring", x, y - 12, {"fam": FONT.groovy, "px": 15, "fill": col, "stroke": ink, "lw": 3.5})
	label(ctx, name, x, y + 7, {"fam": FONT.sign, "px": 19, "fill": "#FFFFFF", "stroke": ink, "lw": 4.5, "track": 2})

## Wall-buy mount: a jagged burst plate with two chrome clips, where the real prop gun hangs.
static func gunMount(ctx, cx: float, cy: float, rx: float, ry: float, col: String) -> void:
	ctx.beginPath()
	for i in 44:
		var a := (i / 44.0) * TAU
		var k := 0.84 if (i & 1) else 1.0
		ctx.lineTo(cx + cos(a) * rx * k, cy + sin(a) * ry * k)
	ctx.closePath()
	ctx.save()
	ctx.shadowColor = "rgba(20,10,30,0.45)"
	ctx.shadowBlur = 10
	ctx.shadowOffsetY = 4
	fill(ctx, radial(ctx, cx, cy - ry * 0.3, ry * 0.2, rx, [lighten(col, 0.55), col, darken(col, 0.2)]))
	ctx.restore()
	stroke(ctx, C.ink, 3)
	for s in [-1, 1]:
		var x := cx + s * rx * 0.42
		var y := cy - ry * 0.18
		rr(ctx, x - 9, y - 16, 18, 32, 6)
		inked(ctx, linear(ctx, x - 9, 0, x + 9, 0, ["#8A90A8", "#FFFFFF", "#9AA2BC"]), 2)
		circle(ctx, x, y - 8, 3)
		inked(ctx, "#C9CED8", 1.2)

static func _wpPumpBg(ctx, w: float, h: float) -> void:
	desertScene(ctx, w, h, h * 0.62, 118)
	cactus(ctx, w * 0.08, h * 0.92, h * 0.34, "#2F6A3A", "#12301C")
	cactus(ctx, w * 0.94, h * 0.86, h * 0.25, "#2F6A3A", "#12301C")

static func _wpPumpTitle(ctx, w: float, h: float) -> void:
	label(ctx, "Dusty Trails", w / 2, h * 0.1, {"fam": FONT.groovy, "px": 62, "maxW": w * 0.86, "fill": vgrad(["#FFF3D0", "#F2C27A", "#D08A3A"]), "stroke": "#4A1E14", "lw": 7, "depth": 6, "depthFill": "#7A2E1E", "rot": -0.04})

static func _wpMp7Bg(ctx, w: float, h: float) -> void:
	opSpiral(ctx, w, h, w / 2, h * 0.45)

static func _wpMp7Title(ctx, w: float, h: float) -> void:
	ctx.fillStyle = "rgba(26,18,40,0.86)"
	ctx.fillRect(0, 0, w, h * 0.19)
	label(ctx, "AGENT", w / 2, h * 0.06, {"fam": FONT.sign, "px": 22, "fill": C.orange, "track": 12})
	label(ctx, "THIRTEEN", w / 2, h * 0.135, {"fam": FONT.sign, "px": 50, "maxW": w * 0.84, "fill": vgrad(["#FFFFFF", "#F6E7C8"]), "stroke": C.red, "lw": 5, "track": 3})

static func _wpM16Bg(ctx, w: float, h: float) -> void:
	jungle(ctx, w, h)

static func _wpM16Title(ctx, w: float, h: float) -> void:
	var py := h * 0.04
	var ph := h * 0.12
	rr(ctx, w * 0.07, py, w * 0.86, ph, 8)
	inked(ctx, linear(ctx, 0, py, 0, py + ph, ["#5A6A2E", "#3E4A1E"]), 4, "#1E2410")
	for sx in [0.11, 0.89]:
		circle(ctx, w * sx, py + ph / 2, 4)
		inked(ctx, "#C9CED8", 2, "#1E2410")
	stencil(ctx, "COMMANDO CLUB", w / 2, py + ph * 0.54, 38, w * 0.7, "#F4E03A")

static var WALL_POSTERS := {
	"pump_37": {"when": "SUNDAYS 7PM", "band": "#8A3A1E", "ink": "#3A120A", "burst": "#FFD23A", "seed": 37, "duke": {"outfit": "western", "hat": "cowboy"}, "bg": _wpPumpBg, "title": _wpPumpTitle},
	"mp7": {"when": "FRIDAYS 9PM", "band": "#3A2A52", "ink": "#0E0818", "burst": "#FF7A4A", "seed": 7, "duke": {"outfit": "tux"}, "bg": _wpMp7Bg, "title": _wpMp7Title},
	"m16a1": {"when": "TUESDAYS 8PM", "band": "#4A5A22", "ink": "#141A08", "burst": "#F4E03A", "seed": 16, "duke": {"outfit": "camo", "hat": "headband"}, "bg": _wpM16Bg, "title": _wpM16Title},
}

static func _reg_wallPosters() -> void:
	for gun in WALL_POSTERS:
		var P: Dictionary = WALL_POSTERS[gun]
		card("poster_%s" % gun, {"w": 384, "h": 512, "opts": "winked: true = Duke winks (after the gun is bought)"}, func(ctx, w, h, t, o):
			var hx: float = w / 2
			var hy: float = h * 0.45
			var s := 56.0
			P.bg.call(ctx, w, h)
			ctx.save()
			ctx.globalCompositeOperation = "lighter"
			glowBlob(ctx, hx, hy, w * 0.5, "#FFE9C0", 0.3)
			ctx.restore()
			var dk: Dictionary = P.duke.duplicate()
			dk.wink = bool(o.get("winked"))
			drawBust(ctx, "duke", hx, hy, s, dk)
			if o.get("winked"):
				sparkle(ctx, hx + s * 0.62, hy - s * 0.18, 17)
				sparkle(ctx, hx + s * 0.95, hy - s * 0.5, 8, 0.8)
			gunMount(ctx, w / 2, h * 0.73, w * 0.42, 46, P.burst)
			tuneIn(ctx, w, h, P.when, P.band, P.ink)
			P.title.call(ctx, w, h)
			starring(ctx, w / 2, h * 0.225, "DUKE DALTON", "#FFE9B0", P.ink)
			posterFinish(ctx, w, h, P.seed))

## Cute cartoon bat.
static func bat(ctx, x: float, y: float, s: float, col: String) -> void:
	ctx.fillStyle = col
	for sx in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(x, y - s * 0.1)
		ctx.quadraticCurveTo(x + sx * s * 0.5, y - s * 0.44, x + sx * s, y - s * 0.22)
		ctx.quadraticCurveTo(x + sx * s * 0.86, y + s * 0.02, x + sx * s * 0.7, y + s * 0.07)
		ctx.quadraticCurveTo(x + sx * s * 0.58, y - s * 0.05, x + sx * s * 0.42, y + s * 0.09)
		ctx.quadraticCurveTo(x + sx * s * 0.3, y - s * 0.01, x, y + s * 0.2)
		ctx.fill()
		poly(ctx, [x + sx * s * 0.03, y - s * 0.12, x + sx * s * 0.13, y - s * 0.32, x + sx * s * 0.16, y - s * 0.08])
		ctx.fill()
	ellipse(ctx, x, y, s * 0.17, s * 0.21)
	ctx.fill()
	for sx in [-1, 1]:
		circle(ctx, x + sx * s * 0.06, y - s * 0.04, s * 0.035)
		fill(ctx, "#FFE14A")

## Telethon goal thermometer, filled to `frac`.
static func goalThermo(ctx, x: float, top: float, bottom: float, frac: float, wd: float) -> void:
	rr(ctx, x - wd / 2, top, wd, bottom - top, wd / 2)
	inked(ctx, "#F4F1E8", 3)
	var fy := lerpf(bottom, top + wd * 0.3, frac)
	rr(ctx, x - wd * 0.28, fy, wd * 0.56, bottom - fy, wd * 0.28)
	fill(ctx, linear(ctx, x - wd * 0.3, 0, x + wd * 0.3, 0, ["#FF6A5A", C.red, "#B01E28"]))
	circle(ctx, x, bottom, wd * 0.9)
	inked(ctx, radial(ctx, x - wd * 0.3, bottom - wd * 0.3, 0, wd, ["#FF8A7A", C.red, "#A01A24"]), 3)
	ctx.strokeStyle = C.ink
	ctx.lineWidth = 2
	ctx.beginPath()
	for i in 9:
		var yy := lerpf(bottom - wd, top + wd * 0.5, i / 8.0)
		ctx.moveTo(x - wd / 2 - (5 if (i & 1) else 9), yy)
		ctx.lineTo(x - wd / 2, yy)
	ctx.stroke()

static func _reg_decorPosters() -> void:
	card("poster_spooktacular", {"w": 384, "h": 512}, func(ctx, w, h, t, o):
		ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#1B1E4A", "#3A1A5A", "#6B3A6E", "#C2407A", "#E3662B"])
		ctx.fillRect(0, 0, w, h)
		starField(ctx, w, h, 60, 13, 0.55)
		circle(ctx, w * 0.5, h * 0.5, 128)
		fill(ctx, radial(ctx, w * 0.45, h * 0.46, 10, 130, ["#FFFBEA", C.moon, "#F2D9A8"]))
		for c in [[0.36, 0.42, 16], [0.62, 0.38, 10], [0.66, 0.56, 20], [0.4, 0.6, 9]]:
			circle(ctx, w * c[0], h * c[1], c[2])
			fill(ctx, "rgba(210,180,140,0.35)")
		for b in [[0.14, 0.34, 26], [0.86, 0.3, 30], [0.2, 0.62, 18], [0.8, 0.66, 22], [0.5, 0.29, 14]]:
			bat(ctx, w * b[0], h * b[1], b[2], "#2A1640")
		drawBust(ctx, "baron", w / 2, h * 0.52, 52, {"mood": "grin", "m": 0.55})
		goalThermo(ctx, w * 0.88, h * 0.33, h * 0.72, 0.97, 18)
		label(ctx, "$13,000", w * 0.88, h * 0.3, {"fam": FONT.sign, "px": 15, "fill": "#FFE14A", "stroke": C.ink, "lw": 3.5})
		tuneIn(ctx, w, h, "SAT 11AM – MIDNIGHT", "#5A1E5A", "#1E0A28", "HOSTED BY BARON VON STATIC")
		label(ctx, "13-HOUR", w / 2, h * 0.066, {"fam": FONT.sign, "px": 24, "fill": "#FFE14A", "stroke": "#1E0A28", "lw": 5, "track": 6})
		label(ctx, "Spooktacular", w / 2, h * 0.145, {"fam": FONT.groovy, "px": 58, "maxW": w * 0.9, "fill": vgrad(["#FFE9A0", "#FFB347", "#E3662B"]), "stroke": "#1E0A28", "lw": 7, "depth": 6, "depthFill": "#6B1A6E", "rot": -0.04})
		label(ctx, "TELETHON", w / 2, h * 0.235, {"fam": FONT.sign, "px": 22, "fill": "#FFFFFF", "stroke": "#1E0A28", "lw": 5, "track": 9})
		posterFinish(ctx, w, h, 29))

	card("poster_hootie", {"w": 384, "h": 512}, func(ctx, w, h, t, o):
		ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#6EC8FF", "#BDEBFF", "#E8FAFF"])
		ctx.fillRect(0, 0, w, h)
		rays(ctx, w / 2, h * 0.62, h, 22, "rgba(255,255,255,0.28)", 0.05)
		var rb := ["#FF6B6B", "#FFA94D", "#FFE066", "#69DB7C", "#4DABF7", "#9775FA"]
		for i in rb.size():
			ctx.beginPath()
			ctx.arc(w / 2, h * 0.78, w * 0.62 - i * 18, PI, 0)
			stroke(ctx, rb[i], 19)
		cloud(ctx, w * 0.16, h * 0.4, 110, 52, "#FFFFFF", "rgba(90,140,200,0.5)", 2)
		cloud(ctx, w * 0.86, h * 0.47, 120, 56, "#FFFFFF", "rgba(90,140,200,0.5)", 2)
		ctx.fillStyle = "#8FD06A"
		ctx.beginPath()
		ctx.moveTo(0, h * 0.74)
		ctx.bezierCurveTo(w * 0.3, h * 0.68, w * 0.6, h * 0.76, w, h * 0.7)
		ctx.lineTo(w, h)
		ctx.lineTo(0, h)
		ctx.fill()
		var r := rng(31)
		for i in 12:
			var fx: float = r.call() * w
			var fy: float = h * (0.75 + r.call() * 0.08)
			var fr: float = 6 + r.call() * 3
			flower(ctx, fx, fy, fr, ["#FFFFFF", "#FFD23A", "#FF8AC8"][i % 3], "#FF8A2A")
		ellipse(ctx, w / 2, h * 0.79, 70, 11)
		fill(ctx, "rgba(40,90,40,0.3)")
		drawHootie(ctx, w / 2, h * 0.6, 92, {"wave": -0.9, "blink": false})
		for xca in [[0.08, "#FF4F5E", 0.3], [0.9, "#3FA9F5", -0.35]]:
			ctx.save()
			ctx.translate(w * xca[0], h * 0.74)
			ctx.rotate(xca[2])
			rr(ctx, -9, -70, 18, 78, 3)
			inked(ctx, xca[1], 2.5)
			poly(ctx, [-9, -70, 9, -70, 0, -92])
			inked(ctx, "#F6E7C8", 2.5)
			poly(ctx, [-3, -85, 3, -85, 0, -92])
			fill(ctx, xca[1])
			ctx.fillStyle = "rgba(255,255,255,0.35)"
			ctx.fillRect(-6, -64, 4, 66)
			ctx.restore()
		tuneIn(ctx, w, h, "WEEKDAYS 4PM", "#E0507A", "#5A1030", "FUN FOR THE WHOLE FAMILY!")
		balloonText(ctx, "HOOTIE'S", w / 2, h * 0.12, 44, 0, 0, w * 0.62)
		balloonText(ctx, "HULLABALOO", w / 2, h * 0.245, 52, 0, 2.3, w * 0.9)
		posterFinish(ctx, w, h, 41))

	card("poster_precinct13", {"w": 384, "h": 512}, func(ctx, w, h, t, o):
		ctx.fillStyle = linear(ctx, 0, 0, 0, h, ["#141638", "#2A2F6B", "#6B3A6E"])
		ctx.fillRect(0, 0, w, h)
		starField(ctx, w, h, 40, 22, 0.4)
		ctx.save()
		ctx.globalCompositeOperation = "lighter"
		for xa in [[0.2, -0.3], [0.8, 0.28]]:
			ctx.save()
			ctx.translate(w * xa[0], h * 0.85)
			ctx.rotate(xa[1])
			poly(ctx, [-8, 0, 8, 0, 60, -h, -60, -h])
			fill(ctx, linear(ctx, 0, 0, 0, -h, ["rgba(255,240,200,0.32)", "rgba(255,240,200,0)"]))
			ctx.restore()
		glowBlob(ctx, 0, h * 0.62, w * 0.6, "#FF3B30", 0.55)
		glowBlob(ctx, w, h * 0.62, w * 0.6, "#3A7BFF", 0.6)
		ctx.restore()
		skyline(ctx, w, h * 0.8, 70, 170, "#2A2358", 15, 0.15, "#8A7AD8")
		skyline(ctx, w, h * 0.9, 50, 130, "#141030", 18, 0.35)
		drawBust(ctx, "duke", w / 2, h * 0.47, 56, {"outfit": "leather"})
		tuneIn(ctx, w, h, "THURSDAYS 9PM", "#23307A", "#0A0E30", "THE TOUGHEST BEAT IN THE TRI-COUNTY")
		label(ctx, "PRECINCT", w * 0.4, h * 0.1, {"fam": FONT.sign, "px": 52, "maxW": w * 0.68, "fill": vgrad(CHROME), "stroke": "#141040", "lw": 7, "depth": 5, "depthFill": "#5A2A8A", "skew": -0.18})
		shield(ctx, w * 0.85, h * 0.1, 34)
		starring(ctx, w / 2, h * 0.215, "DUKE DALTON", "#FFB0A8", "#141040")
		posterFinish(ctx, w, h, 13))

	card("poster_boogie_down", {"w": 384, "h": 512}, func(ctx, w, h, t, o):
		ctx.fillStyle = radial(ctx, w / 2, h * 0.45, 10, h * 0.7, ["#FFE3A3", "#FFB36B", "#E3462B", "#6B1A4A"])
		ctx.fillRect(0, 0, w, h)
		rays(ctx, w / 2, h * 0.45, h, 26, "rgba(255,79,160,0.4)", 0.04)
		danceFloor(ctx, w, h, h * 0.7, ["#FF4FA0", "#FFC23A", "#5FE3FF", "#52E04A", "#FF8A2A"], 1)
		mirrorBall(ctx, w * 0.84, h * 0.3, 24)
		var r := rng(45)
		for i in 14:
			var sx: float = r.call() * w
			var sy: float = h * (0.25 + r.call() * 0.45)
			var sr: float = 3 + r.call() * 6
			sparkle(ctx, sx, sy, sr, 0.9)
		drawBust(ctx, "roxy", w / 2, h * 0.5, 46, {})
		tuneIn(ctx, w, h, "SATURDAYS 7PM", "#6B1A4A", "#2A0A1E", "GET DOWN WITH ROXY RIVERS!")
		label(ctx, "Boogie Down", w / 2, h * 0.1, {"fam": FONT.groovy, "px": 56, "maxW": w * 0.86, "fill": vgrad(["#FFFFFF", "#FFE0F0", "#FF9AD0"]), "stroke": "#6A1A4A", "lw": 7, "depth": 5, "depthFill": "#3A0E2A", "rot": -0.05})
		label(ctx, "SATURDAY", w / 2, h * 0.2, {"fam": FONT.sign, "px": 26, "fill": "#FFE14A", "stroke": "#6A1A4A", "lw": 5, "track": 8, "rot": -0.05})
		posterFinish(ctx, w, h, 77))

# ---------------------------------------------------------------------------------------------------------
# Sponsors: wordless pictogram gag posters, starburst logo cards and neon signs (GDD §10.3, §11)
# ---------------------------------------------------------------------------------------------------------

const SPONSORS := {
	"replay_ade": {"name": "Replay-Ade", "sub": "SPORTS DRINK", "tag": "GET BACK IN THE GAME!", "main": "#F4C81E", "second": "#2F5BD3", "deep": "#1B2F7A", "neon": "#FFD23A", "neon2": "#3A7BFF"},
	"wobble_up": {"name": "Wobble-Up", "sub": "GELATIN", "tag": "IT BOUNCES RIGHT BACK!", "main": "#1FB45A", "second": "#E23B3B", "deep": "#0E4A26", "neon": "#52E04A", "neon2": "#FF5FA2"},
	"jump_cut": {"name": "Jump Cut", "sub": "COFFEE", "tag": "SKIP THE WAITING!", "main": "#E3662B", "second": "#5A3A22", "deep": "#4A1E0E", "neon": "#FF8A2A", "neon2": "#FFD23A"},
	"roller_boogie": {"name": "Roller Boogie", "sub": "SKATE WAX", "tag": "NEVER STOP ROLLIN'!", "main": "#FF5FA2", "second": "#6B3A6E", "deep": "#3A1440", "neon": "#FF5FA2", "neon2": "#5FE3FF"},
	"double_vision": {"name": "Double Vision", "sub": "TOOTHPASTE", "tag": "TWICE THE SMILE!", "main": "#3FB8E8", "second": "#E23B3B", "deep": "#123A7A", "neon": "#5FE3FF", "neon2": "#FF4FA0"},
}

## 70s starburst: alternating rays around (cx, cy) with a warm centre glow.
static func starburst(ctx, w: float, h: float, cx: float, cy: float, c1: String, c2: String, n: int = 22) -> void:
	ctx.fillStyle = c1
	ctx.fillRect(0, 0, w, h)
	rays(ctx, cx, cy, Vector2(w, h).length(), n, c2, 0.08)
	ctx.fillStyle = radial(ctx, cx, cy, 0, maxf(w, h) * 0.6, ["rgba(255,250,230,0.75)", "rgba(255,250,230,0.15)", "rgba(255,250,230,0)"])
	ctx.fillRect(0, 0, w, h)

## Banner ribbon with folded tails.
static func ribbon(ctx, cx: float, cy: float, w: float, h: float, col: String) -> void:
	for s in [-1, 1]:
		var x0 := cx + s * (w / 2 - h * 0.3)
		var x1 := cx + s * (w / 2 + h * 0.85)
		poly(ctx, [x0, cy - h * 0.25, x1, cy - h * 0.25, x1 - s * h * 0.35, cy + h * 0.28, x1, cy + h * 0.8, x0, cy + h * 0.8])
		inked(ctx, darken(col, 0.3), 3)
	rr(ctx, cx - w / 2, cy - h / 2, w, h, 4)
	inked(ctx, linear(ctx, 0, cy - h / 2, 0, cy + h / 2, [lighten(col, 0.15), col]), 3)
	ctx.fillStyle = "rgba(255,255,255,0.18)"
	ctx.fillRect(cx - w / 2 + 4, cy - h / 2 + 3, w - 8, h * 0.25)

static func fist(ctx, x: float, y: float, u: float, thumb: bool = false) -> void:
	if thumb:
		capsule(ctx, x, y, x + u * 0.1, y - u * 1.15, u * 0.55, C.ink)
	circle(ctx, x, y, u * 0.62)
	fill(ctx, C.ink)

static func heart(ctx, x: float, y: float, s: float, col, lw: float) -> void:
	ctx.beginPath()
	ctx.moveTo(x, y + s * 0.38)
	ctx.bezierCurveTo(x - s * 0.95, y - s * 0.22, x - s * 0.38, y - s * 0.88, x, y - s * 0.36)
	ctx.bezierCurveTo(x + s * 0.38, y - s * 0.88, x + s * 0.95, y - s * 0.22, x, y + s * 0.38)
	inked(ctx, col, lw)

static func bananaPeel(ctx, x: float, y: float, s: float) -> void:
	for a in [-2.5, -0.65, -1.55]:
		ctx.save()
		ctx.translate(x, y)
		ctx.rotate(a + PI / 2)
		ellipse(ctx, 0, -s * 0.45, s * 0.2, s * 0.5)
		inked(ctx, "#FFE14A", s * 0.08)
		ctx.restore()
	ellipse(ctx, x, y, s * 0.32, s * 0.2)
	inked(ctx, "#F4C81E", s * 0.08)
	capsule(ctx, x, y - s * 0.1, x + s * 0.1, y - s * 0.5, s * 0.1, "#8A6A2A")

## Quick speed/motion strokes.
static func motionLines(ctx, x: float, y: float, ln: float, n: int, gap: float, col, lw: float) -> void:
	ctx.save()
	ctx.lineCap = "round"
	ctx.strokeStyle = col
	ctx.lineWidth = lw
	ctx.beginPath()
	for i in n:
		var yy := y + (i - (n - 1) / 2.0) * gap
		var l := ln * (0.7 if (i % 2) else 1.0)
		ctx.moveTo(x, yy)
		ctx.lineTo(x + l, yy)
	ctx.stroke()
	ctx.restore()

static func impactStar(ctx, x: float, y: float, r: float, col) -> void:
	starPath(ctx, x, y, r, r * 0.5, 8, 0.2)
	inked(ctx, col, r * 0.1)

static func rewindIcon(ctx, x: float, y: float, s: float, col) -> void:
	for k in [0, 1]:
		poly(ctx, [x + s * (0.1 - k * 0.55), y - s * 0.32, x + s * (0.1 - k * 0.55), y + s * 0.32, x - s * (0.38 + k * 0.55), y])
		inked(ctx, col, s * 0.07)

## Roller wheels under a pictogram foot.
static func skateFoot(ctx, x: float, y: float, u: float) -> void:
	rr(ctx, x - u * 0.9, y - u * 0.3, u * 1.8, u * 0.55, u * 0.2)
	fill(ctx, C.ink)
	for k in [-0.5, 0.5]:
		circle(ctx, x + k * u, y + u * 0.45, u * 0.38)
		inked(ctx, "#FF5FA2", u * 0.15)

static func toothbrush(ctx, x: float, y: float, ln: float, rot: float) -> void:
	ctx.save()
	ctx.translate(x, y)
	ctx.rotate(rot)
	rr(ctx, -ln * 0.06, -ln * 0.5, ln * 0.12, ln, ln * 0.06)
	inked(ctx, "#F4F1E8", ln * 0.03)
	ctx.save()
	ctx.clip()
	var cs := [C.red, C.blue, C.red]
	for i in cs.size():
		ctx.fillStyle = cs[i]
		ctx.fillRect(-ln, -ln * 0.2 + i * ln * 0.22, ln * 2, ln * 0.1)
	ctx.restore()
	rr(ctx, -ln * 0.08, -ln * 0.62, ln * 0.2, ln * 0.16, ln * 0.03)
	inked(ctx, "#FFFFFF", ln * 0.025)
	ctx.restore()

static func stopwatch(ctx, x: float, y: float, r: float, frac: float, col) -> void:
	rr(ctx, x - r * 0.18, y - r * 1.35, r * 0.36, r * 0.3, r * 0.06)
	inked(ctx, "#C9CED8", r * 0.08)
	circle(ctx, x, y, r)
	inked(ctx, "#C9CED8", r * 0.1)
	circle(ctx, x, y, r * 0.8)
	fill(ctx, "#FFFDF2")
	ctx.beginPath()
	ctx.moveTo(x, y)
	ctx.arc(x, y, r * 0.8, -PI / 2, -PI / 2 + frac * TAU)
	ctx.closePath()
	fill(ctx, col)
	ctx.strokeStyle = C.ink
	ctx.lineWidth = r * 0.06
	ctx.beginPath()
	for i in 12:
		var a := (i / 12.0) * TAU
		ctx.moveTo(x + cos(a) * r * 0.66, y + sin(a) * r * 0.66)
		ctx.lineTo(x + cos(a) * r * 0.78, y + sin(a) * r * 0.78)
	ctx.stroke()
	capsule(ctx, x, y, x, y - r * 0.62, r * 0.1, C.ink)
	circle(ctx, x, y, r * 0.1)
	fill(ctx, C.ink)

## Film-strip sprocket edges for the jump-cut panels.
static func sprockets(ctx, x: float, y: float, w: float, h: float) -> void:
	ctx.fillStyle = "#2A1D3A"
	ctx.fillRect(x, y, 14, h)
	ctx.fillRect(x + w - 14, y, 14, h)
	ctx.fillStyle = "#FFF8E8"
	var yy := y + 6
	while yy < y + h - 8:
		rr(ctx, x + 3, yy, 8, 10, 2)
		ctx.fill()
		rr(ctx, x + w - 11, yy, 8, 10, 2)
		ctx.fill()
		yy += 18

# The four wordless gag panels per sponsor: fn(ctx, cx, cy, pw, ph, S).
static func _gagReplay0(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.64
	var j := picto(ctx, cx - pw * 0.06, cy + ph * 0.08, s, {"head": [-0.3, 0.1], "la": [-18, -8], "ra": [58, -150]}, C.ink)
	ctx.save()
	ctx.translate(j.handR[0] + j.u * 0.9, j.handR[1] - j.u * 0.6)
	ctx.rotate(-1.95)
	_prod_replay_ade(ctx, 0, 0, s * 0.36)
	ctx.restore()
	for i in 3:
		ctx.beginPath()
		ctx.arc(j.head[0] - j.u * 2.2, j.head[1] - j.u * 0.4, j.u * (0.8 + i * 0.7), 2.4, 3.9)
		stroke(ctx, C.ink, 2)

static func _gagReplay1(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.58
	ctx.save()
	ctx.translate(cx - pw * 0.06, cy - ph * 0.02)
	ctx.rotate(-1.15)
	picto(ctx, 0, 0, s, {"la": [-150, -178], "ra": [150, 176], "ll": [42, 70], "rl": [-12, 14]}, C.ink)
	ctx.restore()
	bananaPeel(ctx, cx + pw * 0.2, cy + ph * 0.36, ph * 0.13)
	ctx.beginPath()
	ctx.arc(cx, cy + ph * 0.1, ph * 0.3, -2.9, -1.4)
	stroke(ctx, alpha(C.ink, 0.5), 2.5)
	for st in [[0.28, -0.3, 9], [0.36, -0.14, 6], [-0.3, -0.34, 7]]:
		starPath(ctx, cx + pw * st[0], cy + ph * st[1], st[2], st[2] * 0.45, 5)
		inked(ctx, "#FFE14A", 1.5)
	ctx.fillStyle = alpha(C.ink, 0.25)
	ctx.fillRect(cx - pw * 0.45, cy + ph * 0.42, pw * 0.9, 3)

static func _gagReplay2(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	ctx.fillStyle = linear(ctx, 0, cy - ph / 2, 0, cy + ph / 2, ["#2A3A9A", "#1B2766"])
	ctx.fillRect(cx - pw / 2, cy - ph / 2, pw, ph)
	var r := rng(5)
	for i in 7:
		ctx.fillStyle = "rgba(255,255,255,%s)" % _num(0.12 + r.call() * 0.25)
		var ly: float = cy - ph / 2 + r.call() * ph
		var lh: float = 2 + r.call() * 4
		ctx.fillRect(cx - pw / 2, ly, pw, lh)
	var s := ph * 0.52
	for e in [[0.24, -1.2, 0.25], [0.04, -0.6, 0.45], [-0.18, 0, 1]]:
		ctx.save()
		ctx.globalAlpha = e[2]
		ctx.translate(cx + pw * e[0], cy + ph * (0.12 - absf(e[1]) * 0.1))
		ctx.rotate(e[1])
		picto(ctx, 0, 0, s, {"la": [-120, -150], "ra": [120, 150]}, "#DFF4FF")
		ctx.restore()
	rewindIcon(ctx, cx + pw * 0.2, cy - ph * 0.26, ph * 0.24, "#FFE14A")

static func _gagReplay3(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	ctx.save()
	rays(ctx, cx, cy - ph * 0.05, pw, 16, alpha(S.main, 0.35), 0.1)
	ctx.restore()
	var j := picto(ctx, cx, cy + ph * 0.08, ph * 0.64, {"la": [-28, -18], "ra": [48, 172]}, C.ink)
	fist(ctx, j.handR[0], j.handR[1], j.u, true)
	for eh in [[j.elbowR, j.handR], [j.elbowL, j.handL]]:
		var mx := lerpf(eh[0][0], eh[1][0], 0.7)
		var my := lerpf(eh[0][1], eh[1][1], 0.7)
		circle(ctx, mx, my, j.u * 0.55)
		inked(ctx, S.main, 2, S.second)
	sparkle(ctx, cx + pw * 0.3, cy - ph * 0.3, 11)
	sparkle(ctx, cx - pw * 0.28, cy - ph * 0.12, 7)
	ctx.fillStyle = alpha(C.ink, 0.25)
	ctx.fillRect(cx - pw * 0.42, cy + ph * 0.45, pw * 0.84, 3)

static func _gagWobble0(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.64
	var j := picto(ctx, cx + pw * 0.04, cy + ph * 0.08, s, {"head": [0.1, 0], "la": [-55, 45], "ra": [58, -152]}, C.ink)
	_prod_wobble_up(ctx, j.handL[0] - j.u * 0.4, j.handL[1] - s * 0.12, s * 0.3)
	capsule(ctx, j.handR[0], j.handR[1], j.head[0] + j.u * 0.9, j.head[1] + j.u * 0.8, j.u * 0.35, "#C9CED8", C.ink, 1.5)
	circle(ctx, j.head[0] + j.u * 1.0, j.head[1] + j.u * 0.8, j.u * 0.45)
	inked(ctx, "#3FD27A", 1.5)

static func _gagWobble1(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var hipX := cx + pw * 0.16
	var s := ph * 0.62
	var j := picto(ctx, hipX, cy + ph * 0.08, s, {"lean": 18, "la": [-130, -160], "ra": [150, 170], "head": [0.4, 0]}, C.ink)
	var u: float = j.u
	var gx: float = j.neck[0] - u * 1.2
	var gy: float = j.neck[1] + u * 0.8
	var x0 := cx - pw / 2
	ctx.beginPath()
	ctx.moveTo(x0, gy)
	for i in range(1, 9):
		ctx.lineTo(lerpf(x0, gx - u * 1.6, i / 9.0), gy + (-u if (i & 1) else u))
	ctx.lineTo(gx - u * 1.6, gy)
	stroke(ctx, "#8A90A8", 3)
	ellipse(ctx, gx - u * 0.6, gy, u * 1.3, u * 1.1)
	inked(ctx, C.red, 2.5)
	ellipse(ctx, gx - u * 0.4, gy - u * 0.9, u * 0.5, u * 0.35, 0.4)
	inked(ctx, C.red, 2)
	rr(ctx, gx - u * 2.1, gy - u * 0.8, u * 0.6, u * 1.6, u * 0.2)
	inked(ctx, "#F4F1E8", 2)
	impactStar(ctx, gx + u * 0.8, gy - u * 0.4, u * 1.6, "#FFE14A")

static func _gagWobble2(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.64
	var hy := cy + ph * 0.08
	for da in [[-5, 0.35], [5, 0.35]]:
		ctx.save()
		ctx.globalAlpha = da[1]
		picto(ctx, cx + da[0], hy, s, {"la": [-40, -10], "ra": [40, 10], "lean": da[0] * 0.8}, "#3FD27A")
		ctx.restore()
	var j := picto(ctx, cx, hy, s, {"la": [-40, -10], "ra": [40, 10]}, "#0E7A3A")
	ctx.save()
	ctx.translate(j.head[0], j.head[1] - j.u * 0.4)
	ctx.scale(1.1, 1)
	_prod_wobble_up(ctx, 0, 0, j.u * 3.2, 0.12)
	ctx.restore()
	ctx.lineCap = "round"
	for sd in [-1, 1]:
		for k in 3:
			ctx.beginPath()
			ctx.arc(cx, hy - j.u * 2, j.u * (3.5 + k * 1.2), -0.5 if sd > 0 else PI - 0.5, 0.5 if sd > 0 else PI + 0.5)
			stroke(ctx, alpha(S.main, 0.8 - k * 0.2), 2.5)

static func _gagWobble3(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var j := picto(ctx, cx - pw * 0.12, cy + ph * 0.1, ph * 0.6, {"la": [-28, -18], "ra": [48, 172]}, C.ink)
	fist(ctx, j.handR[0], j.handR[1], j.u, true)
	_prod_wobble_up(ctx, j.head[0], j.head[1] - j.u * 0.6, j.u * 3.0, 0)
	heart(ctx, cx + pw * 0.22, cy - ph * 0.28, ph * 0.12, S.second, 2.5)
	ctx.beginPath()
	ctx.moveTo(cx + pw * 0.22, cy - ph * 0.16)
	ctx.lineTo(cx + pw * 0.22, cy - ph * 0.05)
	stroke(ctx, C.ink, 3)
	poly(ctx, [cx + pw * 0.22 - 6, cy - ph * 0.07, cx + pw * 0.22 + 6, cy - ph * 0.07, cx + pw * 0.22, cy])
	fill(ctx, C.ink)
	heart(ctx, cx + pw * 0.15, cy + ph * 0.12, ph * 0.13, S.second, 2.5)
	heart(ctx, cx + pw * 0.3, cy + ph * 0.12, ph * 0.13, S.second, 2.5)

static func _gagJump0(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.64
	var j := picto(ctx, cx - pw * 0.08, cy + ph * 0.08, s, {"head": [-0.2, 0], "la": [-18, -8], "ra": [58, -150]}, C.ink)
	_prod_jump_cut(ctx, j.handR[0] + j.u * 1.2, j.handR[1] + j.u * 0.2, s * 0.34)

static func _gagJump1(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	sprockets(ctx, cx - pw / 2, cy - ph / 2, pw, ph)
	picto(ctx, cx, cy + ph * 0.08, ph * 0.62, {"la": [-28, 100], "ra": [28, -100]}, C.ink)
	ctx.save()
	ctx.setLineDash([6, 5])
	ctx.beginPath()
	ctx.moveTo(cx - pw * 0.4, cy + ph * 0.32)
	ctx.lineTo(cx + pw * 0.4, cy - ph * 0.3)
	stroke(ctx, "#FF3B30", 3)
	ctx.restore()
	ctx.save()
	ctx.translate(cx + pw * 0.3, cy - ph * 0.32)
	ctx.rotate(-0.6)
	for s in [-1, 1]:
		capsule(ctx, 0, 0, s * 10, -18, 4, "#C9CED8", C.ink, 1.5)
		circle(ctx, s * 6, 8, 6)
		stroke(ctx, C.ink, 3)
	ctx.restore()

static func _gagJump2(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	sprockets(ctx, cx - pw / 2, cy - ph / 2, pw, ph)
	var j := picto(ctx, cx - pw * 0.1, cy + ph * 0.08, ph * 0.62, {"la": [55, 88], "ra": [70, 92]}, C.ink)
	for hnd in [j.handL, j.handR]:
		capsule(ctx, hnd[0], hnd[1], hnd[0] + j.u * 1.2, hnd[1], j.u * 0.4, C.ink)
	boltPath(ctx, cx + pw * 0.28, cy - ph * 0.22, ph * 0.26)
	inked(ctx, "#FFD23A", 2.5)
	motionLines(ctx, cx + pw * 0.18, cy - ph * 0.02, pw * 0.2, 3, 7, alpha(C.ink, 0.6), 2)

static func _gagJump3(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	stopwatch(ctx, cx - pw * 0.08, cy + ph * 0.06, ph * 0.28, 0.5, S.main)
	boltPath(ctx, cx + pw * 0.28, cy - ph * 0.12, ph * 0.32)
	inked(ctx, "#FFD23A", 2.5)
	for k in [-1, 1]:
		motionLines(ctx, cx - pw * 0.44, cy + k * ph * 0.1, pw * 0.08, 2, 6, alpha(C.ink, 0.5), 2)

static func _gagRoller0(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.64
	var j := picto(ctx, cx, cy + ph * 0.08, s, {"la": [-60, 40], "ra": [60, -40]}, C.ink)
	_prod_roller_boogie(ctx, j.handL[0] - j.u * 0.2, j.handL[1] - j.u * 0.6, s * 0.36)
	rr(ctx, j.handR[0] - j.u * 0.8, j.handR[1] - j.u * 1.4, j.u * 1.6, j.u * 1.2, j.u * 0.3)
	inked(ctx, S.main, 2)
	sparkle(ctx, j.handL[0] - j.u * 1.8, j.handL[1] - j.u * 2.2, 9)
	sparkle(ctx, j.handL[0] + j.u * 1.4, j.handL[1] - j.u * 2.6, 6)

static func _gagRoller1(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var j := picto(ctx, cx - pw * 0.36, cy + ph * 0.08, ph * 0.62, {"lean": -28, "la": [40, -30], "ra": [-70, -40], "ll": [-60, -10], "rl": [40, 90]}, C.ink)
	skateFoot(ctx, j.footL[0], j.footL[1], j.u)
	skateFoot(ctx, j.footR[0], j.footR[1], j.u)
	motionLines(ctx, cx - pw * 0.12, cy - ph * 0.05, pw * 0.5, 5, 12, alpha(C.ink, 0.7), 3)
	for c in [[0.26, 0.38, 12], [0.38, 0.34, 8], [0.16, 0.42, 7]]:
		cloud(ctx, cx + pw * c[0], cy + ph * c[1], c[2] * 2.4, c[2] * 1.4, "#EDE4D0", alpha(C.ink, 0.5), 1)

static func _gagRoller2(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	ctx.beginPath()
	for i in 61:
		var a := i * 0.2
		var rr0 := ph * 0.05 + i * ph * 0.006
		ctx.lineTo(cx + cos(a) * rr0 * 1.3, cy + sin(a) * rr0 * 0.5 + ph * 0.3)
	stroke(ctx, alpha(S.neon2, 0.8), 3)
	var r := rng(8)
	for i in 7:
		var sx: float = cx + (r.call() - 0.5) * pw * 0.8
		var sy: float = cy + ph * (0.1 + r.call() * 0.3)
		var sr: float = 4 + r.call() * 5
		sparkle(ctx, sx, sy, sr)
	var j := picto(ctx, cx, cy + ph * 0.02, ph * 0.6, {"la": [-100, -95], "ra": [100, 95], "ll": [-4, 0], "rl": [70, 110]}, C.ink)
	skateFoot(ctx, j.footL[0], j.footL[1], j.u)
	skateFoot(ctx, j.footR[0], j.footR[1], j.u)

static func _gagRoller3(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	mirrorBall(ctx, cx + pw * 0.3, cy - ph * 0.3, ph * 0.1)
	ctx.save()
	ctx.globalCompositeOperation = "multiply"
	rays(ctx, cx + pw * 0.3, cy - ph * 0.3, pw, 12, alpha(S.main, 0.25), 0.3)
	ctx.restore()
	var j := picto(ctx, cx - pw * 0.08, cy + ph * 0.06, ph * 0.6, {"la": [-30, 50], "ra": [158, 172], "ll": [-14, -6], "rl": [14, 6]}, C.ink)
	capsule(ctx, j.handR[0], j.handR[1], j.handR[0] + j.u * 0.3, j.handR[1] - j.u * 1.1, j.u * 0.4, C.ink)
	skateFoot(ctx, j.footL[0], j.footL[1], j.u)
	skateFoot(ctx, j.footR[0], j.footR[1], j.u)
	ctx.save()
	ctx.translate(cx - pw * 0.33, cy - ph * 0.04)
	ctx.beginPath()
	for i in 41:
		var a := (i / 40.0) * TAU
		ctx.lineTo(sin(a) * 18, sin(a * 2) * 8)
	stroke(ctx, C.ink, 7)
	stroke(ctx, S.main, 3.5)
	ctx.restore()

static func _gagDouble0(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var s := ph * 0.64
	var j := picto(ctx, cx - pw * 0.04, cy + ph * 0.08, s, {"la": [-18, -8], "ra": [60, -130]}, C.ink)
	toothbrush(ctx, j.handR[0] - j.u * 0.4, j.handR[1] - j.u * 0.3, s * 0.3, -1.1)
	for b in [[-1.6, -0.2, 0.5], [-1.9, 0.6, 0.35], [-1.2, 0.9, 0.3]]:
		circle(ctx, j.head[0] + b[0] * j.u, j.head[1] + b[1] * j.u, b[2] * j.u)
		inked(ctx, "#FFFFFF", 1.5)

static func _gagDouble1(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var r := ph * 0.3
	var hx := cx - pw * 0.04
	var hy := cy + ph * 0.02
	circle(ctx, hx, hy, r)
	fill(ctx, C.ink)
	ctx.beginPath()
	ctx.moveTo(hx - r * 0.62, hy + r * 0.08)
	ctx.quadraticCurveTo(hx, hy + r * 0.3, hx + r * 0.62, hy + r * 0.08)
	ctx.quadraticCurveTo(hx + r * 0.5, hy + r * 0.7, hx, hy + r * 0.72)
	ctx.quadraticCurveTo(hx - r * 0.5, hy + r * 0.7, hx - r * 0.62, hy + r * 0.08)
	fill(ctx, "#FFFFFF")
	ctx.strokeStyle = C.ink
	ctx.lineWidth = 2
	ctx.beginPath()
	for k in [-0.3, 0.0, 0.3]:
		ctx.moveTo(hx + k * r, hy + r * 0.2)
		ctx.lineTo(hx + k * r, hy + r * 0.66)
	ctx.stroke()
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.arc(hx + s * r * 0.36, hy - r * 0.2, r * 0.16, PI * 1.1, PI * 1.9)
		stroke(ctx, "#FFFFFF", 4)
	sparkle(ctx, hx + r * 0.35, hy + r * 0.35, r * 0.5)
	ctx.lineCap = "round"
	for a in [-0.9, -0.4, 0.1]:
		ctx.beginPath()
		ctx.moveTo(hx + r * 0.9 + cos(a) * r * 0.2, hy + r * 0.3 + sin(a) * r * 0.2)
		ctx.lineTo(hx + r * 0.9 + cos(a) * r * 0.55, hy + r * 0.3 + sin(a) * r * 0.55)
		stroke(ctx, C.ink, 3)

static func _gagDouble2(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	ctx.save()
	ctx.globalCompositeOperation = "multiply"
	picto(ctx, cx - pw * 0.13, cy + ph * 0.08, ph * 0.62, {"la": [-150, -170], "ra": [40, 20]}, "#3FD6E0")
	picto(ctx, cx + pw * 0.13, cy + ph * 0.08, ph * 0.62, {"la": [-40, -20], "ra": [150, 170]}, "#D64FD6")
	ctx.restore()
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(cx + s * pw * 0.06, cy - ph * 0.4)
		ctx.lineTo(cx + s * pw * 0.2, cy - ph * 0.4)
		stroke(ctx, C.ink, 2.5)
		poly(ctx, [cx + s * pw * 0.24, cy - ph * 0.4, cx + s * pw * 0.19, cy - ph * 0.44, cx + s * pw * 0.19, cy - ph * 0.36])
		fill(ctx, C.ink)

static func _gagDouble3(ctx, cx: float, cy: float, pw: float, ph: float, S: Dictionary) -> void:
	var j := picto(ctx, cx - pw * 0.28, cy + ph * 0.08, ph * 0.6, {"la": [62, 86], "ra": [78, 90]}, C.ink)
	rr(ctx, j.handR[0] - 2, j.handR[1] - 7, j.u * 2.2, j.u * 1.0, 3)
	fill(ctx, "#3A4A6B")
	var gx: float = j.handR[0] + j.u * 2.2
	var gy: float = j.handR[1] - 3
	var tx := cx + pw * 0.34
	capsule(ctx, gx, gy, tx - 14, gy, 3.5, "#FFD23A")
	ctx.save()
	ctx.globalCompositeOperation = "multiply"
	capsule(ctx, gx, gy + 9, tx - 14, gy + 9, 3.5, alpha("#3FD6E0", 0.9))
	capsule(ctx, gx, gy + 12, tx - 14, gy + 12, 3.5, alpha("#D64FD6", 0.7))
	ctx.restore()
	circle(ctx, tx, gy, ph * 0.12)
	inked(ctx, "#A9C7A4", 2.5)
	for s in [-1, 1]:
		ctx.beginPath()
		ctx.moveTo(tx + s * 8 - 4, gy - 8); ctx.lineTo(tx + s * 8 + 4, gy - 2)
		ctx.moveTo(tx + s * 8 + 4, gy - 8); ctx.lineTo(tx + s * 8 - 4, gy - 2)
		stroke(ctx, C.ink, 2)
	impactStar(ctx, tx - ph * 0.12, gy + 6, 10, "#FFE14A")

static var GAGS := {
	"replay_ade": [_gagReplay0, _gagReplay1, _gagReplay2, _gagReplay3],
	"wobble_up": [_gagWobble0, _gagWobble1, _gagWobble2, _gagWobble3],
	"jump_cut": [_gagJump0, _gagJump1, _gagJump2, _gagJump3],
	"roller_boogie": [_gagRoller0, _gagRoller1, _gagRoller2, _gagRoller3],
	"double_vision": [_gagDouble0, _gagDouble1, _gagDouble2, _gagDouble3],
}

## Comic panel frame for the gag posters.
static func gagPanel(ctx, x: float, y: float, w: float, h: float, n: int, S: Dictionary, draw: Callable) -> void:
	ctx.save()
	rr(ctx, x, y, w, h, 10)
	fill(ctx, "#FFF8E8")
	ctx.clip()
	halftone(ctx, x, y, w, h, alpha(S.main, 0.2), 10, func(u, v): return 0.15 + 0.45 * v)
	ctx.lineJoin = "round"
	draw.call(ctx, x + w / 2, y + h / 2, w, h, S)
	ctx.restore()
	rr(ctx, x, y, w, h, 10)
	stroke(ctx, C.ink, 4)
	circle(ctx, x + 17, y + 17, 12)
	inked(ctx, S.main, 2.5)
	label(ctx, str(n), x + 17, y + 18, {"fam": FONT.round, "px": 15, "fill": "#FFFFFF", "stroke": C.ink, "lw": 3})
