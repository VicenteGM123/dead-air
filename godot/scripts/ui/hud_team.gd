# HudTeam — the MP additions of the HUD (scripts/ui/hud.gd builds it on the first frame of an online co-op game; solo
# never creates it). Same look as the rest of the HUD (Titan One with dark emboss, SVG-rasterised badges, no words):
#   - teammates list, bottom right above the tote board: name (cream) · points (amber tape digits) · hero channel chip
#     (skip 2 / roxy 4 / penny 5 / duke 7 in the hero colour, RECONCILE R8). Downed: the chip turns into the red revive
#     badge, blinking, with a draining bleed-out ring; off-air: the chip shows colour bars and the row dims.
#     Their perks: tiny sponsor-colour dots left of the name (hud_perks.gd drawDots, perks.loadoutOf).
#   - name tags over remote players' heads (RemotePlayer.headPos()), hero colour, scaled / faded with distance, dimmer
#     when a wall is in between; none for downed (the marker replaces it), off-air, hidden or the spectated player.
#   - downed-teammate markers, visible through walls: the revive badge + a ring in the hero colour draining with the
#     bleed-out (blinks the last 5 s), gold while somebody revives; clamped to the screen edge with an arrow when off
#     screen.
#   - own downed ring (replaces the crosshair): big badge + red bleed-out ring, gold revive arc + the reviver's chip.
#   - off-air: a colour-bars bug top left (where the replay bug sits) and a Dymo label "◀ NAME ▶" bottom centre.
# Reads game.net (players, ids, names, colours), game.player.mp (team states, bleed, revive progress) and
# economy.pointsOf(id). Everything lives under hud.stage (hidden with the HUD: hud.hide() during the ending).
extends RefCounted

const CHANNEL := {"skip": 2, "roxy": 4, "penny": 5, "duke": 7}
const COLORS := {"skip": "#FFB870", "roxy": "#FF6FB0", "penny": "#7FD8FF", "duke": "#8A9CFF"}
const BADGE_SVG := '<circle cx="22" cy="22" r="21" fill="#F4F1E8"/><circle cx="22" cy="22" r="17.5" fill="none" stroke="#E23B3B" stroke-width="5"/><rect x="18.5" y="10" width="7" height="24" rx="2" fill="#E23B3B"/><rect x="10" y="18.5" width="24" height="7" rx="2" fill="#E23B3B"/>'
const DARK := "#1A1020"
const TAG_MAX := 40.0
const ROW_H := 36.0

var hud
var game
var H                       # the hud.gd script (static helpers, DrawCtl)
var root: Control
var tagsCtl: Control
var listCtl: Control
var meCtl: Control
var _tags: Array = []       # [{x, y, s, a, name, col}]
var _marks: Array = []      # [{x, y, edge, ang, col, bleed, rev, blink}]
var _rows: Array = []       # [{name, pts, col, ch, state, bleed}]
var _me := {"mode": "", "bleed": 0.0, "rev": -1.0, "revCol": "", "revCh": 0, "name": "", "col": "#FFFFFF"}
var _occ := {}              # id -> {t, hidden}
var _los := {"camera": true, "ignoreTags": 0}
var _losCol = null
var _time := 0.0

func _init(h) -> void:
	hud = h
	game = h.game
	H = h.get_script()
	root = Control.new()
	root.name = "team"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.stage.add_child(root)
	hud.stage.move_child(root, 0)   # behind every other HUD element
	tagsCtl = H.DrawCtl.new(_drawTags, "tags")
	listCtl = H.DrawCtl.new(_drawList, "list")
	meCtl = H.DrawCtl.new(_drawMe, "me")
	for c in [tagsCtl, listCtl, meCtl]:
		root.add_child(c)
	layout(hud.stageW)

func layout(W: float) -> void:
	root.size = Vector2(W, H.REF_H)
	tagsCtl.size = root.size
	listCtl.position = Vector2(W - H.M, H.REF_H - 248.0)
	meCtl.size = root.size

