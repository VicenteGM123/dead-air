# PlayerMP — the players' life cycle in an online co-op game (MP_SPEC §4, RECONCILE R6/R12/R14): down, revive,
# bleed-out, off-air spectating, respawn, team wipe. Built by player.gd as `player.mp` only while game.net.inGame
# (solo never creates it); reset() at every MP newGame, dispose() when a solo game follows.
#
# AUTHORITY: health is the OWNER's (player.hurt runs on the owner; Instant Replay first). The LIFE STATE is the HOST's:
#   every transition is decided by the host and broadcast reliably, so revive vs bleed-out vs disconnect races resolve
#   in one place. The owner predicts its own "down" at once (no move / shoot) and asks the host.
# TEAM TABLE (every peer mirrors it from the host's broadcasts; the host's copy is authoritative):
#   team[id] = {state: ALIVE | DOWN | OFFAIR, pos (down position), bleedLeft (s, frozen while revived), bleedEnd (local
#   realNow when the bleed-out ends while nobody revives), reviver (peer id | 0), reviveAt (local realNow of the
#   revive start | -1), downs, revives}. stateOf(id) -> -1 | ALIVE | DOWN | OFFAIR, bleedOf(id) -> s left,
#   reviveProgress(id) -> 0..1 (being revived), net.teamSummary() reads downs / revives.
# RULES: lethal damage without Replay -> DOWN (kneels, camera low, can look around, cannot move / shoot / interact,
#   zombies ignore it). A teammate holds interact (E / X) REVIVE_TIME s within REVIVE_RANGE m of it (an interact hold
#   item that sits on the downed player): back up with full health, weapons / points / perks kept, REVIVE_GRACE s of
#   no damage. The bleed-out (BLEED_OUT s, param bleed=<s>) pauses while somebody revives. Bleed-out -> OFF AIR:
#   alive = false, perks.clearAll({poof}), CRT power-off, then spectating a teammate (fire / right / D-pad right =
#   next, aim / left / D-pad left = previous); the local player's pos / area follow the watched teammate (lights, fog,
#   audio, area culling follow the view: never use an off-air player's position for gameplay). Respawn at the next
#   round:start (host) near a living teammate (2 m ring, walkable + line of sight) else the slot spawn point, with
#   the starting loadout (weapons.resetLoadout() / loadout()) and RESPAWN_GRACE s of no damage; points kept.
#   Boss start (machine:boss_start): off-air players respawn in the yard (the fight pauses the rounds). Boss defeated
#   (boss:defeated) / hostReviveAll(): every downed player is revived and every off-air one respawned. Every player
#   down or off-air at once -> the host calls game.gameOver() (mp-core broadcasts net.teamSummary()); never while
#   the ending runs or the boss lies defeated.
# MESSAGES (sys "player": player.gd forwards net_<method> here; params untyped, validated):
#   client -> host (net.toHost; on the host the call is local, sender = requester):
#     downReq (pos: Vector3)        the sender went down at pos
#     reviveStart (target: int)     the sender started holding on target   reviveStop (target: int)   released
#     reviveDone (target: int)      the sender's hold completed
#   host -> everyone (net.everyone; the host runs the same handler):
#     downed (id, pos: Vector3, bleed: float)   reviveState (id, reviver: int (0 = nobody), bleedLeft: float)
#     revived (id, reviver: int (0 = host revive-all))   offAir (id)   respawn (id, pos: Vector3, yaw: float)
# EVENTS (game.events, every peer): team:down {id, pos}, team:reviving {id, by} (by 0 = stopped), team:revive {id,
#   by}, team:offair {id}, team:respawn {id, pos}, team:spectate {id} (local view changed), team:wipe {round} (host).
#   Local player: player:down {by}, player:revive {selfRevive: false, by}, player:offair {}, player:respawn {pos}.
# LOOKS (render fx layers, real time, ttl'd): 'mp_down' (desaturated, vignette, static rising with the bleed-out),
#   'mp_offair' (a watched feed: scanlines, grain), 'mp_tx' (CRT power-off at bleed-out, tune-in at respawn, a short
#   static blip at every spectate channel change). The 2D overlays are scripts/ui/hud_team.gd.
extends RefCounted

const ALIVE := 0
const DOWN := 1
const OFFAIR := 2
const BLEED_OUT := 30.0
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 1.8
const REVIVE_SLACK := 1.2        # m of tolerance on the host (interpolated positions, latency)
const REVIVE_GRACE := 1.5
const RESPAWN_GRACE := 2.5
const SPAWN_RING := 2.0
const OFF_T := 0.45              # s of CRT power-off before the view switches to a teammate
const ON_T := 0.45               # s of tune-in after a switch / a respawn
const ARCH_TAGS := ["wall", "glass", "fence", "door", "window", "lattice"]
# mp-story's boss-arena slots (yard), by slot
const YARD_SPOTS := [Vector2(37.0, -8.0), Vector2(37.0, -6.8), Vector2(38.2, -8.0), Vector2(38.2, -6.8)]

