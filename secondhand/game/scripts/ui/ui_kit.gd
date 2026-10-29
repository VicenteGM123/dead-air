class_name UIKit
## Utilidades de interfaz: tema, paneles, etiquetas y botones.
## --- SS SEED: copiado de Midnight Cauldron (scripts/ui/ui_kit.gd) con la misma API (place, label, rich, button,
## icon, fancy_panel, dim_overlay, center, vbox, hbox, pop_in, paper_style, num, ordinal, plural, clock...), pero con
## el estilo de Secondhand Stars: "taller de futuro usado" (placas de metal remachadas, pantallas CRT ámbar,
## etiquetas de papel escritas a mano), letra grande y legible (base 1280x720). Se quitó lo de Midnight Cauldron
## (esencias, esquinas doradas, papel del ticket). GOLD / GOLD_BRIGHT siguen existiendo como alias del acento ámbar.
## Si el arte de la interfaz de ART existe (assets/ui/plate9.png, screen9.png, tag9.png, btn_normal9.png...: 9-slice,
## con sus márgenes en assets/ui/ui_kit.json), se usa; si no, cajas planas con los mismos colores (la semilla).
## Lo nuevo: keycap() y prompt() (la tecla o el botón que hay que apretar; con glyph_key.png / glyph_pad_a.png si
## existen) y kit() (lee ui_kit.json).

# --- paleta (base 1280x720) ---------------------------------------------------------------------------------
const BG := Color(0.105, 0.095, 0.09, 0.94)        # placa de metal oscura (gris cálido)
const BG_SOFT := Color(0.165, 0.15, 0.14, 0.96)
const STEEL := Color(0.56, 0.52, 0.47)             # borde de metal gastado
const STEEL_DARK := Color(0.30, 0.27, 0.25)
const RIVET := Color(0.70, 0.65, 0.58)
const ACCENT := Color(1.0, 0.69, 0.27)             # ámbar de pantalla CRT
const ACCENT_BRIGHT := Color(1.0, 0.82, 0.46)
const GOLD := ACCENT                               # alias (código copiado de Midnight Cauldron)
const GOLD_BRIGHT := ACCENT_BRIGHT
const TEXT := Color(0.96, 0.93, 0.86)
const MUTED := Color(0.72, 0.68, 0.62)
const GOOD := Color(0.56, 0.88, 0.52)
const BAD := Color(1.0, 0.5, 0.42)
const PAPER := Color(0.93, 0.88, 0.76)             # etiquetas de papel
const INK := Color(0.21, 0.17, 0.15)
const SCREEN_BG := Color(0.085, 0.06, 0.035, 0.97) # pantalla CRT apagada
const SCREEN_TEXT := Color(1.0, 0.72, 0.3)

# --- tamaños de letra (base 1280x720: grandes y legibles) ---------------------------------------------------
const FS_SMALL := 16
const FS_BODY := 20
const FS_BUTTON := 21
const FS_HEAD := 26
const FS_TITLE := 40

static var font_regular: Font     # Inter Medium
static var font_bold: Font        # Inter Bold
static var font_italic: Font      # Inter Medium inclinada (FontVariation)
static var font_sc: Font          # (alias de font_bold: no hay versalitas)
static var font_sc_bold: Font
static var font_mono: Font        # Secondhand Mono (pantallas CRT, números)
static var font_hand: Font        # Caveat (etiquetas de papel)
static var _theme: Theme
static var _kit := {}
static var _kit_loaded := false

static func load_fonts() -> void:
	if font_regular:
		return
	font_regular = load("res://assets/fonts/Inter-Medium.otf")
	font_bold = load("res://assets/fonts/Inter-Bold.otf")
	var it := FontVariation.new()
	it.base_font = font_regular
	it.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	font_italic = it
	font_sc = font_bold
	font_sc_bold = font_bold
	font_mono = load("res://assets/fonts/SecondhandMono-Bold.ttf")
	font_hand = load("res://assets/fonts/Caveat-VariableFont_wght.ttf")
	# --- (de Midnight Cauldron, ronda 5) ★ ☆ ✓ ✗ ← → ... : en la web no hay fuentes del sistema; sin este respaldo
	# salen como una cajita con el código. «Secondhand Symbols» (tools/arte/fonts_ss.py) trae solo esos símbolos.
	var sym: Font = load("res://assets/fonts/SecondhandSymbols.ttf")
	if sym:
		for f in [font_regular, font_bold, font_mono, font_hand]:
			if f and not f.fallbacks.has(sym):
				f.fallbacks = f.fallbacks + [sym]
		# Caveat no trae todo: cae en Inter (y de ahí en los símbolos)
		if font_hand and not font_hand.fallbacks.has(font_regular):
			font_hand.fallbacks = [font_regular] + font_hand.fallbacks

