extends Control
class_name Hud
## --- SS CORE: la interfaz de juego, limpia y profesional ("taller de futuro usado"):
##   - UNA placa arriba al centro con lo que importa: el reloj (pantalla CRT ámbar), el día, los créditos, la cuota
##     del puerto (barra) y la fila. Nada de botones arriba al centro.
##   - Arriba a la derecha, un solo botón chico: el menú (Esc / Start).
##   - El aviso contextual sobre la persona o la estación: "[E] Repair" (la tecla del aparato en uso: E con teclado y
##     ratón, A con el mando).
##   - Los relojes de arena de la fila (paciencia) sobre las cabezas.
##   - Abajo: avisos cortos (toast) y la línea de controles; arriba, bajo la placa, el consejo del tutorial (etiqueta
##     de papel). Un cartel grande para los momentos del día ("Day 2", "Closing time").

signal menu_pressed
signal prompt_pressed      # un clic en el aviso "[E] ..." (= apretar la tecla)

const TOP_W := 700.0

var _plate: PanelContainer
var _clock: Label
var _clock_screen: PanelContainer
var _day: Label
var _place: Label
var _credits: Label
var _dues_bar: ProgressBar
var _dues_lbl: Label
var _line_box: HBoxContainer
var _line_lbl: Label
var _menu_btn: Button
var _hint_row: HBoxContainer
var _hint_plate: PanelContainer
var _hint_key := ""
var _toast: PanelContainer
var _toast_lbl: Label
var _toast_tw: Tween
var _tip: PanelContainer
var _tip_lbl: RichTextLabel
var _tip_tw: Tween
var _banner: Control
var _banner_title: Label
var _banner_sub: Label
var _banner_tw: Tween
var _banner_len := 0.0
var _prompt: PanelContainer
var _prompt_key := ""
var _prompt_fade := 1.0
var _chips := {}          # id -> PanelContainer
var _credits_shown := 0
var _credits_tw: Tween
var mode := "morning"      # "morning" | "open" | "closing" | "night"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build_top()
	_build_menu_button()
	_build_hint()
	_build_toast()
	_build_tip()
	_build_banner()
	Game.credits_changed.connect(func(_t, d): _on_credits(d))
	_credits_shown = Game.credits
	refresh()

# ------------------------------------------------------------------ la placa de arriba

func _build_top() -> void:
	_plate = PanelContainer.new()
	_plate.add_theme_stylebox_override("panel", _plate_style(14))
	UIKit.place(_plate, Vector2(0.5, 0.0), Vector2(-TOP_W / 2.0, 10), Vector2(TOP_W, 0), Control.GROW_DIRECTION_BOTH)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	var h := UIKit.hbox(16)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_plate.add_child(h)
	# el reloj: pantalla CRT ámbar
	_clock_screen = PanelContainer.new()
	var scr := UIKit.screen_style(10)
	scr.content_margin_top = 6
	scr.content_margin_bottom = 6
	scr.content_margin_left = 14
	scr.content_margin_right = 14
	_clock_screen.add_theme_stylebox_override("panel", scr)
	_clock = UIKit.label("9:00 AM", 24, UIKit.kit_color("screen9.png", "text", UIKit.SCREEN_TEXT), UIKit.font_mono, HORIZONTAL_ALIGNMENT_CENTER)
	_clock.custom_minimum_size = Vector2(118, 0)
	_clock_screen.add_child(_clock)
	h.add_child(_clock_screen)
	# el día y el lugar
	var dv := UIKit.vbox(-3)
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	_day = UIKit.label("DAY 1 OF 3", 14, Color(0.77, 0.81, 0.8), UIKit.font_bold)
	_place = UIKit.label("Starfall Market", 18, Color(0.93, 0.89, 0.78))
	dv.add_child(_day)
	dv.add_child(_place)
	dv.custom_minimum_size = Vector2(150, 0)
	h.add_child(dv)
	h.add_child(_sep())
	# los créditos
	var ch := UIKit.hbox(6)
	ch.add_child(UIKit.ui_icon("credits", 2.0))
	_credits = UIKit.label("0", 26, Color(0.98, 0.93, 0.78), UIKit.font_bold)
	_credits.custom_minimum_size = Vector2(56, 0)
	ch.add_child(_credits)
	h.add_child(ch)
	h.add_child(_sep())
	# la cuota del puerto (dock dues): barra + número
	var dvv := UIKit.vbox(2)
	dvv.alignment = BoxContainer.ALIGNMENT_CENTER
	var dh := UIKit.hbox(6)
	dh.add_child(UIKit.label("DUES", 13, Color(0.77, 0.81, 0.8), UIKit.font_bold))
	_dues_lbl = UIKit.label("0 / 300", 13, Color(0.93, 0.89, 0.78), UIKit.font_bold)
	dh.add_child(_dues_lbl)
	dvv.add_child(dh)
	_dues_bar = ProgressBar.new()
	_dues_bar.max_value = 1.0
	_dues_bar.step = 0.001
	_dues_bar.show_percentage = false
	_dues_bar.custom_minimum_size = Vector2(120, 10)
	_dues_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dvv.add_child(_dues_bar)
	h.add_child(dvv)
	# la fila (solo con la tienda abierta)
	_line_box = UIKit.hbox(6)
	_line_box.add_child(_sep())
	_line_box.add_child(UIKit.ui_icon("sandtimer", 2.0))
	_line_lbl = UIKit.label("0/4", 22, Color(0.98, 0.93, 0.78), UIKit.font_bold)
	_line_box.add_child(_line_lbl)
	h.add_child(_line_box)

