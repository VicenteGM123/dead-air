# wonder_net.gd — the MP half of wonder.gd (RECONCILE R17/R19; mp-combat). Built by wonder.reset() only while an MP
# game runs (`wonder.mp`; null in solo). Every wonder RESOLUTION (victims, kills, statuses, lure, seats, puddle keys,
# slows) runs on the host; a client runs its own fire logic + visuals and sends a request; observers replay visuals.
# Wonder deaths travel with the kill: the host puts info.wfx (["gag", name, up, pulseR] / ["key", world, up] /
# ["tumble", dir, i] / ["suck", center]) into zombies.damage; mp-zombies calls wonder.corpseFx(z, wfx, by) on clients.
#
# MESSAGES (handlers = wonder.net_<name>, thin wrappers into this object)
#   client -> host  zap(up, ids, origin, dir)            Zapper victims picked by the shooter (aimed weapon)
#                   boomRec(on, up)                       Boom Mic recording on/off (host slows the shooter's cone)
#                   boomPlay(up, charge, origin, dir, mic) playback: host resolves the cones
#                   splash(sid, pos, normal, direct, up)  Chroma blob burst (direct = zombie id | "boss_baron" | null)
#                   tele(lid, origin, vel)                Tiny Tele throw (host spawns the real one)
#   host -> all     fx(kind, args)  kind 'live' [zid] (late-round survivor flicker), 'knock' [zid]
#                   signal(sig, ids, gen)                 resolved signal-colour targets (visual replay)
#                   boomRecFx(by, on, up) · boomFx(by, up, charge, origin, dir, mic) · splashFx(by, sid, pos, normal,
#                   direct, up) · teleSpawn(tid, by, lid, origin, vel) · teleLand(tid, pos, yaw) · teleSeat(tid, zid,
#                   seat, stand, dur) · teleBoom(tid)
#   wfx stream (weapons_net.gd): ZAP (trails for observers), BLOB (cosmetic goo flight for observers).
extends RefCounted

const WD = preload("res://scripts/game/weapon_defs.gd")
const DEG := PI / 180.0

var w                      # game.wonder
var game
var _tid := 0
var _lid := 0
var _sid := 0
var _rrec := {}            # host: by -> {up, t} remote Boom Mic recordings
var _recFx := {}           # observers: by -> loop handle
var _hooked := false

func _init(wonder) -> void:
	w = wonder
	game = wonder.game

func net():
	return game.get("net")

func authority() -> bool:
	var n = net()
	return n == null or not n.isClient

func localId() -> int:
	var n = net()
	return int(n.localId) if n != null else 1

func actorOf(by):
	var n = net()
	if by == null or n == null:
		return null
	return n.playerById(int(by))

func withSender(by: int, fn: Callable):
	var n = net()
	return n.withSender(by, fn) if n != null else fn.call()

func reset() -> void:
	_tid = 0
	_lid = 0
	_sid = 0
	_rrec.clear()
	for k in _recFx:
		w._hcall(_recFx[k], "stop", [0.05])
	_recFx.clear()
	if not _hooked and game.events != null:
		_hooked = true
		game.events.on("net:peer", func(e):
			if w.mp == self and e is Dictionary and e.get("joined") == false:
				_peerLeft(int(e.get("id", 0))))

func _peerLeft(id: int) -> void:
	if _rrec.has(id):
		_stopRec(id)
	if _recFx.has(id):
		w._hcall(_recFx[id], "stop", [0.1])
		_recFx.erase(id)
	for i in range(w._blobs.size() - 1, -1, -1):
		var b: Dictionary = w._blobs[i]
		if b.get("remote") and int(b.get("by", 0)) == id:
			w._drop(b.mesh)
			w._blobs.remove_at(i)

func update(dt: float) -> void:
	if not _rrec.is_empty() and authority():
		for by in _rrec.keys():
			_updateRec(int(by), dt)
	for by in _recFx:
		var rp = actorOf(by)
		if rp != null:
			w._hcall(_recFx[by], "setPos", [rp.pos + Vector3(0, 1.3, 0)])

func _z(id):
	if id == null:
		return null
	if id is String:
		for z in w._zombies():
			if str(w._g(z, "id")) == id:
				return z
		return null
	var zm = game.zombies
	if zm != null and zm.has_method("byId"):
		return zm.byId(int(id))
	for z in w._zombies():
		if w._g(z, "id") == int(id):
			return z
	return null

