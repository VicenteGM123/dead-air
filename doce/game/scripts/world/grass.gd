class_name Grass
extends Node3D
## Grass and meadow flowers on the GPU (shaders/grass.gdshader): three MultiMesh grids of tufts that follow the
## camera in whole cells, so the same world cell always grows the same tuft and nothing is generated on the CPU
## (no hitches on the web, no matter how big the island). Where grass grows, how tall, which colour and where the
## flower drifts are comes from the World's textures: the terrain heights (exact triangles), the ground colour map
## (a = grassiness) and the ground map (paths, props, bare soil, contact AO).
##
##   near   0.5 m cells, 22 m half size: dense tufts round the hero
##   far    1.1 m cells, 50 m half size (skips the near square): sparser, larger tufts out to ~50 m
##   bloom  1.1 m cells, 27 m half size: flower sprigs in drifts
## Draw cost: 3 draw calls, ~18k instances, ~345k triangles (collapsed instances cost a vertex shader run each,
## no fragments).
##
##   var grass := Grass.new(); add_child(grass); grass.build(world)   # world: World (terrain textures)
## Debug: grass=0 builds nothing.

const LAYERS := [
	{"name": "GrassNear", "spacing": 0.5, "half": 22.0, "scale": Vector2(1.2, 1.85), "density": 1.0, "flowers": 0.0, "fade": Vector2(17.0, 25.0)},
	{"name": "GrassFar", "spacing": 1.1, "half": 50.0, "scale": Vector2(1.75, 2.5), "density": 0.85, "flowers": 0.0, "fade": Vector2(38.0, 49.0)},
	{"name": "Flowers", "spacing": 1.1, "half": 27.0, "scale": Vector2(1.45, 1.95), "density": 0.95, "flowers": 1.0, "fade": Vector2(20.0, 27.0)},
]

var src: Object = null
var instances := 0
var _mmis: Array[MultiMeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []


func build(source: Object) -> void:
	src = source
	if Game.arg("grass", "1") == "0":
		return
	var terrain: Variant = src.get("terrain")
	if terrain == null:
		return
	var shader: Shader = load("res://shaders/grass.gdshader")
	var tuft := ModelsNature.grass_tuft_toon(7)
	var tuft_far := ModelsNature.grass_tuft_far(7)
	var bloom := ModelsNature.grass_flowers(3)
	var near_half: float = LAYERS[0]["half"]
	for ly in LAYERS:
		var sp: float = ly["spacing"]
		var half: float = ly["half"]
		var n := int(ceil(half * 2.0 / sp))
		var buf := PackedFloat32Array()
		buf.resize(n * n * 12)
		var k := 0
		for iz in n:
			for ix in n:
				var o := k * 12
				buf[o] = 1.0
				buf[o + 3] = (ix - n / 2) * sp
				buf[o + 5] = 1.0
				buf[o + 10] = 1.0
				buf[o + 11] = (iz - n / 2) * sp
				k += 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bloom if float(ly["flowers"]) > 0.5 else (tuft_far if String(ly["name"]) == "GrassFar" else tuft)
		mm.instance_count = n * n
		mm.buffer = buf
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("height_tex", terrain.height_tex)
		mat.set_shader_parameter("color_tex", terrain.color_tex)
		mat.set_shader_parameter("ground_tex", terrain.ground_tex)
		var ext: float = terrain.EXT
		var gm_ext: float = terrain.GM_EXT
		mat.set_shader_parameter("grid", Vector4(-ext, -ext, float(terrain.CELL), float(terrain.N)))
		mat.set_shader_parameter("ground_rect", Vector4(-gm_ext, -gm_ext, gm_ext * 2.0, gm_ext * 2.0))
		mat.set_shader_parameter("spacing", sp)
		mat.set_shader_parameter("tuft_scale", ly["scale"])
		mat.set_shader_parameter("density", ly["density"])
		mat.set_shader_parameter("flowers", ly["flowers"])
		mat.set_shader_parameter("fade_near", (ly["fade"] as Vector2).x)
		mat.set_shader_parameter("fade_far", (ly["fade"] as Vector2).y)
		mat.set_shader_parameter("skip_half", near_half - 1.0 if String(ly["name"]) == "GrassFar" else 0.0)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = ly["name"]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-half - 2.0, -30.0, -half - 2.0), Vector3(half * 2.0 + 4.0, 120.0, half * 2.0 + 4.0))
		add_child(mmi)
		_mmis.append(mmi)
		_mats.append(mat)
		instances += n * n
	_apply_quality()


func _apply_quality() -> void:
	var q := int(Settings.get_v("quality"))
	var k := 0.55 if q <= 0 else (0.8 if q == 1 else 1.0)
	for i in _mats.size():
		_mats[i].set_shader_parameter("density", float(LAYERS[i]["density"]) * k)


func _process(_delta: float) -> void:
	if _mmis.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var f := -cam.global_transform.basis.z
	var flat := Vector2(f.x, f.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector2.ZERO
	var hero_p := Vector3(0, -100, 0)
	var h: Variant = Game.get("hero")
	if h != null and is_instance_valid(h) and (h as Node3D).is_inside_tree():
		hero_p = (h as Node3D).global_position
	var near_c := Vector3.ZERO
	for i in _mmis.size():
		var ly: Dictionary = LAYERS[i]
		var sp: float = ly["spacing"]
		var half: float = ly["half"]
		# Centre the grid a little ahead of the camera (most of it in view), snapped to whole cells.
		var c := Vector2(cp.x, cp.z) + flat * half * 0.45
		var snapped := Vector3(snappedf(c.x, sp), 0.0, snappedf(c.y, sp))
		_mmis[i].global_position = snapped
		if i == 0:
			near_c = snapped
		_mats[i].set_shader_parameter("hero_pos", hero_p)
		_mats[i].set_shader_parameter("grid_center", near_c)
