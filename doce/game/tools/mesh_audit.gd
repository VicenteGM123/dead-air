extends Node3D
## MESH AUDIT: open (one-sided) surfaces and what can be seen through them (the client's "roofs look transparent
## from below"). Every building and prop model the world uses is built here (every kind, variant and seed the
## village, the props and the passage ask for) and checked two ways:
##
##  1. TOPOLOGY. Vertices are welded (1 mm), and the edges used by ONE triangle only are the open boundary: a
##     surface that is not closed (a box without its bottom: ModelsNature.box5, a single-sided gable triangle...).
##     The open edges are grouped by the connected surface ("part") they belong to.
##  2. SEEING THROUGH. shaders/lowpoly.gdshader is cull_back: a triangle seen from its back is not drawn, so the
##     viewer looks through it at whatever lies behind. Rays are cast from cameras on rings round the model (0.4,
##     1.7, 3.5 and 7 m high; 0.8, 3 and 8 m outside its bounding box; the low ones look UP at the eaves) towards
##     random points of its bounding box. A ray is a DEFECT when the nearest triangle it meets is seen from the
##     back (and is above the ground, y = 0, which hides everything below it). Exact coincident pairs of opposite
##     triangles (cloth drawn on both faces) are two-sided, not a defect. A closed solid with outward faces has
##     no defect rays at all; the parts the defect rays hit are the surfaces that need their other face.
##
##   godot --headless --path . res://tools/mesh_audit.tscn --quit-after 100000 -- [only=house,stall] [all=1]
##         [world=1] [nomodels=1] [rays=48] [az=24] [verbose=1] [list=1] [selftest=1] [out=/abs/report.txt]
##   selftest=1 first checks the tool on shapes whose answer is known (a hollow slab, a closed slab, a single sheet,
##   a two-sided sheet, an inside-out box): "AUDIT SELFTEST ... PASS|FAIL".
##   world=1 also builds the whole island and audits the village mesh round the houses, stalls, well, shrine,
##   gate, goat pen, pier and beach (what nemea_village.gd builds inline). all=1 adds the library models the
##   world does not place (PHAROS leftovers: pharos, farm, dock, tower, wall, barracks, every other prop).
## Prints "AUDIT ..." lines and "AUDIT SUMMARY"; exit status is not used, the world models' verdict is the line
## "AUDIT RESULT see_through_models=N" (0 = nothing in the world can be seen through).

const L := preload("res://scripts/world/nemea_layout.gd")

const WELD := 0.001
const CELL := 0.004
## A model passes when fewer than this share of the rays that reach it are defects.
const PASS_PCT := 0.02
const HEIGHTS := [0.3, 1.0, 1.7, 3.5, 7.0]
const OFFSETS := [0.8, 3.0, 8.0]

var _entries: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _verbose := false
var _az := 24
var _rays := 48
var _out: PackedStringArray = PackedStringArray()
## World pass only: the physics space and the layer the terrain is moved to (rays that reach a hit through the
## terrain are hidden by the ground).
var _space: PhysicsDirectSpaceState3D = null
var _heightfield_world: Node3D = null # the cave: the ground is the heightfield (its floor), checked by sampling along the ray
var _cave_ranges: Array = [] # [name, first triangle] of the merged cave meshes (to say which mesh a part belongs to)
const TERRAIN_LAYER := 1 << 10


func _ready() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print(s)
	_out.append(s)


# --- registry ----------------------------------------------------------------------------------------------------

func _add(label: String, group: String, in_world: bool, build: Callable, owner_s: String = "") -> void:
	_entries.append({"name": label, "group": group, "world": in_world, "build": build, "owner": owner_s})


func _register() -> void:
	# Houses exactly as the village builds them: order of L.HOUSES, seed 700 + 17 i, level 2 for the two-storey kind.
	var i := 0
	for hd in L.HOUSES:
		var lv := 2 if int(hd[2]) == 1 else 1
		var sv := 700 + i * 17
		_add("house%d_%02d" % [lv, i], "house", true, func() -> Variant: return ModelsBuildings.building("house", lv, sv)["mesh"])
		i += 1
	# The three market stalls (plaza angles 30, 108, 190), their awning stripes.
	var stripes := [Pal.CREST, Pal.AEGEAN, Pal.GOLD_DARK]
	for k in 3:
		var col: Color = stripes[k]
		_add("stall_%d" % k, "stall", true, func() -> Variant: return ModelsBuildings.market_stall(500 + k, col))
	# Plaza and village props.
	_add("well", "plaza", true, func() -> Variant: return ModelsNature.well(5))
	_add("herm_shrine", "plaza", true, func() -> Variant: return ModelsNature.herm_shrine(9))
	_add("bench", "plaza", true, func() -> Variant: return _with_builder(func(mb: MeshBuilder) -> void: ModelsBuildings._bench(mb, Vector3.ZERO)))
	_add("crate", "beach", true, func() -> Variant: return _with_builder(func(mb: MeshBuilder) -> void: ModelsBuildings._crate(mb, ModelsNature.make_rng(1), Vector3.ZERO, 0.6)))
	_add("pot_plant", "plaza", true, func() -> Variant: return _with_builder(func(mb: MeshBuilder) -> void: ModelsBuildings._pot_plant(mb, ModelsNature.make_rng(2), Vector3.ZERO, 1.2)))
	# Fences, terraces, ruins, the passage, the farm's wall and threshing floor, the story props.
	for v in 3:
		var sv := 61 * v + 60
		_add("wood_fence_%d" % v, "fence", true, func() -> Variant: return ModelsNature.wood_fence(sv))
		_add("retaining_wall_%d" % v, "terrace", true, func() -> Variant: return ModelsNature.retaining_wall(sv))
	_add("terrace_wall", "farm", true, func() -> Variant: return ModelsNature.terrace_wall(60))
	_add("threshing_floor", "farm", true, func() -> Variant: return ModelsNature.threshing_floor(60))
	_add("ruin_column", "ruin", true, func() -> Variant: return ModelsNature.ruin_column(60))
	for s in [1220, 1235]:
		_add("bridge_end_%d" % s, "passage", true, func() -> Variant: return ModelsNature.bridge_end(s))
	for v in 2:
		var sv := 61 * v + 60
		_add("driftwood_%d" % v, "beach", true, func() -> Variant: return ModelsNature.driftwood(sv))
		_add("bones_%d" % v, "story", true, func() -> Variant: return ModelsNature.bones(sv))
	# Lane B's boats (reported here, edited there).
	_add("boat_small_4", "boat", true, func() -> Variant: return ModelsNature.boat_small(4), "lane B")
	_add("boat_small_7", "boat", true, func() -> Variant: return ModelsNature.boat_small(7), "lane B")
	_add("ship_galley", "boat", true, func() -> Variant: return ModelsBuildings.ship(0, 21)["mesh"], "lane B")
	_add("ship_merchant", "boat", true, func() -> Variant: return ModelsBuildings.ship(1, 33)["mesh"], "lane B")
	# Node-built props (scripts/props): the altar, a ring stone, the boulder.
	_add("altar", "prop", true, func() -> Variant: return _node_mesh(Altar.new()), "CORE")
	_add("chain_ring_stone", "prop", true, func() -> Variant: return _node_mesh(ChainRing.new(3.4)), "CORE")
	_add("chain_ring_wall", "prop", true, func() -> Variant: return _node_mesh(ChainRing.new(0.0, true)), "CORE")
	if Game.arg_on("all"):
		_register_library()


