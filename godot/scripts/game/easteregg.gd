# DEAD AIR — "THE SIGN-OFF" easter egg (port of src/game/easteregg.js; GDD §13 steps 1–5 + the step-6 trigger,
# §18.13 ids, §18.15 events). Step 6 (the Baron fight + ending) belongs to scripts/actors/boss.gd / scripts/game/ending.gd:
# this file opens the cage, runs the 2 s kill-switch hold and calls game.boss.start(round); the boss emits
# egg:step {step:6} / egg:complete (or calls egg.setStep(6), which emits both).
#
# STATE (ARCHITECTURE §10)  step (0..6 completed steps) · done · STEP_IDS · forceForecaster (bool, steps 3→4: rounds.gd
#   reads it: ≥ 1 Forecaster per round + the 60 % rule) · storm (the Stray Storm Dictionary | null; storm.active) ·
#   stormActive · applause (step-3 kill count, persists across rounds) · hasTape · carried (puppet ids on the belt)
# PROGRESS WITHOUT UI (every completed step 1–5): sting_ee_correct ding, the Baron's laugh from the nearest TV (angrier
#   each time: faster, higher, louder), +T.points.eeStep (economy.add(..., 'egg')), egg:step {step} (the MC rundown board
#   pins card <step> with its gold star by itself), and a music-box phrase sting_ee_<step> from every TV.
# STEP 1 "STATION IDENTIFICATION": shootables ee_bar_red/yellow/green/blue (level.objects.ee_chime_rack.raycast per bar;
#   bullets + melee, grenades/splash ignored, at most one bar per frame = shot event). Before power a dull
#   ee_chime_tunk and nothing counts. After power ee_chime_<bar> + egg:chime {bar} (the lobby swings the bar) and a
#   buffer of the last 4 hits; complete when [red, yellow, green, blue] with every gap <= T.ee.chimeGap. Beats: station
#   ID on every TV 3 s + the round motif with its brass chord (sting_round_start); the lobby fixes the neon Z/T and
#   lights the booth ON AIR lamp on egg:step. Hook: the three ghost puppets start to exist + a giggle from the case.
# STEP 2 "THE PUPPET SEGMENT": Dudley (trophy case), Sockrates (anchor desk), Hootie (prize-wheel hub) (cute felt hand
#   puppets: Blender runtime assets, blender/runtime/easteregg.py -> assets/runtime/easteregg/*.glb) live on
#   LAYERS.TV_ONLY in their area root (feeds only), and giggle every 12–20 s within
#   10 m. ON AIR (client pass: they were barely noticeable on the small CRTs) the ghosts are GHOST[key].scale x bigger
#   (Dudley 1.4 standing on the case's middle shelf, the others 1.45), turned toward their feed camera, perform (bob,
#   sway, big waves / wing flaps, jaw chatter, a squash-and-stretch hop every 2.4–5 s, sometimes with a twirl) and wear
#   an on-air look (GHOST_LOOK: a strong warm rim + softer shading, mats.variant of their felt); screens.gd keeps each
#   one in the middle of its feed through the whole camera pan. Tuned in they shrink back to 1x and their normal felt
#   while tumbling down. Shootable spheres r = T.ee.puppetR around the scaled centre ('ee_puppet_<name>'): 0.4 s static
#   flicker -> layer 0,
#   ee_puppet_reveal, drop (Dudley: the case door pops open and he tumbles out). [E] (key only, 1.2 m) picks one up: it
#   hangs bobbing from the belt slot. [E] at the theater (ee_puppet_theater.interact, r 1.5) slots every carried puppet
#   (golden silhouette). All 3: curtain opens, the puppets hop up and sing ee_kazoo_song (6 s), every living Sock
#   Hopper freezes, turns toward Studio B and pops into confetti (kill cause 'egg', no points, counts for the round).
#   Hook: one echoing ee_clap_single from Studio A (30 m), the APPLAUSE sign flickers at 2–5 Hz, the tote twitches.
# STEP 3 "CUE THE APPLAUSE": while step == 2, a zombie:kill whose pos is inside T.ee.applauseZone while the player is
#   in studio_a counts (+1, persists): the sign lights solid 0.6 s, the applause (client pass: it was inaudible under the
#   kill's gunshot) = ee_applause_near (non-positional crowd + the gloves' claps on CLAP.beats) + ee_applause_burst at
#   both bleachers (rolloff to 45 m), the tote board flips +$1 (ee_tote_flip), and APPLAUSE HANDS: a pair of white
#   cartoon gloves pops in (squash and stretch, a confetti puff) above the zombie's body, claps on CLAP.beats (a star
#   burst at each contact), floats up and fades out (2.1 s; pooled, 2 MultiMesh draws, keepColor toon, world
#   layer; only for counted kills). The first kill gets a huge crowd reaction. At 13: $13,000, thermometer-top confetti, two
#   confetti cannons (Blender runtime asset, placed here on the lighting grid) fire, ee_ovation (+ a long near layer),
#   the sign locks lit. Hook (+2 s): ee_thunder_far
#   from the newsroom (map-wide), newsroom lights flicker, weather-map suns slide off, storm + bolt magnets slide onto
#   the tower and blink, ee_map_rumble every 20 s; forceForecaster = true (+ 'egg:need_forecaster' if none is alive).
# STEP 4 "THE WEATHER": while step == 3 the next 'zombie:forecaster_storm' {pos} (a Forecaster killed with his cloud
#   intact) leaves the Stray Storm (Blender runtime asset: 1.5x cloud, #5B4A7A, grumpy face, crackles, rain column,
#   ee_storm_loop).
#   It follows the player's breadcrumb trail (a crumb every 0.25 s) at T.ee.storm.speed, 3 m above the floor (under the
#   ceiling), zaps 10 every 4 s within 2 m (visual rain only), evaporates after 90 s (fades from 75 s) or after 8 s
#   straight farther than 20 m of path (nav.dist). egg:storm {state:'spawn'|'lost'|'arrived'}. Complete when the player
#   is within 6 m (XZ) of the tower base and the storm within 8 m of the player: it races up the tower (1.5 s), a jagged
#   lightning bolt hits the top (whiteout pulse, ee_lightning_strike), the Baron flashes on every TV 0.5 s with a laugh.
#   The yard turns the beacons rainbow and Telly goes purple + arms the tape pull, both on egg:step {step:4}.
# STEP 5 "ROLL TAPE": Telly's forced pull hands out the reel (machine:telly_take {itemId:'ee_tape_reel'}, strapped to
#   the back by telly.gd). Carrying it, [E] at VTR #2 (1.5 m) loads it (1.5 s, ee_tape_thread, ee_vtr2.loadTape): its
#   monitor (scr_vtr2, a private DACanvas texture) plays the Sign-Off film badly: vertical roll 0.5·d screens/s, tearing
#   d/6, snow d/6; audio: the hymn looping from the deck with a wobble ∝ d + ee_tracking_tones (setDistance(d)). The
#   TRACKING knob ([E] key only, 1.5 m; turns and clicks all game) goes +1 per press from a random s0 to a random kT != s0,
#   d = circular distance (0..6), egg:tracking {detent, distance}. Complete when d == 0 and no knob press for 3 s while
#   within 4 m of VTR #2 (leaving pauses the timer). Beats: VTR lamp green, the clean Sign-Off film on every TV (20 s)
#   + sting_signoff_hymn, ON AIR boxes flash, ee_baron_scream from every TV. Hook: the kill-switch cage springs open
#   (ee_cage_boing), the knife switch gets a rainbow outline + glow, ee_alarm_bell rings in the yard for 10 s.
# STEP 6 TRIGGER: [E] hold T.ee.switchHold s on the kill switch (step == 5): the switch is thrown (ee_switch_thunk)
#   and game.boss.start(round) is called (boss.start plays the THUNK after its audio.stopAll). If the fight does not
#   start, or the boss goes inactive without a defeat while playing, the switch re-arms (outline back, hold again).
#   egg:step {step:6} / egg:complete from anyone are mirrored into step/done.
# EVENTS  egg:step {step} · egg:complete {} · egg:chime {bar} · egg:puppet_reveal {id} · egg:puppet_slot {id} ·
#   egg:applause {count} · egg:storm {state} · egg:tracking {detent, distance} · egg:need_forecaster {}
# DEBUG  setStep(n) (= debug.egg(n): jumps, applying each skipped step's end state instantly and emitting egg:step
#   for each) · debugHit(id, {melee}) (ee_bar_*, ee_puppet_*) · debugUse(id) (runs an interactable: 'pickup:<puppet
#   id>', 'ee_puppet_theater', 'ee_vtr2', 'ee_tracking_knob', 'ee_kill_switch') · revealLayer2(bool) (the main camera
#   also renders LAYERS.TV_ONLY) · debugKill(x, z) (a synthetic zombie:kill at x, z: counts + applause hands when it
#   qualifies) · debugClap(x, z) (just the applause hands at x, z) · debugStorm(x, z) (spawns the Stray Storm) ·
#   debugGiveTape() · debugTrack(k) · debugState() -> Dictionary (claps = live applause-hand pairs).
#
# PORT NOTES (Godot)
# * Level objects (game.level.objects.*), zombies, interact items, audio handles … may be Dictionaries (fields +
#   Callables) or Objects: every access to them goes through _g (field read), _s (field write) and _oc (method call).
# * The JS getters `stormActive`, `O` (level objects) and `powered` are GDScript properties with getters.
# * THREE.Vector3 aliasing: the JS storm kept `st.pos` as the SAME object as its root's position; here the root position
#   is the truth and st.pos is refreshed after every move (_stSetPos).
# * The static art the JS built at runtime (the three puppets, the confetti cannon, the Stray Storm's cloud/face/glow/
#   rain meshes and the applause glove geometry) is generated by blender/runtime/easteregg.py into
#   res://assets/runtime/easteregg/*.glb and loaded here (_loadModel). Per-event geometry (lightning bolts, the switch
#   outline derived from the yard's switch mesh) is built here with ArrayMesh; the VTR #2 picture is a DACanvas.
# * Not ported (engine plumbing, SPEC §0.2): warmup() / cloneBare (shader precompile samples).
# * The applause gloves are two MultiMeshInstance3D (the JS InstancedMeshes): the per-instance fade (JS aFade attribute)
#   is INSTANCE_CUSTOM.a read by a patched copy of the toon shader (_clapMaterial, like the JS onBeforeCompile patch).
# * Renames (SPEC §3.2): none.
# MP (online co-op, RECONCILE R14; every MP path guarded by _mp() / _client() / _host(), solo runs the code above):
#   the HOST owns the egg (step, puppets + carriers, applause, storm + leader, tape carrier, tracking, kill switch);
#   clients send requests and run every visual from the host's replicated actions (same code paths, host results).
#   Clients never complete a step (_complete() refuses): the host's net_step(n) runs the completion beats (_beats(n):
#   TV overrides, stings, celebrate -> economy.add(eeStep, "egg") = a team reason paid once by the host, hooks).
#   Player-bound items: puppets hang from their CARRIER's hero belt (remote heroes: render layer RemotePlayer.LAYER);
#   the theater slots the sender's puppets; the tape belongs to its carrier (only they see the VTR #2 prompt). A
#   carrier going off-air (team:offair) or leaving (net:peer) drops the puppets back to their drop spots / the tape
#   is lost and Telly re-arms the tape pull. Stray Storm: follows a LEADER (the Forecaster's killer `by`, else the
#   nearest target; a leader that stops being a target hands over to the nearest one, stranded until close); zaps
#   the nearest target within 2 m (the victim's own peer applies the 10). Applause counts kills (host events) whose
#   killer `by` stands in Studio A (any player in Studio A when the kill has no `by`). Tracking completes while any
#   target is within tracking.radius of VTR #2. Chimes / knob / kill switch: shared, first request wins.
#   MESSAGES (sys "egg"): client -> host (net.toHost; local on the host): reqBar (color) · reqPuppet (id) ·
#     reqPickup (id) · reqSlot () · reqLoad () · reqKnob () · reqSwitch ()
#   host -> everyone: chime (color, powered) · step (n) · puppet (id) · pickup (id, carrier) · slot (carrier, ids) ·
#     drop (ids) · sockPop (pos) · applause (n, pos, zid) · storm (state 'spawn' | 'lost' | 'arrived', pos, leader) ·
#     zap (victim) · tape (carrier, 0 = none) · load (carrier, s0, kT) · knob (k, by) · switch (thrown) ·
#     setStep (n) (debug jumps)
#   stream 'es' (host -> all, 10 Hz while the storm follows): PackedFloat32Array [x, y, z, rotY].
extends RefCounted

const STEP_IDS := ["ee_1_station_id", "ee_2_puppets", "ee_3_applause", "ee_4_storm", "ee_5_roll_tape", "ee_6_sign_off"]

# ------------------------------------------------------------------------------------------------ constants
const ASSET_DIR := "res://assets/runtime/easteregg/"
const BARS := ["red", "yellow", "green", "blue"]
const PRI := {"signoff": 3, "ee": 5}
const ALL_TV := ["scr_decor", "scr_mc_canned", "scr_mc_feeds", "scr_feed_*"]
const IGNORED_CAUSES := ["grenade", "explosion", "splash"]
const PUPPETS := [
	{"id": "ee_puppet_dudley", "key": "dragon", "area": "lobby", "home": [-6.75, 1.3, -2.0], "rotY": -PI / 2, "drop": [-6.0, 0, -2.0], "shift": 0.22},
	{"id": "ee_puppet_sockrates", "key": "sock", "area": "newsroom", "home": [20.2, 1.21, 0.0], "rotY": PI / 2, "drop": [19.6, 0.4, 0.0], "shift": 0},
	{"id": "ee_puppet_hootie", "key": "owl", "area": "studio_a", "home": [4.0, 2.35, -29.3], "rotY": PI, "drop": [4.0, 0.6, -28.6], "shift": 0.05},
]
# belt hangers (belt-slot local; the slot sits at the front of the hips): left hip, right hip, back
const HANG := {"dragon": [-0.21, -0.03, 0.13, 1.25], "sock": [0.21, -0.03, 0.13, -1.25], "owl": [0.0, -0.03, 0.3, PI]}
const HANG_SCALE := 0.55
const PUPPET_CENTER := 0.24
# On-air ghosts (step 2, feeds only): size, idle bob + hop height (model units), squash amount. Dudley stands on the
# trophy case's middle glass shelf (DUDLEY_SHELF above the case base) so the 1.4x ghost fits under the crown.
const GHOST := {
	"dragon": {"scale": 1.4, "bob": 0.02, "hop": 0.015, "sq": 0.5},
	"sock": {"scale": 1.45, "bob": 0.045, "hop": 0.1, "sq": 1.0},
	"owl": {"scale": 1.45, "bob": 0.045, "hop": 0.1, "sq": 1.0},
}
const GHOST_HOP := {"dur": 0.5, "every": [2.4, 5.0], "spin": 0.3}
const DUDLEY_SHELF := 1.03
# the on-air look: a strong warm rim + softer shading so the felt pops off the busy sets on small CRTs
const GHOST_LOOK := {"rim": 0.78, "rimColor": "#FFC477", "rimPower": 1.55, "wrap": 0.8}
# Applause hands (step 3): clap beats (s after the kill; ee_applause_near gets the same list), life, pop-in time,
# fade start, rise, pool size, glove scale, palm gap open / touching (m), height above the body's floor.
const CLAP := {"beats": [0.16, 0.36, 0.56, 0.76, 0.96, 1.16], "life": 2.1, "pop": 0.26, "fade": 1.5, "rise": 0.42, "max": 6,
	"scale": 1.5, "open": 0.5, "touch": 0.15, "height": 1.7}
const CLAP_STARS := ["#FFFFFF", "#FFE45C", "#FFD27A"]
const BAR_PUSH := 0.31
const BAR_R := 0.1
const STUDIO_B_C := Vector3(21, 1, -21)
const STUDIO_A_CLAP := Vector3(4, 4.5, -18)
const BLEACHERS := [Vector3(-2.5, 1.6, -13.4), Vector3(10.5, 1.6, -13.4)]
const CANNONS := [{"pos": [-1.6, 6.2, -17.2], "aim": [2.0, 1.0, -16.6]}, {"pos": [9.6, 6.2, -17.2], "aim": [6.0, 1.0, -16.6]}]
const NEWSROOM_C := Vector3(15, 3, -1)
const TOWER := Vector3(45, 0, -12)
const TOWER_TOP := Vector3(45, 29.5, -12)
const VTR_FALLBACK := Vector3(26.75, 1.0, -2.6)
const KNOB_FALLBACK := Vector3(26.75, 1.1, -3.15)
const TOTE_BASE := 12987
const STORM_COLOR := "#5B4A7A"
const RAINBOW := ["#FF4A4A", "#FF9F2E", "#FFE45C", "#5CE07A", "#4AB8FF", "#9A6BFF"]

const AX_Y := Vector3(0, 1, 0)
const AX_Z := Vector3(0, 0, 1)

static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func easeOutBack(k: float) -> float:
	return 1.0 + 2.4 * pow(k - 1.0, 3.0) + 1.4 * pow(k - 1.0, 2.0)

static func easeInOut(k: float) -> float:
	return 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0

static func v3(a) -> Vector3:
	return DAU.v3(a)

# THREE.Color.setHSL (sRGB components; the JS then works on the linear copy).
static func hueColor(t: float) -> Color:
	var h := fmod(fmod(t, 1.0) + 1.0, 1.0)
	return _hsl(h, 0.95, 0.6)

