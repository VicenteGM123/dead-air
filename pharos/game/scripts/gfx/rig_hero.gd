class_name RigHero
extends Rig
## FANÓS, the automaton of the lighthouse. Forged by Hephaestus to tend the Pharos of Delos; Hestia placed the
## last spark of her eternal flame in his head. A stocky bronze guardian with verdigris patina, a lighthouse
## lantern for a head (the flame is his face), a weathered sail for a sash, a bronze anchor for a weapon and a
## lighthouse lens for a shield.

const BRONZE := Color("C48A3C")
const BRONZE_DARK := Color("8E5F2A")
const BRONZE_LIGHT := Color("E2B064")
const PATINA := Color("5FB5A2")
const PATINA_DARK := Color("3C8577")
const GOLD := Color("F0C45A")
const GLASS := Color(1.0, 0.8, 0.45, 0.5) # self-lit amber panes
const LENS := Color(0.62, 0.47, 0.3, 0.5)
const SAIL := Color("2F6DAE")
const SAIL_DARK := Color("24578C")
const SAIL_STRIPE := Color("F1EBDD")
const ROPE := Color("D6BE88")
const SASH_SEGS := 6
const SASH_LEN := 0.13

var flame: Node3D
var head_glow: MeshInstance3D
var lens_glow: MeshInstance3D
var beam: Node3D
var flame_power := 1.0 # 1 healthy .. 0 extinguished (driven by gameplay)
var lit := true
var _lean := 0.0
var _run_phase := 0.0
var _idle_t := 0.0
var _steam_t := 0.0
var _sash: MeshInstance3D
var _im: ImmediateMesh
var _tails: Array = [[], []]
var _prev_root := Vector3.ZERO
var _flame_meshes: Array[MeshInstance3D] = []
var _flame_k := 1.0
var _beam_k := 0.0
var _lens_flash := 0.0
## Shoulder carry of the anchor (validated by tools/clip_check.gd: no part may pass through the body).
var carry_arm := Vector3(1.3, 0.0, 0.45)
var carry_anchor := Vector3(-3.4, 0.0, 0.9)
## Waypoint used when the anchor leaves the shoulder to be planted or dropped (collision-free path).
const MID_ARM := Vector3(0.4, 0.0, 0.8)
const MID_ANCHOR := Vector3(-1.6, 0.0, 1.0)


func _ready() -> void:
	add_part("body", null)
	add_part("hips", _mesh_hips(), "body", Vector3(0, 0.82, 0))
	add_part("leg_l", _mesh_leg(), "hips", Vector3(-0.15, 0.0, 0))
	add_part("leg_r", _mesh_leg(), "hips", Vector3(0.15, 0.0, 0))
	add_part("torso", _mesh_torso(), "hips", Vector3(0, 0.08, 0))
	add_part("head", _mesh_lantern(), "torso", Vector3(0, 0.6, 0))
	add_part("arm_r", _mesh_arm(1.0), "torso", Vector3(0.45, 0.46, 0))
	add_part("anchor", _mesh_anchor(), "arm_r", Vector3(0.0, -0.34, -0.36))
	add_part("arm_l", _mesh_arm(-1.0), "torso", Vector3(-0.45, 0.46, 0))
	add_part("shield", _mesh_lens(), "arm_l", Vector3(0.0, -0.32, -0.55))
	# Hestia's flame inside the lantern.
	flame = Node3D.new()
	flame.position = Vector3(0, 0.17, 0)
	parts["head"].add_child(flame)
	for i in 2:
		var f := MeshInstance3D.new()
		f.mesh = _flame_mesh(i)
		f.material_override = Materials.lowpoly()
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.add_child(f)
		_flame_meshes.append(f)
	head_glow = _glow_quad(parts["head"], Vector3(0, 0.3, 0), 1.6, Vector3(1.0, 0.7, 0.36))
	lens_glow = _glow_quad(parts["shield"], Vector3(0, 0, -0.08), 1.0, Vector3(1.0, 0.85, 0.55))
	# The lighthouse beam (special power): two crossed additive quads out of the lantern.
	beam = Node3D.new()
	beam.position = Vector3(0, 0.3, 0)
	parts["head"].add_child(beam)
	var cone := MeshInstance3D.new()
	cone.mesh = Materials.cone_mesh(11.0, 0.18, 2.4, 12)
	cone.material_override = Materials.beam_cone(11.0, Color(1.0, 0.82, 0.55))
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The beam shoots forward (-Z) out of the lantern, slightly downwards.
	cone.rotation = Vector3(0.12, PI, 0)
	beam.add_child(cone)
	beam.visible = false
	# Sail sash (rebuilt every frame).
	_im = ImmediateMesh.new()
	_sash = MeshInstance3D.new()
	_sash.mesh = _im
	_sash.material_override = Materials.lowpoly()
	_sash.top_level = true
	add_child(_sash)
	meshes.append(_sash)
	for tail in 2:
		for i in SASH_SEGS + 1:
			_tails[tail].append(Vector3.ZERO)


