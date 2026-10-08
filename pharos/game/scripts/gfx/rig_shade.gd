class_name RigShade
extends Rig
## Sombra: a child of Nyx made of night sky. One flowing silhouette — a hooded spirit whose hood tip falls
## back like a flame and whose hem frays into smoke — two flowing sleeves, two slanted eyes in the dark of the
## hood and a small silver crescent at the chest. Floats; never touches the ground.

const VOID := Color("06040F")
const BODY_LOW := Color("0A081C")
const BODY_HIGH := Color("2B2160")

var glow := Color(0.55, 0.95, 1.0, 0.5)
var rim := Color("9C7BFF")
var size := 1.0
var _sway := 0.0


func _ready() -> void:
	var body := add_part("body", null)
	body.position = Vector3(0, 0.3, 0)
	add_part("shape", _mesh_body(), "body", Vector3.ZERO, true, Materials.nyx_sky(rim, 0.42))
	add_part("arm_l", _mesh_sleeve(-1.0), "body", Vector3(-0.34, 1.02, -0.02), false, Materials.nyx_sky(rim))
	add_part("arm_r", _mesh_sleeve(1.0), "body", Vector3(0.34, 1.02, -0.02), false, Materials.nyx_sky(rim))
	add_glow("body", Vector3(0, 1.43, -0.34), Color(glow.r, glow.g, glow.b), 0.5, 0.45)
	scale = Vector3.ONE * size


func _body_color(c: Vector3, ring: int, side: int) -> Color:
	var k := clampf(c.y / 1.8, 0.0, 1.0)
	var col := BODY_LOW.lerp(BODY_HIGH, k * k)
	# The dark of the hood: an oval facing forward (-Z).
	if c.y > 1.27 and c.y < 1.6:
		var dir := Vector2(c.x, c.z).normalized()
		if dir.dot(Vector2(0, -1)) > 0.62:
			return VOID
	return col


func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(77)
	var prof := [
		Vector3(0.02, -0.05, 0.2), Vector3(0.12, 0.12, 0.1), Vector3(0.22, 0.38, 0.03), Vector3(0.29, 0.68, 0.0),
		Vector3(0.36, 0.94, 0.0), Vector3(0.34, 1.07, 0.0), Vector3(0.24, 1.19, 0.0), Vector3(0.30, 1.33, 0.0),
		Vector3(0.31, 1.49, 0.03), Vector3(0.24, 1.63, 0.1), Vector3(0.12, 1.76, 0.21), Vector3(0.02, 1.86, 0.36),
	]
	mb.lathe(prof, 12, _body_color, PI / 12.0)
	# Slanted almond eyes in the dark of the hood.
	for sx in [-1.0, 1.0]:
		mb.push(Transform3D(Basis(Vector3.BACK, 0.32 * sx), Vector3(0.085 * sx, 1.43, -0.29)))
		mb.ico(Vector3.ZERO, 0.05, glow, 0, 0.0, Vector3(1.55, 0.5, 0.5))
		mb.pop()
	# Silver crescent at the chest.
	var c := Vector3(0, 0.98, -0.355)
	var prev := Vector3.ZERO
	for i in 7:
		var a := lerpf(-2.2, 2.2, float(i) / 6.0)
		var p := c + Vector3(sin(a) * 0.05, cos(a) * 0.05, 0)
		if i > 0:
			mb.limb(prev, p, 0.01, 0.01, 4, Color(0.62, 0.6, 0.78, 0.5))
		prev = p
	return mb.commit()


func _mesh_sleeve(side: float) -> Mesh:
	# A flowing sleeve: flattened wisp, wide at the shoulder, tapering to a point that curls forward.
	var mb := MeshBuilder.new(79)
	mb.push(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.55)), Vector3.ZERO))
	var pts := [Vector3(0, 0.04, 0), Vector3(0.07 * side, -0.2, -0.05), Vector3(0.11 * side, -0.45, -0.14), Vector3(0.09 * side, -0.68, -0.3), Vector3(0.03 * side, -0.86, -0.5), Vector3(-0.02 * side, -0.94, -0.68)]
	mb.tube(pts, 0.17, 0.008, 7, func(t: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, t * 0.7))
	mb.pop()
	return mb.commit()


func _action_length(a: String) -> float:
	match a:
		"attack":
			return 0.75
		"hit":
			return 0.25
		"death":
			return 0.75
		"spawn":
			return 1.1
	return 0.4


func _animate(delta: float) -> void:
	var body: Node3D = parts["body"]
	var arm_l: Node3D = parts["arm_l"]
	var arm_r: Node3D = parts["arm_r"]
	var mv := clampf(speed / speed_max, 0.0, 1.0)
	_sway = lerpf(_sway, mv, 1.0 - exp(-delta * 3.0))
	var bob := sin(t * 2.4) * 0.07
	body.position = Vector3(0, 0.3 + bob, 0)
	body.rotation = Vector3(-0.2 * _sway + sin(t * 1.2) * 0.03, sin(t * 0.8) * 0.06, sin(t * 1.7) * 0.05)
	body.scale = Vector3(1.0 + sin(t * 2.4 + 1.0) * 0.025, 1.0 - sin(t * 2.4 + 1.0) * 0.02, 1.0)
	var trail := 0.35 * _sway
	arm_l.rotation = Vector3(-trail + sin(t * 2.4 + 0.5) * 0.12, 0.1, -0.12 + sin(t * 1.9) * 0.05)
	arm_r.rotation = Vector3(-trail + sin(t * 2.4 + 1.3) * 0.12, -0.1, 0.12 - sin(t * 1.9 + 0.7) * 0.05)
	if action == "":
		return
	var p := ap()
	match action:
		"attack":
			var k := strike_curve(p, 0.48, 0.64)
			body.rotation.x += 0.45 * k
			body.position.z = -maxf(k, 0.0) * 0.45
			body.position.y += 0.12 * maxf(-k, 0.0) * 3.0
			arm_l.rotation = Vector3(-0.6 * maxf(-k, 0.0) * 3.0 + 1.6 * maxf(k, 0.0), 0.35 * maxf(k, 0.0), -0.12)
			arm_r.rotation = Vector3(-0.6 * maxf(-k, 0.0) * 3.0 + 1.6 * maxf(k, 0.0), -0.35 * maxf(k, 0.0), 0.12)
			_mark("impact", 0.56)
		"hit":
			var k := sin(p * PI)
			body.rotation.x -= 0.35 * k
			body.position.z = 0.25 * k
		"death":
			body.rotation.x -= 0.5 * p
			body.position.y += p * 0.6
			body.scale = Vector3.ONE * (1.0 + p * 0.2)
		"spawn":
			body.position.y -= (1.0 - smooth(p)) * 1.6
