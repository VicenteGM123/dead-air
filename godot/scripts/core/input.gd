# Keyboard / mouse / pointer lock / Xbox controller -> actions (port of src/core/input.js; GDD §16; rebindable).
# Per action: down(a), pressed(a) (went down this frame), released(a). Taps shorter than a frame are latched.
# Mouse: `mouse.dx/dy` (pixels this frame), `mouse.wheel` (notches this frame), lookDelta() -> radians with
# sensitivity / invertY applied (plus the pad's look, see below). options.holdToggle.{aim,sprint} = 'hold' | 'toggle'.
# move(out) -> { x: strafe right, y: forward } in -1..1: the keyboard's digital axes, else the left stick's analog ones.
# Pointer lock (Godot: Input.mouse_mode = MOUSE_MODE_CAPTURED): clicking while playing locks it (never required with
# test=1 or while playing with the pad). Losing the lock while playing (Esc while locked, the window losing focus, or
# anything else releasing the capture), or Esc when unlocked, pauses the game; Esc while paused (unlocked) resumes.
#
# GAMEPAD (scripts/core/gamepad.gd reads the hardware: first connected 'standard' pad, radial deadzones 0.15 / 0.12).
# It drives the SAME actions, so every system works unchanged (CoD Zombies layout):
#   LS move (analog speed) · L3 sprint (toggle while moving forward; ends when the stick leaves forward, on LT, RT or
#   when out of stamina) · RS look · LT aim (follows the hold/toggle option) · RT fire · A jump ·
#   X interact / buy (tap) and hold X for the hold interactions; X with no prompt = reload (a hold that started as a
#   reload turns into an interact hold when a prompt appears, so hold X keeps repairing windows) · B melee ·
#   Y next weapon (action 'weaponNext') · RB tube grenade (hold to cook) · LB Tiny Tele · D-pad left/right slots 1/2 ·
#   D-pad down swap shoulder · Menu / View pause.
#   Look: exponent curve (magnitude^1.9), yaw 3.3 / pitch 2.1 rad/s at options.padSensitivity 1, +55 % yaw boost
#   ramping in after 0.12 s held at the edge; invertY is shared with the mouse. Aim assist (options.aimAssist, pad
#   look only): friction on / near zombies and a gentle snap on the LT press (AimAssist in gamepad.gd), passed to the
#   player as lookDelta().snapYaw / snapPitch (not scaled by the ADS factor).
#   UI: while a menu shows (game.menu.mode) the pad drives menu.padButton(name) instead of the actions (D-pad and left
#   stick = directions with auto-repeat); game.ending.padButton(name) gets first pick while the ending runs. A button
#   used by a menu is ignored by gameplay until released. Start / View in play pause; losing the active pad while
#   playing with it pauses.
# device: 'kbm' | 'pad' = where the last deliberate input came from (emits input:device {device}); glyph() -> 'E' | 'X'
#   for the interact prompt. rumble(weak, strong, ms) (only while the pad is the device and options.rumble), wired to
#   weapon:fire (heavy guns: def.shake >= 0.1), player:hurt, weapon:grenade, big camera shakes (cam.shake >= 0.18
#   calls shakeRumble) and the boss beam (boss.gd). options.{padSensitivity, aimAssist, rumble} come from the menu.
#
# Godot glue (the DOM listeners of the JS): a helper Node ("InputHook", added under the Game node in init()) receives
# _input(event) and the window focus notifications. Key codes are the DOM KeyboardEvent.code strings ('KeyW',
# 'ShiftLeft', 'Digit1', 'Escape', 'ArrowUp' …: domCode() maps Godot's physical keycodes), mouse buttons are
# 'Mouse0' (left) 'Mouse1' (middle) 'Mouse2' (right) 'Mouse3' / 'Mouse4' (back / forward), so bindings and
# input.key(code) keep the JS values. Mouse deltas use InputEventMouseMotion.screen_relative (unscaled pixels, like
# movementX). The browser's asynchronous pointer lock is emulated: requestLock() captures the mouse at the next
# update() (pointerlockchange fires later in the browser too), Esc while locked releases it (the browser does that
# itself) and a capture lost by any other means is noticed in update(). UI surfaces that consume a key (the pause
# menu's Esc) must call get_viewport().set_input_as_handled() in their own _input (JS stopImmediatePropagation).
# Renames (SPEC §3.2): none.
# MP: while game.mpPaused (the MP pause card is an overlay over the running world) gameplay gets no input: `blocked`
#   is true, held actions release once (like losing the pointer lock), every action then reads not-down / not-pressed,
#   mouse and pad look / move are zero, and every key pressed while blocked (the one that hit RESUME included: the
#   card resumes before this hook sees the key) is ignored until released. Esc with mpPaused resumes. Rumble hooks
#   (player:hurt, weapon:fire) skip payloads whose `by` is another peer (RECONCILE R7); player:down rumbles (MP).
extends RefCounted

