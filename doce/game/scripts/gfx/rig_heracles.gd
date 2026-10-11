class_name RigHeracles
extends Rig
## Heracles: a skinned code rig (Skeleton3D, 30 bones) about 1.9 m tall with a Corinthian helmet and crest, a bronze
## cuirass, the red cape (cloth: one bone per particle), the aspis on the left forearm, the xiphos in the right hand
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
const SKIN := Color("D69A68")
const SKIN_DARK := Color("B97C52")
const BRONZE := Color("D19A44")
const BRONZE_DARK := Color("9C6B2E")
const BRONZE_LIGHT := Color("EFC172")
const RED := Color("B8302A")
const RED_DARK := Color("8C2226")
const CREST := Color("C9372C")
const CREST_DARK := Color("98272A")
const CREST_LIGHT := Color("E25A40")
const LEATHER := Color("7C4A2C")
const LEATHER_DARK := Color("4E2C1C")
const LEATHER_LIGHT := Color("9C6238")
const SHADOW := Color("1E1824")
const STEEL := Color("CCD5DE")
const STEEL_DARK := Color("8D98A8")
const STEEL_LIGHT := Color("EEF3F7")
const WOOD := Color("5A3A28")
const WOOD_DARK := Color("432A1E")
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
const HEAD_C := Vector3(0.0, 1.75, 0.005) # helmet centre
const P_CREST := Vector3(0.0, 1.90, 0.02)
const SKIRT_Y := 1.0
const SKIRT_R := 0.19
## Fist centre (where the sword grip passes) in hand space, from the wrist.
const GRIP := Vector3(0.0, -0.104, 0.0)
## Hands are drawn this much bigger than life (heroic proportions).
const HAND_K := 1.18
const FWD := Vector3(0.0, 0.0, -1.0)
const SHIELD_R := 0.34
## The left fist holds the spear this far towards its head from the spear's own origin.
const SPEAR_HOLD := 0.22
## don_skin: when the pelt replaces the cape and when the paws are knotted on the chest (s).
const DON_SWAP := 0.78
const DON_KNOT := 1.62
## throw: the left hand closes on the shaft (the spear leaves the back) and lets it go (s).
const THROW_GRAB := 0.17
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
	C_HLK = 73, C_HLX = 76, C_HLS = 77, C_HRS = 78, C_N = 79 }
## pel/pelr/spn/chs/nek/hed: pelvis offset + Euler (x pitch, + leans back; y yaw, + turns left; z roll) and the
## spine bones' Euler. hr: right grip (chest space), hrb blade direction, hrk back of the hand, hrp elbow pole.
## hl: left wrist (chest space), hlf where the shield faces, hlp elbow pole, hlw wrist Euler; hlb/hlk an explicit
## left hand basis (spear held: hlb = spear direction) weighted by hlx. hrs/hls: 1 puts that hand's targets in rig
## space (before `rot`) instead of chest space. fr/fl ankles, frr/flr foot Euler, frp/flp knee poles (rig space).
## rot: whole-body rotation vector about piv. grip: sword roll in the fist. ohl: open left hand. hood: lion hood
## (0 down on the back .. 1 on the head).
const CH := {"pel": C_PEL, "pelr": C_PELR, "spn": C_SPN, "chs": C_CHS, "nek": C_NEK, "hed": C_HED, "hr": C_HR,
	"hrb": C_HRB, "hrk": C_HRK, "hrp": C_HRP, "hl": C_HL, "hlf": C_HLF, "hlp": C_HLP, "hlw": C_HLW, "fr": C_FR,
	"frr": C_FRR, "frp": C_FRP, "fl": C_FL, "flr": C_FLR, "flp": C_FLP, "rot": C_ROT, "piv": C_PIV, "grip": C_GRIP,
	"ohl": C_OHL, "spr": C_SPR, "hood": C_HOOD, "hlb": C_HLB, "hlk": C_HLK, "hlx": C_HLX, "hls": C_HLS, "hrs": C_HRS}

## Neutral stance (hands in chest space, feet in rig space).
const NEUTRAL := {
	"pel": Vector3(0.0, -0.035, 0.0), "pelr": Vector3(0.02, 0.0, 0.0), "spn": Vector3(0.0, 0.0, 0.0),
	"chs": Vector3(0.05, 0.0, 0.0), "nek": Vector3(-0.05, 0.0, 0.0), "hed": Vector3(0.0, 0.0, 0.0),
	"hr": Vector3(0.335, -0.42, -0.1), "hrb": Vector3(0.12, -0.38, -1.0), "hrk": Vector3(1.0, 0.1, 0.15),
	"hrp": Vector3(0.5, 0.0, 1.0),
	"hl": Vector3(-0.335, -0.36, -0.08), "hlf": Vector3(-1.0, 0.0, -0.35), "hlp": Vector3(-0.5, -0.2, 1.0),
	"hlw": Vector3.ZERO,
	"fr": Vector3(0.15, 0.093, 0.04), "frr": Vector3(0.0, -0.18, 0.0), "frp": Vector3(0.25, 0.0, -1.0),
	"fl": Vector3(-0.15, 0.093, -0.06), "flr": Vector3(0.0, 0.18, 0.0), "flp": Vector3(-0.25, 0.0, -1.0),
	"rot": Vector3.ZERO, "piv": Vector3(0.0, 0.9, 0.0), "grip": 0.0, "ohl": 0.0, "spr": 0.0, "hood": 1.0,
	"hlb": Vector3(0.0, 0.0, -1.0), "hlk": Vector3(-1.0, 0.0, 0.0), "hlx": 0.0, "hls": 0.0, "hrs": 0.0,
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
var _crest_mi: MeshInstance3D
var _helm_mi: MeshInstance3D
var _mat_helm: ShaderMaterial
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
	# the helmet has its own copy: under the lion hood it sinks into shadow
	_mat_helm = _mat_metal.duplicate() as ShaderMaterial
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

## [soft mesh, metal mesh] of the whole body (helmet, hands and props excluded), skinned to the NB bones.
static func body_meshes() -> Array:
	if not _cache.has("body"):
		_cache["body"] = _build_body()
	return _cache["body"]


static func _w2(b0: int, b1: int, k: float) -> PackedFloat32Array:
	k = clampf(k, 0.0, 1.0)
	return PackedFloat32Array([float(b0), 1.0 - k, float(b1), k])


static func _build_body() -> Array:
	var sm := SkinMesh.new(31)
	var soft := sm.soft
	var metal := sm.metal
	soft.vary = 0.0
	metal.vary = 0.0
	# --- cuirass (bronze), chest + spine ---
	var prof := [
		[0.995, 0.184, 0.15, 0.148, 0.0],
		[1.02, 0.188, 0.155, 0.152, 0.0],
		[1.045, 0.171, 0.145, 0.14, 0.0],
		[1.09, 0.156, 0.135, 0.126, 0.002],
		[1.15, 0.163, 0.138, 0.126, 0.0],
		[1.21, 0.182, 0.147, 0.133, 0.0],
		[1.27, 0.205, 0.159, 0.143, -0.002],
		[1.33, 0.224, 0.171, 0.153, -0.004],
		[1.39, 0.233, 0.176, 0.159, -0.004],
		[1.44, 0.228, 0.166, 0.161, 0.0],
		[1.48, 0.207, 0.138, 0.153, 0.008],
		[1.51, 0.168, 0.106, 0.133, 0.012],
		[1.535, 0.122, 0.086, 0.102, 0.015],
		[1.548, 0.1, 0.078, 0.088, 0.016],
	]
	var sculpt := func(p: Vector3) -> Vector3:
		var o := Vector3.ZERO
		if p.z < 0.0:
			var q := Vector2(absf(p.x), p.y)
			# pectorals with a crisp lower edge
			var pec := bump(q, Vector2(0.088, 1.405), Vector2(0.11, 0.09))
			pec *= smoothstep(1.305, 1.345, p.y)
			# abdominals: 2 x 3 pads either side of the linea alba
			var ab := 0.0
			for yy in [1.13, 1.19, 1.25]:
				ab += bump(q, Vector2(0.05, yy), Vector2(0.042, 0.032))
			var groove := 1.0 - smoothstep(0.0, 0.016, absf(p.x))
			o.z -= pec * 0.032 + ab * 0.014 - groove * 0.008 * smoothstep(1.1, 1.18, p.y) * (1.0 - smoothstep(1.36, 1.44, p.y))
		else:
			# shoulder blades and the spine groove
			var q2 := Vector2(absf(p.x), p.y)
			o.z += bump(q2, Vector2(0.1, 1.38), Vector2(0.09, 0.1)) * 0.014
			o.z -= (1.0 - smoothstep(0.0, 0.02, absf(p.x))) * 0.008 * smoothstep(1.1, 1.2, p.y)
		return o
	var cuirass_col := func(p: Vector3, k: int, _i: int) -> Color:
		if k <= 1:
			return BRONZE_DARK
		if k == 2:
			return BRONZE_LIGHT
		return BRONZE
	hloft(metal, prof, 28, cuirass_col, 2.5, sculpt)
	# underside of the flared rim (so the hem reads from below)
	hloft(metal, [[0.995, 0.188, 0.152, 0.150, 0.0], [1.02, 0.165, 0.13, 0.13, 0.0]], 28, BRONZE_DARK, 2.5)
	sm.bind(func(p: Vector3) -> PackedFloat32Array:
		if p.y > 1.5:
			return PackedFloat32Array([float(CHEST), 1.0])
		return _w2(SPINE, CHEST, smoothstep(1.17, 1.28, p.y)))
	# neck (skin), from inside the cuirass collar into the helmet
	soft.push(Transform3D.IDENTITY)
	loft(soft, [[Vector3(0, 1.49, 0.02), 0.078, 0.08], [Vector3(0, 1.56, 0.018), 0.074, 0.076], [Vector3(0, 1.64, 0.01), 0.068, 0.07], [Vector3(0, 1.70, 0.0), 0.06, 0.06]], 12, SKIN, FWD, false, true)
	soft.pop()
	sm.bind(func(p: Vector3) -> PackedFloat32Array:
		if p.y < 1.56:
			return _w2(CHEST, NECK, smoothstep(1.5, 1.56, p.y))
		return _w2(NECK, HEAD, smoothstep(1.6, 1.68, p.y)))
	# belt (leather) under the cuirass flare
	hloft(soft, [[0.955, 0.176, 0.146, 0.146, 0.0], [1.005, 0.181, 0.150, 0.150, 0.0], [1.04, 0.172, 0.140, 0.138, 0.0]], 24, LEATHER_DARK, 2.5)
	sm.bind(func(p: Vector3) -> PackedFloat32Array: return _w2(PELVIS, SPINE, smoothstep(0.98, 1.04, p.y)))
	# hips / chiton under-layer (red) so nothing shows under the skirt
	hloft(soft, [[0.80, 0.11, 0.09, 0.10, 0.01], [0.86, 0.17, 0.12, 0.14, 0.01], [0.93, 0.182, 0.14, 0.15, 0.0], [0.98, 0.18, 0.145, 0.15, 0.0]], 18, RED_DARK, 2.5, Callable(), false, true)
	sm.rigid(PELVIS)
	# chiton skirt (red, pleated), skinned to the skirt bones by angle
	var skirt_prof := []
	var ys := [1.02, 0.97, 0.91, 0.85, 0.79, 0.745, 0.732]
	var rs := [0.18, 0.196, 0.211, 0.226, 0.241, 0.25, 0.248]
	for k in ys.size():
		skirt_prof.append([ys[k], rs[k] * 1.04, rs[k] * 0.96, rs[k] * 0.98, 0.0])
	var pleat := func(p: Vector3) -> Vector3:
		var a := atan2(p.x, -p.z)
		var depth := smoothstep(0.98, 0.72, p.y)
		var r := cos(a * 14.0) * 0.011 * depth
		var d := Vector3(p.x, 0, p.z).normalized()
		return d * r
	var skirt_col := func(p: Vector3, k: int, _i: int) -> Color:
		if k >= ys.size() - 2:
			return RED_DARK
		return RED
	hloft(soft, skirt_prof, 28, skirt_col, 2.2, pleat)
	# inner face of the skirt (darker), so the inside reads when the hem lifts
	var inner := []
	for e in skirt_prof:
		inner.append([e[0], e[1] - 0.01, e[2] - 0.01, e[3] - 0.01, 0.0])
	inner.reverse()
	hloft(soft, inner, 28, RED_DARK.darkened(0.25), 2.2, pleat)
	sm.bind(func(p: Vector3) -> PackedFloat32Array: return _skirt_w(p))
	# pteruges: leather strips over the skirt, bronze studs
	var nstrip := 14
	for i in nstrip:
		var a := TAU * (float(i) + 0.5) / float(nstrip)
		var d := Vector3(sin(a), 0.0, -cos(a))
		var t := Vector3(cos(a), 0.0, sin(a))
		var top := 1.035
		var bot := 0.79 if i % 2 == 0 else 0.805
		var r_top := 0.188
		var r_bot := 0.24
		var w := 0.043
		var th := 0.014
		var p0 := Vector3(0, top, 0) + d * (r_top + 0.012)
		var p1 := Vector3(0, bot, 0) + d * (r_bot + 0.02)
		var nrm := (d * (top - bot) + Vector3.UP * (r_bot - r_top)).normalized()
		var colr := LEATHER if i % 2 == 0 else LEATHER_LIGHT
		# a slab: front face, back face, sides, rounded bottom
		var fa := [p0 - t * w + nrm * th, p0 + t * w + nrm * th, p1 + t * (w * 0.95) + nrm * th, p1 - t * (w * 0.95) + nrm * th]
		var ba := [p0 - t * w, p0 + t * w, p1 + t * (w * 0.95), p1 - t * (w * 0.95)]
		var tip := p1 + (p1 - p0).normalized() * 0.03
		soft.quad(fa[0], fa[3], fa[2], fa[1], colr)
		soft.quad(ba[0], ba[1], ba[2], ba[3], colr.darkened(0.3))
		soft.quad(ba[0], ba[3], fa[3], fa[0], colr.darkened(0.12))
		soft.quad(ba[1], fa[1], fa[2], ba[2], colr.darkened(0.12))
		soft.tri(fa[3], tip + nrm * th, fa[2], colr)
		soft.tri(ba[3], ba[2], tip, colr.darkened(0.3))
		soft.quad(fa[3], ba[3], tip, tip + nrm * th, colr.darkened(0.12))
		soft.quad(ba[2], fa[2], tip + nrm * th, tip, colr.darkened(0.12))
		metal.ico(p1 + nrm * (th + 0.004) - (p1 - p0).normalized() * 0.015, 0.012, BRONZE_LIGHT, 0)
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
		# stations along the arm: arc length from the shoulder joint, radii (side, front)
		var st := [[-0.055, 0.05, 0.05], [-0.025, 0.083, 0.086], [0.02, 0.094, 0.09], [0.07, 0.09, 0.086],
			[0.12, 0.083, 0.082], [0.18, 0.076, 0.08], [0.24, 0.068, 0.073], [0.285, 0.062, 0.064],
			[0.315, 0.062, 0.062], [0.35, 0.071, 0.067], [0.395, 0.074, 0.065], [0.45, 0.066, 0.057],
			[0.51, 0.056, 0.048], [0.555, 0.049, 0.043], [0.575, 0.046, 0.04]]
		var rings := []
		for e in st:
			var sd: float = e[0]
			var c: Vector3
			if sd <= LEN_UA:
				c = sh + dua * sd
			else:
				c = el + dfa * (sd - LEN_UA)
			# deltoid sits outwards, biceps forwards
			c += lat * 0.012 * bump(Vector2(sd, 0), Vector2(0.02, 0), Vector2(0.1, 1))
			c += FWD * 0.008 * bump(Vector2(sd, 0), Vector2(0.15, 0), Vector2(0.09, 1))
			rings.append([c, e[1], e[2]])
		loft(soft, rings, 12, SKIN, FWD, true, true)
		var cl := CLAV_R + o
		var ua := UARM_R + o
		var fa := FARM_R + o
		sm.bind(func(p: Vector3) -> PackedFloat32Array:
			var e := (p - el).dot((dua + dfa).normalized())
			if e > -0.07:
				return _w2(ua, fa, smoothstep(-0.05, 0.05, e))
			var top := (p - sh).dot(dua)
			return _w2(cl, ua, smoothstep(-0.05, 0.035, top)))
		# bracer (leather) with bronze rims
		var b0 := el + dfa * 0.10
		var b1 := el + dfa * 0.268
		loft(soft, [[b0, 0.079, 0.072], [el + dfa * 0.14, 0.078, 0.07], [el + dfa * 0.2, 0.07, 0.062], [b1 - dfa * 0.01, 0.061, 0.054], [b1, 0.062, 0.055]], 12, LEATHER, FWD, false, false)
		loft(soft, [[b1, 0.062, 0.055], [b1 - dfa * 0.01, 0.052, 0.045]], 12, LEATHER_DARK, FWD, false, false)
		loft(soft, [[b0 - dfa * 0.004, 0.068, 0.062], [b0, 0.079, 0.072]], 12, LEATHER_DARK, FWD, false, false)
		loft(metal, [[b0 - dfa * 0.006, 0.082, 0.075], [b0 + dfa * 0.016, 0.083, 0.076]], 12, BRONZE, FWD, false, false)
		loft(metal, [[b1 - dfa * 0.02, 0.066, 0.059], [b1 - dfa * 0.004, 0.066, 0.059]], 12, BRONZE, FWD, false, false)
		# lacing on the inner forearm
		for k in 3:
			var lp := el + dfa * (0.15 + 0.035 * float(k))
			soft.box(lp - lat * 0.067, Vector3(0.012, 0.012, 0.03), LEATHER_DARK)
		sm.rigid(fa)
		# pauldron (bronze), on its own bone between the clavicle and the upper arm
		var pc := sh + Vector3(0.012 * s, 0.03, 0.0)
		metal.push(Transform3D(Basis(Vector3.BACK, -0.32 * s), pc))
		var pp := []
		for e2 in [[0.075, 0.0, 0.0], [0.07, 0.03, 0.0], [0.055, 0.06, 0.0], [0.03, 0.08, 0.0]]:
			pp.append(e2)
		_pauldron(metal)
		metal.pop()
		sm.rigid(PAUL_R + side)
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
		var st := [[-0.08, 0.05, 0.05], [-0.04, 0.094, 0.098], [0.02, 0.106, 0.108], [0.1, 0.104, 0.104],
			[0.18, 0.097, 0.097], [0.26, 0.089, 0.088], [0.34, 0.078, 0.078], [0.4, 0.069, 0.07],
			[0.43, 0.066, 0.068], [0.47, 0.066, 0.07], [0.53, 0.067, 0.077], [0.6, 0.066, 0.08],
			[0.68, 0.06, 0.068], [0.76, 0.05, 0.053], [0.815, 0.045, 0.047], [0.84, 0.043, 0.044]]
		var rings := []
		for e in st:
			var sd: float = e[0]
			var c: Vector3
			if sd <= LEN_TH:
				c = hp + dth * sd
			else:
				c = kn + dsh * (sd - LEN_TH)
			c += lat * 0.01 * bump(Vector2(sd, 0), Vector2(0.06, 0), Vector2(0.14, 1))
			c -= FWD * 0.012 * bump(Vector2(sd, 0), Vector2(0.6, 0), Vector2(0.12, 1))
			rings.append([c, e[1], e[2]])
		loft(soft, rings, 12, SKIN, FWD, true, false)
		var th := THIGH_R + o
		var shb := SHIN_R + o
		var ft := FOOT_R + o
		sm.bind(func(p: Vector3) -> PackedFloat32Array:
			var e := (p - kn).dot((dth + dsh).normalized())
			if e > 0.25:
				return _w2(shb, ft, smoothstep(0.37, 0.41, (p - kn).dot(dsh)))
			if e > -0.08:
				return _w2(th, shb, smoothstep(-0.05, 0.05, e))
			var top := (p - hp).dot(dth)
			return _w2(PELVIS, th, smoothstep(-0.06, 0.06, top)))
		# greave (bronze shell) with a knee cap
		var gst := [[0.418, 0.06, 0.066], [0.44, 0.077, 0.082], [0.49, 0.079, 0.087], [0.55, 0.08, 0.091],
			[0.62, 0.078, 0.092], [0.69, 0.07, 0.08], [0.75, 0.06, 0.064], [0.782, 0.056, 0.058], [0.797, 0.047, 0.048]]
		var grings := []
		for e in gst:
			var sd: float = e[0]
			var c := kn + dsh * (sd - LEN_TH)
			c -= FWD * 0.012 * bump(Vector2(sd, 0), Vector2(0.6, 0), Vector2(0.12, 1))
			grings.append([c, e[1], e[2]])
		var gshape := func(_k: int, a: float) -> Vector2:
			# a ridge down the shin (front = +z of the ring frame = forward)
			var f := maxf(0.0, sin(a))
			return Vector2(0.0, pow(f, 6.0) * 0.012)
		loft(metal, grings, 18, func(_p: Vector3, k: int, _i: int) -> Color: return BRONZE_LIGHT if k == 0 or k == 7 else BRONZE, FWD, false, false, gshape)
		metal.ico(kn + dsh * 0.02 + FWD * 0.072, 0.05, BRONZE_LIGHT, 1, 0.0, Vector3(1.0, 1.05, 0.5))
		sm.rigid(shb)
		# foot (skin) and sandal (leather)
		_foot(soft, an, s)
		sm.bind(func(p: Vector3) -> PackedFloat32Array:
			if p.y > an.y + 0.02:
				return _w2(shb, ft, smoothstep(an.y + 0.06, an.y + 0.02, p.y))
			return PackedFloat32Array([float(ft), 1.0]))
	# --- chest details (metal): the cuirass collar rim ---
	metal.push(Transform3D.IDENTITY)
	hloft(metal, [[1.538, 0.12, 0.088, 0.1, 0.015], [1.552, 0.112, 0.082, 0.094, 0.016], [1.556, 0.098, 0.074, 0.086, 0.016]], 20, BRONZE_LIGHT, 2.5)
	metal.pop()
	sm.rigid(CHEST)
	return sm.commit()


static func _skirt_w(p: Vector3) -> PackedFloat32Array:
	var a := fposmod(atan2(p.x, -p.z), TAU) / TAU * float(SKIRT_N)
	var i0 := int(floorf(a)) % SKIRT_N
	var i1 := (i0 + 1) % SKIRT_N
	var f := a - floorf(a)
	var down := smoothstep(1.04, 0.95, p.y)
	return PackedFloat32Array([float(PELVIS), 1.0 - down, float(SKIRT0 + i0), down * (1.0 - f), float(SKIRT0 + i1), down * f])


static func _pauldron(metal: MeshBuilder) -> void:
	# a rounded shell over the shoulder (local +Y up, outward +X after the parent's roll), with a rolled rim
	var prof := [Vector2(0.105, -0.035), Vector2(0.108, -0.01), Vector2(0.1, 0.02), Vector2(0.082, 0.048), Vector2(0.052, 0.068), Vector2(0.0, 0.078)]
	metal.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.12)), Vector3.ZERO))
	metal.lathe(prof, 16, BRONZE, 0.0, false, true)
	metal.ring(Vector3(0, -0.045, 0), 0.112, 0.098, 0.016, 16, BRONZE_LIGHT)
	# second lame below
	metal.lathe([Vector2(0.118, -0.07), Vector2(0.116, -0.045), Vector2(0.104, -0.03)], 16, BRONZE_DARK, 0.0)
	metal.pop()


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
	var fp := func(z: float, rx: float, ry: float, yc: float) -> Array:
		return [an + Vector3(0.0, yc, z), rx, ry]
	# foot body along -Z (rings in XY planes)
	var rings := [fp.call(0.07, 0.03, 0.03, g + 0.05), fp.call(0.055, 0.046, 0.05, g + 0.055), fp.call(0.02, 0.054, 0.058, g + 0.06),
		fp.call(-0.04, 0.058, 0.048, g + 0.052), fp.call(-0.1, 0.062, 0.036, g + 0.042), fp.call(-0.155, 0.063, 0.028, g + 0.036),
		fp.call(-0.195, 0.056, 0.022, g + 0.033), fp.call(-0.215, 0.04, 0.016, g + 0.032)]
	# loft with frames: tangent -Z, z_hint up -> x = t x z
	loft(soft, rings, 10, SKIN, Vector3.UP, true, true)
	# ankle column joining the shin
	loft(soft, [[an + Vector3(0, 0.03, 0), 0.046, 0.048], [an + Vector3(0, -0.01, 0.0), 0.05, 0.054], [an + Vector3(0, -0.045, 0.01), 0.05, 0.056]], 10, SKIN, FWD, false, false)
	# sandal sole and straps
	_sole(soft, an + Vector3(0, g, 0))
	for z in [-0.14, -0.06]:
		loft(soft, [[an + Vector3(0, g + 0.042, z - 0.008), 0.066, 0.034], [an + Vector3(0, g + 0.042, z + 0.008), 0.066, 0.034]], 10, LEATHER, Vector3.UP, false, false)
	loft(soft, [[an + Vector3(0, -0.012, 0.0), 0.054, 0.058], [an + Vector3(0, 0.004, 0.0), 0.053, 0.056]], 10, LEATHER, FWD, false, false)
	loft(soft, [[an + Vector3(0, 0.035, 0.0), 0.05, 0.052], [an + Vector3(0, 0.05, 0.0), 0.049, 0.051]], 10, LEATHER, FWD, false, false)
	soft.limb(an + Vector3(0, g + 0.045, -0.1), an + Vector3(0, -0.005, -0.04), 0.012, 0.012, 5, LEATHER)


