# DEAD AIR — THE UPLINK, the pack-a-punch of the Transmitter Yard (port of src/game/uplink.js; GDD §10.4, §9.5,
# §15 Uplink cues, §18.15 events). Owned by the uplink-powerups engineer. Keeps the stub contract: aligned, busy,
# weaponId (+ reset()).
#
# BUILD (init, into level.areaRoots.yard, reusing props a room may already have placed): 'uplink_dish' (5 m dish on
#   its az-el turntable; parts yaw/tilt/rimBulbs) at uplink_dish, 'uplink_cradle' (feed horn + gun clamp + R/G/B lamps)
#   at uplink_cradle, 'uplink_crank' (hand wheel, glowing grip, elevation gauge) at uplink_crank, 'uplink_booth' (control
#   kiosk, blinking lamp panel) beside them, and the satellite 'skylark_13' crossing the northern sky on a 60 s pass
#   (118 m out, x5 so it reads; fades in and out of the Earth's shadow at both ends; red beacon, green once locked).
#   Plus the effect rigs: the braided SMPTE colour-bar beam, three downlink streams, lamp beams, the R/G/B weapon
#   copies, the colour-bar aurora ribbon (vertex-waved additive curtain across the north sky), flare + flash sprites.
# ALIGNMENT (once per game, needs power): the crank prompt is [E] + plug before power (E: bzzt + the grip jiggles),
#   then a key-only hold of T.uplink.alignHold s. Cranking spins the wheel, whirs (dish_crank) and swings the dish up
#   out of its droop, lighting the rim bulbs like a progress ring; the hold progress survives letting go but decays
#   0.5 s per second (the dish sags), and every hit taken while cranking halves it (clunk + sparks). Lock: the dish
#   overshoots into place, Skylark-13's beacon turns green, dish_lock pips, the rim chasers race, the horn lamps glow,
#   the droop collider under the rim goes away, emits machine:dish_aligned {}.
# UPGRADE (cradle prompt [E] 5000 with a normal weapon, [E] 2500 with an upgraded one = Re-Uplink; one at a time)
#   0.00 the weapon is yanked magnetically out of the hand into the clamp (weapons.takeCurrent: auto-switch / melee),
#        CLANG, the jaws snap shut; the magnet's kick shoves the hero a step back-left (the shoulder camera then sees
#        the clamp). 0.0-0.8 the dish swings round onto Skylark-13, motor whir, the rim chasers race in colour bars.
#   0.8-1.8 COLOUR SPLIT: the R/G/B lamps beam at the gun, which splits into three additive copies orbiting 0.3 m
#        apart (uplink_triad). 1.8-2.6 UPLINK: the copies stretch up and braid into the colour-bar beam that shoots to
#        the satellite (the dish glows in the beam's shifting colours); every TV cuts to LIVE VIA SATELLITE
#        (screens.override 'satellite' until the snap + screens.setInsert:
#        the weapon on the insert turntable, upgraded at the end), uplink_vwoom, crowd ooh, 1 kHz from the TVs.
#   2.6-5.0 Skylark-13 flares, the aurora unfurls across the sky (uplink_aurora), Yard zombies gawk up for 0.8 s.
#   4.3 the beam lifts off; 4.4 three thin streams race down, meet in the clamp and swell (the signal colour thickest
#        and brightest) until
#   5.00 DOWNLINK: they snap together in a white flash into the upgraded weapon in the clamp (Chromacast, signal
#        colour rolled at the start), sparkle burst, uplink_snap + uplink_fanfare, hud.chyron(upgraded name) (else
#        emits machine:uplink_ready with it), machine:uplink_ready {weaponId, signal}; the dish returns to park.
#   5-20 the upgraded weapon rises out of the horn onto a signal-coloured light cone and turns slowly; 15 s to take it
#        with E (weapons.give(id, {upgraded:true, signal, source:'uplink'}), full ammo,
#        machine:uplink_take {weaponId}); from 10 s it flickers like bad reception (uplink_flicker, accelerating
#        ticks); at 15 s it is beamed back up and lost (uplink_lost, machine:uplink_lost {weaponId}).
#   Re-Uplink: a 3.0 s split -> converge -> snap (no beam, aurora or LIVE card) rolling a DIFFERENT signal colour,
#   then the same collection window. Disabled during the boss fight (machine:boss_start: lamps dark; a weapon still in
#   the machine is handed back upgraded) until egg:complete / game:victory / game:over / a new game.
# API (game.uplink)
#   aligned, busy, weaponId, signal_ (JS `signal`), phase ('idle'|'seq'|'ready'), seqT, readyT, reroll, disabled, align (hold s)
#   status() -> snapshot       satellitePos() -> Vector3 (world)
#   debugAlign()  debugUpgrade(weaponId?, { free=true })  debugTake()  debugSkip(t)  debugHit()
# EVENTS machine:dish_aligned {}, machine:uplink_start {weaponId}, machine:uplink_ready {weaponId, signal, name},
#   machine:uplink_take {weaponId}, machine:uplink_lost {weaponId}. Listens: player:hurt, machine:boss_start,
#   egg:complete, game:victory, game:over.
# TESTS tools/scenarios/uplink-powerups_uplink.cjs (params test=1&nozombies=1&god=1&power=1&doors=1&points=20000).
#
# Godot port notes
# * The props are prop-library instances (game.props.place / build). The effect meshes are built here: the beam /
#   streams / lamp beams / light cone are open cylinders (three's CylinderGeometry torso, rebuilt as ArrayMeshes),
#   the aurora is an ArrayMesh curtain whose folds are waved in its vertex shader every frame (like the JS), the
#   flare / flash / halo / beam head are camera-facing sprite quads (THREE.Sprite). The GLSL shaders are ported to
#   Godot shading language 1:1 (uniform names kept); canvas textures (glow / cone) are drawn with DACanvas.
# * The prop helpers of src/props/machines.js the Uplink calls (setUplinkPose, setCrankGlow, setBoothLamps) are
#   ported below as static functions of the same names.
# * JS InstancedMesh parts (rimBulbs, booth lamps) are parents with <name>_<i> children (SPEC §5.4); setColorAt is
#   the "instanceColor" instance shader parameter (sRGB Color, multiplies like three's instanceColor).
# * satellitePos(out) returns the Vector3 (value types). warmup() (shader precompile) is not ported.
# * Node names cannot contain ':' in Godot: 'uplink_gun:<id>' is the node "uplink_gun_<id>".
# * Renames (§3.2): the field `signal` (a GDScript keyword) is `signal_`; event payload keys stay "signal".
extends RefCounted

const TAU := PI * 2.0
const DEG := PI / 180.0
const SIGNALS := ["hot_mic", "laugh_track", "cold_open"]
const RGB := ["#FF3B30", "#3BFF5A", "#3B7BFF"]
const LAMP_COL := ["#FF5A3C", "#52E04A", "#7FD4FF"]   # PAL.hotMic, PAL.laughTrack, PAL.coldOpen
const BARS := ["#E8E8E8", "#F4E03A", "#3FD6E0", "#52D24A", "#D64FD6", "#E4473A", "#3A58E4"]
const FULL := {"land": 0.24, "swivel": 0.8, "split": 0.8, "beam": 1.8, "beamTop": 2.25, "flare": 2.6, "retract": 4.3, "streams": 4.4, "streamsDown": 4.82, "snap": 5.0}
const RE := {"land": 0.24, "split": 0.45, "converge": 2.2, "snap": 3.0}
const SAT := {"period": 60.0, "radius": 118.0, "scale": 5.0, "b0": 72.0, "b1": -72.0, "el0": 24.0, "elPeak": 36.0, "busyRate": 0.1}
const BOOTH := {"pos": [41.95, 0.0, -15.1], "rotY": PI / 2.0}
const DISH_DEF := {"droop": -0.33, "aligned": 0.95, "pivotY": 3.3}
const AURORA := {"radius": 100.0, "span": 150.0 * DEG, "base": 13.0 * DEG, "arch": 9.0 * DEG, "height": 21.0 * DEG, "segS": 144, "segV": 10}
const DECAY := 0.5
const GUN := {"rest": 0.1, "show": 0.3}
const ORBIT_R := 0.22
const BOOTH_COLS := ["#FF3B30", "#FFD23A", "#52E04A", "#7FE7FF", "#FF8A2A"]
const UP := Vector3(0, 1, 0)

# ============================================================================================== shaders
const BAR_GLSL := """
vec3 barCol(float i0) {
	float i = mod(i0, 7.0);
	if (i < 1.0) return vec3(0.92, 0.92, 0.95);
	if (i < 2.0) return vec3(1.0, 0.86, 0.12);
	if (i < 3.0) return vec3(0.12, 0.86, 0.95);
	if (i < 4.0) return vec3(0.18, 0.92, 0.2);
	if (i < 5.0) return vec3(0.92, 0.18, 0.9);
	if (i < 6.0) return vec3(1.0, 0.18, 0.12);
	return vec3(0.16, 0.26, 1.0);
}
"""

# Braided colour-bar beam: open cylinder along +y (0 = horn .. 1 = satellite), helical SMPTE stripes scrolling up,
# hot core, travelling pulses. uHead / uTail clip the visible stretch (shoot up / lift off).
const BEAM_VERT := """
varying float vFace;
void vertex() {
	vec3 mv = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vFace = abs(dot(n, normalize(-mv)));
}
"""
const BEAM_FRAG := """
uniform float uTime;
uniform float uLen = 100.0;
uniform float uHead;
uniform float uTail;
uniform float uAlpha = 1.0;
void fragment() {
	vec2 vUv = UV;
	if (vUv.y > uHead || vUv.y < uTail) discard;
	float m = vUv.y * uLen;
	float tw = vUv.x * 7.0 + m * 0.32 - uTime * 3.2;
	vec3 c = barCol(floor(tw));
	float f = fract(tw);
	c *= 0.82 + 0.18 * smoothstep(0.0, 0.1, f) * smoothstep(1.0, 0.9, f);
	float core = pow(clamp(vFace, 0.0, 1.0), 2.2);
	float soft = smoothstep(0.0, 0.45, vFace);
	float pulse = 0.8 + 0.35 * pow(clamp(0.5 + 0.5 * sin(m * 0.7 - uTime * 20.0), 0.0, 1.0), 3.0);
	vec3 col = c * (0.55 + 0.35 * core) * pulse + vec3(1.0) * pow(core, 5.0) * 0.18;
	float head = smoothstep(uHead - 0.03, uHead, vUv.y);
	col += vec3(0.9) * head;
	float base = 0.55 + 0.45 * smoothstep(0.0, 0.05, vUv.y);
	float fade = 1.0 - 0.45 * smoothstep(0.55, 1.0, vUv.y);
	ALBEDO = col * soft * base * uAlpha * fade * 0.95;
	ALPHA = 1.0;
}
"""

# Downlink stream: thin solid-colour line from the satellite (y = 1) down to the clamp (y = 0).
const STREAM_FRAG := """
uniform float uTime;
uniform float uHead;
uniform float uAlpha = 1.0;
uniform float uLen = 100.0;
uniform vec3 uColor = vec3(1.0);
void fragment() {
	vec2 vUv = UV;
	if (vUv.y < 1.0 - uHead) discard;
	float m = vUv.y * uLen;
	float pulse = 0.75 + 0.3 * pow(clamp(0.5 + 0.5 * sin(m * 1.4 + uTime * 30.0), 0.0, 1.0), 4.0);
	float tip = smoothstep(1.0 - uHead + 0.02, 1.0 - uHead, vUv.y);
	float soft = smoothstep(0.0, 0.5, vFace);
	vec3 col = mix(uColor, vec3(1.0), pow(clamp(vFace, 0.0, 1.0), 6.0) * 0.25) * (0.5 + 0.45 * vFace) * pulse + vec3(1.0) * tip * 0.5;
	ALBEDO = col * soft * uAlpha;
	ALPHA = 1.0;
}
"""

# Colour-bar aurora: a curtain across the north sky. Folds and ripples in the vertex shader; smooth SMPTE colours
# along the ribbon, a hot lower hem fading upward, fine vertical rays; unfurls from the satellite's bearing (uS0).
# aS / aV (the JS attributes) travel in UV.
const AURORA_VERT := """
uniform float uTime;
varying float vS;
varying float vV;
void vertex() {
	float aS = UV.x;
	float aV = UV.y;
	vS = aS; vV = aV;
	vec3 p = VERTEX;
	float w = sin(aS * 34.0 + uTime * 0.8) * 0.65 + sin(aS * 83.0 - uTime * 1.55) * 0.35;
	p += NORMAL * w * (2.5 + aV * 7.0);
	// the whole curtain billows up and down along its length (an undulating hem), the top sways more
	float hem = sin(aS * 9.0 + uTime * 0.55) * 4.5 + sin(aS * 23.0 - uTime * 0.9) * 1.8 + sin(aS * 57.0 + uTime * 1.7) * 0.6;
	p.y += hem + sin(aS * 21.0 + uTime * 1.2) * 2.6 * aV;
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	p += side * sin(aS * 15.0 + uTime * 0.7) * 3.0 * aV;
	VERTEX = p;
}
"""
const AURORA_FRAG := """
uniform float uAlpha;
uniform float uReveal;
uniform float uS0 = 0.5;
vec3 bars(float x0) {
	float x = fract(x0) * 7.0;
	float i = floor(x);
	float f = fract(x);
	return mix(barCol(i), barCol(i + 1.0), smoothstep(0.55, 1.0, f));
}
void fragment() {
	float d = abs(vS - uS0);
	float rev = smoothstep(uReveal * 0.62, uReveal * 0.62 - 0.07, d);
	vec3 c = bars(vS * 2.2 - uTime * 0.04);
	float band = smoothstep(0.0, 0.07, vV) * (1.0 - smoothstep(0.05, 1.0, vV));
	float rays = 0.6 + 0.4 * sin(vS * 520.0 + uTime * 2.2) * sin(vS * 190.0 - uTime * 1.3);
	float hem = exp(-vV * 10.0) * smoothstep(0.0, 0.02, vV);
	float ends = smoothstep(0.0, 0.1, vS) * smoothstep(1.0, 0.9, vS);
	vec3 col = c * (band * band * rays * 1.1 + hem * 1.25) + vec3(1.0) * hem * 0.25;
	ALBEDO = col * uAlpha * rev * ends;
	ALPHA = 1.0;
}
"""
const FX_MODES := "render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;\n"

