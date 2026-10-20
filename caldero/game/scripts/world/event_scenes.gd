extends Node3D
class_name EventScenes
## --- R4 SCENES: los escenarios de los eventos (ronda 4). Un evento aceptado reemplaza el día: ella viaja y juega en un
## escenario nuevo, más bonito que la tienda, con el mismo aspecto HD-2D (texturas pixel art, luz cálida, desenfoque,
## el post-proceso de main.gd y detalles animados). Se construyen en código, como la tienda y el mercado:
##   1. "academia": el gran salón de la Academia de Magia de Valmora (vidrieras altas con rayos de luz, estandartes de
##      las casas, mesas largas de roble con alumnos, velas flotantes, estanterías hasta el techo, el atril de la
##      profesora y su puesto de pociones delante).
##   2. "concurso": el escenario de la fiesta en la plaza de Robledal al atardecer (banderines y farolillos de papel, la
##      mesa del jurado en una tarima con tres sillas, el público, los puestos rivales con el de Fizz y su letrero, y el
##      puesto de ella en el escenario).
##   3. "torneo": el campo del torneo de caballeros por la mañana (tiendas a rayas con gallardetes, la valla de las
##      justas, una grada de madera con público, estandartes, caballos y su puesto con una fila para caballeros y
##      escuderos).
##
## Contrato con EVENTS-LOGIC (ver BRIEF4 y NOTES.txt del lane):
##   var sc := EventScenes.build("academia")     # o "concurso" / "torneo"
##   add_child(sc); sc.get_node("Camera").make_current()
## Hijos Marker3D: "Player" (donde se para ella), "Bench" (donde trabaja: el caldero), "Queue0".."Queue5" (la fila:
## Queue0 es quien está siendo atendido, junto a su puesto; los demás esperan detrás), "Judge0".."Judge2" (solo en el
## concurso: las tres sillas del jurado) y "Camera" (un Camera3D). Cada marcador lleva meta "face": 1 = mira a la
## derecha, -1 = a la izquierda (Actor.face). set_crowd(ids) pone a los personajes del elenco como público, alumnos o
## caballeros (Actor por id) y devuelve la lista de Actor.
## Extras (opcionales): cauldron (el Cauldron de su puesto: set_liquid, brew_burst...), cheer(good) (el público se alegra
## o se lamenta), fixed (los que el escenario pone solo: la profesora Roxa en la Academia, Fizz en su puesto),
## cam_drift (el leve vaivén de la cámara) y set_view(pos, mirar) para mover la cámara.

const KINDS := ["academia", "concurso", "torneo"]
const ART := "res://assets/event/"
const QUEUE_SIZE := 6

var kind := ""
var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var fill: OmniLight3D
var cauldron: Cauldron
var fixed := {}                 # id -> Actor que pone el escenario (no los toca set_crowd)
var crowd: Array = []           # los Actor de set_crowd
var extras: Array = []          # figurantes que el escenario pone en los sitios que quedan libres (los alumnos)
var _extra_ids: Array = []      # sus sprites (assets/chars), si el escenario los usa
var cam_drift := true
var _spots: Array = []          # sitios del público, en orden: {"p": Vector3, "face": int}
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _t := 0.0
var _mats := {}
var _font: Font
var _font_sc: Font
var _flybooks: Array = []       # [AnimatedSprite3D, centro, radio, fase]
var _owl: AnimatedSprite3D
var _owl_t := 3.0
var _owl_hold := 0.0
var _chatter_t := 2.0
var _crowd_emotes: Array = ["note", "dots", "sparkle"]
var _pending_cheers: Array = []   # [{t, a: Actor, good}]

# ------------------------------------------------------------------ construcción

## Construye el escenario de un evento ("academia", "concurso" o "torneo"). No hace falta que esté en el árbol.
static func build(k: String) -> Node3D:
	var s := EventScenes.new()
	s._build(k)
	return s

func _build(k: String) -> void:
	kind = k if KINDS.has(k) else "academia"
	if not KINDS.has(k):
		push_warning("EventScenes: escenario desconocido '%s', uso la academia" % k)
	name = "Event_" + kind
	_font = load("res://assets/fonts/Alegreya-Bold.ttf")
	_font_sc = load("res://assets/fonts/AlegreyaSC-Bold.ttf")
	match kind:
		"academia":
			_academia()
		"concurso":
			_concurso()
		"torneo":
			_torneo()

## Pone a los personajes del elenco (ids de Data.CHARACTERS / assets/chars) en los sitios del público, en orden.
## Quita a los que había. Se salta los repetidos y a los que el escenario ya puso (fixed). Devuelve los Actor.
func set_crowd(ids: Array) -> Array:
	for a in crowd + extras:
		if is_instance_valid(a):
			a.queue_free()
	crowd.clear()
	extras.clear()
	var used := {}
	for id in fixed:
		used[id] = true
	var i := 0
	for raw in ids:
		if i >= _spots.size():
			break
		var id := String(raw)
		if id == "" or used.has(id):
			continue
		used[id] = true
		var sid := id if ResourceLoader.exists("res://assets/chars/%s_idle.png" % id) else Story.sprite_id(id)
		var sp: Dictionary = _spots[i]
		i += 1
		var a := Actor.new()
		a.name = "Crowd_" + id
		add_child(a)
		a.setup(sid)
		a.quiet = true
		a.position = sp["p"]
		var top: float = sp.get("top", -1.0)
		if top > 0.0:
			# sentado tras una mesa o en una grada: sube o baja hasta que la cabeza queda a esa altura (la mesa o la
			# baranda le tapan las piernas); así los niños y los enanos se ven igual que los altos
			a.position.y = top - a.top_height()
		a.face(int(sp["face"]))
		a.set_meta("id", id)
		crowd.append(a)
	_fill_extras(i)
	return crowd

## Los sitios que quedan libres (desde `from`) y están marcados para figurantes se llenan con ellos (en la Academia,
## alumnos con la túnica de su casa): el salón se ve lleno aunque la lista del público sea corta.
func _fill_extras(from: int) -> void:
	if _extra_ids.is_empty():
		return
	var k := 0
	for j in range(from, _spots.size()):
		var sp: Dictionary = _spots[j]
		if not sp.get("extra", false):
			continue
		var id: String = _extra_ids[k % _extra_ids.size()]
		k += 1
		if not ResourceLoader.exists("res://assets/chars/%s_idle.png" % id):
			continue
		var a := Actor.new()
		a.name = "Extra_%d" % k
		add_child(a)
		a.setup(id)
		a.quiet = true
		a.position = sp["p"]
		var top: float = sp.get("top", -1.0)
		if top > 0.0:
			a.position.y = top - a.top_height()
		a.face(int(sp["face"]))
		extras.append(a)

## Cuántos sitios para el público tiene este escenario.
func crowd_capacity() -> int:
	return _spots.size()

## El público reacciona: good = se alegra (saltitos, corazones, estrellas y confeti), si no, se lamenta.
func cheer(good := true) -> void:
	if good:
		_confetti()
	var all: Array = crowd + extras
	for id in fixed:
		all.append(fixed[id])
	# cada uno reacciona con un pequeño retraso (lo lleva _process: nada queda pendiente si el escenario se borra)
	for a in all:
		if is_instance_valid(a):
			_pending_cheers.append({"t": randf_range(0.0, 0.5), "a": a, "good": good})

