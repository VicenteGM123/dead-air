# weapons_net.gd — the MP half of weapons.gd (RECONCILE R17/R18/R19; mp-combat). Built by weapons.reset() only while an
# MP game runs (`weapons.mp`; null in solo), so nothing here ever runs in a solo game.
#
# OBSERVER STREAM 'wfx' (owner -> every other peer, unreliable ordered, at most one packet per frame, only when
#   something happened; handler weapons.net_stream_wfx(from, data)). Little-endian StreamPeerBuffer, events back to back:
#   1 SHOT   u8 gun (WD.GUN_IDS index | 0x80 upgraded) · u8 flags (b0-1 signal 0 none / 1 hot_mic / 2 laugh_track /
#            3 cold_open, b2 ghost (Double Vision), b3 every13) · f32x3 muzzle · u8 n · n x {f32x3 end, u8 kind
#            (0 air, 1 zombie, 2 shootable, 3 wall, 4 wood, 5 metal, 6 glass), s8x3 normal} · u8 nz · nz x {f32x3
#            point, u8 head}
#   2 MELEE  (swing start)       3 MHIT u8 kind (1 zombie, 2 shootable) · f32x3 point
#   4 COOK   (grenade in hand)   5 WIND (Tiny Tele in hand)
#   6 ZAP    u8 up · f32x3 muzzle · f32x3 end · u8 n · n x f32x3 victim chest points (wonder_net.gd)
#   7 BLOB   u8 up · u32 sid · f32x3 from · f32x3 vel (Chroma-Key goo blob, wonder_net.gd)
#   Observers draw it all from the shooter's RemotePlayer (tracers from its held muzzle, impacts, positional
#   wpn_<id> cues, recoil spring, casings, melee swing + prop, grenade / tele in the left hand).
# RELIABLE MESSAGES (handlers on game.weapons, see weapons.gd header): shootableHits (client -> host),
#   nade (owner -> others), nadeBoom (client -> host), nadeFx (host -> all), confirm (host -> thrower).
# REMOTE HELD WEAPONS: buildRemoteHeld(remote, id, upgraded, signal) -> holder (cached per peer and key, layer 1, no
#   hero fade) + remote.postAnimate = the IK pose copy of weapons.gd _pose/_poseLeft driven by the replicated aim
#   (remote.aimPoint / yaw / pitch), ads / sprint flags, anim.reload, swap raise, the recoil spring of SHOT events and
#   the melee / throw timelines of MELEE / COOK / WIND / nade; remote.weaponPose is replaced with the same pose (for
#   systems that chain it under their own animator.override). Reload beat / swap / pump sounds are derived locally.
#   The held copy's moving parts (mag, drum, cover, battery, goo, reels) follow the streamed reload progress through
#   weapons.gd's static reloadPartsOf(holder, u) (mp-onair).
extends RefCounted

const WD = preload("res://scripts/game/weapon_defs.gd")
const WM = preload("res://scripts/game/weapon_models.gd")
const K_SHOT := 1
const K_MELEE := 2
const K_MHIT := 3
const K_COOK := 4
const K_WIND := 5
const K_ZAP := 6
const K_BLOB := 7
const SIGNALS := ["", "hot_mic", "laugh_track", "cold_open"]
const SURF := ["wall", "wood", "metal", "glass"]
const FIRE_CUES := {"revolver_38": "wpn_revolver_38", "pump_37": "wpn_pump_37", "mp7": "wpn_mp7", "m16a1": "wpn_m16a1", "m60": "wpn_m60", "zapper": "wpn_zapper", "chroma_key": "wpn_chroma_fire"}
const LAYER := 1
const UP := Vector3(0, 1, 0)

var W                       # game.weapons
var game
var WS                      # weapons.gd script (statics: HOLDS, solveArm...)
var _buf := StreamPeerBuffer.new()
var _nEv := 0
var _shot := {"on": false, "pellets": [], "zs": [], "flags": 0, "gun": 0, "muzzle": Vector3.ZERO}
var _shootQ: Array = []
var _confirm := {}          # host: peer id -> [hits, head]
var _arms := {}             # peer id -> RemoteArms
var _nadeSeq := 0
var _hooked := false
var stats := {}             # QA: received event counts by name

func _init(weapons) -> void:
	W = weapons
	game = weapons.game
	WS = load("res://scripts/game/weapons.gd")
	_buf.big_endian = false

func net():
	return game.get("net")

func isClient() -> bool:
	var n = net()
	return n != null and n.isClient

func localId() -> int:
	var n = net()
	return int(n.localId) if n != null else 1

func reset() -> void:
	_buf.clear()
	_nEv = 0
	_shot.on = false
	_shootQ.clear()
	_confirm.clear()
	_nadeSeq = 0
	_orphans.clear()
	for id in _arms.keys():
		_arms[id].dispose()
	_arms.clear()
	if not _hooked and game.events != null:
		_hooked = true
		game.events.on("net:peer", func(e):
			if W.mp == self and e is Dictionary and e.get("joined") == false:
				_dropPeer(int(e.get("id", 0))))

func dispose() -> void:
	for id in _arms.keys():
		_arms[id].dispose()
	_arms.clear()

func _dropPeer(id: int) -> void:
	var a = _arms.get(id)
	if a != null:
		a.dispose()
		_arms.erase(id)
	_confirm.erase(id)
	# its grenades in flight stay: the host blows them up at their fuse (orphanBoom -> nadeFx on every peer)

func update(dt: float) -> void:
	for id in _arms:
		_arms[id].tick(dt)

