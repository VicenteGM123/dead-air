extends CanvasLayer
class_name EventUI
## --- R4 EVENTS: la interfaz de los eventos. Capa 6: sobre el HUD del juego (capa 5) y el banco del caldero (capa 4),
## debajo de los paneles de papel (capa 10). El viaje (el mapa de Arvendal) va en su propia capa 15.
##   - el viaje: el mapa en pergamino; el carro avanza por el camino punteado desde su tienda hasta el evento;
##   - el reloj (tablilla de madera con el reloj de arena), la meta en una tarjetita de papel y la barra de puntos con
##     las marcas de bronce, plata y oro (arriba al centro);
##   - la pizarra (la receta, el cartel del puesto o el tema de la ronda) arriba a la izquierda, junto al HUD;
##   - la fila (cara, lo que pide, paciencia) o los puntos de los rivales, arriba a la derecha;
##   - la cuenta atrás, el tema de cada ronda, el jurado (tres tarjetas: estrellas y una frase) y la tarjeta de
##     resultados con la medalla; el recordatorio del evento aceptado (los días de tienda); el botón «Caldero».
## Ratón; teclado (Espacio / Intro = el botón de la tarjeta abierta); mando: PadCursor toca los botones de pad_root().

signal results_closed
signal jury_closed
signal bench_pressed

const INK := Color("3a2618")
const CREAM := Color("f2e2bc")
const OUTL := Color(0.1, 0.06, 0.12)
## El mapa (assets/ui/evui_map.png, 320x180): lugares y caminos en píxeles del mapa (los mismos de events_ui_art.py).
const MAP_ART := Vector2(320, 180)
const MAP_PLACES := {"casa": Vector2(70, 104), "academia": Vector2(252, 50), "concurso": Vector2(168, 132), "torneo": Vector2(270, 140)}
const MAP_ROUTES := {
	"academia": [Vector2(70, 104), Vector2(100, 98), Vector2(128, 86), Vector2(152, 74), Vector2(190, 66), Vector2(222, 58), Vector2(252, 50)],
	"concurso": [Vector2(70, 104), Vector2(96, 114), Vector2(122, 122), Vector2(146, 128), Vector2(168, 132)],
	"torneo": [Vector2(70, 104), Vector2(96, 114), Vector2(122, 122), Vector2(146, 128), Vector2(176, 140), Vector2(210, 146),
		Vector2(240, 146), Vector2(270, 140)],
}
const PLACE_LABEL := {"casa": "Your shop", "academia": "Valmora", "concurso": "Oakdale", "torneo": "Clearbreeze"}

var main
var root: Control             # el HUD del evento (no bloquea el ratón salvo sus botones)
var modal: Control            # tarjetas centradas (jurado, resultados); bloquea el ratón cuando hay una
var _modal_kind := ""
var _modal_btn: Button        # el botón de la tarjeta abierta (Espacio / Intro)
var map_layer: CanvasLayer
var _map: _MapView
var _map_bg: ColorRect

var plate: PanelContainer     # el reloj
var time_lbl: Label
var goal_card: PanelContainer
var goal_txt: RichTextLabel
var bar: _ScoreBar
var board: PanelContainer     # la pizarra (receta / cartel / tema)
var board_txt: RichTextLabel
var line_box: HBoxContainer   # la fila
var bench_btn: Button
var reminder: PanelContainer
var reminder_txt: Label
var reminder_seal: TextureRect
var big: Label                # la cuenta atrás y los avisos grandes
var _line_sig := ""
var _line_cards: Array = []   # [{card, bar, fill, icon}]
var _last_sec := -1
var _head_cache := {}

func setup(m) -> void:
	main = m

func _ready() -> void:
	layer = 6
	UIKit.load_fonts()
	PaperKit.load_fonts()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.theme = UIKit.theme()
	add_child(modal)
	_build_plate()
	_build_board()
	_build_line()
	_build_bench_button()
	_build_reminder()
	_build_big()
	map_layer = CanvasLayer.new()
	map_layer.layer = 15
	add_child(map_layer)
	hide_hud()

# ------------------------------------------------------------------ montaje del HUD

