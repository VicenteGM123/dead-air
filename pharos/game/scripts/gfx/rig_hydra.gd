class_name RigHydra
extends Rig
## Hidra de la Noche, boss of the seventh night. A low serpentine body of night sky (~3 m) that frays into smoke
## where it meets the ground, a dorsal crest of fins with violet-lit leading edges, two pectoral fins and a tail
## that ends in a crescent fluke. Three long necks are skinned bone chains: they bend smoothly, sway with a wave
## that runs up to the head and trail behind turns (secondary motion). The heads are elegant closed-jaw serpent
## heads (no mouth, no teeth) with slanted violet eyes in dark sockets, a stern brow that sweeps back into a long
## horn and a slender dorsal sail (deliberately no fan or crown ornament: from above a fan reads as a hood, and an
## ornament between the eyes as a smile). The small silver crescent of Nyx is the tail fluke, which reads as a
## moon from the gameplay camera.
## Actions: attack (one head lunges to the ground, `impact` on contact), spit (the three heads rear and thrust,
## `release`), roar, spawn (rises from under the water), hit, death.
## MeshInstances: shape, fin_l, fin_r, tail, 3 necks + 3 eye halos + 3 snout glows = 13.

const BODY_LOW := Color("0A081C")
const BODY_HIGH := Color("2C2266")
const BELLY := Color("33276A")
const BELLY_DARK := Color("2A2059")
const FIN := Color("251B58")
const FIN_EDGE := Color(0.42, 0.3, 0.8, 0.5) # self-lit violet edges
const SPINE := Color(0.3, 0.21, 0.6, 0.5)
const FLUKE := Color(0.5, 0.47, 0.7, 0.5) # silver-lilac crescent
const RIM := Color("A882FF")
## Eye colour (self-lit): darker than Pal.BOSS_GLOW so that, multiplied by the shader's glow, it stays violet
## instead of burning to white.
const EYE := Color(0.6, 0.38, 0.98, 0.5)
const HALO_I := 0.3
const HEAD_SCALE := 1.25
## Just past the snout tip, in head-bone space.
const SNOUT := Vector3(0, 1.06, -0.04)

const NB := 6 # bones per neck: five neck segments and the head
const NECK_LEN := 3.0
const SEG := NECK_LEN / 5.0
const TB := 5
const TAIL_SEG := 0.42

## Body: lathe profile (radius, distance forward) around the long axis, centred at BODY_C, flattened vertically.
const BODY_PROF := [
	Vector2(0.1, -1.8), Vector2(0.36, -1.52), Vector2(0.62, -1.05), Vector2(0.8, -0.5), Vector2(0.86, 0.0),
	Vector2(0.82, 0.45), Vector2(0.68, 0.85), Vector2(0.45, 1.12), Vector2(0.2, 1.28), Vector2(0.02, 1.33),
]
const BODY_C := Vector3(0, 0.5, 0.35)
const BODY_FLAT := 0.62
const CHEST_C := Vector3(0, 0.6, -0.5)
const CHEST_R := Vector3(0.66, 0.38, 0.52)

## Neck roots (body space), lean outward (z) and yaw outward. Left, middle, right.
const ROOT_POS := [Vector3(-0.52, 0.74, -0.52), Vector3(0.0, 0.8, -0.72), Vector3(0.52, 0.74, -0.52)]
const ROOT_LEAN := [0.12, 0.0, -0.12]
const ROOT_YAW := [0.36, 0.0, -0.36]

## Neck poses: per-bone forward bend (radians, relative to the parent bone; + bends toward -Z).
const IDLE := [0.96, -0.35, -0.44, -0.26, 0.52, 1.22]
const COIL := [0.35, -0.35, -0.44, -0.17, 0.61, 1.83]
const STRIKE := [0.96, 0.32, 0.24, 0.17, 0.21, 0.4]
const WIND := [0.52, -0.35, -0.44, -0.17, 0.26, 1.13]
const THRUST := [0.70, -0.17, -0.26, -0.09, 0.35, 1.13]
const REAR := [0.35, -0.26, -0.26, -0.17, 0.0, 0.72]
const SLUMP := [1.40, 0.26, 0.09, 0.00, -0.09, 0.09]
## How much of the trailing lag each bone takes (the head trails the most).
const LAG_W := [0.08, 0.14, 0.2, 0.26, 0.3, 0.22]
const NECK_PHASE := [0.0, 2.1, 4.0]
const STRIKE_ORDER := [1, 0, 1, 2]
const TAIL_BEND := [0.0, -0.07, -0.07, -0.05, -0.04]

