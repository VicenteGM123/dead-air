extends Control
class_name HaggleUI
## El regateo (comprar cápsulas al Raker, vender cosas reparadas del estante): el otro pone un precio; Nell
## contraoferta (LOW / FAIR / FIRM, ordenadas por precio) o acepta; 2-3 intercambios y después "es mi último precio".
## Un medidor de ánimo reacciona; si llega a cero, se va. Cada especie tiene su costumbre y su señal (BenchData.HAGGLE):
##   Hornback: aceptar su primer precio lo ofende (el precio empeora): siempre contraofertar una vez; resopla y
##     pisotea cuando su precio ya está cerca de su límite.
##   Quill: dice "¡última oferta!" siempre; si la cresta parpadea es un farol (se puede insistir); quieta = de verdad.
##     Impaciente (el ánimo baja rápido); si el trato se cierra enseguida, deja propina.
##   Glimmerfolk: primero ofrece un trueque (piezas en vez de créditos); sus pensamientos brillan cálidos con un precio
##     que le gusta (al pasar el cursor por una contraoferta se ve la reacción).
##   Burrower: tímido, monedas chicas; un precio alto lo asusta (se esconde y se enoja más).
##   Humano (Rook): un reloj de despegue; cerca del despegue mira la hora y paga más; si llega a cero se va.
##   Bot (Clatter): dice su presupuesto en voz alta; acepta hasta ahí, nunca más; no se enoja.
##   Dune Raker: vende cápsulas cerradas (peso y traqueteo a la vista); saca la lengua cuando su precio ya es bueno.
## --- SS BENCH: reemplaza el placeholder de la semilla con el MISMO contrato (SS_BRIEF §3):
##   open(deal)  deal = {"mode": "buy" | "sell", "what", "species", "base", "customer", "name"} (BenchData.make_deal)
##               (opcionales: "item", "stars" (lo que se vende), "pod" (la cápsula que se compra), "seed")
##               "buy": Nell compra (el otro pide); "sell": Nell vende (el otro ofrece).
##   signal finished(result)  {"deal": bool, "price": int, "mood": 0..1} (+ "barter": part_id y "barter_n": n si se
##               aceptó un trueque (price 0); "tip": la propina incluida en price; "rounds")
##   close_now(), is_open(), bot_play(skill := 1.0) (asíncrono: termina con finished)
## HaggleUI NO toca Game: quien lo abre aplica el trato (créditos, cápsula, estante, piezas del trueque).
## Controles: ratón; teclado 1 / 2 / 3 contraofertas, Intro / E / Espacio acepta, Esc se va; en el trueque 1 acepta
## las piezas y 2 pide créditos; mando: cursor (LB / RB, A), X = Espacio (aceptar), B = irse.

signal finished(result: Dictionary)

const PLATE := Rect2(110, 44, 1060, 632)
const HEADER := Rect2(134, 58, 1012, 46)
const BOOTH := Rect2(134, 114, 372, 432)
const RIGHT_X := 528.0
const RIGHT_W := 618.0

var deal := {}
var _buy := true
var _sp := "human"
var _who := ""
var _r := {}
var _base := 10.0
var _limit := 10.0           # escondido: al comprar, lo mínimo que acepta; al vender, lo máximo que paga
var _price := 10             # su precio de ahora
var _mood := 0.8
var _round := 0              # contraofertas hechas
var _rounds := 3
var _final := false
var _barter := ""            # pieza que ofrece (Glimmerfolk) mientras el trueque está en la mesa
var _barter_n := 0
var _last := -1              # la última contraoferta de Nell
var _clock := 0.0            # el reloj de despegue (humano vendiendo... bueno, comprándole a Nell)
var _hurried := false
var _done := false
var _busy := false
var _gen := 0
var _opts: Array = [-1, -1, -1]
var _hover_k := -1
var _last_pad := false
var _rng := RandomNumberGenerator.new()

var _canvas: Control
var _title: Label
var _pips: HBoxContainer
var _portrait: BenchPortrait
var _bubble: BenchBubble
var _name_lbl: Label
var _species_lbl: Label
var _goods_icon: TextureRect
var _goods_title: Label
var _goods_lines: Label
var _price_head: Label
var _wallet: Label            # --- SS MERGE
var _price_big: Label
var _price_sub: Label
var _mood_bar: Control
var _mood_word: Label
var _counter_btns: Array = []
var _accept_btn: Button
var _walk_btn: Button
var _barter_take: Button
var _barter_no: Button
var _habit: Label
var _hints_box: Control
var _depart: PanelContainer
var _depart_lbl: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (después de entrar al árbol: anclas Y márgenes)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	visible = false
	_build()