func _outlined(text: String, size: int, col: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UIKit.label(text, size, col, font, align)
	l.add_theme_color_override("font_outline_color", OUTL)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	return l

func _build_plate() -> void:
	var v := UIKit.vbox(4)
	UIKit.place(v, Vector2(0.5, 0), Vector2(-250, 8), Vector2(500, 10), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	plate = PaperKit.panel("wood", Vector2(26, 2))
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(plate)
	var h := UIKit.hbox(10)
	plate.add_child(h)
	var hg := PaperKit.pic("paper_i_hourglass", 4.0)
	hg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hg)
	time_lbl = _outlined("1:00", 50, CREAM, UIKit.font_sc_bold)
	time_lbl.custom_minimum_size = Vector2(124, 0)
	h.add_child(time_lbl)
	goal_card = PaperKit.panel("card", Vector2(22, 4))
	goal_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	goal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(goal_card)
	goal_txt = PaperKit.rich(34, INK)
	goal_txt.fit_content = true
	goal_txt.autowrap_mode = TextServer.AUTOWRAP_OFF
	goal_txt.clip_contents = false   # --- R5 EN-UI: el último número (Caveat en negrita) ya no sale cortado («0» -> «c»)
	goal_card.add_child(goal_txt)
	bar = _ScoreBar.new()
	bar.custom_minimum_size = Vector2(460, 54)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(bar)

func _build_board() -> void:
	board = PaperKit.panel("note", Vector2(22, 8))
	UIKit.place(board, Vector2(0, 0), Vector2(252, 14), Vector2(10, 10))
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(board)
	board_txt = PaperKit.rich(34, INK)
	board_txt.fit_content = true
	board_txt.autowrap_mode = TextServer.AUTOWRAP_OFF
	board.add_child(board_txt)
	PaperKit.decor(board, "paper_pin_green", Vector2(0.5, 0.0), Vector2(-10, -12))

func _build_line() -> void:
	line_box = UIKit.hbox(8)
	UIKit.place(line_box, Vector2(1, 0), Vector2(-122, 100), Vector2(10, 10), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	line_box.alignment = BoxContainer.ALIGNMENT_END
	line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(line_box)

func _build_bench_button() -> void:
	# --- R6 UI: el mismo botón que los de arriba en la tienda (HudButton principal: pergamino dorado, aro de latón), con
	# el caldero y su tecla (E; A del mando). Sigue llamándose «Cauldron» (el mando y las pruebas lo buscan así).
	bench_btn = HudButton.make("primary", "Cauldron", "r6_ico_cauldron", "bench", func(): bench_pressed.emit())   # (letra 26: la de los botones de arriba)
	bench_btn.set_tall()   # (resume 2) 66 de alto: la misma forma y tamaño que «Open shop» arriba en la tienda
	bench_btn.custom_minimum_size = Vector2(260, 66)
	UIKit.place(bench_btn, Vector2(0.5, 1), Vector2(-130, -66.0 - GameUI.HUD_EDGE), Vector2(260, 66), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	bench_btn.set_tip("Back to your cauldron", ["bench"])
	# --- end R6 UI
	bench_btn.visible = false
	root.add_child(bench_btn)

func _build_reminder() -> void:
	reminder = PaperKit.panel("tag", Vector2(14, 4))
	UIKit.place(reminder, Vector2(0, 0), Vector2(26, 160), Vector2(10, 10))
	reminder.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UIKit.hbox(8)
	reminder.add_child(h)
	reminder_seal = PaperKit.pic("evui_seal_academia", 1.5)
	reminder_seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(reminder_seal)
	reminder_txt = PaperKit.hand("", 26, INK, true)
	reminder_txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(reminder_txt)
	reminder.visible = false
	add_child(reminder)   # fuera de root: se ve también los días de tienda

func _build_big() -> void:
	big = _outlined("", 120, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold)
	UIKit.place(big, Vector2(0.5, 0.5), Vector2(-500, -150), Vector2(1000, 200), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	big.modulate.a = 0.0
	modal.add_child(big)

# ------------------------------------------------------------------ el HUD durante el evento

func show_hud(kind: String) -> void:
	root.visible = true
	plate.visible = true
	goal_card.visible = true
	board.visible = false
	bar.visible = kind != "concurso"
	_line_sig = ""
	for c in line_box.get_children():
		c.queue_free()
	_line_cards.clear()
	set_time(0.0, 1.0)

func hide_hud() -> void:
	root.visible = false
	bench_btn.visible = false
	_last_sec = -1

## El reloj: m:ss; los últimos 10 segundos en rojo, con un tic por segundo.
func set_time(left: float, _total: float) -> void:
	var s := maxi(0, int(ceil(left)))
	time_lbl.text = "%d:%02d" % [s / 60, s % 60]
	var low := s <= 10 and left > 0.0
	time_lbl.add_theme_color_override("font_color", Color("ff8a7a") if low else CREAM)
	if low and s != _last_sec:
		Sfx.play("click", 0.0, -6.0)
		time_lbl.pivot_offset = time_lbl.size / 2.0
		time_lbl.scale = Vector2(1.18, 1.18)
		create_tween().tween_property(time_lbl, "scale", Vector2.ONE, 0.25)
	_last_sec = s

## La meta (BBCode con iconos: Events.icon()).
func set_goal(bb: String) -> void:
	goal_txt.text = "[center]%s[/center]" % bb
	_fit(goal_card)

## La barra de puntos: score y las marcas (Events.cuts: max, bronze, silver, gold). cuts vacío = sin barra.
func set_score(score: int, cuts: Dictionary) -> void:
	bar.visible = not cuts.is_empty()
	bar.score = score
	bar.cuts = cuts
	bar.queue_redraw()

## La pizarra de arriba a la izquierda (BBCode). "" la esconde.
func set_board(bb: String) -> void:
	board.visible = bb != ""
	board_txt.text = bb
	_fit(board)

## El botón «Caldero» (cuando el banco está cerrado durante el juego).
func set_bench_button(on: bool) -> void:
	bench_btn.visible = on

## La fila: [{"who": sprite, "potion": id o "", "pat": 0..1 o -1, "state": "wait" | "served" | "lost", "label": ""}].
## Las tarjetas se rehacen solo cuando cambia quién está; si no, se actualizan las barras.
func set_line(entries: Array) -> void:
	var sig := ""
	for e in entries:
		sig += "%s:%s:%s:%s:%s|" % [e.get("who", ""), e.get("potion", ""), e.get("state", ""), e.get("name", ""), e.get("label", "")]
	if sig != _line_sig:
		_line_sig = sig
		for c in line_box.get_children():
			c.queue_free()
		_line_cards.clear()
		for e in entries:
			_line_cards.append(_line_card(e))
	for i in mini(entries.size(), _line_cards.size()):
		var e: Dictionary = entries[i]
		var lc: Dictionary = _line_cards[i]
		var pat := float(e.get("pat", -1.0))
		if lc["fill"] != null and pat >= 0.0:
			var f: ColorRect = lc["fill"]
			f.size.x = 76.0 * clampf(pat, 0.0, 1.0)
			f.color = Color("d24a3c").lerp(Color("e2b84a"), clampf(pat * 2.0, 0.0, 1.0)).lerp(Color("6fbf5a"), clampf(pat * 2.0 - 1.0, 0.0, 1.0))

func _line_card(e: Dictionary) -> Dictionary:
	var card := PaperKit.panel("card", Vector2(8, 6))
	card.custom_minimum_size = Vector2(96, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(2)
	card.add_child(v)
	var state := String(e.get("state", "wait"))
	var who := String(e.get("who", ""))
	if who == "":
		# una tienda sin cara (los rivales del concurso): su inicial en un sello de lacre
		var sl := PaperKit.seal(String(e.get("name", "?")).left(1), "paper_seal", 3.0)
		sl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(sl)
	else:
		var face := TextureRect.new()
		face.texture = _head(who)
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_SCALE
		face.custom_minimum_size = Vector2(72, 72)
		face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if state == "lost":
			face.modulate = Color(0.55, 0.5, 0.5)
		v.add_child(face)
	if String(e.get("name", "")) != "":
		# los nombres largos («Raíces y Rocío») van en dos renglones para no salirse de la tarjeta
		var nm := String(e["name"])
		PaperKit.load_fonts()
		var long_name := PaperKit.font_hand_bold != null and \
			PaperKit.font_hand_bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x > 84.0
		v.add_child(PaperKit.hand(nm, 20 if long_name else 22, PaperKit.INK_SOFT, true, HORIZONTAL_ALIGNMENT_CENTER,
			86.0 if long_name else 0.0))
	var pot := String(e.get("potion", ""))
	var icon: TextureRect = null
	if String(e.get("label", "")) != "":
		v.add_child(PaperKit.hand(String(e["label"]), 26, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	elif pot != "":
		icon = UIKit.icon("res://assets/icons/pot_%s.png" % pot, 2.5)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.tooltip_text = Events.potion_name(pot)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(icon)
	var fill: ColorRect = null
	if float(e.get("pat", -1.0)) >= 0.0:
		var bg := ColorRect.new()
		bg.color = Color(0.22, 0.15, 0.1, 0.85)
		bg.custom_minimum_size = Vector2(80, 12)
		bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bg)
		fill = ColorRect.new()
		fill.position = Vector2(2, 2)
		fill.size = Vector2(76, 8)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
	if state == "served":
		var ok := _outlined("✓", 44, Color("8fe08a"), UIKit.font_bold)
		PaperKit.attach(card, ok, Vector2(1, 0), Vector2(-34, -6))
	elif state == "lost":
		var no := _outlined("✗", 40, Color("ff8a7a"), UIKit.font_bold)
		PaperKit.attach(card, no, Vector2(1, 0), Vector2(-30, -6))
	line_box.add_child(card)
	return {"card": card, "fill": fill, "icon": icon}

## La cara de un personaje (como el ticket del pedido): un cuadrado desde la primera fila con píxeles.
func _head(who: String) -> Texture2D:
	var sid := Story.sprite_id(who) if who != "" else "anciano"
	if _head_cache.has(sid):
		return _head_cache[sid]
	var path := "res://assets/chars/%s_idle.png" % sid
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var fw := tex.get_width() / 2
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
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2((fw - 36) / 2, maxi(0, top - 2), 36, 36)
	_head_cache[sid] = at
	return at

## «+3 ★» que sube junto a la barra de puntos.
func pop(text: String, col := UIKit.GOLD_BRIGHT) -> void:
	var l := _outlined(text, 40, col, UIKit.font_sc_bold)
	l.position = Vector2(root.size.x / 2.0 + 230, 150)
	l.size = Vector2(260, 50)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 96.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)

## Un aviso grande en el centro («3», «¡Ya!», «¡Tiempo!»).
func shout(text: String, col := UIKit.GOLD_BRIGHT, dur := 0.8) -> void:
	big.text = text
	big.add_theme_color_override("font_color", col)
	big.pivot_offset = big.size / 2.0
	big.scale = Vector2(1.4, 1.4)
	big.modulate.a = 1.0
	var tw := big.create_tween()
	tw.tween_property(big, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(big, "modulate:a", 0.0, 0.25)

## La cuenta atrás: 3, 2, 1, ¡Ya!
func countdown() -> void:
	for n in ["3", "2", "1"]:
		shout(n, CREAM, 0.45)
		Sfx.play("click", 0.0, -2.0)
		await get_tree().create_timer(0.75).timeout
	shout("Go!", UIKit.GOLD_BRIGHT, 0.5)
	Sfx.play("sparkle", 0.0, -3.0)

func _fit(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c):
		c.reset_size()
	await get_tree().process_frame
	if is_instance_valid(c):
		c.reset_size()

# ------------------------------------------------------------------ tarjetas (modal)

func modal_open() -> bool:
	return _modal_kind != ""

func modal_kind() -> String:
	return _modal_kind

## Lo que el mando puede tocar: la tarjeta abierta o, si no hay, los botones del HUD (el botón «Caldero»).
func pad_root() -> Control:
	if _modal_kind != "":
		return modal
	return root if root.visible else null

## El botón de la tarjeta abierta (Espacio, Intro y el bot).
func press_default() -> bool:
	if _modal_btn and is_instance_valid(_modal_btn) and _modal_btn.visible and not _modal_btn.disabled:
		_modal_btn.pressed.emit()
		return true
	return false

func _open_modal(kind: String, panel: Control, dim_a := 0.55) -> Control:
	_close_modal()
	_modal_kind = kind
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.name = "Card"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(holder)
	modal.move_child(holder, 0)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, dim_a)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(dim)
	holder.add_child(UIKit.center(panel))
	await get_tree().process_frame
	if is_instance_valid(panel):
		UIKit.pop_in(panel)
	return holder

func _close_modal() -> void:
	_modal_kind = ""
	_modal_btn = null
	for c in modal.get_children():
		if c.name.begins_with("Card"):
			c.name = "Gone"
			c.queue_free()

func _unhandled_input(ev: InputEvent) -> void:
	if _modal_kind == "" or not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if ev.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if press_default():
			get_viewport().set_input_as_handled()

## El tema de la ronda (concurso), en grande unos segundos.
func show_theme(round_i: int, total: int, text: String) -> void:
	var p := PaperKit.panel("card", Vector2(70, 34))
	var v := UIKit.vbox(6)
	p.add_child(v)
	v.add_child(PaperKit.head("Round %d of %d" % [round_i, total], 40, Color("7a1d18"), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(PaperKit.hand("“%s”" % text, 66, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	var h := UIKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	for j in Events.JUDGES:
		var f := TextureRect.new()
		f.texture = _head(String(j["id"]))
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.custom_minimum_size = Vector2(64, 64)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(f)
	PaperKit.decor(p, "paper_pin_red", Vector2(0.5, 0.0), Vector2(-10, -14))
	Sfx.play("page", 0.05, -2.0)
	await _open_modal("theme", p, 0.35)
	await get_tree().create_timer(2.4).timeout
	if _modal_kind == "theme":
		_close_modal()

## El jurado de una ronda. d: {"round", "total", "theme", "potion": {"id", "potency", "perfect"} o {}, "scores": [3 ints],
## "lines": [3 textos], "table": [{"name", "round", "total", "me"}], "last": bool}. Espera a «Siguiente».
func show_jury(d: Dictionary) -> void:
	var p := PaperKit.panel("sheet", Vector2(56, 34))
	p.custom_minimum_size = Vector2(1180, 0)
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(PaperKit.head("Round %d · “%s”" % [int(d.get("round", 1)), String(d.get("theme", ""))], 38, Color("7a1d18"), HORIZONTAL_ALIGNMENT_CENTER))
	var pot: Dictionary = d.get("potion", {})
	var ph := UIKit.hbox(12)
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(ph)
	if pot.is_empty():
		ph.add_child(PaperKit.hand("You presented nothing.", 34, PaperKit.RED_INK, true))
	else:
		var pid := String(pot["id"])
		ph.add_child(UIKit.icon("res://assets/icons/pot_%s.png" % pid, 3.0))
		ph.add_child(PaperKit.hand(Events.potion_name(pid), 36, INK, true))
		ph.add_child(UIKit.stars(Game.stars_for(int(pot.get("potency", 4))), 2.0))
		if bool(pot.get("perfect", false)):
			ph.add_child(PaperKit.hand("· perfect stir", 30, PaperKit.HERB, true))
	var row := UIKit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var scores: Array = d.get("scores", [0, 0, 0])
	var lines: Array = d.get("lines", ["", "", ""])
	var star_rows := []
	for i in Events.JUDGES.size():
		var j: Dictionary = Events.JUDGES[i]
		var c := PaperKit.panel("card", Vector2(18, 12))
		c.custom_minimum_size = Vector2(340, 0)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cv := UIKit.vbox(4)
		c.add_child(cv)
		var top := UIKit.hbox(10)
		cv.add_child(top)
		var f := TextureRect.new()
		f.texture = _head(String(j["id"]))
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.custom_minimum_size = Vector2(76, 76)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(f)
		var nv := UIKit.vbox(0)
		top.add_child(nv)
		nv.add_child(PaperKit.head(String(j["name"]), 30, INK))
		nv.add_child(PaperKit.hand("guest judge" if j.get("guest", false) else "judge", 24, PaperKit.INK_SOFT))
		var sr := UIKit.hbox(2)
		sr.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_child(sr)
		for k in 5:
			var st := UIKit.icon("res://assets/icons/emote_star_empty.png", 2.4)
			sr.add_child(st)
		star_rows.append(sr)
		var bub := PaperKit.hand("“%s”" % String(lines[i]) if i < lines.size() else "", 27, INK, false, HORIZONTAL_ALIGNMENT_CENTER, 300)
		bub.modulate.a = 0.0
		bub.name = "Line"
		cv.add_child(bub)
		row.add_child(c)
	# los rivales en esta ronda y en total
	var tb := UIKit.hbox(30)
	tb.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tb)
	for r in d.get("table", []):
		var me: bool = bool(r.get("me", false))
		var cell := UIKit.vbox(0)
		cell.add_child(PaperKit.hand(String(r["name"]), 30, Color("7a1d18") if me else INK, true, HORIZONTAL_ALIGNMENT_CENTER))
		cell.add_child(PaperKit.hand("+%d  ·  %d ★" % [int(r["round"]), int(r["total"])], 28, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER))
		tb.add_child(cell)
	var fl := String(d.get("fizz_line", ""))
	if fl != "":
		v.add_child(PaperKit.hand("Fizz: “%s”" % fl, 28, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER))
	var b := PaperKit.wood_button("See results" if d.get("last", false) else "Next round", func():
		_close_modal()
		jury_closed.emit(), 32)
	b.custom_minimum_size = Vector2(320, 66)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.disabled = true
	v.add_child(b)
	PaperKit.decor(p, "paper_tape", Vector2(0.5, 0.0), Vector2(-36, -12), 3.0, false, Color.WHITE, -0.03)
	await _open_modal("jury", p)
	_modal_btn = b
	Glyphs.attach_chip(b, "confirm", "right", false, Vector2(16, 0))   # --- R6 UI: su tecla (Intro / A)
	# las estrellas de cada jurado, una a una
	for i in star_rows.size():
		await get_tree().create_timer(0.35).timeout
		if _modal_kind != "jury":
			return
		var sr: HBoxContainer = star_rows[i]
		var n := int(scores[i]) if i < scores.size() else 0
		for k in n:
			var st: TextureRect = sr.get_child(k)
			st.texture = load("res://assets/icons/emote_star.png")
			st.pivot_offset = st.size / 2.0
			st.scale = Vector2(1.5, 1.5)
			st.create_tween().tween_property(st, "scale", Vector2.ONE, 0.18)
			Sfx.play_pitched("rune_node", 0.9 + 0.08 * k, -8.0)
			await get_tree().create_timer(0.09).timeout
		var ln: Label = sr.get_parent().get_node_or_null("Line")
		if ln:
			ln.create_tween().tween_property(ln, "modulate:a", 1.0, 0.25)
	if _modal_kind == "jury":
		b.disabled = false

## La tarjeta de resultados. d: {"kind", "medal", "rows": [[icono, texto, valor]], "reward": Events.apply_result(),
## "title"}. Espera a «Volver a casa».
func show_results(d: Dictionary) -> void:
	var kind := String(d.get("kind", "academia"))
	var medal := String(d.get("medal", "none"))
	var p := PaperKit.panel("sheet", Vector2(64, 38))
	p.custom_minimum_size = Vector2(860, 0)
	var v := UIKit.vbox(8)
	p.add_child(v)
	var hd := UIKit.hbox(12)
	hd.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hd)
	var sl := PaperKit.pic(String(Events.info(kind)["seal"]), 2.5)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(sl)
	hd.add_child(PaperKit.head(Events.ev_name(kind, true), 38, INK))
	# la medalla, grande, con un brillo detrás
	var mh := Control.new()
	mh.custom_minimum_size = Vector2(0, 230)
	mh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mh)
	var glow := PaperKit.pic("res://assets/fx/glow.png", 9.0)
	glow.modulate = Color(Events.MEDAL_COLOR[medal], 0.0 if medal == "none" else 0.55)
	glow.set_anchors_preset(Control.PRESET_CENTER)
	mh.add_child(glow)
	var md := PaperKit.pic("evui_medal_%s" % medal, 6.5)
	md.set_anchors_preset(Control.PRESET_CENTER)
	mh.add_child(md)
	mh.resized.connect(func():
		glow.size = glow.custom_minimum_size
		glow.position = mh.size / 2.0 - glow.size / 2.0
		md.size = md.custom_minimum_size
		md.position = mh.size / 2.0 - md.size / 2.0)
	var title := PaperKit.hand(String(Events.MEDAL_TITLE[medal]), 58, Color("7a1d18") if medal == "none" else Color("5b3a8c"), true, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	if String(d.get("line", "")) != "":
		v.add_child(PaperKit.hand("“%s”" % String(d["line"]), 30, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, 720))
	v.add_child(PaperKit.ink_rule(620, Color(0.37, 0.28, 0.2, 0.35)))
	for r in d.get("rows", []):
		v.add_child(_result_row(String(r[0]), String(r[1]), String(r[2])))
	# lo que trae (iconos y números, en una tira de madera)
	var rw: Dictionary = d.get("reward", {})
	var strip := PaperKit.panel("wood", Vector2(30, 8))
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(strip)
	var rt := UIKit.rich(36)
	rt.fit_content = true
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.add_theme_font_override("normal_font", UIKit.font_bold)
	rt.text = "[center]%s[/center]" % reward_bb(rw)
	strip.add_child(rt)
	var b := PaperKit.wood_button("Head home", func():
		_close_modal()
		results_closed.emit(), 34)
	b.custom_minimum_size = Vector2(340, 70)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	PaperKit.decor(p, "paper_pin_brass", Vector2(0.5, 0.0), Vector2(-10, -12))
	Sfx.play("levelup" if medal != "none" else "sad", 0.0, -2.0)
	await _open_modal("results", p, 0.6)
	_modal_btn = b
	Glyphs.attach_chip(b, "confirm", "right", false, Vector2(16, 0))   # --- R6 UI: su tecla (Intro / A)
	if medal != "none":
		md.pivot_offset = md.size / 2.0
		md.scale = Vector2(0.2, 0.2)
		md.rotation = -0.5
		var tw := md.create_tween().set_parallel(true)
		tw.tween_property(md, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(md, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _result_row(icon: String, label: String, value: String) -> Control:
	var h := UIKit.hbox(12)
	h.custom_minimum_size = Vector2(560, 50)
	h.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if icon != "":
		var ic := PaperKit.pic(icon, 3.0) if not icon.begins_with("res://assets/icons/") else UIKit.icon(icon, 2.2)
		ic.custom_minimum_size = Vector2(44, 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := PaperKit.hand(label, 32, PaperKit.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var vl := PaperKit.hand(value, 36, INK, true, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(vl)
	return h

## Lo que dio el evento en una línea de iconos (la tarjeta de resultados; el estilo de Story.reward_line).
static func reward_bb(rw: Dictionary) -> String:
	var bits: Array = []
	var coin := "[img=40]res://assets/icons/emote_coin.png[/img]"
	var gem := "[img=40]res://assets/icons/emote_gem.png[/img]"
	var g := int(rw.get("gold", 0)) + int(rw.get("tips", 0))
	if g > 0:
		bits.append("%s [color=#ffd987]+%d[/color]" % [coin, g])
	var r := int(rw.get("renombre", 0))
	if r > 0:
		bits.append("%s [color=#d9c8ff]+%d[/color]" % [gem, r])
	elif r < 0:
		bits.append("%s [color=#ff9b9b]%d[/color]" % [gem, r])
	if bool(rw.get("trophy", false)):
		bits.append("[img=40]res://assets/ui/evui_trophy.png[/img] [color=#f2e2bc]Trophy[/color]")
	for it in rw.get("items", []):
		var id := String(it["id"])
		bits.append("[img=40]res://assets/icons/ing_%s.png[/img] [color=#9eea9f]+%d[/color]" % [id, int(it["qty"])])
	var page := String(rw.get("page", ""))
	if page != "":
		var ic := "res://assets/icons/rune_%s.png" % page
		bits.append("%s [color=#c9b6ff]%s[/color]" % ["[img=40]%s[/img]" % ic if ResourceLoader.exists(ic) else "", Story.rune_name(page)])
	var pts := int(rw.get("points", 0))
	if pts > 0:
		bits.append("[color=#f2e2bc]Guild +%d[/color]" % pts)
	elif pts < 0:
		bits.append("[color=#ff9b9b]Guild %d[/color]" % pts)
	if bits.is_empty():
		bits.append("[color=#c8b9a4]Nothing this time.[/color]")
	return "    ".join(bits)

# ------------------------------------------------------------------ recordatorio (días de tienda)

## El evento aceptado, en una etiqueta bajo el HUD («Día 4 · Academia»). Se esconde si no hay o durante el evento.
func refresh_reminder(on := true) -> void:
	var bk: Dictionary = Game.ev_booked
	reminder.visible = on and not bk.is_empty()
	_reminder_want = reminder.visible   # --- R4 MERGE
	if reminder.visible:
		var kind := String(bk.get("kind", "academia"))
		reminder_seal.texture = PaperKit.tex(String(Events.info(kind)["seal"]))
		var d := int(bk.get("day", 0)) - Game.day
		var when := "today" if d <= 0 else ("tomorrow" if d == 1 else "Day %d" % int(bk["day"]))
		reminder_txt.text = "%s: %s" % [when.capitalize(), Events.ev_name(kind)]
		reminder.tooltip_text = Events.ev_name(kind, true)
		await _fit(reminder)

# --- R4 MERGE: la etiqueta va justo debajo de la placa del HUD (con el reloj y la gente de PACE la placa es más alta y
# la tapaba) y no se ve sobre las pantallas de trabajo (la bola de Krápido, el banco del caldero): allí estorbaría.
var _reminder_want := false

func _process(_d: float) -> void:
	if reminder == null or main == null:
		return
	var busy: bool = (main.has_method("_ball_open") and main._ball_open()) or (main.has_method("_brew_open") and main._brew_open())
	reminder.visible = _reminder_want and not busy
	if not reminder.visible:
		return
	var hp: Control = main.ui.hud_panel if main.ui else null
	if hp and hp.is_visible_in_tree():
		var y := maxf(160.0, hp.get_global_rect().end.y + 12.0)
		if absf(reminder.global_position.y - y) > 0.5:
			reminder.global_position.y = y
# --- end R4 MERGE

# ------------------------------------------------------------------ el viaje

## El mapa de Arvendal: el carro va de su tienda al lugar del evento (o vuelve: back). Fundido de entrada y salida.
func travel(kind: String, back := false, dur := 2.8) -> void:
	_map_bg = ColorRect.new()
	_map_bg.color = Color(0.05, 0.035, 0.03, 1.0)
	_map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	map_layer.add_child(_map_bg)
	_map = _MapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var route: Array = MAP_ROUTES.get(kind, MAP_ROUTES["academia"]).duplicate()
	if back:
		route.reverse()
	_map.route = route
	_map.dest = kind
	_map.title = Events.ev_name(kind)
	_map_bg.add_child(_map)
	_map_bg.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_map_bg, "modulate:a", 1.0, 0.35)
	await tw.finished
	Sfx.play("page", 0.05, -3.0)
	var t := 0.0
	var step_cd := 0.0
	while t < dur:
		var d := get_process_delta_time()
		t += d
		step_cd -= d
		if step_cd <= 0.0:
			step_cd = 0.34
			Sfx.step()
		_map.progress = clampf(t / dur, 0.0, 1.0)
		_map.queue_redraw()
		await get_tree().process_frame
	_map.progress = 1.0
	_map.queue_redraw()
	await get_tree().create_timer(0.5).timeout

## Quita el mapa (después de que main.gd fundió a negro).
func end_travel() -> void:
	if is_instance_valid(_map_bg):
		_map_bg.queue_free()
	_map_bg = null
	_map = null

## El mapa a medio camino (para la captura --demo=event_map).
func show_map_still(kind: String, progress := 0.55) -> void:
	await travel(kind, false, 0.01)
	_map.progress = progress
	_map.queue_redraw()

# ================================================================== dibujo: el mapa

class _MapView extends Control:
	var route: Array = []
	var dest := "academia"
	var title := ""
	var progress := 0.0
	var _tex: Texture2D = load("res://assets/ui/evui_map.png")
	var _cart: Texture2D = load("res://assets/props/cart.png")
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta

	## Un fondo de pergamino claro detrás de un nombre (se lee sobre los árboles y los caminos).
	func _halo(pos: Vector2, w: float, fs: int) -> void:
		draw_rect(Rect2(pos + Vector2(-8, -fs * 0.78), Vector2(w + 16, fs * 1.02)), Color(0.95, 0.9, 0.77, 0.82))

	func _length() -> float:
		var l := 0.0
		for i in route.size() - 1:
			l += (route[i + 1] as Vector2).distance_to(route[i])
		return l

	func _point_at(d: float) -> Array:
		var acc := 0.0
		for i in route.size() - 1:
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var seg := a.distance_to(b)
			if acc + seg >= d:
				return [a.lerp(b, (d - acc) / maxf(0.001, seg)), b - a]
			acc += seg
		var n := route.size()
		return [route[n - 1], (route[n - 1] as Vector2) - (route[n - 2] as Vector2)]

	func _draw() -> void:
		if _tex == null or route.size() < 2:
			return
		var k := maxf(1.0, floorf(minf(size.x / EventUI.MAP_ART.x, size.y / EventUI.MAP_ART.y)))
		var off := ((size - EventUI.MAP_ART * k) / 2.0).floor()
		draw_texture_rect(_tex, Rect2(off, EventUI.MAP_ART * k), false)
		var font: Font = PaperKit.font_hand_bold
		var ink := Color("3a2618")
		# los nombres de los lugares
		for id in EventUI.MAP_PLACES:
			var p: Vector2 = off + EventUI.MAP_PLACES[id] * k
			var txt: String = EventUI.PLACE_LABEL[id]
			var fs := 44 if id == dest or id == "casa" else 34
			var col := Color("7a1d18") if id == dest else ink
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := p + Vector2(-w / 2.0, 14.0 * k / 6.0 + 38)
			if id == "academia":
				pos = p + Vector2(-w - 24, 10)
			_halo(pos, w, fs)
			draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			TextLog.note("map", txt)   # --- R5 MERGE: el registro de textos de prueba (solo con --textlog)
		# Montaña Gris y el título del mapa
		var mg := off + Vector2(36, 18) * k
		_halo(mg, font.get_string_size("Grey Mountain", HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x, 36)
		draw_string(font, mg, "Grey Mountain", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(ink, 0.85))
		TextLog.note("map", "Grey Mountain")   # --- R5 MERGE
		var tf: Font = UIKit.font_sc_bold
		var tt := "Arvendal"
		var tw := tf.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		draw_string(tf, off + Vector2(EventUI.MAP_ART.x * k - tw - 40 * k / 6.0 - 60, EventUI.MAP_ART.y * k - 46), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(ink, 0.85))
		TextLog.note("map", tt)   # --- R5 MERGE
		if title != "":
			var sw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
			var sp := Vector2(size.x / 2.0 - sw / 2.0, off.y + 20 * k)
			var cr := Rect2(sp + Vector2(-28, -50), Vector2(sw + 56, 68))
			draw_rect(cr, Color(0.95, 0.9, 0.78, 0.95))
			draw_rect(cr, Color("7a1d18"), false, 3.0)
			draw_rect(cr.grow(-6), Color(0.48, 0.11, 0.09, 0.5), false, 1.0)
			draw_string(font, sp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color("7a1d18"))
			TextLog.note("map", title)   # --- R5 MERGE
		# el camino recorrido: puntos de tinta
		var total := _length()
		var done := total * progress
		var d := 0.0
		while d <= done:
			var pa: Array = _point_at(d)
			var q: Vector2 = off + ((pa[0] as Vector2) * k).floor()
			draw_rect(Rect2(q - Vector2(k * 0.75, k * 0.75), Vector2(k * 1.5, k * 1.5)), Color("7a1d18"))
			d += 4.5
		# una cruz en el destino
		var dp: Vector2 = off + (route[route.size() - 1] as Vector2) * k
		draw_line(dp + Vector2(-12, -12), dp + Vector2(12, 12), Color("a3261f"), 5.0)
		draw_line(dp + Vector2(12, -12), dp + Vector2(-12, 12), Color("a3261f"), 5.0)
		# el carro
		var cp: Array = _point_at(done)
		var c: Vector2 = off + (cp[0] as Vector2) * k
		var dir: Vector2 = cp[1]
		if _cart:
			var cs := Vector2(_cart.get_width(), _cart.get_height()) * k * 0.3
			var bob := absf(sin(_t * 11.0)) * 3.0 if progress < 1.0 else 0.0
			var r := Rect2(c - Vector2(cs.x / 2.0, cs.y - 6.0 + bob), cs)
			if dir.x < 0.0:
				draw_texture_rect(_cart, Rect2(r.position + Vector2(r.size.x, 0), Vector2(-r.size.x, r.size.y)), false)
			else:
				draw_texture_rect(_cart, r, false)

# ================================================================== dibujo: la barra de puntos

class _ScoreBar extends Control:
	var score := 0
	var cuts := {}
	var _ticks := {}

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for m in ["bronze", "silver", "gold"]:
			_ticks[m] = PaperKit.tex("evui_tick_%s" % m)

	func _draw() -> void:
		if cuts.is_empty():
			return
		var mx := maxf(1.0, float(cuts.get("max", 1)))
		var r := Rect2(Vector2(14, 30), Vector2(size.x - 28, 16))
		draw_rect(r.grow(4), Color(0.16, 0.1, 0.07, 0.92))
		draw_rect(r, Color(0.92, 0.86, 0.72))
		var f := clampf(float(score) / mx, 0.0, 1.0)
		var medal := Events.medal_for(score, cuts)
		var col: Color = Events.MEDAL_COLOR.get(medal, Color("8f8698")) if medal != "none" else Color("9a8a74")
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), col)
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, 4)), col.lightened(0.35))
		for m in ["bronze", "silver", "gold"]:
			var x := r.position.x + r.size.x * clampf(float(cuts.get(m, 0)) / mx, 0.0, 1.0)
			draw_rect(Rect2(Vector2(x - 1.5, r.position.y - 3), Vector2(3, r.size.y + 6)), Color(0.16, 0.1, 0.07))
			var t: Texture2D = _ticks.get(m)
			if t:
				var s := t.get_size() * 3.0
				var reached := score >= int(cuts.get(m, 0))
				draw_texture_rect(t, Rect2(Vector2(x - s.x / 2.0, -4), s), false, Color.WHITE if reached else Color(0.5, 0.47, 0.46, 0.9))
