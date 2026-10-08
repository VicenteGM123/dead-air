class_name RigNyxArcher
extends Rig
## Arquero de Nyx: a slender hooded shade whose hood runs out into a long tail down its back, with a quiver of
## pale arrows of light. Its bow is a silver crescent moon; string and arrow are conjured from light as it draws.
## "attack" = raise, draw, hold, release: `impact` fires at the release (gameplay launches the projectile then).
## It shoots half-turned with the bow held out in front: the draw sleeve reaches across the FRONT of the chest to
## a string anchored before the chin, and travels there along an arc in front of the body (never through it).
## Parts: shape, arm_l (sleeve + crescent bow), arm_r (draw sleeve), arrow (arrow + string, child of arm_l)
## + one eye halo = 5 draw calls.

const BODY_LOW := Color("0A0A1E")
const BODY_HIGH := Color("262662")
const LIGHT := Color(0.56, 0.94, 0.8, 0.5) # arrows of light
const LIGHT_DIM := Color(0.3, 0.55, 0.5, 0.5)
const MOON := Color(0.46, 0.5, 0.64, 0.5)
const MOON_EDGE := Color(0.78, 0.82, 0.94, 0.5)
const HALO_I := 0.42
const BODY_Y := 0.3
## Bow geometry in arm_l space (the arm hangs along -Y; the bow's long axis is Z, its belly faces -Y).
const HAND := Vector3(-0.02, -0.56, -0.05)
const BOW_R := 0.6
const BOW_OPEN := 1.12
const NOCK := Vector3(0.09, -0.2, -0.05) # string anchored at full draw, in arm_l space (in front of the chin)
const SHOULDER_L := Vector3(-0.29, 1.03, -0.02)
const SHOULDER_R := Vector3(0.29, 1.03, -0.02)
const DRAW_LEN := 0.57
## Shooting stance: the body turns this much (radians) toward its right; both shoulders roll forward and up so
## the bow, the drawn string and the draw sleeve all stay in front of the chest instead of crossing it.
const TURN := 0.5
const ROLL_L := Vector3(0.03, 0.07, -0.1)
const ROLL_R := Vector3(-0.09, 0.08, -0.2)
## Body lathe (radius, y, z offset).
const BODY_PROF := [
	Vector3(0.02, -0.05, 0.18), Vector3(0.1, 0.12, 0.1), Vector3(0.18, 0.38, 0.03), Vector3(0.23, 0.68, 0.0),
	Vector3(0.28, 0.93, 0.0), Vector3(0.28, 1.05, 0.0), Vector3(0.19, 1.16, 0.0), Vector3(0.26, 1.29, 0.0),
	Vector3(0.27, 1.45, 0.03), Vector3(0.21, 1.6, 0.1), Vector3(0.11, 1.73, 0.24), Vector3(0.035, 1.82, 0.4),
]

var glow := Color(0.55, 1.0, 0.92, 0.5)
var rim := Color("7CC4D8")

var _body: Node3D
var _bow_arm: Node3D
var _draw_arm: Node3D
var _arrow: Node3D
var _halo: MeshInstance3D
var _sway := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * TAU
	var mat := Materials.nyx_sky(rim)
	_body = add_part("body", null, "", Vector3(0, BODY_Y, 0))
	add_part("shape", ModelsCreatures.cached("archer_body", _mesh_body), "body", Vector3.ZERO, true, Materials.nyx_sky(rim, 0.42))
	_bow_arm = add_part("arm_l", ModelsCreatures.cached("archer_bow_arm", _mesh_bow_arm), "body", SHOULDER_L, false, mat)
	_draw_arm = add_part("arm_r", ModelsCreatures.cached("archer_draw_arm", _mesh_draw_arm), "body", SHOULDER_R, false, mat)
	_arrow = add_part("arrow", ModelsCreatures.cached("archer_arrow", _mesh_arrow), "arm_l", NOCK, false, mat)
	_arrow.visible = false
	_halo = add_glow("body", Vector3(0, 1.43, -0.34), Color(glow.r, glow.g, glow.b), 0.46, HALO_I)