# ------------------------------------------------------------------------------------------ Zapper
func zapOut(up: bool, muzzle: Vector3, end: Vector3, victims: Array, ctx) -> void:
	var pts: Array = []
	var ids: Array = []
	for z in victims:
		pts.append(w._chest(z))
		ids.append(w._g(z, "id"))
	var W = game.weapons
	if W != null and W.mp != null:
		W.mp.zap(up, muzzle, end, pts)
	var n = net()
	if n != null and n.isClient:
		n.toHost("wonder", "zap", [up, ids, ctx.origin if ctx != null else muzzle, ctx.dir if ctx != null else Vector3.ZERO])

func onZap(up, ids) -> void:
	var n = net()
	if n == null or n.isClient or not (ids is Array):
		return
	var by: int = n.sender
	var u := up == true
	var def = WD.weaponDef("zapper", u)
	var delay := 0.07
	for id in ids.slice(0, 12):
		var z = _z(id)
		if z == null or not w._alive(z):
			delay += 0.075
			continue
		w._claimed[w._zk(z)] = true
		var zz = z
		w._later(delay, func(): w._asBy(by, func(): w._zapHit(zz, u, def)))
		delay += 0.075

# Observers: trails + per-victim sparks of another player's zap (from the wfx stream).
func remoteZap(rp, up: bool, mz: Vector3, end: Vector3, pts: Array) -> void:
	var muzzle := mz
	if rp != null and rp.weaponModel != null and is_instance_valid(rp.weaponModel) and rp.weaponModel.visible:
		muzzle = rp.muzzle()
	var cols: Array = ["#FF5FA2", "#FFE14D", "#5FE3FF", "#9CFF57"] if up else ["#7FE7FF", "#D64FD6", "#F4E03A"]
	var first: Vector3 = pts[0] if not pts.is_empty() else end
	w._ringTrail(muzzle, first, cols, 0.0, 9 if up else 7, 0.14)
	w._fx("muzzle", [muzzle, (first - muzzle).normalized(), cols[0]])
	w._fx("flashLight", [muzzle, cols[0], 6, 0.1])
	if pts.is_empty():
		w._fx("burst", [end, {"shape": "static", "count": 8, "size": 0.06, "life": 0.4}])
	var delay := 0.07
	for i in pts.size():
		var pt: Vector3 = pts[i]
		if i > 0:
			w._ringTrail(pts[i - 1], pt, cols, delay - 0.06, 5, 0.1)
		w._later(delay, func():
			w._fx("burst", [pt, {"shape": "static", "count": 10, "size": 0.08, "life": 0.35}])
			w._fx("burst", [pt, {"shape": "spark", "count": 6, "size": 0.04, "speed": 4, "life": 0.25, "colors": ["#FF5FA2", "#FFE14D", "#5FE3FF"] if up else ["#7FE7FF", "#FFFFFF"]}]))
		delay += 0.075
	w._play("wpn_zapper", {"pos": muzzle, "upgraded": up})

# ------------------------------------------------------------------------------------------ host -> all visuals
func fxOut(kind: String, args: Array) -> void:
	var n = net()
	if n != null and n.isHost:
		n.toAll("wonder", "fx", [kind, args])

func onFx(kind, args) -> void:
	if authority() or not (args is Array) or args.is_empty():
		return
	var z = _z(args[0])
	if z == null:
		return
	if kind == "live":
		w._akick(z, 1.0)
		w._flashLive(z)
	elif kind == "knock":
		w._akick(z, 1.2)

func signalOut(sig: String, zs: Array, gen: int) -> void:
	var n = net()
	if n == null or not n.isHost:
		return
	var ids: Array = []
	for z in zs:
		ids.append(w._g(z, "id"))
	n.toAll("wonder", "signal", [sig, ids, gen])

