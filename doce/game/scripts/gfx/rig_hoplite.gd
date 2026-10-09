class_name RigHoplite
extends Rig
## Allied hoplite of Delos: closed Corinthian helmet (no face), horsehair crest, bronze cuirass, white
## pteruges, cape, aspis shield and a long spear. `soldier` variant = blue crest, smaller.

const SKIN := Color("C89B76")
const SKIN_DARK := Color("A87C5C")

var crest_color := Pal.CREST
var cape_color := Pal.CLOTH_RED
var shield_face := Pal.AEGEAN
var emblem := Pal.GOLD
var soldier := false
var _lean := 0.0
var _cape_lift := 0.0
var _run_phase := 0.0
var _yaw_twist := 0.0


func _init(is_soldier: bool = true) -> void:
	super()
	soldier = is_soldier
	if soldier:
		crest_color = Pal.AEGEAN_LIGHT
		cape_color = Pal.AEGEAN
		shield_face = Pal.CLOTH
		emblem = Pal.AEGEAN


func _ready() -> void:
	_build()


func _build() -> void:
	var body := add_part("body", null)
	add_part("hips", _mesh_hips(), "body", Vector3(0, 0.86, 0))
	add_part("leg_l", _mesh_leg(), "hips", Vector3(-0.13, 0.0, 0))
	add_part("leg_r", _mesh_leg(), "hips", Vector3(0.13, 0.0, 0))
	add_part("torso", _mesh_torso(), "hips", Vector3(0, 0.1, 0))
	add_part("head", _mesh_helmet(), "torso", Vector3(0, 0.6, 0))
	add_part("cape", _mesh_cape(), "torso", Vector3(0, 0.5, 0.2))
	add_part("arm_r", _mesh_arm(true), "torso", Vector3(0.39, 0.44, 0))
	add_part("spear", _mesh_spear(), "arm_r", Vector3(0.0, -0.3, -0.27))
	add_part("arm_l", _mesh_arm(false), "torso", Vector3(-0.39, 0.44, 0))
	add_part("shield", _mesh_shield(), "arm_l", Vector3(-0.06, -0.3, -0.26))
	body.position = Vector3.ZERO
	if soldier:
		scale = Vector3.ONE * 0.86


# --- meshes ------------------------------------------------------------------------------------------------

func _mesh_leg() -> Mesh:
	var mb := MeshBuilder.new(3)
	mb.limb(Vector3(0, 0.02, 0), Vector3(0, -0.42, 0), 0.115, 0.09, 6, SKIN)
	mb.limb(Vector3(0, -0.40, 0), Vector3(0, -0.80, 0), 0.098, 0.075, 6, Pal.BRONZE)
	mb.box(Vector3(0, -0.83, -0.05), Vector3(0.13, 0.07, 0.25), Pal.WOOD_DARK)
	return mb.commit()


func _mesh_hips() -> Mesh:
	var mb := MeshBuilder.new(5)
	# Pteruges: strips of white linen with a red hem.
	var sides := 12
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var c := Pal.CLOTH if i % 2 == 0 else Pal.CLOTH.darkened(0.08)
		var b0 := Vector3(cos(a0), 0, sin(a0))
		var b1 := Vector3(cos(a1), 0, sin(a1))
		var y0 := -0.26
		var y1 := 0.1
		mb.quad(b0 * 0.33 + Vector3(0, y0, 0), b0 * 0.27 + Vector3(0, y1, 0), b1 * 0.27 + Vector3(0, y1, 0), b1 * 0.33 + Vector3(0, y0, 0), c)
		mb.quad(b0 * 0.335 + Vector3(0, y0 - 0.05, 0), b0 * 0.33 + Vector3(0, y0, 0), b1 * 0.33 + Vector3(0, y0, 0), b1 * 0.335 + Vector3(0, y0 - 0.05, 0), cape_color)
	mb.cyl(Vector3(0, 0.04, 0), 0.08, 0.29, 0.29, 10, Pal.WOOD_DARK)
	return mb.commit()


