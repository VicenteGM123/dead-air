extends CanvasLayer
class_name BallUI
## --- R4 RAVEN: la bola de cristal de Krápido, el centro de control de los pedidos a domicilio.
## Una bola de cristal grande sobre su pie de latón (tres garras de cuervo). Dentro flotan los pedidos como tarjetitas de
## papel: la cara de quien pide, lo que pide en una línea, la pista en iconos (las dos esencias), la runa si la lleva y
## un reloj (un aro): cuánto falta para que pase Graznido o, si ya está en la ventanilla, cuánto le queda esperando.
## A la derecha: el letrero de Krápido, cómo anda Graznido, las plumas (la calificación) y el estante de pociones: con
## Graznido esperando, tocar una poción se la da (main._on_potion -> Krapido.take_potion).
## Va en la capa 4, como el banco del caldero: debajo del HUD (capa 5) y de los paneles grandes (capa 10). Es una
## pantalla de trabajo: no para el reloj del día. Fuera de la bola, una medalla en el HUD (abajo a la izquierda) dice
## cuántos pedidos hay y late cuando el cuervo espera; tocarla lleva a la alquimista a la bola.
## Ratón; teclado (Esc o E cierra, ← → eligen la poción, Intro o Espacio se la dan a Graznido, 1-5 acercan una
## tarjeta); mando (PadCursor: A toca, B cierra, LB / RB saltan entre tarjetas, pociones y botones).
## Arte: assets/ui/ball_*.png, pluma_*.png, krapido_*.png, raven_head.png (tools/arte/raven_art.py).

signal opened
signal closed

const ART := 4.0
const STAGE_SIZE := Vector2(1920, 1080)
const BALL_C := Vector2(690, 466)          # centro de la bola en el escenario
const BALL_R := 312.0                      # radio del cristal (78 px de arte x 4)
const CARD := Vector2(256, 178)
const SHELF_K := 4.0
const SHELF_SLOT_X := [15, 35, 55, 75, 95, 115]
const LAYOUTS := {
	1: [Vector2(0, -6)],
	2: [Vector2(0, -102), Vector2(0, 98)],
	3: [Vector2(0, -122), Vector2(-138, 82), Vector2(138, 82)],
	4: [Vector2(-136, -98), Vector2(136, -98), Vector2(-136, 98), Vector2(136, 98)],
	5: [Vector2(0, -150), Vector2(-150, -14), Vector2(150, -14), Vector2(-84, 140), Vector2(84, 140)],
}
const INK := Color("3a2618")
const CREAM := Color("f2e2b8")

var main
var k                                      # Krapido (scripts/krapido.gd)
var ui: GameUI
var ov: Overlays
var root: Control                          # pantalla completa (tapa el escenario 3D para el ratón)
var stage: Control                         # 1920x1080 centrado
var cards_box: Control
var mist: _Mist
var glow: TextureRect
var empty_box: Control
var status_ring: _Ring
var status_icon: TextureRect
var status_time: Label
var status_text: Label
var status_sub: Label
var plumas_row: HBoxContainer
var plumas_num: Label
var tray: Control
var tray_art: TextureRect
var tray_btns: Array = []
var tray_glow: ColorRect
var tray_arrow: Label
var sel_frame: Panel
var close_btn: TextureButton
var badge: Button                          # la medalla del HUD (en ui.root)
var badge_ring: _Ring
var badge_count: Label
var badge_tag: PanelContainer
var _cards := {}                           # id del pedido -> Button
var _card_ring := {}                       # id -> _Ring
var _card_badge := {}                      # id -> TextureRect (Graznido espera por este)
var _focus := -1                           # id de la tarjeta acercada (-1: ninguna)
var _sel := 0                              # poción elegida con el teclado
var _open := false
var _closing := false
var _t := 0.0
var _head_cache := {}                      # sprite -> fila de arriba (para recortar la cabeza)
var _ticket_was := false
var _tip_was := false
var _shelf_was := false

func setup(m, krapido) -> void:
	main = m
	k = krapido
	ui = m.ui
	ov = m.ov

func _ready() -> void:
	layer = 4
	visible = false
	UIKit.load_fonts()
	PaperKit.load_fonts()
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
	_build_ball()
	_build_side()
	_build_tray()
	_build_close()
	_build_badge()
	_build_counter_chip()   # --- R4 MERGE
	k.orders_changed.connect(func():
		if _open:
			_rebuild_cards()
		_refresh_badge())
	k.raven_changed.connect(func():
		if _open:
			_rebuild_cards())
	Game.potions_changed.connect(func():
		if _open:
			_rebuild_tray())

# ------------------------------------------------------------------ montaje

func _build_backdrop() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.07, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var vg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.38, 0.45)
	gt.fill_to = Vector2(1.0, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(0.22, 0.16, 0.42, 0.35))
	g.set_color(1, Color(0, 0, 0, 0.6))
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	vg.texture = gt
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vg)

