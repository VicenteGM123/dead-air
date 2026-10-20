extends CanvasLayer
class_name Overlays
## Pantallas grandes: título, libro de recetas, diario, mercado, resumen del día, ajustes, subida de nivel y minijuego de remover.
## --- R3 PAPER: el recetario, el diario, el correo, el mercado y los paneles del día son papel de verdad (hojas de
## pergamino, madera, corcho, mantel, chinchetas, sellos y letra manuscrita: scripts/ui/paper_kit.gd), con iconos y
## números en vez de frases. El recetario y el diario se hojean: las esquinas de las hojas, las pestañas, ← → (o A D,
## RePág AvPág), la rueda del ratón y LT / RT en el mando.

signal closed(id: String)
signal new_game
signal continue_game
signal open_shop
signal sleep
signal stir_done(perfect: bool)
signal to_title
signal invite_answered(accept: bool)   # --- R4 EVENTS: la invitación a un evento (Aceptar / Rechazar)

var root: Control
var current := ""
var current_node: Control
var _book_sel := ""
var _market_tab := 0
var _market_mode := "day"   # "morning" o "day"
var _market_vendor := ""    # --- WORLD: puesto del mercado cuyo panel está abierto ("" = el panel completo)
var pad_hint := ""          # controles del mando ("" = ratón y teclado); lo pone PadCursor
var _hint_label: Label

const MOUSE_HINT := "Clic: todo   ·   Espacio: avanzar"   # --- R3 PAPER: más corto

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	PaperKit.load_fonts()   # --- R3 PAPER

func is_open() -> bool:
	return current != ""

func close(emit := true) -> void:
	var id := current
	if current_node:
		current_node.queue_free()
	current_node = null
	current = ""
	_flipping = false   # --- R3 PAPER: una hoja a medio pasar no bloquea la próxima vez
	if emit and id != "":
		closed.emit(id)

func _open(id: String, panel: Control, dim := true) -> Control:
	close(false)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	if dim:
		holder.add_child(UIKit.dim_overlay())
	holder.add_child(UIKit.center(panel))
	current = id
	current_node = holder
	await get_tree().process_frame
	if is_instance_valid(panel):
		UIKit.pop_in(panel)
	return holder

func _unhandled_input(ev: InputEvent) -> void:
	if current == "" or current == "title" or current == "stir" or current == "summary" or current == "levelup":
		return
	if current == "invite":   # --- R4 EVENTS: la invitación se acepta o se rechaza (Esc / B no la cierran)
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if current == "confirm":
			show_title(true)
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	# --- R4 RANK: la Gaceta y los créditos también se cierran con Espacio o Intro (como su botón)
	if (current == "gaceta" or current == "credits") and ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER):
		close()
		get_viewport().set_input_as_handled()
		return
	# --- end R4 RANK
	# --- R3 PAPER: pasar la hoja con el teclado
	if (current == "book" or current == "journal") and ev is InputEventKey and ev.pressed and not ev.echo:
		var dir := 0
		match ev.keycode:
			KEY_LEFT, KEY_A, KEY_PAGEUP:
				dir = -1
			KEY_RIGHT, KEY_D, KEY_PAGEDOWN:
				dir = 1
		if dir != 0:
			_turn(dir)
			get_viewport().set_input_as_handled()
	# --- end R3 PAPER

# --- R3 PAPER: gatillos del mando (LT / RT) para pasar la hoja; PadCursor no los usa
var _trig_prev := 0

func _process(_delta: float) -> void:
	if current != "book" and current != "journal":
		_trig_prev = 0
		return
	var t := 0
	for d in Input.get_connected_joypads():
		if Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.6:
			t = 1
		elif Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.6:
			t = -1
	if t != 0 and t != _trig_prev:
		_turn(t)
	_trig_prev = t
# --- end R3 PAPER

func _title_row(text: String, size := 40) -> Label:
	return UIKit.shadow(UIKit.label(text, size, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER), 3)

func _close_button(text := "Cerrar") -> Button:
	var b := PaperKit.button(text, func(): close(), 32)   # --- R3 PAPER
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

# ------------------------------------------------------------------ título

