# Economy + purchasable interactables (port of src/game/economy.js; ARCHITECTURE §10, GDD §5.3 doors, §5.4
# barricades, §6.3–§6.4, §9.1 wall-buys, §14 prompt rules). Owner: econ.
#
# POINTS
#   economy.points (int, never negative)   economy.earned / economy.spent (run totals)
#   economy.multiplier   1, or 2 during SWEEPS WEEK. Plain read/write (powerups.gd writes it); reads also return 2
#                        while powerups.active.sweeps_week > 0, so either side can drive it.
#   add(n, reason='misc') -> points actually added (n × multiplier, rounded, >= 0)
#   canAfford(n) -> bool       spend(n, reason='buy') -> bool (short: emits points:denied {cost}, nothing spent)
#   Every change emits points:change {points, delta, reason} and calls hud.pointsPopup(delta).
#   Start points: params.points, else T.player.startPoints.
#
# PURCHASES (each also reachable without the interact prompt — used by tests / other systems)
#   buyDoor(doorId) -> bool          spend T.doors[id] then level.openDoor(id) (the door plays its own beat: poof,
#                                    chain snap, D5 keypad motif, crowd ooh). Short: bzzt + the door rattles.
#   buyWallbuy(anchorId) -> bool     wb_pump / wb_mp7 / wb_m16: first buy pops the prop gun off the poster into the
#                                    hands (0.3 s arc; weapons.give(id, {source:'wallbuy'}) on the catch -> boing) and
#                                    Duke winks (poster canvas swap, kept while the gun is owned). Owned: ammo refill
#                                    (T.wallbuys[id][1], or T.wallbuys.upgradedAmmo when upgraded); no prompt while full.
#                                    wb_grenades ("Tube-O-Matic" case, T.wallbuys.grenades): the missing tubes hop out
#                                    into the hands, +1 grenade per tube caught (up to T.player.grenadesMax).
#   repairWindow(windowId) -> bool   level.windows[id].repairBoard() (+ T.points.board, capped T.points.boardCap per round)
#   priceOf(interactId | doorId | anchorId) -> cost | null (what the prompt would show now)
#
# INTERACTABLES (game.interact; prompts are only {cost} / {} + hold ring, never names — GDD §14)
#   econ:door:<doorId>:<areaId>  one per face of every closed paid door (DY has none: it opens itself at power);
#                                each declares its face normal
#   econ:wb:<anchorId>           wall-buys and the grenade case, facing = anchor rotY (front side of the wall only)
#   interact.gd also requires line of sight from the player's head (architecture colliders): no buying through walls
#   econ:win:<windowId>          boarded windows missing boards: hold E, one board per 0.6 s while E stays down
#
# EVENTS emitted: points:change, points:denied (canonical) and economy:buy {kind:'door'|'wallbuy'|'ammo'|
#   'grenades', id, cost}. Listens: round:start (resets the board-points cap).
# SOUNDS: ui_buy (ka-ching) / ui_denied (bzzt) / wallbuy_boing come from audio.gd hookups (spend, points:denied,
#   weapon:acquire source 'wallbuy' on the catch); door beats + crowd_ooh from level/doors (D5: door_keypad_motif);
#   board_repair from windows.gd. Played here: pump ammo reload_shell x2 + wpn_pump_rack, other ammo reload_mag x2,
#   dry_fire as the spring-clip / glass-flap clicks, grenade_bounce per caught tube + wallbuy_boing (tube refill).
# FEEL: door buy = gold stars + confetti + small shake, denied = the blocker rattles; wall-buy = poster wobble on
#   its top edge, wink sparkle, clips spring open, cubic-bezier hop with a barrel roll, stretch and a star trail,
#   catch sparkle + cam kick, gun pops back (easeOutBack) and the clips snap shut; ammo = gun hops on its clips +
#   brass confetti; denied = the gun shivers. Tube-O-Matic: marquee chase (all lit while busy), glass flap swings up,
#   tubes pop out one by one into the hands, rise back into the sockets. Barricade: dust puff + sparks + tiny shake.
#
# Frame driver: Game's UPDATE_ORDER has no 'economy' entry, so update(dt) is also driven from a render pre-pass
# (skipped on frames where Game already called update, and outside 'playing' / 'down'). World dt: every tween
# freezes with time.scale = 0 / hitStop. The barricade hold loop re-arms interact's one-completion-per-press latch
# (interact._holdDone) while E stays down, so a held E keeps repairing.
#
# Godot port notes
# * Static geometry the JS assembled at runtime is the Blender asset built by blender/runtime/economy.py:
#   res://assets/runtime/economy/wallbuy_<weaponId>.glb (lightbox frame + picture light "frame", "poster" plane,
#   gun contact "shadow" plane, two brass bulldog clips "clip_0"/"clip_1" hinged at their pivots; root extras "da" =
#   {W, H, len, gh, gd, gcx}) and tube_o_matic.glb (cabinet "body", sunburst "panel", "strip" light, "signBox",
#   "sign", 22 "marquee" bulbs marquee_<i>, the "glass" flap hinged on its top edge). Guns / tubes are prop library
#   instances (game.props.build). Canvas textures drawn at runtime (glint star) use DACanvas (scripts/gfx/canvas2d.gd).
# * Node names cannot contain ':' in Godot: the JS group 'wallbuy:<id>' is the node "wallbuy_<id>".
# * mergeByMaterial / flattenMerge (draw-call merging) and warmup() (shader precompile) are engine plumbing: not ported.
#   The rack's merged filaments (rackGlow) are the list of the rack tubes' glow meshes, toggled together.
# * try/catch (_safe/_tick) become straight calls: a GDScript runtime error aborts only the failing call.
# * No renames (§3.2) were needed.
#
# MP (online co-op, RECONCILE R1/R2/R15; every path below is behind net.inGame — solo runs the code above unchanged):
#   POINTS are per player and owned by each peer (economy.points = the LOCAL player's). The host decides every world
#   award and routes it: add(n, reason, to := null) on the host -> recipient = `to` (attacker peer id; ALL = -1 for
#   everyone) > TEAM_REASONS (cancelled, gaffer, egg, morning: +n to EVERY player) > credit(peer) scope > net.sender
#   (the client whose request is being handled) > the host; the delta is final (host multiplier) and reaches the peer
#   as economy.net_award(delta, reason). A client ignores add() for HOST_REASONS (hit, kill, kill_bonus, board,
#   cancelled, gaffer, egg, morning, telly_refund) — never awarded twice — and applies other reasons (debug) locally.
#   Host event points:award {by (recipient, -1 = all), delta, reason} (power-up drop threshold). addFor(peer, n,
#   reason) = add(n, reason, peer). refund(n, reason='refund') (points back, spent -= n, no multiplier, not earned),
#   refundTo(peer, n, reason) (host). awards (host: routed award count, for "points unchanged" checks).
#   Every peer broadcasts its own {points, kills, earned, spent} (economy.net_points, coalesced <= 10 Hz, flushed at game
#   over); pointsOf(id) / statsOf(id) -> {points, kills, earned, spent} read them (kills = awards with reason 'kill').
#   DOORS (shared): the buyer pays first, then economy.net_buyDoor(doorId, cost, fromPos) (client -> host); the host
#   validates (closed, not busy, cost) and opens it (level.openDoor(id, {from}): replicated by level.gd) ->
#   economy.net_doorFx(doorId, by) (host -> all: stars + confetti; the buyer's shake + economy:buy {.., by}) and
#   economy.net_buyResult(kind, id, ok, cost) (host -> buyer; false = refunded: a second buyer of the same door). The
#   door's prompt is hidden while the request is in flight (5 s without an answer: refunded).
#   WALL-BUYS / TUBE-O-MATIC (inventory only): bought locally, then economy.net_wallbuyFx(anchorId, kind, need) (owner ->
#   others): the same pop / hop / tubes aimed at the buyer's avatar hand (nothing given there; the wink stays "you own
#   it"). A remote animation keeps the stand busy (no prompt) like a local one.
#   BOARDS (shared): a completed repair hold sends economy.net_repairWindow(windowId) (client -> host); the host repairs
#   (replicated by windows.gd), pays T.points.board to the repairer up to T.points.boardCap per player per round and
#   sends economy.net_boardFx(windowId, at, by) (host -> all: sawdust + sparks, the repairer's shake).
extends RefCounted

const WIN_BOARDS := 6
const REPAIR_HOLD := 0.6       # s per board (GDD §5.4 task spec)
const FLIGHT := 0.3            # wall-buy pop-off arc (GDD §9.1)
const RESTOCK := 1.4           # s after a buy until the poster gun / case tubes come back
const GLINT_EVERY := 6.0       # GDD §6.7: the Pump poster's chrome glints every 6 s
const DOOR_R := 2.3
const WB_R := 1.9
const WIN_R := 2.1
const TAU := PI * 2.0
const ASSET_DIR := "res://assets/runtime/economy/"

var game
var points: int = 0
var _mult: float = 1.0
var earned: int = 0
var spent: int = 0
var doors := {}        # doorId -> { door, cost, items: [interactId] }
var wallbuys := {}     # anchorId -> wall-buy state (poster or case)
var windows := {}      # windowId -> { win, itemId, max }
var _items := {}       # interactId -> { kind, id }
var _boardPts: int = 0
var _fx: Array = []    # live cosmetic tweens { t, dur, fn(k, dt) }
var _rattles: Array = []
var _built := false
var _frameSeen := -1
var _time := 0.0
var _starTex = null
var _unsub = null
var _driver: Node = null

# MP (RECONCILE R1 / R2 / R15): each peer owns its local player's points; the host routes every award it decides.
const ALL := -1                       # add(n, reason, ALL) on the host: every player of the session gets +n
# Awards only the host decides (kills, boards, team bonuses, Telly refunds): a client ignores them in add() and gets
# them through net_award, so nothing is ever awarded twice.
const HOST_REASONS := ["hit", "kill", "kill_bonus", "board", "cancelled", "gaffer", "egg", "morning", "telly_refund"]
const TEAM_REASONS := ["cancelled", "gaffer", "egg", "morning"]    # +n to EVERY player
const PTS_EVERY := 0.1                # s (real) between two broadcasts of our points (coalesced)
const PENDING_MAX := 5.0              # s: a door request the host never answered is refunded
var kills: int = 0                    # MP: zombies killed by the local player (awards with reason 'kill')
var awards: int = 0                   # host: awards routed so far, to any player (for "points unchanged" checks)
var _credit: Array = []               # host: credit(peer) scopes (default recipient)
var _peerStats := {}                  # other peers' {points, kills, earned, spent} (net_points)
var _ptsDirty := false
var _ptsSentAt := -INF
var _pending := {}                    # client: doorId -> {cost, t} (a buy request in flight; its prompt is hidden)
var _boardPtsBy := {}                 # host: peer -> board points awarded this round (cap per player)
var _start: int = 0                   # start points of this run (statsOf before a peer's first broadcast)

