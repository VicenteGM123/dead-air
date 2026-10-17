extends Control
class_name RuneGame
## Minijuego de la runa (para inscribir pergaminos): pasa el cursor por los puntos brillantes, en orden, antes de que
## se acabe el tiempo. Funciona con el ratón y con el cursor del mando (que mueve el ratón). Es generoso: los puntos
## se encienden desde lejos y el tiempo empieza al tocar el primero. Trazo PERFECTO = terminar a tiempo siguiendo las
## líneas la mayor parte del recorrido (como la zona dorada al remover: +1 estrella). Si se acaba el tiempo, la runa
## queda escrita igual (sin la estrella extra).

signal finished(perfect: bool)
signal node_lit(index: int)

const PAD := 78.0               # margen entre el borde de la página y los puntos
const NODE_R := 22.0            # radio de un punto (dibujo)
const HIT_R := 50.0             # distancia a la que un punto se enciende (generoso)
const BAND := 56.0              # distancia a la línea que todavía cuenta como "seguir el trazo"
const PERFECT_ACCURACY := 0.66  # parte del recorrido sobre las líneas para un trazo perfecto
const AUTO_SPEED := 620.0       # px/s del cursor automático (capturas)
const PEN_SPEED := 430.0        # px/s de la pluma con el teclado (flechas o WASD)

var points: Array = []          # Vector2 en 0..1 (Data.SPELLS[id]["rune"])
var ink := Color(1.0, 0.75, 0.35)
var time_limit := 8.0
var auto_until := -1.0          # capturas: un cursor automático recorre la runa hasta esta fracción (0..1); -1 = jugador

var completed := false          # se trazaron todos los puntos a tiempo
var perfect := false
var accuracy := 1.0

var _pts: Array = []            # los puntos en coordenadas locales
var _next := 0                  # el próximo punto a encender
var _state := 0                 # 0 = espera el primer punto, 1 = trazando (corre el tiempo), 2 = terminado
var _t := 0.0                   # tiempo trazando
var _anim := 0.0
var _cursor := Vector2(-9999, -9999)
var _has_cursor := false
var _on_path := 0.0
var _moved := 0.0
var _trail: Array = []          # [[pos, edad], ...]
var _sparks: Array = []         # [[pos, vel, vida, color], ...]
var _flash := 0.0
var _auto_d := 0.0
var _page: StyleBoxFlat
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.load_fonts()
	_font = UIKit.font_bold
	_page = StyleBoxFlat.new()
	_page.bg_color = Color("ead9b2")
	_page.border_color = Color("7a5634")
	_page.set_border_width_all(5)
	_page.set_corner_radius_all(16)
	_page.shadow_color = Color(0, 0, 0, 0.5)
	_page.shadow_size = 14
	_page.shadow_offset = Vector2(0, 6)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_pts.clear()
	var inner := size - Vector2(PAD, PAD) * 2.0
	for p in points:
		_pts.append(Vector2(PAD, PAD) + Vector2(p.x * inner.x, p.y * inner.y))

## Fracción de tiempo que queda (1 = toda).
func time_left() -> float:
	if _state == 0:
		return 1.0
	return clampf(1.0 - _t / maxf(time_limit, 0.1), 0.0, 1.0)

func _input(ev: InputEvent) -> void:
	if auto_until >= 0.0 or _state == 2:
		return
	if ev is InputEventMouseMotion or ev is InputEventMouseButton:
		_set_cursor(get_global_transform_with_canvas().affine_inverse() * ev.position)

func _process(delta: float) -> void:
	_anim += delta
	if _pts.size() != points.size():
		_layout()
	# dónde está el cursor al abrirse (ya con la página en su sitio); solo cuenta desde que se mueve
	if not _has_cursor and size.x > 1.0 and auto_until < 0.0:
		_has_cursor = true
		if PadCursor.active:
			_cursor = get_global_transform_with_canvas().affine_inverse() * PadCursor.where
		else:
			_cursor = get_local_mouse_position()
	if auto_until >= 0.0 and _state != 2:
		_auto_step(delta)
	elif _state != 2:
		_key_pen(delta)
	if _state == 1:
		_t += delta
		if _t >= time_limit:
			_finish(false)
	for tr in _trail:
		tr[1] += delta
	while not _trail.is_empty() and _trail[0][1] > 0.35:
		_trail.pop_front()
	for sp in _sparks:
		sp[0] += sp[1] * delta
		sp[1] *= 0.92
		sp[2] -= delta
	_sparks = _sparks.filter(func(sp): return sp[2] > 0.0)
	_flash = maxf(0.0, _flash - delta * 1.4)
	queue_redraw()

# ------------------------------------------------------------------ trazo

