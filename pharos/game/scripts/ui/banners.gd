extends Control
## Centre banners (title, day, night, dawn, boss, danger, blessing) and small toasts at the bottom (build, coins,
## favor, info), both fed by Game.message. Banners queue: a new one shortens the current one instead of
## cutting it, so "Zeus · Ira del cielo" is still read before "Día 2".

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

const T_IN := 0.55
const T_OUT := 0.6
const MIN_HOLD := 1.2

## Per-kind look: title size, colours, icon and hold time (seconds).
const KINDS := {
	"title": {"px": 84, "color": Color("F7F1E3"), "icon": "flame", "icon_col": Color("FFB25A"), "hold": 3.4, "track": 22.0, "sub_px": 26},
	"day": {"px": 56, "color": Color("F7F1E3"), "icon": "sun", "icon_col": Color("E9C46A"), "hold": 2.6, "track": 14.0, "sub_px": 23},
	"night": {"px": 56, "color": Color("EEE8FF"), "icon": "moon", "icon_col": Color("C9B8FF"), "hold": 2.8, "track": 14.0, "sub_px": 23},
	"dawn": {"px": 56, "color": Color("FFF0DC"), "icon": "sun", "icon_col": Color("FFB98A"), "hold": 2.6, "track": 14.0, "sub_px": 23},
	"danger": {"px": 40, "color": Color("FFD9CF"), "icon": "flame_out", "icon_col": Color("E86A5A"), "hold": 2.6, "track": 8.0, "sub_px": 22},
	"boss": {"px": 52, "color": Color("E6DAFF"), "icon": "enemy", "icon_col": Color("B07CFF"), "hold": 2.8, "track": 12.0, "sub_px": 22},
	"blessing": {"px": 54, "color": Color("F7F1E3"), "icon": "sun", "icon_col": Color("E9C46A"), "hold": 2.0, "track": 14.0, "sub_px": 24},
}

var _queue: Array = []
var _cur: Dictionary = {}
var _t := 0.0
var _hold := 0.0
var _blessing_id := ""
var _toasts: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.anchor_left = 0.0
	_toasts.anchor_right = 1.0
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_top = -260.0
	_toasts.offset_bottom = -118.0
	add_child(_toasts)
	Game.blessing_taken.connect(func(id: String) -> void: _blessing_id = id)


## Lifts the toasts so they clear the touch buttons or the vitals.
func set_toast_bottom(px: float) -> void:
	_toasts.offset_bottom = -px
	_toasts.offset_top = -px - 142.0


func post(text: String, sub: String, kind: String) -> void:
	if KINDS.has(kind):
		var d: Dictionary = (KINDS[kind] as Dictionary).duplicate()
		d["text"] = text
		d["sub"] = sub
		d["kind"] = kind
		if kind == "blessing" and _blessing_id != "" and Data.BLESSINGS.has(_blessing_id):
			var b: Dictionary = Data.BLESSINGS[_blessing_id]
			d["icon"] = b["icon"]
			d["icon_col"] = b["color"]
			d["color"] = (b["color"] as Color).lerp(Color("F7F1E3"), 0.55)
		_queue.append(d)
		if _cur.is_empty():
			_next()
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


## Fanós is at something he can use: let the current banner leave as soon as it has been readable.
func hurry() -> void:
	if not _cur.is_empty() and _t < T_IN + _hold:
		_hold = maxf(MIN_HOLD, minf(_hold, _t - T_IN))


## How visible the current centre banner is (0..1); the HUD fades its controls hint under it.
func presence() -> float:
	if _cur.is_empty():
		return 0.0
	var k_in := S.ease_out(_t / T_IN)
	var k_out := S.ease_in_out((_t - T_IN - _hold) / T_OUT)
	return k_in * (1.0 - k_out) * modulate.a


func _process(delta: float) -> void:
	if _cur.is_empty():
		return
	_t += S.rdelta(delta)
	# Someone is waiting: leave as soon as the current banner has been readable for a moment.
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
	while px > 24 and S.tracked_width(f, text, px, tracking) > max_w:
		px -= 2
	var center := Vector2(size.x * 0.5, size.y * 0.3)
	var scale_k := 1.0 + 0.05 * (1.0 - S.ease_out(t / 0.8))
	var rise := -8.0 * k_out
	# Soft dark band behind the words: legible over a bright noon without drawing a box.
	var band_h := float(px) * 3.2 + (40.0 if sub != "" else 0.0)
	S.draw_soft_band(self, Rect2(center.x - size.x * 0.42, center.y - band_h * 0.55, size.x * 0.84, band_h), Color(S.INK, 0.32 * alpha), 0.3, 0.32)
	draw_set_transform(center + Vector2(0, rise), 0.0, Vector2(scale_k, scale_k))
	var icon: String = _cur["icon"]
	var y_title := float(px) * 0.36
	if icon != "" and text != "":
		var isz := float(px) * 0.62
		var ir := Rect2(-isz * 0.5, -float(px) * 0.62 - isz, isz, isz)
		Icons.draw(self, icon, Rect2(ir.position + Vector2(0, 2), ir.size), Color(S.INK, 0.35 * alpha))
		Icons.draw(self, icon, ir, Color(_cur["icon_col"], alpha))
	if text != "":
		var col: Color = _cur["color"]
		S.draw_tracked(self, f, text, px, Vector2(0, y_title), tracking, Color(col, alpha), 1, 7, clampf(t / 0.9, 0.0, 1.0))
	var line_k := S.ease_out((t - 0.12) / 0.8)
	var y_line := y_title + float(px) * 0.38
	if text != "" and line_k > 0.0:
		var hw := clampf(S.tracked_width(f, text, px, base_track) * 0.42, 90.0, 300.0) * line_k
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


# --- toasts ------------------------------------------------------------------------------------------------

func _toast(text: String, sub: String, kind: String) -> void:
	var icon := ""
	var icol := S.GOLD
	var glyph := ""
	match kind:
		"coins":
			icon = "coin"
			icol = S.COIN
		"build":
			icon = "hammer"
		"favor":
			icon = "beam"
			icol = S.FIRE
			# "El Haz del Faro está listo  ·  Q": show the key of the device in use instead of a hardcoded Q.
			var parts := sub.split("·")
			if parts.size() > 1:
				sub = parts[0].strip_edges()
				glyph = "power"
	if kind == "build" and sub == "construida" and text in ["Muelle", "Cuartel", "Olivar", "Faro"]:
		sub = "construido" # masculine buildings (the game always says "construida")
	if text == "" and sub != "":
		text = sub
		sub = ""
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := S.panel(0.58, 18, Color(icol, 0.4), 10.0)
	sb.content_margin_left = 14
	sb.content_margin_right = 18
	sb.content_margin_top = 7
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(row)
	if icon != "":
		var iv := W.IconView.new(icon, icol, 22.0)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(iv)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := S.label(text, S.CINZEL, 17, S.IVORY, 1, 3)
	col.add_child(t)
	if sub != "":
		var s := S.label(sub, S.ITALIC, 16, Color(S.IVORY, 0.78), 0, 3)
		col.add_child(s)
	if glyph != "":
		var g: Control = G.new().setup(glyph, 22.0)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(g)
	_toasts.add_child(pc)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	pc.modulate.a = 0.0
	var tw := S.tween(pc)
	tw.tween_property(pc, "modulate:a", 1.0, 0.22)
	tw.tween_interval(2.8 if kind != "coins" else 3.4)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)