static func panel_style(bg := BG, border := STEEL, bw := 2, radius := 4, margin := 16) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(border.r, border.g, border.b, 0.9)
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.75
	sb.content_margin_bottom = margin * 0.75
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb

## Placa de metal remachada: assets/ui/plate9.png de ART (9-slice) si existe; si no, una caja plana.
static func plate_style(margin := 16, slice := 12) -> StyleBox:
	var sb := nine("plate9.png", margin, slice)
	return sb if sb else panel_style(BG, STEEL, 2, 4, margin)

## Pantalla CRT ámbar (lecturas, precios, la aguja del test): assets/ui/screen9.png si existe.
static func screen_style(margin := 12, slice := 10) -> StyleBox:
	var sb := nine("screen9.png", margin, slice)
	if sb:
		return sb
	var f := panel_style(SCREEN_BG, Color(0.22, 0.17, 0.12), 3, 6, margin)
	f.shadow_size = 0
	return f

## Etiqueta de papel (los síntomas, los precios del estante): assets/ui/tag9.png si existe.
static func tag_style(margin := 12, slice := 10) -> StyleBox:
	var sb := nine("tag9.png", margin, slice)
	if sb:
		return sb
	var f := panel_style(PAPER, Color(0.62, 0.55, 0.44), 1, 2, margin)
	f.shadow_size = 4
	return f

## La entrada de assets/ui/ui_kit.json (ART) para un archivo: {"margin", "content", "text"...}; {} si no hay.
static func kit(file: String) -> Dictionary:
	if not _kit_loaded:
		_kit_loaded = true
		var p := "res://assets/ui/ui_kit.json"
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if d is Dictionary:
				_kit = d
	if _kit.has(file):
		return _kit[file]
	for k in _kit:   # "btn_*9.png" vale para btn_normal9.png, btn_hover9.png...
		if "*" in k and file.match(k):
			return _kit[k]
	return {}

static func kit_color(file: String, key: String, fallback: Color) -> Color:
	var v = kit(file).get(key, "")
	return Color.html(v) if v is String and Color.html_is_valid(v) else fallback

## Un 9-slice de assets/ui/<file> con los márgenes de ui_kit.json (o margin / slice si no los trae); null si falta.
static func nine(file: String, margin := 12, slice := 10) -> StyleBoxTexture:
	var path := "res://assets/ui/" + file
	if not ResourceLoader.exists(path):
		return null
	var k := kit(file)
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	var names := {SIDE_LEFT: "left", SIDE_TOP: "top", SIDE_RIGHT: "right", SIDE_BOTTOM: "bottom"}
	for side in names:
		var tm := float(k.get("margin_" + names[side], k.get("margin", slice)))
		sb.set_texture_margin(side, tm)
		# sin "content" en ui_kit.json: nunca menos que el borde dibujado (el agujero de la etiqueta, los remaches)
		sb.set_content_margin(side, float(k.get("content_" + names[side], k.get("content", maxf(float(margin), tm)))))
	return sb

static func button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4   # canto de la placa (botón "físico")
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb

