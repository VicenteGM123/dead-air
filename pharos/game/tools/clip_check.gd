extends Node3D
## Self-intersection checker for the hero rig: poses Fanós through every animation and reports where the
## anchor or the lens-shield pass through his own body (lantern head, torso, pauldrons, hands, legs).
##   godot --headless --path . res://tools/clip_check.tscn

var rig: RigHero
var _verts := {}


func _ready() -> void:
	rig = RigHero.new()
	add_child(rig)
	await get_tree().process_frame
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	if Game.arg("sweep", "0") == "1":
		_sweep()
		get_tree().quit()
		return
	if Game.arg("path", "") != "":
		_path_sweep(Game.arg("path"))
		get_tree().quit()
		return
	var report: Array = []
	var poses: Array = []
	for i in 6:
		poses.append(["idle", 0.0, float(i) / 6.0])
	for i in 8:
		poses.append(["run", 1.0, float(i) / 8.0])
	for a in ["attack1", "attack2", "attack3", "bash", "dodge", "cast", "cheer", "rest", "look", "death", "relight", "hit"]:
		for i in 11:
			poses.append([a, 0.0, float(i) / 10.0])
	var worst := 0
	for pose in poses:
		_set_pose(pose[0], pose[1], pose[2])
		var issues := _check()
		if not issues.is_empty():
			report.append("%s %.2f: %s" % [pose[0], pose[2], ", ".join(issues)])
			worst += 1
	for line in report:
		print(line)
	print("CLIP_CHECK poses=%d with_issues=%d" % [poses.size(), worst])
	get_tree().quit()


## Search the shoulder-carry pose: no contact with the lantern or the torso, crescent behind the right shoulder.
func _sweep() -> void:
	var best: Array = []
	for ax in [1.0, 1.1, 1.2, 1.3, 1.4]:
		for az in [0.15, 0.3, 0.45, 0.6]:
			for kx in [-3.4, -3.3, -3.2, -3.1, -3.0]:
				for kz in [0.5, 0.7, 0.9, 1.1, 1.3]:
					rig.carry_arm = Vector3(ax, 0.0, az)
					rig.carry_anchor = Vector3(kx, 0.0, kz)
					var bad := 0
					for i in 8:
						_set_pose("run", 1.0, float(i) / 8.0)
						bad += _check().size()
					_set_pose("idle", 0.0, 0.0)
					var issues := _check()
					bad += issues.size()
					if bad == 0:
						# Prefer the crown high and behind (readable from the camera) but clear of the head.
						var crown := (rig.parts["anchor"] as Node3D).global_transform * Vector3(0, -1.18, 0)
						var head := (rig.parts["head"] as Node3D).global_position
						var clear := Vector2(crown.x - head.x, crown.z - head.z).length()
						best.append([ax, az, kx, kz, crown.y, crown.z, clear])
	best.sort_custom(func(a, b): return a[4] + a[5] * 0.5 > b[4] + b[5] * 0.5)
	for b in best.slice(0, 12):
		print("OK arm=(%.2f,%.2f) anchor=(%.2f,%.2f) crown_y=%.2f crown_z=%.2f clear=%.2f" % b)
	print("SWEEP ok=%d" % best.size())