const GP = preload("res://scripts/core/gamepad.gd")
const BTN := GP.BTN
const BTN_NAME := GP.BTN_NAME

const BINDINGS := {
	"forward": ["KeyW", "ArrowUp"],
	"back": ["KeyS", "ArrowDown"],
	"left": ["KeyA", "ArrowLeft"],
	"right": ["KeyD", "ArrowRight"],
	"sprint": ["ShiftLeft", "ShiftRight"],
	"jump": ["Space"],
	"aim": ["Mouse2"],
	"fire": ["Mouse0"],
	"reload": ["KeyR"],
	"interact": ["KeyE"],
	"melee": ["KeyV", "Mouse3"],
	"grenade": ["KeyG"],
	"tactical": ["KeyQ"],
	"weapon1": ["Digit1"],
	"weapon2": ["Digit2"],
	"weaponNext": [],
	"shoulder": ["KeyC"],
	"pause": ["Escape"],
}

# plain one-button pad actions (aim, sprint and X are handled on their own)
const PAD_SIMPLE := [
	["jump", BTN.A], ["melee", BTN.B], ["weaponNext", BTN.Y], ["grenade", BTN.RB], ["tactical", BTN.LB],
	["fire", BTN.RT], ["weapon1", BTN.LEFT], ["weapon2", BTN.RIGHT], ["shoulder", BTN.DOWN],
]
const NAV_DIRS := ["up", "down", "left", "right"]
const NAV_DELAY := 0.38     # s before a held direction repeats in menus
const NAV_REPEAT := 0.11    # s between repeats
const LOOK_EXP := 1.9
const LOOK_YAW := 3.3       # rad/s at full deflection, padSensitivity 1
const LOOK_PITCH := 2.1
const EDGE := 0.97          # stick magnitude that counts as "at the edge"
const EDGE_DELAY := 0.12
const EDGE_RAMP := 0.35
const EDGE_BOOST := 0.55
const SNAP_TIME := 0.12
const SPRINT_FWD := 0.35

const BASE_SENS := 0.0022 # radians per pixel at sensitivity 1
const WORLD := ["playing", "down"]

var game
var bindings := {}
var options := {"sensitivity": 1.0, "invertY": false, "holdToggle": {"aim": "hold", "sprint": "hold"},
	"padSensitivity": 1.0, "aimAssist": true, "rumble": true}
var mouse := {"dx": 0.0, "dy": 0.0, "wheel": 0, "x": 0.0, "y": 0.0}
var locked := false
var device := "kbm"
var pad
var assist
var _codes := {}          # Set of held DOM codes
var _tapLatch := {}       # Set
var _relLatch := {}       # Set
var _state := {}
var _acc := {"dx": 0.0, "dy": 0.0, "wheel": 0}
var _codeToActions := {}
# pad -> action state (rebuilt every frame)
var _padHeld := {}
var _padPress := {}       # Set
var _padRel := {}         # Set
var _padMove := {"x": 0.0, "y": 0.0}
var _padLook := {"yaw": 0.0, "pitch": 0.0, "snapYaw": 0.0, "snapPitch": 0.0}
var _swallow := {}        # pad buttons a menu used: ignored by gameplay until released (Set)
var _xMode = null         # 'interact' | 'reload' while X is held
var _sprintLatch := false
var _aimLatch := false
var _edgeT := 0.0
var _snap := {"yaw": 0.0, "pitch": 0.0, "t": 0.0}
var _nav := {"up": -1.0, "down": -1.0, "left": -1.0, "right": -1.0}
var _stickDir := {"up": false, "down": false, "left": false, "right": false}
var _cursorHidden := false
var _hook: Node = null     # the Node receiving Godot input events (the JS window/canvas listeners)
var _lockPending := false  # requestLock() in flight (the browser locks asynchronously)
var _weaponDefs = null
var blocked := false       # MP: game.mpPaused (see the header)
var _swallowCodes := {}    # MP: keys pressed while blocked, ignored until released (Set)

