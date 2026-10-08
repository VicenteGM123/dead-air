extends Control
## The in-game HUD. Minimal and quiet: dracmas top-left; phase title, Faro bar (and creatures left at night)
## top-centre with the boss bar under it; Fanós' vitals bottom-left (HP and the lantern's Llama); respawn
## countdown; off-screen chevrons toward the beaches where Nyx will land; a first-day controls hint.

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

static var _hint_done := false

var touch_layout := false
var _coin_row: HBoxContainer
var _coin_icon: W.IconView
var _coin_label: Label
var _coin_shown := 0.0
var _coin_target := 0
var _coin_bump := 0.0
var _phase_icon: W.IconView
var _phase_label: Label
var _faro_icon: W.IconView
var _faro_bar: W.Bar
var _faro_hurt := 0.0
var _faro_last := -1.0
var _foes_box: HBoxContainer
var _foes_label: Label
var _boss_box: VBoxContainer
var _boss_label: Label
var _boss_bar: W.Bar
var _boss_k := 0.0
var _boss_ref: Object = null
var _vitals: Vitals
var _respawn: HBoxContainer
var _respawn_num: Label
var _respawn_k := 0.0
var _respawn_last := -1
var _hint: PanelContainer
var _hint_holder: Control
var hint_dim := 0.0 # set by the UI while a centre banner is showing
var _hint_rows: VBoxContainer
var _hint_rev := -1
var _hint_t := 0.0
var _hint_on := false
var _markers: Markers
var _phase := -1
var _shown := 0.0
var _status: VBoxContainer
var _vis_tw: Tween
var _vis_on := false


# --- Fanós' vitals: lantern emblem ringed by the Llama, name and HP bar -------------------------------------

class Vitals extends Control:
	const EMB := 70.0
	var hp := 1.0
	var llama := 0.0
	var lit_ready := false
	var dead := false
	var _glow := 0.0
	var _ready_k := 0.0
	var hp_bar: W.Bar
	var _name: Label
	var _haz: HBoxContainer

	func _init() -> void:
		custom_minimum_size = Vector2(330, 80)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name = S.label("FANÓS", S.CINZEL, 14, Color(S.IVORY, 0.82), 4, 3)
		_name.position = Vector2(EMB + 14, 10)
		add_child(_name)
		hp_bar = W.Bar.new(214.0, 8.0, S.IVORY)
		hp_bar.position = Vector2(EMB + 16, 36)
		add_child(hp_bar)
		_haz = HBoxContainer.new()
		_haz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_haz.add_theme_constant_override("separation", 8)
		_haz.position = Vector2(EMB + 15, 50)
		_haz.add_child(G.new().setup("power", 22.0, "", Color("FFE0B0")))
		var l := S.label("Haz del Faro", S.CINZEL, 15, S.FIRE, 2, 4)
		_haz.add_child(l)
		add_child(_haz)
		_haz.modulate.a = 0.0

	func tick(hero: Node, rd: float) -> void:
		var h: float = clampf(hero.hp / maxf(1.0, hero.max_hp), 0.0, 1.0)
		dead = hero.state == Hero.S.DEAD
		hp_bar.set_value(h)
		var low := h < 0.3 and not dead
		var pulse := 0.5 + 0.5 * sin(S.now() * 6.0)
		hp_bar.color = S.DANGER.lerp(Color("FF9A8A"), pulse * 0.5) if low else S.IVORY
		hp_bar.queue_redraw()
		var lm: float = clampf(hero.favor / maxf(1.0, hero.favor_max()), 0.0, 1.0)
		var r := lm >= 0.999 and not dead
		if r and not lit_ready:
			_glow = 1.0
		lit_ready = r
		llama = lm
		_ready_k = move_toward(_ready_k, 1.0 if lit_ready else 0.0, rd * 4.0)
		_glow = maxf(0.0, _glow - rd * 1.2)
		_haz.modulate.a = _ready_k
		_haz.position.x = EMB + 15 + 6.0 * (1.0 - _ready_k)
		modulate.a = lerpf(modulate.a, 0.55 if dead else 1.0, minf(1.0, rd * 5.0))
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(EMB * 0.5 + 2.0, size.y * 0.5)
		var t := S.now()
		var rr := 30.0
		if lit_ready:
			var p := 0.5 + 0.5 * sin(t * 3.2)
			for i in 4:
				draw_circle(c, rr + 6.0 + i * 4.0 + p * 2.0, Color(S.FIRE, (0.07 - i * 0.015) * _ready_k + _glow * 0.05))
		draw_circle(c, rr + 3.0, Color(S.INK, 0.35))
		draw_circle(c, rr - 2.0, Color(S.PANEL, 0.72))
		draw_arc(c, rr, 0.0, TAU, 48, Color(S.IVORY, 0.14), 4.0, true)
		if llama > 0.0:
			var col := S.GOLD.lerp(S.FIRE, llama)
			draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * llama, maxi(6, int(56 * llama)), col, 4.0, true)
			if not lit_ready:
				var tip := c + Vector2(cos(-PI * 0.5 + TAU * llama), sin(-PI * 0.5 + TAU * llama)) * rr
				draw_circle(tip, 3.0, col.lightened(0.3))
		var icol := Color(S.IVORY, 0.8).lerp(Color("FFD9A0"), _ready_k)
		var isz := 34.0
		Icons.draw(self, "flame_out" if dead else "lantern", Rect2(c - Vector2(isz, isz) * 0.5 + Vector2(0, 1.5), Vector2(isz, isz)), Color(S.INK, 0.4))
		Icons.draw(self, "flame_out" if dead else "lantern", Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), icol)