func _glow_quad(parent: Node3D, pos: Vector3, size: float, tint: Vector3) -> MeshInstance3D:
	var g := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	g.mesh = qm
	g.material_override = Materials.glow_add()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = pos
	g.set_instance_shader_parameter("tint_color", tint)
	parent.add_child(g)
	return g


# --- meshes ------------------------------------------------------------------------------------------------

func _mesh_leg() -> Mesh:
	var mb := MeshBuilder.new(3)
	mb.vary = 0.02
	mb.limb(Vector3(0, 0.04, 0), Vector3(0, -0.36, 0), 0.13, 0.11, 8, BRONZE)
	mb.ico(Vector3(0, -0.4, -0.02), 0.115, PATINA, 0, 0.0, Vector3(1.0, 0.85, 1.0))
	mb.limb(Vector3(0, -0.42, 0), Vector3(0, -0.74, 0), 0.115, 0.095, 8, BRONZE)
	mb.cyl(Vector3(0, -0.56, 0), 0.05, 0.122, 0.118, 8, GOLD)
	# Heavy feet with a toe plate.
	mb.box(Vector3(0, -0.78, -0.05), Vector3(0.2, 0.09, 0.32), BRONZE_DARK)
	mb.box(Vector3(0, -0.76, -0.2), Vector3(0.21, 0.07, 0.08), PATINA_DARK)
	return mb.commit()


func _mesh_hips() -> Mesh:
	var mb := MeshBuilder.new(5)
	# Kilt of bronze plates (metal pteruges), patina at the edges.
	var n := 10
	for i in n:
		var a0 := TAU * (float(i) + 0.06) / n
		var a1 := TAU * (float(i) + 0.94) / n
		var b0 := Vector3(cos(a0), 0, sin(a0))
		var b1 := Vector3(cos(a1), 0, sin(a1))
		var c := BRONZE if i % 2 == 0 else BRONZE_DARK
		mb.quad(b0 * 0.37 + Vector3(0, -0.27, 0), b0 * 0.29 + Vector3(0, 0.06, 0), b1 * 0.29 + Vector3(0, 0.06, 0), b1 * 0.37 + Vector3(0, -0.27, 0), c)
		mb.quad(b1 * 0.37 + Vector3(0, -0.27, 0), b1 * 0.29 + Vector3(0, 0.06, 0), b0 * 0.29 + Vector3(0, 0.06, 0), b0 * 0.37 + Vector3(0, -0.27, 0), c.darkened(0.3))
		mb.quad(b0 * 0.375 + Vector3(0, -0.31, 0), b0 * 0.37 + Vector3(0, -0.27, 0), b1 * 0.37 + Vector3(0, -0.27, 0), b1 * 0.375 + Vector3(0, -0.31, 0), PATINA)
	# Belt with a gold buckle shaped like the sun.
	mb.cyl(Vector3(0, 0.0, 0), 0.1, 0.3, 0.3, 12, BRONZE_DARK)
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.05, -0.3)))
	mb.cyl(Vector3.ZERO, 0.04, 0.075, 0.07, 10, GOLD)
	mb.pop()
	return mb.commit()