var p                       # the local Player
var game
var team := {}
var graceT := 0.0
var bleedTotal := BLEED_OUT
var specId := 0             # peer id of the spectated teammate (0: none)
var _items := {}            # downed teammate id -> interact item id
var _myRevive := 0          # target the local player is holding on (reviveStart sent)
var _predBleedEnd := 0.0    # local prediction of the own bleed-out until the host's downed echo
var _tx = null              # running view transition {kind: 'off' | 'on' | 'blip', t, switched}
var _wiped := false
var _unsub: Array = []
var _fxDown := {"saturation": 1.0, "vignette": 0.0, "static": 0.0, "chroma": 0.0}
var _fxOff := {"scanlines": 0.0, "grain": 0.0, "saturation": 1.0}
var _fxTx := {"collapse": 0.0, "static": 0.0}
var _los := {"camera": true, "ignoreTags": 0}
var _losCol = null

func _init(player, g) -> void:
	p = player
	game = g
	var ev = g.events
	_unsub.append(ev.on("round:start", func(_e = null): _onRoundStart()))
	_unsub.append(ev.on("machine:boss_start", func(_e = null): _onBossStart()))
	_unsub.append(ev.on("boss:defeated", func(_e = null): hostReviveAll("defeated")))
	_unsub.append(ev.on("net:peer", func(e = null): _onPeer(e)))
	_unsub.append(ev.on("state", func(e = null): _onState(e)))

func _net():
	return game.get("net")

func _on() -> bool:
	var n = game.get("net")
	return n != null and n.inGame

func _hostOk() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isHost and game.state == "playing"

func _fromHost() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.sender == 1

func _now() -> float:
	return float(game.time.realNow)

static func _entry() -> Dictionary:
	return {"state": ALIVE, "pos": Vector3.ZERO, "bleedLeft": 0.0, "bleedEnd": 0.0, "reviver": 0, "reviveAt": -1.0,
		"downs": 0, "revives": 0}

# A new MP game: everybody alive, nothing registered, the local view on the own hero.
func reset() -> void:
	_unregisterAll()
	team.clear()
	var n = _net()
	if n != null:
		for id in n.peers:
			team[int(id)] = _entry()
	graceT = 0.0
	specId = 0
	_myRevive = 0
	_wiped = false
	_tx = null
	bleedTotal = BLEED_OUT
	var b = game.params.get("bleed")
	if (b is int or b is float) and float(b) > 0.0:
		bleedTotal = float(b)
	p.spectate = null
	_camFollow(null)
	_showModel(true)
	_clearFx()

func dispose() -> void:
	_unregisterAll()
	for u in _unsub:
		if u is Callable and u.is_valid():
			u.call()
	_unsub.clear()
	team.clear()
	if p.offAir or p.spectate != null:
		p.spectate = null
		_camFollow(null)
	_showModel(true)
	_clearFx()

# ------------------------------------------------------------------------------------------------ queries
func stateOf(id) -> int:
	var e = team.get(int(id))
	return int(e.state) if e != null else -1

# Seconds of bleed-out left for a downed player (frozen while somebody revives).
func bleedOf(id) -> float:
	var e = team.get(int(id))
	if e == null:
		if int(id) == _localId() and p.downed:
			return maxf(0.0, _predBleedEnd - _now())
		return 0.0
	if e.state != DOWN:
		if int(id) == _localId() and p.downed:
			return maxf(0.0, _predBleedEnd - _now())
		return 0.0
	if int(e.reviver) != 0:
		return float(e.bleedLeft)
	return maxf(0.0, float(e.bleedEnd) - _now())

# 0..1 of a running revive on a downed player (extrapolated from the host's reviveState), -1 when nobody revives.
func reviveProgress(id) -> float:
	var e = team.get(int(id))
	if e == null or e.state != DOWN or int(e.reviver) == 0 or float(e.reviveAt) < 0.0:
		return -1.0
	return clampf((_now() - float(e.reviveAt)) / REVIVE_TIME, 0.0, 1.0)

func reviverOf(id) -> int:
	var e = team.get(int(id))
	return int(e.reviver) if e != null and e.state == DOWN else 0

func blocksDamage() -> bool:
	return p.offAir or graceT > 0.0

