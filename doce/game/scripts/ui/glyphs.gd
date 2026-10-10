extends Control
## Input glyphs: remembers the last device used (keyboard+mouse or gamepad) and draws the matching caps for an
## action — [E] on keyboard, (Y) on a pad. Instances refresh by themselves when the device changes.
## The table follows the controls in docs/GDD.md (gamepad names are Xbox-style: A B X Y, LB RB LT RT, L3 R3).

const S := preload("res://scripts/ui/style.gd")

static var device := "kb" # "kb" | "pad"
static var revision := 0

var action := ""
var fixed_device := "" # forces a device (controls screen)
var cap_h := 24.0
var color := S.IVORY
var custom: Array = [] # explicit caps instead of an action
var _caps: Array = []
var _rev := -1


static func set_device(d: String) -> void:
	if d != device:
		device = d
		revision += 1


## Tracks the device from raw input. Touch-emulated mouse events (device -1) are ignored.
static func observe(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		set_device("kb")
	elif e is InputEventMouseButton and e.pressed and e.device != InputEvent.DEVICE_ID_EMULATION:
		set_device("kb")
	elif e is InputEventJoypadButton and e.pressed:
		set_device("pad")
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.55:
		set_device("pad")


## How to trigger `action` on `dev`. Each cap is [kind, text]: "key" (rounded square), "pad" (round face
## button), "pill" (shoulder / menu button), "icon" (vector icon) or "word" (plain small text).
static func caps_for(act: String, dev: String = "") -> Array:
	if dev == "":
		dev = device
	if dev == "pad":
		match act:
			"move": return [["icon", "stick_l"]]
			"camera", "look": return [["icon", "stick_r"]]
			"sprint": return [["pill", "L3"]]
			"jump": return [["pad", "A"]]
			"dodge": return [["pad", "B"]]
			"attack": return [["pad", "X"]]
			"heavy": return [["word", "mantener"], ["pad", "X"]]
			"guard", "parry", "shield": return [["pill", "LT"]]
			"chain", "spear", "throw": return [["pill", "RT"]]
			"lock", "lock_on": return [["pill", "R3"]]
			"interact", "grab", "pet", "wrestle": return [["pad", "Y"]]
			"accept": return [["pad", "A"]]
			"back": return [["pad", "B"]]
			"pause": return [["pill", "Start"]]
			"navigate": return [["icon", "dpad"]]
		return []
	match act:
		"move": return [["key", "W"], ["key", "A"], ["key", "S"], ["key", "D"]]
		"camera", "look": return [["icon", "mouse"]]
		"sprint": return [["word", "mantener"], ["key", "Shift"]]
		"jump": return [["key", "Espacio"]]
		"dodge": return [["key", "Shift"]]
		"attack": return [["icon", "mouse_l"]]
		"heavy": return [["word", "mantener"], ["icon", "mouse_l"]]
		"guard", "parry", "shield": return [["icon", "mouse_r"]]
		"chain", "spear", "throw": return [["key", "Q"]]
		"lock", "lock_on": return [["key", "Tab"]]
		"interact", "grab", "pet", "wrestle": return [["key", "E"]]
		"accept": return [["key", "Intro"]]
		"back": return [["key", "Esc"]]
		"pause": return [["key", "Esc"]]
		"navigate": return [["icon", "arrows"]]
	return []


static func cap_width(cap: Array, h: float) -> float:
	match cap[0]:
		"pad", "icon":
			return h
		"word":
			var fw := S.font(S.ITALIC)
			return fw.get_string_size(cap[1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.62)).x + 2.0
		_:
			var f := S.font(S.CINZEL_BOLD)
			var fs := int(h * (0.5 if cap[0] == "key" else 0.44))
			var tw := f.get_string_size(cap[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			return maxf(h, tw + h * (0.62 if cap[0] == "key" else 0.8))


## Draws one cap in `r` (height = r.size.y).
static func draw_cap(ci: CanvasItem, cap: Array, r: Rect2, col: Color, bg_alpha: float = 0.6) -> void:
	var h := r.size.y
	var kind: String = cap[0]
	var text: String = cap[1]
	match kind:
		"icon":
			Icons.draw(ci, text, r.grow(-h * 0.04), col)
			return
		"word":
			var fw := S.font(S.ITALIC)
			var fsw := int(h * 0.62)
			var yw := r.position.y + (h + fw.get_ascent(fsw) - fw.get_descent(fsw)) * 0.5
			ci.draw_string_outline(fw, Vector2(r.position.x, yw), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsw, 4, Color(S.INK, 0.4 * col.a))
			ci.draw_string(fw, Vector2(r.position.x, yw), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsw, Color(col, col.a * 0.85))
			return
		"pad":
			var c := r.get_center()
			ci.draw_circle(c, h * 0.5, Color(S.PANEL, bg_alpha))
			ci.draw_arc(c, h * 0.5 - 0.75, 0.0, TAU, 32, Color(col, 0.85 * col.a), 1.5, true)
		_:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(S.PANEL, bg_alpha)
			sb.border_color = Color(col, 0.8 * col.a)
			sb.set_border_width_all(1)
			sb.border_width_bottom = 2
			sb.set_corner_radius_all(int(h * (0.22 if kind == "key" else 0.5)))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, r)
	var f := S.font(S.CINZEL_BOLD)
	var fs := int(h * (0.5 if kind == "key" else (0.5 if kind == "pad" else 0.44)))
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var y := r.position.y + (h + asc - desc) * 0.5 - h * 0.02
	ci.draw_string(f, Vector2(r.position.x + (r.size.x - tw) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Width of a row of caps (with the gaps used by draw_caps).
static func caps_width(caps: Array, h: float) -> float:
	var w := 0.0
	for i in caps.size():
		w += cap_width(caps[i], h) + (h * 0.18 if i > 0 else 0.0)
	return w


## Draws a row of caps starting at `pos` (top-left); returns the width used.
static func draw_caps(ci: CanvasItem, caps: Array, pos: Vector2, h: float, col: Color, bg_alpha: float = 0.6) -> float:
	var x := pos.x
	for i in caps.size():
		if i > 0:
			x += h * 0.18
		var cw := cap_width(caps[i], h)
		draw_cap(ci, caps[i], Rect2(x, pos.y, cw, h), col, bg_alpha)
		x += cw
	return x - pos.x


# --- instance: a row of caps -------------------------------------------------------------------------------

func setup(a: String, h: float = 24.0, dev: String = "", col: Color = S.IVORY) -> Control:
	action = a
	cap_h = h
	fixed_device = dev
	color = col
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()
	return self


func setup_caps(c: Array, h: float = 24.0, col: Color = S.IVORY) -> Control:
	custom = c
	cap_h = h
	color = col
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()
	return self


func _refresh() -> void:
	_rev = revision
	_caps = custom if not custom.is_empty() else caps_for(action, fixed_device)
	update_minimum_size()
	queue_redraw()


func _process(_delta: float) -> void:
	if _rev != revision and custom.is_empty() and fixed_device == "":
		_refresh()


func _get_minimum_size() -> Vector2:
	return Vector2(caps_width(_caps, cap_h), cap_h)


func _draw() -> void:
	draw_caps(self, _caps, Vector2(0, (size.y - cap_h) * 0.5), cap_h, color)
