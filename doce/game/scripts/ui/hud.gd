extends Control
## The in-game HUD. Small and quiet:
##  - vitals, bottom-left: a black-glaze medallion with Heracles' Corinthian helmet (the lion's head once he wears
##    the skin) and a slim health bar; it flashes and pulses when hurt or low;
##  - stamina: a ring beside the hero (projected from the 3D position) that only appears while stamina is
##    being spent or refilling, and fades once full; red while the hero is winded;
##  - the boss bar, top-centre: the beast's name and a long bar with notches at its phases (66 % and 33 %);
##  - the lock-on reticle on the target (four bronze arrowheads closing in, turning slowly);
##  - the chain spear's mark on what it would hook if thrown now (Hero.chain_candidate: a bronze ring rimmed by
##    four short ticks, with the chain key beside it), hidden while the sword swings or the thing is within reach of
##    it; on the lock target only the key, beside the reticle.
## Reads Game.hero (hp, max_hp, stamina, max_stamina, alive, outfit / _exhausted when present, chain_candidate,
## state_name()), Game.camera.cam, Game.boss_started / boss_ended and Game.lock_changed. Debug values can be forced
## with sim_* (uitest).

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

const RETICLE_R := 24.0
const BOSS_NOTCHES := [0.33, 0.66]

var _vitals: Vitals
var _boss: BossBar
var _shown := 0.0
var _vis_on := false
var _vis_tw: Tween
var _lock: Node3D = null
var _lock_k := 0.0
var _lock_in := 0.0
var _lock_pos := Vector2.ZERO
var _lock_seen := false
var _stam_k := 0.0
var _stam_full_t := 0.0
var _stam_pos := Vector2.INF
var _stam_val := 1.0
var _stam_last := -1.0
var _stam_red := 0.0
## Debug / screenshots: force values when the hero is missing or for a mock-up.
var _drawn := false
var sim_stamina := -1.0
var sim_lock_pos := Vector2.INF
var sim_chain_pos := Vector2.INF
var _chain: Node3D = null
var _chain_k := 0.0
var _chain_in := 0.0
var _chain_pos := Vector2.INF
var _chain_on_lock := false


# --- vitals: medallion + health bar ------------------------------------------------------------------------

class Vitals extends Control:
	const EMB := 58.0
	var bar: W.Bar
	var stam_bar: W.Bar
	var icon := "helmet"
	var hp := 1.0
	var hurt := 0.0
	var low := false
	var dead := false
	var _stam_k := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(340, 70)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar = W.Bar.new(250.0, 9.0, S.HEALTH)
		bar.trail_color = Color(1.0, 0.86, 0.72, 0.85)
		bar.position = Vector2(EMB + 18, 26)
		add_child(bar)
		stam_bar = W.Bar.new(170.0, 5.0, S.STAMINA)
		stam_bar.position = Vector2(EMB + 18, 44)
		stam_bar.modulate.a = 0.0
		add_child(stam_bar)

	## `stam` < 0 hides the fallback stamina bar (the ring beside the hero shows it instead).
	func tick(h: float, rd: float, stam: float, winded: bool) -> void:
		if h < hp - 0.0001:
			hurt = 1.0
		hp = h
		bar.set_value(h)
		low = h < 0.3 and not dead
		var pulse := 0.5 + 0.5 * sin(S.now() * 6.5)
		bar.color = S.HEALTH.lerp(Color("FF9C84"), pulse * 0.5) if low else S.HEALTH
		bar.queue_redraw()
		hurt = maxf(0.0, hurt - rd * 2.2)
		_stam_k = move_toward(_stam_k, 1.0 if stam >= 0.0 else 0.0, rd * 4.0)
		stam_bar.modulate.a = _stam_k
		if stam >= 0.0:
			stam_bar.set_value(stam)
			stam_bar.color = S.DANGER if winded else S.STAMINA
		modulate.a = lerpf(modulate.a, 0.5 if dead else 1.0, minf(1.0, rd * 5.0))
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(EMB * 0.5 + 2.0, size.y * 0.5)
		var shake := Vector2(sin(S.now() * 60.0), cos(S.now() * 47.0)) * 2.5 * hurt
		c += shake
		var rr := EMB * 0.5
		draw_circle(c + Vector2(0, 2), rr + 2.0, Color(S.INK, 0.35))
		draw_circle(c, rr, Color(S.PANEL, 0.82))
		var ring := S.CLAY.lerp(S.DANGER, maxf(hurt, 0.6 if low else 0.0))
		draw_arc(c, rr - 2.0, 0.0, TAU, 48, ring, 2.5, true)
		draw_arc(c, rr - 6.5, 0.0, TAU, 48, Color(S.IVORY, 0.18), 1.0, true)
		# meander ticks around the rim: eight tiny keys
		for i in 8:
			var a := TAU * float(i) / 8.0 + PI / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (rr - 2.0), c + d * (rr + 3.0), Color(ring, 0.8), 2.0, true)
		var isz := EMB * 0.68
		var ir := Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz))
		Icons.draw(self, icon, Rect2(ir.position + Vector2(0, 1.5), ir.size), Color(S.INK, 0.5))
		Icons.draw(self, icon, ir, S.IVORY.lerp(Color("FFB0A0"), hurt))
		# end caps of the bar: two small diamonds
		var b := bar.position
		S.draw_diamond(self, Vector2(b.x - 7.0, b.y + bar.size.y * 0.5), 3.5, Color(S.CLAY_LIGHT, 0.9))
		S.draw_diamond(self, Vector2(b.x + bar.size.x + 7.0, b.y + bar.size.y * 0.5), 3.5, Color(S.CLAY_LIGHT, 0.9))


