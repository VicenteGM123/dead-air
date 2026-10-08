extends Control
## Input glyphs: remembers the last device used (keyboard+mouse, gamepad or touch) and draws the matching key
## caps for an action — [E] on keyboard, (A) on a pad, a tap ring on touch. Instances refresh by themselves
## when the device changes.

const S := preload("res://scripts/ui/style.gd")

static var device := "kb" # "kb" | "pad" | "touch"
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
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		set_device("touch")
	elif e is InputEventKey and e.pressed:
		set_device("kb")
	elif e is InputEventMouseButton and e.pressed and e.device != InputEvent.DEVICE_ID_EMULATION:
		set_device("kb")
	elif e is InputEventJoypadButton and e.pressed:
		set_device("pad")
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.55:
		set_device("pad")


## How to trigger `action` on `dev`. Each cap is [kind, text]: kind is "key" (rounded square), "pad" (round
## face button), "pill" (shoulder / menu button), "icon" (vector icon) or "word" (plain small text).
static func caps_for(action: String, dev: String = "") -> Array:
	if dev == "":
		dev = device
	if dev == "pad":
		match action:
			"move": return [["icon", "stick"]]
			"attack": return [["pad", "X"]]
			"bash": return [["pad", "Y"]]
			"dodge": return [["pad", "B"]]
			"power": return [["pill", "RB"]]
			"interact", "accept": return [["pad", "A"]]
			"back": return [["pad", "B"]]
			"pause": return [["pill", "Start"]]
			"pick": return [["icon", "dpad"], ["pad", "A"]]
	elif dev == "touch":
		match action:
			"interact", "accept": return [["icon", "tap"]]
			"power": return [["icon", "beam"]]
			"attack": return [["icon", "anchor"]]
			"bash": return [["icon", "lens"]]
			"dodge": return [["icon", "steam"]]
			"pause": return [["icon", "pause"]]
			"move": return [["icon", "stick"]]
			"pick": return [["icon", "tap"]]
			"back": return [] # no key to show on a phone: tap the on-screen button instead
	match action:
		"move": return [["key", "WASD"]]
		"attack": return [["key", "J"], ["icon", "mouse_l"]]
		"bash": return [["key", "K"], ["icon", "mouse_r"]]
		"dodge": return [["key", "Espacio"]]
		"power": return [["key", "Q"]]
		"interact": return [["key", "E"]]
		"accept": return [["key", "Intro"]]
		"back": return [["key", "Esc"]]
		"pause": return [["key", "Esc"]]
		"pick": return [["key", "1"], ["key", "2"], ["key", "3"]]
	return []


static func cap_width(cap: Array, h: float) -> float:
	match cap[0]:
		"pad", "icon":
			return h
		_:
			var f := S.font(S.CINZEL_BOLD)
			var fs := int(h * (0.5 if cap[0] == "key" else 0.44))
			var tw := f.get_string_size(cap[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			return maxf(h, tw + h * (0.62 if cap[0] == "key" else 0.8))


## Draws one cap in `r` (height = r.size.y).
static func draw_cap(ci: CanvasItem, cap: Array, r: Rect2, col: Color, bg_alpha: float = 0.55) -> void:
	var h := r.size.y
	var kind: String = cap[0]
	var text: String = cap[1]
	match kind:
		"icon":
			Icons.draw(ci, text, r.grow(-h * 0.06), col)
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
			sb.set_corner_radius_all(int(h * (0.24 if kind == "key" else 0.5)))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, r)
	var f := S.font(S.CINZEL_BOLD)
	var fs := int(h * (0.5 if kind == "key" else (0.5 if kind == "pad" else 0.44)))
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var y := r.position.y + (h + asc - desc) * 0.5 - h * 0.02
	ci.draw_string(f, Vector2(r.position.x + (r.size.x - tw) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


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
	var w := 0.0
	for i in _caps.size():
		w += cap_width(_caps[i], cap_h) + (cap_h * 0.22 if i > 0 else 0.0)
	return Vector2(w, cap_h)


func _draw() -> void:
	var x := 0.0
	var y := (size.y - cap_h) * 0.5
	for i in _caps.size():
		var cw := cap_width(_caps[i], cap_h)
		draw_cap(self, _caps[i], Rect2(x, y, cw, cap_h), color)
		x += cw + cap_h * 0.22
