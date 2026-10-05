# DEAD AIR — gfx/warmup.gd: first-use shader warm-up (Godot-only engine plumbing; the JS game's renderer.compileAsync /
# game.warmSteps counterpart).
#
# The Compatibility renderer (the web build: WebGL2) compiles a shader variant the first time something draws with it,
# synchronously, on the main thread (on ANGLE/D3D every program link costs 0.1..0.5 s): the first station frame after
# the tune-in froze for seconds and the first zombie / FX / commercial of each kind hitched. Game._load runs this
# behind the title (PLEASE STAND BY) once the station and the model pools exist, so every program the game will need
# is compiled while nobody plays:
#   1. station pass: the station (game.scene) is drawn from a top-down orthographic camera over each area of the
#      layout into a small offscreen SubViewport that shares the world (same lights, environment, fog, viewport
#      format and MSAA as render.view, so the very same variants compile). The main view is frozen meanwhile (its
#      last title picture stays on screen) and the living room is hidden.
#   2. gallery pass: one proxy per distinct (shader, instancing, vertex format) of everything under game.scene,
#      visible or not (the top-down shots miss the sky, things under ceilings, hidden pools, FX multimeshes, ...),
#      laid out on a grid far above the station, once per light specialization the station uses (no omni / omni:
#      _lightCombos; spot combos only if the station ever gets a SpotLight3D). Characters are drawn whole instead
#      (_collectModels): one pooled model of every zombie variant and special, a popped head, the four heroes (built
#      here, the player's is only built by newGame), the Double Vision twins and an Instant Replay afterimage, so the
#      skinning programs and the skinned vertex layout compile too. The zombie models first get their feed variant
#      (screens._prepZombie: a runtime Shader + an eye overlay, otherwise made and compiled on the first spawn).
#   3. 2D pass: the default CanvasItem material and every CanvasItem material of the tree, each drawn with every
#      kind of canvas command (rect, nine-patch, primitive, polygon, multimesh: the canvas shader specializes per
#      command).
#   4. prebuilds of lazy CPU work: the commercial overlay's bezel canvas (scripts/ui/commercial.gd).
# Everything it creates is freed at the end (a few materials excepted, see _keepMat); the game state is untouched.
# Related: render.gd keeps the native fog enabled under Compatibility (toggling it re-specializes every shader).
# API: Warmup.new(game).run() (coroutine: await it). Params: warm=0 skips it, warm=1 forces it under Forward+
#   (by default it only runs under the Compatibility renderer: Forward+ precompiles its pipelines itself).
extends RefCounted

const CELL := 1.6            # gallery grid cell (m)
const SKY := 3000.0          # gallery height (far above the station and out of reach of its lights)
const VP_SIZE := Vector2i(320, 180)
const CHUNK := 24            # gallery proxies drawn per warm-up frame
const MCELL := 3.0           # model gallery cell (m): characters are drawn at full size
const MCHUNK := 8            # real models drawn per warm-up frame

var game
var _vp: SubViewport
var _cam: Camera3D
var _made: Array = []        # nodes to free at the end
var stats := {"frames": 0, "proxies": 0, "models": 0, "canvas": 0, "ms": 0}

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
	_prebuild()
	_extras = _buildExtras()
	_models = _collectModels()
	_items = _collect()
	_combos = _lightCombos()
	_total = Layout.AREAS.size() + 1 + _combos.size() * (int(ceil(_items.size() / float(CHUNK))) + int(ceil(_models.size() / float(MCHUNK)))) + 1
	await _stationPass()
	await _galleryPass()
	await _canvasPass()
	_restoreModels()
	for n in _made:
		if is_instance_valid(n):
			n.queue_free()
	_made.clear()
	for n in _extras:
		if is_instance_valid(n) and not n.is_inside_tree():
			n.free()
	_extras.clear()
	_borrowed.clear()
	_releaseZombies()
	_vp.queue_free()
	stats.ms = Time.get_ticks_msec() - t0
	print("[warmup] %d frames, %d proxies, %d models, %d canvas materials in %d ms" % [stats.frames, stats.proxies, stats.models, stats.canvas, stats.ms])

