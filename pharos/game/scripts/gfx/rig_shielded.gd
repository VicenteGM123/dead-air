class_name RigShielded
extends Rig
## Escudado: a fallen hoplite of the night. A tall, broad shade (pteruges and a tattered cape made of night sky)
## still wearing its dark bronze Corinthian helmet — the T of the face opening glows cyan, there is no face
## behind it — a tall Boeotian shield with a silver crescent and a broken spear. Heavier and slower than the Sombra.
## Parts: shape (body, cape, shield arm), helmet, shield, arm_r (sleeve + spear) + one halo = 5 draw calls.

const BODY_LOW := Color("0A081C")
const BODY_HIGH := Color("2E2462")
const STRIPE := Color("3A2E72")
const BRONZE := Color("3B2F26") # dark bronze, nearly black
const BRONZE_EDGE := Color("86663A")
const BRONZE_DARK := Color("221B16")
const CREST := Color("43347F")
const CREST_EDGE := Color(0.36, 0.3, 0.66, 0.5)
const SHIELD_FACE := Color("2A2058")
const SHAFT := Color("2A2134")
const TIP := Color(0.36, 0.5, 0.56, 0.5)
const HALO_I := 0.26
const BODY_Y := 0.2
## End of the shield arm (body mesh): the hand on the shield's grip.
const SHIELD_HAND := Vector3(-0.3, 0.97, -0.4)
## Body lathe (radius, y, z offset), built with scale BODY_SCALE.
const BODY_SCALE := Vector3(1.18, 1.0, 0.86)
const BODY_PROF := [
	Vector3(0.02, -0.05, 0.16), Vector3(0.14, 0.12, 0.08), Vector3(0.25, 0.36, 0.03), Vector3(0.31, 0.6, 0.0),
	Vector3(0.335, 0.8, 0.0), Vector3(0.3, 0.85, 0.0), Vector3(0.29, 0.98, 0.0), Vector3(0.32, 1.1, 0.0),
	Vector3(0.38, 1.26, 0.0), Vector3(0.41, 1.4, 0.0), Vector3(0.35, 1.5, 0.0), Vector3(0.2, 1.57, 0.0),
	Vector3(0.12, 1.61, 0.0), Vector3(0.1, 1.74, 0.0),
]

var glow := Pal.NYX_GLOW
var rim := Color("8C86FF")

var _body: Node3D
var _helmet: Node3D
var _shield: Node3D
var _arm: Node3D
var _halo: MeshInstance3D
var _sway := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * TAU
	_body = add_part("body", null, "", Vector3(0, BODY_Y, 0))
	add_part("shape", ModelsCreatures.cached("shielded_body", _mesh_body), "body", Vector3.ZERO, true, Materials.nyx_sky(rim, 0.55))
	_helmet = add_part("helmet", ModelsCreatures.cached("shielded_helmet", _mesh_helmet), "body", Vector3(0, 1.6, 0.0), true, Materials.nyx(rim))
	_shield = add_part("shield", ModelsCreatures.cached("shielded_shield", _mesh_shield), "body", Vector3(-0.16, 0.98, -0.47), true, Materials.nyx_sky(rim))
	_arm = add_part("arm_r", ModelsCreatures.cached("shielded_arm", _mesh_arm), "body", Vector3(0.43, 1.38, 0.0), false, Materials.nyx_sky(rim))
	_halo = add_glow("helmet", Vector3(0, 0.22, -0.27), Color(glow.r, glow.g, glow.b), 0.34, HALO_I)


func set_dissolve(v: float) -> void:
	super(v)
	if _halo:
		Materials.set_param(_halo, &"intensity", HALO_I * (1.0 - v) * (1.0 - v))


# --- meshes ------------------------------------------------------------------------------------------------

func _body_color(c: Vector3, ring: int, side: int) -> Color:
	var col := ModelsCreatures.sky_grad(c.y, 1.7, BODY_LOW, BODY_HIGH)
	# Pteruges: alternating strips of night below the cuirass.
	if ring >= 2 and ring <= 4 and side % 2 == 0:
		col = col.lerp(STRIPE, 0.5)
	return col