# player._vitals: the signal-loss target (base = 1 - HP / max).
func damageTarget(base: float) -> float:
	if p.offAir:
		return 0.0
	if p.downed:
		var k := 1.0 - clampf(bleedOf(_localId()) / maxf(0.1, bleedTotal), 0.0, 1.0)
		return 0.22 + 0.25 * k
	return base

func _localId() -> int:
	var n = _net()
	return int(n.localId) if n != null else 1

# ------------------------------------------------------------------------------------------------ per frame
func update(_dt: float, rdt: float) -> void:
	if not _on():
		return
	if graceT > 0.0:
		graceT = maxf(0.0, graceT - rdt)
	if _hostOk():
		_hostUpdate()
	_syncItems()
	if p.offAir:
		_updateSpectate()
	_updateFx(rdt)

# ------------------------------------------------------------------------------------------------ local: going down
# player.hurt at 0 HP without Instant Replay: kneel now (prediction), ask the host.
func goDown(fromPos = null) -> void:
	if p.downed or not p.alive or p.offAir:
		return
	var n = _net()
	p.downed = true
	p.health = 0.0
	p.anim.down = true
	p.vel = Vector3(0.0, minf(0.0, p.vel.y), 0.0)
	p.knock = Vector3.ZERO
	p.sprinting = false
	p.ads = false
	_predBleedEnd = _now() + bleedTotal
	if _myRevive != 0:
		_stopMyRevive()
	game.events.emit("player:down", {"by": _localId(), "from": fromPos})
	_play("hurt_static", {"vol": 0.9})
	if n != null and n.inGame:
		n.toHost("player", "downReq", [p.pos])

# ------------------------------------------------------------------------------------------------ host: requests
func net_downReq(pos) -> void:
	if not _hostOk() or _wiped:
		return
	var n = _net()
	var id: int = int(n.sender)
	var e = team.get(id)
	if e == null or e.state != ALIVE:
		return
	var at: Vector3 = pos if pos is Vector3 else _posOf(id)
	n.everyone("player", "downed", [id, at, bleedTotal])
	_checkWipe()

func net_reviveStart(target) -> void:
	if not _hostOk() or not (target is int or target is float):
		return
	var n = _net()
	var by: int = int(n.sender)
	var id := int(target)
	var e = team.get(id)
	var r = team.get(by)
	if e == null or r == null or e.state != DOWN or r.state != ALIVE or by == id:
		return
	if int(e.reviver) != 0:
		return   # first reviver wins (the same reviver's repeat is ignored too)
	var rp = n.playerById(by)
	if not _canReviveOthers(rp) or _hdist(rp.pos, e.pos) > REVIVE_RANGE + REVIVE_SLACK:
		return
	n.everyone("player", "reviveState", [id, by, bleedOf(id)])

func net_reviveStop(target) -> void:
	if not _hostOk() or not (target is int or target is float):
		return
	var n = _net()
	var id := int(target)
	var e = team.get(id)
	if e == null or e.state != DOWN or int(e.reviver) != int(n.sender):
		return
	n.everyone("player", "reviveState", [id, 0, bleedOf(id)])

func net_reviveDone(target) -> void:
	if not _hostOk() or not (target is int or target is float):
		return
	var n = _net()
	var by: int = int(n.sender)
	var id := int(target)
	var e = team.get(id)
	if e == null or e.state != DOWN or int(e.reviver) != by:
		return
	if float(e.reviveAt) < 0.0 or _now() - float(e.reviveAt) < REVIVE_TIME - 0.6:
		return
	var rp = n.playerById(by)
	if not _canReviveOthers(rp) or _hdist(rp.pos, e.pos) > REVIVE_RANGE + REVIVE_SLACK + 0.5:
		n.everyone("player", "reviveState", [id, 0, bleedOf(id)])
		return
	n.everyone("player", "revived", [id, by])

# Host, every frame: bleed-outs and stale revives.
func _hostUpdate() -> void:
	if _endingLock():
		return
	var n = _net()
	var now := _now()
	for id in team.keys():
		if _wiped or not _hostOk():
			return
		var e = team.get(id)
		if e == null or e.state != DOWN:
			continue
		var rv := int(e.reviver)
		if rv == 0:
			if now >= float(e.bleedEnd):
				n.everyone("player", "offAir", [id])
				_checkWipe()
			continue
		# the reviver went down / off-air / away / silent: the revive stops, the bleed-out resumes
		var rp = n.playerById(rv)
		var stale: bool = rp == null or not _canReviveOthers(rp) or _hdist(rp.pos, e.pos) > REVIVE_RANGE + 1.5 \
			or (float(e.reviveAt) >= 0.0 and now - float(e.reviveAt) > REVIVE_TIME + 2.5)
		if stale:
			n.everyone("player", "reviveState", [id, 0, bleedOf(id)])