func _room():
	var m = game.get("menu")
	if m == null:
		return null
	var R = m.get("_room")
	if R is Dictionary and R.get("scene") is Node3D:
		return R.scene
	return null

var _view: SubViewport
var _items: Array = []
var _total := 1
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
	if game.has_method("_prog"):
		game._prog(0.6 + 0.35 * minf(1.0, float(stats.frames) / _total))   # the title's loading bar (0.6 -> 0.95)
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
# Distinct (shader, instancing, vertex format) combinations of the hidden geometry under game.scene and of the
# off-tree models built for the gallery (the characters are drawn whole instead: _collectModels).
func _collect() -> Array:
	var seen := {}
	var out: Array = []
	var roots: Array = [game.scene]
	roots.append_array(_extras)
	roots.append_array(_borrowed)
	# visible geometry too: the station shots are top-down, so whatever they cannot see (the sky's moon, things
	# under a ceiling, ...) would otherwise compile on its first frame in view
	for root in roots:
		var stack: Array = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is GeometryInstance3D:
				_collectGeom(n, seen, out)
			for c in n.get_children():
				if c is Viewport:
					continue
				stack.append(c)
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
	var items := _items
	var n := items.size()
	var cols := int(ceil(sqrt(float(maxi(1, n)))))
	var span := cols * CELL
	var mn := _models.size()
	var mcols := int(ceil(sqrt(float(maxi(1, mn)))))
	var mspan := mcols * MCELL
	var wide := maxf(span, mspan)
	# light combos of the Compatibility scene shader (_lightCombos): an instance lit by no / an omni / a spot light
	# compiles its own specialization; the key light (directional) is always there
	for ci in _combos.size():
		var combo: int = _combos[ci]
		var root := Node3D.new()
		root.name = "WarmGallery%d" % combo
		var origin := Vector3(ci * (span + mspan + 400.0), SKY, 0.0)
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
		if combo & 1:
			var om := OmniLight3D.new()
			om.omni_range = wide * 1.5 + 10.0
			om.light_energy = 0.5
			om.position = Vector3(0, 4.0, 0)
			root.add_child(om)
		if combo & 2:
			var sp := SpotLight3D.new()
			sp.spot_range = wide * 1.5 + 20.0
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
		# the real models, MCHUNK per frame, at full size around the same spot (same lights)
		if mn > 0:
			_cam.size = mspan + 4.0
			var mroot := Node3D.new()
			mroot.name = "WarmModels"
			root.add_child(mroot)
			for c0 in range(0, mn, MCHUNK):
				var shown: Array = []
				for i in range(c0, mini(mn, c0 + MCHUNK)):
					var node: Node3D = _models[i].node
					if not is_instance_valid(node):
						continue
					DAU.detach(node)
					mroot.add_child(node)
					node.transform = Transform3D(Basis(), Vector3((i % mcols + 0.5) * MCELL - mspan / 2.0, -1.0, (i / mcols + 0.5) * MCELL - mspan / 2.0))
					node.visible = true
					shown.append(node)
					stats.models += 1
				await _frame()
				for node in shown:
					if is_instance_valid(node):
						mroot.remove_child(node)
		root.visible = false

# Light-type specializations worth compiling: omni always (the 8 pooled area lights, fx.flashLight); spot only when
# the station has spot lights (it has none today: every SpotLight3D combo would be wasted programs).
func _lightCombos() -> Array:
	var spot := false
	var stack: Array = [game.scene]
	while not stack.is_empty() and not spot:
		var nd: Node = stack.pop_back()
		if nd is SpotLight3D:
			spot = true
		for c in nd.get_children():
			stack.append(c)
	return [0, 1, 2, 3] if spot else [0, 1]