func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(61)
	mb.push(Transform3D(Basis.from_scale(BODY_SCALE), Vector3.ZERO))
	mb.lathe(BODY_PROF, 14, _body_color, PI / 14.0)
	mb.pop()
	# Tattered cape of night hanging from the shoulders.
	var top: Array = []
	var bot: Array = []
	for i in 7:
		var u := lerpf(-1.0, 1.0, float(i) / 6.0)
		top.append(Vector3(u * 0.36, 1.46 - absf(u) * 0.04, 0.3 + 0.08 * (1.0 - u * u)))
		var tatter := 0.09 if i % 2 == 1 else -0.03
		bot.append(Vector3(u * 0.5, 0.3 + tatter + absf(u) * 0.12, 0.42 + 0.16 * (1.0 - u * u)))
	ModelsCreatures.strip(mb, top, bot, func(k: float, _e: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, 0.35 + 0.3 * absf(k - 0.5)))
	# Shield arm, mostly hidden behind the shield.
	mb.tube([Vector3(-0.42, 1.38, 0.04), Vector3(-0.5, 1.12, -0.04), Vector3(-0.42, 0.98, -0.26), SHIELD_HAND], 0.12, 0.05, 6,
		func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.5))
	return mb.commit()


func _helmet_color(_c: Vector3, ring: int, side: int) -> Color:
	# Face centred on side 11 (see rot below). T-shaped opening: eye slits (ring 3, sides 10 & 12) and the gap
	# between the cheek guards (rings 0-2, side 11) are a dark void; ring 3 side 11 is the nose guard.
	if ring == 3 and (side == 10 or side == 12):
		return ModelsCreatures.VOID
	if ring <= 2 and side == 11:
		return ModelsCreatures.VOID
	if ring >= 4 and ring <= 5:
		return BRONZE.lightened(0.06)
	return BRONZE


func _mesh_helmet() -> Mesh:
	var mb := MeshBuilder.new(63)
	mb.vary = 0.03
	mb.push(Transform3D(Basis.from_scale(Vector3(0.92, 1.0, 1.1)), Vector3.ZERO))
	var prof := [
		Vector3(0.16, -0.02, 0.03), Vector3(0.176, 0.06, 0.015), Vector3(0.188, 0.13, 0.0), Vector3(0.195, 0.19, 0.0),
		Vector3(0.196, 0.25, 0.0), Vector3(0.188, 0.3, 0.0), Vector3(0.17, 0.36, 0.0), Vector3(0.13, 0.42, 0.01),
		Vector3(0.07, 0.455, 0.02), Vector3(0.0, 0.468, 0.02),
	]
	mb.lathe(prof, 16, _helmet_color, PI / 16.0)
	# Brow ridge and nose guard.
	var prev := Vector3.ZERO
	for i in 9:
		var a := lerpf(-1.15, 1.15, float(i) / 8.0) - PI * 0.5
		var p := Vector3(cos(a) * 0.203, 0.258, sin(a) * 0.203)
		if i > 0:
			mb.limb(prev, p, 0.016, 0.016, 4, BRONZE_EDGE)
		prev = p
	mb.box(Vector3(0, 0.215, -0.2), Vector3(0.035, 0.1, 0.03), BRONZE_EDGE)
	# Two slanted eyes glowing in the eye slits; nothing below them.
	for sx in [-1.0, 1.0]:
		ModelsCreatures.eye(mb, Vector3(0.067 * sx, 0.219, -0.2), 0.03, sx, 0.32, glow, 0.4, -0.38 * sx)
	# Neck guard flaring out at the back.
	var a0: Array = []
	var a1: Array = []
	for i in 7:
		var a := lerpf(0.35, PI - 0.35, float(i) / 6.0)
		a0.append(Vector3(cos(a) * 0.165, -0.0, sin(a) * 0.165 + 0.03))
		a1.append(Vector3(cos(a) * 0.215, -0.08, sin(a) * 0.215 + 0.05))
	ModelsCreatures.strip(mb, a0, a1, BRONZE_DARK)
	mb.pop()
	# Crest of night: a fan from brow to nape, and a tail hanging down the back.
	var n := 12
	var w := 0.035
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	for i in n + 1:
		var k := float(i) / float(n)
		var ang := lerpf(-0.85, 1.55, k)
		var h := 0.06 + sin(pow(k, 0.85) * PI) * 0.2
		var dir := Vector3(0, cos(ang), sin(ang))
		var pin := Vector3(0, 0.21, 0.0) + dir * 0.255
		var pout := Vector3(0, 0.21, 0.0) + dir * (0.255 + h)
		if i > 0:
			var cl := CREST if i % 2 == 0 else CREST.lightened(0.05)
			var o := Vector3(w, 0, 0)
			mb.quad(prev_in + o, pin + o, pout + o, prev_out + o, cl)
			mb.quad(prev_in - o, prev_out - o, pout - o, pin - o, cl)
			mb.quad(prev_out + o, pout + o, pout - o, prev_out - o, CREST_EDGE)
		prev_in = pin
		prev_out = pout
	# Horsehair tail spilling from the end of the crest down the nape.
	var tl: Array = []
	var tr: Array = []
	for i in 5:
		var k := float(i) / 4.0
		var c := Vector3(0, 0.2 - k * 0.3, 0.27 + sin(k * 1.4) * 0.07)
		var hw := lerpf(0.045, 0.012, k)
		tl.append(c + Vector3(-hw, 0, 0))
		tr.append(c + Vector3(hw, 0, 0))
	ModelsCreatures.strip(mb, tl, tr, func(k: float, _e: float) -> Color: return CREST.lerp(ModelsCreatures.BODY_LOW, k * 0.5))
	return mb.commit()