func show_title(has_save: bool) -> void:
	close(false)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.01, 0.05, 0.88))
	g.set_color(1, Color(0.02, 0.01, 0.05, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.75, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(grad)
	# --- R3 PAPER: emblema, título, una línea a mano y botones de madera
	var v := UIKit.vbox(0)
	UIKit.place(v, Vector2(0, 0.5), Vector2(130, -400), Vector2(720, 800))
	holder.add_child(v)
	var em := PaperKit.pic("paper_emblem", 5.0)
	em.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(em)
	v.add_child(PaperKit.gap(6))
	var t := UIKit.shadow(UIKit.label("Caldero", 120, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold), 4)
	t.custom_minimum_size = Vector2(0, 118)
	v.add_child(t)
	var t2 := UIKit.shadow(UIKit.label("Nocturno", 120, Color(0.82, 0.78, 1.0), UIKit.font_sc_bold), 4)
	t2.custom_minimum_size = Vector2(0, 118)
	v.add_child(t2)
	var tag := UIKit.shadow(PaperKit.hand("una tiendita de pociones", 44, Color("eadbb8")), 3)
	v.add_child(tag)
	v.add_child(PaperKit.gap(34))
	var btns := UIKit.vbox(14)
	v.add_child(btns)
	if has_save:
		var c := PaperKit.wood_button("Continuar", func(): close(false); continue_game.emit(), 36)
		c.custom_minimum_size = Vector2(360, 74)
		c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btns.add_child(c)
	var n := PaperKit.wood_button("Nueva partida" if has_save else "Empezar", func(): _confirm_new(has_save), 36)
	n.custom_minimum_size = Vector2(360, 74)
	n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btns.add_child(n)
	var q := PaperKit.wood_button("Salir", func(): get_tree().quit(), 30)
	q.custom_minimum_size = Vector2(360, 62)
	q.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btns.add_child(q)
	var credit := UIKit.label(pad_hint if pad_hint != "" else MOUSE_HINT, 18, UIKit.MUTED, UIKit.font_italic)
	UIKit.place(credit, Vector2(0, 1), Vector2(130, -58), Vector2(1400, 30))
	holder.add_child(credit)
	# --- end R3 PAPER
	_hint_label = credit
	current = "title"
	current_node = holder
	holder.modulate.a = 0.0
	var tw := holder.create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 1.2)

## Textos de controles: los del mando cuando hay uno conectado o en uso (ver pad_cursor.gd).
func set_pad_hint(text: String) -> void:
	pad_hint = text
	if is_instance_valid(_hint_label):
		_hint_label.text = text if text != "" else MOUSE_HINT

func _confirm_new(has_save: bool) -> void:
	if not has_save:
		close(false)
		new_game.emit()
		return
	# --- R3 PAPER: una tarjeta clavada, sin explicaciones
	var p := PaperKit.panel("card", Vector2(60, 36))
	var v := UIKit.vbox(18)
	p.add_child(v)
	v.add_child(PaperKit.head("¿Empezar de nuevo?", 42, PaperKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(PaperKit.hand("Se borra la partida guardada.", 34, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER))
	var h := UIKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(PaperKit.button("Sí, borrar", func(): close(false); new_game.emit(), 34))
	h.add_child(PaperKit.button("Volver", func(): show_title(true), 34))
	PaperKit.decor(p, "paper_pin_red", Vector2(0.5, 0.0), Vector2(-10, -14))
	# --- end R3 PAPER
	_open("confirm", p)

# --- R3 PAPER: hojas sueltas que se hojean (el recetario y el diario) ---------------------------------------------

const SHEET := Vector2(580, 760)    # paper_sheet_a / _b / _c (pixel art a x2)
const SHEET_GAP := 26.0
const SHEET_PAD := Vector4(52, 46, 52, 50)   # izquierda, arriba, derecha, abajo: el borde quemado de la hoja
var _pages: Array = []      # cada hoja doble: {"l": Callable(VBoxContainer), "r": Callable(VBoxContainer), "tab": int}
var _page := 0
var _book_page := 0
var _journal_page := 0
var _sheet_l: Control
var _sheet_r: Control
var _spread: Control
var _fold_prev: TextureButton
var _fold_next: TextureButton
var _tab_btns: Array = []   # [Button, página]
var _dot_btns: Array = []   # [Button, página]
var _flipping := false

## El escritorio (madera o corcho) con dos hojas, pestañas arriba, esquinas para pasar la hoja y puntos de página.
func _paper_desk(kind: String, tabs: Array, tab_pages: Array) -> Control:
	var desk := PaperKit.panel(kind, Vector2(30, 22))
	var v := UIKit.vbox(6)
	desk.add_child(v)
	var top := UIKit.hbox(10)
	v.add_child(top)
	top.add_child(PaperKit.gap(0, 8))
	_tab_btns = []
	for i in tabs.size():
		var pg: int = tab_pages[i]
		var tb := PaperKit.button(tabs[i], func(): _go_page(pg), 32, "tab")
		tb.custom_minimum_size = Vector2(190, 52)
		top.add_child(tb)
		_tab_btns.append([tb, pg])
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var cb := PaperKit.button("Cerrar", func(): close(), 30)
	cb.custom_minimum_size = Vector2(0, 52)
	top.add_child(cb)
	_spread = Control.new()
	_spread.custom_minimum_size = Vector2(SHEET.x * 2.0 + SHEET_GAP, SHEET.y)
	_spread.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_spread)
	_sheet_l = _make_sheet("paper_sheet_a", Vector2(0, 0), kind)
	_sheet_r = _make_sheet("paper_sheet_b", Vector2(SHEET.x + SHEET_GAP, 0), kind)
	_fold_prev = PaperKit.image_button("paper_fold_prev", "paper_fold_prev_hover", func(): _turn(-1), 3.0, "Anterior")
	_fold_prev.position = Vector2(12, SHEET.y - 14 - 54)
	_spread.add_child(_fold_prev)
	_fold_next = PaperKit.image_button("paper_fold_next", "paper_fold_next_hover", func(): _turn(1), 3.0, "Siguiente")
	_fold_next.position = Vector2(SHEET.x * 2.0 + SHEET_GAP - 12 - 54, SHEET.y - 14 - 54)
	_spread.add_child(_fold_next)
	var dots := UIKit.hbox(10)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(dots)
	_dot_btns = []
	for i in _pages.size():
		var pg2 := i
		var d := PaperKit.button(str(i + 1), func(): _go_page(pg2), 26, "tag")
		d.custom_minimum_size = Vector2(64, 40)
		dots.add_child(d)
		_dot_btns.append([d, i])
	# la rueda del ratón también pasa la hoja
	desk.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_turn(1)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				_turn(-1))
	return desk

## Una hoja: la textura de pergamino, sujeta con cinta (madera) o chinchetas (corcho), y un margen para el contenido.
func _make_sheet(texname: String, pos: Vector2, kind: String) -> Control:
	var s := Control.new()
	s.position = pos
	s.size = SHEET
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	_spread.add_child(s)
	var bg := PaperKit.pic(texname, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(SHEET_PAD.x))
	m.add_theme_constant_override("margin_top", int(SHEET_PAD.y))
	m.add_theme_constant_override("margin_right", int(SHEET_PAD.z))
	m.add_theme_constant_override("margin_bottom", int(SHEET_PAD.w))
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	s.add_child(m)
	s.set_meta("content", m)
	if kind == "cork":
		PaperKit.decor(s, "paper_pin_red" if pos.x == 0 else "paper_pin_blue", Vector2(0, 0), Vector2(30, 6))
		PaperKit.decor(s, "paper_pin_green" if pos.x == 0 else "paper_pin_brass", Vector2(1, 0), Vector2(-52, 6))
	else:
		PaperKit.decor(s, "paper_tape", Vector2(0, 0), Vector2(-14, 8), 3.0, false, Color.WHITE, -0.5)
		PaperKit.decor(s, "paper_tape", Vector2(1, 0), Vector2(-58, -10), 3.0, false, Color.WHITE, 0.5)
	return s

func _fill_sheet(sheet: Control, builder: Callable) -> void:
	if not is_instance_valid(sheet):
		return
	var m: MarginContainer = sheet.get_meta("content")
	for c in m.get_children():
		m.remove_child(c)
		c.queue_free()
	var v := UIKit.vbox(6)
	m.add_child(v)
	builder.call(v)

func _fill_spread() -> void:
	if _pages.is_empty():
		return
	var pg: Dictionary = _pages[_page]
	_fill_sheet(_sheet_l, pg["l"])
	_fill_sheet(_sheet_r, pg["r"])
	_update_nav()

func _update_nav() -> void:
	if _pages.is_empty():
		return
	var tab: int = _pages[_page].get("tab", -1)
	for t in _tab_btns:
		if is_instance_valid(t[0]):
			t[0].modulate = Color.WHITE if t[1] == tab else Color(0.8, 0.76, 0.7)
	for d in _dot_btns:
		if is_instance_valid(d[0]):
			d[0].modulate = Color.WHITE if d[1] == _page else Color(0.78, 0.74, 0.68)
			d[0].add_theme_color_override("font_color", PaperKit.RED_INK if d[1] == _page else PaperKit.INK)
	if is_instance_valid(_fold_prev):
		_fold_prev.visible = _page > 0
	if is_instance_valid(_fold_next):
		_fold_next.visible = _page < _pages.size() - 1

func _turn(dir: int) -> void:
	if _pages.is_empty() or (current != "book" and current != "journal"):
		return
	_go_page(_page + dir)

func _go_page(to: int) -> void:
	if _flipping or to == _page or to < 0 or to >= _pages.size() or not is_instance_valid(_spread):
		return
	var dir := 1 if to > _page else -1
	_page = to
	if current == "book":
		_book_page = to
	elif current == "journal":
		_journal_page = to
	Sfx.play("page", 0.08, -4.0)
	_flip(dir)

## Pasar la hoja: la hoja se levanta desde un lado, cruza el lomo y cae del otro (dos medias vueltas).
func _flip(dir: int) -> void:
	_flipping = true
	var pg: Dictionary = _pages[_page]
	var src := _sheet_r if dir > 0 else _sheet_l
	var dst := _sheet_l if dir > 0 else _sheet_r
	_fill_sheet(src, pg["r"] if dir > 0 else pg["l"])
	_update_nav()
	var g1 := _ghost(src, dir > 0)
	var tw := g1.create_tween()
	tw.tween_property(g1, "scale:x", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(g1, "modulate", Color(0.78, 0.74, 0.68), 0.15)
	await tw.finished
	g1.queue_free()
	if not is_instance_valid(dst):
		_flipping = false
		return
	var g2 := _ghost(dst, dir < 0)
	g2.scale.x = 0.0
	g2.modulate = Color(0.78, 0.74, 0.68)
	var tw2 := g2.create_tween()
	tw2.tween_property(g2, "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(g2, "modulate", Color.WHITE, 0.15)
	await tw2.finished
	_fill_sheet(dst, pg["l"] if dir > 0 else pg["r"])
	var tw3 := g2.create_tween()
	tw3.tween_property(g2, "modulate:a", 0.0, 0.1)
	await tw3.finished
	g2.queue_free()
	_flipping = false

func _ghost(sheet: Control, pivot_left: bool) -> TextureRect:
	var g := PaperKit.pic("paper_sheet_c", 1.0)
	g.position = sheet.position
	g.size = SHEET
	g.pivot_offset = Vector2(0.0 if pivot_left else SHEET.x, SHEET.y / 2.0)
	_spread.add_child(g)
	return g

# ------------------------------------------------------------------ libro de recetas

func show_book() -> void:
	Sfx.play("page", 0.05, -4.0)
	_flipping = false
	_pages = [
		{"l": func(v): _book_potions(v, 0), "r": func(v): _book_potions(v, 1), "tab": 0},
		{"l": func(v): _book_ingredients(v, 0), "r": func(v): _book_ingredients(v, 1), "tab": 1},
	]
	_page = clampi(_book_page, 0, _pages.size() - 1)
	var desk := _paper_desk("wood", ["Pociones", "Ingredientes"], [0, 1])
	_fill_spread()
	_open("book", desk)

## Cinco pociones por hoja: boceto, nombre, para qué sirve, sus dos esencias, la mejor preparación y el precio.
func _book_potions(v: VBoxContainer, half: int) -> void:
	v.add_theme_constant_override("separation", 2)
	if half == 0:
		v.add_child(PaperKit.head("Pociones", 40))
	else:
		v.add_child(_rule_note())   # la regla de las esencias, arriba de la segunda hoja
	var brewable := Game.brewable_potions()
	var ids: Array = Data.POTION_ORDER.slice(half * 5, half * 5 + 5)
	for i in ids.size():
		v.add_child(_potion_row(ids[i], brewable.has(ids[i])))
		if i < ids.size() - 1:
			v.add_child(PaperKit.ink_rule(440, Color(0.37, 0.28, 0.2, 0.25)))

func _potion_row(pid: String, can_brew: bool) -> Control:
	var known := Game.discovered.has(pid)
	var d: Dictionary = Data.POTIONS[pid]
	var row := UIKit.hbox(10)
	row.custom_minimum_size = Vector2(476, 0)
	var sk := PaperKit.sketch("pot", pid if known else "desconocida", 3.0)
	sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not known:
		sk.modulate = Color(1, 1, 1, 0.6)
	row.add_child(sk)
	var mid := UIKit.vbox(-8)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mid)
	var nm := UIKit.hbox(6)
	mid.add_child(nm)
	nm.add_child(PaperKit.hand(String(d["name"]), 35, PaperKit.INK if known else PaperKit.INK_FAINT, true))
	if not can_brew:
		var lk := PaperKit.pic("paper_i_lock", 3.0)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lk.tooltip_text = "Faltan ingredientes en el mercado"
		lk.mouse_filter = Control.MOUSE_FILTER_PASS
		nm.add_child(lk)
	var ef := PaperKit.hand(String(d["effect"]), 25, PaperKit.INK_SOFT if known else PaperKit.INK_FAINT, false, HORIZONTAL_ALIGNMENT_LEFT, 226)
	ef.add_theme_constant_override("line_spacing", -7)
	mid.add_child(ef)
	var right := UIKit.vbox(6)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	var es := UIKit.hbox(4)
	es.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(es)
	if known:
		es.add_child(PaperKit.ess_icon(d["pair"][0], 4.0))
		es.add_child(PaperKit.hand("+", 34, PaperKit.INK_SOFT, true))
		es.add_child(PaperKit.ess_icon(d["pair"][1], 4.0))
	else:
		es.add_child(PaperKit.hand("? + ?", 34, PaperKit.INK_FAINT, true))
	var br := UIKit.hbox(8)
	br.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(br)
	var best := int(Game.discovered.get(pid, 0))
	if best > 0:
		var st := UIKit.stars(Game.stars_for(best), 1.5)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		br.add_child(st)
	br.add_child(PaperKit.coins(int(d["base"]), 30, PaperKit.INK if known else PaperKit.INK_FAINT, 2.0))
	return row

## La regla de las esencias en una nota amarilla: mandan las dos más fuertes; si empatan, este orden.
func _rule_note() -> Control:
	var n := PaperKit.panel("note", Vector2(30, 8))
	n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(0)
	n.add_child(v)
	var l1 := UIKit.hbox(6)
	l1.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(l1)
	l1.add_child(PaperKit.hand("Mandan las 2 esencias más fuertes", 28, PaperKit.INK, true))
	var l2 := UIKit.hbox(4)
	l2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(l2)
	l2.add_child(PaperKit.hand("Si empatan:", 26, PaperKit.INK_SOFT))
	for i in Data.ESSENCE_ORDER.size():
		var ic := PaperKit.ess_icon(Data.ESSENCE_ORDER[i], 3.0)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l2.add_child(ic)
		if i < Data.ESSENCE_ORDER.size() - 1:
			l2.add_child(PaperKit.hand("›", 30, PaperKit.INK_SOFT, true))
	PaperKit.decor(n, "paper_tape", Vector2(0.0, 0.0), Vector2(-22, 4), 3.0, false, Color.WHITE, -0.55)
	return n

## Cuatro ingredientes por hoja: boceto, nombre y sus esencias (iconos repetidos: 2 de vida = dos hojas).
func _book_ingredients(v: VBoxContainer, half: int) -> void:
	v.add_child(PaperKit.head("Ingredientes" if half == 0 else "", 40))
	var ids: Array = Data.INGREDIENT_ORDER.slice(half * 4, half * 4 + 4)
	for i in ids.size():
		v.add_child(_ingredient_row(ids[i]))
		if i < ids.size() - 1:
			v.add_child(PaperKit.ink_rule(440, Color(0.37, 0.28, 0.2, 0.25)))

func _ingredient_row(id: String) -> Control:
	var d: Dictionary = Data.INGREDIENTS[id]
	var unlocked := Game.ingredient_unlocked(id)
	var row := UIKit.hbox(14)
	row.custom_minimum_size = Vector2(476, 128)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if unlocked:
		row.tooltip_text = String(d.get("desc", ""))
	var sk := PaperKit.sketch("ing", id, 3.0)
	sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not unlocked:
		sk.modulate = Color(0.35, 0.28, 0.22, 0.45)
	row.add_child(sk)
	var mid := UIKit.vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mid)
	mid.add_child(PaperKit.hand(String(d["name"]) if unlocked else "???", 40, PaperKit.INK if unlocked else PaperKit.INK_FAINT, true))
	if unlocked:
		mid.add_child(PaperKit.ess_row(d["ess"], 4.0, 4))
	else:
		var lk := UIKit.hbox(8)
		mid.add_child(lk)
		var li := PaperKit.pic("paper_i_lock", 3.0)
		li.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lk.add_child(li)
		var gm := UIKit.icon("res://assets/icons/emote_gem.png", 2.0)
		gm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lk.add_child(gm)
		lk.add_child(PaperKit.hand(Game.level_name(int(d["level"])), 30, PaperKit.INK_FAINT, true))
	return row

# ------------------------------------------------------------------ diario

func show_journal() -> void:
	Sfx.play("page", 0.05, -4.0)
	_flipping = false
	_pages = []
	var heroes: Array = Data.HERO_ORDER
	for i in range(0, heroes.size(), 2):
		var a: String = heroes[i]
		var b: String = heroes[i + 1] if i + 1 < heroes.size() else ""
		_pages.append({"l": func(v): _journal_hero(v, a), "r": func(v): _journal_hero(v, b), "tab": -1})
	_pages.append({"l": func(v): _journal_pending(v), "r": func(v): _journal_stats(v), "tab": -1})
	_page = clampi(_journal_page, 0, _pages.size() - 1)
	var desk := _paper_desk("cork", [], [])
	_fill_spread()
	_open("journal", desk)

## La hoja de un aventurero: su retrato clavado, nombre, capítulos (estrellas) y lo que pasó, día a día.
func _journal_hero(v: VBoxContainer, hid: String) -> void:
	if hid == "" or not Data.CHARACTERS.has(hid):
		return
	var ch: Dictionary = Data.CHARACTERS[hid]
	var done: int = int(Game.hero_progress.get(hid, 0))
	var known: bool = done > 0 or bool(Game.met.get(hid, false))
	var top := UIKit.hbox(18)
	v.add_child(top)
	var card := PaperKit.pinned_portrait(Story.sprite_id(hid), 2.0, "paper_pin_red", not known)
	top.add_child(card)
	var info := UIKit.vbox(2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(PaperKit.head(String(ch["name"]) if known else "¿?", 44, PaperKit.INK if known else PaperKit.INK_FAINT))
	if known:
		info.add_child(PaperKit.hand(String(ch["title"]), 32, PaperKit.INK_SOFT))
	var st := UIKit.stars(done, 2.0)
	info.add_child(st)
	if done >= 3:
		var sl := PaperKit.seal(String(ch["name"]).left(1), "paper_seal_gold", 3.0)
		sl.tooltip_text = "Historia completa"
		info.add_child(sl)
	v.add_child(PaperKit.gap(6))
	v.add_child(PaperKit.ink_rule(460, Color(0.37, 0.28, 0.2, 0.3)))
	for e in Game.journal:
		if e["hero"] == hid:
			var row := UIKit.hbox(10)
			v.add_child(row)
			var dl := PaperKit.hand("Día %d" % int(e["day"]), 28, PaperKit.RED_INK, true)
			dl.custom_minimum_size = Vector2(76, 0)
			dl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(dl)
			row.add_child(PaperKit.hand(String(e["text"]), 29, PaperKit.INK, false, HORIZONTAL_ALIGNMENT_LEFT, 384))
	if known and done < 3:
		v.add_child(PaperKit.hand("Continuará…", 30, PaperKit.INK_FAINT))

## Lo que se llevaron los clientes y todavía no se sabe cómo les fue.
func _journal_pending(v: VBoxContainer) -> void:
	var hd := UIKit.hbox(10)
	v.add_child(hd)
	var hg := PaperKit.pic("paper_i_hourglass", 4.0)
	hg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(hg)
	hd.add_child(PaperKit.head("Esperando noticias", 38))
	v.add_child(PaperKit.ink_rule(460, Color(0.37, 0.28, 0.2, 0.3)))
	if Game.pending.is_empty():
		v.add_child(PaperKit.gap(30))
		var en := PaperKit.pic("paper_i_envelope", 6.0)
		en.modulate = Color(1, 1, 1, 0.5)
		en.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(en)
		v.add_child(PaperKit.hand("Nada por ahora", 32, PaperKit.INK_FAINT, false, HORIZONTAL_ALIGNMENT_CENTER))
		return
	var shown := 0
	for o in Game.pending:
		if shown >= 7:
			v.add_child(PaperKit.hand("+%d…" % (Game.pending.size() - shown), 28, PaperKit.INK_FAINT))
			break
		var row := UIKit.hbox(10)
		v.add_child(row)
		var kind := String(o.get("item_kind", "potion"))
		var item := String(o.get("item", ""))
		# --- R3 MERGE: una noticia vieja de pergamino (partida de la ronda 2) muestra el icono de su runa (MAGIC3:
		# Game.LEGACY_SPELL_RUNE): los iconos spell_*.png ya no existen
		var ic := PaperKit.sketch("pot", item, 2.0) if kind == "potion" else PaperKit.pic("res://assets/icons/rune_%s.png" % String(Game.LEGACY_SPELL_RUNE.get(item, item)), 2.5)
		ic.custom_minimum_size = Vector2(68, 68)
		row.add_child(ic)
		var tv := UIKit.vbox(-6)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tv)
		tv.add_child(PaperKit.hand(Story.char_name(String(o["who"])), 32, PaperKit.INK, true))
		var il := UIKit.hbox(4)
		tv.add_child(il)
		il.add_child(PaperKit.hand(Story.item_name(kind, item), 26, PaperKit.INK_SOFT))
		for r in o.get("rune_want", []):   # MAGIC3: las runas que pidió (iconos)
			var rp := "res://assets/icons/rune_%s.png" % String(r)
			if ResourceLoader.exists(rp):
				var ri := PaperKit.pic(rp, 1.0)
				ri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				il.add_child(ri)
		row.add_child(PaperKit.hand("día %d" % int(o.get("day", 0)), 28, PaperKit.RED_INK, true))
		shown += 1

## Las cuentas de la tienda: iconos y números.
func _journal_stats(v: VBoxContainer) -> void:
	v.add_child(PaperKit.head("Cuentas", 40))
	v.add_child(PaperKit.ink_rule(460, Color(0.37, 0.28, 0.2, 0.3)))
	v.add_child(PaperKit.gap(8))
	var rows := [
		["paper_i_bottle", "Preparadas", str(int(Game.stats.get("brewed", 0)))],
		["paper_i_bag", "Ventas", str(int(Game.stats.get("sold", 0)))],
		["res://assets/icons/emote_coin.png", "Oro ganado", str(int(Game.stats.get("earned", 0)))],
		["res://assets/icons/emote_star.png", "Remezclas perfectas", str(int(Game.stats.get("perfect", 0)))],
		["res://assets/icons/emote_gem.png", "Renombre", "%d · %s" % [Game.renombre, Game.level_name()]],
	]
	# runas inscritas (MAGIC3: magic_stats["runes"]); con datos viejos, pergaminos
	var ms = Game.get("magic_stats")
	if Game.get("magic_unlocked") and ms is Dictionary:
		if ms.has("runes"):
			rows.insert(2, ["res://assets/icons/rune_prisa.png", "Runas", str(int(ms["runes"]))])
		elif ms.has("scrolls"):
			rows.insert(2, ["res://assets/icons/rune_prisa.png", "Pergaminos", str(int(ms["scrolls"]))])   # --- R3 MERGE: sin spell_*.png
	for r in rows:
		v.add_child(_stat_row(r[0], r[1], r[2]))
	v.add_child(PaperKit.gap(16))
	var sk := PaperKit.sketch("pot", "sueno_profundo", 3.0)
	sk.size_flags_horizontal = Control.SIZE_SHRINK_END
	sk.modulate = Color(1, 1, 1, 0.5)
	v.add_child(sk)

func _stat_row(icon: String, label: String, value: String) -> Control:
	var h := UIKit.hbox(12)
	h.custom_minimum_size = Vector2(0, 60)
	var t := PaperKit.tex(icon)
	var i := PaperKit.pic(icon, maxf(1.0, roundf(46.0 / t.get_height())) if t else 3.0)   # escala entera, ~46 px
	i.custom_minimum_size = Vector2(48, 48)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(i)
	var l := PaperKit.hand(label, 32, PaperKit.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var n := PaperKit.hand(value, 38, PaperKit.INK, true)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	return h
# --- end R3 PAPER

# ------------------------------------------------------------------ mercado y mejoras

## --- R3 PAPER: precios del mercado. Por la mañana, en el puesto: el precio normal. Durante el día, el encargo que
## trae Pip («Encargo al mercado») cuesta el doble: Game.market_price(id, true). Lo que se ve y lo que se cobra sale
## de esa misma función (Game.buy_ingredient(id, cantidad, encargo)).
const UPGRADE_SHORT := {
	"cojin": "Mimos: +1 potencia",
	"alfombra": "+10% propina",
	"caldero_ancho": "3 ingredientes",
	"huerto": "Cosecha cada mañana",
	"estante": "12 pociones",
	"campanilla": "+1 cliente al día",
	"farolillos": "+15% propina",
	"caldero_cobre": "+1 potencia",
	"krapido": "Pedidos por cuervo",   # --- R4 RAVEN
}

func show_market(mode := "day", vendor := "") -> void:
	_market_mode = mode
	# --- WORLD: en el mercado, cada puesto abre este mismo panel filtrado por su vendedor
	_market_vendor = vendor
	if vendor != "" and Data.VENDORS.has(vendor):
		_show_vendor(vendor)
		return
	_market_vendor = ""
	if mode == "day":
		_market_tab = 0   # el encargo del día solo trae ingredientes: las mejoras se compran en el puesto de Mabel
	# --- end WORLD
	# --- R3 PAPER: una hoja de pedido. De día: Pip clavado arriba y el sello rojo «x2» (cuesta el doble)
	var day_order := mode == "day"
	var p := PaperKit.panel("sheet", Vector2(58, 40))
	p.custom_minimum_size = Vector2(1250, 0)
	var v := UIKit.vbox(8)
	p.add_child(v)
	var head := UIKit.hbox(22)
	v.add_child(head)
	if day_order:
		head.add_child(PaperKit.pinned_portrait(Story.sprite_id("pip"), 1.5, "paper_pin_red"))
	var hv := UIKit.vbox(0)
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	hv.add_child(PaperKit.head("Encargo" if day_order else "Mercado", 52))
	if day_order:
		hv.add_child(PaperKit.hand("Pip lo trae corriendo", 32, PaperKit.INK_SOFT))
	if day_order:
		var x2 := PaperKit.pic("paper_x2", 5.0)
		x2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		x2.tooltip_text = "Precio doble"
		x2.mouse_filter = Control.MOUSE_FILTER_PASS
		head.add_child(x2)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var purse := PaperKit.coins(Game.gold, 52, PaperKit.INK, 3.0)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(purse)
	var tabs_row := UIKit.hbox(10)
	if not day_order:
		v.add_child(tabs_row)
		for i in 2:
			var ti := i
			var tb := PaperKit.button(["Ingredientes", "Mejoras"][i], func(): _refill_market(ti), 30, "tab")
			tabs_row.add_child(tb)
	v.add_child(PaperKit.ink_rule(1100, Color(0.37, 0.28, 0.2, 0.3)))
	var body := UIKit.vbox(0)
	body.custom_minimum_size = Vector2(1120, 0)
	v.add_child(body)
	var btns := UIKit.hbox(16)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	if mode == "morning":
		var o := PaperKit.button("Abrir tienda", func(): close(false); open_shop.emit(), 34)
		btns.add_child(o)
		btns.add_child(PaperKit.button("Preparar", func(): close(), 30))
	else:
		btns.add_child(_close_button())
	_mk_body = body
	_mk_gold = purse.get_child(1)
	_mk_tabs = tabs_row
	PaperKit.decor(p, "paper_pin_brass", Vector2(0.5, 0.0), Vector2(-10, -12))
	# --- end R3 PAPER
	_refill_market(_market_tab)
	_open("market", p)

var _mk_body: Control
var _mk_gold: Label
var _mk_tabs: Control

func _refill_market(tab: int) -> void:
	_market_tab = tab
	if not is_instance_valid(_mk_body):
		return
	_mk_gold.text = str(Game.gold)
	for c in _mk_body.get_children():
		_mk_body.remove_child(c)
		c.queue_free()
	var refresh := func(): _refill_market(_market_tab)
	if _market_vendor != "":   # --- WORLD
		_mk_body.add_child(_vendor_goods(_market_vendor, refresh))
		return
	if is_instance_valid(_mk_tabs):   # --- R3 PAPER: pestaña elegida
		for i in _mk_tabs.get_child_count():
			_mk_tabs.get_child(i).modulate = Color.WHITE if i == tab else Color(0.8, 0.76, 0.7)
	_mk_body.add_child(_market_ingredients(refresh, [], _market_mode == "day") if tab == 0 else _market_upgrades(refresh))

## --- R3 PAPER: los ingredientes como artículos (icono, tarjetita con nombre, esencias, precio y cuántos tienes,
## y +1 / +5). day_order: el encargo de día (precio doble en tinta roja, con el de la mañana tachado).
func _market_ingredients(refresh: Callable, only: Array = [], day_order := false) -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for id in (only if not only.is_empty() else Data.INGREDIENT_ORDER):   # --- WORLD: 'only' = los de un puesto
		g.add_child(_ingredient_good(id, refresh, day_order))
	return g

func _ingredient_good(id: String, refresh: Callable, day_order: bool) -> Control:
	var d: Dictionary = Data.INGREDIENTS[id]
	var unlocked := Game.ingredient_unlocked(id)
	var unit := Game.market_price(id, day_order)
	var box := UIKit.vbox(4)
	box.custom_minimum_size = Vector2(262, 0)
	var ic := PaperKit.pic("res://assets/icons/ing_%s.png" % id, 4.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not unlocked:
		ic.modulate = Color(0.25, 0.2, 0.18, 0.55)
	box.add_child(ic)
	var card := PaperKit.panel("card", Vector2(16, 6))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(card)
	var cv := UIKit.vbox(0)
	card.add_child(cv)
	cv.add_child(PaperKit.hand(String(d["name"]) if unlocked else "???", 30, PaperKit.INK if unlocked else PaperKit.INK_FAINT, true, HORIZONTAL_ALIGNMENT_CENTER, 220))
	if not unlocked:
		var lk := UIKit.hbox(6)
		lk.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_child(lk)
		lk.add_child(PaperKit.pic("paper_i_lock", 3.0))
		lk.add_child(UIKit.icon("res://assets/icons/emote_gem.png", 2.0))
		lk.add_child(PaperKit.hand(Game.level_name(int(d["level"])), 28, PaperKit.INK_FAINT, true))
		return box
	var es := PaperKit.ess_row(d["ess"], 3.0, 3)
	es.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(es)
	var pr := UIKit.hbox(12)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(pr)
	var price := PaperKit.coins(unit, 36, PaperKit.RED_INK if day_order else PaperKit.INK, 2.0)
	pr.add_child(price)
	# --- R3 SHIP: de día, el precio de la mañana tachado y el doble en rojo («3 6»). Antes era «6 x2», que se leía
	# como 6 por 2 = 12; el sello grande «x2» de arriba ya dice que cuesta el doble.
	if day_order:
		var was := PaperKit.hand(str(Game.market_price(id, false)), 30, PaperKit.INK_FAINT, true)
		was.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var strike := ColorRect.new()
		strike.color = Color(PaperKit.RED_INK, 0.9)
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strike.anchor_right = 1.0
		strike.anchor_top = 0.56
		strike.anchor_bottom = 0.56
		strike.offset_left = -3.0
		strike.offset_right = 3.0
		strike.offset_top = -1.5
		strike.offset_bottom = 1.5
		was.add_child(strike)
		price.add_child(was)
		price.move_child(was, 1)
	# --- end R3 SHIP
	var have := PaperKit.icon_text("paper_i_bag", str(int(Game.stock.get(id, 0))), 32, PaperKit.INK_SOFT, 3.0)
	have.tooltip_text = "Tienes"
	have.mouse_filter = Control.MOUSE_FILTER_PASS
	pr.add_child(have)
	var bh := UIKit.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bh)
	for q in [1, 5]:
		var qq: int = q
		var b := PaperKit.button("+%d" % qq, func():
			if Game.buy_ingredient(id, qq, day_order):
				Sfx.play("coin", 0.1, -8.0)
			refresh.call(), 34)
		b.custom_minimum_size = Vector2(112, 56)
		b.disabled = Game.gold < unit * qq
		b.tooltip_text = "%d oro" % (unit * qq)
		bh.add_child(b)
	return box

## --- R3 PAPER: las mejoras de Mabel: su dibujo, el nombre, lo que hace (pocas palabras), el precio y Comprar.
func _market_upgrades(refresh: Callable) -> Control:
	var g := GridContainer.new()
	g.columns = 4
	var five := Data.UPGRADE_ORDER.size() > 8   # --- R4 RAVEN: con la 9.ª mejora (Krápido) van 5 por fila (si no, no cabe)
	if five:
		g.columns = 5
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for id in Data.UPGRADE_ORDER:
		var u: Dictionary = Data.UPGRADES[id]
		var owned := Game.has_upgrade(id)
		var locked: bool = Game.level() < int(u["level"])
		var box := UIKit.vbox(4)
		box.custom_minimum_size = Vector2(262 if not five else 214, 0)   # --- R4 RAVEN
		g.add_child(box)
		var ic := PaperKit.pic("paper_up_%s" % id, 4.0)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if locked:
			ic.modulate = Color(0.3, 0.25, 0.22, 0.55)
		box.add_child(ic)
		var card := PaperKit.panel("card", Vector2(16, 6))
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.tooltip_text = String(u.get("desc", ""))
		box.add_child(card)
		var cv := UIKit.vbox(0)
		card.add_child(cv)
		cv.add_child(PaperKit.hand(String(u["name"]), 28, PaperKit.INK if not locked else PaperKit.INK_FAINT, true, HORIZONTAL_ALIGNMENT_CENTER, 226 if not five else 182))   # --- R4 RAVEN
		cv.add_child(PaperKit.hand(String(UPGRADE_SHORT.get(id, u.get("desc", ""))), 27, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, 220 if not five else 178))   # --- R4 RAVEN
		var b: Button
		if owned:
			b = PaperKit.button("Comprada", func(): pass, 28)
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", PaperKit.HERB)
		elif locked:
			var lk := UIKit.hbox(6)
			lk.alignment = BoxContainer.ALIGNMENT_CENTER
			cv.add_child(lk)
			lk.add_child(PaperKit.pic("paper_i_lock", 3.0))
			lk.add_child(UIKit.icon("res://assets/icons/emote_gem.png", 2.0))
			lk.add_child(PaperKit.hand(Game.level_name(int(u["level"])), 28, PaperKit.INK_FAINT, true))
		else:
			var pr := PaperKit.coins(int(u["cost"]), 36, PaperKit.INK, 2.0)
			pr.alignment = BoxContainer.ALIGNMENT_CENTER
			cv.add_child(pr)
			b = PaperKit.button("Comprar", func():
				if Game.buy_upgrade(id):
					Sfx.play("levelup", 0.02, -6.0)
				refresh.call(), 30)
			b.disabled = Game.gold < int(u["cost"])
		if b:
			b.custom_minimum_size = Vector2(160, 48)
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(b)
	return g

# --- WORLD: el panel de un puesto del mercado ------------------------------------------------------------

## Retrato de un personaje: el primer cuadro de su animación de reposo (sirve para sprites de 32x48 o 64x96).
func _char_portrait(id: String, h := 144.0) -> TextureRect:
	var port := TextureRect.new()
	var tex: Texture2D = load("res://assets/chars/%s_idle.png" % id)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, tex.get_width() / 2, tex.get_height())
	port.texture = at
	port.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	port.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	port.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	port.custom_minimum_size = Vector2(h * 2.0 / 3.0, h)
	port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return port

## Sprite que se usa para un vendedor (el suyo si existe; si no, el de reserva de Data.VENDORS).
static func vendor_sprite(vendor: String) -> String:
	if ResourceLoader.exists("res://assets/chars/%s_idle.png" % vendor):
		return vendor
	return Data.VENDORS.get(vendor, {}).get("fallback", "anciano")

func _vendor_hello(vendor: String) -> String:
	var vd: Dictionary = Data.VENDORS[vendor]
	var lines: Array = vd.get("hello", []).duplicate()
	var story: Dictionary = vd.get("hello_story", {})
	for hero in story:
		if Game.hero_progress.get(hero, 0) >= 1:
			lines.append_array(story[hero])
	return lines.pick_random() if not lines.is_empty() else ""

## --- R3 PAPER: el puesto: el festón de su toldo, el letrero de madera, el vendedor con su saludo en un bocadillo,
## la bolsa de monedas y lo que vende sobre un mantel del color del toldo.
func _show_vendor(vendor: String) -> void:
	var vd: Dictionary = Data.VENDORS[vendor]
	var awning := String(vd.get("awning", "rojo"))
	var p := PaperKit.panel("wood", Vector2(34, 26))
	p.custom_minimum_size = Vector2(1250, 0)
	var v := UIKit.vbox(10)
	p.add_child(v)
	var val_path := "res://assets/tex/valance_%s.png" % awning
	if ResourceLoader.exists(val_path):
		PaperKit.attach(p, PaperKit.strip(val_path, 1250.0 - 40.0, 3.0), Vector2(0, 0), Vector2(20, 10))
		v.add_child(PaperKit.gap(28))
	var head := UIKit.hbox(20)
	v.add_child(head)
	var port := PaperKit.portrait(vendor_sprite(vendor), 2.0)
	head.add_child(port)
	var hv := UIKit.vbox(10)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	var sign := PaperKit.panel("sign", Vector2(36, 4))
	sign.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sl := UIKit.label(String(vd["stall"]), 42, Color("f4e4bd"), UIKit.font_sc_bold)
	sl.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02, 0.85))
	sl.add_theme_constant_override("outline_size", 6)
	sign.add_child(sl)
	hv.add_child(sign)
	var hello := _vendor_hello(vendor)
	if hello != "":
		var bub := PaperKit.panel("bubble", Vector2(26, 8))
		bub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bub.add_child(PaperKit.hand(hello, 32, PaperKit.INK, false, HORIZONTAL_ALIGNMENT_LEFT, 640))
		hv.add_child(bub)
	var purse := PaperKit.coins(Game.gold, 56, Color("f4e4bd"), 3.0)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse.get_child(1).add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02, 0.85))
	purse.get_child(1).add_theme_constant_override("outline_size", 6)
	head.add_child(purse)
	var cloth := PaperKit.panel("cloth_" + awning, Vector2(26, 18))
	cloth.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(cloth)
	var btns := UIKit.hbox(16)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	btns.add_child(_close_button("Seguir"))
	_mk_body = cloth
	_mk_gold = purse.get_child(1)
	_mk_tabs = null
	_refill_market(0)
	_open("market", p)