func _init(g) -> void:
	game = g
	for a in BINDINGS:
		bindings[a] = BINDINGS[a].duplicate()
	pad = GP.Gamepad.new()
	assist = GP.AimAssist.new(g)
	for a in bindings:
		_state[a] = {"down": false, "pressed": false, "released": false, "toggled": false}
	_rebuild()


# Receives the engine's input events and window focus changes for the Input system (engine glue).
class InputHook extends Node:
	var sys
	func _init(s) -> void:
		sys = s
		name = "InputHook"
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _input(event: InputEvent) -> void:
		sys._onEvent(event)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			sys._onBlur()


func init() -> void:
	if game is Node:
		_hook = InputHook.new(self)
		game.add_child(_hook)
	pad.init()
	var ev = game.events
	if ev != null:
		# pause / menus silence the motors at once (game over lets the lethal hit's short rumble finish)
		ev.on("state", func(p) -> void:
			if p != null and (p.get("to") == "paused" or p.get("to") == "menu"):
				pad.stopRumble()
				_snap.t = 0.0)
		ev.on("weapon:fire", func(e) -> void: _fireRumble(e))
		ev.on("player:hurt", func(e) -> void:
			if not _mine(e):
				return
			var d := maxf(0.0, GP.U.num(e.get("dmg")) if e is Dictionary else 0.0)
			rumble(minf(0.75, 0.3 + d / 300.0), minf(0.7, 0.2 + d / 220.0), 170.0))
		ev.on("player:down", func(_e) -> void: rumble(0.8, 0.9, 420.0))   # MP only (solo never goes down)
		ev.on("weapon:grenade", func(e) -> void:
			var p = game.player
			if not (e is Dictionary) or e.get("pos") == null or p == null:
				return
			var k := maxf(0.0, 1.0 - p.pos.distance_to(DAU.v3(e.pos)) / 18.0)
			if k > 0.0:
				rumble(0.55 * k, 0.6 * k, 300.0))

func bind(action: String, codes: Array) -> void:
	bindings[action] = codes.duplicate()
	if not _state.has(action):
		_state[action] = {"down": false, "pressed": false, "released": false, "toggled": false}
	_rebuild()

func _rebuild() -> void:
	_codeToActions.clear()
	for a in bindings:
		for c in bindings[a]:
			if not _codeToActions.has(c):
				_codeToActions[c] = []
			_codeToActions[c].append(a)

func down(a: String) -> bool:
	var s = _state.get(a)
	return s != null and s.down

func pressed(a: String) -> bool:
	var s = _state.get(a)
	return s != null and s.pressed

func released(a: String) -> bool:
	var s = _state.get(a)
	return s != null and s.released

func key(code: String) -> bool:
	return _codes.has(code)

# Clears this frame's pressed flag (a system that used the press can stop others from reacting to it).
func consume(a: String) -> void:
	var s = _state.get(a)
	if s != null:
		s.pressed = false

# Movement axes: keyboard (digital) when any move key is held, else the left stick (analog, magnitude <= 1).
# `out` (optional Dictionary {x, y}) is filled and returned, like the JS out object.
func move(out = null) -> Dictionary:
	if out == null:
		out = {"x": 0.0, "y": 0.0}
	var kx := (1.0 if down("right") else 0.0) - (1.0 if down("left") else 0.0)
	var ky := (1.0 if down("forward") else 0.0) - (1.0 if down("back") else 0.0)
	if kx != 0.0 or ky != 0.0:
		out.x = kx
		out.y = ky
		return out
	out.x = _padMove.x
	out.y = _padMove.y
	return out

# Look delta in radians for this frame: { yaw, pitch } (positive yaw = turn left, positive pitch = look up).
# snapYaw / snapPitch: the pad aim-assist snap (applied as is, outside the ADS look scale).
func lookDelta(out = null) -> Dictionary:
	if out == null:
		out = {"yaw": 0.0, "pitch": 0.0}
	var k: float = BASE_SENS * float(options.sensitivity)
	var L := _padLook
	out.yaw = -float(mouse.dx) * k + L.yaw
	out.pitch = -float(mouse.dy) * k * (-1.0 if options.invertY else 1.0) + L.pitch
	out.snapYaw = L.snapYaw
	out.snapPitch = L.snapPitch
	return out