func _shield_point(rho: float, th: float) -> Vector3:
	# Tall Boeotian oval with the two side notches, convex toward -Z.
	var notch := 1.0 - 0.2 * (exp(-pow(angle_difference(th, 0.0) / 0.3, 2.0)) + exp(-pow(angle_difference(th, PI) / 0.3, 2.0))) * smooth(rho * 1.4 - 0.3)
	return Vector3(cos(th) * 0.42 * rho * notch, sin(th) * 0.64 * rho, -0.015 - 0.13 * (1.0 - rho * rho))


func _mesh_shield() -> Mesh:
	var mb := MeshBuilder.new(65)
	mb.vary = 0.025
	var rings := [0.0, 0.42, 0.74, 0.9, 1.0]
	var sides := 24
	for j in rings.size() - 1:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var col := BRONZE_EDGE.darkened(0.2) if j == rings.size() - 2 else SHIELD_FACE.lerp(ModelsCreatures.BODY_LOW, float(j) * 0.25)
			var p00 := _shield_point(rings[j], a0)
			var p01 := _shield_point(rings[j], a1)
			var p10 := _shield_point(rings[j + 1], a0)
			var p11 := _shield_point(rings[j + 1], a1)
			# Front faces -Z: wind so the normal points toward the viewer in front.
			if j == 0:
				mb.tri(p00, p11, p10, col)
			else:
				mb.quad(p00, p01, p11, p10, col)
	# Back and rim.
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var f0 := _shield_point(1.0, a0)
		var f1 := _shield_point(1.0, a1)
		var b0 := Vector3(f0.x, f0.y, 0.025)
		var b1 := Vector3(f1.x, f1.y, 0.025)
		mb.quad(f0, f1, b1, b0, BRONZE_EDGE.darkened(0.35))
		mb.tri(Vector3(0, 0, 0.025), b0, b1, BRONZE_DARK)
	# Grip bar on the back.
	mb.box(Vector3(0, 0.0, 0.05), Vector3(0.3, 0.05, 0.05), BRONZE_DARK)
	# Silver crescent of Nyx and its star.
	ModelsCreatures.crescent_flat(mb, Vector3(0.02, 0.05, -0.135), 0.19, 0.075, 0.025, ModelsCreatures.SILVER, 14, -0.35)
	mb.push(Transform3D(Basis.IDENTITY, Vector3(0.1, 0.1, -0.143)))
	mb.quad(Vector3(0, -0.05, 0), Vector3(0.022, 0, 0), Vector3(0, 0.05, 0), Vector3(-0.022, 0, 0), ModelsCreatures.SILVER)
	mb.quad(Vector3(-0.04, 0, 0.002), Vector3(0, -0.018, 0.002), Vector3(0.04, 0, 0.002), Vector3(0, 0.018, 0.002), ModelsCreatures.SILVER)
	mb.pop()
	return mb.commit()


func _mesh_arm() -> Mesh:
	var mb := MeshBuilder.new(67)
	mb.tube([Vector3(0, 0.05, 0), Vector3(0.06, -0.2, -0.02), Vector3(0.07, -0.42, -0.08), Vector3(0.04, -0.58, -0.16)], 0.13, 0.05, 7,
		func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.6))
	# Broken spear in the fist: shaft forward and slightly down, bronze leaf head, splintered butt.
	var hand := Vector3(0.04, -0.58, -0.16)
	var d := Vector3(0, -0.45, -1.0).normalized()
	var head0 := hand + d * 0.9
	mb.limb(hand - d * 0.42, head0, 0.024, 0.022, 5, SHAFT)
	mb.limb(head0, head0 + d * 0.06, 0.026, 0.05, 4, TIP.darkened(0.3))
	mb.limb(head0 + d * 0.06, head0 + d * 0.3, 0.05, 0.0, 4, TIP)
	var butt := hand - d * 0.42
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var off := Vector3(cos(a), 0, sin(a)).cross(d).normalized() * 0.012
		mb.limb(butt + off, butt - d * (0.05 + 0.03 * float(i % 2)) + off * 0.4, 0.012, 0.0, 3, SHAFT)
	return mb.commit()


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack":
			return 1.1
		"hit":
			return 0.3
		"death":
			return 0.8
		"spawn":
			return 1.1
	return 0.4


