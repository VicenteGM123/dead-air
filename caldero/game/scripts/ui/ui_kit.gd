class_name UIKit
## Utilidades de interfaz: tema, paneles con adornos dorados, etiquetas y botones.

const BG := Color(0.075, 0.062, 0.125, 0.93)
const BG_SOFT := Color(0.12, 0.1, 0.18, 0.95)
const GOLD := Color(0.88, 0.74, 0.46)
const GOLD_BRIGHT := Color(1.0, 0.86, 0.5)
const TEXT := Color(0.97, 0.93, 0.85)
const MUTED := Color(0.74, 0.7, 0.8)
const GOOD := Color(0.62, 0.92, 0.62)
const BAD := Color(1.0, 0.55, 0.55)

static var font_regular: Font
static var font_bold: Font
static var font_italic: Font
static var font_sc: Font
static var font_sc_bold: Font
static var _theme: Theme

static func load_fonts() -> void:
	if font_regular:
		return
	font_regular = load("res://assets/fonts/Alegreya-Medium.ttf")
	font_bold = load("res://assets/fonts/Alegreya-Bold.ttf")
	font_italic = load("res://assets/fonts/Alegreya-MediumItalic.ttf")
	font_sc = load("res://assets/fonts/AlegreyaSC-Medium.ttf")
	font_sc_bold = load("res://assets/fonts/AlegreyaSC-Bold.ttf")

static func panel_style(bg := BG, border := GOLD, bw := 2, radius := 6, margin := 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(border.r, border.g, border.b, 0.85)
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.75
	sb.content_margin_bottom = margin * 0.75
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb

static func button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func theme() -> Theme:
	if _theme:
		return _theme
	load_fonts()
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font_regular)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font("italics_font", "RichTextLabel", font_italic)
	t.set_font_size("normal_font_size", "RichTextLabel", 24)
	t.set_font_size("bold_font_size", "RichTextLabel", 24)
	t.set_font_size("italics_font_size", "RichTextLabel", 24)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	# botones
	t.set_stylebox("normal", "Button", button_style(Color(0.16, 0.13, 0.24, 0.95), Color(GOLD.r, GOLD.g, GOLD.b, 0.55)))
	t.set_stylebox("hover", "Button", button_style(Color(0.26, 0.2, 0.36, 0.98), GOLD_BRIGHT))
	t.set_stylebox("pressed", "Button", button_style(Color(0.34, 0.26, 0.44, 1.0), GOLD_BRIGHT))
	t.set_stylebox("disabled", "Button", button_style(Color(0.12, 0.11, 0.16, 0.7), Color(0.4, 0.38, 0.45, 0.5)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.6))
	t.set_font("font", "Button", font_bold)
	t.set_font_size("font_size", "Button", 23)
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 40)
	# barras de progreso
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.05, 0.04, 0.08, 0.9)
	pb_bg.set_corner_radius_all(4)
	pb_bg.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.5)
	pb_bg.set_border_width_all(1)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = Color(0.78, 0.62, 1.0)
	pb_fg.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_font_size("font_size", "ProgressBar", 1)
	# sliders
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.2, 0.17, 0.28)
	sl.set_corner_radius_all(4)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var gr := StyleBoxFlat.new()
	gr.bg_color = GOLD
	gr.set_corner_radius_all(4)
	gr.content_margin_top = 4
	gr.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", gr)
	t.set_stylebox("grabber_area_highlight", "HSlider", gr)
	# pestañas
	t.set_stylebox("tab_selected", "TabBar", button_style(Color(0.26, 0.2, 0.36), GOLD_BRIGHT))
	t.set_stylebox("tab_unselected", "TabBar", button_style(Color(0.12, 0.1, 0.18), Color(GOLD.r, GOLD.g, GOLD.b, 0.4)))
	t.set_stylebox("tab_hovered", "TabBar", button_style(Color(0.2, 0.16, 0.28), GOLD))
	t.set_color("font_selected_color", "TabBar", GOLD_BRIGHT)
	t.set_color("font_unselected_color", "TabBar", MUTED)
	t.set_font("font", "TabBar", font_sc_bold)
	t.set_font_size("font_size", "TabBar", 24)
	# scroll
	var sg := StyleBoxFlat.new()
	sg.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.6)
	sg.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sg)
	t.set_stylebox("grabber_pressed", "VScrollBar", sg)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0, 0, 0, 0.25)
	sbg.set_corner_radius_all(4)
	sbg.content_margin_left = 6
	sbg.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", sbg)
	# check
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font("font", "CheckButton", font_regular)
	_theme = t
	return t

## Ancla un control a un punto relativo de la pantalla con un desplazamiento en píxeles.
static func place(c: Control, anchor: Vector2, offset: Vector2, size: Vector2, gh := Control.GROW_DIRECTION_END, gv := Control.GROW_DIRECTION_END) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y
	c.grow_horizontal = gh
	c.grow_vertical = gv

static func label(text: String, size := 24, color := TEXT, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	load_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func shadow(l: Label, offset := 2) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", offset)
	l.add_theme_constant_override("shadow_offset_y", offset)
	return l

static func rich(size := 24) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func button(text: String, cb: Callable, size := 23) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	return b

static func icon(path: String, scale := 3.0) -> TextureRect:
	var tr := TextureRect.new()
	var t: Texture2D = load(path)
	tr.texture = t
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(t.get_width(), t.get_height()) * scale
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Panel con adornos dorados en las esquinas (estilo menú de JRPG).
static func fancy_panel(bg := BG, margin := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, GOLD, 2, 6, margin))
	add_corners(p)
	return p

static func add_corners(p: Control) -> void:
	var tex: Texture2D = load("res://assets/ui/corner.png")
	for i in 4:
		var c := TextureRect.new()
		c.texture = tex
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(36, 36)
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.flip_h = i == 1 or i == 3
		c.flip_v = i == 2 or i == 3
		c.set_meta("corner", i)
		c.top_level = false
		p.add_child(c)
		# las esquinas no deben ocupar espacio en el contenedor
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.resized.connect(func(): _place_corners(p))
	p.sort_children.connect(func(): _place_corners(p))

static func _place_corners(p: Control) -> void:
	for c in p.get_children():
		if c is TextureRect and c.has_meta("corner"):
			var i: int = c.get_meta("corner")
			var x := 5.0 if (i == 0 or i == 2) else p.size.x - 41.0
			var y := 5.0 if (i == 0 or i == 1) else p.size.y - 41.0
			c.position = Vector2(x, y)
			c.size = Vector2(36, 36)

static func essence_chip(ess: String, amount: int, size := 20) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = Data.ESSENCES[ess]["color"]
	dot.custom_minimum_size = Vector2(size * 0.55, size * 0.55)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var txt: String = Data.ESSENCES[ess]["name"] + ("" if amount <= 0 else " %d" % amount)
	h.add_child(label(txt, size, Data.ESSENCES[ess]["color"].lerp(TEXT, 0.35), font_bold))
	return h

static func stars(n: int, scale := 1.5) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		h.add_child(icon("res://assets/icons/emote_star.png" if i < n else "res://assets/icons/emote_star_empty.png", scale))
	return h

static func dim_overlay() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.02, 0.01, 0.05, 0.62)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	return d

static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c

static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

static func divider() -> TextureRect:
	var d := icon("res://assets/ui/divider.png", 3.0)
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return d

static func pop_in(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.92, 0.92)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.15)
