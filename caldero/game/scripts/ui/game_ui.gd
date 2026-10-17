extends CanvasLayer
class_name GameUI
## HUD, diálogo, caldero, pociones, consejos y avisos. Los paneles grandes viven en Overlays.

signal brew_pressed
signal empty_pressed
signal slot_pressed(index: int)
signal potion_pressed(index: int)
signal choice_made(id: String)
signal dialog_advanced
signal menu_pressed(id: String)

var root: Control
var gold_label: Label
var day_label: Label
var time_label: Label
var level_label: Label
var level_bar: ProgressBar
var gold_icon: TextureRect
var hud_panel: PanelContainer
var menu_box: HBoxContainer

var dialog: PanelContainer
var dialog_name: Label
var dialog_text: RichTextLabel
var dialog_choices: HBoxContainer
var dialog_more: Label
var _typing := false
var _type_speed := 55.0
var _type_pos := 0.0
var _waiting_click := false

var order_card: PanelContainer
var order_name: Label
var order_text: RichTextLabel
var order_hint: RichTextLabel

var cauldron_panel: PanelContainer
var slot_boxes: Array = []
var essence_bars := {}
var essence_vals := {}
var result_label: RichTextLabel
var brew_btn: Button
var empty_btn: Button

var potion_panel: PanelContainer
var potion_title: Label
var potion_grid: GridContainer

