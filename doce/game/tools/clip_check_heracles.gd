extends Node3D
## Self-intersection checker for RigHeracles (in the spirit of tools/clip_check.gd): poses Heracles through every
## action and locomotion state with a fixed step (cloth and skirt simulated as in game) and reports where the
## sword, shield, spear, cape, hands, arms or crest pass through his own body, each other or the ground.
##   godot --headless --path . res://tools/clip_check_heracles.tscn [-- acts=attack1,heavy] [step=0.0333] [tol=0.008] [verbose=1]
## Prints one line per problem (state, time, points -> volume, depth) and a CLIP_CHECK_HERACLES summary line.

var rig: RigHeracles
var tol := 0.008
var verbose := false
var _local := {}
var _report: Array[String] = []
var _issue_count := 0
var _sample_count := 0
var _worst := {}


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == k:
			return kv[1] if kv.size() > 1 else "1"
	return d


func _ready() -> void:
	tol = float(_arg("tol", "0.008"))
	verbose = _arg("verbose", "0") == "1"
	var step := float(_arg("step", str(1.0 / 30.0)))
	var only := _arg("acts", "")
	var states: Array = []
	# locomotion and states: [label, speed, motion state, guard, vy, outfit, seconds]
	var loco := [["idle", 0.0, &"ground", false, 0.0, &"helmet", 3.0], ["walk", 1.6, &"ground", false, 0.0, &"helmet", 1.6],
		["run", 5.5, &"ground", false, 0.0, &"helmet", 1.2], ["sprint", 8.5, &"ground", false, 0.0, &"helmet", 1.0],
		["guard", 0.0, &"ground", true, 0.0, &"helmet", 1.5], ["guard_walk", 1.5, &"ground", true, 0.0, &"helmet", 1.6],
		["air_up", 3.0, &"air", false, 5.0, &"helmet", 0.8], ["air_down", 3.0, &"air", false, -7.0, &"helmet", 0.8],
		["swim", 1.6, &"swim", false, 0.0, &"helmet", 2.0], ["swim_idle", 0.0, &"swim", false, 0.0, &"helmet", 2.0],
		["zip", 9.0, &"zip", false, 0.0, &"helmet", 1.0], ["idle_lion", 0.0, &"ground", false, 0.0, &"lion", 2.0],
		["run_lion", 5.5, &"ground", false, 0.0, &"lion", 1.2],
		# CORE: strafing round a locked target, back-pedalling with the chain, hanging under a ring
		["strafe_r", 2.2, &"ground", false, 0.0, &"helmet", 1.6, Vector3(2.2, 0.0, 0.0)],
		["strafe_l", 2.2, &"ground", false, 0.0, &"helmet", 1.6, Vector3(-2.2, 0.0, 0.0)],
		["run_strafe", 5.0, &"ground", false, 0.0, &"helmet", 1.2, Vector3(5.0, 0.0, 0.0)],
		["backpedal", 1.8, &"ground", false, 0.0, &"helmet", 1.6, Vector3(0.0, 0.0, 1.8)],
		["guard_strafe", 2.2, &"ground", true, 0.0, &"helmet", 1.6, Vector3(-2.2, 0.0, 0.0)],
		["guard_back", 1.8, &"ground", true, 0.0, &"helmet", 1.6, Vector3(0.0, 0.0, 1.8)],
		["hang", 0.0, &"hang", false, 0.0, &"helmet", 2.5]]
	for l in loco:
		if only == "" or only.split(",").has(l[0]):
			states.append(l)
	var acts: Array = []
	for a in RigHeracles._action_defs().keys():
		if String(a).ends_with("_lion"):
			continue
		if only == "" or only.split(",").has(a):
			acts.append(a)
	rig = RigHeracles.new()
	add_child(rig)
	await get_tree().process_frame
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	_cache_locals()
	if _arg("mode", "") == "search_dodge":
		_search_dodge()
		get_tree().quit()
		return
	if _arg("mode", "") == "cape":
		_reset(StringName(_arg("outfit", "helmet")))
		rig.dbg_off = _arg("off", "").split(",", false)
		_settle(float(_arg("secs", "3")))
		var inv := rig.global_transform.affine_inverse()
		for j in RigHeracles.CAPE_NR:
			var row: Array[String] = []
			for i in RigHeracles.CAPE_NC:
				var q: Vector3 = inv * rig._cape_pos[j * RigHeracles.CAPE_NC + i]
				var r: Vector3 = rig._cape_rest[j * RigHeracles.CAPE_NC + i]
				row.append("(%.2f %.2f %.2f|%.2f)" % [q.x, q.y, q.z, r.x])
			print("ROW %d %s" % [j, " ".join(row)])
		get_tree().quit()
		return
	if _arg("mode", "") == "search":
		_search()
		get_tree().quit()
		return
	if _arg("mode", "") == "lowest":
		_lowest(_arg("acts", "dodge"), float(_arg("at", "-1")))
		get_tree().quit()
		return
	for st in states:
		_run_state(st, step)
	for a in acts:
		_run_action(a, step, &"helmet")
		if a in ["pet", "interact", "victory", "throw", "attack1", "attack2", "attack3", "heavy", "parry", "dodge", "hit_heavy", "death", "grapple_loop", "pull"]:
			_run_action(a, step, &"lion")
	# the combo chained at its recovery windows
	if only == "" or only.split(",").has("combo"):
		_run_combo(step)
	for line in _report:
		print(line)
	var keys := _worst.keys()
	keys.sort()
	for k in keys:
		var w: Array = _worst[k]
		print("WORST %-34s depth=%.3f at %s" % [k, w[0], w[1]])
	print("CLIP_CHECK_HERACLES samples=%d issues=%d" % [_sample_count, _issue_count])
	get_tree().quit()


