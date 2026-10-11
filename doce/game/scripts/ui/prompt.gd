extends Control
## The world-anchored interaction prompt: floats above whatever Heracles can use (an altar, a cat, the boulder,
## the boat). Minimal: the thing's name in small capitals, the interact key (keyboard or pad, whichever was used
## last) inside a ring that fills while a hold is in progress, the verb, and an optional short italic line.
## No box: a soft dark band keeps it legible over the bright world. Reads Game.hero.interact_target and its
## interact_info() -> {title, verb, desc, progress (0..1, -1 none), anchor (Vector3)} (+ optional `action`, the
## key shown: "interact" by default, and `accent`: "gold" (pulses) or "danger").
## The wrestle (Hero.is_grappling(), the grapple protocol of docs/COMBAT.md 6.6) shows the same prompt over the
## struggle: the beast's name, "Aprieta" with the interact key, its ring filled with the wrestle's progress
## (target.grapple_progress()); gold and pulsing while a squeeze window is open (Hero.grapple_window_left()),
## "Aguanta" with the guard key while the beast winds up a thrash (target.telegraph_left()).

const S := preload("res://scripts/ui/style.gd")
const G := preload("res://scripts/ui/glyphs.gd")

var enabled := true
var hud: Control = null # the HUD, whose clusters the prompt keeps clear of
var dim := 0.0 # 0..1 while a centre banner is up
var _target: Object = null
var _info := {}
var _shown := 0.0
var _pop := 0.0
var _point := Vector2.INF
var _pos := Vector2.INF
var _progress := 0.0
var _flash := 0.0
## Debug / screenshots: a fixed prompt without a hero.
var sim_info := {}
var sim_point := Vector2.INF


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func has_target() -> bool:
	return _target != null or not sim_info.is_empty()


func _camera() -> Camera3D:
	var c = Game.camera
	if c != null and is_instance_valid(c) and "cam" in c and c.cam != null:
		return c.cam
	return get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	var rd := S.rdelta(delta)
	var tgt: Object = null
	var h = Game.hero
	var wrestle := {}
	if enabled and h != null and is_instance_valid(h) and h.has_method("is_grappling") and bool(h.call("is_grappling")):
		wrestle = _wrestle_info(h)
		if not wrestle.is_empty():
			tgt = h.get("grapple_target")
	elif enabled and h != null and is_instance_valid(h) and "interact_target" in h:
		var it = h.get("interact_target")
		if it != null and is_instance_valid(it) and it.has_method("interact_info"):
			tgt = it
	if tgt != _target:
		if tgt != null and _target != null:
			_pop = 1.0
		_target = tgt
	var info := {}
	if not wrestle.is_empty():
		info = wrestle
	elif _target != null:
		info = _target.call("interact_info")
	elif enabled and not sim_info.is_empty():
		info = sim_info
	if not info.is_empty():
		_info = info
		_shown = minf(1.0, _shown + rd / 0.16)
		var p := float(info.get("progress", -1.0))
		if p >= 0.999 and _progress < 0.999:
			_flash = 1.0
		_progress = p
		_point = _anchor_point(info)
	else:
		_shown = maxf(0.0, _shown - rd / 0.14)
	_pop = maxf(0.0, _pop - rd * 6.0)
	_flash = maxf(0.0, _flash - rd * 3.0)
	if _shown > 0.0 or _pos.is_finite():
		queue_redraw()


## The wrestle's prompt (see the header): over the struggle, between the two heads.
func _wrestle_info(h: Object) -> Dictionary:
	var t = h.get("grapple_target")
	if t == null or not is_instance_valid(t) or not (t is Node3D):
		return {}
	var hp3: Vector3 = (h as Node3D).global_position if h is Node3D else (t as Node3D).global_position
	var anchor: Vector3 = (hp3 + (t as Node3D).global_position) * 0.5 + Vector3(0, 2.7, 0)
	var nm := String(t.get("display_name")) if "display_name" in t else ""
	var prog := -1.0
	if t.has_method("grapple_progress"):
		prog = float(t.call("grapple_progress"))
	var window: float = float(h.call("grapple_window_left")) if h.has_method("grapple_window_left") else 0.0
	var thrash: float = float(t.call("telegraph_left")) if t.has_method("telegraph_left") else 0.0
	if thrash > 0.0 and window <= 0.0:
		return {"title": nm, "verb": "¡Aguanta!", "desc": "", "progress": prog, "anchor": anchor, "action": "guard", "accent": "danger"}
	if window > 0.0:
		return {"title": nm, "verb": "¡Aprieta!", "desc": "", "progress": prog, "anchor": anchor, "action": "interact", "accent": "gold"}
	return {"title": nm, "verb": "Aprieta", "desc": "", "progress": prog, "anchor": anchor, "action": "interact", "accent": "wait"}


func _anchor_point(info: Dictionary) -> Vector2:
	if sim_point.is_finite() and _target == null:
		return sim_point
	var anchor: Vector3
	if info.has("anchor"):
		anchor = info["anchor"]
	elif _target is Node3D:
		anchor = (_target as Node3D).global_position + Vector3(0, 1.8, 0)
	else:
		return Vector2.INF
	var cam := _camera()
	if cam == null or cam.is_position_behind(anchor):
		return Vector2.INF
	return cam.unproject_position(anchor)