var game
var aligned := false
var busy := false
var weaponId = null
var signal_ = null
var phase := "idle"
var seqT := 0.0
var readyT := 0.0
var reroll := false
var disabled := false
var align := 0.0
var built := false
var U: Dictionary                      # T.uplink
var SIGNAL_COLORS: Dictionary          # weapon_defs.gd SIGNAL_COLORS

var _satT := 0.0
var _tilt := {"x": DISH_DEF.droop, "v": 0.0}
var _yaw := {"x": 0.0, "v": 0.0}
var _cranking := false
var _crankLoop = null
var _lockT := -1.0
var _cues: Array = []
var _cue := 0
var _t := 0.0
var _gun: Node3D = null
var _fly = null
var _take = null
var _lost = null
var _jaw := {"x": 1.0, "v": 0.0, "target": 1.0}
var _copies: Array = []
var _glowCache := {}
var _time := {"value": 0.0}

# build products
var root: Node3D = null
var dish: Node3D = null
var cradle: Node3D = null
var crank: Node3D = null
var booth: Node3D = null
var dishRig := {}
var cradleRig := {}
var crankRig := {}
var P := {"dish": {}, "cradle": {}, "crank": {}, "booth": {}}
var pivot := Vector3.ZERO
var hornPos := Vector3.ZERO
var gunSlot: Node3D = null
var holder: Node3D = null
var slotPos := Vector3.ZERO
var slotQuat := Quaternion.IDENTITY
var _pool = null
var _dishGlow: Array = []
var _dishGlowOn := false
var _dishGlowK := 0.0
var _dishGlowMats: Array = []
var _beaconMats := {}
var satParts := {}
var sat: Node3D = null
var satModel: Node3D = null
var satHalo: MeshInstance3D = null
var satFlare: MeshInstance3D = null
var satPos := Vector3.ZERO
var _satAlpha := 1.0
var beam: MeshInstance3D = null
var beamHead: MeshInstance3D = null
var streams: Array = []
var lampBeams: Array = []
var _copyMats: Array = []
var splitRoot: Node3D = null
var flash: MeshInstance3D = null
var aurora: MeshInstance3D = null
var cone: MeshInstance3D = null
var _crankItem = null
var _cradleItem = null
var _flyer: Node3D = null

# per-frame state (JS fields created lazily)
var _wasHolding := false
var _wheelV := 0.0
var _jiggle := 0.0
var _gripLevel := -1.0
var _crankHeldAt := 0.0
var _droopWasOff := false
var _prevSignal = null
var _retractT := -1.0
var _flareT := -1.0
var _flashT := -1.0
var _auroraT := -1.0
var _splitT := 0.0
var _streamT := 0.0
var _streamSpark := false
var _popT := -1.0
var _glintT := 0.0
var _flickT := 0.0
var _flickOff := false
var _jx := 0.0
var _snd := 0.0
var _tickPlayed := false
var _lostStream = null
var _insertObj = null
var _override = null
var _lampFlash := 0.0
var _lightKey = null
var _poolI := -1.0
var _boothDark = null
var _consoleOn = null
var _consoleOff = null
# MP (see the header)
const MP_GRACE := 0.25
var crankUser := 0                     # peer id cranking the dish (0 = nobody), host-authoritative
var _user := 0                         # peer id whose weapon is in the machine
var _useId := 0                        # host counter of upgrades (stale take requests are ignored)
var _crankSent := false                # this peer reported "holding" to the host
var _crankSendT := 0.0
var _crankDenied := false              # another peer won the crank: off until E is released
var _lockPending := 0.0                # our hold completed, waiting for net_aligned (s)
var _reqT := -1.0                      # an insert request is pending (s)
var _reqData: Array = []
var _userGone := ""                    # host: the user went "down" / "offair" / "left" during the upgrade
var _stateT := 0.0

func _init(g) -> void:
	game = g
	U = Config.T.uplink
	SIGNAL_COLORS = {"hot_mic": Config.PAL.hotMic, "laugh_track": Config.PAL.laughTrack, "cold_open": Config.PAL.coldOpen}
	var wd := "res://scripts/game/weapon_defs.gd"
	if ResourceLoader.exists(wd):
		var s = load(wd)
		if s is Script:
			var sc = s.get("SIGNAL_COLORS")     # static var of weapon_defs.gd (or a constant)
			if not (sc is Dictionary):
				sc = s.get_script_constant_map().get("SIGNAL_COLORS")
			if sc is Dictionary:
				SIGNAL_COLORS = sc

# ============================================================================================ lifecycle
func init() -> void:
	var g = game
	_build()
	var ev = g.events
	ev.on("player:hurt", func(_p = null): _onHurt())
	ev.on("machine:boss_start", func(_p = null): _setDisabled(true))
	for e in ["egg:complete", "game:victory", "game:over"]:
		ev.on(e, func(_p = null): _setDisabled(false))
	_toIdle(true)

func reset() -> void:
	disabled = false
	aligned = false
	align = 0.0
	crankUser = 0
	_user = 0
	_crankSent = false
	_crankDenied = false
	_lockPending = 0.0
	_reqT = -1.0
	_userGone = ""
	_lockT = -1.0
	_satT = game.rand() * SAT.period * 0.6 if game.has_method("rand") else 0.0
	_toIdle(true)
	_tilt.x = DISH_DEF.droop
	_tilt.v = 0.0
	_yaw.x = 0.0
	_yaw.v = 0.0
	if dish != null:
		setUplinkPose(dish, {"tilt": _tilt.x, "yaw": 0.0})
	var col = X.g(game.level, "col")
	if col != null and col.has_method("setEnabled"):
		col.setEnabled("uplink_droop", true)
	if _droopWasOff and game.nav != null and X.g(game.nav, "built", false):
		game.nav.build()
	_droopWasOff = false
	_stopCrank()

# ============================================================================================ build
func _build() -> void:
	var g = game
	var L = g.level
	var roots = X.g(L, "areaRoots", {})
	var A = X.g(L, "anchors", {})
	root = roots.get("yard") if roots is Dictionary else null
	if root == null or not A.has("uplink_dish") or not A.has("uplink_cradle") or not A.has("uplink_crank"):
		push_error("[uplink] build failed: yard / uplink anchors missing")
		return
	var found := {}
	DAU.traverse(root, func(o):
		var oid = DAU.ud(o).get("id")
		if oid is String and (oid.begins_with("uplink_") or oid == "skylark_13") and not found.has(oid):
			found[oid] = o)

	# --- props
	var a = A.uplink_dish
	var ap: Vector3 = DAU.v3(X.g(a, "pos"))
	dish = found.get("uplink_dish")
	if dish == null:
		dish = g.props.place(root, "uplink_dish", {"pos": [ap.x, 0.0, ap.z], "rotY": X.g(a, "rotY", PI), "area": "yard", "colliders": false, "tag": "machine"})
		_dishColliders()
	var c = A.uplink_cradle
	var cp: Vector3 = DAU.v3(X.g(c, "pos"))
	cradle = found.get("uplink_cradle")
	if cradle == null:
		cradle = g.props.place(root, "uplink_cradle", {"pos": [cp.x, 0.0, cp.z], "rotY": X.g(c, "rotY", PI), "area": "yard", "tag": "machine"})
	var k = A.uplink_crank
	var kp: Vector3 = DAU.v3(X.g(k, "pos"))
	crank = found.get("uplink_crank")
	if crank == null:
		crank = g.props.place(root, "uplink_crank", {"pos": [kp.x, 0.0, kp.z], "rotY": X.g(k, "rotY", PI), "area": "yard", "tag": "machine"})
	booth = found.get("uplink_booth")
	if booth == null:
		booth = g.props.place(root, "uplink_booth", {"pos": BOOTH.pos, "rotY": BOOTH.rotY, "area": "yard", "lights": false, "tag": "machine"})
	# draw-call diet: only the big pieces cast into the (player-following) shadow map
	_trimShadows(dish, 0.7)
	for o in [cradle, crank, booth]:
		_trimShadows(o, 0.42)
	dishRig = DISH_DEF.duplicate()
	var rig = DAU.ud(dish).get("rig")
	if rig is Dictionary:
		dishRig.merge(rig, true)
	var crig = DAU.ud(cradle).get("rig")
	cradleRig = crig if crig is Dictionary else {"slotY": 1.3, "jawOpenF": -0.5, "jawOpenB": 0.5, "jawClosed": 0.0, "beamFrom": [0.0, 1.5, 0.08]}
	var krig = DAU.ud(crank).get("rig")
	crankRig = krig if krig is Dictionary else {"hubY": 1.0, "needleMin": -1.05, "needleMax": 1.05}
	P = {"dish": _parts(dish), "cradle": _parts(cradle), "crank": _parts(crank), "booth": _parts(booth)}
	# every part the Uplink rotates follows three's XYZ Euler order
	for grp in [P.dish, P.cradle, P.crank]:
		for key in ["yaw", "tilt", "jawF", "jawB", "wheel", "needle"]:
			if grp.get(key) is Node3D:
				grp[key].rotation_order = EULER_ORDER_XYZ
	pivot = X.worldXform(dish) * Vector3(0, float(dishRig.pivotY), 0)
	hornPos = X.worldXform(cradle) * DAU.v3(cradleRig.get("beamFrom", [0.0, 1.5, 0.08]))
	gunSlot = P.cradle.get("gunSlot") if P.cradle.get("gunSlot") is Node3D else cradle
	holder = DAU.node3d("uplink_gun_holder")
	holder.position = Vector3(0, GUN.rest, 0)
	gunSlot.add_child(holder)
	var hx := X.worldXform(holder)
	slotPos = hx.origin
	slotQuat = hx.basis.get_rotation_quaternion()
	var bulbs = P.dish.get("rimBulbs")
	if bulbs is Node3D and not DAU.ud(bulbs).has("_instColors"):
		# the build's colours (marquee gold x 0.1), kept for getColorAt
		for i in X.instCount(bulbs):
			X.instSetColor(bulbs, i, X.lin(Config.PAL.marqueeGold) * 0.1)
	if P.booth.get("lamps") is Node3D:
		setBoothLamps(booth, 0.37)
	# booth light (enabled with power) + horn light (after alignment) + a warm pool under the rim
	var lights = g.lights
	var bp: Vector3 = X.worldXform(booth) * Vector3(0, 1.2, -1.2)
	if lights != null and lights.has_method("addAnchor"):
		lights.addAnchor({"pos": DAU.arr3(bp), "color": "#7FE7FF", "intensity": 1.3, "distance": 4.5, "area": "yard", "id": "uplink_booth"})
		lights.addAnchor({"pos": [hornPos.x, hornPos.y + 0.4, hornPos.z - 0.2], "color": "#FFFFFF", "intensity": 1.8, "distance": 8, "area": "yard", "id": "uplink_horn"})
	if lights != null and lights.has_method("setAnchor"):
		lights.setAnchor("uplink_booth", {"enabled": false})
		lights.setAnchor("uplink_horn", {"enabled": false})
	_pool = null
	if g.fx != null and g.fx.has_method("lightPool"):
		_pool = g.fx.lightPool(Vector3(pivot.x, 0.02, pivot.z + 0.8), 3.6, Config.PAL.marqueeGold, 0.0)

	_buildDishGlow()
	_buildSatellite()
	_buildFx()
	_registerInteract()
	if g.nav != null and X.g(g.nav, "built", false):
		g.nav.build()
	built = true

func _parts(o: Node) -> Dictionary:
	var p = DAU.ud(o).get("parts")
	return p if p is Dictionary else {}

# Energised dish: emissive variants of the dish's toon materials (unique to it), swapped in during the uplink so
# the rainbow of the beam washes over it (its back faces the camera once it swings onto the satellite).
func _buildDishGlow() -> void:
	var g = game
	_dishGlow = []
	_dishGlowOn = false
	_dishGlowK = 0.0
	var cache := {}
	var r: Node = P.dish.get("tilt") if P.dish.get("tilt") is Node3D else dish
	DAU.traverse(r, func(o):
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null or DAU.ud(o).get("instanced"):
			return
		var mi := o as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if not X.isToon(m):
				continue
			var lit = cache.get(m)
			if lit == null:
				lit = g.mats.variant(m, {"emissive": "#000000", "emissiveIntensity": 1, "name": "uplink_dish_glow:%d" % cache.size()})
				cache[m] = lit
			if lit != m:
				_dishGlow.append({"mesh": mi, "surface": s, "base": m, "lit": lit}))
	_dishGlowMats = []
	for d in _dishGlow:
		if not _dishGlowMats.has(d.lit):
			_dishGlowMats.append(d.lit)

func _setDishGlow(k: float, color: String) -> void:
	var on := k > 0.004
	if on != _dishGlowOn:
		_dishGlowOn = on
		for d in _dishGlow:
			d.mesh.set_surface_override_material(d.surface, d.lit if on else d.base)
	if not on:
		return
	var c: Color = (X.lin(color).lerp(Color(1, 1, 1), 0.5) * k)
	c.a = 1.0
	var srgb := c.linear_to_srgb()
	for m in _dishGlowMats:
		m.set("emissive", srgb)

