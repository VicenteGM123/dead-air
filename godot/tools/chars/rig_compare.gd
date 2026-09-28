# chars-godot QA: numerical comparison of scripts/core/rig.gd (createRig + Animator: every style, poses, override,
# kick, headLag, alignHand) against the ORIGINAL src/core/rig.js run in Node on the same scripted states.
#   node tools/chars/rig_dump.mjs /abs/rig_ref.json        (from godot/; three.js from the repo's node_modules)
#   godot --headless --path . -s res://tools/chars/rig_compare.gd -- ref=/abs/rig_ref.json
# Prints RIG_COMPARE PASS when every joint world matrix matches within 2e-3 (typically ~1e-6).
extends SceneTree

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true

func _run() -> void:
	var ref_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ref="):
			ref_path = a.substr(4)
	var data = JSON.parse_string(FileAccess.get_file_as_string(ref_path))
	Rig.registerPose("testpose", {"head": [0.3, -0.2, 0.1], "shoulderL": [1.2, 0.3, -0.4], "kneeR": [-0.8, 0, 0]})
	var worst := 0.0
	var worstAt := ""
	var nsamples := 0
	for entry in data:
		var sc: Dictionary = entry.scenario
		var rig := Rig.createRig(sc.rig)
		for k in entry.dims:
			var dv: float = entry.dims[k]
			if absf(float(rig.dims[k]) - dv) > 1e-9:
				push_error("dims mismatch %s %s %s" % [k, rig.dims[k], dv])
		var group := Node3D.new()
		group.rotation.y = sc.groupYaw
		group.position = Vector3(sc.groupPos[0], sc.groupPos[1], sc.groupPos[2])
		get_root().add_child(group)
		group.add_child(rig.root)
		var a := Rig.Animator.new(rig, sc.style)
		a.seed = sc.rand.seed
		a.phase = sc.rand.phase
		a.t = sc.rand.t
		for k in sc.rand.wob:
			a.wob[k] = sc.rand.wob[k]
		var si := 0
		var samples: Array = entry.samples
		for i in sc.frames.size():
			var fr: Dictionary = sc.frames[i]
			for k in fr.poses:
				a.pose(k, fr.poses[k])
			if fr.kick:
				a.kick(fr.kick)
			a.override = (func(r, dt): r.joints.head.rotation.y += 0.3; r.joints.chest.position.z += dt) if fr.override else null
			a.update(fr.dt, fr.st)
			if si < samples.size() and int(samples[si].frame) == i:
				var smp: Dictionary = samples[si]
				si += 1
				nsamples += 1
				var mats: Dictionary = smp.mats
				for n in mats:
					var node: Node3D = rig.root if n == "root" else rig.joints[n]
					var gt := node.global_transform
					var e: Array = mats[n]
					var mine := [gt.basis.x.x, gt.basis.x.y, gt.basis.x.z, gt.basis.y.x, gt.basis.y.y, gt.basis.y.z, gt.basis.z.x, gt.basis.z.y, gt.basis.z.z, gt.origin.x, gt.origin.y, gt.origin.z]
					var theirs := [e[0], e[1], e[2], e[4], e[5], e[6], e[8], e[9], e[10], e[12], e[13], e[14]]
					for c in 12:
						var d := absf(float(mine[c]) - float(theirs[c]))
						if d > worst:
							worst = d
							worstAt = "sc %d frame %d joint %s comp %d mine %f js %f" % [sc.id, i, n, c, mine[c], theirs[c]]
				var hl: Array = smp.headLag
				var d2: float = maxf(absf(a.headLag.x - float(hl[0])), absf(a.headLag.z - float(hl[1])))
				if d2 > worst:
					worst = d2
					worstAt = "headLag sc %d frame %d" % [sc.id, i]
		group.queue_free()
	print("RIG_COMPARE samples=%d worst=%s at %s" % [nsamples, str(worst), worstAt])
	print("RIG_COMPARE " + ("PASS" if worst < 2e-3 else "FAIL"))
	quit()