func _init(g) -> void:
	game = g

func _net():
	return game.get("net") if game != null else null

# An MP game is running (net.inGame is already true while the MP newGame's resets run).
func _mp() -> bool:
	var n = _net()
	return n != null and bool(n.inGame)

# ================================================================================================ points
var multiplier: float:
	get:
		var pu = game.powerups if game != null else null
		var active = X.g(pu, "active")
		var sw = X.g(active, "sweeps_week", 0)
		var sweeps := 2.0 if (sw is int or sw is float) and float(sw) > 0.0 else 1.0
		return maxf(_mult, sweeps)
	set(v):
		_mult = v if is_finite(v) and v > 0.0 else 1.0

func add(n, reason: String = "misc", to = null) -> int:
	if _mp():
		return _addMP(n, reason, to)
	if not (n is int or n is float) or not is_finite(float(n)) or float(n) <= 0.0:
		return 0
	var delta: int = maxi(0, int(floorf(float(n) * multiplier + 0.5)))
	if delta == 0:
		return 0
	points += delta
	earned += delta
	_changed(delta, reason)
	return delta

func canAfford(n) -> bool:
	return points >= float(n)

func spend(n, reason: String = "buy") -> bool:
	if not (n is int or n is float) or not is_finite(float(n)) or float(n) <= 0.0:
		return true
	var c: int = int(floorf(float(n) + 0.5))
	if points < c:
		game.events.emit("points:denied", {"cost": c})
		return false
	points = maxi(0, points - c)
	spent += c
	_changed(-c, reason)
	return true

func _changed(delta: int, reason: String) -> void:
	var g = game
	g.events.emit("points:change", {"points": points, "delta": delta, "reason": reason})
	if g.hud != null and g.hud.has_method("pointsPopup"):
		g.hud.pointsPopup(delta)
	if _mp():
		_ptsDirty = true

# ---------------------------------------------------------------------------------------- MP points routing
# Host: the recipient is `to` (the attacker's peer id) > a team reason (every player) > a credit(peer) scope >
# net.sender (the client whose request is being handled) > the host. The delta is final (host multiplier applied).
func _addMP(n, reason: String, to) -> int:
	if not (n is int or n is float) or not is_finite(float(n)) or float(n) <= 0.0:
		return 0
	var net = _net()
	if net.isClient:
		if HOST_REASONS.has(reason):
			return 0                     # the host routes it to us (net_award): never twice
		return _grant(_mulRound(n), reason)
	var d := _mulRound(n)
	if d <= 0:
		return 0
	var who := 0
	if (to is int or to is float) and (int(to) > 0 or int(to) == ALL):
		who = int(to)
	elif TEAM_REASONS.has(reason):
		who = ALL
	elif not _credit.is_empty():
		who = int(_credit.back())
	else:
		who = int(net.sender)
	awards += 1
	game.events.emit("points:award", {"by": who, "delta": d, "reason": reason})
	if who == ALL:
		for id in net.peers.keys():
			_awardTo(int(id), d, reason)
	else:
		_awardTo(who, d, reason)
	return d

func _mulRound(n) -> int:
	return maxi(0, int(floorf(float(n) * multiplier + 0.5)))

func _awardTo(id: int, d: int, reason: String) -> void:
	var net = _net()
	if id == int(net.localId):
		_grant(d, reason)
	elif net.peers.has(id):
		net.toPeer(id, "economy", "award", [d, reason])

# Raw local award (no multiplier: the host already applied it).
func _grant(d: int, reason: String) -> int:
	if d <= 0:
		return 0
	points += d
	earned += d
	if reason == "kill":
		kills += 1
	_changed(d, reason)
	return d

# host -> peer: an award decided on the host (kill, hit, board, team bonus...).
func net_award(d = 0, reason = "misc") -> void:
	var net = _net()
	if net == null or not net.inGame or net.sender != 1:
		return
	if not (d is int or d is float) or not is_finite(float(d)):
		return
	_grant(int(d), str(reason))

# Alias of add(n, reason, peer) (the R15 name is add(n, reason, to)).
func addFor(peer, n, reason: String = "misc") -> int:
	return add(n, reason, peer)

# Host: the default recipient of add() calls without `to` until uncredit() (for code acting for a peer).
func credit(peer) -> void:
	_credit.append(int(peer))

func uncredit() -> void:
	if not _credit.is_empty():
		_credit.pop_back()

# Points back (a denied request): no multiplier, not "earned"; the spend is undone. Emits points:change.
func refund(n, reason: String = "refund") -> int:
	if not (n is int or n is float) or not is_finite(float(n)) or float(n) <= 0.0:
		return 0
	var c: int = int(floorf(float(n) + 0.5))
	points += c
	spent = maxi(0, spent - c)
	_changed(c, reason)
	return c

# Host: refund another peer (local refund for our own id / solo).
func refundTo(peer, n, reason: String = "refund") -> int:
	var net = _net()
	if net == null or not net.inGame or int(peer) == int(net.localId):
		return refund(n, reason)
	if net.isHost and net.peers.has(int(peer)) and (n is int or n is float) and is_finite(float(n)) and float(n) > 0.0:
		net.toPeer(int(peer), "economy", "refund", [int(floorf(float(n) + 0.5)), reason])
	return 0

func net_refund(n = 0, reason = "refund") -> void:
	var net = _net()
	if net == null or not net.inGame or net.sender != 1:
		return
	refund(n, str(reason))

# Points of any player (our own, or the last value its peer broadcast).
func pointsOf(id) -> int:
	return int(statsOf(id).points)

func statsOf(id) -> Dictionary:
	var net = _net()
	if net == null or not net.active or int(id) == int(net.localId):
		return {"points": points, "kills": kills, "earned": earned, "spent": spent}
	var st = _peerStats.get(int(id))
	if st is Dictionary:
		return st.duplicate()
	return {"points": _start, "kills": 0, "earned": 0, "spent": 0}

# owner -> others (coalesced, PTS_EVERY): our points for the teammates list and the results card.
func net_points(p = 0, k = 0, e = 0, s = 0) -> void:
	var net = _net()
	if net == null or not net.active:
		return
	var id: int = int(net.sender)
	if id == int(net.localId):
		return
	_peerStats[id] = {"points": _int(p), "kills": _int(k), "earned": _int(e), "spent": _int(s)}

static func _int(v) -> int:
	return int(v) if (v is int or v is float) and is_finite(float(v)) else 0

func _flushPoints(force: bool) -> void:
	var net = _net()
	if net == null or not net.inGame:
		_ptsDirty = false
		return
	var now: float = float(game.time.realNow)
	if not force and now - _ptsSentAt < PTS_EVERY:
		return
	_ptsSentAt = now
	_ptsDirty = false
	net.toOthers("economy", "points", [points, kills, earned, spent])

# ============================================================================================= lifecycle
func init() -> void:
	var g = game
	g.events.on("round:start", func(_p = null):
		_boardPts = 0
		_boardPtsBy.clear())
	# MP: our final points reach the others before the results card (the pre-pass flush is rate-limited)
	g.events.on("state", func(e = null):
		if _ptsDirty and e is Dictionary and (e.get("to") == "gameover" or e.get("to") == "victory"):
			_flushPoints(true))
	if g.level == null or not X.g(g.level, "built", false):
		return
	_setupDoors()
	_setupWallbuys()
	_setupWindows()
	_built = true
	if g.render != null and g.render.has_method("addPrePass"):
		_unsub = g.render.addPrePass(func(_r = null): _drive())
	elif g is Node:
		# no render pre-pass hook: a tiny process node (child of Game, so it runs after Game's own frame) drives it
		_driver = _Driver.new()
		_driver.eco = self
		_driver.name = "economy_driver"
		g.add_child(_driver)

func reset() -> void:
	var p = game.params.get("points")
	points = maxi(0, int(floorf(float(p)))) if (p is int or p is float) and is_finite(float(p)) else int(Config.T.player.startPoints)
	_mult = 1.0
	earned = 0
	spent = 0
	_boardPts = 0
	_fx.clear()
	for r in _rattles:
		r.restore.call()
	_rattles.clear()
	for w in wallbuys.values():
		w.reset()
	game.events.emit("points:change", {"points": points, "delta": 0, "reason": "start"})
	# MP bookkeeping (a new run: in MP the start points come from the host's start message)
	_start = points
	kills = 0
	awards = 0
	_credit.clear()
	_pending.clear()
	_boardPtsBy.clear()
	if _mp():
		_peerStats.clear()
		_ptsDirty = true
		_ptsSentAt = -INF

func update(dt: float) -> void:
	_frameSeen = game.time.frame
	_tick(dt)

func _drive() -> void:
	var g = game
	if _ptsDirty:
		_flushPoints(false)
	if _frameSeen == g.time.frame:
		return
	if g.state != "playing" and g.state != "down":
		return
	_frameSeen = g.time.frame
	_tick(g.time.dt)

func _tick(dt: float) -> void:
	if not _built:
		return
	_step(dt)

func _step(dt: float) -> void:
	_time += dt
	if not _pending.is_empty():
		_expirePending()
	_keepRepairing()
	for w in wallbuys.values():
		w.update(dt, _time)
	for i in range(_rattles.size() - 1, -1, -1):
		if not _rattles[i].step.call(dt):
			_rattles.remove_at(i)
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f.t += dt
		var k := minf(1.0, f.t / f.dur)
		f.fn.call(k, dt)
		if k >= 1.0:
			_fx.remove_at(i)

func _tween(dur: float, fn: Callable) -> void:
	_fx.append({"t": 0.0, "dur": dur, "fn": fn})

# ================================================================================================= doors
func _setupDoors() -> void:
	var g = game
	var L = g.level
	for d in L.doors.values():
		if X.g(d, "requiresPower", false):
			continue
		var did: String = str(X.g(d, "id"))
		var cost = Config.T.doors.get(did, X.g(d, "cost"))
		if not (cost is int or cost is float) or not (float(cost) > 0.0):
			continue
		var entry := {"door": d, "cost": cost, "items": []}
		var center = X.g(d, "center")
		var cx: float = float(center[0])
		var cz: float = float(center[1])
		var n: Vector3 = DAU.v3(X.g(d, "normal"))
		var areas: Array = X.g(d, "areas", [])
		for areaId in areas:
			var sgn := 1.0 if areaId == areas[1] else -1.0
			var area = L.areas.get(areaId)
			var floorY: float = float(X.g(area, "floorY", 0.0)) if area != null else 0.0
			var id := "econ:door:%s:%s" % [did, areaId]
			var pos := Vector3(cx + n.x * sgn * 0.35, floorY + 1.1, cz + n.z * sgn * 0.35)
			# one item per face (usable from both sides); normal = that face, so interact's front-side + line-of-sight
			# tests keep it from being bought through any other wall (the item sits 0.15 m clear of the door blocker)
			if g.interact != null:
				g.interact.register({
					"id": id, "pos": pos, "radius": DOOR_R, "normal": [n.x * sgn, 0.0, n.z * sgn], "facingSlack": 0.4,
					"enabled": func(): return not X.g(d, "open", false) and not X.g(d, "busy", false) and not _pending.has(did) and _onSide(d, sgn),
					"prompt": func(): return {"cost": cost},
					"use": func(): buyDoor(did),
				})
			_items[id] = {"kind": "door", "id": did}
			entry.items.append(id)
		doors[did] = entry

