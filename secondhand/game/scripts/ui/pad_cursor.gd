extends CanvasLayer
class_name PadCursor
## Mando (Xbox y compatibles). El juego se juega con el ratón, así que el mando lleva su propio cursor, que mueve
## el ratón de Godot (los hovers, los tooltips y los clics en el escenario 3D funcionan igual), y botones que hacen
## de teclas:
##   stick izquierdo / cruceta: mover el cursor     A: tocar donde está el cursor (o avanzar el diálogo)
##   B: volver / cerrar (Esc)     X: Espacio (avanzar)     Menú: Esc     LB / RB: saltar al objeto tocable anterior /
##   siguiente     stick derecho: desplazar listas
## El cursor aparece al usar el mando y se esconde en cuanto se mueve el ratón.
##
## --- SS SEED: copiado de Midnight Cauldron (scripts/ui/pad_cursor.gd) con el mismo comportamiento, pero sin atarlo
## a sus pantallas. Quien lo usa (main.gd) le da Callables:
##   buttons_root   () -> Control    la capa que manda ahora: sus botones visibles y activos son tocables
##   world_picks    () -> Array      lo tocable del escenario 3D: [[Node3D, alto sobre su origen], ...]
##   camera         () -> Camera3D   la cámara del escenario a la vista (para proyectar world_picks)
##   dialog_waiting () -> bool       hay un diálogo esperando: A avanza (como Espacio) si no apunta a un botón
##   modal_open     () -> bool       hay una ventana abierta: B manda Esc (sin Callable: B siempre manda Esc)
## Y los controles de Secondhand Stars («pad: d-pad / stick walk, A interact, B back»): mientras se puede caminar
## (Walker.dpad_walk) el stick izquierdo y la cruceta caminan (walker.gd), el cursor se esconde y A es "interactuar"
## (manda la tecla E = acción "interact"); LB / RB muestran el cursor sobre lo tocable y entonces A toca.
## Y / Vista mandan las teclas de y_key / view_key (ninguna por defecto). pad_in_use (estático) dice si el último
## aparato usado fue el mando: los avisos muestran "A" en vez de "E" (UIKit.prompt). La línea de ayuda de los
## controles sale por la señal hint_changed (antes iba directo a la interfaz de Midnight Cauldron).

signal hint_changed(text: String)
signal device_changed(pad: bool)

const DEAD := 0.2            # zona muerta de los sticks
const SPEED := 1280.0        # píxeles por segundo con el stick a fondo (un ancho de pantalla; base 1280x720)
const DPAD_STEP := 8.0       # un toque de la cruceta
const DPAD_SPEED := 320.0    # cruceta mantenida
const SNAP_DIST := 40.0      # al soltar el stick cerca de algo tocable, el cursor se acerca solo
const PAD_DEVICE := 77       # marca los eventos que inventa el mando (para no confundirlos con el ratón y el teclado)
const PAD_HINT := "A tap · B back · X next"
const PAD_HINT_WALK := "Stick walk · A interact · LB/RB point"
const WEB_SOUND_HINT := "Sound: click or press a key"

static var active := false          # el cursor del mando está a la vista (y el del sistema, escondido)
static var where := Vector2.ZERO    # dónde está, en coordenadas del lienzo (los tooltips lo usan)
static var pad_in_use := false      # --- SS SEED: el último aparato usado fue el mando