func reset() -> void:
	_tags.clear()
	_marks.clear()
	_rows.clear()
	_occ.clear()
	_me.mode = ""

static func _heroCol(n, id: int, hero) -> String:
	var c = n.colorOf(id) if n != null else ""
	if c is String and c != "" and c != "#FFFFFF":
		return c
	return COLORS.get(hero, "#F6E7C8")

# ------------------------------------------------------------------------------------------------ per frame
func update(dt: float) -> void:
	_time += dt
	var g = game
	var n = g.get("net")
	if n == null or not n.inGame:
		root.visible = false
		return
	root.visible = true
	var me = g.player
	var mp = me.get("mp") if me != null else null
	_buildRows(n, mp)
	_buildWorld(n, mp, dt)
	_buildMe(n, mp, me)
	tagsCtl.queue_redraw()
	listCtl.queue_redraw()
	meCtl.queue_redraw()

func _stateOf(mp, id: int, q) -> int:
	if mp != null:
		var s: int = mp.stateOf(id)
		if s >= 0:
			return s
	if q.get("offAir") == true:
		return 2
	return 1 if q.downed else 0

func _buildRows(n, mp) -> void:
	_rows.clear()
	var E = game.get("economy")
	for q in n.players():
		if q == game.player:
			continue
		var id: int = n.idOf(q)
		var pts = E.pointsOf(id) if E != null and E.has_method("pointsOf") else null
		_rows.append({"name": n.nameOf(id), "pts": int(pts) if (pts is int or pts is float) else -1,
			"col": _heroCol(n, id, q.heroId), "ch": CHANNEL.get(q.heroId, 0), "state": _stateOf(mp, id, q),
			"bleed": mp.bleedOf(id) if mp != null else 0.0, "rev": mp.reviveProgress(id) if mp != null else -1.0,
			"perks": game.perks.loadoutOf(id) if game.get("perks") != null else []})

# Projects a world point to stage px. Returns Vector3(x, y, inFront) (inFront 1 / 0).
func _project(cam: Camera3D, pos: Vector3) -> Vector3:
	var xf := cam.global_transform if cam.is_inside_tree() else cam.transform
	var v: Vector3 = xf.affine_inverse() * pos
	var W: float = hud.stageW
	var vp := cam.get_viewport()
	var sz := vp.get_visible_rect().size if vp != null else Vector2(16, 9)
	var aspect := sz.x / maxf(1.0, sz.y)
	var tanV := tan(deg_to_rad(cam.fov) / 2.0)
	var front := 1.0 if v.z < -0.05 else 0.0
	var z := minf(v.z, -0.05)
	var nx := v.x / (-z * tanV * aspect)
	var ny := v.y / (-z * tanV)
	if front == 0.0:
		# behind the camera: keep the side (turn that way), pin to the bottom edge
		nx = nx * 50.0
		ny = -(absf(ny) + 1.0) * 50.0
	return Vector3((nx * 0.5 + 0.5) * W, (0.5 - ny * 0.5) * H.REF_H, front)