static func theme() -> Theme:
	if _theme:
		return _theme
	load_fonts()
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = FS_BODY
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font_regular)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font("italics_font", "RichTextLabel", font_italic)
	t.set_font("mono_font", "RichTextLabel", font_mono)
	t.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", FS_BODY)
	t.set_font_size("italics_font_size", "RichTextLabel", FS_BODY)
	t.set_font_size("mono_font_size", "RichTextLabel", FS_BODY)
	t.set_stylebox("panel", "PanelContainer", plate_style())
	t.set_stylebox("panel", "Panel", plate_style())
	# botones: placa de metal; el borde se enciende en ámbar al pasar el cursor. Con los botones de ART
	# (assets/ui/btn_*9.png: placas claras) la letra es oscura (ui_kit.json "text").
	if ResourceLoader.exists("res://assets/ui/btn_normal9.png"):
		for st in ["normal", "hover", "pressed", "disabled"]:
			var sb := nine("btn_%s9.png" % st, 12, 15)
			if sb:
				sb.content_margin_left = maxf(sb.content_margin_left, 18.0)
				sb.content_margin_right = maxf(sb.content_margin_right, 18.0)
				t.set_stylebox(st, "Button", sb)
		var ink := kit_color("btn_normal9.png", "text", INK)
		t.set_color("font_color", "Button", ink)
		t.set_color("font_hover_color", "Button", ink)
		t.set_color("font_pressed_color", "Button", ink)
		t.set_color("font_disabled_color", "Button", kit_color("btn_normal9.png", "text_disabled", Color(0.29, 0.27, 0.26)))
	else:
		t.set_stylebox("normal", "Button", button_style(Color(0.22, 0.2, 0.19, 0.97), STEEL_DARK))
		t.set_stylebox("hover", "Button", button_style(Color(0.29, 0.26, 0.23, 0.99), ACCENT))
		t.set_stylebox("pressed", "Button", button_style(Color(0.36, 0.3, 0.24, 1.0), ACCENT_BRIGHT))
		t.set_stylebox("disabled", "Button", button_style(Color(0.15, 0.14, 0.13, 0.75), Color(0.3, 0.28, 0.27, 0.6)))
		t.set_color("font_color", "Button", TEXT)
		t.set_color("font_hover_color", "Button", ACCENT_BRIGHT)
		t.set_color("font_pressed_color", "Button", ACCENT_BRIGHT)
		t.set_color("font_disabled_color", "Button", Color(0.5, 0.48, 0.45))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font_bold)
	t.set_font_size("font_size", "Button", FS_BUTTON)
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 32)
	# barras de progreso (paciencia, el medidor de ánimo del regateo)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.05, 0.04, 0.03, 0.9)
	pb_bg.set_corner_radius_all(3)
	pb_bg.border_color = STEEL_DARK
	pb_bg.set_border_width_all(1)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = ACCENT
	pb_fg.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_font_size("font_size", "ProgressBar", 1)
	# sliders (ajustes de volumen)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.2, 0.18, 0.16)
	sl.set_corner_radius_all(3)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var gr := StyleBoxFlat.new()
	gr.bg_color = ACCENT
	gr.set_corner_radius_all(3)
	gr.content_margin_top = 4
	gr.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", gr)
	t.set_stylebox("grabber_area_highlight", "HSlider", gr)
	# scroll
	var sg := StyleBoxFlat.new()
	sg.bg_color = Color(STEEL.r, STEEL.g, STEEL.b, 0.7)
	sg.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sg)
	t.set_stylebox("grabber_pressed", "VScrollBar", sg)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0, 0, 0, 0.25)
	sbg.set_corner_radius_all(3)
	sbg.content_margin_left = 6
	sbg.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", sbg)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font("font", "CheckButton", font_regular)
	style_tooltips(t)
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