# --- boss bar ----------------------------------------------------------------------------------------------

class BossBar extends Control:
	var bar: W.Bar
	var title := ""
	var boss: Node = null
	var k := 0.0
	var fill := 0.0
	var on := false
	var victory := false
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar = W.Bar.new(600.0, 10.0, S.BOSS)
		bar.notches = BOSS_NOTCHES
		bar.trail_color = Color(1.0, 0.9, 0.8, 0.85)
		add_child(bar)

	func start(n: String, b: Node) -> void:
		title = n.to_upper()
		boss = b
		on = true
		victory = false
		fill = 0.0
		_t = 0.0
		bar.set_value(0.0, true)

	func stop(won: bool) -> void:
		on = false
		victory = won

	func ratio() -> float:
		if boss == null or not is_instance_valid(boss):
			return 0.0 if victory else bar.value
		if "hp" in boss and "max_hp" in boss:
			return clampf(float(boss.get("hp")) / maxf(1.0, float(boss.get("max_hp"))), 0.0, 1.0)
		if boss.has_method("health_ratio"):
			return clampf(float(boss.call("health_ratio")), 0.0, 1.0)
		return 1.0

	func tick(rd: float) -> void:
		_t += rd
		k = move_toward(k, 1.0 if on else 0.0, rd * (1.6 if on else 0.7))
		visible = k > 0.0
		if not visible:
			return
		var w := clampf(size.x * 0.46, 380.0, 640.0)
		bar.size = Vector2(w, 10.0)
		bar.custom_minimum_size = bar.size
		bar.position = Vector2((size.x - w) * 0.5, 62.0)
		var target := ratio()
		# the bar fills up once when the fight starts, then follows the beast's health
		fill = move_toward(fill, 1.0, rd * 0.9)
		bar.set_value(minf(target, S.ease_out(fill)), fill < 1.0)
		modulate.a = S.ease_out(k)
		queue_redraw()

	func _draw() -> void:
		var b := bar.position
		var w := bar.size.x
		var cy := b.y + 5.0
		S.draw_soft_band(self, Rect2(b.x - 100.0, b.y - 54.0, w + 200.0, 88.0), Color(S.INK, 0.32), 0.25, 0.35)
		var f := S.font(S.CINZEL)
		var rise := -6.0 * (1.0 - S.ease_out(k))
		S.draw_tracked(self, f, title, 21, Vector2(size.x * 0.5, b.y - 15.0 + rise), 7.0, Color(S.IVORY, 0.95), 1, 5)
		# end caps: a diamond and a hairline flourish on each side
		for side: float in [-1.0, 1.0]:
			var x := b.x - 13.0 if side < 0.0 else b.x + w + 13.0
			S.draw_diamond(self, Vector2(x, cy), 7.0, Color(S.INK, 0.6))
			S.draw_diamond(self, Vector2(x, cy), 5.0, S.CLAY_LIGHT)
			for i in 4:
				var x0 := x + side * (10.0 + i * 9.0)
				draw_line(Vector2(x0, cy), Vector2(x0 + side * 6.0, cy), Color(S.CLAY_LIGHT, 0.7 - 0.16 * i), 1.5, true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals = Vitals.new()
	add_child(_vitals)
	_vitals.anchor_top = 1.0
	_vitals.anchor_bottom = 1.0
	_vitals.offset_left = 22.0
	_vitals.offset_right = 22.0 + 340.0
	_vitals.offset_top = -22.0 - 70.0
	_vitals.offset_bottom = -22.0
	_boss = BossBar.new()
	_boss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boss.visible = false
	add_child(_boss)
	modulate.a = 0.0
	if Game.has_signal("boss_started"):
		Game.boss_started.connect(_on_boss_started)
		Game.boss_ended.connect(_on_boss_ended)
	if Game.has_signal("lock_changed"):
		Game.lock_changed.connect(_on_lock)


func show_hud(on: bool) -> void:
	if on == _vis_on and _vis_tw != null:
		return
	_vis_on = on
	if _vis_tw and _vis_tw.is_valid():
		_vis_tw.kill()
	_vis_tw = S.tween(self)
	_vis_tw.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.35 if on else 0.25)


