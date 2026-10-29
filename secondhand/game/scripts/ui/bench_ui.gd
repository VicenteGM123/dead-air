extends Control
class_name BenchUI
## El banco de reparación (el corazón del juego; una reparación = 20-40 s):
##   1 DIAGNOSTICAR: la nota del cliente + tres herramientas (LISTEN onda de sonido, TAP traqueteo, SCAN calor) y
##     elegir el zócalo de la pieza rota. La mejor herramienta de la familia (radio LISTEN, bot TAP, propulsor SCAN)
##     da la pista clara; las otras dos dejan dos candidatos cada una (señuelos distintos: usarlas juntas deduce la
##     falla). Pieza equivocada: Kettle hace "hmm", +2 s y baja la calidad. Acierto: Kettle silba.
##   2 CAMBIAR: la pieza mala sale sola (se ve rota), el cajón de piezas (Game.parts) marca la que hace falta:
##     Swap (Game.take_part: la pieza va en parts_used) o Patch (cinta: sin pieza, una estrella menos). Sin
##     repuesto solo queda el parche, así el juego nunca se traba.
##   3 SOLDAR: pasar el soldador por 3-5 puntos en orden (bench_solder.gd).
##   4 PROBAR: parar la aguja en la zona verde (bench_gauge.gd).
##   y la tarjeta del resultado (0-3 estrellas, el detalle, el tiempo).
## --- SS BENCH: reemplaza el placeholder de la semilla con el MISMO contrato (SS_BRIEF §3):
##   open(job)  job = {"item", "fault", "symptom", "extras": [], "customer"} (+ opcional "tutorial": true, "seed")
##   signal finished(result)  {"ok", "stars" 0-3, "time" (s), "fault_found", "patched", "parts_used": []}
##                            (+ extras: "wrong", "solder", "test", "tools")
##   close_now() cierra SIN emitir finished; is_open(); bot_play(skill := 1.0) juega solo (asíncrono: termina con
##   finished; skill < 1 se equivoca a propósito, para probar el balance).
## Quién toca Game: el banco llama a Game.take_part() al cambiar la pieza (y la lista en parts_used: no sacarla de
## nuevo). La paga, la reputación y las estadísticas las pone quien lo abre (BenchData.repair_pay(item, stars, time)).
## Controles: ratón (todo es clic); teclado L / T / S herramientas, 1-4 piezas, Intro / Espacio / E la acción
## principal, P parche, flechas / WASD el soldador, Esc rendirse (pide confirmación); mando: el cursor de PadCursor
## (LB / RB saltan entre botones y zócalos, A toca, X = Espacio, B = Esc), el stick mueve el soldador.
## Se arma UNA vez en _ready (abrir el banco no crea nodos ni carga texturas: sin tirones).

signal finished(result: Dictionary)

enum Step { NONE, DIAGNOSE, SWAP, SOLDER, TEST, RESULT }

const PLATE := Rect2(24, 20, 1232, 680)
const HEADER := Rect2(40, 32, 1200, 48)
const LEFT := Rect2(40, 88, 204, 500)
const MAT := Rect2(254, 88, 736, 500)      # la vista x2 (720x480) con 10 px de aire arriba y abajo
const RIGHT := Rect2(1000, 88, 240, 500)
const BOTTOM := Rect2(40, 598, 1200, 88)
const STEP_NAMES := ["Diagnose", "Swap", "Solder", "Test"]

static var seen_families := {}      # la primera vez de cada familia Kettle da el consejo de su herramienta

var job := {}
var step := Step.NONE
var item := ""
var fault := ""
var fault_i := -1
var slots: Array = []

var _wrong := 0
var _found := false
var _patched := false
var _parts_used: Array = []
var _tools_used: Array = []
var _solder_done := false
var _solder_acc := 0.0
var _test := ""
var _elapsed := 0.0
var _penalty := 0.0
var _clock_on := false
var _seed := 0
var _gen := 0
var _busy := false
var _confirm := false
var _last_pad := false
var _result := {}
var _tutorial := false
var _self := false            # --- SS MERGE: el trabajo es el propio cliente (Clatter)
var _head_verb: Label         # --- SS SHIP: "REPAIR" o "REFURBISH"
var _ticket_hdr: Label        # --- SS SHIP: "CUSTOMER NOTE" o "POD FIND"

# nodos (se arman una vez)
var _dim: ColorRect
var _canvas: Control
var _plate: PanelContainer
var _head_item: Label
var _head_who: Label
var _chips: Array = []
var _timer_lbl: Label
var _pen_lbl: Label
var _ticket: PanelContainer
var _ticket_txt: Label
var _ticket_sig: Label
var _kettle: BenchKettle
var _stage: BenchStage
var _solder: BenchSolder
var _gauge: BenchGauge
var _scope: BenchScope
var _tools: Dictionary = {}
var _tools_box: Control
var _tip_tag: PanelContainer
var _tip_lbl: Label
var _drawer: Control
var _drawer_cells: Dictionary = {}
var _swap_btn: Button
var _patch_btn: Button
var _instr: Label
var _hints_box: Control
var _giveup_btn: Button
var _confirm_box: HBoxContainer
var _card: PanelContainer
var _card_title: Label
var _card_icon: TextureRect
var _card_stars: HBoxContainer
var _card_lines: VBoxContainer
var _card_time: Label
var _card_quote_tag: PanelContainer
var _card_quote: Label
var _power_line := ""         # lo que hizo la cosa al probarla (va en la tarjeta del resultado)
var _card_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (después de entrar al árbol: anclas Y márgenes)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	visible = false
	_build()

# ------------------------------------------------------------------ contrato