# Interact prompt key for the HUD.
func glyph() -> String:
	return "X" if device == "pad" else "E"

# Synthetic mouse movement (debug.mouseDelta / harness).
func injectMouse(dx: float, dy: float) -> void:
	_acc.dx += dx
	_acc.dy += dy

func requestLock() -> void:
	if GP.U.truthy(game.params.get("test")) or locked or _hook == null or device == "pad":
		return
	# the browser locks asynchronously (pointerlockchange later): capture at the next update()
	_lockPending = true

func exitLock() -> void:
	_lockPending = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if locked:
		_onLockChange()

func clear() -> void:
	_codes.clear()
	for a in _state:
		var s: Dictionary = _state[a]
		if s.down:
			_relLatch[a] = true
		s.toggled = false
	_acc.dx = 0.0
	_acc.dy = 0.0
	_acc.wheel = 0

# ---------------------------------------------------------------------------------------------- rumble
func rumble(weak: float, strong: float, ms: float) -> void:
	if not options.rumble or device != "pad" or not pad.connected:
		return
	pad.rumble(weak, strong, ms)

# cam.shake(amount, duration) hook: only big moments (explosions, stomps, boss hits) rumble.
func shakeRumble(amount: float, duration = null) -> void:
	if not (amount >= 0.18):
		return
	var a := minf(0.8, amount)
	rumble(a * 0.6, a * 0.7, minf(0.4, maxf(0.1, GP.U.orf(duration, 0.2))) * 1000.0)

func _defs() -> Variant:
	if _weaponDefs == null and ResourceLoader.exists("res://scripts/game/weapon_defs.gd"):
		var s = load("res://scripts/game/weapon_defs.gd")
		if s != null:
			var d = s.get("WEAPON_DEFS")  # static var of weapon_defs.gd
			_weaponDefs = d if d is Dictionary else {}
	return _weaponDefs

# RECONCILE R7: a payload caused by another peer's player carries its id in `by` (absent in solo).
func _mine(e) -> bool:
	if not (e is Dictionary) or e.get("by") == null:
		return true
	var n = game.get("net")
	return n == null or not n.inGame or int(e.by) == int(n.localId)

func _fireRumble(e) -> void:
	if not (e is Dictionary) or device != "pad" or not _mine(e):
		return
	var defs = _defs()
	var def = defs.get(e.get("weaponId")) if defs is Dictionary else null
	var sh = GP.U.g(def, "shake") if def != null else null
	if not ((sh is float or sh is int) and sh >= 0.1):
		return  # light guns (MP7, M16, Zapper) stay silent
	rumble(0.15 + sh * 0.9, sh * 1.1, 60.0 + sh * 280.0)

# ---------------------------------------------------------------------------------------------- per frame
# Called first every frame: latch events into per-frame action state.
func update(dt: float = 0.0) -> void:
	_syncLock()
	_pollPad(dt)
	# MP pause: entering it releases every held key once (their key-ups are swallowed: no second release)
	var mpPause: bool = game.get("mpPaused") == true
	if mpPause != blocked:
		blocked = mpPause
		if blocked:
			for c in _codes:
				_swallowCodes[c] = true
			clear()
			_dropPadLatches()
	var PH := _padHeld
	var PP := _padPress
	var PR := _padRel
	for a in _state:
		var s: Dictionary = _state[a]
		var mode = options.holdToggle.get(a)
		var tapped := _tapLatch.has(a)
		var padHeld: bool = PH.get(a, false)
		if mode == "toggle":
			if tapped:
				s.toggled = not s.toggled
			s.pressed = tapped or PP.has(a)
			var was: bool = s.down
			s.down = s.toggled or padHeld  # the pad keeps its own toggle latches (aim option, L3 sprint)
			s.released = was and not s.down
		else:
			var held := _held(a) or padHeld
			s.pressed = tapped or PP.has(a)
			s.released = (_relLatch.has(a) or PR.has(a)) and not held
			s.down = held or tapped
	_tapLatch.clear()
	_relLatch.clear()
	mouse.dx = _acc.dx
	mouse.dy = _acc.dy
	mouse.wheel = _acc.wheel
	_acc.dx = 0.0
	_acc.dy = 0.0
	_acc.wheel = 0
	if blocked:
		_blockActions()
	pad.updateRumble()
	_updateCursor()