func _on_boss_started(n: String, b: Node) -> void:
	_boss.start(n, b)


func _on_boss_ended(victory: bool) -> void:
	_boss.stop(victory)


func boss_active() -> bool:
	return _boss.on


## Debug (uitour): drop the forced values and the boss bar at once.
func reset_debug() -> void:
	sim_stamina = -1.0
	sim_lock_pos = Vector2.INF
	sim_chain_pos = Vector2.INF
	_chain_k = 0.0
	_lock_k = 0.0
	_stam_k = 0.0
	_boss.on = false
	_boss.k = 0.0
	_boss.boss = null
	_boss.visible = false


func _on_lock(t: Node) -> void:
	var had := _lock != null
	_lock = t as Node3D
	if _lock:
		_lock_in = 0.0
		_lock_seen = false
		S.sfx("ui_lock", -6.0)
	elif had:
		S.sfx("ui_unlock", -8.0)


func _hero() -> Node:
	var h = Game.hero
	return h if h != null and is_instance_valid(h) else null


func _camera() -> Camera3D:
	var c = Game.camera
	if c != null and is_instance_valid(c) and "cam" in c and c.cam != null:
		return c.cam
	return get_viewport().get_camera_3d()


func _project(p: Vector3) -> Vector2:
	var cam := _camera()
	if cam == null or cam.is_position_behind(p):
		return Vector2.INF
	return cam.unproject_position(p)


## Screen rectangles the world prompt keeps clear of.
func reserved_rects() -> Array:
	var out: Array = []
	if modulate.a < 0.05:
		return out
	out.append(_vitals.get_global_rect().grow(6.0))
	if _boss.visible:
		out.append(Rect2(_boss.bar.global_position - Vector2(60, 50), _boss.bar.size + Vector2(120, 66)))
	return out