# ------------------------------------------------------------------------------------------------ real models
# Characters are drawn as they are, not as proxies: a skinned mesh goes through the skinning pass (its own programs)
# and is then drawn from the skinned vertex buffers, a different vertex layout than the bind-pose mesh (ANGLE's D3D
# backend compiles a separate shader per vertex layout on the first draw). One model of every pooled zombie variant,
# of every special, of the popped-head pool and of every hero (built here: the player's is only built by newGame).
var _models: Array = []      # [{node: Node3D, xf, vis, made: bool}]
var _combos: Array = [0, 1]

func _collectModels() -> Array:
	var out: Array = []
	var add := func(node, made: bool) -> void:
		if node is Node3D and is_instance_valid(node) and not (node as Node).is_inside_tree():
			out.append({"node": node, "xf": (node as Node3D).transform, "vis": (node as Node3D).visible, "made": made})
	var ZT = load("res://scripts/actors/zombie_types.gd") if ResourceLoader.exists("res://scripts/actors/zombie_types.gd") else null
	if ZT != null and ZT.get("pools") is Dictionary:
		for list in ZT.pools.values():
			for m in list:
				if m is Dictionary and m.get("group") is Node3D:
					add.call(m.group, false)
					break
	for z in _zombies:
		add.call(z.get("group"), false)
	# screens.gd gives every zombie's materials their feed variant on zombie:spawn (a new Shader with the skin swap
	# + the eye overlay material): done now for the pooled models, so the first spawn neither builds nor compiles them
	var scr = game.get("screens")
	if scr != null and scr.has_method("_prepZombie"):
		for list in (ZT.pools.values() if ZT != null and ZT.get("pools") is Dictionary else []):
			for m in list:
				if m is Dictionary and m.get("group") is Node3D:
					scr._prepZombie(m)
		for z in _zombies:
			scr._prepZombie(z)
	var Z = game.get("zombies")
	var heads = Z.get("_heads") if Z != null else null
	if heads is Dictionary:
		for list in heads.values():
			if list is Array and not list.is_empty() and list[0] is Dictionary:
				add.call(list[0].get("pivot"), false)
	var first = null
	if ResourceLoader.exists("res://scripts/actors/heroes.gd"):
		var H = load("res://scripts/actors/heroes.gd")
		for h in H.HEROES:
			var hero = H.buildHero(h.id, game)
			if hero is Dictionary and hero.get("group") is Node3D:
				if game.mats != null and game.mats.has_method("applyHeroFade"):
					game.mats.applyHeroFade(hero.group)
				add.call(hero.group, true)
				if first == null:
					first = hero
	# hero copies with their own (skinned) materials: the Double Vision commercial's tinted twins (sponsors.gd
	# _makeDups) and an Instant Replay afterimage (perks.gd _makeGhosts: the same material on a hero copy)
	if first != null:
		var sp = game.get("sponsors")
		if sp != null and sp.has_method("_makeDups"):
			for d in sp._makeDups(first, null):
				if d is Dictionary:
					add.call(d.get("holder"), true)
					for m in d.get("meshes", []):
						_keepMat(m.material_override)
		if ResourceLoader.exists("res://scripts/game/perks.gd"):
			var PL = load("res://scripts/game/perks.gd")
			var c: Dictionary = PL.cloneHero(first, [])
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(Color("#7FEFFF"), 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			mat.disable_fog = true
			for m in c.meshes:
				m.material_override = mat
			add.call(c.group, true)
			_keepMat(mat)
	return out

# A StandardMaterial3D's shader lives only as long as a material with its feature set exists: the ones of the
# copies above are made again by their owners later (same features), so one of each is kept alive here or their
# programs would be freed with the warm-up copies and compiled again on first use.
static var _kept: Array = []
static func _keepMat(m) -> void:
	if m is BaseMaterial3D and not _kept.has(m):
		_kept.append(m)

func _restoreModels() -> void:
	for e in _models:
		var node = e.node
		if not is_instance_valid(node):
			continue
		DAU.detach(node)
		if e.made:
			node.queue_free()
			continue
		node.transform = e.xf
		node.visible = e.vis
	_models.clear()

# ------------------------------------------------------------------------------------------------ 2D
# The default CanvasItem material and every CanvasItem material in the tree (HUD, menus, overlays, hidden or not),
# each drawn once with every kind of canvas command: the Compatibility canvas shader specializes per command
# (rect / nine-patch / primitive (lines) / attributes (polygons: circles, arcs, thick lines) / attributes +
# instancing (multimesh)).
class CanvasProbe extends Control:
	var tex: Texture2D
	var sb: StyleBoxTexture
	var mm: MultiMesh
	func _draw() -> void:
		var w := Color.WHITE
		draw_rect(Rect2(0, 0, 6, 6), w)
		draw_texture_rect(tex, Rect2(6, 0, 6, 6), false)
		draw_style_box(sb, Rect2(12, 0, 12, 12))
		draw_line(Vector2(0, 8), Vector2(6, 10), w)
		draw_primitive(PackedVector2Array([Vector2(0, 12), Vector2(4, 12), Vector2(2, 15)]), PackedColorArray([w, w, w]), PackedVector2Array())
		draw_primitive(PackedVector2Array([Vector2(5, 12), Vector2(9, 12), Vector2(9, 15), Vector2(5, 15)]), PackedColorArray([w, w, w, w]), PackedVector2Array())
		draw_colored_polygon(PackedVector2Array([Vector2(0, 16), Vector2(6, 16), Vector2(3, 22)]), w)
		draw_colored_polygon(PackedVector2Array([Vector2(8, 16), Vector2(14, 16), Vector2(11, 22)]), w, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]), tex)
		draw_arc(Vector2(20, 20), 3.0, 0.0, TAU, 12, w, 1.5, true)
		draw_line(Vector2(14, 24), Vector2(20, 26), w, 2.0)
		draw_multimesh(mm, tex)

