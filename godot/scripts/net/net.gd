# Net: online co-op sessions, lobby, messaging and remote players (MP_SPEC §3 + scratchpad RECONCILE; Godot high-level
# multiplayer over ENet/UDP). The system `game.net` (constructed by Game like every system, initialized right after
# `input`). Game calls update(realDt) FIRST in every state (received messages are dispatched there, remote players
# interpolate + animate there) and lateUpdate(realDt) LAST in every state (the local player's state stream is sent
# there, 30 Hz). The @rpc functions live on the Node "Net" (scripts/net/net_node.gd, /root/Game/Net on every peer).
# SOLO: active == false, authority == true, localId == sender == 1; every call below is a direct local call or a no-op
# and nothing here touches game.rand() or any world state, so the solo game is unchanged.
#
# SESSION / ROLES
#   active      an MP session exists (hosting, connecting / connected, lobby or game). false in solo.
#   inGame      an MP game is running: true from the start message (BEFORE the MP newGame's resets run) until the
#               return to the lobby (endGame) or the end of the session. Stays true through game over / victory.
#   isHost / isClient · authority (== not isClient: solo or host may mutate the world — USE THIS in guards)
#   localId     our peer id (1 = host; 1 in solo too)
#   sender      during a message / stream handler: the ORIGINAL sending peer id (also for toOthers messages relayed
#               by the host; 1 = host); outside handlers: localId. withSender(id, fn) runs fn with sender = id
#               (host-side code paths that act for a peer, e.g. points credit).
#   peers       {id -> PeerInfo}; PeerInfo = {id, name, hero, ready, loaded, color (hero colour '#rrggbb'), ping (ms),
#               slot (0..3: join order = spawn slot), ext ({} the peer's setLocalExt values), player (Player |
#               RemotePlayer | null outside a game)}. Other systems may add their own per-peer fields.
#   lobby       {phase: 'lobby' | 'starting' | 'game', countdown (s, phase 'starting'), players: [PeerInfo minus
#               player / ext, by slot], seed, max, version, host (host name)} — {} without a session.
#               Host-authoritative; clients get a copy on every change (net:lobby).
#   maxPlayers 4 · port 31313 (UDP game port) · lanPort 31314 (LAN beacon) · version (protocol, must match to join)
#   status      last net:status: '' | 'hosting' | 'connecting' | 'connected' | 'rejected' | 'failed' | 'lost' | 'left'
#   lan         [{ip, name, players, max, port, version, seen}] LAN games heard by discover(true) (3.5 s expiry)
#   upnp        {state: 'off' | 'working' | 'ok' | 'failed', externalIp}
#   startInfo   the last start message {seed, heroes: {id: hero}, slots: {id: slot}, names: {id: name}, params}
#   interpDelay RemotePlayer interpolation delay (s, 0.1) · bandwidth {up, down} bytes/s of the ENet host (QA)
#   worldParams launch params the host sends in `start` (power, doors, round, nozombies, points, area): every client
#               applies the host's values (its own command-line values are restored when the session ends). Systems
#               may append their own world param keys in init().
# host(opts := {name, hero, port, lan := true, upnp := true}) -> bool   ENet server on `port` (4 players), LAN beacon
#   (1 s broadcast on lanPort while the lobby is open), UPnP mapping in a thread (net:upnp when done; removed on
#   leave / exit). The host is peer 1, slot 0.
# join(ip, port := 31313, opts := {name, hero}) -> bool   client; on connect it sends hello {version, name, hero}; the
#   host answers welcome {id, lobby} (net:status 'connected') or reject {reason: 'version' | 'full' | 'started' |
#   'kicked'} (net:status 'rejected', reason) and disconnects.
# leave() graceful disconnect (bye; net:status 'left'); a running game goes back to the 'menu' state (the menu shows
#   its own screens on net:status). The host leaving ends the session for everyone: clients get net:status 'lost' with
#   reason 'host_left' ('disconnected' when the transport dropped without a bye). 'failed' reasons: 'connect',
#   'timeout' (no welcome), 'port' (host could not bind). kick(id) (host).
# discover(on) LAN listener (net:lan {list} on changes).
# setHero(heroId) -> bool (lobby; unique heroes, the host rejects a taken one: net:hero {hero, ok:false}),
#   setReady(on) -> bool (only when game.loaded), setName(name), canStart() -> bool (host: every other player loaded +
#   ready, or the host alone).
# START (host startGame() -> bool): lobby.phase 'starting' + lobby.countdown (COUNTDOWN 3 s; mpcountdown=<s>; 0 for the
#   test=1 auto start) broadcast; then start {seed, heroes, slots, names, params} to everyone. Every peer: inGame =
#   true, game.seed_value = seed, clients take the host's world params, emits 'net:start' {seed, heroes, slots, names,
#   id, hero}; then game.menu.mpStart(hero) when it exists and returns true (the menu plays its dive and calls
#   game.newGame(hero) itself, START_TIMEOUT safety), else game.newGame(hero) right away. Until the local newGame ran,
#   received world messages (sys != 'net') are held in order and streams dropped, so every later host message is
#   handled after it. The MP newGame (Game) calls onNewGame(): the local player moves to its spawn slot around
#   player_spawn, the RemotePlayers are built (net:avatar {id} each); then game:start.
# endGame(reason := '') (host; alias returnToLobby): everyone back to the lobby (inGame false, ready flags cleared,
#   remote players removed, state 'menu', net:lobby). Used after the MP game over / results cards.
# PLAYERS (MP_SPEC §3.2, RECONCILE R6/R12): players() -> Array (local first, then remotes by slot; includes downed /
#   off-air ones), targets() -> Array (alive, not downed, not off-air, not hidden, not inCommercial; invulnerable
#   players stay targetable; solo: [game.player] if targetable). Both return a shared Array rebuilt once per frame:
#   read it, never modify it. playerById(id) · idOf(player) -> int (0 = unknown) · nearestPlayer(pos, onlyTargets :=
#   true) · nameOf(id) · slotOf(id) · colorOf(id) · isLocal(player) · remotes() -> Array · isTargetable(player) ·
#   viewPlayer() (the player the local camera follows: game.player.spectate when set, else game.player) ·
#   spawnPoint(slot) -> {pos, yaw} · teamSummary() -> {round, kills, points (local), players: [{id, name, hero, color,
#   slot, kills, points, downs, revives}]} (economy.statsOf(id) / rounds.killsBy / player.mp.team when they exist).
# EXT (small per-player replicated values, e.g. perk loadout, costume): setLocalExt(key, value) (null erases; sent
#   reliably to the others on change; cleared at every game start), localExt() -> Dictionary, extOf(id) ->
#   Dictionary (RemotePlayer.ext is the same object). Event net:ext {id, key, value} on the receivers.
# MESSAGING (MP_SPEC §3.3). Arguments must be plain Variants (int, float, bool, String, Vector2/3, Color, Array,
#   Dictionary, Packed*): never an Object / Node / Callable (zombies as z.id, players as peer ids, the acting peer as
#   `by`).
#   toHost(sys, method, args := [])      client -> host request; on the host (or solo) the handler runs right away.
#   toAll(sys, method, args := [])       host -> every client (not self), reliable + ordered. No-op in solo.
#   everyone(sys, method, args := [])    host: toAll then the local call (the replicated action). Solo: local call.
#   toPeer(id, sys, method, args := [])  -> one peer (id == localId or solo: local call). Clients go through the host.
#   toOthers(sys, method, args := [])    any peer -> every other peer (relayed by the host, which handles it too).
#   stream(channel, data)                unreliable ordered (channel 1) to every other peer: snapshots. Receiver:
#                                        game.<sys>.net_stream_<channel>(from, data), sys from registerStream.
#   registerStream(channel, sysName)     (call it in init(); short String channel names, e.g. 'z')
#   emitAll(name, payload)               host: game.events.emit locally + on every client (payload without Objects).
#   A message (sys, method, args) calls game.<sys>.net_<method>(args...) on the receiver ("game" = the Game node
#   itself). Unknown system / method / wrong arg count: one push_warning, ignored. Handlers must validate (ids may
#   refer to things already gone) — declare their params untyped. Reliable messages from one sender arrive in order;
#   every frame the received reliable messages are handled before the received streams.
# EVENTS (game.events): net:lobby {lobby} · net:peer {id, joined} (every peer) · net:status {status, reason} · net:lan
#   {list} · net:upnp {ok, ip} · net:hero {hero, ok} · net:ping {pings: {id: ms}} · net:start {...} · net:ext {id, key,
#   value} · net:avatar {id} (RemotePlayer model built)
# MESSAGES of this system (sys "net"): hello {version, name, hero} / welcome {id, lobby} / reject {reason} / bye
#   (reason) / lobby (lobby) / setHero (hero) / heroDenied (hero) / ready (on) / loaded () / name (name) / start
#   ({seed, heroes, slots, names, params}) / toLobby (reason) / pings ({id: ms}) / peerLeft (id) / emit (name, payload)
#   / ext (key, value) / hurt (dmg, fromPos) and knockback (vec) (owner side of RemotePlayer.hurt / knockback while
#   player.gd has no net_hurt / net_knockback). Streams: 'p' (player state, 30 Hz, remote_player.gd format).
# QA / TEST PARAMS (with test=1 Game.boot calls autoBoot(): no menus): mp=host|join, mpip (an address, or 'lan' = the
#   first LAN game heard), mpport, mpname, mpstart=N (the host starts once N players are connected, loaded and ready;
#   everyone auto-readies), mpcountdown=<s>, mpjoindelay=<s>, mpversion=<v> (protocol override: mismatch tests), mpmax=<n>,
#   mpupnp=0|1 (default 0 with test=1), mplan=0|1 (beacon), mplanport, mpdiscover=1 (listen for beacons). Simulated
#   network conditions on the RECEIVE side: mplag=<ms one way>, mpjitter=<ms>, mploss=<0..1> (drops unreliable
#   packets only; reliable ones are delayed, never dropped or reordered).
extends RefCounted

