# DEAD AIR — power-up drops (port of src/game/powerups.js; GDD §12, §18.11, §15 cues; ARCHITECTURE §4/§10).
#
# DROP RULES (GDD §12)
#   Every zombie:kill (except cause 'cancelled') spawns a drop at the body when the points earned since the last drop
#   reached the threshold (T.drops.threshold, x T.drops.thresholdMul after each drop), else with T.drops.chance (2 %).
#   At most T.drops.perRound drops per round and T.drops.minGap s between drops (guaranteed specials ignore both and
#   do not touch the threshold). Type = a shuffled bag of the 6, no repeats until it empties; CANCELLED is held back
#   in rounds 1-2 (it waits in the bag). A body outside the playable floor (queued at a window, in a screen) drops at
#   the nearest walkable spot inside.
# ON THE GROUND: the 'drop_<type>' prop (the Blender port of src/props/sponsors.js: screen bubble + gold floor ring),
#   1.0 m up, bobbing and spinning (animateDrop), switched on like a CRT (line -> picture), a pooled floor light + a
#   soft pu_idle pad. It lives T.drops.life s and flickers like bad reception for the last T.drops.blink s, then
#   collapses into static. Touch pickup within T.drops.pickupR: the bubble "tunes out", a coloured ring pulses at the
#   hero's feet.
# EFFECTS
#   cancelled        every living non-boss zombie gets a red rubber-stamp X on its face and pops, nearest first,
#                    spread over 1.5 s (zombies.kill cause 'cancelled': no per-kill points, counts for the round;
#                    Big Shots lose 50 % of max HP instead), then +T.points.cancelled.
#   full_reel        weapons.refillAll() (mags + reserves, grenades 4, Tiny Teles 3 if owned).
#   one_take         T.drops.timed s: zombies read isActive('one_take') (one-hit kills, star eyes); a warm gold
#                    vignette on the main camera; each kill gets a tiny laugh-track blip.
#   sweeps_week      T.drops.timed s: economy.multiplier reads active.sweeps_week (written directly if economy has no
#                    getter); the HUD turns the digits gold, audio.gd rings every gain.
#   gaffer_tape      every boarded window refilled (level.windows[*].repairBoard, cascading nearest first) with a
#                    silver gaffer-tape X over the boards (it tears off with the next board); +T.points.gaffer.
#   please_stand_by  T.drops.freeze s: zombies.freezeAll(true) (zombies.gd greys them, screens.gd shows stand_by,
#                    audio.gd plays the bossa bed and "...and we're back!" on powerup:end).
# API (game.powerups)
#   active                 { type: seconds left } for the timed ones (HUD icons + blinking)
#   items                  live drops [{ type, pos, group, life, state, special }]
#   isActive(type) -> bool
#   drop(type|null, pos?) -> item          spawn now (null type = next from the bag; no pos = in front of the hero)
#   dropGuaranteed(type, pos) -> item      special drops (last Sock Hopper, first Big Shot, boss phases): ignore
#                                          the per-round cap and the gap, keep the threshold
#   grab(type) / debugGrab(type)           apply an effect now (no drop)     debugDrop(type, dist = 2.2) -> item
#   threshold, earned (points since the last natural drop), dropsThisRound, bag (next types), state() -> summary
# EVENTS  powerup:spawn {type, pos}  powerup:grab {type}  powerup:end {type}  (+ powerup:expire {type, pos})
# SOUNDS  audio.gd voices pu_spawn (powerup:spawn), each pickup cue + announcer wah-wah + pu_sad_trombone +
#   pu_bossa_bed (powerup:grab) and sting_back (powerup:end please_stand_by). This file plays pu_idle (loop per drop),
#   pu_expire, the stamp clacks and the ONE TAKE laugh blips.
# Also here: animateDrop(drop, t) (the src/props/sponsors.js runtime helper).
#
# PORT NOTES
#   * warmup() (Game.precompile samples) is engine plumbing: not ported.
#   * The stamp / tape / pulse meshes are bare quads (FX primitives: QuadMesh / PlaneMesh); their canvas textures are
#     drawn with the Canvas 2D emulation (commercial.gd canvasTex).
#   * ONE TAKE vignette: the JS gated the full-screen quad on `camera === game.camera` in onBeforeRender; here the
#     shader compares CAMERA_VISIBLE_LAYERS with the main camera's cull mask (uniform uMainMask, set every frame), so
#     the feed, sponsor and insert cameras never draw it.
#   * economy.multiplier: the JS writes it only when economy has no getter; an economy port that mirrors the JS
#     getter keeps its backing field `_mult`, so the write happens only when that field is absent.
#   * No renames were needed (§3.2).
# MP (RECONCILE R3; behind net.inGame — solo unchanged): the HOST owns drops (rules, g.rand(), bag, threshold — counted
#   from economy's host event points:award, every player's awards — life and expiry). Messages (sys "powerups"):
#   net_spawn(id, type, pos, special) host -> clients (drop() / dropGuaranteed() are no-ops on clients) ·
#   net_grab(id, pos) client -> host when the LOCAL player touches a drop (the client plays the "tune out" at once) ·
#   net_grabbed(id, type, by, pos) host -> all (first request wins; id "" = a debug grab): every peer runs the team
#   effect (_apply): FULL REEL refills its own player, timed effects start everywhere; CANCELLED / GAFFER TAPE run their
#   world part on the host only (kills, Big Shot half HP, board repairs; +400 / +200 to every player = economy team
#   reasons) · net_stamp(zid) / net_tape(windowId) host -> clients (stamp / tape X visuals) · net_expire(id),
#   net_end(type) host -> clients (clients never expire / end on their own clock) · net_grabAny(type, pos),
#   net_debugDrop(type, pos) client -> host (tests only). powerup:grab carries `by` in MP. Off-air, hidden and
#   in-commercial players never grab.
extends RefCounted

const Commercial = preload("res://scripts/ui/commercial.gd")

const POWERUP_TYPES := ["cancelled", "full_reel", "one_take", "sweeps_week", "gaffer_tape", "please_stand_by"]
const GLOW := {"cancelled": "#E3662B", "full_reel": "#FFC23A", "one_take": "#FF3B30", "sweeps_week": "#FF4FA0", "gaffer_tape": "#DDE3EA", "please_stand_by": "#EDEDED"}
const SPAWN_T := 0.55
const GRAB_T := 0.4
const EXPIRE_T := 0.45
const CANCEL := {"lead": 0.3, "spread": 1.5, "stampHold": 0.16, "fade": 0.55}
const TAPE := {"cascade": 0.55, "unroll": 0.13, "width": 0.13}
const TAU := PI * 2.0

static func D() -> Dictionary:
	return Config.T.drops

static func DURATION() -> Dictionary:
	return {"one_take": float(Config.T.drops.timed), "sweeps_week": float(Config.T.drops.timed), "please_stand_by": float(Config.T.drops.freeze)}

static func _clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func _easeOutBack(x: float, s: float = 2.2) -> float:
	x = _clamp01(x)
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

static func _easeOutCubic(x: float) -> float:
	return 1.0 - pow(1.0 - _clamp01(x), 3.0)

static func _easeIn(x: float) -> float:
	return pow(_clamp01(x), 2.0)