func _buildWorld(n, mp, dt: float) -> void:
	_tags.clear()
	_marks.clear()
	var cam: Camera3D = game.camera
	var R = game.get("render")
	if cam == null or (R != null and R.get("cameraOverride") != null):
		return
	var eye := cam.global_position if cam.is_inside_tree() else cam.position
	var W: float = hud.stageW
	var spec = game.player.get("spectate") if game.player != null else null
	if spec == null and game.player != null and game.player.get("offAir") == true:
		return   # off-air before the ride-along starts: the screen is the power-off black, no world tags over it
	for q in n.players():
		if q == game.player:
			continue
		var id: int = n.idOf(q)
		var st := _stateOf(mp, id, q)
		var col := _heroCol(n, id, q.heroId)
		if st == 2 or q.get("hidden") == true:
			continue
		if st == 1:
			var e = mp.team.get(id) if mp != null else null
			var at: Vector3 = (e.pos if e != null else q.pos) + Vector3(0.0, 1.35, 0.0)
			var pr := _project(cam, at)
			var m := 70.0
			var x := pr.x
			var y := pr.y
			var edge: bool = pr.z == 0.0 or x < m or x > W - m or y < m or y > H.REF_H - m
			var ang := 0.0
			if edge:
				var c := Vector2(W / 2.0, H.REF_H / 2.0)
				var d := Vector2(x, y) - c
				if d.length() < 1.0:
					d = Vector2(0, 1)
				ang = d.angle()
				var k := minf((W / 2.0 - m) / maxf(1e-3, absf(d.x)), (H.REF_H / 2.0 - m) / maxf(1e-3, absf(d.y)))
				x = c.x + d.x * k
				y = c.y + d.y * k
			var bleed: float = mp.bleedOf(id) if mp != null else 0.0
			_marks.append({"x": x, "y": y, "edge": edge, "ang": ang, "col": col,
				"frac": clampf(bleed / maxf(0.1, mp.bleedTotal if mp != null else 30.0), 0.0, 1.0),
				"rev": mp.reviveProgress(id) if mp != null else -1.0, "blink": bleed <= 5.0})
			continue
		if q == spec or not q.has_method("headPos"):
			continue
		var hp: Vector3 = q.headPos() + Vector3(0.0, 0.1, 0.0)
		var dist := eye.distance_to(hp)
		if dist > TAG_MAX:
			continue
		var p2 := _project(cam, hp)
		if p2.z == 0.0 or p2.x < -50.0 or p2.x > W + 50.0 or p2.y < -50.0 or p2.y > H.REF_H + 50.0:
			continue
		var o: Dictionary = _occ.get(id, {"t": 0.0, "hidden": false})
		o.t -= dt
		if o.t <= 0.0:
			o.t = 0.25
			o.hidden = _blocked(eye, hp)
		_occ[id] = o
		var s := lerpf(1.0, 0.75, clampf((dist - 6.0) / 24.0, 0.0, 1.0))
		var a := (0.45 if o.hidden else 1.0) * clampf((TAG_MAX - dist) / 6.0, 0.0, 1.0)
		_tags.append({"x": p2.x, "y": p2.y, "s": s, "a": a, "name": n.nameOf(id), "col": col})

# A wall between the camera and the point (architecture only, like interact's line of sight).
func _blocked(o: Vector3, t: Vector3) -> bool:
	var col = game.level.get("col") if game.level != null else null
	if col == null or not col.has_method("raycast"):
		return false
	if not is_same(_losCol, col):
		_losCol = col
		_los.ignoreTags = ~int(col.maskOf(["wall", "glass", "fence", "door", "window", "lattice"])) & 0x7fffffff
	var d := t - o
	var len := d.length()
	if len < 0.3:
		return false
	var hit = col.raycast(o, d / len, len, _los)
	return hit != null and float(hit.dist) < len - 0.2

func _buildMe(n, mp, me) -> void:
	_me.mode = ""
	if me == null or mp == null:
		return
	var id: int = n.localId
	if me.downed:
		_me.mode = "down"
		_me.frac = clampf(mp.bleedOf(id) / maxf(0.1, mp.bleedTotal), 0.0, 1.0)
		_me.rev = mp.reviveProgress(id)
		var rv: int = mp.reviverOf(id)
		var rq = n.playerById(rv) if rv != 0 else null
		_me.revCol = _heroCol(n, rv, rq.heroId) if rq != null else ""
		_me.revCh = CHANNEL.get(rq.heroId, 0) if rq != null else 0
	elif me.get("offAir") == true:
		_me.mode = "off"
		var s = me.get("spectate")
		_me.name = n.nameOf(n.idOf(s)) if s != null else ""
		_me.col = _heroCol(n, n.idOf(s), s.heroId) if s != null else "#F6E7C8"

# ------------------------------------------------------------------------------------------------ painting
func _font() -> Font:
	return hud._fonts.hud