const NetNodeScript = preload("res://scripts/net/net_node.gd")
const LanScript = preload("res://scripts/net/net_lan.gd")
const UpnpScript = preload("res://scripts/net/net_upnp.gd")
const RemotePlayerScript = preload("res://scripts/net/remote_player.gd")
const HEROES_PATH := "res://scripts/actors/heroes.gd"

const PROTOCOL := "deadair-mp-1"
const DEFAULT_PORT := 31313
const DEFAULT_LAN_PORT := 31314
const MAX_PLAYERS := 4
const EXTRA_CONNECTIONS := 2        # ENet slots beyond the player cap: a 5th player gets a 'full' reject, not a timeout
const SEND_RATE := 30.0             # player state stream (Hz)
const PING_EVERY := 1.0
const PINGS_EVERY := 2.0
const HELLO_TIMEOUT := 10.0
const WELCOME_TIMEOUT := 30.0           # wall clock: a client compiling shaders can stall for seconds
const REJECT_GRACE := 1.5           # s a rejected peer keeps its connection (the reject message flushes), then dropped
const CLOSE_GRACE := 0.6            # s a closed transport is still polled (bye / disconnect packets go out)
const COUNTDOWN := 3.0              # lobby 'starting' phase before the start message
const START_TIMEOUT := 6.0          # menu.mpStart took over but never called newGame: start anyway
# Hero colours for MP UI (menu CHANNELS glow; RECONCILE R8)
const HERO_COLORS := {"skip": "#FFB870", "roxy": "#FF6FB0", "penny": "#7FD8FF", "duke": "#8A9CFF"}
# spawn slots around player_spawn, in the spawn's frame: x = right, y = back (m)
const SLOT_OFFSETS := [Vector2(0.0, 0.0), Vector2(1.4, 0.0), Vector2(-1.4, 0.0), Vector2(0.0, 1.4)]
const NAME_MAX := 16

var game
var node: Node = null
var peer: ENetMultiplayerPeer = null
var active := false
var inGame := false
var isHost := false
var isClient := false
var authority := true
var localId := 1
var sender := 1
var peers := {}
var lobby := {}
var maxPlayers := MAX_PLAYERS
var port := DEFAULT_PORT
var lanPort := DEFAULT_LAN_PORT
var version := PROTOCOL
var status := ""
var lan: Array = []
var upnp := {"state": "off", "externalIp": ""}
var startInfo := {}
var interpDelay: float = RemotePlayerScript.INTERP_DELAY
var bandwidth := {"up": 0, "down": 0}
var worldParams: Array = ["power", "doors", "round", "nozombies", "points", "area"]
var sim := {"lag": 0.0, "jitter": 0.0, "loss": 0.0}

var _mp: MultiplayerAPI = null
var _lan = null
var _upnp = null
var _streams := {"p": "net"}
var _remotes := {}             # id -> RemotePlayer
var _queue: Array = []         # received, not yet dispatched: [releaseT, kind, from, a, b, c]
var _queueSwap: Array = []
var _lastRel := {}             # (from * 8 + kind) -> last release time (keeps per-sender order under jitter)
var _pending := {}             # host: connected peers that have not said hello yet: id -> connect time
var _rejecting := {}           # host: id -> time after which the rejected peer is force-disconnected
var _closing: Array = []       # [[ENetMultiplayerPeer, closeAt]]
var _joinInfo := {}            # client: {name, hero} for the hello
var _connectT := 0.0
var _connectFrames := 0
var _welcomed := false
var _loadedSent := false
var _byeReason := ""
var _phase := ""
var _seed := 0
var _countdownT := -1.0
var _startPending := false     # start received, the local newGame has not run yet
var _startPendingT := 0.0
var _startHero = null
var _paramBackup = null        # client: {key: [had, value]} of its own world params while the host's apply
var _ext := {}                 # the local player's ext values
var _slots: Array = []         # spawn points of the current game [{pos, yaw}] by slot
var _sendAcc := 0.0
var _seq := 0
var _encSt := {}
var _epochMs := 0
var _buf := PackedByteArray()
var _pingT := 0.0
var _pingsT := 0.0
var _bwT := 0.0
var _auto := {}
var _autoJoinT := -1.0
var _readyReqT := -INF
var _plist: Array = []
var _tlist: Array = []
var _plistFrame := -1
var _warned := {}
var _argCache := {}
var _heroIds: Array = []
var _defaultHero := "duke"

func _init(g) -> void:
	game = g

# ------------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	var g = game
	var P: Dictionary = g.params
	_lan = LanScript.new()
	_upnp = UpnpScript.new()
	if ResourceLoader.exists(HEROES_PATH):
		var H = load(HEROES_PATH)
		if H != null:
			for h in H.HEROES:
				_heroIds.append(h.id)
			_defaultHero = H.DEFAULT_HERO
	if P.get("mpversion") != null:
		version = str(P.mpversion)
	if P.get("mpport") is int:
		port = int(P.mpport)
	if P.get("mplanport") is int:
		lanPort = int(P.mplanport)
	if P.get("mpmax") is int:
		maxPlayers = clampi(int(P.mpmax), 1, MAX_PLAYERS)
	sim.lag = maxf(0.0, _num(P.get("mplag"), 0.0) / 1000.0)
	sim.jitter = maxf(0.0, _num(P.get("mpjitter"), 0.0) / 1000.0)
	sim.loss = clampf(_num(P.get("mploss"), 0.0), 0.0, 1.0)
	node = NetNodeScript.new()
	node.name = "Net"
	node.net = self
	g.add_child(node)
	_mp = g.get_tree().get_multiplayer() if g.is_inside_tree() else null
	if _mp != null:
		_mp.peer_connected.connect(_onPeerConnected)
		_mp.peer_disconnected.connect(_onPeerDisconnected)
		_mp.connected_to_server.connect(_onConnected)
		_mp.connection_failed.connect(_onConnectFailed)
		_mp.server_disconnected.connect(_onServerDisconnected)

