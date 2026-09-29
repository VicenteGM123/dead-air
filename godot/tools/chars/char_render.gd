# chars-godot QA harness (derived from godot-core tools/material_test.gd, + "chars" of the spec; JS side:
# tools/chars/charref_entry.js built by charref_build.mjs, driven by tools/jsref/run.mjs): renders a material_test_*.json scene with the real render / materials / lights / geo
# systems (this node plays the Game: time, params, events ...), exactly like tools/jsref renders it with the
# original three.js modules, so both images can be compared.
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
#     godot --path . --resolution 1280x720 res://tools/material_test.tscn -- spec=res://tools/chars/char_scene.json out=/abs/out.png
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

func rand() -> float:
	return randf()

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var i := a.find("=")
		if i > 0:
			params[a.substr(0, i)] = a.substr(i + 1)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(params.get("spec", "res://tools/chars/char_scene.json")))
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
	var base: String = str(params.get("spec", "res://tools/chars/char_scene.json")).get_base_dir() + "/"
	for ob in spec.get("objects", []):
		var mat = _makeMat(ob.mat, base)
		var g: Mesh = callv_geo(ob.geo)
		if ob.has("ao"):
			g = DAGeo.withAO(g, ob.ao)
		var mi := DAGeo.mesh(g, mat, {"pos": ob.get("pos"), "rot": ob.get("rot"), "scale": ob.get("scale"), "cast": ob.get("cast", true)})
		if ob.has("bulge") and mat is DAMaterial and mat.uniforms.has("uBulge"):
			mat.uniforms.uBulge.value = float(ob.bulge)
		scene.add_child(mi)
	_addChars(spec)
	if spec.get("feedCamera", false):
		camera.cull_mask |= 1 << 17
	camera.cull_mask |= 1 << Config.LAYERS.ZOMBIES
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
		if _out != "":
			img.save_png(_out)
			print("material_test: saved ", _out)
		get_tree().quit()


# chars-godot: characters of the spec, deterministic animator / face state (same as charref/entry.js)
func _addChars(spec: Dictionary) -> void:
	for ch in spec.get("chars", []):
		var c := CharRuntime.buildCharacter(ch.id, {"envMap": mats.envMap, "globals": true, "heroFade": ch.get("heroFade", false), "animator": ch.get("animator", true)})
		var a = c.animator
		if a is Rig.Animator:
			a.seed = 1.5; a.phase = 0.7; a.t = 2.0
			a.wob = {"amp": 1.1, "tilt": 0.05, "armL": 0.1, "armR": -0.08, "speed": 0.95}
		c.face.auto = false
		c.face.blinkT = 99.0
		if ch.has("expr"): c.face.setExpression(ch.expr[0], ch.expr[1])
		if ch.has("look"): c.face.setLook(ch.look[0], ch.look[1])
		for k in ch.get("poses", {}):
			a.pose(k, ch.poses[k])
		for i in int(ch.get("frames", 30)):
			c.update(1.0 / 30.0, ch.get("st", {}))
		var ov: Dictionary = ch.get("overrides", {})
		var bm: ShaderMaterial = c.skinnedMesh.material_override
		bm = bm.duplicate()
		DAU.traverse(c.group, func(o):
			if o is MeshInstance3D and o.material_override != null and o.material_override.shader == bm.shader:
				o.material_override = bm)
		if ov.has("envMapIntensity"): bm.set_shader_parameter("uEnv", float(ov.envMapIntensity))
		for k in ["uIBLDiffuse", "uRimStrength", "uAOAmount", "uDebug"]:
			if ov.has(k): bm.set_shader_parameter(k, ov[k])
		if ch.get("feed", false):
			_feedVariant(c)
		c.group.position = DAU.v3(ch.get("pos", [0, 0, 0]))
		c.group.rotation.y = float(ch.get("rotY", 0.0))
		scene.add_child(c.group)

# screens.gd feed "human skin" variant of the body material (same injection as screens.gd _skinShader), so the
# variant shader is compiled and drawn too (the camera sees feed bit 17 when the spec sets "feedCamera").
func _feedVariant(c) -> void:
	var S = load("res://scripts/game/screens.gd")
	var m: ShaderMaterial = c.skinnedMesh.material_override
	var code: String = m.shader.code
	var fi := code.find("void fragment()")
	var at := code.find(S.SKIN_AT, fi)
	if at < 0:
		push_error("feed variant: injection point missing")
		return
	var ls := code.rfind("\n", at) + 1
	var sh := Shader.new()
	sh.code = code.substr(0, fi) + S.SKIN_SWAP + "\n" + code.substr(fi, ls - fi) + S.SKIN_DIFFUSE + code.substr(ls)
	var v: ShaderMaterial = m.duplicate()
	v.shader = sh
	DAU.traverse(c.group, func(o):
		if o is MeshInstance3D and o.material_override == m:
			o.material_override = v)