var buttons_root: Callable
var world_picks: Callable
var camera: Callable
var dialog_waiting: Callable
var modal_open: Callable
var y_key: Key = KEY_NONE
var view_key: Key = KEY_NONE
var needs_gesture := false   # web: el navegador no deja sonar nada hasta un clic o una tecla
var _sprite: Node2D
var _pos := Vector2(640, 360)
var _hold := 0.0             # tiempo con el stick inclinado (acelera un poco)
var _moving := false
var _gliding := false
var _glide_to := Vector2.ZERO
var _dpad_prev := Vector2.ZERO
var _dpad_hold := 0.0
var _scroll := 0.0
var _a_down := false
var _a_mode := ""            # cómo bajó A: "key" (Espacio), "interact" (E) o "click"
var _hint := ""

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://assets/ui/cursor.png"):
		var s := Sprite2D.new()
		s.texture = load("res://assets/ui/cursor.png")
		s.centered = false
		s.offset = Vector2(-1, -1)   # la punta de la flecha es el píxel (1, 1)
		s.scale = Vector2(2, 2)
		_sprite = s
	else:
		# sin arte: una flecha ámbar con borde oscuro
		var n := Node2D.new()
		var edge := Polygon2D.new()
		edge.polygon = PackedVector2Array([Vector2(-2, -3), Vector2(19, 15), Vector2(9, 16), Vector2(14, 27), Vector2(9, 29), Vector2(4, 18), Vector2(-2, 24)])
		edge.color = Color(0.12, 0.09, 0.07)
		n.add_child(edge)
		var fill := Polygon2D.new()
		fill.polygon = PackedVector2Array([Vector2(0, 0), Vector2(15, 13), Vector2(7, 14), Vector2(11.5, 24), Vector2(9.5, 25), Vector2(5, 15.5), Vector2(0, 20)])
		fill.color = Color(1.0, 0.76, 0.34)
		n.add_child(fill)
		_sprite = n
	_sprite.visible = false
	add_child(_sprite)
	Input.joy_connection_changed.connect(_on_joy_connection)
	if OS.has_feature("web"):
		needs_gesture = not JavaScriptBridge.eval("!!(navigator.userActivation && navigator.userActivation.hasBeenActive)", true)
	_refresh_hint.call_deferred()

func _on_joy_connection(_device: int, _connected: bool) -> void:
	if Input.get_connected_joypads().is_empty():
		_show(false)
		_set_pad(false)
	_refresh_hint()

func _set_pad(on: bool) -> void:
	if on == pad_in_use:
		return
	pad_in_use = on
	device_changed.emit(on)
	_refresh_hint()

func _walk_mode() -> bool:
	return Walker.dpad_walk and not _modal()

func _modal() -> bool:
	return modal_open.is_valid() and bool(modal_open.call())