var tooltip: PanelContainer
var tooltip_box: VBoxContainer
var toast_box: VBoxContainer
var tip_panel: PanelContainer
var tip_text: RichTextLabel
var banner: Label

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_build_hud()
	_build_menu()
	_build_order_card()
	_build_dialog()
	_build_cauldron_panel()
	_build_potion_panel()
	_build_tip()
	_build_tooltip()
	_build_toasts()
	_build_banner()
	Game.gold_changed.connect(func(_v): refresh_hud())
	Game.renombre_changed.connect(func(_a, _b): refresh_hud())
	Game.potions_changed.connect(refresh_potions)
	Game.upgrades_changed.connect(func(): refresh_potions(); set_cauldron([]))
	refresh_hud()
	refresh_potions()
	set_cauldron([])
	hide_dialog()
	hide_order()

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud_panel = UIKit.fancy_panel(UIKit.BG, 16)
	UIKit.place(hud_panel, Vector2(0, 0), Vector2(22, 18), Vector2(250, 0))
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_panel)
	var v := UIKit.vbox(6)
	hud_panel.add_child(v)
	var top := UIKit.hbox(14)
	v.add_child(top)
	day_label = UIKit.shadow(UIKit.label("Día 1", 30, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	top.add_child(day_label)
	time_label = UIKit.label("Mañana", 22, UIKit.MUTED, UIKit.font_italic)
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(time_label)
	var g := UIKit.hbox(8)
	v.add_child(g)
	gold_icon = UIKit.icon("res://assets/icons/emote_coin.png", 2.0)
	g.add_child(gold_icon)
	gold_label = UIKit.shadow(UIKit.label("40", 28, Color(1.0, 0.86, 0.45), UIKit.font_bold))
	g.add_child(gold_label)
	g.add_child(UIKit.label("oro", 20, UIKit.MUTED))
	var r := UIKit.hbox(8)
	v.add_child(r)
	r.add_child(UIKit.icon("res://assets/icons/emote_gem.png", 2.0))
	var rv := UIKit.vbox(2)
	r.add_child(rv)
	level_label = UIKit.label("Aprendiz", 20, Color(0.85, 0.78, 1.0), UIKit.font_bold)
	rv.add_child(level_label)
	level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(190, 10)
	level_bar.max_value = 1.0
	level_bar.show_percentage = false
	level_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(level_bar)

func refresh_hud() -> void:
	day_label.text = "Día %d" % Game.day
	gold_label.text = str(Game.gold)
	level_label.text = Game.level_name()
	var tw := create_tween()
	tw.tween_property(level_bar, "value", Game.level_progress(), 0.4)

func set_time_label(t: String) -> void:
	time_label.text = t

func bump_gold() -> void:
	gold_label.pivot_offset = gold_label.size / 2.0
	var tw := create_tween()
	tw.tween_property(gold_label, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(gold_label, "scale", Vector2.ONE, 0.15)

func _build_menu() -> void:
	menu_box = UIKit.hbox(10)
	UIKit.place(menu_box, Vector2(1, 0), Vector2(-660, 22), Vector2(638, 56), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	menu_box.alignment = BoxContainer.ALIGNMENT_END
	menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_box)
	for m in [["book", "Recetas", "res://assets/icons/pot_sueno_profundo.png"], ["journal", "Diario", "res://assets/icons/emote_note.png"],
			["market", "Mercado", "res://assets/icons/emote_coin.png"], ["settings", "Ajustes", "res://assets/icons/emote_sparkle.png"]]:
		var b := UIKit.button(m[1], func(): menu_pressed.emit(m[0]), 22)
		b.custom_minimum_size = Vector2(0, 52)
		menu_box.add_child(b)

func set_menu_visible(on: bool) -> void:
	menu_box.visible = on
	hud_panel.visible = on

# ------------------------------------------------------------------ pedido

func _build_order_card() -> void:
	order_card = UIKit.fancy_panel(Color(0.09, 0.075, 0.14, 0.9), 16)
	order_card.custom_minimum_size = Vector2(620, 0)
	UIKit.place(order_card, Vector2(0.5, 0), Vector2(-310, 20), Vector2(620, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	order_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(order_card)
	var v := UIKit.vbox(4)
	order_card.add_child(v)
	var h := UIKit.hbox(8)
	v.add_child(h)
	h.add_child(UIKit.icon("res://assets/icons/emote_excl.png", 1.6))
	order_name = UIKit.label("Pedido", 22, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold)
	h.add_child(order_name)
	order_text = UIKit.rich(20)
	order_text.custom_minimum_size = Vector2(580, 0)
	v.add_child(order_text)
	order_hint = UIKit.rich(20)
	order_hint.custom_minimum_size = Vector2(580, 0)
	v.add_child(order_hint)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pad)

func show_order(name: String, text: String, hint: String) -> void:
	order_name.text = "Pedido de %s" % name
	order_text.text = "[color=#e9e1f2]%s[/color]" % text
	order_hint.text = "" if hint == "" else "[color=#ffd987][i]Pista: %s[/i][/color]" % hint
	order_hint.visible = hint != ""
	if not order_card.visible:
		order_card.visible = true
		UIKit.pop_in(order_card)
	order_card.reset_size()
	_resize_later(order_card)

func hide_order() -> void:
	order_card.visible = false

# ------------------------------------------------------------------ diálogo

func _build_dialog() -> void:
	dialog = UIKit.fancy_panel(Color(0.06, 0.05, 0.1, 0.94), 26)
	dialog.custom_minimum_size = Vector2(880, 220)
	UIKit.place(dialog, Vector2(0.5, 1), Vector2(-440, -246), Vector2(880, 220), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.gui_input.connect(_on_dialog_input)
	root.add_child(dialog)
	var v := UIKit.vbox(10)
	dialog.add_child(v)
	dialog_name = UIKit.shadow(UIKit.label("", 28, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	v.add_child(dialog_name)
	dialog_text = UIKit.rich(27)
	dialog_text.custom_minimum_size = Vector2(820, 90)
	dialog_text.fit_content = true
	v.add_child(dialog_text)
	var bottom := UIKit.hbox(12)
	v.add_child(bottom)
	dialog_more = UIKit.label("▼", 22, UIKit.GOLD)
	dialog_more.visible = false
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)
	dialog_choices = UIKit.hbox(12)
	bottom.add_child(dialog_choices)
	bottom.add_child(dialog_more)

## Muestra un texto con efecto de máquina de escribir. choices: [[id, texto], ...]
func say(who: String, text: String, choices: Array = []) -> void:
	var was_visible := dialog.visible
	dialog.visible = true
	dialog_name.text = who
	dialog_name.visible = who != ""
	dialog_text.text = text
	dialog_text.visible_characters = 0
	_type_pos = 0.0
	_typing = true
	_waiting_click = choices.is_empty()
	for c in dialog_choices.get_children():
		c.queue_free()
	for ch in choices:
		var b := UIKit.button(ch[1], func(): choice_made.emit(ch[0]), 23)
		b.visible = false
		dialog_choices.add_child(b)
	dialog_more.visible = false
	if not was_visible:
		UIKit.pop_in(dialog)
	_resize_later(dialog)

func hide_dialog() -> void:
	dialog.visible = false
	_typing = false
	_waiting_click = false

func dialog_open() -> bool:
	return dialog.visible

func _finish_typing() -> void:
	_typing = false
	dialog_text.visible_characters = -1
	for c in dialog_choices.get_children():
		c.visible = true
	dialog_more.visible = _waiting_click

func _on_dialog_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_advance()

func _unhandled_input(ev: InputEvent) -> void:
	if not dialog.visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER):
		_advance()
		get_viewport().set_input_as_handled()

func _advance() -> void:
	if _typing:
		_finish_typing()
	elif _waiting_click:
		_waiting_click = false
		dialog_more.visible = false
		dialog_advanced.emit()

func _process(delta: float) -> void:
	if _typing:
		_type_pos += delta * _type_speed
		var total := dialog_text.get_total_character_count()
		dialog_text.visible_characters = int(_type_pos)
		if int(_type_pos) >= total:
			_finish_typing()
	if dialog_more.visible:
		dialog_more.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
	if tooltip.visible:
		_place_tooltip()

# ------------------------------------------------------------------ caldero

func _build_cauldron_panel() -> void:
	cauldron_panel = UIKit.fancy_panel(UIKit.BG, 18)
	cauldron_panel.custom_minimum_size = Vector2(430, 0)
	UIKit.place(cauldron_panel, Vector2(0, 1), Vector2(22, -300), Vector2(430, 278), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	cauldron_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(cauldron_panel)
	var v := UIKit.vbox(8)
	cauldron_panel.add_child(v)
	var head := UIKit.hbox(8)
	v.add_child(head)
	head.add_child(UIKit.shadow(UIKit.label("Caldero", 26, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold)))
	var slots := UIKit.hbox(8)
	v.add_child(slots)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = ""
		var tr := TextureRect.new()
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 8
		tr.offset_top = 8
		tr.offset_right = -8
		tr.offset_bottom = -8
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.name = "Icon"
		b.add_child(tr)
		var idx := i
		b.pressed.connect(func(): slot_pressed.emit(idx))
		slots.add_child(b)
		slot_boxes.append(b)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	slots.add_child(spacer)
	var bars := UIKit.vbox(2)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_child(bars)
	for e in Data.ESSENCE_ORDER:
		var row := UIKit.hbox(6)
		bars.add_child(row)
		var dot := ColorRect.new()
		dot.color = Data.ESSENCES[e]["color"]
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var bg := ColorRect.new()
		bg.color = Color(1, 1, 1, 0.06)
		bg.custom_minimum_size = Vector2(110, 9)
		bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bg)
		var fg := ColorRect.new()
		fg.color = Data.ESSENCES[e]["color"]
		fg.size = Vector2(0, 9)
		fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fg)
		essence_bars[e] = fg
		var val := UIKit.label("0", 15, UIKit.MUTED, UIKit.font_bold)
		val.custom_minimum_size = Vector2(16, 0)
		row.add_child(val)
		essence_vals[e] = val
	result_label = UIKit.rich(21)
	result_label.custom_minimum_size = Vector2(380, 54)
	v.add_child(result_label)
	var btns := UIKit.hbox(10)
	v.add_child(btns)
	brew_btn = UIKit.button("Remover", func(): brew_pressed.emit(), 24)
	brew_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(brew_btn)
	empty_btn = UIKit.button("Vaciar", func(): empty_pressed.emit(), 20)
	btns.add_child(empty_btn)

func set_cauldron(contents: Array) -> void:
	var slots := Game.cauldron_slots()
	for i in 3:
		var b: Button = slot_boxes[i]
		b.visible = i < slots
		var tr: TextureRect = b.get_node("Icon")
		if i < contents.size():
			tr.texture = load("res://assets/icons/ing_%s.png" % contents[i])
			b.tooltip_text = "Sacar %s" % Data.INGREDIENTS[contents[i]]["name"]
			b.disabled = false
		else:
			tr.texture = null
			b.tooltip_text = ""
			b.disabled = true
	var m := Game.essence_mix(contents)
	var r := Game.evaluate(contents)
	var top: Array = r.get("top", [])
	for e in Data.ESSENCE_ORDER:
		var v: int = m.get(e, 0)
		var fg: ColorRect = essence_bars[e]
		var w := clampf(v / 8.0, 0.0, 1.0) * 110.0
		var tw := create_tween()
		tw.tween_property(fg, "size:x", w, 0.25)
		var lead: bool = top.size() >= 2 and (e == top[0] or e == top[1])
		fg.color = Data.ESSENCES[e]["color"] if lead or top.size() < 2 else Data.ESSENCES[e]["color"].darkened(0.45)
		essence_vals[e].text = str(v)
		essence_vals[e].add_theme_color_override("font_color", UIKit.TEXT if lead else UIKit.MUTED)
	if contents.is_empty():
		result_label.text = "[color=#a99fbf][i]Toca los frascos del estante para echar ingredientes.[/i][/color]"
	elif contents.size() < 2:
		result_label.text = "[color=#a99fbf][i]Añade al menos otro ingrediente.[/i][/color]"
	elif r.get("potion", "") == "":
		result_label.text = "[color=#ff9b9b]Solo hay una esencia: así no cuaja ninguna poción.[/color]"
	else:
		var pid: String = r["potion"]
		var pot := Game.potency_bonus() + int(r["potency"])
		var stars := Game.stars_for(pot)
		var name: String = Data.POTIONS[pid]["name"] if Game.discovered.has(pid) else "Poción desconocida"
		var e1: String = Data.ESSENCES[top[0]]["name"]
		var e2: String = Data.ESSENCES[top[1]]["name"]
		result_label.text = "[b][color=#ffd987]%s[/color][/b]\n[color=#a99fbf]%s + %s · potencia %d (%d %s)[/color]" % [name, e1, e2, pot, stars, "estrella" if stars == 1 else "estrellas"]
	brew_btn.disabled = r.get("potion", "") == ""
	empty_btn.disabled = contents.is_empty()

func set_cauldron_enabled(on: bool) -> void:
	cauldron_panel.modulate.a = 1.0 if on else 0.55

# ------------------------------------------------------------------ pociones

func _build_potion_panel() -> void:
	potion_panel = UIKit.fancy_panel(UIKit.BG, 18)
	potion_panel.custom_minimum_size = Vector2(456, 0)
	UIKit.place(potion_panel, Vector2(1, 1), Vector2(-478, -230), Vector2(456, 208), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	potion_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(potion_panel)
	var v := UIKit.vbox(6)
	potion_panel.add_child(v)
	var head := UIKit.hbox(10)
	v.add_child(head)
	potion_title = UIKit.shadow(UIKit.label("Pociones", 26, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	head.add_child(potion_title)
	potion_grid = GridContainer.new()
	potion_grid.columns = 6
	potion_grid.add_theme_constant_override("h_separation", 6)
	potion_grid.add_theme_constant_override("v_separation", 6)
	potion_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(potion_grid)

func refresh_potions() -> void:
	var cap := Game.potion_capacity()
	potion_title.text = "Pociones  %d/%d" % [Game.potions.size(), cap]
	for c in potion_grid.get_children():
		c.queue_free()
	potion_grid.columns = 6
	for i in cap:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 70 if cap > 6 else 140)
		b.focus_mode = Control.FOCUS_NONE
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i < Game.potions.size():
			var p: Dictionary = Game.potions[i]
			var v := UIKit.vbox(0)
			v.set_anchors_preset(Control.PRESET_FULL_RECT)
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			b.add_child(v)
			var ic := UIKit.icon("res://assets/icons/pot_%s.png" % p["id"], 3.0 if cap <= 6 else 2.4)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(ic)
			var st := UIKit.stars(Game.stars_for(p["potency"]), 0.9 if cap <= 6 else 0.7)
			st.alignment = BoxContainer.ALIGNMENT_CENTER
			v.add_child(st)
			var idx := i
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.pressed.connect(func(): potion_pressed.emit(idx))
			b.mouse_entered.connect(func(): show_potion_tooltip(idx))
			b.mouse_exited.connect(hide_tooltip)
		else:
			b.disabled = true
		potion_grid.add_child(b)

func potion_slot_center(index: int) -> Vector2:
	if index < potion_grid.get_child_count():
		var c: Control = potion_grid.get_child(index)
		return c.get_global_rect().get_center()
	return potion_panel.get_global_rect().get_center()

# ------------------------------------------------------------------ consejos, tooltip, avisos

func _build_tip() -> void:
	tip_panel = UIKit.fancy_panel(Color(0.12, 0.09, 0.05, 0.93), 18)
	tip_panel.custom_minimum_size = Vector2(450, 0)
	UIKit.place(tip_panel, Vector2(1, 0), Vector2(-472, 96), Vector2(450, 0), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tip_panel)
	var v := UIKit.vbox(4)
	tip_panel.add_child(v)
	var h := UIKit.hbox(8)
	v.add_child(h)
	h.add_child(UIKit.icon("res://assets/icons/emote_sparkle.png", 1.8))
	h.add_child(UIKit.label("Consejo", 22, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	tip_text = UIKit.rich(21)
	tip_text.custom_minimum_size = Vector2(394, 0)
	v.add_child(tip_text)
	tip_panel.visible = false

func show_tip(text: String) -> void:
	tip_text.text = text
	tip_panel.visible = true
	tip_panel.reset_size()
	_resize_later(tip_panel)
	UIKit.pop_in(tip_panel)

## Los RichTextLabel calculan su alto un cuadro después: reajusta el panel entonces.
func _resize_later(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c):
		c.reset_size()
	await get_tree().process_frame
	if is_instance_valid(c):
		c.reset_size()

func hide_tip() -> void:
	tip_panel.visible = false

func _build_tooltip() -> void:
	tooltip = UIKit.fancy_panel(Color(0.06, 0.05, 0.1, 0.96), 16)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.z_index = 50
	root.add_child(tooltip)
	tooltip_box = UIKit.vbox(6)
	tooltip.add_child(tooltip_box)
	tooltip.visible = false

func _clear_tooltip() -> void:
	for c in tooltip_box.get_children():
		tooltip_box.remove_child(c)
		c.queue_free()

func show_ingredient_tooltip(id: String) -> void:
	_clear_tooltip()
	var d: Dictionary = Data.INGREDIENTS[id]
	var h := UIKit.hbox(10)
	tooltip_box.add_child(h)
	h.add_child(UIKit.icon("res://assets/icons/ing_%s.png" % id, 2.5))
	var v := UIKit.vbox(2)
	h.add_child(v)
	v.add_child(UIKit.label(d["name"], 25, UIKit.GOLD_BRIGHT, UIKit.font_bold))
	var chips := UIKit.hbox(12)
	v.add_child(chips)
	for e in d["ess"]:
		chips.add_child(UIKit.essence_chip(e, d["ess"][e], 20))
	var desc := UIKit.rich(19)
	desc.custom_minimum_size = Vector2(380, 0)
	desc.text = "[i][color=#b8aecb]%s[/color][/i]" % d["desc"]
	tooltip_box.add_child(desc)
	var n: int = Game.stock.get(id, 0)
	tooltip_box.add_child(UIKit.label("En el estante: %d   ·   Precio: %d oro" % [n, d["price"]], 19, UIKit.TEXT if n > 0 else UIKit.BAD))
	tooltip.visible = true
	tooltip.reset_size()
	_place_tooltip()

func show_potion_tooltip(idx: int) -> void:
	if idx >= Game.potions.size():
		return
	_clear_tooltip()
	var p: Dictionary = Game.potions[idx]
	var d: Dictionary = Data.POTIONS[p["id"]]
	var h := UIKit.hbox(10)
	tooltip_box.add_child(h)
	h.add_child(UIKit.icon("res://assets/icons/pot_%s.png" % p["id"], 2.5))
	var v := UIKit.vbox(2)
	h.add_child(v)
	v.add_child(UIKit.label(d["name"], 25, UIKit.GOLD_BRIGHT, UIKit.font_bold))
	v.add_child(UIKit.stars(Game.stars_for(p["potency"]), 1.2))
	var desc := UIKit.rich(19)
	desc.custom_minimum_size = Vector2(360, 0)
	desc.text = "[i][color=#b8aecb]%s[/color][/i]\n[color=#a99fbf]Potencia %d · Toca para entregar.[/color]" % [d["effect"], p["potency"]]
	tooltip_box.add_child(desc)
	tooltip.visible = true
	tooltip.reset_size()
	_place_tooltip()

func hide_tooltip() -> void:
	tooltip.visible = false

func _place_tooltip() -> void:
	var mp := root.get_local_mouse_position()
	var s := tooltip.size
	var vp := root.size
	var p := mp + Vector2(24, 24)
	if p.x + s.x > vp.x - 10:
		p.x = mp.x - s.x - 20
	if p.y + s.y > vp.y - 10:
		p.y = mp.y - s.y - 20
	tooltip.position = p

func _build_toasts() -> void:
	toast_box = UIKit.vbox(8)
	UIKit.place(toast_box, Vector2(0.5, 0), Vector2(-400, 250), Vector2(800, 10), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

func toast(text: String, color := UIKit.TEXT, duration := 2.6) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.05, 0.1, 0.9), UIKit.GOLD, 1, 6, 14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label(text, 22, color, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
	while toast_box.get_child_count() > 3:
		toast_box.get_child(0).queue_free()
		break

func _build_banner() -> void:
	banner = UIKit.shadow(UIKit.label("", 54, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER), 3)
	UIKit.place(banner, Vector2(0.5, 0.5), Vector2(-700, -300), Vector2(1400, 140), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	banner.modulate.a = 0.0
	root.add_child(banner)

func show_banner(text: String, sub := "") -> void:
	banner.text = text if sub == "" else text + "\n" + sub
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.9, 0.9)
	banner.pivot_offset = banner.size / 2.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.6)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.6)

## Monedas que vuelan desde un punto de la pantalla hasta el contador de oro.
func fly_coins(from: Vector2, count: int) -> void:
	var target := gold_icon.get_global_rect().get_center()
	var tex: Texture2D = load("res://assets/icons/emote_coin.png")
	for i in count:
		var c := TextureRect.new()
		c.texture = tex
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.size = Vector2(32, 32)
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = from + Vector2(randf_range(-40, 40), randf_range(-30, 10))
		c.z_index = 40
		root.add_child(c)
		var mid := c.position + Vector2(randf_range(-80, 80), -randf_range(60, 140))
		var tw := c.create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(c, "position", mid, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position", target - Vector2(16, 16), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			Sfx.play("coin", 0.1, -10.0)
			bump_gold()
			c.queue_free())

func set_gameplay_visible(on: bool) -> void:
	cauldron_panel.visible = on
	potion_panel.visible = on
	set_menu_visible(on)
	if not on:
		hide_order()
		hide_tip()
		hide_tooltip()