# --- end R3 PAPER

## Lo que vende un puesto: sus ingredientes, las mejoras (Mabel) y los objetos de MAGIC_ITEMS de ese vendedor.
func _vendor_goods(vendor: String, refresh: Callable) -> Control:
	if Data.VENDORS[vendor].get("upgrades", false):
		return _market_upgrades(refresh)
	var ids := vendor_ingredients(vendor)
	var items := vendor_items(vendor)
	# --- R3 PAPER: todo en la misma cuadrícula sobre el mantel
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for id in ids:
		g.add_child(_ingredient_good(id, refresh, false))
	for it in items:
		g.add_child(_item_good(it, refresh))
	if ids.size() + items.size() <= 8:
		return g
	# más de dos filas: se desplaza (rueda del ratón o stick derecho del mando)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(1150, 560)
	sc.add_child(g)
	return sc
	# --- end R3 PAPER

## Ingredientes de un puesto: los de Data.VENDORS[...]["goods"] y los que tengan "vendor": <puesto> en INGREDIENTS.
static func vendor_ingredients(vendor: String) -> Array:
	var out: Array = Data.VENDORS.get(vendor, {}).get("goods", []).duplicate()
	for id in Data.INGREDIENT_ORDER:
		if Data.INGREDIENTS[id].get("vendor", "") == vendor and not out.has(id):
			out.append(id)
	return out