func _set_cursor(p: Vector2) -> void:
	if not _has_cursor:
		_has_cursor = true
		_cursor = p
		_check(p, p)
		return
	var a := _cursor
	_cursor = p
	_check(a, p)

## El cursor se movió de a hasta b: enciende los puntos que tocó (en orden) y mide si sigue la línea.
func _check(a: Vector2, b: Vector2) -> void:
	if _state == 2 or _pts.is_empty():
		return
	var step := a.distance_to(b)
	if step > 0.5:
		_trail.append([b, 0.0])
	if _state == 1 and step > 0.0 and _next > 0 and _next < _pts.size():
		_moved += step
		if _seg_dist((a + b) * 0.5, _pts[_next - 1], _pts[_next]) <= BAND:
			_on_path += step
	while _state != 2 and _next < _pts.size() and _seg_dist(_pts[_next], a, b) <= HIT_R:
		_light(_next)

func _light(i: int) -> void:
	_next = i + 1
	if i == 0:
		_state = 1
		_t = 0.0
	for k in 12:
		var ang := randf() * TAU
		_sparks.append([_pts[i], Vector2(cos(ang), sin(ang)) * randf_range(90.0, 260.0), randf_range(0.35, 0.7), ink.lightened(randf_range(0.0, 0.5))])
	Sfx.play_pitched("rune_node", pow(2.0, float(i * 2) / 12.0), -4.0)
	node_lit.emit(i)
	if _next >= _pts.size():
		_finish(true)

func _finish(done: bool) -> void:
	if _state == 2:
		return
	_state = 2
	completed = done
	accuracy = 1.0 if _moved < 1.0 else clampf(_on_path / _moved, 0.0, 1.0)
	perfect = done and accuracy >= PERFECT_ACCURACY
	_flash = 1.0 if done else 0.4
	if done:
		for p in _pts:
			for k in 8:
				var ang := randf() * TAU
				_sparks.append([p, Vector2(cos(ang), sin(ang)) * randf_range(120.0, 320.0), randf_range(0.5, 0.9), ink.lightened(0.4)])
		Sfx.play("rune_done", 0.02, -3.0 if perfect else -6.0)
	else:
		Sfx.play("stir", 0.05, -6.0)
	finished.emit(perfect)

## Teclado: las flechas (o WASD) mueven la pluma; empieza en el centro de la página si el cursor está fuera.
func _key_pen(delta: float) -> void:
	var kv := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)))
	if kv == Vector2.ZERO:
		return
	var start := _cursor
	if not _has_cursor or not Rect2(Vector2.ZERO, size).has_point(_cursor):
		_has_cursor = false
		start = size / 2.0
	_set_cursor((start + kv.normalized() * PEN_SPEED * delta).clamp(Vector2.ZERO, size))