# MP pause: nothing reaches gameplay this frame (the one-frame releases latched by clear() stay visible).
func _blockActions() -> void:
	for a in _state:
		var s: Dictionary = _state[a]
		s.down = false
		s.pressed = false
		s.toggled = false
	mouse.dx = 0.0
	mouse.dy = 0.0
	mouse.wheel = 0
	_resetPadActions()

func _held(a: String) -> bool:
	for c in bindings[a]:
		if _codes.has(c):
			return true
	return false

func _setDevice(d: String) -> void:
	if device == d:
		return
	device = d
	if d != "pad":
		pad.stopRumble()
	if game.events != null:
		game.events.emit("input:device", {"device": d})

# Hide the mouse cursor over the game while playing with the pad unlocked.
func _updateCursor() -> void:
	var hide: bool = device == "pad" and WORLD.has(game.state) and not locked
	if hide == _cursorHidden or _hook == null:
		return
	_cursorHidden = hide
	if hide and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif not hide and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resetPadActions() -> void:
	var H := _padHeld
	for a in H:
		H[a] = false
	_padMove.x = 0.0
	_padMove.y = 0.0
	var L := _padLook
	L.yaw = 0.0
	L.pitch = 0.0
	L.snapYaw = 0.0
	L.snapPitch = 0.0

# Releases every pad-held action (menus took over, pad lost).
func _dropPadLatches() -> void:
	for a in _padHeld:
		if _padHeld[a]:
			_padRel[a] = true
	_sprintLatch = false
	_aimLatch = false
	_xMode = null
	_edgeT = 0.0
	_snap.t = 0.0

func _pollPad(dt: float) -> void:
	var g = game
	_padPress.clear()
	_padRel.clear()
	pad.poll()
	if pad.justDisconnected:
		_dropPadLatches()
		_swallow.clear()
		if device == "pad" and WORLD.has(g.state):
			g.pause()
	if not pad.connected:
		_resetPadActions()
		return
	if pad.active:
		_setDevice("pad")
	var sw := _swallow
	for i in sw.keys():
		if not pad.btn[i].down:
			sw.erase(i)

	# UI surfaces first (the ending, then menus)
	if _padUi(dt):
		_dropPadLatches()
		for i in pad.btn.size():
			if pad.btn[i].down:
				sw[i] = true
		_resetPadActions()
		return
	var st = g.state
	if (_pr(BTN.MENU) or _pr(BTN.VIEW)) and WORLD.has(st):
		for i in pad.btn.size():
			if pad.btn[i].down:
				sw[i] = true
		_dropPadLatches()
		_resetPadActions()
		g.pause()
		return
	_padActions(dt)

func _dn(i: int) -> bool:
	return pad.btn[i].down and not _swallow.has(i)

func _pr(i: int) -> bool:
	return pad.btn[i].pressed and not _swallow.has(i)

func _rl(i: int) -> bool:
	return pad.btn[i].released

func _padActions(dt: float) -> void:
	var g = game
	var H := _padHeld
	var PP := _padPress
	var PR := _padRel
	for a in H:
		H[a] = false
	for pair in PAD_SIMPLE:
		var a: String = pair[0]
		var i: int = pair[1]
		H[a] = _dn(i)
		if _pr(i):
			PP[a] = true
		if _rl(i):
			PR[a] = true
	var p = g.player

	# LT aim: hold, or its own latch when the aim option is 'toggle'
	if options.holdToggle.aim == "toggle":
		if _pr(BTN.LT):
			_aimLatch = not _aimLatch
			PP["aim"] = true
			if not _aimLatch:
				PR["aim"] = true
		H["aim"] = _aimLatch
	else:
		_aimLatch = false
		H["aim"] = _dn(BTN.LT)
		if _pr(BTN.LT):
			PP["aim"] = true
		if _rl(BTN.LT):
			PR["aim"] = true

	# left stick (analog move). The sticks count only while the pad is the device: a resting pad with a drifting
	# stick never creeps the player of a keyboard/mouse session (a push past 0.35 or any press switches at once).
	var ls: Dictionary = pad.ls
	var analog := device == "pad"
	_padMove.x = ls.x if analog else 0.0
	_padMove.y = ls.y if analog else 0.0

	# L3 sprint: CoD toggle while moving forward
	if _pr(BTN.L3):
		_sprintLatch = not _sprintLatch or ls.y > SPRINT_FWD
		if _sprintLatch:
			PP["sprint"] = true
	if _sprintLatch and (ls.m < 0.2 or ls.y < 0.2 or H.aim or PP.has("fire") or (p != null and GP.U.truthy(p.get("_exhausted")))):
		_sprintLatch = false
		PR["sprint"] = true
	H["sprint"] = _sprintLatch

	# X: interact / buy when something is focused (last frame's focus), else reload
	var focus: bool = g.interact != null and g.interact.get("current") != null
	if _pr(BTN.X):
		_xMode = "interact" if focus else "reload"
		PP[_xMode] = true
	if _dn(BTN.X) and _xMode != null:
		if _xMode == "reload" and focus:
			PR["reload"] = true
			_xMode = "interact"  # hold X keeps repairing
		H[_xMode] = true
	if _rl(BTN.X) and _xMode != null:
		PR[_xMode] = true
		_xMode = null

	_padLookUpdate(dt, PP.has("aim") and H.aim)

