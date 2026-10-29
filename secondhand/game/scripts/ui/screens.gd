extends Control
class_name Screens
## --- SS CORE: las pantallas grandes del prototipo (sobre el escenario 3D, que sigue vivo detrás):
##   title    el logo, Continue / New game / Settings
##   intro    3 frases cortas sobre el anillo de restos y la lluvia de chatarra (se saltan con una tecla o un clic)
##   ledger   el libro de cuentas de la noche (reparaciones, ventas, créditos, piezas, paciencia, reputación, la
##            cuota) a la derecha; a la izquierda se ve la ventana con la lluvia de chatarra
##   closing  el día de la cuota: pagada o no, lo hecho en los 3 días, "Thanks for playing the prototype"
## Teclas: E / Intro / Espacio = la opción principal; Esc = la otra (título: nada). Ratón y mando (A) igual.

signal title_choice(id: String)    # "continue" | "new" | "settings"
signal intro_done
signal ledger_done
signal closing_choice(id: String)  # "again" | "title"

var current := ""          # "" | "title" | "intro" | "ledger" | "closing"
var _root: Control
var _primary := ""
var _secondary := ""
var _intro_lines: Array = []
var _intro_i := 0
var _intro_lbl: Label
var _intro_tw: Tween
var _intro_t := 0.0
var _confirm_new := false
var _new_btn: Button
var suspended := false     # una ventana encima (los ajustes desde el título): no se ve ni escucha teclas

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	visible = false

func is_open() -> bool:
	return current != ""

## Esconde la pantalla actual mientras hay una ventana encima (y la vuelve a mostrar).
func suspend(on: bool) -> void:
	suspended = on
	if _root:
		_root.visible = not on

func hide_all() -> void:
	suspended = false
	current = ""
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _intro_tw and _intro_tw.is_valid():
		_intro_tw.kill()
	for c in get_children():
		c.queue_free()
	_root = null

func _begin(which: String, block_mouse := true) -> void:
	hide_all()
	current = which
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP if block_mouse else Control.MOUSE_FILTER_IGNORE
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

## Elige como si se apretara el botón (el bot y las pruebas).
func press(id: String) -> void:
	match current:
		"title":
			title_choice.emit(id)
		"intro":
			_end_intro()
		"ledger":
			hide_all()
			ledger_done.emit()
		"closing":
			hide_all()
			closing_choice.emit(id)

# ------------------------------------------------------------------ botones (los de la placa: teclas de ART)

func _button(text: String, primary: bool, cb: Callable, w := 240.0, key := "") -> Control:
	var h := UIKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	if key != "":
		var kc := UIKit.keycap(key, 16)
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kc)
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(w, 54)
	if primary:
		for pair in [["normal", "btn_primary9.png"], ["hover", "btn_primary_hover9.png"], ["pressed", "btn_primary_pressed9.png"]]:
			var sb := UIKit.nine(pair[1], 12, 15)
			if sb:
				b.add_theme_stylebox_override(pair[0], sb)
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	h.add_child(b)
	h.set_meta("button", b)
	return h

func _outlined(text: String, size: int, col: Color, outline := 10, font: Font = null) -> Label:
	var l := UIKit.label(text, size, col, font if font else UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.06))
	l.add_theme_constant_override("outline_size", outline)
	return l

func _light_plate(pad := 30) -> StyleBox:
	var sb := UIKit.nine("plate_light9.png", 22, 12)
	if sb:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = pad - 6
		sb.content_margin_bottom = pad - 6
		return sb
	return UIKit.panel_style(Color(0.85, 0.79, 0.66, 0.98), Color(0.45, 0.4, 0.34), 2, 4, pad)

const INK := Color(0.165, 0.125, 0.14)
const INK_SOFT := Color(0.33, 0.28, 0.25)