## Cursor automático (capturas): recorre la runa a velocidad fija hasta auto_until.
func _auto_step(delta: float) -> void:
	if _pts.size() < 2:
		return
	var total := 0.0
	for i in range(1, _pts.size()):
		total += _pts[i - 1].distance_to(_pts[i])
	_auto_d = minf(_auto_d + AUTO_SPEED * delta, total * clampf(auto_until, 0.0, 1.0))
	var d := _auto_d
	var p: Vector2 = _pts[0]
	for i in range(1, _pts.size()):
		var L: float = _pts[i - 1].distance_to(_pts[i])
		if d <= L:
			p = _pts[i - 1].lerp(_pts[i], d / maxf(L, 0.001))
			break
		d -= L
		p = _pts[i]
	# un temblor de mano suave
	p += Vector2(sin(_anim * 9.0), cos(_anim * 7.0)) * 5.0
	_set_cursor(p)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ------------------------------------------------------------------ dibujo

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_page, r)
	var c := size / 2.0
	var ink_dark := ink.darkened(0.55)
	# borde interior y círculo mágico que gira despacio
	draw_rect(r.grow(-16.0), Color(0.48, 0.34, 0.2, 0.35), false, 2.0)
	var R := minf(size.x, size.y) * 0.5 - 34.0
	draw_arc(c, R, 0.0, TAU, 96, Color(ink_dark, 0.28), 3.0, true)
	draw_arc(c, R - 14.0, 0.0, TAU, 96, Color(ink_dark, 0.18), 2.0, true)
	for i in 36:
		var a := _anim * 0.08 + i * TAU / 36.0
		var l := 7.0 if i % 3 == 0 else 3.0
		draw_line(c + Vector2(cos(a), sin(a)) * (R - 14.0), c + Vector2(cos(a), sin(a)) * (R - 14.0 + l), Color(ink_dark, 0.3), 2.0, true)
	if _pts.is_empty():
		return
	# líneas: las trazadas brillan, las que faltan son guiones
	for i in range(1, _pts.size()):
		var a: Vector2 = _pts[i - 1]
		var b: Vector2 = _pts[i]
		if i < _next:
			draw_line(a, b, Color(0.22, 0.12, 0.06, 0.55), 15.0, true)
			draw_line(a, b, ink, 10.0, true)
			draw_line(a, b, Color(1, 1, 1, 0.75), 3.0, true)
		else:
			draw_dashed_line(a, b, Color(ink_dark, 0.55), 5.0, 14.0, true, true)
	# la línea que se está trazando: del último punto encendido al cursor
	if _state == 1 and _next > 0 and _next < _pts.size() and _has_cursor:
		var to := _cursor.clamp(Vector2(8, 8), size - Vector2(8, 8))
		draw_line(_pts[_next - 1], to, Color(ink, 0.7), 7.0, true)
	# estela del cursor
	for tr in _trail:
		var k: float = 1.0 - tr[1] / 0.35
		draw_circle(tr[0], 7.0 * k, Color(ink.lightened(0.3), 0.55 * k))
	# puntos
	for i in _pts.size():
		var p: Vector2 = _pts[i]
		if i < _next:
			draw_circle(p, NODE_R + 8.0, Color(ink, 0.3))
			draw_circle(p, NODE_R, Color(0.22, 0.12, 0.06, 0.8))
			draw_circle(p, NODE_R - 3.0, ink)
			draw_circle(p, 7.0, Color(1, 1, 1, 0.9))
		elif i == _next and _state != 2:
			var pulse := 0.5 + 0.5 * sin(_anim * 6.0)
			draw_circle(p, NODE_R + 12.0 + 6.0 * pulse, Color(ink, 0.18 + 0.12 * pulse))
			draw_circle(p, NODE_R, Color(ink.lightened(0.35), 0.95))
			draw_arc(p, NODE_R, 0.0, TAU, 32, Color(0.22, 0.12, 0.06, 0.9), 3.0, true)
			_draw_number(p, i + 1, Color(0.22, 0.12, 0.06))
		else:
			draw_circle(p, NODE_R, Color(0.96, 0.9, 0.76))
			draw_arc(p, NODE_R, 0.0, TAU, 32, Color(ink_dark, 0.8), 3.0, true)
			_draw_number(p, i + 1, Color(ink_dark, 0.9))
	# chispas
	for sp in _sparks:
		var k2: float = clampf(sp[2] / 0.6, 0.0, 1.0)
		var s := 3.0 + 3.0 * k2
		draw_rect(Rect2(sp[0] - Vector2(s, s) * 0.5, Vector2(s, s)), Color(sp[3], k2))
	# el tiempo: una barra que se consume (como una vela)
	var bar := Rect2(Vector2(46.0, size.y - 40.0), Vector2(size.x - 92.0, 12.0))
	draw_rect(bar, Color(0.22, 0.12, 0.06, 0.45))
	var left := time_left()
	var bc := ink if left > 0.3 else ink.lerp(Color(1.0, 0.35, 0.3), 0.6)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)), bc)
	draw_rect(bar, Color(0.22, 0.12, 0.06, 0.8), false, 2.0)
	if _flash > 0.0:
		draw_style_box(_flash_box(), r)

func _draw_number(p: Vector2, n: int, col: Color) -> void:
	var fs := 22
	var txt := str(n)
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, p + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _flash_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.95, 0.75, 0.45 * _flash) if completed else Color(0.3, 0.2, 0.1, 0.3 * _flash)
	sb.set_corner_radius_all(16)
	return sb

## Un dibujo pequeño de la runa (para la página del grimorio): Control que se dibuja solo.
static func preview(pts: Array, col: Color, side := 150.0) -> Control:
	var cv := Control.new()
	cv.custom_minimum_size = Vector2(side, side)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.draw.connect(func():
		var pad := side * 0.14
		var inner := side - pad * 2.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("ead9b2")
		sb.border_color = Color("7a5634")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		cv.draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(side, side)))
		var q := []
		for p in pts:
			q.append(Vector2(pad, pad) + p * inner)
		for i in range(1, q.size()):
			cv.draw_line(q[i - 1], q[i], Color(0.22, 0.12, 0.06, 0.5), 7.0, true)
			cv.draw_line(q[i - 1], q[i], col, 4.0, true)
		for i in q.size():
			cv.draw_circle(q[i], 7.0 if i > 0 else 9.0, Color(0.22, 0.12, 0.06, 0.85))
			cv.draw_circle(q[i], 5.0 if i > 0 else 7.0, col.lightened(0.3) if i > 0 else Color(1, 1, 1)))
	return cv
