extends CanvasLayer
class_name GameUI
## HUD, diálogo, ticket del pedido, estante de pociones, consejos y avisos. Los paneles grandes viven en Overlays y
## el banco del caldero en BrewUI (scripts/ui/brew_ui.gd, capa 4, debajo de esta).
# --- R3 BENCH: esta ronda rehízo casi todo el HUD (menos texto, menos paneles):
#   - estado arriba a la izquierda: «Día n» + icono de la hora, monedas y la barra de renombre (sin palabras).
#   - menú arriba a la derecha: 4 botones de icono (Recetas, Diario, Mercado, Ajustes) con su palabra al pasar.
#   - el pedido: un ticket de papel clavado arriba (retrato, el pedido, la pista con iconos de esencia y las runas).
#   - el estante de pociones: un estantito de madera abajo a la derecha (6 o 12 frascos, con la runa si la tiene).
#   - el panel «Caldero» ya no existe (es el banco: BrewUI). set_cauldron() queda como aviso (señal cauldron_set).
#   - consejos de una línea (una nota clavada) que se van solos; avisos y tooltips cortos.
#   - sin pestaña de pergaminos: magic_setup / show_rack_tab / scroll_slot_center quedan como funciones vacías.

signal potion_pressed(index: int)
signal choice_made(id: String)
signal dialog_advanced
signal menu_pressed(id: String)
signal cauldron_set(contents: Array)   # --- R3 BENCH: el contenido del caldero cambió (el banco se redibuja)

const INK_COL := Color("3a2618")       # --- R3 BENCH: tinta sobre papel
const PAPER_MARGIN := 21               # --- R3 BENCH: márgenes de ticket_paper.png (7 px de arte a 3x)

var root: Control
var gold_label: Label
var day_label: Label
var time_icon: TextureRect             # --- R3 BENCH: la hora del día como icono
var time_label: Label                  # --- R3 BENCH: se conserva (oculto) por compatibilidad
var level_label: Label                 # --- R3 BENCH: se conserva (oculto): el nombre va en el tooltip
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

# --- R3 BENCH: el ticket del pedido
var order_card: Control
var order_paper: PanelContainer
var order_frame: TextureRect
var order_portrait: TextureRect
var order_name: Label
var order_text: RichTextLabel
var order_hint: HBoxContainer
var order_mods: HBoxContainer
var order_who := ""                    # id del cliente (main.gd lo pone; si no, se busca por el nombre)
var _portrait_top := {}                # sprite -> primera fila con píxeles (para recortar la cabeza)
var _order_mod_ids: Array = []         # --- R3 MERGE: las runas que se ven en el ticket (MAGIC3 las lee en su prueba)
var market_x2: Control                 # --- R3 MERGE: sello «x2» del botón Mercado durante el día (UI-PAPER: encargo al doble)

# --- R3 BENCH: el estante de pociones
var potion_panel: Control
var potion_art: TextureRect
var potion_count: Label
var potion_slots: Array = []           # Button por hueco (solo los que tienen poción son tocables)
var potion_grid: Control               # compatibilidad: el contenedor de los huecos
var _held_slot := -1                   # hueco escondido mientras su frasco vuela hacia él
var _bench_mode := false

var tooltip: PanelContainer
var tooltip_box: VBoxContainer
var toast_box: VBoxContainer
var prompts: PromptUI                  # --- R6 UI: los avisos de acción (scripts/ui/prompt_ui.gd)
var tip_panel: PanelContainer
var tip_text: RichTextLabel
var _tip_gen := 0
var banner: Label

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	# --- R6 UI: los avisos de acción van debajo de todo lo demás del HUD (ticket, estante, diálogo, avisos)
	prompts = PromptUI.new()
	root.add_child(prompts)
	# --- end R6 UI
	_build_hud()
	_build_menu()
	_build_order_card()
	_build_dialog()
	_build_potion_panel()
	_build_tip()
	_build_tooltip()
	_build_toasts()
	_build_banner()
	Game.gold_changed.connect(func(_v): refresh_hud())
	Game.renombre_changed.connect(func(_a, _b): refresh_hud())
	Game.potions_changed.connect(refresh_potions)
	Game.upgrades_changed.connect(func(): refresh_potions())
	refresh_hud()
	refresh_potions()
	hide_dialog()
	hide_order()

# ------------------------------------------------------------------ HUD (estado)

# --- R3 BENCH: «Día 3 ☀» / monedas / barra de renombre. Sin «oro», sin la hora ni el título en palabras.
# --- R5 EN-UI: las palabras en inglés (main.gd llama a set_time_label con ellas; los ids de los iconos no cambian)
const TOD_ICONS := {"Morning": "manana", "Midday": "mediodia", "Afternoon": "tarde", "Dusk": "atardecer", "Night": "noche"}

