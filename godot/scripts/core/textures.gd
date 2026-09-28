# Canvas texture helpers (runtime half of src/core/textures.js; ARCHITECTURE §6). Every helper returns a cached
# Texture2D keyed by its arguments, so equal requests share one GPU texture. Patterns are deterministic (seeded).
# The canvas helpers draw with the Canvas 2D emulation (scripts/gfx/canvas2d.gd, DACanvas: same drawing code as
# the JS, line by line); the texture is valid once the canvas has rendered (next frame).
# staticNoise() is the single animated TV-snow texture shared by zombie eyes and snowy screens (GDD §3.5);
# Game calls tex.update() every frame, which re-randomizes it at ~24 Hz.
# Texture metadata read by the DEAD AIR materials (three keeps these on the texture): "wrap" ("repeat" | "clamp"),
# "filter" ("linear" | "nearest"), "flipY" (false for data textures: staticNoise, noise), "repeat" (Vector2, the
# JS texture.repeat of withRepeat/repeat()).
# API (JS names, static functions also reachable as game.tex.X): plaid(base, lines, scale), stripes(colors, vertical,
# count), colorBars(), text(str, opts), woodPanel(base), carpet(base, fleck), tiles(a, b, n), noise(w, h, amount),
# gradient(stops, vertical), radial(stops), poster(opts), staticNoise(), repeat(tex, rx, ry).
extends RefCounted

static var _cache := {}
static var _staticTex: ImageTexture = null
static var _static := {}

var game

func _init(g = null) -> void:
	game = g

func init() -> void:
	pass

func update(_dt = 0.0) -> void:
	if _staticTex != null:
		_staticTick()

static func _canvasClass():
	if ResourceLoader.exists("res://scripts/gfx/canvas2d.gd"):
		return load("res://scripts/gfx/canvas2d.gd")
	return null

static func _white() -> Texture2D:
	var t = _cache.get("__white")
	if t == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		t = ImageTexture.create_from_image(img)
		_cache["__white"] = t
	return t

# Cache wrapper: builder(ctx, canvas, rand) draws; returns the shared texture for `key`.
static func _cached(key: String, w: int, h: int, builder: Callable, opts := {}) -> Texture2D:
	var t = _cache.get(key)
	if t != null:
		return t
	var C = _canvasClass()
	if C == null:
		push_warning("[textures] DACanvas (scripts/gfx/canvas2d.gd) missing: '%s' is blank" % key)
		return _white()
	var canvas = C.new(w, h)
	var ctx = canvas.getContext("2d")
	builder.call(ctx, canvas, Rng.mulberry32(Rng.hashStr(key)))
	if canvas.has_method("redraw"):
		canvas.redraw()
	t = canvas.texture
	if t == null:
		return _white()
	t.set_meta("wrap", "repeat" if opts.get("repeat", true) else "clamp")
	t.set_meta("canvas", canvas)   # keeps the canvas (and its viewport) alive with the texture
	t.resource_name = key
	_cache[key] = t
	return t

static func _shade(hex: String, amt: float) -> String:
	var c := DAU.color(hex).srgb_to_linear()
	if amt >= 0.0:
		c = Color(c.r + (1.0 - c.r) * amt, c.g + (1.0 - c.g) * amt, c.b + (1.0 - c.b) * amt)
	else:
		c = Color(c.r * (1.0 + amt), c.g * (1.0 + amt), c.b * (1.0 + amt))
	return "#" + c.linear_to_srgb().to_html(false)

static func _ceilPow2(n: float) -> int:
	return int(pow(2.0, ceil(log(n) / log(2.0))))

