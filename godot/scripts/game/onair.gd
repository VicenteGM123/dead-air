# DEAD AIR — ON AIR: a teammate shooting a sponsor commercial, as the rest of the crew sees it (MP only; mp-onair).
# Built by sponsors.gd (_onAir) at the first update of an MP game and disposed by sponsors.reset() once no MP game
# runs, so nothing here exists in a solo game.
#
# STUDIO DRESSING (per sponsor set, built once per MP session, render layer 1 = RemotePlayer.LAYER: the gameplay
#   camera and the CCTV feeds draw it, the sponsor commercial camera (layer 0) never does):
#   * an ON AIR box (prop bc_on_air) over the set's painted flat, facing the camera: dark until a teammate's ad
#     starts, then it flickers on (FLICKER) and glows red with a red light anchor in front of it (lights.gd pool);
#   * a floor monitor on a cart (prop bc_cart_monitor) beside the tally camera, facing the crew behind it (first free
#     spot of the collision world on either side): colour bars when idle, the LIVE FEED while the ad runs.
#   * the set's tally camera prop moves to layer 1 too (still drawn by the gameplay camera; out of the live feed it
#     stands in front of, like the performer's own commercial hides it); dispose() puts it back on layer 0.
# A TEAMMATE'S AD (sponsors.net_locked -> _startRemote -> start(by, S, t0); t0 = where the performer's ad is now,
#   from the peers' pings, sponsors._adClock):
#   0.00  the ON AIR box flickers on, the tally camera's tally goes steady red (sponsors' blink is replaced), the set's
#         key lights are already up x2.2 (sponsors), the jingle plays at the set through the monitor speaker.
#   0.00-2.46  the performer's avatar acts out the SAME pantomime as the performer's own commercial: sponsors._poseCtx
#         runs as the RemotePlayer's animator.override on the ad's timeline, with its own gag-prop set
#         (sponsors._makeGags, one per teammate, kept for the session) and Double Vision duplicates
#         (sponsors._makeDups of the avatar); the gag sounds play live at the set (positional), the edit / announcer
#         beats (cuts, ding, wah-wah, the teaser sting) come out of the monitor speaker (audio tv filter).
#   LIVE FEED: the monitor (and the area's program-feed CRTs, screens group scr_feed_<area> when it exists: the
#         station "goes to air" with it) show the ad rendered on this peer by a feed camera at the commercial
#         camera's framing (the same jump-cut / shake beats): a 256x192 SubViewport, 15 fps, rendered only while an
#         ad runs AND this peer's viewer is within NEAR m of the set in a visible area (one feed at a time: the
#         nearest ad). Its cull mask is WORLD + FEED_BIT: the performer's avatar meshes carry FEED_BIT for the length
#         of the pantomime (remote heroes are on layer 1, which the commercial camera skips), zombies and the other
#         avatars stay out of the shot like in the real commercial. Overlay: a blinking red "● REC", the VTR timecode,
#         then the sponsor's logo card slides in at T_CARD, holds, and irises to black at the star wipe.
#   AD() / sponsors.net_unlocked / the performer leaving / the AD()+3 s watchdog: everything goes back (stop(by)).
# API (sponsors.gd only): start(by, S, t0), stop(by), update(rdt), forget(peer) (a teammate left: its gag set goes),
#   dispose(), and for QA: debugHoldAt (holds teammates' ads at t on this peer), ads {peer -> ctx {S, id, t, posed,
#   ...}}, rigs {perkId -> rig}, feedFor (peer | 0), feedFrames (rendered feed frames), feedTexture() (the monitor picture).
extends RefCounted

const SP = preload("res://scripts/game/sponsors.gd")
const FEED_BIT := 1 << 5          # visibility bit of the on-air avatar (no other node uses layer 5)
const LAYER := 1                  # RemotePlayer.LAYER (actors): never in the layer-0 commercial shot / feed
const FEED_W := 256
const FEED_H := 192
const FEED_FPS := 15.0
const NEAR := 16.0
const FLICKER := [[0.0, true], [0.05, false], [0.11, true], [0.17, false], [0.24, true]]
const SIGN_Y := 3.2               # the ON AIR box sits on the painted flats (3.18 m tall)

