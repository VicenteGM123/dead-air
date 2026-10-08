class_name RigCyclops
extends Rig
## Cíclope de sombra: a hunched brute of night sky, ~3.2 m. Massive shoulders and long gorilla arms with silver
## bands at the wrists, a heavy lower body that drags and frays into smoke, a small head low between the shoulders
## with ONE great almond eye in the dark of its face and two pale curved horns.
## "attack" = overhead double-fist smash; `impact` fires when the fists hit the ground (gameplay AoE there).
## Parts: shape, head, arm_l, arm_r (+ one eye halo) = 5 draw calls.

const BODY_LOW := Color("0A081C")
const BODY_HIGH := Color("2D2364")
const HORN := Color("8E86B2")
const HORN_TIP := Color("D2CCEA")
const HALO_I := 0.34
const HIPS := 1.0
const SHOULDER := Vector3(0.98, 1.2, -0.12) # relative to the hips pivot
const NECK := Vector3(0.0, 1.22, -0.62)
## Lower body bell (lathe radius, y, z offset) and the ellipsoid masses of the torso [centre, radii], shape space.
const LOW_SCALE := Vector3(1.12, 1.0, 0.92)
const LOW_PROF := [Vector3(0.22, -0.05, 0.1), Vector3(0.5, 0.12, 0.05), Vector3(0.7, 0.42, 0.0), Vector3(0.76, 0.78, 0.0), Vector3(0.7, 1.08, 0.0), Vector3(0.62, 1.32, -0.04)]
const MASSES := [
	[Vector3(0, 1.5, -0.1), Vector3(0.86, 0.68, 0.68)],
	[Vector3(0, 2.0, -0.32), Vector3(0.95, 0.6, 0.63)],
	[Vector3(0, 2.38, 0.18), Vector3(0.83, 0.56, 0.66)],
	[Vector3(-0.88, 2.22, -0.12), Vector3(0.5, 0.45, 0.5)],
	[Vector3(0.88, 2.22, -0.12), Vector3(0.5, 0.45, 0.5)],
	[Vector3(-0.36, 1.92, -0.72), Vector3(0.43, 0.31, 0.25)],
	[Vector3(0.36, 1.92, -0.72), Vector3(0.43, 0.31, 0.25)],
]
const SKULL_C := Vector3(0, 0.08, -0.02)
const SKULL_R := Vector3(0.38, 0.34, 0.38)
## Arm joints (right arm; mirrored in x for the left), fist offset from the wrist and fist radius.
const ELBOW := Vector3(0.1, -0.62, 0.02)
const WRIST := Vector3(0.06, -1.34, -0.2)
const FIST_OFF := Vector3(0.0, -0.28, -0.06)
const FIST_R := 0.32

var glow := Pal.NYX_GLOW
var rim := Color("9C7BFF")

var _body: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _halo: MeshInstance3D
var _sway := 0.0
var _seed := 0.0
var _step := 0.0


func _ready() -> void:
	_seed = randf() * TAU
	var mat := Materials.nyx_sky(rim)
	_body = add_part("body", null, "", Vector3(0, HIPS, 0))
	add_part("shape", ModelsCreatures.cached("cyclops_body", _mesh_body), "body", Vector3(0, -HIPS, 0), true, Materials.nyx_sky(rim, 0.8))
	_head = add_part("head", ModelsCreatures.cached("cyclops_head", _mesh_head), "body", NECK, true, mat)
	_arm_l = add_part("arm_l", ModelsCreatures.cached("cyclops_arm_l", _mesh_arm.bind(-1.0)), "body", Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z), true, mat)
	_arm_r = add_part("arm_r", ModelsCreatures.cached("cyclops_arm_r", _mesh_arm.bind(1.0)), "body", SHOULDER, true, mat)
	_halo = add_glow("head", Vector3(0, 0.06, -0.42), Color(glow.r, glow.g, glow.b), 0.62, HALO_I)


func set_dissolve(v: float) -> void:
	super(v)
	if _halo:
		Materials.set_param(_halo, &"intensity", HALO_I * (1.0 - v) * (1.0 - v))


# --- meshes ------------------------------------------------------------------------------------------------