func _mesh_torso() -> Mesh:
	var mb := MeshBuilder.new(7)
	mb.vary = 0.02
	# Barrel chest.
	mb.lathe([Vector2(0.28, 0.0), Vector2(0.33, 0.14), Vector2(0.39, 0.33), Vector2(0.37, 0.48), Vector2(0.28, 0.57), Vector2(0.15, 0.62)], 10, BRONZE, PI / 10.0, true, true)
	# Meander band of gold studs around the chest.
	for i in 14:
		var a := TAU * float(i) / 14.0
		var d := Vector3(cos(a), 0, sin(a))
		mb.push(Transform3D(Basis(Vector3.UP, -a), d * 0.345 + Vector3(0, 0.17, 0)))
		mb.box(Vector3.ZERO, Vector3(0.03, 0.05, 0.06), GOLD if i % 2 == 0 else BRONZE_LIGHT)
		mb.pop()
	# Sun emblem on the chest.
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0, 0.35, -0.37)))
	mb.cyl(Vector3.ZERO, 0.04, 0.1, 0.09, 10, GOLD)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.022
		mb.tri(d * 0.1 - side + Vector3(0, 0.03, 0), d * 0.1 + side + Vector3(0, 0.03, 0), d * 0.17 + Vector3(0, 0.02, 0), GOLD)
	mb.pop()
	# Pauldrons with verdigris rims.
	for sx in [-1.0, 1.0]:
		var c := Vector3(0.43 * sx, 0.5, 0.0)
		mb.sphere(c, 0.15, BRONZE_LIGHT, 8, 4, Vector3(1.05, 0.78, 1.15))
		mb.push(Transform3D(Basis(Vector3.BACK, -0.35 * sx), c + Vector3(0.03 * sx, -0.05, 0)))
		mb.ring(Vector3.ZERO, 0.17, 0.13, 0.05, 10, PATINA)
		mb.pop()
	# Back vents for steam.
	for sx in [-1.0, 1.0]:
		mb.limb(Vector3(0.12 * sx, 0.42, 0.3), Vector3(0.13 * sx, 0.5, 0.37), 0.05, 0.055, 6, BRONZE)
	# Sail-cloth strap across the chest (the sash tails hang from the belt).
	mb.push(Transform3D(Basis(Vector3.BACK, 0.62), Vector3(0.02, 0.3, 0.0)))
	mb.cyl(Vector3(0, -0.04, 0), 0.08, 0.36, 0.36, 12, SAIL, false)
	mb.pop()
	return mb.commit()


func _mesh_lantern() -> Mesh:
	var mb := MeshBuilder.new(9)
	mb.vary = 0.02
	# Gear-like neck collar.
	mb.cyl(Vector3(0, -0.04, 0), 0.08, 0.13, 0.12, 10, BRONZE_DARK)
	for i in 8:
		var a := TAU * float(i) / 8.0
		mb.box(Vector3(cos(a) * 0.13, 0.0, sin(a) * 0.13), Vector3(0.04, 0.06, 0.04), BRONZE)
	# Lamp room: base, glass panes, mullions, gallery ring, dome and finial.
	mb.cyl(Vector3(0, 0.04, 0), 0.07, 0.23, 0.24, 8, BRONZE, true, PI / 8.0)
	mb.cyl(Vector3(0, 0.11, 0), 0.3, 0.18, 0.18, 8, GLASS, false, PI / 8.0)
	for i in 8:
		var a := PI / 8.0 + TAU * float(i) / 8.0
		mb.box(Vector3(cos(a) * 0.18, 0.26, sin(a) * 0.18), Vector3(0.035, 0.32, 0.035), BRONZE_DARK)
	mb.cyl(Vector3(0, 0.4, 0), 0.05, 0.25, 0.24, 8, BRONZE, true, PI / 8.0)
	mb.cyl(Vector3(0, 0.45, 0), 0.18, 0.24, 0.05, 8, PATINA, true, PI / 8.0)
	mb.cyl(Vector3(0, 0.62, 0), 0.06, 0.05, 0.03, 6, BRONZE_DARK)
	mb.sphere(Vector3(0, 0.72, 0), 0.05, GOLD, 6, 4)
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.8, 0)))
	mb.ring(Vector3(0, -0.012, 0), 0.06, 0.035, 0.025, 8, GOLD)
	mb.pop()
	return mb.commit()


func _flame_mesh(layer: int) -> Mesh:
	var mb := MeshBuilder.new(21 + layer)
	var col := Color(1.0, 0.62, 0.25, 0.5) if layer == 0 else Color(1.0, 0.95, 0.75, 0.5)
	var r := 0.09 if layer == 0 else 0.05
	var h := 0.24 if layer == 0 else 0.16
	mb.cyl(Vector3(0, -0.05, 0), h, r, 0.0, 6, col, true, 0.3)
	mb.cyl(Vector3(r * 0.45, -0.05, 0.02), h * 0.7, r * 0.55, 0.0, 5, col, true, 1.1)
	mb.cyl(Vector3(-r * 0.4, -0.05, -0.02), h * 0.75, r * 0.5, 0.0, 5, col, true, 2.0)
	return mb.commit()


