extends RefCounted
## The look of the DOCE UI in one place: palette, fonts, label and panel factories, tween and drawing helpers.
## Greek pottery is the reference: black glaze (warm near-black), terracotta clay, added white (ivory) and a
## touch of added red; ornaments are meanders, rules, palmettes and laurel. Everything is drawn in code — no
## theme or image assets — so the UI stays crisp at any size.

const IVORY := Color("F6EEDD")
const DIM := Color(0.965, 0.933, 0.867, 0.62)
const GOLD := Color("EBC170")          # focus / selection
const CLAY := Color("CF7446")          # terracotta: ornaments, borders
const CLAY_LIGHT := Color("E59A66")
const CLAY_DARK := Color("A1532F")
const CLAY_BG := Color("C4683C")       # the clay ground of the friezes
const INK := Color(0.075, 0.052, 0.042) # black glaze: outlines, panels, black-figure silhouettes
const PANEL := Color(0.09, 0.064, 0.052)
const WINE := Color("6F2723")          # added red (death)
const HEALTH := Color("DE5B3E")
const STAMINA := Color("EBC170")
const BOSS := Color("D04A31")
const DANGER := Color("E8604A")
const GOOD := Color("A7D88D")

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
	var base: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
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
		ls.outline_color = Color(INK, 0.45)
		ls.shadow_size = outline + 4
		ls.shadow_color = Color(INK, 0.22)
		ls.shadow_offset = Vector2(0, 2)
	return ls


## A non-interactive label with the house style (ivory, soft dark outline for legibility over bright scenes).
static func label(text: String, path: String, size: int, col: Color = IVORY, spacing: int = 0, outline: int = 4) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = settings(path, size, col, spacing, outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Black-glaze translucent panel with a thin terracotta hairline and softly rounded corners.
static func panel(alpha: float = 0.62, radius: int = 6, line: Color = Color(CLAY, 0.55), margin: float = 14.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL, alpha)
	sb.border_color = line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.16)
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


## Real seconds for this frame, undoing Engine.time_scale (hit-stop, slow motion).
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


static func ease_back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c := 1.4
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)


## Gives focus without the navigation sound (used when a screen opens).
static func focus_quiet(c: Control) -> void:
	_silent_frame = Engine.get_process_frames()
	if is_instance_valid(c) and c.is_visible_in_tree():
		c.grab_focus()


static func is_quiet() -> bool:
	return Engine.get_process_frames() == _silent_frame


static func sfx(n: String, vol_db: float = -4.0) -> void:
	var s: Node = Engine.get_main_loop().root.get_node_or_null("Sfx") if Engine.get_main_loop() else null
	if s and s.has_method("play"):
		s.call("play", n, Vector3.INF, vol_db)


# --- drawing -----------------------------------------------------------------------------------------------

static func tracked_width(f: Font, text: String, size: int, tracking: float) -> float:
	var w := 0.0
	for i in text.length():
		w += f.get_char_size(text.unicode_at(i), size).x
	return w + tracking * maxf(0.0, float(text.length() - 1))


## Draws `text` glyph by glyph so the letter spacing can animate smoothly. `align` 0 = left, 1 = centre.
## `reveal` (0..1) fades the letters in from the centre outwards.
static func draw_tracked(ci: CanvasItem, f: Font, text: String, size: int, pos: Vector2, tracking: float, col: Color, align: int = 1, outline: int = 6, reveal: float = 1.0, ink: Color = INK) -> void:
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
						ci.draw_char_outline(f, Vector2(x, pos.y + 2.0), text[i], size, outline + 4, Color(ink, 0.16 * col.a * a))
						ci.draw_char_outline(f, Vector2(x, pos.y), text[i], size, outline, Color(ink, 0.45 * col.a * a))
				else:
					ci.draw_char(f, Vector2(x, pos.y), text[i], size, Color(col, col.a * a))
			x += adv + tracking


