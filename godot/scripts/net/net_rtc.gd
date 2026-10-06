# Net RTC: the WebRTC transport of game.net (scripts/net/net.gd) — online co-op with a ROOM CODE, in the browser build
# and on desktop (Windows / Linux through the official webrtc-native GDExtension in addons/webrtc/), with no account and
# no server of our own. net.host({transport: 'rtc'}) / net.join(code, 0, {transport: 'rtc'}) pick it; ENet (IP / LAN)
# stays the desktop's other transport. Everything above the transport (handshake hello / welcome, lobby, messages,
# streams, the host relay, the game) is the same code for both: this file only builds the WebRTCMultiplayerPeer that
# net.gd attaches to SceneMultiplayer.
# Topology: a star, exactly like ENet: every client has ONE WebRTC connection, to the host (peer id 1); the host relays
# (net.gd's explicit relay). Channels: SceneMultiplayer channel 0 = WebRTC's reliable ordered channel (messages);
# channel 1 (streams) = an unreliable ORDERED data channel (no retransmission, maxPacketLifeTime 1 ms; ordered so a stale
# snapshot is never delivered after a newer one — the stream decoders were written for ENet's unreliable_ordered);
# channel 2 (pings) = unreliable unordered.
# Room code: 8 characters of an unambiguous alphabet (no I L O 0 1), shown "WZTV-4K2P"; the host's signaling id is
# "deadair-<CODE>". Signaling (net_signal.gd: PeerJS public cloud + an MQTT-over-WebSocket broker as fallback, both at
# once) is only used during connection setup:
#   client -> host  OFFER   {da: 'join', v: protocol version, cid: client id}
#   host -> client  ANSWER  {da: 'no', reason: 'version' | 'full' | 'started'}            (refused before any WebRTC)
#                   OFFER   {da: 'sdp', id: <assigned peer id>, type: 'offer', sdp}        (the host is the offerer)
#   client -> host  ANSWER  {da: 'sdp', type: 'answer', sdp, cid}
#   both ways       CANDIDATE {da: 'ice', m: media, i: index, n: candidate, cid?}           (trickle ICE)
#   PeerJS EXPIRE from the room id = no such room ('notfound'); no answer within FIND_TIMEOUT = 'notfound' too.
# ICE: STUN (Google) + an optional no-account public TURN relay (ICE_DEFAULT; launch param mpice=none | stun | default,
# or the project setting dead_air/net/ice_servers as a JSON array). Without a TURN relay that works, two players both
# behind strict (symmetric) NATs cannot connect ('ice').
# Failure reasons reported to net (net:status failed / rejected): 'signal' (no signaling service reachable),
# 'notfound', 'ice' (the WebRTC connection could not be made / timed out), 'version' | 'full' | 'started' (refused),
# 'nortc' (WebRTC unavailable: desktop build without the extension).
# Host room state (net.room {code, state, reason}): 'opening' (registering) -> 'open' | 'failed' (no service reachable:
# it keeps retrying) ; the code changes if PeerJS says it is taken (net:room again).
extends RefCounted

const SignalScript = preload("res://scripts/net/net_signal.gd")

const ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LEN := 8
const ID_PREFIX := "deadair-"
const ICE_SETTING := "dead_air/net/ice_servers"
const ICE_STUN := [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun2.l.google.com:19302",
	"stun:stun3.l.google.com:19302", "stun:stun4.l.google.com:19302"]}]
# Metered "Open Relay" (openrelay.metered.ca, published free credentials). Best effort: if it is gone, ICE simply
# finds no relay candidate.
const ICE_TURN := [{"urls": ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"],
	"username": "openrelayproject", "credential": "openrelayproject"}]
const CHANNELS := [MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE]
const FIND_TIMEOUT := 12.0      # client: the room never answered
const SIGNAL_TIMEOUT := 10.0    # client: no signaling service could be reached
const ICE_TIMEOUT := 25.0       # WebRTC connection not up after the offer
const PENDING_TIMEOUT := 40.0   # host: a joining peer never connected
const SIGNAL_LINGER := 2.0      # client: signaling stays open this long after the connection is up

