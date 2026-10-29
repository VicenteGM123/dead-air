extends Node
class_name Walker
## Hace caminar a un personaje (Actor) por un "carril" del suelo, de izquierda a derecha: con A/D o las flechas,
## con la cruceta del mando (izquierda / derecha) o yendo a un punto (un clic en el suelo o en una estación).
## El carril es una línea quebrada en el plano XZ: la z sale de interpolar según la x (así rodea muebles).
## Las estaciones son puntos del carril con una zona [x0, x1]: al entrar en la zona se emite station_reached.
## La usan los escenarios (la tienda y la calle: scripts/world/shop_world.gd y street_world.gd).
## --- SS SEED: copiado de Midnight Cauldron (scripts/world/walker.gd). Lo nuevo (los controles de Secondhand Stars:
## «pad: d-pad / stick walk»): también camina con el stick izquierdo del mando (eje x, zona muerta STICK_DEAD).

signal station_reached(id: String)   # entró en la zona de una estación (caminando, con un clic o enviada por código)
signal station_left(id: String)      # salió de esa zona
signal arrived(x: float)             # llegó al destino de go_to() / go_station()
signal _done(gen: int, ok: bool)

## true mientras la protagonista puede caminar con la cruceta: PadCursor deja entonces izquierda/derecha para caminar.
## --- SS SEED: y también el stick izquierdo (PadCursor no mueve su cursor con él mientras esto sea true).
static var dpad_walk := false
const STICK_DEAD := 0.35   # --- SS SEED: zona muerta del stick para caminar

var actor: Actor
var lane: Array = []            # [Vector2(x, z), ...] de izquierda a derecha
var stations := {}              # id -> {"x": float, "face": int (-1 izq., 1 der.), "zone": Vector2(x0, x1), "name": String}
var speed := 2.7                # m/s con el teclado o la cruceta
var auto_speed := 3.1           # m/s yendo a un punto
var can_walk: Callable          # () -> bool: si el jugador puede moverla ahora (lo pone main.gd)
var frozen := false             # true: no la mueve ni la coloca (manda otra animación, p. ej. salir por la puerta)
var x := 0.0
var current := ""               # estación en cuya zona está ("" = ninguna)
var _target := 0.0
var _target_face := 0
var _has_target := false
var _gen := 0
var _was_moving := false

func setup(a: Actor, points: Array, start_x: float, face_dir := 1) -> void:
	actor = a
	lane = points
	teleport(start_x, face_dir)

func x_min() -> float:
	return lane[0].x

func x_max() -> float:
	return lane[lane.size() - 1].x

## La z del carril para una x (interpolada entre sus puntos).
func lane_z(px: float) -> float:
	if lane.is_empty():
		return 0.0
	if px <= lane[0].x:
		return lane[0].y
	for i in range(1, lane.size()):
		var b: Vector2 = lane[i]
		if px <= b.x:
			var a: Vector2 = lane[i - 1]
			return lerpf(a.y, b.y, (px - a.x) / maxf(0.0001, b.x - a.x))
	return lane[lane.size() - 1].y

func point(px: float) -> Vector3:
	return Vector3(px, 0.0, lane_z(px))

# --- R3 WORLD3: se camina a la misma velocidad por los tramos inclinados del carril (p. ej. el paso hacia el fondo
# para rodear un mueble): la velocidad es por metro recorrido, no por metro de x.
## Cuánto avanza x por cada metro caminado en el tramo donde está (dir > 0: hacia la derecha; dir < 0: hacia la izquierda).
func _dx_per_m(px: float, dir: float) -> float:
	if lane.size() < 2 or dir == 0.0:
		return 1.0
	for i in range(1, lane.size()):
		var a: Vector2 = lane[i - 1]
		var b: Vector2 = lane[i]
		if (dir > 0.0 and px < b.x) or (dir < 0.0 and px <= b.x) or i == lane.size() - 1:
			var dx := b.x - a.x
			var seg_len := a.distance_to(b)
			if dx <= 0.0001 or seg_len <= 0.0001:
				return 1.0
			return clampf(dx / seg_len, 0.08, 1.0)
	return 1.0
