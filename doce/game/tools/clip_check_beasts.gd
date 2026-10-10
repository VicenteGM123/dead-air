extends Node3D
## Clip checker for the bestiary rigs (RigWolf, RigBoar, RigLion): drives each rig through idle, alert,
## locomotion at every gait, turning in place, strafing and every action (loops for two cycles), samples the
## pose every few frames and reports:
##   below-ground    any skinned vertex under the ground (CPU skinning of the real mesh)
##   paw-floating    a planted foot (stance, not lifted by the action) hovering above the ground
##   leg-in-body     a lower leg / paw core through the torso core
##   legs-cross      two legs' cores through each other
##   head-in-body / head-in-leg / neck-in-leg / tail-in-body / tail-in-leg, plus rig extras (mane, tusks)
##   corpse-floating a dead beast (death settled) whose body (torso, neck, upper legs) does not rest on the ground
## Besides flat ground, "slope" runs walk / trot / gallop over a rolling heightfield (up to ~23 deg) with the
## rig's ground_fn set, and measures every height above the terrain under it (act=slope runs only that).
## Cores are capsules from the rigs' own construction tables (Rig.clip_volumes()), shrunk so that touching
## surfaces do not count. Usage:
##   godot --headless --path . res://tools/clip_check_beasts.tscn -- beasts=wolf,boar,lion [act=bite] [v=1]

const PB := preload("res://tools/preview_beasts.gd")
const DT := 1.0 / 60.0
const GROUND_TOL := 0.012
const FLOAT_TOL := 0.03
const CORPSE_TOL := 0.05

var verbose := false
## Heightfield of the current run (world x, z -> height); invalid = flat ground at y 0.
var terrain := Callable()
var total_samples := 0
var total_bad := 0
var lines: Array[String] = []


func _ready() -> void:
	verbose = Game.arg("v", "0") == "1"
	var kinds := String(Game.arg("beasts", "wolf,boar,lion")).split(",", false)
	var only := String(Game.arg("act", ""))
	for kind in kinds:
		var variants := [0]
		if kind == "wolf":
			variants = [0, 1, 2] if Game.arg("variants", "1") == "1" else [0]
		for v in variants:
			_check_beast(kind, v, only)
	for l in lines:
		print(l)
	print("CLIP_CHECK_BEASTS samples=%d with_issues=%d" % [total_samples, total_bad])
	get_tree().quit()


# --- scenarios ---------------------------------------------------------------------------------------------

