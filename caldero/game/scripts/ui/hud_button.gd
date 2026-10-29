extends Button
class_name HudButton
## --- R6 UI: el botón del HUD. Una cara de pergamino (tinta encima) sobre una tabla de nogal que asoma por debajo
## (assets/ui/r6_btn_*.png y r6_ibtn_*.png, de tools/arte/ui_art.py --r6). Tres tipos, una sola forma:
##   "primary"   la acción principal (Abrir la tienda): cara dorada, aro de latón y tachuelas;
##   "secondary" las demás (Mercado, Volver a la tienda, las respuestas del diálogo): cara crema y aro de nogal;
##   "icon"      el cuadrado de la barra de arriba a la derecha (solo el icono; su nombre y sus teclas, en el tooltip).
## Estados: normal, encima (también el cursor del mando), pulsado (la cara baja 3 px y el texto con ella), desactivado;
## con el mando, además, un aro dorado que late alrededor del botón que tiene el cursor. A la derecha, el glifo de su
## tecla (Glyphs.Chip: la tecla con el teclado y el ratón; con el mando, su botón si lo tiene). Sigue siendo un Button
## con su texto (el mando, el bot y las pruebas lo encuentran por su texto o por su meta).

const FACE_H := 45.0        # la cara (sin el canto de nogal): 15 px de arte a 3x
const FACE_H_TALL := 57.0   # la alta (set_tall): 19 px de arte a 3x; con el canto, 66 = los cuadrados de la barra
const PAD_X := 20.0         # margen de la cara a los lados (contorno, aro y tachuelas)
const INK := Color("3a2618")
const INK_SOFT := Color("4a3622")
const INK_OFF := Color(0.42, 0.37, 0.31, 0.8)

var kind := "secondary"
var tall := false           # la variante alta (66 px, arte r6_btn_*_t.png): los botones de arriba al centro
var chip: Glyphs.Chip
var tip_title := ""         # el tooltip: su nombre y, al lado, la tecla y el botón del mando (tip_actions)
var tip_actions: Array = []
var _ring: NinePatchRect
var _chip_w := 0.0
var _t := 0.0

## Un botón listo: kind ("primary" / "secondary" / "icon"), su texto, su icono (de assets/ui: "hud_market",
## "r6_ico_bell"...), su acción de Glyphs ("" = sin glifo) y qué hace.
static func make(kind_: String, text_: String, icon_name: String, action: String, cb: Callable, font_size := 26) -> HudButton:
	var b := HudButton.new()
	b.setup(kind_, text_, icon_name, action, cb, font_size)
	return b

func setup(kind_: String, text_: String, icon_name: String, action: String, cb: Callable, font_size := 26) -> void:
	UIKit.load_fonts()
	kind = kind_
	text = text_ if kind != "icon" else ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_override("font", UIKit.font_sc_bold)
	add_theme_font_size_override("font_size", font_size)
	var col := INK if kind == "primary" else INK_SOFT
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(k, col)
	add_theme_color_override("font_disabled_color", INK_OFF)
	add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
	add_theme_constant_override("h_separation", 10)
	if icon_name != "":
		set_icon_name(icon_name)
	if kind == "icon":
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		custom_minimum_size = Vector2(66, 66)
	else:
		custom_minimum_size = Vector2(0, 54)
	pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	mouse_entered.connect(func():
		if not disabled:
			Sfx.play("hover", 0.05, -14.0))
	if action != "":
		chip = Glyphs.Chip.new(action, false, true)
		add_child(chip)
		chip.rebuilt.connect(_restyle)
	_ring = NinePatchRect.new()
	_ring.texture = PaperKit.tex("r6_focus9")
	_ring.patch_margin_left = 15
	_ring.patch_margin_right = 15
	_ring.patch_margin_top = 15
	_ring.patch_margin_bottom = 15
	_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)
	_restyle()

## La variante alta (66 px de alto, como los cuadrados de la barra de la derecha): los botones de arriba al centro.
func set_tall(t := true) -> void:
	tall = t
	if kind != "icon":
		custom_minimum_size.y = 66.0 if tall else 54.0
	_restyle()

## Cambia el icono (16x16 de assets/ui, a 2x en los botones de texto y a 3x en los cuadrados).
func set_icon_name(icon_name: String) -> void:
	icon = PaperKit.scaled(icon_name, 3 if kind == "icon" else 2)

## Cambia el texto y la acción (el botón de viaje: «Market» / «Back to shop»).
func set_label(text_: String, action := "") -> void:
	text = text_
	if chip and action != "":
		chip.set_action(action)

## El tooltip: el nombre y, al lado, la tecla y el botón del mando de cada acción.
func set_tip(title: String, actions: Array = []) -> void:
	tip_title = title
	tip_actions = actions
	tooltip_text = title

func _restyle() -> void:
	_chip_w = 0.0
	if chip and chip.visible:
		chip.reset_size()
		_chip_w = chip.get_combined_minimum_size().x
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, _box("pressed" if st == "hover_pressed" else st))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	update_minimum_size()

func _box(st: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var down := 3.0 if st == "pressed" else 0.0
	if kind == "icon":
		sb.texture = PaperKit.tex("r6_ibtn_%s" % st)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3 + down
		sb.content_margin_bottom = 12 - down
		return sb
	sb.texture = PaperKit.tex("r6_btn_%s_%s%s" % [kind, st, "_t" if tall else ""])
	sb.texture_margin_left = 18
	sb.texture_margin_right = 18
	sb.texture_margin_top = 18
	sb.texture_margin_bottom = 18
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.content_margin_left = PAD_X
	sb.content_margin_right = PAD_X + (_chip_w + 10.0 if _chip_w > 0.0 else 0.0)
	sb.content_margin_top = 3 + down
	sb.content_margin_bottom = 12 - down
	return sb

func _process(delta: float) -> void:
	_t += delta
	var dm := get_draw_mode()
	var down := 3.0 if (dm == DRAW_PRESSED or dm == DRAW_HOVER_PRESSED) else 0.0
	if chip and chip.visible:
		var face := (FACE_H_TALL if tall else FACE_H) if kind != "icon" else size.y - 9.0
		chip.position = Vector2(size.x - PAD_X - _chip_w, roundf((face - chip.size.y) / 2.0) + down + 1.0)
		chip.modulate.a = 0.45 if disabled else 1.0
	# el foco del mando: el aro dorado alrededor del botón que tiene su cursor
	var focus := PadCursor.active and is_hovered() and not disabled and is_visible_in_tree()
	if focus != _ring.visible:
		_ring.visible = focus
		_ring.position = Vector2(-9, -9)
		_ring.size = size + Vector2(18, 18)
	if focus:
		_ring.size = size + Vector2(18, 18)
		_ring.modulate.a = 0.6 + 0.4 * sin(_t * 6.0)

## El tooltip con su nombre y sus teclas (la del teclado y la del mando, como glifos).
func _make_custom_tooltip(_for_text: String) -> Object:
	if tip_title == "":
		return null
	var h := UIKit.hbox(8)
	var l := UIKit.label(tip_title, 22, UIKit.GOLD_BRIGHT, UIKit.font_bold)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	for a in tip_actions:
		for dev in ["keys", "pad"]:
			var g := Glyphs.make(String(a), dev)   # a tamaño normal (a 2x el botón Vista del mando no se reconocía)
			if g:
				g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(g)
	return h
