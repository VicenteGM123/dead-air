extends Control
## On-screen controls for touchscreens: a floating stick on the left half (writes Game.hero.touch_move) and
## round action buttons on the right that press the real input actions, plus a pause button. Only real touch
## events are read (never mouse), so it can't get in the way of mouse play on desktop.

const S := preload("res://scripts/ui/style.gd")

const STICK_R := 62.0
## action, icon, radius, centre offset from the bottom-right corner.
const BUTTONS := [
	{"action": "attack", "icon": "anchor", "r": 60.0, "at": Vector2(-112, -110), "label": "Atacar"},
	{"action": "dodge", "icon": "steam", "r": 37.0, "at": Vector2(-242, -78), "label": "Embestida"},
	{"action": "bash", "icon": "lens", "r": 37.0, "at": Vector2(-218, -204), "label": "Destello"},
	{"action": "power", "icon": "beam", "r": 37.0, "at": Vector2(-98, -250), "label": "Haz"},
	{"action": "interact", "icon": "tap", "r": 44.0, "at": Vector2(-372, -96), "label": "Usar"},
]

var ui: Node = null
var active := false
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _held := {} # touch index -> action
var _press_k := {} # action -> 0..1 visual press
var _use_k := 0.0
var _verb := "Usar"
var _progress := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in BUTTONS:
		_press_k[b["action"]] = 0.0


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not on:
		_release_all()
	var tw := S.tween(self)
	tw.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.25)


func _center(b: Dictionary) -> Vector2:
	return size + (b["at"] as Vector2)


func _pause_center() -> Vector2:
	return Vector2(size.x - 40.0, 40.0)


func _stick_home() -> Vector2:
	return Vector2(118.0, size.y - 118.0)


func _hero() -> Node:
	return Game.hero if Game.hero and is_instance_valid(Game.hero) else null


func _use_visible() -> bool:
	var h := _hero()
	return h != null and h.interact_target != null and is_instance_valid(h.interact_target)


func _input(e: InputEvent) -> void:
	if not active or not visible:
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			if t.position.distance_to(_pause_center()) < 34.0:
				get_viewport().set_input_as_handled()
				if ui:
					ui.call("open_pause")
				return
			for b in BUTTONS:
				if b["action"] == "interact" and not _use_visible():
					continue
				if t.position.distance_to(_center(b)) < float(b["r"]) * 1.18:
					_press(t.index, b["action"])
					get_viewport().set_input_as_handled()
					return
			if t.position.x < size.x * 0.5 and _stick_id < 0:
				_stick_id = t.index
				var m := STICK_R + 16.0
				_stick_origin = Vector2(clampf(t.position.x, m, size.x * 0.5 - m), clampf(t.position.y, m + 60.0, size.y - m))
				_set_stick(t.position)
				get_viewport().set_input_as_handled()
		else:
			if t.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				var h := _hero()
				if h:
					h.touch_move = Vector2.ZERO
			if _held.has(t.index):
				_release(t.index)
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _stick_id:
			_set_stick(d.position)
			get_viewport().set_input_as_handled()


func _set_stick(p: Vector2) -> void:
	var v := (p - _stick_origin) / STICK_R
	if v.length() > 1.0:
		# Drag the base along so the thumb never falls off the stick.
		_stick_origin = p - v.normalized() * STICK_R
		v = v.normalized()
	_stick_vec = v
	var h := _hero()
	if h:
		h.touch_move = v if v.length() > 0.12 else Vector2.ZERO


func _press(index: int, action: String) -> void:
	_held[index] = action
	Input.action_press(action)
	_press_k[action] = 1.0


func _release(index: int) -> void:
	var action: String = _held[index]
	_held.erase(index)
	if not _held.values().has(action):
		Input.action_release(action)


func _release_all() -> void:
	for i in _held.keys():
		_release(i)
	_held.clear()
	if _stick_id >= 0:
		_stick_id = -1
		_stick_vec = Vector2.ZERO
		var h := _hero()
		if h:
			h.touch_move = Vector2.ZERO


