# chars-godot QA: numeric comparison of the Godot character runtime (CharRuntime.buildCharacter: rig rebuild,
# Animator + rest offsets + face wrap, Skeleton3D/Skin binds, parts, attachments, slots) against the ORIGINAL JS
# charRuntime (tools/chars/char_dump: node world matrices incl. slots/parts/attachments, CPU-skinned body vertices
# with morphs, lids / brows / morph weights, hairBounds), plus the heroes.gd buildHero contract.
#   cd tools/chars && node char_dump_build.mjs && node char_dump.mjs duke /abs/duke_ref.json char_state1.json
#   godot --headless --path . -s res://tools/chars/char_compare.gd -- id=duke ref=/abs/duke_ref.json state=/abs/.../char_state1.json
#   (or cases=id:ref:state,id2:ref2:state2 ...). Custom rigs (z_sock, z_bigshot, boss_baron, example_sock): char_state0.json.
extends SceneTree
var _done := false
func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	quit()
	return true

func _arg(k: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(k + "="):
			return a.substr(k.length() + 1)
	return ""

func _run() -> void:
	# cases=id:ref.json:state.json,id2:... (or id= ref= state=)
	var cases := []
	if _arg("cases") != "":
		for cs in _arg("cases").split(","):
			cases.append(cs.split(":"))
	else:
		cases.append([_arg("id"), _arg("ref"), _arg("state")])
	var fails := 0
	for cs in cases:
		if not _case(cs[0], cs[1], cs[2]):
			fails += 1
	# heroes.gd contract (JS buildHero result)
	var h = Heroes.buildHero("duke", null)
	var hok: bool = h != null and h.baked and h.slots.size() == 10 and h.parts.head is Node3D and h.parts.torso == h.rig.joints.chest \
		and h.group.name == "hero_duke" and h.animator is Rig.Animator and h.art.face != null and absf(h.parts.head.position.y - float(h.rig.dims.headH) * 0.5) < 1e-6
	print("CMP heroes.buildHero ", "PASS" if hok else "FAIL", " slots ", h.slots.keys() if h != null else null)
	if not hok:
		fails += 1
	if h != null:
		h.group.free()
	# zombie defaults: ZOMBIES layer, zombie gait, keepColor
	if CharRuntime.isBaked("z_crew"):
		var z := CharRuntime.buildCharacter("z_crew", {"animator": "zombie"})
		var layerOk := z.skinnedMesh.layers == (1 << Config.LAYERS.ZOMBIES)
		var gaitOk: bool = z.animator.p.arms == "forward"
		var kc: bool = DAU.ud(z.skinnedMesh).get("keepColor", false)
		print("CMP zombie defaults ", "PASS" if layerOk and gaitOk and kc else "FAIL")
		if not (layerOk and gaitOk and kc):
			fails += 1
		z.group.free()
	print("CMP ALL %d cases, %d failed" % [cases.size(), fails])

func _case(id: String, refPath: String, statePath: String) -> bool:
	var ref = JSON.parse_string(FileAccess.get_file_as_string(refPath))
	var st = JSON.parse_string(FileAccess.get_file_as_string(statePath))
	Rig._eOrder = "XYZ"   # each JS dump ran in a fresh process (rig.js module-level Euler order state)
	var c := CharRuntime.buildCharacter(id, {"heroFade": true})
	var a = c.animator
	if a is Rig.Animator:
		a.seed = 1.5; a.phase = 0.7; a.t = 2.0
		a.wob = {"amp": 1.1, "tilt": 0.05, "armL": 0.1, "armR": -0.08, "speed": 0.95}
	var face = c.face
	face.auto = false
	face.blinkT = 99.0
	for fr in st.frames:
		if fr.has("expr"): face.setExpression(fr.expr[0], fr.expr[1])
		if fr.has("look"): face.setLook(fr.look[0], fr.look[1])
		if fr.has("blink"): face.blink()
		for k in fr.get("poses", {}):
			a.pose(k, fr.poses[k])
		c.update(fr.dt, fr.st)
	c.group.position = Vector3(0.3, 0, -0.2)
	c.group.rotation.y = 0.4
	get_root().add_child(c.group)
	var skel = c.skinnedMesh.get_parent()
	skel.sync()
	# node world matrices
	var worstM := 0.0
	var worstMAt := ""
	var matched := 0
	for name in ref.mats:
		var gname: String = String(name).validate_node_name()
		var node: Node3D = null
		if c.group.name == gname:
			node = c.group
		else:
			node = c.group.find_child(gname, true, false) as Node3D
		if node == null:
			print("CMP missing node ", name)
			continue
		matched += 1
		var gt := node.global_transform
		var e: Array = ref.mats[name]
		var mine := [gt.basis.x.x, gt.basis.x.y, gt.basis.x.z, gt.basis.y.x, gt.basis.y.y, gt.basis.y.z, gt.basis.z.x, gt.basis.z.y, gt.basis.z.z, gt.origin.x, gt.origin.y, gt.origin.z]
		var theirs := [e[0], e[1], e[2], e[4], e[5], e[6], e[8], e[9], e[10], e[12], e[13], e[14]]
		for k in 12:
			var d := absf(float(mine[k]) - float(theirs[k]))
			if d > worstM:
				worstM = d
				worstMAt = "%s c%d mine %f js %f" % [name, k, mine[k], theirs[k]]
	print("CMP [%s] nodes matched %d/%d worst %s at %s" % [id, matched, ref.mats.size(), str(worstM), worstMAt])
	# CPU skinning of the rebuilt body mesh with the skeleton poses + skin binds (what Godot's GPU skinning does)
	var mesh: ArrayMesh = c.skinnedMesh.mesh
	var arrays := mesh.surface_get_arrays(0)
	var bsa := mesh.surface_get_blend_shape_arrays(0)
	var V: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var B = arrays[Mesh.ARRAY_BONES]
	var W = arrays[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = c.skinnedMesh.skin
	var bindT := []
	for i in skin.get_bind_count():
		var bi: int = skel.find_bone(skin.get_bind_name(i))
		bindT.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(i))
	var mg: Transform3D = c.skinnedMesh.global_transform
	var worstV := 0.0
	var worstVAt := ""
	# the Godot importer may reorder vertices: match the JS vertices by their bind position
	var byPos := {}
	for i in V.size():
		byPos[Vector3i((V[i] * 20000.0).round())] = i
	var unmatched := 0
	for e in ref.verts:
		var key := Vector3i((Vector3(e[4], e[5], e[6]) * 20000.0).round())
		if not byPos.has(key):
			unmatched += 1
			continue
		var i: int = byPos[key]
		var p := V[i]
		for k in bsa.size():
			var wk: float = c.skinnedMesh.get_blend_shape_value(k)
			if wk != 0.0:
				p += (bsa[k][Mesh.ARRAY_VERTEX][i] - V[i]) * wk
		var s := Vector3.ZERO
		for k in 4:
			var w: float = W[i * 4 + k]
			if w != 0.0:
				s += (bindT[int(B[i * 4 + k])] * p) * w
		var wp := mg * s
		var d := wp.distance_to(Vector3(e[1], e[2], e[3]))
		if d > worstV:
			worstV = d
			worstVAt = "v%d mine %s js %s" % [i, str(wp), str([e[1], e[2], e[3]])]
	print("CMP skinned verts %d (unmatched %d) worst %s at %s" % [ref.verts.size(), unmatched, str(worstV), worstVAt])
	# morph influences, brows, lids
	var worstF := 0.0
	for k in ref.infl.size():
		worstF = maxf(worstF, absf(c.skinnedMesh.get_blend_shape_value(k) - float(ref.infl[k])))
	for k in ref.brows.size():
		worstF = maxf(worstF, absf(face.brows[k].mesh.position.y - float(ref.brows[k].y)))
		worstF = maxf(worstF, absf(face.brows[k].mesh.rotation.z - float(ref.brows[k].rz)))
	for k in ref.eyes.size():
		if k < face.eyes.size():
			worstF = maxf(worstF, absf(face.eyes[k].upper.rotation.x - float(ref.eyes[k].upper)))
			worstF = maxf(worstF, absf(face.eyes[k].lower.rotation.x - float(ref.eyes[k].lower)))
	print("CMP face worst %s (eyes %d/%d) hairBounds mine %f js %f" % [str(worstF), face.eyes.size(), ref.eyes.size(), c.hairBounds, float(ref.hairBounds)])
	var ok := worstM < 1e-3 and worstV < 2e-3 and worstF < 1e-3 and absf(c.hairBounds - float(ref.hairBounds)) < 1e-4
	print("CMP %s %s" % [id, "PASS" if ok else "FAIL"])
	c.group.queue_free()
	return ok