# newGame resets every system: the session survives (the MP flavour of newGame calls onNewGame() instead).
func reset() -> void:
	pass

# Test boot (Game.boot with test=1 and an mp= param): host / join right away, auto-ready, auto-start (mpstart=N).
func autoBoot() -> bool:
	var P: Dictionary = game.params
	var mode = P.get("mp")
	if mode == null:
		return false
	var hero = P.get("char")
	var upnpOn := _truthy(P.get("mpupnp")) if P.has("mpupnp") else false
	var lanOn := _truthy(P.get("mplan")) if P.has("mplan") else true
	if P.get("mpdiscover"):
		discover(true)
	if str(mode) == "host":
		_auto = {"mode": "host", "start": int(P.get("mpstart", 0)) if (P.get("mpstart") is int) else 0}
		return host({"name": str(P.get("mpname", "HOST")), "hero": hero, "upnp": upnpOn, "lan": lanOn})
	if str(mode) == "join":
		_auto = {"mode": "join", "ip": str(P.get("mpip", "127.0.0.1")), "hero": hero, "name": str(P.get("mpname", "PLAYER"))}
		_autoJoinT = _num(P.get("mpjoindelay"), 0.0)
		if str(_auto.ip) == "lan":
			discover(true)
		return true
	push_warning("[net] unknown mp=%s (host | join)" % str(mode))
	return false

# Exit (Game's predelete, before the teardown): bye (best effort, flushed at once), close the transport, join the
# UPnP thread. No events and no state changes: the systems are being torn down.
func shutdown() -> void:
	if active and _canSend():
		if isHost:
			toAll("net", "bye", ["host_left"])
		else:
			_sendTo(1, "net", "bye", ["left"])
		_disconnectAllLater()
		if peer.host != null:
			peer.host.flush()
	if peer != null:
		_closing.append([peer, 0.0])
		if _mp != null and is_instance_valid(_mp) and _mp.multiplayer_peer == peer:
			_mp.multiplayer_peer = null
		peer = null
	active = false
	inGame = false
	for c in _closing:
		var p: ENetMultiplayerPeer = c[0]
		if p != null:
			p.poll()
			p.close()
	_closing.clear()
	if _lan != null:
		_lan.close()
	if _upnp != null:
		_upnp.shutdown()
	if node != null and is_instance_valid(node):
		node.net = null

# ------------------------------------------------------------------------------------------------ per frame
# First thing every frame, in every state: dispatch what arrived, LAN / UPnP / handshake / ping housekeeping, and
# the remote players' interpolation + animation.
func update(dt: float = 0.0) -> void:
	var now := _now()
	if not _queue.is_empty():
		_drain(now)
	if not _closing.is_empty():
		_pollClosing(now)
	if _lan != null and (_lan.listening or not _lan.list.is_empty()):
		if _lan.poll(now):
			lan = _lan.list
			_emit("net:lan", {"list": lan})
	if _upnp != null and _upnp.tick():
		upnp = {"state": _upnp.state, "externalIp": _upnp.externalIp}
		_emit("net:upnp", {"ok": _upnp.state == "ok", "ip": _upnp.externalIp})
	if _autoJoinT >= 0.0 and not active:
		_autoJoinT -= dt
		if _autoJoinT <= 0.0:
			_autoJoin()
	if not active:
		return
	if _startPending:
		_startPendingT -= dt
		if _startPendingT <= 0.0:
			push_warning("[net] menu.mpStart did not start the game: starting it")
			game.newGame(_startHero)
	if isHost:
		_hostTick(dt, now)
	elif isClient:
		_clientTick(now)
	if inGame and not _remotes.is_empty():
		for id in _remotes:
			_remotes[id].update(dt)
	_bwT += dt
	if _bwT >= 1.0 and peer != null:
		var h: ENetConnection = peer.host
		if h != null:
			bandwidth.up = int(h.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / _bwT)
			bandwidth.down = int(h.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / _bwT)
		_bwT = 0.0

# Last thing every frame: the local player's state stream (owner -> everyone, 30 Hz, unreliable ordered).
func lateUpdate(dt: float = 0.0) -> void:
	if not inGame or _startPending or not _canSend() or _mp.get_peers().is_empty():
		return
	var p = game.player
	if p == null:
		return
	_sendAcc += dt
	var period := 1.0 / SEND_RATE
	if _sendAcc < period - 1e-4:
		return
	_sendAcc = minf(_sendAcc - period, period)
	_buf = RemotePlayerScript.encodeLocal(game, _buf, _seq, Time.get_ticks_msec() - _epochMs, _encSt)
	_seq = (_seq + 1) & 0xFFFF
	stream("p", _buf)

func _hostTick(dt: float, now: float) -> void:
	var me = peers.get(localId)
	if me != null and bool(me.loaded) != bool(game.loaded):
		me.loaded = bool(game.loaded)
		_lobbyChanged()
	for id in _pending.keys():
		if now - float(_pending[id]) > HELLO_TIMEOUT:
			_pending.erase(id)
			_disconnectPeer(id)
	for id in _rejecting.keys():
		if now >= float(_rejecting[id]):
			_rejecting.erase(id)
			_disconnectPeer(id)
	if _lan != null and _lan.beaconing and _phase == "lobby":
		_lan.beacon(dt, {"name": str(peers[1].name) if peers.has(1) else "HOST", "players": peers.size(), "max": maxPlayers,
			"version": version, "port": port})
	_pingT -= dt
	if _pingT <= 0.0:
		_pingT = PING_EVERY
		var t := Time.get_ticks_msec() / 1000.0
		for id in peers:
			if id != localId and _peerUp(id):
				node.rpc_id(id, "_ping", t)
	_pingsT -= dt
	if _pingsT <= 0.0 and peers.size() > 1:
		_pingsT = PINGS_EVERY
		var tab := {}
		for id in peers:
			tab[id] = int(peers[id].ping)
		everyone("net", "pings", [tab])
	if _phase == "starting" and _countdownT >= 0.0:
		_countdownT -= dt
		if _countdownT <= 0.0:
			_countdownT = -1.0
			_sendStart()
	var n := int(_auto.get("start", 0))
	if n > 0 and _phase == "lobby" and peers.size() >= n and canStart():
		startGame()

func _clientTick(now: float) -> void:
	if not _welcomed:
		# wall time AND polled frames: a client stalled by a long frame (shader compilation) must not give up early
		_connectFrames += 1
		if now - _connectT > WELCOME_TIMEOUT and _connectFrames > 120:
			_endSession("failed", "timeout")
		return
	if game.loaded and not _loadedSent:
		_loadedSent = true
		toHost("net", "loaded", [])
	if _auto.get("mode") == "join" and _phase == "lobby" and game.loaded:
		var me = peers.get(localId)
		if me != null and not me.ready and me.loaded and now - _readyReqT > 1.0:
			_readyReqT = now
			setReady(true)

# ------------------------------------------------------------------------------------------------ session
func host(opts: Dictionary = {}) -> bool:
	if active:
		leave()
	var p := ENetMultiplayerPeer.new()
	if opts.get("port") is int:
		port = int(opts.port)
	var err := p.create_server(port, maxPlayers - 1 + EXTRA_CONNECTIONS)
	if err != OK:
		_status("failed", "port")
		return false
	if p.host != null:
		p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_attach(p)
	active = true
	isHost = true
	isClient = false
	authority = true
	localId = 1
	sender = 1
	_welcomed = true
	peers.clear()
	var me := _newPeer(1, _cleanName(opts.get("name"), "HOST"), _pickHero(opts.get("hero"), 0), 0)
	me.loaded = bool(game.loaded)
	peers[1] = me
	_phase = "lobby"
	_refreshLobby()
	if opts.get("lan", true) != false and _lan != null:
		_lan.startBeacon(lanPort)
	if opts.get("upnp", true) != false and _upnp != null:
		_upnp.start(port)
		upnp = {"state": _upnp.state, "externalIp": ""}
	_status("hosting", "")
	_emit("net:lobby", {"lobby": lobby})
	return true

