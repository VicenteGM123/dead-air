extends Node3D
## Model preview / turntable for art review.
##   godot --path . res://tools/preview.tscn -- script=res://scripts/gfx/models_nature.gd fns=olive_tree,cypress tod=day cam=game
## Each fn is a static function on `script` taking (seed: int) and returning a Mesh, a Node3D, or a Dictionary
## with "mesh" (and optionally "node"). `n=3` shows three seeds of each. `spacing=6` overrides the auto layout.

func _ready() -> void:
	var tod := TimeOfDay.new()
	add_child(tod)
	tod.set_state(Game.arg("tod", "day"))
	var script_path: String = Game.arg("script", "")
	var fns: PackedStringArray = String(Game.arg("fns", "")).split(",", false)
	var count := int(Game.arg("n", "1"))
	var spacing := float(Game.arg("spacing", "0"))
	var items: Array[Node3D] = []
	var scr: Script = load(script_path) if script_path != "" else null
	for fn in fns:
		for k in count:
			var r: Variant = scr.call(fn, 11 + k * 7) if scr else null
			var node: Node3D = null
			if r is Mesh:
				var mi := MeshInstance3D.new()
				mi.mesh = r
				mi.material_override = Materials.lowpoly()
				node = mi
			elif r is Node3D:
				node = r
			elif r is Dictionary:
				if r.has("node"):
					node = r["node"]
				else:
					var mi2 := MeshInstance3D.new()
					mi2.mesh = r["mesh"]
					mi2.material_override = r.get("material", Materials.lowpoly())
					node = mi2
			if node:
				items.append(node)
				add_child(node)
	# Layout in a row (or grid) using the bounding boxes.
	var x := 0.0
	var maxw := 0.0
	var aabbs: Array[AABB] = []
	for it in items:
		var bb := _aabb(it)
		aabbs.append(bb)
		maxw = maxf(maxw, bb.size.x)
	var gap := spacing if spacing > 0.0 else maxw * 0.35 + 1.0
	var cols := int(Game.arg("cols", "0"))
	if cols <= 0:
		cols = items.size()
	var cx := 0.0
	var cz := 0.0
	var row_depth := 0.0
	var total := AABB()
	for i in items.size():
		if i > 0 and i % cols == 0:
			cx = 0.0
			cz += row_depth + gap
			row_depth = 0.0
		var bb := aabbs[i]
		items[i].position = Vector3(cx - bb.position.x, 0, cz - bb.position.z)
		cx += bb.size.x + gap
		row_depth = maxf(row_depth, bb.size.z)
		var moved := AABB(bb.position + items[i].position, bb.size)
		total = moved if i == 0 else total.merge(moved)
	# Ground.
	var mb := MeshBuilder.new()
	var c := total.get_center()
	var ext := maxf(total.size.x, total.size.z) * 0.5 + 8.0
	mb.block(Vector3(c.x, -0.3, c.z), Vector3(ext * 2.0, 0.3, ext * 2.0), Color(Game.arg("ground", "9AAE62")))
	var g := MeshInstance3D.new()
	g.mesh = mb.commit()
	g.material_override = Materials.lowpoly()
	add_child(g)
	var cam := Camera3D.new()
	add_child(cam)
	var mode: String = Game.arg("cam", "game")
	var radius := maxf(total.size.length() * 0.55, 2.0)
	var pitch := 38.0
	if mode == "low":
		pitch = 14.0
	elif mode == "top":
		pitch = 80.0
	elif mode == "game":
		pitch = 52.0
	var yaw := deg_to_rad(float(Game.arg("yaw", "0")))
	cam.fov = float(Game.arg("fov", "30"))
	var dist := radius / tan(deg_to_rad(cam.fov * 0.5)) * float(Game.arg("zoom", "1.0"))
	var p := deg_to_rad(pitch)
	var center := total.get_center()
	cam.position = center + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	cam.look_at(center, Vector3.UP)
	# Rigs can be posed for the shot: pose=attack:0.12 calls play("attack") and lets it run for 0.12 s.
	var pose: String = Game.arg("pose", "")
	if pose != "":
		var parts := pose.split(":")
		for it in items:
			if it.has_method("play"):
				it.call("play", parts[0])
	if Game.arg("move", "") != "":
		for it in items:
			if it.has_method("set_locomotion"):
				it.call("set_locomotion", float(Game.arg("move")), 6.0)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(n):
		var bb: AABB = m.get_aabb()
		bb = (m.global_transform if m.is_inside_tree() else _local_xf(m, n)) * bb
		out = bb if first else out.merge(bb)
		first = false
	return out if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func _local_xf(m: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = m
	while cur and cur != root.get_parent():
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and not ((n as MeshInstance3D).mesh is QuadMesh or (n as MeshInstance3D).mesh is ImmediateMesh):
		out.append(n)
	for ch in n.get_children():
		out.append_array(_meshes(ch))
	return out
