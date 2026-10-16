extends "res://scripts/main.gd"
## Sea and boats probe (fix2 lane B): prints, for every boat in the game, the numbers that decide whether water can
## show on it: the model's gunwale and deck heights (ray casts into the real mesh), where it stands, the ground and
## the sea surface there over a full minute, and (for the ships that float) the clearance of every deck point over
## the water at every instant of a minute. Headless is fine:
##   godot --headless --path . res://tools/sea_probe.tscn --quit-after 60 -- noui=1 play=1 enemies=0 lion=0
## Prints "BOAT ..." lines.

const L := preload("res://scripts/world/nemea_layout.gd")

const WAVE_AMP := 0.18


func _wants_title() -> bool:
	return false


func _ready() -> void:
	if not Game.has_arg("noui"):
		Game.args["noui"] = "1"
	super._ready()
	hero.input_enabled = false
	_run.call_deferred()


## The same swell as water.gdshader / Sea.surface_y, at an explicit time.
func swell(x: float, z: float, t: float, depth: float) -> float:
	var amp := WAVE_AMP * lerpf(0.35, 1.0, smoothstep(0.0, 0.4, clampf(depth / 6.0, 0.0, 1.0)))
	var w := sin(x * 0.33 + t * 1.05) * 0.45 \
		+ sin(z * 0.41 - t * 0.85 + x * 0.12) * 0.35 \
		+ sin((x + z) * 0.78 + t * 1.65) * 0.14 \
		+ sin((x - z) * 1.30 - t * 2.10) * 0.06
	return w * amp


## Highest surface of the mesh at (x, z) in model space (ray from above), or NAN.
func _top(tm: TriangleMesh, x: float, z: float) -> float:
	var r := tm.intersect_ray(Vector3(x, 30.0, z), Vector3.DOWN)
	if r.is_empty():
		return NAN
	return (r["position"] as Vector3).y