## Una lluvia de confeti sobre su puesto y la fila (se borra sola).
func _confetti() -> void:
	var pm_node: Node3D = get_node_or_null("Player")
	var c := pm_node.position if pm_node else Vector3.ZERO
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 3.2
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.2, 0.2, 0.8)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.6
	pm.initial_velocity_max = 4.2
	pm.gravity = Vector3(0, -2.4, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	var cols := Gradient.new()
	cols.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	cols.set_color(0, Color(1.0, 0.35, 0.4))
	cols.set_color(1, Color(0.5, 0.8, 1.0))
	cols.add_point(0.2, Color(1.0, 0.85, 0.3))
	cols.add_point(0.4, Color(0.5, 1.0, 0.55))
	cols.add_point(0.6, Color(0.85, 0.55, 1.0))
	cols.add_point(0.8, Color(1.0, 0.6, 0.25))
	var ct := GradientTexture1D.new()
	ct.gradient = cols
	pm.color_initial_ramp = ct
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _particle_quad(_art("fx_confetti"), 0.035)
	p.position = c + Vector3(2.0, 2.6, 0.2)
	p.visibility_aabb = AABB(Vector3(-6, -4, -3), Vector3(12, 10, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	if is_inside_tree():   # fuera del árbol se queda (de una vez) y se va con el escenario
		get_tree().create_timer(4.0).timeout.connect(p.queue_free)

## Mueve la cámara a otra vista (sigue con su leve vaivén si cam_drift).
func set_view(pos: Vector3, look: Vector3) -> void:
	_cam_pos = pos
	_cam_look = look
	_apply_cam(0.0)

# ------------------------------------------------------------------ ayudas (como en shop_world.gd)

func _tex(path: String) -> Texture2D:
	return load(path)

func _art(n: String) -> Texture2D:
	return load(ART + n + ".png")

func _mat(albedo: String, normal := "", scale := 0.5, rough := 0.92, tint := Color.WHITE) -> StandardMaterial3D:
	var key := albedo + normal + str(scale) + str(rough) + str(tint)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(albedo)
	m.albedo_color = tint
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 20.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = rough
	_mats[key] = m
	return m

func _flat(col: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := "flat:" + str(col) + str(rough) + str(metal)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m

func _box_b(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: Material, parent: Node3D = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x1 - x0, y1 - y0, z1 - z0)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi

func _sprite(tex: Texture2D, px: float, pos: Vector3, parent: Node3D = null, anchor := "bottom", shaded := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.centered = false
	if anchor == "bottom":
		s.offset = Vector2(-tex.get_width() / 2.0, 0)
	elif anchor == "top":
		s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	else:
		s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() / 2.0)
	s.position = pos
	s.shaded = shaded
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	(parent if parent else self).add_child(s)
	return s

func _prop(name_: String, px: float, pos: Vector3, parent: Node3D = null, anchor := "bottom") -> Sprite3D:
	return _sprite(_tex("res://assets/props/%s.png" % name_), px, pos, parent, anchor)

func _ev(name_: String, px: float, pos: Vector3, parent: Node3D = null, anchor := "bottom") -> Sprite3D:
	return _sprite(_art(name_), px, pos, parent, anchor)

## Sprite animado a partir de una tira horizontal de `n` cuadros.
func _anim(tex: Texture2D, n: int, fps: float, px: float, pos: Vector3, parent: Node3D = null, anchor := "bottom", loop := true) -> AnimatedSprite3D:
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", fps)
	sf.set_animation_loop("default", loop)
	var fw := tex.get_width() / n
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, tex.get_height())
		sf.add_frame("default", at)
	var s := AnimatedSprite3D.new()
	s.sprite_frames = sf
	s.pixel_size = px
	s.centered = false
	if anchor == "bottom":
		s.offset = Vector2(-fw / 2.0, 0)
	elif anchor == "top":
		s.offset = Vector2(-fw / 2.0, -tex.get_height())
	else:
		s.offset = Vector2(-fw / 2.0, -tex.get_height() / 2.0)
	s.position = pos
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	(parent if parent else self).add_child(s)
	s.play("default")
	s.frame = randi() % n
	return s

func _quad(size: Vector2, center: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.position = center
	(parent if parent else self).add_child(mi)
	return mi

## Un panel con textura (cuadro plano) que mira hacia `facing` (+x, -x o +z); uv_scale repite la textura.
func _panel(tex: Texture2D, size: Vector2, center: Vector3, facing: Vector3, uv_scale: Vector2, normal_tex: Texture2D = null, tint := Color.WHITE) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	if normal_tex:
		m.normal_enabled = true
		m.normal_texture = normal_tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.8
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	var q := _quad(size, center, m)
	if facing.x > 0.5:
		q.rotation_degrees = Vector3(0, 90, 0)
	elif facing.x < -0.5:
		q.rotation_degrees = Vector3(0, -90, 0)
	return q

func _omni(pos: Vector3, color: Color, energy: float, rng: float, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 0.3
	add_child(l)
	return l

func _particle_quad(tex: Texture2D, size: float, additive := false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(tex.get_width(), tex.get_height()) * size
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	return q

func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.75, Color(1, 1, 1, 0.85))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _marker(n: String, p: Vector3, face := 1) -> Marker3D:
	var m := Marker3D.new()
	m.name = n
	m.position = p
	m.set_meta("face", face)
	add_child(m)
	return m

## La fila: Queue0 junto a su puesto (el que está siendo atendido) y los demás detrás, cada uno un poco más lejos.
func _queue(first: Vector3, step: Vector3, face: int) -> void:
	for i in QUEUE_SIZE:
		_marker("Queue%d" % i, first + step * i, face)

## Un sitio para el público. top > 0: está sentado (o tras una baranda) y su cabeza queda a esa altura. extra: si
## queda libre, lo ocupa un figurante.
func _spot(p: Vector3, face: int, top := -1.0, extra := false) -> void:
	_spots.append({"p": p, "face": face, "top": top, "extra": extra})

## Un personaje que pone el propio escenario (la profesora, Fizz...): set_crowd no lo repite.
func _fixed_actor(id: String, p: Vector3, face: int) -> Actor:
	var a := Actor.new()
	a.name = "Fixed_" + id
	add_child(a)
	a.setup(Story.sprite_id(id))
	a.quiet = true
	a.position = p
	a.face(face)
	fixed[id] = a
	return a

func _label(text: String, pos: Vector3, size := 40, px := 0.006, col := Color(1.0, 0.92, 0.72), sc := true, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.font = _font_sc if sc else _font
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 8
	l.outline_modulate = Color(0.12, 0.07, 0.06)
	l.modulate = col
	l.position = pos
	l.shaded = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	(parent if parent else self).add_child(l)
	return l

# ------------------------------------------------------------------ cámara, entorno y luz

func _camera(pos: Vector3, look: Vector3, fov := 35.0, dof_far := 17.0, dof_near := 7.0) -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	_cam_pos = pos
	_cam_look = look
	_apply_cam(0.0)
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = dof_far
	ca.dof_blur_far_transition = 6.0
	ca.dof_blur_near_enabled = true
	ca.dof_blur_near_distance = dof_near
	ca.dof_blur_near_transition = 2.0
	ca.dof_blur_amount = 0.08
	camera.attributes = ca

func _apply_cam(t: float) -> void:
	if camera == null:
		return
	var p := _cam_pos
	if cam_drift:
		p += Vector3(sin(t * 0.11) * 0.08, sin(t * 0.17) * 0.04, 0.0)
	camera.transform = Transform3D(Basis.looking_at(_cam_look - p, Vector3.UP), p)

## El entorno va en la cámara (como el mercado): la tienda conserva su WorldEnvironment.
func _environment(bg: Color, amb: Color, amb_e: float, glow := 0.4, sat := 1.12) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = glow
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.4
	env.ssao_power = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = sat
	env.adjustment_contrast = 1.06
	camera.environment = env

func _sun(dir: Vector3, col: Color, energy: float, max_dist := 34.0) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), Vector3.ZERO)
	sun.light_color = col
	sun.light_energy = energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = max_dist
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_angular_distance = 0.5
	sun.shadow_blur = 1.0
	sun.light_volumetric_fog_energy = 0.0
	add_child(sun)

func _fill(pos: Vector3, col: Color, energy: float, rng := 16.0) -> void:
	fill = OmniLight3D.new()
	fill.name = "Fill"
	fill.position = pos
	fill.omni_range = rng
	fill.omni_attenuation = 0.7
	fill.light_color = col
	fill.light_energy = energy
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)

# ------------------------------------------------------------------ piezas que se repiten

## Tela que ondea (estandarte, gallardete, bandera): QuadMesh subdividido con ev_cloth.gdshader.
func _cloth(tex: Texture2D, px: float, center: Vector3, params := {}, parent: Node3D = null) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(tex.get_width(), tex.get_height()) * px
	q.subdivide_width = 6
	q.subdivide_depth = 10
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ev_cloth.gdshader")
	m.set_shader_parameter("tex", tex)
	for k in params:
		m.set_shader_parameter(k, params[k])
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = center
	(parent if parent else self).add_child(mi)
	return mi

## Muchos objetos que flotan o cuelgan (velas, farolillos) en un MultiMesh con ev_floater.gdshader, y su halo
## aditivo (otro MultiMesh, mismas posiciones). Dos llamadas de dibujo para todos.
func _floaters(tex: Texture2D, frames: int, rows: int, px: float, positions: Array, params := {}, halo_col := Color(1.0, 0.7, 0.35), halo_size := 0.9, halo_int := 0.35) -> void:
	var fw := tex.get_width() / frames
	var fh := tex.get_height() / rows
	var q := QuadMesh.new()
	q.size = Vector2(fw, fh) * px
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ev_floater.gdshader")
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("frames", float(frames))
	m.set_shader_parameter("variants", float(rows))
	m.set_shader_parameter("pivot_y", fh * px * 0.5)
	for k in params:
		m.set_shader_parameter(k, params[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Floaters"
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	if halo_int <= 0.0:
		return
	var hq := QuadMesh.new()
	hq.size = Vector2(halo_size, halo_size)
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.mesh = hq
	hm.instance_count = positions.size()
	var flame_off := Vector3(0, fh * px * 0.32, 0.02)
	for i in positions.size():
		hm.set_instance_transform(i, Transform3D(Basis(), positions[i] + flame_off))
	var h := ShaderMaterial.new()
	h.shader = load("res://shaders/ev_halo.gdshader")
	h.set_shader_parameter("tex", _tex("res://assets/fx/glow.png"))
	h.set_shader_parameter("color", halo_col)
	h.set_shader_parameter("intensity", halo_int)
	h.set_shader_parameter("bob", params.get("bob", 0.07))
	h.set_shader_parameter("bob_speed", params.get("bob_speed", 0.8))
	var hmi := MultiMeshInstance3D.new()
	hmi.name = "Halos"
	hmi.multimesh = hm
	hmi.material_override = h
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hmi)

## Polvo dorado que flota en la luz.
func _dust(center: Vector3, ext: Vector3, amount := 40, col := Color(1.0, 0.95, 0.8)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3(0.2, 0.3, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, 0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.color = col
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _particle_quad(_tex("res://assets/fx/dust.png"), 0.024, true)
	p.position = center
	p.visibility_aabb = AABB(-ext - Vector3.ONE, (ext + Vector3.ONE) * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## Un cuadrilátero de 4 puntos (p0 arriba-izq, p1 arriba-der, p2 abajo-der, p3 abajo-izq) con UV de 0 a 1.
func _quad4(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var pts := [p0, p1, p2, p0, p2, p3]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in 6:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

## Rayos de luz de una ventana (x0..x1, y0..y1, en la pared z): tres láminas paralelas que bajan en la dirección del
## sol hasta el suelo, aditivas (donde se cruzan se ve más espeso).
func _shafts(x0: float, x1: float, y0: float, y1: float, z: float, dir: Vector3, col: Color, inten: float, slices := 3) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in slices:
		var y := lerpf(y0 + 0.5, y1 - 0.8, float(k) / maxf(1.0, slices - 1.0))
		var t := y / -dir.y
		var a0 := Vector3(x0 + 0.15, y, z)
		var a1 := Vector3(x1 - 0.15, y, z)
		_quad4(st, a0, a1, a1 + dir * t, a0 + dir * t)
	var mi := MeshInstance3D.new()
	mi.name = "Shafts"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ev_shaft.gdshader")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", inten)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## La luz de una vidriera en el suelo: la imagen del vidrio proyectada en la dirección de la luz, SUMADA sobre el suelo
## (luz de colores; el plomo, en negro, no suma). Igual en Forward+ y en Compatibility (WebGL 2): en Compatibility cada
## objeto se escribe ya con el tonemap, así que multiplicar oscurece de más; sumar se ve igual en los dos.
func _glass_pool(tex: Texture2D, x0: float, x1: float, y0: float, y1: float, z: float, dir: Vector3, inten := 0.6, floor_y := 0.012) -> MeshInstance3D:
	var corners := [Vector3(x0, y1, z), Vector3(x1, y1, z), Vector3(x1, y0, z), Vector3(x0, y0, z)]
	var pts := []
	for c in corners:
		var t: float = (c.y - floor_y) / -dir.y
		pts.append(c + dir * t)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad4(st, pts[0], pts[1], pts[2], pts[3])
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(inten, inten, inten, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mi := MeshInstance3D.new()
	mi.name = "GlassPool"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Una mesa larga de roble (frente de paneles, tablero claro, patas) de x0 a x1; su frente mira a la cámara en z1.
func _long_desk(x0: float, x1: float, z0: float, z1: float, top: float, y_base := 0.0) -> void:
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.55, Color(0.9, 0.8, 0.7))
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(x0 - 0.04, x1 + 0.04, y_base + top - 0.07, y_base + top, z0 - 0.04, z1 + 0.05, wood_l)
	_box_b(x0, x1, y_base + 0.06, y_base + top - 0.07, z0 + 0.1, z1, wood_d)
	_panel(_tex("res://assets/tex/counter_front.png"), Vector2(x1 - x0 - 0.06, top - 0.2), Vector3((x0 + x1) / 2.0, y_base + 0.07 + (top - 0.2) / 2.0, z1 + 0.004),
		Vector3.BACK, Vector2((x1 - x0) / 2.0, 1.0), _tex("res://assets/tex/counter_front_n.png"), Color(0.95, 0.85, 0.78))
	_box_b(x0 - 0.02, x1 + 0.02, y_base, y_base + 0.07, z0 + 0.08, z1 + 0.02, wood_d)

# ------------------------------------------------------------------ 1. LA ACADEMIA DE MAGIA DE ARVENDAL

const ACA_WALL_Z := -9.0
const ACA_WINDOWS := [-5.5, 0.0, 5.5]
const ACA_WIN_Y0 := 1.7
const ACA_WIN_PX := 0.05
const ACA_GLASS_DIR := Vector3(0.3, -0.72, 0.62)   # la luz de las vidrieras (rayos y manchas de colores, falsos)
const ACA_KEY := Vector3(0.5, -0.72, -0.48)          # la luz principal: de delante a la izquierda (ventanales del lado)
const ACA_PLAYER := Vector3(-3.2, 0, -2.0)
const ACA_LECTERN := Vector3(-5.9, 0, -5.4)

func _academia() -> void:
	_camera(Vector3(-0.8, 4.6, 8.8), Vector3(-0.8, 1.35, -3.2), 35.0, 17.0, 6.5)
	_environment(Color(0.06, 0.05, 0.08), Color(0.6, 0.55, 0.62), 0.5, 0.42)
	_sun(ACA_KEY, Color(1.0, 0.86, 0.68), 0.75, 30.0)
	_fill(Vector3(-0.8, 4.2, 4.0), Color(1.0, 0.86, 0.72), 0.45, 17.0)
	_aca_room()
	_aca_windows()
	_aca_station()
	_aca_lectern()
	_aca_desks()
	_aca_candles()
	_aca_details()
	# la fila: los alumnos esperan su poción por la alfombra, de su mesa hacia la derecha
	_marker("Player", ACA_PLAYER, 1)
	_marker("Bench", Vector3(-4.3, 0, -2.55), 1)
	_queue(Vector3(-1.3, 0, -1.95), Vector3(0.85, 0, -0.08), -1)
	_crowd_emotes = ["note", "dots", "question", "sparkle"]
	# los alumnos de las casas llenan los pupitres que el público no ocupe
	_extra_ids = ["alumna_azul", "alumno_rojo", "alumna_verde", "alumno_violeta", "alumna_roja", "alumno_azul"]
	_fill_extras(0)

func _aca_room() -> void:
	var floor_m := _mat(ART + "aca_floor.png", ART + "aca_floor_n.png", 0.5, 0.4, Color(0.84, 0.8, 0.78))
	var wall := _mat(ART + "aca_wall.png", ART + "aca_wall_n.png", 0.36, 0.92)
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var z := ACA_WALL_Z
	# suelo de mármol y alfombra del pasillo (bajo la fila)
	_box_b(-18.0, 18.0, -0.2, 0.0, -10.0, 7.0, floor_m)
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = _art("aca_carpet")
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	cm.roughness = 1.0
	var carpet := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.5, 22.0)
	carpet.mesh = pm
	cm.uv1_scale = Vector3(1.0, 11.0, 1.0)
	carpet.material_override = cm
	carpet.position = Vector3(7.2, 0.012, -2.15)
	carpet.rotation_degrees = Vector3(0, 90, 0)
	add_child(carpet)
	# pared del fondo con los huecos de las vidrieras (el marco de piedra tapa las esquinas del arco)
	var fw := 48.0 * ACA_WIN_PX
	var fh := 113.0 * ACA_WIN_PX
	var H := 11.0
	var xs: Array = ACA_WINDOWS
	var x := -18.0
	for wx in xs:
		_box_b(x, wx - fw / 2.0, 0.0, H, z - 0.4, z, wall)
		_box_b(wx - fw / 2.0, wx + fw / 2.0, 0.0, ACA_WIN_Y0, z - 0.4, z, wall)
		_box_b(wx - fw / 2.0, wx + fw / 2.0, ACA_WIN_Y0 + fh, H, z - 0.4, z, wall)
		x = wx + fw / 2.0
	_box_b(x, 18.0, 0.0, H, z - 0.4, z, wall)
	# techo y paredes de los lados (no se ven: tapan el sol que no entra por las vidrieras)
	_box_b(-18.5, 18.5, H - 0.6, H, z - 0.5, 7.0, _flat(Color(0.12, 0.1, 0.1)))
	_box_b(-18.5, -18.0, 0.0, H, z - 0.5, 7.0, wall)
	_box_b(18.0, 18.5, 0.0, H, z - 0.5, 7.0, wall)
	# zócalo de paneles de roble y la moldura de arriba
	var panels := _tex("res://assets/tex/counter_front.png")
	_panel(panels, Vector2(36.0, 1.25), Vector3(0.0, 0.66, z + 0.006), Vector3.BACK, Vector2(18.0, 1.0), _tex("res://assets/tex/counter_front_n.png"), Color(0.86, 0.74, 0.66))
	_box_b(-18.0, 18.0, 1.28, 1.38, z, z + 0.08, wood_d)
	_box_b(-18.0, 18.0, 0.0, 0.07, z, z + 0.05, wood_d)
	# pilastras entre las vidrieras (con basa y capitel) y la cornisa
	var stone := _mat(ART + "aca_wall.png", ART + "aca_wall_n.png", 0.36, 0.9, Color(1.06, 1.02, 0.96))
	for px in [-8.25, -2.75, 2.75, 8.25]:
		_box_b(px - 0.36, px + 0.36, 0.0, H, z, z + 0.3, stone)
		_box_b(px - 0.46, px + 0.46, 0.0, 0.5, z, z + 0.4, stone)
		_box_b(px - 0.48, px + 0.48, 7.55, 7.85, z, z + 0.42, stone)
	_box_b(-18.0, 18.0, 7.85, 8.15, z, z + 0.32, stone)
	# estanterías hasta el techo, a los dos lados, con su escalera
	for b in [[-11.7, "aca_bookcase_a"], [11.7, "aca_bookcase_b"]]:
		var bx: float = b[0]
		_box_b(bx - 1.36, bx + 1.36, 0.0, 7.3, z, z + 0.42, wood_d)
		_ev(b[1], 0.034, Vector3(bx, 0, z + 0.43))
	var lad := _ev("aca_ladder", 0.034, Vector3(10.85, 0, z + 0.75))
	lad.rotation_degrees = Vector3(-8.0, 0, -4.0)

func _aca_windows() -> void:
	var z := ACA_WALL_Z
	var keys := ["a", "b", "c"]
	var shaft_cols := [Color(0.85, 0.92, 1.0), Color(1.0, 0.86, 0.6), Color(0.86, 1.0, 0.88)]
	var gw := 40.0 * ACA_WIN_PX
	var gh := 104.0 * ACA_WIN_PX
	for i in ACA_WINDOWS.size():
		var wx: float = ACA_WINDOWS[i]
		var gtex := _art("aca_glass_" + keys[i])
		# el vidrio: brilla (sin sombra, deja pasar el sol); el marco de piedra delante, con su sombra
		var g := _sprite(gtex, ACA_WIN_PX, Vector3(wx, ACA_WIN_Y0 + 0.25, z - 0.2), null, "bottom", false)
		g.modulate = Color(1.25, 1.2, 1.15)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ev("aca_window_frame", ACA_WIN_PX, Vector3(wx, ACA_WIN_Y0, z + 0.01))
		# la luz de colores en el suelo y los rayos
		var gy0 := ACA_WIN_Y0 + 0.25
		_glass_pool(_art("aca_pool_" + keys[i]), wx - gw / 2.0, wx + gw / 2.0, gy0, gy0 + gh, z - 0.2, ACA_GLASS_DIR.normalized(), 0.7)
		_shafts(wx - gw / 2.0, wx + gw / 2.0, gy0, gy0 + gh, z - 0.1, ACA_GLASS_DIR.normalized(), shaft_cols[i], 0.2)
	_dust(Vector3(1.5, 3.2, -6.0), Vector3(8.0, 2.6, 2.4), 60)

## Su puesto: el caldero, una mesa de trabajo (como el mostrador de la tienda: ella a un lado, el alumno al otro) con el
## paño de la Academia, frascos, el reloj de arena del examen y la gradilla con las pociones iguales.
func _aca_station() -> void:
	cauldron = Cauldron.new()
	cauldron.name = "Cauldron"
	cauldron.position = Vector3(-4.3, 0, -2.55)
	add_child(cauldron)
	cauldron.build()
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.55, Color(0.9, 0.82, 0.74))
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var tx0 := -2.72
	var tx1 := -2.08
	var tz0 := -3.15
	var tz1 := -1.3
	var top := 0.9
	_box_b(tx0 - 0.04, tx1 + 0.04, top - 0.07, top, tz0 - 0.04, tz1 + 0.04, wood_l)
	_box_b(tx0 + 0.04, tx1 - 0.04, 0.0, top - 0.07, tz0 + 0.04, tz1 - 0.04, wood_d)
	var cloth := _ev("aca_tablecloth", 0.032, Vector3(tx1 + 0.05, top - 0.02, (tz0 + tz1) / 2.0), null, "top")
	cloth.rotation_degrees = Vector3(0, 90, 0)
	_ev("aca_cloth_end", 0.031, Vector3((tx0 + tx1) / 2.0, top - 0.02, tz1 + 0.05), null, "top")
	# encima: la gradilla del examen, el reloj de arena, un frasco de ingrediente y el recetario
	_ev("aca_vials", 0.022, Vector3(-2.4, top, -2.85))
	_anim(_art("aca_hourglass"), 2, 3.0, 0.03, Vector3(-2.36, top, -2.2))
	_prop("jar_polvo_estrella", 0.022, Vector3(-2.45, top, -1.72))
	_prop("open_book", 0.022, Vector3(-2.4, top, -1.45))
	# más ingredientes junto al caldero
	_prop("jar_escarcha_luna", 0.026, Vector3(-5.3, 0, -3.1))
	_prop("crate", 0.035, Vector3(-5.5, 0, -2.5))
	_prop("jar_hongo_violeta", 0.024, Vector3(-5.55, 0.45, -2.52))
	_prop("sack", 0.035, Vector3(-3.5, 0, -3.3))

## El atril de la profesora (Roxa), la lechuza en su percha, la esfera armilar y los libros que vuelan sobre el atril.
func _aca_lectern() -> void:
	var lx := ACA_LECTERN.x
	var lz := ACA_LECTERN.z
	# tarima del atril
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(lx - 1.5, lx + 1.1, 0.0, 0.22, lz - 1.3, lz + 0.55, wood_d)
	_ev("aca_lectern", 0.034, Vector3(lx + 0.15, 0.22, lz + 0.15))
	_fixed_actor("roxa", Vector3(lx - 0.5, 0.22, lz - 0.25), 1)
	var perch := _ev("aca_perch", 0.034, Vector3(lx - 1.25, 0.22, lz - 0.85))
	_owl = _anim(_art("aca_owl"), 3, 0.0, 0.03, Vector3(lx - 1.25, 0.22 + 1.42, lz - 0.83))
	_owl.stop()
	_owl.frame = 0
	_anim(_art("aca_armillary"), 4, 3.0, 0.042, Vector3(9.3, 0.0, -4.6))
	# libros que vuelan en círculo sobre el atril
	var ft := _art("aca_flybook")
	var book_cols := [Color(1.0, 0.55, 0.5), Color(0.6, 0.75, 1.1), Color(0.65, 1.0, 0.6)]
	for i in 3:
		var b := _anim(ft, 2, 6.0, 0.036, Vector3.ZERO, null, "center")
		b.shaded = false
		b.modulate = book_cols[i]
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flybooks.append([b, Vector3(lx - 0.1, 2.75, lz - 0.2), 0.75, TAU * i / 3.0])
	# el escudo de la Academia sobre la pilastra de la izquierda (a la altura de los estandartes)
	_ev("aca_crest", 0.042, Vector3(-8.25, 4.4, ACA_WALL_Z + 0.32))
	_omni(Vector3(lx + 0.5, 1.9, lz + 1.1), Color(1.0, 0.78, 0.52), 1.5, 4.2)
	_candle_on(Vector3(lx - 0.15, 0.22 + 1.2, lz + 0.18))

## Una vela con su llama animada (sobre el atril, las mesas...).
func _candle_on(pos: Vector3) -> void:
	var c := _prop("candlestick", 0.022, pos)
	var fl := _anim(_tex("res://assets/props/flame.png"), 3, 8.0, 0.022, Vector3(0, 14 * 0.022, 0.01), c)
	fl.shaded = false
	fl.modulate = Color(2.0, 1.7, 1.2)
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Dos mesas largas de alumnos: una delante y otra detrás sobre una grada. Los alumnos se sientan detrás (set_crowd):
## la mesa les tapa las piernas.
const ACA_DESK1 := {"x0": 0.6, "x1": 8.8, "z0": -6.0, "z1": -5.3, "top": 0.82, "base": 0.0, "seat_z": -6.3}
const ACA_DESK2 := {"x0": -0.4, "x1": 9.8, "z0": -7.6, "z1": -6.95, "top": 0.82, "base": 0.5, "seat_z": -7.95}
const ACA_HEAD := 0.6           # los alumnos sentados: la cabeza queda a esta altura sobre el tablero

func _aca_desks() -> void:
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	# la grada de atrás
	_box_b(-1.0, 10.6, 0.0, 0.5, ACA_WALL_Z, -6.5, wood)
	_box_b(-1.0, 10.6, 0.42, 0.5, -6.5, -6.42, wood_d)
	for d in [ACA_DESK1, ACA_DESK2]:
		_long_desk(d["x0"], d["x1"], d["z0"], d["z1"], d["top"], d["base"])
	# los sitios de los alumnos: del centro hacia los lados, alternando mesa de delante y de atrás
	var seats1 := []
	var seats2 := []
	for i in 8:
		seats1.append(Vector3(1.25 + i * 1.0, ACA_DESK1["base"], ACA_DESK1["seat_z"]))
	for i in 9:
		seats2.append(Vector3(0.25 + i * 1.05, ACA_DESK2["base"], ACA_DESK2["seat_z"]))
	var head1: float = ACA_DESK1["base"] + ACA_DESK1["top"] + ACA_HEAD
	var head2: float = ACA_DESK2["base"] + ACA_DESK2["top"] + ACA_HEAD
	var order1 := [3, 5, 1, 6, 2, 7, 0, 4]
	var order2 := [4, 2, 6, 1, 7, 3, 5, 0, 8]
	for i in 9:
		if i < order1.size():
			_spot(seats1[order1[i]], -1, head1, true)
		_spot(seats2[order2[i]], -1, head2, true)
	# y unos de pie, mirando desde los lados
	_spot(Vector3(-7.3, 0, -2.7), 1)
	_spot(Vector3(8.7, 0, -3.7), -1)
	# cosas sobre las mesas: libros abiertos, tinteros, pilas de libros y velas
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 77
	for d in [ACA_DESK1, ACA_DESK2]:
		var x: float = d["x0"] + 0.45
		var y: float = d["base"] + d["top"]
		while x < d["x1"] - 0.3:
			var pick := rnd.randi() % 5
			var zz: float = d["z1"] - 0.2
			match pick:
				0, 1:
					_prop("open_book", 0.02, Vector3(x, y, zz))
				2:
					_prop("inkwell", 0.016, Vector3(x, y, zz - 0.1))
				3:
					_prop("books", 0.022, Vector3(x, y, zz - 0.15))
				4:
					_prop("bottle_sm_%d" % (rnd.randi() % 6), 0.024, Vector3(x, y, zz - 0.1))
			x += rnd.randf_range(0.45, 0.8)

## Las velas que flotan sobre el salón (un MultiMesh) y la luz cálida que dan.
func _aca_candles() -> void:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 5
	var pts := []
	while pts.size() < 34:
		var p := Vector3(rnd.randf_range(-9.5, 11.0), rnd.randf_range(3.1, 6.2), rnd.randf_range(-8.2, -1.2))
		var ok := true
		for q in pts:
			if (q as Vector3).distance_to(p) < 1.1:
				ok = false
				break
		if ok:
			pts.append(p)
	_floaters(_art("aca_fcandle"), 3, 1, 0.034, pts, {"fps": 7.0, "bob": 0.08, "bob_speed": 0.7},
		Color(1.0, 0.72, 0.38), 0.85, 0.42)
	_omni(Vector3(1.0, 4.4, -4.2), Color(1.0, 0.76, 0.46), 0.85, 8.0)
	_omni(Vector3(7.0, 4.6, -5.4), Color(1.0, 0.76, 0.46), 0.85, 8.0)

func _aca_details() -> void:
	var z := ACA_WALL_Z
	# la rosa de los vientos de mármol incrustada en el suelo, delante de la fila
	var mm := StandardMaterial3D.new()
	mm.albedo_texture = _art("aca_medallion")
	mm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mm.roughness = 0.4
	var med := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.8, 4.8)
	med.mesh = pm
	med.material_override = mm
	med.position = Vector3(0.2, 0.011, 1.0)
	med.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(med)
	# los estandartes de las casas en las pilastras
	var houses := ["azul", "rojo", "verde"]
	var pxs := [-2.75, 2.75, 8.25]
	for i in houses.size():
		var tex := _art("aca_banner_" + houses[i])
		var h: float = tex.get_height() * 0.045
		_cloth(tex, 0.045, Vector3(pxs[i], 7.45 - h / 2.0, z + 0.36), {"amp": 0.05, "freq": 0.8, "speed": 1.1})
	# el violeta, colgado de la barandilla de la grada, a la derecha
	var vt := _art("aca_banner_violeta")
	_cloth(vt, 0.03, Vector3(10.15, 1.9 - vt.get_height() * 0.015, -6.45), {"amp": 0.03, "freq": 0.8, "speed": 1.3})
	# macetas y un globo terráqueo
	_prop("plant_big", 0.04, Vector3(-9.6, 0, -7.6))
	_prop("globe", 0.034, Vector3(9.9, 0.5, -8.1))
	_prop("fern", 0.05, Vector3(-1.2, 0.5, -8.3))

# ------------------------------------------------------------------ 2. EL CONCURSO DE POCIONES DE ROBLEDAL

## Los puestos rivales y sus letreros: los nombres del Escalafón del Gremio (RANK, ranking.gd). EVENTS-LOGIC los lee de
## aquí (Events.rivals_for: lo que va antes de «·», en este orden, sin Fizz) para el marcador del concurso.
const CON_RIVALS := {
	"fizz": "Fizz · ¡pociones con chispa!",
	"raicesrocio": "Raíces y Rocío",
	"vado": "Hierbas del Vado",
}
const CON_STAGE_TOP := 0.55
const CON_DAIS_TOP := 1.1
const CON_PLAYER := Vector3(-3.55, CON_STAGE_TOP, -2.15)

## Un escenario de madera en la plaza de Robledal al atardecer: el jurado en una tarima al fondo, bajo el estandarte;
## el puesto de ella a la izquierda y el de Fizz a la derecha; la fila (gente que sube a probar) delante; farolillos,
## banderines, casas con las ventanas encendidas y el público alrededor.
func _concurso() -> void:
	_camera(Vector3(-0.3, 5.2, 9.4), Vector3(-0.3, 1.75, -3.4), 35.0, 18.0, 6.5)
	_environment(Color(0.16, 0.1, 0.18), Color(0.58, 0.46, 0.72), 0.55, 0.5, 1.15)
	_sun(Vector3(0.6, -0.42, 0.68), Color(1.0, 0.58, 0.36), 1.15, 34.0)
	_fill(Vector3(-0.3, 4.4, 5.0), Color(1.0, 0.76, 0.56), 0.55, 18.0)
	_con_square()
	_con_stage()
	_con_her_stall()
	_con_fizz_stall()
	_con_jury()
	_con_rival_stall(-8.7, "raicesrocio", "verde", "goods_herbs", "")
	_con_rival_stall(8.3, "vado", "azul", "goods_books", "")
	_con_lights()
	_marker("Player", CON_PLAYER, 1)
	_marker("Bench", Vector3(-4.6, CON_STAGE_TOP, -2.7), 1)
	_queue(Vector3(-1.65, CON_STAGE_TOP, -2.05), Vector3(0.72, 0, -0.06), -1)
	# el público, alrededor del escenario (de pie, mirando hacia él)
	for p in [[-7.2, -0.9, 1], [5.9, -0.8, -1], [-7.9, -2.6, 1], [6.8, -2.3, -1], [-6.5, 0.2, 1], [4.9, 0.1, -1],
			[-8.6, -0.2, 1], [7.7, -0.4, -1], [-10.2, -3.9, 1], [5.2, CON_STAGE_TOP, -6.4, -1],
			[-9.4, -1.6, 1], [8.9, -1.4, -1], [-6.6, -4.1, 1], [6.2, -4.3, -1]]:
		if p.size() == 4:
			_spot(Vector3(p[0], p[1], p[2]), p[3])
		else:
			_spot(Vector3(p[0], 0, p[1]), p[2])
	_crowd_emotes = ["note", "heart", "sparkle", "dots"]

## La plaza: adoquines, las casas de Robledal con las ventanas encendidas, un muro bajo, el gran roble y el público.
func _con_square() -> void:
	_box_b(-20.0, 20.0, -0.2, 0.0, -14.0, 7.0, _mat("res://assets/tex/cobble_street.png", "", 0.5, 0.95, Color(0.92, 0.86, 0.9)))
	# casas a los dos lados del fondo y una fila más baja detrás del roble
	for h in [[-17.0, 4.6, 5.0, Color(0.96, 0.88, 0.76), "roof_red", "con_window_a", -9.6],
			[-12.2, 4.4, 4.6, Color(0.9, 0.82, 0.92), "roof_slate", "con_window_b", -9.2],
			[6.6, 4.4, 4.7, Color(0.95, 0.85, 0.7), "roof_plum", "con_window_b", -9.3],
			[11.2, 5.0, 5.2, Color(0.86, 0.9, 0.84), "roof_red", "con_window_a", -9.7],
			[-7.6, 4.0, 3.6, Color(0.92, 0.84, 0.78), "roof_slate", "con_window_a", -12.5],
			[-3.4, 4.2, 3.8, Color(0.97, 0.9, 0.8), "roof_red", "con_window_b", -12.8],
			[1.0, 4.6, 3.6, Color(0.88, 0.82, 0.92), "roof_plum", "con_window_a", -12.4]]:
		_con_house(h[0], h[1], h[2], h[3], h[4], h[5], h[6])
	# muro bajo de piedra al fondo de la plaza
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.5, 0.9, Color(0.9, 0.86, 0.9))
	_box_b(-7.8, 6.4, 0.0, 0.9, -10.6, -10.2, stone)
	# el roble grande con farolillos, a la izquierda del escenario
	var tree := _prop("tree", 0.085, Vector3(-9.6, 0, -7.8))
	tree.modulate = Color(0.78, 0.74, 0.86)
	_prop("bush", 0.05, Vector3(-11.0, 0, -6.4))
	_prop("bush", 0.05, Vector3(10.6, 0, -6.6))
	# público pintado detrás de los puestos rivales (se anima: levantan los brazos)
	_anim(_art("con_crowd_a"), 2, 1.6, 0.04, Vector3(-11.4, 0, -4.6))
	_anim(_art("con_crowd_b"), 2, 1.4, 0.04, Vector3(11.0, 0, -4.4))
	_anim(_art("con_crowd_b"), 2, 1.2, 0.04, Vector3(-1.0, 0, -9.6))
	# el público de espaldas en primer plano (desenfocado), mirando el escenario
	_anim(_art("con_crowd_back_a"), 2, 1.5, 0.042, Vector3(-4.4, -0.5, 1.6))
	_anim(_art("con_crowd_back_b"), 2, 1.3, 0.042, Vector3(3.4, -0.45, 1.7))
	# faroles de la plaza
	for x in [-6.8, 5.9]:
		var lp := _prop("lamppost", 0.05, Vector3(x, 0, -0.2))
		lp.modulate = Color(1.0, 0.96, 0.9)

func _con_house(x0: float, w: float, h: float, col: Color, roof: String, win: String, fz: float) -> void:
	var x1 := x0 + w
	var depth := 3.4
	var plaster := _mat("res://assets/tex/plaster.png", "res://assets/tex/plaster_n.png", 0.25, 0.95, col)
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.5, 0.9)
	var beam := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(x0, x1, 0.0, h, fz - depth, fz, plaster)
	_box_b(x0 - 0.02, x1 + 0.02, 0.0, 0.6, fz - depth, fz + 0.05, stone)
	for y in [0.6, 2.5]:
		_box_b(x0, x1, y, y + 0.14, fz, fz + 0.07, beam)
	_box_b(x0, x1, h - 0.14, h, fz, fz + 0.1, beam)
	for x in [x0 + 0.07, x1 - 0.07]:
		_box_b(x - 0.08, x + 0.08, 0.6, h, fz, fz + 0.07, beam)
	var rh := depth * 0.5 * 1.3
	var pr := PrismMesh.new()
	pr.size = Vector3(depth + 0.8, rh, w + 0.36)
	var rm := MeshInstance3D.new()
	rm.mesh = pr
	rm.material_override = _mat("res://assets/tex/%s.png" % roof, "", 0.6, 0.9)
	rm.position = Vector3((x0 + x1) / 2.0, h + rh / 2.0, fz - depth / 2.0)
	rm.rotation_degrees = Vector3(0, 90, 0)
	add_child(rm)
	# ventanas encendidas (brillan un poco) arriba y abajo
	var n := maxi(1, int(w / 1.5))
	for i in n:
		var wx := x0 + w * (i + 0.5) / n
		for wy in [2.85, 1.0]:
			if wy < 2.0 and i % 2 == 1:
				continue
			var ws := _ev(win, 0.034, Vector3(wx, wy, fz + 0.09))
			ws.shaded = false
			ws.modulate = Color(1.05, 0.95, 0.9)

## El escenario: tablado con su faldón rojo y dorado, escalones delante, el arco con el estandarte y las guirnaldas.
func _con_stage() -> void:
	var planks := _mat("res://assets/tex/floor.png", "res://assets/tex/floor_n.png", 0.5, 0.85, Color(1.0, 0.9, 0.82))
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var top := CON_STAGE_TOP
	_box_b(-6.2, 5.6, 0.0, top, -6.9, -1.2, planks)
	_panel(_art("con_skirt"), Vector2(11.8, top), Vector3(-0.3, top / 2.0, -1.196), Vector3.BACK, Vector2(11.8 / 2.0, 1.0))
	for sx in [-6.2, 5.6]:
		var side := _panel(_art("con_skirt"), Vector2(5.7, top), Vector3(sx + (-0.004 if sx < 0.0 else 0.004), top / 2.0, -4.05),
			Vector3.LEFT if sx < 0.0 else Vector3.RIGHT, Vector2(5.7 / 2.0, 1.0))
	# escalones delante, en el centro
	_box_b(-0.9, 0.3, 0.0, top * 0.5, -1.2, -0.75, wood_d)
	_box_b(-0.9, 0.3, 0.0, top * 0.5, -1.2, -0.95, planks)
	# el arco sobre el escenario: dos postes, el travesaño, el estandarte y las guirnaldas
	var post := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	for px in [-5.9, 5.3]:
		_box_b(px - 0.14, px + 0.14, top, 5.0, -6.75, -6.47, post)
	_box_b(-6.2, 5.6, 4.72, 4.98, -6.74, -6.48, post)
	var title := _ev("con_title", 0.048, Vector3(-0.3, 3.55, -6.42))
	title.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label("Concurso de Pociones de Robledal", Vector3(-0.3, 4.17, -6.39), 64, 0.0062, Color(0.62, 0.14, 0.18), true).outline_modulate = Color(1.0, 0.95, 0.82)
	for i in 5:
		var g := _ev("con_garland", 0.04, Vector3(-4.9 + i * 2.5, 4.72, -6.38), null, "top")
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# banderines a los lados del arco
	for b in [[-4.6, "bunting_a"], [3.9, "bunting_b"]]:
		var bt := _tex("res://assets/props/%s.png" % b[1])
		_cloth(bt, 0.024, Vector3(b[0], 4.3, -6.36), {"amp": 0.03, "freq": 0.6, "speed": 2.0, "pin_left": 0.0})

## Su puesto: el caldero, una mesa de trabajo (ella a un lado, quien prueba al otro), un toldo morado y su letrero.
func _con_her_stall() -> void:
	var top := CON_STAGE_TOP
	cauldron = Cauldron.new()
	cauldron.name = "Cauldron"
	cauldron.position = Vector3(-4.6, top, -2.7)
	add_child(cauldron)
	cauldron.build()
	_worktable(Vector3(-2.75, top, -2.35), 0.62, 1.7, "morado")
	_stall_frame(-5.45, -2.05, top, -3.55, -1.55, "morado", "Caldero Nocturno")
	_ev("aca_vials", 0.022, Vector3(-2.7, top + 0.9, -2.95))
	_prop("jar_lagrima_sirena", 0.022, Vector3(-2.8, top + 0.9, -2.2))
	_prop("bottle_sm_1", 0.03, Vector3(-2.65, top + 0.9, -1.75))
	_prop("crate", 0.033, Vector3(-5.35, top, -3.2))
	_prop("jar_ambar_abeja", 0.024, Vector3(-5.35, top + 0.43, -3.22))
	_prop("sack", 0.033, Vector3(-3.9, top, -3.4))

## Una mesa de trabajo que corre hacia el fondo (como el mostrador de la tienda): de un lado ella, del otro quien llega.
func _worktable(c: Vector3, w: float, l: float, cloth := "") -> void:
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.55, Color(0.9, 0.82, 0.74))
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var t := 0.9
	_box_b(c.x - w / 2.0 - 0.04, c.x + w / 2.0 + 0.04, c.y + t - 0.07, c.y + t, c.z - l / 2.0 - 0.04, c.z + l / 2.0 + 0.04, wood_l)
	_box_b(c.x - w / 2.0 + 0.04, c.x + w / 2.0 - 0.04, c.y, c.y + t - 0.07, c.z - l / 2.0 + 0.04, c.z + l / 2.0 - 0.04, wood_d)
	if cloth != "":
		var v := _tex("res://assets/tex/valance_%s.png" % cloth)
		var m := StandardMaterial3D.new()
		m.albedo_texture = v
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.uv1_scale = Vector3(l / 2.0, 1.0, 1.0)
		var q := _quad(Vector2(l, 0.3), Vector3(c.x + w / 2.0 + 0.05, c.y + t - 0.17, c.z), m)
		q.rotation_degrees = Vector3(0, 90, 0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m2 := m.duplicate()
		m2.uv1_scale = Vector3(w / 2.0, 1.0, 1.0)
		var q2 := _quad(Vector2(w, 0.3), Vector3(c.x, c.y + t - 0.17, c.z + l / 2.0 + 0.05), m2)
		q2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## El armazón de un puesto: cuatro postes, toldo a rayas inclinado con su faldón y un letrero con el nombre.
func _stall_frame(x0: float, x1: float, y0: float, z0: float, z1: float, awning: String, sign: String, sign_y := 2.62) -> void:
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	for px in [x0, x1]:
		_box_b(px - 0.05, px + 0.05, y0, y0 + 2.5, z1 - 0.1, z1, wood_d)
		_box_b(px - 0.05, px + 0.05, y0, y0 + 2.95, z0, z0 + 0.1, wood_d)
	var aw := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0 + 0.5, z1 - z0 + 0.3)
	aw.mesh = pm
	var am := StandardMaterial3D.new()
	am.albedo_texture = _tex("res://assets/tex/awning_%s.png" % awning)
	am.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.uv1_scale = Vector3((x1 - x0) / 2.6, 1.0, 1.0)
	aw.material_override = am
	aw.position = Vector3((x0 + x1) / 2.0, y0 + 2.72, (z0 + z1) / 2.0 - 0.05)
	aw.rotation_degrees = Vector3(14.0, 0, 0)
	add_child(aw)
	var vm := StandardMaterial3D.new()
	vm.albedo_texture = _tex("res://assets/tex/valance_%s.png" % awning)
	vm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	vm.uv1_scale = Vector3((x1 - x0 + 0.5) / 2.6, 1.0, 1.0)
	var val := _quad(Vector2(x1 - x0 + 0.5, 0.32), Vector3((x0 + x1) / 2.0, y0 + 2.36, z1 + 0.12), vm)
	val.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if sign != "":
		_box_b((x0 + x1) / 2.0 - 0.95, (x0 + x1) / 2.0 + 0.95, y0 + sign_y - 0.18, y0 + sign_y + 0.18, z1 + 0.14, z1 + 0.2, wood_d)
		_label(sign, Vector3((x0 + x1) / 2.0, y0 + sign_y, z1 + 0.215), 40, 0.0056)

## El puesto de Fizz, a la derecha, frente al de ella: su alambique de cobre que burbujea, humo de colores, su letrero
## de explosión y él mismo detrás de la mesa, mirándola.
func _con_fizz_stall() -> void:
	var top := CON_STAGE_TOP
	_worktable(Vector3(3.05, top, -2.4), 0.62, 1.7, "naranja")
	_stall_frame(2.35, 5.3, top, -3.6, -1.6, "naranja", "")
	var sign := _ev("con_fizz_sign", 0.04, Vector3(3.85, top + 2.55, -1.42))
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label(CON_RIVALS["fizz"].get_slice("·", 1).strip_edges(), Vector3(3.85, top + 2.38, -1.38), 30, 0.0052, Color(1.0, 0.92, 0.7), false)
	_anim(_art("con_fizz_still"), 2, 3.0, 0.034, Vector3(4.6, top, -2.9))
	_prop("bottle_sm_4", 0.03, Vector3(3.0, top + 0.9, -2.9))
	_prop("bottle_sm_2", 0.03, Vector3(3.1, top + 0.9, -2.3))
	_prop("jar_ceniza_dragon", 0.022, Vector3(3.05, top + 0.9, -1.8))
	var fz := _fixed_actor("fizz", Vector3(3.8, top, -2.35), -1)
	# humo de colores del alambique
	var smoke := GPUParticles3D.new()
	smoke.amount = 8
	smoke.lifetime = 3.0
	smoke.preprocess = 3.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.1, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0.05, 0.05, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color = Color(0.75, 1.0, 0.7, 0.5)
	var hue := Gradient.new()
	hue.set_color(0, Color(0.6, 1.0, 0.6, 0.0))
	hue.add_point(0.2, Color(0.7, 1.0, 0.6, 0.7))
	hue.add_point(0.6, Color(1.0, 0.6, 0.9, 0.5))
	hue.set_color(hue.get_point_count() - 1, Color(0.7, 0.6, 1.0, 0.0))
	var ht := GradientTexture1D.new()
	ht.gradient = hue
	pm.color_ramp = ht
	smoke.process_material = pm
	smoke.draw_pass_1 = _particle_quad(_tex("res://assets/fx/smoke.png"), 0.045)
	smoke.position = Vector3(4.55, top + 1.25, -2.95)
	smoke.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 6, 4))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	_omni(Vector3(4.4, top + 1.2, -2.4), Color(0.6, 1.0, 0.55), 0.55, 3.2)

