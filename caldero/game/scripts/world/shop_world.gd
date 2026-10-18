extends Node3D
class_name ShopWorld
## Construye la tienda en 2.5D (geometría 3D con texturas pixel art + sprites) y controla la luz del día.

signal jar_clicked(id: String)
signal jar_hover(id: String)
signal jar_unhover(id: String)
signal cauldron_clicked
signal cat_clicked
signal book_clicked
signal customer_clicked
signal rack_clicked
# --- WORLD: estaciones. La alquimista camina hasta una estación antes de usarla.
## Usó una estación ("biblioteca", "caldero", "mostrador", "puerta"): hizo clic en ella (o pulsó E) y ya llegó.
signal station_clicked(id: String)
## Entró en el sector de una estación (caminando con teclas o cruceta, con un clic en el suelo o enviada por código).
signal station_reached(id: String)
## Salió de ese sector.
signal station_left(id: String)
# --- end WORLD

# --- R3 WORLD3: el mostrador es transversal: corre de la pared del fondo hacia delante (a lo largo de z) y parte la
# tienda en dos. A su izquierda, el lado de ella (biblioteca, caldero, estantes); a su derecha, el de los clientes
# (la puerta). Junto a la pared tiene una trampilla con bisagra: el único paso, y solo lo usa ella.
const COUNTER_X := 0.85         # eje del mostrador
const COUNTER_HW := 0.39        # medio ancho de la tabla de arriba
const COUNTER_BW := 0.32        # medio ancho del cuerpo
const COUNTER_Z0 := -4.0        # contra la pared del fondo
const COUNTER_Z1 := 3.5         # extremo delantero, casi en el borde del suelo (en el juego queda bajo la pantalla)
const FLAP_Z0 := -3.35          # la trampilla tapa el hueco entre FLAP_Z0 y FLAP_Z1 (bisagra en FLAP_Z0)
const FLAP_Z1 := -2.5
const SERVE_Z := -1.15          # ella y el cliente, frente a frente por encima del mostrador
const P_OUTSIDE := Vector3(4.0, 0, -6.2)
const P_DOOR_IN := Vector3(4.0, 0, -3.35)
const P_DOOR_FRONT := Vector3(3.3, 0, -2.35)
const P_CUSTOMER := Vector3(1.78, 0, -1.15)       # del lado de la puerta, frente al mostrador
const P_ALCH_COUNTER := Vector3(0.03, 0, -1.15)   # de su lado del mostrador
# --- end R3 WORLD3
const P_ALCH_CAULDRON := Vector3(-2.35, 0, -1.65)
const CAULDRON_POS := Vector3(-3.4, 0, -2.55)
const COUNTER_TOP := 0.9       # --- R3 WORLD3 (era 1.08): a la cintura, como los puestos del mercado
const WALL_Z := -4.0
# --- WORLD: la tienda es más ancha que la pantalla. De izquierda a derecha: biblioteca | caldero | mostrador | puerta.
const ROOM_X0 := -15.8          # pared izquierda (biblioteca)
const ROOM_X1 := 7.6            # pared derecha
const LIB_X1 := -7.6            # tabique entre la biblioteca y la sala del caldero
const DESK_POS := Vector3(-11.45, 0, -2.7)
## Carril por donde camina la alquimista: Vector2(x, z). Pasa por delante del caldero hasta su lado del mostrador;
## para ir a la puerta da un paso hacia el fondo y cruza el mostrador por la trampilla (R3 WORLD3).
const LANE := [
	Vector2(-15.0, -2.1), Vector2(-10.2, -2.2), Vector2(-8.6, -2.0), Vector2(-7.0, -1.6),
	Vector2(-2.35, -1.65), Vector2(-0.9, -1.3), Vector2(0.03, -1.15),
	Vector2(0.2, -2.92), Vector2(1.5, -2.92),
	Vector2(3.95, -2.78), Vector2(5.3, -2.65),
]
## Estaciones: x del punto donde se para, hacia dónde mira, su sector [x0, x1] y su nombre.
## --- R3 WORLD3: el mostrador se atiende desde su lado (x 0.03); el sector de la puerta empieza en la trampilla.
const STATIONS := {
	"biblioteca": {"x": -10.2, "face": -1, "zone": Vector2(-15.8, -7.6), "name": "Biblioteca · grimorio"},
	"caldero": {"x": -2.35, "face": -1, "zone": Vector2(-7.6, -1.1), "name": "Caldero"},
	"mostrador": {"x": 0.03, "face": 1, "zone": Vector2(-1.1, 0.46), "name": "Mostrador"},
	"puerta": {"x": 3.95, "face": 1, "zone": Vector2(0.46, 7.6), "name": "Puerta"},
}
const STATION_LABEL_Y := {"biblioteca": 1.75, "caldero": 1.75, "mostrador": 1.75, "puerta": 2.85}
const CAM_X0 := -10.0           # la cámara sigue a la alquimista entre estos límites
const CAM_X1 := 2.0             # --- R3 WORLD3 (era 1.3): del lado de la puerta se ve el frente del mostrador
const CAM_COUNTER_X := -0.3     # --- R3 WORLD3: de su lado, la cámara no pasa de aquí (se ve el mostrador de lado)
# --- end WORLD

var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var fill: OmniLight3D
var cauldron: Cauldron
var alchemist: Actor
var cat: AnimatedSprite3D
var cat_area: Area3D
var jars := {}            # id -> Node3D
var jar_labels := {}      # id -> Label3D
var rack_sprites: Array[Sprite3D] = []
var door_pivot: Node3D
var sky_mat: ShaderMaterial
var upgrade_nodes := {}   # id -> Array[Node3D]
var interior_lights: Array = []   # [OmniLight3D, base_energy]
var fireflies: GPUParticles3D
var dust: GPUParticles3D
var counter_potion: Sprite3D
var time_t := 0.0
var _cam_base := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _t := 0.0
var _time_tween: Tween
var _hovered := ""
var _font: Font
# --- WORLD
var walker: Walker
var can_use: Callable           # (id: String) -> bool: si ahora se puede usar esa estación (lo pone main.gd)
var station_nodes := {}         # id -> Node3D (lo que se toca)
var grimoire_sprite: Sprite3D
var _station_label: Label3D
var _station_label_text := {}   # id -> texto al pasar el cursor
var _hover_station := ""
var _cam_x := 0.0
var cam_fixed_x := INF          # si es finito, la cámara se queda en esa x (capturas de toda la tienda)
# --- end WORLD
# --- R3 WORLD3: la trampilla del mostrador
var flap_pivot: Node3D          # bisagra (gira en x: 0 = cerrada, FLAP_OPEN = levantada contra la pared)
var _flap_a := 0.0
var _flap_open := false
const FLAP_OPEN := -1.82        # radianes (~104°: queda apoyada hacia la pared, detrás de su paso)
# --- end R3 WORLD3

var _mats := {}

# ------------------------------------------------------------------ helpers

func _tex(path: String) -> Texture2D:
	return load(path)

func _mat(albedo: String, normal := "", scale := 0.5, rough := 0.92, tint := Color.WHITE) -> StandardMaterial3D:
	var key := albedo + normal + str(scale) + str(tint)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(albedo)
	m.albedo_color = tint
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal)
		m.normal_scale = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 20.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = rough
	_mats[key] = m
	return m