func _mesh_arm(side: float) -> Mesh:
	var mb := MeshBuilder.new(13)
	mb.vary = 0.02
	mb.limb(Vector3(0, 0.0, 0), Vector3(0, -0.3, 0), 0.105, 0.095, 8, BRONZE)
	mb.ico(Vector3(0, -0.32, 0), 0.1, PATINA, 0, 0.0, Vector3.ONE)
	mb.limb(Vector3(0, -0.32, 0), Vector3(0, -0.32, -0.28), 0.1, 0.09, 8, BRONZE)
	mb.limb(Vector3(0, -0.32, -0.1), Vector3(0, -0.32, -0.22), 0.108, 0.1, 8, GOLD)
	# Big blocky hand.
	mb.box(Vector3(0.0, -0.32, -0.36), Vector3(0.15, 0.16, 0.15), BRONZE_DARK)
	mb.box(Vector3(-0.07 * side, -0.29, -0.33), Vector3(0.05, 0.08, 0.1), BRONZE)
	return mb.commit()


func _mesh_anchor() -> Mesh:
	var mb := MeshBuilder.new(15)
	mb.vary = 0.02
	# Grip at the origin; the shank runs down (-Y) to the crown, the stock and ring sit above the hand.
	mb.limb(Vector3(0, 0.2, 0), Vector3(0, -1.18, 0), 0.05, 0.06, 6, BRONZE_DARK)
	for k in 3:
		mb.cyl(Vector3(0, -0.12 + k * 0.07, 0), 0.05, 0.065, 0.065, 6, ROPE)
	# Stock (crossbar), perpendicular to the arms.
	mb.limb(Vector3(0, 0.13, -0.26), Vector3(0, 0.13, 0.26), 0.05, 0.042, 6, BRONZE)
	mb.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.27, 0)))
	mb.ring(Vector3(0, -0.02, 0), 0.085, 0.05, 0.04, 10, BRONZE_LIGHT)
	mb.pop()
	# Curved arms ending in flukes.
	for sx in [-1.0, 1.0]:
		var pts: Array = []
		for i in 8:
			var a := lerpf(0.0, 1.3, float(i) / 7.0)
			pts.append(Vector3(sin(a) * 0.6 * sx, -1.18 + (1.0 - cos(a)) * 0.6, 0))
		mb.tube(pts, 0.095, 0.06, 7, BRONZE)
		var tip: Vector3 = pts[pts.size() - 1]
		var dir: Vector3 = (tip - pts[pts.size() - 2]).normalized()
		var out := Vector3(sx, 0, 0)
		# Spade-shaped fluke with verdigris.
		var f0 := tip - dir * 0.05
		var f1 := tip + dir * 0.28
		mb.tri(f0 + Vector3(0, 0, -0.14), f1, f0 + Vector3(0, 0, 0.14), PATINA)
		mb.tri(f0 + Vector3(0, 0, 0.14), f1, f0 + Vector3(0, 0, -0.14), PATINA_DARK)
		mb.tri(f0 + Vector3(0, 0, -0.14), f0 + out * 0.08 - dir * 0.1, f1, PATINA)
		mb.tri(f0 + out * 0.08 - dir * 0.1, f0 + Vector3(0, 0, 0.14), f1, PATINA_DARK)
	mb.sphere(Vector3(0, -1.2, 0), 0.11, BRONZE_LIGHT, 6, 4)
	return mb.commit()