func _onSide(d, sgn: float) -> bool:
	var p = game.player
	if p == null or X.g(p, "pos") == null:
		return false
	var center = X.g(d, "center")
	var n: Vector3 = DAU.v3(X.g(d, "normal"))
	var s: float = (p.pos.x - float(center[0])) * n.x + (p.pos.z - float(center[1])) * n.z
	return s * sgn > -0.05

func buyDoor(doorId) -> bool:
	if _mp():
		return _buyDoorMP(doorId)
	var g = game
	var e = doors.get(doorId)
	if e == null or X.g(e.door, "open", false) or X.g(e.door, "busy", false):
		return false
	if not spend(e.cost, "door"):
		_rattleDoor(e.door)
		return false
	g.level.openDoor(doorId)
	g.events.emit("economy:buy", {"kind": "door", "id": doorId, "cost": e.cost})
	if g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.12, 0.3)
	_doorStars(e)
	return true

func _doorStars(e) -> void:
	var g = game
	if g.fx != null:
		var dpos: Vector3 = DAU.v3(X.g(e.door, "pos"))
		g.fx.burst(dpos, {"count": 10, "shape": "star", "colors": [Config.PAL.marqueeGold, "#FFF3B0"], "speed": 3.4, "size": 0.12, "life": 0.9, "gravity": 5})
		g.fx.burst(dpos, {"count": 14, "shape": "confetti", "speed": 4, "life": 1.2})

# MP: the buyer pays first (reservation), the host opens the shared door (first request wins: a second buyer is
# refunded), then every peer plays the buy beat (economy.doorFx). The prompt hides while the request is in flight.
func _buyDoorMP(doorId) -> bool:
	var net = _net()
	var e = doors.get(doorId)
	if e == null or X.g(e.door, "open", false) or X.g(e.door, "busy", false) or _pending.has(doorId):
		return false
	if not spend(e.cost, "door"):
		_rattleDoor(e.door)
		return false
	var cost: int = int(floorf(float(e.cost) + 0.5))
	var p = game.player
	var from = p.pos if p != null and X.g(p, "pos") is Vector3 else null
	if net.isClient:
		_pending[doorId] = {"cost": cost, "t": float(game.time.realNow)}
		net.toHost("economy", "buyDoor", [str(doorId), cost, from])
		return true
	_openDoorFor(str(doorId), int(net.localId), from)
	return true

func _openDoorFor(doorId: String, by: int, from) -> void:
	var opts := {}
	if from is Vector3:
		opts["from"] = from          # doors.away(): the debris flies away from the buyer (mp-zombies)
	game.level.openDoor(doorId, opts)   # replicated to every client by level.gd
	_net().everyone("economy", "doorFx", [doorId, by])

# client -> host: buy request (the client already paid `cost`).
func net_buyDoor(doorId = "", cost = 0, from = null) -> void:
	var net = _net()
	if net == null or not net.isHost or not net.inGame:
		return
	var id := str(doorId)
	var by: int = int(net.sender)
	var e = doors.get(id)
	var paid: int = int(cost) if (cost is int or cost is float) else 0
	var ok: bool = e != null and not X.g(e.door, "open", false) and not X.g(e.door, "busy", false) \
		and paid == int(floorf(float(e.cost) + 0.5)) and game.state == "playing"
	if ok:
		_openDoorFor(id, by, from if from is Vector3 else null)
	net.toPeer(by, "economy", "buyResult", ["door", id, ok, paid])

# host -> buyer: the request's outcome (false: refunded — somebody else opened it first).
func net_buyResult(kind = "", id = "", ok = false, _cost = 0) -> void:
	var net = _net()
	if net == null or net.sender != 1:
		return
	if str(kind) == "door":
		var pd = _pending.get(str(id))
		if pd == null:
			return
		_pending.erase(str(id))
		if not bool(ok):
			refund(int(pd.cost), "refund")

# host -> all: a door was bought (stars + confetti everywhere; the buyer's camera shake + economy:buy).
func net_doorFx(doorId = "", by = 0) -> void:
	var net = _net()
	if net == null or not net.inGame or net.sender != 1:
		return
	var e = doors.get(str(doorId))
	if e == null:
		return
	var g = game
	if int(by) == int(net.localId):
		g.events.emit("economy:buy", {"kind": "door", "id": str(doorId), "cost": e.cost, "by": int(by)})
		if g.cam != null and g.cam.has_method("shake"):
			g.cam.shake(0.12, 0.3)
	_doorStars(e)

func _expirePending() -> void:
	var now: float = float(game.time.realNow)
	for id in _pending.keys():
		if now - float(_pending[id].t) > PENDING_MAX:
			var c: int = int(_pending[id].cost)
			_pending.erase(id)
			push_warning("[economy] door %s: no answer from the host, refunded" % str(id))
			refund(c, "refund")

# Denied: the blocker gives a short "nuh-uh" shake (chain rattle). Restores its exact rest transform.
func _rattleDoor(d) -> void:
	var o = X.g(d, "blocker")
	if o == null or not (o is Node3D) or X.g(d, "open", false) or X.g(d, "busy", false):
		return
	for r in _rattles:
		if is_same(r.key, d):
			return
	var px: float = o.position.x
	var rz: float = o.rotation.z
	var st := {"t": 0.0}
	_rattles.append({
		"key": d,
		"step": func(dt: float) -> bool:
			st.t += dt
			var k := minf(1.0, st.t / 0.32)
			if X.g(d, "open", false) or k >= 1.0:
				o.position.x = px
				o.rotation.z = rz
				return false
			var a := sin(st.t * 70.0) * (1.0 - k)
			o.position.x = px + a * 0.018
			o.rotation.z = rz + a * 0.006
			return true,
		"restore": func() -> void:
			o.position.x = px
			o.rotation.z = rz,
	})

# ============================================================================================= wall-buys
func _setupWallbuys() -> void:
	var g = game
	var L = g.level
	for a in L.anchors.values():
		var aid = X.g(a, "id")
		var gives = X.g(a, "gives")
		if not (aid is String) or not aid.begins_with("wb_") or not gives:
			continue
		var w = GrenadeCase.new(self, a) if gives == "tube_grenade" else WallBuy.new(self, a)
		if w == null or not w.ok:
			push_error("[economy:build:%s] wall-buy build failed" % aid)
			continue
		wallbuys[aid] = w
		var id := "econ:wb:%s" % aid
		# facing = the anchor's rotY: only usable from the poster's side of the wall (never through it)
		var prompt_fn := func():
			var c = w.price()
			return null if c == null else {"cost": c}
		if g.interact != null:
			g.interact.register({
				"id": id, "pos": w.interactPos, "radius": WB_R, "height": 1.8, "facing": float(X.g(a, "rotY", 0.0)),
				"enabled": func(): return not w.busy,
				"prompt": prompt_fn,
				"use": func(): buyWallbuy(aid),
			})
		_items[id] = {"kind": "wallbuy", "id": aid}
		w.itemId = id

func buyWallbuy(anchorId) -> bool:
	var w = wallbuys.get(anchorId)
	if w == null or w.busy:
		return false
	var cost = w.price()
	if cost == null:
		return false
	if not spend(cost, w.kindOf()):
		w.denied()
		return false
	var kind: String = w.kindOf()
	w.buy()
	if _mp():
		# inventory-only purchase (RECONCILE R2): no round trip; the others replay the pop toward our avatar
		var net = _net()
		game.events.emit("economy:buy", {"kind": kind, "id": anchorId, "cost": cost, "by": int(net.localId)})
		net.toOthers("economy", "wallbuyFx", [str(anchorId), kind, int(w.get("lastNeed")) if w.get("lastNeed") != null else 0])
		return true
	game.events.emit("economy:buy", {"kind": kind, "id": anchorId, "cost": cost})
	return true

# owner -> others: a teammate bought at a wall-buy / the Tube-O-Matic (kind 'wallbuy' | 'ammo' | 'grenades', need =
# tubes): the same animation aimed at its avatar's hand; its own peer gave the weapon / ammo / grenades.
func net_wallbuyFx(anchorId = "", kind = "", need = 0) -> void:
	var net = _net()
	if net == null or not net.inGame:
		return
	var by: int = int(net.sender)
	if by == int(net.localId) or net.playerById(by) == null:
		return
	var w = wallbuys.get(str(anchorId))
	if w == null or w.busy:
		return                          # our own buy is playing there: one flight is enough
	w.remoteBuy(by, str(kind), int(need) if (need is int or need is float) else 0)

# The player a wall-buy animation flies to: the local player (by 0) or a teammate's avatar (null once it left).
func _playerOf(by: int):
	if by == 0:
		return game.player
	var net = _net()
	return net.playerById(by) if net != null else null

# Finds the wall surface in front of an anchor (anchors sit 0.1 m off the wall centre line, i.e. inside it).
func _wallFace(anchor) -> Vector3:
	var col = game.level.col
	var rotY: float = float(X.g(anchor, "rotY", 0.0))
	var apos: Vector3 = DAU.v3(X.g(anchor, "pos"))
	var fwd := Vector3(-sin(rotY), 0.0, -cos(rotY))
	var o := apos + fwd * 1.2
	var d := -fwd
	var hit = col.raycast(o, d, 2.0) if col != null else null
	var out := apos
	if hit != null and float(X.g(hit, "dist", INF)) < 1.6:
		out = o + d * float(X.g(hit, "dist"))
	else:
		out += fwd * 0.06
	return out

# Hand position of the hero (target of the pop-off arcs).
func _handPos(who = null) -> Vector3:
	var p = who if who != null else game.player
	var slot = X.g(X.g(X.g(p, "hero"), "slots"), "handR")
	if slot is Node3D:
		return DAU.worldPos(slot)
	var pp: Vector3 = DAU.v3(X.g(p, "pos"))
	return Vector3(pp.x, pp.y + 1.2, pp.z)

