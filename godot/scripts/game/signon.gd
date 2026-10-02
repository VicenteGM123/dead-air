# DEAD AIR — Sign-On (GDD §10.1): the Master Control power lever and the station coming ON THE AIR.
# Port of src/game/signon.js.
#
# Builds (init, into the master_control area, unless a room already placed them): the 'sign_on_lever' prop at the
# sign_on_lever anchor (knife switch under a hinged red hood + ON AIR lamp; light anchor 'signon_lamp'), the console
# island at mc_console (audio + switcher + monitor segments with the scr_preview monitor, walnut end cheeks), the
# 4x4 bc_monitor_wall at prop_monitor_wall when the room has none (its corner CRTs registered as ss_mc_w / ss_mc_e)
# and an ON AIR box over D5 on the MC side (the studio doors D4 / D6 / D7 carry theirs, level.gd lights them).
# Before power the ON AIR lamp pulses every 2 s and the lever's prompt is key-only [E] (interactable
# 'machine_sign_on'). trigger() plays the whole sequence (real time; t = seconds since the lever):
#   0.00  the hood flips up, the lever winds up and SLAMS (0.24: thunk, arc sparks, dust, squash, shake, hit-stop)
#         while the hero yanks it with the left arm and a little lunge (animator.override chained after the weapons
#         pose), the 60 Hz hum swells, the 16 MC-wall CRTs black out. Emits machine:sign_on {}.
#   0.30-1.80  the wall CRTs warm up one by one in snake order: dot -> line -> picture, settling on colour bars
#         (a crt_ping each; screens.warmUp).
#   1.80  every TV in the station opens on colour bars (screens.override priority 0 + blink), the 1 kHz bars tone
#         through the nearest TV speakers.
#   2.60  POWER: machines.powerOn = true, emits power:on {}; every TV cuts to the WZTV 13 station ID (1.6 s, then the
#         powered defaults: live feeds, the MC wall mix, Hootie's show); bells G4-C5-E5-G5 + the 8-bar funk
#         Sign-On theme; confetti from the ON AIR lamp; THE COLOUR WAVE starts at the lever [29, 1, -7.6]:
#         mats.uniforms uWaveOrigin / uWaveRadius grow at 15 m/s to 45 m (3 s: t 2.6-5.6) — the toon shader restores
#         saturation inside it and draws the scrolling colour-bar band at its front — then races on to 160 m and
#         the global grade is switched (uSatEnv 1, uAmber 0, uWaveRadius -1). Everything keyed to the wave
#         (level lights + door ON AIR boxes, feed-camera tallies, the MC ON AIR box, other agents' tally lights,
#         neon, Telly...) uses waveReached(pos) or lever distance / 15 s after power:on.
#   3.20  emits machine:sign_on_look { seconds: 1.5, origin } (zombies may stop and turn their heads to a TV).
#   6.00  DY buzzes and swings open (level.openDoor('dy_mc_yard')) with a gust of night wind; the tower beacons
#         start blinking (level.gd / the yard's tower_beacons follow level.beacons 3.4 s after power:on).
#  10.60  emits machine:sign_on_done {}; state 'on'.
# The console plays along: the audio board's VU needles rest before power, pin at 0 VU on the 1 kHz tone and bounce
# to the theme / programme audio; the switcher's T-bar is "taken" to air at 2.6 s.
# power=1 / debug.power(true) / machines.setPower(true) (power:on from elsewhere) jump straight to the powered
# state; debug.power(false) and newGame() put the lever back up.
#
# API (game.signon)
#   state 'off' | 'sequence' | 'on', done (bool: the lever was thrown or power is on), t (sequence seconds)
#   trigger() -> bool                       starts the sequence (false if already powered / running)
#   waveReached(pos:Vector3|[x,y,z]) -> bool   true once power is on and the colour wave has passed pos
#   waveTime(pos) -> seconds until the wave reaches pos (0 once reached, INF before power)
#   waveRadius (m, -1 = no wave), origin (Vector3), lever (prop Node3D), wall (the fallback monitor wall or null),
#   WAVE { speed, radius } (a constant; game.signon.WAVE reads it), timeScale (debug/tests: 0 holds the sequence on one frame)
# Events (GDD §18.15 + these machine:* extras): machine:sign_on {} (t 0), power:on {} (t 2.6),
#   machine:sign_on_look { seconds, origin } (t 3.2), machine:sign_on_done {} (t 10.6).
#
# Godot notes: props are placed with game.props.place (JS placeProp); mergeByMaterial (draw-call merging) is not
# ported. The lamp / jewel MeshBasicMaterials are unshaded StandardMaterial3Ds whose colour is written as the same
# linear value three.js used (Color.setScalar / multiplyScalar), converted to the sRGB albedo Godot expects.
# The hero pull drives rig.joints[name] as Node3D quaternions (three's Euler XYZ) and rig.root scale / position.
#
# MP (design/mp-machines.md, RECONCILE R9): the lever is a request. E on a client sends signon.net_lever() to the host
#   (the host's own E runs the same handler locally); the host, if the station is still off, runs
#   net.everyone("signon", "start", [by]) and EVERY peer plays the whole sequence from trigger(by) on its own real
#   time (the hero yank poses the user's model: the local Player, or that peer's RemotePlayer chaining its
#   weaponPose). World consequences stay with the host: at its t = 2.6 the host flips machines.powerOn, emits power:on
#   and sends machines.net_power(true, "signon"); a client's own power beat only plays the visuals, its powerOn flips
#   when that message arrives (netPower(): no jump to the end while its sequence runs). At t = 6.0 only the host opens
#   DY (level.openDoor, replicated by level); clients play the gust if DY was closed when their sequence started.
#   Camera shake / hit-stop / console animation follow the local (view) player as in solo.
#   Messages: signon.net_lever() client -> host · signon.net_start(by: int) host -> all (everyone).
extends RefCounted

