# Xbox controller device layer (port of src/core/gamepad.js: Gamepad API "standard" mapping) + gamepad-only aim
# assist. Input (scripts/core/input.gd) owns the action mapping; this file only reads the hardware, shapes the sticks
# and drives the rumble motors.
#
# Gamepad (input.pad)
#   poll()        every frame: the pad list is read fresh each call (_list(): Godot's connected joypads mapped to the
#                 web "standard" layout below; tests may replace it through Gamepad.listOverride), the first connected
#                 'standard' pad is used (the one in use is kept while it stays connected). Godot's joy_connection
#                 signal only flags a rescan.
#   connected, id, index, justConnected, justDisconnected (this frame)
#   ls = { x, y, m }   left stick after a RADIAL deadzone (0.15) rescaled to 0..1 (x right, y forward/up, m magnitude)
#   rs = { x, y, m }   right stick, radial deadzone 0.12 (same shaping; the look curve lives in Input)
#   btn[i] = { down, pressed, released, value }   i = BTN.*; triggers use value hysteresis (0.30 on / 0.18 off)
#   active        true when this frame had deliberate pad input (a press, a stick past 0.35, a trigger past 0.3)
#   rumble(weak, strong, ms)   queues a dual-rumble effect. The mixer plays the max of the active effects in short
#                 chunks (<= 90 ms, re-issued while anything is active), so overlapping cues never cancel each other.
#                 The actuator is Input.start_joy_vibration (JoyActuator below).
#   stopRumble()  drops every queued effect (pause, game over).
# AimAssist (input.assist) — used only while the pad drives the look:
#   friction()    look-rate multiplier: 0.58 (0.5 in ADS) while the crosshair is on a zombie's hitbox (weapons.aimHit,
#                 the boss screen counts), easing from 0.8 to 1 in a small bubble around a zombie, else 1.
#   snap()        on the LT press: the living zombie whose chest is nearest the crosshair inside an 8 degree cone
#                 (<= 28 m, in line of sight) -> { yaw, pitch } = 55 % of the way there (Input spreads it over
#                 0.12 s), else null. Subtle on purpose.
#
# Godot mapping (engine glue): Godot's SDL layout (JoyButton / JoyAxis) is mapped onto the web "standard" indices so
# BTN / BTN_NAME stay the JS ones: A B X Y = JOY_BUTTON_A/B/X/Y, LB/RB = LEFT/RIGHT_SHOULDER, LT/RT = the trigger axes
# (value 0..1), VIEW = BACK, MENU = START, L3/R3 = LEFT/RIGHT_STICK, D-pad = DPAD_*, HOME = GUIDE. "standard" =
# Input.is_joy_known(device) (the pad has an SDL mapping). Axes 0..3 = left x/y, right x/y (+y down, like the web).
# Renames (SPEC §3.2): none. Gamepad.down/pressed/released keep their JS names (no Object built-in collision).

const BTN := {"A": 0, "B": 1, "X": 2, "Y": 3, "LB": 4, "RB": 5, "LT": 6, "RT": 7, "VIEW": 8, "MENU": 9, "L3": 10, "R3": 11, "UP": 12, "DOWN": 13, "LEFT": 14, "RIGHT": 15, "HOME": 16}
const BTN_NAME := ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "back", "start", "l3", "r3", "up", "down", "left", "right", "home"]
const NBTN := 17
const DZ_MOVE := 0.15
const DZ_LOOK := 0.12
const DZ_OUTER := 0.05      # full deflection reads 1 even on worn sticks / diagonals
const TRIG_ON := 0.3
const TRIG_OFF := 0.18
const ACTIVE_STICK := 0.35
const CHUNK := 0.09         # s per rumble chunk

# web standard button index -> Godot JoyButton (-1: a trigger axis, read from TRIGGER_AXIS)
const GODOT_BUTTON := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
	JOY_BUTTON_RIGHT_SHOULDER, -1, -1, JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_GUIDE]
const TRIGGER_AXIS := {6: JOY_AXIS_TRIGGER_LEFT, 7: JOY_AXIS_TRIGGER_RIGHT}

# Radial deadzone with rescaling: direction kept, magnitude remapped from [dz, 1 - outer] to [0, 1]. `out` is a
# Dictionary {x, y, m} (reference type: filled in place, like the JS out object) and returned.
static func radial(x: float, y: float, dz: float, out: Dictionary) -> Dictionary:
	return U.radial(x, y, dz, out)