# --- helmet ------------------------------------------------------------------------------------------------

## [soft, metal] meshes of the Corinthian helmet, skinned to HEAD (crest to CREST_B).
static func helmet_meshes() -> Array:
	if not _cache.has("helmet"):
		_cache["helmet"] = _build_helmet()
	return _cache["helmet"]


const HELM_PROF := [
	[0.176, 0.03, 0.032, 0.034, 0.012],
	[0.166, 0.074, 0.078, 0.082, 0.012],
	[0.146, 0.11, 0.12, 0.124, 0.012],
	[0.112, 0.138, 0.154, 0.156, 0.012],
	[0.068, 0.152, 0.174, 0.168, 0.01],
	[0.028, 0.156, 0.184, 0.172, 0.008],
	[-0.012, 0.154, 0.188, 0.174, 0.006],
	[-0.052, 0.148, 0.184, 0.178, 0.006],
	[-0.09, 0.136, 0.172, 0.188, 0.008],
	[-0.124, 0.118, 0.152, 0.2, 0.01],
	[-0.15, 0.098, 0.13, 0.21, 0.012],
	[-0.168, 0.086, 0.116, 0.216, 0.012],
]
const HELM_SQ := 2.2


## Sculpt of the Corinthian shell (offset for a point p of the plain profile surface, helmet-centre relative).
static func _helm_push(p: Vector3) -> Vector3:
	var o := Vector3.ZERO
	var ax := absf(p.x)
	if p.z < 0.0:
		# brow arches over the eyes, meeting at the nose guard
		var by := 0.03 - 0.016 * pow(minf(ax / 0.11, 1.0), 2.0)
		o.z -= bump(Vector2(0, p.y), Vector2(0, by), Vector2(1, 0.02)) * 0.014 * (1.0 - smoothstep(0.1, 0.15, ax))
		# nose guard: a long bar down between the eyes
		o.z -= bump(Vector2(p.x, p.y), Vector2(0, -0.035), Vector2(0.026, 0.085)) * 0.02
		# cheek guards: a soft ridge along the jaw
		o.x += signf(p.x) * bump(Vector2(0, p.y), Vector2(0, -0.11), Vector2(1, 0.05)) * 0.006
	# ear notch: the lower edge rises at the sides between the cheek guard and the neck guard
	var side := smoothstep(0.5, 0.86, ax / maxf(Vector2(p.x, p.z).length(), 1e-4))
	side *= smoothstep(-0.1, 0.05, p.z)
	if p.y < -0.052:
		o.y += (-0.052 - p.y) * 0.72 * side
		o.x -= signf(p.x) * 0.012 * side * smoothstep(-0.052, -0.168, p.y)
	return o


## Point of the helmet shell (helmet-centre relative) at angle a (0 = front, +x side at PI/2) and height y.
static func helm_pt(a: float, y: float) -> Vector3:
	var prof := HELM_PROF
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
	var cz := lerpf(e0[4], e1[4], f)
	var sa := sin(a)
	var ca := cos(a)
	var ex := 2.0 / HELM_SQ
	var p := Vector3(signf(sa) * pow(absf(sa), ex) * rx, y, -signf(ca) * pow(absf(ca), ex) * (rf if ca > 0.0 else rb) + cz)
	return p + _helm_push(p)