func _canvasPass() -> void:
	var seen := {}
	var mats: Array = [null]
	var stack: Array = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var m = (n as CanvasItem).material
			var k = null
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				k = (m as ShaderMaterial).shader.get_instance_id()
			elif m is CanvasItemMaterial:
				var cm := m as CanvasItemMaterial
				k = "cim%d|%d" % [cm.blend_mode, cm.light_mode]
			if k != null and not seen.has(k):
				seen[k] = true
				mats.append(m)
		for c in n.get_children():
			stack.append(c)
	var vp := SubViewport.new()
	vp.name = "Warmup2D"
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.add_child(vp)
	_made.append(vp)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 1
	sb.texture_margin_right = 1
	sb.texture_margin_top = 1
	sb.texture_margin_bottom = 1
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(0, 2)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(24, 24)))
	mm.set_instance_color(0, Color.WHITE)
	var cols := int(ceil(sqrt(float(mats.size()))))
	var cell := 256.0 / cols
	for i in mats.size():
		var cp := CanvasProbe.new()
		cp.tex = tex
		cp.sb = sb
		cp.mm = mm
		cp.material = mats[i]
		cp.position = Vector2((i % cols) * cell, (i / cols) * cell)
		cp.size = Vector2(cell, cell)
		vp.add_child(cp)
		stats.canvas += 1
	await _frame()

# ------------------------------------------------------------------------------------------------ CPU prebuilds
var _extras: Array = []      # off-tree models built only for the gallery (freed at the end)
var _borrowed: Array = []    # off-tree models of other systems shown to the gallery (left alone)
var _zombies: Array = []     # zombie records built for the gallery (released into their pools at the end)