func lateUpdate(_dt: float) -> void:
	var n = net()
	if n == null or not n.inGame:
		return
	if _nEv > 0:
		n.stream("wfx", _buf.data_array.slice(0, _buf.get_position()))
		_buf.clear()
		_nEv = 0
	if not _shootQ.is_empty():
		n.toHost("weapons", "shootableHits", [_shootQ.duplicate()])
		_shootQ.clear()
	if not _confirm.is_empty():
		for id in _confirm:
			var c: Array = _confirm[id]
			n.toPeer(int(id), "weapons", "confirm", [int(c[0]), bool(c[1])])
		_confirm.clear()

# ------------------------------------------------------------------------------------------ owner: event encoding
func _v3(v: Vector3) -> void:
	_buf.put_float(v.x)
	_buf.put_float(v.y)
	_buf.put_float(v.z)

func event(kind: int) -> void:
	_buf.put_u8(kind)
	_nEv += 1

func meleeHit(kind: int, point: Vector3) -> void:
	_buf.put_u8(K_MHIT)
	_buf.put_u8(kind)
	_v3(point)
	_nEv += 1

func shotBegin(s: Dictionary, muzzle: Vector3, ghost: bool) -> void:
	_shot.on = true
	_shot.pellets.clear()
	_shot.zs.clear()
	var gi := WD.GUN_IDS.find(s.id)
	_shot.gun = (maxi(0, gi) & 0x7F) | (0x80 if W._truthy(s.upgraded) else 0)
	var si := SIGNALS.find(str(s.get("signal"))) if s.get("signal") else 0
	_shot.flags = maxi(0, si) | (4 if ghost else 0)
	_shot.muzzle = muzzle

func shotPellet(end: Vector3, kind: int, normal: Vector3) -> void:
	if _shot.on and _shot.pellets.size() < 16:
		_shot.pellets.append([end, kind, normal])

func shotZombie(point: Vector3, head: bool) -> void:
	if _shot.on and _shot.zs.size() < 16:
		_shot.zs.append([point, head])

func shotEnd(every13: bool) -> void:
	if not _shot.on:
		return
	_shot.on = false
	_buf.put_u8(K_SHOT)
	_buf.put_u8(_shot.gun)
	_buf.put_u8(_shot.flags | (8 if every13 else 0))
	_v3(_shot.muzzle)
	_buf.put_u8(_shot.pellets.size())
	for pl in _shot.pellets:
		_v3(pl[0])
		_buf.put_u8(int(pl[1]))
		var nn: Vector3 = pl[2]
		_buf.put_8(int(clampf(nn.x, -1, 1) * 127))
		_buf.put_8(int(clampf(nn.y, -1, 1) * 127))
		_buf.put_8(int(clampf(nn.z, -1, 1) * 127))
	_buf.put_u8(_shot.zs.size())
	for z in _shot.zs:
		_v3(z[0])
		_buf.put_u8(1 if z[1] else 0)
	_nEv += 1

# Wonder visuals for observers (called by wonder.gd / wonder_net.gd on the shooter's peer).
func zap(up: bool, muzzle: Vector3, end: Vector3, points: Array) -> void:
	_buf.put_u8(K_ZAP)
	_buf.put_u8(1 if up else 0)
	_v3(muzzle)
	_v3(end)
	var n := mini(points.size(), 12)
	_buf.put_u8(n)
	for i in n:
		_v3(points[i])
	_nEv += 1

func blob(up: bool, sid: int, from: Vector3, vel: Vector3) -> void:
	_buf.put_u8(K_BLOB)
	_buf.put_u8(1 if up else 0)
	_buf.put_u32(sid)
	_v3(from)
	_v3(vel)
	_nEv += 1

# ------------------------------------------------------------------------------------------ shootables
# Client: queue the hit for the host (true = handled, skip the local onHit) unless the entry asks to run its onHit
# on the shooter's peer (entry.clientHit: its owner forwards itself).
func shootableHit(e: Dictionary, info: Dictionary) -> bool:
	if not isClient():
		info.by = localId()
		return false
	if e.get("clientHit") == true:
		info.by = localId()
		return false
	_shootQ.append([str(e.id), info.point, info.dir, str(info.weaponId) if info.weaponId != null else "", bool(info.upgraded),
		bool(info.melee), float(info.damage), str(info.cause)])
	return true

func onShootableHits(list) -> void:
	var n = net()
	if n == null or n.isClient or not (list is Array):
		return
	var by: int = n.sender
	for it in list:
		if not (it is Array) or it.size() < 8 or not (it[1] is Vector3) or not (it[2] is Vector3):
			continue
		var e = W.shootables.get(str(it[0]))
		if e == null:
			continue
		var dmg := float(it[6]) if (it[6] is float or it[6] is int) else 0.0
		if not is_finite(dmg) or dmg < 0.0:
			continue
		var info := {"id": e.id, "point": it[1], "dir": it[2], "weaponId": it[3] if it[3] != "" else null, "upgraded": it[4] == true,
			"melee": it[5] == true, "damage": minf(dmg, 1e6), "head": false, "cause": str(it[7]), "by": by}
		if e.get("onHit") is Callable:
			n.withSender(by, func(): e.onHit.call(info))
		game.events.emit("weapon:hit_shootable", info.duplicate())

# ------------------------------------------------------------------------------------------ grenades
func nadeThrown(origin: Vector3, vel: Vector3, fuse: float) -> int:
	_nadeSeq += 1
	var n = net()
	if n != null:
		n.toOthers("weapons", "nade", [_nadeSeq, origin, vel, fuse])
	return _nadeSeq

# The local player's grenade went off (weapons._explode already played the FX / self-damage locally).
func nadeExploded(nid: int, pos: Vector3, inHand: bool, dmgMul: float) -> void:
	var n = net()
	if n == null:
		return
	if n.isClient:
		n.toHost("weapons", "nadeBoom", [nid, pos, inHand, dmgMul])
	else:
		n.toAll("weapons", "nadeFx", [n.localId, nid, pos, inHand])