# ------------------------------------------------------------------ contrato

func open(d: Dictionary) -> void:
	_gen += 1
	deal = d.duplicate(true)
	_buy = String(deal.get("mode", "sell")) == "buy"
	_who = String(deal.get("customer", ""))
	_sp = String(deal.get("species", ""))
	if _sp == "" or not BenchData.HAGGLE.has(_sp):
		_sp = Data.species_of(_who) if _who != "" else "human"
	_r = BenchData.haggle_rules(_sp)
	if deal.has("seed"):
		_rng.seed = int(deal["seed"])
	else:
		_rng.randomize()
	_base = maxf(1.0, float(deal.get("base", 10)))
	_limit = _base * float(_r["floor"] if _buy else _r["ceiling"]) * _rng.randf_range(0.96, 1.04)
	_price = int(round(_base * float(_r["ask"] if _buy else _r["offer"])))
	_price = maxi(_price, ceili(_limit)) if _buy else mini(_price, floori(_limit))
	_price = maxi(1, _price)
	_mood = 0.8
	_round = 0
	_rounds = int(_r.get("rounds", 3))
	_final = _rounds <= 0
	_last = -1
	_done = false
	_busy = false
	_hurried = false
	_hover_k = -1
	_clock = 28.0 if (_r.get("rule", "") == "departure_clock" and not _buy) else 0.0
	_barter = ""
	_barter_n = 0
	if _r.get("rule", "") == "barter_first" and not _buy:
		_pick_barter()
	_fill()
	visible = true
	UIKit.pop_in(_canvas)
	Sfx.blip()
	# la primera frase
	if _barter != "":
		_say(BenchData.haggle_line(_sp, "barter", [_barter_text()]), "")
		_portrait.set_glow("mild")
	elif _sp == "bot" and not _buy:
		_say(BenchData.haggle_line(_sp, "open_sell", [floori(_limit), _price]), String(BenchData.HAGGLE_LINES["bot"]["tell"]))
		_portrait.fx("calc", 1.6)
	else:
		_say(BenchData.haggle_line(_sp, "open_buy" if _buy else "open_sell", [_price]), "")
		if _sp == "glimmerfolk":
			_portrait.set_glow("")
	_after_move_tells(true)
	_refresh()

func is_open() -> bool:
	return visible

func close_now() -> void:
	_gen += 1
	visible = false
	_done = true

## El bot de autoplay: rechaza el trueque, contraoferta "fair" una vez (y otra si el Quill blufea), y si no se
## cerró, acepta el precio que quede. skill < 1: a veces acepta enseguida (torpe).
func bot_play(skill := 1.0) -> void:
	if not visible:
		return
	_bot_run(clampf(skill, 0.0, 1.0), "")

## Capturas: "open" (como se abre), "counter" (después de una contraoferta rechazada), "deal" (cerrado), "hover"
## (el cursor sobre una contraoferta: la reacción de Oona), "tell" (la señal de la especie: el Hornback ofendido por
## un sí rápido, la cresta del Quill, el Burrower que se esconde, el piloto que mira la hora, la lengua del Raker).
## demo_ready = true cuando llegó.
var demo_ready := false

func demo_to(step: String) -> void:
	if not visible:
		return
	demo_ready = false
	if step == "tell":
		_demo_tell()
		return
	_bot_run(1.0, step)

func _demo_tell() -> void:
	var g := _gen
	await get_tree().create_timer(0.35).timeout
	if g != _gen:
		return
	match _sp:
		"hornback":
			_accept()
		"quill", "burrower":
			_counter(0 if _buy else 2)
		"human":
			_clock = minf(_clock, 10.3)
			await get_tree().create_timer(0.5).timeout
		"duneraker":
			for i in 2:
				_counter(0)
				await get_tree().create_timer(0.45).timeout
		"glimmerfolk":
			_decline_barter()
			await get_tree().create_timer(0.4).timeout
			_on_counter_hover(0, true)
	demo_ready = true

# ------------------------------------------------------------------ armado (una vez)