func _checkWipe() -> void:
	if not _hostOk() or _wiped or team.is_empty() or _endingLock():
		return
	for id in team:
		if team[id].state == ALIVE:
			return
	_wiped = true
	game.events.emit("team:wipe", {"round": game.rounds.round if game.rounds != null else 0})
	game.gameOver()   # mp-core: broadcasts net.teamSummary() to every peer

# No bleed-out / wipe while the ending runs or the Baron lies defeated (mp-story).
func _endingLock() -> bool:
	var e = game.get("ending")
	if e != null and e.get("active") == true:
		return true
	var b = game.get("boss")
	return b != null and b.get("state") == "defeated"

# Boss defeated (or mp-story's call): everybody back on air. Host only; idempotent.
func hostReviveAll(kind: String = "defeated") -> void:
	var n = _net()
	if n == null or not n.inGame or not n.isHost:
		return
	for id in team.keys():
		var e = team.get(id)
		if e == null:
			continue
		if e.state == DOWN:
			n.everyone("player", "revived", [id, 0])
		elif e.state == OFFAIR:
			var sp := _respawnSpot(int(id), kind)
			n.everyone("player", "respawn", [id, sp.pos, sp.yaw])

func _onRoundStart() -> void:
	if not _hostOk():
		return
	_respawnOffAir("round")

func _onBossStart() -> void:
	if not _hostOk():
		return
	_respawnOffAir("boss")

func _respawnOffAir(kind: String) -> void:
	var n = _net()
	for id in team.keys():
		var e = team.get(id)
		if e != null and e.state == OFFAIR:
			var sp := _respawnSpot(int(id), kind)
			n.everyone("player", "respawn", [id, sp.pos, sp.yaw])

# A peer left (every peer gets it): forget it, free what it held, the host re-checks the wipe.
func _onPeer(e) -> void:
	if not (e is Dictionary) or e.get("joined") != false or not _on():
		return
	var id := int(e.get("id", 0))
	_unregisterRevive(id)
	team.erase(id)
	var n = _net()
	for other in team.keys():
		var t = team[other]
		if t.state == DOWN and int(t.reviver) == id:
			var left := bleedOf(other)
			t.reviver = 0
			t.reviveAt = -1.0
			t.bleedLeft = left
			t.bleedEnd = _now() + left
			if n.isHost:
				n.everyone("player", "reviveState", [other, 0, left])
	if specId == id:
		specId = 0
		p.spectate = null
	if n.isHost:
		_checkWipe()

func _onState(e) -> void:
	if not (e is Dictionary) or e.get("to") == "playing":
		return
	# game over / victory / back to the menu: drop the transient looks (the cards own the screen)
	_tx = null
	_clearFx()
	if e.get("to") == "menu":
		_unregisterAll()
		if p.spectate != null:
			p.spectate = null
			_camFollow(null)

# ------------------------------------------------------------------------------------------------ broadcasts (all)
func net_downed(id, pos, bleed) -> void:
	if not _fromHost() or not (id is int or id is float):
		return
	var pid := int(id)
	var e = team.get(pid)
	if e == null:
		var n = _net()
		if n == null or not n.peers.has(pid):
			return
		e = _entry()
		team[pid] = e
	if e.state == DOWN:
		return
	var b := clampf(float(bleed) if (bleed is float or bleed is int) else bleedTotal, 0.5, 600.0)
	e.state = DOWN
	e.pos = pos if pos is Vector3 else _posOf(pid)
	e.bleedLeft = b
	e.bleedEnd = _now() + b
	e.reviver = 0
	e.reviveAt = -1.0
	e.downs = int(e.downs) + 1
	if pid == _localId():
		_predBleedEnd = e.bleedEnd
		if not p.downed and p.alive:
			goDownForced()
	else:
		var rp = _net().playerById(pid)
		if rp != null:
			rp.downed = true
		_registerRevive(pid)
		_play("hurt_static", {"pos": e.pos, "vol": 0.7})
	game.events.emit("team:down", {"id": pid, "pos": e.pos})

# The host put the local player down without its request (out of sync): apply it locally.
func goDownForced() -> void:
	p.downed = true
	p.health = 0.0
	p.anim.down = true
	p.vel = Vector3.ZERO
	p.knock = Vector3.ZERO
	p.sprinting = false
	p.ads = false
	game.events.emit("player:down", {"by": _localId()})