# Tartan: `lines` = [[color, width(0..1 of tile), offset(0..1)], ...] woven both ways over `base`.
static func plaid(base: String, lines: Array = [], scale := 1.0) -> Texture2D:
	var t := _cached("plaid|%s|%s" % [base, JSON.stringify(lines)], 256, 256, func(ctx, _c, rand):
		ctx.fillStyle = base
		ctx.fillRect(0, 0, 256, 256)
		for L in lines:
			ctx.fillStyle = L[0]
			ctx.globalAlpha = 0.55
			ctx.fillRect(0, float(L[2]) * 256, 256, float(L[1]) * 256)
			ctx.fillRect(float(L[2]) * 256, 0, float(L[1]) * 256, 256)
		# Twill weave: fine diagonal hatching gives the cloth a woven feel.
		ctx.globalAlpha = 0.07
		ctx.strokeStyle = "#000"
		for i in range(-256, 256, 4):
			ctx.beginPath()
			ctx.moveTo(i, 256)
			ctx.lineTo(i + 256, 0)
			ctx.stroke()
		ctx.globalAlpha = 0.05
		for i in 900:
			ctx.fillStyle = "#fff" if rand.call() < 0.5 else "#000"
			ctx.fillRect(rand.call() * 256, rand.call() * 256, 2, 1)
		ctx.globalAlpha = 1)
	return withRepeat(t, scale, scale)

# Equal-width color stripes, repeated `count` bands in total.
static func stripes(colors: Array, vertical := true, count := -1) -> Texture2D:
	if count < 0:
		count = colors.size()
	var key := "stripes|%s|%s|%d" % [",".join(colors), vertical, count]
	return _cached(key, 256, 256, func(ctx, _c, _r):
		var n := maxi(1, count)
		var step := 256.0 / n
		for i in n:
			ctx.fillStyle = colors[i % colors.size()]
			if vertical:
				ctx.fillRect(floorf(i * step), 0, ceilf(step), 256)
			else:
				ctx.fillRect(0, floorf(i * step), 256, ceilf(step))
		# A soft fabric sheen between stripes.
		ctx.globalAlpha = 0.08
		ctx.fillStyle = "#000"
		for i in range(1, n):
			if vertical:
				ctx.fillRect(floorf(i * step) - 1, 0, 2, 256)
			else:
				ctx.fillRect(0, floorf(i * step) - 1, 256, 2)
		ctx.globalAlpha = 1)

# Cartoonized SMPTE color bars (GDD §3.2) with the reverse-blue strip and PLUGE row.
static func colorBars() -> Texture2D:
	return _cached("colorBars", 256, 192, func(ctx, _c, _r):
		var P := Config.PAL
		var bars: Array = Config.BARS
		var w := 256.0 / 7.0
		for i in bars.size():
			ctx.fillStyle = bars[i]
			ctx.fillRect(floorf(i * w), 0, ceilf(w), 128)
		var rev := [P.barBlue, "#141018", P.barMagenta, "#141018", P.barCyan, "#141018", P.barWhite]
		for i in rev.size():
			ctx.fillStyle = rev[i]
			ctx.fillRect(floorf(i * w), 128, ceilf(w), 16)
		var pluge := ["#1D2A5C", "#F4F1E8", "#3A1D5C", "#141018", "#0E0B12", "#141018", "#1A1620"]
		var pw := [46, 46, 46, 46, 24, 24, 24]
		var x := 0
		for i in pluge.size():
			ctx.fillStyle = pluge[i]
			ctx.fillRect(x, 144, pw[i] + 1, 48)
			x += pw[i], {"repeat": false})

# Text label. opts: { font='Bungee', size=64, color='#fff', bg=null, w, h, align='center', pad=0.18, weight='' }
static func text(str_: String, opts := {}) -> Texture2D:
	var font: String = opts.get("font", "Bungee")
	var size := float(opts.get("size", 64))
	var color: String = opts.get("color", "#ffffff")
	var bg = opts.get("bg")
	var align: String = opts.get("align", "center")
	var pad := float(opts.get("pad", 0.18))
	var weight: String = str(opts.get("weight", ""))
	var fontStr := ("%s %spx \"%s\", \"Arial Black\", sans-serif" % [weight, _num(size), font]).strip_edges()
	var lines := str_.split("\n")
	var key := "text|%s|%s" % [str_, JSON.stringify(opts)]
	if _cache.has(key):
		return _cache[key]
	var C = _canvasClass()
	var tw := 0.0
	if C != null:
		var probe = C.new(4, 4).getContext("2d")
		probe.font = fontStr
		for l in lines:
			tw = maxf(tw, float(probe.measureText(l).width))
	var w: int = int(opts.w) if opts.get("w") else mini(1024, _ceilPow2(ceilf(tw + size * pad * 2.0)))
	var h: int = int(opts.h) if opts.get("h") else mini(1024, _ceilPow2(ceilf(size * (lines.size() * 1.2 + pad * 2.0))))
	return _cached(key, w, h, func(ctx, _c, _r):
		if bg:
			ctx.fillStyle = bg
			ctx.fillRect(0, 0, w, h)
		ctx.font = fontStr
		ctx.fillStyle = color
		ctx.textBaseline = "middle"
		ctx.textAlign = align
		var x := size * pad if align == "left" else (w - size * pad if align == "right" else w / 2.0)
		var lh := size * 1.2
		var y0 := h / 2.0 - ((lines.size() - 1) * lh) / 2.0
		for i in lines.size():
			ctx.fillText(lines[i], x, y0 + i * lh), {"repeat": false})