static func _build_helmet() -> Array:
	var sm := SkinMesh.new(41)
	var metal := sm.metal
	var c := HEAD_C
	metal.push(Transform3D(Basis.IDENTITY, c))
	var col := func(p: Vector3, k: int, _i: int) -> Color:
		if k >= 10:
			return BRONZE_LIGHT
		if k == 4 and p.z < 0.0:
			return BRONZE_LIGHT
		return BRONZE
	hloft(metal, HELM_PROF, 32, col, HELM_SQ, _helm_push, true, false)
	# rolled rim and the inner flange meeting the neck
	var last: Array = HELM_PROF[HELM_PROF.size() - 1]
	var ly: float = last[0]
	hloft(metal, [[ly, last[1], last[2], last[3], last[4]], [ly + 0.008, last[1] - 0.022, last[2] - 0.026, last[3] - 0.04, 0.006], [ly + 0.02, 0.07, 0.07, 0.085, 0.004]], 32, BRONZE_DARK, HELM_SQ, _helm_push)
	# eyes: dark almonds on the face plate with a bronze lip
	for sxv in [-1.0, 1.0]:
		var sx: float = sxv
		var ring: Array[Vector3] = []
		var n := 16
		for i in n:
			var t := TAU * float(i) / float(n)
			# almond in (angle, height): pointed corners, fuller top
			var u := cos(t)
			var v := sin(t)
			var ang := sx * (0.36 + u * 0.24)
			var hy := -0.012 + v * (0.024 if v > 0.0 else 0.017) * pow(1.0 - absf(u) * 0.55, 1.0) - u * sx * 0.0 + (absf(u) * 0.006)
			var pt := helm_pt(ang, hy)
			var nrm := Vector3(pt.x, 0.0, pt.z - 0.006).normalized()
			ring.append(pt + nrm * 0.0035)
		var cen := helm_pt(sx * 0.36, -0.01)
		var cn := Vector3(cen.x, 0.0, cen.z).normalized()
		cen += cn * 0.0035
		for i in n:
			var a2 := ring[i]
			var b2 := ring[(i + 1) % n]
			if sx > 0.0:
				metal.tri(cen, b2, a2, SHADOW)
			else:
				metal.tri(cen, a2, b2, SHADOW)
		# lip
		var pts: Array = []
		for i in n + 1:
			pts.append(ring[i % n])
		metal.tube(pts, 0.0055, 0.0055, 5, BRONZE_DARK, false)
	# crest holder ridge
	var ridge := []
	for i in 9:
		var ang := lerpf(-0.72, 1.78, float(i) / 8.0)
		ridge.append([Vector3(0, cos(ang), sin(ang)) * 0.18 + Vector3(0, 0.0, 0.012), 0.022, 0.016])
	loft(metal, ridge, 6, BRONZE_DARK, Vector3.RIGHT, true, true)
	metal.pop()
	sm.rigid(HEAD)
	# crest: a thick horsehair fan along the ridge
	var soft := sm.soft
	soft.push(Transform3D(Basis.IDENTITY, c + Vector3(0, 0, 0.012)))
	var n2 := 18
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	var hw := 0.042
	for i in n2 + 1:
		var k := float(i) / float(n2)
		var ang := lerpf(-0.66, 2.0, k)
		var dir := Vector3(0, cos(ang), sin(ang))
		var h := 0.035 + 0.215 * pow(sin(clampf(k * 1.1, 0.0, 1.0) * PI), 0.7) * (1.0 - 0.3 * k)
		var pin := dir * 0.192
		var pout := dir * (0.192 + h)
		var w0 := hw * (0.8 + 0.2 * sin(k * PI))
		var ox := Vector3(w0, 0, 0)
		if i > 0:
			var strand := CREST if i % 2 == 0 else CREST_DARK
			soft.quad(prev_in + ox, prev_out + ox, pout + ox, pin + ox, strand)
			soft.quad(prev_in - ox, pin - ox, pout - ox, prev_out - ox, strand)
			var up0 := prev_out.normalized() * 0.024
			var up1 := pout.normalized() * 0.024
			var tc := CREST_LIGHT if i % 2 == 0 else CREST
			soft.quad(prev_out + ox, prev_out + ox * 0.45 + up0, pout + ox * 0.45 + up1, pout + ox, tc)
			soft.quad(prev_out - ox, pout - ox, pout - ox * 0.45 + up1, prev_out - ox * 0.45 + up0, tc)
			soft.quad(prev_out + ox * 0.45 + up0, prev_out - ox * 0.45 + up0, pout - ox * 0.45 + up1, pout + ox * 0.45 + up1, tc)
		else:
			soft.quad(pin - ox, pin + ox, pout + ox, pout - ox, CREST_DARK)
		prev_in = pin
		prev_out = pout
	var oxe := Vector3(hw * 0.8, 0, 0)
	soft.quad(prev_in + oxe, prev_in - oxe, prev_out - oxe, prev_out + oxe, CREST_DARK)
	soft.pop()
	sm.rigid(CREST_B)
	return sm.commit()


# --- lion outfit -----------------------------------------------------------------------------------------------

## Skull cap of the lion hood, over the helmet (head-centre relative; same layout as HELM_PROF).
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
	mb.push(Transform3D(Basis.IDENTITY, HEAD_C))
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
		var knot := Vector3(0.0, 1.425, -0.236)
		for sx in [-1.0, 1.0]:
			var leg := [Vector3(0.118 * sx, 1.595, 0.07), Vector3(0.124 * sx, 1.578, -0.05), Vector3(0.108 * sx, 1.528, -0.13),
				Vector3(0.066 * sx, 1.47, -0.206), Vector3(0.022 * sx, 1.435, -0.236)]
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


## The red cape's collar: a rolled edge across the upper back, straps over the shoulders to bronze fibulae
## (rest rig space, rigid on the chest; hidden under the lion pelt). [soft, metal]
static func collar_meshes() -> Array:
	if not _cache.has("collar"):
		var soft := MeshBuilder.new(33)
		var metal := MeshBuilder.new(34)
		var roll := []
		for i in 9:
			var u := lerpf(-1.0, 1.0, float(i) / 8.0)
			var x := u * 0.205
			roll.append(Vector3(x, 1.478, 0.178 - 0.55 * x * x + 0.006))
		soft.tube(roll, 0.024, 0.024, 8, RED_DARK, true)
		for sxv in [-1.0, 1.0]:
			var sx: float = sxv
			var strap := [Vector3(0.2 * sx, 1.478, 0.14), Vector3(0.215 * sx, 1.535, 0.06), Vector3(0.2 * sx, 1.54, -0.04), Vector3(0.158 * sx, 1.49, -0.115)]
			soft.tube(strap, 0.018, 0.016, 6, RED, true)
			metal.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.35), Vector3(0.155 * sx, 1.47, -0.12)))
			metal.cyl(Vector3.ZERO, 0.02, 0.034, 0.03, 10, BRONZE_LIGHT)
			metal.cyl(Vector3(0, 0.02, 0), 0.008, 0.02, 0.012, 8, BRONZE)
			metal.pop()
		_cache["collar"] = [soft.commit(), metal.commit()]
	return _cache["collar"]


# --- hands -------------------------------------------------------------------------------------------------

## Fist in hand space (rest frame of the hand bone of side s; origin at the wrist): fingers wrap the grip axis
## (Z) through GRIP; back of the hand towards +X*s, thumb on the -Z side.
static func fist_mesh(s: float) -> ArrayMesh:
	var key := "fist_%d" % int(s)
	if not _cache.has(key):
		var mb := MeshBuilder.new(51)
		var w := mx(P_WRIST, s)
		mb.push(Transform3D(Basis.IDENTITY, w))
		# wrist into the bracer cuff
		loft(mb, [[Vector3(0, 0.03, 0), 0.042, 0.038], [Vector3(0, -0.02, 0), 0.044, 0.04]], 10, SKIN, FWD, false, false)
		mb.push(Transform3D(Basis.from_scale(Vector3.ONE * HAND_K), Vector3.ZERO))
		# palm + curled fingers: a rounded block around the grip
		mb.ico(Vector3(0.006 * s, -0.062, 0.0), 0.062, SKIN, 1, 0.0, Vector3(0.78, 0.92, 1.0))
		# knuckles ridge (the curled fingers), wrapping the grip on the palm side
		loft(mb, [[Vector3(-0.004 * s, -0.096, 0.055), 0.03, 0.034], [Vector3(-0.006 * s, -0.1, 0.0), 0.036, 0.038], [Vector3(-0.004 * s, -0.096, -0.052), 0.03, 0.034]], 10, SKIN, Vector3(s, 0, 0), true, true)
		# thumb over the index finger
		mb.limb(Vector3(-0.03 * s, -0.035, -0.04), Vector3(-0.034 * s, -0.08, -0.058), 0.021, 0.017, 6, SKIN_DARK)
		mb.ico(Vector3(-0.034 * s, -0.082, -0.058), 0.018, SKIN_DARK, 0)
		mb.pop()
		mb.pop()
		_cache[key] = mb.commit()
	return _cache[key]


## Open hand (left side, petting / reaching), in hand space at rest: palm facing -X*s... fingers down.
static func open_hand_mesh(s: float) -> ArrayMesh:
	var key := "open_%d" % int(s)
	if not _cache.has(key):
		var mb := MeshBuilder.new(53)
		var w := mx(P_WRIST, s)
		mb.push(Transform3D(Basis.IDENTITY, w))
		loft(mb, [[Vector3(0, 0.03, 0), 0.042, 0.038], [Vector3(0, -0.02, 0), 0.044, 0.04]], 10, SKIN, FWD, false, false)
		mb.push(Transform3D(Basis.from_scale(Vector3.ONE * HAND_K), Vector3.ZERO))
		mb.ico(Vector3(0.0, -0.06, 0.0), 0.058, SKIN, 1, 0.0, Vector3(0.5, 0.95, 1.0))
		for k in 4:
			var z := -0.036 + 0.024 * float(k)
			mb.limb(Vector3(0.0, -0.1, z), Vector3(-0.012 * s, -0.165 + absf(z) * 0.4, z * 1.1), 0.0135, 0.011, 5, SKIN)
		mb.limb(Vector3(-0.012 * s, -0.04, -0.045), Vector3(-0.03 * s, -0.09, -0.075), 0.017, 0.014, 5, SKIN_DARK)
		mb.pop()
		mb.pop()
		_cache[key] = mb.commit()
	return _cache[key]


# --- weapons -----------------------------------------------------------------------------------------------

## The xiphos in grip space: origin where the fist holds it, blade along -Z, edges along ±Y, flats facing ±X.
## [soft (grip), metal (hilt, blade)]
static func sword_meshes() -> Array:
	if not _cache.has("sword"):
		var soft := MeshBuilder.new(61)
		var metal := MeshBuilder.new(62)
		# grip (dark leather wrap)
		loft(soft, [[Vector3(0, 0, 0.068), 0.018, 0.016], [Vector3(0, 0, 0.0), 0.02, 0.018], [Vector3(0, 0, -0.058), 0.018, 0.016]], 8, LEATHER_DARK, Vector3.UP, false, false)
		# pommel and guard (bronze)
		metal.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.07)))
		metal.cyl(Vector3(0, -0.012, 0), 0.026, 0.03, 0.026, 12, BRONZE)
		metal.pop()
		metal.ico(Vector3(0, 0, 0.098), 0.022, BRONZE_LIGHT, 0, 0.0, Vector3(1.0, 1.0, 0.7))
		metal.box(Vector3(0, 0, -0.068), Vector3(0.034, 0.15, 0.022), BRONZE)
		metal.box(Vector3(0, 0, -0.074), Vector3(0.026, 0.11, 0.02), BRONZE_LIGHT)
		# leaf blade: diamond section, widest two thirds of the way out
		var zs := [-0.08, -0.13, -0.22, -0.33, -0.43, -0.5, -0.56, -0.6, -0.635]
		var ws := [0.024, 0.021, 0.022, 0.03, 0.035, 0.032, 0.024, 0.013, 0.0]
		for k in zs.size() - 1:
			var z0: float = zs[k]
			var z1: float = zs[k + 1]
			var w0: float = ws[k]
			var w1: float = ws[k + 1]
			var t0 := 0.0075 if k < zs.size() - 2 else 0.006
			var t1 := 0.0075 if k + 1 < zs.size() - 1 else 0.0
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
		metal.box(Vector3(0, 0, -0.084), Vector3(0.018, 0.05, 0.012), STEEL_DARK)
		_cache["sword"] = [soft.commit(), metal.commit()]
	return _cache["sword"]


## The aspis in rest rig space, mounted on the left forearm (faces -X at rest). [soft, metal]
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
		# painted face: cream field, red band, black club emblem
		var face_col := func(p: Vector3, _k: int, _i: int) -> Color:
			var r := Vector2(p.x, p.z).length()
			if r > R * 0.82:
				return RED
			if r > R * 0.76:
				return INK
			return CREAM
		metal.push(xf)
		soft.push(xf)
		var face := [Vector2(R * 0.93, 0.012), Vector2(R * 0.8, 0.03), Vector2(R * 0.6, 0.052), Vector2(R * 0.38, 0.066), Vector2(R * 0.18, 0.073), Vector2(0.0, 0.075)]
		soft.lathe(face, 28, face_col, 0.0, false, true)
		# bronze rim (rolled) and a bronze inner lip
		metal.lathe([Vector2(R * 0.9, -0.03), Vector2(R * 0.97, -0.034), Vector2(R * 1.03, -0.02), Vector2(R * 1.04, 0.0), Vector2(R * 0.99, 0.018), Vector2(R * 0.92, 0.014)], 28, BRONZE, 0.0)
		# back of the bowl (wood, darker) and its rim
		soft.lathe([Vector2(0.0, 0.05), Vector2(R * 0.3, 0.043), Vector2(R * 0.6, 0.025), Vector2(R * 0.8, 0.004), Vector2(R * 0.9, -0.028)], 28, WOOD, 0.0, true, false)
		# porpax (arm band, bronze) and antilabe (grip cord)
		metal.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.04, -0.06, 0.0)))
		metal.ring(Vector3(0, -0.03, 0), 0.075, 0.064, 0.06, 12, BRONZE_DARK)
		metal.pop()
		soft.limb(Vector3(0.2, 0.03, -0.05), Vector3(0.2, -0.05, -0.05), 0.012, 0.012, 5, LEATHER)
		soft.limb(Vector3(0.2, 0.03, 0.05), Vector3(0.2, -0.05, 0.05), 0.012, 0.012, 5, LEATHER)
		soft.limb(Vector3(0.2, -0.05, -0.06), Vector3(0.2, -0.05, 0.06), 0.012, 0.012, 5, LEATHER)
		# emblem: a black club (Heracles' own), laid on the face along local x
		var club := []
		for i in 9:
			var u := lerpf(-0.21, 0.2, float(i) / 8.0)
			var wd := lerpf(0.022, 0.06, float(i) / 8.0) + (0.012 if i % 3 == 1 else 0.0)
			club.append([u, wd])
		for i in club.size() - 1:
			var u0: float = club[i][0]
			var u1: float = club[i + 1][0]
			var w0: float = club[i][1]
			var w1: float = club[i + 1][1]
			var rot := Basis(Vector3.UP, 0.6)
			var a := rot * Vector3(u0, 0, -w0)
			var b := rot * Vector3(u1, 0, -w1)
			var cc := rot * Vector3(u1, 0, w1)
			var d := rot * Vector3(u0, 0, w0)
			for p in [a, b, cc, d]:
				pass
			var lift := func(v: Vector3) -> Vector3:
				var r := Vector2(v.x, v.z).length() / R
				return Vector3(v.x, 0.075 - 0.07 * r * r + 0.004, v.z)
			soft.quad(lift.call(a), lift.call(d), lift.call(cc), lift.call(b), INK)
		var knob := Basis(Vector3.UP, 0.6) * Vector3(0.215, 0, 0)
		soft.ico(Vector3(knob.x, 0.075 - 0.07 * pow(knob.length() / R, 2.0) + 0.002, knob.z), 0.065, INK, 0, 0.0, Vector3(1.0, 0.08, 1.0))
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
	var hel := helmet_meshes()
	_crest_mi = _skinned_mi(skel, hel[0], skin, _mat_soft, "Crest")
	_helm_mi = _skinned_mi(skel, hel[1], skin, _mat_helm, "Helmet")
	_helmet_mi.append(_crest_mi)
	_helmet_mi.append(_helm_mi)
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
	var col := collar_meshes()
	_collar_mi.append(_rigid_mi(_piv["chest_s"], col[0], _mat_soft, "CapeCollar"))
	_collar_mi.append(_rigid_mi(_piv["chest_s"], col[1], _mat_metal, "Fibulae"))