func _art(path: String, pos: Vector2, parent: Control, kk := ART) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(path) if ResourceLoader.exists(path) else null
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	if tr.texture:
		tr.size = tr.texture.get_size() * kk
	tr.position = pos
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr

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

## La bola: el fondo (interior), la niebla que gira, las tarjetas, el cristal (brillos) y el pie con las garras.
func _build_ball() -> void:
	# sombra en el suelo
	var sh := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = g
	sh.texture = gt
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.stretch_mode = TextureRect.STRETCH_SCALE
	sh.position = Vector2(BALL_C.x - 420, 980)
	sh.size = Vector2(840, 90)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(sh)
	_art("res://assets/ui/ball_back.png", BALL_C - Vector2(320, 320), stage)
	# luz interior (late cuando llega un pedido)
	glow = TextureRect.new()
	var gt2 := GradientTexture2D.new()
	gt2.fill = GradientTexture2D.FILL_RADIAL
	gt2.fill_from = Vector2(0.5, 0.5)
	gt2.fill_to = Vector2(1.0, 0.5)
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.62, 0.5, 1.0, 0.55))
	g2.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	gt2.gradient = g2
	glow.texture = gt2
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = BALL_C - Vector2(BALL_R, BALL_R)
	glow.size = Vector2(BALL_R, BALL_R) * 2.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	glow.modulate.a = 0.35
	stage.add_child(glow)
	mist = _Mist.new()
	mist.center = BALL_C
	mist.radius = BALL_R - 14.0
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(mist)
	# sin pedidos: el logo apagado y dos palabras
	empty_box = Control.new()
	empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(empty_box)
	var logo := _art("res://assets/ui/krapido_logo.png", BALL_C - Vector2(56, 96), empty_box)
	logo.modulate = Color(1, 1, 1, 0.35)
	var el := PaperKit.hand("No orders", 44, Color(0.78, 0.72, 0.98, 0.8), true, HORIZONTAL_ALIGNMENT_CENTER)
	el.position = BALL_C + Vector2(-200, 30)
	el.size = Vector2(400, 60)
	empty_box.add_child(el)
	cards_box = Control.new()
	cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(cards_box)
	_art("res://assets/ui/ball_front.png", BALL_C - Vector2(320, 320), stage)
	_art("res://assets/ui/ball_stand.png", Vector2(BALL_C.x - 368, BALL_C.y + BALL_R + 8 - 176), stage)

