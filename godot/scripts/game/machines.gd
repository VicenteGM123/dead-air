# Machines aggregator (port of src/game/machines.js; ARCHITECTURE §3/§10).
# Constructs the machine sub-systems and exposes them as game.screens, game.signon, game.telly, game.sponsors,
# game.uplink (each loaded from res://scripts/game/<name>.gd when that file exists: telly/sponsors/uplink are ported
# by other agents). Game drives each sub-system's lifecycle (init/reset/update/lateUpdate) as its own isolated system
# right after `machines`; Machines must not call those methods itself.
# powerOn is the single power flag. setPower(on) switches it: the pre-power grade of every toon material
# (mats.uniforms.uSatEnv 0.70 -> 1.0, uAmber 0.08 -> 0, GDD §3.3), opens the doors with requiresPower and emits
# power:on {}. reset() restores the unpowered station (game params power=1 is applied by Game after reset).
# Machine events (GDD §18.15) are emitted by the sub-systems: machine:sign_on, machine:telly_*,
# machine:commercial_start/end, machine:dish_aligned, machine:uplink_*, machine:boss_*, machine:screen_override.
#
# Global uniforms: JS writes game.mats.uniforms.<name>.value. Here _setU() writes the same entry (Dictionary
# {value} or object with .value) when materials.gd exposes `uniforms`, calls mats.setUniform(name, v) when it has
# one, and also sets the Godot global shader parameter of that name when project.godot declares it
# ([shader_globals]); _getU() reads the value back (mats first, else the last value written here, else the
# project default: RenderingServer's global-parameter getters are editor-only).
#
# MP (online co-op, design/mp-machines.md, RECONCILE R9/R11): powerOn is host-authoritative. setPower(on) on the host
#   (debug, the power=1 launch param applied by the host's newGame, boss debugStart...) runs as in solo and then sends
#   machines.net_power(on, "set") to every client; on a client setPower() is ignored unless it comes from that
#   message (the requiresPower doors are the host's: level.openDoor replicates them). The Sign-On sequence's own power
#   beat (signon._beatPower, host t = 2.6) sends machines.net_power(true, "signon"): a client whose Sign-On sequence
#   runs flips powerOn + emits power:on without jumping its sequence (signon.netPower()), else it applies setPower.
#   Messages: machines.net_power(on: bool, src: String) host -> all; machines.net_sync(s: Dictionary) host -> all at
#   the host's game:start ({telly: homeId, satT: uplink satellite clock}: a safety net for reset-time game.rand()
#   picks). Locks: net:peer {id, joined:false}, team:down {id} and team:offair {id} are dispatched to
#   telly / uplink / signon .onPeerGone(id, why) on every peer (their host parts release the machine locks).
extends RefCounted

const PRE_POWER := {"sat": 0.7, "amber": 0.08}
const SUBSYSTEMS := [
	["screens", "res://scripts/game/screens.gd"],
	["signon", "res://scripts/game/signon.gd"],
	["telly", "res://scripts/game/telly.gd"],
	["sponsors", "res://scripts/game/sponsors.gd"],
	["uplink", "res://scripts/game/uplink.gd"],
]

var game
var powerOn := false
var screens
var signon
var telly
var sponsors
var uplink
var _uCache := {}          # last value written per global uniform (see _getU)
var _fromNet := false      # MP: setPower() called by net_power (a client applies the host's power)

func _init(g) -> void:
	game = g
	powerOn = false
	for entry in SUBSYSTEMS:
		var sys = _make(entry[0], entry[1])
		set(entry[0], sys)
		game.set(entry[0], sys)

func _make(name: String, path: String):
	if not ResourceLoader.exists(path):
		push_warning("[machines] sub-system '%s' missing (%s)" % [name, path])
		return null
	var script = load(path)
	if script == null or not script.can_instantiate():
		push_error("[machines] sub-system '%s' failed to load (%s)" % [name, path])
		return null
	return script.new(game)

func reset() -> void:
	powerOn = false
	_grade(false)