## Where the spear sits on the back (rest rig space): head up over the left shoulder, butt at the right hip.
## Under the lion pelt it lies lower and flatter, clear of the mane.
static func spear_back_xf(lion: bool = false) -> Transform3D:
	var tip := Vector3(-0.29, 1.99, 0.215) if not lion else Vector3(-0.45, 1.79, 0.24)
	var butt := Vector3(0.24, 0.85, 0.3) if not lion else Vector3(0.25, 0.89, 0.3)
	var d := (tip - butt).normalized()
	var z := -d
	var x := perp(Vector3.BACK, z).normalized()
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
	var upright := v3(c, C_ROT).length_squared() < 0.01
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
		var pole := v3(c, C_FRP if side == 0 else C_FLP)
		var r := ik2(H, A, pole, LEN_TH, LEN_SH)
		var K: Vector3 = r[0]
		var A2: Vector3 = r[1]
		var y1 := (K - H).normalized()
		var z1 := perp(pole, y1)
		if z1.length_squared() < 1e-8:
			z1 = perp(FWD, y1)
		z1 = z1.normalized()
		var x1 := y1.cross(z1)
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
			hand_cs = cbi * hand_basis(_spc(cb, v3(c, C_HRB), ks), _spc(cb, v3(c, C_HRK), ks), 1.0)
			var grip_rig := _keep_out(_spp(chest, v3(c, C_HR), ks), 0.075)
			wrist_cs = chest.affine_inverse() * grip_rig - hand_cs * GRIP
			pole_cs = cbi * _spc(cb, v3(c, C_HRP), ks)
		else:
			wrist_cs = chest.affine_inverse() * _keep_out(_spp(chest, v3(c, C_HL), ks), 0.085)
			pole_cs = cbi * _spc(cb, v3(c, C_HLP), ks)
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
		var pole := cb * pole_cs
		var r := ik2(S, W, pole, LEN_UA, LEN_FA)
		var E: Vector3 = r[0]
		# an elbow inside the body swings the other way round
		var e_safe := _keep_out(E, 0.06)
		if e_safe.distance_squared_to(E) > 1e-6:
			pole = (pole.normalized() + (e_safe - E).normalized() * 2.0).normalized()
			r = ik2(S, W, pole, LEN_UA, LEN_FA)
			E = r[0]
		var W2: Vector3 = r[1]
		var y1 := (E - S).normalized()
		var z1 := -perp(pole, y1)
		if z1.length_squared() < 1e-8:
			z1 = perp(cb * FWD, y1)
		z1 = z1.normalized()
		var x1 := y1.cross(z1)
		var bua := Basis(x1, y1, z1) * _f0_ua[side].transposed()
		_bx[UARM_R + o] = Transform3D(bua, S)
		var y1f := (W2 - E).normalized()
		var f1f := Basis(x1, y1f, x1.cross(y1f))
		var twist := 0.0
		var hand_b: Basis
		if side == 0:
			hand_b = cb * hand_cs
			var hx := perp(hand_b.x, y1f)
			if hx.length() > 0.2:
				twist = x1.signed_angle_to(hx.normalized(), y1f) * 0.5
		else:
			var n := perp(_spc(cb, v3(c, C_HLF), ks), y1f)
			if n.length() > 0.05:
				twist = (-x1).signed_angle_to(n.normalized(), y1f)
		var bfa := Basis(y1f, twist) * f1f * _f0_fa[side].transposed()
		_bx[FARM_R + o] = Transform3D(bfa, E)
		if side == 1:
			hand_b = bfa * eul(v3(c, C_HLW))
			var hx := clampf(c[C_HLX], 0.0, 1.0)
			if hx > 0.001:
				var hb2 := hand_basis(_spc(cb, v3(c, C_HLB), ks), _spc(cb, v3(c, C_HLK), ks), -1.0)
				hand_b = Basis(hand_b.get_rotation_quaternion().slerp(hb2.get_rotation_quaternion(), hx))
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
	# the crest folds down into the hood as it comes over, the helmet sinks into its shadow
	var crest_k := 1.0 if not _show_lion else 1.0 - smoothstep(0.1, 0.5, _show_hood)
	_crest_mi.visible = crest_k > 0.02
	if crest_k < 0.999:
		var cb := _bx[CREST_B]
		_bx[CREST_B] = Transform3D(cb.basis * Basis.from_scale(Vector3.ONE * maxf(crest_k, 0.02)), cb.origin)
	var shade := smoothstep(0.55, 1.0, _show_hood) if _show_lion else 0.0
	if absf(shade - _helm_shade) > 0.01:
		_helm_shade = shade
		var k := lerpf(1.0, 0.22, shade)
		_mat_helm.set_shader_parameter("tint", Vector3(k, k * 0.94, k * 1.04))
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
	_blade[1] = gx * Vector3(0.0, 0.0, -0.64)
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
var _phase := 0.0
var _prev_s := PackedFloat32Array([0.0, 0.5])
var _guard_k := 0.0
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
## Channels the legs and hips take from the locomotion under an upper-body action.
const LOWER_CH := [C_FR, C_FRR, C_FRP, C_FL, C_FLR, C_FLP, C_PEL]


## Upper-body layering: legs and hips from the locomotion pose, the rest from the action.
func _layer_lower(dst: PackedFloat32Array, loco: PackedFloat32Array) -> void:
	for o in LOWER_CH:
		dst[o] = loco[o]
		dst[o + 1] = loco[o + 1]
		dst[o + 2] = loco[o + 2]
	# the hips turn half with the action, half with the gait; no whole-body rotation
	for j in 3:
		dst[C_PELR + j] = lerpf(loco[C_PELR + j], dst[C_PELR + j], 0.5)
		dst[C_ROT + j] = loco[C_ROT + j]
		dst[C_PIV + j] = loco[C_PIV + j]


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
	motion_state = s
	if action == "" or not is_busy():
		_start_blend(0.18 if s != &"zip" else 0.1)


func set_vertical_speed(vy: float) -> void:
	vspeed = vy


func set_guard(on: bool) -> void:
	guard = on


## Definition actually played for action `a` (the lion outfit draws the spear from its own place on the back).
func _variant(a: String) -> String:
	if (a == "throw" or a == "catch") and _show_lion:
		return a + "_lion"
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
	_fired.clear()
	if (a == "don_skin") != _don_hide:
		_don_hide = a == "don_skin"
		_update_weapons()
	_hold = bool(def.get("hold", false))
	action_speed = 1.0
	action_hold = -1.0
	_upper = 0.0
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
	_blend_len = maxf(dur, 0.001)


func _process(delta: float) -> void:
	advance(delta)


## One animation step (the rig calls it from _process; tools call it directly with a fixed step).
func advance(delta: float) -> void:
	delta = clampf(delta, 0.0, 0.1)
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
	var loco := _loco_pose(delta)
	if action != "":
		if _akey == "" or not _akey.begins_with(action):
			_akey = _variant(action)
		_src = sample_action(_akey, action_t)
		if _upper > 0.0:
			_layer_lower(_src, loco)
		_emit_events(act_def(_akey))
	else:
		_src = loco
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / _blend_len)
		_pose = mix_pose(_from, _src, smooth(_blend_t))
	else:
		_pose = _src
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
	_update_outfit_state()
	_secondary(delta)
	_apply_outfit()
	_apply_props()
	_apply_bones()


## World velocity / acceleration / yaw rate of the rig (drives leans and secondary motion).
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
	var k := 1.0 - exp(-dt * 12.0)
	var nv := _vel.lerp(v, k)
	_acc = _acc.lerp((nv - _vel) / dt, 1.0 - exp(-dt * 8.0))
	_vel = nv
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _prev_yaw, -PI, PI) / dt, 1.0 - exp(-dt * 6.0))
	_prev_pos = p
	_prev_yaw = yaw


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


## Compiles one raw action definition (see _action_defs) into sampled poses and Hermite tangents.
static func compile_action(d: Dictionary) -> Dictionary:
	if true:
		var keys: Array = d["keys"]
		var times := PackedFloat32Array()
		var poses: Array[PackedFloat32Array] = []
		var ease := PackedByteArray()
		var prev := default_pose()
		for k in keys:
			var tk: float = k[0]
			var ch: Dictionary = k[1]
			var pose := prev.duplicate()
			for key in ch:
				if key == "ease":
					continue
				set_ch(pose, key, ch[key])
			times.append(tk)
			poses.append(pose)
			ease.append(1 if ch.get("ease", false) else 0)
			prev = pose
		# Hermite tangents (non-uniform Catmull-Rom; zero at the ends and at eased keys)
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
		return {"len": float(d["len"]), "loop": bool(d.get("loop", false)), "hold": bool(d.get("hold", false)),
			"in": float(d.get("in", 0.08)), "out": float(d.get("out", 0.2)), "ev": d.get("ev", {}),
			"times": times, "poses": poses, "tans": tans}
	return {}


static func sample_action(a: String, at: float) -> PackedFloat32Array:
	var d := act_def(a)
	var times: PackedFloat32Array = d["times"]
	var poses: Array[PackedFloat32Array] = d["poses"]
	var tans: Array[PackedFloat32Array] = d["tans"]
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
	_guard_k = move_toward(_guard_k, 1.0 if guard else 0.0, dt * 9.0)
	_vy = lerpf(_vy, vspeed, 1.0 - exp(-dt * 10.0))
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


## One foot of the gait cycle at cycle position s: [z offset (back +), ankle height, pitch].
static func foot_cycle(s: float, duty: float, half: float, lift: float, run: float) -> Vector3:
	if s < duty:
		var u := s / duty
		var pitch := 0.0
		if u < 0.2:
			pitch = 0.24 * (1.0 - u / 0.2) * (1.0 - run * 0.8)
		if u > 0.62:
			pitch = -0.8 * pow((u - 0.62) / 0.38, 2.0)
		var y := 0.093 + (0.14 * sin(-pitch) if pitch < 0.0 else 0.0)
		return Vector3(lerpf(-half, half, u), y, pitch)
	var w := (s - duty) / (1.0 - duty)
	var z := lerpf(half, -half, smooth(w))
	var y2 := 0.093 + 0.11 * pow(1.0 - w, 3.0) * 0.6 + lift * sin(PI * pow(w, lerpf(0.9, 0.65, run)))
	var p2 := lerpf(-0.8, lerpf(0.24, 0.05, run), smooth(w))
	return Vector3(z, y2, p2)