# Small shared helpers (inner classes cannot call the outer script's static functions unqualified).
class U:
	static func radial(x: float, y: float, dz: float, out: Dictionary) -> Dictionary:
		var m := sqrt(x * x + y * y)
		if not (m > dz):
			out.x = 0.0
			out.y = 0.0
			out.m = 0.0
			return out
		var r := minf(1.0, (m - dz) / (1.0 - dz - DZ_OUTER))
		out.x = (x / m) * r
		out.y = (y / m) * r
		out.m = r
		return out

	# Number.isFinite(v) ? v : 0
	static func num(v) -> float:
		if v is float or v is int:
			var f := float(v)
			return f if is_finite(f) else 0.0
		return 0.0

	# JS truthiness (!!v)
	static func truthy(v) -> bool:
		if v == null:
			return false
		if v is bool:
			return v
		if v is int or v is float:
			return v != 0 and not is_nan(float(v))
		if v is String or v is StringName:
			return v != ""
		return true

	# JS `v || d` for numbers (0 / NaN / null / missing -> d).
	static func orf(v, d: float) -> float:
		if v == null or not (v is float or v is int):
			return d
		var f := float(v)
		return d if f == 0.0 or is_nan(f) else f

	# o.k for a Dictionary or an Object (null when missing).
	static func g(o, k: String) -> Variant:
		if o is Dictionary:
			return o.get(k)
		if o is Object:
			return o.get(k)
		return null


# The vibration actuator of one Godot joypad (the web GamepadHapticActuator 'dual-rumble' effect).
class JoyActuator extends RefCounted:
	var device := 0
	func _init(dev: int) -> void:
		device = dev
	func playEffect(_type: String, params: Dictionary) -> void:
		Input.start_joy_vibration(device, clampf(float(params.weakMagnitude), 0.0, 1.0), clampf(float(params.strongMagnitude), 0.0, 1.0), float(params.duration) / 1000.0)
	func reset() -> void:
		Input.stop_joy_vibration(device)


