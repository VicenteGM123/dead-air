# Net signaling (the WebRTC transport's matchmaker, scripts/net/net_rtc.gd): short JSON messages between a room host
# and the peers that want to join it, carried by FREE PUBLIC services reachable from a browser over WebSocket, with no
# account and no server of our own. Used only while connections are being set up (offer / answer / ICE candidates);
# game traffic never goes through it.
# Backends (one hub runs several at once; a message is answered on the backend it came from):
#   peerjs   the PeerJS signaling protocol (github.com/peers/peerjs-server; public cloud wss://0.peerjs.com/, key
#            'peerjs'). Every endpoint registers an id (`<base>peerjs?key=peerjs&id=<id>&token=<random>`); the server
#            answers {type: OPEN} (or ID-TAKEN / ERROR), relays {type: OFFER | ANSWER | CANDIDATE | LEAVE, dst, payload}
#            adding `src`, and answers {type: EXPIRE, src: <dst>} when the destination id is not connected (= the room
#            does not exist). Clients send {type: HEARTBEAT} every 5 s.
#   mqtt     MQTT 3.1.1 over WebSocket (subprotocol 'mqtt'; public brokers such as wss://broker.hivemq.com:8884/mqtt or
#            wss://test.mosquitto.org:8081/mqtt). Every endpoint subscribes to the topic `deadair-rtc/<id>` (QoS 0) and
#            publishes {type, src, payload} JSON to `deadair-rtc/<dst>`. No EXPIRE: a missing room is a timeout.
# Configuration: a comma list of "<kind>:<url>" (kind peerjs | mqtt), from the launch param mpsignal= or the project
# setting dead_air/net/signal_servers (DEFAULT_SERVERS when unset).
# API: start(myId) · poll(now) -> Array [{b (backend index), type, src, payload}] (+ {b, type: '_open' | '_down'} state
#   notes) · send(b, dst, type, payload) · stateOf(b) / anyOpen() / allFailed() · close() · kinds() · retry(now).
#   Backend states: 'connecting' | 'open' | 'failed' (unreachable / refused) | 'taken' (peerjs: id in use) | 'closed'.
extends RefCounted

const DEFAULT_SERVERS := "peerjs:wss://0.peerjs.com/,mqtt:wss://broker.hivemq.com:8884/mqtt"
const SETTING := "dead_air/net/signal_servers"
const RETRY_EVERY := 6.0

var backends: Array = []
var myId := ""

static func configured(params: Dictionary) -> Array:
	var s := ""
	if params.get("mpsignal") != null and str(params.mpsignal) != "":
		s = str(params.mpsignal)
	else:
		s = str(ProjectSettings.get_setting(SETTING, DEFAULT_SERVERS))
	if s.strip_edges() == "":
		s = DEFAULT_SERVERS
	var out: Array = []
	for raw in s.split(",", false):
		var e := raw.strip_edges()
		var i := e.find(":")
		if i <= 0:
			continue
		var kind := e.substr(0, i).to_lower()
		var url := e.substr(i + 1)
		if kind in ["peerjs", "mqtt"] and (url.begins_with("ws://") or url.begins_with("wss://")):
			out.append({"kind": kind, "url": url})
	return out

func _init(list: Array) -> void:
	for e in list:
		if e.kind == "peerjs":
			backends.append(PeerJs.new(str(e.url)))
		elif e.kind == "mqtt":
			backends.append(Mqtt.new(str(e.url)))

func start(id: String) -> void:
	myId = id
	for b in backends:
		b.start(id)

func kinds() -> String:
	var k: Array = []
	for b in backends:
		k.append(b.kind)
	return ",".join(k)

func poll(now: float) -> Array:
	var out: Array = []
	for i in backends.size():
		var b = backends[i]
		var was: String = b.state
		for msg in b.poll(now):
			msg.b = i
			out.append(msg)
		if b.state != was:
			print("[net] signal %s %s -> %s" % [b.kind, was, b.state])   # (browser console / stdout: diagnosis)
			out.append({"b": i, "type": "_open" if b.state == "open" else "_down", "state": b.state})
	return out

# Failed / dropped backends try again (the host keeps its room reachable while the lobby is open).
func retry(now: float) -> void:
	for b in backends:
		if (b.state == "failed" or b.state == "closed") and now - b.t0 > RETRY_EVERY:
			b.start(myId)

func send(b: int, dst: String, type: String, payload) -> bool:
	if b < 0 or b >= backends.size():
		return false
	return backends[b].send(dst, type, payload)

func stateOf(b: int) -> String:
	return backends[b].state if b >= 0 and b < backends.size() else "failed"