func onNade(nid, origin, vel, fuse) -> void:
	var n = net()
	if n == null or not (origin is Vector3) or not (vel is Vector3):
		return
	var by: int = n.sender
	if by == n.localId:
		return
	var g = game
	var model: Node3D = WM.buildGrenadeModel(g)
	WS._xyzOrder(model)
	model.scale = Vector3(1.25, 1.25, 1.25)
	model.position = origin
	DAU.setLayerRecursive(model, LAYER)
	g.scene.add_child(model)
	var pool = g.fx.lightPool(origin, 0.8, "#FF8A2E", 0.35) if g.fx.has_method("lightPool") else null
	W._projectiles.append({"kind": "grenade", "pos": origin, "vel": vel, "fuse": clampf(float(fuse), 0.0, 3.0), "model": model,
		"spin": Vector3(randf() * 14 - 7, randf() * 10 + 6, randf() * 8 - 4), "rest": false, "pool": pool, "bounceT": 0.0,
		"remote": true, "by": by, "nid": int(nid)})
	W._play("grenade_throw", {"pos": origin})
	var a = _arms.get(by)
	if a != null:
		a.throwNade()

# Host: another player's grenade copy reached its fuse; its thrower left (or stayed silent 2 s past the fuse: dropped
# without a bye): the host resolves the blast at the copy's position (true = done, the caller removes the copy).
var _orphans := {}
func orphanBoom(pr: Dictionary) -> bool:
	var n = net()
	if n == null or n.isClient:
		return false
	var by := int(pr.get("by", 0))
	if n.peers.has(by) and float(pr.fuse) > -2.0:
		return false
	var nid := int(pr.get("nid", -1))
	var pos: Vector3 = pr.pos
	if n.peers.has(by):
		_orphans["%d:%d" % [by, nid]] = true      # a late nadeBoom for it is ignored
	n.withSender(by, func(): return W._blastDamage(pos, W._blastBase(1.0), by))
	var p = game.player
	W._blastFx(pos, false, (p.pos + Vector3(0, 0.9, 0)).distance_to(pos) if p != null else 99.0, by)
	n.toAll("weapons", "nadeFx", [by, nid, pos, false])
	return true

func onNadeBoom(nid, pos, inHand, dmgMul) -> void:
	var n = net()
	if n == null or n.isClient or not (pos is Vector3):
		return
	var by: int = n.sender
	if _orphans.erase("%d:%d" % [by, int(nid)]):
		return
	var mul := clampf(float(dmgMul) if (dmgMul is float or dmgMul is int) else 1.0, 0.0, 10.0)
	var hk: Array = n.withSender(by, func(): return W._blastDamage(pos, W._blastBase(mul), by))
	if int(hk[0]) > 0:
		_confirm[by] = [int(_confirm.get(by, [0, false])[0]) + int(hk[0]), false]
	_blastFxRemote(by, int(nid), pos, inHand == true)
	n.toAll("weapons", "nadeFx", [by, int(nid), pos, inHand == true])

func onNadeFx(by, nid, pos, inHand) -> void:
	var n = net()
	if n == null or not (pos is Vector3) or int(by) == n.localId:
		return
	_blastFxRemote(int(by), int(nid), pos, inHand == true)

func _blastFxRemote(by: int, nid: int, pos: Vector3, inHand: bool) -> void:
	for i in range(W._projectiles.size() - 1, -1, -1):
		var pr: Dictionary = W._projectiles[i]
		if pr.get("remote") and int(pr.get("by", 0)) == by and int(pr.get("nid", -2)) == nid:
			W._removeProjectile(pr)
			W._projectiles.remove_at(i)
	var a = _arms.get(by)
	if a != null:
		a.nadeDone()
	var p = game.player
	var pd: float = (p.pos + Vector3(0, 0.9, 0)).distance_to(pos) if p != null else 99.0
	W._blastFx(pos, inHand, pd, by)

# ------------------------------------------------------------------------------------------ observer stream
func onStream(from: int, data: PackedByteArray) -> void:
	var n = net()
	if n == null or from == n.localId:
		return
	var rp = n.playerById(from)
	var a = _armsOf(rp) if rp != null else null
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.big_endian = false
	var size := data.size()
	var guard := 0
	while b.get_position() < size and guard < 64:
		guard += 1
		var k = b.get_u8()
		stats[k] = int(stats.get(k, 0)) + 1
		match k:
			K_SHOT:
				if not _remoteShot(b, rp, a):
					return
			K_MELEE:
				if a != null:
					a.melee()
			K_MHIT:
				if b.get_position() + 13 > size:
					return
				var kind := b.get_u8()
				var p := _g3(b)
				_meleeHitFx(rp, kind, p)
			K_COOK:
				if a != null:
					a.cook()
			K_WIND:
				if a != null:
					a.wind()
			K_ZAP:
				if b.get_position() + 26 > size:
					return
				var up := b.get_u8() == 1
				var mz := _g3(b)
				var end := _g3(b)
				var nv := b.get_u8()
				var pts: Array = []
				for i in nv:
					if b.get_position() + 12 > size:
						return
					pts.append(_g3(b))
				var Wn = game.wonder
				if Wn != null and Wn.has_method("remoteZap"):
					Wn.remoteZap(rp, up, mz, end, pts)
				if a != null:
					a.kick({"recoil": [0.03, 0.5]})
			K_BLOB:
				if b.get_position() + 29 > size:
					return
				var up2 := b.get_u8() == 1
				var sid := b.get_u32()
				var from3 := _g3(b)
				var vel := _g3(b)
				var Wn2 = game.wonder
				if Wn2 != null and Wn2.has_method("remoteBlob"):
					Wn2.remoteBlob(from, sid, up2, from3, vel)
				if a != null:
					a.kick({"recoil": [0.09, 0.25]})
			_:
				return

