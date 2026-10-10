extends Control
## Game.message(text, sub, kind) on screen.
##  - Centre banners for the big moments, queued (a new one shortens the current one instead of cutting it):
##      "title" / "area" / "place"   a place name ("NEMEA" · "La isla del León"), meander under it
##      "labor"                       a labour announced in words (the frieze card is Game.labor_card)
##      "boss"                        a beast appears
##      "warning" / "danger" / "rule" a rule the game says once ("Su piel no se puede cortar")
##      "victory" / "big"             a triumph, a big statement
##  - Toasts for everything else ("info", "hint", "tutorial", "altar", "checkpoint", "item", ...): small, top
##    centre, at most three. Text may carry action tokens such as {chain}, {interact}, {attack}, {lock}: they are
##    drawn as the key or button of the device in use (see glyphs.gd for the names).

const S := preload("res://scripts/ui/style.gd")
const G := preload("res://scripts/ui/glyphs.gd")

const T_IN := 0.55
const T_OUT := 0.6
const MIN_HOLD := 1.2

const KINDS := {
	"title": {"px": 62, "color": Color("F6EEDD"), "icon": "", "icon_col": Color("E59A66"), "hold": 3.0, "track": 22.0, "sub_px": 25, "orn": "meander"},
	"labor": {"px": 52, "color": Color("F6EEDD"), "icon": "", "icon_col": Color("E59A66"), "hold": 3.0, "track": 14.0, "sub_px": 24, "orn": "meander"},
	"boss": {"px": 50, "color": Color("FFE2D6"), "icon": "eye", "icon_col": Color("E8604A"), "hold": 2.6, "track": 12.0, "sub_px": 22, "orn": "rule"},
	"warning": {"px": 34, "color": Color("FFE6DA"), "icon": "eye", "icon_col": Color("E8604A"), "hold": 3.2, "track": 7.0, "sub_px": 22, "orn": "rule"},
	"victory": {"px": 54, "color": Color("F8DFA0"), "icon": "laurel", "icon_col": Color("EBC170"), "hold": 3.0, "track": 14.0, "sub_px": 24, "orn": "rule"},
	"big": {"px": 52, "color": Color("F6EEDD"), "icon": "", "icon_col": Color("E59A66"), "hold": 2.6, "track": 12.0, "sub_px": 23, "orn": "rule"},
}
const ALIASES := {"area": "title", "place": "title", "region": "title", "danger": "warning", "rule": "warning",
	"labour": "labor"}
const TOAST_ICONS := {"altar": "altar", "checkpoint": "altar", "save": "altar", "item": "lion", "skin": "lion",
	"chain": "chain", "boat": "boat", "cat": "cat", "sword": "sword", "shield": "shield"}

var hud: Control = null # toasts step down under the boss bar while it is up
var _queue: Array = []
var _cur: Dictionary = {}
var _t := 0.0
var _hold := 0.0
var _toasts: VBoxContainer


# --- a toast: icon, text with action glyphs, an italic line under it ----------------------------------------