func onSignal(sig, ids, gen) -> void:
	if authority() or not (ids is Array):
		return
	var zs: Array = []
	for id in ids:
		var z = _z(id)
		if z != null:
			zs.append(z)
	if zs.is_empty():
		return
	match str(sig):
		"hot_mic":
			for z in zs:
				w._ignite(z, int(gen) if (gen is int or gen is float) else 1, null)
		"laugh_track":
			w._laughGroup(zs)
		"cold_open":
			w._coldGroup(zs[0], zs.slice(1))
	game.events.emit("wonder:signal", {"z": zs[0], "signal": str(sig), "weaponId": null, "splash": false})

# ------------------------------------------------------------------------------------------ Boom Mic
func boomRecOut(on: bool, up: bool) -> void:
	var n = net()
	if n == null:
		return
	if n.isClient:
		n.toHost("wonder", "boomRec", [on, up])
	else:
		n.toAll("wonder", "boomRecFx", [n.localId, on, up])

func onBoomRec(on, up) -> void:
	var n = net()
	if n == null or n.isClient:
		return
	var by: int = n.sender
	if on == true:
		_rrec[by] = {"up": up == true, "t": 0.0}
	elif _rrec.has(by):
		_stopRec(by)
	_recVisual(by, on == true)
	n.toAll("wonder", "boomRecFx", [by, on == true, up == true])

func onBoomRecFx(by, on, _up) -> void:
	if int(by) == localId() or authority():
		return
	_recVisual(int(by), on == true)

func _recVisual(by: int, on: bool) -> void:
	if on and not _recFx.has(by):
		var rp = actorOf(by)
		var A = game.audio
		if A != null and A.has_method("loop"):
			_recFx[by] = A.loop("wpn_boom_record", {"pos": rp.pos + Vector3(0, 1.3, 0) if rp != null else Vector3.ZERO})
	elif not on and _recFx.has(by):
		w._hcall(_recFx[by], "stop", [0.08])
		_recFx.erase(by)

func _updateRec(by: int, dt: float) -> void:
	var r: Dictionary = _rrec[by]
	r.t = float(r.t) + dt
	var rp = actorOf(by)
	var def = WD.weaponDef("boom_mic", r.up)
	var RC = def.get("record", {}) if def != null else {}
	if rp == null or not rp.alive or rp.downed or r.t > float(RC.get("max", 3.0)) + 1.0:
		_stopRec(by)
		return
	var ray: Dictionary = rp.aimRay()
	var zs: Array = w._inCone(ray.origin, ray.dir, float(RC.get("range", 12.0)), (float(RC.get("cone", 40.0)) / 2.0) * DEG, rp)
	var key := "rec%d" % by
	var now := {}
	for z in zs:
		now[w._zk(z)] = true
		w._slow(z, key, float(RC.get("slow", 0.35)))
	for k in w._status.keys():
		var s = w._status.get(k)
		if s != null and s.slows != null and s.slows.has(key) and not now.has(k):
			w._unslow(s.z, key)

func _stopRec(by: int) -> void:
	_rrec.erase(by)
	var key := "rec%d" % by
	for k in w._status.keys():
		var s = w._status.get(k)
		if s != null and s.slows != null and s.slows.has(key):
			w._unslow(s.z, key)

func boomPlayOut(up: bool, ch: float, origin: Vector3, dir: Vector3, mic: Vector3) -> void:
	var n = net()
	if n == null:
		return
	if n.isClient:
		n.toHost("wonder", "boomPlay", [up, ch, origin, dir, mic])
	else:
		n.toAll("wonder", "boomFx", [n.localId, up, ch, origin, dir, mic])

func onBoomPlay(up, ch, origin, dir, mic) -> void:
	var n = net()
	if n == null or n.isClient or not (origin is Vector3) or not (dir is Vector3) or not (mic is Vector3):
		return
	var by: int = n.sender
	if _rrec.has(by):
		_stopRec(by)
	_recVisual(by, false)
	var u := up == true
	var c := clampf(float(ch) if (ch is float or ch is int) else 0.0, 0.0, 10.0)
	var def = WD.weaponDef("boom_mic", u)
	var rp = actorOf(by)
	var cones: Array = w._boomCones(dir, c, u)
	w._asBy(by, func(): w._playCones(origin, dir, cones, u, def, mic, rp, true))
	_playFx(u, c, mic)
	n.toAll("wonder", "boomFx", [by, u, c, origin, dir, mic])