# --- chevrons toward the beaches where creatures will land (daytime) ---------------------------------------

class Markers extends Control:
	var points: Array = []
	var k := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if k <= 0.01 or size.x < 240.0 or size.y < 240.0:
			return
		var margin := 54.0
		var inner := Rect2(Vector2(margin, margin + 30.0), size - Vector2(margin * 2.0, margin * 2.0 + 30.0))
		var c := inner.get_center()
		var t := S.now()
		for i in points.size():
			var p: Vector2 = points[i]
			if inner.grow(-6.0).has_point(p):
				continue
			var d := p - c
			if d.length() < 1.0:
				continue
			var sx := (inner.size.x * 0.5) / maxf(absf(d.x), 0.001)
			var sy := (inner.size.y * 0.5) / maxf(absf(d.y), 0.001)
			var e := c + d * minf(sx, sy)
			var dir := d.normalized()
			var pulse := 0.5 + 0.5 * sin(t * 3.0 + i * 1.3)
			var a := k * (0.75 + 0.25 * pulse)
			var push := 4.0 * pulse
			draw_circle(e, 20.0, Color(S.INK, 0.28 * k))
			draw_arc(e, 19.0, 0.0, TAU, 32, Color(S.NYX, 0.45 * a), 1.5, true)
			Icons.draw(self, "enemy", Rect2(e - Vector2(10, 11), Vector2(20, 20)), Color(S.NYX_LIGHT, 0.9 * a))
			var tip := e + dir * (31.0 + push)
			var n := Vector2(-dir.y, dir.x)
			var pts := PackedVector2Array([tip, tip - dir * 10.0 + n * 8.0, tip - dir * 6.0, tip - dir * 10.0 - n * 8.0])
			draw_colored_polygon(pts, Color(S.NYX, a))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers = Markers.new()
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_markers)
	_build_coins()
	_build_status()
	_vitals = Vitals.new()
	add_child(_vitals)
	_build_respawn()
	_build_hint()
	_layout()
	modulate.a = 0.0
	Game.coins_changed.connect(_on_coins)


func _build_coins() -> void:
	_coin_row = HBoxContainer.new()
	_coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_row.add_theme_constant_override("separation", 10)
	_coin_row.position = Vector2(26, 20)
	add_child(_coin_row)
	_coin_icon = W.IconView.new("coin", S.COIN, 34.0)
	_coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin_row.add_child(_coin_icon)
	_coin_label = S.label("0", S.CINZEL_BOLD, 32, S.IVORY, 1, 5)
	_coin_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin_row.add_child(_coin_label)
	_coin_target = Game.coins
	_coin_shown = Game.coins
	_coin_label.text = str(Game.coins)


