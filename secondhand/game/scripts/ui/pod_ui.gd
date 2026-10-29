extends Control
class_name PodUI
## Abrir una cápsula de chatarra (salvage pod): se ve cerrada sobre su pie, con el peso y el traqueteo en etiquetas
## de papel; "Crack it open" la hace temblar y estallar, y lo de adentro (2-3 piezas y a veces una cosa rota para
## reparar y vender) sale volando a su lugar en el cajón. "Take all" se lo lleva.
## --- SS BENCH: reemplaza el placeholder de la semilla con el MISMO contrato (SS_BRIEF §3):
##   open(pod)  pod = {"id", "weight": 1-3, "rattle": 0-2, "price", "contents": [...]} (BenchData.roll_pod());
##              si pod no trae "contents", se sortean al abrir
##   signal finished(contents)  contents = [{"part": "cell"}, {"item": "radio", "fault": "tuner"}, ...]
##   close_now(), is_open(), bot_play() (asíncrono: abre, salta la animación y se lleva todo)
## PodUI NO toca Game: quien lo abre guarda las piezas (Game.add_part) y las cosas rotas (Game.add_junk).
## Controles: clic en el botón o en la cápsula; Intro / Espacio / E (la acción del botón; durante la animación la
## salta); mando: A sobre el botón o la cápsula, X = Espacio.

signal finished(contents: Array)

const PLATE := Rect2(240, 40, 800, 640)
const HEADER := Rect2(264, 54, 752, 46)
const POD_CENTER := Vector2(640, 238)
const TRAY := Rect2(264, 420, 752, 182)
const CARD := Vector2(176, 182)

var pod := {}
var _cracked := false
var _gen := 0
var _canvas: Control
var _view: BenchPodView
var _id_lbl: Label
var _weight_lbl: Label
var _rattle_lbl: Label
var _status: Label
var _btn: Button
var _cards: Array = []
var _hints_box: Control
var _pod_btn: Button
var _last_pad := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (después de entrar al árbol: anclas Y márgenes)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	visible = false
	_build()

func open(p: Dictionary) -> void:
	_gen += 1
	pod = p.duplicate(true)
	if not pod.has("contents") or not (pod["contents"] is Array):
		pod["contents"] = BenchData.roll_pod()["contents"]
	_cracked = false
	_id_lbl.text = String(pod.get("id", "")).to_upper()
	_weight_lbl.text = "Weight: %s" % BenchData.POD_WEIGHT[clampi(int(pod.get("weight", 1)) - 1, 0, 2)]
	_rattle_lbl.text = "Rattle: %s" % BenchData.POD_RATTLE[clampi(int(pod.get("rattle", 0)), 0, 2)]
	_status.text = "Sealed since last night's starfall. What's inside?"
	BenchKit.set_text(_btn, "Crack it open")
	BenchKit.enable(_btn, true)
	_layout_cards()
	visible = true
	UIKit.pop_in(_canvas)
	_refresh_hints()

func is_open() -> bool:
	return visible

func close_now() -> void:
	_gen += 1
	visible = false

## El bot de autoplay: abre, salta la animación y se lleva todo.
func bot_play() -> void:
	if not visible:
		return
	var g := _gen
	await get_tree().create_timer(0.2).timeout
	if g != _gen:
		return
	_crack()
	await get_tree().create_timer(0.3).timeout
	if g != _gen:
		return
	_view.skip()
	await get_tree().create_timer(0.3).timeout
	if g == _gen:
		_take()

## Capturas: "closed", "crack" (a mitad de la animación), "open" (todo afuera).
func demo_to(step: String) -> void:
	if not visible or step == "closed":
		return
	var g := _gen
	await get_tree().create_timer(0.3).timeout
	if g != _gen:
		return
	_crack()