func onBoomFx(by, up, ch, origin, dir, mic) -> void:
	if int(by) == localId() or authority() or not (origin is Vector3) or not (dir is Vector3) or not (mic is Vector3):
		return
	_recVisual(int(by), false)
	var u := up == true
	var c := clampf(float(ch), 0.0, 10.0)
	var def = WD.weaponDef("boom_mic", u)
	w._playCones(origin, dir, w._boomCones(dir, c, u), u, def, mic, actorOf(by), false)
	_playFx(u, c, mic)

func _playFx(up: bool, ch: float, mic: Vector3) -> void:
	w._play("wpn_boom_playback", {"upgraded": up, "pos": mic})
	if up:
		w._play("wpn_upgraded_sparkle", {"pos": mic})
	w._fx("flashLight", [mic, "#FF5FA2", 5 + ch, 0.15])

# ------------------------------------------------------------------------------------------ Chroma-Key
func blobLaunched(b: Dictionary, from: Vector3, vel: Vector3, up: bool) -> void:
	_sid += 1
	b.sid = _sid
	var W = game.weapons
	if W != null and W.mp != null:
		W.mp.blob(up, _sid, from, vel)

func blobBurst(b: Dictionary, pos: Vector3, normal, direct) -> void:
	var n = net()
	var nrm: Vector3 = normal if normal is Vector3 else Vector3.UP
	if n != null and n.isClient:
		w._splash(pos, nrm, b.up, b.def, direct, false)
		n.toHost("wonder", "splash", [int(b.get("sid", 0)), pos, nrm, w._g(direct, "id") if direct != null else null, b.up == true])
	else:
		w._splash(pos, nrm, b.up, b.def, direct)
		if n != null:
			n.toAll("wonder", "splashFx", [localId(), int(b.get("sid", 0)), pos, nrm, direct != null, b.up == true])

func remoteBlob(by: int, sid: int, up: bool, from: Vector3, vel: Vector3) -> void:
	if by == localId():
		return
	var R = w.res
	var C: Dictionary = w.get_script().G.chroma
	var def = WD.weaponDef("chroma_key", up)
	var B = def.get("blob", {}) if def != null else {}
	var r := float(B.get("r", C.r))
	var mesh = w._mi(R.blobGeo, R.mGooUp if up else R.mGoo)
	mesh.scale = Vector3.ONE * r
	mesh.position = from
	game.scene.add_child(mesh)
	w._blobs.append({"pos": from, "vel": vel, "t": 0.0, "up": up, "def": def, "mesh": mesh, "bounces": int(B.get("bounces", 1 if up else 0)), "r": r,
		"grav": float(B.get("gravity", C.grav)), "life": float(B.get("life", C.fuse)), "trail": 0.0, "seed": randf() * 10.0, "squash": 0.0,
		"remote": true, "by": by, "sid": sid})
	var P: Dictionary = Config.PAL
	w._fx("burst", [from, {"shape": "goo", "count": 6, "dir": vel.normalized(), "cone": 0.5, "speed": 4, "size": 0.07, "colors": [P.greenScreen, "#9CFF57"] if up else [P.chromaBlue, "#4F86FF"]}])
	w._play("wpn_chroma_fire", {"pos": from})

func _dropBlob(by: int, sid: int) -> void:
	for i in range(w._blobs.size() - 1, -1, -1):
		var b: Dictionary = w._blobs[i]
		if b.get("remote") and int(b.get("by", 0)) == by and int(b.get("sid", -1)) == sid:
			w._drop(b.mesh)
			w._blobs.remove_at(i)

func onSplash(sid, pos, normal, directId, up) -> void:
	var n = net()
	if n == null or n.isClient or not (pos is Vector3):
		return
	var by: int = n.sender
	var u := up == true
	var nrm: Vector3 = normal if normal is Vector3 else Vector3.UP
	_dropBlob(by, int(sid))
	var direct = _z(directId)
	var def = WD.weaponDef("chroma_key", u)
	w._asBy(by, func(): w._splash(pos, nrm, u, def, direct))
	n.toAll("wonder", "splashFx", [by, int(sid), pos, nrm, direct != null, u])

func onSplashFx(by, sid, pos, normal, direct, up) -> void:
	if int(by) == localId() or authority() or not (pos is Vector3):
		return
	_dropBlob(int(by), int(sid))
	var u := up == true
	w._splash(pos, normal if normal is Vector3 else Vector3.UP, u, WD.weaponDef("chroma_key", u), true if direct == true else null, false)