func _build() -> void:
	var dim := UIKit.dim_overlay()
	dim.color = Color(0.02, 0.015, 0.01, 0.55)
	add_child(dim)
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
	var plate := BenchKit.plate(16)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BenchKit.at(plate, PLATE)
	_canvas.add_child(plate)
	# cabecera
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	BenchKit.at(h, HEADER)
	_canvas.add_child(h)
	var ic := UIKit.ui_icon("credits", 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := BenchKit.shadow(UIKit.label("HAGGLE", 26, UIKit.ACCENT, UIKit.font_bold))
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	_title = BenchKit.shadow(UIKit.label("", 24, BenchKit.CREAM, UIKit.font_bold))
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_title)
	# --- SS MERGE: al comprar, lo que tiene Nell (la placa de arriba queda tapada mientras regatea)
	_wallet = UIKit.label("", 18, UIKit.MUTED, UIKit.font_bold)
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_wallet)
	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var ex := UIKit.label("Exchanges", 17, UIKit.MUTED, UIKit.font_bold)
	ex.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ex)
	_pips = UIKit.hbox(6)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_pips)
	# la cabina con el personaje
	_portrait = BenchPortrait.new()
	BenchKit.at(_portrait, BOOTH)
	_canvas.add_child(_portrait)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = Color(0.03, 0.02, 0.02, 0.95)
	fsb.set_border_width_all(4)
	fsb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", fsb)
	BenchKit.at(frame, BOOTH.grow(2))
	_canvas.add_child(frame)
	var nb := HBoxContainer.new()
	nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nb.add_theme_constant_override("separation", 10)
	BenchKit.at(nb, Rect2(BOOTH.position.x + 4, BOOTH.end.y + 8, BOOTH.size.x, 32))
	_name_lbl = BenchKit.shadow(UIKit.label("", 24, BenchKit.CREAM, UIKit.font_bold))
	nb.add_child(_name_lbl)
	_species_lbl = UIKit.label("", 18, UIKit.MUTED, UIKit.font_regular)
	_species_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	nb.add_child(_species_lbl)
	_canvas.add_child(nb)
	# el consejo de la especie (etiqueta de papel)
	var tag := BenchKit.tag(10)
	tag.position = Vector2(BOOTH.position.x, BOOTH.end.y + 48)
	tag.custom_minimum_size = Vector2(BOOTH.size.x, 0)
	_habit = UIKit.label("", 24, BenchKit.INK, UIKit.font_hand)
	_habit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_habit.custom_minimum_size = Vector2(BOOTH.size.x - 56, 0)
	tag.add_child(_habit)
	_canvas.add_child(tag)
	# el reloj de despegue (el piloto)
	_depart = BenchKit.screen(8)
	var dsb: StyleBox = _depart.get_theme_stylebox("panel").duplicate()
	dsb.content_margin_top = 4
	dsb.content_margin_bottom = 4
	dsb.content_margin_left = 12
	dsb.content_margin_right = 12
	_depart.add_theme_stylebox_override("panel", dsb)
	_depart.position = BOOTH.position + Vector2(BOOTH.size.x - 178, 12)
	_depart_lbl = UIKit.label("LAUNCH 0:28", 20, BenchKit.AMBER, UIKit.font_mono)
	_depart.add_child(_depart_lbl)
	_canvas.add_child(_depart)
	# lo que se compra o vende
	var goods := Panel.new()
	goods.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goods.add_theme_stylebox_override("panel", BenchKit.inset_style(Color(0.08, 0.075, 0.07, 0.95), 6))
	BenchKit.at(goods, Rect2(RIGHT_X, BOOTH.position.y, 148, 148))
	_canvas.add_child(goods)
	_goods_icon = BenchKit.pixel_rect(null, 2.0)
	BenchKit.at(_goods_icon, Rect2(RIGHT_X + 10, BOOTH.position.y + 10, 128, 128))
	_canvas.add_child(_goods_icon)
	var gt := BenchKit.tag(10)
	gt.position = Vector2(RIGHT_X + 162, BOOTH.position.y + 4)
	gt.custom_minimum_size = Vector2(RIGHT_W - 162, 0)
	var gv := UIKit.vbox(0)
	_goods_title = UIKit.label("", 22, BenchKit.INK, UIKit.font_bold)
	gv.add_child(_goods_title)
	_goods_lines = UIKit.label("", 26, Color("4a3a30"), UIKit.font_hand)
	gv.add_child(_goods_lines)
	gt.add_child(gv)
	_canvas.add_child(gt)
	# el precio (pantalla CRT)
	var scr := BenchKit.screen(12)
	BenchKit.at(scr, Rect2(RIGHT_X, BOOTH.position.y + 160, RIGHT_W, 112))
	var sv := HBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_theme_constant_override("separation", 18)
	var pl := UIKit.vbox(0)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_head = UIKit.label("THEY ASK", 18, BenchKit.AMBER_DIM, UIKit.font_mono)
	pl.add_child(_price_head)
	_price_big = UIKit.label("", 46, BenchKit.AMBER, UIKit.font_mono)
	pl.add_child(_price_big)
	sv.add_child(pl)
	_price_sub = UIKit.label("", 18, BenchKit.AMBER, UIKit.font_mono)
	_price_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_price_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_price_sub)
	scr.add_child(sv)
	_canvas.add_child(scr)
	# el ánimo
	var mr := HBoxContainer.new()
	mr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mr.add_theme_constant_override("separation", 12)
	BenchKit.at(mr, Rect2(RIGHT_X + 4, BOOTH.position.y + 282, RIGHT_W - 8, 34))
	var ml := UIKit.label("Mood", 20, BenchKit.CREAM, UIKit.font_bold)
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mr.add_child(ml)
	_mood_bar = Control.new()
	_mood_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mood_bar.custom_minimum_size = Vector2(360, 26)
	_mood_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mood_bar.draw.connect(_draw_mood)
	mr.add_child(_mood_bar)
	_mood_word = UIKit.label("", 20, BenchKit.CREAM, UIKit.font_bold)
	_mood_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mr.add_child(_mood_word)
	_canvas.add_child(mr)
	# las contraofertas
	var names := ["LOW", "FAIR", "FIRM"]
	var bw := floorf((RIGHT_W - 24.0) / 3.0)
	for k in 3:
		var kk := k
		var b := BenchKit.key_button("", str(k + 1), func(): _counter(kk), Vector2(bw, 74), "", false, 22)
		var row: HBoxContainer = b.find_child("Row", true, false)
		var txt: Label = b.find_child("Text", true, false)
		var col := UIKit.vbox(-4)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var cap := UIKit.label(names[k], 14, Color("6a5a50"), UIKit.font_bold)
		cap.name = "Cap"
		row.remove_child(txt)
		col.add_child(cap)
		col.add_child(txt)
		row.add_child(col)
		row.move_child(col, 0)
		b.position = Vector2(RIGHT_X + k * (bw + 12.0), BOOTH.position.y + 328)
		b.mouse_entered.connect(func(): _on_counter_hover(kk, true))
		b.mouse_exited.connect(func(): _on_counter_hover(kk, false))
		_canvas.add_child(b)
		_counter_btns.append(b)
	_accept_btn = BenchKit.key_button("Accept", "Enter", func(): _accept(), Vector2(RIGHT_W * 0.56, 62), "credits", true, 22)
	_accept_btn.position = Vector2(RIGHT_X, BOOTH.position.y + 414)
	_canvas.add_child(_accept_btn)
	_walk_btn = BenchKit.key_button("Walk away", "Esc", func(): _walk_away(), Vector2(RIGHT_W * 0.44 - 12.0, 62), "", false, 21)
	_walk_btn.position = Vector2(RIGHT_X + RIGHT_W * 0.56 + 12.0, BOOTH.position.y + 414)
	_canvas.add_child(_walk_btn)
	# el trueque (Glimmerfolk): dos botones en lugar de las contraofertas
	_barter_take = BenchKit.key_button("", "1", func(): _take_barter(), Vector2(RIGHT_W * 0.56, 74), "", true, 21)
	_barter_take.position = Vector2(RIGHT_X, BOOTH.position.y + 328)
	_barter_take.visible = false
	_canvas.add_child(_barter_take)
	_barter_no = BenchKit.key_button("Credits, please", "2", func(): _decline_barter(), Vector2(RIGHT_W * 0.44 - 12.0, 74), "", false, 21)
	_barter_no.position = Vector2(RIGHT_X + RIGHT_W * 0.56 + 12.0, BOOTH.position.y + 328)
	_barter_no.visible = false
	_canvas.add_child(_barter_no)
	_hints_box = BenchKit.group(Rect2(RIGHT_X, BOOTH.position.y + 494, RIGHT_W, 40))
	_canvas.add_child(_hints_box)
	_bubble = BenchBubble.new()
	_bubble.max_width = 340.0
	_bubble.tail_x = 0.35
	_bubble.font_size = 20
	_canvas.add_child(_bubble)