var sp                            # game.sponsors
var game
var rigs := {}
var ads := {}
var feedFor := 0
var feedFrames := 0
var debugHoldAt = null            # QA: a teammate's ad on this peer will not advance past t (null releases it)
var _feed = null                  # {vp, cam, ui, rec, tc, card, black, cardId}
var _feedAcc := 0.0
var _pinned = null                # screens group pinned to the feed
var _gagSets := {}                # peer -> gag set (sponsors._makeGags)
var _dupSets := {}                # peer -> {hero, list}
var _font = null
var _bars = null

func _init(sponsors) -> void:
	sp = sponsors
	game = sponsors.game
	for id in sp.sets:
		_buildRig(sp.sets[id])

# ------------------------------------------------------------------------------------------ studio dressing
func _buildRig(S: Dictionary) -> void:
	var g = game
	var par: Node = S.root.get_parent()
	if par == null or g.props == null:
		return
	var rig := {"S": S, "on": false, "tally": null, "lit": null}
	var face: Vector3 = S.fwd
	# ON AIR box over the flat, centred on the set's neon sign
	var sign = g.props.build("bc_on_air", {"lit": false})
	if sign is Node3D:
		var sp0: Vector3 = S.product - S.fwd * 0.7
		var sn = DAU.ud(S.root).get("parts", {}).get("sign")
		if sn is Array:
			sn = sn[0] if sn.size() > 0 else null
		if sn is Node3D:
			sp0 = DAU.worldPos(sn)
		par.add_child(sign)
		sign.global_position = Vector3(sp0.x, S.mark.y - 0.2 + SIGN_Y, sp0.z) + face * 0.1
		sign.rotation = Vector3(0, atan2(-face.x, -face.z), 0)
		sign.scale = Vector3.ONE * 1.5
		DAU.setLayerRecursive(sign, LAYER)
		var parts = DAU.ud(sign).get("parts", {})
		var lm = DAU.ud(sign).get("lampMats")
		rig.sign = sign
		rig.lamp = parts.get("lamp") if parts is Dictionary else null
		rig.lampOn = lm.get("on") if lm is Dictionary else null
		rig.lampOff = lm.get("off") if lm is Dictionary else null
		var lp: Vector3 = sign.global_position + face * 0.5 + Vector3(0, -0.1, 0)
		var a = SP._m(g.lights, "addAnchor", [{"id": "onair_" + S.id, "pos": lp, "color": Config.PAL.onAirRed, "intensity": 0.0, "distance": 4.5, "area": S.area}])
		rig.light = a.id if a is Dictionary else null
	# floor monitor on a cart beside the tally camera, facing the crew behind it
	var spot = _monitorSpot(S)
	var mon = g.props.build("bc_cart_monitor", {"group": "scr_feed_newsroom", "id": "mon_newsroom_cart", "card": "snow"}) if spot != null else null
	if mon is Node3D:
		par.add_child(mon)
		mon.global_position = spot.pos
		mon.rotation = Vector3(0, atan2(-spot.dir.x, -spot.dir.z), 0)
		DAU.setLayerRecursive(mon, LAYER)
		rig.mon = mon
		var scr = DAU.ud(mon).get("screens", [])
		var mesh = scr[0].get("mesh") if scr is Array and scr.size() > 0 and scr[0] is Dictionary else null
		rig.screen = mesh
		rig.mat = _screenMat(mesh)
		_setScreen(rig, _colorBars())
	# the tally camera itself onto the actors layer: still drawn by the gameplay camera, out of the live feed it
	# stands in front of (the performer's own commercial hides it the same way: camProp.visible = false)
	DAU.setLayerRecursive(S.camProp, LAYER)
	rigs[S.id] = rig