func join(ip: String, port_: int = DEFAULT_PORT, opts: Dictionary = {}) -> bool:
	if active:
		leave()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port_)
	if err != OK:
		_status("failed", "connect")
		return false
	if p.host != null:
		p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	port = port_
	_attach(p)
	active = true
	isHost = false
	isClient = true
	authority = false
	localId = p.get_unique_id()
	sender = localId
	_welcomed = false
	_loadedSent = false
	_byeReason = ""
	_connectT = _now()
	_connectFrames = 0
	_joinInfo = {"name": _cleanName(opts.get("name"), "PLAYER"), "hero": opts.get("hero")}
	peers.clear()
	_phase = ""
	lobby = {}
	_status("connecting", "")
	return true

# Graceful leave: bye to the others (the host's bye ends the session for everyone), then the transport closes
# CLOSE_GRACE s later; locally the session ends at once (net:status 'left').
func leave() -> void:
	if not active:
		return
	if _canSend():
		if isHost:
			toAll("net", "bye", ["host_left"])
		else:
			_sendTo(1, "net", "bye", ["left"])
		var h: ENetConnection = peer.host
		if h != null:
			h.flush()
		_disconnectAllLater()
	_endSession("left", "")

# Every ENet connection (the host's clients, or a client's host) disconnects once its queued packets went out.
func _disconnectAllLater() -> void:
	if peer == null or _mp == null:
		return
	for id in _mp.get_peers():
		if isHost or id == 1:
			var pp: ENetPacketPeer = peer.get_peer(id)
			if pp != null:
				pp.peer_disconnect_later()

func kick(id: int) -> void:
	if not isHost or id == localId or not peers.has(id):
		return
	_reject(id, "kicked")
	_dropPeer(id)

func discover(on: bool) -> void:
	if _lan != null:
		_lan.listen(on, lanPort)
		lan = _lan.list

func setHero(heroId) -> bool:
	if not active or not _heroIds.has(heroId) or _phase != "lobby":
		return false
	toHost("net", "setHero", [heroId])
	return true

func setReady(on: bool) -> bool:
	if not active or not game.loaded or _phase != "lobby":
		return false
	toHost("net", "ready", [on])
	return true

func setName(n: String) -> void:
	if active:
		toHost("net", "name", [n])

func canStart() -> bool:
	if not isHost or _phase != "lobby" or not game.loaded:
		return false
	for id in peers:
		if id == localId:
			continue
		var p = peers[id]
		if not p.loaded or not p.ready:
			return false
	return true

func startGame() -> bool:
	if not canStart():
		return false
	var P: Dictionary = game.params
	_seed = int(P.seed) if (P.get("seed") is int or P.get("seed") is float) else randi() % 2147483648
	_phase = "starting"
	var cd := COUNTDOWN
	if P.get("mpcountdown") is int or P.get("mpcountdown") is float:
		cd = maxf(0.0, float(P.mpcountdown))
	elif _auto.get("mode") == "host":
		cd = 0.0
	_countdownT = cd
	_lobbyChanged()
	if cd <= 0.0:
		_countdownT = -1.0
		_sendStart()
	return true

func _sendStart() -> void:
	if not isHost or _phase != "starting":
		return
	var heroes := {}
	var slots := {}
	var names := {}
	for id in peers:
		heroes[id] = peers[id].hero
		slots[id] = int(peers[id].slot)
		names[id] = str(peers[id].name)
	var wp := {}
	for k in worldParams:
		if game.params.has(k):
			wp[k] = game.params[k]
	everyone("net", "start", [{"seed": _seed, "heroes": heroes, "slots": slots, "names": names, "params": wp}])

func endGame(reason: String = "") -> void:
	if isHost and inGame:
		everyone("net", "toLobby", [reason])

func returnToLobby() -> void:
	endGame("")

# ------------------------------------------------------------------------------------------------ messaging
func toHost(sys: String, method: String, args: Array = []) -> void:
	if not isClient:
		_invoke(localId, sys, method, args)
		return
	_sendTo(1, sys, method, args)

func toAll(sys: String, method: String, args: Array = []) -> void:
	if not isHost:
		if isClient:
			_warnOnce("toAll:" + sys + "." + method, "[net] toAll(%s.%s) on a client is ignored (use toHost / toOthers)" % [sys, method])
		return
	if not _canSend():
		return
	_checkArgs(sys, method, args)
	for id in peers:
		if id != localId and _peerUp(id):
			node.rpc_id(id, "_m", sys, method, args)

func everyone(sys: String, method: String, args: Array = []) -> void:
	if isClient:
		_warnOnce("everyone:" + sys + "." + method, "[net] everyone(%s.%s) on a client is ignored (use toHost)" % [sys, method])
		return
	toAll(sys, method, args)   # serialized first: the local handler may modify args
	_invoke(localId, sys, method, args)

func toPeer(id: int, sys: String, method: String, args: Array = []) -> void:
	if id == localId or not active:
		_invoke(localId, sys, method, args)
		return
	if isHost or id == 1:
		_sendTo(id, sys, method, args)
	elif _canSend():
		_checkArgs(sys, method, args)
		node.rpc_id(1, "_rq", id, sys, method, args)   # via the host

func toOthers(sys: String, method: String, args: Array = []) -> void:
	if not active or not _canSend():
		return
	if isHost:
		toAll(sys, method, args)
		return
	_checkArgs(sys, method, args)
	node.rpc_id(1, "_rq", 0, sys, method, args)        # the host handles it and forwards it to the others

func stream(channel: String, data) -> void:
	if not active or not _canSend():
		return
	if isHost:
		for id in peers:
			if id != localId and _peerUp(id):
				node.rpc_id(id, "_s", channel, data)
	else:
		node.rpc_id(1, "_sq", channel, data)           # the host handles it and forwards it to the others

func registerStream(channel: String, sysName: String) -> void:
	_streams[channel] = sysName

func emitAll(name: String, payload = null) -> void:
	if isClient:
		_warnOnce("emitAll:" + name, "[net] emitAll(%s) on a client is ignored" % name)
		return
	everyone("net", "emit", [name, payload])

# Runs fn with `sender` = id (host-side code acting for a peer), restoring it after.
func withSender(id: int, fn: Callable):
	var prev := sender
	sender = id
	var r = fn.call()
	sender = prev
	return r

# Direct message on the reliable channel (host -> one client, or client -> host).
func _sendTo(id: int, sys: String, method: String, args: Array) -> void:
	if not _canSend():
		_warnOnce("nosend:" + sys + "." + method, "[net] %s.%s dropped: not connected" % [sys, method])
		return
	if not _peerUp(id):
		return
	_checkArgs(sys, method, args)
	node.rpc_id(id, "_m", sys, method, args)

func _canSend() -> bool:
	return peer != null and node != null and node.is_inside_tree() \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _hasPeer(id: int) -> bool:
	return _mp != null and _mp.get_peers().has(id)

# A live ENet connection to `id` (the host's clients; a client only has the host, id 1): never send to a peer that
# is connecting, disconnecting or gone.
func _peerUp(id: int) -> bool:
	if peer == null or not _hasPeer(id) or (not isHost and id != 1):
		return false
	var pp: ENetPacketPeer = peer.get_peer(id)
	return pp != null and pp.get_state() == ENetPacketPeer.STATE_CONNECTED

# Host: forwards a client's message / stream to the session members (relay with the original sender id).
func _relayMsg(origin: int, target: int, sys, method, args) -> void:
	for id in peers:
		if id == localId or id == origin or (target != 0 and id != target):
			continue
		if _peerUp(id):
			node.rpc_id(id, "_rl", origin, sys, method, args)