func _g3(b: StreamPeerBuffer) -> Vector3:
	var x := b.get_float()
	var y := b.get_float()
	var z := b.get_float()
	return Vector3(x, y, z)

func _remoteShot(b: StreamPeerBuffer, rp, a) -> bool:
	var size := b.data_array.size()
	if b.get_position() + 15 > size:
		return false
	var gun := b.get_u8()
	var flags := b.get_u8()
	var mz := _g3(b)
	var np := b.get_u8()
	var pellets: Array = []
	for i in np:
		if b.get_position() + 16 > size:
			return false
		var e := _g3(b)
		var kind := b.get_u8()
		var nn := Vector3(b.get_8(), b.get_8(), b.get_8()) / 127.0
		pellets.append([e, kind, nn])
	if b.get_position() + 1 > size:
		return false
	var nz := b.get_u8()
	var zs: Array = []
	for i in nz:
		if b.get_position() + 13 > size:
			return false
		zs.append([_g3(b), b.get_u8() == 1])
	var gi := gun & 0x7F
	if gi >= WD.GUN_IDS.size():
		return true
	var id: String = WD.GUN_IDS[gi]
	var up := (gun & 0x80) != 0
	var sig = SIGNALS[flags & 3] if (flags & 3) != 0 else null
	var def = WD.weaponDef(id, up)
	if def == null:
		return true
	var s := {"id": id, "upgraded": up, "signal": sig}
	var muzzle := mz
	if rp != null and rp.weaponModel != null and is_instance_valid(rp.weaponModel) and rp.weaponModel.visible and rp.model != null and rp.model.visible:
		muzzle = rp.muzzle()
	_shotFx(s, def, muzzle, pellets, zs, (flags & 4) != 0, (flags & 8) != 0)
	if a != null:
		a.kick(def)
		a.shot(def)
	return true

# Tracers, muzzle, impacts and hit pops of another player's shot (the zombie-side reactions come from mp-zombies).
func _shotFx(s: Dictionary, def: Dictionary, muzzle: Vector3, pellets: Array, zs: Array, ghost: bool, every13: bool) -> void:
	var g = game
	var fx = W.fx
	if fx == null or g.fx == null:
		return
	var style: Dictionary = def.get("tracer") if def.get("tracer") is Dictionary else {}
	var col = W._tracerColor(s, def)
	var first := muzzle + Vector3(0, 0, -1)
	var multi := pellets.size() > 1
	for i in pellets.size():
		var pl: Array = pellets[i]
		var end: Vector3 = pl[0]
		var kind: int = pl[1]
		if i == 0:
			first = end
		fx.streak(muzzle, end, style, col, i * 0.004 if multi else 0.0)
		if style.get("style") == "scratch":
			var st2 := style.duplicate()
			st2.width = float(style.get("width", 0.03)) * 0.5
			st2.len = float(style.get("len", 2.5)) * 0.6
			fx.streak(muzzle, end, st2, "#FFD8A0", 0.01)
		if ghost:
			fx.streak(muzzle, end, style, "#5FF4FF", 0.012, Vector3(0.035, 0, 0))
			fx.streak(muzzle, end, style, "#FF5FD2", 0.018, Vector3(-0.035, 0, 0))
		if style.get("style") == "stars":
			g.fx.burst(muzzle.lerp(end, 0.25 + randf() * 0.7), {"shape": "star", "count": 1, "speed": 0.6, "size": 0.07, "life": 0.45, "gravity": 0.5, "colors": [Config.PAL.marqueeGold, "#FFF3B0"]})
		if kind >= 3:
			g.fx.impact(end, pl[2], SURF[mini(kind - 3, 3)])
		elif kind == 2:
			fx.pop(end, 0.22, "#FFFFFF", 0.06)
		if def.get("splash") is Dictionary and def.splash.get("r") and kind != 0:
			_splashFx(end, float(def.splash.r), "#EAF6FF")
	if every13 and def.get("every13") is Dictionary:
		_splashFx(first, float(def.every13.get("r", 2.0)), "#FFE08A")
	for z in zs:
		var pt: Vector3 = z[0]
		var head: bool = z[1]
		fx.pop(pt, 0.42 if head else 0.3, "#FFE27A" if head else "#FFFFFF", 0.07)
		var back = (muzzle - pt).normalized()
		g.fx.burst(pt, {"shape": "spark", "count": 7 if head else 4, "dir": back, "cone": 0.9, "speed": 5, "life": 0.2, "size": 0.035})
		if head:
			g.fx.burst(pt, {"shape": "star", "count": 2, "speed": 2.2, "size": 0.08, "life": 0.5})
		if def.get("pageHits"):
			g.fx.burst(pt, {"shape": "confetti", "count": 7, "speed": 3, "size": 0.11, "life": 1.2, "colors": ["#F4F1E8", "#E6DCCB", "#FFFFFF", "#D9D2C2"], "dir": back, "cone": 1.3})
	W._muzzleFX(s, def, muzzle, (first - muzzle).normalized())
	var cue = FIRE_CUES.get(s.id)
	if cue != null and g.audio != null:
		g.audio.play(cue, {"pos": muzzle, "upgraded": s.upgraded})

func _splashFx(point: Vector3, r: float, color: String) -> void:
	var g = game
	W.fx.pop(point, r * 0.9, color, 0.12)
	if g.camera != null:
		W.fx.ring(point, (g.camera.global_position - point).normalized(), 0.15, r * 0.7, 0.22, color, false)
	g.fx.burst(point, {"shape": "star", "count": 6, "speed": 3.5, "size": 0.08, "life": 0.5, "colors": ["#FFFFFF", color]})
	g.fx.flashLight(point, color, 10, 0.12)
	W._play("studio_flash", {"pos": point, "vol": 0.8})