## Outlined single-line string; `align` 0 = left, 1 = centre, 2 = right of pos.x.
static func draw_text(ci: CanvasItem, f: Font, text: String, size: int, pos: Vector2, col: Color, align: int = 1, outline: int = 4) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	if outline > 0:
		ci.draw_string_outline(f, Vector2(x, pos.y + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline + 4, Color(INK, 0.16 * col.a))
		ci.draw_string_outline(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(INK, 0.45 * col.a))
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


## One meander key (a square spiral hook) with its top-left corner at `o`, cell size `cell` (key = 4 cells high,
## 5 wide including the gap). Used by the bands below.
static func _key_points(o: Vector2, cell: float) -> PackedVector2Array:
	return PackedVector2Array([
		o + Vector2(cell * 0.5, 4.0 * cell), o + Vector2(cell * 0.5, 0.0), o + Vector2(4.0 * cell, 0.0),
		o + Vector2(4.0 * cell, 3.0 * cell), o + Vector2(1.75 * cell, 3.0 * cell),
		o + Vector2(1.75 * cell, 1.25 * cell), o + Vector2(2.75 * cell, 1.25 * cell),
		o + Vector2(2.75 * cell, 2.0 * cell),
	])


## A band of Greek key (meander): square hooks standing on a baseline, a hairline above, fading at both ends.
## `h` is the height of one key; keep it >= 12 px or the pattern turns into noise.
static func draw_meander(ci: CanvasItem, c: Vector2, half_w: float, h: float, col: Color, fade: bool = true) -> void:
	var cell := h / 4.0
	var unit := cell * 5.0
	var n := int(half_w * 2.0 / unit)
	if n < 1:
		return
	var lw := clampf(h * 0.1, 1.0, 1.8)
	var x0 := c.x - n * unit * 0.5
	var y0 := c.y - h * 0.5
	for i in n:
		var a := col.a
		if fade:
			var t := absf((float(i) + 0.5) / n - 0.5) * 2.0
			a = col.a * clampf(1.2 - t * t * 1.15, 0.0, 1.0)
		var cc := Color(col, a)
		var ux := x0 + i * unit
		ci.draw_polyline(_key_points(Vector2(ux, y0), cell), cc, lw, true)
		ci.draw_line(Vector2(ux, y0 + 4.0 * cell), Vector2(ux + unit, y0 + 4.0 * cell), cc, lw, true)
		ci.draw_line(Vector2(ux, y0 - cell * 0.9), Vector2(ux + unit, y0 - cell * 0.9), Color(cc, a * 0.55), 1.0, true)


## A solid frieze band as painted on a vase: a strip of `bg`, a running meander of `col` between two border
## lines. `r` is the whole band; the keys fill it edge to edge (no fade).
static func draw_meander_band(ci: CanvasItem, r: Rect2, col: Color, bg: Color = Color(0, 0, 0, 0), line_w: float = 2.0) -> void:
	if bg.a > 0.0:
		ci.draw_rect(r, bg)
	var pad := r.size.y * 0.16
	var h := r.size.y - pad * 2.0
	var cell := h / 4.0
	var unit := cell * 5.0
	var n := maxi(1, int(r.size.x / unit))
	var x0 := r.position.x + (r.size.x - n * unit) * 0.5
	var y0 := r.position.y + pad
	var lw := maxf(1.0, minf(line_w, cell * 0.45))
	for i in n:
		var ux := x0 + i * unit
		ci.draw_polyline(_key_points(Vector2(ux, y0), cell), col, lw, true)
		ci.draw_line(Vector2(ux, y0 + 4.0 * cell), Vector2(ux + unit, y0 + 4.0 * cell), col, lw, true)
	ci.draw_line(Vector2(r.position.x, r.position.y + lw * 0.5), Vector2(r.end.x, r.position.y + lw * 0.5), col, lw, true)
	ci.draw_line(Vector2(r.position.x, r.end.y - lw * 0.5), Vector2(r.end.x, r.end.y - lw * 0.5), col, lw, true)


## A row of tongues (the "egg" or "ray" border of a vase): rounded drops hanging from a line.
static func draw_tongues(ci: CanvasItem, r: Rect2, col: Color, count: int = 0) -> void:
	var w := r.size.y * 0.9
	var n := count if count > 0 else maxi(1, int(r.size.x / w))
	w = r.size.x / n
	ci.draw_line(r.position, Vector2(r.end.x, r.position.y), col, 1.5, true)
	for i in n:
		var cx := r.position.x + (i + 0.5) * w
		var pts := PackedVector2Array()
		for k in 13:
			var a := PI * float(k) / 12.0
			pts.append(Vector2(cx + cos(a) * w * 0.36, r.position.y + 2.0 + sin(a) * (r.size.y - 3.0)))
		pts.append(Vector2(cx - w * 0.36, r.position.y + 2.0))
		ci.draw_colored_polygon(pts, col)


## Non-breaking space before "%" so "30 %" never wraps across two lines.
static func nb(text: String) -> String:
	return text.replace(" %", " %")