## Finds an intermediate pose so that carry -> mid -> final is collision free.
func _path_sweep(which: String) -> void:
	var final_arm := Vector3(0.75, 0.0, 0.3)
	var final_anchor := Vector3(-0.55, 0.0, 0.2)
	if which == "death":
		final_arm = Vector3(0.5, 0.0, 0.55)
		final_anchor = Vector3(-0.3, 0.0, 0.35)
	var ok: Array = []
	for mx in [0.4, 0.8, 1.2, 1.6]:
		for mz in [0.8, 1.1, 1.4, 1.7]:
			for kx in [-2.4, -1.6, -0.8, 0.0, 0.8]:
				for kz in [0.0, 0.5, 1.0, 1.5]:
					var mid_arm := Vector3(mx, 0.0, mz)
					var mid_anchor := Vector3(kx, 0.0, kz)
					var bad := 0
					for i in 21:
						var k := float(i) / 20.0
						var arm: Vector3
						var anc: Vector3
						if k < 0.5:
							arm = rig.carry_arm.lerp(mid_arm, k * 2.0)
							anc = Rig.lerp_angle_v(rig.carry_anchor, mid_anchor, k * 2.0)
						else:
							arm = mid_arm.lerp(final_arm, (k - 0.5) * 2.0)
							anc = Rig.lerp_angle_v(mid_anchor, final_anchor, (k - 0.5) * 2.0)
						_set_pose("idle", 0.0, 0.0)
						(rig.parts["arm_r"] as Node3D).rotation = arm
						(rig.parts["anchor"] as Node3D).rotation = anc
						bad += _check().size()
						if bad > 0:
							break
					if bad == 0:
						ok.append([mx, mz, kx, kz])
	for o in ok.slice(0, 10):
		print("PATH_OK mid_arm=(%.2f,0,%.2f) mid_anchor=(%.2f,0,%.2f)" % o)
	print("PATH %s ok=%d" % [which, ok.size()])


func _set_pose(action: String, mv: float, p: float) -> void:
	rig.action = ""
	rig.speed = mv * 6.0
	rig.speed_max = 6.0
	if action == "run":
		rig._run_phase = p * TAU
	elif action == "idle":
		rig.t = p * 4.0
	else:
		rig.play(action)
		rig.action_t = p * rig.action_len * 0.999
	for k in 6:
		rig._fired.clear()
		var saved_phase: float = rig._run_phase
		rig._animate(0.2)
		if action == "run":
			rig._run_phase = saved_phase # keep the sampled phase
		if action != "run" and action != "idle":
			rig.action = action
			rig.action_t = p * rig.action_len * 0.999


func _mesh_of(part: String) -> MeshInstance3D:
	for c in rig.parts[part].get_children():
		if c is MeshInstance3D and not ((c as MeshInstance3D).mesh is QuadMesh):
			return c
	return null


func _world_verts(part: String) -> PackedVector3Array:
	var mi := _mesh_of(part)
	var out := PackedVector3Array()
	if mi == null:
		return out
	if not _verts.has(part):
		_verts[part] = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform
	for v in _verts[part]:
		out.append(xf * v)
	return out


## Points of `pts` inside a vertical cylinder (in `part` local space) [r, y0, y1], with tolerance.
func _inside_cyl(pts: PackedVector3Array, part: String, r: float, y0: float, y1: float, tol: float = 0.015) -> int:
	var inv := (rig.parts[part] as Node3D).global_transform.affine_inverse()
	var n := 0
	for w in pts:
		var l := inv * w
		if l.y > y0 + tol and l.y < y1 - tol and Vector2(l.x, l.z).length() < r - tol:
			n += 1
	return n


func _inside_box(pts: PackedVector3Array, part: String, c: Vector3, size: Vector3, tol: float = 0.01) -> int:
	var inv := (rig.parts[part] as Node3D).global_transform.affine_inverse()
	var h := size * 0.5 - Vector3(tol, tol, tol)
	var n := 0
	for w in pts:
		var l := inv * w - c
		if absf(l.x) < h.x and absf(l.y) < h.y and absf(l.z) < h.z:
			n += 1
	return n


func _inside_ellipsoid(pts: PackedVector3Array, part: String, c: Vector3, radii: Vector3, tol: float = 0.015) -> int:
	var inv := (rig.parts[part] as Node3D).global_transform.affine_inverse()
	var n := 0
	for w in pts:
		var l := inv * w - c
		var q := Vector3(l.x / (radii.x - tol), l.y / (radii.y - tol), l.z / (radii.z - tol))
		if q.length() < 1.0:
			n += 1
	return n


## Torso lathe radius at height y (torso local space).
func _torso_r(y: float) -> float:
	var prof := [Vector2(0.28, 0.0), Vector2(0.33, 0.14), Vector2(0.39, 0.33), Vector2(0.37, 0.48), Vector2(0.28, 0.57), Vector2(0.15, 0.62)]
	if y <= 0.0 or y >= 0.62:
		return 0.0
	for i in prof.size() - 1:
		if y <= prof[i + 1].y:
			var k: float = (y - prof[i].y) / (prof[i + 1].y - prof[i].y)
			return lerpf(prof[i].x, prof[i + 1].x, k)
	return 0.0