# JS number formatting in a CSS font string (64 -> "64", 61.44 -> "61.44").
static func _num(x: float) -> String:
	if x == floorf(x):
		return str(int(x))
	return str(x)

# Lacquered walnut paneling: vertical planks, grooves and flowing grain.
static func woodPanel(base := "#7A4A2A") -> Texture2D:
	return _cached("wood|%s" % base, 256, 256, func(ctx, _c, rand):
		ctx.fillStyle = base
		ctx.fillRect(0, 0, 256, 256)
		var planks := 4
		var pw := 256.0 / planks
		for p in planks:
			var x0 := p * pw
			ctx.fillStyle = _shade(base, (rand.call() - 0.5) * 0.16)
			ctx.fillRect(x0, 0, pw, 256)
			ctx.lineWidth = 1.2
			for g in 9:
				var gx: float = x0 + rand.call() * pw
				var amp: float = 2.0 + rand.call() * 5.0
				var freq: float = 0.01 + rand.call() * 0.02
				ctx.strokeStyle = _shade(base, -0.25 - rand.call() * 0.15)
				ctx.globalAlpha = 0.35 + rand.call() * 0.3
				ctx.beginPath()
				for y in range(0, 257, 8):
					var x := gx + sin(y * freq + g) * amp
					if y == 0:
						ctx.moveTo(x, y)
					else:
						ctx.lineTo(x, y)
				ctx.stroke()
			ctx.globalAlpha = 1
			ctx.fillStyle = _shade(base, -0.55)
			ctx.fillRect(x0, 0, 2, 256)
			ctx.fillStyle = _shade(base, 0.18)
			ctx.fillRect(x0 + 2, 0, 1, 256))

# Shag carpet: dense colored flecks over a base.
static func carpet(base := "#D9602B", fleck := "#E8A92E") -> Texture2D:
	return _cached("carpet|%s|%s" % [base, fleck], 256, 256, func(ctx, _c, rand):
		ctx.fillStyle = base
		ctx.fillRect(0, 0, 256, 256)
		var dark := _shade(base, -0.3)
		var light := _shade(base, 0.15)
		for i in 5200:
			var r: float = rand.call()
			ctx.fillStyle = dark if r < 0.45 else (light if r < 0.85 else fleck)
			ctx.globalAlpha = 0.35 + rand.call() * 0.5
			var x: float = rand.call() * 256
			var y: float = rand.call() * 256
			ctx.beginPath()
			var rx: float = 1.0 + rand.call() * 1.6
			var ry: float = 1.0 + rand.call() * 1.6
			ctx.ellipse(x, y, rx, ry, 0, 0, PI * 2)
			ctx.fill()
		ctx.globalAlpha = 1)

# Checker tiles (n x n per texture) with soft grout and a faint gloss.
static func tiles(a := "#E8E1D0", b := "#B5472A", n := 4) -> Texture2D:
	return _cached("tiles|%s|%s|%d" % [a, b, n], 256, 256, func(ctx, _c, rand):
		var s := 256.0 / n
		for y in n:
			for x in n:
				ctx.fillStyle = _shade(b if (x + y) % 2 else a, (rand.call() - 0.5) * 0.06)
				ctx.fillRect(x * s, y * s, s, s)
		ctx.strokeStyle = "rgba(40,24,30,0.35)"
		ctx.lineWidth = 2
		for i in n + 1:
			ctx.beginPath()
			ctx.moveTo(i * s, 0)
			ctx.lineTo(i * s, 256)
			ctx.stroke()
			ctx.beginPath()
			ctx.moveTo(0, i * s)
			ctx.lineTo(256, i * s)
			ctx.stroke())