func _check_beast(kind: String, variant: int, only: String) -> void:
	var probe := _spawn(kind, variant)
	if probe == null:
		lines.append("%s: rig not found" % kind)
		return
	var actions: Dictionary = probe.get("actions")
	var act_info := {}
	for a in actions:
		act_info[a] = [float(actions[a][0]), bool(actions[a][1])]
	var gaits: Array = probe.q.gaits
	var mesh_data := _mesh_data(probe)
	_despawn(probe)
	var name := "%s%s" % [kind, ("/v%d" % variant) if kind == "wolf" else ""]
	var stats := {"samples": 0, "bad": 0}
	if only == "" or only == "idle":
		_run(name, "idle", kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void: pass, 240, 12)
		_run(name, "alert", kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void: r.call("set_alert", 1.0), 240, 12)
	if only == "" or only == "loco":
		var speeds: Array = []
		for g in gaits:
			speeds.append(float(g["speed"]) * 0.75)
			speeds.append(float(g["speed"]))
			speeds.append(float(g["speed"]) * 1.25)
		for sp in speeds:
			var spd: float = sp
			_run(name, "move %.1f m/s" % spd, kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
				var v := spd * clampf(float(i) / 40.0, 0.0, 1.0)
				r.set_locomotion(v, 9.0)
				r.position += r.global_transform.basis * Vector3(0, 0, -v * DT), 150, 3)
		_run(name, "turn in place", kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
			r.set_locomotion(0.0, 9.0)
			r.rotation.y += 2.2 * DT, 150, 4)
		_run(name, "turn walking", kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
			r.set_locomotion(1.3, 9.0)
			r.rotation.y -= 1.6 * DT
			r.position += r.global_transform.basis * Vector3(0, 0, -1.3 * DT), 150, 4)
		_run(name, "strafe", kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
			r.set_locomotion(0.9, 9.0)
			r.position += r.global_transform.basis * Vector3(0.9 * DT, 0, 0), 150, 4)
	if only == "" or only == "slope":
		var hf := func(x: float, z: float) -> float:
			return 0.35 * sin(x * 0.6) + 0.42 * sin(z * 0.55 + 1.0) + 0.12 * sin((x + z) * 1.3)
		for sp in [float(gaits[0]["speed"]), float(gaits[1]["speed"]), float(gaits[2]["speed"])]:
			var spd: float = sp
			_run(name, "slope %.1f m/s" % spd, kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
				var v := spd * clampf(float(i) / 40.0, 0.0, 1.0)
				r.set_locomotion(v, 9.0)
				r.rotation.y += 0.35 * DT
				r.position += r.global_transform.basis * Vector3(0, 0, -v * DT)
				r.position.y = hf.call(r.position.x, r.position.z), 240, 3, hf)
		_run(name, "slope idle", kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
			r.position = Vector3(1.7, hf.call(1.7, -2.1), -2.1)
			r.rotation.y = 0.8, 120, 6, hf)
	for a in act_info:
		var an: String = a
		if only != "" and only != an and only != "actions":
			continue
		var info: Array = act_info[an]
		var frames := int(float(info[0]) * 2.0 / DT) + 20 if bool(info[1]) else int((float(info[0]) + 0.35) / DT)
		var sides := [1.0, -1.0] if an in ["death", "hit", "stagger", "thrash"] else [0.0]
		for sd in sides:
			var side: float = sd
			_run(name, an + ("" if side == 0.0 else (" R" if side > 0.0 else " L")), kind, variant, mesh_data, stats, func(r: Rig, i: int) -> void:
				if i == 0:
					if side != 0.0 and r.has_method("set_hit_dir"):
						r.call("set_hit_dir", Vector3(side, 0, 0))
					r.play(an), frames, 2)
	lines.append("%s: %d samples, %d with issues" % [name, stats["samples"], stats["bad"]])
	total_samples += int(stats["samples"])
	total_bad += int(stats["bad"])


func _spawn(kind: String, variant: int) -> Rig:
	var r := PB.make(kind, variant)
	if r == null:
		return null
	add_child(r)
	r.process_mode = Node.PROCESS_MODE_DISABLED
	r.q.always_pose = true
	return r


func _despawn(r: Rig) -> void:
	remove_child(r)
	r.free()


## Simulates `frames` steps of 1/60 s; `drive` is called before each step; checks every `every` frames.
func _run(name: String, label: String, kind: String, variant: int, md: Dictionary, stats: Dictionary, drive: Callable, frames: int, every: int, ground: Callable = Callable()) -> void:
	var r := _spawn(kind, variant)
	terrain = ground
	if ground.is_valid():
		r.set("ground_fn", ground)
	var vols: Array = r.call("clip_volumes")
	var worst := {}
	var bad := 0
	var n := 0
	var first_bad := -1.0
	for f in frames:
		drive.call(r, f)
		r._process(DT)
		if f % every != 0 or f < 6:
			continue
		n += 1
		var issues := _check_pose(r, md, vols)
		if not issues.is_empty():
			bad += 1
			if first_bad < 0.0:
				first_bad = f * DT
			for it in issues:
				var key: String = it[0]
				if not worst.has(key) or float(it[1]) > float(worst[key][0]):
					worst[key] = [it[1], f * DT]
	stats["samples"] += n
	stats["bad"] += bad
	if bad > 0 or verbose:
		var parts: Array[String] = []
		var keys := worst.keys()
		keys.sort_custom(func(x: String, y: String) -> bool: return float(worst[x][0]) > float(worst[y][0]))
		for k in keys.slice(0, 6):
			parts.append("%s %.3f m @%.2fs" % [k, worst[k][0], worst[k][1]])
		lines.append("  %s %-16s %d/%d bad  %s" % [name, label, bad, n, ", ".join(parts)])
	_despawn(r)