var net
var role := ""                  # host | client
var code := ""
var mp: WebRTCMultiplayerPeer = null
var sig = null
var roomState := "off"          # host: opening | open | failed
var _ice: Array = []
# host
var _joins := {}                # cid -> {id, conn, t, b, src, up}
# client
var _cid := ""
var _host := {}                 # {b, src} once the host answered
var _conn: WebRTCPeerConnection = null
var _cands: Array = []          # candidates received before the offer
var _asked := {}                # backend index -> true (join sent)
var _expired := {}              # backend index -> true (PeerJS EXPIRE: no such id there)
var _t0 := 0.0
var _frames := 0                # polls since _t0: a timeout needs wall time AND frames (a long loading frame is not one)
var _phase := ""                # client: finding | connecting | up | done
var _upT := 0.0

func _init(n) -> void:
	net = n
	_ice = iceServers(n.game.params)

# WebRTC usable here: the browser build always; desktop only with the webrtc-native extension loaded.
static func available() -> bool:
	return OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")

static func newCode() -> String:
	var s := ""
	for i in CODE_LEN:
		s += ALPHABET[randi() % ALPHABET.length()]
	return s

# Uppercase, only alphabet characters (dashes / spaces dropped), at most CODE_LEN.
static func normalizeCode(s) -> String:
	var out := ""
	for ch in str(s).to_upper():
		if ALPHABET.contains(ch):
			out += ch
	return out.substr(0, CODE_LEN)

static func formatCode(c: String) -> String:
	return c.substr(0, 4) + "-" + c.substr(4) if c.length() > 4 else c

static func iceServers(params: Dictionary) -> Array:
	var p = params.get("mpice")
	if p != null:
		var ps := str(p)
		if ps == "none" or ps == "0":
			return []
		if ps == "stun":
			return ICE_STUN.duplicate(true)
	var s = ProjectSettings.get_setting(ICE_SETTING, "")
	if s is String and s != "":
		var j = JSON.parse_string(s)
		if j is Array:
			return j
	if params.get("mpturn") != null and str(params.mpturn) == "0":
		return ICE_STUN.duplicate(true)
	return ICE_STUN.duplicate(true) + ICE_TURN.duplicate(true)

func _newSig():
	return SignalScript.new(SignalScript.configured(net.game.params))

func _newConn() -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	var cfg := {"iceServers": _ice}
	if c.initialize(cfg) != OK:
		return null
	return c

# ------------------------------------------------------------------------------------------------ host
# Creates the server peer (id 1) and opens the room on every signaling backend. Returns null if WebRTC is missing.
func host(c: String = "") -> WebRTCMultiplayerPeer:
	if not available():
		return null
	role = "host"
	code = normalizeCode(c)
	if code.length() != CODE_LEN:
		code = newCode()
	mp = WebRTCMultiplayerPeer.new()
	if mp.create_server(CHANNELS) != OK:
		mp = null
		return null
	sig = _newSig()
	if sig.backends.is_empty():
		push_warning("[net] no valid signaling server configured")
	sig.start(ID_PREFIX + code)
	roomState = "opening"
	return mp

func _hostPoll(now: float) -> void:
	for m in sig.poll(now):
		var ty: String = m.type
		if ty == "_open" or ty == "_down":
			continue
		var pl = m.payload
		if not (pl is Dictionary):
			continue
		var da := str(pl.get("da", ""))
		var cid := str(pl.get("cid", m.src))
		if ty == "OFFER" and da == "join":
			_onJoin(int(m.b), str(m.src), cid, pl)
		elif ty == "ANSWER" and da == "sdp" and _joins.has(cid):
			var J: Dictionary = _joins[cid]
			if J.conn != null and str(pl.get("sdp", "")) != "":
				J.conn.set_remote_description("answer", str(pl.sdp))
		elif ty == "CANDIDATE" and da == "ice" and _joins.has(cid):
			var J2: Dictionary = _joins[cid]
			if J2.conn != null:
				J2.conn.add_ice_candidate(str(pl.get("m", "")), int(pl.get("i", 0)), str(pl.get("n", "")))
		elif ty == "LEAVE" and _joins.has(cid) and not _joins[cid].up:
			_dropJoin(cid)
	# room state: open on any backend; taken (PeerJS) -> a new code; all down -> failed (keeps retrying)
	var st := roomState
	var taken := false
	for b in sig.backends:
		if b.state == "taken":
			taken = true
	if taken and _joins.is_empty():
		sig.close()
		code = newCode()
		sig = _newSig()
		sig.start(ID_PREFIX + code)
		st = "opening"
	elif sig.anyOpen():
		st = "open"
	elif sig.allFailed():
		st = "failed"
		sig.retry(now)
	if st != roomState or taken:
		roomState = st
		net._rtcRoom(code, roomState, "signal" if roomState == "failed" else "")
	# pending joins: connected -> done; failed / timed out -> removed
	for cid in _joins.keys():
		var J: Dictionary = _joins[cid]
		if J.up:
			continue
		var info = mp.get_peer(J.id) if mp.has_peer(J.id) else null
		if info is Dictionary and info.get("connected") == true:
			J.up = true
			continue
		var cs: int = J.conn.get_connection_state() if J.conn != null else WebRTCPeerConnection.STATE_FAILED
		if cs == WebRTCPeerConnection.STATE_FAILED or cs == WebRTCPeerConnection.STATE_CLOSED or now - float(J.t) > PENDING_TIMEOUT:
			_dropJoin(cid)