# Grey value noise around mid-grey (+-amount), handy as a subtle overlay/roughness map. (Pixel data: built as an
# Image directly, exactly the JS putImageData values.)
static func noise(w := 128, h := 128, amount := 0.2) -> Texture2D:
	var key := "noise|%d|%d|%s" % [w, h, amount]
	var t = _cache.get(key)
	if t != null:
		return t
	var rand := Rng.mulberry32(Rng.hashStr(key))
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in w * h:
		var v := int(floorf(255.0 * clampf(0.5 + (rand.call() * 2.0 - 1.0) * amount, 0.0, 1.0) + 0.5))
		data[i * 4] = v
		data[i * 4 + 1] = v
		data[i * 4 + 2] = v
		data[i * 4 + 3] = 255
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	t = ImageTexture.create_from_image(img)
	t.set_meta("wrap", "repeat")
	t.resource_name = key
	_cache[key] = t
	return t

static func _addStops(g, stops: Array) -> void:
	for i in stops.size():
		var s = stops[i]
		if s is Array:
			g.addColorStop(float(s[0]), s[1])
		else:
			g.addColorStop(float(i) / maxi(1, stops.size() - 1), s)

# Linear gradient. stops: ['#a', '#b', ...] (evenly spaced) or [[0,'#a'], [1,'#b']].
static func gradient(stops: Array, vertical := true) -> Texture2D:
	var w := 4 if vertical else 256
	var h := 256 if vertical else 4
	return _cached("grad|%s|%s" % [JSON.stringify(stops), vertical], w, h, func(ctx, c, _r):
		var g = ctx.createLinearGradient(0, 0, 0, 256) if vertical else ctx.createLinearGradient(0, 0, 256, 0)
		_addStops(g, stops)
		ctx.fillStyle = g
		ctx.fillRect(0, 0, c.width, c.height), {"repeat": false})

# Radial gradient (center -> edge). stops as in gradient(); default = soft white falloff to transparent.
static func radial(stops: Array = [[0, "rgba(255,255,255,1)"], [0.45, "rgba(255,255,255,0.45)"], [1, "rgba(255,255,255,0)"]]) -> Texture2D:
	return _cached("radial|%s" % JSON.stringify(stops), 128, 128, func(ctx, _c, _r):
		var g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64)
		_addStops(g, stops)
		ctx.fillStyle = g
		ctx.fillRect(0, 0, 128, 128), {"repeat": false})

# Retro show poster: sunburst background, big title, subtitle band.
# opts: { title='WZTV', sub='CHANNEL 13', bg=PAL.harvestGold, fg=PAL.chocolate, accent=PAL.burntOrange, font='Bungee', w=256, h=384 }
static func poster(opts := {}) -> Texture2D:
	var P := Config.PAL
	var title: String = opts.get("title", "WZTV")
	var sub: String = opts.get("sub", "CHANNEL 13")
	var bg: String = opts.get("bg", P.harvestGold)
	var fg: String = opts.get("fg", P.chocolate)
	var accent: String = opts.get("accent", P.burntOrange)
	var font: String = opts.get("font", "Bungee")
	var w := int(opts.get("w", 256))
	var h := int(opts.get("h", 384))
	return _cached("poster|%s" % JSON.stringify(opts), w, h, func(ctx, _c, _r):
		ctx.fillStyle = bg
		ctx.fillRect(0, 0, w, h)
		var cx := w / 2.0
		var cy := h * 0.42
		var rays := 18
		ctx.fillStyle = accent
		ctx.globalAlpha = 0.55
		for i in rays:
			var a0 := (float(i) / rays) * PI * 2.0
			var a1 := a0 + PI / rays
			ctx.beginPath()
			ctx.moveTo(cx, cy)
			ctx.lineTo(cx + cos(a0) * h, cy + sin(a0) * h)
			ctx.lineTo(cx + cos(a1) * h, cy + sin(a1) * h)
			ctx.fill()
		ctx.globalAlpha = 1
		ctx.lineWidth = w * 0.035
		ctx.strokeStyle = fg
		ctx.strokeRect(ctx.lineWidth, ctx.lineWidth, w - ctx.lineWidth * 2, h - ctx.lineWidth * 2)
		ctx.textAlign = "center"
		ctx.textBaseline = "middle"
		var size := w * 0.24
		ctx.font = "%spx \"%s\", \"Arial Black\", sans-serif" % [_num(size), font]
		while float(ctx.measureText(title).width) > w * 0.84 and size > 8:
			size *= 0.92
			ctx.font = "%spx \"%s\", \"Arial Black\", sans-serif" % [_num(size), font]
		ctx.fillStyle = _shade(fg, -0.3)
		ctx.fillText(title, cx + 3, cy + 3)
		ctx.fillStyle = P.capWhite
		ctx.fillText(title, cx, cy)
		ctx.fillStyle = fg
		ctx.fillRect(w * 0.08, h * 0.76, w * 0.84, h * 0.13)
		ctx.fillStyle = bg
		ctx.font = "%spx \"%s\", \"Arial Black\", sans-serif" % [_num(w * 0.09), font]
		ctx.fillText(sub, cx, h * 0.825), {"repeat": false})