func _mesh_torso() -> Mesh:
	var mb := MeshBuilder.new(7)
	mb.vary = 0.02
	# Muscle cuirass.
	mb.cyl(Vector3(0, 0.0, 0), 0.3, 0.27, 0.33, 8, Pal.BRONZE, true, PI / 8.0)
	mb.cyl(Vector3(0, 0.3, 0), 0.24, 0.33, 0.30, 8, Pal.BRONZE, true, PI / 8.0, Pal.BRONZE_DARK)
	# Pectoral plates hint.
	mb.box(Vector3(0.1, 0.36, -0.3), Vector3(0.16, 0.12, 0.04), Pal.BRONZE.lightened(0.12))
	mb.box(Vector3(-0.1, 0.36, -0.3), Vector3(0.16, 0.12, 0.04), Pal.BRONZE.lightened(0.12))
	# Linen shoulder guards.
	mb.push(Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.24, 0.52, 0.0)))
	mb.box(Vector3.ZERO, Vector3(0.17, 0.06, 0.26), Pal.CLOTH.darkened(0.05))
	mb.pop()
	mb.push(Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-0.24, 0.52, 0.0)))
	mb.box(Vector3.ZERO, Vector3(0.17, 0.06, 0.26), Pal.CLOTH.darkened(0.05))
	mb.pop()
	# Neck.
	mb.cyl(Vector3(0, 0.52, 0), 0.12, 0.09, 0.085, 6, SKIN_DARK)
	return mb.commit()


func _mesh_helmet() -> Mesh:
	var mb := MeshBuilder.new(9)
	mb.vary = 0.025
	mb.push(Transform3D(Basis.from_scale(Vector3.ONE * 1.2), Vector3(0, -0.02, 0)))
	# Closed Corinthian helmet.
	mb.sphere(Vector3(0, 0.17, 0.0), 0.215, Pal.BRONZE, 10, 7, Vector3(0.95, 1.16, 1.06))
	# Neck guard flare.
	mb.cyl(Vector3(0, -0.02, 0.03), 0.1, 0.21, 0.18, 10, Pal.BRONZE_DARK)
	# The face is a dark opening: two eye slits and the vertical gap, split by the nose guard.
	mb.box(Vector3(0.075, 0.2, -0.205), Vector3(0.085, 0.04, 0.05), Pal.SKIN_SHADOW)
	mb.box(Vector3(-0.075, 0.2, -0.205), Vector3(0.085, 0.04, 0.05), Pal.SKIN_SHADOW)
	mb.box(Vector3(0, 0.08, -0.215), Vector3(0.055, 0.15, 0.05), Pal.SKIN_SHADOW)
	# Brow ridge.
	mb.box(Vector3(0, 0.245, -0.2), Vector3(0.3, 0.035, 0.07), Pal.BRONZE.lightened(0.1))
	# Crest holder and horsehair crest: a continuous fan from brow to nape.
	mb.box(Vector3(0, 0.39, 0.02), Vector3(0.05, 0.05, 0.36), Pal.BRONZE_DARK)
	var n := 12
	var w := 0.045
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	for i in n + 1:
		var k := float(i) / float(n)
		var ang := lerpf(-1.0, 1.3, k)
		var h := 0.07 + sin(pow(k, 0.8) * PI) * 0.2
		var dir := Vector3(0, cos(ang), sin(ang))
		var pin := Vector3(0, 0.17, 0) + dir * 0.235
		var pout := Vector3(0, 0.17, 0) + dir * (0.235 + h)
		if i > 0:
			var cl := crest_color if i % 2 == 0 else crest_color.darkened(0.1)
			var o := Vector3(w, 0, 0)
			mb.quad(prev_in + o, pin + o, pout + o, prev_out + o, cl)
			mb.quad(prev_in - o, prev_out - o, pout - o, pin - o, cl)
			mb.quad(prev_out + o, pout + o, pout - o, prev_out - o, cl.lightened(0.06))
		prev_in = pin
		prev_out = pout
	# Tail of the crest hanging at the back.
	mb.push(Transform3D(Basis(Vector3.RIGHT, 2.3), Vector3(0, 0.1, 0.27)))
	mb.box(Vector3(0, 0.1, 0), Vector3(0.08, 0.24, 0.05), crest_color.darkened(0.12))
	mb.pop()
	mb.pop()
	return mb.commit()


