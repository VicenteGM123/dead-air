extends Node
## Global game state (autoload "Game"): phase, coins, nights, blessings, unit registry and input map.

signal coins_changed(value: int, delta: int)
signal phase_changed(phase: int)
signal message(text: String, sub: String, kind: String)
signal pharos_level_changed(level: int)
signal blessing_taken(id: String)
signal stats_changed

enum Phase { BOOT, TITLE, DAY, DUSK, NIGHT, DAWN, BLESSING, VICTORY, DEFEAT }

var args := {}
var main: Node = null
var phase := Phase.BOOT
var coins := 0
var night := 0 # current night number (1-based) while it lasts; nights survived = night once dawn comes
var pharos_level := 1
var blessings: Array[String] = []
var stats := {"kills": 0, "built": 0, "upgrades": 0, "coins_earned": 0, "cats": 0, "deaths": 0, "bolts": 0}
var paused := false
var time_scale_target := 1.0

# Unit registry: team 0 = Delos (hero, soldiers, buildings), team 1 = Nyx.
var units: Array = [[], []]

# References filled by main.gd
var island: Island = null
var hero: Node3D = null
var pharos: Node3D = null
var fx: Node3D = null
var projectiles: Node3D = null
var rig: Node3D = null
var hud: Node = null

var _hitstop_until := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.has_feature("web"):
		_parse_web_args()


func _parse_web_args() -> void:
	var q: Variant = JavaScriptBridge.eval("window.location.search", true)
	if q is String and (q as String).length() > 1:
		for part in (q as String).substr(1).split("&"):
			var kv := part.split("=", true, 1)
			args[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else "1"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()


func arg(key: String, default: Variant = null) -> Variant:
	return args.get(key, default)


func reset() -> void:
	coins = int(arg("coins", str(Data.START_COINS)))
	night = 0
	pharos_level = 1
	blessings.clear()
	for k in stats:
		stats[k] = 0
	units = [[], []]
	Engine.time_scale = 1.0
	time_scale_target = 1.0
	_hitstop_until = 0


func set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)


func is_night() -> bool:
	return phase == Phase.NIGHT


func add_coins(n: int) -> void:
	coins += n
	if n > 0:
		stats["coins_earned"] += n
	coins_changed.emit(coins, n)


func spend(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins, -n)
	return true


func say(text: String, sub: String = "", kind: String = "info") -> void:
	message.emit(text, sub, kind)


func has_blessing(id: String) -> bool:
	return blessings.has(id)


func take_blessing(id: String) -> void:
	if not blessings.has(id):
		blessings.append(id)
	blessing_taken.emit(id)


# --- modifiers from blessings ------------------------------------------------------------------------------

func building_hp_mult(type: String) -> float:
	var m := 1.0
	if has_blessing("athena"):
		m *= 1.3
	if type == "wall" and has_blessing("hephaestus"):
		m *= 1.6
	if type == "pharos" and has_blessing("hestia"):
		m *= 1.25
	return m


func income_bonus(type: String) -> int:
	var b := 0
	if (type == "farm" or type == "dock") and has_blessing("demeter"):
		b += 2
	if type == "house" and has_blessing("hestia"):
		b += 1
	return b


# --- unit registry -----------------------------------------------------------------------------------------

func register(u: Node3D, team: int) -> void:
	if not units[team].has(u):
		units[team].append(u)


func unregister(u: Node3D, team: int) -> void:
	units[team].erase(u)


func enemies_of(team: int) -> Array:
	return units[1 - team]


## Living units of `team` within radius (XZ distance, accounting for their size).
func query(team: int, pos: Vector3, radius: float, include_buildings: bool = true) -> Array:
	var out: Array = []
	for u in units[team]:
		if not is_instance_valid(u) or not u.alive:
			continue
		if not include_buildings and u.is_building:
			continue
		var d: float = Vector2(u.global_position.x - pos.x, u.global_position.z - pos.z).length() - u.radius
		if d <= radius:
			out.append(u)
	return out


func nearest(team: int, pos: Vector3, radius: float, filter: Callable = Callable()) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for u in units[team]:
		if not is_instance_valid(u) or not u.alive:
			continue
		if filter.is_valid() and not filter.call(u):
			continue
		var d: float = Vector2(u.global_position.x - pos.x, u.global_position.z - pos.z).length() - u.radius
		if d < best_d:
			best_d = d
			best = u
	return best


func enemy_count() -> int:
	var c := 0
	for u in units[1]:
		if is_instance_valid(u) and u.alive:
			c += 1
	return c


# --- feel --------------------------------------------------------------------------------------------------

## Freeze the world for a few frames on heavy hits.
func hitstop(seconds: float) -> void:
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(seconds * 1000.0))


func shake(amount: float) -> void:
	if rig and rig.has_method("add_trauma"):
		rig.add_trauma(amount)


func _process(_delta: float) -> void:
	if paused:
		return
	if Time.get_ticks_msec() < _hitstop_until:
		Engine.time_scale = 0.05
	else:
		Engine.time_scale = time_scale_target


# --- input -------------------------------------------------------------------------------------------------

func _key(action: String, keys: Array, mouse: Array = [], joy_buttons: Array = [], joy_axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for m in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(action, e)
	for b in joy_buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in joy_axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)


func _setup_input() -> void:
	_key("move_left", [KEY_A, KEY_LEFT], [], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_key("move_right", [KEY_D, KEY_RIGHT], [], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_key("move_up", [KEY_W, KEY_UP], [], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_key("move_down", [KEY_S, KEY_DOWN], [], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_key("attack", [KEY_J], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X])
	_key("bash", [KEY_K], [MOUSE_BUTTON_RIGHT], [JOY_BUTTON_Y])
	_key("dodge", [KEY_SPACE, KEY_SHIFT, KEY_L], [], [JOY_BUTTON_B])
	_key("power", [KEY_Q, KEY_R], [], [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_key("interact", [KEY_E, KEY_ENTER], [], [JOY_BUTTON_A])
	_key("pause", [KEY_ESCAPE, KEY_P], [], [JOY_BUTTON_START])
	_key("pick_1", [KEY_1])
	_key("pick_2", [KEY_2])
	_key("pick_3", [KEY_3])
