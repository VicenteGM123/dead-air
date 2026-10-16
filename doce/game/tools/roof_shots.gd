extends "res://scripts/main.gd"
## Low cameras looking UP at the roofs and the other things built from thin plates (the client's "the roofs of the
## houses look transparent seen from below"): the real island, a free camera just under the eaves, the balcony, the
## pergola, the stalls' awnings, the well, the shrine, the fence, the altar... Run it on the old and the new models and
## compare the PNGs (tools/mesh_audit.gd gives the numbers; this gives the pictures).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     res://tools/roof_shots.tscn --quit-after 20000 -- set=houses outdir=/abs/dir [settle=10] [only=eave]
## set=houses (every house type, several yaws, eaves / gables / balcony / pergola / terrace), set=props (stalls, well,
## shrine, fence, gate, pen, nets, crates, altar, ring, threshing floor, plaza) or set=models (terrace wall, retaining
## wall, ruin column, driftwood ... on a stage high above the island).

const L := preload("res://scripts/world/nemea_layout.gd")
const NemeaTerrain := preload("res://scripts/world/nemea_terrain.gd")
const STAGE := Vector3(0.0, 150.0, 0.0)

var _out_dir := ""
var _stage_nodes: Array[Node] = []


func _wants_title() -> bool:
	return false


func _ready() -> void:
	for k in ["noui", "fauna"]:
		if not Game.has_arg(k):
			Game.args[k] = "0" if k == "fauna" else "1"
	if not Game.has_arg("enemies"):
		Game.args["enemies"] = "0"
	if not Game.has_arg("lion"):
		Game.args["lion"] = "0"
	super._ready()
	_run.call_deferred()


func _run() -> void:
	_out_dir = String(Game.arg("outdir", OS.get_user_data_dir()))
	var settle := int(Game.arg("settle", "10"))
	var only := String(Game.arg("only", "")).split(",", false)
	var shots: Array = []
	match String(Game.arg("set", "houses")):
		"houses":
			shots = _house_shots()
		"props":
			shots = _prop_shots()
		"models":
			shots = _model_shots()
		_:
			shots = _house_shots() + _prop_shots() + _model_shots()
	for s: Dictionary in shots:
		if not only.is_empty():
			var ok := false
			for o in only:
				if String(s["name"]).contains(o):
					ok = true
			if not ok:
				continue
		if s.has("setup"):
			(s["setup"] as Callable).call()
		_look(s["pos"], s["at"], float(s.get("fov", 70.0)))
		for i in settle:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out_dir.path_join(String(s["name"]) + ".png"))
		print("SHOT ", s["name"])
		if s.has("teardown"):
			(s["teardown"] as Callable).call()
	get_tree().quit()