class Gamepad extends RefCounted:
	# Test hook (engine glue for the headless tests that override navigator.getGamepads in the JS build): when valid,
	# called instead of reading Godot's joypads; returns the web-style list [{index, id, connected, mapping, axes:[],
	# buttons:[{pressed, value}] | [number], vibrationActuator?}] (null holes allowed).
	static var listOverride: Callable = Callable()

	var connected := false
	var id := ""
	var index := -1
	var justConnected := false
	var justDisconnected := false
	var active := false
	var ls := {"x": 0.0, "y": 0.0, "m": 0.0}
	var rs := {"x": 0.0, "y": 0.0, "m": 0.0}
	var btn: Array = []
	var _gp = null
	var _rescan := true
	var _fx: Array = []          # queued rumble effects { w, s, end } (seconds, performance clock)
	var _rum := {"w": 0.0, "s": 0.0, "end": 0.0}
	var rumbleCount := 0         # effects actually sent to the actuator (tests)
	var _actuators := {}         # Godot device -> JoyActuator

	func _init() -> void:
		for i in NBTN:
			btn.append({"down": false, "pressed": false, "released": false, "value": 0.0})

	func init() -> void:
		var flag := func(_device: int, _connected: bool) -> void:
			_rescan = true
		Input.joy_connection_changed.connect(flag)

	# performance.now() / 1000
	static func _now() -> float:
		return DAU.nowMs() / 1000.0

	func _list() -> Array:
		if Gamepad.listOverride.is_valid():
			var l = Gamepad.listOverride.call()
			return l if l is Array else []
		var out: Array = []
		for dev in Input.get_connected_joypads():
			var d := int(dev)
			while out.size() <= d:
				out.append(null)
			var buttons: Array = []
			for i in NBTN:
				var gb: int = GODOT_BUTTON[i]
				if gb < 0:
					var v := Input.get_joy_axis(d, TRIGGER_AXIS[i])
					buttons.append({"pressed": v > 0.5, "value": v})
				else:
					var pr := Input.is_joy_button_pressed(d, gb)
					buttons.append({"pressed": pr, "value": 1.0 if pr else 0.0})
			if not _actuators.has(d):
				_actuators[d] = JoyActuator.new(d)
			out[d] = {
				"index": d, "id": Input.get_joy_name(d), "connected": true,
				"mapping": "standard" if Input.is_joy_known(d) else "",
				"axes": [Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y),
					Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)],
				"buttons": buttons,
				"vibrationActuator": _actuators[d],
			}
		return out

	static func _ok(p) -> bool:
		return p is Dictionary and U.truthy(p.get("connected")) and p.get("mapping") == "standard"

	# The pad in use while it stays connected, else the first connected 'standard' pad.
	func _pick(list: Array) -> Variant:
		var cur = list[index] if index >= 0 and index < list.size() else null
		if _ok(cur):
			return cur
		for i in list.size():
			var p = list[i]
			if _ok(p):
				return p
		return null

	func poll() -> void:
		var gp = _pick(_list())
		var was := connected
		connected = gp != null
		justConnected = not was and connected
		justDisconnected = was and not connected
		_rescan = false
		_gp = gp
		active = false
		if gp == null:
			index = -1
			ls.x = 0.0; ls.y = 0.0; ls.m = 0.0
			rs.x = 0.0; rs.y = 0.0; rs.m = 0.0
			for b in btn:
				b.released = b.down
				b.down = false
				b.pressed = false
				b.value = 0.0
			return
		index = int(gp.get("index", 0))
		var gid = gp.get("id")
		id = str(gid) if U.truthy(gid) else "gamepad"
		var ax: Array = gp.get("axes", []) if gp.get("axes") is Array else []
		# standard mapping: axes 0/1 left stick, 2/3 right stick, +y = down -> flip to up-positive
		U.radial(U.num(ax[0] if ax.size() > 0 else 0.0), -U.num(ax[1] if ax.size() > 1 else 0.0), DZ_MOVE, ls)
		U.radial(U.num(ax[2] if ax.size() > 2 else 0.0), -U.num(ax[3] if ax.size() > 3 else 0.0), DZ_LOOK, rs)
		var bs: Array = gp.get("buttons", []) if gp.get("buttons") is Array else []
		var act: bool = ls.m > ACTIVE_STICK or rs.m > ACTIVE_STICK
		for i in NBTN:
			var b: Dictionary = btn[i]
			var raw = bs[i] if i < bs.size() else null
			var value := 0.0
			var down := false
			if raw != null:
				if raw is Dictionary:
					value = U.num(raw.get("value"))
					down = U.truthy(raw.get("pressed"))
				else:
					value = U.num(raw)
					down = value > 0.5
			if i == BTN.LT or i == BTN.RT:
				down = value > TRIG_ON or (b.down and value > TRIG_OFF) or (down and value == 0.0)
			b.pressed = down and not b.down
			b.released = not down and b.down
			b.down = down
			b.value = value
			if b.pressed and i != BTN.HOME:
				act = true
		active = act

	func down(i: int) -> bool:
		return btn[i].down
	func pressed(i: int) -> bool:
		return btn[i].pressed
	func released(i: int) -> bool:
		return btn[i].released

	# ---------------------------------------------------------------------------------------------- rumble
	func rumble(weak: float, strong: float, ms: float) -> void:
		if not (ms > 0.0):
			return
		var now := _now()
		var fx := _fx
		for i in range(fx.size() - 1, -1, -1):
			if fx[i].end <= now:
				fx.remove_at(i)
		if fx.size() >= 12:
			fx.pop_front()
		fx.append({"w": clampf(weak, 0.0, 1.0), "s": clampf(strong, 0.0, 1.0), "end": now + minf(5.0, ms / 1000.0)})

	func stopRumble() -> void:
		_fx.clear()
		_rum.end = 0.0
		_rum.w = 0.0
		_rum.s = 0.0
		var act = _actuator()
		if act != null and act.has_method("reset"):
			act.reset()

	func _actuator() -> Variant:
		var gp = _gp
		var act = gp.get("vibrationActuator") if gp is Dictionary else null
		return act if act is Object and act.has_method("playEffect") else null

	# Mixer: called once per frame by Input (after poll).
	func updateRumble() -> void:
		var fx := _fx
		if fx.is_empty():
			return
		var now := _now()
		var w := 0.0
		var s := 0.0
		var end := 0.0
		for i in range(fx.size() - 1, -1, -1):
			var e: Dictionary = fx[i]
			if e.end <= now:
				fx.remove_at(i)
				continue
			if e.w > w:
				w = e.w
			if e.s > s:
				s = e.s
			if e.end > end:
				end = e.end
		if fx.is_empty():
			return
		var R := _rum
		var due: bool = now >= R.end - 0.015 or absf(w - R.w) > 0.04 or absf(s - R.s) > 0.04
		if not due:
			return
		var act = _actuator()
		var dur := minf(CHUNK, end - now)
		R.w = w
		R.s = s
		R.end = now + dur
		if act == null or dur <= 0.005:
			return
		act.playEffect("dual-rumble", {"startDelay": 0, "duration": floorf(dur * 1000.0 + 0.5), "weakMagnitude": w, "strongMagnitude": s})
		rumbleCount += 1


# ------------------------------------------------------------------------------------------------ aim assist
const SNAP_CONE := 8.0 * PI / 180.0
const SNAP_RANGE := 28.0
const SNAP_AMOUNT := 0.55
const FRICTION_ON := 0.58
const FRICTION_ON_ADS := 0.5
const FRICTION_NEAR := 0.8
const BUBBLE_RANGE := 32.0
const SNAP_HEIGHTS := [0.66, 0.8]  # fractions of the zombie's height tried for line of sight (chest, upper chest)