const Screens = preload("res://scripts/game/screens.gd")

const WAVE := {"speed": 15.0, "radius": 45.0, "far": 160.0, "farSpeed": 60.0}
const TL := {"impact": 0.24, "bars": 1.8, "power": 2.6, "look": 3.2, "idEnd": 4.2, "dy": 6.0, "done": 10.6}
const FLICKER := [[0.0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]]
const CHIMES := ["ee_chime_red", "ee_chime_yellow", "ee_chime_green", "ee_chime_blue"] # G4 C5 E5 G5
const CONSOLE := [
	# dx along the console's local x (rotY pi: local +x = world west): audio west, switcher centre, monitors east
	{"id": "bc_console_audio", "dx": 1.2, "opts": {"vinyl": "#8A3A22"}},
	{"id": "bc_console_switcher", "dx": 0.0, "opts": {"tbar": 0.35}},
	{"id": "bc_console_monitor", "dx": -1.2, "opts": {"group": "scr_decor", "id": "mc_program"}},
]
const D5_ONAIR := {"pos": [23.225, 2.92, -4.0], "rotY": -PI / 2}
# The hero's lever yank (left arm; the gun arm keeps the weapons pose): reach up 0-0.1 s, slam 0.1-0.24 s with a
# forward lean, hold, let go by 0.75 s. Keys: [t, shoulderL x, shoulderL z, elbowL x, spine x].
const PULL := [[0.0, 0.3, 0.1, 0.3, 0.0], [0.1, 2.05, 0.02, 0.55, -0.05], [0.24, 0.8, 0.05, 0.12, 0.26], [0.45, 0.85, 0.06, 0.2, 0.18], [0.75, 0.3, 0.1, 0.3, 0.0]]
const UP_V := Vector3(0, 1, 0)

var game
var state := "off"
var done := false
var t := 0.0
var waveRadius := -1.0
var origin := Vector3(29, 1, -7.6)
var lever: Node3D = null
var wall: Node3D = null
var parts := {}
var rig := {}
var timeScale := 1.0              # debug / tests: 0 holds the sequence on a frame (freeze-frame screenshots)
var _clock := 0.0
var _next := 0
var _waveDone := false
var _emitting := false
var _switches: Array = []
var _ov: Array = []
var _whiteout := 0.0
var _timeline: Array = []
var _anchorId = null
var _lampMat: Material = null
var _jewelMat: Material = null
var _console = null
var _pullFn := Callable()
var _pullPrev = null
var _pullRoot = null
var _pullP = null                 # the player-like whose hero yanks the lever (solo: game.player)
var _pullBy := 0                  # MP: peer id of the lever user (0 = none)
var _dyWasClosed := false         # MP client: DY was still closed when the sequence started (gust FX at t = 6.0)

static func smooth(a: float, b: float, x: float) -> float:
	var u := clamp01((x - a) / (b - a))
	return u * u * (3.0 - 2.0 * u)

static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func easeOutBack(x: float, s: float = 1.8) -> float:
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

func _init(g) -> void:
	game = g

# ------------------------------------------------------------------------------------------------ build
func init() -> void:
	var g = game
	var a = _anchor("sign_on_lever")
	if a != null and a.get("pos") != null:
		var ap: Vector3 = DAU.v3(a.pos)
		origin = Vector3(ap.x, 1, ap.z)
	_timeline = [
		[0.0, func(): _beatStart()],
		[TL.impact, func(): _beatImpact()],
		[TL.bars, func(): _beatBars()],
		[TL.power, func(): _beatPower()],
		[TL.look, func(): g.events.emit("machine:sign_on_look", {"seconds": 1.5, "origin": origin})],
		[TL.idEnd, func(): _beatWall()],
		[TL.dy, func(): _beatDoor()],
		[TL.done, func(): _beatDone()],
	]
	_build()
	g.events.on("power:on", func():
		if not _emitting:
			_instantOn())
	_toOff()

func _beatDone() -> void:
	state = "on"
	game.events.emit("machine:sign_on_done", {})

