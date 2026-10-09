extends RefCounted
## Small reusable controls of the DOCE UI (inherited from PHAROS): icons, bars, text-only menu buttons, option rows and ornaments.

const S := preload("res://scripts/ui/style.gd")


## A vector icon (see Icons) with a soft drop shadow.
class IconView extends Control:
	var icon := "coin"
	var color := Color.WHITE
	var shadow := true

	func _init(i: String = "coin", c: Color = Color.WHITE, px: float = 24.0) -> void:
		icon = i
		color = c
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_icon(i: String, c: Color) -> void:
		if i != icon or c != color:
			icon = i
			color = c
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if shadow:
			Icons.draw(self, icon, Rect2(r.position + Vector2(0, 1.5), r.size), Color(S.INK, 0.4 * color.a))
		Icons.draw(self, icon, r, color)


## A thin rounded bar with a delayed "damage trail" that drains after a hit.
class Bar extends Control:
	var value := 1.0
	var trail := 1.0
	var color := S.IVORY
	var back := Color(S.INK, 0.5)
	var trail_color := Color(1.0, 0.93, 0.85, 0.75)
	var flash := 0.0
	var _hold := 0.0
	var _sb := StyleBoxFlat.new()

	func _init(w: float = 200.0, h: float = 6.0, c: Color = S.IVORY) -> void:
		custom_minimum_size = Vector2(w, h)
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.anti_aliasing = true

	func set_value(v: float, instant: bool = false) -> void:
		v = clampf(v, 0.0, 1.0)
		if is_equal_approx(v, value) and not instant:
			return
		if v < value and not instant:
			_hold = 0.45
			flash = 1.0
		value = v
		if instant or trail < value:
			trail = value
		queue_redraw()

	func _process(delta: float) -> void:
		var rd := S.rdelta(delta)
		if trail > value:
			if _hold > 0.0:
				_hold -= rd
			else:
				trail = move_toward(trail, value, rd * 0.55)
			queue_redraw()
		if flash > 0.0:
			flash = maxf(0.0, flash - rd * 3.0)
			queue_redraw()

	func _rounded(r: Rect2, c: Color) -> void:
		if r.size.x < 0.5:
			return
		_sb.bg_color = c
		_sb.set_corner_radius_all(int(minf(r.size.y, r.size.x) * 0.5))
		draw_style_box(_sb, r)

	func _draw() -> void:
		var h := size.y
		_rounded(Rect2(-1, -1, size.x + 2, h + 2), Color(S.INK, 0.35 * back.a / 0.5))
		_rounded(Rect2(Vector2.ZERO, size), back)
		if trail > value:
			_rounded(Rect2(0, 0, size.x * trail, h), trail_color)
		var c := color.lerp(Color.WHITE, flash * 0.6)
		_rounded(Rect2(0, 0, size.x * value, h), c)
		if value > 0.02 and h >= 5.0:
			draw_line(Vector2(h * 0.5, 1.0), Vector2(maxf(h * 0.5, size.x * value - h * 0.5), 1.0), Color(1, 1, 1, 0.28), 1.0)