func _draw_mood() -> void:
	var w := _mood_bar.size.x
	var hgt := _mood_bar.size.y
	_mood_bar.draw_rect(Rect2(0, 0, w, hgt), Color(0.04, 0.03, 0.03, 0.9))
	var n := 12
	var seg := (w - 4.0) / n
	var filled := int(round(_mood * n))
	for i in n:
		var u := float(i) / float(n - 1)
		var col := Color(0.86, 0.3, 0.22).lerp(Color(1.0, 0.75, 0.3), clampf(u * 2.0, 0.0, 1.0))
		if u > 0.5:
			col = Color(1.0, 0.75, 0.3).lerp(Color(0.5, 0.86, 0.42), (u - 0.5) * 2.0)
		if i >= filled:
			col = Color(0.16, 0.14, 0.13)
		_mood_bar.draw_rect(Rect2(2 + i * seg + 1, 3, seg - 3, hgt - 6), col)

# ------------------------------------------------------------------ lo que se ve

func _fill() -> void:
	var what := String(deal.get("what", "?"))
	_title.text = ("Buying: %s" if _buy else "Selling: %s") % what
	_wallet.text = ("·  you have %d cr" % Game.credits) if _buy else ""   # --- SS MERGE
	_name_lbl.text = String(deal.get("name", Data.char_name(_who)))
	_species_lbl.text = String(Data.SPECIES.get(_sp, {}).get("name", _sp.capitalize()))
	_portrait.set_char(_who if _who != "" else "nell")
	_habit.text = String(_r.get("habit", ""))
	# la mercadería
	var icon_path := ""
	var lines: Array = []
	if deal.has("pod") and deal["pod"] is Dictionary:
		var pod: Dictionary = deal["pod"]
		icon_path = "res://assets/items/pod_closed.png"
		_goods_title.text = "Sealed salvage pod"
		lines.append("Weight: %s" % BenchData.POD_WEIGHT[clampi(int(pod.get("weight", 1)) - 1, 0, 2)])
		lines.append("Rattle: %s" % BenchData.POD_RATTLE[clampi(int(pod.get("rattle", 0)), 0, 2)])
	elif deal.has("item"):
		icon_path = "res://assets/items/%s_closed.png" % String(deal["item"])
		_goods_title.text = BenchData.item_name(String(deal["item"]))
		if deal.has("stars"):
			var st := int(deal["stars"])
			lines.append("Refurbished  " + "★".repeat(st) + "☆".repeat(3 - st))
	else:
		_goods_title.text = what
		if what.to_lower().contains("pod"):
			icon_path = "res://assets/items/pod_closed.png"
	lines.append("Fair price ~%d cr" % int(round(_base)))
	_goods_lines.text = "\n".join(lines)
	_goods_icon.texture = BenchKit.tex(icon_path) if icon_path != "" else null
	_price_head.text = "THEY ASK" if _buy else "THEY OFFER"
	_depart.visible = _clock > 0.0
	for c in _pips.get_children():
		_pips.remove_child(c)
		c.queue_free()
	for i in _rounds:
		var p := Panel.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.custom_minimum_size = Vector2(16, 16)
		_pips.add_child(p)

