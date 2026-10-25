extends CanvasLayer
class_name BrewUI
## --- R3 BENCH: el banco del caldero. A la izquierda, el mueble de los frascos (los ingredientes, con su número en la
## etiqueta de la repisa); a la derecha, el caldero grande sobre su fuego, los tubos de las esencias y los botones
## Remover · Embotellar · Tinta · Vaciar. Se abre en la estación del caldero (E, un clic en el caldero o en un frasco
## del estante de la tienda: main.open_brew()).
## Va en la capa 4: DEBAJO de la interfaz (capa 5: el ticket, el oro, los avisos, el estante de pociones y el
## diálogo quedan encima) y de los paneles grandes (capa 10: recetas, diario...).
## main.gd guarda el estado (contents, brew_ready) y lo valida todo (brew_add, brew_take, _on_brew, brew_bottle...);
## aquí solo se dibuja, se anima y se pide. El pixel art del banco va a 4x (tools/arte/ui_art.py, bloque R3 BENCH).
## Ratón, teclado (Esc o E cierra, Espacio remueve / embotella / acierta, 1-8 echan un frasco, Retroceso saca el
## último) y el cursor del mando (A toca, B cierra, X = Espacio, LB / RB saltan entre frascos y botones).

signal opened
signal closed

const ART := 4.0
const STAGE_SIZE := Vector2(1920, 1080)
const SHELF_POS := Vector2(90, 236)       # esquina del mueble (bench_shelf.png, 200x150 px de arte)
const JAR_X := [31, 77, 123, 169]         # centro de cada frasco en el mueble (px de arte)
const BOARD_Y := [52, 104]                # la repisa: los frascos apoyan aquí
const TAG_POS := Vector2(98, 848)         # la etiqueta del frasco señalado (bench_tag.png)
const POT_POS := Vector2(1010, 372)       # esquina del lienzo del caldero (104x80 px de arte)
const LIQ_C := Vector2(52.0, 14.2)        # centro y radios del líquido (px de arte, en el lienzo del caldero)
const LIQ_R := Vector2(33.5, 8.2)
const RACK_POS := Vector2(1474, 446)      # los tubos de ensayo (bench_rack.png, 98x60)
const SLOTS_Y := 756.0                    # los huecos del caldero (lo que lleva dentro)
const BTN_Y := 926.0
const BTN_SIZE := Vector2(120, 104)
const EMPTY_LIQUID := Color("3b3156")

var main                       # main.gd
var ui: GameUI
var ov: Overlays
var root: Control              # pantalla completa (para el ratón: tapa el escenario 3D)
var stage: Control             # 1920x1080 centrado
var busy := false              # removiendo o embotellando
var _open := false
var _closing := false
var _pending := 0              # frascos en el aire (los huecos y los tubos los muestran al caer)
var _hover := ""               # frasco señalado
var _guide: Array = []         # frascos que brillan (el primer pedido)
var _stir: StirGame = null
var _catcher: Control          # durante el removido: un clic en cualquier sitio acierta
var _t := 0.0
var _msg_tw: Tween

var jar_btns := {}             # id -> Button
var jar_tex := {}              # id -> TextureRect
var jar_glow := {}             # id -> TextureRect
var jar_count := {}            # id -> Label
var jar_lock := {}             # id -> TextureRect
var slot_btns: Array = []      # Button (aro de latón + icono)
var pot: _Pot
var tubes: _Tubes
var tag: TextureRect
var tag_icon: TextureRect
var tag_name: Label
var tag_ess: HBoxContainer
var fc: Control                # la visión en el vapor: la poción que saldría
var fc_glow: TextureRect
var fc_icon: TextureRect
var fc_name: Label
var fc_stars: HBoxContainer
var btns := {}                 # "stir" / "bottle" / "ink" / "empty" -> Button
var btn_icons := {}
var btn_row: Control
var close_btn: TextureButton
var msg: Label

# ------------------------------------------------------------------ montaje

func setup(m) -> void:
	main = m
	ui = m.ui
	ov = m.ov

func _ready() -> void:
	layer = 4
	visible = false
	UIKit.load_fonts()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UIKit.theme()
	add_child(root)
	_build_backdrop()
	stage = Control.new()
	stage.anchor_left = 0.5
	stage.anchor_right = 0.5
	stage.anchor_top = 0.5
	stage.anchor_bottom = 0.5
	stage.offset_left = -STAGE_SIZE.x / 2.0
	stage.offset_right = STAGE_SIZE.x / 2.0
	stage.offset_top = -STAGE_SIZE.y / 2.0
	stage.offset_bottom = STAGE_SIZE.y / 2.0
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(stage)
	_build_shelf()
	_build_tag()
	_build_pot()
	_build_tubes()
	_build_forecast()
	_build_slots()
	_build_buttons()
	_build_close()
	msg = UIKit.label("", 34, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER)
	msg.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.12))
	msg.add_theme_constant_override("outline_size", 10)
	msg.position = Vector2(POT_POS.x + 208 - 300, POT_POS.y + 170)
	msg.size = Vector2(600, 50)
	msg.modulate.a = 0.0
	stage.add_child(msg)
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _stir:
			_stir.press())
	root.add_child(_catcher)
	Game.stock_changed.connect(func():
		if _open:
			_refresh_jars())
	Game.upgrades_changed.connect(func():
		if _open:
			refresh())
	Game.renombre_changed.connect(func(_a, _b):
		if _open:
			_refresh_jars())
	Game.magic_changed.connect(func():
		if _open:
			_update_buttons())
	ui.cauldron_set.connect(func(_c):
		if _open and _pending == 0:
			refresh())

func _build_backdrop() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	_dim = dim   # --- R4 EVENTS
	# viñeta y una luz cálida detrás del caldero (degradados radiales: sin shaders)
	var vg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.55))
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	vg.texture = gt
	vg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vg)

func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