func _onJoin(b: int, src: String, cid: String, pl: Dictionary) -> void:
	if _joins.has(cid):
		return   # the same client asking on another backend (or again): the first one is being served
	var reason := ""
	if str(pl.get("v", "")) != str(net.version):
		reason = "version"
	elif net._phase != "lobby":
		reason = "started"
	else:
		var pend := 0
		for k in _joins:
			if not _joins[k].up:
				pend += 1
		if net.peers.size() + pend >= net.maxPlayers:
			reason = "full"
	if reason != "":
		sig.send(b, src, "ANSWER", {"da": "no", "reason": reason})
		return
	var id := 0
	while id <= 1 or mp.has_peer(id) or net.peers.has(id):
		id = randi_range(2, 0x7FFFFFFF)
	var conn := _newConn()
	if conn == null:
		sig.send(b, src, "ANSWER", {"da": "no", "reason": "ice"})
		return
	var J := {"id": id, "conn": conn, "t": _now(), "b": b, "src": src, "up": false}
	_joins[cid] = J
	conn.session_description_created.connect(_onHostDesc.bind(cid))
	conn.ice_candidate_created.connect(_onHostCand.bind(cid))
	if mp.add_peer(conn, id) != OK:
		_joins.erase(cid)
		sig.send(b, src, "ANSWER", {"da": "no", "reason": "ice"})
		return
	conn.create_offer()

# (bound method Callables: no reference cycle between a connection and its handlers)
func _onHostDesc(type: String, sdp: String, cid: String) -> void:
	var J = _joins.get(cid)
	if J == null or sig == null:
		return
	sig.send(int(J.b), str(J.src), "OFFER", {"da": "sdp", "id": int(J.id), "type": type, "sdp": sdp})
	J.conn.set_local_description(type, sdp)

func _onHostCand(media: String, index: int, cname: String, cid: String) -> void:
	var J = _joins.get(cid)
	if J != null and sig != null:
		sig.send(int(J.b), str(J.src), "CANDIDATE", {"da": "ice", "m": media, "i": index, "n": cname})

func _dropJoin(cid: String) -> void:
	var J: Dictionary = _joins[cid]
	_joins.erase(cid)
	if mp != null and mp.has_peer(J.id):
		mp.remove_peer(J.id)
	elif J.conn != null:
		J.conn.close()

# net.gd: a member left (disconnect / kick): forget its join record.
func forget(id: int) -> void:
	for cid in _joins.keys():
		if int(_joins[cid].id) == id:
			_joins.erase(cid)

# ------------------------------------------------------------------------------------------------ client
func join(c: String) -> bool:
	if not available():
		return false
	role = "client"
	code = normalizeCode(c)
	_cid = ID_PREFIX + "c" + SignalScript.PeerJs._tok(12)
	sig = _newSig()
	if sig.backends.is_empty():
		return false
	sig.start(_cid)
	_phase = "finding"
	_t0 = _now()
	_frames = 0
	return true