var glow := Pal.BOSS_GLOW

var _body: Node3D
var _fin_l: Node3D
var _fin_r: Node3D
var _tail: Skeleton3D
var _necks: Array[Skeleton3D] = []
var _halos: Array[MeshInstance3D] = []
var _spits: Array[MeshInstance3D] = []
var _lag := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _lag_v := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _last_yaw := 0.0
var _yaw_init := false
var _strike := 1
var _strike_seq := 0
var _sway := 0.0
var _seed := 0.0
var _dis := 0.0
var _jolted := false
# Per-neck action weights, filled by _neck_action() each frame (no allocations).
var _wc := 0.0
var _ws := 0.0
var _ww := 0.0
var _wt := 0.0
var _wr := 0.0
var _wd := 0.0
var _yaw_extra := 0.0
var _spread := 0.0
var _charge := 0.0


func _ready() -> void:
	_seed = randf() * TAU
	_body = add_part("body", null)
	add_part("shape", ModelsCreatures.cached("hydra_body", _mesh_body), "body", Vector3.ZERO, true, Materials.nyx_sky(RIM, 0.42))
	var mat := Materials.nyx_sky(RIM)
	_fin_l = add_part("fin_l", ModelsCreatures.cached("hydra_fin_l", _mesh_fin.bind(-1.0)), "body", Vector3(-0.7, 0.56, -0.15), false, mat)
	_fin_r = add_part("fin_r", ModelsCreatures.cached("hydra_fin_r", _mesh_fin.bind(1.0)), "body", Vector3(0.7, 0.56, -0.15), false, mat)
	var eye_rgb := Color(glow.r, glow.g, glow.b)
	for n in 3:
		var piv := add_part("neck%d" % n, null, "body", ROOT_POS[n])
		piv.basis = Basis.from_euler(Vector3(0.0, ROOT_YAW[n], ROOT_LEAN[n]))
		var sk := ModelsCreatures.make_chain(self, piv, NB, SEG, ModelsCreatures.cached("hydra_neck", _mesh_neck), mat)
		_necks.append(sk)
		var att := BoneAttachment3D.new()
		att.name = "head%d" % n
		att.bone_name = "b%d" % (NB - 1)
		sk.add_child(att)
		parts["head%d" % n] = att
		_halos.append(add_glow("head%d" % n, Vector3(0, 0.52, 0.13), eye_rgb, 0.7, HALO_I))
		var sg := add_glow("head%d" % n, SNOUT, eye_rgb, 0.9, 0.0)
		sg.visible = false
		_spits.append(sg)
	var tp := add_part("tail_root", null, "body", Vector3(0, 0.42, 1.72))
	tp.basis = Basis(Vector3.RIGHT, PI * 0.5 + 0.12)
	_tail = ModelsCreatures.make_chain(self, tp, TB, TAIL_SEG, ModelsCreatures.cached("hydra_tail", _mesh_tail), mat)
	_animate(0.0)


func set_dissolve(v: float) -> void:
	super(v)
	_dis = v


func play(a: String) -> float:
	if a == "attack":
		_strike = STRIKE_ORDER[_strike_seq % STRIKE_ORDER.size()]
		_strike_seq += 1
	_jolted = false
	return super(a)


## Index (0 left, 1 middle, 2 right) of the head that lunges in the current/next "attack".
func strike_head() -> int:
	return _strike


## Global position just past head `n`'s snout, where its spit glow burns (0 left, 1 middle, 2 right). Gameplay
## can launch each "spit" orb from here so the three shots leave the three heads.
func snout_position(n: int) -> Vector3:
	return (parts["head%d" % n] as Node3D).global_transform * SNOUT


func neck(n: int) -> Skeleton3D:
	return _necks[n]


func tail() -> Skeleton3D:
	return _tail


# --- meshes ------------------------------------------------------------------------------------------------