func anyOpen() -> bool:
	for b in backends:
		if b.state == "open":
			return true
	return false

func allFailed() -> bool:
	for b in backends:
		if b.state == "open" or b.state == "connecting":
			return false
	return true

func close() -> void:
	for b in backends:
		b.close()

# ------------------------------------------------------------------------------------------------ PeerJS
class PeerJs:
	extends RefCounted
	var kind := "peerjs"
	var polls := 0                 # polls since start(): a timeout needs wall time AND frames (a loading stall is not one)
	var _openAt := -1.0
	const TIMEOUT := 9.0

	static func _tok(n: int) -> String:
		var a := "abcdefghijklmnopqrstuvwxyz0123456789"
		var s := ""
		for i in n:
			s += a[randi() % a.length()]
		return s

	var url := ""
	var ws: WebSocketPeer = null
	var state := "closed"
	var t0 := -INF
	var _hb := 0.0
	var _id := ""
	var _token := ""

	func _init(u: String) -> void:
		url = u

	func start(id: String) -> void:
		close()
		if id != _id or _token == "":
			_token = _tok(16)   # the same token on a reconnect: the server re-attaches our id instead of ID-TAKEN
		_id = id
		polls = 0
		_openAt = -1.0
		var u := url
		if u.ends_with("/"):
			u += "peerjs?key=peerjs"
		elif not u.contains("?"):
			u += "?key=peerjs"
		u += "&id=%s&token=%s&version=1.5.4" % [id.uri_encode(), _token]
		ws = WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 18
		ws.outbound_buffer_size = 1 << 18
		t0 = Time.get_ticks_msec() / 1000.0
		state = "connecting" if ws.connect_to_url(u) == OK else "failed"

	func poll(now: float) -> Array:
		var out: Array = []
		if ws == null:
			return out
		polls += 1
		ws.poll()
		var rs := ws.get_ready_state()
		if rs == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var txt := ws.get_packet().get_string_from_utf8()
				var m = JSON.parse_string(txt)
				if not (m is Dictionary):
					continue
				var ty := str(m.get("type", ""))
				if ty == "OPEN":
					state = "open"
					_hb = now
				elif ty == "ID-TAKEN":
					state = "taken"
				elif ty == "ERROR":
					state = "failed"
				elif ty in ["OFFER", "ANSWER", "CANDIDATE", "LEAVE", "EXPIRE"]:
					out.append({"type": ty, "src": str(m.get("src", "")), "payload": m.get("payload")})
			if state == "open" and now - _hb > 5.0:
				_hb = now
				ws.send_text('{"type":"HEARTBEAT"}')
			elif state == "connecting" and _openAt < 0.0:
				_openAt = now
			elif state == "connecting" and now - _openAt > 3.0 and polls > 30:
				state = "open"   # a reconnect with our token: the server re-attaches the id without an OPEN
				_hb = now
			elif state == "taken" or state == "failed":
				ws.close()
		elif rs == WebSocketPeer.STATE_CLOSED:
			if state == "connecting" or state == "open":
				state = "failed" if state == "connecting" else "closed"
			ws = null
		elif state == "connecting" and now - t0 > TIMEOUT and polls > 30:
			_fail()
		return out

	func _fail() -> void:
		state = "failed"
		if ws != null:
			ws.close()
			ws = null

	func send(dst: String, type: String, payload) -> bool:
		if ws == null or state != "open":
			return false
		return ws.send_text(JSON.stringify({"type": type, "dst": dst, "payload": payload})) == OK

	func close() -> void:
		if ws != null:
			if state == "open":
				ws.send_text('{"type":"LEAVE"}')
			ws.close()
		ws = null
		state = "closed"