func _ground_pose(c: PackedFloat32Array, dt: float) -> void:
	var v := _spd
	var move := smoothstep(0.05, 0.6, v)
	var run := smoothstep(2.3, 4.6, v)
	var sprint := smoothstep(6.2, 8.4, v)
	# direction of travel in rig space (CORE: strafing round a locked target, back-pedalling with the chain)
	var lv := (global_transform.basis.inverse() * _vel) if is_inside_tree() else Vector3(0.0, 0.0, -v)
	var lv2 := Vector2(lv.x, lv.z)
	if lv2.length() > 0.35:
		_mdir = _mdir.lerp(lv2.normalized(), 1.0 - exp(-dt * 10.0)).normalized()
	elif move < 0.2:
		_mdir = _mdir.lerp(Vector2(0.0, -1.0), 1.0 - exp(-dt * 4.0)).normalized()
	var side_k := absf(_mdir.x)
	var back_k := clampf(_mdir.y, 0.0, 1.0)
	var stride := lerpf(0.55 + 0.62 * v, 1.25 + 0.27 * v, run) * lerpf(1.0, 0.62, maxf(side_k, back_k * 0.6))
	_phase = fposmod(_phase + v / maxf(stride, 0.45) * dt, 1.0)
	var duty := lerpf(0.6, 0.38, run)
	var half := duty * stride * 0.5
	var lift := lerpf(0.08, 0.2, run) + 0.08 * sprint
	var ph := _phase
	var br := sin(t * lerpf(1.7, 3.4, tired))
	var idle := 1.0 - move
	# --- legs ---
	for side in 2:
		var s := fposmod(ph + (0.0 if side == 0 else 0.5), 1.0)
		var f := foot_cycle(s, duty, half, lift, run)
		var sx := 1.0 if side == 0 else -1.0
		var x := sx * lerpf(0.125, 0.09, run) * lerpf(1.0, 1.25, side_k)
		# the stride runs along the travel direction (f.x: behind +); a strafing foot never crosses the other
		var lat := -_mdir.x * f.x
		var cx := x + lat
		cx = maxf(cx, 0.07) if side == 0 else minf(cx, -0.07)
		var cyc := Vector3(cx, f.y, -_mdir.y * f.x)
		var o := C_FR if side == 0 else C_FL
		var idle_foot := v3(c, o)
		_setv(c, o, idle_foot.lerp(cyc, move))
		var ro := C_FRR if side == 0 else C_FLR
		var yaw0 := c[ro + 1]
		_setv(c, ro, Vector3(f.z * move * lerpf(1.0, 0.35, maxf(side_k, back_k)), lerpf(yaw0, -sx * 0.07, move), 0.0))
		# footfalls
		if move > 0.3 and s < _prev_s[side] and _spd > 0.2:
			event.emit("step")
		_prev_s[side] = s
	# --- pelvis ---
	var mid := ph - duty * 0.5
	var bob := cos(TAU * 2.0 * mid)
	var pel := v3(c, C_PEL)
	pel.y = lerpf(pel.y, lerpf(-0.05, -0.085, run) - 0.035 * sprint, move) + lerpf(0.018, -0.036, run) * bob * move
	pel.x += 0.02 * cos(TAU * mid) * move * (1.0 - run) + 0.012 * sin(t * 0.45) * idle
	pel.z += -0.02 * run - 0.04 * sprint
	_setv(c, C_PEL, pel)
	var yaw := lerpf(0.09, 0.15, run) * cos(TAU * ph) * move
	var turn := clampf(_yaw_rate * v * 0.035, -0.28, 0.28)
	_setv(c, C_PELR, Vector3(c[C_PELR] + 0.04 * run, yaw, 0.03 * sin(TAU * ph) * move * (1.0 - run * 0.5) + 0.012 * sin(t * 0.45) * idle + turn * 0.4))
	# --- spine: lean with speed and acceleration, counter-rotate the shoulders ---
	var accel := clampf(-(_acc.dot(-global_transform.basis.z if is_inside_tree() else FWD)) * 0.012, -0.12, 0.12) if move > 0.1 else 0.0
	_setv(c, C_SPN, Vector3(-0.03 * move - 0.07 * run - 0.1 * sprint + accel, -yaw * 0.5, turn * 0.5))
	var chs := v3(c, C_CHS)
	chs.x += -0.02 * move - 0.05 * run - 0.1 * sprint + lerpf(0.018, 0.05, tired) * br * idle - 0.12 * tired * idle
	chs.y += -yaw * 1.1
	_setv(c, C_CHS, chs)
	if tired > 0.0:
		# winded: the head drops, the shoulders heave
		c[C_NEK] -= 0.1 * tired * idle
		c[C_SPN] -= 0.05 * tired * idle
	_setv(c, C_NEK, Vector3(c[C_NEK] + 0.05 * run + 0.12 * sprint, yaw * 0.6, -turn * 0.4))
	_setv(c, C_HED, Vector3(0.008 * br * idle, 0.08 * sin(t * 0.31) * idle, 0.0))
	# --- arms ---
	var fw_r := cos(TAU * (ph - 0.5))
	var fw_l := cos(TAU * ph)
	var amp_r := (lerpf(0.09, 0.17, run) + 0.06 * sprint) * move
	var amp_l := (lerpf(0.07, 0.14, run) + 0.08 * sprint) * move
	var hr := v3(c, C_HR).lerp(Vector3(0.33, -0.31, -0.12), run)
	hr += Vector3(0.0, 0.06 * maxf(fw_r, 0.0) * run - 0.012 * br * idle, -amp_r * fw_r)
	_setv(c, C_HR, hr)
	_lerpv(c, C_HRB, Vector3(0.1, -0.25 - 0.35 * sprint, -1.0), run)
	_addv(c, C_HRB, Vector3(0.0, -0.25 * fw_r * move, 0.0))
	var hl := v3(c, C_HL).lerp(Vector3(-0.33, -0.27, -0.1), run)
	hl += Vector3(0.0, 0.05 * maxf(fw_l, 0.0) * run - 0.01 * br * idle, -amp_l * fw_l)
	_setv(c, C_HL, hl)
	# --- guard: shield up in front, sword ready at the hip ---
	if _guard_k > 0.0:
		var g := smooth(_guard_k)
		# the shield forward-left of the chest (a hoplite's stance): its rim shows past his left side even from
		# behind him, so a raised guard reads from the gameplay camera
		_lerpv(c, C_HL, Vector3(-0.14, 0.02, -0.46), g)
		_lerpv(c, C_HLF, Vector3(-0.06, 0.06, -1.0), g)
		_lerpv(c, C_HLP, Vector3(-1.0, -0.7, 0.3), g)
		_lerpv(c, C_HR, Vector3(0.3, -0.2, -0.24), g)
		_lerpv(c, C_HRB, Vector3(0.05, 0.22, -1.0), g)
		_lerpv(c, C_HRK, Vector3(1.0, 0.3, 0.2), g)
		_lerpv(c, C_HRP, Vector3(0.6, -0.3, 1.0), g)
		c[C_CHS + 1] += 0.14 * g
		c[C_SPN] -= 0.05 * g
		c[C_PEL + 1] -= 0.04 * g * idle
		c[C_NEK + 1] -= 0.1 * g
		var fl := v3(c, C_FL)
		_setv(c, C_FL, fl + Vector3(-0.02, 0.0, -0.06) * g * idle)
		# a blow on the shield: the shield arm is driven back towards the chest, the chest leans back with it
		if absf(_jolt) > 0.001:
			var j := clampf(_jolt, -0.4, 1.0) * g
			_addv(c, C_HL, Vector3(-0.03, 0.03, 0.12) * j)
			c[C_CHS] += 0.12 * j
			c[C_SPN] += 0.06 * j
			c[C_PEL + 2] += 0.05 * j


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
	var fl := sin(t * 7.0) * 0.02
	_setv(c, C_PEL, Vector3(0.0, lerpf(0.02, -0.02, k), 0.0))
	_setv(c, C_PELR, Vector3(lerpf(0.12, -0.05, k), 0.0, 0.0))
	_setv(c, C_SPN, Vector3(lerpf(-0.12, 0.04, k), 0.0, 0.0))
	_setv(c, C_CHS, Vector3(lerpf(0.0, 0.08, k), 0.05, 0.0))
	_setv(c, C_NEK, Vector3(lerpf(0.05, -0.12, k), 0.0, 0.0))
	_setv(c, C_FR, Vector3(0.13, lerpf(0.42, 0.14, k) + fl, lerpf(-0.16, -0.06, k)))
	_setv(c, C_FRR, Vector3(lerpf(-0.35, 0.15, k), -0.1, 0.0))
	_setv(c, C_FL, Vector3(-0.14, lerpf(0.3, 0.2, k) - fl, lerpf(0.14, 0.12, k)))
	_setv(c, C_FLR, Vector3(lerpf(-0.7, -0.2, k), 0.1, 0.0))
	_setv(c, C_HR, Vector3(lerpf(0.36, 0.52, k), lerpf(-0.05, 0.02, k), lerpf(-0.2, -0.02, k)))
	_setv(c, C_HRB, Vector3(lerpf(0.1, 0.5, k), lerpf(0.25, 0.4, k), -1.0))
	_setv(c, C_HRP, Vector3(0.6, -0.5, 0.8))
	_setv(c, C_HL, Vector3(lerpf(-0.36, -0.5, k), lerpf(-0.12, 0.0, k), lerpf(-0.18, 0.0, k)))
	_setv(c, C_HLF, Vector3(-1.0, -0.2, -0.3))
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


func _crest_spring(dt: float, gx: Transform3D) -> void:
	if dt > 0.0:
		var wp := gx * _bx[HEAD].origin
		var hv := (wp - _prev_head_p) / dt + velocity_hint
		var ha := (hv - _prev_head_v) / dt
		if _prev_head_p == Vector3.ZERO:
			ha = Vector3.ZERO
		_prev_head_p = wp
		_prev_head_v = hv
		var la := (gx.basis * _bx[HEAD].basis).inverse() * ha
		var force := Vector2(la.z, -la.x) * 0.012
		_crest_v += (force - _crest * 90.0 - _crest_v * 9.0) * dt
		_crest += _crest_v * dt
		_crest = _crest.clamp(Vector2(-0.22, -0.18), Vector2(0.22, 0.18))
	var cb := _bx[CREST_B]
	_bx[CREST_B] = Transform3D(cb.basis * Basis(Vector3.RIGHT, _crest.x) * Basis(Vector3.BACK, _crest.y), cb.origin)


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

const CAPE_NC := 9
const CAPE_NR := 9
var cape_skel: Skeleton3D
var _cape_pos := PackedVector3Array()
var _cape_prev := PackedVector3Array()
var _cape_rest := PackedVector3Array()
var _cape_ca := PackedInt32Array()
var _cape_cb := PackedInt32Array()
var _cape_cl := PackedFloat32Array()
var _cape_ck := PackedFloat32Array()
var _cape_meshes: Array[MeshInstance3D] = []
var _cape_outfit := &""
## Tools: names of cloth constraints to skip (debugging): caps, chest, spine, cone, shield, spear, drape, air.
var dbg_off: PackedStringArray = []