func _padLookUpdate(dt: float, aimPressed: bool) -> void:
	var g = game
	var o := options
	var rs: Dictionary = pad.rs
	var L := _padLook
	L.yaw = 0.0
	L.pitch = 0.0
	L.snapYaw = 0.0
	L.snapPitch = 0.0
	var world: bool = WORLD.has(g.state)
	if rs.m > 0.0 and world and device == "pad":
		_edgeT = _edgeT + dt if rs.m >= EDGE else 0.0
		var e := clampf((_edgeT - EDGE_DELAY) / EDGE_RAMP, 0.0, 1.0)
		var boost := 1.0 + EDGE_BOOST * e * e * (3.0 - 2.0 * e)
		var curve: float = pow(rs.m, LOOK_EXP) / rs.m  # scales the direction vector by m^exp
		var sens := clampf(GP.U.orf(o.padSensitivity, 1.0), 0.1, 3.0)
		var fr: float = assist.friction() if o.aimAssist else 1.0
		L.yaw = -rs.x * curve * LOOK_YAW * sens * boost * fr * dt
		L.pitch = rs.y * curve * LOOK_PITCH * sens * fr * dt * (-1.0 if o.invertY else 1.0)
	else:
		_edgeT = 0.0
	# gentle snap on the LT press (only when ADS starts: in toggle mode the press that ends ADS does not snap)
	var S := _snap
	if aimPressed and world and o.aimAssist and g.player != null and not g.player.ads:
		var s = assist.snap()
		if s != null:
			S.yaw = s.yaw
			S.pitch = s.pitch
			S.t = SNAP_TIME
	if S.t > 0.0 and dt > 0.0:
		var f := minf(1.0, dt / S.t)
		L.snapYaw = S.yaw * f
		L.snapPitch = S.pitch * f
		S.yaw -= L.snapYaw
		S.pitch -= L.snapPitch
		S.t -= dt

# Menus / the ending own the pad. Returns true when a menu surface shows (gameplay gets nothing this frame).
func _padUi(dt: float) -> bool:
	var g = game
	var end = null
	if g.ending != null and GP.U.truthy(g.ending.get("active")) and g.ending.has_method("padButton"):
		end = g.ending
	var menu = null
	if g.menu != null and GP.U.truthy(g.menu.get("mode")) and g.menu.has_method("padButton"):
		menu = g.menu
	if end == null and menu == null:
		_resetNav()
		return false
	var send := func(name: String, i: int) -> bool:
		var used := false
		if end != null:
			used = GP.U.truthy(end.padButton(name))
		if not used and menu != null:
			var r = menu.padButton(name)
			used = not (r is bool and r == false)
		if used and i >= 0:
			_swallow[i] = true
		return used
	# face / shoulder / system buttons (edges)
	for i in pad.btn.size():
		if i >= BTN.UP and i <= BTN.RIGHT:
			continue
		if i == BTN.HOME or not _pr(i):
			continue
		if not send.call(BTN_NAME[i], i) and menu == null and (i == BTN.MENU or i == BTN.VIEW) and WORLD.has(g.state):
			_swallow[i] = true
			g.pause()
			return true
	if menu == null:
		_resetNav()
		return false
	# directions: D-pad or the left stick (dominant axis, hysteresis), auto-repeat while held
	var ls: Dictionary = pad.ls
	var SD := _stickDir
	var ax := absf(ls.x)
	var ay := absf(ls.y)
	var on := func(dir: String, v: float, other: float) -> bool:
		return v > 0.35 if SD[dir] else (v > 0.55 and v > other)
	SD.up = on.call("up", ls.y, ax)
	SD.down = on.call("down", -ls.y, ax)
	SD.left = on.call("left", -ls.x, ay)
	SD.right = on.call("right", ls.x, ay)
	var dpad := {"up": BTN.UP, "down": BTN.DOWN, "left": BTN.LEFT, "right": BTN.RIGHT}
	for dir in NAV_DIRS:
		var held: bool = _dn(dpad[dir]) or SD[dir]
		var N := _nav
		if not held:
			N[dir] = -1.0
			continue
		if N[dir] < 0.0:
			N[dir] = 0.0
			send.call(dir, -1)
			continue
		var before: float = N[dir]
		N[dir] += dt
		if N[dir] >= NAV_DELAY:
			var k0 := floorf((before - NAV_DELAY) / NAV_REPEAT)
			var k1 := floorf((N[dir] - NAV_DELAY) / NAV_REPEAT)
			if before < NAV_DELAY or k1 > k0:
				send.call(dir, -1)
	return true