func _build_status() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_top = 16.0
	add_child(col)
	_status = col
	var r1 := HBoxContainer.new()
	r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r1.alignment = BoxContainer.ALIGNMENT_CENTER
	r1.add_theme_constant_override("separation", 10)
	col.add_child(r1)
	_phase_icon = W.IconView.new("sun", S.GOLD, 22.0)
	_phase_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(_phase_icon)
	_phase_label = S.label("DÍA 1", S.CINZEL, 21, S.IVORY, 6, 5)
	r1.add_child(_phase_label)
	var r2 := HBoxContainer.new()
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	r2.add_theme_constant_override("separation", 8)
	col.add_child(r2)
	_faro_icon = W.IconView.new("pharos", Color("F2D7A0"), 22.0)
	_faro_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(_faro_icon)
	_faro_bar = W.Bar.new(210.0, 6.0, Color("F2D7A0"))
	_faro_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(_faro_bar)
	_foes_box = HBoxContainer.new()
	_foes_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foes_box.add_theme_constant_override("separation", 5)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foes_box.add_child(gap)
	var fi := W.IconView.new("enemy", S.NYX_LIGHT, 17.0)
	fi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foes_box.add_child(fi)
	_foes_label = S.label("0", S.CINZEL_BOLD, 18, S.IVORY, 0, 4)
	_foes_box.add_child(_foes_label)
	r2.add_child(_foes_box)
	_boss_box = VBoxContainer.new()
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.add_theme_constant_override("separation", 4)
	col.add_child(_boss_box)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.add_child(sp)
	_boss_label = S.label("HIDRA DE LA NOCHE", S.CINZEL, 16, S.NYX_LIGHT, 5, 5)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_label)
	var br := HBoxContainer.new()
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_theme_constant_override("separation", 10)
	_boss_box.add_child(br)
	br.add_child(_diamond_icon())
	_boss_bar = W.Bar.new(460.0, 9.0, S.NYX)
	_boss_bar.trail_color = Color(1.0, 0.92, 1.0, 0.7)
	_boss_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(_boss_bar)
	br.add_child(_diamond_icon())
	_boss_box.modulate.a = 0.0
	_boss_box.visible = false


func _diamond_icon() -> Control:
	var d := W.IconView.new("diamond", S.NYX, 10.0)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return d


func _build_respawn() -> void:
	_respawn = HBoxContainer.new()
	_respawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_respawn.alignment = BoxContainer.ALIGNMENT_CENTER
	_respawn.add_theme_constant_override("separation", 12)
	_respawn.anchor_left = 0.0
	_respawn.anchor_right = 1.0
	_respawn.anchor_top = 0.6
	_respawn.anchor_bottom = 0.6
	add_child(_respawn)
	var l := S.label("La llama vuelve en", S.ITALIC, 27, S.IVORY, 0, 5)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_respawn.add_child(l)
	_respawn_num = S.label("7", S.CINZEL_BOLD, 44, S.GOLD, 0, 6)
	_respawn_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_respawn_num.custom_minimum_size = Vector2(34, 0)
	_respawn.add_child(_respawn_num)
	_respawn.modulate.a = 0.0
	_respawn.visible = false


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := S.panel(0.55, 10, Color(S.GOLD, 0.35), 14.0)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_hint.add_theme_stylebox_override("panel", sb)
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_holder = Control.new()
	_hint_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hint_holder)
	_hint_holder.add_child(_hint)
	_hint_rows = VBoxContainer.new()
	_hint_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_rows.add_theme_constant_override("separation", 5)
	_hint.add_child(_hint_rows)
	_hint.visible = false
	_hint.modulate.a = 0.0


func _fill_hint() -> void:
	_hint_rev = G.revision
	for c in _hint_rows.get_children():
		_hint_rows.remove_child(c)
		c.queue_free()
	var title := S.label("CÓMO SE JUEGA", S.CINZEL, 13, S.GOLD, 4, 3)
	_hint_rows.add_child(title)
	var rows := [
		["move", "Moverse"],
		["attack", "Atacar con el ancla"],
		["bash", "Destello de la lente"],
		["dodge", "Embestida de vapor"],
		["power", "Haz del Faro"],
		["interact", "Mantener: construir y usar"],
	]
	if G.device == "touch":
		# The thumb buttons carry their own icons: only what they can't say, so the panel stays clear of them.
		rows = [
			["move", "Arrastra a la izquierda para moverte"],
			["interact", "Mantén «Usar» para construir"],
		]
	for r in rows:
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 10)
		var cell := HBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.custom_minimum_size = Vector2(70 if G.device != "kb" else 88, 0)
		cell.add_child(G.new().setup(r[0], 22.0))
		h.add_child(cell)
		h.add_child(S.label(r[1], S.GARAMOND, 17, Color(S.IVORY, 0.92), 0, 3))
		_hint_rows.add_child(h)
	var foot := S.label("Al terminar, toca el cuerno de la plaza\npara llamar a la noche.", S.ITALIC, 15, Color(S.IVORY, 0.72), 0, 3)
	_hint_rows.add_child(foot)


## Places the clusters; touch moves the vitals to the top so thumbs don't cover them.
func _layout() -> void:
	if touch_layout:
		_vitals.anchor_top = 0.0
		_vitals.anchor_bottom = 0.0
		_vitals.position = Vector2(14, 64)
		_hint.offset_top = 86.0
	else:
		_vitals.anchor_top = 1.0
		_vitals.anchor_bottom = 1.0
		_vitals.offset_top = -24.0 - 80.0
		_vitals.offset_bottom = -24.0
		_vitals.offset_left = 20.0
		_vitals.offset_right = 20.0 + 330.0
		_hint.offset_top = 20.0
	_hint.offset_right = -22.0