func net_reviveState(id, reviver, left) -> void:
	if not _fromHost() or not (id is int or id is float) or not (reviver is int or reviver is float):
		return
	var pid := int(id)
	var e = team.get(pid)
	if e == null or e.state != DOWN:
		return
	var rv := int(reviver)
	var l := clampf(float(left) if (left is float or left is int) else bleedOf(pid), 0.0, 600.0)
	e.reviver = rv
	e.bleedLeft = l
	if rv != 0:
		e.reviveAt = _now()
	else:
		e.reviveAt = -1.0
		e.bleedEnd = _now() + l
	if pid == _localId():
		_predBleedEnd = _now() + l
	if _myRevive == pid and rv != _localId():
		_myRevive = 0   # somebody else revives it (or the host stopped ours): our item disables itself
	game.events.emit("team:reviving", {"id": pid, "by": rv})

func net_revived(id, reviver) -> void:
	if not _fromHost() or not (id is int or id is float):
		return
	var pid := int(id)
	var by := int(reviver) if (reviver is int or reviver is float) else 0
	var e = team.get(pid)
	if e == null or e.state != DOWN:
		return
	e.state = ALIVE
	e.reviver = 0
	e.reviveAt = -1.0
	if by != 0:
		var r = team.get(by)
		if r != null:
			r.revives = int(r.revives) + 1
	_unregisterRevive(pid)
	if _myRevive == pid:
		_myRevive = 0
	if pid == _localId():
		_localRevive(by)
	else:
		var rp = _net().playerById(pid)
		if rp != null:
			rp.downed = false
		_play("ui_tune_in", {"pos": e.pos, "vol": 0.6})
	game.events.emit("team:revive", {"id": pid, "by": by})

func _localRevive(by: int) -> void:
	p.downed = false
	p.alive = true
	p.anim.down = false
	p.anim.dead = 0.0
	p.health = p.maxHealth
	p.set("_sinceHurt", 99.0)
	p.knock = Vector3.ZERO
	p.vel = Vector3.ZERO
	graceT = REVIVE_GRACE
	game.events.emit("player:revive", {"selfRevive": false, "by": by})
	_play("ui_tune_in", {})

func net_offAir(id) -> void:
	if not _fromHost() or not (id is int or id is float):
		return
	var pid := int(id)
	var e = team.get(pid)
	if e == null or e.state == OFFAIR:
		return
	e.state = OFFAIR
	e.reviver = 0
	e.reviveAt = -1.0
	_unregisterRevive(pid)
	if _myRevive == pid:
		_myRevive = 0
	if pid == _localId():
		_localOffAir()
	else:
		var rp = _net().playerById(pid)
		if rp != null:
			rp.downed = false
			rp.offAir = true
			_puff(rp.pos, false)
	game.events.emit("team:offair", {"id": pid})

func _localOffAir() -> void:
	p.downed = false
	p.alive = false
	p.offAir = true
	p.anim.down = false
	p.health = 0.0
	p.vel = Vector3.ZERO
	p.knock = Vector3.ZERO
	p.sprinting = false
	p.ads = false
	if _myRevive != 0:
		_stopMyRevive()
	var pk = game.get("perks")
	if pk != null:
		if pk.has_method("clearAll"):
			pk.clearAll({"poof": true})
		elif pk.has_method("loseAll"):
			pk.loseAll()
	_tx = {"kind": "off", "t": 0.0, "switched": false}
	_play("crt_power_off", {"vol": 0.8})
	game.events.emit("player:offair", {})

func net_respawn(id, pos, yaw) -> void:
	if not _fromHost() or not (id is int or id is float) or not (pos is Vector3):
		return
	var pid := int(id)
	var e = team.get(pid)
	if e == null or e.state != OFFAIR:
		return
	e.state = ALIVE
	e.reviver = 0
	e.reviveAt = -1.0
	if pid == _localId():
		_localRespawn(pos, float(yaw) if (yaw is float or yaw is int) else 0.0)
	else:
		var rp = _net().playerById(pid)
		if rp != null:
			rp.offAir = false
			rp.alive = true
		_puff(pos, true)
	game.events.emit("team:respawn", {"id": pid, "pos": pos})

func _localRespawn(pos: Vector3, yaw: float) -> void:
	p.spectate = null
	specId = 0
	_camFollow(null)
	p.offAir = false
	p.alive = true
	p.downed = false
	p.anim.down = false
	p.anim.dead = 0.0
	p.health = p.maxHealth
	p.set("_sinceHurt", 99.0)
	p.stamina = float(Config.T.player.stamina)
	p.set("_exhausted", false)
	p.teleport(pos.x, pos.z, yaw)
	p.pitch = -0.08
	p.history.clear()
	_showModel(true)
	var W = game.get("weapons")
	if W != null:
		if W.has_method("resetLoadout"):
			W.resetLoadout()
		elif W.has_method("loadout"):
			W.loadout()
		else:
			push_warning("[player_mp] weapons.resetLoadout() missing: respawn keeps the old weapons")
	graceT = RESPAWN_GRACE
	_tx = {"kind": "on", "t": 0.0, "switched": true}
	_play("ui_tune_in", {})
	var H = game.get("hud")
	if H != null and H.has_method("whiteout"):
		H.whiteout(0.3, 0.35)
	_puff(pos, true)
	game.events.emit("player:respawn", {"pos": pos})