## Models the world does not place: every building type and level, and every other prop builder of ModelsNature.
func _register_library() -> void:
	for type_s in ModelsBuildings.LEVELS:
		for lv in int(ModelsBuildings.LEVELS[type_s]):
			var t: String = type_s
			var l := lv + 1
			_add("lib_%s_%d" % [t, l], "library", false, func() -> Variant: return ModelsBuildings.building(t, l, 7)["mesh"])
	var done := {}
	for e in _entries:
		done[e["name"]] = true
	var ns: Script = load("res://scripts/gfx/models_nature.gd")
	for m in ns.get_script_method_list():
		var fn: String = m["name"]
		if fn.begins_with("_") or fn.begins_with("add_") or not (int(m["flags"]) & METHOD_FLAG_STATIC):
			continue
		if (m["args"] as Array).size() != 1 or String((m["return"] as Dictionary).get("class_name", "")) != "ArrayMesh":
			continue
		if fn in ["material_for", "casts_shadow", "info", "make_rng"]:
			continue
		var f: String = fn
		var lab := "lib_" + f
		if done.has(lab):
			continue
		_add(lab, "library", false, func() -> Variant: return ns.call(f, 60))


## Runs `fill` on a fresh MeshBuilder (with the same shading noise the models use) and returns the mesh.
func _with_builder(fill: Callable) -> Mesh:
	var mb := MeshBuilder.new(3)
	mb.vary = 0.03
	fill.call(mb)
	return mb.commit()


## All the mesh children of a node (props built in _ready) merged into one ArrayMesh in the node's space.
func _node_mesh(n: Node3D) -> Mesh:
	add_child(n)
	var vs := PackedVector3Array()
	var cs := PackedColorArray()
	_gather(n, Transform3D.IDENTITY, vs, cs)
	n.queue_free()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_COLOR] = cs
	var m := ArrayMesh.new()
	if vs.size() >= 3:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _gather(n: Node, xf: Transform3D, vs: PackedVector3Array, cs: PackedColorArray) -> void:
	var here := xf
	if n is Node3D and n != self:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh and not (n as MeshInstance3D).mesh is QuadMesh:
		var mesh: ArrayMesh = (n as MeshInstance3D).mesh
		var faces := mesh.get_faces()
		var col := _tri_colors(mesh, faces.size() / 3)
		for i in faces.size():
			vs.append(here * faces[i])
			cs.append(col[i / 3])
	for ch in n.get_children():
		_gather(ch, here, vs, cs)


# --- run ---------------------------------------------------------------------------------------------------------

func _run() -> void:
	_verbose = Game.arg_on("verbose")
	_az = int(Game.arg("az", "24"))
	_rays = int(Game.arg("rays", "48"))
	if Game.arg_on("selftest"):
		_selftest()
	_register()
	if Game.arg_on("list"):
		for e in _entries:
			_p("AUDIT LIST %-22s group=%-8s world=%s %s" % [e["name"], e["group"], str(e["world"]), e["owner"]])
		_finish()
		return
	var only := String(Game.arg("only", "")).split(",", false)
	var t0 := Time.get_ticks_msec()
	for e in _entries:
		if Game.arg_on("nomodels"):
			break
		if not only.is_empty():
			var ok := false
			for o in only:
				if String(e["name"]).contains(o) or String(e["group"]) == o:
					ok = true
			if not ok:
				continue
		var mesh: Mesh = e["build"].call()
		if mesh == null or mesh.get_surface_count() == 0:
			_p("AUDIT SKIP %s (empty)" % e["name"])
			continue
		var row := _audit(String(e["name"]), mesh)
		row["group"] = e["group"]
		row["world"] = e["world"]
		row["owner"] = e["owner"]
		_rows.append(row)
		_print_row(row)
	if Game.arg_on("world"):
		await _audit_world()
	_summary(Time.get_ticks_msec() - t0)
	_finish()