class Toast extends Control:
	var icon := ""
	var icon_col := S.CLAY_LIGHT
	var parts: Array = [] # [["text", "..."], ["glyph", "chain"], ...]
	var sub := ""
	var k := 0.0
	var _rev := -1

	func _init(t: String, s: String, ic: String) -> void:
		icon = ic
		sub = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		parts = _parse(t)
		_resize()

	static func _parse(t: String) -> Array:
		var out: Array = []
		var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
		var at := 0
		for m in re.search_all(t):
			if m.get_start() > at:
				out.append(["text", t.substr(at, m.get_start() - at)])
			out.append(["glyph", m.get_string(1)])
			at = m.get_end()
		if at < t.length():
			out.append(["text", t.substr(at)])
		return out

	func _line_w() -> float:
		var f := S.font(S.GARAMOND)
		var w := 0.0
		for p in parts:
			if p[0] == "text":
				w += f.get_string_size(p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			else:
				w += G.caps_width(G.caps_for(p[1]), 24.0) + 8.0
		return w

	func _resize() -> void:
		_rev = G.revision
		var w := _line_w() + (34.0 if icon != "" else 0.0)
		if sub != "":
			w = maxf(w, S.font(S.ITALIC).get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
		custom_minimum_size = Vector2(w + 40.0, 34.0 + (22.0 if sub != "" else 0.0))
		update_minimum_size()

	func _process(_d: float) -> void:
		if _rev != G.revision:
			_resize()
			queue_redraw()

	func _draw() -> void:
		var a := modulate.a
		S.draw_soft_band(self, Rect2(-30, -6, size.x + 60, size.y + 12), Color(S.INK, 0.4), 0.22, 0.3)
		var lw := _line_w() + (34.0 if icon != "" else 0.0)
		var x := (size.x - lw) * 0.5
		var y := 22.0
		if icon != "":
			Icons.draw(self, icon, Rect2(x, y - 19.0, 24, 24), icon_col)
			x += 34.0
		var f := S.font(S.GARAMOND)
		for p in parts:
			if p[0] == "text":
				S.draw_text(self, f, p[1], 20, Vector2(x, y), S.IVORY, 0, 4)
				x += f.get_string_size(p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			else:
				x += 4.0
				x += G.draw_caps(self, G.caps_for(p[1]), Vector2(x, y - 18.0), 24.0, S.IVORY)
				x += 4.0
		if sub != "":
			S.draw_text(self, S.font(S.ITALIC), sub, 17, Vector2(size.x * 0.5, y + 22.0), Color(S.IVORY, 0.78), 1, 4)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 10)
	_toasts.anchor_left = 0.0
	_toasts.anchor_right = 1.0
	_toasts.offset_top = 26.0
	_toasts.offset_bottom = 220.0
	add_child(_toasts)


func post(text: String, sub: String, kind: String) -> void:
	var k := String(ALIASES.get(kind, kind))
	if KINDS.has(k):
		var d: Dictionary = (KINDS[k] as Dictionary).duplicate()
		d["text"] = text
		d["sub"] = sub
		d["kind"] = k
		_queue.append(d)
		if _cur.is_empty():
			_next()
		if k == "warning":
			S.sfx("ui_toast", -2.0)
	else:
		_toast(text, sub, kind)


func clear() -> void:
	_queue.clear()
	_cur = {}
	queue_redraw()
	for c in _toasts.get_children():
		c.queue_free()


func _next() -> void:
	_cur = {}
	if _queue.is_empty():
		queue_redraw()
		return
	_cur = _queue.pop_front()
	_t = 0.0
	_hold = float(_cur["hold"])


## How visible the current centre banner is (0..1).
func presence() -> float:
	if _cur.is_empty():
		return 0.0
	var k_in := S.ease_out(_t / T_IN)
	var k_out := S.ease_in_out((_t - T_IN - _hold) / T_OUT)
	return k_in * (1.0 - k_out) * modulate.a


func _process(delta: float) -> void:
	var top := 26.0 + (82.0 if hud != null and bool(hud.call("boss_active")) else 0.0)
	_toasts.offset_top = move_toward(_toasts.offset_top, top, S.rdelta(delta) * 400.0)
	_toasts.offset_bottom = _toasts.offset_top + 200.0
	if _cur.is_empty():
		return
	_t += S.rdelta(delta)
	if not _queue.is_empty() and _t < T_IN + _hold:
		_hold = maxf(MIN_HOLD, minf(_hold, _t - T_IN))
	if _t >= T_IN + _hold + T_OUT:
		_next()
	queue_redraw()


func _draw() -> void:
	if _cur.is_empty():
		return
	var t := _t
	var k_in := S.ease_out(t / T_IN)
	var k_out := S.ease_in_out((t - T_IN - _hold) / T_OUT)
	var alpha := k_in * (1.0 - k_out)
	if alpha <= 0.005:
		return
	var px: int = _cur["px"]
	var f := S.font(S.CINZEL)
	var text: String = (_cur["text"] as String).to_upper()
	var sub: String = _cur["sub"]
	var base_track: float = _cur["track"]
	var tracking := base_track + 18.0 * (1.0 - S.ease_out(t / 1.5)) + 8.0 * k_out
	var max_w := size.x - 96.0
	while px > 22 and S.tracked_width(f, text, px, tracking) > max_w:
		px -= 2
	var warn: bool = _cur["kind"] == "warning"
	var center := Vector2(size.x * 0.5, size.y * (0.25 if warn else 0.3))
	var scale_k := 1.0 + 0.05 * (1.0 - S.ease_out(t / 0.8))
	var rise := -8.0 * k_out
	var band_h := float(px) * 3.2 + (44.0 if sub != "" else 0.0)
	S.draw_soft_band(self, Rect2(center.x - size.x * 0.42, center.y - band_h * 0.55, size.x * 0.84, band_h), Color(S.INK, 0.44 * alpha), 0.3, 0.32)
	draw_set_transform(center + Vector2(0, rise), 0.0, Vector2(scale_k, scale_k))
	var icon: String = _cur["icon"]
	var y_title := float(px) * 0.36
	if icon != "" and text != "":
		var isz := float(px) * (0.9 if warn else 0.62)
		var ir := Rect2(-isz * 0.5, -float(px) * 0.62 - isz, isz, isz)
		Icons.draw(self, icon, Rect2(ir.position + Vector2(0, 2), ir.size), Color(S.INK, 0.4 * alpha))
		Icons.draw(self, icon, ir, Color(_cur["icon_col"], alpha))
	if text != "":
		var col: Color = _cur["color"]
		S.draw_tracked(self, f, text, px, Vector2(0, y_title), tracking, Color(col, alpha), 1, 7, clampf(t / 0.9, 0.0, 1.0))
	var line_k := S.ease_out((t - 0.12) / 0.8)
	var y_line := y_title + float(px) * 0.38
	if text != "" and line_k > 0.0:
		var hw := clampf(S.tracked_width(f, text, px, base_track) * 0.45, 90.0, 320.0) * line_k
		if _cur["orn"] == "meander":
			S.draw_meander(self, Vector2(0, y_line + 6.0), hw, 13.0, Color(S.CLAY_LIGHT, 0.85 * alpha))
			y_line += 12.0
		else:
			S.draw_rule(self, Vector2(0, y_line), hw, Color(_cur["icon_col"], 0.85 * alpha))
	if sub != "":
		var sa := S.ease_out((t - 0.25) / 0.5) * (1.0 - k_out)
		var fi := S.font(S.ITALIC)
		var spx: int = _cur["sub_px"]
		while spx > 15 and fi.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x > max_w:
			spx -= 1
		var y_sub := y_line + float(spx) * 1.35 if text != "" else 0.0
		S.draw_text(self, fi, sub, spx, Vector2(0, y_sub), Color(S.IVORY, 0.92 * sa), 1, 5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _toast(text: String, sub: String, kind: String) -> void:
	if text == "" and sub != "":
		text = sub
		sub = ""
	var ic := String(TOAST_ICONS.get(kind, ""))
	var t := Toast.new(text, sub, ic)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toasts.add_child(t)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	t.modulate.a = 0.0
	var hold := 4.5 if kind in ["hint", "tutorial"] else 3.0
	var tw := S.tween(t)
	tw.tween_property(t, "modulate:a", 1.0, 0.25)
	tw.tween_interval(hold)
	tw.tween_property(t, "modulate:a", 0.0, 0.6)
	tw.tween_callback(t.queue_free)
	S.sfx("ui_toast", -6.0)