## All the surfaces hit from above at (x, z), highest first.
func _hits(tm: TriangleMesh, x: float, z: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var y0 := 30.0
	for i in 8:
		var r := tm.intersect_ray(Vector3(x, y0, z), Vector3.DOWN)
		if r.is_empty():
			break
		var y: float = (r["position"] as Vector3).y
		out.append(y)
		y0 = y - 0.004
	return out


func _sea_stats(x: float, z: float, depth: float) -> Vector2:
	var mx := -INF
	var mn := INF
	var t := 0.0
	while t < 60.0:
		var s := swell(x, z, t, maxf(depth, 0.0))
		mx = maxf(mx, s)
		mn = minf(mn, s)
		t += 0.05
	return Vector2(mn, mx)


## Model numbers of a boat mesh placed with `tf` (origin = the waterline for the floating ones, the ground for the
## beached ones): the gunwale and the highest walkable/visible floor on the centre line, from the real triangles.
func _model_report(label: String, m: Mesh, length: float, beam: float, tf: Transform3D, floor_probe_z: float) -> void:
	var tm := m.generate_triangle_mesh()
	var aabb := m.get_aabb()
	# the gunwale amidships, from the real triangles: the highest hull surface in the outer 12 cm of the half beam at
	# z = 0 (the oars and shields of the galley lie nearer the ends / outside this strip)
	var hw0 := beam * 0.5
	var best := -INF
	var xx := hw0 - 0.12
	while xx <= hw0 + 0.01:
		var y := _top(tm, xx, 0.0)
		if not is_nan(y):
			best = maxf(best, y)
		xx += 0.01
	var hits := _hits(tm, 0.0, floor_probe_z)
	print("BOAT %s model: lowest vertex y %.2f, gunwale amidships %.2f, hits from above at z=%.1f on the centre line (mast / sail yard, then the deck or floor, the hull, the keel): %s" % [
		label, aabb.position.y, best, floor_probe_z, str(hits)])


func _ship_report(label: String, node_name: String, d: Dictionary) -> Dictionary:
	var node: Node = world.get_node_or_null(node_name)
	if node == null:
		print("BOAT %s: node %s not found (a ship baked into the village mesh?)" % [label, node_name])
		return {"ok": false}
	var length: float = d["length"]
	var beam: float = d["beam"]
	var depth: float = d["depth"]
	var draft: float = d["draft"]
	var deck: float = d["deck"]
	var rest: Vector3 = node.get("base")
	var gh: float = world.height_at(rest.x, rest.z)
	var sea_mm := _sea_stats(rest.x, rest.z, float(world.sea_level) - gh)
	print("BOAT %s: at (%.1f, %.1f) ground %.2f (depth %.2f m); swell at its middle over 60 s: min %.3f max %.3f; deck %.2f over the waterline, gunwale %.2f amidships (+%.2f at the quarters, %.2f at the ends), keel %.2f under it" % [
		label, rest.x, rest.z, gh, world.sea_level - gh, sea_mm.x, sea_mm.y, deck, depth - draft, 0.24 * pow(0.5, 2.0), depth - draft + 0.24, draft])
	# the deck points (a grid inside the deck outline) and the rail points, in the ship's frame, against the water
	# under each of them, at every instant of a minute, with the pose the BoatFloat node computes
	var deck_pts: Array[Vector3] = []
	var rail_pts: Array[Vector3] = []
	var zz := -length * 0.46
	while zz <= length * 0.46:
		var tn := zz / (length * 0.5)
		var wd: float = ModelsNature.hull_width_at(tn, beam, depth, draft + deck) - 0.07
		var xx := -wd
		while xx <= wd + 0.001:
			deck_pts.append(Vector3(xx, deck, zz))
			xx += maxf(wd * 0.5, 0.3)
		var wr: float = ModelsNature.hull_width_at(tn, beam, depth, depth)
		rail_pts.append(Vector3(wr, depth - draft + 0.24 * tn * tn, zz))
		rail_pts.append(Vector3(-wr, depth - draft + 0.24 * tn * tn, zz))
		zz += 0.5
	var tod_node: Node = Game.tod
	var min_deck := INF
	var min_rail := INF
	var at_deck := Vector3.ZERO
	var tilt_max := 0.0
	var ymin := INF
	var ymax := -INF
	var t := 0.0
	while t < 60.0:
		tod_node.set("_time", t)
		var pose: Transform3D = node.call("pose")
		ymin = minf(ymin, pose.origin.y)
		ymax = maxf(ymax, pose.origin.y)
		tilt_max = maxf(tilt_max, rad_to_deg(acos(clampf(pose.basis.y.y, -1.0, 1.0))))
		for p in deck_pts:
			var w := pose * p
			var dep: float = float(world.sea_level) - float(world.height_at(w.x, w.z))
			var c: float = w.y - (float(world.sea_level) + swell(w.x, w.z, t, maxf(dep, 0.0)))
			if c < min_deck:
				min_deck = c
				at_deck = w
		for p in rail_pts:
			var w2 := pose * p
			var dep2: float = float(world.sea_level) - float(world.height_at(w2.x, w2.z))
			min_rail = minf(min_rail, w2.y - (float(world.sea_level) + swell(w2.x, w2.z, t, maxf(dep2, 0.0))))
		t += 0.05
	print("BOAT %s: over 60 s the hull's origin moves %.3f..%.3f, tilts up to %.2f deg; the lowest deck point is %.3f m ABOVE the water (at %s), the lowest rail point %.3f m above it -> %s" % [
		label, ymin, ymax, tilt_max, min_deck, str(at_deck.snapped(Vector3.ONE * 0.01)), min_rail, "NO WATER CAN SHOW" if min_deck > 0.05 else "WATER REACHES THE DECK"])
	return {"ok": min_deck > 0.05 and min_rail > 0.3, "min_deck": min_deck, "min_rail": min_rail}


## A boat drawn up on the sand: how its hull bottom lies on the ground.
func _beached_report(label: String, m: Mesh, tf: Transform3D) -> float:
	var arr := m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	var n := 0
	var buried := 0
	var floating := 0
	var worst := 0.0
	for v in vs:
		if v.y > 0.45 or absf(v.x) > 0.8 or absf(v.z) > 1.7:
			continue # the hull bottom only (not the oars, the posts, the stone and the rope coil)
		var w := tf * v
		var c := w.y - float(world.height_at(w.x, w.z))
		lo = minf(lo, c)
		hi = maxf(hi, c)
		n += 1
		if c < -0.05:
			buried += 1
		if c > 0.08:
			floating += 1
	var gh: float = world.height_at(tf.origin.x, tf.origin.z)
	var sea := _sea_stats(tf.origin.x, tf.origin.z, 0.0)
	# the keel line (the boat rests on it): from the stem to the stern post, how high over the sand is each end?
	var klo := INF
	var khi := -INF
	var k_end_hi := -INF
	for v in vs:
		if v.y > 0.12 or absf(v.x) > 0.3 or absf(v.z) > 1.55:
			continue
		var wk := tf * v
		var ck: float = wk.y - float(world.height_at(wk.x, wk.z))
		klo = minf(klo, ck)
		khi = maxf(khi, ck)
		if absf(v.z) > 1.1:
			k_end_hi = maxf(k_end_hi, ck)
	print("BOAT %s: on the sand at (%.1f, %.1f), ground %.2f (the highest swell there %.3f), hull clearance over the ground: lowest vertex %.3f; keel line from stem to stern: %.3f .. %.3f (the last 0.45 m at each end up to %.3f; the hull's own rocker there is 0.04-0.09)" % [
		label, tf.origin.x, tf.origin.z, gh, sea.y, lo, klo, khi, k_end_hi])
	return lo


func _run() -> void:
	await get_tree().process_frame
	print("BOAT ---- probe of every boat (positions from nemea_layout / nemea_village)")
	var g: Dictionary = ModelsBuildings.ship(0, 21)
	_model_report("galley(Heracles)", g["mesh"], float(g["length"]), float(g["beam"]), Transform3D(), 3.0)
	var all_ok := true
	var rg: Dictionary = _ship_report("galley(Heracles)", "ShipHeracles", g)
	all_ok = all_ok and bool(rg["ok"])
	var m: Dictionary = ModelsBuildings.ship(1, 33)
	_model_report("merchantman(Lerna)", m["mesh"], float(m["length"]), float(m["beam"]), Transform3D(), -3.0)
	var rm: Dictionary = _ship_report("merchantman(Lerna)", "ShipLerna", m)
	all_ok = all_ok and bool(rm["ok"])
	# the beached boats (the same transforms nemea_village._beach() builds)
	var v: RefCounted = world.get("village")
	for e in [["beached#1 boat_small(4)", 4, Vector2(-6.0, 106.0), 1.2], ["beached#2 boat_small(7)", 7, Vector2(30.0, 107.0), -1.9]]:
		var mesh := ModelsNature.boat_small(int(e[1]))
		var xz: Vector2 = e[2]
		var tf: Transform3D
		if v != null and v.has_method("beached_transform"):
			tf = v.call("beached_transform", mesh, xz, float(e[3]))
		else:
			tf = Transform3D(Basis(Vector3.UP, float(e[3])), Vector3(xz.x, world.height_at(xz.x, xz.y) + 0.05, xz.y))
		_model_report(String(e[0]), mesh, 3.6, 1.35, tf, 0.0)
		var lowest := _beached_report(String(e[0]) + " [AFTER: beached_transform]", mesh, tf)
		# resting on the sand (not hung over it, not sunk in it) and dry: the sand is over the highest swell
		var dry: bool = float(world.height_at(xz.x, xz.y)) > _sea_stats(xz.x, xz.y, 0.0).y + 0.3
		all_ok = all_ok and lowest > -0.08 and lowest < 0.05 and dry
		# the placement the game used before FIX2: the origin on the ground under the middle + 5 cm, no pitch
		var old_tf := Transform3D(Basis(Vector3.UP, float(e[3])), Vector3(xz.x, world.height_at(xz.x, xz.y) + 0.05, xz.y))
		_beached_report(String(e[0]) + " [BEFORE: ground + 0.05]", mesh, old_tf)
	# the dock-pack fishing boat (ModelsBuildings.boat: not placed in DOCE, kept consistent): its floor against a
	# flat sea, for the record
	var fb := ModelsBuildings.boat(5)
	var tmfb := fb.generate_triangle_mesh()
	var fh := _hits(tmfb, 0.0, 0.3)
	var swell_max := _sea_stats(0.0, 0.0, 6.0).y
	var dock_ok: bool = fh.size() >= 2 and fh[fh.size() - 2] > swell_max + 0.02
	all_ok = all_ok and dock_ok
	print("BOAT dock boat ModelsBuildings.boat(5) (origin = the waterline): hits from above at z=0.3 %s; the highest swell %.3f -> floor %s" % [str(fh), swell_max, "ABOVE the swell" if dock_ok else "(read the hits: the floor is the second from the bottom)"])
	# ground profile south of the village: where is the shoreline, the wet line, the foam?
	for xx in [-6.0, 14.0, 30.0]:
		var line := ""
		for zz in range(96, 150, 3):
			line += "%d:%.2f " % [zz, world.height_at(xx, float(zz))]
		print("BOAT ground profile x=%.0f  z:height  %s" % [xx, line])
	print("BOAT pier deck %.2f" % L.PIER_DECK)
	print("BOAT result=%s (ships: deck > 5 cm and rails > 30 cm over the water at every instant of a minute; beached boats: resting on dry sand; the dock boat: floor over the highest swell)" % ("PASS" if all_ok else "FAIL"))
	if Game.arg_on("landing"):
		await _stand_on_pier()
		await _landing("ShipLerna", Vector3(0.0, 0.0, 0.0))
		await _landing("ShipHeracles", Vector3(0.0, 0.0, 1.5))
	get_tree().quit()


## The reference: the hero standing on the pier's deck (a box, like every solid of the village): how far above the
## surface (1.55 m) does the physics hold his feet?
func _stand_on_pier() -> void:
	hero.teleport(Transform3D(Basis.IDENTITY, Vector3(14.0, L.PIER_DECK + 1.5, 125.0)))
	hero.input_enabled = false
	for i in 200:
		await get_tree().physics_frame
	print("BOAT landing reference: on the pier deck (y %.2f) the hero's feet are at %.3f (%.3f over the deck), on the floor %s" % [L.PIER_DECK, hero.global_position.y, hero.global_position.y - L.PIER_DECK, str(hero.is_on_floor())])


## The hero drops onto a ship's deck (he jumped from the pier) and must stand on it, riding it: his feet stay on the
## deck (not in the planks, not in the air) while the ship heaves for ten seconds.
func _landing(node_name: String, local: Vector3) -> void:
	var node: Node3D = world.get_node_or_null(node_name)
	if node == null:
		print("BOAT landing %s: no node" % node_name)
		return
	var pose: Transform3D = node.call("pose")
	var drop := pose * (local + Vector3(0, 2.6, 0))
	hero.teleport(Transform3D(Basis.IDENTITY, drop))
	hero.input_enabled = false
	var dmax := -INF
	var dmin := INF
	var floor_n := 0
	var n := 0
	var swim_n := 0
	for i in 720: # 12 s of physics frames
		await get_tree().physics_frame
		if i < 150:
			continue # falling and settling
		var deck_y: float = (node.global_transform * Vector3(local.x, 0.34, local.z)).y
		var d := hero.global_position.y - deck_y
		dmax = maxf(dmax, d)
		dmin = minf(dmin, d)
		n += 1
		if hero.is_on_floor():
			floor_n += 1
		if hero.motion_state == &"swim":
			swim_n += 1
	print("BOAT landing %s: hero dropped from 2.6 m over the deck; over %d frames his feet were %.3f..%.3f m from the deck surface, on the floor %d%% of the frames, swimming %d frames, motion %s" % [
		node_name, n, dmin, dmax, int(100.0 * floor_n / maxf(1.0, n)), swim_n, String(hero.motion_state)])