func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(91)
	mb.vary = 0.03
	# Heavy lower body: a bell of smoke that drags on the ground.
	mb.push(Transform3D(Basis.from_scale(LOW_SCALE), Vector3.ZERO))
	mb.lathe(LOW_PROF, 12, func(c: Vector3, _r: int, _s: int) -> Color: return ModelsCreatures.sky_grad(c.y, 3.0, BODY_LOW, BODY_HIGH), PI / 12.0)
	mb.pop()
	# Hunched torso: core, chest, hump, the two great shoulders and the pectoral masses.
	for i in MASSES.size():
		var e: Array = MASSES[i]
		var c: Vector3 = e[0]
		var r: Vector3 = e[1]
		var big := maxf(r.x, maxf(r.y, r.z))
		mb.ico(c, big, ModelsCreatures.sky_grad(c.y + 0.3, 2.9, BODY_LOW, BODY_HIGH), 1 if big > 0.45 else 0, 0.05, r / big)
	# Silver crescent of Nyx on the left breast: a moon opening sideways (never a smile under the eye).
	mb.push(Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3.RIGHT, -0.2), Vector3(-0.36, 1.93, -0.955)))
	ModelsCreatures.crescent_flat(mb, Vector3.ZERO, 0.13, 0.055, 0.03, ModelsCreatures.SILVER, 12, 0.25)
	mb.pop()
	return mb.commit()


func _head_color(c: Vector3) -> Color:
	return ModelsCreatures.sky_grad(c.y + 2.3, 2.9, BODY_LOW, BODY_HIGH)


## Pointed almond (lens) in the XY plane of the current transform, bulging toward -Z. `top` < 1 flattens the
## upper lid (a stern, heavy-lidded eye).
static func _almond(mb: MeshBuilder, half_w: float, half_h: float, top: float, bulge: float, col: Color, segs: int = 10) -> void:
	var rim: Array[Vector3] = []
	for i in segs:
		var x := lerpf(-1.0, 1.0, float(i) / float(segs))
		rim.append(Vector3(x * half_w, pow(1.0 - x * x, 0.75) * half_h * top, 0))
	for i in segs:
		var x := lerpf(1.0, -1.0, float(i) / float(segs))
		rim.append(Vector3(x * half_w, -pow(1.0 - x * x, 0.75) * half_h, 0))
	var c := Vector3(0, -half_h * 0.1, -bulge)
	for i in rim.size():
		mb.tri(c, rim[i], rim[(i + 1) % rim.size()], col)


func _mesh_head() -> Mesh:
	var mb := MeshBuilder.new(93)
	mb.vary = 0.03
	# Skull and heavy brow; the face is a dark hollow under the brow.
	mb.ico(SKULL_C, 1.0, _head_color(Vector3(0, 0.1, 0)), 1, 0.04, SKULL_R)
	mb.push(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 0.07, -0.27)))
	mb.ico(Vector3.ZERO, 0.2, ModelsCreatures.VOID, 1, 0.0, Vector3(1.18, 0.62, 0.55))
	mb.pop()
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 0.19, -0.29)))
	mb.box(Vector3.ZERO, Vector3(0.48, 0.08, 0.14), _head_color(Vector3(0, 0.3, 0)))
	mb.pop()
	# The one great eye: a pointed almond with a heavy upper lid and a slit pupil, deep in the dark of the face.
	mb.push(Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 0.06, -0.37)))
	_almond(mb, 0.16, 0.075, 0.72, 0.03, glow, 12)
	mb.push(Transform3D(Basis.IDENTITY, Vector3(0, -0.004, -0.032)))
	mb.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	_almond(mb, 0.058, 0.014, 1.0, 0.006, ModelsCreatures.VOID, 6)
	mb.pop()
	mb.pop()
	mb.pop()
	# Two horns sweeping out, up and forward.
	for sx in [-1.0, 1.0]:
		var pts := [Vector3(0.24 * sx, 0.2, 0.02), Vector3(0.42 * sx, 0.37, 0.04), Vector3(0.6 * sx, 0.57, -0.04), Vector3(0.68 * sx, 0.79, -0.2), Vector3(0.62 * sx, 0.95, -0.38), Vector3(0.5 * sx, 1.01, -0.5)]
		mb.tube(pts, 0.12, 0.0, 6, func(k: float) -> Color: return HORN.lerp(HORN_TIP, k))
	return mb.commit()


func _mesh_arm(side: float) -> Mesh:
	var mb := MeshBuilder.new(95)
	mb.vary = 0.03
	var s := side
	var elbow := Vector3(ELBOW.x * s, ELBOW.y, ELBOW.z)
	var wrist := Vector3(WRIST.x * s, WRIST.y, WRIST.z)
	var col_a := func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.55)
	mb.tube([Vector3(0, 0.12, 0), Vector3(0.06 * s, -0.25, 0.02), elbow], 0.34, 0.25, 7, col_a)
	mb.ico(elbow, 0.26, BODY_HIGH.lerp(BODY_LOW, 0.4), 0)
	var col_b := func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, 0.3 + k * 0.4)
	mb.tube([elbow, elbow.lerp(wrist, 0.5) + Vector3(0.03 * s, 0, 0.0), wrist], 0.27, 0.22, 7, col_b)
	# Silver band at the wrist.
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.28), wrist + Vector3(0, 0.06, 0)))
	mb.ring(Vector3.ZERO, 0.245, 0.2, 0.08, 10, ModelsCreatures.SILVER_DIM)
	mb.pop()
	# Great fist.
	mb.ico(Vector3(wrist.x, wrist.y, wrist.z) + FIST_OFF, FIST_R, BODY_HIGH.lerp(BODY_LOW, 0.55), 1, 0.08, Vector3(1.0, 0.9, 1.1))
	return mb.commit()


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack":
			return 1.9
		"hit":
			return 0.35
		"death":
			return 0.8
		"spawn":
			return 1.4
	return 0.4


