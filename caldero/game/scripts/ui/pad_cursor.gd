extends CanvasLayer
class_name PadCursor
## Mando (Xbox y compatibles). El juego se juega con el ratón, así que el mando lleva su propio cursor, que mueve
## el ratón de Godot (los hovers, los tooltips y los clics en el escenario 3D funcionan igual), y botones que hacen
## de teclas:
##   stick izquierdo / cruceta: mover el cursor     A: tocar donde está el cursor (o avanzar el diálogo)
##   B: volver / cerrar (Esc)     X: Espacio (avanzar, remover)     Y: recetas (R)     Vista: diario (J)
##   Menú: ajustes (Esc)     LB / RB: saltar al objeto tocable anterior / siguiente     stick derecho: desplazar listas
## El cursor aparece al usar el mando y se esconde en cuanto se mueve el ratón.
## --- R6 UI: A también hace lo que dice el aviso de acción (PromptBrain: hablar, dar la poción, preparar, comprar...)
## cuando el cursor no está sobre algo tocable, o mientras está guardado: al caminar con la cruceta el cursor se guarda
## (se esconde) y vuelve al mover el stick o con LB / RB. Con las respuestas del diálogo a la vista, A sin cursor encima
## elige la primera; en un papel, su botón principal (Dormir, Siguiente...). X es la segunda acción del aviso (Espacio).
## Con el estante para elegir abierto: la cruceta elige, A la da, B vuelve.

const DEAD := 0.2            # zona muerta de los sticks
const SPEED := 1920.0        # píxeles por segundo con el stick a fondo (un ancho de pantalla)
const DPAD_STEP := 12.0      # un toque de la cruceta
const DPAD_SPEED := 480.0    # cruceta mantenida
const SNAP_DIST := 60.0      # al soltar el stick cerca de algo tocable, el cursor se acerca solo
const PAD_DEVICE := 77       # marca los eventos que inventa el mando (para no confundirlos con el ratón y el teclado)
const PAD_HINT := "A tap · B back · X next · Y recipes · View journal"   # --- R3 MERGE: dieta de texto
const WEB_SOUND_HINT := "Sound: click or press a key"   # --- R3 MERGE: dieta de texto

static var active := false          # el cursor del mando está a la vista (y el del sistema, escondido)
static var where := Vector2.ZERO    # dónde está, en coordenadas del lienzo (los tooltips lo usan)

var ui: GameUI
var ov: Overlays
var world: ShopWorld
var market: MarketWorld   # --- WORLD: el mercado (sus puestos son tocables cuando está a la vista)
var brew: BrewUI          # --- R3 BENCH: el banco del caldero (sus frascos y botones son tocables cuando está abierto)
var ball: BallUI          # --- R4 RAVEN: la bola de Krápido (sus tarjetas, su estante y cerrar, cuando está abierta)
var events_ui: EventUI    # --- R4 EVENTS: las tarjetas del evento (jurado, resultados) y el botón «Caldero»
var brain: PromptBrain    # --- R6 UI: los avisos de acción (A / X hacen lo que dicen)
var _parked := false      # --- R6 UI: el cursor guardado (escondido) mientras la cruceta la hace caminar
var _a_mode := ""         # --- R6 UI: qué hizo A al bajar: "space" (diálogo), "click" (tocar), "done" (otra cosa)
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
	var fresh := pressed and not active   # --- R6 UI: el primer botón tras usar el ratón o el teclado (el cursor recién aparece)
	if pressed:
		_show(true)
	match b:
		JOY_BUTTON_A:
			# --- R6 UI: A según lo que hay (ver _a_route): avanzar el diálogo, tocar donde está el cursor, o hacer el aviso
			if pressed and not _a_down:
				_a_down = true
				_a_mode = _a_route(fresh)
				_a_key = _a_mode == "space"
				if _a_mode == "space":
					_key(KEY_SPACE, true)
				elif _a_mode == "click":
					_mouse_button(true)
			elif not pressed and _a_down:
				_a_down = false
				if _a_mode == "space":
					_key(KEY_SPACE, false)
				elif _a_mode == "click":
					_mouse_button(false)
				_a_mode = ""
			# --- end R6 UI
		JOY_BUTTON_B:
			if pressed and ui != null and ui.picker_open():   # --- R6 UI: B vuelve del estante para elegir
				ui.close_picker()
			elif pressed and (ov.is_open() or _bench_open() or _ball_open()):   # --- R3 BENCH: B también cierra el banco (R4 RAVEN: y la bola)
				_tap(KEY_ESCAPE)
		# --- R6 UI: con el estante para elegir abierto, la cruceta elige (no mueve el cursor ni a ella)
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			if pressed and ui != null and (ui.picker_open() or _ball_waiting()):
				_tap({JOY_BUTTON_DPAD_LEFT: KEY_LEFT, JOY_BUTTON_DPAD_RIGHT: KEY_RIGHT, JOY_BUTTON_DPAD_UP: KEY_UP, JOY_BUTTON_DPAD_DOWN: KEY_DOWN}[b])
		# --- end R6 UI
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
				_park(false)   # --- R6 UI: LB / RB sacan el cursor guardado
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
	# --- WORLD: mientras se puede caminar, izquierda/derecha de la cruceta mueven a la alquimista (walker.gd)
	if Walker.dpad_walk:
		if dpad.x != 0.0 and active:
			_park(true)   # --- R6 UI: caminando con la cruceta el cursor se guarda (A hace el aviso de acción)
		dpad.x = 0.0
	# --- end WORLD
	if ui != null and (ui.picker_open() or _ball_waiting()):
		dpad = Vector2.ZERO   # --- R6 UI: la cruceta elige en el estante o en la bandeja de la bola (_on_button)
	var m := (stick.length() - DEAD) / (1.0 - DEAD)
	if m > 0.0 or dpad != Vector2.ZERO or absf(scroll) > DEAD:
		_show(true)
		_park(false)   # --- R6 UI: el stick (o la cruceta arriba / abajo) saca el cursor guardado
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
	_sprite.visible = on and not _parked   # --- R6 UI
	if not on:
		_parked = false   # --- R6 UI
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
			if _a_mode == "click":   # --- R6 UI: (antes: not _a_key)
				_mouse_button(false)
			_a_mode = ""
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
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down and _a_mode == "click" else 0   # --- R6 UI
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
	# --- R4 EVENTS: la tarjeta abierta del evento manda; sin tarjeta, el botón «Caldero» del HUD del evento
	if events_ui != null and not ov.is_open():
		var er: Control = events_ui.pad_root()
		if events_ui.modal_open():
			_collect(er, out)
			return out
		if er != null and not _bench_open() and not ui.dialog_open():
			_collect(er, out)
	# --- end R4 EVENTS
	# --- R3 BENCH: con el banco del caldero abierto (y sin ventana ni diálogo encima), sus frascos y botones
	if not ov.is_open() and _bench_open() and not ui.dialog_open():
		_collect(brew.root, out)
		_collect(ui.potion_panel, out)   # --- R6 UI: el estante del HUD (dar o presentar la poción sin cerrar el banco)
		return out
	# --- end R3 BENCH
	# --- R4 RAVEN: con la bola de Krápido abierta: sus tarjetas, las pociones de su estante y cerrar
	if not ov.is_open() and _ball_open() and not ui.dialog_open():
		_collect(ball.root, out)
		return out
	_collect(ov.root if ov.is_open() else ui.root, out)
	return out

