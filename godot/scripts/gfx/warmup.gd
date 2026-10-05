# DEAD AIR — gfx/warmup.gd: first-use shader warm-up (Godot-only engine plumbing; the JS game's renderer.compileAsync /
# game.warmSteps counterpart).
#
# The Compatibility renderer (the web build: WebGL2) compiles a shader variant the first time something draws with it,
# synchronously, on the main thread: the first station frame after the tune-in froze for seconds and the first
# zombie / FX / commercial of each kind hitched. Game._load runs this behind the title (PLEASE STAND BY) once the
# station and the model pools exist, so every program the game will need is compiled while nobody plays:
#   1. station pass: the station (game.scene) is drawn from a top-down orthographic camera over each area of the
#      layout into a small offscreen SubViewport that shares the world (same lights, environment, fog, viewport
#      format and MSAA as render.view, so the very same variants compile). The main view is frozen meanwhile (its
#      last title picture stays on screen) and the living room is hidden.
#   2. gallery pass: one proxy per distinct shader of everything that is NOT drawn yet (hidden pools, FX multimeshes,
#      the pooled zombie models, ...) laid out on a grid far above the station, four times: under the key light only,
#      + an omni light, + a spot light, + both (the light-type specializations of the Compatibility scene shader).
#   3. 2D pass: the CanvasItem materials of the HUD / menus / overlays on a small 2D SubViewport.
#   4. prebuilds of lazy CPU work: the commercial overlay's bezel canvas (scripts/ui/commercial.gd).
# Everything it creates is freed at the end; the game state is untouched.
# API: Warmup.new(game).run() (coroutine: await it). Params: warm=0 skips it, warm=1 forces it under Forward+
#   (by default it only runs under the Compatibility renderer: Forward+ precompiles its pipelines itself).
extends RefCounted

const CELL := 1.6            # gallery grid cell (m)
const SKY := 3000.0          # gallery height (far above the station and out of reach of its lights)
const VP_SIZE := Vector2i(320, 180)
const CHUNK := 24            # gallery proxies drawn per warm-up frame

var game
var _vp: SubViewport
var _cam: Camera3D
var _made: Array = []        # nodes to free at the end
var stats := {"frames": 0, "proxies": 0, "canvas": 0, "ms": 0}

func _init(g) -> void:
	game = g

static func wanted(g) -> bool:
	var p = g.params.get("warm")
	if p != null:
		return float(p) != 0.0
	return DAU.isCompat()

func run() -> void:
	var r = game.render
	if r == null or game.scene == null or not (r.get("view") is SubViewport):
		return
	var t0 := Time.get_ticks_msec()
	var view: SubViewport = r.view
	var mainMode := view.render_target_update_mode
	var room = _room()
	var roomVis := false
	if room != null:
		roomVis = room.visible
	var sceneVis: bool = game.scene.visible
	_vp = SubViewport.new()
	_vp.name = "Warmup"
	_vp.size = VP_SIZE
	_vp.use_hdr_2d = view.use_hdr_2d
	_vp.msaa_3d = view.msaa_3d
	_vp.screen_space_aa = view.screen_space_aa
	_vp.positional_shadow_atlas_size = view.positional_shadow_atlas_size
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(_vp)
	_cam = Camera3D.new()
	_cam.name = "WarmupCam"
	_cam.cull_mask = r.camera.cull_mask if r.get("camera") is Camera3D else 0xFFFFF
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.5
	_cam.far = 400.0
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	_vp.add_child(_cam)
	_cam.current = true
	_view = view
	_mainMode = mainMode
	_room_n = room
	_roomVis = roomVis
	_sceneVis = sceneVis
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await _stationPass()
	await _galleryPass()
	await _canvasPass()
	for n in _made:
		if is_instance_valid(n):
			n.queue_free()
	_made.clear()
	_vp.queue_free()
	_prebuild()
	stats.ms = Time.get_ticks_msec() - t0
	print("[warmup] %d frames, %d proxies, %d canvas materials in %d ms" % [stats.frames, stats.proxies, stats.canvas, stats.ms])

func _room():
	var m = game.get("menu")
	if m == null:
		return null
	var R = m.get("_room")
	if R is Dictionary and R.get("scene") is Node3D:
		return R.scene
	return null

var _view: SubViewport
var _mainMode := SubViewport.UPDATE_ALWAYS
var _room_n = null
var _roomVis := false
var _sceneVis := false

# One warm-up frame: the title picture freezes for it (main view not redrawn, living room hidden) while the station
# shows to the warm-up camera only; then everything is put back and the title gets the next frame (it keeps
# animating between the warm-up frames).
func _frame() -> void:
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _room_n != null and is_instance_valid(_room_n):
		_room_n.visible = false
	game.scene.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	stats.frames += 1
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	game.scene.visible = _sceneVis
	if _room_n != null and is_instance_valid(_room_n):
		_room_n.visible = _roomVis
	_view.render_target_update_mode = _mainMode
	await RenderingServer.frame_post_draw