func _look(pos: Vector3, at: Vector3, fov: float) -> void:
	var d := at - pos
	cam.set_fly(pos, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	cam.cam.fov = fov


## Point `p` in the frame of a thing standing on the ground at `o`, turned by `yaw`, scaled by `sc`; `y` is above the ground there.
func _at(o: Vector3, yaw: float, sc: float, p: Vector3, on_ground: bool = true) -> Vector3:
	var w := o + Basis(Vector3.UP, yaw) * (p * sc)
	if on_ground:
		w.y = float(world.height_at(w.x, w.z)) + p.y * sc
	return w


# --- houses ------------------------------------------------------------------------------------------------------

func _house_shots() -> Array:
	var out: Array = []
	var houses: Array = world.village.houses
	var done := {}
	for i in houses.size():
		var h: Dictionary = houses[i]
		var kind: int = h["kind"]
		if int(done.get(kind, 0)) >= 2:
			continue
		done[kind] = int(done.get(kind, 0)) + 1
		var o: Vector3 = h["pos"]
		var yaw: float = h["yaw"]
		var sc: float = h["scale"]
		var tag := "house%d_%02d" % [kind + 1, i]
		var views: Array = []
		if kind == 0:
			views = [
				["eave_front", Vector3(1.4, 0.5, 4.4), Vector3(0.0, 3.0, 1.75)],
				["eave_front_close", Vector3(0.8, 0.4, 2.9), Vector3(0.0, 3.1, 1.9)],
				["eave_back", Vector3(-1.4, 0.5, -4.3), Vector3(0.0, 3.0, -1.75)],
				["gable_side", Vector3(4.8, 0.5, 1.0), Vector3(2.0, 3.1, 0.0)],
				["corner_far", Vector3(-5.5, 0.35, 6.5), Vector3(0.0, 3.3, 0.0)],
			]
		else:
			views = [
				["balcony", Vector3(-1.7, 0.5, 4.9), Vector3(-1.7, 3.2, 2.1)],
				["pergola", Vector3(2.15, 0.5, 4.4), Vector3(2.15, 2.5, 1.8)],
				["terrace", Vector3(5.2, 0.5, 1.3), Vector3(2.4, 2.9, 0.2)],
				["main_eave", Vector3(-1.0, 0.5, 5.4), Vector3(-1.0, 4.7, 1.9)],
				["main_back", Vector3(-1.0, 0.5, -5.4), Vector3(-1.0, 4.7, -1.9)],
				["gable_side", Vector3(-6.2, 0.5, 0.5), Vector3(-2.8, 4.6, 0.0)],
			]
		for v: Array in views:
			var cam_l: Vector3 = v[1]
			var tgt_l: Vector3 = v[2]
			out.append({"name": "%s_%s" % [tag, v[0]], "pos": _at(o, yaw, sc, cam_l), "at": _at(o, yaw, sc, tgt_l, false), "fov": 72.0})
	return out


# --- props in the village and elsewhere ------------------------------------------------------------------------------

func _prop_shots() -> Array:
	var out: Array = []
	var plaza := L.PLAZA
	var pc: Vector3 = world.ground(Vector3(plaza.x, 0, plaza.y))
	var ang := [30.0, 108.0, 190.0]
	for k in 3:
		var a := deg_to_rad(float(ang[k]))
		var sp := Vector3(plaza.x + cos(a) * 7.0, pc.y + 0.04, plaza.y + sin(a) * 7.0)
		var to_c := Vector3(plaza.x, 0, plaza.y) - Vector3(sp.x, 0, sp.z)
		var yaw := atan2(to_c.x, to_c.z)
		out.append({"name": "stall%d_front" % k, "pos": _at(sp, yaw, 1.0, Vector3(0.9, 0.35, 3.3), false), "at": _at(sp, yaw, 1.0, Vector3(0.0, 2.2, 0.5), false), "fov": 72.0})
		out.append({"name": "stall%d_side" % k, "pos": _at(sp, yaw, 1.0, Vector3(3.3, 0.3, 0.6), false), "at": _at(sp, yaw, 1.0, Vector3(0.0, 2.1, 0.0), false), "fov": 72.0})
		out.append({"name": "stall%d_back" % k, "pos": _at(sp, yaw, 1.0, Vector3(0.6, 0.3, -2.4), false), "at": _at(sp, yaw, 1.0, Vector3(0.0, 0.9, -0.5), false), "fov": 72.0})
	var wp := Vector3(L.WELL.x, pc.y - 0.02, L.WELL.y)
	out.append({"name": "well_beam", "pos": wp + Vector3(0.3, 0.35, 2.6), "at": wp + Vector3(0, 1.5, 0), "fov": 66.0})
	out.append({"name": "well_rim", "pos": wp + Vector3(2.4, 0.35, 0.5), "at": wp + Vector3(0, 0.8, 0), "fov": 66.0})
	var sh := Vector3(L.SHRINE.x, float(world.height_at(L.SHRINE.x, L.SHRINE.y)), L.SHRINE.y)
	out.append({"name": "shrine", "pos": sh + Vector3(0.9, 0.35, 2.5), "at": sh + Vector3(0, 1.4, -0.2), "fov": 66.0})
	out.append({"name": "plaza_low", "pos": pc + Vector3(-3.0, 0.5, -3.0), "at": pc + Vector3(2.0, 0.2, 3.0), "fov": 78.0})
	# the north fence (west flank, intact), the torn gate leaf, the goat pen's trough, the nets and crates on the beach
	var fp := Vector3(-28.0, 0.0, 56.8)
	fp.y = float(world.height_at(fp.x, fp.z))
	out.append({"name": "fence_low", "pos": fp + Vector3(1.4, 0.35, -1.6), "at": fp + Vector3(0, 0.8, 0), "fov": 70.0})
	var gl := Vector3(-8.2, 0.0, 51.5)
	gl.y = float(world.height_at(gl.x, gl.z))
	out.append({"name": "gate_leaf", "pos": gl + Vector3(2.4, 0.3, 2.6), "at": gl + Vector3(0, 0.2, 0), "fov": 70.0})
	var tp := Vector3(L.GOAT_PEN.x + 2.0, 0.0, L.GOAT_PEN.y + 1.5)
	tp.y = float(world.height_at(tp.x, tp.z))
	out.append({"name": "pen_trough", "pos": tp + Vector3(1.6, 0.3, 1.6), "at": tp + Vector3(0, 0.3, 0), "fov": 70.0})
	var np := Vector3(-12.8, 0.0, 101.0)
	np.y = float(world.height_at(np.x, np.z))
	out.append({"name": "beach_nets", "pos": np + Vector3(0.2, 0.3, 2.4), "at": np + Vector3(0, 1.8, 0), "fov": 70.0})
	var cp := Vector3(20.4, 0.0, 102.4)
	cp.y = float(world.height_at(cp.x, cp.z))
	out.append({"name": "beach_crates", "pos": cp + Vector3(2.0, 0.3, 1.6), "at": cp + Vector3(0, 0.4, 0), "fov": 70.0})
	# the farm's threshing floor and the altar / ring stone (CORE's props)
	var tf := Vector3(L.THRESHING.x, 0.0, L.THRESHING.y)
	tf.y = float(world.height_at(tf.x, tf.z))
	out.append({"name": "threshing_floor", "pos": tf + Vector3(4.2, 0.35, 3.0), "at": tf + Vector3(0, 0.1, 0), "fov": 74.0})
	var altars: Array = world.altars()
	if altars.size() > 0:
		var al: Node3D = altars[0]
		var ap := al.global_position
		var ab := al.global_transform.basis
		out.append({"name": "altar", "pos": ap + ab * Vector3(1.4, 0.3, 2.4), "at": ap + Vector3(0, 1.45, 0), "fov": 64.0})
	# the sea stack of the broken passage, from the water (its strata overhang each other)
	var ps := Vector3(L.PASS_STACK.x, 0.0, L.PASS_STACK.y)
	out.append({"name": "sea_stack", "pos": ps + Vector3(6.5, 0.7, 4.5), "at": ps + Vector3(0, 5.5, 0), "fov": 66.0})
	# the arena of the cave: the rock lid seen from the floor
	var cf := Vector3(L.CAVE_C.x, float(world.height_at(L.CAVE_C.x, L.CAVE_C.y)), L.CAVE_C.y)
	out.append({"name": "cave_lid", "pos": cf + Vector3(-6.0, 1.7, 7.0), "at": cf + Vector3(2.0, 12.0, -3.0), "fov": 74.0})
	# the dry-stone wall on the wheat field's south bank, from the downhill side (its back)
	var wp2 := _wheat_wall_spot()
	if wp2.size() == 2:
		var wpos: Vector3 = wp2[0]
		var wout: Vector3 = wp2[1]
		out.append({"name": "wheat_wall_back", "pos": wpos + wout * 2.2 + Vector3(0, 0.5, 0), "at": wpos + Vector3(0, 0.45, 0), "fov": 70.0})
	var rings: Array = world.anchors()
	if rings.size() > 0:
		var rn: Node3D = rings[0]
		var rp := rn.global_position
		var rb := rn.global_transform.basis
		out.append({"name": "chain_ring", "pos": rp + rb * Vector3(0.6, -1.2, 2.2) + Vector3(0, 0.0, 0), "at": rp + Vector3(0, 2.4, 0), "fov": 64.0})
	return out


# --- single models on a stage high above the island ---------------------------------------------------------------------

func _model_shots() -> Array:
	var out: Array = []
	var specs := [
		["terrace_wall_back", "terrace_wall", 60, 0.0, Vector3(1.6, 0.35, -2.4), Vector3(0, 0.45, 0)],
		["terrace_wall_back_up", "terrace_wall", 60, 0.0, Vector3(0.4, 0.3, -1.3), Vector3(0.2, 0.6, 0)],
		["terrace_wall_front", "terrace_wall", 60, 0.0, Vector3(1.4, 0.3, 2.2), Vector3(0, 0.45, 0)],
		["retaining_wall_cap", "retaining_wall", 60, 0.0, Vector3(0.9, 0.3, 1.1), Vector3(0, 0.9, -0.3)],
		["wood_fence_0", "wood_fence", 60, 0.0, Vector3(1.2, 0.3, 1.5), Vector3(0, 0.8, 0)],
		["wood_fence_1", "wood_fence", 121, 0.0, Vector3(1.2, 0.3, 1.8), Vector3(0.3, 0.6, 0)],
		["threshing_floor_low", "threshing_floor", 60, 0.0, Vector3(4.6, 0.3, 2.2), Vector3(0, 0.05, 0)],
		["ruin_column_base", "ruin_column", 60, 0.0, Vector3(1.6, 0.3, 1.8), Vector3(0, 0.5, 0)],
		["driftwood", "driftwood", 60, 0.0, Vector3(1.5, 0.3, 1.6), Vector3(0, 0.25, 0)],
		["herm_shrine_up", "herm_shrine", 9, 0.0, Vector3(0.9, 0.3, 1.8), Vector3(0, 1.4, -0.2)],
		["well_up", "well", 5, 0.0, Vector3(0.4, 0.3, 2.4), Vector3(0, 1.4, 0)],
	]
	for sp: Array in specs:
		var fn: String = sp[1]
		var seed_v: int = sp[2]
		var yaw: float = sp[3]
		var cam_l: Vector3 = sp[4]
		var tgt_l: Vector3 = sp[5]
		var holder := {}
		out.append({
			"name": "model_" + String(sp[0]),
			"pos": STAGE + cam_l,
			"at": STAGE + tgt_l,
			"fov": 70.0,
			"setup": func() -> void: _stage_model(fn, seed_v, yaw, holder),
			"teardown": func() -> void: _unstage(holder),
		})
	return out


func _stage_model(fn: String, seed_v: int, yaw: float, holder: Dictionary) -> void:
	# a stage: a grass slab with the model on it, lit by the island's sun
	var ground := MeshInstance3D.new()
	var mb := MeshBuilder.new(1)
	mb.block(STAGE + Vector3(0, -0.4, 0), Vector3(16, 0.4, 16), Pal.GRASS)
	ground.mesh = mb.commit()
	ground.material_override = Materials.lowpoly()
	add_child(ground)
	var mi := MeshInstance3D.new()
	mi.mesh = _build_nature(fn, seed_v)
	mi.material_override = Materials.lowpoly()
	mi.position = STAGE
	mi.rotation.y = yaw
	add_child(mi)
	holder["nodes"] = [ground, mi]


func _build_nature(fn: String, seed_v: int) -> Mesh:
	var ns: Script = load("res://scripts/gfx/models_nature.gd")
	return ns.call(fn, seed_v)


func _unstage(holder: Dictionary) -> void:
	for n: Node in holder.get("nodes", []):
		n.queue_free()



## Where the first dry-stone wall piece of the wheat field stands (the loop of WheatField.place_props) and the way
## out of the field there: [position, outward direction (XZ, unit)] or [].
func _wheat_wall_spot() -> Array:
	var poly: Array = L.WHEAT_FIELD
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var mid := (a + b) * 0.5
		if mid.y < 38.0:
			continue
		var seg := b - a
		var l := seg.length()
		var dir := seg / l
		var outv := Vector2(dir.y, -dir.x)
		if NemeaTerrain.poly_sd(mid.x + outv.x, mid.y + outv.y, poly) < 0.0:
			outv = -outv
		var k := 0.0
		while k + 3.0 <= l:
			if fmod(k * 0.37 + float(i) * 1.3, 1.0) > 0.22:
				var p := a + dir * (k + 1.5) + outv * 1.6
				return [Vector3(p.x, float(world.height_at(p.x, p.y)), p.y), Vector3(outv.x, 0, outv.y)]
			k += 3.0
	return []