func _sep() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.6, 0.66, 0.64, 0.35)
	c.custom_minimum_size = Vector2(2, 34)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _plate_style(margin: int) -> StyleBox:
	var sb := UIKit.nine("plate9.png", margin, 12)
	if sb:
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		return sb
	return UIKit.panel_style(UIKit.BG, UIKit.STEEL, 2, 4, margin)

func _build_menu_button() -> void:
	_menu_btn = Button.new()
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.text = "Menu"
	_menu_btn.tooltip_text = "Pause, volume, quit"
	_menu_btn.add_theme_font_size_override("font_size", 18)
	_menu_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UIKit.place(_menu_btn, Vector2(1.0, 0.0), Vector2(-132, 14), Vector2(118, 46), Control.GROW_DIRECTION_BEGIN)
	_menu_btn.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		menu_pressed.emit())
	add_child(_menu_btn)

## Muestra u oculta la placa de arriba y el botón de menú (el título y las pantallas grandes la esconden).
func show_top(on: bool) -> void:
	_plate.visible = on
	_menu_btn.visible = on

## --- SS MERGE: el banco, el regateo y la cápsula tapan casi toda la pantalla y su placa asomaba por arriba, a
## medias: mientras están abiertos la placa y el menú se apagan (sin tocar show_top).
func set_covered(on: bool) -> void:
	var a := 0.0 if on else 1.0
	if _plate.modulate.a != a:
		_plate.modulate.a = a
		_menu_btn.modulate.a = a

# ------------------------------------------------------------------ datos

func refresh() -> void:
	_day.text = "DAY %d OF %d" % [Game.day, Data.DAYS]
	_set_credits_text(Game.credits)
	_dues_bar.value = Game.dues_progress()
	_dues_lbl.text = "%s / %s" % [UIKit.num(Game.credits), UIKit.num(Game.dues_goal)]
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.GOOD if Game.dues_met() else UIKit.ACCENT
	fill.set_corner_radius_all(3)
	_dues_bar.add_theme_stylebox_override("fill", fill)

func _set_credits_text(n: int) -> void:
	_credits.text = UIKit.num(n)

func _on_credits(delta: int) -> void:
	refresh()
	if delta == 0:
		_credits_shown = Game.credits
		return
	# el número cuenta hasta el nuevo valor y parpadea (verde gana, rojo gasta)
	if _credits_tw and _credits_tw.is_valid():
		_credits_tw.kill()
	_credits_tw = create_tween()
	var from := _credits_shown
	_credits_shown = Game.credits
	_credits_tw.tween_method(func(v: float): _set_credits_text(int(round(v))), float(from), float(Game.credits), 0.45)
	_credits.add_theme_color_override("font_color", UIKit.GOOD if delta > 0 else UIKit.BAD)
	_credits_tw.tween_callback(func(): _credits.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78)))

## El reloj. mode: "morning" (sin reloj: dice MORNING), "open" (la hora), "closing" (6:00 PM), "night".
func set_clock(minutes: int, m := "open") -> void:
	mode = m
	match m:
		"morning":
			_clock.text = "MORNING"
		"night":
			_clock.text = "NIGHT"
		_:
			_clock.text = clock_text(minutes)
	_place.text = {"morning": "Starfall Market", "open": "Open for business", "closing": "Closing time",
		"night": "The ledger"}.get(m, "Rustwater")
	_line_box.visible = m == "open" or m == "closing"

