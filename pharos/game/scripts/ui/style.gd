extends RefCounted
## The look of the PHAROS UI in one place: palette (from Pal), fonts, label and panel factories, tween and
## drawing helpers. Everything is built in code — no theme or image assets — so the UI stays crisp at any size.

const IVORY := Pal.UI_TEXT
const DIM := Pal.UI_DIM
const GOLD := Pal.UI_GOLD
const COIN := Pal.GOLD
const DANGER := Pal.UI_DANGER
const GOOD := Pal.UI_GOOD
const PANEL := Color(0.078, 0.071, 0.125) # #141220, used at ~60 % alpha
const INK := Color(0.045, 0.038, 0.085) # outlines and shadows
const NYX := Color("B07CFF") # the UI never uses cyan: Nyx things are violet, like the mist over the beaches
const NYX_LIGHT := Color("D9C9FF")
const FIRE := Color("FFB25A")

const CINZEL := "res://assets/fonts/Cinzel-SemiBold.ttf"
const CINZEL_BOLD := "res://assets/fonts/Cinzel-Bold.ttf"
const GARAMOND := "res://assets/fonts/EBGaramond-Medium.ttf"
const ITALIC := "res://assets/fonts/EBGaramond-Italic.ttf"

static var _fonts := {}
static var _silent_frame := -1


## A font, optionally with extra letter spacing (tracking) in pixels. Cached.
static func font(path: String, spacing: int = 0) -> Font:
	var key := path + ":" + str(spacing)
	if _fonts.has(key):
		return _fonts[key]
	var base: Font = load(path)
	var f: Font = base
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.spacing_glyph = spacing
		f = fv
	_fonts[key] = f
	return f


static func settings(path: String, size: int, col: Color = IVORY, spacing: int = 0, outline: int = 4) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font(path, spacing)
	ls.font_size = size
	ls.font_color = col
	if outline > 0:
		ls.outline_size = outline
		ls.outline_color = Color(INK, 0.4)
		ls.shadow_size = outline + 4
		ls.shadow_color = Color(INK, 0.2)
		ls.shadow_offset = Vector2(0, 2)
	return ls