func _finish() -> void:
	var path := String(Game.arg("out", ""))
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_out) + "\n")
			f.close()
	get_tree().quit()


# --- the audit of one mesh -----------------------------------------------------------------------------------------

## Everything that does not depend on the cameras: triangles, normals, colours, welded topology, parts, twins.
func _prepare(mesh: Mesh) -> Dictionary:
	var faces := mesh.get_faces()
	var n_tri := faces.size() / 3
	var col := _tri_colors(mesh, n_tri)
	var nrm := PackedVector3Array()
	nrm.resize(n_tri)
	for t in n_tri:
		var a := faces[t * 3]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		# Godot's front face is clockwise: (c - a) x (b - a) points out of the front.
		var n := (c - a).cross(b - a)
		nrm[t] = n.normalized() if n.length_squared() > 1e-14 else Vector3.ZERO
	var topo := _topology(faces)
	var ctx := {
		"mesh": mesh, "faces": faces, "n_tri": n_tri, "col": col, "nrm": nrm, "topo": topo,
		"two": _two_sided(topo["vid"], n_tri), "tm": mesh.generate_triangle_mesh(),
	}
	_parts(ctx)
	return ctx


## Casts the rays of `cams` ({pos, box, ground}) and counts the back-face hits. Returns the counters and the
## per-triangle back-view hits.
func _cast(ctx: Dictionary, cams: Array, check_inside: bool) -> Dictionary:
	var tm: TriangleMesh = ctx["tm"]
	var nrm: PackedVector3Array = ctx["nrm"]
	var two: PackedByteArray = ctx["two"]
	var back := PackedInt32Array()
	back.resize(int(ctx["n_tri"]))
	var front := PackedInt32Array()
	front.resize(int(ctx["n_tri"]))
	var samples := {}
	var rays_model := 0
	var rays_def := 0
	var rays_up := 0
	var rays_up_def := 0
	_rng.seed = 1234
	for cam_d in cams:
		var cam: Vector3 = cam_d["pos"]
		var box: AABB = cam_d["box"]
		var ground: float = cam_d["ground"]
		if check_inside and _inside(tm, nrm, cam):
			continue
		# this camera's hits, kept apart until we know it is not standing inside a solid
		var hits_f := PackedInt32Array()
		var hits_b := PackedInt32Array()
		var back_far := 0.0
		var ups := 0
		var ups_def := 0
		var smp: Array = []
		for k in _rays:
			var tgt := Vector3(
				_rng.randf_range(box.position.x, box.end.x),
				_rng.randf_range(maxf(box.position.y, ground), maxf(box.end.y, ground + 0.1)),
				_rng.randf_range(box.position.z, box.end.z))
			var dir := tgt - cam
			var dl := dir.length()
			if dl < 0.05:
				continue
			dir /= dl
			var h: Dictionary = tm.intersect_ray(cam, dir)
			if h.is_empty():
				continue
			var hp: Vector3 = h["position"]
			var dist := cam.distance_to(hp)
			if _space != null and dist > dl + 2.0:
				continue # past the region of interest (another house, the paving...)
			if _space != null:
				# the island: the terrain (moved to its own layer) hides what lies behind or under it
				var tq := PhysicsRayQueryParameters3D.create(cam, hp - dir * 0.02, TERRAIN_LAYER)
				if not _space.intersect_ray(tq).is_empty():
					continue
				if _heightfield_world != null:
					var under := false
					for si in range(1, 9):
						var sp := cam + dir * (dist * float(si) / 9.0)
						if sp.y < float(_heightfield_world.call("height_at", sp.x, sp.z)) - 0.05:
							under = true
							break
					if under:
						continue
			else:
				if hp.y < ground + 0.005:
					continue # the ground is in front of it
				if dir.y < 0.0 and (cam.y - ground) / -dir.y < dist - 0.002:
					continue # the ray reaches the ground first
			var up := dir.y > 0.15
			if up:
				ups += 1
			var fi: int = h["face_index"]
			if nrm[fi].dot(dir) > 1e-4 and two[fi] == 0:
				hits_b.append(fi)
				back_far = maxf(back_far, dist)
				if up:
					ups_def += 1
				if _verbose and smp.size() < 6:
					smp.append([fi, cam, dir, hp])
			else:
				hits_f.append(fi)
		var n_cam := hits_f.size() + hits_b.size()
		# The island's placement rings do not know what stands where: a camera inside a small solid (a post, a rock)
		# meets only back faces, all within a metre or two. (A camera under a roof also meets only back faces, but from
		# further away, and that is exactly the defect to count; in a model audit the cameras are outside the box.)
		if check_inside and n_cam >= 8 and hits_f.is_empty() and back_far < 2.0:
			continue
		rays_model += n_cam
		rays_def += hits_b.size()
		rays_up += ups
		rays_up_def += ups_def
		for fi in hits_b:
			back[fi] += 1
		for fi in hits_f:
			front[fi] += 1
		for sm: Array in smp:
			var fi2: int = sm[0]
			if (samples.get(fi2, []) as Array).size() < 2:
				samples[fi2] = samples.get(fi2, []) + [[sm[1], sm[2], sm[3]]]
	return {"rays": rays_model, "defects": rays_def, "up": rays_up, "up_def": rays_up_def, "back": back, "front": front, "samples": samples}