func set_touch_layout(on: bool) -> void:
	if on != touch_layout:
		touch_layout = on
		_layout()


func set_phase(p: int) -> void:
	_phase = p
	if p != Game.Phase.DAY and _hint_on:
		_hide_hint()
	if p == Game.Phase.DAY and not _hint_done and not _hint_on:
		_show_hint()


func _show_hint() -> void:
	_hint_on = true
	_hint_t = 0.0
	_fill_hint()
	_hint.visible = true
	var tw := S.tween(_hint)
	tw.tween_interval(1.6)
	tw.tween_property(_hint, "modulate:a", 1.0, 0.6)


func _hide_hint() -> void:
	_hint_on = false
	_hint_done = true
	var tw := S.tween(_hint)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: _hint.visible = false)


func show_hud(on: bool) -> void:
	if on == _vis_on and _vis_tw != null:
		return
	_vis_on = on
	if _vis_tw and _vis_tw.is_valid():
		_vis_tw.kill()
	_vis_tw = S.tween(self)
	_vis_tw.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.35 if on else 0.25)


## Screen rectangles the world prompt must not cover (top status, the controls hint, dracmas, vitals).
func reserved_rects() -> Array:
	var out: Array = []
	if modulate.a < 0.05:
		return out
	out.append(_status.get_global_rect().grow(6.0))
	out.append(_coin_row.get_global_rect().grow(6.0))
	out.append(_vitals.get_global_rect())
	if _hint.visible and _hint.modulate.a * _hint_holder.modulate.a > 0.05:
		out.append(_hint.get_global_rect().grow(8.0))
	return out


func _on_coins(value: int, delta: int) -> void:
	_coin_target = value
	if delta > 0:
		_coin_bump = 1.0
		_float_gain(delta)
	elif delta < 0:
		_coin_shown = value
		_coin_bump = -0.35
	else:
		_coin_shown = value
	if delta <= 2:
		_coin_shown = value


func _float_gain(n: int) -> void:
	var l := S.label("+%d" % n, S.CINZEL_BOLD, 24, S.COIN, 0, 5)
	add_child(l)
	l.position = _coin_row.position + Vector2(_coin_row.size.x + 10.0, 2.0)
	var tw := S.tween(l)
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 30.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.75)
	tw.chain().tween_callback(l.queue_free)


func _phase_text() -> Array:
	match _phase:
		Game.Phase.DAY:
			return ["DÍA %d" % (Game.night + 1), "sun", S.GOLD]
		Game.Phase.DUSK:
			return ["NOCHE %d · %d" % [Game.night + 1, Data.NIGHTS], "moon", Color("C9B8FF")]
		Game.Phase.NIGHT:
			return ["NOCHE %d · %d" % [Game.night, Data.NIGHTS], "moon", Color("C9B8FF")]
		Game.Phase.DAWN, Game.Phase.BLESSING:
			return ["AMANECER", "sun", Color("FFB98A")]
	return ["", "sun", S.GOLD]


## A faint dark band behind the top-centre status, so it stays legible over the bright lantern room or a
## sunlit plaza without drawing a box.
func _draw() -> void:
	if _status == null:
		return
	var r := _status.get_rect()
	S.draw_soft_band(self, Rect2(r.position.x - 70.0, r.position.y - 14.0, r.size.x + 140.0, r.size.y + 26.0), Color(S.INK, 0.26), 0.3, 0.35)