func _box(size: Vector3, center: Vector3, mat: Material, parent: Node3D = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi

## Caja definida por sus límites (más cómodo para paredes).
func _box_b(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	return _box(Vector3(x1 - x0, y1 - y0, z1 - z0), Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0), mat, parent)

func _sprite(path: String, px: float, pos: Vector3, parent: Node3D = null, anchor := "bottom", shaded := true) -> Sprite3D:
	var s := Sprite3D.new()
	var t := _tex(path)
	s.texture = t
	s.pixel_size = px
	s.centered = false
	if anchor == "bottom":
		s.offset = Vector2(-t.get_width() / 2.0, 0)
	elif anchor == "top":
		s.offset = Vector2(-t.get_width() / 2.0, -t.get_height())
	else:
		s.offset = Vector2(-t.get_width() / 2.0, -t.get_height() / 2.0)
	s.position = pos
	s.shaded = shaded
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	(parent if parent else self).add_child(s)
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

func _omni(pos: Vector3, color: Color, energy: float, rng: float, shadows := false, parent: Node3D = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 0.4
	(parent if parent else self).add_child(l)
	interior_lights.append([l, energy])
	return l

func _pick(parent: Node3D, size: Vector3, offset: Vector3, on_click: Callable, on_enter := Callable(), on_exit := Callable()) -> Area3D:
	var a := Area3D.new()
	a.monitoring = false
	a.monitorable = false
	a.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	a.add_child(cs)
	a.input_event.connect(func(_cam, ev, _p, _n, _i):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	if on_enter.is_valid():
		a.mouse_entered.connect(on_enter)
	if on_exit.is_valid():
		a.mouse_exited.connect(on_exit)
	parent.add_child(a)
	return a

# --- R3 WORLD3: madera con la veta a lo largo de z (el mostrador corre hacia el fondo)
## Como _mat(), pero la proyección triplanar es en el espacio del objeto: sigue el giro de la caja (_zbox).
func _mat_obj(albedo: String, normal := "", scale := 1.0, rough := 0.8, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "obj:" + albedo + normal + str(scale) + str(tint)
	if _mats.has(key):
		return _mats[key]
	var m := _mat(albedo, normal, scale, rough, tint).duplicate()
	m.uv1_world_triplanar = false
	_mats[key] = m
	return m

## Caja por sus límites, girada 90° en y: su veta (x local) queda a lo largo de z.
func _zbox(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(z1 - z0, y1 - y0, x1 - x0)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	mi.rotation_degrees = Vector3(0, 90, 0)
	(parent if parent else self).add_child(mi)
	return mi

## Un panel con textura (cuadro plano) que mira hacia `normal` (+x, -x o +z); u = a lo largo, v = alto.
func _panel(tex: String, normal_tex: String, size: Vector2, center: Vector3, facing: Vector3, uv_scale: Vector2) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex)
	if normal_tex != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal_tex)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.8
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	var q := _quad(size, center, m)
	if facing.x > 0.5:
		q.rotation_degrees = Vector3(0, 90, 0)
	elif facing.x < -0.5:
		q.rotation_degrees = Vector3(0, -90, 0)
	return q
# --- end R3 WORLD3

func _register_upgrade(id: String, node: Node3D) -> void:
	if not upgrade_nodes.has(id):
		upgrade_nodes[id] = []
	upgrade_nodes[id].append(node)
	node.visible = false

# ------------------------------------------------------------------ construcción

func build() -> void:
	_font = load("res://assets/fonts/Alegreya-Bold.ttf")
	_build_camera_and_env()
	_build_room()
	_build_outside()
	_build_shelves()
	_build_counter()
	_build_cauldron()
	_build_decor()
	_build_library()   # --- WORLD
	_build_characters()
	_build_stations()   # --- WORLD
	_build_walker()     # --- WORLD
	_build_particles()
	refresh_jars()
	refresh_rack()
	refresh_upgrades()
	set_time(0.0, false)

func _build_camera_and_env() -> void:
	camera = Camera3D.new()
	camera.fov = 35.0
	camera.near = 0.1
	camera.far = 80.0
	_cam_base = Vector3(0.0, 3.9, 8.7)      # --- WORLD: la x la pone _cam_x (sigue a la alquimista)
	_cam_target = Vector3(0.0, 1.3, -2.0)
	camera.position = _cam_base
	add_child(camera)
	camera.look_at(_cam_target, Vector3.UP)
	camera.current = true
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 15.0
	ca.dof_blur_far_transition = 5.0
	ca.dof_blur_near_enabled = true
	ca.dof_blur_near_distance = 7.4
	ca.dof_blur_near_transition = 2.0
	ca.dof_blur_amount = 0.09
	camera.attributes = ca

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.015, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.65)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(1.0, 0.96, 0.92)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 22.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 3.0
	sun.shadow_blur = 1.0
	add_child(sun)

	fill = OmniLight3D.new()
	fill.position = Vector3(0.5, 3.4, 4.0)
	fill.omni_range = 14.0
	fill.omni_attenuation = 0.7
	fill.light_color = Color(1.0, 0.86, 0.72)
	fill.light_energy = 0.4
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)

func _build_room() -> void:
	var floor_m := _mat("res://assets/tex/floor.png", "res://assets/tex/floor_n.png", 0.5, 0.85)
	var plaster := _mat("res://assets/tex/plaster.png", "res://assets/tex/plaster_n.png", 0.25, 0.95)
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.5, 0.9)
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	# suelo
	_box_b(LIB_X1, 7.6, -0.2, 0.0, -4.3, 3.6, floor_m)   # --- WORLD: la biblioteca tiene su propio suelo
	# pared trasera con hueco para ventana (x 0.5..2.5, y 1.4..3.1) y puerta (x 3.3..4.7, y 0..2.5)
	var z0 := -4.3
	var z1 := WALL_Z
	var H := 5.8
	var pieces := [
		[-7.6, 0.5, 0.0, H], [0.5, 2.5, 0.0, 1.4], [0.5, 2.5, 3.1, H], [2.5, 3.3, 0.0, H],
		[3.3, 4.7, 2.5, H], [4.7, 7.6, 0.0, H],
	]
	for p in pieces:
		var ya: float = p[2]
		var yb: float = p[3]
		if ya < 1.0:
			_box_b(p[0], p[1], ya, minf(yb, 1.0), z0, z1 + 0.04, stone)
		if yb > 1.0:
			_box_b(p[0], p[1], maxf(ya, 1.0), yb, z0, z1, plaster)
	# techo (no se ve, pero bloquea el sol y la niebla de arriba)
	var ceil_m := StandardMaterial3D.new()
	ceil_m.albedo_color = Color(0.1, 0.08, 0.1)
	_box_b(ROOM_X0 - 0.6, 8.2, H, H + 0.3, -4.6, 14.0, ceil_m)
	# paredes laterales
	# --- WORLD: donde estaba la pared izquierda queda un tabique corto: detrás, la biblioteca
	_box_b(-7.9, -7.6, 0.0, H, -4.3, -3.05, plaster)
	_box_b(-7.92, -7.58, 0.0, 1.0, -4.3, -3.05, stone)
	_box_b(7.6, 7.9, 0.0, H, -4.3, 3.6, plaster)
	_box_b(7.6, 7.88, 0.0, 1.0, -4.3, 3.6, stone)
	# vigas y postes
	_box_b(-7.6, 3.25, 1.0, 1.14, z1, z1 + 0.09, wood_d)
	_box_b(4.75, 7.6, 1.0, 1.14, z1, z1 + 0.09, wood_d)
	_box_b(ROOM_X0, 7.6, 4.55, 4.8, z1, z1 + 0.14, wood_d)
	for x in [-7.35, -2.45, 2.9, 7.35]:
		_box_b(x - 0.12, x + 0.12, 1.14, 4.55, z1, z1 + 0.12, wood_d)
	# viga delantera (queda desenfocada en primer plano)
	_box_b(ROOM_X0 - 0.2, 8.0, 4.1, 4.36, 2.4, 2.7, wood_d)
	# marco de la ventana
	_box_b(0.38, 2.62, 1.3, 1.42, z1 - 0.05, z1 + 0.26, wood_d)   # alféizar
	_box_b(0.38, 2.62, 3.1, 3.22, z1 - 0.05, z1 + 0.1, wood_d)
	_box_b(0.38, 0.5, 1.4, 3.1, z1 - 0.05, z1 + 0.1, wood_d)
	_box_b(2.5, 2.62, 1.4, 3.1, z1 - 0.05, z1 + 0.1, wood_d)
	_box_b(1.47, 1.53, 1.4, 3.1, -4.2, -4.1, wood_d)
	_box_b(0.5, 2.5, 2.22, 2.28, -4.2, -4.1, wood_d)
	var glass := StandardMaterial3D.new()
	glass.albedo_texture = _tex("res://assets/tex/glass.png")
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.uv1_scale = Vector3(2, 2, 1)
	var g := _quad(Vector2(2.0, 1.7), Vector3(1.5, 2.25, -4.15), glass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# marco de la puerta
	_box_b(3.18, 3.3, 0.0, 2.62, z1 - 0.03, z1 + 0.1, wood_d)
	_box_b(4.7, 4.82, 0.0, 2.62, z1 - 0.03, z1 + 0.1, wood_d)
	_box_b(3.18, 4.82, 2.5, 2.62, z1 - 0.03, z1 + 0.1, wood_d)
	# puerta con bisagra
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(3.31, 0, -4.12)
	add_child(door_pivot)
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = _tex("res://assets/tex/door.png")
	dm.normal_enabled = true
	dm.normal_texture = _tex("res://assets/tex/door_n.png")
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var door := _quad(Vector2(1.38, 2.48), Vector3(0.69, 1.24, 0.0), dm, door_pivot)
	door.name = "Door"
	# farol junto a la puerta
	var lantern := _sprite("res://assets/props/lantern.png", 0.04, Vector3(5.15, 2.05, -3.9))
	lantern.shaded = false
	lantern.modulate = Color(1.3, 1.2, 1.0)
	_omni(Vector3(5.15, 2.3, -3.5), Color(1.0, 0.75, 0.45), 0.9, 4.5)
	# tablón de anuncios, mapa, reloj y letrero
	_sprite("res://assets/props/notice.png", 0.045, Vector3(6.1, 1.5, -3.92))
	_sprite("res://assets/props/map.png", 0.04, Vector3(-1.0, 2.75, -3.94))
	_sprite("res://assets/props/clock.png", 0.04, Vector3(4.0, 3.0, -3.93))
	_sprite("res://assets/props/sign.png", 0.042, Vector3(1.5, 3.32, -3.9))

func _build_outside() -> void:
	var sh := ShaderMaterial.new()
	sh.shader = load("res://shaders/sky.gdshader")
	sh.set_shader_parameter("hills", _tex("res://assets/tex/backdrop.png"))
	sky_mat = sh
	# --- WORLD: más ancho, para que también se vea por el ventanal de la biblioteca
	sh.set_shader_parameter("hills_repeat", 3.4)
	sh.set_shader_parameter("aspect", 50.0 / 14.0)
	var q := _quad(Vector2(50, 14), Vector3(-5.0, 4.0, -10.0), sh)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var grass := _mat("res://assets/tex/cobble.png", "", 0.5, 1.0, Color(0.85, 0.9, 0.8))
	_box_b(-30.0, 20.0, -0.25, -0.02, -10.0, -4.3, grass)

func _build_shelves() -> void:
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var xa := -6.3
	var xb := -2.7
	var boards := [1.15, 1.95, 2.75]
	for y in boards:
		_box_b(xa, xb, y - 0.07, y, -3.98, -3.5, wood)
	_box_b(xa - 0.08, xa, 0.95, 3.25, -3.98, -3.48, wood)
	_box_b(xb, xb + 0.08, 0.95, 3.25, -3.98, -3.48, wood)
	_box_b(xa - 0.1, xb + 0.1, 3.25, 3.33, -4.0, -3.45, wood)
	# frascos: 4 por fila en las dos primeras repisas
	var xs := [-5.8, -4.95, -4.1, -3.25]
	for i in Data.INGREDIENT_ORDER.size():
		var id: String = Data.INGREDIENT_ORDER[i]
		var row := i / 4
		var col := i % 4
		var holder := Node3D.new()
		holder.position = Vector3(xs[col], boards[row], -3.72)
		add_child(holder)
		var s := _sprite("res://assets/props/jar_%s.png" % id, 0.03, Vector3.ZERO, holder)
		s.name = "Jar"
		var lbl := Label3D.new()
		lbl.font = _font
		lbl.font_size = 40
		lbl.pixel_size = 0.0045
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0.12, 0.07, 0.1)
		lbl.modulate = Color(1.0, 0.95, 0.8)
		lbl.position = Vector3(0.2, 0.06, 0.12)
		lbl.text = "0"
		lbl.no_depth_test = false
		lbl.shaded = false
		lbl.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		holder.add_child(lbl)
		jar_labels[id] = lbl
		jars[id] = holder
		_pick(holder, Vector3(0.6, 0.72, 0.4), Vector3(0, 0.36, 0),
			func(): jar_clicked.emit(id),
			func(): _hover_jar(id, true),
			func(): _hover_jar(id, false))
	# decoración en la repisa superior
	_sprite("res://assets/props/books.png", 0.035, Vector3(-5.75, 2.75, -3.75))
	_sprite("res://assets/props/crystal_ball.png", 0.035, Vector3(-4.85, 2.75, -3.75))
	_sprite("res://assets/props/scrolls.png", 0.035, Vector3(-4.05, 2.75, -3.75))
	_sprite("res://assets/props/bottle_sm_2.png", 0.035, Vector3(-3.45, 2.75, -3.75))
	_sprite("res://assets/props/bottle_sm_0.png", 0.035, Vector3(-3.15, 2.75, -3.75))
	_sprite("res://assets/props/herbs.png", 0.035, Vector3(-4.5, 3.25, -3.62), null, "top")
	_sprite("res://assets/props/lavender.png", 0.035, Vector3(-5.6, 3.25, -3.62), null, "top")

	# repisas de pociones (inventario visible), detrás del mostrador
	var rack_boards := [1.6, 2.25]
	for r in 2:
		var y: float = rack_boards[r]
		var board := _box_b(-2.2, 0.2, y - 0.06, y, -3.98, -3.66, wood)
		var brackets := [_box_b(-2.05, -1.97, y - 0.26, y - 0.06, -3.98, -3.75, wood), _box_b(0.0, 0.08, y - 0.26, y - 0.06, -3.98, -3.75, wood)]
		if r == 1:
			_register_upgrade("estante", board)
			for b in brackets:
				_register_upgrade("estante", b)
		for c in 6:
			var s := _sprite("res://assets/icons/pot_elixir_alba.png", 0.03, Vector3(-1.95 + c * 0.39, y, -3.8))
			s.visible = false
			rack_sprites.append(s)
	var rack_holder := Node3D.new()
	add_child(rack_holder)
	_pick(rack_holder, Vector3(2.5, 1.4, 0.4), Vector3(-1.0, 1.9, -3.8), func(): rack_clicked.emit())