static func label(text: String, size := FS_BODY, color := TEXT, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
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

static func rich(size := FS_BODY) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func button(text: String, cb: Callable, size := FS_BUTTON) -> Button:
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

## Icono pixel art escalado (sin suavizar). Si falta el archivo, un hueco del mismo tamaño (sin error).
static func icon(path: String, scale := 3.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		tr.texture = t
		tr.custom_minimum_size = Vector2(t.get_width(), t.get_height()) * scale
	else:
		tr.custom_minimum_size = Vector2(12, 12) * scale
	return tr

## Iconos de la interfaz por nombre (credits, star, sand-timer, wrench, listen, tap, scan, tea, rep...):
## busca assets/ui/icon_<nombre>.png y luego assets/ui/<nombre>.png.
static func ui_icon(name: String, scale := 2.0) -> TextureRect:
	for p in ["res://assets/ui/icon_%s.png" % name, "res://assets/ui/%s.png" % name]:
		if ResourceLoader.exists(p):
			return icon(p, scale)
	return icon("res://assets/ui/icon_%s.png" % name, scale)

## Placa remachada con margen (el panel de las ventanas del juego). Los remaches van en las cuatro esquinas.
static func fancy_panel(bg := BG, margin := 20) -> PanelContainer:
	var p := PanelContainer.new()
	if bg == BG:
		p.add_theme_stylebox_override("panel", plate_style(margin))
	else:
		p.add_theme_stylebox_override("panel", panel_style(bg, STEEL, 2, 4, margin))
	if not ResourceLoader.exists("res://assets/ui/plate9.png"):   # la placa de ART ya trae sus remaches
		add_rivets(p)
	return p

## Cuatro remaches en las esquinas de un panel (no ocupan lugar en el contenedor).
static func add_rivets(p: Control) -> void:
	for i in 4:
		var r := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = RIVET
		sb.set_corner_radius_all(4)
		sb.border_color = Color(0.2, 0.18, 0.16)
		sb.border_width_bottom = 2
		sb.border_width_right = 1
		r.add_theme_stylebox_override("panel", sb)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_meta("rivet", i)
		r.size = Vector2(8, 8)
		p.add_child(r)
	p.resized.connect(func(): _place_rivets(p))
	p.sort_children.connect(func(): _place_rivets(p))

static func _place_rivets(p: Control) -> void:
	for c in p.get_children():
		if c is Panel and c.has_meta("rivet"):
			var i: int = c.get_meta("rivet")
			c.position = Vector2(6.0 if (i == 0 or i == 2) else p.size.x - 14.0, 6.0 if i < 2 else p.size.y - 14.0)
			c.size = Vector2(8, 8)

## Estrellas de calidad (0-3) con los símbolos ★ ☆ (fuente de respaldo), en ámbar.
static func stars(n: int, size := 26) -> Label:
	var s := ""
	for i in 3:
		s += "★" if i < n else "☆"
	return label(s, size, ACCENT_BRIGHT, font_bold)

static func dim_overlay() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.03, 0.02, 0.02, 0.6)
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

## Una línea divisoria de metal (2 px).
static func divider(width := 320) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(STEEL.r, STEEL.g, STEEL.b, 0.55)
	d.custom_minimum_size = Vector2(width, 2)
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

static func pop_in(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.94, 0.94)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.14)

## Papel (antes el ticket de Midnight Cauldron): ahora la etiqueta de papel de Secondhand Stars.
static func paper_style(margin := 14) -> StyleBox:
	return tag_style(margin)

## Los tooltips: placa oscura con borde ámbar.
static func style_tooltips(t: Theme) -> void:
	var sb := panel_style(Color(0.07, 0.06, 0.05, 0.96), ACCENT, 1, 4, 10)
	sb.shadow_size = 4
	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_color("font_color", "TooltipLabel", ACCENT_BRIGHT)
	t.set_font("font", "TooltipLabel", font_bold)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL + 1)