func _mesh_lens() -> Mesh:
	var mb := MeshBuilder.new(17)
	# A lighthouse lens: bronze rim, concentric prism rings around a glowing bullseye. Faces -Z.
	mb.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	var r := 0.34
	mb.cyl(Vector3(0, -0.05, 0), 0.05, r, r, 16, BRONZE_DARK)
	mb.ring(Vector3(0, 0.0, 0), r, r * 0.86, 0.06, 16, BRONZE)
	mb.ring(Vector3(0, 0.0, 0), r * 0.84, r * 0.66, 0.035, 16, Color("E9D9B0"))
	mb.ring(Vector3(0, 0.0, 0), r * 0.64, r * 0.6, 0.05, 16, BRONZE_LIGHT)
	mb.ring(Vector3(0, 0.0, 0), r * 0.58, r * 0.4, 0.045, 16, Color("F3E6C2"))
	mb.cyl(Vector3(0, 0.0, 0), 0.07, r * 0.38, r * 0.2, 12, LENS)
	# Bronze brackets in a cross.
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		mb.box(d * r * 0.63 + Vector3(0, 0.05, 0), Vector3(0.06, 0.04, 0.06), BRONZE)
	mb.pop()
	# Grip bracket between the fist and the back of the lens.
	mb.box(Vector3(0.0, 0.0, 0.085), Vector3(0.1, 0.1, 0.05), BRONZE_DARK)
	return mb.commit()


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack1", "attack2":
			return 0.4
		"attack3":
			return 0.62
		"bash":
			return 0.45
		"dodge":
			return 0.34
		"hit":
			return 0.28
		"death":
			return 1.4
		"cast":
			return 1.5
		"cheer":
			return 1.8
		"look":
			return 3.0
		"rest":
			return 3.6
		"relight":
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
	var anchor: Node3D = parts["anchor"]
	var shield: Node3D = parts["shield"]

	var mv := clampf(speed / speed_max, 0.0, 1.2)
	_run_phase += delta * (3.6 + 6.8 * mv) * (1.0 if mv > 0.05 else 0.0)
	var s := sin(_run_phase)
	var breath := sin(t * 1.6)

	# Heavy gait: big vertical bob, stomping legs, shoulders rolling.
	var bob := absf(s) * 0.09 * mv
	body.position = Vector3(0, bob - 0.03 * mv, 0)
	body.rotation = Vector3(0, 0, s * 0.04 * mv)
	_lean = lerpf(_lean, -0.14 * mv, 1.0 - exp(-delta * 7.0))
	hips.rotation = Vector3(0, s * 0.1 * mv, 0)
	torso.rotation = Vector3(_lean + breath * 0.012, -s * 0.16 * mv, -s * 0.03 * mv)
	head.rotation = Vector3(-_lean * 0.4, s * 0.05 * mv, 0)
	leg_l.rotation = Vector3(s * 0.7 * mv, 0, 0)
	leg_r.rotation = Vector3(-s * 0.7 * mv, 0, 0)
	# The anchor rests on the right shoulder, its crown behind like a bronze crescent.
	arm_r.rotation = carry_arm + Vector3(s * 0.06 * mv, 0.0, 0.0)
	anchor.rotation = carry_anchor - Vector3(absf(s) * 0.05 * mv, 0.0, 0.0)
	anchor.position = Vector3(0.0, -0.34, -0.36)
	# Lens-shield held out at the left, clear of the body.
	arm_l.rotation = Vector3(0.4 + s * 0.15 * mv, 0.55, -0.12)
	shield.rotation = Vector3.ZERO

	if mv < 0.05 and action == "":
		_idle_t += delta
		if _idle_t > 6.0 and _idle_t - delta <= 6.0:
			play("look")
		elif _idle_t > 13.0:
			_idle_t = 0.0
			play("rest")
	elif mv >= 0.05:
		_idle_t = 0.0
		if action == "look" or action == "rest":
			action = ""

	_animate_action(body, hips, torso, head, leg_l, leg_r, arm_r, arm_l, anchor, shield)
	_animate_flame(delta, mv)
	_update_sash(delta)


