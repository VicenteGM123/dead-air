class_name RigHeracles
extends Rig
## Heracles: a skinned code rig (Skeleton3D, 30 bones) about 1.9 m tall: bare-headed (short wavy hair, a faceless face),
## bare-chested, a linen kilt, the red cape (cloth: one bone per particle) under a mantle pinned by a gold brooch, the
## round shield on the left forearm, the sword in the right hand
## and the chain spear on the back; the lion outfit (hood and pelt) after the first labour. Built by the HERO
## stream, owned and tuned for combat by CORE.
## API (docs/ARCHITECTURE.md 5.7): set_locomotion, set_motion_state (&"ground" &"air" &"swim" &"zip" &"hang"),
## set_vertical_speed, set_guard, set_outfit, set_spear_on_back, play(action) -> length, event(name) with impact,
## swing, release, pull, step...; hand_r(), hand_l(), chain_origin(), head(), grapple_point().
## CORE additions: play_at(action, speed, upper) (upper: the legs keep the locomotion), action_hold (hold an
## action at a key: the heavy blow's charge), stop_action(), charge / tired (tremble, winded), guard_impact(k)
## (a blow on the shield), blade_segment() (the sword in world space), a strafing / back-pedalling gait, the hang
## pose, and the recoil / backstep actions. Clip check: tools/clip_check_heracles.tscn.

# --- palette -----------------------------------------------------------------------------------------------
# LOOK: warm orange-tan skin (SKIN_SHADE: the creases' gentle vertex shading, SKIN_LIGHT: the upper planes)
const SKIN := Color("E0A35F")
const SKIN_DARK := Color("B97B47")
const SKIN_SHADE := Color("CD8F55")
const SKIN_LIGHT := Color("E9B26F")
const BRONZE := Color("D19A44")
const BRONZE_DARK := Color("9C6B2E")
const BRONZE_LIGHT := Color("EFC172")
const RED := Color("B8302A")
const RED_DARK := Color("8C2226")
# LOOK: short wavy hair (dark brown, the upper faces of the locks lighter)
const HAIR := Color("5E3722")
const HAIR_DARK := Color("3B2217")
const HAIR_LIGHT := Color("87562F")
# LOOK: the linen kilt, the deep red mantle and its gold brooch
const LINEN := Color("F2DAAA")
const LINEN_SHADE := Color("DEC18E")
const LINEN_DARK := Color("B49F79")
## LOOK2: the kilt's ambient in the shade: how much of the sky's blue it keeps, and a warm tint (see lowpoly.gdshader).
const KILT_AMB_SAT := 0.15
const KILT_AMB_TINT := Vector3(1.15, 1.1, 1.0)
const CAPE := Color("8C3329")
const CAPE_DARK := Color("62221F")
const CAPE_LIGHT := Color("9E3B2E")
const GOLD := Color("E2AE45")
const GOLD_LIGHT := Color("F6D584")
const GOLD_DARK := Color("A77629")
const LEATHER := Color("7C4A2C")
const LEATHER_DARK := Color("4E2C1C")
const LEATHER_LIGHT := Color("9C6238")
const SHADOW := Color("1E1824")
const STEEL := Color("CCD5DE")
const STEEL_DARK := Color("8D98A8")
const STEEL_LIGHT := Color("EEF3F7")
const WOOD := Color("5A3A28")
const WOOD_DARK := Color("432A1E")
# LOOK: the round shield's leather face (two browns) and its dark iron-brown rim
const SHIELD_FACE := Color("7A4A2D")
const SHIELD_FACE_LIGHT := Color("94603A")
const SHIELD_FACE_DARK := Color("5E3823")
const SHIELD_RIM := Color("4E3626")
const SHIELD_RIM_LIGHT := Color("6E4E36")
const IRON := Color("5B6070")
## CORE: the darker bronze of the chain links (alternating with BRONZE_DARK).
const CHAIN_DARK := Color("7A5226")
const IRON_DARK := Color("3F4352")
const CREAM := Color("F0E6CF")
const INK := Color("2A2430")
# the Nemean lion's coat (same colours as RigLion's COAT, so the pelt matches the beast)
const FUR := Color("B2935A")
const FUR_LIGHT := Color("DCC497")
const FUR_DARK := Color("9C7C45")
const MUZZLE := Color("D6BE90")
const NOSE := Color("8C5446")
const PAW := Color("BC9D62")
const MANE := Color("4A2D1C")
const MANE_DARK := Color("3A2416")
const MANE_LIGHT := Color("63402A")

# --- skeleton ----------------------------------------------------------------------------------------------
enum { PELVIS, SPINE, CHEST, NECK, HEAD, CLAV_R, UARM_R, FARM_R, HAND_R, CLAV_L, UARM_L, FARM_L, HAND_L,
	THIGH_R, SHIN_R, FOOT_R, THIGH_L, SHIN_L, FOOT_L, PAUL_R, PAUL_L, CREST_B, SKIRT0 }
const SKIRT_N := 8
const NB := SKIRT0 + SKIRT_N

# Rest joint positions (rig space, right side; the left side mirrors x).
const P_PELVIS := Vector3(0.0, 0.99, 0.0)
const P_SPINE := Vector3(0.0, 1.11, 0.01)
const P_CHEST := Vector3(0.0, 1.30, 0.0)
const P_NECK := Vector3(0.0, 1.555, 0.015)
const P_HEAD := Vector3(0.0, 1.635, 0.005)
const P_CLAV := Vector3(0.055, 1.50, 0.015)
const P_SHOULDER := Vector3(0.255, 1.475, 0.02)
const P_ELBOW := Vector3(0.295, 1.17, 0.035)
const P_WRIST := Vector3(0.315, 0.90, 0.005)
const P_HIP := Vector3(0.112, 0.93, 0.0)
const P_KNEE := Vector3(0.12, 0.505, -0.018)
const P_ANKLE := Vector3(0.125, 0.093, 0.012)
const HEAD_C := Vector3(0.0, 1.75, 0.005) # head centre (the head() node; the lion hood is placed from it)
const P_CREST := Vector3(0.0, 1.90, 0.02)
const SKIRT_Y := 1.0
const SKIRT_R := 0.19
## Fist centre (where the sword grip passes) in hand space, from the wrist.
const GRIP := Vector3(0.0, -0.104, 0.0)
## Hands are drawn this much bigger than life (heroic proportions).
const HAND_K := 1.18
## LOOK2: and grown this much more round the grip (the reference's big fists).
const HAND_GROW := 1.12
const FWD := Vector3(0.0, 0.0, -1.0)
const SHIELD_R := 0.39
## The left fist holds the spear this far towards its head from the spear's own origin.
const SPEAR_HOLD := 0.22
## The direction (chest space) the spear's local x axis lies along on the back, the leaf's broad side being the way across it.
const SPEAR_ROLL := Vector3(0.12, 0.11, 1.01)
const SPEAR_ROLL_LION := Vector3(0.0, 0.0, 1.0)
## don_skin: when the pelt replaces the cape and when the paws are knotted on the chest (s).
const DON_SWAP := 0.78
const DON_KNOT := 1.62
## throw: the left hand closes on the shaft (the spear leaves the back) and lets it go (s).
const THROW_GRAB := 0.20
const THROW_RELEASE := 0.47
## CORE: "catch" (the spear flying home into the left fist): the fist swings it onto the back at this key.
const CATCH_STOW := 0.24
## Centre of the wrestling hold (rig space): the beast's neck goes here during grapple_*.
const GRAPPLE_HOLD := Vector3(0.0, 1.17, -0.43)

static var LEN_UA := P_SHOULDER.distance_to(P_ELBOW)
static var LEN_FA := P_ELBOW.distance_to(P_WRIST)
static var LEN_TH := P_HIP.distance_to(P_KNEE)
static var LEN_SH := P_KNEE.distance_to(P_ANKLE)

static var _cache := {}

# --- pose channels -----------------------------------------------------------------------------------------
## A pose is a PackedFloat32Array; these are the offsets of its channels (3 floats each unless noted).
enum { C_PEL = 0, C_PELR = 3, C_SPN = 6, C_CHS = 9, C_NEK = 12, C_HED = 15, C_HR = 18, C_HRB = 21, C_HRK = 24,
	C_HRP = 27, C_HL = 30, C_HLF = 33, C_HLP = 36, C_HLW = 39, C_FR = 42, C_FRR = 45, C_FRP = 48, C_FL = 51,
	C_FLR = 54, C_FLP = 57, C_ROT = 60, C_PIV = 63, C_GRIP = 66, C_OHL = 67, C_SPR = 68, C_HOOD = 69, C_HLB = 70,
	C_HLK = 73, C_HLX = 76, C_HLS = 77, C_HRS = 78, C_HLR = 79, C_HRR = 80, C_N = 81 }
## pel/pelr/spn/chs/nek/hed: pelvis offset + Euler (x pitch, + leans back; y yaw, + turns left; z roll) and the
## spine bones' Euler. hr: right grip (chest space), hrb blade direction, hrk back of the hand, hrp elbow pole.
## hl: left wrist (chest space), hlf where the shield faces, hlp elbow pole, hlw wrist Euler; hlb/hlk an explicit
## left hand basis (spear held: hlb = spear direction) weighted by hlx (hl is then the fist's place, with the roll hlk, and the hand's own roll about hlb is
## hlr: 1 as authored (hlk), 0 the one that keeps the wrist straight: the fist closes on the shaft however the forearm lies). hrs/hls: 1 puts that hand's targets in rig
## space (before `rot`) instead of chest space. fr/fl ankles, frr/flr foot Euler, frp/flp knee poles (rig space).
## rot: whole-body rotation vector about piv. grip: sword roll in the fist. ohl: open left hand. hood: lion hood
## (0 down on the back .. 1 on the head).
const CH := {"pel": C_PEL, "pelr": C_PELR, "spn": C_SPN, "chs": C_CHS, "nek": C_NEK, "hed": C_HED, "hr": C_HR,
	"hrb": C_HRB, "hrk": C_HRK, "hrp": C_HRP, "hl": C_HL, "hlf": C_HLF, "hlp": C_HLP, "hlw": C_HLW, "fr": C_FR,
	"frr": C_FRR, "frp": C_FRP, "fl": C_FL, "flr": C_FLR, "flp": C_FLP, "rot": C_ROT, "piv": C_PIV, "grip": C_GRIP,
	"ohl": C_OHL, "spr": C_SPR, "hood": C_HOOD, "hlb": C_HLB, "hlk": C_HLK, "hlx": C_HLX, "hls": C_HLS, "hrs": C_HRS, "hlr": C_HLR, "hrr": C_HRR}

## Neutral stance (hands in chest space, feet in rig space).
const NEUTRAL := {
	"pel": Vector3(0.0, -0.035, 0.0), "pelr": Vector3(0.02, 0.0, 0.0), "spn": Vector3(0.0, 0.0, 0.0),
	"chs": Vector3(0.05, 0.0, 0.0), "nek": Vector3(-0.05, 0.0, 0.0), "hed": Vector3(0.0, 0.0, 0.0),
	"hr": Vector3(0.33, -0.44, 0.0), "hrb": Vector3(0.29, -0.62, 0.73), "hrk": Vector3(0.7, 0.05, -0.7),
	"hrp": Vector3(0.5, 0.0, 1.0),
	"hl": Vector3(-0.335, -0.36, -0.08), "hlf": Vector3(-1.0, 0.0, -0.35), "hlp": Vector3(-0.5, -0.2, 1.0),
	"hlw": Vector3.ZERO,
	"fr": Vector3(0.15, 0.093, 0.04), "frr": Vector3(0.0, -0.18, 0.0), "frp": Vector3(0.25, 0.0, -1.0),
	"fl": Vector3(-0.15, 0.093, -0.06), "flr": Vector3(0.0, 0.18, 0.0), "flp": Vector3(-0.25, 0.0, -1.0),
	"rot": Vector3.ZERO, "piv": Vector3(0.0, 0.9, 0.0), "grip": 0.0, "ohl": 0.0, "spr": 0.0, "hood": 1.0,
	"hlb": Vector3(0.0, 0.0, -1.0), "hlk": Vector3(-1.0, 0.0, 0.0), "hlx": 0.0, "hls": 0.0, "hrs": 0.0, "hlr": 1.0, "hrr": 1.0,
}

# --- state -------------------------------------------------------------------------------------------------
var skel: Skeleton3D
var outfit := &"helmet"
var spear_on_back := true
var guard := false
var motion_state := &"ground"
var vspeed := 0.0
## Posed bone transforms (rig space) and their rest origins.
var _bx: Array[Transform3D] = []
var _rest: Array[Vector3] = []
var _pose := PackedFloat32Array()
var _mat_soft: ShaderMaterial
var _mat_metal: ShaderMaterial
var _mesh_nodes: Array[MeshInstance3D] = []
## Skinning pivots (rest-space children follow their bone) and API attachment nodes.
var _piv := {}
var _hand_r: Node3D
var _hand_l: Node3D
var _head: Node3D
var _sword: Node3D
var _fist_l: MeshInstance3D
var _open_l: MeshInstance3D
var _helmet_mi: Array[MeshInstance3D] = []
var _spear_back: Node3D
var _spear_hand: Node3D
var _shield_mi: Array[MeshInstance3D] = []
## CORE: the sword and the shield are laid aside (set_weapons_aside).
var weapons_aside := false
var _don_hide := false
## CORE: the cape stays in front of walls behind him and over rising ground (two rays and one down per frame);
## tools without a world can switch it off.
var cape_world := true
## LOOK: no helmet and no crest any more: _crest_mi is an empty hidden node (tools ask for it), _helm_mi the head,
## _hair_mi the hair.
var _crest_mi: MeshInstance3D
var _helm_mi: MeshInstance3D
var _hair_mi: MeshInstance3D
var _mat_helm: ShaderMaterial
var _mat_kilt: ShaderMaterial
var _hood_mi: MeshInstance3D
var _paws_mi: MeshInstance3D
var _collar_mi: Array[MeshInstance3D] = []
## What the outfit looks like right now (don_skin switches it part-way through).
var _show_lion := false
var _show_hood := 1.0
var _show_paws := false
var _don_from_helmet := false
var _helm_shade := -1.0
var _spear_lion := false
# Rest frames of the limb bones (right, left).
var _f0_ua: Array[Basis] = []
var _f0_fa: Array[Basis] = []
var _f0_th: Array[Basis] = []
var _f0_sh: Array[Basis] = []


func _init() -> void:
	super()
	name = "Heracles"
	_mat_soft = Materials.lowpoly().duplicate() as ShaderMaterial
	_mat_metal = Materials.lowpoly().duplicate() as ShaderMaterial
	_mat_metal.set_shader_parameter("metal", 1.0)
	# LOOK: the head and the hair have their own copy: under the lion hood the face sinks into its shade
	_mat_helm = _mat_soft.duplicate() as ShaderMaterial
	# LOOK2: and the linen kilt: a neutral, slightly warm ambient in its shade (lowpoly.gdshader amb_sat / amb_tint)
	_mat_kilt = _mat_soft.duplicate() as ShaderMaterial
	_mat_kilt.set_shader_parameter("amb_sat", KILT_AMB_SAT)
	_mat_kilt.set_shader_parameter("amb_tint", KILT_AMB_TINT)
	_init_rest()
	_build()
	_pose = default_pose()
	_solve(_pose)
	_apply_bones()


# --- rest skeleton -----------------------------------------------------------------------------------------

static func mx(v: Vector3, s: float) -> Vector3:
	return Vector3(v.x * s, v.y, v.z)


static func perp(v: Vector3, axis: Vector3) -> Vector3:
	return v - axis * v.dot(axis)


## Orthonormal frame with +Y along `y` and +Z as close as possible to `z_hint`.
static func frame(y: Vector3, z_hint: Vector3) -> Basis:
	y = y.normalized()
	var z := perp(z_hint, y)
	if z.length_squared() < 1e-8:
		z = perp(Vector3.BACK, y)
	z = z.normalized()
	return Basis(y.cross(z), y, z)


func _init_rest() -> void:
	_rest.resize(NB)
	_bx.resize(NB)
	_rest[PELVIS] = P_PELVIS
	_rest[SPINE] = P_SPINE
	_rest[CHEST] = P_CHEST
	_rest[NECK] = P_NECK
	_rest[HEAD] = P_HEAD
	_rest[CREST_B] = P_CREST
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var o := 0 if side == 0 else 4
		_rest[CLAV_R + o] = mx(P_CLAV, s)
		_rest[UARM_R + o] = mx(P_SHOULDER, s)
		_rest[FARM_R + o] = mx(P_ELBOW, s)
		_rest[HAND_R + o] = mx(P_WRIST, s)
		var lo := 0 if side == 0 else 3
		_rest[THIGH_R + lo] = mx(P_HIP, s)
		_rest[SHIN_R + lo] = mx(P_KNEE, s)
		_rest[FOOT_R + lo] = mx(P_ANKLE, s)
		_rest[PAUL_R + side] = mx(P_SHOULDER, s)
		var ua := frame(mx(P_ELBOW, s) - mx(P_SHOULDER, s), FWD)
		_f0_ua.append(ua)
		var yf := (mx(P_WRIST, s) - mx(P_ELBOW, s)).normalized()
		_f0_fa.append(Basis(ua.x, yf, ua.x.cross(yf)))
		var th := frame(mx(P_KNEE, s) - mx(P_HIP, s), FWD)
		_f0_th.append(th)
		var ys := (mx(P_ANKLE, s) - mx(P_KNEE, s)).normalized()
		_f0_sh.append(Basis(th.x, ys, th.x.cross(ys)))
	for i in SKIRT_N:
		var a := TAU * float(i) / float(SKIRT_N)
		_rest[SKIRT0 + i] = Vector3(sin(a) * SKIRT_R, SKIRT_Y, -cos(a) * SKIRT_R)
	for i in NB:
		_bx[i] = Transform3D(Basis.IDENTITY, _rest[i])


# --- skinned mesh builder ----------------------------------------------------------------------------------

## Two MeshBuilders (soft: skin, cloth, leather / metal: bronze) whose vertices are bound to up to four bones.
class SkinMesh:
	var soft: MeshBuilder
	var metal: MeshBuilder
	var bs := PackedInt32Array()
	var ws := PackedFloat32Array()
	var bm := PackedInt32Array()
	var wm := PackedFloat32Array()

	func _init(seed_value: int) -> void:
		soft = MeshBuilder.new(seed_value)
		metal = MeshBuilder.new(seed_value + 7)

	## Binds every vertex added since the last call with fn(rest_pos) -> [b0, w0, b1, w1, ...] (PackedFloat32Array).
	func bind(fn: Callable) -> void:
		_bind(soft, bs, ws, fn)
		_bind(metal, bm, wm, fn)

	func rigid(bone: int) -> void:
		var r := PackedFloat32Array([float(bone), 1.0])
		bind(func(_p: Vector3) -> PackedFloat32Array: return r)

	static func _bind(mb: MeshBuilder, b: PackedInt32Array, w: PackedFloat32Array, fn: Callable) -> void:
		var v := mb._v
		var start := b.size() / 4
		for i in range(start, v.size()):
			var r: PackedFloat32Array = fn.call(v[i])
			var tot := 0.0
			for k in range(1, r.size(), 2):
				tot += r[k]
			for k in 4:
				if k * 2 + 1 < r.size():
					b.append(int(r[k * 2]))
					w.append(r[k * 2 + 1] / maxf(tot, 1e-5))
				else:
					b.append(0)
					w.append(0.0)

	static func _commit(mb: MeshBuilder, b: PackedInt32Array, w: PackedFloat32Array) -> ArrayMesh:
		var m := ArrayMesh.new()
		if mb._v.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mb._v
		arrays[Mesh.ARRAY_NORMAL] = MeshBuilder.smooth_normals(mb._v, mb._n, MeshBuilder.TOON_SMOOTH_DEG)
		arrays[Mesh.ARRAY_COLOR] = mb._c
		arrays[Mesh.ARRAY_BONES] = b
		arrays[Mesh.ARRAY_WEIGHTS] = w
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m

	## [soft ArrayMesh, metal ArrayMesh]
	func commit() -> Array:
		bind(func(_p: Vector3) -> PackedFloat32Array: return PackedFloat32Array([0.0, 1.0]))
		return [_commit(soft, bs, ws), _commit(metal, bm, wm)]


## Skin resource (one bind per bone: the inverse of its rest origin, rest bases are identity).
static func make_skin(rest: Array[Vector3]) -> Skin:
	var sk := Skin.new()
	for i in rest.size():
		sk.add_bind(i, Transform3D(Basis.IDENTITY, -rest[i]))
	return sk


# --- modelling helpers -------------------------------------------------------------------------------------

## Loft of closed rings along a path. `rings` entries: [centre: Vector3, rx: float, rz: float] where rx runs along
## the frame's x (side) and rz along its z (towards `z_hint`). `col` is a Color or Callable(p, n_guess, k, i) -> Color.
## shape (optional): Callable(k: int, a: float) -> Vector2 offset (x, z) in the ring frame.
static func loft(mb: MeshBuilder, rings: Array, sides: int, col: Variant, z_hint: Vector3, cap0: bool, cap1: bool, shape: Callable = Callable(), rot0: float = 0.0) -> void:
	var n := rings.size()
	var pts: Array = []
	var cen: Array[Vector3] = []
	for k in n:
		var c: Vector3 = rings[k][0]
		cen.append(c)
	for k in n:
		var t: Vector3
		if k == 0:
			t = cen[1] - cen[0]
		elif k == n - 1:
			t = cen[n - 1] - cen[n - 2]
		else:
			t = cen[k + 1] - cen[k - 1]
		t = t.normalized()
		var z := perp(z_hint, t)
		if z.length_squared() < 1e-6:
			z = perp(Vector3.BACK, t)
		z = z.normalized()
		var x := t.cross(z)
		var rx: float = rings[k][1]
		var rz: float = rings[k][2]
		var ring: Array[Vector3] = []
		for i in sides:
			var a := rot0 + TAU * float(i) / float(sides)
			var off := Vector2(cos(a) * rx, sin(a) * rz)
			if shape.is_valid():
				off += shape.call(k, a)
			ring.append(cen[k] + x * off.x + z * off.y)
		pts.append(ring)
	for k in n - 1:
		for i in sides:
			var j := (i + 1) % sides
			var a: Vector3 = pts[k][i]
			var b: Vector3 = pts[k + 1][i]
			var c: Vector3 = pts[k + 1][j]
			var d: Vector3 = pts[k][j]
			var fc: Color = col.call((a + b + c + d) * 0.25, k, i) if col is Callable else col
			mb.quad(a, b, c, d, fc)
	if cap0:
		for i in sides:
			var fc: Color = col.call(cen[0], -1, i) if col is Callable else col
			mb.tri(cen[0], pts[0][(i + 1) % sides], pts[0][i], fc)
	if cap1:
		for i in sides:
			var fc: Color = col.call(cen[n - 1], n, i) if col is Callable else col
			mb.tri(cen[n - 1], pts[n - 1][i], pts[n - 1][(i + 1) % sides], fc)


## Horizontal ring loft around +Y with an angle-dependent radius: profile entries [y, rx, rz_front, rz_back, cz]
## (a = 0 is the front, -Z; a grows towards +X). `push` (optional): Callable(p: Vector3) -> Vector3 sculpt offset.
static func hloft(mb: MeshBuilder, prof: Array, sides: int, col: Variant, sq: float = 2.4, push: Callable = Callable(), cap_top: bool = false, cap_bot: bool = false) -> void:
	var pts: Array = []
	for e in prof:
		var y: float = e[0]
		var rx: float = e[1]
		var rf: float = e[2]
		var rb: float = e[3]
		var cz: float = e[4]
		var ring: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var sa := sin(a)
			var ca := cos(a)
			var ex := 2.0 / sq
			var px := signf(sa) * pow(absf(sa), ex) * rx
			var pz := -signf(ca) * pow(absf(ca), ex) * (rf if ca > 0.0 else rb) + cz
			var p := Vector3(px, y, pz)
			if push.is_valid():
				p += push.call(p)
			ring.append(p)
		pts.append(ring)
	# rings go bottom -> top or top -> bottom: orient faces outwards either way
	var up := (prof[prof.size() - 1][0] as float) > (prof[0][0] as float)
	for k in prof.size() - 1:
		for i in sides:
			var j := (i + 1) % sides
			var a: Vector3 = pts[k][i]
			var b: Vector3 = pts[k + 1][i]
			var c: Vector3 = pts[k + 1][j]
			var d: Vector3 = pts[k][j]
			var fc: Color = col.call((a + b + c + d) * 0.25, k, i) if col is Callable else col
			if up:
				mb.quad(a, b, c, d, fc)
			else:
				mb.quad(a, d, c, b, fc)
	var last: Array = pts[prof.size() - 1]
	var first: Array = pts[0]
	if cap_top:
		var top: Array = last if up else first
		var cy: float = (prof[prof.size() - 1][0] if up else prof[0][0])
		var c := Vector3(0, cy, 0)
		for i in sides:
			var fc: Color = col.call(c, -2, i) if col is Callable else col
			mb.tri(c, top[(i + 1) % sides], top[i], fc)
	if cap_bot:
		var bot: Array = first if up else last
		var cy2: float = (prof[0][0] if up else prof[prof.size() - 1][0])
		var c2 := Vector3(0, cy2, 0)
		for i in sides:
			var fc: Color = col.call(c2, -3, i) if col is Callable else col
			mb.tri(c2, bot[i], bot[(i + 1) % sides], fc)


static func bump(p: Vector2, c: Vector2, r: Vector2) -> float:
	var q := (p - c) / r
	var d := q.length_squared()
	return 0.0 if d >= 1.0 else (1.0 - d) * (1.0 - d)


# --- body ----------------------------------------------------------------------------------------------------

## [soft mesh, metal mesh] of the whole body (head, hair, hands and props excluded), skinned to the NB bones.
static func body_meshes() -> Array:
	if not _cache.has("body"):
		# (LOOK2: [soft, metal, the kilt])
		_cache["body"] = _build_body() + [_build_kilt()]
	return _cache["body"]


## LOOK2: the linen (the hips' dark under-layer, so nothing shows under the kilt, and the cream kilt to mid-thigh with its soft
## vertical folds and darker inner face, skinned to the skirt bones by angle): its own mesh, drawn with _mat_kilt (the cream
## stays warm in the shade).
static func _build_kilt() -> ArrayMesh:
	var sm := SkinMesh.new(37)
	var soft := sm.soft
	soft.vary = 0.0
	hloft(soft, [[0.80, 0.11, 0.09, 0.10, 0.01], [0.86, 0.17, 0.12, 0.14, 0.01], [0.93, 0.172, 0.135, 0.145, 0.0], [0.985, 0.165, 0.135, 0.14, 0.0]], 18, LINEN_DARK, 2.5, Callable(), false, true)
	sm.rigid(PELVIS)
	hloft(soft, KILT_PROF, 32, _kilt_col, 2.2, _kilt_fold)
	# inner face of the kilt (darker), so the inside reads when the hem lifts
	var inner := []
	for e in KILT_PROF:
		inner.append([e[0], e[1] - 0.008, e[2] - 0.008, e[3] - 0.008, 0.0])
	inner.reverse()
	hloft(soft, inner, 32, LINEN_DARK, 2.2, _kilt_fold)
	sm.bind(func(p: Vector3) -> PackedFloat32Array: return _skirt_w(p))
	return sm.commit()[0]


static func _w2(b0: int, b1: int, k: float) -> PackedFloat32Array:
	k = clampf(k, 0.0, 1.0)
	return PackedFloat32Array([float(b0), 1.0 - k, float(b1), k])


static func _build_body() -> Array:
	var sm := SkinMesh.new(31)
	var soft := sm.soft
	var metal := sm.metal
	soft.vary = 0.0
	metal.vary = 0.0
	# --- LOOK: the bare torso (skin): a narrow waist in the belt, the V up to broad lats and chest, the pectorals, a hint
	# of abdominals and obliques, the shoulder blades, the trapezius sloping into the neck ---
	var trings: Array = []
	for e in TORSO_PROF:
		var ring: Array[Vector3] = []
		for i in TORSO_SIDES:
			ring.append(_torso_pt(TAU * float(i) / float(TORSO_SIDES), e))
		trings.append(ring)
	_stitch(soft, trings, _torso_col, false, true)
	sm.bind(func(p: Vector3) -> PackedFloat32Array:
		if p.y < 1.06:
			return _w2(PELVIS, SPINE, smoothstep(0.98, 1.04, p.y))
		var w := _w2(SPINE, CHEST, smoothstep(1.17, 1.28, p.y))
		# the top of the shoulders rises with the clavicle (a shrug), the trapezius with it
		var wc := smoothstep(0.12, 0.2, absf(p.x)) * smoothstep(1.42, 1.48, p.y) * 0.7
		if wc > 0.001:
			var cl := CLAV_R if p.x > 0.0 else CLAV_L
			return PackedFloat32Array([float(CHEST), 1.0 - wc, float(cl), wc])
		return w)
	# neck (skin): thick, from inside the trapezius into the head
	loft(soft, [[Vector3(0, 1.47, 0.022), 0.086, 0.085], [Vector3(0, 1.545, 0.02), 0.081, 0.079], [Vector3(0, 1.615, 0.013), 0.074, 0.072], [Vector3(0, 1.69, 0.006), 0.064, 0.064]], 16, SKIN, FWD, false, true)
	sm.bind(func(p: Vector3) -> PackedFloat32Array:
		if p.y < 1.56:
			return _w2(CHEST, NECK, smoothstep(1.5, 1.56, p.y))
		return _w2(NECK, HEAD, smoothstep(1.6, 1.68, p.y)))
	# --- belt: wide dark-brown leather with rolled edges, a square plate buckle at the front ---
	var belt := [[0.938, 0.167, 0.138, 0.141, 0.0], [0.945, 0.176, 0.147, 0.150, 0.0], [0.955, 0.18, 0.151, 0.154, 0.0],
		[1.047, 0.181, 0.152, 0.155, 0.0], [1.057, 0.177, 0.148, 0.151, 0.0], [1.064, 0.166, 0.137, 0.14, 0.0], [1.068, 0.152, 0.123, 0.125, 0.0]]
	var belt_col := func(_p: Vector3, k: int, _i: int) -> Color:
		return LEATHER_DARK if k != 2 else LEATHER
	hloft(soft, belt, 28, belt_col, 2.5)
	# the buckle: a dark bronze plate with a raised square in it
	metal.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.001, -0.155)))
	metal.box(Vector3(0, 0, 0.0), Vector3(0.092, 0.082, 0.012), BRONZE_DARK)
	metal.box(Vector3(0, 0, -0.006), Vector3(0.064, 0.054, 0.008), BRONZE, BRONZE_LIGHT)
	metal.box(Vector3(0, 0, -0.0105), Vector3(0.034, 0.026, 0.004), BRONZE_DARK)
	metal.pop()
	sm.bind(func(p: Vector3) -> PackedFloat32Array: return _w2(PELVIS, SPINE, smoothstep(0.98, 1.04, p.y)))
	# (LOOK2: the hips' under-layer and the kilt are their own mesh, _build_kilt: the linen has its own material)
	# the red front panel hanging from the belt over the kilt (his left of centre), on the front skirt bones
	_flap(soft)
	sm.bind(func(p: Vector3) -> PackedFloat32Array: return _skirt_w(p))
	# --- arms ---
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var o := 0 if side == 0 else 4
		var sh := mx(P_SHOULDER, s)
		var el := mx(P_ELBOW, s)
		var wr := mx(P_WRIST, s)
		var dua := (el - sh).normalized()
		var dfa := (wr - el).normalized()
		var lat := Vector3(s, 0, 0)
		var rings := []
		for e in ARM_ST:
			var sd: float = e[0]
			var c: Vector3
			if sd <= LEN_UA:
				c = sh + dua * sd
			else:
				c = el + dfa * (sd - LEN_UA)
			# the deltoid sits outwards and a little forwards
			c += lat * 0.016 * bump(Vector2(sd, 0), Vector2(0.03, 0), Vector2(0.11, 1))
			c += FWD * 0.006 * bump(Vector2(sd, 0), Vector2(0.02, 0), Vector2(0.08, 1))
			rings.append([c, e[1], e[2]])
		var musc := func(k: int, a: float) -> Vector2:
			var sd: float = ARM_ST[k][0]
			var fr := maxf(0.0, sin(a))
			var bk := maxf(0.0, -sin(a))
			var lt := maxf(0.0, cos(a) * s)
			var m := bump(Vector2(sd, 0), Vector2(0.2, 0), Vector2(0.085, 1)) * fr * fr * 0.016 # biceps
			m += bump(Vector2(sd, 0), Vector2(0.15, 0), Vector2(0.1, 1)) * bk * bk * 0.012 # triceps
			m += bump(Vector2(sd, 0), Vector2(0.36, 0), Vector2(0.06, 1)) * pow(lt, 1.5) * 0.0105 # forearm extensors
			return Vector2(cos(a), sin(a)) * m
		loft(soft, rings, 14, SKIN, FWD, true, true, musc)
		var cl := CLAV_R + o
		var ua := UARM_R + o
		var fa := FARM_R + o
		var pa := PAUL_R + side
		sm.bind(func(p: Vector3) -> PackedFloat32Array:
			var e := (p - el).dot((dua + dfa).normalized())
			if e > -0.07:
				return _w2(ua, fa, smoothstep(-0.05, 0.05, e))
			# the deltoid on the PAUL bone (half way between the clavicle and the upper arm): the shoulder keeps its volume
			var top := (p - sh).dot(dua)
			var w_ua := smoothstep(0.03, 0.13, top)
			var w_cl := 1.0 - smoothstep(-0.075, -0.015, top)
			return PackedFloat32Array([float(cl), w_cl, float(pa), maxf(0.0, 1.0 - w_ua - w_cl), float(ua), w_ua]))
		# bracer: brown leather from two thirds up the forearm to the wrist, a lighter strap round its upper edge
		var brc := []
		for e in BRACER_ST:
			brc.append([el + dfa * float(e[0]), e[1], e[2]])
		var brc_col := func(_p: Vector3, k: int, _i: int) -> Color:
			return LEATHER_DARK if k == 0 or k == BRACER_ST.size() - 2 else LEATHER
		loft(soft, brc, 14, brc_col, FWD, false, false)
		# the edge strap (lighter leather)
		loft(soft, [[el + dfa * 0.088, 0.098, 0.088], [el + dfa * 0.096, 0.105, 0.095], [el + dfa * 0.118, 0.104, 0.094], [el + dfa * 0.126, 0.097, 0.087]], 14, LEATHER_LIGHT, FWD, false, false)
		sm.rigid(fa)
	# --- legs ---
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var o := 0 if side == 0 else 3
		var hp := mx(P_HIP, s)
		var kn := mx(P_KNEE, s)
		var an := mx(P_ANKLE, s)
		var dth := (kn - hp).normalized()
		var dsh := (an - kn).normalized()
		var lat := Vector3(s, 0, 0)
		var leg_c := func(sd: float) -> Vector3:
			var c: Vector3
			if sd <= LEN_TH:
				c = hp + dth * sd
			else:
				c = kn + dsh * (sd - LEN_TH)
			c += lat * 0.01 * bump(Vector2(sd, 0), Vector2(0.06, 0), Vector2(0.14, 1))
			c -= FWD * 0.01 * bump(Vector2(sd, 0), Vector2(0.6, 0), Vector2(0.12, 1))
			return c
		var rings := []
		for e in LEG_ST:
			rings.append([leg_c.call(float(e[0])), e[1], e[2]])
		var musc := func(k: int, a: float) -> Vector2:
			return Vector2(cos(a), sin(a)) * _leg_bulge(float(LEG_ST[k][0]), a, s)
		loft(soft, rings, 14, SKIN, FWD, true, false, musc)
		var th := THIGH_R + o
		var shb := SHIN_R + o
		var ft := FOOT_R + o
		var leg_w := func(p: Vector3) -> PackedFloat32Array:
			var e := (p - kn).dot((dth + dsh).normalized())
			if e > 0.25:
				return _w2(shb, ft, smoothstep(0.37, 0.41, (p - kn).dot(dsh)))
			if e > -0.08:
				return _w2(th, shb, smoothstep(-0.05, 0.05, e))
			var top := (p - hp).dot(dth)
			return _w2(PELVIS, th, smoothstep(-0.06, 0.06, top))
		sm.bind(leg_w)
		# leather wraps from below the knee to the ankle: a cuff, then bands that overlap downwards
		var wr_rings := []
		var wr_cols: Array[Color] = []
		var bands := WRAP_BANDS
		var sd0 := WRAP_TOP
		for b in bands + 1:
			var sd := sd0 + (WRAP_BOT - sd0) * float(b) / float(bands)
			var r := _leg_r(sd)
			if b > 0:
				# the lower lip of the band above, then the step in to the next band
				wr_rings.append([leg_c.call(sd - 0.004), r.x + 0.019, r.y + 0.019])
				wr_cols.append(LEATHER if b > 1 else LEATHER_LIGHT)
			wr_rings.append([leg_c.call(sd), r.x + 0.012, r.y + 0.012])
			wr_cols.append(LEATHER_DARK)
		var wcol := func(_p: Vector3, k: int, _i: int) -> Color:
			return wr_cols[clampi(k + 1, 0, wr_cols.size() - 1)]
		var wmusc := func(k: int, a: float) -> Vector2:
			var sd: float = sd0
			# (the ring's own station: its centre's distance down the leg)
			var cen: Vector3 = wr_rings[k][0]
			sd = LEN_TH + (cen - kn).dot(dsh)
			return Vector2(cos(a), sin(a)) * _leg_bulge(sd, a, s)
		loft(soft, wr_rings, 14, wcol, FWD, false, false, wmusc)
		sm.bind(leg_w)
		# foot (skin) and sandal (leather)
		_foot(soft, an, s)
		sm.bind(func(p: Vector3) -> PackedFloat32Array:
			if p.y > an.y + 0.02:
				return _w2(shb, ft, smoothstep(an.y + 0.06, an.y + 0.02, p.y))
			return PackedFloat32Array([float(ft), 1.0]))
	return sm.commit()


## LOOK: torso rings [y, rx, r_front, r_back, cz, squareness] (rest rig space, bottom to top).
const TORSO_PROF := [
	[0.975, 0.148, 0.118, 0.122, 0.0, 2.4],
	[1.03, 0.150, 0.12, 0.122, 0.0, 2.4],
	[1.09, 0.155, 0.124, 0.121, 0.002, 2.4],
	[1.15, 0.165, 0.13, 0.122, 0.002, 2.45],
	[1.21, 0.188, 0.14, 0.128, 0.0, 2.5],
	[1.27, 0.212, 0.151, 0.137, -0.002, 2.55],
	[1.325, 0.233, 0.161, 0.147, -0.004, 2.6],
	[1.375, 0.243, 0.165, 0.154, -0.004, 2.6],
	[1.42, 0.243, 0.158, 0.158, -0.002, 2.6],
	[1.46, 0.229, 0.142, 0.154, 0.004, 2.5],
	[1.495, 0.195, 0.117, 0.141, 0.01, 2.4],
	[1.52, 0.155, 0.098, 0.121, 0.014, 2.3],
	[1.54, 0.114, 0.086, 0.099, 0.016, 2.2],
	[1.556, 0.088, 0.08, 0.087, 0.016, 2.1],
]
const TORSO_SIDES := 32


## A point of the torso at angle a (0 front, PI/2 his right) on profile ring e, with the muscles sculpted in.
static func _torso_pt(a: float, e: Array) -> Vector3:
	var sa := sin(a)
	var ca := cos(a)
	var ex := 2.0 / float(e[5])
	var p := Vector3(signf(sa) * pow(absf(sa), ex) * float(e[1]), float(e[0]), -signf(ca) * pow(absf(ca), ex) * (float(e[2]) if ca > 0.0 else float(e[3])) + float(e[4]))
	return p + _torso_push(p)


static func _torso_push(p: Vector3) -> Vector3:
	var o := Vector3.ZERO
	var ax := absf(p.x)
	var q := Vector2(ax, p.y)
	if p.z < 0.0:
		var front := smoothstep(0.0, -0.07, p.z)
		# pectorals: two broad pads with a firm lower edge, the sternum's groove between them
		var pec := bump(q, Vector2(0.094, 1.398), Vector2(0.108, 0.088)) * smoothstep(1.312, 1.35, p.y)
		var groove := (1.0 - smoothstep(0.0, 0.022, ax)) * smoothstep(1.3, 1.36, p.y) * (1.0 - smoothstep(1.43, 1.47, p.y))
		# abdominals (a hint: three soft pads either side) and the line between them
		var ab := 0.0
		for yy in [1.115, 1.178, 1.243]:
			ab += bump(q, Vector2(0.046, yy), Vector2(0.042, 0.032))
		var alba := (1.0 - smoothstep(0.0, 0.013, ax)) * smoothstep(1.07, 1.12, p.y) * (1.0 - smoothstep(1.28, 1.32, p.y))
		o.z -= (pec * 0.03 + ab * 0.0075 - groove * 0.006 - alba * 0.004) * front
	else:
		# shoulder blades and the spine's groove
		o.z += bump(q, Vector2(0.095, 1.385), Vector2(0.08, 0.1)) * 0.012
		o.z -= (1.0 - smoothstep(0.0, 0.018, ax)) * 0.008 * smoothstep(1.08, 1.18, p.y) * (1.0 - smoothstep(1.47, 1.52, p.y))
	# obliques swelling over the belt
	o.x += signf(p.x) * bump(q, Vector2(0.15, 1.085), Vector2(0.04, 0.055)) * 0.007
	return o


## Gentle shading of the torso's planes: the creases under the pectorals and between the abdominals a touch darker, the
## tops of the shoulders and the upper chest a touch lighter (no painted lines: a few percent either way).
static func _torso_col(p: Vector3, _k: int, _i: int) -> Color:
	var ax := absf(p.x)
	var q := Vector2(ax, p.y)
	var c := SKIN
	if p.z < -0.04:
		var under := bump(q, Vector2(0.09, 1.322), Vector2(0.1, 0.026))
		var mid := (1.0 - smoothstep(0.006, 0.02, ax)) * smoothstep(1.08, 1.14, p.y) * (1.0 - smoothstep(1.3, 1.34, p.y))
		c = c.lerp(SKIN_SHADE, clampf(under * 1.3 + mid * 0.6, 0.0, 0.85))
		c = c.lerp(SKIN_LIGHT, bump(q, Vector2(0.1, 1.43), Vector2(0.09, 0.05)) * 0.6)
	if p.y > 1.47:
		c = c.lerp(SKIN_LIGHT, smoothstep(1.47, 1.52, p.y) * 0.5)
	return c


## Quads between consecutive rings (each ring the same count of points, ordered round from the front towards +x):
## rings bottom to top give outward faces; `closed_top` fans the last ring shut.
static func _stitch(mb: MeshBuilder, rings: Array, col: Variant, closed_bot: bool = false, closed_top: bool = false) -> void:
	var n: int = (rings[0] as Array).size()
	for k in rings.size() - 1:
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for i in n:
			var j := (i + 1) % n
			var a: Vector3 = r0[i]
			var b: Vector3 = r1[i]
			var c: Vector3 = r1[j]
			var d: Vector3 = r0[j]
			var fc: Color = col.call((a + b + c + d) * 0.25, k, i) if col is Callable else col
			mb.quad(a, b, c, d, fc)
	if closed_top:
		var last: Array = rings[rings.size() - 1]
		var cen := Vector3.ZERO
		for p in last:
			cen += p
		cen /= float(n)
		for i in n:
			var fc: Color = col.call(cen, rings.size(), i) if col is Callable else col
			mb.tri(cen, last[(i + 1) % n], last[i], fc)
	if closed_bot:
		var first: Array = rings[0]
		var cb := Vector3.ZERO
		for p in first:
			cb += p
		cb /= float(n)
		for i in n:
			var fc: Color = col.call(cb, -1, i) if col is Callable else col
			mb.tri(cb, first[i], first[(i + 1) % n], fc)


## LOOK: the kilt's rings [y, rx, r_front, r_back, cz]: tucked under the belt, flaring to a hem at mid-thigh.
const KILT_PROF := [
	[1.0, 0.163, 0.136, 0.14, 0.0],
	[0.955, 0.172, 0.144, 0.147, 0.0],
	[0.91, 0.19, 0.165, 0.169, 0.0],
	[0.85, 0.21, 0.19, 0.194, 0.0],
	[0.79, 0.227, 0.211, 0.214, 0.0],
	[0.752, 0.237, 0.222, 0.224, 0.0],
	[0.737, 0.235, 0.22, 0.222, 0.0],
]


## Soft vertical folds of the linen, deeper towards the hem (two waves, so they do not read as pleats).
static func _kilt_fold(p: Vector3) -> Vector3:
	var a := atan2(p.x, -p.z)
	var depth := smoothstep(0.985, 0.76, p.y)
	var r := (cos(a * 7.0 + 0.5) * 0.65 + cos(a * 12.0 + 2.1) * 0.35) * 0.0105 * depth
	return Vector3(p.x, 0, p.z).normalized() * r


static func _kilt_col(p: Vector3, k: int, _i: int) -> Color:
	if k >= KILT_PROF.size() - 2:
		return LINEN_SHADE
	var a := atan2(p.x, -p.z)
	# the folds' troughs a shade darker
	var f := cos(a * 7.0 + 0.5) * 0.65 + cos(a * 12.0 + 2.1) * 0.35
	return LINEN.lerp(LINEN_SHADE, clampf(-f, 0.0, 1.0) * smoothstep(0.96, 0.82, p.y) * 0.8)


## The kilt's front panel: a red cloth slab hanging from under the belt, over the kilt to below its hem, a little to his
## left of the centre (rest rig space; skinned like the kilt by its angle).
const FLAP_A := -0.36
static func _flap(mb: MeshBuilder) -> void:
	var hw := 0.25 # half-width (rad)
	var ys := [0.975, 0.95, 0.91, 0.85, 0.79, 0.745, 0.705, 0.685]
	var nu := 5
	var front: Array = []
	var back: Array = []
	for y: float in ys:
		var rowf: Array[Vector3] = []
		var rowb: Array[Vector3] = []
		for iu in nu:
			var a := FLAP_A + lerpf(-hw, hw, float(iu) / float(nu - 1))
			var yy := clampf(y, KILT_PROF[KILT_PROF.size() - 1][0], 1.0)
			var r := _kilt_r(a, yy)
			# below the hem it keeps falling along the kilt's flare
			var below := maxf(0.0, float(KILT_PROF[KILT_PROF.size() - 1][0]) - y)
			var d := Vector3(sin(a), 0.0, -cos(a))
			var base := Vector3(0.0, y, 0.0) + d * (r + below * 0.22)
			# a slight sag in the middle of the cloth
			var sag := sin(float(iu) / float(nu - 1) * PI) * 0.004 * smoothstep(0.95, 0.8, y)
			rowf.append(base + d * (0.0135 + sag))
			rowb.append(base + d * (0.0045 + sag))
		front.append(rowf)
		back.append(rowb)
	var n := ys.size()
	for k in n - 1:
		for iu in nu - 1:
			var col := CAPE if k < n - 2 else CAPE_DARK
			# front faces outwards (rows go down, columns towards +a)
			mb.quad(front[k][iu], front[k][iu + 1], front[k + 1][iu + 1], front[k + 1][iu], col)
			mb.quad(back[k][iu], back[k + 1][iu], back[k + 1][iu + 1], back[k][iu + 1], CAPE_DARK)
		# the side edges
		var cin: Vector3 = (front[k][nu / 2] + back[k + 1][nu / 2]) * 0.5
		_quad_out(mb, front[k][0], front[k + 1][0], back[k + 1][0], back[k][0], cin, CAPE_DARK)
		_quad_out(mb, front[k][nu - 1], back[k][nu - 1], back[k + 1][nu - 1], front[k + 1][nu - 1], cin, CAPE_DARK)
	for iu in nu - 1:
		var cb: Vector3 = (front[n - 2][iu] + back[n - 2][iu + 1]) * 0.5
		_quad_out(mb, front[n - 1][iu], front[n - 1][iu + 1], back[n - 1][iu + 1], back[n - 1][iu], cb, CAPE_DARK)


## The kilt's outer radius (before the folds) at angle a and height y.
static func _kilt_r(a: float, y: float) -> float:
	var prof := KILT_PROF
	var e0: Array = prof[0]
	var e1: Array = prof[1]
	var f := 0.0
	for k in prof.size() - 1:
		var y0: float = prof[k][0]
		var y1: float = prof[k + 1][0]
		if y <= y0 and y >= y1:
			e0 = prof[k]
			e1 = prof[k + 1]
			f = (y - y0) / (y1 - y0)
	var rx := lerpf(e0[1], e1[1], f)
	var rf := lerpf(e0[2], e1[2], f)
	var rb := lerpf(e0[3], e1[3], f)
	var sa := sin(a)
	var ca := cos(a)
	var ex := 2.0 / 2.2
	var p := Vector2(signf(sa) * pow(absf(sa), ex) * rx, signf(ca) * pow(absf(ca), ex) * (rf if ca > 0.0 else rb))
	return p.length()


## LOOK: arm stations [arc length from the shoulder joint, radius out, radius forward]: the deltoid capping the shoulder,
## the biceps, the elbow, a strong forearm narrowing to the wrist.
## (LOOK2: the forearms a sixth thicker, the reference's chunky build)
const ARM_ST := [[-0.064, 0.046, 0.046], [-0.042, 0.084, 0.087], [-0.012, 0.1, 0.099], [0.035, 0.104, 0.099], [0.085, 0.097, 0.093],
	[0.135, 0.084, 0.088], [0.185, 0.075, 0.087], [0.235, 0.069, 0.08], [0.28, 0.065, 0.07], [0.308, 0.064, 0.067],
	[0.34, 0.079, 0.076], [0.385, 0.085, 0.076], [0.44, 0.078, 0.067], [0.5, 0.067, 0.056], [0.548, 0.058, 0.049], [0.58, 0.053, 0.046]]
## The bracer's stations [distance from the elbow along the forearm, radius out, radius forward].
const BRACER_ST := [[0.084, 0.086, 0.078], [0.09, 0.1, 0.09], [0.15, 0.095, 0.083], [0.21, 0.083, 0.072], [0.258, 0.073, 0.064], [0.266, 0.073, 0.064], [0.272, 0.064, 0.056]]
## LOOK: leg stations [arc length from the hip joint, radius out, radius forward] and the wraps (below the knee to the ankle).
## (LOOK2: the calves an eighth thicker)
const LEG_ST := [[-0.09, 0.05, 0.05], [-0.05, 0.098, 0.1], [0.0, 0.108, 0.11], [0.06, 0.11, 0.112], [0.13, 0.106, 0.107],
	[0.2, 0.099, 0.099], [0.27, 0.09, 0.09], [0.34, 0.079, 0.079], [0.39, 0.07, 0.071], [0.425, 0.066, 0.068],
	[0.46, 0.068, 0.07], [0.5, 0.073, 0.078], [0.555, 0.078, 0.086], [0.615, 0.075, 0.083], [0.685, 0.065, 0.068],
	[0.755, 0.054, 0.056], [0.81, 0.047, 0.049], [0.84, 0.044, 0.045]]
## LOOK2: the feet and the sandals drawn this much bigger (width, height, length).
const FOOT_K := Vector3(1.1, 1.05, 1.1)
const WRAP_TOP := 0.48
const WRAP_BOT := 0.835
const WRAP_BANDS := 5


## The leg's radii (out, forward) at arc length sd.
static func _leg_r(sd: float) -> Vector2:
	for k in LEG_ST.size() - 1:
		var s0: float = LEG_ST[k][0]
		var s1: float = LEG_ST[k + 1][0]
		if sd >= s0 and sd <= s1:
			var f := (sd - s0) / (s1 - s0)
			return Vector2(lerpf(LEG_ST[k][1], LEG_ST[k + 1][1], f), lerpf(LEG_ST[k][2], LEG_ST[k + 1][2], f))
	var e: Array = LEG_ST[LEG_ST.size() - 1]
	return Vector2(e[1], e[2])


## The leg's muscles at arc length sd and ring angle a (side s): the quadriceps in front of the thigh, the kneecap,
## the calf swelling behind the shin.
static func _leg_bulge(sd: float, a: float, s: float) -> float:
	var fr := maxf(0.0, sin(a))
	var bk := maxf(0.0, -sin(a))
	var inner := maxf(0.0, -cos(a) * s)
	var m := bump(Vector2(sd, 0), Vector2(0.21, 0), Vector2(0.15, 1)) * pow(fr, 1.5) * 0.012
	m += bump(Vector2(sd, 0), Vector2(0.43, 0), Vector2(0.045, 1)) * pow(fr, 4.0) * 0.01
	m += bump(Vector2(sd, 0), Vector2(0.565, 0), Vector2(0.11, 1)) * pow(bk, 1.3) * 0.022
	m += bump(Vector2(sd, 0), Vector2(0.56, 0), Vector2(0.09, 1)) * pow(inner, 2.0) * 0.006
	return m


static func _skirt_w(p: Vector3) -> PackedFloat32Array:
	var a := fposmod(atan2(p.x, -p.z), TAU) / TAU * float(SKIRT_N)
	var i0 := int(floorf(a)) % SKIRT_N
	var i1 := (i0 + 1) % SKIRT_N
	var f := a - floorf(a)
	var down := smoothstep(1.04, 0.95, p.y)
	return PackedFloat32Array([float(PELVIS), 1.0 - down, float(SKIRT0 + i0), down * (1.0 - f), float(SKIRT0 + i1), down * f])


## Rounded sandal sole, `base` = on the ground under the ankle.
static func _sole(mb: MeshBuilder, base: Vector3) -> void:
	var zs := [0.085, 0.07, 0.04, 0.0, -0.06, -0.12, -0.17, -0.2, -0.218, -0.228]
	var hws := [0.022, 0.042, 0.052, 0.054, 0.059, 0.062, 0.06, 0.052, 0.038, 0.016]
	var th := 0.024
	var outline: Array[Vector3] = []
	for k in zs.size():
		outline.append(Vector3(hws[k], 0, zs[k]))
	for k in range(zs.size() - 1, -1, -1):
		outline.append(Vector3(-float(hws[k]), 0, zs[k]))
	var n := outline.size()
	var cen := Vector3(0, 0, -0.07)
	for i in n:
		var a: Vector3 = outline[i]
		var b: Vector3 = outline[(i + 1) % n]
		var a0 := base + a
		var b0 := base + b
		var a1 := base + a + Vector3(0, th, 0)
		var b1 := base + b + Vector3(0, th, 0)
		mb.tri(base + cen + Vector3(0, th, 0), a1, b1, LEATHER_LIGHT)
		mb.tri(base + cen, b0, a0, LEATHER_DARK)
		mb.quad(a0, b0, b1, a1, LEATHER_DARK)


static func _foot(soft: MeshBuilder, an: Vector3, s: float) -> void:
	var g := -an.y # ground, relative to the ankle
	# (LOOK2: the foot and its sandal bigger, about the ground under the ankle)
	var pv := an + Vector3(0, g, 0)
	soft.push(Transform3D(Basis.from_scale(FOOT_K), pv - FOOT_K * pv))
	var fp := func(z: float, rx: float, ry: float, yc: float) -> Array:
		return [an + Vector3(0.0, yc, z), rx, ry]
	# foot body along -Z (rings in XY planes)
	var rings := [fp.call(0.07, 0.03, 0.03, g + 0.05), fp.call(0.055, 0.046, 0.05, g + 0.055), fp.call(0.02, 0.054, 0.058, g + 0.06),
		fp.call(-0.04, 0.058, 0.048, g + 0.052), fp.call(-0.1, 0.062, 0.036, g + 0.042), fp.call(-0.155, 0.063, 0.028, g + 0.036),
		fp.call(-0.195, 0.056, 0.022, g + 0.033), fp.call(-0.215, 0.04, 0.016, g + 0.032)]
	# loft with frames: tangent -Z, z_hint up -> x = t x z
	loft(soft, rings, 10, SKIN, Vector3.UP, true, true)
	# toes: the big toe a little apart from the others (a groove of shade between them)
	soft.ico(an + Vector3(-0.026 * s, g + 0.036, -0.2), 0.024, SKIN, 0, 0.0, Vector3(0.8, 0.62, 1.0))
	# ankle column joining the shin (under the wraps)
	loft(soft, [[an + Vector3(0, 0.03, 0), 0.046, 0.048], [an + Vector3(0, -0.01, 0.0), 0.05, 0.054], [an + Vector3(0, -0.045, 0.01), 0.05, 0.056]], 10, SKIN, FWD, false, false)
	# sandal sole and straps
	_sole(soft, an + Vector3(0, g, 0))
	for z in [-0.14, -0.06]:
		loft(soft, [[an + Vector3(0, g + 0.042, z - 0.009), 0.066, 0.034], [an + Vector3(0, g + 0.042, z + 0.009), 0.066, 0.034]], 10, LEATHER_DARK, Vector3.UP, false, false)
	loft(soft, [[an + Vector3(0, -0.02, 0.0), 0.055, 0.059], [an + Vector3(0, -0.002, 0.0), 0.054, 0.058]], 10, LEATHER_DARK, FWD, false, false)
	soft.limb(an + Vector3(0, g + 0.045, -0.1), an + Vector3(0, -0.012, -0.045), 0.012, 0.012, 5, LEATHER_DARK)
	soft.pop()


# --- head (LOOK: no helmet: the head, a faceless face and short wavy hair) ------------------------------------

## Centre of the skull at eye level (rest rig space): the head, the face and the hair are built round it.
const SKULL_C := Vector3(0.0, 1.737, 0.012)
## The head and the hair are drawn this much bigger, about HEAD_PIV under the skull (stylised, like the reference).
const HEAD_SCALE := 1.1
const HEAD_PIV := Vector3(0.0, 1.64, 0.01)
## The head's rings [y (from SKULL_C), rx, r_front, r_back, cz, squareness], crown to the underside of the chin.
## FACE (2026-10-17, "la cara más redonda"): a round face like the reference: full cheeks down to the mouth's level, a
## broad round jaw (no corners: exponents near 2) to a short, soft chin raised from -0.138 to -0.123, and a gently convex
## profile (the forehead and the chin curve back, no long chin).
const HEAD_PROF := [
	[0.128, 0.032, 0.035, 0.04, 0.004, 2.0],
	[0.118, 0.057, 0.061, 0.069, 0.005, 2.1],
	[0.098, 0.077, 0.081, 0.091, 0.006, 2.2],
	[0.07, 0.087, 0.091, 0.102, 0.006, 2.2],
	[0.04, 0.091, 0.0945, 0.106, 0.005, 2.25],
	[0.018, 0.092, 0.0955, 0.105, 0.004, 2.25],
	[0.004, 0.092, 0.0963, 0.102, 0.003, 2.25],
	[-0.01, 0.0925, 0.0965, 0.099, 0.002, 2.25],
	[-0.024, 0.0935, 0.0965, 0.096, 0.001, 2.2],
	[-0.038, 0.094, 0.096, 0.092, 0.0, 2.2],
	[-0.05, 0.0945, 0.095, 0.088, -0.001, 2.2],
	[-0.062, 0.0935, 0.0935, 0.083, -0.002, 2.2],
	[-0.073, 0.091, 0.0915, 0.078, -0.003, 2.15],
	[-0.084, 0.087, 0.088, 0.072, -0.005, 2.15],
	[-0.094, 0.0835, 0.084, 0.065, -0.007, 2.1],
	[-0.102, 0.078, 0.0795, 0.058, -0.009, 2.1],
	[-0.109, 0.07, 0.0745, 0.051, -0.011, 2.05],
	[-0.114, 0.062, 0.069, 0.045, -0.013, 2.0],
	[-0.118, 0.053, 0.063, 0.04, -0.015, 2.0],
	[-0.121, 0.042, 0.055, 0.035, -0.017, 2.0],
	[-0.123, 0.029, 0.045, 0.029, -0.019, 2.0],
]
## Angles of the head's columns: dense over the face (its curves are a few centimetres wide), sparse at the back where
## the hair covers it.
const HEAD_A := [0.0, 0.1, 0.2, 0.31, 0.43, 0.56, 0.71, 0.88, 1.06, 1.26, 1.47, 1.7, 1.96, 2.24, 2.54, 2.84]


## The head's surface at angle a (0 front, PI/2 his right) and height y (SKULL_C relative), without the face.
static func _head_raw(a: float, y: float) -> Vector3:
	var prof := HEAD_PROF
	var e0: Array = prof[0]
	var e1: Array = prof[0]
	var f := 0.0
	if y < float(prof[prof.size() - 1][0]):
		e0 = prof[prof.size() - 1]
		e1 = e0
	elif y <= float(prof[0][0]):
		for k in prof.size() - 1:
			var y0: float = prof[k][0]
			var y1: float = prof[k + 1][0]
			if y <= y0 and y >= y1:
				e0 = prof[k]
				e1 = prof[k + 1]
				f = (y - y0) / (y1 - y0)
				break
	var rx := lerpf(e0[1], e1[1], f)
	var rf := lerpf(e0[2], e1[2], f)
	var rb := lerpf(e0[3], e1[3], f)
	var cz := lerpf(e0[4], e1[4], f)
	var sq := lerpf(e0[5], e1[5], f)
	var sa := sin(a)
	var ca := cos(a)
	var ex := 2.0 / sq
	return Vector3(signf(sa) * pow(absf(sa), ex) * rx, y, -signf(ca) * pow(absf(ca), ex) * (rf if ca > 0.0 else rb) + cz)


## The face sculpted on the head (SKULL_C relative). FACE: the round face is in HEAD_PROF; here only a broad, soft fullness
## of the middle of the face (the old straight nose cast a long dark band down the face; the brow ridge, cheekbones and
## jaw corners are gone). No eyes, no mouth, no brows, no hollows.
static func _face_push(p: Vector3) -> Vector3:
	var o := Vector3.ZERO
	if p.z >= 0.0:
		return o
	var fwd := smoothstep(0.03, 0.085, -p.z)
	o.z -= bump(Vector2(p.x, p.y), Vector2(0.0, -0.045), Vector2(0.045, 0.055)) * 0.006 * fwd
	return o


static func head_pt(a: float, y: float) -> Vector3:
	var p := _head_raw(a, y)
	return p + _face_push(p)


## Tools (clip checks): the outer surface of the head and its hair at angle a and height y, HEAD_C relative.
static func helm_pt(a: float, y: float) -> Vector3:
	var yl := (y + HEAD_C.y - HEAD_PIV.y) / HEAD_SCALE + HEAD_PIV.y - SKULL_C.y
	var p := head_pt(a, yl)
	if yl > _hairline(a):
		p += _hair_n(p) * _hair_shell(a, yl)
	return _head_xf() * (p + SKULL_C) - HEAD_C


## The head's and the hair's drawing transform (rest rig space): HEAD_SCALE about HEAD_PIV.
static func _head_xf() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * HEAD_SCALE), HEAD_PIV * (1.0 - HEAD_SCALE))


## [head (skin), hair] meshes skinned to HEAD.
static func head_meshes() -> Array:
	if not _cache.has("head"):
		_cache["head"] = [_build_head(), _build_hair()]
	return _cache["head"]


## (old name, kept for the tools)
static func helmet_meshes() -> Array:
	return head_meshes()


static func _build_head() -> ArrayMesh:
	var sm := SkinMesh.new(41)
	var mb := sm.soft
	mb.push(_head_xf())
	var angs: Array[float] = []
	for a: float in HEAD_A:
		angs.append(a)
	for k in range(HEAD_A.size() - 1, 0, -1):
		angs.append(TAU - float(HEAD_A[k]))
	angs.append(PI)
	angs.sort()
	var rings: Array = []
	for k in range(HEAD_PROF.size() - 1, -1, -1):
		var y: float = HEAD_PROF[k][0]
		var ring: Array[Vector3] = []
		for a in angs:
			ring.append(SKULL_C + head_pt(a, y))
		rings.append(ring)
	var col := func(p: Vector3, k: int, _i: int) -> Color:
		var q := p - SKULL_C
		if q.y < -0.117:
			return SKIN_SHADE
		return SKIN
	_stitch(mb, rings, col, true, true)
	# ears: simple, set back on the sides of the head, tilted back
	for sx in [-1.0, 1.0]:
		var ep := SKULL_C + Vector3(0.09 * sx, -0.03, 0.016)
		mb.push(Transform3D(Basis(Vector3.RIGHT, 0.18) * Basis(Vector3.UP, 0.32 * sx), ep))
		mb.ico(Vector3.ZERO, 0.028, SKIN, 1, 0.0, Vector3(0.42, 1.0, 0.66))
		mb.ico(Vector3(0.006 * sx, -0.002, 0.002), 0.018, SKIN_SHADE, 0, 0.0, Vector3(0.4, 0.8, 0.5))
		mb.pop()
	mb.pop()
	sm.rigid(HEAD)
	return sm.commit()[0]


## The hairline (SKULL_C-relative height) at angle a: high over the forehead, down to the sideburns in front of the
## ears, up over the ears and down to the nape.
static func _hairline(a: float) -> float:
	var x := absf(wrapf(a, -PI, PI))
	if x < 1.0:
		return _hairline_k(x) + cos(x * 9.0) * 0.005 * (1.0 - smoothstep(0.6, 1.0, x))
	return _hairline_k(x)


static func _hairline_k(x: float) -> float:
	# (LOOK2: higher over the forehead, which the hair now leaves clear; FACE: the front a little lower again, 0.08 -> 0.066,
	# so the rounder face reads round, not long)
	var keys := [0.0, 0.066, 0.55, 0.06, 0.95, 0.038, 1.12, 0.0, 1.24, -0.046, 1.38, -0.05, 1.5, -0.006, 1.66, 0.006, 1.86, -0.006, 2.15, -0.056, 2.6, -0.09, PI, -0.1]
	for k in range(0, keys.size() - 2, 2):
		var a0: float = keys[k]
		var a1: float = keys[k + 2]
		if x >= a0 and x <= a1:
			return lerpf(keys[k + 1], keys[k + 3], smoothstep(0.0, 1.0, (x - a0) / (a1 - a0)))
	return keys[keys.size() - 1]


## Outward normal of the scalp (roughly: up over the crown, out at the sides), SKULL_C relative.
static func _hair_n(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y * 1.5 + 0.012, p.z - 0.004).normalized()


## The hair's outer surface at angle a, height y, `t` above the scalp (SKULL_C relative).
static func _hair_pt(a: float, y: float, t: float) -> Vector3:
	var p := _head_raw(a, y)
	return p + _hair_n(p) * t


## The hair's thickness over the scalp at angle a, a fraction f of the way from the crown (0) to the hairline (1).
## LOOK2: swept up and back: over the forehead it rises from the hairline in a long slope (its front face leaning back, the
## forehead clear) to a quiff, the fullest of it, above the front of the skull, a little lower over the crown and the back,
## close over the ears and short at the nape.
static func _hair_t(a: float, f: float) -> float:
	var x := absf(wrapf(a, -PI, PI))
	var front := 1.0 - smoothstep(0.3, 1.1, x)
	var side := smoothstep(0.95, 1.4, x) * (1.0 - smoothstep(1.85, 2.35, x))
	var nape := smoothstep(2.3, 2.9, x)
	var base := lerpf(0.034, 0.054, front) - side * 0.018 - nape * 0.006
	# the slope up from the hairline: long in front (the quiff's face), short at the sides and the back
	var rise := smoothstep(1.0, lerpf(0.62, 0.22, front), f)
	# the quiff stands highest above the forehead and settles towards the crown
	var crown := lerpf(1.0, 0.78, (1.0 - smoothstep(0.0, 0.42, f)) * front)
	return base * (0.14 + 0.86 * rise) * crown


## The hair's surface height above the scalp at angle a and height y (SKULL_C relative).
static func _hair_shell(a: float, y: float) -> float:
	var y_h := _hairline(a)
	var f := clampf((0.131 - y) / maxf(0.131 - y_h, 1e-3), 0.0, 1.0)
	return _hair_t(a, pow(f, 1.0 / 0.85))


static func _build_hair() -> ArrayMesh:
	var sm := SkinMesh.new(43)
	var mb := sm.soft
	mb.push(_head_xf())
	# the mass: columns from the crown down to the hairline, thick over the top, thin at the edge
	var na := 30
	var nv := 8
	var cols: Array = []
	for i in na:
		var a := TAU * float(i) / float(na)
		var y_h := _hairline(a)
		var col_pts: Array[Vector3] = []
		for v in nv + 1:
			var f := float(v) / float(nv)
			var y := lerpf(0.131, y_h, pow(f, 0.85))
			col_pts.append(SKULL_C + _hair_pt(a, y, _hair_t(a, f)))
		# the lip down onto the scalp at the hairline
		col_pts.append(SKULL_C + _hair_pt(a, y_h - 0.003, 0.0015))
		cols.append(col_pts)
	var rings: Array = []
	for v in nv + 2:
		var ring: Array[Vector3] = []
		for i in na:
			ring.append(cols[i][v])
		rings.append(ring)
	rings.reverse() # bottom (the hairline) first: the faces turn outwards
	var cap_col := func(p: Vector3, k: int, _i: int) -> Color:
		# (LOOK2: the lip at the hairline is dark at the sides and the back; over the forehead the hair just rises from it)
		return HAIR_DARK if k == 0 and (p - SKULL_C).z > -0.06 else HAIR
	_stitch(mb, rings, cap_col, false, true)
	# the locks: chunky, swept back from the forehead over the top, back and down over the sides, short at the nape
	for lk in HAIR_LOCKS:
		_lock(mb, lk[0], lk[1], lk[2], lk[3], lk[4], lk[5], lk[6])
	mb.pop()
	sm.rigid(HEAD)
	return sm.commit()[0]


## The locks: [root angle, root height, tip angle, tip height, width, thickness, lift] (heights SKULL_C relative; lift:
## how far the tip stands off the hair's surface).
const HAIR_LOCKS := [
	# the front: waves rising from the hairline and swept back over the top, their tips lifted (LOOK2: the quiff)
	[0.06, 0.104, 0.2, 0.131, 0.05, 0.03, 0.05],
	[0.46, 0.098, 0.8, 0.13, 0.046, 0.028, 0.042],
	[-0.4, 0.1, -0.7, 0.13, 0.046, 0.028, 0.042],
	[0.9, 0.07, 1.3, 0.115, 0.04, 0.024, 0.03],
	[-0.9, 0.07, -1.3, 0.115, 0.04, 0.024, 0.03],
	# the crown, swept back, the tips curling up off the back of the head
	[0.25, 0.128, 2.95, 0.1, 0.048, 0.028, 0.034],
	[-0.3, 0.127, -2.8, 0.095, 0.048, 0.028, 0.032],
	[1.05, 0.115, 2.3, 0.07, 0.044, 0.025, 0.03],
	[-1.05, 0.115, -2.3, 0.07, 0.044, 0.025, 0.03],
	# the sides: back over the temples, above the ears
	[1.12, 0.074, 1.98, 0.042, 0.034, 0.02, 0.016],
	[-1.12, 0.074, -1.98, 0.042, 0.034, 0.02, 0.016],
	# the sideburns
	[1.29, 0.012, 1.31, -0.046, 0.021, 0.011, 0.004],
	[-1.29, 0.012, -1.31, -0.046, 0.021, 0.011, 0.004],
	# the back: down to the nape, shorter there, the tips flicking out
	[2.05, 0.08, 2.3, -0.015, 0.038, 0.022, 0.018],
	[-2.05, 0.08, -2.3, -0.015, 0.038, 0.022, 0.018],
	[2.62, 0.105, 2.7, -0.068, 0.044, 0.025, 0.03],
	[-2.62, 0.105, -2.7, -0.068, 0.044, 0.025, 0.03],
	[PI, 0.11, PI, -0.083, 0.044, 0.025, 0.03],
	[1.75, 0.06, 2.02, 0.0, 0.03, 0.019, 0.014],
	[-1.75, 0.06, -2.02, 0.0, 0.03, 0.019, 0.014],
]


## One lock of hair: a chunky, pointed wedge lying on the scalp from (a0, y0) to (a1, y1), its tip standing off by `lift`.
## The faces turned up are the lighter brown.
static func _lock(mb: MeshBuilder, a0: float, y0: float, a1: float, y1: float, w0: float, h0: float, lift: float) -> void:
	var n := 5
	var cen: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for k in n:
		var s := float(k) / float(n - 1)
		var a := lerpf(a0, a1, s)
		var y := minf(lerpf(y0, y1, s), 0.13)
		var base := _head_raw(a, y)
		var nn := _hair_n(base)
		var shell := _hair_shell(a, y)
		# (the root starts inside the hair's mass, so the lock grows out of it)
		cen.append(SKULL_C + base + nn * (shell * lerpf(0.45, 0.85, smoothstep(0.0, 0.35, s)) + lift * pow(s, 1.4) + h0 * 0.3 * (1.0 - s)))
		nrm.append(nn)
	var ring: Array = []
	for k in n:
		var s := float(k) / float(n - 1)
		var t: Vector3 = (cen[mini(k + 1, n - 1)] - cen[maxi(k - 1, 0)]).normalized()
		var nn: Vector3 = perp(nrm[k], t).normalized()
		var b := t.cross(nn).normalized()
		var w := w0 * (1.0 - pow(s, 1.7)) * (0.6 + 0.65 * sin(minf(s * 1.6, 1.0) * PI * 0.5))
		var h := h0 * (1.0 - s * 0.85)
		var c: Vector3 = cen[k]
		if k == n - 1:
			ring.append([c, c, c, c])
		else:
			ring.append([c + b * w, c + nn * h * 0.55, c - b * w, c - nn * h * 0.45])
	for k in n - 1:
		var r0: Array = ring[k]
		var r1: Array = ring[k + 1]
		for i in 4:
			var j := (i + 1) % 4
			var mid: Vector3 = (r0[i] + r0[j] + r1[i] + r1[j]) * 0.25
			var inside: Vector3 = cen[k] if k < n - 2 else cen[n - 2]
			var fn: Vector3 = (r1[i] - r0[i]).cross(r0[j] - r0[i]) + (r1[j] - r0[i]).cross(r0[j] - r0[i])
			if fn.dot(mid - inside) < 0.0:
				fn = -fn
			var up := fn.normalized().y if fn.length_squared() > 1e-14 else 0.0
			var col := HAIR
			if i < 2:
				col = HAIR_LIGHT if up > 0.25 else HAIR
			elif up < 0.2:
				col = HAIR_DARK
			_quad_out(mb, r0[i], r1[i], r1[j], r0[j], inside, col)
	# the root end, closed
	var r0e: Array = ring[0]
	_quad_out(mb, r0e[0], r0e[1], r0e[2], r0e[3], cen[1], HAIR)


## A quad a, b, c, d turned to face away from `inside`.
static func _quad_out(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a) + (c - a).cross(d - a)
	if n.dot((a + b + c + d) * 0.25 - inside) < 0.0:
		mb.quad(a, d, c, b, col)
	else:
		mb.quad(a, b, c, d, col)


# --- lion outfit -----------------------------------------------------------------------------------------------

## Skull cap of the lion hood (head-centre relative, as cut for the old helmet; HOOD_K and HOOD_OFF set it on the bare head).
const HOOD_PROF := [
	[0.236, 0.05, 0.05, 0.05, 0.0],
	[0.226, 0.1, 0.106, 0.112, 0.0],
	[0.202, 0.148, 0.16, 0.17, 0.0],
	[0.164, 0.18, 0.2, 0.206, 0.0],
	[0.114, 0.196, 0.224, 0.226, 0.0],
	[0.064, 0.2, 0.234, 0.236, 0.0],
	[0.022, 0.198, 0.234, 0.24, 0.0],
]
const HOOD_SQ := 2.2
## The nape hinge the hood swings about when it is pulled up (rest rig space) and its angle when down.
const HOOD_HINGE := Vector3(0.0, 1.6, 0.2)
const HOOD_DOWN := 3.0
## LOOK: the hair hides once the hood is this far over the head (pose channel `hood`), the face's tint under it.
const HOOD_HAIR_OFF := 0.85
## LOOK: the hood's scale and offset (from HEAD_C) on the bare head.
const HOOD_K := Vector3(0.74, 0.76, 0.7)
const HOOD_OFF := Vector3(0.0, 0.006, 0.03)
const HOOD_SHADE := 0.62


## Point on the hood cap (head-centre relative), a = 0 front, PI/2 right side.
static func hood_pt(a: float, y: float) -> Vector3:
	var prof := HOOD_PROF
	var e0: Array = prof[prof.size() - 2]
	var e1: Array = prof[prof.size() - 1]
	var f := 1.0
	for k in prof.size() - 1:
		var y0: float = prof[k][0]
		var y1: float = prof[k + 1][0]
		if y <= y0 and y >= y1:
			e0 = prof[k]
			e1 = prof[k + 1]
			f = (y - y0) / (y1 - y0)
	var rx := lerpf(e0[1], e1[1], f)
	var rf := lerpf(e0[2], e1[2], f)
	var rb := lerpf(e0[3], e1[3], f)
	var sa := sin(a)
	var ca := cos(a)
	var ex := 2.0 / HOOD_SQ
	return Vector3(signf(sa) * pow(absf(sa), ex) * rx, y, -signf(ca) * pow(absf(ca), ex) * (rf if ca > 0.0 else rb))


## Triangle a, b, c turned to face away from `inside`.
static func _tri_out(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		mb.tri(a, c, b, col)
	else:
		mb.tri(a, b, c, col)


## A tuft of mane: a flattened four-sided spike from `base` along `dir` (w across `side`, half that across).
static func _tuft(mb: MeshBuilder, base: Vector3, dir: Vector3, length: float, w: float, side: Vector3, col: Color) -> void:
	var d := dir.normalized()
	var x := perp(side, d)
	if x.length_squared() < 1e-6:
		x = perp(Vector3.RIGHT, d)
	x = x.normalized()
	var y := d.cross(x)
	var tip := base + d * length
	var ring := [base + x * w, base + y * w * 0.45, base - x * w, base - y * w * 0.45]
	var inside := base + d * length * 0.3
	for i in 4:
		var c2 := col if i % 2 == 0 else col.darkened(0.12)
		_tri_out(mb, ring[i], ring[(i + 1) % 4], tip, inside, c2)


## [soft mesh] of the lion hood in rest rig space (rigid on the hood pivot): skull cap with ears, a heavy brow
## with closed eyes, the muzzle jutting over the face like a visor (no mouth, no teeth: its underside is in
## shadow) and a ruff of mane tufts framing the face and covering the back of the head.
static func hood_meshes() -> Array:
	if not _cache.has("hood"):
		_cache["hood"] = [_build_hood()]
	return _cache["hood"]


static func _build_hood() -> ArrayMesh:
	var mb := MeshBuilder.new(47)
	# LOOK: the hood was cut to go over the helmet: scaled down and set back onto the bare head (the hair hides under it)
	mb.push(Transform3D(Basis.from_scale(HOOD_K), HEAD_C + HOOD_OFF))
	# skull cap: golden forehead, mane everywhere else
	var cap_col := func(p: Vector3, k: int, _i: int) -> Color:
		var front := -p.z / maxf(Vector2(p.x, p.z).length(), 1e-4)
		if front > 0.55 and k <= 5:
			return FUR
		return MANE if k % 2 == 0 else MANE_DARK
	hloft(mb, HOOD_PROF, 26, cap_col, HOOD_SQ, Callable(), true, false)
	# dark lining (mirrored = faces turned inwards) so the cap never shows its back faces from below
	mb.push(Transform3D(Basis.from_scale(Vector3(-0.985, 1.0, 0.985)), Vector3(0, -0.004, 0)))
	hloft(mb, HOOD_PROF, 26, SHADOW, HOOD_SQ, Callable(), false, false)
	mb.pop()
	var rim_y: float = HOOD_PROF[HOOD_PROF.size() - 1][0]
	for i in 26:
		var a0 := TAU * float(i) / 26.0
		var a1 := TAU * float(i + 1) / 26.0
		var o0 := hood_pt(a0, rim_y)
		var o1 := hood_pt(a1, rim_y)
		var i0 := Vector3(o0.x * 0.985, rim_y - 0.004, o0.z * 0.985)
		var i1 := Vector3(o1.x * 0.985, rim_y - 0.004, o1.z * 0.985)
		_tri_out(mb, o0, o1, i1, Vector3(0, rim_y + 0.05, 0), MANE_DARK)
		_tri_out(mb, o0, i1, i0, Vector3(0, rim_y + 0.05, 0), MANE_DARK)
	# heavy brow ridge and closed eyes under it
	var brow := []
	for i in 9:
		var a := lerpf(-0.9, 0.9, float(i) / 8.0)
		var bp := hood_pt(a, 0.1)
		brow.append(bp + Vector3(bp.x, 0, bp.z).normalized() * 0.01 + Vector3(0, -0.016 * pow(absf(a) / 0.9, 2.0), 0))
	mb.tube(brow, 0.026, 0.022, 7, FUR_DARK, true)
	for sx in [-1.0, 1.0]:
		var ec := hood_pt(0.42 * sx, 0.072)
		var en := Vector3(ec.x, 0.0, ec.z).normalized()
		var et := Vector3(-en.z, 0.0, en.x)
		var e0 := ec + en * 0.008 - et * 0.034 + Vector3(0, 0.006, 0)
		var e1 := ec + en * 0.014 + Vector3(0, -0.009, 0)
		var e2 := ec + en * 0.008 + et * 0.034 + Vector3(0, 0.004, 0)
		var e3 := ec + en * 0.014 + Vector3(0, -0.001, 0)
		_tri_out(mb, e0, e1, e3, ec - en * 0.05, MANE_DARK)
		_tri_out(mb, e3, e1, e2, ec - en * 0.05, MANE_DARK)
	# the muzzle: a broad snout jutting forward from between the eyes like a visor; golden bridge, pale lips,
	# a dark nose pad at the tip, nothing under it but shadow (no mouth, no teeth)
	var mz := [[Vector3(0, 0.074, -0.17), 0.1, 0.07], [Vector3(0, 0.068, -0.24), 0.105, 0.072],
		[Vector3(0, 0.052, -0.3), 0.098, 0.066], [Vector3(0, 0.032, -0.348), 0.082, 0.056],
		[Vector3(0, 0.014, -0.378), 0.056, 0.04]]
	var mz_col := func(p: Vector3, _k: int, _i: int) -> Color:
		var cy := lerpf(0.074, 0.014, clampf((-p.z - 0.17) / 0.208, 0.0, 1.0))
		if p.y < cy - 0.03:
			return SHADOW
		if p.y > cy + 0.022 and absf(p.x) < 0.06:
			return FUR
		return MUZZLE
	loft(mb, mz, 14, mz_col, Vector3.UP, false, true)
	mb.ico(Vector3(0, 0.05, -0.372), 0.034, NOSE, 1, 0.0, Vector3(1.35, 0.6, 0.85))
	for sx in [-1.0, 1.0]:
		# whisker pads and the cheeks blending the snout into the mane
		mb.ico(Vector3(0.05 * sx, 0.02, -0.335), 0.042, MUZZLE, 1, 0.0, Vector3(1.0, 0.8, 0.9))
		mb.ico(Vector3(0.11 * sx, 0.04, -0.22), 0.07, FUR, 1, 0.0, Vector3(0.85, 0.8, 1.0))
	# small round ears, half sunk in the mane
	for sx in [-1.0, 1.0]:
		var ep := hood_pt(0.95 * sx, 0.2)
		mb.push(Transform3D(Basis(Vector3.UP, -0.5 * sx) * Basis(Vector3.BACK, -0.35 * sx), ep + Vector3(0, 0.022, 0)))
		mb.ico(Vector3.ZERO, 0.04, FUR, 1, 0.0, Vector3(1.0, 0.95, 0.45))
		mb.ico(Vector3(0, -0.004, -0.012), 0.026, MANE_DARK, 0, 0.0, Vector3(0.8, 0.85, 0.3))
		mb.pop()
	# the mane: a ruff framing the face, then rows over the top, sides and back, the lowest falling over the nape
	var cols := [MANE, MANE_DARK, MANE_LIGHT]
	var ci := 0
	# face ruff: broad locks pointing out and down round the forehead and the cheeks
	for i in 17:
		var u := float(i) / 16.0
		var a := lerpf(-1.62, 1.62, u)
		var side_k := absf(a) / 1.62
		var y := 0.2 - 0.28 * pow(side_k, 1.5)
		var bp := hood_pt(a, clampf(y, 0.022, 0.22))
		if y < 0.022:
			var rr := hood_pt(a, 0.022)
			bp = Vector3(rr.x * 1.04, y, rr.z * 1.04)
		var out := Vector3(bp.x, 0.0, bp.z).normalized()
		var dir := out * 0.8 + Vector3(0, 0.3 - side_k * 0.55, 0) + Vector3(0, 0, 0.35 + 0.3 * side_k)
		var h := float((i * 37) % 11) / 10.0
		_tuft(mb, bp, dir, 0.11 + 0.03 * side_k + 0.03 * h, 0.062, Vector3(0, 1, 0), cols[ci % 3])
		ci += 1
	# flowing locks from the crown down to the nape, staggered row to row
	var rows := [[0.225, 0.95, 0.15, 0.07, 0.35], [0.165, 1.05, 0.19, 0.078, 0.05], [0.1, 1.2, 0.2, 0.08, -0.2],
		[0.035, 1.45, 0.2, 0.078, -0.45], [-0.04, 1.95, 0.19, 0.074, -0.75], [-0.1, 2.3, 0.16, 0.07, -1.0]]
	for ri in rows.size():
		var row: Array = rows[ri]
		var y: float = row[0]
		var a_from: float = row[1]
		var ln: float = row[2]
		var wd: float = row[3]
		var lift: float = row[4]
		var n := 7
		for side in [-1.0, 1.0]:
			for i in n:
				var stag := 0.5 * float(ri % 2) / float(n - 1)
				var a: float = side * lerpf(a_from, PI, minf(float(i) / float(n - 1) + stag, 1.0))
				if side > 0.0 and absf(absf(a) - PI) < 0.01:
					continue
				var base := hood_pt(a, clampf(y, 0.022, 0.23))
				if y < 0.022:
					var rr := hood_pt(a, 0.022)
					base = Vector3(rr.x * 1.02, y, rr.z * 1.02)
				var out := Vector3(base.x, 0.0, base.z).normalized()
				var h := float((i * 53 + ri * 29 + int(side + 1.0) * 17) % 13) / 12.0
				var dir := out * 0.85 + Vector3(0, lift - 0.45, 0) + Vector3(0, 0, 0.4) + Vector3(out.z, 0, -out.x) * (h - 0.5) * 0.4
				_tuft(mb, base - out * 0.018, dir, ln * (0.8 + 0.45 * h), wd * (0.9 + 0.25 * h), Vector3(out.z, 0, -out.x), cols[ci % 3])
				ci += 1
	mb.pop()
	return mb.commit()


## [soft mesh] the pelt's forelegs brought over the shoulders and knotted on the chest, the paws hanging below
## (rest rig space, rigid on the chest).
static func paws_mesh() -> ArrayMesh:
	if not _cache.has("paws"):
		var mb := MeshBuilder.new(49)
		# LOOK: the knot sits on the bare chest (the cuirass was 3 cm deeper)
		var knot := Vector3(0.0, 1.42, -0.2)
		for sx in [-1.0, 1.0]:
			var leg := [Vector3(0.115 * sx, 1.585, 0.065), Vector3(0.122 * sx, 1.568, -0.045), Vector3(0.106 * sx, 1.516, -0.112),
				Vector3(0.066 * sx, 1.462, -0.17), Vector3(0.022 * sx, 1.43, -0.198)]
			mb.tube(leg, 0.036, 0.032, 9, FUR, false)
			# a darker stripe of mane where the leg leaves the pelt
			mb.tube([leg[0] + Vector3(0, 0.01, 0), leg[1] + Vector3(0, 0.01, 0)], 0.039, 0.037, 9, MANE, false)
			var hang := [knot + Vector3(0.014 * sx, -0.012, -0.004), knot + Vector3(0.028 * sx, -0.045, -0.008),
				knot + Vector3(0.036 * sx, -0.062 - 0.012 * (sx + 1.0), -0.006)]
			mb.tube(hang, 0.032, 0.03, 8, FUR, false)
			var paw: Vector3 = hang[2] + Vector3(0.004 * sx, -0.03, -0.006)
			mb.ico(paw, 0.044, PAW, 1, 0.0, Vector3(1.0, 0.85, 0.7))
			for k in 3:
				mb.ico(paw + Vector3((float(k) - 1.0) * 0.022, -0.033, -0.013), 0.014, MANE_DARK, 0)
		mb.ico(knot, 0.046, FUR_DARK, 1, 0.0, Vector3(1.3, 0.9, 0.75))
		_cache["paws"] = mb.commit()
	return _cache["paws"]


## LOOK2: the mantle, the top of the cloak: a thick fold of the deep red cloth lying over both shoulders and the base of the
## neck, over the deltoids and down their outsides, across the upper back (over the cloak's pinned row, hiding it) and in a
## band from each shoulder down to the upper chest, where a round gold brooch pins the two sides together; its lower edge is a
## full rolled hem, gathered thicker on his left shoulder (rest rig space, skinned like the skin under it: the chest, the
## clavicles, the base of the neck, the deltoids and the upper arms; hidden under the lion pelt). [soft (cloth), metal (brooch)]
## It is laid on the body with rays from MANTLE_O: per angle round the neck an elevation range (MANTLE_PHI), along each ray
## the body's outer surface (_body_ray) plus the cloth's thickness.
static func collar_meshes() -> Array:
	if not _cache.has("collar"):
		var sm := SkinMesh.new(33)
		var soft := sm.soft
		var metal := sm.metal
		# the cross-section, from the inner edge (the base of the neck, or the front band's upper edge) over the top to the rolled
		# outer edge and tucked under it: [fraction of the way from the top elevation to the bottom one, arc (m) past the bottom
		# one, height over the body (m), colour: 2 the underside, else the top]
		var sec := [[0.0, -0.006, 0.002, 2], [0.0, -0.002, 0.011, 0], [0.14, 0.0, 0.016, 0], [0.38, 0.0, 0.018, 0],
			[0.62, 0.0, 0.019, 0], [0.82, 0.0, 0.022, 0], [0.95, 0.0, 0.03, 1], [1.0, 0.009, 0.029, 1], [1.0, 0.017, 0.016, 2],
			[1.0, 0.015, 0.003, 2]]
		var na := 56
		var ns := sec.size()
		var grid: Array = []
		var cols: Array = []
		# the rays and the body's surface along them, then the cloth's height over it
		var dirs: Array = []
		var tb: Array = []
		var hs: Array = []
		for i in na:
			var a := TAU * float(i) / float(na)
			var ph := _mantle_phi(a)
			var x := absf(wrapf(a, -PI, PI))
			# the hem's fullness: slimmer in the front band, fuller over the shoulders, gathered on his left shoulder
			var rs := lerpf(0.62, 1.0, smoothstep(0.35, 1.1, x))
			rs += 0.55 * exp(-pow((wrapf(a, -PI, PI) + 1.62) / 0.42, 2.0))
			# (the arcs past the bottom edge, as angles at the distance of that edge)
			var t_bot := maxf(_body_ray(_mantle_dir(a, ph.y)).x, 0.08)
			var dr: Array[Vector3] = []
			var tr := PackedFloat32Array()
			var hr := PackedFloat32Array()
			for j in ns:
				var e: Array = sec[j]
				var d := _mantle_dir(a, lerpf(ph.x, ph.y, float(e[0])) - float(e[1]) * rs / t_bot)
				dr.append(d)
				tr.append(_body_ray(d).x)
				hr.append(float(e[2]) * (rs if j >= 5 else lerpf(1.0, rs, 0.4)))
			dirs.append(dr)
			tb.append(tr)
			hs.append(hr)
		# the cloth bridges the hollows between the trapezius and the deltoid (a few passes of its neighbours' mean, never under
		# the body): no creases in its top for the toon light to break up on
		var tt: Array = []
		for i in na:
			tt.append((tb[i] as PackedFloat32Array).duplicate())
		for pass_i in 6:
			var nt: Array = []
			for i in na:
				var row: PackedFloat32Array = (tt[i] as PackedFloat32Array).duplicate()
				for j in range(1, 8):
					var m: float = (tt[(i + na - 1) % na][j] + tt[(i + 1) % na][j] + tt[i][j - 1] + tt[i][j + 1] + 2.0 * tt[i][j]) / 6.0
					row[j] = maxf(tb[i][j], m)
				nt.append(row)
			tt = nt
		for i in na:
			var ring: Array[Vector3] = []
			var rc: Array[Color] = []
			for j in ns:
				var d: Vector3 = dirs[i][j]
				ring.append(MANTLE_O + d * (float(tt[i][j]) + float(hs[i][j])))
				rc.append(CAPE_DARK if int(sec[j][3]) == 2 else CAPE)
			grid.append(ring)
			cols.append(rc)
		for i in na:
			var i2 := (i + 1) % na
			for j in ns - 1:
				var p00: Vector3 = grid[i][j]
				var p01: Vector3 = grid[i][j + 1]
				var p11: Vector3 = grid[i2][j + 1]
				var p10: Vector3 = grid[i2][j]
				var c: Color = cols[i][j] if j < 6 else cols[i][j + 1]
				# (outwards: away from the body under it, MANTLE_O)
				_quad_out(soft, p00, p01, p11, p10, MANTLE_O, c)
		# the brooch: a gold disc with a raised rim and a boss, pinning the two sides of the cloth at the front
		var phb := _mantle_phi(0.0)
		var db := _mantle_dir(0.0, lerpf(phb.x, phb.y, 0.55))
		var bp := MANTLE_O + db * (_body_ray(db).x + 0.019)
		var bn := Vector3(0.0, 0.25, -1.0).normalized()
		var bx := Vector3.RIGHT
		var bz := bx.cross(bn).normalized()
		metal.push(Transform3D(Basis(bx, bn, bz), bp + bn * 0.004))
		metal.cyl(Vector3(0, -0.004, 0), 0.009, 0.041, 0.039, 16, GOLD_DARK)
		metal.ring(Vector3(0, 0.005, 0), 0.039, 0.029, 0.008, 16, GOLD_LIGHT)
		metal.cyl(Vector3(0, 0.003, 0), 0.004, 0.03, 0.028, 16, GOLD, true)
		metal.ico(Vector3(0, 0.009, 0), 0.014, GOLD_LIGHT, 1, 0.0, Vector3(1.0, 0.6, 1.0))
		metal.pop()
		sm.bind(func(p: Vector3) -> PackedFloat32Array: return _mantle_w(p))
		_cache["collar"] = sm.commit()
	return _cache["collar"]


## Rays for the mantle and the cloak's pins start here (inside the upper chest).
const MANTLE_O := Vector3(0.0, 1.43, 0.02)
## [|angle| round the neck (deg, 0 the front, 90 his side, 180 the back), the mantle's top elevation (its inner edge: the front
## band's upper edge, then the base of the neck), its bottom elevation (the rolled hem)] seen from MANTLE_O (deg).
const MANTLE_PHI := [[0.0, 20.0, 5.0], [25.0, 24.0, 3.0], [50.0, 32.0, -1.0], [72.0, 41.0, -7.0], [92.0, 46.0, -10.0],
	[110.0, 47.0, -8.0], [135.0, 46.0, -13.0], [160.0, 45.0, -17.0], [180.0, 45.0, -18.0]]


static func _mantle_dir(a: float, phi: float) -> Vector3:
	return Vector3(sin(a) * cos(phi), sin(phi), -cos(a) * cos(phi))


## The mantle's (top, bottom) elevation (rad) at angle a round the neck (a smooth curve through MANTLE_PHI).
static func _mantle_phi(a: float) -> Vector2:
	var x := rad_to_deg(absf(wrapf(a, -PI, PI)))
	var t := MANTLE_PHI
	var n := t.size()
	var k := 0
	while k < n - 2 and x > float(t[k + 1][0]):
		k += 1
	var f := clampf((x - float(t[k][0])) / (float(t[k + 1][0]) - float(t[k][0])), 0.0, 1.0)
	var out := Vector2.ZERO
	for c in 2:
		var p0: float = t[maxi(k - 1, 0)][c + 1]
		var p1: float = t[k][c + 1]
		var p2: float = t[k + 1][c + 1]
		var p3: float = t[mini(k + 2, n - 1)][c + 1]
		var f2 := f * f
		var v := 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f2 * f)
		out[c] = deg_to_rad(v)
	return out


## The distance from MANTLE_O along the unit direction d to the upper body's outer surface (rest rig space): the torso, the
## neck, the deltoids and the upper arms. y: 1 where that surface is an arm's.
static func _body_ray(d: Vector3) -> Vector2:
	var o := MANTLE_O
	# the torso (its rings, star-shaped round MANTLE_O): halving the way out
	var lo := 0.0
	var hi := 0.45
	for it in 12:
		var mid := (lo + hi) * 0.5
		if _torso_inside(o + d * mid):
			lo = mid
		else:
			hi = mid
	# (the muscles, a centimetre or two over the rings, added where the ray leaves them)
	var best := lo + maxf(_torso_push(o + d * lo).dot(d), 0.0)
	var arm := 0.0
	var tn := _ray_vcyl_exit(o, d, Vector2(0.0, 0.018), 0.083)
	if tn > best and (o + d * tn).y < 1.7:
		best = tn
	for s in [-1.0, 1.0]:
		var t := maxf(_ray_sphere_exit(o, d, Vector3(0.262 * s, 1.455, 0.022), 0.106), _ray_capsule_exit(o, d, Vector3(0.27 * s, 1.4, 0.024), mx(P_ELBOW, s), 0.1))
		if t > best:
			best = t
			arm = 1.0
	return Vector2(best, arm)


## Is p (rest rig space) inside the torso's rings (without the muscles)?
static func _torso_inside(p: Vector3) -> bool:
	var prof := TORSO_PROF
	var n := prof.size()
	if p.y < float(prof[0][0]) or p.y > float(prof[n - 1][0]):
		return false
	var k := 0
	while k < n - 2 and p.y > float(prof[k + 1][0]):
		k += 1
	var e0: Array = prof[k]
	var e1: Array = prof[k + 1]
	var f := (p.y - float(e0[0])) / (float(e1[0]) - float(e0[0]))
	var dz := p.z - lerpf(e0[4], e1[4], f)
	var rz := lerpf(e0[2], e1[2], f) if dz < 0.0 else lerpf(e0[3], e1[3], f)
	var sq := lerpf(e0[5], e1[5], f)
	return pow(absf(p.x) / lerpf(e0[1], e1[1], f), sq) + pow(absf(dz) / rz, sq) < 1.0


## Where a ray o + t d (d unit) leaves a sphere, a vertical cylinder (axis through (c.x, ., c.y)) or a capsule a-b (0: it misses).
static func _ray_sphere_exit(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.dot(oc) - r * r)
	if disc < 0.0:
		return 0.0
	return maxf(-b + sqrt(disc), 0.0)


static func _ray_vcyl_exit(o: Vector3, d: Vector3, c: Vector2, r: float) -> float:
	var ox := o.x - c.x
	var oz := o.z - c.y
	var qa := d.x * d.x + d.z * d.z
	if qa < 1e-8:
		return 0.0
	var qb := ox * d.x + oz * d.z
	var disc := qb * qb - qa * (ox * ox + oz * oz - r * r)
	if disc < 0.0:
		return 0.0
	return maxf((-qb + sqrt(disc)) / qa, 0.0)


static func _ray_capsule_exit(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best := maxf(_ray_sphere_exit(o, d, a, r), _ray_sphere_exit(o, d, b, r))
	var ab := b - a
	var l := ab.length()
	var u := ab / l
	var oc := o - a
	var dp := d - u * d.dot(u)
	var op := oc - u * oc.dot(u)
	var qa := dp.dot(dp)
	if qa > 1e-8:
		var qb := op.dot(dp)
		var disc := qb * qb - qa * (op.dot(op) - r * r)
		if disc >= 0.0:
			var t := (-qb + sqrt(disc)) / qa
			var hh := (oc + d * t).dot(u)
			if t > best and hh >= 0.0 and hh <= l:
				best = t
	return best


## Skin weights [bone, weight, ...] of a point of the mantle (or of the cloak's pinned row): those of the skin under it. Over
## the trapezius the chest and the clavicle (the torso's binding), at the base of the neck a little of the neck, over the
## deltoid the clavicle, PAUL and the upper arm (the arm's binding), blended across the top of the shoulder.
static func _mantle_w(p: Vector3) -> PackedFloat32Array:
	var ax := absf(p.x)
	var s := 1.0 if p.x >= 0.0 else -1.0
	var wc := smoothstep(0.12, 0.2, ax) * smoothstep(1.42, 1.48, p.y) * 0.7
	var wn := smoothstep(1.5, 1.56, p.y) * (1.0 - smoothstep(0.05, 0.11, ax)) * 0.5
	var sh := mx(P_SHOULDER, s)
	var top := (p - sh).dot((mx(P_ELBOW, s) - sh).normalized())
	var w_ua := smoothstep(0.03, 0.13, top)
	var w_cl := 1.0 - smoothstep(-0.075, -0.015, top)
	var w_pa := maxf(0.0, 1.0 - w_ua - w_cl)
	var k := smoothstep(0.17, 0.25, ax)
	var cl := CLAV_R if p.x >= 0.0 else CLAV_L
	var pa := PAUL_R if p.x >= 0.0 else PAUL_L
	var ua := UARM_R if p.x >= 0.0 else UARM_L
	var ws := [[CHEST, (1.0 - wc - wn) * (1.0 - k)], [cl, wc * (1.0 - k) + w_cl * k], [NECK, wn * (1.0 - k)], [pa, w_pa * k], [ua, w_ua * k]]
	var out := PackedFloat32Array()
	for e in ws:
		if float(e[1]) > 0.002 and out.size() < 8:
			out.append(float(e[0]))
			out.append(float(e[1]))
	return out


## A point on the torso's surface at angle a (0 front, PI/2 his right) and height y (rest rig space).
static func _torso_surf(a: float, y: float) -> Vector3:
	var prof := TORSO_PROF
	var e0: Array = prof[0]
	var e1: Array = prof[0]
	var f := 0.0
	if y >= float(prof[prof.size() - 1][0]):
		e0 = prof[prof.size() - 1]
		e1 = e0
	elif y > float(prof[0][0]):
		for k in prof.size() - 1:
			if y >= float(prof[k][0]) and y <= float(prof[k + 1][0]):
				e0 = prof[k]
				e1 = prof[k + 1]
				f = (y - float(e0[0])) / (float(e1[0]) - float(e0[0]))
				break
	var e := []
	for q in 6:
		e.append(lerpf(e0[q], e1[q], f))
	return _torso_pt(a, e)


# --- hands -------------------------------------------------------------------------------------------------

## Fist in hand space (rest frame of the hand bone of side s; origin at the wrist): fingers wrap the grip axis
## (Z) through GRIP; back of the hand towards +X*s, thumb on the -Z side. LOOK: the bracer's leather cuff round the
## wrist (it slides inside the bracer as the wrist bends).
static func fist_mesh(s: float) -> ArrayMesh:
	var key := "fist_%d" % int(s)
	if not _cache.has(key):
		var mb := MeshBuilder.new(51)
		var w := mx(P_WRIST, s)
		mb.push(Transform3D(Basis.IDENTITY, w))
		_cuff(mb)
		# (LOOK2: bigger, grown round the grip so the sword's hilt stays where it was)
		mb.push(Transform3D(Basis.from_scale(Vector3.ONE * HAND_GROW), GRIP * (1.0 - HAND_GROW)))
		mb.push(Transform3D(Basis.from_scale(Vector3.ONE * HAND_K), Vector3.ZERO))
		# palm + curled fingers: a rounded block around the grip
		mb.ico(Vector3(0.006 * s, -0.062, 0.0), 0.062, SKIN, 1, 0.0, Vector3(0.78, 0.92, 1.0))
		# knuckles ridge (the curled fingers), wrapping the grip on the palm side
		loft(mb, [[Vector3(-0.004 * s, -0.096, 0.055), 0.03, 0.034], [Vector3(-0.006 * s, -0.1, 0.0), 0.036, 0.038], [Vector3(-0.004 * s, -0.096, -0.052), 0.03, 0.034]], 10, SKIN, Vector3(s, 0, 0), true, true)
		# thumb over the index finger
		mb.limb(Vector3(-0.03 * s, -0.035, -0.04), Vector3(-0.034 * s, -0.08, -0.058), 0.021, 0.017, 6, SKIN_SHADE)
		mb.ico(Vector3(-0.034 * s, -0.082, -0.058), 0.018, SKIN_SHADE, 0)
		mb.pop()
		mb.pop()
		mb.pop()
		_cache[key] = mb.commit()
	return _cache[key]


## The leather cuff at the wrist (hand space, origin at the wrist).
static func _cuff(mb: MeshBuilder) -> void:
	loft(mb, [[Vector3(0, 0.04, 0), 0.06, 0.054], [Vector3(0, 0.0, 0), 0.062, 0.056], [Vector3(0, -0.014, 0), 0.061, 0.055], [Vector3(0, -0.02, 0), 0.052, 0.047]], 12,
		func(_p: Vector3, k: int, _i: int) -> Color: return LEATHER_DARK if k >= 1 else LEATHER, FWD, false, false)


## Open hand (left side, petting / reaching), in hand space at rest: palm facing -X*s... fingers down.
static func open_hand_mesh(s: float) -> ArrayMesh:
	var key := "open_%d" % int(s)
	if not _cache.has(key):
		var mb := MeshBuilder.new(53)
		var w := mx(P_WRIST, s)
		mb.push(Transform3D(Basis.IDENTITY, w))
		_cuff(mb)
		mb.push(Transform3D(Basis.from_scale(Vector3.ONE * HAND_GROW), GRIP * (1.0 - HAND_GROW)))
		mb.push(Transform3D(Basis.from_scale(Vector3.ONE * HAND_K), Vector3.ZERO))
		mb.ico(Vector3(0.0, -0.06, 0.0), 0.058, SKIN, 1, 0.0, Vector3(0.5, 0.95, 1.0))
		for k in 4:
			var z := -0.036 + 0.024 * float(k)
			mb.limb(Vector3(0.0, -0.1, z), Vector3(-0.012 * s, -0.165 + absf(z) * 0.4, z * 1.1), 0.0135, 0.011, 5, SKIN)
		mb.limb(Vector3(-0.012 * s, -0.04, -0.045), Vector3(-0.03 * s, -0.09, -0.075), 0.017, 0.014, 5, SKIN_SHADE)
		mb.pop()
		mb.pop()
		mb.pop()
		_cache[key] = mb.commit()
	return _cache[key]


# --- weapons -----------------------------------------------------------------------------------------------

## The sword's measures in grip space (m): the blade runs along -Z from SWORD_ROOT (just past the guard) to
## SWORD_TIP, a leaf widest (SWORD_W each side) about 62 % of the way out; SWORD_GUARD is the crossguard's half-width
## and SWORD_POMMEL the far end of the hilt. The hit sweep (blade_segment), the trail and the scabbard use them.
const SWORD_ROOT := -0.095
const SWORD_TIP := -1.075
const SWORD_W := 0.045
const SWORD_GUARD := 0.11
const SWORD_POMMEL := 0.14
## The hero's sword in grip space (a heroic leaf blade, xiphos-shaped, about 1.2 m long): origin where the fist
## holds it, blade along -Z, edges along ±Y, flats facing ±X. [soft (grip), metal (hilt, blade)]
static func sword_meshes() -> Array:
	if not _cache.has("sword"):
		var soft := MeshBuilder.new(61)
		var metal := MeshBuilder.new(62)
		# grip (dark leather wrap), long enough for the whole fist
		loft(soft, [[Vector3(0, 0, 0.088), 0.019, 0.017], [Vector3(0, 0, 0.0), 0.021, 0.019], [Vector3(0, 0, -0.074), 0.019, 0.017]], 8, LEATHER_DARK, Vector3.UP, false, false)
		# pommel and guard (bronze)
		metal.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.09)))
		metal.cyl(Vector3(0, -0.012, 0), 0.03, 0.034, 0.03, 12, BRONZE)
		metal.pop()
		metal.ico(Vector3(0, 0, 0.118), 0.028, BRONZE_LIGHT, 0, 0.0, Vector3(1.0, 1.0, 0.75))
		metal.box(Vector3(0, 0, -0.082), Vector3(0.042, SWORD_GUARD * 2.0, 0.028), BRONZE)
		metal.box(Vector3(0, 0, -0.088), Vector3(0.032, SWORD_GUARD * 1.45, 0.026), BRONZE_LIGHT)
		for sy in [-1.0, 1.0]:
			metal.ico(Vector3(0, sy * SWORD_GUARD, -0.082), 0.019, BRONZE_LIGHT, 0, 0.0, Vector3(1.0, 0.8, 1.0))
		# leaf blade: diamond section, waisted near the hilt, widest about 62 % of the way out
		var zs := [SWORD_ROOT, -0.16, -0.3, -0.48, -0.66, -0.8, -0.92, -1.0, -1.045, SWORD_TIP]
		var ws := [0.034, 0.03, 0.029, 0.034, 0.044, SWORD_W, 0.038, 0.026, 0.013, 0.0]
		var ts := [0.0105, 0.0095, 0.009, 0.009, 0.0095, 0.009, 0.008, 0.007, 0.0055, 0.0]
		for k in zs.size() - 1:
			var z0: float = zs[k]
			var z1: float = zs[k + 1]
			var w0: float = ws[k]
			var w1: float = ws[k + 1]
			var t0: float = ts[k]
			var t1: float = ts[k + 1]
			for sy in [-1.0, 1.0]:
				for sx in [-1.0, 1.0]:
					var e0 := Vector3(0, sy * w0, z0)
					var e1 := Vector3(0, sy * w1, z1)
					var r0 := Vector3(sx * t0, 0, z0)
					var r1 := Vector3(sx * t1, 0, z1)
					# bevel: the outer third of each face is the bright edge
					var m0 := e0.lerp(r0, 0.35)
					var m1 := e1.lerp(r1, 0.35)
					var a := [r0, m0, m1, r1]
					var b := [m0, e0, e1, m1]
					if sx * sy > 0.0:
						metal.quad(a[0], a[3], a[2], a[1], STEEL)
						metal.quad(b[0], b[3], b[2], b[1], STEEL_LIGHT)
					else:
						metal.quad(a[0], a[1], a[2], a[3], STEEL)
						metal.quad(b[0], b[1], b[2], b[3], STEEL_LIGHT)
		# blade root
		metal.box(Vector3(0, 0, -0.1), Vector3(0.023, 0.062, 0.016), STEEL_DARK)
		_cache["sword"] = [soft.commit(), metal.commit()]
	return _cache["sword"]


## The round shield in rest rig space, mounted on the left forearm (faces -X at rest). [soft, metal]
## LOOK: a gently domed leather face in two browns (a lighter ring band), a darker rolled rim, a small bronze boss, a
## faint darker club (Heracles' own) on the face; behind, the wooden bowl, the bronze arm band and the grip as before,
## and a leather carrying strap across the back (from local (-0.2, 0, -0.27) to (-0.2, 0, 0.27), on the wood).
static func shield_meshes() -> Array:
	if not _cache.has("shield"):
		var soft := MeshBuilder.new(71)
		var metal := MeshBuilder.new(72)
		var el := mx(P_ELBOW, -1.0)
		var wr := mx(P_WRIST, -1.0)
		var dfa := (wr - el).normalized()
		var cen := el + dfa * 0.13 + Vector3(-0.085, 0, 0)
		# shield frame: local +Y = outward normal (-X), local +X along the forearm
		var ny := Vector3(-1, 0, 0)
		var nx := perp(dfa, ny).normalized()
		var nz := nx.cross(ny)
		var xf := Transform3D(Basis(nx, ny, nz), cen)
		var R := SHIELD_R
		metal.push(xf)
		soft.push(xf)
		# the face: an inner field, a lighter band, the outer field, a darker ring at the rim
		var face_col := func(p: Vector3, _k: int, _i: int) -> Color:
			var r := Vector2(p.x, p.z).length() / R
			if r > 0.85:
				return SHIELD_FACE_DARK
			if r > 0.6 and r < 0.69:
				return SHIELD_FACE_LIGHT
			return SHIELD_FACE
		var face := [Vector2(R * 0.93, 0.012), Vector2(R * 0.85, 0.022), Vector2(R * 0.77, 0.031), Vector2(R * 0.69, 0.04),
			Vector2(R * 0.6, 0.048), Vector2(R * 0.42, 0.06), Vector2(R * 0.24, 0.068), Vector2(R * 0.13, 0.071), Vector2(0.0, 0.072)]
		soft.lathe(face, 32, face_col, 0.0, false, true)
		# the rim: dark bronze, rolled over the edge of the face
		metal.lathe([Vector2(R * 0.9, -0.03), Vector2(R * 0.97, -0.034), Vector2(R * 1.03, -0.02), Vector2(R * 1.045, 0.0), Vector2(R * 1.0, 0.019), Vector2(R * 0.92, 0.016)], 32,
			func(p: Vector3, k: int, _i: int) -> Color: return SHIELD_RIM_LIGHT if k == 3 else SHIELD_RIM, 0.0)
		# the boss: a small bronze dome in the centre
		metal.lathe([Vector2(R * 0.16, 0.068), Vector2(R * 0.15, 0.078), Vector2(R * 0.11, 0.092), Vector2(R * 0.05, 0.1), Vector2(0.0, 0.102)], 16,
			func(p: Vector3, k: int, _i: int) -> Color: return BRONZE_LIGHT if k >= 2 else BRONZE, 0.0, false, true)
		metal.lathe([Vector2(R * 0.185, 0.066), Vector2(R * 0.17, 0.073), Vector2(R * 0.15, 0.076)], 16, BRONZE_DARK, 0.0)
		# back of the bowl (wood, darker) and its rim
		soft.lathe([Vector2(0.0, 0.05), Vector2(R * 0.3, 0.043), Vector2(R * 0.6, 0.025), Vector2(R * 0.8, 0.004), Vector2(R * 0.9, -0.028)], 28, WOOD, 0.0, true, false)
		# porpax (arm band, bronze) and antilabe (grip cord)
		metal.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.04, -0.06, 0.0)))
		metal.ring(Vector3(0, -0.03, 0), 0.075, 0.064, 0.06, 12, BRONZE_DARK)
		metal.pop()
		soft.limb(Vector3(0.2, 0.03, -0.05), Vector3(0.2, -0.05, -0.05), 0.012, 0.012, 5, LEATHER)
		soft.limb(Vector3(0.2, 0.03, 0.05), Vector3(0.2, -0.05, 0.05), 0.012, 0.012, 5, LEATHER)
		soft.limb(Vector3(0.2, -0.05, -0.06), Vector3(0.2, -0.05, 0.06), 0.012, 0.012, 5, LEATHER)
		# the carrying strap across the back (the shield hangs on his back by it): a leather band on the wood, riveted
		var back_y := func(r: float) -> float:
			# the wooden back's height at radius r (the lathe above, linear between its rings)
			var prof := [[0.0, 0.05], [R * 0.3, 0.043], [R * 0.6, 0.025], [R * 0.8, 0.004], [R * 0.9, -0.028]]
			for k in prof.size() - 1:
				if r <= float(prof[k + 1][0]):
					return lerpf(prof[k][1], prof[k + 1][1], (r - float(prof[k][0])) / (float(prof[k + 1][0]) - float(prof[k][0])))
			return -0.028
		var sx := -0.2
		var segs := 8
		var prev_a := Vector3.ZERO
		var prev_b := Vector3.ZERO
		for k in segs + 1:
			var z := lerpf(-0.27, 0.27, float(k) / float(segs))
			var y: float = back_y.call(Vector2(sx, z).length()) - 0.007
			var a := Vector3(sx - 0.019, y, z)
			var b := Vector3(sx + 0.019, y, z)
			if k > 0:
				soft.quad(prev_a, prev_b, b, a, LEATHER_DARK)
				soft.quad(prev_a + Vector3(0, 0.004, 0), a + Vector3(0, 0.004, 0), b + Vector3(0, 0.004, 0), prev_b + Vector3(0, 0.004, 0), LEATHER_DARK)
			prev_a = a
			prev_b = b
		for zz in [-0.25, 0.25]:
			var yy: float = back_y.call(Vector2(sx, zz).length()) - 0.01
			metal.ico(Vector3(sx, yy, zz), 0.011, BRONZE, 0, 0.0, Vector3(1.0, 0.6, 1.0))
		# the emblem: Heracles' club, a shade darker than the leather, laid on the face along local x
		var lift := func(v: Vector3) -> Vector3:
			var r := Vector2(v.x, v.z).length() / R
			return Vector3(v.x, 0.072 - 0.066 * r * r + 0.0025, v.z)
		var rot := Basis(Vector3.UP, 0.6)
		for i in 8:
			var u0 := lerpf(-0.24, 0.17, float(i) / 8.0)
			var u1 := lerpf(-0.24, 0.17, float(i + 1) / 8.0)
			var w0 := lerpf(0.016, 0.042, float(i) / 8.0) + (0.007 if i % 3 == 1 else 0.0)
			var w1 := lerpf(0.016, 0.042, float(i + 1) / 8.0) + (0.007 if (i + 1) % 3 == 1 else 0.0)
			# (skip the boss: the club passes under it)
			if absf(u0) < R * 0.17 and absf(u1) < R * 0.17:
				continue
			var a := rot * Vector3(u0, 0, -w0)
			var b := rot * Vector3(u1, 0, -w1)
			var cc := rot * Vector3(u1, 0, w1)
			var d := rot * Vector3(u0, 0, w0)
			soft.quad(lift.call(a), lift.call(d), lift.call(cc), lift.call(b), SHIELD_FACE_DARK)
		var knob := rot * Vector3(0.2, 0, 0)
		soft.ico(lift.call(knob) - Vector3(0, 0.001, 0), 0.05, SHIELD_FACE_DARK, 0, 0.0, Vector3(1.0, 0.06, 1.0))
		metal.pop()
		soft.pop()
		_cache["shield"] = [soft.commit(), metal.commit()]
	return _cache["shield"]


## The chain-spear in grip space: origin at the throwing grip, head along -Z, chain coiled round the lower shaft.
## [soft (shaft), metal (head, butt, chain)]
static func spear_meshes(coil: bool = true) -> Array:
	var key := "spear" if coil else "spear_bare"
	if not _cache.has(key):
		var soft := MeshBuilder.new(81)
		var metal := MeshBuilder.new(82)
		# shaft
		loft(soft, [[Vector3(0, 0, 0.7), 0.021, 0.021], [Vector3(0, 0, 0.0), 0.023, 0.023], [Vector3(0, 0, -0.3), 0.02, 0.02]], 8, WOOD, Vector3.UP, false, false)
		# leather grip wrap
		loft(soft, [[Vector3(0, 0, 0.07), 0.026, 0.026], [Vector3(0, 0, -0.07), 0.026, 0.026]], 8, LEATHER, Vector3.UP, false, false)
		# socket + leaf head
		loft(metal, [[Vector3(0, 0, -0.27), 0.024, 0.024], [Vector3(0, 0, -0.33), 0.02, 0.02], [Vector3(0, 0, -0.345), 0.026, 0.026]], 8, BRONZE_DARK, Vector3.UP, true, false)
		var zs := [-0.34, -0.39, -0.45, -0.5, -0.545, -0.58]
		var ws := [0.018, 0.04, 0.046, 0.036, 0.018, 0.0]
		for k in zs.size() - 1:
			var z0: float = zs[k]
			var z1: float = zs[k + 1]
			var w0: float = ws[k]
			var w1: float = ws[k + 1]
			var t0 := 0.012
			var t1 := 0.012 if k + 1 < zs.size() - 1 else 0.0
			for sy in [-1.0, 1.0]:
				for sx in [-1.0, 1.0]:
					var e0 := Vector3(0, sy * w0, z0)
					var e1 := Vector3(0, sy * w1, z1)
					var r0 := Vector3(sx * t0, 0, z0)
					var r1 := Vector3(sx * t1, 0, z1)
					var colh := BRONZE_LIGHT if sx > 0.0 else BRONZE
					if sx * sy > 0.0:
						metal.quad(r0, r1, e1, e0, colh)
					else:
						metal.quad(r0, e0, e1, r1, colh)
		# butt cap and the ring the chain hangs from
		loft(metal, [[Vector3(0, 0, 0.69), 0.024, 0.024], [Vector3(0, 0, 0.75), 0.022, 0.022], [Vector3(0, 0, 0.77), 0.012, 0.012]], 8, BRONZE_DARK, Vector3.UP, false, true)
		metal.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.79)))
		metal.ring(Vector3(0, -0.006, 0), 0.03, 0.02, 0.012, 10, BRONZE)
		metal.pop()
		# chain coiled round the lower shaft: links along a helix, alternating planes (CORE: bronze, like the
		# chain that pays out when the spear flies; `coil` false: the bare spear in flight)
		var turns := 3.5
		var nl := 30 if coil else 0
		var rc := 0.05
		for i in nl:
			var k := float(i) / float(nl - 1)
			var ang := k * turns * TAU
			var z := lerpf(0.42, 0.66, k)
			var p := Vector3(cos(ang) * rc, sin(ang) * rc, z)
			var tang := Vector3(-sin(ang) * rc * turns * TAU, cos(ang) * rc * turns * TAU, 0.24).normalized()
			var radial := Vector3(cos(ang), sin(ang), 0)
			var nrm := radial if i % 2 == 0 else tang.cross(radial).normalized()
			_link(metal, p, tang, nrm, BRONZE_DARK if i % 2 == 0 else CHAIN_DARK)
		_cache[key] = [soft.commit(), metal.commit()]
	return _cache[key]


## One chain link: an elongated ring centred at p, long axis `t`, ring plane normal `n`.
static func _link(mb: MeshBuilder, p: Vector3, t: Vector3, n: Vector3, col: Color) -> void:
	var b := Basis(t.cross(n).normalized(), n.normalized(), t.normalized())
	var seg := 8
	var pts := []
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(Vector3(cos(a) * 0.016, 0.0, sin(a) * 0.026))
	for i in seg:
		var a0: Vector3 = pts[i]
		var a1: Vector3 = pts[(i + 1) % seg]
		var d0 := Vector3(a0.x, 0, a0.z * 0.6).normalized()
		var d1 := Vector3(a1.x, 0, a1.z * 0.6).normalized()
		var r := 0.0055
		var q0 := [a0 + d0 * r, a0 + Vector3(0, r, 0), a0 - d0 * r, a0 - Vector3(0, r, 0)]
		var q1 := [a1 + d1 * r, a1 + Vector3(0, r, 0), a1 - d1 * r, a1 - Vector3(0, r, 0)]
		for j in 4:
			var j2 := (j + 1) % 4
			mb.quad(p + b * q0[j], p + b * q0[j2], p + b * q1[j2], p + b * q1[j], col)


# --- build the rig -----------------------------------------------------------------------------------------

func _skinned_mi(parent: Node3D, mesh: ArrayMesh, skin: Skin, mat: ShaderMaterial, nm: String) -> MeshInstance3D:
	if mesh.get_surface_count() == 0:
		return null
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.skin = skin
	m.material_override = mat
	m.set_meta(&"own_material", mat)
	m.custom_aabb = AABB(Vector3(-2.2, -1.2, -2.2), Vector3(4.4, 4.4, 4.4))
	parent.add_child(m)
	m.skeleton = NodePath("..")
	_mesh_nodes.append(m)
	meshes.append(m)
	return m


func _rigid_mi(parent: Node3D, mesh: ArrayMesh, mat: ShaderMaterial, nm: String) -> MeshInstance3D:
	if mesh.get_surface_count() == 0:
		return null
	var m := MeshInstance3D.new()
	m.name = nm
	m.mesh = mesh
	m.material_override = mat
	m.set_meta(&"own_material", mat)
	parent.add_child(m)
	_mesh_nodes.append(m)
	meshes.append(m)
	return m


func _pivot(nm: String) -> Node3D:
	var p := Node3D.new()
	p.name = nm
	add_child(p)
	return p


func _build() -> void:
	skel = Skeleton3D.new()
	skel.name = "Skeleton"
	for i in NB:
		skel.add_bone("b%d" % i)
	add_child(skel)
	var skin := make_skin(_rest)
	var body := body_meshes()
	_skinned_mi(skel, body[0], skin, _mat_soft, "BodySoft")
	_skinned_mi(skel, body[1], skin, _mat_metal, "BodyMetal")
	_skinned_mi(skel, body[2], skin, _mat_kilt, "Kilt")
	# LOOK: the head and the hair (their own material: see _apply_outfit)
	var hd := head_meshes()
	_helm_mi = _skinned_mi(skel, hd[0], skin, _mat_helm, "Head")
	_hair_mi = _skinned_mi(skel, hd[1], skin, _mat_helm, "Hair")
	_helmet_mi.append(_helm_mi)
	_helmet_mi.append(_hair_mi)
	_crest_mi = MeshInstance3D.new()
	_crest_mi.name = "Crest"
	_crest_mi.visible = false
	skel.add_child(_crest_mi)
	# skinning pivots for rigid props (children are modelled in rest rig space)
	for nm in ["hand_r_s", "hand_l_s", "farm_l_s", "chest_s", "spear_s", "hood_s", "pelvis_s", "thigh_r_s", "thigh_l_s"]:
		_piv[nm] = _pivot(nm)
	_rigid_mi(_piv["hand_r_s"], fist_mesh(1.0), _mat_soft, "FistR")
	_fist_l = _rigid_mi(_piv["hand_l_s"], fist_mesh(-1.0), _mat_soft, "FistL")
	_open_l = _rigid_mi(_piv["hand_l_s"], open_hand_mesh(-1.0), _mat_soft, "OpenL")
	_open_l.visible = false
	var sh := shield_meshes()
	_shield_mi.append(_rigid_mi(_piv["farm_l_s"], sh[0], _mat_soft, "ShieldSoft"))
	_shield_mi.append(_rigid_mi(_piv["farm_l_s"], sh[1], _mat_metal, "ShieldMetal"))
	# API attachment nodes
	_hand_r = _pivot("HandR")
	_hand_l = _pivot("HandL")
	_head = _pivot("Head")
	_sword = Node3D.new()
	_sword.name = "Sword"
	_hand_r.add_child(_sword)
	var sw := sword_meshes()
	_rigid_mi(_sword, sw[1], _mat_metal, "SwordMetal")
	_rigid_mi(_sword, sw[0], _mat_soft, "SwordSoft")
	# spear: on the back (child of the chest pivot, placed in rest space) and in the left hand
	var sp := spear_meshes()
	_spear_back = Node3D.new()
	_spear_back.name = "SpearBack"
	_piv["spear_s"].add_child(_spear_back)
	_spear_back.transform = spear_back_xf()
	_rigid_mi(_spear_back, sp[0], _mat_soft, "SpearSoft")
	_rigid_mi(_spear_back, sp[1], _mat_metal, "SpearMetal")
	_spear_hand = Node3D.new()
	_spear_hand.name = "SpearHand"
	_hand_l.add_child(_spear_hand)
	# the fist holds the shaft SPEAR_HOLD towards the head from the spear's own origin
	_spear_hand.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, SPEAR_HOLD))
	_rigid_mi(_spear_hand, sp[0], _mat_soft, "SpearSoftH")
	_rigid_mi(_spear_hand, sp[1], _mat_metal, "SpearMetalH")
	_spear_hand.visible = false
	# cape: its own skeleton, one bone per cloth particle
	cape_skel = Skeleton3D.new()
	cape_skel.name = "CapeSkeleton"
	for k in CAPE_NC * CAPE_NR:
		cape_skel.add_bone("c%d" % k)
	add_child(cape_skel)
	for lion in [false, true]:
		var cm := cape_mesh(lion)
		var mi := _skinned_mi(cape_skel, cm[0], cm[1], _mat_soft, "Pelt" if lion else "Cape")
		mi.visible = not lion
		_cape_meshes.append(mi)
	# lion outfit: the hood (its own pivot, swung from the back onto the head) and the paws knotted on the chest
	_hood_mi = _rigid_mi(_piv["hood_s"], hood_meshes()[0], _mat_soft, "LionHood")
	_paws_mi = _rigid_mi(_piv["chest_s"], paws_mesh(), _mat_soft, "LionPaws")
	_hood_mi.visible = false
	_paws_mi.visible = false
	# named parts for tools/clip_check.gd (see clip_pairs / clip_volume)
	parts["sword"] = _sword
	parts["shield"] = _piv["farm_l_s"]
	parts["back_spear"] = _spear_back
	parts["torso"] = _piv["chest_s"]
	parts["head"] = _head
	parts["hips"] = _piv["pelvis_s"]
	parts["leg_r"] = _piv["thigh_r_s"]
	parts["leg_l"] = _piv["thigh_l_s"]
	for nm in act_names():
		ACTIONS[nm] = action_length(nm)
	# LOOK: the mantle and its gold brooch (skinned: the shoulders rise with the clavicles)
	var col := collar_meshes()
	_collar_mi.append(_skinned_mi(skel, col[0], skin, _mat_soft, "CapeCollar"))
	_collar_mi.append(_skinned_mi(skel, col[1], skin, _mat_metal, "Brooch"))
	_build_stow() # STOW: the scabbard and the carried weapons


## Where the spear sits on the back (rest rig space): head up over the left shoulder, butt at the right hip (the head's end and a point
## on the line to the butt). Under the lion pelt it lies lower and flatter, clear of the mane. (INTEGRATE: tilted out further, its head
## lower and wider of the head: from the front the old placement put the spearhead right beside his head, like a horn.)
const SPEAR_BACK_TIP := Vector3(-0.47, 1.8, 0.24)
const SPEAR_BACK_BUTT := Vector3(0.26, 0.72, 0.31)
const SPEAR_BACK_TIP_LION := Vector3(-0.45, 1.79, 0.24)
const SPEAR_BACK_BUTT_LION := Vector3(0.25, 0.89, 0.3)
## Where the spear sits on the back (rest rig space): head up over the left shoulder, butt at the right hip.
## Under the lion pelt it lies lower and flatter, clear of the mane.
static func spear_back_xf(lion: bool = false) -> Transform3D:
	var tip := SPEAR_BACK_TIP if not lion else SPEAR_BACK_TIP_LION
	var butt := SPEAR_BACK_BUTT if not lion else SPEAR_BACK_BUTT_LION
	var d := (tip - butt).normalized()
	var z := -d
	# (the spear's roll about its shaft is the one the left fist has when it closes on it, THROW_GRAB, so that the spear in the hand and
	# the one on the back are the same spear at the swap: `anim_check mode=swap` measures it. The fist's roll there is the authored one
	# (hlk = g_back), the hand takes the roll that keeps its wrist straight from the draw on)
	var x := perp(SPEAR_ROLL if not lion else SPEAR_ROLL_LION, z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x, y, z), tip - d * 0.58)


# --- pose evaluation ---------------------------------------------------------------------------------------

static func default_pose() -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(C_N)
	for k in NEUTRAL:
		set_ch(c, k, NEUTRAL[k])
	return c


static func set_ch(c: PackedFloat32Array, key: String, v: Variant) -> void:
	var o: int = CH[key]
	if v is Vector3:
		c[o] = v.x
		c[o + 1] = v.y
		c[o + 2] = v.z
	else:
		c[o] = float(v)


static func v3(c: PackedFloat32Array, o: int) -> Vector3:
	return Vector3(c[o], c[o + 1], c[o + 2])


static func eul(v: Vector3) -> Basis:
	return Basis(Vector3.UP, v.y) * Basis(Vector3.RIGHT, v.x) * Basis(Vector3.BACK, v.z)


## Hand basis from a blade direction and a back-of-hand direction (side s: +1 right, -1 left).
static func hand_basis(blade: Vector3, back: Vector3, s: float) -> Basis:
	var z := -blade.normalized()
	var x := perp(back, z)
	if x.length_squared() < 1e-6:
		x = perp(Vector3.RIGHT, z)
	x = x.normalized() * s
	return Basis(x, z.cross(x), z)


## Two-bone IK: returns [elbow, reached end].
static func ik2(s: Vector3, w: Vector3, pole: Vector3, a: float, b: float) -> Array:
	var d := w - s
	var dist := d.length()
	var dmax := a + b - 0.002
	var dmin := absf(a - b) + 0.02
	if dist < 1e-5:
		d = Vector3.DOWN
		dist = dmin
	var u := d / dist
	dist = clampf(dist, dmin, dmax)
	var e_end := s + u * dist
	var v := perp(pole, u)
	if v.length_squared() < 1e-8:
		v = perp(Vector3.BACK, u)
		if v.length_squared() < 1e-8:
			v = perp(Vector3.RIGHT, u)
	v = v.normalized()
	var ca := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
	var sa := sqrt(maxf(0.0, 1.0 - ca * ca))
	return [s + (u * ca + v * sa) * a, e_end]


## A direction given in chest space (k = 0) or rig space (k = 1), returned in rig space.
static func _spc(cb: Basis, v: Vector3, k: float) -> Vector3:
	if k <= 0.0:
		return cb * v
	if k >= 1.0:
		return v
	return (cb * v).lerp(v, k)


## A point given in chest space (k = 0) or rig space (k = 1), returned in rig space.
static func _spp(chest: Transform3D, p: Vector3, k: float) -> Vector3:
	if k <= 0.0:
		return chest * p
	if k >= 1.0:
		return p
	return (chest * p).lerp(p, k)


func _solve(c: PackedFloat32Array) -> void:
	var pb := eul(v3(c, C_PELR))
	var po := P_PELVIS + v3(c, C_PEL)
	var upright := _reduce_rot(v3(c, C_ROT)).length_squared() < 0.01
	var ground_ik := upright and _gnd_k > 0.001
	if ground_ik:
		# CORE foot IK: the hips sink so the leg over the lower ground still reaches it
		po.y += minf(0.0, minf(_gnd_dy.x, _gnd_dy.y)) * _gnd_k
	_bx[PELVIS] = Transform3D(pb, po)
	var sb := pb * eul(v3(c, C_SPN))
	var so := po + pb * (P_SPINE - P_PELVIS)
	_bx[SPINE] = Transform3D(sb, so)
	var cb := sb * eul(v3(c, C_CHS))
	var co := so + sb * (P_CHEST - P_SPINE)
	_bx[CHEST] = Transform3D(cb, co)
	var nb := cb * eul(v3(c, C_NEK))
	var no := co + cb * (P_NECK - P_CHEST)
	_bx[NECK] = Transform3D(nb, no)
	var hb := nb * eul(v3(c, C_HED))
	var ho := no + nb * (P_HEAD - P_NECK)
	_bx[HEAD] = Transform3D(hb, ho)
	_bx[CREST_B] = Transform3D(hb, ho + hb * (P_CREST - P_HEAD))
	var chest := Transform3D(cb, co)
	# legs
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var o := 0 if side == 0 else 3
		var H := po + pb * (mx(P_HIP, s) - P_PELVIS)
		var A := v3(c, C_FR if side == 0 else C_FL)
		var fbasis := eul(v3(c, C_FRR if side == 0 else C_FLR))
		var gy := 0.0
		if ground_ik:
			# CORE foot IK: the foot rides the ground under it and tilts with the slope
			gy = (_gnd_dy.x if side == 0 else _gnd_dy.y) * _gnd_k
			A.y += gy
			fbasis = _gnd_tilt.slerp(Basis.IDENTITY, 1.0 - _gnd_k) * fbasis
		if upright:
			# the sole (heel and toe) never sinks into the ground: lift the ankle instead
			var low := minf((fbasis * Vector3(0.0, -0.093, 0.075)).y, (fbasis * Vector3(0.0, -0.093, -0.22)).y)
			A.y = maxf(A.y, gy - low)
		var pole := _pole_eff(2 + side, A - H, v3(c, C_FRP if side == 0 else C_FLP))
		var r := ik2(H, A, pole, LEN_TH, LEN_SH)
		var K: Vector3 = r[0]
		var A2: Vector3 = r[1]
		var y1 := (K - H).normalized()
		# (the frame of both bones is the plane the knee bends in: its normal is hip-to-ankle x the knee's bend direction, which
		# is what ik2 used, so it is as continuous as the pole is. It used to be thigh axis x pole, which flips sign when the
		# thigh swings through the pole's direction: a hip flexed to 90 degrees with the pole straight ahead.)
		var x1 := _bend_normal(A2 - H, pole)
		var z1 := x1.cross(y1)
		_bx[THIGH_R + o] = Transform3D(Basis(x1, y1, z1) * _f0_th[side].transposed(), H)
		var ys := (A2 - K).normalized()
		_bx[SHIN_R + o] = Transform3D(Basis(x1, ys, x1.cross(ys)) * _f0_sh[side].transposed(), K)
		_bx[FOOT_R + o] = Transform3D(fbasis, A2)
	# arms
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var o := 0 if side == 0 else 4
		var clav_r := mx(P_CLAV, s)
		var sh_r := mx(P_SHOULDER, s)
		var hand_cs: Basis
		var wrist_cs: Vector3
		var pole_cs: Vector3
		var cbi := cb.inverse()
		var ks := c[C_HRS] if side == 0 else c[C_HLS]
		if side == 0:
			var h_nom_r := hand_basis(_spc(cb, v3(c, C_HRB), ks), _spc(cb, v3(c, C_HRK), ks), 1.0)
			var grip_rig := _keep_out(_spp(chest, v3(c, C_HR), ks), 0.075)
			var rr := clampf(c[C_HRR], 0.0, 1.0)
			if rr < 0.999:
				# the sword hand of an action that is not a blow (the roll, the victory, the grapple): the edge turned to whatever lets the
				# wrist stay straight, the blade where it was put (see hlr)
				var fa0r := _prelim_fa_dir(0, grip_rig - h_nom_r * GRIP, _spc(cb, v3(c, C_HRP), ks), chest, cb, co, clav_r, sh_r)
				h_nom_r = _free_hand(h_nom_r, fa0r, rr)
			hand_cs = cbi * h_nom_r
			wrist_cs = chest.affine_inverse() * grip_rig - hand_cs * GRIP
			pole_cs = cbi * _spc(cb, v3(c, C_HRP), ks)
		else:
			var hl_rig := _spp(chest, v3(c, C_HL), ks)
			_lh_held = Basis()
			_lh_on = false
			if c[C_HLX] > 0.001:
				# a held hand (the spear, the chain): hl is the wrist for the roll hlk (the fist is GRIP from it); with the roll free
				# (hlr < 1) the fist stays where it was put and the hand turns about the shaft to the roll that keeps the wrist straight,
				# the forearm's direction of the last frame being the one it is straight to
				var h_nom := hand_basis(_spc(cb, v3(c, C_HLB), ks), _spc(cb, v3(c, C_HLK), ks), -1.0)
				var rw := clampf(c[C_HLR], 0.0, 1.0)
				var h_tgt := h_nom
				if rw < 0.999:
					var fa0 := _prelim_fa_dir(1, hl_rig, _spc(cb, v3(c, C_HLP), ks), chest, cb, co, clav_r, sh_r)
					h_tgt = _free_hand(h_nom, fa0, rw)
					hl_rig = hl_rig + h_nom * GRIP - h_tgt * GRIP
				_lh_held = h_tgt
				_lh_on = true
			wrist_cs = chest.affine_inverse() * _keep_out(hl_rig, 0.085)
			pole_cs = cbi * _spc(cb, v3(c, C_HLP), ks)
		# the hand goes round the shoulder, never through it: the direction from the shoulder to the hand turns at most ARM_DIR_RATE rad/s
		# (a hand sent from one side of the shoulder to the other along a straight line passes close to it and its direction
		# would swing half a turn in a few frames, the whole arm with it)
		if side == 1 or not _wlim:
			wrist_cs = (sh_r - P_CHEST) + _limit_arm_dir(side, wrist_cs - (sh_r - P_CHEST))
		else:
			# (the sword hand of a blow goes where it was authored to go, and the limiter keeps up with it)
			var dw := wrist_cs - (sh_r - P_CHEST)
			if dw.length() > 1e-4:
				_arm_dir[0] = dw.normalized()
		if side == 1 or not _wlim:
			# (an arm is never locked straight: as the hand nears the length of the arm the elbow's angle changes ever faster, a
			# square root of the distance, and the last centimetres are a snap of the elbow; the reach closes on 98.5 % of it
			# softly. The sword arm of a blow is left as authored.)
			wrist_cs = (sh_r - P_CHEST) + _soft_reach(wrist_cs - (sh_r - P_CHEST))
		if side == 1:
			_dbg_wt = wrist_cs - (sh_r - P_CHEST)
		# clavicle: shrug when the hand goes high, protract when it reaches forward
		var dd := (wrist_cs - (sh_r - P_CHEST)).normalized()
		var elev := asin(clampf(dd.y, -1.0, 1.0))
		var raise := clampf((elev + 0.25) * 0.3, 0.0, 0.4)
		var prot := clampf(-dd.z * 0.16 - 0.02, -0.1, 0.16)
		var clb := cb * Basis(Vector3.BACK, raise * s) * Basis(Vector3.UP, prot * s)
		var clo := co + cb * (clav_r - P_CHEST)
		_bx[CLAV_R + o] = Transform3D(clb, clo)
		var S := clo + clb * (sh_r - clav_r)
		var W := chest * wrist_cs
		var pole := _pole_eff(side, W - S, cb * pole_cs)
		if side == 0 and _wlim:
			# (the elbow of a blow goes where the blow was built to put it: the tracking only follows it)
			pole = cb * pole_cs
		var r := ik2(S, W, pole, LEN_UA, LEN_FA)
		var E: Vector3 = r[0]
		# an elbow inside the body swings the other way round
		var e_safe := _keep_out(E, 0.06)
		if e_safe.distance_squared_to(E) > 1e-6:
			# (the push on the pole grows with how deep the elbow is in the body: a fixed push switched on at the first millimetre
			# flipped the elbow from one side of the arm to the other and back from one frame to the next)
			# (the sword arm of a blow keeps the fixed push the blows were built and measured with)
			var push := e_safe - E
			pole = (pole.normalized() + push.normalized() * (2.0 if (side == 0 and _wlim) else minf(push.length() * 40.0, 2.0))).normalized()
			r = ik2(S, W, pole, LEN_UA, LEN_FA)
			E = r[0]
		var W2: Vector3 = r[1]
		var y1 := (E - S).normalized()
		var x1 := -_bend_normal(W2 - S, pole)
		var z1 := x1.cross(y1)
		var bua := Basis(x1, y1, z1) * _f0_ua[side].transposed()
		_bx[UARM_R + o] = Transform3D(bua, S)
		var y1f := (W2 - E).normalized()
		if side == 1:
			_fa_dir_l = y1f
		var f1f := Basis(x1, y1f, x1.cross(y1f))
		var twist := 0.0
		var hand_b: Basis
		# (the forearm's twist follows the hand's side (the sword hand) or the shield's facing (the shield arm): where that
		# vector is nearly along the forearm's own axis the twist is undefined and the old fallback of 0 flipped the shield
		# 180 degrees in one frame, so it is tracked: it follows the vector in proportion to how well defined it is, else it
		# keeps what it was, and always takes the short way round)
		if side == 0:
			hand_b = cb * hand_cs
			if _wlim:
				hand_b = _wrist_limit(hand_b, y1f)
			var hx := perp(hand_b.x, y1f)
			var hxl := hx.length()
			if hxl > 1e-4:
				var cand := x1.signed_angle_to(hx / hxl, y1f) * 0.5
				_tw_fa[0] += _twist_step(wrapf(cand - _tw_fa[0], -PI, PI) * smoothstep(0.06, 0.3, hxl))
			twist = _tw_fa[0]
		else:
			# (the left forearm turns towards two things: the shield's facing, and, when the hand is held to an explicit frame (the
			# spear, the chain), the grip: the forearm turns with the hand so that the wrist is not asked for the whole turn. Each is the
			# angle nearest the twist it has now, so the mix of the two never goes the long way round; the grip's twist is kept within
			# what a forearm turns, and the wrist keeps the rest.)
			var tw := _tw_fa[1]
			var n := perp(_spc(cb, v3(c, C_HLF), ks), y1f)
			var nl := n.length()
			# (the forearm is ahead of the hand: it follows the grip from the first third of the hand's blend on)
			var hxw := clampf(clampf(c[C_HLX], 0.0, 1.0) * TW_LEAD, 0.0, 1.0)
			var w_s := maxf(1.0 - hxw, TW_SHIELD) * smoothstep(0.03, 0.2, nl)
			var d_s := 0.0
			if nl > 1e-4:
				d_s = clampf(tw + wrapf((-x1).signed_angle_to(n / nl, y1f) - tw, -PI, PI), -TW_MAX, TW_MAX) - tw
			var w_h := 0.0
			var d_h := 0.0
			if hxw > 0.001:
				var hb2f := _lh_held
				# (the hand swung so that its long axis lies along the forearm's: what is left to turn is the forearm's own twist)
				var f0 := _f0_fa[side]
				var yh := (hb2f * f0.y).normalized()
				var sw := Quaternion(yh, y1f) if yh.dot(y1f) > -0.999 else Quaternion.IDENTITY
				_dbg_wb = rad_to_deg(yh.angle_to(y1f))
				var hxv := perp(Basis(sw) * (hb2f * f0.x), y1f)
				if hxv.length() > 1e-4:
					# (the angle nearest the twist it has: at half a turn from the forearm's own the choice between the two ways round is the
					# one it is already taking)
					d_h = clampf(tw + wrapf(x1.signed_angle_to(hxv.normalized(), y1f) - tw, -PI, PI), -TW_HAND_MAX, TW_HAND_MAX) - tw
					w_h = hxw * smoothstep(0.03, 0.2, hxv.length())
			_dbg_tw = Vector4(rad_to_deg(d_s), w_s, rad_to_deg(d_h), w_h)
			if w_s + w_h > 1e-4:
				# (it comes back to the shield's twist faster than it leaves it for the hand's: the shield has to be clear of him again)
				_tw_fa[1] += _twist_step((d_s * w_s + d_h * w_h) / (w_s + w_h) * minf(w_s + w_h, 1.0), lerpf(TWIST_RATE_FREE, TWIST_RATE, hxw))
			twist = _tw_fa[1]
			# (the shield hangs from a strap on the forearm and slips round it: what the forearm could not give of the shield's facing
			# because it turned with the hand, the shield takes, up to SH_SLACK_MAX; the shield stays clear of his head and chest while the hand
			# draws a spear from his back)
			_sh_slack_t = 0.0
			if nl > 1e-4 and hxw > 0.001 and _brush <= 0.0005:
				_sh_slack_t = clampf(wrapf(tw + d_s - twist, -PI, PI), -SH_SLACK_MAX, SH_SLACK_MAX) * hxw * smoothstep(0.03, 0.2, nl)
			if _solve_dt > 0.0:
				_sh_slack = move_toward(_sh_slack, _sh_slack_t, SH_SLACK_RATE * _solve_dt)
			else:
				_sh_slack = _sh_slack_t
		var bfa := Basis(y1f, twist) * f1f * _f0_fa[side].transposed()
		_bx[FARM_R + o] = Transform3D(bfa, E)
		if side == 1:
			hand_b = bfa * eul(v3(c, C_HLW))
			var hx := clampf(c[C_HLX], 0.0, 1.0)
			if hx > 0.001:
				var hb2 := _lh_held
				# (the turn from the hand as the forearm carries it to the held frame, blended as a swing and a twist about the forearm's
				# own axis: a plain slerp between two frames half a turn apart changes the way round it goes in a frame, a snap of the wrist)
				var dq := (hand_b.inverse() * hb2).get_rotation_quaternion()
				if dq.w < 0.0:
					dq = -dq
				var ax := _f0_fa[side].y
				var tw_d := 2.0 * atan2(Vector3(dq.x, dq.y, dq.z).dot(ax), dq.w)
				var tw_q := Quaternion(ax, tw_d)
				var sw_q := dq * tw_q.inverse()
				# (the twist is followed as a continuous angle while the hand blends in or out; when the held frame is fully on, the same
				# rotation is renamed to its principal angle, so that a turn gone round on the way in does not have to be unwound on the way out)
				_wr_tw = _wr_tw + wrapf(tw_d - _wr_tw, -PI, PI) if _wr_on else tw_d
				if hx > 0.999:
					_wr_tw = tw_d
				_wr_on = true
				_dbg_wb2 = Vector3(rad_to_deg(tw_d), rad_to_deg(_wr_tw), rad_to_deg(sw_q.get_angle()))
				hand_b = hand_b * Basis(Quaternion.IDENTITY.slerp(sw_q, hx) * Quaternion(ax, _wr_tw * hx))
			else:
				_wr_on = false
		_bx[HAND_R + o] = Transform3D(hand_b, W2)
		# pauldron follows the clavicle and part of the arm
		var qp := clb.get_rotation_quaternion().slerp(bua.get_rotation_quaternion(), 0.45)
		_bx[PAUL_R + side] = Transform3D(Basis(qp), S)
	# skirt bones (static for now): follow the pelvis
	for i in SKIRT_N:
		_bx[SKIRT0 + i] = Transform3D(pb, po + pb * (_rest[SKIRT0 + i] - P_PELVIS))
	# whole-body rotation (rolls, swimming, death falls)
	var rv := v3(c, C_ROT)
	if rv.length_squared() > 1e-8:
		var rb := Basis(rv.normalized(), rv.length())
		var pv := v3(c, C_PIV)
		var root := Transform3D(rb, pv - rb * pv)
		for i in NB:
			_bx[i] = root * _bx[i]


## The direction the forearm will have when the wrist is put at `wrist_rig` (rig space) with the elbow towards `pole_rig`: a first solve of the
## arm, the clavicle's shrug in, the keep-out and the rate limiters left out. `chest`, `cb`, `co`: the chest's transform, basis, origin.
func _prelim_fa_dir(side: int, wrist_rig: Vector3, pole_rig: Vector3, chest: Transform3D, cb: Basis, co: Vector3, clav_r: Vector3, sh_r: Vector3) -> Vector3:
	var s := 1.0 if side == 0 else -1.0
	var wcs0 := chest.affine_inverse() * _keep_out(wrist_rig, 0.085)
	var d0 := (wcs0 - (sh_r - P_CHEST)).normalized()
	var clb0 := cb * Basis(Vector3.BACK, clampf((asin(clampf(d0.y, -1.0, 1.0)) + 0.25) * 0.3, 0.0, 0.4) * s) * Basis(Vector3.UP, clampf(-d0.z * 0.16 - 0.02, -0.1, 0.16) * s)
	var s0 := co + cb * (clav_r - P_CHEST) + clb0 * (sh_r - clav_r)
	var r0 := ik2(s0, chest * wcs0, pole_rig, LEN_UA, LEN_FA)
	return ((r0[1] as Vector3) - (r0[0] as Vector3)).normalized()


## The hand `h_nom` (a basis, its z the shaft or the blade's own axis, the fingers' length axis y pointing to the elbow) turned about z to the
## roll that keeps the wrist straight to a forearm running along `fa`, `rw` of the way back to the authored one (1 = as authored).
static func _free_hand(h_nom: Basis, fa: Vector3, rw: float) -> Basis:
	var zt := h_nom.z.normalized()
	var fp := fa - zt * fa.dot(zt)
	if fp.length() <= 0.2:
		return h_nom
	var y_h := -fp.normalized()
	var h_free := Basis(y_h.cross(zt), y_h, zt)
	return Basis(h_free.get_rotation_quaternion().slerp(h_nom.get_rotation_quaternion(), rw))


## The direction a limb bends towards, as ik2 would take it from the pole, kept continuous: where the pole lies along the limb's
## root-to-end line it defines no direction (ik2 then falls back on a fixed one and the knee or elbow flips to the other side in a
## frame), so the bend direction of the last frame is kept there, and it never turns faster than POLE_RATE rad/s about the line.
## `i`: 0 right arm, 1 left arm, 2 right leg, 3 left leg. Returns a pole (a unit vector across the line).
var _pole_prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
const POLE_RATE := 32.0


func _pole_eff(i: int, d: Vector3, pole: Vector3) -> Vector3:
	var u := d.normalized()
	var v := perp(pole, u)
	var vl := v.length()
	var w := smoothstep(0.03, 0.3, vl / maxf(pole.length(), 1e-6))
	var prev := perp(_pole_prev[i], u)
	var out: Vector3
	if prev.length_squared() < 1e-6:
		out = v.normalized() if vl > 1e-6 else perp(Vector3.BACK, u).normalized()
	else:
		prev = prev.normalized()
		if vl < 1e-6 or w <= 0.0:
			out = prev
		else:
			var cand := v / vl
			var ang := prev.signed_angle_to(cand, u) * w
			if _solve_dt > 0.0:
				ang = clampf(ang, -POLE_RATE * _solve_dt, POLE_RATE * _solve_dt)
			out = prev.rotated(u, ang)
	_pole_prev[i] = out
	return out


## The reach of an arm eased towards its end: up to 93 % of the arm's length as asked, then closing on 98.5 % of it.
func _soft_reach(d: Vector3) -> Vector3:
	var lmax := LEN_UA + LEN_FA
	var knee := 0.93 * lmax
	var top := 0.985 * lmax
	var l := d.length()
	if l <= 1e-5:
		return d
	if l > knee:
		var l2 := knee + (top - knee) * (1.0 - exp(-(l - knee) / (top - knee)))
		return d * (l2 / l)
	# (the other end: an elbow folds to 150 degrees of flexion, and the closer the hand comes the slower it goes on)
	if l < ELBOW_SOFT_D:
		var l3 := ELBOW_SOFT_D - (ELBOW_SOFT_D - ELBOW_MIN_D) * (1.0 - exp(-(ELBOW_SOFT_D - l) / (ELBOW_SOFT_D - ELBOW_MIN_D)))
		return d * (l3 / l)
	return d


## The shoulder-to-wrist distances at which an elbow is flexed 128 and 144 degrees (the range stops at 150).
static var ELBOW_SOFT_D := sqrt(LEN_UA * LEN_UA + LEN_FA * LEN_FA - 2.0 * LEN_UA * LEN_FA * cos(PI - deg_to_rad(128.0)))
static var ELBOW_MIN_D := sqrt(LEN_UA * LEN_UA + LEN_FA * LEN_FA - 2.0 * LEN_UA * LEN_FA * cos(PI - deg_to_rad(144.0)))
## The direction from each shoulder to its hand (chest space) as last solved, and how fast it may turn (rad/s).
var _arm_dir: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
const ARM_DIR_RATE := 30.0


func _limit_arm_dir(i: int, d: Vector3) -> Vector3:
	var l := d.length()
	if l < 1e-4:
		return d
	var u := d / l
	var prev := _arm_dir[i]
	if prev == Vector3.ZERO or _solve_dt <= 0.0:
		_arm_dir[i] = u
		return d
	var maxa := ARM_DIR_RATE * _solve_dt
	if prev.angle_to(u) > maxa:
		var axis := prev.cross(u)
		if axis.length_squared() < 1e-8:
			axis = perp(Vector3.UP, prev)
			if axis.length_squared() < 1e-8:
				axis = Vector3.RIGHT
		u = prev.rotated(axis.normalized(), maxa)
	_arm_dir[i] = u
	return u * l


## Normal of the plane a two-bone limb bends in: the root-to-end line `d` crossed with the pole's component across it (the same
## direction ik2 bends towards, with its fallback when the pole lies along the line).
static func _bend_normal(d: Vector3, pole: Vector3) -> Vector3:
	var u := d.normalized()
	var v := perp(pole, u)
	if v.length_squared() < 1e-8:
		v = perp(Vector3.BACK, u)
		if v.length_squared() < 1e-8:
			v = perp(Vector3.RIGHT, u)
	return u.cross(v.normalized()).normalized()


## Keeps a point (rig space) of radius r out of the torso, helmet, hips and thighs of the pose being solved
## (the chest, spine, pelvis, head and leg bones must already be solved).
func _keep_out(p: Vector3, r: float) -> Vector3:
	var ch := _bx[CHEST]
	var sp := _bx[SPINE]
	var pv := _bx[PELVIS]
	var cs := func(b: Transform3D, bone: int, q: Vector3) -> Vector3: return b.origin + b.basis * (q - _rest[bone])
	for it in 2:
		for sx in [-1.0, 1.0]:
			p = _push_capsule(p, cs.call(ch, CHEST, Vector3(0.085 * sx, 1.2, 0.0)), cs.call(ch, CHEST, Vector3(0.1 * sx, 1.43, 0.0)), 0.145 + r)
			p = _push_capsule(p, cs.call(sp, SPINE, Vector3(0.06 * sx, 1.03, 0.0)), cs.call(sp, SPINE, Vector3(0.07 * sx, 1.17, 0.0)), 0.13 + r)
		p = _push_capsule(p, cs.call(ch, CHEST, Vector3(0.0, 1.2, -0.01)), cs.call(ch, CHEST, Vector3(0.0, 1.42, -0.01)), 0.165 + r)
		p = _push_capsule(p, cs.call(pv, PELVIS, Vector3(-0.07, 0.88, 0.0)), cs.call(pv, PELVIS, Vector3(0.07, 0.88, 0.0)), 0.19 + r)
		var hc := _bx[HEAD].origin + _bx[HEAD].basis * (HEAD_C - P_HEAD)
		p = _push_capsule(p, hc, hc, 0.175 + r)
		for o in [0, 3]:
			p = _push_capsule(p, _bx[THIGH_R + o].origin, _bx[SHIN_R + o].origin, 0.095 + r)
	return p


## Pushes the solved bones to the skeleton and the pivots.
func _apply_bones() -> void:
	for i in NB:
		skel.set_bone_pose(i, _bx[i])
	_set_skin_pivot("hand_r_s", HAND_R)
	_set_skin_pivot("hand_l_s", HAND_L)
	_set_skin_pivot("farm_l_s", FARM_L)
	if _sh_slack != 0.0:
		(_piv["farm_l_s"] as Node3D).transform = _slack_xf() * (_piv["farm_l_s"] as Node3D).transform
	if _brush > 0.0005 and action == "":
		_brush_shield()
	_set_skin_pivot("chest_s", CHEST)
	_set_skin_pivot("pelvis_s", PELVIS)
	_set_skin_pivot("thigh_r_s", THIGH_R)
	_set_skin_pivot("thigh_l_s", THIGH_L)
	_set_blend_pivot("spear_s", SPINE, CHEST, 0.6, Vector3(0.0, 1.3, 0.25))
	var hr := _bx[HAND_R]
	_hand_r.transform = Transform3D(hr.basis, hr.origin + hr.basis * GRIP)
	var hl := _bx[HAND_L]
	_hand_l.transform = Transform3D(hl.basis, hl.origin + hl.basis * GRIP)
	var hd := _bx[HEAD]
	_head.transform = Transform3D(hd.basis, hd.origin + hd.basis * (HEAD_C - P_HEAD))
	_sword.transform = Transform3D(Basis(Vector3.RIGHT, _pose[C_GRIP]), Vector3.ZERO)
	_place_weapons() # STOW: the sword, the scabbard, the shield and the spear on the back where they are


## What the outfit shows this frame: don_skin swaps the cape for the pelt at DON_SWAP, swings the hood from the
## back onto the head (pose channel `hood`) and knots the paws at DON_KNOT.
func _update_outfit_state() -> void:
	_show_lion = outfit == &"lion"
	_show_hood = 1.0
	_show_paws = _show_lion
	if action == "don_skin" and _don_from_helmet:
		_show_lion = action_t >= DON_SWAP
		_show_hood = clampf(_pose[C_HOOD], 0.0, 1.0)
		_show_paws = action_t >= DON_KNOT


func _apply_outfit() -> void:
	if _cape_meshes.size() == 2:
		_cape_meshes[0].visible = not _show_lion
		_cape_meshes[1].visible = _show_lion
	_hood_mi.visible = _show_lion
	_paws_mi.visible = _show_paws
	for m in _collar_mi:
		m.visible = not _show_lion
	if _show_lion:
		(_piv["hood_s"] as Node3D).transform = hood_xf(_bx[HEAD], _rest[HEAD], _show_hood)
	# LOOK: the hood comes down over the hair (hidden once it is on, so no lock pokes through the mane) and the face sinks
	# into its shade
	_hair_mi.visible = not (_show_lion and _show_hood > HOOD_HAIR_OFF)
	var shade := smoothstep(0.55, 1.0, _show_hood) if _show_lion else 0.0
	if absf(shade - _helm_shade) > 0.01:
		_helm_shade = shade
		var k := lerpf(1.0, HOOD_SHADE, shade)
		_mat_helm.set_shader_parameter("tint", Vector3(k, k * 0.95, k * 1.02))
	if _spear_lion != _show_lion:
		_spear_lion = _show_lion
		_spear_back.transform = spear_back_xf(_show_lion)


## Shield frame (rig space) for a left forearm bone pose: origin at the shield's centre, +Y its outward normal,
## +X along the forearm (the frame shield_meshes() is modelled in).
static func shield_xf(farm_bx: Transform3D, farm_rest: Vector3) -> Transform3D:
	var el := mx(P_ELBOW, -1.0)
	var wr := mx(P_WRIST, -1.0)
	var dfa := (wr - el).normalized()
	var cen := el + dfa * 0.13 + Vector3(-0.085, 0, 0)
	var ny := Vector3(-1, 0, 0)
	var nx := perp(dfa, ny).normalized()
	var skin := Transform3D(farm_bx.basis, farm_bx.origin - farm_bx.basis * farm_rest)
	return skin * Transform3D(Basis(nx, ny, nx.cross(ny)), cen)


## Hood pivot transform (rig space) for a head bone pose: on the head at h = 1, swung back about the nape onto
## the upper back at h = 0.
static func hood_xf(head_bx: Transform3D, head_rest: Vector3, h: float) -> Transform3D:
	var skin_h := Transform3D(head_bx.basis, head_bx.origin - head_bx.basis * head_rest)
	var r := Basis(Vector3.RIGHT, (1.0 - h) * HOOD_DOWN)
	return skin_h * Transform3D(r, HOOD_HINGE - r * HOOD_HINGE)


## Spear (back or left hand) and the left hand's shape.
func _apply_props() -> void:
	var back := spear_on_back
	var in_hand := false
	if action == "throw" and action_t >= THROW_GRAB:
		back = false
		in_hand = action_t < THROW_RELEASE
	elif action == "catch" and action_t < CATCH_STOW:
		back = false
		in_hand = true
	_spear_back.visible = back
	_spear_hand.visible = in_hand
	var open := _pose[C_OHL] > 0.5
	_open_l.visible = open
	_fist_l.visible = not open


## A pivot between two bones (rotation slerped, `ref` placed halfway): for props strapped across both.
func _set_blend_pivot(nm: String, a: int, b: int, k: float, ref: Vector3) -> void:
	(_piv[nm] as Node3D).transform = blend_skin(a, b, k, ref)


func blend_skin(a: int, b: int, k: float, ref: Vector3) -> Transform3D:
	var ba := _bx[a]
	var bb := _bx[b]
	var q := ba.basis.get_rotation_quaternion().slerp(bb.basis.get_rotation_quaternion(), k)
	var bs := Basis(q)
	var pa := ba.origin + ba.basis * (ref - _rest[a])
	var pb := bb.origin + bb.basis * (ref - _rest[b])
	var pr := pa.lerp(pb, k)
	return Transform3D(bs, pr - bs * ref)


## Skinning matrix of a bone as a node transform: children modelled in rest rig space follow the bone.
func _set_skin_pivot(nm: String, bone: int) -> void:
	var b := _bx[bone]
	(_piv[nm] as Node3D).transform = Transform3D(b.basis, b.origin - b.basis * _rest[bone])


# --- API ---------------------------------------------------------------------------------------------------

func hand_r() -> Node3D:
	return _hand_r


func hand_l() -> Node3D:
	return _hand_l


func head() -> Node3D:
	return _head


func chain_origin() -> Vector3:
	return _hand_l.global_position if _hand_l.is_inside_tree() else _hand_l.position


var _blade := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])


## CORE: the sword blade's root and tip as posed this frame (world space when in the tree): [root, tip]. The
## hero's sword sweep and its trail read it.
func blade_segment() -> PackedVector3Array:
	var gx := _sword.global_transform if _sword.is_inside_tree() else transform * _hand_r.transform * _sword.transform
	_blade[0] = gx * Vector3(0.0, 0.0, -0.1)
	_blade[1] = gx * Vector3(0.0, 0.0, SWORD_TIP + 0.005)
	return _blade




# --- animation: state ----------------------------------------------------------------------------------------

## Right shoulder in chest space (pivot of the sword swings).
const SHOULDER_CS := Vector3(0.255, 0.175, 0.02)
## Water surface height above the rig origin while swimming (the hero code keeps the origin this far below it).
var swim_waterline := 1.2
## Tools: pretend the rig moves at this world velocity (cloth and secondary motion react as if it did).
var velocity_hint := Vector3.ZERO
## Key of the definition being played (the outfit variant of `action`).
var _akey := ""
var _src := PackedFloat32Array()
var _from := PackedFloat32Array()
var _blend_t := 1.0
var _blend_len := 0.1
var _hold := false
var _spd := 0.0
var _guard_k := 0.0
var _guard_v := 0.0
## The shield's spring (rad/s, damping ratio): 0.62 overshoots the guard pose by about 8 % and settles in a quarter of a second.
const GUARD_W := 24.0
const GUARD_Z := 0.62
## The landing's spring on the pelvis: `_land_x` (m, negative = down), its speed, the strength of the impact that excited it.
const LAND_W := 21.0
const LAND_Z := 0.48
var _land_x := 0.0
var _land_v := 0.0
var _land_k := 0.0
## The vertical speed the body had the last tick it was in the air (the speed the ground is met at).
var _vy_air := 0.0
var _vy := 0.0
var _swim_phase := 0.0
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _yaw_rate := 0.0
var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _have_prev := false
var _crest := Vector2.ZERO
var _crest_v := Vector2.ZERO
var _prev_head_v := Vector3.ZERO
var _prev_head_p := Vector3.ZERO

static var _acts := {}

# --- CORE combat additions ---
## Playback speed of the current action (play_at sets it; play resets it to 1).
var action_speed := 1.0
## When >= 0 the current action holds at this time (the heavy blow's charge); -1 lets it run.
var action_hold := -1.0
## 0..1 strain of a held charge: the chest and the sword hand tremble.
var charge := 0.0
## 0..1 exhaustion: heavier breathing and a slight hunch while standing.
var tired := 0.0
## 1 while the current action is upper-body only (play_at upper): legs and hips keep the locomotion.
var _upper := 0.0
## Shield jolt of a blocked blow (guard_impact), springing back to 0.
var _jolt := 0.0
var _jolt_v := 0.0
## Smoothed direction of travel in rig space (x right, y back): strafing and back-pedalling gaits.
var _mdir := Vector2(0.0, -1.0)
## CORE foot IK: the ground under the right / left foot relative to the rig origin (m, smoothed), the slope's
## tilt (rig space) and how much it applies (0 in the air, 1 on the ground). Fed by the hero (set_ground).
var _gnd_dy := Vector2.ZERO
var _gnd_goal := Vector2.ZERO
var _gnd_tilt := Basis.IDENTITY
var _gnd_n_goal := Vector3.UP
var _gnd_k := 0.0
var _gnd_on := false
## Hanging from the chain: the swing of the body under the hand.
var _hang_sw := 0.0
var _hang_swv := 0.0
## The ground gait's state (the gait code is below, "animation: the ground gait"): the phase of the right foot (0 = it
## touches down), whether the cycle drives the feet, the planted feet and their swings, the springs of the lean.
var _gph := 0.0
var _gait_on := false
var _gait_w := 0.0
var _a_fwd := 0.0
var _speed_prev := 0.0
var _fp_ok := false
var _gp_n := -10
var _gp_prev := -10
var _pel_yp := 0.0
var _pel_ok := false
var _adv_n := 0
## Tools: start the gait at this phase (previews); the rig's world XZ and yaw this frame; the instantaneous yaw rate.
var _pv_phase := -1.0
var _rp := Vector2.ZERO
var _ry := 0.0
var _yaw_inst := 0.0
var _yaw_lead := 0.0
var _vu := 0.0
var _yaw_head := 0.0
var _mv_arm := 0.0
## Direction of travel in rig space as an angle (0 forward, + to the right).
var _mang := 0.0
var _lean_acc := 0.0
var _lean_accv := 0.0
var _roll_turn := 0.0
var _roll_turnv := 0.0
## Per foot (0 right, 1 left): state, the pinned contact point (world XZ; the heel, then the toe) and which, the foot's
## world yaw, the pitch it touched down with, the swing's start (ankle world XZ, height, pitch, yaw), its progress and
## length (home steps), the phase it lifted at, the phase offset and last phase, and what the frame produced: the ankle
## (rig space and world XZ), pitch, yaw, how much the pelvis must respect it.
var _ft_st := PackedInt32Array([0, 0])
var _ft_kind := PackedInt32Array([0, 0])
var _ft_pin := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _ft_yaw := PackedFloat32Array([0.0, 0.0])
var _ft_th0 := PackedFloat32Array([0.0, 0.0])
var _ft_from := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _ft_from_y := PackedFloat32Array([0.093, 0.093])
var _ft_from_th := PackedFloat32Array([0.0, 0.0])
var _ft_from_yaw := PackedFloat32Array([0.0, 0.0])
var _ft_s := PackedFloat32Array([0.0, 0.0])
var _ft_dur := PackedFloat32Array([0.2, 0.2])
var _ft_philo := PackedFloat32Array([0.0, 0.0])
var _ft_off := PackedFloat32Array([0.0, 0.5])
var _ft_phi := PackedFloat32Array([0.0, 0.5])
var _ft_ank := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _ft_aw := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _ft_ay := PackedFloat32Array([0.093, 0.093])
var _ft_pit := PackedFloat32Array([0.0, 0.0])
var _ft_wy := PackedFloat32Array([0.0, 0.0])
var _ft_ry := PackedFloat32Array([0.0, 0.0])
var _ft_w := PackedFloat32Array([1.0, 1.0])
var _ft_pv := PackedFloat32Array([0.0, 0.0])
var _ft_from_pv := PackedFloat32Array([0.0, 0.0])
## The spot a swinging foot is set down on (world XZ, pitch, yaw).
var _ft_goal := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _ft_goal_th := PackedFloat32Array([0.0, 0.0])
var _ft_goal_yaw := PackedFloat32Array([0.0, 0.0])
## Channels the legs and hips take from the locomotion under an upper-body action.
const LOWER_CH := [C_FR, C_FRR, C_FRP, C_FL, C_FLR, C_FLP, C_PEL]


## Upper-body layering: legs and hips from the locomotion pose, the rest from the action.
## Actions that keep the air pose's legs when they are played in the air (the others have legs of their own: a jump, a roll).
const AIR_LAYERED := ["hit", "hit_heavy", "recoil", "death", "parry", "catch", "pull"]
var _airl := 0.0


## Mixes the locomotion's pose into an action's by `k` (0..1) for everything above the hips: the legs, the pelvis' translation and
## the whole-body rotation stay the action's (their blend is the exit's, inertialized, from the action's last pose).
func _handover(dst: PackedFloat32Array, loco: PackedFloat32Array, k: float) -> void:
	for i in C_N:
		if (i >= C_PEL and i < C_PEL + 3) or (i >= C_FR and i < C_PIV + 3):
			continue
		dst[i] = lerpf(dst[i], loco[i], k)


func _layer_lower(dst: PackedFloat32Array, loco: PackedFloat32Array, w: float = 1.0) -> void:
	for o in LOWER_CH:
		dst[o] = lerpf(dst[o], loco[o], w)
		dst[o + 1] = lerpf(dst[o + 1], loco[o + 1], w)
		dst[o + 2] = lerpf(dst[o + 2], loco[o + 2], w)
	# the hips turn half with the action, half with the gait; no whole-body rotation
	for j in 3:
		dst[C_PELR + j] = lerpf(dst[C_PELR + j], lerpf(loco[C_PELR + j], dst[C_PELR + j], 0.5), w)
		dst[C_ROT + j] = lerpf(dst[C_ROT + j], loco[C_ROT + j], w)
		dst[C_PIV + j] = lerpf(dst[C_PIV + j], loco[C_PIV + j], w)


## CORE foot IK input: the ground height under the right and left foot relative to the rig origin (m) and the ground
## normal (world). `on` false (in the air, swimming...) fades the adaptation out.
func set_ground(dy_right: float, dy_left: float, normal_world: Vector3, on: bool) -> void:
	_gnd_on = on
	_gnd_goal = Vector2(clampf(dy_right, -0.45, 0.45), clampf(dy_left, -0.45, 0.45))
	var gb := global_transform.basis if is_inside_tree() else transform.basis
	_gnd_n_goal = (gb.inverse() * normal_world).normalized() if normal_world.length() > 0.01 else Vector3.UP


## Rig-space ankle position of the right (0) or left (1) foot as posed this frame.
func foot_local(side: int) -> Vector3:
	return _bx[FOOT_R if side == 0 else FOOT_L].origin


func _update_ground(dt: float) -> void:
	var k := 1.0 - exp(-dt * 14.0)
	_gnd_k = move_toward(_gnd_k, 1.0 if (_gnd_on and motion_state == &"ground") else 0.0, dt * 6.0)
	_gnd_dy = _gnd_dy.lerp(_gnd_goal if _gnd_on else Vector2.ZERO, k)
	var n := _gnd_n_goal if _gnd_on else Vector3.UP
	# never tilt the feet more than 35 degrees
	if n.angle_to(Vector3.UP) > deg_to_rad(35.0):
		n = Vector3.UP.slerp(n, deg_to_rad(35.0) / n.angle_to(Vector3.UP))
	var want := Basis(Quaternion(Vector3.UP, n.normalized())) if n.cross(Vector3.UP).length() > 1e-4 else Basis.IDENTITY
	_gnd_tilt = _gnd_tilt.slerp(want, k).orthonormalized()


## CORE: a blow lands on the raised shield (0..1): the shield arm and the chest are knocked back and spring back.
func guard_impact(strength: float = 1.0) -> void:
	_jolt_v += 9.0 * clampf(strength, 0.0, 1.5)


# --- animation: API ------------------------------------------------------------------------------------------

func set_motion_state(s: StringName) -> void:
	if s == motion_state:
		return
	if motion_state == &"air" and s == &"ground":
		_land_impact(-minf(_vy_air, 0.0))
	motion_state = s
	_io_src_new = true # (the locomotion's last frame came from another generator: no velocity to take from it)
	if action == "" or not is_busy():
		_start_blend(0.18 if s != &"zip" else 0.1)


func set_vertical_speed(vy: float) -> void:
	vspeed = vy
	if motion_state == &"air":
		_vy_air = vy


## The ground is met at `v` m/s: the pelvis gives under it (about 1.2 cm per m/s, at most 20 cm; less when the landing action's own
## crouch comes with it) and the spring brings it back.
func _land_impact(v: float) -> void:
	if v < 2.0:
		return
	var depth := clampf(v * 0.012, 0.0, 0.2) * (0.45 if action == "land" else 1.0)
	_land_v = minf(_land_v, -depth * LAND_W * 2.4)
	_land_k = clampf(v / 14.0, 0.0, 1.0)


## The authored seconds from which a blow's recovery may be cancelled into the guard (HeroMelee `cancel`): the hero is already
## guarding then (his state is MOVE) and the shield comes up at once, instead of waiting for the end of a recovery he has left.
## (attack1..3 are the old names: they play a1, a2, a4.)
const GUARD_CUT := {"a1": 0.30, "a2": 0.24, "a3": 0.28, "a4": 0.50, "b1": 0.27, "b2": 0.24, "b3": 0.46, "dash": 0.56, "heavy": 0.80,
	"attack1": 0.30, "attack2": 0.24, "attack3": 0.50}


func set_guard(on: bool) -> void:
	if on and not guard and _upper == 0.0 and GUARD_CUT.has(action) and action_t >= float(GUARD_CUT[action]):
		stop_action(0.14)
	guard = on


# --- FINAL: the free hand brushing the wheat (the client's "Gladiator" shot) -----------------------------------

## Weight the hero asks for (0..1, every tick through set_brush()): the left hand lets go of the shield's grip and
## lowers out beside the hip, open and palm down, so the fingertips skim the ears as he walks; the shield stays on
## the forearm (its face turned out), the sword hand is untouched. The rig eases in over ~0.45 s and out over ~0.3 s,
## fades it under the guard and lets any action (a blow, a roll, interact) take the arm over.
var brush_goal := 0.0
## Rig-space height of the left wrist while brushing (the ears' tops + a little: Hero._feed_brush measures them).
var brush_height := 1.06
var _brush := 0.0


func set_brush(amount: float, wrist_height: float = 1.06) -> void:
	brush_goal = clampf(amount, 0.0, 1.0)
	brush_height = clampf(wrist_height, 0.82, 1.2)


## 0..1: how far the brush pose is in now (the hero hangs the hand's pusher on it).
func brush_amount() -> float:
	return smooth(_brush) if action == "" else 0.0


## Definition actually played for action `a` (the lion outfit draws the spear from its own place on the back).
func _variant(a: String) -> String:
	if a == "throw" or a == "catch":
		# (STOW: with the shield on his back the spear lies over it: the hand finds it there)
		var v := a + ("_over" if _spear_over > 0.5 else "")
		return v + "_lion" if _show_lion else v
	if a == "draw_shield" and guard:
		return "draw_shield_guard" # (STOW: drawn for the guard it ends up in front)
	if a == "draw_sword" and DRAW_INTO.has(draw_into):
		return "draw_sword_" + draw_into # (INTEGRATE: the quick draw that leads into the blow pressed)
	return a


func play(a: String) -> float:
	var def := act_def(_variant(a))
	if def.is_empty():
		push_warning("RigHeracles: unknown action '%s'" % a)
		return 0.0
	_start_blend(float(def["in"]))
	if action == "don_skin" and _don_from_helmet and action_t >= DON_SWAP:
		outfit = &"lion"
	if a == "don_skin":
		_don_from_helmet = not _show_lion
	action = a
	_akey = _variant(a)
	action_t = 0.0
	action_len = float(def["len"])
	_io_from_strike = false
	_fired.clear()
	if (a == "don_skin") != _don_hide:
		_don_hide = a == "don_skin"
		_update_weapons()
	_hold = bool(def.get("hold", false))
	action_speed = 1.0
	action_hold = -1.0
	_upper = 0.0
	if a == "hit" or a == "hit_heavy":
		# (on the move the reaction is the upper body's: the legs stumble on the gait the knock-back puts them in)
		_upper = 1.0 if _spd > 1.5 else 0.0
		# which way the blow pushes him is read from his own motion a few frames in (the hero code adds the knock-back to
		# his velocity): the reaction is authored for a blow from the front and turned about the vertical to that direction
		var lv := (global_transform.basis.inverse() if is_inside_tree() else Basis.IDENTITY) * _vel_inst
		_hit_v0 = Vector2(lv.x, lv.z)
		_hit_set = false
		_hit_ang = 0.0
	_sk_init = true
	_sk_run = def.has("strike") and _spd > SK_RUN_V and not _strike_own_legs(def["strike"])
	return action_len


## CORE: play `a` at `spd` times its authored speed; `upper` keeps the legs and hips on the locomotion (throwing
## while running or in the air, the charge walk). Returns the real duration (s).
func play_at(a: String, spd: float = 1.0, upper: bool = false) -> float:
	var l := play(a)
	action_speed = maxf(spd, 0.01)
	_upper = 1.0 if upper else 0.0
	return l / action_speed


## CORE: stop the current action without the out-blend jump (the locomotion or the next action blends in).
func stop_action(blend: float = 0.15) -> void:
	if action == "":
		return
	_io_from_strike = act_def(_akey).has("strike") or action == "throw" # INTEGRATE (see IO_STRIKE_V)
	if action == "don_skin" and _don_hide:
		_don_hide = false
		_update_weapons()
	action = ""
	action_hold = -1.0
	_start_blend(blend)


func _on_action_done(a: String) -> void:
	if a == "don_skin":
		outfit = &"lion"
		if _don_hide:
			_don_hide = false
			_update_weapons()


## Length of an action in seconds (0 if unknown), without playing it.
func action_length(a: String) -> float:
	var def := act_def(a)
	return float(def["len"]) if not def.is_empty() else 0.0


func _start_blend(dur: float) -> void:
	if _pose.size() == C_N:
		_from = _pose.duplicate()
	else:
		_from = default_pose()
	_blend_t = 0.0 if dur > 0.0 else 1.0
	_blend_len = maxf(dur, 0.03)
	# (the whole-body rotation still mixes from the snapshot above; everything else is inertialized, see _blend_out)
	_io_pending = dur > 0.0 and _out_p1.size() == C_N
	_io_len = _blend_len
	if dur <= 0.0:
		_io_on = false


func _process(delta: float) -> void:
	advance(delta)


## One animation step (the rig calls it from _process; tools call it directly with a fixed step).
func advance(delta: float) -> void:
	delta = clampf(delta, 0.0, 0.1)
	_adv_n += 1
	t += delta
	_track_motion(delta)
	if action != "":
		if _akey == "" or not _akey.begins_with(action):
			_akey = _variant(action)
		action_t += delta * action_speed
		if action_hold >= 0.0:
			action_t = minf(action_t, action_hold)
		var def := act_def(_akey)
		if bool(def["loop"]):
			if action_t >= action_len:
				action_t = fposmod(action_t, action_len)
				_fired.clear()
		elif action_t >= action_len:
			if _hold:
				action_t = action_len
			else:
				var done := action
				action = ""
				_io_from_strike = def.has("strike") or done == "throw" # INTEGRATE (see IO_STRIKE_V)
				_start_blend(float(def["out"]))
				_on_action_done(done)
	if _flash > 0.0:
		if _flash_fresh:
			_flash_fresh = false
		else:
			_flash = maxf(0.0, _flash - _real_dt(delta) * FLASH_DECAY)
			_apply_flash()
	_animate(delta)


func _animate(delta: float) -> void:
	# a blow built from joint angles drives its own feet (the gait only follows its state afterwards)
	var sk := false
	var skl := false
	var skc := false
	if action != "":
		if _akey == "" or not _akey.begins_with(action):
			_akey = _variant(action)
		sk = _upper == 0.0 and act_def(_akey).has("strike")
		skl = sk and _sk_run
		sk = sk and not _sk_run
		# (the heavy's charge: the legs and hips on the locomotion, the coil held as authored)
		skc = _upper > 0.0 and act_def(_akey).has("strike")
	if sk != _sk_on:
		_sk_on = sk
		if sk:
			_strike_begin()
		else:
			_strike_end()
	if (skl or skc) != _skl_on:
		_skl_on = skl or skc
		if not _skl_on:
			_wlim_tail = 0.4 # (a blow on the run or its held coil ends: the wrist limit holds while it blends out)
	_wlim_tail = maxf(0.0, _wlim_tail - delta)
	_wlim = sk or skl or skc or _wlim_tail > 0.0
	var loco := _loco_pose(delta)
	# an action that plays in the air (a hit, a recoil) leaves the legs to the air pose (eased in and out with the state)
	_airl = move_toward(_airl, 1.0 if (action != "" and AIR_LAYERED.has(action) and motion_state == &"air") else 0.0, delta * 8.0)
	if action != "":
		_src = sample_action(_akey, action_t)
		if skc:
			_strike_layer(_src, loco)
		elif _upper > 0.0:
			_layer_lower(_src, loco)
		elif sk:
			_strike_feet(_src, delta)
		elif skl:
			_strike_layer(_src, loco)
		if _airl > 0.001 and _upper == 0.0 and not (sk or skl or skc):
			_layer_lower(_src, loco, smooth(_airl))
		_hit_dir_apply(_src)
		_stow_layer(_src, loco) # STOW: a draw or a sheathe plays on the upper body over the locomotion
		# the action hands over to the locomotion before its end (the trunk, the head and the arms follow the gait that is running
		# underneath: a roll ends in a run, a flinch in the idle, with no stand-to-attention in between)
		var ho_t: float = act_def(_akey).get("ho", -1.0)
		if ho_t >= 0.0 and action_t > ho_t and not (sk or skl or skc):
			_handover(_src, loco, smooth(clampf((action_t - ho_t) / maxf(action_len - ho_t, 0.02), 0.0, 1.0)))
		_emit_events(act_def(_akey))
	else:
		_src = loco
	_io_rt = sk or skl or skc
	_pose = _blend_out(_src, delta)
	_stow_pose(delta) # STOW: the fists exactly on the grip and the rim they take
	_loco_prev = loco
	_solve_dt = delta
	_update_ground(delta)
	if action == "climb" and climb_lip > -50.0:
		_pin_climb_hands()
	if charge > 0.0:
		# a charged blow trembles: the chest and the sword hand shiver with the held strain
		var q := charge * 0.012
		_pose[C_CHS] += sin(t * 61.0) * q
		_pose[C_CHS + 2] += sin(t * 47.0 + 1.3) * q
		_pose[C_HR + 1] += sin(t * 53.0 + 0.4) * q * 0.8
	_solve(_pose)
	_stow_frame(delta) # STOW: who holds the sword and the shield, where they are
	_update_outfit_state()
	_secondary(delta)
	_apply_outfit()
	_apply_props()
	_apply_bones()


## World velocity / acceleration / yaw rate of the rig (drives leans and secondary motion).
## The reaction to a blow (hit, hit_heavy) turned to the direction it pushed him (see play()): the local velocity when it started,
## the angle once known (0: pushed straight back, + towards his right), whether it has been read.
var _hit_v0 := Vector2.ZERO
var _hit_set := true
var _hit_ang := 0.0
var _vel_inst := Vector3.ZERO


func _hit_dir_apply(c: PackedFloat32Array) -> void:
	if action != "hit" and action != "hit_heavy":
		return
	if not _hit_set:
		if action_t < 0.05:
			return
		_hit_set = true
		var lv := (global_transform.basis.inverse() if is_inside_tree() else Basis.IDENTITY) * _vel_inst
		var dv := Vector2(lv.x, lv.z) - _hit_v0
		_hit_ang = atan2(dv.x, dv.y) if dv.length() > 1.2 else 0.0
	if absf(_hit_ang) < 0.05:
		return
	var w := smoothstep(0.03, 0.12, action_t)
	var cs := cos(_hit_ang)
	var sn := sin(_hit_ang)
	# the lean of the torso (pitch back = +x, roll to his left = +z) and the pelvis' push turned by the angle
	for o in [C_PELR, C_SPN, C_CHS, C_NEK, C_HED]:
		var p := c[o]
		var r := c[o + 2]
		c[o] = lerpf(p, p * cs + r * sn, w)
		c[o + 2] = lerpf(r, r * cs - p * sn, w)
	var px := c[C_PEL]
	var pz := c[C_PEL + 2]
	c[C_PEL] = lerpf(px, px * cs + pz * sn, w)
	c[C_PEL + 2] = lerpf(pz, -px * sn + pz * cs, w)


func _track_motion(dt: float) -> void:
	if dt <= 0.0:
		return
	var p := global_position if is_inside_tree() else position
	var yaw := global_rotation.y if is_inside_tree() else rotation.y
	if not _have_prev or p.distance_to(_prev_pos) > 3.0:
		if _have_prev:
			reset_cloth() # a teleport (start, respawn, tests): the cloth must not stretch across the gap
		_prev_pos = p
		_prev_yaw = yaw
		_have_prev = true
	var v := (p - _prev_pos) / dt + velocity_hint
	_vel_inst = v
	var k := 1.0 - exp(-dt * 12.0)
	var nv := _vel.lerp(v, k)
	_acc = _acc.lerp((nv - _vel) / dt, 1.0 - exp(-dt * 8.0))
	_vel = nv
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _prev_yaw, -PI, PI) / dt, 1.0 - exp(-dt * 6.0))
	_yaw_inst = wrapf(yaw - _prev_yaw, -PI, PI) / dt
	_prev_pos = p
	_prev_yaw = yaw


# --- animation: inertialized transitions (docs/ANIMATION.md 6.8) ------------------------------------------------------
## A change of source (an action starts or ends, the motion state changes) used to mix a frozen snapshot of the old pose into the new
## one: every joint that was moving stopped dead on the first frame of the blend (a snap in all of them) and the new pose arrived
## with no memory of the old motion. Now the old motion goes on: on the first frame of the new source the difference between where
## the old pose was heading and the new source's pose, and the difference of their velocities, are kept as an offset per channel that
## dies away along a cubic Hermite curve (zero and zero slope at the end of the blend), "inertialization" (Bollinger, GDC 2018). The
## pose and its velocity are continuous through every transition, however fast the joints were moving.
var _io_x := PackedFloat32Array()
var _io_v := PackedFloat32Array()
var _io_on := false
var _io_pending := false
var _io_t := 0.0
var _io_len := 0.1
var _io_dlen := 0.1
var _io_dang := 0.0
## The blended output of the last two frames (the old motion's position and velocity) and the locomotion's last pose (the velocity
## of the source a transition lands on).
var _out_p1 := PackedFloat32Array()
var _out_p2 := PackedFloat32Array()
var _out_dt := 0.0166
var _loco_prev := PackedFloat32Array()
## The source just changed its generator (a new motion state): its previous frame says nothing about its velocity.
var _io_src_new := false
## The new source's legs and hips are driven at run time (a blow's footwork, the layers over the gait): the sampled action
## has no velocity for them.
var _io_rt := false
## INTEGRATE: the transition being started leaves a blow (its end or its cut) or the throw (its sword hand swings back to the
## carry the same way); the sword hand's carried speed limit then (m/s).
var _io_from_strike := false
const IO_STRIKE_V := 1.2
## Channels that are weights (kept in 0..1 when an offset is added).
const IO_FLAGS := [C_OHL, C_SPR, C_HOOD, C_HLX, C_HLS, C_HRS, C_HLR, C_HRR]
## Channels that are directions (the blade, the back of the hand, the elbow poles, the shield's facing, the left hand's blade and
## back): their offset is a rotation, taken the short way round. A vector difference between two nearly opposite directions
## (the blade up, the blade down) passes through nothing, and the hand turns over in one frame.
const IO_DIRS := [C_HRB, C_HRK, C_HRP, C_HLF, C_HLP, C_HLB, C_HLK]
const DIR_SLOW := 1.8
const DIR_RATE := 22.0
var _io_q: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY,
	Quaternion.IDENTITY, Quaternion.IDENTITY]


## The rotation that takes direction `a` to direction `b` the short way (any way across when they are opposite).
static func _dir_rot(a: Vector3, b: Vector3) -> Quaternion:
	if a.length_squared() < 1e-8 or b.length_squared() < 1e-8:
		return Quaternion.IDENTITY
	var an := a.normalized()
	var bn := b.normalized()
	var d := an.dot(bn)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var ax := an.cross(Vector3.UP)
		if ax.length_squared() < 1e-6:
			ax = an.cross(Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(an, bn)


## The source's pose a frame ago (for its velocity): the action sampled a step earlier, the locomotion's last frame.
func _src_before(src: PackedFloat32Array, delta: float) -> PackedFloat32Array:
	if _io_src_new and action == "":
		return src
	if action != "":
		var tb := action_t - delta * action_speed
		var d := act_def(_akey)
		if tb < 0.0:
			if bool(d["loop"]):
				tb += action_len
			else:
				tb = 0.0
		var sp := sample_action(_akey, tb)
		if _io_rt or ((_upper > 0.0 or _airl > 0.001) and _loco_prev.size() == C_N):
			# (what the layer takes from the locomotion has the locomotion's velocity; what a blow drives at run time none)
			for o in LOWER_CH:
				for j in 3:
					sp[o + j] = src[o + j] if _io_rt else _loco_prev[o + j]
			if _io_rt:
				for j in 3:
					sp[C_PELR + j] = src[C_PELR + j]
		return sp
	return _loco_prev if _loco_prev.size() == C_N else src


## The pose to solve this frame: the source plus what is left of the offset of the last transition. Also keeps the output of the
## last two frames (the velocity the next transition inherits).
func _blend_out(src: PackedFloat32Array, delta: float) -> PackedFloat32Array:
	var out := src.duplicate()
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / _blend_len)
	if delta > 1e-5 and _out_p1.size() == C_N:
		if _io_pending:
			_io_pending = false
			var sp := _src_before(src, delta)
			if _io_x.size() != C_N:
				_io_x.resize(C_N)
				_io_v.resize(C_N)
			var inv := 1.0 / maxf(_out_dt, 1e-4)
			for i in C_N:
				var ov := (_out_p1[i] - _out_p2[i]) * inv if _out_p2.size() == C_N else 0.0
				var sv := (src[i] - sp[i]) / delta
				_io_x[i] = _out_p1[i] + ov * delta - src[i]
				_io_v[i] = ov - sv
			if _io_from_strike:
				# INTEGRATE: out of a blow (its end, or its recovery cut short by the stick) the sword hand's speed is carried on no faster
				# than IO_STRIKE_V: a recovery sweeps back to the carry fast, and carried on at full speed the fist overshot into the hip
				for j in 3:
					_io_v[C_HR + j] = clampf(_io_v[C_HR + j], -IO_STRIKE_V, IO_STRIKE_V)
				_io_from_strike = false
			var dmax := 0.0
			for k in IO_DIRS.size():
				var o: int = IO_DIRS[k]
				_io_q[k] = _dir_rot(Vector3(src[o], src[o + 1], src[o + 2]), Vector3(_out_p1[o], _out_p1[o + 1], _out_p1[o + 2]))
				dmax = maxf(dmax, _io_q[k].get_angle())
			_io_t = 0.0
			_io_dang = dmax
			_io_on = true
			_io_src_new = false
			# (a blow's entry keeps the blend it was built and measured with)
			# (a turn comes round at about DIR_RATE rad/s at its fastest at most: half a turn takes 0.2 s)
			# (an action that must have its hand somewhere on time, the throw's grab of the spear on the back, keeps the quick lane)
			var fast := action != "" and bool(act_def(_akey).get("fast", false))
			_io_dlen = _io_len if (_io_rt or fast) else clampf(maxf(_io_len * DIR_SLOW, 0.09) * 0.0 + _io_dang * 1.5 / DIR_RATE, maxf(_io_len * DIR_SLOW, 0.09), 0.32)
			# (an action whose first moments turn the hand over, the roll's sword going behind him, says how long that is to take)
			if action != "" and not _io_rt and not fast:
				_io_dlen = maxf(_io_dlen, float(act_def(_akey).get("dlen", 0.0)))
		elif _io_on:
			_io_t += delta
		if _io_on:
			var u := _io_t / _io_len
			if u >= 1.0 and _io_t >= _io_dlen:
				_io_on = false
			else:
				u = minf(u, 1.0)
				var u2 := u * u
				var u3 := u2 * u
				var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
				var h10 := (u3 - 2.0 * u2 + u) * _io_len
				# the arms and hands come on the lane of their directions: a hand that arrives in 0.05 s while the blade it holds turns
				# for 0.2 s makes the wrist the sum of both, and the arm lagging a body that folds quickly is follow-through
				var ua := minf(_io_t / _io_dlen, 1.0)
				var ua2 := ua * ua
				var ua3 := ua2 * ua
				var a00 := 2.0 * ua3 - 3.0 * ua2 + 1.0
				var a10 := (ua3 - 2.0 * ua2 + ua) * _io_dlen
				for i in C_N:
					# (the sword hand and the shield's own hand: not the explicit hold of the spear or the chain, whose weights and
					# frames belong to the body's own blend)
					# (the weights that say which space a hand's numbers are in, hrs and hls, travel with the numbers: with the numbers still
					# the old ones and the weight already the new one, the hand is somewhere else altogether)
					if (i >= C_HR and i < C_HLW) or i == C_HLS or i == C_HRS:
						out[i] = src[i] + _io_x[i] * a00 + _io_v[i] * a10
					else:
						out[i] = src[i] + _io_x[i] * h00 + _io_v[i] * h10
				for o in IO_FLAGS:
					out[o] = clampf(out[o], minf(src[o], 0.0), maxf(src[o], 1.0))
				# (a direction can be half a turn off the new pose's: it takes longer to come round than a position to arrive)
				var ud := clampf(_io_t / _io_dlen, 0.0, 1.0)
				var wd := 2.0 * ud * ud * ud - 3.0 * ud * ud + 1.0
				var wq := 2.0 * u3 - 3.0 * u2 + 1.0
				for k in IO_DIRS.size():
					var o: int = IO_DIRS[k]
					var dv := Quaternion.IDENTITY.slerp(_io_q[k], wd if o < C_HLW else wq) * Vector3(src[o], src[o + 1], src[o + 2])
					out[o] = dv.x
					out[o + 1] = dv.y
					out[o + 2] = dv.z
	if _blend_t < 1.0 or _io_on:
		# (the whole-body rotation and its pivot keep the mixed blend: rotation vectors do not add up)
		var mixed := mix_pose(_from, src, smooth(_blend_t))
		for o in [C_ROT, C_PIV]:
			for j in 3:
				out[o + j] = mixed[o + j]
	_out_p2 = _out_p1
	_out_p1 = out
	_out_dt = maxf(delta, 1e-5)
	return out


static func mix_pose(a: PackedFloat32Array, b: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(C_N)
	for i in C_N:
		out[i] = lerpf(a[i], b[i], k)
	# whole-body rotation: rotation vectors, reduced to the shortest equivalent turn, then slerped
	var ra := _reduce_rot(v3(a, C_ROT))
	var rb := _reduce_rot(v3(b, C_ROT))
	var qa := Quaternion(ra.normalized(), ra.length()) if ra.length_squared() > 1e-10 else Quaternion.IDENTITY
	var qb := Quaternion(rb.normalized(), rb.length()) if rb.length_squared() > 1e-10 else Quaternion.IDENTITY
	var q := qa.slerp(qb, k)
	var ang := q.get_angle()
	var rv := q.get_axis() * ang if ang > 1e-5 else Vector3.ZERO
	_setv(out, C_ROT, rv)
	return out


## The same rotation as the rotation vector v, with an angle in [-PI, PI].
static func _reduce_rot(v: Vector3) -> Vector3:
	var l := v.length()
	if l <= PI:
		return v
	var a := fposmod(l + PI, TAU) - PI
	return v / l * a


# --- animation: keyframed actions ----------------------------------------------------------------------------

## Swing key values: the grip turns about `n` (through the right shoulder, chest space) from the radial direction
## `u` by `phi` at distance `rad`; the blade points along `u` turned by `beta`; the back of the hand faces `n * k`.
static func swing(n: Vector3, u: Vector3, phi: float, beta: float, rad: float, k: float = -1.0) -> Dictionary:
	n = n.normalized()
	u = perp(u, n).normalized()
	return {"hr": SHOULDER_CS + Basis(n, phi) * u * rad, "hrb": Basis(n, beta) * u, "hrk": n * k}


## A grip position between a and b along the arc around the right shoulder (chest space).
static func arcp(a: Vector3, b: Vector3, k: float) -> Vector3:
	var da := a - SHOULDER_CS
	var db := b - SHOULDER_CS
	return SHOULDER_CS + da.normalized().slerp(db.normalized(), k) * lerpf(da.length(), db.length(), k)


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	return a.merged(b, true)


static func act_def(a: String) -> Dictionary:
	if _acts.is_empty():
		_compile_actions()
	return _acts.get(a, {})


static func _compile_actions() -> void:
	var defs := _action_defs()
	for nm in defs:
		_acts[nm] = compile_action(defs[nm])
	# the blows built from joint angles replace the keyed ones (_strike_raw); the old names play the new blows (STRIKE_ALIAS)
	for nm in STRIKE_NAMES:
		_acts[nm] = _bake_strike(_strike_raw(nm))
	for al in STRIKE_ALIAS:
		_acts[al] = _acts[STRIKE_ALIAS[al]]


## Compiles one raw action definition (see _action_defs) into sampled poses and Hermite tangents.
static func compile_action(d: Dictionary) -> Dictionary:
	var keys: Array = d["keys"]
	var times := PackedFloat32Array()
	var poses: Array[PackedFloat32Array] = []
	var ease := PackedByteArray()
	var prev := default_pose()
	# the keys that set a whole pose (every channel not listed keeps what the key before it had)
	for k in keys:
		var ch: Dictionary = k[1]
		if ch.get("partial", false):
			continue
		var pose := prev.duplicate()
		for key in ch:
			if key == "ease":
				continue
			set_ch(pose, key, ch[key])
		times.append(float(k[0]))
		poses.append(pose)
		ease.append(1 if ch.get("ease", false) else 0)
		prev = pose
	var tans := _key_tangents(times, poses, ease)
	# a partial key (`"partial": true`) only sets the channels it lists, at its time: the others stay on the curve the whole keys
	# make through that time (one limb can lead or lag the rest without giving every channel a key); the tangents are then those of
	# all the keys together
	var has_partial := false
	for k in keys:
		if (k[1] as Dictionary).get("partial", false):
			has_partial = true
	if has_partial:
		var t2 := times.duplicate()
		var p2: Array[PackedFloat32Array] = poses.duplicate()
		var e2 := ease.duplicate()
		for k in keys:
			var ch: Dictionary = k[1]
			if not ch.get("partial", false):
				continue
			var tk: float = k[0]
			var pose := _hermite_sample(times, poses, tans, tk)
			for key in ch:
				if key == "ease" or key == "partial":
					continue
				set_ch(pose, key, ch[key])
			var at := 0
			while at < t2.size() and t2[at] <= tk:
				at += 1
			t2.insert(at, tk)
			p2.insert(at, pose)
			e2.insert(at, 1 if ch.get("ease", false) else 0)
		times = t2
		poses = p2
		ease = e2
		tans = _key_tangents(times, poses, ease)
	return {"len": float(d["len"]), "loop": bool(d.get("loop", false)), "hold": bool(d.get("hold", false)),
		"in": float(d.get("in", 0.08)), "out": float(d.get("out", 0.2)), "ev": d.get("ev", {}),
		"ho": float(d.get("ho", -1.0)), "fast": bool(d.get("fast", false)), "dlen": float(d.get("dlen", 0.0)), "times": times, "poses": poses, "tans": tans}


## Hermite tangents (non-uniform Catmull-Rom; zero at the ends and at eased keys).
static func _key_tangents(times: PackedFloat32Array, poses: Array[PackedFloat32Array], ease: PackedByteArray) -> Array[PackedFloat32Array]:
	var tans: Array[PackedFloat32Array] = []
	var n := poses.size()
	for i in n:
		var m := PackedFloat32Array()
		m.resize(C_N)
		if i > 0 and i < n - 1 and ease[i] == 0:
			var dt := times[i + 1] - times[i - 1]
			for j in C_N:
				m[j] = (poses[i + 1][j] - poses[i - 1][j]) / maxf(dt, 1e-4)
		tans.append(m)
	return tans


static func sample_action(a: String, at: float) -> PackedFloat32Array:
	var d := act_def(a)
	return _hermite_sample(d["times"], d["poses"], d["tans"], at)


static func _hermite_sample(times: PackedFloat32Array, poses: Array[PackedFloat32Array], tans: Array[PackedFloat32Array], at: float) -> PackedFloat32Array:
	var n := times.size()
	if at <= times[0] or n == 1:
		return poses[0].duplicate()
	if at >= times[n - 1]:
		return poses[n - 1].duplicate()
	var i := 0
	while i < n - 2 and at >= times[i + 1]:
		i += 1
	var h := times[i + 1] - times[i]
	var u := (at - times[i]) / h
	var u2 := u * u
	var u3 := u2 * u
	var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
	var h10 := (u3 - 2.0 * u2 + u) * h
	var h01 := -2.0 * u3 + 3.0 * u2
	var h11 := (u3 - u2) * h
	var p0 := poses[i]
	var p1 := poses[i + 1]
	var m0 := tans[i]
	var m1 := tans[i + 1]
	var out := PackedFloat32Array()
	out.resize(C_N)
	for j in C_N:
		out[j] = h00 * p0[j] + h10 * m0[j] + h01 * p1[j] + h11 * m1[j]
	# a direction (the blade, the back of the hand, a pole, the shield's facing) between two keys that are far apart turns the short
	# way round on its great circle: the components of such a vector, interpolated one by one, pass through nothing and the
	# direction flips in a frame (the blade from forward to back, a roll's first step)
	for o in IO_DIRS:
		var da := Vector3(p0[o], p0[o + 1], p0[o + 2])
		var db := Vector3(p1[o], p1[o + 1], p1[o + 2])
		if da.length_squared() > 1e-6 and db.length_squared() > 1e-6 and da.angle_to(db) > 1.2:
			var sl := u2 * (3.0 - 2.0 * u)
			var v := Quaternion.IDENTITY.slerp(_dir_rot(da, db), sl) * da.normalized() * lerpf(da.length(), db.length(), sl)
			out[o] = v.x
			out[o + 1] = v.y
			out[o + 2] = v.z
	return out


# --- animation: locomotion -----------------------------------------------------------------------------------

static func _addv(c: PackedFloat32Array, o: int, v: Vector3) -> void:
	c[o] += v.x
	c[o + 1] += v.y
	c[o + 2] += v.z


static func _setv(c: PackedFloat32Array, o: int, v: Vector3) -> void:
	c[o] = v.x
	c[o + 1] = v.y
	c[o + 2] = v.z


static func _lerpv(c: PackedFloat32Array, o: int, v: Vector3, k: float) -> void:
	c[o] = lerpf(c[o], v.x, k)
	c[o + 1] = lerpf(c[o + 1], v.y, k)
	c[o + 2] = lerpf(c[o + 2], v.z, k)


func _loco_pose(dt: float) -> PackedFloat32Array:
	var c := default_pose()
	_spd = lerpf(_spd, speed, 1.0 - exp(-dt * 10.0))
	# the shield comes up (and goes down) on a spring: it arrives a little past the guard pose and settles, the way a heavy thing
	# carried on an arm does (the old ramp stopped dead at the pose)
	var gn := maxi(ceili(dt / (1.0 / 90.0)), 1)
	var gh := dt / float(gn)
	for _i in gn:
		_guard_v += (GUARD_W * GUARD_W * ((1.0 if guard else 0.0) - _guard_k) - 2.0 * GUARD_Z * GUARD_W * _guard_v) * gh
		_guard_k += _guard_v * gh
	_vy = lerpf(_vy, vspeed, 1.0 - exp(-dt * 10.0))
	# the landing's give: a damped spring on the pelvis' height, kicked by the speed the ground was met at (_land_impact)
	var ln := maxi(ceili(dt / (1.0 / 90.0)), 1)
	var lh := dt / float(ln)
	for _i in ln:
		_land_v += (-LAND_W * LAND_W * _land_x - 2.0 * LAND_Z * LAND_W * _land_v) * lh
		_land_x += _land_v * lh
	# shield jolt: a stiff damped spring
	_jolt_v += (-_jolt * 160.0 - _jolt_v * 16.0) * dt
	_jolt += _jolt_v * dt
	match motion_state:
		&"air":
			_air_pose(c)
		&"swim":
			_swim_pose(c, dt)
		&"zip":
			_zip_pose(c, dt)
		&"hang":
			_hang_pose(c, dt)
		_:
			_ground_pose(c, dt)
	return c


# --- animation: the ground gait (docs/ANIMATION.md) -------------------------------------------------------------------
## The ground locomotion: idle, walk, jog, sprint, strafe, back-pedal. A phase-driven cycle (cadence and stance share
## from the speed tables below), feet PLANTED in the world (the heel, then the toe, stay pinned where they touch down:
## nothing slides), a swing that is an arc in world space to where the next step will land, a pelvis lowered where the
## leg would over-reach, a trunk lean that grows with speed (a spring adds the push of an acceleration and the roll of
## a turn), pelvis and chest counter-rotating, the head held level and forward, and arms swung from forward kinematics
## (shoulder swing + elbow flexion) in opposition to the legs. Standing, the feet stay put and step home when the body
## has turned or been shifted too far.

const FOOT_HEEL := Vector3(0.0, -0.093, 0.075)
const FOOT_TOE := Vector3(0.0, -0.093, -0.22)
const SOLE_LEN := 0.295
const ST_STAND := 0
const ST_SWING := 1
const ST_HOME := 2
## The share of the leg's length a foot may ask of the pelvis (the knee keeps about 16 degrees of bend).
const LEG_REACH := 0.99
const GAIT_ON_V := 0.62
## A planted foot that the body has left this far behind lifts at once.
const LIFT_REACH := 0.56
## A swing's last share: the foot is already over the spot where it will land and only comes down.
const SET_DOWN := 1.0
const GAIT_OFF_V := 0.38
## Hip -> neck line lean is this much of the chest bone's lean (the pelvis and spine lean less than the chest).
const LEAN_LINE := 1.29
const LEAN_SHARE_PELVIS := 0.38
const LEAN_SHARE_SPINE := 0.34

# Tables of [speed m/s, value, speed, value, ...] (smoothstepped between the anchors, flat beyond the ends).
const T_F := [0.55, 0.62, 1.4, 1.0, 2.2, 1.28, 3.2, 1.55, 4.5, 1.9, 6.2, 2.1, 9.0, 2.45] # cycles per second
const T_D := [0.55, 0.78, 1.4, 0.6, 2.2, 0.52, 3.2, 0.42, 4.5, 0.32, 6.2, 0.26, 9.0, 0.2] # stance share of the cycle
const T_TH0 := [2.2, 0.26, 3.2, 0.18, 4.5, 0.1, 6.2, 0.05, 9.0, -0.2] # foot pitch at touchdown (+ toe up)
const T_THTO := [2.2, 0.75, 6.2, 0.82, 9.0, 0.9] # foot pitch at toe-off (the heel up)
const T_UH := [2.2, 0.55, 4.5, 0.48, 6.2, 0.42, 9.0, 0.36] # where in the stance the heel starts to rise
const T_APEX := [0.55, 0.02, 2.2, 0.035, 4.5, 0.11, 6.2, 0.16, 9.0, 0.24] # swing foot height over the straight line
const T_LEAN := [0.0, 0.0, 2.2, 4.0, 4.5, 8.5, 6.2, 13.5, 9.0, 27.0] # hip -> neck lean, degrees (STOW: P2, the run leans in hard)
## STOW: the relaxed arms (empty fists): swing centre (deg, + forward: the swing pumps forward more than back), amplitude, elbow
## flexion and its swing (more bent in front), abduction.
const T_RX_C := [0.3, 0.0, 2.2, 3.0, 4.5, 6.0, 6.2, 9.0, 9.0, 12.0]
const T_RX_A := [0.3, 0.0, 2.2, 24.0, 4.5, 42.0, 6.2, 50.0, 9.0, 58.0]
const T_RX_EL := [0.0, 16.0, 2.2, 24.0, 4.5, 74.0, 6.2, 88.0, 9.0, 98.0]
const T_RX_ELV := [0.0, 0.0, 2.2, 10.0, 4.5, 14.0, 6.2, 16.0, 9.0, 16.0]
const T_RX_AB := [0.0, 9.0, 2.2, 10.0, 4.5, 12.0, 6.2, 13.0, 9.0, 14.0]
## STOW: the armed carry (ref_sword_pose): the sword arm's swing centre and amplitude (less: it carries the sword), elbow, abduction
## (the blade clear of the leg) and the blade's elevation (deg, trailing back and down; it rises a little with speed).
const T_AC_C := [0.3, 4.0, 2.2, 4.0, 4.5, 8.0, 6.2, 10.0, 9.0, 12.0]
const T_AC_A := [0.3, 0.0, 2.2, 12.0, 4.5, 18.0, 6.2, 22.0, 9.0, 26.0]
const T_AC_EL := [0.0, 14.0, 2.2, 20.0, 4.5, 32.0, 6.2, 40.0, 9.0, 52.0]
const T_AC_AB := [0.0, 12.0, 2.2, 13.0, 6.2, 16.0, 9.0, 18.0]
const T_AC_EV := [0.0, -36.0, 2.2, -34.0, 6.2, -28.0, 9.0, -24.0]
const T_PYAW := [0.0, 0.0, 2.2, 4.0, 4.5, 5.5, 6.2, 6.5, 9.0, 8.5] # pelvis yaw amplitude, degrees
const T_CRATIO := [0.0, 1.2, 2.2, 1.2, 4.5, 1.4, 6.2, 1.5, 9.0, 1.6] # chest counter-rotation / pelvis yaw
const T_PROLL := [0.0, 0.0, 2.2, 3.0, 4.5, 3.5, 6.2, 3.5, 9.0, 4.0] # pelvis list amplitude, degrees
const T_SWAY := [0.0, 0.0, 2.2, 0.022, 4.5, 0.015, 6.2, 0.012, 9.0, 0.01] # pelvis side shift over the stance foot, m
const T_BOB := [0.0, 0.0, 2.2, 0.016, 3.2, 0.0, 4.5, -0.02, 6.2, -0.03, 9.0, -0.032] # + high at mid-stance (walk), - low (run)
const T_PELH := [0.0, -0.035, 2.2, -0.06, 4.5, -0.08, 6.2, -0.09, 9.0, -0.11] # pelvis height offset
const T_PELZ := [0.0, 0.0, 2.2, -0.01, 4.5, -0.03, 6.2, -0.05, 9.0, -0.09] # pelvis shifted forward with the lean, m
const T_ARM_C := [0.3, 0.0, 2.2, 0.0, 4.5, 0.0, 6.2, -2.0, 9.0, -4.0] # sword arm: swing centre (shoulder flexion, deg)
const T_ARM_A := [0.3, 0.0, 2.2, 20.0, 4.5, 29.0, 6.2, 33.0, 9.0, 39.0] # and amplitude
const T_EL_R := [0.3, 25.0, 2.2, 38.0, 4.5, 86.0, 6.2, 92.0, 9.0, 90.0] # elbow flexion, mean
const T_EL_RV := [0.3, 0.0, 2.2, 12.0, 4.5, 10.0, 6.2, 10.0, 9.0, 8.0] # and swing
const T_AB_R := [0.3, 10.0, 2.2, 18.0, 4.5, 16.0, 6.2, 15.0, 9.0, 15.0] # abduction (elbow out)
const T_ARM_LC := [0.3, 8.0, 2.2, 9.0, 4.5, 20.0, 6.2, 27.0, 9.0, 26.0] # shield arm: centre
const T_ARM_LA := [0.3, 0.0, 2.2, 7.0, 4.5, 9.0, 6.2, 10.0, 9.0, 13.0] # amplitude
const T_EL_L := [0.3, 56.0, 2.2, 68.0, 4.5, 96.0, 6.2, 102.0, 9.0, 100.0] # elbow flexion
const T_AB_L := [0.3, 16.0, 2.2, 20.0, 4.5, 21.0, 6.2, 24.0, 9.0, 28.0] # abduction (INTEGRATE: wider at speed: the shield met the left thigh)
const T_ARM_PH := [2.2, 0.41, 4.5, 0.3, 6.2, 0.23, 9.0, 0.2] # phase at which the sword arm is furthest forward (the opposite thigh peaks)
const T_ULN := [0.3, 40.0, 2.2, 48.0, 4.5, 54.0, 6.2, 58.0, 9.0, 58.0] # sword hand: the blade turned towards the forearm's line (ulnar deviation), deg
const T_TW := [0.3, 0.0, 2.2, 8.0, 6.2, 26.0, 9.0, 30.0] # sword hand: forearm twist (deg, + turns the blade tip out)
const T_ULN_K := [2.2, 0.0, 4.5, 0.4, 9.0, 0.5] # the wrist keeps the blade up: ulnar deviation follows the arm's swing by this much
const T_KNEE := [2.2, 0.25, 4.5, 0.14, 6.2, 0.08, 9.0, 0.03] # knee pole: how far out the knee points (x per unit forward)
const T_HEADP := [0.0, 0.0, 2.2, 1.5, 6.2, 0.5, 9.0, -1.0] # where the helmet looks: pitch (deg, + down)


## Value of a table at speed v.
static func _pl(v: float, k: Array) -> float:
	var n := k.size()
	if v <= float(k[0]):
		return float(k[1])
	var i := 2
	while i < n:
		if v <= float(k[i]):
			var a: float = k[i - 2]
			var b: float = k[i]
			var tt := (v - a) / (b - a)
			tt = tt * tt * (3.0 - 2.0 * tt)
			return lerpf(float(k[i - 1]), float(k[i + 1]), tt)
		i += 2
	return float(k[n - 1])


## Ankle height (m) of a foot that stands on its heel (pitch >= 0) or on its toe (pitch < 0) at pitch th.
static func _ankle_y(th: float) -> float:
	return 0.093 * cos(th) + (0.075 * sin(th) if th >= 0.0 else -0.22 * sin(th))


## Rig-space ankle of a foot with its heel (kind 0) or toe (kind 1) pinned at `pin` (rig-space XZ) on the ground.
static func _ankle_of(pin: Vector2, kind: int, psi: float, th: float) -> Vector3:
	var off := (Basis(Vector3.UP, psi) * Basis(Vector3.RIGHT, th)) * (FOOT_HEEL if kind == 0 else FOOT_TOE)
	return Vector3(pin.x - off.x, -off.y, pin.y - off.z)


## The contact point (rig-space XZ) of a foot whose ankle is at `ank`.
static func _pin_of(ank: Vector2, kind: int, psi: float, th: float) -> Vector2:
	var off := (Basis(Vector3.UP, psi) * Basis(Vector3.RIGHT, th)) * (FOOT_HEEL if kind == 0 else FOOT_TOE)
	return Vector2(ank.x + off.x, ank.y + off.z)


## Foot pitch through a stance (u 0..1): heel strike (or toe strike) settling flat, flat, then the heel rising.
static func _stance_pitch(u: float, th0: float, th_to: float, uh: float) -> float:
	var uf := 0.2
	if u < uf:
		var k := u / uf
		return th0 * (1.0 - k * k * (3.0 - 2.0 * k))
	if u < uh:
		return 0.0
	var w := clampf((u - uh) / maxf(1.0 - uh, 0.05), 0.0, 1.0)
	return -th_to * pow(w, 1.7)


## World XZ <-> rig-local XZ (x right, y = z backwards) for the rig as it stands this frame.
func _rig_frame() -> void:
	var gt := global_transform if is_inside_tree() else transform
	_rp = Vector2(gt.origin.x, gt.origin.z)
	_ry = atan2(gt.basis.z.x, gt.basis.z.z)


func _w2l(p: Vector2) -> Vector2:
	var d := p - _rp
	var s := sin(_ry)
	var co := cos(_ry)
	return Vector2(d.x * co - d.y * s, d.x * s + d.y * co)


func _l2w(p: Vector2) -> Vector2:
	var s := sin(_ry)
	var co := cos(_ry)
	return _rp + Vector2(p.x * co + p.y * s, -p.x * s + p.y * co)


## An arm from its joint angles, in chest space: shoulder flexion `psi` (+ forward), abduction `ab` (+ out), elbow
## flexion `el`, and `rho`, how far the forearm is turned in towards the midline. Returns [wrist, elbow pole].
static func _arm_fk(side: float, psi: float, ab: float, el: float, rho: float) -> Array:
	var u := Vector3(side * sin(ab), -cos(ab) * cos(psi), -cos(ab) * sin(psi))
	var fw := perp(Vector3(0.0, 0.0, -1.0), u).normalized().rotated(u, -side * rho)
	var f := u * cos(el) + fw * sin(el)
	var s0 := Vector3(side * SHOULDER_CS.x, SHOULDER_CS.y, SHOULDER_CS.z)
	var e := s0 + u * LEN_UA
	var w := e + f * LEN_FA
	var pole := perp(e - s0, (w - s0).normalized())
	if pole.length_squared() < 1e-6:
		pole = Vector3(side * 0.5, -0.2, 1.0)
	return [w, pole.normalized(), f]


## The sword hand from the forearm (all in chest space). Zero is a hammer grip: the blade across the forearm, out of the
## thumb side, the back of the hand facing out. `uln` turns the blade towards the forearm's own line (ulnar deviation),
## `ext` extends the wrist, `tw` twists the forearm. Returns [blade direction, back of the hand].
static func _sword_hand(f: Vector3, uln: float, ext: float, tw: float) -> Array:
	var fn := f.normalized()
	var y_n := -fn
	var x_n := perp(Vector3(1.0, 0.0, 0.0), fn).normalized()
	var z_n := x_n.cross(y_n)
	var rot := Basis(fn, tw) * Basis(x_n, -uln) * Basis(z_n, ext)
	var h := rot * Basis(x_n, y_n, z_n)
	return [-h.z, h.x]


## Rest position of a foot in rig space (from the idle pose being built, the guard's stance included).
func _home(c: PackedFloat32Array, i: int, guard_g: float) -> Vector2:
	var o := C_FR if i == 0 else C_FL
	var h := Vector2(c[o], c[o + 2])
	if i == 1:
		h += Vector2(-0.02, -0.06) * guard_g
	return h


func _plant_home(c: PackedFloat32Array, guard_g: float) -> void:
	for i in 2:
		var ro := (C_FRR if i == 0 else C_FLR) + 1
		var h := _home(c, i, guard_g)
		var yaw_rel := c[ro]
		_ft_st[i] = ST_STAND
		_ft_kind[i] = 0
		_ft_pin[i] = _l2w(_pin_of(h, 0, yaw_rel, 0.0))
		_ft_yaw[i] = _ry + yaw_rel
		_ft_th0[i] = 0.0
		_ft_s[i] = 0.0
		_ft_aw[i] = _l2w(h)
		_ft_ay[i] = 0.093
		_ft_pit[i] = 0.0
		_ft_ank[i] = Vector3(h.x, 0.093, h.y)
		_ft_ry[i] = yaw_rel
		_ft_w[i] = 1.0
		_ft_phi[i] = fposmod(_gph + _ft_off[i], 1.0)
	_fp_ok = true


## The gait starts (from standing, or from a given phase in tools): who lifts first, where the phases are. Returns the
## foot that has just landed (the other lifts at once), -1 in tools.
func _gait_start(duty: float, tn: Vector2, landing: bool = false) -> int:
	_gait_on = true
	var stance := -1
	# a foot still coming down at home (a stop a moment ago) is the one that lifts: it carries on as the first swing
	var airborne := -1
	for i in 2:
		if _ft_st[i] == ST_HOME:
			airborne = i
	if _pv_phase >= 0.0:
		_gph = _pv_phase
		_pv_phase = -1.0
		_ft_off[0] = 0.0
		_ft_off[1] = 0.5
	else:
		# the foot furthest back (along the travel) lifts first; the other has just landed
		var a := 1
		var p0 := _w2l(_ft_aw[0])
		var p1 := _w2l(_ft_aw[1])
		if p0.x * tn.x + p0.y * tn.y < p1.x * tn.x + p1.y * tn.y - 0.001:
			a = 0
		if airborne >= 0:
			a = airborne
		stance = 1 - a
		if landing:
			# touching down at speed: the feet are half a cycle apart already (one just landed, the other passing under)
			_ft_off[0] = 0.0
			_ft_off[1] = 0.5
			_gph = 0.0 if stance == 0 else 0.5
		elif a == 0:
			_gph = duty
			_ft_off[0] = 0.0
			_ft_off[1] = 1.0 - duty
		else:
			_gph = 0.0
			_ft_off[0] = 0.0
			_ft_off[1] = duty
	for i in 2:
		_ft_phi[i] = fposmod(_gph + _ft_off[i], 1.0)
		if _ft_st[i] == ST_SWING:
			_ft_st[i] = ST_STAND
	if airborne >= 0 and not landing:
		_liftoff(airborne, _ft_phi[airborne])
	return stance


## The gait ends: a foot in the air comes down at home (a short step); the planted one stays.
func _gait_stop() -> void:
	_gait_on = false
	for i in 2:
		if _ft_st[i] == ST_SWING:
			_ft_st[i] = ST_HOME
			_ft_from[i] = _ft_aw[i]
			_ft_from_y[i] = _ft_ay[i]
			_ft_from_th[i] = _ft_pit[i]
			_ft_from_yaw[i] = _ft_wy[i]
			_ft_from_pv[i] = _ft_pv[i]
			_ft_s[i] = 0.0
			_ft_dur[i] = 0.16


## Landing (or starting) at speed: the foot that has just touched down is already where the stride puts it, ahead of the
## pelvis, instead of at the idle stance with the body racing off ahead of it.
func _plant_landing(c: PackedFloat32Array, stance: int, v: float, reach_f: float, side_k: float, tn: Vector2) -> void:
	var run := smoothstep(2.3, 4.6, v)
	var lat := lerpf(lerpf(0.125, 0.09, run), 0.22, side_k)
	var fwd_k := clampf(-tn.y, 0.0, 1.0)
	var th0 := _pl(v, T_TH0) * fwd_k
	var pel_z := c[C_PEL + 2] + _pl(v, T_PELZ)
	for i in 2:
		if i != stance:
			continue
		var sx := 1.0 if i == 0 else -1.0
		var tgt := Vector2(sx * lat + tn.x * reach_f, pel_z + tn.y * reach_f)
		tgt.x = maxf(tgt.x, 0.07) if i == 0 else minf(tgt.x, -0.07)
		_land(i, tgt, th0, _ry - sx * 0.07, false)
		_ft_aw[i] = _l2w(tgt)
		_ft_ank[i] = Vector3(tgt.x, _ankle_y(th0), tgt.y)
		_ft_pit[i] = th0
		_ft_wy[i] = _ry - sx * 0.07


func _liftoff(i: int, phi: float) -> void:
	_ft_st[i] = ST_SWING
	_ft_from[i] = _ft_aw[i]
	_ft_from_y[i] = _ft_ay[i]
	_ft_from_th[i] = _ft_pit[i]
	_ft_from_yaw[i] = _ft_wy[i]
	_ft_from_pv[i] = _ft_pv[i]
	_ft_philo[i] = phi
	_ft_s[i] = 0.0


func _land(i: int, tgt: Vector2, th0: float, yaw_w: float, step: bool) -> void:
	var psi := wrapf(yaw_w - _ry, -PI, PI)
	var kind := 0 if th0 > 0.001 else 1
	_ft_st[i] = ST_STAND
	_ft_kind[i] = kind
	_ft_pin[i] = _l2w(_pin_of(tgt, kind, psi, th0))
	_ft_yaw[i] = yaw_w
	_ft_th0[i] = th0
	_ft_s[i] = 0.0
	if step and (action == "" or _upper > 0.0) and _spd > 0.2:
		event.emit("step")


## One frame of both feet: the state machine (stance, swing, home step) and the ankles it gives. Writes _ft_ank,
## _ft_pit, _ft_ry (relative to the rig) and the weights the pelvis uses to respect them (_ft_w).
func _feet_update(c: PackedFloat32Array, dt: float, v: float, run: float, f_cyc: float, duty: float, reach_f: float,
		pel_x: float, pel_z: float, side_k: float, guard_g: float, tn: Vector2) -> void:
	if velocity_hint != Vector3.ZERO:
		# tools pretending the rig moves: the ground slides back under it
		var sh := Vector2(velocity_hint.x, velocity_hint.z) * dt
		for i in 2:
			_ft_pin[i] -= sh
			_ft_from[i] -= sh
			_ft_aw[i] -= sh
	var vw := Vector2(_vel.x, _vel.z)
	var lat := lerpf(lerpf(0.125, 0.09, run), 0.22, side_k)
	# the foot rolls heel to toe going forward; going back or sideways it is put down flat
	var fwd_k := clampf(-tn.y, 0.0, 1.0)
	var th0 := _pl(v, T_TH0) * fwd_k
	var th_to := lerpf(0.25, _pl(v, T_THTO), fwd_k)
	var uh := _pl(v, T_UH)
	var back_k := clampf(tn.y, 0.0, 1.0)
	var apex := maxf(_pl(v, T_APEX), 0.08 * maxf(side_k, back_k))
	var f_inv := 1.0 / maxf(f_cyc, 0.1)
	# the phases of the two feet relax to half a cycle apart
	if _gait_on:
		var relax := minf(1.0, 0.6 * f_cyc) * dt
		for i in 2:
			var nominal := 0.0 if i == 0 else 0.5
			var d := wrapf(nominal - _ft_off[i], -0.5, 0.5)
			_ft_off[i] += clampf(d, -relax, relax)
	var stepped := false
	for i in 2:
		var sx := 1.0 if i == 0 else -1.0
		var ro := (C_FRR if i == 0 else C_FLR) + 1
		var home := _home(c, i, guard_g)
		var home_yaw_w := _ry + c[ro]
		var phi := fposmod(_gph + _ft_off[i], 1.0)
		var wrapped := _gait_on and phi < _ft_phi[i] - 0.5
		_ft_phi[i] = phi
		var tgt := Vector2(sx * lat + tn.x * reach_f, pel_z + tn.y * reach_f)
		# going sideways the legs cross: the right foot lands behind the left, the left in front of the right
		tgt.y += sx * -0.14 * side_k
		var xmin := lerpf(0.07, -0.4, side_k)
		if i == 0:
			tgt.x = maxf(tgt.x, xmin)
		else:
			tgt.x = minf(tgt.x, -xmin)
		var yaw_td := _ry - sx * 0.07
		var st := _ft_st[i]
		# --- transitions
		if st == ST_SWING:
			var s := (phi - _ft_philo[i]) / maxf(1.0 - _ft_philo[i], 0.02)
			if _gait_on and (wrapped or s >= 1.0):
				_land(i, _w2l(_ft_goal[i]), _ft_goal_th[i], _ft_goal_yaw[i], true)
				st = ST_STAND
			else:
				_ft_s[i] = clampf(s, 0.0, 1.0)
		elif st == ST_HOME:
			_ft_s[i] += dt / maxf(_ft_dur[i], 0.05)
			if _ft_s[i] >= 1.0:
				var gl := _w2l(_ft_goal[i])
				_land(i, gl, _ft_goal_th[i], _ft_goal_yaw[i], _w2l(_ft_from[i]).distance_to(gl) > 0.25)
				st = ST_STAND
		if st == ST_STAND:
			if _gait_on:
				var behind := Vector2(_ft_ank[i].x - (sx * 0.112 + pel_x), _ft_ank[i].z - pel_z).length()
				# (a start: the body runs away from a planted foot, which has to leave the ground sooner)
				var lift_reach := lerpf(LIFT_REACH, 0.36, clampf(_a_fwd / 25.0, 0.0, 1.0))
				if behind > lift_reach and phi < duty and not wrapped:
					# the body has run ahead of this foot (a start, a turn): it lifts now, and its phase follows
					_ft_off[i] = fposmod(duty - _gph, 1.0)
					phi = duty
					_ft_phi[i] = phi
				if phi >= duty and not wrapped:
					_liftoff(i, phi)
					st = ST_SWING
					_ft_s[i] = 0.0
			elif not stepped:
				# standing: step home when the body has turned or shifted too far from this foot
				var err := (_l2w(home) - _ft_aw[i]).length()
				var yerr := absf(wrapf(home_yaw_w - _ft_yaw[i], -PI, PI))
				var other := _ft_st[1 - i]
				if other == ST_STAND and (err > 0.14 or yerr > 0.62):
					_ft_st[i] = ST_HOME
					_ft_from[i] = _ft_aw[i]
					_ft_from_y[i] = _ft_ay[i]
					_ft_from_th[i] = _ft_pit[i]
					_ft_from_yaw[i] = _ft_wy[i]
					_ft_from_pv[i] = _ft_pv[i]
					_ft_s[i] = 0.0
					_ft_dur[i] = clampf(0.16 + 0.3 * err, 0.18, 0.3)
					st = ST_HOME
					stepped = true
				elif err > 1.2:
					_ft_pin[i] = _l2w(_pin_of(home, 0, c[ro], 0.0))
					_ft_yaw[i] = home_yaw_w
					_ft_kind[i] = 0
				elif err < 0.1:
					# small differences (the guard's stance): the foot shuffles over, slowly
					var dv := (_l2w(home) - _ft_aw[i]).limit_length(0.35 * dt)
					_ft_pin[i] += dv
					var dy := clampf(wrapf(home_yaw_w - _ft_yaw[i], -PI, PI), -1.5 * dt, 1.5 * dt)
					_ft_yaw[i] += dy
		_ft_st[i] = st
		# --- the ankle
		var ank := Vector3.ZERO
		var pit := 0.0
		var yaw_w := _ft_yaw[i]
		var w := 1.0
		if st == ST_STAND:
			var th := 0.0
			if _gait_on:
				var u := clampf(phi / maxf(duty, 0.05), 0.0, 1.0)
				th = _stance_pitch(u, _ft_th0[i], th_to, uh)
			else:
				th = move_toward(_ft_pit[i], 0.0, 3.0 * dt)
			var psi := wrapf(_ft_yaw[i] - _ry, -PI, PI)
			if absf(psi) > 0.8:
				psi = clampf(psi, -0.8, 0.8)
				_ft_yaw[i] = _ry + psi
			var pl := _w2l(_ft_pin[i])
			if _ft_kind[i] == 0 and th <= 0.0:
				# the sole has come flat: the toe takes the weight, pinned where it lies
				_ft_kind[i] = 1
				pl += Vector2(-sin(psi), -cos(psi)) * SOLE_LEN
				_ft_pin[i] = _l2w(pl)
			ank = _ankle_of(pl, _ft_kind[i], psi, th)
			# a foot dragged beyond what the leg can reach (a shove, a skid): the contact slides in
			var hxz := Vector2(sx * 0.112 + pel_x, pel_z)
			var dd := Vector2(ank.x, ank.z) - hxz
			if dd.length() > 0.78:
				var cl := hxz + dd.normalized() * 0.78
				pl += cl - Vector2(ank.x, ank.z)
				_ft_pin[i] = _l2w(pl)
				ank = _ankle_of(pl, _ft_kind[i], psi, th)
			pit = th
			yaw_w = _ry + psi
		else:
			var s := _ft_s[i]
			var sh := clampf(s / SET_DOWN, 0.0, 1.0) # the foot arrives over its spot, then it is set down on it
			var e := sh * sh * (3.0 - 2.0 * sh)
			var ev := s * s * (3.0 - 2.0 * s)
			var goal: Vector2
			var gth := 0.0
			var gyaw := yaw_td
			if s < SET_DOWN:
				if st == ST_SWING or _gait_on:
					var t_rem := (1.0 - s) * (1.0 - _ft_philo[i]) * f_inv if st == ST_SWING else 0.1
					goal = _l2w(tgt) + vw * t_rem
					gth = th0
				else:
					goal = _l2w(home)
					gyaw = home_yaw_w
				_ft_goal[i] = goal
				_ft_goal_th[i] = gth
				_ft_goal_yaw[i] = gyaw
			else:
				goal = _ft_goal[i]
				gth = _ft_goal_th[i]
				gyaw = _ft_goal_yaw[i]
			var aw := _ft_from[i].lerp(goal, e)
			var al := _w2l(aw)
			var arc := sin(PI * pow(s, 0.8)) * smoothstep(0.0, 0.14, s)
			# the ankle stays up where it left the ground and comes down late: the toe never drags
			var y := lerpf(_ft_from_y[i], _ankle_y(gth), ev * ev) + (apex if st == ST_SWING else 0.04) * arc
			ank = Vector3(al.x + sx * 0.03 * sin(PI * s), y, al.y)
			# the pitch leaves the stance turning at the rate it had, and settles on the landing pitch
			var sp := clampf(s / 0.85, 0.0, 1.0)
			var h00 := 2.0 * sp * sp * sp - 3.0 * sp * sp + 1.0
			var h10 := sp * sp * sp - 2.0 * sp * sp + sp
			var h01 := -2.0 * sp * sp * sp + 3.0 * sp * sp
			var m0 := clampf(_ft_from_pv[i] * (1.0 - _ft_philo[i]) * f_inv if st == ST_SWING else _ft_from_pv[i] * _ft_dur[i], -2.5, 2.5) * 0.85
			pit = h00 * _ft_from_th[i] + h10 * m0 + h01 * gth
			yaw_w = lerp_angle(_ft_from_yaw[i], gyaw, e)
			# the pelvis respects a foot that is about to land and one that has just left
			w = maxf(1.0 - smoothstep(0.0, 0.15, s), smoothstep(0.55, 0.85, s))
		if st != ST_STAND and side_k < 0.3:
			# a swinging foot never passes through the planted leg: it keeps its own side of it (going sideways the
			# legs cross, one in front of the other: the landing spots are offset in depth instead)
			var oth := _ft_ank[1 - i]
			if i == 1:
				ank.x = minf(ank.x, oth.x - 0.11)
			elif _ft_st[1] == ST_STAND:
				ank.x = maxf(ank.x, oth.x + 0.11)
		_ft_pv[i] = lerpf(_ft_pv[i], (pit - _ft_pit[i]) / maxf(dt, 0.001), 0.6) if dt > 0.0 else _ft_pv[i]
		_ft_ank[i] = ank
		_ft_pit[i] = pit
		_ft_wy[i] = yaw_w
		_ft_ry[i] = wrapf(yaw_w - _ry, -PI, PI)
		_ft_aw[i] = _l2w(Vector2(ank.x, ank.z))
		_ft_ay[i] = ank.y
		_ft_w[i] = w


## The highest the pelvis may stand (its y offset) with every foot that matters still within the leg's reach.
func _pelvis_limit(pel: Vector3, pelr: Vector3) -> float:
	var pb := eul(pelr)
	var lim := pel.y
	var lmax := (LEN_TH + LEN_SH) * LEG_REACH
	for i in 2:
		if _ft_w[i] < 0.01:
			continue
		var sx := 1.0 if i == 0 else -1.0
		var hv := pb * (mx(P_HIP, sx) - P_PELVIS)
		var hx := P_PELVIS.x + pel.x + hv.x
		var hz := P_PELVIS.z + pel.z + hv.z
		var a := _ft_ank[i]
		var dh2 := (a.x - hx) * (a.x - hx) + (a.z - hz) * (a.z - hz)
		var room := sqrt(maxf(lmax * lmax - dh2, 0.0025))
		var py := a.y + room - hv.y - P_PELVIS.y
		lim = minf(lim, lerpf(pel.y, minf(py, pel.y), _ft_w[i]))
	return maxf(lim, pel.y - 0.12)


## The guard's weight: eased between 0 and 1, and past them (the spring's overshoot) linear.
func _guard_shape() -> float:
	var k := clampf(_guard_k, 0.0, 1.0)
	return smooth(k) + (_guard_k - k) * 0.9


static func _softmin(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


func _ground_pose(c: PackedFloat32Array, dt: float) -> void:
	var v := _spd # the feet's speed (the stride matches the ground)
	_vu = lerpf(_vu, v, 1.0 - exp(-dt * 7.0)) # the body's: the arms and the trunk follow it a little later
	_yaw_lead = lerpf(_yaw_lead, _yaw_inst, 1.0 - exp(-dt * 18.0))
	_yaw_head = lerpf(_yaw_head, _yaw_lead, 1.0 - exp(-dt * 9.0))
	var vu := _vu
	var move := smoothstep(0.05, 0.6, vu)
	# the arms leave their idle poses a little more slowly than the legs start
	_mv_arm = lerpf(_mv_arm, move, 1.0 - exp(-dt * 9.0))
	var mva := _mv_arm
	var run := smoothstep(2.3, 4.6, v)
	var sprint := smoothstep(6.2, 8.4, v)
	var idle := 1.0 - move
	# direction of travel in rig space (CORE: strafing round a locked target, back-pedalling with the chain)
	var lv := (global_transform.basis.inverse() * _vel) if is_inside_tree() else Vector3(0.0, 0.0, -v)
	var lv2 := Vector2(lv.x, lv.z)
	# (an angle, so that going from forward to backward turns through the side instead of sticking at forward)
	if lv2.length() > 0.35:
		_mang = lerp_angle(_mang, atan2(lv2.x, -lv2.y), 1.0 - exp(-dt * 10.0))
	elif move < 0.2:
		_mang = lerp_angle(_mang, 0.0, 1.0 - exp(-dt * 4.0))
	_mdir = Vector2(sin(_mang), -cos(_mang))
	var side_k := absf(_mdir.x)
	var back_k := clampf(_mdir.y, 0.0, 1.0)
	var br := sin(t * lerpf(1.7, 3.4, tired))
	c[C_CHS] -= 0.066 * (1.0 - move) # (the idle chest is not thrown back: about 1.4 degrees behind the vertical)
	var tn := Vector2(_mdir.x, _mdir.y)
	var guard_g := _guard_shape()
	# --- the gait: cadence, stance share, how far a stance carries the body
	_rig_frame()
	var replant := not _fp_ok or _adv_n - _gp_n > 1
	if replant:
		# (the first frame, or back from the air, a swim, a roll: the feet are put down afresh)
		_gait_on = false
		_plant_home(c, guard_g)
	_gp_prev = _gp_n
	_gp_n = _adv_n
	var kdir := lerpf(1.0, 0.62, side_k) * lerpf(1.0, 0.75, back_k)
	# a start: the first steps are quick ones (the cadence follows the speed the body is about to have)
	var a_f := _acc.dot(-global_transform.basis.z) if is_inside_tree() else 0.0
	# how hard the speed being fed is rising (the rig's own estimate of the acceleration lags): the stride and the
	# stance of the first steps follow where the speed is going
	var a_raw := (speed - _speed_prev) / maxf(dt, 0.001) if _adv_n - _gp_prev <= 1 else 0.0
	_speed_prev = speed
	_a_fwd = lerpf(_a_fwd, clampf(a_raw, -60.0, 60.0), 1.0 - exp(-dt * 25.0))
	var v_g := v + clampf(_a_fwd, 0.0, 45.0) * 0.1
	var f_cyc := maxf(_pl(v_g, T_F) / kdir, 0.3)
	var duty := _pl(v_g, T_D)
	var reach_f := 0.38 * v_g * duty / f_cyc
	var want := speed > (GAIT_OFF_V if _gait_on else GAIT_ON_V) and not _sk_on
	if want and not _gait_on:
		var at_speed := replant and v > 2.5
		var stance := _gait_start(duty, tn, at_speed)
		if at_speed:
			_plant_landing(c, stance, v, reach_f, side_k, tn)
	elif not want and _gait_on and not _sk_on:
		_gait_stop()
	if _gait_on:
		_gph = fposmod(_gph + f_cyc * dt, 1.0)
	# what the cycle drives (the pelvis's sway, turn and list, the bob, the arms' swing) fades in with the gait: a gait
	# that starts again while the body is still moving does not make them jump to the new phase
	_gait_w = move_toward(_gait_w, 1.0 if _gait_on else 0.0, dt / 0.12)
	var gw := smoothstep(0.0, 1.0, _gait_w)
	var p := _gph
	var th := TAU * p
	# --- the trunk's lean: speed, the push of an acceleration, the roll of a turn
	var vf := vu * clampf(-_mdir.y, -1.0, 1.0)
	var lean := deg_to_rad(_pl(maxf(vf, 0.0), T_LEAN)) - 0.008 * minf(maxf(-vf, 0.0), 3.0)
	var sdt := minf(dt, 1.0 / 30.0)
	var w2 := 16.0 * 16.0
	_lean_accv += (w2 * (clampf(a_f * 0.0042, -0.14, 0.12) - _lean_acc) - 32.0 * _lean_accv) * sdt
	_lean_acc += _lean_accv * sdt
	var roll_goal := clampf(_yaw_lead * minf(vu, 7.0) * 0.0046, -0.2, 0.2) - _mdir.x * minf(vu, 5.0) * 0.012 * side_k
	var w3 := 14.0 * 14.0
	_roll_turnv += (w3 * (roll_goal - _roll_turn) - 28.0 * _roll_turnv) * sdt
	_roll_turn += _roll_turnv * sdt
	var lean_c := (lean + _lean_acc) * LEAN_LINE
	# --- pelvis: forward with the lean, over the stance foot, up and down twice a stride
	var pel := Vector3(c[C_PEL], c[C_PEL + 1], c[C_PEL + 2])
	var sway := _pl(vu, T_SWAY) * gw
	var mid := p - duty * 0.5
	pel.x += sway * cos(TAU * mid) + 0.012 * sin(t * 0.45) * idle
	# STOW (P1): standing, his weight rests on one leg (the other hip drops, the shoulders tilt against it), and shifts now and then
	var wsh := _idle_shift(dt, idle)
	pel.x += 0.03 * wsh
	pel.z += _pl(vu, T_PELZ) + _lean_acc * 0.25
	# --- the feet
	if not _sk_on:
		_feet_update(c, dt, v, run, f_cyc, duty, reach_f, pel.x, pel.z, side_k, guard_g, tn)
	for i in 2:
		var o := C_FR if i == 0 else C_FL
		var ro := C_FRR if i == 0 else C_FLR
		var sx := 1.0 if i == 0 else -1.0
		_setv(c, o, _ft_ank[i])
		_setv(c, ro, Vector3(_ft_pit[i], _ft_ry[i], 0.0))
		_setv(c, o + 6, Basis(Vector3.UP, _ft_ry[i]) * Vector3(sx * _pl(v, T_KNEE), 0.0, -1.0))
	# --- pelvis height: the bob (twice a stride), lowered where the leg would over-reach
	var bob := _pl(vu, T_BOB) * gw * cos(TAU * 2.0 * mid)
	# (walking through the wheat with the hand out, the legs are straighter: the hand's height is the ears' and the shoulder
	# has to be where the arm reaches it without the shield folding into the chest)
	pel.y = _pl(vu, T_PELH) + bob + 0.05 * smooth(_brush) + _land_x
	var yaw_a := deg_to_rad(_pl(vu, T_PYAW)) * gw
	var list_a := deg_to_rad(_pl(vu, T_PROLL)) * gw
	var pelr := Vector3(c[C_PELR] * idle - LEAN_SHARE_PELVIS * lean_c, yaw_a * cos(th),
		c[C_PELR + 2] + list_a * cos(TAU * (p - duty * 0.5)) + 0.012 * sin(t * 0.45) * idle)
	pelr.z += _roll_turn * 0.2 + 0.055 * wsh
	pel.y = _softmin(pel.y, _pelvis_limit(pel, pelr), 0.03)
	# the pelvis drops at once where the leg would over-reach, but rises again no faster than a body can
	if _adv_n - _gp_prev > 1 or not _pel_ok:
		_pel_yp = pel.y
		_pel_ok = true
	pel.y = minf(lerpf(_pel_yp, pel.y, 1.0 - exp(-dt * 30.0)), _pel_yp + 1.5 * dt)
	_pel_yp = pel.y
	_setv(c, C_PEL, pel)
	_setv(c, C_PELR, pelr)
	# --- spine and chest: lean, counter-rotation (the chest turns against the pelvis), the roll of a turn
	var cr := _pl(vu, T_CRATIO)
	var chest_yaw := -cr * yaw_a * cos(th - 0.25) + clampf(_yaw_lead * 0.03, -0.2, 0.2)
	var chest_roll := -0.5 * list_a * cos(TAU * (p - duty * 0.5)) + _roll_turn * 0.8
	var bob_p := 0.02 * run * gw * cos(TAU * 2.0 * (mid + 0.12))
	# (the landing folds the trunk over the dipping pelvis: about 2.5 rad per metre of dip)
	_setv(c, C_SPN, Vector3(-LEAN_SHARE_SPINE * lean_c + 2.0 * _land_x, 0.4 * (chest_yaw - pelr.y), 0.4 * (chest_roll - pelr.z)))
	var chs := v3(c, C_CHS)
	chs.x = chs.x * idle - (1.0 - LEAN_SHARE_PELVIS - LEAN_SHARE_SPINE) * lean_c + bob_p
	chs.y += 0.6 * (chest_yaw - pelr.y)
	chs.z += 0.6 * (chest_roll - pelr.z)
	chs.x += lerpf(0.018, 0.05, tired) * br * idle - 0.12 * tired * idle
	chs.z -= 0.035 * wsh
	_setv(c, C_CHS, chs)
	if tired > 0.0:
		# winded: the head drops, the shoulders heave
		c[C_NEK] -= 0.1 * tired * idle
		c[C_SPN] -= 0.05 * tired * idle
	# --- neck and head: the gaze stays level and forward whatever the trunk does
	var chest_pitch := -(c[C_PELR] + c[C_SPN] + c[C_CHS])
	var gaze := deg_to_rad(_pl(vu, T_HEADP))
	var comp := chest_pitch - gaze
	var nek_x := lerpf(c[C_NEK], 0.55 * comp, move)
	var hed_x := lerpf(c[C_HED], 0.45 * comp, move)
	var chest_yaw_w := c[C_PELR + 1] + c[C_SPN + 1] + c[C_CHS + 1]
	var head_yaw := -chest_yaw_w * 0.85 + clampf(_yaw_head * 0.05, -0.35, 0.35)
	var chest_roll_w := c[C_PELR + 2] + c[C_SPN + 2] + c[C_CHS + 2]
	_setv(c, C_NEK, Vector3(nek_x, lerpf(c[C_NEK + 1], 0.5 * head_yaw, move), lerpf(c[C_NEK + 2], -0.5 * chest_roll_w, move)))
	_setv(c, C_HED, Vector3(hed_x + 0.008 * br * idle, lerpf(0.08 * sin(t * 0.31) * idle, 0.5 * head_yaw, move), lerpf(0.0, -0.4 * chest_roll_w, move)))
	# --- arms (STOW): each relaxed (an empty fist swinging against the opposite leg) or armed (the sword carried low and trailing, the
	# shield at the side), by what is in its hand; standing, the idles (_ground_arms)
	var armk := lerpf(1.0, 0.6, maxf(side_k, back_k * 0.6))
	# (and the arms fly out to the sides for balance as the ground is met, then come back with the spring)
	var land_arm := clampf(-_land_x / 0.1, -0.5, 2.0) * _land_k
	_ground_arms(c, vu, gw, th, run, mva, br, armk, land_arm, idle)
	# --- guard (P7): crouched behind the shield held up in front of him (he looks over its rim), the shield side forward, the sword arm
	# drawn back low with the blade trailing
	if absf(_guard_k) > 0.001:
		var g := _guard_shape()
		_lerpv(c, C_HL, Vector3(-0.1, 0.04, -0.42), g)
		_lerpv(c, C_HLF, Vector3(-0.12, 0.1, -1.0), g)
		_lerpv(c, C_HLP, Vector3(-1.0, -0.7, 0.3), g)
		_lerpv(c, C_HR, Vector3(0.35, -0.36, 0.1), g)
		_lerpv(c, C_HRB, Vector3(0.32, -0.5, 0.8), g)
		_lerpv(c, C_HRK, Vector3(0.7, 0.1, -0.7), g)
		_lerpv(c, C_HRP, Vector3(0.6, -0.2, 1.0), g)
		c[C_CHS + 1] -= 0.16 * g
		c[C_SPN] -= 0.1 * g
		c[C_CHS] -= 0.04 * g
		c[C_PEL + 1] -= lerpf(0.09, 0.05, move) * g
		c[C_NEK + 1] += 0.13 * g
		c[C_NEK] += 0.06 * g
		c[C_HED] += 0.03 * g
		# a blow on the shield: the shield arm is driven back towards the chest, the chest leans back with it
		if absf(_jolt) > 0.001:
			var j := clampf(_jolt, -0.4, 1.0) * g
			_addv(c, C_HL, Vector3(-0.03, 0.03, 0.12) * j)
			c[C_CHS] += 0.12 * j
			c[C_SPN] += 0.06 * j
			c[C_PEL + 2] += 0.05 * j
	# FINAL: the free hand in the wheat (set_brush)
	_brush_pose(c, dt, move, run, _gph)


## FINAL: while the hand brushes the wheat the shield rides up the arm (the forearm slides out of the arm band, which
## settles on the upper arm), so the forearm and the open hand come out free under its rim: from behind (the gameplay
## camera) the shield shows edge on at the shoulder and the hand out over the ears.
const BRUSH_SHIELD_SLIDE := 0.62 # how far up the arm, as a fraction of the elbow -> shoulder length
var _brush_run := 0.0


func _brush_shield() -> void:
	var piv := _piv["farm_l_s"] as Node3D
	piv.transform = piv.transform.interpolate_with(_brush_shield_skin(), _brush_shield_k())


## The shield rides up once the arm is on its way out (clear of the shoulder piece), and comes down first.
func _brush_shield_k() -> float:
	return smoothstep(0.35, 1.0, _brush)


## Where the shield's pivot goes when it has ridden up onto the upper arm (a skin transform: rest rig space -> rig).
## Walking: it rides the upper arm as strapped there (its face out and forward, the inside showing from behind).
## Running: the arm band sits at the elbow with the face turned out whatever the arm's twist (nearly edge on from
## behind, clear of the helmet's cheek guard and of his back as the arm swings). Both checked clear of the body by
## tools/wheat_walk.tscn (shield_clip).
const BRUSH_SHIELD_FACE := Vector3(-1.0, 0.0, 0.0)
static var _shield_rest := Transform3D()
static var _shield_rest_ok := false


func _brush_shield_skin() -> Transform3D:
	var ua := _bx[UARM_L]
	var ua_skin := Transform3D(ua.basis, ua.origin - ua.basis * _rest[UARM_L])
	var walk_xf := ua_skin * Transform3D(Basis.IDENTITY, (_rest[UARM_L] - _rest[FARM_L]) * BRUSH_SHIELD_SLIDE)
	if _brush_run <= 0.001:
		return walk_xf
	if not _shield_rest_ok:
		_shield_rest = shield_xf(Transform3D(Basis.IDENTITY, _rest[FARM_L]), _rest[FARM_L])
		_shield_rest_ok = true
	var s_p := _bx[UARM_L].origin
	var e_p := _bx[FARM_L].origin
	var a := (e_p - s_p).normalized()
	var n := perp(BRUSH_SHIELD_FACE, a).normalized()
	var ax := perp(a, n).normalized()
	var up := (BRUSH_SHIELD_SLIDE - 0.2) * LEN_UA - 0.13
	var run_xf := Transform3D(Basis(ax, n, ax.cross(n)), e_p - a * up + n * 0.085) * _shield_rest.affine_inverse()
	return walk_xf.interpolate_with(run_xf, _brush_run)


## FINAL: the left arm out beside the hip, the hand open and palm down over the ears (rig space, so the hand glides
## level while the body bobs), swaying a little with the stride and riding up and down over the ears twice a stride;
## at a run it trails a little further back. The open hand is fanned out to the side and a little back, the fingers
## dipping into the ears; the forearm turns with the hand (no twist at the wrist) now that the shield hangs from the
## upper arm (_brush_shield).
const BRUSH_BACK := Vector3(-0.302, 0.893, 0.333) # the back of the hand (palm down, fingers out, back and down)
const BRUSH_THUMB := Vector3(-0.739, 0.0, -0.672) # hand_basis' blade axis: the thumb side (out and forward)


func _brush_pose(c: PackedFloat32Array, dt: float, move: float, run: float, ph: float) -> void:
	var goal := brush_goal * (1.0 - clampf(_guard_k, 0.0, 1.0))
	_brush = move_toward(_brush, goal, dt * (2.2 if goal > _brush else 3.4))
	if _brush <= 0.0005:
		return
	var w := smooth(_brush)
	_brush_run = run
	var sw := cos(TAU * ph) * move # the left arm's swing in the gait (as above)
	var skim := sin(TAU * 2.0 * ph) * move
	var tgt := Vector3(-0.52 - 0.07 * run, brush_height + 0.014 * skim + 0.025 * run, 0.04 - 0.03 * run - lerpf(0.05, 0.06, run) * sw)
	_setv(c, C_HL, v3(c, C_HL).lerp(tgt, w))
	c[C_HLS] = lerpf(c[C_HLS], 1.0, w)
	_lerpv(c, C_HLP, Vector3(-1.0, 0.05, 0.4), w)
	var dip := Vector3(-0.05 * skim, 0.0, 0.0)
	_lerpv(c, C_HLF, BRUSH_BACK, w)
	_lerpv(c, C_HLB, BRUSH_THUMB, w)
	_lerpv(c, C_HLK, BRUSH_BACK + dip, w)
	c[C_HLX] = lerpf(c[C_HLX], 1.0, w)
	if _brush > 0.35:
		c[C_OHL] = 1.0


## Hanging from a ring: where the left fist grips the chain (rig space; the body swings about it). Hero.HANG_HAND
## matches it.
const HANG_GRIP := Vector3(-0.38, 2.02, -0.03)


## CORE: hanging from the chain under a bronze ring: the left fist high on the chain (the arm nearly straight, the
## shield upright beside the head), the sword arm loose, the legs together and a little bent, the whole body
## swinging gently about the hand.
func _hang_pose(c: PackedFloat32Array, dt: float) -> void:
	var lvx := (global_transform.basis.inverse() * _vel) if is_inside_tree() else Vector3.ZERO
	_hang_swv += (-_hang_sw * 9.0 - _hang_swv * 1.6 - lvx.z * 0.9) * dt
	_hang_sw = clampf(_hang_sw + _hang_swv * dt, -0.35, 0.35)
	var sw := _hang_sw + sin(t * 2.1) * 0.025
	_setv(c, C_PIV, HANG_GRIP)
	_setv(c, C_ROT, Vector3(sw, 0.0, sin(t * 1.3) * 0.02))
	_setv(c, C_PEL, Vector3(0.0, 0.0, 0.0))
	_setv(c, C_PELR, Vector3(-0.08, 0.0, 0.0))
	_setv(c, C_SPN, Vector3(0.05, 0.08, 0.0))
	_setv(c, C_CHS, Vector3(0.06, 0.12, 0.04))
	_setv(c, C_NEK, Vector3(0.12, -0.12, 0.0))
	_setv(c, C_HED, Vector3(0.08, -0.05, 0.0))
	# the left fist high on the chain, the arm nearly straight and a little out to the side: the shield on the
	# forearm hangs upright beside the head, facing out, clear of the shoulder and the crest
	var lb := Vector3(0.0, 1.0, 0.0)
	var lk := Vector3(-1.0, 0.0, 0.15)
	_setv(c, C_HL, _lw(HANG_GRIP - P_CHEST, lb, lk))
	_setv(c, C_HLB, lb)
	_setv(c, C_HLK, lk)
	c[C_HLX] = 1.0
	_setv(c, C_HLF, Vector3(-1.0, 0.0, 0.1))
	_setv(c, C_HLP, Vector3(-0.8, -0.5, 0.3))
	_setv(c, C_HR, Vector3(0.37, -0.36, -0.02))
	_setv(c, C_HRB, Vector3(0.15, -0.7, -0.6))
	_setv(c, C_HRK, Vector3(1.0, 0.1, 0.1))
	_setv(c, C_HRP, Vector3(0.6, -0.2, 1.0))
	var fl := sin(t * 1.9) * 0.015
	_setv(c, C_FR, Vector3(0.11, 0.2 + fl, 0.1))
	_setv(c, C_FRR, Vector3(-0.55, -0.08, 0.0))
	_setv(c, C_FRP, Vector3(0.2, 0.0, -1.0))
	_setv(c, C_FL, Vector3(-0.11, 0.14 - fl, 0.03))
	_setv(c, C_FLR, Vector3(-0.45, 0.08, 0.0))
	_setv(c, C_FLP, Vector3(-0.2, 0.0, -1.0))


func _air_pose(c: PackedFloat32Array) -> void:
	var k := smoothstep(1.5, -4.0, _vy) # 0 rising .. 1 falling
	var run := smoothstep(1.5, 6.0, _spd) # 0 a jump from standing .. 1 a leap from a run
	var fl := sin(t * 7.0) * 0.02
	_setv(c, C_PEL, Vector3(0.0, lerpf(0.02, -0.02, k), 0.0))
	_setv(c, C_PELR, Vector3(lerpf(0.12, -0.05, k), 0.0, 0.0))
	_setv(c, C_SPN, Vector3(lerpf(-0.12, 0.04, k), 0.0, 0.0))
	_setv(c, C_CHS, Vector3(lerpf(0.0, 0.08, k), 0.05, 0.0))
	_setv(c, C_NEK, Vector3(lerpf(0.05, -0.12, k), 0.0, 0.0))
	# the legs are not a seated tuck: the right leg leads (the knee comes up and forward on the rise, the foot reaches down and ahead on
	# the way down) and the left trails behind (extended back on the rise, coming under him for the landing); the faster he came, the
	# longer the stride between them
	_setv(c, C_FR, Vector3(0.13, lerpf(lerpf(0.42, 0.5, run), lerpf(0.17, 0.15, run), k) + fl, lerpf(lerpf(-0.26, -0.42, run), lerpf(-0.14, -0.3, run), k)))
	_setv(c, C_FRR, Vector3(lerpf(-0.2, 0.2, k), -0.1, 0.0))
	_setv(c, C_FL, Vector3(-0.14, lerpf(lerpf(0.26, 0.34, run), lerpf(0.17, 0.16, run), k) - fl, lerpf(lerpf(0.22, 0.4, run), lerpf(0.08, 0.2, run), k)))
	_setv(c, C_FLR, Vector3(lerpf(-0.8, -0.2, k), 0.1, 0.0))
	# the arms (P6): spread out to his sides for balance, up and out on the rise, lower on the way down; armed, the sword arm out to his
	# side with the blade out and back (clear of his legs), the shield out in front of his left side
	var ksw := smoothstep(0.0, 1.0, _carry_sw)
	var ksh := smoothstep(0.0, 1.0, _carry_sh)
	_setv(c, C_HR, Vector3(lerpf(0.62, 0.6, k), lerpf(0.1, -0.04, k), lerpf(-0.2, -0.06, k)))
	_setv(c, C_HRB, Vector3(0.1, 0.05, -1.0).slerp(Vector3(0.7, -0.2, 0.68).normalized(), ksw))
	_setv(c, C_HRK, Vector3(0.05, 1.0, 0.1).slerp(Vector3(0.2, 1.0, -0.3), ksw))
	_setv(c, C_HRP, Vector3(0.6, -0.5, 0.8))
	_setv(c, C_HL, Vector3(lerpf(-0.62, -0.6, k), lerpf(0.1, -0.04, k), lerpf(-0.2, -0.06, k)).lerp(Vector3(lerpf(-0.46, -0.5, k), lerpf(-0.02, -0.08, k), lerpf(-0.32, -0.22, k)), ksh))
	_setv(c, C_HLF, Vector3(-0.1, 1.0, 0.0).lerp(Vector3(-0.6, -0.1, -0.8), ksh))
	_setv(c, C_HLP, Vector3(-0.6, -0.6, 0.8))


## Left wrist target that puts the left fist's centre at `fist` with the given blade (held spear / chain) and
## back-of-hand directions (all in the same space).
static func _lw(fist: Vector3, blade: Vector3, back: Vector3) -> Vector3:
	return fist - hand_basis(blade, back, -1.0) * GRIP


## Cyclic key interpolation: keys [[phase, value], ...] sorted, smoothstepped between neighbours.
static func _cyc(keys: Array, p: float) -> Variant:
	var n := keys.size()
	for i in n:
		var a: Array = keys[i]
		var b: Array = keys[(i + 1) % n]
		var pa: float = a[0]
		var pb: float = b[0] if i + 1 < n else float(b[0]) + 1.0
		var pp := p if p >= pa else p + 1.0
		if pp >= pa and pp < pb:
			var k := smooth((pp - pa) / (pb - pa))
			return lerp(a[1], b[1], k)
	return keys[0][1]


## Swimming at the surface: a breaststroke (pulls, frog kicks, glides) when moving, treading water when not.
## The body pitches about the waterline (swim_waterline above the rig origin) so the helmet stays above it.
func _swim_pose(c: PackedFloat32Array, dt: float) -> void:
	var mv := smoothstep(0.25, 1.6, _spd)
	_swim_phase = fposmod(_swim_phase + dt * lerpf(0.42, 0.8, mv), 1.0)
	var p := _swim_phase
	var tread := 1.0 - mv
	var stroke := sin(TAU * p)
	_setv(c, C_PIV, Vector3(0.0, swim_waterline, 0.0))
	_setv(c, C_ROT, Vector3(lerpf(-0.3, -1.0, mv) + 0.05 * stroke * mv, 0.0, 0.0))
	_setv(c, C_PEL, Vector3(0.0, -0.03 + 0.02 * stroke * tread, 0.0))
	_setv(c, C_PELR, Vector3(0.0, 0.0, 0.0))
	_setv(c, C_SPN, Vector3(0.06 + 0.05 * mv, 0.0, 0.0))
	_setv(c, C_CHS, Vector3(0.04 + 0.04 * mv - 0.05 * stroke * mv, 0.0, 0.0))
	_setv(c, C_NEK, Vector3(0.1 + 0.3 * mv, 0.0, 0.0))
	_setv(c, C_HED, Vector3(0.05 + 0.22 * mv, 0.0, 0.0))
	# arms: breaststroke keys (right grip, chest space) and treading-water sculls
	var ext := Vector3(0.1, 0.56, -0.36)
	var wide := Vector3(0.5, 0.42, -0.26)
	var pulled := Vector3(0.38, 0.08, -0.33)
	var under := Vector3(0.09, 0.04, -0.38)
	var hk := [[0.0, ext], [0.12, wide], [0.3, pulled], [0.42, under], [0.62, ext]]
	var bk := [[0.0, Vector3(0.0, 0.85, -0.52)], [0.12, Vector3(0.6, 0.5, -0.6)], [0.3, Vector3(0.3, 0.2, -0.93)], [0.42, Vector3(-0.2, 0.5, -0.85)], [0.62, Vector3(0.0, 0.85, -0.52)]]
	var sw: Vector3 = _cyc(hk, p)
	var sb: Vector3 = _cyc(bk, p)
	var ang := TAU * p * 1.5
	var scull := Vector3(0.32 + 0.07 * sin(ang), -0.04 + 0.02 * cos(ang * 2.0), -0.3 + 0.07 * cos(ang))
	_setv(c, C_HR, scull.lerp(sw, mv))
	_setv(c, C_HRB, Vector3(0.3, -0.1, -1.0).lerp(sb, mv))
	_setv(c, C_HRK, Vector3(1.0, 0.3, 0.0))
	_setv(c, C_HRP, Vector3(0.8, -0.4, 0.4))
	# the left arm holds the shield flat on the water like a float: out at the side treading, ahead when stroking
	var side_float := Vector3(-0.46, -0.06, -0.12)
	var board := Vector3(-0.3, 0.58, -0.24)
	_setv(c, C_HL, side_float.lerp(board, mv) + Vector3(0.0, 0.015 * stroke, 0.0))
	var pitch := lerpf(-0.3, -1.0, mv)
	_setv(c, C_HLF, Vector3(0.0, -cos(pitch), sin(pitch)))
	_setv(c, C_HLP, Vector3(-0.9, 0.0, 0.3))
	# legs: frog kick (knees out, feet up, snap back) or a slow alternating pedal
	var kick := [[0.0, Vector3(0.11, 0.1, 0.06)], [0.3, Vector3(0.12, 0.12, 0.08)], [0.46, Vector3(0.24, 0.36, 0.26)], [0.6, Vector3(0.18, 0.12, 0.1)], [0.7, Vector3(0.11, 0.1, 0.06)]]
	var kr := [[0.0, Vector3(-1.1, -0.1, 0.0)], [0.3, Vector3(-0.9, -0.1, 0.0)], [0.46, Vector3(0.35, -0.6, 0.0)], [0.6, Vector3(-0.6, -0.3, 0.0)], [0.7, Vector3(-1.1, -0.1, 0.0)]]
	var kf: Vector3 = _cyc(kick, p)
	var kfr: Vector3 = _cyc(kr, p)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var pp := TAU * p + (0.0 if side == 0 else PI)
		var ped := Vector3(0.13, 0.2 + 0.1 * sin(pp), 0.05 + 0.09 * cos(pp))
		var f := ped.lerp(kf, mv)
		_setv(c, C_FR if side == 0 else C_FL, Vector3(f.x * sx, f.y, f.z))
		var fr := Vector3(-0.5 + 0.3 * sin(pp + 1.0), 0.0, 0.0).lerp(kfr, mv)
		_setv(c, C_FRR if side == 0 else C_FLR, Vector3(fr.x, fr.y * sx, 0.0))
		_setv(c, C_FRP if side == 0 else C_FLP, Vector3(0.6 * sx, 0.0, -1.0))


var _zip_pitch := -0.9
## CORE: the lip's height over the rig's origin while the hero climbs a ledge (Hero sets it each tick of the climb;
## -99 none): the hands of the climb's grip keys (0.12-0.33, rig space) are held on it, so they neither float over
## the lip nor sink into it while the body rises at its own pace.
var climb_lip := -99.0


func _pin_climb_hands() -> void:
	var w := smoothstep(0.06, 0.12, action_t) * (1.0 - smoothstep(0.33, 0.4, action_t))
	if w <= 0.0:
		return
	_pose[C_HR + 1] = lerpf(_pose[C_HR + 1], climb_lip + 0.06, w * clampf(_pose[C_HRS], 0.0, 1.0))
	_pose[C_HL + 1] = lerpf(_pose[C_HL + 1], climb_lip + 0.05, w * clampf(_pose[C_HLS], 0.0, 1.0))
## CORE: 0..1 near the end of a zip to a ring: the body comes upright for the hang or the climb (Hero sets it).
var zip_upright := 0.0


## Zipping along the chain: stretched towards the anchor (the body lies along the velocity), the chain fist
## reaching ahead, the sword trailing, legs together.
func _zip_pose(c: PackedFloat32Array, dt: float) -> void:
	var hv := Vector2(_vel.x, _vel.z).length()
	var elev := atan2(_vel.y, maxf(hv, 1.0))
	var want := clampf(-(PI * 0.5 - elev) * 0.85, -1.25, -0.2)
	want = lerpf(want, -0.12, clampf(zip_upright, 0.0, 1.0))
	_zip_pitch = lerpf(_zip_pitch, want, 1.0 - exp(-dt * 8.0))
	var fl := sin(t * 23.0) * 0.012
	_setv(c, C_PIV, Vector3(0.0, 1.0, 0.0))
	_setv(c, C_ROT, Vector3(_zip_pitch, 0.0, 0.0))
	_setv(c, C_PEL, Vector3(0.0, -0.01, 0.0))
	_setv(c, C_PELR, Vector3(0.0, 0.0, 0.0))
	_setv(c, C_SPN, Vector3(0.05, 0.05, 0.0))
	_setv(c, C_CHS, Vector3(0.04, 0.14, 0.0))
	_setv(c, C_NEK, Vector3(clampf(-_zip_pitch * 0.3, 0.0, 0.38), -0.1, 0.0))
	_setv(c, C_HED, Vector3(clampf(-_zip_pitch * 0.18, 0.0, 0.22), -0.05, 0.0))
	var lb := Vector3(0.05, 1.0, -0.4)
	var lk := Vector3(-1.0, 0.1, 0.3)
	_setv(c, C_HL, _lw(Vector3(-0.1, 0.58, -0.24), lb, lk))
	_setv(c, C_HLB, lb)
	_setv(c, C_HLK, lk)
	c[C_HLX] = 1.0
	_setv(c, C_HLF, Vector3(-1.0, 0.0, 0.25))
	_setv(c, C_HLP, Vector3(-1.0, 0.1, 0.4))
	_setv(c, C_HR, Vector3(0.36, -0.4, 0.12 + fl))
	_setv(c, C_HRB, Vector3(0.15, -0.6, 0.8))
	_setv(c, C_HRK, Vector3(1.0, 0.0, 0.0))
	_setv(c, C_HRP, Vector3(0.6, 0.0, 1.0))
	_setv(c, C_FR, Vector3(0.1, 0.17 + fl, 0.12))
	_setv(c, C_FRR, Vector3(-0.9, -0.05, 0.0))
	_setv(c, C_FL, Vector3(-0.1, 0.24 - fl, 0.19))
	_setv(c, C_FLR, Vector3(-0.8, 0.05, 0.0))


# --- secondary motion ----------------------------------------------------------------------------------------

func _secondary(dt: float) -> void:
	var gx := global_transform if is_inside_tree() else transform
	_crest_spring(dt, gx)
	_skirt_step(dt, gx)
	_cape_step(dt, gx)


## LOOK: the crest is gone (no helmet): nothing is skinned to CREST_B any more and its spring is off.
func _crest_spring(_dt: float, _gx: Transform3D) -> void:
	pass


## CORE: forget the secondary motion (cape, skirt, crest, tracked velocity): they restart from the rest drape
## at the next frame. Called by itself when the rig jumps more than 3 m in a frame (teleports, respawns).
func reset_cloth() -> void:
	_cape_pos.resize(0)
	_cape_prev.resize(0)
	_sk_tip.resize(0)
	_sk_prev.resize(0)
	_prev_head_p = Vector3.ZERO
	_prev_head_v = Vector3.ZERO
	_crest = Vector2.ZERO
	_crest_v = Vector2.ZERO
	_vel = Vector3.ZERO
	_acc = Vector3.ZERO
	_have_prev = false
	_fp_ok = false
	_gait_on = false


## Rest-space point carried by a bone's current pose (rig space).
func _carry(bone: int, p_rest: Vector3) -> Vector3:
	var b := _bx[bone]
	return b.origin + b.basis * (p_rest - _rest[bone])


# --- skirt: one pendulum per skirt bone (hinge on the belt, tip at the hem) ----------------------------------

const SKIRT_LEN := 0.29
const SKIRT_FLARE := 0.22
var _sk_tip := PackedVector3Array()
var _sk_prev := PackedVector3Array()


func _skirt_rest_dir(i: int) -> Vector3:
	var a := TAU * float(i) / float(SKIRT_N)
	return Vector3(sin(a) * SKIRT_FLARE, -1.0, -cos(a) * SKIRT_FLARE).normalized()


func _skirt_step(dt: float, gx: Transform3D) -> void:
	var pb := _bx[PELVIS].basis
	if _sk_tip.size() != SKIRT_N:
		_sk_tip.resize(SKIRT_N)
		_sk_prev.resize(SKIRT_N)
		for i in SKIRT_N:
			var h := gx * _carry(PELVIS, _rest[SKIRT0 + i])
			_sk_tip[i] = h + gx.basis * (pb * _skirt_rest_dir(i)) * SKIRT_LEN
			_sk_prev[i] = _sk_tip[i]
	# thighs (world): hip -> knee capsules
	var caps: Array = []
	for o in [0, 3]:
		caps.append([gx * _bx[THIGH_R + o].origin, gx * _bx[SHIN_R + o].origin, 0.125])
	var h2 := dt * dt
	var gvec := Vector3(0, -9.8, 0)
	var air := _air_velocity()
	for i in SKIRT_N:
		var hinge := gx * _carry(PELVIS, _rest[SKIRT0 + i])
		var rest_dir := gx.basis * (pb * _skirt_rest_dir(i))
		var target := hinge + rest_dir * SKIRT_LEN
		var tip := _sk_tip[i]
		if dt > 0.0:
			var vel := (tip - _sk_prev[i])
			_sk_prev[i] = tip
			var acc := gvec * 0.35 + (target - tip) * 160.0 + (air - vel / dt) * 1.2
			tip += vel * 0.86 + acc * h2
		# keep the length, stay outside the thighs and outside the hips
		for k in 2:
			tip = hinge + (tip - hinge).normalized() * SKIRT_LEN
			for cp in caps:
				tip = _push_capsule(tip, cp[0], cp[1], cp[2])
			var lp := (gx * _bx[PELVIS]).affine_inverse() * tip
			var rad := Vector2(lp.x, lp.z)
			var min_r := 0.2 + 0.05 * clampf((P_PELVIS.y - SKIRT_Y + 0.0 - lp.y) / SKIRT_LEN, 0.0, 1.0)
			if rad.length() < min_r:
				rad = rad.normalized() * min_r if rad.length() > 1e-4 else Vector2(sin(TAU * float(i) / float(SKIRT_N)), -cos(TAU * float(i) / float(SKIRT_N))) * min_r
				tip = (gx * _bx[PELVIS]) * Vector3(rad.x, lp.y, rad.y)
		_sk_tip[i] = tip
		var cur := (tip - hinge).normalized()
		var q := Quaternion(rest_dir.normalized(), cur)
		var wb := Basis(q) * (gx.basis * pb)
		_bx[SKIRT0 + i] = Transform3D(gx.basis.inverse() * wb, gx.affine_inverse() * hinge)


static func _push_capsule(p: Vector3, a: Vector3, b: Vector3, r: float) -> Vector3:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
	var c := a + ab * tt
	var d := p - c
	var l := d.length()
	if l >= r:
		return p
	if l < 1e-5:
		return c + Vector3(0, 0, r)
	return c + d / l * r


## Air velocity relative to the world (ambient breeze; tools add the virtual motion of the rig).
func _air_velocity() -> Vector3:
	return Vector3(0.3, 0.0, 0.18) * (0.6 + 0.4 * sin(t * 0.7)) - velocity_hint


# --- cape: a verlet grid pinned along the upper back, drawn as a skinned mesh (one bone per particle) ----------

const CAPE_NC := 13
const CAPE_NR := 10
var cape_skel: Skeleton3D
var _cape_pos := PackedVector3Array()
var _cape_prev := PackedVector3Array()
var _cape_rest := PackedVector3Array()
var _cape_ca := PackedInt32Array()
var _cape_cb := PackedInt32Array()
var _cape_cl := PackedFloat32Array()
var _cape_ck := PackedFloat32Array()
var _cape_wa := PackedFloat32Array()
var _cape_wb := PackedFloat32Array()
var _cape_meshes: Array[MeshInstance3D] = []
var _cape_outfit := &""
## Tools: names of cloth constraints to skip (debugging): caps, chest, spine, cone, shield, spear, drape, air.
var dbg_off: PackedStringArray = []


## Rest grid of the cape (or the lion pelt) in rest rig space: row 0 pinned, hanging down. LOOK2: the cloak's row 0 lies under
## the mantle's rolled hem, from the back of one deltoid round the upper back to the other (_cloak_pin); its rows fall wide and
## long (CLOAK_ROWS: wider than his back, wrapping a little round his sides, down to CLOAK_HEM above the ground) in a few big
## folds, clear of the body, the arms and the legs at rest (_cloak_rest_push). The pelt hangs from the upper back as before.
static func cape_rest(lion: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	if lion:
		for j in CAPE_NR:
			var v := float(j) / float(CAPE_NR - 1)
			var y := 1.475 - v * 1.0
			var hw := lerpf(0.24, 0.36, pow(v, 0.7))
			for i in CAPE_NC:
				var u := float(i) / float(CAPE_NC - 1) * 2.0 - 1.0
				var x := u * hw
				# over the shoulder blades, then out over the skirt, then straight down
				var z := 0.175 + 0.075 * smoothstep(0.0, 0.55, v) - 0.55 * x * x * (1.0 - v * 0.6)
				out.append(Vector3(x, y, z))
		return out
	# the pins evenly spaced along the pinned row (rays from MANTLE_O crowd them on the back and leave the shoulders bare)
	var pins := PackedVector3Array()
	var dense := PackedVector3Array()
	var m := 64
	for q in m + 1:
		dense.append(_cloak_pin(float(q) / float(m) * 2.0 - 1.0))
	var cum := PackedFloat32Array([0.0])
	for q in m:
		cum.append(cum[q] + dense[q].distance_to(dense[q + 1]))
	for i in CAPE_NC:
		var want := cum[m] * float(i) / float(CAPE_NC - 1)
		var q := 0
		while q < m - 1 and cum[q + 1] < want:
			q += 1
		pins.append(dense[q].lerp(dense[q + 1], clampf((want - cum[q]) / maxf(cum[q + 1] - cum[q], 1e-6), 0.0, 1.0)))
	for j in CAPE_NR:
		var v := float(j) / float(CAPE_NR - 1)
		var row := _cloak_row(v)
		for i in CAPE_NC:
			if j == 0:
				out.append(pins[i])
				continue
			var u := float(i) / float(CAPE_NC - 1) * 2.0 - 1.0
			var al := u * PI * 0.5
			var arc := Vector2(row.x * sin(al), row.y + (row.z - row.y) * cos(al))
			# the big folds stand off the arc along its outward normal
			var nrm := Vector2((row.z - row.y) * sin(al), row.x * cos(al)).normalized()
			arc += nrm * CLOAK_FOLD * smoothstep(0.2, 0.75, v) * cos(u * TAU)
			var pin := pins[i]
			var xz := Vector2(pin.x, pin.z).lerp(arc, smoothstep(0.0, 0.24, v))
			out.append(_cloak_rest_push(Vector3(xz.x, lerpf(pin.y, CLOAK_HEM, v), xz.y)))
	return out


## LOOK2: the cloak's measures: [v (0 the pinned row .. 1 the hem), half-width, z of its side edges, z in the middle] of its
## rows (rest rig space), the hem's height over the ground, the depth of its big folds, the strength of the pull back to the
## rest drape (the pelt keeps 3), the pinned row's reach round the back from its middle (rad) and the colliders' radii (the
## upper arms capping the deltoids, the forearms to the fists, the thighs, the shins).
const CLOAK_ROWS := [[0.0, 0.33, 0.12, 0.17], [0.11, 0.34, 0.17, 0.19], [0.3, 0.44, 0.13, 0.225], [0.5, 0.54, 0.07, 0.29],
	[0.7, 0.63, 0.03, 0.335], [1.0, 0.72, 0.0, 0.37]]
const CLOAK_HEM := 0.4
const CLOAK_FOLD := 0.055
const CLOAK_SHAPE_K := 10.0
const CLOAK_PIN_A := 1.38
const CLOAK_UARM_R := 0.135
const CLOAK_FARM_R := 0.125
const CLOAK_THIGH_R := 0.14
const CLOAK_SHIN_R := 0.125
## LOOK2: cloth up to this far outside the face of the shield on his arm (m, along its normal) is put back on his side of it.
const CLOAK_SHIELD_OUT := 0.2
## LOOK2: the chest's turn rates (rad/s) over which the cloak goes from swinging free to being carried round with him.
const CLOAK_SPIN := Vector2(4.0, 11.0)


## One of the cloak's rows: (half-width, z of the side edges, z in the middle).
static func _cloak_row(v: float) -> Vector3:
	var t := CLOAK_ROWS
	var k := 0
	while k < t.size() - 2 and v > float(t[k + 1][0]):
		k += 1
	var f := clampf((v - float(t[k][0])) / (float(t[k + 1][0]) - float(t[k][0])), 0.0, 1.0)
	return Vector3(lerpf(t[k][1], t[k + 1][1], f), lerpf(t[k][2], t[k + 1][2], f), lerpf(t[k][3], t[k + 1][3], f))


## A point of the cloak's pinned row (u -1 his left .. 1 his right): a little above the mantle's lower edge, under it.
static func _cloak_pin(u: float) -> Vector3:
	var a := PI - u * CLOAK_PIN_A
	var d := _mantle_dir(a, _mantle_phi(a).y + deg_to_rad(5.0))
	return MANTLE_O + d * (_body_ray(d).x + 0.006)


## A rest position of the cloak pushed clear of the colliders of _cape_colliders and _cape_step (the rest skeleton, a margin more).
static func _cloak_rest_push(p: Vector3) -> Vector3:
	for s in [-1.0, 1.0]:
		p = _push_capsule(p, mx(P_SHOULDER, s), mx(P_ELBOW, s), CLOAK_UARM_R + 0.015)
		p = _push_capsule(p, mx(P_ELBOW, s), mx(P_WRIST, s) + GRIP, CLOAK_FARM_R + 0.015)
		p = _push_capsule(p, mx(P_HIP, s), mx(P_KNEE, s), CLOAK_THIGH_R + 0.015)
		p = _push_capsule(p, mx(P_KNEE, s), mx(P_ANKLE, s), CLOAK_SHIN_R + 0.015)
	var lc := p - P_CHEST
	if lc.y > -0.25 and lc.y < 0.3 and absf(lc.x) < 0.24:
		p.z = maxf(p.z, P_CHEST.z + 0.172 - 0.6 * lc.x * lc.x + 0.012)
	var lq := p - P_PELVIS
	if lq.y > -0.34 and lq.y < 0.07:
		var rmin := lerpf(0.235, 0.31, clampf((0.05 - lq.y) / 0.25, 0.0, 1.0)) + 0.015
		var r2 := Vector2(lq.x, lq.z)
		if r2.length() < rmin:
			r2 = r2.normalized() * rmin if r2.length() > 1e-4 else Vector2(0.0, rmin)
			p = P_PELVIS + Vector3(r2.x, lq.y, r2.y)
	return p


func _cape_setup(lion: bool) -> void:
	_cape_rest = cape_rest(lion)
	_cape_ca.clear()
	_cape_cb.clear()
	_cape_cl.clear()
	_cape_ck.clear()
	_cape_wa.clear()
	_cape_wb.clear()
	var nc := CAPE_NC
	for j in CAPE_NR:
		for i in nc:
			var k := j * nc + i
			if i + 1 < nc:
				_cape_con(k, k + 1, 1.0)
			if j + 1 < CAPE_NR:
				_cape_con(k, k + nc, 1.0)
				if i + 1 < nc:
					_cape_con(k, k + nc + 1, 0.6)
				if i > 0:
					_cape_con(k, k + nc - 1, 0.6)
			if i + 2 < nc:
				_cape_con(k, k + 2, 0.25)
			if j + 2 < CAPE_NR:
				_cape_con(k, k + 2 * nc, 0.3)
	# LOOK2: the pinned row rides on the bones under it, skinned like the mantle over it (the pelt's on the chest)
	_cape_pb.resize(CAPE_NC * 4)
	_cape_pw.resize(CAPE_NC * 4)
	for i in CAPE_NC:
		var w := PackedFloat32Array([float(CHEST), 1.0]) if lion else _mantle_w(_cape_rest[i])
		var tot := 0.0
		for m in range(1, w.size(), 2):
			tot += w[m]
		for m in 4:
			var on := m * 2 + 1 < w.size()
			_cape_pb[i * 4 + m] = int(w[m * 2]) if on else CHEST
			_cape_pw[i * 4 + m] = w[m * 2 + 1] / tot if on else 0.0
	_cape_pos.resize(0)


## LOOK2: the pinned row's bones and weights (4 a particle) and where it is this frame (world space).
var _cape_pb := PackedInt32Array()
var _cape_pw := PackedFloat32Array()
var _cape_pin := PackedVector3Array()
## LOOK2: the chest last frame (its yaw, its frame) and its turn rate (rad/s, peak held), for the carry in _cape_step.
var _cape_yaw := 0.0
var _cape_yaw_ok := false
var _cape_spin := 0.0
var _cape_chest := Transform3D()


func _cape_pins(gx: Transform3D) -> void:
	if _cape_pin.size() != CAPE_NC:
		_cape_pin.resize(CAPE_NC)
	for i in CAPE_NC:
		var q := Vector3.ZERO
		for m in 4:
			var w := _cape_pw[i * 4 + m]
			if w > 0.0:
				var b := _cape_pb[i * 4 + m]
				q += (_bx[b] * (_cape_rest[i] - _rest[b])) * w
		_cape_pin[i] = gx * q


func _cape_con(a: int, b: int, k: float) -> void:
	# (LOOK2: two pinned ends: nothing to keep; the share of each correction its two ends take, the stiffness folded in: a pinned
	# end takes none, its partner all of it)
	if a < CAPE_NC and b < CAPE_NC:
		return
	_cape_ca.append(a)
	_cape_cb.append(b)
	_cape_cl.append(_cape_rest[a].distance_to(_cape_rest[b]))
	_cape_ck.append(k)
	var fa := 0.0 if a < CAPE_NC else 1.0
	var fb := 0.0 if b < CAPE_NC else 1.0
	_cape_wa.append(k * fa / (fa + fb))
	_cape_wb.append(k * fb / (fa + fb))


## Colliders for the cape, world space: capsules [a, b, r].
## The cape's colliders this frame (world capsules a-b of radius r, plus each one's bounding sphere for a cheap
## early-out), written into packed arrays kept between frames (no allocation per frame).
var _cap_a := PackedVector3Array()
var _cap_b := PackedVector3Array()
var _cap_c := PackedVector3Array()
var _cap_r := PackedFloat32Array()
var _cap_rr := PackedFloat32Array()
var _cap_n := 0


func _cap_add(a: Vector3, b: Vector3, r: float) -> void:
	var i := _cap_n
	_cap_a[i] = a
	_cap_b[i] = b
	_cap_c[i] = (a + b) * 0.5
	var br := a.distance_to(b) * 0.5 + r
	_cap_rr[i] = br * br
	_cap_r[i] = r
	_cap_n += 1


func _cape_colliders(gx: Transform3D) -> void:
	var need := 14 + SKIRT_N
	if _cap_a.size() < need:
		_cap_a.resize(need)
		_cap_b.resize(need)
		_cap_c.resize(need)
		_cap_r.resize(need)
		_cap_rr.resize(need)
	_cap_n = 0
	# legs (inflated by about half the particle spacing, so a leg cannot slip between two particles)
	for o in 2:
		var k := o * 3
		_cap_add(gx * _bx[THIGH_R + k].origin, gx * _bx[SHIN_R + k].origin, CLOAK_THIGH_R)
		_cap_add(gx * _bx[SHIN_R + k].origin, gx * _bx[FOOT_R + k].origin, CLOAK_SHIN_R)
	# arms (LOOK2: the upper arm's capsule caps the deltoid, the forearm's reaches the fist)
	for o in 2:
		var k := o * 4
		var hb := _bx[HAND_R + k]
		_cap_add(gx * _bx[UARM_R + k].origin, gx * _bx[FARM_R + k].origin, CLOAK_UARM_R)
		_cap_add(gx * _bx[FARM_R + k].origin, gx * (hb.origin + hb.basis * GRIP), CLOAK_FARM_R)
	# hips and the skirt: a core plus a cage of hinge -> hem capsules
	_cap_add(gx * _carry(PELVIS, Vector3(-0.08, 0.95, 0.0)), gx * _carry(PELVIS, Vector3(0.08, 0.95, 0.0)), 0.215)
	_cap_add(gx * _carry(PELVIS, Vector3(-0.08, 0.8, 0.0)), gx * _carry(PELVIS, Vector3(0.08, 0.8, 0.0)), 0.2)
	for i in SKIRT_N:
		_cap_add(gx * _carry(PELVIS, _rest[SKIRT0 + i]), _sk_tip[i], 0.06)
	# helmet (and its flared neck guard) or the lion hood
	# (LOOK2: the bare head and its hair, the bare neck)
	var hc := gx * _carry(HEAD, HEAD_C + Vector3(0, 0.0, 0.02))
	_cap_add(hc, hc, 0.17 if not _show_lion else 0.27)
	var hn := gx * _carry(HEAD, HEAD_C + Vector3(0, -0.12, 0.07))
	_cap_add(hn, hn, 0.12 if not _show_lion else 0.21)
	# the blade (STOW: the whole of it, while it is in his hand) and the scabbard at his left hip (the cape drapes over it)
	if not _weapons_hidden() and _sw_at == AT_HAND:
		var sw := gx * _sw_xf
		_cap_add(sw * Vector3(0, 0, -0.1), sw * Vector3(0, 0, SWORD_TIP + 0.06), 0.04)
	if _scab_node != null:
		_cap_add(gx * (_scab_xf * Vector3(0.0, 0.0, SCAB_THROAT)), gx * (_scab_xf * Vector3(0.0, 0.0, SCAB_END + 0.03)), 0.05)


func _cape_step(dt: float, gx: Transform3D) -> void:
	var lion := _show_lion
	var want := &"lion" if lion else &"helmet"
	if _cape_outfit != want:
		_cape_outfit = want
		_cape_setup(lion)
	var n := _cape_rest.size()
	var chest := gx * _bx[CHEST]
	var chest_rest := _rest[CHEST]
	# LOOK2: the pinned row this frame (skinned: its ends ride on the shoulders)
	_cape_pins(gx)
	if _cape_pos.size() != n:
		_cape_pos.resize(n)
		_cape_prev.resize(n)
		for k in n:
			_cape_pos[k] = _cape_pin[k] if k < CAPE_NC else chest * (_cape_rest[k] - chest_rest)
			_cape_prev[k] = _cape_pos[k]
	_cape_colliders(gx)
	var ncap := _cap_n
	var use_caps := not dbg_off.has("caps")
	var use_chest := not dbg_off.has("chest")
	var use_cone := not dbg_off.has("cone")
	var use_spine := not dbg_off.has("spine")
	var use_shield := not dbg_off.has("shield") and not _weapons_hidden()
	var use_spear := not dbg_off.has("spear")
	var use_coil := not dbg_off.has("coil")
	var band_w := 0.1 if dbg_off.has("band") else 0.16
	var use_drape := not dbg_off.has("drape")
	# torso back plane (chest frame) and the spear slab
	var chest_inv := chest.affine_inverse()
	var pel := gx * _bx[PELVIS]
	var pel_inv := pel.affine_inverse()
	var spine := gx * _bx[SPINE]
	var spine_inv := spine.affine_inverse()
	var sp_on := spear_on_back and _spear_back.visible
	# the shield's disc (a slab in the shield frame), where the shield is (STOW: on the arm (the brush's ride up the arm included), in the
	# left fist, or hung on his back over the cape)
	var sh_xf := gx * _sh_xf
	var sh_back := _sh_at == AT_BACK
	var sh_inv := sh_xf.affine_inverse()
	var sp_xf := gx * blend_skin(SPINE, CHEST, 0.6, Vector3(0.0, 1.3, 0.25)) * _spear_back.transform
	var sp_inv := sp_xf.affine_inverse()
	var air := _air_velocity()
	var steps := clampi(int(ceil(dt / (1.0 / 60.0))), 1, 3) if dt > 0.0 else 0
	var h := dt / float(maxi(steps, 1))
	var h2 := h * h
	var g := Vector3(0, -9.8, 0)
	var ground := gx.origin.y + 0.03
	# the world behind him (CORE): a wall or a rock at his back is a plane the cloth stays in front of, and rising
	# ground behind (a slope uphill) lifts the floor the hem rests on
	_cape_world(gx)
	var wall_on := _wall_n != Vector3.ZERO
	var wall_p := _wall_p
	var wall_n := _wall_n
	var ground_back := maxf(ground, _ground_back + 0.03)
	var back_dir := (gx.basis * Vector3(0, 0, 1)).normalized()
	var origin := gx.origin
	# the spin of the heavy attack and the roll would wrap the cloak round an arm: it follows the body stiffly then
	# (LOOK2: the cloak holds its wide drape standing, and lets go of it to fly out behind him at a run)
	var shape_k := 3.0 if lion else CLOAK_SHAPE_K * lerpf(1.0, 0.3, smoothstep(1.5, 6.0, air.length()))
	if action != "" and _akey == "heavy":
		shape_k = 70.0 if action_t > 0.3 and action_t < 0.8 else 25.0
	elif action != "" and _akey == "dodge":
		shape_k = 25.0
	elif action != "" and _akey == "b3" and action_t > 0.12 and action_t < 0.6:
		# (INTEGRATE: the long lunge of b3: the cloak keeps its drape behind the shoulders instead of falling forward over the
		# outstretched sword arm)
		shape_k = 30.0
	# (LOOK2: and whenever his chest turns fast, whatever the action (a spinning blow, a quick turn), the big cloak is carried
	# round with it (its points and their last positions, so it keeps its own motion) instead of swinging round into a bell about
	# his legs: the chest's yaw rate, its peak held a moment)
	var yaw_c := atan2(chest.basis.z.x, chest.basis.z.z)
	if dt > 0.0 and _cape_yaw_ok:
		_cape_spin = maxf(absf(wrapf(yaw_c - _cape_yaw, -PI, PI)) / dt, _cape_spin - dt * 25.0)
		var carry := smoothstep(CLOAK_SPIN.x, CLOAK_SPIN.y, _cape_spin)
		if carry > 0.0:
			var dx := chest * _cape_chest.affine_inverse()
			for k in range(CAPE_NC, n):
				_cape_pos[k] = _cape_pos[k].lerp(dx * _cape_pos[k], carry)
				_cape_prev[k] = _cape_prev[k].lerp(dx * _cape_prev[k], carry)
	_cape_yaw = yaw_c
	_cape_chest = chest
	_cape_yaw_ok = true
	var swimming := motion_state == &"swim"
	var water_y := gx.origin.y + swim_waterline - 0.02
	# (INTEGRATE) the sword arm reaching ahead of the chest (b3's lunge, the thrusts, the cuts' follow-through): the cloth lying
	# on the upper arm slides off it to the back, so the cloak hangs behind the arm instead of over it like a sleeve
	var ua := gx * _bx[UARM_R].origin
	var uu := gx * _bx[FARM_R].origin - ua
	var ulen := uu.length()
	uu = uu / maxf(ulen, 1e-4)
	var cbk := chest.basis.z.normalized()
	var ub := cbk - uu * uu.dot(cbk)
	ub = ub.normalized() if ub.length_squared() > 1e-6 else cbk
	var arm_fwd := smoothstep(0.25, 0.65, -uu.dot(cbk)) if use_caps else 0.0
	for st in steps:
		for k in n:
			var j := k / CAPE_NC
			if j == 0:
				_cape_prev[k] = _cape_pos[k]
				_cape_pos[k] = _cape_pin[k]
				continue
			var p := _cape_pos[k]
			var vel := (p - _cape_prev[k]) / h
			var rel := air - vel
			var flut := Vector3(sin(t * 7.3 + float(k) * 0.71), sin(t * 5.1 + float(k) * 1.37) * 0.6, cos(t * 6.4 + float(k) * 0.93))
			var vrow := float(j) / float(CAPE_NR - 1)
			var acc := g + rel * (1.6 + 0.9 * vrow) + flut * (0.6 + rel.length() * 0.9) * vrow
			# a weak pull back to the draped shape (hanging from the shoulders in the chest frame) so the cloak
			# recovers after spins and rolls instead of staying wrapped over a shoulder; stronger mid-spin
			var drape := chest * (_cape_rest[k] - chest_rest)
			drape.y = minf(drape.y, p.y + 0.05)
			if use_drape:
				acc += (drape - p) * (shape_k * (1.0 - 0.5 * vrow))
			# afloat: cloth under the surface rises to it and stops sinking
			if swimming and p.y < water_y:
				acc.y += (water_y - p.y) * 60.0 - vel.y * 6.0
			_cape_prev[k] = p
			_cape_pos[k] = p + vel * h * 0.985 + acc * h2
		# (LOOK2: four passes, each correction shared out as _cape_con set it: the bigger cloak costs about what the old one did)
		var ncon := _cape_ca.size()
		for it in 4:
			for c in ncon:
				var a := _cape_ca[c]
				var b := _cape_cb[c]
				var pa := _cape_pos[a]
				var pb := _cape_pos[b]
				var dv := pb - pa
				var dl := dv.length()
				if dl < 1e-6:
					continue
				var f := (dl - _cape_cl[c]) / dl
				_cape_pos[a] = pa + dv * (f * _cape_wa[c])
				_cape_pos[b] = pb - dv * (f * _cape_wb[c])
			# the collisions: after the 2nd and the last pass of the constraints (cheaper than after every pass,
			# and the cloth always ends the step outside the body)
			if it != 1 and it != 3:
				continue
			for k in range(CAPE_NC, n):
				var p := _cape_pos[k]
				if use_caps:
					for ci in ncap:
						if p.distance_squared_to(_cap_c[ci]) < _cap_rr[ci]:
							p = _push_capsule(p, _cap_a[ci], _cap_b[ci], _cap_r[ci])
				# (INTEGRATE) off the forward sword arm, round its top to its back (a quarter of the way each pass)
				if arm_fwd > 0.0:
					var sa := (p - ua).dot(uu)
					if sa > 0.3 * ulen and sa < ulen + 0.06:
						var ax := ua + uu * sa
						var off := p - ax
						var dl := off.length()
						if dl > 1e-4 and dl < CLOAK_UARM_R + 0.04 and off.dot(ub) < 0.8 * dl:
							p = ax + (off / dl).slerp(ub, 0.25 * arm_fwd) * maxf(dl, CLOAK_UARM_R)
				# never inside the torso: stay behind the back surface of the cuirass
				var lc := chest_inv * p
				if lc.y > -0.25 and lc.y < 0.3 and absf(lc.x) < 0.24 and use_chest:
					var bz := 0.172 - 0.6 * lc.x * lc.x
					if lc.z < bz:
						lc.z = bz
						p = chest * lc
				# outside the skirt and its pteruges: a flared cone round the hips
				var lq := pel_inv * p
				if lq.y > -0.34 and lq.y < 0.07 and use_cone:
					var rmin := lerpf(0.235, 0.31, clampf((0.05 - lq.y) / 0.25, 0.0, 1.0))
					var r2 := Vector2(lq.x, lq.z)
					if r2.length() < rmin:
						r2 = r2.normalized() * rmin if r2.length() > 1e-4 else Vector2(0.0, rmin)
						p = pel * Vector3(r2.x, lq.y, r2.y)
				var ls := spine_inv * p
				if ls.y > -0.2 and ls.y < 0.12 and absf(ls.x) < 0.22 and use_spine:
					var bz2 := 0.17 - 0.6 * ls.x * ls.x
					if ls.z < bz2:
						ls.z = bz2
						p = spine * ls
				# out of the shield's slab (STOW: the shield on his back is over the cape: the cloth stays between his back and the shield.
				# LOOK2: the cloak hangs inside the shield on his arm: cloth in its slab, or up to CLOAK_SHIELD_OUT outside its face,
				# goes back to the body's side of it; the pelt goes to the nearer side)
				var qs := sh_inv * p
				if use_shield and Vector2(qs.x, qs.z).length() < SHIELD_R * 1.04:
					if sh_back:
						if qs.y > -0.05 and qs.y < 0.25:
							qs.y = -0.05
							p = sh_xf * qs
					elif qs.y > -0.06 and qs.y < (0.1 if lion else CLOAK_SHIELD_OUT):
						qs.y = 0.1 if (lion and qs.y >= 0.02) else -0.06
						p = sh_xf * qs
				# under the spear (it is strapped over the cape)
				if sp_on and use_spear:
					var q := sp_inv * p
					if q.z > -0.32 and q.z < 0.78:
						var band := absf(q.y)
						var coil := 1.0 if (q.z > 0.38 and q.z < 0.7 and use_coil) else 0.0
						var lim := -0.032 - 0.02 * coil + maxf(0.0, band - 0.06 - 0.03 * coil) * 1.4
						if band < band_w and q.x > lim:
							q.x = lim
							p = sp_xf * q
				# the floor: under the rig, or the rising ground behind him for cloth that hangs behind
				var gy := ground_back if (p - origin).dot(back_dir) > 0.12 else ground
				if p.y < gy:
					p.y = gy
				if wall_on:
					var dw := (p - wall_p).dot(wall_n) - 0.035
					if dw < 0.0:
						p -= wall_n * dw
				_cape_pos[k] = p
	_cape_pose(gx)


## A wall or rock behind the rig (world layer, two rays from the back at chest and hip height) and the ground
## height a little behind his heels; read by the cape. Nothing in tools without a world (no physics space).
var _wall_n := Vector3.ZERO
var _wall_p := Vector3.ZERO
var _ground_back := -INF
var _wall_q: PhysicsRayQueryParameters3D = null


func _cape_world(gx: Transform3D) -> void:
	_wall_n = Vector3.ZERO
	_ground_back = -INF
	if not is_inside_tree() or not cape_world:
		return
	var w := get_world_3d()
	if w == null:
		return
	var space := w.direct_space_state
	if space == null:
		return
	if _wall_q == null:
		_wall_q = PhysicsRayQueryParameters3D.new()
		_wall_q.collision_mask = 1
	var back := (gx.basis * Vector3(0, 0, 1)).normalized()
	var best := INF
	for h in [1.3, 0.75]:
		var from := gx * Vector3(0, h, 0.05)
		_wall_q.from = from
		_wall_q.to = from + back * 0.95
		var hit := space.intersect_ray(_wall_q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.dot(back) > -0.35 or absf(n.y) > 0.8:
			continue
		var d := from.distance_to(hit["position"])
		if d < best:
			best = d
			_wall_n = n
			_wall_p = hit["position"]
	# the ground 0.45 m behind his heels
	var foot := gx * Vector3(0, 0.9, 0.45)
	_wall_q.from = foot
	_wall_q.to = foot - Vector3(0, 1.6, 0)
	var g := space.intersect_ray(_wall_q)
	if not g.is_empty():
		_ground_back = (g["position"] as Vector3).y


## Bone frames of the cape particles (rig space) from their neighbours.
static func _cape_frame(pos: PackedVector3Array, i: int, j: int) -> Basis:
	var nc := CAPE_NC
	var l := pos[j * nc + maxi(i - 1, 0)]
	var r := pos[j * nc + mini(i + 1, nc - 1)]
	var up := pos[maxi(j - 1, 0) * nc + i]
	var dn := pos[mini(j + 1, CAPE_NR - 1) * nc + i]
	var x := (r - l)
	var v := (up - dn)
	if x.length_squared() < 1e-10:
		x = Vector3.RIGHT
	if v.length_squared() < 1e-10:
		v = Vector3.UP
	x = x.normalized()
	var z := x.cross(v)
	if z.length_squared() < 1e-10:
		z = Vector3.BACK
	z = z.normalized()
	return Basis(x, z.cross(x), z)


## Render mesh of the cape (lion=false) or the pelt, skinned to the CAPE_NC x CAPE_NR particle bones: [mesh, skin].
static func cape_mesh(lion: bool) -> Array:
	var key := "cape_%s" % lion
	if _cache.has(key):
		return _cache[key]
	var rest := cape_rest(lion)
	var frames: Array[Basis] = []
	for j in CAPE_NR:
		for i in CAPE_NC:
			frames.append(_cape_frame(rest, i, j))
	var sub_u := 2
	var sub_v := 2
	var gu_n := (CAPE_NC - 1) * sub_u + 1
	var gv_n := (CAPE_NR - 1) * sub_v + 1
	var th := 0.007
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var mb := MeshBuilder.new(91)
	# vertex grid (front layer then back layer), positions computed per (gu, gv)
	var grid: Array = [[], []]
	var binds: Array = []
	for layer in 2:
		for gv in gv_n:
			for gu in gu_n:
				var fu := float(gu) / float(sub_u)
				var fv := float(gv) / float(sub_v)
				var i0 := mini(int(floor(fu)), CAPE_NC - 2)
				var j0 := mini(int(floor(fv)), CAPE_NR - 2)
				var a := fu - float(i0)
				var b := fv - float(j0)
				var ks := [j0 * CAPE_NC + i0, j0 * CAPE_NC + i0 + 1, (j0 + 1) * CAPE_NC + i0, (j0 + 1) * CAPE_NC + i0 + 1]
				var ws := [(1.0 - a) * (1.0 - b), a * (1.0 - b), (1.0 - a) * b, a * b]
				var pos := Vector3.ZERO
				var nrm := Vector3.ZERO
				for q in 4:
					pos += rest[ks[q]] * float(ws[q])
					nrm += frames[ks[q]].z * float(ws[q])
				nrm = nrm.normalized()
				var u := float(gu) / float(gu_n - 1)
				var v := float(gv) / float(gv_n - 1)
				var pleat := sin(u * TAU * 3.0 + 0.4) * (0.006 + 0.014 * v)
				if lion:
					pleat = sin(u * TAU * 2.0) * 0.008 * v
				pos += nrm * (pleat + (th if layer == 0 else -th))
				grid[layer].append(pos)
				binds.append([ks, ws])
	var col_front := func(u: float, v: float) -> Color:
		if lion:
			# the mane continues from the hood over the shoulders (a ragged lower edge), then the golden coat with a
			# darker line down the spine, paler flanks, a dark ragged hem
			var mane_edge := 0.2 + 0.07 * absf(sin(u * PI * 5.0)) + 0.05 * (1.0 - absf(u * 2.0 - 1.0))
			if v < mane_edge:
				return MANE if int(floor(u * 12.0)) % 2 == 0 else MANE_DARK
			if v > 0.95:
				return FUR_DARK
			var cu := absf(u * 2.0 - 1.0)
			if cu < 0.16:
				return FUR_DARK
			if cu > 0.84:
				return FUR_LIGHT
			return FUR
		# LOOK: deep red, a darker hem
		if v > 0.95:
			return CAPE_DARK
		return CAPE
	var col_back := func(u: float, v: float) -> Color:
		if lion:
			return LEATHER_LIGHT if v > 0.12 else MANE_DARK
		return CAPE_DARK
	var tri := func(layer: int, i0: int, i1: int, i2: int, c: Color) -> void:
		var base := layer * gu_n * gv_n
		for idx in [base + i0, base + i2, base + i1]:
			verts.append(grid[layer][idx - base])
			cols.append(c)
			var bd: Array = binds[idx]
			for q in 4:
				bones.append(bd[0][q])
				wts.append(bd[1][q])
	for gv in gv_n - 1:
		for gu in gu_n - 1:
			var i00 := gv * gu_n + gu
			var i10 := i00 + 1
			var i01 := i00 + gu_n
			var i11 := i01 + 1
			var u := (float(gu) + 0.5) / float(gu_n - 1)
			var v := (float(gv) + 0.5) / float(gv_n - 1)
			# front faces +z (outwards): seen from behind, +x right and +y up -> counter-clockwise is (i00, i01, i11)
			var cf: Color = col_front.call(u, v)
			var cb: Color = col_back.call(u, v)
			tri.call(0, i00, i01, i11, cf)
			tri.call(0, i00, i11, i10, cf)
			tri.call(1, i00, i11, i01, cb)
			tri.call(1, i00, i10, i11, cb)
	# rim: left, right and bottom edges join the two layers
	var edge_pairs: Array = []
	for gv in gv_n - 1:
		edge_pairs.append([gv * gu_n, (gv + 1) * gu_n, true])
		edge_pairs.append([gv * gu_n + gu_n - 1, (gv + 1) * gu_n + gu_n - 1, false])
	for gu in gu_n - 1:
		edge_pairs.append([(gv_n - 1) * gu_n + gu, (gv_n - 1) * gu_n + gu + 1, true])
	var nv := gu_n * gv_n
	var rim_col := CAPE_DARK if not lion else MANE_DARK
	for e in edge_pairs:
		var i0: int = e[0]
		var i1: int = e[1]
		var flip: bool = e[2]
		var quad := [[0, i0], [0, i1], [1, i1], [1, i0]]
		if flip:
			quad = [[0, i1], [0, i0], [1, i0], [1, i1]]
		for tr in [[0, 1, 2], [0, 2, 3]]:
			for q in [tr[0], tr[2], tr[1]]:
				var lay: int = quad[q][0]
				var ii: int = quad[q][1]
				verts.append(grid[lay][ii])
				cols.append(rim_col)
				var bd: Array = binds[lay * nv + ii]
				for w in 4:
					bones.append(bd[0][w])
					wts.append(bd[1][w])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for k in range(0, verts.size(), 3):
		var nn := (verts[k + 2] - verts[k]).cross(verts[k + 1] - verts[k]).normalized()
		normals[k] = nn
		normals[k + 1] = nn
		normals[k + 2] = nn
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = MeshBuilder.smooth_normals(verts, normals, 60.0)
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = wts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skin := Skin.new()
	for k in rest.size():
		skin.add_bind(k, Transform3D(frames[k], rest[k]).affine_inverse())
	_cache[key] = [m, skin]
	return _cache[key]


func _cape_pose(gx: Transform3D) -> void:
	if cape_skel == null:
		return
	var inv := gx.affine_inverse()
	var local := PackedVector3Array()
	local.resize(_cape_pos.size())
	for k in _cape_pos.size():
		local[k] = inv * _cape_pos[k]
	for j in CAPE_NR:
		for i in CAPE_NC:
			var k := j * CAPE_NC + i
			cape_skel.set_bone_pose(k, Transform3D(_cape_frame(local, i, j), local[k]))


# --- tools ---------------------------------------------------------------------------------------------------

## Tools: pose the rig deterministically (pre-simulated with a fixed step from a settled idle) and freeze it.
## act = "" shows locomotion at `spd` (cycle position `phase`); otherwise the action at t_norm of its length.
func preview_pose(act: String, t_norm: float, spd: float, state: StringName, outfit_name: StringName, guard_on: bool, vy: float, phase: float, heading: float = 0.0, lunge: float = 0.0, armed: int = -1, ready_k: float = -1.0) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	# STOW: armed 1 / 0 puts the sword and the shield in the hands / away first (-1 leaves them as they are); ready_k the foe's nearness
	if armed >= 0:
		set_armed(armed == 1, true)
	if ready_k >= 0.0:
		alert = ready_k
		_alert = ready_k
	set_outfit(outfit_name)
	set_guard(guard_on)
	set_motion_state(state)
	set_vertical_speed(vy)
	var dt := 1.0 / 60.0
	var fwd := -(global_transform.basis.z if is_inside_tree() else Vector3.BACK)
	var rgt := global_transform.basis.x if is_inside_tree() else Vector3.RIGHT
	velocity_hint = (fwd * cos(heading) + rgt * sin(heading)) * spd
	set_locomotion(spd, 9.0)
	_spd = spd
	var pre := 1.6
	if act == "":
		# the gait starts at the phase that puts it at `phase` after the pre-roll (a steady speed, straight ahead)
		var kd := lerpf(1.0, 0.62, absf(sin(heading))) * lerpf(1.0, 0.75, clampf(-cos(heading), 0.0, 1.0))
		_pv_phase = fposmod(phase - _pl(spd, T_F) / kd * pre, 1.0)
		_swim_phase = phase
	var steps := int(pre / dt)
	for i in steps:
		advance(dt)
	if act != "":
		play(act)
		if lunge > 0.0:
			set_strike_run(false) # (a foe in reach: the hero stops and lunges, the blow plants its own feet, see HeroMelee)
		_blend_t = 1.0
		_io_pending = false
		_io_on = false
		var target := t_norm * action_len * 0.999
		# a blow's lunge (HeroMelee: LUNGE_T0 .. the first active frame, a sine ease-out) moves the node while the blow plays,
		# so that the feet of the blow are the ones the game shows; the node is put back for the picture
		var base := global_position
		var l_end := float(act_def(act)["ev"].get("swing", 0.12)) + 0.04
		var elapsed := 0.0
		while action_t + dt < target:
			elapsed += dt
			if lunge > 0.0:
				global_position = base + fwd * lunge * sin(clampf((elapsed - 0.02) / maxf(l_end - 0.02, 0.05), 0.0, 1.0) * PI * 0.5)
			advance(dt)
		var rest := maxf(target - action_t, 0.0)
		if lunge > 0.0:
			elapsed += rest
			global_position = base + fwd * lunge * sin(clampf((elapsed - 0.02) / maxf(l_end - 0.02, 0.05), 0.0, 1.0) * PI * 0.5)
		advance(rest)
		global_position = base


## &"helmet" or &"lion". Shown from the next frame; play("don_skin") makes the change itself, part-way through.
## (LOOK: &"helmet" is the default outfit's old name: bare-headed now, the cape and its mantle.)
func set_outfit(o: StringName) -> void:
	outfit = o


## The chain-spear strapped on the back (false while it flies on the chain or is stuck somewhere).
func set_spear_on_back(v: bool) -> void:
	spear_on_back = v


## CORE: the sword and the shield put aside (hidden: the hero lays them on the ground to wrestle bare-handed, as
## Heracles strangled the lion); false brings them back to the hands.
func set_weapons_aside(on: bool) -> void:
	weapons_aside = on
	_update_weapons()


## The weapons are hidden while laid aside, and through don_skin (the hands are busy with the pelt).
func _update_weapons() -> void:
	if _sword == null:
		return
	var hide := weapons_aside or _don_hide
	_sword.visible = not hide
	for mi in _shield_mi:
		mi.visible = not hide


func _weapons_hidden() -> bool:
	return weapons_aside or _don_hide


## Anime metal highlights on the bronze (Rig.set_metal in the live base class works on add_part materials).
func set_metal(k: float) -> void:
	_mat_metal.set_shader_parameter("metal", k)


## Every action play() accepts and its length in seconds (filled at construction from the definitions).
var ACTIONS := {}


## Names of the playable actions (outfit variants such as throw_lion are internal).
static func act_names() -> Array:
	if _acts.is_empty():
		_compile_actions()
	var out: Array = []
	for k in _acts.keys():
		if not String(k).ends_with("_lion"):
			out.append(k)
	return out


## tools/clip_check.gd: which part meshes must stay out of which part volumes.
func clip_pairs() -> Array:
	var out: Array = []
	for b in ["torso", "head", "hips", "leg_l", "leg_r"]:
		out.append(["sword", b])
		out.append(["shield", b])
	for b in ["head", "hips", "leg_l", "leg_r"]:
		out.append(["back_spear", b])
	return out


## tools/clip_check.gd: part-local ellipsoids [centre, radii] inscribed in the real body (the checker shrinks
## them by its tolerance): torso, head, hips under the kilt, thighs. Body pivots live in rest rig space.
func clip_volume(part: String) -> Array:
	match part:
		"torso":
			return [Vector3(0.0, 1.27, 0.0), Vector3(0.2, 0.25, 0.135)]
		"head":
			# LOOK: the bare head and its hair (HEAD_C relative)
			return [Vector3(0.0, -0.005, 0.012), Vector3(0.092, 0.14, 0.1)]
		"hips":
			return [Vector3(0.0, 0.9, 0.0), Vector3(0.19, 0.12, 0.16)]
		"leg_r":
			return [Vector3(0.116, 0.72, -0.01), Vector3(0.1, 0.24, 0.1)]
		"leg_l":
			return [Vector3(-0.116, 0.72, -0.01), Vector3(0.1, 0.24, 0.1)]
	return []


## World position of the wrestling hold (where the beast's neck should be during grapple_*).
func grapple_point() -> Vector3:
	return global_transform * GRAPPLE_HOLD if is_inside_tree() else transform * GRAPPLE_HOLD


# --- animation: the actions ----------------------------------------------------------------------------------

## Every action: len (s), in/out blend (s), events {name: t or [t, ...]}, keys [[t, {channel: value}]] where each
## key inherits the previous one and "ease" stops the motion at that key (anticipation holds, settles).
static func _action_defs() -> Dictionary:
	var d := {}
	var ready := {"hr": Vector3(0.3, -0.36, -0.2), "hrb": Vector3(0.0, -0.3, -1.0), "hrk": Vector3(1.0, 0.2, 0.0), "hrp": Vector3(0.5, 0.0, 1.0)}
	var neutral := NEUTRAL.duplicate()
	neutral.erase("rot")
	neutral.erase("piv")
	# attack1, attack2, attack3 and heavy are not keyed here: they are built from joint angles (STRIKE_NAMES, _strike_raw,
	# docs/ANIMATION.md section 4.8) and replace anything of those names in _compile_actions
	# parry: the shield punches forward (a bash). Played on the upper body (the legs and hips stay on the guard's gait): the shield
	# comes back to the chest and the chest winds away (anticipation, 4 frames), the punch turns the spine and the chest into it with
	# the shoulders leading, the arm carries a few centimetres past the contact (follow-through, in slow motion under the hit's slow
	# motion), the head holds on the target, then the arm comes back to the guard along a lower path (handover to the guard pose).
	d["parry"] = {"len": 0.5, "in": 0.05, "out": 0.12, "ho": 0.3, "ev": {"impact": 0.15, "step": [0.14, 0.45]}, "keys": [
		[0.0, {}],
		[0.06, {"ease": true, "hl": Vector3(-0.22, -0.05, -0.27), "hlf": Vector3(-0.35, 0.05, -1.0), "hlp": Vector3(-1.0, -0.5, 0.4),
			"chs": Vector3(0.05, -0.17, 0.0), "spn": Vector3(0.03, -0.09, 0.0), "nek": Vector3(-0.05, 0.16, 0.0), "hed": Vector3(0.0, 0.04, 0.0),
			"pel": Vector3(0.0, -0.07, 0.04), "hr": Vector3(0.46, -0.26, 0.06), "hrb": Vector3(0.55, 0.1, 0.83), "hrk": Vector3(0.75, 0.0, -0.65),
			"fl": Vector3(-0.15, 0.093, -0.06)}],
		[0.15, {"hl": Vector3(0.05, -0.03, -0.55), "hlf": Vector3(0.05, 0.05, -1.0), "hlp": Vector3(-1.0, -0.45, 0.35),
			"chs": Vector3(-0.05, 0.21, 0.0), "spn": Vector3(-0.13, 0.11, 0.0), "nek": Vector3(0.03, -0.20, 0.0), "hed": Vector3(0.0, -0.04, 0.0),
			"pel": Vector3(0.0, -0.10, -0.13), "hr": Vector3(0.5, -0.18, 0.08), "hrb": Vector3(0.6, 0.42, 0.68),
			"fl": Vector3(-0.16, 0.093, -0.3), "flr": Vector3(0.0, 0.12, 0.0)}],
		[0.22, {"hl": Vector3(0.07, -0.02, -0.58), "chs": Vector3(-0.06, 0.24, 0.0), "spn": Vector3(-0.14, 0.12, 0.0), "nek": Vector3(0.03, -0.22, 0.0)}],
		[0.34, {"ease": true, "hl": Vector3(-0.14, 0.02, -0.46), "hlf": Vector3(-0.06, 0.06, -1.0), "hlp": Vector3(-1.0, -0.7, 0.3),
			"chs": Vector3(-0.03, 0.14, 0.0), "spn": Vector3(-0.05, 0.0, 0.0), "nek": Vector3(-0.05, -0.10, 0.0), "hed": Vector3(0.0, 0.06, 0.0),
			"pel": Vector3(0.0, -0.08, 0.0), "hr": Vector3(0.42, -0.28, 0.06), "hrb": Vector3(0.48, -0.2, 0.85), "hrk": Vector3(0.75, 0.05, -0.65),
			"fl": Vector3(-0.17, 0.093, -0.12), "flr": Vector3(0.0, 0.18, 0.0)}],
		[0.5, {}],
	]}
	# dodge: a forward roll. The dive drops the hips and folds the spine over the thighs (anticipation, the blade swung down along
	# the leg so that it never leads the tumble), the tumble is one even turn of the whole body about a point under the chest (the
	# path is Hero.ROLL_PATH: its speed goes with these keys), the landing is a deep crouch with the arms out for balance, and the
	# rise leans into the next stride (the trunk and arms hand over to the locomotion from 0.5 s).
	# (the pivot is high enough that the crest and the spear on his back clear the ground at the bottom of the tumble)
	var rp := Vector3(0.0, 0.75, -0.18)
	# (the hands stay in the chest's own frame all through: in front of the chest they are at the knees as the trunk folds over them
	# and no flag changes the meaning of the numbers half way. The blade points out to the right, along the axis the body turns
	# about: it neither leads the tumble nor sweeps the ground)
	d["dodge"] = {"len": 0.62, "in": 0.05, "out": 0.12, "ho": 0.55, "dlen": 0.26, "ev": {"step": [0.06, 0.46]}, "keys": [
		[0.0, {"hrb": Vector3(0.15, 0.2, 0.95), "hrk": Vector3(1.0, 0.0, 0.1)}],
		[0.08, {"pel": Vector3(0.0, -0.22, -0.1), "spn": Vector3(-0.42, 0.0, 0.0), "chs": Vector3(-0.30, 0.0, 0.0), "nek": Vector3(-0.25, 0.0, 0.0),
			"hed": Vector3(0.08, 0.0, 0.0), "hr": Vector3(0.32, -0.30, -0.22), "hrp": Vector3(0.6, -0.2, 0.8),
			"hl": Vector3(-0.36, -0.22, -0.26), "hlf": Vector3(-1.0, 0.0, -0.1), "hlp": Vector3(-0.3, -0.3, 1.0),
			"fr": Vector3(0.14, 0.12, 0.10), "frr": Vector3(-0.4, -0.1, 0.0), "fl": Vector3(-0.14, 0.093, -0.1), "piv": rp}],
		[0.15, {"rot": Vector3(-1.0, 0.0, 0.0), "pel": Vector3(0.0, -0.4, -0.05), "pelr": Vector3(0.0, 0.5, 0.0), "spn": Vector3(-0.75, 0.0, 0.0),
			"chs": Vector3(-0.55, 0.0, 0.0), "nek": Vector3(-0.55, 0.0, 0.0), "fr": Vector3(0.13, 0.4, 0.05), "fl": Vector3(-0.13, 0.38, 0.08),
			"frr": Vector3(-0.7, 0.0, 0.0), "flr": Vector3(-0.7, 0.0, 0.0), "hl": Vector3(-0.34, -0.20, -0.40), "hlf": Vector3(-1.0, 0.0, 0.0),
			"hlp": Vector3(-1.0, 0.0, 0.0), "hr": Vector3(0.42, -0.2, -0.36), "hrp": Vector3(0.2, 0.7, 0.7)}],
		[0.25, {"rot": Vector3(-2.6, 0.0, 0.0), "hrb": Vector3(0.97, 0.2, 0.12)}],
		[0.35, {"rot": Vector3(-4.3, 0.0, 0.0), "hrb": Vector3(0.95, 0.0, -0.3)}],
		# the landing: a deep crouch, the arms out to the sides for balance, the blade forward again
		[0.45, {"rot": Vector3(-TAU, 0.0, 0.0), "pel": Vector3(0.0, -0.3, -0.02), "pelr": Vector3(0.0, 0.0, 0.0), "spn": Vector3(-0.38, 0.0, 0.0),
			"chs": Vector3(-0.2, 0.0, 0.0), "nek": Vector3(-0.1, 0.0, 0.0), "fr": Vector3(0.15, 0.093, 0.06), "fl": Vector3(-0.15, 0.093, -0.1),
			"frr": Vector3(0.0, -0.18, 0.0), "flr": Vector3(0.0, 0.18, 0.0), "hl": Vector3(-0.42, -0.26, -0.20), "hlf": Vector3(-1.0, 0.0, -0.3),
			"hlp": Vector3(-0.5, -0.2, 1.0), "hr": Vector3(0.42, -0.26, -0.20), "hrb": Vector3(0.62, -0.2, 0.76), "hrk": Vector3(0.6, 0.3, -0.7),
			"hrp": Vector3(0.5, 0.2, 0.9)}],
		# the rise: the trunk comes up leaning into the next stride, the hands settle at the sides
		[0.56, {"rot": Vector3(-TAU, 0.0, 0.0), "pel": Vector3(0.0, -0.16, -0.04), "spn": Vector3(-0.22, 0.0, 0.0), "chs": Vector3(-0.10, 0.0, 0.0),
			"nek": Vector3(-0.05, 0.0, 0.0), "hl": Vector3(-0.44, -0.30, -0.14), "hlf": Vector3(-1.0, 0.0, -0.35),
			"hlp": Vector3(-0.5, -0.2, 1.0), "hr": Vector3(0.4, -0.34, -0.1), "hrb": Vector3(0.38, -0.45, 0.8), "hrk": Vector3(0.7, 0.1, -0.7),
			"hrp": Vector3(0.5, 0.0, 1.0)}],
		[0.62, _merge(neutral, {"rot": Vector3(-TAU, 0.0, 0.0), "piv": rp, "pel": Vector3(0.0, -0.08, -0.02), "spn": Vector3(-0.08, 0.0, 0.0)})],
	]}
	# light hit: the blow lands on the chest (the pelvis and the trunk take it first, the head is thrown back a beat later: the 0.09 s
	# peak of the neck comes after the chest's), the arms fly out for balance, and the whole body comes back past upright and
	# settles. Turned to the direction the blow pushed (see _hit_dir_apply); on the move it is the upper body's only.
	d["hit"] = {"len": 0.38, "in": 0.05, "out": 0.12, "ho": 0.2, "ev": {}, "keys": [
		[0.0, {}],
		[0.04, {"spn": Vector3(0.07, 0.03, 0.0), "chs": Vector3(0.05, 0.04, 0.0), "nek": Vector3(0.08, 0.0, 0.0), "pel": Vector3(0.0, -0.05, 0.03),
			"pelr": Vector3(0.04, 0.0, 0.0), "hr": Vector3(0.38, -0.33, -0.03), "hl": Vector3(-0.32, -0.30, -0.14), "hlf": Vector3(-0.8, 0.1, -0.6)}],
		[0.09, {"spn": Vector3(0.15, 0.05, 0.03), "chs": Vector3(0.12, 0.08, 0.0), "nek": Vector3(0.24, 0.0, 0.0), "hed": Vector3(0.05, 0.0, 0.0),
			"pel": Vector3(0.0, -0.075, 0.065), "pelr": Vector3(0.07, 0.0, 0.0), "hr": Vector3(0.42, -0.27, 0.05), "hrb": Vector3(0.6, -0.25, 0.75),
			"hl": Vector3(-0.30, -0.18, -0.2), "hlf": Vector3(-0.6, 0.2, -0.8)}],
		[0.17, {"spn": Vector3(-0.05, 0.0, 0.0), "chs": Vector3(-0.04, 0.0, 0.0), "nek": Vector3(-0.10, 0.0, 0.0), "hed": Vector3(-0.02, 0.0, 0.0),
			"pel": Vector3(0.0, -0.05, 0.01), "pelr": Vector3(0.02, 0.0, 0.0), "hr": Vector3(0.36, -0.38, -0.08), "hl": Vector3(-0.34, -0.34, -0.1),
			"hlf": Vector3(-0.9, 0.05, -0.45)}],
		[0.28, {"spn": Vector3(0.01, 0.0, 0.0), "chs": Vector3(0.02, 0.0, 0.0), "nek": Vector3(-0.04, 0.0, 0.0), "hed": Vector3.ZERO, "pel": Vector3(0.0, -0.04, 0.0)}],
		[0.38, neutral],
	]}
	# heavy hit: the blow takes the whole body: the chest and the head are thrown back (the head a beat after), the arms fly wide, the
	# left foot is lifted off and comes down behind him (the stumble, 0.22 s) as the pelvis is driven back and down; the trunk folds
	# forward over it catching the balance (0.34 s), the right foot slides back (0.7 s), then he straightens, shield coming up.
	d["hit_heavy"] = {"len": 0.85, "in": 0.05, "out": 0.15, "ho": 0.58, "ev": {"step": [0.22, 0.7]}, "keys": [
		[0.0, {}],
		[0.05, {"spn": Vector3(0.14, 0.05, 0.03), "chs": Vector3(0.10, 0.05, 0.0), "nek": Vector3(0.14, 0.0, 0.0), "pel": Vector3(0.0, -0.05, 0.07),
			"pelr": Vector3(0.07, 0.0, 0.0), "hr": Vector3(0.46, -0.24, 0.08), "hrb": Vector3(0.4, 0.2, -0.8), "hl": Vector3(-0.46, -0.16, 0.05),
			"hlf": Vector3(-0.9, 0.2, -0.2)}],
		[0.11, {"spn": Vector3(0.32, 0.10, 0.05), "chs": Vector3(0.22, 0.10, 0.0), "nek": Vector3(0.34, 0.0, 0.0), "hed": Vector3(0.10, 0.0, 0.0),
			"pel": Vector3(0.0, -0.05, 0.15), "pelr": Vector3(0.12, 0.0, 0.0), "hr": Vector3(0.56, -0.05, 0.2), "hrb": Vector3(0.6, 0.4, -0.6),
			"hl": Vector3(-0.56, -0.05, 0.12), "hlf": Vector3(-0.9, 0.3, 0.2), "fl": Vector3(-0.15, 0.16, 0.05)}],
		[0.22, {"ease": true, "fl": Vector3(-0.16, 0.093, 0.3), "flr": Vector3(0.0, 0.18, 0.0), "pel": Vector3(0.0, -0.12, 0.22),
			"pelr": Vector3(0.08, 0.0, 0.0), "spn": Vector3(0.16, 0.0, 0.0), "chs": Vector3(0.08, 0.0, 0.0), "nek": Vector3(0.12, 0.0, 0.0),
			"hed": Vector3.ZERO, "hr": Vector3(0.50, -0.12, 0.12), "hl": Vector3(-0.50, -0.10, 0.06)}],
		[0.36, {"pel": Vector3(0.0, -0.20, 0.19), "pelr": Vector3(0.0, 0.0, 0.0), "spn": Vector3(-0.20, 0.0, 0.0), "chs": Vector3(-0.12, 0.0, 0.0),
			"nek": Vector3(0.12, 0.0, 0.0), "hed": Vector3(0.04, 0.0, 0.0), "hl": Vector3(-0.38, -0.33, -0.1), "hlf": Vector3(-1.0, 0.0, -0.3),
			"hr": Vector3(0.34, -0.36, -0.04), "hrb": Vector3(0.35, -0.45, 0.82), "hrk": Vector3(0.7, 0.1, -0.7), "hrp": Vector3(0.5, 0.0, 1.0)}],
		[0.54, {"pel": Vector3(0.0, -0.10, 0.10), "spn": Vector3(-0.05, 0.0, 0.0), "chs": Vector3(-0.02, 0.0, 0.0), "nek": Vector3(0.0, 0.0, 0.0),
			"fl": Vector3(-0.15, 0.13, 0.05), "fr": Vector3(0.15, 0.093, 0.1)}],
		[0.7, {"ease": true, "pel": Vector3(0.0, -0.05, 0.02), "fl": Vector3(-0.15, 0.093, 0.04), "fr": Vector3(0.15, 0.093, 0.04)}],
		[0.85, neutral],
	]}
	# death: the blow (the head and the chest recoil), the legs give, the sword hand opens and goes slack, down on the knees, the
	# trunk slumps over them, the head drops last, then he topples onto his right side (thud at 1.28 s, a small bounce), the arms
	# flop out. The last pose holds.
	var dp := Vector3(0.14, 0.07, 0.04)
	d["death"] = {"len": 1.8, "in": 0.06, "out": 0.3, "hold": true, "ev": {"step": [0.48], "thud": 1.28}, "keys": [
		[0.0, {"piv": dp}],
		[0.08, {"spn": Vector3(0.22, 0.0, 0.0), "chs": Vector3(0.14, 0.0, 0.0), "nek": Vector3(0.22, 0.0, 0.0), "pel": Vector3(0.0, -0.06, 0.08),
			"hr": Vector3(0.45, -0.25, 0.1), "hrb": Vector3(0.75, -0.12, 0.6), "hl": Vector3(-0.45, -0.25, 0.05)}],
		[0.24, {"spn": Vector3(0.10, 0.0, 0.0), "chs": Vector3(0.06, 0.0, 0.0), "nek": Vector3(0.30, 0.0, 0.0), "pel": Vector3(0.0, -0.20, 0.06),
			"fl": Vector3(-0.14, 0.12, 0.10), "hr": Vector3(0.38, -0.40, 0.0), "hrb": Vector3(0.45, -0.25, -0.85)}],
		[0.5, {"pel": Vector3(0.0, -0.405, 0.04), "pelr": Vector3(0.1, 0.0, 0.0), "spn": Vector3(-0.05, 0.0, 0.0), "chs": Vector3(-0.08, 0.0, 0.0),
			"nek": Vector3(0.15, 0.0, 0.0), "fr": Vector3(0.14, 0.2, 0.42), "frr": Vector3(-1.25, -0.05, 0.0), "fl": Vector3(-0.14, 0.2, 0.42),
			"flr": Vector3(-1.25, 0.05, 0.0), "hr": Vector3(0.33, -0.4, -0.16), "hrb": Vector3(0.34, -0.16, -0.92), "hl": Vector3(-0.33, -0.4, -0.1),
			"hlf": Vector3(-1.0, -0.2, -0.2)}],
		[0.85, {"spn": Vector3(-0.3, 0.0, 0.05), "chs": Vector3(-0.25, 0.0, 0.0), "nek": Vector3(0.38, 0.0, 0.1), "hr": Vector3(0.3, -0.42, -0.26),
			"hrb": Vector3(0.3, 0.1, -0.95)}],
		[1.3, {"rot": Vector3(0.0, 0.0, -1.3), "piv": Vector3(0.14, 0.26, 0.04), "spn": Vector3(-0.15, 0.0, -0.1), "chs": Vector3(0.0, 0.0, 0.1),
			"nek": Vector3(0.15, 0.0, 0.1), "hr": Vector3(0.3, 0.1, -0.45), "hrb": Vector3(0.2, 0.2, -1.0), "hrk": Vector3(1.0, 0.3, 0.0),
			"hrp": Vector3(0.3, -0.2, 1.0), "hl": Vector3(-0.4, -0.22, -0.12), "hlf": Vector3(-1.0, 0.2, 0.0), "hlp": Vector3(-0.6, -0.5, 0.6)}],
		[1.45, {"rot": Vector3(0.0, 0.0, -1.43), "hl": Vector3(-0.46, -0.18, -0.2), "hr": Vector3(0.34, 0.06, -0.5), "hrb": Vector3(0.11, 0.2, -1.0)}],
		[1.8, {"rot": Vector3(0.0, 0.0, -1.37), "hl": Vector3(-0.42, -0.24, -0.14), "hr": Vector3(0.3, 0.08, -0.46), "hrb": Vector3(0.2, 0.2, -1.0)}],
	]}
	# jump: leaves the ground with the push of the toes (pointed, trailing), the arms swing up and forward for the lift, the lead knee
	# comes up and the other leg trails: the rising air pose (_air_pose, k = 0), which this ends in
	var air_up := {"pel": Vector3(0.0, 0.03, 0.0), "pelr": Vector3(0.10, 0.0, 0.0), "spn": Vector3(-0.10, 0.0, 0.0), "chs": Vector3(0.02, 0.0, 0.0),
		"nek": Vector3(0.05, 0.0, 0.0), "hr": Vector3(0.62, 0.1, -0.2), "hrb": Vector3(0.55, -0.2, 0.8), "hrk": Vector3(0.2, 1.0, -0.3), "hrp": Vector3(0.6, -0.5, 0.8),
		"hl": Vector3(-0.62, 0.1, -0.2), "hlf": Vector3(-0.1, 1.0, 0.0), "hlp": Vector3(-0.6, -0.6, 0.8),
		"fr": Vector3(0.13, 0.42, -0.26), "frr": Vector3(-0.2, -0.1, 0.0), "fl": Vector3(-0.14, 0.26, 0.22), "flr": Vector3(-0.8, 0.1, 0.0)}
	d["jump"] = {"len": 0.28, "in": 0.05, "out": 0.12, "ho": 0.16, "ev": {"step": 0.0}, "keys": [
		[0.0, {"pel": Vector3(0.0, -0.10, 0.0), "spn": Vector3(-0.10, 0.0, 0.0), "hr": Vector3(0.36, -0.40, 0.0), "hrb": Vector3(0.3, -0.55, 0.78), "hrk": Vector3(0.7, 0.0, -0.7),
			"hl": Vector3(-0.36, -0.36, 0.02)}],
		[0.09, {"pel": Vector3(0.0, 0.04, 0.02), "spn": Vector3(0.02, 0.0, 0.0), "chs": Vector3(0.06, 0.0, 0.0), "nek": Vector3(0.0, 0.0, 0.0),
			"fr": Vector3(0.14, 0.14, 0.06), "frr": Vector3(-0.9, -0.1, 0.0), "fl": Vector3(-0.15, 0.12, 0.10), "flr": Vector3(-0.95, 0.1, 0.0),
			"hr": Vector3(0.46, 0.06, -0.26), "hrb": Vector3(0.5, -0.05, 0.86), "hrk": Vector3(0.3, 1.0, -0.2), "hl": Vector3(-0.44, 0.04, -0.24), "hlf": Vector3(-1.0, -0.1, -0.2)}],
		[0.28, air_up],
	]}
	# land: the ground met hard (the spring of _land_impact has the first give: this is the crouch he stays in a moment and the rise):
	# arms out for balance, the head bows then lifts, the rise overshoots upright a little
	d["land"] = {"len": 0.36, "in": 0.05, "out": 0.1, "ho": 0.22, "ev": {"step": 0.0}, "keys": [
		[0.0, {"fr": Vector3(0.15, 0.12, -0.06), "fl": Vector3(-0.15, 0.16, 0.08), "pel": Vector3(0.0, -0.10, 0.0), "hr": Vector3(0.5, -0.1, -0.1),
			"hrb": Vector3(0.55, -0.3, 0.78), "hrk": Vector3(0.6, 0.6, -0.5)}],
		[0.07, {"ease": true, "pel": Vector3(0.0, -0.26, 0.02), "pelr": Vector3(0.05, 0.0, 0.0), "spn": Vector3(-0.28, 0.0, 0.0), "chs": Vector3(-0.10, 0.0, 0.0),
			"nek": Vector3(0.18, 0.0, 0.0), "fr": Vector3(0.18, 0.093, 0.03), "frr": Vector3(0.0, -0.25, 0.0), "fl": Vector3(-0.17, 0.093, -0.08),
			"flr": Vector3(0.0, 0.25, 0.0), "hr": Vector3(0.52, -0.28, -0.06), "hrb": Vector3(0.55, -0.45, 0.7), "hrk": Vector3(0.6, 0.6, -0.5), "hl": Vector3(-0.50, -0.26, -0.06)}],
		[0.2, {"pel": Vector3(0.0, -0.10, 0.0), "spn": Vector3(-0.08, 0.0, 0.0), "chs": Vector3(0.02, 0.0, 0.0), "nek": Vector3.ZERO,
			"hr": Vector3(0.38, -0.38, -0.1), "hl": Vector3(-0.38, -0.34, -0.08)}],
		[0.36, neutral],
	]}
	_more_actions(d)
	_stow_actions(d) # STOW: draw, sheathe, draw_sword, draw_shield, sheathe_sword, sheathe_shield (and the throw over the shield)
	return d


## The spear throw (left hand): reach over the left shoulder for the shaft, raise it, whip it forward.
static func _throw_def(lion: bool, neutral: Dictionary, over: bool = false) -> Dictionary:
	var sp := spear_over_xf(lion) if over else spear_back_xf(lion)
	var sdir := -sp.basis.z
	var grab_cs := sp.origin + sdir * SPEAR_HOLD - P_CHEST
	var g_back := Vector3(-0.35, 0.45, -0.82)
	# palm up under the shaft: the fist sits inwards of the wrist, so the shaft passes clear of the shield
	var cock_b := Vector3(0.06, 0.12, -1.0)
	var cock_k := Vector3(0.0, -1.0, 0.0)
	var rel_b := Vector3(0.0, 0.06, -1.0)
	var rel_k := Vector3(0.0, -1.0, 0.0)
	# (half way to the grip: the hand's frame and the forearm's twist come round over the whole reach, not in its last frames)
	var mid_b := Vector3(0.0, 0.0, -1.0).slerp(sdir, 0.5)
	var mid_k := Vector3(-1.0, 0.0, 0.0).slerp(g_back.normalized(), 0.5)
	return {"len": 0.95, "in": 0.08, "out": 0.2, "fast": true, "ev": {"grab": THROW_GRAB, "release": THROW_RELEASE, "swing": 0.38, "step": [0.33, 0.8]}, "keys": [
		[0.0, {}],
		[0.10, {"hl": Vector3(-0.45, -0.22, -0.11), "hlf": Vector3(-1.0, 0.0, 0.0), "hlp": Vector3(-0.8, 0.0, -0.6), "nek": Vector3(-0.04, 0.1, 0.0),
			"hlb": mid_b, "hlk": mid_k, "hlx": 0.5}],
		[0.12, {"partial": true, "hr": Vector3(0.4, -0.3, -0.08), "hrb": Vector3(0.85, -0.12, -0.5)}],
		[THROW_GRAB, {"pel": Vector3(0.0, -0.05, 0.01), "pelr": Vector3(0.02, -0.06, 0.0), "spn": Vector3(0.0, 0.0, 0.0),
			"chs": Vector3(0.05, 0.0, 0.0), "nek": Vector3(-0.04, 0.16, 0.0), "hed": Vector3(0.0, 0.06, 0.0),
			"hl": _lw(grab_cs, sdir, g_back), "hlb": sdir, "hlk": g_back, "hlx": 1.0, "hlp": Vector3(-0.75, 0.25, -0.35),
			"hlf": Vector3(-1.0, 0.25, -0.1), "hr": Vector3(0.38, -0.3, -0.16), "hrb": Vector3(0.3, -0.2, -1.0),
			"fl": Vector3(-0.15, 0.093, 0.04), "fr": Vector3(0.16, 0.093, -0.04)}],
		# (the sword arm, held still until the grab, comes up to point at the target a little behind the rest: no start from nothing)
		[0.265, {"partial": true, "hrs": 0.40, "hr": Vector3(0.30, 0.38, -0.30), "hrb": Vector3(0.20, 0.0, -1.0)}],
		# cocked: torso wound to the left, the spear raised over the left shoulder pointing at the target, the
		# forearm upright (the shield stays edge-on beside the head, facing out and a little back: away from the spear that points forward
		# past it; the strap lets it turn that far from where the forearm is)
		[0.335, {"ease": true, "pel": Vector3(0.02, -0.08, 0.05), "pelr": Vector3(0.05, 0.2, 0.0), "spn": Vector3(0.08, 0.1, 0.04),
			"chs": Vector3(0.08, 0.14, 0.04), "nek": Vector3(-0.06, -0.28, 0.0), "hed": Vector3(0.0, -0.06, 0.0), "hls": 1.0,
			"hl": _lw(Vector3(-0.44, 1.86, 0.17), cock_b, cock_k), "hlb": cock_b, "hlk": cock_k, "hlr": 0.0, "hlp": Vector3(-0.6, -0.8, 0.0),
			"hlf": Vector3(-1.0, 0.0, 0.8), "hrs": 1.0, "hr": Vector3(0.2, 1.36, -0.52), "hrb": Vector3(0.0, 0.35, -1.0), "hrk": Vector3(1.0, 0.0, 0.2),
			"hrp": Vector3(0.8, -0.6, 0.2), "fr": Vector3(0.17, 0.093, -0.26), "frr": Vector3(0.0, -0.1, 0.0), "fl": Vector3(-0.16, 0.11, 0.14),
			"flr": Vector3(-0.2, 0.25, 0.0)}],
		# the whip: hips and chest unwind, the elbow leads forward past the head
		[0.395, {"pel": Vector3(0.0, -0.09, -0.03), "pelr": Vector3(0.0, -0.08, 0.0), "spn": Vector3(-0.04, -0.1, 0.0), "chs": Vector3(-0.04, -0.18, 0.0),
			"nek": Vector3(0.0, 0.08, 0.0), "hl": _lw(Vector3(-0.38, 1.84, -0.14), Vector3(0.02, 0.2, -1.0), rel_k),
			"hlb": Vector3(0.02, 0.2, -1.0), "hlk": rel_k, "hlp": Vector3(-0.6, 0.0, -1.0), "hlf": Vector3(-1.0, -0.1, 0.4),
			"hr": Vector3(0.3, 1.2, -0.3), "hrb": Vector3(0.2, 0.0, -1.0)}],
		[THROW_RELEASE, {"pel": Vector3(0.0, -0.1, -0.12), "pelr": Vector3(0.0, -0.18, 0.0), "spn": Vector3(-0.14, -0.2, 0.0),
			"chs": Vector3(-0.12, -0.32, 0.0), "nek": Vector3(0.08, 0.34, 0.0), "hl": _lw(Vector3(-0.16, 1.62, -0.58), rel_b, rel_k),
			"hlb": rel_b, "hlp": Vector3(-1.0, -0.4, 0.2), "hlf": Vector3(-1.0, -0.6, 0.4), "fl": Vector3(-0.15, 0.13, 0.08), "flr": Vector3(-0.55, 0.2, 0.0),
			"hr": Vector3(0.42, 1.06, 0.06), "hrb": Vector3(0.4, -0.3, -0.9), "hrp": Vector3(0.6, -0.5, 0.8)}],
		[0.6, {"pel": Vector3(0.0, -0.11, -0.14), "spn": Vector3(-0.2, -0.28, 0.0), "chs": Vector3(-0.12, -0.36, 0.0), "nek": Vector3(0.1, 0.4, 0.0),
			"hl": Vector3(0.04, 1.05, -0.56), "hlx": 0.0, "hlf": Vector3(-0.3, 0.2, -1.0), "hlp": Vector3(-0.6, -0.8, 0.2),
			"fl": Vector3(-0.15, 0.12, -0.02), "flr": Vector3(-0.3, 0.15, 0.0), "hr": Vector3(0.4, 1.0, 0.02)}],
		[0.72, {"ease": true, "pel": Vector3(0.0, -0.09, -0.1), "hl": Vector3(-0.04, 1.0, -0.46)}],
		[0.8, {"partial": true, "hrb": Vector3(0.85, -0.15, 0.5)}],
		[0.95, neutral],
	]}


## CORE: catching the spear as it flies home butt first: the left fist closes on the shaft in front of the chest
## (the spear pointing out along its flight), swings it up over the shoulder (the throw's cocked pose) and straps it
## on the back (the throw's grab pose, where the spear in the fist and the one on the back coincide: CATCH_STOW).
## Played on the upper body (Hero / ChainSpear), so the legs keep running.
static func _catch_def(lion: bool, neutral: Dictionary, over: bool = false) -> Dictionary:
	# (the fist meets the spear in the roll the guard hand already has: the reach does not turn the wrist over)
	var catch_k := Vector3(-1.0, -0.25, 0.0)
	var sp := spear_over_xf(lion) if over else spear_back_xf(lion)
	var sdir := -sp.basis.z
	var grab_cs := sp.origin + sdir * SPEAR_HOLD - P_CHEST
	var g_back := Vector3(-0.35, 0.45, -0.82)
	var cock_b := Vector3(0.06, 0.12, -1.0)
	var cock_k := Vector3(0.0, -1.0, 0.0)
	var rel_b := Vector3(0.0, 0.06, -1.0)
	var rel_k := Vector3(0.0, -1.0, 0.0)
	return {"len": 0.46, "in": 0.04, "out": 0.16, "ev": {}, "keys": [
		[0.0, {}],
		[0.08, {"chs": Vector3(-0.05, -0.12, 0.0), "nek": Vector3(0.04, 0.14, 0.0), "hls": 1.0,
			"hl": _lw(Vector3(-0.22, 1.5, -0.5), rel_b, catch_k), "hlb": rel_b, "hlk": catch_k, "hlx": 1.0, "hlr": 0.0,
			"hlp": Vector3(-1.0, -0.4, 0.2), "hlf": Vector3(-1.0, -0.6, 0.2)}],
		[0.16, {"ease": true, "chs": Vector3(0.06, 0.12, 0.04), "nek": Vector3(-0.04, -0.2, 0.0), "hls": 1.0,
			"hl": _lw(Vector3(-0.44, 1.86, 0.17), cock_b, cock_k), "hlb": cock_b, "hlk": cock_k, "hlx": 1.0,
			"hlp": Vector3(-0.6, -0.8, 0.0), "hlf": Vector3(-1.0, 0.0, 0.0)}],
		[CATCH_STOW, {"ease": true, "chs": Vector3(0.05, 0.0, 0.0), "nek": Vector3(-0.04, 0.16, 0.0), "hls": 0.0,
			"hl": _lw(grab_cs, sdir, g_back), "hlb": sdir, "hlk": g_back, "hlx": 1.0, "hlr": 1.0, "hlp": Vector3(-0.75, 0.25, -0.35),
			"hlf": Vector3(-1.0, 0.25, -0.1)}],
		# (the empty hand comes out to the side before it drops: never back down through the shoulder and the chest)
		[0.32, {"hl": Vector3(-0.58, 0.1, 0.04), "hlx": 0.0, "hlf": Vector3(-1.0, 0.1, 0.0), "hlp": Vector3(-0.8, -0.5, 0.3)}],
		[0.46, neutral],
	]}


## Spear, chain, wrestling, everyday and ceremony actions (added to _action_defs).
static func _more_actions(d: Dictionary) -> void:
	var neutral := NEUTRAL.duplicate()
	neutral.erase("rot")
	neutral.erase("piv")
	# --- throw: the left hand draws the spear from behind the left shoulder, cocks it, hurls it overhand ---
	for lion in [false, true]:
		d["throw_lion" if lion else "throw"] = _throw_def(lion, neutral)
		d["catch_lion" if lion else "catch"] = _catch_def(lion, neutral)
	# --- pull: both fists on the chain, a big haul leaning back, a braced hold, recover ---
	var ch_b := Vector3(0.0, 0.08, -1.0)
	var ch_k := Vector3(-1.0, 0.35, 0.0)
	d["pull"] = {"len": 0.8, "in": 0.06, "out": 0.22, "ev": {"pull": 0.24, "step": [0.26]}, "keys": [
		[0.0, {"hlr": 0.0}],
		[0.12, {"ease": true, "pel": Vector3(0.0, -0.08, -0.06), "pelr": Vector3(-0.04, 0.0, 0.0), "spn": Vector3(-0.15, 0.06, 0.0),
			"chs": Vector3(-0.06, 0.1, 0.0), "nek": Vector3(0.1, -0.1, 0.0), "hl": _lw(Vector3(-0.05, -0.04, -0.54), ch_b, ch_k),
			"hlb": ch_b, "hlk": ch_k, "hlx": 1.0, "hlp": Vector3(-1.0, -0.6, 0.2), "hlf": Vector3(-1.0, 0.1, 0.0),
			"hr": Vector3(0.34, -0.1, -0.36), "hrb": Vector3(0.62, -0.4, 0.68), "hrk": Vector3(0.8, 0.5, -0.2), "hrp": Vector3(1.0, -0.4, 0.3),
			"fl": Vector3(-0.16, 0.093, -0.24), "flr": Vector3(0.0, 0.15, 0.0), "fr": Vector3(0.16, 0.093, 0.12), "frr": Vector3(0.0, -0.25, 0.0)}],
		[0.3, {"pel": Vector3(0.0, -0.17, 0.17), "pelr": Vector3(0.16, 0.0, 0.0), "spn": Vector3(0.2, -0.05, 0.0), "chs": Vector3(0.12, -0.1, 0.0),
			"nek": Vector3(-0.18, 0.06, 0.0), "hl": _lw(Vector3(-0.08, -0.14, -0.34), ch_b, ch_k), "hr": Vector3(0.36, -0.24, -0.06),
			"hrb": Vector3(0.6, -0.15, 0.78), "fl": Vector3(-0.17, 0.093, -0.32), "fr": Vector3(0.18, 0.093, 0.3), "frr": Vector3(0.0, -0.3, 0.0)}],
		[0.5, {"ease": true, "pel": Vector3(0.0, -0.18, 0.19), "pelr": Vector3(0.19, 0.0, 0.0), "spn": Vector3(0.22, -0.03, 0.0)}],
		[0.8, neutral],
	]}
	# --- grapple: lunge in and lock the arms round the beast's neck (GRAPPLE_HOLD), strain in a loop, shove free ---
	var hold := {"pel": Vector3(0.0, -0.14, 0.07), "pelr": Vector3(-0.06, 0.0, 0.0), "spn": Vector3(-0.2, 0.0, 0.0),
		"chs": Vector3(-0.1, 0.0, 0.0), "nek": Vector3(0.14, 0.0, 0.0), "hed": Vector3(0.1, -0.35, 0.0),
		"fr": Vector3(0.22, 0.093, 0.18), "frr": Vector3(0.0, -0.3, 0.0), "fl": Vector3(-0.21, 0.093, -0.1), "flr": Vector3(0.0, 0.25, 0.0),
		"hrs": 1.0, "hrr": 0.0, "hr": Vector3(0.0, 1.46, -0.64), "hrb": Vector3(0.55, -0.6, -0.55), "hrk": Vector3(0.0, 1.0, -0.3), "hrp": Vector3(1.0, 0.4, 0.0),
		"hls": 1.0, "hl": Vector3(0.05, 0.9, -0.72), "hlf": Vector3(0.0, -0.6, -0.8), "hlp": Vector3(-1.0, -0.4, 0.0), "hlx": 0.0}
	d["grapple_start"] = {"len": 0.5, "in": 0.06, "out": 0.15, "ev": {"impact": 0.36, "step": [0.2]}, "keys": [
		[0.0, {"hrr": 0.0}],
		[0.16, {"pel": Vector3(0.0, -0.12, -0.05), "spn": Vector3(-0.22, 0.0, 0.0), "chs": Vector3(-0.08, 0.0, 0.0),
			"hr": Vector3(0.55, 0.02, -0.25), "hrb": Vector3(0.6, 0.3, 0.75), "hrk": Vector3(0.0, 1.0, 0.0), "hrp": Vector3(1.0, 0.2, 0.4),
			"hl": Vector3(-0.55, -0.02, -0.22), "hlf": Vector3(-0.5, -0.4, -0.7), "hlp": Vector3(-1.0, 0.2, 0.4),
			"fl": Vector3(-0.18, 0.15, -0.2), "flr": Vector3(0.2, 0.2, 0.0)}],
		[0.36, hold],
		[0.5, {"ease": true, "spn": Vector3(-0.23, 0.0, 0.0), "hr": Vector3(0.0, 1.45, -0.62)}],
	]}
	var sway_r := _merge(hold, {"pelr": Vector3(-0.06, -0.12, 0.06), "chs": Vector3(-0.1, -0.12, 0.05),
		"fr": Vector3(0.24, 0.1, 0.22), "hed": Vector3(0.12, -0.42, 0.0)})
	var squeeze := _merge(hold, {"spn": Vector3(-0.26, 0.0, 0.0), "chs": Vector3(-0.14, 0.0, 0.0), "pel": Vector3(0.0, -0.17, 0.08),
		"hr": Vector3(0.0, 1.44, -0.6), "hl": Vector3(0.05, 0.88, -0.68)})
	var sway_l := _merge(hold, {"pelr": Vector3(-0.06, 0.12, -0.06), "chs": Vector3(-0.1, 0.12, -0.05),
		"fl": Vector3(-0.23, 0.11, -0.15), "hed": Vector3(0.12, -0.28, 0.0)})
	d["grapple_loop"] = {"len": 1.6, "loop": true, "in": 0.1, "out": 0.15, "ev": {"strain": 0.8, "step": [0.42, 1.22]}, "keys": [
		[0.0, hold], [0.4, sway_r], [0.8, squeeze], [1.2, sway_l], [1.6, hold],
	]}
	d["grapple_end"] = {"len": 0.7, "in": 0.05, "out": 0.2, "ev": {"impact": 0.14, "step": [0.32, 0.6]}, "keys": [
		[0.0, hold],
		[0.14, {"pel": Vector3(0.0, -0.1, -0.04), "spn": Vector3(-0.1, 0.0, 0.0), "chs": Vector3(-0.04, 0.0, 0.0), "hed": Vector3(0.0, 0.0, 0.0),
			"hr": Vector3(0.27, 1.22, -0.64), "hrb": Vector3(0.2, 0.5, -0.85), "hrk": Vector3(1.0, 0.0, 0.0), "hl": Vector3(-0.24, 1.08, -0.6),
			"hlf": Vector3(0.0, 0.1, -1.0)}],
		[0.32, {"pel": Vector3(0.0, -0.1, 0.1), "spn": Vector3(0.04, 0.0, 0.0), "fl": Vector3(-0.16, 0.093, 0.2), "flr": Vector3(0.0, 0.18, 0.0),
			"hrs": 0.0, "hls": 0.0, "hr": Vector3(0.36, -0.3, -0.18), "hrb": Vector3(0.1, -0.2, -1.0), "hrk": Vector3(1.0, 0.1, 0.1),
			"hrp": Vector3(0.5, 0.0, 1.0), "hl": Vector3(-0.36, -0.3, -0.12), "hlf": Vector3(-1.0, 0.0, -0.4), "hlp": Vector3(-0.5, -0.2, 1.0)}],
		[0.7, neutral],
	]}
	# --- interact: reach out with the open left hand and press ---
	d["interact"] = {"len": 0.7, "in": 0.08, "out": 0.2, "ev": {"use": 0.3, "step": [0.28]}, "keys": [
		[0.0, {}],
		[0.16, {"ease": true, "pel": Vector3(0.0, -0.05, 0.02), "spn": Vector3(0.02, 0.06, 0.0), "chs": Vector3(0.05, 0.1, 0.0),
			"hl": Vector3(-0.2, -0.12, -0.3), "hlf": Vector3(-0.8, 0.1, -0.5), "hlp": Vector3(-0.8, -0.6, 0.2), "ohl": 1.0,
			"hlw": Vector3(0.0, 0.0, 0.0)}],
		[0.3, {"pel": Vector3(0.0, -0.08, -0.08), "spn": Vector3(-0.1, 0.1, 0.0), "chs": Vector3(-0.04, 0.16, 0.0), "nek": Vector3(0.06, -0.1, 0.0),
			"hl": Vector3(-0.1, -0.06, -0.54), "hlw": Vector3(0.9, 0.0, 0.0), "fl": Vector3(-0.16, 0.093, -0.2), "flr": Vector3(0.0, 0.15, 0.0)}],
		[0.46, {"ease": true, "hl": Vector3(-0.1, -0.06, -0.52)}],
		[0.7, neutral],
	]}
	# --- pet: kneel on the right knee, the open left hand strokes something small twice ---
	var kneel := {"pel": Vector3(0.0, -0.43, 0.06), "pelr": Vector3(0.08, 0.06, 0.0), "spn": Vector3(-0.22, 0.0, 0.0), "chs": Vector3(-0.1, 0.0, 0.0),
		"nek": Vector3(0.18, 0.0, 0.0), "hed": Vector3(0.14, 0.05, 0.0), "fl": Vector3(-0.15, 0.2, 0.42), "flr": Vector3(-1.25, 0.05, 0.0),
		"fr": Vector3(0.16, 0.093, -0.22), "frr": Vector3(0.0, -0.15, 0.0), "hls": 1.0, "hl": Vector3(-0.22, 0.4, -0.5), "ohl": 1.0,
		"hlf": Vector3(-1.0, 0.0, 0.0), "hlp": Vector3(-1.0, 0.5, 0.2), "hlw": Vector3(0.5, 0.0, 0.0),
		"hrs": 1.0, "hrr": 0.0, "hr": Vector3(0.24, 0.65, -0.28), "hrb": Vector3(0.3, -0.4, -0.85), "hrk": Vector3(1.0, 0.2, 0.0), "hrp": Vector3(0.8, 0.0, 1.0)}
	d["pet"] = {"len": 1.6, "in": 0.1, "out": 0.25, "ev": {"use": 0.52, "step": [0.34, 1.45]}, "keys": [
		[0.0, {}],
		[0.36, kneel],
		[0.56, {"hl": Vector3(-0.22, 0.37, -0.62)}],
		[0.76, {"hl": Vector3(-0.22, 0.4, -0.47)}],
		[0.96, {"hl": Vector3(-0.22, 0.37, -0.61)}],
		[1.14, {"ease": true, "hl": Vector3(-0.22, 0.41, -0.5)}],
		[1.6, neutral],
	]}
	# --- don_skin: crouch to the pelt, swing it over the shoulders, the right hand pulls the hood over the helmet
	# (following the hood's own hinge path), both hands knot the paws on the chest ---
	var up_b := Vector3(0.85, 0.45, 0.25)
	d["don_skin"] = {"len": 2.4, "in": 0.1, "out": 0.3, "ev": {"pelt": DON_SWAP, "hood": 1.34, "knot": DON_KNOT, "step": [0.3, 2.0]}, "keys": [
		[0.0, {"hood": 0.0}],
		[0.36, {"ease": true, "pel": Vector3(0.0, -0.3, 0.05), "pelr": Vector3(-0.05, 0.0, 0.0), "spn": Vector3(-0.42, 0.0, 0.0),
			"chs": Vector3(-0.2, 0.0, 0.0), "nek": Vector3(0.25, 0.0, 0.0), "hls": 1.0, "hl": Vector3(-0.3, 0.52, -0.42), "ohl": 1.0,
			"hlf": Vector3(-1.0, -0.2, 0.0), "hlp": Vector3(-1.0, 0.3, 0.3), "hrs": 1.0, "hr": Vector3(0.2, 0.52, -0.44),
			"hrb": Vector3(0.5, -0.3, 0.8), "hrk": Vector3(0.6, 0.8, 0.0), "hrp": Vector3(1.0, 0.3, 0.5),
			"fl": Vector3(-0.17, 0.093, 0.1), "fr": Vector3(0.17, 0.093, -0.14)}],
		[0.5, {"hrb": Vector3(1.0, 0.0, 0.25), "hrk": Vector3(0.0, 1.0, 0.0)}],
		[0.62, {"pel": Vector3(0.0, -0.06, 0.0), "pelr": Vector3(0.02, 0.0, 0.0), "spn": Vector3(0.04, 0.0, 0.0), "chs": Vector3(0.06, 0.0, 0.0),
			"nek": Vector3(0.0, 0.0, 0.0), "hls": 0.0, "hl": Vector3(-0.3, 0.1, -0.12), "ohl": 0.0, "hlf": Vector3(-1.0, 0.0, 0.0),
			"hlp": Vector3(-1.0, -0.4, 0.3), "hr": Vector3(0.34, 1.86, 0.12), "hrb": up_b, "hrk": Vector3(0.0, 1.0, 0.3), "hrp": Vector3(1.0, 0.0, -0.3)}],
		[DON_SWAP, {"hood": 0.45, "hl": Vector3(-0.14, 0.1, -0.24), "hlf": Vector3(-0.6, -0.3, -0.7), "hr": Vector3(0.15, 2.03, 0.42),
			"nek": Vector3(0.06, 0.0, 0.0)}],
		[1.05, {"hood": 0.7, "hr": Vector3(0.16, 2.08, 0.08)}],
		[1.22, {"hood": 0.9, "hr": Vector3(0.16, 1.92, -0.2), "nek": Vector3(0.14, 0.0, 0.0)}],
		[1.34, {"hood": 1.0, "hr": Vector3(0.17, 1.77, -0.31), "hrb": Vector3(0.9, 0.3, -0.1)}],
		[DON_KNOT, {"hl": Vector3(-0.36, -0.3, -0.1), "hrs": 0.0, "hr": Vector3(0.03, 0.09, -0.34), "hrb": Vector3(0.75, -0.3, 0.55),
			"hrk": Vector3(0.0, 1.0, 0.0), "hrp": Vector3(1.0, -0.4, 0.3), "hlf": Vector3(-1.0, 0.0, -0.35), "hlp": Vector3(-0.5, -0.2, 1.0),
			"nek": Vector3(0.12, 0.0, 0.0)}],
		[1.8, {"hr": Vector3(0.1, 0.06, -0.33)}],
		[2.05, {"ease": true, "chs": Vector3(0.14, 0.0, 0.0), "spn": Vector3(0.04, 0.0, 0.0), "nek": Vector3(-0.1, 0.0, 0.0),
			"hl": Vector3(-0.36, -0.3, -0.1), "hlf": Vector3(-1.0, 0.0, -0.35), "hlp": Vector3(-0.5, -0.2, 1.0),
			"hr": Vector3(0.36, -0.36, -0.12), "hrb": Vector3(0.12, -0.38, -1.0), "hrk": Vector3(1.0, 0.1, 0.15), "hrp": Vector3(0.5, 0.0, 1.0)}],
		[2.4, neutral],
	]}
	# --- victory: anticipation, the sword thrust to the sky, chest out, hold, settle ---
	d["victory"] = {"len": 2.2, "in": 0.1, "out": 0.3, "ev": {"raise": 0.62, "step": [0.6]}, "keys": [
		[0.0, {"hrr": 0.0}],
		[0.14, {"partial": true, "hr": Vector3(0.38, -0.34, -0.12), "hrb": Vector3(0.85, -0.22, -0.2)}],
		[0.3, {"ease": true, "pel": Vector3(0.0, -0.12, 0.0), "spn": Vector3(-0.12, 0.05, 0.0), "chs": Vector3(-0.02, 0.2, 0.0),
			"nek": Vector3(0.1, -0.15, 0.0), "hr": Vector3(0.3, -0.4, -0.22), "hrb": Vector3(0.25, -0.33, -0.91), "hrk": Vector3(0.3, 0.9, 0.0),
			"hrp": Vector3(1.0, -0.2, 0.3), "hl": Vector3(-0.38, -0.22, -0.14), "hlf": Vector3(-0.9, 0.0, -0.4)}],
		[0.62, {"pel": Vector3(0.0, 0.0, 0.0), "pelr": Vector3(0.04, 0.0, 0.0), "spn": Vector3(0.1, 0.0, 0.0), "chs": Vector3(0.16, -0.05, 0.0),
			"nek": Vector3(-0.16, 0.05, 0.0), "hed": Vector3(-0.14, 0.0, 0.0), "hr": Vector3(0.32, 0.6, -0.2), "hrb": Vector3(0.12, 1.0, -0.2),
			"hrk": Vector3(1.0, 0.0, 0.3), "hrp": Vector3(1.0, 0.1, 0.2), "hl": Vector3(-0.5, -0.04, -0.14), "hlf": Vector3(-0.85, 0.1, -0.5),
			"hlp": Vector3(-0.6, -0.8, 0.2), "fr": Vector3(0.2, 0.093, 0.02), "frr": Vector3(0.0, -0.25, 0.0), "fl": Vector3(-0.2, 0.093, -0.06),
			"flr": Vector3(0.0, 0.25, 0.0)}],
		[0.76, {"hr": Vector3(0.32, 0.63, -0.19)}],
		[1.6, {"ease": true, "hr": Vector3(0.32, 0.62, -0.2), "chs": Vector3(0.14, -0.05, 0.0)}],
		[2.2, neutral],
	]}
	_combat_actions(d, neutral)


## CORE: combat reactions the hero code needs beyond the brief's list.
##   recoil    the blade bounces off something it cannot cut (the Nemean Lion, a raised shield): the sword arm is
##             flung up and back, a step back, the guard comes back
##   backstep  the dodge without a direction: a quick hop back with the shield up
static func _combat_actions(d: Dictionary, neutral: Dictionary) -> void:
	# (INTEGRATE: the low trailing carry the actions end in, not the old fencer's point forward: a blade held forward at the end of a
	# key swung down through the ground into the carry, NEUTRAL)
	var ready := {"hr": Vector3(0.33, -0.42, -0.04), "hrb": Vector3(0.3, -0.6, 0.74), "hrk": Vector3(0.7, 0.05, -0.7), "hrp": Vector3(0.5, 0.0, 1.0)}
	d["recoil"] = {"len": 0.52, "in": 0.03, "out": 0.18, "ev": {"step": [0.08]}, "keys": [
		[0.0, {}],
		[0.1, {"hr": Vector3(0.52, 0.08, 0.02), "hrb": Vector3(0.7, 0.7, -0.15), "hrk": Vector3(0.6, -0.2, 0.75), "hrp": Vector3(0.8, -0.4, 0.4),
			"chs": Vector3(0.14, -0.22, 0.05), "spn": Vector3(0.1, -0.1, 0.0), "nek": Vector3(-0.12, 0.16, 0.0), "pel": Vector3(0.0, -0.06, 0.09),
			"pelr": Vector3(0.06, -0.08, 0.0), "fr": Vector3(0.17, 0.093, 0.2), "frr": Vector3(0.0, -0.22, 0.0), "fl": Vector3(-0.15, 0.12, -0.06),
			"flr": Vector3(-0.2, 0.18, 0.0), "hl": Vector3(-0.46, -0.12, 0.02), "hlf": Vector3(-1.0, 0.2, 0.2), "hlp": Vector3(-0.6, -0.5, 0.8)}],
		[0.22, {"ease": true, "hr": Vector3(0.5, 0.02, 0.0), "hrb": Vector3(0.75, 0.62, -0.2), "chs": Vector3(0.1, -0.18, 0.04),
			"fl": Vector3(-0.15, 0.093, -0.06), "flr": Vector3(0.0, 0.18, 0.0)}],
		[0.36, _merge({"chs": Vector3(0.04, -0.04, 0.0), "spn": Vector3(0.02, 0.0, 0.0), "nek": Vector3(-0.06, 0.04, 0.0), "pel": Vector3(0.0, -0.06, 0.05),
			"pelr": Vector3(0.02, 0.0, 0.0), "fr": Vector3(0.16, 0.093, 0.12), "frr": Vector3(0.0, -0.2, 0.0), "hl": Vector3(-0.36, -0.3, -0.1),
			"hlf": Vector3(-1.0, 0.0, -0.3), "hlp": Vector3(-0.5, -0.2, 1.0)}, ready)],
		[0.52, neutral],
	]}
	d["backstep"] = {"len": 0.5, "in": 0.03, "out": 0.15, "ev": {"step": [0.04, 0.29]}, "keys": [
		[0.0, {}],
		[0.06, {"pel": Vector3(0.0, -0.1, -0.04), "spn": Vector3(-0.08, 0.0, 0.0), "chs": Vector3(0.0, 0.0, 0.0),
			"hl": Vector3(-0.2, -0.12, -0.32), "hlf": Vector3(-0.3, 0.05, -1.0), "hlp": Vector3(-1.0, -0.6, 0.3)}],
		[0.13, {"pel": Vector3(0.0, 0.0, 0.07), "pelr": Vector3(0.1, 0.0, 0.0), "spn": Vector3(0.06, 0.0, 0.0), "chs": Vector3(0.04, 0.0, 0.0),
			"nek": Vector3(-0.06, 0.0, 0.0), "fr": Vector3(0.14, 0.2, 0.1), "frr": Vector3(-0.35, -0.1, 0.0), "fl": Vector3(-0.14, 0.26, -0.03),
			"flr": Vector3(-0.5, 0.1, 0.0), "hl": Vector3(0.0, -0.04, -0.42), "hlf": Vector3(0.1, 0.05, -1.0), "hlp": Vector3(-1.0, -0.7, 0.3),
			"hr": Vector3(0.36, -0.28, -0.12), "hrb": Vector3(0.1, 0.1, -1.0), "hrk": Vector3(1.0, 0.2, 0.1), "hrp": Vector3(0.6, -0.3, 1.0)}],
		[0.29, {"pel": Vector3(0.0, -0.13, 0.05), "pelr": Vector3(0.04, 0.0, 0.0), "spn": Vector3(-0.1, 0.0, 0.0), "chs": Vector3(-0.02, 0.0, 0.0),
			"nek": Vector3(0.08, 0.0, 0.0), "fr": Vector3(0.15, 0.093, 0.14), "frr": Vector3(0.0, -0.2, 0.0), "fl": Vector3(-0.15, 0.093, -0.05),
			"flr": Vector3(0.0, 0.18, 0.0)}],
		[0.37, {"ease": true, "pel": Vector3(0.0, -0.08, 0.03), "spn": Vector3(-0.04, 0.0, 0.0)}],
		[0.5, neutral],
	]}
	# climb: up and over a ledge from below its lip (the zip's end: Hero.MANTLE_DROP under the lip, the wall
	# Hero.MANTLE_STANDOFF in front). The hero moves the body along its path (Hero._tick_climb); the hands are given in
	# rig space so they stay on the lip while the body rises: reach (0), both hands on the lip (0.12), the press with
	# the chest over the edge and the right knee up (0.3), the right foot on the top (0.4), standing (0.5). The sword
	# stands up out of the right fist (never along the lip towards his chest), the shield faces out to the left.
	var up_blade := {"hrb": Vector3(0.3, 0.5, -0.8), "hrk": Vector3(1.0, 0.6, 0.0), "hrs": 1.0, "hls": 1.0, "hrr": 0.0}
	d["climb"] = {"len": 0.58, "in": 0.08, "out": 0.16, "ev": {"step": [0.38, 0.5]}, "keys": [
		[0.0, _merge({"hr": Vector3(0.3, 1.85, -0.4), "hl": Vector3(-0.3, 1.85, -0.4), "hrp": Vector3(1.0, -0.2, 0.4),
			"hlf": Vector3(-1.0, 0.1, 0.1), "hlp": Vector3(-1.0, -0.2, 0.4), "spn": Vector3(0.06, 0.0, 0.0), "chs": Vector3(0.04, 0.0, 0.0),
			"nek": Vector3(0.12, 0.0, 0.0), "fr": Vector3(0.12, 0.22, 0.06), "frr": Vector3(-0.3, -0.1, 0.0), "fl": Vector3(-0.12, 0.14, 0.1),
			"flr": Vector3(-0.2, 0.1, 0.0)}, up_blade)],
		[0.12, {"hr": Vector3(0.32, 1.09, -0.55), "hl": Vector3(-0.3, 1.09, -0.55), "spn": Vector3(-0.12, 0.0, 0.0),
			"chs": Vector3(-0.08, 0.0, 0.0), "nek": Vector3(0.2, 0.0, 0.0), "pel": Vector3(0.0, -0.04, 0.02),
			"fr": Vector3(0.13, 0.3, -0.16), "frr": Vector3(-0.2, -0.1, 0.0), "fl": Vector3(-0.12, 0.2, -0.1), "flr": Vector3(-0.1, 0.1, 0.0)}],
		[0.3, {"hr": Vector3(0.38, 0.38, -0.55), "hl": Vector3(-0.36, 0.38, -0.55), "pel": Vector3(0.0, -0.42, -0.08),
			"pelr": Vector3(-0.3, 0.0, 0.0), "spn": Vector3(-0.45, 0.0, 0.0), "chs": Vector3(-0.3, 0.0, 0.0), "nek": Vector3(0.38, 0.0, 0.0),
			"hed": Vector3(0.12, 0.0, 0.0), "hrp": Vector3(1.0, 0.4, 0.3), "hlp": Vector3(-1.0, 0.4, 0.3),
			"fr": Vector3(0.12, 0.45, -0.22), "frr": Vector3(-0.1, -0.1, 0.0), "frp": Vector3(0.05, 0.4, -1.0),
			"fl": Vector3(-0.12, 0.12, 0.12), "flr": Vector3(0.3, 0.1, 0.0), "flp": Vector3(-0.25, -0.3, -1.0)}],
		[0.4, {"hr": Vector3(0.36, 0.45, -0.45), "hl": Vector3(-0.34, 0.42, -0.42), "pel": Vector3(0.0, -0.32, -0.1),
			"pelr": Vector3(-0.2, 0.0, 0.0), "spn": Vector3(-0.3, 0.0, 0.0), "chs": Vector3(-0.15, 0.0, 0.0), "nek": Vector3(0.25, 0.0, 0.0),
			"hed": Vector3(0.05, 0.0, 0.0), "fr": Vector3(0.13, 0.093, -0.42), "frr": Vector3(0.0, -0.1, 0.0), "frp": Vector3(0.25, 0.2, -1.0),
			"fl": Vector3(-0.12, 0.3, 0.15), "flr": Vector3(0.4, 0.1, 0.0), "flp": Vector3(-0.25, -0.2, -1.0)}],
		[0.5, _merge({"pel": Vector3(0.0, -0.06, 0.0), "pelr": Vector3(0.0, 0.0, 0.0), "spn": Vector3(-0.04, 0.0, 0.0), "chs": Vector3(0.02, 0.0, 0.0),
			"nek": Vector3(0.0, 0.0, 0.0), "hed": Vector3.ZERO, "fr": Vector3(0.15, 0.093, -0.06), "frr": Vector3(0.0, -0.18, 0.0),
			"frp": Vector3(0.25, 0.0, -1.0), "fl": Vector3(-0.15, 0.093, 0.04), "flr": Vector3(0.0, 0.18, 0.0), "flp": Vector3(-0.25, 0.0, -1.0),
			"hl": Vector3(-0.36, -0.3, -0.1), "hlf": Vector3(-1.0, 0.0, -0.3), "hlp": Vector3(-0.5, -0.2, 1.0), "hls": 0.0, "hrs": 0.0},
			_merge(ready, {"hr": Vector3(0.39, -0.4, -0.08)}))],
		# (INTEGRATE: as he rises off the ledge the blade comes up and over at his right side into the trailing carry, high and clear
		# of his thigh while the fist passes it, instead of swinging down through his leg)
		[0.44, {"partial": true, "hrb": Vector3(0.45, 0.85, 0.25)}],
		[0.52, {"partial": true, "hrb": Vector3(0.6, -0.05, 0.8)}],
		[0.58, neutral],
	]}


# >>> STRIKES BEGIN (spliced by splice_strike.py from strike_block.gd.txt: edit that file, not this block)
# --- animation: the sword blows (docs/ANIMATION.md section 4) -----------------------------------------------------------
## attack1, attack2, attack3 and heavy are built from JOINT ANGLES (in degrees, as curves over the action's own seconds),
## not from hand positions: pelvis and chest turn in the world, the sword arm is a shoulder (plane of elevation, elevation,
## axial rotation), an elbow and a wrist (ulnar deviation, extension, forearm twist), so the hips lead and the shoulder, the
## elbow and the wrist follow one after the other (the kinetic chain), the hand travels on an arc, the blade stays where a
## wrist can hold it (never closer than 30 degrees to the forearm), and nothing pops. The shield arm is keyed where its wrist
## is, which way its elbow bends and where the shield faces, all in chest space (it travels with the chest: a disc whose rim
## reaches 0.2 m behind the elbow swings into the belly as soon as it is aimed in the world). `_bake_strike` samples the
## curves at 120 Hz into the ordinary pose arrays (sample_action plays them like any other action); the footwork
## (`_strike_feet`) is added while the action plays, because it depends on how far the hero lunges. The keys come from
## design/defs.py (see docs/ANIMATION.md 4.8): edit that, never the generated `_strike_raw` below.

## A smooth curve through keys [t0, v0, t1, v1, ...]: monotone cubic Hermite (never overshoots between two keys, a slope of
## zero at the ends and at every turning point, a flowing slope where the value keeps going the same way).
static func _kc(k: Array, t: float) -> float:
	var n := k.size() / 2
	if t <= float(k[0]):
		return float(k[1])
	if t >= float(k[2 * n - 2]):
		return float(k[2 * n - 1])
	var i := 0
	while i < n - 2 and t >= float(k[2 * i + 2]):
		i += 1
	var t0 := float(k[2 * i])
	var t1 := float(k[2 * i + 2])
	var v0 := float(k[2 * i + 1])
	var v1 := float(k[2 * i + 3])
	var h := t1 - t0
	var m0 := _kc_slope(k, i, n)
	var m1 := _kc_slope(k, i + 1, n)
	var u := (t - t0) / h
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * v0 + (u3 - 2.0 * u2 + u) * h * m0 + (-2.0 * u3 + 3.0 * u2) * v1 + (u3 - u2) * h * m1


static func _kc_slope(k: Array, j: int, n: int) -> float:
	if j <= 0 or j >= n - 1:
		return 0.0
	var h0 := float(k[2 * j]) - float(k[2 * j - 2])
	var h1 := float(k[2 * j + 2]) - float(k[2 * j])
	var d0 := (float(k[2 * j + 1]) - float(k[2 * j - 1])) / h0
	var d1 := (float(k[2 * j + 3]) - float(k[2 * j + 1])) / h1
	if d0 * d1 <= 0.0:
		return 0.0
	var w1 := 2.0 * h1 + h0
	var w2 := h1 + 2.0 * h0
	return (w1 + w2) / (w1 / d0 + w2 / d1)


static func _sv(S: Dictionary, key: String, t: float, d: float = 0.0) -> float:
	return _kc(S[key], t) if S.has(key) else d


## An arm from its joint angles (radians), in chest space. `az` the plane the upper arm is raised in (+ across the body,
## 0 forward), `e` its elevation from hanging (90 = horizontal), `r` its axial rotation (+ inward: with the arm forward the
## forearm bends towards the midline), `el` the elbow's flexion. side +1 right, -1 left. Returns [wrist, elbow pole,
## forearm direction, elbow, the elbow's hinge axis].
static func _arm_q(side: float, az: float, e: float, r: float, el: float) -> Array:
	var rb := Basis(Vector3.UP, az) * Basis(Vector3.RIGHT, e) * Basis(Vector3.UP, r)
	var u := rb * Vector3(0.0, -1.0, 0.0)
	var f := rb * Vector3(0.0, -cos(el), -sin(el))
	var s0 := Vector3(SHOULDER_CS.x, SHOULDER_CS.y, SHOULDER_CS.z)
	var el_p := s0 + u * LEN_UA
	var w := el_p + f * LEN_FA
	var pole := perp(el_p - s0, (w - s0).normalized())
	if pole.length_squared() < 4e-4:
		pole = rb * Vector3(0.0, 0.0, 1.0)
	pole = pole.normalized()
	var xl := rb * Vector3(1.0, 0.0, 0.0)
	if side < 0.0:
		return [mx(w, -1.0), mx(pole, -1.0), mx(f, -1.0), mx(el_p, -1.0), mx(xl, -1.0)]
	return [w, pole, f, el_p, xl]


## The sword hand from the forearm direction f (chest space), like _sword_hand but measured from the elbow's own hinge axis
## `xl` (the back of the hand lies along it at zero, so the wrist angles never jump when the arm turns): `uln` turns the
## blade towards the forearm's line (so the blade is 90 - uln degrees off it), `ext` extends the wrist (rolls the fist
## about the blade), `tw` twists the forearm (carries the blade round the forearm's axis). Returns [blade direction,
## back of the hand].
static func _sword_hand2(f: Vector3, xl: Vector3, uln: float, ext: float, tw: float) -> Array:
	var fn := f.normalized()
	var x_n := perp(xl, fn).normalized()
	var y_n := -fn
	var z_n := x_n.cross(y_n)
	var rot := Basis(fn, tw) * Basis(x_n, -uln) * Basis(z_n, ext)
	var h := rot * Basis(x_n, y_n, z_n)
	return [-h.z, h.x]


## Pose channels of strike `S` (raw definition) at action time t (s).
static func _strike_pose(S: Dictionary, t: float) -> PackedFloat32Array:
	var c := default_pose()
	var D := PI / 180.0
	# pelvis: yaw (+ left), pitch (+ back), roll (+ right side up) in the world, and where it sits
	var pb_v := Vector3(_sv(S, "pp", t, 1.1) * D, _sv(S, "py", t) * D, _sv(S, "pr", t) * D)
	var pb := eul(pb_v)
	set_ch(c, "pelr", pb_v)
	set_ch(c, "pel", Vector3(_sv(S, "px", t), NEUTRAL["pel"].y + _sv(S, "pdy", t), _sv(S, "pz", t)))
	# chest (absolute), shared between the spine (40 %) and the chest bone (60 %)
	var tb_v := Vector3(_sv(S, "cp", t, 4.0) * D, _sv(S, "cy", t) * D, _sv(S, "cr", t) * D)
	var tb := eul(tb_v)
	var q_rel := (pb.inverse() * tb).get_rotation_quaternion()
	var q_s := Quaternion.IDENTITY.slerp(q_rel, 0.4)
	var q_c := q_s.inverse() * q_rel
	set_ch(c, "spn", Basis(q_s).get_euler(EULER_ORDER_YXZ))
	set_ch(c, "chs", Basis(q_c).get_euler(EULER_ORDER_YXZ))
	# head (absolute): neck 55 %, head 45 % of the turn from the chest
	var hb := eul(Vector3(_sv(S, "hp", t) * D, _sv(S, "hy", t) * D, _sv(S, "hrl", t) * D))
	var q_h := (tb.inverse() * hb).get_rotation_quaternion()
	var q_n := Quaternion.IDENTITY.slerp(q_h, 0.55)
	set_ch(c, "nek", Basis(q_n).get_euler(EULER_ORDER_YXZ))
	set_ch(c, "hed", Basis(q_n.inverse() * q_h).get_euler(EULER_ORDER_YXZ))
	# sword arm
	var ra := _arm_q(1.0, _sv(S, "az", t) * D, _sv(S, "e", t, 10.0) * D, _sv(S, "r", t) * D, _sv(S, "el", t, 40.0) * D)
	var hand := _sword_hand2(ra[2], ra[4], _sv(S, "uln", t, 48.0) * D, _sv(S, "ext", t, 8.0) * D, _sv(S, "tw", t) * D)
	var hrb: Vector3 = hand[0]
	var hrk: Vector3 = hand[1]
	set_ch(c, "hrb", hrb)
	set_ch(c, "hrk", hrk)
	set_ch(c, "hr", (ra[0] as Vector3) + hand_basis(hrb, hrk, 1.0) * GRIP)
	set_ch(c, "hrp", ra[1])
	# shield arm (a counterweight and a guard): where its wrist is, which way its elbow bends and where the shield faces, all in
	# chest space (hl*, hp*, hf* curves), so it travels with the chest and never swings into it
	var hl := Vector3(_sv(S, "hlx", t, -0.335), _sv(S, "hly", t, -0.366), _sv(S, "hlz", t, -0.08))
	set_ch(c, "hl", hl)
	set_ch(c, "hlp", Vector3(_sv(S, "hpx", t, -0.5), _sv(S, "hpy", t, -0.2), _sv(S, "hpz", t, 1.0)))
	set_ch(c, "hlf", Vector3(_sv(S, "hfx", t, -1.0), _sv(S, "hfy", t, 0.0), _sv(S, "hfz", t, -0.35)))
	# the whole body turning about a vertical axis (the heavy's spin about the ball of the standing foot)
	var rot := _sv(S, "rot", t)
	if rot != 0.0:
		set_ch(c, "rot", Vector3(0.0, rot * D, 0.0))
		set_ch(c, "piv", Vector3(float(S.get("pivx", 0.0)), 0.9, float(S.get("pivz", 0.0))))
	# feet that are part of the pose (a blow whose feet are baked: ankle x, y, z, pitch, yaw relative to the rig; deg)
	for i in 2:
		var k := "f%d" % i
		if S.has(k + "x"):
			var ank := Vector3(_sv(S, k + "x", t), _sv(S, k + "y", t), _sv(S, k + "z", t))
			var o := C_FR if i == 0 else C_FL
			var yaw := _sv(S, k + "w", t) * D
			set_ch(c, "fr" if i == 0 else "fl", ank)
			set_ch(c, "frr" if i == 0 else "flr", Vector3(_sv(S, k + "p", t) * D, yaw, 0.0))
			set_ch(c, "frp" if i == 0 else "flp", Basis(Vector3.UP, yaw) * Vector3((1.0 if i == 0 else -1.0) * 0.12, 0.0, -1.0))
	return c


## Samples a strike's raw definition into the compiled action form (times, poses, Hermite tangents).
static func _bake_strike(S: Dictionary) -> Dictionary:
	var len: float = S["len"]
	var step := 1.0 / 120.0
	var n := int(ceil(len / step - 1e-6)) + 1
	var times := PackedFloat32Array()
	var poses: Array[PackedFloat32Array] = []
	for i in n:
		var t := minf(float(i) * step, len)
		times.append(t)
		poses.append(_strike_pose(S, t))
	var tans: Array[PackedFloat32Array] = []
	for i in n:
		var m := PackedFloat32Array()
		m.resize(C_N)
		if i > 0 and i < n - 1:
			var dt := times[i + 1] - times[i - 1]
			for j in C_N:
				m[j] = (poses[i + 1][j] - poses[i - 1][j]) / maxf(dt, 1e-4)
		tans.append(m)
	return {"len": len, "loop": false, "hold": false, "in": float(S["in"]), "out": float(S["out"]), "ev": S["ev"],
		"times": times, "poses": poses, "tans": tans, "strike": S}


## The raw definitions: curves [t, value, ...] per joint, in degrees and metres (see _strike_pose for the names).
## GENERATED by design/*.py (docs/ANIMATION.md section 4.8): the key poses were solved for the blade's path, the timings
## set so the joints peak in the order of the kinetic chain.
static func _strike_raw(nm: String) -> Dictionary:
	match nm:
		"a1":
			return {"len": 0.6, "in": 0.07, "out": 0.22, "ev": {"swing": 0.13, "impact": 0.175, "step": [0.17, 0.56]},
				"py": [0.0, 0.0, 0.11, -16.0, 0.13, -17.0, 0.165, 10.0, 0.2, 24.0, 0.3, 32.0, 0.42, 20.0, 0.6, 0.0],
				"cy": [0.0, 0.0, 0.11, -40.0, 0.135, -42.0, 0.18, 22.0, 0.21, 42.0, 0.3, 58.0, 0.42, 34.0, 0.6, 0.0],
				"pp": [0.0, 1.1, 0.12, 4.0, 0.18, -6.0, 0.3, -6.0, 0.45, -1.0, 0.6, 1.1],
				"cp": [0.0, 4.0, 0.11, 10.0, 0.135, 10.0, 0.19, -14.0, 0.3, -20.0, 0.42, -10.0, 0.6, 4.0],
				"cr": [0.0, 0.0, 0.11, 7.0, 0.135, 7.0, 0.19, -6.0, 0.32, -9.0, 0.45, -3.0, 0.6, 0.0],
				"pr": [0.0, 0.0, 0.12, 3.0, 0.19, -4.0, 0.32, -4.0, 0.6, 0.0],
				"px": [0.0, 0.0, 0.12, 0.04, 0.19, -0.04, 0.32, -0.06, 0.46, -0.02, 0.6, 0.0],
				"pz": [0.0, 0.0, 0.12, 0.05, 0.135, 0.05, 0.19, -0.14, 0.32, -0.18, 0.46, -0.07, 0.6, 0.0],
				"pdy": [0.0, 0.0, 0.12, -0.04, 0.135, -0.05, 0.19, -0.12, 0.32, -0.15, 0.46, -0.05, 0.6, 0.0],
				"hy": [0.0, 0.0, 0.12, -6.0, 0.17, -2.0, 0.21, 6.0, 0.32, 14.0, 0.46, 6.0, 0.6, 0.0],
				"hp": [0.0, 0.0, 0.12, 2.0, 0.21, -6.0, 0.32, -8.0, 0.6, 0.0],
				"hlx": [0.0, -0.335, 0.12, -0.42, 0.14, -0.42, 0.21, -0.2, 0.34, -0.2, 0.5, -0.335, 0.6, -0.335],
				"hly": [0.0, -0.366, 0.12, -0.14, 0.14, -0.14, 0.21, -0.2, 0.34, -0.2, 0.5, -0.366, 0.6, -0.366],
				"hlz": [0.0, -0.08, 0.12, -0.1, 0.14, -0.1, 0.21, -0.3, 0.34, -0.3, 0.5, -0.08, 0.6, -0.08],
				"hpx": [0.0, -0.5, 0.12, -0.6, 0.14, -0.6, 0.21, -0.8, 0.34, -0.8, 0.5, -0.5, 0.6, -0.5],
				"hpy": [0.0, -0.2, 0.12, -0.6, 0.14, -0.6, 0.21, -0.5, 0.34, -0.5, 0.5, -0.2, 0.6, -0.2],
				"hpz": [0.0, 1.0, 0.12, 0.5, 0.14, 0.5, 0.21, 0.5, 0.34, 0.5, 0.5, 1.0, 0.6, 1.0],
				"hfx": [0.0, -1.0, 0.12, -0.85, 0.14, -0.85, 0.21, -0.45, 0.34, -0.45, 0.5, -1.0, 0.6, -1.0],
				"hfy": [0.0, 0.0, 0.12, 0.1, 0.14, 0.1, 0.21, 0.1, 0.34, 0.1, 0.5, 0.0, 0.6, 0.0],
				"hfz": [0.0, -0.35, 0.12, -0.5, 0.14, -0.5, 0.21, -0.9, 0.34, -0.9, 0.5, -0.35, 0.6, -0.35],
				"az": [0.0, -83.19, 0.017, -85.79, 0.033, -91.23, 0.05, -95.95, 0.06, -96.97, 0.067, -89.24, 0.083, -73.59, 0.1, -63.14, 0.117, -57.92, 0.125, -57.27, 0.133, -54.24, 0.14, -55.19, 0.15, -55.72, 0.167, -49.43, 0.18, -17.08, 0.183, -16.25, 0.2, -17.46, 0.21, -17.36, 0.217, -17.76, 0.233, -18.16, 0.235, -18.09, 0.25, -21.1, 0.267, -32.19, 0.283, -46.87, 0.3, -58.36, 0.31, -61.56, 0.317, -61.81, 0.333, -64.26, 0.35, -68.55, 0.367, -73.73, 0.383, -78.8, 0.4, -82.81, 0.417, -84.77, 0.42, -84.84, 0.433, -82.61, 0.45, -75.1, 0.467, -65.01, 0.483, -55.21, 0.5, -48.55, 0.51, -47.27, 0.517, -47.81, 0.533, -53.06, 0.55, -61.75, 0.567, -71.24, 0.583, -78.87, 0.6, -86.29],
				"e": [0.0, 18.66, 0.017, 18.54, 0.033, 18.27, 0.05, 18.04, 0.06, 17.99, 0.067, 28.66, 0.083, 50.28, 0.1, 64.71, 0.117, 71.92, 0.125, 72.82, 0.133, 72.66, 0.14, 73.18, 0.15, 75.37, 0.167, 71.98, 0.18, 45.79, 0.183, 44.89, 0.2, 38.48, 0.21, 38.67, 0.217, 37.92, 0.233, 37.91, 0.235, 38.05, 0.25, 35.75, 0.267, 29.9, 0.283, 25.24, 0.3, 23.09, 0.31, 22.62, 0.317, 22.55, 0.333, 21.81, 0.35, 20.51, 0.367, 18.95, 0.383, 17.41, 0.4, 16.2, 0.417, 15.61, 0.42, 15.59, 0.433, 15.99, 0.45, 17.34, 0.467, 19.16, 0.483, 20.92, 0.5, 22.12, 0.51, 22.35, 0.517, 22.28, 0.533, 21.62, 0.55, 20.54, 0.567, 19.35, 0.583, 18.39, 0.6, 18.9],
				"r": [0.0, -95.07, 0.017, -70.11, 0.033, -17.95, 0.05, 27.44, 0.06, 37.24, 0.067, 32.7, 0.083, 23.5, 0.1, 17.37, 0.117, 14.3, 0.125, 13.92, 0.133, 16.24, 0.14, 16.87, 0.15, 15.22, 0.167, 28.44, 0.18, 34.69, 0.183, 37.18, 0.2, 49.19, 0.21, 48.62, 0.217, 49.63, 0.233, 48.22, 0.235, 47.63, 0.25, 46.96, 0.267, 59.62, 0.283, 78.08, 0.3, 93.61, 0.31, 98.19, 0.317, 98.22, 0.333, 98.49, 0.35, 98.97, 0.367, 99.54, 0.383, 100.11, 0.4, 100.55, 0.417, 100.77, 0.42, 100.78, 0.433, 89.35, 0.45, 50.82, 0.467, -0.92, 0.483, -51.17, 0.5, -85.29, 0.51, -91.9, 0.517, -91.95, 0.533, -92.42, 0.55, -93.19, 0.567, -94.04, 0.583, -94.72, 0.6, -95.09],
				"el": [0.0, 21.68, 0.017, 29.4, 0.033, 45.53, 0.05, 59.56, 0.06, 62.59, 0.067, 73.3, 0.083, 94.97, 0.1, 109.44, 0.117, 116.67, 0.125, 117.57, 0.133, 117.68, 0.14, 117.69, 0.15, 115.22, 0.167, 97.58, 0.18, 58.97, 0.183, 55.03, 0.2, 50.3, 0.21, 48.34, 0.217, 48.88, 0.233, 48.83, 0.235, 48.69, 0.25, 53.29, 0.267, 65.42, 0.283, 78.64, 0.3, 88.18, 0.31, 90.82, 0.317, 90.69, 0.333, 89.33, 0.35, 86.95, 0.367, 84.09, 0.383, 81.28, 0.4, 79.07, 0.417, 77.98, 0.42, 77.94, 0.433, 73.77, 0.45, 59.69, 0.467, 40.79, 0.483, 22.43, 0.5, 9.96, 0.51, 7.55, 0.517, 7.78, 0.533, 9.96, 0.55, 13.58, 0.567, 17.52, 0.583, 20.7, 0.6, 19.67],
				"uln": [0.0, 59.52, 0.017, 50.69, 0.033, 32.25, 0.05, 16.21, 0.06, 12.74, 0.067, 10.61, 0.083, 6.3, 0.1, 3.42, 0.117, 1.98, 0.125, 1.8, 0.133, 1.8, 0.14, 1.83, 0.15, 9.68, 0.167, 30.53, 0.18, 55.32, 0.183, 57.02, 0.2, 58.94, 0.21, 59.57, 0.217, 59.66, 0.233, 59.8, 0.235, 59.81, 0.25, 59.93, 0.267, 60.05, 0.283, 60.19, 0.3, 60.25, 0.31, 60.2, 0.317, 60.09, 0.333, 59.04, 0.35, 57.19, 0.367, 54.96, 0.383, 52.78, 0.4, 51.05, 0.417, 50.2, 0.42, 50.18, 0.433, 50.28, 0.45, 50.62, 0.467, 51.09, 0.483, 51.54, 0.5, 51.84, 0.51, 51.9, 0.517, 52.02, 0.533, 53.17, 0.55, 55.07, 0.567, 57.14, 0.583, 58.81, 0.6, 58.43],
				"ext": [0.0, 60.03, 0.017, 37.09, 0.033, -10.84, 0.05, -52.55, 0.06, -61.56, 0.067, -37.88, 0.083, 10.08, 0.1, 42.07, 0.117, 58.06, 0.125, 60.06, 0.133, 60.19, 0.14, 60.2, 0.15, 60.24, 0.167, 60.15, 0.18, 48.39, 0.183, 43.3, 0.2, 25.33, 0.21, 22.2, 0.217, 20.42, 0.233, 19.02, 0.235, 19.25, 0.25, 23.8, 0.267, 29.84, 0.283, 39.94, 0.3, 50.88, 0.31, 55.68, 0.317, 55.73, 0.333, 56.22, 0.35, 57.08, 0.367, 58.12, 0.383, 59.14, 0.4, 59.94, 0.417, 60.34, 0.42, 60.35, 0.433, 60.37, 0.45, 60.43, 0.467, 60.52, 0.483, 60.6, 0.5, 60.66, 0.51, 60.67, 0.517, 60.66, 0.533, 60.56, 0.55, 60.39, 0.567, 60.21, 0.583, 60.06, 0.6, 59.92],
				"tw": [0.0, -20.62, 0.017, 2.75, 0.033, 51.58, 0.05, 94.07, 0.06, 103.24, 0.067, 103.76, 0.083, 104.8, 0.1, 105.5, 0.117, 105.85, 0.125, 105.89, 0.133, 105.79, 0.14, 105.5, 0.15, 103.39, 0.167, 110.13, 0.18, 110.74, 0.183, 110.8, 0.2, 111.38, 0.21, 111.38, 0.217, 111.5, 0.233, 111.58, 0.235, 111.57, 0.25, 111.57, 0.267, 111.68, 0.283, 111.67, 0.3, 111.63, 0.31, 111.64, 0.317, 111.64, 0.333, 111.69, 0.35, 111.77, 0.367, 111.87, 0.383, 111.96, 0.4, 112.04, 0.417, 112.07, 0.42, 112.07, 0.433, 104.52, 0.45, 79.07, 0.467, 44.88, 0.483, 11.68, 0.5, -10.86, 0.51, -15.23, 0.517, -15.3, 0.533, -16.02, 0.55, -17.22, 0.567, -18.52, 0.583, -19.57, 0.6, -23.92],
				"feet": {"moves": [{"f": 1, "t0": 0.04, "t1": 0.17, "x": -0.18, "z": -0.44, "yaw": 8.0, "apex": 0.1, "th": 12.0}, {"f": 1, "t0": 0.44, "t1": 0.58, "x": -0.15, "z": -0.08, "yaw": 4.0, "apex": 0.07, "th": 6.0}], "pitch0": [0.0, 0.0, 0.13, 0.0, 0.24, -32.0, 0.36, -32.0, 0.52, -4.0], "follow0": [0.0, 0.0, 0.12, 0.0, 0.25, 0.7, 0.4, 0.7]}}
		"a2":
			return {"len": 0.52, "in": 0.06, "out": 0.22, "ev": {"swing": 0.075, "impact": 0.115, "step": [0.12, 0.5]},
				"py": [0.0, 31.646, 0.06, 36.0, 0.085, 30.0, 0.13, -14.0, 0.18, -24.0, 0.28, -18.0, 0.4, -6.0, 0.52, 0.0],
				"cy": [0.0, 57.055, 0.06, 66.0, 0.09, 60.0, 0.14, -30.0, 0.19, -50.0, 0.28, -40.0, 0.4, -12.0, 0.52, 0.0],
				"pp": [0.0, -6.0, 0.07, -4.0, 0.14, -6.0, 0.28, -3.0, 0.52, 1.1],
				"cp": [0.0, -19.793, 0.07, -12.0, 0.14, -14.0, 0.22, -10.0, 0.36, -2.0, 0.52, 4.0],
				"cr": [0.0, -8.726, 0.07, -10.0, 0.14, 6.0, 0.24, 8.0, 0.4, 2.0, 0.52, 0.0],
				"pr": [0.0, -4.0, 0.08, -4.0, 0.14, 4.0, 0.3, 3.0, 0.52, 0.0],
				"px": [0.0, -0.058, 0.08, -0.06, 0.14, 0.04, 0.3, 0.05, 0.44, 0.01, 0.52, 0.0],
				"pz": [0.0, -0.176, 0.08, -0.17, 0.14, -0.2, 0.3, -0.16, 0.44, -0.05, 0.52, 0.0],
				"pdy": [0.0, -0.147, 0.08, -0.14, 0.14, -0.12, 0.3, -0.11, 0.44, -0.04, 0.52, 0.0],
				"hy": [0.0, 12.66, 0.06, 16.0, 0.1, 4.0, 0.14, -8.0, 0.24, -14.0, 0.4, -4.0, 0.52, 0.0],
				"hp": [0.0, -7.685, 0.1, -6.0, 0.2, -2.0, 0.4, 0.0, 0.52, 0.0],
				"hlx": [0.0, -0.2, 0.07, -0.3, 0.14, -0.42, 0.26, -0.42, 0.42, -0.335, 0.52, -0.335],
				"hly": [0.0, -0.2, 0.07, -0.3, 0.14, -0.14, 0.26, -0.14, 0.42, -0.366, 0.52, -0.366],
				"hlz": [0.0, -0.3, 0.07, -0.24, 0.14, -0.1, 0.26, -0.1, 0.42, -0.08, 0.52, -0.08],
				"hpx": [0.0, -0.8, 0.07, -0.8, 0.14, -0.6, 0.26, -0.6, 0.42, -0.5, 0.52, -0.5],
				"hpy": [0.0, -0.5, 0.07, -0.5, 0.14, -0.6, 0.26, -0.6, 0.42, -0.2, 0.52, -0.2],
				"hpz": [0.0, 0.5, 0.07, 0.4, 0.14, 0.5, 0.26, 0.5, 0.42, 1.0, 0.52, 1.0],
				"hfx": [0.0, -0.45, 0.07, -0.6, 0.14, -0.85, 0.26, -0.85, 0.42, -1.0, 0.52, -1.0],
				"hfy": [0.0, 0.1, 0.07, 0.0, 0.14, 0.1, 0.26, 0.1, 0.42, 0.0, 0.52, 0.0],
				"hfz": [0.0, -0.9, 0.07, -0.8, 0.14, -0.5, 0.26, -0.5, 0.42, -0.35, 0.52, -0.35],
				"az": [0.0, -44.51, 0.017, -43.78, 0.033, -40.19, 0.05, -36.35, 0.067, -35.18, 0.07, -35.54, 0.078, -34.62, 0.083, -33.37, 0.1, -20.67, 0.115, -10.69, 0.117, -9.48, 0.133, -0.63, 0.145, 2.12, 0.15, 2.8, 0.167, 4.57, 0.18, 5.6, 0.183, 4.43, 0.2, -6.11, 0.217, -25.33, 0.233, -44.52, 0.25, -60.97, 0.267, -72.2, 0.27, -73.94, 0.283, -74.01, 0.3, -74.26, 0.317, -74.68, 0.333, -75.23, 0.35, -75.89, 0.367, -76.62, 0.383, -77.41, 0.4, -78.21, 0.417, -79.01, 0.433, -79.77, 0.45, -80.46, 0.467, -81.06, 0.483, -81.53, 0.5, -81.85, 0.517, -82.0, 0.52, -86.23],
				"e": [0.0, 26.81, 0.017, 27.29, 0.033, 27.0, 0.05, 25.78, 0.067, 23.78, 0.07, 23.48, 0.078, 24.31, 0.083, 24.92, 0.1, 37.64, 0.115, 66.1, 0.117, 69.06, 0.133, 90.5, 0.145, 96.46, 0.15, 97.6, 0.167, 99.64, 0.18, 100.34, 0.183, 99.55, 0.2, 93.79, 0.217, 86.08, 0.233, 76.71, 0.25, 69.61, 0.267, 66.8, 0.27, 66.8, 0.283, 66.4, 0.3, 64.86, 0.317, 62.33, 0.333, 58.99, 0.35, 55.0, 0.367, 50.55, 0.383, 45.81, 0.4, 40.94, 0.417, 36.12, 0.433, 31.53, 0.45, 27.33, 0.467, 23.71, 0.483, 20.84, 0.5, 18.89, 0.517, 18.03, 0.52, 18.9],
				"r": [0.0, 75.96, 0.017, 76.23, 0.033, 72.11, 0.05, 66.51, 0.067, 65.28, 0.07, 66.11, 0.078, 63.51, 0.083, 62.43, 0.1, 35.05, 0.115, 6.27, 0.117, 4.68, 0.133, 3.87, 0.145, 7.25, 0.15, 7.56, 0.167, 11.4, 0.18, 15.05, 0.183, 9.03, 0.2, -6.15, 0.217, -7.34, 0.233, -2.74, 0.25, 4.2, 0.267, 10.67, 0.27, 12.08, 0.283, 11.2, 0.3, 7.82, 0.317, 2.27, 0.333, -5.06, 0.35, -13.8, 0.367, -23.57, 0.383, -33.99, 0.4, -44.67, 0.417, -55.24, 0.433, -65.32, 0.45, -74.52, 0.467, -82.46, 0.483, -88.76, 0.5, -93.05, 0.517, -94.94, 0.52, -95.11],
				"el": [0.0, 75.97, 0.017, 74.64, 0.033, 73.05, 0.05, 73.7, 0.067, 77.58, 0.07, 78.39, 0.078, 78.02, 0.083, 77.51, 0.1, 64.98, 0.115, 58.3, 0.117, 58.56, 0.133, 56.84, 0.145, 53.32, 0.15, 53.48, 0.167, 54.33, 0.18, 53.47, 0.183, 58.51, 0.2, 80.84, 0.217, 94.52, 0.233, 106.03, 0.25, 113.57, 0.267, 116.9, 0.27, 117.16, 0.283, 116.38, 0.3, 113.38, 0.317, 108.45, 0.333, 101.94, 0.35, 94.16, 0.367, 85.48, 0.383, 76.22, 0.4, 66.73, 0.417, 57.33, 0.433, 48.38, 0.45, 40.2, 0.467, 33.14, 0.483, 27.54, 0.5, 23.73, 0.517, 22.05, 0.52, 19.88],
				"uln": [0.0, 59.52, 0.017, 56.82, 0.033, 52.61, 0.05, 47.35, 0.067, 41.03, 0.07, 40.22, 0.078, 40.65, 0.083, 40.91, 0.1, 50.43, 0.115, 59.76, 0.117, 59.85, 0.133, 59.74, 0.145, 59.61, 0.15, 59.53, 0.167, 56.9, 0.18, 55.64, 0.183, 57.39, 0.2, 59.7, 0.217, 58.21, 0.233, 52.27, 0.25, 46.67, 0.267, 43.18, 0.27, 42.48, 0.283, 42.62, 0.3, 43.15, 0.317, 44.03, 0.333, 45.2, 0.35, 46.59, 0.367, 48.14, 0.383, 49.8, 0.4, 51.5, 0.417, 53.18, 0.433, 54.78, 0.45, 56.24, 0.467, 57.51, 0.483, 58.51, 0.5, 59.19, 0.517, 59.49, 0.52, 58.71],
				"ext": [0.0, 36.06, 0.017, 27.64, 0.033, 19.23, 0.05, 18.15, 0.067, 22.83, 0.07, 23.53, 0.078, 25.03, 0.083, 24.81, 0.1, 33.85, 0.115, 58.13, 0.117, 60.01, 0.133, 56.42, 0.145, 50.13, 0.15, 48.87, 0.167, 43.28, 0.18, 38.39, 0.183, 45.07, 0.2, 60.44, 0.217, 60.56, 0.233, 60.62, 0.25, 60.67, 0.267, 60.72, 0.27, 60.72, 0.283, 60.71, 0.3, 60.69, 0.317, 60.65, 0.333, 60.6, 0.35, 60.54, 0.367, 60.48, 0.383, 60.41, 0.4, 60.34, 0.417, 60.27, 0.433, 60.2, 0.45, 60.14, 0.467, 60.08, 0.483, 60.04, 0.5, 60.01, 0.517, 60.0, 0.52, 59.61],
				"tw": [0.0, 110.22, 0.017, 110.33, 0.033, 111.08, 0.05, 112.24, 0.067, 113.29, 0.07, 113.36, 0.078, 113.25, 0.083, 113.24, 0.1, 111.86, 0.115, 110.35, 0.117, 110.34, 0.133, 110.44, 0.145, 110.54, 0.15, 110.57, 0.167, 110.82, 0.18, 111.0, 0.183, 110.98, 0.2, 111.07, 0.217, 111.54, 0.233, 112.07, 0.25, 112.44, 0.267, 112.62, 0.27, 112.67, 0.283, 111.58, 0.3, 107.39, 0.317, 100.52, 0.333, 91.44, 0.35, 80.61, 0.367, 68.5, 0.383, 55.6, 0.4, 42.36, 0.417, 29.26, 0.433, 16.78, 0.45, 5.38, 0.467, -4.46, 0.483, -12.27, 0.5, -17.59, 0.517, -19.93, 0.52, -24.09],
				"feet": {"moves": [{"f": 0, "t0": 0.03, "t1": 0.12, "x": 0.2, "z": -0.3, "yaw": -8.0, "apex": 0.09, "th": 10.0}, {"f": 1, "t0": 0.3, "t1": 0.44, "x": -0.15, "z": -0.06, "yaw": 4.0, "apex": 0.07, "th": 6.0, "near": 0.12}, {"f": 0, "t0": 0.36, "t1": 0.5, "x": 0.15, "z": 0.04, "yaw": -4.0, "apex": 0.07, "th": 6.0}], "pitch1": [0.0, 0.0, 0.1, 0.0, 0.18, -26.0, 0.28, -26.0, 0.34, 0.0], "follow1": [0.0, 0.0, 0.08, 0.0, 0.2, 0.6, 0.3, 0.6]}}
		"a3":
			return {"len": 0.6, "in": 0.06, "out": 0.22, "ev": {"swing": 0.1, "impact": 0.14, "step": [0.15, 0.58]},
				"py": [0.0, -23.899, 0.08, -28.0, 0.1, -30.0, 0.14, 8.0, 0.18, 32.0, 0.28, 40.0, 0.42, 22.0, 0.6, 0.0],
				"cy": [0.0, -50.0, 0.08, -58.0, 0.105, -62.0, 0.15, 20.0, 0.19, 58.0, 0.28, 72.0, 0.42, 36.0, 0.6, 0.0],
				"pp": [0.0, -5.346, 0.09, 2.0, 0.15, -6.0, 0.3, -5.0, 0.6, 1.1],
				"cp": [0.0, -11.887, 0.09, 2.0, 0.15, -10.0, 0.3, -12.0, 0.45, -4.0, 0.6, 4.0],
				"cr": [0.0, 7.484, 0.09, 4.0, 0.15, -4.0, 0.3, -6.0, 0.6, 0.0],
				"pr": [0.0, 3.858, 0.09, 3.0, 0.15, -3.0, 0.3, -3.0, 0.6, 0.0],
				"px": [0.0, 0.046, 0.09, 0.06, 0.15, -0.02, 0.3, -0.06, 0.46, -0.02, 0.6, 0.0],
				"pz": [0.0, -0.195, 0.09, -0.1, 0.15, -0.16, 0.3, -0.18, 0.46, -0.06, 0.6, 0.0],
				"pdy": [0.0, -0.116, 0.09, -0.12, 0.15, -0.15, 0.3, -0.14, 0.46, -0.05, 0.6, 0.0],
				"hy": [0.0, -12.382, 0.08, -12.0, 0.12, -4.0, 0.16, 8.0, 0.28, 16.0, 0.46, 6.0, 0.6, 0.0],
				"hp": [0.0, -2.229, 0.1, -2.0, 0.2, -4.0, 0.45, 0.0, 0.6, 0.0],
				"hlx": [0.0, -0.42, 0.09, -0.2, 0.16, -0.42, 0.3, -0.42, 0.48, -0.335, 0.6, -0.335],
				"hly": [0.0, -0.14, 0.09, -0.2, 0.16, -0.14, 0.3, -0.14, 0.48, -0.366, 0.6, -0.366],
				"hlz": [0.0, -0.1, 0.09, -0.3, 0.16, -0.1, 0.3, -0.1, 0.48, -0.08, 0.6, -0.08],
				"hpx": [0.0, -0.6, 0.09, -0.8, 0.16, -0.6, 0.3, -0.6, 0.48, -0.5, 0.6, -0.5],
				"hpy": [0.0, -0.6, 0.09, -0.5, 0.16, -0.6, 0.3, -0.6, 0.48, -0.2, 0.6, -0.2],
				"hpz": [0.0, 0.5, 0.09, 0.5, 0.16, 0.5, 0.3, 0.5, 0.48, 1.0, 0.6, 1.0],
				"hfx": [0.0, -0.85, 0.09, -0.45, 0.16, -0.85, 0.3, -0.85, 0.48, -1.0, 0.6, -1.0],
				"hfy": [0.0, 0.1, 0.09, 0.1, 0.16, 0.1, 0.3, 0.1, 0.48, 0.0, 0.6, 0.0],
				"hfz": [0.0, -0.5, 0.09, -0.9, 0.16, -0.5, 0.3, -0.5, 0.48, -0.35, 0.6, -0.35],
				"az": [0.0, 1.41, 0.017, -7.95, 0.033, -30.75, 0.05, -59.09, 0.067, -85.06, 0.083, -100.74, 0.09, -102.37, 0.097, -98.95, 0.1, -97.9, 0.117, -87.8, 0.133, -73.79, 0.14, -60.3, 0.15, -47.81, 0.167, -42.4, 0.172, -46.05, 0.183, -52.0, 0.2, -55.24, 0.21, -57.18, 0.217, -46.83, 0.233, -26.05, 0.25, -32.41, 0.267, -40.75, 0.283, -49.95, 0.3, -56.88, 0.317, -53.82, 0.333, -46.17, 0.35, -36.22, 0.367, -26.27, 0.383, -18.62, 0.4, -15.56, 0.417, -16.86, 0.433, -20.1, 0.45, -24.32, 0.467, -28.54, 0.483, -31.78, 0.5, -33.08, 0.517, -36.7, 0.533, -45.76, 0.55, -57.54, 0.567, -69.32, 0.583, -78.37, 0.6, -85.91],
				"e": [0.0, 97.87, 0.017, 95.61, 0.033, 90.1, 0.05, 83.26, 0.067, 76.98, 0.083, 73.2, 0.09, 72.8, 0.097, 72.95, 0.1, 73.16, 0.117, 73.0, 0.133, 71.06, 0.14, 71.83, 0.15, 74.16, 0.167, 76.85, 0.172, 76.88, 0.183, 75.46, 0.2, 74.4, 0.21, 74.15, 0.217, 62.34, 0.233, 38.93, 0.25, 29.66, 0.267, 23.96, 0.283, 20.04, 0.3, 18.01, 0.317, 19.89, 0.333, 24.6, 0.35, 30.72, 0.367, 36.83, 0.383, 41.54, 0.4, 43.42, 0.417, 42.36, 0.433, 39.69, 0.45, 36.22, 0.467, 32.76, 0.483, 30.09, 0.5, 29.03, 0.517, 28.21, 0.533, 26.17, 0.55, 23.51, 0.567, 20.86, 0.583, 18.82, 0.6, 18.87],
				"r": [0.0, 0.28, 0.017, 5.26, 0.033, 17.39, 0.05, 32.47, 0.067, 46.28, 0.083, 54.62, 0.09, 55.49, 0.097, 55.0, 0.1, 54.46, 0.117, 51.01, 0.133, 44.79, 0.14, 41.46, 0.15, 37.89, 0.167, 34.9, 0.172, 33.74, 0.183, 32.09, 0.2, 31.07, 0.21, 30.52, 0.217, 27.08, 0.233, 22.74, 0.25, 49.15, 0.267, 70.16, 0.283, 86.27, 0.3, 96.39, 0.317, 96.19, 0.333, 95.68, 0.35, 95.01, 0.367, 94.35, 0.383, 93.84, 0.4, 93.63, 0.417, 89.49, 0.433, 79.13, 0.45, 65.66, 0.467, 52.18, 0.483, 41.83, 0.5, 37.68, 0.517, 27.85, 0.533, 3.29, 0.55, -28.66, 0.567, -60.61, 0.583, -85.17, 0.6, -95.03],
				"el": [0.0, 68.08, 0.017, 66.51, 0.033, 62.71, 0.05, 57.97, 0.067, 53.64, 0.083, 51.02, 0.09, 50.75, 0.097, 50.84, 0.1, 50.8, 0.117, 50.93, 0.133, 51.08, 0.14, 51.22, 0.15, 51.09, 0.167, 50.78, 0.172, 50.67, 0.183, 54.63, 0.2, 58.44, 0.21, 59.23, 0.217, 67.23, 0.233, 79.12, 0.25, 91.45, 0.267, 100.1, 0.283, 105.15, 0.3, 107.29, 0.317, 102.27, 0.333, 89.75, 0.35, 73.45, 0.367, 57.16, 0.383, 44.63, 0.4, 39.62, 0.417, 37.23, 0.433, 31.25, 0.45, 23.48, 0.467, 15.71, 0.483, 9.73, 0.5, 7.34, 0.517, 8.43, 0.533, 11.14, 0.55, 14.67, 0.567, 18.2, 0.583, 20.91, 0.6, 19.91],
				"uln": [0.0, 59.12, 0.017, 59.15, 0.033, 59.23, 0.05, 59.34, 0.067, 59.44, 0.083, 59.49, 0.09, 59.5, 0.097, 59.51, 0.1, 59.51, 0.117, 59.53, 0.133, 59.55, 0.14, 59.56, 0.15, 59.54, 0.167, 59.51, 0.172, 59.5, 0.183, 59.52, 0.2, 59.51, 0.21, 59.5, 0.217, 59.62, 0.233, 60.05, 0.25, 61.1, 0.267, 61.38, 0.283, 61.4, 0.3, 61.38, 0.317, 61.34, 0.333, 61.22, 0.35, 61.08, 0.367, 60.93, 0.383, 60.81, 0.4, 60.77, 0.417, 60.38, 0.433, 59.41, 0.45, 58.15, 0.467, 56.9, 0.483, 55.93, 0.5, 55.54, 0.517, 55.83, 0.533, 56.57, 0.55, 57.52, 0.567, 58.47, 0.583, 59.21, 0.6, 58.57],
				"ext": [0.0, 55.42, 0.017, 46.67, 0.033, 25.36, 0.05, -1.14, 0.067, -25.43, 0.083, -40.09, 0.09, -41.61, 0.097, -41.63, 0.1, -41.62, 0.117, -41.63, 0.133, -41.63, 0.14, -41.65, 0.15, -41.65, 0.167, -41.57, 0.172, -41.55, 0.183, -45.49, 0.2, -49.86, 0.21, -50.98, 0.217, -53.43, 0.233, -40.62, 0.25, -45.86, 0.267, -44.54, 0.283, -40.2, 0.3, -36.73, 0.317, -29.49, 0.333, -11.39, 0.35, 12.14, 0.367, 35.68, 0.383, 53.77, 0.4, 61.02, 0.417, 61.0, 0.433, 60.97, 0.45, 60.92, 0.467, 60.88, 0.483, 60.84, 0.5, 60.83, 0.517, 60.77, 0.533, 60.61, 0.55, 60.41, 0.567, 60.22, 0.583, 60.06, 0.6, 60.03],
				"tw": [0.0, 110.15, 0.017, 92.82, 0.033, 50.62, 0.05, -1.85, 0.067, -49.92, 0.083, -78.95, 0.09, -81.96, 0.097, -81.84, 0.1, -81.86, 0.117, -81.52, 0.133, -81.04, 0.14, -80.87, 0.15, -81.27, 0.167, -81.76, 0.172, -81.96, 0.183, -85.82, 0.2, -89.94, 0.21, -91.0, 0.217, -104.37, 0.233, -110.76, 0.25, -111.21, 0.267, -111.64, 0.283, -111.84, 0.3, -111.85, 0.317, -95.31, 0.333, -53.99, 0.35, -0.24, 0.367, 53.5, 0.383, 94.82, 0.4, 111.37, 0.417, 111.28, 0.433, 111.06, 0.45, 110.78, 0.467, 110.5, 0.483, 110.28, 0.5, 110.2, 0.517, 100.55, 0.533, 76.45, 0.55, 45.1, 0.567, 13.75, 0.583, -10.35, 0.6, -23.39],
				"feet": {"moves": [{"f": 0, "t0": 0.07, "t1": 0.16, "x": 0.02, "z": -0.3, "yaw": -30.0, "apex": 0.08, "th": 6.0}, {"f": 1, "t0": 0.4, "t1": 0.52, "x": -0.15, "z": -0.06, "yaw": 4.0, "apex": 0.07, "th": 6.0, "near": 0.12}, {"f": 0, "t0": 0.44, "t1": 0.58, "x": 0.15, "z": 0.04, "yaw": -4.0, "apex": 0.07, "th": 6.0}], "pitch1": [0.0, 0.0, 0.1, 0.0, 0.17, -28.0, 0.36, -28.0, 0.42, 0.0], "follow1": [0.0, 0.0, 0.08, 0.0, 0.2, 0.8, 0.36, 0.8]}}
		"a4":
			return {"len": 0.82, "in": 0.07, "out": 0.25, "ev": {"swing": 0.21, "impact": 0.28, "step": [0.26, 0.78]},
				"py": [0.0, 37.098, 0.1, 10.0, 0.19, -8.0, 0.24, 6.0, 0.3, 12.0, 0.44, 10.0, 0.62, 4.0, 0.82, 0.0],
				"cy": [0.0, 65.556, 0.1, 20.0, 0.19, -18.0, 0.25, 4.0, 0.3, 10.0, 0.44, 8.0, 0.62, 2.0, 0.82, 0.0],
				"pp": [0.0, -5.716, 0.1, 4.0, 0.19, 8.0, 0.27, -14.0, 0.44, -14.0, 0.62, -4.0, 0.82, 1.1],
				"cp": [0.0, -11.469, 0.1, 10.0, 0.19, 22.0, 0.24, 0.0, 0.28, -32.0, 0.44, -30.0, 0.62, -8.0, 0.82, 4.0],
				"cr": [0.0, -5.447, 0.1, 4.0, 0.19, -4.0, 0.28, 3.0, 0.44, 3.0, 0.82, 0.0],
				"pr": [0.0, -3.0, 0.1, 2.0, 0.19, -3.0, 0.28, 2.0, 0.82, 0.0],
				"px": [0.0, -0.048, 0.1, 0.02, 0.19, 0.04, 0.28, -0.02, 0.44, -0.02, 0.62, -0.01, 0.82, 0.0],
				"pz": [0.0, -0.174, 0.1, -0.06, 0.19, -0.04, 0.27, -0.3, 0.44, -0.28, 0.62, -0.1, 0.82, 0.0],
				"pdy": [0.0, -0.148, 0.1, -0.08, 0.19, 0.0, 0.24, -0.06, 0.28, -0.3, 0.44, -0.28, 0.62, -0.12, 0.82, 0.0],
				"hy": [0.0, 13.831, 0.1, 4.0, 0.19, 0.0, 0.28, 2.0, 0.44, 2.0, 0.82, 0.0],
				"hp": [0.0, -3.927, 0.1, 4.0, 0.19, 10.0, 0.27, -12.0, 0.44, -16.0, 0.62, -4.0, 0.82, 0.0],
				"hlx": [0.0, -0.42, 0.1, -0.2, 0.19, -0.36, 0.27, -0.46, 0.44, -0.46, 0.64, -0.335, 0.82, -0.335],
				"hly": [0.0, -0.14, 0.1, -0.2, 0.19, 0.02, 0.27, -0.3, 0.44, -0.3, 0.64, -0.366, 0.82, -0.366],
				"hlz": [0.0, -0.1, 0.1, -0.3, 0.19, -0.3, 0.27, 0.16, 0.44, 0.16, 0.64, -0.08, 0.82, -0.08],
				"hpx": [0.0, -0.6, 0.1, -0.8, 0.19, -0.8, 0.27, -0.4, 0.44, -0.4, 0.64, -0.5, 0.82, -0.5],
				"hpy": [0.0, -0.6, 0.1, -0.5, 0.19, -0.4, 0.27, -0.5, 0.44, -0.5, 0.64, -0.2, 0.82, -0.2],
				"hpz": [0.0, 0.5, 0.1, 0.5, 0.19, 0.4, 0.27, 1.0, 0.44, 1.0, 0.64, 1.0, 0.82, 1.0],
				"hfx": [0.0, -0.85, 0.1, -0.45, 0.19, -0.6, 0.27, -0.95, 0.44, -0.95, 0.64, -1.0, 0.82, -1.0],
				"hfy": [0.0, 0.1, 0.1, 0.1, 0.19, 0.2, 0.27, 0.0, 0.44, 0.0, 0.64, 0.0, 0.82, 0.0],
				"hfz": [0.0, -0.5, 0.1, -0.9, 0.19, -0.8, 0.27, 0.25, 0.44, 0.25, 0.64, -0.35, 0.82, -0.35],
				"az": [0.0, -41.9, 0.017, -35.85, 0.033, -21.12, 0.05, -2.81, 0.067, 13.98, 0.083, 24.11, 0.09, 25.16, 0.1, 18.02, 0.117, 7.89, 0.133, -0.03, 0.15, -5.76, 0.167, -9.28, 0.183, -10.6, 0.185, -10.62, 0.2, -15.5, 0.205, -17.54, 0.217, -23.44, 0.233, -35.22, 0.25, -44.64, 0.255, -44.21, 0.267, -39.25, 0.283, -35.45, 0.285, -35.45, 0.3, -35.92, 0.317, -36.05, 0.333, -36.19, 0.35, -36.37, 0.367, -36.45, 0.383, -36.56, 0.4, -36.71, 0.417, -36.84, 0.433, -36.97, 0.44, -37.01, 0.45, -38.36, 0.467, -45.77, 0.483, -58.03, 0.5, -73.28, 0.517, -89.65, 0.533, -105.26, 0.55, -118.27, 0.567, -126.8, 0.58, -129.15, 0.583, -129.12, 0.6, -128.22, 0.617, -126.18, 0.633, -123.2, 0.65, -119.46, 0.667, -115.14, 0.683, -110.46, 0.7, -105.58, 0.717, -100.69, 0.733, -96.01, 0.75, -91.69, 0.767, -87.95, 0.783, -84.97, 0.8, -82.93, 0.817, -82.03, 0.82, -85.37],
				"e": [0.0, 56.95, 0.017, 63.14, 0.033, 78.22, 0.05, 96.96, 0.067, 114.14, 0.083, 124.51, 0.09, 125.59, 0.1, 120.67, 0.117, 113.7, 0.133, 108.24, 0.15, 104.29, 0.167, 101.87, 0.183, 100.96, 0.185, 100.95, 0.2, 101.85, 0.205, 103.78, 0.217, 104.62, 0.233, 91.11, 0.25, 62.47, 0.255, 53.17, 0.267, 47.27, 0.283, 43.93, 0.285, 43.81, 0.3, 42.99, 0.317, 42.28, 0.333, 41.67, 0.35, 41.16, 0.367, 40.64, 0.383, 40.21, 0.4, 39.88, 0.417, 39.6, 0.433, 39.36, 0.44, 39.27, 0.45, 38.94, 0.467, 37.13, 0.483, 34.14, 0.5, 30.41, 0.517, 26.41, 0.533, 22.6, 0.55, 19.42, 0.567, 17.34, 0.58, 16.76, 0.583, 16.76, 0.6, 16.79, 0.617, 16.84, 0.633, 16.92, 0.65, 17.02, 0.667, 17.13, 0.683, 17.25, 0.7, 17.38, 0.717, 17.51, 0.733, 17.63, 0.75, 17.75, 0.767, 17.84, 0.783, 17.92, 0.8, 17.98, 0.817, 18.0, 0.82, 18.87],
				"r": [0.0, 26.11, 0.017, 24.11, 0.033, 19.23, 0.05, 13.17, 0.067, 7.61, 0.083, 4.26, 0.09, 3.91, 0.1, 5.5, 0.117, 7.75, 0.133, 9.52, 0.15, 10.79, 0.167, 11.58, 0.183, 11.87, 0.185, 11.88, 0.2, 13.96, 0.205, 14.08, 0.217, 15.32, 0.233, 24.79, 0.25, 51.05, 0.255, 64.61, 0.267, 61.73, 0.283, 59.64, 0.285, 59.52, 0.3, 59.2, 0.317, 59.17, 0.333, 59.31, 0.35, 59.65, 0.367, 59.84, 0.383, 60.19, 0.4, 60.7, 0.417, 61.22, 0.433, 61.76, 0.44, 61.95, 0.45, 62.52, 0.467, 65.66, 0.483, 70.85, 0.5, 77.3, 0.517, 84.23, 0.533, 90.84, 0.55, 96.35, 0.567, 99.96, 0.58, 100.96, 0.583, 100.84, 0.6, 97.1, 0.617, 88.63, 0.633, 76.23, 0.65, 60.67, 0.667, 42.75, 0.683, 23.26, 0.7, 2.98, 0.717, -17.31, 0.733, -36.79, 0.75, -54.71, 0.767, -70.27, 0.783, -82.67, 0.8, -91.14, 0.817, -94.89, 0.82, -95.11],
				"el": [0.0, 70.18, 0.017, 64.54, 0.033, 50.8, 0.05, 33.72, 0.067, 18.07, 0.083, 8.62, 0.09, 7.64, 0.1, 28.7, 0.117, 58.61, 0.133, 81.99, 0.15, 98.9, 0.167, 109.3, 0.183, 113.2, 0.185, 113.23, 0.2, 113.92, 0.205, 114.05, 0.217, 112.06, 0.233, 101.13, 0.25, 74.01, 0.255, 61.34, 0.267, 56.07, 0.283, 52.02, 0.285, 51.93, 0.3, 52.23, 0.317, 52.65, 0.333, 53.0, 0.35, 53.28, 0.367, 53.55, 0.383, 53.75, 0.4, 53.89, 0.417, 53.98, 0.433, 54.03, 0.44, 54.04, 0.45, 54.04, 0.467, 54.05, 0.483, 54.06, 0.5, 54.07, 0.517, 54.09, 0.533, 54.1, 0.55, 54.11, 0.567, 54.12, 0.58, 54.12, 0.583, 54.11, 0.6, 53.49, 0.617, 52.1, 0.633, 50.07, 0.65, 47.52, 0.667, 44.58, 0.683, 41.39, 0.7, 38.06, 0.717, 34.74, 0.733, 31.54, 0.75, 28.6, 0.767, 26.05, 0.783, 24.02, 0.8, 22.63, 0.817, 22.02, 0.82, 20.41],
				"uln": [0.0, 59.54, 0.017, 59.73, 0.033, 60.19, 0.05, 60.76, 0.067, 61.28, 0.083, 61.6, 0.09, 61.63, 0.1, 61.24, 0.117, 60.68, 0.133, 60.24, 0.15, 59.92, 0.167, 59.72, 0.183, 59.65, 0.185, 59.65, 0.2, 59.57, 0.205, 59.54, 0.217, 59.55, 0.233, 59.58, 0.25, 59.54, 0.255, 59.57, 0.267, 60.11, 0.283, 60.48, 0.285, 60.49, 0.3, 60.52, 0.317, 60.55, 0.333, 60.58, 0.35, 60.6, 0.367, 60.62, 0.383, 60.63, 0.4, 60.64, 0.417, 60.65, 0.433, 60.65, 0.44, 60.65, 0.45, 60.64, 0.467, 60.62, 0.483, 60.59, 0.5, 60.54, 0.517, 60.49, 0.533, 60.45, 0.55, 60.41, 0.567, 60.39, 0.58, 60.38, 0.583, 60.38, 0.6, 60.36, 0.617, 60.32, 0.633, 60.27, 0.65, 60.2, 0.667, 60.12, 0.683, 60.03, 0.7, 59.94, 0.717, 59.85, 0.733, 59.76, 0.75, 59.68, 0.767, 59.61, 0.783, 59.56, 0.8, 59.52, 0.817, 59.5, 0.82, 59.06],
				"ext": [0.0, -52.13, 0.017, -41.83, 0.033, -16.74, 0.05, 14.46, 0.067, 43.05, 0.083, 60.31, 0.09, 62.1, 0.1, 56.63, 0.117, 48.87, 0.133, 42.79, 0.15, 38.4, 0.167, 35.7, 0.183, 34.69, 0.185, 34.68, 0.2, 43.45, 0.205, 45.43, 0.217, 48.73, 0.233, 59.8, 0.25, 60.21, 0.255, 60.11, 0.267, 58.66, 0.283, 55.97, 0.285, 55.97, 0.3, 56.18, 0.317, 56.7, 0.333, 57.07, 0.35, 57.28, 0.367, 57.67, 0.383, 57.92, 0.4, 58.03, 0.417, 58.1, 0.433, 58.14, 0.44, 58.17, 0.45, 58.2, 0.467, 58.38, 0.483, 58.67, 0.5, 59.03, 0.517, 59.42, 0.533, 59.8, 0.55, 60.11, 0.567, 60.31, 0.58, 60.36, 0.583, 60.36, 0.6, 60.36, 0.617, 60.34, 0.633, 60.32, 0.65, 60.29, 0.667, 60.26, 0.683, 60.22, 0.7, 60.18, 0.717, 60.14, 0.733, 60.11, 0.75, 60.08, 0.767, 60.05, 0.783, 60.02, 0.8, 60.01, 0.817, 60.0, 0.82, 60.02],
				"tw": [0.0, -106.43, 0.017, -98.8, 0.033, -80.23, 0.05, -57.14, 0.067, -35.98, 0.083, -23.21, 0.09, -21.89, 0.1, -9.68, 0.117, 7.66, 0.133, 21.22, 0.15, 31.02, 0.167, 37.05, 0.183, 39.31, 0.185, 39.33, 0.2, 50.74, 0.205, 52.97, 0.217, 57.65, 0.233, 76.43, 0.25, 99.1, 0.255, 110.04, 0.267, 110.54, 0.283, 110.74, 0.285, 110.74, 0.3, 110.77, 0.317, 110.8, 0.333, 110.83, 0.35, 110.86, 0.367, 110.88, 0.383, 110.9, 0.4, 110.91, 0.417, 110.92, 0.433, 110.92, 0.44, 110.92, 0.45, 110.94, 0.467, 111.01, 0.483, 111.13, 0.5, 111.29, 0.517, 111.45, 0.533, 111.61, 0.55, 111.74, 0.567, 111.82, 0.58, 111.85, 0.583, 111.77, 0.6, 109.25, 0.617, 103.55, 0.633, 95.21, 0.65, 84.74, 0.667, 72.68, 0.683, 59.57, 0.7, 45.92, 0.717, 32.28, 0.733, 19.16, 0.75, 7.11, 0.767, -3.36, 0.783, -11.71, 0.8, -17.41, 0.817, -19.92, 0.82, -22.97],
				"feet": {"moves": [{"f": 0, "t0": 0.02, "t1": 0.12, "x": 0.16, "z": 0.06, "yaw": -6.0, "apex": 0.06, "th": 4.0, "near": 0.14}, {"f": 1, "t0": 0.12, "t1": 0.27, "x": -0.22, "z": -0.62, "yaw": 10.0, "apex": 0.16, "th": 8.0}, {"f": 1, "t0": 0.6, "t1": 0.78, "x": -0.15, "z": -0.1, "yaw": 4.0, "apex": 0.08, "th": 5.0}], "pitch0": [0.0, 0.0, 0.2, 0.0, 0.3, -30.0, 0.56, -30.0, 0.74, -4.0], "follow0": [0.0, 0.0, 0.2, 0.0, 0.32, 0.6, 0.5, 0.6]}}
		"b1":
			return {"len": 0.58, "in": 0.07, "out": 0.22, "ev": {"swing": 0.11, "impact": 0.155, "step": [0.145, 0.56]},
				"py": [0.0, 0.0, 0.105, -14.0, 0.115, -15.0, 0.155, 12.0, 0.195, 26.0, 0.29, 30.0, 0.43, 14.0, 0.58, 0.0],
				"cy": [0.0, 0.0, 0.105, -30.0, 0.12, -32.0, 0.165, 30.0, 0.205, 50.0, 0.29, 56.0, 0.43, 26.0, 0.58, 0.0],
				"pp": [0.0, 1.1, 0.115, 6.0, 0.175, -2.0, 0.31, -3.0, 0.58, 1.1],
				"cp": [0.0, 4.0, 0.105, 12.0, 0.12, 12.0, 0.175, -8.0, 0.25, -12.0, 0.41, -4.0, 0.58, 4.0],
				"cr": [0.0, 0.0, 0.105, -6.0, 0.175, 10.0, 0.29, 12.0, 0.43, 4.0, 0.58, 0.0],
				"pr": [0.0, 0.0, 0.115, -3.0, 0.175, 4.0, 0.31, 4.0, 0.58, 0.0],
				"px": [0.0, 0.0, 0.115, 0.04, 0.175, -0.04, 0.31, -0.05, 0.47, -0.02, 0.58, 0.0],
				"pz": [0.0, 0.0, 0.115, 0.04, 0.175, -0.12, 0.31, -0.14, 0.47, -0.05, 0.58, 0.0],
				"pdy": [0.0, 0.0, 0.115, -0.1, 0.175, -0.06, 0.31, -0.08, 0.47, -0.03, 0.58, 0.0],
				"hy": [0.0, 0.0, 0.105, -8.0, 0.145, 0.0, 0.195, 10.0, 0.31, 14.0, 0.47, 4.0, 0.58, 0.0],
				"hp": [0.0, 0.0, 0.115, -4.0, 0.195, 4.0, 0.31, 2.0, 0.58, 0.0],
				"hlx": [0.0, -0.335, 0.105, -0.2, 0.175, -0.42, 0.31, -0.42, 0.47, -0.335, 0.58, -0.335],
				"hly": [0.0, -0.366, 0.105, -0.2, 0.175, -0.14, 0.31, -0.14, 0.47, -0.366, 0.58, -0.366],
				"hlz": [0.0, -0.08, 0.105, -0.3, 0.175, -0.1, 0.31, -0.1, 0.47, -0.08, 0.58, -0.08],
				"hpx": [0.0, -0.5, 0.105, -0.8, 0.175, -0.6, 0.31, -0.6, 0.47, -0.5, 0.58, -0.5],
				"hpy": [0.0, -0.2, 0.105, -0.5, 0.175, -0.6, 0.31, -0.6, 0.47, -0.2, 0.58, -0.2],
				"hpz": [0.0, 1.0, 0.105, 0.5, 0.175, 0.5, 0.31, 0.5, 0.47, 1.0, 0.58, 1.0],
				"hfx": [0.0, -1.0, 0.105, -0.45, 0.175, -0.85, 0.31, -0.85, 0.47, -1.0, 0.58, -1.0],
				"hfy": [0.0, 0.0, 0.105, 0.1, 0.175, 0.1, 0.31, 0.1, 0.47, 0.0, 0.58, 0.0],
				"hfz": [0.0, -0.35, 0.105, -0.9, 0.175, -0.5, 0.31, -0.5, 0.47, -0.35, 0.58, -0.35],
				"az": [0.0, -83.19, 0.017, -83.97, 0.033, -85.93, 0.05, -88.53, 0.067, -91.21, 0.083, -93.42, 0.1, -94.61, 0.105, -94.69, 0.115, -93.31, 0.117, -93.26, 0.133, -65.22, 0.15, -21.65, 0.155, -1.4, 0.167, 3.54, 0.183, 5.28, 0.185, 5.21, 0.2, 6.58, 0.215, 7.33, 0.217, 7.56, 0.233, 8.42, 0.24, 8.51, 0.25, 6.36, 0.267, -4.41, 0.283, -19.5, 0.3, -33.52, 0.317, -41.05, 0.32, -41.3, 0.333, -42.55, 0.35, -46.86, 0.367, -52.89, 0.383, -59.2, 0.4, -64.37, 0.417, -66.97, 0.42, -67.05, 0.433, -66.66, 0.45, -65.33, 0.467, -63.55, 0.483, -61.82, 0.5, -60.65, 0.51, -60.42, 0.517, -60.97, 0.533, -66.02, 0.55, -73.51, 0.567, -79.95, 0.58, -86.08],
				"e": [0.0, 18.66, 0.017, 18.7, 0.033, 18.8, 0.05, 18.92, 0.067, 19.05, 0.083, 19.16, 0.1, 19.22, 0.105, 19.22, 0.115, 18.76, 0.117, 18.67, 0.133, 17.26, 0.15, 40.05, 0.155, 60.7, 0.167, 94.11, 0.183, 104.35, 0.185, 104.33, 0.2, 108.83, 0.215, 111.14, 0.217, 111.57, 0.233, 113.42, 0.24, 113.76, 0.25, 110.43, 0.267, 93.64, 0.283, 70.14, 0.3, 48.31, 0.317, 36.58, 0.32, 36.19, 0.333, 35.43, 0.35, 32.82, 0.367, 29.16, 0.383, 25.33, 0.4, 22.2, 0.417, 20.62, 0.42, 20.57, 0.433, 20.46, 0.45, 20.07, 0.467, 19.55, 0.483, 19.05, 0.5, 18.7, 0.51, 18.64, 0.517, 18.62, 0.533, 18.47, 0.55, 18.25, 0.567, 18.06, 0.58, 18.89],
				"r": [0.0, -95.07, 0.017, -85.07, 0.033, -59.8, 0.05, -26.35, 0.067, 8.17, 0.083, 36.63, 0.1, 51.96, 0.105, 52.94, 0.115, 57.33, 0.117, 58.06, 0.133, 37.93, 0.15, 15.18, 0.155, -1.08, 0.167, -36.75, 0.183, -48.51, 0.185, -51.45, 0.2, -56.09, 0.215, -59.35, 0.217, -60.37, 0.233, -63.51, 0.24, -64.86, 0.25, -57.72, 0.267, -21.79, 0.283, 28.53, 0.3, 75.28, 0.317, 100.39, 0.32, 101.23, 0.333, 100.95, 0.35, 100.01, 0.367, 98.7, 0.383, 97.32, 0.4, 96.19, 0.417, 95.62, 0.42, 95.61, 0.433, 92.49, 0.45, 81.97, 0.467, 67.85, 0.483, 54.14, 0.5, 44.82, 0.51, 43.02, 0.517, 39.5, 0.533, 7.25, 0.55, -40.68, 0.567, -81.89, 0.58, -95.05],
				"el": [0.0, 21.68, 0.017, 25.02, 0.033, 33.45, 0.05, 44.6, 0.067, 56.12, 0.083, 65.61, 0.1, 70.72, 0.105, 71.05, 0.115, 69.51, 0.117, 69.16, 0.133, 50.79, 0.15, 32.36, 0.155, 19.66, 0.167, 7.81, 0.183, 16.61, 0.185, 18.39, 0.2, 24.63, 0.215, 27.77, 0.217, 28.3, 0.233, 31.45, 0.24, 32.57, 0.25, 33.72, 0.267, 39.48, 0.283, 47.56, 0.3, 55.06, 0.317, 59.09, 0.32, 59.22, 0.333, 58.85, 0.35, 57.57, 0.367, 55.79, 0.383, 53.91, 0.4, 52.38, 0.417, 51.61, 0.42, 51.58, 0.433, 48.98, 0.45, 40.19, 0.467, 28.39, 0.483, 16.94, 0.5, 9.16, 0.51, 7.65, 0.517, 8.02, 0.533, 11.37, 0.55, 16.35, 0.567, 20.64, 0.58, 19.79],
				"uln": [0.0, 59.52, 0.017, 57.76, 0.033, 53.32, 0.05, 47.44, 0.067, 41.37, 0.083, 36.36, 0.1, 33.67, 0.105, 33.5, 0.115, 32.45, 0.117, 32.21, 0.133, 42.74, 0.15, 62.59, 0.155, 63.68, 0.167, 62.96, 0.183, 62.53, 0.185, 62.48, 0.2, 62.41, 0.215, 62.35, 0.217, 62.35, 0.233, 62.3, 0.24, 62.27, 0.25, 62.23, 0.267, 62.04, 0.283, 61.78, 0.3, 61.53, 0.317, 61.4, 0.32, 61.39, 0.333, 61.33, 0.35, 61.11, 0.367, 60.8, 0.383, 60.47, 0.4, 60.21, 0.417, 60.08, 0.42, 60.07, 0.433, 59.44, 0.45, 57.31, 0.467, 54.45, 0.483, 51.68, 0.5, 49.79, 0.51, 49.43, 0.517, 49.69, 0.533, 52.04, 0.55, 55.54, 0.567, 58.54, 0.58, 58.5],
				"ext": [0.0, 60.03, 0.017, 59.13, 0.033, 56.86, 0.05, 53.84, 0.067, 50.73, 0.083, 48.17, 0.1, 46.79, 0.105, 46.7, 0.115, 45.24, 0.117, 44.69, 0.133, 24.6, 0.15, -6.49, 0.155, -21.58, 0.167, 8.31, 0.183, 22.51, 0.185, 26.02, 0.2, 33.39, 0.215, 38.2, 0.217, 39.66, 0.233, 44.46, 0.24, 46.2, 0.25, 41.62, 0.267, 18.6, 0.283, -13.64, 0.3, -43.6, 0.317, -59.69, 0.32, -60.23, 0.333, -56.96, 0.35, -45.68, 0.367, -29.91, 0.383, -13.41, 0.4, 0.12, 0.417, 6.9, 0.42, 7.12, 0.433, 10.28, 0.45, 20.92, 0.467, 35.21, 0.483, 49.09, 0.5, 58.51, 0.51, 60.34, 0.517, 60.33, 0.533, 60.25, 0.55, 60.13, 0.567, 60.03, 0.58, 60.03],
				"tw": [0.0, -20.62, 0.017, -11.93, 0.033, 10.0, 0.05, 39.03, 0.067, 68.99, 0.083, 93.69, 0.1, 107.01, 0.105, 107.85, 0.115, 110.16, 0.117, 110.22, 0.133, 111.88, 0.15, 114.12, 0.155, 111.65, 0.167, 110.38, 0.183, 110.57, 0.185, 110.61, 0.2, 110.82, 0.215, 110.91, 0.217, 110.92, 0.233, 111.03, 0.24, 111.06, 0.25, 110.78, 0.267, 109.38, 0.283, 107.41, 0.3, 105.58, 0.317, 104.6, 0.32, 104.57, 0.333, 104.87, 0.35, 105.91, 0.367, 107.35, 0.383, 108.87, 0.4, 110.11, 0.417, 110.73, 0.42, 110.75, 0.433, 110.72, 0.45, 110.62, 0.467, 110.49, 0.483, 110.36, 0.5, 110.28, 0.51, 110.26, 0.517, 106.94, 0.533, 76.5, 0.55, 31.27, 0.567, -7.63, 0.58, -23.59],
				"feet": {"moves": [{"f": 1, "t0": 0.04, "t1": 0.145, "x": -0.17, "z": -0.36, "yaw": 6.0, "apex": 0.09, "th": 10.0}, {"f": 1, "t0": 0.42, "t1": 0.56, "x": -0.15, "z": -0.08, "yaw": 4.0, "apex": 0.07, "th": 6.0}], "pitch0": [0.0, 0.0, 0.125, 0.0, 0.215, -28.0, 0.35, -28.0, 0.5, -4.0], "follow0": [0.0, 0.0, 0.115, 0.0, 0.235, 0.7, 0.41, 0.7]}}
		"b2":
			return {"len": 0.5, "in": 0.06, "out": 0.22, "ev": {"swing": 0.07, "impact": 0.11, "step": [0.11, 0.48]},
				"py": [0.0, 27.506, 0.06, 32.0, 0.075, 30.0, 0.12, -10.0, 0.16, -22.0, 0.26, -24.0, 0.4, -8.0, 0.5, 0.0],
				"cy": [0.0, 51.288, 0.06, 60.0, 0.08, 56.0, 0.13, -24.0, 0.17, -46.0, 0.26, -48.0, 0.4, -14.0, 0.5, 0.0],
				"pp": [0.0, -2.525, 0.07, -2.0, 0.13, -6.0, 0.26, -4.0, 0.5, 1.1],
				"cp": [0.0, -11.042, 0.07, -8.0, 0.13, -14.0, 0.24, -14.0, 0.4, -4.0, 0.5, 4.0],
				"cr": [0.0, 11.149, 0.07, 8.0, 0.13, -6.0, 0.26, -8.0, 0.4, -2.0, 0.5, 0.0],
				"pr": [0.0, 4.0, 0.07, 3.0, 0.13, -4.0, 0.26, -4.0, 0.5, 0.0],
				"px": [0.0, -0.045, 0.07, -0.05, 0.13, 0.04, 0.26, 0.05, 0.42, 0.01, 0.5, 0.0],
				"pz": [0.0, -0.131, 0.07, -0.14, 0.13, -0.18, 0.26, -0.16, 0.42, -0.05, 0.5, 0.0],
				"pdy": [0.0, -0.064, 0.07, -0.08, 0.13, -0.14, 0.26, -0.13, 0.42, -0.04, 0.5, 0.0],
				"hy": [0.0, 11.212, 0.06, 12.0, 0.1, 2.0, 0.14, -8.0, 0.26, -12.0, 0.42, -4.0, 0.5, 0.0],
				"hp": [0.0, 3.871, 0.1, -6.0, 0.2, -6.0, 0.4, -1.0, 0.5, 0.0],
				"hlx": [0.0, -0.42, 0.07, -0.2, 0.14, -0.42, 0.26, -0.42, 0.42, -0.335, 0.5, -0.335],
				"hly": [0.0, -0.14, 0.07, -0.2, 0.14, -0.14, 0.26, -0.14, 0.42, -0.366, 0.5, -0.366],
				"hlz": [0.0, -0.1, 0.07, -0.3, 0.14, -0.1, 0.26, -0.1, 0.42, -0.08, 0.5, -0.08],
				"hpx": [0.0, -0.6, 0.07, -0.8, 0.14, -0.6, 0.26, -0.6, 0.42, -0.5, 0.5, -0.5],
				"hpy": [0.0, -0.6, 0.07, -0.5, 0.14, -0.6, 0.26, -0.6, 0.42, -0.2, 0.5, -0.2],
				"hpz": [0.0, 0.5, 0.07, 0.5, 0.14, 0.5, 0.26, 0.5, 0.42, 1.0, 0.5, 1.0],
				"hfx": [0.0, -0.85, 0.07, -0.45, 0.14, -0.85, 0.26, -0.85, 0.42, -1.0, 0.5, -1.0],
				"hfy": [0.0, 0.1, 0.07, 0.1, 0.14, 0.1, 0.26, 0.1, 0.42, 0.0, 0.5, 0.0],
				"hfz": [0.0, -0.5, 0.07, -0.9, 0.14, -0.5, 0.26, -0.5, 0.42, -0.35, 0.5, -0.35],
				"az": [0.0, 6.37, 0.017, 9.74, 0.033, 17.72, 0.05, 29.44, 0.062, 34.68, 0.067, 33.43, 0.07, 33.71, 0.083, 29.39, 0.1, 20.89, 0.11, 12.89, 0.117, 11.63, 0.133, 9.35, 0.14, 10.84, 0.15, 12.47, 0.167, 7.0, 0.18, -1.4, 0.183, -4.99, 0.2, -41.82, 0.217, -75.35, 0.233, -80.66, 0.25, -82.73, 0.26, -84.85, 0.267, -84.84, 0.283, -84.77, 0.3, -84.63, 0.317, -84.44, 0.333, -84.21, 0.35, -83.95, 0.367, -83.66, 0.383, -83.36, 0.4, -83.07, 0.417, -82.79, 0.433, -82.54, 0.45, -82.32, 0.467, -82.15, 0.483, -82.04, 0.5, -86.2],
				"e": [0.0, 111.94, 0.017, 118.97, 0.033, 133.58, 0.05, 144.79, 0.062, 146.36, 0.067, 145.46, 0.07, 145.29, 0.083, 140.95, 0.1, 120.95, 0.11, 95.86, 0.117, 85.21, 0.133, 69.56, 0.14, 67.66, 0.15, 65.13, 0.167, 49.85, 0.18, 44.06, 0.183, 40.26, 0.2, 15.15, 0.217, 12.35, 0.233, 12.43, 0.25, 12.71, 0.26, 12.69, 0.267, 12.7, 0.283, 12.83, 0.3, 13.08, 0.317, 13.44, 0.333, 13.87, 0.35, 14.37, 0.367, 14.9, 0.383, 15.45, 0.4, 16.0, 0.417, 16.52, 0.433, 17.0, 0.45, 17.4, 0.467, 17.72, 0.483, 17.93, 0.5, 18.9],
				"r": [0.0, -58.24, 0.017, -54.08, 0.033, -45.26, 0.05, -51.15, 0.062, -50.72, 0.067, -51.71, 0.07, -51.82, 0.083, -55.14, 0.1, -58.43, 0.11, -43.43, 0.117, -34.13, 0.133, -9.61, 0.14, -4.34, 0.15, 2.3, 0.167, 29.3, 0.18, 47.42, 0.183, 48.32, 0.2, 72.71, 0.217, 100.67, 0.233, 101.16, 0.25, 101.38, 0.26, 101.3, 0.267, 100.85, 0.283, 96.1, 0.3, 86.76, 0.317, 73.64, 0.333, 57.52, 0.35, 39.19, 0.367, 19.44, 0.383, -0.93, 0.4, -21.16, 0.417, -40.44, 0.433, -57.97, 0.45, -72.99, 0.467, -84.69, 0.483, -92.29, 0.5, -95.06],
				"el": [0.0, 26.5, 0.017, 23.61, 0.033, 13.64, 0.05, 6.88, 0.062, 6.09, 0.067, 6.21, 0.07, 6.12, 0.083, 6.52, 0.1, 6.59, 0.11, 6.27, 0.117, 6.14, 0.133, 7.13, 0.14, 7.2, 0.15, 7.45, 0.167, 27.78, 0.18, 37.87, 0.183, 40.74, 0.2, 76.03, 0.217, 84.67, 0.233, 85.84, 0.25, 97.76, 0.26, 101.52, 0.267, 101.34, 0.283, 99.41, 0.3, 95.63, 0.317, 90.31, 0.333, 83.78, 0.35, 76.36, 0.367, 68.36, 0.383, 60.1, 0.4, 51.91, 0.417, 44.1, 0.433, 37.0, 0.45, 30.92, 0.467, 26.17, 0.483, 23.1, 0.5, 19.7],
				"uln": [0.0, 59.95, 0.017, 60.4, 0.033, 61.99, 0.05, 63.78, 0.062, 64.23, 0.067, 64.22, 0.07, 64.22, 0.083, 63.97, 0.1, 62.66, 0.11, 61.77, 0.117, 61.51, 0.133, 61.26, 0.14, 61.4, 0.15, 61.51, 0.167, 60.72, 0.18, 60.03, 0.183, 59.57, 0.2, 29.6, 0.217, 18.61, 0.233, 14.36, 0.25, 1.6, 0.26, 1.27, 0.267, 1.41, 0.283, 2.82, 0.3, 5.59, 0.317, 9.48, 0.333, 14.26, 0.35, 19.7, 0.367, 25.56, 0.383, 31.6, 0.4, 37.6, 0.417, 43.32, 0.433, 48.52, 0.45, 52.97, 0.467, 56.44, 0.483, 58.7, 0.5, 58.45],
				"ext": [0.0, 38.23, 0.017, 42.15, 0.033, 47.1, 0.05, 60.07, 0.062, 60.31, 0.067, 60.28, 0.07, 60.3, 0.083, 60.16, 0.1, 54.66, 0.11, 39.5, 0.117, 35.66, 0.133, 20.28, 0.14, 17.13, 0.15, 13.56, 0.167, -5.45, 0.18, -22.21, 0.183, -23.85, 0.2, -12.2, 0.217, -10.67, 0.233, -7.71, 0.25, 18.14, 0.26, 30.68, 0.267, 30.74, 0.283, 31.45, 0.3, 32.85, 0.317, 34.81, 0.333, 37.22, 0.35, 39.95, 0.367, 42.9, 0.383, 45.95, 0.4, 48.97, 0.417, 51.85, 0.433, 54.47, 0.45, 56.71, 0.467, 58.46, 0.483, 59.6, 0.5, 60.02],
				"tw": [0.0, 110.1, 0.017, 110.24, 0.033, 110.49, 0.05, 110.5, 0.062, 110.46, 0.067, 110.47, 0.07, 110.46, 0.083, 110.45, 0.1, 110.24, 0.11, 110.23, 0.117, 110.28, 0.133, 110.45, 0.14, 110.56, 0.15, 110.67, 0.167, 112.47, 0.18, 112.72, 0.183, 112.62, 0.2, 114.12, 0.217, 113.87, 0.233, 113.59, 0.25, 113.73, 0.26, 113.65, 0.267, 113.35, 0.283, 110.11, 0.3, 103.75, 0.317, 94.82, 0.333, 83.85, 0.35, 71.36, 0.367, 57.92, 0.383, 44.05, 0.4, 30.27, 0.417, 17.15, 0.433, 5.21, 0.45, -5.01, 0.467, -12.98, 0.483, -18.16, 0.5, -23.82],
				"feet": {"moves": [{"f": 0, "t0": 0.02, "t1": 0.11, "x": 0.2, "z": -0.26, "yaw": -8.0, "apex": 0.08, "th": 10.0}, {"f": 1, "t0": 0.3, "t1": 0.42, "x": -0.15, "z": -0.06, "yaw": 4.0, "apex": 0.07, "th": 6.0, "near": 0.12}, {"f": 0, "t0": 0.34, "t1": 0.48, "x": 0.15, "z": 0.04, "yaw": -4.0, "apex": 0.07, "th": 6.0}], "pitch1": [0.0, 0.0, 0.08, 0.0, 0.16, -24.0, 0.28, -24.0, 0.34, 0.0], "follow1": [0.0, 0.0, 0.07, 0.0, 0.18, 0.6, 0.3, 0.6]}}
		"b3":
			return {"len": 0.74, "in": 0.07, "out": 0.25, "ev": {"swing": 0.17, "impact": 0.215, "step": [0.215, 0.7]},
				"py": [0.0, -23.062, 0.1, -26.0, 0.165, -28.0, 0.21, 10.0, 0.26, 18.0, 0.4, 16.0, 0.56, 6.0, 0.74, 0.0],
				"cy": [0.0, -46.839, 0.1, -46.0, 0.165, -48.0, 0.215, 18.0, 0.26, 26.0, 0.4, 22.0, 0.56, 8.0, 0.74, 0.0],
				"pp": [0.0, -5.377, 0.1, 4.0, 0.165, 6.0, 0.215, -10.0, 0.4, -10.0, 0.56, -3.0, 0.74, 1.1],
				"cp": [0.0, -14.0, 0.1, 6.0, 0.165, 8.0, 0.215, -18.0, 0.4, -18.0, 0.56, -6.0, 0.74, 4.0],
				"cr": [0.0, -7.448, 0.1, -4.0, 0.165, -4.0, 0.215, 4.0, 0.4, 4.0, 0.74, 0.0],
				"pr": [0.0, -4.0, 0.1, 2.0, 0.215, -3.0, 0.4, -3.0, 0.74, 0.0],
				"px": [0.0, 0.047, 0.1, 0.04, 0.165, 0.05, 0.215, -0.02, 0.4, -0.02, 0.74, 0.0],
				"pz": [0.0, -0.175, 0.1, 0.06, 0.165, 0.08, 0.215, -0.32, 0.4, -0.3, 0.56, -0.1, 0.74, 0.0],
				"pdy": [0.0, -0.138, 0.1, -0.12, 0.165, -0.14, 0.215, -0.22, 0.4, -0.21, 0.56, -0.08, 0.74, 0.0],
				"hy": [0.0, -10.652, 0.1, 4.0, 0.165, 6.0, 0.215, 2.0, 0.4, 2.0, 0.74, 0.0],
				"hp": [0.0, -6.0, 0.1, -2.0, 0.215, -8.0, 0.4, -8.0, 0.74, 0.0],
				"hlx": [0.0, -0.42, 0.1, -0.1, 0.165, -0.1, 0.19, -0.4, 0.215, -0.52, 0.4, -0.52, 0.58, -0.335, 0.74, -0.335],
				"hly": [0.0, -0.14, 0.1, -0.12, 0.165, -0.12, 0.19, -0.08, 0.215, -0.22, 0.4, -0.22, 0.58, -0.366, 0.74, -0.366],
				"hlz": [0.0, -0.1, 0.1, -0.42, 0.165, -0.42, 0.19, -0.12, 0.215, 0.14, 0.4, 0.14, 0.58, -0.08, 0.74, -0.08],
				"hpx": [0.0, -0.6, 0.1, -1.0, 0.165, -1.0, 0.19, -0.7, 0.215, -0.4, 0.4, -0.4, 0.58, -0.5, 0.74, -0.5],
				"hpy": [0.0, -0.6, 0.1, -0.5, 0.165, -0.5, 0.19, -0.5, 0.215, -0.5, 0.4, -0.5, 0.58, -0.2, 0.74, -0.2],
				"hpz": [0.0, 0.5, 0.1, 0.3, 0.165, 0.3, 0.19, 0.6, 0.215, 1.0, 0.4, 1.0, 0.58, 1.0, 0.74, 1.0],
				"hfx": [0.0, -0.85, 0.1, -0.2, 0.165, -0.2, 0.19, -0.7, 0.215, -0.95, 0.4, -0.95, 0.58, -1.0, 0.74, -1.0],
				"hfy": [0.0, 0.1, 0.1, 0.05, 0.165, 0.05, 0.19, 0.05, 0.215, 0.0, 0.4, 0.0, 0.58, 0.0, 0.74, 0.0],
				"hfz": [0.0, -0.5, 0.1, -1.0, 0.165, -1.0, 0.19, -0.35, 0.215, 0.25, 0.4, 0.25, 0.58, -0.35, 0.74, -0.35],
				"az": [0.0, -23.95, 0.017, -29.29, 0.033, -42.64, 0.05, -60.0, 0.067, -77.36, 0.083, -90.71, 0.1, -96.06, 0.117, -99.75, 0.133, -99.18, 0.15, -98.43, 0.165, -98.19, 0.167, -98.1, 0.183, -88.02, 0.2, -61.13, 0.215, -22.56, 0.217, -23.33, 0.233, -27.53, 0.25, -30.18, 0.267, -36.15, 0.283, -41.3, 0.3, -41.73, 0.317, -41.56, 0.333, -41.23, 0.35, -40.78, 0.367, -40.24, 0.383, -39.64, 0.4, -39.01, 0.417, -41.8, 0.433, -49.34, 0.45, -60.39, 0.467, -73.69, 0.483, -87.98, 0.5, -102.02, 0.517, -114.57, 0.533, -124.36, 0.55, -130.16, 0.56, -131.19, 0.567, -130.99, 0.583, -128.93, 0.6, -124.98, 0.617, -119.63, 0.633, -113.35, 0.65, -106.6, 0.667, -99.84, 0.683, -93.56, 0.7, -88.21, 0.717, -84.26, 0.733, -82.2, 0.74, -86.14],
				"e": [0.0, 31.86, 0.017, 32.9, 0.033, 35.49, 0.05, 38.85, 0.067, 42.22, 0.083, 44.81, 0.1, 45.84, 0.117, 41.84, 0.133, 42.36, 0.15, 42.92, 0.165, 43.16, 0.167, 43.21, 0.183, 49.54, 0.2, 66.43, 0.215, 90.65, 0.217, 90.73, 0.233, 89.74, 0.25, 89.22, 0.267, 87.56, 0.283, 86.88, 0.3, 86.35, 0.317, 85.98, 0.333, 85.77, 0.35, 85.66, 0.367, 85.64, 0.383, 85.7, 0.4, 85.82, 0.417, 83.7, 0.433, 77.98, 0.45, 69.6, 0.467, 59.5, 0.483, 48.66, 0.5, 38.0, 0.517, 28.47, 0.533, 21.04, 0.55, 16.65, 0.56, 15.86, 0.567, 15.87, 0.583, 15.96, 0.6, 16.13, 0.617, 16.36, 0.633, 16.64, 0.65, 16.93, 0.667, 17.22, 0.683, 17.5, 0.7, 17.73, 0.717, 17.9, 0.733, 17.99, 0.74, 18.89],
				"r": [0.0, 64.24, 0.017, 66.93, 0.033, 73.66, 0.05, 82.42, 0.067, 91.17, 0.083, 97.9, 0.1, 100.6, 0.117, 100.52, 0.133, 100.69, 0.15, 100.8, 0.165, 100.83, 0.167, 100.77, 0.183, 93.49, 0.2, 74.07, 0.215, 46.23, 0.217, 50.13, 0.233, 52.16, 0.25, 56.7, 0.267, 68.03, 0.283, 72.22, 0.3, 71.63, 0.317, 71.07, 0.333, 70.77, 0.35, 70.6, 0.367, 70.52, 0.383, 70.53, 0.4, 70.6, 0.417, 71.5, 0.433, 73.93, 0.45, 77.49, 0.467, 81.77, 0.483, 86.37, 0.5, 90.9, 0.517, 94.94, 0.533, 98.1, 0.55, 99.96, 0.56, 100.3, 0.567, 99.51, 0.583, 91.31, 0.6, 75.65, 0.617, 54.41, 0.633, 29.47, 0.65, 2.65, 0.667, -24.17, 0.683, -49.12, 0.7, -70.35, 0.717, -86.01, 0.733, -94.22, 0.74, -95.07],
				"el": [0.0, 55.25, 0.017, 59.39, 0.033, 69.72, 0.05, 83.16, 0.067, 96.61, 0.083, 106.94, 0.1, 111.08, 0.117, 112.02, 0.133, 111.51, 0.15, 111.12, 0.165, 111.03, 0.167, 110.92, 0.183, 97.17, 0.2, 60.49, 0.215, 7.88, 0.217, 7.92, 0.233, 7.93, 0.25, 7.91, 0.267, 19.63, 0.283, 31.07, 0.3, 32.94, 0.317, 33.66, 0.333, 34.13, 0.35, 34.49, 0.367, 34.74, 0.383, 34.9, 0.4, 34.97, 0.417, 35.22, 0.433, 35.88, 0.45, 36.86, 0.467, 38.04, 0.483, 39.3, 0.5, 40.54, 0.517, 41.65, 0.533, 42.52, 0.55, 43.03, 0.56, 43.12, 0.567, 43.04, 0.583, 42.15, 0.6, 40.45, 0.617, 38.16, 0.633, 35.46, 0.65, 32.56, 0.667, 29.66, 0.683, 26.96, 0.7, 24.67, 0.717, 22.97, 0.733, 22.08, 0.74, 19.75],
				"uln": [0.0, 50.1, 0.017, 50.84, 0.033, 52.69, 0.05, 55.09, 0.067, 57.5, 0.083, 59.35, 0.1, 60.09, 0.117, 60.06, 0.133, 60.07, 0.15, 60.09, 0.165, 60.09, 0.167, 60.09, 0.183, 60.09, 0.2, 60.1, 0.215, 60.1, 0.217, 60.07, 0.233, 60.09, 0.25, 60.08, 0.267, 59.94, 0.283, 59.55, 0.3, 59.53, 0.317, 59.55, 0.333, 59.57, 0.35, 59.58, 0.367, 59.59, 0.383, 59.59, 0.4, 59.59, 0.417, 59.59, 0.433, 59.58, 0.45, 59.57, 0.467, 59.56, 0.483, 59.55, 0.5, 59.54, 0.517, 59.53, 0.533, 59.52, 0.55, 59.51, 0.56, 59.51, 0.567, 59.51, 0.583, 59.51, 0.6, 59.51, 0.617, 59.51, 0.633, 59.51, 0.65, 59.51, 0.667, 59.51, 0.683, 59.5, 0.7, 59.5, 0.717, 59.5, 0.733, 59.5, 0.74, 58.48],
				"ext": [0.0, -22.52, 0.017, -24.65, 0.033, -29.97, 0.05, -36.9, 0.067, -43.82, 0.083, -49.14, 0.1, -51.27, 0.117, -60.16, 0.133, -60.25, 0.15, -60.26, 0.165, -60.24, 0.167, -60.17, 0.183, -51.71, 0.2, -29.16, 0.215, 3.19, 0.217, 3.0, 0.233, 3.36, 0.25, 3.57, 0.267, 15.33, 0.283, 28.8, 0.3, 31.21, 0.317, 32.06, 0.333, 32.6, 0.35, 33.0, 0.367, 33.28, 0.383, 33.46, 0.4, 33.55, 0.417, 34.36, 0.433, 36.55, 0.45, 39.76, 0.467, 43.62, 0.483, 47.77, 0.5, 51.85, 0.517, 55.49, 0.533, 58.33, 0.55, 60.01, 0.56, 60.31, 0.567, 60.31, 0.583, 60.3, 0.6, 60.27, 0.617, 60.24, 0.633, 60.2, 0.65, 60.16, 0.667, 60.11, 0.683, 60.07, 0.7, 60.04, 0.717, 60.01, 0.733, 60.0, 0.74, 60.02],
				"tw": [0.0, 110.79, 0.017, 103.24, 0.033, 84.38, 0.05, 59.85, 0.067, 35.32, 0.083, 16.47, 0.1, 8.92, 0.117, -3.13, 0.133, -2.78, 0.15, -2.09, 0.165, -1.73, 0.167, -1.66, 0.183, 6.37, 0.2, 27.78, 0.215, 58.48, 0.217, 62.47, 0.233, 65.87, 0.25, 71.24, 0.267, 92.98, 0.283, 108.71, 0.3, 110.01, 0.317, 110.02, 0.333, 110.03, 0.35, 110.03, 0.367, 110.03, 0.383, 110.04, 0.4, 110.04, 0.417, 110.08, 0.433, 110.2, 0.45, 110.37, 0.467, 110.58, 0.483, 110.8, 0.5, 111.02, 0.517, 111.22, 0.533, 111.37, 0.55, 111.46, 0.56, 111.48, 0.567, 110.95, 0.583, 105.42, 0.6, 94.88, 0.617, 80.59, 0.633, 63.79, 0.65, 45.74, 0.667, 27.68, 0.683, 10.89, 0.7, -3.41, 0.717, -13.95, 0.733, -19.47, 0.74, -23.76],
				"feet": {"moves": [{"f": 1, "t0": 0.02, "t1": 0.1, "x": -0.2, "z": -0.1, "yaw": 6.0, "apex": 0.06, "th": 4.0, "near": 0.14}, {"f": 1, "t0": 0.12, "t1": 0.215, "x": -0.2, "z": -0.72, "yaw": 8.0, "apex": 0.12, "th": 10.0}, {"f": 1, "t0": 0.52, "t1": 0.7, "x": -0.15, "z": -0.1, "yaw": 4.0, "apex": 0.08, "th": 5.0}], "pitch0": [0.0, 0.0, 0.18, 0.0, 0.26, -34.0, 0.48, -34.0, 0.66, -4.0], "follow0": [0.0, 0.0, 0.16, 0.0, 0.26, 0.5, 0.4, 0.5]}}
		"dash":
			return {"len": 0.86, "in": 0.05, "out": 0.25, "ev": {"swing": 0.235, "impact": 0.3, "step": [0.3, 0.8]},
				"py": [0.0, 0.0, 0.12, -10.0, 0.22, -14.0, 0.3, 12.0, 0.45, 10.0, 0.65, 3.0, 0.86, 0.0],
				"cy": [0.0, 0.0, 0.12, -24.0, 0.22, -30.0, 0.3, 16.0, 0.45, 12.0, 0.65, 3.0, 0.86, 0.0],
				"pp": [0.0, 4.0, 0.08, 8.0, 0.16, 6.0, 0.22, 10.0, 0.31, -14.0, 0.46, -14.0, 0.65, -4.0, 0.86, 1.1],
				"cp": [0.0, 8.0, 0.1, 14.0, 0.22, 22.0, 0.25, 12.0, 0.31, -30.0, 0.46, -32.0, 0.65, -8.0, 0.86, 4.0],
				"cr": [0.0, 0.0, 0.12, -4.0, 0.22, -6.0, 0.31, 4.0, 0.46, 4.0, 0.86, 0.0],
				"pr": [0.0, 0.0, 0.12, -2.0, 0.31, 3.0, 0.46, 3.0, 0.86, 0.0],
				"px": [0.0, 0.0, 0.12, 0.02, 0.31, -0.03, 0.46, -0.03, 0.7, 0.0, 0.86, 0.0],
				"pz": [0.0, 0.0, 0.06, 0.04, 0.22, -0.04, 0.31, -0.24, 0.46, -0.22, 0.66, -0.06, 0.86, 0.0],
				"pdy": [0.0, -0.06, 0.06, -0.1, 0.14, 0.14, 0.22, 0.22, 0.27, 0.12, 0.315, -0.3, 0.46, -0.29, 0.64, -0.12, 0.86, 0.0],
				"hy": [0.0, 0.0, 0.12, -4.0, 0.31, 2.0, 0.86, 0.0],
				"hp": [0.0, 0.0, 0.14, -4.0, 0.22, -8.0, 0.31, -14.0, 0.46, -16.0, 0.66, -4.0, 0.86, 0.0],
				"hlx": [0.0, -0.335, 0.1, -0.44, 0.22, -0.52, 0.31, -0.46, 0.46, -0.46, 0.66, -0.335, 0.86, -0.335],
				"hly": [0.0, -0.366, 0.1, -0.1, 0.22, 0.02, 0.31, -0.3, 0.46, -0.3, 0.66, -0.366, 0.86, -0.366],
				"hlz": [0.0, -0.08, 0.1, -0.02, 0.22, 0.06, 0.31, 0.16, 0.46, 0.16, 0.66, -0.08, 0.86, -0.08],
				"hpx": [0.0, -0.5, 0.1, -0.5, 0.22, -0.4, 0.31, -0.4, 0.46, -0.4, 0.66, -0.5, 0.86, -0.5],
				"hpy": [0.0, -0.2, 0.1, -0.6, 0.22, -0.6, 0.31, -0.5, 0.46, -0.5, 0.66, -0.2, 0.86, -0.2],
				"hpz": [0.0, 1.0, 0.1, 0.6, 0.22, 0.7, 0.31, 1.0, 0.46, 1.0, 0.66, 1.0, 0.86, 1.0],
				"hfx": [0.0, -1.0, 0.1, -0.9, 0.22, -0.95, 0.31, -0.95, 0.46, -0.95, 0.66, -1.0, 0.86, -1.0],
				"hfy": [0.0, 0.0, 0.1, 0.2, 0.22, 0.3, 0.31, 0.0, 0.46, 0.0, 0.66, 0.0, 0.86, 0.0],
				"hfz": [0.0, -0.35, 0.1, -0.3, 0.22, -0.1, 0.31, 0.25, 0.46, 0.25, 0.66, -0.35, 0.86, -0.35],
				"f0x": [0.0, 0.15, 0.08, 0.15, 0.2, 0.14, 0.3, 0.22, 0.64, 0.22, 0.78, 0.15, 0.86, 0.15],
				"f0y": [0.0, 0.093, 0.04, 0.1, 0.1, 0.2, 0.2, 0.42, 0.27, 0.22, 0.31, 0.093, 0.64, 0.093, 0.71, 0.16, 0.78, 0.093, 0.86, 0.093],
				"f0z": [0.0, 0.04, 0.08, 0.1, 0.2, -0.22, 0.3, 0.26, 0.64, 0.26, 0.78, 0.04, 0.86, 0.04],
				"f0p": [0.0, 0.0, 0.06, -30.0, 0.12, -40.0, 0.22, 10.0, 0.3, 0.0, 0.31, -10.0, 0.64, -10.0, 0.7, -20.0, 0.78, 6.0, 0.86, 0.0],
				"f0w": [0.0, -10.0, 0.3, -14.0, 0.64, -14.0, 0.86, -10.0],
				"f1x": [0.0, -0.15, 0.2, -0.14, 0.3, -0.24, 0.64, -0.24, 0.78, -0.15, 0.86, -0.15],
				"f1y": [0.0, 0.093, 0.06, 0.12, 0.14, 0.3, 0.22, 0.34, 0.27, 0.2, 0.3, 0.093, 0.64, 0.093, 0.71, 0.15, 0.78, 0.093, 0.86, 0.093],
				"f1z": [0.0, -0.06, 0.14, 0.18, 0.22, 0.2, 0.3, -0.56, 0.64, -0.56, 0.78, -0.08, 0.86, -0.06],
				"f1p": [0.0, 0.0, 0.1, -20.0, 0.22, -30.0, 0.28, 10.0, 0.31, 0.0, 0.64, 0.0, 0.7, -10.0, 0.78, 4.0, 0.86, 0.0],
				"f1w": [0.0, 10.0, 0.3, 12.0, 0.64, 12.0, 0.86, 10.0],
				"az": [0.0, -81.36, 0.017, -82.92, 0.033, -86.82, 0.05, -91.9, 0.067, -96.97, 0.083, -100.87, 0.1, -102.43, 0.117, -87.82, 0.133, -75.87, 0.15, -66.57, 0.167, -59.93, 0.183, -55.95, 0.2, -54.62, 0.217, -55.82, 0.225, -56.53, 0.233, -59.04, 0.25, -60.32, 0.267, -56.86, 0.283, -51.26, 0.285, -48.29, 0.3, -41.58, 0.31, -38.17, 0.317, -38.0, 0.333, -37.68, 0.35, -37.32, 0.367, -37.02, 0.383, -36.67, 0.4, -36.38, 0.417, -36.07, 0.433, -35.82, 0.45, -35.61, 0.467, -35.43, 0.48, -35.59, 0.483, -35.7, 0.5, -39.27, 0.517, -47.03, 0.533, -57.81, 0.55, -70.46, 0.567, -83.8, 0.583, -96.67, 0.6, -107.91, 0.617, -116.37, 0.633, -120.87, 0.64, -121.31, 0.65, -121.07, 0.667, -119.71, 0.683, -117.33, 0.7, -114.13, 0.717, -110.31, 0.733, -106.09, 0.75, -101.65, 0.767, -97.22, 0.783, -92.99, 0.8, -89.18, 0.817, -85.97, 0.833, -83.59, 0.85, -82.24, 0.86, -86.5],
				"e": [0.0, 19.38, 0.017, 19.32, 0.033, 19.19, 0.05, 19.01, 0.067, 18.84, 0.083, 18.7, 0.1, 18.65, 0.117, 49.91, 0.133, 75.47, 0.15, 95.36, 0.167, 109.57, 0.183, 118.09, 0.2, 120.93, 0.217, 122.18, 0.225, 122.61, 0.233, 124.23, 0.25, 123.51, 0.267, 102.88, 0.283, 62.62, 0.285, 53.62, 0.3, 40.45, 0.31, 39.1, 0.317, 39.05, 0.333, 38.86, 0.35, 38.74, 0.367, 38.68, 0.383, 38.63, 0.4, 38.65, 0.417, 38.6, 0.433, 38.65, 0.45, 38.75, 0.467, 38.85, 0.48, 38.64, 0.483, 38.61, 0.5, 37.59, 0.517, 35.38, 0.533, 32.31, 0.55, 28.71, 0.567, 24.91, 0.583, 21.24, 0.6, 18.04, 0.617, 15.63, 0.633, 14.34, 0.64, 14.22, 0.65, 14.24, 0.667, 14.37, 0.683, 14.6, 0.7, 14.91, 0.717, 15.28, 0.733, 15.68, 0.75, 16.11, 0.767, 16.54, 0.783, 16.94, 0.8, 17.31, 0.817, 17.62, 0.833, 17.85, 0.85, 17.98, 0.86, 18.92],
				"r": [0.0, -95.36, 0.017, -84.83, 0.033, -58.53, 0.05, -24.32, 0.067, 9.89, 0.083, 36.19, 0.1, 46.72, 0.117, 42.98, 0.133, 39.92, 0.15, 37.54, 0.167, 35.84, 0.183, 34.82, 0.2, 34.48, 0.217, 37.09, 0.225, 36.88, 0.233, 37.31, 0.25, 49.15, 0.267, 63.83, 0.283, 68.93, 0.285, 60.32, 0.3, 57.01, 0.31, 55.49, 0.317, 55.29, 0.333, 54.91, 0.35, 54.65, 0.367, 54.64, 0.383, 54.6, 0.4, 54.76, 0.417, 54.8, 0.433, 55.03, 0.45, 55.35, 0.467, 55.79, 0.48, 56.7, 0.483, 56.75, 0.5, 58.57, 0.517, 62.51, 0.533, 67.99, 0.55, 74.42, 0.567, 81.2, 0.583, 87.74, 0.6, 93.45, 0.617, 97.75, 0.633, 100.04, 0.64, 100.26, 0.65, 99.09, 0.667, 92.35, 0.683, 80.52, 0.7, 64.61, 0.717, 45.64, 0.733, 24.65, 0.75, 2.63, 0.767, -19.39, 0.783, -40.38, 0.8, -59.35, 0.817, -75.26, 0.833, -87.09, 0.85, -93.83, 0.86, -95.1],
				"el": [0.0, 26.74, 0.017, 30.12, 0.033, 38.55, 0.05, 49.53, 0.067, 60.51, 0.083, 68.95, 0.1, 72.32, 0.117, 85.04, 0.133, 95.43, 0.15, 103.53, 0.167, 109.3, 0.183, 112.77, 0.2, 113.93, 0.217, 113.78, 0.225, 113.76, 0.233, 113.16, 0.25, 107.74, 0.267, 94.14, 0.283, 63.53, 0.285, 61.19, 0.3, 53.88, 0.31, 51.95, 0.317, 52.04, 0.333, 52.45, 0.35, 52.77, 0.367, 53.07, 0.383, 53.34, 0.4, 53.54, 0.417, 53.8, 0.433, 53.96, 0.45, 54.05, 0.467, 54.07, 0.48, 54.05, 0.483, 54.05, 0.5, 54.15, 0.517, 54.37, 0.533, 54.68, 0.55, 55.04, 0.567, 55.42, 0.583, 55.78, 0.6, 56.1, 0.617, 56.34, 0.633, 56.47, 0.64, 56.48, 0.65, 56.27, 0.667, 55.08, 0.683, 52.99, 0.7, 50.18, 0.717, 46.84, 0.733, 43.13, 0.75, 39.24, 0.767, 35.35, 0.783, 31.64, 0.8, 28.29, 0.817, 25.49, 0.833, 23.4, 0.85, 22.21, 0.86, 19.49],
				"uln": [0.0, 59.97, 0.017, 56.01, 0.033, 46.1, 0.05, 33.22, 0.067, 20.33, 0.083, 10.43, 0.1, 6.46, 0.117, 5.68, 0.133, 5.04, 0.15, 4.55, 0.167, 4.19, 0.183, 3.98, 0.2, 3.91, 0.217, 2.0, 0.225, 2.0, 0.233, 2.0, 0.25, 7.84, 0.267, 27.06, 0.283, 52.86, 0.285, 59.3, 0.3, 60.31, 0.31, 60.49, 0.317, 60.5, 0.333, 60.53, 0.35, 60.56, 0.367, 60.58, 0.383, 60.6, 0.4, 60.62, 0.417, 60.63, 0.433, 60.64, 0.45, 60.64, 0.467, 60.65, 0.48, 60.65, 0.483, 60.64, 0.5, 60.3, 0.517, 59.56, 0.533, 58.52, 0.55, 57.31, 0.567, 56.03, 0.583, 54.8, 0.6, 53.72, 0.617, 52.9, 0.633, 52.47, 0.64, 52.43, 0.65, 52.47, 0.667, 52.72, 0.683, 53.15, 0.7, 53.72, 0.717, 54.41, 0.733, 55.17, 0.75, 55.97, 0.767, 56.76, 0.783, 57.52, 0.8, 58.21, 0.817, 58.79, 0.833, 59.21, 0.85, 59.46, 0.86, 58.3],
				"ext": [0.0, 60.51, 0.017, 51.46, 0.033, 28.84, 0.05, -0.57, 0.067, -29.99, 0.083, -52.6, 0.1, -61.65, 0.117, -24.48, 0.133, 5.92, 0.15, 29.58, 0.167, 46.47, 0.183, 56.6, 0.2, 59.98, 0.217, 60.12, 0.225, 60.12, 0.233, 60.1, 0.25, 59.53, 0.267, 58.62, 0.283, 53.54, 0.285, 60.02, 0.3, 57.1, 0.31, 55.9, 0.317, 56.03, 0.333, 56.44, 0.35, 56.81, 0.367, 57.05, 0.383, 57.4, 0.4, 57.59, 0.417, 57.96, 0.433, 58.15, 0.45, 58.23, 0.467, 58.28, 0.48, 58.26, 0.483, 58.26, 0.5, 58.35, 0.517, 58.54, 0.533, 58.79, 0.55, 59.1, 0.567, 59.42, 0.583, 59.73, 0.6, 60.0, 0.617, 60.2, 0.633, 60.31, 0.64, 60.32, 0.65, 60.31, 0.667, 60.3, 0.683, 60.28, 0.7, 60.26, 0.717, 60.23, 0.733, 60.19, 0.75, 60.16, 0.767, 60.12, 0.783, 60.09, 0.8, 60.06, 0.817, 60.03, 0.833, 60.01, 0.85, 60.0, 0.86, 60.02],
				"tw": [0.0, -21.26, 0.017, -12.49, 0.033, 9.42, 0.05, 37.91, 0.067, 66.41, 0.083, 88.32, 0.1, 97.09, 0.117, 96.09, 0.133, 95.27, 0.15, 94.63, 0.167, 94.18, 0.183, 93.9, 0.2, 93.81, 0.217, 97.56, 0.225, 97.98, 0.233, 99.07, 0.25, 105.41, 0.267, 110.12, 0.283, 110.5, 0.285, 110.15, 0.3, 110.67, 0.31, 110.74, 0.317, 110.75, 0.333, 110.78, 0.35, 110.81, 0.367, 110.84, 0.383, 110.86, 0.4, 110.88, 0.417, 110.89, 0.433, 110.9, 0.45, 110.91, 0.467, 110.92, 0.48, 110.92, 0.483, 110.92, 0.5, 110.99, 0.517, 111.13, 0.533, 111.32, 0.55, 111.55, 0.567, 111.79, 0.583, 112.02, 0.6, 112.23, 0.617, 112.38, 0.633, 112.46, 0.64, 112.47, 0.65, 111.67, 0.667, 107.1, 0.683, 99.08, 0.7, 88.28, 0.717, 75.42, 0.733, 61.17, 0.75, 46.23, 0.767, 31.29, 0.783, 17.05, 0.8, 4.18, 0.817, -6.61, 0.833, -14.63, 0.85, -19.2, 0.86, -24.19],
				"feet": {"mode": "baked"}}
		"heavy":
			return {"len": 1.0, "in": 0.06, "out": 0.25, "ev": {"swing": 0.34, "impact": 0.47, "step": [0.4, 0.72]},
				"pivx": 0.26,
				"pivz": -0.02,
				"rot": [0.0, 0.0, 0.3, 0.0, 0.31, -0.97, 0.32, -3.87, 0.33, -8.71, 0.34, -15.48, 0.35, -24.19, 0.36, -34.84, 0.37, -46.45, 0.38, -58.06, 0.39, -69.68, 0.4, -81.29, 0.41, -92.9, 0.42, -104.52, 0.43, -116.13, 0.44, -127.74, 0.45, -139.35, 0.46, -150.97, 0.47, -162.58, 0.48, -174.19, 0.49, -185.81, 0.5, -197.42, 0.51, -209.03, 0.52, -220.65, 0.53, -232.26, 0.54, -243.87, 0.55, -255.48, 0.56, -267.1, 0.57, -278.35, 0.58, -288.87, 0.59, -298.67, 0.6, -307.74, 0.61, -316.09, 0.62, -323.71, 0.63, -330.6, 0.64, -336.77, 0.65, -342.22, 0.66, -346.94, 0.67, -350.93, 0.68, -354.19, 0.69, -356.73, 0.7, -358.55, 0.71, -359.64, 0.72, -360.0, 1.0, -360.0],
				"py": [0.0, 0.0, 0.16, 16.0, 0.3, 24.0, 0.36, 18.0, 0.46, -6.0, 0.6, -10.0, 0.72, -14.0, 0.85, -10.0, 1.0, 0.0],
				"cy": [0.0, 0.0, 0.16, 40.0, 0.3, 62.0, 0.36, 50.0, 0.46, -2.0, 0.6, -20.0, 0.72, -28.0, 0.85, -20.0, 1.0, 0.0],
				"pp": [0.0, 1.1, 0.3, 6.0, 0.4, -4.0, 0.72, -8.0, 0.85, -6.0, 1.0, 1.1],
				"cp": [0.0, 4.0, 0.3, 14.0, 0.4, 6.0, 0.6, 0.0, 0.72, -10.0, 0.85, -8.0, 1.0, 4.0],
				"cr": [0.0, 0.0, 0.3, 8.0, 0.45, -6.0, 0.72, -8.0, 1.0, 0.0],
				"pr": [0.0, 0.0, 0.3, 4.0, 0.45, -4.0, 0.72, -4.0, 1.0, 0.0],
				"px": [0.0, 0.0, 0.2, 0.02, 0.3, 0.04, 0.38, 0.1, 0.66, 0.1, 0.74, 0.04, 0.9, 0.01, 1.0, 0.0],
				"pz": [0.0, 0.0, 0.2, 0.02, 0.3, 0.0, 0.38, -0.02, 0.66, -0.02, 0.74, -0.06, 0.9, -0.02, 1.0, 0.0],
				"pdy": [0.0, 0.0, 0.16, -0.12, 0.3, -0.17, 0.38, -0.12, 0.66, -0.12, 0.74, -0.19, 0.85, -0.18, 0.95, -0.05, 1.0, 0.0],
				"hy": [0.0, 0.0, 0.16, 8.0, 0.3, 12.0, 0.4, -10.0, 0.72, -16.0, 0.85, -10.0, 1.0, 0.0],
				"hp": [0.0, 0.0, 0.3, -6.0, 0.5, -4.0, 0.72, -8.0, 1.0, 0.0],
				"hlx": [0.0, -0.335, 0.16, -0.12, 0.3, -0.08, 0.4, -0.42, 0.66, -0.46, 0.85, -0.42, 1.0, -0.335],
				"hly": [0.0, -0.366, 0.16, -0.16, 0.3, -0.17, 0.4, -0.14, 0.66, -0.3, 0.85, -0.14, 1.0, -0.366],
				"hlz": [0.0, -0.08, 0.16, -0.52, 0.3, -0.55, 0.4, -0.1, 0.66, 0.16, 0.85, -0.1, 1.0, -0.08],
				"hpx": [0.0, -0.5, 0.16, -1.0, 0.3, -1.0, 0.4, -0.6, 0.66, -0.4, 0.85, -0.6, 1.0, -0.5],
				"hpy": [0.0, -0.2, 0.16, -0.5, 0.3, -0.5, 0.4, -0.6, 0.66, -0.5, 0.85, -0.6, 1.0, -0.2],
				"hpz": [0.0, 1.0, 0.16, 0.3, 0.3, 0.3, 0.4, 0.5, 0.66, 1.0, 0.85, 0.5, 1.0, 1.0],
				"hfx": [0.0, -1.0, 0.16, -0.1, 0.3, 0.05, 0.4, -0.85, 0.66, -0.95, 0.85, -0.85, 1.0, -1.0],
				"hfy": [0.0, 0.0, 0.16, 0.0, 0.3, 0.0, 0.4, 0.1, 0.66, 0.0, 0.85, 0.1, 1.0, 0.0],
				"hfz": [0.0, -0.35, 0.16, -1.0, 0.3, -1.0, 0.4, -0.5, 0.66, 0.25, 0.85, -0.5, 1.0, -0.35],
				"f0x": [0.0, 0.15, 0.16, 0.26, 0.3, 0.26, 0.34, 0.26, 0.72, 0.26, 0.78, 0.26, 0.92, 0.26, 1.0, 0.15],
				"f0y": [0.0, 0.093, 0.08, 0.16, 0.16, 0.093, 0.3, 0.093, 0.34, 0.195, 0.72, 0.195, 0.78, 0.093, 0.92, 0.093, 0.96, 0.13, 1.0, 0.093],
				"f0z": [0.0, 0.04, 0.16, 0.2, 0.3, 0.2, 0.34, 0.117, 0.72, 0.117, 0.78, 0.2, 0.92, 0.2, 1.0, 0.04],
				"f0p": [0.0, 0.0, 0.16, 0.0, 0.3, 0.0, 0.34, -32.0, 0.72, -32.0, 0.78, 0.0, 1.0, 0.0],
				"f0w": [0.0, -10.0, 0.16, -14.0, 0.72, -14.0, 1.0, -10.0],
				"f1x": [0.0, -0.15, 0.16, -0.26, 0.3, -0.26, 0.4, -0.12, 0.64, -0.12, 0.72, -0.26, 0.9, -0.26, 1.0, -0.15],
				"f1y": [0.0, 0.093, 0.08, 0.17, 0.16, 0.093, 0.3, 0.093, 0.4, 0.26, 0.64, 0.26, 0.72, 0.093, 0.9, 0.093, 0.95, 0.14, 1.0, 0.093],
				"f1z": [0.0, -0.06, 0.16, -0.36, 0.3, -0.36, 0.4, -0.1, 0.64, -0.1, 0.72, -0.36, 0.9, -0.36, 1.0, -0.06],
				"f1p": [0.0, 0.0, 0.3, 0.0, 0.4, -40.0, 0.64, -40.0, 0.7, 8.0, 0.74, 0.0, 1.0, 0.0],
				"f1w": [0.0, 10.0, 0.16, 16.0, 0.72, 16.0, 1.0, 10.0],
				"az": [0.0, -83.19, 0.017, -81.6, 0.033, -77.29, 0.05, -70.99, 0.067, -63.39, 0.083, -55.23, 0.1, -47.21, 0.117, -40.05, 0.133, -34.46, 0.15, -31.15, 0.16, -30.56, 0.167, -28.87, 0.183, -25.0, 0.2, -21.64, 0.217, -18.8, 0.233, -16.48, 0.25, -14.68, 0.267, -13.38, 0.283, -12.61, 0.3, -12.35, 0.317, -13.3, 0.333, -17.08, 0.35, -28.68, 0.36, -36.06, 0.367, -41.15, 0.383, -51.63, 0.4, -59.43, 0.417, -65.77, 0.433, -71.8, 0.45, -78.99, 0.46, -84.36, 0.467, -84.81, 0.483, -86.28, 0.5, -87.89, 0.517, -89.52, 0.533, -91.13, 0.55, -92.64, 0.567, -94.0, 0.583, -95.12, 0.6, -95.97, 0.617, -96.4, 0.633, -96.37, 0.65, -96.02, 0.667, -95.48, 0.683, -94.89, 0.7, -94.39, 0.717, -94.11, 0.72, -94.11, 0.733, -94.93, 0.75, -96.24, 0.767, -97.73, 0.783, -99.36, 0.8, -101.05, 0.817, -102.75, 0.833, -104.33, 0.85, -105.76, 0.867, -104.95, 0.883, -102.77, 0.9, -99.6, 0.917, -95.85, 0.933, -91.91, 0.95, -88.16, 0.967, -85.0, 0.983, -82.82, 1.0, -84.68],
				"e": [0.0, 18.66, 0.017, 19.0, 0.033, 19.92, 0.05, 21.26, 0.067, 22.87, 0.083, 24.6, 0.1, 26.3, 0.117, 27.82, 0.133, 29.01, 0.15, 29.71, 0.16, 29.84, 0.167, 31.53, 0.183, 35.4, 0.2, 38.75, 0.217, 41.59, 0.233, 43.91, 0.25, 45.72, 0.267, 47.01, 0.283, 47.78, 0.3, 48.04, 0.317, 49.04, 0.333, 48.1, 0.35, 50.4, 0.36, 54.85, 0.367, 54.61, 0.383, 55.28, 0.4, 57.3, 0.417, 60.54, 0.433, 64.71, 0.45, 69.29, 0.46, 72.04, 0.467, 72.67, 0.483, 74.34, 0.5, 75.93, 0.517, 77.4, 0.533, 78.73, 0.55, 79.92, 0.567, 80.95, 0.583, 81.83, 0.6, 82.56, 0.617, 83.12, 0.633, 83.51, 0.65, 83.79, 0.667, 83.98, 0.683, 84.12, 0.7, 84.22, 0.717, 84.26, 0.72, 84.26, 0.733, 84.24, 0.75, 84.0, 0.767, 83.57, 0.783, 82.99, 0.8, 82.3, 0.817, 81.52, 0.833, 80.67, 0.85, 79.8, 0.867, 77.68, 0.883, 72.0, 0.9, 63.78, 0.917, 54.03, 0.933, 43.77, 0.95, 34.02, 0.967, 25.8, 0.983, 20.12, 1.0, 18.82],
				"r": [0.0, -95.07, 0.017, -89.15, 0.033, -73.15, 0.05, -49.72, 0.067, -21.51, 0.083, 8.81, 0.1, 38.61, 0.117, 65.23, 0.133, 85.99, 0.15, 98.29, 0.16, 100.48, 0.167, 100.46, 0.183, 100.39, 0.2, 100.34, 0.217, 100.29, 0.233, 100.25, 0.25, 100.22, 0.267, 100.2, 0.283, 100.19, 0.3, 100.19, 0.317, 100.02, 0.333, 90.34, 0.35, 75.08, 0.36, 62.24, 0.367, 62.13, 0.383, 61.78, 0.4, 60.83, 0.417, 59.09, 0.433, 55.65, 0.45, 49.94, 0.46, 44.71, 0.467, 44.25, 0.483, 43.72, 0.5, 43.23, 0.517, 42.66, 0.533, 42.02, 0.55, 41.27, 0.567, 40.44, 0.583, 39.5, 0.6, 38.47, 0.617, 37.16, 0.633, 35.41, 0.65, 33.43, 0.667, 31.44, 0.683, 29.67, 0.7, 28.32, 0.717, 27.64, 0.72, 27.62, 0.733, 27.35, 0.75, 27.19, 0.767, 27.06, 0.783, 27.04, 0.8, 27.11, 0.817, 27.23, 0.833, 27.27, 0.85, 27.3, 0.867, 23.1, 0.883, 11.87, 0.9, -4.41, 0.917, -23.71, 0.933, -44.0, 0.95, -63.29, 0.967, -79.57, 0.983, -90.8, 1.0, -95.1],
				"el": [0.0, 21.68, 0.017, 22.68, 0.033, 25.38, 0.05, 29.34, 0.067, 34.09, 0.083, 39.21, 0.1, 44.23, 0.117, 48.72, 0.133, 52.23, 0.15, 54.3, 0.16, 54.67, 0.167, 55.88, 0.183, 58.63, 0.2, 61.02, 0.217, 63.04, 0.233, 64.69, 0.25, 65.97, 0.267, 66.89, 0.283, 67.44, 0.3, 67.62, 0.317, 64.74, 0.333, 57.62, 0.35, 56.17, 0.36, 55.62, 0.367, 54.71, 0.383, 53.05, 0.4, 51.42, 0.417, 49.56, 0.433, 47.47, 0.45, 45.18, 0.46, 43.66, 0.467, 43.61, 0.483, 43.57, 0.5, 43.57, 0.517, 43.57, 0.533, 43.57, 0.55, 43.58, 0.567, 43.6, 0.583, 43.6, 0.6, 43.61, 0.617, 43.63, 0.633, 43.66, 0.65, 43.68, 0.667, 43.68, 0.683, 43.67, 0.7, 43.65, 0.717, 43.61, 0.72, 43.61, 0.733, 43.55, 0.75, 43.54, 0.767, 43.54, 0.783, 43.53, 0.8, 43.52, 0.817, 43.52, 0.833, 43.53, 0.85, 43.53, 0.867, 42.79, 0.883, 40.81, 0.9, 37.95, 0.917, 34.55, 0.933, 30.98, 0.95, 27.58, 0.967, 24.72, 0.983, 22.74, 1.0, 20.93],
				"uln": [0.0, 59.52, 0.017, 58.82, 0.033, 56.93, 0.05, 54.17, 0.067, 50.84, 0.083, 47.26, 0.1, 43.75, 0.117, 40.61, 0.133, 38.16, 0.15, 36.71, 0.16, 36.45, 0.167, 38.61, 0.183, 43.55, 0.2, 47.84, 0.217, 51.46, 0.233, 54.43, 0.25, 56.73, 0.267, 58.38, 0.283, 59.37, 0.3, 59.7, 0.317, 59.88, 0.333, 59.81, 0.35, 59.6, 0.36, 59.57, 0.367, 59.57, 0.383, 59.56, 0.4, 59.55, 0.417, 59.54, 0.433, 59.54, 0.45, 59.54, 0.46, 59.52, 0.467, 59.5, 0.483, 59.49, 0.5, 59.48, 0.517, 59.48, 0.533, 59.49, 0.55, 59.5, 0.567, 59.5, 0.583, 59.5, 0.6, 59.5, 0.617, 59.51, 0.633, 59.51, 0.65, 59.51, 0.667, 59.51, 0.683, 59.51, 0.7, 59.51, 0.717, 59.5, 0.72, 59.5, 0.733, 59.5, 0.75, 59.49, 0.767, 59.45, 0.783, 59.42, 0.8, 59.38, 0.817, 59.31, 0.833, 59.15, 0.85, 58.97, 0.867, 58.98, 0.883, 59.03, 0.9, 59.1, 0.917, 59.19, 0.933, 59.28, 0.95, 59.36, 0.967, 59.43, 0.983, 59.48, 1.0, 59.4],
				"ext": [0.0, 60.03, 0.017, 57.81, 0.033, 51.82, 0.05, 43.03, 0.067, 32.46, 0.083, 21.09, 0.1, 9.92, 0.117, -0.06, 0.133, -7.84, 0.15, -12.45, 0.16, -13.28, 0.167, -14.22, 0.183, -16.37, 0.2, -18.24, 0.217, -19.82, 0.233, -21.12, 0.25, -22.12, 0.267, -22.84, 0.283, -23.27, 0.3, -23.42, 0.317, -19.82, 0.333, -19.43, 0.35, -23.21, 0.36, -26.13, 0.367, -28.4, 0.383, -33.83, 0.4, -38.38, 0.417, -41.74, 0.433, -44.08, 0.45, -45.49, 0.46, -45.94, 0.467, -45.92, 0.483, -45.88, 0.5, -45.88, 0.517, -45.88, 0.533, -45.89, 0.55, -45.91, 0.567, -45.94, 0.583, -45.94, 0.6, -45.94, 0.617, -45.98, 0.633, -46.01, 0.65, -46.03, 0.667, -46.03, 0.683, -46.02, 0.7, -45.99, 0.717, -45.95, 0.72, -45.95, 0.733, -45.89, 0.75, -45.87, 0.767, -45.84, 0.783, -45.81, 0.8, -45.77, 0.817, -45.72, 0.833, -45.64, 0.85, -45.52, 0.867, -41.9, 0.883, -32.21, 0.9, -18.16, 0.917, -1.51, 0.933, 15.99, 0.95, 32.64, 0.967, 46.69, 0.983, 56.38, 1.0, 59.91],
				"tw": [0.0, -20.62, 0.017, -21.46, 0.033, -23.71, 0.05, -27.02, 0.067, -31.0, 0.083, -35.27, 0.1, -39.47, 0.117, -43.23, 0.133, -46.16, 0.15, -47.89, 0.16, -48.2, 0.167, -47.38, 0.183, -45.51, 0.2, -43.88, 0.217, -42.51, 0.233, -41.39, 0.25, -40.51, 0.267, -39.89, 0.283, -39.51, 0.3, -39.39, 0.317, -34.75, 0.333, -36.81, 0.35, -43.14, 0.36, -46.7, 0.367, -51.68, 0.383, -63.52, 0.4, -74.44, 0.417, -84.11, 0.433, -92.99, 0.45, -101.52, 0.46, -107.22, 0.467, -107.58, 0.483, -107.72, 0.5, -107.73, 0.517, -107.73, 0.533, -107.7, 0.55, -107.68, 0.567, -107.65, 0.583, -107.64, 0.6, -107.63, 0.617, -107.59, 0.633, -107.55, 0.65, -107.53, 0.667, -107.53, 0.683, -107.54, 0.7, -107.57, 0.717, -107.62, 0.72, -107.62, 0.733, -107.68, 0.75, -107.7, 0.767, -107.77, 0.783, -107.84, 0.8, -107.92, 0.817, -108.05, 0.833, -108.33, 0.85, -108.68, 0.867, -105.63, 0.883, -97.49, 0.9, -85.69, 0.917, -71.69, 0.933, -56.98, 0.95, -42.99, 0.967, -31.19, 0.983, -23.04, 1.0, -22.23],
				"feet": {"mode": "baked"}}
	return {}


## The strikes that are built from joint angles (the others still play their keys).
const STRIKE_NAMES := ["a1", "a2", "a3", "a4", "b1", "b2", "b3", "dash", "heavy"]


## The old blow names still play (tools, older callers): attack1/attack2/attack3 are combo A's first, second and last blow.
const STRIKE_ALIAS := {"attack1": "a1", "attack2": "a2", "attack3": "a4"}


# --- a blow that starts on the run ---------------------------------------------------------------------------------------------
## A blow that starts while the hero runs and carries the run on (HeroMelee: no foe in reach, so the run slows at 13 m/s^2
## instead of stopping; it says so with set_strike_run, and play() guesses it from the speed, faster than SK_RUN_V m/s, when
## nobody does) keeps its legs on the gait: the stride goes on under the swing and stops the way a run stops, instead of the
## feet being planted in the world and dragged along. The blow owns the chest, the head and the arms (as authored, in the
## world), the turn of the pelvis (mostly) and nothing of the legs. A blow with a foe in reach (the hero stops dead and
## lunges, 15 m/s for a moment: no gait follows that) plants its feet itself, as from a standstill. The heavy's charge (the
## hero plays its coil with the legs on the locomotion and holds it at 0.3 s) is layered the same way, so the chest keeps
## the wind-up it was authored with.
const SK_RUN_V := 2.5
var _sk_run := false
var _skl_on := false


## HeroMelee, right after it has aimed the blow it started: whether the run is carried on (the legs stay on the gait) or not.
func set_strike_run(on: bool) -> void:
	if action != "" and act_def(_akey).has("strike") and not _strike_own_legs(act_def(_akey)["strike"]):
		_sk_run = on


## A blow whose legs are its own (the heavy's spin, the dash's leap: the feet are baked into it) never runs on the gait.
static func _strike_own_legs(S: Dictionary) -> bool:
	return S.has("rot") or String((S.get("feet", {}) as Dictionary).get("mode", "")) == "baked"


func _strike_layer(c: PackedFloat32Array, loco: PackedFloat32Array) -> void:
	var pb_s := eul(v3(c, C_PELR))
	var tb := pb_s * eul(v3(c, C_SPN)) * eul(v3(c, C_CHS))
	# the heavy's held coil keeps its own wide, low stance (P5) while he stands; walking, the legs are the gait's
	var own := 0.0
	if _upper > 0.0 and _strike_own_legs(act_def(_akey)["strike"]):
		own = 1.0 - smoothstep(0.25, 0.9, _spd)
	for o in LOWER_CH:
		c[o] = lerpf(loco[o], c[o], own)
		c[o + 1] = lerpf(loco[o + 1], c[o + 1], own)
		c[o + 2] = lerpf(loco[o + 2], c[o + 2], own)
	var ps := v3(c, C_PELR)
	var pl := v3(loco, C_PELR)
	var pe := Vector3(lerpf(ps.x, pl.x, 0.5 * (1.0 - own)), lerpf(ps.y, pl.y, 0.1 * (1.0 - own)), lerpf(ps.z, pl.z, 0.5 * (1.0 - own)))
	_setv(c, C_PELR, pe)
	# the chest keeps the orientation the blow gave it in the world: the spine and the chest bone take up what the pelvis gave away
	var q_rel := (eul(pe).inverse() * tb).get_rotation_quaternion()
	var q_s := Quaternion.IDENTITY.slerp(q_rel, 0.4)
	var q_c := q_s.inverse() * q_rel
	_setv(c, C_SPN, Basis(q_s).get_euler(EULER_ORDER_YXZ))
	_setv(c, C_CHS, Basis(q_c).get_euler(EULER_ORDER_YXZ))
	for j in 3:
		c[C_ROT + j] = loco[C_ROT + j]
		c[C_PIV + j] = loco[C_PIV + j]


# --- the wrist's limit -------------------------------------------------------------------------------------------------------
## A hand cannot point the blade closer than about 30 degrees to its forearm's line (docs/ANIMATION.md 6.3). The blows are
## authored inside that, but a blend into one (from a run, from the guard, from the blow before) is a straight mix of two
## poses and can dip below it for a frame or two: while a blow plays and while it blends out, `_solve` turns such a hand away
## from the forearm about the axis across both (a degree or two, only in those frames).
const WRIST_MIN := 0.515
var _wlim := false
var _wlim_tail := 0.0
## The forearms' twist about their own axes as last solved (right, left): tracked so that it never jumps (_solve): it follows its
## target at no more than TWIST_RATE rad/s (the shield's facing sweeping across the forearm's axis, as in the air pose, asks for half a
## turn in a few frames: the shield turns over in a few frames instead).
var _tw_fa := PackedFloat32Array([0.0, 0.0])
const TWIST_RATE := 20.0
const TWIST_RATE_FREE := 36.0
## The twist (about the forearm's axis) between the held hand's frame and the one the forearm gives it, as last solved, kept continuous.
var _wr_tw := 0.0
var _wr_on := false
var _dbg_tw := Vector4()
## The left hand's held frame (the spear, the chain) as this frame's solve has it, and the left forearm's direction of the last solve.
var _lh_held := Basis()
var _lh_on := false
var _fa_dir_l := Vector3.ZERO
var _dbg_wb := 0.0
var _dbg_wt := Vector3()
var _dbg_wb2 := Vector3()
## How far (rad) the left forearm turns to follow a held hand's frame; the wrist keeps what is beyond.
const TW_HAND_MAX := 1.2
## ... and the shield's: the forearm never turns further than this either way from where the arm bends (it cannot go round: the twist
## was once found at 280 degrees).
const TW_MAX := 2.0
const TW_LEAD := 3.0
## ... and how much of the forearm's twist stays the shield's even with the hand held (the shield is on that arm: it must stay clear of him).
const TW_SHIELD := 0.5
var _solve_dt := 0.0
## The shield's slip about the left forearm (rad), the most it may be, how fast it goes (rad/s), and what the last solve wanted.
var _sh_slack := 0.0
var _sh_slack_t := 0.0
const SH_SLACK_MAX := 1.2
const SH_SLACK_RATE := 20.0


## The turn of the shield about the forearm's axis through the elbow, as a transform in rig space (identity when the strap is not slipping).
func _slack_xf() -> Transform3D:
	if absf(_sh_slack) < 1e-4:
		return Transform3D.IDENTITY
	var e := _bx[FARM_L].origin
	var ax := _bx[HAND_L].origin - e
	if ax.length_squared() < 1e-8:
		return Transform3D.IDENTITY
	var rb := Basis(ax.normalized(), _sh_slack)
	return Transform3D(rb, e - rb * e)


## The shield's skinning matrix (rest rig space -> rig): the forearm's, turned by the strap's slip.
func shield_skin() -> Transform3D:
	var b := _bx[FARM_L]
	return _slack_xf() * Transform3D(b.basis, b.origin - b.basis * _rest[FARM_L])


func _twist_step(d: float, rate: float = TWIST_RATE) -> float:
	if _solve_dt <= 0.0:
		return d
	return clampf(d, -rate * _solve_dt, rate * _solve_dt)


static func _wrist_limit(hb: Basis, fore: Vector3) -> Basis:
	var bd := -hb.z
	var ang := bd.angle_to(fore)
	if ang >= WRIST_MIN:
		return hb
	var ax := fore.cross(bd)
	if ax.length_squared() < 1e-8:
		ax = hb.x
	return Basis(ax.normalized(), WRIST_MIN - ang) * hb


# --- the footwork of the blows -----------------------------------------------------------------------------------------------
## While a joint-angle blow plays, its feet are driven here, in the world (the gait's own foot state: `_ft_*`), so the
## blow ends with the feet exactly where the gait takes over. A blow's "feet" plan: `moves` (one foot swings from where it
## stands to a spot in the rig's frame: foot f, from t0 to t1, ankle at x, z, yaw (deg from the rig), apex (m) over the
## ground, landing pitch th (deg, + toes up)), `pitchN` (the planted foot N's pitch over the blow: - lifts the heel, the
## toe stays down) and `followN` (how much of the pelvis' yaw change the planted foot N turns with: it pivots).
var _sk_on := false
var _sk_init := false
var _sk_yaw0 := PackedFloat32Array([0.0, 0.0])
var _sk_p0 := PackedFloat32Array([0.0, 0.0])
var _sk_land_t := PackedFloat32Array([-9.0, -9.0])
var _sk_land_th := PackedFloat32Array([0.0, 0.0])
var _sk_mv := PackedByteArray()


## A blow (from joint angles) starts: the feet that were swinging or stepping home are put down where they are, the gait
## stops driving them.
func _strike_begin() -> void:
	_gait_on = false
	for i in 2:
		if _ft_st[i] != ST_STAND:
			var psi := wrapf(_ft_wy[i] - _ry, -PI, PI)
			_ft_st[i] = ST_STAND
			_ft_kind[i] = 0
			_ft_pin[i] = _l2w(_pin_of(_w2l(_ft_aw[i]), 0, psi, 0.0))
			_ft_yaw[i] = _ft_wy[i]
			_ft_th0[i] = 0.0
		_sk_land_t[i] = -9.0
	_sk_init = true


## The blow ends (or is cut short): a foot in the air comes down at home, the others stay where they are.
func _strike_end() -> void:
	_gait_on = true
	_gait_stop()
	_wlim_tail = 0.4


## The move of foot `i` that is under way at action time t (one that goes where the foot already is - a "near" distance - is
## skipped: a blow started from its own stance does not hop on the spot, one chained out of another gathers its feet).
func _strike_move(plan: Dictionary, i: int, t: float) -> Dictionary:
	var mvs: Array = plan.get("moves", [])
	if _sk_mv.size() != mvs.size():
		_sk_mv.resize(mvs.size())
		_sk_mv.fill(0)
	for k in mvs.size():
		var mv: Dictionary = mvs[k]
		if int(mv["f"]) != i or t < float(mv["t0"]) or t >= float(mv["t1"]) or _sk_mv[k] == 1:
			continue
		if _sk_mv[k] == 0:
			if mv.has("near") and _ft_st[i] != ST_SWING and _ft_aw[i].distance_to(_l2w(Vector2(float(mv["x"]), float(mv["z"])))) < float(mv["near"]):
				_sk_mv[k] = 1
				continue
			_sk_mv[k] = 2
		return mv
	return {}


## The feet of the blow at action time `action_t`: writes the ankle, pitch, yaw and knee channels of `c` and the gait's
## own foot state, then lowers the pelvis where a leg would not reach.
func _strike_feet(c: PackedFloat32Array, dt: float) -> void:
	var def := act_def(_akey)
	var plan: Dictionary = (def["strike"] as Dictionary).get("feet", {})
	var t := action_t
	_rig_frame()
	if plan.get("mode", "") == "baked":
		# the feet are in the pose (the spin turns the whole body about a planted foot): the gait's foot state follows
		# them, planted where the pose puts them, so that the gait can take over from here
		for i in 2:
			var o := C_FR if i == 0 else C_FL
			var ank := v3(c, o)
			var fr := v3(c, o + 3)
			_ft_st[i] = ST_STAND
			_ft_kind[i] = 1
			var psi := fr.y
			_ft_ank[i] = ank
			_ft_pit[i] = fr.x
			_ft_ry[i] = psi
			_ft_wy[i] = _ry + psi
			_ft_yaw[i] = _ry + psi
			_ft_aw[i] = _l2w(Vector2(ank.x, ank.z))
			_ft_ay[i] = ank.y
			_ft_pin[i] = _l2w(_pin_of(Vector2(ank.x, ank.z), 1, psi, minf(fr.x, 0.0)))
			_ft_w[i] = 0.0
		return
	var pyaw := c[C_PELR + 1]
	if _sk_init:
		_sk_init = false
		_sk_mv.clear()
		for i in 2:
			_sk_yaw0[i] = _ft_yaw[i]
			_sk_p0[i] = pyaw
	var pel := v3(c, C_PEL)
	var pelr := v3(c, C_PELR)
	for i in 2:
		var sx := 1.0 if i == 0 else -1.0
		var mv := _strike_move(plan, i, t)
		var ank := Vector3.ZERO
		var pit := 0.0
		var yaw_w := _ft_yaw[i]
		var w := 1.0
		if not mv.is_empty():
			var t0 := float(mv["t0"])
			var t1 := float(mv["t1"])
			if _ft_st[i] != ST_SWING:
				_ft_st[i] = ST_SWING
				_ft_from[i] = _ft_aw[i]
				_ft_from_y[i] = _ft_ay[i]
				_ft_from_th[i] = _ft_pit[i]
				_ft_from_yaw[i] = _ft_wy[i]
				_ft_from_pv[i] = 0.0
			var s := clampf((t - t0) / maxf(t1 - t0, 0.02), 0.0, 1.0)
			var tgt := Vector2(float(mv["x"]), float(mv["z"]))
			var gth := deg_to_rad(float(mv.get("th", 0.0)))
			var gyaw := _ry + deg_to_rad(float(mv.get("yaw", 0.0)))
			var goal := _l2w(tgt)
			_ft_goal[i] = goal
			_ft_goal_th[i] = gth
			_ft_goal_yaw[i] = gyaw
			var e := s * s * (3.0 - 2.0 * s)
			var ev := s * s * (3.0 - 2.0 * s)
			var aw := _ft_from[i].lerp(goal, e)
			var al := _w2l(aw)
			var arc := sin(PI * pow(s, 0.8)) * smoothstep(0.0, 0.14, s)
			var y := lerpf(_ft_from_y[i], _ankle_y(gth), ev * ev) + float(mv.get("apex", 0.08)) * arc
			ank = Vector3(al.x, y, al.y)
			var sp := clampf(s / 0.85, 0.0, 1.0)
			var k2 := sp * sp * (3.0 - 2.0 * sp)
			pit = lerpf(_ft_from_th[i], gth, k2)
			yaw_w = lerp_angle(_ft_from_yaw[i], gyaw, e)
			w = maxf(1.0 - smoothstep(0.0, 0.15, s), smoothstep(0.55, 0.85, s))
		else:
			if _ft_st[i] == ST_SWING:
				# the move is over: the foot lands on the spot it was heading for
				_land(i, _w2l(_ft_goal[i]), _ft_goal_th[i], _ft_goal_yaw[i], false)
				_sk_yaw0[i] = _ft_yaw[i]
				_sk_p0[i] = pyaw
				_sk_land_t[i] = t
				_sk_land_th[i] = _ft_goal_th[i]
			# planted: the pitch (a heel lifted while the toe stays down), the pivot with the hips
			var pk: Variant = plan.get("pitch%d" % i)
			var th := deg_to_rad(_kc(pk, t)) if pk != null else 0.0
			if _sk_land_t[i] > -8.0 and _sk_land_th[i] > 0.0:
				th += _sk_land_th[i] * (1.0 - smoothstep(0.0, 0.07, t - _sk_land_t[i]))
			var fk: Variant = plan.get("follow%d" % i)
			if fk != null:
				_ft_yaw[i] = _sk_yaw0[i] + _kc(fk, t) * (pyaw - _sk_p0[i])
			var psi := wrapf(_ft_yaw[i] - _ry, -PI, PI)
			if absf(psi) > 0.8:
				psi = clampf(psi, -0.8, 0.8)
				_ft_yaw[i] = _ry + psi
			var pl := _w2l(_ft_pin[i])
			if _ft_kind[i] == 0 and th <= 0.0:
				# the sole has come flat: the toe takes the weight, pinned where it lies
				_ft_kind[i] = 1
				pl += Vector2(-sin(psi), -cos(psi)) * SOLE_LEN
				_ft_pin[i] = _l2w(pl)
			elif _ft_kind[i] == 1 and th > 0.02:
				# a toe-pinned foot cannot point its toes up: it lies flat
				th = 0.0
			ank = _ankle_of(pl, _ft_kind[i], psi, th)
			pit = th
			yaw_w = _ry + psi
		if _ft_st[i] == ST_SWING:
			# a swinging foot keeps its own side of the planted leg
			var oth := _ft_ank[1 - i]
			if i == 1:
				ank.x = minf(ank.x, oth.x - 0.11)
			elif _ft_st[1] == ST_STAND:
				ank.x = maxf(ank.x, oth.x + 0.11)
		_ft_ank[i] = ank
		_ft_pit[i] = pit
		_ft_wy[i] = yaw_w
		_ft_ry[i] = wrapf(yaw_w - _ry, -PI, PI)
		_ft_aw[i] = _l2w(Vector2(ank.x, ank.z))
		_ft_ay[i] = ank.y
		_ft_w[i] = w
		var o := C_FR if i == 0 else C_FL
		_setv(c, o, ank)
		_setv(c, o + 3, Vector3(pit, _ft_ry[i], 0.0))
		_setv(c, o + 6, Basis(Vector3.UP, _ft_ry[i]) * Vector3(sx * 0.12, 0.0, -1.0))
	pel.y = _softmin(pel.y, _pelvis_limit(pel, pelr), 0.03)
	_setv(c, C_PEL, pel)
	# the leg's reach, with the pelvis where it ended up: a foot the pelvis has run away from (a lunge, a blow carried out of a
	# run) is dragged along by its contact (a planted foot slides in) or pulled in (a foot in the air)
	var lmax := (LEN_TH + LEN_SH) * LEG_REACH * 0.99
	for i in 2:
		var sx2 := 1.0 if i == 0 else -1.0
		var hip := P_PELVIS + pel + eul(pelr) * (mx(P_HIP, sx2) - P_PELVIS)
		var a := _ft_ank[i]
		var dh := Vector2(a.x - hip.x, a.z - hip.z)
		var hmax := sqrt(maxf(lmax * lmax - (hip.y - a.y) * (hip.y - a.y), 0.0016))
		if dh.length() > hmax:
			var sh := dh.normalized() * (dh.length() - hmax)
			a.x -= sh.x
			a.z -= sh.y
			_ft_ank[i] = a
			_ft_aw[i] = _l2w(Vector2(a.x, a.z))
			if _ft_st[i] == ST_STAND:
				_ft_pin[i] = _l2w(_pin_of(Vector2(a.x, a.z), _ft_kind[i], _ft_ry[i], _ft_pit[i]))
			_setv(c, C_FR if i == 0 else C_FL, a)
# <<< STRIKES END


## Emits an action's events (a name may carry several times).
func _emit_events(def: Dictionary) -> void:
	var ev: Dictionary = def["ev"]
	for k in ev:
		var v: Variant = ev[k]
		if v is Array:
			for i in (v as Array).size():
				var tk: float = v[i]
				var id := "%s#%d" % [k, i]
				if action_t >= tk and not _fired.has(id):
					_fired[id] = true
					event.emit(k)
		else:
			_mark(k, float(v))


## Tools: shift the idle clock (breathing / sway) without simulating.
func t_offset(dt: float) -> void:
	t += dt
	_animate(0.0)


# >>> STOW BEGIN (lane STOW: carrying the weapons; docs/ANIMATION.md section 9)
# --- the weapons carried: ARMED (the sword in the right fist, the shield on the left forearm) or STOWED (the sword in its scabbard
# at the left hip, the shield on his back with the chain spear strapped over it). No node changes parent: every frame _stow_frame
# works out where each prop is (rig space) and _place_weapons puts it there, so a prop that changes hands leaves from exactly where
# it was (what the hand missed by is an offset that dies away in a few frames: never a pop).

## Where a prop is: the sword in its scabbard or in the right fist; the shield on the back, held by its rim in the left fist (on its
## way between the back and the arm) or on the forearm.
enum { AT_SHEATH, AT_HAND, AT_BACK, AT_RIM, AT_ARM }
## The scabbard in the sword's own grip space (the blade along -Z; sheathed, the sword's frame is the scabbard's turned half a turn
## about the blade, SHEATH_ROLL, so that the right fist meets the grip palm out, the back of the hand to his belly): the throat's top
## (under the guard), the throat band's lower edge, where the bronze chape begins and the end.
const SCAB_TOP := -0.096
const SCAB_THROAT := -0.15
const SCAB_CHAPE := -0.99
const SCAB_END := -1.11
const SHEATH_ROLL := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, 1.0))
## How far the sword slides along the scabbard until its tip leaves the throat (m).
const SCAB_SLIDE := 1.0
## The scabbard on the belt (rest rig space): the strap's top on the belt (what it swings about), the throat band's centre, the
## direction it points (throat -> chape: back, down and a little out) and a hint for its upper edge.
const SCAB_HINGE := Vector3(-0.2, 0.985, -0.045)
const SCAB_T := Vector3(-0.29, 0.91, -0.085)
const SCAB_D := Vector3(-0.2, -0.55, 0.81)
const SCAB_UP := Vector3(0.0, 1.0, 0.3)
## The scabbard turned on its strap by a draw (it follows the blade out: where it points when the tip leaves the throat) and by the
## sheathe (where it waits for the tip).
const SCAB_D_DRAW := Vector3(-0.6, -0.68, 0.33)
const SCAB_D_SHEATHE := Vector3(-0.55, -0.72, 0.38)
## The scabbard's swing on its strap: stiffness, damping, the most it may be turned from rest (rad), the chape's least height.
const SCAB_K := 140.0
const SCAB_C := 13.0
const SCAB_SWING_MAX := 1.3
const SCAB_GROUND := 0.07
## The sheath's leather, darker than the belt, and its seams.
const SHEATH := Color("3B2216")
const SHEATH_LIGHT := Color("5A3420")
## The shield on the back (rest rig space, in the frame of the spear on the back): its centre, its face (out: back and a little up,
## following the upper back) and the forearm's axis on it (down: it hangs from its top). The lion's pelt is thicker.
const SHB_C := Vector3(0.0, 1.27, 0.305)
const SHB_C_LION := Vector3(0.0, 1.25, 0.335)
const SHB_N := Vector3(0.0, 0.15, 1.0)
const SHB_X := Vector3(0.0, -1.0, 0.0)
## The chain spear strapped over the shield on the back: how much further out its head end and its butt end lie than on the cape
## (along the shield's face), so that the shaft clears the shield's boss and the coiled chain its lower rim.
const SPEAR_OVER_TIP := 0.135
const SPEAR_OVER_BUTT := 0.19
## Where on the rim the left fist takes the shield (rad about its face from the forearm's axis: on the back about 65 degrees round
## from straight down towards his left, the lower left of the rim, clear of the spear).
const RIM_ANG := 1.13
## The six actions (upper body: the legs keep the locomotion) and their moments (s). Drawing: the right fist closes on the grip, the
## tip leaves the throat; the left fist takes the rim, the forearm goes into the shield's band. Sheathing: the tip finds the throat,
## the sword is home; the left fist takes the rim, the shield is hung on the back.
const STOW_ACTS := ["draw", "sheathe", "draw_sword", "draw_shield", "sheathe_sword", "sheathe_shield"]
const STOW_EV := {
	"draw": {"sw_grab": 0.12, "sw_free": 0.27, "sh_grab": 0.15, "sh_arm": 0.4},
	"draw_sword": {"sw_grab": 0.06, "sw_free": 0.15},
	"draw_shield": {"sh_grab": 0.07, "sh_arm": 0.18},
	"sheathe": {"sw_enter": 0.38, "sw_home": 0.56, "sh_grab": 0.12, "sh_back": 0.5},
	"sheathe_sword": {"sw_enter": 0.26, "sw_home": 0.42},
	"sheathe_shield": {"sh_grab": 0.08, "sh_back": 0.36},
}

## Where the sword and the shield are (AT_*); the last hand-off of each prop: its offset (where it was, in its new holder's frame),
## how much of it is left (1 -> 0) and how fast it goes (1/s). The scabbard has one too (it leaves the blade or meets it).
var _sw_at := AT_HAND
var _sh_at := AT_ARM
var _sw_off := Transform3D.IDENTITY
var _sw_off_k := 0.0
var _sw_off_rate := 12.0
var _sh_off := Transform3D.IDENTITY
var _sh_off_k := 0.0
var _sh_off_rate := 6.0
var _scab_off := Transform3D.IDENTITY
var _scab_off_k := 0.0
var _scab_off_rate := 14.0
## This frame (rig space): the scabbard's frame (sword grip space -> rig), the sword's grip frame, the shield's frame (the frame
## shield_meshes() is modelled in).
var _scab_xf := Transform3D()
var _sw_xf := Transform3D()
var _sh_xf := Transform3D()
var _stow_ok := false
var _scab_node: Node3D
## The scabbard's swing on its strap (a rotation vector in the pelvis' rest frame) and how fast it turns; the strap's last world
## position and velocity (its acceleration swings it); whether the blade is in the scabbard on its way out or in (it lies along it).
var _scab_a := Vector3.ZERO
var _scab_av := Vector3.ZERO
var _scab_hp := Vector3.ZERO
var _scab_hv := Vector3.ZERO
var _scab_hok := false
var _riding := false
## How much the arms carry the weapons (0 relaxed, empty hands .. 1 armed), each following what is in its hand.
var _carry_sw := 1.0
var _carry_sh := 1.0
## The stow action being followed, the moments of it already passed, its last time.
var _stow_act := ""
var _stow_fired := {}
var _stow_tp := 0.0
## The chain spear lies over the shield on his back (1) or on the cape (0).
var _spear_over := 0.0
## 0..1: a foe close by (Hero sets it): the armed idle is the ready stance, else the sword hangs low in his hand.
var alert := 0.0
var _alert := 0.0
static var _scab_rest_c := Transform3D()
static var _scab_rest_ok := false
static var _sh_rest_c := Transform3D()
static var _sh_rest_ok := false


# --- API ---------------------------------------------------------------------------------------------------------------------------

## ARMED (on) or STOWED. Played: the draw or the sheathe of whatever is not where it should be (`draw`, `draw_sword`, `draw_shield`,
## `sheathe`, `sheathe_sword`, `sheathe_shield`, on the upper body). `instant`: put there now (the start of the game, tools).
func set_armed(on: bool, instant: bool = false) -> void:
	if instant:
		if STOW_EV.has(action):
			stop_action(0.0)
		_stow_act = ""
		_sw_at = AT_HAND if on else AT_SHEATH
		_sh_at = AT_ARM if on else AT_BACK
		_sw_off_k = 0.0
		_sh_off_k = 0.0
		_scab_off_k = 0.0
		_scab_a = Vector3.ZERO
		_scab_av = Vector3.ZERO
		_riding = false
		_carry_sw = 1.0 if on else 0.0
		_carry_sh = _carry_sw
		_spear_over = 0.0 if on else 1.0
		_stow_ok = false
		return
	var a := stow_action_for(on, on, on)
	if a != "" and action != a:
		play_at(a, 1.0, true)


## The action that brings the sword (`sword`) and the shield (`shield`) to the hands (on) or puts them away (off), "" if nothing is to
## be done: only what is not already where it should be.
func stow_action_for(on: bool, sword: bool, shield: bool) -> String:
	if on:
		var sw := sword and _sw_at != AT_HAND
		var sh := shield and _sh_at == AT_BACK
		if sw and sh:
			return "draw"
		if sw:
			return "draw_sword"
		if sh:
			return "draw_shield"
		return ""
	var sw2 := sword and _sw_at == AT_HAND
	var sh2 := shield and _sh_at != AT_BACK
	if sw2 and sh2:
		return "sheathe"
	if sw2:
		return "sheathe_sword"
	if sh2:
		return "sheathe_shield"
	return ""


## Armed, or on the way to it: the sword in the hand (or a draw playing), and no sheathe playing.
func is_armed() -> bool:
	if action.begins_with("sheathe"):
		return false
	if action.begins_with("draw"):
		return true
	return _sw_at == AT_HAND or _sh_at != AT_BACK


func sword_in_hand() -> bool:
	return _sw_at == AT_HAND


## The sword in the hand and clear of its scabbard (a blow can start): in a draw, from the moment its tip leaves the throat.
func sword_free() -> bool:
	if _sw_at != AT_HAND:
		return false
	if action == "draw" or action == "draw_sword":
		return action_t >= _stow_t(action, "sw_free")
	return not _riding


func shield_in_hand() -> bool:
	return _sh_at != AT_BACK


## A draw or a sheathe is playing.
func stow_busy() -> bool:
	return STOW_EV.has(action)


## The scabbard's throat and its end (world space, for tools and the clip check).
func scabbard_segment() -> PackedVector3Array:
	var gx := global_transform if is_inside_tree() else transform
	return PackedVector3Array([gx * (_scab_xf * Vector3(0.0, 0.0, SCAB_THROAT)), gx * (_scab_xf * Vector3(0.0, 0.0, SCAB_END))])


# --- the scabbard -----------------------------------------------------------------------------------------------------------------

## The scabbard in the sword's grip space: a leather sheath that follows the leaf of the blade (a lens in section, its seams lighter),
## a bronze throat (its mouth dark) and chape, a bronze band a third of the way down, a ring on the upper edge of the throat and the
## short strap from it up to the belt (to SCAB_HINGE, the point it swings about). [soft, metal]
static func scabbard_meshes() -> Array:
	if not _cache.has("scabbard"):
		var soft := MeshBuilder.new(65)
		var metal := MeshBuilder.new(66)
		var zs := [SCAB_THROAT + 0.004, -0.3, -0.48, -0.64, -0.78, -0.9, SCAB_CHAPE + 0.012]
		var ws := [0.047, 0.043, 0.047, 0.057, 0.058, 0.051, 0.04]
		var ts := [0.024, 0.022, 0.022, 0.024, 0.023, 0.021, 0.018]
		var rings := []
		for k in zs.size():
			rings.append([Vector3(0.0, 0.0, zs[k]), ts[k], ws[k]])
		var col := func(_p: Vector3, k: int, i: int) -> Color:
			if k < 0:
				return INK
			return SHEATH_LIGHT if (i == 2 or i == 7) else SHEATH
		loft(soft, rings, 10, col, Vector3.UP, true, false)
		var band := func(_p: Vector3, k: int, _i: int) -> Color:
			return INK if k < 0 else BRONZE
		loft(metal, [[Vector3(0.0, 0.0, SCAB_TOP), 0.03, 0.056], [Vector3(0.0, 0.0, SCAB_TOP - 0.018), 0.028, 0.053], [Vector3(0.0, 0.0, SCAB_THROAT), 0.027, 0.05]], 10, band, Vector3.UP, true, false)
		loft(metal, [[Vector3(0.0, 0.0, -0.33), 0.026, 0.048], [Vector3(0.0, 0.0, -0.36), 0.026, 0.048]], 10, BRONZE_DARK, Vector3.UP, false, false)
		loft(metal, [[Vector3(0.0, 0.0, SCAB_CHAPE + 0.02), 0.021, 0.044], [Vector3(0.0, 0.0, SCAB_CHAPE - 0.03), 0.019, 0.036], [Vector3(0.0, 0.0, SCAB_END + 0.03), 0.014, 0.017]], 10, BRONZE, Vector3.UP, false, true)
		metal.ico(Vector3(0.0, 0.0, SCAB_END + 0.016), 0.019, BRONZE_LIGHT, 0, 0.0, Vector3(1.0, 1.0, 1.2))
		# the ring on the throat's upper edge and the strap up to the belt
		metal.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.004, 0.066, -0.123)))
		metal.ring(Vector3.ZERO, 0.017, 0.01, 0.008, 8, BRONZE_DARK)
		metal.pop()
		var h := scab_rest_xf().affine_inverse() * SCAB_HINGE
		soft.limb(Vector3(0.0, 0.07, -0.123), h, 0.011, 0.012, 6, LEATHER_DARK)
		soft.ico(h, 0.017, LEATHER, 0)
		_cache["scabbard"] = [soft.commit(), metal.commit()]
	return _cache["scabbard"]


## The scabbard's frame at rest (its grip space -> rest rig space).
static func scab_rest_xf() -> Transform3D:
	if not _scab_rest_ok:
		var d := SCAB_D.normalized()
		var z := -d
		var y := perp(SCAB_UP, z).normalized()
		var b := Basis(y.cross(z), y, z)
		_scab_rest_c = Transform3D(b, SCAB_T - b * Vector3(0.0, 0.0, (SCAB_TOP + SCAB_THROAT) * 0.5))
		_scab_rest_ok = true
	return _scab_rest_c


## The scabbard's frame (rig space) for a pelvis skinning transform and a swing `q` about its strap (pelvis rest frame).
static func _scab_frame(pel_skin: Transform3D, q: Quaternion) -> Transform3D:
	var r := Basis(q)
	return pel_skin * Transform3D(r, SCAB_HINGE - r * SCAB_HINGE) * scab_rest_xf()


## The turn of the scabbard on its strap that points it along `d` (rest frame) from where it points at rest.
static func _scab_turn(d: Vector3) -> Quaternion:
	return Quaternion(SCAB_D.normalized(), d.normalized())


## The frame shield_meshes() is modelled in, on the forearm at rest (rest rig space).
static func _sh_rest_xf() -> Transform3D:
	if not _sh_rest_ok:
		var e := mx(P_ELBOW, -1.0)
		_sh_rest_c = shield_xf(Transform3D(Basis.IDENTITY, e), e)
		_sh_rest_ok = true
	return _sh_rest_c


## The shield on the back (rest rig space, the spear's pivot).
static func _shb_rest(lion: bool) -> Transform3D:
	var n := SHB_N.normalized()
	var x := perp(SHB_X, n).normalized()
	return Transform3D(Basis(x, n, x.cross(n)), SHB_C_LION if lion else SHB_C)


## The left fist's grip frame on the shield's rim, in the shield's frame: the fist round the rim (its shaft along the rim), the back of
## the hand out over the edge and a little towards the face.
static func _rim_grip() -> Transform3D:
	var rad := Vector3(cos(RIM_ANG), 0.0, sin(RIM_ANG))
	var tg := Vector3(-sin(RIM_ANG), 0.0, cos(RIM_ANG))
	return Transform3D(hand_basis(tg, (rad + Vector3(0.0, 0.5, 0.0)).normalized(), -1.0), rad * (SHIELD_R * 0.99) + Vector3(0.0, -0.012, 0.0))


## Where the spear lies on the back with the shield under it: as on the cape (spear_back_xf), the head end SPEAR_OVER_TIP and the butt
## end SPEAR_OVER_BUTT further out along the shield's face.
static func spear_over_xf(lion: bool = false) -> Transform3D:
	var n := SHB_N.normalized()
	var tip := (SPEAR_BACK_TIP if not lion else SPEAR_BACK_TIP_LION) + n * SPEAR_OVER_TIP
	var butt := (SPEAR_BACK_BUTT if not lion else SPEAR_BACK_BUTT_LION) + n * SPEAR_OVER_BUTT
	var d := (tip - butt).normalized()
	var z := -d
	var x := perp(SPEAR_ROLL if not lion else SPEAR_ROLL_LION, z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), tip - d * 0.58)


# --- the skeleton's frames before the solve (the hands' targets of a draw are where the props are this frame) -----------------------

## [pelvis, spine, chest, root] for a pose, as _solve will have them: the first three before the whole-body rotation `root`.
func _trunk_xf(c: PackedFloat32Array) -> Array:
	var pb := eul(v3(c, C_PELR))
	var po := P_PELVIS + v3(c, C_PEL)
	var upright := _reduce_rot(v3(c, C_ROT)).length_squared() < 0.01
	if upright and _gnd_k > 0.001:
		po.y += minf(0.0, minf(_gnd_dy.x, _gnd_dy.y)) * _gnd_k
	var sb := pb * eul(v3(c, C_SPN))
	var so := po + pb * (P_SPINE - P_PELVIS)
	var cb := sb * eul(v3(c, C_CHS))
	var co := so + sb * (P_CHEST - P_SPINE)
	var root := Transform3D.IDENTITY
	var rv := v3(c, C_ROT)
	if rv.length_squared() > 1e-8:
		var rb := Basis(rv.normalized(), rv.length())
		var pv := v3(c, C_PIV)
		root = Transform3D(rb, pv - rb * pv)
	return [Transform3D(pb, po), Transform3D(sb, so), Transform3D(cb, co), root]


static func _skin_of(b: Transform3D, rest: Vector3) -> Transform3D:
	return Transform3D(b.basis, b.origin - b.basis * rest)


## The spear's pivot (the spine and the chest blended) for two bone transforms (blend_skin of the solved skeleton).
static func _spear_pivot_of(sp: Transform3D, ch: Transform3D) -> Transform3D:
	var q := sp.basis.get_rotation_quaternion().slerp(ch.basis.get_rotation_quaternion(), 0.6)
	var bs := Basis(q)
	var ref := Vector3(0.0, 1.3, 0.25)
	var pa := sp.origin + sp.basis * (ref - P_SPINE)
	var pb := ch.origin + ch.basis * (ref - P_CHEST)
	return Transform3D(bs, pa.lerp(pb, 0.6) - bs * ref)


func _grip_r() -> Transform3D:
	var h := _bx[HAND_R]
	return Transform3D(h.basis, h.origin + h.basis * GRIP)


func _grip_l() -> Transform3D:
	var h := _bx[HAND_L]
	return Transform3D(h.basis, h.origin + h.basis * GRIP)


## The shield's frame on the forearm (rig space): the forearm's, turned by the strap's slip, ridden up the arm while the hand brushes
## the wheat.
func _shield_arm_nom() -> Transform3D:
	var fa := _bx[FARM_L]
	var skin := _slack_xf() * _skin_of(fa, _rest[FARM_L])
	if _brush > 0.0005 and action == "":
		skin = skin.interpolate_with(_brush_shield_skin(), _brush_shield_k())
	return skin * _sh_rest_xf()


# --- the stow actions ------------------------------------------------------------------------------------------------------------

## The time of moment `k` of the stow action `a`, or -1.
static func _stow_t(a: String, k: String) -> float:
	var ev: Dictionary = STOW_EV.get(a, {})
	return float(ev.get(k, -1.0))


## The scabbard turned on its strap by the action playing: [turn, weight] (weight 0: it hangs as it swings).
func _scab_sched() -> Array:
	var t := action_t
	match action:
		"draw", "draw_sword":
			var tg := _stow_t(action, "sw_grab")
			var tf := _stow_t(action, "sw_free")
			if t >= tg - 0.04 and t <= tf + 0.001:
				var u := clampf((t - tg) / (tf - tg), 0.0, 1.0)
				var full := SCAB_D_DRAW if action == "draw" else SCAB_D_DRAW.lerp(SCAB_D, 0.35)
				return [Quaternion.IDENTITY.slerp(_scab_turn(full), smoothstep(0.0, 1.0, u)), smoothstep(tg - 0.04, tg, t)]
		"sheathe", "sheathe_sword":
			var te := _stow_t(action, "sw_enter")
			var th := _stow_t(action, "sw_home")
			var qs := _scab_turn(SCAB_D_SHEATHE)
			if t < te:
				return [qs, smoothstep(te - 0.16, te - 0.03, t)]
			if t <= th + 0.001:
				var u2 := clampf((t - te) / (th - te), 0.0, 1.0)
				return [qs.slerp(Quaternion.IDENTITY, smoothstep(0.0, 1.0, u2)), 1.0]
	return [Quaternion.IDENTITY, 0.0]


## How far out of the scabbard the sword is meant to be now in a draw or a sheathe (-1: not in it).
func _slide_sched() -> float:
	var t := action_t
	match action:
		"draw", "draw_sword":
			var tg := _stow_t(action, "sw_grab")
			var tf := _stow_t(action, "sw_free")
			if t >= tg and t <= tf:
				var u := (t - tg) / (tf - tg)
				return SCAB_SLIDE * 1.04 * u * u * (2.2 - 1.2 * u)
		"sheathe", "sheathe_sword":
			var te := _stow_t(action, "sw_enter")
			var th := _stow_t(action, "sw_home")
			if t >= te and t <= th:
				var u2 := (t - te) / (th - te)
				return SCAB_SLIDE * 1.03 * (1.0 - smoothstep(0.0, 1.0, u2))
	return -1.0


## The swing of the scabbard on its strap now: what it swings to, or what the action turns it to.
func _scab_q() -> Quaternion:
	var q := Quaternion(_scab_a.normalized(), _scab_a.length()) if _scab_a.length_squared() > 1e-10 else Quaternion.IDENTITY
	var s: Array = _scab_sched()
	if float(s[1]) > 0.0:
		q = q.slerp(s[0], float(s[1]))
	return q


## After the blend (Hermite keys, inertialized transition): a draw or a sheathe puts the fists exactly on what they take: the grip of
## the sheathed sword (then along the scabbard while the blade slides out), the rim of the shield where it hangs; and, sheathing, the
## tip on the throat (then along the scabbard while it slides in) and the shield onto its place on the back.
func _stow_pose(_delta: float) -> void:
	if not STOW_EV.has(action):
		return
	var t := action_t
	var tr := _trunk_xf(_pose)
	var root: Transform3D = tr[3]
	var pel_skin: Transform3D = root * _skin_of(tr[0], P_PELVIS)
	var chest_pre: Transform3D = tr[2]
	var to_cs := chest_pre.affine_inverse() * root.affine_inverse()
	# the sword hand
	var w := 0.0
	var g := Transform3D()
	match action:
		"draw", "draw_sword":
			var tg := _stow_t(action, "sw_grab")
			var tf := _stow_t(action, "sw_free")
			var u := clampf((t - tg) / (tf - tg), 0.0, 1.0)
			w = smoothstep(tg - 0.08, tg, t) if t <= tf else 1.0 - smoothstep(tf, tf + 0.07, t)
			if w > 0.0:
				var full := SCAB_D_DRAW if action == "draw" else SCAB_D_DRAW.lerp(SCAB_D, 0.35)
				var q := Quaternion.IDENTITY.slerp(_scab_turn(full), smoothstep(0.0, 1.0, u))
				var s := SCAB_SLIDE * 1.04 * u * u * (2.2 - 1.2 * u)
				g = _scab_frame(pel_skin, q) * Transform3D(SHEATH_ROLL, Vector3(0.0, 0.0, s))
		"sheathe", "sheathe_sword":
			var te := _stow_t(action, "sw_enter")
			var th := _stow_t(action, "sw_home")
			var u2 := clampf((t - te) / (th - te), 0.0, 1.0)
			w = smoothstep(te - 0.09, te, t) if t <= th else 1.0 - smoothstep(th, th + 0.06, t)
			if w > 0.0:
				var qs := _scab_turn(SCAB_D_SHEATHE).slerp(Quaternion.IDENTITY, smoothstep(0.0, 1.0, u2))
				var s2 := SCAB_SLIDE * 1.03 * (1.0 - smoothstep(0.0, 1.0, u2))
				g = _scab_frame(pel_skin, qs) * Transform3D(SHEATH_ROLL, Vector3(0.0, 0.0, s2))
	if w > 0.0:
		var gc := to_cs * g
		_lerpv(_pose, C_HR, gc.origin, w)
		_lerpv(_pose, C_HRB, (-gc.basis.z).normalized(), w)
		_lerpv(_pose, C_HRK, gc.basis.x.normalized(), w)
		_pose[C_HRS] = lerpf(_pose[C_HRS], 0.0, w)
		_pose[C_HRR] = lerpf(_pose[C_HRR], 1.0, w)
		_pose[C_GRIP] = lerpf(_pose[C_GRIP], 0.0, w)
	# the free blade (out of the scabbard, not yet in it) kept a hand's breadth over the ground and outside the right leg, as in the carry:
	# a draw's sweep on the run leans down with him
	if _sw_at == AT_HAND and w < 1.0:
		var b0 := v3(_pose, C_HRB).normalized()
		_setv(_pose, C_HRB, b0.slerp(_blade_clear(_pose, v3(_pose, C_HR), b0), 1.0 - w))
	# the shield hand
	var wl := 0.0
	var sh := Transform3D()
	match action:
		"draw", "draw_shield":
			var tgs := _stow_t(action, "sh_grab")
			wl = smoothstep(tgs - 0.08, tgs, t) if t <= tgs else 1.0 - smoothstep(tgs, tgs + 0.05, t)
			if wl > 0.0:
				sh = _spear_pivot_of(root * tr[1], root * tr[2]) * _shb_rest(_show_lion)
		"sheathe", "sheathe_shield":
			# (the rim is taken where the keys bring the hand: the shield on the forearm moves with the hand, a target on it would
			# chase itself; the shield slides from the forearm into the fist as it changes hands, _hand_shield. It is hung exactly in
			# its place on the back.)
			var tb := _stow_t(action, "sh_back")
			wl = smoothstep(tb - 0.09, tb, t) if t <= tb else 1.0 - smoothstep(tb, tb + 0.05, t)
			sh = _spear_pivot_of(root * tr[1], root * tr[2]) * _shb_rest(_show_lion)
	if wl > 0.0:
		var hg := to_cs * (sh * _rim_grip())
		var hb := hg.basis.orthonormalized()
		_lerpv(_pose, C_HL, hg.origin - hb * GRIP, wl)
		_lerpv(_pose, C_HLB, (-hb.z).normalized(), wl)
		_lerpv(_pose, C_HLK, (-hb.x).normalized(), wl)
		_pose[C_HLX] = lerpf(_pose[C_HLX], 1.0, wl)
		_pose[C_HLR] = lerpf(_pose[C_HLR], 1.0, wl)
		_pose[C_HLS] = lerpf(_pose[C_HLS], 0.0, wl)


## Under a stow action (upper body): the legs and the hips stay the locomotion's, the trunk keeps the locomotion's posture (a draw on
## the run keeps the run's lean) and adds the action's own turn, and the arm a partial draw does not use stays the locomotion's.
func _stow_layer(src: PackedFloat32Array, loco: PackedFloat32Array) -> void:
	if not STOW_EV.has(action) or loco.size() != C_N:
		return
	_layer_lower(src, loco)
	var neu := default_pose()
	for o in [C_PELR, C_SPN, C_CHS, C_NEK, C_HED]:
		for j in 3:
			src[o + j] = loco[o + j] + (src[o + j] - neu[o + j])
	if action == "draw_sword" or action == "sheathe_sword":
		for o in [C_HL, C_HLF, C_HLP, C_HLW, C_HLB, C_HLK]:
			for j in 3:
				src[o + j] = loco[o + j]
		for o in [C_HLX, C_HLS, C_HLR, C_OHL]:
			src[o] = loco[o]
	elif action == "draw_shield" or action == "sheathe_shield":
		for o in [C_HR, C_HRB, C_HRK, C_HRP]:
			for j in 3:
				src[o + j] = loco[o + j]
		for o in [C_HRS, C_HRR, C_GRIP]:
			src[o] = loco[o]


# --- every frame: where the props are -----------------------------------------------------------------------------------------------

## After the solve: the moments of a draw or a sheathe (who holds what), the scabbard's swing, where the sword, the scabbard and the
## shield are this frame (rig space), how much the arms carry, where the spear lies on the back.
func _stow_frame(delta: float) -> void:
	if _scab_node == null:
		return
	var gx := global_transform if is_inside_tree() else transform
	var pel_skin := _skin_of(_bx[PELVIS], _rest[PELVIS])
	_empty_fist(delta)
	_scab_swing(delta, gx, pel_skin)
	if not _stow_ok:
		_stow_compute(pel_skin)
		_stow_ok = true
	# a stow action that started, ended or was cut
	var cur := action if STOW_EV.has(action) else ""
	if cur != _stow_act or (cur != "" and action_t < _stow_tp - 1e-4):
		if _stow_act != "":
			_stow_settle(_stow_act, pel_skin)
		_stow_act = cur
		_stow_fired.clear()
	_stow_tp = action_t
	# the blade in the scabbard (the scabbard lies along it) or not: when that changes, the scabbard leaves from where it was
	var ride := _sw_at == AT_HAND and _slide_sched() >= 0.0
	_stow_compute(pel_skin)
	if ride != _riding:
		var was := _scab_xf
		_riding = ride
		if not ride:
			_scab_hold(was, pel_skin)
		_stow_compute(pel_skin)
		_scab_off = _scab_xf.affine_inverse() * was
		_scab_off_k = 1.0
		_scab_off_rate = 16.0 if ride else 10.0
		_stow_compute(pel_skin)
	# the moments passed this frame
	if cur != "":
		var ev: Dictionary = STOW_EV[cur]
		for k in ev:
			if action_t >= float(ev[k]) and not _stow_fired.has(k):
				_stow_fired[k] = true
				_stow_event(k, pel_skin)
	# what is left of the hand-offs
	if delta > 0.0:
		_sw_off_k = maxf(0.0, _sw_off_k - delta * _sw_off_rate)
		_sh_off_k = maxf(0.0, _sh_off_k - delta * _sh_off_rate)
		_scab_off_k = maxf(0.0, _scab_off_k - delta * _scab_off_rate)
	_stow_compute(pel_skin)
	var r := delta / 0.25
	_carry_sw = move_toward(_carry_sw, 1.0 if _sw_at == AT_HAND else 0.0, r)
	_carry_sh = move_toward(_carry_sh, 1.0 if _sh_at == AT_ARM else 0.0, r)
	_alert = move_toward(_alert, clampf(alert, 0.0, 1.0), delta * 2.5)
	# the spear lies over the shield while the shield is on the back, and settles onto the cape as it is taken away
	var ov := 0.0
	if _sh_at == AT_BACK:
		ov = 1.0
	elif _sh_at == AT_RIM:
		var nb := _spear_pivot_of(_bx[SPINE], _bx[CHEST]) * _shb_rest(_show_lion)
		ov = 1.0 - smoothstep(0.04, 0.3, _sh_xf.origin.distance_to(nb.origin))
	_spear_over = ov if delta <= 0.0 else move_toward(_spear_over, ov, delta * 8.0)


static func _off_w(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


## The props' frames this frame from who holds them (and what is left of each hand-off).
func _stow_compute(pel_skin: Transform3D) -> void:
	var strap := _scab_frame(pel_skin, _scab_q())
	if _sw_at == AT_HAND:
		_sw_xf = _grip_r() * Transform3D(Basis(Vector3.RIGHT, _pose[C_GRIP]), Vector3.ZERO)
		if _sw_off_k > 0.0:
			_sw_xf = _sw_xf * Transform3D.IDENTITY.interpolate_with(_sw_off, _off_w(_sw_off_k))
		if _riding:
			# the scabbard on the blade: as far along it from the grip as the blade is out, at the point nearest its strap
			var d := -_sw_xf.basis.z.normalized()
			var s := clampf((strap.origin - _sw_xf.origin).dot(d), 0.0, SCAB_SLIDE + 0.05)
			_scab_xf = _sw_xf * Transform3D(SHEATH_ROLL.inverse(), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -s))
		else:
			_scab_xf = strap
		if _scab_off_k > 0.0:
			_scab_xf = _scab_xf * Transform3D.IDENTITY.interpolate_with(_scab_off, _off_w(_scab_off_k))
	else:
		_scab_xf = strap
		if _scab_off_k > 0.0:
			_scab_xf = _scab_xf * Transform3D.IDENTITY.interpolate_with(_scab_off, _off_w(_scab_off_k))
		_sw_xf = _scab_xf * Transform3D(SHEATH_ROLL, Vector3.ZERO)
		if _sw_off_k > 0.0:
			_sw_xf = _sw_xf * Transform3D.IDENTITY.interpolate_with(_sw_off, _off_w(_sw_off_k))
	var shn: Transform3D
	match _sh_at:
		AT_BACK:
			shn = _spear_pivot_of(_bx[SPINE], _bx[CHEST]) * _shb_rest(_show_lion)
		AT_RIM:
			shn = _grip_l() * _rim_grip().affine_inverse()
		_:
			shn = _shield_arm_nom()
	if _sh_off_k > 0.0:
		shn = shn * Transform3D.IDENTITY.interpolate_with(_sh_off, _off_w(_sh_off_k))
	_sh_xf = shn


## A moment of a draw or a sheathe: a prop changes hands (from exactly where it is now).
func _stow_event(k: String, pel_skin: Transform3D) -> void:
	var at := global_position if is_inside_tree() else Vector3.INF
	match k:
		"sw_grab":
			_hand_sword(AT_HAND, 14.0, pel_skin)
			_sfx("sword_draw", at, -6.0)
		"sw_home":
			_hand_sword(AT_SHEATH, 16.0, pel_skin)
		"sw_enter":
			_sfx("sword_sheathe", at, -6.0)
		"sh_grab":
			# (off the back the fist closes on the rim where it is; off the forearm the shield slides down the arm into the fist)
			_hand_shield(AT_RIM, 14.0 if _sh_at == AT_BACK else 5.0, pel_skin)
		"sh_arm":
			_hand_shield(AT_ARM, 6.0, pel_skin)
			_sfx("shield_draw", at, -6.0)
		"sh_back":
			_hand_shield(AT_BACK, 6.0, pel_skin)
			_sfx("shield_stow", at, -6.0)


func _sfx(nm: String, at: Vector3, db: float) -> void:
	if not is_inside_tree():
		return
	var s := get_node_or_null(^"/root/Sfx")
	if s != null and s.has_method("play"):
		s.call("play", nm, at + Vector3(0.0, 1.0, 0.0) if at.is_finite() else at, db, randf_range(0.95, 1.05))


func _hand_sword(to: int, rate: float, pel_skin: Transform3D) -> void:
	if to == _sw_at:
		return
	var was := _sw_xf
	if to == AT_SHEATH and _riding:
		# (the scabbard leaves the blade where it is: its swing takes the blade's turn, what the fist missed by dies away)
		var was_scab := _scab_xf
		_riding = false
		_scab_hold(was_scab, pel_skin)
		_scab_off_k = 0.0
		_stow_compute(pel_skin)
		_scab_off = _scab_xf.affine_inverse() * was_scab
		_scab_off_k = 1.0
		_scab_off_rate = 10.0
	_sw_at = to
	_sw_off_k = 0.0
	_stow_compute(pel_skin)
	_sw_off = _sw_xf.affine_inverse() * was
	_sw_off_k = 1.0
	_sw_off_rate = rate
	_stow_compute(pel_skin)


func _hand_shield(to: int, rate: float, pel_skin: Transform3D) -> void:
	if to == _sh_at:
		return
	var was := _sh_xf
	_sh_at = to
	_sh_off_k = 0.0
	_stow_compute(pel_skin)
	_sh_off = _sh_xf.affine_inverse() * was
	_sh_off_k = 1.0
	_sh_off_rate = rate
	_stow_compute(pel_skin)


## The scabbard left hanging at the frame `xf` (rig space): its swing takes that turn, and it springs back from there.
func _scab_hold(xf: Transform3D, pel_skin: Transform3D) -> void:
	var rest := scab_rest_xf()
	var r := (pel_skin.basis.inverse() * xf.basis.orthonormalized() * rest.basis.inverse()).get_rotation_quaternion()
	var a := r.get_axis() * r.get_angle() if r.get_angle() > 1e-5 else Vector3.ZERO
	_scab_a = a.limit_length(SCAB_SWING_MAX)
	_scab_av = Vector3.ZERO


## A draw or a sheathe ended or was cut: what is still in a fist goes where it was going (a quick settle).
func _stow_settle(a: String, pel_skin: Transform3D) -> void:
	if _sh_at == AT_RIM:
		_hand_shield(AT_ARM if a.begins_with("draw") else AT_BACK, 5.0, pel_skin)


## The scabbard swings on its strap: a damped spring back to its rest, driven by how the strap point accelerates and how the pelvis is
## tilted from upright; the chape never goes into the ground and the scabbard never into the left thigh.
func _scab_swing(delta: float, gx: Transform3D, pel_skin: Transform3D) -> void:
	if delta > 0.0:
		var hw := gx * (pel_skin * SCAB_HINGE)
		if not _scab_hok:
			_scab_hp = hw
			_scab_hv = Vector3.ZERO
			_scab_hok = true
		var v := (hw - _scab_hp) / delta + velocity_hint
		var acc := ((v - _scab_hv) / delta).limit_length(40.0)
		_scab_hp = hw
		_scab_hv = v
		var pw := gx.basis * pel_skin.basis
		var inv := pw.inverse()
		var rc := scab_rest_xf().basis * Vector3(0.0, 0.0, -0.45) + (SCAB_T - SCAB_HINGE)
		var f := -(inv * acc) * 0.6 + (inv * Vector3(0.0, -9.8, 0.0) - Vector3(0.0, -9.8, 0.0))
		var alpha := rc.cross(f) / rc.length_squared()
		var n := maxi(1, ceili(delta / (1.0 / 120.0)))
		var h := delta / float(n)
		for i in n:
			_scab_av += (alpha - _scab_a * SCAB_K - _scab_av * SCAB_C) * h
			_scab_a += _scab_av * h
		_scab_a = _scab_a.limit_length(SCAB_SWING_MAX)
	if _riding or float(_scab_sched()[1]) > 0.0:
		return
	# the ground and the thigh push it round its strap
	var hp := pel_skin * SCAB_HINGE
	for it in 2:
		var xf := _scab_frame(pel_skin, _scab_q())
		var e := xf * Vector3(0.0, 0.0, SCAB_END)
		var floor_y := minf(_gnd_dy.x, _gnd_dy.y) * _gnd_k + SCAB_GROUND
		var push := Vector3.ZERO
		var at := e
		if e.y < floor_y:
			push = Vector3(0.0, floor_y - e.y, 0.0)
		else:
			var a0 := xf * Vector3(0.0, 0.0, SCAB_THROAT)
			var ks := _seg_closest(a0, e, _bx[THIGH_L].origin, _bx[SHIN_L].origin)
			var dv: Vector3 = ks[0] - ks[1]
			var dl := dv.length()
			if dl < 0.135 and dl > 1e-4:
				push = dv / dl * (0.135 - dl)
				at = ks[0]
		if push == Vector3.ZERO:
			break
		var arm := at - hp
		var ax := arm.cross(push)
		if ax.length_squared() < 1e-10 or arm.length() < 0.05:
			break
		var ang := push.length() / arm.length()
		var axl := (pel_skin.basis.inverse() * ax).normalized()
		var q := Quaternion(axl, ang) * _scab_q()
		_scab_a = q.get_axis() * q.get_angle() if q.get_angle() > 1e-5 else Vector3.ZERO
		_scab_av *= 0.5


## The closest points of the segments a0-a1 and b0-b1: [on a, on b].
static func _seg_closest(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> Array:
	var d1 := a1 - a0
	var d2 := b1 - b0
	var r := a0 - b0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a > 1e-8 and e > 1e-8:
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var den := a * e - b * b
		s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-8 else 0.0
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return [a0 + d1 * s, b0 + d2 * t]


## The nodes where _stow_frame put the props (end of _apply_bones).
func _place_weapons() -> void:
	if _scab_node == null:
		return
	if not _stow_ok:
		_stow_compute(_skin_of(_bx[PELVIS], _rest[PELVIS]))
		_stow_ok = true
	_scab_node.transform = _scab_xf
	_sword.transform = _hand_r.transform.affine_inverse() * _sw_xf
	(_piv["farm_l_s"] as Node3D).transform = _sh_xf * _sh_rest_xf().affine_inverse()
	var k := smoothstep(0.0, 1.0, _spear_over)
	_spear_back.transform = spear_back_xf(_show_lion) if k <= 0.0 else spear_back_xf(_show_lion).interpolate_with(spear_over_xf(_show_lion), k)


## Builds the scabbard (on the belt; it swings there) and starts ARMED (the tools and the tests see the hero as before; the game
## stows the weapons at once, Hero._ready).
func _build_stow() -> void:
	_scab_node = Node3D.new()
	_scab_node.name = "Scabbard"
	add_child(_scab_node)
	var sm := scabbard_meshes()
	_rigid_mi(_scab_node, sm[0], _mat_soft, "ScabbardSoft")
	_rigid_mi(_scab_node, sm[1], _mat_metal, "ScabbardMetal")
	parts["scabbard"] = _scab_node
# --- the keyed draws and sheathes ------------------------------------------------------------------------------------------------

## A shield frame in chest space: its centre, its face's normal, the forearm's axis on it.
static func _shf(c: Vector3, n: Vector3, x: Vector3) -> Transform3D:
	var nn := n.normalized()
	var xx := perp(x, nn).normalized()
	return Transform3D(Basis(xx, nn, xx.cross(nn)), c)


## The left hand holding the shield by its rim with the shield at `s` (chest space): the hand's keys.
static func _rim_keys(s: Transform3D) -> Dictionary:
	var g := s * _rim_grip()
	var b := g.basis.orthonormalized()
	return {"hl": g.origin - b * GRIP, "hlb": -b.z, "hlk": -b.x, "hlx": 1.0, "hlr": 1.0, "hls": 0.0}


## Two keys mixed (positions and directions lerped, weights too; anything else taken from the nearer).
static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := a.duplicate()
	for key in b:
		if a.has(key) and a[key] is Vector3 and b[key] is Vector3:
			out[key] = (a[key] as Vector3).lerp(b[key], k)
		elif a.has(key) and a[key] is float and b[key] is float:
			out[key] = lerpf(a[key], b[key], k)
		elif k >= 0.5 or not a.has(key):
			out[key] = b[key]
	return out


## Keys for both arms and the trunk at the same moments: `t` the times, `r` the sword arm's, `l` the shield arm's and `k` the trunk's
## channels at each (a key inherits every channel it does not list from the key before it, so both arms are given at every moment).
static func _keys3(t: Array, r: Array, l: Array, k: Array) -> Array:
	var out: Array = []
	for i in t.size():
		out.append([t[i], _merge(_merge(r[i], l[i]), k[i])])
	return out


## draw, sheathe and the quick partial ones (added to the action table). Upper body: the legs keep the locomotion and the trunk keeps
## its posture, the keys only turn it (_stow_layer). The fists are put exactly on the grip and the rim at the moments they take them
## (_stow_pose), the props change hands there (_stow_frame); the throw and the catch get the variants that find the spear over the
## shield on the back.
static func _stow_actions(d: Dictionary) -> void:
	var neutral := NEUTRAL.duplicate()
	neutral.erase("rot")
	neutral.erase("piv")
	for lion in [false, true]:
		d["throw_over_lion" if lion else "throw_over"] = _throw_def(lion, neutral, true)
		d["catch_over_lion" if lion else "catch_over"] = _catch_def(lion, neutral, true)
	# the shield's path (chest space): on the back; slid down to the left out from under the spear; out at his left side turning its
	# face out; forward at his left side as the arm comes round under it
	var sb := _shb_rest(false)
	var s0 := Transform3D(sb.basis, sb.origin - P_CHEST)
	var lo := (sb.basis.x + sb.basis.z).normalized()
	var s1 := Transform3D(sb.basis, s0.origin + lo * 0.2 + sb.basis.y * 0.035)
	var s2 := _shf(Vector3(-0.5, -0.2, 0.22), Vector3(-0.8, 0.1, 0.6), Vector3(0.0, -1.0, 0.1))
	var s3 := _shf(Vector3(-0.47, -0.2, -0.1), Vector3(-0.98, 0.19, -0.06), Vector3(-0.1, -0.73, -0.67))
	# the sword's way (chest space, the trunk turned to the left as it is drawn): across the belly to the grip at the left hip; the
	# scabbard leads it out (_stow_pose) to high in front on the right; the blade sweeps down in front of him and trails back
	var reach := {"hr": Vector3(-0.18, -0.31, -0.26), "hrb": SCAB_D.normalized(), "hrk": Vector3(0.98, -0.06, 0.2), "hrp": Vector3(0.6, -0.6, 0.4), "hrr": 1.0, "hrs": 0.0}
	var out_end := {"hr": Vector3(0.42, 0.42, -0.48), "hrb": SCAB_D_DRAW.normalized(), "hrk": Vector3(0.75, -0.45, 0.5), "hrp": Vector3(0.9, -0.3, 0.3)}
	var sweep := {"hr": Vector3(0.37, 0.14, -0.48), "hrb": Vector3(0.18, -0.72, -0.67), "hrk": Vector3(0.95, 0.0, -0.3), "hrp": Vector3(0.8, -0.4, 0.5)}
	var swing_out := {"hr": Vector3(0.42, 0.08, -0.32), "hrb": Vector3(0.9, -0.42, -0.1), "hrk": Vector3(0.3, 0.6, -0.75), "hrp": Vector3(0.7, -0.4, 0.7)}
	var swing_back := {"hr": Vector3(0.4, -0.02, -0.12), "hrb": Vector3(0.42, -0.6, 0.68), "hrk": Vector3(0.85, 0.2, 0.5), "hrp": Vector3(0.6, -0.2, 1.0)}
	var carry := {"hr": Vector3(0.33, -0.45, 0.02), "hrb": Vector3(0.27, -0.57, 0.78), "hrk": Vector3(0.7, 0.0, -0.7), "hrp": Vector3(0.5, 0.0, 1.0)}
	var cocked := {"hr": Vector3(0.38, 0.12, -0.06), "hrb": Vector3(0.25, 0.55, 0.8), "hrk": Vector3(0.85, -0.3, 0.45), "hrp": Vector3(0.7, -0.6, 0.4)}
	var arm_carry := {"hl": Vector3(-0.34, -0.3, -0.12), "hlf": Vector3(-1.0, 0.05, -0.5), "hlp": Vector3(-0.5, -0.2, 1.0), "hlx": 0.0}
	var relax_r := {"hr": Vector3(0.31, -0.46, -0.03), "hrb": Vector3(0.05, -0.15, -1.0), "hrk": Vector3(1.0, 0.0, 0.05), "hrp": Vector3(0.5, 0.0, 1.0)}
	var relax_l := {"hl": Vector3(-0.31, -0.36, -0.02), "hlf": Vector3(-1.0, 0.0, -0.15), "hlp": Vector3(-0.5, -0.1, 1.0), "hlx": 0.0}
	var reach_back := _merge(_rim_keys(s0), {"hlp": Vector3(-0.8, 0.2, -0.6), "hlf": Vector3(-1.0, 0.0, 0.3)})
	var rim := func(a: Transform3D, b: Transform3D, k: float) -> Dictionary: return _rim_keys(a.interpolate_with(b, k))
	var turn_l := {"chs": Vector3(0.07, 0.17, 0.03), "spn": Vector3(0.02, 0.07, 0.0), "nek": Vector3(-0.05, -0.15, 0.0), "hed": Vector3(0.0, -0.06, 0.0)}
	var turn_0 := {"chs": Vector3(0.05, 0.0, 0.0), "spn": Vector3.ZERO, "nek": Vector3(-0.05, 0.0, 0.0), "hed": Vector3.ZERO}
	var turn_r := {"chs": Vector3(0.05, -0.06, 0.0), "spn": Vector3.ZERO, "nek": Vector3(-0.05, 0.03, 0.0), "hed": Vector3.ZERO}
	# draw (0.55 s): the right fist on the grip at 0.12 while the left reaches back for the rim (0.15); the blade out by 0.27, the shield
	# pulled out from under the spear and swung round his left side; the forearm into its band at 0.4; the handover to the armed carry
	d["draw"] = {"len": 0.55, "in": 0.06, "out": 0.15, "ho": 0.44, "dlen": 0.12, "fast": true, "ev": STOW_EV["draw"], "keys": _keys3(
		[0.0, 0.08, 0.15, 0.22, 0.27, 0.3, 0.34, 0.37, 0.43, 0.55],
		[{}, reach, reach, _mix(reach, out_end, 0.6), out_end, _mix(out_end, sweep, 0.45), sweep, swing_out, swing_back, carry],
		[{}, reach_back, _rim_keys(s0), _rim_keys(s1), rim.call(s1, s2, 0.55), _rim_keys(s2), rim.call(s2, s3, 0.55), _merge(_rim_keys(s3), {"hlp": Vector3(-0.8, -0.4, 0.4)}), arm_carry, arm_carry],
		[{}, turn_l, _mix(turn_l, turn_0, 0.3), _mix(turn_l, turn_0, 0.8), turn_r, turn_r, turn_r, _mix(turn_r, turn_0, 0.5), turn_0, turn_0])}
	# draw_sword (0.24 s, before a blow): the fist on the grip at 0.06, the blade out by 0.15 (Hero starts the blow then), cocked over
	# the right shoulder at the end
	d["draw_sword"] = {"len": 0.24, "in": 0.04, "out": 0.15, "dlen": 0.08, "fast": true, "ev": STOW_EV["draw_sword"], "keys": _keys3(
		[0.0, 0.05, 0.15, 0.24],
		[{}, reach, _merge(out_end, {"hr": Vector3(0.38, 0.3, -0.42)}), cocked],
		[{}, {}, {}, {}],
		[{}, _mix(turn_l, turn_0, 0.2), turn_r, _mix(turn_r, turn_0, 0.3)])}
	# draw_shield (0.26 s): the left fist on the rim at 0.07, pulled out and round, the forearm in at 0.18; it ends where the locomotion
	# takes it (the handover at 0.18 carries its speed on): at his side in the carry, or, as "draw_shield_guard" (_variant: the guard
	# held), up in front
	var s3q := _shf(Vector3(-0.42, -0.14, -0.22), Vector3(-0.9, 0.05, -0.45), Vector3(0.1, -0.8, -0.6))
	var up_front := _merge(arm_carry, {"hl": Vector3(-0.2, -0.1, -0.36), "hlf": Vector3(-0.4, 0.05, -1.0), "hlp": Vector3(-1.0, -0.6, 0.4)})
	for g in [false, true]:
		d["draw_shield_guard" if g else "draw_shield"] = {"len": 0.26, "in": 0.04, "out": 0.12, "ho": 0.18, "dlen": 0.08, "fast": true, "ev": STOW_EV["draw_shield"], "keys": _keys3(
			[0.0, 0.07, 0.11, 0.16, 0.26],
			[{}, {}, {}, {}, {}],
			[{}, reach_back, _rim_keys(s1), _merge(_rim_keys(s3q), {"hlp": Vector3(-0.8, -0.4, 0.4)}), up_front if g else arm_carry],
			[{}, {"chs": Vector3(0.05, 0.06, 0.0)}, {"chs": Vector3(0.05, 0.02, 0.0)}, {"chs": Vector3(0.05, -0.04, 0.0)}, turn_0])}
	# sheathe (0.8 s): the blade swings up in front and across, its tip finds the throat at 0.38 (the scabbard turned up to meet it) and
	# it slides home by 0.56; the left fist takes the shield's rim at 0.12, swings it round his left side and slides it in under the
	# spear (hung at 0.5); both hands come back to his sides
	var lift := {"hr": Vector3(0.36, 0.02, -0.44), "hrb": Vector3(0.2, -0.6, -0.77), "hrk": Vector3(0.95, 0.2, -0.2), "hrp": Vector3(0.8, -0.4, 0.5), "hrr": 1.0, "hrs": 0.0}
	var across := {"hr": Vector3(0.36, 0.42, -0.5), "hrb": SCAB_D_SHEATHE.normalized(), "hrk": Vector3(0.7, -0.45, 0.55), "hrp": Vector3(0.9, -0.3, 0.3)}
	var home := {"hr": Vector3(-0.18, -0.31, -0.26), "hrb": SCAB_D.normalized(), "hrk": Vector3(0.98, -0.06, 0.2), "hrp": Vector3(0.6, -0.6, 0.4)}
	var off_grip := {"hr": Vector3(0.0, -0.36, -0.3), "hrb": Vector3(0.0, -0.3, -1.0), "hrk": Vector3(1.0, 0.0, 0.1), "hrp": Vector3(0.6, -0.4, 0.6)}
	var let_go := {"hl": Vector3(-0.36, -0.2, 0.2), "hlf": Vector3(-1.0, 0.0, 0.2), "hlp": Vector3(-0.6, 0.0, -0.8), "hlx": 0.0}
	d["sheathe"] = {"len": 0.8, "in": 0.08, "out": 0.2, "ho": 0.62, "dlen": 0.12, "fast": true, "ev": STOW_EV["sheathe"], "keys": _keys3(
		[0.0, 0.12, 0.2, 0.26, 0.3, 0.38, 0.42, 0.5, 0.56, 0.62, 0.68, 0.8],
		[{}, lift, _mix(lift, across, 0.5), across, across, across, _mix(across, home, 0.4), _mix(across, home, 0.85), home, off_grip, _mix(off_grip, relax_r, 0.5), relax_r],
		[{}, _rim_keys(s3), _rim_keys(s3), rim.call(s3, s2, 0.6), _rim_keys(s2), rim.call(s2, s1, 0.6), _rim_keys(s1), _merge(_rim_keys(s0), {"hlp": Vector3(-0.8, 0.2, -0.6)}), _merge(_rim_keys(s0), {"hlp": Vector3(-0.8, 0.2, -0.6)}), let_go, _mix(let_go, relax_l, 0.5), relax_l],
		[{}, turn_0, _mix(turn_0, turn_l, 0.5), turn_l, turn_l, turn_l, turn_l, turn_l, _mix(turn_l, turn_0, 0.3), _mix(turn_l, turn_0, 0.7), turn_0, turn_0])}
	d["sheathe_sword"] = {"len": 0.62, "in": 0.06, "out": 0.18, "ho": 0.48, "dlen": 0.1, "fast": true, "ev": STOW_EV["sheathe_sword"], "keys": _keys3(
		[0.0, 0.1, 0.2, 0.26, 0.42, 0.5, 0.62],
		[{}, lift, across, across, home, off_grip, relax_r],
		[{}, {}, {}, {}, {}, {}, {}],
		[{}, turn_0, turn_l, turn_l, _mix(turn_l, turn_0, 0.3), _mix(turn_l, turn_0, 0.8), turn_0])}
	d["sheathe_shield"] = {"len": 0.55, "in": 0.06, "out": 0.18, "ho": 0.42, "dlen": 0.1, "fast": true, "ev": STOW_EV["sheathe_shield"], "keys": _keys3(
		[0.0, 0.08, 0.15, 0.22, 0.31, 0.36, 0.44, 0.55],
		[{}, {}, {}, {}, {}, {}, {}, {}],
		[{}, _rim_keys(s3), _rim_keys(s3), _rim_keys(s2), _rim_keys(s1), _merge(_rim_keys(s0), {"hlp": Vector3(-0.8, 0.2, -0.6)}), let_go, relax_l],
		[{}, turn_0, turn_0, {"chs": Vector3(0.05, 0.05, 0.0)}, {"chs": Vector3(0.05, 0.08, 0.0)}, {"chs": Vector3(0.05, 0.06, 0.0)}, turn_0, turn_0])}
	_draw_into_actions(d, reach, turn_l, turn_0, turn_r) # INTEGRATE: the quick draws that lead into the first blows
# --- the arms on the ground ----------------------------------------------------------------------------------------------------

## The arms on the ground (_ground_pose). Each arm is relaxed (empty: a loose fist swinging against the opposite leg, forward of the
## body more than behind it, the elbow bending with speed: the run pumps, P2) or armed (the sword carried low in the right fist, the
## blade trailing back and down, ref_sword_pose; the shield carried a little forward at his left side), by what is in its hand
## (_carry_sw / _carry_sh). Standing, the idles: relaxed (P1, hanging loose), armed (P9, the sword hanging low in his hand; with a
## foe close, `alert`, the ready stance: the shield up in front of his left side, the sword low at his right, the body lower).
func _ground_arms(c: PackedFloat32Array, vu: float, gw: float, th: float, run: float, mva: float, br: float, armk: float, land_arm: float, idle: float) -> void:
	var ph_a := TAU * _pl(vu, T_ARM_PH)
	var cs := cos(th - ph_a)
	var cs2 := cos(th - ph_a + 0.35)
	var ksw := smoothstep(0.0, 1.0, _carry_sw)
	var ksh := smoothstep(0.0, 1.0, _carry_sh)
	var rdy := smoothstep(0.0, 1.0, _alert)
	var brv := br * idle
	# the sword arm's joints (deg: flexion, abduction, elbow), relaxed and armed, moving and standing
	var r_mv := Vector3(_pl(vu, T_RX_C) + _pl(vu, T_RX_A) * armk * gw * cs, _pl(vu, T_RX_AB), _pl(vu, T_RX_EL) + _pl(vu, T_RX_ELV) * gw * cs2)
	var a_mv := Vector3(_pl(vu, T_AC_C) + _pl(vu, T_AC_A) * armk * gw * cs, _pl(vu, T_AC_AB), _pl(vu, T_AC_EL) + 7.0 * gw * cs2)
	var r_id := Vector3(-3.0 + brv, 9.0, 16.0 + 2.0 * brv)
	var a_id := Vector3(3.0, 11.0, 13.0 + brv).lerp(Vector3(8.0, 14.0, 32.0 + 2.0 * brv), rdy)
	var ang := r_id.lerp(r_mv, mva).lerp(a_id.lerp(a_mv, mva), ksw)
	ang.y += 22.0 * land_arm
	var fk := _arm_fk(1.0, deg_to_rad(ang.x), deg_to_rad(ang.y), deg_to_rad(ang.z), lerpf(lerpf(0.3, 0.36, run), 0.12, ksw))
	# the hand: relaxed, a loose fist with the wrist straight; armed, the blade trailing back and down (it rises and falls a little with
	# the swing), or, standing calm, hanging forward and down beside the right foot
	var rel: Array = _sword_hand(fk[2], deg_to_rad(4.0), deg_to_rad(6.0), 0.0)
	var ev := deg_to_rad(_pl(vu, T_AC_EV)) + 0.45 * deg_to_rad(ang.x - lerpf(3.0, _pl(vu, T_AC_C), mva))
	var az := deg_to_rad(16.0)
	var trail := Vector3(sin(az) * cos(ev), sin(ev), cos(az) * cos(ev))
	# (standing, the blade hangs steeper and a little more out, its tip near the ground behind his right heel: P9 with the sword)
	var evs := deg_to_rad(-44.0)
	var azs := deg_to_rad(24.0)
	var hang := Vector3(sin(azs) * cos(evs), sin(evs), cos(azs) * cos(evs))
	var blade := hang.slerp(trail, maxf(mva, rdy * 0.5))
	var bk := Vector3(0.7, 0.05, -0.7).normalized()
	var hrb := (rel[0] as Vector3).normalized().slerp(blade, ksw)
	var hrk := (rel[1] as Vector3).normalized().slerp(bk, ksw)
	var grip: Vector3 = (fk[0] as Vector3) + hand_basis(hrb, hrk, 1.0) * GRIP
	if ksw > 0.01:
		hrb = _blade_clear(c, grip, hrb)
	_setv(c, C_HR, grip)
	_setv(c, C_HRB, hrb)
	_setv(c, C_HRK, hrk)
	_setv(c, C_HRP, fk[1])
	# the left arm: relaxed (the right's mirror, swinging the other way) or carrying the shield
	# (the relaxed left arm swings a little wider than the right: the sword's hilt is at his left hip)
	var lr_mv := Vector3(_pl(vu, T_RX_C) - _pl(vu, T_RX_A) * armk * gw * cs, _pl(vu, T_RX_AB) + 7.0, _pl(vu, T_RX_EL) - _pl(vu, T_RX_ELV) * gw * cs2)
	var ls_mv := Vector3(_pl(vu, T_ARM_LC) - _pl(vu, T_ARM_LA) * armk * gw * cs, _pl(vu, T_AB_L), _pl(vu, T_EL_L) - 6.0 * gw * cs2)
	var lr_id := Vector3(-3.0 + brv, 15.0, 16.0 + 2.0 * brv)
	var ls_id := Vector3(5.0, 18.0, 38.0 + brv)
	var angl := lr_id.lerp(lr_mv, mva).lerp(ls_id.lerp(ls_mv, mva), ksh)
	angl.y += 22.0 * land_arm
	var psi_l := deg_to_rad(angl.x)
	var ab_l := deg_to_rad(angl.y)
	var el_l := deg_to_rad(angl.z)
	# the free hand out over the wheat (set_brush): the arm opens by its joints to where the brush pose holds it (out to the side, the
	# forearm hanging), so the shield does not sweep through the chest on its way there
	var bw := smooth(_brush)
	if bw > 0.0:
		psi_l = lerpf(psi_l, deg_to_rad(-26.0), bw)
		ab_l = lerpf(ab_l, deg_to_rad(58.0), smoothstep(0.0, 0.3, bw))
		el_l = lerpf(el_l, deg_to_rad(64.0), bw)
	var fkl := _arm_fk(-1.0, psi_l, ab_l, el_l, lerpf(lerpf(0.3, 0.36, run), 0.1 * run, ksh) * (1.0 - bw))
	var hl: Vector3 = fkl[0]
	var hlf := Vector3(-1.0, 0.0, -0.15).lerp(Vector3(-1.0, 0.0, -0.25).lerp(Vector3(-1.0, 0.05, -0.5), mva), ksh)
	var hlp: Vector3 = fkl[1]
	# the left hand resting on the sword's pommel at his hip (standing a while, the weapons put away)
	var pk := _pommel_rest(_solve_dt if _solve_dt > 0.0 else 1.0 / 60.0, idle)
	if pk > 0.001 and _scab_node != null:
		var tr := _trunk_xf(c)
		var top := (tr[2] as Transform3D).affine_inverse() * (_scab_xf * Vector3(0.0, 0.035, 0.15))
		hl = hl.lerp(top + Vector3(-0.015, 0.075, 0.035), pk)
		hlf = hlf.lerp(Vector3(-0.6, 0.6, -0.4), pk)
		hlp = hlp.lerp(Vector3(-1.0, 0.0, 0.5), pk)
	# the ready stance: the shield up in front of his left side
	var rk := rdy * ksh * (1.0 - mva)
	if rk > 0.001:
		hl = hl.lerp(Vector3(-0.22, -0.14, -0.38), rk)
		hlf = hlf.lerp(Vector3(-0.5, 0.05, -1.0), rk)
		hlp = hlp.lerp(Vector3(-1.0, -0.5, 0.4), rk)
	_setv(c, C_HL, hl)
	_setv(c, C_HLF, hlf)
	_setv(c, C_HLP, hlp)
	# the ready stance's body: lower, leaning in a little, the shield side forward (the head stays on the foe)
	var rb := rdy * ksw * idle
	if rb > 0.001:
		c[C_PEL + 1] -= 0.05 * rb
		c[C_SPN] -= 0.06 * rb
		c[C_CHS + 1] -= 0.1 * rb
		c[C_NEK + 1] += 0.08 * rb


## The carried blade `b` (chest space, from the fist at `grip`) turned so that its tip stays a hand's breadth over the ground and the
## blade passes outside the right leg (judged on the pose being built).
func _blade_clear(c: PackedFloat32Array, grip: Vector3, b: Vector3) -> Vector3:
	var tr := _trunk_xf(c)
	var ch: Transform3D = tr[2]
	var pel: Transform3D = tr[0]
	var g := ch * grip
	var bw := (ch.basis * b).normalized()
	var ln := -SWORD_TIP
	var hip := pel.origin + pel.basis * (P_HIP - P_PELVIS)
	var ank := v3(c, C_FR)
	for it in 2:
		var tip := g + bw * ln
		var low := 0.26 + minf(_gnd_dy.x, _gnd_dy.y) * _gnd_k
		if tip.y < low:
			var ax := bw.cross(Vector3.UP)
			if ax.length_squared() > 1e-6:
				bw = bw.rotated(ax.normalized(), asin(clampf((low - tip.y) / ln, 0.0, 0.9)))
		var ks := _seg_closest(g + bw * 0.12, g + bw * ln, hip, ank)
		var dv: Vector3 = ks[0] - ks[1]
		var dl := dv.length()
		if dl < 0.15:
			var away := dv / dl if dl > 1e-4 else Vector3.RIGHT
			var arm: Vector3 = (ks[0] as Vector3) - g
			var ax2 := arm.cross(away)
			if ax2.length_squared() > 1e-8:
				bw = bw.rotated(ax2.normalized(), (0.15 - dl) / maxf(arm.length(), 0.2))
	return (ch.basis.inverse() * bw).normalized()


## An empty right fist (the sword in its scabbard): the hand turned to lie along the forearm (a loose fist, the wrist straight), except
## where a stow action is closing it on the grip. After the solve, before the bones are applied.
var _fist_free := 0.0


func _empty_fist(delta: float) -> void:
	var want := 1.0 if _sw_at == AT_SHEATH else 0.0
	if want > 0.0 and STOW_EV.has(action):
		# (the fist turns to the grip as it reaches for it, and stays a fist round it until the sword is out)
		var tg := _stow_t(action, "sw_grab")
		var th := _stow_t(action, "sw_home")
		if tg >= 0.0:
			want = 1.0 - smoothstep(tg - 0.12, tg - 0.03, action_t)
		elif th >= 0.0:
			want = smoothstep(th, th + 0.08, action_t)
	_fist_free = want if delta <= 0.0 else move_toward(_fist_free, want, delta * 8.0)
	if _fist_free <= 0.001:
		return
	var h := _bx[HAND_R]
	var fa := _bx[FARM_R]
	# (the forearm's frame, the fingers curled a little in towards the palm)
	var relaxed := (fa.basis * Basis(Vector3.BACK, -0.12)).orthonormalized()
	var q := h.basis.orthonormalized().get_rotation_quaternion().slerp(relaxed.get_rotation_quaternion(), smoothstep(0.0, 1.0, _fist_free))
	_bx[HAND_R] = Transform3D(Basis(q), h.origin)
# --- the idle --------------------------------------------------------------------------------------------------------------------

## The weight of the idle on one leg (-1 the left .. 1 the right), where it is going, the clock of the next shift; the left hand
## resting on the sword's pommel at his hip (0..1) and its clock.
var _idle_w := 1.0
var _idle_goal := 1.0
var _idle_next := 7.0
var _pommel := 0.0
var _pommel_t := 0.0


## Standing (P1), the weight on one leg, changing legs every 6-11 s (over a second and a half); none in the ready stance. Returns the
## shift (-1..1) scaled by how much he stands.
func _idle_shift(dt: float, idle: float) -> float:
	if idle > 0.5:
		_idle_next -= dt
		if _idle_next <= 0.0:
			_idle_goal = -_idle_goal
			_idle_next = 6.0 + 5.0 * fposmod(sin(t * 12.9898) * 43758.5453, 1.0)
	_idle_w = lerpf(_idle_w, _idle_goal, 1.0 - exp(-dt * 1.8))
	var calm := 1.0 - smoothstep(0.0, 1.0, _alert) * smoothstep(0.0, 1.0, _carry_sw)
	return _idle_w * idle * calm


## Standing a while with the sword in its scabbard, now and then his left hand comes to rest on its pommel (a few seconds in every
## eleven). Returns how far it is there (0..1).
func _pommel_rest(dt: float, idle: float) -> float:
	var free := idle > 0.95 and _sw_at == AT_SHEATH and _sh_at == AT_BACK and not guard and _brush <= 0.0005 and _alert < 0.05
	_pommel_t = _pommel_t + dt if free else 0.0
	var ph := fposmod(_pommel_t, 11.0)
	var want := 1.0 if (free and _pommel_t > 3.0 and ph > 3.0 and ph < 7.5) else 0.0
	_pommel = move_toward(_pommel, want, dt / 0.6)
	return smoothstep(0.0, 1.0, _pommel)
# <<< STOW END

# >>> INTEGRATE BEGIN (step INTEGRATE: the lanes wired together; docs/ANIMATION.md section 10)
# --- a blow pressed with the sword in its scabbard ----------------------------------------------------------------------------------
## The blow the next draw_sword leads into ("" the plain quick draw): Hero sets it right before it plays draw_sword for a pressed blow,
## and the variant "draw_sword_<blow>" plays (_variant: `action` stays "draw_sword", so all of STOW's scabbard work runs as for it).
var draw_into := ""
## Per first blow (the routing rule's A1, B1 and the dash): the moment of the draw at which the blow takes over (`go`, the draw's own
## seconds) and the moment of the blow it starts at (`skip`, the blow's seconds): the draw ends exactly on the blow's pose there (the
## sword arm and the trunk), so the blow's own wind-up goes on from it.
const DRAW_INTO := {
	"a1": {"go": 0.245, "skip": 0.06},
	"b1": {"go": 0.245, "skip": 0.05},
	"dash": {"go": 0.245, "skip": 0.05},
}


## The quick draws that lead into the first blows (added to the action table by _stow_actions). The fist on the grip at 0.06 and the
## blade free at 0.15 as in draw_sword (STOW_EV: the same scabbard work); then, instead of cocking the sword back over his shoulder
## (the blade would pass behind his back: through the shield hung there and the cloak), the free blade swings down in front of him
## under the hand and out round his right side, the tip going back as the hand comes down into the blow's pose at `skip`.
static func _draw_into_actions(d: Dictionary, reach: Dictionary, turn_l: Dictionary, turn_0: Dictionary, turn_r: Dictionary) -> void:
	var out := {"hr": Vector3(0.38, 0.3, -0.42), "hrb": SCAB_D_DRAW.normalized(), "hrk": Vector3(0.75, -0.45, 0.5), "hrp": Vector3(0.9, -0.3, 0.3)}
	var dip := {"hr": Vector3(0.42, 0.1, -0.4), "hrb": Vector3(0.45, -0.5, -0.74).normalized(), "hrk": Vector3(0.95, 0.15, -0.25), "hrp": Vector3(0.8, -0.4, 0.5)}
	var side := {"hr": Vector3(0.46, -0.08, -0.2), "hrb": Vector3(0.9, -0.38, 0.2).normalized(), "hrk": Vector3(0.4, 0.5, -0.75), "hrp": Vector3(0.7, -0.4, 0.7)}
	for nm in DRAW_INTO:
		var e: Dictionary = DRAW_INTO[nm]
		var go := float(e["go"])
		var c := _strike_pose(_strike_raw(nm), float(e["skip"]))
		var tgt := {"hrr": 1.0, "hrs": 0.0, "grip": 0.0}
		for ch in ["hr", "hrb", "hrk", "hrp", "pelr", "spn", "chs", "nek", "hed"]:
			tgt[ch] = v3(c, CH[ch])
		d["draw_sword_" + nm] = {"len": go + 0.08, "in": 0.04, "out": 0.12, "dlen": 0.08, "fast": true, "ev": STOW_EV["draw_sword"], "keys": _keys3(
			[0.0, 0.05, 0.15, 0.185, 0.215, go, go + 0.08],
			[{}, reach, out, dip, side, tgt, tgt],
			[{}, {}, {}, {}, {}, {}, {}],
			[{}, _mix(turn_l, turn_0, 0.2), turn_r, turn_r, _mix(turn_r, turn_0, 0.5), {}, {}])}


## The draw that leads into a blow is playing: the moment (its seconds) at which the blow takes over; -1 when none is.
func draw_go() -> float:
	var nm := _draw_into_now()
	return float(DRAW_INTO[nm]["go"]) if nm != "" else -1.0


## ... and the moment of the blow it starts at (0 when none is).
func draw_skip() -> float:
	var nm := _draw_into_now()
	return float(DRAW_INTO[nm]["skip"]) if nm != "" else 0.0


func _draw_into_now() -> String:
	if action == "draw_sword" and _akey.begins_with("draw_sword_"):
		var nm := _akey.substr(11)
		if DRAW_INTO.has(nm):
			return nm
	return ""
# <<< INTEGRATE END