## A la derecha: el letrero de Krápido, Graznido y las plumas.
func _build_side() -> void:
	var x0 := 1150.0
	var logo := _art("res://assets/ui/krapido_logo.png", Vector2(x0 + 6, 66), stage)
	logo.pivot_offset = logo.size / 2.0
	var title := UIKit.shadow(UIKit.label("Crow Delivery", 76, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold), 3)
	title.position = Vector2(x0 + 140, 56)
	stage.add_child(title)
	var tag := PaperKit.hand(String(Data.KRAPIDO["tagline"]), 38, CREAM, false)
	tag.position = Vector2(x0 + 146, 140)
	stage.add_child(tag)
	# Graznido: una tarjeta de papel con su cabeza, su reloj y una frase corta
	var card := PaperKit.panel("card", Vector2(22, 14))
	card.position = Vector2(x0, 222)
	card.custom_minimum_size = Vector2(700, 178)
	card.size = Vector2(700, 178)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(card)
	var h := UIKit.hbox(22)
	card.add_child(h)
	status_icon = TextureRect.new()
	status_icon.texture = load("res://assets/ui/raven_head.png")
	status_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_icon.custom_minimum_size = Vector2(108, 96)
	status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(status_icon)
	status_ring = _Ring.new()
	status_ring.custom_minimum_size = Vector2(112, 112)
	status_ring.radius = 48.0
	status_ring.width = 10.0
	status_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(status_ring)
	status_time = UIKit.label("", 38, CREAM, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	status_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_time.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_ring.add_child(status_time)
	var v := UIKit.vbox(0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	status_text = PaperKit.hand("", 46, INK, true)
	v.add_child(status_text)
	status_sub = PaperKit.hand("", 34, PaperKit.INK_SOFT, false)
	v.add_child(status_sub)
	# las plumas (la calificación de Krápido)
	plumas_row = UIKit.hbox(6)
	plumas_row.position = Vector2(x0 + 14, 432)
	stage.add_child(plumas_row)
	for i in 5:
		var f := TextureRect.new()
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.stretch_mode = TextureRect.STRETCH_SCALE
		f.custom_minimum_size = Vector2(14, 20) * 3.6
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plumas_row.add_child(f)
	plumas_num = UIKit.shadow(PaperKit.hand("", 64, UIKit.GOLD_BRIGHT, true), 3)
	plumas_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plumas_row.add_child(PaperKit.gap(0, 10))
	plumas_row.add_child(plumas_num)
	var pl := PaperKit.hand("feathers", 36, CREAM, false)   # --- R5 EN-UI
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plumas_row.add_child(pl)

## El estante de pociones (las del HUD, más grandes): tocar una se la da a Graznido.
func _build_tray() -> void:
	tray = Control.new()
	tray.position = Vector2(1150 + 90, 610)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(tray)
	tray_glow = ColorRect.new()
	tray_glow.color = Color(1.0, 0.78, 0.4, 0.0)
	tray_glow.position = Vector2(-18, -18)
	tray_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_child(tray_glow)
	tray_art = TextureRect.new()
	tray_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tray_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tray_art.stretch_mode = TextureRect.STRETCH_SCALE
	tray_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_child(tray_art)
	tray_arrow = UIKit.shadow(UIKit.label("▼", 54, UIKit.GOLD_BRIGHT, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER), 3)
	tray_arrow.size = Vector2(80, 60)
	tray.add_child(tray_arrow)
	sel_frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color("f0d58a")
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(8)
	sel_frame.add_theme_stylebox_override("panel", sb)
	sel_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_frame.visible = false
	tray.add_child(sel_frame)

func _rebuild_tray() -> void:
	for b in tray_btns:
		b.queue_free()
	tray_btns.clear()
	var cap := Game.potion_capacity()
	var rows := 2 if cap > 6 else 1
	var tex: Texture2D = load("res://assets/ui/hud_shelf%d.png" % (rows * 6))
	tray_art.texture = tex
	tray_art.size = tex.get_size() * SHELF_K
	tray_glow.size = tray_art.size + Vector2(36, 36)
	tray_arrow.position = Vector2(tray_art.size.x / 2.0 - 40, -74)
	for i in cap:
		var r := i / 6
		var col := i % 6
		var b := _flat_button(Vector2((SHELF_SLOT_X[col] - 10) * SHELF_K, (7.0 + r * 31.0) * SHELF_K), Vector2(20, 31) * SHELF_K)
		tray.add_child(b)
		tray_btns.append(b)
		if i >= Game.potions.size():
			b.disabled = true
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		var p: Dictionary = Game.potions[i]
		var ic := TextureRect.new()
		ic.texture = load("res://assets/icons/pot_%s.png" % p["id"])
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_SCALE
		ic.size = Vector2(16, 16) * SHELF_K
		ic.position = Vector2(2, 6) * SHELF_K
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.name = "Icon"
		b.add_child(ic)
		var st := HBoxContainer.new()
		st.add_theme_constant_override("separation", 1)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.position = Vector2(1.5, 23.5) * SHELF_K
		for kk in 3:
			st.add_child(UIKit.icon("res://assets/ui/shelf_star.png" if kk < Game.stars_for(int(p["potency"])) else "res://assets/ui/shelf_star_empty.png", SHELF_K))
		b.add_child(st)
		var gy := 2.0
		for rk in ["rune", "rune2"]:
			var rune := String(p.get(rk, ""))
			if rune != "" and ResourceLoader.exists("res://assets/icons/rune_%s.png" % rune):
				var gl := UIKit.icon("res://assets/icons/rune_%s.png" % rune, 1.25)
				gl.position = Vector2(b.size.x - 30, gy)
				b.add_child(gl)
				gy += 30.0
		var idx := i
		b.tooltip_text = String(Data.POTIONS[p["id"]]["name"])
		b.pressed.connect(func(): _give(idx))
		b.mouse_entered.connect(func():
			_sel = idx
			Sfx.play("hover", 0.05, -14.0)
			var tw := ic.create_tween()
			tw.tween_property(ic, "position:y", 3 * SHELF_K, 0.08))
		b.mouse_exited.connect(func():
			if is_instance_valid(ic):
				var tw := ic.create_tween()
				tw.tween_property(ic, "position:y", 6 * SHELF_K, 0.1))
	_sel = clampi(_sel, 0, maxi(0, Game.potions.size() - 1))

func _build_close() -> void:
	close_btn = TextureButton.new()
	close_btn.texture_normal = load("res://assets/ui/bench_close.png")
	close_btn.texture_hover = load("res://assets/ui/bench_close_hover.png")
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

## La medalla del HUD (abajo a la izquierda): la bolita, cuántos pedidos hay y el reloj de Graznido si espera.
func _build_badge() -> void:
	badge = Button.new()
	badge.flat = true
	badge.focus_mode = Control.FOCUS_NONE
	badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		badge.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	UIKit.place(badge, Vector2(0, 1), Vector2(26, -132), Vector2(108, 108), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	badge.tooltip_text = "Crow Delivery"
	badge.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		if main._brew_open():   # --- R4 MERGE: con el banco abierto, primero se cierra (embotella lo removido)
			if main.brew.is_busy():
				return
			await main.brew.close()
		k.go_ball())
	badge.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	badge_ring = _Ring.new()
	badge_ring.radius = 50.0
	badge_ring.width = 7.0
	badge_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_ring)
	var ic := TextureRect.new()
	ic.texture = load("res://assets/ui/krapido_badge.png")
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_SCALE
	ic.size = Vector2(26, 28) * 3.0
	ic.position = Vector2(54 - 39, 54 - 44)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.name = "Icon"
	badge.add_child(ic)
	badge_tag = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("9e2b25")
	sb.border_color = Color("f4e4bd")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = -2
	sb.content_margin_bottom = -1
	badge_tag.add_theme_stylebox_override("panel", sb)
	badge_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_tag.position = Vector2(78, -6)
	badge_count = UIKit.label("0", 28, Color("f4e4bd"), PaperKit.font_hand_bold, HORIZONTAL_ALIGNMENT_CENTER)
	badge_tag.add_child(badge_count)
	badge.add_child(badge_tag)
	badge.visible = false
	ui.root.add_child(badge)

# ------------------------------------------------------------------ las tarjetas

## Vuelve a armar las tarjetas según los pedidos de Krápido (k.orders).
func _rebuild_cards() -> void:
	for c in cards_box.get_children():
		c.queue_free()
	_cards.clear()
	_card_ring.clear()
	_card_badge.clear()
	var list: Array = k.orders.duplicate()
	list.sort_custom(func(a, b): return float(a["pickup"]) < float(b["pickup"]))
	list = list.slice(0, 5)
	var n := list.size()
	empty_box.visible = n == 0
	if n == 0:
		_focus = -1
		return
	var lay: Array = LAYOUTS[n]
	var sc := 1.0 if n <= 3 else (0.9 if n == 4 else 0.8)
	for i in n:
		var o: Dictionary = list[i]
		var c := _make_card(o)
		c.scale = Vector2.ONE * sc
		c.set_meta("home", BALL_C + lay[i] - CARD / 2.0)
		c.set_meta("scale", sc)
		c.set_meta("phase", float(i) * 1.7)
		c.position = c.get_meta("home")
		cards_box.add_child(c)
		_cards[int(o["id"])] = c
	if not _cards.has(_focus):
		_focus = -1

func _make_card(o: Dictionary) -> Button:
	var b := _flat_button(Vector2.ZERO, CARD)
	b.pivot_offset = CARD / 2.0
	var id := int(o["id"])
	b.pressed.connect(func(): _toggle_focus(id))
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	var paper := Panel.new()
	paper.add_theme_stylebox_override("panel", PaperKit.nine("card", Vector2(10, 8)))
	paper.size = CARD
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(paper)
	# la cara de quien pide, en su marquito
	var frame := TextureRect.new()
	frame.texture = load("res://assets/ui/ticket_frame.png")
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = Vector2(70, 70)
	frame.position = Vector2(14, 12)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(frame)
	var face := TextureRect.new()
	face.texture = head_of(String(o["who"]))
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.size = Vector2(57, 57)
	face.position = Vector2(6.5, 6.5)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(face)
	var cname := Story.char_name(String(o["who"]))
	# --- R5 MERGE: el nombre se achica (hasta 18 px) para caber en su caja de 118 px; si aun así no cabe («Father
	# Anselmo» se cortaba a 20 px), va en dos renglones a 20 px. El reloj de la esquina no deja ensanchar la caja.
	UIKit.load_fonts()
	var nfont: Font = UIKit.font_sc_bold
	var nsize := 24 if cname.length() <= 8 else 20
	while nsize > 18 and nfont.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x > 116.0:
		nsize -= 1
	var two := cname.contains(" ") and nfont.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x > 116.0
	if two:
		nsize = 20
	var nm := UIKit.label(cname, nsize, Color("7a1d18"), nfont)
	if two:
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD
		nm.add_theme_constant_override("line_spacing", -9)
		nm.position = Vector2(94, 0)
		nm.size = Vector2(118, 50)
	else:
		nm.position = Vector2(94, 16 if nsize >= 24 else 18)
		nm.size = Vector2(118, 30)
		nm.clip_text = true
	# --- end R5 MERGE
	b.add_child(nm)
	# lo que pide (a mano, dos líneas)
	var line := PaperKit.hand(String(o["line"]), 27, INK, false, HORIZONTAL_ALIGNMENT_LEFT, 226.0)
	line.position = Vector2(16, 84)
	line.size = Vector2(226, 60)
	line.add_theme_constant_override("line_spacing", -7)
	b.add_child(line)
	# la pista: las dos esencias; y la runa si la pide
	var hint := UIKit.hbox(4)
	hint.position = Vector2(94, 46)
	b.add_child(hint)
	var ess: Array = o.get("ess", [])
	if ess.size() == 2:
		hint.add_child(UIKit.ess_icon(String(ess[0]), 2.4))
		hint.add_child(UIKit.label("+", 22, INK, UIKit.font_bold))
		hint.add_child(UIKit.ess_icon(String(ess[1]), 2.4))
	for r in o.get("runes", []):
		var rp := "res://assets/icons/rune_%s.png" % String(r)
		if ResourceLoader.exists(rp):
			var ri := UIKit.icon(rp, 1.15)
			ri.tooltip_text = Story.rune_name(String(r))
			hint.add_child(PaperKit.gap(0, 4))
			hint.add_child(ri)
	# el reloj: un sello redondo que asoma por la esquina de la tarjeta
	var ring := _Ring.new()
	ring.radius = 25.0
	ring.width = 7.0
	ring.size = Vector2(60, 60)
	ring.position = Vector2(CARD.x - 42, -18)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ring)
	var num := UIKit.label("", 21, CREAM, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.name = "Num"
	ring.add_child(num)
	_card_ring[id] = ring
	# Graznido espera por este pedido: un borde ámbar que late y su cabeza junto al reloj
	var rb := Control.new()
	rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rb.visible = false
	b.add_child(rb)
	b.move_child(rb, 1)
	var border := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color(1.0, 0.76, 0.34)
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(10)
	sb.expand_margin_left = 6
	sb.expand_margin_right = 6
	sb.expand_margin_top = 6
	sb.expand_margin_bottom = 6
	border.add_theme_stylebox_override("panel", sb)
	border.size = CARD
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.name = "Border"
	rb.add_child(border)
	var head := TextureRect.new()
	head.texture = load("res://assets/ui/raven_head.png")
	head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head.stretch_mode = TextureRect.STRETCH_SCALE
	head.size = Vector2(18, 16) * 3.6
	head.position = Vector2(CARD.x - 108, -30)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.name = "Head"
	rb.add_child(head)
	_card_badge[id] = rb
	return b

## La cara (cabeza) del primer cuadro de su sprite, recortada desde la primera fila con píxeles (como el ticket).
func head_of(who: String) -> Texture2D:
	var sid := Story.sprite_id(who)
	var path := "res://assets/chars/%s_idle.png" % sid
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var fw := tex.get_width() / 2
	if not _head_cache.has(sid):
		var top := 6
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			top = -1
			for y in img.get_height():
				for x in range(8, fw - 8):
					if img.get_pixel(x, y).a > 0.5:
						top = y
						break
				if top >= 0:
					break
			top = maxi(0, top)
		_head_cache[sid] = top
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2((fw - 36) / 2, maxi(0, int(_head_cache[sid]) - 2), 36, 36)
	return at

func _toggle_focus(id: int) -> void:
	_focus = -1 if _focus == id else id
	Sfx.play("page", 0.08, -10.0)
	var c: Control = _cards.get(id)
	if c and _focus == id:
		cards_box.move_child(c, cards_box.get_child_count() - 1)

# ------------------------------------------------------------------ abrir y cerrar

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	_closing = false
	visible = true
	_focus = -1
	_rebuild_cards()
	_rebuild_tray()
	_hud(false)
	root.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	stage.position.y = 18.0
	tw.tween_property(stage, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("ball_chime", 0.05, -12.0)
	opened.emit()

func close() -> void:
	if not _open or _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.15)
	await tw.finished
	if not _open:
		return
	_finish_close()

func close_now() -> void:
	if not _open:
		return
	_finish_close()

func _finish_close() -> void:
	_open = false
	_closing = false
	visible = false
	if counter_chip:
		counter_chip.visible = false   # --- R4 MERGE
	_hud(true)
	closed.emit()

## Con la bola abierta se esconden el menú, el ticket, el consejo y el estante del HUD (la bola trae el suyo).
func _hud(on: bool) -> void:
	if not on:
		_ticket_was = ui.order_card.visible
		_tip_was = ui.tip_panel.visible
		_shelf_was = ui.potion_panel.visible
		ui.order_card.visible = false
		ui.tip_panel.visible = false
		ui.potion_panel.visible = false
		ui.set_bench_mode(true)
		ui.hide_tooltip()
		main.top_box.visible = false
		main.world.block_hover(true)
	else:
		if _ticket_was and main.customer_ready:
			ui.order_card.visible = true
		if _tip_was:
			ui.tip_panel.visible = true
		ui.potion_panel.visible = _shelf_was and not main.in_market
		ui.set_bench_mode(false)
		ui.hide_tooltip()
		main.top_box.visible = true
		main._update_top_buttons()
		main.world.block_hover(false)

## Una poción del estante de la bola: si Graznido espera, se la da (main._on_potion -> Krapido.take_potion).
func _give(i: int) -> void:
	if k.raven_waiting():
		Sfx.play("click", 0.05, -4.0)
		main._on_potion(i)
		return
	Sfx.play("sad", 0.05, -12.0)
	if i < tray_btns.size():
		var b: Control = tray_btns[i]
		var tw := b.create_tween()
		for j in 3:
			tw.tween_property(b, "position:x", b.position.x + 6, 0.04)
			tw.tween_property(b, "position:x", b.position.x - 6, 0.04)
		tw.tween_property(b, "position:x", b.position.x, 0.04)
	_flash_status()

func _flash_status() -> void:
	var tw := status_text.create_tween()
	tw.tween_property(status_text, "modulate", Color(1.6, 0.6, 0.5), 0.1)
	tw.tween_property(status_text, "modulate", Color.WHITE, 0.4)

# ------------------------------------------------------------------ cada cuadro

func _process(delta: float) -> void:
	_t += delta
	_refresh_badge()
	_refresh_counter_chip()   # --- R4 MERGE
	if not _open:
		return
	# las tarjetas flotan; la acercada va al centro y crece
	for id in _cards:
		var c: Button = _cards[id]
		var ph: float = c.get_meta("phase")
		var home: Vector2 = c.get_meta("home")
		var goal := home + Vector2(sin(_t * 0.9 + ph) * 5.0, sin(_t * 1.3 + ph) * 7.0)
		var sc: float = c.get_meta("scale")
		if id == _focus:
			goal = BALL_C - CARD / 2.0
			sc = 1.32
		elif _focus != -1:
			sc *= 0.92
		c.position = c.position.lerp(goal, 1.0 - exp(-8.0 * delta))
		c.scale = c.scale.lerp(Vector2.ONE * sc, 1.0 - exp(-10.0 * delta))
		c.rotation = sin(_t * 0.7 + ph * 1.3) * 0.025
		c.modulate = Color(1, 1, 1, 0.55 if (_focus != -1 and id != _focus) else 1.0)
	# los relojes de las tarjetas
	for o in k.orders:
		var id := int(o["id"])
		if not _card_ring.has(id):
			continue
		var ring: _Ring = _card_ring[id]
		var num: Label = ring.get_node("Num")
		var waiting: bool = k.raven_waiting() and not k.raven_order.is_empty() and int(k.raven_order["id"]) == id
		_card_badge[id].visible = waiting
		if waiting:
			var f: float = k.raven_left / Krapido.RAVEN_WAIT
			ring.frac = f
			ring.color = _wait_color(f)
			num.text = str(int(ceil(k.raven_left)))
			var rbx: Control = _card_badge[id]
			rbx.get_node("Head").position.y = -30.0 + sin(_t * 8.0) * 3.0
			rbx.get_node("Border").modulate.a = 0.55 + 0.45 * sin(_t * 6.0)
		else:
			var left: float = k.time_to_pickup(o)
			var lead := maxf(1.0, float(o.get("lead", 60.0)))
			ring.frac = left / lead
			ring.color = Color(0.56, 0.85, 1.0)
			if left <= 0.0:
				ring.frac = 1.0
				ring.color = Color(1.0, 0.9, 0.55).lerp(Color(1, 1, 1), 0.5 + 0.5 * sin(_t * 6.0))
				num.text = "…"
			else:
				num.text = str(int(ceil(left)))
		ring.queue_redraw()
	# la luz y la niebla de la bola
	glow.modulate.a = 0.3 + 0.12 * sin(_t * 1.6) + (0.25 if k.raven_waiting() else 0.0)
	mist.t = _t
	mist.queue_redraw()
	_refresh_side()

func _wait_color(f: float) -> Color:
	if f < 0.25:
		return Color(1.0, 0.42, 0.36).lerp(Color(1.3, 0.75, 0.6), 0.5 + 0.5 * sin(_t * 11.0))
	if f < 0.55:
		return Color(1.0, 0.76, 0.34)
	return Color(0.6, 0.95, 0.55)

## Graznido, las plumas y el estante, según cómo va el día.
func _refresh_side() -> void:
	var waiting: bool = k.raven_waiting()
	if waiting:
		status_icon.modulate = Color.WHITE
		status_icon.position.y = sin(_t * 6.0) * 3.0
		var f: float = k.raven_left / Krapido.RAVEN_WAIT
		status_ring.frac = f
		status_ring.color = _wait_color(f)
		status_time.text = str(int(ceil(k.raven_left)))
		status_text.text = "At the window!"
		status_sub.text = "Give him a potion"
	else:
		status_icon.modulate = Color(0.55, 0.5, 0.62, 0.8)
		status_icon.position.y = 0.0
		var next := INF
		var lead := 60.0
		for o in k.orders:
			if String(o["state"]) == "incoming":
				var tt: float = k.time_to_pickup(o)
				if tt < next:
					next = tt
					lead = maxf(1.0, float(o.get("lead", 60.0)))
		if k.raven_state == "arriving":
			status_ring.frac = 1.0
			status_ring.color = Color(1.0, 0.9, 0.55)
			status_time.text = "…"
			status_text.text = "On his way!"
			status_sub.text = ""
		elif next < INF:
			status_ring.frac = next / lead
			status_ring.color = Color(0.56, 0.85, 1.0)
			status_time.text = str(int(ceil(next))) if next > 0.0 else "…"
			status_text.text = "Squawk arrives in"
			status_sub.text = ("second" if int(ceil(next)) == 1 else "seconds") if next > 0.0 else "a moment"   # --- R5 EN-UI: plural
		else:
			status_ring.frac = 0.0
			status_ring.color = Color(0.5, 0.45, 0.6)
			status_time.text = "–"
			status_text.text = "No orders" if main.is_open_phase() else "Open the shop"
			status_sub.text = ""
	status_ring.queue_redraw()
	# plumas
	var p := Game.plumas()
	for i in 5:
		var tr: TextureRect = plumas_row.get_child(i)
		var v := p - float(i)
		var kind := "full" if v >= 0.75 else ("half" if v >= 0.25 else "empty")
		tr.texture = load("res://assets/ui/pluma_%s.png" % kind)
	plumas_num.text = "%.1f" % p   # --- R5 EN-UI: «4.0» (punto decimal)
	# el estante: brilla y la flecha baila si Graznido espera
	tray_glow.color.a = (0.18 + 0.12 * sin(_t * 5.0)) if waiting else 0.0
	tray_arrow.visible = waiting and not Game.potions.is_empty()
	tray_arrow.position.y = -74.0 + sin(_t * 6.0) * 6.0
	for i in tray_btns.size():
		var b: Button = tray_btns[i]
		if b.has_node("Icon"):
			b.modulate = Color.WHITE if waiting else Color(0.8, 0.78, 0.86)
	var show_sel := not Game.potions.is_empty() and _sel < tray_btns.size() and not PadCursor.active
	sel_frame.visible = show_sel
	if show_sel:
		var sb: Button = tray_btns[_sel]
		sel_frame.position = sb.position - Vector2(4, 4)
		sel_frame.size = sb.size + Vector2(8, 8)

## La medalla del HUD: visible con la mejora, de mañana o con la tienda abierta (no en el mercado ni con otra pantalla).
func _refresh_badge() -> void:
	if badge == null:
		return
	var show: bool = Game.krapido_on() and (main.is_open_phase() or main.is_morning_phase()) \
		and not main.in_market and not _open and ui.hud_panel.visible and not ov.is_open()   # --- R4 MERGE: también con el banco abierto (el minuto del cuervo sigue corriendo)
	badge.visible = show
	if not show:
		return
	var n: int = k.orders.size()
	badge_tag.visible = n > 0
	badge_count.text = str(n)
	var ic: TextureRect = badge.get_node("Icon")
	if k.raven_waiting():
		var f: float = k.raven_left / Krapido.RAVEN_WAIT
		badge_ring.visible = true
		badge_ring.frac = f
		badge_ring.color = _wait_color(f)
		ic.scale = Vector2.ONE * (1.0 + 0.06 * sin(_t * 9.0))
	elif k.unseen > 0:
		badge_ring.visible = true
		badge_ring.frac = 1.0
		badge_ring.color = Color(0.75, 0.62, 1.0, 0.5 + 0.5 * sin(_t * 4.0))
		ic.scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * 4.0))
	else:
		badge_ring.visible = false
		ic.scale = Vector2.ONE
	ic.pivot_offset = ic.size / 2.0
	badge_ring.queue_redraw()