## A non-interactive label with the house style (ivory, soft dark outline for legibility over bright scenes).
static func label(text: String, path: String, size: int, col: Color = IVORY, spacing: int = 0, outline: int = 4) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = settings(path, size, col, spacing, outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Dark translucent panel with a thin gold hairline and rounded corners.
static func panel(alpha: float = 0.6, radius: int = 10, line: Color = Color(Pal.UI_GOLD, 0.42), margin: float = 14.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL, alpha)
	sb.border_color = line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.14)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func box(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


## A tween that keeps running during pause and ignores hit-stop (Engine.time_scale).
static func tween(n: Node) -> Tween:
	var t := n.create_tween()
	t.set_ignore_time_scale(true)
	return t


## Real seconds for this frame, undoing Engine.time_scale (hit-stop, bot speed-ups).
static func rdelta(delta: float) -> float:
	return minf(delta / maxf(Engine.time_scale, 0.001), 0.1)


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Gives focus without the navigation sound (used when a screen opens).
static func focus_quiet(c: Control) -> void:
	_silent_frame = Engine.get_process_frames()
	c.grab_focus()


static func is_quiet() -> bool:
	return Engine.get_process_frames() == _silent_frame


static func sfx(n: String) -> void:
	Sfx.play(n, Vector3.INF, -4.0)


# --- drawing -----------------------------------------------------------------------------------------------

static func tracked_width(f: Font, text: String, size: int, tracking: float) -> float:
	var w := 0.0
	for i in text.length():
		w += f.get_char_size(text.unicode_at(i), size).x
	return w + tracking * maxf(0.0, float(text.length() - 1))


## Draws `text` glyph by glyph so the letter spacing can animate smoothly. `align` 0 = left, 1 = centre.
## `reveal` (0..1) fades the letters in from the centre outwards.
static func draw_tracked(ci: CanvasItem, f: Font, text: String, size: int, pos: Vector2, tracking: float, col: Color, align: int = 1, outline: int = 6, reveal: float = 1.0) -> void:
	var n := text.length()
	if n == 0:
		return
	var w := tracked_width(f, text, size, tracking)
	var x0 := pos.x - (w * 0.5 if align == 1 else 0.0)
	for p in 2:
		var x := x0
		for i in n:
			var c := text.unicode_at(i)
			var adv := f.get_char_size(c, size).x
			var a := 1.0
			if reveal < 1.0:
				var from_mid := absf((float(i) + 0.5) / float(n) - 0.5) * 2.0
				a = clampf((reveal * 1.6 - from_mid * 0.6) / 1.0, 0.0, 1.0)
			if a > 0.0:
				if p == 0:
					if outline > 0:
						ci.draw_char_outline(f, Vector2(x, pos.y + 2.0), text[i], size, outline + 4, Color(INK, 0.16 * col.a * a))
						ci.draw_char_outline(f, Vector2(x, pos.y), text[i], size, outline, Color(INK, 0.42 * col.a * a))
				else:
					ci.draw_char(f, Vector2(x, pos.y), text[i], size, Color(col, col.a * a))
			x += adv + tracking


## Outlined single-line string; `align` 0 = left, 1 = centre, 2 = right of pos.x.
static func draw_text(ci: CanvasItem, f: Font, text: String, size: int, pos: Vector2, col: Color, align: int = 1, outline: int = 4) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	if outline > 0:
		ci.draw_string_outline(f, Vector2(x, pos.y + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline + 4, Color(INK, 0.16 * col.a))
		ci.draw_string_outline(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(INK, 0.42 * col.a))
	ci.draw_string(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## A rectangle whose alpha fades to zero at every edge: a soft dark band that keeps text legible over a
## bright scene without looking like a box.
static func draw_soft_band(ci: CanvasItem, r: Rect2, col: Color, inner_x: float = 0.25, inner_y: float = 0.3) -> void:
	var xs := [r.position.x, r.position.x + r.size.x * inner_x, r.end.x - r.size.x * inner_x, r.end.x]
	var ys := [r.position.y, r.position.y + r.size.y * inner_y, r.end.y - r.size.y * inner_y, r.end.y]
	var clear := Color(col, 0.0)
	for j in 3:
		for i in 3:
			var pts := PackedVector2Array([Vector2(xs[i], ys[j]), Vector2(xs[i + 1], ys[j]), Vector2(xs[i + 1], ys[j + 1]), Vector2(xs[i], ys[j + 1])])
			var cols := PackedColorArray()
			for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var inside: bool = k[0] >= 1 and k[0] <= 2 and k[1] >= 1 and k[1] <= 2
				cols.append(col if inside else clear)
			ci.draw_polygon(pts, cols)


static func draw_diamond(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## Hairline – diamond – hairline separator, fading at the ends.
static func draw_rule(ci: CanvasItem, c: Vector2, half_w: float, col: Color) -> void:
	var gap := 9.0
	var steps := 6
	for side in [-1.0, 1.0]:
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var a := 1.0 - t0
			var x0: float = c.x + side * (gap + (half_w - gap) * t0)
			var x1: float = c.x + side * (gap + (half_w - gap) * t1)
			ci.draw_line(Vector2(x0, c.y), Vector2(x1, c.y), Color(col, col.a * a * 0.85), 1.0, true)
	draw_diamond(ci, c, 3.5, col)


## A band of Greek key (meander): square hooks standing on a baseline, a hairline above, fading at both ends.
## `h` is the height of one key; keep it >= 12 px or the pattern turns into noise.
static func draw_meander(ci: CanvasItem, c: Vector2, half_w: float, h: float, col: Color) -> void:
	var cell := h / 4.0
	var unit := cell * 5.0
	var n := int(half_w * 2.0 / unit)
	if n < 1:
		return
	var lw := clampf(h * 0.1, 1.0, 1.6)
	var x0 := c.x - n * unit * 0.5
	var y0 := c.y - h * 0.5
	for i in n:
		var t := absf((float(i) + 0.5) / n - 0.5) * 2.0
		var a := col.a * clampf(1.2 - t * t * 1.15, 0.0, 1.0)
		var cc := Color(col, a)
		var ux := x0 + i * unit
		# One key: up from the baseline, across, down, back and in — a square spiral.
		var pts := PackedVector2Array([
			Vector2(ux + cell * 0.5, y0 + 4.0 * cell), Vector2(ux + cell * 0.5, y0), Vector2(ux + 4.0 * cell, y0),
			Vector2(ux + 4.0 * cell, y0 + 3.0 * cell), Vector2(ux + 1.75 * cell, y0 + 3.0 * cell),
			Vector2(ux + 1.75 * cell, y0 + 1.25 * cell), Vector2(ux + 2.75 * cell, y0 + 1.25 * cell),
			Vector2(ux + 2.75 * cell, y0 + 2.0 * cell),
		])
		ci.draw_polyline(pts, cc, lw, true)
		ci.draw_line(Vector2(ux, y0 + 4.0 * cell), Vector2(ux + unit, y0 + 4.0 * cell), cc, lw, true)
		ci.draw_line(Vector2(ux, y0 - cell * 0.9), Vector2(ux + unit, y0 - cell * 0.9), Color(cc, a * 0.55), 1.0, true)


## Non-breaking space before "%" so "30 %" never wraps across two lines.
static func nb(text: String) -> String:
	return text.replace(" %", "\u00A0%")

