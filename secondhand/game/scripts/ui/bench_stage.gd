extends Control
class_name BenchStage
## La cosa abierta sobre la alfombra del banco: la vista de 360x240 de ART (assets/items/<item>_open_empty.png) a x2
## = 720x480 y encima las 4 piezas en sus zócalos (assets/items/manifest.json: pos/size en la vista; la pieza de 32x32
## va a x2 en la vista, o sea x4 en pantalla), cada una dibujada aparte para que pueda traquetear, brillar, salir o
## entrar volando. Los efectos de las herramientas: ondas de sonido (LISTEN), traqueteo (TAP), brillo de calor y la
## línea del escáner (SCAN). Después: la pieza mala que sale (se ve su _bad: el daño recién ahora), la nueva que entra,
## el parche (cinta), y al probarla, que funcione (notas, el bot habla, la llama del propulsor).
## Los zócalos son botones planos (ratón y cursor del mando): slot_pressed / slot_hovered.
## --- SS BENCH (nuevo).

signal slot_pressed(i: int)
signal slot_hovered(i: int)          # -1 = ninguno

const VIEW := Vector2(360, 240)
const K := 2.0                         # la vista a x2 en pantalla

var item := ""
var slots: Array = []                  # [{"part", "pos": Vector2, "size": Vector2}] (en la vista)
var fault_i := -1
var hover_i := -1
var pick_enabled := false              # los zócalos se pueden tocar (solo en DIAGNOSE)
var show_numbers := true               # el número de cada zócalo (teclas 1-4)
var dim := 0.0                         # oscurece la vista (cuando encima van la soldadura o el test)
var origin := Vector2.ZERO             # dónde empieza la vista dentro del control