func _handMatrix(who = null) -> Transform3D:
	var p = who if who != null else game.player
	var slot = X.g(X.g(X.g(p, "hero"), "slots"), "handR")
	if slot is Node3D:
		return X.worldXform(slot)
	var yaw: float = float(X.g(p, "yaw", 0.0)) if p != null else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), _handPos(who))

func _slot(id):
	var w = game.weapons
	if w != null and w.has_method("slotOf"):
		return w.slotOf(id)
	var slots = X.g(w, "slots")
	if slots is Array:
		for s in slots:
			if s != null and X.g(s, "id") == id:
				return s
	return null

func _def(id, upgraded):
	var w = game.weapons
	if w != null and w.has_method("defOf"):
		return w.defOf(id, upgraded)
	var defs = X.g(w, "defs")
	var d = defs.get(id) if defs is Dictionary else null
	if d == null:
		return null
	if upgraded and X.g(d, "upgraded"):
		var m: Dictionary = d.duplicate()
		m.merge(d.upgraded, true)
		return m
	return d

func _ammoFull(id) -> bool:
	var s = _slot(id)
	if s == null:
		return true
	var def = _def(id, X.g(s, "upgraded", false))
	if def == null:
		return true
	return float(s.mag) >= float(def.mag) and float(s.reserve) >= float(def.reserve)

func _refillAmmo(id) -> bool:
	var w = game.weapons
	if w == null:
		return false
	if w.has_method("refill"):
		return w.refill(id)
	if w.has_method("refillAmmo"):
		return w.refillAmmo(id)
	var s = _slot(id)
	if s == null:
		return false
	var def = _def(id, X.g(s, "upgraded", false))
	if def == null:
		return false
	s.mag = def.mag
	s.reserve = def.reserve
	return true

func _grenades() -> int:
	var w = game.weapons
	var n = X.g(w, "grenades")
	return int(n) if (n is int or n is float) else 0

# Silent top-up, one tube per catch (the case plays its own boing + glass tocks; weapons.give would emit
# weapon:acquire -> a second boing). Clamped to T.player.grenadesMax by weapons.addGrenades.
func _addGrenades(n: int) -> void:
	var w = game.weapons
	if w == null or not (n > 0):
		return
	if w.has_method("addGrenades"):
		w.addGrenades(n)
	elif X.g(w, "grenades") is int or X.g(w, "grenades") is float:
		w.grenades = mini(int(Config.T.player.grenadesMax), int(w.grenades) + n)
	elif w.has_method("give"):
		w.give("tube_grenade", {"source": "wallbuy_case"})

func _starTexture():
	if _starTex != null:
		return _starTex
	var cv = X.newCanvas(64, 64)
	if cv == null:
		return null
	var x = cv.getContext("2d")
	var gr = x.createRadialGradient(32, 32, 0, 32, 32, 30)
	gr.addColorStop(0, "rgba(255,255,255,1)")
	gr.addColorStop(0.2, "rgba(255,245,210,0.7)")
	gr.addColorStop(1, "rgba(255,230,160,0)")
	x.fillStyle = gr
	x.beginPath()
	for i in 8:
		var a := (float(i) / 8.0) * TAU
		var r := 6.0 if i % 2 else 31.0
		x.lineTo(32.0 + cos(a) * r, 32.0 + sin(a) * r)
	x.closePath()
	x.fill()
	_starTex = cv.texture
	return _starTex

func _glint() -> MeshInstance3D:
	var s := X.sprite(_starTexture(), Color(2.2, 2.0, 1.6), 1.0, 5)
	s.scale = Vector3.ONE * 1e-3
	return s

# ============================================================================================ barricades
func _setupWindows() -> void:
	var g = game
	var L = g.level
	for w in L.windows.values():
		if X.g(w, "type") != "boarded":
			continue
		var wid: String = str(X.g(w, "id"))
		var id := "econ:win:%s" % wid
		var bm = X.g(w, "boardMeshes")
		var mx: int = bm.size() if (bm is Array and bm.size() > 0) else WIN_BOARDS
		if g.interact != null:
			g.interact.register({
				"id": id, "pos": DAU.v3(X.g(w, "pos")), "radius": WIN_R, "hold": REPAIR_HOLD,
				"enabled": func(): return int(X.g(w, "boards", 0)) < mx,
				"prompt": func(): return {},
				"use": func(): repairWindow(wid),
			})
		_items[id] = {"kind": "window", "id": wid}
		windows[wid] = {"win": w, "itemId": id, "max": mx}

func repairWindow(windowId) -> bool:
	if _mp():
		return _repairMP(windowId)
	var g = game
	var e = windows.get(windowId)
	if e == null or int(X.g(e.win, "boards", 0)) >= e.max:
		return false
	if not e.win.repairBoard():
		return false
	var pts: int = Config.T.points.board
	if _boardPts + pts <= int(Config.T.points.boardCap):
		_boardPts += pts
		add(pts, "board")
	var at: Vector3 = _boardAt(e)
	_boardBurst(e, at)
	if g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.05, 0.12)
	return true

# Where the board just put back sits (its handle position, else the window).
func _boardAt(e) -> Vector3:
	var bm = X.g(e.win, "boardMeshes")
	var bi: int = int(X.g(e.win, "boards", 0)) - 1
	var b = bm[bi] if bm is Array and bi >= 0 and bi < bm.size() else null
	return DAU.v3(X.g(b, "position")) if b != null else DAU.v3(X.g(e.win, "pos"))

func _boardBurst(e, at: Vector3) -> void:
	var g = game
	if g.fx != null:
		# sawdust puffs blown into the room + hammer sparks
		var inward = null
		var outside = X.g(e.win, "outsidePos")
		if outside != null:
			var dv: Vector3 = DAU.v3(X.g(e.win, "pos")) - DAU.v3(outside)
			dv.y = 0.0
			inward = dv.normalized()
		g.fx.burst(at, {"count": 5, "shape": "puff", "colors": ["#EFE0C4", "#D8C29C"], "speed": 1.7, "size": 0.075, "life": 0.4, "gravity": -0.3, "dir": inward, "cone": 1.2})
		g.fx.burst(at, {"count": 6, "shape": "spark", "colors": ["#FFE8A0", "#FFFFFF"], "speed": 3.8, "size": 0.035, "life": 0.2, "dir": inward, "cone": 1.4})

# MP: the boards are shared (host). A client's completed hold is a request; the host repairs, pays the repairer
# (board cap per player per round) and every peer plays the sawdust beat (economy.boardFx).
func _repairMP(windowId) -> bool:
	var e = windows.get(windowId)
	if e == null or int(X.g(e.win, "boards", 0)) >= e.max:
		return false
	var net = _net()
	if net.isClient:
		net.toHost("economy", "repairWindow", [str(windowId)])
		return true
	return _repairFor(str(windowId), int(net.localId))

func net_repairWindow(windowId = "") -> void:
	var net = _net()
	if net == null or not net.isHost or not net.inGame:
		return
	_repairFor(str(windowId), int(net.sender))

func _repairFor(wid: String, by: int) -> bool:
	var e = windows.get(wid)
	if e == null or int(X.g(e.win, "boards", 0)) >= e.max or game.state != "playing":
		return false
	if not e.win.repairBoard():           # replicated to every client by windows.gd (level.net_boards)
		return false
	var pts: int = Config.T.points.board
	var have: int = int(_boardPtsBy.get(by, 0))
	if have + pts <= int(Config.T.points.boardCap):
		_boardPtsBy[by] = have + pts
		add(pts, "board", by)
	_net().everyone("economy", "boardFx", [wid, _boardAt(e), by])
	return true

# host -> all: a board went back up at `at` (the repairer's camera shakes).
func net_boardFx(windowId = "", at = null, by = 0) -> void:
	var net = _net()
	if net == null or not net.inGame or net.sender != 1 or not (at is Vector3):
		return
	var e = windows.get(str(windowId))
	if e == null:
		return
	_boardBurst(e, at)
	var g = game
	if int(by) == int(net.localId) and g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.05, 0.12)

# interact.gd completes a hold once per press; keep repairing one board per REPAIR_HOLD while E stays down.
func _keepRepairing() -> void:
	var it = game.interact
	var cur = X.g(it, "current")
	var cid = X.g(cur, "id")
	if not (cid is String) or not cid.begins_with("econ:win:"):
		return
	var e = windows.get(cid.substr(9))
	if e == null or int(X.g(e.win, "boards", 0)) >= e.max:
		return
	if game.input != null and game.input.down("interact") and X.g(it, "_holdDone") == true:
		it.set("_holdDone", false)

# ================================================================================================= misc
func priceOf(key):
	var hit = _items.get(key)
	var kind = null
	if hit != null:
		kind = hit.kind
	elif doors.has(key):
		kind = "door"
	elif wallbuys.has(key):
		kind = "wallbuy"
	var id = hit.id if hit != null else key
	if kind == "door":
		var e = doors.get(id)
		return e.cost if e != null and not X.g(e.door, "open", false) else null
	if kind == "wallbuy":
		return wallbuys[id].price() if wallbuys.has(id) else null
	return null

# Instantiates a runtime asset of this system (Blender: blender/runtime/economy.py) with the prop conventions:
# node extras "da" -> DAU.ud(node) (castShadow, visible:false …), material extras "da" -> game.mats.fromSpec.
func _asset(key: String) -> Node3D:
	var path := ASSET_DIR + key + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[economy] runtime asset missing: %s (run blender/build_all.py --only runtime)" % path)
		return null
	var props = game.props
	if props != null and props.has_method("loadRuntime"):
		return props.loadRuntime(path)
	var ps = load(path)
	if ps == null or not (ps is PackedScene):
		return null
	var inst: Node3D = ps.instantiate()
	X.prepare(game, inst)
	return inst


# ================================================================================================ driver
# Engine glue (only when render.gd offers no addPrePass): runs after Game's own frame, like the JS render pre-pass.
class _Driver extends Node:
	var eco = null
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _process(_delta: float) -> void:
		if eco != null:
			eco._drive()