static func _hue2rgb(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 1.0 / 2.0:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p

static func _hsl(h: float, s: float, l: float) -> Color:
	if s == 0.0:
		return Color(l, l, l)
	var p := l * (1.0 + s) if l <= 0.5 else l + s - l * s
	var q := 2.0 * l - p
	return Color(_hue2rgb(q, p, h + 1.0 / 3.0), _hue2rgb(q, p, h), _hue2rgb(q, p, h - 1.0 / 3.0))

# '#hex' (sRGB) -> linear Color (THREE.Color internal value), optionally times k (HDR).
static func _lin(hex, k: float = 1.0) -> Color:
	var c := DAU.color(hex)
	return Color(DAU.srgbToLinear(c.r) * k, DAU.srgbToLinear(c.g) * k, DAU.srgbToLinear(c.b) * k, c.a)

# Ray (o, unit d) vs capsule (segment a-b, radius r): entry distance or -1.
static func rayCapsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var seg := b - a
	var w0 := o - a
	var B := d.dot(seg)
	var C := seg.dot(seg)
	var D := d.dot(w0)
	var Ee := seg.dot(w0)
	var den := C - B * B
	var s := (Ee - B * D) / den if den > 1e-8 else 0.0
	s = 0.0 if s < 0.0 else (1.0 if s > 1.0 else s)
	var t := maxf(0.0, B * s - D)
	var pr := o + d * t
	var px := a.x + seg.x * s - pr.x
	var py := a.y + seg.y * s - pr.y
	var pz := a.z + seg.z * s - pr.z
	var dd := sqrt(px * px + py * py + pz * pz)
	if dd > r:
		return -1.0
	return maxf(0.0, t - sqrt(maxf(0.0, r * r - dd * dd)))

# THREE.Quaternion.setFromUnitVectors (Godot's Quaternion(arc_from, arc_to) degenerates for opposite vectors).
static func _quatFromUnitVectors(vFrom: Vector3, vTo: Vector3) -> Quaternion:
	var r := vFrom.dot(vTo) + 1.0
	var q := Quaternion()
	if r < 1e-8:
		r = 0.0
		if absf(vFrom.x) > absf(vFrom.z):
			q = Quaternion(-vFrom.y, vFrom.x, 0.0, r)
		else:
			q = Quaternion(0.0, -vFrom.z, vFrom.y, r)
	else:
		var c := vFrom.cross(vTo)
		q = Quaternion(c.x, c.y, c.z, r)
	return q.normalized()

# ================================================================================================ generic access
# Field read on a Dictionary or an Object (the JS `o?.k ?? d`).
static func _g(o, k: String, d = null):
	if o == null:
		return d
	if o is Dictionary:
		var v = o.get(k)
		return d if v == null else v
	if o is Object:
		if not is_instance_valid(o):
			return d
		var v2 = o.get(k)
		return d if v2 == null else v2
	return d

# Field write on a Dictionary or an Object.
static func _s(o, k: String, v) -> void:
	if o == null:
		return
	if o is Dictionary:
		o[k] = v
	elif o is Object and is_instance_valid(o):
		o.set(k, v)

# Method call on a Dictionary (Callable field) or an Object (method or Callable property): the JS `o?.m?.(...args)`.
static func _oc(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Dictionary:
		var f = o.get(m)
		if f is Callable and f.is_valid():
			return f.callv(args)
		return null
	if o is Object and is_instance_valid(o):
		if o.has_method(m):
			return o.callv(m, args)
		var f2 = o.get(m)
		if f2 is Callable and f2.is_valid():
			return f2.callv(args)
	return null

static func _has(o, m: String) -> bool:
	if o == null:
		return false
	if o is Dictionary:
		return o.get(m) is Callable
	if o is Object and is_instance_valid(o):
		return o.has_method(m) or o.get(m) is Callable
	return false

static func _finite(x) -> bool:
	return (x is float or x is int) and is_finite(float(x))

# ------------------------------------------------------------------------------------------------ scene-graph glue
# World transform (works outside the tree too: composes the parent chain).
static func _worldXform(n: Node3D) -> Transform3D:
	if n == null:
		return Transform3D.IDENTITY
	if n.is_inside_tree():
		return n.global_transform
	var t := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

static func _worldPos(n: Node3D) -> Vector3:
	return _worldXform(n).origin

static func _worldQuat(n: Node3D) -> Quaternion:
	return _worldXform(n).basis.get_rotation_quaternion()

# three's parent.add(child): moves the child (local transform kept).
static func _add(parent: Node, child: Node) -> void:
	if parent == null or child == null:
		return
	var old := child.get_parent()
	if old == parent:
		return
	if old != null:
		old.remove_child(child)
	parent.add_child(child)

# three's parent.attach(child): moves the child keeping its world transform.
static func _attach(parent: Node3D, child: Node3D) -> void:
	if parent == null or child == null:
		return
	var xf := _worldXform(child)
	_add(parent, child)
	child.transform = _worldXform(parent).affine_inverse() * xf

static func _removeFromParent(n: Node) -> void:
	if n != null and is_instance_valid(n):
		DAU.detach(n)

static func _free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		DAU.detach(n)
		n.queue_free()

# ============================================================================================== the easter egg
var game
var E: Dictionary
var S: Dictionary

var step := 0
var done := false
var forceForecaster := false
var storm = null
var applause := 0
var hasTape := false
var carried: Array = []
var puppets := {}
var _jobs: Array = []
var _handles: Array = []
var _magFall: Array = []
var _cannons: Array = []
var _built := false
var _emitting := false
var _bars: Array = []
var _barFrame := -1
var _crumbs: Array = []
var _crumbT := 0.0
var _laughs := 0
var _claps: Array = []          # live applause-hand pairs (step 3)
var _clapPool: Array = []
var _hands = null               # { mat, l, r } the two glove MultiMeshInstance3Ds

# (set by reset() and the step code; declared here)
var _killSwitchUsed := false
var _switchThrownAt = null
var _signMode := "off"
var _signSolidT := 0.0
var _flickT := 0.0
var _toteTwitchT := 3.0
var _toteTwitchBack := -1.0
var _mapBlink := false
var _rumbleT := 20.0
var _onAirT := -1.0
var _onAirOn = null
var _whiteT := -1.0
var _cageT := -1.0
var _switchT := -1.0
var _song = null
var _socks: Array = []
var _storm2 = null
var _track = null
var _outline = null
var _alarm = null
var _rackFront = null
var _mapRest = null
var _picture = null
var _vtrPos: Vector3 = VTR_FALLBACK
var _knobPos: Vector3 = KNOB_FALLBACK
var _reel = null
var _reelFly = null
var _tones = null
var _hymn = null
var _strikeFx = null
var _boltM = null
var _models := {}               # asset name -> PackedScene (cache)
# MP (see the header)
var tapeCarrier := 0            # peer id carrying the EE reel (0: nobody)
var _esT := 0.0
var _esPos = null               # client: the storm's streamed position / yaw
var _esYaw := 0.0

var stormActive: bool:
	get:
		return storm != null and bool(storm.active)

func _init(g) -> void:
	game = g
	E = Config.T.ee
	S = E.storm

# ------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	var g = game
	_build()
	var ev = g.events
	ev.on("zombie:kill", func(e): _onKill(e))
	ev.on("zombie:forecaster_storm", func(e): _onForecasterStorm(e))
	ev.on("machine:telly_take", func(e): _onTellyTake(e))
	ev.on("egg:step", func(e):
		if not _emitting and e != null and float(_g(e, "step", 0)) > step:
			_mirror(int(e.step)))
	ev.on("egg:complete", func(_e):
		if not _emitting and not done:
			step = STEP_IDS.size()
			done = true)
	# MP host: a carrier off the air / gone drops what it carried
	ev.on("team:offair", func(e): if e is Dictionary and e.get("id") != null: _onPlayerLost(int(e.id)))
	ev.on("net:peer", func(e): if e is Dictionary and e.get("joined") == false and e.get("id") != null: _onPlayerLost(int(e.id)))
	var n = _net()
	if n != null and n.has_method("registerStream"):
		n.registerStream("es", "egg")
	_registerAll()

func reset() -> void:
	_jobs.clear()
	tapeCarrier = 0
	_esPos = null
	step = 0
	done = false
	forceForecaster = false
	applause = 0
	hasTape = false
	carried = []
	_bars.clear()
	_barFrame = -1
	_crumbs.clear()
	_laughs = 0
	_killSwitchUsed = false
	_signMode = "off"
	_signSolidT = 0.0
	_toteTwitchT = 3.0
	_toteTwitchBack = -1.0
	_mapBlink = false
	_rumbleT = 20.0
	_onAirT = -1.0
	_whiteT = -1.0
	_cageT = -1.0
	_switchT = -1.0
	_song = null
	_socks = []
	_storm2 = null
	_removeStorm(true)
	_stopTracking()
	_track = null
	_removeOutline()
	_magFall.clear()
	_clearClaps()
	for h in _handles:
		_oc(h, "cancel")
	_handles = []
	_oc(_alarm, "stop", [0.1])
	_alarm = null
	if not _built:
		return
	for p in puppets.values():
		_resetPuppet(p)
	_restoreMap()
	for c in _cannons:
		c.kick = -1.0
		(c.parts.barrel as Node3D).position = Vector3.ZERO
	_oc(game.screens, "setSource", ["scr_vtr2", null])
	_registerAll()

func update(dt: float) -> void:
	if not _built:
		return
	var g = game
	var rdt: float = g.time.realDt if float(g.time.realDt) != 0.0 else dt
	# scheduled beats (world time: they hold during commercials / time.scale 0)
	if _jobs.size() and dt > 0.0:
		for i in range(_jobs.size() - 1, -1, -1):
			if i >= _jobs.size():
				continue
			var j: Dictionary = _jobs[i]
			j.t -= dt
			if j.t <= 0.0:
				_jobs.remove_at(i)
				(j.fn as Callable).call()
	_updatePuppets(dt)
	_updateSong(dt)
	_updateSocks(dt)
	_updateApplauseProps(dt)
	_updateMap(dt)
	_updateStorm(dt)
	_updateTracking(dt)
	_updateYard(dt, rdt)
	_updatePost(rdt)
	_updateClaps(rdt)

# ------------------------------------------------------------------------------------------ helpers
var O: Dictionary:
	get:
		var o = _g(game.level, "objects")
		return o if o is Dictionary else {}

var powered: bool:
	get:
		return bool(_g(game.machines, "powerOn", false))

# ------------------------------------------------------------------------------------------ MP helpers
func _net():
	return game.get("net")

func _mp() -> bool:
	var n = _net()
	return n != null and n.inGame

func _client() -> bool:
	return _mp() and _net().isClient

func _host() -> bool:
	return _mp() and _net().isHost

func _fromHost() -> bool:
	return _client() and int(_net().sender) == 1

func _req(m: String, args: Array = []) -> void:
	_net().toHost("egg", m, args)

func _lid() -> int:
	return int(_net().localId) if _mp() else 1

func _pl(id: int):
	return _net().playerById(id) if _mp() else (game.player if id == 1 else null)

# The local player carries at least one puppet / the tape (solo: the old fields).
func _hasCarried() -> bool:
	if not _mp():
		return carried.size() > 0
	for p in puppets.values():
		if p.state == "carried" and int(p.get("carrier", 0)) == _lid():
			return true
	return false

func _tapeMine() -> bool:
	return tapeCarrier == _lid() if _mp() else hasTape

# MP host: player `id` went off the air or left: its puppets go back to their drop spots, its tape is lost.
func _onPlayerLost(id: int) -> void:
	if not _host():
		return
	var ids := []
	for p in puppets.values():
		if p.state == "carried" and int(p.get("carrier", 0)) == id:
			ids.append(p.id)
	if not ids.is_empty():
		_net().everyone("egg", "drop", [ids])
	if tapeCarrier == id and step == 4 and _track == null:
		var t = game.telly
		if _has(t, "rearmTape"):
			_oc(t, "rearmTape")     # mp-machines: replicated (old reel freed, the tape pull armed again)
		else:
			_oc(t, "setMood", ["purple"])
			_oc(t, "forceTapePull")
		_net().everyone("egg", "tape", [0])

func _later(t: float, fn: Callable) -> void:
	_jobs.append({"t": t, "fn": fn})

func _play(id: String, o: Dictionary = {}):
	var a = game.audio
	if a == null or not a.has_method("play"):
		return null
	return a.play(id, o)

func _areaRoot(area: String) -> Node3D:
	var roots = _g(game.level, "areaRoots")
	var r = roots.get(area) if roots is Dictionary else null
	return r if r is Node3D else game.scene

func _emit(name: String, payload) -> void:
	_emitting = true
	game.events.emit(name, payload)
	_emitting = false

func _override(source, groups, seconds: float, priority: int):
	var s = game.screens
	if s == null or not _has(s, "override"):
		return null
	var h = _oc(s, "override", [source, groups, seconds, priority])
	if h != null:
		_handles.append(h)
	return h

func _tvSound(id: String, o: Dictionary = {}):
	var s = game.screens
	if s != null and _has(s, "speaker"):
		return _oc(s, "speaker", [id, o])
	return _play(id, o)

func _baronLaugh() -> void:
	_laughs += 1
	var n := _laughs
	_tvSound("baron_laugh", {"near": 2, "rate": 1 + 0.07 * n, "detune": 40 * n, "vol": 0.85 + 0.1 * n})

# Common completion beats of steps 1–5 (GDD §13 "Every completed step also triggers").
func _celebrate(n: int, o: Dictionary = {}) -> void:
	var laugh: float = o.get("laugh", 1.6)
	var box: float = o.get("box", 3.0)
	_play("sting_ee_correct")
	_oc(game.economy, "add", [Config.T.points.eeStep, "egg"])
	if laugh >= 0.0:
		_later(laugh, func(): _baronLaugh())
	if box >= 0.0:
		_later(box, func(): _play("sting_ee_%d" % n))

# step n completed (n = 1..5): the state change + egg:step (MC card, neon, beacons, Telly react to it)
func _complete(n: int) -> bool:
	if step != n - 1 or _client():
		return false
	step = n
	if _host():
		_net().toAll("egg", "step", [n])
	_emit("egg:step", {"step": n})
	return true

func _beats(n: int) -> void:
	match n:
		1: _beats1()
		2: _beats2()
		3: _beats3()
		4: _beats4()
		5: _beats5()

# MP client: the host completed step n (missed steps, if any, are applied instantly first).
func net_step(n) -> void:
	if not _fromHost() or int(n) <= step:
		return
	while step < int(n) - 1:
		step += 1
		_applyInstant(step)
	step = int(n)
	_emit("egg:step", {"step": step})
	_beats(step)

# someone else (the boss) advanced the egg: keep our state in sync
func _mirror(n: int) -> void:
	var tgt := mini(STEP_IDS.size(), n)
	while step < tgt:
		step += 1
		_applyInstant(step)
	if step >= STEP_IDS.size() and not done:
		done = true

# ------------------------------------------------------------------------------------------ debug jumps
func setStep(n) -> int:
	var target := clampi(int(floor(float(n))), 0, STEP_IDS.size())
	if target < step:
		# backwards: rebuild the world from scratch, then replay forward silently
		var keep = _g(game.economy, "points")
		reset()
		if keep != null and game.economy != null:
			game.economy.points = keep
	while step < target:
		step += 1
		_applyInstant(step)
		_emit("egg:step", {"step": step})
		_applyHook(step)
	step = target
	if target == STEP_IDS.size() and not done:
		done = true
		_emit("egg:complete", {})
	if _host():
		_net().toAll("egg", "setStep", [target])
	return step

# the end state of step k, applied instantly (debug jumps and mirrored steps)
func _applyInstant(k: int) -> void:
	var O_ := O
	if k == 1:
		_oc(O_.get("neon_logo"), "setState", ["lit"])
		_oc(O_.get("booth_on_air"), "set", [true])
	elif k == 2:
		for p in puppets.values():
			_placeOnStage(p)
		_oc(O_.get("ee_puppet_theater"), "setOpen", [1, 0])
	elif k == 3:
		applause = E.applauseKills
		_oc(O_.get("ee_tote_board"), "setValue", [TOTE_BASE + E.applauseKills])
		_signMode = "locked"
		_oc(O_.get("ee_applause_sign"), "setLit", [true])
		_moveMagnets(0)
	elif k == 4:
		forceForecaster = false
		_removeStorm(true)
		_mapBlink = false
		_restoreMapTower()
	elif k == 5:
		var vtr = O_.get("ee_vtr2")
		if vtr != null and not _g(vtr, "loaded", false):
			_oc(vtr, "loadTape", [0.2])
		_oc(vtr, "setLamp", ["green", false])
		hasTape = false
		_stopTracking()
		_oc(game.screens, "setSource", ["scr_vtr2", "signoff_film"])
		_openCage(true)

# the hook toward step k+1 that a debug jump should leave running
func _applyHook(k: int) -> void:
	if k == 1:
		for p in puppets.values():
			if p.state == "dormant":
				_ghost(p)
	if k == 2:
		_signMode = "flicker"
	if k == 3:
		forceForecaster = true
		_mapBlink = true
		_rumbleT = 20.0

# ================================================================================================ art (Blender assets)
# Loads res://assets/runtime/easteregg/<name>.glb (blender/runtime/easteregg.py) and returns the prop root: the glTF
# node carrying the "da" extras (JS root userData), with its materials converted by game.mats.fromSpec and every
# node's "da" extras restored into DAU.ud(node). Parts ({name: node name}) are resolved to the nodes. A missing asset
# yields an empty placeholder (warned once), so the egg's logic keeps running.
func _loadModel(name: String, convertMats: bool = true) -> Node3D:
	var path := ASSET_DIR + name + ".glb"
	var ps = _models.get(name)
	if ps == null:
		if not ResourceLoader.exists(path):
			push_warning("[egg] missing runtime asset %s (run blender/build_all.py --only runtime)" % path)
			_models[name] = false
		else:
			_models[name] = load(path)
		ps = _models[name]
	if not (ps is PackedScene):
		var ph := DAU.node3d(name)
		DAU.ud(ph)["parts"] = {}
		return ph
	var inst: Node = (ps as PackedScene).instantiate()
	# the glTF scene root wraps the prop root (the node with "da" extras)
	var root: Node3D = null
	if _extrasDa(inst) != null:
		root = inst as Node3D
	else:
		for c in inst.get_children():
			if c is Node3D and _extrasDa(c) != null:
				root = c
				break
		# plain groups carry no extras: a single top node is the root (the storm, the gloves)
		if root == null and inst.get_child_count() == 1 and inst.get_child(0) is Node3D:
			root = inst.get_child(0)
		if root == null:
			root = inst as Node3D
		else:
			inst.remove_child(root)
			inst.free()
	_convertModel(root, convertMats)
	return root

static func _extrasDa(n):
	if n == null or not n.has_meta("extras"):
		return null
	var ex = n.get_meta("extras")
	if ex is Dictionary and ex.has("da"):
		var da = ex.da
		if da is String:
			return JSON.parse_string(da)
		return da
	return null

func _convertModel(root: Node3D, convertMats: bool = true) -> void:
	var mats = game.mats if convertMats else null
	var nodes: Array = []
	DAU.traverse(root, func(n): nodes.append(n))
	for n in nodes:
		if n is Node3D:
			(n as Node3D).rotation_order = EULER_ORDER_XYZ
		var da = _extrasDa(n)
		if da is Dictionary:
			var ud := DAU.ud(n)
			for k in da:
				ud[k] = da[k]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mats != null and _has(mats, "fromSpec"):
				for i in mi.mesh.get_surface_count():
					var m: Material = mi.mesh.surface_get_material(i)
					var spec = _extrasDa(m) if m != null else null
					if spec is Dictionary:
						var cm = mats.fromSpec(spec, m)
						if cm is Material:
							mi.set_surface_override_material(i, cm)
			var ud2 := DAU.ud(mi)
			if ud2.has("castShadow"):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if ud2.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if ud2.get("visible") == false:
				mi.visible = false
	# root userData: parts {name: node name|null} -> nodes; {"__node": name} references -> nodes
	var rud := DAU.ud(root)
	var parts = rud.get("parts", {})
	var out := {}
	if parts is Dictionary:
		for k in parts:
			var v = parts[k]
			if v is Dictionary and v.has("__node"):
				v = v["__node"]
			out[k] = _findNode(root, str(v)) if v is String else null
	rud["parts"] = out
	for k in rud.keys():
		var v2 = rud[k]
		if v2 is Dictionary and v2.has("__node"):
			rud[k] = _findNode(root, str(v2["__node"]))

static func _findNode(root: Node, name: String) -> Node:
	if root.name == name:
		return root
	var n := root.find_child(name, true, false)
	if n == null:
		# Godot sanitizes some characters of node names (':' '.' '@' …)
		n = root.find_child(name.validate_node_name(), true, false)
	return n

static func _meshes(root: Node) -> Array:
	var out: Array = []
	DAU.traverse(root, func(n):
		if n is MeshInstance3D:
			out.append(n))
	return out

# Dudley: purple felt dragon, googly eyes, yellow belly (GDD §13 step 2). ~0.5 m, base at y 0, front -z.
# Sockrates: striped sock puppet with tiny spectacles, a toga sash, a laurel wreath and a felt beard.
# Hootie: brown felt owl host with huge round eyes, ear tufts, a red bow tie.
# (geometry: blender/runtime/easteregg.py; finishPuppet's shadow flags are applied here)
func buildDudley(_game) -> Node3D:
	return _finishPuppet(_loadModel("ee_puppet_dudley"))

func buildSockrates(_game) -> Node3D:
	return _finishPuppet(_loadModel("ee_puppet_sockrates"))

func buildHootie(_game) -> Node3D:
	return _finishPuppet(_loadModel("ee_puppet_hootie"))

func _finishPuppet(g: Node3D) -> Node3D:
	for o in _meshes(g):
		(o as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parts: Dictionary = DAU.ud(g).get("parts", {})
	for k in ["jaw", "armL", "armR"]:
		if not parts.has(k):
			parts[k] = null
	DAU.ud(g)["parts"] = parts
	return g

# Confetti cannon for the lighting grid (step 3): a striped barrel with a flared gold muzzle on a clamp post.
# Pivot at the origin; the post rises to the grid (+y); parts.barrel points along aimDir (its local +y).
func buildCannon(_game, aimDir: Vector3) -> Node3D:
	var g := _loadModel("ee_confetti_cannon")
	var parts: Dictionary = DAU.ud(g).get("parts", {})
	var barrel = parts.get("barrel")
	if not (barrel is Node3D):
		barrel = DAU.node3d("barrel")
		g.add_child(barrel)
		parts["barrel"] = barrel
		DAU.ud(g)["parts"] = parts
	(barrel as Node3D).quaternion = _quatFromUnitVectors(Vector3(0, 1, 0), aimDir)
	for o in _meshes(g):
		(o as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g

# The Stray Storm: a 1.5x Forecaster cloud in #5B4A7A with a grumpy face, an inner crackle glow and a rain column.
# Meshes + the face / rain canvas textures come from the asset; the materials are built here (the JS built them in
# code too: the cloud toon, and unlit ones for the face, glow and rain).
func buildStorm(g) -> Dictionary:
	var root := _loadModel("ee_stray_storm", false)   # (materials built below, like the JS)
	root.name = "stray_storm"
	var body: Node3D = _findNode(root, "body") as Node3D
	if body == null:
		body = DAU.node3d("body")
		root.add_child(body)
	var cloud: MeshInstance3D = _findNode(root, "cloud") as MeshInstance3D
	var face: MeshInstance3D = _findNode(root, "face") as MeshInstance3D
	var glow: MeshInstance3D = _findNode(root, "glow") as MeshInstance3D
	var rain: MeshInstance3D = _findNode(root, "rain") as MeshInstance3D
	if cloud != null:
		if g.mats != null and _has(g.mats, "toon"):
			var mat = g.mats.toon(STORM_COLOR, {"rough": 0.95, "rim": 0.32, "rimColor": "#B9A4F0", "rimPower": 2.4, "wrap": 0.7, "keepColor": true, "emissive": "#1C1430", "emissiveIntensity": 0.6})
			if mat is Material:
				cloud.material_override = mat
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# grumpy face: angry brows, squinting eyes with little pupils, a wobbly frown (canvas 'egg.storm_face')
	var faceMat := _basicMat({"map": _surfaceTex(face), "transparent": true, "alphaTest": 0.3, "depthWrite": false, "renderOrder": 2})
	if face != null:
		face.material_override = faceMat
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# crackle glow (inner)
	var glowMat := _basicMat({"color": _lin("#C9A8FF", 2.2), "transparent": true, "opacity": 0.0, "additive": true, "depthWrite": false})
	if glow != null:
		glow.material_override = glowMat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# rain column: additive streaks scrolling down (canvas 'egg.storm_rain', repeat (4, 1))
	var rainTex := {"offset": Vector2(0, 0), "repeat": Vector2(4, 1)}
	var rainMat := _basicMat({"map": _surfaceTex(rain), "color": _lin("#AFC4FF"), "transparent": true, "opacity": 0.7, "additive": true, "depthWrite": false, "side": "double", "repeat": true})
	if rain != null:
		rain.material_override = rainMat
		rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rainUv(rainMat, rainTex)
	root.scale = Vector3.ONE * 0.92
	return {"root": root, "body": body, "cloud": cloud, "face": face, "faceMat": faceMat, "glow": glow, "glowMat": glowMat,
		"rain": rain, "rainMat": rainMat, "rainTex": rainTex}

# the canvas texture of a mesh's imported material: its "da" spec mapFile (the shared PNG), else the albedo texture
static func _surfaceTex(mi: MeshInstance3D) -> Texture2D:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return null
	var m = mi.mesh.surface_get_material(0)
	var spec = _extrasDa(m) if m != null else null
	if spec is Dictionary and spec.get("mapFile") is String and ResourceLoader.exists(spec.mapFile):
		var t = load(spec.mapFile)
		if t is Texture2D:
			return t
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null

# three.js texture repeat/offset on the rain map (the rainTex clone's transform; the asset keeps raw UVs).
static func _rainUv(mat: ShaderMaterial, rt: Dictionary) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("uv_scale", rt.repeat)
	mat.set_shader_parameter("uv_offset", rt.offset)

# Unlit material (THREE.MeshBasicMaterial): color (linear, may be HDR), opacity, map (sRGB), alphaTest, additive,
# side 'front'|'back'|'double', depthWrite, renderOrder, repeat (map wrap), uv_scale/uv_offset (three texture
# repeat/offset). Mesh UVs from the assets are three.js UVs (dalib); the canvas is sampled at (u, 1 - v) = three's flipY.
const FOG_INC := "res://shaders/da_common.gdshaderinc"
static var _basicShaders := {}
static func _basicMat(o: Dictionary) -> ShaderMaterial:
	var additive: bool = o.get("additive", false)
	var transparent: bool = o.get("transparent", false)
	var side: String = o.get("side", "front")
	var depthWrite: bool = o.get("depthWrite", true)
	var hasMap: bool = o.get("map") != null
	var repeat: bool = o.get("repeat", false)
	var key := "%s|%s|%s|%s|%s|%s" % [additive, transparent, side, depthWrite, hasMap, repeat]
	var sh: Shader = _basicShaders.get(key)
	if sh == null:
		var modes: Array = ["unshaded"]
		modes.append("blend_add" if additive else "blend_mix")
		modes.append({"front": "cull_back", "back": "cull_front", "double": "cull_disabled"}.get(side, "cull_back"))
		modes.append("depth_draw_opaque" if depthWrite else "depth_draw_never")
		# three's scene fog (THREE.Fog) as the project's fog-as-uniform (shaders/da_common.gdshaderinc)
		var fog := ResourceLoader.exists(FOG_INC)
		if fog:
			modes.append("fog_disabled")
		var code := "shader_type spatial;\nrender_mode %s;\n" % ", ".join(modes)
		if fog:
			code += "#include \"%s\"\n" % FOG_INC
		code += "uniform vec4 color = vec4(1.0);\nuniform float opacity = 1.0;\nuniform float alpha_test = 0.0;\n"
		code += "uniform vec2 uv_scale = vec2(1.0);\nuniform vec2 uv_offset = vec2(0.0);\n"
		if hasMap:
			code += "uniform sampler2D map : source_color, filter_linear_mipmap%s;\n" % (", repeat_enable" if repeat else ", repeat_disable")
		code += "void fragment() {\n\tvec4 c = color;\n"
		if hasMap:
			code += "\tvec2 t = UV * uv_scale + uv_offset;\n\tc *= texture(map, vec2(t.x, 1.0 - t.y));\n"
		code += "\tif (c.a * opacity < alpha_test) { discard; }\n"
		if fog:
			code += "\tc.rgb = mix(c.rgb, daFogColor, daFogF(-VERTEX.z, CAMERA_VISIBLE_LAYERS));\n"
		code += "\tALBEDO = c.rgb;\n"
		if transparent:
			code += "\tALPHA = c.a * opacity;\n"
		code += "}\n"
		sh = Shader.new()
		sh.code = code
		_basicShaders[key] = sh
	var m := ShaderMaterial.new()
	m.shader = sh
	var c: Color = o.get("color", Color(1, 1, 1))
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("opacity", float(o.get("opacity", 1.0)))
	m.set_shader_parameter("alpha_test", float(o.get("alphaTest", 0.0)))
	if hasMap:
		m.set_shader_parameter("map", o.map)
	m.render_priority = int(o.get("renderOrder", 0))
	return m

static func _setOpacity(m, a: float) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("opacity", a)

# Jagged lightning: segments of thin open cylinders (5 sides) along a jittered polyline (+ branches), one ArrayMesh.
func boltGeometry(from: Vector3, to: Vector3, o: Dictionary = {}) -> ArrayMesh:
	var jag: float = o.get("jag", 0.18)
	var segs: int = o.get("segs", 12)
	var width: float = o.get("width", 0.05)
	var branches: int = o.get("branches", 2)
	var rand: Callable = o.get("rand", func(): return randf())
	var pts: Array = []
	var dir := to - from
	var blen := dir.length()
	var side := Vector3(-dir.z, 0, dir.x).normalized()
	if side.length_squared() < 0.5:
		side = Vector3(1, 0, 0)
	var side2 := dir.cross(side).normalized()
	for i in segs + 1:
		var k := float(i) / segs
		var p := from.lerp(to, k)
		if i > 0 and i < segs:
			p += side * ((rand.call() - 0.5) * 2.0 * jag * blen / segs * 2.2)
			p += side2 * ((rand.call() - 0.5) * 2.0 * jag * blen / segs * 2.2)
		pts.append(p)
	var verts: Array = []        # (an Array: lambdas capture packed arrays by value)
	var seg := func(a: Vector3, b: Vector3, w: float) -> void:
		var l := a.distance_to(b)
		var q := _quatFromUnitVectors(Vector3(0, 1, 0), (b - a).normalized())
		# THREE.CylinderGeometry(w, w, l, 5, 1, true) translated (0, l/2, 0): ring y=l (top) and y=0
		var ring := func(y: float) -> Array:
			var r: Array = []
			for x in 6:
				var th := float(x) / 5.0 * TAU
				r.append(a + q * Vector3(w * sin(th), y, w * cos(th)))
			return r
		var top: Array = ring.call(l)
		var bot: Array = ring.call(0.0)
		for x in 5:
			var va: Vector3 = top[x]
			var vb: Vector3 = bot[x]
			var vc: Vector3 = bot[x + 1]
			var vd: Vector3 = top[x + 1]
			# three faces (a, b, d), (b, c, d) counter-clockwise -> Godot clockwise
			verts.append_array([va, vd, vb, vb, vd, vc])
	for i in pts.size() - 1:
		seg.call(pts[i], pts[i + 1], width * (1.0 - (float(i) / pts.size()) * 0.3))
	for b in branches:
		var i0 := 2 + int(floor(rand.call() * (segs - 4)))
		var a: Vector3 = pts[i0]
		for k in 3:
			var n: Vector3 = a + dir * (0.06 + rand.call() * 0.04) + side * ((rand.call() - 0.3) * blen * 0.08) + side2 * ((rand.call() - 0.5) * blen * 0.05)
			seg.call(a, n, width * 0.45)
			a = n
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

# ============================================================================================== TrackingPicture
# Private CRT picture for VTR #2: the Sign-Off film with vertical roll, tearing and snow (GDD §13 step 5 part C).
class TrackingPicture extends RefCounted:
	var game
	var W := 256
	var H := 192
	var film
	var roll
	var out
	var snow
	var fctx
	var rctx
	var octx
	var texture = null
	var phase := 0.0
	var t := 0.0
	var acc := 1.0
	var filmT := 0.0
	var d := 6.0

	func _init(g) -> void:
		game = g
		var path := "res://scripts/gfx/canvas2d.gd"
		if not ResourceLoader.exists(path):
			push_warning("[egg] DACanvas missing: VTR #2 picture disabled")
			return
		var DC = load(path)
		film = DC.new(W, H)
		roll = DC.new(W, H)
		out = DC.new(W, H)
		snow = DC.new(W, H * 2)
		fctx = film.getContext("2d")
		rctx = roll.getContext("2d")
		octx = out.getContext("2d")
		var sctx = snow.getContext("2d")
		var img = sctx.createImageData(W, H * 2)
		var data = img.data
		var n: int = data.size()
		var i := 0
		while i < n:
			var v: int = 0 if randf() < 0.5 else int(150 + randf() * 105)
			data[i] = v
			data[i + 1] = v
			data[i + 2] = v
			data[i + 3] = 255
			i += 4
		img.data = data
		sctx.putImageData(img, 0, 0)
		texture = out.texture

	func update(dt: float, dd: float, visible: bool) -> void:
		t += dt
		filmT += dt
		d = dd
		phase = fmod(phase + dt * 0.5 * dd, 1.0)
		acc += dt
		if not visible or acc < 1.0 / 15.0 or out == null:
			return
		acc = 0.0
		var cards = game.cards
		if cards != null and _hasM(cards, "drawTo"):
			_callM(cards, "drawTo", [fctx, "signoff_film", W, H, fmod(filmT, 20.0)])
		else:
			fctx.fillStyle = "#223"
			fctx.fillRect(0, 0, W, H)
		var k := dd / 6.0
		# vertical roll: the frame slides up with the black blanking bar between two copies
		var bar := int(floor(H * 0.09 + 0.5))
		var off := int(floor(phase * (H + bar) + 0.5))
		var r = rctx
		r.fillStyle = "#050308"
		r.fillRect(0, 0, W, H)
		r.drawImage(film, 0, -off)
		r.drawImage(film, 0, H + bar - off)
		# tearing: horizontal bands shifted by a wobbling sine (amplitude d/6)
		var o = octx
		o.fillStyle = "#050308"
		o.fillRect(0, 0, W, H)
		var bands := 24
		var bh := float(H) / bands
		for i in bands:
			var y := i * bh
			var tear := k * (sin(y * 0.071 + t * 7.3) * 0.11 + sin(y * 0.23 + t * 17.0) * 0.05 + ((randf() - 0.5) * 0.4 if randf() < 0.08 * k else 0.0))
			o.drawImage(roll, 0, y, W, bh + 1, tear * W, y, W, bh + 1)
		# snow + a dimming/chroma wash
		if k > 0.001:
			o.globalAlpha = minf(0.85, k * 0.9)
			o.globalCompositeOperation = "lighter"
			o.drawImage(snow, 0, -floorf(randf() * H))
			o.globalCompositeOperation = "source-over"
			o.globalAlpha = k * 0.25
			o.fillStyle = "#20183A"
			o.fillRect(0, 0, W, H)
			o.globalAlpha = 1.0
		if out.has_method("redraw"):
			out.redraw()

	static func _hasM(o, m: String) -> bool:
		if o is Dictionary:
			return o.get(m) is Callable
		return o is Object and (o.has_method(m) or o.get(m) is Callable)

	static func _callM(o, m: String, args: Array):
		if o is Dictionary:
			return (o.get(m) as Callable).callv(args)
		if o.has_method(m):
			return o.callv(m, args)
		return (o.get(m) as Callable).callv(args)

# ================================================================================================ build
func _build() -> void:
	var g = game
	# puppets
	var builders := {"dragon": buildDudley, "sock": buildSockrates, "owl": buildHootie}
	for def in PUPPETS:
		var model: Node3D = (builders[def.key] as Callable).call(g)
		var root := DAU.node3d(def.id)
		var pivot := DAU.node3d()
		root.add_child(pivot)
		pivot.add_child(model)
		var p: Dictionary = def.duplicate(true)
		p.merge({"model": model, "root": root, "pivot": pivot, "parts": DAU.ud(model).get("parts", {}), "state": "dormant", "t": 0.0,
			"giggleT": 14.0, "home": v3(def.home), "drop": v3(def.drop), "pos": Vector3(), "blob": null, "from": Vector3(),
			"to": Vector3(), "fromQ": Quaternion(), "toQ": Quaternion(), "fromS": 1.0, "toS": 1.0, "dur": 0.0, "hanger": null,
			"phase": randf() * TAU, "gs": GHOST[def.key].scale, "face": 0.0, "looks": [], "look": null, "hopT": 2.0,
			"hopK": -1.0, "hopSpin": false, "layer": null}, true)
		# on-air look: every toon mesh gets a warm-rim variant of its felt/plastic (same programs, uniforms only)
		if g.mats != null and _has(g.mats, "variant"):
			for mi in _meshes(model):
				if mi.mesh == null:
					continue
				for i in mi.mesh.get_surface_count():
					var base = mi.get_active_material(i)
					if base == null:
						continue
					var look = g.mats.variant(base, GHOST_LOOK)
					if look is Material and look != base:
						p.looks.append([mi, i, base, look])
		puppets[def.id] = p
	_resolveHomes()
	for p in puppets.values():
		p.face = _faceYaw(p)
	_buildHands()
	# confetti cannons on the Studio A lighting grid (visible from the start, dormant)
	_cannons = []
	for c in CANNONS:
		var dir := (v3(c.aim) - v3(c.pos)).normalized()
		var m := buildCannon(g, dir)
		m.position = v3(c.pos)
		_add(_areaRoot("studio_a"), m)
		_cannons.append({"group": m, "parts": DAU.ud(m).parts, "kick": -1.0, "dir": dir})
	# weather-map magnet rest poses (restored on a new game)
	_mapRest = null
	var map = O.get("ee_weather_map")
	var mparts = _g(map, "parts")
	if mparts is Dictionary:
		_mapRest = {}
		for k in mparts:
			var mm = mparts[k]
			if mm is Node3D:
				_mapRest[k] = {"p": mm.position, "r": mm.rotation, "v": mm.visible}
	# VTR #2 picture
	_picture = TrackingPicture.new(g)
	_built = true
	for p in puppets.values():
		_resetPuppet(p)

func _resolveHomes() -> void:
	var O_ := O
	var A = _g(game.level, "anchors", {})
	if not (A is Dictionary):
		A = {}
	var P := puppets
	var tc = O_.get("ee_trophy_case")
	var ad = A.get("ee_puppet_dudley")
	if _g(tc, "dudley") != null:
		P.ee_puppet_dudley.home = v3(tc.dudley)
	elif _g(ad, "pos") != null:
		P.ee_puppet_dudley.home = v3(ad.pos)
	# the bigger on-air Dudley stands on the case's middle glass shelf (he fits under the lit crown)
	var tg = _g(tc, "group")
	P.ee_puppet_dudley.home.y = (_worldPos(tg).y if tg is Node3D else 0.0) + DUDLEY_SHELF
	if _g(ad, "drop") != null:
		P.ee_puppet_dudley.drop = v3(ad.drop)
	var desk = O_.get("ee_anchor_desk")
	if _g(desk, "top") != null:
		P.ee_puppet_sockrates.home = v3(desk.top)
	if _g(desk, "drop") != null:
		P.ee_puppet_sockrates.drop = v3(desk.drop)
	var wheel = O_.get("ee_prize_wheel")
	if _g(wheel, "puppetSeat") != null:
		P.ee_puppet_hootie.home = v3(wheel.puppetSeat)
	var ah = A.get("ee_puppet_hootie")
	if _g(ah, "drop") != null:
		P.ee_puppet_hootie.drop = v3(ah.drop)
	# drops land on the real floor
	var col = _g(game.level, "col")
	for p in P.values():
		var drop: Vector3 = p.drop
		var y = _oc(col, "floorAt", [drop.x, drop.z, drop.y + 0.8])
		if _finite(y):
			p.drop.y = float(y)

# ================================================================================================ interactables
func _registerAll() -> void:
	var g = game
	if not _built:
		return
	var W = g.weapons
	var I = g.interact
	# step 1: the four chime bars
	for c in BARS:
		_oc(W, "registerShootable", [{
			"id": "ee_bar_%s" % c,
			"raycast": func(o, d, mx): return _barRay(c, o, d, mx),
			"onHit": func(info): _onBarHit(c, info),
		}])
	# step 2: the ghost puppets
	for p in puppets.values():
		_oc(W, "registerShootable", [{"id": p.id, "raycast": func(o, d, mx): return _puppetRay(p, o, d, mx), "onHit": func(info): _onPuppetHit(p, info)}])
		_oc(I, "register", [{
			"id": "ee_pickup_%s" % p.key, "pos": p.drop, "radius": 1.2, "height": 2.2,
			"enabled": func(): return p.state == "ground", "prompt": func(): return {} if p.state == "ground" else null, "use": func(): _usePickup(p),
		}])
	var th = O.get("ee_puppet_theater")
	var thPos = _g(th, "interact")
	_oc(I, "register", [{
		"id": "ee_puppet_theater", "pos": v3(thPos) if thPos != null else Vector3(17.75, 0, -24.9), "radius": _g(th, "interactR", 1.5), "height": 2.5,
		"enabled": func(): return _hasCarried(), "prompt": func(): return {} if _hasCarried() else null, "use": func(): _useTheater(),
	}])
	# step 5: VTR #2 load + the TRACKING knob
	var vtr = O.get("ee_vtr2")
	var vg = _g(vtr, "group")
	var vtrPos: Vector3 = VTR_FALLBACK
	if vg is Node3D:
		vtrPos = _worldPos(vg)
		vtrPos.y = 1.0
	_vtrPos = vtrPos
	_oc(I, "register", [{
		"id": "ee_vtr2", "pos": vtrPos, "radius": 1.5, "height": 2.4,
		"enabled": func(): return _tapeMine() and step == 4 and _track == null, "prompt": func(): return {} if (_tapeMine() and step == 4 and _track == null) else null,
		"use": func(): _useVtr(),
	}])
	var knob = O.get("ee_tracking_knob")
	var kp = _g(knob, "pos")
	var knobPos: Vector3 = v3(kp) if kp != null else KNOB_FALLBACK
	_knobPos = knobPos
	_oc(I, "register", [{
		"id": "ee_tracking_knob", "pos": knobPos, "radius": 1.5, "height": 2.4,
		"enabled": func(): return powered and not (_tapeMine() and step == 4 and _track == null), "prompt": func(): return {} if powered else null,
		"use": func(): _useKnob(),
	}])
	# step 6 trigger: the kill switch (key-only hold)
	var ks = O.get("ee_kill_switch")
	var ksi = _g(ks, "interact")
	var ksPos: Vector3 = v3(ksi) if ksi != null else Vector3(45, 1.2, -9.0)
	_oc(I, "register", [{
		"id": "ee_kill_switch", "pos": ksPos, "radius": 1.5, "height": 2.6, "hold": E.switchHold,
		"enabled": func(): return step == 5 and not _killSwitchUsed, "prompt": func(): return {"hold": E.switchHold} if (step == 5 and not _killSwitchUsed) else null,
		"use": func(): _useSwitch(),
	}])

# Interactable uses: MP -> a request to the host (local call on the host); solo -> the old functions.
func _usePickup(p: Dictionary) -> void:
	if _mp():
		_req("reqPickup", [p.id])
	else:
		_pickup(p)

func _useTheater() -> void:
	if _mp():
		_req("reqSlot")
	else:
		_slotAll()

func _useVtr() -> void:
	if _mp():
		_req("reqLoad")
	else:
		_loadTape()

func _useKnob() -> void:
	if _mp():
		_req("reqKnob")
	else:
		_turnKnob()

func _useSwitch() -> void:
	if _mp():
		_req("reqSwitch")
	else:
		_throwSwitch()

# ------------------------------------------------------------------------------------------ MP requests (host)
func _hostOk() -> bool:
	return _host() and (game.state == "playing" or game.state == "down")

func net_reqBar(color) -> void:
	if not _hostOk() or not BARS.has(str(color)):
		return
	_barFrame = -1
	_onBarHit(str(color), {"by": int(_net().sender)})

func net_reqPuppet(id) -> void:
	var p = puppets.get(str(id))
	if not _hostOk() or p == null or p.state != "ghost":
		return
	_net().everyone("egg", "puppet", [p.id])

func net_reqPickup(id) -> void:
	var p = puppets.get(str(id))
	if not _hostOk() or p == null or p.state != "ground":
		return
	var pl = _pl(int(_net().sender))
	if pl == null or not _g(pl, "alive", false) or _g(pl, "downed", false) or _g(pl, "offAir", false):
		return
	_net().everyone("egg", "pickup", [p.id, int(_net().sender)])

func net_reqSlot() -> void:
	if not _hostOk():
		return
	var by := int(_net().sender)
	var ids := []
	for p in puppets.values():
		if p.state == "carried" and int(p.get("carrier", 0)) == by:
			ids.append(p.id)
	if not ids.is_empty():
		_net().everyone("egg", "slot", [by, ids])

func net_reqLoad() -> void:
	var by := int(_net().sender)
	if not _hostOk() or tapeCarrier != by or step != 4 or _track != null:
		return
	var n: int = E.tracking.detents
	var s0 := int(floor(game.rand() * n))
	var kT := int(floor(game.rand() * (n - 1)))
	if kT >= s0:
		kT += 1
	_net().everyone("egg", "load", [by, s0, kT])

func net_reqKnob() -> void:
	var by := int(_net().sender)
	if not _hostOk() or not powered or (tapeCarrier == by and step == 4 and _track == null):
		return
	var knob = O.get("ee_tracking_knob")
	var n: int = E.tracking.detents
	var kt = _oc(knob, "turn", [1]) if _has(knob, "turn") else null
	var k: int = int(kt) if kt != null else (int(_g(_track, "k", 3)) + 1) % n
	_net().everyone("egg", "knob", [k, by])

func net_reqSwitch() -> void:
	if not _hostOk():
		return
	_throwSwitch()

# ------------------------------------------------------------------------------------------ MP actions (everyone)
func _act() -> bool:
	return _mp() and int(_net().sender) == 1

func net_chime(color, on) -> void:
	if not _fromHost() or not BARS.has(str(color)):
		return
	var c := str(color)
	var rack = O.get("ee_chime_rack")
	var bars = _g(rack, "bars")
	var bar = bars.get(c) if bars is Dictionary else null
	var pos := Vector3(-6.6, 1.6, -4.5)
	if bar != null:
		pos = (_oc(bar, "top") as Vector3).lerp(_oc(bar, "bottom"), 0.6)
	if not bool(on):
		_play("ee_chime_tunk", {"pos": pos})
		_oc(rack, "swing", [c, 0.35, null])
		return
	_play("ee_chime_%s" % c, {"pos": pos})
	_emit("egg:chime", {"bar": c})

func net_puppet(id) -> void:
	var p = puppets.get(str(id))
	if not _act() or p == null:
		return
	if p.state == "dormant":
		_ghost(p)             # this peer's ghost timer lags the host's
	if p.state == "ghost":
		_tunePuppet(p)

func net_pickup(id, carrier) -> void:
	var p = puppets.get(str(id))
	if not _act() or p == null:
		return
	_toGround(p)
	if p.state == "ground":
		_pickup(p, int(carrier))

func net_slot(carrier, ids) -> void:
	if not _act() or not (ids is Array):
		return
	for id in ids:
		var p = puppets.get(str(id))
		if p != null and p.state != "carried":
			_toGround(p)
			if p.state == "ground":
				_pickup(p, int(carrier))
	_slotAll(ids)

# MP: a puppet carried by a remote hero copies its hanger's world transform (hidden while the hanger is gone).
func _followHanger(p: Dictionary) -> void:
	var hg = p.hanger
	var root: Node3D = p.root
	if not (hg is Node3D) or not is_instance_valid(hg) or not (hg as Node3D).is_inside_tree():
		root.visible = false
		return
	root.visible = true
	var h: Array = HANG[p.key]
	var local := Transform3D(Basis(Vector3.UP, h[3]).scaled(Vector3.ONE * HANG_SCALE), Vector3(0, -0.25 * HANG_SCALE, 0))
	root.global_transform = (hg as Node3D).global_transform * local

# MP: a puppet whose local timeline lags the host's (dormant / ghost / tuning / falling / landing) jumps to the floor.
func _toGround(p: Dictionary) -> void:
	if not ["dormant", "ghost", "tuning", "falling", "landing"].has(p.state):
		return
	if p.state == "dormant" or p.state == "ghost" or p.state == "tuning":
		_revealPuppet(p)
	var pr: Node3D = p.root
	_setWorld(pr, p.drop, p.rotY, 1.0)
	(p.model as Node3D).rotation = Vector3.ZERO
	(p.model as Node3D).scale = Vector3.ONE
	(p.pivot as Node3D).position = Vector3.ZERO
	(p.pivot as Node3D).rotation = Vector3.ZERO
	if p.blob == null:
		p.blob = _oc(game.fx, "blob", [pr, 0.22])
	p.state = "ground"

func net_drop(ids) -> void:
	if not _act() or not (ids is Array):
		return
	for id in ids:
		var p = puppets.get(str(id))
		if p != null and p.state == "carried":
			_dropPuppet(p)

func net_sockPop(pos) -> void:
	if not _fromHost() or not (pos is Vector3):
		return
	_sockFx(pos)

func net_applause(n, pos, zid) -> void:
	if not _act() or not (pos is Vector3):
		return
	applause = int(n) - 1
	var Z = game.zombies
	var z = _oc(Z, "byId", [int(zid)]) if (zid != null and int(zid) >= 0 and _has(Z, "byId")) else null
	_countApplause(pos, z)

func net_storm(st, pos, leader) -> void:
	if not _fromHost() or not (pos is Vector3):
		return
	match str(st):
		"spawn":
			_esPos = null
			_spawnStorm(pos)
			if storm != null:
				storm.leader = int(leader)
		"lost":
			if storm != null:
				_evaporate(storm)
		"arrived":
			if storm != null:
				_stSetPos(storm, pos)
				_arrive(storm)

func net_zap(victim) -> void:
	if not _act() or storm == null:
		return
	_zapFx(storm, int(victim))

func net_tape(carrier) -> void:
	if not _act():
		return
	tapeCarrier = int(carrier)
	hasTape = tapeCarrier != 0
	if tapeCarrier == 0:
		# the tape was lost with its carrier: drop the reel from the back (Telly re-arms the pull on the host)
		var r = _reel if _reel != null else _g(game.telly, "tapeReel")
		if r is Node3D and is_instance_valid(r) and _track == null:
			DAU.detach(r)
		_reel = null
	else:
		_reel = _g(game.telly, "tapeReel")

func net_load(carrier, s0, kT) -> void:
	if not _act() or step != 4 or _track != null:
		return
	_loadTapeAt(int(s0), int(kT))

func net_knob(k, by) -> void:
	if not _act():
		return
	_knobTo(int(k), not _host())

func net_switch(thrown) -> void:
	if not _fromHost():
		return
	if bool(thrown):
		_switchFx()
	else:
		_rearmSwitch()

func net_setStep(n) -> void:
	if not _fromHost():
		return
	setStep(int(n))

# MP host -> client snapshot of the storm (follow state).
func net_stream_es(_from, data) -> void:
	if not _client() or int(_net().sender) != 1 or storm == null:
		return
	if not (data is PackedFloat32Array) or data.size() < 4:
		return
	_esPos = Vector3(data[0], data[1], data[2])
	_esYaw = data[3]

# ================================================================================================ STEP 1: chimes
# The chime_rack prop's collider box sits ~0.3 m in front of the bars and stops bullets. A ray that (extended) hits
# the real bar capsule (radius BAR_R, a little fat so the muzzle ray, which diverges from the crosshair ray, still
# agrees) is reported where it reaches the plane BAR_PUSH in front of the bars: in front of the collider, so the
# crosshair point and the bullet from the muzzle (aimed at that point) both land on the bar the player aimed at.
func _barRay(color: String, o: Vector3, d: Vector3, mx: float):
	var rack = O.get("ee_chime_rack")
	var bars = _g(rack, "bars")
	var b = bars.get(color) if bars is Dictionary else null
	if b == null:
		return null
	if _rackFront == null:
		var rg = _g(rack, "group")
		var q: Quaternion = _worldQuat(rg) if rg is Node3D else Quaternion()
		_rackFront = q * Vector3(0, 0, -1)
	var top: Vector3 = _oc(b, "top")
	var bot: Vector3 = _oc(b, "bottom")
	var t := rayCapsule(o, d, top, bot, BAR_R)
	if t < 0.0:
		return null
	var f: Vector3 = _rackFront
	var dn := d.dot(f)
	if dn < -1e-4:
		var tp := (top.x + f.x * BAR_PUSH - o.x) * f.x + (top.y + f.y * BAR_PUSH - o.y) * f.y + (top.z + f.z * BAR_PUSH - o.z) * f.z
		var tf := tp / dn
		if tf > 0.0 and tf < t:
			t = maxf(0.01, tf - 0.02)
	return {"dist": t, "point": o + d * t} if t <= mx else null

func _onBarHit(color: String, info = {}) -> void:
	var g = game
	if info == null:
		info = {}
	if IGNORED_CAUSES.has(_g(info, "cause")):
		return
	if _barFrame == int(g.time.frame):
		return          # at most one bar per shot event
	_barFrame = int(g.time.frame)
	if _client():
		_req("reqBar", [color])     # MP: the host rings it for everyone
		return
	var rack = O.get("ee_chime_rack")
	var bars = _g(rack, "bars")
	var bar = bars.get(color) if bars is Dictionary else null
	var pos := Vector3(-6.6, 1.6, -4.5)
	if bar != null:
		var top: Vector3 = _oc(bar, "top")
		var bot: Vector3 = _oc(bar, "bottom")
		pos = top.lerp(bot, 0.6)
	if _host():
		_net().toAll("egg", "chime", [color, powered])
	if not powered:
		_play("ee_chime_tunk", {"pos": pos})
		_oc(rack, "swing", [color, 0.35, _g(info, "dir")])
		return
	_play("ee_chime_%s" % color, {"pos": pos})
	_emit("egg:chime", {"bar": color})
	var now: float = g.time.now
	_bars.append({"bar": color, "t": now})
	if _bars.size() > 4:
		_bars.pop_front()
	if step != 0 or _bars.size() < 4:
		return
	for i in 4:
		if _bars[i].bar != E.chimeOrder[i]:
			return
		if i > 0 and _bars[i].t - _bars[i - 1].t > E.chimeGap:
			return
	_bars.clear()
	_completeStation()

func _completeStation() -> void:
	if not _complete(1):
		return
	_beats1()

func _beats1() -> void:
	_override("station_id", ALL_TV, 3, PRI.ee)
	_play("sting_round_start", {"delay": 0.25})
	_oc(O.get("neon_logo"), "fix")
	_oc(O.get("booth_on_air"), "set", [true])
	_celebrate(1, {"laugh": 2.2, "box": 3.6})
	# hook: the ghost puppets start to exist; Dudley giggles from the "empty" case
	_later(3.1, func():
		for p in puppets.values():
			if p.state == "dormant":
				_ghost(p))
	_later(3.2, func(): _oc(game.screens, "zoomFeed", ["lobby", 9, {"zoom": 5}]))      # the booth monitor: Dudley, big
	_later(4.4, func(): _giggle(puppets.ee_puppet_dudley, true))

# ================================================================================================ STEP 2: puppets
func _resetPuppet(p: Dictionary) -> void:
	_setPuppetLayer(p, Config.LAYERS.TV_ONLY)
	p.state = "dormant"
	p.t = 0.0
	var root: Node3D = p.root
	root.visible = false
	_oc(p.blob, "remove")
	p.blob = null
	p.hanger = null
	p.follow = false
	var model: Node3D = p.model
	var pivot: Node3D = p.pivot
	model.scale = Vector3.ONE
	model.rotation = Vector3(0, p.face, 0)
	pivot.position = Vector3.ZERO
	pivot.rotation = Vector3.ZERO
	p.hopK = -1.0
	p.hopT = 1.2 + randf() * 2.5
	_add(_areaRoot(p.area), root)
	_setWorld(root, p.home, p.rotY, p.gs)
	_setLook(p, true)
	_poseParts(p, 0, 0, 0)

# on-air (ghost) look on / off: the warm-rim material variants built in _build
func _setLook(p: Dictionary, on: bool) -> void:
	if p.look == on:
		return
	p.look = on
	for L in p.looks:
		(L[0] as MeshInstance3D).set_surface_override_material(L[1], L[3] if on else L[2])

# model yaw (relative to the puppet's rotY) that turns an on-air ghost toward its feed camera
func _faceYaw(p: Dictionary) -> float:
	var anchors = _g(game.level, "anchors")
	var a = anchors.get("feed_cam_%s" % p.area) if anchors is Dictionary else null
	var ap = _g(a, "pos")
	if ap == null:
		return 0.0
	var apos := v3(ap)
	var home: Vector3 = p.home
	var yaw := atan2(-(apos.x - home.x), -(apos.z - home.z))
	var ry: float = p.rotY
	return atan2(sin(yaw - ry), cos(yaw - ry))

func _setWorld(obj: Node3D, pos: Vector3, rotY: float, scale: float) -> void:
	var parent := obj.get_parent()
	obj.position = pos
	if parent is Node3D:
		obj.position = _worldXform(parent).affine_inverse() * pos
	obj.rotation = Vector3(0, rotY, 0)
	obj.scale = Vector3.ONE * scale

func _setPuppetLayer(p: Dictionary, layer: int) -> void:
	if p.layer == layer:
		return
	p.layer = layer
	DAU.setLayerRecursive(p.root, layer)

func _poseParts(p: Dictionary, jaw: float, armL: float, armR: float) -> void:
	var P: Dictionary = p.parts
	var j = P.get("jaw")
	var al = P.get("armL")
	var ar = P.get("armR")
	if j is Node3D:
		j.rotation.x = -jaw
	if al is Node3D:
		al.rotation.z = -armL
	if ar is Node3D:
		ar.rotation.z = armR

func _ghost(p: Dictionary) -> void:
	_resetPuppet(p)
	p.state = "ghost"
	(p.root as Node3D).visible = true
	p.giggleT = 6.0 + randf() * 8.0

func _giggle(p, force: bool = false) -> void:
	if p == null:
		return
	var pl = game.player
	var v: Vector3 = p.home
	v.y += PUPPET_CENTER * p.gs
	if not force and pl != null and (pl.pos as Vector3).distance_to(v) > 10.0:
		return
	_play("ee_puppet_giggle", {"pos": v, "range": 12})

func _puppetRay(p: Dictionary, o: Vector3, d: Vector3, mx: float):
	if p.state != "ghost":
		return null
	# hit sphere r = T.ee.puppetR around the puppet, nudged along its facing (Dudley: out through the case glass,
	# whose collider would otherwise stop oblique shots before they reach the sphere)
	var ry: float = p.rotY
	var c: Vector3 = Vector3(-sin(ry), 0, -cos(ry)) * float(p.get("shift", 0.0)) + (p.home as Vector3)
	c.y += PUPPET_CENTER * p.gs
	var r: float = E.puppetR
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.length_squared() - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return null
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	if t < 0.0:
		return null
	if t > mx:
		return null
	return {"dist": t, "point": o + d * t}

func _onPuppetHit(p: Dictionary, info = {}) -> void:
	if info == null:
		info = {}
	if p.state != "ghost" or IGNORED_CAUSES.has(_g(info, "cause")):
		return
	if _client():
		_req("reqPuppet", [p.id])
		return
	if _host():
		_net().everyone("egg", "puppet", [p.id])
		return
	_tunePuppet(p)

func _tunePuppet(p: Dictionary) -> void:
	p.state = "tuning"
	p.t = 0.0
	var v: Vector3 = p.home
	v.y += PUPPET_CENTER * p.gs
	_oc(game.fx, "burst", [v, {"shape": "static", "count": 26, "speed": 1.6, "size": 0.07, "life": 0.45, "gravity": 0}])
	_play("zmb_death_static", {"pos": v, "vol": 0.6})

func _pickup(p: Dictionary, carrier: int = 0) -> void:
	if p.state != "ground":
		return
	var pl = game.player if carrier == 0 else _pl(carrier)
	p.carrier = carrier if carrier != 0 else _lid()
	var belt = _g(_g(_g(pl, "hero"), "slots"), "belt")
	_oc(p.blob, "remove")
	p.blob = null
	p.state = "carried"
	if not carried.has(p.id):
		carried.append(p.id)
	var root: Node3D = p.root
	if belt is Node3D:
		var h: Array = HANG[p.key]
		var hanger := DAU.node3d("hang_%s" % p.key)
		hanger.position = Vector3(h[0], h[1], h[2])
		(belt as Node3D).add_child(hanger)
		p.hanger = hanger
		p.follow = _mp() and pl != game.player
		if p.follow:
			# MP: a remote hero's model is freed when its player leaves: the puppet stays in the scene and follows the
			# hanger every frame (_followHanger) instead of being parented to it; actors render layer like the hero
			_add(game.scene, root)
			_followHanger(p)
			_setPuppetLayer(p, 1)
		else:
			_add(hanger, root)
			root.position = Vector3(0, -0.25 * HANG_SCALE, 0)
			root.rotation = Vector3(0, h[3], 0)
			root.scale = Vector3.ONE * HANG_SCALE
			_setPuppetLayer(p, 0)
	else:
		root.visible = false
	var ppos = pl.pos if pl != null else null
	var o1 := {"vol": 0.7}
	var o2 := {"vol": 0.5, "delay": 0.15}
	if ppos != null:
		o1.pos = ppos
		o2.pos = ppos
	_play("costume_pop", o1)
	_play("ee_puppet_giggle", o2)

func _slotAll(only = null) -> void:
	var th = O.get("ee_puppet_theater")
	if th == null or carried.is_empty():
		return
	var ids: Array = carried.duplicate()
	if only is Array:
		ids = ids.filter(func(id): return only.has(id))
		carried = carried.filter(func(id): return not only.has(id))
	else:
		carried.clear()
	var root := _areaRoot("studio_b")
	var slots = _g(th, "slots")
	for i in ids.size():
		var p = puppets.get(ids[i])
		if p == null:
			continue
		var pr: Node3D = p.root
		p.from = _worldPos(pr)
		p.fromQ = _worldQuat(pr)
		p.fromS = HANG_SCALE
		_attach(root, pr)
		if p.hanger != null:
			_free(p.hanger)
		p.hanger = null
		p.follow = false
		pr.visible = true
		var sl = slots.get(p.key) if slots is Dictionary else null
		p.to = v3(sl) if sl != null else v3(_g(th, "interact"))
		p.toQ = Quaternion(Vector3(0, 1, 0), PI)
		p.toS = 1.0
		p.dur = 0.55
		p.t = -i * 0.18
		p.state = "flying"
	_play("telly_thwip", {"pos": v3(_g(th, "interact")), "vol": 0.6})

func _landSlot(p: Dictionary) -> void:
	var th = O.get("ee_puppet_theater")
	p.state = "slotted"
	p.t = 0.0
	_oc(th, "setSlot", [p.key, true])
	_play("costume_pop", {"pos": p.to, "vol": 0.8})
	_emit("egg:puppet_slot", {"id": p.id})
	var all := true
	for q in puppets.values():
		if q.state != "slotted":
			all = false
	if all and step == 1:
		_completePuppets()

# MP: the carrier is gone: the puppet pops back to its drop spot on the floor (pickable again).
func _dropPuppet(p: Dictionary) -> void:
	if p.hanger != null:
		_free(p.hanger)
	p.hanger = null
	p.follow = false
	p.carrier = 0
	carried = carried.filter(func(id): return id != p.id)
	var pr: Node3D = p.root
	_add(_areaRoot(p.area), pr)
	_setPuppetLayer(p, 0)
	_setWorld(pr, p.drop, p.rotY, 1.0)
	pr.visible = true
	(p.model as Node3D).rotation = Vector3.ZERO
	(p.model as Node3D).scale = Vector3.ONE
	(p.pivot as Node3D).position = Vector3.ZERO
	(p.pivot as Node3D).rotation = Vector3.ZERO
	p.state = "ground"
	p.t = 0.0
	_oc(game.fx, "burst", [p.drop, {"shape": "puff", "count": 6, "speed": 0.8, "size": 0.12, "life": 0.5, "color": "#E8DCCB"}])
	p.blob = _oc(game.fx, "blob", [pr, 0.22])
	_play("costume_pop", {"pos": p.drop, "vol": 0.6})

func _placeOnStage(p: Dictionary) -> void:
	var th = O.get("ee_puppet_theater")
	_oc(p.blob, "remove")
	p.blob = null
	if p.hanger != null:
		_free(p.hanger)
	p.hanger = null
	p.follow = false
	var root := _areaRoot("studio_b")
	var pr: Node3D = p.root
	_add(root, pr)
	_setPuppetLayer(p, 0)
	_setLook(p, false)
	(p.model as Node3D).scale = Vector3.ONE
	(p.model as Node3D).rotation = Vector3.ZERO
	pr.visible = true
	_oc(th, "setSlot", [p.key, true])
	var stage = _g(th, "stage")
	var slots = _g(th, "slots")
	var sp = stage.get(p.key) if stage is Dictionary else null
	if sp == null:
		sp = slots.get(p.key) if slots is Dictionary else null
	var pos: Vector3 = v3(sp) if sp != null else STUDIO_B_C
	_setWorld(pr, pos, PI, 1)
	p.state = "stage"
	carried = carried.filter(func(id): return id != p.id)

func _completePuppets() -> void:
	if not _complete(2):
		return
	_beats2()

func _beats2() -> void:
	var th = O.get("ee_puppet_theater")
	_celebrate(2, {"laugh": 7.6, "box": 8.6})
	_oc(th, "setOpen", [1, 0.8])
	_song = {"t": 0.0, "clapped": false}
	# every puppet hops up behind the playboard
	var stage = _g(th, "stage")
	var i := 0
	for p in puppets.values():
		p.from = _worldPos(p.root)
		var sp = stage.get(p.key) if stage is Dictionary else null
		p.to = v3(sp) if sp != null else p.from
		p.dur = 0.45
		p.t = -0.35 - i * 0.12
		p.state = "hop"
		i += 1
	var thi = _g(th, "interact")
	var songPos: Vector3 = v3(thi) if thi != null else STUDIO_B_C
	_later(0.55, func(): _play("ee_kazoo_song", {"pos": songPos, "range": 45}))
	_later(0.7, func(): _popSocks())

func _popSocks() -> void:
	if _client():
		return
	var Z = game.zombies
	var alive = _g(Z, "alive")
	if alive == null:
		return
	_socks = []
	var i := 0
	for z in alive:
		if _g(z, "type") != "sock_hopper" or _g(z, "dead", false):
			continue
		_oc(Z, "stun", [z, 2.5])
		_socks.append({"z": z, "t": -0.25 - i * 0.12 - randf() * 0.2})
		i += 1

func _updateSocks(dt: float) -> void:
	if _socks.is_empty() or _client():
		return
	var Z = game.zombies
	for i in range(_socks.size() - 1, -1, -1):
		var s: Dictionary = _socks[i]
		var z = s.z
		if z == null or _g(z, "dead", false) or _g(z, "removed", false):
			_socks.remove_at(i)
			continue
		s.t += dt
		# freeze + turn toward Studio B
		var zp: Vector3 = _g(z, "pos", Vector3.ZERO)
		var zy: float = _g(z, "yaw", 0.0)
		var yaw := atan2(-(STUDIO_B_C.x - zp.x), -(STUDIO_B_C.z - zp.z))
		zy += atan2(sin(yaw - zy), cos(yaw - zy)) * minf(1.0, dt * 8.0)
		_s(z, "yaw", zy)
		var zg = _g(z, "group")
		if zg is Node3D:
			zg.rotation.y = zy
		if _g(z, "vel") != null:
			_s(z, "vel", Vector3.ZERO)
		if s.t >= 0.9:
			var v := zp
			v.y += float(_g(z, "height", 1.0)) * 0.5
			if _host():
				_net().toAll("egg", "sockPop", [v])
			_sockFx(v)
			_oc(Z, "kill", [z, {"cause": "egg", "points": false, "corpse": false}])
			_socks.remove_at(i)

func _sockFx(v: Vector3) -> void:
	_oc(game.fx, "burst", [v, {"shape": "confetti", "count": 40, "speed": 4.5, "size": 0.08, "life": 1.3, "gravity": 5, "colors": RAINBOW}])
	_oc(game.fx, "burst", [v, {"shape": "star", "count": 8, "speed": 2.5, "size": 0.1, "life": 0.6}])
	_play("sock_boing", {"pos": v, "rate": 1.3})

func _updateSong(dt: float) -> void:
	var s = _song
	if s == null:
		return
	s.t += dt
	if not s.clapped and s.t >= 6.9:
		s.clapped = true
		_play("ee_clap_single", {"pos": STUDIO_A_CLAP, "range": 30, "wet": 0.8})
		_signMode = "flicker"
		_toteTwitchT = 1.2
	if s.t > 7.6:
		_song = null

func _updatePuppets(dt: float) -> void:
	var t: float = game.time.now
	for p in puppets.values():
		var pivot: Node3D = p.pivot
		var model: Node3D = p.model
		var root: Node3D = p.root
		match p.state:
			"ghost":
				# on-air performance (feeds only): bob + sway, a big wave (Sockrates: head bobs), jaw chatter, and every
				# 2.4-5 s a squash-and-stretch hop with the arms up (30 %: a twirl)
				var ph: float = t + p.phase
				var G: Dictionary = GHOST[p.key]
				var hop := 0.0
				var sq := 0.0
				var spin := 0.0
				var up := 0.0
				if p.hopK < 0.0:
					p.hopT -= dt
					if p.hopT <= 0.0:
						p.hopK = 0.0
						p.hopSpin = randf() < GHOST_HOP.spin
				if p.hopK >= 0.0:
					p.hopK += dt / GHOST_HOP.dur
					var k := minf(1.0, p.hopK)
					if k < 0.2:
						sq = -0.16 * sin((k / 0.2) * PI)                     # crouch
					elif k < 0.8:                                          # up: stretch, arms up
						var u := (k - 0.2) / 0.6
						hop = sin(u * PI) * G.hop
						sq = 0.12 * sin(u * PI)
						up = sin(u * PI)
						if p.hopSpin:
							spin = TAU * easeInOut(u)
					else:
						sq = -0.13 * sin(((k - 0.8) / 0.2) * PI)            # land
					if p.hopK >= 1.0:
						p.hopK = -1.0
						p.hopT = GHOST_HOP.every[0] + randf() * (GHOST_HOP.every[1] - GHOST_HOP.every[0])
				sq *= G.sq
				pivot.position.y = absf(sin(ph * 3.4)) * G.bob + hop
				pivot.rotation.z = sin(ph * 1.9) * (0.2 if p.key == "sock" else 0.14)
				pivot.rotation.x = sin(ph * 2.3) * 0.06
				model.rotation.y = p.face + sin(ph * 0.8) * 0.18 + spin
				model.scale = Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5)
				var jaw := 0.1 + maxf(0.0, sin(ph * 6.3)) * 0.34 + up * 0.2
				_poseParts(p, jaw, 0.55 + sin(ph * 2.2) * 0.35 + up * 1.7, 1.85 + sin(ph * 10.5) * 0.7 + up * 0.5)
				p.giggleT -= dt
				if p.giggleT <= 0.0:
					p.giggleT = 12.0 + randf() * 8.0
					_giggle(p)
			"tuning":
				p.t += dt
				var on := int(floor(p.t / 0.05)) % 2 == 0
				_setPuppetLayer(p, 0 if on else Config.LAYERS.TV_ONLY)
				pivot.position.x = (randf() - 0.5) * 0.04
				model.scale = Vector3(1.0 + (randf() - 0.5) * 0.12, 1.0 + (randf() - 0.5) * 0.12, 1.0)
				if p.t >= 0.4:
					_revealPuppet(p)
			"falling":
				p.t += dt
				var k := clamp01(p.t / p.dur)
				var v: Vector3 = (p.from as Vector3).lerp(p.to, k)
				v.y += sin(k * PI) * 0.45
				# tumbling out of the feed and into the room: back to 1x and facing its drop direction
				var e := easeInOut(k)
				_setWorld(root, v, p.rotY, 1.0 + (p.gs - 1.0) * (1.0 - e))
				model.rotation.y = p.face * (1.0 - e)
				pivot.rotation.x = (-TAU if p.key == "dragon" else -PI * 0.5) * easeInOut(k) * (1.0 if k < 1.0 else 0.0)
				pivot.rotation.z = sin(k * PI) * 0.4
				if k >= 1.0:
					model.rotation.y = 0.0
					pivot.rotation = Vector3.ZERO
					p.state = "landing"
					p.t = 0.0
					_oc(game.fx, "burst", [p.to, {"shape": "puff", "count": 6, "speed": 0.8, "size": 0.12, "life": 0.5, "color": "#E8DCCB"}])
					p.blob = _oc(game.fx, "blob", [root, 0.22])
			"landing":
				p.t += dt
				var k := clamp01(p.t / 0.5)
				var sq := sin(k * PI * 2.5) * (1.0 - k) * 0.25
				model.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)
				pivot.position = Vector3(0, absf(sin(k * PI * 2.0)) * 0.12 * (1.0 - k), 0)
				if k >= 1.0:
					model.scale = Vector3.ONE
					pivot.position = Vector3.ZERO
					p.state = "ground"
			"ground":
				var ph: float = t + p.phase
				pivot.rotation.z = sin(ph * 1.3) * 0.04
				_poseParts(p, 0.05 + maxf(0.0, sin(ph * 2.0)) * 0.08, 0.25, 0.25 + maxf(0.0, sin(ph * 1.1)) * 0.5)
			"carried":
				var pl = game.player if not _mp() else _pl(int(p.get("carrier", 0)))
				var pv = _g(pl, "vel")
				var sp := Vector2(pv.x, pv.z).length() if pv is Vector3 else 0.0
				var ph: float = t * (4.0 + sp * 1.4) + p.phase
				var hanger = p.hanger
				if p.get("follow", false):
					_followHanger(p)
				if hanger is Node3D and is_instance_valid(hanger):
					hanger.rotation.x = sin(ph) * (0.08 + sp * 0.05)
					hanger.rotation.z = sin(ph * 0.5 + 1.0) * (0.06 + sp * 0.03)
				pivot.position.y = absf(sin(ph)) * 0.02
				_poseParts(p, 0.1 + maxf(0.0, sin(ph * 1.3)) * 0.1, 0.5 + sin(ph) * 0.3, 0.5 - sin(ph) * 0.3)
			"flying":
				p.t += dt
				if p.t < 0.0:
					continue
				var k := clamp01(p.t / p.dur)
				var e := easeInOut(k)
				var v: Vector3 = (p.from as Vector3).lerp(p.to, e)
				v.y += sin(k * PI) * 0.6
				var parent := root.get_parent()
				root.position = v
				if parent is Node3D:
					root.position = _worldXform(parent).affine_inverse() * v
				root.quaternion = (p.fromQ as Quaternion).slerp(p.toQ, e)
				root.scale = Vector3.ONE * (p.fromS + (p.toS - p.fromS) * e)
				pivot.rotation.x = -sin(k * PI) * 0.5
				if k >= 1.0:
					pivot.rotation = Vector3.ZERO
					_landSlot(p)
			"slotted":
				p.t += dt
				var k := clamp01(p.t / 0.4)
				var sq := sin(k * PI * 2.0) * (1.0 - k) * 0.2
				model.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)
				var ph: float = t + p.phase
				_poseParts(p, 0.06 + maxf(0.0, sin(ph * 2.4)) * 0.1, 0.3, 0.3 + maxf(0.0, sin(ph * 1.7)) * 0.5)
			"hop":
				p.t += dt
				if p.t < 0.0:
					continue
				var k := clamp01(p.t / p.dur)
				var v: Vector3 = (p.from as Vector3).lerp(p.to, easeInOut(k))
				v.y += sin(k * PI) * 0.35
				_setWorld(root, v, PI, 1)
				model.scale = Vector3.ONE
				if k >= 1.0:
					p.state = "stage"
					p.t = 0.0
			"stage":
				p.t += dt
				var s = _song
				var beat := 0.5 * 60.0 / 132.0
				if s != null and s.t > 0.55 and s.t < 6.6:
					var u: float = (s.t - 0.55) / beat
					var off: float = {"dragon": 0.0, "sock": 0.33, "owl": 0.66}[p.key]
					var b := absf(sin((u + off) * PI))
					pivot.position.y = b * 0.07
					pivot.rotation.z = sin((u + off) * PI * 0.5) * 0.18
					_poseParts(p, 0.15 + b * 0.35, 1.2 + sin(u * 1.3) * 0.6, 1.2 + cos(u * 1.3) * 0.6)
				elif s != null and s.t >= 6.6:
					var k := clamp01((s.t - 6.6) / 0.5)
					pivot.rotation.x = -sin(k * PI) * 0.6          # the bow
					pivot.position.y = 0.0
					_poseParts(p, 0.1, 0.4, 0.4)
				else:
					var ph: float = game.time.now + p.phase
					pivot.position.y = absf(sin(ph * 1.6)) * 0.015
					pivot.rotation = Vector3(0, 0, sin(ph * 0.9) * 0.05)
					_poseParts(p, 0.06 + maxf(0.0, sin(ph * 1.9)) * 0.08, 0.35, 0.35 + maxf(0.0, sin(ph * 0.8)) * 0.6)
			_:
				pass

func _revealPuppet(p: Dictionary) -> void:
	_setPuppetLayer(p, 0)
	_setLook(p, false)
	(p.pivot as Node3D).position = Vector3.ZERO
	(p.pivot as Node3D).rotation = Vector3.ZERO
	(p.model as Node3D).scale = Vector3.ONE
	var v: Vector3 = p.home
	v.y += PUPPET_CENTER * p.gs
	_play("ee_puppet_reveal", {"pos": v})
	_oc(game.fx, "burst", [v, {"shape": "star", "count": 10, "speed": 2.2, "size": 0.08, "life": 0.6, "colors": ["#FFE45C", "#FFFFFF", "#C9A8FF"]}])
	_emit("egg:puppet_reveal", {"id": p.id})
	if p.key == "dragon":
		_oc(O.get("ee_trophy_case"), "setOpen", [true])
	p.from = p.home
	p.to = p.drop
	p.dur = 0.8 if p.key == "owl" else 0.7
	p.t = -0.25 if p.key == "dragon" else 0.0         # the case door swings first (k stays 0 while t < 0)
	p.state = "falling"

# ================================================================================================ STEP 3: applause
func _onKill(e) -> void:
	if e == null or step != 2 or _client():
		return
	var pos = _g(e, "pos")
	if pos == null:
		pos = _g(_g(e, "z"), "pos")
	if not (pos is Vector3):
		return
	var zone: Array = E.applauseZone
	var x0: float = zone[0]
	var z0: float = zone[1]
	var x1: float = zone[2]
	var z1: float = zone[3]
	if pos.x < x0 or pos.x > x1 or pos.z < z0 or pos.z > z1:
		return
	if _mp():
		# MP: the killer stands in Studio A (no killer known: anybody in Studio A)
		var by = _g(e, "by")
		var ok := false
		if by is int or by is float:
			ok = _g(_pl(int(by)), "area") == "studio_a"
		else:
			for q in _net().players():
				if _g(q, "area") == "studio_a" and q.get("offAir") != true:
					ok = true
		if not ok:
			return
		var z = _g(e, "z")
		var zid = _g(z, "id")
		_net().everyone("egg", "applause", [applause + 1, pos, int(zid) if zid != null else -1])
		return
	if _g(game.player, "area") != "studio_a":
		return
	_countApplause(pos, _g(e, "z"))

# One counted kill at `pos` (the zombie `z`, if any, for the hands to follow its body's slide).
func _countApplause(pos = null, z = null) -> void:
	applause += 1
	var n := applause
	var O_ := O
	_signSolidT = 0.6
	_oc(O_.get("ee_applause_sign"), "setLit", [true])
	# the applause: the close crowd + the gloves' claps (non-positional, sfx bus) and both bleachers (positional,
	# linear rolloff to 45 m), a hair after the kill's own shot
	_play("ee_applause_near", {"claps": CLAP.beats})
	for b in BLEACHERS:
		_play("ee_applause_burst", {"pos": b, "delay": 0.04})
	if pos != null:
		_spawnClap(pos, z)
	var tote = O_.get("ee_tote_board")
	_oc(tote, "setValue", [TOTE_BASE + mini(n, E.applauseKills)])
	_toteTwitchBack = -1.0
	var tg = _g(tote, "group")
	var tpos := Vector3(4, 2.8, -21)
	if tg is Node3D:
		tpos = _worldPos(tg)
		tpos.y = 2.8
	_play("ee_tote_flip", {"pos": tpos})
	if n == 1:
		_play("crowd_ooh", {"pos": BLEACHERS[0], "delay": 0.15, "range": 45})
		_play("crowd_applause", {"pos": BLEACHERS[1], "dur": 2.2, "delay": 0.5, "range": 45})
		for b in BLEACHERS:
			var v: Vector3 = b
			v.y = 2.2
			_oc(game.fx, "burst", [v, {"shape": "confetti", "count": 30, "speed": 3.5, "size": 0.08, "life": 1.4, "gravity": 4, "colors": RAINBOW}])
	_emit("egg:applause", {"count": n})
	if n >= E.applauseKills:
		_completeApplause()

func _completeApplause() -> void:
	if not _complete(3):
		return
	_beats3()

func _beats3() -> void:
	var O_ := O
	var g = game
	_oc(O_.get("ee_tote_board"), "setValue", [TOTE_BASE + E.applauseKills])
	_signMode = "locked"
	_oc(O_.get("ee_applause_sign"), "setLit", [true])
	# thermometer top confetti + the grid cannons + a standing ovation
	var top = _g(_g(O_.get("ee_tote_board"), "parts"), "topper")
	var tp: Vector3 = _worldPos(top) if top is Node3D else Vector3(4, 3.4, -21)
	_oc(g.fx, "burst", [tp, {"shape": "confetti", "count": 70, "speed": 5.5, "size": 0.09, "life": 1.8, "gravity": 4, "dir": Vector3(0, 1, 0), "cone": 0.9, "colors": RAINBOW}])
	_oc(g.fx, "burst", [tp, {"shape": "star", "count": 14, "speed": 3, "size": 0.12, "life": 0.9}])
	_oc(g.fx, "flashLight", [tp, "#FFD27A", 5, 0.4])
	for i in _cannons.size():
		var c: Dictionary = _cannons[i]
		_later(0.15 + i * 0.22, func(): _fireCannon(c))
	for b in BLEACHERS:
		_play("ee_ovation", {"pos": b, "delay": 0.2})
	# + the ovation's close layer (a job, so the audio engine does not merge it with this kill's own near layer)
	_later(0.3, func(): _play("ee_applause_near", {"dur": 3.8, "claps": [], "vol": 0.8}))
	_celebrate(3, {"laugh": 4.6, "box": 6.2})
	# hook (+2 s): thunder over the newsroom + the weather map
	_later(2.0, func(): _thunderHook())

func _fireCannon(c: Dictionary) -> void:
	var g = game
	c.kick = 0.0
	var barrel: Node3D = c.parts.barrel
	var muzzle: Vector3 = _worldXform(barrel) * Vector3(0, 0.5, 0)
	_oc(g.fx, "burst", [muzzle, {"shape": "confetti", "count": 90, "speed": 7, "size": 0.1, "life": 2.4, "gravity": 3.2, "drag": 1.2, "dir": c.dir, "cone": 0.45, "colors": RAINBOW}])
	_oc(g.fx, "burst", [muzzle, {"shape": "puff", "count": 6, "speed": 1.5, "size": 0.2, "life": 0.6, "color": "#FFFFFF"}])
	_play("ee_confetti_cannon", {"pos": muzzle})

func _updateApplauseProps(dt: float) -> void:
	var O_ := O
	var signObj = O_.get("ee_applause_sign")
	if _signSolidT > 0.0:
		_signSolidT -= dt
		if _signSolidT <= 0.0 and _signMode != "locked":
			_oc(signObj, "setLit", [false])
	elif _signMode == "flicker" and signObj != null and dt > 0.0:
		_flickT -= dt
		if _flickT <= 0.0:
			_flickT = 1.0 / (2.0 * (2.0 + randf() * 3.0))            # random 2–5 Hz
			_oc(signObj, "setLit", [not bool(_g(signObj, "lit", false))])
	# tote digits twitch (step 2 hook) and the per-kill flip pop
	var tote = O_.get("ee_tote_board")
	if tote != null and _signMode == "flicker" and step == 2 and dt > 0.0:
		if _toteTwitchBack >= 0.0:
			_toteTwitchBack -= dt
			if _toteTwitchBack < 0.0:
				_oc(tote, "setValue", [TOTE_BASE + applause])
		else:
			_toteTwitchT -= dt
			if _toteTwitchT <= 0.0:
				_toteTwitchT = 1.5 + randf() * 3.0
				_toteTwitchBack = 0.09 + randf() * 0.08
				_oc(tote, "setValue", [TOTE_BASE + applause + (1 if randf() < 0.5 else -1)])
				if _g(game.player, "area") == "studio_a":
					var tg = _g(tote, "group")
					var o := {"vol": 0.25}
					if tg is Node3D:
						o.pos = _worldPos(tg)
					_play("ee_tote_flip", o)
	# cannon recoil
	for c in _cannons:
		if c.kick < 0.0:
			continue
		c.kick += dt
		var k := clamp01(c.kick / 0.6)
		var barrel: Node3D = c.parts.barrel
		barrel.position = (c.dir as Vector3) * (-sin(minf(1.0, k * 3.0) * PI * 0.5) * 0.14 * (1.0 - k))
		if k >= 1.0:
			c.kick = -1.0
			barrel.position = Vector3.ZERO

# ================================================================================================ STEP 3: applause hands
# Two MultiMeshInstance3D (left / right glove, CLAP.max instances each) in the scene root, world layer, hidden while
# no pair is alive: 2 draw calls for any number of live pairs.
func _buildHands() -> void:
	var g = game
	if g.scene == null:
		_hands = null
		return
	var src := _loadModel("ee_applause_glove")
	var gl := _findNode(src, "ee_applause_glove_l") as MeshInstance3D
	var gr := _findNode(src, "ee_applause_glove_r") as MeshInstance3D
	if gl == null or gr == null or gl.mesh == null or gr.mesh == null:
		push_warning("[egg] applause hands: glove asset missing")
		src.free()
		_hands = null
		return
	var mat = _clapMaterial()
	var make := func(mirror: bool) -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = (gr if mirror else gl).mesh
		mm.instance_count = CLAP.max
		mm.visible_instance_count = 0
		for i in CLAP.max:
			mm.set_instance_custom_data(i, Color(0, 0, 0, 1))
		var m := MultiMeshInstance3D.new()
		m.name = "ee_applause_glove_r" if mirror else "ee_applause_glove_l"
		m.multimesh = mm
		if mat is Material:
			m.material_override = mat
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		DAU.ud(m)["noMerge"] = true
		g.scene.add_child(m)
		return m
	_hands = {"mat": mat, "l": make.call(false), "r": make.call(true)}
	src.free()

# White glove: a keepColor toon (vertex colours, soft wrap, cream rim) with a per-instance alpha (INSTANCE_CUSTOM.a, the
# JS aFade attribute) so each pair fades on its own: a copy of the toon material whose shader is the toon include
# patched with the JS onBeforeCompile's lines (varying vEggFade; diffuseColor.a *= vEggFade after the colour).
func _clapMaterial():
	var mats = game.mats
	if mats == null or not _has(mats, "toon"):
		return null
	var base = mats.toon("#ffffff", {"keepColor": true, "vertexColors": true, "rough": 0.55, "rim": 0.5, "rimColor": "#FFF1D8", "rimPower": 2.0, "wrap": 0.7, "transparent": true})
	if not (base is ShaderMaterial) or (base as ShaderMaterial).shader == null:
		return base
	var patched := _patchFade(_inlineIncludes((base as ShaderMaterial).shader.code))
	if patched == "":
		push_warning("[egg] applause glove: toon shader not patchable (no per-pair fade)")
		return base
	var sh := Shader.new()
	sh.code = patched
	var mat = base.clone() if base.has_method("clone") else (base as ShaderMaterial).duplicate()
	mat.shader = sh
	for u in (base as ShaderMaterial).shader.get_shader_uniform_list():
		var v = (base as ShaderMaterial).get_shader_parameter(u.name)
		if v != null:
			mat.set_shader_parameter(u.name, v)
	mat.resource_name = "egg:applause_glove"
	return mat

# `#include "res://…"` lines of a shader whose include holds fragment() are replaced by the include's code.
static func _inlineIncludes(code: String) -> String:
	if code.find("void fragment()") >= 0:
		return code
	var out := ""
	for line in code.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("#include"):
			var a := l.find("\"")
			var b := l.rfind("\"")
			var path := l.substr(a + 1, b - a - 1) if a >= 0 and b > a else ""
			var inc = load(path) if path != "" and ResourceLoader.exists(path) else null
			if inc is ShaderInclude and (inc as ShaderInclude).code.find("void fragment()") >= 0:
				out += (inc as ShaderInclude).code + "\n"
				continue
		out += line + "\n"
	return out

# Inserts `varying float vEggFade;`, vEggFade = INSTANCE_CUSTOM.a in vertex() and the fade on the diffuse alpha
# (after the colour, like the JS `#include <color_fragment>` hook; else ALPHA at the end of fragment()).
# Returns "" when the shader has no fragment() to patch.
static func _patchFade(code: String) -> String:
	var fi := code.find("void fragment()")
	if fi < 0:
		return ""
	var vi := code.find("void vertex()")
	var first := fi if vi < 0 else mini(vi, fi)
	var out := code.substr(0, first) + "varying float vEggFade;\n" + code.substr(first)
	vi = out.find("void vertex()")
	if vi >= 0:
		var b := out.find("{", vi)
		out = out.substr(0, b + 1) + "\n\tvEggFade = INSTANCE_CUSTOM.a;" + out.substr(b + 1)
	else:
		fi = out.find("void fragment()")
		out = out.substr(0, fi) + "void vertex() {\n\tvEggFade = INSTANCE_CUSTOM.a;\n}\n" + out.substr(fi)
	var hook := "diffuseColor.rgb *= instanceColor.rgb;"
	var hi := out.find(hook, out.find("void fragment()"))
	if hi >= 0:
		return out.substr(0, hi + hook.length()) + "\n\tdiffuseColor.a *= vEggFade;" + out.substr(hi + hook.length())
	fi = out.find("void fragment()")
	var ob := out.find("{", fi)
	var depth := 0
	var i := ob
	while i < out.length():
		var ch := out[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				break
		i += 1
	if i >= out.length():
		return ""
	var body := out.substr(ob, i - ob)
	var line := "\tALPHA *= vEggFade;\n" if body.find("ALPHA") >= 0 else "\tALPHA = vEggFade;\n"
	return out.substr(0, i) + line + out.substr(i)

# A pair of applause hands over a counted kill at `pos` (following zombie `z`'s body while it slides).
func _spawnClap(pos, z = null):
	if _hands == null or pos == null:
		return null
	if _claps.size() >= CLAP.max:
		_clapPool.append(_claps.pop_front())
	var c = _clapPool.pop_back() if _clapPool.size() else {"x": 0.0, "y": 0.0, "z": 0.0, "t": 0.0, "beat": 0, "zombie": null}
	var p: Vector3 = pos
	c.x = p.x
	c.z = p.z
	var fy := _floorY(p.x, p.z, p.y + 0.6)
	c.y = maxf(fy, p.y - 0.5) if is_finite(fy) else p.y
	c.t = 0.0
	c.beat = 0
	c.zombie = z
	_claps.append(c)
	var v := Vector3(c.x, c.y + CLAP.height, c.z)
	_oc(game.fx, "burst", [v, {"shape": "confetti", "count": 16, "speed": 2.4, "size": 0.06, "life": 1.1, "gravity": 3.5, "colors": RAINBOW}])
	return c

func _clearClaps() -> void:
	while _claps.size():
		var c = _claps.pop_back()
		c.zombie = null
		_clapPool.append(c)
	var H = _hands
	if H != null:
		for m in [H.l, H.r]:
			(m as MultiMeshInstance3D).multimesh.visible_instance_count = 0
			(m as MultiMeshInstance3D).visible = false

# Poses every live pair: pop in with squash and stretch, clap on CLAP.beats (palms meet, squash, a star burst),
# jazz-hands wiggle after the last clap, float up CLAP.rise and fade out; the pair turns to face the camera.
func _updateClaps(rdt: float) -> void:
	var H = _hands
	var list := _claps
	if H == null:
		return
	var L: MultiMeshInstance3D = H.l
	var R: MultiMeshInstance3D = H.r
	if list.is_empty():
		if L.visible:
			L.visible = false
			R.visible = false
			L.multimesh.visible_instance_count = 0
			R.multimesh.visible_instance_count = 0
		return
	for i in range(list.size() - 1, -1, -1):
		var c = list[i]
		c.t += rdt
		if c.t >= CLAP.life:
			c.zombie = null
			_clapPool.append(c)
			list.remove_at(i)
	var g = game
	var cam = _g(g.render, "cameraOverride")
	if not (cam is Node3D):
		cam = g.camera
	var cp: Vector3 = _worldPos(cam) if cam is Node3D else Vector3.ZERO
	var B: Array = CLAP.beats
	var last: float = B[B.size() - 1]
	var n := 0
	for c in list:
		var u: float = c.t
		var zb = c.zombie
		if zb != null and not _g(zb, "removed", false) and _g(zb, "pos") != null and u < 0.5:
			c.x = zb.pos.x
			c.z = zb.pos.z
		# timeline
		var kp := clamp01(u / CLAP.pop)
		var pop := easeOutBack(kp) if kp < 1.0 else 1.0
		var stretch := sin(kp * PI) * 0.35 * (1.0 - 0.4 * kp)
		var kf := clamp01((u - CLAP.fade) / (CLAP.life - CLAP.fade))
		var alpha := 1.0 - kf * kf * (3.0 - 2.0 * kf)
		var dmin := 9.0
		for i in B.size():
			dmin = minf(dmin, absf(u - B[i]))
		var touch := maxf(0.0, 1.0 - dmin / 0.04)
		var open := 0.0
		if u < B[0]:
			open = sin((0.5 + 0.5 * (u / B[0])) * PI)
		elif u < last:
			var i := 0
			while i < B.size() - 2 and u >= B[i + 1]:
				i += 1
			open = sin(((u - B[i]) / (B[i + 1] - B[i])) * PI)
		else:
			open = 0.85 * (1.0 - pow(1.0 - clamp01((u - last) / 0.2), 2.0))
		var sep: float = CLAP.touch + (CLAP.open - CLAP.touch) * pow(maxf(0.0, open), 0.7)
		var jazz := sin(u * 19.0) * 0.14 * clamp01((u - last) / 0.2) if u > last else 0.0
		var bump := 0.035 * touch
		# star burst where the palms meet (once per beat)
		while c.beat < B.size() and u >= B[c.beat]:
			c.beat += 1
			var ay0: float = c.y + CLAP.height + 0.04
			_oc(g.fx, "burst", [Vector3(c.x, ay0, c.z), {"shape": "star", "count": 3, "speed": 1.5, "size": 0.06, "life": 0.35, "gravity": 0, "colors": CLAP_STARS}])
		# pair frame: yaw toward the camera, rising
		var rise: float = CLAP.rise * easeInOut(clamp01((u - 0.9) / (CLAP.life - 0.9)))
		var ay: float = c.y + CLAP.height + rise + sin(u * 5.2) * 0.02
		var qy := Quaternion(AX_Y, atan2(cp.x - c.x, cp.z - c.z))
		var S_: float = CLAP.scale * pop * (1.0 - 0.15 * kf)
		var sc := Vector3(S_ * (1.0 - stretch * 0.5) * (1.0 + 0.08 * touch), S_ * (1.0 + stretch) * (1.0 + 0.06 * touch), S_ * (1.0 - stretch * 0.5) * (1.0 - 0.22 * touch))
		for side in [-1.0, 1.0]:
			# wrist below the pair's centre, palms facing each other, backs a little toward the camera, fingers fanned
			var w: Vector3 = qy * Vector3(side * sep * 0.5, -0.1 * S_ + bump, 0)
			var up := Vector3(c.x + w.x, ay + w.y, c.z + w.z)
			var qr := Quaternion(AX_Z, -side * (0.04 + 0.42 * open + jazz))
			var qt := Quaternion(AX_Y, side * (1.45 - 0.5 * open))
			var q := qy * qr * qt
			var xf := Transform3D(Basis(q) * Basis.from_scale(sc), up)
			var M: MultiMeshInstance3D = L if side < 0.0 else R
			M.multimesh.set_instance_transform(n, xf)
			M.multimesh.set_instance_custom_data(n, Color(0, 0, 0, alpha))
		n += 1
	L.multimesh.visible_instance_count = n
	R.multimesh.visible_instance_count = n
	L.visible = n > 0
	R.visible = n > 0

# ================================================================================================ STEP 3 hook: weather map
func _thunderHook() -> void:
	var g = game
	_play("ee_thunder_far", {"pos": NEWSROOM_C, "range": 220, "vol": 1.2})
	_oc(g.cam, "shake", [0.15, 0.6])
	var L = g.lights
	var anchors = _g(L, "anchors")
	if anchors is Dictionary:
		for id in anchors.keys():
			var a = anchors[id]
			if _g(a, "area") == "newsroom" and not _g(a, "flash", false):
				_oc(L, "flicker", [id, 0.95, 1.4])
	var map = O.get("ee_weather_map")
	_oc(map, "flash", [true])
	_later(1.4, func(): _oc(map, "flash", [false]))
	_moveMagnets(1.6)
	_later(1.8, func(): _mapBlink = true)
	_rumbleT = 20.0
	forceForecaster = true
	var cnt = _oc(g.zombies, "count", ["forecaster"])
	if not (cnt != null and float(cnt) > 0.0) and not _client():
		_emit("egg:need_forecaster", {})

func _moveMagnets(seconds: float) -> void:
	var map = O.get("ee_weather_map")
	var parts = _g(map, "parts")
	if not (parts is Dictionary):
		return
	var manchors = _g(map, "anchors")
	var icon = manchors.get("tower_icon") if manchors is Dictionary else null
	var face = manchors.get("face") if manchors is Dictionary else null
	var tx: float = icon[0] if icon != null else 0.6
	var ty: float = icon[1] if icon != null else 1.5
	var W: float = _g(face, "w", 2.2)
	var go := func(name: String, x: float, y: float) -> void:
		if parts.get("magnet_%s" % name) == null:
			return
		if seconds > 0.0 and _has(map, "slide"):
			_oc(map, "slide", [name, [x, y], seconds])
		else:
			_oc(map, "showMagnet", [name, [x, y]])
	# the suns slide to the edges of the map and drop off it, storm + bolt slide onto the tower icon
	var sa = parts.get("magnet_sun_a")
	var sb = parts.get("magnet_sun_b")
	go.call("sun_a", W / 2.0 - 0.2, (sa.position.y if sa is Node3D else 1.6) + 0.05)
	go.call("sun_b", -W / 2.0 + 0.2, (sb.position.y if sb is Node3D else 1.6) - 0.05)
	go.call("storm", tx + 0.02, ty + 0.2)
	go.call("bolt", tx - 0.02, ty - 0.02)
	var suns: Array = []
	for m in [sa, sb]:
		if m is Node3D:
			suns.append(m)
	if seconds > 0.0:
		_later(seconds + 0.05, func():
			for m in suns:
				_magFall.append({"m": m, "t": 0.0, "y0": m.position.y, "s": 1.0 if m == suns[0] else -1.0}))
	else:
		for m in suns:
			m.visible = false

func _restoreMapTower() -> void:
	var parts = _g(O.get("ee_weather_map"), "parts")
	if not (parts is Dictionary):
		return
	for n in ["storm", "bolt"]:
		var m = parts.get("magnet_%s" % n)
		if m is Node3D:
			m.visible = true

func _restoreMap() -> void:
	var map = O.get("ee_weather_map")
	var parts = _g(map, "parts")
	if not (parts is Dictionary) or _mapRest == null:
		return
	for k in _mapRest:
		var m = parts.get(k)
		if not (m is Node3D):
			continue
		var r: Dictionary = _mapRest[k]
		m.position = r.p
		m.rotation = r.r
		m.visible = r.v
	_oc(map, "flash", [false])

func _updateMap(dt: float) -> void:
	for i in range(_magFall.size() - 1, -1, -1):
		var f: Dictionary = _magFall[i]
		f.t += dt
		var k := clamp01(f.t / 0.45)
		var m: Node3D = f.m
		m.position.y = f.y0 - k * k * 0.9
		m.rotation.z = f.s * k * 2.2
		if k >= 1.0:
			m.visible = false
			_magFall.remove_at(i)
	if not _mapBlink or step != 3:
		return
	var map = O.get("ee_weather_map")
	var parts = _g(map, "parts")
	if parts is Dictionary:
		var on := fmod(float(game.time.now), 0.8) < 0.5
		for n in ["storm", "bolt"]:
			var m = parts.get("magnet_%s" % n)
			if m is Node3D:
				m.visible = on
	_rumbleT -= dt
	if _rumbleT <= 0.0:
		_rumbleT = 20.0
		var ti = _g(map, "towerIcon")
		var p: Vector3 = v3(ti) if ti != null else NEWSROOM_C
		_play("ee_map_rumble", {"pos": p, "range": 26})
		_oc(map, "flash", [true])
		_later(0.25, func(): _oc(map, "flash", [false]))

# ================================================================================================ STEP 4: the Stray Storm
func _onForecasterStorm(e) -> void:
	if step != 3 or stormActive or _g(e, "pos") == null or _client():
		return
	var by = _g(e, "by")
	if by == null:
		by = _g(_g(e, "z"), "lastHitBy")
	_spawnBy = int(by) if (by is int or by is float) else 0
	_spawnStorm(e.pos)
	_spawnBy = 0

var _spawnBy := 0

# MP host: the storm's leader at the spawn (the Forecaster's killer when targetable, else the nearest target).
func _pickLeader(pos: Vector3, prefer: int) -> int:
	var n = _net()
	var q = n.playerById(prefer) if prefer != 0 else null
	if q != null and n.isTargetable(q):
		return prefer
	q = n.nearestPlayer(pos, true)
	return n.idOf(q) if q != null else 0

func _stSetPos(st: Dictionary, p: Vector3) -> void:
	(st.art.root as Node3D).position = p
	st.pos = p

func _spawnStorm(pos: Vector3):
	var g = game
	_removeStorm(true)
	var art := buildStorm(g)
	g.scene.add_child(art.root)
	var flr := _floorY(pos.x, pos.z, pos.y)
	(art.root as Node3D).position = Vector3(pos.x, maxf(pos.y, flr + 1.5), pos.z)
	var st := {
		"active": true, "art": art, "age": 0.0, "lostT": 0.0, "zapCd": 1.5, "crackleT": 0.5, "bolt": null, "boltT": 0.0, "state": "follow",
		"pos": (art.root as Node3D).position, "vel": Vector3(), "fade": 1.0, "loop": null, "raceT": 0.0, "raceFrom": Vector3(),
		"stranded": false, "flash": 0.0, "zaps": 0,
	}
	var au = g.audio
	if au != null and _has(au, "loop"):
		st.loop = _oc(au, "loop", ["ee_storm_loop", {"pos": st.pos, "vol": 0.8}])
	storm = st
	_crumbs.clear()
	_crumbT = 0.0
	var pl = g.player
	if _host():
		st.leader = _pickLeader(pos, _spawnBy)
		pl = _pl(st.leader)
		_net().toAll("egg", "storm", ["spawn", pos, st.leader])
	elif _client():
		pl = null
	if pl != null:
		_crumbs.append(pl.pos)
	_oc(g.fx, "burst", [st.pos, {"shape": "puff", "count": 14, "speed": 2, "size": 0.35, "life": 0.8, "color": STORM_COLOR}])
	_play("ee_thunder_far", {"pos": st.pos, "vol": 0.6})
	_emit("egg:storm", {"state": "spawn"})
	return st

func _removeStorm(instant: bool = false) -> void:
	var st = storm
	if st == null:
		return
	_oc(st.loop, "stop", [0.05 if instant else 0.6])
	st.active = false
	if st.bolt != null:
		_free(st.bolt)
		st.bolt = null
	_free(st.art.root)
	storm = null

func _floorY(x: float, z: float, yFrom: float = 50.0) -> float:
	var col = _g(game.level, "col")
	var y = _oc(col, "floorAt", [x, z, yFrom])
	if _finite(y):
		return float(y)
	var n = _oc(game.nav, "heightAt", [x, z])
	return float(n) if _finite(n) else 0.0

func _ceilAt(x: float, z: float) -> float:
	var lv = game.level
	var id = _oc(lv, "areaAt", [x, z])
	var areas = _g(lv, "areas")
	var a = areas.get(id) if (id != null and areas is Dictionary) else null
	if a == null or id == "yard":
		return INF
	var cy = _g(a, "ceilY")
	if cy == null:
		cy = _g(a, "ceil")
	return float(cy) if cy != null else INF

func _updateStorm(dt: float) -> void:
	var g = game
	var pl = g.player
	# breadcrumbs (a position every 0.25 s while a storm lives)
	var st = storm
	if st != null and _mp() and st.state == "follow":
		if _client():
			_puppetStorm(st, dt)
			return
		pl = _stormLeader(st)
		_esT -= dt
		if _esT <= 0.0:
			_esT = 0.1
			_net().stream("es", PackedFloat32Array([st.pos.x, st.pos.y, st.pos.z, (st.art.root as Node3D).rotation.y]))
	if st == null or pl == null:
		return
	if dt <= 0.0:
		return
	st.age += dt
	var art: Dictionary = st.art
	var root: Node3D = art.root
	if st.state == "race":
		_updateRace(st, dt)
		return
	if st.state == "evaporate":
		st.fade -= dt / 0.9
		root.scale = Vector3.ONE * (0.92 * maxf(0.01, st.fade))
		var ep := root.position
		ep.y += dt * 0.6
		_stSetPos(st, ep)
		if st.fade <= 0.0:
			_removeStorm()
		return
	var plpos: Vector3 = pl.pos
	_crumbT += dt
	var p: Vector3 = root.position
	if _crumbT >= 0.25:
		_crumbT = 0.0
		var last = _crumbs.back() if _crumbs.size() else null
		if last != null and (last as Vector3).distance_squared_to(plpos) > 16.0:
			# the trail broke (a teleport): the storm is stranded until the player is back in sight within 6 m
			_crumbs.clear()
			st.stranded = true
		if st.stranded:
			var w := p
			w.y -= 1.0
			var u := plpos
			u.y += 1.4
			var los = _oc(_g(g.level, "col"), "lineOfSight", [w, u])
			if p.distance_to(plpos) < 6.0 and (los if los != null else true):
				st.stranded = false
		var lc = _crumbs.back() if _crumbs.size() else null
		if not st.stranded and (lc == null or (lc as Vector3).distance_squared_to(plpos) > 0.04):
			_crumbs.append(plpos)
		if _crumbs.size() > 600:
			_crumbs.pop_front()
	# follow the trail
	var target = null
	var targetIsPlayer := false
	while _crumbs.size():
		var c: Vector3 = _crumbs[0]
		var dx := c.x - p.x
		var dz := c.z - p.z
		if dx * dx + dz * dz < 0.35 * 0.35 and _crumbs.size() > 1:
			_crumbs.pop_front()
			continue
		target = c
		break
	var dxp := plpos.x - p.x
	var dzp := plpos.z - p.z
	var hDist := sqrt(dxp * dxp + dzp * dzp)
	if st.stranded:
		target = p
	elif target == null or _crumbs.size() <= 1:
		target = plpos
		targetIsPlayer = true
	var tgt: Vector3 = target
	var tx := tgt.x - p.x
	var tz := tgt.z - p.z
	var tl := sqrt(tx * tx + tz * tz)
	var speed: float = S.speed * (maxf(0.0, (hDist - 0.3) / 0.9) if (hDist < 1.2 and targetIsPlayer) else 1.0)
	if tl > 1e-3:
		var stp := minf(tl, speed * dt)
		p.x += (tx / tl) * stp
		p.z += (tz / tl) * stp
		var yaw := atan2(-dxp, -dzp)
		root.rotation.y += atan2(sin(yaw - root.rotation.y), cos(yaw - root.rotation.y)) * minf(1.0, dt * 3.0)
	var flr := minf(_floorY(p.x, p.z, p.y), tgt.y + 0.5)
	var hy := minf(flr + S.height, _ceilAt(p.x, p.z) - 0.6)
	p.y += (hy - p.y) * minf(1.0, dt * 2.5)
	_stSetPos(st, p)
	# wobble + face + rain
	var t: float = g.time.now
	var body: Node3D = art.body
	body.position = Vector3(sin(t * 1.3) * 0.06, sin(t * 2.1) * 0.08, 0)
	body.rotation.z = sin(t * 0.9) * 0.05
	var rainH := maxf(0.3, p.y - _floorY(p.x, p.z, p.y) - 0.35)
	var rain: MeshInstance3D = art.rain
	if rain != null:
		rain.scale = Vector3(1, rainH / root.scale.y, 1)
		rain.position.y = -0.3
	var rt: Dictionary = art.rainTex
	rt.offset.y = fmod(rt.offset.y + dt * 2.6, 1.0)
	rt.repeat.y = rainH / 1.6
	_rainUv(art.rainMat, rt)
	if randf() < dt * 6.0:
		var v := Vector3(p.x + (randf() - 0.5) * 1.4, _floorY(p.x, p.z, p.y) + 0.03, p.z + (randf() - 0.5) * 1.4)
		_oc(g.fx, "burst", [v, {"shape": "spark", "count": 2, "speed": 1.2, "size": 0.02, "life": 0.25, "color": "#BFD2FF", "dir": Vector3(0, 1, 0), "cone": 0.8, "gravity": 6}])
	# crackles
	st.crackleT -= dt
	if st.crackleT <= 0.0:
		st.crackleT = 0.5 + randf() * 1.1
		st.flash = 0.18
		var v2 := p + Vector3((randf() - 0.5) * 1.2, (randf() - 0.3) * 0.5, (randf() - 0.5) * 0.8)
		_oc(g.fx, "burst", [v2, {"shape": "spark", "count": 6, "speed": 2.5, "size": 0.025, "life": 0.2, "color": "#E7D8FF"}])
	if st.flash > 0.0:
		st.flash -= dt
	_setOpacity(art.glowMat, 0.55 * (st.flash / 0.18) if st.flash > 0.0 else 0.0)
	# zap: 10 every 4 s within 2 m (horizontal)
	st.zapCd -= dt
	if _mp():
		if st.zapCd <= 0.0:
			var vb = null
			var vd := 2.0
			for q in _net().targets():
				var dd := Vector2(q.pos.x - p.x, q.pos.z - p.z).length()
				if dd <= vd:
					vd = dd
					vb = q
			if vb != null:
				st.zapCd = float(S.zapEvery)
				_net().everyone("egg", "zap", [_net().idOf(vb)])
	elif hDist <= 2.0 and st.zapCd <= 0.0:
		_zap(st)
	if st.bolt != null:
		st.boltT -= dt
		_setOpacity((st.bolt as MeshInstance3D).material_override, maxf(0.0, st.boltT / 0.2) * (1.0 if randf() < 0.7 else 0.3))
		if st.boltT <= 0.0:
			_free(st.bolt)
			st.bolt = null
	_oc(st.loop, "setPos", [p])
	# evaporation: 90 s life (fades from 75 s) or > 20 m of path for 8 s straight
	if st.age >= S.life - 15:
		var k := clamp01((st.age - (S.life - 15)) / 15.0)
		root.scale = Vector3.ONE * (0.92 * (1.0 - k * 0.55))
		# (the JS also re-set the opaque cloud material's opacity to 1 here: no visible effect)
	var pd = _oc(g.nav, "dist", [p.x, p.z])
	if not _finite(pd):
		pd = sqrt(dxp * dxp + dzp * dzp) * 1.3
	st.lostT = st.lostT + dt if float(pd) > S.lostDist else 0.0
	if st.age >= S.life or st.lostT >= S.lostTime:
		_evaporate(st)
		return
	# arrival at the tower
	var tv := Vector3(plpos.x - TOWER.x, 0, plpos.z - TOWER.z)
	if tv.length() <= E.towerR and p.distance_to(plpos) <= E.stormNear and step == 3:
		_arrive(st)

# MP host: the storm's leader (re-picked when it stops being a target: stranded until the new one is close).
func _stormLeader(st: Dictionary):
	var n = _net()
	var q = n.playerById(int(st.get("leader", 0)))
	if q != null and n.isTargetable(q):
		return q
	var nq = n.nearestPlayer(st.pos, true)
	if nq == null:
		return null
	st.leader = n.idOf(nq)
	_crumbs.clear()
	st.stranded = true
	return nq

# MP client: the storm follows the host's stream; local wobble / rain / crackles / bolt fade.
func _puppetStorm(st: Dictionary, dt: float) -> void:
	var g = game
	st.age += dt
	var art: Dictionary = st.art
	var root: Node3D = art.root
	var p: Vector3 = root.position
	if _esPos is Vector3:
		p = p.lerp(_esPos, 1.0 - exp(-dt * 8.0))
		root.rotation.y = lerp_angle(root.rotation.y, _esYaw, 1.0 - exp(-dt * 8.0))
	_stSetPos(st, p)
	var t: float = g.time.now
	var body: Node3D = art.body
	body.position = Vector3(sin(t * 1.3) * 0.06, sin(t * 2.1) * 0.08, 0)
	body.rotation.z = sin(t * 0.9) * 0.05
	var rainH := maxf(0.3, p.y - _floorY(p.x, p.z, p.y) - 0.35)
	var rain: MeshInstance3D = art.rain
	if rain != null:
		rain.scale = Vector3(1, rainH / root.scale.y, 1)
		rain.position.y = -0.3
	var rt: Dictionary = art.rainTex
	rt.offset.y = fmod(rt.offset.y + dt * 2.6, 1.0)
	rt.repeat.y = rainH / 1.6
	_rainUv(art.rainMat, rt)
	st.crackleT -= dt
	if st.crackleT <= 0.0:
		st.crackleT = 0.5 + randf() * 1.1
		st.flash = 0.18
		var v2 := p + Vector3((randf() - 0.5) * 1.2, (randf() - 0.3) * 0.5, (randf() - 0.5) * 0.8)
		_oc(g.fx, "burst", [v2, {"shape": "spark", "count": 6, "speed": 2.5, "size": 0.025, "life": 0.2, "color": "#E7D8FF"}])
	if st.flash > 0.0:
		st.flash -= dt
	_setOpacity(art.glowMat, 0.55 * (st.flash / 0.18) if st.flash > 0.0 else 0.0)
	if st.bolt != null:
		st.boltT -= dt
		_setOpacity((st.bolt as MeshInstance3D).material_override, maxf(0.0, st.boltT / 0.2) * (1.0 if randf() < 0.7 else 0.3))
		if st.boltT <= 0.0:
			_free(st.bolt)
			st.bolt = null
	_oc(st.loop, "setPos", [p])
	if st.age >= S.life - 15:
		var k := clamp01((st.age - (S.life - 15)) / 15.0)
		root.scale = Vector3.ONE * (0.92 * (1.0 - k * 0.55))

# MP: the zap bolt toward `victim` (as this peer sees it); only the victim's own peer takes the 10.
func _zapFx(st: Dictionary, victim: int) -> void:
	var g = game
	var pl = _pl(victim)
	if pl == null:
		return
	st.zapCd = float(S.zapEvery)
	st.zaps = int(st.get("zaps", 0)) + 1
	var v: Vector3 = pl.pos
	v.y += 1.2
	var from: Vector3 = (st.pos as Vector3) + Vector3(0, -0.45, 0)
	var geo := boltGeometry(from, v, {"jag": 0.2, "segs": 8, "width": 0.035, "branches": 1})
	if st.bolt != null:
		_free(st.bolt)
	var mat: ShaderMaterial = _boltMat().duplicate()
	var bolt := MeshInstance3D.new()
	bolt.mesh = geo
	bolt.material_override = mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	st.bolt = bolt
	g.scene.add_child(bolt)
	st.boltT = 0.2
	st.flash = 0.2
	if pl == g.player:
		_oc(pl, "hurt", [S.zap, st.pos])
		_oc(g.cam, "shake", [0.12, 0.2])
	_play("ee_storm_zap", {"pos": st.pos})
	_oc(g.fx, "burst", [v, {"shape": "spark", "count": 12, "speed": 3, "size": 0.03, "life": 0.25, "color": "#E0D0FF"}])
	_oc(g.fx, "flashLight", [v, "#C9A8FF", 4, 0.2])

func _zap(st: Dictionary) -> void:
	var g = game
	var pl = g.player
	st.zapCd = float(S.zapEvery)
	st.zaps = int(st.get("zaps", 0)) + 1
	var v: Vector3 = pl.pos
	v.y += 1.2
	var from: Vector3 = (st.pos as Vector3) + Vector3(0, -0.45, 0)
	var geo := boltGeometry(from, v, {"jag": 0.2, "segs": 8, "width": 0.035, "branches": 1})
	if st.bolt != null:
		_free(st.bolt)
	var mat: ShaderMaterial = _boltMat().duplicate()
	var bolt := MeshInstance3D.new()
	bolt.mesh = geo
	bolt.material_override = mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	st.bolt = bolt
	g.scene.add_child(bolt)
	st.boltT = 0.2
	st.flash = 0.2
	_oc(pl, "hurt", [S.zap, st.pos])
	_play("ee_storm_zap", {"pos": st.pos})
	_oc(g.fx, "burst", [v, {"shape": "spark", "count": 12, "speed": 3, "size": 0.03, "life": 0.25, "color": "#E0D0FF"}])
	_oc(g.fx, "flashLight", [v, "#C9A8FF", 4, 0.2])
	_oc(g.cam, "shake", [0.12, 0.2])

func _evaporate(st: Dictionary) -> void:
	if st.state == "evaporate":
		return
	st.state = "evaporate"
	st.fade = 1.0
	if _host():
		_net().toAll("egg", "storm", ["lost", st.pos, 0])
	_oc(st.loop, "stop", [0.8])
	_oc(game.fx, "burst", [st.pos, {"shape": "puff", "count": 12, "speed": 1.5, "size": 0.3, "life": 0.9, "color": "#8A7AA8"}])
	_play("fc_cloud_pop", {"pos": st.pos, "rate": 0.7})
	st.active = false
	_emit("egg:storm", {"state": "lost"})

func _arrive(st: Dictionary) -> void:
	if _host():
		_net().toAll("egg", "storm", ["arrived", st.pos, 0])
	st.state = "race"
	st.raceT = 0.0
	st.raceFrom = st.pos
	_emit("egg:storm", {"state": "arrived"})
	_play("fc_rumble", {"pos": st.pos, "vol": 1.2})

func _updateRace(st: Dictionary, dt: float) -> void:
	var g = game
	st.raceT += dt
	var k := clamp01(st.raceT / 1.5)
	var e := k * k
	var a: Dictionary = st.art
	# spiral up the tower
	var ang := k * TAU * 1.5
	var r := (1.0 - e) * 2.5 + 0.6
	var rf: Vector3 = st.raceFrom
	var bx := rf.x + (TOWER.x - rf.x) * minf(1.0, k * 2.2)
	var bz := rf.z + (TOWER.z - rf.z) * minf(1.0, k * 2.2)
	_stSetPos(st, Vector3(bx + cos(ang) * r * minf(1.0, k * 3.0), rf.y + (TOWER_TOP.y + 2.0 - rf.y) * e, bz + sin(ang) * r * minf(1.0, k * 3.0)))
	if a.rain != null:
		(a.rain as Node3D).visible = false
	_setOpacity(a.glowMat, 0.3 + randf() * 0.4)
	(a.body as Node3D).rotation.z = sin(st.raceT * 20.0) * 0.1
	_oc(st.loop, "setPos", [st.pos])
	if randf() < dt * 12.0:
		_oc(g.fx, "burst", [st.pos, {"shape": "spark", "count": 4, "speed": 3, "size": 0.03, "life": 0.2, "color": "#E7D8FF"}])
	if k >= 1.0:
		_strike(st)

func _strike(st: Dictionary) -> void:
	var g = game
	var top := TOWER_TOP
	var sky := top + Vector3(1.5, 34, -2)
	var geo := boltGeometry(sky, top, {"jag": 0.16, "segs": 20, "width": 0.55, "branches": 5})
	var mat: ShaderMaterial = _boltMat().duplicate()
	var bolt := MeshInstance3D.new()
	bolt.mesh = geo
	bolt.material_override = mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.scene.add_child(bolt)
	var down := MeshInstance3D.new()
	down.mesh = boltGeometry(top, Vector3(top.x, 3, top.z), {"jag": 0.05, "segs": 16, "width": 0.12, "branches": 0})
	down.material_override = mat
	down.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.scene.add_child(down)
	_strikeFx = {"bolt": bolt, "down": down, "t": 0.0}
	_whiteT = 0.0
	_play("ee_lightning_strike", {"pos": top, "range": 400, "vol": 1.2})
	_play("ee_thunder_far", {"delay": 0.35, "vol": 0.9})
	_oc(g.fx, "flashLight", [top, "#E8DDFF", 14, 0.5])
	_oc(g.fx, "burst", [top, {"shape": "spark", "count": 40, "speed": 9, "size": 0.06, "life": 0.6, "color": "#F0E8FF"}])
	_oc(g.fx, "burst", [st.pos, {"shape": "puff", "count": 16, "speed": 3, "size": 0.45, "life": 1.0, "color": STORM_COLOR}])
	_oc(g.cam, "shake", [0.55, 0.7])
	_removeStorm()
	if not _complete(4):
		return
	_beats4()

func _beats4() -> void:
	_removeStorm(true)
	forceForecaster = false
	_mapBlink = false
	_restoreMapTower()
	_oc(O.get("tower_beacons"), "setMode", ["rainbow"])
	# Baron on "Channel 0" on every TV for 0.5 s, with the (angrier) laugh
	_override("baron", ALL_TV, 0.5, PRI.ee)
	_celebrate(4, {"laugh": 0.05, "box": 3.2})

func _boltMat() -> ShaderMaterial:
	if _boltM == null:
		_boltM = _basicMat({"color": _lin("#EDE4FF", 3.0), "transparent": true, "opacity": 1.0, "additive": true, "depthWrite": false})
	return _boltM

# ================================================================================================ STEP 5: tape + tracking
func _onTellyTake(e) -> void:
	if e == null or _g(e, "itemId") != "ee_tape_reel":
		return
	if _mp():
		# MP: the host names the carrier (the Telly user: `by`, or mp-machines' `user`) for everyone
		if not _host():
			return
		var by = _g(e, "by")
		if by == null:
			by = _g(e, "user")
		if by == null:
			by = _g(game.telly, "tapeHolder")
		_net().everyone("egg", "tape", [int(by) if (by is int or by is float) and int(by) != 0 else _lid()])
		return
	hasTape = true
	_reel = _g(game.telly, "tapeReel")

func _loadTape() -> void:
	if not hasTape or _track != null or step != 4:
		return
	var g = game
	var vtr = O.get("ee_vtr2")
	hasTape = false
	var reel = _reel if _reel != null else _g(g.telly, "tapeReel")
	if reel is Node3D and is_instance_valid(reel):
		var from := _worldPos(reel)
		_attach(g.scene, reel)
		var vg = _g(vtr, "group")
		var to: Vector3
		if vg is Node3D:
			to = _worldXform(vg) * Vector3(0, 1.3, -0.55)
		else:
			to = _vtrPos
			to.y = 1.3
		_reelFly = {"reel": reel, "from": from, "to": to, "t": 0.0}
	_oc(vtr, "loadTape", [1.5])
	_play("ee_tape_thread", {"pos": _vtrPos})
	var n: int = E.tracking.detents
	var s0 := int(floor(g.rand() * n))
	var kT := int(floor(g.rand() * (n - 1)))
	if kT >= s0:
		kT += 1
	_track = {"s0": s0, "kT": kT, "k": s0, "quietT": 0.0, "started": false, "t": 0.0, "wob": 0.0}
	_oc(O.get("ee_tracking_knob"), "set", [s0, true])
	_later(1.5, func(): _startPlayback())

# MP (every peer): the carrier loads the reel with the host's s0 / kT (the _loadTape body without the rolls).
func _loadTapeAt(s0: int, kT: int) -> void:
	var g = game
	var vtr = O.get("ee_vtr2")
	hasTape = false
	tapeCarrier = 0
	var reel = _reel if _reel != null else _g(g.telly, "tapeReel")
	if reel is Node3D and is_instance_valid(reel):
		var from := _worldPos(reel)
		_attach(g.scene, reel)
		var vg = _g(vtr, "group")
		var to: Vector3
		if vg is Node3D:
			to = _worldXform(vg) * Vector3(0, 1.3, -0.55)
		else:
			to = _vtrPos
			to.y = 1.3
		_reelFly = {"reel": reel, "from": from, "to": to, "t": 0.0}
	_oc(vtr, "loadTape", [1.5])
	_play("ee_tape_thread", {"pos": _vtrPos})
	_track = {"s0": s0, "kT": kT, "k": s0, "quietT": 0.0, "started": false, "t": 0.0, "wob": 0.0}
	_oc(O.get("ee_tracking_knob"), "set", [s0, true])
	_later(1.5, func(): _startPlayback())

# MP (every peer): the knob went to detent k (the host already turned its own).
func _knobTo(k: int, setKnob: bool) -> void:
	if setKnob:
		_oc(O.get("ee_tracking_knob"), "set", [k, false])
	_play("ee_tracking_click", {"pos": _knobPos})
	var tr = _track
	if tr == null or step != 4:
		return
	tr.k = k
	tr.quietT = 0.0
	var d := _trackDist()
	_oc(_tones, "setDistance", [d])
	_emit("egg:tracking", {"detent": k, "distance": d})

func _startPlayback() -> void:
	var g = game
	var tr = _track
	if tr == null or step != 4:
		return
	tr.started = true
	var d := _trackDist()
	if _picture != null and _picture.texture != null:
		_oc(g.screens, "setSource", ["scr_vtr2", _picture.texture])
	var au = g.audio
	if au != null and _has(au, "loop"):
		_tones = _oc(au, "loop", ["ee_tracking_tones", {"pos": _vtrPos, "vol": 0.55, "d": d}])
		_oc(_tones, "setDistance", [d])
		_hymn = _oc(au, "loop", ["sting_signoff_hymn", {"pos": _vtrPos, "vol": 0.5, "tv": true}])

func _stopTracking() -> void:
	_oc(_tones, "stop", [0.2])
	_oc(_hymn, "stop", [0.3])
	_tones = null
	_hymn = null
	if _reelFly != null:
		_removeFromParent(_reelFly.reel)
		_reelFly = null

func _trackDist() -> int:
	var tr = _track
	if tr == null:
		return 6
	var n: int = E.tracking.detents
	var a: int = absi(int(tr.k) - int(tr.kT))
	return mini(a, n - a)

func _turnKnob() -> void:
	var knob = O.get("ee_tracking_knob")
	var n: int = E.tracking.detents
	var k: int
	var kt = _oc(knob, "turn", [1]) if _has(knob, "turn") else null
	if kt != null:
		k = int(kt)
	else:
		k = (int(_g(_track, "k", 3)) + 1) % n
	_play("ee_tracking_click", {"pos": _knobPos})
	var tr = _track
	if tr == null or step != 4:
		return
	tr.k = k
	tr.quietT = 0.0
	var d := _trackDist()
	_oc(_tones, "setDistance", [d])
	_emit("egg:tracking", {"detent": k, "distance": d})

func _updateTracking(dt: float) -> void:
	var g = game
	var fly = _reelFly
	if fly != null:
		fly.t += dt
		var k := clamp01(fly.t / 0.45)
		var reel: Node3D = fly.reel
		var rp: Vector3 = (fly.from as Vector3).lerp(fly.to, easeInOut(k))
		rp.y += sin(k * PI) * 0.4
		reel.position = rp
		reel.rotation.z += dt * 12.0
		if k >= 1.0:
			_removeFromParent(reel)
			_reelFly = null
	var tr = _track
	if tr == null or not tr.started or step != 4:
		return
	var d := _trackDist()
	var pl = g.player
	var near := false
	var vis := false
	if pl != null:
		var pp: Vector3 = pl.pos
		near = Vector2(pp.x - _vtrPos.x, pp.z - _vtrPos.z).length() <= E.tracking.radius
		vis = _g(pl, "area") == "master_control" or pp.distance_to(_vtrPos) < 14.0
	if _mp():
		near = false
		if not _client():
			for q in _net().targets():
				if Vector2(q.pos.x - _vtrPos.x, q.pos.z - _vtrPos.z).length() <= E.tracking.radius:
					near = true
	if _picture != null:
		_picture.update(dt, float(d), vis)
	tr.t += dt
	# the hymn wobbles with the mistracking (a slow wow flutter on the level)
	if _has(_hymn, "setVol"):
		tr.wob += dt
		if tr.wob > 0.05:
			tr.wob = 0.0
			_oc(_hymn, "setVol", [0.5 * (1.0 - (float(d) / 6.0) * 0.45 * (0.5 + 0.5 * sin(tr.t * (3.0 + d)))), 0.05])
	if d == 0:
		if near:
			tr.quietT += dt
		if tr.quietT >= E.tracking.hold:
			_completeTape()
	else:
		tr.quietT = 0.0

func _completeTape() -> void:
	if not _complete(5):
		return
	_beats5()

func _beats5() -> void:
	var g = game
	tapeCarrier = 0
	var O_ := O
	_stopTracking()
	_track = null
	_oc(O_.get("ee_vtr2"), "setLamp", ["green", false])
	_oc(g.screens, "setSource", ["scr_vtr2", "signoff_film"])
	_override("signoff_film", null, 20, PRI.signoff)
	_play("sting_signoff_hymn")
	_onAirT = 0.0
	_later(0.5, func(): _tvSound("ee_baron_scream", {"near": 3, "vol": 1.1}))
	_celebrate(5, {"laugh": 3.4, "box": 5.2})
	_later(1.0, func(): _openCage(false))

# ================================================================================================ STEP 5 hook + STEP 6 trigger
func _openCage(instant: bool) -> void:
	var ks = O.get("ee_kill_switch")
	if ks == null:
		return
	var door = _g(_g(ks, "parts"), "door")
	if instant:
		if door is Node3D:
			door.rotation.y = -1.7
		_cageT = -1.0
	else:
		_cageT = 0.0
		var kpos: Vector3 = v3(_g(ks, "pos", Vector3.ZERO))
		_play("ee_cage_boing", {"pos": kpos})
		_oc(_alarm, "stop", [0.1])
		var ap := kpos
		ap.y = 2.2
		_alarm = _play("ee_alarm_bell", {"pos": ap, "dur": 10, "range": 70, "vol": 1})
		var hp = _g(ks, "handle")
		_oc(game.fx, "burst", [v3(hp) if hp != null else kpos, {"shape": "star", "count": 14, "speed": 2.5, "size": 0.1, "life": 0.8, "colors": RAINBOW}])
	_addOutline()

func _addOutline() -> void:
	var ks = O.get("ee_kill_switch")
	var sw = _g(_g(ks, "parts"), "switch")
	if not (sw is Node3D) or _outline != null:
		return
	var mat := _basicMat({"color": _lin("#FF4A4A"), "side": "back", "transparent": true, "opacity": 0.9, "additive": true, "depthWrite": false})
	var group := DAU.node3d("ee_switch_outline")
	for m in (sw as Node3D).get_children():
		if not (m is MeshInstance3D) or (m as MeshInstance3D).mesh == null:
			continue
		var src: Mesh = (m as MeshInstance3D).mesh
		var gg := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nor = arr[Mesh.ARRAY_NORMAL]
			if not (nor is PackedVector3Array) or nor.size() != pos.size():
				var stool := SurfaceTool.new()
				stool.create_from_arrays(arr)
				stool.generate_normals()
				arr = stool.commit_to_arrays()
				pos = arr[Mesh.ARRAY_VERTEX]
				nor = arr[Mesh.ARRAY_NORMAL]
			for i in pos.size():
				pos[i] = pos[i] + nor[i] * 0.032
			var out := []
			out.resize(Mesh.ARRAY_MAX)
			out[Mesh.ARRAY_VERTEX] = pos
			out[Mesh.ARRAY_NORMAL] = nor
			out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
			gg.add_surface_from_arrays((src as ArrayMesh).surface_get_primitive_type(si) if src is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES, out)
		var o := MeshInstance3D.new()
		o.mesh = gg
		o.material_override = mat
		o.transform = (m as MeshInstance3D).transform
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(o)
	(sw as Node3D).add_child(group)
	var L = game.lights
	var hp = _g(ks, "handle")
	if hp == null:
		hp = _g(ks, "pos", Vector3.ZERO)
	var h := v3(hp)
	_oc(L, "addAnchor", [{"id": "ee_switch_glow", "pos": [h.x, h.y + 0.2, h.z - 0.6], "color": "#FF4A4A", "intensity": 2.2, "distance": 4, "area": "yard"}])
	_outline = {"group": group, "mat": mat, "t": 0.0}

func _removeOutline() -> void:
	if _outline == null:
		return
	_free(_outline.group)
	_outline = null
	_oc(game.lights, "removeAnchor", ["ee_switch_glow"])

func _throwSwitch() -> void:
	if step != 5 or _killSwitchUsed or _client():
		return
	var g = game
	if _host():
		_net().toAll("egg", "switch", [true])
	_switchFx()
	var ks = O.get("ee_kill_switch")
	# boss.start plays the THUNK itself (after audio.stopAll, the dead air); play it here only without a boss
	var ok := false
	var boss = g.boss
	var hasStart := _has(boss, "start")
	if hasStart:
		var rnd = _g(g.rounds, "round", 1)
		if not rnd:
			rnd = 1
		var r = _oc(boss, "start", [rnd])
		ok = not (r is bool and r == false) or bool(_g(boss, "active", false))
	if not hasStart:
		var hp = _g(ks, "handle")
		if hp == null:
			hp = _g(ks, "pos")
		var o := {}
		if hp != null:
			o.pos = v3(hp)
		_play("ee_switch_thunk", o)
	elif not ok:
		_rearmSwitch()

# The switch is thrown (every peer): THUNK animation, alarm off, the outline goes.
func _switchFx() -> void:
	var g = game
	_killSwitchUsed = true
	_switchThrownAt = g.time.realNow
	_switchT = 0.0
	_oc(_alarm, "stop", [0.2])
	_alarm = null
	_oc(g.cam, "shake", [0.25, 0.3])
	_later(0.3, func():
		if _killSwitchUsed:
			_removeOutline())

# the fight never started (or ended without a defeat, e.g. an aborted boss): the switch can be thrown again
func _rearmSwitch() -> void:
	if step != 5 or done:
		return
	if _host():
		_net().toAll("egg", "switch", [false])
	_killSwitchUsed = false
	_switchT = -1.0
	var sw = _g(_g(O.get("ee_kill_switch"), "parts"), "switch")
	if sw is Node3D:
		sw.rotation.x = 0.0
	_addOutline()

func _updateYard(dt: float, rdt: float) -> void:
	var ks = O.get("ee_kill_switch")
	var kparts = _g(ks, "parts")
	var door = _g(kparts, "door")
	var sw = _g(kparts, "switch")
	if _cageT >= 0.0 and door is Node3D:
		_cageT += dt
		var k := clamp01(_cageT / 0.55)
		door.rotation.y = -1.7 * easeOutBack(k)
		if k >= 1.0:
			_cageT = -1.0
	var boss = game.boss
	if _killSwitchUsed and step == 5 and not done and boss != null and not bool(_g(boss, "active", false)) and not _client() \
			and game.state == "playing" and float(game.time.realNow) - float(_switchThrownAt if _switchThrownAt != null else 0.0) > 4.0:
		_rearmSwitch()
	if _switchT >= 0.0 and sw is Node3D:
		_switchT += dt
		var k := clamp01(_switchT / 0.28)
		sw.rotation.x = 1.9 * (k * k if k < 1.0 else 1.0)
		if k >= 1.0:
			_switchT = -1.0
	if _outline != null:
		var rn: float = game.time.realNow
		var col := hueColor(rn * 0.35)
		var lin := Color(DAU.srgbToLinear(col.r), DAU.srgbToLinear(col.g), DAU.srgbToLinear(col.b))
		var km := 2.2 + sin(rn * 6.0) * 0.6
		(_outline.mat as ShaderMaterial).set_shader_parameter("color", Color(lin.r * km, lin.g * km, lin.b * km, 1.0))
		_outline.t += rdt
		if _outline.t > 0.1:
			_outline.t = 0.0
			_oc(game.lights, "setAnchor", ["ee_switch_glow", {"color": "#" + col.to_html(false), "intensity": 2 + sin(rn * 5.0) * 0.6}])
	# ON AIR boxes flash after the tape (2 s), then stay as the power says
	if _onAirT >= 0.0:
		_onAirT += rdt
		var lv = game.level
		var on := int(floor(_onAirT * 6.0)) % 2 == 0
		if _onAirT >= 2.2:
			_onAirT = -1.0
			_oc(lv, "setOnAir", [bool(_g(lv, "powered", false))])
		elif on != _onAirOn:
			_onAirOn = on
			_oc(lv, "setOnAir", [on])

func _updatePost(rdt: float) -> void:
	var post = _g(game.render, "post")
	if _whiteT >= 0.0 and post is Dictionary:
		_whiteT += rdt
		var k := _whiteT
		post.whiteout = 0.5 if k < 0.05 else maxf(0.0, 0.5 * (1.0 - (k - 0.05) / 0.45))
		if k > 0.65:
			post.whiteout = 0.0
			_whiteT = -1.0
	var fx = _strikeFx
	if fx != null:
		fx.t += rdt
		var k2: float = fx.t
		var o := (1.0 if randf() < 0.75 else 0.25) if k2 < 0.45 else maxf(0.0, 1.0 - (k2 - 0.45) / 0.25)
		_setOpacity((fx.bolt as MeshInstance3D).material_override, o)
		if k2 > 0.72:
			for m in [fx.bolt, fx.down]:
				_free(m)
			_strikeFx = null

# ================================================================================================ debug
func revealLayer2(on: bool = true) -> bool:
	var c: Camera3D = game.camera
	if c != null:
		c.set_cull_mask_value(Config.LAYERS.TV_ONLY + 1, on)
	return on

func debugHit(id, opts: Dictionary = {}) -> bool:
	var melee: bool = opts.get("melee", false)
	var info := {"id": id, "melee": melee, "cause": "melee" if melee else "bullet", "weaponId": "melee" if melee else "revolver_38", "damage": 50, "dir": Vector3(-1, 0, 0)}
	var c := str(id).replace("ee_bar_", "")
	if BARS.has(c):
		_barFrame = -1
		_onBarHit(c, info)
		return true
	var p = puppets.get(id)
	if p != null:
		_onPuppetHit(p, info)
		return p.state == "tuning"
	return false

func debugUse(id) -> bool:
	var sid := str(id)
	if sid.begins_with("pickup:"):
		var p = puppets.get(sid.substr(7))
		if p != null:
			_usePickup(p)
		return p != null
	var items = _g(game.interact, "items")
	var it = items.get(sid) if items is Dictionary else null
	if it == null:
		return false
	var en = _g(it, "enabled")
	if en is Callable and not en.call():
		return false
	_oc(it, "use")
	return true

# a qualifying kill at (x, z) without a zombie (the handler only, no zombie:kill broadcast)
func debugKill(x: float, z: float) -> int:
	_onKill({"z": null, "pos": Vector3(x, 0, z), "cause": "debug"})
	return applause

# just the applause hands at (x, z) (no count, no sound)
func debugClap(x: float, z: float) -> bool:
	return _spawnClap(Vector3(x, _floorY(x, z, 2), z), null) != null

func debugStorm(x = null, z = null) -> bool:
	var pl = game.player
	var px: float = x if x != null else pl.pos.x + 6.0
	var pz: float = z if z != null else pl.pos.z
	return _spawnStorm(Vector3(px, _floorY(px, pz) + 2.5, pz)) != null

func debugGiveTape(peer: int = 0) -> bool:
	var g = game
	if _host() and peer != 0 and peer != _lid():
		_net().everyone("egg", "tape", [peer])     # MP test: a remote carrier (no reel model here)
		return true
	var back = _g(_g(_g(g.player, "hero"), "slots"), "back")
	var reel = _g(g.telly, "tapeReel")
	if reel == null:
		# telly.gd's buildTapeReel (JS: import { buildTapeReel } from './telly.js')
		if _has(g.telly, "buildTapeReel"):
			reel = _oc(g.telly, "buildTapeReel", [g])
		if not (reel is Node3D):
			reel = DAU.node3d("ee_tape_reel")
		if back is Node3D:
			back.add_child(reel)
			reel.position = Vector3(0, 0.05, 0.09)
			reel.rotation = Vector3(0, 0, 0.15)
			reel.scale = Vector3.ONE * 0.9
		if g.telly != null:
			_s(g.telly, "tapeReel", reel)
	_reel = reel
	hasTape = true
	if _host():
		_net().everyone("egg", "tape", [_lid()])
	return true

func debugTrack(k: int) -> int:
	var tr = _track
	var knob = O.get("ee_tracking_knob")
	_oc(knob, "set", [k, true])
	if tr != null:
		tr.k = posmod(k, 13)
		tr.quietT = 0.0
		_oc(_tones, "setDistance", [_trackDist()])
	return _trackDist()

static func _r2(x: float) -> float:
	return snappedf(x, 0.01)

static func _arr2(v: Vector3) -> Array:
	return [_r2(v.x), _r2(v.y), _r2(v.z)]

func debugState() -> Dictionary:
	var tr = _track
	var pups := {}
	for p in puppets.values():
		pups[p.key] = {"state": p.state, "layer": p.layer, "home": _arr2(p.home), "drop": _arr2(p.drop)}
	var bars: Array = []
	var barT: Array = []
	for b in _bars:
		bars.append(b.bar)
		barT.append(_r2(b.t))
	return {
		"step": step, "done": done, "power": powered, "forceForecaster": forceForecaster, "applause": applause,
		"hasTape": hasTape, "carried": carried.duplicate(), "bars": bars, "barT": barT, "sign": _signMode,
		"puppets": pups,
		"storm": {"state": storm.state, "age": _r2(storm.age), "pos": _arr2(storm.pos), "lostT": _r2(storm.lostT), "crumbs": _crumbs.size(), "zaps": storm.get("zaps", 0)} if storm != null else null,
		"track": {"s0": tr.s0, "kT": tr.kT, "k": tr.k, "d": _trackDist(), "quietT": _r2(tr.quietT), "started": tr.started} if tr != null else null,
		"killSwitchUsed": _killSwitchUsed, "outline": _outline != null, "jobs": _jobs.size(),
		"claps": _claps.size(), "clapDraws": ((2 if (_hands.l as Node3D).visible else 0) if _hands != null else -1),
	}
