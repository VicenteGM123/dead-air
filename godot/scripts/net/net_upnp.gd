# UPnP port mapping for the host (MP_SPEC §3.5; owned by scripts/net/net.gd, not a Game system).
# start(port) discovers the internet gateway and maps UDP <port> -> <port> in a Thread, so the game never blocks
#   (discovery takes up to ~2 s when there is no gateway). state: 'off' | 'working' | 'ok' | 'failed';
#   externalIp ('' unless ok); error (a short reason when failed: 'unavailable' (engine built without UPnP),
#   'discover', 'gateway', 'map').
# poll() -> bool: true on the frame the thread finished (state is then 'ok' or 'failed').
# remove(): deletes the mapping in a background thread (leave); shutdown(): joins any thread and deletes the mapping
#   synchronously (exit: a mapping only exists when the gateway answered, so this is quick).
extends RefCounted

const DESC := "DEAD AIR co-op"

var state := "off"
var externalIp := ""
var error := ""
var _thread: Thread = null
var _job := ""          # 'map' | 'unmap'
var _upnp = null        # the UPNP object of a successful mapping
var _port := 0

static func available() -> bool:
	return ClassDB.class_exists("UPNP") and ClassDB.can_instantiate("UPNP")

func start(port: int) -> void:
	if _thread != null:
		return
	if not available():
		state = "failed"
		error = "unavailable"
		return
	_port = port
	state = "working"
	externalIp = ""
	error = ""
	_job = "map"
	_thread = Thread.new()
	_thread.start(_mapWork.bind(port))

# Thread body: discovery + mapping. Returns {ok, ip, err, upnp}. (Touches no member: runs off the main thread.)
func _mapWork(port: int) -> Dictionary:
	var u = ClassDB.instantiate("UPNP")
	var err: int = u.discover(2000, 2, "InternetGatewayDevice")
	if err != 0:   # UPNP.UPNP_RESULT_SUCCESS
		return {"ok": false, "err": "discover"}
	var gw = u.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		return {"ok": false, "err": "gateway"}
	var r: int = u.add_port_mapping(port, port, DESC, "UDP", 0)
	if r != 0:
		return {"ok": false, "err": "map"}
	return {"ok": true, "ip": str(u.query_external_address()), "upnp": u}

func _unmapWork(u, port: int) -> int:
	return u.delete_port_mapping(port, "UDP")

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var res = _thread.wait_to_finish()
	_thread = null
	var job := _job
	_job = ""
	if job != "map":
		return false
	if res is Dictionary and res.get("ok"):
		_upnp = res.upnp
		externalIp = str(res.get("ip", ""))
		state = "ok"
	else:
		state = "failed"
		error = str(res.get("err", "discover")) if res is Dictionary else "discover"
	return true

func remove() -> void:
	if _thread != null:
		return   # still discovering: shutdown() / the next poll() deal with it (see stop())
	if _upnp == null:
		state = "off"
		return
	var u = _upnp
	_upnp = null
	state = "off"
	externalIp = ""
	_job = "unmap"
	_thread = Thread.new()
	_thread.start(_unmapWork.bind(u, _port))

# Leave while a discovery may still run: wait for it in the background, then unmap (net.update keeps polling).
func stop() -> void:
	if _thread != null and _job == "map":
		_job = "map_then_unmap"
		return
	remove()

# Called every frame by net.update while something is pending (also finishes a deferred stop()).
func tick() -> bool:
	if _thread == null:
		return false
	if _job == "map_then_unmap":
		if _thread.is_alive():
			return false
		var res = _thread.wait_to_finish()
		_thread = null
		_job = ""
		if res is Dictionary and res.get("ok"):
			_upnp = res.upnp
			remove()
		state = "off"
		return false
	return poll()

func shutdown() -> void:
	if _thread != null:
		var res = _thread.wait_to_finish()
		_thread = null
		if _job.begins_with("map") and res is Dictionary and res.get("ok"):
			_upnp = res.upnp
		_job = ""
	if _upnp != null:
		_upnp.delete_port_mapping(_port, "UDP")
		_upnp = null
	state = "off"
