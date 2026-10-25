class_name PaperKit
## --- R3 PAPER: piezas de "papel de verdad" para los paneles grandes (overlays.gd): hojas de pergamino con bordes
## deshilachados, madera, corcho, mantel, letreros, chinchetas, cinta, manchas, sellos de lacre, bocetos a tinta de
## pociones e ingredientes, iconos de esencias y letra manuscrita (Caveat, licencia OFL: assets/fonts/OFL-Caveat.txt).
## El arte sale de tools/arte/ui_art.py (bloque R3 PAPER) a assets/ui/paper_*.png.

const INK := Color("3a2618")            # tinta marrón oscuro
const INK_SOFT := Color("5e4632")       # tinta aguada (textos secundarios)
const INK_FAINT := Color(0.37, 0.28, 0.2, 0.62)   # lápiz / lo que aún no se sabe
const RED_INK := Color("a3261f")        # tinta roja (precios del encargo, avisos)
const WAX := Color("9e2b25")
const BRASS := Color("c9a15a")
const HERB := Color("4e6b3a")
const CREAM := Color("eadbb8")
const CREAM_LIGHT := Color("f7eed7")
const NIGHT := Color("3b2f52")

## Nine-patch: [textura, margen izquierdo, arriba, derecho, abajo] en píxeles de la imagen (ya guardada a x2).
const NINE := {
	"sheet": ["paper_sheet9", 24, 24, 24, 24],
	"card": ["paper_card9", 24, 24, 24, 24],
	"note": ["paper_note9", 24, 24, 24, 24],
	"bubble": ["paper_bubble9", 20, 20, 20, 20],
	"wood": ["paper_wood9", 20, 20, 20, 20],
	"cork": ["paper_cork9", 20, 20, 20, 20],
	"sign": ["paper_sign9", 20, 16, 20, 16],
	"tab": ["paper_tab9", 12, 12, 12, 12],
	"tag": ["paper_tag9", 16, 4, 4, 4],
}

static var font_hand: Font        # Caveat seminegrita: casi todo lo escrito a mano
static var font_hand_bold: Font   # Caveat negrita: nombres y números
static var _tex_cache := {}

static func load_fonts() -> void:
	if font_hand:
		return
	UIKit.load_fonts()
	var base: FontFile = load("res://assets/fonts/Caveat-VariableFont_wght.ttf")
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	var a := FontVariation.new()
	a.base_font = base
	a.variation_opentype = {tag: 560}
	a.fallbacks = [UIKit.font_regular]
	font_hand = a
	var b := FontVariation.new()
	b.base_font = base
	b.variation_opentype = {tag: 700}
	b.fallbacks = [UIKit.font_bold]
	font_hand_bold = b

static func tex(name: String) -> Texture2D:
	var path := name if name.begins_with("res://") else "res://assets/ui/%s.png" % name
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]

## Una textura de pixel art ampliada k veces sin suavizado (para iconos de botones, que no se escalan solos).
static func scaled(name: String, k := 3) -> Texture2D:
	var key := "%s@%d" % [name, k]
	if not _tex_cache.has(key):
		var t := tex(name)
		if t == null:
			_tex_cache[key] = null
		else:
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
			_tex_cache[key] = ImageTexture.create_from_image(img)
	return _tex_cache[key]

## Un nine-patch de papel, madera, corcho... content: margen interior (x: izquierda/derecha, y: arriba/abajo).
static func nine(kind: String, content := Vector2(-1, -1), modulate := Color.WHITE) -> StyleBoxTexture:
	var d: Array = NINE.get(kind, NINE["sheet"])
	if kind.begins_with("cloth_"):
		d = ["paper_%s9" % kind, 16, 16, 16, 16]
	var sb := StyleBoxTexture.new()
	sb.texture = tex(d[0])
	sb.texture_margin_left = d[1]
	sb.texture_margin_top = d[2]
	sb.texture_margin_right = d[3]
	sb.texture_margin_bottom = d[4]
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	var cx := content.x if content.x >= 0 else float(d[1]) + 10.0
	var cy := content.y if content.y >= 0 else float(d[2]) + 6.0
	sb.content_margin_left = cx
	sb.content_margin_right = cx
	sb.content_margin_top = cy
	sb.content_margin_bottom = cy
	sb.modulate_color = modulate
	return sb

static func panel(kind: String, content := Vector2(-1, -1), modulate := Color.WHITE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", nine(kind, content, modulate))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

## Una imagen de pixel art escalada sin suavizado (x3 por defecto).
static func pic(name: String, scale := 3.0) -> TextureRect:
	var tr := TextureRect.new()
	var t := tex(name)
	tr.texture = t
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if t:
		tr.custom_minimum_size = Vector2(t.get_width(), t.get_height()) * scale
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Texto escrito a mano (tinta sobre el papel).
static func hand(text: String, size := 30, color := INK, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, wrap_w := 0.0) -> Label:
	load_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_hand_bold if bold else font_hand)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -int(size * 0.18))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap_w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_w, 0)
	return l