# ------------------------------------------------------------------------------------------------ revive items
# One interact hold item per downed teammate (interact.gd): E / X held REVIVE_TIME s within REVIVE_RANGE m.
func _registerRevive(id: int) -> void:
	var I = game.get("interact")
	if I == null or not I.has_method("register"):
		return
	var e = team.get(id)
	if e == null:
		return
	var key := "revive:%d" % id
	var at: Vector3 = e.pos
	I.register({"id": key, "pos": at + Vector3(0.0, 0.6, 0.0), "radius": REVIVE_RANGE, "height": 1.6,
		"hold": REVIVE_TIME,
		"enabled": func() -> bool: return _canReviveNow(id),
		"prompt": func() -> Dictionary: return {"revive": true},
		"onHold": func(_t = 0.0) -> void: _onHold(id),
		"onCancel": func() -> void: _onCancel(id),
		"use": func() -> void: _onDone(id)})
	_items[id] = key

func _unregisterRevive(id: int) -> void:
	var key = _items.get(id)
	if key == null:
		return
	_items.erase(id)
	var I = game.get("interact")
	if I != null and I.has_method("unregister"):
		I.unregister(key)

func _unregisterAll() -> void:
	for id in _items.keys():
		_unregisterRevive(int(id))
	_items.clear()
	_myRevive = 0

# Items sit on the (reliable) down position, which follows a downed player that was teleported (the boss start moves
# everybody into the yard); an item whose teammate is no longer down goes away.
func _syncItems() -> void:
	var n = _net()
	for id in team.keys():
		var e = team[id]
		if e.state != DOWN:
			continue
		var q = n.playerById(int(id))
		if q != null and _hdist(q.pos, e.pos) > 2.0:
			e.pos = q.pos
			var key = _items.get(id)
			var I = game.get("interact")
			if key != null and I != null and I.items.has(key):
				I.items[key].pos = e.pos + Vector3(0.0, 0.6, 0.0)
	if _items.is_empty():
		return
	for id in _items.keys():
		var e2 = team.get(id)
		if e2 == null or e2.state != DOWN:
			_unregisterRevive(int(id))

func _canReviveNow(id: int) -> bool:
	if game.get("mpPaused") == true:
		return false
	var e = team.get(id)
	if e == null or e.state != DOWN:
		return false
	var rv := int(e.reviver)
	if rv != 0 and rv != _localId():
		return false
	return _canReviveOthers(p)

# A player-like that may revive: alive, not downed / off-air / hidden / in a commercial, not locked by a cutscene.
func _canReviveOthers(q) -> bool:
	if q == null or not q.alive or q.downed:
		return false
	if q.get("offAir") == true or q.get("hidden") == true or q.get("inCommercial") == true:
		return false
	return q.get("controlLocked") != true and q.get("busy") != true

func _onHold(id: int) -> void:
	if _myRevive == id:
		return
	if _myRevive != 0:
		_stopMyRevive()
	_myRevive = id
	var n = _net()
	if n != null and n.inGame:
		n.toHost("player", "reviveStart", [id])

func _onCancel(id: int) -> void:
	if _myRevive != id:
		return
	_stopMyRevive()

func _stopMyRevive() -> void:
	var id := _myRevive
	_myRevive = 0
	var n = _net()
	if id != 0 and n != null and n.inGame:
		n.toHost("player", "reviveStop", [id])

func _onDone(id: int) -> void:
	var n = _net()
	if n != null and n.inGame:
		n.toHost("player", "reviveDone", [id])
	_myRevive = 0

# ------------------------------------------------------------------------------------------------ spectating
# Other players still on air (not off-air), the standing ones first, by slot order (net.players()).
func _candidates() -> Array:
	var n = _net()
	var up: Array = []
	var down: Array = []
	for q in n.players():
		if q == p:
			continue
		var id: int = n.idOf(q)
		var st := stateOf(id)
		if st == OFFAIR or id == 0:
			continue
		if st == DOWN or q.downed:
			down.append(q)
		else:
			up.append(q)
	up.append_array(down)
	return up

