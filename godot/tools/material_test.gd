# godot-core QA harness: renders a material_test_*.json scene with the real render / materials / lights / geo
# systems (this node plays the Game: time, params, events ...), exactly like tools/jsref renders it with the
# original three.js modules, so both images can be compared.
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --path . --resolution 1280x720 res://tools/material_test.tscn -- spec=res://tools/material_test_scene.json out=/abs/out.png
extends Node

var params := {}
var time := {"now": 0.0, "dt": 0.0, "realNow": 0.0, "realDt": 0.0, "frame": 0, "scale": 1.0}
var events = null
var state := "playing"
var render
var scene: Node3D
var camera: Camera3D
var tex
var mats
var lights
var level = null
var player := {"pos": Vector3.ZERO}
var machines := {"powerOn": true}
var cam = null
var cards = null
var props = null
var screens = null
var _out := ""
var _wait := 0
var _sweep = null

# placeProp test doubles (collision / screen registration are other systems)
class MockCol extends RefCounted:
	var boxes: Array = []
	func addBox(mn, mx, opts = {}) -> void:
		boxes.append([mn, mx, opts])
		print("material_test: col.addBox ", mn, " ", mx, " ", opts)
class MockScreens extends RefCounted:
	func register(mesh, group, opts = {}) -> void:
		print("material_test: screens.register ", mesh.name if mesh else null, " ", group, " ", opts)

func rand() -> float:
	return randf()

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			params[a.substr(0, i)] = a.substr(i + 1)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(params.get("spec", "res://tools/material_test_scene.json")))
	_out = params.get("out", "")
	events = load("res://scripts/core/events.gd").new()
	render = load("res://scripts/core/render.gd").new(self)
	scene = render.scene
	camera = render.camera
	render.dynamic = false
	if ResourceLoader.exists("res://scripts/core/textures.gd"):
		tex = load("res://scripts/core/textures.gd").new(self)
	mats = load("res://scripts/core/materials.gd").new(self)
	machines.powerOn = spec.get("powered", true)
	player.pos = DAU.v3(spec.get("focus", [0, 0, 0]))
	lights = load("res://scripts/core/lights.gd").new(self)
	var U: Dictionary = mats.uniforms
	var G: Dictionary = spec.get("globals", {})
	for k in G:
		U[k].value = DAU.v3(G[k]) if G[k] is Array else float(G[k])
	for k in spec.get("post", {}):
		render.post[k] = float(spec.post[k])
	var c: Dictionary = spec.camera
	camera.fov = float(c.get("fov", 70))
	camera.position = DAU.v3(c.pos)
	camera.look_at(DAU.v3(c.target), Vector3.UP)
	if spec.has("fog"):
		render.fog = {"color": Color(spec.fog.color), "near": float(spec.fog.near), "far": float(spec.fog.far)}
	for a in spec.get("anchors", []):
		lights.addAnchor(a)
	var base: String = str(params.get("spec", "res://tools/material_test_scene.json")).get_base_dir() + "/"
	for ob in spec.get("objects", []):
		var mat = _makeMat(ob.mat, base)
		var g: Mesh = callv_geo(ob.geo)
		if ob.has("ao"):
			g = DAGeo.withAO(g, ob.ao)
		var mi := DAGeo.mesh(g, mat, {"pos": ob.get("pos"), "rot": ob.get("rot"), "scale": ob.get("scale"), "cast": ob.get("cast", true)})
		if ob.has("bulge") and mat is DAMaterial and mat.uniforms.has("uBulge"):
			mat.uniforms.uBulge.value = float(ob.bulge)
		scene.add_child(mi)
	if spec.has("props"):
		level = {"col": MockCol.new()}
		screens = MockScreens.new()
		props = load("res://scripts/props/props.gd").new(self)
		for pr in spec.props:
			var g = props.place(scene, pr.id, {"pos": pr.get("pos", [0, 0, 0]), "rotY": float(pr.get("rotY", 0.0)), "opts": pr.get("opts", {}), "area": "lobby"})
			if g != null:
				print("material_test: prop ", pr.id, " ud=", JSON.stringify(_udJson(DAU.ud(g))))
	var dt := 1.0 / 30.0
	for i in int(spec.get("frames", 45)):
		time.realNow += dt
		time.now += dt
		time.frame += 1
		lights.update(dt)
		mats.update(dt)
		if tex != null and tex.has_method("update"):
			tex.update(dt)
		if spec.has("time"):
			U.uTime.value = float(spec.time)
		render.frame(dt)
	_wait = 12