static func clock_text(minutes: int) -> String:
	var m5 := (minutes / 5) * 5
	var h24 := (m5 / 60) % 24
	var h := h24 % 12
	if h == 0:
		h = 12
	return "%d:%02d %s" % [h, m5 % 60, "AM" if h24 < 12 else "PM"]

func set_line(n: int, max_n: int) -> void:
	_line_lbl.text = "%d/%d" % [n, max_n]
	_line_lbl.add_theme_color_override("font_color", UIKit.BAD if n >= max_n else Color(0.98, 0.93, 0.78))

# ------------------------------------------------------------------ la línea de controles (abajo a la izquierda)

func _build_hint() -> void:
	# una placa oscura translúcida detrás (sobre la arena clara del mercado el texto blanco no se leía)
	_hint_plate = PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.07, 0.06, 0.05, 0.62), Color(0, 0, 0, 0), 0, 6, 10)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.shadow_size = 0
	_hint_plate.add_theme_stylebox_override("panel", sb)
	_hint_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(_hint_plate, Vector2(0, 1), Vector2(14, -56), Vector2(10, 42), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	add_child(_hint_plate)
	_hint_row = UIKit.hbox(8)
	_hint_plate.add_child(_hint_row)
	_hint_plate.visible = false

## La línea de controles según el aparato: "[A][D] Walk  [E] Use  [Esc] Menu" o "(Stick) Walk  (A) Use  (Start) Menu".
## extra: un texto al final (p. ej. la ayuda de sonido de la web).
func set_hint(walking: bool, extra := "") -> void:
	var pad := PadCursor.pad_in_use
	var key := "%s|%s|%s" % [walking, pad, extra]
	if key == _hint_key:
		return
	_hint_key = key
	for c in _hint_row.get_children():
		_hint_row.remove_child(c)
		c.queue_free()
	if walking:
		if pad:
			_hint_pair(["Stick"], "Walk")
			_hint_pair(["A"], "Use")
			_hint_pair(["LB"], "Point")
			_hint_pair(["Start"], "Menu")
		else:
			_hint_pair(["A", "D"], "Walk")
			_hint_pair(["E"], "Use")
			_hint_pair(["Esc"], "Menu")
	if extra != "":
		_hint_row.add_child(UIKit.shadow(UIKit.label(extra, UIKit.FS_SMALL, UIKit.MUTED)))
	elif _hint_row.get_child_count() > 0 and not (_hint_row.get_child(-1) is Label):
		var last := _hint_row.get_child(-1)    # sin el hueco final: la placa queda pareja a los dos lados
		_hint_row.remove_child(last)
		last.queue_free()
	_hint_plate.visible = walking or extra != ""
	_hint_plate.reset_size()

func _hint_pair(keys: Array, what: String) -> void:
	for k in keys:
		_hint_row.add_child(UIKit.keycap(k, 16))
	var l := UIKit.label(what, 16, Color(0.95, 0.92, 0.85), UIKit.font_bold)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_row.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 1)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.add_child(gap)

# ------------------------------------------------------------------ el aviso contextual

## El aviso "[E] Verbo" sobre un punto de la pantalla (abajo al centro del aviso = el punto). verb "" = sin aviso.
## enabled false: sin tecla, apagado (p. ej. "No one at the counter"). walking: medio transparente mientras camina.
func show_prompt(at: Vector2, verb: String, enabled := true, walking := false) -> void:
	if verb == "":
		hide_prompt()
		return
	var key := "%s|%s|%s" % [verb, enabled, UIKit.interact_key()]
	if key != _prompt_key or _prompt == null:
		_prompt_key = key
		if _prompt:
			_prompt.queue_free()
		if enabled:
			_prompt = UIKit.prompt("", verb, 20)
			# el aviso también se puede tocar con el ratón (o con el cursor del mando)
			_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
			_prompt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			_prompt.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					accept_event()
					prompt_pressed.emit())
		else:
			_prompt = _info_tag(verb)
		add_child(_prompt)
		_prompt.reset_size()
		_prompt.modulate.a = 0.0
	var target := 0.7 if walking else 1.0
	if _banner.modulate.a > 0.02:
		target = 0.0    # el cartel del día ("Day 2", "Open!") pasa por la misma altura: el aviso espera a que se vaya
	_prompt.modulate.a = lerpf(_prompt.modulate.a, target, 0.35)
	var sz := _prompt.get_combined_minimum_size()
	var p := (at - Vector2(sz.x / 2.0, sz.y)).round()
	var vr := get_viewport_rect()
	p.x = clampf(p.x, 8.0, vr.size.x - sz.x - 8.0)
	p.y = clampf(p.y, 96.0, vr.size.y - sz.y - 60.0)
	_prompt.position = p

