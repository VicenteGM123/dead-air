extends Control
class_name BenchSolder
## SOLDAR: un primer plano de la placa con 3-5 puntos (pads) unidos por una pista de cobre. Se pasa el soldador por
## los puntos EN ORDEN (no hace falta hacer clic): el tiempo corre desde el primero. Prolijidad = la parte del
## recorrido que va sobre la pista (como la runa de Midnight Cauldron, scripts/ui/rune_game.gd, de donde sale la
## mecánica). Ratón: mover; teclado: flechas o WASD mueven el soldador; mando: el stick mueve el cursor (PadCursor
## mueve el ratón). Generoso: los puntos se encienden desde lejos.
## --- SS BENCH (nuevo).

signal finished(completed: bool, accuracy: float)
signal pad_lit(index: int, total: int)

const HIT_R := 36.0             # distancia a la que un punto se suelda (generoso)
const BAND := 30.0              # distancia a la pista que todavía cuenta como "sobre la pista"
const PEN_SPEED := 360.0        # px/s del soldador con el teclado
const AUTO_SPEED := 520.0       # px/s del soldador automático (bot y capturas)

var n_pads := 4
var time_limit := 8.0
var part := ""                  # la pieza nueva (se ve en la esquina de la placa)
var auto_until := -1.0          # bot / capturas: el soldador recorre solo hasta esta fracción (0..1); -1 = jugador
var auto_wobble := 0.0          # bot torpe: cuánto se sale de la pista (px)

var completed := false
var accuracy := 1.0
var _pts: Array = []            # los puntos en coordenadas locales
var _next := 0
var _state := 0                 # 0 = espera el primero, 1 = soldando (corre el tiempo), 2 = terminado
var _t := 0.0                   # tiempo soldando
var _anim := 0.0
var _iron := Vector2(-999, -999)
var _has_iron := false
var _on := 0.0
var _moved := 0.0
var _trail: Array = []          # [[pos, edad, sobre_la_pista], ...]
var _smoke: Array = []          # [[pos, vel, vida]]
var _auto_d := 0.0
var _seed := 0
var _board: Rect2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Una placa nueva: n puntos en zigzag (seed: siempre la misma para el mismo trabajo).
func setup(pads: int, seed: int, part_id: String) -> void:
	n_pads = clampi(pads, 3, 5)
	_seed = seed
	part = part_id
	time_limit = 2.2 + 1.6 * n_pads
	completed = false
	accuracy = 1.0
	_next = 0
	_state = 0
	_t = 0.0
	_on = 0.0
	_moved = 0.0
	_trail.clear()
	_smoke.clear()
	_has_iron = false
	_auto_d = 0.0
	auto_until = -1.0
	auto_wobble = 0.0
	_layout()

func _layout() -> void:
	_board = Rect2(Vector2.ZERO, size).grow(-6)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_pts.clear()
	var x0 := _board.position.x + 150.0
	var x1 := _board.end.x - 70.0
	var top := _board.position.y + 120.0
	var bot := _board.end.y - 70.0
	var hi := rng.randf() < 0.5
	for i in n_pads:
		var x := lerpf(x0, x1, float(i) / float(n_pads - 1))
		var y := (top + rng.randf_range(0.0, 50.0)) if hi else (bot - rng.randf_range(0.0, 50.0))
		hi = not hi
		_pts.append(Vector2(x, y).round())

func is_done() -> bool:
	return _state == 2

func lit() -> int:
	return _next

func time_left() -> float:
	return 1.0 if _state == 0 else clampf(1.0 - _t / maxf(time_limit, 0.1), 0.0, 1.0)

## Punto i (para el bot y las capturas).
func pad_pos(i: int) -> Vector2:
	return _pts[i] if i >= 0 and i < _pts.size() else Vector2.ZERO

func _input(ev: InputEvent) -> void:
	if not is_visible_in_tree() or auto_until >= 0.0 or _state == 2:
		return
	if ev is InputEventMouseMotion or ev is InputEventMouseButton:
		_set_iron(get_global_transform_with_canvas().affine_inverse() * ev.position)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_anim += delta
	if _pts.size() != n_pads:
		_layout()
	if not _has_iron and auto_until < 0.0 and size.x > 1.0:
		_has_iron = true
		_iron = (get_global_transform_with_canvas().affine_inverse() * PadCursor.where) if PadCursor.active else get_local_mouse_position()
	if auto_until >= 0.0 and _state != 2:
		_auto_step(delta)
	elif _state != 2:
		_key_pen(delta)
	if _state == 0:
		_t += delta
		if _t >= 5.0:          # nadie empezó: el tiempo corre igual (el paso no se queda colgado)
			_state = 1
			_t = 0.0
	elif _state == 1:
		_t += delta
		if _t >= time_limit:
			_finish(false)
	for tr in _trail:
		tr[1] += delta
	while not _trail.is_empty() and _trail[0][1] > 0.6:
		_trail.pop_front()
	for s in _smoke:
		s[0] += s[1] * delta
		s[2] -= delta
	_smoke = _smoke.filter(func(s): return s[2] > 0.0)
	queue_redraw()