func set_dissolve(v: float) -> void:
	super(v)
	if _halo:
		Materials.set_param(_halo, &"intensity", HALO_I * (1.0 - v) * (1.0 - v))


# --- meshes ------------------------------------------------------------------------------------------------

func _body_color(c: Vector3, _ring: int, _side: int) -> Color:
	var col := ModelsCreatures.sky_grad(c.y, 1.8, BODY_LOW, BODY_HIGH)
	if c.y > 1.25 and c.y < 1.58:
		var dir := Vector2(c.x, c.z).normalized()
		if dir.dot(Vector2(0, -1)) > 0.6:
			return ModelsCreatures.VOID
	return col


func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(81)
	mb.lathe(BODY_PROF, 12, _body_color, PI / 12.0)
	# The hood runs out into a long tail falling down the back.
	mb.tube([Vector3(0, 1.8, 0.37), Vector3(0, 1.68, 0.42), Vector3(0, 1.5, 0.4), Vector3(0.015, 1.28, 0.36), Vector3(0.03, 1.04, 0.37), Vector3(0.05, 0.8, 0.44)], 0.05, 0.004, 5,
		func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.7), false)
	# Eyes in the dark of the hood.
	for sx in [-1.0, 1.0]:
		ModelsCreatures.eye(mb, Vector3(0.082 * sx, 1.43, -0.285), 0.046, sx, 0.3, glow)
	# Silver crescent clasp at the chest.
	ModelsCreatures.crescent_wire(mb, Vector3(0, 1.0, -0.29), 0.045, 0.009, ModelsCreatures.SILVER)
	# Quiver across the back with pale arrows of light.
	var q0 := Vector3(-0.13, 0.72, 0.31)
	var q1 := Vector3(0.12, 1.3, 0.33)
	mb.limb(q0, q1, 0.06, 0.07, 6, Color("1A1838"))
	mb.limb(q0.lerp(q1, 0.85), q0.lerp(q1, 0.92), 0.075, 0.075, 6, ModelsCreatures.SILVER_DIM)
	var qd := (q1 - q0).normalized()
	for i in 4:
		var off := Vector3(-0.035 + 0.025 * float(i), 0.0, 0.01 * float(i % 2))
		var a := q1 + off - qd * 0.02
		var b := a + (qd + Vector3(0.05 * float(i) - 0.08, 0, 0.02)).normalized() * (0.2 + 0.03 * float(i % 2))
		mb.limb(a, b, 0.011, 0.009, 3, LIGHT_DIM)
		mb.limb(b - (b - a).normalized() * 0.07, b, 0.024, 0.0, 3, LIGHT)
	return mb.commit()


func _mesh_bow_arm() -> Mesh:
	var mb := MeshBuilder.new(83)
	mb.push(Transform3D(Basis.from_scale(Vector3(0.62, 1.0, 1.0)), Vector3.ZERO))
	mb.tube([Vector3(0, 0.05, 0), Vector3(-0.05, -0.16, -0.01), Vector3(-0.05, -0.36, -0.03), Vector3(-0.02, -0.56, -0.05)], 0.15, 0.04, 7,
		func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.6))
	mb.pop()
	# Crescent-moon bow: thick at the grip, tapering to sharp horns that curve back toward the archer.
	var c := HAND + Vector3(0, BOW_R * 0.8, 0)
	var n := 14
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in n + 1:
		var ph := lerpf(-BOW_OPEN, BOW_OPEN, float(i) / float(n))
		var o := c + Vector3(0, -cos(ph), sin(ph)) * BOW_R
		var w := 0.075 * pow(cos(ph / BOW_OPEN * PI * 0.5), 0.7) + 0.004
		outer.append(o)
		inner.append(o + (c - o).normalized() * w)
	var hx := Vector3(0.014, 0, 0)
	for i in n:
		var col := MOON if i != 0 and i != n - 1 else MOON_EDGE
		mb.quad(outer[i] + hx, outer[i + 1] + hx, inner[i + 1] + hx, inner[i] + hx, col)
		mb.quad(outer[i] - hx, inner[i] - hx, inner[i + 1] - hx, outer[i + 1] - hx, col)
		mb.quad(outer[i] - hx, outer[i + 1] - hx, outer[i + 1] + hx, outer[i] + hx, MOON_EDGE)
		mb.quad(inner[i] + hx, inner[i + 1] + hx, inner[i + 1] - hx, inner[i] - hx, MOON.darkened(0.15))
	# Dark grip wrapped around the middle.
	mb.limb(HAND + Vector3(0, -0.06, -0.06), HAND + Vector3(0, -0.06, 0.06), 0.03, 0.03, 5, Color("161430"))
	return mb.commit()