## La tarima del jurado al fondo del escenario: mesa con paño azul y la copa, tres sillas de respaldo alto y los
## marcadores Judge0..Judge2 (de pie sobre la tarima, detrás de la mesa: la mesa les tapa las piernas).
func _con_jury() -> void:
	var top := CON_STAGE_TOP
	var dt := CON_DAIS_TOP
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.55, Color(0.9, 0.82, 0.74))
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(-2.3, 1.7, top, dt, -6.8, -4.35, wood)
	_panel(_art("con_skirt"), Vector2(4.0, dt - top), Vector3(-0.3, (top + dt) / 2.0, -4.346), Vector3.BACK, Vector2(2.0, 1.0))
	_box_b(-0.9, 0.3, top, (top + dt) / 2.0, -4.35, -3.95, wood_d)
	# mesa
	var tz0 := -5.45
	var tz1 := -4.85
	var tt := dt + 0.78
	_box_b(-1.95, 1.35, tt - 0.07, tt, tz0, tz1, wood_l)
	_box_b(-1.9, 1.3, dt, tt - 0.07, tz0 + 0.05, tz1 - 0.02, wood_d)
	var cloth := _ev("con_jury_cloth", 0.034, Vector3(-0.3, tt, tz1 + 0.03), null, "top")
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label("Jurado", Vector3(-0.3, tt - 0.62, tz1 + 0.05), 34, 0.005, Color(1.0, 0.88, 0.56))
	_ev("con_cup", 0.03, Vector3(1.05, tt, tz1 - 0.15))
	_prop("bottle_sm_3", 0.026, Vector3(-1.75, tt, tz1 - 0.12))
	_prop("open_book", 0.02, Vector3(-0.8, tt, tz1 - 0.12))
	# sillas y marcadores
	for i in 3:
		var jx := -1.3 + i * 1.0
		_ev("con_chair", 0.04, Vector3(jx, dt, -6.25))
		var m := _marker("Judge%d" % i, Vector3(jx, dt, -5.85), -1 if i < 2 else -1)
		m.set_meta("top", tt + 0.6)
	_omni(Vector3(-0.3, dt + 2.3, -4.2), Color(1.0, 0.82, 0.58), 0.95, 5.0)
	# la mesita donde se presentan las pociones al jurado, al pie de la tarima
	var pt := top + 0.62
	_box_b(-0.75, 0.15, pt - 0.06, pt, -3.0, -2.5, wood_l)
	_box_b(-0.38, -0.22, top, pt - 0.06, -2.83, -2.67, wood_d)
	_box_b(-0.6, 0.0, top, top + 0.05, -2.9, -2.6, wood_d)
	var pcloth := _ev("con_jury_cloth", 0.0095, Vector3(-0.3, pt, -2.48), null, "top")
	pcloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ev("con_tray", 0.03, Vector3(-0.3, pt, -2.77))