func _relayStream(origin: int, channel, data) -> void:
	for id in peers:
		if id != localId and id != origin and _peerUp(id):
			node.rpc_id(id, "_sl", origin, channel, data)

# Debug builds: a message argument must be a plain Variant (MP_SPEC §3.3).
func _checkArgs(sys: String, method: String, args: Array) -> void:
	if OS.is_debug_build() and not _plain(args, 0):
		push_error("[net] %s.%s: arguments must be plain Variants (no Object / Node / Callable)" % [sys, method])

static func _plain(v, depth: int) -> bool:
	if depth > 16:
		return false
	match typeof(v):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_ARRAY:
			for e in v:
				if not _plain(e, depth + 1):
					return false
		TYPE_DICTIONARY:
			for k in v:
				if not _plain(k, depth + 1) or not _plain(v[k], depth + 1):
					return false
	return true

# ------------------------------------------------------------------------------------------------ receive
# net_node.gd hands every RPC here. kind: 0 message, 1 stream, 2 ping, 3 pong, 4 transport event ('gone' / 'host'),
# 5 relay request (host: a = target), 6 relayed message (client: a = origin), 7 stream relay request (host),
# 8 relayed stream (client: a = origin). Simulated conditions (mplag / mpjitter / mploss) delay the release (loss
# drops unreliable packets only); every class (reliable / streams / pings) keeps its per-sender order.
const RELIABLE_KINDS := [0, 4, 5, 6]

func _recv(kind: int, from: int, a, b, c, d) -> void:
	var rel := 0.0
	if sim.lag > 0.0 or sim.jitter > 0.0 or sim.loss > 0.0:
		var reliable := RELIABLE_KINDS.has(kind)
		if not reliable and sim.loss > 0.0 and randf() < sim.loss:
			return
		rel = _now() + sim.lag + randf() * sim.jitter
		var key := from * 8 + (0 if reliable else (1 if kind == 1 or kind >= 7 else 2))
		rel = maxf(rel, float(_lastRel.get(key, 0.0)))
		_lastRel[key] = rel
	_queue.append([rel, kind, from, a, b, c, d])

# Two passes over what is due: reliable messages + transport events first (in arrival order), then streams / pings.
# While a start is pending (the local newGame has not run), world messages are held and streams dropped.
func _drain(now: float) -> void:
	var q := _queue
	_queue = _queueSwap
	_queueSwap = q
	_queue.clear()
	for pass_ in 2:
		for e in q:
			var kind: int = e[1]
			if RELIABLE_KINDS.has(kind) != (pass_ == 0):
				continue
			if float(e[0]) > now:
				_queue.append(e)
				continue
			var from: int = e[2]
			match kind:
				0:
					if _startPending and str(e[3]) != "net":
						_queue.append(e)
						continue
					if isClient and from != 1:
						continue
					_onMsg(from, e[3], e[4], e[5])
				5:   # host: a client's message for others (target 0 = everyone else)
					if _startPending and str(e[4]) != "net":
						_queue.append(e)
						continue
					if not isHost or not peers.has(from) or not (e[3] is int):
						continue
					var target: int = e[3]
					if target != localId:
						_relayMsg(from, target, e[4], e[5], e[6])
					if target == 0 or target == localId:
						_onMsg(from, e[4], e[5], e[6])
				6:   # client: a message relayed by the host from peer `origin`
					if _startPending and str(e[4]) != "net":
						_queue.append(e)
						continue
					if isClient and from == 1 and e[3] is int:
						_onMsg(int(e[3]), e[4], e[5], e[6])
				1:
					if _startPending or (isClient and from != 1):
						continue
					_onStream(from, e[3], e[4])
				7:   # host: a client's stream for everyone else
					if isHost and peers.has(from):
						if not _startPending:
							_onStream(from, e[3], e[4])
						_relayStream(from, e[3], e[4])
				8:   # client: a stream relayed by the host from peer `origin`
					if not _startPending and isClient and from == 1 and e[3] is int:
						_onStream(int(e[3]), e[4], e[5])
				2:
					if isClient and _canSend() and from == 1:
						node.rpc_id(1, "_pong", e[3])
				3:
					_onPong(from, e[3])
				4:
					_onTransport(from, e[3])
	q.clear()

# Session gating: before its welcome a client only listens to the host's "net" messages; the host only accepts a
# hello from a connection that is not a member yet.
func _onMsg(from: int, sys, method, args) -> void:
	if not active:
		return
	if not (sys is String or sys is StringName) or not (method is String or method is StringName) or not (args is Array):
		_warnOnce("bad:%d" % from, "[net] malformed message from peer %d dropped" % from)
		return
	if isClient and not _welcomed and String(sys) != "net":
		return
	if isHost and from != localId and not peers.has(from) and not (String(sys) == "net" and String(method) == "hello"):
		return
	_invoke(from, String(sys), String(method), args)

func _invoke(from: int, sys: String, method: String, args: Array) -> void:
	var target = game if sys == "game" else game.get(sys)
	var fn := "net_" + method
	if not (target is Object) or not is_instance_valid(target) or not target.has_method(fn):
		_warnOnce("nohandler:" + sys + "." + method, "[net] no handler %s.net_%s (message ignored)" % [sys, method])
		return
	var r := _argRange(target, fn)
	if args.size() < r.x or args.size() > r.y:
		_warnOnce("argc:" + sys + "." + method, "[net] %s.net_%s: %d args (expects %d..%d), ignored" % [sys, method, args.size(), r.x, r.y])
		return
	var prev := sender
	sender = from
	target.callv(fn, args)
	sender = prev

func _argRange(obj: Object, fn: String) -> Vector2i:
	var scr = obj.get_script()
	var key := "%d:%s" % [scr.get_instance_id() if scr != null else obj.get_instance_id(), fn]
	if _argCache.has(key):
		return _argCache[key]
	var r := Vector2i(0, 64)
	if scr != null:
		for m in scr.get_script_method_list():
			if m.name == fn:
				var n: int = (m.args as Array).size()
				r = Vector2i(n - (m.default_args as Array).size(), n)
				break
	_argCache[key] = r
	return r

func _onStream(from: int, channel, data) -> void:
	if not active or not (channel is String or channel is StringName) or (isClient and not _welcomed):
		return
	var ch := String(channel)
	var sysName = _streams.get(ch)
	var target = null
	if sysName != null:
		target = game if sysName == "game" else game.get(sysName)
	var fn := "net_stream_" + ch
	if not (target is Object) or not target.has_method(fn):
		_warnOnce("nostream:" + ch, "[net] no stream handler for '%s'" % ch)
		return
	var prev := sender
	sender = from
	target.call(fn, from, data)
	sender = prev

func _onPong(from: int, t) -> void:
	if not isHost or not (t is float or t is int) or not peers.has(from):
		return
	var rtt := maxf(0.0, Time.get_ticks_msec() / 1000.0 - float(t)) * 1000.0
	var p = peers[from]
	p.ping = int(round(rtt)) if int(p.ping) == 0 else int(round(lerpf(float(p.ping), rtt, 0.35)))

# ------------------------------------------------------------------------------------------------ transport
func _attach(p: ENetMultiplayerPeer) -> void:
	peer = p
	_epochMs = Time.get_ticks_msec()
	_queue.clear()
	_lastRel.clear()
	_pending.clear()
	_rejecting.clear()
	_seq = 0
	_encSt = {}
	_sendAcc = 0.0
	_pingT = 0.0
	_pingsT = 0.0
	_countdownT = -1.0
	_startPending = false
	bandwidth = {"up": 0, "down": 0}
	if _mp != null:
		_mp.set("server_relay", false)   # explicit host relay (_rq / _sq -> _rl / _sl): see net_node.gd
		_mp.multiplayer_peer = p

# Detaches the transport from SceneMultiplayer at once; the ENet peer keeps being polled for CLOSE_GRACE s so the
# queued bye / disconnect commands go out, then it is closed.
func _detachPeer() -> void:
	if peer == null:
		return
	if _mp != null and _mp.multiplayer_peer == peer:
		_mp.multiplayer_peer = null
	_closing.append([peer, _now() + CLOSE_GRACE])
	peer = null