func hide_prompt() -> void:
	if _prompt:
		_prompt.queue_free()
		_prompt = null
	_prompt_key = ""

func prompt_visible() -> bool:
	return _prompt != null

func _info_tag(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.07, 0.06, 0.05, 0.72), Color(0.5, 0.48, 0.44), 1, 5, 8)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.shadow_size = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UIKit.label(text, 18, Color(0.85, 0.82, 0.76), UIKit.font_bold))
	return p

# ------------------------------------------------------------------ los relojes de arena de la fila

## El reloj de arena de alguien (p = paciencia 0..1) sobre su cabeza (at = punto de pantalla). Verde, ámbar, rojo.
func set_chip(id: int, at: Vector2, p: float, visible_now := true) -> void:
	var c: PanelContainer = _chips.get(id)
	if c == null:
		c = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.05, 0.78)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 4
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		c.add_theme_stylebox_override("panel", sb)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UIKit.hbox(3)
		h.add_child(UIKit.ui_icon("sandtimer", 1.5))
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(38, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(bar)
		c.add_child(h)
		add_child(c)
		move_child(c, 0)   # debajo del aviso y de los textos
		_chips[id] = c
	c.visible = visible_now
	if not visible_now:
		return
	var bar2: ProgressBar = c.find_child("Bar", true, false)
	bar2.value = p
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.GOOD if p > 0.5 else (UIKit.ACCENT if p > 0.25 else UIKit.BAD)
	fill.set_corner_radius_all(3)
	bar2.add_theme_stylebox_override("fill", fill)
	var sz := c.get_combined_minimum_size()
	var pos := at - Vector2(sz.x / 2.0, sz.y)
	if p < 0.25:
		pos.x += sin(Time.get_ticks_msec() / 28.0) * 2.0   # tiembla cuando se acaba
	c.position = pos.round()

func remove_chip(id: int) -> void:
	var c: PanelContainer = _chips.get(id)
	if c:
		c.queue_free()
	_chips.erase(id)

func clear_chips() -> void:
	for id in _chips:
		(_chips[id] as Node).queue_free()
	_chips = {}

# ------------------------------------------------------------------ avisos, consejos y carteles

func _build_toast() -> void:
	_toast = PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.07, 0.06, 0.05, 0.88), UIKit.ACCENT, 1, 6, 14)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_toast.add_theme_stylebox_override("panel", sb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(_toast, Vector2(0.5, 1.0), Vector2(-330, -118), Vector2(660, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_toast_lbl = UIKit.label("", UIKit.FS_BODY, UIKit.TEXT, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_child(_toast_lbl)
	_toast.modulate.a = 0.0
	add_child(_toast)

## Un aviso corto abajo al centro (sube un poco y se va).
func toast(msg: String, col := UIKit.TEXT, secs := 2.6) -> void:
	_toast_lbl.text = msg
	_toast_lbl.add_theme_color_override("font_color", col)
	# --- SS SHIP: con autowrap y sin ancho mínimo, reset_size() dejaba el aviso de UNA letra de ancho (una columna de
	# letras a la izquierda). Ahora: una línea si cabe, si no un ancho fijo con salto de palabra; y centrado abajo.
	var f: Font = _toast_lbl.get_theme_font("font")
	var fs: int = _toast_lbl.get_theme_font_size("font_size")
	var tw: float = f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f else 9999.0
	var one := tw <= TOAST_MAX_W
	_toast_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF if one else TextServer.AUTOWRAP_WORD_SMART
	_toast_lbl.custom_minimum_size = Vector2(0.0 if one else TOAST_MAX_W, 0.0)
	_toast.reset_size()
	_fit_toast()
	_fit_toast.call_deferred()
	# --- end SS SHIP
	if _toast_tw and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tw.tween_interval(secs)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

# --- SS SHIP: el aviso centrado abajo, con el borde de abajo 118 px sobre el borde de la pantalla (como antes)
const TOAST_MAX_W := 620.0
func _fit_toast() -> void:
	var sz := _toast.get_combined_minimum_size()
	_toast.offset_left = -sz.x * 0.5
	_toast.offset_right = sz.x * 0.5
	_toast.offset_top = -118.0 - sz.y
	_toast.offset_bottom = -118.0

func toast_text() -> String:
	return _toast_lbl.text if _toast.modulate.a > 0.05 else ""

func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UIKit.tag_style(10))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(_tip, Vector2(0.5, 0.0), Vector2(-320, 96), Vector2(640, 0), Control.GROW_DIRECTION_BOTH)
	_tip_lbl = UIKit.rich(21)
	_tip_lbl.add_theme_color_override("default_color", UIKit.kit_color("tag9.png", "text", UIKit.INK))
	_tip_lbl.add_theme_font_override("normal_font", UIKit.font_bold)
	_tip_lbl.add_theme_font_override("bold_font", UIKit.font_bold)
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_lbl.custom_minimum_size = Vector2(560, 0)
	_tip.add_child(_tip_lbl)
	_tip.modulate.a = 0.0
	_tip.visible = false
	add_child(_tip)

## El consejo del tutorial: una etiqueta de papel bajo la placa de arriba. secs <= 0: queda hasta clear_tip().
func tip(text: String, secs := 7.0) -> void:
	_tip_lbl.text = "[center]%s[/center]" % text
	_tip.visible = true
	_tip.reset_size()
	if _tip_tw and _tip_tw.is_valid():
		_tip_tw.kill()
	_tip_tw = create_tween()
	# con el cartel del día en pantalla ("Day 1"), el consejo espera a que se vaya: uno por vez
	if _banner_tw and _banner_tw.is_valid() and _banner_tw.is_running():
		var left := _banner_len - _banner_tw.get_total_elapsed_time() - 0.3
		if left > 0.0:
			_tip.modulate.a = 0.0
			_tip_tw.tween_interval(left)
	_tip_tw.tween_property(_tip, "modulate:a", 1.0, 0.25)
	if secs > 0.0:
		_tip_tw.tween_interval(secs)
		_tip_tw.tween_property(_tip, "modulate:a", 0.0, 0.5)
		_tip_tw.tween_callback(func(): _tip.visible = false)

func clear_tip() -> void:
	if _tip_tw and _tip_tw.is_valid():
		_tip_tw.kill()
	_tip.modulate.a = 0.0
	_tip.visible = false

func tip_text() -> String:
	return _tip_lbl.text if _tip.visible else ""

func _build_banner() -> void:
	_banner = Control.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	# una cinta oscura detrás (se lee igual sobre la arena clara y sobre el taller)
	var rib := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.06, 0.04, 0.03, 0.0), Color(0.06, 0.04, 0.03, 0.62), Color(0.06, 0.04, 0.03, 0.62), Color(0.06, 0.04, 0.03, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	rib.texture = gt
	rib.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rib.stretch_mode = TextureRect.STRETCH_SCALE
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(rib, Vector2(0.5, 0.36), Vector2(-480, -66), Vector2(960, 132))
	_banner.add_child(rib)
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(v, Vector2(0.5, 0.36), Vector2(-400, -60), Vector2(800, 120), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_banner.add_child(v)
	_banner_title = UIKit.label("", 54, Color(1.0, 0.8, 0.42), UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_title.add_theme_color_override("font_outline_color", Color(0.14, 0.09, 0.06))
	_banner_title.add_theme_constant_override("outline_size", 14)
	_banner_sub = UIKit.label("", 24, Color(1.0, 0.97, 0.9), UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.add_theme_color_override("font_outline_color", Color(0.14, 0.09, 0.06))
	_banner_sub.add_theme_constant_override("outline_size", 10)
	v.add_child(_banner_title)
	v.add_child(_banner_sub)
	_banner.modulate.a = 0.0

## Un cartel grande en el centro (el día que empieza, la hora de cerrar).
func banner(title: String, sub := "", secs := 2.2) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner.scale = Vector2.ONE
	_banner_tw = create_tween()
	_banner_len = 0.3 + secs + 0.5
	_banner_tw.tween_property(_banner, "modulate:a", 1.0, 0.3)
	_banner_tw.tween_interval(secs)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.5)

## Esconde el cartel ya (se abrió una ventana encima).
func hide_banner() -> void:
	if _banner.modulate.a <= 0.0:
		return
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner_tw = create_tween()
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.15)

## Monedas que vuelan de un punto de la pantalla a los créditos de arriba.
func fly_coins(from: Vector2, n := 5) -> void:
	var to := _credits.get_global_rect().get_center()
	for i in n:
		var c := UIKit.ui_icon("credits", 2.0)
		c.size = c.custom_minimum_size
		c.position = from + Vector2(randf_range(-18, 18), randf_range(-10, 10)) - c.size / 2.0
		add_child(c)
		var tw := c.create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(c, "position", to - c.size / 2.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "scale", Vector2(0.7, 0.7), 0.55)
		tw.tween_callback(c.queue_free)