# ------------------------------------------------------------------------------------------------ MQTT over WebSocket
class Mqtt:
	extends RefCounted
	var kind := "mqtt"
	var polls := 0
	const TIMEOUT := 9.0

	static func _tok(n: int) -> String:
		var a := "abcdefghijklmnopqrstuvwxyz0123456789"
		var s := ""
		for i in n:
			s += a[randi() % a.length()]
		return s

	var url := ""
	var ws: WebSocketPeer = null
	var state := "closed"
	var t0 := -INF
	var _id := ""
	var _sent := false
	var _ping := 0.0
	var _rx := PackedByteArray()
	const PREFIX := "deadair-rtc/"
	const KEEPALIVE := 30

	func _init(u: String) -> void:
		url = u

	func start(id: String) -> void:
		close()
		_id = id
		polls = 0
		_sent = false
		_rx = PackedByteArray()
		ws = WebSocketPeer.new()
		ws.supported_protocols = PackedStringArray(["mqtt"])
		ws.inbound_buffer_size = 1 << 18
		ws.outbound_buffer_size = 1 << 18
		t0 = Time.get_ticks_msec() / 1000.0
		state = "connecting" if ws.connect_to_url(url) == OK else "failed"

	func poll(now: float) -> Array:
		var out: Array = []
		if ws == null:
			return out
		polls += 1
		ws.poll()
		var rs := ws.get_ready_state()
		if rs == WebSocketPeer.STATE_OPEN:
			if not _sent:
				_sent = true
				# CONNECT: protocol "MQTT" level 4, clean session, keep-alive; client id = our id + a random tail
				var vh := _str("MQTT")
				vh.append_array(PackedByteArray([4, 0x02, KEEPALIVE >> 8, KEEPALIVE & 0xFF]))
				vh.append_array(_str(_id.substr(0, 40) + "-" + _tok(6)))
				_write(0x10, vh)
			while ws.get_available_packet_count() > 0:
				_rx.append_array(ws.get_packet())
			_parse(out, now)
			if state == "open" and now - _ping > KEEPALIVE * 0.5:
				_ping = now
				ws.send(PackedByteArray([0xC0, 0]), WebSocketPeer.WRITE_MODE_BINARY)
			elif state == "connecting" and now - t0 > TIMEOUT and polls > 30:
				_fail()
		elif rs == WebSocketPeer.STATE_CLOSED:
			if state == "connecting" or state == "open":
				state = "failed" if state == "connecting" else "closed"
			ws = null
		elif state == "connecting" and now - t0 > TIMEOUT and polls > 30:
			_fail()
		return out

	func _parse(out: Array, now: float) -> void:
		while _rx.size() >= 2:
			var mul := 1
			var rl := 0
			var i := 1
			var done := false
			while i < _rx.size() and i <= 4:
				var c := _rx[i]
				rl += (c & 0x7F) * mul
				mul *= 128
				i += 1
				if (c & 0x80) == 0:
					done = true
					break
			if not done:
				return
			if _rx.size() < i + rl:
				return
			var head := _rx[0]
			var body := _rx.slice(i, i + rl)
			_rx = _rx.slice(i + rl)
			var ty := head >> 4
			if ty == 2:      # CONNACK
				if body.size() >= 2 and body[1] == 0:
					# SUBSCRIBE (packet id 1) to our inbox, QoS 0
					var p := PackedByteArray([0, 1])
					p.append_array(_str(PREFIX + _id))
					p.append(0)
					_write(0x82, p)
				else:
					_fail()
					return
			elif ty == 9:    # SUBACK
				state = "open"
				_ping = now
			elif ty == 3:    # PUBLISH (QoS 0 expected; skip a packet id for QoS > 0)
				if body.size() < 2:
					continue
				var tl := (body[0] << 8) | body[1]
				var o := 2 + tl
				if ((head >> 1) & 3) > 0:
					o += 2
				if o > body.size():
					continue
				var m = JSON.parse_string(body.slice(o).get_string_from_utf8())
				if m is Dictionary and str(m.get("type", "")) in ["OFFER", "ANSWER", "CANDIDATE", "LEAVE"]:
					out.append({"type": str(m.type), "src": str(m.get("src", "")), "payload": m.get("payload")})

	func send(dst: String, type: String, payload) -> bool:
		if ws == null or state != "open":
			return false
		var p := _str(PREFIX + dst)
		p.append_array(JSON.stringify({"type": type, "src": _id, "payload": payload}).to_utf8_buffer())
		return _write(0x30, p) == OK

	func _write(head: int, body: PackedByteArray) -> int:
		var pkt := PackedByteArray([head])
		var n := body.size()
		while true:
			var d := n % 128
			n = n / 128
			if n > 0:
				d |= 0x80
			pkt.append(d)
			if n == 0:
				break
		pkt.append_array(body)
		return ws.send(pkt, WebSocketPeer.WRITE_MODE_BINARY)

	static func _str(s: String) -> PackedByteArray:
		var b := s.to_utf8_buffer()
		var out := PackedByteArray([b.size() >> 8, b.size() & 0xFF])
		out.append_array(b)
		return out

	func _fail() -> void:
		state = "failed"
		if ws != null:
			ws.close()
			ws = null

	func close() -> void:
		if ws != null:
			if state == "open":
				ws.send(PackedByteArray([0xE0, 0]), WebSocketPeer.WRITE_MODE_BINARY)   # DISCONNECT
			ws.close()
		ws = null
		state = "closed"