func _releaseZombies() -> void:
	var ZT = load("res://scripts/actors/zombie_types.gd")
	for z in _zombies:
		if z.def.get("release") is Callable:
			z.def.release.call(game, z)
		elif z.get("model") is Dictionary:
			ZT.releaseModel(z.model)
	_zombies.clear()

# Models the game builds on first use, off-tree: built once here so their GLB loads / material conversions are
# cached (props.gd keeps the scenes) and their shaders go through the gallery. Perk costumes (+ gold leaf).
func _buildExtras() -> Array:
	var out: Array = []
	var props = game.get("props")
	if props == null or not props.has_method("build"):
		return out
	var P = load("res://scripts/game/perks.gd") if ResourceLoader.exists("res://scripts/game/perks.gd") else null
	var costumes = P.COSTUMES if P != null and "COSTUMES" in P else {}
	if costumes is Dictionary:
		for id in costumes.values():
			for v in [str(id), str(id) + "_gold"]:
				var n = props.build(v, {}) if props.has_method("_variant") and props._variant(v, {}) != null else null
				if n is Node3D:
					out.append(n)
	# the power-up drops (powerups.gd builds one when a kill drops it)
	var PU = load("res://scripts/game/powerups.gd") if ResourceLoader.exists("res://scripts/game/powerups.gd") else null
	if PU != null and "POWERUP_TYPES" in PU:
		for t in PU.POWERUP_TYPES:
			var v := "drop_" + str(t)
			var n = props.build(v, {}) if props.has_method("_variant") and props._variant(v, {}) != null else null
			if n is Node3D:
				out.append(n)
	# the Double Vision weapon ghosts (weapons.gd builds them on the perk's first frame: a weapon model with the
	# ghost material)
	var W = load("res://scripts/game/weapons.gd") if ResourceLoader.exists("res://scripts/game/weapons.gd") else null
	var WM = load("res://scripts/game/weapon_models.gd") if ResourceLoader.exists("res://scripts/game/weapon_models.gd") else null
	if W != null and WM != null and W.has_method("ghostMaterial"):
		var gm = WM.buildModel("revolver_38", false, null, game)
		if gm is Node3D:
			var gmat = W.ghostMaterial("#5FF4FF")
			DAU.traverse(gm, func(o):
				if o is GeometryInstance3D:
					(o as GeometryInstance3D).material_override = gmat)
			out.append(gm)
	# one model of every zombie type that is not pooled yet (later rounds' specials): built as a spawn would and
	# released into its type's pool afterwards (_releaseZombies), so the first one of each kind spawns hitch-free
	var Z = game.get("zombies")
	var ZT = load("res://scripts/actors/zombie_types.gd") if ResourceLoader.exists("res://scripts/actors/zombie_types.gd") else null
	if Z != null and ZT != null and Z.has_method("_record"):
		ZT.getType("tuned_in")
		for id in ZT.ZOMBIE_TYPES.keys():
			if id == "tuned_in":
				continue
			var def: Dictionary = ZT.getType(id)
			if def.get("fallback", false):
				ZT.prewarmModels(game, id, 1)
			elif def.get("build") is Callable:
				var z: Dictionary = Z._record(def, 1, {})
				def.build.call(game, z)
				if z.get("group") is Node3D:
					_zombies.append(z)
	# the commercial's gag props (sponsors.gd builds them on the first commercial)
	var sp = game.get("sponsors")
	if sp != null and sp.has_method("_ensureGags"):
		sp._ensureGags()
		var gg = sp.get("_gags")
		if gg is Dictionary:
			for v in gg.values():
				if v is Node3D and not (v as Node).is_inside_tree():
					_borrowed.append(v)
	return out

func _prebuild() -> void:
	if ResourceLoader.exists("res://scripts/ui/commercial.gd"):
		var CO = load("res://scripts/ui/commercial.gd")
		var ov = CO.getOverlay() if CO != null else null
		if ov != null and ov.has_method("_ensure") and ov.has_method("_resize"):
			ov._ensure()
			ov._resize()