func _animate_flame(delta: float, mv: float) -> void:
	var target := (0.35 + 0.65 * flame_power) if lit else 0.0
	_flame_k = lerpf(_flame_k, target, 1.0 - exp(-delta * 4.0))
	var fl := 1.0 + sin(t * 13.0) * 0.1 + sin(t * 21.0) * 0.07
	if flame_power < 0.35 and lit:
		fl *= 0.7 + 0.3 * absf(sin(t * 9.0)) # sputtering when badly hurt
	for i in _flame_meshes.size():
		var f := _flame_meshes[i]
		var k := maxf(_flame_k * fl, 0.001)
		f.global_basis = Basis(Vector3.UP, t * (2.5 + i)).scaled(Vector3(k, k * (1.0 + 0.3 * i), k))
		f.visible = _flame_k > 0.02
	var night: float = Game.main.tod.night_amount() if Game.main and Game.main.tod else 0.0
	head_glow.set_instance_shader_parameter("intensity", (0.06 + 0.8 * night) * _flame_k * fl + _beam_k * 1.5)
	lens_glow.set_instance_shader_parameter("intensity", (0.0 + 0.25 * night) * _flame_k + _lens_flash * 2.5)
	_lens_flash = maxf(0.0, _lens_flash - delta * 3.0)
	beam.visible = _beam_k > 0.01
	if beam.visible:
		for q in beam.get_children():
			(q as MeshInstance3D).set_instance_shader_parameter("intensity", _beam_k * 3.0)
	# Steam from the back vents while running.
	if Game.fx and is_inside_tree():
		_steam_t -= delta
		if mv > 0.5 and _steam_t <= 0.0:
			_steam_t = 0.32
			var torso: Node3D = parts["torso"]
			Game.fx.smoke(torso.global_transform * Vector3(0.13 * (1.0 if randf() < 0.5 else -1.0), 0.56, 0.44), 1, Color(0.92, 0.92, 0.9))


