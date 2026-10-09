extends SceneTree
## Writes the DOCE input map (every control of docs/GDD.md, keyboard + mouse and gamepad) into project.godot's
## [input] section. This table is the source of truth: edit it, then run
##   godot --headless --path . -s res://tools/input_map.gd
## Godot rewrites project.godot in its own format; the other sections are kept.
##
## Shared buttons are resolved in code (scripts/player/hero.gd):
##   Shift / pad B   "dodge" on a tap, "sprint" while held      LMB / pad X   "attack" on a tap, heavy when held
##   L3              "sprint_toggle": sprint until the stick is released

const DEADZONE := 0.25

## [action, physical keys, mouse buttons, joypad buttons, joypad axes [[axis, value]]]
const MAP := [
	["move_left", [KEY_A, KEY_LEFT], [], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]]],
	["move_right", [KEY_D, KEY_RIGHT], [], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]]],
	["move_forward", [KEY_W, KEY_UP], [], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]]],
	["move_back", [KEY_S, KEY_DOWN], [], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]]],
	["look_left", [], [], [], [[JOY_AXIS_RIGHT_X, -1.0]]],
	["look_right", [], [], [], [[JOY_AXIS_RIGHT_X, 1.0]]],
	["look_up", [], [], [], [[JOY_AXIS_RIGHT_Y, -1.0]]],
	["look_down", [], [], [], [[JOY_AXIS_RIGHT_Y, 1.0]]],
	["jump", [KEY_SPACE], [], [JOY_BUTTON_A], []],
	["dodge", [KEY_SHIFT], [], [JOY_BUTTON_B], []],
	["sprint", [KEY_SHIFT], [], [JOY_BUTTON_B], []],
	["sprint_toggle", [], [], [JOY_BUTTON_LEFT_STICK], []],
	["attack", [], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X], []],
	["guard", [], [MOUSE_BUTTON_RIGHT], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]]],
	["chain", [KEY_Q], [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]],
	["lock_on", [KEY_TAB], [MOUSE_BUTTON_MIDDLE], [JOY_BUTTON_RIGHT_STICK], []],
	["interact", [KEY_E], [], [JOY_BUTTON_Y], []],
	["pause", [KEY_ESCAPE, KEY_P], [], [JOY_BUTTON_START], []],
]


func _init() -> void:
	for row in MAP:
		var events: Array = []
		for k in row[1]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			events.append(e)
		for m in row[2]:
			var e := InputEventMouseButton.new()
			e.button_index = m
			events.append(e)
		for b in row[3]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			events.append(e)
		for a in row[4]:
			var e := InputEventJoypadMotion.new()
			e.axis = a[0]
			e.axis_value = a[1]
			events.append(e)
		for e in events:
			(e as InputEvent).device = -1 # any keyboard / mouse / controller, like actions made in the editor
		ProjectSettings.set_setting("input/" + String(row[0]), {"deadzone": DEADZONE, "events": events})
	var err := ProjectSettings.save()
	print("input_map: %d actions written to project.godot (%s)" % [MAP.size(), error_string(err)])
	quit(0 if err == OK else 1)