func _updateSpectate() -> void:
	var n = _net()
	if _tx != null and _tx.kind == "off" and not _tx.switched:
		return   # the CRT power-off still shows our own hero
	var cur = p.spectate
	var valid: bool = cur != null and specId != 0 and n.playerById(specId) == cur and stateOf(specId) != OFFAIR
	var list := _candidates()
	if not valid:
		_setSpectate(list[0] if not list.is_empty() else null, cur != null)
	elif game.get("mpPaused") != true and list.size() > 1:
		var I = game.input
		var dir := 0
		if I.pressed("fire") or I.pressed("right") or I.pressed("weapon2"):
			dir = 1
		elif I.pressed("aim") or I.pressed("left") or I.pressed("weapon1"):
			dir = -1
		if dir != 0:
			var i := list.find(cur)
			_setSpectate(list[(i + dir + list.size()) % list.size()], true)
	# ride along: presentation systems keyed off the local player's pos / area follow the view
	var s = p.spectate
	if s != null:
		p.pos = s.pos
		if s.area != null and s.area != "":
			p.area = s.area
		p.model.position = p.pos

func _setSpectate(q, blip: bool) -> void:
	var n = _net()
	if q == p.spectate:
		return
	p.spectate = q
	specId = n.idOf(q) if q != null else 0
	_camFollow(q)
	if q != null:
		if blip and (_tx == null or _tx.kind == "blip"):
			_tx = {"kind": "blip", "t": 0.0, "switched": true}
			_play("ui_round_dial", {"vol": 0.6})
		game.events.emit("team:spectate", {"id": specId})

func _camFollow(q) -> void:
	var c = game.get("cam")
	if c != null and c.has_method("spectate"):
		c.spectate(q)

# ------------------------------------------------------------------------------------------------ looks (fx layers)
func _updateFx(rdt: float) -> void:
	var R = game.get("render")
	if R == null or not R.has_method("setFx"):
		return
	# own downed look: desaturated, vignette, static creeping in as the bleed-out runs down
	if p.downed:
		var k := 1.0 - clampf(bleedOf(_localId()) / maxf(0.1, bleedTotal), 0.0, 1.0)
		var rev := reviveProgress(_localId())
		var lift := maxf(0.0, rev)
		_fxDown.saturation = lerpf(0.45, 0.85, lift)
		_fxDown.vignette = 0.55 * (1.0 - 0.5 * lift)
		_fxDown.static = (0.02 + 0.1 * k * k) * (1.0 - lift)
		_fxDown.chroma = 1.5 + 2.0 * k
		R.setFx("mp_down", _fxDown, {"ttl": 0.25})
	elif R.has_method("hasFx") and R.hasFx("mp_down"):
		R.clearFx("mp_down")
	# watching a teammate's feed
	if p.offAir and p.spectate != null and (_tx == null or _tx.switched):
		_fxOff.scanlines = 0.3
		_fxOff.grain = 0.06
		_fxOff.saturation = 0.85
		R.setFx("mp_offair", _fxOff, {"ttl": 0.25})
	elif R.has_method("hasFx") and R.hasFx("mp_offair"):
		R.clearFx("mp_offair")
	# transitions: CRT power-off -> switch -> tune-in; tune-in at respawn; a channel-change blip
	if _tx == null:
		return
	_tx.t += rdt
	var t: float = _tx.t
	if _tx.kind == "off":
		if not _tx.switched:
			var u := clampf(t / OFF_T, 0.0, 1.0)
			_fxTx.collapse = u
			_fxTx.static = 0.35 * u
			if t >= OFF_T:
				_tx.switched = true
				_tx.t = 0.0
				_showModel(false)
				_updateSpectate()
		else:
			var v := clampf(t / ON_T, 0.0, 1.0)
			_fxTx.collapse = 1.0 - v
			_fxTx.static = 0.45 * (1.0 - v)
			if t >= ON_T:
				_tx = null
	elif _tx.kind == "on":
		var v2 := clampf(t / ON_T, 0.0, 1.0)
		_fxTx.collapse = 0.0
		_fxTx.static = 0.5 * (1.0 - v2)
		if t >= ON_T:
			_tx = null
	else:
		var v3 := clampf(t / 0.22, 0.0, 1.0)
		_fxTx.collapse = 0.0
		_fxTx.static = 0.4 * (1.0 - v3)
		if t >= 0.22:
			_tx = null
	if _tx == null:
		R.clearFx("mp_tx")
	else:
		R.setFx("mp_tx", _fxTx, {"ttl": 0.25})

func _clearFx() -> void:
	var R = game.get("render")
	if R == null or not R.has_method("clearFx"):
		return
	R.clearFx("mp_down")
	R.clearFx("mp_offair")
	R.clearFx("mp_tx")