# First free spot for the monitor cart: beside the tally camera (either side, a little ahead or behind), turned
# from the set's axis toward the line between the camera and the mark.
func _monitorSpot(S: Dictionary):
	var col = SP._f(game.level, "col")
	var cam: Vector3 = S.camPos
	for side in [1.0, -1.0]:
		for ahead in [0.1, -0.35, 0.55]:
			var p: Vector3 = cam + S.right * (side * 1.2) + S.fwd * ahead
			var fy = col.floorAt(p.x, p.z, 1.0) if col != null and col.has_method("floorAt") else 0.0
			p.y = float(fy) if fy != null and is_finite(float(fy)) else 0.0
			if col != null and col.has_method("blockedAt") and col.blockedAt(p.x, p.z, 0.55, p.y, 0.3, 1.5):
				continue
			if col != null and col.has_method("lineOfSight") and not col.lineOfSight(cam + Vector3(0, 1.2, 0), p + Vector3(0, 1.2, 0)):
				continue
			# the screen faces open floor of the set's area (the crew's side first, else across the room)
			for dv in [S.fwd + S.right * (-side * 0.45), S.fwd + S.right * (side * 0.6), S.right * side + S.fwd * 0.2]:
				var dir: Vector3 = (dv as Vector3).normalized()
				var front: Vector3 = p + dir * 1.8
				if Layout.areaAt(front.x, front.z) != S.area:
					continue
				if col != null and col.has_method("blockedAt") and col.blockedAt(front.x, front.z, 0.4, p.y, 0.45, 1.5):
					continue
				if col != null and col.has_method("lineOfSight") and not col.lineOfSight(p + dir * 0.5 + Vector3(0, 1.2, 0), front + Vector3(0, 1.2, 0)):
					continue
				return {"pos": p, "dir": dir}
	return null

func _screenMat(mesh):
	if not (mesh is MeshInstance3D):
		return null
	var mi := mesh as MeshInstance3D
	var m: Material = mi.material_override
	if m == null:
		m = mi.get_surface_override_material(0)
	if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
		if m != null:
			m = m.duplicate()
			mi.set_surface_override_material(0, m)
	return m

# Puts a picture on a rig's monitor (the CRT material's map, like screens.gd _matSetMap).
func _setScreen(rig: Dictionary, tex) -> void:
	var m = rig.get("mat")
	if m == null or rig.get("tex") == tex:
		return
	rig.tex = tex
	if "map" in m:
		m.map = tex
	elif m is ShaderMaterial:
		var has := {}
		if m.shader != null:
			for u in m.shader.get_shader_uniform_list():
				has[u.name] = true
		var nm := "tScreen" if has.has("tScreen") else "map"
		m.set_shader_parameter(nm, tex)
		if tex != null and has.has("uTexel"):
			var sz: Vector2 = tex.get_size()
			if sz.x > 0.0 and sz.y > 0.0:
				m.set_shader_parameter("uTexel", Vector2(1.0 / sz.x, 1.0 / sz.y))
	elif m is BaseMaterial3D:
		m.albedo_texture = tex

func _card(id: String):
	var c = game.cards
	if c != null and c.has_method("get_"):
		return c.get_(id, {})
	return null

func _colorBars():
	if _bars == null:
		_bars = _card("color_bars")
	return _bars

func _setSign(rig: Dictionary, on: bool) -> void:
	if rig.get("lit") == on:
		return
	rig.lit = on
	var lamp = rig.get("lamp")
	var m = rig.lampOn if on else rig.lampOff
	if lamp is GeometryInstance3D and m is Material:
		(lamp as GeometryInstance3D).material_override = m
	if rig.get("light") != null:
		SP._m(game.lights, "setAnchor", [rig.light, {"intensity": 2.4 if on else 0.0}])

func _setTally(rig: Dictionary, on: bool) -> void:
	if rig.get("tally") == on:
		return
	rig.tally = on
	var S: Dictionary = rig.S
	sp.setTally(S.camProp, on)

# ------------------------------------------------------------------------------------------ a teammate's ad
func start(by: int, S: Dictionary, t0: float) -> void:
	if ads.has(by):
		stop(by)
	var net = game.net
	var rp = net.playerById(by) if net != null else null
	var ctx := {"S": S, "id": S.id, "t": t0, "peer": by, "rp": rp, "fired": {}, "props": [], "posed": false,
		"over": false, "faceYaw": SP._yawTo(S.spot.x, S.spot.z, S.camBase.x, S.camBase.z), "face": null}
	ads[by] = ctx
	var rig = rigs.get(S.id)
	if rig != null:
		rig.on = true
		_setTally(rig, true)
	if rp != null and SP._f(rp, "hero") != null and rp.model != null and rp.animator != null:
		_pose(ctx)