func _hover_jar(id: String, on: bool) -> void:
	var holder: Node3D = jars[id]
	var s: Sprite3D = holder.get_node("Jar")
	var tw := create_tween()
	if on:
		_hovered = id
		tw.tween_property(s, "position:y", 0.06, 0.08)
		s.modulate = Color(1.35, 1.3, 1.2)
		jar_hover.emit(id)
	else:
		if _hovered == id:
			_hovered = ""
		tw.tween_property(s, "position:y", 0.0, 0.1)
		s.modulate = Color.WHITE if Game.stock.get(id, 0) > 0 else Color(0.55, 0.5, 0.6)
		jar_unhover.emit(id)

func bump_jar(id: String) -> void:
	var s: Sprite3D = jars[id].get_node("Jar")
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector3(1.15, 0.85, 1), 0.06)
	tw.tween_property(s, "scale", Vector3(0.95, 1.1, 1), 0.08)
	tw.tween_property(s, "scale", Vector3.ONE, 0.08)

func shake_jar(id: String) -> void:
	var s: Sprite3D = jars[id].get_node("Jar")
	var tw := create_tween()
	for i in 3:
		tw.tween_property(s, "position:x", 0.04, 0.04)
		tw.tween_property(s, "position:x", -0.04, 0.04)
	tw.tween_property(s, "position:x", 0.0, 0.04)

func refresh_jars() -> void:
	for id in jars:
		var holder: Node3D = jars[id]
		var unlocked := Game.ingredient_unlocked(id)
		holder.visible = unlocked
		var n: int = Game.stock.get(id, 0)
		jar_labels[id].text = str(n)
		jar_labels[id].modulate = Color(1.0, 0.95, 0.8) if n > 0 else Color(1.0, 0.5, 0.45)
		if _hovered != id:
			holder.get_node("Jar").modulate = Color.WHITE if n > 0 else Color(0.55, 0.5, 0.6)

func refresh_rack() -> void:
	for i in rack_sprites.size():
		var s := rack_sprites[i]
		if i < Game.potions.size():
			s.texture = _tex("res://assets/icons/pot_%s.png" % Game.potions[i]["id"])
			s.visible = true
		else:
			s.visible = false

func rack_slot_position(index: int) -> Vector3:
	index = clampi(index, 0, rack_sprites.size() - 1)
	return rack_sprites[index].global_position + Vector3(0, 0.25, 0)