func _clientPoll(now: float) -> void:
	_frames += 1
	if sig != null:
		var hostId := ID_PREFIX + code
		for m in sig.poll(now):
			var ty: String = m.type
			var b: int = m.b
			if ty == "_open":
				if _phase == "finding" and not _asked.has(b):
					_asked[b] = true
					sig.send(b, hostId, "OFFER", {"da": "join", "v": str(net.version), "cid": _cid})
				continue
			if ty == "_down":
				continue
			if ty == "EXPIRE" and m.src == hostId:
				_expired[b] = true
				continue
			if m.src != hostId or not (m.payload is Dictionary):
				continue
			var pl: Dictionary = m.payload
			var da := str(pl.get("da", ""))
			if ty == "ANSWER" and da == "no" and _phase == "finding":
				_fail("rejected", str(pl.get("reason", "failed")))
				return
			if ty == "OFFER" and da == "sdp" and _phase == "finding":
				if not _connect(b, m.src, pl):
					return
			elif ty == "CANDIDATE" and da == "ice":
				if _conn != null and _host.get("b") == b:
					_conn.add_ice_candidate(str(pl.get("m", "")), int(pl.get("i", 0)), str(pl.get("n", "")))
				elif _conn == null:
					_cands.append(pl)
	match _phase:
		"finding":
			if not sig.anyOpen():
				if sig.allFailed() and (now - _t0 > 1.0 or _asked.is_empty()):
					_fail("failed", "signal" if _asked.is_empty() else "notfound")
				elif now - _t0 > SIGNAL_TIMEOUT and _frames > 60 and _asked.is_empty():
					_fail("failed", "signal")
				return
			var allExpired := not _asked.is_empty()
			for b in _asked:
				if not _expired.has(b) and sig.stateOf(b) == "open":
					allExpired = false
			if allExpired or (not _asked.is_empty() and now - _t0 > FIND_TIMEOUT and _frames > 60):
				_fail("failed", "notfound")
		"connecting":
			var cs: int = _conn.get_connection_state() if _conn != null else WebRTCPeerConnection.STATE_FAILED
			if cs == WebRTCPeerConnection.STATE_FAILED or cs == WebRTCPeerConnection.STATE_CLOSED or (now - _t0 > ICE_TIMEOUT and _frames > 60):
				_fail("failed", "ice")
			elif mp != null and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				_phase = "up"
				_upT = now
		"up":
			if now - _upT > SIGNAL_LINGER:
				_phase = "done"
				if sig != null:
					sig.close()
					sig = null

# The host's offer: our peer id is known -> the client peer + its one connection (to peer 1), attached to net.
func _connect(b: int, src: String, pl: Dictionary) -> bool:
	var id := int(pl.get("id", 0))
	if id <= 1 or str(pl.get("sdp", "")) == "":
		_fail("failed", "ice")
		return false
	_host = {"b": b, "src": src}
	mp = WebRTCMultiplayerPeer.new()
	if mp.create_client(id, CHANNELS) != OK:
		_fail("failed", "ice")
		return false
	_conn = _newConn()
	if _conn == null:
		_fail("failed", "nortc")
		return false
	_conn.session_description_created.connect(_onClientDesc)
	_conn.ice_candidate_created.connect(_onClientCand)
	mp.add_peer(_conn, 1)
	_conn.set_remote_description("offer", str(pl.sdp))
	for c in _cands:
		_conn.add_ice_candidate(str(c.get("m", "")), int(c.get("i", 0)), str(c.get("n", "")))
	_cands.clear()
	_phase = "connecting"
	_t0 = _now()
	_frames = 0
	net._rtcAttach(mp, id)
	return true

func _onClientDesc(type: String, sdp: String) -> void:
	if sig != null:
		sig.send(int(_host.b), str(_host.src), "ANSWER", {"da": "sdp", "type": type, "sdp": sdp, "cid": _cid})
	if _conn != null:
		_conn.set_local_description(type, sdp)

func _onClientCand(media: String, index: int, cname: String) -> void:
	if sig != null:
		sig.send(int(_host.b), str(_host.src), "CANDIDATE", {"da": "ice", "m": media, "i": index, "n": cname, "cid": _cid})

func _fail(st: String, reason: String) -> void:
	_phase = "done"
	if sig != null:
		sig.close()
		sig = null
	net._rtcFail(st, reason)

# ------------------------------------------------------------------------------------------------ common
func poll(now: float) -> void:
	if role == "host" and sig != null and mp != null:
		_hostPoll(now)
	elif role == "client" and _phase != "done":
		_clientPoll(now)

# Signaling only (the multiplayer peer itself is closed by net.gd with its grace period).
func close() -> void:
	if sig != null:
		sig.close()
		sig = null
	_joins.clear()
	_phase = "done"
	role = ""

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
