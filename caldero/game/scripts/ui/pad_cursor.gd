extends CanvasLayer
class_name PadCursor
## Mando (Xbox y compatibles). El juego se juega con el ratón, así que el mando lleva su propio cursor, que mueve
## el ratón de Godot (los hovers, los tooltips y los clics en el escenario 3D funcionan igual), y botones que hacen
## de teclas:
##   stick izquierdo / cruceta: mover el cursor     A: tocar donde está el cursor (o avanzar el diálogo)
##   B: volver / cerrar (Esc)     X: Espacio (avanzar, remover)     Y: recetas (R)     Vista: diario (J)
##   Menú: ajustes (Esc)     LB / RB: saltar al objeto tocable anterior / siguiente     stick derecho: desplazar listas
## El cursor aparece al usar el mando y se esconde en cuanto se mueve el ratón.

const DEAD := 0.2            # zona muerta de los sticks
const SPEED := 1920.0        # píxeles por segundo con el stick a fondo (un ancho de pantalla)
const DPAD_STEP := 12.0      # un toque de la cruceta
const DPAD_SPEED := 480.0    # cruceta mantenida
const SNAP_DIST := 60.0      # al soltar el stick cerca de algo tocable, el cursor se acerca solo
const PAD_DEVICE := 77       # marca los eventos que inventa el mando (para no confundirlos con el ratón y el teclado)
const PAD_HINT := "Mando: stick izquierdo mueve el cursor · A tocar · B volver · X avanzar · Y recetas · Vista diario · Menú ajustes"
const WEB_SOUND_HINT := "En el navegador, el sonido empieza con el primer clic o tecla (el mando no cuenta)."

static var active := false          # el cursor del mando está a la vista (y el del sistema, escondido)
static var where := Vector2.ZERO    # dónde está, en coordenadas del lienzo (los tooltips lo usan)

var ui: GameUI
var ov: Overlays
var world: ShopWorld
var needs_gesture := false   # web: el navegador no deja sonar nada hasta un clic o una tecla
var _sprite: Sprite2D
var _pos := Vector2(960, 540)
var _hold := 0.0             # tiempo con el stick inclinado (acelera un poco)
var _moving := false
var _gliding := false
var _glide_to := Vector2.ZERO
var _dpad_prev := Vector2.ZERO
var _dpad_hold := 0.0
var _scroll := 0.0
var _a_down := false
var _a_key := false          # A bajó como Espacio (diálogo) y no como clic
var _hint := ""

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/ui/cursor.png")
	_sprite.centered = false
	_sprite.offset = Vector2(-1, -1)   # la punta de la flecha es el píxel (1, 1)
	_sprite.scale = Vector2(3, 3)
	_sprite.visible = false
	add_child(_sprite)
	Input.joy_connection_changed.connect(_on_joy_connection)
	if OS.has_feature("web"):
		needs_gesture = not JavaScriptBridge.eval("!!(navigator.userActivation && navigator.userActivation.hasBeenActive)", true)
	_refresh_hint.call_deferred()

func _on_joy_connection(_device: int, _connected: bool) -> void:
	if Input.get_connected_joypads().is_empty():
		_show(false)
	_refresh_hint()

func _input(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton:
		# el mando no toca la interfaz directamente (así ui_accept y compañía no pulsan ni mueven el foco)
		get_viewport().set_input_as_handled()
		_on_button(ev.button_index, ev.pressed)
	elif ev is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()   # los sticks se leen en _process
	elif ev.device != PAD_DEVICE:
		if needs_gesture and ev.is_pressed() and (ev is InputEventMouseButton or ev is InputEventKey or ev is InputEventScreenTouch):
			needs_gesture = false
			_refresh_hint()
		if active and (ev is InputEventMouseButton or (ev is InputEventMouseMotion and ev.relative.length() > 2.0)):
			_show(false)

func _on_button(b: int, pressed: bool) -> void:
	if pressed:
		_show(true)
	match b:
		JOY_BUTTON_A:
			if pressed and not _a_down:
				_a_down = true
				_a_key = _a_advances_dialog()
				if _a_key:
					_key(KEY_SPACE, true)
				else:
					_mouse_button(true)
			elif not pressed and _a_down:
				_a_down = false
				if _a_key:
					_key(KEY_SPACE, false)
				else:
					_mouse_button(false)
		JOY_BUTTON_B:
			if pressed and ov.is_open():
				_tap(KEY_ESCAPE)
		JOY_BUTTON_X:
			_key(KEY_SPACE, pressed)
		JOY_BUTTON_Y:
			if pressed:
				_tap(KEY_ESCAPE if ov.current == "book" else KEY_R)
		JOY_BUTTON_BACK:
			if pressed:
				_tap(KEY_ESCAPE if ov.current == "journal" else KEY_J)
		JOY_BUTTON_START:
			if pressed:
				_tap(KEY_ESCAPE)
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			if pressed:
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
	var m := (stick.length() - DEAD) / (1.0 - DEAD)
	if m > 0.0 or dpad != Vector2.ZERO or absf(scroll) > DEAD:
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
	# stick derecho: rueda del ratón (listas largas del libro, el diario y el mercado)
	if active and absf(scroll) > DEAD:
		_scroll += delta * lerpf(4.0, 14.0, (absf(scroll) - DEAD) / (1.0 - DEAD))
		while _scroll >= 1.0:
			_scroll -= 1.0
			_wheel(scroll < 0.0)
	else:
		_scroll = 0.99   # el primer toque desplaza enseguida
	if active and p != _pos:
		_move_to(p)

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
		if _a_down:
			_a_down = false
			if not _a_key:
				_mouse_button(false)
	_refresh_hint()

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
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down and not _a_key else 0
	_pos = p
	where = p
	_sprite.position = p
	Input.parse_input_event(mm)

# de coordenadas del lienzo a coordenadas de la ventana (como main._click_at)
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
	if ov.is_open() or not ui.dialog_waiting():
		return false
	for b in _buttons():
		if b.get_global_rect().has_point(_pos):
			return false
	return true

## Botones visibles y activos de la capa que manda (la ventana abierta, o si no hay, la interfaz del juego).
func _buttons() -> Array:
	var out := []
	_collect(ov.root if ov.is_open() else ui.root, out)
	return out

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CanvasItem and not c.visible:
			continue
		if c is BaseButton and not c.disabled and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(c)
		_collect(c, out)

## Todo lo que se puede tocar, como rectángulos en el lienzo: botones, y si no hay ventana abierta,
## los frascos del estante, el caldero y la gata.
func _targets() -> Array:
	var out := []
	for b in _buttons():
		out.append(b.get_global_rect())
	if world == null or ov.is_open():
		return out
	var picks := [[world.cauldron, 0.6], [world.cat, 0.3]]
	for id in world.jars:
		picks.append([world.jars[id], 0.36])
	for pk in picks:
		var n: Node3D = pk[0]
		if not n.is_visible_in_tree():
			continue
		var w: Vector3 = n.global_position + Vector3(0, pk[1], 0)
		if world.camera.is_position_behind(w):
			continue
		out.append(Rect2(world.screen_pos(w) - Vector2(30, 30), Vector2(60, 60)))
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
	var order := func(c: Vector2) -> float: return roundf(c.y / 90.0) * 100000.0 + c.x
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
	if active or not Input.get_connected_joypads().is_empty():
		t = PAD_HINT
		if needs_gesture:
			t += "\n" + WEB_SOUND_HINT
	if t != _hint:
		_hint = t
		ov.set_pad_hint(t)