func _input(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton:
		# el mando no toca la interfaz directamente (así ui_accept y compañía no pulsan ni mueven el foco)
		get_viewport().set_input_as_handled()
		_set_pad(true)
		_on_button(ev.button_index, ev.pressed)
	elif ev is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()   # los sticks se leen en _process
		if absf(ev.axis_value) > 0.5:
			_set_pad(true)
	elif ev.device != PAD_DEVICE:
		if needs_gesture and ev.is_pressed() and (ev is InputEventMouseButton or ev is InputEventKey or ev is InputEventScreenTouch):
			needs_gesture = false
			_refresh_hint()
		if ev is InputEventKey or ev is InputEventMouseButton or (ev is InputEventMouseMotion and ev.relative.length() > 2.0):
			_set_pad(false)
		if active and (ev is InputEventMouseButton or (ev is InputEventMouseMotion and ev.relative.length() > 2.0)):
			_show(false)

func _on_button(b: int, pressed: bool) -> void:
	match b:
		JOY_BUTTON_A:
			if pressed and not _a_down:
				_a_down = true
				if not active and _walk_mode():
					_a_mode = "interact"
					_key(KEY_E, true)
				elif _a_advances_dialog():
					_a_mode = "key"
					_key(KEY_SPACE, true)
				else:
					_a_mode = "click"
					_show(true)
					_mouse_button(true)
			elif not pressed and _a_down:
				_a_down = false
				match _a_mode:
					"interact":
						_key(KEY_E, false)
					"key":
						_key(KEY_SPACE, false)
					_:
						_mouse_button(false)
		JOY_BUTTON_B:
			if pressed and (not modal_open.is_valid() or _modal()):
				_tap(KEY_ESCAPE)
		JOY_BUTTON_X:
			_key(KEY_SPACE, pressed)
		JOY_BUTTON_Y:
			if pressed and y_key != KEY_NONE:
				_tap(y_key)
		JOY_BUTTON_BACK:
			if pressed and view_key != KEY_NONE:
				_tap(view_key)
		JOY_BUTTON_START:
			if pressed:
				_tap(KEY_ESCAPE)
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			if pressed:
				_show(true)
				_jump(1 if b == JOY_BUTTON_RIGHT_SHOULDER else -1)

func _process(delta: float) -> void:
	var stick := Vector2.ZERO
	var dpad := Vector2.ZERO
	var scroll := 0.0
	for d in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if s.length() > stick.length():
			stick = s
		dpad.x += float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT))
		dpad.y += float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP))
		var r := Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)
		if absf(r) > absf(scroll):
			scroll = r
	dpad = dpad.clamp(Vector2(-1, -1), Vector2(1, 1))
	# mientras se puede caminar, el stick izquierdo y la cruceta (izquierda / derecha) mueven a Nell (walker.gd)
	if _walk_mode():
		dpad.x = 0.0
		if not active:
			stick = Vector2.ZERO
	var m := (stick.length() - DEAD) / (1.0 - DEAD)
	if m > 0.0 or dpad != Vector2.ZERO or (absf(scroll) > DEAD and not _walk_mode()):
		_show(true)
	var p := _pos
	if m > 0.0:
		# más rápido cuanto más se inclina, y un poco de aceleración al mantenerlo
		var accel := lerpf(0.6, 1.0, clampf(_hold / 0.5, 0.0, 1.0))
		p += stick.normalized() * SPEED * accel * pow(minf(m, 1.0), 1.6) * delta
		_hold += delta
		_moving = true
		_gliding = false
	else:
		_hold = 0.0
		if _moving:
			# recién soltado: si quedó cerca de algo tocable, el cursor se acerca solo
			_moving = false
			_glide(_snap_target(p))
	if dpad != Vector2.ZERO:
		_gliding = false
		if _dpad_prev == Vector2.ZERO:
			p += dpad * DPAD_STEP
		else:
			_dpad_hold += delta
			if _dpad_hold > 0.3:
				p += dpad * DPAD_SPEED * delta
	else:
		_dpad_hold = 0.0
	_dpad_prev = dpad
	if _gliding:
		p = p.lerp(_glide_to, 1.0 - exp(-18.0 * delta))
		if p.distance_to(_glide_to) < 1.0:
			p = _glide_to
			_gliding = false
	# stick derecho: rueda del ratón (listas largas)
	if active and absf(scroll) > DEAD:
		_scroll += delta * lerpf(4.0, 14.0, (absf(scroll) - DEAD) / (1.0 - DEAD))
		while _scroll >= 1.0:
			_scroll -= 1.0
			_wheel(scroll < 0.0)
	else:
		_scroll = 0.99   # el primer toque desplaza enseguida
	if active and p != _pos:
		_move_to(p)
	_refresh_hint()   # --- SS SEED: la ayuda cambia al entrar y salir del modo caminar

# ------------------------------------------------------------------ cursor

func _show(on: bool) -> void:
	if on == active:
		return
	active = on
	_sprite.visible = on
	if on:
		# aparece donde estaba el ratón
		var r := get_viewport().get_visible_rect()
		var mp := get_viewport().get_mouse_position()
		_pos = mp if r.has_point(mp) and mp != Vector2.ZERO else r.get_center()
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_move_to(_pos)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_moving = false
		_gliding = false
		if _a_down and _a_mode == "click":
			_a_down = false
			_mouse_button(false)
	_refresh_hint()

## Esconde el cursor del mando (p. ej. al volver a caminar).
func hide_cursor() -> void:
	_show(false)

func _glide(to: Vector2) -> void:
	if to.x >= 0.0 and to.distance_to(_pos) > 1.0:
		_glide_to = to
		_gliding = true

func _move_to(p: Vector2) -> void:
	var r := get_viewport().get_visible_rect()
	p = p.clamp(r.position, r.end - Vector2.ONE)
	var mm := InputEventMouseMotion.new()
	_fill(mm, p)
	mm.relative = _window(p) - _window(_pos)
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down and _a_mode == "click" else 0
	_pos = p
	where = p
	_sprite.position = p
	Input.parse_input_event(mm)