var _empty_tex: Texture2D
var _part_tex := {}                    # part -> [normal, bad]
var _state: Array = []                 # in | wrong | found | out | empty | new | patched
var _state_t: Array = []
var _shake: Array = []
var _ripple: Array = []
var _heat: Array = []                  # -1..1
var _heat_a := 0.0                     # cuánto se ve el brillo del escáner (se apaga solo)
var _scan_t := -1.0                    # la línea del escáner (0..1 mientras baja)
var _tap_t := -1.0                     # el martillito de TAP
var _power := ""                       # notes | talk | flame
var _power_t := 0.0
var _t := 0.0
var _btns: Array = []
var _bubble: BenchBubble
var _manifest := {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true      # ondas, llama, piezas que vuelan: todo queda dentro de la alfombra
	_load_manifest()
	for i in 4:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var idx := i
		b.pressed.connect(func(): if pick_enabled: slot_pressed.emit(idx))
		b.mouse_entered.connect(func(): _hover(idx, true))
		b.mouse_exited.connect(func(): _hover(idx, false))
		b.visible = false
		add_child(b)
		_btns.append(b)
	_bubble = BenchBubble.new()
	_bubble.max_width = 250.0
	_bubble.tail_x = 0.2
	add_child(_bubble)
	# todas las texturas de una vez (abrir el banco no carga nada)
	for it in BenchData.ITEM_ORDER:
		BenchKit.tex("res://assets/items/%s_open_empty.png" % it)
		BenchKit.tex("res://assets/items/%s_open.png" % it)
	for p in BenchData.PART_ORDER:
		_part_tex[p] = [BenchKit.tex("res://assets/parts/%s.png" % p), BenchKit.tex("res://assets/parts/%s_bad.png" % p)]

func _load_manifest() -> void:
	var path := "res://assets/items/manifest.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			_manifest = d

## Prepara la vista para un trabajo (sin animaciones pendientes).
func setup(item_id: String, fault_index: int) -> void:
	item = item_id
	fault_i = fault_index
	origin = ((size - VIEW * K) / 2.0).floor()
	_empty_tex = BenchKit.tex("res://assets/items/%s_open_empty.png" % item)
	slots = []
	var parts: Array = BenchData.ITEMS.get(item, {}).get("slots", [])
	var man: Array = _manifest.get(item, {}).get("slots", [])
	for i in parts.size():
		var pos := Vector2(28 + (i % 2) * 180, 30 + (i / 2) * 110)   # sin manifest: una grilla de 2x2
		var sz := Vector2(64, 64)
		for m in man:
			if String(m.get("part", "")) == parts[i] and String(m.get("slot", "")) == "s%d" % (i + 1):
				pos = Vector2(m["pos"][0], m["pos"][1])
				sz = Vector2(m["size"][0], m["size"][1])
		slots.append({"part": parts[i], "pos": pos, "size": sz})
	_state = []
	_state_t = []
	_shake = []
	_ripple = []
	_heat = []
	for i in slots.size():
		_state.append("in")
		_state_t.append(0.0)
		_shake.append(0.0)
		_ripple.append(0.0)
		_heat.append(0.0)
	_heat_a = 0.0
	_scan_t = -1.0
	_tap_t = -1.0
	_power = ""
	dim = 0.0
	hover_i = -1
	_bubble.hide_now()
	for i in _btns.size():
		var b: Button = _btns[i]
		b.visible = i < slots.size()
		if i < slots.size():
			var r := slot_rect(i)
			b.position = r.position
			b.size = r.size
	queue_redraw()

## El rectángulo de un zócalo en pantalla (coordenadas de este control).
func slot_rect(i: int) -> Rect2:
	if i < 0 or i >= slots.size():
		return Rect2()
	var s: Dictionary = slots[i]
	return Rect2(origin + s["pos"] * K, s["size"] * K)

func slot_center(i: int) -> Vector2:
	return slot_rect(i).get_center()

func set_pick_enabled(on: bool) -> void:
	pick_enabled = on
	for i in _btns.size():
		var b: Button = _btns[i]
		b.disabled = not on or i >= slots.size() or _state[i] == "wrong"
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	if not on:
		hover_i = -1

func _hover(i: int, on: bool) -> void:
	if i >= _state.size():
		return
	if on and pick_enabled and _state[i] != "wrong":
		hover_i = i
		slot_hovered.emit(i)
	elif not on and hover_i == i:
		hover_i = -1
		slot_hovered.emit(-1)

func state(i: int) -> String:
	return String(_state[i]) if i >= 0 and i < _state.size() else ""

func set_state(i: int, s: String) -> void:
	if i < 0 or i >= _state.size():
		return
	_state[i] = s
	_state_t[i] = 0.0
	if s == "wrong" and i < _btns.size():
		_btns[i].disabled = true
		if hover_i == i:
			hover_i = -1

# ------------------------------------------------------------------ herramientas

## Muestra la pista de una herramienta (BenchData.clue()).
func show_clue(c: Dictionary) -> void:
	var st: Array = c.get("strength", [])
	match String(c.get("tool", "")):
		"listen":
			for i in _ripple.size():
				_ripple[i] = float(st[i]) if i < st.size() else 0.0
		"tap":
			_tap_t = 0.0
			var amp := 7.0 if bool(c.get("clear", false)) else 3.5
			for i in _shake.size():
				_shake[i] = amp if (i < st.size() and float(st[i]) > 0.01) else 0.0
		"scan":
			_scan_t = 0.0
			var h: Array = c.get("heat", [])
			for i in _heat.size():
				_heat[i] = float(h[i]) if i < h.size() else 0.0
			_heat_a = 0.0
	queue_redraw()

func clear_clues() -> void:
	for i in _ripple.size():
		_ripple[i] = 0.0
		_shake[i] = 0.0
	_heat_a = 0.0
	_scan_t = -1.0

## El bot de bolsillo habla (un globo junto a su cabeza: el zócalo de la lente).
func bot_say(text: String, dur := 2.2) -> void:
	var li := -1
	for i in slots.size():
		if slots[i]["part"] == "lens":
			li = i
	var r := slot_rect(li) if li >= 0 else Rect2(origin + Vector2(300, 40), Vector2(10, 10))
	_bubble.say(text, "", dur)
	_bubble.point_at(r.end + Vector2(60, -r.size.y + 48) if li >= 0 else r.position)   # a la derecha de la cabeza

func hide_bubble() -> void:
	_bubble.hide_now()

## Al probarla bien: notes (radio), talk (bot: lo dice bot_say aparte), flame (propulsor).
func power(kind: String) -> void:
	_power = kind
	_power_t = 0.0

# ------------------------------------------------------------------ dibujo

func _process(delta: float) -> void:
	_t += delta
	for i in _state_t.size():
		_state_t[i] += delta
		_shake[i] = maxf(0.0, _shake[i] - delta * 3.2)
		_ripple[i] = maxf(0.0, _ripple[i] - delta * 0.12)
	if _scan_t >= 0.0:
		_scan_t += delta / 0.55
		if _scan_t >= 1.0:
			_scan_t = -1.0
			_heat_a = 1.0
	elif _heat_a > 0.0:
		_heat_a = maxf(0.0, _heat_a - delta * 0.08)
	if _tap_t >= 0.0:
		_tap_t += delta
		if _tap_t > 0.6:
			_tap_t = -1.0
	if _power != "":
		_power_t += delta
	queue_redraw()

func _px(v: Vector2) -> Vector2:
	return (v / K).floor() * K

func _draw() -> void:
	var vr := Rect2(origin, VIEW * K)
	# la alfombra de trabajo (cuadriculada) bajo la cosa
	draw_style_box(BenchKit.inset_style(Color(0.075, 0.09, 0.085, 0.97), 8), Rect2(Vector2.ZERO, size))
	var gc := Color(0.55, 0.8, 0.7, 0.05)
	var gx := 8.0
	while gx < size.x - 4.0:
		draw_rect(Rect2(gx, 6, 2, size.y - 12), gc)
		gx += 32.0
	var gy := 8.0
	while gy < size.y - 4.0:
		draw_rect(Rect2(6, gy, size.x - 12, 2), gc)
		gy += 32.0
	# sombra suave debajo
	draw_rect(Rect2(vr.position + Vector2(10, vr.size.y - 14), Vector2(vr.size.x - 20, 10)), Color(0, 0, 0, 0.18))
	if _empty_tex:
		draw_texture_rect(_empty_tex, vr, false)
	else:
		draw_rect(vr.grow(-8), Color(0.18, 0.3, 0.28))
		draw_rect(vr.grow(-8), Color(0.05, 0.08, 0.07), false, 4.0)
	# el brillo de calor va debajo de las piezas (se ve alrededor)
	if _heat_a > 0.0:
		for i in slots.size():
			_draw_heat(i)
	for i in slots.size():
		_draw_slot(i)
	for i in slots.size():
		if _ripple[i] > 0.01:
			_draw_ripples(i)
	if _scan_t >= 0.0:
		var y := vr.position.y + vr.size.y * _scan_t
		draw_rect(Rect2(vr.position.x, y - 2, vr.size.x, 4), Color(1.0, 0.72, 0.3, 0.85))
		draw_rect(Rect2(vr.position.x, y - 22, vr.size.x, 20), Color(1.0, 0.6, 0.2, 0.12))
	if _tap_t >= 0.0:
		_draw_tap()
	if _power != "":
		_draw_power()
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.03, 0.62 * dim))

