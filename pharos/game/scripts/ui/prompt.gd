extends Control
## The world-anchored interaction prompt: floats above whatever Fanós can use (build spot, night horn, cats).
## Title, a short italic description, the interact key inside a ring that fills while held, the verb, and the
## price in dracmas (red when it can't be paid, with a small shake when the hold is denied).

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

const DESC_W := 252.0

var _card: PanelContainer
var _sb: StyleBoxFlat
var _title: Label
var _desc: Label
var _rule: Control
var _ring: KeyRing
var _verb: Label
var _cost_box: HBoxContainer
var _coin: Control
var _cost: Label
var _target: Object = null
var _shown := 0.0
var _pop := 0.0
var _deny := 0.0
var _point := Vector2.ZERO
var _accent := S.GOLD
var _last := {}
var _placed := false
var enabled := true
var hud: Control = null # the HUD, whose clusters the card keeps clear of
var dim := 0.0 # 0..1 while a centre banner is still on screen (the card waits under it)


## The interact key in a ring that fills with the hold / payment progress.
class KeyRing extends Control:
	var progress := 0.0
	var accent := Color("E9C46A")
	var _rev := -1
	var _caps: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(38, 38)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if _rev != G.revision:
			_rev = G.revision
			_caps = G.caps_for("interact")
			queue_redraw()

	func set_progress(p: float) -> void:
		p = clampf(p, 0.0, 1.0)
		if not is_equal_approx(p, progress):
			progress = p
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_arc(c, r, 0.0, TAU, 40, Color(S.INK, 0.45), 4.0, true)
		draw_arc(c, r, 0.0, TAU, 40, Color(S.IVORY, 0.16), 2.0, true)
		if progress > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * progress, maxi(8, int(48 * progress)), accent, 3.0, true)
		if _caps.is_empty():
			return
		var cap: Array = _caps[0]
		var h := r * 1.15
		var cw := G.cap_width(cap, h)
		G.draw_cap(self, cap, Rect2(c.x - cw * 0.5, c.y - h * 0.5, cw, h), S.IVORY, 0.0 if cap[0] == "icon" else 0.5)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sb = S.panel(0.64, 10, Color(S.GOLD, 0.45), 12.0)
	_sb.content_margin_left = 16
	_sb.content_margin_right = 16
	_sb.content_margin_top = 10
	_sb.content_margin_bottom = 10
	_card.add_theme_stylebox_override("panel", _sb)
	add_child(_card)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)
	_card.add_child(col)
	_title = S.label("", S.CINZEL, 18, S.IVORY, 2, 4)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_desc = S.label("", S.ITALIC, 16, Color(S.IVORY, 0.8), 0, 3)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(DESC_W, 0)
	col.add_child(_desc)
	_rule = W.Ornament.new("rule", DESC_W, Color(S.GOLD, 0.55))
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_rule)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_ring = KeyRing.new()
	row.add_child(_ring)
	_verb = S.label("", S.CINZEL, 17, S.GOLD, 2, 4)
	_verb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_verb)
	_cost_box = HBoxContainer.new()
	_cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_box.add_theme_constant_override("separation", 5)
	row.add_child(_cost_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_box.add_child(gap)
	_coin = W.IconView.new("coin", S.COIN, 20.0)
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost_box.add_child(_coin)
	_cost = S.label("", S.CINZEL_BOLD, 19, S.IVORY, 0, 4)
	_cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost_box.add_child(_cost)
	_card.modulate.a = 0.0
	_card.visible = false


func has_target() -> bool:
	return _target != null


func _hero() -> Node:
	return Game.hero if Game.hero and is_instance_valid(Game.hero) else null


func _process(delta: float) -> void:
	var rd := S.rdelta(delta)
	var hero := _hero()
	var tgt: Object = null
	if enabled and hero and hero.interact_target and is_instance_valid(hero.interact_target) and hero.interact_target.has_method("interact_info"):
		tgt = hero.interact_target
	if tgt != _target:
		if tgt != null and _target != null:
			_pop = 1.0
		_target = tgt
		_last = {}
	if _target != null:
		_shown = minf(1.0, _shown + rd / 0.16)
		_update_info(_target.call("interact_info"))
	else:
		_shown = maxf(0.0, _shown - rd / 0.14)
	_pop = maxf(0.0, _pop - rd * 6.0)
	_deny = maxf(0.0, _deny - rd * 2.5)
	_card.visible = _shown > 0.0
	if not _card.visible:
		_placed = false
		queue_redraw()
		return
	_place(rd)
	var a := S.ease_out(_shown)
	_card.modulate.a = a * (1.0 - clampf(dim, 0.0, 1.0))
	var sc := (0.94 + 0.06 * a) * (1.0 - 0.03 * _pop)
	_card.pivot_offset = Vector2(_card.size.x * 0.5, _card.size.y)
	_card.scale = Vector2(sc, sc)
	queue_redraw()


func _update_info(info: Dictionary) -> void:
	var kind: String = info.get("kind", "")
	var title: String = info.get("title", "")
	var desc: String = info.get("desc", "")
	var verb: String = info.get("verb", "Usar")
	var cost: int = int(info.get("cost", 0))
	var afford: bool = info.get("afford", true)
	var progress: float = float(info.get("progress", 0.0))
	var denied: bool = info.get("denied", false)
	_accent = S.NYX if kind == "horn" else S.GOLD
	if _last.get("title", "~") != title:
		_title.text = title.to_upper()
		_fit(_title, 18, 13, DESC_W + 8.0)
	if _last.get("desc", "~") != desc:
		_desc.text = desc
		_desc.visible = desc != ""
	if _last.get("verb", "~") != verb or _last.get("kind", "~") != kind:
		_verb.text = verb
		_verb.label_settings.font_color = S.NYX_LIGHT if kind == "horn" else S.GOLD
		(_rule as W.Ornament).color = Color(_accent, 0.55)
		_rule.queue_redraw()
		_sb.border_color = Color(_accent, 0.45)
		_ring.accent = _accent.lightened(0.1)
	_cost_box.visible = cost > 0
	if cost > 0:
		var ctext := str(cost)
		if _last.get("cost", "~") != ctext or _last.get("afford", "~") != str(afford):
			_cost.text = ctext
			_cost.label_settings.font_color = S.IVORY if afford else S.DANGER
			(_coin as W.IconView).color = S.COIN if afford else S.COIN.darkened(0.35)
			_coin.queue_redraw()
	_ring.set_progress(progress)
	if denied:
		_deny = 1.0
	var border := Color(_accent, 0.45).lerp(Color(S.DANGER, 0.9), _deny)
	if _sb.border_color != border:
		_sb.border_color = border
	_point = Vector2.INF
	var anchor: Vector3
	if info.has("anchor"):
		anchor = info["anchor"]
	elif _target is Node3D:
		anchor = (_target as Node3D).global_position + Vector3(0, 2.0, 0)
	else:
		return
	var cam := _camera()
	if cam and not cam.is_position_behind(anchor):
		_point = cam.unproject_position(anchor)
	_last = {"title": title, "desc": desc, "verb": verb, "kind": kind, "cost": str(cost), "afford": str(afford)}


func _camera() -> Camera3D:
	if Game.main and "rig" in Game.main and Game.main.rig and Game.main.rig.cam:
		return Game.main.rig.cam
	return get_viewport().get_camera_3d()


## Shrinks a single-line label until it fits `max_w`.
func _fit(l: Label, px: int, min_px: int, max_w: float) -> void:
	var f := l.label_settings.font
	var s := px
	while s > min_px and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	l.label_settings.font_size = s


func _place(rd: float) -> void:
	if not _point.is_finite():
		_card.visible = false
		_placed = false
		return
	var cs := _card.get_combined_minimum_size()
	_card.size = cs
	var pos := Vector2(_point.x - cs.x * 0.5, _point.y - cs.y - 16.0)
	pos = _clamp_screen(pos, cs)
	pos = _avoid_hud(pos, cs)
	# Follow the anchor tightly, but glide (rather than jump) when the card steps around a HUD cluster.
	if _placed:
		pos = _card.position.lerp(pos, 1.0 - exp(-rd * 22.0))
	_placed = true
	var shake := sin(S.now() * 70.0) * 5.0 * _deny
	_card.position = (pos + Vector2(shake, 0)).round()


func _clamp_screen(pos: Vector2, cs: Vector2) -> Vector2:
	pos.x = clampf(pos.x, 12.0, maxf(12.0, size.x - cs.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, size.y - cs.y - 12.0))
	return pos


## Moves the card the shortest way out of the HUD's clusters (top status, controls hint, dracmas, vitals).
func _avoid_hud(pos: Vector2, cs: Vector2) -> Vector2:
	if hud == null or not hud.has_method("reserved_rects"):
		return pos
	var rects: Array = hud.call("reserved_rects")
	for _pass in 3:
		var hit := false
		for rr in rects:
			var r: Rect2 = rr
			if not Rect2(pos, cs).intersects(r):
				continue
			hit = true
			var best := pos
			var best_d := INF
			for cand in [Vector2(pos.x, r.end.y + 4.0), Vector2(pos.x, r.position.y - cs.y - 4.0), Vector2(r.position.x - cs.x - 4.0, pos.y), Vector2(r.end.x + 4.0, pos.y)]:
				var c: Vector2 = cand
				if c.x < 8.0 or c.y < 8.0 or c.x + cs.x > size.x - 8.0 or c.y + cs.y > size.y - 8.0:
					continue
				var d := c.distance_squared_to(pos)
				if d < best_d:
					best_d = d
					best = c
			pos = best
		if not hit:
			break
	return pos


func _draw() -> void:
	if not _card.visible or not _point.is_finite():
		return
	# A small pointer from the card toward its anchor: below the card normally, above it when the card had to
	# step down out of the way of the HUD, none when the card sits beside the anchor.
	var a := _card.modulate.a
	var top := _card.position.y
	var bottom := _card.position.y + _card.size.y
	var dir := 0.0
	if _point.y >= bottom - 2.0:
		dir = 1.0
	elif _point.y <= top + 2.0:
		dir = -1.0
	if dir == 0.0 or absf(_point.x - _card.get_rect().get_center().x) > _card.size.x * 0.5 + 40.0:
		return
	var bx := clampf(_point.x, _card.position.x + 18.0, _card.position.x + _card.size.x - 18.0)
	var by := bottom if dir > 0.0 else top
	var tip := Vector2(bx, by + 9.0 * dir)
	var line := Color(_sb.border_color, _sb.border_color.a * a)
	draw_colored_polygon(PackedVector2Array([Vector2(bx - 8, by - 0.5 * dir), Vector2(bx + 8, by - 0.5 * dir), tip]), Color(S.PANEL, 0.64 * a))
	draw_line(Vector2(bx - 8, by), tip, line, 1.0, true)
	draw_line(Vector2(bx + 8, by), tip, line, 1.0, true)
	draw_circle(tip + Vector2(0, 5.0 * dir), 2.0, Color(_accent, 0.8 * a))