func _build() -> void:
	var g = game
	var lv = g.level
	if lv == null:
		return
	var roots = lv.get("areaRoots")
	var parent = roots.get("master_control") if roots is Dictionary else null
	if not (parent is Node3D):
		return
	var found := {"lever": null, "console": false}
	DAU.traverse(parent, func(o):
		var id = _udGet(o, "id")
		if id == "sign_on_lever" and found.lever == null:
			found.lever = o
		if id is String and id.begins_with("bc_console_"):
			found.console = true)
	var lev = found.lever
	var a = _anchor("sign_on_lever")
	if lev == null and a != null and g.props != null:
		var ap: Vector3 = DAU.v3(a.pos)
		var ry = a.get("rotY")
		lev = g.props.place(parent, "sign_on_lever", {
			"pos": [ap.x, 0, ap.z], "rotY": ry if ry != null else PI, "area": "master_control", "tag": "machine",
			"opts": {"anchorId": "signon_lamp", "lamp": 0.2},
		})
		_anchorId = "signon_lamp"
	var island := DAU.node3d("signon_island")
	parent.add_child(island)
	var c = _anchor("mc_console")
	if c != null and not found.console and g.props != null:
		var rc = c.get("rotY")
		var rot: float = rc if rc != null else PI
		var cp: Vector3 = DAU.v3(c.pos)
		var cosr := cos(rot)
		for s in CONSOLE:
			g.props.place(island, s.id, {"pos": [cp.x + s.dx * cosr, 0, cp.z], "rotY": rot, "area": "master_control", "opts": s.opts, "tag": "machine"})
		for sx in [-1, 1]:
			g.props.place(island, "bc_console_end", {"pos": [cp.x + sx * 1.825, 0, cp.z], "rotY": rot, "area": "master_control", "tag": "machine"})
	_findConsoleParts(parent)
	_buildWall(parent, island)
	var box = g.props.place(island, "bc_on_air", {"pos": D5_ONAIR.pos, "rotY": D5_ONAIR.rotY, "area": "master_control", "opts": {"lit": false}, "colliders": false}) if g.props != null else null
	if box is Node3D:
		var bu := DAU.ud(box)
		var P = bu.get("parts", {})
		var lampMats = _lampMats(bu.get("lampMats"))
		if P is Dictionary and P.get("lamp") != null and lampMats != null:
			var lamp = P.lamp
			var pos: Vector3 = DAU.worldPos(box)
			pos.y = 3.0
			_switches.append({"pos": pos, "apply": func(on): _setMat(lamp, lampMats.on if on else lampMats.off), "sound": "onair_clack", "t": -1.0, "done": false, "sparks": true, "state": null})
	# mergeByMaterial(island): draw-call merging, not ported (SPEC §0.2)
	if lev is Node3D:
		lever = lev
		var lu := DAU.ud(lev)
		parts = lu.get("parts", {}) if lu.get("parts") is Dictionary else {}
		rig = lu.get("rig") if lu.get("rig") is Dictionary else {"leverOff": 1.2, "leverOn": 0.0, "coverClosed": 0.0, "coverOpen": 1.95}
		for k in ["lever", "cover"]:
			if parts.get(k) is Node3D:
				parts[k].rotation_order = EULER_ORDER_XYZ
		var lampTex = g.screens._cardGet("on_air", {"lit": true}) if g.screens != null else null
		_lampMat = _basicMat("#ffffff", lampTex, "signon:lamp")
		_jewelMat = _basicMat("#FFB347", null, "signon:jewels")
		if parts.get("lamp") != null:
			_setMat(parts.lamp, _lampMat)
		if parts.get("jewels") != null:
			_setMat(parts.jewels, _jewelMat)
		var ia = lu.get("interact")
		var ip = ia.get("point") if ia is Dictionary and ia.get("point") != null else [0, 1.0, -0.5]
		var pos: Vector3 = lev.to_global(DAU.v3(ip)) if lev.is_inside_tree() else lev.transform * DAU.v3(ip)
		if g.interact != null:
			g.interact.register({
				"id": "machine_sign_on", "pos": pos, "radius": 1.7,
				"enabled": func(): return state == "off" and not _powered(),
				"prompt": func(): return {},
				"use": func(): return _useLever(),
			})

# Console details that play along: the audio board's two VU needles (rest on the left stop before power, pinned
# at 0 VU by the 1 kHz tone, then bouncing to the funk theme / programme audio) and the switcher's T-bar, which
# the station "takes" to air at power (snaps from 0.35 to -0.35 rad with a bounce).
func _findConsoleParts(parent: Node) -> void:
	var C := {"needles": [], "lvl": [], "tbar": null}
	DAU.traverse(parent, func(o):
		var id = _udGet(o, "id")
		var P = _udGet(o, "parts")
		if not (P is Dictionary):
			return
		if id == "bc_console_audio":
			for n in [P.get("needleL"), P.get("needleR")]:
				if n is Node3D:
					n.rotation_order = EULER_ORDER_XYZ
					C.needles.append(n)
					C.lvl.append(0.0)
		if id == "bc_console_switcher" and P.get("tbar") is Node3D and C.tbar == null:
			C.tbar = P.tbar
			C.tbar.rotation_order = EULER_ORDER_XYZ)
	_console = C

func _animConsole(dt: float) -> void:
	var C = _console
	if C == null or (C.needles.is_empty() and C.tbar == null) or not _nearPlayer(16):
		return
	var st := t
	var tt := _clock
	var music := func(x: float) -> float: return 0.36 + 0.42 * exp(-(fmod(x, 0.5) / 0.11)) + 0.14 * sin(x * 7.3) * sin(x * 2.1)
	var target: float
	if state == "off":
		target = 0.04 + 0.02 * sin(tt * 47.0)
	elif state == "sequence":
		if st < TL.bars:
			target = 0.1 + 0.3 * clamp01(st / TL.bars) * (0.6 + 0.4 * sin(st * 31.0))
		elif st < TL.power:
			target = 0.78 + 0.01 * sin(st * 80.0)
		else:
			target = music.call(st - TL.power)
	else:
		target = 0.2 + 0.55 * music.call(tt) * (0.8 + 0.2 * sin(tt * 0.7))
	var k := minf(1.0, dt * 14.0)
	for i in C.needles.size():
		var n: Node3D = C.needles[i]
		var tg := minf(1.05, target * (0.93 if i % 2 else 1.0) + (0.02 * sin(tt * 13.0) if i % 2 else 0.0))
		C.lvl[i] += (tg - C.lvl[i]) * k
		n.rotation.z = -0.72 + 1.3 * C.lvl[i]
	if C.tbar != null:
		var x := 0.35
		if state == "on":
			x = -0.35
		elif state == "sequence" and st >= TL.power:
			x = 0.35 - 0.7 * easeOutBack(clamp01((st - TL.power) / 0.4), 2.2)
		C.tbar.rotation.x = x