func _draw_slot(i: int) -> void:
	var r := slot_rect(i)
	var part: String = slots[i]["part"]
	var texs: Array = _part_tex.get(part, [null, null])
	var st := String(_state[i])
	var t: float = _state_t[i]
	var off := Vector2.ZERO
	if _shake[i] > 0.0:
		off = _px(Vector2(sin(_t * 61.0 + i * 1.7), cos(_t * 47.0 + i)) * _shake[i] * Vector2(1.0, 0.6))
	var tex: Texture2D = texs[0]
	match st:
		"empty":
			return
		"out":
			# sale de su zócalo, sube y se queda flotando ahí (se ve rota: el daño recién ahora) hasta elegir
			# cambiarla (se va al tacho mientras entra la nueva) o parcharla (vuelve a su lugar con cinta)
			tex = texs[1] if texs[1] else texs[0]
			draw_rect(r.grow(-6), Color(0.02, 0.02, 0.02, 0.55))      # el zócalo vacío
			_tex_at(tex, Rect2(_lifted(r, t), r.size))
			if t > 0.25:
				_tag(Vector2(r.position.x + r.size.x * 0.5, maxf(6.0, r.position.y - 66.0)), "BROKEN", BenchKit.RED)
			return
		"new":
			# la rota cae al tacho (abajo a la izquierda) y la nueva entra volando desde el cajón, con un arco
			var kb := minf(t / 0.45, 1.0)
			if kb < 1.0 and texs[1]:
				var bp := _lifted(r, 1.0).lerp(Vector2(-20, size.y - 40), kb * kb)
				_tex_at(texs[1], Rect2(_px(bp), r.size), Color(1, 1, 1, 1.0 - kb))
			var k := minf(t / 0.42, 1.0)
			var from := Vector2(size.x + 20, r.position.y - 30)
			var p := from.lerp(r.position, 1.0 - pow(1.0 - k, 2.0)) + Vector2(0, -60.0 * sin(k * PI))
			_tex_at(texs[0], Rect2(_px(p), r.size))
			if k >= 1.0 and t < 1.0:
				_sparkle(r.get_center(), t - 0.42)
			return
		"patched":
			# la rota vuelve a su zócalo y le ponen cinta
			tex = texs[1] if texs[1] else texs[0]
			var back := minf(t / 0.2, 1.0)
			_tex_at(tex, Rect2(_px(_lifted(r, 1.0).lerp(r.position, back)), r.size))
			if t > 0.2:
				_draw_tape(r, minf((t - 0.2) / 0.3, 1.0))
			return
	_tex_at(tex, Rect2(r.position + off, r.size))
	# marcas encima
	if st == "wrong":
		var a := 1.0 if t < 0.5 else 0.55
		draw_rect(r, Color(0.6, 0.1, 0.08, 0.28 * a))
		var c := Color(BenchKit.RED.r, BenchKit.RED.g, BenchKit.RED.b, a)
		var m := r.grow(-30)
		draw_line(m.position, m.end, Color(0.1, 0.02, 0.02, a * 0.8), 14.0)
		draw_line(Vector2(m.end.x, m.position.y), Vector2(m.position.x, m.end.y), Color(0.1, 0.02, 0.02, a * 0.8), 14.0)
		draw_line(m.position, m.end, c, 8.0)
		draw_line(Vector2(m.end.x, m.position.y), Vector2(m.position.x, m.end.y), c, 8.0)
	elif st == "found":
		var pulse := 0.6 + 0.4 * sin(t * 12.0)
		draw_rect(r.grow(4), Color(BenchKit.GREEN.r, BenchKit.GREEN.g, BenchKit.GREEN.b, pulse), false, 6.0)
	if pick_enabled and st == "in":
		if i == hover_i:
			var pulse2 := 0.75 + 0.25 * sin(_t * 8.0)
			draw_rect(r.grow(6), Color(0.05, 0.03, 0.02, 0.6), false, 8.0)
			draw_rect(r.grow(4), Color(1.0, 0.75, 0.32, pulse2), false, 4.0)
		if show_numbers:
			_badge(r.position + Vector2(-10, -10), str(i + 1), i == hover_i)
	elif pick_enabled and st == "wrong" and show_numbers:
		_badge(r.position + Vector2(-10, -10), str(i + 1), false, true)