## Un título en versalitas de tinta (Alegreya SC, como el resto del juego).
static func head(text: String, size := 36, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	UIKit.load_fonts()
	var l := UIKit.label(text, size, color, UIKit.font_sc_bold, align)
	return l

## Texto con formato (BBCode) en tinta y letra manuscrita.
static func rich(size := 30, color := INK) -> RichTextLabel:
	load_fonts()
	var r := UIKit.rich(size)
	r.add_theme_font_override("normal_font", font_hand)
	r.add_theme_font_override("bold_font", font_hand_bold)
	r.add_theme_font_override("italics_font", font_hand)
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", -int(size * 0.15))
	return r

## Un adorno (chincheta, cinta, mancha...) pegado a un control: anchor 0..1 sobre su tamaño + offset en píxeles,
## girado rot radianes. under = true lo deja debajo del contenido (manchas). Funciona también con contenedores (se
## recoloca cada vez que el contenedor ordena a sus hijos, que les quita el giro y la escala).
static func decor(host: Control, name: String, anchor: Vector2, offset: Vector2, scale := 3.0, under := false, tint := Color.WHITE, rot := 0.0) -> TextureRect:
	var t := pic(name, scale)
	t.modulate = tint
	attach(host, t, anchor, offset, under, rot)
	return t

## Pega cualquier control encima de otro (una tarjeta clavada, un sello, una tira...), en anchor (0..1) + offset,
## sin ocupar sitio en su distribución. El tamaño es el mínimo del control; la escala que ya tenga se conserva.
static func attach(host: Control, c: Control, anchor: Vector2, offset: Vector2, under := false, rot := 0.0) -> Control:
	c.set_meta("paper_decor", [anchor, offset, c.custom_minimum_size, c.scale, rot])
	host.add_child(c)
	if under:
		host.move_child(c, 0)
	if host is Container:
		if c is TextureRect:
			c.custom_minimum_size = Vector2.ZERO
		if not host.has_meta("paper_decor_hooked"):
			host.set_meta("paper_decor_hooked", true)
			host.sort_children.connect(func(): _place_decor(host))
	else:
		var sz: Vector2 = c.custom_minimum_size if c.custom_minimum_size != Vector2.ZERO else c.get_combined_minimum_size()
		c.anchor_left = anchor.x
		c.anchor_right = anchor.x
		c.anchor_top = anchor.y
		c.anchor_bottom = anchor.y
		c.offset_left = offset.x
		c.offset_top = offset.y
		c.offset_right = offset.x + sz.x
		c.offset_bottom = offset.y + sz.y
		c.rotation = rot
	return c

static func _place_decor(host: Control) -> void:
	for c in host.get_children():
		if c is Control and c.has_meta("paper_decor"):
			var m: Array = c.get_meta("paper_decor")
			var sz: Vector2 = m[2]
			if sz == Vector2.ZERO:
				sz = c.get_combined_minimum_size()
			c.position = Vector2(host.size.x * m[0].x, host.size.y * m[0].y) + m[1]
			c.size = sz
			c.scale = m[3]
			c.rotation = m[4]

## Una tira repetida (el festón del toldo de un puesto, por ejemplo), ampliada sin suavizado.
static func strip(path: String, width: float, scale := 3.0) -> TextureRect:
	var t := tex(path)
	var tr := TextureRect.new()
	tr.texture = t
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if t:
		tr.custom_minimum_size = Vector2(width / scale, t.get_height())
	tr.scale = Vector2(scale, scale)
	return tr

## Icono de una esencia (llama, copo, hoja, luna, sol).
static func ess_icon(ess: String, scale := 3.0) -> TextureRect:
	var t := pic("paper_ess_%s" % ess, scale)
	t.tooltip_text = String(Data.ESSENCES.get(ess, {}).get("name", ess))
	return t

## Esencias de un ingrediente como iconos repetidos (vida 2 + sombra 1 = hoja hoja luna).
static func ess_row(ess: Dictionary, scale := 3.0, sep := 2) -> HBoxContainer:
	var h := UIKit.hbox(sep)
	for e in Data.ESSENCE_ORDER:
		if ess.has(e):
			for i in int(ess[e]):
				h.add_child(ess_icon(e, scale))
	return h

## Boceto a tinta de una poción ("pot") o un ingrediente ("ing"); si falta, el icono de siempre.
static func sketch(kind: String, id: String, scale := 3.0) -> TextureRect:
	var name := "paper_sk_%s_%s" % [kind, id]
	if tex(name):
		return pic(name, scale)
	return pic("res://assets/icons/%s_%s.png" % [kind, id], scale * 2.0)

## Moneda + cantidad.
static func coins(n: int, size := 30, color := INK, scale := 2.0) -> HBoxContainer:
	var h := UIKit.hbox(4)
	var c := pic("res://assets/icons/emote_coin.png", scale)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	var l := hand(UIKit.num(n), size, color, true)   # --- R5 EN-UI: «1,241»
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

## Icono + texto corto en una fila (p. ej. bolsa x4).
static func icon_text(icon: String, text: String, size := 28, color := INK, scale := 3.0, bold := true) -> HBoxContainer:
	var h := UIKit.hbox(6)
	var i := pic(icon, scale)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(i)
	var l := hand(text, size, color, bold)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

static func _button_base(text: String, cb: Callable, size: int) -> Button:
	load_fonts()
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font_hand_bold)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	return b