## The report row of one mesh from its context and the result of _cast.
func _row(label: String, ctx: Dictionary, res: Dictionary) -> Dictionary:
	var back: PackedInt32Array = res["back"]
	var parts: Array = ctx["parts"]
	var part_of: PackedInt32Array = ctx["part_of"]
	var front: PackedInt32Array = res["front"]
	for p in parts:
		p["rays"] = 0
		p["front"] = 0
		p["samples"] = []
	for t in back.size():
		var pd: Dictionary = parts[part_of[t]]
		pd["front"] = int(pd["front"]) + front[t]
		if back[t] > 0:
			pd["rays"] = int(pd["rays"]) + back[t]
			if (res["samples"] as Dictionary).has(t) and (pd["samples"] as Array).size() < 3:
				(pd["samples"] as Array).append_array(res["samples"][t])
	var open_total := 0
	var open_exposed := 0
	var open_buried := 0
	var exposed_parts := 0
	for p in parts:
		open_total += int(p["open"])
		if int(p["open"]) > 0:
			if float(p["ymax"]) < 0.03:
				open_buried += int(p["open"])
			elif int(p["rays"]) > 0:
				open_exposed += int(p["open"])
				exposed_parts += 1
	var topo: Dictionary = ctx["topo"]
	return {
		"name": label, "tris": ctx["n_tri"], "open": open_total, "open_exposed": open_exposed, "open_buried": open_buried,
		"exposed_parts": exposed_parts, "rays": res["rays"], "defects": res["defects"],
		"pct": 100.0 * float(res["defects"]) / maxf(1.0, float(res["rays"])),
		"up": res["up"], "up_def": res["up_def"],
		"up_pct": 100.0 * float(res["up_def"]) / maxf(1.0, float(res["up"])),
		"folds": topo["folds"], "nonmanifold": topo["nonmanifold"], "parts": parts.duplicate(), "aabb": (ctx["mesh"] as Mesh).get_aabb(),
	}


func _audit(label: String, mesh: Mesh) -> Dictionary:
	var ctx := _prepare(mesh)
	var res := _cast(ctx, _model_cameras(mesh.get_aabb()), false)
	return _row(label, ctx, res)


func _print_row(r: Dictionary) -> void:
	_p("AUDIT %-20s tris=%5d open_edges=%4d (exposed %4d in %2d parts, buried %4d) see_through=%6.3f%% (%d of %d rays) looking_up=%6.3f%% folds=%d" % [
		r["name"], r["tris"], r["open"], r["open_exposed"], r["exposed_parts"], r["open_buried"], r["pct"], r["defects"], r["rays"], r["up_pct"], r["folds"]])
	var shown := 0
	var parts: Array = r["parts"]
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rays"]) > int(b["rays"]))
	for p in parts:
		if int(p["rays"]) == 0 and not (_verbose and int(p["open"]) > 0):
			continue
		if shown >= (40 if _verbose else 8):
			break
		shown += 1
		var bbx: AABB = p["box"]
		_p("      part %-4d tris=%3d open=%3d back=%5d front=%5d  at (%.2f %.2f %.2f) size (%.2f %.2f %.2f) colour #%s  %s" % [
			p["id"], p["tris"], p["open"], p["rays"], p["front"], bbx.get_center().x, bbx.get_center().y, bbx.get_center().z,
			bbx.size.x, bbx.size.y, bbx.size.z, (p["color"] as Color).to_html(false), "SEEN FROM BEHIND" if int(p["rays"]) > 0 else "hidden"])
		if _verbose:
			for sm: Array in (p["samples"] as Array).slice(0, 2):
				_p("          e.g. camera (%.2f %.2f %.2f) looking (%.2f %.2f %.2f) meets the back at (%.2f %.2f %.2f)" % [
					sm[0].x, sm[0].y, sm[0].z, sm[1].x, sm[1].y, sm[1].z, sm[2].x, sm[2].y, sm[2].z])


func _summary(ms: int) -> void:
	var world_bad := 0
	var world_n := 0
	var tris := 0
	var open_exposed := 0
	var lib_bad := 0
	_p("AUDIT SUMMARY (%d ms)  model                tris   open  exposed  see_through%%  looking_up%%" % ms)
	for r in _rows:
		if bool(r.get("world", false)):
			world_n += 1
			tris += int(r["tris"])
			open_exposed += int(r["open_exposed"])
		var bad := float(r["pct"]) > PASS_PCT
		if bad:
			if bool(r.get("world", false)):
				world_bad += 1
			else:
				lib_bad += 1
		_p("AUDIT %s %-22s %5d %6d %8d %12.3f %12.3f  %s" % ["FAIL" if bad else "ok  ", r["name"], r["tris"], r["open"], r["open_exposed"], r["pct"], r["up_pct"], r.get("owner", "")])
	_p("AUDIT TOTAL world_models=%d tris=%d open_exposed_edges=%d library_models_with_defects=%d" % [world_n, tris, open_exposed, lib_bad])
	_p("AUDIT RESULT see_through_models=%d" % world_bad)


# --- cameras -------------------------------------------------------------------------------------------------------

func _model_cameras(bb: AABB) -> Array:
	var out: Array = []
	var c := bb.get_center()
	var hx := bb.size.x * 0.5 + 0.05
	var hz := bb.size.z * 0.5 + 0.05
	var box := bb.grow(0.05)
	for k in _az:
		var a := TAU * (float(k) + 0.5) / float(_az)
		var d := Vector2(sin(a), cos(a))
		var t := INF
		if absf(d.x) > 1e-4:
			t = minf(t, hx / absf(d.x))
		if absf(d.y) > 1e-4:
			t = minf(t, hz / absf(d.y))
		for off: float in OFFSETS:
			for h: float in HEIGHTS:
				if h > bb.end.y + 5.0:
					continue
				out.append({"pos": Vector3(c.x + d.x * (t + off), h, c.z + d.y * (t + off)), "box": box, "ground": 0.0})
	return out