# Animated TV snow (singleton, 128^2 RGBA8 ImageTexture, no mipmaps, repeat, linear, flipY false like the JS
# DataTexture). tick() re-randomizes it at most ~24 times per second (real time): each frame is a random window of
# a pre-generated xorshift snow buffer (the JS per-pixel generator is far too slow in GDScript at 24 Hz), with the
# JS colour bias (R = v-6, G = v, B = v+18) and the rolling darker band (7 rows at (frame * 3) % 128, halved).
static func staticNoise() -> Texture2D:
	if _staticTex != null:
		return _staticTex
	var size := 128
	var frames := 4
	var n := size * size * frames
	var buf := PackedByteArray()
	buf.resize(n * 4)
	var half := PackedByteArray()
	half.resize(n * 4)
	var seed := 0x9E3779B9
	for i in n:
		seed = (seed ^ (seed << 13)) & 0xFFFFFFFF
		seed = seed ^ (seed >> 17)
		seed = (seed ^ (seed << 5)) & 0xFFFFFFFF
		var v := (seed >> 24) & 0xff
		var r := maxi(0, v - 6)
		var b := mini(255, v + 18)
		buf[i * 4] = r
		buf[i * 4 + 1] = v
		buf[i * 4 + 2] = b
		buf[i * 4 + 3] = 255
		half[i * 4] = r >> 1
		half[i * 4 + 1] = v >> 1
		half[i * 4 + 2] = b >> 1
		half[i * 4 + 3] = 255
	_static = {"buf": buf, "half": half, "size": size, "count": n, "frame": 0, "last": -1.0}
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	_staticTex = ImageTexture.create_from_image(img)
	_staticTex.set_meta("wrap", "repeat")
	_staticTex.set_meta("flipY", false)
	_staticTex.resource_name = "staticNoise"
	_staticTick()
	return _staticTex

static func _staticTick() -> void:
	var now := DAU.nowMs()
	var S := _static
	if S.last >= 0.0 and now - S.last < 41.0:
		return
	S.last = now
	S.frame += 1
	var size: int = S.size
	var bytes := size * size * 4
	var count: int = S.count
	var off := (randi() % (count - size * size)) * 4
	var band: int = (S.frame * 3) % size
	var b0 := band * size * 4
	var b1 := mini(size, band + 7) * size * 4
	var data: PackedByteArray = S.buf.slice(off, off + b0) + S.half.slice(off + b0, off + b1) + S.buf.slice(off + b1, off + bytes)
	_staticTex.update(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data))

# Textures are shared: a repeat is recorded as texture metadata (read by the DEAD AIR materials as the map's
# uv repeat), like the JS lightweight clone with its own .repeat.
static func withRepeat(tex: Texture2D, rx: float, ry: float) -> Texture2D:
	if rx == 1.0 and ry == 1.0:
		return tex
	tex.set_meta("repeat", Vector2(rx, ry))
	return tex

# Shared-texture repeat helper for any cached texture.
static func repeat(tex: Texture2D, rx: float, ry = null) -> Texture2D:
	return withRepeat(tex, rx, rx if ry == null else float(ry))