func _animate_action(body: Node3D, hips: Node3D, torso: Node3D, head: Node3D, leg_l: Node3D, leg_r: Node3D, arm_r: Node3D, arm_l: Node3D, anchor: Node3D, shield: Node3D) -> void:
	if action == "":
		_beam_k = maxf(0.0, _beam_k - 0.08)
		return
	var p := ap()
	match action:
		"attack1", "attack2":
			# Wide horizontal swing of the anchor (right-to-left, then back).
			var dir := 1.0 if action == "attack1" else -1.0
			var w: float
			if p < 0.3:
				w = -smooth(p / 0.3)
			elif p < 0.55:
				w = lerpf(-1.0, 1.0, ease_out((p - 0.3) / 0.25))
			else:
				w = lerpf(1.0, 0.0, smooth((p - 0.55) / 0.45))
			torso.rotation.y = -w * 1.05 * dir
			hips.rotation.y = -w * 0.3 * dir
			var out_k := smooth(minf(p / 0.18, 1.0)) * smooth(minf((1.0 - p) / 0.3, 1.0))
			var back_k := smooth(clampf((p - 0.7) / 0.3, 0.0, 1.0))
			# Arm swings out to the side; on the way back it lifts so the anchor clears the shoulder.
			arm_r.rotation = Vector3(lerpf(carry_arm.x, 1.3, out_k) + 0.5 * sin(back_k * PI), -0.1 * dir * out_k, lerpf(carry_arm.z, 0.65, out_k) + 0.45 * sin(back_k * PI))
			anchor.rotation = Rig.lerp_angle_v(carry_anchor, Vector3(0.45, 0.0, 0.0), out_k)
			body.position.z = -0.1 * maxf(w * dir, 0.0)
			leg_l.rotation.x = 0.35 * absf(w)
			leg_r.rotation.x = -0.3 * absf(w)
			_mark("impact", 0.46)
		"attack3":
			# Overhead slam that shakes the ground.
			if p < 0.42:
				var k := smooth(p / 0.42)
				arm_r.rotation = Vector3(lerpf(carry_arm.x, 3.0, k), 0.0, lerpf(carry_arm.z, 0.1, k))
				anchor.rotation = Rig.lerp_angle_v(carry_anchor, Vector3(2.01, 0, 0), k)
				torso.rotation.x = -0.25 * k
				head.rotation.x = -0.2 * k
				body.position.y = 0.06 * k
			elif p < 0.56:
				var k := ease_in((p - 0.42) / 0.14)
				arm_r.rotation = Vector3(lerpf(3.0, 0.9, k), 0.0, 0.1)
				anchor.rotation = Rig.lerp_angle_v(Vector3(2.01, 0, 0), Vector3(0.05, 0, 0), k)
				torso.rotation.x = lerpf(-0.25, 0.35, k)
				body.position.y = lerpf(0.06, -0.14, k)
			else:
				var k := smooth((p - 0.56) / 0.44)
				arm_r.rotation = Vector3(lerpf(0.9, carry_arm.x, k) + 0.6 * sin(k * PI), 0.0, lerpf(0.1, carry_arm.z, k) + 0.85 * sin(k * PI))
				anchor.rotation = Rig.lerp_angle_v(Vector3(0.05, 0, 0), carry_anchor, k)
				torso.rotation.x = lerpf(0.35, 0.0, k)
				body.position.y = lerpf(-0.14, 0.0, k)
			leg_l.rotation.x = -0.45
			leg_r.rotation.x = 0.35
			_mark("impact", 0.56)
		"bash":
			# Thrust the lens forward: a blinding flash.
			var k := strike_curve(p, 0.3, 0.48)
			arm_l.rotation = Rig.lerp_angle_v(arm_l.rotation, Vector3(1.45, 0.25, -0.05), clampf(absf(k) * 1.4, 0.0, 1.0))
			torso.rotation.y += 0.4 * k
			body.position.z = -maxf(k, 0.0) * 0.22
			leg_l.rotation.x = -0.5 * maxf(k, 0.0)
			leg_r.rotation.x = 0.4 * maxf(k, 0.0)
			if action_t >= 0.48 * action_len and not _fired.has("flash"):
				_fired["flash"] = true
				_lens_flash = 1.0
			_mark("impact", 0.48)
		"dodge":
			# Steam-powered dash: crouch low, lean hard into it.
			var k := sin(p * PI)
			body.position.y = -0.12 * k
			torso.rotation.x = 0.45 * k
			leg_l.rotation.x = -0.9 * k
			leg_r.rotation.x = 0.7 * k
			arm_r.rotation.x = -0.9 * k
			arm_l.rotation.x = 0.9 * k
			if Game.fx and not _fired.has("steam"):
				_fired["steam"] = true
				var tr: Node3D = parts["torso"]
				for sx in [-1.0, 1.0]:
					Game.fx.smoke(tr.global_transform * Vector3(0.13 * sx, 0.56, 0.44), 3, Color(0.95, 0.95, 0.93))
		"hit":
			var k := sin(p * PI)
			torso.rotation.x -= 0.3 * k
			head.rotation.x -= 0.25 * k
			body.position.z = 0.12 * k
		"death":
			# Knees give way, the automaton slumps over its anchor.
			var k := smooth(minf(p / 0.6, 1.0))
			body.position.y = -0.38 * k
			leg_l.rotation.x = -1.3 * k
			leg_r.rotation.x = -1.1 * k
			torso.rotation.x = 0.55 * k
			head.rotation.x = 0.45 * k
			_anchor_via_mid(k, Vector3(0.5, 0.0, 0.55), Vector3(-0.3, 0.0, 0.35))
			arm_l.rotation.x = lerpf(0.4, -0.2, k)
		"relight":
			var k := 1.0 - smooth(p)
			_anchor_via_mid(k, Vector3(0.5, 0.0, 0.55), Vector3(-0.3, 0.0, 0.35))
			body.position.y = -0.38 * k
			leg_l.rotation.x = -1.3 * k
			leg_r.rotation.x = -1.1 * k
			torso.rotation.x = 0.55 * k
			head.rotation.x = 0.45 * k - 0.3 * sin(p * PI)
		"cast":
			# The lighthouse turns: the lantern blazes and the beam sweeps all around.
			var k := smooth(minf(p / 0.15, 1.0)) * smooth(minf((1.0 - p) / 0.12, 1.0))
			_beam_k = k
			body.rotation.y = smooth(clampf((p - 0.1) / 0.8, 0.0, 1.0)) * TAU
			arm_r.rotation = Vector3(-0.6, 0, 0.5)
			arm_l.rotation = Vector3(-0.2, 0.3, -0.6)
			head.rotation.x = -0.1
			body.position.y = -0.05 * k
			leg_l.rotation.x = -0.3 * k
			leg_r.rotation.x = 0.3 * k
		"cheer":
			var k := sin(minf(p * 1.6, 1.0) * PI * 0.5)
			arm_r.rotation = Vector3(lerpf(1.2, 2.9, k), 0, 0.1)
			anchor.rotation = Rig.lerp_angle_v(carry_anchor, Vector3(0.24, 0, 0), k)
			head.rotation.x = -0.3 * k
			_beam_k = maxf(_beam_k, 0.3 * k)
		"look":
			var k := sin(p * PI)
			head.rotation.y = sin(p * TAU) * 0.8 * k
			torso.rotation.y = sin(p * TAU) * 0.12 * k
		"rest":
			# Plants the anchor and leans on it, gazing out to sea.
			var k := smooth(minf(p / 0.2, 1.0)) * smooth(minf((1.0 - p) / 0.2, 1.0))
			_anchor_via_mid(k, Vector3(0.75, 0.0, 0.3), Vector3(-0.55, 0.0, 0.2))
			torso.rotation.x += 0.12 * k
			torso.rotation.z = -0.06 * k
			head.rotation.y = 0.35 * k * sin(t * 0.5)
		"build":
			var k := sin(p * PI)
			torso.rotation.x += 0.2 * k
			arm_l.rotation.x += 0.4 * k