func _process(delta: float) -> void:
	var rd := S.rdelta(delta)
	var hero := _hero()
	# --- vitals and stamina ---
	var hp := 1.0
	var st := 1.0
	var winded := false
	if hero:
		hp = clampf(float(hero.get("hp")) / maxf(1.0, float(hero.get("max_hp"))), 0.0, 1.0)
		if "stamina" in hero:
			st = clampf(float(hero.get("stamina")) / maxf(1.0, float(hero.get("max_stamina"))), 0.0, 1.0)
		var ex = hero.get("exhausted") if "exhausted" in hero else hero.get("_exhausted")
		winded = ex == true
		_vitals.dead = not bool(hero.get("alive")) if "alive" in hero else false
		var outfit = hero.get("outfit") if "outfit" in hero else ""
		_vitals.icon = "lion" if String(outfit) == "lion" else "helmet"
	if sim_stamina >= 0.0:
		st = sim_stamina
	# stamina shows while it moves or is not full; a moment after it fills it fades
	var changed := _stam_last >= 0.0 and absf(st - _stam_last) > 0.0005
	_stam_last = st
	if st < 0.999 or changed:
		_stam_full_t = 0.0
	else:
		_stam_full_t += rd
	var want := _stam_full_t < 0.9 and modulate.a > 0.01
	_stam_k = move_toward(_stam_k, 1.0 if want else 0.0, rd * (5.0 if want else 2.0))
	_stam_val = lerpf(_stam_val, st, minf(1.0, rd * 14.0))
	_stam_red = move_toward(_stam_red, 1.0 if winded else 0.0, rd * 4.0)
	var ring_at := Vector2.INF
	if hero and hero is Node3D:
		ring_at = _project((hero as Node3D).global_position + Vector3(0, 1.25, 0))
	if sim_stamina >= 0.0 and not ring_at.is_finite():
		ring_at = size * Vector2(0.5, 0.55)
	if ring_at.is_finite():
		var target := ring_at + Vector2(62.0, -34.0)
		_stam_pos = target if not _stam_pos.is_finite() else _stam_pos.lerp(target, 1.0 - exp(-rd * 20.0))
	else:
		_stam_pos = Vector2.INF
	_vitals.tick(hp, rd, st if (not _stam_pos.is_finite() and _stam_k > 0.01) else -1.0, winded)
	# --- boss ---
	_boss.tick(rd)
	# --- lock-on ---
	var lock_ok := _lock != null and is_instance_valid(_lock) and _lock.is_inside_tree()
	if lock_ok and _lock.has_method("is_alive") and not _lock.call("is_alive"):
		lock_ok = false
	var lp := Vector2.INF
	if lock_ok:
		var wp: Vector3 = _lock.call("lock_point") if _lock.has_method("lock_point") else _lock.global_position
		lp = _project(wp)
	if sim_lock_pos.is_finite():
		lp = sim_lock_pos
		lock_ok = true
	if lp.is_finite():
		_lock_pos = lp if not _lock_seen else _lock_pos.lerp(lp, 1.0 - exp(-rd * 30.0))
		_lock_seen = true
	_lock_k = move_toward(_lock_k, 1.0 if (lock_ok and lp.is_finite()) else 0.0, rd * (7.0 if lock_ok else 5.0))
	_lock_in = minf(1.0, _lock_in + rd / 0.22)
	# --- the chain spear's mark ---
	var cand: Node3D = null
	if hero and "chain_candidate" in hero:
		var c = hero.get("chain_candidate")
		if c != null and is_instance_valid(c) and (c as Node3D).is_inside_tree() and c.has_method("chain_point"):
			cand = c as Node3D
	if cand and hero is Node3D:
		var busy := false
		if hero.has_method("state_name"):
			busy = StringName(hero.call("state_name")) in [&"attack", &"charge", &"heavy", &"grapple", &"dead"]
		if busy or (hero as Node3D).global_position.distance_to(cand.global_position) < 3.2:
			cand = null
	if cand != _chain:
		if cand != null:
			_chain_in = 0.0
		_chain = cand if cand != null else _chain
	var cp := Vector2.INF
	if cand != null:
		_chain_on_lock = lock_ok and cand == _lock
		cp = _project(cand.call("chain_point"))
	if sim_chain_pos.is_finite():
		cp = sim_chain_pos
		_chain_on_lock = false
	if cp.is_finite():
		_chain_pos = cp if (_chain_k <= 0.01 or not _chain_pos.is_finite()) else _chain_pos.lerp(cp, 1.0 - exp(-rd * 30.0))
	_chain_k = move_toward(_chain_k, 1.0 if cp.is_finite() else 0.0, rd * (8.0 if cp.is_finite() else 6.0))
	_chain_in = minf(1.0, _chain_in + rd / 0.2)
	if _stam_k > 0.0 or _lock_k > 0.0 or _chain_k > 0.0 or _drawn:
		queue_redraw()
	_drawn = _stam_k > 0.0 or _lock_k > 0.0 or _chain_k > 0.0


func _draw() -> void:
	if _stam_k > 0.01 and _stam_pos.is_finite():
		_draw_stamina(_stam_pos, _stam_k)
	if _lock_k > 0.01:
		_draw_reticle(_lock_pos, _lock_k)
	if _chain_k > 0.01 and _chain_pos.is_finite():
		_draw_chain_mark(_chain_pos, _chain_k)