func _mesh_draw_arm() -> Mesh:
	var mb := MeshBuilder.new(85)
	mb.push(Transform3D(Basis.from_scale(Vector3(0.62, 1.0, 1.0)), Vector3.ZERO))
	mb.tube([Vector3(0, 0.05, 0), Vector3(0.05, -0.16, 0.0), Vector3(0.05, -0.36, -0.02), Vector3(0.02, -DRAW_LEN, -0.03)], 0.15, 0.035, 7,
		func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.6))
	mb.pop()
	return mb.commit()


## Bow horn tips in arm_l space.
static func _horn(sign_z: float) -> Vector3:
	var c := HAND + Vector3(0, BOW_R * 0.8, 0)
	return c + Vector3(0, -cos(BOW_OPEN), sin(BOW_OPEN) * sign_z) * BOW_R


func _mesh_arrow() -> Mesh:
	# Arrow of light along -Y from the nock (origin), plus the drawn string back to both horns.
	var mb := MeshBuilder.new(87)
	mb.limb(Vector3(0, 0.03, 0), Vector3(0, -0.6, 0), 0.012, 0.011, 4, LIGHT)
	mb.limb(Vector3(0, -0.58, 0), Vector3(0, -0.64, 0), 0.012, 0.032, 4, LIGHT)
	mb.limb(Vector3(0, -0.64, 0), Vector3(0, -0.76, 0), 0.032, 0.0, 4, MOON_EDGE)
	for k in 2:
		var a := PI * 0.5 * float(k)
		var d := Vector3(cos(a), 0, sin(a)) * 0.035
		mb.plate([Vector3(0, -0.02, 0), d + Vector3(0, 0.02, 0), d + Vector3(0, 0.1, 0), Vector3(0, 0.08, 0)], LIGHT_DIM)
		mb.plate([Vector3(0, -0.02, 0), Vector3(0, 0.08, 0), -d + Vector3(0, 0.1, 0), -d + Vector3(0, 0.02, 0)], LIGHT_DIM)
	for s in [-1.0, 1.0]:
		mb.limb(Vector3.ZERO, _horn(s) - NOCK, 0.005, 0.005, 3, LIGHT_DIM)
	return mb.commit()


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack":
			return 1.25
		"hit":
			return 0.25
		"death":
			return 0.75
		"spawn":
			return 1.1
	return 0.4


## Points the draw sleeve from its shoulder (`origin`, body space) at `target`, stretching it to reach.
func _aim_draw_arm(target: Vector3, origin: Vector3, k: float, rest: Basis) -> void:
	var d := target - origin
	var l := d.length()
	if l < 0.01 or k <= 0.0:
		_draw_arm.basis = rest
		return
	var y := -d / l
	var z := Vector3.RIGHT.cross(y).normalized()
	var x := y.cross(z)
	var aim := Basis(x, y * (l / DRAW_LEN), z)
	_draw_arm.basis = Basis(rest.x.lerp(aim.x, k), rest.y.lerp(aim.y, k), rest.z.lerp(aim.z, k))