func _pollClosing(now: float) -> void:
	for i in range(_closing.size() - 1, -1, -1):
		var c: Array = _closing[i]
		var p: ENetMultiplayerPeer = c[0]
		if p.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_closing.remove_at(i)   # already closed (a client's transport closes itself when the host lets go)
		elif now >= float(c[1]):
			p.close()
			_closing.remove_at(i)
		else:
			p.poll()
			while p.get_available_packet_count() > 0:
				p.get_packet()

func _setPeerTimeout(id: int) -> void:
	if peer == null:
		return
	var pp: ENetPacketPeer = peer.get_peer(id)
	if pp != null:
		# loading a game blocks a frame for seconds: be patient before declaring a peer dead (default min 5 s)
		pp.set_timeout(32, 15000, 30000)

func _disconnectPeer(id: int) -> void:
	if peer != null and _hasPeer(id):
		peer.disconnect_peer(id)

func _onPeerConnected(id: int) -> void:
	if isHost:
		_pending[id] = _now()
		_setPeerTimeout(id)

func _onPeerDisconnected(id: int) -> void:
	if active:
		_recv(4, id, "gone", null, null, null)

func _onConnected() -> void:
	if not isClient:
		return
	_setPeerTimeout(1)
	_sendTo(1, "net", "hello", [{"version": version, "name": _joinInfo.get("name", "PLAYER"), "hero": _joinInfo.get("hero")}])

func _onConnectFailed() -> void:
	if isClient:
		_endSession("failed", "connect")

func _onServerDisconnected() -> void:
	if isClient:
		_recv(4, 1, "host", null, null, null)

func _onTransport(from: int, what) -> void:
	if not active:
		return
	if what == "host":
		_endSession("lost", _byeReason if _byeReason != "" else "disconnected")
	elif what == "gone":
		if isHost:
			_pending.erase(from)
			_rejecting.erase(from)
		if peers.has(from) and from != localId:
			_dropPeer(from)

# A peer left (disconnect, bye, kick): its RemotePlayer goes away and net:peer {joined:false} fires on every peer
# (the host relays peerLeft), the lobby is updated.
func _dropPeer(id: int) -> void:
	if not peers.has(id):
		return
	_removeRemote(id)
	peers.erase(id)
	_plistFrame = -1
	if isHost:
		toAll("net", "peerLeft", [id])     # the members only (id is no longer one)
		_lobbyChanged()
		_disconnectPeer(id)
	_emit("net:peer", {"id": id, "joined": false})

func _endSession(st: String, reason: String) -> void:
	var wasGame := inGame
	_removeRemotes()
	if _lan != null:
		_lan.stopBeacon()
	if _upnp != null:
		_upnp.stop()
		upnp = {"state": "off", "externalIp": ""}
	_detachPeer()
	active = false
	inGame = false
	isHost = false
	isClient = false
	authority = true
	localId = 1
	sender = 1
	peers.clear()
	lobby = {}
	startInfo = {}
	_phase = ""
	_welcomed = false
	_countdownT = -1.0
	_startPending = false
	_queue.clear()
	_pending.clear()
	_rejecting.clear()
	_auto = {}
	_ext.clear()
	_plistFrame = -1
	_restoreParams()
	if game.get("mpPaused") == true:
		game.set("mpPaused", false)
	if wasGame and game.state != "menu":
		if game.input != null and game.input.has_method("exitLock"):
			game.input.exitLock()
		game.setState("menu")
	_status(st, reason)

func _autoJoin() -> void:
	_autoJoinT = -1.0
	var ip := str(_auto.get("ip", "127.0.0.1"))
	if ip == "lan":
		if lan.is_empty():
			_autoJoinT = 0.5   # keep listening
			return
		var g0: Dictionary = lan[0]
		join(str(g0.ip), int(g0.port), {"name": _auto.get("name"), "hero": _auto.get("hero")})
		return
	join(ip, port, {"name": _auto.get("name"), "hero": _auto.get("hero")})

# ------------------------------------------------------------------------------------------------ lobby (host side)
func net_hello(info) -> void:
	if not isHost:
		return
	var id := sender
	if peers.has(id) or not _pending.has(id):
		return
	_pending.erase(id)
	if not (info is Dictionary) or str(info.get("version", "")) != version:
		_reject(id, "version")
		return
	if _phase != "lobby":
		_reject(id, "started")
		return
	if peers.size() >= maxPlayers:
		_reject(id, "full")
		return
	var slot := _freeSlot()
	var p := _newPeer(id, _cleanName(info.get("name"), "PLAYER %d" % (slot + 1)), _pickHero(info.get("hero"), id), slot)
	peers[id] = p
	_refreshLobby()
	toPeer(id, "net", "welcome", [{"id": id, "lobby": lobby}])
	toAll("net", "lobby", [lobby])
	_emit("net:peer", {"id": id, "joined": true})
	_emit("net:lobby", {"lobby": lobby})

func _reject(id: int, reason: String) -> void:
	_sendTo(id, "net", "reject", [{"reason": reason}])
	if peer != null:
		var pp: ENetPacketPeer = peer.get_peer(id)
		if pp != null:
			pp.peer_disconnect_later()
	_rejecting[id] = _now() + REJECT_GRACE

func net_bye(reason = "") -> void:
	if isHost:
		if sender != localId and peers.has(sender):
			_dropPeer(sender)
	elif isClient and sender == 1:
		_byeReason = str(reason) if reason is String and reason != "" else "host_left"
		_endSession("lost", _byeReason)

func net_setHero(heroId) -> void:
	if not isHost or not peers.has(sender) or _phase != "lobby":
		return
	var ok: bool = _heroIds.has(heroId)
	if ok:
		for id in peers:
			if id != sender and peers[id].hero == heroId:
				ok = false
	if not ok:
		toPeer(sender, "net", "heroDenied", [heroId])
		return
	peers[sender].hero = heroId
	peers[sender].color = HERO_COLORS.get(heroId, "#FFFFFF")
	_lobbyChanged()

func net_ready(on) -> void:
	if not isHost or not peers.has(sender) or _phase != "lobby":
		return
	var p = peers[sender]
	var want: bool = on == true
	if want and not p.loaded:
		return
	if p.ready != want:
		p.ready = want
		_lobbyChanged()

func net_loaded() -> void:
	if not isHost or not peers.has(sender):
		return
	if not peers[sender].loaded:
		peers[sender].loaded = true
		_lobbyChanged()

func net_name(n) -> void:
	if not isHost or not peers.has(sender):
		return
	peers[sender].name = _cleanName(n, peers[sender].name)
	_lobbyChanged()

func _lobbyChanged() -> void:
	_refreshLobby()
	toAll("net", "lobby", [lobby])
	_emit("net:lobby", {"lobby": lobby})

func _refreshLobby() -> void:
	var list: Array = []
	for id in peers:
		var p: Dictionary = peers[id]
		list.append({"id": id, "name": p.name, "hero": p.hero, "ready": p.ready, "loaded": p.loaded, "color": p.color,
			"ping": p.ping, "slot": p.slot})
	list.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	lobby = {"phase": _phase, "players": list, "seed": _seed, "max": maxPlayers, "version": version,
		"host": str(peers[1].name) if peers.has(1) else "", "countdown": maxf(0.0, _countdownT) if _phase == "starting" else 0.0}

func _freeSlot() -> int:
	for s in maxPlayers:
		var used := false
		for id in peers:
			if int(peers[id].slot) == s:
				used = true
		if not used:
			return s
	return peers.size()

func _newPeer(id: int, name: String, hero, slot: int) -> Dictionary:
	return {"id": id, "name": name, "hero": hero, "ready": false, "loaded": false, "color": HERO_COLORS.get(hero, "#FFFFFF"),
		"ping": 0, "slot": slot, "ext": {}, "player": null}