func _trimShadows(r: Node, minR: float) -> void:
	DAU.traverse(r, func(o):
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null:
			return
		var mi := o as MeshInstance3D
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return
		var s: Vector3 = X.worldXform(mi).basis.get_scale()
		if X.boundingRadius(mi.mesh) * maxf(s.x, maxf(s.y, s.z)) < minR:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

# The dish's local colliders, placed by hand so the one under the drooped rim can be switched off once aligned.
func _dishColliders() -> void:
	var col = X.g(game.level, "col")
	if col == null:
		return
	var xf := X.worldXform(dish)
	var cls = DAU.ud(dish).get("colliders")
	if not (cls is Array):
		return
	for cl in cls:
		var mn: Vector3 = DAU.v3(cl.min)
		var mx: Vector3 = DAU.v3(cl.max)
		var bb := AABB()
		for i in 8:
			var p := Vector3(mx.x if i & 1 else mn.x, mx.y if i & 2 else mn.y, mx.z if i & 4 else mn.z)
			var wp: Vector3 = xf * p
			bb = AABB(wp, Vector3.ZERO) if i == 0 else bb.expand(wp)
		var droop: bool = cl.get("opts") is Dictionary and cl.opts.get("tag") == "uplink_droop"
		col.addBox(DAU.arr3(bb.position), DAU.arr3(bb.end), {"tag": "machine", "id": "uplink_droop"} if droop else {"tag": "machine", "id": "uplink_dish"})

func _buildSatellite() -> void:
	var g = game
	var sm: Node3D = g.props.build("skylark_13", {"beacon": "red"})
	# 118 m out, past the Yard fog: every material needs fog off (toon ones through mats.variant, which keeps the
	# cartoon shader patch; plain glows are cloned)
	var cache := {}
	DAU.traverse(sm, func(o):
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null:
			return
		var mi := o as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			if src == null:
				continue
			if not cache.has(src):
				var m = g.mats.variant(src, {"fog": false}) if X.isToon(src) else null
				if m == null or m == src:
					m = src.duplicate()
					if "fog" in m:
						m.set("fog", false)
					elif m is BaseMaterial3D:
						(m as BaseMaterial3D).disable_fog = true
				cache[src] = m
			mi.set_surface_override_material(s, cache[src]))
	_beaconMats = {
		"red": X.basicMat(X.lin(Config.PAL.onAirRed) * 3.0, false, false, false),
		"green": X.basicMat(X.lin(Config.PAL.laughTrack) * 3.0, false, false, false),
		"flare": X.basicMat(Color(6, 6, 6), false, false, false),
		"off": X.basicMat(X.lin("#3A1A1A"), false, false, false),
	}
	satParts = _parts(sm)
	if satParts.get("beacon") is GeometryInstance3D:
		satParts.beacon.material_override = _beaconMats.red
	var h := DAU.node3d("skylark_13_orbit")
	sm.scale = Vector3.ONE * SAT.scale
	sm.position.y = -0.7 * SAT.scale
	h.add_child(sm)
	# the blinking beacon halo that makes it read at 118 m
	var halo := X.sprite(_glowTexture(4), X.lin("#FF5A4A"), 1.0, 0)
	halo.scale = Vector3.ONE * 7.0
	halo.position.y = 0.46 * SAT.scale
	h.add_child(halo)
	var fl := X.sprite(_glowTexture(8), Color(1, 1, 1), 0.0, 0)
	fl.scale = Vector3.ONE
	fl.visible = false
	h.add_child(fl)
	root.add_child(h)
	sat = h
	satModel = sm
	satHalo = halo
	satFlare = fl
	satPos = Vector3.ZERO
	_satAlpha = 1.0
	_updateSatellite(0.0)

func _buildFx() -> void:
	var g = game
	# beam
	var cyl := X.cylMesh(1.0, 1.0, 1.0, 20, 0.5)
	var beamMat := X.shaderMat("uplink:beam", FX_MODES + BAR_GLSL + BEAM_VERT + BEAM_FRAG, {"uTime": 0.0, "uLen": 100.0, "uHead": 0.0, "uTail": 0.0, "uAlpha": 1.0})
	beamMat.render_priority = 4
	beam = X.meshNode("uplink_beam", cyl, beamMat)
	beam.visible = false
	root.add_child(beam)
	var head := X.sprite(_glowTexture(6), Color(1, 1, 1), 1.0, 0)
	head.visible = false
	root.add_child(head)
	beamHead = head
	# downlink streams
	streams = []
	for i in RGB.size():
		var m := X.shaderMat("uplink:stream%d" % i, FX_MODES + BEAM_VERT + STREAM_FRAG, {"uTime": 0.0, "uHead": 0.0, "uAlpha": 1.0, "uLen": 100.0, "uColor": X.lin3(LAMP_COL[i])})
		m.render_priority = 4
		var s := X.meshNode("uplink_stream%d" % i, cyl, m)
		s.visible = false
		root.add_child(s)
		streams.append(s)
	# lamp beams (colour split)
	var thin := X.cylMesh(1.0, 1.0, 1.0, 8, 0.5)
	lampBeams = []
	for i in LAMP_COL.size():
		var m := X.basicMat(X.lin(LAMP_COL[i]) * 2.2, true, false, false)
		m.set_shader_parameter("opacity", 0.0)
		var b := X.meshNode("uplink_lamp_beam%d" % i, thin, m)
		b.visible = false
		root.add_child(b)
		lampBeams.append(b)
	# R/G/B copy materials
	_copyMats = []
	for col in RGB:
		var m := X.basicMat(X.lin(col) * 1.25, true, false, false)
		m.resource_name = "uplink:copy"
		m.render_priority = 6
		_copyMats.append(m)
	splitRoot = DAU.node3d("uplink_split")
	gunSlot.add_child(splitRoot)
	splitRoot.position = holder.position
	# flash at the clamp
	var fl := X.sprite(_glowTexture(10), Color(1, 1, 1), 0.0, 0)
	fl.visible = false
	fl.position = slotPos
	root.add_child(fl)
	flash = fl
	# aurora
	aurora = _buildAurora()
	# showcase light cone rising out of the horn while the upgraded weapon waits (signal colour)
	var cm := X.basicMat(Color(1, 1, 1), true, true, false, _coneTexture())
	cm.set_shader_parameter("opacity", 0.0)
	cm.render_priority = 5
	cone = X.meshNode("uplink_cone", X.cylMesh(0.46, 0.3, 0.95, 24, 0.475), cm)
	cone.position = Vector3(slotPos.x, slotPos.y - 0.02, slotPos.z)
	cone.visible = false
	root.add_child(cone)
	root.add_child(aurora)

func _coneTexture():
	var cv = X.newCanvas(64, 128)
	if cv == null:
		return null
	var x = cv.getContext("2d")
	var gr = x.createLinearGradient(0, 128, 0, 0)
	gr.addColorStop(0, "rgba(255,255,255,0.95)")
	gr.addColorStop(0.35, "rgba(255,255,255,0.35)")
	gr.addColorStop(1, "rgba(255,255,255,0)")
	x.fillStyle = gr
	x.fillRect(0, 0, 64, 128)
	x.globalCompositeOperation = "destination-out"
	for i in range(0, 64, 8):
		x.fillStyle = "rgba(0,0,0,0.45)"
		x.fillRect(i, 0, 3, 128)
	return cv.texture

func _glowTexture(rays: int = 0):
	var cv = X.newCanvas(256, 256)
	if cv == null:
		return null
	var x = cv.getContext("2d")
	var gg = x.createRadialGradient(128, 128, 0, 128, 128, 128)
	gg.addColorStop(0, "rgba(255,255,255,1)")
	gg.addColorStop(0.18, "rgba(255,255,255,0.75)")
	gg.addColorStop(0.45, "rgba(255,255,255,0.18)")
	gg.addColorStop(1, "rgba(255,255,255,0)")
	x.fillStyle = gg
	x.fillRect(0, 0, 256, 256)
	if rays:
		x.translate(128, 128)
		for i in rays:
			x.rotate(TAU / rays)
			var lg = x.createLinearGradient(0, 0, 0, -124)
			lg.addColorStop(0, "rgba(255,255,255,0.9)")
			lg.addColorStop(1, "rgba(255,255,255,0)")
			x.fillStyle = lg
			x.beginPath()
			x.moveTo(-5, 0)
			x.lineTo(0, -124)
			x.lineTo(5, 0)
			x.closePath()
			x.fill()
	return cv.texture

func _buildAurora() -> MeshInstance3D:
	var R: float = AURORA.radius
	var span: float = AURORA.span
	var base: float = AURORA.base
	var arch: float = AURORA.arch
	var height: float = AURORA.height
	var segS: int = AURORA.segS
	var segV: int = AURORA.segV
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var C := pivot
	for j in segV + 1:
		for i in segS + 1:
			var s := float(i) / segS
			var v := float(j) / segV
			var b := (s - 0.5) * span
			var e := base + arch * sin(PI * s) + v * height * (0.75 + 0.25 * sin(PI * s))
			var ce := cos(e)
			pos.append(Vector3(C.x + R * sin(b) * ce, C.y + R * sin(e), C.z - R * cos(b) * ce))
			nor.append(Vector3(sin(b), 0, -cos(b)))
			uv.append(Vector2(s, v))
	var idx := PackedInt32Array()
	for j in segV:
		for i in segS:
			var a := j * (segS + 1) + i
			var b := a + 1
			var c := a + segS + 1
			var d := c + 1
			# three (a, c, b) (b, c, d), reversed for Godot's clockwise front faces
			idx.append_array([a, b, c, b, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := X.shaderMat("uplink:aurora", FX_MODES + BAR_GLSL + AURORA_VERT + AURORA_FRAG, {"uTime": 0.0, "uAlpha": 0.0, "uReveal": 0.0, "uS0": 0.5})
	mat.render_priority = -5
	var m := X.meshNode("uplink_aurora", mesh, mat)
	m.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))   # frustumCulled = false
	m.visible = false
	return m

func _registerInteract() -> void:
	var g = game
	var I = g.interact
	if I == null:
		return
	var cint = DAU.ud(crank).get("interact")
	var kp: Vector3 = X.worldXform(crank) * DAU.v3(cint.point if cint is Dictionary and cint.has("point") else [0.0, 1.0, -0.55])
	_crankItem = I.register({
		"id": "machine_uplink_crank", "pos": kp, "radius": 1.35,
		"enabled": func(): return built and not aligned and not disabled and (not _mp() or (not _crankDenied and _lockPending <= 0.0 and (crankUser == 0 or crankUser == _me()))),
		"prompt": func(): return {"hold": U.alignHold} if _powered() else {"plug": true},
		"hold": 0,
		"use": func():
			if _powered():
				if _mp():
					_lockPending = 1.5
					game.net.toHost("uplink", "lock", [])
				else:
					_lock()
			else:
				_unpoweredPoke(),
		"onHold": func(p):
			align = float(p) * float(U.alignHold)
			_crankHeldAt = game.time.realNow,
	})
	var rint = DAU.ud(cradle).get("interact")
	var cp: Vector3 = X.worldXform(cradle) * DAU.v3(rint.point if rint is Dictionary and rint.has("point") else [0.0, 1.3, -0.55])
	_cradleItem = I.register({
		"id": "machine_uplink", "pos": cp, "radius": 1.4,
		"enabled": func(): return built and aligned and not disabled and _powered() and ((phase == "ready" and (not _mp() or _user == _me())) or (phase == "idle" and _reqT < 0.0 and _upgradable() != null)),
		"prompt": func():
			if phase == "ready":
				return {}
			var s = _upgradable()
			return {"cost": U.reroll if X.g(s, "upgraded", false) else U.cost} if s != null else null,
		"use": func():
			if phase == "ready":
				if _mp():
					game.net.toHost("uplink", "take", [_useId])
				else:
					_takeWeapon()
			elif phase == "idle":
				if _mp():
					_requestInsert()
				else:
					_start(false),
	})

# ============================================================================================ helpers
func _powered() -> bool:
	return bool(X.g(game.machines, "powerOn", false))

func _lit(pos: Vector3) -> bool:
	if not _powered():
		return false
	var so = game.signon
	return so.waveReached(pos) if so != null and so.has_method("waveReached") else true

func _upgradable():
	var W = game.weapons
	var slots = X.g(W, "slots")
	if not (slots is Array):
		return null
	var cur: int = int(X.g(W, "current", -1))
	var s = slots[cur] if cur >= 0 and cur < slots.size() else null
	if s == null:
		return null
	var d = W.defOf(X.g(s, "id"), true) if W.has_method("defOf") else null
	return s if d != null and X.g(d, "isUpgraded", false) else null

func _glow(color: String, intensity: float):
	var q := roundf(intensity * 5.0) / 5.0
	var key := "%s|%s" % [color, q]
	var m = _glowCache.get(key)
	if m == null:
		m = game.mats.glow(color, q) if q > 0.0 else game.mats.toon("#3A3440", {"rough": 0.4})
		_glowCache[key] = m
	return m

func satellitePos() -> Vector3:
	if sat != null:
		return satPos
	if dish != null:
		return pivot
	return Vector3(0, 50, 0)

func _satDir(u: float) -> Vector3:
	var b := lerpf(SAT.b0, SAT.b1, u) * DEG
	var e := (float(SAT.el0) + float(SAT.elPeak) * sin(PI * u)) * DEG
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e))

# ============================================================================================ per frame
func update(dt: float) -> void:
	if not built:
		return
	_t += dt
	_time.value += dt
	if _reqT >= 0.0:
		_reqTick(dt)
	for m in [beam, aurora] + streams:
		(m.material_override as ShaderMaterial).set_shader_parameter("uTime", _time.value)
	_updateSatellite(dt)
	_updateCrank(dt)
	if phase == "seq":
		_updateSeq(dt)
	elif phase == "ready":
		_updateReady(dt)
	_updateFly(dt)
	_updateDish(dt)
	_updateLights(dt)
	_updateAurora(dt)
	_updateFlash(dt)

func _updateSatellite(dt: float) -> void:
	var rate: float = SAT.busyRate if busy and phase == "seq" else 1.0
	_satT = fmod(_satT + dt * rate, SAT.period)
	var u: float = _satT / SAT.period
	var dir := _satDir(u)
	satPos = pivot + dir * float(SAT.radius)
	sat.position = satPos
	# local -y faces the Earth (the dish); wings roughly along the pass
	sat.quaternion = Quaternion(Vector3(0, -1, 0), -dir)
	satModel.rotation.y = 0.35 + sin(_t * 0.2) * 0.1
	var alpha := X.smooth(0.0, 0.07, u) * (1.0 - X.smooth(0.93, 1.0, u))
	_satAlpha = alpha
	sat.visible = alpha > 0.02
	# beacon: red blink (1 Hz) until locked, then green double-blink; flare during the uplink
	var flare: bool = phase == "seq" and not reroll and seqT >= FULL.flare and seqT < FULL.flare + 0.7
	var locked := aligned
	var ph := fmod(_t, 1.0)
	var on := (ph < 0.12 or (ph > 0.24 and ph < 0.36)) if locked else ph < 0.45
	var beacon = satParts.get("beacon")
	if beacon is GeometryInstance3D:
		beacon.material_override = _beaconMats.flare if flare else (((_beaconMats.green if locked else _beaconMats.red)) if on else _beaconMats.off)
	X.spriteSet(satHalo, "color", X.lin("#FFFFFF" if flare else (Config.PAL.laughTrack if locked else "#FF5A4A")))
	X.spriteSet(satHalo, "opacity", alpha * (1.0 if flare else (1.0 if on else 0.3)))
	satHalo.scale = Vector3.ONE * (18.0 if flare else (10.0 if on else 6.0))