func open(j: Dictionary) -> void:
	_gen += 1
	job = j.duplicate(true)
	item = String(job.get("item", ""))
	if not BenchData.ITEMS.has(item):
		push_warning("BenchUI: cosa desconocida '%s' (uso la radio)" % item)
		item = "radio"
	slots = BenchData.ITEMS[item]["slots"]
	fault = String(job.get("fault", ""))
	if not fault in slots:
		push_warning("BenchUI: falla '%s' no es una pieza de %s" % [fault, item])
		fault = String(BenchData.FAULTS[item].keys()[0])
	fault_i = slots.find(fault)
	_seed = int(job.get("seed", randi() % 100000))
	_tutorial = bool(job.get("tutorial", false))
	_wrong = 0
	_found = false
	_patched = false
	_parts_used = []
	_tools_used = []
	_solder_done = false
	_solder_acc = 0.0
	_test = ""
	_power_line = ""
	_elapsed = 0.0
	_penalty = 0.0
	_clock_on = true
	_busy = false
	_confirm = false
	_result = {}
	# la cabecera y la nota
	_head_item.text = BenchData.item_name(item)
	var who := String(job.get("customer", ""))
	_head_who.text = ("for %s" % Data.char_name(who)) if who != "" else ""
	# --- SS SHIP: sin cliente es algo roto de una cápsula: se reacondiciona para el estante (no es un encargo)
	_head_verb.text = "REPAIR" if who != "" else "REFURBISH"
	_ticket_hdr.text = "CUSTOMER NOTE" if who != "" else "POD FIND · WHAT'S WRONG"
	if who == "":
		_head_who.text = "for the shelf"
	# --- end SS SHIP
	# --- SS MERGE: el cliente es la cosa (Clatter viene a arreglarse a sí mismo): su nombre en la cabecera
	_self = bool(job.get("self", false))
	if _self:
		_head_item.text = String(job.get("label", Data.char_name(who)))
		_head_who.text = String(job.get("sub", "fixing himself"))
	# --- end SS MERGE
	var sym := String(job.get("symptom", ""))
	if sym == "":
		sym = BenchData.symptom(item, fault)
	_ticket_txt.text = "“%s”" % sym
	_ticket_sig.text = ("— %s" % Data.char_name(who)) if who != "" else ""
	_stage.setup(item, fault_i)
	_card.visible = false
	_kettle.reset()
	visible = true
	modulate.a = 1.0
	_enter(Step.DIAGNOSE)
	UIKit.pop_in(_canvas)
	Sfx.play("ratchet", 0.05, -4.0)
	# Kettle: el consejo de la herramienta la primera vez de cada familia (o en el tutorial)
	if _tutorial:
		_kettle.say(BenchData.KETTLE_TUTORIAL["diagnose"], 5.0)
	elif not seen_families.has(item):
		_kettle.say(String(BenchData.ITEMS[item].get("kettle_tip", "")), 5.0)
	else:
		var hi: Array = BenchData.KETTLE["hello"]
		_kettle.say(String(hi[randi() % hi.size()]), 2.5)
	seen_families[item] = true

func is_open() -> bool:
	return visible

## Cierra sin emitir finished (p. ej. al volver al título).
func close_now() -> void:
	_gen += 1
	visible = false
	step = Step.NONE
	_busy = false
	_confirm = false
	_clock_on = false

## El bot de autoplay: diagnostica con la mejor herramienta, cambia (o parcha si no hay repuesto), suelda y prueba.
## skill 1.0 = perfecto; menos = se equivoca de pieza, suelda torcido, para la aguja corrida (para probar balance).
func bot_play(skill := 1.0) -> void:
	if not visible:
		return
	_bot_run(clampf(skill, 0.0, 1.0), "")

## Capturas: juega solo hasta un paso y se queda ahí: "diagnose" (pista a la vista), "wrong", "swap", "solder"
## (soldadura a medias), "test" (aguja en marcha), "result".
func demo_to(step_name: String) -> void:
	if not visible:
		return
	_bot_run(1.0, step_name)

# ------------------------------------------------------------------ armado (una vez)

func _build() -> void:
	_dim = UIKit.dim_overlay()
	_dim.color = Color(0.02, 0.015, 0.01, 0.55)
	_dim.gui_input.connect(_on_bg_input)
	add_child(_dim)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.anchor_left = 0.5
	_canvas.anchor_right = 0.5
	_canvas.anchor_top = 0.5
	_canvas.anchor_bottom = 0.5
	_canvas.offset_left = -640
	_canvas.offset_right = 640
	_canvas.offset_top = -360
	_canvas.offset_bottom = 360
	add_child(_canvas)
	_plate = BenchKit.plate(16)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BenchKit.at(_plate, PLATE)
	_canvas.add_child(_plate)
	_build_header()
	_build_left()
	_build_stage()
	_build_right()
	_build_bottom()
	_build_card()
	_canvas.move_child(_kettle, -1)      # Kettle y su globo, encima de la alfombra
	_canvas.move_child(_pen_lbl, -1)     # el "+2s" va encima de la pantalla del osciloscopio

