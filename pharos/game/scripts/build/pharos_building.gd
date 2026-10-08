class_name PharosBuilding
extends Building
## The lighthouse: holds Hestia's flame. Its fire lights the plaza at night and its beam sweeps the sea.

var flame: MeshInstance3D
var flame_core: MeshInstance3D
var halo: MeshInstance3D
var light: OmniLight3D
var beam: Node3D
var _flame_k := 1.0
var _beam_k := 0.0


func _ready() -> void:
	super()
	flame = MeshInstance3D.new()
	flame.mesh = _flame_mesh(Pal.FIRE, 0.95, 1.9)
	flame.material_override = Materials.lowpoly()
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	flame_core = MeshInstance3D.new()
	flame_core.mesh = _flame_mesh(Pal.FIRE_CORE, 0.5, 1.2)
	flame_core.material_override = Materials.lowpoly()
	flame_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame_core)
	halo = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(7.0, 7.0)
	halo.mesh = qm
	halo.material_override = Materials.glow_add()
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.set_instance_shader_parameter("tint_color", Vector3(1.0, 0.72, 0.4))
	add_child(halo)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.42)
	light.omni_range = 26.0
	light.omni_attenuation = 1.2
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	beam = Node3D.new()
	add_child(beam)
	# Two opposite cones, like a real lighthouse lens turning.
	for i in 2:
		var q := MeshInstance3D.new()
		q.mesh = Materials.cone_mesh(64.0, 0.6, 9.0, 28)
		q.material_override = Materials.beam_cone(64.0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.rotation = Vector3(0.05, PI * i, 0)
		beam.add_child(q)
	_place_fire()
	var crackle := Sfx.loop("fire", flame, -6.0)
	if crackle is AudioStreamPlayer3D:
		(crackle as AudioStreamPlayer3D).unit_size = 9.0


func _beam_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/beam.gdshader")
	return m


func _flame_mesh(col: Color, r: float, h: float) -> ArrayMesh:
	var mb := MeshBuilder.new(5)
	mb.cyl(Vector3(0, 0, 0), h, r, 0.0, 6, col, true, 0.3)
	mb.cyl(Vector3(r * 0.35, 0, 0.1), h * 0.7, r * 0.6, 0.0, 5, col, true, 1.1)
	mb.cyl(Vector3(-r * 0.3, 0, -0.15), h * 0.8, r * 0.55, 0.0, 5, col, true, 2.0)
	return mb.commit()


func _on_model_changed() -> void:
	if flame:
		_place_fire()


func _place_fire() -> void:
	var f: Vector3 = anchors.get("fire", Vector3(0, height, 0))
	flame.position = f
	flame_core.position = f + Vector3(0, 0.05, 0)
	halo.position = f + Vector3(0, 1.0, 0)
	light.position = f + Vector3(0, 1.2, 0)
	beam.position = f + Vector3(0, 0.9, 0)


func _process(delta: float) -> void:
	super(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var night: float = Game.main.tod.night_amount() if Game.main and Game.main.tod else 0.0
	var target_k := 1.0 if alive else 0.0
	_flame_k = lerpf(_flame_k, target_k, 1.0 - exp(-delta * 2.0))
	var fl := 1.0 + sin(t * 9.0) * 0.06 + sin(t * 13.7) * 0.05
	flame.scale = Vector3(1.0 + sin(t * 7.0) * 0.05, fl * (0.9 + 0.1 * level), 1.0 + cos(t * 6.3) * 0.05) * maxf(_flame_k, 0.001)
	flame.rotation.y = t * 0.8
	flame_core.scale = Vector3(1.0, 1.0 + sin(t * 11.0) * 0.12, 1.0) * maxf(_flame_k, 0.001)
	flame_core.rotation.y = -t * 1.3
	flame.visible = _flame_k > 0.02
	flame_core.visible = flame.visible
	halo.set_instance_shader_parameter("intensity", (0.35 + 0.9 * night) * _flame_k * fl)
	light.light_energy = (0.25 + 1.6 * night) * _flame_k * fl
	light.omni_range = 22.0 + 4.0 * level
	_beam_k = lerpf(_beam_k, night * _flame_k, 1.0 - exp(-delta * 1.5))
	beam.visible = _beam_k > 0.02
	beam.rotation.y = t * 0.35
	for q in beam.get_children():
		(q as MeshInstance3D).set_instance_shader_parameter("intensity", _beam_k)


func _on_death() -> void:
	super()
	Sfx.play("structure_break", global_position, 4.0, 0.7)
	if Game.main and Game.main.has_method("on_pharos_destroyed"):
		Game.main.on_pharos_destroyed()


func upgrade() -> void:
	super()
	Game.pharos_level = level
	Game.pharos_level_changed.emit(level)
