class_name BenchKit
## Ayudas de interfaz compartidas por el banco (BenchUI), el regateo (HaggleUI) y la cápsula (PodUI).
## --- SS BENCH (nuevo). Usa el estilo de UIKit (placas remachadas, pantallas CRT ámbar, etiquetas de papel) y el arte
## de ART cuando existe: assets/ui/btn_primary*9.png (botón principal ámbar), bubble9.png + bubble_tail.png (globos),
## glyph_*.png (teclas y botones del mando), icon_*.png; assets/chars, items, parts. Sin el arte: cajas planas.
## Todo lo que se dibuja a mano va en píxeles enteros (px) para que combine con el pixel art.

const INK := Color("2a2024")          # texto oscuro sobre papel, globos, teclas y botones claros (ui_kit.json)
const INK_DIM := Color("4a4642")      # texto de un botón desactivado
const CREAM := Color("ece2c8")        # texto claro sobre la placa oscura
const AMBER := Color("f0b44a")        # texto de las pantallas CRT
const AMBER_DIM := Color("9a6a2a")
const GREEN := Color(0.5, 0.86, 0.46)
const RED := Color(1.0, 0.42, 0.34)
const COLD := Color(0.45, 0.72, 1.0)

static var _tex := {}

## Una textura (con caché); null si el archivo no existe (sin error en la consola).
static func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex[path] = t
	return t

## Un cuadro de una tira de cuadros iguales (los personajes: 64x96). crop: la parte del cuadro que se quiere
## (en píxeles del cuadro; vacío = el cuadro entero).
static func frame(path: String, i: int, fw := 64, fh := 96, crop := Rect2()) -> AtlasTexture:
	var t := tex(path)
	if t == null:
		return null
	var a := AtlasTexture.new()
	a.atlas = t
	var r := Rect2(i * fw, 0, fw, fh)
	if crop.size != Vector2.ZERO:
		r = Rect2(i * fw + crop.position.x, crop.position.y, crop.size.x, crop.size.y)
	a.region = r
	return a

