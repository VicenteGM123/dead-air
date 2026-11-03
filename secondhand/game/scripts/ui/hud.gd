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
signal rank_pressed        # --- SS2 SEASON: el chip del tablero ("★ #14 ▲3"): abre el tablero entero

const TOP_W := 700.0

var _plate: PanelContainer
var _clock: Label
var _clock_screen: PanelContainer
var _fast_lbl: Label         # --- POLISH FIX (F5): "»" sobre el reloj mientras la tienda vacía adelanta la hora
var _fast_on := false
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
# --- SS2 SEASON
var _rank_btn: Button
var _dues_head: Label
var _event_name := ""
# --- POLISH LOOK (P1): los globos de la calle (las frases de Raker, Mags, Dolly...): 4 globos de papel armados
# escondidos en _ready (sin crear nada al hablar), proyectados cada cuadro sobre la cabeza de quien habla
const BUBBLE_POOL := 4
const BUBBLE_MAX_W := 380.0
const BUBBLE_EDGE := 16.0         # nunca a menos de esto del borde de la pantalla
const BUBBLE_TOP := 92.0          # ni sobre la placa de arriba
const BUBBLE_GAP := 6.0           # dos globos a la vez: uno encima del otro, nunca encimados
var bubble_block := false         # main: una ventana abierta, otro escenario, el fundido (los globos esperan escondidos)
var _bubbles: Array = []          # [{"root", "panel", "label", "tail", "actor", "cam", "lift", "t", "secs", "seq"}]
var _bubble_layer: Control
var _bubble_seq := 0
var _covered := false
# --- end POLISH LOOK

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build_bubbles()   # --- POLISH LOOK (P1): primero: debajo de la placa, los avisos y el cartel del día
	_build_top()
	_build_menu_button()
	_build_rank_chip()   # --- SS2 SEASON
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
	scr.content_margin_left = 16    # --- POLISH FIX (F5): 14 -> 16 / 24 (el "»" cabe a la derecha, sin tocar el borde)
	scr.content_margin_right = 24
	_clock_screen.add_theme_stylebox_override("panel", scr)
	_clock = UIKit.label("9:00 AM", 24, UIKit.kit_color("screen9.png", "text", UIKit.SCREEN_TEXT), UIKit.font_mono, HORIZONTAL_ALIGNMENT_CENTER)
	_clock.custom_minimum_size = Vector2(118, 0)
	_clock_screen.add_child(_clock)
	# --- POLISH FIX (F5): el "»" va en el margen derecho de la pantalla (hijo del reloj: no mueve la placa)
	_fast_lbl = UIKit.label("»", 17, UIKit.kit_color("screen9.png", "text", UIKit.SCREEN_TEXT), UIKit.font_bold)
	_fast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fast_lbl.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_fast_lbl.offset_left = 2.0
	_fast_lbl.offset_right = 14.0
	_fast_lbl.offset_top = -13.0
	_fast_lbl.offset_bottom = 9.0
	_fast_lbl.visible = false
	_clock.add_child(_fast_lbl)
	# --- end POLISH FIX
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
	# --- SS2 SEASON: "DUES · NIGHT 6" arriba; la barra y "134 / 200" abajo (cabe junto al menú a 1024 de ancho)
	_dues_head = UIKit.label("DUES", 13, Color(0.77, 0.81, 0.8), UIKit.font_bold)
	dvv.add_child(_dues_head)
	var dh := UIKit.hbox(6)
	_dues_bar = ProgressBar.new()
	_dues_bar.max_value = 1.0
	_dues_bar.step = 0.001
	_dues_bar.show_percentage = false
	_dues_bar.custom_minimum_size = Vector2(84, 10)
	_dues_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dues_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dh.add_child(_dues_bar)
	_dues_lbl = UIKit.label("0 / 300", 13, Color(0.93, 0.89, 0.78), UIKit.font_bold)
	dh.add_child(_dues_lbl)
	dvv.add_child(dh)
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