## Un puesto rival en la plaza (como los del mercado): mostrador, toldo, mercancía, letrero y alguien detrás.
func _con_rival_stall(x: float, key: String, awning: String, goods: String, keeper: String) -> void:
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.6)
	var z := -3.2
	_box_b(x - 1.1, x + 1.1, 0.0, 0.76, z - 0.35, z + 0.35, wood)
	_box_b(x - 1.17, x + 1.17, 0.76, 0.83, z - 0.4, z + 0.4, wood_l)
	_stall_frame(x - 1.2, x + 1.2, 0.0, z - 0.9, z + 0.42, awning, CON_RIVALS[key])
	_prop(goods, 0.025, Vector3(x - 0.1, 0.83, z))
	if keeper != "":
		var a := _fixed_actor(keeper, Vector3(x - 0.3, 0, z - 0.6), 1 if x < 0.0 else -1)
		a.position.y = clampf(1.62 - a.top_height(), 0.0, 0.55)

## Farolillos de papel colgados en hileras sobre la plaza (un MultiMesh), su luz cálida y las guirnaldas de luces.
func _con_lights() -> void:
	var pts := []
	var rows := [[-7.7, 5.5, 0.45], [-5.1, 5.35, 0.55], [-2.6, 5.75, 0.5]]
	for r in rows:
		var z: float = r[0]
		var y0: float = r[1]
		var sag: float = r[2]
		var n := 15
		for i in n:
			var t := float(i) / float(n - 1)
			var x := lerpf(-10.5, 9.5, t) + (0.35 if int(z) % 2 == 0 else 0.0)
			var y := y0 - sag * (1.0 - pow(2.0 * t - 1.0, 2.0)) * 1.6
			pts.append(Vector3(x, y, z))
	_floaters(_art("con_lanterns"), 2, 4, 0.033, pts, {"fps": 3.0, "bob": 0.0, "sway": 0.08},
		Color(1.0, 0.62, 0.32), 0.95, 0.32)
	# pocas luces (en Compatibility cada objeto recibe 8 como mucho): tres grandes bajo los farolillos
	for l in [[-6.0, 4.4, -3.6], [-0.3, 4.6, -3.0], [5.4, 4.4, -3.6]]:
		_omni(Vector3(l[0], l[1], l[2]), Color(1.0, 0.66, 0.36), 0.85, 9.5)
	_dust(Vector3(-0.3, 2.6, -3.0), Vector3(8.0, 2.0, 3.0), 30, Color(1.0, 0.85, 0.6))