# The 4x4 MC monitor wall is the Sign-On's stage (snake warm-up, pass B feeds). The master_control room owns it;
# when the room has not built one (no scr_mc_* screen and no bc_monitor_wall prop), place it at the
# prop_monitor_wall anchor so the sequence always plays. The two bottom-corner CRTs are re-registered with the
# screen-spawn ids ss_mc_w / ss_mc_e (screens.telegraph finds them by id).
func _buildWall(parent: Node3D, island: Node3D) -> void:
	var g = game
	var lv = g.level
	var s = g.screens
	var wa = _anchor("prop_monitor_wall")
	if s == null or wa == null or g.props == null:
		return
	if s.groups.scr_mc_feeds.size() + s.groups.scr_mc_canned.size() > 0:
		return
	var found := {"v": false}
	DAU.traverse(parent, func(o):
		if _udGet(o, "id") == "bc_monitor_wall":
			found.v = true)
	if found.v:
		return
	var rw = wa.get("rotY")
	var rot: float = rw if rw != null else PI
	var back := 0.25 # prop back face at local z = +0.25: stand it against the wall face
	var wp: Vector3 = DAU.v3(wa.pos)
	var w = g.props.place(island, "bc_monitor_wall", {
		"pos": [wp.x - sin(rot) * back, 0, wp.z - cos(rot) * back], "rotY": rot, "area": "master_control", "tag": "machine",
	})
	if not (w is Node3D):
		return
	# local variant: the kit's brushed 'metal' preset (rough 0.42, metal 0.7) blows out into a big specular hot
	# spot on the wall's top bevels under MC's low ceiling; a satin finish reads as brushed aluminium without it.
	var satin := {}
	DAU.traverse(w, func(o):
		if not (o is MeshInstance3D) or o.mesh == null:
			return
		for si in o.mesh.get_surface_count():
			var m = o.get_active_material(si)
			if m == null:
				continue
			var d = _matUd(m, "daToon")
			var p = d.get("params") if d is Dictionary else null
			if not (p is Dictionary) or not (float(p.get("metal", 0.0)) >= 0.6) or p.get("map") == null:
				continue
			var v = satin.get(m)
			if v == null and g.mats != null:
				var np: Dictionary = p.duplicate()
				np.rough = 0.74
				np.metal = 0.18
				np.env = 0.14
				v = g.mats.toon("#C3C8D0", np)
				satin[m] = v
			if v != null:
				o.set_surface_override_material(si, v))
	var wu := DAU.ud(w)
	var screens = wu.get("screens", [])
	var spawnIds := {"mcwall_r3c0": "ss_mc_w", "mcwall_r3c3": "ss_mc_e"}
	for sc in screens:
		var mesh = _screenMesh(sc, w)
		var sid = sc.get("id") if sc.get("id") else (_udGet(mesh, "screenId") if mesh != null else null)
		var ssId = spawnIds.get(sid)
		if ssId == null or mesh == null:
			continue
		s.register(mesh, "scr_mc_canned", {"id": ssId})
		var objs = lv.get("objects")
		if objs is Dictionary and not objs.has(ssId):
			objs[ssId] = {"group": w, "screen": mesh}
	wall = w

# ------------------------------------------------------------------------------------------------ lifecycle
func reset() -> void:
	for h in _ov:
		h.cancel()
	_ov.clear()
	_toOff()

func update(_dt = 0.0) -> void:
	var dt: float = float(game.time.realDt) * timeScale
	_clock += dt
	if state == "off":
		if _powered():
			_instantOn()
		else:
			_lamp(0.1 + 0.9 * pow(sin(PI * (fmod(_clock, 2.0) / 2.0)), 3.0))
	elif state == "sequence":
		_tick(dt)
	else:
		if not _powered():
			_toOff()
		else:
			_lamp(0.94 + 0.06 * sin(_clock * 377.0) * sin(_clock * 1.3))
	_updateSwitches(dt)
	_animConsole(dt)
	if not _pullFn.is_null() and (state != "sequence" or t >= PULL[PULL.size() - 1][0]):
		_heroPull(false)

# ------------------------------------------------------------------------------------------------ API
# by: MP peer id of the lever user (0 = the local player, as in solo).
func trigger(by: int = 0) -> bool:
	if state != "off" or _powered():
		return false
	_pullBy = by
	if _mp():
		var dy = _doorDY()
		_dyWasClosed = dy != null and not dy.get("open")
	_heroPull(true)
	state = "sequence"
	done = true
	t = 0.0
	_next = 0
	_waveDone = false
	waveRadius = -1.0
	_tick(0.0)
	return true

# ------------------------------------------------------------------------------------------------ MP
func _mp() -> bool:
	var n = game.get("net")
	return n != null and n.inGame

func _cli() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isClient

func _hst() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isHost

# The lever's E: solo throws it; MP asks the host (a host's own E runs the handler right away).
func _useLever() -> bool:
	if not _mp():
		return trigger()
	game.net.toHost("signon", "lever", [])
	return true

# client -> host: someone pulled the lever.
func net_lever() -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient or state != "off" or _powered():
		return
	n.everyone("signon", "start", [n.sender])

# host -> all (everyone): the Sign-On sequence starts on every peer.
func net_start(by) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.sender != 1:
		return
	trigger(int(by) if (by is int or by is float) else 0)