func _mesh_cape() -> Mesh:
	var mb := MeshBuilder.new(11)
	var c := cape_color
	var top_w := 0.28
	var bot_w := 0.38
	var l := 0.95
	# Two panels with a slight fold, hanging along -Y, slightly behind (+Z).
	var p := [Vector3(-top_w, 0, 0), Vector3(0, 0, 0.04), Vector3(top_w, 0, 0)]
	var q := [Vector3(-bot_w, -l, 0.08), Vector3(0, -l * 1.02, 0.16), Vector3(bot_w, -l, 0.08)]
	for i in 2:
		mb.quad(q[i], q[i + 1], p[i + 1], p[i], c)
		mb.quad(p[i], p[i + 1], q[i + 1], q[i], c.darkened(0.25))
	return mb.commit()


func _mesh_arm(right: bool) -> Mesh:
	var mb := MeshBuilder.new(13)
	var s := 1.0 if right else -1.0
	mb.ico(Vector3(0.02 * s, 0.02, 0), 0.11, Pal.BRONZE, 0, 0.0, Vector3(1.0, 0.8, 1.0))
	mb.limb(Vector3(0, 0, 0), Vector3(0, -0.3, 0), 0.08, 0.07, 6, SKIN)
	mb.limb(Vector3(0, -0.3, 0), Vector3(0, -0.3, -0.24), 0.07, 0.06, 6, SKIN)
	mb.limb(Vector3(0, -0.3, -0.08), Vector3(0, -0.3, -0.2), 0.078, 0.07, 6, Pal.WOOD_DARK)
	mb.ico(Vector3(0, -0.3, -0.27), 0.06, SKIN_DARK, 0)
	return mb.commit()


func _mesh_spear() -> Mesh:
	var mb := MeshBuilder.new(15)
	# Held at the hand; shaft along -Z (forward).
	mb.limb(Vector3(0, 0, 0.95), Vector3(0, 0, -1.45), 0.028, 0.026, 5, Pal.WOOD_LIGHT)
	# Leaf-shaped bronze head.
	mb.limb(Vector3(0, 0, -1.42), Vector3(0, 0, -1.58), 0.03, 0.06, 4, Pal.BRONZE)
	mb.limb(Vector3(0, 0, -1.58), Vector3(0, 0, -1.86), 0.06, 0.0, 4, Pal.BRONZE.lightened(0.15))
	# Butt spike (sauroter).
	mb.limb(Vector3(0, 0, 0.95), Vector3(0, 0, 1.08), 0.03, 0.0, 4, Pal.BRONZE_DARK)
	return mb.commit()


func _mesh_shield() -> Mesh:
	var mb := MeshBuilder.new(17)
	# Round aspis facing -Z: build it facing +Y then tip it over.
	mb.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	var r := 0.5
	mb.cyl(Vector3(0, -0.06, 0), 0.06, r * 0.97, r, 16, Pal.BRONZE_DARK)
	mb.cyl(Vector3(0, 0.0, 0), 0.03, r * 0.9, r * 0.82, 16, shield_face)
	mb.ring(Vector3(0, 0.0, 0), r, r * 0.88, 0.05, 16, Pal.BRONZE)
	# Sun emblem: disc with rays.
	mb.cyl(Vector3(0, 0.03, 0), 0.025, 0.14, 0.13, 10, emblem)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x)
		mb.quad(d * 0.17 + side * 0.035 + Vector3(0, 0.035, 0), d * 0.17 - side * 0.035 + Vector3(0, 0.035, 0), d * 0.3 + Vector3(0, 0.035, 0), d * 0.3 + Vector3(0, 0.035, 0) + side * 0.001, emblem)
	mb.pop()
	return mb.commit()


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack1", "attack2":
			return 0.34
		"attack3":
			return 0.52
		"bash":
			return 0.42
		"dodge":
			return 0.38
		"hit":
			return 0.28
		"death":
			return 1.2
		"cast":
			return 0.9
		"cheer":
			return 1.2
		"build":
			return 0.35
	return 0.4