func _refresh() -> void:
	_opts = _options()
	var verb := "Offer" if _buy else "Ask"
	var barter := _barter != ""
	for k in 3:
		var b: Button = _counter_btns[k]
		b.visible = not barter
		var c: int = _opts[k]
		BenchKit.set_text(b, ("%s %d" % [verb, c]) if c > 0 and not _done else "—")
		BenchKit.enable(b, c > 0 and not _final and not _done and not barter)
	_barter_take.visible = barter
	_barter_no.visible = barter
	if barter:
		BenchKit.set_text(_barter_take, "Take %s" % _barter_text())
	BenchKit.enable(_accept_btn, not _done and not barter)
	BenchKit.set_text(_accept_btn, "Accept %d cr" % _price)
	BenchKit.enable(_walk_btn, not _done)
	_price_big.text = ("%d cr" % _price) if not barter else "TRADE"
	var sub := ""
	if _final and not _done:
		sub = "FINAL PRICE"
	elif _last > 0:
		sub = "You said %d" % _last
	_price_sub.text = sub
	_mood_word.text = BenchData.mood_word(_mood)
	_mood_bar.queue_redraw()
	for i in _pips.get_child_count():
		var p: Panel = _pips.get_child(i)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.bg_color = UIKit.ACCENT if i < _round else Color(0.12, 0.11, 0.1)
		sb.border_color = UIKit.ACCENT_BRIGHT if i < _round else Color(0.4, 0.37, 0.33)
		sb.set_border_width_all(2)
		p.add_theme_stylebox_override("panel", sb)
	_refresh_hints()

func _refresh_hints() -> void:
	for c in _hints_box.get_children():
		c.queue_free()
	_last_pad = PadCursor.pad_in_use
	if _done:
		return     # trato cerrado: ya no hay nada que tocar
	var items: Array = []
	if _barter != "":
		items = [{"keys": ["1"], "text": "take the parts"}, {"keys": ["2"], "text": "credits"},
			{"pad": ["LB", "RB"], "text": "select"}, {"pad": ["A"], "text": "choose"}]
	else:
		items = [{"keys": ["1", "2", "3"], "text": "counter"}, {"keys": ["Enter"], "text": "accept"}, {"keys": ["Esc"], "text": "walk away"},
			{"pad": ["LB", "RB"], "text": "select"}, {"pad": ["A"], "text": "choose"}, {"pad": ["B"], "text": "walk away"}]
	var row := BenchKit.hints(items, 17)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hints_box.add_child(row)
	BenchKit.refresh_keys(_canvas)
	_last_pad = PadCursor.pad_in_use