# MP client: the host's power beat (machines.net_power(true, "signon")) while our own sequence runs: flip the flag
# and emit power:on without jumping the sequence to its end. False when no sequence runs (machines applies setPower).
func netPower() -> bool:
	if state != "sequence":
		return false
	if _powered():
		return true
	_emitting = true
	game.machines.powerOn = true
	game.events.emit("power:on", {})
	_emitting = false
	return true

# machines dispatch (net:peer left / team:down / team:offair): the lever user's yank pose is dropped if they leave.
func onPeerGone(id: int, why: String = "left") -> void:
	if why == "left" and id == _pullBy and _pullBy != 0:
		_heroPull(false)
		_pullBy = 0

func _doorDY():
	var lv = game.level
	var doors = lv.get("doors") if lv != null else null
	return doors.get("dy_mc_yard") if doors is Dictionary else null

func waveReached(pos) -> bool:
	if not _powered():
		return false
	if _waveDone or (waveRadius < 0.0 and state != "sequence"):
		return true
	if waveRadius < 0.0:
		return false
	var p := _wpos(pos)
	return p.distance_to(origin) <= waveRadius

func waveTime(pos) -> float:
	if not _powered() and state != "sequence":
		return INF
	if waveReached(pos):
		return 0.0
	var p := _wpos(pos)
	var r: float = -(TL.power - t) * WAVE.speed if waveRadius < 0.0 else waveRadius
	return maxf(0.0, (p.distance_to(origin) - r) / WAVE.speed)

# [x, y, z] arrays default y to 1 (JS `pos[1] ?? 1`).
func _wpos(pos) -> Vector3:
	if pos is Vector3:
		return pos
	if pos is Array:
		return Vector3(float(pos[0]), float(pos[1]) if pos.size() > 1 and pos[1] != null else 1.0, float(pos[2]) if pos.size() > 2 else 0.0)
	return DAU.v3(pos)

# ------------------------------------------------------------------------------------------------ sequence
func _tick(dt: float) -> void:
	t += dt
	var tt := t
	while _next < _timeline.size() and tt >= _timeline[_next][0]:
		var fn: Callable = _timeline[_next][1]
		_next += 1
		fn.call()
	_pose(tt)
	# ON AIR lamp: strobe while the lever travels, a low hum that swells with the transformer, then a hard flash
	if tt < TL.impact:
		_lamp(1.0 if int(floor(tt * 30.0)) % 2 else 0.15)
	elif tt < TL.power:
		_lamp(0.22 + 0.3 * ((tt - TL.impact) / (TL.power - TL.impact)) + 0.05 * sin(tt * 377.0))
	else:
		_lamp(1.0 + 1.1 * exp(-(tt - TL.power) * 5.0))
	# the colour wave
	if tt >= TL.power and not _waveDone:
		var k: float = tt - TL.power
		var r0: float = WAVE.radius / WAVE.speed
		waveRadius = k * WAVE.speed if k < r0 else WAVE.radius + (k - r0) * WAVE.farSpeed
		if waveRadius >= WAVE.far:
			_finishWave()
		else:
			_setU("uWaveOrigin", origin)
			_setU("uWaveRadius", waveRadius)
	# power-surge flash on the frame
	var post = _post()
	if tt >= TL.power and tt < TL.power + 0.45:
		_whiteout = 0.012 * exp(-(tt - TL.power) * 12.0)
		if post != null:
			post["whiteout"] = _whiteout
	elif _whiteout > 0.0:
		_whiteout = 0.0
		if post != null:
			post["whiteout"] = 0.0

# Poses the hero's left arm on the lever for the slam (animator.override, chained after the weapons pose so the
# gun arm keeps its hold), with a squash on impact. Only when the hero stands at the lever.
func _heroPull(on: bool) -> void:
	var p = _pullP if not on and _pullP != null else _pullPlayer()
	var a = p.get("animator") if p != null and is_instance_valid(p) else null
	if a == null:
		_pullP = null
		return
	if not on:
		var cur = a.get("override")
		if not _pullFn.is_null() and cur is Callable and cur == _pullFn:
			a.set("override", _pullPrev)
		_pullFn = Callable()
		var root = _rigRoot(p.get("rig"))
		if root != null:
			root.scale = Vector3.ONE
			if _pullRoot != null:
				root.position = _pullRoot
		_pullRoot = null
		_pullP = null
		return
	var ov = a.get("override")
	if (ov is Callable and not ov.is_null()) or (ov != null and not (ov is Callable)) or not _nearP(p, 2.4):
		return
	_pullP = p
	_pullPrev = ov
	var root0 = _rigRoot(p.get("rig"))
	_pullRoot = root0.position if root0 != null else null
	_pullFn = func(rg, dt): _pullPose(rg, dt)
	a.set("override", _pullFn)

# The lever user's player-like: solo / own pull = game.player, MP = that peer's RemotePlayer (null if gone).
func _pullPlayer():
	if _pullBy != 0 and _mp():
		return game.net.playerById(_pullBy)
	return game.player