# Field of a Dictionary or Object (the JS `a?.b`).
static func _f(o, k: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		return o.get(k, def)
	if o is Object:
		var v = o.get(k)
		return def if v == null else v
	return def

# Method call guarded like the JS `a?.m?.(...)` (Objects, or Callable fields of Dictionaries).
static func _m(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Object:
		if o.has_method(m):
			return o.callv(m, args)
		var c = o.get(m)
		if c is Callable and c.is_valid():
			return c.callv(args)
		return null
	if o is Dictionary and o.get(m) is Callable:
		return o[m].callv(args)
	return null

static func _gxf(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.global_transform
	var x := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

# THREE.Color (linear) -> the sRGB-encoded Color Godot's albedo expects (keeps > 1 values: HDR tints).
static func _albedoFromLinear(r: float, g: float, b: float, a: float = 1.0) -> Color:
	return Color(DAU.linearToSrgb(r), DAU.linearToSrgb(g), DAU.linearToSrgb(b), a)

# ------------------------------------------------------------------------------------------------ textures
# A red rubber-stamp X with ink speckle and a double border ring (CANCELLED).
static func stampTexture():
	return Commercial.canvasTex(256, 256, func(x, w, h):
		var st := {"s": 7}
		var rnd := func() -> float:
			st.s = (st.s * 16807) % 2147483647
			return float(st.s) / 2147483647.0
		x.translate(w / 2.0, h / 2.0)
		x.rotate(-0.12)
		x.strokeStyle = "#E8262E"
		x.lineCap = "round"
		x.lineWidth = 46
		x.beginPath()
		x.moveTo(-78, -78)
		x.lineTo(78, 78)
		x.stroke()
		x.beginPath()
		x.moveTo(78, -80)
		x.lineTo(-76, 80)
		x.stroke()
		x.lineWidth = 9
		x.beginPath()
		x.arc(0, 0, 118, 0, TAU)
		x.stroke()
		x.lineWidth = 4
		x.beginPath()
		x.arc(0, 0, 105, 0, TAU)
		x.stroke()
		x.setTransform(1, 0, 0, 1, 0, 0)
		# dry-ink speckle: knock holes out of the ink
		x.globalCompositeOperation = "destination-out"
		for i in 260:
			x.globalAlpha = 0.25 + rnd.call() * 0.6
			x.beginPath()
			x.arc(rnd.call() * w, rnd.call() * h, 0.6 + rnd.call() * 2.6, 0, TAU)
			x.fill()
		for i in 18:
			x.globalAlpha = 0.35
			x.fillRect(rnd.call() * w, rnd.call() * h, 18.0 + rnd.call() * 40.0, 2.0 + rnd.call() * 3.0)
		x.globalCompositeOperation = "source-over"
		x.globalAlpha = 1)

# Silver cloth tape strip with torn ends (u along the strip).
static func tapeTexture():
	return Commercial.canvasTex(256, 32, func(x, w, h):
		var g = x.createLinearGradient(0, 0, 0, h)
		g.addColorStop(0, "#C8CED8")
		g.addColorStop(0.45, "#F2F5F8")
		g.addColorStop(1, "#AEB6C2")
		x.fillStyle = g
		x.fillRect(0, 0, w, h)
		x.strokeStyle = "rgba(90,98,112,0.22)"
		x.lineWidth = 1
		var i := 0
		while i < w:
			x.beginPath()
			x.moveTo(i, 0)
			x.lineTo(i + 2, h)
			x.stroke()
			i += 3
		var j := 2
		while j < h:
			x.beginPath()
			x.moveTo(0, j)
			x.lineTo(w, j)
			x.stroke()
			j += 4
		x.fillStyle = "rgba(255,255,255,0.35)"
		x.fillRect(0, h * 0.3, w, 2)
		# torn ends
		x.globalCompositeOperation = "destination-out"
		for end in [0, w]:
			x.beginPath()
			x.moveTo(end, 0)
			var jj := 0
			while jj <= h:
				x.lineTo(end + (-1 if end else 1) * (2 + ((jj * 37) % 9)), jj)
				jj += 4
			x.lineTo(end, h)
			x.closePath()
			x.fill()
		x.globalCompositeOperation = "source-over")

# Soft radial disc (pickup ring pulse).
static func ringTexture():
	return Commercial.canvasTex(128, 128, func(x, w, h):
		var g = x.createRadialGradient(w / 2.0, h / 2.0, 0, w / 2.0, h / 2.0, w / 2.0)
		g.addColorStop(0, "rgba(255,255,255,0)")
		g.addColorStop(0.72, "rgba(255,255,255,0)")
		g.addColorStop(0.86, "rgba(255,255,255,1)")
		g.addColorStop(1, "rgba(255,255,255,0)")
		x.fillStyle = g
		x.fillRect(0, 0, w, h))

# ------------------------------------------------------------------------------------------------ ONE TAKE vignette
# Full-screen clip-space quad drawn last in the main scene pass, only for the main camera (feed, sponsor and insert
# cameras see nothing: the camera gate compares the rendering camera's cull mask with the main camera's). Additive
# warm gold at the frame edges with a slow shimmer of film-strip sparkles.
const VIG_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float uOn = 0.0;
uniform float uAmt = 0.0;
uniform float uTime = 0.0;
uniform int uMainMask = 3;
varying vec2 vUv;
varying float vGate;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	vUv = vec2(UV.x, 1.0 - UV.y);
	vGate = (int(CAMERA_VISIBLE_LAYERS) == uMainMask) ? 1.0 : 0.0;
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
	float uAspect = VIEWPORT_SIZE.x / max(1.0, VIEWPORT_SIZE.y);
	// distance to the nearest screen edge in screen heights: a warm frame of even thickness, fuller in the corners
	float dx = min(vUv.x, 1.0 - vUv.x) * uAspect;
	float dy = min(vUv.y, 1.0 - vUv.y);
	float d = min(dx, dy);
	float corner = length(max(vec2(0.16) - vec2(dx, dy), 0.0));
	float shimmer = 0.9 + 0.1 * sin(uTime * 2.7 + vUv.x * 6.0 + vUv.y * 4.0);
	float glow = exp(-d * 11.0) * 0.36 * shimmer + smoothstep(0.0, 0.16, corner) * 0.16;
	// sparse twinkling four-point sparkles hugging the frame
	vec2 gridUv = vUv * vec2(64.0 * uAspect / 1.7778, 36.0);
	vec2 cell = floor(gridUv);
	vec2 f = fract(gridUv) - 0.5;
	float on = step(0.985, hash(cell + floor(uTime * 4.0 + hash(cell) * 3.0)));
	float star = max(0.0, 1.0 - length(f) * 5.0) + max(0.0, 1.0 - abs(f.x) * 14.0) * max(0.0, 1.0 - abs(f.y) * 3.0) * 0.6
	           + max(0.0, 1.0 - abs(f.y) * 14.0) * max(0.0, 1.0 - abs(f.x) * 3.0) * 0.6;
	float tw = on * star * exp(-d * 28.0);
	vec3 gold = vec3(1.0, 0.68, 0.2);
	vec3 col = gold * glow + vec3(1.0, 0.92, 0.6) * tw * 0.9;
	ALBEDO = col * uAmt * uOn * vGate;
	ALPHA = 1.0;
}
"""

var game
var active := {}
var items: Array = []
var bag: Array = []
var threshold: float = 2000.0
var earned: float = 0.0
var dropsThisRound := 0
var lastDropAt: float = -INF
var round := 1
var _n := 0
var _cancel = null
var _stamps: Array = []
var _tapes := {}
var _tapeQueue: Array = []
var _pulses: Array = []
var _laughAt: float = -1.0
var _frozeZombies := false
var _vig: MeshInstance3D = null
var _vigMat: ShaderMaterial = null
var _vigAmt := 0.0
var _mats = null
var _stampGeo: QuadMesh = null
var _tapeGeo: QuadMesh = null
var _ringGeo: PlaneMesh = null

var _netPops: Array = []         # MP client: CANCELLED pops scheduled after a host stamp { z, t }

func _init(g) -> void:
	game = g
	threshold = float(D().threshold)

func _net():
	return game.get("net") if game != null else null

# An MP game is running (net.inGame is already true while the MP newGame's resets run).
func _mp() -> bool:
	var n = _net()
	return n != null and bool(n.inGame)

func _isClient() -> bool:
	var n = _net()
	return n != null and bool(n.inGame) and bool(n.isClient)

# ------------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	var g = game
	var ev = g.events
	_buildShared()
	ev.on("zombie:kill", func(p = null): _onKill(p if p is Dictionary else {}))
	ev.on("points:change", func(p = null):
		if p and float(_f(p, "delta", 0.0)) > 0 and not _mp():   # MP: the host counts points:award instead
			earned += float(p.delta))
	# MP host: every award routed to any player (economy.add) counts toward the drop threshold
	ev.on("points:award", func(p = null):
		if p and float(_f(p, "delta", 0.0)) > 0:
			earned += float(p.delta))
	ev.on("round:start", func(p = null):
		dropsThisRound = 0
		var r = _f(p, "round")
		round = int(r) if r else round)
	ev.on("barricade:break", func(p = null): _tearTape(_f(p, "id")))

func reset() -> void:
	for it in items:
		_dispose(it)
	items.clear()
	for type in active.keys():
		_end(type, true)
	active = {}
	bag = []
	threshold = float(D().threshold)
	earned = 0.0
	dropsThisRound = 0
	lastDropAt = -INF
	round = 1
	_cancel = null
	_netPops.clear()
	for s in _stamps:
		_free(s.mesh)
	_stamps.clear()
	for id in _tapes.keys():
		_removeTape(id, false)
	_tapeQueue.clear()
	for p in _pulses:
		p.mesh.visible = false
	_vigAmt = 0.0
	if _vig:
		_vig.visible = false
	if _frozeZombies:
		_frozeZombies = false
		_m(game.zombies, "freezeAll", [false])

static func _free(n) -> void:
	if n is Node and is_instance_valid(n):
		DAU.detach(n)
		n.queue_free()

# ------------------------------------------------------------------------------------------------ API
func isActive(type: String) -> bool:
	return float(active.get(type, 0.0)) > 0.0

func drop(type = null, pos = null, opts: Dictionary = {}):
	if _isClient():
		return null                  # MP: drops are the host's (its RNG / bag); they arrive as powerups.net_spawn
	var g = game
	if type == null:
		type = _nextType()
	if not POWERUP_TYPES.has(type):
		return null
	if pos == null:
		var p = g.player
		var fwd: Vector3 = p.forward() if p.has_method("forward") else Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		fwd.y = 0.0
		pos = p.pos + fwd.normalized() * 2.2
	var at := _placeFor(pos, opts.get("z"))
	var item = _spawnItem("", type, at, bool(opts.get("special", false)))
	if item != null and _mp():
		_net().toAll("powerups", "spawn", [item.id, item.type, at, item.special])
	return item

# The drop on the ground (prop, floor light, idle pad, pop-in bursts, powerup:spawn). id "" = the next local id
# (host / solo); MP clients pass the host's id.
func _spawnItem(id: String, type: String, at: Vector3, special: bool):
	var g = game
	var group = _m(g.props, "build", ["drop_" + type, {}])
	if not (group is Node3D):
		push_warning("[powerups] drop prop failed drop_" + type)
		return null
	group.position = at
	load("res://scripts/game/sponsors.gd").resolveRefs(group, DAU.ud(group))
	var P = DAU.ud(group).get("parts", {})
	if not (P is Dictionary):
		P = {}
	g.scene.add_child(group)
	if id == "":
		_n += 1
		id = "pu_drop_%d" % _n
	var item := {"id": id, "type": type, "pos": at, "group": group, "parts": P, "age": 0.0, "life": float(D().life), "state": "in", "t": 0.0, "special": special, "anchor": null, "idle": null, "glitch": 0.0, "glitchOff": false, "jx": 0.0, "sq": 1.0}
	var ar = _m(g.level, "areaAt", [at.x, at.z])
	var anc = _m(g.lights, "addAnchor", [{"pos": [at.x, at.y + 0.2, at.z], "color": GLOW[type], "intensity": 1.0, "distance": 2.4, "area": ar, "id": id}])
	item.anchor = id if anc else null
	var up := Vector3(at.x, at.y + 1.0, at.z)
	var idle = _m(g.audio, "loop", ["pu_idle", {"pos": up, "vol": 0.7}])
	item.idle = idle if idle else null
	items.append(item)
	_setScale(item, 0.05, 0.02, 0.0)
	_m(g.fx, "burst", [up, {"shape": "star", "count": 7, "colors": [GLOW[type], Config.PAL.get("marqueeGold", "#FFD23A"), "#FFFFFF"], "speed": 2.6, "life": 0.7, "size": 0.1}])
	_m(g.fx, "burst", [up, {"shape": "static", "count": 10, "speed": 1.6, "size": 0.07, "life": 0.5}])
	g.events.emit("powerup:spawn", {"type": type, "pos": at})
	return item

func dropGuaranteed(type, pos):
	return drop(type if type else null, pos, {"special": true})

func grab(type: String) -> bool:
	if not POWERUP_TYPES.has(type):
		return false
	if _mp():
		# MP: a team effect decided by the host (a client asks; test / debug use only)
		var net = _net()
		var p = game.player
		var at: Vector3 = p.pos if p != null else Vector3.ZERO
		if net.isClient:
			net.toHost("powerups", "grabAny", [type, at])
		else:
			net.everyone("powerups", "grabbed", ["", type, int(net.localId), at])
		return true
	_apply(type, null)
	return true

func debugGrab(type: String) -> bool:
	return grab(type)

func debugDrop(type = null, dist: float = 2.2):
	var p = game.player
	var v := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	if _isClient():
		_net().toHost("powerups", "debugDrop", [str(type) if type is String else "", p.pos + v * dist])
		return null
	return drop(type, p.pos + v * dist)

# ------------------------------------------------------------------------------------------------ MP messages
func _itemById(id: String):
	for it in items:
		if it.id == id:
			return it
	return null

func _zById(zid):
	var Z = game.zombies
	if Z == null or not (zid is int or zid is float):
		return null
	if Z.has_method("byId"):
		return Z.byId(int(zid))
	for z in _f(Z, "alive", []):
		if z and int(_f(z, "id", -1)) == int(zid):
			return z
	return null

# host -> clients: a drop appeared (the host already resolved type and position).
func net_spawn(id = "", type = "", pos = null, special = false) -> void:
	var net = _net()
	if net == null or not net.inGame or not net.isClient or net.sender != 1:
		return
	if not POWERUP_TYPES.has(str(type)) or not (pos is Vector3) or _itemById(str(id)) != null:
		return
	_spawnItem(str(id), str(type), pos, bool(special))

# client -> host: my player touched drop `id` standing at `at`. The first request the host sees wins.
func net_grab(id = "", at = null) -> void:
	var net = _net()
	if net == null or not net.isHost or not net.inGame:
		return
	var it = _itemById(str(id))
	if it == null:
		return
	var ok: bool = it.state == "idle" or (it.state == "in" and it.t > 0.15) or (it.state == "expire" and it.t < 0.25)
	var pos: Vector3 = at if at is Vector3 else it.pos
	if not ok or Vector2(pos.x - it.pos.x, pos.z - it.pos.z).length() > float(D().pickupR) + 1.5:
		return
	net.everyone("powerups", "grabbed", [it.id, it.type, int(net.sender), pos])

# host -> all: drop `id` (or "" for a debug grab) was grabbed by peer `by` at `at`: the team effect on every peer.
func net_grabbed(id = "", type = "", by = 0, at = null) -> void:
	var net = _net()
	if net == null or not net.inGame or net.sender != 1 or not POWERUP_TYPES.has(str(type)):
		return
	var it = _itemById(str(id)) if str(id) != "" else null
	var p = game.player
	var pos: Vector3 = at if at is Vector3 else (p.pos if p != null else Vector3.ZERO)
	if it != null and it.state != "grab":
		_grabFx(it, pos)
	_apply(str(type), it, int(by), pos)

# client -> host: grab() without a drop (tests).
func net_grabAny(type = "", at = null) -> void:
	var net = _net()
	if net == null or not net.isHost or not net.inGame or not POWERUP_TYPES.has(str(type)) or not game.params.get("test"):
		return
	net.everyone("powerups", "grabbed", ["", str(type), int(net.sender), at if at is Vector3 else Vector3.ZERO])

# client -> host: debugDrop (tests).
func net_debugDrop(type = "", pos = null) -> void:
	var net = _net()
	if net == null or not net.isHost or not net.inGame or not (pos is Vector3) or not game.params.get("test"):
		return
	drop(str(type) if str(type) != "" else null, pos)

# host -> clients: the drop's life ran out.
func net_expire(id = "") -> void:
	var net = _net()
	if net == null or not net.inGame or not net.isClient or net.sender != 1:
		return
	var it = _itemById(str(id))
	if it != null and (it.state == "idle" or it.state == "in"):
		_expire(it)

# host -> clients: a timed effect is over.
func net_end(type = "") -> void:
	var net = _net()
	if net == null or not net.inGame or not net.isClient or net.sender != 1:
		return
	if active.has(str(type)):
		_end(str(type))

# host -> clients: CANCELLED stamps zombie `zid` (the host kills it CANCEL.stampHold later; the kill replicates).
func net_stamp(zid = -1) -> void:
	var net = _net()
	if net == null or not net.inGame or not net.isClient or net.sender != 1:
		return
	var z = _zById(zid)
	if z == null or _f(z, "removed", false):
		return
	_stamp(z)
	_m(game.audio, "play", ["telly_clack", {"pos": z.pos, "rate": 0.7 + randf() * 0.2, "vol": 0.9}])
	_netPops.append({"z": z, "t": 0.0})

func _updateNetPops(dt: float) -> void:
	for i in range(_netPops.size() - 1, -1, -1):
		var q: Dictionary = _netPops[i]
		q.t += dt
		if q.t < CANCEL.stampHold:
			continue
		_netPops.remove_at(i)
		var z = q.z
		if z == null or _f(z, "removed", false):
			continue
		var v: Vector3 = z.pos
		v.y = z.pos.y + float(_f(z, "height", 1.7)) * 0.8
		_m(game.fx, "burst", [v, {"shape": "confetti", "count": 12, "colors": ["#E8262E", "#FFFFFF", "#FFD23A"], "speed": 4, "life": 1}])
		_m(game.fx, "burst", [v, {"shape": "static", "count": 8, "speed": 2.2, "size": 0.08, "life": 0.5}])

# host -> clients: GAFFER TAPE taped window `wid` (its boards come back through the windows replication).
func net_tape(wid = "") -> void:
	var net = _net()
	if net == null or not net.inGame or not net.isClient or net.sender != 1:
		return
	var W = _f(game.level, "windows", {})
	var w = W.get(str(wid)) if W is Dictionary else null
	if w != null:
		_addTape(w)

func state() -> Dictionary:
	var its := []
	for i in items:
		its.append({"type": i.type, "life": snappedf(i.life, 0.01), "state": i.state, "pos": [snappedf(i.pos.x, 0.01), snappedf(i.pos.y, 0.01), snappedf(i.pos.z, 0.01)]})
	return {
		"active": active.duplicate(), "items": its,
		"threshold": int(roundf(threshold)), "earned": earned, "dropsThisRound": dropsThisRound, "bag": bag.duplicate(),
		"cancelling": _cancel != null, "tapes": _tapes.size(), "vignette": snappedf(_vigAmt, 0.01),
	}

# ------------------------------------------------------------------------------------------------ drop rules
func _onKill(p: Dictionary) -> void:
	if p.get("cause") == "cancelled":
		return
	var g = game
	if float(active.get("one_take", 0.0)) > 0 and g.time.realNow - _laughAt > 0.18:
		_laughAt = g.time.realNow
		_m(g.audio, "play", ["crowd_laugh", {"pos": p.get("pos"), "dur": 0.45, "vol": 0.32, "rate": 1.15 + randf() * 0.25}])
	if _isClient():
		return                       # MP: the drop rules (and their RNG) are the host's
	var due := earned >= threshold
	if not due and not (g.rand() < float(D().chance)):
		return
	var now: float = g.time.now
	if dropsThisRound >= int(D().perRound) or now - lastDropAt < float(D().minGap):
		return
	var pos = p.get("pos")
	if pos == null and p.get("z") != null:
		pos = _f(p.z, "pos")
	if pos == null:
		return
	var item = drop(null, pos, {"z": p.get("z")})
	if item == null:
		return
	earned = 0.0
	threshold *= float(D().thresholdMul)
	dropsThisRound += 1
	lastDropAt = now

func _nextType() -> String:
	var g = game
	var rr = _f(g.rounds, "round")
	var rnd: int = int(rr) if rr != null else round
	var allowed := func(t) -> bool: return not (t == "cancelled" and rnd <= 2)
	var i := -1
	for k in bag.size():
		if allowed.call(bag[k]):
			i = k
			break
	if i < 0:
		var add := []
		for t in POWERUP_TYPES:
			if not bag.has(t):
				add.append(t)
		for k in range(add.size() - 1, 0, -1):
			var j := int(floor(g.rand() * (k + 1)))
			var tmp = add[k]
			add[k] = add[j]
			add[j] = tmp
		bag.append_array(add)
		for k in bag.size():
			if allowed.call(bag[k]):
				i = k
				break
	if i < 0:
		return "full_reel"
	var out: String = bag[i]
	bag.remove_at(i)
	return out

# A reachable floor spot for a drop: the body if it lies on the walkable floor, else its window's inside point,
# else the nearest walkable cell within 4 m. Also keeps 0.9 m from other drops.
func _placeFor(pos, z) -> Vector3:
	var g = game
	var nav = g.nav
	var col = _f(g.level, "col")
	var py: float = float(pos.y) if pos is Vector3 else 0.0
	var out := Vector3(pos.x, py, pos.z)
	var ok := func(x: float, zz: float) -> bool:
		if nav and nav.has_method("walkable"):
			return bool(nav.walkable(x, zz))
		return true
	if not ok.call(out.x, out.z):
		var entry = _f(z, "entry")
		var eid = _f(entry, "id")
		var wins = _f(g.level, "windows")
		var win = null
		if eid and wins is Dictionary:
			win = wins.get(eid)
		var inside = _f(win, "inside")
		if win and inside:
			out = DAU.v3(inside)
		if not ok.call(out.x, out.z):
			var best = null
			var bd := INF
			var r := 0.5
			while r <= 4.0 and best == null:
				for k in 16:
					var a := (k / 16.0) * TAU
					var x := out.x + cos(a) * r
					var zz := out.z + sin(a) * r
					if not ok.call(x, zz):
						continue
					var d: float = Vector2(x - g.player.pos.x, zz - g.player.pos.z).length() if g.player else r
					if d < bd:
						bd = d
						best = [x, zz]
				r += 0.5
			if best != null:
				out = Vector3(best[0], out.y, best[1])
	for it in items:
		var dx: float = out.x - it.pos.x
		var dz: float = out.z - it.pos.z
		var d := Vector2(dx, dz).length()
		if d < 0.9:
			var a: float = atan2(dz, dx) if d > 1e-3 else g.rand() * TAU
			var nx: float = it.pos.x + cos(a) * 0.95
			var nz: float = it.pos.z + sin(a) * 0.95
			if ok.call(nx, nz):
				out = Vector3(nx, out.y, nz)
	var y := -INF
	if nav and nav.has_method("heightAt"):
		var hv = nav.heightAt(out.x, out.z)
		y = float(hv) if hv != null else -INF
	if not (y > -INF) and col and col.has_method("floorAt"):
		var fv = col.floorAt(out.x, out.z, py + 1.0)
		y = float(fv) if fv != null else -INF
	out.y = y if y > -INF else py
	return out

# ------------------------------------------------------------------------------------------------ per frame
func update(dt: float) -> void:
	var g = game
	var p = g.player
	var canGrab: bool = p != null and p.alive != false and not p.downed
	var mp := _mp()
	var cl := _isClient()
	if canGrab and mp:
		# MP: off-air, hidden and on-set (commercial) players never touch a drop
		canGrab = not bool(_f(p, "offAir", false)) and not bool(_f(p, "hidden", false)) \
			and not bool(_f(p, "inCommercial", false)) and not bool(_f(g.sponsors, "inCommercial", false))
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it.age += dt
		it.t += dt
		if it.state == "in":
			_animIdle(it)
			var k: float = it.t / SPAWN_T
			var sx := 0.08 + 0.92 * _easeOutBack(_clamp01(k / 0.45), 1.4)
			var sy := 0.03 if k < 0.3 else 0.03 + 0.97 * _easeOutBack((k - 0.3) / 0.7, 2.6)
			_setScale(it, sx, sy, _easeOutBack(k, 1.8))
			if it.t >= SPAWN_T:
				it.state = "idle"
				it.t = 0.0
				_setScale(it, 1, 1, 1)
		elif it.state == "idle":
			it.life -= dt
			_animIdle(it)
			_reception(it, dt)
			if it.life <= 0:
				if cl:
					it.life = 0.0            # MP client: the host decides the expiry (powerups.net_expire)
				else:
					_expire(it)
					if mp:
						_net().toAll("powerups", "expire", [it.id])
		elif it.state == "grab":
			var k: float = it.t / GRAB_T
			_animIdle(it)
			var sy := 1.0 + 0.3 * sin((k / 0.3) * PI) if k < 0.3 else maxf(0.02, 1.0 - _easeIn((k - 0.3) / 0.25))
			var sx := 1.0 + 0.25 * _easeOutCubic(k / 0.5) if k < 0.5 else maxf(0.0, 1.25 * (1.0 - _easeIn((k - 0.5) / 0.5)))
			_setScale(it, sx, sy, maxf(0.0, 1.0 - _easeIn(k)))
			if it.t >= GRAB_T:
				_dispose(it)
				items.remove_at(i)
			continue
		elif it.state == "expire":
			var k: float = it.t / EXPIRE_T
			_animIdle(it)
			var sy := maxf(0.02, 1.0 - _easeIn(k / 0.45))
			var sx := 1.0 if k < 0.45 else maxf(0.0, 1.0 - _easeIn((k - 0.45) / 0.55))
			_setScale(it, sx, sy, maxf(0.0, 1.0 - k))
			if it.t >= EXPIRE_T:
				_dispose(it)
				items.remove_at(i)
			continue
		if canGrab and (it.state == "idle" or (it.state == "in" and it.t > 0.15)):
			var dx: float = p.pos.x - it.pos.x
			var dz: float = p.pos.z - it.pos.z
			var dy: float = p.pos.y - it.pos.y
			var R: float = float(D().pickupR)
			if dx * dx + dz * dz <= R * R and dy > -1.2 and dy < 2.2:
				_pickup(it)
	for type in active.keys():
		if not (dt > 0):
			break
		active[type] -= dt
		if active[type] <= 0:
			if cl:
				active[type] = 0.001         # MP client: the effect ends with the host's powerups.net_end
			else:
				_end(type)
				if mp:
					_net().toAll("powerups", "end", [type])
	if _cancel != null:
		_updateCancel(dt)
	if not _netPops.is_empty():
		_updateNetPops(dt)
	_updateStamps(dt)
	_updateTapes(dt)
	_updatePulses(dt)
	_updateVignette(g.time.realDt if g.time.realDt else dt)
	var zs = g.zombies
	if not cl and float(active.get("please_stand_by", 0.0)) > 0 and zs and not _f(zs, "frozen", false):
		_m(zs, "freezeAll", [true])
		_frozeZombies = true

func _animIdle(it: Dictionary) -> void:
	animateDrop(it.group, it.age)

func _setScale(it: Dictionary, sx: float, sy: float, ring: float) -> void:
	var P: Dictionary = it.parts
	if P.get("float") is Node3D:
		P.float.scale = Vector3(sx, sy, sx)
	if P.get("ring") is Node3D:
		P.ring.scale = Vector3.ONE * maxf(0.001, ring)

# Bad reception during the last T.drops.blink seconds: drop-outs that get longer, sideways tearing, squashes.
func _reception(it: Dictionary, dt: float) -> void:
	var P: Dictionary = it.parts
	if not (P.get("float") is Node3D):
		return
	var blink: float = float(D().blink)
	if it.life > blink:
		P.float.visible = true
		P.float.position.x = 0.0
		return
	var f: float = 1.0 - it.life / blink
	it.glitch -= dt
	if it.glitch <= 0:
		var off := randf() < 0.28 + 0.45 * f
		it.glitchOff = off
		it.glitch = 0.04 + randf() * (0.05 + 0.12 * f) if off else 0.06 + randf() * (0.35 - 0.25 * f)
		it.jx = (randf() - 0.5) * 0.14 * (0.4 + f)
		it.sq = 1.0 - randf() * 0.35 * f
		if off and randf() < 0.3:
			var v := Vector3(it.pos.x, it.pos.y + 1.0, it.pos.z)
			_m(game.fx, "burst", [v, {"shape": "static", "count": 3, "speed": 1.2, "size": 0.05, "life": 0.3}])
	P.float.visible = not it.glitchOff
	P.float.position.x = 0.0 if it.glitchOff else it.jx
	P.float.scale.y = it.sq

func _pickup(it: Dictionary) -> void:
	if _mp():
		_pickupMP(it)
		return
	_grabFx(it, game.player.pos)
	_apply(it.type, it)

# The drop "tunes out" (confetti, stars, a flash) and a coloured ring pulses at `at` (the grabber's feet).
func _grabFx(it: Dictionary, at: Vector3) -> void:
	var g = game
	it.state = "grab"
	it.t = 0.0
	if it.parts.get("float") is Node3D:
		it.parts.float.visible = true
		it.parts.float.position.x = 0.0
	_stopIdle(it)
	var v := Vector3(it.pos.x, it.pos.y + 1.0, it.pos.z)
	var c: String = GLOW[it.type]
	_m(g.fx, "burst", [v, {"shape": "confetti", "count": 18, "colors": [c, "#FFFFFF", Config.PAL.get("marqueeGold", "#FFD23A")], "speed": 4, "life": 1.1}])
	_m(g.fx, "burst", [v, {"shape": "star", "count": 8, "colors": [c, "#FFFFFF"], "speed": 3.2, "life": 0.6, "size": 0.12}])
	_m(g.fx, "flashLight", [v, c, 6, 0.2])
	_pulse(at, c)

# MP: the host decides who got it first. A client shows the "tune out" right away (the effect waits for the host's
# powerups.net_grabbed: if a teammate was first, the drop is gone either way and the effect is the team's anyway).
func _pickupMP(it: Dictionary) -> void:
	var net = _net()
	var p = game.player
	if net.isClient:
		if it.get("req", false):
			return
		it["req"] = true
		_grabFx(it, p.pos)
		net.toHost("powerups", "grab", [it.id, p.pos])
		return
	net.everyone("powerups", "grabbed", [it.id, it.type, int(net.localId), p.pos])

func _expire(it: Dictionary) -> void:
	var g = game
	it.state = "expire"
	it.t = 0.0
	if it.parts.get("float") is Node3D:
		it.parts.float.visible = true
		it.parts.float.position.x = 0.0
	_stopIdle(it)
	var v := Vector3(it.pos.x, it.pos.y + 1.0, it.pos.z)
	_m(g.fx, "burst", [v, {"shape": "static", "count": 18, "speed": 2, "size": 0.08, "life": 0.6}])
	_m(g.audio, "play", ["pu_expire", {"pos": v}])
	g.events.emit("powerup:expire", {"type": it.type, "pos": it.pos})

func _stopIdle(it: Dictionary) -> void:
	if it.idle != null:
		_m(it.idle, "stop", [0.25])
	it.idle = null
	if it.anchor:
		_m(game.lights, "removeAnchor", [it.anchor])
		it.anchor = null

func _dispose(it: Dictionary) -> void:
	_stopIdle(it)
	_free(it.group)

# ------------------------------------------------------------------------------------------------ effects
# by / at: MP only (the grabber's peer id and position; the host runs the world parts, every peer its own player's).
func _apply(type: String, _item, by = null, at = null) -> void:
	var g = game
	var cl := _isClient()
	if by == null:
		g.events.emit("powerup:grab", {"type": type})
	else:
		g.events.emit("powerup:grab", {"type": type, "by": by})
	if type == "cancelled":
		if not cl:
			_startCancel(at)
	elif type == "full_reel":
		_m(g.weapons, "refillAll")
		if not (by != null and g.player.alive == false):      # (MP: an off-air spectator gets no burst)
			var v: Vector3 = g.player.pos
			v.y = g.player.pos.y + 1.1
			_m(g.fx, "burst", [v, {"shape": "star", "count": 10, "colors": ["#FFC23A", "#FFF3B0", "#FFFFFF"], "speed": 3, "life": 0.8, "size": 0.12}])
	elif type == "gaffer_tape":
		if not cl:
			_gaffer(at)
	var DU := DURATION()
	if not DU.has(type):
		return
	active[type] = DU[type]
	if type == "sweeps_week":
		_setMultiplier(2)
	elif type == "please_stand_by":
		_m(g.zombies, "freezeAll", [true])
		_frozeZombies = true

func _end(type: String, silent: bool = false) -> void:
	var g = game
	active.erase(type)
	if type == "sweeps_week":
		_setMultiplier(1)
	elif type == "please_stand_by" and _frozeZombies:
		_frozeZombies = false
		_m(g.zombies, "freezeAll", [false])
	if not silent:
		g.events.emit("powerup:end", {"type": type})

# economy.gd reads active.sweeps_week through its multiplier getter; a plain-field economy gets it written.
func _setMultiplier(v: float) -> void:
	var e = game.economy
	if e == null:
		return
	if e is Object and e.get("_mult") != null:
		return      # the getter design (JS: property descriptor with get)
	if e is Object:
		e.set("multiplier", v)
	elif e is Dictionary:
		e.multiplier = v

# Coloured ring expanding at the hero's feet (pickup feedback).
func _pulse(pos: Vector3, color: String) -> void:
	var p = null
	for q in _pulses:
		if not q.mesh.visible:
			p = q
			break
	if p == null:
		if _pulses.size() >= 3:
			p = _pulses[0]
		else:
			var mesh := MeshInstance3D.new()
			mesh.name = "pu_pulse"
			mesh.mesh = _ringGeo
			var mat: StandardMaterial3D = _mats.ring.duplicate()
			mesh.material_override = mat
			mesh.extra_cull_margin = 16384.0      # frustumCulled = false
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			game.scene.add_child(mesh)
			p = {"mesh": mesh, "mat": mat, "t": 0.0}
			_pulses.append(p)
	p.t = 0.0
	var c := Color(color)
	var a: float = p.mat.albedo_color.a
	p.mat.albedo_color = _albedoFromLinear(DAU.srgbToLinear(c.r) * 1.6, DAU.srgbToLinear(c.g) * 1.6, DAU.srgbToLinear(c.b) * 1.6, a)
	p.mesh.position = Vector3(pos.x, pos.y + 0.06, pos.z)
	p.mesh.visible = true

func _updatePulses(dt: float) -> void:
	var rdt: float = game.time.realDt if game.time.realDt else dt
	for p in _pulses:
		if not p.mesh.visible:
			continue
		p.t += rdt
		var k: float = p.t / 0.55
		var s := 0.4 + 2.6 * _easeOutCubic(k)
		p.mesh.scale = Vector3(s, s, s)
		var c: Color = p.mat.albedo_color
		p.mat.albedo_color = Color(c.r, c.g, c.b, maxf(0.0, 1.0 - k))
		if k >= 1:
			p.mesh.visible = false

# --- CANCELLED
func _startCancel(origin = null) -> void:
	var g = game
	var Z = g.zombies
	var list := []
	for z in _f(Z, "alive", []):
		if z and not _f(z, "dead", false) and not _f(z, "removed", false) and _f(z, "type") != "boss_baron":
			list.append(z)
	var pp: Vector3 = origin if origin is Vector3 else g.player.pos      # MP: nearest the grabber first
	list.sort_custom(func(a, b): return a.pos.distance_squared_to(pp) < b.pos.distance_squared_to(pp))
	var n := list.size()
	var entries := []
	for i in n:
		entries.append({"z": list[i], "at": CANCEL.lead + (CANCEL.spread * pow(float(i) / (n - 1), 0.85) if n > 1 else 0.2), "stamped": false, "done": false})
	_cancel = {"t": 0.0, "bonus": false, "list": entries}

func _updateCancel(dt: float) -> void:
	var c: Dictionary = _cancel
	var g = game
	var Z = g.zombies
	c.t += dt
	var pending := false
	for e in c.list:
		if e.done:
			continue
		pending = true
		var z = e.z
		if z == null or _f(z, "dead", false) or _f(z, "removed", false):
			e.done = true
			continue
		if not e.stamped and c.t >= e.at:
			e.stamped = true
			_stamp(z)
			_m(g.audio, "play", ["telly_clack", {"pos": z.pos, "rate": 0.7 + randf() * 0.2, "vol": 0.9}])
			if _mp():
				_net().toAll("powerups", "stamp", [int(_f(z, "id", -1))])
		if e.stamped and c.t >= e.at + CANCEL.stampHold:
			e.done = true
			var v: Vector3 = z.pos
			v.y = z.pos.y + float(_f(z, "height", 1.7)) * 0.8
			_m(g.fx, "burst", [v, {"shape": "confetti", "count": 12, "colors": ["#E8262E", "#FFFFFF", "#FFD23A"], "speed": 4, "life": 1}])
			_m(g.fx, "burst", [v, {"shape": "static", "count": 8, "speed": 2.2, "size": 0.08, "life": 0.5}])
			if _f(z, "type") == "big_shot":
				# exactly half his max HP (no front armour, no ONE TAKE): straight off the health, or the pop if that kills
				var mh = _f(z, "maxHp")
				var half: float = (float(mh) if mh else float(z.hp)) * 0.5
				if z.hp - half > 0:
					z.hp -= half
					var an = _f(z, "anim")
					if an is Dictionary:
						an.hurt = 1
					var anm = _f(z, "animator")
					if anm and anm.has_method("kick"):
						anm.kick(1)
				else:
					_m(Z, "kill", [z, {"cause": "cancelled"}])
			elif Z and Z.has_method("kill"):
				Z.kill(z, {"cause": "cancelled"})
			else:
				_m(Z, "damage", [z, z.hp + 1, {"cause": "cancelled", "points": false, "hitmarker": false}])
	if not c.bonus and c.t >= CANCEL.lead + CANCEL.spread + 0.2:
		c.bonus = true
		_m(g.economy, "add", [Config.T.points.cancelled, "cancelled"])
	if not pending and c.bonus:
		_cancel = null

func _stamp(z) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "pu_stamp"
	mesh.mesh = _stampGeo
	var mat: StandardMaterial3D = _mats.stamp.duplicate()
	mesh.material_override = mat
	mesh.layers = 1 << Config.LAYERS.ZOMBIES
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.scene.add_child(mesh)
	var hr = _f(z, "headR")
	var s := {"mesh": mesh, "mat": mat, "z": z, "t": 0.0, "popped": false, "rot": (randf() - 0.5) * 0.5, "pos": Vector3.ZERO, "size": maxf(0.42, (float(hr) if hr else 0.22) * 2.6)}
	s.pos = _headPos(z)
	_stamps.append(s)

func _headPos(z) -> Vector3:
	var head = _f(z, "head")
	var h: float = float(_f(z, "height", 1.7))
	var zp: Vector3 = z.pos
	if head is Node3D and is_instance_valid(head) and not _f(z, "removed", false):
		var out := _gxf(head).origin
		if not is_finite(out.y) or out.distance_squared_to(zp) > 16:
			out = Vector3(zp.x, zp.y + h * 0.85, zp.z)
		return out
	return Vector3(zp.x, zp.y + h * 0.85, zp.z)

func _updateStamps(dt: float) -> void:
	if _stamps.is_empty():
		return
	var cam: Camera3D = game.camera
	if cam == null:
		return
	var cxf := _gxf(cam)
	var camPos := cxf.origin
	var camQ := cxf.basis.get_rotation_quaternion()
	var rdt := dt if dt > 0 else 0.0
	var hi := DAU.linearToSrgb(1.6)
	for i in range(_stamps.size() - 1, -1, -1):
		var s: Dictionary = _stamps[i]
		var z = s.z
		s.t += rdt
		if not _f(z, "removed", false) and not (_f(z, "dead", false) and s.t > CANCEL.stampHold + 0.25):
			s.pos = _headPos(z)
		var v: Vector3 = (camPos - s.pos).normalized()
		var hr = _f(z, "headR")
		var pos: Vector3 = s.pos + v * ((float(hr) if hr else 0.22) + 0.06)
		var q := camQ * Quaternion(Vector3(0, 0, 1), s.rot)
		var slam: float = 2.4 - 1.5 * (s.t / 0.09) if s.t < 0.09 else 0.9 + 0.1 * _easeOutBack((s.t - 0.09) / 0.12, 3)
		var sc: float = s.size * slam
		s.mesh.transform = Transform3D(Basis(q).scaled(Vector3(sc, sc, sc)), pos)
		var fadeT: float = s.t - CANCEL.stampHold - 0.2
		var op := maxf(0.0, 1.0 - fadeT / CANCEL.fade) if fadeT > 0 else 1.0
		var cv := hi if s.t < 0.12 else 1.0
		s.mat.albedo_color = Color(cv, cv, cv, op)
		if fadeT >= CANCEL.fade:
			_free(s.mesh)
			_stamps.remove_at(i)

# --- GAFFER TAPE
func _gaffer(origin = null) -> void:
	var g = game
	var L = g.level
	var wins := []
	var W = _f(L, "windows", {})
	if W is Dictionary:
		for w in W.values():
			if w and _f(w, "type") == "boarded":
				wins.append(w)
	var pp: Vector3 = origin if origin is Vector3 else g.player.pos      # MP: the cascade starts at the grabber
	var dist := func(w) -> float:
		var wp: Vector3 = DAU.v3(_f(w, "pos"))
		return Vector2(wp.x - pp.x, wp.z - pp.z).length()
	wins.sort_custom(func(a, b): return dist.call(a) < dist.call(b))
	var n := wins.size()
	for i in n:
		_tapeQueue.append({"w": wins[i], "at": TAPE.cascade * (float(i) / (n - 1)) if n > 1 else 0.0, "t": 0.0})
	_m(g.economy, "add", [Config.T.points.gaffer, "gaffer"])

func _updateTapes(dt: float) -> void:
	var rdt: float = game.time.realDt if game.time.realDt else dt
	for i in range(_tapeQueue.size() - 1, -1, -1):
		var q: Dictionary = _tapeQueue[i]
		q.t += rdt
		if q.t < q.at:
			continue
		_tapeQueue.remove_at(i)
		var w = q.w
		var guard := 8
		while int(_f(w, "boards", 6)) < 6 and guard > 0:
			guard -= 1
			if not _m(w, "repairBoard"):
				break
		_addTape(w)
		if _mp():
			_net().toAll("powerups", "tape", [str(_f(w, "id", ""))])
	for tp in _tapes.values():
		if tp.t >= 1:
			continue
		tp.t = minf(1.0, tp.t + rdt / (TAPE.unroll * 2.0 + 0.25))
		var k: float = tp.t * (TAPE.unroll * 2.0 + 0.25)
		tp.a.scale.x = maxf(0.001, _easeOutCubic((k - 0.25) / TAPE.unroll))
		tp.b.scale.x = maxf(0.001, _easeOutCubic((k - 0.25 - TAPE.unroll) / TAPE.unroll))

func _addTape(w) -> void:
	var g = game
	var pivot = _f(w, "pivot")
	var top = _f(w, "top")
	var sill = _f(w, "sill")
	if not (pivot is Node3D or pivot is Transform3D) or top == null or sill == null or not is_finite(float(top)) or not is_finite(float(sill)):
		return
	var wid = _f(w, "id")
	_removeTape(wid, false)
	var roots = _f(g.level, "areaRoots", {})
	var parent = roots.get(_f(w, "area")) if roots is Dictionary and roots.get(_f(w, "area")) else g.scene
	var grp := DAU.node3d("gaffer_x:%s" % wid)
	# the pivot's placement (the windows port keeps it as a Transform3D: the JS pivot's matrix)
	var pxf: Transform3D = pivot.transform if pivot is Node3D else pivot
	grp.position = pxf.origin
	grp.quaternion = pxf.basis.get_rotation_quaternion()
	var wwv = _f(w, "width")
	var W: float = (float(wwv) if wwv else 1.6) * 0.96
	var H: float = (float(top) - float(sill)) * 0.92
	var yc: float = float(sill) + (float(top) - float(sill)) / 2.0
	var zc: float = float(_wallT()) / 2.0 + 0.06 + 6 * 0.012 + 0.035
	var len := Vector2(W, H).length()
	var ang := atan2(H, W)
	var mk := func(a: float, zOff: float) -> Node3D:
		var pv := DAU.node3d("tape")
		pv.position = Vector3(-cos(a) * len / 2.0, yc - sin(a) * len / 2.0, zc + zOff)
		pv.rotation.z = a
		var m := MeshInstance3D.new()
		m.mesh = _tapeGeo
		if _mats.tape is Material:
			m.material_override = _mats.tape
		m.scale = Vector3(len, 1, 1)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pv.add_child(m)
		pv.scale.x = 0.001
		grp.add_child(pv)
		return pv
	var a: Node3D = mk.call(ang, 0.0)
	var b: Node3D = mk.call(PI - ang, 0.006)
	b.position = Vector3(cos(ang) * len / 2.0, yc - sin(ang) * len / 2.0, zc + 0.006)
	parent.add_child(grp)
	_tapes[wid] = {"group": grp, "a": a, "b": b, "t": 0.0}
	var v: Vector3 = (_gxf(pivot) if pivot is Node3D else pxf) * Vector3(0, yc, zc)
	_m(g.fx, "burst", [v, {"shape": "confetti", "count": 6, "colors": ["#DDE3EA", "#FFFFFF", "#AEB6C2"], "speed": 2, "life": 0.7, "size": 0.05}])

func _wallT() -> float:
	var L = load("res://scripts/game/sponsors.gd")
	if L != null:
		var lay: Dictionary = L._layout()
		return float(lay.get("WALL_T", 0.3))
	return 0.3

func _tearTape(id) -> void:
	if not id or not _tapes.has(id):
		return
	_removeTape(id, true)

func _removeTape(id, fx: bool) -> void:
	var tp = _tapes.get(id)
	if tp == null:
		return
	if fx:
		var v: Vector3 = _gxf(tp.group).origin
		v.y += 1.2
		_m(game.fx, "burst", [v, {"shape": "confetti", "count": 8, "colors": ["#DDE3EA", "#AEB6C2"], "speed": 3, "life": 0.9, "size": 0.06}])
	_free(tp.group)
	_tapes.erase(id)

# --- ONE TAKE
func _updateVignette(rdt: float) -> void:
	var g = game
	var left: float = float(active.get("one_take", 0.0))
	var want := minf(1.0, left / 1.2) if left > 0 else 0.0
	_vigAmt += (want - _vigAmt) * minf(1.0, rdt * (5.0 if want > _vigAmt else 4.0))
	if _vigAmt < 0.003:
		_vigAmt = 0.0
	if _vig == null:
		return
	_vig.visible = _vigAmt > 0
	_vigMat.set_shader_parameter("uAmt", _vigAmt)
	_vigMat.set_shader_parameter("uTime", float(g.time.realNow) if g.time.realNow else 0.0)
	# the main-camera gate (JS: uOn = camera === game.camera, set in onBeforeRender)
	var cam: Camera3D = g.camera
	_vigMat.set_shader_parameter("uOn", 1.0 if cam != null else 0.0)
	if cam != null:
		_vigMat.set_shader_parameter("uMainMask", cam.cull_mask)

# ------------------------------------------------------------------------------------------------ shared
func _buildShared() -> void:
	var g = game
	_stampGeo = QuadMesh.new()
	_stampGeo.size = Vector2(1, 1)
	_tapeGeo = QuadMesh.new()
	_tapeGeo.size = Vector2(1, TAPE.width)
	_tapeGeo.center_offset = Vector3(0.5, 0, 0)
	_ringGeo = PlaneMesh.new()
	_ringGeo.size = Vector2(1, 1)
	var stampTex = stampTexture()
	var tapeTex = tapeTexture()
	var ringTex = ringTexture()
	var stamp := StandardMaterial3D.new()
	stamp.resource_name = "powerups:stamp"
	stamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if stampTex is Texture2D:
		stamp.albedo_texture = stampTex
	stamp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stamp.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	stamp.cull_mode = BaseMaterial3D.CULL_DISABLED
	stamp.disable_fog = true
	stamp.render_priority = 5
	var tape = null
	if g.mats and g.mats.has_method("toon"):
		tape = g.mats.toon("#FFFFFF", {"map": tapeTex, "rough": 0.5, "metal": 0.25, "transparent": true, "alphaTest": 0.35, "keepColor": true, "side": "double"})
	if not (tape is Material):
		var tm := StandardMaterial3D.new()
		if tapeTex is Texture2D:
			tm.albedo_texture = tapeTex
		tm.roughness = 0.5
		tm.metallic = 0.25
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		tm.alpha_scissor_threshold = 0.35
		tm.cull_mode = BaseMaterial3D.CULL_DISABLED
		tape = tm
	var ring := StandardMaterial3D.new()
	ring.resource_name = "powerups:ring"
	ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if ringTex is Texture2D:
		ring.albedo_texture = ringTex
	ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring.disable_fog = true
	ring.render_priority = 3
	_mats = {"stamp": stamp, "tape": tape, "ring": ring}
	# ONE TAKE gold vignette (main camera only)
	var sh := Shader.new()
	sh.code = VIG_SHADER
	var mat := ShaderMaterial.new()
	mat.resource_name = "powerups:one_take_vignette"
	mat.shader = sh
	mat.render_priority = Material.RENDER_PRIORITY_MAX
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var vig := MeshInstance3D.new()
	vig.name = "one_take_vignette"
	vig.mesh = q
	vig.material_override = mat
	vig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vig.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))   # frustumCulled = false
	vig.visible = false
	if g.scene:
		g.scene.add_child(vig)
	_vig = vig
	_vigMat = mat

# ------------------------------------------------------------------------------------------------ prop helper
# Bob + spin + each item's own loop. t = seconds (use the drop's age). (src/props/sponsors.js animateDrop)
static func animateDrop(drop: Node3D, t: float) -> void:
	var u := DAU.ud(drop)
	var p = u.get("parts")
	if not (p is Dictionary) or not (p.get("float") is Node3D):
		return
	p.float.position.y = 1.0 + sin(t * TAU) * 0.05
	p.float.rotation.y = t * (PI / 2.0)
	var type = u.get("dropType")
	if type == "cancelled" and p.get("stamp") is Node3D:
		var c := fmod(t * 1.4, 1.0)   # lift, slam, hold
		var lift := 0.0
		if c < 0.55:
			lift = DAU.smoothstep3(c, 0.0, 0.5) * 0.09
		elif c < 0.62:
			lift = 0.09 * (1.0 - (c - 0.55) / 0.07)
		p.stamp.position.y = -0.1 + lift - (0.004 if c >= 0.62 and c < 0.7 else 0.0)
	elif type == "full_reel" and p.get("reel") is Node3D:
		p.reel.rotation.z = -t * 5.0
	elif type == "one_take" and p.get("clapper") is Node3D:
		var c := fmod(t * 1.2, 1.0)
		p.clapper.rotation.z = -0.34 * DAU.smoothstep3(c, 0.0, 0.6) if c < 0.7 else -0.34 * (1.0 - (c - 0.7) / 0.06) * (1.0 if c < 0.76 else 0.0)
	elif type == "sweeps_week" and p.get("needle") is Node3D:
		p.needle.rotation.z = -0.9 + sin(t * 9.0) * 0.08 + sin(t * 2.3) * 0.12
	elif type == "gaffer_tape" and p.get("roll") is Node3D:
		p.roll.rotation.y = t * 2.0