func _animate(delta: float) -> void:
	var mv := clampf(speed / speed_max, 0.0, 1.0)
	_sway = lerpf(_sway, mv, 1.0 - exp(-delta * 2.5))
	# Heavy, slow float with a marching roll.
	var step := t * 3.2 + _seed
	var bob := sin(t * 1.6 + _seed) * 0.035 + absf(sin(step)) * 0.03 * _sway
	var pos := Vector3(0, BODY_Y + bob, 0)
	var rot := Vector3(-0.13 * _sway + sin(t * 0.9) * 0.02, sin(t * 0.5 + _seed) * 0.04, sin(step) * 0.035 * _sway + sin(t * 1.1) * 0.015)
	var sh_pos := Vector3(-0.16, 0.98 + sin(t * 1.6 + 0.6) * 0.012, -0.47)
	var sh_rot := Vector3(0.04 * _sway, 0.1, sin(t * 1.2) * 0.02)
	var arm_pos := Vector3(0.43, 1.38, 0.0)
	var arm_rot := Vector3(0.25 + sin(t * 1.6 + 1.0) * 0.05 - 0.1 * _sway + sin(step) * 0.06 * _sway, 0.0, 0.1)
	var helm_pos := Vector3(0, 1.6, 0)
	var helm_rot := Vector3(sin(t * 0.9 + 0.5) * 0.03, sin(t * 0.37 + _seed) * 0.06, 0.0)
	if action != "":
		var p := ap()
		match action:
			"attack":
				# Brace (0-.28), shield shove (.28-.42), spear jab over the shield (.45-.56), recover.
				var a := smooth(p / 0.28) * (1.0 - smooth((p - 0.3) / 0.1))
				var shove := smooth((p - 0.27) / 0.13) * (1.0 - smooth((p - 0.62) / 0.3))
				var jab := smooth((p - 0.44) / 0.1) * (1.0 - smooth((p - 0.66) / 0.28))
				var cock := smooth((p - 0.12) / 0.26) * (1.0 - smooth((p - 0.44) / 0.08))
				pos += Vector3(0, 0.06 * a, 0.12 * a - 0.42 * shove)
				rot.x += 0.16 * a - 0.2 * shove
				rot.y += -0.12 * a + 0.1 * shove - 0.12 * jab
				# The shield stays on its grip (the hand is part of the body): the lunge of the body carries it, the
				# arm only adds a short punch and a twist.
				sh_pos += Vector3(0.02 * shove, 0.03 * shove + 0.02 * a, -0.06 * shove)
				sh_rot += Vector3(-0.12 * shove, 0.12 * shove, 0)
				arm_rot.x += -0.6 * cock + 0.15 * jab
				arm_pos += Vector3(-0.03 * jab + 0.03 * cock, 0.16 * cock + 0.05 * jab, 0.18 * cock - 0.55 * jab)
				_mark("impact", 0.58)
			"hit":
				var k := sin(p * PI)
				pos.z += 0.16 * k
				rot.x += 0.12 * k
				sh_rot.z += sin(p * 30.0) * 0.06 * (1.0 - p)
				helm_rot.x -= 0.12 * k
			"death":
				# The shade sags and drifts back; the helmet falls from it.
				var e := ease_in(p)
				pos += Vector3(0, -0.45 * p, 0.25 * p)
				rot.x += 0.35 * smooth(p)
				helm_pos += Vector3(0.2 * p, -1.1 * e, 0.06 * p)
				helm_rot += Vector3(-1.1 * e, 0.4 * p, 0.5 * e)
				# The shield sags forward on its grip as the shade loses its shape.
				sh_pos += Vector3(0.0, -0.06 * e, -0.04 * p)
				sh_rot += Vector3(-0.3 * e, 0.0, 0.15 * e)
				arm_rot.x -= 0.4 * p
			"spawn":
				var e := smooth(p)
				pos.y -= (1.0 - e) * 1.7
				rot.x += 0.25 * (1.0 - e)
	_body.position = pos
	_body.rotation = rot
	_shield.position = sh_pos
	_shield.rotation = sh_rot
	_arm.position = arm_pos
	_arm.rotation = arm_rot
	_helmet.position = helm_pos
	_helmet.rotation = helm_rot