# The requested hero when free, else the default hero, else the first free one (heroes are unique).
func _pickHero(requested, forId: int):
	var taken := {}
	for id in peers:
		if id != forId:
			taken[peers[id].hero] = true
	if _heroIds.has(requested) and not taken.has(requested):
		return requested
	if not taken.has(_defaultHero):
		return _defaultHero
	for h in _heroIds:
		if not taken.has(h):
			return h
	return _defaultHero

static func _cleanName(n, fallback: String) -> String:
	var s := str(n).strip_edges() if n != null else ""
	s = s.replace("\n", " ").replace("\t", " ")
	if s == "" or s == "<null>":
		s = fallback
	return s.substr(0, NAME_MAX)

# ------------------------------------------------------------------------------------------------ lobby (client side)
func net_welcome(info) -> void:
	if not isClient or sender != 1 or _welcomed or not (info is Dictionary):
		return
	_welcomed = true
	if info.get("lobby") is Dictionary:
		_applyLobby(info.lobby)
	_status("connected", "")

func net_reject(info) -> void:
	if not isClient or sender != 1:
		return
	var reason := str(info.get("reason", "rejected")) if info is Dictionary else "rejected"
	_endSession("rejected", reason)

func net_lobby(l) -> void:
	if not isClient or sender != 1 or not (l is Dictionary):
		return
	_applyLobby(l)

func _applyLobby(l: Dictionary) -> void:
	var before := peers.keys()
	var seen := {}
	for e in l.get("players", []):
		if not (e is Dictionary) or not (e.get("id") is int):
			continue
		var id: int = e.id
		seen[id] = true
		var p = peers.get(id)
		if p == null:
			p = _newPeer(id, str(e.get("name", "")), e.get("hero"), int(e.get("slot", 0)))
			peers[id] = p
		for k in ["name", "hero", "ready", "loaded", "color", "ping", "slot"]:
			if e.has(k):
				p[k] = e[k]
	for id in before:
		if not seen.has(id) and id != localId:
			_removeRemote(id)
			peers.erase(id)
			_emit("net:peer", {"id": id, "joined": false})
	for id in seen:
		if not before.has(id) and id != localId:
			_emit("net:peer", {"id": id, "joined": true})
	if not inGame:
		_phase = str(l.get("phase", "lobby"))
	_seed = int(l.get("seed", 0)) if (l.get("seed") is int) else 0
	lobby = l
	_plistFrame = -1
	_emit("net:lobby", {"lobby": lobby})

func net_heroDenied(heroId) -> void:
	if sender == 1:
		_emit("net:hero", {"hero": heroId, "ok": false})

func net_pings(tab) -> void:
	if sender != 1 or not (tab is Dictionary):
		return
	for id in tab:
		if peers.has(id) and (tab[id] is int):
			peers[id].ping = tab[id]
	_emit("net:ping", {"pings": tab})

func net_peerLeft(id) -> void:
	if isClient and sender == 1 and id is int and peers.has(id) and id != localId:
		_dropPeer(id)

func net_emit(name, payload = null) -> void:
	if sender == 1 and name is String:
		game.events.emit(name, payload)

# ------------------------------------------------------------------------------------------------ ext
func setLocalExt(key: String, value) -> void:
	if value == null:
		_ext.erase(key)
	else:
		_ext[key] = value
	if active and _canSend():
		toOthers("net", "ext", [key, value])

func localExt() -> Dictionary:
	return _ext

func extOf(id: int) -> Dictionary:
	if id == localId:
		return _ext
	var p = peers.get(id)
	return p.ext if p != null else {}

func net_ext(key, value = null) -> void:
	var id := sender
	if id == localId or not peers.has(id) or not (key is String):
		return
	var e: Dictionary = peers[id].ext
	if value == null:
		e.erase(key)
	else:
		e[key] = value
	_emit("net:ext", {"id": id, "key": key, "value": value})

# ------------------------------------------------------------------------------------------------ game start / end
func net_start(info) -> void:
	if sender != 1 or not (info is Dictionary) or not active or inGame:
		return
	if not (info.get("heroes") is Dictionary) or not (info.get("slots") is Dictionary):
		return
	startInfo = info
	_seed = int(info.get("seed", 0))
	_phase = "game"
	for id in peers:
		if info.heroes.has(id):
			peers[id].hero = info.heroes[id]
			peers[id].color = HERO_COLORS.get(info.heroes[id], peers[id].color)
			peers[id].slot = int(info.slots.get(id, peers[id].slot))
		peers[id].ext = {}
	_ext.clear()
	if isHost:
		_refreshLobby()
		toAll("net", "lobby", [lobby])
	else:
		lobby["phase"] = "game"
		_applyWorldParams(info.get("params"))
	inGame = true
	_sendAcc = 0.0
	game.seed_value = _seed
	var hero = info.heroes.get(localId, peers[localId].hero if peers.has(localId) else null)
	_startHero = hero
	_startPending = true
	_startPendingT = START_TIMEOUT
	_emit("net:start", {"seed": _seed, "heroes": info.heroes, "slots": info.slots, "names": info.get("names", {}),
		"id": localId, "hero": hero})
	var m = game.get("menu")
	if m != null and m.has_method("mpStart") and m.mpStart(hero) == true:
		return
	game.newGame(hero)

# Game.newGame in MP flavour (after every system's reset, before the 'playing' state): spawn slots, remote players.
func onNewGame() -> void:
	_startPending = false
	_removeRemotes()
	_slots = _slotPoints()
	var me = peers.get(localId)
	var mySlot: int = clampi(int(me.slot) if me != null else 0, 0, _slots.size() - 1)
	var sp: Dictionary = _slots[mySlot]
	if mySlot != 0 and game.player != null:
		game.player.teleport(sp.pos.x, sp.pos.z, sp.yaw)
	if me != null:
		me.player = game.player
	var heroes: Dictionary = startInfo.get("heroes", {})
	for id in peers:
		if id == localId:
			continue
		var info: Dictionary = peers[id]
		var rp = RemotePlayerScript.new(game, id, heroes.get(id, info.hero), str(info.name), str(info.color))
		rp.ext = info.ext
		var s: Dictionary = _slots[clampi(int(info.slot), 0, _slots.size() - 1)]
		rp.teleport(s.pos.x, s.pos.z, s.yaw)
		_remotes[id] = rp
		info.player = rp
	_plistFrame = -1

func net_toLobby(_reason = "") -> void:
	if sender != 1 or not active:
		return
	var wasGame := inGame
	inGame = false
	_startPending = false
	_removeRemotes()
	_phase = "lobby"
	for id in peers:
		peers[id].ready = false
		peers[id].player = null
	if isHost:
		_lobbyChanged()
	else:
		lobby["phase"] = "lobby"
		_emit("net:lobby", {"lobby": lobby})
	if game.get("mpPaused") == true:
		game.set("mpPaused", false)
	if wasGame and game.state != "menu":
		if game.input != null and game.input.has_method("exitLock"):
			game.input.exitLock()
		game.setState("menu")

func _applyWorldParams(wp) -> void:
	if not (wp is Dictionary):
		wp = {}
	var P: Dictionary = game.params
	if _paramBackup == null:
		_paramBackup = {}
		for k in worldParams:
			_paramBackup[k] = [P.has(k), P.get(k)]
	for k in worldParams:
		if wp.has(k):
			P[k] = wp[k]
		else:
			P.erase(k)

func _restoreParams() -> void:
	if _paramBackup == null:
		return
	var P: Dictionary = game.params
	for k in _paramBackup:
		var e: Array = _paramBackup[k]
		if e[0]:
			P[k] = e[1]
		else:
			P.erase(k)
	_paramBackup = null