# ------------------------------------------------------------------ 3. LA FERIA DEL TORNEO

const TOR_PLAYER := Vector3(-3.55, 0, -2.15)
const TOR_LIST_Z := -10.0          # la valla central de las justas
var _riders: Array = []            # [{s: AnimatedSprite3D, dir: 1/-1, z: float, dust: GPUParticles3D}]
var _joust_t := 0.2
var _joust_on := false
var _joust_x := 0.0
var _clash_fx: GPUParticles3D
var _swallow_t := 2.0
var _swallow_frames: SpriteFrames

## El campo del torneo por la mañana: su puesto delante a la izquierda, con una fila marcada con cuerdas para caballeros
## y escuderos; detrás, la liza con su valla pintada (dos caballeros justan de vez en cuando), la grada de madera con
## público, las tiendas a rayas con gallardetes, caballos, el armero y, a lo lejos, el castillo.
func _torneo() -> void:
	_camera(Vector3(-0.3, 5.2, 9.4), Vector3(-0.3, 1.5, -3.4), 35.0, 20.0, 6.5)
	_environment(Color(0.62, 0.78, 0.98), Color(0.6, 0.68, 0.86), 0.42, 0.3, 1.2)
	_sun(Vector3(0.55, -0.62, -0.56), Color(1.0, 0.93, 0.8), 1.55, 40.0)
	_fill(Vector3(-0.3, 4.2, 5.0), Color(1.0, 0.9, 0.78), 0.28, 18.0)
	_tor_ground()
	_tor_lists()
	_tor_stand()
	_tor_tents()
	_tor_her_stall()
	_tor_paddock()
	_marker("Player", TOR_PLAYER, 1)
	_marker("Bench", Vector3(-4.6, 0, -2.7), 1)
	_queue(Vector3(-1.65, 0, -2.05), Vector3(0.8, 0, -0.06), -1)
	# el público: a lo largo de la valla de la liza (mirando las justas), junto a los caballos y al armero
	for p in [[-2.6, -6.9, 1], [0.9, -7.0, -1], [-5.4, -6.8, 1], [3.6, -6.9, -1], [-0.9, -7.1, 1], [2.2, -7.2, -1],
			[5.4, -6.8, -1], [-7.7, -3.4, 1], [6.9, -3.5, -1], [-4.1, -7.0, 1], [7.8, -6.6, -1], [-6.6, -7.0, 1],
			[8.6, -2.6, -1], [-9.0, -2.2, 1]]:
		_spot(Vector3(p[0], 0, p[1]), p[2])
	_crowd_emotes = ["note", "heart", "excl", "star"]