## Rest grid of the cape (or the lion pelt) in rest rig space: row 0 along the upper back, hanging down.
static func cape_rest(lion: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var length := 1.0 if lion else 0.95
	for j in CAPE_NR:
		var v := float(j) / float(CAPE_NR - 1)
		var y := 1.475 - v * length
		var hw := lerpf(0.2, 0.31, pow(v, 0.8)) if not lion else lerpf(0.24, 0.36, pow(v, 0.7))
		for i in CAPE_NC:
			var u := float(i) / float(CAPE_NC - 1) * 2.0 - 1.0
			var x := u * hw
			# over the shoulder blades, then out over the skirt, then straight down
			var z := 0.175 + 0.075 * smoothstep(0.0, 0.55, v) - 0.55 * x * x * (1.0 - v * 0.6)
			out.append(Vector3(x, y, z))
	return out


func _cape_setup(lion: bool) -> void:
	_cape_rest = cape_rest(lion)
	_cape_ca.clear()
	_cape_cb.clear()
	_cape_cl.clear()
	_cape_ck.clear()
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
	_cape_pos.resize(0)


func _cape_con(a: int, b: int, k: float) -> void:
	_cape_ca.append(a)
	_cape_cb.append(b)
	_cape_cl.append(_cape_rest[a].distance_to(_cape_rest[b]))
	_cape_ck.append(k)


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
	var need := 13 + SKIRT_N
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
		_cap_add(gx * _bx[THIGH_R + k].origin, gx * _bx[SHIN_R + k].origin, 0.135)
		_cap_add(gx * _bx[SHIN_R + k].origin, gx * _bx[FOOT_R + k].origin, 0.115)
	# arms
	for o in 2:
		var k := o * 4
		_cap_add(gx * _bx[UARM_R + k].origin, gx * _bx[FARM_R + k].origin, 0.11)
		_cap_add(gx * _bx[FARM_R + k].origin, gx * _bx[HAND_R + k].origin, 0.105)
	# hips and the skirt: a core plus a cage of hinge -> hem capsules
	_cap_add(gx * _carry(PELVIS, Vector3(-0.08, 0.95, 0.0)), gx * _carry(PELVIS, Vector3(0.08, 0.95, 0.0)), 0.215)
	_cap_add(gx * _carry(PELVIS, Vector3(-0.08, 0.8, 0.0)), gx * _carry(PELVIS, Vector3(0.08, 0.8, 0.0)), 0.2)
	for i in SKIRT_N:
		_cap_add(gx * _carry(PELVIS, _rest[SKIRT0 + i]), _sk_tip[i], 0.06)
	# helmet (and its flared neck guard) or the lion hood
	var hc := gx * _carry(HEAD, HEAD_C + Vector3(0, 0.0, 0.02))
	_cap_add(hc, hc, 0.23 if not _show_lion else 0.27)
	var hn := gx * _carry(HEAD, HEAD_C + Vector3(0, -0.12, 0.07))
	_cap_add(hn, hn, 0.17 if not _show_lion else 0.21)
	# the blade
	if not _weapons_hidden():
		var hb := _bx[HAND_R]
		var sw := gx * Transform3D(hb.basis * Basis(Vector3.RIGHT, _pose[C_GRIP]), hb.origin + hb.basis * GRIP)
		_cap_add(sw * Vector3(0, 0, -0.1), sw * Vector3(0, 0, -0.62), 0.04)


func _cape_step(dt: float, gx: Transform3D) -> void:
	var lion := _show_lion
	var want := &"lion" if lion else &"helmet"
	if _cape_outfit != want:
		_cape_outfit = want
		_cape_setup(lion)
	var n := _cape_rest.size()
	var chest := gx * _bx[CHEST]
	var chest_rest := _rest[CHEST]
	if _cape_pos.size() != n:
		_cape_pos.resize(n)
		_cape_prev.resize(n)
		for k in n:
			_cape_pos[k] = chest * (_cape_rest[k] - chest_rest)
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
	# the shield's disc (a slab in the shield frame)
	var sh_xf := gx * shield_xf(_bx[FARM_L], _rest[FARM_L])
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
	var shape_k := 3.0
	if action != "" and _akey == "heavy":
		shape_k = 70.0 if action_t > 0.3 and action_t < 0.8 else 25.0
	elif action != "" and _akey == "dodge":
		shape_k = 25.0
	var swimming := motion_state == &"swim"
	var water_y := gx.origin.y + swim_waterline - 0.02
	for st in steps:
		for k in n:
			var j := k / CAPE_NC
			if j == 0:
				_cape_prev[k] = _cape_pos[k]
				_cape_pos[k] = chest * (_cape_rest[k] - chest_rest)
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
		for it in 5:
			for c in _cape_ca.size():
				var a := _cape_ca[c]
				var b := _cape_cb[c]
				var pa := _cape_pos[a]
				var pb := _cape_pos[b]
				var dv := pb - pa
				var dl := dv.length()
				if dl < 1e-6:
					continue
				var diff := (dl - _cape_cl[c]) / dl * _cape_ck[c]
				var fa := 0.0 if a < CAPE_NC else 0.5
				var fb := 0.0 if b < CAPE_NC else 0.5
				if fa + fb <= 0.0:
					continue
				var s := diff / (fa + fb)
				_cape_pos[a] = pa + dv * (s * fa)
				_cape_pos[b] = pb - dv * (s * fb)
			# the collisions: after the 3rd and the last pass of the constraints (cheaper than after every pass,
			# and the cloth always ends the step outside the body)
			if it != 2 and it != 4:
				continue
			for k in range(CAPE_NC, n):
				var p := _cape_pos[k]
				if use_caps:
					for ci in ncap:
						if p.distance_squared_to(_cap_c[ci]) < _cap_rr[ci]:
							p = _push_capsule(p, _cap_a[ci], _cap_b[ci], _cap_r[ci])
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
				# out of the shield's slab
				var qs := sh_inv * p
				if Vector2(qs.x, qs.z).length() < SHIELD_R * 1.04 and qs.y > -0.06 and qs.y < 0.1 and use_shield:
					qs.y = -0.06 if qs.y < 0.02 else 0.1
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
		if v > 0.94:
			return CREAM
		if v > 0.9:
			return RED_DARK
		return RED
	var col_back := func(u: float, v: float) -> Color:
		if lion:
			return LEATHER_LIGHT if v > 0.12 else MANE_DARK
		return RED_DARK.darkened(0.15) if v < 0.9 else CREAM.darkened(0.25)
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
	var rim_col := RED_DARK if not lion else MANE_DARK
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
func preview_pose(act: String, t_norm: float, spd: float, state: StringName, outfit_name: StringName, guard_on: bool, vy: float, phase: float) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	set_outfit(outfit_name)
	set_guard(guard_on)
	set_motion_state(state)
	set_vertical_speed(vy)
	var dt := 1.0 / 60.0
	var fwd := -(global_transform.basis.z if is_inside_tree() else Vector3.BACK)
	velocity_hint = fwd * spd if state != &"swim" else fwd * spd
	set_locomotion(spd, 9.0)
	_spd = spd
	var pre := 1.6
	if act == "":
		var v := spd
		var run := smoothstep(2.3, 4.6, v)
		var stride := lerpf(0.55 + 0.62 * v, 1.25 + 0.27 * v, run)
		_phase = fposmod(phase - v / maxf(stride, 0.45) * pre, 1.0)
		_swim_phase = _phase
	var steps := int(pre / dt)
	for i in steps:
		advance(dt)
	if act != "":
		play(act)
		_blend_t = 1.0
		var target := t_norm * action_len * 0.999
		while action_t + dt < target:
			advance(dt)
		advance(maxf(target - action_t, 0.0))


## &"helmet" or &"lion". Shown from the next frame; play("don_skin") makes the change itself, part-way through.
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
	_mat_helm.set_shader_parameter("metal", k)


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


## tools/clip_check.gd: part-local ellipsoids [centre, radii] inscribed in the real armour (the checker shrinks
## them by its tolerance): cuirass, helmet, hips under the skirt, thighs. Body pivots live in rest rig space.
func clip_volume(part: String) -> Array:
	match part:
		"torso":
			return [Vector3(0.0, 1.27, 0.0), Vector3(0.19, 0.25, 0.15)]
		"head":
			return [Vector3(0.0, -0.01, 0.0), Vector3(0.165, 0.18, 0.185)]
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
	# swing planes (chess space, through the right shoulder)
	var n1 := Vector3(-0.909, 0.263, 0.324)
	var u1 := Vector3(0.351, 0.902, 0.251)
	var n2 := Vector3(0.465, -0.852, 0.239)
	var u2 := Vector3(-0.73, -0.52, -0.43)
	var n3 := Vector3(-0.93, 0.35, 0.1)
	var u3 := Vector3(-0.15, 0.95, 0.27)
	var ready := {"hr": Vector3(0.3, -0.36, -0.2), "hrb": Vector3(0.0, -0.3, -1.0), "hrk": Vector3(1.0, 0.2, 0.0), "hrp": Vector3(0.5, 0.0, 1.0)}
	var neutral := NEUTRAL.duplicate()
	neutral.erase("rot")
	neutral.erase("piv")
	# 1: forehand slash, high right to low left in front, lunge on the left foot
	var a1 := Vector3(0.42, 0.4, 0.1)
	var a1b := Vector3(0.05, 0.65, 0.76).normalized()
	var b1 := Vector3(0.14, 0.05, -0.62)
	var b1b := Vector3(-0.55, -0.15, -0.82).normalized()
	var n1p := a1b.cross(b1b).normalized()
	var c1 := Vector3(0.06, -0.14, -0.52)
	var c1b := Basis(n1p, 0.85) * b1b
	var k1 := -n1p
	d["attack1"] = {"len": 0.56, "in": 0.07, "out": 0.22, "ev": {"swing": 0.13, "impact": 0.205, "step": [0.2, 0.53]}, "keys": [
		[0.0, {}],
		[0.12, {"ease": true, "pel": Vector3(0.03, -0.07, 0.03), "pelr": Vector3(0.02, -0.16, 0.0), "spn": Vector3(0.03, -0.2, 0.03),
			"chs": Vector3(0.1, -0.34, 0.0), "nek": Vector3(-0.08, 0.3, 0.0), "hed": Vector3(0.0, 0.12, 0.0),
			"fr": Vector3(0.16, 0.093, 0.06), "frr": Vector3(0.0, -0.32, 0.0), "fl": Vector3(-0.15, 0.115, -0.08), "flr": Vector3(-0.25, 0.2, 0.0),
			"hl": Vector3(-0.38, -0.2, -0.2), "hlf": Vector3(-0.75, 0.15, -0.65), "hlp": Vector3(-0.6, -0.4, 0.8),
			"hr": a1, "hrb": a1b, "hrk": k1, "hrp": Vector3(0.8, -0.6, 0.2)}],
		[0.165, {"fl": Vector3(-0.16, 0.17, -0.22), "flr": Vector3(0.1, 0.15, 0.0), "pel": Vector3(0.0, -0.06, -0.06), "pelr": Vector3(0.0, -0.05, 0.0),
			"spn": Vector3(-0.02, -0.05, 0.0), "chs": Vector3(0.02, -0.08, 0.0), "nek": Vector3(-0.04, 0.1, 0.0),
			"hr": arcp(a1, b1, 0.5), "hrb": a1b.slerp(b1b, 0.5), "hrp": Vector3(0.8, -0.6, 0.1)}],
		[0.205, {"fl": Vector3(-0.17, 0.093, -0.36), "flr": Vector3(0.0, 0.12, 0.0), "fr": Vector3(0.15, 0.1, 0.1), "frr": Vector3(-0.18, -0.2, 0.0),
			"pel": Vector3(-0.02, -0.11, -0.14), "pelr": Vector3(0.0, 0.12, 0.0), "spn": Vector3(-0.08, 0.16, 0.0), "chs": Vector3(-0.04, 0.3, -0.02),
			"nek": Vector3(0.02, -0.28, 0.0), "hed": Vector3(0.0, -0.05, 0.0), "hl": Vector3(-0.42, -0.14, -0.12), "hlf": Vector3(-0.75, 0.12, -0.6),
			"hlp": Vector3(-0.6, -0.7, 0.5), "hr": b1, "hrb": b1b, "hrp": Vector3(0.8, -0.9, 0.1)}],
		[0.29, {"pel": Vector3(-0.03, -0.125, -0.15), "spn": Vector3(-0.12, 0.2, 0.02), "chs": Vector3(-0.1, 0.42, -0.02),
			"nek": Vector3(0.05, -0.34, 0.0), "hl": Vector3(-0.42, -0.06, -0.08), "hlf": Vector3(-0.8, 0.1, -0.5),
			"hr": c1, "hrb": c1b, "hrp": Vector3(0.5, -1.0, 0.2)}],
		[0.38, {"ease": true, "chs": Vector3(-0.08, 0.38, 0.0), "hr": c1 + Vector3(0.03, 0.03, 0.0), "hrb": Basis(n1p, -0.15) * c1b}],
		[0.47, _merge({"fl": Vector3(-0.16, 0.15, -0.2), "flr": Vector3(-0.2, 0.15, 0.0), "pel": Vector3(0.0, -0.07, -0.06), "pelr": Vector3(0.0, 0.03, 0.0),
			"spn": Vector3(-0.03, 0.08, 0.0), "chs": Vector3(0.02, 0.15, 0.0), "nek": Vector3(-0.03, -0.1, 0.0), "hed": Vector3.ZERO,
			"hl": Vector3(-0.35, -0.33, -0.08), "hlf": Vector3(-1.0, 0.0, -0.2)}, ready)],
		[0.56, neutral],
	]}
	# 2: backhand, left to right at chest height, step on the right foot
	var a2 := Vector3(-0.02, 0.04, -0.58)
	var a2b := Vector3(-0.45, 0.72, 0.52).normalized()
	var b2 := Vector3(0.3, 0.02, -0.6)
	var b2b := Vector3(0.45, 0.1, -0.89).normalized()
	var n2p := a2b.cross(b2b).normalized()
	var c2 := Vector3(0.6, 0.05, -0.2)
	var c2b := Basis(n2p, 0.85) * b2b
	var k2 := -n2p
	d["attack2"] = {"len": 0.56, "in": 0.06, "out": 0.22, "ev": {"swing": 0.12, "impact": 0.2, "step": [0.2, 0.52]}, "keys": [
		[0.0, {"chs": Vector3(-0.04, 0.32, 0.0), "spn": Vector3(-0.06, 0.15, 0.0), "pel": Vector3(-0.02, -0.1, -0.08), "pelr": Vector3(0.0, 0.12, 0.0),
			"fl": Vector3(-0.17, 0.093, -0.3), "flr": Vector3(0.0, 0.12, 0.0), "fr": Vector3(0.15, 0.093, 0.08), "frr": Vector3(0.0, -0.2, 0.0),
			"nek": Vector3(0.02, -0.28, 0.0), "hl": Vector3(-0.45, -0.1, -0.15), "hlf": Vector3(-0.7, 0.0, -0.7), "hlp": Vector3(-0.8, -0.5, 0.4),
			"hr": arcp(c1, a2, 0.5), "hrb": c1b.slerp(a2b, 0.5), "hrk": k2, "hrp": Vector3(0.7, -0.5, -0.75)}],
		[0.11, {"ease": true, "chs": Vector3(0.0, 0.42, 0.02), "spn": Vector3(-0.04, 0.2, 0.0), "pelr": Vector3(0.0, 0.18, 0.0),
			"nek": Vector3(0.0, -0.36, 0.0), "fr": Vector3(0.15, 0.11, 0.08), "frr": Vector3(-0.25, -0.2, 0.0),
			"hl": Vector3(-0.46, -0.08, -0.14), "hlf": Vector3(-0.7, 0.0, -0.7), "hr": a2, "hrb": a2b, "hrp": Vector3(0.75, -0.4, -0.8)}],
		[0.155, {"chs": Vector3(-0.04, 0.08, 0.0), "spn": Vector3(-0.06, 0.04, 0.0), "pelr": Vector3.ZERO, "fr": Vector3(0.18, 0.16, -0.1),
			"frr": Vector3(0.1, -0.25, 0.0), "hr": arcp(a2, b2, 0.5), "hrb": a2b.slerp(b2b, 0.5), "hrp": Vector3(0.9, -0.7, -0.2)}],
		[0.2, {"chs": Vector3(-0.06, -0.3, 0.02), "spn": Vector3(-0.08, -0.15, 0.0), "pelr": Vector3(0.0, -0.14, 0.0), "pel": Vector3(0.03, -0.1, -0.16),
			"fr": Vector3(0.2, 0.093, -0.22), "frr": Vector3(0.0, -0.3, 0.0), "fl": Vector3(-0.17, 0.093, -0.2), "nek": Vector3(0.0, 0.25, 0.0),
			"hl": Vector3(-0.41, -0.25, -0.1), "hlf": Vector3(-0.85, 0.0, -0.35), "hr": b2, "hrb": b2b, "hrp": Vector3(0.7, -0.7, 0.2)}],
		[0.28, {"chs": Vector3(-0.06, -0.46, 0.02), "spn": Vector3(-0.08, -0.22, 0.0), "nek": Vector3(0.02, 0.36, 0.0),
			"hr": c2, "hrb": c2b, "hrp": Vector3(0.7, -0.6, 0.4)}],
		[0.37, {"ease": true, "hr": c2 + Vector3(-0.03, 0.0, -0.03), "hrb": Basis(n2p, -0.15) * c2b}],
		[0.47, _merge({"fr": Vector3(0.16, 0.14, -0.04), "frr": Vector3(-0.2, -0.2, 0.0), "pel": Vector3(0.0, -0.07, -0.06), "pelr": Vector3(0.0, -0.03, 0.0),
			"spn": Vector3(-0.03, -0.05, 0.0), "chs": Vector3(0.02, -0.12, 0.0), "nek": Vector3(-0.03, 0.1, 0.0),
			"fl": Vector3(-0.15, 0.093, -0.1), "hl": Vector3(-0.35, -0.33, -0.08), "hlf": Vector3(-1.0, 0.0, -0.2)}, ready)],
		[0.56, neutral],
	]}
	# 3: overhead chop, the heaviest of the combo: rise, slam, stomp, hold, recover
	d["attack3"] = {"len": 0.8, "in": 0.07, "out": 0.25, "ev": {"swing": 0.27, "impact": 0.345, "step": [0.345, 0.72]}, "keys": [
		[0.0, _merge({"hrp": Vector3(0.8, -0.3, 0.5)}, swing(n3, u3, -0.2, -1.0, 0.4))],
		[0.24, _merge({"ease": true, "pel": Vector3(0.0, 0.0, 0.05), "pelr": Vector3(0.1, 0.0, 0.0), "spn": Vector3(0.12, 0.0, 0.0),
			"chs": Vector3(0.1, -0.05, 0.0), "nek": Vector3(-0.12, 0.0, 0.0), "fr": Vector3(0.15, 0.093, 0.06), "fl": Vector3(-0.15, 0.13, -0.05),
			"flr": Vector3(-0.35, 0.18, 0.0), "hl": Vector3(-0.25, 0.0, -0.3), "hlf": Vector3(-0.5, 0.2, -0.85), "hlp": Vector3(-0.8, -0.5, 0.5),
			"hrp": Vector3(0.9, 0.2, 0.4)}, swing(n3, u3, -0.35, -1.65, 0.42))],
		[0.3, _merge({"spn": Vector3(-0.05, 0.0, 0.0), "chs": Vector3(-0.05, 0.0, 0.0), "pel": Vector3(0.0, -0.08, -0.08), "fl": Vector3(-0.16, 0.16, -0.25),
			"flr": Vector3(0.1, 0.15, 0.0), "hrp": Vector3(0.9, -0.3, 0.3)}, swing(n3, u3, 1.0, 0.6, 0.58))],
		[0.345, _merge({"pel": Vector3(0.0, -0.26, -0.2), "pelr": Vector3(-0.05, 0.0, 0.0), "spn": Vector3(-0.3, 0.0, 0.0), "chs": Vector3(-0.22, 0.02, 0.0),
			"nek": Vector3(0.25, 0.0, 0.0), "fl": Vector3(-0.17, 0.093, -0.4), "flr": Vector3(0.0, 0.1, 0.0), "fr": Vector3(0.16, 0.12, 0.16),
			"frr": Vector3(-0.3, -0.2, 0.0), "hl": Vector3(-0.42, -0.38, -0.12), "hlf": Vector3(-0.8, -0.2, -0.5), "hrp": Vector3(0.7, -0.7, 0.3)},
			swing(n3, u3, 2.2, 2.45, 0.62))],
		[0.45, _merge({"ease": true, "pel": Vector3(0.0, -0.24, -0.19)}, swing(n3, u3, 2.3, 2.55, 0.6))],
		[0.6, _merge({"pel": Vector3(0.0, -0.1, -0.08), "spn": Vector3(-0.08, 0.0, 0.0), "chs": Vector3(0.0, 0.0, 0.0), "nek": Vector3(0.0, 0.0, 0.0),
			"fl": Vector3(-0.16, 0.14, -0.2), "flr": Vector3(-0.2, 0.15, 0.0), "fr": Vector3(0.15, 0.093, 0.06), "frr": Vector3(0.0, -0.18, 0.0),
			"hl": Vector3(-0.35, -0.33, -0.08), "hlf": Vector3(-1.0, 0.0, -0.2)}, ready)],
		[0.8, neutral],
	]}
	# heavy: a charged spin slash (wind up low, one full turn with the blade out flat, settle)
	var spin_sword := {"hr": Vector3(0.6, -0.04, -0.05), "hrb": Vector3(0.95, 0.05, 0.3), "hrk": Vector3(0.0, 1.0, 0.0), "hrp": Vector3(0.3, -1.0, 0.3)}
	d["heavy"] = {"len": 1.0, "in": 0.1, "out": 0.25, "ev": {"swing": 0.36, "impact": 0.47, "step": [0.4, 0.72]}, "keys": [
		[0.0, {}],
		[0.32, {"ease": true, "pel": Vector3(0.0, -0.16, 0.06), "pelr": Vector3(0.0, -0.32, 0.0), "spn": Vector3(0.05, -0.32, 0.0), "chs": Vector3(0.06, -0.42, 0.0),
			"nek": Vector3(-0.06, 0.55, 0.0), "fr": Vector3(0.24, 0.093, 0.16), "frr": Vector3(0.0, -0.5, 0.0), "fl": Vector3(-0.22, 0.093, -0.16),
			"flr": Vector3(0.0, 0.25, 0.0), "hr": Vector3(0.42, -0.25, 0.32), "hrb": Vector3(0.35, -0.15, 1.0), "hrk": Vector3(0.0, 1.0, 0.0),
			"hrp": Vector3(0.7, -0.4, 0.5), "hl": Vector3(-0.08, -0.05, -0.46), "hlf": Vector3(0.2, 0.0, -1.0), "hlp": Vector3(-1.0, -0.6, 0.3)}],
		[0.4, _merge({"rot": Vector3(0.0, 0.9, 0.0), "pelr": Vector3(0.0, -0.1, 0.0), "spn": Vector3(0.0, -0.1, 0.0), "chs": Vector3(0.02, -0.1, 0.0),
			"nek": Vector3(0.0, 0.1, 0.0), "hl": Vector3(-0.3, -0.18, 0.05), "hlf": Vector3(-1.0, 0.0, 0.3), "hlp": Vector3(-0.4, -0.5, 1.0)}, spin_sword)],
		[0.48, {"rot": Vector3(0.0, 2.7, 0.0), "pel": Vector3(0.0, -0.12, 0.0)}],
		[0.56, {"rot": Vector3(0.0, 4.5, 0.0)}],
		[0.64, {"rot": Vector3(0.0, 5.9, 0.0)}],
		[0.7, {"ease": true, "rot": Vector3(0.0, TAU, 0.0), "hr": Vector3(0.2, -0.12, -0.56), "hrb": Vector3(-0.6, -0.1, -0.8),
			"chs": Vector3(0.0, 0.3, 0.0), "spn": Vector3(-0.08, 0.15, 0.0)}],
		[0.82, {"chs": Vector3(0.02, 0.2, 0.0), "pel": Vector3(0.0, -0.1, 0.0)}],
		[1.0, _merge(neutral, {"rot": Vector3(0.0, TAU, 0.0)})],
	]}
	# parry: the shield punches forward (a bash) with a step
	d["parry"] = {"len": 0.5, "in": 0.05, "out": 0.2, "ev": {"impact": 0.15, "step": [0.14, 0.45]}, "keys": [
		[0.0, {}],
		[0.08, {"ease": true, "hl": Vector3(-0.26, -0.06, -0.26), "hlf": Vector3(-0.3, 0.05, -1.0), "hlp": Vector3(-1.0, -0.5, 0.4),
			"chs": Vector3(0.06, -0.18, 0.0), "spn": Vector3(0.0, -0.08, 0.0), "pel": Vector3(0.0, -0.07, 0.04),
			"hr": Vector3(0.36, -0.28, 0.05), "hrb": Vector3(0.2, 0.3, -1.0), "hrk": Vector3(1.0, 0.0, 0.2)}],
		[0.15, {"hl": Vector3(0.06, -0.02, -0.52), "hlf": Vector3(0.05, 0.05, -1.0), "hlp": Vector3(-1.0, -0.45, 0.35), "chs": Vector3(-0.04, 0.18, 0.0),
			"spn": Vector3(-0.12, 0.08, 0.0), "pel": Vector3(0.0, -0.1, -0.13), "fl": Vector3(-0.16, 0.093, -0.3), "flr": Vector3(0.0, 0.12, 0.0),
			"fr": Vector3(0.15, 0.1, 0.08), "frr": Vector3(-0.15, -0.2, 0.0), "hr": Vector3(0.38, -0.3, 0.12), "hrb": Vector3(0.2, 0.35, -1.0)}],
		[0.27, {"ease": true}],
		[0.5, neutral],
	]}
	# dodge: a forward roll, tucked tight (sword pointing back along the arm, shield over the knees)
	var rp := Vector3(0.0, 0.68, -0.18)
	d["dodge"] = {"len": 0.62, "in": 0.04, "out": 0.18, "ev": {"step": [0.06, 0.46]}, "keys": [
		[0.0, {}],
		[0.08, {"pel": Vector3(0.0, -0.28, -0.12), "spn": Vector3(-0.5, 0.0, 0.0), "chs": Vector3(-0.35, 0.0, 0.0), "nek": Vector3(-0.35, 0.0, 0.0),
			"hr": Vector3(0.25, -0.35, -0.08), "hrb": Vector3(0.1, -0.15, 1.0), "hrk": Vector3(1.0, 0.0, 0.0), "hrp": Vector3(0.6, -0.2, 0.8),
			"hl": Vector3(-0.44, -0.2, -0.05), "hlf": Vector3(-1.0, 0.0, -0.1), "hlp": Vector3(-0.3, -0.3, 1.0),
			"fr": Vector3(0.14, 0.12, 0.12), "frr": Vector3(-0.4, -0.1, 0.0), "fl": Vector3(-0.14, 0.093, -0.1), "piv": rp}],
		[0.15, {"rot": Vector3(-1.0, 0.0, 0.0), "pel": Vector3(0.0, -0.4, -0.05), "pelr": Vector3(0.0, 0.85, 0.0), "spn": Vector3(-0.75, 0.0, 0.0), "chs": Vector3(-0.55, 0.0, 0.0),
			"nek": Vector3(-0.55, 0.0, 0.0), "fr": Vector3(0.13, 0.4, 0.05), "fl": Vector3(-0.13, 0.38, 0.08), "frr": Vector3(-0.7, 0.0, 0.0),
			"flr": Vector3(-0.7, 0.0, 0.0), "hls": 1.0, "hl": Vector3(-0.48, 0.85, 0.05), "hlf": Vector3(-1.0, 0.0, 0.0), "hlp": Vector3(-1.0, 0.0, 0.0),
			"hrs": 1.0, "hr": Vector3(0.48, 0.55, -0.25), "hrb": Vector3(0.3, -0.3, 0.9), "hrk": Vector3(1.0, 0.0, 0.0), "hrp": Vector3(0.2, 0.7, 0.7)}],
		[0.25, {"rot": Vector3(-2.6, 0.0, 0.0)}],
		[0.35, {"rot": Vector3(-4.3, 0.0, 0.0)}],
		[0.45, {"ease": true, "rot": Vector3(-TAU, 0.0, 0.0), "pel": Vector3(0.0, -0.3, -0.02), "pelr": Vector3(0.0, 0.0, 0.0), "spn": Vector3(-0.35, 0.0, 0.0), "chs": Vector3(-0.2, 0.0, 0.0),
			"nek": Vector3(-0.15, 0.0, 0.0), "fr": Vector3(0.15, 0.093, 0.06), "fl": Vector3(-0.15, 0.093, -0.1), "frr": Vector3(0.0, -0.18, 0.0),
			"flr": Vector3(0.0, 0.18, 0.0)}],
		[0.62, _merge(neutral, {"rot": Vector3(-TAU, 0.0, 0.0), "piv": rp})],
	]}
	# light hit: a flinch
	d["hit"] = {"len": 0.38, "in": 0.03, "out": 0.15, "ev": {}, "keys": [
		[0.0, {}],
		[0.06, {"spn": Vector3(0.14, 0.05, 0.03), "chs": Vector3(0.12, 0.08, 0.0), "nek": Vector3(0.22, 0.0, 0.0), "pel": Vector3(0.0, -0.06, 0.06),
			"hl": Vector3(-0.3, -0.2, -0.2), "hlf": Vector3(-0.6, 0.2, -0.8), "hr": Vector3(0.4, -0.3, 0.05)}],
		[0.16, {"spn": Vector3(-0.04, 0.0, 0.0), "chs": Vector3(0.0, 0.0, 0.0), "nek": Vector3(-0.08, 0.0, 0.0)}],
		[0.38, neutral],
	]}
	# heavy hit: knocked back, a stumbling step, catch, recover
	d["hit_heavy"] = {"len": 0.85, "in": 0.03, "out": 0.2, "ev": {"step": [0.22, 0.7]}, "keys": [
		[0.0, {}],
		[0.07, {"spn": Vector3(0.32, 0.1, 0.05), "chs": Vector3(0.2, 0.1, 0.0), "nek": Vector3(0.3, 0.0, 0.0), "pel": Vector3(0.0, -0.04, 0.14),
			"pelr": Vector3(0.12, 0.0, 0.0), "hr": Vector3(0.55, -0.05, 0.2), "hrb": Vector3(0.6, 0.4, -0.6), "hl": Vector3(-0.55, -0.05, 0.1),
			"hlf": Vector3(-0.9, 0.3, 0.2), "fl": Vector3(-0.15, 0.15, 0.05)}],
		[0.22, {"fl": Vector3(-0.16, 0.093, 0.3), "pel": Vector3(0.0, -0.12, 0.22), "spn": Vector3(0.1, 0.0, 0.0), "chs": Vector3(0.05, 0.0, 0.0)}],
		[0.4, _merge({"pel": Vector3(0.0, -0.2, 0.18), "pelr": Vector3(0.0, 0.0, 0.0), "spn": Vector3(-0.2, 0.0, 0.0), "chs": Vector3(-0.1, 0.0, 0.0),
			"nek": Vector3(0.1, 0.0, 0.0), "hl": Vector3(-0.38, -0.33, -0.1), "hlf": Vector3(-1.0, 0.0, -0.3)}, ready)],
		[0.6, {"pel": Vector3(0.0, -0.08, 0.1), "fl": Vector3(-0.15, 0.13, 0.05)}],
		[0.85, neutral],
	]}
	# death: recoil, drop to the knees, slump, topple onto the right side; the last pose holds
	var dp := Vector3(0.14, 0.07, 0.04)
	d["death"] = {"len": 1.8, "in": 0.04, "out": 0.3, "hold": true, "ev": {"step": [0.48], "thud": 1.28}, "keys": [
		[0.0, {"piv": dp}],
		[0.1, {"spn": Vector3(0.25, 0.0, 0.0), "chs": Vector3(0.15, 0.0, 0.0), "nek": Vector3(0.3, 0.0, 0.0), "pel": Vector3(0.0, -0.05, 0.08),
			"hr": Vector3(0.45, -0.25, 0.1), "hl": Vector3(-0.45, -0.25, 0.05)}],
		[0.5, {"pel": Vector3(0.0, -0.405, 0.04), "pelr": Vector3(0.1, 0.0, 0.0), "spn": Vector3(-0.05, 0.0, 0.0), "chs": Vector3(-0.08, 0.0, 0.0),
			"nek": Vector3(0.15, 0.0, 0.0), "fr": Vector3(0.14, 0.2, 0.42), "frr": Vector3(-1.25, -0.05, 0.0), "fl": Vector3(-0.14, 0.2, 0.42),
			"flr": Vector3(-1.25, 0.05, 0.0), "hr": Vector3(0.33, -0.4, -0.16), "hrb": Vector3(0.25, -0.42, -0.87), "hl": Vector3(-0.33, -0.4, -0.1),
			"hlf": Vector3(-1.0, -0.2, -0.2)}],
		[0.85, {"spn": Vector3(-0.3, 0.0, 0.05), "chs": Vector3(-0.25, 0.0, 0.0), "nek": Vector3(0.35, 0.0, 0.1), "hr": Vector3(0.3, -0.4, -0.26),
			"hrb": Vector3(0.25, -0.3, -0.92)}],
		[1.3, {"rot": Vector3(0.0, 0.0, -1.3), "piv": Vector3(0.14, 0.26, 0.04), "spn": Vector3(-0.15, 0.0, -0.1), "chs": Vector3(0.0, 0.0, 0.1),
			"nek": Vector3(0.15, 0.0, 0.1), "hr": Vector3(0.3, 0.1, -0.45), "hrb": Vector3(0.2, 0.2, -1.0), "hrk": Vector3(1.0, 0.3, 0.0),
			"hrp": Vector3(0.3, -0.2, 1.0), "hl": Vector3(-0.4, -0.22, -0.12), "hlf": Vector3(-1.0, 0.2, 0.0), "hlp": Vector3(-0.6, -0.5, 0.6)}],
		[1.5, {"rot": Vector3(0.0, 0.0, -1.4)}],
		[1.8, {"rot": Vector3(0.0, 0.0, -1.37)}],
	]}
	# jump: push off into the rising air pose
	var air_up := {"fr": Vector3(0.13, 0.42, -0.16), "frr": Vector3(-0.35, -0.1, 0.0), "fl": Vector3(-0.14, 0.3, 0.14), "flr": Vector3(-0.7, 0.1, 0.0),
		"pel": Vector3(0.0, 0.02, 0.0), "pelr": Vector3(0.12, 0.0, 0.0), "spn": Vector3(-0.12, 0.0, 0.0), "chs": Vector3(0.0, 0.05, 0.0),
		"nek": Vector3(0.05, 0.0, 0.0), "hr": Vector3(0.36, -0.05, -0.2), "hrb": Vector3(0.1, 0.25, -1.0), "hrp": Vector3(0.6, -0.5, 0.8),
		"hl": Vector3(-0.36, -0.12, -0.18), "hlf": Vector3(-1.0, -0.2, -0.3), "hlp": Vector3(-0.6, -0.6, 0.8)}
	d["jump"] = {"len": 0.28, "in": 0.05, "out": 0.12, "ev": {"step": 0.0}, "keys": [
		[0.0, {"pel": Vector3(0.0, -0.12, 0.0), "spn": Vector3(-0.12, 0.0, 0.0), "hr": Vector3(0.36, -0.42, 0.05), "hl": Vector3(-0.36, -0.36, 0.05)}],
		[0.08, {"pel": Vector3(0.0, 0.04, 0.0), "spn": Vector3(0.0, 0.0, 0.0), "chs": Vector3(0.08, 0.0, 0.0), "fr": Vector3(0.14, 0.15, -0.05),
			"frr": Vector3(-0.7, -0.1, 0.0), "fl": Vector3(-0.15, 0.12, 0.08), "flr": Vector3(-0.8, 0.1, 0.0), "hr": Vector3(0.36, -0.05, -0.2),
			"hrb": Vector3(0.1, 0.25, -1.0), "hl": Vector3(-0.36, -0.12, -0.18)}],
		[0.28, air_up],
	]}
	# land: squash and recover
	d["land"] = {"len": 0.36, "in": 0.03, "out": 0.15, "ev": {"step": 0.0}, "keys": [
		[0.0, {"fr": Vector3(0.15, 0.12, -0.06), "fl": Vector3(-0.15, 0.16, 0.08), "pel": Vector3(0.0, -0.02, 0.0)}],
		[0.06, {"ease": true, "pel": Vector3(0.0, -0.26, 0.02), "pelr": Vector3(0.05, 0.0, 0.0), "spn": Vector3(-0.28, 0.0, 0.0), "chs": Vector3(-0.1, 0.0, 0.0),
			"nek": Vector3(0.2, 0.0, 0.0), "fr": Vector3(0.18, 0.093, 0.03), "frr": Vector3(0.0, -0.25, 0.0), "fl": Vector3(-0.17, 0.093, -0.08),
			"flr": Vector3(0.0, 0.25, 0.0), "hr": Vector3(0.42, -0.4, -0.15), "hrb": Vector3(0.3, -0.5, -1.0), "hl": Vector3(-0.42, -0.36, -0.1)}],
		[0.2, {"pel": Vector3(0.0, -0.1, 0.0), "spn": Vector3(-0.08, 0.0, 0.0), "chs": Vector3(0.02, 0.0, 0.0), "nek": Vector3.ZERO}],
		[0.36, neutral],
	]}
	_more_actions(d)
	return d


## The spear throw (left hand): reach over the left shoulder for the shaft, raise it, whip it forward.
static func _throw_def(lion: bool, neutral: Dictionary) -> Dictionary:
	var sp := spear_back_xf(lion)
	var sdir := -sp.basis.z
	var grab_cs := sp.origin + sdir * SPEAR_HOLD - P_CHEST
	var g_back := Vector3(-0.35, 0.45, -0.82)
	# palm up under the shaft: the fist sits inwards of the wrist, so the shaft passes clear of the shield
	var cock_b := Vector3(0.06, 0.12, -1.0)
	var cock_k := Vector3(0.0, -1.0, 0.0)
	var rel_b := Vector3(0.0, 0.06, -1.0)
	var rel_k := Vector3(0.0, -1.0, 0.0)
	return {"len": 0.95, "in": 0.08, "out": 0.2, "ev": {"grab": THROW_GRAB, "release": THROW_RELEASE, "swing": 0.38, "step": [0.33, 0.8]}, "keys": [
		[0.0, {}],
		[0.08, {"hl": Vector3(-0.42, 0.06, -0.12), "hlf": Vector3(-1.0, 0.0, 0.0), "hlp": Vector3(-0.8, 0.0, -0.6), "nek": Vector3(-0.04, 0.1, 0.0)}],
		[THROW_GRAB, {"ease": true, "pel": Vector3(0.0, -0.05, 0.01), "pelr": Vector3(0.02, -0.06, 0.0), "spn": Vector3(0.0, 0.0, 0.0),
			"chs": Vector3(0.05, 0.0, 0.0), "nek": Vector3(-0.04, 0.16, 0.0), "hed": Vector3(0.0, 0.06, 0.0),
			"hl": _lw(grab_cs, sdir, g_back), "hlb": sdir, "hlk": g_back, "hlx": 1.0, "hlp": Vector3(-0.35, 0.7, -1.0),
			"hlf": Vector3(-1.0, 0.25, -0.1), "hr": Vector3(0.38, -0.3, -0.16), "hrb": Vector3(0.3, -0.2, -1.0),
			"fl": Vector3(-0.15, 0.093, 0.04), "fr": Vector3(0.16, 0.093, -0.04)}],
		# cocked: torso wound to the left, the spear raised over the left shoulder pointing at the target, the
		# forearm upright (the shield stays edge-on beside the head)
		[0.31, {"ease": true, "pel": Vector3(0.02, -0.08, 0.05), "pelr": Vector3(0.05, 0.2, 0.0), "spn": Vector3(0.08, 0.1, 0.04),
			"chs": Vector3(0.08, 0.14, 0.04), "nek": Vector3(-0.06, -0.28, 0.0), "hed": Vector3(0.0, -0.06, 0.0), "hls": 1.0,
			"hl": _lw(Vector3(-0.44, 1.86, 0.17), cock_b, cock_k), "hlb": cock_b, "hlk": cock_k, "hlp": Vector3(-0.6, -0.8, 0.0),
			"hlf": Vector3(-1.0, 0.0, 0.0), "hrs": 1.0, "hr": Vector3(0.2, 1.36, -0.52), "hrb": Vector3(0.0, 0.35, -1.0), "hrk": Vector3(1.0, 0.0, 0.2),
			"hrp": Vector3(0.8, -0.6, 0.2), "fr": Vector3(0.17, 0.093, -0.26), "frr": Vector3(0.0, -0.1, 0.0), "fl": Vector3(-0.16, 0.11, 0.14),
			"flr": Vector3(-0.2, 0.25, 0.0)}],
		# the whip: hips and chest unwind, the elbow leads forward past the head
		[0.41, {"pel": Vector3(0.0, -0.09, -0.03), "pelr": Vector3(0.0, -0.08, 0.0), "spn": Vector3(-0.04, -0.1, 0.0), "chs": Vector3(-0.04, -0.18, 0.0),
			"nek": Vector3(0.0, 0.22, 0.0), "hl": _lw(Vector3(-0.38, 1.84, -0.14), Vector3(0.02, 0.2, -1.0), rel_k),
			"hlb": Vector3(0.02, 0.2, -1.0), "hlk": rel_k, "hlp": Vector3(-0.6, 0.0, -1.0), "hlf": Vector3(-1.0, -0.1, 0.0),
			"hr": Vector3(0.3, 1.2, -0.3), "hrb": Vector3(0.2, 0.0, -1.0)}],
		[THROW_RELEASE, {"pel": Vector3(0.0, -0.1, -0.12), "pelr": Vector3(0.0, -0.18, 0.0), "spn": Vector3(-0.14, -0.2, 0.0),
			"chs": Vector3(-0.12, -0.32, 0.0), "nek": Vector3(0.08, 0.34, 0.0), "hl": _lw(Vector3(-0.16, 1.62, -0.58), rel_b, rel_k),
			"hlb": rel_b, "hlp": Vector3(-1.0, -0.4, 0.2), "hlf": Vector3(-1.0, -0.6, 0.2), "fl": Vector3(-0.15, 0.13, 0.08), "flr": Vector3(-0.55, 0.2, 0.0),
			"hr": Vector3(0.42, 1.06, 0.06), "hrb": Vector3(0.4, -0.3, -0.9), "hrp": Vector3(0.6, -0.5, 0.8)}],
		[0.6, {"pel": Vector3(0.0, -0.11, -0.14), "spn": Vector3(-0.2, -0.28, 0.0), "chs": Vector3(-0.12, -0.36, 0.0), "nek": Vector3(0.1, 0.4, 0.0),
			"hl": Vector3(0.04, 1.05, -0.56), "hlx": 0.0, "hlf": Vector3(-0.3, 0.2, -1.0), "hlp": Vector3(-0.6, -0.8, 0.2),
			"fl": Vector3(-0.15, 0.12, -0.02), "flr": Vector3(-0.3, 0.15, 0.0), "hr": Vector3(0.4, 1.0, 0.02)}],
		[0.72, {"ease": true, "pel": Vector3(0.0, -0.09, -0.1), "hl": Vector3(-0.04, 1.0, -0.46)}],
		[0.95, neutral],
	]}


## CORE: catching the spear as it flies home butt first: the left fist closes on the shaft in front of the chest
## (the spear pointing out along its flight), swings it up over the shoulder (the throw's cocked pose) and straps it
## on the back (the throw's grab pose, where the spear in the fist and the one on the back coincide: CATCH_STOW).
## Played on the upper body (Hero / ChainSpear), so the legs keep running.
static func _catch_def(lion: bool, neutral: Dictionary) -> Dictionary:
	var sp := spear_back_xf(lion)
	var sdir := -sp.basis.z
	var grab_cs := sp.origin + sdir * SPEAR_HOLD - P_CHEST
	var g_back := Vector3(-0.35, 0.45, -0.82)
	var cock_b := Vector3(0.06, 0.12, -1.0)
	var cock_k := Vector3(0.0, -1.0, 0.0)
	var rel_b := Vector3(0.0, 0.06, -1.0)
	var rel_k := Vector3(0.0, -1.0, 0.0)
	return {"len": 0.46, "in": 0.04, "out": 0.16, "ev": {}, "keys": [
		[0.0, {}],
		[0.05, {"chs": Vector3(-0.05, -0.12, 0.0), "nek": Vector3(0.04, 0.14, 0.0), "hls": 1.0,
			"hl": _lw(Vector3(-0.22, 1.5, -0.5), rel_b, rel_k), "hlb": rel_b, "hlk": rel_k, "hlx": 1.0,
			"hlp": Vector3(-1.0, -0.4, 0.2), "hlf": Vector3(-1.0, -0.6, 0.2)}],
		[0.14, {"ease": true, "chs": Vector3(0.06, 0.12, 0.04), "nek": Vector3(-0.04, -0.2, 0.0), "hls": 1.0,
			"hl": _lw(Vector3(-0.44, 1.86, 0.17), cock_b, cock_k), "hlb": cock_b, "hlk": cock_k, "hlx": 1.0,
			"hlp": Vector3(-0.6, -0.8, 0.0), "hlf": Vector3(-1.0, 0.0, 0.0)}],
		[CATCH_STOW, {"ease": true, "chs": Vector3(0.05, 0.0, 0.0), "nek": Vector3(-0.04, 0.16, 0.0), "hls": 0.0,
			"hl": _lw(grab_cs, sdir, g_back), "hlb": sdir, "hlk": g_back, "hlx": 1.0, "hlp": Vector3(-0.35, 0.7, -1.0),
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
		[0.0, {}],
		[0.12, {"ease": true, "pel": Vector3(0.0, -0.08, -0.06), "pelr": Vector3(-0.04, 0.0, 0.0), "spn": Vector3(-0.15, 0.06, 0.0),
			"chs": Vector3(-0.06, 0.1, 0.0), "nek": Vector3(0.1, -0.1, 0.0), "hl": _lw(Vector3(-0.05, -0.04, -0.54), ch_b, ch_k),
			"hlb": ch_b, "hlk": ch_k, "hlx": 1.0, "hlp": Vector3(-1.0, -0.6, 0.2), "hlf": Vector3(-1.0, 0.1, 0.0),
			"hr": Vector3(0.06, -0.1, -0.36), "hrb": Vector3(0.45, -0.75, 0.5), "hrk": Vector3(1.0, 0.3, 0.0), "hrp": Vector3(1.0, -0.4, 0.3),
			"fl": Vector3(-0.16, 0.093, -0.24), "flr": Vector3(0.0, 0.15, 0.0), "fr": Vector3(0.16, 0.093, 0.12), "frr": Vector3(0.0, -0.25, 0.0)}],
		[0.3, {"pel": Vector3(0.0, -0.17, 0.17), "pelr": Vector3(0.16, 0.0, 0.0), "spn": Vector3(0.2, -0.05, 0.0), "chs": Vector3(0.12, -0.1, 0.0),
			"nek": Vector3(-0.18, 0.06, 0.0), "hl": _lw(Vector3(-0.08, -0.14, -0.34), ch_b, ch_k), "hr": Vector3(0.14, -0.24, -0.12),
			"hrb": Vector3(0.6, -0.6, 0.5), "fl": Vector3(-0.17, 0.093, -0.32), "fr": Vector3(0.18, 0.093, 0.3), "frr": Vector3(0.0, -0.3, 0.0)}],
		[0.5, {"ease": true, "pel": Vector3(0.0, -0.18, 0.19), "pelr": Vector3(0.19, 0.0, 0.0), "spn": Vector3(0.22, -0.03, 0.0)}],
		[0.8, neutral],
	]}
	# --- grapple: lunge in and lock the arms round the beast's neck (GRAPPLE_HOLD), strain in a loop, shove free ---
	var hold := {"pel": Vector3(0.0, -0.14, 0.07), "pelr": Vector3(-0.06, 0.0, 0.0), "spn": Vector3(-0.2, 0.0, 0.0),
		"chs": Vector3(-0.1, 0.0, 0.0), "nek": Vector3(0.14, 0.0, 0.0), "hed": Vector3(0.1, -0.35, 0.0),
		"fr": Vector3(0.22, 0.093, 0.18), "frr": Vector3(0.0, -0.3, 0.0), "fl": Vector3(-0.21, 0.093, -0.1), "flr": Vector3(0.0, 0.25, 0.0),
		"hrs": 1.0, "hr": Vector3(0.0, 1.46, -0.64), "hrb": Vector3(0.55, -0.6, -0.55), "hrk": Vector3(0.0, 1.0, -0.3), "hrp": Vector3(1.0, 0.4, 0.0),
		"hls": 1.0, "hl": Vector3(0.05, 0.9, -0.72), "hlf": Vector3(0.0, -0.6, -0.8), "hlp": Vector3(-1.0, -0.4, 0.0), "hlx": 0.0}
	d["grapple_start"] = {"len": 0.5, "in": 0.06, "out": 0.15, "ev": {"impact": 0.36, "step": [0.2]}, "keys": [
		[0.0, {}],
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
		"hrs": 1.0, "hr": Vector3(0.24, 0.65, -0.28), "hrb": Vector3(0.3, -0.4, -0.85), "hrk": Vector3(1.0, 0.2, 0.0), "hrp": Vector3(0.8, 0.0, 1.0)}
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
		[0.0, {}],
		[0.3, {"ease": true, "pel": Vector3(0.0, -0.12, 0.0), "spn": Vector3(-0.12, 0.05, 0.0), "chs": Vector3(-0.02, 0.2, 0.0),
			"nek": Vector3(0.1, -0.15, 0.0), "hr": Vector3(0.3, -0.4, -0.22), "hrb": Vector3(0.25, -0.6, -0.75), "hrk": Vector3(0.3, 0.9, 0.0),
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
	var ready := {"hr": Vector3(0.3, -0.36, -0.2), "hrb": Vector3(0.0, -0.3, -1.0), "hrk": Vector3(1.0, 0.2, 0.0), "hrp": Vector3(0.5, 0.0, 1.0)}
	d["recoil"] = {"len": 0.52, "in": 0.03, "out": 0.18, "ev": {"step": [0.08]}, "keys": [
		[0.0, {}],
		[0.07, {"hr": Vector3(0.52, 0.08, 0.02), "hrb": Vector3(0.7, 0.7, -0.15), "hrk": Vector3(0.6, -0.2, 0.75), "hrp": Vector3(0.8, -0.4, 0.4),
			"chs": Vector3(0.14, -0.22, 0.05), "spn": Vector3(0.1, -0.1, 0.0), "nek": Vector3(-0.12, 0.16, 0.0), "pel": Vector3(0.0, -0.06, 0.09),
			"pelr": Vector3(0.06, -0.08, 0.0), "fr": Vector3(0.17, 0.093, 0.2), "frr": Vector3(0.0, -0.22, 0.0), "fl": Vector3(-0.15, 0.12, -0.06),
			"flr": Vector3(-0.2, 0.18, 0.0), "hl": Vector3(-0.46, -0.12, 0.02), "hlf": Vector3(-1.0, 0.2, 0.2), "hlp": Vector3(-0.6, -0.5, 0.8)}],
		[0.2, {"ease": true, "hr": Vector3(0.5, 0.02, 0.0), "hrb": Vector3(0.75, 0.62, -0.2), "chs": Vector3(0.1, -0.18, 0.04),
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
	var up_blade := {"hrb": Vector3(0.3, 0.5, -0.8), "hrk": Vector3(1.0, 0.6, 0.0), "hrs": 1.0, "hls": 1.0}
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
			"hl": Vector3(-0.36, -0.3, -0.1), "hlf": Vector3(-1.0, 0.0, -0.3), "hlp": Vector3(-0.5, -0.2, 1.0), "hls": 0.0, "hrs": 0.0}, ready)],
		[0.58, neutral],
	]}


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