func _roi_cameras(rois: Array, world: Node3D) -> Array:
	var out: Array = []
	for roi: Dictionary in rois:
		var c: Vector3 = roi["c"]
		var r: float = roi["r"]
		var box := AABB(Vector3(c.x - r, c.y, c.z - r), Vector3(r * 2.0, float(roi.get("h", 5.0)), r * 2.0))
		# where the cameras stand: a ring round the region, or the floor points the region names (the cave's tunnels)
		var pts: Array = []
		if roi.has("pts"):
			pts = roi["pts"]
		else:
			var n := int(roi.get("az", 16))
			for k in n:
				var a := TAU * (float(k) + 0.5) / float(n)
				for rm: float in [0.7, 1.15, 1.8]:
					pts.append(Vector2(c.x + sin(a) * r * rm, c.z + cos(a) * r * rm))
		for pt: Vector2 in pts:
			var x := pt.x
			var z := pt.y
			var gy := 0.0
			if bool(roi.get("floor", false)):
				gy = float(world.call("height_at", x, z)) # under a roof (the cave): the floor, not what a ray from the sky meets
			else:
				# where a person would stand there: the top solid (paving, deck, ground), not a roof or an awning
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, c.y + 40.0, z), Vector3(x, c.y - 30.0, z), 1 | TERRAIN_LAYER)
				var hit := _space.intersect_ray(q)
				if hit.is_empty():
					continue
				gy = (hit["position"] as Vector3).y
				if gy > float(world.call("height_at", x, z)) + 0.9:
					continue
			for h: float in [0.3, 1.0, 1.7, 3.5]:
				out.append({"pos": Vector3(x, gy + h, z), "box": box, "ground": gy})
	return out


## A camera inside a solid (a rock, a post: the placement rings do not know what stands where): most of the six axis
## rays meet a back face first.
func _inside(tm: TriangleMesh, nrm: PackedVector3Array, cam: Vector3) -> bool:
	var backs := 0
	var fronts := 0
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var h: Dictionary = tm.intersect_ray(cam, d)
		if h.is_empty():
			continue
		if nrm[int(h["face_index"])].dot(d) <= 0.0:
			fronts += 1
		else:
			backs += 1
	return backs >= 4 and fronts <= 1


# --- topology --------------------------------------------------------------------------------------------------------

## Per-triangle colour (the vertex colour of its first vertex), in the order of Mesh.get_faces().
func _tri_colors(mesh: Mesh, n_tri: int) -> PackedColorArray:
	var out := PackedColorArray()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var cl: Variant = a[Mesh.ARRAY_COLOR]
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n := (idx as PackedInt32Array).size() / 3 if (idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0) else v.size() / 3
		for t in n:
			var vi: int = (idx as PackedInt32Array)[t * 3] if (idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0) else t * 3
			out.append((cl as PackedColorArray)[vi] if cl is PackedColorArray else Color.WHITE)
	while out.size() < n_tri:
		out.append(Color.WHITE)
	return out


## Welds the vertices and counts the uses of each edge. Returns {vid, edge_n, edge_tri, folds, nonmanifold}.
func _topology(faces: PackedVector3Array) -> Dictionary:
	var cells := {}
	var upos := PackedVector3Array()
	var vid := PackedInt32Array()
	vid.resize(faces.size())
	for i in faces.size():
		var p := faces[i]
		var cx := floori(p.x / CELL)
		var cy := floori(p.y / CELL)
		var cz := floori(p.z / CELL)
		var found := -1
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var lst: Variant = cells.get(Vector3i(cx + dx, cy + dy, cz + dz))
					if lst == null:
						continue
					for u: int in lst:
						if upos[u].distance_squared_to(p) <= WELD * WELD:
							found = u
							break
					if found >= 0:
						break
				if found >= 0:
					break
			if found >= 0:
				break
		if found < 0:
			found = upos.size()
			upos.append(p)
			var key := Vector3i(cx, cy, cz)
			var l: Variant = cells.get(key)
			if l == null:
				cells[key] = [found]
			else:
				(l as Array).append(found)
		vid[i] = found
	var edge_n := {}
	var edge_tri := {}
	var edge_dir := {}
	for t in faces.size() / 3:
		var ids := [vid[t * 3], vid[t * 3 + 1], vid[t * 3 + 2]]
		if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
			continue
		for e in 3:
			var a: int = ids[e]
			var b: int = ids[(e + 1) % 3]
			var key := (mini(a, b) << 32) | maxi(a, b)
			edge_n[key] = int(edge_n.get(key, 0)) + 1
			edge_dir[key] = int(edge_dir.get(key, 0)) + (1 if a < b else -1)
			if not edge_tri.has(key):
				edge_tri[key] = t
	var folds := 0
	var nonman := 0
	for key in edge_n:
		var n: int = edge_n[key]
		if n == 2 and absi(int(edge_dir[key])) == 2:
			folds += 1
		elif n > 2:
			nonman += 1
	return {"vid": vid, "edge_n": edge_n, "edge_tri": edge_tri, "folds": folds, "nonmanifold": nonman, "upos": upos}


## True for the triangles that have an exact opposite twin (the same three welded vertices, reversed): cloth, plates
## and awnings drawn on both faces.
func _two_sided(vid: PackedInt32Array, n_tri: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n_tri)
	var seen := {}
	for t in n_tri:
		var ids := [vid[t * 3], vid[t * 3 + 1], vid[t * 3 + 2]]
		var sorted := ids.duplicate()
		sorted.sort()
		var key := Vector3i(sorted[0], sorted[1], sorted[2])
		# orientation: 1 when the cyclic order equals the sorted order
		var fwd := 1 if (ids[0] == sorted[0] and ids[1] == sorted[1]) or (ids[1] == sorted[0] and ids[2] == sorted[1]) or (ids[2] == sorted[0] and ids[0] == sorted[1]) else -1
		if seen.has(key):
			var o: Array = seen[key]
			if int(o[1]) != fwd:
				out[t] = 1
				out[int(o[0])] = 1
		else:
			seen[key] = [t, fwd]
	return out