func _badge() -> Texture2D:
	return hud._tx("mp_badge", func(): return H.svgTexture(H.iconSvg(BADGE_SVG, 44, 44, 44, 44, [[0.0, 2.0, 2.0, "rgba(0,0,0,.5)"]])))

func _bars() -> Texture2D:
	return hud._tx("mp_bars", func():
		var b := ""
		for i in Config.BARS.size():
			b += '<rect x="%s" y="3" width="4.3" height="18" fill="%s"/>' % [H.n_(3.0 + i * 4.3), Config.BARS[i]]
		return H.svgTexture(H.svgDoc(0, 0, 36, 24, '<path d="%s" fill="#14141A"/>%s' % [H.rrd(0, 0, 36, 24, 5), b])))

func _emb(col: String) -> Array:
	return [[0.0, 2.0, 0.0, DARK], [0.0, -1.0, 0.0, DARK], [2.0, 0.0, 0.0, DARK], [-2.0, 0.0, 0.0, DARK]]

func _text(ci: Control, s: String, x: float, cy: float, size: float, col: Color, align := 0.5) -> void:
	var f := _font()
	var w: float = H.textWidth(f, s, size)
	H.drawText(ci, f, x - w * align, H.baselineAt(f, size, cy), s, size, col, 0.0, _emb(""))

func _chip(ci: Control, c: Vector2, col: String, ch: int, a: float) -> void:
	var r := Rect2(c.x - 15.0, c.y - 15.0, 30.0, 30.0)
	ci.draw_rect(Rect2(r.position + Vector2(0, 2), r.size), Color(0, 0, 0, 0.45 * a))
	ci.draw_rect(r, Color(DAU.color(col), a))
	if ch > 0:
		_text(ci, str(ch), c.x, c.y, 20.0, Color(DAU.color(DARK), a))

func _ring(ci: Control, c: Vector2, r: float, frac: float, col: Color, w: float) -> void:
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(0, 0, 0, 0.35 * col.a), w + 2.0, true)
	if frac > 0.0:
		ci.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * frac, maxi(4, int(48 * frac)), col, w, true)

func _drawTags(ci: Control) -> void:
	for t in _tags:
		var c: Color = DAU.color(t.col)
		c.a = t.a
		ci.draw_set_transform(Vector2(t.x, t.y), 0.0, Vector2(t.s, t.s))
		_text(ci, t.name, 0.0, -10.0, 22.0, c)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-6, 4), Vector2(6, 4), Vector2(0, 11)]), c)
	ci.draw_set_transform(Vector2.ZERO)
	var badge := _badge()
	for m in _marks:
		var c2: Color = DAU.color(m.col)
		var bl := 1.0
		if m.blink:
			bl = H.stepsBlink(_time, 0.5, 0.35)
		var p := Vector2(m.x, m.y)
		if m.edge:
			var d := Vector2.from_angle(m.ang)
			var tip := p + d * 50.0
			ci.draw_colored_polygon(PackedVector2Array([tip, p + d * 38.0 + d.orthogonal() * 9.0, p + d * 38.0 - d.orthogonal() * 9.0]), Color(c2, 0.9))
		if badge:
			ci.draw_texture_rect(badge, Rect2(p.x - 30, p.y - 30, 60, 60), false, Color(1, 1, 1, bl))
		_ring(ci, p, 27.0, m.frac, Color(c2, bl), 4.5)
		if m.rev >= 0.0:
			_ring(ci, p, 33.0, m.rev, DAU.color("#FFD23A"), 4.0)