# ------------------------------------------------------------------ teclado

func _unhandled_input(ev: InputEvent) -> void:
	if not _open or ov.is_open():
		return
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var kc: int = ev.keycode
	# --- R4 SHIP: Esc / E cierran la bola también con el diálogo de un cliente encima (antes la bola lo ignoraba y Esc
	# abría los ajustes: el reloj se paraba con la bola y el diálogo debajo)
	if kc == KEY_ESCAPE or kc == KEY_E:
		close()
		get_viewport().set_input_as_handled()
		return
	if ui.dialog_open():
		return
	if kc == KEY_LEFT or kc == KEY_A:
		_sel = maxi(0, _sel - 1)
		Sfx.play("hover", 0.05, -12.0)
	elif kc == KEY_RIGHT or kc == KEY_D:
		_sel = mini(maxi(0, Game.potions.size() - 1), _sel + 1)
		Sfx.play("hover", 0.05, -12.0)
	elif kc == KEY_ENTER or kc == KEY_SPACE or kc == KEY_KP_ENTER:
		if _sel < Game.potions.size():
			_give(_sel)
	elif kc >= KEY_1 and kc <= KEY_5:
		var list: Array = k.orders.duplicate()
		list.sort_custom(func(a, b): return float(a["pickup"]) < float(b["pickup"]))
		var i := kc - KEY_1
		if i < list.size():
			_toggle_focus(int(list[i]["id"]))
	else:
		return
	get_viewport().set_input_as_handled()