## Angle (radians, world yaw) the beam is pointing at during "cast".
func _anchor_via_mid(k: float, final_arm: Vector3, final_anchor: Vector3) -> void:
	var arm_r: Node3D = parts["arm_r"]
	var anchor: Node3D = parts["anchor"]
	if k < 0.5:
		var u := k * 2.0
		arm_r.rotation = carry_arm.lerp(MID_ARM, u)
		anchor.rotation = Rig.lerp_angle_v(carry_anchor, MID_ANCHOR, u)
	else:
		var u := (k - 0.5) * 2.0
		arm_r.rotation = MID_ARM.lerp(final_arm, u)
		anchor.rotation = Rig.lerp_angle_v(MID_ANCHOR, final_anchor, u)


func beam_yaw() -> float:
	var body: Node3D = parts["body"]
	return rotation.y + body.rotation.y


func beam_active() -> bool:
	return action == "cast" and _beam_k > 0.5


func _update_sash(delta: float) -> void:
	if not is_inside_tree():
		return
	var hips: Node3D = parts["hips"]
	var xf := hips.global_transform
	var back := xf.basis.z.normalized()
	var right := xf.basis.x.normalized()
	var anchors := [xf * Vector3(-0.22, 0.03, 0.2), xf * Vector3(-0.27, 0.03, 0.08)]
	var vel := (global_position - _prev_root) / maxf(delta, 0.0001)
	_prev_root = global_position
	var lift := clampf(vel.length() / 6.0, 0.0, 1.0)
	for tail in 2:
		var pts: Array = _tails[tail]
		var seg := SASH_LEN * (1.0 - 0.15 * tail)
		if pts[0] == Vector3.ZERO:
			for i in pts.size():
				pts[i] = anchors[tail] + Vector3.DOWN * seg * i + back * 0.02 * i
		pts[0] = anchors[tail]
		for i in range(1, pts.size()):
			var k := float(i) / float(pts.size() - 1)
			var rest_dir := (back * (0.25 + 0.75 * lift) + Vector3.DOWN * (1.0 - 0.7 * lift) + right * sin(t * 2.6 - k * 3.5 + tail * 1.3) * (0.15 + 0.3 * lift)).normalized()
			var target: Vector3 = pts[i - 1] + rest_dir * seg
			pts[i] = (pts[i] as Vector3).lerp(target, clampf(delta * (13.0 - k * 5.0), 0.0, 1.0))
			var d: Vector3 = pts[i] - pts[i - 1]
			pts[i] = pts[i - 1] + d.normalized() * seg
			if Game.island:
				var g := Game.island.height_at(pts[i].x, pts[i].z) + 0.04
				if pts[i].y < g:
					pts[i] = Vector3(pts[i].x, g, pts[i].z)
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for tail in 2:
		var pts: Array = _tails[tail]
		var w := 0.095 if tail == 0 else 0.075
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var segd := (b - a).normalized()
			var wdir := segd.cross(back)
			if wdir.length() < 0.1:
				wdir = right
			wdir = wdir.normalized()
			var col := SAIL if tail == 0 else SAIL_DARK
			if i == 2:
				col = SAIL_STRIPE
			_quad2(a - wdir * w, a + wdir * w, b + wdir * w * 0.92, b - wdir * w * 0.92, col)
	_im.surface_end()


func _quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for tri in [[a, c, b], [a, d, c]]:
		for v in tri:
			_im.surface_set_color(col)
			_im.surface_set_normal(n)
			_im.surface_add_vertex(v)
	for tri in [[a, b, c], [a, c, d]]:
		for v in tri:
			_im.surface_set_color(col.darkened(0.15))
			_im.surface_set_normal(-n)
			_im.surface_add_vertex(v)