# ================================================================================================ wall-buy
# A promo lightbox poster (cards poster_<gun>, Duke Dalton's show) with the real chunky prop gun clipped on it.
class WallBuy extends RefCounted:
	var eco
	var game
	var id: String
	var anchor
	var weaponId: String
	var busy := false
	var itemId = null
	var winked := false
	var ok := false
	var _state := "idle"     # idle | flying | away | restock
	var _by := 0             # MP: peer id of the teammate the playing flight belongs to (0 = the local player)
	var _t := 0.0
	var _wobble := 1.0
	var _glintPhase := 0.0
	var root: Node3D
	var board: Node3D
	var inner: Node3D
	var W := 1.0
	var H := 1.0
	var matNormal = null
	var matWinked = null
	var poster: MeshInstance3D = null
	var gun: Node3D
	var gunZ := -0.055
	var gunRest := {}
	var poseInv := Transform3D.IDENTITY
	var shadow: Node3D = null
	var clips: Array = []
	var normal := Vector3.ZERO
	var gunLen := 0.0
	var gunFront := 0.0
	var glint: MeshInstance3D
	var glintRange: Array = [0.0, 0.0]
	var glintY := 0.0
	var interactPos := Vector3.ZERO
	var _from := Vector3.ZERO
	var _fromQ := Quaternion.IDENTITY
	var _fromS := 1.0
	var _trail := 0.0

	func _init(e, a) -> void:
		eco = e
		game = e.game
		id = str(X.g(a, "id"))
		anchor = a
		weaponId = str(X.g(a, "gives"))
		_glintPhase = fmod(float(eco.wallbuys.size()) * 1.7, GLINT_EVERY)
		_build()          # sets ok = true as its last step (a runtime error aborts _build only)

	func kindOf() -> String:
		var w = game.weapons
		return "ammo" if w != null and w.has_method("has") and w.has(weaponId) else "wallbuy"

	func price():
		if busy:
			return null
		var costs = Config.T.wallbuys.get(weaponId)
		if costs == null:
			return null
		var w = game.weapons
		if w == null or not w.has_method("has") or not w.has(weaponId):
			return costs[0]
		if eco._ammoFull(weaponId):
			return null
		var s = eco._slot(weaponId)
		return Config.T.wallbuys.upgradedAmmo if s != null and X.g(s, "upgraded", false) else costs[1]

	func _build() -> void:
		var g = game
		var M = g.mats
		var a = anchor
		var face: Vector3 = eco._wallFace(a)
		var roots = X.g(g.level, "areaRoots", {})
		var parent: Node3D = roots.get(X.g(a, "area")) if roots is Dictionary and roots.get(X.g(a, "area")) != null else g.scene
		root = DAU.node3d("wallbuy_%s" % id)
		DAU.ud(root).noMerge = true
		parent.add_child(root)
		root.position = X.toLocal(parent, face)
		root.rotation.y = float(X.g(a, "rotY", 0.0))

		# Gun in 'wall' pose: side-on, back at z = 0, barrel toward -x. Measure it to size the poster.
		gun = g.props.build(weaponId, {"pose": "wall"})
		var box := X.aabbOf(gun, true)
		var ln: float = box.size.x
		var gh: float = box.size.y
		var gd: float = box.size.z
		var gcx: float = box.position.x + box.size.x / 2.0
		# Sheet width from the gun length; long rifles may overhang the walnut frame by a few cm, never the wall.
		W = clampf(ln / 0.8, 0.95, 1.3)
		if ln > W + 0.12:
			W = ln - 0.12
		H = W * 4.0 / 3.0
		# The poster's painted mount sits 73% down the sheet: put it at the anchor height (gun centre = anchor y).
		var top := 0.73 * H
		board = DAU.node3d("board")           # hangs from the top edge (wobble pivot)
		board.position = Vector3(0, top, 0)
		root.add_child(board)
		inner = DAU.node3d("inner")           # poster space: origin at the anchor, z = 0 on the wall
		inner.position = Vector3(0, -top, 0)
		board.add_child(inner)

		# Lightbox: walnut frame, chrome lip, backlit poster (unlit glow material so it reads in dark studios),
		# picture light, contact shadow and the two bulldog clips: the Blender asset (blender/runtime/economy.py).
		var cy := top - H / 2.0
		var asset: Node3D = eco._asset("wallbuy_%s" % weaponId)
		if asset != null:
			asset.name = "lightbox"
			inner.add_child(asset)
			var ad: Dictionary = X.rootUd(asset)
			if ad.has("W") and absf(float(ad.W) - W) > 0.01:
				push_warning("[economy] %s: lightbox asset W %.3f != measured %.3f (rebuild blender/runtime/economy.py)" % [id, float(ad.W), W])
			poster = DAU.byName(asset, "poster") as MeshInstance3D
			shadow = DAU.byName(asset, "shadow") as Node3D
		var card := "poster_%s" % weaponId
		if M != null and M.has_method("glow"):
			matNormal = M.glow("#ffffff", 0.92, {"map": X.card(g, card, {})})
			matWinked = M.glow("#ffffff", 0.92, {"map": X.card(g, card, {"winked": true})})
		if poster != null and matNormal != null:
			poster.material_override = matNormal
		if shadow != null:
			shadow.position = Vector3(ln * 0.03, -gh * 0.32, -0.043)
			X.setRenderPriority(shadow, 1)

		# The gun, clipped just in front of the poster, plus two chrome spring clips over it.
		gunZ = -0.055
		gun.position = Vector3(0, 0, gunZ)
		inner.add_child(gun)
		gunRest = {"pos": gun.position, "quat": gun.quaternion}
		# The prop's body is in wall-pose space; its 'wpn' group keeps the pose matrix (hand pose = identity).
		# Flight target = hand matrix x inverse(pose) so the gun lands exactly as it will be held.
		var wpn = DAU.byName(gun, "wpn")
		poseInv = (wpn as Node3D).transform.affine_inverse() if wpn is Node3D and wpn != gun else Transform3D.IDENTITY
		# Brass bulldog clips, each hinged just above the gun's real silhouette at its x (a rifle's barrel sits lower
		# than its carry handle).
		clips = []
		var si := 0
		for s in [-1.0, 1.0]:
			var cx: float = gcx + s * ln * 0.24
			var prof := X.sliceProfile(gun, cx - 0.03, cx + 0.03)
			var topY: float = prof.top if is_finite(prof.top) else gh / 2.0
			var frontZ: float = prof.front if is_finite(prof.front) else -gd
			var hinge: Node3D = DAU.byName(asset, "clip_%d" % si) as Node3D if asset != null else null
			if hinge == null:
				hinge = DAU.node3d("clip_%d" % si)
				inner.add_child(hinge)
			hinge.rotation_order = EULER_ORDER_XYZ
			hinge.position = Vector3(cx, topY + 0.03, gunZ + frontZ - 0.006)
			clips.append(hinge)
			si += 1
		normal = Vector3(-sin(root.rotation.y), 0, -cos(root.rotation.y))
		gunLen = ln
		gunFront = gunZ - gd

		# Chrome glint (GDD §6.7) sweeping along the barrel every GLINT_EVERY s.
		glint = eco._glint()
		inner.add_child(glint)
		glintRange = [ln * 0.3, -ln * 0.42]
		glintY = gh * 0.18

		interactPos = face
		interactPos.y = DAU.v3(X.g(a, "pos")).y
		if gun is Node3D:
			gun.rotation_order = EULER_ORDER_XYZ
		ok = true

	# Eye of the winking Duke on the poster (card space: head at 0.5/0.45, wink sparkle at +0.62·s / −0.18·s).
	func _eyeWorld() -> Vector3:
		var u := (192.0 + 56.0 * 0.62) / 384.0
		var v := (0.45 * 512.0 - 56.0 * 0.18) / 512.0
		var cy := 0.73 * H - H / 2.0
		return X.toGlobal(inner, Vector3((0.5 - u) * W, cy + (0.5 - v) * H, -0.06))

	func _setWink(on: bool, pop: bool) -> void:
		if on == winked:
			return
		winked = on
		if poster != null:
			poster.material_override = matWinked if on else matNormal
		if pop:
			_wobble = 0.0
			var fx = game.fx
			if on and fx != null:
				fx.burst(_eyeWorld(), {"count": 5, "shape": "star", "colors": ["#FFFFFF", Config.PAL.marqueeGold], "speed": 1.6, "size": 0.1, "life": 0.7, "gravity": 0.5})

	func denied() -> void:
		# Nope: the gun shivers on its clips.
		if _state != "idle":
			return
		var base: Vector3 = gunRest.pos
		eco._tween(0.3, func(k: float, _dt: float) -> void:
			if _state != "idle":
				return
			var a := sin(k * 30.0) * (1.0 - k)
			gun.position = Vector3(base.x + a * 0.012, base.y, base.z)
			gun.rotation.z = a * 0.03
			if k >= 1.0:
				gun.position = base
				gun.quaternion = gunRest.quat)

	func buy() -> void:
		if kindOf() == "ammo":
			_buyAmmo()
			return
		_by = 0
		_fly(true)

	# MP: a teammate (peer `by`) bought here: the same pop / hop, aimed at its avatar's hand. Its own peer gives the
	# weapon / ammo; Duke's wink keeps meaning "YOU own this gun".
	func remoteBuy(by: int, kind: String, _need: int = 0) -> void:
		if busy or _state != "idle":
			return
		if kind == "ammo":
			_buyAmmo(by)
			return
		_by = by
		_fly(false)

	func _fly(wink: bool) -> void:
		var g = game
		busy = true
		_state = "flying"
		_t = 0.0
		if wink:
			_setWink(true, true)
		_wobble = 0.0
		# Pop: the clips spring open, the gun is handed to the scene root keeping its world transform and arcs into
		# the hero's hands (ka-ching from the spend now, boing from weapon:acquire on the catch).
		_clipsOpen(FLIGHT + RESTOCK + 0.2)
		X.attach(g.scene, gun)
		_from = gun.position
		_fromQ = gun.quaternion
		_fromS = gun.scale.x
		_trail = 0.0
		if g.audio != null:
			g.audio.play("dry_fire", {"pos": _from, "vol": 0.45, "rate": 1.5})
		if g.fx != null:
			g.fx.burst(_from, {"count": 5, "shape": "puff", "colors": ["#FFF4DC", "#F6E7C8"], "speed": 1.9, "size": 0.065, "life": 0.32, "gravity": -0.4, "dir": normal, "cone": 0.9})
			g.fx.burst(_from, {"count": 7, "shape": "spark", "colors": ["#FFF3B0", "#FFFFFF"], "speed": 4.2, "size": 0.03, "life": 0.18, "dir": normal, "cone": 1.1})

	func _buyAmmo(by: int = 0) -> void:
		var g = game
		if by == 0:
			eco._refillAmmo(weaponId)
		var def = eco._def(weaponId, false)
		var a = g.audio
		if a != null and def != null and X.g(def, "shellReload"):
			# pump: two shells thumbed in, then the rack
			a.play("reload_shell", {"pos": interactPos})
			a.play("reload_shell", {"pos": interactPos, "delay": 0.13, "rate": 1.06})
			a.play("wpn_pump_rack", {"pos": interactPos, "delay": 0.32, "vol": 0.8})
		elif a != null:
			a.play("reload_mag", {"pos": interactPos})
			a.play("reload_mag", {"pos": interactPos, "delay": 0.25, "vol": 0.6, "rate": 1.1})
		# The gun hops off the clips and settles; brass spills toward the player.
		var base: Vector3 = gunRest.pos
		eco._tween(0.45, func(k: float, _dt: float) -> void:
			if _state != "idle":
				return
			var hop := sin(PI * k) * (1.0 - k * 0.3)
			gun.position = Vector3(base.x, base.y + hop * 0.06, base.z - hop * 0.05)
			gun.rotation.z = sin(k * TAU * 1.5) * 0.08 * (1.0 - k)
			if k >= 1.0:
				gun.position = base
				gun.quaternion = gunRest.quat)
		_clipsOpen(0.5)
		var who = eco._playerOf(by)
		if g.fx != null and who != null:
			var gp := DAU.worldPos(gun)
			var dir: Vector3 = (eco._handPos(who) - gp).normalized()
			g.fx.burst(gp, {"count": 12, "shape": "confetti", "colors": ["#E8B84A", "#C8963C", "#FFE09A"], "speed": 3.2, "size": 0.05, "life": 0.9, "gravity": 9, "dir": dir, "cone": 0.7})

	func _clipsOpen(hold: float) -> void:
		var cl := clips
		eco._tween(hold + 0.35, func(k: float, _dt: float) -> void:
			var t := k * (hold + 0.35)
			var a: float
			if t < 0.12:
				a = X.easeOutBack(t / 0.12, 3.0) * 1.25
			elif t < hold:
				a = 1.25
			else:
				a = 1.25 * (1.0 - X.easeOutBack(minf(1.0, (t - hold) / 0.35), 1.6))
			for c in cl:
				c.rotation.x = -a)

	func reset() -> void:
		busy = false
		_state = "idle"
		_by = 0
		_wobble = 1.0
		_setWink(false, false)
		_restoreGun()
		gun.scale = Vector3.ONE
		gun.visible = true
		for c in clips:
			c.rotation.x = 0.0
		board.rotation = Vector3.ZERO

	func _restoreGun() -> void:
		if gun.get_parent() != inner:
			DAU.detach(gun)
			inner.add_child(gun)
		gun.position = gunRest.pos
		gun.quaternion = gunRest.quat
		gun.scale = Vector3.ONE

	func update(dt: float, time: float) -> void:
		var g = game
		# Duke keeps winking while the player owns this gun.
		if _state == "idle" or _state == "restock":
			var w = g.weapons
			var owned: bool = w != null and w.has_method("has") and w.has(weaponId)
			_setWink(owned, true)
		# Poster wobble on its top edge (paper-on-spring), decaying.
		if _wobble < 1.0:
			_wobble = minf(1.0, _wobble + dt / 0.7)
			var k := _wobble
			board.rotation.z = sin(k * 22.0) * 0.035 * pow(1.0 - k, 2.0)
			board.rotation.x = sin(k * 17.0) * 0.02 * pow(1.0 - k, 2.0)
		_updateGlint(dt, time)

		if _state == "flying":
			_t += dt
			var who = eco._playerOf(_by)
			if _by != 0 and who == null:
				_t = FLIGHT                  # MP: the buyer left mid-flight: catch now (the gun just vanishes)
			var k := minf(1.0, _t / FLIGHT)
			# fast pop off the sheet, a hang at the apex, a snap into the hand
			var e := clampf(k + 0.12 * sin(TAU * k), 0.0, 1.0)
			# landing frame = hand x inverse(wall pose): the gun arrives exactly as it will be held
			var land: Transform3D = eco._handMatrix(who) * poseInv
			var to := land.origin
			var q2 := land.basis.get_rotation_quaternion()
			var sc3 := land.basis.get_scale()
			var from := _from
			var n := normal
			# cubic bezier: out of the poster along its normal and up, over the top, then down into the hand
			var up := 0.35 + 0.25 * clampf(from.distance_to(to) - 0.8, 0.0, 1.5)
			var p1 := from + n * 0.45
			p1.y = from.y + up
			var p2 := to
			p2.y = maxf(to.y, from.y) + up * 1.3
			var u := 1.0 - e
			gun.position = from * (u * u * u) + p1 * (3.0 * u * u * e) + p2 * (3.0 * u * e * e) + to * (e * e * e)
			# wall pose -> hand pose, with one barrel roll (local x) on the way
			var ei := X.easeInOut(k)
			gun.quaternion = _fromQ.slerp(q2, ei) * Quaternion(Vector3(1, 0, 0), TAU * ei)
			# stretch along the barrel in flight, squash on the catch frames
			var s := 1.0 + sin(PI * minf(1.0, k * 1.15)) * 0.2
			var sc := lerpf(_fromS, sc3.x, e)
			gun.scale = Vector3(sc * s, sc * (2.0 - s), sc * (2.0 - s) * 0.5 + sc * 0.5)
			# sparkle trail
			_trail += dt
			if g.fx != null and _trail > 0.04 and k < 0.92:
				_trail = 0.0
				g.fx.burst(gun.position, {"count": 1, "shape": "star", "colors": ["#FFF3B0", "#FFFFFF"], "speed": 0.3, "size": 0.055, "life": 0.3, "gravity": 0})
			if k >= 1.0:
				_catch()
		elif _state == "away":
			_t += dt
			if _t >= RESTOCK:
				_state = "restock"
				_t = 0.0
				_restoreGun()
				gun.visible = true
				gun.scale = Vector3.ONE * 1e-3
				var gp := DAU.worldPos(gun)
				if g.fx != null:
					g.fx.burst(gp, {"count": 5, "shape": "puff", "colors": ["#FFF4DC"], "speed": 1.2, "size": 0.06, "life": 0.35, "gravity": -0.3, "dir": normal, "cone": 1})
				if g.audio != null:
					g.audio.play("dry_fire", {"pos": gp, "vol": 0.3, "rate": 1.25, "delay": 0.2})
		elif _state == "restock":
			_t += dt
			var k := minf(1.0, _t / 0.38)
			gun.scale = Vector3.ONE * maxf(1e-3, X.easeOutBack(k, 2.6))
			if k >= 1.0:
				gun.scale = Vector3.ONE
				_state = "idle"
				busy = false

	func _catch() -> void:
		var g = game
		gun.visible = false
		gun.scale = Vector3.ONE
		_restoreGun()
		_state = "away"
		_t = 0.0
		if _by != 0:
			# MP: a teammate's catch: its own peer gives the weapon (wink unchanged: it means "YOU own it")
			var who = eco._playerOf(_by)
			_by = 0
			if g.fx != null and who != null:
				g.fx.burst(eco._handPos(who), {"count": 6, "shape": "star", "colors": ["#FFFFFF", Config.PAL.marqueeGold], "speed": 2.2, "size": 0.07, "life": 0.45, "gravity": 2})
			return
		var w = g.weapons
		if w != null and w.has_method("give"):
			w.give(weaponId, {"source": "wallbuy"})
		_setWink(true, false)
		if g.fx != null:
			g.fx.burst(eco._handPos(), {"count": 6, "shape": "star", "colors": ["#FFFFFF", Config.PAL.marqueeGold], "speed": 2.2, "size": 0.07, "life": 0.45, "gravity": 2})
		if g.cam != null and g.cam.has_method("kick"):
			g.cam.kick(0.01, 0.0)

	func _updateGlint(_dt: float, time: float) -> void:
		var s := glint
		var period := fmod(time + _glintPhase, GLINT_EVERY)
		var dur := 0.5
		if _state != "idle" or period > dur:
			s.visible = false
			return
		s.visible = true
		var k := period / dur
		var x0: float = glintRange[0]
		var x1: float = glintRange[1]
		s.position = Vector3(lerpf(x0, x1, X.easeInOut(k)), glintY, gunFront - 0.02)
		var sz := pow(sin(PI * k), 1.5) * 0.26
		s.scale = Vector3.ONE * maxf(1e-3, sz)
		X.spriteSet(s, "rotation", k * 2.4)