# --- end R3 WORLD3

## La pone en un punto del carril sin caminar.
func teleport(px: float, face_dir := 0) -> void:
	_cancel()
	x = clampf(px, x_min(), x_max())
	_place()
	if face_dir != 0:
		actor.face(face_dir)
	actor.set_walking(false)
	_was_moving = false
	_update_station()

## Camina hasta una x del carril. Devuelve true al llegar, false si la interrumpen (el jugador camina, u otro go_to).
func go_to(px: float, face_dir := 0) -> bool:
	_cancel()
	px = clampf(px, x_min(), x_max())
	if absf(px - x) < 0.04:
		x = px
		_place()
		if face_dir != 0:
			actor.face(face_dir)
		_update_station()
		arrived.emit(x)
		return true
	_gen += 1
	var my := _gen
	_target = px
	_target_face = face_dir
	_has_target = true
	var ok := false
	while true:
		var r: Array = await _done
		if r[0] == my:
			ok = r[1]
			break
	return ok

## Camina hasta el punto de una estación y se gira hacia ella.
func go_station(id: String) -> bool:
	if not stations.has(id):
		return false
	var s: Dictionary = stations[id]
	return await go_to(s["x"], s.get("face", 0))

func at_station(id: String) -> bool:
	return current == id

func station_at(px: float) -> String:
	for id in stations:
		var z: Vector2 = stations[id]["zone"]
		if px >= z.x and px <= z.y:
			return id
	return ""

func is_walking() -> bool:
	return _was_moving

## Se detiene donde está (cancela un go_to pendiente).
func stop() -> void:
	_cancel()
	if actor:
		actor.set_walking(false)
	_was_moving = false

func _cancel() -> void:
	if _has_target:
		_has_target = false
		_done.emit(_gen, false)

func _place() -> void:
	if actor:
		actor.position = Vector3(x, 0.0, lane_z(x))

func _update_station() -> void:
	var now := station_at(x)
	if now != current:
		var old := current
		current = now
		if old != "":
			station_left.emit(old)
		if now != "":
			station_reached.emit(now)

func _input_dir() -> float:
	var d := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d += 1.0
	for j in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(j, JOY_BUTTON_DPAD_LEFT):
			d -= 1.0
		if Input.is_joy_button_pressed(j, JOY_BUTTON_DPAD_RIGHT):
			d += 1.0
		# --- SS SEED: el stick izquierdo (eje x) también camina
		var ax := Input.get_joy_axis(j, JOY_AXIS_LEFT_X)
		if absf(ax) > STICK_DEAD:
			d += signf(ax)
		# --- end SS SEED
	return clampf(d, -1.0, 1.0)

func _process(delta: float) -> void:
	if actor == null or lane.size() < 2:
		return
	var allowed := can_walk.is_valid() and bool(can_walk.call())
	dpad_walk = allowed
	if frozen:
		return
	var dir := _input_dir() if allowed else 0.0
	var moving := false
	if dir != 0.0:
		_cancel()
		var old := x
		x = clampf(x + dir * speed * delta * _dx_per_m(x, dir), x_min(), x_max())   # --- R3 WORLD3
		actor.face(1 if dir > 0.0 else -1)
		moving = absf(x - old) > 0.0001
	elif _has_target:
		var d := _target - x
		var step := auto_speed * delta * _dx_per_m(x, signf(d))   # --- R3 WORLD3
		actor.face(1 if d > 0.0 else -1)
		if absf(d) <= step:
			x = _target
			_has_target = false
			_place()
			if _target_face != 0:
				actor.face(_target_face)
			actor.set_walking(false)
			_was_moving = false
			_update_station()
			_done.emit(_gen, true)
			arrived.emit(x)
			return
		x += signf(d) * step
		moving = true
	_place()
	if moving != _was_moving:
		actor.set_walking(moving)
		_was_moving = moving
	_update_station()