## Dónde flota la pieza rota en el paso CAMBIAR (sube 40 px y se mece un poco).
func _lifted(r: Rect2, t: float) -> Vector2:
	var up := minf(t / 0.3, 1.0)
	var bob := sin(_t * 3.0) * 3.0 if t > 0.3 else 0.0
	return _px(r.position + Vector2(0, -40.0 * (1.0 - pow(1.0 - up, 3.0)) + bob))

func _tex_at(tex: Texture2D, r: Rect2, mod := Color.WHITE) -> void:
	if tex:
		draw_texture_rect(tex, r, false, mod)
	else:
		draw_rect(r.grow(-10), Color(0.5, 0.5, 0.5, mod.a))

## El número del zócalo (tecla 1-4) en una placa chiquita.
func _badge(p: Vector2, txt: String, hot: bool, dead := false) -> void:
	var r := Rect2(p, Vector2(30, 30))
	draw_rect(r.grow(2), Color(0.05, 0.03, 0.02, 0.85))
	var bg := Color(1.0, 0.72, 0.3) if hot else (Color(0.4, 0.36, 0.33) if dead else Color(0.93, 0.89, 0.78))
	draw_rect(r, bg)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), Color(0, 0, 0, 0.25))
	var f: Font = UIKit.font_bold
	var fs := 20
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		BenchKit.INK if not dead else Color(0.2, 0.18, 0.17))