# --- geometry ----------------------------------------------------------------------------------------------

## Unique (position, weights) vertices of the rig's mesh with their part.
func _mesh_data(r: Rig) -> Dictionary:
	var q: RigWolf.Quadruped = r.q
	var arr := q.mesh.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var seen := {}
	var uv := PackedVector3Array()
	var ub := PackedInt32Array()
	var uw := PackedFloat32Array()
	var upart := PackedStringArray()
	for i in vs.size():
		var key := "%d,%d,%d,%d" % [roundi(vs[i].x * 500.0), roundi(vs[i].y * 500.0), roundi(vs[i].z * 500.0), bs[i * 4]]
		if seen.has(key):
			continue
		seen[key] = true
		uv.append(vs[i])
		var best := 0
		for k in 4:
			ub.append(bs[i * 4 + k])
			uw.append(ws[i * 4 + k])
			if ws[i * 4 + k] > ws[i * 4 + best]:
				best = k
		upart.append(_part_of(q, bs[i * 4 + best]))
	return {"v": uv, "b": ub, "w": uw, "part": upart}


func _part_of(q: RigWolf.Quadruped, b: int) -> String:
	if b < q.ns:
		return "torso"
	if b == q.B_NECK0 or b == q.B_NECK1:
		return "neck"
	if b >= q.B_HEAD and b <= q.B_EAR_R:
		return "head"
	if b >= q.B_LEG and b < q.B_TAIL:
		var i := (b - q.B_LEG) / 4
		return "leg%d_%d" % [i, (b - q.B_LEG) % 4]
	if b >= q.B_TAIL and b < q.B_EXTRA:
		return "tail"
	return "extra"


func _skin_mats(q: RigWolf.Quadruped) -> Array[Transform3D]:
	var m: Array[Transform3D] = []
	m.resize(q.bone_count)
	for b in q.bone_count:
		m[b] = q.xf[b] * q.rest[b].affine_inverse()
	return m


static func _skin_point(m: Array[Transform3D], p: Vector3, w: PackedFloat32Array) -> Vector3:
	var out := Vector3.ZERO
	var tot := 0.0
	var k := 0
	while k + 1 < w.size():
		out += (m[int(w[k])] * p) * w[k + 1]
		tot += w[k + 1]
		k += 2
	return out / maxf(tot, 1e-6)


static func seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(p2)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-9 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