# ================================================================== dibujo

## Un reloj redondo: un aro que se vacía (frac 1 = lleno), sobre un disco oscuro.
class _Ring extends Control:
	var frac := 1.0
	var color := Color(0.56, 0.85, 1.0)
	var radius := 24.0
	var width := 6.0

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, radius + width * 0.5 + 2.0, Color(0.05, 0.03, 0.1, 0.9))
		draw_arc(c, radius, 0.0, TAU, 48, Color(0.22, 0.18, 0.32, 1.0), width, false)
		if frac > 0.001:
			draw_arc(c, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 48, color, width, false)

## La niebla de la bola: motas de luz (cuadraditos de un píxel de arte) que giran despacio dentro del cristal.
class _Mist extends Control:
	var center := Vector2.ZERO
	var radius := 300.0
	var t := 0.0
	var _motes: Array = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in 70:
			_motes.append([rng.randf_range(0.12, 0.95), rng.randf() * TAU, rng.randf_range(0.08, 0.32) * (1 if rng.randf() < 0.7 else -1),
				rng.randf(), rng.randi_range(0, 2)])

	func _draw() -> void:
		var cols := [Color(0.78, 0.66, 1.0), Color(0.56, 0.86, 1.0), Color(1.0, 0.95, 0.85)]
		for m in _motes:
			var r: float = m[0] * radius
			var a: float = m[1] + t * m[2]
			var p := center + Vector2(cos(a), sin(a) * 0.92) * r
			p = (p / 4.0).floor() * 4.0
			var al: float = 0.25 + 0.35 * (0.5 + 0.5 * sin(t * 2.0 + m[3] * 9.0))
			var c: Color = cols[m[4]]
			c.a = al
			draw_rect(Rect2(p, Vector2(4, 4)), c)