# MP (see the header): lock releases + the game-start sync.
func init() -> void:
	var ev = game.events
	if ev == null:
		return
	ev.on("net:peer", func(e = null):
		if e is Dictionary and e.get("joined") == false and _inGame():
			_peerGone(int(e.get("id", 0)), "left"))
	for name in ["team:down", "team:offair"]:
		var why: String = name.substr(5)
		ev.on(name, func(e = null):
			if e is Dictionary and _inGame():
				_peerGone(int(e.get("id", 0)), why))
	ev.on("game:start", func(_e = null):
		if _hst():
			var t = telly
			var u = uplink
			game.net.toAll("machines", "sync", [{"telly": t.homeId if t != null and t.get("homeId") != null else "",
				"satT": float(u.get("_satT")) if u != null and u.get("_satT") != null else -1.0}]))

func setPower(on: bool) -> void:
	var g = game
	if powerOn == on:
		return
	# MP: a client only changes power from the host's net_power
	if _cli() and not _fromNet:
		return
	powerOn = on
	_grade(on)
	if not on:
		if _hst():
			g.net.toAll("machines", "power", [false, "set"])
		return
	var lv = g.level
	var doors = lv.get("doors") if lv != null else null
	if doors is Dictionary and not _cli():
		for id in doors.keys():
			var d = doors[id]
			if d != null and d.get("requiresPower"):
				lv.openDoor(id)
	g.events.emit("power:on", {})
	if _hst():
		g.net.toAll("machines", "power", [true, "set"])

# ------------------------------------------------------------------------------------------------ MP
func _inGame() -> bool:
	var n = game.get("net")
	return n != null and n.inGame

func _cli() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isClient

func _hst() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isHost

# host -> all: the host's power changed (src "set": setPower, "signon": the Sign-On sequence's power beat).
func net_power(on, src = "set") -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isHost or n.sender != 1:
		return
	var v := bool(on)
	if v and str(src) == "signon" and signon != null and signon.has_method("netPower") and signon.netPower():
		return
	_fromNet = true
	setPower(v)
	_fromNet = false

# host -> all at the host's game:start: reset-time picks (Telly's start home, the satellite pass) as the host made them.
func net_sync(s) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isHost or n.sender != 1 or not (s is Dictionary):
		return
	if telly != null and telly.has_method("netHome"):
		telly.netHome(str(s.get("telly", "")))
	var st = s.get("satT")
	if uplink != null and (st is float or st is int) and float(st) >= 0.0 and uplink.get("_satT") != null:
		uplink.set("_satT", float(st))

func _peerGone(id: int, why: String) -> void:
	if id <= 0:
		return
	for s in [telly, uplink, signon]:
		if s != null and s.has_method("onPeerGone"):
			s.onPeerGone(id, why)

func _grade(on: bool) -> void:
	_setU("uSatEnv", 1.0 if on else PRE_POWER.sat)
	_setU("uAmber", 0.0 if on else PRE_POWER.amber)
	_setU("uWaveRadius", -1.0)

# game.mats.uniforms[name].value = v (see the header).
func _setU(name: String, v) -> void:
	_uCache[name] = v
	var M = game.mats
	if M != null:
		if M.has_method("setUniform"):
			M.setUniform(name, v)
		else:
			var U = M.get("uniforms")
			if U is Dictionary and U.has(name):
				var u = U[name]
				if u is Dictionary:
					u["value"] = v
				elif u is Object:
					u.set("value", v)
	if ProjectSettings.has_setting("shader_globals/" + name):
		RenderingServer.global_shader_parameter_set(name, v)

# game.mats.uniforms[name].value (see the header).
func _getU(name: String):
	var M = game.mats
	if M != null:
		if M.has_method("getUniform"):
			return M.getUniform(name)
		var U = M.get("uniforms")
		if U is Dictionary and U.has(name):
			var u = U[name]
			return u.get("value") if (u is Dictionary or u is Object) else u
	if _uCache.has(name):
		return _uCache[name]
	var d = ProjectSettings.get_setting("shader_globals/" + name)
	return d.get("value") if d is Dictionary else null