func _tag(center_top: Vector2, txt: String, col: Color) -> void:
	var f: Font = UIKit.font_bold
	var fs := 16
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
	var r := Rect2(_px(center_top - Vector2(w / 2.0, 0)), Vector2(roundf(w), 24))
	draw_rect(r.grow(2), Color(0.05, 0.03, 0.02, 0.9))
	draw_rect(r, col)
	draw_string(f, r.position + Vector2(8, 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.03, 0.02))

func _draw_heat(i: int) -> void:
	var h: float = _heat[i]
	if absf(h) < 0.05:
		return
	var a := _heat_a * clampf(absf(h), 0.0, 1.0)
	var col := BenchKit.COLD if h < 0.0 else Color(1.0, 0.45, 0.12)
	if h > 0.0 and h < 0.9:
		col = Color(1.0, 0.66, 0.25)
	var c := slot_center(i)
	var flick := 0.85 + 0.15 * sin(_t * 9.0 + i)
	for k in 5:
		var s := 70.0 + k * 16.0
		var rr := Rect2(_px(c - Vector2(s, s)), Vector2(s, s) * 2.0)
		draw_rect(rr, Color(col.r, col.g, col.b, a * flick * (0.2 - k * 0.035)))
	# encima de la pieza también, para que se lea el color
	var r := slot_rect(i)
	draw_rect(r, Color(col.r, col.g, col.b, a * 0.35))
	draw_rect(r.grow(2), Color(col.r, col.g, col.b, a * 0.9), false, 4.0)

func _draw_ripples(i: int) -> void:
	var c := slot_center(i)
	var s: float = _ripple[i]
	for k in 3:
		var ph := fmod(_t * 0.9 + k / 3.0, 1.0)
		var rad := 50.0 + ph * 90.0
		var a := s * (1.0 - ph) * 0.9
		draw_arc(c, rad, -PI * 0.9, -PI * 0.1, 18, Color(0.1, 0.06, 0.02, a * 0.5), 9.0)
		draw_arc(c, rad, -PI * 0.9, -PI * 0.1, 18, Color(1.0, 0.86, 0.5, minf(1.0, a * 1.2)), 5.0)
		draw_arc(c, rad, PI * 0.1, PI * 0.9, 18, Color(1.0, 0.86, 0.5, a * 0.7), 5.0)

func _draw_tap() -> void:
	# un martillito que golpea la carcasa arriba a la izquierda de la cosa
	var tex := BenchKit.tex("res://assets/ui/icon_tap.png")
	var k := _tap_t / 0.6
	var bob := 0.0 if fmod(_tap_t, 0.2) > 0.1 else 10.0
	var p := origin + Vector2(VIEW.x * K * 0.5 - 24, -10 + bob - 20.0 * k)
	if tex:
		draw_texture_rect(tex, Rect2(_px(p), Vector2(48, 48)), false, Color(1, 1, 1, 1.0 - k * 0.6))

func _sparkle(c: Vector2, t: float) -> void:
	var a := clampf(1.0 - t / 0.5, 0.0, 1.0)
	for k in 6:
		var ang := k * TAU / 6.0 + 0.4
		var d := 70.0 + t * 80.0
		var p := _px(c + Vector2(cos(ang), sin(ang)) * d)
		draw_rect(Rect2(p, Vector2(6, 6)), Color(1.0, 0.95, 0.7, a))
		draw_rect(Rect2(p + Vector2(-4, 2), Vector2(14, 2)), Color(1.0, 0.95, 0.7, a * 0.6))