func _gagsFor(by: int) -> Dictionary:
	var G = _gagSets.get(by)
	if G == null:
		G = sp._makeGags()
		_gagSets[by] = G
	return G

func _dupsFor(by: int, rp) -> Array:
	var D = _dupSets.get(by)
	if D == null or not is_same(D.hero, rp.hero):
		if D != null:
			for d in D.list:
				_drop(d.holder)
		D = {"hero": rp.hero, "list": sp._makeDups(rp.hero, rp.weaponModel)}
		_dupSets[by] = D
	return D.list

static func _drop(n) -> void:
	if n is Node and is_instance_valid(n):
		DAU.detach(n)
		n.queue_free()

func _pose(ctx: Dictionary) -> void:
	var rp = ctx.rp
	var by: int = ctx.peer
	var G := _gagsFor(by)
	var dups := _dupsFor(by, rp) if ctx.id == "double_vision" else []
	ctx.G = G
	ctx.dups = dups
	sp._setupPantomimeFor(ctx, rp, G)
	_feedBits(rp.model, true)
	var an = rp.animator
	ctx.prevOv = an.override
	var ID: String = str(rp.heroId) if rp.heroId else "duke"
	var fn := func(rig, _dt = 0.0) -> void:
		var wm = rp.weaponModel
		if wm != null and is_instance_valid(wm) and wm.visible:
			wm.visible = false                  # (props in hand; the stream's inCommercial flag may lag behind)
		sp._poseCtx(ctx, rp, G, dups, ID, rig)
	ctx.ov = fn
	an.override = fn
	ctx.posed = true

func _unpose(ctx: Dictionary) -> void:
	if not ctx.posed:
		return
	ctx.posed = false
	var rp = ctx.rp
	var alive: bool = rp != null and rp.model != null and is_instance_valid(rp.model)
	if alive and rp.animator != null and rp.animator.override == ctx.ov:
		rp.animator.override = ctx.prevOv
	for o in ctx.props:
		if is_instance_valid(o):
			DAU.detach(o)
	ctx.props.clear()
	if ctx.get("skates") != null:
		for part in ctx.skates:
			if is_instance_valid(part):
				DAU.detach(part)
		ctx.skates = null
	for d in ctx.dups:
		if is_instance_valid(d.holder):
			DAU.detach(d.holder)
	if alive:
		_feedBits(rp.model, false)
		rp.model.visible = not (rp.hidden or rp.offAir)
		var G: Dictionary = ctx.G
		if G.get("spoon") and G.spoon.jelly:
			G.spoon.jelly.visible = true
	if ctx.get("face") != null and alive:
		SP._m(ctx.face, "setExpression", ["neutral", 1])

func _feedBits(n, on: bool) -> void:
	if n == null or not is_instance_valid(n):
		return
	DAU.traverse(n, func(o):
		if o is VisualInstance3D:
			var vi := o as VisualInstance3D
			vi.layers = (vi.layers | FEED_BIT) if on else (vi.layers & ~FEED_BIT))

# Off air: the sign and tally go back (the ad is over even if the host's unlocked is still on its way).
func _offAir(ctx: Dictionary) -> void:
	if ctx.over:
		return
	ctx.over = true
	_unpose(ctx)
	var rig = rigs.get(ctx.id)
	if rig != null and not _otherOn(ctx):
		rig.on = false
		_setSign(rig, false)
		var S: Dictionary = ctx.S
		for l in S.lights:
			SP._m(game.lights, "setAnchor", [l.id, {"intensity": l.intensity if sp._live(S) else 0.0}])
		_setTally(rig, sp._live(ctx.S) and not ctx.S.soldOut)
		rig.tally = null
		_setScreen(rig, _colorBars())