# --- driving the rig ------------------------------------------------------------------------------------------

func _reset(outfit: StringName) -> void:
	rig.free()
	rig = RigHeracles.new()
	add_child(rig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	rig.set_outfit(outfit)
	_cache_locals()


func _settle(seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		rig.advance(dt)


func _run_state(st: Array, step: float) -> void:
	_reset(st[5])
	rig.set_guard(st[3])
	rig.set_motion_state(st[2])
	rig.set_vertical_speed(st[4])
	rig.set_locomotion(st[1], 9.0)
	rig.velocity_hint = st[7] if st.size() > 7 else Vector3(0, 0, -st[1])
	_settle(1.0)
	var t := 0.0
	var dt := 1.0 / 60.0
	var next := 0.0
	while t < float(st[6]):
		rig.advance(dt)
		t += dt
		if t >= next:
			next += step
			_check("%s %.2fs" % [st[0], t], st[2] == &"ground", false)


func _run_action(a: String, step: float, outfit: StringName) -> void:
	_reset(outfit)
	_settle(1.0)
	var len := rig.play(a)
	var dt := 1.0 / 60.0
	var t := 0.0
	var next := 0.0
	var total := len + (0.35 if not RigHeracles.act_def(a).get("hold", false) else 0.3)
	if RigHeracles.act_def(a).get("loop", false):
		total = len * 2.0
	var lying := a == "death"
	while t < total:
		rig.advance(dt)
		t += dt
		if t >= next:
			next += step
			_check("%s%s %.2fs" % [a, "/lion" if outfit == &"lion" else "", t], true, lying)


func _run_combo(step: float) -> void:
	_reset(&"helmet")
	_settle(1.0)
	var dt := 1.0 / 60.0
	var t := 0.0
	var next := 0.0
	var seq := [["attack1", 0.0], ["attack2", 0.36], ["attack3", 0.72]]
	var si := 0
	while t < 2.1:
		if si < seq.size() and t >= float(seq[si][1]):
			rig.play(seq[si][0])
			si += 1
		rig.advance(dt)
		t += dt
		if t >= next:
			next += step
			_check("combo %.2fs" % t, true, false)


# --- geometry -------------------------------------------------------------------------------------------------

## Unique vertex positions of a mesh, subsampled.
func _verts(m: Mesh, every: int = 1) -> PackedVector3Array:
	var out := PackedVector3Array()
	var seen := {}
	for si in m.get_surface_count():
		var arr: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for i in arr.size():
			var key := Vector3i(roundi(arr[i].x * 500.0), roundi(arr[i].y * 500.0), roundi(arr[i].z * 500.0))
			if seen.has(key):
				continue
			seen[key] = true
			if seen.size() % every == 0:
				out.append(arr[i])
	return out


func _cache_locals() -> void:
	if not _local.is_empty():
		return
	var sw: Array = RigHeracles.sword_meshes()
	var pts := PackedVector3Array()
	for m in sw:
		for v in _verts(m):
			# the grip is inside the fist
			if v.z > -0.062 and v.z < 0.075 and Vector2(v.x, v.y).length() < 0.03:
				continue
			pts.append(v)
	_local["sword"] = pts
	var sh := PackedVector3Array()
	for m in RigHeracles.shield_meshes():
		sh.append_array(_verts(m, 2))
	_local["shield"] = sh
	var sp := PackedVector3Array()
	for m in RigHeracles.spear_meshes():
		sp.append_array(_verts(m, 2))
	_local["spear"] = sp
	_local["fist_r"] = _verts(RigHeracles.fist_mesh(1.0))
	_local["fist_l"] = _verts(RigHeracles.fist_mesh(-1.0))
	_local["open_l"] = _verts(RigHeracles.open_hand_mesh(-1.0))
	# crest: soft surface of the helmet meshes (the crest is the only soft part), bound to CREST_B
	_local["crest"] = _verts(RigHeracles.helmet_meshes()[0], 2)
	var hood: Array = RigHeracles.hood_meshes()
	var hp := PackedVector3Array()
	for m in hood:
		hp.append_array(_verts(m, 3))
	_local["hood"] = hp
	_local["paws"] = _verts(RigHeracles.paws_mesh(), 2)


func _xform(pts: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = xf * pts[i]
	return out


## Skinning matrix of a bone (rest rig space -> posed rig space).
func _skin(bone: int) -> Transform3D:
	var b: Transform3D = rig._bx[bone]
	return Transform3D(b.basis, b.origin - b.basis * rig._rest[bone])


## Points along a limb's surface (rings of 8) between two joints.
func _limb_pts(a: Vector3, b: Vector3, r: float, n: int = 5) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := (b - a).normalized()
	var x := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var y := d.cross(x)
	for k in n:
		var c := a.lerp(b, (float(k) + 0.5) / float(n))
		for i in 8:
			var ang := TAU * float(i) / 8.0
			out.append(c + (x * cos(ang) + y * sin(ang)) * r)
	return out


# --- volumes --------------------------------------------------------------------------------------------------
# Each volume: {name, kind: "cap" (a, b, r) | "ell" (xf: Transform3D to unit sphere space, r_min) | "box" (inv, half)
# | "disc" (inv xf, r, y0, y1)}

func _volumes() -> Array:
	var bx: Array[Transform3D] = rig._bx
	var v: Array = []
	var cap := func(nm: String, a: Vector3, b: Vector3, r: float) -> void:
		v.append({"name": nm, "kind": "cap", "a": a, "b": b, "r": r})
	# torso: chest (cuirass) and waist
	var ch := _skin(RigHeracles.CHEST)
	var spn := _skin(RigHeracles.SPINE)
	for sx in [-1.0, 1.0]:
		cap.call("torso", ch * Vector3(0.085 * sx, 1.2, 0.0), ch * Vector3(0.1 * sx, 1.43, 0.0), 0.135)
		cap.call("torso", spn * Vector3(0.06 * sx, 1.03, 0.0), spn * Vector3(0.07 * sx, 1.17, 0.0), 0.12)
	cap.call("torso", ch * Vector3(0.0, 1.2, -0.01), ch * Vector3(0.0, 1.42, -0.01), 0.155)
	var pv := _skin(RigHeracles.PELVIS)
	cap.call("pelvis", pv * Vector3(-0.07, 0.9, 0.0), pv * Vector3(0.07, 0.9, 0.0), 0.17)
	cap.call("pelvis", pv * Vector3(-0.07, 0.8, 0.0), pv * Vector3(0.07, 0.8, 0.0), 0.15)
	var nk := _skin(RigHeracles.NECK)
	cap.call("neck", nk * Vector3(0, 1.5, 0.015), nk * Vector3(0, 1.62, 0.01), 0.06)
	# helmet (its real shell profile) and crest (boxes along its arc)
	var hd := _skin(RigHeracles.HEAD)
	v.append({"name": "head", "kind": "helm", "inv": hd.affine_inverse()})
	if rig._show_lion:
		var hx: Transform3D = (rig._piv["hood_s"] as Node3D).transform
		v.append({"name": "hood", "kind": "hood", "inv": hx.affine_inverse()})
		var px: Transform3D = (rig._piv["chest_s"] as Node3D).transform
		if rig._paws_mi.visible:
			for sx in [-1.0, 1.0]:
				cap.call("paws", px * Vector3(0.13 * sx, 1.585, 0.06), px * Vector3(0.12 * sx, 1.525, -0.165), 0.034)
				cap.call("paws", px * Vector3(0.12 * sx, 1.525, -0.165), px * Vector3(0.022 * sx, 1.415, -0.262), 0.032)
				cap.call("paws", px * Vector3(0.012 * sx, 1.395, -0.266), px * Vector3(0.046 * sx, 1.28 - 0.025 * (sx + 1.0), -0.27), 0.04)
	var cr := _skin(RigHeracles.CREST_B)
	for i in (8 if rig._crest_mi.visible else 0):
		var k := (float(i) + 0.5) / 8.0
		var ang := lerpf(-0.66, 2.0, k)
		var hgt := 0.035 + 0.215 * pow(sin(clampf(k * 1.1, 0.0, 1.0) * PI), 0.7) * (1.0 - 0.3 * k)
		var dir := Vector3(0, cos(ang), sin(ang))
		var mid := RigHeracles.HEAD_C + Vector3(0, 0, 0.012) + dir * (0.192 + hgt * 0.5)
		var bas := Basis(Vector3.RIGHT, dir.cross(Vector3.RIGHT).normalized(), dir) if false else Basis(Vector3.RIGHT, ang)
		var bxf := cr * Transform3D(bas, mid)
		v.append({"name": "crest", "kind": "box", "inv": bxf.affine_inverse(), "half": Vector3(0.034, hgt * 0.42, 0.04)})
	# arms
	for side in 2:
		var o := 0 if side == 0 else 4
		var sfx := "_r" if side == 0 else "_l"
		cap.call("uarm" + sfx, bx[RigHeracles.UARM_R + o].origin, bx[RigHeracles.FARM_R + o].origin, 0.072)
		cap.call("farm" + sfx, bx[RigHeracles.FARM_R + o].origin, bx[RigHeracles.HAND_R + o].origin, 0.064)
		var hb: Transform3D = bx[RigHeracles.HAND_R + o]
		cap.call("hand" + sfx, hb.origin + hb.basis * Vector3(0, -0.05, 0), hb.origin + hb.basis * RigHeracles.GRIP, 0.058)
		var pa := _skin(RigHeracles.PAUL_R + side)
		var ps := RigHeracles.mx(RigHeracles.P_SHOULDER, 1.0 if side == 0 else -1.0) + Vector3(0.012 * (1.0 if side == 0 else -1.0), 0.03, 0.0)
		cap.call("pauldron" + sfx, pa * ps, pa * ps, 0.085)
	# legs
	for side in 2:
		var o := 0 if side == 0 else 3
		var sfx := "_r" if side == 0 else "_l"
		cap.call("thigh" + sfx, bx[RigHeracles.THIGH_R + o].origin, bx[RigHeracles.SHIN_R + o].origin, 0.088)
		cap.call("shin" + sfx, bx[RigHeracles.SHIN_R + o].origin, bx[RigHeracles.FOOT_R + o].origin, 0.07)
		var fb := _skin(RigHeracles.FOOT_R + o)
		var an := RigHeracles.mx(RigHeracles.P_ANKLE, 1.0 if side == 0 else -1.0)
		cap.call("foot" + sfx, fb * (an + Vector3(0, -0.05, 0.04)), fb * (an + Vector3(0, -0.06, -0.17)), 0.04)
	# props
	var shx := _skin(RigHeracles.FARM_L)
	var el := RigHeracles.mx(RigHeracles.P_ELBOW, -1.0)
	var wr := RigHeracles.mx(RigHeracles.P_WRIST, -1.0)
	var dfa := (wr - el).normalized()
	var cen := el + dfa * 0.13 + Vector3(-0.085, 0, 0)
	var ny := Vector3(-1, 0, 0)
	var nx := RigHeracles.perp(dfa, ny).normalized()
	var disc := shx * Transform3D(Basis(nx, ny, nx.cross(ny)), cen)
	if not rig._weapons_hidden():
		v.append({"name": "shield", "kind": "disc", "inv": disc.affine_inverse(), "r": RigHeracles.SHIELD_R * 0.98, "y0": -0.025, "y1": 0.07})
	if rig._spear_back.visible:
		var sxf: Transform3D = (rig._piv["spear_s"] as Node3D).transform * rig._spear_back.transform
		cap.call("spear", sxf * Vector3(0, 0, -0.5), sxf * Vector3(0, 0, 0.74), 0.02)
		cap.call("spear", sxf * Vector3(0, 0, 0.42), sxf * Vector3(0, 0, 0.66), 0.06)
	if rig._spear_hand.visible:
		var hxf: Transform3D = rig._hand_l.transform * rig._spear_hand.transform
		cap.call("spear", hxf * Vector3(0, 0, -0.5), hxf * Vector3(0, 0, 0.74), 0.02)
		cap.call("spear", hxf * Vector3(0, 0, 0.42), hxf * Vector3(0, 0, 0.66), 0.06)
	var swx: Transform3D = rig._hand_r.transform * rig._sword.transform
	if rig._sword.visible:
		cap.call("sword", swx * Vector3(0, 0, -0.1), swx * Vector3(0, 0, -0.6), 0.022)
	return v


func _depth(p: Vector3, vol: Dictionary) -> float:
	match String(vol["kind"]):
		"cap":
			var a: Vector3 = vol["a"]
			var b: Vector3 = vol["b"]
			var ab := b - a
			var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
			return float(vol["r"]) - p.distance_to(a + ab * tt)
		"ell":
			var q: Vector3 = (vol["inv"] as Transform3D) * p
			return (1.0 - q.length()) * float(vol["rmin"])
		"helm":
			var qh: Vector3 = (vol["inv"] as Transform3D) * p - RigHeracles.HEAD_C
			if qh.y > 0.176 or qh.y < -0.168:
				return -1.0
			var sp := RigHeracles.helm_pt(atan2(qh.x, -qh.z), qh.y)
			return Vector2(sp.x, sp.z).length() - Vector2(qh.x, qh.z).length()
		"hood":
			var qd: Vector3 = (vol["inv"] as Transform3D) * p - RigHeracles.HEAD_C
			var best := -1.0
			# muzzle
			var m := (qd - Vector3(0, 0.04, -0.29)) / Vector3(0.095, 0.065, 0.11)
			best = maxf(best, (1.0 - m.length()) * 0.065)
			var a := atan2(qd.x, -qd.z)
			if qd.y <= 0.236 and qd.y >= 0.022:
				var hp := RigHeracles.hood_pt(a, qd.y)
				best = maxf(best, Vector2(hp.x, hp.z).length() + 0.03 - Vector2(qd.x, qd.z).length())
			elif qd.y < 0.022 and qd.y > -0.15 and absf(a) > 1.1:
				# the mane hanging over the sides and the nape
				var rp := RigHeracles.hood_pt(a, 0.022)
				var r0 := Vector2(rp.x, rp.z).length() + 0.03
				var lo := lerpf(-0.07, -0.15, clampf((absf(a) - 1.1) / 1.5, 0.0, 1.0))
				if qd.y > lo:
					best = maxf(best, r0 - Vector2(qd.x, qd.z).length())
			return best
		"box":
			var q2: Vector3 = (vol["inv"] as Transform3D) * p
			var h: Vector3 = vol["half"]
			return minf(minf(h.x - absf(q2.x), h.y - absf(q2.y)), h.z - absf(q2.z))
		"disc":
			var q3: Vector3 = (vol["inv"] as Transform3D) * p
			var rr := float(vol["r"]) - Vector2(q3.x, q3.z).length()
			return minf(rr, minf(q3.y - float(vol["y0"]), float(vol["y1"]) - q3.y))
	return -1.0


# --- the check ------------------------------------------------------------------------------------------------

func _check(label: String, grounded: bool, lying: bool) -> void:
	_sample_count += 1
	var vols := _volumes()
	var sets := {}
	var swx: Transform3D = rig._hand_r.transform * rig._sword.transform
	# (laid aside or hidden through don_skin: not there to clip)
	if rig._sword.visible:
		sets["sword"] = _xform(_local["sword"], swx)
	if not rig._weapons_hidden():
		sets["shield"] = _xform(_local["shield"], _skin(RigHeracles.FARM_L))
	if rig._spear_back.visible:
		sets["spear"] = _xform(_local["spear"], (rig._piv["spear_s"] as Node3D).transform * rig._spear_back.transform)
	if rig._spear_hand.visible:
		sets["spear_hand"] = _xform(_local["spear"], rig._hand_l.transform * rig._spear_hand.transform)
	sets["fist_r"] = _xform(_local["fist_r"], _skin(RigHeracles.HAND_R))
	sets["hand_l"] = _xform(_local["open_l"] if rig._open_l.visible else _local["fist_l"], _skin(RigHeracles.HAND_L))
	if rig._crest_mi.visible:
		sets["crest"] = _xform(_local["crest"], _skin(RigHeracles.CREST_B))
	if rig._show_lion:
		sets["hood"] = _xform(_local["hood"], (rig._piv["hood_s"] as Node3D).transform)
	if rig._paws_mi.visible:
		sets["paws"] = _xform(_local["paws"], (rig._piv["chest_s"] as Node3D).transform)
	var cape := PackedVector3Array()
	var inv := rig.global_transform.affine_inverse()
	var nc := RigHeracles.CAPE_NC
	for j in range(1, RigHeracles.CAPE_NR):
		for i in nc:
			cape.append(inv * rig._cape_pos[j * nc + i])
			if i + 1 < nc:
				cape.append(inv * (rig._cape_pos[j * nc + i] + rig._cape_pos[j * nc + i + 1]) * 0.5)
	sets["cape"] = cape
	var bx: Array[Transform3D] = rig._bx
	for side in 2:
		var o := 0 if side == 0 else 4
		var sfx := "_r" if side == 0 else "_l"
		var sh0: Vector3 = bx[RigHeracles.UARM_R + o].origin
		var el0: Vector3 = bx[RigHeracles.FARM_R + o].origin
		sets["arm" + sfx] = _limb_pts(sh0.lerp(el0, 0.4), el0, 0.07, 3)
		sets["arm" + sfx].append_array(_limb_pts(bx[RigHeracles.FARM_R + o].origin, bx[RigHeracles.HAND_R + o].origin, 0.065, 3))
	# which volumes each point set must stay out of
	var body := ["torso", "pelvis", "neck", "head", "crest", "thigh_r", "thigh_l", "shin_r", "shin_l", "foot_r", "foot_l"]
	var rules := {
		"sword": body + ["uarm_l", "farm_l", "hand_l", "uarm_r", "pauldron_r", "pauldron_l", "shield", "spear", "hood", "paws"],
		"shield": body + ["uarm_r", "farm_r", "hand_r", "pauldron_r", "spear", "hood", "paws"],
		"spear": ["head", "crest", "neck", "uarm_r", "farm_r", "hand_r", "uarm_l", "farm_l", "hand_l", "thigh_r", "thigh_l", "shin_r", "shin_l", "pauldron_l", "pauldron_r", "shield", "hood"],
		"spear_hand": body + ["uarm_r", "farm_r", "hand_r", "uarm_l", "pauldron_l", "pauldron_r", "shield", "hood", "paws"],
		"fist_r": body + ["shield", "spear", "hand_l", "farm_l", "hood", "paws"],
		"hand_l": body + ["spear", "hood", "paws"],
		"crest": ["spear", "shield", "uarm_r", "farm_r", "hand_r", "uarm_l", "farm_l", "hand_l"],
		"hood": ["spear", "shield", "uarm_r", "farm_r", "hand_r", "farm_l", "hand_l", "pauldron_r", "pauldron_l"],
		"paws": ["uarm_r", "farm_r", "hand_r", "uarm_l", "farm_l", "hand_l", "shield"],
		"cape": ["torso", "pelvis", "thigh_r", "thigh_l", "shin_r", "shin_l", "uarm_r", "uarm_l", "farm_r", "farm_l", "head", "crest", "sword", "shield", "spear"],
		"arm_r": ["torso", "head", "crest", "thigh_r", "thigh_l", "shield", "spear", "hood", "paws"],
		"arm_l": ["torso", "head", "crest", "thigh_r", "thigh_l", "spear", "hood", "paws"],
	}
	# the left hand closing on the spear's shaft is meant to touch it
	if rig.action == "throw":
		rules["hand_l"] = body + ["hood", "paws"]
	for sname in sets:
		var pts: PackedVector3Array = sets[sname]
		if not rules.has(sname):
			continue
		var allowed: Array = rules[sname]
		for vol in vols:
			var vn: String = vol["name"]
			if not allowed.has(vn):
				continue
			var worst := 0.0
			var cnt := 0
			for p in pts:
				var d := _depth(p, vol)
				if d > tol:
					cnt += 1
					worst = maxf(worst, d)
			if cnt > 0:
				_issue(label, "%s->%s" % [sname, vn], cnt, worst)
		# ground
		var low := 0.0
		var lcnt := 0
		var floor_y := -0.012 if not lying else -0.03
		for p in pts:
			if p.y < floor_y:
				lcnt += 1
				low = minf(low, p.y)
		if lcnt > 0 and (grounded or lying):
			_issue(label, "%s->ground" % sname, lcnt, -low)
	# body parts in the ground (feet, knees, torso when kneeling or lying)
	if grounded or lying:
		var floor2 := -0.012 if not lying else -0.035
		for vol in vols:
			if vol["kind"] != "cap":
				continue
			var a: Vector3 = vol["a"]
			var b: Vector3 = vol["b"]
			var lowest := minf(a.y, b.y) - float(vol["r"])
			if lowest < floor2 and not String(vol["name"]).begins_with("spear"):
				_issue(label, "%s->ground" % vol["name"], 1, -lowest)


func _issue(label: String, pair: String, cnt: int, depth: float) -> void:
	_issue_count += 1
	var key := pair
	if not _worst.has(key) or float(_worst[key][0]) < depth:
		_worst[key] = [depth, label]
	if verbose or depth > 0.02:
		_report.append("%-22s %-26s n=%-4d depth=%.3f" % [label, pair, cnt, depth])


## Diagnostic: the lowest point of every point set and body volume through an action (mode=lowest acts=x [at=s]).
func _lowest(a: String, at: float) -> void:
	_reset(StringName(_arg("outfit", "helmet")))
	_settle(1.0)
	var len := rig.play(a)
	var dt := 1.0 / 60.0
	var t := 0.0
	var next := 0.0
	while t < len + 0.1:
		rig.advance(dt)
		t += dt
		if (at < 0.0 and t >= next) or (at >= 0.0 and absf(t - at) < dt * 0.5):
			next += 0.05
			var parts: Array[String] = []
			var vols := _volumes()
			var lows := {}
			for vol in vols:
				if vol["kind"] != "cap":
					continue
				var lo := minf((vol["a"] as Vector3).y, (vol["b"] as Vector3).y) - float(vol["r"])
				var nm: String = vol["name"]
				lows[nm] = minf(lows.get(nm, 9.0), lo)
			var swx: Transform3D = rig._hand_r.transform * rig._sword.transform
			var sets := {"sword": _xform(_local["sword"], swx), "shield": _xform(_local["shield"], _skin(RigHeracles.FARM_L))}
			if rig._crest_mi.visible:
				sets["crest"] = _xform(_local["crest"], _skin(RigHeracles.CREST_B))
			if rig._show_lion:
				sets["hood"] = _xform(_local["hood"], (rig._piv["hood_s"] as Node3D).transform)
			if rig._spear_back.visible:
				sets["spear"] = _xform(_local["spear"], (rig._piv["spear_s"] as Node3D).transform * rig._spear_back.transform)
			for k in sets:
				var lo2 := 9.0
				for p in sets[k]:
					lo2 = minf(lo2, p.y)
				lows[k] = lo2
			var hd := _skin(RigHeracles.HEAD) * RigHeracles.HEAD_C
			lows["helmet"] = hd.y - 0.17
			var keys := lows.keys()
			keys.sort_custom(func(x, y): return lows[x] < lows[y])
			for k in keys.slice(0, 7):
				parts.append("%s=%.2f" % [k, lows[k]])
			print("LOW %s %.2fs  %s" % [a, t, "  ".join(parts)])


## Lowest point over the whole body and its props (rig space) at the current pose.
func _min_y() -> float:
	var lo := 9.0
	for vol in _volumes():
		if vol["kind"] == "cap":
			lo = minf(lo, minf((vol["a"] as Vector3).y, (vol["b"] as Vector3).y) - float(vol["r"]))
	var swx: Transform3D = rig._hand_r.transform * rig._sword.transform
	for pset in [_xform(_local["sword"], swx), _xform(_local["shield"], _skin(RigHeracles.FARM_L)), _xform(_local["crest"], _skin(RigHeracles.CREST_B)),
			_xform(_local["spear"], (rig._piv["spear_s"] as Node3D).transform * rig._spear_back.transform)]:
		for p in pset:
			lo = minf(lo, p.y)
	return lo


## Grid search over the roll's tuck: pivot height, body yaw / roll inside the tuck, head tilt.
func _search_dodge() -> void:
	var def: Dictionary = RigHeracles.act_def("dodge")
	var poses: Array[PackedFloat32Array] = def["poses"]
	var orig: Array = []
	for p in poses:
		orig.append(p.duplicate())
	var results: Array = []
	for py in [0.62, 0.68, 0.74, 0.8]:
		for yaw in [-0.9, -0.45, 0.0, 0.45, 0.9]:
			for roll in [-0.7, -0.35, 0.0, 0.35, 0.7]:
				for tilt in [0.0, 0.6, 1.0]:
					for i in poses.size():
						var p: PackedFloat32Array = orig[i].duplicate()
						p[RigHeracles.C_PIV + 1] = py
						if i >= 2 and i <= 4:
							p[RigHeracles.C_PELR + 1] = yaw
							p[RigHeracles.C_PELR + 2] = roll
							p[RigHeracles.C_NEK + 2] = tilt
						poses[i] = p
					# tangents stay as compiled (fine for a search)
					_reset(&"helmet")
					_settle(0.3)
					var len := rig.play("dodge")
					var lo := 9.0
					var tt := 0.0
					while tt < len:
						rig.advance(1.0 / 60.0)
						tt += 1.0 / 60.0
						if tt > 0.12 and tt < 0.42:
							lo = minf(lo, _min_y())
					results.append([lo, py, yaw, roll, tilt])
	results.sort_custom(func(a, b): return a[0] > b[0])
	for r in results.slice(0, 15):
		print("ROLL min_y=%.3f pivot=%.2f yaw=%.2f roll=%.2f tilt=%.2f" % r)
	# best result per pivot height
	for py in [0.62, 0.68, 0.74, 0.8]:
		var best: Array = []
		for r in results:
			if is_equal_approx(float(r[1]), py) and (best.is_empty() or float(r[0]) > float(best[0])):
				best = r
		print("BEST@%.2f min_y=%.3f yaw=%.2f roll=%.2f tilt=%.2f" % [py, best[0], best[2], best[3], best[4]])
	for i in poses.size():
		poses[i] = orig[i]


# --- key search -----------------------------------------------------------------------------------------------
## mode=search act=<action> outfit=<o> keys=<i,j> c1=<channel> v1=<x,y,z;x,y,z;...> [c2=.. v2=..] [c3=.. v3=..]
## pairs=<set->vol,set->vol...> [ground=<set,set>]: tries every combination of the candidate values on the given
## raw keys (all listed key indices get the same value) and prints the best by summed penetration depth.
func _parse_vals(txt: String) -> Array:
	var out: Array = []
	for v in txt.split(";", false):
		var f := v.split(",")
		if f.size() == 3:
			out.append(Vector3(float(f[0]), float(f[1]), float(f[2])))
		else:
			out.append(float(f[0]))
	return out


func _search() -> void:
	var a := _arg("act", "dodge")
	var outfit := StringName(_arg("outfit", "helmet"))
	var key_idx: Array = []
	for k in _arg("keys", "1").split(","):
		key_idx.append(int(k))
	var chans: Array = []
	var vals: Array = []
	for i in [1, 2, 3]:
		var c := _arg("c%d" % i, "")
		if c != "":
			chans.append(c)
			vals.append(_parse_vals(_arg("v%d" % i, "")))
	var pairs: Array = []
	for pr in _arg("pairs", "shield->head").split(","):
		pairs.append(pr.split("->"))
	var ground_sets := _arg("ground", "").split(",", false)
	var raw: Dictionary = RigHeracles._action_defs()[a]
	var combos: Array = [[]]
	for vi in vals.size():
		var nxt: Array = []
		for cmb in combos:
			for v in vals[vi]:
				var c2: Array = cmb.duplicate()
				c2.append(v)
				nxt.append(c2)
		combos = nxt
	var results: Array = []
	RigHeracles.act_def(a)
	var saved: Dictionary = RigHeracles._acts[a]
	for cmb in combos:
		var d: Dictionary = raw.duplicate(true)
		var keys: Array = d["keys"]
		for ki in key_idx:
			var kd: Dictionary = (keys[ki][1] as Dictionary).duplicate()
			for ci in chans.size():
				kd[chans[ci]] = cmb[ci]
			keys[ki] = [keys[ki][0], kd]
		RigHeracles._acts[a] = RigHeracles.compile_action(d)
		_reset(outfit)
		_settle(0.5)
		var len := rig.play(a)
		var cost := 0.0
		var worst := 0.0
		var tt := 0.0
		while tt < len:
			rig.advance(1.0 / 30.0)
			tt += 1.0 / 30.0
			var vols := _volumes()
			var sets := _point_sets()
			for pr in pairs:
				var pts: PackedVector3Array = sets.get(pr[0], PackedVector3Array())
				for vol in vols:
					if vol["name"] != pr[1]:
						continue
					for pp in pts:
						var dd := _depth(pp, vol)
						if dd > 0.0:
							cost += dd
							worst = maxf(worst, dd)
			for gs in ground_sets:
				var pts2: PackedVector3Array = sets.get(gs, PackedVector3Array())
				for pp in pts2:
					if pp.y < 0.0:
						cost += -pp.y
						worst = maxf(worst, -pp.y)
		results.append([cost, worst, cmb])
	RigHeracles._acts[a] = saved
	results.sort_custom(func(x, y): return x[0] < y[0])
	for r in results.slice(0, 12):
		print("SEARCH cost=%.3f worst=%.3f %s" % [r[0], r[1], str(r[2])])


## The point sets of the current pose (as _check builds them).
func _point_sets() -> Dictionary:
	var sets := {}
	var swx: Transform3D = rig._hand_r.transform * rig._sword.transform
	sets["sword"] = _xform(_local["sword"], swx)
	sets["shield"] = _xform(_local["shield"], _skin(RigHeracles.FARM_L))
	if rig._spear_back.visible:
		sets["spear"] = _xform(_local["spear"], (rig._piv["spear_s"] as Node3D).transform * rig._spear_back.transform)
	sets["fist_r"] = _xform(_local["fist_r"], _skin(RigHeracles.HAND_R))
	sets["hand_l"] = _xform(_local["open_l"] if rig._open_l.visible else _local["fist_l"], _skin(RigHeracles.HAND_L))
	if rig._crest_mi.visible:
		sets["crest"] = _xform(_local["crest"], _skin(RigHeracles.CREST_B))
	if rig._show_lion:
		sets["hood"] = _xform(_local["hood"], (rig._piv["hood_s"] as Node3D).transform)
	var bx: Array[Transform3D] = rig._bx
	for side in 2:
		var o := 0 if side == 0 else 4
		var sfx := "_r" if side == 0 else "_l"
		var sh0: Vector3 = bx[RigHeracles.UARM_R + o].origin
		var el0: Vector3 = bx[RigHeracles.FARM_R + o].origin
		sets["arm" + sfx] = _limb_pts(sh0.lerp(el0, 0.4), el0, 0.07, 3)
		sets["arm" + sfx].append_array(_limb_pts(el0, bx[RigHeracles.HAND_R + o].origin, 0.065, 3))
	return sets