# --- alignment crank ---------------------------------------------------------------------------------------
func _updateCrank(dt: float) -> void:
	var g = game
	var I = g.interact
	var item = _crankItem
	var powered := _powered()
	if item != null:
		X.s(item, "hold", U.alignHold if powered and not aligned else 0)
	var focused: bool = I != null and item != null and is_same(X.g(I, "current"), item)
	var down: bool = g.input != null and g.input.has_method("down") and g.input.down("interact")
	var holding: bool = focused and down and powered and not aligned and not disabled and dt > 0.0 and not X.g(I, "_holdDone", false)
	if holding and not _wasHolding:
		# resume from the (decayed) progress instead of zero: interact adds dt / hold on top of this and calls onHold
		I.set("_holdItem", item)
		I.set("progress", clampf(align / float(U.alignHold), 0.0, 1.0))
	_wasHolding = holding
	# MP: another peer cranking drives the same visuals; its progress is extrapolated between its reports
	var remote: bool = _mp() and crankUser != 0 and crankUser != _me()
	if holding or remote:
		if not _cranking:
			_startCrank()
		if remote and not aligned and dt > 0.0:
			align = minf(float(U.alignHold) * 0.995, align + dt)
	else:
		if _cranking:
			_stopCrank()
		if not aligned and align > 0.0 and dt > 0.0 and _lockPending <= 0.0:
			align = maxf(0.0, align - DECAY * dt)
	if _mp():
		_crankNet(holding, down, dt)
	# wheel + gauge + grip glow
	var PC: Dictionary = P.crank
	var wheel = PC.get("wheel")
	if wheel is Node3D:
		_wheelV = lerpf(_wheelV, 7.5 if _cranking else 0.0, minf(1.0, dt * 8.0))
		if not _cranking and not aligned and align > 0.0:
			_wheelV = lerpf(_wheelV, -DECAY * 2.2, minf(1.0, dt * 4.0))
		wheel.rotation.z += _wheelV * dt
		if _jiggle > 0.0:
			_jiggle -= dt
			wheel.rotation.z += sin(_jiggle * 60.0) * 0.02
	var needle = PC.get("needle")
	if needle is Node3D:
		var k := 1.0 if aligned else clampf(align / float(U.alignHold), 0.0, 1.0)
		var want := lerpf(float(crankRig.get("needleMax", 1.05)), float(crankRig.get("needleMin", -1.05)), k) + (sin(_t * 40.0) * 0.03 if _cranking else 0.0)
		needle.rotation.z += (want - needle.rotation.z) * minf(1.0, dt * 12.0)
	if PC.get("handle") != null:
		var lit := _lit(DAU.worldPos(crank))
		var level := 0.0
		if not lit or disabled:
			level = 0.0
		elif aligned:
			level = 0.25
		elif _cranking:
			level = 1.0
		else:
			level = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 5.2))
		if level != _gripLevel:
			_gripLevel = level
			setCrankGlow(g, crank, level)

func _startCrank() -> void:
	var g = game
	_cranking = true
	var p := DAU.worldPos(crank)
	p.y = 1.0
	_crankLoop = g.audio.loop("dish_crank", {"pos": p, "vol": 0.9}) if g.audio != null and g.audio.has_method("loop") else null

func _stopCrank() -> void:
	_cranking = false
	if _crankLoop != null and _crankLoop is Object and _crankLoop.has_method("stop"):
		_crankLoop.stop(0.15)
	_crankLoop = null

func _onHurt() -> void:
	if not _cranking or aligned:
		return
	if _mp():
		if not _wasHolding:
			return                                   # someone else cranks: their own peer applies it
		_penalty()
		game.net.toHost("uplink", "penalty", [align])
		return
	_penalty()

func _penalty() -> void:
	var g = game
	var I = g.interact
	align *= 0.5
	if I != null and is_same(X.g(I, "_holdItem"), _crankItem):
		I.set("progress", clampf(align / float(U.alignHold), 0.0, 1.0))
	_tilt.v -= 1.6
	_jiggle = 0.25
	var p := Vector3(pivot.x, pivot.y - 1.1, pivot.z)
	if g.fx != null:
		g.fx.burst(p, {"shape": "spark", "count": 12, "speed": 5, "life": 0.4})
	if g.audio != null:
		g.audio.play("uplink_clang", {"pos": p, "vol": 0.5, "rate": 1.4})

func _unpoweredPoke() -> void:
	var g = game
	_jiggle = 0.3
	if g.audio != null:
		g.audio.play("sponsor_denied", {"pos": DAU.worldPos(crank)})
	var p: Vector3 = X.worldXform(crank) * Vector3(0, float(crankRig.get("hubY", 1.0)), -0.1)
	if g.fx != null:
		g.fx.burst(p, {"shape": "spark", "count": 4, "speed": 2.5, "life": 0.25, "colors": ["#7FE7FF", "#FFFFFF"]})

func _lock() -> void:
	var g = game
	if aligned:
		return
	aligned = true
	align = float(U.alignHold)
	_stopCrank()
	_lockT = 0.0
	_tilt.v += 2.4
	var col = X.g(g.level, "col")
	if col != null and col.has_method("setEnabled"):
		col.setEnabled("uplink_droop", false)
	_droopWasOff = true
	if g.nav != null and X.g(g.nav, "built", false):
		g.nav.build()
	if g.audio != null:
		g.audio.play("dish_lock", {"pos": pivot})
		g.audio.play("uplink_clang", {"pos": pivot, "vol": 0.6, "rate": 0.8, "delay": 0.05})
	if g.fx != null:
		g.fx.burst(pivot, {"shape": "star", "count": 14, "speed": 4, "life": 0.9, "colors": [Config.PAL.marqueeGold, "#FFFFFF", Config.PAL.laughTrack]})
		if g.fx.has_method("flashLight"):
			g.fx.flashLight(pivot, Config.PAL.marqueeGold, 8, 0.3)
	if g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.12, 0.25)
	g.events.emit("machine:dish_aligned", {})

# --- the upgrade ---------------------------------------------------------------------------------------------
func _start(free_: bool = false) -> bool:
	var g = game
	var W = g.weapons
	if phase != "idle" or not aligned or disabled:
		return false
	var s = _upgradable()
	if s == null:
		return false
	var rr: bool = bool(X.g(s, "upgraded", false))
	var cost = U.reroll if rr else U.cost
	if not free_ and not (g.economy != null and g.economy.spend(cost, "uplink")):
		return false
	# where the gun leaves from: the hand, facing where the hero faces
	var hand: Vector3
	var slot = X.g(X.g(X.g(g.player, "hero"), "slots"), "handR")
	if slot is Node3D:
		hand = DAU.worldPos(slot)
	else:
		hand = DAU.v3(g.player.pos)
		hand.y += 1.2
	# the holder turns the model's barrel (-z) toward -x: pre-rotate so it leaves pointing where the hero faces
	var fromQ := Quaternion(UP, float(X.g(g.player, "yaw", 0.0)) - PI / 2.0)
	var data = null
	if W.has_method("takeCurrent"):
		data = W.takeCurrent()
	elif W.has_method("remove"):
		data = W.remove(X.g(s, "id"))
	if data == null:
		return false
	weaponId = X.g(data, "id")
	reroll = rr
	var dsig = X.g(data, "signal")
	_prevSignal = dsig
	var pool: Array = SIGNALS.filter(func(x): return x != dsig) if rr else SIGNALS.duplicate()
	signal_ = pool[int(floorf(g.rand() * pool.size())) % pool.size()]
	busy = true
	phase = "seq"
	seqT = 0.0
	readyT = 0.0
	_cue = 0
	_cues = _rerollCues() if rr else _fullCues()
	_clearGun()
	_gun = _makeGun(weaponId, bool(X.g(data, "upgraded", false)), dsig)
	_makeCopies(weaponId, bool(X.g(data, "upgraded", false)), dsig)
	# the flight into the clamp (a fresh carrier per flight: Godot nodes left out of the tree are never collected)
	if _flyer != null:
		X.dispose(_flyer)
	_flyer = DAU.node3d("uplink_flyer")
	g.scene.add_child(_flyer)
	_flyer.position = hand
	_flyer.quaternion = fromQ
	_flyer.add_child(_gun)
	_fly = {"t": 0.0, "dur": FULL.land, "from": hand, "fromQ": fromQ, "prev": hand}
	_jaw.target = 1.0
	# the magnet's kick: the hero stumbles a step back (and the camera gets the clamp in view)
	var p = g.player
	if p != null and p.has_method("knockback"):
		var v := Vector3(p.pos.x - slotPos.x, 0, p.pos.z - slotPos.z)
		var d := v.length()
		if d < 2.6 and d > 1e-3:
			# back and a little to the hero's left, so the right-shoulder camera sees the clamp past the hero
			var yaw: float = float(X.g(p, "yaw", 0.0))
			v = (v / d + Vector3(-cos(yaw), 0, sin(yaw)) * 0.55).normalized()
			p.knockback(v * 7.0)
	if g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.1, 0.18)
	g.events.emit("machine:uplink_start", {"weaponId": weaponId})
	return true

func _fullCues() -> Array:
	var A = game.audio
	return [
		[0.0, func():
			if A != null:
				A.play("uplink_motor", {"pos": pivot, "dur": FULL.swivel + 0.1})],
		[FULL.split, func(): _beginSplit()],
		[FULL.beam, func(): _beginBeam()],
		[FULL.beam + 0.2, func(): _speaker("crowd_ooh", {"vol": 0.8})],
		[FULL.flare, func(): _beginFlare()],
		[FULL.retract, func(): _retractT = 0.0],
		[FULL.streams, func(): _beginStreams()],
		[FULL.snap - 1.1, func(): _swapInsert()],
		[FULL.snap, func(): _snap()],
	]

func _rerollCues() -> Array:
	var A = game.audio
	return [
		[0.0, func():
			if A != null:
				A.play("uplink_motor", {"pos": pivot, "dur": 0.5})],
		[RE.split, func(): _beginSplit()],
		[RE.converge, func():
			if A != null:
				A.play("uplink_vwoom", {"pos": slotPos, "vol": 0.55, "rate": 1.5})],
		[RE.snap, func(): _snap()],
	]

func _updateSeq(dt: float) -> void:
	seqT += dt
	var t := seqT
	while _cue < _cues.size() and t >= float(_cues[_cue][0]):
		var fn: Callable = _cues[_cue][1]
		_cue += 1
		fn.call()
	if phase != "seq":
		return
	_animCopies(t)
	_animBeam(dt, t)
	_animStreams(t)

func _speaker(id: String, opts: Dictionary = {}):
	var g = game
	if g.screens != null and g.screens.has_method("speaker"):
		return g.screens.speaker(id, opts)
	return g.audio.play(id, opts) if g.audio != null else null