# Owner side of RemotePlayer.hurt / knockback while player.gd has no net_hurt / net_knockback (mp-players).
func net_hurt(dmg, fromPos = null) -> void:
	var p = game.player
	if p == null or not inGame or sender != 1 or not (dmg is float or dmg is int):
		return
	p.hurt(clampf(float(dmg), 0.0, 1000.0), fromPos if fromPos is Vector3 else null)

func net_knockback(vec) -> void:
	var p = game.player
	if p != null and inGame and sender == 1 and vec is Vector3:
		p.knockback(vec)

# Game over / results summary (RECONCILE R14/R20). Per-player numbers from economy.statsOf(id), rounds.killsBy and
# player.mp.team when those exist, else 0 (the local points from economy).
func teamSummary() -> Dictionary:
	var g = game
	var E = g.economy
	var R = g.rounds
	var mpObj = g.player.get("mp") if g.player != null else null
	var team = mpObj.get("team") if mpObj is Object else null
	var killsBy = R.get("killsBy") if R != null else null
	var ids: Array = peers.keys() if active else [localId]
	var list: Array = []
	for id in ids:
		var p: Dictionary = peers.get(id, {})
		var st = E.statsOf(id) if E != null and E.has_method("statsOf") else null
		var pts = st.get("points") if st is Dictionary else null
		if pts == null:
			pts = E.points if (id == localId and E != null) else p.get("points", 0)
		var kills = st.get("kills") if st is Dictionary else null
		if kills == null:
			kills = killsBy.get(id, 0) if killsBy is Dictionary else p.get("kills", 0)
		var t = team.get(id) if team is Dictionary else null
		var hero = p.get("hero", g.heroId if id == localId else null)
		list.append({"id": id, "name": str(p.get("name", "")), "hero": hero, "color": p.get("color", HERO_COLORS.get(hero, "#FFFFFF")),
			"slot": int(p.get("slot", 0)), "kills": int(kills) if (kills is int or kills is float) else 0,
			"points": int(pts) if (pts is int or pts is float) else 0,
			"downs": int(t.get("downs", 0)) if t is Dictionary else 0, "revives": int(t.get("revives", 0)) if t is Dictionary else 0})
	list.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	return {"round": R.round if R != null else 0, "kills": R.totalKills if R != null else 0,
		"points": E.points if E != null else 0, "players": list}

# ------------------------------------------------------------------------------------------------ spawn slots
func spawnPoint(slot: int) -> Dictionary:
	if _slots.is_empty():
		_slots = _slotPoints()
	return _slots[clampi(slot, 0, _slots.size() - 1)]

# Slot 0 = the local player's reset spawn (player_spawn, or the area= world param: the same on every peer); slots
# 1-3 1.4 m to its right / left / behind, moved to the nearest free walkable spot (0.9 m apart). No RNG.
func _slotPoints() -> Array:
	var p = game.player
	var base: Vector3 = p.pos if p != null else Vector3.ZERO
	var yaw: float = float(p.yaw) if p != null else 0.0
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var col = game.level.get("col") if game.level != null else null
	var out: Array = []
	for i in SLOT_OFFSETS.size():
		var o: Vector2 = SLOT_OFFSETS[i]
		var want := base + right * o.x - fwd * o.y
		var q := _freeSpot(want.x, want.z, out) if i > 0 else Vector2(base.x, base.z)
		var y := base.y
		if col != null:
			var f: float = col.floorAt(q.x, q.y, 50.0)
			if f > -INF:
				y = f
		out.append({"pos": Vector3(q.x, y, q.y), "yaw": yaw})
	return out

func _freeSpot(x: float, z: float, taken: Array) -> Vector2:
	var nav = game.nav
	for ri in 17:
		var r := ri * 0.5
		var n := 1 if r == 0.0 else int(ceilf((2.0 * PI * r) / 0.5))
		for i in n:
			var a := (float(i) / n) * PI * 2.0
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if nav != null and not nav.walkable(px, pz):
				continue
			var ok := true
			for t in taken:
				if Vector2(px - t.pos.x, pz - t.pos.z).length() < 0.9:
					ok = false
					break
			if ok:
				return Vector2(px, pz)
	return Vector2(x, z)

# ------------------------------------------------------------------------------------------------ players
func players() -> Array:
	if _plistFrame != int(game.time.frame):
		_rebuildLists()
	return _plist

func targets() -> Array:
	if _plistFrame != int(game.time.frame):
		_rebuildLists()
	return _tlist

func remotes() -> Array:
	return _remotes.values()

func _rebuildLists() -> void:
	var pl: Array = []
	var tl: Array = []
	if game.player != null:
		pl.append(game.player)
	if not _remotes.is_empty():
		var ids := _remotes.keys()
		ids.sort_custom(func(a, b): return slotOf(a) < slotOf(b))
		for id in ids:
			pl.append(_remotes[id])
	for p in pl:
		if isTargetable(p):
			tl.append(p)
	_plist = pl
	_tlist = tl
	_plistFrame = int(game.time.frame)

# Zombies may target it (RECONCILE R6): alive, not downed, not off-air, not hidden, not in a commercial.
# Invulnerable players (grace, god) stay targetable.
func isTargetable(p) -> bool:
	if p == null or not p.alive or p.downed:
		return false
	if p.get("offAir") == true or p.get("hidden") == true:
		return false
	if p.get("isRemote") == true:
		return not p.inCommercial
	return not RemotePlayerScript._inCommercialLocal(game, p)

func playerById(id: int):
	if id == localId:
		return game.player
	return _remotes.get(id)

func idOf(p) -> int:
	if p == null:
		return 0
	if p == game.player:
		return localId
	var id = p.get("peerId")
	return int(id) if id is int else 0

func nameOf(id: int) -> String:
	var p = peers.get(id)
	return str(p.name) if p != null else ""

func slotOf(id: int) -> int:
	var p = peers.get(id)
	return int(p.slot) if p != null else 0

func colorOf(id: int) -> String:
	var p = peers.get(id)
	if p != null:
		return str(p.color)
	return HERO_COLORS.get(game.heroId, "#FFFFFF") if id == localId else "#FFFFFF"

func isLocal(p) -> bool:
	return p != null and p == game.player

# The player the local camera follows: the spectated teammate (mp-players sets game.player.spectate while off-air).
func viewPlayer():
	var p = game.player
	if p != null:
		var s = p.get("spectate")
		if s != null and s is Object and is_instance_valid(s):
			return s
	return p

func nearestPlayer(pos: Vector3, onlyTargets := true):
	var list := targets() if onlyTargets else players()
	var best = null
	var bd := INF
	for p in list:
		var d: float = (p.pos as Vector3).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best

func _removeRemote(id: int) -> void:
	var rp = _remotes.get(id)
	if rp != null:
		rp.free_()
		_remotes.erase(id)
	if peers.has(id):
		peers[id].player = null
	_plistFrame = -1

func _removeRemotes() -> void:
	for id in _remotes.keys():
		_removeRemote(id)

func net_stream_p(from: int, data) -> void:
	if not inGame or not (data is PackedByteArray):
		return
	var rp = _remotes.get(from)
	if rp != null:
		rp.pushState(data, _now())

# ------------------------------------------------------------------------------------------------ helpers
func _status(st: String, reason: String) -> void:
	status = st
	_emit("net:status", {"status": st, "reason": reason})

func _emit(name: String, payload) -> void:
	if game.events != null:
		game.events.emit(name, payload)

func _warnOnce(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)

static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0

static func _num(v, d: float) -> float:
	return float(v) if (v is int or v is float) else d

static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != "" and v != "0" and v != "false"
	return true

# Compact state for QA logs.
func debugState() -> Dictionary:
	var ps := {}
	for id in peers:
		var p: Dictionary = peers[id]
		ps[id] = {"name": p.name, "hero": p.hero, "ready": p.ready, "loaded": p.loaded, "ping": p.ping, "slot": p.slot}
	return {"active": active, "inGame": inGame, "isHost": isHost, "localId": localId, "phase": _phase, "status": status,
		"peers": ps, "remotes": _remotes.size(), "bw": bandwidth}