func _set_iron(p: Vector2) -> void:
	if not _has_iron:
		_has_iron = true
		_iron = p
		_check(p, p)
		return
	var a := _iron
	_iron = p
	_check(a, p)

func _check(a: Vector2, b: Vector2) -> void:
	if _state == 2 or _pts.is_empty():
		return
	var step := a.distance_to(b)
	var on_path := false
	if _state == 1 and step > 0.0 and _next > 0 and _next < _pts.size():
		_moved += step
		if _seg_dist((a + b) * 0.5, _pts[_next - 1], _pts[_next]) <= BAND:
			_on += step
			on_path = true
	if step > 0.5:
		_trail.append([b, 0.0, on_path])
		if on_path and randf() < 0.35:
			_smoke.append([b, Vector2(randf_range(-10, 10), randf_range(-50, -30)), 0.7])
	while _state != 2 and _next < _pts.size() and _seg_dist(_pts[_next], a, b) <= HIT_R:
		_light(_next)

func _light(i: int) -> void:
	_next = i + 1
	if i == 0 and _state == 0:
		_state = 1
		_t = 0.0
	for k in 6:
		_smoke.append([_pts[i], Vector2(randf_range(-40, 40), randf_range(-90, -40)), randf_range(0.5, 0.9)])
	Sfx.play_pitched("sizzle", 0.9 + 0.1 * i, -6.0)
	pad_lit.emit(_next, _pts.size())
	if _next >= _pts.size():
		_finish(true)

func _finish(done: bool) -> void:
	if _state == 2:
		return
	_state = 2
	completed = done
	accuracy = 1.0 if _moved < 1.0 else clampf(_on / _moved, 0.0, 1.0)
	if not done and _next <= 1:
		accuracy = 0.0      # no se soldó nada
	finished.emit(completed, accuracy)

func _key_pen(delta: float) -> void:
	var kv := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)))
	if kv == Vector2.ZERO:
		return
	var start := _iron
	if not _has_iron or not _board.has_point(_iron):
		# con el teclado el soldador aparece sobre el primer punto
		_has_iron = false
		start = _pts[0] if not _pts.is_empty() else size / 2.0
	_set_iron((start + kv.normalized() * PEN_SPEED * delta).clamp(_board.position, _board.end))

## El soldador automático: recorre la pista a velocidad fija (con auto_wobble, se sale un poco).
func _auto_step(delta: float) -> void:
	if _pts.size() < 2:
		return
	var total := 0.0
	for i in range(1, _pts.size()):
		total += _pts[i - 1].distance_to(_pts[i])
	var stop := total * clampf(auto_until, 0.0, 1.0)
	if _auto_d >= stop:
		return
	if _auto_d <= 0.0:
		_has_iron = false        # empieza justo sobre el primer punto
	# en pasitos de 10 px (un cuadro largo no se saltea puntos)
	var remaining := AUTO_SPEED * delta
	while remaining > 0.0 and _auto_d < stop and _state != 2:
		var stp := minf(remaining, 10.0)
		remaining -= stp
		_auto_d = minf(_auto_d + stp, stop)
		var p := _path_point(_auto_d)
		if auto_wobble > 0.0:
			p += Vector2(0, sin(_auto_d / 40.0) * auto_wobble)
		_set_iron(p)

## El punto de la pista a d px del primer punto.
func _path_point(d: float) -> Vector2:
	var p: Vector2 = _pts[0]
	for i in range(1, _pts.size()):
		var seg: float = _pts[i - 1].distance_to(_pts[i])
		if d <= seg:
			return _pts[i - 1].lerp(_pts[i], d / maxf(seg, 0.001))
		d -= seg
		p = _pts[i]
	return p

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ------------------------------------------------------------------ dibujo