func _process(delta: float) -> void:
	if modulate.a <= 0.0:
		return
	var rd := S.rdelta(delta)
	for a in _press_k:
		var down := _held.values().has(a)
		_press_k[a] = move_toward(_press_k[a], 1.0 if down else 0.0, rd * 10.0)
	_use_k = move_toward(_use_k, 1.0 if _use_visible() else 0.0, rd * 5.0)
	var h := _hero()
	if h and _use_visible():
		var info: Dictionary = h.interact_target.call("interact_info") if h.interact_target.has_method("interact_info") else {}
		_verb = String(info.get("verb", "Usar"))
		_progress = float(info.get("progress", 0.0))
	queue_redraw()


func _draw() -> void:
	var h := _hero()
	# Stick.
	var base := _stick_origin if _stick_id >= 0 else _stick_home()
	var on := _stick_id >= 0
	draw_circle(base, STICK_R + 6.0, Color(S.INK, 0.16 if on else 0.1))
	draw_arc(base, STICK_R, 0.0, TAU, 48, Color(S.IVORY, 0.45 if on else 0.22), 2.0, true)
	for i in 4:
		var a := TAU * i / 4.0
		var d := Vector2(cos(a), sin(a))
		var tip := base + d * (STICK_R - 9.0)
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([tip + d * 5.0, tip + n * 5.0, tip - n * 5.0]), Color(S.IVORY, 0.3 if on else 0.16))
	var knob := base + _stick_vec * STICK_R
	draw_circle(knob, 28.0, Color(S.PANEL, 0.55 if on else 0.35))
	draw_arc(knob, 28.0, 0.0, TAU, 36, Color(S.GOLD if on else S.IVORY, 0.7 if on else 0.35), 2.0, true)
	# Buttons.
	for b in BUTTONS:
		var action: String = b["action"]
		var k := 1.0
		if action == "interact":
			k = _use_k
			if k <= 0.01:
				continue
		var c := _center(b)
		var r: float = b["r"]
		var p: float = _press_k[action]
		var rr := r * (1.0 - 0.06 * p)
		var ready := true
		var fill := 0.0
		if action == "power" and h:
			fill = clampf(h.favor / maxf(1.0, h.favor_max()), 0.0, 1.0)
			ready = fill >= 0.999
		draw_circle(c, rr + 2.0, Color(S.INK, 0.25 * k))
		draw_circle(c, rr, Color(S.PANEL, (0.42 + 0.25 * p) * k))
		var ring := Color(S.GOLD, (0.85 if p > 0.1 else 0.5) * k) if action != "power" or ready else Color(S.IVORY, 0.25 * k)
		draw_arc(c, rr, 0.0, TAU, 48, ring, 2.0, true)
		if action == "power":
			if fill > 0.0:
				draw_arc(c, rr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * fill, maxi(6, int(48 * fill)), Color(S.FIRE, 0.95), 3.5, true)
			if ready:
				var pulse := 0.5 + 0.5 * sin(S.now() * 3.5)
				draw_circle(c, rr + 9.0 + 3.0 * pulse, Color(S.FIRE, 0.12))
		if action == "interact" and _progress > 0.0:
			draw_arc(c, rr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * _progress, 40, Color(S.GOLD, 0.95 * k), 3.5, true)
		var isz := rr * (0.95 if action != "attack" else 0.9)
		var icol := Color(S.IVORY, 0.92 * k) if action != "power" or ready else Color(S.IVORY, 0.4 * k)
		Icons.draw(self, String(b["icon"]), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), icol)
		if action == "interact":
			var f := S.font(S.CINZEL, 2)
			S.draw_text(self, f, _verb.to_upper(), 14, c + Vector2(0, rr + 22.0), Color(S.GOLD, k), 1, 4)
	# Pause.
	var pc := _pause_center()
	draw_circle(pc, 24.0, Color(S.PANEL, 0.45))
	draw_arc(pc, 24.0, 0.0, TAU, 36, Color(S.IVORY, 0.45), 1.5, true)
	Icons.draw(self, "pause", Rect2(pc - Vector2(13, 13), Vector2(26, 26)), Color(S.IVORY, 0.9))