## Connected surfaces: triangles joined by shared (welded) edges. Fills ctx.parts (id, tris, open edges, box, colour,
## ymax) and ctx.part_of (triangle -> index in parts).
func _parts(ctx: Dictionary) -> void:
	var faces: PackedVector3Array = ctx["faces"]
	var col: PackedColorArray = ctx["col"]
	var topo: Dictionary = ctx["topo"]
	var n_tri: int = ctx["n_tri"]
	var parent := PackedInt32Array()
	parent.resize(n_tri)
	for t in n_tri:
		parent[t] = t
	var edge_tri: Dictionary = topo["edge_tri"]
	var edge_n: Dictionary = topo["edge_n"]
	var vid: PackedInt32Array = topo["vid"]
	var first := {}
	for t in n_tri:
		var ids := [vid[t * 3], vid[t * 3 + 1], vid[t * 3 + 2]]
		if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
			continue
		for e in 3:
			var a: int = ids[e]
			var b: int = ids[(e + 1) % 3]
			var key := (mini(a, b) << 32) | maxi(a, b)
			if first.has(key):
				var ra := _find(parent, t)
				var rb := _find(parent, int(first[key]))
				if ra != rb:
					parent[ra] = rb
			else:
				first[key] = t
	var index_of := {}
	var parts: Array = []
	var part_of := PackedInt32Array()
	part_of.resize(n_tri)
	for t in n_tri:
		var r := _find(parent, t)
		if not index_of.has(r):
			index_of[r] = parts.size()
			parts.append({"id": r, "tris": 0, "open": 0, "rays": 0, "ymax": -INF, "color": col[t], "box": AABB(faces[t * 3], Vector3.ZERO)})
		var pi: int = index_of[r]
		part_of[t] = pi
		var p: Dictionary = parts[pi]
		p["tris"] = int(p["tris"]) + 1
		for k in 3:
			var v := faces[t * 3 + k]
			p["ymax"] = maxf(float(p["ymax"]), v.y)
			p["box"] = (p["box"] as AABB).expand(v)
	for key in edge_n:
		if int(edge_n[key]) == 1:
			var t: int = edge_tri[key]
			var p: Dictionary = parts[part_of[t]]
			p["open"] = int(p["open"]) + 1
	ctx["parts"] = parts
	ctx["part_of"] = part_of


func _find(parent: PackedInt32Array, x: int) -> int:
	var r := x
	while parent[r] != r:
		r = parent[r]
	var c := x
	while parent[c] != r:
		var nx := parent[c]
		parent[c] = r
		c = nx
	return r


# --- the island's own village mesh -----------------------------------------------------------------------------------

func _audit_world() -> void:
	# Only the village is needed: no meadow, wheat or fauna (they cost minutes in software).
	for k in ["fauna", "grass", "wheat"]:
		if not Game.has_arg(k):
			Game.args[k] = "0"
	var world := World.new()
	add_child(world)
	world.build(int(Game.arg("seed", "7")))
	# the terrain alone on its own layer, to tell what the ground hides
	(world.terrain_body as StaticBody3D).collision_layer = TERRAIN_LAYER
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	if _verbose:
		for k in [0.0, 3.0, 6.0, 7.5, 9.0, 10.0, 12.0]:
			for a_deg in [0.0, 90.0, 180.0, 270.0]:
				var a := deg_to_rad(a_deg)
				var px: float = L.PLAZA.x + cos(a) * k
				var pz: float = L.PLAZA.y + sin(a) * k
				var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(px, 40, pz), Vector3(px, -10, pz), 1 | TERRAIN_LAYER))
				_p("AUDIT PLAZA r=%.1f az=%d terrain=%.3f stand=%.3f" % [k, int(a_deg), world.height_at(px, pz), (hit["position"] as Vector3).y if not hit.is_empty() else -99.0])
	var vm: MeshInstance3D = world.get_node_or_null("Village")
	if vm == null:
		_p("AUDIT WORLD no Village mesh")
		return
	var rois: Array = []
	var v: RefCounted = world.village
	var hi := 0
	for h in v.houses:
		var p: Vector3 = h["pos"]
		rois.append({"name": "house%d_%02d" % [2 if int(h["kind"]) == 1 else 1, hi], "c": p, "r": 6.0 * float(h["scale"]), "h": 9.0, "az": 20})
		hi += 1
	var plaza := L.PLAZA
	var pc := world.ground(Vector3(plaza.x, 0, plaza.y))
	var ang := [30.0, 108.0, 190.0]
	for k in 3:
		var a := deg_to_rad(float(ang[k]))
		var sp := world.ground(Vector3(plaza.x + cos(a) * 7.0, 0, plaza.y + sin(a) * 7.0))
		rois.append({"name": "stall_%d" % k, "c": sp, "r": 3.2, "h": 3.2, "az": 16})
	rois.append({"name": "well", "c": world.ground(Vector3(L.WELL.x, 0, L.WELL.y)), "r": 2.6, "h": 2.4, "az": 12})
	rois.append({"name": "shrine", "c": world.ground(Vector3(L.SHRINE.x, 0, L.SHRINE.y)), "r": 2.4, "h": 2.4, "az": 12})
	rois.append({"name": "plaza_rim", "c": pc, "r": 9.5, "h": 2.5, "az": 24})
	rois.append({"name": "north_gate", "c": world.ground(Vector3(-4.0, 0, 54.0)), "r": 6.0, "h": 3.2, "az": 16})
	rois.append({"name": "gate_leaf", "c": world.ground(Vector3(-8.2, 0, 51.5)), "r": 2.4, "h": 2.0, "az": 12})
	rois.append({"name": "goat_pen", "c": world.ground(Vector3(L.GOAT_PEN.x, 0, L.GOAT_PEN.y)), "r": 7.0, "h": 2.4, "az": 20})
	for zz in [108.0, 122.0, 136.0]:
		rois.append({"name": "pier_%d" % int(zz), "c": Vector3(L.PIER_A.x, L.PIER_DECK, zz), "r": 5.0, "h": 3.5, "az": 16})
	rois.append({"name": "beach_nets", "c": world.ground(Vector3(-11.0, 0, 101.0)), "r": 6.0, "h": 2.4, "az": 16})
	rois.append({"name": "beach_crates", "c": world.ground(Vector3(20.0, 0, 102.0)), "r": 3.0, "h": 1.6, "az": 12})
	await _run_rois("village", _prepare(vm.mesh), rois, world, "village")
	await _audit_cave(world)
	world.queue_free()