## Issues of the current pose: Array of [kind, depth].
func _check_pose(r: Rig, md: Dictionary, vols: Array) -> Array:
	var q: RigWolf.Quadruped = r.q
	var m := _skin_mats(q)
	var issues: Array = []
	var gx: Transform3D = q.root.global_transform
	# ground (real skinned vertices) and the lowest point of each paw
	var vs: PackedVector3Array = md["v"]
	var bs: PackedInt32Array = md["b"]
	var ws: PackedFloat32Array = md["w"]
	var parts: PackedStringArray = md["part"]
	var low := {}
	var paw_min := [INF, INF, INF, INF]
	var torso_min := INF
	for i in vs.size():
		var p := Vector3.ZERO
		for k in 4:
			var w := ws[i * 4 + k]
			if w > 0.0:
				p += (m[bs[i * 4 + k]] * vs[i]) * w
		var part := parts[i]
		if terrain.is_valid():
			var wp := gx * p
			p.y = wp.y - float(terrain.call(wp.x, wp.z))
		if p.y < -GROUND_TOL:
			var d := -p.y
			var pk := part.get_slice("_", 0)
			if verbose:
				pk += ":b%d" % bs[i * 4]
			if d > float(low.get(pk, 0.0)):
				low[pk] = d
		if part.ends_with("_3"):
			var li := int(part.substr(3, 1))
			paw_min[li] = minf(paw_min[li], p.y)
		if part == "torso" or part == "neck" or part.ends_with("_0"):
			torso_min = minf(torso_min, p.y)
	for pk in low:
		issues.append(["below-ground(%s)" % pk, low[pk]])
	# a dead beast lies on the ground once the fall has settled (its body: torso, neck, thighs / shoulders)
	if r.has_method("is_dead") and bool(r.call("is_dead")) and (r.action == "" or r.ap() >= 0.85):
		if torso_min > CORPSE_TOL:
			issues.append(["corpse-floating", torso_min])
	# planted paws must touch the ground
	var gw := clampf(q.ch[RigWolf.Quadruped.GAIT], 0.0, 1.0)
	for i in 4:
		var o := RigWolf.Quadruped.LEG + i * RigWolf.Quadruped.LEG_N
		var lifted := q.ch[o + RigWolf.Quadruped.LY] > 0.01 or q.ch[o + RigWolf.Quadruped.LREL] > 0.05
		var stance := q.plant[i] > 0.95 or q.walk * gw < 0.05
		if stance and not lifted and float(paw_min[i]) > FLOAT_TOL:
			issues.append(["paw-floating(leg%d)" % i, float(paw_min[i])])
	# capsule cores
	var posed: Array = []
	for v in vols:
		posed.append([v["part"], _skin_point(m, v["a"], v["wa"]), _skin_point(m, v["b"], v["wb"]), float(v["r"])])
	for i in posed.size():
		var A: Array = posed[i]
		var pa: String = A[0]
		for j in range(i + 1, posed.size()):
			var B: Array = posed[j]
			var pb: String = B[0]
			var kind := _pair_kind(pa, pb)
			if kind == "":
				continue
			var d := seg_dist(A[1], A[2], B[1], B[2])
			var depth := float(A[3]) + float(B[3]) - d
			if depth > 0.004:
				issues.append([kind + ((" " + pa + "/" + pb) if verbose else ""), depth])
	return issues


## Which part pairs must stay apart (cores never overlapping); "" = allowed to overlap.
func _pair_kind(a: String, b: String) -> String:
	var la := a.begins_with("leg")
	var lb := b.begins_with("leg")
	if la and lb:
		var sa := int(a.get_slice("_", 1))
		var sb := int(b.get_slice("_", 1))
		var ia := int(a.substr(3, 1))
		var ib := int(b.substr(3, 1))
		if ia == ib or sa < 1 or sb < 1:
			return ""
		return "legs-cross(%d-%d)" % [mini(ia, ib), maxi(ia, ib)]
	if lb and not la:
		var t := a
		a = b
		b = t
		la = true
	if la:
		var seg := int(a.get_slice("_", 1))
		var leg := int(a.substr(3, 1))
		if b == "torso":
			return "leg-in-body(%d)" % leg if seg >= 1 else ""
		if b == "head":
			return "head-in-leg(%d)" % leg
		if b == "neck":
			return "neck-in-leg(%d)" % leg if seg >= 1 else ""
		if b.begins_with("tail"):
			return "tail-in-leg(%d)" % leg if leg >= 2 and int(b.substr(4)) >= 1 else ""
		if b.begins_with("tusk"):
			return "tusk-in-leg(%d)" % leg
		if b.begins_with("mane"):
			return "paw-in-mane(%d)" % leg if seg >= 2 else ""
		return ""
	if (a == "head" and b == "torso") or (a == "torso" and b == "head"):
		return "head-in-body"
	if (a.begins_with("tail") and b == "torso") or (b.begins_with("tail") and a == "torso"):
		var tn := int((a if a.begins_with("tail") else b).substr(4))
		return "tail-in-body" if tn >= 2 else ""
	return ""