## Un TextureRect de pixel art a la escala del banco.
func _art(path: String, pos: Vector2, parent: Control, k := ART) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _tex(path)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	if tr.texture:
		tr.size = tr.texture.get_size() * k
	tr.position = pos
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr

## Botón sin estilo (lo que se ve son sus hijos).
func _flat_button(pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.position = pos
	b.size = sz
	b.custom_minimum_size = sz
	return b

# ------------------------------------------------------------------ el mueble de los frascos

func _build_shelf() -> void:
	# sombra en el suelo y el mueble
	var sh := ColorRect.new()
	sh.color = Color(0, 0, 0, 0.35)
	sh.position = SHELF_POS + Vector2(12, 150 * ART - 8)
	sh.size = Vector2(200 * ART - 24, 16)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(sh)
	_art("res://assets/ui/bench_shelf.png", SHELF_POS, stage)
	for i in Data.INGREDIENT_ORDER.size():
		var id: String = Data.INGREDIENT_ORDER[i]
		var cx: float = JAR_X[i % 4]
		var by: float = BOARD_Y[i / 4]
		var pos := SHELF_POS + Vector2((cx - 9.0) * ART, (by - 22.0) * ART)
		var glow := _art("res://assets/fx/glow.png", pos + Vector2(-34, -26), stage, 4.4)
		glow.modulate = Color(Data.INGREDIENTS[id]["color"], 0.0)
		jar_glow[id] = glow
		var b := _flat_button(pos - Vector2(8, 12), Vector2(18 * ART + 16, 22 * ART + 12))
		b.tooltip_text = ""
		stage.add_child(b)
		var jt := _art("res://assets/props/jar_%s.png" % id, Vector2(8, 12), b)
		jt.pivot_offset = Vector2(9, 22) * ART
		jar_tex[id] = jt
		var lock := _art("res://assets/ui/bench_lock.png", Vector2(8 + 5.5 * ART, 12 + 7 * ART), b)
		lock.visible = false
		jar_lock[id] = lock
		b.pressed.connect(func(): throw(id))
		b.mouse_entered.connect(func(): _on_jar_hover(id, true))
		b.mouse_exited.connect(func(): _on_jar_hover(id, false))
		jar_btns[id] = b
		# --- R3 MERGE: la cuenta va escrita a mano en la etiqueta de papel (UI-PAPER: PaperKit.font_hand_bold, Caveat)
		PaperKit.load_fonts()
		var lbl := UIKit.label("0", 30, Color("3a2618"), PaperKit.font_hand_bold, HORIZONTAL_ALIGNMENT_CENTER)
		lbl.position = SHELF_POS + Vector2((cx - 9.0) * ART, (by + 3.0) * ART - 6.0)
		lbl.size = Vector2(18 * ART, 6 * ART)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stage.add_child(lbl)
		jar_count[id] = lbl

func _refresh_jars() -> void:
	for id in jar_btns:
		var unlocked := Game.ingredient_unlocked(id)
		var n: int = Game.stock.get(id, 0)
		var b: Button = jar_btns[id]
		b.disabled = not unlocked
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
		jar_lock[id].visible = not unlocked
		var jt: TextureRect = jar_tex[id]
		if not unlocked:
			jt.modulate = Color(0.05, 0.04, 0.08, 0.6)
		elif n <= 0:
			jt.modulate = Color(0.5, 0.46, 0.55)
		elif _hover == id:
			jt.modulate = Color(1.3, 1.25, 1.15)
		else:
			jt.modulate = Color.WHITE
		var lbl: Label = jar_count[id]
		lbl.text = str(n) if unlocked else ""
		lbl.add_theme_color_override("font_color", Color("3a2618") if n > 0 else Color("9e2b25"))

func _on_jar_hover(id: String, on: bool) -> void:
	if not Game.ingredient_unlocked(id):
		return
	var jt: TextureRect = jar_tex[id]
	var tw := create_tween()
	if on:
		_hover = id
		Sfx.play("hover", 0.05, -14.0)
		tw.tween_property(jt, "position:y", 12.0 - 2 * ART, 0.08)
		_show_tag(id)
	else:
		if _hover == id:
			_hover = ""
			_hide_tag()
		tw.tween_property(jt, "position:y", 12.0, 0.1)
	_refresh_jars()

# ------------------------------------------------------------------ la etiqueta (nombre y esencias del frasco)

func _build_tag() -> void:
	tag = _art("res://assets/ui/bench_tag.png", TAG_POS, stage)
	tag.modulate.a = 0.0
	var h := UIKit.hbox(14)
	h.position = Vector2(40, 10)
	h.size = Vector2(tag.size.x - 80, 68)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	tag.add_child(h)
	tag_icon = TextureRect.new()
	tag_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tag_icon.custom_minimum_size = Vector2(64, 64)
	tag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tag_icon)
	PaperKit.load_fonts()   # --- R3 MERGE: el nombre, a mano en la etiqueta de papel (como el recetario de UI-PAPER)
	tag_name = UIKit.label("", 36, Color("3a2618"), PaperKit.font_hand_bold)
	tag_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag_name)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	tag_ess = UIKit.hbox(6)
	tag_ess.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag_ess)

