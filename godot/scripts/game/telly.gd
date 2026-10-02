# DEAD AIR — Telly, the living console TV (the mystery box, 950): GDD §10.2 entirely, §6.7 (lamp language), §18.10,
# §18.15. Port of src/game/telly.js (owner: telly engineer). Builds Telly + its four homes, runs the pull, the glove,
# the sign-off relocation, percussive maintenance and the EE hooks. Constructed by machines.gd as game.telly.
#
# HOMES  telly_home_green (T1), telly_home_newsroom (T2), telly_home_studio_a (T3), telly_home_studio_b (T4)
#   Each home (layout anchor: Telly pos/rotY + couch + lamp) gets couch_avocado, telly_rug (dust footprint),
#   telly_lamp (light anchor `telly_lamp_<homeId>`) and telly_cord (props 'telly_*', Blender port of
#   src/props/machines.js), parented to its area root (portal culled). The lamp is lit only where Telly lives (dim
#   amber before power, full after, flickering purple in the EE mood; a glowing shade + warm fx.lightPool on the
#   floor, an unlit one looks dead); empty homes show the clean dust rectangle and the unplugged cord. A 60 Hz hum
#   loop (telly_hum, 12 m) follows Telly. Start home: T1 or T2 (game.rand). The CRT spill (light anchor
#   'telly_screen' + floor pool) takes the colour of the channel on screen.
# SIZE  Telly stands SCALE (1.1x) bigger than the prop's modelling size (player feedback: its screen and cards must
#   read from gameplay distance). The root is scaled about its floor origin, so everything in prop space follows
#   (cabinet, legs, dial, antennas, glove reach + presentation point, the item diorama, screen, Zzz, local fx points);
#   the world-space parts are scaled by hand: collider, interact radius, melee reach test, bullet ray, CRT spill,
#   refund coin, relocation dot/line, waddle footprint, the dust footprint decal. Lamps that would now touch the
#   cabinet are eased sideways (see _buildHomes).
#
# PUBLIC API (game.telly)
#   homeId            current home anchor id (null while it is between homes)
#   state             'idle' | 'spinning' | 'offer' | 'moving'      phase: finer ('asleep','spin','land','bulge',
#                     'offer','take','timeout','signoff','bad', ...)   pulls (this game), pullsHere, pity
#   awake             true once the colour wave woke it (sleeps before power: prompt [E] plug)
#   pull({free, forced}) -> bool   the 950 pull (what E does): spends, rolls the result FIRST, then choreographs
#                           the dial (forced = item id | 'signoff' | 'bad' | 'tape': the Morning Show's 13-point pulls)
#   take() -> bool          takes the presented item (what E does during the offer)
#   forceTapePull()         arms the EE step-5 tape pull: the next pull lands on the blank notch "0" and the glove
#                           pushes out the 2-inch quad reel (no timeout, no bump, no sign-off). egg:step {step:4}
#                           arms it automatically and sets the purple mood.
#   setMood('purple'|'normal')  EE step-4 hook: purple flickering lamp, constant shiver, Baron-face glitches.
#   onHit(info)             shootable handler: info.melee -> percussive maintenance / smack rules, bullets -> tink
#   tapeReel                the reel Node3D once taken (strapped to player.hero.slots.back); the egg may
#                           re-parent it (VTR #2). buildTapeReel(game) (static) is exported for reuse.
#   canMove(), canPull()    another home lies in an opened area (sign-offs need it) / a pull can start now
#   morning, disabled       flags set from outside (ending.gd's Morning Show wrapper / boss.gd), declared here
#                           because a GDScript object cannot grow new fields at runtime.
# Interactable 'machine_telly' (interact.register): prompt {plug:true} asleep, {cost:950} idle, {} while the glove
#   offers (key only), null otherwise. Shootable 'machine_telly' via weapons.registerShootable (melee + bullets);
#   while weapons has no registerShootable, weapon:melee / weapon:fire are hit-tested here instead.
#
# EVENTS (GDD §18.15)
#   machine:telly_spin {homeId}                  machine:telly_result {result, channel}   result = item id |
#   machine:telly_bump {fromChannel, toChannel}     'signoff' | 'tape' | 'bad_reception' (bumped into snow, no move)
#   machine:telly_take {itemId}  (itemId 'ee_tape_reel' for the EE reel)   machine:telly_move {from, to}
#   weapon:acquire {source:'telly'} comes from weapons.give(id, {source:'telly'}).
#
# DEBUG  debugPull(outcome?, {free}) outcome = item id | 'signoff' | 'bad' | 'tape' (charges 950 when affordable)
#        debugBump() (melee smack now) · debugHit({melee}) · debugTake() · debugMove(homeId) · debugWake()
#        debugFreezeAt(t) (sets game.time.scale = 0 when the pull timeline reaches t; scale = 1 resumes)
#        debugState() -> snapshot Dictionary
#
# PROP RUNTIME HELPERS (ports of the helpers src/props/machines.js exports for Telly's parts; static, usable by
#   ending.gd / menu.gd on their own Telly / lamp props): updateTellyArm(g), setTellyLegs(g, t), setTellyDial(g, ch),
#   setTellyGlove(g, pose), setLampLevel(game, g, level), partsOf(g) (the resolved userData.parts of a prop).
#
# GODOT PORT NOTES
#   * Static runtime meshes of the JS module (the EE tape reel, the refund coin) and its static canvas textures (Zzz,
#     afterglow dot, the lamp shade weaves the lamp language swaps in) are Blender assets built by
#     blender/runtime/telly.py into res://assets/runtime/telly/. Per-frame meshes (the stretchy arm tube, the merged
#     outline hull of a display model) are built here (ArrayMesh). The rubber-glass bubble, the outline hull and the
#     sprites are Godot shaders written below (same GLSL maths as the JS ShaderMaterials).
#   * Not ported (engine plumbing, SPEC §0.2): bakeStatic (legs/cord and display-model draw-call merges; the original
#     meshes simply stay visible), warmup() (shader precompile samples), the CanvasTexture needsUpdate plumbing.
#   * Renames (SPEC §3.2): none of this module's own names collide. Calls into other systems' `set`/`get` methods
#     go through _invoke(), which prefers the renamed `set_`/`get_` (and accepts Dictionaries of Callables).
#   * Locals holding the game are named `gm` (the member `g` is the Telly prop, as in the JS).
extends RefCounted

const TELLY_HOMES := ["telly_home_green", "telly_home_newsroom", "telly_home_studio_a", "telly_home_studio_b"]
const RUNTIME_DIR := "res://assets/runtime/telly/"

# ------------------------------------------------------------------------------------------------ constants
const TAU := PI * 2.0
const WONDER := ["zapper", "boom_mic", "chroma_key"]
const CYCLE := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
const CYCLE_EE := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0]
const DIAL_ORDER := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0]
const TAPE_ID := "ee_tape_reel"

# Pull timeline (GDD §10.2 table): SPIN / WINDOW / OFFER depend on Config.T.telly and are built in _init().
const LAND := {"jingle": 0.35, "bulge": 0.60, "bulgeDur": 0.40}          # relative to the landing (4.30)
# Sign-off beats relative to the landing. The GDD packs stand + shake + turn + a 2 s waddle + turn + wave into
# 2.5 s; here each beat keeps its own duration (power-off lands ~1.1 s later than 10.40).
const SO := {"card": 0.6, "gloveOut": 0.95, "flick": 1.45, "coin": 0.5, "gloveIn": 2.05, "stand": 3.25, "shake": 3.6,
	"turn": 4.0, "walk": 4.3, "walkDur": 2.0, "turnBack": 6.3, "wave": 6.55, "off": 7.15, "squash": 7.45, "gone": 7.85,
	"arrive": 9.15, "unfold": 9.45, "done": 10.3}
const BAD := {"gloveOut": 0.6, "shrug": 0.9, "flick": 1.75, "coin": 0.5, "gloveIn": 2.35, "done": 2.9}
const NEAR_WAKE := 6.0
const NEAR_DOZE := 7.2
const ZOMBIE_NEAR := 3.0
const SCALE := 1.1                                   # Telly's size vs the prop (uniform, applied on root)
const PIV := Vector3(0.12, 0.9, -0.3)               # screen centre in prop space (collapse / unfold pivot)
const BOX := {"x": 0.72, "y0": 0.0, "y1": 1.42, "z": 0.38}  # cabinet hit box (prop space)
# lamp shade vs cabinet (prop space: body half width with the pillowy bulge + lid overhang, half depth + lid)
const LAMP_CLEAR := {"hw": 0.69, "hd": 0.34, "top": 1.44, "shadeR": 0.37, "shadeY0": 1.29, "gap": 0.05}
const GLOW_CRT := "#9FD8FF"
# CRT light spill per show (the room takes the colour of the channel on screen)
const CH_GLOW := {2: "#8AA2FF", 4: "#FFB06A", 5: "#F48CFF", 7: "#86E08E", 8: "#FFC45C", 9: "#FFE26A", 11: "#B49CFF",
	12: "#FF7CD6", 13: "#7FE3FF"}
const KIND_GLOW := {"face": GLOW_CRT, "snow": "#D6E6FF", "baron": "#C47BFF", "test": "#EDEAFF", "black": GLOW_CRT}
const ITEM_LIFT := 0.075                             # presented item above the glove's hold point (m)
const SW := 384
const SH := 288

# src/props/kit.js MAT presets used by the lamp language (K.mat forces vertexColors).
const KIT_MAT := {
	"fabric": {"rough": 0.95, "rim": 0.5, "wrap": 0.7, "rimPower": 1.8},
	"ceramic": {"rough": 0.22, "rim": 0.3, "env": 0.15},
}
# Object methods that other systems had to rename with a trailing underscore (SPEC §3.2).
const _RENAMED := ["set", "get", "call", "free", "connect", "notification", "duplicate", "to_string", "get_class",
	"is_class", "emit_signal"]

# ------------------------------------------------------------------------------------------------ helpers
static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func easeOutCubic(x: float) -> float:
	return 1.0 - pow(1.0 - clamp01(x), 3.0)

static func easeInCubic(x: float) -> float:
	var c := clamp01(x)
	return c * c * c

static func easeInOut(x: float) -> float:
	x = clamp01(x)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

static func easeOutBack(x: float, s: float = 1.9) -> float:
	x = clamp01(x) - 1.0
	return 1.0 + (s + 1.0) * x * x * x + s * x * x

static func easeInBack(x: float, s: float = 1.7) -> float:
	x = clamp01(x)
	return (s + 1.0) * x * x * x - s * x * x

static func easeOutElastic(x: float) -> float:
	x = clamp01(x)
	return x if x == 0.0 or x == 1.0 else pow(2.0, -9.0 * x) * sin((x * 8.0 - 0.75) * (TAU / 3.0)) + 1.0

static func smooth(x: float) -> float:
	x = clamp01(x)
	return x * x * (3.0 - 2.0 * x)

static func wrapPi(a: float) -> float:
	return atan2(sin(a), cos(a))

# JS Math.round (.5 rounds toward +inf)
static func jround(x: float) -> float:
	return floorf(x + 0.5)