func _build_hud() -> void:
	hud_panel = UIKit.fancy_panel(UIKit.BG, 14)
	UIKit.place(hud_panel, Vector2(0, 0), Vector2(24, 20), Vector2(212, 0))   # --- R6 UI: los mismos márgenes que la barra de la derecha (24, 20)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(hud_panel)
	var v := UIKit.vbox(4)
	hud_panel.add_child(v)
	var top := UIKit.hbox(10)
	v.add_child(top)
	day_label = UIKit.shadow(UIKit.label("Day 1", 30, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	top.add_child(day_label)
	time_icon = UIKit.icon("res://assets/ui/tod_manana.png", 3.0)
	time_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(time_icon)
	time_label = UIKit.label("Morning", 20, UIKit.MUTED, UIKit.font_italic)
	time_label.visible = false
	top.add_child(time_label)
	var g := UIKit.hbox(8)
	v.add_child(g)
	gold_icon = UIKit.icon("res://assets/icons/emote_coin.png", 2.0)
	g.add_child(gold_icon)
	gold_label = UIKit.shadow(UIKit.label("40", 28, Color(1.0, 0.86, 0.45), UIKit.font_bold))
	g.add_child(gold_label)
	var r := UIKit.hbox(8)
	v.add_child(r)
	r.add_child(UIKit.icon("res://assets/icons/emote_gem.png", 1.6))
	level_label = UIKit.label("Apprentice", 18, Color(0.85, 0.78, 1.0), UIKit.font_bold)
	level_label.visible = false
	r.add_child(level_label)
	level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(140, 10)
	level_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_bar.max_value = 1.0
	level_bar.show_percentage = false
	level_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(level_bar)
	_pace_build_clock(v)   # --- R4 PACE: el reloj del día y la fila, bajo «Día n»

func refresh_hud() -> void:
	day_label.text = "Day %d" % Game.day
	gold_label.text = UIKit.num(Game.gold)   # --- R5 EN-UI: «1,241»
	level_label.text = Game.level_name()
	hud_panel.tooltip_text = "%s · %s" % [Game.level_name(), time_label.text]
	var tw := create_tween()
	tw.tween_property(level_bar, "value", Game.level_progress(), 0.4)

func set_time_label(t: String) -> void:
	time_label.text = t
	var p := "res://assets/ui/tod_%s.png" % TOD_ICONS.get(t, "mediodia")
	if ResourceLoader.exists(p):
		time_icon.texture = load(p)
	hud_panel.tooltip_text = "%s · %s" % [Game.level_name(), t]

func bump_gold() -> void:
	gold_label.pivot_offset = gold_label.size / 2.0
	var tw := create_tween()
	tw.tween_property(gold_label, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(gold_label, "scale", Vector2.ONE, 0.15)

# --- R3 BENCH: el menú, 4 botones de icono
# --- R6 UI: una barra ordenada de 5 cuadrados iguales (HudButton "icon": pergamino en un marco de nogal, 66x66 con 8 de
# separación), alineada con la placa del HUD a 24 px del borde; al pasar el cursor (o el del mando), el tooltip dice su
# nombre, su tecla y su botón del mando (Recipes R / Y, Journal J / View, Market M, Rankings G, Settings Esc / Menu).
const MENU_ITEMS := [["book", "Recipes", "hud_book", "recipes"], ["journal", "Journal", "hud_journal", "journal"],
	["market", "Market", "hud_market", "market"], ["rank", "Rankings", "hud_rank", "rankings"], ["settings", "Settings", "hud_settings", "settings"]]
const HUD_EDGE := 24.0      # margen de la placa, la barra y el estante a los bordes de la pantalla
const HUD_TOP := 20.0
func _build_menu() -> void:
	menu_box = UIKit.hbox(8)
	var w := 66.0 * MENU_ITEMS.size() + 8.0 * (MENU_ITEMS.size() - 1)
	UIKit.place(menu_box, Vector2(1, 0), Vector2(-w - HUD_EDGE, HUD_TOP), Vector2(w, 66), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	menu_box.alignment = BoxContainer.ALIGNMENT_END
	menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_box)
	for m in MENU_ITEMS:   # --- R4 RANK: el Escalafón del Gremio
		var b := HudButton.make("icon", "", m[2], "", func(): menu_pressed.emit(m[0]))
		b.set_tip(m[1], [m[3]])
		b.set_meta("menu", m[0])
		menu_box.add_child(b)
		if m[0] == "rank":
			rank_btn = b   # --- R4 RANK
		# --- R3 MERGE: de día el mercado es el encargo de Pip y cuesta el doble: un sellito rojo «x2» en la esquina
		if m[0] == "market":
			PaperKit.load_fonts()
			var tag := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("9e2b25")            # lacre (guía de estilo)
			sb.border_color = Color("f4e4bd")
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(6)
			sb.content_margin_left = 5
			sb.content_margin_right = 5
			sb.content_margin_top = -2
			sb.content_margin_bottom = -1
			tag.add_theme_stylebox_override("panel", sb)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var l := UIKit.label("x2", 24, Color("f4e4bd"), PaperKit.font_hand_bold, HORIZONTAL_ALIGNMENT_CENTER)
			tag.add_child(l)
			tag.position = Vector2(34, -10)
			tag.rotation = 0.14
			tag.visible = false
			b.add_child(tag)
			market_x2 = tag
		# --- end R3 MERGE

## --- R4 RANK: el botón del Escalafón brilla un momento (la primera línea del Escalafón en el correo).
var rank_btn: Button
func pulse_rank_button() -> void:
	if not is_instance_valid(rank_btn):
		return
	var tw := rank_btn.create_tween()
	for i in 4:
		tw.tween_property(rank_btn, "modulate", Color(1.7, 1.45, 0.8), 0.28)
		tw.tween_property(rank_btn, "modulate", Color.WHITE, 0.34)
# --- end R4 RANK

## --- R3 MERGE: muestra el «x2» del botón Mercado (main.gd: true con la tienda abierta, false por la mañana).
func set_day_market(on: bool) -> void:
	if market_x2:
		market_x2.visible = on

func set_menu_visible(on: bool) -> void:
	menu_box.visible = on and not _bench_mode
	hud_panel.visible = on

## --- R3 BENCH: con el banco del caldero abierto el menú se esconde (Y / R y Vista / J siguen abriendo recetas y diario).
func set_bench_mode(on: bool) -> void:
	_bench_mode = on
	menu_box.visible = hud_panel.visible and not on
	if on:
		hide_tooltip()

# ------------------------------------------------------------------ el ticket del pedido

# --- R3 BENCH: un papelito clavado arriba: retrato, el pedido (una o dos líneas), la pista (iconos de esencia si
# la pista las nombra; si no, la frase corta) y las runas que pide (res://assets/icons/rune_<id>.png).
func _build_order_card() -> void:
	order_card = Control.new()
	UIKit.place(order_card, Vector2(0.5, 0), Vector2(-300, 6), Vector2(600, 10), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	order_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(order_card)
	order_paper = PanelContainer.new()
	order_paper.add_theme_stylebox_override("panel", UIKit.paper_style(14))
	order_paper.custom_minimum_size = Vector2(600, 0)
	order_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_card.add_child(order_paper)
	var h := UIKit.hbox(16)
	order_paper.add_child(h)
	order_frame = TextureRect.new()
	order_frame.texture = load("res://assets/ui/ticket_frame.png")
	order_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	order_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	order_frame.stretch_mode = TextureRect.STRETCH_SCALE
	order_frame.custom_minimum_size = Vector2(88, 88)
	order_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	order_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(order_frame)
	order_portrait = TextureRect.new()
	order_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	order_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	order_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	order_portrait.position = Vector2(8, 8)
	order_portrait.size = Vector2(72, 72)
	order_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_frame.add_child(order_portrait)
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	order_name = UIKit.label("", 23, Color("7a1d18"), UIKit.font_sc_bold)
	v.add_child(order_name)
	# --- R3 MERGE: el pedido va escrito a mano, con la letra de los papeles (UI-PAPER: PaperKit, Caveat)
	order_text = PaperKit.rich(26, INK_COL)
	order_text.custom_minimum_size = Vector2(440, 0)
	v.add_child(order_text)
	var bottom := UIKit.hbox(18)
	v.add_child(bottom)
	order_hint = UIKit.hbox(6)
	bottom.add_child(order_hint)
	order_mods = UIKit.hbox(6)
	bottom.add_child(order_mods)
	_pace_ticket_row(v)   # --- R4 PACE: la paciencia de quien espera (reloj de arena + barra)
	var pin := TextureRect.new()
	pin.texture = load("res://assets/ui/ticket_pin.png")
	pin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pin.stretch_mode = TextureRect.STRETCH_SCALE
	pin.size = Vector2(27, 27)
	pin.position = Vector2(300 - 12, -4)
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_card.add_child(pin)

## El ticket del pedido. name: el nombre que se ve; text: lo que pide; hint: la pista ("" si aún no la pidió);
## mods: runas que lleva el pedido (ids; el icono es res://assets/icons/rune_<id>.png, si no existe no se dibuja).
func show_order(name: String, text: String, hint: String, mods: Array = []) -> void:
	order_name.text = name
	order_text.text = text
	_fill_hint(hint)
	for c in order_mods.get_children():
		c.queue_free()
	var runes := 0
	_order_mod_ids = []   # --- R3 MERGE
	for m in mods:
		var p := "res://assets/icons/rune_%s.png" % str(m)
		if ResourceLoader.exists(p):
			var ic := UIKit.icon(p, 2.0)
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			ic.tooltip_text = _rune_name(str(m))
			order_mods.add_child(ic)
			runes += 1
			_order_mod_ids.append(str(m))   # --- R3 MERGE
	order_mods.visible = runes > 0
	_set_portrait(order_who if order_who != "" else _who_by_name(name))
	order_who = ""
	if not order_card.visible:
		order_card.visible = true
		order_card.pivot_offset = Vector2(300, 0)
		order_card.rotation = -0.05
		order_card.position.y = -40.0
		order_card.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(order_card, "position:y", 6.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(order_card, "rotation", 0.012, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(order_card, "modulate:a", 1.0, 0.15)
		Sfx.play("page", 0.08, -8.0)
	order_paper.reset_size()
	_resize_later(order_paper)

func hide_order() -> void:
	order_card.visible = false

## --- R3 MERGE: las runas (ids) que muestra el ticket ahora mismo (MAGIC3: --demo=magictest lo imprime).
func order_mods_ids() -> Array:
	return _order_mod_ids.duplicate() if order_card.visible else []

## La pista: si nombra dos esencias, sus iconos (Vida + Sombra); si no, la frase, corta y en cursiva.
func _fill_hint(hint: String) -> void:
	for c in order_hint.get_children():
		c.queue_free()
	order_hint.visible = hint != ""
	if hint == "":
		return
	order_hint.add_child(UIKit.icon("res://assets/icons/emote_sparkle.png", 1.6))
	var es := hint_essences(hint)
	if es.size() == 2:
		order_hint.add_child(UIKit.ess_icon(es[0], 3.0))
		var plus := UIKit.label("+", 24, INK_COL, UIKit.font_bold)
		order_hint.add_child(plus)
		order_hint.add_child(UIKit.ess_icon(es[1], 3.0))
		order_hint.tooltip_text = hint
	else:
		var l := PaperKit.hand(hint, 24, Color("6e4e2e"), false, HORIZONTAL_ALIGNMENT_LEFT, 380.0)   # --- R3 MERGE: a mano
		order_hint.add_child(l)

## Las esencias que nombra una pista ("Life and shadow, for sleep." -> ["vida", "sombra"]).
## --- R5 EN-UI: busca el NOMBRE de cada esencia (Data.ESSENCES[e]["name"]: fire, frost, life, shadow, light) como
## palabra suelta, no su id castellano (contrato C1 con EN-DATA: las pistas usan esas palabras exactas).
static func hint_essences(hint: String) -> Array:
	var low := hint.to_lower()
	var out := []
	for e in Data.ESSENCE_ORDER:
		var word := String(Data.ESSENCES.get(e, {}).get("name", e)).to_lower()
		var re := RegEx.create_from_string("(^|[^a-z])%s($|[^a-z])" % word)
		if re.search(low):
			out.append(e)
	return out

func _rune_name(id: String) -> String:
	var runes = Data.get("RUNES")
	if runes is Dictionary and runes.has(id) and runes[id] is Dictionary:
		return String(runes[id].get("name", id))
	return id.capitalize()

func _who_by_name(name: String) -> String:
	for id in Data.CHARACTERS:
		if String(Data.CHARACTERS[id].get("name", "")) == name:
			return id
	return ""

## Retrato: la cabeza del primer cuadro de su sprite (64x96), recortada desde la primera fila con píxeles.
func _set_portrait(who: String) -> void:
	order_frame.visible = who != ""
	if who == "":
		return
	var sid := Story.sprite_id(who)
	var path := "res://assets/chars/%s_idle.png" % sid
	if not ResourceLoader.exists(path):
		order_frame.visible = false
		return
	var tex: Texture2D = load(path)
	var fw := tex.get_width() / 2
	if not _portrait_top.has(sid):
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
		_portrait_top[sid] = top
	var at := AtlasTexture.new()
	at.atlas = tex
	var y0: int = maxi(0, int(_portrait_top[sid]) - 2)
	at.region = Rect2((fw - 36) / 2, y0, 36, 36)
	order_portrait.texture = at

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
		dialog_choices.remove_child(c)   # --- R6 UI: fuera ya (el bot y las teclas 1-3 leen los hijos en este cuadro)
		c.queue_free()
	# --- R6 UI: las respuestas son botones del HUD (la primera, la principal) con su tecla: 1, 2, 3 (E, Espacio o Intro
	# también eligen la primera); con el mando, A sobre la que tiene el cursor o, sin cursor encima de ninguna, la primera
	var n := 0
	for ch in choices:
		n += 1
		var b := HudButton.make("primary" if n == 1 else "secondary", ch[1], "", "choice%d" % n, func(): choice_made.emit(ch[0]), 24)
		b.set_tall()   # (resume 3) la misma altura que todos los botones del HUD (en la baja la tecla llenaba la cara)
		b.set_meta("choice", ch[0])   # --- R5 EN-UI: el id de la elección (el bot lo lee: no compara el texto del botón)
		b.visible = false
		dialog_choices.add_child(b)
	# --- end R6 UI
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

## Hay un diálogo escribiéndose o esperando un clic (el botón A del mando lo avanza).
func dialog_waiting() -> bool:
	return dialog.visible and (_typing or _waiting_click)

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
	# --- R6 UI: con las respuestas a la vista, 1 / 2 / 3 eligen una y E, Espacio o Intro la primera; mientras se escribe,
	# E, Espacio e Intro terminan la frase (como antes Espacio e Intro)
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.keycode
		if k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			if not _typing and choices_ready():
				press_choice(0)
			else:
				_advance()
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k <= KEY_3 and not _typing and choices_ready():
			if press_choice(k - KEY_1):
				get_viewport().set_input_as_handled()
	# --- end R6 UI

## --- R6 UI: las respuestas del diálogo ya están a la vista (terminó de escribirse).
func choices_ready() -> bool:
	return dialog.visible and not _typing and dialog_choices.get_child_count() > 0 and dialog_choices.get_child(0).visible

## Pulsa la respuesta i (0 = la primera). true si había.
func press_choice(i: int) -> bool:
	if i < 0 or i >= dialog_choices.get_child_count():
		return false
	var b := dialog_choices.get_child(i) as BaseButton
	if b == null or b.disabled or not b.visible:
		return false
	b.pressed.emit()
	return true
# --- end R6 UI

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
	_pace_process_ui(delta)   # --- R4 PACE: el reloj late en la última hora; la barra, cuando se acaba la paciencia
	_pick_process()   # --- R6 UI: el estante para elegir se cierra solo si ya no tiene sentido

# ------------------------------------------------------------------ caldero (compatibilidad)

## --- R3 BENCH: el panel «Caldero» ya no existe (el banco del caldero lo dibuja todo). Se sigue llamando desde
## main.gd cuando cambia lo que hay en el caldero: avisa al banco.
func set_cauldron(contents: Array) -> void:
	cauldron_set.emit(contents)

# ------------------------------------------------------------------ el estante de pociones

# --- R3 BENCH: un estantito de madera (assets/ui/hud_shelf6.png o hud_shelf12.png, a 3x) con los frascos de pie;
# las estrellas en el canto de la repisa, el número (3/6) en la plaquita de latón y, si la poción lleva una runa
# ("rune"), su glifo pequeño junto al frasco.
const SHELF_K := 3.0
const SHELF_SLOT_X := [15, 35, 55, 75, 95, 115]

func _build_potion_panel() -> void:
	potion_panel = Control.new()
	potion_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(potion_panel)
	potion_art = TextureRect.new()
	potion_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	potion_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	potion_art.stretch_mode = TextureRect.STRETCH_SCALE
	potion_art.mouse_filter = Control.MOUSE_FILTER_STOP   # tapa el escenario 3D detrás del estante
	potion_panel.add_child(potion_art)
	potion_grid = Control.new()
	potion_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	potion_panel.add_child(potion_grid)
	potion_count = UIKit.label("0/6", 19, INK_COL, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	potion_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	potion_panel.add_child(potion_count)

func refresh_potions() -> void:
	var cap := Game.potion_capacity()
	var rows := 2 if cap > 6 else 1
	var tex: Texture2D = load("res://assets/ui/hud_shelf%d.png" % (rows * 6))
	var sz := tex.get_size() * SHELF_K
	potion_art.texture = tex
	potion_art.size = sz
	UIKit.place(potion_panel, Vector2(1, 1), Vector2(-sz.x - 22, -sz.y - 22), sz, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	potion_count.text = "%d/%d" % [Game.potions.size(), cap]
	potion_count.position = Vector2(sz.x / 2.0 - 39, -2)
	potion_count.size = Vector2(78, 24)
	potion_count.add_theme_color_override("font_color", INK_COL if not Game.potions_full() else Color("7a1d18"))
	for c in potion_slots:
		c.queue_free()
	potion_slots.clear()
	for i in cap:
		var r := i / 6
		var col := i % 6
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var top := (7.0 + r * 31.0) * SHELF_K
		b.position = Vector2((SHELF_SLOT_X[col] - 10) * SHELF_K, top)
		b.size = Vector2(20, 31) * SHELF_K
		potion_grid.add_child(b)
		potion_slots.append(b)
		if i < Game.potions.size():
			var p: Dictionary = Game.potions[i]
			var ic := TextureRect.new()
			ic.texture = load("res://assets/icons/pot_%s.png" % p["id"])
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_SCALE
			ic.size = Vector2(16, 16) * SHELF_K
			ic.position = Vector2(2, 6) * SHELF_K
			ic.pivot_offset = Vector2(8, 16) * SHELF_K
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.name = "Icon"
			ic.visible = i != _held_slot
			b.add_child(ic)
			var st := HBoxContainer.new()
			st.add_theme_constant_override("separation", 1)
			st.mouse_filter = Control.MOUSE_FILTER_IGNORE
			st.position = Vector2(1.5, 23.5) * SHELF_K
			for k in 3:
				var s := UIKit.icon("res://assets/ui/shelf_star.png" if k < Game.stars_for(int(p["potency"])) else "res://assets/ui/shelf_star_empty.png", SHELF_K)
				st.add_child(s)
			b.add_child(st)
			# la runa (o las dos runas) de la etiqueta, pequeñas junto al frasco
			var gy := 2.0
			for rk in ["rune", "rune2"]:
				var rune := String(p.get(rk, ""))
				if rune != "" and ResourceLoader.exists("res://assets/icons/rune_%s.png" % rune):
					var g := UIKit.icon("res://assets/icons/rune_%s.png" % rune, 1.0)
					g.position = Vector2(b.size.x - 24, gy)
					b.add_child(g)
					gy += 24.0
			var idx := i
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.pressed.connect(func():
				close_picker()   # --- R6 UI
				potion_pressed.emit(idx))
			b.mouse_entered.connect(func():
				if _pick_on:
					return   # --- R6 UI: eligiendo con el teclado, el tooltip es el del frasco elegido
				show_potion_tooltip(idx)
				var tw := ic.create_tween()
				tw.tween_property(ic, "position:y", 3 * SHELF_K, 0.08))
			b.mouse_exited.connect(func():
				if _pick_on:
					return   # --- R6 UI
				hide_tooltip()
				if is_instance_valid(ic):
					var tw := ic.create_tween()
					tw.tween_property(ic, "position:y", 6 * SHELF_K, 0.1))
		else:
			b.disabled = true
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- R6 UI: el estante se rehízo (cambiaron las pociones): el aro del estante para elegir vuelve a su frasco
	_pick_lifted = -1
	if _pick_on:
		_pick_show.call_deferred()
	# --- end R6 UI

## Centro (en pantalla) del frasco del hueco index.
func potion_slot_center(index: int) -> Vector2:
	if index >= 0 and index < potion_slots.size():
		var b: Control = potion_slots[index]
		return b.get_global_rect().position + Vector2(10, 14) * SHELF_K
	return potion_panel.get_global_rect().get_center()

## --- R3 BENCH: esconde el frasco del hueco index mientras otro vuela hacia él (release lo muestra con un saltito).
func hold_potion_slot(index: int) -> void:
	_held_slot = index
	if index >= 0 and index < potion_slots.size() and potion_slots[index].has_node("Icon"):
		potion_slots[index].get_node("Icon").visible = false

func release_potion_slot() -> void:
	var i := _held_slot
	_held_slot = -1
	if i >= 0 and i < potion_slots.size() and potion_slots[i].has_node("Icon"):
		var ic: TextureRect = potion_slots[i].get_node("Icon")
		ic.visible = true
		ic.scale = Vector2(1.3, 0.7)
		ic.create_tween().tween_property(ic, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ consejos, tooltip, avisos

# --- R3 BENCH: el consejo es una nota de papel de una línea; se va sola a los secs segundos (0: se queda).
func _build_tip() -> void:
	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", UIKit.paper_style(10))
	UIKit.place(tip_panel, Vector2(0, 0), Vector2(1200, 100), Vector2(10, 0))
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tip_panel)
	var h := UIKit.hbox(10)
	tip_panel.add_child(h)
	var ic := UIKit.icon("res://assets/icons/emote_sparkle.png", 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	tip_text = UIKit.rich(22)
	tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF   # una línea: la nota mide lo que su texto
	tip_text.add_theme_color_override("default_color", INK_COL)
	tip_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tip_text)
	tip_panel.visible = false

func show_tip(text: String, secs := 10.0) -> void:
	tip_text.text = text
	tip_panel.visible = true
	_fit_tip()
	UIKit.pop_in(tip_panel)
	_tip_gen += 1
	if secs > 0.0:
		var gen := _tip_gen
		get_tree().create_timer(secs).timeout.connect(func():
			if gen == _tip_gen and tip_panel.visible:
				var tw := tip_panel.create_tween()
				tw.tween_property(tip_panel, "modulate:a", 0.0, 0.5)
				tw.tween_callback(func():
					if gen == _tip_gen:
						tip_panel.visible = false
					tip_panel.modulate.a = 1.0))

## La nota del consejo se ajusta a su texto y queda pegada a la derecha (bajo el menú).
func _fit_tip() -> void:
	for i in 3:
		tip_panel.reset_size()
		tip_panel.position.x = root.size.x - tip_panel.size.x - 22
		tip_panel.pivot_offset = tip_panel.size / 2.0
		await get_tree().process_frame
		if not is_instance_valid(tip_panel):
			return

## Los RichTextLabel calculan su alto un cuadro después: reajusta el panel entonces.
func _resize_later(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c):
		c.reset_size()
	await get_tree().process_frame
	if is_instance_valid(c):
		c.reset_size()

func hide_tip() -> void:
	_tip_gen += 1
	tip_panel.visible = false
	tip_panel.modulate.a = 1.0

func _build_tooltip() -> void:
	tooltip = UIKit.fancy_panel(Color(0.06, 0.05, 0.1, 0.96), 14)
	# --- R6 UI: más aire a los lados y abajo: la línea más ancha (el efecto de la poción) tocaba las esquinas doradas
	var tsb := tooltip.get_theme_stylebox("panel") as StyleBoxFlat
	if tsb:
		tsb.content_margin_left = 24
		tsb.content_margin_right = 24
		tsb.content_margin_bottom = 16
	# --- end R6 UI
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.z_index = 50
	root.add_child(tooltip)
	tooltip_box = UIKit.vbox(4)
	tooltip.add_child(tooltip_box)
	tooltip.visible = false

func _clear_tooltip() -> void:
	for c in tooltip_box.get_children():
		tooltip_box.remove_child(c)
		c.queue_free()

# --- R3 BENCH: tooltips cortos: el ingrediente (nombre, esencias en iconos, cuántos quedan)...
func show_ingredient_tooltip(id: String) -> void:
	_clear_tooltip()
	var d: Dictionary = Data.INGREDIENTS[id]
	var h := UIKit.hbox(10)
	tooltip_box.add_child(h)
	h.add_child(UIKit.icon("res://assets/icons/ing_%s.png" % id, 2.5))
	var v := UIKit.vbox(2)
	h.add_child(v)
	v.add_child(UIKit.label(d["name"], 24, UIKit.GOLD_BRIGHT, UIKit.font_bold))
	var row := UIKit.hbox(4)
	v.add_child(row)
	for e in Data.ESSENCE_ORDER:
		for k in int(d["ess"].get(e, 0)):
			row.add_child(UIKit.ess_icon(e, 2.0))
	var n: int = Game.stock.get(id, 0)
	var cnt := UIKit.label("×%d" % n, 22, UIKit.TEXT if n > 0 else UIKit.BAD, UIKit.font_bold)
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cnt)
	tooltip.visible = true
	tooltip.reset_size()
	_place_tooltip()

# ... y la poción (nombre, estrellas, para qué sirve en una línea, y su runa si la tiene).
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
	v.add_child(UIKit.label(d["name"], 24, UIKit.GOLD_BRIGHT, UIKit.font_bold))
	v.add_child(UIKit.stars(Game.stars_for(p["potency"]), 1.1))
	var eff := UIKit.label(d["effect"], 19, Color("b8aecb"), UIKit.font_italic)
	tooltip_box.add_child(eff)
	for rk in ["rune", "rune2"]:
		var rune := String(p.get(rk, ""))
		if rune == "":
			continue
		var rh := UIKit.hbox(6)
		if ResourceLoader.exists("res://assets/icons/rune_%s.png" % rune):
			rh.add_child(UIKit.icon("res://assets/icons/rune_%s.png" % rune, 1.0))
		rh.add_child(UIKit.label(_rune_name(rune), 20, UIKit.GOLD, UIKit.font_bold))
		if p.has(rk + "_stars"):
			rh.add_child(UIKit.stars(int(p[rk + "_stars"]), 0.8))
		tooltip_box.add_child(rh)
	tooltip.visible = true
	tooltip.reset_size()
	_place_tooltip()

func hide_tooltip() -> void:
	tooltip.visible = false

func _place_tooltip() -> void:
	# --- R6 UI: eligiendo en el estante, el tooltip va justo encima del frasco elegido
	if _pick_on and _pick_i < potion_slots.size():
		var r: Rect2 = (potion_slots[_pick_i] as Control).get_global_rect()
		var tp := Vector2(r.get_center().x - tooltip.size.x * 0.5, potion_panel.get_global_rect().position.y - tooltip.size.y - 98.0)
		tooltip.position = tp.clamp(Vector2(10, 10), root.size - tooltip.size - Vector2(10, 10))
		return
	# --- end R6 UI
	var mp := root.get_local_mouse_position()
	if PadCursor.active:
		mp = PadCursor.where   # con el mando, junto a su cursor
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
	UIKit.place(toast_box, Vector2(0.5, 0), Vector2(-400, 236), Vector2(800, 10), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

func toast(text: String, color := UIKit.TEXT, duration := 2.6) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.05, 0.1, 0.9), UIKit.GOLD, 1, 18, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label(text, 21, color, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
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

## --- R4 MERGE: quita los avisos que queden (p. ej. «¡Inscrita!» al aceptar la invitación, justo antes del correo).
func clear_toasts() -> void:
	for c in toast_box.get_children():
		c.queue_free()

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

# --- WORLD: en el mercado no se ven el caldero ni las pociones (son cosas de la tienda)
func set_shop_panels_visible(on: bool) -> void:
	potion_panel.visible = on   # --- R3 BENCH: ya no hay panel del caldero
	if not on:
		hide_tooltip()
# --- end WORLD

func set_gameplay_visible(on: bool) -> void:
	potion_panel.visible = on   # --- R3 BENCH
	set_menu_visible(on)
	if not on:
		hide_order()
		hide_tip()
		hide_tooltip()

# --- MAGIC / PREP: los pergaminos tenían una pestaña en este estante y el caldero un botón «Tinta».
# --- R3 BENCH: los pergaminos dejan de ser un producto (MAGIC3) y «Tinta» está en el banco del caldero (BrewUI).
# Se conservan las funciones y señales que otros scripts llaman, vacías, para que nada se rompa.
signal scroll_pressed(index: int)
signal ink_pressed
var rack_tab := "potion"

func magic_setup() -> void:
	pass

func show_rack_tab(_kind: String) -> void:
	pass

func refresh_scrolls() -> void:
	pass

func scroll_slot_center(_index: int) -> Vector2:
	return potion_panel.get_global_rect().get_center()

func show_scroll_tooltip(_idx: int) -> void:
	pass
# --- end R3 BENCH

# --- R4 PACE: el reloj del día en la placa del HUD, cuántos esperan en la fila y la paciencia del ticket -------------
# Bajo «Día n»: una esfera de reloj (assets/ui/hud_clock.png con las agujas dibujadas encima), la hora de 5 en 5
# minutos (9:00 a 18:00; en la última hora se pone roja y late; a las 18:00, «Cerrado») y una personita con cuántos
# esperan en la fila (ámbar o rojo si alguien está por irse). El ticket del pedido lleva un reloj de arena y una barra
# con la paciencia de quien espera en el mostrador. main.gd lo llama (bloque R4 PACE): set_clock, set_clock_visible,
# set_queue, set_order_patience.
var clock_row: HBoxContainer
var clock_face: Control
var clock_label: Label
var queue_box: HBoxContainer
var queue_icon: TextureRect
var queue_label: Label
var order_patience_row: HBoxContainer
var order_pbar: ProgressBar
var order_pglass: TextureRect
var _pbar_fill: StyleBoxFlat
var _clock_tex: Texture2D
var _clock_min := 540
var _clock_state := ""
var _queue_worst := 1.0
var _queue_n := 0
var _order_p := 1.0
var _pace_t := 0.0

func _pace_build_clock(v: VBoxContainer) -> void:
	_clock_tex = load("res://assets/ui/hud_clock.png")
	clock_row = UIKit.hbox(8)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(clock_row)
	v.move_child(clock_row, 1)   # justo debajo de «Día n»
	clock_face = Control.new()
	clock_face.custom_minimum_size = Vector2(39, 39)
	clock_face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_face.draw.connect(_draw_clock)
	clock_row.add_child(clock_face)
	clock_label = UIKit.shadow(UIKit.label("9:00", 30, UIKit.GOLD_BRIGHT, UIKit.font_bold))
	clock_label.custom_minimum_size = Vector2(78, 0)
	clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(clock_label)
	queue_box = UIKit.hbox(4)
	queue_box.mouse_filter = Control.MOUSE_FILTER_PASS
	queue_box.tooltip_text = "In line"
	clock_row.add_child(queue_box)
	queue_icon = UIKit.icon("res://assets/ui/hud_queue.png", 3.0)
	queue_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_box.add_child(queue_icon)
	queue_label = UIKit.shadow(UIKit.label("0", 28, UIKit.TEXT, UIKit.font_bold))
	queue_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_box.add_child(queue_label)
	clock_row.visible = false

## La esfera (13x13 a x3) y las agujas, píxel a píxel.
func _draw_clock() -> void:
	if _clock_tex:
		clock_face.draw_texture_rect(_clock_tex, Rect2(Vector2.ZERO, Vector2(39, 39)), false)
	var h := fmod(float(_clock_min) / 60.0, 12.0) / 12.0
	var m := float(_clock_min % 60) / 60.0
	_clock_hand(m * TAU, 4.2, Color("6b4a30"))
	_clock_hand(h * TAU, 2.7, Color("2e1d12"))
	clock_face.draw_rect(Rect2(Vector2(18, 18), Vector2(3, 3)), Color("b8862f"))

func _clock_hand(a: float, length: float, col: Color) -> void:
	var dir := Vector2(sin(a), -cos(a))
	var t := 0.7
	while t <= length:
		var p := (Vector2(6.0, 6.0) + dir * t).round()
		clock_face.draw_rect(Rect2(p * 3.0, Vector2(3, 3)), col)
		t += 0.5

func set_clock_visible(on: bool) -> void:
	if clock_row:
		clock_row.visible = on
		_clock_state = ""
		hud_panel.reset_size()

## La hora del HUD. minutes: desde la medianoche (540 = 9:00 ... 1080 = 18:00), se muestra de 5 en 5. state: "open",
## "late" (la última hora: roja y latiendo), "closed" (cerrado) o "paused" (un menú de lectura detiene el reloj).
func set_clock(minutes: int, state := "open") -> void:
	if clock_row == null:
		return
	var shown := (minutes / 5) * 5
	if shown != _clock_min or state != _clock_state:
		_clock_min = shown
		_clock_state = state
		if state == "closed":
			clock_label.text = "Closed"
			clock_label.add_theme_font_size_override("font_size", 24)
		else:
			clock_label.text = UIKit.clock(shown)   # --- R5 EN-UI: 12 horas, sin AM/PM («1:00» = 13:00)
			clock_label.add_theme_font_size_override("font_size", 30)
		var col := UIKit.GOLD_BRIGHT
		if state == "late":
			col = Color(1.0, 0.56, 0.42)
		elif state == "closed":
			col = Color(0.86, 0.72, 0.62)
		clock_label.add_theme_color_override("font_color", col)
		clock_face.queue_redraw()
	clock_row.modulate.a = 0.6 if state == "paused" else 1.0

## Cuántos esperan en la fila y la paciencia del que está peor (0..1): ámbar con menos de la mitad, rojo con menos de
## un cuarto.
func set_queue(n: int, worst: float) -> void:
	if queue_box == null:
		return
	if n == _queue_n and absf(worst - _queue_worst) < 0.01:
		return
	_queue_n = n
	_queue_worst = worst
	queue_label.text = str(n)
	var col := UIKit.TEXT
	if n == 0:
		col = UIKit.MUTED
	elif worst < 0.25:
		col = Color(1.0, 0.5, 0.42)
	elif worst < 0.5:
		col = Color(1.0, 0.8, 0.45)
	queue_label.add_theme_color_override("font_color", col)
	queue_icon.modulate = Color(1, 1, 1, 0.45) if n == 0 else Color(1, 1, 1, 1)

func _pace_ticket_row(v: VBoxContainer) -> void:
	order_patience_row = UIKit.hbox(8)
	order_patience_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(order_patience_row)
	order_pglass = PaperKit.pic("paper_i_hourglass", 2.0)
	order_pglass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	order_pglass.pivot_offset = order_pglass.custom_minimum_size / 2.0
	order_patience_row.add_child(order_pglass)
	order_pbar = ProgressBar.new()
	order_pbar.custom_minimum_size = Vector2(320, 12)
	order_pbar.max_value = 1.0
	order_pbar.step = 0.0
	order_pbar.show_percentage = false
	order_pbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	order_pbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.37, 0.28, 0.2, 0.16)
	bg.border_color = Color(0.23, 0.15, 0.09, 0.6)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	_pbar_fill = StyleBoxFlat.new()
	_pbar_fill.bg_color = PaperKit.HERB
	_pbar_fill.set_corner_radius_all(3)
	order_pbar.add_theme_stylebox_override("background", bg)
	order_pbar.add_theme_stylebox_override("fill", _pbar_fill)
	order_patience_row.add_child(order_pbar)
	order_patience_row.visible = false

## La paciencia de quien espera en el mostrador (0..1). p < 0: no se muestra (aún no pidió, o ya se le atendió).
func set_order_patience(p: float) -> void:
	if order_patience_row == null:
		return
	if p < 0.0:
		if order_patience_row.visible:
			order_patience_row.visible = false
			order_paper.reset_size()
		return
	if not order_patience_row.visible:
		order_patience_row.visible = true
		order_paper.reset_size()
	_order_p = p
	order_pbar.value = p
	var col := PaperKit.HERB
	if p < 0.25:
		col = PaperKit.RED_INK
	elif p < 0.5:
		col = Color("c27a2c")
	_pbar_fill.bg_color = col

func _pace_process_ui(delta: float) -> void:
	_pace_t += delta
	if clock_row and clock_row.visible:
		if _clock_state == "late":
			clock_label.modulate.a = 0.72 + 0.28 * sin(_pace_t * 6.0)
		else:
			clock_label.modulate.a = 1.0
		if _queue_n > 0 and _queue_worst < 0.25:
			queue_label.modulate.a = 0.78 + 0.22 * sin(_pace_t * 9.0)   # --- R4 MERGE: late, pero nunca casi invisible (antes 0.2..1)
		else:
			queue_label.modulate.a = 1.0
	if order_patience_row and order_patience_row.visible:
		if _order_p < 0.25:
			order_pglass.modulate = Color(1.0, 0.6 + 0.4 * sin(_pace_t * 10.0), 0.6 + 0.4 * sin(_pace_t * 10.0))
			order_pglass.rotation = sin(_pace_t * 18.0) * 0.12
		else:
			order_pglass.modulate = Color.WHITE
			order_pglass.rotation = 0.0
# --- end R4 PACE

# --- R6 UI: elegir una poción del estante con el teclado o el mando -------------------------------------------------
# «E  Give potion» en el mostrador (con varias clases de poción en el estante), «Space  Present» en el concurso o «Tab»
# con el banco abierto: el estante se enciende, un aro dorado marca el frasco elegido (se levanta un poco y sale su
# tooltip encima) y el aviso de encima dice las teclas: ← → (o A / D, o la cruceta) eligen, E / Intro / Espacio (A del
# mando) lo dan y Esc (B) vuelve. Con el ratón se sigue tocando el frasco. Al dar la poción se emite potion_pressed(i),
# como un clic en el frasco (main.gd decide a quién: el cliente, el cuervo, el jurado...).
var _pick_on := false
var _pick_i := 0
var _pick_verb := "Give"
var _pick_valid: Callable
var _pick_ring: NinePatchRect

func picker_open() -> bool:
	return _pick_on

func picker_verb() -> String:
	return _pick_verb

func picker_index() -> int:
	return _pick_i if _pick_on else -1

## Abre el estante para elegir. valid: si deja de ser cierto (se fue el cliente...), el estante se cierra solo.
func open_picker(verb := "Give", valid := Callable()) -> void:
	if Game.potions.is_empty() or not potion_panel.is_visible_in_tree():
		return
	_pick_on = true
	_pick_verb = verb
	_pick_valid = valid
	_pick_i = 0   # siempre desde el primer frasco (el estante cambia entre una vez y otra)
	if _pick_ring == null:
		_pick_ring = NinePatchRect.new()
		_pick_ring.texture = PaperKit.tex("r6_focus9")
		for side in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
			_pick_ring.set(side, 15)
		_pick_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_pick_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		potion_panel.add_child(_pick_ring)
	Sfx.play("hover", 0.05, -8.0)
	_pick_show()

func close_picker() -> void:
	if not _pick_on:
		return
	_pick_on = false
	if is_instance_valid(_pick_ring):
		_pick_ring.visible = false
	_pick_lift(-1)
	hide_tooltip()

func _pick_move(d: int) -> void:
	var n := Game.potions.size()
	if n == 0:
		close_picker()
		return
	var j := clampi(_pick_i + d, 0, n - 1)
	if j != _pick_i:
		_pick_i = j
		Sfx.play("hover", 0.05, -12.0)
		_pick_show()

func _pick_confirm() -> void:
	var i := _pick_i
	close_picker()
	if i >= 0 and i < Game.potions.size():
		potion_pressed.emit(i)

## El aro sobre el frasco elegido, el frasco un poco levantado y su tooltip encima del estante.
func _pick_show() -> void:
	if not _pick_on:
		return
	if _pick_i >= potion_slots.size() or _pick_i >= Game.potions.size():
		close_picker()
		return
	var b: Control = potion_slots[_pick_i]
	_pick_ring.visible = true
	_pick_ring.position = b.position - Vector2(6, 4)
	_pick_ring.size = b.size + Vector2(12, 8)
	_pick_lift(_pick_i)
	show_potion_tooltip(_pick_i)

var _pick_lifted := -1
func _pick_lift(i: int) -> void:
	if _pick_lifted == i:
		return
	for k in [_pick_lifted, i]:
		if k >= 0 and k < potion_slots.size() and potion_slots[k].has_node("Icon"):
			var ic: TextureRect = potion_slots[k].get_node("Icon")
			var tw := ic.create_tween()
			tw.tween_property(ic, "position:y", (3 if k == i else 6) * SHELF_K, 0.08)
	_pick_lifted = i

func _input(ev: InputEvent) -> void:
	if not _pick_on:
		return
	# un clic fuera del estante lo cierra (el clic en un frasco lo da, como siempre)
	if ev is InputEventMouseButton and ev.pressed and ev.device != Glyphs.PAD_DEVICE:
		if not potion_panel.get_global_rect().has_point(root.get_global_mouse_position()):
			close_picker()
		return
	if not (ev is InputEventKey and ev.pressed):
		return
	var k: int = ev.keycode
	var cols := 6
	match k:
		KEY_LEFT, KEY_A:
			_pick_move(-1)
		KEY_RIGHT, KEY_D:
			_pick_move(1)
		KEY_UP, KEY_W:
			_pick_move(-cols)
		KEY_DOWN, KEY_S:
			_pick_move(cols)
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not ev.echo:
				_pick_confirm()
		KEY_ESCAPE, KEY_BACKSPACE, KEY_TAB:
			if not ev.echo:
				close_picker()
				Sfx.play("click", 0.05, -10.0)
		_:
			if k >= KEY_1 and k <= KEY_9 and not ev.echo and k - KEY_1 < Game.potions.size():
				_pick_i = k - KEY_1
				_pick_confirm()
			else:
				return
	get_viewport().set_input_as_handled()

## Cada cuadro: si ya no tiene sentido (se fue el cliente, se abrió un papel...), se cierra.
func _pick_process() -> void:
	if not _pick_on:
		return
	if Game.potions.is_empty() or not potion_panel.is_visible_in_tree() or (_pick_valid.is_valid() and not bool(_pick_valid.call())):
		close_picker()
		return
	if _pick_i >= Game.potions.size():
		_pick_i = Game.potions.size() - 1
		_pick_show()
# --- end R6 UI