## Botón de papel (una tarjetita con texto a tinta). kind: "card", "note", "tag", "tab"...
static func button(text: String, cb: Callable, size := 30, kind := "card", icon := "") -> Button:
	var b := _button_base(text, cb, size)
	var pad := Vector2(20, 6) if kind != "tag" else Vector2(12, 4)
	b.add_theme_stylebox_override("normal", nine(kind, pad))
	b.add_theme_stylebox_override("hover", nine(kind, pad, Color(1.08, 1.06, 1.0)))
	b.add_theme_stylebox_override("pressed", nine(kind, pad, Color(0.86, 0.82, 0.76)))
	b.add_theme_stylebox_override("disabled", nine(kind, pad, Color(0.8, 0.78, 0.74, 0.6)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", RED_INK)
	b.add_theme_color_override("font_pressed_color", RED_INK)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.38, 0.3, 0.6))
	if icon != "":
		b.icon = scaled(icon, 3)
		b.add_theme_constant_override("h_separation", 10)
	return b

## Botón de madera con esquinas de latón (pantalla de título, letreros).
static func wood_button(text: String, cb: Callable, size := 34) -> Button:
	var b := _button_base(text, cb, size)
	b.add_theme_font_override("font", UIKit.font_sc_bold)
	b.add_theme_stylebox_override("normal", nine("wood", Vector2(30, 10)))
	b.add_theme_stylebox_override("hover", nine("wood", Vector2(30, 10), Color(1.35, 1.25, 1.12)))
	b.add_theme_stylebox_override("pressed", nine("wood", Vector2(30, 10), Color(0.8, 0.76, 0.72)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("f2e2bc"))
	b.add_theme_color_override("font_hover_color", Color("ffe9a8"))
	b.add_theme_color_override("font_pressed_color", Color("ffe9a8"))
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
	b.add_theme_constant_override("outline_size", 6)
	return b

## Botón de imagen (esquina doblada para pasar la hoja, sello de lacre...): sigue siendo un Button para el mando.
static func image_button(normal: String, hover: String, cb: Callable, scale := 3.0, tip := "") -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = tex(normal)
	b.texture_hover = tex(hover) if hover != "" else null
	b.texture_pressed = tex(hover) if hover != "" else null
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if b.texture_normal:
		b.custom_minimum_size = b.texture_normal.get_size() * scale
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	return b

## Sello de lacre con una letra (las cartas; botón "x" para cerrar si cb es válido).
static func seal(letter: String, kind := "paper_seal", scale := 3.0) -> Control:
	var holder := Control.new()
	var t := pic(kind, scale)
	holder.custom_minimum_size = t.custom_minimum_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(t)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	var light := {"paper_seal": Color("f2b8a0"), "paper_seal_grey": Color("d8d0e8"), "paper_seal_gold": Color("fff2c0")}
	var l := UIKit.label(letter, int(11 * scale), light.get(kind, Color.WHITE), UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_top = -scale
	l.add_theme_color_override("font_shadow_color", Color(0.18, 0.04, 0.03, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	holder.add_child(l)
	return holder

## Retrato (primer cuadro de la animación de reposo) de un personaje.
static func portrait(id: String, scale := 2.0) -> TextureRect:
	var path := "res://assets/chars/%s_idle.png" % id
	var tr := TextureRect.new()
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2(0, 0, t.get_width() / 2.0, t.get_height())
		tr.texture = at
		tr.custom_minimum_size = Vector2(t.get_width() / 2.0, t.get_height()) * scale
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Retrato clavado: una tarjetita de papel con el retrato y una chincheta arriba.
static func pinned_portrait(id: String, scale := 2.0, pin_name := "paper_pin_red", dark := false) -> PanelContainer:
	var card := panel("card", Vector2(14, 12))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := portrait(id, scale)
	if dark:
		p.modulate = Color(0.16, 0.12, 0.1, 0.9)
	card.add_child(p)
	decor(card, pin_name, Vector2(0.5, 0.0), Vector2(-10, -12), 3.0)
	return card

## Una línea de tinta a mano (separador).
static func ink_rule(width := 400.0, color := INK_FAINT) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(width, 2)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Espacio vacío.
static func gap(h := 10.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