static func body_radius(fwd: float) -> float:
	if fwd <= BODY_PROF[0].y or fwd >= BODY_PROF[BODY_PROF.size() - 1].y:
		return 0.0
	for i in BODY_PROF.size() - 1:
		var a: Vector2 = BODY_PROF[i]
		var b: Vector2 = BODY_PROF[i + 1]
		if fwd <= b.y:
			return lerpf(a.x, b.x, (fwd - a.y) / (b.y - a.y))
	return 0.0


## Height of the body's back at depth z (body space).
static func body_top(z: float) -> float:
	return BODY_C.y + body_radius(BODY_C.z - z) * BODY_FLAT


func _body_color(c: Vector3, _ring: int, _side: int) -> Color:
	# Lathe space: c.z is up.
	var up := clampf(c.z / 0.8 * 0.5 + 0.5, 0.0, 1.0)
	return BODY_LOW.lerp(BODY_HIGH, up * up)


func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(301)
	mb.vary = 0.03
	mb.push(Transform3D(Basis.from_scale(Vector3(1.0, BODY_FLAT, 1.0)), BODY_C))
	mb.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	mb.lathe(BODY_PROF, 12, _body_color, PI / 12.0)
	mb.pop()
	mb.pop()
	# Breast where the three necks rise.
	mb.ico(CHEST_C, 1.0, BODY_HIGH.lerp(BODY_LOW, 0.35), 1, 0.03, CHEST_R)
	# Dorsal crest: swept fins with glowing leading edges, tall at the shoulders, low toward the tail.
	var n := 9
	for i in n:
		var k := float(i) / float(n - 1)
		var z := lerpf(-0.2, 1.62, k)
		var base := body_top(z) - 0.04
		var h := lerpf(0.46, 0.14, pow(k, 0.8))
		var bf := Vector3(0, base, z - 0.1)
		var bb := Vector3(0, base, z + 0.17)
		var tip := Vector3(0, base + h, z + 0.22)
		mb.plate([bf, bb, tip], FIN)
		mb.limb(bf + Vector3(0, 0.02, 0), tip, 0.016, 0.004, 3, FIN_EDGE)
	return mb.commit()


func _mesh_fin(side: float) -> Mesh:
	# Pectoral fin sweeping back and out like a folded wing: glowing rays and a scalloped membrane.
	var mb := MeshBuilder.new(303)
	var s := side
	var root := [Vector3(0, 0.03, -0.12), Vector3(0, -0.02, 0.12)]
	var tips := [Vector3(0.42 * s, 0.1, 0.12), Vector3(0.66 * s, 0.02, 0.48), Vector3(0.64 * s, -0.1, 0.84), Vector3(0.42 * s, -0.16, 1.02)]
	var hub: Vector3 = (root[0] + root[1]) * 0.5
	for i in tips.size() - 1:
		var a: Vector3 = tips[i]
		var b: Vector3 = tips[i + 1]
		var mid: Vector3 = hub.lerp((a + b) * 0.5, 0.8)
		mb.plate([hub, a, mid], FIN)
		mb.plate([hub, mid, b], FIN)
	mb.plate([root[0], tips[0], hub], FIN)
	mb.plate([hub, tips[3], root[1]], FIN)
	for tp in tips:
		mb.limb(hub, tp, 0.02, 0.004, 3, SPINE)
	return mb.commit()


func _neck_color(c: Vector3, ring: int, _side: int) -> Color:
	var k := clampf((c.y + 0.4) / (NECK_LEN + 0.4), 0.0, 1.0)
	if c.z < -0.07:
		# Belly plates facing forward, like a serpent's.
		return (BELLY if ring % 2 == 0 else BELLY_DARK).lerp(BODY_LOW, (1.0 - k) * 0.45)
	return BODY_LOW.lerp(BODY_HIGH, 0.35 + 0.65 * k)