## --- SS2 SEASON: el chip del Lantern Board a la izquierda del menú: puesto y flecha de la última noche.
## --- POLISH LOOK (P7): ya no es un botón de crema igual a "Menu" (parecía otro menú): es una pieza de la placa de
## arriba (metal oscuro, letra ámbar de pantalla, el farol del tablero). Por la mañana: "#14 ▲3" (verde si subió,
## rojo si bajó); con la tienda abierta: "#14 · +12★ today" (lo que el tablero de esta noche daría ahora).
## Sigue siendo un Button (clic o cursor del mando: abre el tablero entero).
const RANK_PAD := 12.0
const RANK_FLY_POOL := 3
var _rank_row: HBoxContainer
var _rank_pos_lbl: Label
var _rank_move_lbl: Label
var _rank_today_lbl: Label
var _rank_str := ""
var _rank_key := ""
var _rank_today := -1          # las estrellas de hoy en el chip (-1: la mañana / la noche, sin "today")
var _rank_flies: Array = []    # los "+3★" que vuelan al chip (armados escondidos en _ready)
var _rank_pulse: Tween

func _rank_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = RANK_PAD
	sb.content_margin_right = RANK_PAD
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	return sb

func _build_rank_chip() -> void:
	_rank_btn = Button.new()
	_rank_btn.focus_mode = Control.FOCUS_NONE
	_rank_btn.text = ""
	_rank_btn.tooltip_text = "The Lantern Board"
	_rank_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# el metal de la placa de arriba (gris verdoso oscuro, canto negro); el borde se enciende en ámbar con el cursor
	var plate := Color(0.155, 0.2, 0.205, 0.97)
	_rank_btn.add_theme_stylebox_override("normal", _rank_style(plate, Color(0.06, 0.075, 0.08)))
	_rank_btn.add_theme_stylebox_override("hover", _rank_style(Color(0.2, 0.25, 0.255, 0.97), UIKit.ACCENT))
	_rank_btn.add_theme_stylebox_override("pressed", _rank_style(Color(0.1, 0.13, 0.135, 0.97), UIKit.ACCENT))
	_rank_btn.add_theme_stylebox_override("hover_pressed", _rank_style(Color(0.1, 0.13, 0.135, 0.97), UIKit.ACCENT))
	_rank_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UIKit.place(_rank_btn, Vector2(1.0, 0.0), Vector2(-132, 66), Vector2(118, 40), Control.GROW_DIRECTION_BEGIN)   # bajo el menú
	_rank_btn.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		rank_pressed.emit())
	add_child(_rank_btn)
	_rank_row = UIKit.hbox(6)
	_rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rank_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rank_row.offset_left = RANK_PAD
	_rank_row.offset_right = -RANK_PAD
	_rank_btn.add_child(_rank_row)
	_rank_row.add_child(UIKit.ui_icon("rank", 1.5))
	_rank_pos_lbl = UIKit.label("#30", 22, UIKit.kit_color("screen9.png", "text", UIKit.SCREEN_TEXT), UIKit.font_mono)
	_rank_pos_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_row.add_child(_rank_pos_lbl)
	_rank_move_lbl = UIKit.label("", 17, UIKit.GOOD, UIKit.font_bold)
	_rank_move_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_row.add_child(_rank_move_lbl)
	_rank_today_lbl = UIKit.label("", 16, Color(0.93, 0.89, 0.78), UIKit.font_bold)
	_rank_today_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_today_lbl.visible = false
	_rank_row.add_child(_rank_today_lbl)
	# los "+3★" que vuelan del cliente al chip: una pila chica, escondida (nada se crea al entregar)
	for i in RANK_FLY_POOL:
		var f := UIKit.label("", 26, UIKit.ACCENT_BRIGHT, UIKit.font_bold)
		f.add_theme_color_override("font_outline_color", Color(0.14, 0.09, 0.06))
		f.add_theme_constant_override("outline_size", 8)
		f.visible = false
		add_child(f)
		_rank_flies.append(f)