# --- R4 MERGE: con la bola abierta, el ticket del mostrador se esconde (la bola ocupa el centro). Bajo la placa del HUD
# queda una etiqueta pequeña con la cara de quien espera en el mostrador y su paciencia (la barra del ticket de PACE):
# las dos prisas a la vista a la vez (el minuto de Graznido en la bola y la paciencia del cliente aquí).
var counter_chip: PanelContainer
var _chip_face: TextureRect
var _chip_glass: TextureRect
var _chip_bar: ProgressBar
var _chip_fill: StyleBoxFlat

func _build_counter_chip() -> void:
	counter_chip = PaperKit.panel("card", Vector2(14, 6))
	counter_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(counter_chip, Vector2(0, 0), Vector2(22, 226), Vector2(212, 0))
	counter_chip.tooltip_text = "Counter"
	var h := UIKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter_chip.add_child(h)
	_chip_face = TextureRect.new()
	_chip_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chip_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chip_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chip_face.custom_minimum_size = Vector2(48, 48)
	_chip_face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_chip_face)
	_chip_glass = PaperKit.pic("paper_i_hourglass", 2.0)
	_chip_glass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_glass.pivot_offset = _chip_glass.custom_minimum_size / 2.0
	_chip_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_chip_glass)
	_chip_bar = ProgressBar.new()
	_chip_bar.custom_minimum_size = Vector2(92, 12)
	_chip_bar.max_value = 1.0
	_chip_bar.step = 0.0
	_chip_bar.show_percentage = false
	_chip_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.37, 0.28, 0.2, 0.16)
	bg.border_color = Color(0.23, 0.15, 0.09, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	_chip_fill = StyleBoxFlat.new()
	_chip_fill.bg_color = PaperKit.HERB
	_chip_fill.set_corner_radius_all(3)
	_chip_bar.add_theme_stylebox_override("background", bg)
	_chip_bar.add_theme_stylebox_override("fill", _chip_fill)
	h.add_child(_chip_bar)
	counter_chip.visible = false
	ui.root.add_child(counter_chip)

func _refresh_counter_chip() -> void:
	if counter_chip == null:
		return
	var row = ui.get("order_patience_row")
	var show: bool = _open and row is Control and (row as Control).visible and main.customer_ready and not main.current.is_empty()
	counter_chip.visible = show
	if not show:
		return
	_chip_face.texture = head_of(String(main.current.get("who", "")))
	var p := float(ui.get("_order_p"))
	_chip_bar.value = p
	_chip_fill.bg_color = PaperKit.RED_INK if p < 0.25 else (Color("c27a2c") if p < 0.5 else PaperKit.HERB)
	if p < 0.25:
		_chip_glass.modulate = Color(1.0, 0.6 + 0.4 * sin(_t * 10.0), 0.6 + 0.4 * sin(_t * 10.0))
		_chip_glass.rotation = sin(_t * 18.0) * 0.12
	else:
		_chip_glass.modulate = Color.WHITE
		_chip_glass.rotation = 0.0
# --- end R4 MERGE