# Gun model in the HAND convention, centred and scaled for the clamp (barrel toward the cradle's -x).
func _makeGun(id, upgraded: bool, sig) -> Node3D:
	var g = game
	var W = g.weapons
	var model: Node3D = W.buildModel(id, upgraded, sig) if W != null and W.has_method("buildModel") else null
	if model == null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.12, 0.08)
		mi.mesh = bm
		mi.material_override = g.mats.toon("#888888") if g.mats != null else null
		model = mi
	var def = W.defOf(id, upgraded) if W != null and W.has_method("defOf") else null
	var wrap := DAU.node3d("uplink_gun_%s" % id)
	var inner := DAU.node3d()
	inner.rotation.y = PI / 2.0
	inner.add_child(model)
	wrap.add_child(inner)
	var s: float = float(X.g(def, "scale", 1.0)) if def != null else 1.0
	if s == 0.0:
		s = 1.0
	if X.hasMeshes(model):
		var box := X.aabbOf(model, true)
		model.position -= box.get_center()
		var ln := maxf(box.size.x, maxf(box.size.y, box.size.z)) * s
		inner.scale = Vector3.ONE * (s * (1.05 / ln if ln > 1.05 else 1.0))
	else:
		inner.scale = Vector3.ONE * s
	DAU.traverse(model, func(o):
		if o is GeometryInstance3D:
			(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	return wrap

func _makeCopies(id, upgraded: bool, sig) -> void:
	for c in _copies:
		X.dispose(c)
	_copies = []
	for i in 3:
		var c := _makeGun(id, upgraded, sig)
		var mat = _copyMats[i]
		DAU.traverse(c, func(o):
			if o is GeometryInstance3D:
				(o as GeometryInstance3D).material_override = mat
				(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		c.visible = false
		splitRoot.add_child(c)
		_copies.append(c)
	splitRoot.scale = Vector3.ONE
	splitRoot.position = holder.position

func _clearGun() -> void:
	if _gun != null:
		X.dispose(_gun)
		_gun = null

func _updateFly(dt: float) -> void:
	var f = _fly
	if f != null:
		f.t += dt
		var k := clampf(f.t / f.dur, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var P0: Vector3 = f.from
		var P2 := slotPos
		var mid := P0.lerp(P2, 0.5)
		mid.y = maxf(P0.y, P2.y) + 0.9
		var a := (1.0 - e) * (1.0 - e)
		var b := 2.0 * (1.0 - e) * e
		var c := e * e
		var v := P0 * a + mid * b + P2 * c
		if game.fx != null and game.fx.has_method("tracer"):
			game.fx.tracer(f.prev, v, "#9FE8FF", 0.05)
		f.prev = v
		_flyer.position = v
		_flyer.quaternion = Quaternion(f.fromQ).slerp(slotQuat, e) * Quaternion(Vector3(1, 0, 0), sin(e * PI) * 1.2)
		var st := 1.0 + sin(k * PI) * 0.25
		_flyer.scale = Vector3(1.0 / sqrt(st), 1.0 / sqrt(st), st)
		if k >= 1.0:
			_land()
	var tk = _take
	if tk != null:
		tk.t += dt
		var k := clampf(tk.t / 0.2, 0.0, 1.0)
		var tp = _pl(int(tk.get("by", 0)))
		var hand = X.g(X.g(X.g(tp, "hero"), "slots"), "handR")
		var w: Vector3
		if hand is Node3D:
			w = DAU.worldPos(hand)
		elif tp != null:
			w = DAU.v3(tp.pos)
			w.y = 1.2
		else:
			w = slotPos
		var v := slotPos.lerp(w, k * k)
		v.y += sin(k * PI) * 0.35
		tk.obj.position = v
		tk.obj.scale = Vector3.ONE * (1.0 - 0.6 * k)
		if k >= 1.0:
			X.dispose(tk.obj)
			_take = null
	# jaws: spring toward open (1) / closed (0)
	spring(_jaw, _jaw.target, 260.0, 0.35, minf(dt, 1.0 / 30.0))
	var PC: Dictionary = P.cradle
	var R := cradleRig
	if PC.get("jawF") is Node3D:
		PC.jawF.rotation.x = lerpf(float(R.get("jawClosed", 0.0)), float(R.get("jawOpenF", -0.5)), _jaw.x)
	if PC.get("jawB") is Node3D:
		PC.jawB.rotation.x = lerpf(float(R.get("jawClosed", 0.0)), float(R.get("jawOpenB", 0.5)), _jaw.x)

func _land() -> void:
	var g = game
	_fly = null
	_flyer.scale = Vector3.ONE
	if _gun != null:
		DAU.detach(_gun)
		_gun.position = Vector3.ZERO
		_gun.quaternion = Quaternion.IDENTITY
		holder.add_child(_gun)
	X.dispose(_flyer)
	_flyer = null
	_jaw.target = 0.0
	_jaw.v = -6.0
	if g.audio != null:
		g.audio.play("uplink_clang", {"pos": slotPos})
	if g.fx != null:
		g.fx.burst(slotPos, {"shape": "spark", "count": 14, "speed": 4.5, "life": 0.35, "colors": ["#9FE8FF", "#FFFFFF", "#FFE8A0"]})
		if g.fx.has_method("flashLight"):
			g.fx.flashLight(slotPos, "#9FE8FF", 5, 0.15)
	if g.player != null and DAU.v3(g.player.pos).distance_to(slotPos) < 6.0 and g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.14, 0.2)
	_lampFlash = 0.25

func _beginSplit() -> void:
	var g = game
	_splitT = 0.0
	if _gun != null:
		_gun.visible = false
	for c in _copies:
		c.visible = true
	if g.audio != null:
		g.audio.play("uplink_triad", {"pos": slotPos})
	if g.fx != null:
		g.fx.burst(slotPos, {"shape": "star", "count": 6, "speed": 1.6, "life": 0.5, "colors": RGB})
	for b in lampBeams:
		b.visible = true

func _lampWorld(i: int) -> Vector3:
	var key: String = ["lampR", "lampG", "lampB"][i]
	var l = P.cradle.get(key)
	if l is Node3D:
		return DAU.worldPos(l)
	return hornPos

func _orient(mesh: Node3D, from: Vector3, to: Vector3, radius: float) -> float:
	var w := to - from
	var ln := maxf(1e-3, w.length())
	mesh.position = from
	mesh.quaternion = Quaternion(UP, w / ln)
	mesh.scale = Vector3(radius, ln, radius)
	return ln

# R/G/B copies: overlap (white) -> drift 0.3 m apart orbiting the barrel axis -> (full) stretch up the beam and fade,
# (Re-Uplink) spiral back in, the signal colour brightest, until the snap.
func _animCopies(t: float) -> void:
	var R: Dictionary = RE if reroll else FULL
	if _copies.is_empty() or t < float(R.split):
		return
	var ts: float = t - float(R.split)
	var orbitEnd: float = RE.converge if reroll else FULL.beam
	var r: float
	var spin: float
	var fade := 1.0
	var up := 0.0
	var stretch := 1.0
	var spinRate := 1.6 + ts * 2.2
	spin = ts * spinRate
	r = ORBIT_R * X.easeOutBack(ts / 0.45, 2.2)
	if t >= orbitEnd:
		var k := clampf((t - RE.converge) / (RE.snap - RE.converge), 0.0, 1.0) if reroll else clampf((t - FULL.beam) / 0.55, 0.0, 1.0)
		if reroll:
			r = ORBIT_R * (1.0 - X.easeInCubic(k))
			spin += k * k * 18.0
		else:
			r = ORBIT_R * (1.0 - k * 0.8)
			up = X.easeInCubic(k) * 4.5
			stretch = 1.0 + X.easeInCubic(k) * 5.0
			fade = 1.0 - X.smooth(0.45, 1.0, k)
	splitRoot.position = Vector3(holder.position.x, holder.position.y + up, holder.position.z)
	splitRoot.scale = Vector3(1, stretch, 1)
	var sig := SIGNALS.find(signal_)
	for i in 3:
		var c: Node3D = _copies[i]
		var a := spin + (i * TAU) / 3.0
		c.position = Vector3(0, cos(a) * r, sin(a) * r)
		c.rotation.x = sin(spin * 0.5 + i) * 0.25
		var bright := (1.35 if i == sig else 0.7) if reroll and t >= RE.converge else 1.0
		_copyMats[i].set_shader_parameter("opacity", fade * (0.85 + 0.15 * sin(t * 30.0 + i * 2.0)) * bright)
	# lamp beams while splitting
	var on := t < orbitEnd + (0.6 if reroll else 0.1)
	for i in 3:
		var b: MeshInstance3D = lampBeams[i]
		b.visible = on
		if not on:
			continue
		_orient(b, _lampWorld(i), slotPos, 0.028 + 0.012 * sin(t * 40.0 + i))
		(b.material_override as ShaderMaterial).set_shader_parameter("opacity", X.smooth(R.split, R.split + 0.15, t) * (0.6 + 0.4 * sin(t * 55.0 + i * 1.7)))

func _beginBeam() -> void:
	var g = game
	beam.visible = true
	beamHead.visible = true
	_retractT = -1.0
	if g.audio != null:
		g.audio.play("uplink_vwoom", {"pos": slotPos})
	_speaker("tone_1khz", {"dur": 0.9, "vol": 0.7})
	_insertObj = _insertModel(weaponId, false, null)
	if g.screens != null:
		if g.screens.has_method("setInsert"):
			g.screens.setInsert(_insertObj)
		# world-time sequence vs. the screens' own clock (a commercial could pause us): hold it until the snap cancels it
		if g.screens.has_method("override"):
			_override = g.screens.override("satellite", ["scr_decor", "scr_mc_canned", "scr_feed_*"], 20)
	if _override == null and (g.screens == null or not g.screens.has_method("override")):
		push_warning("[uplink] satellite override failed")

func _insertModel(id, upgraded: bool, sig):
	var W = game.weapons
	if W == null or not W.has_method("buildModel"):
		return null
	var model: Node3D = W.buildModel(id, upgraded, sig)
	if model == null:
		return null
	var wrap := DAU.node3d()
	var inner := DAU.node3d()
	inner.rotation.y = PI / 2.0
	inner.add_child(model)
	wrap.add_child(inner)
	if X.hasMeshes(model):
		var box := X.aabbOf(model, true)
		model.position -= box.get_center()
		var size := box.size
		inner.scale = Vector3.ONE * (0.62 / maxf(0.1, maxf(size.x, maxf(size.y, size.z))))
	wrap.position.y = 0.16
	wrap.rotation.z = 0.12
	return wrap

func _swapInsert() -> void:
	var g = game
	var up = _insertModel(weaponId, true, signal_)
	if up != null and g.screens != null and g.screens.has_method("setInsert"):
		g.screens.setInsert(up)
		_insertObj = up

func _animBeam(dt: float, t: float) -> void:
	if not beam.visible:
		return
	var from := hornPos
	var to := satPos
	var ln := _orient(beam, from, to, 1.0)
	var M := beam.material_override as ShaderMaterial
	M.set_shader_parameter("uLen", ln)
	var shoot := clampf((t - FULL.beam - 0.08) / (FULL.beamTop - FULL.beam - 0.08), 0.0, 1.0)
	var uHead := maxf(0.001, pow(X.easeOutCubic(shoot), 1.3))
	M.set_shader_parameter("uHead", uHead)
	var rad := 0.26 * X.easeOutBack(clampf((t - FULL.beam) / 0.3, 0.0, 1.0), 2.0) * (1.0 + 0.08 * sin(t * 24.0))
	beam.scale.x = maxf(0.01, rad)
	beam.scale.z = maxf(0.01, rad)
	if _retractT >= 0.0:
		_retractT += dt
		M.set_shader_parameter("uTail", X.easeInCubic(_retractT / 0.3))
		if _retractT >= 0.3:
			beam.visible = false
			beamHead.visible = false
			M.set_shader_parameter("uTail", 0.0)
			_retractT = -1.0
			return
	else:
		M.set_shader_parameter("uTail", 0.0)
	M.set_shader_parameter("uAlpha", 1.0)
	# head sprite at the tip
	var hk := 1.0 if _retractT >= 0.0 else uHead
	beamHead.position = from.lerp(to, hk)
	var d: float = game.camera.global_position.distance_to(beamHead.position) if game.camera != null else 10.0
	beamHead.scale = Vector3.ONE * (maxf(0.8, d * 0.06) * (1.4 if shoot < 1.0 else 0.8 + 0.2 * sin(t * 20.0)))
	X.spriteSet(beamHead, "opacity", 1.0 if shoot < 1.0 else 0.7)

func _beginFlare() -> void:
	var g = game
	_flareT = 0.0
	satFlare.visible = true
	if g.audio != null:
		g.audio.play("uplink_aurora", {})
	aurora.visible = true
	_auroraT = 0.0
	var b := atan2(satPos.x - pivot.x, -(satPos.z - pivot.z))
	(aurora.material_override as ShaderMaterial).set_shader_parameter("uS0", clampf(b / float(AURORA.span) + 0.5, 0.0, 1.0))
	# Yard zombies stop and gawk up at the sky for 0.8 s
	var alive = X.g(g.zombies, "alive", [])
	for z in alive:
		if z == null or X.g(z, "dead", false):
			continue
		var zp: Vector3 = DAU.v3(X.g(z, "pos"))
		var area = X.g(z, "area")
		if not area and g.level != null and g.level.has_method("areaAt"):
			area = g.level.areaAt(zp.x, zp.z)
		if area != "yard":
			continue
		var st = X.g(z, "state")
		if st and not ["chase", "attack", "approach"].has(st):
			continue
		X.s(z, "gawkT", 0.8 + randf() * 0.15)
		X.s(z, "gawkAt", satPos)

func _beginStreams() -> void:
	_streamT = 0.0
	_streamSpark = false
	for s in streams:
		s.visible = true
	if game.audio != null:
		game.audio.play("uplink_vwoom", {"pos": slotPos, "vol": 0.4, "rate": 0.7})

# Three thin streams race down from around the satellite, meet in the clamp, then brighten (the signal colour
# swelling thickest) until the snap.
func _animStreams(t: float) -> void:
	if not streams[0].visible:
		return
	var k := clampf((t - FULL.streams) / (FULL.streamsDown - FULL.streams), 0.0, 1.0)
	var hold := clampf((t - FULL.streamsDown) / (FULL.snap - FULL.streamsDown), 0.0, 1.0)
	var sig := SIGNALS.find(signal_)
	for i in 3:
		var s: MeshInstance3D = streams[i]
		var a := (float(i) / 3.0) * TAU + t * 1.4
		var spread := 9.0 * (1.0 - 0.6 * hold)
		var u := Vector3(cos(a) * spread, sin(a) * spread * 0.6, sin(a + 1.0) * spread * 0.4)
		var v := satPos + u
		var lead := i == sig
		var r := (0.13 if lead else 0.06) * (1.0 + hold * (1.0 if lead else 0.3)) * (1.0 + 0.15 * sin(t * 50.0 + i))
		var ln := _orient(s, slotPos, v, r)
		var M := s.material_override as ShaderMaterial
		M.set_shader_parameter("uLen", ln)
		M.set_shader_parameter("uHead", maxf(0.001, k * k * (3.0 - 2.0 * k)))
		M.set_shader_parameter("uAlpha", (0.9 if lead else 0.5) * (1.0 + hold * 0.4))
	if hold > 0.0 and not _streamSpark:
		_streamSpark = true
		if game.fx != null:
			game.fx.burst(slotPos, {"shape": "spark", "count": 10, "speed": 3, "life": 0.3, "colors": LAMP_COL + ["#FFFFFF"]})

func _snap() -> void:
	var g = game
	var id = weaponId
	var sig = signal_
	for s in streams:
		s.visible = false
	for b in lampBeams:
		b.visible = false
	for c in _copies:
		c.visible = false
	beam.visible = false
	beamHead.visible = false
	splitRoot.scale = Vector3.ONE
	splitRoot.position = holder.position
	_clearGun()
	_gun = _makeGun(id, true, sig)
	_gun.scale = Vector3.ONE * 0.01
	holder.add_child(_gun)
	_popT = 0.0
	_jaw.target = 1.0
	cone.visible = true
	var col: String = SIGNAL_COLORS.get(sig, "#FFFFFF")
	(cone.material_override as ShaderMaterial).set_shader_parameter("color", X.lin(col))
	# the flash
	_flashT = 0.0
	flash.visible = true
	if g.fx != null:
		if g.fx.has_method("flashLight"):
			g.fx.flashLight(slotPos, "#FFFFFF", 12, 0.3)
		g.fx.burst(slotPos, {"shape": "star", "count": 16, "speed": 4.2, "life": 0.9, "size": 0.12, "colors": [col, "#FFFFFF", Config.PAL.marqueeGold]})
		g.fx.burst(slotPos, {"shape": "confetti", "count": 22, "speed": 4.5, "life": 1.3, "colors": [col] + BARS})
		g.fx.burst(slotPos, {"shape": "spark", "count": 14, "speed": 6, "life": 0.4, "colors": [col, "#FFFFFF"]})
	if g.player != null and DAU.v3(g.player.pos).distance_to(slotPos) < 12.0:
		if g.cam != null and g.cam.has_method("shake"):
			g.cam.shake(0.22, 0.3)
		if g.hud != null and g.hud.has_method("whiteout"):
			g.hud.whiteout(0.5, 0.22)
	if g.audio != null:
		g.audio.play("uplink_snap", {"pos": slotPos})
		g.audio.play("uplink_fanfare", {"pos": slotPos, "delay": 0.1})
	var nm := _nameOf(id)
	var shown := false
	var near: bool = not _mp() or _user == _me() or (g.player != null and DAU.v3(g.player.pos).distance_to(slotPos) < 12.0)
	if near and g.hud != null and g.hud.has_method("chyron"):
		g.hud.chyron(nm)
		shown = true
	if g.screens != null and g.screens.has_method("setInsert"):
		g.screens.setInsert(null)
	_cancelOverride()
	_override = null
	_insertObj = null
	phase = "ready"
	readyT = 0.0
	_flickT = 0.0
	_tickPlayed = false
	g.events.emit("machine:uplink_ready", {"weaponId": id, "signal": sig, "name": nm, "chyron": shown} if not _mp() else {"weaponId": id, "signal": sig, "name": nm, "chyron": shown, "by": _user})
	if _hst() and _userGone != "":
		_releaseUser()

func _cancelOverride() -> void:
	var h = _override
	if h == null:
		return
	if X.g(h, "active") == false:
		return
	if h is Dictionary:
		var c = h.get("cancel")
		if c is Callable:
			c.call()
	elif h is Object and h.has_method("cancel"):
		h.cancel()

func _nameOf(id) -> String:
	var W = game.weapons
	var d = W.defOf(id, true) if W != null and W.has_method("defOf") else null
	var nm = null
	if d != null:
		nm = X.g(d, "upgradedName")
		if not nm:
			nm = X.g(d, "displayName")
		if not nm:
			nm = X.g(d, "name")
	return str(nm) if nm else str(id).to_upper()

# --- ready: 15 s to take it -----------------------------------------------------------------------------------
func _updateReady(dt: float) -> void:
	var g = game
	readyT += dt
	var t := readyT
	var gun := _gun
	var collect: float = float(U.collect)
	var flickerAt: float = float(U.flickerAt)
	if gun != null:
		if _popT >= 0.0:
			_popT += dt
			gun.scale = Vector3.ONE * maxf(0.01, X.easeOutBack(_popT / 0.3, 3.0))
			if _popT >= 0.3:
				_popT = -1.0
		# presented: it rises out of the horn onto the light cone and turns slowly so the finish reads from all sides
		var lift := X.easeOutBack(t / 0.7, 1.4) * (GUN.show - GUN.rest)
		gun.position.y = lift + sin(t * 2.4) * 0.018
		gun.rotation.y = t * 0.9
		gun.rotation.z = sin(t * 1.7) * 0.06
		# glints
		_glintT -= dt
		if _glintT <= 0.0 and t < flickerAt:
			_glintT = 0.55 + randf() * 0.4
			var gp := slotPos + Vector3((randf() - 0.5) * 0.5, (randf() - 0.3) * 0.18, (randf() - 0.5) * 0.2)
			if g.fx != null:
				g.fx.burst(gp, {"shape": "star", "count": 1, "speed": 0.2, "life": 0.5, "size": 0.1, "colors": ["#FFFFFF", SIGNAL_COLORS.get(signal_, "#FFFFFF")]})
		# bad reception from flickerAt: drop-outs + sideways tearing + static
		if t >= flickerAt:
			var f := clampf((t - flickerAt) / (collect - flickerAt), 0.0, 1.0)
			_flickT -= dt
			if _flickT <= 0.0:
				var off := randf() < 0.3 + 0.45 * f
				_flickOff = off
				_flickT = 0.04 + randf() * (0.05 + 0.12 * f) if off else 0.06 + randf() * (0.3 - 0.2 * f)
				_jx = (randf() - 0.5) * 0.12 * (0.4 + f)
				if off and randf() < 0.5 and g.fx != null:
					g.fx.burst(slotPos, {"shape": "static", "count": 4, "speed": 1.2, "size": 0.05, "life": 0.3})
			gun.visible = not _flickOff
			gun.position.x = _jx
			_snd -= dt
			if _snd <= 0.0:
				_snd = 0.85
				if g.audio != null:
					g.audio.play("uplink_flicker", {"pos": slotPos, "vol": 0.7})
			if not _tickPlayed:
				_tickPlayed = true
				if g.audio != null:
					g.audio.play("tele_tick", {"pos": slotPos, "dur": collect - flickerAt, "vol": 0.6})
		else:
			gun.visible = true
			gun.position.x = 0.0
	if cone != null and cone.visible:
		var cm := cone.material_override as ShaderMaterial
		cm.set_shader_parameter("opacity", X.smooth(0.0, 0.5, t) * (0.38 + 0.08 * sin(t * 7.0)) * (0.25 if gun != null and not gun.visible else 1.0))
		cm.set_shader_parameter("uvOffset", Vector2(t * 0.08, 0.0))
	if not _mp():
		if t >= collect:
			_loseWeapon()
	elif _hst() and t >= collect + MP_GRACE:
		game.net.everyone("uplink", "lost", [_useId])

func _takeWeapon() -> void:
	var g = game
	var W = g.weapons
	if phase != "ready" or not weaponId:
		return
	var id = weaponId
	var sig = signal_
	var ok := false
	if not _isMe(_user):
		ok = true                                     # MP: the weapon goes to the user's own peer
	elif W != null and W.has_method("give"):
		ok = bool(W.give(id, {"upgraded": true, "signal": sig, "source": "uplink"}))
	if not ok:
		push_error("[uplink] give failed")
		if not _mp():
			return
	if _gun != null:
		var obj := _gun
		var xf := X.worldXform(obj)
		var s := xf.basis.get_scale().x
		DAU.detach(obj)
		g.scene.add_child(obj)
		obj.position = xf.origin
		obj.quaternion = xf.basis.get_rotation_quaternion()
		obj.scale = Vector3.ONE * s
		obj.visible = true
		_take = {"obj": obj, "t": 0.0, "by": _user}
		_gun = null
	_jaw.target = 1.0
	var up = _pl(_user)
	if g.audio != null:
		g.audio.play("wallbuy_boing", {"pos": DAU.v3(up.pos) if up != null else slotPos})
	if g.fx != null:
		g.fx.burst(slotPos, {"shape": "star", "count": 6, "speed": 2, "life": 0.5, "colors": [SIGNAL_COLORS.get(sig, "#FFFFFF"), "#FFFFFF"]})
	g.events.emit("machine:uplink_take", {"weaponId": id} if not _mp() else {"weaponId": id, "by": _user})
	_toIdle(false)

func _loseWeapon() -> void:
	var g = game
	var id = weaponId
	# beamed back up: a thin white stream shoots up out of the clamp, the gun dissolves into static
	if g.fx != null:
		g.fx.burst(slotPos, {"shape": "static", "count": 26, "speed": 2.4, "size": 0.08, "life": 0.8})
		g.fx.burst(slotPos, {"shape": "star", "count": 5, "speed": 5, "life": 0.5, "dir": UP, "cone": 0.3, "colors": ["#FFFFFF"]})
	_lost = {"t": 0.0}
	var si := SIGNALS.find(signal_)
	var s: MeshInstance3D = streams[si] if si >= 0 else streams[0]
	s.visible = true
	_lostStream = s
	if g.audio != null:
		g.audio.play("uplink_lost", {"pos": slotPos})
	_jaw.target = 1.0
	g.events.emit("machine:uplink_lost", {"weaponId": id} if not _mp() else {"weaponId": id, "by": _user})
	_toIdle(false)

func _toIdle(hard: bool) -> void:
	var g = game
	phase = "idle"
	busy = false
	_userGone = ""
	weaponId = null
	signal_ = null
	seqT = 0.0
	readyT = 0.0
	_cues = []
	_cue = 0
	_clearGun()
	for c in _copies:
		X.dispose(c)
	_copies = []
	if _fly != null:
		_fly = null
		if _flyer != null:
			X.dispose(_flyer)
			_flyer = null
	if hard:
		if _take != null:
			X.dispose(_take.obj)
			_take = null
		_lost = null
		_flashT = -1.0
		if flash != null:
			flash.visible = false
		if aurora != null:
			aurora.visible = false
			_auroraT = -1.0
		_jaw.target = 1.0
		_jaw.x = 1.0
		_jaw.v = 0.0
	if beam != null:
		beam.visible = false
		beamHead.visible = false
		_retractT = -1.0
	for s in streams:
		if s != _lostStream or hard:
			s.visible = false
	for b in lampBeams:
		b.visible = false
	if satFlare != null:
		satFlare.visible = false
	if cone != null:
		cone.visible = false
		(cone.material_override as ShaderMaterial).set_shader_parameter("opacity", 0.0)
	_cancelOverride()
	if _insertObj != null and g.screens != null and g.screens.has_method("setInsert"):
		g.screens.setInsert(null)
	_override = null
	_insertObj = null
	reroll = false
	if hard and dish != null:
		_dishGlowK = 0.0
		_setDishGlow(0.0, "#000000")

func _setDisabled(on: bool) -> void:
	var g = game
	if disabled == on:
		return
	disabled = on
	if not on:
		return
	# hand back whatever is in the machine (upgraded: it was paid for)
	if _mp():
		if _hst() and weaponId and (phase == "seq" or phase == "ready"):
			g.net.everyone("uplink", "handback", [_user, str(weaponId), str(signal_) if signal_ else ""])
	elif weaponId and (phase == "seq" or phase == "ready"):
		if g.weapons != null and g.weapons.has_method("give"):
			g.weapons.give(weaponId, {"upgraded": true, "signal": signal_, "source": "uplink"})
		g.events.emit("machine:uplink_take", {"weaponId": weaponId})
	_toIdle(true)
	_stopCrank()

# ============================================================================================ visuals
func _updateDish(dt: float) -> void:
	if dish == null:
		return
	var R := dishRig
	var tilt: float
	var yaw: float
	var k := 18.0
	var zeta := 0.45
	var ky := 10.0
	var zy := 0.8
	if not aligned:
		var p := clampf(align / float(U.alignHold), 0.0, 1.0)
		tilt = lerpf(float(R.droop), float(R.aligned), p * p * (3.0 - 2.0 * p)) + (sin(_t * 23.0) * 0.012 if _cranking else 0.0)
		yaw = 0.0
		k = 30.0 if _cranking else 14.0
		zeta = 0.5
	elif phase == "seq" and seqT < (float(RE.snap) if reroll else float(FULL.snap)):
		# swivel onto Skylark-13 (the Re-Uplink only nudges)
		var v := satPos - pivot
		var want := atan2(-v.x, -v.z) - dish.rotation.y
		var el := atan2(v.y, Vector2(v.x, v.z).length())
		if reroll:
			tilt = float(R.aligned) + 0.08 * sin(minf(1.0, seqT / 0.5) * PI)
			yaw = 0.0
		else:
			tilt = clampf(el, float(R.droop), 1.25)
			yaw = _yaw.x + X.wrapPi(want - _yaw.x)
		k = 26.0
		zeta = 0.55
		ky = 16.0
		zy = 0.62
		if seqT > 0.8:
			k = 40.0
			ky = 30.0
			zy = 0.9
	else:
		tilt = float(R.aligned) + (-0.25 if disabled else 0.0)
		yaw = 0.0
		k = 10.0
		zeta = 0.55
		ky = 5.5
		zy = 0.85
	var h := minf(dt, 1.0 / 30.0)
	if h > 0.0:
		spring(_tilt, tilt, k, zeta, h)
		spring(_yaw, yaw, ky, zy, h)
	setUplinkPose(dish, {"tilt": _tilt.x, "yaw": _yaw.x})
	if _lockT >= 0.0:
		_lockT += dt
		if _lockT > 2.0:
			_lockT = -1.0

func _updateLights(dt: float) -> void:
	var g = game
	var lit := _lit(pivot) and not disabled
	var boothLit := _lit(DAU.worldPos(booth)) and not disabled
	# rim bulbs
	var bulbs = P.dish.get("rimBulbs")
	if bulbs is Node3D:
		var n := X.instCount(bulbs)
		var t := _t
		var mode := "off"
		var speed := 12.0
		var color: String = Config.PAL.marqueeGold
		if lit and not aligned:
			mode = "progress"
		elif lit and phase == "seq":
			mode = "rainbow"
			speed = 40.0
		elif lit and phase == "ready":
			mode = "chase"
			speed = 28.0
			color = SIGNAL_COLORS.get(signal_, color)
		elif lit:
			mode = "lock" if _lockT >= 0.0 else "chase"
		var p := clampf(align / float(U.alignHold), 0.0, 1.0)
		var head := int(floorf(t * speed))
		for i in n:
			var v := 0.03
			var col := color
			if mode == "progress":
				var f := float(i) / n
				v = 0.9 if f < p else 0.06
				if f < p and f > p - 1.0 / n:
					v = 1.6
				if p <= 0.0:
					v = 0.06 + 0.1 * (0.5 + 0.5 * sin(t * 5.2))
			elif mode == "chase" or mode == "rainbow":
				var kk := ((i - head) % 4 + 4) % 4
				v = 1.4 if kk == 0 else (0.45 if kk == 1 else 0.14)
				if mode == "rainbow":
					col = BARS[(i + int(floorf(t * 6.0))) % 7]
			elif mode == "lock":
				v = 1.6 if sin(_lockT * 18.0 + i * 0.5) > 0.0 else 0.3
				col = "#FFFFFF"
			X.instSetColor(bulbs, i, X.lin(col) * v)
	# horn lamps: dark before alignment; steady after; flashing during the split; the signal lamp leads when ready
	var PC: Dictionary = P.cradle
	if _lampFlash > 0.0:
		_lampFlash -= dt
	var keys := ["lampR", "lampG", "lampB"]
	for i in 3:
		var m = PC.get(keys[i])
		if not (m is GeometryInstance3D):
			continue
		var lv := 0.0
		if lit and aligned:
			lv = 0.45
			if phase == "seq":
				lv = 0.9 + 0.1 * sin(_t * 40.0 + i) if seqT >= (float(RE.split) if reroll else float(FULL.split)) else 0.7
			if phase == "ready":
				lv = 1.0 if SIGNALS[i] == signal_ else 0.2
			if _lampFlash > 0.0:
				lv = 1.0
		m.material_override = _glow(LAMP_COL[i], 0.4 + 2.8 * lv if lv > 0.0 else 0.0)
	# light anchors + floor pool
	var L = g.lights
	if L != null and L.has_method("setAnchor"):
		var hornOn := lit and aligned
		var hc: String = SIGNAL_COLORS.get(signal_, "#FFFFFF") if phase == "ready" else (BARS[int(floorf(_t * 8.0)) % 7] if phase == "seq" else "#E8F4FF")
		var key := "%s|%s|%s" % [hornOn, hc, boothLit]
		if key != _lightKey:
			_lightKey = key
			L.setAnchor("uplink_horn", {"enabled": hornOn, "color": hc, "intensity": 1.1 if phase == "idle" else (5.5 if phase == "seq" else 3.0)})
			L.setAnchor("uplink_booth", {"enabled": boothLit})
	# the energised dish (rainbow wash while uplinking, the signal colour as it winds down)
	if not _dishGlow.is_empty():
		var want := 0.0
		if lit and phase == "seq":
			var t := seqT
			want = 0.06 * X.smooth(RE.split, RE.split + 0.4, t) if reroll else 0.07 * X.smooth(0.5, 1.8, t) + 0.09 * X.smooth(1.8, 2.3, t) * (0.85 + 0.15 * sin(_t * 18.0))
		elif lit and phase == "ready":
			want = 0.05 * (1.0 - X.smooth(0.0, 2.5, readyT))
		_dishGlowK += (want - _dishGlowK) * minf(1.0, dt * 5.0)
		if _dishGlowK < 0.004 and want == 0.0:
			_dishGlowK = 0.0
		var col: String = SIGNAL_COLORS.get(signal_, "#FFFFFF") if phase == "ready" else BARS[int(floorf(_t * 8.0)) % 7]
		_setDishGlow(_dishGlowK, col)
	if _pool != null:
		var want := 0.22 + (0.12 * (0.5 + 0.5 * sin(_t * 20.0)) if phase == "seq" else 0.0) if lit and aligned else 0.0
		if absf(want - _poolI) > 0.01:
			_poolI = want
			X.poolSet(_pool, {"intensity": want})
	# booth: dark before power, then its lamp panel blinks and the roof beacon flashes
	var B: Dictionary = P.booth
	if B.get("lamps") is Node3D:
		if boothLit:
			setBoothLamps(booth, _t)
		elif _boothDark != true:
			var inst: Node3D = B.lamps
			for i in X.instCount(inst):
				X.instSetColor(inst, i, X.instGetColor(inst, i) * 0.06)
		_boothDark = not boothLit
	if B.get("beacon") is GeometryInstance3D:
		var on := boothLit and fmod(_t, 1.2) < 0.5
		B.beacon.material_override = _glow(Config.PAL.onAirRed, 2.6 if on else 0.0)
	if B.get("console") is GeometryInstance3D:
		var con: GeometryInstance3D = B.console
		if _consoleOn == null:
			_consoleOn = con.material_override if con.material_override != null else ((con as MeshInstance3D).get_active_material(0) if con is MeshInstance3D else null)
			_consoleOff = game.mats.toon("#1A2230", {"rough": 0.3})
		con.material_override = _consoleOn if boothLit else _consoleOff

func _updateAurora(dt: float) -> void:
	var a := aurora
	if a == null or not a.visible:
		if _lost != null:
			_updateLost(dt)
		return
	_auroraT += dt
	var t := _auroraT
	var M := a.material_override as ShaderMaterial
	M.set_shader_parameter("uReveal", X.easeOutCubic(t / 2.4) * 1.9)
	M.set_shader_parameter("uAlpha", X.smooth(0.0, 0.6, t) * (1.0 - X.smooth(3.2, 7.2, t)) * 1.15)
	if t > 7.3:
		a.visible = false
		_auroraT = -1.0
	if _lost != null:
		_updateLost(dt)

func _updateLost(dt: float) -> void:
	var Ls = _lost
	Ls.t += dt
	var s = _lostStream
	if s != null:
		var v := Vector3(slotPos.x + 0.001, slotPos.y + 60.0, slotPos.z)
		var ln := _orient(s, slotPos, v, 0.05 * (1.0 - clampf(Ls.t / 0.6, 0.0, 1.0)) + 0.005)
		var M := (s as MeshInstance3D).material_override as ShaderMaterial
		M.set_shader_parameter("uLen", ln)
		M.set_shader_parameter("uHead", 1.0)
		M.set_shader_parameter("uAlpha", 1.4 * (1.0 - clampf(Ls.t / 0.6, 0.0, 1.0)))
	if Ls.t > 0.6:
		if s != null:
			s.visible = false
		_lostStream = null
		_lost = null

func _updateFlash(dt: float) -> void:
	if _flashT >= 0.0 and flash.visible:
		_flashT += dt
		var k := _flashT / 0.45
		flash.scale = Vector3.ONE * (0.3 + 3.2 * X.easeOutCubic(k))
		X.spriteSet(flash, "opacity", maxf(0.0, 1.0 - k * k))
		if k >= 1.0:
			flash.visible = false
			_flashT = -1.0
	if _flareT >= 0.0 and satFlare.visible:
		_flareT += dt
		var k := _flareT / 1.2
		satFlare.scale = Vector3.ONE * (6.0 + 60.0 * X.easeOutCubic(k))
		X.spriteSet(satFlare, "opacity", maxf(0.0, 1.0 - k) * _satAlpha)
		X.spriteSet(satFlare, "rotation", k * 0.8)
		if k >= 1.0:
			satFlare.visible = false
			_flareT = -1.0


# ============================================================================================== MP (online co-op)
# See the header's MP paragraph. Reached only with game.net.inGame (solo never calls these).
func _mp() -> bool:
	var n = game.get("net")
	return n != null and n.inGame

func _hst() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isHost

func _me() -> int:
	return int(game.net.localId) if _mp() else 0

func _isMe(by) -> bool:
	return by == null or int(by) == 0 or not _mp() or int(by) == int(game.net.localId)

func _pl(by):
	if by == null or int(by) == 0 or not _mp():
		return game.player
	return game.net.playerById(int(by))

func _fromHost() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.sender == 1

# Crank reports (local cranker -> host): edges + 10 Hz while holding; the host relays 5 Hz while someone cranks.
func _crankNet(holding: bool, down: bool, dt: float) -> void:
	var n = game.net
	if _lockPending > 0.0:
		_lockPending = maxf(0.0, _lockPending - dt)
	if not down:
		_crankDenied = false
	if holding != _crankSent:
		_crankSent = holding
		_crankSendT = 0.1
		n.toHost("uplink", "crank", [holding, align])
	elif holding:
		_crankSendT -= dt
		if _crankSendT <= 0.0:
			_crankSendT = 0.1
			n.toHost("uplink", "crank", [true, align])
	if n.isHost and crankUser != 0:
		_stateT -= dt
		if _stateT <= 0.0:
			_stateT = 0.2
			n.toAll("uplink", "crankState", [crankUser, align])

func net_crank(holding, a) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient or aligned or disabled or not _powered():
		return
	var by: int = n.sender
	if crankUser != 0 and crankUser != by:
		if holding == true:
			n.toPeer(by, "uplink", "crankBusy", [crankUser])
		return
	var was := crankUser
	crankUser = by if holding == true else 0
	if (a is float or a is int) and by != n.localId:
		align = clampf(float(a), 0.0, float(U.alignHold))
	if was != crankUser:
		_stateT = 0.2
		n.toAll("uplink", "crankState", [crankUser, align])

func net_crankBusy(u) -> void:
	if not _fromHost():
		return
	_crankDenied = true
	crankUser = int(u)

func net_crankState(u, a) -> void:
	if not _fromHost():
		return
	crankUser = int(u)
	if not _wasHolding and (a is float or a is int) and not aligned:
		align = clampf(float(a), 0.0, float(U.alignHold))

func net_penalty(a) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient or aligned or n.sender != crankUser:
		return
	if n.sender != n.localId and (a is float or a is int):
		align = clampf(float(a), 0.0, float(U.alignHold))
	n.toAll("uplink", "penaltyFx", [n.sender, align])
	if n.sender != n.localId:
		_penaltyFxLocal()

func net_penaltyFx(by, a) -> void:
	if not _fromHost() or int(by) == _me():
		return
	_penaltyFxLocal()
	if a is float or a is int:
		align = clampf(float(a), 0.0, float(U.alignHold))

# the clunk of a hit cranker, seen by everyone else (align comes with the message)
func _penaltyFxLocal() -> void:
	var g = game
	_tilt.v -= 1.6
	_jiggle = 0.25
	var p := Vector3(pivot.x, pivot.y - 1.1, pivot.z)
	if g.fx != null:
		g.fx.burst(p, {"shape": "spark", "count": 12, "speed": 5, "life": 0.4})
	if g.audio != null:
		g.audio.play("uplink_clang", {"pos": p, "vol": 0.5, "rate": 1.4})

func net_lock() -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient or aligned or disabled or not _powered():
		return
	if crankUser != 0 and crankUser != n.sender:
		return
	n.everyone("uplink", "aligned", [])

func net_aligned() -> void:
	if not _fromHost():
		return
	crankUser = 0
	_lockPending = 0.0
	_lock()

# The user's side of an upgrade: pay (reservation), yank the weapon out of the hands, then ask the host.
func _requestInsert() -> bool:
	var g = game
	var W = g.weapons
	if phase != "idle" or not aligned or disabled or _reqT >= 0.0:
		return false
	var s = _upgradable()
	if s == null:
		return false
	var rr: bool = bool(X.g(s, "upgraded", false))
	var cost: int = int(U.reroll if rr else U.cost)
	if not (g.economy != null and g.economy.spend(cost, "uplink")):
		return false
	var hand: Vector3
	var slot = X.g(X.g(X.g(g.player, "hero"), "slots"), "handR")
	if slot is Node3D:
		hand = DAU.worldPos(slot)
	else:
		hand = DAU.v3(g.player.pos)
		hand.y += 1.2
	var yaw: float = float(X.g(g.player, "yaw", 0.0))
	var data = null
	if W.has_method("takeCurrent"):
		data = W.takeCurrent()
	elif W.has_method("remove"):
		data = W.remove(X.g(s, "id"))
	if data == null:
		_refund(cost)
		return false
	var p = g.player
	if p != null and p.has_method("knockback"):
		var v := Vector3(p.pos.x - slotPos.x, 0, p.pos.z - slotPos.z)
		var d := v.length()
		if d < 2.6 and d > 1e-3:
			v = (v / d + Vector3(-cos(yaw), 0, sin(yaw)) * 0.55).normalized()
			p.knockback(v * 7.0)
	if g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(0.1, 0.18)
	var dsig = X.g(data, "signal")
	_reqT = 5.0
	_reqData = [str(X.g(data, "id")), bool(X.g(data, "upgraded", false)), str(dsig) if dsig else "", cost]
	g.net.toHost("uplink", "insert", [_reqData[0], _reqData[1], _reqData[2], cost, hand, yaw])
	return true

func _refund(n: int) -> void:
	var eco = game.economy
	if n <= 0 or eco == null:
		return
	if eco.has_method("refund"):
		eco.refund(n, "uplink")
	else:
		eco.add(n, "uplink")

# requester: no answer in 5 s -> weapon back + refund
func _reqTick(dt: float) -> void:
	_reqT -= dt
	if _reqT < 0.0 and _reqData.size() == 4:
		push_warning("[uplink] insert request timed out (weapon returned)")
		net_deny(_reqData[0], _reqData[1], _reqData[2], _reqData[3], true)

func net_insert(wid, upgraded, prevSig, cost, hand, yaw) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient:
		return
	var by: int = n.sender
	if phase != "idle" or not aligned or disabled or not _powered() or not (wid is String) or str(wid) == "":
		n.toPeer(by, "uplink", "deny", [str(wid), bool(upgraded), str(prevSig), int(cost)])
		return
	var rr := bool(upgraded)
	var ps := str(prevSig)
	var pool: Array = SIGNALS.filter(func(x): return x != ps) if rr else SIGNALS.duplicate()
	var sig: String = pool[int(floorf(game.rand() * pool.size())) % pool.size()]
	_useId += 1
	n.everyone("uplink", "start", [by, _useId, str(wid), rr, ps, sig, rr, DAU.v3(hand), float(yaw), _satT])

func net_deny(wid, upgraded, prevSig, cost, _local = false) -> void:
	if not _local and not _fromHost():
		return
	_reqT = -1.0
	_reqData = []
	var W = game.weapons
	if W != null and W.has_method("give") and str(wid) != "":
		var o := {"upgraded": bool(upgraded), "source": "uplink"}
		if str(prevSig) != "":
			o["signal"] = str(prevSig)
		W.give(str(wid), o)
	_refund(int(cost))
	if game.audio != null:
		game.audio.play("sponsor_denied", {"pos": slotPos})

# host -> all (everyone): the upgrade starts (the user already paid and let go of the weapon).
func net_start(by, id, wid, upgraded, prevSig, sig, rr, hand, yaw, satT) -> void:
	if not _fromHost() or not built:
		return
	if int(by) == _me():
		_reqT = -1.0
		_reqData = []
	var g = game
	if phase != "idle":
		_toIdle(true)
	if (satT is float or satT is int) and float(satT) >= 0.0:
		_satT = float(satT)
	weaponId = str(wid)
	reroll = bool(rr)
	_prevSignal = str(prevSig) if str(prevSig) != "" else null
	signal_ = str(sig)
	_user = int(by)
	_useId = int(id)
	_userGone = ""
	busy = true
	phase = "seq"
	seqT = 0.0
	readyT = 0.0
	_cue = 0
	_cues = _rerollCues() if reroll else _fullCues()
	_clearGun()
	_gun = _makeGun(weaponId, bool(upgraded), _prevSignal)
	_makeCopies(weaponId, bool(upgraded), _prevSignal)
	var from: Vector3 = DAU.v3(hand)
	var fromQ := Quaternion(UP, float(yaw) - PI / 2.0)
	if _flyer != null:
		X.dispose(_flyer)
	_flyer = DAU.node3d("uplink_flyer")
	g.scene.add_child(_flyer)
	_flyer.position = from
	_flyer.quaternion = fromQ
	_flyer.add_child(_gun)
	_fly = {"t": 0.0, "dur": FULL.land, "from": from, "fromQ": fromQ, "prev": from}
	_jaw.target = 1.0
	g.events.emit("machine:uplink_start", {"weaponId": weaponId, "by": _user})

func net_take(id) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient or phase != "ready" or int(id) != _useId or n.sender != _user:
		return
	if _userGone != "" or readyT >= float(U.collect) + MP_GRACE:
		return
	n.everyone("uplink", "took", [_useId])

func net_took(id) -> void:
	if not _fromHost() or int(id) != _useId:
		return
	if phase == "seq":
		_updateSeq(maxf(0.0, (float(RE.snap) if reroll else float(FULL.snap)) - seqT + 0.001))
	if phase == "ready":
		_takeWeapon()

func net_lost(id) -> void:
	if not _fromHost() or int(id) != _useId:
		return
	if phase == "seq":
		_updateSeq(maxf(0.0, (float(RE.snap) if reroll else float(FULL.snap)) - seqT + 0.001))
	if phase == "ready":
		_loseWeapon()

# host -> all: the weapon goes back to its owner (boss start, owner downed).
func net_handback(by, wid, sig) -> void:
	if not _fromHost():
		return
	if _isMe(int(by)) and str(wid) != "":
		var W = game.weapons
		if W != null and W.has_method("give"):
			W.give(str(wid), {"upgraded": true, "signal": str(sig) if str(sig) != "" else null, "source": "uplink"})
	game.events.emit("machine:uplink_take", {"weaponId": str(wid), "by": int(by)})
	_toIdle(true)

# host: the user is gone / down / off-air -> hand back (down) or lose (off-air, left) once the weapon is ready.
func _releaseUser() -> void:
	var n = game.net
	if _userGone == "down":
		n.everyone("uplink", "handback", [_user, str(weaponId), str(signal_) if signal_ else ""])
	else:
		n.everyone("uplink", "lost", [_useId])

func onPeerGone(id: int, why: String = "left") -> void:
	if not _hst():
		return
	if crankUser == id:
		crankUser = 0
		game.net.toAll("uplink", "crankState", [0, align])
	if _user == id and (phase == "seq" or phase == "ready"):
		_userGone = why
		if phase == "ready":
			_releaseUser()

# ============================================================================================ debug / status
func status() -> Dictionary:
	return {
		"built": built, "powered": _powered(), "aligned": aligned, "align": snappedf(align, 0.01), "busy": busy, "phase": phase,
		"seqT": snappedf(seqT, 0.01), "readyT": snappedf(readyT, 0.01), "weaponId": weaponId, "signal": signal_, "reroll": reroll,
		"disabled": disabled, "cranking": _cranking, "tilt": snappedf(_tilt.x, 0.001), "yaw": snappedf(_yaw.x, 0.001),
		"sat": [snappedf(satPos.x, 0.1), snappedf(satPos.y, 0.1), snappedf(satPos.z, 0.1)] if sat != null else null, "satVisible": sat != null and sat.visible,
		"beam": beam != null and beam.visible, "aurora": aurora != null and aurora.visible, "copies": _copies.size(),
		"gun": _gun != null,
	}

func debugAlign() -> bool:
	if not aligned:
		_lock()
	return aligned

func debugUpgrade(wid = null, opts: Dictionary = {}) -> bool:
	var W = game.weapons
	var isFree: bool = opts.get("free", true)
	if not aligned:
		_lock()
	if wid and not W.has(wid):
		W.give(wid, {"source": "debug"})
	if wid:
		var i := -1
		for j in W.slots.size():
			if X.g(W.slots[j], "id") == wid:
				i = j
				break
		if i >= 0 and i != int(W.current):
			if W.has_method("_equip"):
				W._equip(i, false)
			elif W.has_method("switchTo"):
				W.switchTo(i)
	return _start(isFree)

func debugTake() -> String:
	_takeWeapon()
	return phase

func debugSkip(t: float) -> Dictionary:
	if phase == "seq":
		var dtt := maxf(0.0, t - seqT)
		update(0.0)
		_updateSeq(dtt)
	elif phase == "ready":
		readyT = maxf(readyT, t)
	return status()

func debugHit() -> float:
	_penalty()
	return align

# ============================================================================================ spring
static func spring(s: Dictionary, target: float, k: float, zeta: float, dt: float) -> void:
	var a: float = k * (target - s.x) - 2.0 * zeta * sqrt(k) * s.v
	s.v += a * dt
	s.x += s.v * dt

# ============================================================================================ prop helpers
# (src/props/machines.js runtime helpers of the Uplink props)
# Pose: tilt = elevation in radians (rig.droop .. rig.aligned), yaw = turntable angle.
static func setUplinkPose(g: Node3D, o: Dictionary = {}) -> void:
	var Pp = DAU.ud(g).get("parts", {})
	if o.has("tilt") and Pp.get("tilt") is Node3D:
		Pp.tilt.rotation.x = o.tilt
	if o.has("yaw") and Pp.get("yaw") is Node3D:
		Pp.yaw.rotation.y = o.yaw

static func setCrankGlow(game, g: Node3D, level: float = 1.0) -> void:
	var Pp = DAU.ud(g).get("parts", {})
	var q := roundf(clampf(level, 0.0, 1.0) * 10.0) / 10.0
	if Pp.get("handle") is GeometryInstance3D and game.mats != null:
		# K.glow(game, PAL.marqueeGold, 0.5 + 2.5 q) / K.mat(game, 'plastic', '#B89A5A')
		Pp.handle.material_override = game.mats.glow(Config.PAL.marqueeGold, 0.5 + 2.5 * q) if q > 0.0 else game.mats.toon("#B89A5A", {"rough": 0.34, "rim": 0.3, "env": 0.12, "vertexColors": true})

static func setBoothLamps(g: Node3D, t: float = 0.0) -> void:
	var inst = DAU.ud(g).get("parts", {}).get("lamps")
	if not (inst is Node3D):
		return
	for i in X.instCount(inst):
		var ph := sin(i * 12.9898 + 78.233) * 43758.5453
		var rate := 0.7 + (ph - floorf(ph)) * 2.2
		var on := sin(t * rate * TAU + i * 1.7) > -0.1
		X.instSetColor(inst, i, X.lin(BOOTH_COLS[i % 5]) * (1.0 if on else 0.12))


# ---------------------------------------------------------------------------------------------- helpers
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
	static var _shaders := {}
	static var _quad: QuadMesh = null

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

	# obj.key = v for a Dictionary or an Object.
	static func s(o, k: String, v) -> void:
		if o is Dictionary:
			o[k] = v
		elif o is Object:
			o.set(k, v)

	# THREE.Color(hex) (linear components).
	static func lin(c) -> Color:
		var col: Color = DAU.color(c)
		return col.srgb_to_linear()

	static func lin3(c) -> Vector3:
		var l := lin(c)
		return Vector3(l.r, l.g, l.b)

	static func smooth(a: float, b: float, x: float) -> float:
		var t := clampf((x - a) / (b - a), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)

	static func easeOutBack(x: float, s: float = 1.8) -> float:
		x = clampf(x, 0.0, 1.0)
		return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

	static func easeOutCubic(x: float) -> float:
		return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

	static func easeInCubic(x: float) -> float:
		return pow(clampf(x, 0.0, 1.0), 3.0)

	static func wrapPi(a: float) -> float:
		return atan2(sin(a), cos(a))

	static func isToon(m) -> bool:
		if m == null or not (m is Object):
			return false
		var ud = m.get("userData")
		return ud is Dictionary and ud.has("daToon")

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

	static func relXform(n: Node, root: Node) -> Transform3D:
		var xf := Transform3D.IDENTITY
		var c := n
		while c != null and c != root:
			if c is Node3D:
				xf = (c as Node3D).transform * xf
			c = c.get_parent()
		return xf

	static func meshes(root: Node) -> Array:
		var out: Array = []
		DAU.traverse(root, func(o):
			if o is MeshInstance3D and (o as MeshInstance3D).mesh != null:
				out.append(o))
		return out

	static func hasMeshes(root: Node) -> bool:
		return not meshes(root).is_empty()

	# Box3.setFromObject(model) in the model's parent space (the parents' transforms are not applied, like JS).
	static func aabbOf(root: Node3D, withRoot: bool) -> AABB:
		var out := AABB()
		var first := true
		var base := root.transform if withRoot else Transform3D.IDENTITY
		for mi in meshes(root):
			var box: AABB = (base * relXform(mi, root)) * (mi as MeshInstance3D).get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
		return out

	# geometry.boundingSphere.radius (centre = bounding box centre, radius = farthest vertex).
	static func boundingRadius(mesh: Mesh) -> float:
		var c := mesh.get_aabb().get_center()
		var r2 := 0.0
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			for v in arr[Mesh.ARRAY_VERTEX]:
				r2 = maxf(r2, c.distance_squared_to(v))
		return sqrt(r2)

	# removeFromParent() of a node that is never reused (Godot nodes are not garbage collected).
	static func dispose(n: Node) -> void:
		if n == null or not is_instance_valid(n):
			return
		DAU.detach(n)
		n.queue_free()

	static func newCanvas(w: int, h: int):
		var path := "res://scripts/gfx/canvas2d.gd"
		if not ResourceLoader.exists(path):
			return null
		var C = load(path)
		if C == null or not C.can_instantiate():
			return null
		return C.new(w, h)

	static func poolSet(h, o: Dictionary) -> void:
		if h is Dictionary:
			var f = h.get("set")
			if f is Callable:
				f.call(o)
		elif h is Object:
			if h.has_method("set_"):
				h.set_(o)

	# ---- instanced parts (parent <name> with children <name>_<i>; colour = "instanceColor" instance uniform)
	static func _inst(inst: Node3D, i: int) -> Node:
		var c = inst.get_node_or_null(NodePath("%s_%d" % [inst.name, i]))
		if c == null and i < inst.get_child_count():
			c = inst.get_child(i)
		return c

	static func instCount(inst: Node3D) -> int:
		return inst.get_child_count()

	static func instSetColor(inst: Node3D, i: int, linColor: Color) -> void:
		var ud := DAU.ud(inst)
		if not ud.has("_instColors"):
			ud["_instColors"] = []
		var cols: Array = ud["_instColors"]
		if cols.size() <= i:
			cols.resize(i + 1)
		linColor.a = 1.0
		cols[i] = linColor
		var c = _inst(inst, i)
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).set_instance_shader_parameter("instanceColor", linColor.linear_to_srgb())

	static func instGetColor(inst: Node3D, i: int) -> Color:
		var cols = DAU.ud(inst).get("_instColors")
		if cols is Array and i < cols.size() and cols[i] is Color:
			return cols[i]
		return Color(1, 1, 1)

	# ---- effect meshes / materials
	# three's CylinderGeometry(rt, rb, h, radial, 1, openEnded=true).translate(0, ty, 0); UVs as three (v = 0 bottom).
	static func cylMesh(rt: float, rb: float, h: float, radial: int, ty: float) -> ArrayMesh:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		var slope := (rb - rt) / h
		for y in 2:
			var v := float(y)
			var r := v * (rb - rt) + rt
			for x in radial + 1:
				var u := float(x) / radial
				var th := u * TAU
				var st := sin(th)
				var ct := cos(th)
				verts.append(Vector3(r * st, -v * h + h / 2.0 + ty, r * ct))
				norms.append(Vector3(st, slope, ct).normalized())
				uvs.append(Vector2(u, 1.0 - v))
		for x in radial:
			var a := x
			var b := radial + 1 + x
			var c := radial + 1 + x + 1
			var d := x + 1
			# three (a, b, d) (b, c, d), reversed for Godot's clockwise front faces
			idx.append_array([a, d, b, b, d, c])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	static func meshNode(nm: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	static func shaderMat(nm: String, code: String, params: Dictionary) -> ShaderMaterial:
		var sh: Shader = _shaders.get(code)
		if sh == null:
			sh = Shader.new()
			sh.code = "shader_type spatial;\n" + code
			_shaders[code] = sh
		var m := ShaderMaterial.new()
		m.resource_name = nm
		m.shader = sh
		for k in params:
			m.set_shader_parameter(k, params[k])
		return m

	# THREE.MeshBasicMaterial({color (linear), opacity, map, AdditiveBlending|opaque, depthWrite, fog:false, side}).
	# Meshes built here carry three's UVs, so canvas maps are sampled with v flipped (three's flipY).
	static func basicMat(color: Color, additive: bool, doubleSided: bool, fog: bool, map = null) -> ShaderMaterial:
		var modes := ["unshaded", "shadows_disabled"]
		if additive:
			modes.append_array(["blend_add", "depth_draw_never"])
		modes.append("cull_disabled" if doubleSided else "cull_back")
		if not fog:
			modes.append("fog_disabled")
		var code := "render_mode %s;\n" % ", ".join(modes)
		code += "uniform vec4 color = vec4(1.0);\nuniform float opacity = 1.0;\n"
		code += "uniform sampler2D map : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;\n"
		code += "uniform vec2 uvOffset = vec2(0.0);\n"
		code += "void fragment() {\n\tvec4 t = texture(map, vec2(UV.x, 1.0 - UV.y) + uvOffset);\n\tALBEDO = color.rgb * t.rgb;\n"
		if additive:
			code += "\tALPHA = clamp(opacity * t.a, 0.0, 1.0);\n"
		code += "}\n"
		var m := shaderMat("basic", code, {"color": color, "opacity": 1.0})
		if map != null:
			m.set_shader_parameter("map", map)
		return m

	static func sprite(tex, color: Color, opacity: float, priority: int) -> MeshInstance3D:
		var sh: Shader = _shaders.get(SPRITE_SHADER)
		if sh == null:
			sh = Shader.new()
			sh.code = SPRITE_SHADER
			_shaders[SPRITE_SHADER] = sh
		if _quad == null:
			_quad = QuadMesh.new()
			_quad.size = Vector2(1, 1)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = priority
		if tex != null:
			m.set_shader_parameter("map", tex)
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("opacity", opacity)
		var sp := MeshInstance3D.new()
		sp.mesh = _quad
		sp.material_override = m
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.extra_cull_margin = 1.0
		return sp

	static func spriteSet(sp: MeshInstance3D, key: String, v) -> void:
		var m = sp.material_override
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter(key, v)