# ============================================================================================ grenade case
# "Tube-O-Matic": a 70s drugstore tube-tester style wall cabinet. Four glowing Tube grenades stand behind the glass.
class GrenadeCase extends RefCounted:
	const W := 0.96
	const D := 0.5
	const winY0 := 1.06
	const winY1 := 1.74
	const Dw := 0.42
	const NB := 22
	var eco
	var game
	var id: String
	var anchor
	var weaponId := "tube_grenade"
	var busy := false
	var itemId = null
	var ok := false
	var lastNeed := 0        # tubes of the last local purchase (MP: sent to the others for their replay)
	var _by := 0             # MP: peer id of the teammate the flying tubes belong to (0 = the local player)
	var _restock := -1.0
	var _owed := 0
	var _time := 0.0
	var root: Node3D
	var sockets: Array = []
	var bulbPos: Array = []
	var bulbs: Node3D = null
	var _bulbLit := -1
	var glass: Node3D = null
	var normal := Vector3.ZERO
	var tubes: Array = []
	var rack: Node3D
	var rackGlow: Array = []     # the rack's filament meshes (a rare shared flicker, like a power dip)
	var interactPos := Vector3.ZERO

	func _init(e, a) -> void:
		eco = e
		game = e.game
		id = str(X.g(a, "id"))
		anchor = a
		_build()          # sets ok = true as its last step (a runtime error aborts _build only)

	func kindOf() -> String:
		return "grenades"

	func price():
		if busy:
			return null
		return Config.T.wallbuys.grenades if eco._grenades() < int(Config.T.player.grenadesMax) else null

	func _build() -> void:
		var g = game
		var a = anchor
		var face: Vector3 = eco._wallFace(a)
		var area = g.level.areas.get(X.g(a, "area"))
		var floorY: float = float(X.g(area, "floorY", 0.0)) if area != null else 0.0
		var roots = X.g(g.level, "areaRoots", {})
		var parent: Node3D = roots.get(X.g(a, "area")) if roots is Dictionary and roots.get(X.g(a, "area")) != null else g.scene
		root = DAU.node3d("wallbuy_%s" % id)
		DAU.ud(root).noMerge = true
		parent.add_child(root)
		root.position = X.toLocal(parent, Vector3(face.x, floorY, face.z))
		root.rotation.y = float(X.g(a, "rotY", 0.0))

		# Floor-standing cabinet against the wall. Local: floor y = 0, back on z = 0, front toward -z. The display
		# window is centred near the anchor height (1.4 m); the base holds the coin plate, the push button and a chute.
		# Cabinet, backlit sunburst panel, strip light, header sign, marquee bulbs and the glass flap: Blender asset.
		var dy := (winY0 + winY1) / 2.0
		var dh := winY1 - winY0 + 0.1
		var asset: Node3D = eco._asset("tube_o_matic")
		if asset != null:
			asset.name = "tube_o_matic"
			root.add_child(asset)
		sockets = []
		for i in 4:
			var x := -0.3 + i * 0.2
			sockets.append(Vector3(x, winY0 + 0.155, -Dw / 2.0 - 0.02))
		# Header sign with 22 chasing marquee bulbs (an unlit bulb is scaled to a dim pip, not hidden).
		var signY := winY1 + 0.25
		bulbPos = []
		var bw := W + 0.02
		var bh := 0.3
		var perim := 2.0 * (bw + bh)
		for i in NB:
			# walk the rectangle around the sign face
			var d := (float(i) / NB) * perim
			var x: float
			var y: float
			if d < bw:
				x = -bw / 2.0 + d
				y = bh / 2.0
			elif d < bw + bh:
				x = bw / 2.0
				y = bh / 2.0 - (d - bw)
			elif d < 2.0 * bw + bh:
				x = bw / 2.0 - (d - bw - bh)
				y = -bh / 2.0
			else:
				x = -bw / 2.0
				y = -bh / 2.0 + (d - 2.0 * bw - bh)
			bulbPos.append(Vector3(x, signY + y, -Dw / 2.0 - 0.165))
		bulbs = DAU.byName(asset, "marquee") as Node3D if asset != null else null
		_bulbLit = -1
		_setBulbs(0, false)

		# The glass is a flap hinged on its top edge: it swings up and out when the tubes pop (see buy()).
		glass = DAU.byName(asset, "glass") as Node3D if asset != null else null
		if glass == null:
			glass = DAU.node3d("glass")
			glass.position = Vector3(0, winY1 - 0.01, -Dw - 0.012)
			root.add_child(glass)
		glass.rotation_order = EULER_ORDER_XYZ
		normal = Vector3(-sin(root.rotation.y), 0, -cos(root.rotation.y))

		# The four tubes (display pose, floor at y = 0), each an animatable part.
		# At rest the four tubes show as one "rack"; the individual tubes only show while a purchase plays (they fly,
		# restock), then the rack takes over again.
		rack = DAU.node3d("rack")
		root.add_child(rack)
		tubes = []
		var i := 0
		for p in sockets:
			var ry := 0.35 if i % 2 else -0.35
			var t: Node3D = g.props.build("tube_grenade", {"pose": "display"})
			t.rotation_order = EULER_ORDER_XYZ
			t.position = p
			t.rotation.y = ry
			t.visible = false
			root.add_child(t)
			var r: Node3D = g.props.build("tube_grenade", {"pose": "display"})
			r.position = p
			r.rotation.y = ry
			rack.add_child(r)
			tubes.append({"obj": t, "rest": p, "restRot": ry, "state": "home", "t": 0.0})
			i += 1
		rackGlow = X.glowMeshes(rack)

		# collider so the player does not walk into the cabinet
		var xf := X.worldXform(root)
		var box := AABB()
		var first := true
		for q in [Vector3(-W / 2.0, 0, 0), Vector3(W / 2.0, 0, 0), Vector3(-W / 2.0, signY + 0.2, -D - 0.04), Vector3(W / 2.0, signY + 0.2, -D - 0.04)]:
			var wp: Vector3 = xf * q
			if first:
				box = AABB(wp, Vector3.ZERO)
				first = false
			else:
				box = box.expand(wp)
		var col = g.level.col
		if col != null:
			col.addBox(DAU.arr3(box.position), DAU.arr3(box.end), {"tag": "prop", "id": "econ_tube_o_matic"})

		interactPos = face
		interactPos.y = floorY + 1.2
		interactPos += Vector3(-sin(root.rotation.y), 0, -cos(root.rotation.y)) * D
		ok = true

	# true: the rack shows the tubes at rest; false: the individual (animatable) tubes do.
	func _rackOn(on: bool) -> void:
		rack.visible = on
		for tb in tubes:
			if tb.state == "home":
				tb.obj.visible = not on

	func denied() -> void:
		if rack.visible:
			# the whole rack rattles in its sockets
			var r := rack
			eco._tween(0.3, func(k: float, _dt: float) -> void:
				var a := sin(k * 34.0) * (1.0 - k)
				r.position = Vector3(a * 0.005, absf(a) * 0.008, 0)
				r.rotation.z = a * 0.015
				if k >= 1.0:
					r.position = Vector3.ZERO
					r.rotation.z = 0.0)
			return
		for tb in tubes:
			if tb.state != "home":
				continue
			var o: Node3D = tb.obj
			var rest: Vector3 = tb.rest
			eco._tween(0.3, func(k: float, _dt: float) -> void:
				if tb.state != "home":
					return
				var a := sin(k * 34.0 + rest.x * 9.0) * (1.0 - k)
				o.position = Vector3(rest.x + a * 0.006, rest.y + absf(a) * 0.01, rest.z)
				o.rotation.z = a * 0.12
				if k >= 1.0:
					o.position = rest
					o.rotation.z = 0.0)

	func buy() -> void:
		var need: int = maxi(1, mini(tubes.size(), int(Config.T.player.grenadesMax) - eco._grenades()))
		lastNeed = need
		_by = 0
		_launch(need, need)

	# MP: a teammate (peer `by`) bought `need` tubes: they fly to its avatar's hand (its own peer adds the grenades).
	func remoteBuy(by: int, _kind: String, need: int = 0) -> void:
		if busy:
			return
		_by = by
		_launch(clampi(need, 1, tubes.size()), 0)

	func _launch(need: int, owed: int) -> void:
		var g = game
		_owed = owed                        # granted one per tube caught (the HUD tubes light up in sync)
		busy = true
		_rackOn(false)
		_restock = RESTOCK + 0.25
		if g.audio != null:
			g.audio.play("wallbuy_boing", {"pos": interactPos})
			g.audio.play("dry_fire", {"pos": interactPos, "vol": 0.4, "rate": 0.85})
		# The glass flap swings up (overshoot), stays open while the tubes fly and restock, then drops shut.
		var open := RESTOCK + 0.25 + 0.3
		var flap := glass
		eco._tween(open + 0.4, func(k: float, _dt: float) -> void:
			var t := k * (open + 0.4)
			var a: float
			if t < 0.14:
				a = X.easeOutBack(t / 0.14, 2.4) * 1.05
			elif t < open:
				a = 1.05 + sin((t - 0.14) * 3.0) * 0.03
			else:
				a = 1.05 * (1.0 - X.easeOutBounce(minf(1.0, (t - open) / 0.4)))
			flap.rotation.x = a
			if k >= 1.0:
				flap.rotation.x = 0.0)
		var ip := interactPos
		eco._tween(open + 0.12, func(k: float, _dt: float) -> void:
			if k >= 1.0 and g.audio != null:
				g.audio.play("dry_fire", {"pos": ip, "vol": 0.35, "rate": 1.1}))
		# `need` tubes pop up out of their sockets, hop out through the open front and arc into the hero's hands.
		var n := 0
		for tb in tubes:
			if n >= need:
				break
			tb.state = "wait"
			tb.t = -0.06 - n * 0.08
			n += 1
		_setBulbs(0, true)

	# Marquee chase: every third bulb dark, stepping at 8 Hz; all lit (and a touch bigger) while a purchase plays.
	func _setBulbs(step: int, all: bool) -> void:
		var key := -2 if all else step % 3
		if key == _bulbLit:
			return
		_bulbLit = key
		if bulbs == null:
			return
		var n := bulbPos.size()
		for i in n:
			var on := all or (i + step) % 3 != 0
			var s := (1.25 if all else 1.0) if on else 0.45
			X.instSetXform(bulbs, i, Transform3D(Basis.from_scale(Vector3(s, s, s)), bulbPos[i]))

	func reset() -> void:
		busy = false
		_restock = -1.0
		_owed = 0
		_by = 0
		glass.rotation.x = 0.0
		_setBulbs(0, false)
		for tb in tubes:
			_home(tb)
		rack.position = Vector3.ZERO
		rack.rotation.z = 0.0
		_rackOn(true)

	func _home(tb: Dictionary) -> void:
		var o: Node3D = tb.obj
		if o.get_parent() != root:
			DAU.detach(o)
			root.add_child(o)
		o.position = tb.rest
		o.rotation = Vector3(0, tb.restRot, 0)
		o.scale = Vector3.ONE
		o.visible = not rack.visible
		tb.state = "home"

	func update(dt: float, _time_now: float) -> void:
		var g = game
		_time += dt
		# marquee chase + a rare filament flicker on the rack
		_setBulbs(int(floorf(_time * 8.0)), busy)
		if not rackGlow.is_empty():
			var vis := sin(_time * 37.0) > -0.985 or sin(_time * 1.3) < 0.9
			for m in rackGlow:
				m.visible = vis
		for tb in tubes:
			var o: Node3D = tb.obj
			if tb.state == "home":
				continue
			tb.t += dt
			if tb.state == "wait":
				if tb.t < 0.0:
					continue
				X.attach(g.scene, o)
				tb.from = o.position
				tb.state = "fly"
				tb.t = 0.0
			if tb.state == "fly":
				var who = eco._playerOf(_by)
				if _by != 0 and who == null:
					tb.t = FLIGHT                # MP: the buyer left: the tube is caught now (vanishes)
				var k := minf(1.0, tb.t / FLIGHT)
				var e := clampf(k + 0.1 * sin(TAU * k), 0.0, 1.0)
				var to: Vector3 = eco._handPos(who)
				var from: Vector3 = tb.from
				# cubic bezier: up out of the socket (staying under the display top), out through the open front, into the hand
				var p1 := from + normal * 0.3
				p1.y = from.y + 0.24
				var p2 := to
				p2.y = maxf(to.y, from.y) + 0.32
				var u := 1.0 - e
				o.position = from * (u * u * u) + p1 * (3.0 * u * u * e) + p2 * (3.0 * u * e * e) + to * (e * e * e)
				o.rotation.x += dt * 14.0
				var s := 1.0 + sin(PI * k) * 0.25
				o.scale = Vector3(s, 2.0 - s, s)
				if k >= 1.0:
					tb.state = "gone"
					o.visible = false
					if _owed > 0:
						_owed -= 1
						eco._addGrenades(1)
					if _by != 0:
						# a teammate's catch: positional, nothing granted here
						if who != null:
							if g.audio != null:
								g.audio.play("grenade_bounce", {"pos": to, "vol": 0.7, "rate": 1.1 + tubes.find(tb) * 0.08})
							if g.fx != null:
								g.fx.burst(to, {"count": 3, "shape": "spark", "colors": ["#FFB060", "#FFE8A0"], "speed": 2, "size": 0.03, "life": 0.2})
						continue
					if g.audio != null:
						g.audio.play("grenade_bounce", {"vol": 0.7, "rate": 1.1 + tubes.find(tb) * 0.08})
					if g.fx != null:
						g.fx.burst(to, {"count": 3, "shape": "spark", "colors": ["#FFB060", "#FFE8A0"], "speed": 2, "size": 0.03, "life": 0.2})
		if _restock > 0.0:
			_restock -= dt
			if _restock <= 0.0:
				if _owed > 0:
					eco._addGrenades(_owed)   # never short-change a buy
					_owed = 0
				# tubes rise back into the sockets with a pop
				for tb in tubes:
					if tb.state == "home":
						continue
					_home(tb)
					var o: Node3D = tb.obj
					o.scale = Vector3.ONE * 1e-3
					tb.state = "rise"
					eco._tween(0.35, func(k: float, _dt: float) -> void:
						o.scale = Vector3.ONE * maxf(1e-3, X.easeOutBack(k, 2.8))
						if k >= 1.0:
							o.scale = Vector3.ONE
							tb.state = "home")
				eco._tween(0.36, func(k: float, _dt: float) -> void:
					if k >= 1.0:
						busy = false
						_rackOn(true))