# Top-down orthographic shot of a rectangle (x0, z0, x1, z1) of the station.
func _shoot(x0: float, z0: float, x1: float, z1: float, y := 60.0) -> void:
	var w := maxf(1.0, x1 - x0)
	var h := maxf(1.0, z1 - z0)
	var aspect := float(VP_SIZE.x) / float(VP_SIZE.y)
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = maxf(h, w / aspect) + 2.0
	_cam.position = Vector3((x0 + x1) / 2.0, y, (z0 + z1) / 2.0)
	await _frame()

func _stationPass() -> void:
	var areas: Array = Layout.AREAS
	var fp = Layout.FOOTPRINT if not Layout.FOOTPRINT.is_empty() else null
	for a in areas:
		var rc = a.get("rect")
		if rc is Array and rc.size() >= 4:
			await _shoot(float(rc[0]), float(rc[1]), float(rc[2]), float(rc[3]))
	# the whole site, exterior included
	if fp != null:
		await _shoot(float(fp.x0) - 40.0, float(fp.z0) - 40.0, float(fp.x1) + 40.0, float(fp.z1) + 40.0, 120.0)
	else:
		await _shoot(-60.0, -80.0, 100.0, 60.0, 120.0)

# ------------------------------------------------------------------------------------------------ gallery
# Distinct (shader, instancing, vertex format) combinations of the hidden geometry under game.scene, plus the pooled
# zombie models (off-tree until a zombie spawns).
func _collect() -> Array:
	var seen := {}
	var out: Array = []
	var roots: Array = [game.scene]
	var ZT = load("res://scripts/actors/zombie_types.gd") if ResourceLoader.exists("res://scripts/actors/zombie_types.gd") else null
	if ZT != null and ZT.get("pools") is Dictionary:
		for list in ZT.pools.values():
			for m in list:
				if m is Dictionary and m.get("group") is Node3D and not (m.group as Node).is_inside_tree():
					roots.append(m.group)
	for root in roots:
		var stack: Array = [[root, root == game.scene]]
		while not stack.is_empty():
			var e: Array = stack.pop_back()
			var n: Node = e[0]
			var drawn: bool = e[1]
			if n is Node3D:
				drawn = drawn and (n as Node3D).visible
			if n is GeometryInstance3D and not drawn:
				_collectGeom(n, seen, out)
			for c in n.get_children():
				if c is Viewport:
					continue
				stack.append([c, drawn])
	return out

static func _matKey(m) -> String:
	var k := ""
	while m != null:
		if m is ShaderMaterial:
			k += "s%d;" % ((m as ShaderMaterial).shader.get_instance_id() if (m as ShaderMaterial).shader != null else 0)
		elif m is Material:
			k += "m%d;" % m.get_instance_id()
		m = m.next_pass if m is Material else null
	return k

func _collectGeom(o: GeometryInstance3D, seen: Dictionary, out: Array) -> void:
	if o is MeshInstance3D:
		var mi := o as MeshInstance3D
		if mi.mesh == null:
			return
		for i in mi.mesh.get_surface_count():
			var m = mi.get_active_material(i)
			if m == null:
				continue
			var key := "M%s|%d|%s" % [_matKey(m), mi.mesh.surface_get_format(i) if mi.mesh is ArrayMesh else 0, _matKey(o.material_overlay)]
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"kind": "mesh", "mesh": mi.mesh, "surface": i, "mat": m, "overlay": o.material_overlay, "transparency": o.transparency})
	elif o is MultiMeshInstance3D:
		var mm := (o as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return
		for i in mm.mesh.get_surface_count():
			var m = o.material_override if o.material_override != null else mm.mesh.surface_get_material(i)
			if m == null:
				continue
			var key := "I%s|%d|%d%d%d" % [_matKey(m), mm.mesh.surface_get_format(i) if mm.mesh is ArrayMesh else 0, int(mm.use_colors), int(mm.use_custom_data), mm.transform_format]
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"kind": "multi", "mm": mm, "surface": i, "mat": m})
	elif o is CPUParticles3D:
		var cp := o as CPUParticles3D
		if cp.mesh == null:
			return
		var m = o.material_override if o.material_override != null else cp.mesh.surface_get_material(0)
		if m == null:
			return
		var key := "P%s" % _matKey(m)
		if seen.has(key):
			return
		seen[key] = true
		out.append({"kind": "particles", "mesh": cp.mesh, "mat": m})