# --- R3 BENCH
func _bench_open() -> bool:
	return brew != null and brew.is_open()
# --- end R3 BENCH

func _ball_open() -> bool:   # --- R4 RAVEN
	return ball != null and ball.is_open()

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
	if world == null or ov.is_open() or _bench_open() or _ball_open():   # --- R3 BENCH: el banco tapa la tienda (R4 RAVEN: y la bola)
		return out
	# --- WORLD: en el mercado, los puestos y la puerta de la tienda; en la tienda, también las estaciones.
	# Solo cuenta lo que está en pantalla (la tienda y el mercado son más anchos que ella).
	var in_market := market != null and market.visible
	var cam: Camera3D = market.camera if in_market else world.camera
	var picks := []
	if in_market:
		picks = market.pad_picks()
	else:
		picks = [[world.cauldron, 0.6], [world.cat, 0.3]]
		for id in world.jars:
			picks.append([world.jars[id], 0.36])
		picks.append_array(world.pad_picks())
	var view := get_viewport().get_visible_rect()
	# --- end WORLD
	for pk in picks:
		var n: Node3D = pk[0]
		if not n.is_visible_in_tree():
			continue
		var w: Vector3 = n.global_position + Vector3(0, pk[1], 0)
		if cam.is_position_behind(w):
			continue
		var sp := cam.unproject_position(w)
		if not view.has_point(sp):   # --- WORLD
			continue
		out.append(Rect2(sp - Vector2(30, 30), Vector2(60, 60)))
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

# --- R6 UI: A según lo que hay, y el cursor guardado ---------------------------------------------------------------
## Qué hace A: "space" (el diálogo se escribe o espera: avanza), "click" (toca donde está el cursor) o "done" (ya hizo
## otra cosa: el aviso de acción, la respuesta del diálogo, el botón principal del papel, la poción del estante...).
## fresh: el cursor apareció con este mismo botón (no apuntaba a nada todavía).
func _a_route(fresh: bool) -> String:
	var over := not fresh and not _parked and _over_target()
	if not over and not ov.is_open() and ui != null and ui.dialog_waiting():
		return "space"
	if not over:
		if ui != null and ui.picker_open():
			ui.call("_pick_confirm")
			return "done"
		if events_ui != null and not ov.is_open() and events_ui.modal_open():
			if events_ui.press_default():
				return "done"
		elif ov.is_open():
			if ov.press_default():
				return "done"
		elif ui != null and ui.choices_ready():
			ui.press_choice(0)
			return "done"
		elif _ball_waiting():
			_tap(KEY_ENTER)   # la bola con Graznido esperando: la poción elegida en la bandeja
			return "done"
		elif brain != null and brain.press("interact"):
			return "done"
	if _parked or fresh:
		_park(false)   # nada que hacer: primero se ve el cursor (el próximo A toca donde está)
		return "done"
	return "click"

## La bola abierta con Graznido esperando su poción (la cruceta elige en la bandeja y A se la da).
func _ball_waiting() -> bool:
	return _ball_open() and not ov.is_open() and ui != null and not ui.dialog_open() and ball.k != null \
		and ball.k.raven_waiting() and not Game.potions.is_empty()

## El cursor está sobre algo tocable (un botón, o un objeto o estación de la tienda o del mercado).
func _over_target() -> bool:
	for r in _targets():
		if (r as Rect2).grow(4.0).has_point(_pos):
			return true
	return false

## Guarda (esconde) el cursor del mando o lo vuelve a mostrar donde estaba. Guardado, el ratón virtual se va fuera de
## la pantalla: nada queda «debajo del cursor» (letreros de las estaciones, tooltips).
func _park(on: bool) -> void:
	if on == _parked:
		return
	_parked = on
	_sprite.visible = active and not on
	if not active:
		return
	if on:
		var mm := InputEventMouseMotion.new()
		_fill(mm, Vector2(-400, -400))
		mm.relative = Vector2.ZERO
		Input.parse_input_event(mm)
	else:
		_move_to(_pos)
# --- end R6 UI