func _animate(delta: float) -> void:
	var mv := clampf(speed / speed_max, 0.0, 1.0)
	_sway = lerpf(_sway, mv, 1.0 - exp(-delta * 2.0))
	# Lumbering gait: a heavy roll from side to side, dipping on each "step".
	_step = fmod(_step + delta * lerpf(0.0, 1.7, _sway) * PI, TAU)
	var st := sin(_step)
	var dip := absf(sin(_step)) * 0.09 * _sway
	var breathe := sin(t * 1.3 + _seed)
	var pos := Vector3(0, HIPS - dip + breathe * 0.02, 0)
	var rot := Vector3(-0.1 * _sway + breathe * 0.015, st * 0.08 * _sway + sin(t * 0.4 + _seed) * 0.05, st * 0.07 * _sway)
	var scl := Vector3(1.0, 1.0 + breathe * 0.012, 1.0)
	var arm_r := Vector3(0.12 - st * 0.3 * _sway + breathe * 0.03, 0.0, 0.1)
	var arm_l := Vector3(0.12 + st * 0.3 * _sway + breathe * 0.03, 0.0, -0.1)
	var head := Vector3(0.03 + sin(t * 0.7) * 0.05, sin(t * 0.33 + _seed) * 0.22 - st * 0.05 * _sway, 0.0)
	if action != "":
		var p := ap()
		match action:
			"attack":
				# Wind up overhead (0-.42), hang (.42-.5), SMASH (.5-.58), stay down, haul back up.
				var up := smooth(p / 0.42)
				var slam := smooth((p - 0.5) / 0.08)
				var rec := smooth((p - 0.72) / 0.28)
				var raise := up * (1.0 - slam)
				var down := slam * (1.0 - rec)
				var shake := sin(t * 60.0) * 0.012 * smooth((p - 0.38) / 0.06) * (1.0 - slam)
				pos += Vector3(0, 0.16 * raise - 0.32 * down, 0.12 * raise - 0.45 * down)
				rot.x += 0.28 * raise - 0.55 * down + shake
				rot.y *= 1.0 - up * (1.0 - rec)
				scl = Vector3(1.0 - 0.03 * raise + 0.08 * down, 1.0 + 0.06 * raise - 0.12 * down, 1.0 - 0.03 * raise + 0.08 * down)
				# Rebound after the impact.
				var bounce := sin(clampf((p - 0.58) / 0.14, 0.0, 1.0) * PI) * 0.06
				pos.y += bounce
				# The attack owns the arms and head while it lasts, blending from and back to the idle pose.
				var own := up * (1.0 - rec)
				var arms := lerpf(lerpf(0.12, 3.25, raise), 1.2, slam)
				arm_r = arm_r.lerp(Vector3(arms, -0.12 * raise, 0.1 + 0.25 * raise - 0.15 * down), own)
				arm_l = arm_l.lerp(Vector3(arms, 0.12 * raise, -0.1 - 0.25 * raise + 0.15 * down), own)
				head = head.lerp(Vector3(-0.35 * raise + 0.3 * down, 0.0, 0.0), own)
				_mark("impact", 1.1)
			"hit":
				var k := sin(p * PI)
				rot.x += 0.1 * k
				pos.z += 0.12 * k
				head.x -= 0.3 * k
			"death":
				# Rears back with a silent howl of the shoulders, then sinks into its own smoke.
				var e := smooth(p)
				rot.x += 0.25 * sin(p * PI) - 0.3 * ease_in(p)
				pos.y -= 1.2 * ease_in(p)
				arm_r.x += 1.6 * sin(p * PI * 0.8)
				arm_l.x += 1.6 * sin(p * PI * 0.8)
				arm_r.z += 0.4 * e
				arm_l.z -= 0.4 * e
				head.x -= 0.6 * e
			"spawn":
				var e := smooth(p)
				pos.y -= (1.0 - e) * 2.6
				rot.x += 0.35 * (1.0 - e)
				arm_r.x += 1.2 * (1.0 - e)
				arm_l.x += 1.2 * (1.0 - e)
	_body.position = pos
	_body.rotation = rot
	_body.scale = scl
	_arm_r.rotation = arm_r
	_arm_l.rotation = arm_l
	_head.rotation = head