func _meleeHitFx(rp, kind: int, a: Vector3) -> void:
	var g = game
	var fx = W.fx
	if fx == null:
		return
	var from: Vector3 = rp.pos if rp != null else a
	var c = Vector3(a.x - from.x, 0, a.z - from.z)
	c = c.normalized() if c.length_squared() > 1e-6 else Vector3(0, 0, -1)
	if kind == 1:
		fx.pop(a, 0.6, "#FFFFFF", 0.09)
		if g.camera != null:
			fx.ring(a, (g.camera.global_position - a).normalized(), 0.1, 0.55, 0.18, "#FFE27A", false)
		g.fx.burst(a, {"shape": "star", "count": 5, "speed": 3, "size": 0.1, "life": 0.5})
		g.fx.burst(a, {"shape": "spark", "count": 8, "dir": c, "cone": 0.8, "speed": 6, "life": 0.2})
	else:
		fx.pop(a, 0.5, "#FFFFFF", 0.08)
		g.fx.burst(a, {"shape": "star", "count": 4, "speed": 2.5, "size": 0.09, "life": 0.45})
	if g.audio != null:
		var hero = rp.heroId if rp != null else null
		g.audio.play("melee_hit_" + (str(hero) if ["skip", "roxy", "penny", "duke"].has(hero) else "skip"), {"pos": a, "delay": 0.04})

# ------------------------------------------------------------------------------------------ remote held weapons
func buildRemoteHeld(remote, id: String, up: bool, sig: String) -> Variant:
	var a = _armsOf(remote)
	if a == null:
		return null
	return a.held(id, up, sig)

func _armsOf(rp):
	if rp == null or rp.get("isRemote") != true:
		return null
	var id := int(rp.peerId)
	var a = _arms.get(id)
	if a == null or a.rp != rp:
		if a != null:
			a.dispose()
		a = RemoteArms.new(self, rp)
		_arms[id] = a
	return a