func _resetNav() -> void:
	_nav.up = -1.0
	_nav.down = -1.0
	_nav.left = -1.0
	_nav.right = -1.0

# ---------------------------------------------------------------------------------------------- keyboard / mouse
# Every engine input event (InputHook._input): the JS keydown/keyup/mousedown/mouseup/mousemove/wheel listeners.
func _onEvent(event: InputEvent) -> void:
	if event is InputEventKey:
		var code := domCode(event)
		if code != "":
			_onKey(code, event.pressed, event.echo)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_acc.wheel += 1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
				_setDevice("kbm")
			return
		var n := _mouseIndex(mb.button_index)
		if n < 0:
			return
		if mb.pressed:
			# the JS listened to mousedown on the canvas only: a press on a UI control (a menu button) is not
			# the game's; while locked every click is the canvas' (pointer lock targets it)
			if locked or not _overUi():
				_onMouseDown(n)
		else:
			_onButton("Mouse%d" % n, false)
	elif event is InputEventMouseMotion:
		_onMove(event as InputEventMouseMotion)

# The pointer is over a GUI control that takes mouse presses (a DOM element over the canvas in the JS build).
func _overUi() -> bool:
	if _hook == null or not _hook.is_inside_tree():
		return false
	var vp := _hook.get_viewport()
	var c: Control = vp.gui_get_hovered_control() if vp != null else null
	return c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP

# DOM MouseEvent.button of a Godot mouse button (-1: not a button the game knows).
static func _mouseIndex(b: int) -> int:
	match b:
		MOUSE_BUTTON_LEFT:
			return 0
		MOUSE_BUTTON_MIDDLE:
			return 1
		MOUSE_BUTTON_RIGHT:
			return 2
		MOUSE_BUTTON_XBUTTON1:
			return 3
		MOUSE_BUTTON_XBUTTON2:
			return 4
	return -1

func _onKey(code: String, isDown: bool, isRepeat: bool) -> void:
	if isDown and isRepeat:
		return
	if isDown:
		_setDevice("kbm")
	var wasLocked := locked
	if code == "Escape" and isDown:
		_onEscape()
	_onButton(code, isDown)
	# the browser itself releases the pointer lock on Esc (then pointerlockchange pauses)
	if code == "Escape" and isDown and wasLocked:
		exitLock()

func _onButton(code: String, isDown: bool) -> void:
	if blocked or _swallowCodes.has(code):
		# MP pause card up (or the key went down while it was): ignored until released
		if isDown:
			_swallowCodes[code] = true
		else:
			_swallowCodes.erase(code)
			_codes.erase(code)
		return
	var acts = _codeToActions.get(code)
	if isDown:
		_codes[code] = true
	else:
		_codes.erase(code)
	if acts == null:
		return
	for a in acts:
		if isDown:
			_tapLatch[a] = true
		else:
			_relLatch[a] = true

func _onMouseDown(button: int) -> void:
	_setDevice("kbm")
	if blocked:
		_onButton("Mouse%d" % button, true)   # MP pause: no pointer-lock request, swallowed
		return
	var st = game.state
	if (st == "playing" or st == "down") and not locked and not GP.U.truthy(game.params.get("test")):
		requestLock()
		return  # the locking click is not a shot
	_onButton("Mouse%d" % button, true)