## Objetos de MAGIC (Data.MAGIC_ITEMS, si existe) con "vendor": <puesto>. Cada uno: {"id", "name", "price", ...}.
static func vendor_items(vendor: String) -> Array:
	var out := []
	var mi = Data.get("MAGIC_ITEMS")
	if mi is Dictionary:
		var order = Data.get("MAGIC_ITEM_ORDER")
		var keys: Array = order if order is Array else mi.keys()
		for id in keys:
			var it: Dictionary = mi[id]
			if it.get("vendor", "") == vendor:
				var d := it.duplicate()
				d["id"] = id
				out.append(d)
	elif mi is Array:
		for it in mi:
			if it is Dictionary and it.get("vendor", "") == vendor:
				out.append(it)
	return out

## --- R3 PAPER: un objeto de MAGIC (tinta, papel, una página...): comprar llama a Game.buy_item(id, cantidad) y lo
## que tienes, a Game.item_count(id). Icono: "icon" (ruta) o assets/icons/<id>.png. Con "max": n solo se compra
## hasta tener n (una página del grimorio, por ejemplo: un único botón «Comprar»).
func _item_good(it: Dictionary, refresh: Callable) -> Control:
	var id: String = it.get("id", "")
	var price: int = int(it.get("price", 0))
	var have: int = int(Game.call("item_count", id)) if Game.has_method("item_count") else 0
	var cap: int = int(it.get("max", 0))
	var box := UIKit.vbox(4)
	box.custom_minimum_size = Vector2(262, 0)
	var icon_path: String = it.get("icon", "res://assets/icons/%s.png" % id)
	var ic := PaperKit.pic(icon_path, 4.0)
	ic.custom_minimum_size = Vector2(64, 64)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var card := PaperKit.panel("card", Vector2(16, 6))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.tooltip_text = String(it.get("desc", ""))
	box.add_child(card)
	var cv := UIKit.vbox(0)
	card.add_child(cv)
	cv.add_child(PaperKit.hand(String(it.get("name", id)), 30, PaperKit.INK, true, HORIZONTAL_ALIGNMENT_CENTER, 220))
	var pr := UIKit.hbox(12)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(pr)
	pr.add_child(PaperKit.coins(price, 36, PaperKit.INK, 2.0))
	pr.add_child(PaperKit.icon_text("paper_i_bag", str(have), 32, PaperKit.INK_SOFT, 3.0))
	var bh := UIKit.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bh)
	var qs: Array = [1] if cap > 0 else [1, 5]
	for q in qs:
		var qq: int = q
		var b := PaperKit.button("Comprar" if cap > 0 else "+%d" % qq, func():
			if Game.has_method("buy_item") and Game.call("buy_item", id, qq):
				Sfx.play("coin", 0.1, -8.0)
			refresh.call(), 34)
		b.custom_minimum_size = Vector2(112, 56)
		b.disabled = Game.gold < price * qq or not Game.has_method("buy_item") or (cap > 0 and have >= cap)
		if cap > 0 and have >= cap:   # MAGIC3: la página del grimorio se compra una vez ("max": 1)
			b.text = "Aprendida" if it.has("rune") else "Comprada"
			b.add_theme_color_override("font_disabled_color", PaperKit.HERB)
		bh.add_child(b)
	return box