func _inside_torso(pts: PackedVector3Array, tol: float = 0.02) -> int:
	var inv := (rig.parts["torso"] as Node3D).global_transform.affine_inverse()
	var n := 0
	for w in pts:
		var l := inv * w
		var r := _torso_r(l.y)
		if r > 0.0 and Vector2(l.x, l.z).length() < r - tol:
			n += 1
	return n


func _check() -> Array:
	var issues: Array = []
	var anchor := _world_verts("anchor")
	var shield := _world_verts("shield")
	# Lantern head: base ring r 0.24 (y 0.04..0.11), panes r 0.19 (0.11..0.41), gallery r 0.25 (0.4..0.45), dome to 0.63.
	var a_head := _inside_cyl(anchor, "head", 0.25, -0.05, 0.47) + _inside_cyl(anchor, "head", 0.17, 0.45, 0.66)
	if a_head > 0:
		issues.append("anchor-in-head(%d)" % a_head)
	var a_torso := _inside_torso(anchor)
	if a_torso > 0:
		issues.append("anchor-in-torso(%d)" % a_torso)
	var a_pauld := _inside_ellipsoid(anchor, "torso", Vector3(0.43, 0.5, 0), Vector3(0.158, 0.117, 0.172)) + _inside_ellipsoid(anchor, "torso", Vector3(-0.43, 0.5, 0), Vector3(0.158, 0.117, 0.172))
	if a_pauld > 2:
		issues.append("anchor-in-pauldron(%d)" % a_pauld)
	var a_hips := _inside_cyl(anchor, "hips", 0.34, -0.3, 0.1)
	if a_hips > 0:
		issues.append("anchor-in-kilt(%d)" % a_hips)
	for leg in ["leg_l", "leg_r"]:
		var a_leg := _inside_cyl(anchor, leg, 0.12, -0.8, 0.04)
		if a_leg > 0:
			issues.append("anchor-in-%s(%d)" % [leg, a_leg])
	var s_hand := _inside_box(shield, "arm_l", Vector3(0, -0.32, -0.36), Vector3(0.15, 0.16, 0.15))
	if s_hand > 0:
		issues.append("shield-in-hand(%d)" % s_hand)
	var hand_pts := PackedVector3Array()
	var arm_mi := _mesh_of("arm_l")
	var s_arm := 0
	var inv_arm := (rig.parts["arm_l"] as Node3D).global_transform.affine_inverse()
	for w in shield:
		var l := inv_arm * w
		# Forearm cylinder along -Z at y=-0.32, r 0.1, z 0..-0.28; upper arm along -Y r 0.105.
		if l.z < -0.01 and l.z > -0.29 and Vector2(l.x, l.y + 0.32).length() < 0.09:
			s_arm += 1
		if l.y < -0.01 and l.y > -0.31 and Vector2(l.x, l.z).length() < 0.095:
			s_arm += 1
	if s_arm > 0:
		issues.append("shield-in-arm(%d)" % s_arm)
	var s_torso := _inside_torso(shield)
	if s_torso > 0:
		issues.append("shield-in-torso(%d)" % s_torso)
	var s_head := _inside_cyl(shield, "head", 0.25, -0.05, 0.66)
	if s_head > 0:
		issues.append("shield-in-head(%d)" % s_head)
	var s_legs := _inside_cyl(shield, "leg_l", 0.12, -0.8, 0.04) + _inside_cyl(shield, "hips", 0.36, -0.31, 0.1)
	if s_legs > 0:
		issues.append("shield-in-legs/kilt(%d)" % s_legs)
	# Right hand (holding the anchor) must not enter the lantern either.
	var rh := _world_verts("arm_r")
	var h_head := _inside_cyl(rh, "head", 0.25, -0.05, 0.66)
	if h_head > 0:
		issues.append("rhand-in-head(%d)" % h_head)
	return issues