func _tor_ground() -> void:
	var grass := _mat(ART + "tor_grass.png", "", 0.5, 1.0, Color(0.86, 0.9, 0.84))
	var dirt := _mat(ART + "tor_dirt.png", "", 0.5, 1.0, Color(0.82, 0.76, 0.72))
	_box_b(-40.0, 40.0, -0.2, 0.0, -60.0, 8.0, grass)
	_box_b(-40.0, 40.0, -0.2, 0.01, -12.6, -7.4, dirt, null, false)       # la pista de las justas
	# la tierra pisada delante de su puesto y de la fila (mancha de bordes irregulares sobre la hierba)
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = _art("tor_trodden")
	tm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tm.roughness = 1.0
	var trod := MeshInstance3D.new()
	var tp := PlaneMesh.new()
	tp.size = Vector2(12.0, 4.0)
	trod.mesh = tp
	trod.material_override = tm
	trod.position = Vector3(-1.0, 0.01, -2.2)
	trod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trod)
	# el cielo de la mañana con las colinas y el castillo a lo lejos
	var sh := ShaderMaterial.new()
	sh.shader = load("res://shaders/sky.gdshader")
	sh.set_shader_parameter("hills", _tex("res://assets/tex/backdrop.png"))
	sh.set_shader_parameter("top_color", Color(0.4, 0.64, 0.98))
	sh.set_shader_parameter("bottom_color", Color(0.96, 0.92, 0.82))
	sh.set_shader_parameter("hills_tint", Color(0.9, 1.0, 0.95))
	sh.set_shader_parameter("star_amount", 0.0)
	sh.set_shader_parameter("moon_amount", 0.0)
	sh.set_shader_parameter("hills_repeat", 3.0)
	sh.set_shader_parameter("aspect", 120.0 / 30.0)
	sh.set_shader_parameter("hills_height", 0.5)
	var q := _quad(Vector2(120, 30), Vector3(0.0, 9.0, -52.0), sh)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var castle := _ev("tor_castle", 0.13, Vector3(3.0, -0.6, -44.0))
	castle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	castle.modulate = Color(0.95, 1.0, 1.05)
	for t in [[-14.0, -30.0], [-9.0, -33.0], [16.0, -31.0], [21.0, -34.0], [-20.0, -32.0]]:
		var tr := _prop("tree", 0.07, Vector3(t[0], 0, t[1]))
		tr.modulate = Color(0.85, 0.95, 1.0)

