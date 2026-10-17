extends Node3D
class_name Cauldron
## Caldero: cuerpo en pixel art, líquido teñido, fuego animado, burbujas y vapor.

const PX := 0.035

var body: Sprite3D
var liquid: Sprite3D
var fire: AnimatedSprite3D
var light: OmniLight3D
var bubbles: GPUParticles3D
var steam: GPUParticles3D
var embers: GPUParticles3D
var liquid_color := Color("3b3156")
var _bubble_mat: ParticleProcessMaterial
var _t := 0.0
var _bubble_timer := 1.0
var activity := 0.2
var copper := false
var _flash := 0.0
var base_energy := 2.2

func build() -> void:
	var hearth_back := _sprite("res://assets/props/logs.png", PX, Vector3(0, 0.0, -0.02))
	hearth_back.offset = Vector2(-13, 0)
	fire = AnimatedSprite3D.new()
	var sf := SpriteFrames.new()
	var tex: Texture2D = load("res://assets/props/fire.png")
	sf.set_animation_speed("default", 9.0)
	for i in 4:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 26, 0, 26, 10)
		sf.add_frame("default", at)
	fire.sprite_frames = sf
	fire.pixel_size = PX
	fire.centered = false
	fire.offset = Vector2(-13, 0)
	fire.position = Vector3(0, 0.03, 0.03)
	fire.shaded = false
	fire.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	fire.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fire.modulate = Color(1.6, 1.4, 1.2)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire)
	fire.play("default")

	liquid = _sprite("res://assets/props/cauldron_liquid.png", PX, Vector3(0, 0.18, -0.03))
	liquid.offset = Vector2(-20, 0)
	liquid.shaded = false
	liquid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body = _sprite("res://assets/props/cauldron_iron.png", PX, Vector3(0, 0.18, 0.0))
	body.offset = Vector2(-20, 0)
	var hearth := _sprite("res://assets/props/hearth.png", PX, Vector3(0, 0.0, 0.32))
	hearth.offset = Vector2(-21, 0)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 2.2
	light.omni_range = 6.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 0.6
	light.position = Vector3(0.0, 0.55, 0.65)
	add_child(light)

	bubbles = _particles(12, 1.0, "res://assets/fx/bubble.png", 0.028)
	bubbles.position = Vector3(0, 1.08, -0.02)
	_bubble_mat = bubbles.process_material
	_bubble_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_bubble_mat.emission_box_extents = Vector3(0.5, 0.02, 0.02)
	_bubble_mat.direction = Vector3(0, 1, 0)
	_bubble_mat.spread = 12.0
	_bubble_mat.initial_velocity_min = 0.15
	_bubble_mat.initial_velocity_max = 0.35
	_bubble_mat.gravity = Vector3(0, 0, 0)
	_bubble_mat.scale_min = 0.6
	_bubble_mat.scale_max = 1.3
	_bubble_mat.color = liquid_color.lightened(0.4)
	_bubble_mat.color_ramp = _fade_ramp()

	steam = _particles(7, 4.0, "res://assets/fx/smoke.png", 0.05)
	steam.position = Vector3(0, 1.15, -0.05)
	var sm: ParticleProcessMaterial = steam.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(0.4, 0.02, 0.05)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 25.0
	sm.initial_velocity_min = 0.2
	sm.initial_velocity_max = 0.35
	sm.gravity = Vector3(0.05, 0.02, 0)
	sm.scale_min = 0.8
	sm.scale_max = 1.8
	sm.color = Color(0.9, 0.9, 1.0, 0.035)
	sm.color_ramp = _fade_ramp()

	embers = _particles(10, 1.6, "res://assets/fx/ember.png", 0.035)
	embers.position = Vector3(0, 0.15, 0.1)
	var em: ParticleProcessMaterial = embers.process_material
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	em.emission_box_extents = Vector3(0.35, 0.02, 0.05)
	em.direction = Vector3(0, 1, 0)
	em.spread = 25.0
	em.initial_velocity_min = 0.3
	em.initial_velocity_max = 0.7
	em.gravity = Vector3(0, 0.1, 0)
	em.color = Color(2.0, 1.2, 0.6)
	em.color_ramp = _fade_ramp()
	set_liquid(liquid_color, false)

func _sprite(path: String, px: float, pos: Vector3) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load(path)
	s.pixel_size = px
	s.centered = false
	s.position = pos
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(s)
	return s

func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 1, 1, 1))
	g.add_point(0.7, Color(1, 1, 1, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _particles(amount: int, life: float, tex: String, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var pm := ParticleProcessMaterial.new()
	p.process_material = pm
	var q := QuadMesh.new()
	var t: Texture2D = load(tex)
	q.size = Vector2(t.get_width(), t.get_height()) * size
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	add_child(p)
	return p

func set_copper(on: bool) -> void:
	copper = on
	body.texture = load("res://assets/props/cauldron_copper.png" if on else "res://assets/props/cauldron_iron.png")

func set_liquid(c: Color, animate := true) -> void:
	liquid_color = c
	var target := Color(c.r * 1.25, c.g * 1.25, c.b * 1.25, 1.0)
	if animate:
		var tw := create_tween()
		tw.tween_property(liquid, "modulate", target, 0.6)
	else:
		liquid.modulate = target
	_bubble_mat.color = c.lightened(0.35)

func set_activity(a: float) -> void:
	activity = clampf(a, 0.0, 1.0)
	bubbles.amount_ratio = 0.25 + activity * 0.75
	_bubble_mat.initial_velocity_max = 0.3 + activity * 0.4

func splash(c: Color) -> void:
	var p := _particles(14, 0.8, "res://assets/fx/bubble.png", 0.035)
	p.position = Vector3(0, 1.1, 0.0)
	p.one_shot = true
	p.explosiveness = 0.95
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -4.0, 0)
	pm.color = c.lightened(0.3)
	pm.color_ramp = _fade_ramp()
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

func brew_burst(c: Color) -> void:
	var p := _particles(26, 1.6, "res://assets/fx/smoke.png", 0.06)
	p.position = Vector3(0, 1.15, 0.05)
	p.one_shot = true
	p.explosiveness = 0.9
	var pm: ParticleProcessMaterial = p.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.3, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.4
	pm.scale_min = 1.0
	pm.scale_max = 2.2
	pm.color = Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.9)
	pm.color_ramp = _fade_ramp()
	p.emitting = true
	var s := _particles(20, 1.2, "res://assets/fx/sparkle.png", 0.04)
	s.position = Vector3(0, 1.2, 0.1)
	s.one_shot = true
	s.explosiveness = 0.8
	var sm: ParticleProcessMaterial = s.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.4
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 70.0
	sm.initial_velocity_min = 0.5
	sm.initial_velocity_max = 1.4
	sm.gravity = Vector3(0, -0.5, 0)
	sm.color = Color(2.0, 2.0, 1.6)
	sm.color_ramp = _fade_ramp()
	s.emitting = true
	_flash = 4.0
	get_tree().create_timer(2.5).timeout.connect(func():
		p.queue_free()
		s.queue_free())

func _process(delta: float) -> void:
	_t += delta
	var n := sin(_t * 9.0) * 0.12 + sin(_t * 23.0 + 1.7) * 0.08 + sin(_t * 3.1) * 0.1
	_flash = move_toward(_flash, 0.0, delta * 5.0)
	light.light_energy = base_energy + n + _flash
	_bubble_timer -= delta * (0.4 + activity * 1.6)
	if _bubble_timer <= 0.0:
		_bubble_timer = randf_range(0.6, 1.6)
		if is_visible_in_tree():
			Sfx.bubble()