func _draw() -> void:
	var b := _board
	# la placa: verde oscuro con canto, agujeros de tornillo y una grilla de vías
	draw_rect(b.grow(6), Color(0.03, 0.04, 0.03, 0.95))
	draw_rect(b, Color(0.11, 0.27, 0.2))
	draw_rect(Rect2(b.position, Vector2(b.size.x, 4)), Color(0.2, 0.42, 0.32))
	draw_rect(Rect2(b.position + Vector2(0, b.size.y - 6), Vector2(b.size.x, 6)), Color(0.06, 0.15, 0.11))
	var vx := b.position.x + 20.0
	while vx < b.end.x - 10.0:
		var vy := b.position.y + 24.0
		while vy < b.end.y - 10.0:
			draw_rect(Rect2(vx, vy, 2, 2), Color(0.22, 0.45, 0.33, 0.6))
			vy += 24.0
		vx += 24.0
	for c in [b.position + Vector2(18, 18), Vector2(b.end.x - 18, b.position.y + 18), Vector2(b.position.x + 18, b.end.y - 18), b.end - Vector2(18, 18)]:
		draw_circle(c, 9.0, Color(0.05, 0.07, 0.06))
		draw_arc(c, 9.0, 0, TAU, 16, Color(0.75, 0.68, 0.45), 3.0)
	var f: Font = UIKit.font_mono
	# la pieza nueva, arriba a la izquierda (se ve qué se está soldando)
	var pt: Texture2D = BenchKit.tex("res://assets/parts/%s.png" % part)
	if pt:
		draw_texture_rect(pt, Rect2(b.position + Vector2(30, 26), Vector2(96, 96)), false)
	draw_string(f, b.position + Vector2(34, 142), BenchData.part_name(part).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200, 15,
		Color(0.85, 0.92, 0.8, 0.85))
	# la barra del tiempo (arriba)
	var tb := Rect2(b.position.x + 170, b.position.y + 26, b.size.x - 200, 12)
	draw_rect(tb, Color(0.03, 0.06, 0.05))
	var left := time_left()
	var tcol := Color(1.0, 0.72, 0.3) if left > 0.3 else BenchKit.RED
	draw_rect(Rect2(tb.position, Vector2(roundf(tb.size.x * left), tb.size.y)), tcol)
	draw_string(f, tb.position + Vector2(0, 34), "TRACE THE PADS IN ORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.95, 0.85, 0.8))
	# la pista: punteada hasta soldarla, cobre brillante después
	for i in range(1, _pts.size()):
		var a: Vector2 = _pts[i - 1]
		var c2: Vector2 = _pts[i]
		var done := i < _next
		var cur := i == _next and _state == 1
		if done:
			draw_line(a, c2, Color(0.35, 0.2, 0.1), 16.0)
			draw_line(a, c2, Color(0.86, 0.55, 0.28), 10.0)
			draw_line(a, c2, Color(1.0, 0.85, 0.6), 3.0)
		else:
			var segs := int(a.distance_to(c2) / 18.0)
			for k in segs:
				if k % 2 == 0:
					var p0 := a.lerp(c2, float(k) / segs)
					var p1 := a.lerp(c2, float(k + 1) / segs)
					draw_line(p0, p1, Color(0.85, 0.55, 0.3, 0.9 if cur else 0.45), 8.0 if cur else 6.0)
	# el rastro del soldador (plateado sobre la pista, rojo afuera)
	for tr in _trail:
		var al: float = 1.0 - float(tr[1]) / 0.6
		var col := Color(0.95, 0.95, 0.9, 0.7 * al) if tr[2] else Color(1.0, 0.4, 0.3, 0.45 * al)
		draw_rect(Rect2(tr[0] - Vector2(3, 3), Vector2(6, 6)), col)
	# los puntos
	for i in _pts.size():
		var p: Vector2 = _pts[i]
		var is_next := i == _next and _state != 2
		var lit_now := i < _next
		draw_circle(p, 22.0, Color(0.05, 0.1, 0.07))
		draw_circle(p, 19.0, Color(0.8, 0.5, 0.25))
		draw_circle(p, 12.0, Color(0.32, 0.18, 0.08))
		if lit_now:
			draw_circle(p, 16.0, Color(0.62, 0.64, 0.66))
			draw_circle(p, 13.0, Color(0.85, 0.87, 0.88))
			draw_circle(p + Vector2(-5, -5), 4.0, Color(1, 1, 1))
		elif is_next:
			var pulse := 0.5 + 0.5 * sin(_anim * 9.0)
			draw_arc(p, 28.0 + pulse * 6.0, 0, TAU, 28, Color(1.0, 0.78, 0.35, 0.5 + 0.5 * pulse), 4.0)
		draw_string(UIKit.font_bold, p + Vector2(-6, -30), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.95, 0.97, 0.9, 0.95 if (is_next or lit_now) else 0.55))
	# humo
	for s in _smoke:
		var a2: float = clampf(s[2] / 0.8, 0.0, 1.0)
		draw_rect(Rect2((s[0] as Vector2).round() - Vector2(4, 4), Vector2(8, 8)), Color(0.85, 0.85, 0.8, 0.35 * a2))
	# el soldador (punta caliente + mango)
	if _has_iron and _state != 2 and _board.grow(40).has_point(_iron):
		var tip := _iron.round()
		draw_line(tip + Vector2(10, 10), tip + Vector2(46, 46), Color(0.55, 0.56, 0.58), 8.0)
		draw_line(tip + Vector2(44, 44), tip + Vector2(92, 92), Color(0.12, 0.1, 0.1), 18.0)
		draw_line(tip + Vector2(46, 46), tip + Vector2(90, 90), Color(0.62, 0.32, 0.18), 12.0)
		draw_line(tip, tip + Vector2(12, 12), Color(0.8, 0.8, 0.82), 6.0)
		var glow := 0.6 + 0.4 * sin(_anim * 20.0)
		draw_circle(tip, 10.0, Color(1.0, 0.55, 0.15, 0.35 * glow))
		draw_circle(tip, 5.0, Color(1.0, 0.85, 0.5))