## Un TextureRect de pixel art a escala entera (sin suavizar).
static func pixel_rect(t: Texture2D, scale := 2.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = t
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if t:
		tr.custom_minimum_size = Vector2(t.get_width(), t.get_height()) * scale
	return tr

## Pone un control en un rectángulo fijo del lienzo de 1280x720 (los paneles de BENCH se arman así).
static func at(c: Control, r: Rect2) -> Control:
	c.position = r.position
	c.size = r.size
	c.custom_minimum_size = r.size
	return c

## Un Control vacío que no atrapa el ratón (para agrupar).
static func group(r := Rect2()) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if r.size != Vector2.ZERO:
		at(c, r)
	return c

# ------------------------------------------------------------------ botones

## Estilo del botón principal (ámbar de ART: btn_primary9 / _hover9 / _pressed9).
static func style_primary(b: Button) -> void:
	if ResourceLoader.exists("res://assets/ui/btn_primary9.png"):
		var pairs := {"normal": "btn_primary9.png", "hover": "btn_primary_hover9.png", "pressed": "btn_primary_pressed9.png",
			"disabled": "btn_disabled9.png"}
		for st in pairs:
			var sb := UIKit.nine(pairs[st], 12, 15)
			if sb:
				sb.content_margin_left = maxf(sb.content_margin_left, 18.0)
				sb.content_margin_right = maxf(sb.content_margin_right, 18.0)
				b.add_theme_stylebox_override(st, sb)
	else:
		b.add_theme_stylebox_override("normal", UIKit.button_style(Color(0.86, 0.55, 0.2), Color(0.55, 0.32, 0.1)))
		b.add_theme_stylebox_override("hover", UIKit.button_style(Color(0.95, 0.66, 0.3), UIKit.ACCENT_BRIGHT))
		b.add_theme_stylebox_override("pressed", UIKit.button_style(Color(0.78, 0.48, 0.16), UIKit.ACCENT_BRIGHT))

## Botón con icono, texto y (con teclado) la tecla dibujada a la derecha. El texto y la tecla son hijos del botón
## (el botón no los acomoda solo: se dan medidas fijas con size). key "" = sin tecla.
static func key_button(text: String, key: String, cb: Callable, size: Vector2, icon_name := "", primary := false,
		font_size := UIKit.FS_BUTTON) -> Button:
	var b := UIKit.button("", cb, font_size)
	if primary:
		style_primary(b)
	b.custom_minimum_size = size
	b.size = size
	var h := HBoxContainer.new()
	h.name = "Row"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	h.anchor_right = 1.0
	h.anchor_bottom = 1.0
	h.offset_left = 12
	h.offset_right = -12
	h.offset_top = 4
	h.offset_bottom = -8      # el labio de abajo de los botones de ART
	b.add_child(h)
	if icon_name != "":
		var ic := UIKit.ui_icon(icon_name, 2.0)
		ic.name = "Icon"
		h.add_child(ic)
	var l := UIKit.label(text, font_size, INK, UIKit.font_bold)
	l.name = "Text"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var k := HBoxContainer.new()
	k.name = "Key"
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(k)
	b.set_meta("key", key)
	set_key(b, key)
	return b

## Cambia (o vuelve a dibujar según el aparato en uso) la tecla de un key_button. Con el mando no se muestra:
## se toca con el cursor (LB / RB saltan entre botones) y A.
static func set_key(b: Button, key: String) -> void:
	var k: Node = b.find_child("Key", true, false)
	if k == null:
		return
	b.set_meta("key", key)
	for c in k.get_children():
		c.queue_free()
	if key != "" and not PadCursor.pad_in_use:
		k.add_child(UIKit.keycap(key, 16))

static func set_text(b: Button, text: String) -> void:
	var l: Label = b.find_child("Text", true, false)
	if l:
		l.text = text

## Activa o desactiva un key_button (con el color de letra de ART para desactivado).
static func enable(b: Button, on: bool) -> void:
	b.disabled = not on
	var l: Label = b.find_child("Text", true, false)
	if l:
		l.add_theme_color_override("font_color", INK if on else UIKit.kit_color("btn_normal9.png", "text_disabled", INK_DIM))
	var ic: Control = b.find_child("Icon", true, false)
	if ic:
		ic.modulate = Color(1, 1, 1, 1.0 if on else 0.4)
	var k: Control = b.find_child("Key", true, false)
	if k:
		k.modulate = Color(1, 1, 1, 1.0 if on else 0.35)

## Vuelve a dibujar las teclas de todos los key_button debajo de root (al cambiar de teclado a mando o al revés).
static func refresh_keys(root: Node) -> void:
	for c in root.find_children("*", "Button", true, false):
		if c.has_meta("key"):
			set_key(c, String(c.get_meta("key")))

# ------------------------------------------------------------------ teclas y botones del mando (ayudas)

## El dibujo de un botón del mando: A / B (los de ART), X / Y (círculos de color), LB / RB, "Stick".
static func pad_glyph(name: String, size := 16) -> Control:
	if name in ["A", "B"] and ResourceLoader.exists("res://assets/ui/glyph_pad_%s.png" % name.to_lower()):
		return UIKit.icon("res://assets/ui/glyph_pad_%s.png" % name.to_lower(), roundf(size * 1.5 / 16.0))
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var cols := {"A": Color(0.36, 0.7, 0.32), "B": Color(0.82, 0.3, 0.26), "X": Color(0.3, 0.52, 0.88), "Y": Color(0.9, 0.74, 0.26)}
	var round_btn: bool = cols.has(name)
	sb.bg_color = cols.get(name, Color(0.16, 0.15, 0.15))
	sb.border_color = Color(0.08, 0.06, 0.06)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size) if round_btn else 6)
	sb.content_margin_left = 6 if round_btn else 8
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(name, size - (2 if name.length() > 1 else 0), Color.WHITE, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(size * 0.85, 0) if round_btn else Vector2.ZERO
	p.add_child(l)
	return p

## Una fila de ayudas de controles según el aparato en uso. items = [{"keys": ["L", "T"], "pad": ["LB", "RB"],
## "text": "tools"}, ...]; "keys" (teclado) o "pad" vacíos = esa ayuda no va con ese aparato.
static func hints(items: Array, size := 17) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var pad := PadCursor.pad_in_use
	for it in items:
		var keys: Array = it.get("pad" if pad else "keys", [])
		if keys.is_empty():
			continue
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 5)
		for k in keys:
			if String(k) == "/":
				h.add_child(UIKit.label("/", size, UIKit.MUTED))
			elif pad:
				h.add_child(pad_glyph(String(k), size))
			else:
				h.add_child(UIKit.keycap(String(k), size))
		var l := UIKit.label(String(it.get("text", "")), size, CREAM, UIKit.font_regular)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
		row.add_child(h)
	return row

# ------------------------------------------------------------------ cajas

## Una placa remachada de ART (o la caja plana de la semilla) como PanelContainer.
static func plate(margin := 16) -> PanelContainer:
	return UIKit.fancy_panel(UIKit.BG, margin)

## Una pantalla CRT ámbar (PanelContainer).
static func screen(margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.screen_style(margin))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Una etiqueta de papel (PanelContainer, con el ojal a la izquierda).
static func tag(margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.tag_style(margin))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Una caja hundida (la alfombra del banco, la cabina del regateo): fondo oscuro con canto claro abajo.
static func inset_style(bg := Color(0.07, 0.075, 0.07, 0.96), radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.02, 0.02, 0.02, 0.9)
	sb.set_border_width_all(3)
	sb.border_width_bottom = 2
	sb.border_width_top = 4
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0)
	return sb

## Letra con sombra suave (para textos sobre la placa).
static func shadow(l: Label) -> Label:
	return UIKit.shadow(l, 2)

## Píxel entero.
static func snap(p: Vector2, px := 2.0) -> Vector2:
	return (p / px).floor() * px