func _pullPose(rg, dt) -> void:
	var w = game.weapons
	var rp = _pullP if _pullP != null and _pullP != game.player else null
	if rp != null:
		# a remote user: chain its own gun pose (RemotePlayer.weaponPose), never the local weapons pose
		var wp = rp.get("weaponPose")
		if wp is Callable and (wp as Callable).is_valid():
			wp.call(rg, dt)
	elif w != null:
		var pf = w.get("_poseFn")
		if pf is Callable and pf.is_valid():
			pf.call(rg, dt)
		elif w.has_method("_poseFn"):
			w.call("_poseFn", rg, dt)
	var tt := t
	var J = rg.get("joints") if rg != null else null
	if not (J is Dictionary):
		J = {}
	if state != "sequence" or tt >= PULL[PULL.size() - 1][0]:
		return # update() removes the override
	var i := 0
	while i < PULL.size() - 2 and tt > PULL[i + 1][0]:
		i += 1
	var A: Array = PULL[i]
	var B: Array = PULL[i + 1]
	var u := smooth(A[0], B[0], tt)
	var k := func(n: int) -> float: return A[n] + (B[n] - A[n]) * u
	var wt := smooth(0.0, 0.06, tt) * (1.0 - smooth(0.5, 0.75, tt))
	_slerpJoint(J.get("shoulderL"), k.call(1), 0.0, k.call(2), wt)
	_slerpJoint(J.get("elbowL"), k.call(3), 0.0, 0.0, wt)
	var spine = J.get("spine")
	if spine is Node3D:
		spine.quaternion = spine.quaternion * _qXYZ(k.call(4) * wt, 0.0, 0.0)
	var sq := 0.07 * exp(-(tt - TL.impact) * 10.0) * cos((tt - TL.impact) * 28.0) if tt > TL.impact else 0.0
	var root = _rigRoot(rg)
	if root != null:
		root.scale = Vector3(1.0 + sq * 0.5, 1.0 - sq, 1.0 + sq * 0.5)
		# a little lunge toward the switch (model only; the player does not move)
		if _pullRoot != null:
			root.position = Vector3(_pullRoot.x, _pullRoot.y, _pullRoot.z - 0.32 * smooth(0.02, 0.2, tt) * (1.0 - smooth(0.4, 0.75, tt)))

func _slerpJoint(j, x: float, y: float, z: float, wt: float) -> void:
	if not (j is Node3D):
		return
	j.quaternion = j.quaternion.slerp(_qXYZ(x, y, z), wt)

static func _qXYZ(x: float, y: float, z: float) -> Quaternion:
	return Basis.from_euler(Vector3(x, y, z), EULER_ORDER_XYZ).get_rotation_quaternion()

func _rigRoot(rg) -> Node3D:
	if rg == null:
		return null
	var r = rg.get("root")
	return r if r is Node3D else null

func _beatStart() -> void:
	var g = game
	g.events.emit("machine:sign_on", {})
	if g.audio != null:
		g.audio.play("signon_hum", {"pos": origin})

func _beatImpact() -> void:
	var g = game
	var P := parts
	if g.audio != null:
		g.audio.play("signon_thunk", {"pos": origin})
	if P.get("lever") is Node3D:
		var lv: Node3D = P.lever
		lv.rotation.x = 0.0
		var v: Vector3 = lv.to_global(Vector3(0, 0.24, 0.02)) if lv.is_inside_tree() else Vector3(origin.x, 1.2, origin.z)
		if g.fx != null:
			g.fx.burst(v, {"shape": "spark", "count": 26, "speed": 6.5, "size": 0.045, "life": 0.5, "colors": ["#FFFFFF", "#BFE8FF", "#FFE8A0", Config.PAL.crtCyan], "dir": UP_V, "cone": 1.3})
			g.fx.burst(v, {"shape": "star", "count": 4, "speed": 2.2, "size": 0.09, "life": 0.5, "colors": ["#FFF3B0", Config.PAL.crtCyan]})
			g.fx.flashLight(v, "#BFE8FF", 7, 0.14)
	if g.fx != null:
		g.fx.burst(Vector3(origin.x, 0.12, origin.z), {"shape": "puff", "count": 9, "speed": 1.4, "size": 0.2, "life": 0.7, "colors": ["#D8D0C4", "#BFB6AA"]})
	if _nearPlayer(9):
		if g.cam != null and g.cam.has_method("shake"):
			g.cam.shake(0.22, 0.32)
		g.hitStop(0.05)
	# MC wall: black out, then the snake warm-up (0.30 .. 1.80)
	if g.screens != null:
		g.screens.warmUp(null, {"start": 0.3 - TL.impact, "end": TL.bars - TL.impact, "settle": "color_bars"})

func _beatBars() -> void:
	var s = game.screens
	if s == null:
		return
	_ov.append(s.override("color_bars", Screens.OVERRIDE_GROUPS, TL.power - TL.bars + 0.05, Screens.PRIORITY.sequence))
	s.blink(null, {"spread": 0.25, "from": origin, "except": s.wallOrder()})
	s.speaker("tone_1khz", {"near": 2, "dur": TL.power - TL.bars, "vol": 0.9})

func _beatPower() -> void:
	var g = game
	var s = g.screens
	# the single power flag, then everyone else (level lights, sponsors, Telly, feeds...) hears power:on
	_emitting = true
	if g.machines != null:
		g.machines.powerOn = true
	g.events.emit("power:on", {})
	_emitting = false
	_setU("uWaveOrigin", origin)
	_setU("uWaveRadius", 0.0)
	waveRadius = 0.0
	if s != null:
		for h in _ov:
			h.cancel()
		_ov.clear()
		_ov.append(s.override("station_id", Screens.OVERRIDE_GROUPS, TL.idEnd - TL.power, Screens.PRIORITY.sequence))
		s.blink(null, {"spread": 0.08, "dur": 0.14})
	if g.audio != null:
		g.audio.play("sting_sign_on_theme")
		for i in CHIMES.size():
			g.audio.play(CHIMES[i], {"delay": i * 0.14, "vol": 0.75})
	var P := parts
	if P.get("lamp") is Node3D:
		var v: Vector3 = DAU.worldPos(P.lamp)
		if g.fx != null:
			g.fx.burst(v, {"shape": "confetti", "count": 44, "speed": 5.5, "life": 1.9, "gravity": 6, "colors": Config.BARS, "dir": UP_V, "cone": 1.0})
			g.fx.burst(v, {"shape": "star", "count": 9, "speed": 3.2, "size": 0.13, "life": 1.1, "colors": [Config.PAL.marqueeGold, "#FFF3B0", Config.PAL.onAirRed]})
			g.fx.flashLight(v, Config.PAL.onAirRed, 9, 0.3)
	if _nearPlayer(14) and g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.14, 0.5)