# ------------------------------------------------------------------------------------------------ helpers
func _showModel(on: bool) -> void:
	if p.model != null and p.model.visible != on:
		p.model.visible = on
	var b = p.get("blob")
	if b != null and b is Object and "visible" in b:
		b.visible = on

func _posOf(id: int) -> Vector3:
	var n = _net()
	var q = n.playerById(id) if n != null else null
	return q.pos if q != null else p.pos

static func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _play(id: String, opts: Dictionary) -> void:
	var a = game.get("audio")
	if a != null and a.has_method("play"):
		a.play(id, opts)

# Static puff where a player went off air (false) / a tune-in sparkle where one respawns (true).
func _puff(at: Vector3, on: bool) -> void:
	var f = game.get("fx")
	if f == null or not f.has_method("burst"):
		return
	var up := Vector3(at.x, at.y + 0.9, at.z)
	f.burst(up, {"shape": "static", "count": 16, "speed": 2.4, "size": 0.12, "life": 0.6})
	if on:
		f.burst(up, {"shape": "star", "count": 10, "speed": 3.0, "size": 0.09, "life": 0.6, "colors": ["#FFE27A", "#FFFFFF", "#7FE7FF"]})
	_play("crt_power_off" if not on else "ui_tune_in", {"pos": at, "vol": 0.5})

# Respawn spot for `id` (host): yard slot during the boss fight; else a 2 m ring around a living teammate (walkable,
# line of sight from its chest, starting behind it); else the slot spawn point. Deterministic (no RNG).
func _respawnSpot(id: int, kind: String) -> Dictionary:
	var n = _net()
	var slot: int = clampi(n.slotOf(id), 0, 3)
	var boss = game.get("boss")
	var bossOn: bool = kind == "boss" or (boss != null and boss.get("active") == true and kind != "defeated")
	if bossOn:
		var y: Vector2 = YARD_SPOTS[slot]
		var w := _walkableNear(y.x, y.y)
		return {"pos": _floor(w.x, w.y, 0.0), "yaw": PI / 2.0}
	for q in n.players():
		var qid: int = n.idOf(q)
		if qid == id or qid == 0 or stateOf(qid) != ALIVE or not n.isTargetable(q):
			continue
		var s = _ringSpot(q)
		if s != null:
			return s
	var sp: Dictionary = n.spawnPoint(slot)
	return {"pos": sp.pos, "yaw": float(sp.yaw)}

func _ringSpot(q) -> Variant:
	var nav = game.get("nav")
	var col = game.level.get("col") if game.level != null else null
	var chest: Vector3 = q.pos + Vector3(0.0, 1.0, 0.0)
	if col != null and not is_same(_losCol, col) and col.has_method("maskOf"):
		_losCol = col
		_los.ignoreTags = ~int(col.maskOf(ARCH_TAGS)) & 0x7fffffff
	for k in 8:
		# behind first, then alternating sides toward the front
		var off := (float((k + 1) / 2) * (PI / 4.0)) * (1.0 if k % 2 == 1 else -1.0)
		var a: float = float(q.yaw) + PI + off
		var x: float = q.pos.x - sin(a) * SPAWN_RING
		var z: float = q.pos.z - cos(a) * SPAWN_RING
		if nav != null and nav.has_method("walkable") and not nav.walkable(x, z):
			continue
		var at := _floor(x, z, q.pos.y)
		if col != null and col.has_method("raycast"):
			var d := (at + Vector3(0.0, 1.0, 0.0)) - chest
			var len := d.length()
			if len > 0.05:
				var hit = col.raycast(chest, d / len, len, _los)
				if hit != null and float(hit.dist) < len - 0.15:
					continue
		return {"pos": at, "yaw": atan2(-(q.pos.x - x), -(q.pos.z - z))}
	return null

func _walkableNear(x: float, z: float) -> Vector2:
	var nav = game.get("nav")
	if nav == null or not nav.has_method("walkable"):
		return Vector2(x, z)
	for ri in 9:
		var r := ri * 0.5
		var cnt := 1 if r == 0.0 else int(ceilf((2.0 * PI * r) / 0.5))
		for i in cnt:
			var a := (float(i) / cnt) * PI * 2.0
			if nav.walkable(x + cos(a) * r, z + sin(a) * r):
				return Vector2(x + cos(a) * r, z + sin(a) * r)
	return Vector2(x, z)

func _floor(x: float, z: float, y0: float) -> Vector3:
	var col = game.level.get("col") if game.level != null else null
	var f: float = col.floorAt(x, z, maxf(y0, 0.0) + 50.0) if col != null else -INF
	return Vector3(x, f if f > -INF else y0, z)