func _animate(delta: float) -> void:
	var mv := clampf(speed / speed_max, 0.0, 1.0)
	_sway = lerpf(_sway, mv, 1.0 - exp(-delta * 3.0))
	var bob := sin(t * 2.2 + _seed) * 0.06
	var pos := Vector3(0, BODY_Y + bob, 0)
	var rot := Vector3(-0.18 * _sway + sin(t * 1.2) * 0.03, sin(t * 0.8 + _seed) * 0.05, sin(t * 1.6) * 0.04)
	var trail := 0.3 * _sway
	# Rest: the crescent bow held ready, nearly upright in front of the left side, the draw sleeve hanging.
	var bow_rot := Vector3(1.05 - trail + sin(t * 2.2 + 0.5) * 0.05, 0.42, -0.2)
	var draw_rot := Vector3(-trail + sin(t * 2.2 + 1.3) * 0.1, -0.1, 0.12 - sin(t * 1.9) * 0.04)
	var bow_pos := SHOULDER_L
	var draw_pos := SHOULDER_R
	var draw_k := 0.0
	var arrow_k := 0.0
	var anchor := Vector3.ZERO
	if action != "":
		var p := ap()
		match action:
			"attack":
				# Raise and turn (0-.22), reach and draw (.2-.55), hold (.55-.68), loose at .68, recover.
				var up := smooth(p / 0.22) * (1.0 - smooth((p - 0.82) / 0.18))
				var loose := smooth((p - 0.68) / 0.05)
				rot.y += -TURN * up
				rot.x += 0.06 * up - 0.08 * loose * (1.0 - smooth((p - 0.75) / 0.2))
				var raised := Vector3(PI * 0.5, TURN, 0.0)
				bow_rot = Vector3(lerp_angle(bow_rot.x, raised.x, up), lerp_angle(bow_rot.y, raised.y, up), lerp_angle(bow_rot.z, raised.z, up))
				bow_rot.x += 0.07 * loose * (1.0 - smooth((p - 0.72) / 0.15))
				bow_pos += ROLL_L * up
				# The draw hand reaches the grip, then pulls the string back to the anchor at the nock.
				var reach := smooth((p - 0.16) / 0.14)
				var pull := smooth((p - 0.3) / 0.25)
				draw_k = reach * (1.0 - smooth((p - 0.7) / 0.22))
				draw_pos += ROLL_R * draw_k
				var grip := HAND + Vector3(0.05, 0.08, 0)
				anchor = Transform3D(Basis.from_euler(bow_rot), bow_pos) * grip.lerp(NOCK, pull)
				# On the loose the hand flies back and out to the right (follow-through), clear of the chest.
				anchor += Vector3(0.16, 0.06, -0.02) * loose * (1.0 - smooth((p - 0.74) / 0.2))
				if p > 0.55 and p < 0.68:
					anchor += Vector3(sin(t * 47.0), sin(t * 53.0), 0) * 0.004
				arrow_k = smooth((p - 0.36) / 0.18) * (1.0 - loose)
				_mark("impact", 0.85)
			"hit":
				var k := sin(p * PI)
				pos.z += 0.22 * k
				rot.x += 0.3 * k
				bow_rot.x -= 0.3 * k
			"death":
				pos.y += p * 0.5
				rot.x -= 0.45 * p
				bow_rot.x -= 0.5 * p
				draw_rot.x -= 0.4 * p
				_body.scale = Vector3.ONE * (1.0 + p * 0.15)
			"spawn":
				pos.y -= (1.0 - smooth(p)) * 1.6
				bow_rot.x -= 0.4 * (1.0 - smooth(p))
	if action != "death":
		_body.scale = Vector3.ONE
	_body.position = pos
	_body.rotation = rot
	_bow_arm.rotation = bow_rot
	_bow_arm.position = bow_pos
	_draw_arm.position = draw_pos
	var rest := Basis.from_euler(draw_rot)
	if draw_k > 0.0:
		# The hand travels from where it hangs to the string along an arc in front of the chest (never through it).
		var rest_hand := draw_pos + rest * Vector3(0.02, -DRAW_LEN, -0.03)
		var path := rest_hand.lerp(anchor, smooth(draw_k)) + Vector3(0.0, 0.05, -0.3) * sin(draw_k * PI)
		_aim_draw_arm(path, draw_pos, draw_k, rest)
	else:
		_draw_arm.basis = rest
	_arrow.visible = arrow_k > 0.01
	if _arrow.visible:
		_arrow.scale = Vector3.ONE * lerpf(0.25, 1.0, arrow_k)