func _ink(text: String, size := 20, font: Font = null, col := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return UIKit.label(text, size, col, font if font else UIKit.font_regular, align)

# ------------------------------------------------------------------ el título

func show_title(can_continue: bool) -> void:
	_begin("title", false)
	_confirm_new = false
	# un velo suave arriba para que el logo se lea sobre el cielo
	var veil := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.1, 0.05, 0.03, 0.42), Color(0.1, 0.05, 0.03, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 64
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	UIKit.place(veil, Vector2(0, 0), Vector2(0, 0), Vector2(0, 300))
	veil.anchor_right = 1.0
	veil.offset_right = 0
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)
	if ResourceLoader.exists("res://assets/ui/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/ui/logo.png")
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		UIKit.place(logo, Vector2(0.5, 0.0), Vector2(-301, 26), Vector2(603, 196), Control.GROW_DIRECTION_BOTH)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(logo)
	else:
		var t := _outlined("SECONDHAND STARS", 64, Color(1.0, 0.8, 0.4), 14)
		UIKit.place(t, Vector2(0.5, 0.0), Vector2(-400, 60), Vector2(800, 90), Control.GROW_DIRECTION_BOTH)
		_root.add_child(t)
	var tag := _outlined("A junk-and-repair shop on a desert spaceport", 22, Color(1.0, 0.95, 0.86), 8)
	UIKit.place(tag, Vector2(0.5, 0.0), Vector2(-400, 226), Vector2(800, 30), Control.GROW_DIRECTION_BOTH)
	_root.add_child(tag)
	var v := UIKit.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(v, Vector2(0.5, 0.0), Vector2(-170, 330), Vector2(340, 200), Control.GROW_DIRECTION_BOTH)
	_root.add_child(v)
	var ik := UIKit.interact_key()
	if can_continue:
		v.add_child(_button("Continue", true, func(): title_choice.emit("continue"), 240, ik))
		var nb := _button("New game", false, func(): _new_pressed(), 240, "N")
		_new_btn = nb.get_meta("button")
		v.add_child(nb)
		_primary = "continue"
	else:
		var nb2 := _button("New game", true, func(): title_choice.emit("new"), 240, ik)
		_new_btn = nb2.get_meta("button")
		v.add_child(nb2)
		_primary = "new"
	v.add_child(_button("Settings", false, func(): title_choice.emit("settings"), 240, "S"))
	var foot := _outlined("A prototype  ·  keyboard, mouse or pad", 17, Color(1.0, 0.95, 0.86), 6, UIKit.font_regular)
	UIKit.place(foot, Vector2(0.5, 1.0), Vector2(-300, -46), Vector2(600, 26), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_root.add_child(foot)

func _new_pressed() -> void:
	if not _confirm_new:
		_confirm_new = true
		if _new_btn:
			_new_btn.text = "Start over?"
		get_tree().create_timer(3.0).timeout.connect(func():
			_confirm_new = false
			if is_instance_valid(_new_btn):
				_new_btn.text = "New game")
		return
	title_choice.emit("new")

# ------------------------------------------------------------------ la introducción

func show_intro(lines: Array) -> void:
	_begin("intro")
	_intro_lines = lines.duplicate()
	_intro_i = -1
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_next_line())
	_root.add_child(shade)
	# una sombra abajo: el texto se lee sobre las casas
	var low := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.02, 0.01, 0.04, 0.0), Color(0.02, 0.01, 0.04, 0.78)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	low.texture = gt
	low.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	low.stretch_mode = TextureRect.STRETCH_SCALE
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(low, Vector2(0, 1), Vector2(0, -300), Vector2(1280, 300), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	low.anchor_right = 1.0
	low.offset_right = 0
	_root.add_child(low)
	_intro_lbl = _outlined("", 30, Color(1.0, 0.95, 0.86), 10, UIKit.font_bold)
	_intro_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.place(_intro_lbl, Vector2(0.5, 1.0), Vector2(-430, -210), Vector2(860, 110), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_intro_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_intro_lbl)
	var skip := UIKit.hbox(8)
	skip.add_child(UIKit.keycap(UIKit.interact_key(), 16))
	skip.add_child(UIKit.shadow(UIKit.label("Next", 16, Color(1, 0.95, 0.86), UIKit.font_bold)))
	skip.add_child(UIKit.keycap("B" if PadCursor.pad_in_use else "Esc", 16))
	skip.add_child(UIKit.shadow(UIKit.label("Skip", 16, Color(1, 0.95, 0.86), UIKit.font_bold)))
	UIKit.place(skip, Vector2(1.0, 1.0), Vector2(-250, -52), Vector2(230, 32), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	skip.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(skip)
	_next_line()

func _next_line() -> void:
	if current != "intro":
		return
	_intro_i += 1
	if _intro_i >= _intro_lines.size():
		_end_intro()
		return
	_intro_t = 0.0
	if _intro_tw and _intro_tw.is_valid():
		_intro_tw.kill()
	_intro_lbl.text = String(_intro_lines[_intro_i])
	_intro_lbl.modulate.a = 0.0
	_intro_tw = create_tween()
	_intro_tw.tween_property(_intro_lbl, "modulate:a", 1.0, 0.7)
	_intro_tw.tween_interval(3.4)
	_intro_tw.tween_property(_intro_lbl, "modulate:a", 0.0, 0.6)
	_intro_tw.tween_callback(_next_line)

func _end_intro() -> void:
	if current != "intro":
		return
	hide_all()
	intro_done.emit()

# ------------------------------------------------------------------ el libro de cuentas (de noche)

## s: el resumen del día (Game.close_day()). last: es el último día (el botón lleva a la cuota).
## Compacto (entra entero en 1280x720) y a la derecha: a la izquierda se ve la ventana con la lluvia de chatarra.
func show_ledger(s: Dictionary, last: bool) -> void:
	_begin("ledger")
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.18)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _light_plate(28))
	UIKit.place(panel, Vector2(1.0, 0.5), Vector2(-584, 0), Vector2(548, 0), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH)
	_root.add_child(panel)
	var v := UIKit.vbox(6)
	panel.add_child(v)
	var head := UIKit.hbox(10)
	var hic := UIKit.ui_icon("ledger", 2.5)
	hic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hic)
	var hv := UIKit.vbox(-4)
	hv.add_child(_ink("NIGHT %d OF %d" % [int(s.get("day", 1)), Data.DAYS], 14, UIKit.font_bold, INK_SOFT))
	hv.add_child(_ink("The ledger", 28, UIKit.font_bold))
	head.add_child(hv)
	v.add_child(head)
	v.add_child(_rule())
	var reps := int(s.get("repairs", 0))
	var avg := float(s.get("avg_stars_x10", 0)) / 10.0
	var served := reps + int(s.get("sales", 0))
	var lost := int(s.get("patience_lost", 0))
	_ledger_row(v, "wrench", "Repairs", "%d" % reps, ("avg %.1f ★" % avg) if reps > 0 else "")
	_ledger_row(v, "credits", "Sales", "%d" % int(s.get("sales", 0)),
		("%d refurbished" % int(s.get("refurbished", 0))) if int(s.get("refurbished", 0)) > 0 else "")
	_ledger_row(v, "star", "Customers served", "%d of %d" % [served, int(s.get("arrived", 0))], "")
	_ledger_row(v, "sandtimer", "Patience lost", "%d" % lost, "left unhappy" if lost > 0 else "nobody walked out", Color(0.62, 0.22, 0.16) if lost > 0 else INK)
	_ledger_row(v, "pod", "Parts used", "%d" % int(s.get("parts_used", 0)), ("%d pod%s bought" % [int(s.get("pods", 0)), "" if int(s.get("pods", 0)) == 1 else "s"]) if int(s.get("pods", 0)) > 0 else "")
	v.add_child(_rule())
	_ledger_row(v, "credits", "Earned", "+%s cr" % UIKit.num(int(s.get("earned", 0))),
		("incl. %d in tips" % int(s.get("tips", 0))) if int(s.get("tips", 0)) > 0 else "", Color(0.2, 0.42, 0.14))
	_ledger_row(v, "credits", "Spent", "-%s cr" % UIKit.num(int(s.get("spent", 0))), "pods & parts", Color(0.62, 0.22, 0.16))
	var rd := int(s.get("rep_delta", 0))
	_ledger_row(v, "rep", "Reputation", ("%+d" % rd), "total %d" % int(s.get("rep", 0)))
	v.add_child(_rule())
	# la cuota del puerto
	var dues := int(s.get("dues", Data.DUES_GOAL))
	var cr := int(s.get("credits", 0))
	var dh := UIKit.hbox(10)
	dh.add_child(_ink("Dock dues", 19, UIKit.font_bold))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dh.add_child(spacer)
	dh.add_child(_ink("%s / %s cr" % [UIKit.num(cr), UIKit.num(dues)], 19, UIKit.font_bold))
	v.add_child(dh)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(float(cr) / float(maxi(1, dues)), 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.GOOD.darkened(0.15) if cr >= dues else UIKit.ACCENT.darkened(0.1)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	var left := Data.DAYS - int(s.get("day", 1))
	var dues_note := ""
	if cr >= dues:
		dues_note = "Covered! Anything more is yours."
	elif left > 0:
		dues_note = "%s cr to go, %s left." % [UIKit.num(dues - cr), UIKit.plural(left, "day")]
	else:
		dues_note = "Short by %s cr." % UIKit.num(dues - cr)
	v.add_child(_ink(dues_note, 16, UIKit.font_bold, INK_SOFT))
	# el cartel: ¿se encendió una punta? + el botón
	var bh := UIKit.hbox(12)
	var sp := int(s.get("sign_points", 0))
	var star := UIKit.icon("res://assets/props/star_sign_%d.png" % clampi(sp, 0, 5), 0.75)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(star)
	var good := bool(s.get("good", false))
	var msg := ("A good day! The sign lights a point." if good else "A quiet day. The sign stays as it was.")
	var ml := _ink(msg, 17, UIKit.font_bold, Color(0.5, 0.32, 0.06) if good else INK_SOFT)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(ml)
	_primary = "next"
	var btn := _button("Pay the dues" if last else "Sleep", true, func(): press("next"), 170, UIKit.interact_key())
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(btn)
	v.add_child(bh)
	UIKit.pop_in(panel)
	# lo que se ve por la ventana: una línea abajo a la izquierda
	var hint := _outlined("Tonight's starfall is tomorrow's pods.", 19, Color(1.0, 0.93, 0.8), 6, UIKit.font_bold)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UIKit.place(hint, Vector2(0, 1), Vector2(32, -62), Vector2(560, 28), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	_root.add_child(hint)

func _rule() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.35, 0.28, 0.22, 0.35)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _ledger_row(v: VBoxContainer, icon: String, what: String, value: String, note := "", col := INK) -> void:
	var h := UIKit.hbox(10)
	var ic := UIKit.ui_icon(icon, 1.5)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := _ink(what, 18, UIKit.font_bold)
	l.custom_minimum_size = Vector2(176, 0)
	h.add_child(l)
	var n := _ink(note, 15, UIKit.font_bold, INK_SOFT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(_ink(value, 19, UIKit.font_bold, col, HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(h)

# ------------------------------------------------------------------ el cierre (el día de la cuota)

func show_closing(t: Dictionary) -> void:
	_begin("closing")
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _light_plate(34))
	_root.add_child(UIKit.center(panel))
	var v := UIKit.vbox(10)
	v.custom_minimum_size = Vector2(640, 0)
	panel.add_child(v)
	var paid := bool(t.get("dues_met", false))
	v.add_child(_ink("DUES DAY", 16, UIKit.font_bold, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var big := _ink("Dues paid!" if paid else "Short by %s cr" % UIKit.num(Data.DUES_GOAL - int(t.get("credits", 0))), 40,
		UIKit.font_bold, Color(0.22, 0.45, 0.16) if paid else Color(0.6, 0.22, 0.14), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(big)
	var story := ("The landlord counts the credits twice, grumbles, and leaves. The Secondhand Star stays open." if paid
		else "The landlord sighs. \"One more week, Nell. One.\" The Secondhand Star lives to fix another day.")
	var sl := _ink(story, 19, UIKit.font_regular, INK, HORIZONTAL_ALIGNMENT_CENTER)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(600, 0)
	v.add_child(sl)
	v.add_child(_rule())
	var mid := UIKit.hbox(26)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	var sv := UIKit.vbox(2)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_child(UIKit.icon("res://assets/props/star_sign_%d.png" % clampi(int(t.get("sign_points", 0)), 0, 5), 1.5))
	sv.add_child(_ink(UIKit.plural(int(t.get("good_days", 0)), "good day"), 17, UIKit.font_bold, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	mid.add_child(sv)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	var reps := int(t.get("repairs", 0))
	var rows := [
		["Repairs", "%d" % reps],
		["Average", ("%.1f ★" % (float(t.get("stars", 0)) / float(maxi(1, reps)))) if reps > 0 else "-"],
		["Sales", "%d" % int(t.get("sales", 0))],
		["Credits earned", "%s cr" % UIKit.num(int(t.get("earned", 0)))],
		["Credits now", "%s cr" % UIKit.num(int(t.get("credits", 0)))],
		["Reputation", "%d" % int(t.get("rep", 0))],
	]
	if int(t.get("best_day", 0)) > 0:
		rows.append(["Best day", "Day %d (%+d cr)" % [int(t.get("best_day", 0)), int(t.get("best_net", 0))]])
	for r in rows:
		grid.add_child(_ink(r[0], 18, UIKit.font_bold, INK_SOFT))
		grid.add_child(_ink(r[1], 19, UIKit.font_bold, INK, HORIZONTAL_ALIGNMENT_RIGHT))
	mid.add_child(grid)
	v.add_child(mid)
	v.add_child(_rule())
	v.add_child(_ink("Thanks for playing the prototype!", 26, UIKit.font_bold, Color(0.55, 0.33, 0.06), HORIZONTAL_ALIGNMENT_CENTER))
	var bh := UIKit.hbox(16)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	_primary = "again"
	_secondary = "title"
	bh.add_child(_button("Play again", true, func(): press("again"), 200, UIKit.interact_key()))
	bh.add_child(_button("Title", false, func(): press("title"), 160, "B" if PadCursor.pad_in_use else "Esc"))
	v.add_child(bh)
	UIKit.pop_in(panel)

# ------------------------------------------------------------------ teclado

func _input(ev: InputEvent) -> void:
	if current == "" or suspended or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode
	var ok := k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE
	var handled := true
	match current:
		"title":
			if ok:
				title_choice.emit(_primary)
			elif k == KEY_N:
				_new_pressed()
			elif k == KEY_S:
				title_choice.emit("settings")
			else:
				handled = false
		"intro":
			if k == KEY_ESCAPE:
				_end_intro()
			elif ok:
				_next_line()
			else:
				handled = false
		"ledger":
			if ok:
				press("next")
			else:
				handled = false
		"closing":
			if ok:
				press("again")
			elif k == KEY_ESCAPE:
				press("title")
			else:
				handled = false
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
