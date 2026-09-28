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
