extends Node3D
## Clipping checker for character rigs (generic port of PHAROS' hero checker): poses a rig through idle, a run
## cycle and every action, and reports
##  - parts passing through each other: for each pair [a, b] the vertices of part a's mesh that lie inside part b's
##    volume. Pairs come from the rig's clip_pairs() -> Array of [part_a, part_b] when it has one; otherwise every
##    weapon-like part (spear, sword, shield, weapon, club, chain) against every body part (torso, head, hips,
##    legs). Part b's volume is the rig's clip_volume(part) -> [centre: Vector3, radii: Vector3] (part-local
##    ellipsoid) when it has one, else the ellipsoid inscribed in that part's mesh AABB, shrunk by TOL;
##  - feet in the ground or floating: the lowest vertex of the rig on idle and run poses must stay within
##    [-0.03, +0.06] m of the rig origin (rigs stand with their origin on the ground).
##   godot --headless --path . res://tools/clip_check.tscn -- rig=res://scripts/gfx/rig_hero_standin.gd
##   (optional: actions=attack1,heavy  verbose=1)
## Prints the poses with issues and "CLIP_CHECK poses=N with_issues=M".

const TOL := 0.02
const WEAPONS := ["spear", "sword", "shield", "weapon", "club", "chain", "back_spear"]
const BODY := ["torso", "head", "hips", "leg_l", "leg_r"]

var rig: Rig
var _verts := {}


func _ready() -> void:
	var path: String = Game.arg("rig", "res://scripts/gfx/rig_hero_standin.gd")
	if path == "res://scripts/gfx/rig_hero_standin.gd" and ResourceLoader.exists("res://scripts/gfx/rig_heracles.gd") and not Game.has_arg("rig"):
		path = "res://scripts/gfx/rig_heracles.gd"
	rig = (load(path) as Script).new()
	add_child(rig)
	await get_tree().process_frame
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var actions: Array = []
	if Game.has_arg("actions"):
		actions = Array(String(Game.arg("actions")).split(",", false))
	elif "ACTIONS" in rig:
		actions = (rig.get("ACTIONS") as Dictionary).keys()
	else:
		actions = ["attack1", "attack2", "attack3", "hit", "death"]
	var pairs := _pairs()
	var poses: Array = []
	for i in 6:
		poses.append(["idle", 0.0, float(i) / 6.0])
	for i in 8:
		poses.append(["run", 1.0, float(i) / 8.0])
	for a in actions:
		for i in 11:
			poses.append([a, 0.0, float(i) / 10.0])
	var bad := 0
	for pose in poses:
		_set_pose(pose[0], pose[1], pose[2])
		var issues := _check(pairs, pose[0] == "idle" or pose[0] == "run")
		if not issues.is_empty():
			print("%s %.2f: %s" % [pose[0], pose[2], ", ".join(issues)])
			bad += 1
		elif Game.arg_on("verbose"):
			print("%s %.2f: ok" % [pose[0], pose[2]])
	print("CLIP_CHECK rig=%s pairs=%d poses=%d with_issues=%d" % [path.get_file(), pairs.size(), poses.size(), bad])
	get_tree().quit()


func _pairs() -> Array:
	if rig.has_method("clip_pairs"):
		return rig.call("clip_pairs")
	var out: Array = []
	for w in WEAPONS:
		if not rig.parts.has(w) or _mesh_of(w) == null:
			continue
		for b in BODY:
			if rig.parts.has(b) and _mesh_of(b) != null and not _is_ancestor(b, w):
				out.append([w, b])
	return out


## True when `part` is `other` or one of its pivots' ancestors (a weapon parented under a hand is not "inside" it).
func _is_ancestor(part: String, other: String) -> bool:
	var n: Node = rig.parts[other]
	var p: Node = rig.parts[part]
	return n == p


func _set_pose(action: String, mv: float, p: float) -> void:
	rig.action = ""
	rig.speed = mv * 6.0
	rig.speed_max = 6.0
	if action == "run":
		if "_run_phase" in rig:
			rig.set("_run_phase", p * TAU)
	elif action == "idle":
		rig.t = p * 4.0
	else:
		rig.play(action)
		rig.action_t = p * rig.action_len * 0.999
	for k in 4:
		rig._fired.clear()
		var saved: Variant = rig.get("_run_phase") if "_run_phase" in rig else null
		rig._animate(0.2)
		if action == "run" and saved != null:
			rig.set("_run_phase", saved)
		if action != "run" and action != "idle":
			rig.action = action
			rig.action_t = p * rig.action_len * 0.999


func _mesh_of(part: String) -> MeshInstance3D:
	for c in (rig.parts[part] as Node).get_children():
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


func _volume(part: String) -> Array:
	if rig.has_method("clip_volume"):
		var v: Variant = rig.call("clip_volume", part)
		if v is Array and not (v as Array).is_empty():
			return v
	var mi := _mesh_of(part)
	var bb := mi.mesh.get_aabb()
	return [mi.transform * bb.get_center(), bb.size * 0.5]


func _inside(pts: PackedVector3Array, part: String) -> int:
	var vol := _volume(part)
	var c: Vector3 = vol[0]
	var r: Vector3 = vol[1] - Vector3.ONE * TOL
	if r.x <= 0.0 or r.y <= 0.0 or r.z <= 0.0:
		return 0
	var inv := (rig.parts[part] as Node3D).global_transform.affine_inverse()
	var n := 0
	for w in pts:
		var l := inv * w - c
		if (l / r).length() < 1.0:
			n += 1
	return n


func _check(pairs: Array, ground: bool) -> Array:
	var issues: Array = []
	for pr in pairs:
		var k := _inside(_world_verts(pr[0]), pr[1])
		if k > 0:
			issues.append("%s-in-%s(%d)" % [pr[0], pr[1], k])
	if ground:
		var low := INF
		for m in rig.meshes:
			if not m.visible or m.mesh is QuadMesh:
				continue
			var xf := (m as Node3D).global_transform
			for v in m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				low = minf(low, (xf * v).y - rig.global_position.y)
		if low < -0.03:
			issues.append("below-ground(%.3f)" % low)
		elif low > 0.06:
			issues.append("floating(%.3f)" % low)
	return issues