func _build_counter() -> void:
	# --- R3 WORLD3: el mostrador transversal. Corre de la pared del fondo (COUNTER_Z0) hasta delante (COUNTER_Z1, bajo
	# el borde de la pantalla) y parte la tienda: a la izquierda trabaja ella, a la derecha esperan los clientes. Junto
	# a la pared, un poste corto sostiene la bisagra de la trampilla (FLAP_Z0..FLAP_Z1): por ahí pasa ella. Vista desde
	# la cámara: la tabla clara con canto, el costado de su lado (cajones y puertas), el frente de paneles del lado de
	# los clientes y, encima, la campanilla, el libro de cuentas, el recetario, unos frascos, el mortero y la vela.
	var wood_d := _mat_obj("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var wood_l := _mat_obj("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.55, Color(0.86, 0.8, 0.74))
	var cx := COUNTER_X
	var hw := COUNTER_HW
	var bw := COUNTER_BW
	var top := COUNTER_TOP
	# poste del fondo, contra la pared (la bisagra de la trampilla apoya en su canto)
	_zbox(cx - bw, cx + bw, 0.0, top - 0.08, COUNTER_Z0, FLAP_Z0, wood_d)
	_zbox(cx - hw, cx + hw, top - 0.08, top, COUNTER_Z0 + 0.02, FLAP_Z0, wood_l)
	# el cuerpo largo y su tabla (con un poco de vuelo delante y a los lados)
	_zbox(cx - bw, cx + bw, 0.0, top - 0.08, FLAP_Z1, COUNTER_Z1, wood_d)
	_zbox(cx - hw, cx + hw, top - 0.08, top, FLAP_Z1, COUNTER_Z1 + 0.07, wood_l)
	# moldura oscura bajo el canto de la tabla, a los dos lados (separa la tabla del cuerpo)
	for sx in [-1.0, 1.0]:
		var xa: float = cx + sx * bw
		var xb: float = cx + sx * (bw + 0.035)
		_zbox(minf(xa, xb), maxf(xa, xb), top - 0.13, top - 0.08, FLAP_Z1 + 0.02, COUNTER_Z1, wood_d)
	# zócalo oscuro
	_zbox(cx - bw - 0.02, cx + bw + 0.02, 0.0, 0.07, FLAP_Z1 + 0.02, COUNTER_Z1 + 0.02, wood_d)
	_zbox(cx - bw - 0.02, cx + bw + 0.02, 0.0, 0.07, COUNTER_Z0, FLAP_Z0 - 0.01, wood_d)
	# costados: paneles del lado de los clientes, cajones y puertas del lado de ella, y el frente del extremo
	var body_len := COUNTER_Z1 - FLAP_Z1
	var zc := (COUNTER_Z1 + FLAP_Z1) / 2.0
	var ph := top - 0.2                      # alto de los paneles (entre el zócalo y la moldura)
	var py := 0.07 + ph / 2.0
	_panel("res://assets/tex/counter_front.png", "res://assets/tex/counter_front_n.png", Vector2(body_len - 0.04, ph),
		Vector3(cx + bw + 0.004, py, zc), Vector3.RIGHT, Vector2(body_len / 2.0, 1.0))
	_panel("res://assets/tex/counter_side.png", "", Vector2(body_len - 0.04, ph),
		Vector3(cx - bw - 0.004, py, zc), Vector3.LEFT, Vector2(body_len / 2.0, 1.0))
	_panel("res://assets/tex/counter_front.png", "res://assets/tex/counter_front_n.png", Vector2(2.0 * bw, ph),
		Vector3(cx, py, COUNTER_Z1 + 0.004), Vector3.BACK, Vector2(0.5, 1.0))
	var post_len := FLAP_Z0 - COUNTER_Z0
	_panel("res://assets/tex/counter_side.png", "", Vector2(post_len - 0.04, ph),
		Vector3(cx - bw - 0.004, py, (COUNTER_Z0 + FLAP_Z0) / 2.0), Vector3.LEFT, Vector2(post_len / 2.0, 1.0))
	_panel("res://assets/tex/counter_front.png", "res://assets/tex/counter_front_n.png", Vector2(post_len - 0.04, ph),
		Vector3(cx + bw + 0.004, py, (COUNTER_Z0 + FLAP_Z0) / 2.0), Vector3.RIGHT, Vector2(post_len / 2.0, 1.0))
	# la trampilla: una tabla con bisagras de hierro y una argolla de latón; se levanta hacia la pared cuando ella pasa
	flap_pivot = Node3D.new()
	flap_pivot.name = "Flap"
	flap_pivot.position = Vector3(cx, top, FLAP_Z0)
	add_child(flap_pivot)
	var flap_len := FLAP_Z1 - FLAP_Z0
	_zbox(-hw, hw, -0.08, 0.0, 0.012, flap_len - 0.008, wood_l, flap_pivot)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.17, 0.15, 0.16)
	iron.metallic = 0.6
	iron.roughness = 0.45
	for hx in [-0.24, 0.24]:
		_box(Vector3(0.07, 0.014, 0.2), Vector3(hx, 0.007, 0.08), iron, flap_pivot)        # bisagra (arriba)
		_box(Vector3(0.06, 0.012, 0.62), Vector3(hx, -0.086, 0.34), iron, flap_pivot)      # cincho de hierro (abajo: se ve al levantarla)
		_box(Vector3(0.09, 0.03, 0.03), Vector3(hx, 0.0, 0.0), iron, flap_pivot)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.32)
	brass.metallic = 0.75
	brass.roughness = 0.3
	_box(Vector3(0.12, 0.016, 0.035), Vector3(0.0, 0.008, flap_len - 0.1), brass, flap_pivot)
	# encima. El tramo entre el sitio de atender y la trampilla queda despejado (desde la cámara, lo que hay ahí tapa a
	# la alquimista cuando cruza). En el poste del fondo, unos frascos; a la altura de los dos, el sitio de la poción que
	# entrega (counter_potion) y la campanilla del lado de los clientes; más adelante, el libro de cuentas, el
	# recetario, la vela y el mortero (lo de más al fondo se ve más arriba).
	for b in [[-0.22, "bottle_sm_1", -3.78], [-0.08, "bottle_sm_3", -3.86], [0.05, "bottle_sm_5", -3.76]]:
		_sprite("res://assets/props/%s.png" % b[1], 0.034, Vector3(cx + b[0], top, b[2]))
	var cbell := _sprite("res://assets/props/counter_bell.png", 0.036, Vector3(cx + 0.21, top, -1.02))
	cbell.name = "CounterBell"
	_sprite("res://assets/props/ledger.png", 0.024, Vector3(cx - 0.12, top, -0.45))
	# libro de recetas abierto
	var book := _sprite("res://assets/props/open_book.png", 0.022, Vector3(cx + 0.06, top, 0.3))
	_pick(book, Vector3(0.5, 0.3, 0.35), Vector3(0, 0.13, 0), func(): book_clicked.emit())
	_sprite("res://assets/props/mortar.png", 0.028, Vector3(cx + 0.17, top, 1.0))
	# vela
	var candle := _sprite("res://assets/props/candle.png", 0.035, Vector3(cx - 0.2, top, 0.9))
	# --- end R3 WORLD3
	var fl := AnimatedSprite3D.new()
	var sf := SpriteFrames.new()
	var ft := _tex("res://assets/props/flame.png")
	sf.set_animation_speed("default", 8.0)
	for i in 3:
		var at := AtlasTexture.new()
		at.atlas = ft
		at.region = Rect2(i * 5, 0, 5, 6)
		sf.add_frame("default", at)
	fl.sprite_frames = sf
	fl.pixel_size = 0.035
	fl.centered = false
	fl.offset = Vector2(-2.5, 0)
	fl.position = Vector3(0, 8 * 0.035, 0.01)
	fl.shaded = false
	fl.modulate = Color(2.0, 1.7, 1.2)
	fl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fl.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	candle.add_child(fl)
	fl.play("default")
	# --- R3 WORLD3: la vela, la lámpara colgante y la poción entregada, en el mostrador nuevo
	_omni(candle.position + Vector3(0.0, 0.5, 0.3), Color(1.0, 0.72, 0.42), 0.9, 3.2)
	# lámpara colgante sobre el mostrador, entre ella y el cliente: los ilumina a los dos
	var lx := COUNTER_X + 0.05
	var lamp := _sprite("res://assets/props/lantern.png", 0.045, Vector3(lx, 3.15, SERVE_Z), null, "top")
	lamp.shaded = false
	lamp.modulate = Color(1.4, 1.25, 1.0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cord := _box_b(lx - 0.015, lx + 0.015, 3.15, 5.8, SERVE_Z - 0.02, SERVE_Z + 0.02, _mat("res://assets/tex/wood_dark.png", "", 1.0))
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ll := _omni(Vector3(COUNTER_X + 0.75, 2.35, SERVE_Z + 0.55), Color(1.0, 0.76, 0.48), 1.3, 4.5, true)
	ll.light_volumetric_fog_energy = 0.3
	# poción entregada: aparece sobre el mostrador, entre los dos
	counter_potion = _sprite("res://assets/icons/pot_elixir_alba.png", 0.03, Vector3(COUNTER_X, COUNTER_TOP, SERVE_Z))
	counter_potion.visible = false
	# --- end R3 WORLD3
	# área del cliente
	var cust_area := Node3D.new()
	add_child(cust_area)
	_pick(cust_area, Vector3(0.9, 1.8, 0.6), P_CUSTOMER + Vector3(0, 0.9, 0), func(): _station_press("mostrador"))   # --- WORLD
	# campanilla (mejora) sobre la puerta
	var bell := _sprite("res://assets/props/bell.png", 0.035, Vector3(4.0, 2.62, -3.92), null, "bottom")
	_register_upgrade("campanilla", bell)

func _build_cauldron() -> void:
	cauldron = Cauldron.new()
	cauldron.position = CAULDRON_POS
	add_child(cauldron)
	cauldron.build()
	# --- WORLD: el caldero es una estación (camina hasta él y luego se usa)
	_pick(cauldron, Vector3(1.5, 1.3, 0.8), Vector3(0, 0.6, 0), func(): _station_press("caldero"),
		func(): _station_hover("caldero", true), func(): _station_hover("caldero", false))

func _build_decor() -> void:
	# barriles y cajas junto a la puerta
	_sprite("res://assets/props/barrel.png", 0.04, Vector3(5.7, 0, -3.55))
	_sprite("res://assets/props/crate.png", 0.04, Vector3(6.6, 0, -3.3))
	_sprite("res://assets/props/crate.png", 0.04, Vector3(6.55, 0.52, -3.35))
	_sprite("res://assets/props/sack.png", 0.04, Vector3(5.15, 0, -3.1))
	# plantas a los lados
	_sprite("res://assets/props/fern.png", 0.05, Vector3(-5.7, 0, 0.2))
	_sprite("res://assets/props/fern.png", 0.05, Vector3(6.0, 0, -0.3))
	_sprite("res://assets/props/barrel.png", 0.04, Vector3(-6.6, 0, -1.2))
	_sprite("res://assets/props/sack.png", 0.04, Vector3(-6.0, 0, -0.9))
	# hierbas colgando de la viga delantera
	for p in [[-4.3, "herbs"], [-1.9, "lavender"], [2.6, "herbs"], [4.6, "lavender"]]:
		var s := _sprite("res://assets/props/%s.png" % p[1], 0.04, Vector3(p[0], 4.1, 2.55), null, "top")
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# alfombra (mejora)
	var rug_m := StandardMaterial3D.new()
	rug_m.albedo_texture = _tex("res://assets/tex/rug.png")
	rug_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	rug_m.roughness = 1.0
	var rug := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.4, 3.2)
	rug.mesh = pm
	rug.material_override = rug_m
	rug.position = Vector3(3.15, 0.012, -0.9)   # --- R3 WORLD3: del lado de los clientes (antes bajo el mostrador)
	rug.rotation_degrees = Vector3(0, 90, 0)
	add_child(rug)
	_register_upgrade("alfombra", rug)
	# huerto en la ventana (mejora)
	var garden := Node3D.new()
	add_child(garden)
	for p in [[0.85, "pot_red"], [1.5, "pot_yellow"], [2.15, "pot_blue"]]:
		_sprite("res://assets/props/%s.png" % p[1], 0.04, Vector3(p[0], 1.42, -3.9), garden)
	_register_upgrade("huerto", garden)
	# farolillos de luciérnaga (mejora)
	var lamps := Node3D.new()
	add_child(lamps)
	for p in [Vector3(COUNTER_X + 0.21, COUNTER_TOP, -3.8), Vector3(-2.6, 3.33, -3.7), Vector3(2.75, 1.42, -3.85)]:   # --- R3 WORLD3
		var j := _sprite("res://assets/props/firefly_jar.png", 0.04, p, lamps)
		j.shaded = false
		j.modulate = Color(1.4, 1.5, 1.1)
		var l := _omni(p + Vector3(0, 0.3, 0.3), Color(0.8, 1.0, 0.55), 0.7, 3.0, false, lamps)
		l.light_volumetric_fog_energy = 0.8
	_register_upgrade("farolillos", lamps)