# --- end WORLD

# --- STORY: el correo de la mañana -----------------------------------------------------------------------------

const PAPER := Color(0.95, 0.9, 0.79)
const PAPER_EDGE := Color(0.62, 0.47, 0.3)
const INK := Color(0.27, 0.19, 0.13)

var _mail_letters: Array = []
var _mail_rumors: Array = []
var _rank_strip: Control   # --- R4 RANK
var _mail_body: VBoxContainer
var _mail_nav: HBoxContainer

## El correo de la mañana: las cartas de los clientes una a una (quién escribe, la carta y lo que trae) y, al final,
## los rumores del pueblo. letters: ver Story.letter(). rumors: textos. first_time: ya no cambia nada (R3 PAPER: sin
## explicaciones). Se cierra con el último botón, con Esc o con B en el mando (emite closed("mail")).
func show_mail(letters: Array, rumors: Array = [], _first_time := false) -> void:
	_mail_letters = letters
	_mail_rumors = rumors
	Sfx.play("page", 0.05, -3.0)
	# --- R3 PAPER: solo la carta (pergamino, retrato clavado, sello de lacre), lo que trae y el botón
	var box := UIKit.vbox(10)
	box.custom_minimum_size = Vector2(1080, 0)
	var hd := UIKit.hbox(12)
	hd.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hd)
	var env := PaperKit.pic("paper_i_envelope", 4.0)
	env.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(env)
	hd.add_child(_title_row("Correo", 46))
	# --- R4 RANK: la línea del Escalafón del Gremio (puesto, flecha, a quién pasó), en la primera página
	_rank_strip = RankUI.mail_strip() if Ranking.has_morning_news() else null
	if _rank_strip:
		box.add_child(_rank_strip)
	# --- end R4 RANK
	_mail_body = UIKit.vbox(12)
	box.add_child(_mail_body)
	_mail_nav = UIKit.hbox(18)
	_mail_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_mail_nav)
	_mail_page(0)
	# --- end R3 PAPER
	_open("mail", box)

func _clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

## Una página del correo: la carta i (y los rumores con la última).
func _mail_page(i: int) -> void:
	if not is_instance_valid(_mail_body):
		return
	_clear_children(_mail_body)
	_clear_children(_mail_nav)
	if is_instance_valid(_rank_strip):
		_rank_strip.visible = i == 0   # --- R4 RANK
	var n := _mail_letters.size()
	if i < n:
		_mail_body.add_child(_mail_letter(_mail_letters[i]))
		if _mail_letters[i].get("ok", false):
			Sfx.play("coin", 0.05, -9.0)
	var last := i >= n - 1
	if last and not _mail_rumors.is_empty():
		_mail_body.add_child(_mail_rumor_box())
	# --- R3 PAPER: «2 / 3» y un botón de una palabra
	if n > 1:
		_mail_nav.add_child(UIKit.shadow(PaperKit.hand("%d / %d" % [i + 1, n], 34, Color("eadbb8"), true), 2))
	if not last:
		var b := PaperKit.wood_button("Siguiente", func():
			Sfx.play("page", 0.05, -5.0)
			_mail_page(i + 1), 32)
		b.custom_minimum_size = Vector2(260, 64)
		_mail_nav.add_child(b)
	else:
		var b2 := PaperKit.wood_button("Listo" if n > 0 else "A trabajar", func(): close(), 32)
		b2.custom_minimum_size = Vector2(260, 64)
		_mail_nav.add_child(b2)
	# --- end R3 PAPER