func _otherOn(ctx: Dictionary) -> bool:
	for by in ads:
		var c: Dictionary = ads[by]
		if c != ctx and c.id == ctx.id and not c.over:
			return true
	return false

func stop(by: int, force: bool = false) -> void:
	var ctx = ads.get(by)
	if ctx == null:
		return
	if debugHoldAt != null and not force:
		ctx.stopPending = true            # QA: a held ad stays on air on this peer until debugHoldAt is released
		return
	_offAir(ctx)
	ads.erase(by)
	if feedFor == by:
		_releaseFeed()

func forget(peer: int) -> void:
	stop(peer, true)
	var G = _gagSets.get(peer)
	_gagSets.erase(peer)
	if G is Dictionary:
		for o in G.values():
			_drop(o.grp if o is Dictionary else o)
	var D = _dupSets.get(peer)
	_dupSets.erase(peer)
	if D != null:
		for d in D.list:
			_drop(d.holder)

func dispose() -> void:
	for by in ads.keys():
		stop(by, true)
	for peer in _gagSets.keys():
		forget(peer)
	_releaseFeed()
	for id in rigs:
		var rig: Dictionary = rigs[id]
		if rig.get("light") != null:
			SP._m(game.lights, "removeAnchor", [rig.light])
		for k in ["sign", "mon"]:
			_drop(rig.get(k))
		var cp = rig.S.get("camProp")
		if cp is Node3D and is_instance_valid(cp):
			DAU.setLayerRecursive(cp, Config.LAYERS.WORLD)
	rigs.clear()
	if _feed != null:
		_drop(_feed.vp)
		_feed = null

# ------------------------------------------------------------------------------------------ per frame
func update(rdt: float) -> void:
	if ads.is_empty():
		return
	var best = null
	var bestD := INF
	var vp = game.net.viewPlayer() if game.net != null else game.player
	var vpos: Vector3 = vp.pos if vp != null else Vector3.ZERO
	for by in ads.keys():
		var ctx: Dictionary = ads[by]
		ctx.t += rdt
		if debugHoldAt != null and ctx.t > float(debugHoldAt):
			ctx.t = float(debugHoldAt)
		var t: float = ctx.t
		var rig = rigs.get(ctx.id)
		if ctx.get("stopPending") and debugHoldAt == null:
			stop(by)
			continue
		if ctx.over:
			continue
		if t >= SP.AD():
			_offAir(ctx)
			if feedFor == by:
				_releaseFeed()
			continue
		if rig != null:
			var k := -1
			for i in FLICKER.size():
				if t >= FLICKER[i][0]:
					k = i
			_setSign(rig, k >= 0 and FLICKER[k][1])
			_setTally(rig, true)
			for l in ctx.S.lights:                 # the set's key lights at full (sponsors: x2.2) while on air
				SP._m(game.lights, "setAnchor", [l.id, {"intensity": l.intensity * 2.2, "enabled": true}])
		if ctx.posed:
			if not (ctx.rp != null and ctx.rp.model != null and is_instance_valid(ctx.rp.model)):
				ctx.posed = false
			elif t >= SP.T_CLEAN:
				_unpose(ctx)
			else:
				_beats(ctx, t)
		if t >= 0.0:
			_cardBeats(ctx, t, rig)
		var d: float = vpos.distance_to(ctx.S.spot)
		if d < NEAR and d < bestD and ctx.S.root.is_visible_in_tree():
			best = by
			bestD = d
	if best == null:
		if feedFor != 0:
			_releaseFeed()
		return
	if feedFor != best:
		_releaseFeed()
		feedFor = best
	_updateFeed(ads[best], rdt)