## La liza: la valla central pintada a rayas, las vallas de los lados y los estandartes en sus mástiles.
func _tor_lists() -> void:
	var post := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var rail := _mat(ART + "tor_rail.png", "", 1.0, 0.8)
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var z := TOR_LIST_Z
	_box_b(-40.0, 40.0, 0.55, 1.15, z - 0.06, z + 0.06, rail)
	var x := -30.0
	while x <= 30.0:
		_box_b(x - 0.08, x + 0.08, 0.0, 1.25, z - 0.09, z + 0.09, post)
		x += 2.5
	# vallas de los lados (la de delante, donde mira el público)
	for fz in [-7.4, -12.6]:
		_box_b(-40.0, 40.0, 0.62, 0.72, fz - 0.04, fz + 0.04, wood)
		_box_b(-40.0, 40.0, 0.28, 0.36, fz - 0.04, fz + 0.04, wood)
		x = -30.0
		while x <= 30.0:
			_box_b(x - 0.06, x + 0.06, 0.0, 0.85, fz - 0.06, fz + 0.06, post)
			x += 1.8
	# estandartes en sus mástiles junto a la valla
	var keys := ["leon", "torre", "estrella", "leon"]
	var xs := [-7.0, -1.6, 4.4, 10.0]
	for i in xs.size():
		var mx: float = xs[i]
		_box_b(mx - 0.06, mx + 0.06, 0.0, 4.6, -7.75, -7.63, post)
		_box_b(mx - 0.5, mx + 0.5, 4.5, 4.58, -7.75, -7.63, post)
		var tex := _art("tor_banner_" + keys[i])
		var h: float = tex.get_height() * 0.042
		_cloth(tex, 0.042, Vector3(mx, 4.5 - h / 2.0, -7.58), {"amp": 0.07, "freq": 0.7, "speed": 1.7})
	# los destellos del choque de lanzas (se crea ya, para que WebGL compile su shader detrás del fundido)
	_clash_fx = GPUParticles3D.new()
	_clash_fx.amount = 18
	_clash_fx.lifetime = 0.9
	_clash_fx.one_shot = true
	_clash_fx.explosiveness = 0.95
	var cpm := ParticleProcessMaterial.new()
	cpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cpm.emission_sphere_radius = 0.2
	cpm.direction = Vector3(0, 1, 0)
	cpm.spread = 90.0
	cpm.initial_velocity_min = 1.2
	cpm.initial_velocity_max = 2.6
	cpm.gravity = Vector3(0, -3.0, 0)
	cpm.color = Color(1.8, 1.6, 1.0)
	cpm.color_ramp = _fade_ramp()
	_clash_fx.process_material = cpm
	_clash_fx.draw_pass_1 = _particle_quad(_tex("res://assets/fx/sparkle.png"), 0.05, true)
	_clash_fx.position = Vector3(0, 2.0, z)
	_clash_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clash_fx.emitting = true
	add_child(_clash_fx)
	# los dos caballeros que justan a lo largo de la valla (cada tanto)
	for r in [["rojo", 1, z + 0.75], ["azul", -1, z - 0.75]]:
		var s := _anim(_art("tor_rider_" + r[0]), 2, 8.0, 0.045, Vector3(0, 0, r[2]))
		s.flip_h = r[1] < 0
		s.visible = false
		var dust := _dust_trail()
		dust.position = Vector3(0, 0.15, r[2])
		_riders.append({"s": s, "dir": r[1], "z": r[2], "dust": dust})

func _dust_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.2
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.4, 0.05, 0.2)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -0.3, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.color = Color(0.9, 0.8, 0.62, 0.55)
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.draw_pass_1 = _particle_quad(_tex("res://assets/fx/smoke.png"), 0.05)
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -1, -3), Vector3(80, 5, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## La grada de madera, detrás de la liza a la derecha: tres gradas con público pintado (que aplaude), el paño
## heráldico delante, el dosel a rayas y estandartes.
func _tor_stand() -> void:
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var x0 := 2.0
	var x1 := 13.0
	for i in 3:
		var zf := -13.4 - i * 0.8
		_box_b(x0, x1, 0.0, 0.6 + i * 0.6, zf - 0.8, zf, wood)
	_box_b(x0, x1, 0.0, 4.4, -16.3, -16.0, wood_d)
	for px in [x0 + 0.1, (x0 + x1) / 2.0, x1 - 0.1]:
		_box_b(px - 0.08, px + 0.08, 0.0, 4.6, -13.5, -13.34, wood_d)
	_panel(_art("tor_drape"), Vector2(x1 - x0, 0.75), Vector3((x0 + x1) / 2.0, 0.6 - 0.375 + 0.02, -13.38), Vector3.BACK, Vector2((x1 - x0) / 2.0, 1.0))
	# el dosel
	var aw := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0 + 0.6, 3.4)
	aw.mesh = pm
	var am := StandardMaterial3D.new()
	am.albedo_texture = _art("tor_stripes_azul")
	am.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.uv1_scale = Vector3((x1 - x0) / 1.0, 1.0, 1.0)
	aw.material_override = am
	aw.position = Vector3((x0 + x1) / 2.0, 4.55, -14.8)
	aw.rotation_degrees = Vector3(-12.0, 0, 0)
	add_child(aw)
	var vm := StandardMaterial3D.new()
	vm.albedo_texture = _tex("res://assets/tex/valance_azul.png")
	vm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	vm.uv1_scale = Vector3((x1 - x0) / 2.0, 1.0, 1.0)
	var val := _quad(Vector2(x1 - x0 + 0.6, 0.36), Vector3((x0 + x1) / 2.0, 4.06, -13.1), vm)
	val.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# el público pintado en las gradas
	var strips := ["tor_crowd_a", "tor_crowd_b", "tor_crowd_a"]
	for i in 3:
		var c := _anim(_art(strips[i]), 2, 1.1 + i * 0.25, 0.05, Vector3((x0 + x1) / 2.0 + (0.6 if i == 1 else 0.0), 0.6 + i * 0.6 - 0.35, -13.75 - i * 0.8))
		c.flip_h = i == 2
	for b in [[x0 - 0.3, "tor_banner_leon"], [x1 + 0.3, "tor_banner_torre"]]:
		_box_b(b[0] - 0.06, b[0] + 0.06, 0.0, 5.6, -13.3, -13.18, wood_d)
		var tex := _art(b[1])
		_cloth(tex, 0.04, Vector3(b[0], 5.5 - tex.get_height() * 0.02, -13.12), {"amp": 0.06, "freq": 0.7, "speed": 1.5})

## Las tiendas a rayas de los caballeros (cilindro y cono con la lona), con un gallardete en la punta y un escudo.
func _tor_tents() -> void:
	var tents := [[-10.6, -15.0, "rojo", "rojo", "a"], [-6.0, -16.4, "azul", "oro", "b"], [-15.2, -16.8, "verde", "verde", "c"],
		[-1.6, -17.6, "violeta", "azul", ""], [17.0, -16.0, "rojo", "oro", "a"]]
	for t in tents:
		var c := Vector3(t[0], 0, t[1])
		var lona := StandardMaterial3D.new()
		lona.albedo_texture = _art("tor_stripes_" + t[2])
		lona.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		lona.uv1_scale = Vector3(6.0, 1.0, 1.0)
		lona.roughness = 0.95
		var wall := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 1.6
		cy.bottom_radius = 1.7
		cy.height = 2.2
		cy.radial_segments = 20
		cy.rings = 1
		wall.mesh = cy
		wall.material_override = lona
		wall.position = c + Vector3(0, 1.1, 0)
		add_child(wall)
		var roof := MeshInstance3D.new()
		var co := CylinderMesh.new()
		co.top_radius = 0.02
		co.bottom_radius = 1.95
		co.height = 1.6
		co.radial_segments = 20
		co.rings = 1
		roof.mesh = co
		roof.material_override = lona
		roof.position = c + Vector3(0, 3.0, 0)
		add_child(roof)
		# la entrada (oscura) y el escudo
		var door := _quad(Vector2(0.9, 1.6), c + Vector3(0, 0.8, 1.72), _flat(Color(0.16, 0.1, 0.12)))
		door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if t[4] != "":
			_ev("tor_shield_" + t[4], 0.04, c + Vector3(0.75, 1.3, 1.75))
		# mástil con gallardete
		_box_b(c.x - 0.03, c.x + 0.03, 3.6, 4.6, c.z - 0.03, c.z + 0.03, _flat(Color(0.35, 0.25, 0.2)))
		var pt := _art("tor_pennant_" + t[3])
		_cloth(pt, 0.04, c + Vector3(pt.get_width() * 0.02, 4.42, 0.0), {"amp": 0.08, "freq": 0.9, "speed": 2.6, "pin_left": 1.0, "droop": 0.05})