func _beatWall() -> void:
	var s = game.screens
	if s != null:
		s.blink(s.wallOrder(), {"spread": 0.35})

func _beatDoor() -> void:
	var g = game
	var lv = g.level
	if lv == null:
		return
	var doors = lv.get("doors")
	var d = doors.get("dy_mc_yard") if doors is Dictionary else null
	if d == null or d.get("open"):
		return
	lv.openDoor("dy_mc_yard")
	var pos: Vector3 = DAU.v3(d.pos) if d.get("pos") != null else Vector3(35, 0, -8)
	var ap = d.get("approach")
	var inside = ap.get("master_control") if ap is Dictionary else null
	var dir: Vector3
	if inside != null:
		dir = DAU.v3(inside) - pos
		dir.y = 0.0
		dir = dir.normalized()
	else:
		dir = Vector3(-1, 0, 0)
	dir.y = 0.12
	pos.y = 1.1
	if g.fx != null:
		g.fx.burst(pos, {"shape": "puff", "count": 14, "speed": 2.8, "size": 0.24, "life": 1.2, "gravity": -0.3, "drag": 1.5, "colors": ["#9FB6FF", "#C8D2F0", "#E6E9F5"], "dir": dir, "cone": 0.55})
		g.fx.burst(pos, {"shape": "confetti", "count": 12, "speed": 3.6, "size": 0.06, "life": 2.4, "gravity": 2.2, "colors": [Config.PAL.avocado, Config.PAL.mustard, Config.PAL.burntOrange], "dir": dir, "cone": 0.7})
	if g.audio != null:
		g.audio.play("world_desert", {"pos": pos, "vol": 0.8})

func _finishWave() -> void:
	_waveDone = true
	waveRadius = -1.0
	_setU("uSatEnv", 1.0)
	_setU("uAmber", 0.0)
	_setU("uWaveRadius", -1.0)

# Lever + hood animation (anticipation, slam, bounce) and the cabinet's squash & stretch.
func _pose(tt: float) -> void:
	var P := parts
	if P.is_empty() or lever == null:
		return
	var R := rig
	if P.get("cover") is Node3D:
		P.cover.rotation.x = float(R.get("coverOpen", 1.95)) * easeOutBack(clamp01(tt / 0.2), 1.6)
	if P.get("lever") is Node3D:
		var x: float
		var off := float(R.get("leverOff", 1.2))
		if tt < 0.1:
			x = off + 0.16 * sin((tt / 0.1) * (PI / 2.0))
		elif tt < TL.impact:
			var u: float = (tt - 0.1) / (TL.impact - 0.1)
			x = (off + 0.16) * (1.0 - u * u * u)
		else:
			var kk: float = tt - TL.impact
			x = 0.18 * absf(sin(kk * 15.0)) * exp(-kk * 8.0)
		P.lever.rotation.x = x
	var k: float = tt - TL.impact
	if k >= 0.0 and k < 0.8:
		var s := 0.075 * exp(-k * 9.0) * cos(k * 30.0)
		lever.scale = Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5)
	elif k >= 0.8:
		lever.scale = Vector3.ONE

# JS: lampMat.color.setScalar(0.1 + 1.75 level), jewelMat.color.set('#FFB347').multiplyScalar(...) (linear colour
# scales; the DAMaterial basic shader multiplies uColor by uIntensity, the StandardMaterial3D fallback gets the
# equivalent sRGB albedo).
func _lamp(level: float) -> void:
	if _lampMat != null:
		_scaleMat(_lampMat, Color(1, 1, 1), 0.1 + 1.75 * level)
	if _jewelMat != null:
		_scaleMat(_jewelMat, Color("#FFB347"), 0.12 + 2.2 * minf(level, 1.2))
	if _anchorId != null and game.lights != null:
		game.lights.setAnchor(_anchorId, {"intensity": 2.4 * (0.08 + 0.92 * minf(level, 1.3))})

# ------------------------------------------------------------------------------------------------ states
func _instantOn() -> void:
	_heroPull(false)
	for h in _ov:
		h.cancel()
	_ov.clear()
	if state == "sequence" and _whiteout > 0.0:
		var post = _post()
		if post != null:
			post["whiteout"] = 0.0
		_whiteout = 0.0
	state = "on"
	done = true
	t = TL.done
	_next = _timeline.size()
	_waveDone = true
	waveRadius = -1.0
	var wr = _getU("uWaveRadius")
	var sat = _getU("uSatEnv")
	if wr == null or sat == null or float(wr) >= 0.0 or float(sat) < 1.0:
		_setU("uSatEnv", 1.0)
		_setU("uAmber", 0.0)
		_setU("uWaveRadius", -1.0)
	var P := parts
	if not P.is_empty():
		if P.get("lever") is Node3D:
			P.lever.rotation.x = float(rig.get("leverOn", 0.0))
		if P.get("cover") is Node3D:
			P.cover.rotation.x = float(rig.get("coverOpen", 1.95))
		if lever != null:
			lever.scale = Vector3.ONE
	_lamp(1.0)
	for sw in _switches:
		sw.apply.call(true)
		sw.done = true
		sw.t = 1.0