# The pantomime's live sounds (positional at the set) and sparkles, on the ad's timeline (cf. sponsors._beats).
func _beats(ctx: Dictionary, t: float) -> void:
	var S: Dictionary = ctx.S
	var G: Dictionary = ctx.G
	var sparks = SP._f(game.perks, "sparkles")
	var rp = ctx.rp
	var hero = rp.hero
	var at: Vector3 = S.spot + Vector3(0, 1.2, 0)
	var live := func(id: String, o: Dictionary = {}) -> void:
		var oo := {"pos": at, "vol": 0.6}
		oo.merge(o, true)
		sp._play(id, oo)
	var star := func(n: Node3D, o: Dictionary) -> void:
		if sparks != null and n != null and is_instance_valid(n) and n.is_inside_tree():
			sparks.emit(n.global_position, o)
	var thumb := {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.34, "life": 0.5, "gravity": 0, "spin": 4}
	match ctx.id:
		"replay_ade":
			sp._once(ctx, t, "glug", 0.3, func(): star.call(G.get("bottle"), {"count": 6, "colors": ["#FFE14D", "#7FB8FF"], "speed": 0.8, "size": 0.05, "life": 0.4, "gravity": 3}))
			sp._once(ctx, t, "slip", 0.86, func():
				live.call("telly_boing", {"vol": 0.55})
				if sparks != null:
					sparks.emit(S.spot + Vector3(0, 0.15, 0), {"kind": "puff", "count": 5, "speed": 1.2, "size": 0.12, "life": 0.4, "gravity": -0.4}))
			sp._once(ctx, t, "rew", 1.4, func(): _tv(ctx, "replay_rewind", {"vol": 0.7}))
			sp._once(ctx, t, "land", 1.86, func(): live.call("land", {"vol": 0.55}))
			sp._once(ctx, t, "thumb", 1.98, func():
				star.call(hero.slots.handR, thumb)
				live.call("smile_ting", {"vol": 0.45}))
		"wobble_up":
			sp._once(ctx, t, "gulp", 0.45, func():
				if G.get("spoon") and G.spoon.jelly:
					G.spoon.jelly.visible = false)
			sp._once(ctx, t, "pow", 0.72, func():
				live.call("melee_hit_skip", {"vol": 0.65})
				live.call("jelly_bwoing", {"delay": 0.05})
				star.call(hero.parts.head, {"count": 12, "colors": ["#FFE27A", "#FFFFFF", "#52E04A"], "speed": 3, "size": 0.12, "life": 0.55, "gravity": 0.5}))
			sp._once(ctx, t, "thumb", 1.85, func():
				star.call(hero.slots.handR, thumb)
				live.call("smile_ting", {"vol": 0.45}))
		"jump_cut":
			var cuts := [0.7, 1.2, 1.7]
			for i in 3:
				sp._once(ctx, t, "cut%d" % i, cuts[i], func():
					_tv(ctx, "commercial_cut", {"vol": 0.6})
					_tv(ctx, "jumpcut_snip", {"delay": 0.02, "vol": 0.6}))
			if t < 0.7 and sparks != null and G.get("pot") and is_instance_valid(G.pot) and G.pot.is_inside_tree() and randf() < sp.rdtChance(22):
				sparks.emit(G.pot.global_position + Vector3(0, 0.22, 0), {"kind": "puff", "count": 1, "colors": ["#FFFFFF", "#F2EEE6"], "speed": 0.3, "size": 0.045, "life": 0.9, "gravity": -0.35, "dir": Vector3(0, 1, 0), "cone": 0.35, "grow": 2.6})
			sp._once(ctx, t, "reload", 1.45, func():
				live.call("reload_speedloader", {"vol": 0.55})
				star.call(G.get("gun"), {"count": 8, "colors": ["#FFE27A", "#FFFFFF"], "speed": 1.6, "size": 0.08, "life": 0.4, "gravity": 0}))
			sp._once(ctx, t, "wink", 1.8, func():
				star.call(hero.parts.head, {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.3, "life": 0.45, "gravity": 0, "spin": 5})
				live.call("smile_ting", {"vol": 0.45}))
		"roller_boogie":
			sp._once(ctx, t, "whoosh", 0.14, func(): live.call("melee_whoosh", {"rate": 0.6, "vol": 0.6}))
			sp._once(ctx, t, "push1", 0.64, func(): live.call("skate_push"))
			sp._once(ctx, t, "push2", 0.92, func(): live.call("skate_push"))
			sp._once(ctx, t, "disco", 1.52, func():
				star.call(hero.slots.handR, {"count": 16, "colors": ["#FF9EDB", "#7FE7FF", "#FFE27A", "#FFFFFF"], "speed": 2.6, "size": 0.1, "life": 0.7, "gravity": 0.3})
				live.call("smile_ting", {"vol": 0.4}))
			if sparks != null and ((t > 0.12 and t < 0.4) or (t > 0.62 and t < 1.35)) and randf() < sp.rdtChance(70):
				for side in ["footL", "footR"]:
					star.call(hero.slots[side], {"count": 1, "colors": ["#FF9EDB", "#7FE7FF", "#FFE27A"], "speed": 0.3, "size": 0.07, "life": 0.5, "gravity": -0.2})
		"double_vision":
			if t < 0.8 and sparks != null and randf() < sp.rdtChance(16):
				var hp: Vector3 = DAU.worldPos(hero.parts.head) + S.fwd * 0.22 + Vector3(0, -0.08, 0)
				sparks.emit(hp, {"kind": "puff", "count": 1, "colors": ["#FFFFFF", "#DFF8FF"], "speed": 0.4, "size": 0.045, "life": 0.5, "gravity": 0.6, "grow": 1.5})
			sp._once(ctx, t, "ting", 0.95, func():
				live.call("smile_ting", {"vol": 0.55})
				star.call(hero.parts.head, {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.46, "life": 0.55, "gravity": 0, "spin": 6}))
			sp._once(ctx, t, "split", 1.2, func():
				var mp = rp.model.get_parent()
				if mp != null:
					for d in ctx.dups:
						DAU.detach(d.holder)
						mp.add_child(d.holder)
				_tv(ctx, "commercial_cut", {"vol": 0.45}))