func _build_characters() -> void:
	alchemist = Actor.new()
	add_child(alchemist)
	alchemist.setup("alquimista", 0.04)
	alchemist.position = P_ALCH_COUNTER
	alchemist.face(1)
	# gata Miga
	var cushion := _sprite("res://assets/props/cushion.png", 0.035, Vector3(-4.55, 0, -2.05))
	_register_upgrade("cojin", cushion)
	cat = AnimatedSprite3D.new()
	var sf := SpriteFrames.new()
	var ct := _tex("res://assets/props/cat.png")
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for anim in [["sleep", [0, 1], 1.2], ["sit", [2, 3], 1.5], ["happy", [4, 2], 3.0]]:
		sf.add_animation(anim[0])
		sf.set_animation_speed(anim[0], anim[2])
		for fi in anim[1]:
			var at := AtlasTexture.new()
			at.atlas = ct
			at.region = Rect2(fi * 48, 0, 48, 40)
			sf.add_frame(anim[0], at)
	cat.sprite_frames = sf
	cat.pixel_size = 0.0175
	cat.centered = false
	cat.offset = Vector2(-24, 0)
	cat.position = Vector3(-4.55, 0.0, -2.0)
	cat.shaded = true
	cat.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	cat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(cat)
	cat.play("sleep")
	cat_area = _pick(cat, Vector3(0.9, 0.7, 0.6), Vector3(0, 0.3, 0), func(): cat_clicked.emit())

func set_cat_on_cushion(on: bool) -> void:
	cat.position.y = 0.21 if on else 0.0

func _build_particles() -> void:
	# polvo flotando en el rayo de luz de la ventana
	dust = GPUParticles3D.new()
	dust.amount = 45
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.6, 1.4, 1.6)
	pm.direction = Vector3(0.2, 0.3, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, 0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.turbulence_noise_speed_random = 0.2
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.color = Color(1.0, 0.95, 0.85, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	dust.process_material = pm
	var dq := _particle_quad("res://assets/fx/dust.png", 0.022)
	var dmat: StandardMaterial3D = dq.material
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.albedo_color = Color(1.2, 1.1, 1.0)
	dust.draw_pass_1 = dq
	dust.position = Vector3(2.4, 1.6, -2.2)
	dust.visibility_aabb = AABB(Vector3(-4, -3, -3), Vector3(8, 6, 6))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	# luciérnagas (mejora)
	fireflies = GPUParticles3D.new()
	fireflies.amount = 14
	fireflies.lifetime = 7.0
	fireflies.preprocess = 7.0
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(6.0, 1.4, 2.2)
	fm.spread = 180.0
	fm.initial_velocity_min = 0.05
	fm.initial_velocity_max = 0.15
	fm.gravity = Vector3.ZERO
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 0.6
	fm.turbulence_influence_min = 0.05
	fm.turbulence_influence_max = 0.12
	fm.color = Color(1.3, 1.6, 0.6)
	fm.color_ramp = gt
	fireflies.process_material = fm
	fireflies.draw_pass_1 = _particle_quad("res://assets/fx/firefly.png", 0.016)
	fireflies.position = Vector3(0.0, 2.3, -2.0)
	fireflies.visibility_aabb = AABB(Vector3(-8, -3, -4), Vector3(16, 6, 8))
	fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fireflies)
	_register_upgrade("farolillos", fireflies)

func _particle_quad(tex: String, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	var t := _tex(tex)
	q.size = Vector2(t.get_width(), t.get_height()) * size
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	return q

func refresh_upgrades() -> void:
	for id in upgrade_nodes:
		for n in upgrade_nodes[id]:
			n.visible = Game.has_upgrade(id)
	cauldron.set_copper(Game.has_upgrade("caldero_cobre"))
	set_cat_on_cushion(Game.has_upgrade("cojin"))

func reveal_upgrade(id: String) -> void:
	refresh_upgrades()
	if upgrade_nodes.has(id):
		for n in upgrade_nodes[id]:
			if n is Node3D and not (n is GPUParticles3D) and not (n is OmniLight3D):
				var base: Vector3 = n.scale
				n.scale = base * 0.2
				var tw := create_tween()
				tw.tween_property(n, "scale", base * 1.12, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(n, "scale", base, 0.12)
				spawn_sparkles(n.global_position + Vector3(0, 0.3, 0.1), Color(1.6, 1.5, 1.0))

# ------------------------------------------------------------------ efectos

func spawn_sparkles(pos: Vector3, color: Color, amount := 16) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.85
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -0.8, 0)
	pm.color = color
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _particle_quad("res://assets/fx/sparkle.png", 0.04)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

func spawn_hearts(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.05, 0)
	pm.color = Color(1.3, 1.1, 1.1)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.7, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _particle_quad("res://assets/fx/heart.png", 0.04)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)

## Hace volar un sprite en arco entre dos puntos del mundo.
func fly(tex: Texture2D, from: Vector3, to: Vector3, duration := 0.5, arc := 0.8, px := 0.035) -> void:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = 5
	add_child(s)
	s.global_position = from
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := from.lerp(to, t)
		p.y += sin(t * PI) * arc
		s.global_position = p
		s.rotation.z = t * TAU * 0.5, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE)
	await tw.finished
	s.queue_free()