# ------------------------------------------------------------------ armado

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
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	BenchKit.at(h, HEADER)
	_canvas.add_child(h)
	var ic := UIKit.ui_icon("pod", 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := BenchKit.shadow(UIKit.label("SALVAGE POD", 26, UIKit.ACCENT, UIKit.font_bold))
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	_id_lbl = UIKit.label("", 18, UIKit.MUTED, UIKit.font_mono)
	_id_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_id_lbl)
	# el escenario de la cápsula (hundido)
	var stage := Panel.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", BenchKit.inset_style(Color(0.08, 0.075, 0.07, 0.95), 8))
	BenchKit.at(stage, Rect2(HEADER.position.x, 108, HEADER.size.x, 300))
	_canvas.add_child(stage)
	# la cápsula se puede tocar (un botón invisible encima)
	_pod_btn = Button.new()
	_pod_btn.flat = true
	_pod_btn.focus_mode = Control.FOCUS_NONE
	_pod_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		_pod_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	BenchKit.at(_pod_btn, Rect2(POD_CENTER - Vector2(110, 120), Vector2(220, 240)))
	_pod_btn.pressed.connect(_on_main)
	_canvas.add_child(_pod_btn)
	# las pistas (etiquetas de papel a los lados)
	var wt := BenchKit.tag(10)
	wt.position = Vector2(HEADER.position.x + 26, 150)
	_weight_lbl = UIKit.label("", 28, BenchKit.INK, UIKit.font_hand)
	wt.add_child(_weight_lbl)
	_canvas.add_child(wt)
	var rt := BenchKit.tag(10)
	rt.position = Vector2(HEADER.end.x - 236, 150)
	_rattle_lbl = UIKit.label("", 28, BenchKit.INK, UIKit.font_hand)
	rt.add_child(_rattle_lbl)
	_canvas.add_child(rt)
	# la bandeja del cajón (las tarjetas)
	var tray := Panel.new()
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_theme_stylebox_override("panel", BenchKit.inset_style(Color(0.1, 0.085, 0.07, 0.9), 6))
	BenchKit.at(tray, TRAY)
	_canvas.add_child(tray)
	for i in 4:
		var c := _make_card()
		_canvas.add_child(c)
		_cards.append(c)
	_status = BenchKit.shadow(UIKit.label("", 20, BenchKit.CREAM, UIKit.font_regular, HORIZONTAL_ALIGNMENT_CENTER))
	BenchKit.at(_status, Rect2(TRAY.position.x, TRAY.position.y + 70, TRAY.size.x, 30))
	_canvas.add_child(_status)
	_btn = BenchKit.key_button("Crack it open", "E", func(): _on_main(), Vector2(300, 60), "wrench", true, 22)
	_btn.position = Vector2(PLATE.end.x - 324, PLATE.end.y - 76)
	_canvas.add_child(_btn)
	_hints_box = BenchKit.group(Rect2(PLATE.position.x + 24, PLATE.end.y - 72, 420, 52))
	_canvas.add_child(_hints_box)
	# la animación va arriba de todo
	_view = BenchPodView.new()
	BenchKit.at(_view, Rect2(0, 0, 1280, 720))
	_canvas.add_child(_view)
	_view.landed.connect(_on_landed)
	_view.all_landed.connect(_on_all_landed)