# One remote avatar's weapon side: held models (cached per id|upgraded|signal), IK pose, props, sounds.
class RemoteArms extends RefCounted:
	var N
	var rp
	var WS
	var _cache := {}
	var cur = null              # current held record
	var key := ""
	var adsW := 0.0
	var sprintW := 0.0
	var busyW := 0.0
	var recoil := {"back": 0.0, "vb": 0.0, "rise": 0.0, "vr": 0.0, "roll": 0.0, "vroll": 0.0}
	var raise := 1.0
	var meleeT := -1.0
	var nadeState := "none"
	var nadeT := 0.0
	var teleT := -1.0
	var reloadPrev := 0.0
	var reloadCues := 0
	var pumpT := -1.0
	var partsU := 0.0           # reload progress the held copy's moving parts last showed
	var props := {}             # melee / nade / tele models in the left hand

	func _init(n, remote) -> void:
		N = n
		rp = remote
		WS = n.WS
		var me = self
		remote.postAnimate = func(r, rdt): me.pose(r, rdt)
		remote.weaponPose = func(rg, dt): me._pose(rg, dt, true)

	func dispose() -> void:
		if rp != null:
			rp.postAnimate = Callable()
		for k in _cache:
			var h: Dictionary = _cache[k]
			if is_instance_valid(h.holder) and h.holder.get_parent() == null:
				h.holder.free()
		_cache.clear()
		for k in props:
			var m = props[k]
			if m != null and is_instance_valid(m):
				DAU.detach(m)
				m.queue_free()
		props.clear()
		cur = null

	func held(id: String, up: bool, sig: String) -> Variant:
		var k = "%s|%d|%s" % [id, 1 if up else 0, sig]
		var h = _cache.get(k)
		if h == null:
			var def = WD.weaponDef(id, up)
			if def == null:
				return null
			var model: Node3D = WM.buildModel(id, up, sig if sig != "" else null, N.game)
			var holder := DAU.node3d("weaponHolder")
			holder.quaternion = WS.RH_FRAME.inverse()
			var sc: float = float(def.get("scale", 1.0)) if def.get("scale") else 1.0
			holder.scale = Vector3(sc, sc, sc)
			holder.add_child(model)
			var u := DAU.ud(model)
			var mz = DAU.byName(model, "muzzle")
			h = {"holder": holder, "model": model, "def": def,
				"leftHand": WS.v3a(u.leftHand) if u.get("leftHand") != null else Vector3(0, 0, -0.15),
				"butt": WS.v3a(u.butt) if u.get("butt") != null else Vector3(0, 0.08, 0.05),
				"muzzle": (mz as Node3D).position if mz is Node3D else Vector3(0, 0.08, -0.3),
				"parts": u.get("parts") if u.get("parts") is Dictionary else {}, "rest": {}}
			for pk in h.parts:
				var o = h.parts[pk]
				if o is Node3D:
					WS._xyzOrder(o)
					h.rest[o] = {"pos": o.position, "rot": o.rotation, "scale": o.scale, "visible": o.visible}
			_cache[k] = h
		if cur != null and not is_same(cur, h) and partsU > 0.001:
			_parts(0.0)                 # (a swap mid-reload: the old copy's parts back to rest)
		if key != "" and key != k:
			raise = 0.0
			N.W._play("weapon_swap", {"pos": rp.pos + Vector3(0, 1.2, 0), "vol": 0.8})
		key = k
		cur = h
		reloadPrev = 0.0
		return h.holder

	# ---- events
	func kick(def) -> void:
		var rc: Array = def.recoil if def.get("recoil") else [0.04, 0.15]
		recoil.vb += float(rc[0]) * 30.0
		recoil.vr += float(rc[1]) * 28.0
		recoil.vroll += (randf() - 0.5) * float(rc[1]) * 18.0

	func shot(def) -> void:
		if def.get("eject") == "brass":
			_eject("brass", 0.8)
		if def.get("mode") == "pump":
			pumpT = maxf(0.3, float(def.get("pumpTime", 0.85)) - 0.12) * 0.25

	func melee() -> void:
		meleeT = 0.0
		N.W._play("melee_whoosh", {"pos": rp.pos + Vector3(0, 1.2, 0)})
		_prop("melee", true)

	func cook() -> void:
		nadeState = "cook"
		nadeT = 0.0
		_prop("nade", true)

	func throwNade() -> void:
		nadeState = "throw"
		nadeT = 0.0

	func nadeDone() -> void:
		if nadeState == "cook":
			nadeState = "none"
			_prop("nade", false)

	func wind() -> void:
		teleT = 0.0
		_prop("tele", true)

	func _prop(which: String, on: bool) -> void:
		if rp == null or rp.hero == null:
			return
		var m = props.get(which)
		if m == null and on:
			var g = N.game
			if which == "melee":
				m = WM.buildMeleeProp(rp.heroId, g)
				if m != null:
					m.scale = Vector3(1.15, 1.15, 1.15)
					m.quaternion = WS.qEuler(0, PI, 0)
			elif which == "nade":
				m = WM.buildGrenadeModel(g)
				m.scale = Vector3(1.25, 1.25, 1.25)
			else:
				m = WM.buildTeleModel(g)
				m.scale = Vector3(0.9, 0.9, 0.9)
				m.quaternion = WS.qEuler(0, PI, 0)
			if m != null:
				DAU.setLayerRecursive(m, LAYER)
				props[which] = m
		if m == null:
			return
		var handL: Node3D = rp.hero.slots.handL
		if on and m.get_parent() != handL:
			DAU.detach(m)
			handL.add_child(m)
		m.visible = on

	func _eject(kind: String, speed: float) -> void:
		var h = cur
		if h == null or not h.model.is_inside_tree() or N.W.fx == null:
			return
		var mt: Transform3D = h.model.global_transform
		var a: Vector3 = mt * Vector3(0.03, h.muzzle.y * 0.9, h.butt.z * 0.1 - 0.06)
		var q: Quaternion = mt.basis.get_rotation_quaternion()
		var b := q * (Vector3(1.6 + randf() * 0.8, 1.6 + randf() * 1.2, 0.4 + randf() * 0.6) * speed)
		b.x += rp.vel.x * 0.8
		b.z += rp.vel.z * 0.8
		N.W.fx.eject(kind, a, b)

	# ---- per frame (timelines + sounds), called from weapons.update
	func tick(dt: float) -> void:
		if rp == null:
			return
		raise = minf(1.0, raise + dt / 0.28)
		if meleeT >= 0.0:
			meleeT += dt
			if meleeT >= float(WD.WEAPON_DEFS.melee.time):
				meleeT = -1.0
				_prop("melee", false)
		if nadeState != "none":
			nadeT += dt
			if nadeState == "cook" and nadeT > 2.2:
				nadeState = "none"
				_prop("nade", false)
			elif nadeState == "throw":
				if nadeT >= 0.36 * 0.42:
					_prop("nade", false)
				if nadeT >= 0.52:
					nadeState = "none"
		if teleT >= 0.0:
			teleT += dt
			if teleT >= 0.42 * 0.45:
				_prop("tele", false)
			if teleT >= 0.42:
				teleT = -1.0
		if pumpT >= 0.0:
			pumpT -= dt
			if pumpT < 0.0:
				N.W._play("wpn_pump_rack", {"pos": rp.pos + Vector3(0, 1.2, 0), "vol": 0.8})
				_eject("shell", 0.9)
		# reload beats from the replicated progress
		var u := float(rp.anim.get("reload", 0.0))
		if cur != null and u > 0.001:
			if reloadPrev <= 0.001:
				reloadCues = 0
			var def: Dictionary = cur.def
			var beats: Array = [0.0, 0.66] if def.get("fire") == "custom" else WS.RELOAD_BEATS.get(def.get("reloadKind"), [0.5])
			while reloadCues < beats.size() and u >= float(beats[reloadCues]):
				var cue: String = def.reloadCue if def.get("reloadCue") else "reload_mag"
				N.W._play(cue, {"pos": rp.pos + Vector3(0, 1.2, 0), "vol": 0.7, "rate": 0.9 if reloadCues == 0 else 1.1})
				reloadCues += 1
		reloadPrev = u
		_parts(u)

	# The held copy's moving parts (mag drop, drum swing, cover, battery, goo, reels) follow the streamed reload, like
	# weapons.gd _reloadParts on the owner's screen; back to rest when the reload ends.
	func _parts(u: float) -> void:
		var h = cur
		if h == null or h.get("parts") == null or h.parts.is_empty():
			partsU = 0.0
			return
		if u > 0.001:
			WS.reloadPartsOf(h, u)
		elif partsU > 0.001:
			for o in h.rest:
				if is_instance_valid(o):
					var r: Dictionary = h.rest[o]
					o.position = r.pos
					o.rotation = r.rot
					o.scale = r.scale
					o.visible = r.visible
		partsU = u

	# ---- pose (copy of weapons.gd _pose / _poseLeft on this avatar's replicated state)
	func pose(r, rdt: float) -> void:
		if r == null or r.animator == null or r.hero == null:
			return
		_springs(rdt)
		var ov = r.animator.override
		if ov != null and not (ov is Callable and not (ov as Callable).is_valid()):
			return
		_pose(r.rig, rdt, false)

	func _springs(dt: float) -> void:
		var k = 1.0 - exp(-dt / 0.06)
		adsW += ((1.0 if rp.ads else 0.0) - adsW) * k
		var spr: bool = rp.sprinting and float(rp.anim.speed) > 0.5
		sprintW += ((1.0 if spr else 0.0) - sprintW) * (1.0 - exp(-dt / 0.09))
		var busy := meleeT >= 0.0 or nadeState != "none" or teleT >= 0.0
		busyW += ((1.0 if busy else 0.0) - busyW) * (1.0 - exp(-dt / 0.05))
		var R := recoil
		var n := maxi(1, ceili(dt / (1.0 / 120.0)))
		var h := dt / n
		for i in n:
			R.vb += (-420.0 * R.back - 26.0 * R.vb) * h
			R.back += R.vb * h
			R.vr += (-336.0 * R.rise - 26.0 * R.vr) * h
			R.rise += R.vr * h
			R.vroll += (-420.0 * R.roll - 26.0 * R.vroll) * h
			R.roll += R.vroll * h

	func _aimDir() -> Vector3:
		return Vector3(-sin(rp.yaw) * cos(rp.pitch), sin(rp.pitch), -cos(rp.yaw) * cos(rp.pitch))

	func _pose(rig, _dt: float, _forced: bool) -> void:
		var p = rp
		if p == null or p.hero == null or not p.alive or p.downed or p.offAir or rig == null:
			return
		var J: Dictionary = rig.joints
		var h = cur
		var hasGun: bool = h != null and p.weaponModel != null and is_instance_valid(p.weaponModel) and is_same(p.weaponModel, h.holder) and p.weaponModel.visible
		var leftBusy: bool = meleeT >= 0.0 or nadeState != "none" or teleT >= 0.0
		if not hasGun and not leftBusy:
			return
		if not (J.chest as Node3D).is_inside_tree():
			return
		var def = h.def if hasGun else null
		var hold: Dictionary = WS.HOLDS.get(def.get("hold") if def != null and def.get("hold") else "pistol", WS.HOLDS.pistol)
		var dh = rig.dims.get("height") if rig.dims is Dictionary else null
		var hs: float = (float(dh) if dh else 1.8) / 1.8
		var aimDir := _aimDir()
		var eye: Vector3 = p.pos + Vector3(0, p.height * 0.92, 0)
		var aimPoint: Vector3 = p.aimPoint
		var aimDist := maxf(0.05, eye.distance_to(aimPoint))
		var blade: float = float(hold.chest) * (1.0 - sprintW) * (1.0 if hasGun else 0.0)
		J.chest.rotation.y += blade + _meleeTwist()
		J.head.rotation.y -= blade * 0.8
		J.spine.rotation.x += p.pitch * 0.12 * (1.0 - sprintW)
		var M: Vector3 = ((J.shoulderR as Node3D).global_position + (J.shoulderL as Node3D).global_position) * 0.5
		var qBody := Quaternion(UP, p.model.rotation.y)
		var a := aimPoint - M
		if a.length_squared() < 16.0 or a.dot(aimDir) < 0.0:
			a = eye + aimDir * (maxf(aimDist, 4.0) + 2.0) - M
		var qAim := Basis.looking_at(a.normalized(), UP).get_rotation_quaternion()
		if hasGun:
			var off: Vector3 = WS.v3a(hold.hip).lerp(WS.v3a(hold.ads), adsW) * hs
			var qGun := qAim
			if hold.get("pitch"):
				qGun = qGun * Quaternion(Vector3(1, 0, 0), float(hold.pitch) * (1.0 - adsW))
			var grip: Vector3
			if hold.mode == "butt":
				var sc: float = (h.holder as Node3D).scale.x
				grip = M + qAim * off - qGun * ((h.butt as Vector3) * sc)
			else:
				grip = M + qAim * off
			var R := recoil
			grip += qGun * Vector3(0, 0, R.back * hs)
			qGun = qGun * WS.qEuler(R.rise, 0, R.roll)
			var u := float(p.anim.get("reload", 0.0))
			if u > 0.001:
				var rl = WS.smooth(0, 0.14, u) * (1.0 - WS.smooth(0.86, 1, u))
				grip += qAim * (Vector3(-0.08, -0.07, 0.1) * (rl * hs))
				qGun = qGun * WS.qEuler(0.45 * rl, 0.25 * rl, -0.55 * rl)
			var lower = 0.0
			if raise < 1.0:
				lower = clampf(1.0 - WS.easeOutBack(raise, 1.6), -0.15, 1.0)
			if lower > 0.0:
				grip += qAim * (Vector3(0.04, -0.32, 0.14) * (lower * hs))
				qGun = qGun * WS.qEuler(-1.15 * lower, 0.35 * lower, 0)
			if sprintW > 0.001:
				var c = qBody * (Vector3(0.12, -0.36, -0.2) * hs) + M
				grip = grip.lerp(c, sprintW)
				qGun = qGun.slerp(qBody * WS.qEuler(-0.55, 0.75, 0.25), sprintW)
			if busyW > 0.001:
				var c2 = qBody * (Vector3(0.2, -0.28, -0.06) * hs) + M
				grip = grip.lerp(c2, busyW)
				qGun = qGun.slerp(qAim * WS.qEuler(-0.6, 0.55, 0.2), busyW)
			var qHand: Quaternion = qGun * WS.RH_FRAME
			var slotR: Vector3 = p.hero.slots.handR.position
			WS.solveArm(J.shoulderR, J.elbowR, J.handR, grip - qHand * slotR, qBody * WS.v3a(hold.poleR), qHand)
		_poseLeft(J, h if hasGun else null, hold, M, qAim, qBody, hs)

	func _swingStyle() -> String:
		var hp = WD.MELEE_PROPS.get(rp.heroId)
		return hp.swing if hp != null and hp.get("swing") else "chop"

	func _meleeTwist() -> float:
		if meleeT < 0.0:
			return 0.0
		var u: float = meleeT / float(WD.WEAPON_DEFS.melee.time)
		var S: Dictionary = WS.SWINGS.get(_swingStyle(), WS.SWINGS.chop)
		var wind = WS.smooth(0, 0.28, u)
		var strike = WS.smooth(0.28, 0.46, u)
		var back = WS.smooth(0.62, 1, u)
		return lerpf(S.twist[0] * wind, S.twist[1], strike) * (1.0 - back)

	func _poseLeft(J: Dictionary, h, hold: Dictionary, M: Vector3, qAim: Quaternion, qBody: Quaternion, hs: float) -> void:
		var p = rp
		var target := Vector3.ZERO
		var qL := Quaternion.IDENTITY
		var reach: float = WS.armReach(J.shoulderL, J.elbowL, J.handL) * 0.985
		var shoulderL: Vector3 = (J.shoulderL as Node3D).global_position
		var wOnGun := 1.0 if h != null else 0.0
		if h != null:
			var mt: Transform3D = (h.model as Node3D).global_transform
			var lh: Vector3 = h.leftHand
			var a := mt * lh
			if a.distance_to(shoulderL) > reach + 0.02:
				var b := Vector3(lh.x, lh.y, maxf(lh.z, -0.02))
				var lo := 0.0
				var hi := 1.0
				for i in 8:
					var m := (lo + hi) / 2.0
					if (mt * b.lerp(lh, m)).distance_to(shoulderL) <= reach:
						lo = m
					else:
						hi = m
				a = mt * b.lerp(lh, lo)
			target = a
			qL = mt.basis.get_rotation_quaternion() * WS.LH_FRAMES.get(hold.lh, WS.LH_FRAMES.under)
			var u := float(p.anim.get("reload", 0.0))
			if u > 0.001:
				var belt = WS.smooth(0.14, 0.32, u) * (1.0 - WS.smooth(0.5, 0.72, u))
				var bb: Vector3 = qBody * (WS.BELT_L * hs) + M
				target = target.lerp(bb, belt)
				if belt > 0.01:
					qL = qL.slerp(qBody, belt * 0.8)
		if meleeT >= 0.0:
			var u2: float = meleeT / float(WD.WEAPON_DEFS.melee.time)
			var S: Dictionary = WS.SWINGS.get(_swingStyle(), WS.SWINGS.chop)
			var wind = WS.smooth(0, 0.28, u2)
			var back = WS.smooth(0.62, 1, u2)
			var k = WS.smooth(0.28, 0.46, u2)
			var strike = k * k * (3.0 - 2.0 * k) if k < 1.0 else 1.0
			var b2 = WS.v3a(S.wind) * hs
			var c = WS.v3a(S.ctrl) * hs
			var d = WS.v3a(S.hit) * hs
			var o = strike + 0.12 * sin(PI * WS.smooth(0.46, 0.7, u2))
			var a0 = (1.0 - o) * (1.0 - o)
			var a1 = 2.0 * (1.0 - o) * o
			var a2 = o * o
			var v5 = qAim * Vector3(b2.x * a0 + c.x * a1 + d.x * a2, b2.y * a0 + c.y * a1 + d.y * a2, b2.z * a0 + c.z * a1 + d.z * a2) + M
			var w = maxf(wind, strike) * (1.0 - back)
			target = target.lerp(v5, w) if h != null else v5
			wOnGun = 1.0 if h != null else w
			var q2 = qAim * WS.qEuler(lerpf(S.rotW[0], S.rotH[0], strike), lerpf(S.rotW[1], S.rotH[1], strike), lerpf(S.rotW[2], S.rotH[2], strike))
			qL = qL.slerp(q2, w if h != null else 1.0)
		var throwing := nadeState != "none" or teleT >= 0.0
		if throwing:
			var wind2 = 0.0
			var fwd = 0.0
			var hold2 = 1.0
			if nadeState == "cook":
				hold2 = WS.smooth(0, 0.12, nadeT)
				wind2 = 0.35 * hold2
			elif nadeState == "throw" or teleT >= 0.0:
				var dur := 0.36 if nadeState == "throw" else 0.42
				var uu: float = (nadeT if nadeState == "throw" else teleT) / dur
				wind2 = lerpf(0.35, 1.0, WS.smooth(0, 0.3, uu)) if uu < 0.3 else 1.0 - WS.smooth(0.3, 0.5, uu)
				fwd = WS.smooth(0.28, 0.55, uu) * (1.0 - WS.smooth(0.8, 1, uu))
				hold2 = 1.0 - WS.smooth(0.85, 1, uu)
			var hb = qAim * (Vector3(-0.24, -0.02, -0.26) * hs) + M
			var hc = qAim * (Vector3(-0.32, 0.34, 0.24) * hs) + M
			var hd = qAim * (Vector3(-0.06, 0.1, -0.6) * hs) + M
			hb = hb.lerp(hc, wind2).lerp(hd, fwd)
			target = target.lerp(hb, hold2) if h != null else hb
			wOnGun = 1.0 if h != null else hold2
			var q3 = qAim * WS.qEuler(0.4 - fwd * 0.9, 0, 0.3)
			qL = qL.slerp(q3, hold2 if h != null else 1.0)
		if wOnGun <= 0.001:
			return
		var slotL: Vector3 = p.hero.slots.handL.position
		WS.solveArm(J.shoulderL, J.elbowL, J.handL, target - qL * slotL, qBody * WS.v3a(hold.poleL), qL)