# The announcer / card beats, out of the monitor speaker.
func _cardBeats(ctx: Dictionary, t: float, _rig) -> void:
	if t < SP.T_CARD:
		return
	sp._once(ctx, t, "ding", SP.T_CARD, func(): _tv(ctx, "commercial_ding", {"vol": 0.7}))
	sp._once(ctx, t, "wah", SP.T_CARD + 0.14, func(): _tv(ctx, "announcer_wahwah", {"vol": 0.7, "rhythm": SP.WAH.get(ctx.id)}))
	sp._once(ctx, t, "button", SP.T_BUTTON, func(): _tv(ctx, "sponsor_teaser_" + ctx.id, {"vol": 0.6}))

func _tv(ctx: Dictionary, id: String, o: Dictionary = {}) -> void:
	var rig = rigs.get(ctx.id)
	var pos: Vector3 = rig.mon.global_position + Vector3(0, 1.2, 0) if rig != null and rig.get("mon") != null else ctx.S.spot
	var oo := {"pos": pos, "tv": true}
	oo.merge(o, true)
	sp._play(id, oo)

# ------------------------------------------------------------------------------------------ live feed
func _ensureFeed():
	if _feed != null:
		return _feed
	var vp := SubViewport.new()
	vp.name = "onair_feed"
	vp.size = Vector2i(FEED_W, FEED_H)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	var cam := Camera3D.new()
	cam.name = "onair_cam"
	cam.near = 0.05
	cam.far = 60.0
	cam.cull_mask = (1 << Config.LAYERS.WORLD) | FEED_BIT
	vp.add_child(cam)
	cam.current = true
	if _font == null and ResourceLoader.exists("res://assets/fonts/VT323.woff"):
		_font = load("res://assets/fonts/VT323.woff")
	var ui := Control.new()
	ui.size = Vector2(FEED_W, FEED_H)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(ui)
	var card := TextureRect.new()
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.size = Vector2(FEED_W, FEED_H)
	card.visible = false
	ui.add_child(card)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.size = Vector2(FEED_W, FEED_H)
	ui.add_child(black)
	var rec := _label(ui, "● REC", Color("#FF3B30"), Vector2(10, 4), 26)
	var tc := _label(ui, "00:00:00:00", Color("#F4F1E8"), Vector2(FEED_W - 118, FEED_H - 30), 22)
	var live := _label(ui, "LIVE", Color("#FFE14D"), Vector2(FEED_W - 52, 4), 26)
	if game.scene != null:
		game.scene.add_child(vp)
	_feed = {"vp": vp, "cam": cam, "ui": ui, "rec": rec, "tc": tc, "live": live, "card": card, "black": black, "cardId": ""}
	return _feed