func screen_pos(p: Vector3) -> Vector2:
	return camera.unproject_position(p)

func open_door() -> void:
	Sfx.play("door", 0.05, -4.0)
	if Game.has_upgrade("campanilla"):
		Sfx.play("doorbell", 0.03, -6.0)
		var bell: Node3D = upgrade_nodes["campanilla"][0]
		var tb := create_tween()
		for i in 3:
			tb.tween_property(bell, "rotation:z", 0.3, 0.07)
			tb.tween_property(bell, "rotation:z", -0.3, 0.07)
		tb.tween_property(bell, "rotation:z", 0.0, 0.07)
	var tw := create_tween()
	tw.tween_property(door_pivot, "rotation:y", deg_to_rad(-105.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func close_door() -> void:
	var tw := create_tween()
	tw.tween_property(door_pivot, "rotation:y", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

# ------------------------------------------------------------------ hora del día

const TOD := [
	# t, sol (color, energía, pitch, yaw), ambiente (color, energía), cielo arriba, cielo abajo, colinas, estrellas, luna, luces interiores, niebla
	{"t": 0.0, "sun": Color(1.0, 0.94, 0.82), "sun_e": 3.2, "pitch": -36.0, "yaw": -160.0, "amb": Color(0.55, 0.6, 0.78), "amb_e": 0.38,
		"top": Color(0.42, 0.66, 0.98), "bot": Color(0.98, 0.9, 0.76), "hills": Color(0.9, 0.95, 1.05), "stars": 0.0, "moon": 0.0, "lights": 0.5, "fog": Color(1.0, 0.95, 0.88)},
	{"t": 0.35, "sun": Color(1.0, 0.82, 0.58), "sun_e": 3.6, "pitch": -32.0, "yaw": -152.0, "amb": Color(0.58, 0.54, 0.62), "amb_e": 0.34,
		"top": Color(0.36, 0.56, 0.92), "bot": Color(1.0, 0.8, 0.56), "hills": Color(0.95, 0.9, 0.9), "stars": 0.0, "moon": 0.0, "lights": 0.7, "fog": Color(1.0, 0.88, 0.72)},
	{"t": 0.7, "sun": Color(1.0, 0.5, 0.36), "sun_e": 3.0, "pitch": -24.0, "yaw": -146.0, "amb": Color(0.46, 0.38, 0.58), "amb_e": 0.32,
		"top": Color(0.24, 0.2, 0.46), "bot": Color(1.0, 0.52, 0.38), "hills": Color(0.55, 0.42, 0.6), "stars": 0.25, "moon": 0.0, "lights": 1.0, "fog": Color(1.0, 0.7, 0.6)},
	{"t": 1.0, "sun": Color(0.52, 0.62, 1.0), "sun_e": 1.6, "pitch": -38.0, "yaw": -155.0, "amb": Color(0.26, 0.3, 0.55), "amb_e": 0.34,
		"top": Color(0.03, 0.04, 0.13), "bot": Color(0.1, 0.13, 0.3), "hills": Color(0.26, 0.3, 0.48), "stars": 1.0, "moon": 1.0, "lights": 1.3, "fog": Color(0.7, 0.78, 1.0)},
]

func _tod_sample(t: float) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	for i in TOD.size() - 1:
		var a: Dictionary = TOD[i]
		var b: Dictionary = TOD[i + 1]
		if t <= b["t"]:
			var k: float = (t - a["t"]) / maxf(0.0001, b["t"] - a["t"])
			var out := {}
			for key in a:
				if a[key] is Color:
					out[key] = a[key].lerp(b[key], k)
				elif a[key] is float:
					out[key] = lerpf(a[key], b[key], k)
			return out
	return TOD[TOD.size() - 1]

func _apply_time(t: float) -> void:
	time_t = t
	var s := _tod_sample(t)
	sun.light_color = s["sun"]
	sun.light_energy = s["sun_e"]
	sun.rotation_degrees = Vector3(s["pitch"], s["yaw"], 0.0)
	env.ambient_light_color = s["amb"]
	env.ambient_light_energy = s["amb_e"]
	env.volumetric_fog_albedo = s["fog"]
	sky_mat.set_shader_parameter("top_color", s["top"])
	sky_mat.set_shader_parameter("bottom_color", s["bot"])
	sky_mat.set_shader_parameter("hills_tint", s["hills"])
	sky_mat.set_shader_parameter("star_amount", s["stars"])
	sky_mat.set_shader_parameter("moon_amount", s["moon"])
	for pair in interior_lights:
		var l: OmniLight3D = pair[0]
		l.light_energy = pair[1] * s["lights"]
	cauldron.base_energy = 1.6 + 0.8 * s["lights"]
	fill.light_energy = 0.45 + 0.15 * (1.0 - t)
	Sfx.set_night_amount(smoothstep(0.65, 1.0, t))

func set_time(t: float, animate := true) -> void:
	if _time_tween and _time_tween.is_valid():
		_time_tween.kill()
	if not animate:
		_apply_time(t)
		return
	_time_tween = create_tween()
	_time_tween.tween_method(_apply_time, time_t, t, 2.5).set_trans(Tween.TRANS_SINE)

func time_label() -> String:
	if time_t < 0.15:
		return "Mañana"
	if time_t < 0.45:
		return "Mediodía"
	if time_t < 0.68:
		return "Tarde"
	if time_t < 0.88:
		return "Atardecer"
	return "Noche"

func _process(delta: float) -> void:
	_t += delta
	if camera:
		# --- WORLD: la cámara sigue a la alquimista por la tienda (y la luz de relleno con ella)
		_cam_x = lerpf(_cam_x, _cam_goal(), 1.0 - exp(-2.6 * delta))
		fill.position.x = _cam_x + 0.5
		var off := Vector3(_cam_x, 0.0, 0.0)
		# --- end WORLD
		camera.position = _cam_base + off + Vector3(sin(_t * 0.11) * 0.08, sin(_t * 0.17) * 0.04, 0.0)
		camera.look_at(_cam_target + off, Vector3.UP)
	_update_flap(delta)   # --- R3 WORLD3

# --- R3 WORLD3: la trampilla se levanta (hacia la pared) cuando ella se acerca al hueco y baja cuando ya pasó.
func _update_flap(delta: float) -> void:
	if flap_pivot == null or alchemist == null:
		return
	var p := alchemist.position
	var near := absf(p.x - COUNTER_X) < COUNTER_HW + 0.5 and p.z < FLAP_Z1 + 0.2 and p.z > FLAP_Z0 - 0.5
	if near != _flap_open:
		_flap_open = near
		if near:
			Sfx.play_pitched("door", 1.75, -13.0)   # un crujido corto de madera
		else:
			Sfx.play("click", 0.08, -11.0)
	var goal := FLAP_OPEN if _flap_open else 0.0
	if not is_equal_approx(_flap_a, goal):
		# sube rápido; baja un poco más despacio y da un golpecito al cerrar
		_flap_a = move_toward(_flap_a, goal, delta * (6.0 if _flap_open else 4.2))
		flap_pivot.rotation.x = _flap_a
# --- end R3 WORLD3

# --- WORLD: biblioteca, estaciones, caminar y cámara ------------------------------------------------

## La biblioteca, a la izquierda: estanterías, un ventanal, el escritorio con el grimorio (la estación de MAGIC),
## un sillón de lectura, el retrato de la maestra y una alfombra.
func _build_library() -> void:
	var H := 5.8
	var z0 := -4.3
	var z1 := WALL_Z
	var floor_l := _mat("res://assets/tex/floor.png", "res://assets/tex/floor_n.png", 0.5, 0.85, Color(0.95, 0.82, 0.76))
	var plaster_l := _mat("res://assets/tex/plaster.png", "res://assets/tex/plaster_n.png", 0.25, 0.95, Color(0.8, 0.88, 0.98))
	var panel := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8, Color(0.92, 0.8, 0.74))
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.6)
	# suelo y paredes (ventanal en x -12.3..-10.5, y 1.3..3.5)
	_box_b(ROOM_X0, LIB_X1, -0.2, 0.0, -4.3, 3.6, floor_l)
	var wx0 := -12.3
	var wx1 := -10.5
	var wy0 := 1.3
	var wy1 := 3.5
	for p in [[ROOM_X0, wx0, 0.0, H], [wx0, wx1, 0.0, wy0], [wx0, wx1, wy1, H], [wx1, LIB_X1, 0.0, H]]:
		var ya: float = p[2]
		var yb: float = p[3]
		if ya < 1.0:
			_box_b(p[0], p[1], ya, minf(yb, 1.0), z0, z1 + 0.04, panel)
		if yb > 1.0:
			_box_b(p[0], p[1], maxf(ya, 1.0), yb, z0, z1, plaster_l)
	_box_b(ROOM_X0 - 0.3, ROOM_X0, 0.0, H, -4.3, 3.6, plaster_l)
	_box_b(ROOM_X0 - 0.28, ROOM_X0, 0.0, 1.0, -4.3, 3.6, panel)
	_box_b(ROOM_X0, LIB_X1, 1.0, 1.1, z1, z1 + 0.08, wood_d)
	for x in [-15.62, -9.95, -7.75]:
		_box_b(x - 0.12, x + 0.12, 1.1, 4.55, z1, z1 + 0.12, wood_d)
	# poste del tabique (lado de la biblioteca)
	_box_b(-7.98, -7.52, 0.0, 4.55, -3.12, -2.95, wood_d)
	# ventanal
	_box_b(wx0 - 0.12, wx1 + 0.12, wy0 - 0.1, wy0 + 0.02, z1 - 0.05, z1 + 0.26, wood_d)
	_box_b(wx0 - 0.12, wx1 + 0.12, wy1, wy1 + 0.12, z1 - 0.05, z1 + 0.1, wood_d)
	_box_b(wx0 - 0.12, wx0, wy0, wy1, z1 - 0.05, z1 + 0.1, wood_d)
	_box_b(wx1, wx1 + 0.12, wy0, wy1, z1 - 0.05, z1 + 0.1, wood_d)
	var mx := (wx0 + wx1) / 2.0
	_box_b(mx - 0.03, mx + 0.03, wy0, wy1, -4.2, -4.1, wood_d)
	for yy in [2.05, 2.8]:
		_box_b(wx0, wx1, yy - 0.03, yy + 0.03, -4.2, -4.1, wood_d)
	var glass := StandardMaterial3D.new()
	glass.albedo_texture = _tex("res://assets/tex/glass.png")
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.uv1_scale = Vector3(2, 2, 1)
	var g := _quad(Vector2(wx1 - wx0, wy1 - wy0), Vector3(mx, (wy0 + wy1) / 2.0, -4.15), glass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# estanterías (con un poco de cuerpo detrás del dibujo) y la escalera
	for b in [["bookshelf", -14.75], ["bookshelf_b", -13.2]]:
		var bx: float = b[1]
		_box_b(bx - 0.68, bx + 0.68, 0.0, 3.05, -3.98, -3.8, wood_d)
		_sprite("res://assets/props/%s.png" % b[0], 0.026, Vector3(bx, 0, -3.78))
	_sprite("res://assets/props/ladder.png", 0.028, Vector3(-14.15, 0, -3.55))
	_sprite("res://assets/props/scroll_basket.png", 0.03, Vector3(-12.75, 0, -2.75))
	# escritorio con el grimorio
	var dx0 := DESK_POS.x - 0.7
	var dx1 := DESK_POS.x + 0.7
	var dz0 := DESK_POS.z - 0.35
	var dz1 := DESK_POS.z + 0.35
	var top := 0.82
	_box_b(dx0, dx1, top - 0.07, top, dz0, dz1, wood_l)
	_box_b(dx0 + 0.06, dx1 - 0.06, top - 0.26, top - 0.07, dz1 - 0.06, dz1 - 0.02, wood_d)
	for lx in [dx0 + 0.09, dx1 - 0.09]:
		for lz in [dz0 + 0.08, dz1 - 0.08]:
			_box_b(lx - 0.05, lx + 0.05, 0.0, top - 0.07, lz - 0.05, lz + 0.05, wood_d)
	grimoire_sprite = _sprite("res://assets/props/grimoire.png", 0.018, Vector3(DESK_POS.x + 0.05, top, DESK_POS.z - 0.05))
	_sprite("res://assets/props/inkwell.png", 0.02, Vector3(DESK_POS.x + 0.52, top, DESK_POS.z + 0.15))
	_sprite("res://assets/props/paper_stack.png", 0.022, Vector3(DESK_POS.x - 0.5, top, DESK_POS.z + 0.2))
	_candle_stick(Vector3(DESK_POS.x - 0.52, top, DESK_POS.z - 0.12))
	_omni(Vector3(DESK_POS.x - 0.45, top + 0.75, DESK_POS.z + 0.35), Color(1.0, 0.72, 0.42), 0.85, 3.6)
	var glow := _omni(Vector3(DESK_POS.x, top + 0.45, DESK_POS.z + 0.4), Color(0.72, 0.55, 1.0), 0.65, 2.4)
	glow.light_volumetric_fog_energy = 0.6
	_motes(Vector3(DESK_POS.x, top + 0.35, DESK_POS.z))
	# rincón de lectura
	_sprite("res://assets/props/armchair.png", 0.03, Vector3(-9.05, 0, -3.25))
	_sprite("res://assets/props/portrait.png", 0.032, Vector3(-9.05, 2.05, -3.94))
	_sprite("res://assets/props/star_chart.png", 0.032, Vector3(-8.55, 3.1, -3.93), null, "top")
	_sprite("res://assets/props/globe.png", 0.03, Vector3(-8.2, 0, -2.85))
	_sprite("res://assets/props/plant_big.png", 0.036, Vector3(-15.0, 0, -0.6))
	# farol colgante
	var lamp := _sprite("res://assets/props/lantern.png", 0.045, Vector3(-13.5, 3.35, -2.2), null, "top")
	lamp.shaded = false
	lamp.modulate = Color(1.4, 1.25, 1.0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cord := _box_b(-13.515, -13.485, 3.35, 5.8, -2.22, -2.18, wood_d)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_omni(Vector3(-13.5, 2.9, -1.9), Color(1.0, 0.76, 0.48), 1.0, 5.5)
	# alfombra
	var rug_m := StandardMaterial3D.new()
	rug_m.albedo_texture = _tex("res://assets/tex/rug_library.png")
	rug_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	rug_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	rug_m.roughness = 1.0
	var rug := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.6, 2.5)
	rug.mesh = pm
	rug.material_override = rug_m
	rug.position = Vector3(-11.3, 0.012, -1.45)
	add_child(rug)

## Un candelero con su llama animada.
func _candle_stick(pos: Vector3) -> void:
	var c := _sprite("res://assets/props/candlestick.png", 0.025, pos)
	var fl := AnimatedSprite3D.new()
	var sf := SpriteFrames.new()
	var ft := _tex("res://assets/props/flame.png")
	sf.set_animation_speed("default", 8.0)
	for i in 3:
		var at := AtlasTexture.new()
		at.atlas = ft
		at.region = Rect2(i * 5, 0, 5, 6)
		sf.add_frame("default", at)
	fl.sprite_frames = sf
	fl.pixel_size = 0.025
	fl.centered = false
	fl.offset = Vector2(-2.5, 0)
	fl.position = Vector3(0, 14 * 0.025, 0.01)
	fl.shaded = false
	fl.modulate = Color(2.0, 1.7, 1.2)
	fl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fl.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(fl)
	fl.play("default")

## Motas de luz violeta que suben despacio del grimorio.
func _motes(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 3.2
	p.preprocess = 3.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.05, 0.15)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.06
	pm.initial_velocity_max = 0.16
	pm.gravity = Vector3(0, 0.02, 0)
	pm.color = Color(1.1, 0.9, 1.6)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _particle_quad("res://assets/fx/sparkle.png", 0.022)
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

## Lo que se toca de cada estación, el letrero que aparece al pasar el cursor y el suelo (clic = caminar ahí).
func _build_stations() -> void:
	var desk := Node3D.new()
	desk.position = DESK_POS
	add_child(desk)
	station_nodes["biblioteca"] = desk
	_pick(desk, Vector3(1.6, 1.5, 0.9), Vector3(0, 0.75, 0.15), func(): _station_press("biblioteca"),
		func(): _station_hover("biblioteca", true), func(): _station_hover("biblioteca", false))
	station_nodes["caldero"] = cauldron
	# --- R3 WORLD3: el mostrador transversal: se toca su tramo de atender (entre ella y el cliente)
	var counter := Node3D.new()
	counter.position = Vector3(COUNTER_X, 0, SERVE_Z)
	add_child(counter)
	station_nodes["mostrador"] = counter
	_pick(counter, Vector3(2.0 * COUNTER_HW, 1.12, 2.4), Vector3(0, 0.56, -0.1), func(): _station_press("mostrador"),
		func(): _station_hover("mostrador", true), func(): _station_hover("mostrador", false))
	# --- end R3 WORLD3
	var door := Node3D.new()
	door.position = Vector3(4.0, 0, -3.95)
	add_child(door)
	station_nodes["puerta"] = door
	_pick(door, Vector3(1.5, 2.6, 0.4), Vector3(0, 1.3, 0.15), func(): _station_press("puerta"),
		func(): _station_hover("puerta", true), func(): _station_hover("puerta", false))
	_station_label = Label3D.new()
	_station_label.font = _font
	_station_label.font_size = 44
	_station_label.pixel_size = 0.0055
	_station_label.outline_size = 12
	_station_label.outline_modulate = Color(0.1, 0.06, 0.12)
	_station_label.modulate = Color(1.0, 0.88, 0.55)
	_station_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_station_label.no_depth_test = true
	_station_label.render_priority = 8
	_station_label.shaded = false
	_station_label.visible = false
	add_child(_station_label)
	_pick_floor()

func _pick_floor() -> void:
	var a := Area3D.new()
	a.name = "Floor"
	a.monitoring = false
	a.monitorable = false
	a.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(ROOM_X1 - ROOM_X0, 0.1, 6.8)
	cs.shape = bs
	cs.position = Vector3((ROOM_X0 + ROOM_X1) / 2.0, -0.05, -0.6)
	a.add_child(cs)
	a.input_event.connect(func(_cam, ev, pos, _n, _i):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_floor_click(pos))
	add_child(a)

func _floor_click(pos: Vector3) -> void:
	if walker == null or not (walker.can_walk.is_valid() and walker.can_walk.call()):
		return
	var tx := clampf(pos.x, walker.x_min(), walker.x_max())
	spawn_sparkles(walker.point(tx) + Vector3(0, 0.05, 0.05), Color(1.3, 1.2, 0.9), 5)
	walker.go_to(tx)

func _build_walker() -> void:
	walker = Walker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.stations = STATIONS.duplicate(true)
	walker.setup(alchemist, LANE, P_ALCH_COUNTER.x, 1)
	walker.station_reached.connect(func(id): station_reached.emit(id))
	walker.station_left.connect(func(id): station_left.emit(id))
	snap_camera()

func _station_press(id: String) -> void:
	if can_use.is_valid() and not can_use.call(id):
		return
	use_station(id)

## Camina hasta la estación y la usa: emite station_clicked(id) al llegar. false si la interrumpieron.
func use_station(id: String) -> bool:
	if walker == null or not STATIONS.has(id):
		return false
	if not await walker.go_station(id):
		return false
	station_clicked.emit(id)
	return true

## Solo camina hasta la estación (sin usarla). true al llegar.
func go_station(id: String) -> bool:
	if walker == null:
		return false
	return await walker.go_station(id)

## Está en el sector de esa estación.
func at_station(id: String) -> bool:
	return walker != null and walker.current == id

func current_station() -> String:
	return walker.current if walker else ""

## --- R3 SHIP: el letrero de la estación sigue al ratón de verdad. Godot repite cada cuadro la selección 3D con la última
## posición del ratón que vio fuera de la interfaz; con el banco del caldero abierto (que tapa toda la pantalla) esa
## posición queda vieja, y como la cámara se mueve, el letrero «Caldero» se encendía solo detrás del banco o al cerrarlo.
## main.gd llama block_hover(true) al abrir el banco y block_hover(false) al cerrarlo; después, el letrero vuelve
## cuando el ratón se mueve de verdad sobre la tienda (_unhandled_input: no lo tapa ningún panel).
var _hover_blocked := false     # el banco del caldero está abierto
var _hover_live := true         # false desde que se abre el banco hasta que el ratón se mueve sobre la tienda
var _godot_hover := ""          # la estación que Godot cree que está bajo el ratón (mouse_entered / mouse_exited)

func block_hover(on: bool) -> void:
	_hover_blocked = on
	_hover_live = false
	hide_station_label()

func hover_blocked() -> bool:
	return _hover_blocked or not _hover_live

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and not _hover_blocked and not _hover_live:
		_hover_live = true
		if _godot_hover != "":
			_label_on(_godot_hover)

## Esconde el letrero de la estación.
func hide_station_label() -> void:
	if _hover_station != "":
		_label_off(_hover_station)
	elif _station_label:
		_station_label.visible = false
# --- end R3 SHIP

## Cambia el letrero que aparece al pasar el cursor por una estación (p. ej. "Puerta · ir al mercado").
func set_station_label(id: String, text: String) -> void:
	_station_label_text[id] = text
	if _hover_station == id and _station_label:
		_station_label.text = text

func _station_hover(id: String, on: bool) -> void:
	if _station_label == null:
		return
	# --- R3 SHIP: se anota lo que cree Godot, pero el letrero solo se enciende si el ratón está de verdad en la tienda
	if on:
		_godot_hover = id
		if not hover_blocked():
			_label_on(id)
	else:
		if _godot_hover == id:
			_godot_hover = ""
		if _hover_station == id:
			_label_off(id)
	# --- end R3 SHIP

func _label_on(id: String) -> void:
	_hover_station = id
	_station_label.text = _station_label_text.get(id, STATIONS[id]["name"])
	var n: Node3D = station_nodes[id]
	_station_label.global_position = n.global_position + Vector3(0, STATION_LABEL_Y.get(id, 1.8), 0.35)
	_station_label.visible = true
	if id == "biblioteca" and grimoire_sprite:
		grimoire_sprite.modulate = Color(1.3, 1.25, 1.4)

func _label_off(_id: String) -> void:
	_hover_station = ""
	_station_label.visible = false
	if grimoire_sprite:
		grimoire_sprite.modulate = Color.WHITE

func _cam_goal() -> float:
	if is_finite(cam_fixed_x):
		return cam_fixed_x
	if alchemist == null:
		return 0.0
	var g := alchemist.position.x + alchemist.facing * 0.6
	# --- R3 WORLD3: de su lado del mostrador (y mientras cruza la trampilla) la cámara se queda a su izquierda: el
	# mostrador se ve de lado (no de punta), el cliente del otro lado se ve entero y a ella se la ve pasar
	if alchemist.position.x < COUNTER_X + COUNTER_HW + 0.3:
		g = minf(g, CAM_COUNTER_X)
	return clampf(g, CAM_X0, CAM_X1)

## Pone la cámara sobre la alquimista sin deslizarse (tras teletransportarla).
func snap_camera() -> void:
	_cam_x = _cam_goal()

## Objetos de las estaciones para el cursor del mando (LB / RB): [[Node3D, altura], ...].
func pad_picks() -> Array:
	return [[station_nodes["biblioteca"], 0.95], [station_nodes["mostrador"], 0.9], [station_nodes["puerta"], 1.3]]
# --- end WORLD

# --- R3 MAGIC3: aquí estaba el estante 3D de pergaminos (MAGIC, ronda 2): ya no hay pergaminos.