# ------------------------------------------------------------------------------------------ Tiny Tele
func _findTele(key: String, v: int):
	for t in w.teles:
		if int(t.get(key, -1)) == v:
			return t
	return null

# Every new tele (w._spawnTele): returns true when the LOCAL player threw it (its recoil plays).
func teleSpawned(t: Dictionary, ctx) -> bool:
	var n = net()
	if n == null:
		return true
	var c: Dictionary = ctx if ctx is Dictionary else {}
	if c.get("copy") == true:                 # a client's copy of someone else's tele (teleSpawn)
		t.auth = false
		t.tid = int(c.tid)
		t.by = int(c.by)
		return false
	if c.get("by") != null:                    # host spawning a client's tele (tele request)
		_tid += 1
		t.auth = true
		t.tid = _tid
		t.by = int(c.by)
		n.toAll("wonder", "teleSpawn", [_tid, t.by, int(c.get("lid", -1)), t.pos, t.vel])
		return false
	t.by = n.localId
	if n.isClient:
		_lid += 1
		t.auth = false
		t.lid = _lid
		n.toHost("wonder", "tele", [_lid, t.pos, t.vel])
	else:
		_tid += 1
		t.auth = true
		t.tid = _tid
		n.toAll("wonder", "teleSpawn", [_tid, n.localId, -1, t.pos, t.vel])
	return true

func onTele(lid, origin, vel) -> void:
	var n = net()
	if n == null or n.isClient or not (origin is Vector3) or not (vel is Vector3):
		return
	w._spawnTele({"origin": origin, "velocity": vel, "by": n.sender, "lid": int(lid)})

func onTeleSpawn(tid, by, lid, origin, vel) -> void:
	if authority() or not (origin is Vector3) or not (vel is Vector3):
		return
	if int(by) == localId():
		var t = _findTele("lid", int(lid))
		if t != null:
			t.tid = int(tid)
		return
	w._spawnTele({"origin": origin, "velocity": vel, "copy": true, "by": int(by), "tid": int(tid)})

func teleLanded(t: Dictionary) -> void:
	var n = net()
	if n != null and n.isHost and t.get("auth", true):
		n.toAll("wonder", "teleLand", [int(t.get("tid", 0)), t.pos, float(t.yaw)])

func onTeleLand(tid, pos, yaw) -> void:
	if authority() or not (pos is Vector3):
		return
	var t = _findTele("tid", int(tid))
	if t == null:
		return
	w._telePos(t, pos)
	if t.state == "fly":
		t.state = "land"
		t.t = 0.0
		t.vel = Vector3.ZERO
		t.floor = pos.y
		t.q0 = t.spin.quaternion
	t.yaw = float(yaw)
	t.q1 = w.qAxis(Vector3.UP, t.yaw)

func teleSeatOut(t: Dictionary, z, seat: Dictionary) -> void:
	var n = net()
	if n != null and n.isHost:
		n.toAll("wonder", "teleSeat", [int(t.get("tid", 0)), w._g(z, "id"), seat.pos, seat.stand == true, float(seat.dur)])

func onTeleSeat(tid, zid, seat, stand, dur) -> void:
	if authority() or not (seat is Vector3):
		return
	var t = _findTele("tid", int(tid))
	var z = _z(zid)
	if t == null or z == null:
		return
	var s: Dictionary = w._stat(z)
	s.seat = {"tele": t, "pos": seat, "from": z.pos, "t": 0.0, "stand": stand == true, "dur": float(dur), "yaw0": float(w._or(w._g(z, "yaw"), 0.0)), "plopped": false}
	s.t = 0.0
	t.seated[w._zk(z)] = z
	w._applyPose(z)

func teleBoomOut(t: Dictionary) -> void:
	var n = net()
	if n != null and n.isHost:
		n.toAll("wonder", "teleBoom", [int(t.get("tid", 0))])

func onTeleBoom(tid) -> void:
	if authority():
		return
	var t = _findTele("tid", int(tid))
	if t == null or t.state == "implode":
		return
	t.state = "implode"
	t.t = 0.0
	w._teleBoom(t)