func _mesh_neck() -> Mesh:
	var neck := MeshBuilder.new(305)
	var prof: Array = []
	var rings := 18
	for i in rings:
		var y := lerpf(-0.42, NECK_LEN + 0.04, float(i) / float(rings - 1))
		var k := clampf(y / NECK_LEN, 0.0, 1.0)
		prof.append(Vector2(lerpf(0.3, 0.19, smooth(k)), y))
	neck.lathe(prof, 9, _neck_color, PI / 18.0)
	# Small swept spines down the back of the neck (+Z), with lit tips.
	var y := 0.15
	while y < NECK_LEN - 0.3:
		var r := lerpf(0.3, 0.19, smooth(y / NECK_LEN)) - 0.02
		var h := lerpf(0.16, 0.09, y / NECK_LEN)
		var bf := Vector3(0, y + 0.1, r)
		var bb := Vector3(0, y - 0.1, r)
		var tip := Vector3(0, y - 0.17, r + h)
		var mid := Vector3(0, y - 0.03, r + h * 0.5)
		neck.plate([bf, bb, mid], FIN)
		neck.plate([mid, bb, tip], SPINE)
		y += 0.3
	var head := MeshBuilder.new(307)
	head.push(Transform3D(Basis.from_scale(Vector3.ONE * HEAD_SCALE), Vector3(0, NECK_LEN, 0)))
	_build_head(head)
	head.pop()
	return ModelsCreatures.commit_skinned([[neck, func(p: Vector3) -> Vector3: return ModelsCreatures.chain_weight(p, SEG, NB)], [head, NB - 1]])


func _head_color(c: Vector3, _ring: int, _side: int) -> Color:
	# Lathe space before flattening: c.z > 0 is the crown, < 0 the jaw.
	var col := BODY_HIGH.lerp(BODY_LOW, 0.15)
	if c.z > 0.07:
		col = BODY_HIGH.lightened(0.04)
	elif c.z < -0.08:
		col = BELLY.lerp(BODY_LOW, 0.3)
	if c.y > 0.62:
		col = col.darkened(0.15)
	return col


## Serpent head in head-bone space: snout toward +Y, crown toward +Z. Closed jaw: no mouth line, no teeth.
func _build_head(mb: MeshBuilder) -> void:
	mb.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), Vector3.ZERO))
	var prof := [
		Vector3(0.165, -0.08, 0.0), Vector3(0.205, 0.05, 0.015), Vector3(0.222, 0.18, 0.025), Vector3(0.21, 0.31, 0.02),
		Vector3(0.176, 0.44, 0.006), Vector3(0.13, 0.56, -0.012), Vector3(0.085, 0.66, -0.025), Vector3(0.04, 0.73, -0.035),
		Vector3(0.0, 0.755, -0.04),
	]
	mb.lathe(prof, 10, _head_color, PI / 10.0)
	mb.pop()
	for sx in [-1.0, 1.0]:
		# Slanted violet eye in a dark socket, set high on the side and looking forward.
		var d := Vector3(0.7 * sx, 0.34, 0.62)
		var b := ModelsCreatures.frame(Vector3(0, 1.0, -0.34), d)
		var ep := Vector3(0.143 * sx, 0.43, 0.078)
		mb.push(Transform3D(b, ep - d.normalized() * 0.014))
		mb.ico(Vector3.ZERO, 0.078, ModelsCreatures.VOID, 0, 0.0, Vector3(1.5, 0.66, 0.32))
		mb.pop()
		mb.push(Transform3D(b, ep))
		mb.ico(Vector3.ZERO, 0.062, EYE, 0, 0.0, Vector3(1.55, 0.46, 0.4))
		mb.pop()
		# Stern brow over the eye that runs back into a long swept horn (a clean V from the gameplay camera).
		mb.tube([Vector3(0.1 * sx, 0.55, 0.088), Vector3(0.158 * sx, 0.43, 0.128), Vector3(0.186 * sx, 0.28, 0.14), Vector3(0.2 * sx, 0.1, 0.16), Vector3(0.22 * sx, -0.14, 0.2), Vector3(0.25 * sx, -0.44, 0.22)], 0.032, 0.003, 4,
			func(k: float) -> Color: return BODY_HIGH.lightened(0.08).lerp(SPINE, smooth((k - 0.55) / 0.45)))
		# Small swept frill at the jaw hinge.
		var f0 := Vector3(0.19 * sx, 0.12, -0.01)
		var f1 := Vector3(0.2 * sx, -0.05, -0.04)
		var f2 := Vector3(0.3 * sx, -0.17, 0.0)
		var f3 := Vector3(0.27 * sx, 0.02, 0.03)
		mb.plate([f0, f1, f2, f3], FIN)
		mb.limb(f0, f2, 0.011, 0.003, 3, SPINE)
	# Dorsal sail along the midline, rising from the brow and running back onto the neck: a thin line seen from
	# above, a swept fin seen from the side; its edge is lit like the crest of the body.
	var base := [Vector3(0, 0.4, 0.12), Vector3(0, 0.22, 0.16), Vector3(0, 0.02, 0.16), Vector3(0, -0.18, 0.13), Vector3(0, -0.42, 0.13)]
	var top := [Vector3(0, 0.38, 0.14), Vector3(0, 0.17, 0.205), Vector3(0, -0.06, 0.255), Vector3(0, -0.3, 0.275), Vector3(0, -0.54, 0.19)]
	ModelsCreatures.strip(mb, base, top, func(k: float, _e: float) -> Color: return FIN.lerp(BODY_HIGH, 0.3 * k))
	for i in top.size() - 1:
		mb.limb(top[i], top[i + 1], 0.012, 0.012, 3, FIN_EDGE)