func _draw_tape(r: Rect2, k: float) -> void:
	# dos tiras de cinta cruzadas (el parche)
	var tape := Color(0.86, 0.78, 0.58, 0.95)
	var edge := Color(0.45, 0.36, 0.24, 0.95)
	var w := r.size.x * k
	var y1 := r.position.y + r.size.y * 0.32
	var y2 := r.position.y + r.size.y * 0.62
	draw_rect(Rect2(r.position.x - 6, y1, w + 12, 18), edge)
	draw_rect(Rect2(r.position.x - 4, y1 + 2, w + 8, 14), tape)
	draw_rect(Rect2(r.position.x - 6, y2, w + 12, 18), edge)
	draw_rect(Rect2(r.position.x - 4, y2 + 2, w + 8, 14), tape)
	var x := r.position.x
	while x < r.position.x + w:
		draw_rect(Rect2(x, y1 + 6, 6, 2), Color(0.7, 0.6, 0.4, 0.6))
		draw_rect(Rect2(x + 4, y2 + 8, 6, 2), Color(0.7, 0.6, 0.4, 0.6))
		x += 14.0
	if k >= 1.0:
		_tag(r.position + Vector2(r.size.x * 0.5, r.size.y + 8), "PATCHED", Color(0.93, 0.82, 0.55))

func _draw_power() -> void:
	var t := _power_t
	var vr := Rect2(origin, VIEW * K)
	match _power:
		"notes":
			var f: Font = UIKit.font_bold
			var src := slot_center(0)
			for k in 5:
				var ph := fmod(t * 0.7 + k * 0.2, 1.0)
				var p := _px(src + Vector2(sin(ph * 6.0 + k) * 30.0 + k * 22.0 - 40.0, -60.0 - ph * 140.0))
				draw_string(f, p, "♪" if k % 2 == 0 else "♫", HORIZONTAL_ALIGNMENT_LEFT, -1, 34,
					Color(1.0, 0.86, 0.45, (1.0 - ph) * minf(t * 3.0, 1.0)))
		"flame":
			# la llama sale por la tobera (a la izquierda de la vista del propulsor)
			var ni := -1
			for i in slots.size():
				if slots[i]["part"] == "nozzle":
					ni = i
			var r := slot_rect(ni) if ni >= 0 else Rect2(vr.position, Vector2(10, 10))
			var base := Vector2(r.position.x + 8, r.get_center().y)
			var grow := minf(t * 4.0, 1.0)
			var room := maxf(0.0, base.x - 6.0)          # la llama no sale de la alfombra
			# el resplandor azul en la tobera
			for k in 4:
				draw_circle(base, (34.0 + k * 16.0) * grow, Color(0.55, 0.8, 1.0, 0.16 - k * 0.03))
			for k in 7:
				var len := minf(room, (150.0 - k * 18.0) * grow * (0.85 + 0.15 * sin(t * 30.0 + k)))
				var hh := 60.0 - k * 8.0
				var col := Color(0.55, 0.8, 1.0, 0.35) if k < 3 else (Color(0.85, 0.95, 1.0, 0.7) if k < 6 else Color(1, 1, 1, 0.9))
				draw_rect(Rect2(_px(base - Vector2(len, hh / 2.0)), _px(Vector2(len, hh))), col)
			# ondas de calor que suben
			for k in 3:
				var ph := fmod(t * 1.2 + k / 3.0, 1.0)
				var y0 := base.y - 40.0 - ph * 70.0
				draw_rect(Rect2(_px(Vector2(base.x - 10 + k * 14, y0)), Vector2(4, 14)), Color(0.85, 0.95, 1.0, 0.5 * (1.0 - ph)))
		"sputter":
			var ni2 := 0
			var r2 := slot_rect(ni2)
			for k in 4:
				var ph := fmod(t * 1.4 + k * 0.25, 1.0)
				var p := _px(r2.get_center() + Vector2(-20 - ph * 60.0, -30 - ph * 90.0 + k * 12))
				draw_rect(Rect2(p, Vector2(14, 14) * (1.0 + ph)), Color(0.35, 0.33, 0.32, (1.0 - ph) * 0.8))