## The chain spear's mark: a thin bronze ring with four short ticks (unlike the reticle's arrowheads), turning the
## other way, closing in when a new thing is marked; the chain key beside it. On the lock target only the key.
func _draw_chain_mark(c: Vector2, k: float) -> void:
	var a := S.ease_out(k) * 0.92
	var caps := G.caps_for("chain")
	var cap_h := 18.0
	if not _chain_on_lock:
		var r := 11.0 + 14.0 * (1.0 - S.ease_out(_chain_in))
		var spin := -S.now() * 0.6
		var bronze := S.CLAY_LIGHT.lerp(S.GOLD, 0.45)
		draw_arc(c, r, 0.0, TAU, 32, Color(S.INK, 0.45 * a), 3.5, true)
		draw_arc(c, r, 0.0, TAU, 32, Color(bronze, a), 1.6, true)
		for i in 4:
			var ang := spin + TAU * float(i) / 4.0
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * (r + 3.0), c + d * (r + 9.0), Color(S.INK, 0.5 * a), 3.5, true)
			draw_line(c + d * (r + 3.0), c + d * (r + 9.0), Color(bronze, a), 1.8, true)
		draw_circle(c, 2.0, Color(S.IVORY, 0.85 * a))
	if caps.is_empty():
		return
	var cap: Array = caps[0]
	var cw := G.cap_width(cap, cap_h)
	var at := c + (Vector2(RETICLE_R + 14.0, RETICLE_R - 4.0) if _chain_on_lock else Vector2(22.0, 10.0))
	G.draw_cap(self, cap, Rect2(at, Vector2(cw, cap_h)), Color(S.IVORY, a), 0.0 if cap[0] == "icon" else 0.55 * a)


func _draw_stamina(c: Vector2, k: float) -> void:
	var r := 15.0
	var a := S.ease_out(k)
	var col := S.STAMINA.lerp(S.DANGER, _stam_red)
	if _stam_red > 0.0:
		col = col.lerp(Color("FF9C84"), (0.5 + 0.5 * sin(S.now() * 9.0)) * 0.5 * _stam_red)
	draw_circle(c, r + 4.0, Color(S.INK, 0.32 * a))
	draw_arc(c, r, 0.0, TAU, 40, Color(S.INK, 0.55 * a), 5.5, true)
	draw_arc(c, r, 0.0, TAU, 40, Color(S.IVORY, 0.12 * a), 3.5, true)
	if _stam_val > 0.002:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * _stam_val, maxi(6, int(48 * _stam_val)), Color(col, a), 3.5, true)
	S.draw_diamond(self, c, 2.5, Color(col, 0.8 * a))


func _draw_reticle(c: Vector2, k: float) -> void:
	var a := S.ease_out(k)
	var intro := S.ease_out(_lock_in)
	var r := RETICLE_R + 26.0 * (1.0 - intro)
	var spin := S.now() * 0.9
	draw_arc(c, r * 0.6, 0.0, TAU, 40, Color(S.INK, 0.4 * a), 4.0, true)
	draw_arc(c, r * 0.6, 0.0, TAU, 40, Color(S.IVORY, 0.55 * a), 1.5, true)
	for i in 4:
		var ang := spin + TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector2(cos(ang), sin(ang))
		var n := Vector2(-d.y, d.x)
		var tip := c + d * r * 0.8
		var base := c + d * (r + 12.0)
		var pts := PackedVector2Array([tip, base + n * 8.5, base - n * 8.5])
		var off := Vector2(0, 2.0)
		draw_colored_polygon(PackedVector2Array([pts[0] + off, pts[1] + off, pts[2] + off]), Color(S.INK, 0.5 * a))
		draw_colored_polygon(pts, Color(S.CLAY_LIGHT.lerp(S.IVORY, 0.2), a))
		draw_polyline(PackedVector2Array([tip, base + n * 8.5, base - n * 8.5, tip]), Color(S.INK, 0.75 * a), 1.5, true)
	draw_circle(c, 2.6, Color(S.IVORY, 0.9 * a))