## Text-only menu button: Cinzel, ivory; when focused or hovered it turns gold and two small diamonds and a
## hairline slide in. `confirm` makes it ask once before firing (destructive actions).
class Btn extends Button:
	signal activated
	var left := false
	var confirm := ""
	var _k := 0.0
	var _armed := false
	var _base := ""
	var _tw: Tween

	func _init(t: String, px: int = 24, align_left: bool = false, confirm_text: String = "") -> void:
		text = t
		_base = t
		left = align_left
		confirm = confirm_text
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
		add_theme_font_override("font", S.font(S.CINZEL, 3))
		add_theme_font_size_override("font_size", px)
		add_theme_color_override("font_color", Color(S.IVORY, 0.88))
		for n in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			add_theme_color_override(n, S.GOLD)
		add_theme_color_override("font_outline_color", Color(S.INK, 0.45))
		add_theme_constant_override("outline_size", 5)
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 34 if left else 40
		e.content_margin_right = 40
		e.content_margin_top = 5
		e.content_margin_bottom = 9
		for n in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(n, e)
		mouse_entered.connect(_on_hover)
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))
		pressed.connect(_on_pressed)

	func _on_hover() -> void:
		if not disabled and not has_focus():
			grab_focus()

	func _on_focus(on: bool) -> void:
		if on and not S.is_quiet():
			S.sfx("ui_move")
		if not on and _armed:
			_disarm()
		if _tw:
			_tw.kill()
		_tw = S.tween(self)
		_tw.tween_method(_set_k, _k, 1.0 if on else 0.0, 0.22 if on else 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _set_k(v: float) -> void:
		_k = v
		queue_redraw()

	func _on_pressed() -> void:
		if confirm != "" and not _armed:
			_armed = true
			text = confirm
			add_theme_color_override("font_focus_color", S.DANGER.lightened(0.15))
			add_theme_color_override("font_hover_color", S.DANGER.lightened(0.15))
			S.sfx("ui_back")
			return
		S.sfx("ui_select")
		activated.emit()

	func _disarm() -> void:
		_armed = false
		text = _base
		add_theme_color_override("font_focus_color", S.GOLD)
		add_theme_color_override("font_hover_color", S.GOLD)

	func _draw() -> void:
		if _k <= 0.01:
			return
		var f := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cy := size.y * 0.5 - 1.0
		var col := Color(S.DANGER if _armed else S.GOLD, _k)
		if left:
			S.draw_diamond(self, Vector2(16.0 - 8.0 * (1.0 - _k), cy), 4.0, col)
			draw_line(Vector2(34, size.y - 6), Vector2(34 + tw * _k, size.y - 6), Color(col, 0.5 * _k), 1.0, true)
		else:
			var cx := size.x * 0.5
			var off := tw * 0.5 + 20.0 + 10.0 * (1.0 - _k)
			S.draw_diamond(self, Vector2(cx - off, cy), 4.0, col)
			S.draw_diamond(self, Vector2(cx + off, cy), 4.0, col)
			draw_line(Vector2(cx - tw * 0.45 * _k, size.y - 5), Vector2(cx + tw * 0.45 * _k, size.y - 5), Color(col, 0.5 * _k), 1.0, true)


## One line of the options screen: a label on the left and a slider or a choice (segmented) on the right.
## Left / right change the value; mouse click and drag work too.
class OptionRow extends Control:
	signal changed(v: Variant)
	signal committed(v: Variant)
	var title := ""
	var kind := "slider"
	var value := 0.5
	var options: Array = []
	var index := 0
	var _k := 0.0
	var _drag := false
	var _seg_rects: Array = []
	var _tw: Tween

	func _init(t: String, k: String, opts: Array = []) -> void:
		title = t
		kind = k
		options = opts
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(540, 52)
		mouse_entered.connect(_on_hover)
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))

	func _on_hover() -> void:
		if not has_focus():
			grab_focus()

	func _on_focus(on: bool) -> void:
		if on and not S.is_quiet():
			S.sfx("ui_move")
		if _tw:
			_tw.kill()
		_tw = S.tween(self)
		_tw.tween_method(_set_k, _k, 1.0 if on else 0.0, 0.2)

	func _set_k(v: float) -> void:
		_k = v
		queue_redraw()

	func _widget_rect() -> Rect2:
		var x0 := size.x * 0.5
		return Rect2(x0, 0, size.x - x0 - 22.0, size.y)

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left", true):
			_step(-1)
			accept_event()
		elif e.is_action_pressed("ui_right", true):
			_step(1)
			accept_event()
		elif e.is_action_pressed("ui_accept") and kind == "choice":
			_step(1, true)
			accept_event()
		elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed:
				if kind == "slider":
					_drag = true
					_slide_to(mb.position.x)
				else:
					for i in _seg_rects.size():
						if (_seg_rects[i] as Rect2).grow(6).has_point(mb.position):
							_set_index(i)
			elif _drag:
				_drag = false
				committed.emit(value)
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			_slide_to((e as InputEventMouseMotion).position.x)
			accept_event()
		elif e is InputEventScreenDrag and _drag:
			_slide_to((e as InputEventScreenDrag).position.x)

	func _track() -> Rect2:
		var w := _widget_rect()
		return Rect2(w.position.x, size.y * 0.5 - 1.5, w.size.x - 64.0, 3.0)

	func _slide_to(x: float) -> void:
		var t := _track()
		var v := clampf((x - t.position.x) / t.size.x, 0.0, 1.0)
		v = snappedf(v, 0.05)
		if not is_equal_approx(v, value):
			value = v
			changed.emit(value)
			queue_redraw()

	func _step(d: int, wrap: bool = false) -> void:
		if kind == "slider":
			var v := clampf(snappedf(value + 0.1 * d, 0.05), 0.0, 1.0)
			if not is_equal_approx(v, value):
				value = v
				changed.emit(value)
				committed.emit(value)
				queue_redraw()
		else:
			var n := options.size()
			var i := index + d
			i = (i + n) % n if wrap else clampi(i, 0, n - 1)
			_set_index(i)

	func _set_index(i: int) -> void:
		if i == index:
			return
		index = i
		S.sfx("ui_move")
		changed.emit(index)
		committed.emit(index)
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		if _k > 0.01:
			var sb := S.box(Color(S.PANEL, 0.45 * _k), 8)
			sb.border_color = Color(S.GOLD, 0.3 * _k)
			sb.set_border_width_all(1)
			draw_style_box(sb, Rect2(Vector2.ZERO, size))
			S.draw_diamond(self, Vector2(14.0 - 6.0 * (1.0 - _k), h * 0.5), 3.5, Color(S.GOLD, _k))
		var f := S.font(S.CINZEL, 3)
		var col := Color(S.IVORY, 0.9).lerp(S.GOLD, _k)
		S.draw_text(self, f, title, 19, Vector2(28, h * 0.5 + 7), col, 0, 4)
		if kind == "slider":
			var t := _track()
			draw_line(t.position + Vector2(0, 1.5), Vector2(t.end.x, t.position.y + 1.5), Color(S.IVORY, 0.22), 3.0, true)
			draw_line(t.position + Vector2(0, 1.5), Vector2(t.position.x + t.size.x * value, t.position.y + 1.5), S.GOLD, 3.0, true)
			var kx := t.position.x + t.size.x * value
			draw_circle(Vector2(kx, h * 0.5), 8.0, Color(S.INK, 0.5))
			draw_circle(Vector2(kx, h * 0.5), 6.5, S.IVORY.lerp(S.GOLD, _k))
			S.draw_text(self, S.font(S.CINZEL_BOLD), str(int(round(value * 100.0))), 17, Vector2(t.end.x + 52.0, h * 0.5 + 6), Color(S.IVORY, 0.85), 2, 3)
		else:
			# Choices right-aligned to the same edge as the slider values, evenly spaced, small dots between.
			_seg_rects.clear()
			var fo := S.font(S.CINZEL, 2)
			var fs := 17
			var n := options.size()
			var gap := 34.0
			var right := _track().end.x + 52.0
			var widths: Array = []
			var total := 0.0
			for i in n:
				var tw := fo.get_string_size(String(options[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				widths.append(tw)
				total += tw
			total += gap * (n - 1)
			var x := right - total
			for i in n:
				var tw: float = widths[i]
				var r := Rect2(x - gap * 0.5, h * 0.18, tw + gap, h * 0.64)
				_seg_rects.append(r)
				var sel := i == index
				var c: Color = S.GOLD if sel else Color(S.IVORY, 0.48)
				S.draw_text(self, fo, String(options[i]), fs, Vector2(x, h * 0.5 + 6), c, 0, 3)
				if sel:
					draw_line(Vector2(x, h * 0.5 + 13), Vector2(x + tw, h * 0.5 + 13), Color(S.GOLD, 0.8), 1.0, true)
				if i < n - 1:
					S.draw_diamond(self, Vector2(x + tw + gap * 0.5, h * 0.5), 2.0, Color(S.IVORY, 0.3))
				x += tw + gap


## A decorative separator: "rule" (hairline + diamond) or "meander" (Greek key band).
class Ornament extends Control:
	var style := "rule"
	var color := Color(S.GOLD, 0.7)

	func _init(st: String = "rule", w: float = 240.0, c: Color = Color(S.GOLD, 0.7)) -> void:
		style = st
		color = c
		custom_minimum_size = Vector2(w, 20.0 if st == "meander" else 9.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if style == "meander":
			S.draw_meander(self, c + Vector2(0, 1.5), size.x * 0.5, 13.0, color)
		else:
			S.draw_rule(self, c, size.x * 0.5, color)


## Glyph-by-glyph text with animatable tracking and reveal (titles).
class TrackedText extends Control:
	var text := ""
	var font_path := S.CINZEL
	var px := 64
	var tracking := 12.0
	var reveal := 1.0
	var color := S.IVORY
	var align := 1
	var outline := 7

	func _init(t: String = "", fp: String = S.CINZEL, size_px: int = 64, track: float = 12.0, c: Color = S.IVORY, al: int = 1) -> void:
		text = t
		font_path = fp
		px = size_px
		tracking = track
		color = c
		align = al
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resize()

	func _resize() -> void:
		var f := S.font(font_path)
		custom_minimum_size = Vector2(S.tracked_width(f, text, px, tracking), f.get_height(px) * 1.05)

	func set_tracking(t: float) -> void:
		tracking = t
		queue_redraw()

	func set_reveal(r: float) -> void:
		reveal = r
		queue_redraw()

	func _draw() -> void:
		var f := S.font(font_path)
		var y := (size.y + f.get_ascent(px) - f.get_descent(px)) * 0.5
		var x := size.x * 0.5 if align == 1 else 0.0
		S.draw_tracked(self, f, text, px, Vector2(x, y), tracking, color, align, outline, reveal)