## Casts the rays of every region of interest at one big mesh (the village, the cave) and prints a row for each.
func _run_rois(prefix: String, ctx: Dictionary, rois: Array, world: Node3D, owner_s: String) -> void:
	var only := String(Game.arg("only", "")).split(",", false)
	_p("AUDIT WORLD %s mesh: %d tris, %d parts" % [prefix, int(ctx["n_tri"]), (ctx["parts"] as Array).size()])
	for roi: Dictionary in rois:
		if not only.is_empty():
			var ok := false
			for o in only:
				if String(roi["name"]).contains(o):
					ok = true
			if not ok:
				continue
		var res := _cast(ctx, _roi_cameras([roi], world), true)
		var row := _row(prefix + ":" + String(roi["name"]), ctx, res)
		row["group"] = prefix
		row["world"] = true
		row["owner"] = owner_s
		if _verbose:
			var all_parts: Array = (row["parts"] as Array).duplicate()
			all_parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rays"]) > int(b["rays"]))
			for p in all_parts.slice(0, 3):
				if int(p["rays"]) > 0:
					var pb: AABB = p["box"]
					var which_mesh := ""
					var pi: int = (ctx["parts"] as Array).find(p)
					for t0 in (ctx["part_of"] as PackedInt32Array).size():
						if (ctx["part_of"] as PackedInt32Array)[t0] == pi:
							for rg: Array in _cave_ranges:
								if t0 >= int(rg[1]):
									which_mesh = String(rg[0])
							break
					_p("      (any part) back=%d front=%d tris=%d open=%d at (%.2f %.2f %.2f) size (%.2f %.2f %.2f) colour #%s %s" % [p["rays"], p["front"], p["tris"], p["open"], pb.get_center().x, pb.get_center().y, pb.get_center().z, pb.size.x, pb.size.y, pb.size.z, (p["color"] as Color).to_html(false), which_mesh if prefix == "cave" else ""])
					for sm: Array in (p["samples"] as Array).slice(0, 2):
						_p("          e.g. camera (%.2f %.2f %.2f) looking (%.2f %.2f %.2f) meets the back at (%.2f %.2f %.2f)" % [sm[0].x, sm[0].y, sm[0].z, sm[1].x, sm[1].y, sm[1].z, sm[2].x, sm[2].y, sm[2].z])
					# its first triangles: where the winding points
					var fcs: PackedVector3Array = ctx["faces"]
					var pof: PackedInt32Array = ctx["part_of"]
					var shown_t := 0
					for t in pof.size():
						if pof[t] == (ctx["parts"] as Array).find(p):
							var a := fcs[t * 3]
							var b := fcs[t * 3 + 1]
							var c := fcs[t * 3 + 2]
							var nn := ((c - a).cross(b - a)).normalized()
							_p("          tri %d normal (%.2f %.2f %.2f) a=(%.2f %.2f %.2f)" % [t, nn.x, nn.y, nn.z, a.x, a.y, a.z])
							shown_t += 1
							if shown_t >= 6:
								break
		# only the parts near the region matter: keep the parts whose box touches it
		var near: Array = []
		var c: Vector3 = roi["c"]
		var rr: float = roi["r"] + 1.0
		for p in row["parts"]:
			var b: AABB = p["box"]
			if Vector2(b.get_center().x - c.x, b.get_center().z - c.z).length() < rr + b.size.length() * 0.5:
				near.append(p)
		var oe := 0
		var ox := 0
		var xp := 0
		for p in near:
			oe += int(p["open"])
			if int(p["open"]) > 0 and int(p["rays"]) > 0 and float(p["ymax"]) > 0.03 + c.y:
				ox += int(p["open"])
				xp += 1
		row["parts"] = near
		row["open"] = oe
		row["open_exposed"] = ox
		row["exposed_parts"] = xp
		row["open_buried"] = 0
		row["tris"] = int(ctx["n_tri"])
		_rows.append(row)
		_print_row(row)