func _udJson(v):
	if v is Node:
		return "<node %s>" % v.name
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _udJson(v[k])
		return o
	if v is Array:
		return v.map(func(x): return _udJson(x))
	return v

func callv_geo(g: Array) -> Mesh:
	var kind: String = g[0]
	var args: Array = g.slice(1)
	for i in args.size():
		if args[i] is float and args[i] == floorf(args[i]) and kind in ["sphere", "plane", "capsule", "cylinder", "torus", "roundedBox"]:
			# segment counts are ints in GDScript signatures
			pass
	match kind:
		"sphere":
			return DAGeo.sphere(args[0], int(args[1]), int(args[2]))
		"plane":
			return DAGeo.plane(args[0], args[1], int(args[2]), int(args[3]))
		"box":
			return DAGeo.box(args[0], args[1], args[2])
		"roundedBox":
			return DAGeo.roundedBox(args[0], args[1], args[2], args[3], int(args[4]))
		"cylinder":
			return DAGeo.cylinder(args[0], args[1], args[2], int(args[3]))
		"capsule":
			return DAGeo.capsule(args[0], args[1], int(args[2]), int(args[3]))
		"torus":
			return DAGeo.torus(args[0], args[1], int(args[2]), int(args[3]))
	push_error("unknown geo " + kind)
	return DAGeo.box(1, 1, 1)

func _makeMat(m: Dictionary, base: String):
	var o: Dictionary = m.get("opts", {}).duplicate()
	var map: Texture2D = null
	if m.get("map"):
		var img := Image.load_from_file(ProjectSettings.globalize_path(base + str(m.map)))
		map = ImageTexture.create_from_image(img)
		map.set_meta("wrap", m.get("mapWrap", "clamp"))
	match str(m.get("kind", "toon")):
		"glow":
			var it := float(o.get("intensity", 2.0))
			o.erase("intensity")
			if map:
				o["map"] = map
			return mats.glow(m.color, it, o)
		"basic":
			if map:
				o["map"] = map
			return mats.basic(m.color, o)
		"glass":
			return mats.glass(m.color, o)
		"skin":
			return mats.skin(m.color, o)
		"screen":
			return mats.screen(map, o)
		"rubberGlass":
			return mats.rubberGlass(map, o)
	if map:
		o["map"] = map
	return mats.toon(m.color, o)

func _process(_d: float) -> void:
	if _wait <= 0:
		return
	_wait -= 1
	if _wait == 0:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if params.has("probe"):
			var vi: Image = render.view.get_texture().get_image()
			var bi: Image = render._bloom.comp.vp.get_texture().get_image()
			for pt in [[10, 10], [640, 700], [640, 100]]:
				var q := Vector2i(int(pt[0] * vi.get_width() / 1280.0), int(pt[1] * vi.get_height() / 720.0))
				print("material_test: probe ", pt, " view ", vi.get_pixelv(q), " bloom ", bi.get_pixelv(q / 2), " out ", img.get_pixelv(Vector2i(pt[0], pt[1])))
		if _out != "":
			img.save_png(_out)
			print("material_test: saved ", _out)
		# sweep=<json>: [{"levels": [7 floats], "intensity": x, "out": "/abs.png"}, ...] (glow tuning)
		if params.has("sweep") and _sweep == null:
			_sweep = JSON.parse_string(FileAccess.get_file_as_string(params.sweep))
		if _sweep is Array and not _sweep.is_empty():
			var v: Dictionary = _sweep.pop_front()
			for i in 7:
				render.env.set_glow_level(i, float(v.levels[i]))
			render.env.glow_intensity = float(v.intensity)
			if v.has("scale"):
				render.env.glow_hdr_scale = float(v.scale)
			_out = v.out
			_wait = 8
			return
		get_tree().quit()