func _show_tag(id: String) -> void:
	var d: Dictionary = Data.INGREDIENTS[id]
	tag_icon.texture = _tex("res://assets/icons/ing_%s.png" % id)
	tag_name.text = d["name"]
	for c in tag_ess.get_children():
		c.queue_free()
	for e in Data.ESSENCE_ORDER:
		var n: int = d["ess"].get(e, 0)
		for k in n:
			tag_ess.add_child(UIKit.ess_icon(e, 4.0))
		if n > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(10, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag_ess.add_child(gap)
	var tw := create_tween()
	tw.tween_property(tag, "modulate:a", 1.0, 0.12)

func _hide_tag() -> void:
	var tw := create_tween()
	tw.tween_property(tag, "modulate:a", 0.0, 0.2).set_delay(0.25)

# ------------------------------------------------------------------ el caldero grande

func _build_pot() -> void:
	pot = _Pot.new()
	pot.position = POT_POS
	pot.size = Vector2(104, 80) * ART
	pot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(pot)

## Centro del líquido en coordenadas del escenario.
func mouth() -> Vector2:
	return POT_POS + LIQ_C * ART

# ------------------------------------------------------------------ los tubos de las esencias

func _build_tubes() -> void:
	tubes = _Tubes.new()
	tubes.position = RACK_POS
	tubes.size = Vector2(98, 60) * ART
	tubes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(tubes)

# ------------------------------------------------------------------ la visión en el vapor (lo que saldría)

func _build_forecast() -> void:
	fc = Control.new()
	fc.position = Vector2(POT_POS.x + 208 - 220, 204)
	fc.size = Vector2(440, 170)
	fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.modulate.a = 0.0
	stage.add_child(fc)
	fc_glow = _art("res://assets/fx/glow.png", Vector2(220 - 96, -46), fc, 6.0)
	fc_icon = TextureRect.new()
	fc_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fc_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fc_icon.stretch_mode = TextureRect.STRETCH_SCALE
	fc_icon.size = Vector2(80, 80)
	fc_icon.position = Vector2(220 - 40, -8)
	fc_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.add_child(fc_icon)
	fc_name = UIKit.label("", 32, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER)
	fc_name.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.12))
	fc_name.add_theme_constant_override("outline_size", 10)
	fc_name.position = Vector2(0, 66)
	fc_name.size = Vector2(440, 44)
	fc.add_child(fc_name)
	fc_stars = UIKit.hbox(2)
	fc_stars.position = Vector2(220 - 72, 112)
	fc_stars.size = Vector2(144, 48)
	fc_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	fc.add_child(fc_stars)