func _say(text: String, caption: String) -> void:
	_bubble.say(text, caption)
	_bubble.point_at(BOOTH.position + _portrait.top_point() + Vector2(0, -6))

func _barter_text() -> String:
	var pn := BenchData.part_name(_barter)
	return ("a %s" % pn.to_lower()) if _barter_n <= 1 else ("%d %ss" % [_barter_n, pn.to_lower()])

# ------------------------------------------------------------------ reglas

## Las tres contraofertas (precios enteros, de menor a mayor; -1 = no tiene sentido).
func _options() -> Array:
	var out: Array = []
	# los límites en enteros (así el redondeo nunca deja afuera la contraoferta FIRM)
	var lo := 0
	var hi := 0
	var fr: Array = []
	if _buy:
		lo = ceili(_base * (0.62 + 0.06 * _round))
		if _last > 0:
			lo = maxi(lo, _last + 1)
		hi = _price - 1
		fr = [0.0, 0.45, 0.8]
	else:
		lo = _price + 1
		hi = floori(_base * (1.36 - 0.05 * _round))
		if _last > 0:
			hi = mini(hi, _last - 1)
		fr = [0.2, 0.55, 1.0]
		if _r.get("rule", "") == "fixed_savings" and floori(_limit) >= lo + 1:
			# el bot dijo su presupuesto en voz alta: FAIR es justo ese número (lógico, sin farol)
			var b := floori(_limit)
			return [int(round(lerpf(float(_price), float(b), 0.5))), b, maxi(b + 2, int(round(_base * 1.3)))]
	if hi < lo + 2:
		return [-1, -1, -1]
	for f in fr:
		out.append(int(round(lerpf(float(lo), float(hi), f))))
	for i in 3:
		if i > 0 and out[i] <= out[i - 1]:
			out[i] = out[i - 1] + 1
		if out[i] < lo or out[i] > hi or out[i] < 1:
			out[i] = -1
	return out

func _acceptable(c: int) -> bool:
	return float(c) >= _limit if _buy else float(c) <= _limit

func _counter(k: int) -> void:
	if not visible or _done or _busy or _final or _barter != "" or k < 0 or k > 2:
		return
	var c: int = _opts[k]
	if c <= 0:
		return
	_round += 1
	_last = c
	if _clock > 0.0:
		_clock = maxf(1.0, _clock - 4.0)
	_portrait.set_hiding(false)
	if _acceptable(c):
		_mood = clampf(_mood - float(_r["temper"]) * 0.4 * absf(float(c - _price)) / _base, 0.0, 1.0)
		if _sp == "glimmerfolk":
			_portrait.set_glow("warm")
		_close(c, BenchData.haggle_line(_sp, "accept"))
		return
	# rechazada: baja el ánimo (más cuanto más lejos de su límite)
	var over := absf(float(c) - _limit) / _base
	_mood -= float(_r["temper"]) * (0.7 + 2.5 * over)
	var caption := ""
	if _r.get("rule", "") == "small_coins" and not _buy and float(c) > _limit * 1.08:
		_mood -= 0.15
		_portrait.set_hiding(true)
		caption = String(BenchData.HAGGLE_LINES["burrower"]["tell"])
	if _sp == "glimmerfolk":
		_portrait.set_glow(_glow_for(c))
	_mood = clampf(_mood, 0.0, 1.0)
	if _mood <= 0.02:
		_leave(BenchData.haggle_line(_sp, "walk"))
		return
	# se acerca a su límite (al final, un último paso grande)
	var give := float(_r.get("give", 0.4))
	if _round >= _rounds:
		_final = true
		if give > 0.0:
			_move_price(maxf(give, 0.6))
		_say(BenchData.haggle_line(_sp, "final", [_price]), caption)
	else:
		_move_price(give)
		_say(BenchData.haggle_line(_sp, "reject", [_price]), caption)
	Sfx.play("blip", 0.08, -6.0)
	_after_move_tells(false)
	_lock(0.3)
	_refresh()

func _move_price(f: float) -> void:
	_price = int(round(lerpf(float(_price), _limit, f)))
	_price = maxi(_price, ceili(_limit)) if _buy else mini(_price, floori(_limit))
	_price = maxi(1, _price)