# One proxy (scaled into a CELL) at `at`.
func _proxy(it: Dictionary, at: Vector3, parent: Node3D) -> void:
	var node: GeometryInstance3D
	var aabb := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	if it.kind == "mesh":
		var mi := MeshInstance3D.new()
		mi.mesh = it.mesh
		for i in (it.mesh as Mesh).get_surface_count():
			mi.set_surface_override_material(i, it.mat if i == it.surface else _hiddenMat())
		mi.material_overlay = it.overlay
		mi.transparency = it.transparency
		aabb = (it.mesh as Mesh).get_aabb()
		node = mi
	else:
		var src: MultiMesh = it.get("mm")
		var mm := MultiMesh.new()
		mm.transform_format = src.transform_format if src != null else MultiMesh.TRANSFORM_3D
		mm.use_colors = src.use_colors if src != null else true
		mm.use_custom_data = src.use_custom_data if src != null else true
		mm.mesh = src.mesh if src != null else it.mesh
		mm.instance_count = 1
		if mm.transform_format == MultiMesh.TRANSFORM_3D:
			mm.set_instance_transform(0, Transform3D())
		else:
			mm.set_instance_transform_2d(0, Transform2D())
		if mm.use_colors:
			mm.set_instance_color(0, Color.WHITE)
		if mm.use_custom_data:
			mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = it.mat
		aabb = mm.mesh.get_aabb()
		node = mmi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = _cam.cull_mask & 0x3
	var s := 1.0 / maxf(0.05, maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)))
	node.transform = Transform3D(Basis().scaled(Vector3(s, s, s)), at - aabb.get_center() * s)
	node.extra_cull_margin = 2.0
	parent.add_child(node)
	stats.proxies += 1

static var _hidden: Material = null
static func _hiddenMat() -> Material:
	# the other surfaces of a proxy mesh: an already-compiled, invisible-ish material (unshaded, depth only)
	if _hidden == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0, 0, 0)
		_hidden = m
	return _hidden

func _galleryPass() -> void:
	var items := _collect()
	if items.is_empty():
		return
	var n := items.size()
	var cols := int(ceil(sqrt(float(n))))
	var span := cols * CELL
	# light combos of the Compatibility scene shader: none / omni / spot / omni + spot (the key light is directional)
	for combo in 4:
		var root := Node3D.new()
		root.name = "WarmGallery%d" % combo
		var origin := Vector3(combo * (span + 400.0), SKY, 0.0)
		root.position = origin
		game.scene.add_child(root)
		_made.append(root)
		var chunks: Array = []
		for i in n:
			if i % CHUNK == 0:
				var ch := Node3D.new()
				ch.visible = false
				root.add_child(ch)
				chunks.append(ch)
			_proxy(items[i], Vector3((i % cols + 0.5) * CELL - span / 2.0, 0.0, (i / cols + 0.5) * CELL - span / 2.0), chunks[-1])
		if combo == 1 or combo == 3:
			var om := OmniLight3D.new()
			om.omni_range = span * 1.5 + 10.0
			om.light_energy = 0.5
			om.position = Vector3(0, 4.0, 0)
			root.add_child(om)
		if combo == 2 or combo == 3:
			var sp := SpotLight3D.new()
			sp.spot_range = span * 1.5 + 20.0
			sp.spot_angle = 80.0
			sp.light_energy = 0.5
			sp.position = Vector3(0, 6.0, 0)
			sp.rotation_degrees = Vector3(-90, 0, 0)
			root.add_child(sp)
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.size = span + 2.0
		_cam.position = origin + Vector3(0, 30.0, 0)
		# a few shaders per frame, so no single frame stalls for long
		for ch in chunks:
			ch.visible = true
			await _frame()
			ch.visible = false
		root.visible = false

# ------------------------------------------------------------------------------------------------ 2D
# Every CanvasItem material in the tree (HUD, menus, overlays, hidden or not) drawn once on a ColorRect.
func _canvasPass() -> void:
	var seen := {}
	var mats: Array = []
	var stack: Array = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var m = (n as CanvasItem).material
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				var k := (m as ShaderMaterial).shader.get_instance_id()
				if not seen.has(k):
					seen[k] = true
					mats.append(m)
		for c in n.get_children():
			stack.append(c)
	if mats.is_empty():
		return
	var vp := SubViewport.new()
	vp.name = "Warmup2D"
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.add_child(vp)
	_made.append(vp)
	var cols := int(ceil(sqrt(float(mats.size()))))
	var cell := 256.0 / cols
	for i in mats.size():
		var cr := ColorRect.new()
		cr.material = mats[i]
		cr.position = Vector2((i % cols) * cell, (i / cols) * cell)
		cr.size = Vector2(cell, cell)
		vp.add_child(cr)
		stats.canvas += 1
	await _frame()

# ------------------------------------------------------------------------------------------------ CPU prebuilds
func _prebuild() -> void:
	if ResourceLoader.exists("res://scripts/ui/commercial.gd"):
		var CO = load("res://scripts/ui/commercial.gd")
		var ov = CO.getOverlay() if CO != null else null
		if ov != null and ov.has_method("_ensure") and ov.has_method("_resize"):
			ov._ensure()
			ov._resize()