func _tail_color(c: Vector3, _ring: int, _side: int) -> Color:
	# Local -Z is up once the tail lies down behind the body.
	var up := clampf(-c.z / 0.3 * 0.5 + 0.5, 0.0, 1.0)
	return BODY_LOW.lerp(BODY_HIGH, up * up * 0.85)


func _mesh_tail() -> Mesh:
	var mb := MeshBuilder.new(309)
	var length := TAIL_SEG * float(TB)
	var prof: Array = []
	for i in 13:
		var y := lerpf(-0.35, length, float(i) / 12.0)
		var k := clampf(y / length, 0.0, 1.0)
		prof.append(Vector2(lerpf(0.3, 0.045, pow(k, 0.85)), y))
	mb.lathe(prof, 8, _tail_color, PI / 8.0, false, true)
	# Dorsal spines continuing the crest (local -Z is up).
	for i in 5:
		var y := 0.1 + float(i) * 0.36
		var r := lerpf(0.3, 0.045, pow(y / length, 0.85)) - 0.02
		var h := lerpf(0.13, 0.05, y / length)
		mb.plate([Vector3(0, y - 0.1, -r), Vector3(0, y + 0.16, -r), Vector3(0, y + 0.2, -r - h)], FIN)
		mb.limb(Vector3(0, y - 0.08, -r - 0.01), Vector3(0, y + 0.2, -r - h), 0.01, 0.003, 3, FIN_EDGE)
	var fluke := MeshBuilder.new(311)
	# Crescent fluke lying flat (horns swept back): a moon of night at the end of the tail.
	ModelsCreatures.crescent_flat(fluke, Vector3(0, length + 0.12, 0), 0.34, 0.15, 0.035, FLUKE, 14, PI * 0.5)
	return ModelsCreatures.commit_skinned([[mb, func(p: Vector3) -> Vector3: return ModelsCreatures.chain_weight(p, TAIL_SEG, TB)], [fluke, TB - 1]])


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack":
			return 1.5
		"spit":
			return 1.3
		"roar":
			return 1.6
		"spawn":
			return 2.4
		"hit":
			return 0.4
		"death":
			return 1.0
	return 0.4


## Fills the per-neck action weights for neck `n` at action progress `p`.
func _neck_action(n: int, p: float) -> void:
	_wc = 0.0
	_ws = 0.0
	_ww = 0.0
	_wt = 0.0
	_wr = 0.0
	_wd = 0.0
	_yaw_extra = 0.0
	_spread = 0.0
	_charge = 0.0
	var side := float(n - 1)
	match action:
		"attack":
			var coil := smooth(p / 0.3) * (1.0 - smooth((p - 0.3) / 0.1))
			var strike := ease_out(clampf((p - 0.3) / 0.14, 0.0, 1.0)) * (1.0 - smooth((p - 0.6) / 0.4))
			if n == _strike:
				_wc = coil
				_ws = strike
				# Side heads turn in a little so the bite lands ahead of the body.
				_yaw_extra = -float(ROOT_YAW[n]) * 0.55 * strike
			else:
				# The other two rise and lean away from the striking neck (+yaw / +roll turn a neck toward -X).
				_wr = 0.3 * (coil + strike * 0.7)
				var away := -side if side != 0.0 else (-1.0 if _strike == 0 else 1.0)
				_yaw_extra = 0.22 * away * (coil + strike)
				_spread = 0.08 * away * (coil + strike)
		"spit":
			var q := clampf(p + side * 0.025, 0.0, 1.0)
			_ww = smooth(q / 0.4) * (1.0 - smooth((q - 0.4) / 0.08))
			_wt = smooth((q - 0.4) / 0.08) * (1.0 - smooth((q - 0.62) / 0.38))
			_charge = smooth(q / 0.42) * (1.0 - smooth((q - 0.47) / 0.07))
			_yaw_extra = -float(ROOT_YAW[n]) * 0.35 * _wt
			# Rearing back would swing the side necks in behind the middle one: lean them out while winding up.
			_spread = -0.1 * side * _ww
		"roar":
			var r := smooth(p / 0.22) * (1.0 - smooth((p - 0.76) / 0.24))
			_wr = r
			_spread = -0.22 * side * r
			_yaw_extra = -0.25 * side * r + sin(t * 31.0 + float(n) * 2.0) * 0.05 * r
		"spawn":
			var q := clampf(p - float(n % 2) * 0.06, 0.0, 1.0)
			_wr = 1.0 - smooth((q - 0.42) / 0.45)
			_spread = -0.17 * side * (1.0 - smooth(q / 0.8))
		"hit":
			_wr = 0.45 * sin(p * PI)
		"death":
			var q := clampf(p - float(n) * 0.07, 0.0, 1.0)
			_wr = sin(clampf(q / 0.28, 0.0, 1.0) * PI) * 0.8
			_wd = ease_in(clampf((q - 0.18) / 0.55, 0.0, 1.0))
			_spread = -0.2 * side * _wd


