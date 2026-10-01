# LAN discovery for the net system (MP_SPEC §3.5; owned by scripts/net/net.gd, not a Game system).
# Beacon (host): a UDP broadcast every BEACON_EVERY s to 255.255.255.255:<lanPort> (and to 127.0.0.1, so games on
#   the same machine see each other) carrying JSON {g: 'deadair', v: version, n: name, p: players, m: max, port}.
# Listener (net.discover(true)): a PacketPeerUDP bound to <lanPort> (any address); every beacon updates `list`
#   (one entry per ip:port): [{ip, name, players, max, port, version, seen}] (seen = wall-clock s of the last
#   beacon); entries not heard for EXPIRE s are dropped. Beacons of another protocol version are listed too (version
#   field) so the menu can grey them out.
# API: startBeacon(port) -> bool, stopBeacon(), beacon(info) (net.update calls it, rate-limited), listen(on, port) ->
#   bool, listening, error ('' | 'bind' | 'send'), poll(now) -> bool (true when `list` changed), close().
# The sockets are non-blocking; nothing here allocates per frame unless a packet arrives.
extends RefCounted

const BEACON_EVERY := 1.0
const EXPIRE := 3.5
const MAGIC := "deadair"

var list: Array = []
var listening := false
var beaconing := false
var error := ""
var _rx: PacketPeerUDP = null
var _tx: PacketPeerUDP = null
var _txPort := 31314
var _beaconT := 0.0

func startBeacon(port: int) -> bool:
	stopBeacon()
	_tx = PacketPeerUDP.new()
	_tx.set_broadcast_enabled(true)
	_txPort = port
	beaconing = true
	_beaconT = 0.0
	return true

func stopBeacon() -> void:
	if _tx != null:
		_tx.close()
	_tx = null
	beaconing = false

# Sends the beacon when due (dt = real seconds since the last call). info: {name, players, max, version, port}.
func beacon(dt: float, info: Dictionary) -> void:
	if _tx == null:
		return
	_beaconT -= dt
	if _beaconT > 0.0:
		return
	_beaconT = BEACON_EVERY
	var pkt := JSON.stringify({"g": MAGIC, "v": info.get("version", ""), "n": info.get("name", ""), "p": info.get("players", 1),
		"m": info.get("max", 4), "port": info.get("port", 31313)}).to_utf8_buffer()
	var ok := false
	for addr in ["255.255.255.255", "127.0.0.1"]:
		if _tx.set_dest_address(addr, _txPort) == OK and _tx.put_packet(pkt) == OK:
			ok = true
	if not ok:
		error = "send"

func listen(on: bool, port: int) -> bool:
	if not on:
		if _rx != null:
			_rx.close()
		_rx = null
		listening = false
		if not list.is_empty():
			list.clear()
		return true
	if _rx != null:
		return true
	_rx = PacketPeerUDP.new()
	if _rx.bind(port, "*") != OK:
		_rx = null
		listening = false
		error = "bind"
		return false
	listening = true
	error = ""
	return true

# Reads every pending beacon and expires old entries. Returns true when the list changed (added / removed / player
# count or name changed).
func poll(now: float) -> bool:
	var changed := false
	if _rx != null:
		var guard := 0
		while _rx.get_available_packet_count() > 0 and guard < 64:
			guard += 1
			var pkt := _rx.get_packet()
			var ip := _rx.get_packet_ip()
			if pkt.size() > 1024:
				continue
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if not (d is Dictionary) or d.get("g") != MAGIC:
				continue
			var port := int(d.get("port", 31313)) if (d.get("port") is float or d.get("port") is int) else 31313
			var entry = null
			for e in list:
				if e.ip == ip and e.port == port:
					entry = e
					break
			var name := str(d.get("n", "")).substr(0, 24)
			var players := clampi(int(d.get("p", 1)) if (d.get("p") is float or d.get("p") is int) else 1, 0, 16)
			var mx := clampi(int(d.get("m", 4)) if (d.get("m") is float or d.get("m") is int) else 4, 1, 16)
			var ver := str(d.get("v", ""))
			if entry == null:
				list.append({"ip": ip, "name": name, "players": players, "max": mx, "port": port, "version": ver, "seen": now})
				changed = true
			else:
				if entry.name != name or entry.players != players or entry.max != mx or entry.version != ver:
					changed = true
				entry.name = name
				entry.players = players
				entry.max = mx
				entry.version = ver
				entry.seen = now
	for i in range(list.size() - 1, -1, -1):
		if now - float(list[i].seen) > EXPIRE:
			list.remove_at(i)
			changed = true
	return changed

func close() -> void:
	stopBeacon()
	listen(false, 0)