func _build_header() -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	BenchKit.at(h, HEADER)
	_canvas.add_child(h)
	var ic := UIKit.ui_icon("wrench", 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := BenchKit.shadow(UIKit.label("REPAIR", 26, UIKit.ACCENT, UIKit.font_bold))
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	_head_verb = t   # --- SS SHIP
	_head_item = BenchKit.shadow(UIKit.label("", 26, BenchKit.CREAM, UIKit.font_bold))
	_head_item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_head_item)
	_head_who = UIKit.label("", 20, UIKit.MUTED, UIKit.font_regular)
	_head_who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_head_who)
	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	for i in STEP_NAMES.size():
		if i > 0:
			var arrow := UIKit.label("›", 24, UIKit.MUTED, UIKit.font_bold)
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(arrow)
		h.add_child(_make_chip(i))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	var scr := BenchKit.screen(8)
	var sb: StyleBox = scr.get_theme_stylebox("panel").duplicate()
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	scr.add_theme_stylebox_override("panel", sb)
	scr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var th := HBoxContainer.new()
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_theme_constant_override("separation", 6)
	th.add_child(UIKit.ui_icon("sandtimer", 2.0))
	_timer_lbl = UIKit.label("0:00", 24, BenchKit.AMBER, UIKit.font_mono)
	_timer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	th.add_child(_timer_lbl)
	scr.add_child(th)
	h.add_child(scr)
	_pen_lbl = BenchKit.shadow(UIKit.label("+2s", 20, BenchKit.RED, UIKit.font_bold))
	_pen_lbl.position = Vector2(HEADER.end.x - 60, HEADER.end.y + 2)
	_pen_lbl.modulate.a = 0.0
	_canvas.add_child(_pen_lbl)