func _animate(delta: float) -> void:
	var mv := clampf(speed / speed_max, 0.0, 1.0)
	_sway = lerpf(_sway, mv, 1.0 - exp(-delta * 2.0))
	var breathe := sin(t * 1.1 + _seed)
	var pos := Vector3(0, breathe * 0.015, 0)
	var rot := Vector3(breathe * 0.01, sin(t * 1.8) * 0.05 * _sway + sin(t * 0.3 + _seed) * 0.03, sin(t * 1.8 + 0.6) * 0.025 * _sway)
	var scl := Vector3(1.0 + breathe * 0.01, 1.0 + breathe * 0.018, 1.0)
	var flare := 0.0
	var eye := 0.0
	var p := ap()
	var acting := action != ""
	if acting:
		match action:
			"attack":
				var coil := smooth(p / 0.3) * (1.0 - smooth((p - 0.3) / 0.1))
				var strike := ease_out(clampf((p - 0.3) / 0.14, 0.0, 1.0)) * (1.0 - smooth((p - 0.6) / 0.4))
				pos += Vector3(0, 0.05 * coil - 0.05 * strike, 0.18 * coil - 0.42 * strike)
				rot.x += 0.05 * coil - 0.07 * strike
				rot.y += 0.12 * float(_strike - 1) * strike
				eye = coil
				_mark("impact", 0.44 * 1.5)
				if action_t >= 0.66 and not _jolted:
					_jolted = true
					for n in 3:
						if n != _strike:
							_lag_v[n] += Vector2(0.0, 2.2)
			"spit":
				var wind := smooth(p / 0.4) * (1.0 - smooth((p - 0.4) / 0.08))
				var thrust := smooth((p - 0.4) / 0.08) * (1.0 - smooth((p - 0.62) / 0.38))
				pos += Vector3(0, 0.06 * wind, 0.14 * wind - 0.2 * thrust)
				rot.x += 0.05 * wind - 0.04 * thrust
				eye = wind + thrust
				flare = 0.3 * wind
				_mark("release", 0.47 * 1.3)
			"roar":
				var r := smooth(p / 0.22) * (1.0 - smooth((p - 0.76) / 0.24))
				pos.y += 0.1 * r
				rot.x += 0.1 * r + sin(t * 29.0) * 0.012 * r
				scl.y += 0.04 * r
				flare = r
				eye = 1.6 * r
			"spawn":
				var e := smooth(p / 0.85)
				pos.y -= 3.9 * (1.0 - e)
				pos.z += 0.6 * (1.0 - e)
				rot.x += 0.32 * (1.0 - e)
				flare = sin(clampf((p - 0.55) / 0.45, 0.0, 1.0) * PI)
				eye = flare
			"hit":
				var k := sin(p * PI)
				pos.z += 0.14 * k
				rot.x += 0.05 * k
				if not _jolted:
					_jolted = true
					for n in 3:
						_lag_v[n] += Vector2(randf_range(-1.0, 1.0), -2.4)
			"death":
				var c := ease_in(clampf((p - 0.2) / 0.6, 0.0, 1.0))
				pos.y -= 0.45 * c
				rot.x += 0.06 * c
				rot.z += 0.08 * c
				flare = sin(clampf(p / 0.3, 0.0, 1.0) * PI)
	_body.position = pos
	_body.rotation = rot
	_body.scale = scl
	# Fins paddle slowly and flare on a roar.
	var paddle := sin(t * 1.3 + _seed) * 0.08 + sin(t * 2.6) * 0.05 * _sway
	_fin_r.rotation = Vector3(paddle * 0.5, -0.1 * flare, 0.08 + paddle + 0.55 * flare)
	_fin_l.rotation = Vector3(paddle * 0.5, 0.1 * flare, -(0.08 + paddle + 0.55 * flare))
	# Secondary motion: when the body turns the necks trail behind and spring back.
	var yaw_now := global_rotation.y if is_inside_tree() else rotation.y
	var dyaw := 0.0
	if _yaw_init:
		dyaw = angle_difference(_last_yaw, yaw_now)
	_yaw_init = true
	_last_yaw = yaw_now
	# Calmer sway while biting or dying, eased in and out so the necks never snap.
	var calm_all := 1.0
	if acting and action == "attack":
		calm_all = 1.0 - 0.4 * smooth(p / 0.15) * (1.0 - smooth((p - 0.8) / 0.2))
	elif acting and action == "death":
		calm_all = 1.0 - 0.4 * smooth(p / 0.15)
	for n in 3:
		var x: Vector2 = _lag[n]
		var v: Vector2 = _lag_v[n]
		x.x = clampf(x.x - dyaw * 0.9, -0.45, 0.45)
		v += (-x * 38.0 - v * 8.5) * minf(delta, 0.05)
		x += v * minf(delta, 0.05)
		# Limits of the secondary motion (a fast turn, two stacked jolts): beyond them the necks would cross.
		x.y = clampf(x.y, -0.3, 0.3)
		_lag[n] = x
		_lag_v[n] = v
		if acting:
			_neck_action(n, p)
		else:
			_neck_action(n, 0.0)
		var calm := calm_all * (1.0 - 0.85 * maxf(_ws, _wt))
		var ph: float = NECK_PHASE[n] + _seed
		var sk := _necks[n]
		var bend0 := 0.08 * absf(float(n - 1))
		for i in NB:
			var a: float = IDLE[i]
			if i == 0:
				a += bend0
			a = lerpf(a, COIL[i], _wc)
			a = lerpf(a, STRIKE[i], _ws)
			a = lerpf(a, WIND[i], _ww)
			a = lerpf(a, THRUST[i], _wt)
			a = lerpf(a, REAR[i], _wr)
			a = lerpf(a, SLUMP[i], _wd)
			a += sin(t * 1.25 + ph - float(i) * 0.6) * 0.045 * calm + x.y * LAG_W[i]
			var yaw: float = sin(t * 0.8 + ph * 1.7 - float(i) * 0.5) * 0.05 * calm + x.x * LAG_W[i]
			var roll := 0.0
			if i == 0:
				yaw += _yaw_extra
				roll = _spread
			if i == NB - 1:
				yaw += sin(t * 0.37 + ph) * 0.22 * calm
			sk.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(-a, yaw, roll)))
		var fade := (1.0 - _dis) * (1.0 - _dis)
		Materials.set_param(_halos[n], &"intensity", HALO_I * (1.0 + eye * 0.8 + _charge) * fade)
		var sg := _spits[n]
		sg.visible = _charge > 0.02
		if sg.visible:
			Materials.set_param(sg, &"intensity", _charge * 0.9 * fade)
			sg.scale = Vector3.ONE * (0.35 + 0.75 * _charge)
	# Tail: a slow travelling wave, livelier while moving; it lies on the ground behind the body.
	var tw := 0.07 + 0.1 * _sway
	for i in TB:
		var k := float(i) / float(TB - 1)
		var sway := sin(t * 1.5 - float(i) * 0.8 + _seed) * tw * (0.4 + 0.6 * k)
		if acting and action == "roar":
			sway += sin(t * 9.0 - float(i)) * 0.08 * sin(ap() * PI)
		_tail.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(TAIL_BEND[i], 0.0, sway)))