## Las señales que se ven después de que el otro pone (o mueve) su precio.
func _after_move_tells(opening: bool) -> void:
	var near := absf(float(_price) - _limit) <= 0.06 * _base
	var cap := ""
	match _sp:
		"hornback":
			if near and not opening:
				_portrait.fx("snort", 1.2)
				cap = String(BenchData.HAGGLE_LINES["hornback"]["tell"])
				Sfx.play_pitched("blip", 0.5, -8.0)
		"quill":
			if not opening:
				var bluff := not _final and absf(float(_price) - _limit) > 0.04 * _base
				_portrait.set_crest("bluff" if bluff else "steady")
				cap = String(BenchData.HAGGLE_LINES["quill"]["tell" if bluff else "steady"])
		"duneraker":
			if float(_price) <= _base * 1.05:
				_portrait.fx("tongue", 1.0)
				cap = String(BenchData.HAGGLE_LINES["duneraker"]["tell"])
		"bot":
			if not opening:
				_portrait.fx("calc", 1.0)
	if cap != "":
		_bubble.say(_bubble.text(), cap)
		_bubble.point_at(BOOTH.position + _portrait.top_point() + Vector2(0, -6))

## Glimmerfolk: cómo le cae un precio (cálido = lo acepta; tibio = cerca; frío = lejos).
func _glow_for(c: int) -> String:
	if _acceptable(c):
		return "warm"
	if (not _buy and float(c) <= _limit * 1.1) or (_buy and float(c) >= _limit * 0.9):
		return "mild"
	return "cool"

func _on_counter_hover(k: int, on: bool) -> void:
	if _sp != "glimmerfolk" or _done or _barter != "":
		return
	if on and _opts[k] > 0:
		_hover_k = k
		_portrait.set_glow(_glow_for(_opts[k]))
	elif not on and _hover_k == k:
		_hover_k = -1
		_portrait.set_glow(_glow_for(_last) if _last > 0 else "")

func _accept() -> void:
	if not visible or _done or _busy or _barter != "":
		return
	var p := _price
	if _r.get("rule", "") == "insulted_by_quick_yes" and _round == 0:
		# un sí rápido lo ofende: el precio empeora para Nell
		p = int(round(float(p) * (1.15 if _buy else 0.85)))
		_mood = clampf(_mood - 0.3, 0.0, 1.0)
		_portrait.fx("snort", 1.2)
		_close(p, BenchData.haggle_line(_sp, "insulted", [p]))
		return
	_close(p, BenchData.haggle_line(_sp, "accept"))

func _close(p: int, line: String) -> void:
	_done = true
	var tip := 0
	if _r.get("rule", "") == "tips_for_speed" and not _buy and _round <= 1:
		tip = maxi(1, int(round(float(p) * 0.1)))
		line += " " + BenchData.haggle_line(_sp, "tip")
	var cap := ""
	if _r.get("rule", "") == "small_coins":
		cap = String(BenchData.HAGGLE_LINES["burrower"]["coins"])
	_say(line, cap)
	_price = p
	_refresh()
	_price_head.text = "DEAL"
	_price_big.text = "%d cr" % (p + tip)
	_price_big.add_theme_color_override("font_color", Color(0.7, 1.0, 0.55))
	_price_sub.text = ("+%d tip" % tip) if tip > 0 else ""
	Sfx.play_pitched("coins", 1.25 if _sp == "burrower" else 1.0, -2.0)
	_finish({"deal": true, "price": p + tip, "mood": snappedf(_mood, 0.01), "tip": tip, "rounds": _round}, 1.3)

func _walk_away() -> void:
	if not visible or _done:
		return
	_leave("Maybe next time.", true)

func _leave(line: String, nell := false) -> void:
	_done = true
	if nell:
		_say(BenchData.haggle_line(_sp, "walk") if _sp == "duneraker" else "Hm. Suit yourself.", "")
	else:
		_say(line, "")
	_refresh()
	_price_head.text = "NO DEAL"
	_price_big.add_theme_color_override("font_color", BenchKit.RED)
	Sfx.play("bad", 0.05, -6.0)
	_finish({"deal": false, "price": _price, "mood": snappedf(_mood, 0.01), "tip": 0, "rounds": _round}, 1.1)

func _take_barter() -> void:
	if not visible or _done or _busy or _barter == "":
		return
	_done = true
	_portrait.set_glow("warm")
	_say(BenchData.haggle_line(_sp, "accept"), "")
	_price_head.text = "TRADE"
	_price_big.text = "%d x %s" % [_barter_n, BenchData.part_name(_barter)]
	_price_big.add_theme_color_override("font_color", Color(0.7, 1.0, 0.55))
	BenchKit.enable(_barter_take, false)
	BenchKit.enable(_barter_no, false)
	BenchKit.enable(_walk_btn, false)
	Sfx.play("ratchet", 0.05, -4.0)
	_finish({"deal": true, "price": 0, "mood": snappedf(_mood, 0.01), "tip": 0, "rounds": _round,
		"barter": _barter, "barter_n": _barter_n}, 1.3)