## El texto del chip: "#14 ▲3" (la flecha de la última noche); con la tienda abierta, "#14 · +12★ today".
func set_rank(pos: int, delta: int) -> void:
	if _rank_btn == null:
		return
	var arrow := ""
	if delta > 0:
		arrow = "▲%d" % delta
	elif delta < 0:
		arrow = "▼%d" % -delta
	var today := _rank_today if mode in ["open", "closing"] else -1
	var key := "%d|%s|%d" % [pos, arrow, today]
	if key == _rank_key:
		return
	_rank_key = key
	_rank_str = "★ #%d%s" % [pos, (" " + arrow) if arrow != "" else ""]
	_rank_pos_lbl.text = "#%d" % pos
	_rank_move_lbl.text = arrow
	_rank_move_lbl.add_theme_color_override("font_color", UIKit.GOOD if delta > 0 else UIKit.BAD)
	_rank_move_lbl.visible = arrow != "" and today < 0
	_rank_today_lbl.visible = today >= 0
	if today >= 0:
		_rank_today_lbl.text = "· +%d★ today" % today
		_rank_str += " · +%d today" % today
	_fit_rank()
	_fit_rank.call_deferred()

## El chip crece hacia la izquierda con su contenido (el borde derecho queda bajo el de "Menu").
func _fit_rank() -> void:
	var w := maxf(118.0, ceilf(_rank_row.get_combined_minimum_size().x + RANK_PAD * 2.0 + 4.0))
	_rank_btn.offset_left = _rank_btn.offset_right - w
	_rank_btn.pivot_offset = Vector2(w * 0.5, 20.0)

## Las estrellas de hoy (Ranking.day_stars, solo lectura): main las pide al abrir y cuando aterriza un "+N★".
func refresh_today() -> void:
	_rank_today = int(Ranking.day_stars().get("total", 0))
	set_rank(Ranking.position(), int(Ranking.last_move().get("delta", 0)))