class AimAssist extends RefCounted:
	var game

	func _init(g) -> void:
		game = g

	func _onTarget(hit) -> bool:
		if hit == null:
			return false
		var kind = U.g(hit, "kind")
		if kind == "zombie":
			var z = U.g(hit, "z")
			return z != null and not U.truthy(U.g(z, "dead"))
		var entry = U.g(hit, "entry")
		return kind == "shootable" and entry != null and U.g(entry, "id") == "boss_baron"

	func friction() -> float:
		var g = game
		var W = g.weapons
		var p = g.player
		var Z = g.zombies
		if W == null or p == null or U.g(W, "aimDir") == null:
			return 1.0
		if _onTarget(U.g(W, "aimHit")) and float(U.orf(U.g(W, "aimDist"), 0.0)) < BUBBLE_RANGE + 8.0:
			return FRICTION_ON_ADS if U.truthy(p.ads) else FRICTION_ON
		var list = U.g(Z, "alive")
		if list == null or list.is_empty() or U.g(W, "aimOrigin") == null:
			return 1.0
		var o: Vector3 = W.aimOrigin
		var d: Vector3 = W.aimDir
		var best := 1.0
		for i in list.size():
			var z = list[i]
			if z == null or U.truthy(U.g(z, "dead")) or U.g(z, "pos") == null:
				continue
			var zp: Vector3 = z.pos
			var sc := U.orf(U.g(z, "scale"), 1.0)
			var lo := zp.y + 0.2
			var hi := zp.y + U.orf(U.g(z, "height"), 1.6) * sc
			var cy := (lo + hi) * 0.5
			var t := (zp.x - o.x) * d.x + (cy - o.y) * d.y + (zp.z - o.z) * d.z
			if t < 1.0 or t > BUBBLE_RANGE:
				continue
			var px := o.x + d.x * t
			var py := o.y + d.y * t
			var pz := o.z + d.z * t
			var hd := maxf(0.0, Vector2(px - zp.x, pz - zp.z).length() - U.orf(U.g(z, "radius"), 0.36) * sc)
			var vd := lo - py if py < lo else (py - hi if py > hi else 0.0)
			var dist := Vector2(hd, vd).length()
			var bubble := 0.4 + t * 0.012
			if dist < bubble:
				best = minf(best, FRICTION_NEAR + (1.0 - FRICTION_NEAR) * (dist / bubble))
		return best

	func snap() -> Variant:
		var g = game
		var W = g.weapons
		var p = g.player
		var Z = g.zombies
		var list = U.g(Z, "alive")
		if W == null or p == null or list == null or list.is_empty() or g.camera == null:
			return null
		var cam: Camera3D = g.camera
		var _o: Vector3 = cam.global_position if cam.is_inside_tree() else cam.position
		var yaw: float = p.yaw
		var pitch: float = p.pitch
		var _d := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		var best = null
		var bestAng := SNAP_CONE
		var bestDist := 0.0
		for i in list.size():
			var z = list[i]
			if z == null or U.truthy(U.g(z, "dead")) or U.g(z, "pos") == null:
				continue
			var zp: Vector3 = z.pos
			var sc := U.orf(U.g(z, "scale"), 1.0)
			var _v := Vector3(zp.x, zp.y + U.orf(U.g(z, "height"), 1.6) * sc * 0.66, zp.z) - _o
			var dist := _v.length()
			if dist < 1.5 or dist > SNAP_RANGE:
				continue
			var ang := acos(clampf(_v.dot(_d) / dist, -1.0, 1.0))
			if ang < bestAng:
				bestAng = ang
				best = z
				bestDist = dist
		if best == null:
			return null
		# line of sight to the chest, else the upper chest (a zombie behind a counter): the first thing along the ray
		# must be that zombie
		var bsc := U.orf(U.g(best, "scale"), 1.0)
		var bp: Vector3 = best.pos
		var ok := false
		var dist2 := bestDist
		var v := Vector3.ZERO
		for k in SNAP_HEIGHTS:
			v = Vector3(bp.x, bp.y + U.orf(U.g(best, "height"), 1.6) * bsc * float(k), bp.z) - _o
			dist2 = v.length()
			if not (W is Object and W.has_method("traceRay")):
				ok = true
				break
			var hit = W.traceRay(_o, v / dist2, dist2 + 0.6, {"zombies": true, "shootables": false, "level": true, "blockingOnly": true})
			if hit != null and U.g(hit, "kind") == "zombie" and is_same(U.g(hit, "z"), best):
				ok = true
				break
		if not ok:
			return null
		var ty := atan2(-v.x, -v.z)
		var tp := asin(clampf(v.y / dist2, -1.0, 1.0))
		var dy := atan2(sin(ty - yaw), cos(ty - yaw))
		var dp := tp - pitch
		if absf(dy) + absf(dp) < 0.008:
			return null
		return {"yaw": dy * SNAP_AMOUNT, "pitch": dp * SNAP_AMOUNT, "z": best}