func _onMove(e: InputEventMouseMotion) -> void:
	mouse.x = e.position.x
	mouse.y = e.position.y
	var rel: Vector2 = e.screen_relative
	if absf(rel.x) + absf(rel.y) > 3.0:
		_setDevice("kbm")
	# Look only while locked; unlocked test sessions can drag-look with the right button.
	if locked or (GP.U.truthy(game.params.get("test")) and (e.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0):
		_acc.dx += rel.x
		_acc.dy += rel.y

# window 'blur': drop every held key; the browser also drops the pointer lock.
func _onBlur() -> void:
	clear()
	if locked:
		exitLock()

# The pending lock request lands, and a capture changed by anyone else is noticed (pointerlockchange).
func _syncLock() -> void:
	if _lockPending:
		_lockPending = false
		if not locked and device != "pad" and _hook != null and not GP.U.truthy(game.params.get("test")):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) != locked:
		_onLockChange()

func _onLockChange() -> void:
	var was := locked
	locked = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if locked:
		_cursorHidden = false
	if was and not locked:
		clear()
		var st = game.state
		if st == "playing" or st == "down":
			game.pause()

func _onEscape() -> void:
	if locked:
		return  # the browser releases the lock; _onLockChange pauses
	if game.get("mpPaused") == true:
		game.resume()   # MP pause card (when the card itself did not take the key)
		return
	var st = game.state
	if st == "playing" or st == "down":
		game.pause()
	elif st == "paused":
		game.resume()

# ---------------------------------------------------------------------------------------------- DOM key codes
# KeyboardEvent.code of a Godot key event (physical key = layout independent, like the DOM code). "" = unknown.
static func domCode(e: InputEventKey) -> String:
	var k: int = e.physical_keycode
	if k == KEY_NONE:
		k = e.keycode
	if k >= KEY_A and k <= KEY_Z:
		return "Key" + char(k)
	if k >= KEY_0 and k <= KEY_9:
		return "Digit" + char(k)
	if k >= KEY_F1 and k <= KEY_F12:
		return "F%d" % (k - KEY_F1 + 1)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return "Numpad%d" % (k - KEY_KP_0)
	var right: bool = e.location == KEY_LOCATION_RIGHT
	match k:
		KEY_SHIFT:
			return "ShiftRight" if right else "ShiftLeft"
		KEY_CTRL:
			return "ControlRight" if right else "ControlLeft"
		KEY_ALT:
			return "AltRight" if right else "AltLeft"
		KEY_META:
			return "MetaRight" if right else "MetaLeft"
		KEY_SPACE:
			return "Space"
		KEY_ESCAPE:
			return "Escape"
		KEY_TAB:
			return "Tab"
		KEY_ENTER:
			return "Enter"
		KEY_KP_ENTER:
			return "NumpadEnter"
		KEY_BACKSPACE:
			return "Backspace"
		KEY_DELETE:
			return "Delete"
		KEY_INSERT:
			return "Insert"
		KEY_HOME:
			return "Home"
		KEY_END:
			return "End"
		KEY_PAGEUP:
			return "PageUp"
		KEY_PAGEDOWN:
			return "PageDown"
		KEY_UP:
			return "ArrowUp"
		KEY_DOWN:
			return "ArrowDown"
		KEY_LEFT:
			return "ArrowLeft"
		KEY_RIGHT:
			return "ArrowRight"
		KEY_CAPSLOCK:
			return "CapsLock"
		KEY_MINUS:
			return "Minus"
		KEY_EQUAL:
			return "Equal"
		KEY_BRACKETLEFT:
			return "BracketLeft"
		KEY_BRACKETRIGHT:
			return "BracketRight"
		KEY_BACKSLASH:
			return "Backslash"
		KEY_SEMICOLON:
			return "Semicolon"
		KEY_APOSTROPHE:
			return "Quote"
		KEY_QUOTELEFT:
			return "Backquote"
		KEY_COMMA:
			return "Comma"
		KEY_PERIOD:
			return "Period"
		KEY_SLASH:
			return "Slash"
		KEY_KP_ADD:
			return "NumpadAdd"
		KEY_KP_SUBTRACT:
			return "NumpadSubtract"
		KEY_KP_MULTIPLY:
			return "NumpadMultiply"
		KEY_KP_DIVIDE:
			return "NumpadDivide"
		KEY_KP_PERIOD:
			return "NumpadDecimal"
		KEY_PAUSE:
			return "Pause"
		KEY_PRINT:
			return "PrintScreen"
		KEY_MENU:
			return "ContextMenu"
	return ""