func _label(ui: Control, text: String, c: Color, at: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	ui.add_child(l)
	return l

func feedTexture():
	return _feed.vp.get_texture() if _feed != null else null

func _releaseFeed() -> void:
	var by := feedFor
	feedFor = 0
	if _feed != null:
		_feed.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _pinned != null:
		SP._m(game.screens, "setSource", [_pinned, null])
		_pinned = null
	var ctx = ads.get(by)
	if ctx != null:
		var rig = rigs.get(ctx.id)
		if rig != null:
			_setScreen(rig, _card("sponsor_logo_" + ctx.id) if not ctx.over else _colorBars())

func _updateFeed(ctx: Dictionary, rdt: float) -> void:
	var F: Dictionary = _ensureFeed()
	var S: Dictionary = ctx.S
	var t: float = maxf(0.0, ctx.t)
	var rig = rigs.get(ctx.id)
	var tex = F.vp.get_texture()
	if rig != null:
		_setScreen(rig, tex)
	if _pinned == null and game.screens != null:
		var grp := "scr_feed_" + str(S.area)
		var groups = SP._f(game.screens, "groups", {})
		if groups is Dictionary and groups.has(grp) and game.screens.setSource(grp, tex):
			_pinned = grp
	# framing: the commercial camera's (+ the jump-cut reframes / the punch shake)
	var dIn := 0.0
	var side := 0.0
	var up := 0.0
	var fovMul := 1.0
	var lookUp := 0.0
	match ctx.id:
		"wobble_up":
			side = sin(t * 90.0) * 0.03 * (1.0 - (t - 0.72) / 0.28) if t > 0.72 and t < 1.0 else 0.0
		"jump_cut":
			if t >= 1.7:
				dIn = 1.05
				side = 0.12
				up = 0.18
				fovMul = 0.72
				lookUp = 0.42
			elif t >= 1.2:
				dIn = -0.2
				side = 0.45
				up = 0.1
				fovMul = 1.04
			elif t >= 0.7:
				dIn = 0.55
				side = -0.35
				up = -0.05
				fovMul = 0.86
				lookUp = 0.08
	var pos: Vector3 = S.camBase + S.fwd * -dIn + S.right * side
	pos.y += up
	var look: Vector3 = S.camLook
	look.y += lookUp
	var cam: Camera3D = F.cam
	cam.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	cam.fov = rad_to_deg(2.0 * atan(1.36 / S.camD)) * fovMul
	# overlay: REC blink, timecode, the logo card from T_CARD, the iris to black at the star wipe
	F.rec.visible = fmod(t + 0.5, 1.0) < 0.65
	var fr := int(t * 30.0)
	F.tc.text = "00:00:%02d:%02d" % [int(fr / 30.0), fr % 30]
	var card: TextureRect = F.card
	if t >= SP.T_CARD:
		if F.cardId != ctx.id:
			F.cardId = ctx.id
			card.texture = _card("sponsor_logo_" + ctx.id)
		card.visible = card.texture != null
		var k := SP._easeOutBack(SP._clamp01((t - SP.T_CARD) / (SP.T_SETTLE - SP.T_CARD)), 1.4)
		card.position = Vector2(FEED_W * (1.0 - k), 0)
		var push := 1.0 + 0.04 * SP._clamp01((t - SP.T_SETTLE) / (SP.T_WIPE() - SP.T_SETTLE))
		card.scale = Vector2(push, push)
		card.pivot_offset = Vector2(FEED_W * 0.5, FEED_H * 0.5)
	else:
		card.visible = false
	var wipe := SP._clamp01((t - SP.T_WIPE()) / (SP.AD() - SP.T_WIPE()))
	F.black.color = Color(0, 0, 0, wipe)
	F.live.visible = t < SP.T_CARD
	# render at FEED_FPS
	_feedAcc += rdt
	if _feedAcc >= 1.0 / FEED_FPS or F.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		_feedAcc = 0.0
		F.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		feedFrames += 1