## Layout of the prompt at its anchor; returns [rect, title, verb, desc, caps, cap_h].
func _layout() -> Array:
	var title := String(_info.get("title", "")).to_upper()
	var verb := String(_info.get("verb", "Usar"))
	var desc := String(_info.get("desc", ""))
	var caps := G.caps_for(String(_info.get("action", "interact")))
	var cap_h := 26.0
	var ft := S.font(S.CINZEL)
	var fv := S.font(S.CINZEL)
	var fd := S.font(S.ITALIC)
	var tw := S.tracked_width(ft, title, 13, 3.0)
	var ring := cap_h + 12.0
	var vw := ring + 10.0 + fv.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var dw := fd.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x if desc != "" else 0.0
	var w := maxf(maxf(tw, vw), dw)
	var h := 18.0 + ring + (22.0 if desc != "" else 0.0)
	return [Rect2(0, 0, w, h), title, verb, desc, caps, cap_h]


func _avoid(pos: Vector2, sz: Vector2) -> Vector2:
	pos.x = clampf(pos.x, 12.0, maxf(12.0, size.x - sz.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, size.y - sz.y - 12.0))
	if hud == null or not hud.has_method("reserved_rects"):
		return pos
	for rr in hud.call("reserved_rects"):
		var r: Rect2 = rr
		if Rect2(pos, sz).intersects(r):
			var up := Vector2(pos.x, r.position.y - sz.y - 6.0)
			var right := Vector2(r.end.x + 6.0, pos.y)
			pos = up if absf(up.y - pos.y) < absf(right.x - pos.x) else right
	return pos


func _draw() -> void:
	if _shown <= 0.0 or not _point.is_finite():
		_pos = Vector2.INF
		return
	var lay := _layout()
	var r: Rect2 = lay[0]
	var target := Vector2(_point.x - r.size.x * 0.5, _point.y - r.size.y - 10.0)
	target = _avoid(target, r.size)
	_pos = target if not _pos.is_finite() else _pos.lerp(target, 0.35)
	var accent := String(_info.get("accent", ""))
	var a := S.ease_out(_shown) * (1.0 - clampf(dim, 0.0, 1.0))
	if accent == "wait":
		a *= 0.62 # between the wrestle's beats the prompt rests, dimmed
	var o := _pos.round() + Vector2(0, 6.0 * (1.0 - S.ease_out(_shown)))
	var sc := 1.0 - 0.04 * _pop
	if accent == "gold" or accent == "danger":
		sc *= 1.0 + 0.07 * (0.5 + 0.5 * sin(S.now() * 18.0))
	draw_set_transform(o + r.size * 0.5, 0.0, Vector2(sc, sc))
	var c0 := -r.size * 0.5
	S.draw_soft_band(self, Rect2(c0 - Vector2(40, 16), r.size + Vector2(80, 30)), Color(S.INK, 0.42 * a), 0.3, 0.32)
	var title: String = lay[1]
	var verb: String = lay[2]
	var desc: String = lay[3]
	var caps: Array = lay[4]
	var cap_h: float = lay[5]
	var y := c0.y
	if title != "":
		S.draw_tracked(self, S.font(S.CINZEL), title, 13, Vector2(0, y + 12.0), 3.0, Color(S.CLAY_LIGHT.lerp(S.IVORY, 0.35), a), 1, 4)
	y += 18.0
	# key in a ring + verb, centred together
	var fv := S.font(S.CINZEL)
	var ring := cap_h + 12.0
	var vw := fv.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var row_w := ring + 10.0 + vw
	var rc := Vector2(-row_w * 0.5 + ring * 0.5, y + ring * 0.5)
	draw_arc(rc, ring * 0.5 - 1.0, 0.0, TAU, 40, Color(S.INK, 0.5 * a), 4.0, true)
	draw_arc(rc, ring * 0.5 - 1.0, 0.0, TAU, 40, Color(S.IVORY, 0.2 * a), 2.0, true)
	if accent == "gold" or accent == "danger":
		# the beat: a bright ring round the key, a halo pulsing out from it
		var ac := S.GOLD if accent == "gold" else S.DANGER
		var pulse := fmod(S.now() * 2.6, 1.0)
		draw_arc(rc, ring * 0.5 + 2.0, 0.0, TAU, 40, Color(ac, a), 3.0, true)
		draw_arc(rc, ring * 0.5 + 3.0 + pulse * 12.0, 0.0, TAU, 40, Color(ac, a * 0.6 * (1.0 - pulse)), 2.0, true)
	if _progress > 0.0:
		var pc := S.GOLD.lerp(Color.WHITE, _flash * 0.6)
		draw_arc(rc, ring * 0.5 - 1.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_progress, 0.0, 1.0), maxi(8, int(48 * _progress)), Color(pc, a), 3.0, true)
	if not caps.is_empty():
		var cap: Array = caps[0]
		var cw := G.cap_width(cap, cap_h * 0.82)
		G.draw_cap(self, cap, Rect2(rc.x - cw * 0.5, rc.y - cap_h * 0.41, cw, cap_h * 0.82), Color(S.IVORY, a), 0.0 if cap[0] == "icon" else 0.5 * a)
	var vcol := S.DANGER.lerp(S.IVORY, 0.25) if accent == "danger" else S.GOLD
	S.draw_text(self, fv, verb, 20, Vector2(rc.x + ring * 0.5 + 10.0, rc.y + 7.0), Color(vcol, a), 0, 5)
	y += ring
	if desc != "":
		S.draw_text(self, S.font(S.ITALIC), desc, 16, Vector2(0, y + 17.0), Color(S.IVORY, 0.82 * a), 1, 4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# a small diamond pointing down toward the anchor when the prompt sits right above it
	if absf(_point.x - (o.x + r.size.x * 0.5)) < r.size.x * 0.5 + 20.0 and _point.y > o.y + r.size.y:
		var tip := Vector2(clampf(_point.x, o.x + 6.0, o.x + r.size.x - 6.0), o.y + r.size.y + 8.0)
		S.draw_diamond(self, tip, 3.5, Color(S.CLAY_LIGHT, 0.85 * a))