## Su puesto: el caldero, la mesa de trabajo, el toldo morado con su letrero y la fila marcada con postes y cuerdas.
func _tor_her_stall() -> void:
	cauldron = Cauldron.new()
	cauldron.name = "Cauldron"
	cauldron.position = Vector3(-4.6, 0, -2.7)
	add_child(cauldron)
	cauldron.build()
	_worktable(Vector3(-2.75, 0, -2.35), 0.62, 1.7, "morado")
	_stall_frame(-5.45, -2.05, 0.0, -3.55, -1.55, "morado", "Caldero Nocturno")
	_ev("aca_vials", 0.022, Vector3(-2.7, 0.9, -2.95))
	_prop("jar_raiz_mandragora", 0.022, Vector3(-2.8, 0.9, -2.2))
	_prop("bottle_sm_5", 0.03, Vector3(-2.65, 0.9, -1.75))
	_prop("crate", 0.033, Vector3(-5.35, 0, -3.2))
	_prop("jar_pluma_fenix", 0.024, Vector3(-5.35, 0.43, -3.22))
	_prop("barrel", 0.034, Vector3(-6.1, 0, -2.4))
	# la fila: postes con cuerdas a los dos lados, de su mesa hacia la derecha, y un letrero al final
	var post := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var rope := _flat(Color(0.72, 0.58, 0.38))
	for rz in [-1.35, -2.85]:
		var x := -1.9
		var prev := -INF
		while x <= 3.4:
			_box_b(x - 0.05, x + 0.05, 0.0, 0.95, rz - 0.05, rz + 0.05, post)
			_box_b(x - 0.08, x + 0.08, 0.95, 1.0, rz - 0.08, rz + 0.08, _flat(Color(0.85, 0.66, 0.3), 0.4, 0.6))
			if prev > -INF:
				for k in 2:   # la cuerda cuelga un poco: dos tramos
					var xa: float = lerpf(prev, x, k * 0.5)
					var xb: float = lerpf(prev, x, (k + 1) * 0.5)
					var r := _box_b(xa, xb, 0.84, 0.865, rz - 0.015, rz + 0.015, rope, null, false)
					r.rotation_degrees = Vector3(0, 0, -6.0 if k == 0 else 6.0)
					r.position.y -= 0.06
			prev = x
			x += 1.32
	# el letrero al final de la fila, detrás de la cuerda (fuera del camino por el que llegan y se van)
	_box_b(3.55, 3.63, 0.0, 1.5, -3.25, -3.17, post)
	_box_b(3.05, 4.15, 1.15, 1.55, -3.16, -3.1, _mat("res://assets/tex/wood_light.png", "", 1.0, 0.8))
	_label("← Pociones", Vector3(3.6, 1.35, -3.085), 34, 0.0052, Color(0.25, 0.14, 0.1), false).outline_size = 0
	# público de espaldas en las esquinas de abajo (desenfocado) y unas flores delante
	_anim(_art("tor_crowd_back"), 2, 1.3, 0.042, Vector3(-6.6, -0.55, 1.9))
	var cb := _anim(_art("tor_crowd_back"), 2, 1.1, 0.042, Vector3(6.2, -0.6, 2.0))
	cb.flip_h = true
	for f in [[-1.2, 1.3], [1.6, 1.6], [3.4, 1.1]]:
		_prop("flowers", 0.04, Vector3(f[0], 0, f[1]))

## Los caballos atados junto al abrevadero, paja, el armero con las lanzas y unos escudos.
func _tor_paddock() -> void:
	var post := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(-10.4, -6.6, 0.85, 0.93, -5.25, -5.17, post)
	for x in [-10.3, -6.7]:
		_box_b(x - 0.06, x + 0.06, 0.0, 1.0, -5.27, -5.15, post)
	var h1 := _anim(_art("tor_horse_gris"), 4, 1.2, 0.034, Vector3(-9.3, 0, -5.0))
	var h2 := _anim(_art("tor_horse_castano"), 4, 0.9, 0.034, Vector3(-7.4, 0, -5.45))
	h2.flip_h = true
	_ev("tor_trough", 0.034, Vector3(-8.3, 0, -4.2))
	_ev("tor_hay", 0.036, Vector3(-6.4, 0, -4.0))
	_ev("tor_hay", 0.036, Vector3(-6.0, 0.5, -4.1))
	_ev("tor_rack", 0.036, Vector3(6.0, 0, -4.6))
	_ev("tor_hay", 0.036, Vector3(7.6, 0, -4.2))
	_prop("barrel", 0.034, Vector3(5.0, 0, -4.4))
	var h3 := _anim(_art("tor_horse_castano"), 4, 1.0, 0.034, Vector3(9.4, 0, -5.4))
	h3.flip_h = true

## Golondrinas que cruzan el cielo de la mañana de vez en cuando (como en el mercado).
func _update_swallows(delta: float) -> void:
	_swallow_t -= delta
	if _swallow_t > 0.0:
		return
	_swallow_t = randf_range(7.0, 13.0)
	if _swallow_frames == null:
		_swallow_frames = SpriteFrames.new()
		_swallow_frames.set_animation_speed("default", 9.0)
		var tex := _tex("res://assets/props/swallow.png")
		for i in 2:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 12, 0, 12, 7)
			_swallow_frames.add_frame("default", at)
	var y := randf_range(4.6, 5.4)
	var z := randf_range(-6.0, -2.0)
	for i in randi_range(2, 4):
		var s := AnimatedSprite3D.new()
		s.sprite_frames = _swallow_frames
		s.pixel_size = 0.035
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = false
		s.flip_h = true
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(12.0 + i * randf_range(0.6, 1.2), y + randf_range(-0.3, 0.3), z)
		add_child(s)
		s.play("default")
		var tw := s.create_tween()
		tw.tween_property(s, "position", s.position + Vector3(-26.0, randf_range(-0.4, 0.8), 0), randf_range(3.4, 4.2))
		tw.tween_callback(s.queue_free)

## Las justas: cada tanto dos caballeros salen de los extremos de la liza, galopan uno hacia el otro y chocan en el
## centro (destellos, polvo y el público celebra).
func _update_joust(delta: float) -> void:
	if _riders.is_empty():
		return
	if not _joust_on:
		_joust_t -= delta
		if _joust_t <= 0.0:
			_joust_on = true
			_joust_x = 0.0
			for r in _riders:
				r["s"].visible = true
				r["dust"].emitting = true
		return
	_joust_x += delta * 7.0
	for r in _riders:
		var x: float = -26.0 + _joust_x
		if r["dir"] < 0:
			x = 26.0 - _joust_x
		r["s"].position.x = x
		r["dust"].position.x = x - r["dir"] * 0.8
	if absf(_joust_x - 26.0) < delta * 7.0:
		_clash(Vector3(0, 2.0, TOR_LIST_Z))
	if _joust_x > 52.0:
		_joust_on = false
		_joust_t = randf_range(9.0, 15.0)
		for r in _riders:
			r["s"].visible = false
			r["dust"].emitting = false

func _clash(pos: Vector3) -> void:
	if _clash_fx:
		_clash_fx.position = pos
		_clash_fx.restart()
	for a in crowd:
		if is_instance_valid(a) and randf() < 0.5:
			a.emote(["excl", "heart", "star"].pick_random(), 1.2)

# ------------------------------------------------------------------ cada cuadro

func _process(delta: float) -> void:
	_t += delta
	_apply_cam(_t)
	for fb in _flybooks:
		var b: AnimatedSprite3D = fb[0]
		var c: Vector3 = fb[1]
		var r: float = fb[2]
		var a: float = fb[3] + _t * 0.6
		b.position = c + Vector3(cos(a) * r, sin(_t * 1.7 + fb[3]) * 0.12 + sin(a * 2.0) * 0.1, sin(a) * r * 0.45)
		b.flip_h = sin(a) > 0.0
	_update_owl(delta)
	_update_chatter(delta)
	_update_cheers(delta)
	_update_joust(delta)
	if kind == "torneo":
		_update_swallows(delta)

func _update_cheers(delta: float) -> void:
	var i := _pending_cheers.size() - 1
	while i >= 0:
		var c: Dictionary = _pending_cheers[i]
		c["t"] -= delta
		if c["t"] <= 0.0:
			_pending_cheers.remove_at(i)
			var a = c["a"]
			if is_instance_valid(a) and a.is_inside_tree():
				if c["good"]:
					a.hop(2, 0.16)
					a.emote(["heart", "star", "note", "sparkle"].pick_random(), 1.6)
				else:
					a.emote(["sweat", "dots", "question"].pick_random(), 1.6)
		i -= 1

## La lechuza parpadea de vez en cuando y a veces gira la cabeza.
func _update_owl(delta: float) -> void:
	if _owl == null:
		return
	if _owl_hold > 0.0:
		_owl_hold -= delta
		if _owl_hold <= 0.0:
			_owl.frame = 0
		return
	_owl_t -= delta
	if _owl_t <= 0.0:
		_owl_t = randf_range(2.0, 5.5)
		if randf() < 0.3:
			_owl.frame = 2
			_owl_hold = randf_range(1.0, 2.2)
		else:
			_owl.frame = 1
			_owl_hold = 0.14

## El público vive: de vez en cuando alguien comenta algo (una burbuja) o da un saltito.
func _update_chatter(delta: float) -> void:
	_chatter_t -= delta
	if _chatter_t > 0.0:
		return
	_chatter_t = randf_range(2.5, 5.0)
	var all: Array = crowd + extras
	for id in fixed:
		all.append(fixed[id])
	if all.is_empty():
		return
	var a = all.pick_random()
	if is_instance_valid(a) and a.is_inside_tree():
		a.emote(_crowd_emotes.pick_random(), 1.3)
		if randf() < 0.25:
			a.hop(1, 0.1)