# ---------------------------------------------------------------------------------------------- helpers
# Static helpers shared by the economy and its inner classes (GDScript inner classes cannot call the outer
# script's static functions unqualified).
class X:
	const SPRITE_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
uniform sampler2D map : source_color, filter_linear_mipmap, repeat_disable, hint_default_white;
uniform vec4 color = vec4(1.0);
uniform float opacity = 1.0;
uniform float rotation = 0.0;
void vertex() {
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec2 aligned = VERTEX.xy * scale;
	vec2 rot = vec2(cos(rotation) * aligned.x - sin(rotation) * aligned.y, sin(rotation) * aligned.x + cos(rotation) * aligned.y);
	VERTEX = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + vec3(rot, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}
void fragment() {
	vec4 t = texture(map, UV);
	ALBEDO = color.rgb * t.rgb;
	ALPHA = clamp(color.a * t.a * opacity, 0.0, 1.0);
}
"""
	static var _spriteShader: Shader = null
	static var _quad: QuadMesh = null

	# obj.key for a Dictionary or an Object (null / missing -> def), like a JS property read.
	static func g(o, k: String, def = null):
		if o == null:
			return def
		if o is Dictionary:
			var v = o.get(k)
			return def if v == null else v
		if o is Object:
			var v = o.get(k)
			return def if v == null else v
		return def

	static func easeOutBack(t: float, s: float = 2.2) -> float:
		return 1.0 + (s + 1.0) * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)

	static func easeInOut(t: float) -> float:
		return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

	static func easeOutBounce(t: float) -> float:
		var n := 7.5625
		var d := 2.75
		if t < 1.0 / d:
			return n * t * t
		if t < 2.0 / d:
			t -= 1.5 / d
			return n * t * t + 0.75
		if t < 2.5 / d:
			t -= 2.25 / d
			return n * t * t + 0.9375
		t -= 2.625 / d
		return n * t * t + 0.984375

	# Global transform (also for nodes not inside the tree yet).
	static func worldXform(n: Node3D) -> Transform3D:
		if n.is_inside_tree():
			return n.global_transform
		var xf := n.transform
		var p := n.get_parent()
		while p != null:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		return xf

	static func toLocal(parent: Node3D, p: Vector3) -> Vector3:
		return worldXform(parent).affine_inverse() * p

	static func toGlobal(n: Node3D, p: Vector3) -> Vector3:
		return worldXform(n) * p

	# object.attach(child): reparent keeping the world transform.
	static func attach(parent: Node3D, n: Node3D) -> void:
		var xf := worldXform(n)
		DAU.detach(n)
		parent.add_child(n)
		n.transform = worldXform(parent).affine_inverse() * xf

	# Transform of `n` relative to `root` (root's own transform excluded).
	static func relXform(n: Node, root: Node) -> Transform3D:
		var xf := Transform3D.IDENTITY
		var c := n
		while c != null and c != root:
			if c is Node3D:
				xf = (c as Node3D).transform * xf
			c = c.get_parent()
		return xf

	# Box3.setFromObject(root) for a root without parent: every mesh AABB in root's parent space.
	static func aabbOf(root: Node3D, withRoot: bool) -> AABB:
		var out := AABB()
		var first := true
		var base := root.transform if withRoot else Transform3D.IDENTITY
		for mi in _meshes(root):
			var aabb: AABB = mi.get_aabb()
			var box: AABB = (base * relXform(mi, root)) * aabb
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
		return out

	static func _meshes(root: Node) -> Array:
		var out: Array = []
		DAU.traverse(root, func(o):
			if o is MeshInstance3D and (o as MeshInstance3D).mesh != null:
				out.append(o))
		return out

	# Highest y and front-most z (most negative) of a prop's vertices with x in [x0, x1], in the prop's own space.
	static func sliceProfile(root: Node3D, x0: float, x1: float) -> Dictionary:
		var top := -INF
		var front := INF
		for mi in _meshes(root):
			var m := relXform(mi, root)
			var mesh: Mesh = mi.mesh
			for s in mesh.get_surface_count():
				var arr: Array = mesh.surface_get_arrays(s)
				if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
					continue
				for v in arr[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = m * v
					if p.x < x0 or p.x > x1:
						continue
					if p.y > top:
						top = p.y
					if p.z < front:
						front = p.z
		return {"top": top, "front": front}

	# Canvas2D emulation (scripts/gfx/canvas2d.gd, DACanvas), loaded dynamically so this file never depends on it.
	static func newCanvas(w: int, h: int):
		var path := "res://scripts/gfx/canvas2d.gd"
		if not ResourceLoader.exists(path):
			return null
		var C = load(path)
		if C == null or not C.can_instantiate():
			return null
		return C.new(w, h)

	static func card(game, id: String, opts: Dictionary):
		var c = game.cards
		if c != null and c.has_method("getCard"):
			return c.getCard(id, opts)
		return null

	# THREE.Sprite(SpriteMaterial{map, color, additive, depthWrite:false, fog:false}): a camera-facing quad of
	# 1 x 1 world units scaled by the node, `rotation` spins the texture. color is linear (THREE.Color).
	static func sprite(tex, color: Color, opacity: float, priority: int) -> MeshInstance3D:
		if _spriteShader == null:
			_spriteShader = Shader.new()
			_spriteShader.code = SPRITE_SHADER
			_quad = QuadMesh.new()
			_quad.size = Vector2(1, 1)
		var m := ShaderMaterial.new()
		m.shader = _spriteShader
		m.render_priority = priority
		if tex != null:
			m.set_shader_parameter("map", tex)
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("opacity", opacity)
		var s := MeshInstance3D.new()
		s.mesh = _quad
		s.material_override = m
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.extra_cull_margin = 1.0
		return s

	static func spriteSet(s: MeshInstance3D, key: String, v) -> void:
		var m = s.material_override
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter(key, v)

	# renderOrder: the node's materials sort with this priority (materials duplicated, they are this node's own).
	static func setRenderPriority(n: Node, p: int) -> void:
		DAU.traverse(n, func(o):
			if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null:
				return
			var mi := o as MeshInstance3D
			if mi.material_override != null:
				mi.material_override = mi.material_override.duplicate()
				mi.material_override.render_priority = p
				return
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(s)
				if m != null:
					m = m.duplicate()
					m.render_priority = p
					mi.set_surface_override_material(s, m))

	# Meshes of a (prop) subtree whose material is a glow material (JS: material.name /^glow/).
	static func glowMeshes(root: Node) -> Array:
		var out: Array = []
		for mi in _meshes(root):
			var m: Material = mi.material_override if mi.material_override != null else mi.get_active_material(0)
			if m == null:
				continue
			var nm := m.resource_name
			var spec = null
			if m.has_meta("da"):
				spec = m.get_meta("da")
			elif m.has_meta("extras") and m.get_meta("extras") is Dictionary:
				spec = m.get_meta("extras").get("da")
			if spec is String:
				spec = JSON.parse_string(spec)
			if nm.begins_with("glow") or (spec is Dictionary and spec.get("kind") == "glow"):
				out.append(mi)
		return out

	# JS InstancedMesh.setMatrixAt: a MultiMeshInstance3D, or a parent whose children <name>_<i> are the instances.
	static func instSetXform(inst: Node3D, i: int, xf: Transform3D) -> void:
		if inst is MultiMeshInstance3D:
			var mm: MultiMesh = (inst as MultiMeshInstance3D).multimesh
			if mm != null and i < mm.instance_count:
				mm.set_instance_transform(i, xf)
			return
		var c = inst.get_node_or_null(NodePath("%s_%d" % [inst.name, i]))
		if c == null and i < inst.get_child_count():
			c = inst.get_child(i)
		if c is Node3D:
			(c as Node3D).transform = xf

	# The root node userData of a runtime asset (the glTF scene root or its single top node).
	static func rootUd(inst: Node) -> Dictionary:
		var ud := DAU.ud(inst)
		if not ud.is_empty():
			return ud
		if inst.get_child_count() == 1:
			return DAU.ud(inst.get_child(0))
		return ud

	static func _extrasDa(o: Object):
		if not o.has_meta("extras"):
			return null
		var ex = o.get_meta("extras")
		if not (ex is Dictionary) or not ex.has("da"):
			return null
		var d = ex.da
		if d is String:
			d = JSON.parse_string(d)
		return d

	# Runtime asset conventions (SPEC §5.4/§5.5): node "da" -> DAU.ud (+ visible:false, castShadow), material "da"
	# spec -> game.mats.fromSpec(spec, importedMaterial).
	static func prepare(game, root: Node) -> void:
		var mats = game.mats
		var cache := {}
		DAU.traverse(root, func(o):
			var d = _extrasDa(o)
			if d is Dictionary:
				DAU.ud(o).merge(d, true)
				if d.get("visible") == false and o is Node3D:
					o.visible = false
			if o is Node3D and (o as Node3D).rotation_order != EULER_ORDER_XYZ:
				(o as Node3D).rotation_order = EULER_ORDER_XYZ
			if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null:
				return
			var mi := o as MeshInstance3D
			var cs = DAU.ud(mi).get("castShadow")
			if cs != null:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cs else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mats == null or not mats.has_method("fromSpec"):
				return
			for s in mi.mesh.get_surface_count():
				var im: Material = mi.mesh.surface_get_material(s)
				if im == null:
					continue
				var spec = _extrasDa(im)
				if not (spec is Dictionary):
					continue
				if not cache.has(im):
					cache[im] = mats.fromSpec(spec, im)
				if cache[im] != null:
					mi.set_surface_override_material(s, cache[im]))