func _set_forecast(icon: String, name: String, stars: int, col: Color, ready := false) -> void:
	if icon == "":
		create_tween().tween_property(fc, "modulate:a", 0.0, 0.2)
		return
	var was_hidden := fc.modulate.a < 0.05
	fc_icon.texture = _tex(icon)
	fc_name.text = name
	fc_glow.modulate = Color(col.r, col.g, col.b, 0.75 if ready else 0.45)
	for c in fc_stars.get_children():
		c.queue_free()
	if stars > 0:
		for i in 3:
			fc_stars.add_child(UIKit.icon("res://assets/icons/emote_star.png" if i < stars else "res://assets/icons/emote_star_empty.png", 3.0))
	create_tween().tween_property(fc, "modulate:a", 1.0, 0.2)
	if was_hidden or ready:
		fc_icon.pivot_offset = Vector2(40, 40)
		fc_icon.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(fc_icon, "scale", Vector2(1.25, 1.25) if ready else Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ los huecos del caldero

func _build_slots() -> void:
	for i in 3:
		var b := _flat_button(Vector2.ZERO, Vector2(21, 21) * ART)
		var ring := _art("res://assets/ui/bench_slot_empty.png", Vector2.ZERO, b)
		ring.name = "Ring"
		var ic := _art("res://assets/icons/ing_raiz_mandragora.png", Vector2(2.5, 2.5) * ART, b)
		ic.name = "Icon"
		ic.pivot_offset = Vector2(8, 8) * ART
		var idx := i
		b.pressed.connect(func(): _take(idx))
		b.mouse_entered.connect(func():
			if idx < _shown().size():
				_on_slot_hover(idx, true))
		b.mouse_exited.connect(func(): _on_slot_hover(idx, false))
		stage.add_child(b)
		slot_btns.append(b)

func _on_slot_hover(i: int, on: bool) -> void:
	var b: Button = slot_btns[i]
	b.get_node("Ring").modulate = Color(1.3, 1.25, 1.1) if on else Color.WHITE
	var c := _shown()
	if on and i < c.size():
		Sfx.play("hover", 0.05, -14.0)
		_show_tag(c[i])
	elif not on:
		_hide_tag()

func _layout_slots() -> void:
	var n := Game.cauldron_slots()
	var gap := 100.0
	var x0 := POT_POS.x + 208 - (gap * (n - 1)) / 2.0 - 21 * ART / 2.0
	for i in 3:
		var b: Button = slot_btns[i]
		b.visible = i < n
		b.position = Vector2(x0 + gap * i, SLOTS_Y)

## Lo que se ve dentro del caldero (sin los frascos que aún están en el aire).
func _shown() -> Array:
	var c: Array = main.contents if main else []
	return c.slice(0, maxi(0, c.size() - _pending))

func _refresh_slots() -> void:
	var c := _shown()
	for i in slot_btns.size():
		var b: Button = slot_btns[i]
		var ring: TextureRect = b.get_node("Ring")
		var ic: TextureRect = b.get_node("Icon")
		var full := i < c.size()
		ring.texture = _tex("res://assets/ui/bench_slot.png" if full else "res://assets/ui/bench_slot_empty.png")
		ic.visible = full
		if full:
			ic.texture = _tex("res://assets/icons/ing_%s.png" % c[i])
		b.disabled = not full or busy or not main.brew_ready.is_empty()
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if full else Control.CURSOR_ARROW

# ------------------------------------------------------------------ botones

func _build_buttons() -> void:
	btn_row = UIKit.hbox(14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.position = Vector2(POT_POS.x + 160 - 360, BTN_Y)
	btn_row.size = Vector2(720, BTN_SIZE.y)
	stage.add_child(btn_row)
	for spec in [["stir", "Stir"], ["bottle", "Bottle"], ["ink", "Ink"], ["empty", "Empty"]]:
		var id: String = spec[0]
		var b := Button.new()
		b.custom_minimum_size = BTN_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_wood_style(b, false)
		var v := UIKit.vbox(0)
		v.name = "Box"
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 10
		v.offset_bottom = -12
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(v)
		var ic := UIKit.icon("res://assets/ui/act_%s.png" % id, 3.0)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		btn_icons[id] = ic
		var l := UIKit.label(spec[1], 22, Color(0.98, 0.93, 0.8), UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.02, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.name = "Word"
		v.add_child(l)
		b.pressed.connect(func():
			Sfx.play("click", 0.05, -4.0)
			_on_action(id))
		b.mouse_entered.connect(func():
			if not b.disabled:
				Sfx.play("hover", 0.05, -14.0))
		btn_row.add_child(b)
		btns[id] = b

## Madera del banco (bench_btn_*.png, 30x26 px de arte estirados a 4x); el principal, con borde dorado.
func _wood_style(b: Button, primary: bool) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var kind: String = st
		if st == "normal" and primary:
			kind = "primary"
		var sb := StyleBoxTexture.new()
		sb.texture = _tex("res://assets/ui/bench_btn_%s.png" % kind)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_action(id: String) -> void:
	if busy or _closing or not main:
		return
	match id:
		"stir":
			main._on_brew()
		"bottle":
			main.brew_bottle()
		"ink":
			main._on_brew_ink()
		"empty":
			_empty()

func _update_buttons() -> void:
	if not main:
		return
	var c := _shown()
	var ready: bool = not main.brew_ready.is_empty()
	var r := Game.evaluate(c)
	var magic: bool = Game.magic_unlocked
	var ink := Game.ink_for_mix(c) if magic else {}
	var can_stir: bool = not ready and r.get("potion", "") != "" and not busy and _pending == 0
	_enable("stir", can_stir, can_stir)
	_enable("bottle", ready and not busy, ready)
	btns["ink"].visible = magic and not event_mode   # --- R4 EVENTS: en un evento no hay «Tinta»
	_enable("ink", magic and not ready and not ink.is_empty() and not busy and _pending == 0, false)
	if not ink.is_empty():
		var p := "res://assets/icons/%s.png" % ink["ink"]
		if ResourceLoader.exists(p):
			btn_icons["ink"].texture = load(p)
	_enable("empty", not c.is_empty() and not ready and not busy, false)
	close_btn.disabled = busy

func _enable(id: String, on: bool, primary: bool) -> void:
	var b: Button = btns[id]
	b.disabled = not on
	_wood_style(b, primary and on)
	b.get_node("Box/Word").add_theme_color_override("font_color", Color(0.98, 0.93, 0.8) if on else Color(0.62, 0.58, 0.54))
	btn_icons[id].modulate = Color.WHITE if on else Color(0.55, 0.52, 0.5, 0.7)

func _build_close() -> void:
	close_btn = TextureButton.new()
	close_btn.texture_normal = _tex("res://assets/ui/bench_close.png")
	close_btn.texture_hover = _tex("res://assets/ui/bench_close_hover.png")
	close_btn.texture_pressed = close_btn.texture_hover
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_SCALE
	close_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -96
	close_btn.offset_right = -24
	close_btn.offset_top = 24
	close_btn.offset_bottom = 96
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.tooltip_text = "Close"
	close_btn.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		close())
	close_btn.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	root.add_child(close_btn)

# ------------------------------------------------------------------ abrir y cerrar

func is_open() -> bool:
	return _open

## Hay algo en marcha (removiendo, embotellando o frascos en el aire).
func is_busy() -> bool:
	return busy or _pending > 0

func open() -> void:
	if _open:
		return
	_open = true
	_closing = false
	visible = true
	_hover = ""
	tag.modulate.a = 0.0
	refresh()
	_layout_slots()
	root.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	stage.position.y = 18.0
	tw.tween_property(stage, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("bubble_1", 0.1, -4.0)
	opened.emit()

## Cierra el banco. Si hay una poción removida sin embotellar, la embotella antes (no se pierde nada).
func close() -> void:
	if not _open or _closing or busy:
		return
	_closing = true
	if main and not main.brew_ready.is_empty():
		await main.brew_bottle()
	if not _open:
		return
	_guide.clear()
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.15)
	await tw.finished
	_open = false
	_closing = false
	visible = false
	_pending = 0
	closed.emit()

## Cierra al instante, sin animaciones (cambios de lugar, fin del día, título).
func close_now() -> void:
	if not _open:
		return
	_open = false
	_closing = false
	visible = false
	_pending = 0
	_guide.clear()
	if _stir:
		_stir.queue_free()
		_stir = null
	_catcher.visible = false
	busy = false
	closed.emit()

## Vuelve a dibujar todo según main.contents y main.brew_ready.
func refresh() -> void:
	if not main:
		return
	_refresh_jars()
	_layout_slots()
	_refresh_slots()
	var c := _shown()
	pot.copper = Game.has_upgrade("caldero_cobre")
	var ready: Dictionary = main.brew_ready
	fc_icon.modulate = Color.WHITE
	if not ready.is_empty():
		var pid: String = ready["potion"]
		pot.col = Data.POTIONS[pid]["color"]
		pot.shine = 1.0
		pot.activity = 0.8
		_set_forecast("res://assets/icons/pot_%s.png" % pid, Data.POTIONS[pid]["name"], Game.stars_for(int(ready["potency"])), pot.col, true)
		tubes.set_mix({}, [])
	else:
		pot.shine = 0.0
		pot.col = main._mix_color(c) if not c.is_empty() else EMPTY_LIQUID
		pot.activity = 0.15 + 0.3 * c.size()
		var m := Game.essence_mix(c)
		var r := Game.evaluate(c)
		tubes.set_mix(m, r.get("top", []) if r.get("potion", "") != "" else [])
		if c.size() < 2:
			_set_forecast("", "", 0, Color.WHITE)
		elif r.get("potion", "") == "":
			fc_icon.modulate = Color(0.55, 0.52, 0.6)
			_set_forecast("res://assets/icons/pot_desconocida.png", "Won't brew", 0, Color(0.6, 0.6, 0.7))
		else:
			var pid: String = r["potion"]
			var known: bool = Game.discovered.has(pid)
			var pot_n := Game.potency_bonus() + int(r["potency"])
			_set_forecast("res://assets/icons/pot_%s.png" % (pid if known else "desconocida"),
				Data.POTIONS[pid]["name"] if known else "New recipe?", Game.stars_for(pot_n), Data.POTIONS[pid]["color"])
	_update_buttons()

# ------------------------------------------------------------------ echar, sacar, vaciar

## Echa un frasco al caldero (clic, tecla 1-8, el frasco del estante de la tienda o el bot).
func throw(id: String) -> void:
	if not _open or not main or busy or _closing or main.busy:
		return
	if not Game.ingredient_unlocked(id):
		return
	var why: String = main.brew_add(id)
	var jt: TextureRect = jar_tex[id]
	if why != "":
		_shake(jt)
		say({"lleno": "Cauldron full", "agotado": "None left", "listo": "Bottle it first!"}.get(why, ""), UIKit.BAD)
		Sfx.play("sad", 0.05, -10.0)
		return
	_guide.erase(id)
	# el frasco se aplasta un poco y el ingrediente salta al caldero
	jt.scale = Vector2(1.12, 0.86)
	create_tween().tween_property(jt, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("bubble_0", 0.1, -8.0)
	_pending += 1
	_refresh_jars()
	_update_buttons()
	var from := jt.get_global_rect().position - stage.get_global_rect().position + Vector2(9 * ART - 32, 0)
	var to := mouth() - Vector2(32, 32) + Vector2(randf_range(-40, 40), -6)
	var f := _flyer("res://assets/icons/ing_%s.png" % id)
	f.position = from
	await _arc(f, from, to, 0.55, 200.0, randf_range(-5.0, 5.0))
	f.queue_free()
	_pending = maxi(0, _pending - 1)
	if not _open:
		return
	Sfx.play("plop", 0.12, -2.0)
	pot.splash(mouth(), main._mix_color(_shown()))
	refresh()
	_pop_slot(_shown().size() - 1)

## Saca el ingrediente del hueco i (vuelve volando a su frasco).
func _take(i: int) -> void:
	if busy or _pending > 0 or not main:
		return
	var id: String = main.brew_take(i)
	if id == "":
		return
	Sfx.play("bubble_1", 0.1, -4.0)
	_hide_tag()
	refresh()
	_fly_back(id, slot_btns[i].position + Vector2(10, 10))

func _empty() -> void:
	if busy or _pending > 0 or not main:
		return
	var before: Array = main.contents.duplicate()
	main._on_empty()
	if not main.contents.is_empty():
		return
	refresh()
	for k in before.size():
		var id: String = before[k]
		var from := mouth() - Vector2(32, 40) + Vector2((k - 1) * 50.0, 0)
		get_tree().create_timer(0.08 * k).timeout.connect(func(): _fly_back(id, from))

func _fly_back(id: String, from: Vector2) -> void:
	if not jar_tex.has(id):
		return
	var jt: TextureRect = jar_tex[id]
	var to := jt.get_global_rect().position - stage.get_global_rect().position + Vector2(9 * ART - 32, 4)
	var f := _flyer("res://assets/icons/ing_%s.png" % id)
	await _arc(f, from, to, 0.45, 160.0, randf_range(-3.0, 3.0))
	f.queue_free()
	if _open:
		Sfx.play("click", 0.08, -10.0)
		jt.scale = Vector2(0.9, 1.1)
		create_tween().tween_property(jt, "scale", Vector2.ONE, 0.15)

func _pop_slot(i: int) -> void:
	if i < 0 or i >= slot_btns.size():
		return
	var ic: TextureRect = slot_btns[i].get_node("Icon")
	ic.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(ic, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _flyer(path: String) -> TextureRect:
	var f := TextureRect.new()
	f.texture = _tex(path)
	f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.size = Vector2(64, 64)
	f.pivot_offset = Vector2(32, 32)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 20
	stage.add_child(f)
	return f

## Vuelo en arco (una parábola) con un giro.
func _arc(f: Control, from: Vector2, to: Vector2, dur: float, height: float, spin: float) -> void:
	var step := func(t: float) -> void:
		if is_instance_valid(f):
			f.position = from.lerp(to, t) + Vector2(0, -4.0 * height * t * (1.0 - t))
			f.rotation = spin * t
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, dur)
	await tw.finished

func _shake(c: Control) -> void:
	var x0 := c.position.x
	var tw := create_tween()
	for i in 3:
		tw.tween_property(c, "position:x", x0 + 6, 0.04)
		tw.tween_property(c, "position:x", x0 - 6, 0.04)
	tw.tween_property(c, "position:x", x0, 0.04)

# ------------------------------------------------------------------ remover (el minijuego, sobre el caldero)

## El minijuego de remover en el caldero grande. Devuelve true si fue perfecto. kind "ink": al terminar, el frasco de
## tinta sale del caldero.
func stir(difficulty := 1.0, kind := "potion") -> bool:
	var ink: Dictionary = Game.ink_for_mix(_shown()) if kind == "ink" else {}
	busy = true
	_update_buttons()
	_refresh_slots()
	var g := StirGame.new()
	g.embedded = true
	g.px = ART
	g.speed = 1.6 + 0.3 * difficulty
	g.position = Vector2.ZERO
	g.size = STAGE_SIZE
	g.center = mouth() + Vector2(0, 2)
	g.radii = Vector2(LIQ_R.x - 5.0, LIQ_R.y - 1.8) * ART
	stage.add_child(g)
	_stir = g
	_catcher.visible = true
	pot.stirring = true
	say("Tap on the gold!", UIKit.TEXT, 6.0)
	var perfect: bool = await g.finished
	_catcher.visible = false
	pot.stirring = false
	say("Perfect!  +1" if perfect else "Nicely stirred!", UIKit.GOLD_BRIGHT if perfect else UIKit.TEXT, 1.4)
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(g):
		g.queue_free()
	_stir = null
	busy = false
	if not ink.is_empty():
		_rise_ink(String(ink["ink"]))
	return perfect

## El frasco de tinta sube del caldero entre chispas y se desvanece (la tinta va a los materiales del grimorio).
func _rise_ink(ink: String) -> void:
	var f := _flyer("res://assets/icons/%s.png" % ink)
	var from := mouth() - Vector2(32, 40)
	f.position = from
	f.scale = Vector2(0.5, 0.5)
	pot.burst(mouth())
	Sfx.play("sparkle", 0.05, -6.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(f, "position", from + Vector2(0, -190), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "scale", Vector2(1.4, 1.4), 0.5)
	tw.tween_property(f, "modulate:a", 0.0, 0.4).set_delay(0.8)
	await tw.finished
	f.queue_free()

## La poción cuajó (main.brew_ready): brilla, se ve en el vapor y «Embotellar» pasa a ser el botón principal.
func show_ready() -> void:
	if not _open:
		return
	pot.burst(mouth())
	refresh()

## Una poción embotellada: el frasco sube del caldero y vuela hasta su hueco del estante del HUD.
func fly_bottle(pid: String, to_global: Vector2) -> void:
	var f := TextureRect.new()
	f.texture = _tex("res://assets/icons/pot_%s.png" % pid)
	f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.size = Vector2(64, 64)
	f.pivot_offset = Vector2(32, 32)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 45
	ui.root.add_child(f)   # encima del estante del HUD (capa 5)
	var m := stage.get_global_transform() * mouth()
	var from := m - Vector2(32, 48)
	var up := from + Vector2(0, -150)
	f.position = from
	f.scale = Vector2(0.5, 0.5)
	pot.burst(mouth())
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(f, "position", up, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "scale", Vector2(1.3, 1.3), 0.35)
	await tw.finished
	await get_tree().create_timer(0.12).timeout
	var step := func(t: float) -> void:
		if is_instance_valid(f):
			f.position = up.lerp(to_global - Vector2(32, 32), t) + Vector2(0, -120.0 * t * (1.0 - t))
			f.rotation = 0.6 * t
	var t2 := create_tween()
	t2.set_parallel(true)
	t2.tween_method(step, 0.0, 1.0, 0.5)
	t2.tween_property(f, "scale", Vector2(0.8, 0.8), 0.5)
	await t2.finished
	f.queue_free()

## Un mensaje corto sobre el caldero ("Caldero lleno", "¡Perfecto! +1"...).
func say(text: String, col := UIKit.GOLD_BRIGHT, dur := 1.3) -> void:
	if text == "":
		return
	msg.text = text
	msg.add_theme_color_override("font_color", col)
	if _msg_tw and _msg_tw.is_valid():
		_msg_tw.kill()
	msg.modulate.a = 1.0
	msg.pivot_offset = msg.size / 2.0
	msg.scale = Vector2(0.85, 0.85)
	_msg_tw = create_tween()
	_msg_tw.tween_property(msg, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_msg_tw.tween_interval(dur)
	_msg_tw.tween_property(msg, "modulate:a", 0.0, 0.35)

## Los frascos que brillan para guiar (el primer pedido del tutorial).
func guide(ids: Array) -> void:
	_guide = ids.duplicate()

# ------------------------------------------------------------------ cada cuadro y teclado

func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	# el brillo de los frascos guía (y del señalado)
	for id in jar_glow:
		var g: TextureRect = jar_glow[id]
		var a := 0.0
		if id in _guide:
			a = 0.45 + 0.35 * sin(_t * 5.0)
		elif id == _hover:
			a = 0.35
		g.modulate.a = lerpf(g.modulate.a, a, minf(1.0, delta * 10.0))
	# la visión flota en el vapor
	fc.position.y = 204.0 + sin(_t * 1.8) * 5.0
	if not main.brew_ready.is_empty():
		fc_glow.modulate.a = 0.6 + 0.25 * sin(_t * 4.0)
		var b: Button = btns["bottle"]
		if not b.disabled:
			b.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.15, 0.9), 0.5 + 0.5 * sin(_t * 5.0))
	else:
		btns["bottle"].modulate = Color.WHITE
	var s: Button = btns["stir"]
	s.modulate = Color(1, 1, 1).lerp(Color(1.2, 1.12, 0.92), 0.5 + 0.5 * sin(_t * 4.0)) if not s.disabled else Color.WHITE

func _unhandled_input(ev: InputEvent) -> void:
	if not _open or ov.is_open():
		return
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var k: int = ev.keycode
	# --- R4 SHIP: Esc / E cierran el banco también con el diálogo de un cliente encima (con la fila de PACE pasa a
	# menudo; antes el banco lo ignoraba y Esc abría los ajustes)
	if k == KEY_ESCAPE or k == KEY_E:
		close()
		get_viewport().set_input_as_handled()
		return
	if ui.dialog_open():
		return
	if k == KEY_SPACE or k == KEY_ENTER:
		if _stir:
			_stir.press()
		elif not btns["bottle"].disabled:
			_on_action("bottle")
		elif not btns["stir"].disabled:
			_on_action("stir")
	elif k >= KEY_1 and k <= KEY_8:
		var i := k - KEY_1
		if i < Data.INGREDIENT_ORDER.size():
			throw(Data.INGREDIENT_ORDER[i])
	elif k == KEY_BACKSPACE:
		var n := _shown().size()
		if n > 0:
			_take(n - 1)
	else:
		return
	get_viewport().set_input_as_handled()

# --- R4 EVENTS: el banco en un evento ------------------------------------------------------------------------------
## main.gd lo enciende el día de un evento: el fondo se oscurece menos (detrás se ve el escenario del evento) y no hay
## botón «Tinta» (la despensa del evento no se convierte en tinta para casa).
var event_mode := false
var _dim: ColorRect

func set_event_mode(on: bool) -> void:
	event_mode = on
	if _dim:
		_dim.color = Color(0.03, 0.02, 0.06, 0.42 if on else 0.8)
	if _open:
		_update_buttons()
# --- end R4 EVENTS

# ================================================================== dibujo: el caldero

class _Pot extends Control:
	const K := 4.0
	const LC := Vector2(52.0, 14.2)
	const LR := Vector2(33.5, 8.2)
	var body_iron: Texture2D = load("res://assets/ui/bench_cauldron_iron.png")
	var body_copper: Texture2D = load("res://assets/ui/bench_cauldron_copper.png")
	var liquid: Texture2D = load("res://assets/ui/bench_liquid.png")
	var bubble: Texture2D = load("res://assets/ui/bench_bubble.png")
	var fire: Texture2D = load("res://assets/ui/bench_fire.png")
	var hearth: Texture2D = load("res://assets/ui/bench_hearth.png")
	var smoke: Texture2D = load("res://assets/fx/smoke.png")
	var glow: Texture2D = load("res://assets/fx/glow.png")
	var spark: Texture2D = load("res://assets/fx/sparkle.png")
	var copper := false
	var col := Color("3b3156")
	var shine := 0.0
	var activity := 0.2
	var stirring := false
	var _shown_col := Color("3b3156")
	var _t := 0.0
	var _bub: Array = []      # [pos (arte), edad, vida]
	var _steam: Array = []    # [pos (px), vel, edad, vida, tamaño]
	var _drops: Array = []    # [pos (px), vel, edad, color]
	var _sparks: Array = []   # [pos (px), vel, edad, vida]
	var _bub_cd := 0.0
	var _steam_cd := 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		_t += delta
		_shown_col = _shown_col.lerp(col, minf(1.0, delta * 4.0))
		# burbujas
		_bub_cd -= delta
		if _bub_cd <= 0.0:
			var rate := lerpf(0.7, 0.12, clampf(activity, 0.0, 1.0))
			if stirring:
				rate = 0.06
			_bub_cd = rate * randf_range(0.6, 1.4)
			var a := randf() * TAU
			var r := sqrt(randf()) * 0.82
			_bub.append([Vector2(LC.x + cos(a) * r * LR.x, LC.y + sin(a) * r * LR.y), 0.0, randf_range(0.45, 0.85)])
			if randf() < 0.3:
				Sfx.play("bubble_%d" % (randi() % 3), 0.15, -22.0)
		for b in _bub:
			b[1] += delta
		_bub = _bub.filter(func(b): return b[1] < b[2])
		# vapor
		_steam_cd -= delta
		if _steam_cd <= 0.0:
			_steam_cd = randf_range(0.18, 0.34) * (0.6 if shine > 0.0 or stirring else 1.0)
			var p := Vector2(LC.x + randf_range(-0.6, 0.6) * LR.x, LC.y - 2.0) * K
			_steam.append([p, Vector2(randf_range(-10, 10), randf_range(-70, -46)), 0.0, randf_range(1.8, 2.8), randf_range(40.0, 64.0)])
		for s in _steam:
			s[2] += delta
			s[0] += s[1] * delta
			s[1].x += sin(_t * 1.5 + s[4]) * 6.0 * delta
		_steam = _steam.filter(func(s): return s[2] < s[3])
		# salpicaduras
		for d in _drops:
			d[2] += delta
			d[1].y += 620.0 * delta
			d[0] += d[1] * delta
		_drops = _drops.filter(func(d): return d[2] < 0.7)
		# destellos
		for s in _sparks:
			s[2] += delta
			s[0] += s[1] * delta
			s[1] *= 0.96
		_sparks = _sparks.filter(func(s): return s[2] < s[3])
		if shine > 0.0 and randf() < delta * 6.0:
			var q := Vector2(LC.x + randf_range(-0.7, 0.7) * LR.x, LC.y + randf_range(-0.5, 0.4) * LR.y) * K
			_sparks.append([q, Vector2(randf_range(-8, 8), randf_range(-60, -30)), 0.0, randf_range(0.6, 1.0)])
		queue_redraw()

	func splash(at_stage: Vector2, c: Color) -> void:
		var p := at_stage - position
		for i in 9:
			_drops.append([p + Vector2(randf_range(-12, 12), 0), Vector2(randf_range(-140, 140), randf_range(-330, -170)), 0.0, c.lightened(0.25)])
		_bub_cd = 0.0

	func burst(at_stage: Vector2) -> void:
		var p := at_stage - position
		for i in 22:
			_sparks.append([p + Vector2(randf_range(-60, 60), randf_range(-10, 10)), Vector2(randf_range(-90, 90), randf_range(-260, -90)), 0.0, randf_range(0.6, 1.1)])
		for i in 4:
			_steam.append([p + Vector2(randf_range(-50, 50), -8), Vector2(randf_range(-20, 20), randf_range(-90, -60)), 0.0, 1.6, randf_range(56.0, 80.0)])

	func _snap(p: Vector2) -> Vector2:
		return (p / K).floor() * K

	func _draw() -> void:
		var fire_pulse := 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 3.1)
		# luz cálida del fuego detrás del caldero
		draw_texture_rect(glow, Rect2(Vector2(52 - 84, -8) * K, Vector2(168, 120) * K), false, Color(1.0, 0.55, 0.22, 0.30 * fire_pulse))
		if shine > 0.0:
			draw_texture_rect(glow, Rect2(Vector2(52 - 60, -36) * K, Vector2(120, 80) * K), false, Color(_shown_col.r, _shown_col.g, _shown_col.b, 0.35))
		# el hogar
		draw_texture_rect(hearth, Rect2(Vector2(52 - 60, 74) * K, Vector2(120, 18) * K), false)
		# el líquido (gris teñido con el color de la mezcla) y sus burbujas
		var lc := _shown_col
		if shine > 0.0:
			lc = lc.lerp(Color.WHITE, 0.12 + 0.1 * sin(_t * 4.0))
		draw_texture_rect(liquid, Rect2(Vector2.ZERO, Vector2(104, 80) * K), false, lc)
		var bc := lc.lightened(0.5)
		for b in _bub:
			var f := clampi(int(b[1] / b[2] * 3.0), 0, 2)
			var p: Vector2 = (b[0] - Vector2(3.5, 3.5)).floor() * K
			draw_texture_rect_region(bubble, Rect2(p, Vector2(7, 7) * K), Rect2(f * 7, 0, 7, 7), bc)
		# el cuerpo del caldero (tapa el líquido fuera de la boca)
		draw_texture_rect(body_copper if copper else body_iron, Rect2(Vector2.ZERO, Vector2(104, 80) * K), false)
		# el fuego, delante de la base de la panza (entre las patas)
		var fi := int(_t * 9.0) % 4
		draw_texture_rect_region(fire, Rect2(Vector2(52 - 32, 47) * K, Vector2(64, 30) * K), Rect2(fi * 64, 0, 64, 30))
		# brasas
		for i in 5:
			var ex := 52.0 - 18.0 + i * 9.0 + sin(_t * 3.0 + i) * 1.5
			var ey := 75.0 - absf(sin(_t * 7.0 + i * 1.3)) * 2.0
			draw_rect(Rect2(_snap(Vector2(ex, ey) * K), Vector2(K, K)), Color(1.0, 0.75, 0.3, 0.8))
		# vapor
		for s in _steam:
			var a: float = s[2] / s[3]
			var sz: float = s[4] * (0.7 + 0.8 * a)
			var alpha := (1.0 - a) * minf(1.0, s[2] * 3.0) * 0.32
			var sc := _shown_col.lerp(Color.WHITE, 0.65)
			draw_texture_rect(smoke, Rect2(_snap(s[0] - Vector2(sz, sz) / 2.0), Vector2(sz, sz)), false, Color(sc.r, sc.g, sc.b, alpha))
		# salpicaduras
		for d in _drops:
			var a: float = 1.0 - d[2] / 0.7
			var c: Color = d[3]
			draw_rect(Rect2(_snap(d[0]), Vector2(K, K)), Color(c.r, c.g, c.b, a))
		# destellos
		for s in _sparks:
			var a: float = 1.0 - s[2] / s[3]
			var tw := 0.6 + 0.4 * sin(_t * 20.0 + s[3] * 10.0)
			draw_texture_rect(spark, Rect2(_snap(s[0]) - Vector2(14, 14), Vector2(28, 28)), false, Color(1.0, 0.95, 0.7, a * tw))

# ================================================================== dibujo: los tubos de las esencias

class _Tubes extends Control:
	const K := 4.0
	const TX := [13, 31, 49, 67, 85]
	const BOT := 43
	var rack: Texture2D = load("res://assets/ui/bench_rack.png")
	var glow: Texture2D = load("res://assets/fx/glow.png")
	var icons := {}
	var level := {}
	var target := {}
	var lead: Array = []
	var _t := 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for e in Data.ESSENCE_ORDER:
			level[e] = 0.0
			target[e] = 0.0
			var p := "res://assets/ui/ess_%s.png" % e
			icons[e] = load(p) if ResourceLoader.exists(p) else null

	func set_mix(m: Dictionary, top: Array) -> void:
		for e in Data.ESSENCE_ORDER:
			target[e] = float(m.get(e, 0))
		lead = top.duplicate()

	func _process(delta: float) -> void:
		_t += delta
		for e in level:
			level[e] = move_toward(level[e], target[e], delta * 14.0)
		queue_redraw()

	func _draw() -> void:
		for i in Data.ESSENCE_ORDER.size():
			var e: String = Data.ESSENCE_ORDER[i]
			var cx: float = TX[i]
			var base: Color = Data.ESSENCES[e]["color"]
			var is_lead: bool = e in lead
			if is_lead:
				var ga := 0.45 + 0.2 * sin(_t * 4.0 + i)
				draw_texture_rect(glow, Rect2(Vector2(cx - 14, 6) * K, Vector2(28, 44) * K), false, Color(base.r, base.g, base.b, ga))
			var v: float = minf(level[e], 7.5)
			if v > 0.05:
				var rows := int(round(v * 4.0))
				var top := BOT + 1 - rows
				var c := base if (is_lead or lead.is_empty()) else base.darkened(0.4)
				draw_rect(Rect2(Vector2(cx - 3, top) * K, Vector2(7, BOT - top) * K), c)
				draw_rect(Rect2(Vector2(cx - 2, BOT) * K, Vector2(5, 1) * K), c.darkened(0.1))
				draw_rect(Rect2(Vector2(cx - 3, top) * K, Vector2(7, 1) * K), c.lightened(0.45))
				# una rayita por unidad (se cuentan sin números)
				var u := 1
				while BOT + 1 - u * 4 > top:
					draw_rect(Rect2(Vector2(cx + 2, BOT + 1 - u * 4) * K, Vector2(1, 1) * K), c.darkened(0.3))
					u += 1
				# burbujitas que suben en los tubos que mandan
				if is_lead:
					var by := BOT - fposmod(_t * 7.0 + i * 3.0, float(rows))
					draw_rect(Rect2(Vector2(cx - 1, floorf(by)) * K, Vector2(1, 1) * K), c.lightened(0.6))
		draw_texture_rect(rack, Rect2(Vector2.ZERO, Vector2(98, 60) * K), false)
		for i in Data.ESSENCE_ORDER.size():
			var e: String = Data.ESSENCE_ORDER[i]
			if icons[e]:
				var m := Color.WHITE if (e in lead or level[e] > 0.05 or lead.is_empty()) else Color(0.6, 0.58, 0.65)
				draw_texture_rect(icons[e], Rect2(Vector2(TX[i] - 5, 48) * K, Vector2(11, 11) * K), false, m)