func _toOff() -> void:
	_heroPull(false)
	state = "off"
	done = false
	t = 0.0
	_next = 0
	_waveDone = false
	waveRadius = -1.0
	if _whiteout > 0.0:
		var post = _post()
		if post != null:
			post["whiteout"] = 0.0
		_whiteout = 0.0
	var P := parts
	if not P.is_empty():
		if P.get("lever") is Node3D:
			P.lever.rotation.x = float(rig.get("leverOff", 1.2))
		if P.get("cover") is Node3D:
			var cc = rig.get("coverClosed")
			P.cover.rotation.x = float(cc) if cc != null else 0.0
		if lever != null:
			lever.scale = Vector3.ONE
	for sw in _switches:
		sw.apply.call(false)
		sw.done = false
		sw.t = -1.0

# Things this file lights when the wave passes them: relay clack + 3-flash flicker + a few red sparks.
func _updateSwitches(dt: float) -> void:
	if state == "off":
		return
	for sw in _switches:
		if sw.done:
			continue
		if sw.t < 0.0:
			if not waveReached(sw.pos):
				continue
			sw.t = 0.0
			sw.state = null
			if sw.sound and game.audio != null:
				game.audio.play(sw.sound, {"pos": sw.pos})
			if sw.sparks and game.fx != null:
				game.fx.burst(sw.pos, {"shape": "spark", "count": 10, "speed": 3, "size": 0.03, "life": 0.35, "colors": [Config.PAL.onAirRed, "#FFD0C0", "#FFFFFF"]})
		sw.t += dt
		var on := true
		for f in FLICKER:
			if sw.t >= f[0]:
				on = f[1]
		if sw.state == null or on != sw.state:
			sw.apply.call(on)
			sw.state = on
		if sw.t >= FLICKER[FLICKER.size() - 1][0]:
			sw.done = true

func _powered() -> bool:
	return game.machines != null and bool(game.machines.powerOn)

func _nearPlayer(r: float) -> bool:
	var p = game.player
	if p == null:
		return false
	var pp = p.get("pos")
	if not (pp is Vector3):
		return false
	return Vector2(pp.x - origin.x, pp.z - origin.z).length() < r

# ------------------------------------------------------------------------------------------------ helpers (Godot glue)
# JS new THREE.MeshBasicMaterial({ map, color }): an own copy of game.mats.basic() (a StandardMaterial3D unshaded
# without materials.gd).
func _basicMat(color: String, map, name: String) -> Material:
	var M = game.mats
	if M != null and M.has_method("basic"):
		var o := {"name": name}
		if map != null:
			o.map = map
		var b = M.basic(color, o)
		if b != null:
			return b.clone() if b.has_method("clone") else b.duplicate()
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color)
	m.albedo_texture = map
	return m

# userData.lampMats {on, off}: Materials, or the Blender export's {"__material": spec} refs (built with
# game.mats.fromSpec). null when missing.
func _lampMats(lm):
	if not (lm is Dictionary) or lm.get("on") == null or lm.get("off") == null:
		return null
	var out := {}
	for k in ["on", "off"]:
		var v = lm[k]
		if v is Dictionary and v.has("__material"):
			v = game.mats.fromSpec(v.__material) if game.mats != null and game.mats.has_method("fromSpec") else null
		if not (v is Material):
			return null
		out[k] = v
	return out

# material colour = base colour (sRGB) x k in linear space.
static func _scaleMat(m: Material, base: Color, k: float) -> void:
	if "intensity" in m and "color" in m:
		m.color = base
		m.intensity = k
	elif m is BaseMaterial3D:
		var c := base.srgb_to_linear()
		m.albedo_color = Color(c.r * k, c.g * k, c.b * k).linear_to_srgb()

# material.userData[key] (DAMaterial keeps userData as a property; other objects as the "userData" meta).
static func _matUd(m, key: String):
	var u = m.get("userData") if m is Object else null
	if u is Dictionary:
		return u.get(key)
	return _udGet(m, key)

func _anchor(id: String):
	var lv = game.level
	if lv == null:
		return null
	var A = lv.get("anchors")
	return A.get(id) if A is Dictionary else null

# userData[key] without creating the meta on nodes that have none (DAU.ud would add it).
static func _udGet(o, key: String):
	if o == null or not (o is Object) or not o.has_meta("userData"):
		return null
	var u = o.get_meta("userData")
	return u.get(key) if u is Dictionary else null

# mesh.material = m (JS). Works on MeshInstance3D / any GeometryInstance3D.
static func _setMat(n, m) -> void:
	if n is MeshInstance3D and n.mesh != null and n.material_override == null:
		for i in n.mesh.get_surface_count():
			n.set_surface_override_material(i, m)
	elif n is GeometryInstance3D:
		n.material_override = m

# A prop screen record ({mesh} in JS; the Godot prop library may give {mesh} or {node: name | Node}).
static func _screenMesh(sc, root: Node):
	if not (sc is Dictionary):
		return null
	var m = sc.get("mesh")
	if m == null:
		m = sc.get("node")
	if m is String and root != null:
		m = DAU.byName(root, m)
	return m if m is Node else null

func _post():
	var r = game.render
	if r == null:
		return null
	var p = r.get("post")
	return p if p is Dictionary else null

func _setU(name: String, v) -> void:
	if game.machines != null and game.machines.has_method("_setU"):
		game.machines._setU(name, v)

func _getU(name: String):
	if game.machines != null and game.machines.has_method("_getU"):
		return game.machines._getU(name)
	return null