func _animate(delta: float) -> void:
	var body: Node3D = parts["body"]
	var hips: Node3D = parts["hips"]
	var torso: Node3D = parts["torso"]
	var head: Node3D = parts["head"]
	var leg_l: Node3D = parts["leg_l"]
	var leg_r: Node3D = parts["leg_r"]
	var arm_r: Node3D = parts["arm_r"]
	var arm_l: Node3D = parts["arm_l"]
	var spear: Node3D = parts["spear"]
	var shield: Node3D = parts["shield"]
	var cape: Node3D = parts["cape"]

	var mv := clampf(speed / speed_max, 0.0, 1.2)
	_run_phase += delta * (4.0 + 7.5 * mv) * (1.0 if mv > 0.05 else 0.0)
	var s := sin(_run_phase)
	var c := cos(_run_phase)
	var breath := sin(t * 2.2)

	# Base pose (idle / run).
	var bob := absf(s) * 0.07 * mv
	body.position = Vector3(0, bob - 0.02 * mv, 0)
	body.rotation = Vector3.ZERO
	_lean = lerpf(_lean, -0.16 * mv, 1.0 - exp(-delta * 8.0))
	hips.rotation = Vector3(0, s * 0.12 * mv, 0)
	torso.rotation = Vector3(_lean + breath * 0.012, -s * 0.18 * mv, 0)
	torso.scale = Vector3.ONE * (1.0 + breath * 0.008)
	head.rotation = Vector3(-_lean * 0.5, 0, 0)
	leg_l.rotation = Vector3(s * 0.75 * mv, 0, 0)
	leg_r.rotation = Vector3(-s * 0.75 * mv, 0, 0)
	# Spear arm: hoplite rest pose, spear pointing up-forward.
	arm_r.rotation = Vector3(0.15 - s * 0.25 * mv, 0, 0.08)
	spear.rotation = Vector3(deg_to_rad(62.0) - 0.1 * mv, 0, 0)
	spear.position = Vector3(0.0, -0.3, -0.27)
	# Shield arm: shield held in front-left.
	arm_l.rotation = Vector3(0.25 + s * 0.15 * mv, 0.3, -0.05)
	shield.rotation = Vector3(0, -0.45, 0)
	_cape_lift = lerpf(_cape_lift, 0.15 + 0.75 * mv, 1.0 - exp(-delta * 4.0))
	cape.rotation = Vector3(_cape_lift + sin(t * 3.1) * 0.05 + c * 0.06 * mv, 0, sin(t * 1.7) * 0.04)

	if action == "":
		return
	var p := ap()
	match action:
		"attack1", "attack2":
			var k := strike_curve(p, 0.25, 0.5)
			var hi := 0.0 if action == "attack1" else 0.12
			torso.rotation.y += -0.35 * k
			torso.rotation.x += 0.12 * k
			arm_r.rotation = Rig.lerp_angle_v(arm_r.rotation, Vector3(1.45 - hi, -0.25, 0.1), clampf(absf(k) * 1.4, 0.0, 1.0))
			spear.rotation = Rig.lerp_angle_v(spear.rotation, Vector3(-1.35 + hi, 0.1, 0), clampf(absf(k) * 1.6, 0.0, 1.0))
			spear.position.z = -0.27 - maxf(k, 0.0) * 0.5
			body.position.z = -maxf(k, 0.0) * 0.12
			leg_r.rotation.x = -0.5 * maxf(k, 0.0)
			leg_l.rotation.x = 0.4 * maxf(k, 0.0)
			_mark("impact", 0.38)
		"attack3":
			# Wide sweep: wind up to the right, sweep across to the left.
			var w: float
			if p < 0.22:
				w = -smooth(p / 0.22)
			elif p < 0.55:
				w = lerpf(-1.0, 1.0, ease_out((p - 0.22) / 0.33))
			else:
				w = lerpf(1.0, 0.0, smooth((p - 0.55) / 0.45))
			torso.rotation.y = w * 1.2
			torso.rotation.x = 0.15 * absf(w)
			hips.rotation.y = w * 0.4
			arm_r.rotation = Vector3(1.5, 0.2, 0.9)
			spear.rotation = Vector3(-1.5, 0.0, 0.0)
			spear.position.z = -0.45
			body.position.y = -0.08 * absf(w)
			leg_l.rotation.x = 0.35
			leg_r.rotation.x = -0.35
			_mark("impact", 0.36)
		"bash":
			var k := strike_curve(p, 0.3, 0.5)
			arm_l.rotation = Rig.lerp_angle_v(arm_l.rotation, Vector3(1.4, 0.0, 0.0), clampf(absf(k) * 1.4, 0.0, 1.0))
			shield.rotation = Rig.lerp_angle_v(shield.rotation, Vector3(-1.3, -0.1, 0), clampf(absf(k) * 1.4, 0.0, 1.0))
			torso.rotation.y += 0.45 * k
			torso.rotation.x += 0.2 * maxf(k, 0.0)
			body.position.z = -maxf(k, 0.0) * 0.25
			leg_l.rotation.x = -0.55 * maxf(k, 0.0)
			leg_r.rotation.x = 0.45 * maxf(k, 0.0)
			_mark("impact", 0.42)
		"dodge":
			# Forward roll around the waist.
			var rp := smooth(p)
			body.rotation.x = -rp * TAU
			body.position.y = 0.45 * sin(p * PI) * 0.6 - 0.25 * sin(p * PI)
			var tuck := sin(p * PI)
			leg_l.rotation.x = -1.4 * tuck
			leg_r.rotation.x = -1.2 * tuck
			torso.rotation.x = 0.6 * tuck
			arm_r.rotation.x = 0.4 + 0.6 * tuck
			spear.rotation.x = deg_to_rad(62.0) - 1.1 * tuck
			cape.rotation.x = 0.4
		"hit":
			var k := sin(p * PI)
			torso.rotation.x -= 0.35 * k
			head.rotation.x -= 0.3 * k
			body.position.z = 0.1 * k
		"death":
			var k := smooth(minf(p / 0.55, 1.0))
			body.rotation = Vector3(0, 0, -k * 1.45)
			body.position = Vector3(-k * 0.5, -k * 0.35, 0)
			arm_r.rotation.x = -0.3
			spear.rotation.x = 0.2 * k
			torso.rotation.x = -0.2 * k
		"cast":
			# Raise the spear to the sky, then drive it into the ground.
			if p < 0.55:
				var k := smooth(p / 0.55)
				arm_r.rotation = Vector3(lerpf(0.15, 2.9, k), 0, 0.15)
				spear.rotation = Vector3(lerpf(1.08, 1.6, k), 0, 0)
				torso.rotation.x = -0.15 * k
				head.rotation.x = -0.35 * k
			else:
				var k := ease_out((p - 0.55) / 0.2) if p < 0.75 else 1.0
				arm_r.rotation = Vector3(lerpf(2.9, 0.9, k), 0, 0.15)
				spear.rotation = Vector3(lerpf(1.6, -1.2, k), 0, 0)
				torso.rotation.x = 0.25 * k
				body.position.y = -0.12 * k
			_mark("impact", 0.68)
		"cheer":
			var k := sin(minf(p * 1.5, 1.0) * PI * 0.5)
			arm_r.rotation = Vector3(2.6 * k + 0.15 * (1.0 - k), 0, 0.2)
			spear.rotation = Vector3(1.55, 0, 0)
			body.position.y += absf(sin(p * TAU * 2.0)) * 0.08
		"build":
			var k := sin(p * PI)
			torso.rotation.x += 0.25 * k
			arm_l.rotation.x += 0.4 * k