func _process(delta: float) -> void:
	if modulate.a <= 0.0:
		return
	var rd := S.rdelta(delta)
	queue_redraw()
	# Dracmas.
	if absf(_coin_shown - _coin_target) > 0.01:
		_coin_shown = move_toward(_coin_shown, _coin_target, maxf(6.0, absf(_coin_target - _coin_shown) * 3.0) * rd)
	var ct := str(int(round(_coin_shown)))
	if _coin_label.text != ct:
		_coin_label.text = ct
	_coin_bump = move_toward(_coin_bump, 0.0, rd * 3.2)
	var cb := 1.0 + 0.22 * maxf(0.0, _coin_bump) * _coin_bump - 0.05 * maxf(0.0, -_coin_bump)
	_coin_icon.pivot_offset = _coin_icon.size * 0.5
	_coin_icon.scale = Vector2(cb, cb)
	_coin_label.pivot_offset = Vector2(0, _coin_label.size.y * 0.5)
	_coin_label.scale = Vector2(cb, cb)
	# Phase title.
	var pt := _phase_text()
	if _phase_label.text != pt[0]:
		_phase_label.text = pt[0]
		_phase_icon.set_icon(pt[1], pt[2])
	# The Faro.
	var ph: Node = Game.pharos if Game.pharos and is_instance_valid(Game.pharos) else null
	if ph:
		var v: float = clampf(ph.hp / maxf(1.0, ph.max_hp), 0.0, 1.0)
		if _faro_last >= 0.0 and v < _faro_last - 0.0001:
			_faro_hurt = 1.0
		_faro_last = v
		_faro_bar.set_value(v)
		var low := v < 0.35
		_faro_bar.color = S.DANGER if low else Color("F2D7A0")
	_faro_hurt = maxf(0.0, _faro_hurt - rd * 1.5)
	var fp := 0.5 + 0.5 * sin(S.now() * 12.0)
	var fcol := Color("F2D7A0").lerp(S.DANGER, _faro_hurt * fp)
	if fcol != _faro_icon.color:
		_faro_icon.color = fcol
		_faro_icon.queue_redraw()
	# Creatures left tonight.
	var night := _phase == Game.Phase.NIGHT
	_foes_box.visible = night
	if night and Game.main and Game.main.waves:
		var n: int = Game.main.waves.remaining()
		var s := str(n)
		if _foes_label.text != s:
			_foes_label.text = s
	_tick_boss(rd)
	# Fanós.
	var hero: Node = Game.hero if Game.hero and is_instance_valid(Game.hero) else null
	if hero:
		_vitals.tick(hero, rd)
		_tick_respawn(hero, rd)
	# First-day hint (steps aside while a centre banner is up).
	_hint_holder.modulate.a = move_toward(_hint_holder.modulate.a, 1.0 - clampf(hint_dim, 0.0, 1.0), rd * 4.0)
	if _hint_on:
		if _hint_rev != G.revision:
			_fill_hint()
		if not Game.paused:
			_hint_t += rd
		if _hint_t > 26.0:
			_hide_hint()
	# Beaches of the coming night.
	var day := _phase == Game.Phase.DAY
	_markers.k = move_toward(_markers.k, 1.0 if day else 0.0, rd * 2.0)
	if _markers.k > 0.0:
		_markers.points.clear()
		var cam: Camera3D = Game.main.rig.cam if Game.main and Game.main.rig else null
		if cam and Game.main.markers:
			for wp in Game.main.markers.shown_positions():
				var p3: Vector3 = wp
				var sp := cam.unproject_position(p3)
				if cam.is_position_behind(p3):
					sp = size - sp
					sp = sp + (sp - size * 0.5) * 100.0
				_markers.points.append(sp)
		_markers.queue_redraw()


func _tick_boss(rd: float) -> void:
	var boss: Node = null
	if Game.main and Game.main.waves and Game.main.waves.boss and is_instance_valid(Game.main.waves.boss):
		boss = Game.main.waves.boss
	var alive: bool = boss != null and boss.alive
	if boss and boss != _boss_ref:
		_boss_ref = boss
		var nm: String = boss.display_name if "display_name" in boss and boss.display_name != "" else "Hidra de la Noche"
		_boss_label.text = nm.to_upper()
		_boss_bar.set_value(1.0, true)
	_boss_k = move_toward(_boss_k, 1.0 if alive else 0.0, rd * (1.5 if alive else 0.8))
	_boss_box.visible = _boss_k > 0.0
	_boss_box.modulate.a = S.ease_out(_boss_k)
	if boss:
		_boss_bar.set_value(clampf(boss.hp / maxf(1.0, boss.max_hp), 0.0, 1.0))


func _tick_respawn(hero: Node, rd: float) -> void:
	var dead: bool = hero.state == Hero.S.DEAD and Game.phase != Game.Phase.DEFEAT
	_respawn_k = move_toward(_respawn_k, 1.0 if dead else 0.0, rd * 3.0)
	_respawn.visible = _respawn_k > 0.0
	_respawn.modulate.a = S.ease_out(_respawn_k)
	if dead:
		var n := maxi(1, int(ceil(hero.respawn_t)))
		if n != _respawn_last:
			_respawn_last = n
			_respawn_num.text = str(n)
			_respawn_num.pivot_offset = _respawn_num.size * 0.5
			_respawn_num.scale = Vector2(1.25, 1.25)
			var tw := S.tween(_respawn_num)
			tw.tween_property(_respawn_num, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_respawn_last = -1