func _make_card() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = CARD
	p.visible = false
	var icon := BenchKit.pixel_rect(null, 3.0)
	icon.name = "Icon"
	icon.position = Vector2(24, 8)
	icon.size = Vector2(128, 112)
	p.add_child(icon)
	var name_l := UIKit.label("", 18, BenchKit.CREAM, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.name = "Name"
	name_l.position = Vector2(4, 120)
	name_l.size = Vector2(CARD.x - 8, 24)
	p.add_child(name_l)
	var sub := UIKit.label("", 16, UIKit.MUTED, UIKit.font_regular, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "Sub"
	sub.position = Vector2(4, 146)
	sub.size = Vector2(CARD.x - 8, 24)
	p.add_child(sub)
	return p

func _layout_cards() -> void:
	var cs: Array = pod.get("contents", [])
	var n := mini(cs.size(), _cards.size())
	var total := n * CARD.x + maxi(0, n - 1) * 14.0
	var x0 := TRAY.position.x + (TRAY.size.x - total) / 2.0
	var targets: Array = []
	var icons: Array = []
	var pending := {}
	for i in _cards.size():
		var card: Panel = _cards[i]
		card.visible = false
		if i >= n:
			continue
		var c: Dictionary = cs[i]
		card.position = Vector2(x0 + i * (CARD.x + 14.0), TRAY.position.y)
		var icon: TextureRect = card.find_child("Icon", false, false)
		var nm: Label = card.find_child("Name", false, false)
		var sub: Label = card.find_child("Sub", false, false)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		var tex: Texture2D = null
		var sc := 3.0
		if c.has("part"):
			var part := String(c["part"])
			tex = BenchKit.tex("res://assets/parts/%s.png" % part)
			nm.text = BenchData.part_name(part)
			pending[part] = int(pending.get(part, 0)) + 1
			sub.text = "+1  ·  in drawer: %d" % (Game.part_count(part) + int(pending[part]))
			sub.add_theme_color_override("font_color", Color(0.72, 0.9, 0.62))
			sb.bg_color = Color(0.13, 0.15, 0.12, 0.95)
			sb.border_color = Color(0.45, 0.6, 0.4)
		else:
			var it := String(c.get("item", ""))
			tex = BenchKit.tex("res://assets/items/%s_closed.png" % it)
			sc = 2.0
			nm.text = BenchData.item_name(it)
			sub.text = "Broken: fix it, sell it"
			sub.add_theme_color_override("font_color", Color(1.0, 0.68, 0.5))
			sb.bg_color = Color(0.2, 0.13, 0.1, 0.95)
			sb.border_color = Color(0.85, 0.5, 0.3)
		card.add_theme_stylebox_override("panel", sb)
		icon.texture = tex
		if tex:
			var s := Vector2(tex.get_width(), tex.get_height()) * sc
			icon.size = s
			icon.position = Vector2((CARD.x - s.x) / 2.0, 6 + (112 - s.y) / 2.0)
		targets.append(card.position + Vector2(CARD.x / 2.0, 62))
		icons.append([tex, sc])
	_view.reset(POD_CENTER, targets, icons)

# ------------------------------------------------------------------ acciones

func _on_main() -> void:
	if not visible:
		return
	if not _cracked:
		_crack()
	elif _view.state != "done":
		_view.skip()
	else:
		_take()

func _crack() -> void:
	if not visible or _cracked:
		return
	_cracked = true
	_view.crack()
	BenchKit.enable(_btn, true)
	BenchKit.set_text(_btn, "Skip")
	_status.text = ""
	_refresh_hints()

func _on_landed(i: int) -> void:
	if i < 0 or i >= _cards.size():
		return
	var c: Panel = _cards[i]
	c.visible = true
	c.pivot_offset = CARD / 2.0
	c.scale = Vector2(0.8, 0.8)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_all_landed() -> void:
	var cs: Array = pod.get("contents", [])
	var parts := 0
	var items := 0
	for c in cs:
		if c.has("part"):
			parts += 1
		elif c.has("item"):
			items += 1
	var msg := UIKit.plural(parts, "part")
	if items > 0:
		msg += " and something to fix!"
	else:
		msg += "."
	_status.text = ""
	BenchKit.set_text(_btn, "Take all")
	_refresh_hints()
	var hdr: Label = _id_lbl
	hdr.text = "%s  ·  %s" % [String(pod.get("id", "")).to_upper(), msg]
	if items > 0:
		Sfx.play("good", 0.02, -6.0)

func _take() -> void:
	if not visible or not _cracked or _view.state != "done":
		return
	var out: Array = pod.get("contents", []).duplicate(true)
	_gen += 1
	visible = false
	Sfx.play("coins", 0.05, -6.0)
	finished.emit(out)

func _refresh_hints() -> void:
	for c in _hints_box.get_children():
		c.queue_free()
	var verb := "open" if not _cracked else ("skip" if _view.state != "done" else "take all")
	var row := BenchKit.hints([{"keys": ["E", "/", "Space"], "text": verb}, {"pad": ["A", "/", "X"], "text": verb}], 17)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hints_box.add_child(row)
	BenchKit.refresh_keys(_canvas)
	_last_pad = PadCursor.pad_in_use

func _process(_d: float) -> void:
	if visible and PadCursor.pad_in_use != _last_pad:
		_refresh_hints()

func _input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	var lk: int = ev.keycode if ev.keycode != KEY_NONE else k
	if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or lk == KEY_E:
		_on_main()
	elif k == KEY_ESCAPE and _cracked and _view.state == "done":
		_take()
	else:
		return
	get_viewport().set_input_as_handled()