## --- R3 PAPER: una carta de papel de verdad: el retrato de quien escribe clavado a la izquierda, el sello de lacre
## (gris si es una queja), saludo, texto y firma a mano; debajo, en una tablilla, lo que trae (iconos y números).
func _mail_letter(L: Dictionary) -> Control:
	var box := UIKit.vbox(8)
	var paper := PaperKit.panel("sheet", Vector2(56, 36))
	paper.custom_minimum_size = Vector2(1060, 0)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(paper)
	var row := UIKit.hbox(26)
	paper.add_child(row)
	var card := PaperKit.pinned_portrait(String(L.get("sprite", "anciano")), 2.0, "paper_pin_red")
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card)
	var pv := UIKit.vbox(8)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pv)
	var top := UIKit.hbox(10)
	pv.add_child(top)
	var hello := PaperKit.hand(String(L.get("hello", "")), 36, PaperKit.INK, true)
	hello.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hello.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(hello)
	top.add_child(_mail_seal(String(L.get("name", "?")).left(1), bool(L.get("ok", true))))
	var body := PaperKit.rich(33, PaperKit.INK)
	body.custom_minimum_size = Vector2(780, 0)
	body.text = String(L.get("body", ""))
	pv.add_child(body)
	pv.add_child(PaperKit.hand("— " + String(L.get("sign", "")), 32, PaperKit.INK_SOFT, true, HORIZONTAL_ALIGNMENT_RIGHT))
	if String(L.get("reward", "")) != "":
		var tab := PaperKit.panel("wood", Vector2(30, 6))
		tab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rw := UIKit.rich(38)
		rw.fit_content = true
		rw.autowrap_mode = TextServer.AUTOWRAP_OFF
		rw.add_theme_font_override("normal_font", UIKit.font_bold)
		rw.text = "[center]%s[/center]" % String(L["reward"]).replace("[img=32]", "[img=48]").replace("[img=30]", "[img=40]").replace("[img=27]", "[img=36]")
		tab.add_child(rw)
		box.add_child(tab)
	return box