## The Lion's cave: the lid (the roof of the arena, seen from below), the tunnel plugs, the mouth arches and the
## pillars, merged, with cameras on the floor looking up.
func _audit_cave(world: Node3D) -> void:
	var names := ["CaveLidUnder", "CaveLidTop", "TunnelPlugA", "TunnelTopA", "TunnelPlugB", "TunnelTopB", "MouthArchA", "MouthArchB", "CavePillars", "CaveFloor"]
	var vs := PackedVector3Array()
	var cs := PackedColorArray()
	_cave_ranges.clear()
	for n in names:
		var mi: MeshInstance3D = world.get_node_or_null(n)
		if mi == null or not (mi.mesh is ArrayMesh):
			continue
		_cave_ranges.append([n, vs.size() / 3])
		var fcs := (mi.mesh as ArrayMesh).get_faces()
		var cl := _tri_colors(mi.mesh, fcs.size() / 3)
		for i in fcs.size():
			vs.append(mi.global_transform * fcs[i])
			cs.append(cl[i / 3])
	if vs.size() < 3:
		_p("AUDIT WORLD no cave meshes")
		return
	if _verbose:
		_p("AUDIT WORLD cave meshes first triangle: " + str(_cave_ranges))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_COLOR] = cs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var c0 := Vector3(L.CAVE_C.x, float(world.call("height_at", L.CAVE_C.x, L.CAVE_C.y)), L.CAVE_C.y)
	var arena_pts: Array = []
	for k in 12:
		var ak := TAU * (float(k) + 0.5) / 12.0
		for rk: float in [3.0, 6.5, 10.0, 12.2]:
			arena_pts.append(Vector2(L.CAVE_C.x + sin(ak) * rk, L.CAVE_C.y + cos(ak) * rk))
	var rois: Array = [
		{"name": "arena_roof", "c": c0, "r": 11.0, "h": 16.0, "pts": arena_pts, "floor": true},
		{"name": "arena_wall", "c": c0, "r": 13.0, "h": 8.0, "pts": arena_pts, "floor": true},
	]
	for which in [["mouth_a", L.MOUTH_A, 3.6], ["mouth_b", L.MOUTH_B, 1.75]]:
		var mp: Vector2 = which[1]
		var along := (L.CAVE_C - mp)
		var len_t := maxf(along.length() - 13.0, 4.0)
		var dir := along.normalized()
		var side := Vector2(-dir.y, dir.x)
		var pts: Array = []
		var s := 1.5
		while s < len_t:
			for lat: float in [-0.6, 0.0, 0.6]:
				pts.append(mp + dir * s + side * float(which[2]) * lat)
			s += 2.5
		var mid := mp + dir * (len_t * 0.5)
		var cc := Vector3(mid.x, float(world.call("height_at", mid.x, mid.y)), mid.y)
		rois.append({"name": "tunnel_" + String(which[0]), "c": cc, "r": len_t * 0.5 + 2.0, "h": 8.0, "pts": pts, "floor": true})
	_heightfield_world = world
	await _run_rois("cave", _prepare(m), rois, world, "world")
	_heightfield_world = null


# --- self test -----------------------------------------------------------------------------------------------------

## Shapes whose answer is known: (name, mesh builder, must the audit find defects?).
func _selftest() -> void:
	var cases: Array = [
		["hollow_slab", func(mb: MeshBuilder) -> void: ModelsNature.box5(mb, Vector3(0, 2.0, 0), Vector3(2, 0.2, 2), Color.WHITE), true],
		["closed_slab", func(mb: MeshBuilder) -> void: mb.box(Vector3(0, 2.0, 0), Vector3(2, 0.2, 2), Color.WHITE), false],
		["single_sheet", func(mb: MeshBuilder) -> void: mb.quad(Vector3(-1, 2, 1), Vector3(1, 2, 1), Vector3(1, 2, -1), Vector3(-1, 2, -1), Color.WHITE), true],
		["two_sided_sheet", func(mb: MeshBuilder) -> void:
			mb.quad(Vector3(-1, 2, 1), Vector3(1, 2, 1), Vector3(1, 2, -1), Vector3(-1, 2, -1), Color.WHITE)
			mb.quad(Vector3(-1, 2, 1), Vector3(-1, 2, -1), Vector3(1, 2, -1), Vector3(1, 2, 1), Color.RED), false],
		["inside_out_box", func(mb: MeshBuilder) -> void:
			# a closed box whose every face points inwards: from outside only back faces are met
			var h := 1.0
			var p := [Vector3(-h, 1, -h), Vector3(h, 1, -h), Vector3(h, 1, h), Vector3(-h, 1, h), Vector3(-h, 3, -h), Vector3(h, 3, -h), Vector3(h, 3, h), Vector3(-h, 3, h)]
			mb.quad(p[4], p[5], p[6], p[7], Color.WHITE)
			mb.quad(p[3], p[2], p[1], p[0], Color.WHITE)
			mb.quad(p[3], p[7], p[6], p[2], Color.WHITE)
			mb.quad(p[1], p[5], p[4], p[0], Color.WHITE)
			mb.quad(p[2], p[6], p[5], p[1], Color.WHITE)
			mb.quad(p[0], p[4], p[7], p[3], Color.WHITE), true],
		["roof_before", func(mb: MeshBuilder) -> void:
			# the old gable roof: a slab (box5) over a single-sided gable triangle
			ModelsNature.box5(mb, Vector3(0, 3.0, 0), Vector3(4, 0.17, 3), Color.WHITE), true],
	]
	var fails := 0
	for c: Array in cases:
		var mb := MeshBuilder.new(1)
		(c[1] as Callable).call(mb)
		var row := _audit("selftest_" + String(c[0]), mb.commit())
		var found := int(row["defects"]) > 0
		var ok := found == bool(c[2])
		if not ok:
			fails += 1
		_p("AUDIT SELFTEST %-16s expected_defects=%s defects=%d of %d rays (%.2f%%) %s" % [c[0], str(c[2]), row["defects"], row["rays"], row["pct"], "PASS" if ok else "FAIL"])
	_p("AUDIT SELFTEST result fails=%d" % fails)
