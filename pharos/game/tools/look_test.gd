extends Node3D
## Rendering sanity test: shadows on/off must give the same brightness on lit faces.
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var shadow: bool = args.get("shadow", "1") == "1"
	RenderingServer.global_shader_parameter_set("g_sun_comp", 1.0 if shadow else 0.0)
	RenderingServer.global_shader_parameter_set("g_amb_sky", Vector3(0.30, 0.38, 0.55))
	RenderingServer.global_shader_parameter_set("g_amb_ground", Vector3(0.22, 0.18, 0.13))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lowpoly.gdshader")
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 6, 9); cam.look_at(Vector3(0, 0.5, 0)); cam.fov = 40
	var sun := DirectionalLight3D.new(); add_child(sun); sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = shadow
	sun.light_color = Color(1.0, 0.92, 0.8); sun.light_energy = 1.0
	var mb := MeshBuilder.new(3)
	mb.vary = 0.03
	mb.block(Vector3(0, -0.2, 0), Vector3(16, 0.2, 16), Color("A3B860"))
	mb.block(Vector3(-2.5, 0, 0), Vector3(1.4, 1.4, 1.4), Color("F3EFE6"))
	mb.roof_gable(Vector3(-2.5, 1.4, 0), 1.7, 1.7, 0.7, Color("C8623E"), Color("F3EFE6"))
	mb.cyl(Vector3(0, 0, 0), 2.0, 0.45, 0.4, 8, Color("E3D3B4"))
	mb.ico(Vector3(2.5, 0.7, 0), 0.8, Color("8C9C66"), 1, 0.12)
	mb.cyl(Vector3(2.5, 0, 0), 0.5, 0.12, 0.1, 6, Color("8A5A3B"))
	mb.sphere(Vector3(0, 0.4, 2), 0.4, Color("2E6FB0"), 10, 6)
	mb.cyl(Vector3(-1.2, 0, 2.2), 1.6, 0.35, 0.0, 7, Color("3E5B3A"))
	mb.box(Vector3(1.5, 0.3, 2.3), Vector3(0.3, 0.3, 0.3), Color(0.49, 0.96, 1.0, 0.5))
	var mi := MeshInstance3D.new(); mi.mesh = mb.commit(); mi.material_override = mat; add_child(mi)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("BFE6F2")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.BLACK; e.ambient_light_energy = 0.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e; add_child(env)
	print("tris: ", mb.tri_count())