func _drawList(ci: Control) -> void:
	var y := 0.0
	var badge := _badge()
	for i in range(_rows.size() - 1, -1, -1):
		var r: Dictionary = _rows[i]
		var a := 0.45 if r.state == 2 else 1.0
		var cy := y - ROW_H / 2.0
		var cc := Vector2(-15.0, cy)
		if r.state == 1:
			var bl: float = H.stepsBlink(_time, 0.5, 0.35)
			if badge:
				ci.draw_texture_rect(badge, Rect2(cc.x - 19, cc.y - 19, 38, 38), false, Color(1, 1, 1, bl))
			_ring(ci, cc, 19.0, clampf(r.bleed / 30.0, 0.0, 1.0), Color(DAU.color(r.col), 1.0), 3.0)
		elif r.state == 2:
			var bars := _bars()
			if bars:
				ci.draw_texture_rect(bars, Rect2(cc.x - 18, cc.y - 12, 36, 24), false, Color(1, 1, 1, a))
		else:
			_chip(ci, cc, r.col, r.ch, a)
		var x := -42.0
		if r.pts >= 0:
			var ps := str(r.pts)
			_text(ci, ps, x, cy, 24.0, Color(DAU.color("#FFB347"), a), 1.0)
			x -= H.textWidth(_font(), ps, 24.0) + 14.0
		_text(ci, r.name, x, cy, 22.0, Color(DAU.color(H.CREAM), a), 1.0)
		if hud.perkTray != null and not r.perks.is_empty():   # their perks: tiny sponsor dots left of the name
			hud.perkTray.drawDots(ci, r.perks, x - H.textWidth(_font(), r.name, 22.0) - 10.0, cy, a)
		y -= ROW_H + 4.0

func _drawMe(ci: Control) -> void:
	var W: float = hud.stageW
	if _me.mode == "down":
		var c := Vector2(W / 2.0, H.REF_H / 2.0)
		var badge := _badge()
		if badge:
			ci.draw_texture_rect(badge, Rect2(c.x - 44, c.y - 44, 88, 88), false, Color(1, 1, 1, H.stepsBlink(_time, 0.5, 0.4) if _me.frac < 0.17 else 1.0))
		_ring(ci, c, 58.0, _me.frac, DAU.color("#FF5A46"), 8.0)
		if _me.rev >= 0.0:
			_ring(ci, c, 70.0, _me.rev, DAU.color("#FFD23A"), 6.0)
			if _me.revCol != "":
				_chip(ci, c + Vector2(0, 98.0), _me.revCol, _me.revCh, 1.0)
	elif _me.mode == "off":
		var bars := _bars()
		if bars:
			ci.draw_texture_rect(bars, Rect2(H.M, H.M, 72, 48), false)
		ci.draw_circle(Vector2(H.M + 82.0, H.M + 12.0), 6.0, Color(DAU.color("#FF3B30"), H.stepsBlink(_time, 1.0, 0.2)))
		if _me.name == "":
			return
		var f := _font()
		var tw: float = H.textWidth(f, _me.name, 30.0)
		var w := ceilf(tw + 2.0 * (40.0 + 28.0) + 32.0)
		var h := 54.0
		var x0 := W / 2.0 - w / 2.0
		var y0: float = H.REF_H - H.M - 150.0
		var bg = hud._tx("dymo%d" % int(w), func(): return H.svgTexture(hud._dymoSvg(w, h)))
		if bg:
			ci.draw_texture_rect(bg, Rect2(x0 - 14, y0 - 10, w + 28, h + 30), false)
		var pad: bool = game.input != null and game.input.get("device") == "pad"
		var key = hud._tx("key%s" % pad, func(): return H.svgTexture(hud._keySvg(pad)))
		for side in [-1, 1]:
			var kx := x0 + 16.0 if side < 0 else x0 + w - 56.0
			if key:
				ci.draw_texture_rect(key, Rect2(kx - 2, y0 + 5, 44, 44), false)
			var cx := kx + 20.0
			var cy := y0 + 27.0
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx + 7.0 * side, cy), Vector2(cx - 5.0 * side, cy - 8.0), Vector2(cx - 5.0 * side, cy + 8.0)]), DAU.color("#F2F0EA"))
		_text(ci, _me.name, W / 2.0, y0 + h / 2.0, 30.0, DAU.color(_me.col))