# de coordenadas del lienzo a coordenadas de la ventana
func _window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

func _fill(e: InputEventMouse, p: Vector2) -> void:
	e.device = PAD_DEVICE
	e.position = _window(p)
	e.global_position = e.position

func _mouse_button(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	_fill(e, _pos)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)

func _wheel(up: bool) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		_fill(e, _pos)
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = pressed
		e.factor = 1.0
		Input.parse_input_event(e)

func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.device = PAD_DEVICE
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)

# ------------------------------------------------------------------ objetos tocables

## A avanza el diálogo (como Espacio) si hay uno esperando y el cursor no está sobre un botón (una respuesta, p. ej.).
func _a_advances_dialog() -> bool:
	if not dialog_waiting.is_valid() or not bool(dialog_waiting.call()):
		return false
	if active:
		for b in _buttons():
			if b.get_global_rect().has_point(_pos):
				return false
	return true

## Botones visibles y activos de la capa que manda ahora.
func _buttons() -> Array:
	var out := []
	if buttons_root.is_valid():
		var root = buttons_root.call()
		if root is Node and is_instance_valid(root):
			_collect(root, out)
	return out

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if c is BaseButton and not c.disabled and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(c)
		_collect(c, out)

## Todo lo que se puede tocar, como rectángulos en el lienzo: botones, y si no hay ventana abierta, lo tocable del
## escenario 3D que está en pantalla.
func _targets() -> Array:
	var out := []
	for b in _buttons():
		out.append(b.get_global_rect())
	if _modal() or not world_picks.is_valid() or not camera.is_valid():
		return out
	var cam = camera.call()
	if not (cam is Camera3D) or not is_instance_valid(cam):
		return out
	var view := get_viewport().get_visible_rect()
	for pk in world_picks.call():
		var n: Node3D = pk[0]
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var w: Vector3 = n.global_position + Vector3(0, pk[1], 0)
		if cam.is_position_behind(w):
			continue
		var sp: Vector2 = cam.unproject_position(w)
		if not view.has_point(sp):
			continue
		out.append(Rect2(sp - Vector2(20, 20), Vector2(40, 40)))
	return out

## Al soltar el stick: el centro de lo tocable que tiene debajo o a menos de SNAP_DIST (o (-1, -1) si no hay nada).
func _snap_target(p: Vector2) -> Vector2:
	var best := Vector2(-1, -1)
	var best_k := INF
	for r in _targets():
		var d := p.distance_to(p.clamp(r.position, r.end))
		var k := d * 10000.0 + p.distance_to(r.get_center())
		if d < SNAP_DIST and k < best_k:
			best_k = k
			best = r.get_center()
	return best

## LB / RB: el cursor salta al objeto tocable anterior o siguiente, en orden de lectura.
func _jump(dir: int) -> void:
	var order := func(c: Vector2) -> float: return roundf(c.y / 60.0) * 100000.0 + c.x
	var centers := []
	for r in _targets():
		centers.append(r.get_center())
	if centers.is_empty():
		return
	centers.sort_custom(func(a, b): return order.call(a) < order.call(b))
	var here: float = order.call(_pos)
	var pick: Vector2 = centers[0] if dir > 0 else centers[-1]
	if dir > 0:
		for c in centers:
			if order.call(c) > here + 1.0:
				pick = c
				break
	else:
		for i in range(centers.size() - 1, -1, -1):
			if order.call(centers[i]) < here - 1.0:
				pick = centers[i]
				break
	_glide(pick)

# ------------------------------------------------------------------ textos de controles

func _refresh_hint() -> void:
	var t := ""
	if active or pad_in_use or not Input.get_connected_joypads().is_empty():
		t = PAD_HINT if (active or not Walker.dpad_walk) else PAD_HINT_WALK
	if needs_gesture:
		t = (t + "\n" if t != "" else "") + WEB_SOUND_HINT
	if t != _hint:
		_hint = t
		hint_changed.emit(t)

## La línea de ayuda de los controles que toca mostrar ahora ("" = ninguna).
func hint() -> String:
	return _hint