## El sello de lacre de la carta, con la inicial de quien escribe (gris si es una queja).
func _mail_seal(initial: String, ok: bool) -> Control:
	var s := PaperKit.seal(initial, "paper_seal" if ok else "paper_seal_grey", 3.0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s

## Los rumores del pueblo: una nota amarilla clavada.
func _mail_rumor_box() -> Control:
	var n := PaperKit.panel("note", Vector2(40, 16))
	n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	n.custom_minimum_size = Vector2(900, 0)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rb := UIKit.vbox(2)
	n.add_child(rb)
	rb.add_child(PaperKit.head(String(Data.LETTERS["rumors"]), 32, PaperKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	for t in _mail_rumors:
		rb.add_child(PaperKit.hand("«%s»" % t, 30, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, 820))
	PaperKit.decor(n, "paper_pin_green", Vector2(0.5, 0.0), Vector2(-10, -12))
	return n
# --- end STORY

# --- R4 EVENTS: la invitación a un evento (llega con el correo de la mañana) ----------------------------------------
## Una invitación de papel grueso: el retrato de quien invita clavado a la izquierda, su sello de lacre, el saludo, dos
## líneas y la firma; debajo, en una tira, el evento, el día, la dificultad, la inscripción, el premio (con medalla de
## oro) y el riesgo (sin medalla), en iconos y números. Aceptar paga la inscripción. Emite invite_answered(acepta).
## inv: Game.ev_invite (ver Events.make_invite). No se cierra con Esc: hay que elegir.
func show_invitation(inv: Dictionary) -> void:
	var kind := String(inv.get("kind", "academia"))
	var c: Dictionary = Events.info(kind)
	var tier := int(inv.get("tier", 0))
	Sfx.play("page", 0.05, -3.0)
	var box := UIKit.vbox(10)
	box.custom_minimum_size = Vector2(1100, 0)
	var hd := UIKit.hbox(12)
	hd.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hd)
	var env := PaperKit.pic("paper_i_envelope", 4.0)
	env.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(env)
	hd.add_child(_title_row("Invitación", 46))
	var paper := PaperKit.panel("sheet", Vector2(56, 34))
	paper.custom_minimum_size = Vector2(1080, 0)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(paper)
	var col := UIKit.vbox(10)
	paper.add_child(col)
	var row := UIKit.hbox(26)
	col.add_child(row)
	var card := PaperKit.pinned_portrait(Story.sprite_id(String(c["host"])), 2.0, "paper_pin_brass")
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card)
	var pv := UIKit.vbox(6)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pv)
	var top := UIKit.hbox(10)
	pv.add_child(top)
	var hello := PaperKit.hand(String(c["hello"]), 36, PaperKit.INK, true)
	hello.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hello.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(hello)
	var seal := PaperKit.pic(String(c["seal"]), 3.5)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.tooltip_text = String(c["host_name"])
	seal.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(seal)
	var body := PaperKit.rich(33, PaperKit.INK)
	body.custom_minimum_size = Vector2(780, 0)
	body.text = String(c["body"])
	pv.add_child(body)
	pv.add_child(PaperKit.hand("— " + String(c["sign"]), 30, PaperKit.INK_SOFT, true, HORIZONTAL_ALIGNMENT_RIGHT))
	col.add_child(PaperKit.ink_rule(900, Color(0.37, 0.28, 0.2, 0.35)))
	# el evento y sus datos (iconos y números)
	var name_l := PaperKit.head(Events.ev_name(kind, true), 40, Color("7a1d18"), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(name_l)
	col.add_child(PaperKit.hand(Events.line(kind, "what", inv), 30, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER))
	var facts := UIKit.hbox(34)
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(facts)
	facts.add_child(PaperKit.icon_text("evui_calendar", Events.when_text(int(inv.get("day", Game.day + 2))), 30, PaperKit.INK, 3.5))
	var dif := UIKit.hbox(4)
	dif.tooltip_text = "Dificultad"
	dif.mouse_filter = Control.MOUSE_FILTER_PASS
	dif.add_child(PaperKit.hand("Dificultad", 30, PaperKit.INK, true))
	dif.add_child(PaperKit.gap(0, 6))
	var nd := int(inv.get("difficulty", 1))
	for i in 3:
		var st := UIKit.icon("res://assets/icons/emote_star.png" if i < nd else "res://assets/icons/emote_star_empty.png", 2.2)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dif.add_child(st)
	facts.add_child(dif)
	var feeb := UIKit.hbox(6)
	feeb.add_child(PaperKit.hand("Inscripción", 30, PaperKit.INK, true))
	feeb.add_child(PaperKit.coins(int(inv.get("fee", 0)), 30, PaperKit.RED_INK))
	facts.add_child(feeb)
	# premio (con oro) y riesgo (sin medalla)
	var win: Dictionary = Events.reward(kind, "gold", tier)
	var lose: Dictionary = Events.reward(kind, "none", tier)
	var strip := PaperKit.panel("wood", Vector2(30, 8))
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(strip)
	var rw := UIKit.rich(34)
	rw.fit_content = true
	rw.autowrap_mode = TextServer.AUTOWRAP_OFF
	rw.add_theme_font_override("normal_font", UIKit.font_bold)
	var coin := "[img=40]res://assets/icons/emote_coin.png[/img]"
	var gem := "[img=40]res://assets/icons/emote_gem.png[/img]"
	var t := "[img=36]res://assets/ui/evui_tick_gold.png[/img] %s [color=#ffd987]+%d[/color]   %s [color=#d9c8ff]+%d[/color]   [img=40]res://assets/ui/evui_trophy.png[/img]" % [coin, int(win["gold"]), gem, int(win["renombre"])]
	if kind == "torneo":
		t += "  [color=#f2e2bc]+ propinas[/color]"
	t += "        [color=#c8b9a4]Sin medalla:[/color] %s [color=#ff9b9b]%d[/color]" % [gem, int(lose["renombre"])]
	rw.text = "[center]%s[/center]" % t
	strip.add_child(rw)
	# Aceptar / Rechazar
	var nav := UIKit.hbox(26)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(nav)
	var fee := int(inv.get("fee", 0))
	var acc := PaperKit.wood_button("Aceptar", func():
		if Game.gold < fee:
			return
		close(false)
		invite_answered.emit(true), 34)
	acc.custom_minimum_size = Vector2(280, 70)
	acc.name = "Aceptar"
	nav.add_child(acc)
	var rej := PaperKit.wood_button("Rechazar", func():
		close(false)
		invite_answered.emit(false), 34)
	rej.custom_minimum_size = Vector2(280, 70)
	rej.name = "Rechazar"
	nav.add_child(rej)
	if Game.gold < fee:
		acc.disabled = true
		acc.modulate = Color(0.7, 0.68, 0.66)
		nav.add_child(UIKit.shadow(PaperKit.hand("Faltan %d" % (fee - Game.gold), 32, Color("ff9b9b"), true), 2))
	_open("invite", box)

## La invitación abierta: Aceptar (true) o Rechazar (false), como un clic (el bot y las pruebas).
func answer_invitation(accept: bool) -> bool:
	if current != "invite" or not is_instance_valid(current_node):
		return false
	var b := current_node.find_child("Aceptar" if accept else "Rechazar", true, false)
	if b is Button and not b.disabled:
		b.pressed.emit()
		return true
	return false

## La fila del evento en las cuentas de la noche: la medalla, el nombre del evento y la medalla en palabras.
func _event_row(e: Dictionary) -> Control:
	var medal := String(e.get("medal", "none"))
	var h := UIKit.hbox(14)
	h.custom_minimum_size = Vector2(0, 66)
	var ic := PaperKit.pic("evui_medal_%s" % medal, 2.0)
	ic.custom_minimum_size = Vector2(52, 66)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := PaperKit.hand(Events.ev_name(String(e.get("kind", "academia"))), 32, PaperKit.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var word := String(Events.MEDAL_WORD.get(medal, medal)).capitalize() if medal != "none" else "Sin medalla"
	var vl := PaperKit.hand(word, 36, Color("7a1d18") if medal == "none" else PaperKit.INK, true, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(vl)
	return h
# --- end R4 EVENTS

# ------------------------------------------------------------------ resumen del día

## --- R4 PACE: el libro de cuentas de la noche (como en Papers, Please): una hoja con renglones, una fila por cosa
## (icono, concepto, una línea de puntos y la cifra a mano) que se van escribiendo de una en una, y al final el sello
## del día. Los números salen de Game.today (main.gd, bloque R4 PACE): atendidos, se cansaron de esperar, fila llena,
## a casa al cerrar, sin atender, espera media (en horas del reloj de la tienda), lo ganado, las propinas por rapidez y
## el renombre (lo ganado y lo perdido). Debajo, en una sola línea: recetas nuevas, noticias por llegar y el diario.
## _ledger_extra(v, today) queda para filas de otras partes (el escalafón). Se cierra con «Dormir».
## (Antes, R3 PAPER: una hoja de cuentas con oro, renombre y ventas.)
func show_summary(day: int, today: Dictionary) -> void:
	var p := PaperKit.panel("sheet", Vector2(66, 36))
	p.custom_minimum_size = Vector2(800, 0)
	var v := UIKit.vbox(0)
	p.add_child(v)
	var hd := UIKit.hbox(14)
	hd.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hd)
	var moon := PaperKit.pic("paper_i_moon", 4.0)
	moon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(moon)
	hd.add_child(PaperKit.head("Cuentas del día %d" % day, 44))
	v.add_child(PaperKit.gap(4))
	v.add_child(_ledger_rule(Color(0.62, 0.16, 0.12, 0.5)))   # la doble raya roja de los libros de cuentas
	v.add_child(PaperKit.gap(3))
	v.add_child(_ledger_rule(Color(0.62, 0.16, 0.12, 0.5)))
	var lines: Array = []   # lo que se va escribiendo, en orden
	var served := int(today.get("served", 0))
	var tired := int(today.get("lost_tired", 0))
	var full := int(today.get("lost_full", 0))
	var closed := int(today.get("lost_closed", 0))
	var declined := int(today.get("declined", 0))
	var ev_day: bool = today.get("event", null) is Dictionary   # --- R4 EVENTS (merge): día de evento: la tienda no abrió
	if ev_day:   # --- R4 EVENTS (merge): primero la medalla del evento; en lugar de las filas de la tienda, una sola línea
		lines.append(_event_row(today["event"]))
		lines.append(_ledger_row("paper_i_lock", "Tienda cerrada: día de evento", _ledger_num("—", PaperKit.INK_SOFT)))
	else:
		lines.append(_ledger_row("paper_i_person", "Atendidos", _ledger_num(str(served))))
		lines.append(_ledger_row("res://assets/icons/emote_hourglass_0.png", "Se cansaron de esperar",
			_ledger_num(str(tired), PaperKit.RED_INK if tired > 0 else PaperKit.INK_SOFT)))
		lines.append(_ledger_row("paper_i_door", "Fila llena: no entraron",
			_ledger_num(str(full), PaperKit.RED_INK if full > 0 else PaperKit.INK_SOFT)))
		if closed > 0:
			lines.append(_ledger_row("paper_i_moon", "A casa al cerrar", _ledger_num(str(closed), PaperKit.INK_SOFT)))
		if declined > 0:
			lines.append(_ledger_row("paper_i_lock", "Sin atender", _ledger_num(str(declined), PaperKit.INK_SOFT)))
		if served > 0:
			lines.append(_ledger_row("res://assets/ui/hud_clock.png", "Espera media", _ledger_num(_ledger_wait(float(today.get("avg_wait", 0.0))))))
		# --- R4 RAVEN (merge: the Krápido row moved from the old summary into PACE's ledger): entregas por cuervo
		if Game.krapido_on() or int(today.get("deliveries", 0)) > 0:
			var dl := int(today.get("deliveries_lost", 0))
			lines.append(_ledger_row("res://assets/ui/raven_head.png", "Krápido",
				_ledger_num(str(int(today.get("deliveries", 0))) + ("  (−%d)" % dl if dl > 0 else ""))))
		# --- end R4 RAVEN
	lines.append(_ledger_rule(Color(0.37, 0.28, 0.2, 0.35)))
	lines.append(_ledger_row("res://assets/icons/emote_coin.png", "Ganado", _ledger_num("+%d" % int(today.get("earned", 0)))))
	var tips := int(today.get("speed_tips", 0))
	if tips > 0:
		lines.append(_ledger_row("res://assets/icons/emote_hourglass_4.png", "Propinas por rapidez", _ledger_num("+%d" % tips, PaperKit.HERB)))
	var lost := int(today.get("renombre_lost", 0))
	lines.append(_ledger_row("res://assets/icons/emote_gem.png", "Renombre", _ledger_renown(int(today.get("renombre", 0)) + lost, lost)))
	var rank_row := _ledger_rank_row()   # --- R4 RANK (merge): el puesto en el Escalafón, un renglón más del libro de cuentas
	if rank_row:
		lines.append(rank_row)
	for c in lines:
		v.add_child(c)
	_ledger_extra(v, today)
	# lo de las historias, en una sola línea: recetas nuevas, noticias por llegar y páginas del diario
	var ex := UIKit.hbox(12)
	ex.alignment = BoxContainer.ALIGNMENT_CENTER
	ex.custom_minimum_size = Vector2(0, 58)
	if today.get("new_recipes", []).size() > 0:
		ex.add_child(_ledger_icon("paper_i_bottle", "Recetas nuevas"))
		for pid in today["new_recipes"]:
			var sk := PaperKit.sketch("pot", pid, 2.0)
			sk.tooltip_text = String(Data.POTIONS.get(pid, {}).get("name", pid))
			sk.mouse_filter = Control.MOUSE_FILTER_PASS
			sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ex.add_child(sk)
	var waiting := Game.pending.size()   # --- STORY: las noticias que faltan (llegan por carta o en persona)
	if waiting > 0:
		if ex.get_child_count() > 0:
			ex.add_child(PaperKit.gap(0, 18))
		ex.add_child(_ledger_icon("paper_i_envelope", "Noticias por llegar"))
		ex.add_child(_ledger_num(str(waiting), PaperKit.INK_SOFT))
	if today.get("journal", []).size() > 0:
		if ex.get_child_count() > 0:
			ex.add_child(PaperKit.gap(0, 18))
		ex.add_child(_ledger_icon("paper_i_page", "Diario"))
		for e in today["journal"]:
			var who := String(e["hero"])
			var pt := PaperKit.portrait(Story.sprite_id(who), 0.8)
			pt.tooltip_text = String(Data.CHARACTERS.get(who, {}).get("name", who))
			pt.mouse_filter = Control.MOUSE_FILTER_PASS
			ex.add_child(pt)
	if ex.get_child_count() > 0:
		lines.append(ex)
		v.add_child(PaperKit.gap(4))
		v.add_child(ex)
	v.add_child(PaperKit.gap(16))   # --- R4 MERGE: algo más de aire: el sello (torcido) no pisa el último renglón (el Escalafón)
	var b := PaperKit.button("Dormir", func(): close(false); sleep.emit(), 38, "card", "paper_i_moon")
	b.custom_minimum_size = Vector2(300, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	PaperKit.decor(p, "paper_tape", Vector2(0.5, 0.0), Vector2(-36, -12), 3.0, false, Color.WHITE, 0.04)
	# el sello del día: según cuántos de los que vinieron se fueron atendidos
	var came := served + tired + full
	var stamp: Control = null
	if ev_day:   # --- R4 EVENTS (merge): el sello del día de evento es la medalla
		var md := String((today["event"] as Dictionary).get("medal", "none"))
		var good := md == "gold" or md == "silver"
		stamp = _ledger_stamp({"gold": "¡Oro!", "silver": "Plata", "bronze": "Bronce"}.get(md, "Sin medalla"),
			PaperKit.HERB if good else (PaperKit.INK if md == "bronze" else PaperKit.RED_INK))
		PaperKit.attach(p, stamp, Vector2(1, 1), Vector2(-236, -98), false, -0.12)   # --- R4 MERGE: junto a «Dormir» (antes -116)
		stamp.modulate.a = 0.0
	elif came > 0:
		var rate := float(served) / float(came)
		var verdict := "Día flojo"
		if rate >= 0.9 and served >= 3:
			verdict = "¡Gran día!"
		elif rate >= 0.7:
			verdict = "Buen día"
		elif rate >= 0.45:
			verdict = "Día duro"
		stamp = _ledger_stamp(verdict, PaperKit.HERB if rate >= 0.7 else PaperKit.RED_INK)
		PaperKit.attach(p, stamp, Vector2(1, 1), Vector2(-236, -98), false, -0.12)   # --- R4 MERGE: junto a «Dormir» (antes -116)
		stamp.modulate.a = 0.0
	_open("summary", p)
	# se escribe renglón por renglón (la pluma), y al final cae el sello
	for c in lines:
		c.modulate.a = 0.0
	var snd := AudioStreamPlayer.new()
	snd.bus = "SFX"
	snd.stream = load("res://assets/audio/pace_stamp.ogg") if ResourceLoader.exists("res://assets/audio/pace_stamp.ogg") else null
	snd.volume_db = -3.0
	p.add_child(snd)
	var tw := p.create_tween()
	tw.tween_interval(0.4)
	for c in lines:
		tw.tween_callback(func(): Sfx.play_pitched("quill", randf_range(0.92, 1.12), -14.0))
		tw.tween_property(c, "modulate:a", 1.0, 0.14)
		tw.tween_interval(0.06)
	if stamp:
		tw.tween_interval(0.25)
		tw.tween_callback(func():
			if snd.stream:
				snd.play())
		tw.tween_property(stamp, "modulate:a", 0.92, 0.07)

## Más filas del libro de cuentas para otras partes del juego (el escalafón del gremio: RANK). Vacío por ahora.
func _ledger_extra(_v: VBoxContainer, _today: Dictionary) -> void:
	pass

## --- R4 RANK (merge): el renglón del Escalafón (Ranking.commit_day ya sumó el día): escudo del Gremio, flecha y puesto.
## (Lo que era RankUI.summary_row() en el resumen viejo, con el formato del libro de cuentas de PACE.)
func _ledger_rank_row() -> Control:
	var mv: Dictionary = Ranking.last_move
	if mv.is_empty() or int(mv.get("day", 0)) != Game.day:
		return null
	var val := UIKit.hbox(8)
	val.add_child(RankUI.arrow(int(mv.get("delta", 0)), 30, false))
	val.add_child(_ledger_num("%dº" % int(mv.get("pos", 30))))
	return _ledger_row("rank_crest_gremio", "Escalafón", val)
# --- end R4 RANK

## Un renglón: icono, concepto, una línea de puntos y la cifra.
func _ledger_row(icon: String, label: String, value: Control) -> Control:
	var h := UIKit.hbox(10)
	h.custom_minimum_size = Vector2(0, 44)
	h.add_child(_ledger_icon(icon, label))
	var l := PaperKit.hand(label, 30, PaperKit.INK_SOFT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var dots := Control.new()
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.custom_minimum_size = Vector2(40, 30)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.draw.connect(func():
		var y := dots.size.y * 0.74
		var x := 6.0
		while x < dots.size.x - 6.0:
			dots.draw_rect(Rect2(x, y, 3, 3), Color(0.37, 0.28, 0.2, 0.42))
			x += 11.0)
	h.add_child(dots)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(value)
	return h

func _ledger_icon(icon: String, tip := "") -> TextureRect:
	var t := PaperKit.tex(icon)
	var i := PaperKit.pic(icon, maxf(1.0, roundf(34.0 / float(t.get_height()))) if t else 2.0)
	i.custom_minimum_size = Vector2(40, 40)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tip != "":
		i.tooltip_text = tip
		i.mouse_filter = Control.MOUSE_FILTER_PASS
	return i

func _ledger_num(text: String, color := PaperKit.INK) -> Label:
	return PaperKit.hand(text, 36, color, true)

## El renombre del día: lo ganado y, en rojo, lo que se perdió con quienes se cansaron de esperar.
func _ledger_renown(gain: int, lost: int) -> Control:
	var h := UIKit.hbox(12)
	h.add_child(_ledger_num("+%d" % maxi(0, gain)))
	if lost > 0:
		h.add_child(_ledger_num("−%d" % lost, PaperKit.RED_INK))
	return h

## Lo que esperaron, en horas del reloj de la tienda (5 minutos reales = de 9:00 a 18:00).
func _ledger_wait(secs: float) -> String:
	var m := int(round(secs * float(Game.PACE_CLOSE_MIN - Game.PACE_OPEN_MIN) / Game.PACE_DAY_SECONDS))
	if m >= 60:
		return "%d h %02d min" % [m / 60, m % 60]
	return "%d min" % m

func _ledger_rule(col: Color) -> Control:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(640, 2)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## El sello de goma del día (tinta verde o roja), un poco torcido.
func _ledger_stamp(text: String, col: Color) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.06)
	sb.border_color = col
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 34, col, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER)
	pc.add_child(l)
	return pc
# --- end R4 PACE

# ------------------------------------------------------------------ subida de nivel

## --- R3 PAPER: un diploma: la gema, el nuevo título y lo que trae (dibujos de lo nuevo, sin frases).
func show_level_up(lv: int) -> void:
	Sfx.play("levelup", 0.0, -2.0)
	var p := PaperKit.panel("card", Vector2(64, 42))
	p.custom_minimum_size = Vector2(680, 0)
	var v := UIKit.vbox(10)
	p.add_child(v)
	var gem := UIKit.icon("res://assets/icons/emote_gem.png", 5.0)
	gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(gem)
	v.add_child(PaperKit.head("¡Renombre!", 42, PaperKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(PaperKit.hand(Game.level_name(lv), 60, Color("5b3a8c"), true, HORIZONTAL_ALIGNMENT_CENTER))
	var rw := _level_rewards(lv)
	if rw:
		v.add_child(PaperKit.ink_rule(480, Color(0.37, 0.28, 0.2, 0.3)))
		v.add_child(rw)
	v.add_child(PaperKit.gap(6))
	var b := PaperKit.button("¡Bien!", func(): close(), 36)
	b.custom_minimum_size = Vector2(220, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	PaperKit.decor(p, "paper_pin_brass", Vector2(0.5, 0.0), Vector2(-10, -12))
	PaperKit.attach(p, PaperKit.seal(str(lv), "paper_seal_gold", 3.0), Vector2(1, 1), Vector2(-96, -100))
	_open("levelup", p)

## Lo nuevo de un nivel de renombre: ingredientes del mercado, mejoras de Mabel y +1 cliente (si lo hay).
func _level_rewards(lv: int) -> Control:
	var h := UIKit.hbox(26)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in Data.INGREDIENT_ORDER:
		if int(Data.INGREDIENTS[id]["level"]) == lv:
			h.add_child(_reward_item(PaperKit.pic("res://assets/icons/ing_%s.png" % id, 4.0), String(Data.INGREDIENTS[id]["name"])))
	if String(Data.LEVEL_REWARDS.get(lv, "")).contains("cliente"):
		h.add_child(_reward_item(PaperKit.pic("paper_i_person", 6.0), "+1 cliente"))
	for u in Data.UPGRADE_ORDER:
		if int(Data.UPGRADES[u]["level"]) == lv:
			h.add_child(_reward_item(PaperKit.pic("paper_up_%s" % u, 4.0), String(Data.UPGRADES[u]["name"])))
	if h.get_child_count() == 0:
		var t := String(Data.LEVEL_REWARDS.get(lv, ""))
		if t == "":
			return null
		h.add_child(PaperKit.hand(t, 30, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER, 520))
	return h

func _reward_item(icon: Control, label: String) -> Control:
	var b := UIKit.vbox(2)
	b.custom_minimum_size = Vector2(130, 0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_child(icon)
	b.add_child(PaperKit.hand(label, 28, PaperKit.INK, true, HORIZONTAL_ALIGNMENT_CENTER, 150))
	return b

# ------------------------------------------------------------------ ajustes

## --- R3 PAPER: una tarjeta clavada: dos deslizadores con su icono, pantalla completa, Inicio y Cerrar.
func show_settings() -> void:
	var p := PaperKit.panel("card", Vector2(60, 40))
	p.custom_minimum_size = Vector2(620, 0)
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(PaperKit.head("Ajustes", 46, PaperKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	for s in [["paper_i_note", "music_volume", "Música"], ["paper_i_speaker", "sfx_volume", "Efectos"]]:
		var h := UIKit.hbox(16)
		v.add_child(h)
		var ic := PaperKit.pic(s[0], 5.0)
		ic.custom_minimum_size = Vector2(50, 50)
		ic.tooltip_text = s[2]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(ic)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Game.get(s[1])
		sl.custom_minimum_size = Vector2(420, 36)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		_paper_slider(sl)
		var key: String = s[1]
		sl.value_changed.connect(func(val):
			Game.set(key, val)
			Sfx.apply_volumes())
		h.add_child(sl)
	var fh := UIKit.hbox(16)
	v.add_child(fh)
	var si := PaperKit.pic("paper_i_screen", 5.0)
	si.custom_minimum_size = Vector2(50, 50)
	fh.add_child(si)
	var fs := CheckButton.new()
	fs.text = "Pantalla completa"
	fs.add_theme_font_override("font", PaperKit.font_hand_bold)
	fs.add_theme_font_size_override("font_size", 34)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		fs.add_theme_color_override(c, PaperKit.INK)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		fs.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.focus_mode = Control.FOCUS_NONE
	fs.toggled.connect(func(on):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	fh.add_child(fs)
	v.add_child(PaperKit.ink_rule(480, Color(0.37, 0.28, 0.2, 0.3)))
	var h2 := UIKit.hbox(16)
	h2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h2)
	var home := PaperKit.button("Inicio", func(): close(false); Game.save_game(); to_title.emit(), 32, "card", "paper_i_door")
	home.tooltip_text = "Guardar y volver al título"
	h2.add_child(home)
	h2.add_child(PaperKit.button("Cerrar", func(): Game.save_game(); close(), 32))
	PaperKit.decor(p, "paper_pin_blue", Vector2(0.5, 0.0), Vector2(-10, -12))
	_open("settings", p)

func _paper_slider(sl: HSlider) -> void:
	var tr := StyleBoxFlat.new()
	tr.bg_color = Color(0.37, 0.28, 0.2, 0.35)
	tr.set_corner_radius_all(4)
	tr.content_margin_top = 4
	tr.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", tr)
	var gr := StyleBoxFlat.new()
	gr.bg_color = PaperKit.HERB
	gr.set_corner_radius_all(4)
	gr.content_margin_top = 4
	gr.content_margin_bottom = 4
	sl.add_theme_stylebox_override("grabber_area", gr)
	sl.add_theme_stylebox_override("grabber_area_highlight", gr)

# ------------------------------------------------------------------ minijuego: remover

func show_stir(difficulty := 1.0) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(holder)
	close(false)
	current = "stir"
	current_node = holder
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(dim)
	var game := StirGame.new()
	game.speed = 1.6 + 0.3 * difficulty
	UIKit.place(game, Vector2(0.5, 0.5), Vector2(-180, -250), Vector2(360, 360))
	holder.add_child(game)
	var how := "A" if pad_hint != "" else "Clic o Espacio"   # --- R3 PAPER: una línea corta
	var info := UIKit.shadow(UIKit.label("¡Remueve!   %s en el dorado" % how, 28, UIKit.TEXT, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	UIKit.place(info, Vector2(0.5, 0.5), Vector2(-600, 130), Vector2(1200, 40))
	holder.add_child(info)
	holder.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game.press())
	game.finished.connect(func(perfect: bool):
		info.text = "¡Perfecto! +1 potencia" if perfect else "¡Bien!"   # --- R3 PAPER
		info.add_theme_color_override("font_color", UIKit.GOLD_BRIGHT if perfect else UIKit.TEXT)
		await get_tree().create_timer(0.7).timeout
		close(false)
		stir_done.emit(perfect))

func stir_key() -> void:
	if current == "stir" and current_node:
		for c in current_node.get_children():
			if c is StirGame:
				c.press()

func _input(ev: InputEvent) -> void:
	if current == "stir" and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE:
		stir_key()
		get_viewport().set_input_as_handled()

# --- R4 RANK: el Escalafón del Gremio de Boticarios de Arvendal (los papeles están en scripts/ui/rank_ui.gd) --------
## El tablón del Gremio: las 30 tiendas, su fila subrayada, flechas y la ficha de cada tienda (botón del HUD o G).
func show_ranking() -> void:
	Sfx.play("page", 0.05, -4.0)
	_open("ranking", RankUI.fit(RankUI.board(self)))

## La Gaceta del Gremio (llega cada 5 días con el correo). main.gd espera a que se cierre.
func show_gaceta() -> void:
	Sfx.play("page", 0.05, -3.0)
	_open("gaceta", RankUI.fit(RankUI.gaceta(self)))

## Los créditos del final del puesto 1. done: lo que pasa con «Seguir jugando» (Esc, Espacio o Intro también cierran;
## quien espera mira que current deje de ser "credits").
func show_credits(done := Callable()) -> void:
	_open("credits", RankUI.fit(RankUI.credits(self, func():
		if done.is_valid():
			done.call())))
	if current_node and current_node.get_child_count() > 0 and current_node.get_child(0) is ColorRect:
		current_node.get_child(0).color = Color(0.02, 0.01, 0.05, 0.9)
# --- end R4 RANK