## Un "+N★" vuela de un punto de la pantalla (el cliente) al chip, como las monedas a los créditos; al llegar, el
## chip cuenta las estrellas nuevas y da un saltito.
func fly_stars(from: Vector2, n: int) -> void:
	if n <= 0 or _rank_flies.is_empty():
		refresh_today()
		return
	var f: Label = _rank_flies[0]
	for x in _rank_flies:
		if not (x as Label).visible:
			f = x
			break
	_rank_flies.erase(f)
	_rank_flies.append(f)   # el que vuela pasa al final (si están todos ocupados, se reusa el más viejo)
	if f.has_meta("tw"):
		var old = f.get_meta("tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	f.text = "+%d★" % n
	f.reset_size()
	var sz := f.get_combined_minimum_size()
	f.size = sz
	f.pivot_offset = sz * 0.5
	f.position = (from - sz * 0.5).round()
	f.scale = Vector2(0.6, 0.6)
	f.modulate.a = 0.0
	f.visible = true
	move_child(f, -1)   # encima del aviso y de los relojes de arena
	var to := _rank_btn.get_global_rect().get_center() - sz * 0.5
	var tw := f.create_tween()
	f.set_meta("tw", tw)
	tw.tween_property(f, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(f, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "position:y", f.position.y - 18.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "position", to, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(f, "scale", Vector2(0.7, 0.7), 0.6)
	tw.tween_callback(func():
		f.visible = false
		refresh_today()
		_rank_pop())

func _rank_pop() -> void:
	if _rank_pulse and _rank_pulse.is_valid():
		_rank_pulse.kill()
	_rank_btn.scale = Vector2.ONE
	_rank_pulse = _rank_btn.create_tween()
	_rank_pulse.tween_property(_rank_btn, "scale", Vector2(1.08, 1.08), 0.08)
	_rank_pulse.tween_property(_rank_btn, "scale", Vector2.ONE, 0.18)

func rank_text() -> String:
	return _rank_str
# --- end SS2 SEASON / POLISH LOOK (P7)

## Muestra u oculta la placa de arriba y el botón de menú (el título y las pantallas grandes la esconden).
func show_top(on: bool) -> void:
	_plate.visible = on
	_menu_btn.visible = on
	if _rank_btn:
		_rank_btn.visible = on   # --- SS2 SEASON

## --- SS MERGE: el banco, el regateo y la cápsula tapan casi toda la pantalla y su placa asomaba por arriba, a
## medias: mientras están abiertos la placa y el menú se apagan (sin tocar show_top).
func set_covered(on: bool) -> void:
	_covered = on   # --- POLISH LOOK (P1): los globos también se apagan
	var a := 0.0 if on else 1.0
	if _plate.modulate.a != a:
		_plate.modulate.a = a
		_menu_btn.modulate.a = a
		if _rank_btn:
			_rank_btn.modulate.a = a   # --- SS2 SEASON

# ------------------------------------------------------------------ datos

func refresh() -> void:
	# --- SS2 SEASON: "DAY 5 OF 10" (sin fin: "DAY 12"), el evento de hoy debajo, la próxima cuota (o el pago de
	# mantenimiento del modo sin fin) con su noche, el chip del tablero
	_day.text = ("DAY %d OF %d" % [Game.day, SeasonData.LAST_DAY]) if Game.is_campaign() else "DAY %d" % Game.day
	_event_name = String(Season.event_def().get("name", ""))
	var nd: Dictionary = Season.next_dues()
	if _dues_head:
		_dues_head.text = "%s · NIGHT %d" % ["UPKEEP" if bool(nd.get("upkeep", false)) else "DUES", int(nd.get("night", 0))]
	set_rank(Ranking.position(), int(Ranking.last_move().get("delta", 0)))
	if mode in ["morning", "open"] and _event_name != "":
		_place.text = _event_name
	# --- end SS2 SEASON
	_set_credits_text(Game.credits)
	# --- POLISH FIX (F6): el día del cometa no muestra la cuota sin fin ("UPKEEP · NIGHT 12"): esta noche solo cuentan
	# las estrellas, y cuentan doble
	var finale := Game.is_last_day()
	_dues_bar.visible = not finale
	if finale:
		if _dues_head:
			_dues_head.text = "FINAL NIGHT"
		_dues_lbl.text = "Every ★ counts ×2"
		_dues_lbl.add_theme_color_override("font_color", UIKit.ACCENT_BRIGHT)
		return
	_dues_lbl.add_theme_color_override("font_color", Color(0.93, 0.89, 0.78))
	# --- end POLISH FIX
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
	if m in ["morning", "open"] and _event_name != "":
		_place.text = _event_name   # --- SS2 SEASON: el día especial
	_line_box.visible = m == "open" or m == "closing"
	# --- POLISH LOOK (P7): al abrir, el chip pasa a "· +N★ today"; de mañana y de noche, la flecha
	# (cada paso del reloj vuelve a contar: las idas sin atender también restan; no mientras vuela un "+N★")
	if m in ["open", "closing"]:
		var flying := false
		for f in _rank_flies:
			flying = flying or (f as Label).visible
		if not flying:
			refresh_today()
	elif _rank_today >= 0:
		_rank_today = -1
		set_rank(Ranking.position(), int(Ranking.last_move().get("delta", 0)))
	# --- end POLISH LOOK

## --- POLISH FIX (F5): la tienda vacía adelanta la hora (ShopDay.IDLE_K): "»" junto al reloj, solo si cambia.
func set_fast(on: bool) -> void:
	if on == _fast_on:
		return
	_fast_on = on
	if _fast_lbl:
		_fast_lbl.visible = on

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
			_hint_pair(["Y"], "Board")   # --- SS2 SEASON
			_hint_pair(["Menu"], "Menu")   # --- POLISH LOOK (P5): el botón se llama Menu en el mando Xbox (antes "Start")
		else:
			_hint_pair(["A", "D"], "Walk")
			_hint_pair(["E"], "Use")
			_hint_pair(["R"], "Board")   # --- SS2 SEASON
			_hint_pair(["Esc"], "Menu")
	if extra != "":
		_hint_row.add_child(UIKit.shadow(UIKit.label(extra, UIKit.FS_SMALL, UIKit.MUTED)))
	elif _hint_row.get_child_count() > 0 and not (_hint_row.get_child(-1) is Label):
		var last := _hint_row.get_child(-1)    # sin el hueco final: la placa queda pareja a los dos lados
		_hint_row.remove_child(last)
		last.queue_free()
	_hint_plate.visible = walking or extra != ""
	_hint_plate.reset_size()
	_pin_hint()              # --- SS SHIP
	_pin_hint.call_deferred()

# --- SS SHIP: la placa queda pegada abajo a la izquierda (14 px de margen). reset_size() conserva el borde de arriba:
# cada vez que se vaciaba (al abrir una ventana) y se volvía a llenar, subía ~32 px; a media tarde flotaba en medio
# del piso de la tienda.
func _pin_hint() -> void:
	var sz := _hint_plate.get_combined_minimum_size()
	_hint_plate.offset_left = 14.0
	_hint_plate.offset_right = 14.0 + sz.x
	_hint_plate.offset_bottom = -14.0
	_hint_plate.offset_top = -14.0 - sz.y

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
	var sz := _prompt.get_combined_minimum_size()
	var p := (at - Vector2(sz.x / 2.0, sz.y)).round()
	var vr := get_viewport_rect()
	p.x = clampf(p.x, 8.0, vr.size.x - sz.x - 8.0)
	p.y = clampf(p.y, 96.0, vr.size.y - sz.y - 60.0)
	# --- POLISH LOOK (P10): el cartel del día ya no pasa por la altura de la gente: el aviso solo espera si lo toca
	var br := banner_rect()
	if br.size.x > 0.0 and br.intersects(Rect2(p, sz)):
		target = 0.0
	# --- end POLISH LOOK
	_prompt.modulate.a = lerpf(_prompt.modulate.a, target, 0.35)
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

# ------------------------------------------------------------------ --- POLISH LOOK (P1): los globos de la calle

## Los 4 globos (el papel y la cola de ART: bubble9.png + bubble_tail.png, como Kettle en el banco), escondidos.
## Todo es de la interfaz 2D (el mismo shader que ya dibuja la HUD): nada nuevo que compilar.
func _build_bubbles() -> void:
	_bubble_layer = Control.new()
	_bubble_layer.name = "Bubbles"
	_bubble_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble_layer)
	UIKit.load_fonts()
	var tail_tex: Texture2D = load("res://assets/ui/bubble_tail.png") if ResourceLoader.exists("res://assets/ui/bubble_tail.png") else null
	for i in BUBBLE_POOL:
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.visible = false
		_bubble_layer.add_child(root)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb: StyleBox = UIKit.nine("bubble9.png", 14, 18)
		if sb == null:
			var f := StyleBoxFlat.new()
			f.bg_color = Color("f4ead2")
			f.border_color = Color("2a2024")
			f.set_border_width_all(3)
			f.set_corner_radius_all(8)
			sb = f
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 9
		sb.content_margin_bottom = 11
		panel.add_theme_stylebox_override("panel", sb)
		root.add_child(panel)
		var lbl := UIKit.label("", 19, UIKit.kit_color("bubble9.png", "text", UIKit.INK), UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		panel.add_child(lbl)
		var tail := TextureRect.new()
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tail.texture = tail_tex
		tail.size = Vector2(24, 18)
		tail.visible = tail_tex != null
		root.add_child(tail)
		_bubbles.append({"root": root, "panel": panel, "label": lbl, "tail": tail, "actor": null, "cam": null,
			"lift": 0.0, "t": 0.0, "secs": 0.0, "seq": 0, "hold": 0.0})
	set_process(false)

## Una frase en un globo sobre la cabeza de alguien (SetKit.bubble_sink, en la calle). Quien ya tenía un globo lo
## cambia por la frase nueva; si los 4 están ocupados, se reusa el más viejo.
func bubble(actor: Node3D, text: String, _col: Color, secs: float, lift: float, cam: Camera3D) -> void:
	if not is_instance_valid(actor) or cam == null or text == "" or _bubbles.is_empty():
		return
	var b: Dictionary = {}
	for x in _bubbles:   # el mismo que habla: su globo
		if x["actor"] == actor:
			b = x
	if b.is_empty():
		for x in _bubbles:   # uno libre
			if x["actor"] == null:
				b = x
				break
	if b.is_empty():     # el más viejo
		b = _bubbles[0]
		for x in _bubbles:
			if int(x["seq"]) < int(b["seq"]):
				b = x
	_bubble_seq += 1
	b["actor"] = actor
	b["cam"] = cam
	b["lift"] = lift
	b["t"] = 0.0
	b["hold"] = 0.0
	b["secs"] = maxf(1.2, secs)
	b["seq"] = _bubble_seq
	var lbl: Label = b["label"]
	lbl.text = text
	# una línea si cabe; si no, líneas parejas (el ancho justo para 2 o 3 renglones, nunca más que BUBBLE_MAX_W)
	var f: Font = lbl.get_theme_font("font")
	var fs: int = lbl.get_theme_font_size("font_size")
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f else BUBBLE_MAX_W + 1.0
	var one := tw <= BUBBLE_MAX_W
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF if one else TextServer.AUTOWRAP_WORD_SMART
	var lines := ceilf(tw / BUBBLE_MAX_W)
	lbl.custom_minimum_size = Vector2(0.0 if one else minf(BUBBLE_MAX_W, ceilf(tw / lines) + 30.0), 0.0)
	var panel: PanelContainer = b["panel"]
	panel.reset_size()
	panel.size = panel.get_combined_minimum_size()
	var root: Control = b["root"]
	root.size = panel.size + Vector2(0, 15)
	root.modulate.a = 0.0
	root.visible = false
	set_process(true)

func clear_bubbles() -> void:
	for b in _bubbles:
		b["actor"] = null
		(b["root"] as Control).visible = false
	set_process(false)

## (pruebas) el texto de los globos a la vista
func bubble_texts() -> Array:
	var out: Array = []
	for b in _bubbles:
		if b["actor"] != null and (b["root"] as Control).visible:
			out.append((b["label"] as Label).text)
	return out

## (pruebas) el rectángulo en pantalla de cada globo a la vista (con la cola)
func bubble_rects() -> Array:
	var out: Array = []
	for b in _bubbles:
		if b["actor"] != null and (b["root"] as Control).visible:
			out.append(Rect2((b["root"] as Control).position, (b["root"] as Control).size))
	return out

func _process(delta: float) -> void:
	var any := false
	var placed: Array = []   # los rectángulos ya puestos este cuadro (del más viejo al más nuevo)
	var order := _bubbles.duplicate()
	order.sort_custom(func(x, y): return int(x["seq"]) < int(y["seq"]))
	var vr := get_viewport_rect()
	for b in order:
		var a = b["actor"]
		if a == null:
			continue
		var root: Control = b["root"]
		if not is_instance_valid(a) or not is_instance_valid(b["cam"]):
			b["actor"] = null
			root.visible = false
			continue
		any = true
		var actor := a as Node3D
		var cam := b["cam"] as Camera3D
		# esperando: una ventana, otro escenario, el fundido, el banco (no corre el tiempo) o el cartel del día
		# (que pasa por la misma altura: el globo sale cuando se va, como el aviso; como mucho 4 s)
		var waiting := bubble_block or _covered or not actor.is_visible_in_tree() or not cam.current
		if not waiting and _banner.modulate.a > 0.02 and float(b["hold"]) < 4.0:
			b["hold"] = float(b["hold"]) + delta
			waiting = true
		if waiting:
			root.visible = false
			continue
		b["t"] = float(b["t"]) + delta
		var t := float(b["t"])
		var secs := float(b["secs"])
		if t >= secs:
			b["actor"] = null
			root.visible = false
			continue
		var panel: PanelContainer = b["panel"]
		panel.size = panel.get_combined_minimum_size()   # (con salto de palabra el alto se sabe después del primer cuadro)
		root.size = panel.size + Vector2(0, 15)
		var head: float = actor.call("top_height") if actor.has_method("top_height") else 1.6
		var wp := actor.global_position + Vector3.UP * (head + 0.35 + float(b["lift"]))
		if cam.is_position_behind(wp):
			root.visible = false
			continue
		var sp := cam.unproject_position(wp)
		var sz: Vector2 = root.size
		var rise := 8.0 * t / secs     # sube un poquito mientras se lee (como la frase de antes)
		var p := Vector2(sp.x - sz.x / 2.0, sp.y - sz.y - rise)
		p.x = clampf(p.x, BUBBLE_EDGE, vr.size.x - sz.x - BUBBLE_EDGE)
		p.y = clampf(p.y, BUBBLE_TOP, vr.size.y - sz.y - BUBBLE_EDGE)
		# dos a la vez (Raker y Nell): el más nuevo se corre arriba del otro
		for i in 3:
			var hit := false
			for r in placed:
				var me := Rect2(p, sz).grow(BUBBLE_GAP * 0.5)
				if me.intersects((r as Rect2).grow(BUBBLE_GAP * 0.5)):
					p.y = (r as Rect2).position.y - sz.y - BUBBLE_GAP
					hit = true
			if not hit:
				break
		if p.y < BUBBLE_TOP:   # sin lugar arriba: abajo del otro
			p.y = BUBBLE_TOP
			for r in placed:
				if Rect2(p, sz).intersects(r as Rect2):
					p.y = (r as Rect2).end.y + BUBBLE_GAP
		p = p.round()
		root.position = p
		placed.append(Rect2(p, sz))
		# la cola apunta a quien habla (dentro del globo, lejos de las esquinas)
		var tail: TextureRect = b["tail"]
		tail.position = Vector2(clampf(round(sp.x - p.x - 12.0), 12.0, panel.size.x - 36.0), panel.size.y - 3.0)
		# aparece (0,15 s, con un saltito) y se desvanece (0,4 s)
		var k_in := clampf(t / 0.15, 0.0, 1.0)
		var k_out := clampf((secs - t) / 0.4, 0.0, 1.0)
		root.modulate.a = minf(k_in, k_out)
		root.pivot_offset = Vector2(tail.position.x + 12.0, sz.y)
		var sc := 0.9 + 0.1 * (1.0 - pow(1.0 - k_in, 3.0))
		root.scale = Vector2(sc, sc)
		root.visible = true
	if not any:
		set_process(false)
# --- end POLISH LOOK

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

const BANNER_Y := 146.0        # --- POLISH LOOK (P10): el centro de la cinta del día (bajo la placa de arriba)
var _banner_rib: Control

## --- POLISH LOOK (P10): el rectángulo de la cinta mientras se ve (los avisos solo esperan si lo tocan).
func banner_rect() -> Rect2:
	if _banner == null or _banner.modulate.a <= 0.02 or _banner_rib == null:
		return Rect2()
	return _banner_rib.get_global_rect()

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
	# --- POLISH LOOK (P10): la cinta va arriba, justo bajo la placa (y 84-208), no a media pantalla: antes tapaba el
	# cartel THE SECONDHAND STAR cada mañana y las caras; ahora el cielo / la pared alta la llevan y abajo se ve todo
	UIKit.place(rib, Vector2(0.5, 0.0), Vector2(-480, BANNER_Y - 62), Vector2(960, 124))
	_banner.add_child(rib)
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(v, Vector2(0.5, 0.0), Vector2(-400, BANNER_Y - 56), Vector2(800, 112), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_banner.add_child(v)
	_banner_rib = rib
	# --- end POLISH LOOK
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