# --- SS SEED: la tecla o el botón que hay que apretar (el cliente lo pidió: "que aparezca el botón que tengo que
# apretar cuando me acerco a alguna persona"). keycap("E") = una tecla dibujada; prompt("E", "Repair") = [E] Repair.
# interact_key() dice qué mostrar según el último aparato usado: "E" con teclado / ratón, "A" con el mando.
## Una tecla (o botón del mando) dibujada: caja clara con canto, letra oscura. Con el mando, un círculo verde "A".
static func keycap(key: String, size := FS_BODY) -> Control:
	load_fonts()
	var pad_btn0 := key in ["A", "B"] and PadCursor.pad_in_use
	var glyph := "res://assets/ui/glyph_pad_%s.png" % key.to_lower() if pad_btn0 else "res://assets/ui/glyph_key.png"
	# --- SS CORE: todas las teclas del mismo alto y con el mismo pixel: escala entera mínima x2 desde letra 13
	# (antes una letra de 15 daba una tecla de 16 px al lado de un "Esc" dibujado de 28) y las teclas largas
	# ("Esc", "1-4", "LB", "Start") son la misma tecla de ART estirada en 9 partes, no una caja plana distinta.
	var s := maxi(2 if size >= 13 else 1, roundi(size * 1.5 / 16.0))
	var pad_named := PadCursor.pad_in_use and key in ["X", "Y"]
	if pad_btn0 and ResourceLoader.exists(glyph):
		return icon(glyph, s)    # el botón del mando de ART (ya trae su letra)
	if not pad_named and ResourceLoader.exists(glyph):
		var tex := _key_nine(s)
		if tex:
			var np := NinePatchRect.new()
			np.texture = tex
			np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			np.patch_margin_left = 2 * s
			np.patch_margin_right = 2 * s
			np.patch_margin_top = 2 * s
			np.patch_margin_bottom = 4 * s
			np.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# como la tecla de antes (TextureRect centrada): dentro de un botón alto no se estira, queda al medio
			np.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			np.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var tw := font_bold.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			np.custom_minimum_size = Vector2(maxf(16.0 * s, ceilf(tw) + 6.0 * s), 16.0 * s)
			var l0 := label(key, size, kit_color("glyph_*.png", "text", INK), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
			l0.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l0.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l0.offset_top = -s
			l0.offset_bottom = -0.5 * s
			np.add_child(l0)
			return np
	# --- end SS CORE
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var pad_btn := key in ["A", "B", "X", "Y"] and PadCursor.pad_in_use
	if pad_btn:
		var cols := {"A": Color(0.36, 0.7, 0.32), "B": Color(0.82, 0.3, 0.26), "X": Color(0.3, 0.5, 0.86), "Y": Color(0.9, 0.74, 0.26)}
		sb.bg_color = cols[key]
		sb.set_corner_radius_all(int(size))
		sb.border_color = Color(0, 0, 0, 0.35)
	else:
		sb.bg_color = Color(0.9, 0.86, 0.78)
		sb.set_corner_radius_all(4)
		sb.border_color = Color(0.45, 0.4, 0.34)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.content_margin_left = 7 if key.length() == 1 else 8
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(key, size, Color.WHITE if pad_btn else INK, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size.x = size * 0.7
	p.add_child(l)
	return p

## [tecla] Acción, sobre una placa oscura. key "" = la tecla de interactuar del aparato en uso (E o A).
static func prompt(key: String, action: String, size := FS_BODY) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := panel_style(Color(0.07, 0.06, 0.05, 0.86), ACCENT, 1, 5, 8)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := hbox(8)
	h.add_child(keycap(key if key != "" else interact_key(), size))
	h.add_child(label(action, size, TEXT, font_bold))
	p.add_child(h)
	return p

static func interact_key() -> String:
	return "A" if PadCursor.pad_in_use else "E"

# --- SS CORE: la tecla de ART (16x16) agrandada sin suavizar, una vez por escala, para estirarla en 9 partes.
static var _key_tex := {}
static func _key_nine(s: int) -> Texture2D:
	if _key_tex.has(s):
		return _key_tex[s]
	var src: Texture2D = load("res://assets/ui/glyph_key.png")
	var img: Image = src.get_image() if src else null
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(img.get_width() * s, img.get_height() * s, Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(img)
	_key_tex[s] = t
	return t
# --- end SS CORE
# --- end SS SEED

# --- (de Midnight Cauldron, ronda 5) números, ordinales, plurales y la hora a la inglesa ----------------------
## «1,241»: los miles con coma (los negativos con «-»).
static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## «1st», «2nd», «3rd», «4th», «11th», «12th», «13th», «21st», «22nd», «23rd», «101st».
static func ordinal(n: int) -> String:
	var s := "th"
	var t := absi(n) % 100
	if t < 11 or t > 13:
		match absi(n) % 10:
			1:
				s = "st"
			2:
				s = "nd"
			3:
				s = "rd"
	return "%d%s" % [n, s]

## «1 customer», «2 customers». many: el plural cuando no es solo +s.
static func plural(n: int, one: String, many := "") -> String:
	return "%s %s" % [num(n), one if n == 1 else (many if many != "" else one + "s")]

## La hora del HUD, corta y de 12 horas sin AM/PM (la tienda abre de 9 a 6): 540 -> «9:00», 780 -> «1:00».
static func clock(minutes: int) -> String:
	var h := (minutes / 60) % 12
	if h == 0:
		h = 12
	return "%d:%02d" % [h, minutes % 60]

## La hora dentro de una frase: 1080 -> «6 PM», 570 -> «9:30 AM».
static func clock_words(minutes: int) -> String:
	var h24 := (minutes / 60) % 24
	var h := h24 % 12
	if h == 0:
		h = 12
	var m := minutes % 60
	var ampm := "AM" if h24 < 12 else "PM"
	return ("%d %s" % [h, ampm]) if m == 0 else ("%d:%02d %s" % [h, m, ampm])