func _decline_barter() -> void:
	if not visible or _done or _busy or _barter == "":
		return
	_barter = ""
	_portrait.set_glow("")
	_say(BenchData.haggle_line(_sp, "open_sell", [_price]), "")
	_lock(0.3)
	_refresh()

## Glimmerfolk: piezas que le faltan a Nell (las que menos hay), por un valor parecido al de la cosa.
func _pick_barter() -> void:
	var least := 999
	var pool: Array = []
	for p in BenchData.PART_ORDER:
		var n := Game.part_count(p)
		if n < least:
			least = n
			pool = [p]
		elif n == least:
			pool.append(p)
	_barter = String(pool[_rng.randi() % pool.size()])
	var val := float(BenchData.part_price(_barter))
	_barter_n = clampi(int(round(_base * 0.75 / val)), 1, 3)

func _finish(r: Dictionary, delay: float) -> void:
	_busy = true
	var g := _gen
	await get_tree().create_timer(delay).timeout
	if g != _gen:
		return
	_gen += 1
	visible = false
	_busy = false
	_price_big.remove_theme_color_override("font_color")
	finished.emit(r)

func _lock(secs: float) -> void:
	_busy = true
	var g := _gen
	await get_tree().create_timer(secs).timeout
	if g == _gen:
		_busy = false

func _process(delta: float) -> void:
	if not visible:
		return
	if _clock > 0.0 and not _done:
		_clock -= delta
		if _clock <= 10.0 and not _hurried:
			# el despegue se acerca: mira la hora y paga un poco más
			_hurried = true
			_limit *= 1.08
			_move_price(0.35)
			_portrait.fx("watch", 2.0)
			_say(BenchData.haggle_line(_sp, "hurry") + " " + str(_price) + ".", String(BenchData.HAGGLE_LINES["human"]["tell"]))
			_refresh()
		if _clock <= 0.0:
			_clock = 0.0
			_leave(BenchData.haggle_line(_sp, "walk"))
	if _depart.visible:
		var s := int(ceilf(maxf(_clock, 0.0)))
		_depart_lbl.text = "LAUNCH %d:%02d" % [s / 60, s % 60]
		_depart_lbl.add_theme_color_override("font_color", BenchKit.RED if (_clock < 10.0 and fmod(_clock, 0.6) < 0.3) else BenchKit.AMBER)
	if PadCursor.pad_in_use != _last_pad:
		_refresh_hints()

func _input(ev: InputEvent) -> void:
	if not visible or _done or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	var lk: int = ev.keycode if ev.keycode != KEY_NONE else k
	var go := k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or lk == KEY_E
	if _barter != "":
		if k == KEY_1 or go:
			_take_barter()
		elif k == KEY_2:
			_decline_barter()
		elif k == KEY_ESCAPE:
			_walk_away()
		else:
			return
	else:
		if k >= KEY_1 and k <= KEY_3:
			_counter(k - KEY_1)
		elif go:
			_accept()
		elif k == KEY_ESCAPE:
			_walk_away()
		else:
			return
	get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ bot y capturas

func _bot_run(skill: float, stop_at: String) -> void:
	var g := _gen
	await get_tree().create_timer(0.35).timeout
	if g != _gen or _done:
		return
	if stop_at == "open":
		return
	if _barter != "":
		_decline_barter()
		await get_tree().create_timer(0.4).timeout
		if g != _gen:
			return
	if stop_at == "hover":
		_on_counter_hover(1, true)
		return
	if skill < 0.999 and _rng.randf() > skill:
		_accept()
		return
	# una contraoferta "fair" (en la captura, la más lejos de su precio, para que se vea el rechazo y la señal)
	var k := (0 if _buy else 2) if stop_at == "counter" else 1
	if _opts[k] <= 0:
		k = 2 if _opts[2] > 0 else -1
	if k >= 0:
		_counter(k)
	if stop_at == "counter" or _done:
		return
	await get_tree().create_timer(0.5).timeout
	if g != _gen or _done:
		return
	# el Quill blufea (cresta que parpadea): otra vez; si no, aceptar lo que hay
	if _sp == "quill" and not _final and _opts[2] > 0:
		_counter(2)
		await get_tree().create_timer(0.5).timeout
		if g != _gen or _done:
			return
	_accept()