# ---- cross-module plumbing: JS `a?.b?.(...)` on systems that may be missing while the port is incomplete.
# o.m(...args): Objects (prefers the SPEC §3.2 renamed `m_`) or Dictionaries holding Callables. null when absent.
static func _invoke(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Dictionary:
		var f = o.get(m + "_", o.get(m))
		if f is Callable and (f as Callable).is_valid():
			return (f as Callable).callv(args)
		return null
	if o is Object and is_instance_valid(o):
		if (o as Object).has_method(m + "_"):
			return (o as Object).callv(m + "_", args)
		if not _RENAMED.has(m) and (o as Object).has_method(m):
			return (o as Object).callv(m, args)
	return null

static func _hasm(o, m: String) -> bool:
	if o == null:
		return false
	if o is Dictionary:
		return o.get(m + "_", o.get(m)) is Callable
	if o is Object and is_instance_valid(o):
		return (o as Object).has_method(m + "_") or (not _RENAMED.has(m) and (o as Object).has_method(m))
	return false

# o.name (Dictionary key or Object property), `def` when missing / null.
static func _field(o, name: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		var v = o.get(name)
		return def if v == null else v
	if o is Object and is_instance_valid(o):
		var v = (o as Object).get(name)
		return def if v == null else v
	return def

static func _num(v, def: float = 0.0) -> float:
	return float(v) if (v is float or v is int) else def

# World transform of a node, also outside the scene tree (object.matrixWorld after updateMatrixWorld).
static func _gxf(n: Node3D) -> Transform3D:
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

# object.attach(child): re-parent keeping the world transform.
static func _attach(parent: Node3D, child: Node3D) -> void:
	var w := _gxf(child)
	var old := child.get_parent()
	if old != null:
		old.remove_child(child)
	parent.add_child(child)
	child.transform = _gxf(parent).affine_inverse() * w

static func _reparent(parent: Node, child: Node) -> void:
	if child.get_parent() == parent:
		return
	if child.get_parent() != null:
		child.get_parent().remove_child(child)
	parent.add_child(child)

# Imported glTF nodes use Godot's YXZ Euler order: switch to three's 'XYZ' keeping the current orientation (setting
# rotation_order alone keeps the Euler angles and changes the basis).
static func _xyz(n) -> void:
	if n is Node3D and (n as Node3D).rotation_order != EULER_ORDER_XYZ:
		var b := (n as Node3D).basis
		(n as Node3D).rotation_order = EULER_ORDER_XYZ
		(n as Node3D).basis = b

static func _meshes(root: Node) -> Array:
	var out: Array = []
	DAU.traverse(root, func(o): if o is MeshInstance3D: out.append(o))
	return out

static func _noShadow(root: Node) -> void:
	for m in _meshes(root):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ------------------------------------------------------------------------------------------------ prop parts
# The Telly prop's JS userData.parts, resolved to nodes: {"__node": name} / name strings / nested arrays and
# dictionaries (legs, gloveFingers). Falls back to the JS node names. Cached on the prop (meta).
const PART_NAMES := {"body": "body", "screen": "screen", "glass": "glass", "weaponSlot": "weaponSlot", "dial": "dial",
	"uhf": "uhf", "pilot": "pilot", "antennas": "antennas", "earL": "earL", "earR": "earR", "cord": "cord",
	"armRig": "armRig", "armCtrl": "armCtrl", "arm": "arm", "glove": "glove", "gloveHold": "glove_hold"}

static func _resolve(root: Node, v):
	if v is Node:
		return v
	if v is String or v is StringName:
		return DAU.byName(root, str(v))
	if v is Dictionary:
		if v.has("__node"):
			return DAU.byName(root, str(v["__node"]))
		var o := {}
		for k in v:
			o[k] = _resolve(root, v[k])
		return o
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_resolve(root, x))
		return a
	return v

# Generic userData.parts of any prop (lamp: bulb/lining/shade, rug: dust), with by-name fallbacks for `names`.
static func _partsGeneric(root: Node, names: Array = []) -> Dictionary:
	if root == null:
		return {}
	if root.has_meta("_daParts"):
		return root.get_meta("_daParts")
	var raw = DAU.ud(root).get("parts", {})
	var P := {}
	if raw is Dictionary:
		for k in raw:
			P[k] = _resolve(root, raw[k])
	for k in names:
		if P.get(k) == null:
			P[k] = DAU.byName(root, k)
	root.set_meta("_daParts", P)
	return P

static func partsOf(g: Node) -> Dictionary:
	if g == null:
		return {}
	if g.has_meta("_tellyParts"):
		return g.get_meta("_tellyParts")
	var raw = DAU.ud(g).get("parts", {})
	var P := {}
	if raw is Dictionary:
		for k in raw:
			P[k] = _resolve(g, raw[k])
	for k in PART_NAMES:
		if not (P.get(k) is Node):
			P[k] = DAU.byName(g, PART_NAMES[k])
	var legs = P.get("legs")
	if not (legs is Array) or (legs as Array).is_empty() or not ((legs as Array)[0] is Node):
		legs = []
		for i in 4:
			var l := DAU.byName(g, "leg%d" % i)
			if l != null:
				legs.append(l)
		P["legs"] = legs
	var F = P.get("gloveFingers")
	if not (F is Dictionary) or not (F.get("index") is Node):
		F = {}
		for f in ["index", "middle", "pinky", "thumb"]:
			F[f] = DAU.byName(g, "glove_" + f)
		P["gloveFingers"] = F
	# parts the runtime turns with Euler angles use three's XYZ order
	for k in ["dial", "uhf", "antennas", "earL", "earR"]:
		_xyz(P.get(k))
	for f in F:
		_xyz(F[f])
	g.set_meta("_tellyParts", P)
	return P

# ------------------------------------------------------------------------------------------------ prop helpers
# Port of the runtime helpers src/props/machines.js exports for the Telly prop (TL = its build constants).
const TL := {"legH": 0.35, "sy": 0.55, "legSplay": [0.27, 0.19]}
const ARM := {"rings": 32, "radial": 9, "r": 0.052, "ribs": 9, "restLen": 0.6}
static var _armIdx := PackedInt32Array()

static func _extLen() -> float:
	var d := Vector3(sin(TL.legSplay[0]), -1.0, sin(TL.legSplay[1])).normalized()
	return 0.4 / -d.y                                  # telescoping travel along the axis (+0.4 m of height)

# VHF detents: 2..13 then the blank notch, clockwise from lower-left, blank at 6 o'clock.
static func _dialAngle(i: int) -> float:
	var step := TAU / 13.0
	return i * step - (12.0 * step - PI)

# Rebuilds Telly's arm tube from parts.armRig origin (inside the screen) through parts.armCtrl (curve control)
# to the glove's cuff. Call after moving parts.glove / parts.armCtrl. The tube thins as it stretches and its
# accordion ribs spread out (fixed rib count). The mesh is an ArrayMesh rebuilt in place (per-frame geometry).
static func updateTellyArm(g: Node) -> void:
	var P := partsOf(g)
	var arm = P.get("arm")
	var glove = P.get("glove")
	var ctrl = P.get("armCtrl")
	if not (arm is MeshInstance3D) or not (glove is Node3D):
		return
	var a0 := Vector3.ZERO
	var a1: Vector3 = (ctrl as Node3D).position if ctrl is Node3D else Vector3.ZERO
	var a2: Vector3 = (glove as Node3D).transform * Vector3(0.0, -0.085, 0.0)   # cuff mouth
	# arc length (coarse)
	var L := 0.0
	var prev := a0
	for i in range(1, 17):
		var t := i / 16.0
		var p := a0 * ((1.0 - t) * (1.0 - t)) + a1 * (2.0 * (1.0 - t) * t) + a2 * (t * t)
		L += p.distance_to(prev)
		prev = p
	var thin := sqrt(clampf(ARM.restLen / maxf(L, 1e-3), 0.45, 1.25))
	var rings: int = ARM.rings
	var radial: int = ARM.radial
	var n := (rings + 1) * (radial + 1)
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	pos.resize(n)
	nor.resize(n)
	col.resize(n)
	uv.resize(n)
	var gold := Color("#F2A51E").srgb_to_linear()
	var dark := Color("#9A4E0C").srgb_to_linear()
	# parallel-transport frame
	var nn := Vector3(1, 0, 0)
	for i in rings + 1:
		var t := float(i) / rings
		var p := a0 * ((1.0 - t) * (1.0 - t)) + a1 * (2.0 * (1.0 - t) * t) + a2 * (t * t)
		# tangent
		var tg := a0 * (-2.0 * (1.0 - t)) + a1 * (2.0 - 4.0 * t) + a2 * (2.0 * t)
		if tg.length_squared() < 1e-10:
			tg = Vector3(0, 0, -1)
		tg = tg.normalized()
		nn -= tg * nn.dot(tg)
		if nn.length_squared() < 1e-8:
			nn = Vector3(0, 1, 0) - tg * tg.y
		nn = nn.normalized()
		var b := tg.cross(nn)
		var rib := 0.5 + 0.5 * cos(t * ARM.ribs * TAU)
		var r: float = ARM.r * thin * (0.84 + 0.26 * rib) * (1.08 - 0.2 * t)
		var c := dark.lerp(gold, 0.35 + 0.65 * rib)
		for j in radial + 1:
			var a := (float(j) / radial) * TAU
			var ca := cos(a)
			var sa := sin(a)
			var k := i * (radial + 1) + j
			var nv := nn * ca + b * sa
			pos[k] = p + nv * r
			nor[k] = nv
			col[k] = Color(c.r, c.g, c.b, 1.0)
			uv[k] = Vector2(float(j) / radial, 1.0 - t)
	if _armIdx.is_empty():
		for i in rings:
			for j in radial:
				var a := i * (radial + 1) + j
				var bb := a + radial + 1
				# three's CCW (a, a+1, b) (a+1, b+1, b) -> Godot's clockwise front faces
				_armIdx.append_array(PackedInt32Array([a, bb, a + 1, a + 1, bb, bb + 1]))
	var mi := arm as MeshInstance3D
	var mesh: ArrayMesh = mi.get_meta("_armMesh") if mi.has_meta("_armMesh") else null
	if mesh == null:
		# keep the prop's material (plastic, vertex colours) on the rebuilt tube
		var mat: Material = mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_surface_override_material(0) if mi.get_surface_override_material(0) != null else mi.mesh.surface_get_material(0)
		mesh = ArrayMesh.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.extra_cull_margin = 2.0                    # frustumCulled = false
		mi.set_meta("_armMesh", mesh)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = _armIdx
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

# Legs telescope: t = 0 (rest, top at 1.35 m) .. 1 (standing, +0.4 m). Moves parts.body and every leg's
# chrome tube/foot so the feet stay on the floor.
static func setTellyLegs(g: Node, t: float) -> void:
	var P := partsOf(g)
	t = clampf(t, 0.0, 1.0)
	if P.get("body") is Node3D:
		(P.body as Node3D).position.y = TL.legH + t * 0.4
	var ext := _extLen()
	for leg in P.get("legs", []):
		if not (leg is Node3D):
			continue
		var u := DAU.ud(leg)
		var tube = DAU.byName(leg, str(u.get("tubeName", str(leg.name) + "_tube")))
		var foot = DAU.byName(leg, str(u.get("footName", str(leg.name) + "_foot")))
		if tube is Node3D:
			(tube as Node3D).scale.y = maxf(1e-3, t)
			(tube as Node3D).visible = t > 0.01
		if foot is Node3D:
			(foot as Node3D).position.y = -0.14 - t * ext

# Turns the VHF dial to a channel (2..13, 0 = blank notch); returns the rotation.z used.
static func setTellyDial(g: Node, ch: int) -> float:
	var i := maxi(0, DIAL_ORDER.find(ch))
	var a := _dialAngle(i)
	var d = partsOf(g).get("dial")
	if d is Node3D:
		(d as Node3D).rotation.z = a
	return a

# Glove poses for previews: 'hidden' | 'present' | 'fingerguns' | 'wag'. The machine animates the same parts.
static func setTellyGlove(g: Node, pose: String = "present") -> void:
	var P := partsOf(g)
	var F: Dictionary = P.get("gloveFingers", {})
	var glove = P.get("glove")
	var ctrl = P.get("armCtrl")
	if not (glove is Node3D) or not (ctrl is Node3D):
		return
	var show := pose != "hidden"
	glove.visible = show
	if P.get("arm") is Node3D:
		P.arm.visible = show
	if P.get("glass") is Node3D:
		P.glass.visible = not show                 # the membrane has parted while the glove is out
	if not show:
		glove.position = Vector3(0, 0, 0.02)
		glove.quaternion = Quaternion.IDENTITY
		ctrl.position = Vector3(0, 0, -0.02)
		updateTellyArm(g)
		return
	# item 0.8 m in front of the screen at 1.2 m height (legs at rest): palm up, fingers to the viewer's left
	glove.position = Vector3(-0.02, 1.12 - (TL.legH + TL.sy), -0.74)
	ctrl.position = Vector3(0.06, -0.26, -0.34)
	var y := Vector3(1, 0.28, -0.3).normalized()
	var z := Vector3(0, -1, 0.1)
	z = (z - y * z.dot(y)).normalized()
	var x := y.cross(z)
	glove.quaternion = Basis(x, y, z).get_rotation_quaternion()
	if P.get("gloveHold") is Node3D:
		P.gloveHold.quaternion = (glove.quaternion as Quaternion).inverse()   # hold stays aligned with Telly's axes
	var curls := {"present": [-0.35, -0.45, -0.55, -0.3], "fingerguns": [-0.05, -1.9, -2.0, 0.3], "wag": [0.05, -1.9, -2.0, -1.2]}
	var curl: Array = curls.get(pose, [-0.3, -0.3, -0.3, -0.3])
	if F.get("index") is Node3D:
		F.index.rotation.x = curl[0]
	if F.get("middle") is Node3D:
		F.middle.rotation.x = curl[1]
	if F.get("pinky") is Node3D:
		F.pinky.rotation.x = curl[2]
	if F.get("thumb") is Node3D:
		F.thumb.rotation.x = curl[3] - 0.35
	if pose == "fingerguns" or pose == "wag":
		glove.quaternion = Basis.from_euler(Vector3(-0.25, 0.25, 0.2 if pose == "wag" else -PI / 2.0 + 0.2), EULER_ORDER_XYZ).get_rotation_quaternion()
		glove.position = Vector3(0.05, 0.62, -0.62)
	updateTellyArm(g)

# Lamp levels: 0 = off, ~0.35 = dim amber (before power), 1 = full. Swaps the bulb / lining / shade materials on
# this instance (materials themselves stay shared). The pooled light is the room code's job:
# game.lights.setAnchor(anchorId, { intensity: 1.6 * level }) (see userData.lightAnchors[0].id / opts.anchorId).
static func setLampLevel(game_, g: Node, level: float = 1.0) -> void:
	var P := _partsGeneric(g, ["bulb", "lining", "shade"])
	var q := jround(clampf(level, 0.0, 1.0) * 20.0) / 20.0
	var mats = _field(game_, "mats")
	if P.get("bulb") is MeshInstance3D:
		P.bulb.material_override = _invoke(mats, "glow", [Config.PAL.gelAmber if q < 0.6 else Config.PAL.tungsten, 0.6 + 3.4 * q]) if q > 0.0 else _kitMat(game_, "ceramic", "#E8DCC0")
	if P.get("lining") is MeshInstance3D:
		P.lining.material_override = _invoke(mats, "glow", ["#FFD9A0", 0.25 + 0.9 * q]) if q > 0.0 else _kitMat(game_, "fabric", "#8A6A3A")
	if P.get("shade") is MeshInstance3D:
		P.shade.material_override = _kitMat(game_, "fabric", "#ffffff", {"map": _weave("#E9B64A"), "mapWrap": "repeat", "side": "double", "emissive": "#FF9A40", "emissiveIntensity": 0.34 * q})
	DAU.ud(g)["lampLevel"] = q

# K.mat(game, preset, color, extra) = mats.toon(color, {...MAT[preset], vertexColors: true, ...extra})
static func _kitMat(game_, preset: String, color: String, extra: Dictionary = {}):
	var o: Dictionary = KIT_MAT.get(preset, {}).duplicate()
	o["vertexColors"] = true
	o.merge(extra, true)
	return _invoke(_field(game_, "mats"), "toon", [color, o])

static var _texCache := {}

# K.tex.weave(base, {pattern:'plain', scale:3}) — drawn in Blender (blender/runtime/telly.py).
static func _weave(base: String):
	return _tex("weave_%s.png" % base.trim_prefix("#").to_upper())

static func _tex(file: String):
	if _texCache.has(file):
		return _texCache[file]
	var path := RUNTIME_DIR + file
	var t = load(path) if ResourceLoader.exists(path) else null
	if t == null:
		push_warning("[telly] missing runtime texture %s" % path)
	_texCache[file] = t
	return t

# Instantiates a Blender runtime asset (res://assets/runtime/telly/<file>.glb): props.loadRuntime(path) (the prop
# conversion: "da" extras -> DAU.ud(node), material specs -> game.mats.fromSpec, node flags); without the prop
# library, the same conversion done here.
static func _loadRuntime(game_, file: String) -> Node3D:
	var path := RUNTIME_DIR + file
	if not ResourceLoader.exists(path):
		push_warning("[telly] missing runtime asset %s" % path)
		return null
	var props = _field(game_, "props")
	if _hasm(props, "loadRuntime"):
		return _invoke(props, "loadRuntime", [path])
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var n: Node = (ps as PackedScene).instantiate()
	var mats = _field(game_, "mats")
	DAU.traverse(n, func(o):
		if o.has_meta("extras"):
			var ex = o.get_meta("extras")
			if ex is Dictionary and ex.has("da"):
				var da = JSON.parse_string(str(ex["da"])) if ex["da"] is String else ex["da"]
				if da is Dictionary:
					DAU.ud(o).merge(da, true)
					if o is Node3D and da.get("visible") == false:
						o.visible = false
					if o is GeometryInstance3D and da.get("castShadow") == false:
						o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if o is MeshInstance3D and o.mesh != null and _hasm(mats, "fromSpec"):
			for i in o.mesh.get_surface_count():
				var m: Material = o.mesh.surface_get_material(i)
				if m == null or not m.has_meta("extras"):
					continue
				var mex = m.get_meta("extras")
				var spec = mex.get("da") if mex is Dictionary else null
				if spec is String:
					spec = JSON.parse_string(spec)
				if spec is Dictionary:
					var conv = _invoke(mats, "fromSpec", [spec, m])
					if conv is Material:
						o.set_surface_override_material(i, conv))
	return n as Node3D

# The EE 2-inch quad videotape reel: 0.36 m aluminium reel, gold tape pack, white label with a marker "13".
# Faces -z, centred at the origin (hub axis = z). Blender asset (blender/runtime/telly.py: build_tape_reel).
static func buildTapeReel(game_) -> Node3D:
	var n := _loadRuntime(game_, "ee_tape_reel.glb")
	if n == null:
		return null
	n.name = "prop:" + TAPE_ID
	var u := DAU.ud(n)
	if not u.has("id"):
		u["id"] = TAPE_ID
	u["colliders"] = []
	return n

# ------------------------------------------------------------------------------------------------ shaders
const HUE_GLSL := "vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }\n"

# Soap-bubble membrane: the screen glass bulging outward into a wobbling dome (GDD §10.2, 4.90–5.30). The plane is
# the prop-front CRT plane (faces local +z, w x h = uSize); c is taken from the vertex so any UV convention works.
const BUBBLE_SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform float uBulge = 0.0;
uniform float uWobble = 0.0;
uniform float uAlpha = 1.0;
uniform float uTime = 0.0;
uniform vec2 uSize = vec2(1.0, 0.75);
varying vec3 vN;
varying vec3 vView;
varying vec2 vUv;
""" + HUE_GLSL + """
void vertex() {
	vec2 c = VERTEX.xy / max(uSize * 0.5, vec2(1e-4));
	vUv = c * 0.5 + 0.5;
	float wob = 1.0 + uWobble * 0.35 * sin(uTime * 23.0 + c.x * 6.0) * sin(uTime * 17.0 - c.y * 5.0);
	float amp = uBulge * wob;
	float w = max((1.0 - c.x * c.x) * (1.0 - c.y * c.y), 0.0);
	vec3 p = VERTEX;
	p.z += amp * pow(w, 0.6);
	float dw = 0.6 * pow(max(w, 2e-3), -0.4);
	float dx = amp * dw * (-2.0 * c.x) * (1.0 - c.y * c.y) * 2.0 / max(uSize.x, 1e-3);
	float dy = amp * dw * (-2.0 * c.y) * (1.0 - c.x * c.x) * 2.0 / max(uSize.y, 1e-3);
	vN = normalize(MODELVIEW_NORMAL_MATRIX * normalize(vec3(-dx, -dy, 1.0)));
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	vView = -mv.xyz;
	POSITION = PROJECTION_MATRIX * mv;
}
void fragment() {
	vec3 n = normalize(vN);
	vec3 v = normalize(vView);
	if (!FRONT_FACING) n = -n;
	float ndv = clamp(abs(dot(n, v)), 0.0, 1.0);
	float fr = pow(1.0 - ndv, 1.6);
	vec2 c = vUv * 2.0 - 1.0;
	// thin-film interference: swirling colour bands that drift like a real soap film
	float swirl = 0.22 * sin(c.x * 5.0 + uTime * 1.7) * cos(c.y * 4.0 - uTime * 1.3) + 0.12 * sin((c.x + c.y) * 9.0 - uTime * 2.4);
	vec3 film = mix(vec3(1.0), hue(fr * 1.3 + swirl + length(c) * 0.45 - uTime * 0.2), 0.85);
	vec3 r = reflect(-v, n);
	// a soft window highlight (the studio key light) + a small hot glint + a rim sheen
	float s1 = pow(max(dot(r, normalize(vec3(-0.45, 0.7, 0.55))), 0.0), 60.0);
	float s2 = pow(max(dot(r, normalize(vec3(0.55, 0.4, 0.75))), 0.0), 14.0) * 0.35;
	float bands = 0.5 + 0.5 * sin((fr * 7.0 + swirl * 6.0) * 3.14159);
	float edge = 1.0 - smoothstep(0.86, 1.0, max(abs(c.x), abs(c.y)));
	vec3 col = film * (0.35 + fr * 1.6 + bands * 0.25) + vec3(s1 * 3.0 + s2);
	float a = clamp((0.14 + fr * 0.9 + bands * 0.08 + s1 + s2) * uAlpha, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = a * mix(0.4, 1.0, edge);
}
"""

# Inverted-hull outline for the presented item: warm white, or a rainbow shimmer for wonder weapons.
const HULL_SHADER := """shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform float uThick = 0.01;
uniform vec3 uColor : source_color = vec3(1.0, 0.906, 0.722);
uniform float uRainbow = 0.0;
uniform float uGlow = 1.15;
uniform float uTime = 0.0;
varying vec3 vW;
""" + HUE_GLSL + """
void vertex() {
	VERTEX += normalize(NORMAL) * uThick;
	vW = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 rb = hue(fract(uTime * 0.55 + vW.y * 2.2 + (vW.x + vW.z) * 1.4)) * 1.15 + 0.12;
	vec3 c = mix(uColor, rb, uRainbow);
	float pulse = 0.82 + 0.18 * sin(uTime * 7.0 + vW.y * 9.0);
	ALBEDO = c * uGlow * pulse;
}
"""

# THREE.Sprite + SpriteMaterial (map, color, opacity, rotation): a camera-facing 1x1 quad scaled by the world scale.
const SPRITE_SHADER := """shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 color : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform float rotation = 0.0;
void vertex() {
	vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec2 ap = VERTEX.xy * sc;
	float c = cos(rotation);
	float s = sin(rotation);
	vec4 mv = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	mv.xy += vec2(c * ap.x - s * ap.y, s * ap.x + c * ap.y);
	POSITION = PROJECTION_MATRIX * mv;
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * color.rgb;
	ALPHA = t.a * opacity;
}
"""

static var _shaders := {}

static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]

static func bubbleMaterial(w: float, h: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("bubble", BUBBLE_SHADER)
	m.set_shader_parameter("uSize", Vector2(w, h))
	m.render_priority = 3                                 # renderOrder 3
	return m

static func hullMaterial() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("hull", HULL_SHADER)
	m.set_shader_parameter("uThick", 0.01)
	m.set_shader_parameter("uColor", Color("#FFE7B8"))
	m.set_shader_parameter("uRainbow", 0.0)
	m.set_shader_parameter("uGlow", 1.15)
	return m

static func spriteMaterial(tex, color: String, additive: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("sprite_add" if additive else "sprite", SPRITE_SHADER % ("blend_add" if additive else "blend_mix"))
	if tex != null:
		m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("color", Color(color))
	m.set_shader_parameter("opacity", 1.0)
	m.set_shader_parameter("rotation", 0.0)
	return m

static func spriteNode(mat: Material, name: String = "") -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var s := MeshInstance3D.new()
	s.mesh = q
	s.material_override = mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.extra_cull_margin = 1.0
	s.rotation_order = EULER_ORDER_XYZ
	if name != "":
		s.name = name
	return s

# One position+normal mesh of every mesh in `meshes`, in `space`'s frame (the inverted-hull outline of a whole
# display model in a single draw).
static func mergedHullGeometry(meshes: Array, space: Node3D) -> ArrayMesh:
	if meshes.is_empty():
		return null
	var inv := _gxf(space).affine_inverse()
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var idx := PackedInt32Array()
	for o in meshes:
		var mi := o as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var m := inv * _gxf(mi)
		var nb := m.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var sp: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sn = arr[Mesh.ARRAY_NORMAL]
			if sp.is_empty() or not (sn is PackedVector3Array) or (sn as PackedVector3Array).size() != sp.size():
				continue
			var base := pos.size()
			for i in sp.size():
				pos.append(m * sp[i])
				nor.append((nb * (sn as PackedVector3Array)[i]).normalized())
			var si_idx = arr[Mesh.ARRAY_INDEX]
			if si_idx is PackedInt32Array and not (si_idx as PackedInt32Array).is_empty():
				for i in (si_idx as PackedInt32Array):
					idx.append(base + i)
			else:
				for i in sp.size():
					idx.append(base + i)
	if pos.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

# ------------------------------------------------------------------------------------------------ Spring
# Damped spring toward a target (sub-stepped: dt may be 1/20 s).
class Spring extends RefCounted:
	var k: float
	var c: float
	var x: float
	var v := 0.0

	func _init(k_: float = 260.0, c_: float = 15.0, x_: float = 0.0) -> void:
		k = k_
		c = c_
		x = x_

	func kick(dv: float) -> void:
		v += dv

	func update(dt: float, target: float = 0.0) -> float:
		var n := maxi(1, ceili(dt / (1.0 / 90.0)))
		var h := dt / n
		for i in n:
			v += (-k * (x - target) - c * v) * h
			x += v * h
		return x

# ------------------------------------------------------------------------------------------------ screen
# Telly's own CRT compositor (384x288 canvas, DACanvas): face / show cards / snow / Baron / test card plus the effects
# the engine CRT shader has no knobs for (zipper wipe, vertical roll, zoom, CRT collapse to a line and a dot, the
# degauss unfold). Redraws only when its source redraws or an effect runs (<= 30 fps).
static func _newCanvas(w: int, h: int):
	var path := "res://scripts/gfx/canvas2d.gd"
	if not ResourceLoader.exists(path):
		return null
	var C = load(path)
	return C.new(w, h) if C != null else null

# The drawable image of a card: cards.get(id, opts).image in the JS (the canvas behind the CanvasTexture).
static func _cardImage(game_, id: String, opts: Dictionary = {}):
	var cards = _field(game_, "cards")
	if cards == null:
		return null
	var t = _invoke(cards, "get", [id, opts])
	if t == null:
		t = _invoke(cards, "getCard", [id, opts])
	if t is Dictionary:
		return t.get("image", t.get("canvas", t.get("texture")))
	if t is Object and not (t is Texture2D):
		if "image" in t and t.image != null:
			return t.image
		if "canvas" in t and t.canvas != null:
			return t.canvas
	return t

class TellyScreen extends RefCounted:
	var game
	var M                                  # the telly script (static helpers: inner classes cannot call them)
	var canvas
	var ctx
	var texture
	var prev
	var face
	var snow
	var baron
	var noise: Array = []
	var kind := "face"
	var ch = null
	var expr := "zzz"
	var look: Array = [0.0, 0.0]
	var _lookT := 0.0
	var fx := {"zip": -1.0, "roll": -1.0, "zoom": 1.0, "collapse": -1.0, "unfold": -1.0, "flash": 0.0, "noise": 0.0, "dot": 0.0}
	var dirty := true
	var _last := -1.0
	var _srcCanvas = null

	func _init(game_, M_) -> void:
		game = game_
		M = M_
		canvas = M._newCanvas(SW, SH)
		if canvas != null:
			canvas.opaque = true                 # port hints (DACanvas): always fully painted, redrawn while animated
			canvas.bakeMode = "never"
		ctx = canvas.getContext("2d") if canvas != null else null
		texture = canvas.texture if canvas != null else null
		prev = M._newCanvas(SW, SH)
		var cards = game.cards
		face = M._invoke(cards, "animated", ["telly_face", {"owner": "telly", "expr": "zzz", "look": [0, 0]}])
		snow = M._invoke(cards, "animated", ["snow", {"owner": "telly"}])
		baron = M._invoke(cards, "animated", ["baron", {"owner": "telly"}])
		# three 96x72 grey noise tiles (createImageData / putImageData)
		for n in 3:
			var img := Image.create(96, 72, false, Image.FORMAT_RGBA8)
			for y in 72:
				for x in 96:
					var v := 20.0 + randf() * 60.0 if randf() < 0.5 else 150.0 + randf() * 105.0
					img.set_pixel(x, y, Color8(int(v), int(v), mini(255, int(v + 8.0)), 255))
			noise.append(ImageTexture.create_from_image(img))

	# kind: 'face' | 'card' (ch) | 'snow' (ch?) | 'baron' | 'test' | 'black'
	func show(kind_: String, ch_ = null) -> void:
		if kind_ == kind and ch_ == ch:
			return
		kind = kind_
		ch = ch_
		if kind_ == "snow":
			M._invoke(snow, "set", [{"channel": ch_}])
		dirty = true

	func setFace(expr_: String, look_, t: float) -> void:
		var patch = null
		if expr_ != expr:
			expr = expr_
			patch = {"expr": expr_}
		if look_ != null and t - _lookT > 1.0 / 12.0 and (absf(look_[0] - look[0]) > 0.04 or absf(look_[1] - look[1]) > 0.04):
			look = [M.jround(look_[0] * 50.0) / 50.0, M.jround(look_[1] * 50.0) / 50.0]
			_lookT = t
			if patch == null:
				patch = {}
			patch["look"] = look
		if patch != null:
			M._invoke(face, "set", [patch])

	func snapshot() -> void:
		if prev == null:
			return
		var x = prev.getContext("2d")
		x.clearRect(0, 0, SW, SH)
		x.drawImage(canvas, 0, 0)

	func _tick(h, t: float) -> Array:
		if h == null:
			return [null, false]
		return [M._field(h, "canvas"), bool(M._invoke(h, "tick", [t]))]

	func _source(t: float) -> Array:
		match kind:
			"face": return _tick(face, t)
			"snow": return _tick(snow, t)
			"baron": return _tick(baron, t)
			"card": return [M._cardImage(game, "show_%d" % int(ch)), false]
			"test": return [M._cardImage(game, "test_card", {"variant": "sleepy"}), false]
			_: return [null, false]

	func render(t: float) -> bool:
		if ctx == null:
			return false
		var f := fx
		var sr := _source(t)
		var src = sr[0]
		var redrew: bool = sr[1]
		var drt: bool = dirty or redrew or src != _srcCanvas
		var active: bool = f.zip >= 0 or f.roll >= 0 or f.collapse >= 0 or f.unfold >= 0 or f.flash > 0.01 or f.noise > 0.01 \
			or absf(f.zoom - 1.0) > 1e-3 or f.dot > 0.01
		if active and (t - _last >= 1.0 / 30.0 or t < _last):
			drt = true
		if not drt:
			return false
		_last = t
		dirty = false
		_srcCanvas = src
		ctx.globalCompositeOperation = "source-over"
		ctx.globalAlpha = 1.0
		ctx.fillStyle = "#04060a"
		ctx.fillRect(0, 0, SW, SH)
		if f.collapse >= 0:
			_collapse(src, f.collapse)
		elif f.unfold >= 0:
			_unfold(src, f.unfold, t)
		elif f.dot > 0.01:
			_dot(f.dot, 1.0)
		elif src != null:
			_draw(src, f.zoom, f.roll)
			if f.zip >= 0:
				_zip(f.zip)
			if f.noise > 0.01:
				_noise(f.noise)
			if f.flash > 0.01:
				ctx.globalAlpha = f.flash
				ctx.fillStyle = "#F4FBFF"
				ctx.fillRect(0, 0, SW, SH)
				ctx.globalAlpha = 1.0
		return true

	func _draw(src, zoom: float = 1.0, roll: float = -1.0) -> void:
		if roll >= 0:
			var off: float = M.jround(fmod(roll, 1.0) * SH)
			ctx.drawImage(src, 0, off, SW, SH)
			ctx.drawImage(src, 0, off - SH, SW, SH)
			ctx.fillStyle = "#020305"
			ctx.fillRect(0, off - 9, SW, 14)
			return
		var w := SW * zoom
		var h := SH * zoom
		ctx.drawImage(src, (SW - w) / 2.0, (SH - h) / 2.0, w, h)

	func _noise(a: float) -> void:
		ctx.globalAlpha = minf(1.0, a)
		ctx.drawImage(noise[randi() % 3], -randf() * 20.0, -randf() * 20.0, SW + 24, SH + 24)
		ctx.globalAlpha = 1.0

	func _zip(z: float) -> void:
		# the static band sweeps down: new content above it, the old picture below
		var y: float = M.jround(z * (SH + 30)) - 15.0
		ctx.save()
		ctx.beginPath()
		ctx.rect(0, y, SW, SH - y)
		ctx.clip()
		if prev != null:
			ctx.drawImage(prev, 0, 0)
		ctx.restore()
		ctx.drawImage(noise[randi() % 3], 0, 0, 96, 12, 0, y - 16, SW, 32)
		ctx.fillStyle = "rgba(240,252,255,0.9)"
		ctx.fillRect(0, y + 14, SW, 3)

	func _dot(a: float, r: float = 1.0) -> void:
		ctx.globalCompositeOperation = "lighter"
		var g = ctx.createRadialGradient(SW / 2.0, SH / 2.0, 0, SW / 2.0, SH / 2.0, 26.0 * r)
		g.addColorStop(0, "rgba(255,255,255,%s)" % a)
		g.addColorStop(0.25, "rgba(200,245,255,%s)" % (a * 0.8))
		g.addColorStop(1, "rgba(120,220,255,0)")
		ctx.fillStyle = g
		ctx.fillRect(0, 0, SW, SH)
		ctx.globalCompositeOperation = "source-over"

	# CRT power-off: the picture squashes into a bright horizontal line, the line shrinks into a dot.
	func _collapse(src, c: float) -> void:
		if c < 0.5:
			var u := c / 0.5
			var sy: float = M.lerp_(1.0, 0.012, M.easeInCubic(u))
			if src != null:
				ctx.drawImage(src, 0, (SH - SH * sy) / 2.0, SW, SH * sy)
			ctx.globalCompositeOperation = "lighter"
			ctx.globalAlpha = u * 0.85
			ctx.fillStyle = "#E8FAFF"
			ctx.fillRect(0, (SH - SH * sy) / 2.0, SW, SH * sy)
			ctx.globalAlpha = 1.0
			ctx.globalCompositeOperation = "source-over"
		else:
			var u := (c - 0.5) / 0.5
			var lw: float = (SW - 8) * (1.0 - M.easeInCubic(u)) + 8.0
			ctx.save()
			ctx.shadowColor = "#7FE7FF"
			ctx.shadowBlur = 16
			ctx.fillStyle = "#FFFFFF"
			ctx.fillRect((SW - lw) / 2.0, SH / 2.0 - 2.5, lw, 5)
			ctx.restore()
			if u > 0.7:
				_dot((u - 0.7) / 0.3, 0.8)

	# Degauss unfold: dot -> line -> picture, with rainbow fringes and a wobble that settles.
	func _unfold(src, u: float, t: float) -> void:
		if u < 0.2:
			_dot(u / 0.2, 0.3 + u * 3.0)
			return
		if u < 0.42:
			var w: float = SW * M.easeOutCubic((u - 0.2) / 0.22)
			ctx.save()
			ctx.shadowColor = "#7FE7FF"
			ctx.shadowBlur = 14
			ctx.fillStyle = "#FFFFFF"
			ctx.fillRect((SW - w) / 2.0, SH / 2.0 - 2.5, w, 5)
			ctx.restore()
			return
		var k := (u - 0.42) / 0.58
		var sy := maxf(0.02, M.easeOutBack(k, 1.4))
		var h := SH * minf(sy, 1.12)
		if src != null:
			var bands := 12
			var bh := float(SH) / bands
			for i in bands:
				var wob := sin(t * 40.0 + i * 1.3) * 16.0 * (1.0 - k)
				ctx.drawImage(src, 0, i * bh, SW, bh, wob, (SH - h) / 2.0 + (i * h) / bands, SW, h / bands + 1.0)
		ctx.globalCompositeOperation = "lighter"
		ctx.globalAlpha = 0.55 * (1.0 - k)
		var gr = ctx.createLinearGradient(0, 0, SW, SH)
		var cols := ["#FF3B30", "#F4E03A", "#52D24A", "#3FD6E0", "#3A58E4", "#D64FD6"]
		for i in cols.size():
			gr.addColorStop(fmod(i / 5.0 + t * 0.8, 1.0), cols[i])
		ctx.fillStyle = gr
		ctx.fillRect(0, 0, SW, SH)
		ctx.globalAlpha = 1.0
		ctx.globalCompositeOperation = "source-over"
		if k < 0.3:
			_dot(1.0 - k / 0.3, 1.2)

# ------------------------------------------------------------------------------------------------ Telly
var game
var homeId = null
var state := "idle"
var phase := "none"
var pulls := 0
var pullsHere := 0
var pity := 0
var mood := "normal"
var awake := false
var homes := {}
var items := {}
var seq = null
var tapeReel = null
var built := false
var morning := false                 # the Morning Show flag (ending.gd wraps the interactable: 13-point pulls)
var disabled := false                # set by the boss fight (boss.gd)
var _tapeArmed := false
var _clock := 0.0
var _shootable := false
var _freezeAt = null
var _powerAt := -1.0
# MP (see the header)
const MP_GRACE := 0.25               # host-side extension of the offer window (a client's last-moment E still lands)
var tapeHolder := 0                  # peer id of the EE reel carrier (0 = none)
var _seqId := 0                      # host: pull counter sent with net_spin (stale requests are ignored)
var _exclCtx = null                  # host: {owned, teles} of the pull's user while rolling / bumping
var _reqT := -1.0                    # requester: a pull request is pending (s); _reqCost refunded if it expires
var _reqCost := 0
var _freezeWarned := false

# Config.T.telly-derived tables (the JS module constants)
var TT: Dictionary
var COST: int
var CH_ITEM := {}                    # channel (int) -> item id
var ITEM_CH := {}                    # item id -> channel (int)
var ITEMS: Array = []
var SNOW: Array = []
var SPIN := {}
var WINDOW: Array = []
var OFFER := {}

# built parts
var g: Node3D = null                 # the 'telly' prop
var P := {}
var rig := {}
var root: Node3D = null
var pivot: Node3D = null
var screen = null                    # TellyScreen
var scrMat: ShaderMaterial = null
var brightBase := 1.05
var bubble: MeshInstance3D = null
var poses := {}
var glove := {}
var bakedLegs = null
var _legsBaked := false
var earRest := {}
var ears := {}
var squash = null
var hopY := 0.0
var hop = null
var prop := {}
var dial := {}
var zzz: Array = []
var _zzzMat: ShaderMaterial = null
var _zzzT := 0.0
var dotSprite: MeshInstance3D = null
var coin: Node3D = null
var coinFly = null
var glowAnchor = null
var pool = null
var _glowLevel := 0.0
var hum = null
var hullMats := {}
var act = null
var _matCache := {}

# runtime state (JS fields created on the fly)
var _wakeHop := false
var _near := false
var _nearT := 0.0
var _exprTemp = null
var _exprT := 0.0
var _zombieNear := false
var _zT := 0.0
var _smackT := 0.0
var _tinkT := 0.0
var _glitchT := 3.0
var _twitchT := 2.0
var _pd := INF
var _zList: Array = []
var _legs := 0.0
var _shake := 0.0
var _waddlePh = null
var _yawnT = null
var _rollT := 0.0
var _joltT := 0.0
var _joltA := 0.0
var rippleT := 0.0
var _shownItem = null
var _look = null
var _glowCol = null                  # linear Color (THREE.Color semantics)

func _init(game_) -> void:
	game = game_
	TT = Config.T.telly
	COST = int(TT.cost)
	for k in TT.channels:
		CH_ITEM[int(k)] = TT.channels[k]
	for ch in CH_ITEM:
		ITEM_CH[CH_ITEM[ch]] = ch
	ITEMS = TT.weights.keys()
	SNOW = TT.snow.map(func(x): return int(x))
	var spinTime := float(TT.spinTime)
	# Detent intervals ease 0.07 -> 0.50 s over ~20 detents, first at 0.30, last at 4.30.
	SPIN = {"t0": 0.30, "dur": spinTime - 0.30, "iMin": 0.07, "iMax": 0.50, "pow": 2.6, "want": 20, "snowFlash": 0.06, "zip": 0.15}
	WINDOW = [spinTime - float(TT.bumpWindow), spinTime]      # percussive maintenance [3.30, 4.30)
	OFFER = {"out": 0.34, "drum": 6.0, "wag": 8.0, "window": float(TT.window), "tapeDrum": 4.0}

# ============================================================================================ build
func init() -> void:
	var gm = game
	var lv = gm.level
	var anchors = _field(lv, "anchors")
	if not (anchors is Dictionary) or not TELLY_HOMES.any(func(id): return anchors.get(id) != null):
		return
	_shootable = _hasm(gm.weapons, "registerShootable")
	_buildHomes()
	if not _buildTelly():
		return
	_buildItems()
	_register()
	_listen()
	built = true
	var objs = _field(lv, "objects")
	if objs is Dictionary:
		objs["machine_telly"] = {"group": root, "parts": P, "telly": self}

func _col():
	return _field(game.level, "col")

func _place(parent: Node, id: String, o: Dictionary) -> Node3D:
	var n = _invoke(game.props, "place", [parent, id, o])
	if n is Node3D:
		return n
	# no prop library yet: an empty stand-in keeps the machine logic running
	var s := DAU.node3d("prop:" + id)
	var p := DAU.v3(o.get("pos", [0, 0, 0]))
	s.position = p
	s.rotation.y = float(o.get("rotY", 0.0))
	parent.add_child(s)
	return s

# col.raycast(o, d, max, opts) -> hit {dist, point, ...} | null
func _raycastCol(o: Vector3, d: Vector3, mx: float, opts = null):
	var col = _col()
	if col == null:
		return null
	return _invoke(col, "raycast", [o, d, mx, opts] if opts != null else [o, d, mx])

func _buildHomes() -> void:
	var gm = game
	var lv = gm.level
	var anchors: Dictionary = _field(lv, "anchors", {})
	var areaRoots = _field(lv, "areaRoots")
	for id in TELLY_HOMES:
		var a = anchors.get(id)
		if a == null:
			continue
		var area = _field(a, "area")
		var parent: Node = areaRoots.get(area) if areaRoots is Dictionary and areaRoots.get(area) is Node else gm.scene
		var grp := DAU.node3d("telly_home:" + id)
		parent.add_child(grp)
		var rotY := _num(_field(a, "rotY"), 0.0)
		var apos := DAU.v3(_field(a, "pos"))
		var fwd := Vector3(-sin(rotY), 0, -cos(rotY))
		var lampA = _field(a, "lamp")
		var lpos = _field(lampA, "pos")
		var lp: Array = DAU.arr3(DAU.v3(lpos)) if lpos != null else [apos.x + fwd.z * 1.2, 0.0, apos.z - fwd.x * 1.2]
		var fit := _fitHome(apos, rotY, lp)
		var pos: Vector3 = fit.pos
		var couch = _field(a, "couch")
		if couch != null:
			var crot = _field(couch, "rotY")
			_place(grp, "couch_avocado", {"pos": DAU.arr3(DAU.v3(_field(couch, "pos"))), "rotY": float(crot) if crot != null else rotY + PI, "area": area})
		var rug := _place(grp, "telly_rug", {"pos": [pos.x, pos.y, pos.z], "rotY": rotY, "area": area, "colliders": false})
		var lampId: String = "telly_lamp_" + id
		var lpf: Array = fit.lamp
		var lamp := _place(grp, "telly_lamp", {"pos": lpf, "rotY": rotY + 0.5, "area": area, "opts": {"anchorId": lampId, "level": 1}})
		# warm pool of light on the floor under the lit lamp (off = intensity 0)
		var lpool = _invoke(gm.fx, "lightPool", [Vector3(lamp.position.x, 0.02, lamp.position.z), 1.7, "#FFD08A", 0.0])
		# the unplugged cord runs from the wall outlet behind Telly into the room, beside the footprint
		var back := -fwd
		var hit = _raycastCol(Vector3(pos.x, 0.3, pos.z), back, 3.0)
		var wallD: float = _num(_field(hit, "dist"), 0.75) if hit != null else 0.75
		var side := Vector3(-fwd.z, 0, fwd.x)
		var cp := pos + back * (wallD - 0.01) + side * 0.55
		var cord := _place(grp, "telly_cord", {"pos": [cp.x, 0.0, cp.z], "rotY": rotY, "area": area, "colliders": false})
		# flat floor dressing casts no shadow (saves the shadow-pass draws)
		for flat in [rug, cord]:
			_noShadow(flat)
		# the clean footprint left in the dust matches the (scaled) cabinet's feet
		var dust = _partsGeneric(rug, ["dust"]).get("dust")
		if dust is Node3D:
			(dust as Node3D).scale = Vector3(SCALE, 1.0, SCALE)
		else:
			dust = null
		# Telly's collision box at this home (enabled only where it lives)
		var colId: String = "telly_col_" + id
		var bb := AABB()
		for i in 8:
			var v := Vector3(BOX.x if i & 1 else -BOX.x, BOX.y1 if i & 2 else BOX.y0, BOX.z if i & 4 else -BOX.z) * SCALE
			v = v.rotated(Vector3.UP, rotY) + pos
			bb = AABB(v, Vector3.ZERO) if i == 0 else bb.expand(v)
		var col = _col()
		_invoke(col, "addBox", [DAU.arr3(bb.position), DAU.arr3(bb.end), {"tag": "telly", "id": colId, "walkable": false, "shots": not _shootable}])
		_invoke(col, "setEnabled", [colId, false])
		homes[id] = {
			"id": id, "area": area, "group": grp, "pos": pos, "rotY": rotY, "fwd": fwd, "rug": rug, "dust": dust,
			"lamp": lamp, "lampId": lampId, "cord": cord, "colId": colId, "pool": lpool,
			"lampMode": "off", "lampShown": "", "flick": 0.0,
		}

# The lamp stands beside Telly; its bell shade (y 1.29-1.72) hangs at the height of the cabinet's lid, which is taller
# and wider once Telly is SCALE bigger. When the shade would touch the cabinet, first ease the lamp straight out
# sideways (along Telly's width) just enough; if a wall leaves no room for that (a lamp tucked in a corner), Telly's
# spot (and its rug, cord and collider with it) slides the other way instead. Returns { pos, lamp }.
func _fitHome(pos: Vector3, rotY: float, lp: Array) -> Dictionary:
	var C := LAMP_CLEAR
	var col = _col()
	var out := {"pos": pos, "lamp": lp}
	if C.shadeY0 >= C.top * SCALE:
		return out
	var rx := cos(rotY)
	var rz := -sin(rotY)                        # Telly's +x (width) in world
	var bx := sin(rotY)
	var bz := cos(rotY)                         # Telly's +z (back) in world
	var dx: float = float(lp[0]) - pos.x
	var dz: float = float(lp[2]) - pos.z
	var lat := dx * rx + dz * rz
	var dep := dx * bx + dz * bz
	var hw: float = C.hw * SCALE
	var hd: float = C.hd * SCALE
	var need: float = C.shadeR + C.gap
	var gapDep := maxf(0.0, absf(dep) - hd)
	if gapDep >= need:
		return out
	var push := hw + sqrt(need * need - gapDep * gapDep) - absf(lat)
	if push <= 0.0:
		return out
	var s := signf(lat)
	if s == 0.0:
		s = 1.0
	# free distance from (x, z) along ±width, 0.3-1.5 m up
	var room := func(x: float, z: float, dirSign: float, reach: float) -> float:
		if col == null:
			return INF
		var free := INF
		for y in [0.3, 1.5]:
			var hit = _invoke(col, "raycast", [Vector3(x, y, z), Vector3(rx * dirSign, 0, rz * dirSign), reach + 0.3, {"ignoreTags": ["telly"]}])
			if hit != null:
				free = minf(free, _num(_field(hit, "dist"), INF))
		return free
	var moved: Array = [float(lp[0]) + rx * s * push, float(lp[1]) if lp.size() > 1 and lp[1] != null else 0.0, float(lp[2]) + rz * s * push]
	if room.call(moved[0], moved[2], s, C.shadeR) >= C.shadeR + 0.02:
		out.lamp = moved
		return out
	# no room for the lamp: slide Telly away from it, if the other side has the room
	if room.call(pos.x, pos.z, -s, hw + push) >= hw + push + 0.05:
		out.pos = pos + Vector3(rx, 0, rz) * (-s * push)
	return out

func _buildTelly() -> bool:
	var gm = game
	var t = _invoke(gm.props, "build", ["telly", {"card": "telly_face", "expr": "zzz", "channel": 13, "pose": "hidden"}])
	if not (t is Node3D):
		push_error("[telly] prop 'telly' unavailable")
		return false
	g = t
	_xyz(g)
	P = partsOf(t)
	rig = DAU.ud(t).get("rig", {}) if DAU.ud(t).get("rig") is Dictionary else {}
	if not rig.has("screen"):
		rig["screen"] = {"w": 0.8, "h": 0.6, "center": [0.12, 0.55, -0.105], "bulgeMax": 0.35}
	root = DAU.node3d("machine_telly")
	root.scale = Vector3.ONE * SCALE              # about the floor origin: the feet stay on the floor
	pivot = DAU.node3d("telly_pivot")
	pivot.position = PIV
	root.add_child(pivot)
	_reparent(pivot, t)
	t.position = -PIV
	gm.scene.add_child(root)

	# screen: registered with the ScreenManager (scr_telly is never overridden) but composited here
	screen = TellyScreen.new(gm, get_script())
	var sm := P.screen as MeshInstance3D
	if sm != null:
		var m0: Material = sm.material_override
		if m0 == null and sm.mesh != null and sm.mesh.get_surface_count() > 0:
			m0 = sm.get_surface_override_material(0) if sm.get_surface_override_material(0) != null else sm.mesh.surface_get_material(0)
		if m0 is ShaderMaterial:
			# mats.screen() materials are never cached (one per CRT); a plain ShaderMaterial is made unique here
			scrMat = m0 if m0.has_method("setParam") else (m0 as ShaderMaterial).duplicate()
			sm.material_override = scrMat
	if scrMat != null:
		if screen.texture != null:
			if "map" in scrMat:
				scrMat.map = screen.texture                 # DAMaterial: tScreen + uFlip + uTexel
			else:
				scrMat.set_shader_parameter("tScreen", screen.texture)
		_setU(scrMat, "uTexel", Vector2(1.0 / SW, 1.0 / SH))
		scrMat.set_meta("pinnedMap", screen.texture)       # JS: mat.map is pinned to Telly's own texture
		var b0 = _getU(scrMat, "uBright")
		brightBase = float(b0) if b0 != null else 1.05
	_invoke(gm.screens, "register", [P.screen, "scr_telly", {"id": "telly"}])

	# soap-bubble membrane in front of the glass
	var scr: Dictionary = rig.screen
	var bw := float(scr.w) + 0.02
	var bh := float(scr.h) + 0.02
	bubble = MeshInstance3D.new()
	bubble.name = "telly_bubble"
	bubble.rotation_order = EULER_ORDER_XYZ
	var geo = _invoke(gm.mats, "screenGeometry", [bw, bh])
	if not (geo is Mesh):
		var pm := PlaneMesh.new()                         # plane(w, h, 24, 18) facing +z
		pm.orientation = PlaneMesh.FACE_Z
		pm.size = Vector2(bw, bh)
		pm.subdivide_width = 23
		pm.subdivide_depth = 17
		geo = pm
	bubble.mesh = geo
	bubble.material_override = bubbleMaterial(bw, bh)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.rotation.y = PI
	var gz: float = (P.glass as Node3D).position.z if P.glass is Node3D else -0.314
	bubble.position = Vector3(float(scr.center[0]), float(scr.center[1]), gz - 0.004)
	bubble.visible = false
	bubble.extra_cull_margin = 2.0                    # frustumCulled = false
	(P.body as Node3D).add_child(bubble)

	# glove poses (captured from the prop's preview poses) + custom ones
	var F: Dictionary = P.gloveFingers
	var cap := func() -> Dictionary:
		return {"pos": (P.glove as Node3D).position, "quat": (P.glove as Node3D).quaternion, "ctrl": (P.armCtrl as Node3D).position,
			"f": [F.index.rotation.x, F.middle.rotation.x, F.pinky.rotation.x, F.thumb.rotation.x]}
	var ps := {}
	for name in ["present", "fingerguns", "wag"]:
		setTellyGlove(t, name)
		if name == "present":
			_aimPresent(t)
		ps[name] = cap.call()
	setTellyGlove(t, "hidden")
	var hid: Dictionary = cap.call()
	hid.f = (ps.present.f as Array).duplicate()
	ps["hidden"] = hid
	var basis := func(x: Array, y: Array, z: Array) -> Quaternion:
		return Basis(DAU.v3(x), DAU.v3(y), DAU.v3(z)).get_rotation_quaternion()
	var P0: Dictionary = ps.present
	ps["reach"] = {"pos": Vector3(0.0, -0.05, -0.34), "quat": P0.quat, "ctrl": Vector3(0, -0.06, -0.16), "f": (P0.f as Array).duplicate()}
	ps["wave"] = {"pos": Vector3(0.02, 0.1, -0.46), "quat": Quaternion.IDENTITY, "ctrl": Vector3(0.02, -0.12, -0.22), "f": [0.08, 0.08, 0.08, -0.25]}
	ps["shrug"] = {"pos": Vector3(0.0, 0.02, -0.5), "quat": P0.quat, "ctrl": Vector3(0.04, -0.14, -0.25), "f": [0.05, 0.05, 0.05, -0.1]}
	ps["coin"] = {"pos": Vector3(0.04, -0.02, -0.5), "quat": P0.quat, "ctrl": Vector3(0.04, -0.14, -0.25), "f": [-1.0, -1.1, -1.2, -0.2]}
	ps["bop"] = {"pos": Vector3(0.0, -0.08, -1.3), "quat": basis.call([1, 0, 0], [0, 0, -1], [0, 1, 0]), "ctrl": Vector3(0.0, 0.1, -0.6), "f": [-1.9, -2.0, -2.0, -1.3]}
	ps["catch"] = {"pos": Vector3(0.0, 0.0, -0.8), "quat": Quaternion.IDENTITY, "ctrl": Vector3(0.0, -0.1, -0.4), "f": [-1.2, -1.3, -1.3, -0.9]}
	poses = ps
	glove = {"from": ps.hidden, "to": ps.hidden, "t": 1.0, "dur": 0.3, "ease": easeOutBack, "on": false,
		"wave": 0, "wag": 0, "drum": -1.0, "shake": 0, "flick": -1.0, "hold": null, "shrug": 0, "name": "hidden"}
	_showGlove(false)

	# animated rest values (the JS static bake of legs + cord is draw-call plumbing: not ported)
	bakedLegs = null
	_legsBaked = false
	for ear in [P.earL, P.earR]:
		if ear is Node:
			_noShadow(ear)                           # thin antenna rods cast no shadow
	earRest = {"L": (P.earL as Node3D).rotation, "R": (P.earR as Node3D).rotation}
	ears = {"L": Spring.new(180, 7), "R": Spring.new(180, 7), "droop": 0.0, "droopT": 0.0, "dCur": 0.0}
	squash = Spring.new(320, 13, 1)
	hopY = 0.0
	hop = null
	prop = {"spin": 0.0, "angle": 0.0, "settle": null}
	var dz: float = (P.dial as Node3D).rotation.z
	dial = {"idx": DIAL_ORDER.find(13), "angle": dz, "from": dz, "to": dz, "t": 1.0, "dur": 0.0}

	# Zzz particles, afterglow dot, refund coin
	_zzzMat = spriteMaterial(_tex("zzz.png"), "#DFFBFF")
	zzz = []
	for i in 3:
		var s := spriteNode(_zzzMat, "telly_zzz%d" % i)
		s.visible = false
		DAU.ud(s)["life"] = -1.0
		DAU.ud(s)["x"] = 0.0
		root.add_child(s)
		zzz.append(s)
	_zzzT = 0.0
	var dm := spriteMaterial(_tex("dot.png"), "#ffffff", true)
	dm.render_priority = 5                          # renderOrder 5
	dotSprite = spriteNode(dm, "telly_dot")
	dotSprite.visible = false
	gm.scene.add_child(dotSprite)
	coin = DAU.node3d("telly_coin")
	var cm := _loadRuntime(gm, "telly_coin.glb")
	if cm != null:
		var coinMat = _invoke(gm.mats, "toon", ["#E8B84A", {"rough": 0.25, "metal": 0.85, "keepColor": true, "emissive": "#6A4A10", "emissiveIntensity": 0.4}])
		if coinMat is Material:
			for m in _meshes(cm):
				(m as MeshInstance3D).material_override = coinMat
		coin.add_child(cm)
	coin.scale = Vector3.ONE * SCALE                # world-space prop held by the (scaled) glove
	coin.visible = false
	gm.scene.add_child(coin)
	coinFly = null

	# CRT glow: pooled light anchor in front of the screen + a floor light pool
	glowAnchor = _invoke(gm.lights, "addAnchor", [{"pos": [0, -50, 0], "color": GLOW_CRT, "intensity": 0.0, "distance": 3.2 * SCALE, "id": "telly_screen"}])
	pool = _invoke(gm.fx, "lightPool", [Vector3(0, -50, 0), 1.2 * SCALE, GLOW_CRT, 0.0])
	_glowLevel = 0.0

	# positional hum
	hum = _invoke(gm.audio, "loop", ["telly_hum", {"pos": Vector3(0, -50, 0), "vol": 0.0}])
	return true

# Moves the 'present' glove pose so the presented item floats exactly where GDD §10.2 puts it: 0.8 m in front of the
# screen at 1.2 m height (rig.glove.presentWorld, prop space, legs at rest). The item rides ITEM_LIFT above the
# glove's hold point. The arm control point follows so the tube keeps its curve.
func _aimPresent(t: Node3D) -> void:
	var want: Array = []
	var gr = rig.get("glove")
	if gr is Dictionary and gr.get("presentWorld") is Array:
		want = gr.presentWorld
	else:
		want = [float(rig.screen.center[0]), 1.2, -1.1]
	var hold := _gxf(P.gloveHold).origin
	var target := _gxf(t) * Vector3(float(want[0]), float(want[1]) - ITEM_LIFT, float(want[2]))
	var inv := _gxf(P.armRig).affine_inverse()
	var d := (inv * target) - (inv * hold)
	(P.glove as Node3D).position += d
	(P.armCtrl as Node3D).position += d * 0.5
	updateTellyArm(t)

# Display models of every item (props 'wall' pose: right side toward -z, barrel toward -x) + the EE reel.
func _buildItems() -> void:
	var gm = game
	var hn := hullMaterial()
	var hw := hullMaterial()
	hw.set_shader_parameter("uRainbow", 1.0)
	hw.set_shader_parameter("uGlow", 1.45)
	hullMats = {"normal": hn, "wonder": hw}
	for id in ITEMS + [TAPE_ID]:
		var model = buildTapeReel(gm) if id == TAPE_ID else _invoke(gm.props, "build", [id, {"pose": "wall"}])
		if not (model is Node3D):
			push_warning("[telly] item model %s failed" % id)
			continue
		items[id] = _wrapItem(id, model)

func _wrapItem(id: String, model: Node3D) -> Dictionary:
	var wrap := DAU.node3d("telly_item:" + id)
	var inner := DAU.node3d("telly_item_inner")
	wrap.add_child(inner)
	inner.add_child(model)
	# Box3.setFromObject: each mesh's local bounds through its transform, in the wrap's frame
	var bb := AABB()
	var first := true
	var wi := _gxf(wrap).affine_inverse()
	for m in _meshes(model):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := (wi * _gxf(mi)) * mi.get_aabb()
		bb = box if first else bb.merge(box)
		first = false
	var size := bb.size
	var c := bb.get_center()
	model.position -= c
	var sIn := minf(minf(0.6 / maxf(size.x, 1e-6), 0.34 / maxf(size.y, 1e-6)), minf(0.17 / maxf(size.z, 1e-3), 1.7))
	# the EE reel is presented at its real 0.36 m size (GDD §13 step 5: undo Telly's SCALE); weapons are blown up to
	# read at 2 m (and grow with Telly)
	var sOut := 1.0 / SCALE if id == TAPE_ID else minf(minf(0.82 / maxf(size.x, 1e-6), 0.5 / maxf(size.y, 1e-6)), 1.5)
	var wonder := WONDER.has(id) or id == TAPE_ID
	# collect first, then add: adding the hull inside the traversal would visit it
	var targets: Array = []
	for m in _meshes(model):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.skin != null or mi.mesh == null or _isTransparent(mi):
			continue
		targets.append(mi)
	# ONE outline hull for the whole display model
	var hulls: Array = []
	var hullGeo := mergedHullGeometry(targets, inner)
	if hullGeo != null:
		var h := MeshInstance3D.new()
		h.name = "telly_hull"
		h.mesh = hullGeo
		h.material_override = hullMats.wonder if wonder else hullMats.normal
		h.visible = false
		h.extra_cull_margin = 2.0
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		DAU.ud(h)["hull"] = true
		inner.add_child(h)
		hulls.append(h)
	wrap.visible = false
	(P.weaponSlot as Node3D).add_child(wrap)
	return {"id": id, "wrap": wrap, "inner": inner, "model": model, "size": size, "sIn": sIn, "sOut": sOut, "wonder": wonder,
		"hulls": hulls, "mode": "in", "pop": 0.0, "rot0": 0.0, "holdFrom": Vector3.ZERO, "holdT": 0.0, "flyT": 0.0,
		"flyFrom": Vector3.ZERO, "flyScale": 1.0}

# material.transparent of the mesh (its surfaces' materials)
static func _isTransparent(mi: MeshInstance3D) -> bool:
	var mats: Array = []
	if mi.material_override != null:
		mats.append(mi.material_override)
	else:
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			mats.append(m if m != null else mi.mesh.surface_get_material(i))
	for m in mats:
		if m == null:
			continue
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
		if m.has_meta("transparent") and m.get_meta("transparent"):
			return true
		var spec = m.get_meta("da", null) if m.has_meta("da") else null
		if spec is Dictionary and spec.get("opts") is Dictionary and spec.opts.get("transparent"):
			return true
	return false

func _register() -> void:
	var gm = game
	act = _invoke(gm.interact, "register", [{
		"id": "machine_telly", "pos": Vector3(0, 0.9, 0), "radius": 1.7 * SCALE,
		"enabled": func() -> bool: return built and homeId != null and root.visible,
		"prompt": func(): return _prompt(),
		"use": func(): _use(),
	}])
	_registerShootable()

func _registerShootable() -> void:
	var w = game.weapons
	if not _hasm(w, "registerShootable"):
		_shootable = false
		return
	_invoke(w, "unregisterShootable", ["machine_telly"])
	_invoke(w, "registerShootable", [{
		"id": "machine_telly", "blocksBullet": true, "melee": true, "bullets": true,
		"raycast": func(o, d, mx = INF): return _raycast(o, d, mx),
		"onHit": func(info = null): onHit(info if info is Dictionary else {}),
	}])
	_shootable = true

func _listen() -> void:
	var ev = game.events
	ev.on("power:on", func(_e): _powerAt = _clock)
	ev.on("egg:step", func(e):
		if e is Dictionary and e.get("step") == 4:
			setMood("purple")
			forceTapePull())
	# fallback hit tests while the weapons system has no shootables
	ev.on("weapon:melee", func(_e):
		if not _shootable and _meleeReaches():
			onHit({"melee": true}))
	ev.on("weapon:fire", func(_e):
		if not _shootable:
			_fallbackBullet())

# ============================================================================================ lifecycle
func reset() -> void:
	if not built:
		return
	var gm = game
	_registerShootable()
	_endSeq(true)
	pulls = 0
	pullsHere = 0
	pity = 0
	_tapeArmed = false
	_freezeAt = null
	tapeHolder = 0
	_exclCtx = null
	_reqT = -1.0
	mood = "normal"
	awake = false
	_wakeHop = false
	_powerAt = -1.0
	_near = false
	_nearT = 0.0
	_exprTemp = null
	_exprT = 0.0
	_zombieNear = false
	_zT = 0.0
	_smackT = 0.0
	_tinkT = 0.0
	_glitchT = 3.0
	_twitchT = 2.0
	if tapeReel != null:
		if is_instance_valid(tapeReel):
			DAU.detach(tapeReel)
		tapeReel = null
	if items.get(TAPE_ID) == null:
		var reel := buildTapeReel(gm)
		if reel != null:
			items[TAPE_ID] = _wrapItem(TAPE_ID, reel)
		else:
			push_warning("[telly] tape reel unavailable")
	var start := "telly_home_green" if gm.rand() < 0.5 else "telly_home_newsroom"
	_placeAt(start if homes.has(start) else homes.keys()[0])
	for h in homes.values():
		h.lampMode = "dim" if h.id == homeId else "off"
	_applyLamps(true)
	phase = "asleep"
	state = "idle"
	if _field(gm.nav, "built"):
		_invoke(gm.nav, "build")

func update(dt: float) -> void:
	if not built:
		return
	_clock += dt
	var t := _clock
	if _reqT >= 0.0:
		_updateReq(dt)
	_updatePower(dt)
	_updateProximity(dt)
	if seq != null:
		_updateSeq(dt)
	else:
		_updateIdle(dt)
	_animate(dt, t)
	_updateGlove(dt)
	_updateItem(dt, t)
	_updateScreen(dt, t)
	_updateZzz(dt, t)
	_updateLamps(dt, t)
	_updateCoin(dt)
	_updateAnchors(dt)
	_updateShaderTime()
	if seq == null:
		state = "idle"
	else:
		var ph: String = seq.phase
		if ph == "spin" or ph == "land" or ph == "bulge":
			state = "spinning"
		elif ph == "offer" or ph == "take" or ph == "timeout":
			state = "offer"
		elif ph == "bad":
			state = "spinning"
		else:
			state = "moving"

# the JS ShaderMaterials share mats.uniforms.uTime (= game.time.realNow)
func _updateShaderTime() -> void:
	var tn: float = _num(game.time.get("realNow"), 0.0)
	if bubble != null and bubble.visible:
		(bubble.material_override as ShaderMaterial).set_shader_parameter("uTime", tn)
	for k in hullMats:
		(hullMats[k] as ShaderMaterial).set_shader_parameter("uTime", tn)

# ============================================================================================ power / wake
func _updatePower(_dt: float = 0.0) -> void:
	var on := bool(_field(game.machines, "powerOn", false))
	if not on:
		if awake and seq == null:
			awake = false
			phase = "asleep"
			_lampModeHome("dim")
		return
	if awake or homeId == null:
		return
	if _waveReached():
		awake = true
		phase = "idle"
		_lampModeHome("purple" if mood == "purple" else "full", true)
		_hopNow(0.16)
		_play("telly_wake", {"vol": 1.1})
		_tempExpr("happy", 1.1)
		_near = true
		_nearT = 0.0

# mats.uniforms.<name>.value (Dictionary {value} / object .value / plain value)
func _mu(name: String):
	var U = _field(game.mats, "uniforms")
	var u = U.get(name) if U is Dictionary else (_field(U, name) if U is Object else null)
	if u is Dictionary:
		return u.get("value")
	if u is Object and "value" in u:
		return u.value
	return u

func _waveReached() -> bool:
	var gm = game
	var pos: Vector3 = homes[homeId].pos
	if _hasm(gm.signon, "waveReached"):
		return bool(_invoke(gm.signon, "waveReached", [pos]))
	var wr = _mu("uWaveRadius")
	if (wr is float or wr is int) and wr >= 0:
		var wo = _mu("uWaveOrigin")
		return pos.distance_to(DAU.v3(wo)) <= float(wr)
	if _powerAt < 0:
		return true                                # power already on (power=1, debug)
	var lever = _field(_field(_field(gm.level, "anchors"), "sign_on_lever"), "pos")
	return lever == null or _clock - _powerAt >= pos.distance_to(DAU.v3(lever)) / 15.0 - 0.05 or _clock - _powerAt > 3.5

func _updateProximity(dt: float) -> void:
	var p = game.player
	if homeId == null or p == null:
		_pd = INF
		return
	var pp := DAU.v3(_field(p, "pos"))
	_pd = Vector2(pp.x - root.position.x, pp.z - root.position.z).length()
	_zT -= dt
	if _zT <= 0.0:
		_zT = 0.25
		var near := false
		var z = game.zombies
		if _hasm(z, "inRadius"):
			var r = _invoke(z, "inRadius", [root.position, ZOMBIE_NEAR, _zList])
			near = (r is Array and not (r as Array).is_empty()) or not _zList.is_empty()
		_zList.clear()
		_zombieNear = near

# idle life: doze / wake hops, antenna twitches, purple glitches
func _updateIdle(dt: float) -> void:
	if homeId == null:
		return
	_twitchT -= dt
	if _twitchT <= 0.0:
		_twitchT = 3.0 + randf() * 3.0
		var s: Spring = ears.L if randf() < 0.5 else ears.R
		s.kick((-1.0 if randf() < 0.5 else 1.0) * (5.0 if awake else 2.5))
	if not awake:
		return
	var near := _pd < (NEAR_DOZE if _near else NEAR_WAKE)
	if near:
		_nearT = 0.0
		if not _near:
			_near = true
			_hopNow(0.12)
			_play("telly_wake")
			_tempExpr("happy", 0.7)
	elif _near:
		_nearT += dt
		if _nearT > 1.5:
			_near = false
			_tempExpr("sleepy", 1.8)
	if mood == "purple":
		_glitchT -= dt
		if _glitchT <= 0.0:
			_glitchT = 4.0 + randf() * 2.0
			_tempExpr("baron_glitch", 0.3)

# ============================================================================================ interaction
func _prompt():
	if homeId == null or not root.visible:
		return null
	var s = seq
	if s == null:
		if not _field(game.machines, "powerOn", false) or not awake:
			return {"plug": true}
		if _reqT >= 0.0:
			return null
		return {"cost": COST}
	if s.phase == "offer" and s.u > OFFER.out * 0.6:
		return {} if not _mp() or (int(s.by) == _me() and not s.orphan) else null
	return null

func _use() -> void:
	var s = seq
	if s != null:
		if s.phase == "offer":
			take()
		return
	if not _field(game.machines, "powerOn", false) or not awake:
		# asleep: a mumble and a wriggle, nothing else
		_play("telly_nuh_uh", {"vol": 0.55, "rate": 0.8})
		squash.kick(-1.2)
		return
	pull()

func canPull() -> bool:
	return built and homeId != null and seq == null and awake and bool(_field(game.machines, "powerOn", false)) and root.visible

# opts: { free = false, forced = null }
func pull(opts = {}) -> bool:
	if _mp():
		return _pullMP(opts)
	if not canPull():
		return false
	var o: Dictionary = opts if opts is Dictionary else {}
	var free: bool = bool(o.get("free", false))
	var forced = o.get("forced")
	var gm = game
	if not free:
		var eco = gm.economy
		if eco == null or not _invoke(eco, "spend", [COST, "telly"]):
			squash.kick(-2)
			_tempExpr("pout", 0.8)
			return false
	pulls += 1
	pullsHere += 1
	var r := _roll(forced)
	return _beginSpin(r, _dialCh(), -2, 0 if free else COST, 0)

# Builds the pull sequence from a resolved roll r {outcome, item, ch} with the dial on `start` (solo: pull(); MP:
# net_spin on every peer). cameo -2 = roll it here (randf, as the solo order); by = the user's peer id (0 = local).
func _beginSpin(r: Dictionary, start: int, cameo: int, cost: int, by: int) -> bool:
	var gm = game
	var cycle: Array = CYCLE_EE if r.outcome == "tape" else CYCLE
	var L := cycle.size()
	var startPos := cycle.find(start)
	if startPos < 0:
		startPos = cycle.find(13)
	var targetPos := cycle.find(r.ch)
	var off := posmod(targetPos - startPos, L)
	var n1 := off + L
	var n2 := off + 2 * L
	var want: int = SPIN.want
	var N := n2 if absi(n2 - want) < absi(n1 - want) else n1
	var iv: Array = []
	var sum := 0.0
	for j in N - 1:
		var i: float = SPIN.iMin + (SPIN.iMax - SPIN.iMin) * pow(float(j) / maxi(1, N - 2), SPIN.pow)
		iv.append(i)
		sum += i
	var times: Array = [SPIN.t0]
	for j in N - 1:
		times.append(times[j] + (iv[j] * SPIN.dur) / sum)
	if cameo == -2:
		cameo = -1
		if r.outcome != "tape" and randf() < float(TT.cameo):
			cameo = 6 + int(floor(randf() * maxi(1, N - 12)))
	seq = {
		"phase": "spin", "t": 0.0, "prev": -1.0, "u": -1e-6, "pu": -1.0,
		"outcome": r.outcome, "item": r.item, "ch": r.ch, "orig": r.duplicate(),
		"cost": cost, "cycle": cycle, "startPos": startPos, "N": N, "times": times, "passed": 0, "shift": 0,
		"landT": times[times.size() - 1],
		"bumped": false, "cameo": cameo,
		"shownCh": start, "detT": -1.0, "offerT": -1.0, "took": false, "drum": false, "wag": false, "refunded": false,
		"dest": null, "walk": null, "arp": null, "lastDetentCh": start,
		# fields the JS adds on the fly
		"detIdx": 0, "cameoNow": false, "bopT": 0.0, "catchT": 0.0, "drumK": -1, "yawnT": null, "walkDone": false,
		# MP: user peer, host pull id, the user's exclusions, the host's landing, orphaned (user down / gone)
		"by": by, "id": 0, "excl": null, "landMsg": null, "orphan": false, "holdT": 0.0,
	}
	phase = "spin"
	gm.events.emit("machine:telly_spin", {"homeId": homeId})
	return true

func _snowCh() -> int:
	return int(SNOW[int(floor(game.rand() * SNOW.size())) % SNOW.size()])

# Result first (GDD §10.2): tape > sign-off > weighted item (exclusions, pity).
func _roll(forced) -> Dictionary:
	var gm = game
	if _tapeArmed or forced == "tape":
		_tapeArmed = false
		return {"outcome": "tape", "item": TAPE_ID, "ch": 0}
	if forced == "signoff" and canMove():
		return {"outcome": "signoff", "item": null, "ch": _snowCh()}
	if forced == "bad":
		return {"outcome": "bad", "item": null, "ch": _snowCh()}
	if forced != null and ITEM_CH.has(forced):
		return {"outcome": "item", "item": forced, "ch": int(ITEM_CH[forced])}
	var n := pullsHere
	if (forced == null or forced == "") and n > int(TT.moveSafe) and canMove():
		var p := minf(float(TT.moveBase) + float(TT.moveStep) * (n - (int(TT.moveSafe) + 1)), float(TT.moveCap))
		if gm.rand() < p:
			return {"outcome": "signoff", "item": null, "ch": _snowCh()}
	var pityOn := pity >= int(TT.pity)
	var total := 0.0
	var pl: Array = []
	for id in ITEMS:
		if _excluded(id):
			continue
		var w: float = float(TT.weights[id]) * (float(TT.pityMul) if pityOn and WONDER.has(id) else 1.0)
		pl.append([id, w])
		total += w
	var x: float = gm.rand() * total
	var pick: String = pl[pl.size() - 1][0] if not pl.is_empty() else "revolver_38"
	for e in pl:
		x -= e[1]
		if x < 0.0:
			pick = e[0]
			break
	return {"outcome": "item", "item": pick, "ch": int(ITEM_CH[pick])}

func _excluded(id) -> bool:
	if _exclCtx != null and id != null and id != "":
		if id == "tiny_tele":
			return float(_exclCtx.teles) >= float(Config.T.player.teleMax)
		return (_exclCtx.owned as Array).has(id)
	var w = game.weapons
	if w == null or id == null or id == "":
		return false
	if id == "tiny_tele":
		return _num(_field(w, "teles", 0), 0.0) >= float(Config.T.player.teleMax)
	if _hasm(w, "has") and _invoke(w, "has", [id]):
		return true
	var slots = _field(w, "slots")
	if slots is Array:
		for s in slots:
			if s != null and _field(s, "id") == id:
				return true
	return false

func canMove() -> bool:
	return bool(_pickDestination(true))

func _areaOpen(areaId) -> bool:
	var lv = game.level
	if areaId == "lobby" or _field(game.player, "area") == areaId:
		return true
	if _mp():
		for pl in game.net.players():
			if pl != null and pl.alive and not pl.get("offAir") and pl.area == areaId:
				return true
	var areas = _field(lv, "areas")
	var a = areas.get(areaId) if areas is Dictionary else null
	var doors = _field(lv, "doors")
	var ids = _field(a, "doors")
	if not (ids is Array) or not (doors is Dictionary):
		return false
	for d in ids:
		if _field(doors.get(d), "open", false):
			return true
	return false

func _pickDestination(check: bool = false):
	var opts: Array = []
	for id in homes:
		if id != homeId and _areaOpen(homes[id].area):
			opts.append(id)
	if check:
		return opts.size() > 0
	if opts.is_empty():
		return null
	return opts[int(floor(game.rand() * opts.size())) % opts.size()]

# ============================================================================================ smacks & bullets
func onHit(info = {}) -> void:
	if not built or homeId == null or not root.visible:
		return
	if not (info is Dictionary):
		info = {}
	if _mp():
		_onHitMP(info)
		return
	var gm = game
	var s = seq
	if not info.get("melee", false):
		# bullets: "tink" and a glare
		if _clock - _tinkT > 0.07:
			_tinkT = _clock
			_play("smile_ting", {"vol": 0.7, "rate": 1.5 + randf() * 0.3, "at": info.get("point")})
			if info.get("point") != null:
				_invoke(gm.fx, "burst", [DAU.v3(info.point), {"shape": "spark", "count": 5, "speed": 3, "size": 0.03, "life": 0.2}])
		if s == null or s.phase == "spin" or s.phase == "land":
			_tempExpr("glare", 1.2)
		squash.kick(-0.4)
		return
	if _clock - _smackT < 0.35:
		return
	_smackT = _clock
	if s != null and s.phase == "spin" and s.outcome == "tape":
		_catchHand()
		return
	if s != null and s.phase == "offer":
		if s.outcome == "tape":
			_catchHand()
		else:
			_bopBack()
		return
	if s != null and s.phase == "spin" and not s.bumped and s.t >= WINDOW[0] and s.t < WINDOW[1]:
		_bump(s)
		return
	if s == null or s.phase == "spin" or s.phase == "land":
		_play("telly_hey")
		_tempExpr("glare", 1.4)
		squash.kick(-2.2)
		_jolt(0.05)
		_invoke(gm.cam, "shake", [0.08, 0.15])

# Percussive maintenance (GDD §10.2 rules 1-6): one detent forward now, then resolve the landing.
func _bump(s: Dictionary, hitter: int = 0) -> void:
	var r := _bumpResolve(s)
	_bumpApply(s, r[0], r[1], r[2], r[3], r[4], hitter)

# The percussive-maintenance rules (no mutation): [fromCh, ch, outcome, item|null, extra]. Host / solo only.
func _bumpResolve(s: Dictionary) -> Array:
	var fromCh: int = s.ch            # the channel the dial was going to land on (GDD: "a 12 bumps to a 13")
	var cyc: Array = s.cycle
	var L := cyc.size()
	var pos: int = s.startPos + s.N + s.shift + 1
	var ch: int = cyc[pos % L]
	var extra := 0
	var toItem := func() -> Array:
		var pp := pos
		var cc := ch
		var ex := extra
		while SNOW.has(cc) or _excluded(CH_ITEM.get(cc)):
			pp += 1
			ex += 1
			cc = cyc[pp % L]
		return [pp, cc, ex]
	var outcome: String = s.outcome
	if s.outcome == "signoff":                          # rule 5: bumping cancels a sign-off
		var r: Array = toItem.call()
		pos = r[0]; ch = r[1]; extra = r[2]
		outcome = "item"
	elif SNOW.has(ch):                                  # rule 4
		outcome = "signoff" if canMove() else "bad"
	else:                                               # rule 3
		var r: Array = toItem.call()
		pos = r[0]; ch = r[1]; extra = r[2]
		outcome = "item"
	return [fromCh, ch, outcome, CH_ITEM.get(ch) if outcome == "item" else null, extra]

# Applies a resolved bump (solo / every MP peer): the dial jumps, the landing moves `extra` detents later.
func _bumpApply(s: Dictionary, fromCh: int, ch: int, outcome: String, item, extra: int, hitter: int = 0) -> void:
	var gm = game
	s.bumped = true
	s.shift += 1
	var cyc: Array = s.cycle
	var L := cyc.size()
	s.outcome = outcome
	s.ch = ch
	s.item = item
	var times: Array = s.times
	var last: float = times[times.size() - 1]
	for i in range(1, extra + 1):
		times.append(last + 0.2 * i)
	s.landT = times[times.size() - 1]
	# the jump itself: an extra-loud clack, "ow!", a vertical roll
	var nowCh: int = cyc[(s.startPos + s.passed + s.shift) % L]
	_showDetent(s, nowCh, true)
	_play("telly_clack", {"vol": 1.9, "rate": 0.8})
	_play("telly_clack_final", {"vol": 0.9})
	_play("telly_ow", {"vol": 1.1})
	screen.fx.roll = 0.0
	_rollT = 0.3
	_tempExpr("glare", 0.3)
	squash.kick(-3.5)
	_jolt(0.09)
	ears.L.kick(-7)
	ears.R.kick(7)
	if _isMe(hitter):
		_invoke(gm.cam, "shake", [0.12, 0.2])
	_invoke(gm.fx, "burst", [_worldPoint(Vector3(0, 1.25, -0.1)), {"shape": "star", "count": 6, "speed": 2.6, "size": 0.1, "life": 0.6}])
	gm.events.emit("machine:telly_bump", {"fromChannel": fromCh, "toChannel": ch} if not _mp() else {"fromChannel": fromCh, "toChannel": ch, "by": hitter})

func _bopBack(hitter: int = 0) -> void:
	var gm = game
	var s = seq
	var p = gm.player if _isMe(hitter) else null    # MP: only the hitter's own peer moves its player
	_play("telly_nuh_uh", {"vol": 1.1})
	_gloveTo("bop", 0.12, easeOutCubic)
	if s != null:
		s.bopT = 0.32
	if p != null:
		var pp := DAU.v3(_field(p, "pos"))
		var v := Vector3(pp.x - root.position.x, 0, pp.z - root.position.z).normalized() * 6.0
		v.y = 2.0
		_invoke(p, "knockback", [v])
	if _isMe(hitter):
		_invoke(gm.cam, "shake", [0.14, 0.22])

func _catchHand() -> void:
	var s = seq
	_play("telly_nuh_uh", {"vol": 1.0})
	if s != null and s.phase == "offer":
		s.catchT = 1.1
		_gloveTo("catch", 0.12, easeOutCubic)
	else:
		_tempExpr("glare", 0.8)

func _meleeReaches() -> bool:
	var p = game.player
	if p == null or homeId == null or not root.visible:
		return false
	var fw = _invoke(p, "forward")
	var d: Vector3 = fw if fw is Vector3 else Vector3(0, 0, -1)
	var pp := DAU.v3(_field(p, "pos"))
	var v := _gxf(root).affine_inverse() * pp
	var dx := maxf(absf(v.x) - BOX.x, 0.0)
	var dz := maxf(absf(v.z) - BOX.z, 0.0)
	var dist := Vector2(dx, dz).length() * SCALE      # prop space -> metres (the player's reach does not grow)
	var v2 := Vector3(root.position.x - pp.x, 0, root.position.z - pp.z).normalized()
	return dist < 1.25 and d.x * v2.x + d.z * v2.z > 0.35

# player.aimRay(outOrigin, outDir) -> [origin, dir] (value-type port: Dictionary {origin, dir} or Array)
func _aimRay(p) -> Array:
	var r = _invoke(p, "aimRay")
	if r is Dictionary:
		return [DAU.v3(r.get("origin", r.get("o"))), DAU.v3(r.get("dir", r.get("d")))]
	if r is Array and r.size() >= 2:
		return [DAU.v3(r[0]), DAU.v3(r[1])]
	return []

func _fallbackBullet() -> void:
	var gm = game
	var p = gm.player
	if not _hasm(p, "aimRay") or homeId == null or not root.visible:
		return
	var ray := _aimRay(p)
	if ray.is_empty():
		return
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var hit = _raycast(o, d, 80.0)
	if hit == null:
		return
	var wall = _raycastCol(o, d, 80.0, {"ignoreTags": ["telly"]})
	if wall != null and _num(_field(wall, "dist"), INF) < hit.dist - 0.05:
		return
	onHit({"melee": false, "point": hit.point})

# ray vs the cabinet box (Telly local = prop space; the root is scaled by SCALE). The local direction is NOT
# normalised, so the slab distances stay in world metres along `d`.
func _raycast(o, d, mx = INF):
	if not built or homeId == null or not root.visible or (seq != null and seq.phase == "gap"):
		return null
	var ov := DAU.v3(o)
	var dv := DAU.v3(d)
	var inv := _gxf(root).affine_inverse()
	var lo := inv * ov
	var ld := (inv * (ov + dv)) - lo
	var y1: float = BOX.y1 + _legs * 0.4
	var tmin := 0.0
	var tmax := float(mx) if mx != null else INF
	for sl in [[lo.x, ld.x, -BOX.x, BOX.x], [lo.y, ld.y, BOX.y0, y1], [lo.z, ld.z, -BOX.z, BOX.z]]:
		var oo: float = sl[0]
		var dd: float = sl[1]
		var a: float = sl[2]
		var b: float = sl[3]
		if absf(dd) < 1e-8:
			if oo < a or oo > b:
				return null
			continue
		var t1 := (a - oo) / dd
		var t2 := (b - oo) / dd
		if t1 > t2:
			var tt := t1
			t1 = t2
			t2 = tt
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return null
	return {"dist": tmin, "point": ov + dv * tmin}

# ============================================================================================ the pull sequence
func _phase(s: Dictionary, name: String) -> void:
	s.phase = name
	s.u = -1e-6
	s.pu = -2e-6
	phase = name

# JS `hit(x)`: the phase clock crossed x this frame.
static func _hit(s: Dictionary, x: float) -> bool:
	return s.pu < x and s.u >= x

func _updateSeq(dt: float) -> void:
	var s: Dictionary = seq
	var gm = game
	s.prev = s.t
	s.t += dt
	s.pu = s.u
	s.u += dt
	if _freezeAt != null and s.prev < _freezeAt and s.t >= _freezeAt:
		var back: float = s.t - _freezeAt
		s.t -= back
		s.u = maxf(0.0, s.u - back)
		if _mp():
			if not _freezeWarned:
				_freezeWarned = true
				push_warning("[telly] debugFreezeAt: no global freeze in MP (ignored)")
		else:
			gm.time.scale = 0.0
		_freezeAt = null
	match s.phase:
		"spin": _seqSpin(s)
		"land": _seqLand(s)
		"bulge": _seqBulge(s)
		"offer": _seqOffer(s)
		"take": _seqTake(s)
		"timeout": _seqTimeout(s)
		"signoff": _seqSignoff(s)
		"bad": _seqBad(s)
		_: pass

func _seqSpin(s: Dictionary) -> void:
	var u: float = s.u
	if _hit(s, 0.0):
		_play("telly_ooh", {"vol": 1.1})
		_hopNow(0.13, true)
		_tempExpr("o_mouth", 0.5)
		screen.show("face")
	if _hit(s, SPIN.zip):
		screen.snapshot()
		screen.fx.zip = 0.0
		_play("telly_zip")
	if u >= SPIN.zip:
		screen.fx.zip = (u - SPIN.zip) / 0.15 if u < SPIN.zip + 0.15 else -1.0
	if _hit(s, SPIN.t0):
		s.arp = _invoke(game.audio, "play", ["telly_surf_arp", {"pos": _audio(), "vol": 0.9}])
		prop.spin = 1.0
		prop.settle = null
	var times: Array = s.times
	while s.passed < times.size() and u >= times[s.passed]:
		s.passed += 1
		var ch: int = s.cycle[(s.startPos + s.passed + s.shift) % (s.cycle as Array).size()]
		var final: bool = s.passed == times.size()
		_showDetent(s, ch, false, final)
	# propellers slow in the last second
	if u >= SPIN.t0:
		prop.spin = 1.0 if u < s.landT - 0.8 else lerp_(1.0, 0.25, (u - (s.landT - 0.8)) / 0.8)
	if u >= s.landT and s.passed >= times.size():
		if _cli():
			var lm = s.landMsg
			if lm == null:
				return                                 # MP client: hold the last detent until the host lands
			s.outcome = lm[0]
			s.item = lm[1]
			s.ch = lm[2]
		_land(s)

# One detent: the dial clacks forward, 60 ms of snow, then the channel's card + its 3D item inside the cabinet.
func _showDetent(s: Dictionary, ch: int, bumped: bool = false, final: bool = false) -> void:
	s.shownCh = ch
	s.detT = s.u
	s.detIdx = s.detIdx + 1
	s.cameoNow = s.passed == s.cameo
	_dialTo(ch, 0.11 if final else 0.06)
	if not final and not bumped:
		_play("telly_clack", {"vol": 0.8 + randf() * 0.25, "rate": 0.95 + randf() * 0.1})
		if s.arp != null:
			_invoke(s.arp, "step")
	squash.kick(-0.9)
	if s.cameoNow:
		_play("baron_laugh", {"vol": 0.45, "rate": 1.45})
	_showItem(null if s.outcome == "tape" or s.cameoNow else CH_ITEM.get(ch), "pop")

func _land(s: Dictionary) -> void:
	var gm = game
	_phase(s, "signoff" if s.outcome == "signoff" else ("bad" if s.outcome == "bad" else "land"))
	if s.arp != null:
		_invoke(s.arp, "stop", [0.06])
	s.arp = null
	_play("telly_clack_final", {"vol": 1.3})
	_play("telly_boing", {"vol": 0.9})
	prop.spin = 0.0
	var ay: float = (P.antennas as Node3D).rotation.y
	prop.settle = {"from": ay, "to": jround(ay / PI) * PI, "t": 0.0}
	ears.droop = 1.0
	ears.droopT = 1.6
	squash.kick(-4)
	s.shownCh = s.ch
	if s.outcome == "item":
		if s.item != null and WONDER.has(s.item):
			pity = 0
		else:
			pity += 1
	var result = "bad_reception" if s.outcome == "bad" else (s.item if s.outcome == "item" else s.outcome)
	if _hst():
		gm.net.toAll("telly", "land", [s.id, str(s.outcome), str(s.item) if s.item != null else "", int(s.ch)])
	gm.events.emit("machine:telly_result", {"result": result, "channel": s.ch} if not _mp() else {"result": result, "channel": s.ch, "by": s.by})
	if s.outcome == "tape":
		_play("baron_laugh", {"vol": 1.0})
	if s.outcome == "signoff" or s.outcome == "bad":
		_showItem(null)
		_play("pu_expire", {"vol": 0.9})
		_play("telly_zip", {"vol": 1.2, "rate": 0.55})
	else:
		_showItem(s.item, "pop")

func _seqLand(s: Dictionary) -> void:
	var gm = game
	screen.fx.zoom = 1.0 + 0.06 * smooth(s.u / LAND.jingle)
	if _hit(s, LAND.jingle) and s.outcome == "item":
		_play("jingle_%s" % s.item, {"vol": 1.1})
		var it = items.get(s.item)
		if it != null:
			it.pop = 1.0
		var scr := _worldPoint(Vector3(0.12, 0.9, -0.36))
		_invoke(gm.fx, "burst", [scr, {"shape": "star", "count": 10, "speed": 2.8, "size": 0.12, "life": 0.9, "dir": _fwd(), "cone": 0.9}])
		if WONDER.has(s.item):
			_play("telly_wonder_tada", {"vol": 1.1})
			_play("crowd_ooh", {"vol": 0.8, "delay": 0.15})
			var grille := _worldPoint(Vector3(-0.43, 0.35 + 0.335, -0.36))
			_invoke(gm.fx, "burst", [grille, {"shape": "confetti", "count": 36, "speed": 4.2, "size": 0.07, "life": 1.6, "dir": (_fwd() + Vector3(0, 1.1, 0)).normalized(), "cone": 0.55}])
			_invoke(gm.fx, "burst", [grille, {"shape": "star", "count": 6, "speed": 2.4, "size": 0.12, "life": 1}])
			_tempExpr("happy", 0.1)
	if _hit(s, LAND.jingle) and s.outcome == "tape" and items.get(TAPE_ID) != null:
		items[TAPE_ID].pop = 1.0
	if s.u >= LAND.bulge:
		screen.fx.zoom = 1.06
		_phase(s, "bulge")
		_play("telly_bulge", {"vol": 1.1})
		(P.glass as Node3D).visible = false
		bubble.visible = true
		_bubbleSet("uAlpha", 1.0)

func _bubbleSet(name: String, v) -> void:
	(bubble.material_override as ShaderMaterial).set_shader_parameter(name, v)

func _seqBulge(s: Dictionary) -> void:
	var k: float = s.u / LAND.bulgeDur
	_bubbleSet("uBulge", 0.35 * easeOutBack(minf(1.0, k * 1.15), 2.4))
	var wob: float = 0.6 + 0.4 * sin(s.u * 30.0)
	if s.outcome == "tape":
		wob += 0.5
	_bubbleSet("uWobble", wob)
	screen.fx.zoom = 1.06 - 0.06 * smooth(k)
	if s.u >= LAND.bulgeDur:
		_ploop(s)

func _ploop(s: Dictionary) -> void:
	var gm = game
	_phase(s, "offer")
	s.offerT = 0.0
	bubble.visible = false
	_bubbleSet("uBulge", 0.0)
	_play("telly_ploop", {"vol": 1.2})
	var tip := _worldPoint(Vector3(0.12, 0.9, -0.32 - 0.35))
	_invoke(gm.fx, "burst", [tip, {"shape": "spark", "count": 16, "speed": 3.6, "size": 0.04, "life": 0.3, "colors": ["#FFFFFF", "#CFF6FF", "#FFD9F4"]}])
	_invoke(gm.fx, "burst", [tip, {"shape": "puff", "count": 5, "speed": 1.2, "size": 0.12, "life": 0.4, "colors": ["#F4FBFF"]}])
	_invoke(gm.fx, "burst", [tip, {"shape": "star", "count": 5, "speed": 1.8, "size": 0.09, "life": 0.7}])
	_showGlove(true)
	_gloveTo("present", OFFER.out, easeOutBack)
	var it = items.get(s.item)
	if it != null:
		(P.gloveHold as Node3D).quaternion = (P.glove as Node3D).quaternion.inverse()
		_attach(P.gloveHold, it.wrap)
		it.rot0 = (it.wrap as Node3D).rotation.y
		it.mode = "hold"
		it.holdFrom = (it.wrap as Node3D).position
		it.holdT = 0.0
		for h in it.hulls:
			h.visible = true
	squash.kick(2.5)

func _seqOffer(s: Dictionary) -> void:
	var tape: bool = s.outcome == "tape"
	var dt: float = game.time.dt
	if s.bopT > 0:
		s.bopT -= dt
		if s.bopT <= 0:
			_gloveTo("present", 0.25, easeOutBack)
	if s.catchT > 0:
		s.catchT -= dt
		glove.wag = 1 if s.catchT < 0.8 else 0
		if s.catchT <= 0:
			glove.wag = 0
			_gloveTo("present", 0.25, easeOutBack)
	if tape:
		glove.shake = 1
		var k := int(floor(s.u / OFFER.tapeDrum))
		if k >= 1 and k != s.drumK:
			s.drumK = k
			glove.drum = 0.0
			_play("telly_drum")
		return
	if _hit(s, OFFER.drum):
		glove.drum = 0.0
		_play("telly_drum")
		_tempExpr("idle", 0.1)
	if _hit(s, OFFER.drum + 0.5):
		_play("telly_drum", {"rate": 1.05})
	if _hit(s, OFFER.wag):
		_gloveTo("wag", 0.25, easeOutBack)
		glove.wag = 1
		_play("telly_nuh_uh")
	if _hit(s, OFFER.wag + 1.3):
		glove.wag = 0
		_gloveTo("present", 0.3, easeOutBack)
	if not _mp():
		if s.u >= OFFER.window:
			_doTimeout(s)
	elif _hst() and (s.u >= OFFER.window + MP_GRACE or (s.orphan and s.u >= 1.0)):
		game.net.everyone("telly", "timeout", [s.id])

func _doTimeout(s: Dictionary) -> void:
	_phase(s, "timeout")
	_gloveTo("reach", 0.3, easeInOut)
	_play("telly_slurp")

func take() -> bool:
	var s = seq
	if s == null or s.phase != "offer" or s.u < OFFER.out * 0.6:
		return false
	if _mp():
		if s.orphan or s.by != _me():
			return false
		game.net.toHost("telly", "take", [s.id])
		return true
	_doTake(s)
	return true

# The take on every peer (solo: take(); MP: net_took): only the user's peer gets the weapon / reel.
func _doTake(s: Dictionary) -> void:
	var gm = game
	var it = items.get(s.item)
	if s.outcome == "tape":
		_giveTape(it, s.by)
	elif _isMe(s.by):
		var w = gm.weapons
		if _hasm(w, "give"):
			_invoke(w, "give", [s.item, {"source": "telly"}])
		else:
			gm.events.emit("weapon:acquire", {"weaponId": s.item, "upgraded": false, "source": "telly"})
	if s.outcome != "tape":
		if it != null:
			for h in it.hulls:
				h.visible = false
			var parent: Node3D = root.get_parent() if root.get_parent() is Node3D else gm.scene
			_attach(parent, it.wrap)
			it.mode = "fly"
			it.flyT = 0.0
			it.flyFrom = (it.wrap as Node3D).position
			it.flyScale = (it.wrap as Node3D).scale.x
			it["flyBy"] = s.by
	gm.events.emit("machine:telly_take", {"itemId": s.item} if not _mp() else {"itemId": s.item, "by": s.by})
	s.took = true
	_phase(s, "take")
	_gloveTo("fingerguns", 0.18, easeOutBack)
	glove.drum = -1.0
	glove.wag = 0
	glove.shake = 0
	_play("costume_pop", {"vol": 0.6})

func _giveTape(it, by: int = 0) -> void:
	var gm = game
	var p = _pl(by)
	tapeHolder = by
	if it == null:
		return
	for h in it.hulls:
		h.visible = false
	var back = _field(_field(_field(p, "hero"), "slots"), "back")
	it.mode = "gone"
	var reel: Node3D = it.wrap
	DAU.detach(reel)
	items[TAPE_ID] = null
	if back is Node3D:
		(back as Node3D).add_child(reel)
		reel.position = Vector3(0, 0.05, 0.09)
		reel.rotation = Vector3(0, 0, 0.15)
		reel.scale = Vector3.ONE * 0.9
	else:
		var par: Node = root.get_parent() if root.get_parent() != null else gm.scene
		par.add_child(reel)
		reel.visible = false
	reel.visible = true
	reel.name = TAPE_ID
	if p != null and p != gm.player and back is Node3D:
		DAU.setLayerRecursive(reel, 1)            # RemotePlayer.LAYER: drawn with the remote hero
	tapeReel = reel
	setMood("normal")

func _seqTake(s: Dictionary) -> void:
	if _hit(s, 0.02):
		_play("telly_giggle", {"delay": 0.25})
		_tempExpr("wink", 1.6)
		rippleT = 0.9
	if _hit(s, 0.55):
		_gloveTo("hidden", 0.28, easeInBack)
		_play("telly_slurp")
	if _hit(s, 0.85):
		_showGlove(false)
	if s.u >= 1.25:
		_endSeq()

func _seqTimeout(s: Dictionary) -> void:
	var it = items.get(s.item)
	if _hit(s, 0.3):
		_gloveTo("hidden", 0.3, easeInBack)
	if _hit(s, 0.62):
		_showGlove(false)
		if it != null:
			_stowItem(it)
		_tempExpr("pout", 2.2)
		_play("telly_aww")
		rippleT = 0.6
		squash.kick(-1.5)
	if s.u >= 1.4:
		_endSeq()

# Sign-off: roaring snow, test card + lullaby + refund coin, stand up, waddle, CRT power-off, unfold elsewhere.
func _seqSignoff(s: Dictionary) -> void:
	var gm = game
	if s.dest == null and s.u >= SO.arrive - 0.01 and _cli():
		s.holdT += gm.time.realDt
		if s.holdT < 3.0:
			s.u = SO.arrive - 0.01                     # MP client: wait for the host's destination
			s.pu = s.u
		else:
			s.dest = homeId if homes.has(homeId) else homes.keys()[0]
	var u: float = s.u
	if _hit(s, SO.card):
		_play("telly_lullaby", {"vol": 1.1})
		s.yawnT = 0.0
	if _hit(s, SO.gloveOut):
		_showGlove(true)
		_gloveTo("coin", 0.3, easeOutBack)
		_coinInHand(true)
	if _hit(s, SO.flick):
		_flickCoin(s)
	if _hit(s, SO.gloveIn):
		_gloveTo("hidden", 0.3, easeInBack)
	if _hit(s, SO.gloveIn + 0.32):
		_showGlove(false)
	if _hit(s, SO.stand):
		_play("telly_boing", {"vol": 0.8, "rate": 1.3})
	if u >= SO.stand and u < SO.stand + 0.5:
		_legs = easeOutBack((u - SO.stand) / 0.32, 2.6)
	if _hit(s, SO.shake):
		_play("jelly_bwoing", {"vol": 0.5, "rate": 1.4})
		_invoke(gm.fx, "burst", [_worldPoint(Vector3(0, 1.3, 0)), {"shape": "puff", "count": 6, "speed": 1.6, "size": 0.16, "life": 0.6, "colors": ["#E8DCCB", "#CFC3B0"]}])
	_shake = 1.0 - (u - SO.shake) / (SO.turn - SO.shake) if u >= SO.shake and u < SO.turn else 0.0
	if _hit(s, SO.turn):
		var h = homes.get(homeId)
		if h != null:
			if h.dust != null:
				h.dust.visible = true
			_invoke(_col(), "setEnabled", [h.colId, false])
		s.walk = _walkPlan()
		s.walk.yaw0 = root.rotation.y
	var walk = s.walk
	if walk != null and u >= SO.turn and u < SO.walk:
		root.rotation.y = walk.yaw0 + wrapPi(walk.yaw - walk.yaw0) * easeInOut((u - SO.turn) / (SO.walk - SO.turn))
	if walk != null and u >= SO.walk and u < SO.walk + SO.walkDur:
		_waddle(s, gm.time.dt, u - SO.walk)
	if walk != null and u >= SO.walk + SO.walkDur and not s.walkDone:
		s.walkDone = true
		_waddleEnd()
	if _hit(s, SO.turnBack) and walk != null:
		walk.yaw1 = root.rotation.y
	if walk != null and u >= SO.turnBack and u < SO.wave:
		var p = _pl(s.by)
		var faceYaw: float = walk.yaw0
		if p != null:
			var pp := DAU.v3(_field(p, "pos"))
			faceYaw = atan2(-(pp.x - root.position.x), -(pp.z - root.position.z))
		root.rotation.y = walk.yaw1 + wrapPi(faceYaw - walk.yaw1) * easeInOut((u - SO.turnBack) / (SO.wave - SO.turnBack))
	if _hit(s, SO.wave):
		_showGlove(true)
		_gloveTo("wave", 0.2, easeOutBack)
		glove.wave = 1
		_play("telly_giggle", {"rate": 0.9})
	if _hit(s, SO.off - 0.15):
		glove.wave = 0
		_gloveTo("hidden", 0.14, easeInBack)
	if _hit(s, SO.off):
		_showGlove(false)
		if _cli():
			pass                                       # MP client: the host's net_dest sets s.dest
		else:
			var dest = _pickDestination()
			s.dest = dest if dest != null else homeId
			if _hst():
				gm.net.toAll("telly", "dest", [s.id, str(s.dest)])
		gm.events.emit("machine:telly_move", {"from": homeId, "to": s.dest})
		_play("crt_power_off", {"vol": 1.1})
		screen.fx.collapse = 0.0
	if u >= SO.off and u < SO.squash:
		screen.fx.collapse = minf(1.0, (u - SO.off) / (SO.squash - SO.off))
	if _hit(s, SO.squash):
		screen.fx.collapse = -1.0
		screen.fx.dot = 1.0
		_play("telly_thwip", {"vol": 1.1})
		_dotAt(_worldPoint(Vector3(PIV.x, PIV.y, PIV.z - 0.08)))
	if u >= SO.squash and u < SO.gone:
		var k: float = (u - SO.squash) / (SO.gone - SO.squash)
		var sx := maxf(0.001, 1.0 - easeInBack(k, 1.4))
		var sy := maxf(0.001, 1.0 - easeInBack(minf(1.0, k * 1.5), 1.2))
		pivot.scale = Vector3(sx, sy, maxf(0.001, sx))
		dotSprite.scale = Vector3.ONE * ((0.15 + 0.35 * k) * SCALE)
		_dotOpacity(0.4 + 0.6 * k)
	if _hit(s, SO.gone):
		var from = homes.get(homeId)
		root.visible = false
		_humVol(0.0)
		if from != null:
			from.lampMode = "off"
			from.flick = 0.15
			if from.cord != null:
				from.cord.visible = true
		var at = null
		if from != null:
			at = (from.lamp as Node3D).position
			at.y = 1.5
		_play("light_thunk", {"vol": 0.5, "at": at})
		_invoke(gm.fx, "flashLight", [dotSprite.position, "#CFF6FF", 3.0, 0.25])
		homeId = null
	if u >= SO.gone and u < SO.arrive:
		var k: float = (u - SO.gone) / (SO.arrive - SO.gone)
		_dotOpacity(maxf(0.0, 1.0 - k * k))
		dotSprite.scale = Vector3.ONE * (0.5 * SCALE * (1.0 - 0.6 * k) * (0.9 + 0.1 * sin(u * 40.0)))
	if _hit(s, SO.arrive):
		var to = s.dest if homes.has(s.dest) else homes.keys()[0]
		_placeAt(to, true)
		var h: Dictionary = homes[to]
		h.lampMode = "purple" if mood == "purple" else "full"
		h.flick = 0.6
		var lp: Vector3 = (h.lamp as Node3D).position
		lp.y = 1.5
		_play("onair_clack", {"vol": 0.8, "at": lp})
		_dotAt(_worldPoint(Vector3(PIV.x, PIV.y, PIV.z - 0.08)))
		_dotOpacity(0.0)
		pullsHere = 0
	if u >= SO.arrive and u < SO.unfold:
		var k: float = (u - SO.arrive) / (SO.unfold - SO.arrive)
		_dotOpacity(minf(1.0, k * 3.0))
		var w: float = 0.12 + k * 0.4 if k < 0.5 else 0.32 + easeOutCubic((k - 0.5) / 0.5) * 0.9
		var hh: float = 0.12 + k * 0.4 if k < 0.5 else maxf(0.05, 0.32 - (k - 0.5) * 0.6)
		dotSprite.scale = Vector3(w * SCALE, hh * SCALE, 1.0)
	if _hit(s, SO.unfold):
		root.visible = true
		dotSprite.visible = false
		pivot.scale = Vector3(1, 0.01, 1)
		screen.fx.dot = 0.0
		screen.fx.unfold = 0.0
		screen.show("face")
		_play("telly_bwong", {"vol": 1.2})
		_humVol(1.0)
		_invoke(gm.fx, "flashLight", [_worldPoint(Vector3(PIV.x, PIV.y, PIV.z - 0.3)), "#BFF1FF", 4.0, 0.3])
		_invoke(gm.fx, "burst", [_worldPoint(Vector3(PIV.x, PIV.y, PIV.z - 0.2)), {"shape": "static", "count": 14, "speed": 2.2, "size": 0.07, "life": 0.6}])
	if u >= SO.unfold and u < SO.done:
		var k: float = (u - SO.unfold) / 0.5
		var sx := minf(1.25, easeOutElastic(minf(1.0, k * 1.6)))
		var sy := maxf(0.01, easeOutElastic(maxf(0.0, k - 0.12) / 0.88))
		pivot.scale = Vector3.ONE if k >= 1.0 else Vector3(sx, sy, sx)
		screen.fx.unfold = minf(1.0, (u - SO.unfold) / 0.65)
		if screen.fx.unfold >= 1.0:
			screen.fx.unfold = -1.0
	if _hit(s, SO.unfold + 0.55):
		_tempExpr("sleepy", 1.6)
		_yawnT = 0.0
		_play("telly_aww", {"vol": 0.5, "rate": 0.75})
	if u >= SO.done:
		pivot.scale = Vector3.ONE
		screen.fx.unfold = -1.0
		var hh = homes.get(homeId)
		if hh != null:
			_invoke(_col(), "setEnabled", [hh.colId, true])
		if _field(gm.nav, "built"):
			_invoke(gm.nav, "build")
		_near = false
		_endSeq()

# "Bad reception": bumped into snow and nowhere to go. The glove comes out empty, shrugs, refunds 950.
func _seqBad(s: Dictionary) -> void:
	if _hit(s, BAD.gloveOut):
		_showGlove(true)
		_gloveTo("shrug", 0.3, easeOutBack)
		_play("telly_nuh_uh", {"rate": 0.85})
		_tempExpr("o_mouth", 1.2)
	glove.shrug = 1 if s.u >= BAD.shrug and s.u < BAD.flick - 0.15 else 0
	if _hit(s, BAD.flick - 0.15):
		_gloveTo("coin", 0.15, easeOutCubic)
		_coinInHand(true)
	if _hit(s, BAD.flick):
		_flickCoin(s)
	if _hit(s, BAD.gloveIn):
		_gloveTo("hidden", 0.3, easeInBack)
	if _hit(s, BAD.gloveIn + 0.32):
		_showGlove(false)
	if s.u >= BAD.done:
		_endSeq()

func _endSeq(hard: bool = false) -> void:
	var s = seq
	if s != null and s.arp != null:
		_invoke(s.arp, "stop", [0.05])
	seq = null
	phase = "idle" if awake else "asleep"
	_showGlove(false)
	glove.drum = -1.0
	glove.wag = 0
	glove.wave = 0
	glove.shake = 0
	glove.shrug = 0
	bubble.visible = false
	(P.glass as Node3D).visible = true
	for it in items.values():
		if it != null and it.mode != "gone":
			_stowItem(it)
	screen.fx.zoom = 1.0
	screen.fx.zip = -1.0
	screen.fx.roll = -1.0
	screen.fx.collapse = -1.0
	screen.fx.unfold = -1.0
	screen.fx.dot = 0.0
	prop.spin = 0.0
	_legs = 0.0
	_shake = 0.0
	if hard:
		pivot.scale = Vector3.ONE
		dotSprite.visible = false
		coin.visible = false
		coinFly = null
		root.visible = true
		ears.droop = 0.0

# ============================================================================================ coin, walk, dot
func _coinInHand(on: bool) -> void:
	coin.visible = on
	coinFly = {"mode": "hand"} if on else null

func _flickCoin(s: Dictionary) -> void:
	glove.flick = 0.0
	_play("telly_ploop", {"vol": 0.4, "rate": 1.8})
	coinFly = {"mode": "fly", "t": 0.0, "dur": 0.5, "from": _gxf(P.gloveHold).origin, "refund": s.cost, "s": s}

func _updateCoin(dt: float) -> void:
	var c = coinFly
	if c == null:
		return
	var gm = game
	if c.mode == "hand":
		var hp := _gxf(P.gloveHold).origin
		hp.y += 0.06
		coin.position = hp
		coin.rotation.y += dt * 3.0
		return
	c.t += dt
	var k := clamp01(c.t / c.dur)
	var p = _pl(c.s.by)
	var v: Vector3 = DAU.v3(_field(p, "pos")) if p != null else c.from
	v.y = (DAU.v3(_field(p, "pos")).y if p != null else 0.0) + 1.25
	var cp: Vector3 = (c.from as Vector3).lerp(v, k)
	cp.y += sin(k * PI) * 0.9
	coin.position = cp
	coin.rotation.x += dt * 24.0
	coin.rotation.y += dt * 5.0
	if k >= 1.0:
		coin.visible = false
		coinFly = null
		var eco = gm.economy
		if _mp():
			# MP: only the user's peer is refunded (economy.refund: not earned, no multiplier)
			if c.refund > 0 and eco != null and not c.s.refunded and _isMe(c.s.by):
				c.s.refunded = true
				if _hasm(eco, "refund"):
					_invoke(eco, "refund", [c.refund, "telly_refund"])
		elif c.refund > 0 and eco != null and not c.s.refunded:
			c.s.refunded = true
			var mul = _field(eco, "multiplier", 1)
			if not mul:
				mul = 1
			var got = _invoke(eco, "add", [float(c.refund) / float(mul), "telly_refund"])
			var earned = _field(eco, "earned")
			if (earned is float or earned is int) and _num(got) > 0:
				eco.earned -= got                     # a refund is not earned points
		_play("telly_coin", {"vol": 1.1, "at": v})
		_invoke(gm.fx, "burst", [v, {"shape": "star", "count": 6, "speed": 2, "size": 0.08, "life": 0.6, "colors": [Config.PAL.marqueeGold, "#FFF3B0"]}])

func _walkPlan() -> Dictionary:
	var lv = game.level
	var h = homes.get(homeId)
	var areas = _field(lv, "areas")
	var area = areas.get(h.area) if areas is Dictionary and h != null else null
	var doors = _field(lv, "doors")
	var best = null
	var bd := INF
	var ids = _field(area, "doors", [])
	for id in (ids if ids is Array else []):
		var d = doors.get(id) if doors is Dictionary else null
		var dp = _field(d, "pos")
		if dp == null:
			continue
		var dv := DAU.v3(dp)
		var dist := Vector2(dv.x - root.position.x, dv.z - root.position.z).length()
		if dist < bd:
			bd = dist
			best = dv
	var dir: Vector3 = Vector3(best.x - root.position.x, 0, best.z - root.position.z).normalized() if best != null else h.fwd
	return {"dir": dir, "yaw": atan2(-dir.x, -dir.z), "max": maxf(0.0, bd - 1.2 * SCALE) if best != null else 2.4, "moved": 0.0,
		"pos": root.position, "step": 0, "yaw0": 0.0, "yaw1": 0.0}

# col.moveCircle(pos, delta, radius, height, stepUp) mutates pos in the JS: the port returns the moved feet in
# res.pos (the grounded flag is remembered per `owner`: the walk Dictionary, the JS pos object).
func _moveCircle(pos: Vector3, delta: Vector3, r: float, h: float, stepUp: float, owner = null) -> Vector3:
	var col = _col()
	if not _hasm(col, "moveCircle"):
		return pos + delta
	var res = _invoke(col, "moveCircle", [pos, delta, r, h, stepUp, null, owner])
	if res is Vector3:
		return res
	if res is Dictionary and res.get("pos") is Vector3:
		return res.pos
	return pos + delta

func _waddle(s: Dictionary, dt: float, w: float) -> void:
	var walk: Dictionary = s.walk
	root.rotation.y = walk.yaw
	# same gait at the bigger size: stride speed and footprint scale with Telly
	var speed := 1.2 * SCALE * smooth(w / 0.2) * (1.0 - smooth((w - SO.walkDur + 0.2) / 0.2))
	var step := minf(speed * dt, maxf(0.0, walk.max - walk.moved))
	if step > 0.0 and dt > 0.0:
		var d: Vector3 = (walk.dir as Vector3) * step
		var before: Vector3 = walk.pos
		var np := _moveCircle(walk.pos, d, 0.5 * SCALE, 1.4 * SCALE, 0.1, walk)
		np.y = 0.0
		walk.pos = np
		walk.moved += before.distance_to(np)
		root.position.x = np.x
		root.position.z = np.z
	var ph := w * 2.6 * TAU / 2.0
	_waddlePh = ph
	var k := int(floor(w * 5.2))
	if k != walk.step:
		walk.step = k
		_play("telly_clonk", {"vol": 0.9, "rate": 1.08 if k & 1 else 0.94})

func _waddleEnd() -> void:
	_waddlePh = null

func _dotAt(p: Vector3) -> void:
	dotSprite.position = p
	dotSprite.visible = true
	dotSprite.scale = Vector3.ONE * (0.15 * SCALE)
	_dotOpacity(1.0)

func _dotOpacity(a: float) -> void:
	(dotSprite.material_override as ShaderMaterial).set_shader_parameter("opacity", a)

# ============================================================================================ placement
func _placeAt(id, hidden: bool = false) -> void:
	var gm = game
	var h = homes.get(id)
	if h == null:
		return
	var roots = _field(gm.level, "areaRoots")
	var parent: Node = roots.get(h.area) if roots is Dictionary and roots.get(h.area) is Node else gm.scene
	if root.get_parent() != parent:
		_reparent(parent, root)
	root.position = h.pos
	root.rotation = Vector3(0, h.rotY, 0)
	root.visible = not hidden
	pivot.scale = Vector3.ONE
	homeId = id
	_legs = 0.0
	setTellyLegs(g, 0.0)
	for o in homes.values():
		var here: bool = o.id == id
		if o.dust != null:
			o.dust.visible = not here
		if o.cord != null:
			o.cord.visible = not here
		_invoke(_col(), "setEnabled", [o.colId, here and not hidden])
	_humVol(0.0 if hidden else 1.0)
	if act != null:
		act.pos = _worldPoint(Vector3(0.12, 0.9, -0.55))

func _humVol(v: float) -> void:
	if hum == null:
		return
	_invoke(hum, "setPos", [root.position])
	_invoke(hum, "setVol", [v * (0.9 if awake else 0.5), 0.4])

# ============================================================================================ animation
func _hopNow(height: float = 0.12, big: bool = false) -> void:
	hop = {"t": 0.0, "h": height, "big": big}
	squash.kick(-5 if big else -3)

func _jolt(a: float) -> void:
	_joltT = 0.25
	_joltA = a

func _tempExpr(expr: String, sec: float) -> void:
	_exprTemp = expr
	_exprT = sec

func _dialTo(ch: int, dur: float) -> void:
	var D := dial
	var bi := DIAL_ORDER.find(ch)
	if bi < 0:
		return
	var steps := posmod(bi - int(D.idx), 13)
	D.idx = bi
	D.from = (P.dial as Node3D).rotation.z
	D.angle = D.angle + steps * (TAU / 13.0)
	D.to = D.angle
	D.t = 0.0
	D.dur = dur

func _dialCh() -> int:
	return DIAL_ORDER[dial.idx]

func _animate(dt: float, t: float) -> void:
	var s = seq
	# hop (anticipation squash, stretch in the air, land squash)
	var hy := 0.0
	if hop != null:
		var H: Dictionary = hop
		H.t += dt
		var pre := 0.08
		var air := 0.36 if H.big else 0.3
		if H.t < pre:
			squash.x = lerp_(squash.x, 0.86, 0.5)
		elif H.t < pre + air:
			var k: float = (H.t - pre) / air
			hy = 4.0 * H.h * k * (1.0 - k)
			if k < 0.5:
				squash.x = lerp_(squash.x, 1.1, 0.35)
		else:
			squash.kick(-3)
			hop = null
	var sq: float = squash.update(dt, 1.0)
	var breathe := 0.0 if seq != null else 0.01 * (1.0 + sin(t * TAU * 0.4))
	var sy := maxf(0.5, sq) * (1.0 + breathe)
	var sxz := 1.0 / sqrt(maxf(0.5, sq))
	g.scale = Vector3(sxz, sy, sxz)
	g.position.y = -PIV.y + hy
	# shiver (zombies near, purple mood) / jolt / wet-dog shake / waddle
	var shiver := s == null and awake and (_zombieNear or mood == "purple")
	var rz := 0.0
	var rx := 0.0
	var px := 0.0
	if shiver:
		px += sin(t * 57.0) * 0.007
		rz += sin(t * 43.0) * 0.012
	if _joltT > 0.0:
		_joltT -= dt
		rz += sin(_joltT * 60.0) * _joltA * (_joltT / 0.25)
	if _shake > 0.0:
		rz += sin(t * 58.0) * 0.16 * _shake
		px += sin(t * 47.0) * 0.02 * _shake
	if _waddlePh != null:
		rz += sin(_waddlePh) * 0.11
		rx += 0.05
		hy += absf(sin(_waddlePh)) * 0.035
		g.position.y += absf(sin(_waddlePh)) * 0.035
	g.rotation = Vector3(rx, 0.0, rz)
	g.position.x = -PIV.x + px
	# yawn: slow stretch up
	if _yawnT != null or (s != null and s.yawnT != null):
		var yt: float
		if s != null and s.yawnT != null:
			s.yawnT += dt
			yt = s.yawnT
		else:
			_yawnT += dt
			yt = _yawnT
		if yt < 1.4:
			g.scale.y *= 1.0 + 0.07 * sin(minf(1.0, yt / 1.4) * PI)
		elif s != null and s.yawnT != null:
			s.yawnT = null
		else:
			_yawnT = null
	# legs telescope (sign-off) + waddle feet
	var legT := _legs
	setTellyLegs(g, minf(1.15, legT))
	if _waddlePh != null:
		var legs: Array = P.get("legs", [])
		for i in legs.size():
			var leg: Node3D = legs[i]
			var foot = DAU.byName(leg, str(DAU.ud(leg).get("footName", str(leg.name) + "_foot")))
			if foot is Node3D:
				(foot as Node3D).position.y += maxf(0.0, sin(_waddlePh + (i % 2) * PI)) * 0.05
	# dial snap with overshoot
	var D := dial
	if D.t < 1.0:
		D.t = minf(1.0, D.t + dt / maxf(0.02, D.dur if D.dur else 0.06))
		(P.dial as Node3D).rotation.z = D.from + (D.to - D.from) * easeOutBack(D.t, 2.2)
	# antennas: propellers during the spin, droop at the landing, twitches
	var pr := prop
	var ant := P.antennas as Node3D
	if pr.spin > 0.0:
		ant.rotation.y += dt * TAU * 2.0 * pr.spin
	elif pr.settle != null:
		var st: Dictionary = pr.settle
		st.t += dt / 0.45
		ant.rotation.y = st.from + (st.to - st.from) * easeOutBack(st.t, 2.0)
		if st.t >= 1.0:
			pr.settle = null
	var E := ears
	if E.droopT > 0.0:
		E.droopT -= dt
		if E.droopT <= 0.0:
			E.droop = 0.0
	E.dCur = lerp_(E.dCur, E.droop, 1.0 - exp(-dt * (14.0 if E.droop else 3.0)))
	var eL: float = E.L.update(dt, 0.0)
	var eR: float = E.R.update(dt, 0.0)
	var spinSplay: float = 0.35 * pr.spin if pr.spin > 0.0 else 0.0
	var rL: Vector3 = earRest.L
	var rR: Vector3 = earRest.R
	(P.earL as Node3D).rotation = Vector3(rL.x + E.dCur * 0.35 + eL * 0.04, 0.0, rL.z - E.dCur * 0.85 - spinSplay + eL * 0.06)
	(P.earR as Node3D).rotation = Vector3(rR.x + E.dCur * 0.35 + eR * 0.04, 0.0, rR.z + E.dCur * 0.85 + spinSplay + eR * 0.06)
	if _waddlePh != null:
		(P.earL as Node3D).rotation.z += sin(_waddlePh) * 0.2
		(P.earR as Node3D).rotation.z += sin(_waddlePh) * 0.2
	# screen ripple after a take / timeout
	if scrMat != null:
		if rippleT > 0.0:
			rippleT -= dt
			_setU(scrMat, "uWobble", clamp01(rippleT / 0.6))
			_setU(scrMat, "uBulge", 0.03 + 0.05 * clamp01(rippleT / 0.6))
		else:
			_setU(scrMat, "uWobble", 0.0)
			_setU(scrMat, "uBulge", 0.03)

# Glove: pose blending + procedural layers (wave, wag, drum, shake, shrug, thumb flick). Arm tube rebuilt each frame.
func _showGlove(on: bool) -> void:
	glove.on = on
	(P.glove as Node3D).visible = on
	(P.arm as Node3D).visible = on
	(P.glass as Node3D).visible = not on and not (bubble != null and bubble.visible)
	if not on:
		var hp = poses.get("hidden")
		if hp != null:
			(P.glove as Node3D).position = hp.pos
			(P.glove as Node3D).quaternion = hp.quat
			(P.armCtrl as Node3D).position = hp.ctrl
		glove.to = hp if hp != null else glove.to
		glove.from = glove.to
		glove.t = 1.0

func _gloveTo(name: String, dur: float = 0.3, ease: Callable = easeOutBack) -> void:
	var G := glove
	var F: Dictionary = P.gloveFingers
	G.from = {
		"pos": (P.glove as Node3D).position, "quat": (P.glove as Node3D).quaternion, "ctrl": (P.armCtrl as Node3D).position,
		"f": [F.index.rotation.x, F.middle.rotation.x, F.pinky.rotation.x, F.thumb.rotation.x],
	}
	G.to = poses.get(name, poses.present)
	G.t = 0.0
	G.dur = dur
	G.ease = ease
	G.name = name

func _updateGlove(dt: float) -> void:
	var G := glove
	if not G.on:
		return
	var F: Dictionary = P.gloveFingers
	var gl := P.glove as Node3D
	G.t = minf(1.0, G.t + dt / maxf(0.01, G.dur))
	var k: float = (G.ease as Callable).call(G.t)
	var kq := clamp01(k)
	gl.position = (G.from.pos as Vector3).lerp(G.to.pos, k)
	var q: Quaternion = (G.from.quat as Quaternion).normalized().slerp((G.to.quat as Quaternion).normalized(), kq)
	(P.armCtrl as Node3D).position = (G.from.ctrl as Vector3).lerp(G.to.ctrl, k)
	var fl: Array = []
	for i in 4:
		fl.append(lerp_(G.from.f[i], G.to.f[i], kq))
	var t := _clock
	# procedural layers
	var zAxis := Vector3(0, 0, 1)
	if G.wave:
		q = Quaternion(zAxis, sin(t * 16.0) * 0.45) * q
	if G.wag:
		q = Quaternion(zAxis, sin(t * 22.0) * 0.35) * q
	var p := gl.position
	if G.shrug:
		q = Quaternion(zAxis, sin(t * 7.0) * 0.3) * q
		p.y += absf(sin(t * 7.0)) * 0.04
	if G.shake:
		p.x += (randf() - 0.5) * 0.012
		p.y += (randf() - 0.5) * 0.012
	if G.drum >= 0.0:
		G.drum += dt
		var d: float = G.drum
		for i in 3:
			fl[i] += -0.9 * maxf(0.0, sin((d * 9.0 - i * 0.7) * PI)) * (1.0 if d < 1.4 else 0.0)
		if d > 1.5:
			G.drum = -1.0
	if G.flick >= 0.0:
		G.flick += dt
		fl[3] += -1.2 * sin(minf(1.0, G.flick / 0.25) * PI)
		if G.flick > 0.3:
			G.flick = -1.0
	if seq == null or seq.phase == "offer":
		p.y += sin(t * 2.4) * 0.012
	gl.position = p
	gl.quaternion = q
	F.index.rotation.x = fl[0]
	F.middle.rotation.x = fl[1]
	F.pinky.rotation.x = fl[2]
	F.thumb.rotation.x = fl[3]
	(P.gloveHold as Node3D).quaternion = q.inverse()
	updateTellyArm(g)

# The item: floats inside the cabinet, pushes into the bubble, rides the glove, flies to the player.
func _showItem(id, fx = null) -> void:
	for it in items.values():
		if it == null or it.mode == "gone":
			continue
		var on: bool = it.id == id
		if it.mode == "hold" or it.mode == "fly":
			continue
		it.wrap.visible = on
		if on and fx == "pop":
			it.pop = maxf(it.pop, 0.6)
	_shownItem = id

func _stowItem(it: Dictionary) -> void:
	for h in it.hulls:
		h.visible = false
	var w: Node3D = it.wrap
	if w.get_parent() != P.weaponSlot:
		_reparent(P.weaponSlot, w)
	w.transform = Transform3D.IDENTITY
	w.scale = Vector3.ONE * it.sIn
	w.visible = false
	it.mode = "in"
	it.pop = 0.0

func _updateItem(dt: float, t: float) -> void:
	var s = seq
	var glScale: float = (P.glove as Node3D).scale.x
	if glScale == 0.0:
		glScale = 1.0
	for it in items.values():
		if it == null or it.mode == "gone":
			continue
		var w: Node3D = it.wrap
		if it.mode == "hold":
			it.holdT += dt
			var k := easeOutCubic(it.holdT / 0.3)
			w.position = (it.holdFrom as Vector3).lerp(Vector3(0, ITEM_LIFT / glScale, -0.02 / glScale), k)
			var sc: float = lerp_(it.sIn * 1.08, it.sOut, k) / glScale
			w.rotation = Vector3(0, it.rot0 + it.holdT * TAU, 0)
			w.scale = Vector3.ONE * sc
			if not it.hulls.is_empty():
				var mat := (it.hulls[0] as MeshInstance3D).material_override as ShaderMaterial
				mat.set_shader_parameter("uThick", (0.0085 if it.wonder else 0.0065) / maxf(0.2, sc * glScale))
			if s != null and s.phase == "timeout" and s.u > 0.3:
				w.scale *= maxf(0.05, 1.0 - (s.u - 0.3) / 0.32)
			continue
		if it.mode == "fly":
			it.flyT += dt
			var k := clamp01(it.flyT / 0.22)
			var p = _pl(int(it.get("flyBy", 0)))
			var v: Vector3 = DAU.v3(_field(p, "pos")) if p != null else it.flyFrom
			v.y = (DAU.v3(_field(p, "pos")).y if p != null else 0.0) + 1.1
			w.position = (it.flyFrom as Vector3).lerp(v, easeInCubic(k))
			w.scale = Vector3.ONE * (it.flyScale * (1.0 - 0.8 * k))
			w.rotation.y += dt * 12.0
			if k >= 1.0:
				_invoke(game.fx, "burst", [v, {"shape": "star", "count": 7, "speed": 2.2, "size": 0.09, "life": 0.5}])
				_play("smile_ting", {"vol": 0.6, "rate": 1.2, "at": v})
				_stowItem(it)
			continue
		if not w.visible:
			continue
		# inside the cabinet
		it.pop = maxf(0.0, it.pop - dt * 4.0)
		var bob := sin(t * 2.2 + (it.id as String).length()) * 0.012
		var z := 0.0
		var sc: float = it.sIn * (1.0 + 0.18 * it.pop * it.pop)
		if s != null and s.phase == "bulge":
			var k := easeOutCubic(s.u / LAND.bulgeDur)
			z = -0.36 * k
			sc *= 1.0 + 0.08 * k
		# each detent opens with 60 ms of snow: the item pops in only once the card is up
		var flash: bool = s != null and s.phase == "spin" and s.u >= SPIN.t0 and s.u - s.detT < SPIN.snowFlash
		var spinning: bool = s != null and s.phase == "spin"
		w.position = Vector3(0, bob, z)
		w.rotation = Vector3(0, sin(t * 3.0) * 0.25 if spinning else sin(t * 0.9) * 0.45, sin(t * 1.3) * 0.04)
		w.scale = Vector3.ONE * (1e-4 if flash else sc)

# ============================================================================================ screen
func _updateScreen(dt: float, t: float) -> void:
	var S = screen
	var s = seq
	if _rollT > 0.0:
		_rollT -= dt
		S.fx.roll = 1.0 - clamp01(_rollT / 0.3)
		if _rollT <= 0.0:
			S.fx.roll = -1.0
	if _exprT > 0.0:
		_exprT -= dt
		if _exprT <= 0.0:
			_exprTemp = null
	var bright := brightBase
	var noise := 0.0
	if s == null:
		var expr: String
		if not awake:
			expr = "zzz"
			bright *= 0.55
		elif _exprTemp != null:
			expr = _exprTemp
		elif _zombieNear or mood == "purple":
			expr = "shiver"
		else:
			expr = "idle" if _near else "zzz"
		if _exprTemp == "baron_glitch":
			noise = 0.25
		S.show("face")
		S.setFace(expr, _gaze(dt) if expr == "idle" else null, t)
	else:
		match s.phase:
			"spin":
				if s.u < SPIN.zip:
					S.show("face")
					S.setFace("o_mouth", null, t)
				elif s.u < SPIN.t0:
					S.show("snow")
				elif s.outcome == "tape" or s.cameoNow:
					S.show("snow" if s.u - s.detT < SPIN.snowFlash else "baron")
				elif s.u - s.detT < SPIN.snowFlash:
					S.show("snow", s.shownCh)
				elif SNOW.has(s.shownCh):
					S.show("snow", s.shownCh)
				else:
					S.show("card", s.shownCh)
				if s.u >= SPIN.t0:
					bright *= 1.0 + 0.25 * maxf(0.0, 1.0 - (s.u - s.detT) / 0.12)
			"land", "bulge", "offer":
				S.show("baron" if s.outcome == "tape" else "card", s.ch)
				if s.phase == "land" and s.u < 0.12:
					bright *= 1.35
			"take", "timeout":
				if (s.u < 0.05) if s.phase == "take" else (s.u < 0.62):
					S.show("baron" if s.outcome == "tape" else "card", s.ch)
				else:
					S.show("face")
					S.setFace(_exprTemp if _exprTemp != null else "idle", _gaze(dt), t)
			"signoff":
				if s.u < SO.card:
					S.show("snow", s.ch)
					noise = 0.55 * (1.0 - s.u / SO.card)
					bright *= 1.2
				elif s.u < SO.unfold:
					S.show("test")
				else:
					S.show("face")
					S.setFace(_exprTemp if _exprTemp != null else "sleepy", null, t)
			"bad":
				if s.u < BAD.gloveOut:
					S.show("snow", s.ch)
					noise = 0.5 * (1.0 - s.u / BAD.gloveOut)
				else:
					S.show("face")
					S.setFace(_exprTemp if _exprTemp != null else "pout", null, t)
			_:
				pass
	S.fx.noise = noise
	if mood == "purple" and s == null and randf() < 0.01:
		bright *= 0.6
	if scrMat != null:
		var cur = _getU(scrMat, "uBright")
		var cb: float = float(cur) if cur != null else brightBase
		_setU(scrMat, "uBright", lerp_(cb, bright, 1.0 - exp(-dt * 25.0)))
	# redraw only when someone can see it (area rendered, within 40 m)
	var par := root.get_parent()
	var areaVis: bool = not (par is Node3D) or (par as Node3D).visible
	if root.visible and areaVis and _pd < 40.0:
		S.render(t)

func _gaze(dt: float) -> Array:
	var p = game.player
	if p == null:
		return [0.0, 0.0]
	var v := DAU.v3(_field(p, "pos"))
	v.y += 1.55
	v = _gxf(root).affine_inverse() * v
	var dx := v.x - PIV.x
	var dy := v.y - PIV.y
	var dz := v.z - PIV.z
	var fwd := maxf(0.5, -dz)
	var tx := clampf(-dx / fwd, -1.0, 1.0)
	var ty := clampf(-dy / Vector2(fwd, dx).length() * 1.4, -1.0, 1.0)
	if _look == null:
		_look = [0.0, 0.0]
	var L: Array = _look
	var a := 1.0 - exp(-dt * 8.0)
	L[0] = lerp_(L[0], tx, a)
	L[1] = lerp_(L[1], ty, a)
	return L

func _updateZzz(dt: float, t: float) -> void:
	var dozing: bool = seq == null and root.visible and (not awake or (not _near and _exprTemp == null and not _zombieNear and mood != "purple"))
	_zzzT -= dt
	if dozing and _zzzT <= 0.0 and _pd < 25.0:
		_zzzT = 1.1
		for z in zzz:
			var u := DAU.ud(z)
			if u.life < 0:
				u.life = 0.0
				u.x = (randf() - 0.5) * 0.08
				z.visible = true
				break
	for z in zzz:
		var u := DAU.ud(z)
		if u.life < 0:
			continue
		u.life += dt / 2.4
		var k: float = u.life
		if k >= 1.0:
			u.life = -1.0
			z.visible = false
			continue
		(z as Node3D).position = Vector3(-0.32 + u.x + sin(k * 7.0) * 0.05 - k * 0.12, 1.36 + k * 0.55, -0.05)
		var sc := 0.07 + 0.1 * k
		(z as Node3D).scale = Vector3(sc, sc, 1.0)
		# one shared SpriteMaterial (as in the JS): the last sprite's opacity / rotation wins
		_zzzMat.set_shader_parameter("opacity", minf(1.0, k * 5.0) * (1.0 - k))
		_zzzMat.set_shader_parameter("rotation", sin(k * 5.0) * 0.3)

# ============================================================================================ lamps & lights
func _lampModeHome(mode: String, flick: bool = false) -> void:
	var h = homes.get(homeId)
	if h == null:
		return
	h.lampMode = mode
	if flick:
		h.flick = 0.5

func setMood(m: String = "normal") -> void:
	mood = "purple" if m == "purple" else "normal"
	var h = homes.get(homeId)
	if h != null and awake:
		h.lampMode = "purple" if mood == "purple" else "full"
	if h != null and mood == "purple":
		h.flick = 0.4
	_glitchT = 2.0

func forceTapePull() -> bool:
	_tapeArmed = true
	return true

func _purpleMats(level: float) -> Array:
	var q := jround(clamp01(level) * 4.0) / 4.0
	var key := "p:%s" % q
	if not _matCache.has(key):
		var mats = game.mats
		_matCache[key] = [
			_invoke(mats, "glow", ["#B45CFF", 0.8 + 3.0 * q]),
			_invoke(mats, "glow", ["#E3AEFF", 0.25 + 0.9 * q]),
			_kitMat(game, "fabric", "#ffffff", {"map": _weave("#9A5AD0"), "mapWrap": "repeat", "side": "double", "emissive": "#B040FF", "emissiveIntensity": 0.55 * q}),
		]
	return _matCache[key]

# Warm lamp (lamp language, GDD §6.7): a lit shade must read from across the room (glowing parchment + bloom), an
# unlit one must look dead (dull, darker fabric, grey bulb). Quantised levels keep the material count tiny.
func _warmMats(level: float) -> Array:
	var q := jround(clamp01(level) * 20.0) / 20.0
	var key := "w:%s" % q
	if _matCache.has(key):
		return _matCache[key]
	var mats = game.mats
	var out: Array
	if q <= 0.0:
		out = [
			_kitMat(game, "ceramic", "#CFC6B4"),
			_kitMat(game, "fabric", "#6E5530"),
			_kitMat(game, "fabric", "#ffffff", {"map": _weave("#BE9442"), "mapWrap": "repeat", "side": "double"}),
		]
	else:
		var warm: String = Config.PAL.gelAmber if q < 0.6 else Config.PAL.tungsten
		out = [
			_invoke(mats, "glow", [warm, 1.2 + 4.0 * q]),
			_invoke(mats, "glow", ["#FFD9A0", 0.35 + 1.25 * q]),
			_kitMat(game, "fabric", "#ffffff", {"map": _weave("#F2C45A"), "mapWrap": "repeat", "side": "double", "emissive": "#FF8A30" if q < 0.6 else "#FFA850", "emissiveIntensity": 0.95 * q}),
		]
	_matCache[key] = out
	return out

func _applyLamps(force: bool = false) -> void:
	for h in homes.values():
		_applyLamp(h, force)

func _applyLamp(h: Dictionary, force: bool = false, level = null) -> void:
	var gm = game
	var target: float
	if level != null:
		target = float(level)
	else:
		target = 1.0 if (h.lampMode == "full" or h.lampMode == "purple") else (0.35 if h.lampMode == "dim" else 0.0)
	var key := "%s:%d" % [h.lampMode, int(jround(target * 20.0))]
	if not force and key == h.lampShown:
		return
	h.lampShown = key
	var purple: bool = h.lampMode == "purple"
	var ms: Array = _purpleMats(target) if purple else _warmMats(target)
	var LP := _partsGeneric(h.lamp, ["bulb", "lining", "shade"])
	var names := ["bulb", "lining", "shade"]
	for i in 3:
		var part = LP.get(names[i])
		if part is GeometryInstance3D and ms[i] is Material:
			(part as GeometryInstance3D).material_override = ms[i]
	DAU.ud(h.lamp)["lampLevel"] = target
	if purple:
		_invoke(gm.lights, "setAnchor", [h.lampId, {"color": "#A54CFF", "intensity": 2.2 * target, "flicker": 0.5}])
	else:
		_invoke(gm.lights, "setAnchor", [h.lampId, {"color": Config.PAL.gelAmber if target < 0.6 else Config.PAL.tungsten, "intensity": 2.0 * target, "flicker": 0}])
	if h.pool != null:
		_invoke(h.pool, "set", [{"color": "#B45CFF" if purple else ("#FFB060" if target < 0.6 else "#FFD08A"), "intensity": (0.34 if purple else 0.3) * target}])

func _updateLamps(dt: float, t: float) -> void:
	for h in homes.values():
		if h.flick > 0.0:
			h.flick -= dt
			var on: bool = sin(h.flick * 70.0) > -0.2 or h.flick < 0.05
			var base := 0.0 if h.lampMode == "off" else (0.35 if h.lampMode == "dim" else 1.0)
			_applyLamp(h, false, ((0.5 if on else 0.0) if h.lampMode == "off" else (base if on else base * 0.15)))
			if h.flick <= 0.0:
				_applyLamp(h, true)
		elif h.lampMode == "purple":
			var k := 0.55 + 0.45 * (1.0 if sin(t * 13.0) * sin(t * 7.3) > 0.1 else 0.4)
			_applyLamp(h, false, jround(k * 4.0) / 4.0)
		else:
			_applyLamp(h)

func _updateAnchors(dt: float) -> void:
	var gm = game
	var s = seq
	var vis: bool = root.visible and homeId != null
	var level := 0.0
	if vis:
		level = 0.7 if awake else 0.18
		if s != null and s.phase == "spin" and s.u >= SPIN.t0:
			level = 1.2 + 0.6 * maxf(0.0, 1.0 - (s.u - s.detT) / 0.15)
		elif s != null and (s.phase == "land" or s.phase == "bulge" or s.phase == "offer"):
			level = 1.3
		elif s != null and s.phase == "signoff" and s.u >= SO.off:
			level = 0.0
	_glowLevel = lerp_(_glowLevel, level, 1.0 - exp(-dt * 12.0))
	# spill colour follows what is on screen (snappy on detents, soft otherwise)
	var S = screen
	var want: String = CH_GLOW.get(S.ch, GLOW_CRT) if S.kind == "card" else KIND_GLOW.get(S.kind, GLOW_CRT)
	if _glowCol == null:
		_glowCol = Color(GLOW_CRT).srgb_to_linear()
	var gc: Color = _glowCol
	gc = gc.lerp(Color(want).srgb_to_linear(), 1.0 - exp(-dt * (30.0 if s != null and s.phase == "spin" else 8.0)))
	_glowCol = gc
	var gs := gc.linear_to_srgb()
	var v := _worldPoint(Vector3(0.12, 0.9, -0.85))
	if glowAnchor != null:
		if glowAnchor is Dictionary or glowAnchor is Object:
			glowAnchor.pos = v
			var h = homes.get(homeId)
			if (glowAnchor is Dictionary and glowAnchor.has("area")) or (glowAnchor is Object and "area" in glowAnchor):
				if h != null:
					glowAnchor.area = h.area
		_invoke(gm.lights, "setAnchor", ["telly_screen", {"intensity": _glowLevel * 1.1, "color": gs}])
	if pool != null:
		_invoke(pool, "set", [{"pos": Vector3(v.x, 0.02, v.z), "intensity": _glowLevel * 0.22, "color": gs}])
	if act != null and vis and s == null:
		act.pos = _worldPoint(Vector3(0.12, 0.9, -0.55))
	if hum != null and vis:
		_invoke(hum, "setPos", [root.position])

# ============================================================================================ utils
# mat.uniforms.<name>.value (DAMaterial facade: also reaches its two-pass twin) or the plain shader parameter.
static func _setU(mat: Material, name: String, v) -> void:
	if mat == null:
		return
	var U = mat.get("uniforms")
	if U is Dictionary and U.get(name) != null and "value" in U[name]:
		U[name].value = v
	elif mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(name, v)

static func _getU(mat: Material, name: String):
	if mat == null:
		return null
	var U = mat.get("uniforms")
	if U is Dictionary and U.get(name) != null and "value" in U[name]:
		return U[name].value
	if mat is ShaderMaterial:
		return (mat as ShaderMaterial).get_shader_parameter(name)
	return null

func _worldPoint(local: Vector3) -> Vector3:
	return _gxf(root) * local

func _fwd() -> Vector3:
	var y := root.rotation.y
	return Vector3(-sin(y), 0, -cos(y))

func _audio() -> Vector3:
	return _worldPoint(Vector3(0.12, 0.9, -0.3))

func _play(id: String, o: Dictionary = {}):
	var a = game.audio
	if not _hasm(a, "play"):
		return null
	var rest := o.duplicate()
	var at = rest.get("at")
	rest.erase("at")
	var opts := {"pos": DAU.v3(at) if at != null else _audio()}
	opts.merge(rest, true)
	return _invoke(a, "play", [id, opts])


# ============================================================================================ MP (online co-op)
# See the header's MP paragraph. Every function here is reached only with game.net.inGame (solo never calls them).
func _mp() -> bool:
	var n = game.get("net")
	return n != null and n.inGame

func _cli() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isClient

func _hst() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isHost

func _me() -> int:
	return int(game.net.localId) if _mp() else 0

# by == the local player (solo: always; 0 = local)
func _isMe(by) -> bool:
	return by == 0 or not _mp() or int(by) == int(game.net.localId)

# The player-like of peer `by` (0 / solo = game.player; null when that peer is gone).
func _pl(by):
	if by == null or int(by) == 0 or not _mp():
		return game.player
	return game.net.playerById(int(by))

func _fromHost() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.sender == 1

# pull() in MP, on the user's peer: spend (the reservation), then ask the host. The host's own pulls go the same way.
func _pullMP(opts) -> bool:
	var o: Dictionary = opts if opts is Dictionary else {}
	if _reqT >= 0.0 or not canPull():
		return false
	var morning: bool = bool(o.get("morning", false))
	var cost := 0 if bool(o.get("free", false)) else int(o.get("cost", 13 if morning else COST))
	if cost > 0:
		var eco = game.economy
		if eco == null or not _invoke(eco, "spend", [cost, "telly"]):
			squash.kick(-2)
			_tempExpr("pout", 0.8)
			return false
	var owned: Array = []
	var w = game.weapons
	var slots = _field(w, "slots")
	if slots is Array:
		for sl in slots:
			if sl != null and _field(sl, "id") != null:
				owned.append(str(_field(sl, "id")))
	var ex = o.get("exclude")
	if ex is Array:
		for x in ex:
			if not owned.has(str(x)):
				owned.append(str(x))
	var forced = o.get("forced")
	_reqT = 5.0
	_reqCost = cost
	game.net.toHost("telly", "pull", [cost, owned, int(_num(_field(w, "teles", 0))), str(forced) if forced != null else "", morning])
	return true

# client -> host: a pull request (the client already paid `cost`).
func net_pull(cost, owned, teles, forced, isMorning) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient:
		return
	var by: int = n.sender
	if not canPull() or not (owned is Array):
		n.toPeer(by, "telly", "deny", [int(cost)])
		return
	var f = null
	if str(forced) != "" and game.params.get("test"):
		f = str(forced)
	_exclCtx = {"owned": owned, "teles": int(teles) if (teles is int or teles is float) else 0}
	if isMorning == true and morning and f == null:
		var en = game.get("ending")
		if en != null and en.has_method("rollTelly"):
			f = en.rollTelly(owned)
	pulls += 1
	pullsHere += 1
	var r := _roll(f)
	var start := _dialCh()
	_beginSpin(r, start, -2, int(cost), by)
	_seqId += 1
	seq.id = _seqId
	seq.excl = _exclCtx
	_exclCtx = null
	if by == n.localId:
		_reqT = -1.0
	n.toAll("telly", "spin", [by, _seqId, str(r.outcome), str(r.item) if r.item != null else "", int(r.ch), start,
		int(seq.cameo), int(cost), pulls, pullsHere])

# host -> requester: the pull was refused (Telly busy / asleep): give the reservation back.
func net_deny(cost) -> void:
	if not _fromHost():
		return
	_reqT = -1.0
	_refund(int(cost), "telly")
	squash.kick(-2)
	_tempExpr("pout", 0.8)

func _refund(n: int, reason: String) -> void:
	var eco = game.economy
	if n <= 0 or eco == null:
		return
	if _hasm(eco, "refund"):
		_invoke(eco, "refund", [n, reason])
	else:
		_invoke(eco, "add", [n, reason])

# host -> clients: a pull starts (the host already runs it).
func net_spin(by, id, outcome, item, ch, startCh, cameo, cost, pulls_, here) -> void:
	if not _fromHost() or not built:
		return
	if int(by) == _me():
		_reqT = -1.0
	if seq != null:
		_endSeq(true)
	pulls = int(pulls_)
	pullsHere = int(here)
	var sc := int(startCh)
	if _dialCh() != sc and DIAL_ORDER.has(sc):
		dial.idx = DIAL_ORDER.find(sc)
		var a := setTellyDial(g, sc)
		dial.angle = a
		dial.from = a
		dial.to = a
		dial.t = 1.0
	var r := {"outcome": str(outcome), "item": str(item) if str(item) != "" else null, "ch": int(ch)}
	_beginSpin(r, sc, int(cameo), int(cost), int(by))
	seq.id = int(id)

# host -> clients: the host's landing (a client holds its last detent until it arrives).
func net_land(id, outcome, item, ch) -> void:
	var s = seq
	if not _fromHost() or s == null or int(id) != int(s.id) or s.phase != "spin":
		return
	s.landMsg = [str(outcome), str(item) if str(item) != "" else null, int(ch)]

# Host: a hit on Telly (weapons runs shootable onHit on the host with info.by; a client without that path forwards).
func _onHitMP(info: Dictionary) -> void:
	var n = game.net
	if n.isClient:
		if info.get("melee", false):
			n.toHost("telly", "hit", [true, DAU.v3(info.point) if info.get("point") != null else Vector3.ZERO])
		return
	var hitter := int(info.get("by", n.sender))
	var s = seq
	if not info.get("melee", false):
		if _clock - _tinkT > 0.07:
			_tinkT = _clock
			n.everyone("telly", "tink", [DAU.v3(info.point) if info.get("point") != null else root.position + Vector3(0, 1, 0)])
		return
	if _clock - _smackT < 0.35:
		return
	_smackT = _clock
	if s != null and s.phase == "spin" and s.outcome == "tape":
		n.everyone("telly", "smack", [hitter, "catch"])
		return
	if s != null and s.phase == "offer":
		n.everyone("telly", "smack", [hitter, "catch" if s.outcome == "tape" else "bop"])
		return
	if s != null and s.phase == "spin" and not s.bumped and s.t >= WINDOW[0] and s.t < WINDOW[1]:
		_exclCtx = s.excl
		var r := _bumpResolve(s)
		_exclCtx = null
		n.everyone("telly", "bump", [hitter, int(s.id), r[0], r[1], str(r[2]), str(r[3]) if r[3] != null else "", r[4]])
		return
	if s == null or s.phase == "spin" or s.phase == "land":
		n.everyone("telly", "smack", [hitter, "hey"])

# client -> host (fallback while weapons runs onHit on clients): a melee hit.
func net_hit(melee, point) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.isClient or not built or homeId == null or not root.visible:
		return
	_onHitMP({"melee": bool(melee), "point": point, "by": n.sender})

# host -> all: bullets "tink" (cosmetic).
func net_tink(point) -> void:
	if not _fromHost() or not built or homeId == null:
		return
	var s = seq
	_play("smile_ting", {"vol": 0.7, "rate": 1.5 + randf() * 0.3, "at": point})
	_invoke(game.fx, "burst", [DAU.v3(point), {"shape": "spark", "count": 5, "speed": 3, "size": 0.03, "life": 0.2}])
	if s == null or s.phase == "spin" or s.phase == "land":
		_tempExpr("glare", 1.2)
	squash.kick(-0.4)

# host -> all: a melee reaction ("hey" | "bop" | "catch").
func net_smack(hitter, kind) -> void:
	if not _fromHost() or not built or homeId == null:
		return
	var h := int(hitter)
	match str(kind):
		"catch":
			_catchHand()
		"bop":
			_bopBack(h)
		_:
			_play("telly_hey")
			_tempExpr("glare", 1.4)
			squash.kick(-2.2)
			_jolt(0.05)
			if _isMe(h):
				_invoke(game.cam, "shake", [0.08, 0.15])

# host -> all: a resolved percussive-maintenance bump.
func net_bump(hitter, id, fromCh, ch, outcome, item, extra) -> void:
	var s = seq
	if not _fromHost() or s == null or int(id) != int(s.id) or s.phase != "spin" or s.bumped:
		return
	_bumpApply(s, int(fromCh), int(ch), str(outcome), str(item) if str(item) != "" else null, int(extra), int(hitter))

# client -> host: the user takes the offered item.
func net_take(id) -> void:
	var n = game.get("net")
	var s = seq
	if n == null or not n.inGame or n.isClient or s == null or int(id) != int(s.id):
		return
	if s.phase != "offer" or s.orphan or int(s.by) != n.sender or s.u < OFFER.out * 0.6:
		return
	n.everyone("telly", "took", [int(s.id)])

# host -> all: the take happens (weapon / reel only on the user's peer).
func net_took(id) -> void:
	var s = seq
	if not _fromHost() or s == null or int(id) != int(s.id):
		return
	if s.phase == "land" or s.phase == "bulge":
		_ploop(s)
	if s.phase != "offer":
		return
	_doTake(s)

# host -> all: the offer ended (user too late, down or gone).
func net_timeout(id) -> void:
	var s = seq
	if not _fromHost() or s == null or int(id) != int(s.id):
		return
	if s.phase == "land" or s.phase == "bulge":
		_ploop(s)
	if s.phase == "offer":
		_doTimeout(s)

# host -> clients: the sign-off destination (picked at SO.off with game.rand()).
func net_dest(id, dest) -> void:
	var s = seq
	if not _fromHost() or s == null or int(id) != int(s.id) or not homes.has(str(dest)):
		return
	s.dest = str(dest)

# EE (mp-story): host API, re-arms the tape pull after its carrier went off-air / left. Replicated.
func rearmTape() -> bool:
	if _cli():
		return false
	if _hst():
		game.net.everyone("telly", "rearm", [])
	else:
		net_rearm()
	return true

func net_rearm() -> void:
	if _mp() and not _fromHost():
		return
	if tapeReel != null and is_instance_valid(tapeReel):
		DAU.detach(tapeReel)
		tapeReel.queue_free()
	tapeReel = null
	tapeHolder = 0
	if items.get(TAPE_ID) == null:
		var reel := buildTapeReel(game)
		if reel != null:
			items[TAPE_ID] = _wrapItem(TAPE_ID, reel)
	setMood("purple")
	forceTapePull()

# machines.net_sync: the host's start home (reset-time game.rand() pick).
func netHome(id: String) -> void:
	if not built or seq != null or not homes.has(id) or id == homeId:
		return
	var from = homes.get(homeId)
	if from != null:
		from.lampMode = "off"
	_placeAt(id)
	homes[id].lampMode = ("purple" if mood == "purple" else "full") if awake else "dim"
	_applyLamps(true)
	if _field(game.nav, "built"):
		_invoke(game.nav, "build")

# machines dispatch: net:peer left / team:down / team:offair of `id`. Host: the user's pull is orphaned (nobody can
# take it; the offer ends within a second). Every peer: a gone requester's pending state is cleared.
func onPeerGone(id: int, why: String = "left") -> void:
	var s = seq
	if _hst() and s != null and int(s.by) == id:
		s.orphan = true
	if why == "left" and tapeHolder == id:
		tapeHolder = 0

# requester: a pending pull without any answer (5 s) is refunded.
func _updateReq(dt: float) -> void:
	if _reqT < 0.0:
		return
	_reqT -= dt
	if _reqT < 0.0:
		push_warning("[telly] pull request timed out (refunded)")
		_refund(_reqCost, "telly")

# ============================================================================================ debug
func debugPull(outcome = null, opts = {}) -> bool:
	if not built:
		return false
	var free: bool = bool(opts.get("free", false)) if opts is Dictionary else false
	if not awake and _field(game.machines, "powerOn", false):
		debugWake()
	var pay: bool = not free and _num(_field(game.economy, "points", 0), 0.0) >= COST
	return pull({"free": not pay, "forced": outcome})

func debugBump():
	_smackT = -1.0
	onHit({"melee": true})
	return {"bumped": seq.bumped, "outcome": seq.outcome, "item": seq.item, "ch": seq.ch} if seq != null else null

func debugHit(info = {"melee": true}) -> bool:
	_smackT = -1.0
	onHit(info)
	return true

func debugTake() -> bool:
	return take()

func debugWake() -> bool:
	if homeId == null:
		return false
	_powerAt = -1.0
	if not awake:
		awake = true
		phase = "idle"
		_lampModeHome("purple" if mood == "purple" else "full", true)
		_hopNow(0.16)
		_play("telly_wake")
		_tempExpr("happy", 1.0)
	return true

func debugMove(id) -> bool:
	if not homes.has(id) or seq != null:
		return false
	var from = homes.get(homeId)
	if from != null:
		from.lampMode = "off"
	_placeAt(id)
	homes[id].lampMode = ("purple" if mood == "purple" else "full") if awake else "dim"
	pullsHere = 0
	_applyLamps(true)
	if _field(game.nav, "built"):
		_invoke(game.nav, "build")
	return true

func debugFreezeAt(t = null):
	_freezeAt = null if t == null else float(t)
	return _freezeAt

func debugState() -> Dictionary:
	var s = seq
	var lamps := {}
	for h in homes.values():
		lamps[h.id] = h.lampMode
	return {
		"homeId": homeId, "state": state, "phase": phase, "awake": awake, "mood": mood, "pulls": pulls,
		"pullsHere": pullsHere, "pity": pity, "tapeArmed": _tapeArmed, "dial": _dialCh(), "near": _near,
		"seq": {"t": snappedf(s.t, 0.001), "u": snappedf(s.u, 0.001), "phase": s.phase, "outcome": s.outcome, "item": s.item, "ch": s.ch,
			"shown": s.shownCh, "landT": snappedf(s.landT, 0.001), "bumped": s.bumped, "N": s.N, "passed": s.passed, "dest": s.dest} if s != null else null,
		"lamps": lamps,
	}