func _make_chip(i: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var num := UIKit.label(str(i + 1), 17, UIKit.MUTED, UIKit.font_bold)
	num.name = "Num"
	h.add_child(num)
	var nm := UIKit.label(STEP_NAMES[i], 17, UIKit.MUTED, UIKit.font_bold)
	nm.name = "Name"
	h.add_child(nm)
	p.add_child(h)
	_chips.append(p)
	return p

func _paint_chips() -> void:
	var cur := int(step) - 1     # DIAGNOSE = 0
	for i in _chips.size():
		var p: PanelContainer = _chips[i]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(13)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 3
		sb.content_margin_bottom = 4
		sb.set_border_width_all(2)
		var col := UIKit.MUTED
		var num: Label = p.find_child("Num", true, false)
		num.text = str(i + 1)
		if i < cur or step == Step.RESULT:
			sb.bg_color = Color(0.2, 0.32, 0.18, 0.55)
			sb.border_color = Color(0.45, 0.7, 0.4, 0.8)
			col = Color(0.72, 0.95, 0.62)
			num.text = "✓"
		elif i == cur:
			sb.bg_color = UIKit.ACCENT
			sb.border_color = UIKit.ACCENT_BRIGHT
			col = BenchKit.INK
		else:
			sb.bg_color = Color(0, 0, 0, 0.25)
			sb.border_color = Color(0.4, 0.38, 0.35, 0.5)
		p.add_theme_stylebox_override("panel", sb)
		num.add_theme_color_override("font_color", col)
		(p.find_child("Name", true, false) as Label).add_theme_color_override("font_color", col)

func _build_left() -> void:
	_ticket = BenchKit.tag(12)
	_ticket.position = LEFT.position + Vector2(0, 6)
	_ticket.custom_minimum_size = Vector2(LEFT.size.x, 0)
	_canvas.add_child(_ticket)
	var v := UIKit.vbox(2)
	_ticket.add_child(v)
	var hdr := UIKit.label("CUSTOMER NOTE", 13, Color("7a6656"), UIKit.font_bold)
	v.add_child(hdr)
	_ticket_hdr = hdr   # --- SS SHIP
	_ticket_txt = UIKit.label("", 29, BenchKit.INK, UIKit.font_hand)
	_ticket_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticket_txt.custom_minimum_size = Vector2(LEFT.size.x - 52, 0)
	v.add_child(_ticket_txt)
	_ticket_sig = UIKit.label("", 24, Color("5a4436"), UIKit.font_hand, HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(_ticket_sig)
	_kettle = BenchKettle.new()
	_kettle.position = Vector2(LEFT.position.x + 4, LEFT.end.y - 156)
	_canvas.add_child(_kettle)

func _build_stage() -> void:
	_stage = BenchStage.new()
	BenchKit.at(_stage, MAT)
	_canvas.add_child(_stage)
	_stage.slot_pressed.connect(_pick)
	_solder = BenchSolder.new()
	BenchKit.at(_solder, Rect2(MAT.position + Vector2(40, 29), Vector2(656, 442)))
	_solder.visible = false
	_canvas.add_child(_solder)
	_solder.pad_lit.connect(_on_pad_lit)
	_solder.finished.connect(_on_solder_done)
	_gauge = BenchGauge.new()
	BenchKit.at(_gauge, Rect2(MAT.position + Vector2(88, 85), Vector2(560, 330)))
	_gauge.visible = false
	_canvas.add_child(_gauge)
	_gauge.stopped.connect(_on_test_stopped)

func _build_right() -> void:
	_scope = BenchScope.new()
	BenchKit.at(_scope, Rect2(RIGHT.position, Vector2(RIGHT.size.x, 262)))
	_canvas.add_child(_scope)
	_tools_box = BenchKit.group(Rect2(RIGHT.position + Vector2(0, 274), Vector2(RIGHT.size.x, 212)))
	_canvas.add_child(_tools_box)
	var y := 0.0
	for t in BenchData.TOOL_ORDER:
		var tool: String = t
		var b := BenchKit.key_button(BenchData.tool_name(tool), String(BenchData.TOOLS[tool]["key"]),
			func(): _use_tool(tool), Vector2(RIGHT.size.x, 64), tool, false, 22)
		(b.find_child("Row", true, false) as HBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
		var sp := Control.new()
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row: HBoxContainer = b.find_child("Row", true, false)
		row.add_child(sp)
		row.move_child(sp, row.get_child_count() - 2)
		b.tooltip_text = String(BenchData.TOOLS[tool]["about"])
		b.position = Vector2(0, y)
		_tools_box.add_child(b)
		_tools[tool] = b
		y += 73.0
	# consejo (soldar / probar): una etiqueta de papel bajo la pantalla
	_tip_tag = BenchKit.tag(10)
	_tip_tag.position = RIGHT.position + Vector2(0, 282)
	_tip_tag.custom_minimum_size = Vector2(RIGHT.size.x, 0)
	_tip_lbl = UIKit.label("", 25, BenchKit.INK, UIKit.font_hand)
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_lbl.custom_minimum_size = Vector2(RIGHT.size.x - 52, 0)
	_tip_tag.add_child(_tip_lbl)
	_tip_tag.visible = false
	_canvas.add_child(_tip_tag)
	_build_drawer()

func _build_drawer() -> void:
	_drawer = BenchKit.group(RIGHT)
	_drawer.visible = false
	_canvas.add_child(_drawer)
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", BenchKit.inset_style(Color(0.09, 0.08, 0.07, 0.95), 6))
	bg.position = Vector2.ZERO
	bg.size = Vector2(RIGHT.size.x, 330)
	_drawer.add_child(bg)
	var ttl := UIKit.label("PARTS DRAWER", 16, UIKit.ACCENT, UIKit.font_bold)
	ttl.position = Vector2(14, 10)
	_drawer.add_child(ttl)
	var cw := 70.0
	var chh := 92.0
	for i in BenchData.PART_ORDER.size():
		var p: String = BenchData.PART_ORDER[i]
		var cell := Panel.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.position = Vector2(12 + (i % 3) * (cw + 6), 38 + (i / 3) * (chh + 4))
		cell.size = Vector2(cw, chh)
		_drawer.add_child(cell)
		var icon := BenchKit.pixel_rect(BenchKit.tex("res://assets/parts/%s.png" % p), 2.0)
		icon.position = Vector2(3, 2)
		icon.size = Vector2(64, 64)
		icon.name = "Icon"
		cell.add_child(icon)
		var cnt := UIKit.label("x0", 16, BenchKit.CREAM, UIKit.font_mono, HORIZONTAL_ALIGNMENT_CENTER)
		cnt.name = "Count"
		cnt.position = Vector2(0, 64)
		cnt.size = Vector2(cw, 22)
		cell.add_child(cnt)
		_drawer_cells[p] = cell
	_swap_btn = BenchKit.key_button("Swap it", "E", func(): _do_swap(), Vector2(RIGHT.size.x, 60), "", true, 21)
	_swap_btn.position = Vector2(0, 342)
	_drawer.add_child(_swap_btn)
	_patch_btn = BenchKit.key_button("Patch it", "P", func(): _do_patch(), Vector2(RIGHT.size.x, 54), "", false, 20)
	_patch_btn.position = Vector2(0, 412)
	_drawer.add_child(_patch_btn)

func _paint_drawer() -> void:
	for p in _drawer_cells:
		var cell: Panel = _drawer_cells[p]
		var n := Game.part_count(p)
		var need := String(p) == fault
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(3 if need else 1)
		sb.bg_color = Color(0.2, 0.17, 0.13, 0.95) if need else Color(0.13, 0.12, 0.11, 0.9)
		sb.border_color = UIKit.ACCENT if need else Color(0.32, 0.3, 0.28)
		cell.add_theme_stylebox_override("panel", sb)
		(cell.find_child("Icon", false, false) as Control).modulate = Color(1, 1, 1, 1.0 if n > 0 else 0.3)
		var cnt: Label = cell.find_child("Count", false, false)
		cnt.text = "x%d" % n
		cnt.add_theme_color_override("font_color", (UIKit.ACCENT_BRIGHT if n > 0 else BenchKit.RED) if need else (BenchKit.CREAM if n > 0 else UIKit.MUTED))

func _build_bottom() -> void:
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", BenchKit.inset_style(Color(0.06, 0.06, 0.055, 0.85), 6))
	BenchKit.at(bar, BOTTOM)
	_canvas.add_child(bar)
	_instr = BenchKit.shadow(UIKit.label("", 24, BenchKit.CREAM, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	BenchKit.at(_instr, Rect2(BOTTOM.position + Vector2(150, 9), Vector2(BOTTOM.size.x - 300, 34)))
	_canvas.add_child(_instr)
	_hints_box = BenchKit.group(Rect2(BOTTOM.position + Vector2(150, 48), Vector2(BOTTOM.size.x - 300, 34)))
	_canvas.add_child(_hints_box)
	_giveup_btn = BenchKit.key_button("Give up", "Esc", func(): _ask_give_up(), Vector2(150, 50), "", false, 18)
	_giveup_btn.position = BOTTOM.position + Vector2(BOTTOM.size.x - 162, 19)
	_canvas.add_child(_giveup_btn)
	_confirm_box = HBoxContainer.new()
	_confirm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_box.add_theme_constant_override("separation", 16)
	BenchKit.at(_confirm_box, Rect2(BOTTOM.position + Vector2(0, 16), Vector2(BOTTOM.size.x, 56)))
	var q := BenchKit.shadow(UIKit.label("Give up this repair?", 24, BenchKit.CREAM, UIKit.font_bold))
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_box.add_child(q)
	_confirm_box.add_child(BenchKit.key_button("Give up", "Esc", func(): _give_up(), Vector2(170, 54), "", false, 20))
	_confirm_box.add_child(BenchKit.key_button("Keep working", "Enter", func(): _cancel_give_up(), Vector2(250, 54), "", true, 20))
	_confirm_box.visible = false
	_canvas.add_child(_confirm_box)

func _build_card() -> void:
	_card = BenchKit.plate(26)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.custom_minimum_size = Vector2(520, 0)
	_card.visible = false
	_canvas.add_child(_card)
	# centrada en el lienzo: crece hacia los dos lados según el contenido
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.offset_left = 0
	_card.offset_right = 0
	_card.offset_top = -10
	_card.offset_bottom = -10
	var v := UIKit.vbox(12)
	_card.add_child(v)
	_card_title = BenchKit.shadow(UIKit.label("REPAIRED", 32, UIKit.ACCENT, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_card_title)
	var mid := UIKit.hbox(18)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_icon = BenchKit.pixel_rect(null, 2.0)
	_card_icon.custom_minimum_size = Vector2(128, 128)
	mid.add_child(_card_icon)
	_card_stars = UIKit.hbox(6)
	_card_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var s := UIKit.ui_icon("star", 3.0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_card_stars.add_child(s)
	mid.add_child(_card_stars)
	v.add_child(mid)
	# lo que hizo la cosa al encenderla (el bot lo dice con su voz), en una etiqueta de papel
	_card_quote_tag = BenchKit.tag(10)
	_card_quote = UIKit.label("", 26, BenchKit.INK, UIKit.font_hand, HORIZONTAL_ALIGNMENT_CENTER)
	_card_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_quote.custom_minimum_size = Vector2(400, 0)
	_card_quote_tag.add_child(_card_quote)
	v.add_child(_card_quote_tag)
	v.add_child(UIKit.divider(440))
	_card_lines = UIKit.vbox(6)
	v.add_child(_card_lines)
	_card_time = UIKit.label("", 20, UIKit.MUTED, UIKit.font_regular, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_card_time)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_btn = BenchKit.key_button("Done", "Enter", func(): _done(), Vector2(220, 58), "", true, 22)
	row.add_child(_card_btn)
	v.add_child(row)

# ------------------------------------------------------------------ pasos

func _enter(s: Step) -> void:
	step = s
	_paint_chips()
	_stage.set_pick_enabled(s == Step.DIAGNOSE)
	_tools_box.visible = s == Step.DIAGNOSE
	_scope.visible = s in [Step.DIAGNOSE, Step.SOLDER, Step.TEST]
	_drawer.visible = s == Step.SWAP
	_solder.visible = s == Step.SOLDER
	_gauge.visible = s == Step.TEST
	_tip_tag.visible = s in [Step.SOLDER, Step.TEST]
	_giveup_btn.visible = s != Step.RESULT
	var tw := create_tween()
	tw.tween_property(_stage, "dim", 1.0 if s in [Step.SOLDER, Step.TEST] else 0.0, 0.25)
	match s:
		Step.DIAGNOSE:
			for t in _tools:
				BenchKit.enable(_tools[t], true)
			_scope.show_mode("idle", "BENCH SCOPE", "Pick a tool to check the parts.")
			_set_instr("Find the faulty part: use a tool, then click the part.")
		Step.SWAP:
			_enter_swap()
		Step.SOLDER:
			_enter_solder()
		Step.TEST:
			_enter_test()
		Step.RESULT:
			_enter_result()
	_refresh_hints()

func _set_instr(t: String) -> void:
	_instr.text = t

func _refresh_hints() -> void:
	for c in _hints_box.get_children():
		c.queue_free()
	var items: Array = []
	match step:
		Step.DIAGNOSE:
			items = [{"keys": ["L", "T", "S"], "text": "tools"}, {"keys": ["1-4"], "text": "pick a part"},
				{"pad": ["LB", "RB"], "text": "select"}, {"pad": ["A"], "text": "use"}]
		Step.SWAP:
			if Game.has_part(fault):
				items = [{"keys": ["E"], "text": "swap"}, {"keys": ["P"], "text": "patch"}]
			else:
				items = [{"keys": ["E"], "text": "patch (no spare)"}]
			items.append_array([{"pad": ["LB", "RB"], "text": "select"}, {"pad": ["A"], "text": "use"}])
		Step.SOLDER:
			items = [{"keys": ["←", "↑", "→", "↓"], "text": "or mouse: move the iron"}, {"pad": ["Stick"], "text": "move the iron"}]
		Step.TEST:
			items = [{"keys": ["Space"], "text": "or click: stop the needle"}, {"pad": ["A"], "text": "stop the needle"}]
		Step.RESULT:
			items = [{"keys": ["Enter"], "text": "done"}, {"pad": ["A"], "text": "done"}]
	if step != Step.RESULT:
		items.append({"pad": ["B"], "text": "give up"})
	var row := BenchKit.hints(items, 17)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hints_box.add_child(row)
	BenchKit.refresh_keys(_canvas)
	_last_pad = PadCursor.pad_in_use

# --- 1 diagnosticar

func _use_tool(t: String) -> void:
	if not visible or step != Step.DIAGNOSE or _busy or _confirm:
		return
	var c := BenchData.clue(item, fault, t, _seed)
	if not t in _tools_used:
		_tools_used.append(t)
	_stage.show_clue(c)
	var ttl := "%s%s" % [BenchData.tool_name(t).to_upper(), "  ✓ CLEAR" if bool(c.get("clear", false)) else ""]
	_scope.show_mode(t, ttl, String(c.get("text", "")), c)
	match t:
		"listen":
			Sfx.play("sizzle" if String(c.get("wave", "")) in ["hiss", "mixed"] else "blip", 0.05, -8.0)
		"tap":
			Sfx.play("ratchet", 0.1, -4.0)
		"scan":
			Sfx.play_pitched("blip", 1.5, -6.0)
	if BenchData.ITEMS[item].get("talks", false):
		if t == "tap":
			var ow: Array = BenchData.BOT_TALK["tap"]
			_stage.bot_say(String(ow[randi() % ow.size()]), 1.4)
		elif t == "listen":
			_stage.bot_say(String(_bot_talk().get(fault, {}).get("before", "...")), 2.4)
	_lock(0.45)

func _pick(i: int) -> void:
	if not visible or step != Step.DIAGNOSE or _busy or _confirm or i < 0 or i >= slots.size():
		return
	if _stage.state(i) == "wrong":
		return
	if i == fault_i:
		_found = true
		_stage.set_state(i, "found")
		_stage.set_pick_enabled(false)
		_kettle.whistle()
		_scope.show_mode("info", "FOUND IT", "The %s is bad." % BenchData.part_name(fault).to_lower(), {})
		_busy = true
		var g := _gen
		await _wait(0.75)
		if g != _gen:
			return
		_busy = false
		_enter(Step.SWAP)
	else:
		_wrong += 1
		_penalty += float(BenchData.SCORE["wrong_secs"])
		_stage.set_state(i, "wrong")
		_kettle.hmm()
		Sfx.play("bad", 0.05, -8.0)
		_flash_penalty()
		_lock(0.35)

# --- 2 cambiar

func _enter_swap() -> void:
	_stage.clear_clues()
	_stage.set_state(fault_i, "out")
	_paint_drawer()
	var pn := BenchData.part_name(fault)
	var have := Game.has_part(fault)
	BenchKit.set_text(_swap_btn, "Swap: %s" % pn)
	BenchKit.enable(_swap_btn, have)
	BenchKit.set_key(_swap_btn, "E" if have else "")
	BenchKit.set_text(_patch_btn, "Patch it  (−1★)")
	BenchKit.enable(_patch_btn, true)
	BenchKit.set_key(_patch_btn, "P" if have else "E")
	if have:
		_set_instr("Swap in a new %s from the drawer (or patch the old one)." % pn.to_lower())
		_kettle.say(BenchData.KETTLE_TUTORIAL["swap"] if _tutorial else String(BenchData.KETTLE["swap"]), 2.5)
	else:
		_set_instr("No spare %s in the drawer. Patch the old one!" % pn.to_lower())
		_kettle.say(String(BenchData.KETTLE["patch"]), 2.5)
	_lock(0.6)

func _do_swap() -> void:
	if not visible or step != Step.SWAP or _busy or _confirm:
		return
	if not Game.take_part(fault):
		_do_patch()
		return
	_parts_used.append(fault)
	_stage.set_state(fault_i, "new")
	_paint_drawer()
	Sfx.play("ratchet", 0.05, -2.0)
	_busy = true
	var g := _gen
	await _wait(0.85)
	if g != _gen:
		return
	_busy = false
	_enter(Step.SOLDER)

func _do_patch() -> void:
	if not visible or step != Step.SWAP or _busy or _confirm:
		return
	_patched = true
	_stage.set_state(fault_i, "patched")
	Sfx.play("ratchet", 0.15, -6.0)
	_busy = true
	var g := _gen
	await _wait(0.85)
	if g != _gen:
		return
	_busy = false
	_enter(Step.SOLDER)

## La acción principal del paso CAMBIAR (Intro / E / Espacio / X): cambiar si hay repuesto, si no parchar.
func _swap_primary() -> void:
	if Game.has_part(fault):
		_do_swap()
	else:
		_do_patch()

# --- 3 soldar

func _enter_solder() -> void:
	_solder.setup(int(BenchData.ITEMS[item].get("pads", 4)), _seed, fault)
	_scope.show_mode("solder", "SOLDER", "Trace the pads in order.", {"lit": 0, "n": _solder.n_pads, "acc": -1.0})
	_set_instr("Solder it: run the iron over the pads, in order.")
	_tip_lbl.text = BenchData.KETTLE_TUTORIAL["solder"] if _tutorial else "Stay on the copper line for a clean joint."
	_kettle.say(String(BenchData.KETTLE["solder"]), 2.0)

func _on_pad_lit(k: int, n: int) -> void:
	_scope.data = {"lit": k, "n": n, "acc": -1.0}

func _on_solder_done(completed: bool, acc: float) -> void:
	if step != Step.SOLDER:
		return
	_solder_done = completed
	_solder_acc = acc
	_scope.show_mode("solder", "SOLDER", ("Clean joints!" if acc >= 0.8 else "A bit messy.") if completed else "Ran out of time. Cold joints.",
		{"lit": _solder.lit(), "n": _solder.n_pads, "acc": acc})
	if completed and acc >= 0.8:
		Sfx.play("good", 0.03, -8.0)
	_busy = true
	var g := _gen
	await _wait(0.9)
	if g != _gen:
		return
	_busy = false
	_enter(Step.TEST)

# --- 4 probar

func _enter_test() -> void:
	var d: Dictionary = BenchData.ITEMS[item]
	_gauge.setup(float(d.get("sweep", 0.9)), float(d.get("zone", 0.2)), _seed + 7)
	_scope.show_mode("test", "POWER TEST", "Stop it in the green.", {"verdict": ""})
	_set_instr("Power test: stop the needle in the green!")
	_tip_lbl.text = BenchData.KETTLE_TUTORIAL["test"] if _tutorial else "The bright middle is perfect."
	_kettle.say(String(BenchData.KETTLE["test"]), 2.0)

func _on_test_stopped(v: String) -> void:
	if step != Step.TEST:
		return
	_test = v
	_clock_on = false
	_scope.show_mode("test", "POWER TEST", {"perfect": "Right in the middle!", "good": "In the green.",
		"ok": "Just outside the green.", "miss": "Missed the green."}.get(v, ""), {"verdict": v})
	_busy = true
	var g := _gen
	await _wait(0.75)
	if g != _gen:
		return
	_gauge.visible = false
	_tip_tag.visible = false
	var tw := create_tween()
	tw.tween_property(_stage, "dim", 0.0, 0.2)
	# ¡funciona! (o casi)
	if v != "miss":
		match item:
			"radio":
				_stage.power("notes")
				Sfx.play("good", 0.02, -4.0)
			"thruster":
				_stage.power("flame")
				Sfx.play("takeoff", 0.05, -10.0)
			_:
				Sfx.play("good", 0.02, -4.0)
		_power_line = String(BenchData.ITEMS[item].get("power", "It works!"))
		if BenchData.ITEMS[item].get("talks", false):
			var after := String(_bot_talk().get(fault, {}).get("after", "Hello!"))
			if "%s" in after:
				after = after % Data.char_name(String(job.get("customer", ""))) if String(job.get("customer", "")) != "" else after.replace(", %s", "")
			_stage.bot_say(after, 2.4)
			_power_line = "“%s”" % after
		_set_instr(String(_bot_talk().get("power", "")) if _self else String(BenchData.ITEMS[item].get("power", "It works!")))
	else:
		_stage.power("sputter")
		Sfx.play("bad", 0.02, -6.0)
		_power_line = "It works... barely."
		_set_instr(_power_line)
	await _wait(1.4)
	if g != _gen:
		return
	_busy = false
	_enter(Step.RESULT)

# --- el resultado

func _score() -> float:
	var sc: Dictionary = BenchData.SCORE
	var s := 3.0
	s -= float(sc["wrong"]) * _wrong
	if _patched:
		s -= float(sc["patch"])
	if not _solder_done:
		s -= float(sc["cold"])
	s -= float(sc["mess"]) * (1.0 - _solder_acc)
	s -= float(sc["test"].get(_test, 1.5))
	return s

func _time_total() -> float:
	return snappedf(_elapsed + _penalty, 0.1)

func _enter_result() -> void:
	var stars := BenchData.stars_for(_score())
	_result = {"ok": true, "stars": stars, "time": _time_total(), "fault_found": _found, "patched": _patched,
		"parts_used": _parts_used.duplicate(), "wrong": _wrong, "solder": snappedf(_solder_acc, 0.01), "test": _test,
		"tools": _tools_used.duplicate()}
	_card_title.text = ["FIXED... SORT OF", "FIXED", "NICE REPAIR", "GOOD AS NEW"][stars]
	_stage.hide_bubble()
	_card_quote.text = _power_line
	_card_quote_tag.visible = _power_line != ""
	_card_title.add_theme_color_override("font_color", UIKit.ACCENT if stars >= 2 else (BenchKit.CREAM if stars == 1 else BenchKit.RED))
	_card_icon.texture = BenchKit.tex("res://assets/items/%s_closed.png" % item)
	if _self:
		# --- SS MERGE: el retrato del propio cliente (la parte de arriba de su hoja de 64x96)
		var at := AtlasTexture.new()
		at.atlas = BenchKit.tex("res://assets/chars/%s_idle.png" % String(job.get("customer", "clatter")))
		at.region = Rect2(0, 0, 64, 64)
		_card_icon.texture = at
	for i in 3:
		var st: Control = _card_stars.get_child(i)
		st.modulate = Color(1, 1, 1, 1) if i < stars else Color(0.2, 0.18, 0.17, 0.85)
	for c in _card_lines.get_children():
		_card_lines.remove_child(c)
		c.queue_free()
	var pn := BenchData.part_name(fault).to_lower()
	_card_line(_wrong == 0, "Found the %s first try" % pn if _wrong == 0 else "Found the %s after %s" % [pn, UIKit.plural(_wrong, "wrong guess", "wrong guesses")])
	_card_line(not _patched, "New %s fitted" % pn if not _patched else "Patched (no new part)")
	var acc := int(round(_solder_acc * 100.0))
	_card_line(_solder_done and _solder_acc >= 0.7, ("Clean solder (%d%%)" % acc if _solder_acc >= 0.7 else "Messy solder (%d%%)" % acc) if _solder_done else "Cold joints (ran out of time)")
	_card_line(_test in ["perfect", "good"], {"perfect": "Test: right in the middle", "good": "Test: in the green",
		"ok": "Test: just outside the green", "miss": "Test: missed the green"}.get(_test, "Test"))
	_card_time.text = "Time %s%s" % [_fmt_time(_time_total()), ("  (+%ds for wrong guesses)" % int(_penalty)) if _penalty > 0.0 else ""]
	_card.visible = true
	_card.reset_size()
	UIKit.pop_in(_card)
	var dl: Array = BenchData.KETTLE["done"]
	if stars >= 2:
		_kettle.whistle(String(dl[stars]))
	else:
		_kettle.say(String(dl[stars]), 3.0)
	_set_instr("")
	Sfx.play("coins" if stars >= 2 else "blip", 0.03, -4.0)

## --- SS MERGE: lo que dice el bot del banco (el de bolsillo, o el propio cliente si viene a arreglarse él).
func _bot_talk() -> Dictionary:
	return BenchData.BOT_TALK_SELF if _self else BenchData.BOT_TALK

func _card_line(good: bool, text: String) -> void:
	var h := UIKit.hbox(10)
	var mark := UIKit.label("✓" if good else "✗", 22, BenchKit.GREEN if good else BenchKit.RED, UIKit.font_bold)
	mark.custom_minimum_size = Vector2(24, 0)
	h.add_child(mark)
	h.add_child(UIKit.label(text, 21, BenchKit.CREAM, UIKit.font_regular))
	_card_lines.add_child(h)

func _done() -> void:
	if not visible or step != Step.RESULT:
		return
	_emit(_result)

# --- rendirse

func _ask_give_up() -> void:
	if not visible or step in [Step.NONE, Step.RESULT] or _confirm:
		return
	_confirm = true
	_instr.visible = false
	_hints_box.visible = false
	_giveup_btn.visible = false
	_confirm_box.visible = true
	BenchKit.refresh_keys(_confirm_box)

func _cancel_give_up() -> void:
	_confirm = false
	_instr.visible = true
	_hints_box.visible = true
	_giveup_btn.visible = step != Step.RESULT
	_confirm_box.visible = false

func _give_up() -> void:
	if not visible or step == Step.NONE:
		return
	_cancel_give_up()
	_emit({"ok": false, "stars": 0, "time": _time_total(), "fault_found": _found, "patched": _patched,
		"parts_used": _parts_used.duplicate(), "wrong": _wrong, "solder": 0.0, "test": "", "tools": _tools_used.duplicate()})

func _emit(r: Dictionary) -> void:
	_gen += 1
	visible = false
	step = Step.NONE
	_busy = false
	_clock_on = false
	finished.emit(r)

# ------------------------------------------------------------------ tiempo, entrada

func _process(delta: float) -> void:
	if not visible:
		return
	if _clock_on and step in [Step.DIAGNOSE, Step.SWAP, Step.SOLDER, Step.TEST]:
		_elapsed += delta
	var tt := _elapsed + _penalty
	_timer_lbl.text = _fmt_time(tt)
	_timer_lbl.add_theme_color_override("font_color", BenchKit.AMBER if tt < 35.0 else (Color(1.0, 0.55, 0.3) if tt < 45.0 else BenchKit.RED))
	if PadCursor.pad_in_use != _last_pad:
		_refresh_hints()

func _fmt_time(s: float) -> String:
	var t := int(s)
	return "%d:%02d" % [t / 60, t % 60]

func _flash_penalty() -> void:
	_pen_lbl.text = "+%ds" % int(BenchData.SCORE["wrong_secs"])
	_pen_lbl.modulate.a = 1.0
	_pen_lbl.position = Vector2(HEADER.end.x - 64, HEADER.end.y + 4)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_pen_lbl, "position:y", HEADER.end.y + 24, 0.9)
	tw.tween_property(_pen_lbl, "modulate:a", 0.0, 0.9).set_delay(0.3)

func _lock(secs: float) -> void:
	_busy = true
	var g := _gen
	await _wait(secs)
	if g == _gen:
		_busy = false

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

## Un clic en cualquier lado (fuera de los botones) para la aguja del test (así el A del mando sirve donde esté
## el cursor).
func _on_bg_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if step == Step.TEST and not _confirm:
			_gauge.press()

func _gui_input(ev: InputEvent) -> void:
	_on_bg_input(ev)

func _input(ev: InputEvent) -> void:
	if not visible or step == Step.NONE or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	var lk: int = ev.keycode if ev.keycode != KEY_NONE else k      # las letras, según la distribución del teclado
	var go := k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or lk == KEY_E
	if _confirm:
		if k == KEY_ESCAPE:
			_give_up()
		elif go:
			_cancel_give_up()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if k == KEY_ESCAPE:
		if step == Step.RESULT:
			_done()
		else:
			_ask_give_up()
		get_viewport().set_input_as_handled()
		return
	var used := true
	match step:
		Step.DIAGNOSE:
			if k >= KEY_1 and k <= KEY_4:
				_pick(k - KEY_1)
			elif lk == KEY_L:
				_use_tool("listen")
			elif lk == KEY_T:
				_use_tool("tap")
			elif lk == KEY_S:
				_use_tool("scan")
			else:
				used = false
		Step.SWAP:
			if go:
				_swap_primary()
			elif lk == KEY_P:
				_do_patch()
			else:
				used = false
		Step.SOLDER:
			used = k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_W, KEY_A, KEY_S, KEY_D]
		Step.TEST:
			if go:
				_gauge.press()
			else:
				used = false
		Step.RESULT:
			if go:
				_done()
			else:
				used = false
	if used:
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ bot y capturas

## Juega solo. stop_at: "" (hasta el final, emite finished) o el paso donde quedarse (capturas).
func _bot_run(skill: float, stop_at: String) -> void:
	var g := _gen
	await _wait(0.25)
	if g != _gen:
		return
	# 1 diagnosticar: la mejor herramienta, y (si es torpe) primero una pieza equivocada
	var best := BenchData.best_tool(item)
	if stop_at == "diagnose":
		_use_tool(best)
		await _wait(0.5)
		if g == _gen:
			_stage.hover_i = fault_i
		return
	if stop_at == "wrong" or (skill < 0.999 and randf() > skill):
		var wrong := (fault_i + 1 + randi() % maxi(1, slots.size() - 1)) % slots.size()
		_pick(wrong)
		await _until(func(): return not _busy, 3.0)
		if stop_at == "wrong" or g != _gen:
			return
	_use_tool(best)
	await _until(func(): return not _busy, 3.0)
	await _wait(0.3)
	if g != _gen:
		return
	_pick(fault_i)
	# 2 cambiar (si no hay repuesto, parche)
	var ok: bool = await _until(func(): return step == Step.SWAP and not _busy, 6.0)
	if not ok or g != _gen:
		return
	if stop_at == "swap":
		return
	if Game.has_part(fault) and skill >= 0.3:
		_do_swap()
	else:
		_do_patch()
	# 3 soldar
	ok = await _until(func(): return step == Step.SOLDER and not _busy, 6.0)
	if not ok or g != _gen:
		return
	_solder.auto_wobble = (1.0 - skill) * 45.0
	_solder.auto_until = 0.55 if stop_at == "solder" else 1.0
	if stop_at == "solder":
		return
	# 4 probar
	ok = await _until(func(): return step == Step.TEST, 15.0)
	if not ok or g != _gen:
		return
	if stop_at == "test":
		return
	_gauge.auto_miss = (1.0 - skill) * 0.22 * (1.0 if randf() < 0.5 else -1.0)
	_gauge.auto = true
	ok = await _until(func(): return step == Step.RESULT, 15.0)
	if not ok or g != _gen:
		return
	if stop_at == "result":
		return
	await _wait(0.4)
	if g == _gen:
		_done()

## Espera hasta que cond() sea verdad (o pase el tiempo). true si se cumplió.
func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if not visible:
			return false
		if cond.call():
			return true
		await _wait(0.05)
		t += 0.05
	return bool(cond.call())
