extends Node3D
class_name MarketWorld
## El mercado del pueblo: una calle empedrada por la mañana, con puestos bajo toldos de colores, casas con
## entramado, una fuente, flores, banderines, palomas y gente de todas partes que pasea. Se construye en código, como
## la tienda (shop_world.gd), y vive escondido y en pausa mientras la alquimista está en la tienda (ver main.gd).
## Ella camina por la calle con walker.gd (A/D, flechas, cruceta o clic en el suelo). Al tocar un puesto camina hasta
## él y emite station_clicked(id del vendedor): main.gd abre el panel de ese puesto (overlays.gd show_market).
## La puerta de su tienda, al principio de la calle, es la estación "tienda": la devuelve a casa.

signal station_clicked(id: String)   # llegó al puesto que tocó ("ilse", "borin", ...) o a la puerta de su tienda ("tienda")
signal station_reached(id: String)   # entró en la zona de un puesto o de la puerta
signal station_left(id: String)

const LANE_Z := -0.55                 # la calle por donde camina ella
const X0 := -2.6                      # inicio de la calle (delante de la puerta de su tienda)
const X1 := 29.2                      # fin de la calle
const SHOP_DOOR_X := -2.0
const FACADE_Z := -4.5                # fachadas de las casas
const STALL_X := {"ilse": 3.6, "borin": 8.2, "tobias": 17.4, "mabel": 22.0, "lupo": 26.6}
const FOUNTAIN_POS := Vector3(12.8, 0, -3.3)
const CAM_X0 := 2.4
const CAM_X1 := 24.2
## Quiénes pueden pasear por el mercado (solo los que tienen sprite: el resto aparece cuando exista su dibujo).
const CROWD := ["lirien", "bram", "elda", "kit", "aldric", "wren", "granjero", "panadera", "anciano", "sylwen", "nyra",
	"ragnar", "isolde", "roxa", "anselmo", "marta", "vianne", "hassim", "pip", "grumm", "zaria", "fizz", "brann"]
const CROWD_MAX := 10
const NPC_LANES := [-1.1, 0.25, 0.85]   # --- R5 WORLD: (era -1.15) 5 cm más adelante: con los desvíos de profundidad de la gente, nadie se mete en los postes de los puestos

var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var fill: OmniLight3D
var alchemist: Actor
var walker: Walker
var can_use: Callable                 # (id) -> bool (lo pone main.gd)
var vendors := {}                     # id -> Actor
var station_nodes := {}               # id -> Node3D (para el cursor del mando)
var npcs: Array = []                  # [{a, x, z, tx, tz, speed, wait, pass, greet}]
var pigeons: Array = []               # [{s, state, vel, t, home}]
var _swallow_t := 3.0
var _swallow_frames: SpriteFrames
var _label: Label3D
var _label_text := {}
var _hover := ""
var _cam_x := 4.0
var _cam_base := Vector3(0.0, 5.3, 10.0)
var _cam_target := Vector3(0.0, 1.7, -2.6)
var _t := 0.0
var _enter_gen := 0
var _font: Font
var _font_sc: Font
var _mats := {}

# ------------------------------------------------------------------ ayudas (como en shop_world.gd)

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
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 20.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = rough
	_mats[key] = m
	return m

func _box_b(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x1 - x0, y1 - y0, z1 - z0)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	(parent if parent else self).add_child(mi)
	return mi

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

func _tex_mat(path: String, cull_off := false) -> StandardMaterial3D:
	var key := "tm:" + path + str(cull_off)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.roughness = 1.0
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

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

func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.7, Color(1, 1, 1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

## Sprite que se usa para un vendedor: el suyo si ya existe; si no, el de reserva de Data.VENDORS.
static func vendor_sprite(vendor: String) -> String:
	if ResourceLoader.exists("res://assets/chars/%s_idle.png" % vendor):
		return vendor
	return Data.VENDORS.get(vendor, {}).get("fallback", "anciano")

static func _has_sprite(id: String) -> bool:
	return ResourceLoader.exists("res://assets/chars/%s_idle.png" % id) and ResourceLoader.exists("res://assets/chars/%s_walk.png" % id)

# ------------------------------------------------------------------ construcción

func build() -> void:
	_font = load("res://assets/fonts/Alegreya-Bold.ttf")
	_font_sc = load("res://assets/fonts/AlegreyaSC-Bold.ttf")
	_build_camera_and_env()
	_build_sky_and_ground()
	_build_houses()
	_build_shop_facade()
	_build_plaza()
	for v in Data.VENDOR_ORDER:
		if STALL_X.has(v):
			_build_stall(v)
	_build_decor()
	_build_alchemist()
	_build_crowd()
	_build_pigeons()
	_build_label()
	_pick_floor()

# --- R6 PERF: el desenfoque de arriba y abajo del mercado (main.gd lo aplica cuando esta cámara es la activa). La
# gente camina en la mitad de abajo de la pantalla: la banda nítida baja y se abre más que en la tienda.
# Antes: centro 0,46, mitad 0,22, caída 0,30 (la calle con la gente quedaba en la franja borrosa de abajo). Ahora la
# banda nítida va de la fila 124 a la 638 (de 720): solo el 28 % desenfocado (los tejados y las macetas de delante).
func post_params() -> Dictionary:
	return POST
const POST := {"focus_center": 0.53, "focus_half": 0.34, "focus_falloff": 0.13, "max_lod": 2.6}
# --- end R6 PERF

func _build_camera_and_env() -> void:
	camera = Camera3D.new()
	camera.fov = 35.0
	camera.near = 0.1
	camera.far = 90.0
	add_child(camera)
	var ca := CameraAttributesPractical.new()
	# --- R6 PERF: el desenfoque de cámara (solo Forward+) más lejos: la calle de delante (la gente, las macetas) y las
	# casas del fondo quedan nítidas (antes: lejos 19 m / 8, cerca 6,2 m / 2)
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 24.0
	ca.dof_blur_far_transition = 8.0
	ca.dof_blur_near_enabled = true
	ca.dof_blur_near_distance = 4.5
	ca.dof_blur_near_transition = 1.5
	# --- end R6 PERF
	ca.dof_blur_amount = 0.08
	camera.attributes = ca
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.76, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.7, 0.86)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
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
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(1.0, 0.94, 0.86)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_ambient_inject = 0.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	camera.environment = env   # el entorno va en la cámara: la tienda conserva el suyo (WorldEnvironment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 34.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.5
	sun.shadow_blur = 1.0
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.75
	sun.rotation_degrees = Vector3(-40.0, -35.0, 0.0)   # sol de mañana por delante a la izquierda: ilumina las fachadas
	add_child(sun)
	fill = OmniLight3D.new()
	fill.position = Vector3(4.0, 3.6, 4.5)
	fill.omni_range = 16.0
	fill.omni_attenuation = 0.7
	fill.light_color = Color(1.0, 0.9, 0.78)
	fill.light_energy = 0.45
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)

func _build_sky_and_ground() -> void:
	var sh := ShaderMaterial.new()
	sh.shader = load("res://shaders/sky.gdshader")
	sh.set_shader_parameter("hills", _tex("res://assets/tex/backdrop.png"))
	sh.set_shader_parameter("top_color", Color(0.44, 0.66, 0.98))
	sh.set_shader_parameter("bottom_color", Color(0.99, 0.9, 0.78))
	sh.set_shader_parameter("hills_tint", Color(0.92, 0.96, 1.05))
	sh.set_shader_parameter("star_amount", 0.0)
	sh.set_shader_parameter("moon_amount", 0.0)
	sh.set_shader_parameter("hills_repeat", 4.0)
	sh.set_shader_parameter("aspect", 70.0 / 20.0)
	sh.set_shader_parameter("hills_height", 0.42)
	var q := _quad(Vector2(70, 20), Vector3(13.0, 7.0, -18.0), sh)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var street := _mat("res://assets/tex/cobble_street.png", "", 0.5, 0.95)
	var flag := _mat("res://assets/tex/flagstone.png", "", 0.6, 0.95, Color(1.0, 0.97, 0.92))
	var flag2 := _mat("res://assets/tex/flagstone.png", "", 0.6, 0.95, Color(0.92, 0.95, 0.88))
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.5, 0.9)
	var grass := _mat("res://assets/tex/cobble.png", "", 0.5, 1.0, Color(0.62, 0.8, 0.52))
	_box_b(-14.0, 40.0, -0.2, 0.0, -3.1, 1.75, street)         # la calle
	_box_b(-14.0, 40.0, -0.2, 0.02, -8.5, -3.1, flag)          # acera junto a las casas (y la placita)
	_box_b(-14.0, 40.0, -0.2, 0.16, 1.75, 1.95, stone)         # bordillo
	_box_b(-14.0, 40.0, -0.2, 0.02, 1.95, 6.0, flag2)          # paseo delantero
	_box_b(-20.0, 46.0, -0.3, -0.05, -30.0, -8.5, grass)       # campo detrás del pueblo

func _build_label() -> void:
	_label = Label3D.new()
	_label.font = _font
	_label.font_size = 44
	_label.pixel_size = 0.0055
	_label.outline_size = 12
	_label.outline_modulate = Color(0.1, 0.06, 0.12)
	_label.modulate = Color(1.0, 0.88, 0.55)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 8
	_label.shaded = false
	_label.visible = false
	add_child(_label)

# ------------------------------------------------------------------ casas

const HOUSES := [
	# x0, ancho, alto de pared, color, tejado, ventanas, letrero colgante, puerta
	[-11.1, 5.5, 4.6, Color(0.96, 0.9, 0.78), "roof_red", "window_green", "", "door_brown"],
	# --- R5 WORLD: aquí estaba la panadería [-0.5, 4.2...] con su puerta azul: ahora ese tramo es de la tienda
	[3.7, 3.4, 4.5, Color(0.97, 0.92, 0.8), "roof_red", "window_green", "", ""],
	[7.1, 3.2, 5.0, Color(0.78, 0.86, 0.96), "roof_plum", "window_red", "jarra", "door_brown"],
	[15.6, 3.6, 4.7, Color(0.82, 0.92, 0.8), "roof_red", "window_red", "bota", "door_green"],
	[19.2, 4.0, 5.1, Color(0.97, 0.92, 0.8), "roof_slate", "window_blue", "yunque", "door_brown"],
	[23.2, 3.4, 4.6, Color(0.97, 0.8, 0.76), "roof_red", "window_green", "", ""],
	[26.6, 4.2, 4.9, Color(0.78, 0.86, 0.96), "roof_plum", "window_red", "", "door_blue"],
	[30.8, 4.6, 4.5, Color(0.95, 0.85, 0.62), "roof_red", "window_green", "", "door_green"],
	[35.4, 5.0, 4.8, Color(0.97, 0.92, 0.8), "roof_slate", "window_blue", "", ""],
]

func _build_houses() -> void:
	for h in HOUSES:
		_house(h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], FACADE_Z)
	# detrás de la fuente, la placita se abre y las casas quedan más atrás
	_house(10.3, 5.3, 5.2, Color(0.95, 0.85, 0.62), "roof_red", "window_blue", "", "door_brown", -8.6)

func _house(x0: float, w: float, h: float, col: Color, roof: String, win: String, sign: String, door: String, fz: float) -> void:
	var x1 := x0 + w
	var depth := 3.6
	var plaster := _mat("res://assets/tex/plaster.png", "res://assets/tex/plaster_n.png", 0.25, 0.95, col)
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.5, 0.9)
	var beam := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(x0, x1, 0.0, h, fz - depth, fz, plaster)
	_box_b(x0 - 0.02, x1 + 0.02, 0.0, 0.62, fz - depth, fz + 0.05, stone)
	# entramado de madera
	var bz0 := fz
	var bz1 := fz + 0.07
	# --- R5 WORLD: las vigas van de poste a poste (antes llegaban a la esquina y su canto quedaba a 1 cm del del poste)
	for y in [0.62, 2.62]:
		_box_b(x0 + 0.07, x1 - 0.07, y, y + 0.14, bz0, bz1, beam)
	_box_b(x0 + 0.07, x1 - 0.07, h - 0.14, h, bz0, bz1 + 0.03, beam)
	# --- end R5 WORLD
	for x in [x0 + 0.07, x1 - 0.07]:
		_box_b(x - 0.08, x + 0.08, 0.62, h, bz0, bz1, beam)
	# tejado a dos aguas (cumbrera paralela a la calle) y chimenea
	var rh := depth * 0.5 * 1.35
	var pr := PrismMesh.new()
	pr.size = Vector3(depth + 0.8, rh, w + 0.36)
	var rm := MeshInstance3D.new()
	rm.mesh = pr
	rm.material_override = _mat("res://assets/tex/%s.png" % roof, "", 0.6, 0.9)
	rm.position = Vector3((x0 + x1) / 2.0, h + rh / 2.0, fz - depth / 2.0)
	rm.rotation_degrees = Vector3(0, 90, 0)
	add_child(rm)
	_box_b(x1 - 1.0, x1 - 0.5, h, h + rh + 0.5, fz - depth * 0.62, fz - depth * 0.62 + 0.5, stone)
	# ventanas del piso de arriba
	var n := maxi(1, int(w / 1.45))
	for i in n:
		var wx := x0 + w * (i + 0.5) / n
		_sprite("res://assets/props/%s.png" % win, 0.034, Vector3(wx, 2.95, fz + 0.09))
		if i < n - 1 and w > 3.0:
			# cruces de San Andrés entre ventanas
			var mx := x0 + w * (i + 1.0) / n
			for sgn in [-1.0, 1.0]:
				var d := _box_b(mx - 0.06, mx + 0.06, 0.0, 1.9, bz0, bz1, beam)
				d.position = Vector3(mx, 3.7, bz0 + 0.035)
				d.rotation_degrees = Vector3(0, 0, 32.0 * sgn)
	# puerta y letrero colgante
	if door != "":
		_sprite("res://assets/props/%s.png" % door, 0.05, Vector3(x0 + w * 0.3, 0.0, fz + 0.1))   # --- R5 WORLD: (era fz + 0.08: 1 cm delante de la viga de abajo)
	if sign != "":
		_sprite("res://assets/props/hsign_%s.png" % sign, 0.042, Vector3(x0 + w * 0.3 + 1.0, 2.05, fz + 0.3))

## --- R5 WORLD: la fachada de su tienda, al principio de la calle. Antes la tienda ocupaba 5 m (x -5,6..-0,5) y a su
## lado había otra casa (la panadería, con su puerta azul): parecía una segunda puerta de la tienda, que por dentro no
## existe. Ahora toda esa fachada (x -5,6..3,7) es la tienda, un solo edificio con su tejado morado, y se lee como lo
## de dentro: su única puerta (por donde entra y sale ella), el escaparate de pociones, el letrero con el nombre, la
## ventana con jardinera y, si tiene Crow Delivery (la mejora "krapido"), la ventanilla del cuervo con su percha y su
## letrero; si no, una ventana con flores en ese sitio. Ninguna cara comparte plano con otra (ver zcheck.gd).
const SHOP_X0 := -5.6
const SHOP_X1 := 3.7
const SHOP_H := 4.8
const CROW_WIN_X := 1.55        # centro de la ventanilla del cuervo (entre el farol de la calle y el puesto de Ilse)
const DOOR_LABEL_H := 2.74      # altura del letrero de la puerta al pasar el cursor (bajo el tablero del nombre)
var _crow_nodes: Array = []     # se ven con la mejora "krapido"
var _crow_plain: Array = []     # se ven sin ella (una ventana con flores)

func _build_shop_facade() -> void:
	var x0 := SHOP_X0
	var x1 := SHOP_X1
	var h := SHOP_H
	var plaster := _mat("res://assets/tex/plaster.png", "res://assets/tex/plaster_n.png", 0.25, 0.95, Color(0.84, 0.78, 0.95))
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.5, 0.9)
	var beam := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var fz := FACADE_Z
	var dl := SHOP_DOOR_X - 0.81   # el marco de la puerta (de canto a canto)
	var dr := SHOP_DOOR_X + 0.81
	# la pared y el zócalo de piedra (el zócalo no pasa por la puerta: antes tapaba sus 60 cm de abajo)
	_box_b(x0, x1, 0.0, h, fz - 3.6, fz, plaster)
	_box_b(x0 + 0.02, dl, 0.0, 0.62, fz - 0.3, fz + 0.05, stone)
	_box_b(dr, x1 - 0.02, 0.0, 0.62, fz - 0.3, fz + 0.05, stone)
	# entramado: postes en las esquinas y entre los tramos; vigas de poste a poste (la de abajo no cruza la puerta)
	var posts := [x0 + 0.07, -3.0, -0.55, x1 - 0.07]
	for x in posts:
		_box_b(x - 0.08, x + 0.08, 0.62, h, fz, fz + 0.07, beam)
	_box_b(x0 + 0.07, dl, 0.62, 0.76, fz, fz + 0.07, beam)
	_box_b(dr, x1 - 0.07, 0.62, 0.76, fz, fz + 0.07, beam)
	_box_b(x0 + 0.07, x1 - 0.07, 2.7, 2.84, fz, fz + 0.07, beam)
	_box_b(x0 + 0.07, x1 - 0.07, h - 0.14, h, fz, fz + 0.1, beam)
	# el tejado (uno solo, de punta a punta) y la chimenea, que humea (el fuego del caldero nunca se apaga)
	var pr := PrismMesh.new()
	pr.size = Vector3(4.4, 2.6, x1 - x0 + 0.4)
	var rm := MeshInstance3D.new()
	rm.mesh = pr
	rm.material_override = _mat("res://assets/tex/roof_plum.png", "", 0.6, 0.9)
	rm.position = Vector3((x0 + x1) / 2.0, h + 1.3, fz - 1.8)
	rm.rotation_degrees = Vector3(0, 90, 0)
	add_child(rm)
	_box_b(-4.85, -4.25, h + 1.0, h + 3.25, fz - 1.75, fz - 1.15, stone)
	# la puerta (sin nada que la cruce), su marco, el farol y las macetas
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = _tex("res://assets/tex/door.png")
	dm.normal_enabled = true
	dm.normal_texture = _tex("res://assets/tex/door_n.png")
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_quad(Vector2(1.38, 2.48), Vector3(SHOP_DOOR_X, 1.24, fz + 0.04), dm)
	_box_b(SHOP_DOOR_X - 0.69, SHOP_DOOR_X + 0.69, 0.0, 2.5, fz - 0.3, fz + 0.02, _flat_mat(Color(0.09, 0.07, 0.08)))   # detrás de la puerta (se ve por su ventanita)
	for x in [SHOP_DOOR_X - 0.75, SHOP_DOOR_X + 0.75]:
		_box_b(x - 0.06, x + 0.06, 0.0, 2.62, fz, fz + 0.12, beam)
	_box_b(dl, dr, 2.5, 2.62, fz, fz + 0.12, beam)
	var lantern := _sprite("res://assets/props/lantern.png", 0.04, Vector3(SHOP_DOOR_X - 1.05, 1.85, fz + 0.12))
	lantern.shaded = false
	_sprite("res://assets/props/flowerpot_red.png", 0.035, Vector3(SHOP_DOOR_X - 1.0, 0.0, fz + 0.35))
	_sprite("res://assets/props/flowerpot_yellow.png", 0.035, Vector3(SHOP_DOOR_X + 1.0, 0.0, fz + 0.36))
	# el letrero colgado del caldero, junto a la puerta
	_sprite("res://assets/props/hsign_caldero.png", 0.05, Vector3(SHOP_DOOR_X + 1.25, 2.1, fz + 0.3))
	# el escaparate de pociones, a la izquierda de la puerta, con su jardinera
	_sprite("res://assets/props/window_shop.png", 0.045, Vector3(-4.3, 0.75, fz + 0.1))
	_flower_box(-4.3, 1.5, 0.62, fz)
	# el nombre de la tienda en un tablero sobre el escaparate y la puerta
	_box_b(-5.25, -1.25, 2.88, 3.24, fz + 0.07, fz + 0.12, wood)
	var name_l := Label3D.new()
	name_l.font = _font_sc
	name_l.text = "Midnight Cauldron"
	name_l.font_size = 46
	name_l.pixel_size = 0.0062
	name_l.outline_size = 9
	name_l.outline_modulate = Color(0.12, 0.07, 0.06)
	name_l.modulate = Color(1.0, 0.86, 0.5)
	name_l.position = Vector3(-3.25, 3.06, fz + 0.135)
	name_l.shaded = false
	name_l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	add_child(name_l)
	# a la derecha de la puerta: una ventana con jardinera (el farol de la calle queda entre ella y la del cuervo)
	_sprite("res://assets/props/window_plum.png", 0.034, Vector3(0.0, 1.0, fz + 0.1))
	_flower_box(0.0, 1.05, 0.88, fz)
	# arriba, el piso de la maestra: cinco ventanas
	for wx in [-4.3, -2.0, 0.0, CROW_WIN_X, 3.0]:
		_sprite("res://assets/props/window_plum.png", 0.034, Vector3(wx, 3.38, fz + 0.1))
	# la ventanilla del cuervo (Crow Delivery) o, sin la mejora, una ventana con flores
	_build_crow_window(CROW_WIN_X, fz)
	_refresh_facade()
	if not Game.upgrades_changed.is_connected(_refresh_facade):
		Game.upgrades_changed.connect(_refresh_facade)
	# la puerta es una estación: entrar = volver a la tienda
	var door := Node3D.new()
	door.position = Vector3(SHOP_DOOR_X, 0, fz)
	add_child(door)
	station_nodes["tienda"] = door
	# (el letrero «Back to the shop» sale entre el marco de la puerta y el tablero del nombre, sin taparlo: era 2.9)
	_pick(door, Vector3(1.6, 2.7, 0.8), Vector3(0, 1.35, 0.3), func(): _station_press("tienda"),
		func(): _hover_on("tienda", door, DOOR_LABEL_H), func(): _hover_off("tienda"))

## Un color liso (para lo oscuro de detrás de la puerta).
func _flat_mat(col: Color) -> StandardMaterial3D:
	var key := "flat:" + col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	_mats[key] = m
	return m

## Una jardinera de madera con flores bajo una ventana (cx: centro; w: ancho; y: su borde de arriba).
func _flower_box(cx: float, w: float, y: float, fz: float, parent: Node3D = null) -> void:
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(cx - w / 2.0, cx + w / 2.0, y - 0.2, y, fz + 0.11, fz + 0.36, wood_d, parent)
	var f := _sprite("res://assets/props/flowers.png", 0.034 * minf(1.0, w / 1.5), Vector3(cx, y - 0.04, fz + 0.24), parent)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## La ventanilla del cuervo, como la de dentro (marco, tapa con el logo pintado, percha y el letrero CROW DELIVERY), y
## la ventana con flores que ocupa su sitio mientras no se compre.
func _build_crow_window(cx: float, fz: float) -> void:
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.6)
	var crow := Node3D.new()
	crow.name = "CrowWindow"
	add_child(crow)
	var hw := 0.31          # medio ancho del hueco
	var y0 := 1.45          # alféizar
	var y1 := 2.37          # dintel
	# la tapa (cerrada) con el logo, 3 cm delante de la pared, dentro del marco
	var hm := StandardMaterial3D.new()
	hm.albedo_texture = _tex("res://assets/props/krapido_hatch.png")
	hm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hm.roughness = 0.85
	var hq := _quad(Vector2(2.0 * hw, y1 - y0), Vector3(cx, (y0 + y1) / 2.0, fz + 0.03), hm, crow)
	hq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# el marco: alféizar ancho, dintel y jambas (de 7 a 12 cm delante de la pared: la tapa queda hundida)
	_box_b(cx - hw - 0.1, cx + hw + 0.1, y0 - 0.1, y0, fz, fz + 0.2, wood_d, crow)
	_box_b(cx - hw - 0.1, cx + hw + 0.1, y1, y1 + 0.11, fz, fz + 0.09, wood_d, crow)
	_box_b(cx - hw - 0.1, cx - hw, y0, y1, fz, fz + 0.09, wood_d, crow)
	_box_b(cx + hw, cx + hw + 0.1, y0, y1, fz, fz + 0.09, wood_d, crow)
	# la percha: una barra redonda delante del alféizar, con dos soportes
	var perch := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.022
	cyl.height = 2.0 * hw - 0.1   # las puntas, dentro de los soportes
	cyl.radial_segments = 8
	perch.mesh = cyl
	perch.material_override = wood_l
	perch.rotation_degrees = Vector3(0, 0, 90)
	perch.position = Vector3(cx, y0 + 0.1, fz + 0.15)
	crow.add_child(perch)
	for sx in [cx - hw + 0.04, cx + hw - 0.04]:
		_box_b(sx - 0.018, sx + 0.018, y0, y0 + 0.09, fz + 0.12, fz + 0.18, wood_d, crow)
	# el letrero sobre la ventanilla, delante de la viga
	var crow_sign := _sprite("res://assets/props/krapido_sign.png", 0.019, Vector3(cx, y1 + 0.14, fz + 0.14), crow)
	crow_sign.name = "CrowSign"
	_crow_nodes.append(crow)
	# sin la mejora: una ventana con flores
	var plain := Node3D.new()
	plain.name = "PlainWindow"
	add_child(plain)
	_sprite("res://assets/props/window_red.png", 0.034, Vector3(cx, 1.15, fz + 0.1), plain)
	_flower_box(cx, 1.05, 1.0, fz, plain)
	_crow_plain.append(plain)

## La ventanilla del cuervo se ve si tiene Crow Delivery (se llama al construir, al entrar al mercado y al comprar).
func _refresh_facade() -> void:
	var on := Game.has_upgrade("krapido")
	for n in _crow_nodes:
		if is_instance_valid(n):
			n.visible = on
	for n in _crow_plain:
		if is_instance_valid(n):
			n.visible = not on
# --- end R5 WORLD

## La placita: fuente con agua que cae, un árbol, bancos, un carro de verduras y flores.
func _build_plaza() -> void:
	_build_fountain()   # --- R3 WORLD3: la fuente con agua de verdad (ver más abajo)
	# árbol, arbustos y bancos
	_sprite("res://assets/props/tree.png", 0.062, Vector3(FOUNTAIN_POS.x + 0.6, 0, -6.9))
	_sprite("res://assets/props/bush.png", 0.045, Vector3(FOUNTAIN_POS.x - 2.2, 0, -5.9))
	_sprite("res://assets/props/bush.png", 0.045, Vector3(FOUNTAIN_POS.x + 2.4, 0, -6.0))
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	for bx in [FOUNTAIN_POS.x - 2.6, FOUNTAIN_POS.x + 2.6]:
		_box_b(bx - 0.6, bx + 0.6, 0.42, 0.5, -4.6, -4.2, wood)
		_box_b(bx - 0.55, bx - 0.45, 0.0, 0.42, -4.55, -4.25, wood)
		_box_b(bx + 0.45, bx + 0.55, 0.0, 0.42, -4.55, -4.25, wood)
	_sprite("res://assets/props/bucket.png", 0.03, Vector3(FOUNTAIN_POS.x + 1.55, 0, FOUNTAIN_POS.z + 0.9))
	_sprite("res://assets/props/cart.png", 0.036, Vector3(10.6, 0, -2.6))

# --- R3 WORLD3: la fuente con agua de verdad ----------------------------------------------------------------------
# Antes la pileta era un cilindro macizo (el agua quedaba dentro de la piedra). Ahora: una pileta hueca (pared de
# piedra con su borde), con fondo y unas monedas, llena de agua (shaders/fountain_water.gdshader: olas, anillos donde
# caen los chorros, destellos, un poco transparente); el cuenco de arriba también hueco y con agua; un surtidor en lo
# alto que lo llena y 8 chorros que caen del borde del cuenco a la pileta (shaders/fountain_stream.gdshader), con
# salpicaduras donde tocan el agua. Todo funciona en Compatibility (WebGL 2).
const BASIN_R_OUT := 1.42
const BASIN_R_IN := 1.16
const BASIN_H := 0.64
const BASIN_FLOOR := 0.3        # poco hondo (como las de verdad): así desde la calle se ve el fondo con las monedas
const WATER_Y := 0.53
const BOWL_TOP := 2.04
const BOWL_R_OUT := 0.66
const BOWL_R_IN := 0.55
const BOWL_WATER := 1.99
const JET_COUNT := 8
const JET_PHASE := 0.3927        # el primer chorro a 22,5° (así ninguno cae justo delante de la columna)
const JET_LAND_R := 0.98
var fountain_water: MeshInstance3D
var fountain_streams: MeshInstance3D

func _build_fountain() -> void:
	var stone := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.7, 0.9, Color(1.0, 0.97, 0.92))
	var stone_dk := _mat("res://assets/tex/stone.png", "res://assets/tex/stone_n.png", 0.7, 0.95, Color(0.5, 0.58, 0.56))
	var f := Node3D.new()
	f.name = "Fountain"
	f.position = FOUNTAIN_POS
	add_child(f)
	# la pileta: pared hueca con un borde que sobresale (de donde se ve el agua por dentro)
	_mesh_in(f, _ring_mesh(BASIN_R_IN, BASIN_R_OUT - 0.04, BASIN_H - 0.08, 0.0, BASIN_R_OUT, BASIN_FLOOR), stone)
	_mesh_in(f, _ring_mesh(BASIN_R_IN - 0.05, BASIN_R_OUT + 0.05, BASIN_H, BASIN_H - 0.09, BASIN_R_OUT + 0.05, BASIN_H - 0.09), stone)
	# el fondo (piedra oscura, con verdín) y unas monedas que brillan bajo el agua
	var floor_mi := _cyl(f, BASIN_R_IN + 0.02, BASIN_R_IN + 0.02, 0.04, BASIN_FLOOR - 0.02, stone_dk, 32)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.74, 0.28)
	gold.metallic = 0.85
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color(0.8, 0.58, 0.16)
	for c in [[0.75, -2.3], [0.85, -0.6], [0.55, -1.0], [0.7, -0.15]]:   # más bien atrás: desde la calle el borde tapa la parte de delante
		var coin := _cyl(f, 0.06, 0.06, 0.012, BASIN_FLOOR + 0.006, gold, 10)
		coin.position.x = cos(c[1]) * c[0]
		coin.position.z = sin(c[1]) * c[0]
		coin.rotation.x = randf_range(-0.12, 0.12)
	# la columna (desde el fondo, con un zócalo bajo el agua), el cuenco de arriba y el surtidor
	_cyl(f, 0.36, 0.4, 0.14, BASIN_FLOOR + 0.07, stone, 16)
	_cyl(f, 0.2, 0.28, 1.8 - BASIN_FLOOR, (1.8 + BASIN_FLOOR) / 2.0, stone, 12)
	_mesh_in(f, _ring_mesh(BOWL_R_IN, BOWL_R_OUT, BOWL_TOP, 1.72, 0.22, BOWL_WATER - 0.08, 20), stone)
	_cyl(f, BOWL_R_IN + 0.01, BOWL_R_IN + 0.01, 0.02, BOWL_WATER - 0.08, stone_dk, 20)   # fondo del cuenco
	_cyl(f, 0.1, 0.13, 0.36, BOWL_WATER + 0.12, stone, 10)
	var top := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.13
	sp.height = 0.26
	sp.radial_segments = 12
	sp.rings = 6
	top.mesh = sp
	top.material_override = stone
	top.position = Vector3(0, BOWL_WATER + 0.36, 0)
	f.add_child(top)
	# el agua: la pileta y el cuenco de arriba
	var wsh: Shader = load("res://shaders/fountain_water.gdshader")
	fountain_water = _water_surface(f, wsh, BASIN_R_IN + 0.03, WATER_Y, {"radius": BASIN_R_IN, "jets": float(JET_COUNT),
		"jets_r": JET_LAND_R, "jet_phase": JET_PHASE})
	_water_surface(f, wsh, BOWL_R_IN + 0.02, BOWL_WATER, {"radius": BOWL_R_IN, "jets": 4.0, "jets_r": 0.3,
		"jet_phase": 0.0, "center_jet": 1.0, "ring_max": 0.22, "alpha": 0.86})
	# los chorros: 8 caen del borde del cuenco a la pileta; 4 cortitos salen del surtidor al cuenco
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in JET_COUNT:
		var a := JET_PHASE + TAU * float(i) / float(JET_COUNT)
		_stream_tube(st, a, BOWL_R_OUT - 0.01, BOWL_TOP - 0.01, JET_LAND_R, WATER_Y, 0.0, 0.036, 0.026)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		_stream_tube(st, a, 0.06, BOWL_WATER + 0.42, 0.3, BOWL_WATER, 0.22, 0.025, 0.018)
	fountain_streams = MeshInstance3D.new()
	fountain_streams.name = "Streams"
	fountain_streams.mesh = st.commit()
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/fountain_stream.gdshader")
	fountain_streams.material_override = smat
	fountain_streams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.add_child(fountain_streams)
	# salpicaduras donde caen los chorros (y en el cuenco de arriba)
	for i in JET_COUNT:
		var a := JET_PHASE + TAU * float(i) / float(JET_COUNT)
		_splash(f, Vector3(cos(a) * JET_LAND_R, WATER_Y + 0.02, sin(a) * JET_LAND_R), 6, 1.0)
	_splash(f, Vector3(0, BOWL_WATER + 0.02, 0), 8, 0.6)

## Un MeshInstance3D con esa malla y material, hijo de `parent`.
func _mesh_in(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi

## Un cilindro (tronco de cono) centrado en y.
func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, y: float, mat: Material, segs := 16) -> MeshInstance3D:
	var cy := CylinderMesh.new()
	cy.top_radius = r_top
	cy.bottom_radius = r_bot
	cy.height = h
	cy.radial_segments = segs
	cy.rings = 1
	var mi := _mesh_in(parent, cy, mat)
	mi.position = Vector3(0, y, 0)
	return mi

## Un anillo de piedra hueco: pared de fuera (de r_out_bot en y_out_bot a r_out en y_top), pared de dentro (r_in, de
## y_in_bot a y_top) y la cara de arriba. La piedra usa proyección triplanar, así que no hacen falta UV.
func _ring_mesh(r_in: float, r_out: float, y_top: float, y_out_bot: float, r_out_bot: float, y_in_bot: float, segs := 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP
	var slope := (r_out - r_out_bot) / maxf(0.001, y_top - y_out_bot)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		# fuera (Godot: caras delanteras en sentido horario)
		var n0 := (d0 - up * slope).normalized()
		var n1 := (d1 - up * slope).normalized()
		var t0 := d0 * r_out + up * y_top
		var t1 := d1 * r_out + up * y_top
		var b0 := d0 * r_out_bot + up * y_out_bot
		var b1 := d1 * r_out_bot + up * y_out_bot
		_tri(st, [t1, t0, b0], [n1, n0, n0])
		_tri(st, [t1, b0, b1], [n1, n0, n1])
		# dentro
		var i0 := d0 * r_in + up * y_top
		var i1 := d1 * r_in + up * y_top
		var j0 := d0 * r_in + up * y_in_bot
		var j1 := d1 * r_in + up * y_in_bot
		_tri(st, [i0, i1, j1], [-d0, -d1, -d1])
		_tri(st, [i0, j1, j0], [-d0, -d1, -d0])
		# arriba
		_tri(st, [i0, t0, t1], [up, up, up])
		_tri(st, [i0, t1, i1], [up, up, up])
	return st.commit()

func _tri(st: SurfaceTool, pts: Array, normals: Array) -> void:
	for k in 3:
		st.set_normal(normals[k])
		st.add_vertex(pts[k])

## Un chorro: un tubo fino que sale de (r0, y0) en la dirección del ángulo `a` y cae en arco hasta (r1, y1).
## `rise` lo hace subir un poco antes de caer (el surtidor). UV.y = 0 arriba, 1 donde toca el agua.
func _stream_tube(st: SurfaceTool, a: float, r0: float, y0: float, r1: float, y1: float, rise: float, w0: float, w1: float, steps := 12, sides := 6) -> void:
	var d := Vector3(cos(a), 0.0, sin(a))
	var side := Vector3(-d.z, 0.0, d.x)
	var pts := []
	for k in steps + 1:
		var s := float(k) / float(steps)
		# sale casi horizontal y cae cada vez más rápido (parábola); con `rise`, primero sube
		var y := y0 + rise * 4.0 * s * (1.0 - s) - (y0 - y1) * (s * s if rise <= 0.0 else s)
		pts.append(d * lerpf(r0, r1, s) + Vector3(0.0, y, 0.0))
	var rings := []
	for k in steps + 1:
		var p: Vector3 = pts[k]
		var tv: Vector3 = (pts[mini(k + 1, steps)] - pts[maxi(k - 1, 0)]).normalized()
		var b2 := tv.cross(side).normalized()
		var w := lerpf(w0, w1, float(k) / float(steps))
		var ring := []
		for j in sides + 1:
			var ph := TAU * float(j) / float(sides)
			var n := (side * cos(ph) + b2 * sin(ph)).normalized()
			ring.append([p + n * w, n, Vector2(float(j) / float(sides), float(k) / float(steps))])
		rings.append(ring)
	for k in steps:
		for j in sides:
			var q := [rings[k][j], rings[k][j + 1], rings[k + 1][j + 1], rings[k + 1][j]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(q[idx][1])
				st.set_uv(q[idx][2])
				st.add_vertex(q[idx][0])

## La superficie del agua: un disco con el shader del agua (dibujado antes que los chorros y las salpicaduras).
func _water_surface(parent: Node3D, sh: Shader, r: float, y: float, params: Dictionary) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = -1
	m.set_shader_parameter("center", Vector2(FOUNTAIN_POS.x, FOUNTAIN_POS.z))
	for k in params:
		m.set_shader_parameter(k, params[k])
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = 0.01
	cy.radial_segments = 40
	cy.rings = 1
	var mi := _mesh_in(parent, cy, m)
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Gotitas que saltan donde cae un chorro.
func _splash(parent: Node3D, pos: Vector3, amount: int, strength: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.42
	p.preprocess = 0.5
	p.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 0.45 * strength
	pm.initial_velocity_max = 1.05 * strength
	pm.gravity = Vector3(0, -6.5, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.1
	pm.color = Color(1.05, 1.1, 1.2)
	p.process_material = pm
	var q := _particle_quad("res://assets/props/drop.png", 0.026)
	(q.material as StandardMaterial3D).render_priority = 1
	p.draw_pass_1 = q
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-0.4, -0.2, -0.4), Vector3(0.8, 0.8, 0.8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
# --- end R3 WORLD3

# ------------------------------------------------------------------ puestos

## Un puesto: mostrador con su mercancía, postes, toldo de rayas con festón, cartel con el nombre y el vendedor detrás.
func _build_stall(v: String) -> void:
	var vd: Dictionary = Data.VENDORS[v]
	var sx: float = STALL_X[v]
	var root := Node3D.new()
	root.name = "Stall_" + v
	root.position = Vector3(sx, 0, 0)
	add_child(root)
	var wood := _mat("res://assets/tex/wood.png", "res://assets/tex/wood_n.png", 1.0, 0.8)
	var wood_l := _mat("res://assets/tex/wood_light.png", "res://assets/tex/wood_light_n.png", 1.0, 0.6)
	var wood_d := _mat("res://assets/tex/wood_dark.png", "res://assets/tex/wood_dark_n.png", 1.0, 0.8)
	_box_b(-1.15, 1.15, 0.0, 0.76, -2.2, -1.5, wood, root)
	_box_b(-1.22, 1.22, 0.76, 0.83, -2.26, -1.44, wood_l, root)
	var awning: String = vd.get("awning", "rojo")
	var cloth := _quad(Vector2(2.3, 0.36), Vector3(0, 0.62, -1.43), _tex_mat("res://assets/tex/valance_%s.png" % awning), root)
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for px in [-1.22, 1.22]:
		_box_b(px - 0.05, px + 0.05, 0.0, 2.52, -1.42, -1.32, wood_d, root)
		_box_b(px - 0.05, px + 0.05, 0.0, 3.0, -2.9, -2.8, wood_d, root)
	# toldo inclinado hacia la calle
	var aw := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.8, 1.85)
	aw.mesh = pm
	aw.material_override = _tex_mat("res://assets/tex/awning_%s.png" % awning, true)
	aw.position = Vector3(0, 2.76, -2.08)
	aw.rotation_degrees = Vector3(16.0, 0, 0)
	root.add_child(aw)
	var val := _quad(Vector2(2.8, 0.34), Vector3(0, 2.36, -1.18), _tex_mat("res://assets/tex/valance_%s.png" % awning, true), root)
	val.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# mercancía y adornos colgados
	_sprite("res://assets/props/%s.png" % vd.get("goods_art", "goods_books"), 0.025, Vector3(-0.1, 0.83, -1.86), root)
	match v:
		"ilse":
			for hx in [-1.0, 1.0]:
				_sprite("res://assets/props/%s.png" % ("lavender" if hx < 0.0 else "herbs"), 0.03, Vector3(hx, 2.38, -1.3), root, "top")
		"mabel":
			for hx in [-0.95, 0.95]:
				var l := _sprite("res://assets/props/lantern.png", 0.034, Vector3(hx, 2.38, -1.3), root, "top")
				l.shaded = false
		"borin":
			_sprite("res://assets/props/crystal_ball.png", 0.03, Vector3(0.95, 0.83, -1.95), root)
		"tobias":
			_sprite("res://assets/props/scrolls.png", 0.03, Vector3(0.85, 0.83, -1.95), root)
			_sprite("res://assets/props/books.png", 0.03, Vector3(-1.6, 0.0, -1.6), root)
		"lupo":
			_sprite("res://assets/props/barrel.png", 0.034, Vector3(1.75, 0.0, -2.2), root)
	# cartel con el nombre del puesto
	_box_b(-0.95, 0.95, 2.5, 2.86, -1.2, -1.14, wood_d, root)
	var lbl := Label3D.new()
	lbl.font = _font_sc
	lbl.text = vd.get("stall", v)
	lbl.font_size = 40
	lbl.pixel_size = 0.0058
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.12, 0.07, 0.06)
	lbl.modulate = Color(1.0, 0.92, 0.72)
	lbl.position = Vector3(0, 2.68, -1.105)
	lbl.shaded = false
	lbl.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	root.add_child(lbl)
	# el vendedor, detrás del mostrador
	var a := Actor.new()
	root.add_child(a)
	a.setup(vendor_sprite(v))
	a.quiet = true
	a.position = Vector3(-0.3, 0, -2.45)
	# --- INTEGRATE: con los sprites de 64x96 (cabezas grandes, enanos bajitos) el mostrador tapaba a los vendedores:
	# suben a un escalón escondido detrás del mostrador para que se vean cabeza y hombros (los pies no se ven)
	a.position.y = clampf(1.62 - a.top_height(), 0.0, 0.55)
	# --- end INTEGRATE
	a.face(1)
	vendors[v] = a
	# tocar el puesto
	var target := Node3D.new()
	target.position = Vector3(0, 0, -1.8)
	root.add_child(target)
	station_nodes[v] = target
	_pick(root, Vector3(2.8, 3.0, 1.7), Vector3(0, 1.5, -2.05), func(): _station_press(v),
		func(): _hover_on(v, target, 3.25), func(): _hover_off(v))

# ------------------------------------------------------------------ decorado

func _build_decor() -> void:
	# banderines sobre los puestos y estandartes en las fachadas
	var bx := [0.6, 6.8, 19.8, 26.4]
	for i in bx.size():
		var b := _sprite("res://assets/props/bunting_%s.png" % ("a" if i % 2 == 0 else "b"), 0.05, Vector3(bx[i], 4.6, -3.6 + 0.02 * (i % 2)), null, "top")   # --- R5 WORLD: (z alterna: los vecinos se tapan)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for p in [[5.4, "banner_blue"], [17.1, "banner_red"], [24.9, "banner_blue"], [33.0, "banner_red"]]:
		_sprite("res://assets/props/%s.png" % p[1], 0.045, Vector3(p[0], 4.45, FACADE_Z + 0.12), null, "top")
	# faroles, flores y cosas en el paseo delantero (quedan desenfocados en primer plano)
	for x in [0.9, 5.9, 15.2, 19.8, 24.4, 29.1]:
		_sprite("res://assets/props/lamppost.png", 0.042, Vector3(x, 0.0, -3.35))
	for x in [-3.4, 1.6, 6.2, 10.9, 14.6, 19.6, 24.0, 28.6, 33.0]:
		_sprite("res://assets/props/flowers.png", 0.034, Vector3(x, 0.16, 1.86))
	_sprite("res://assets/props/flowerpot_red.png", 0.034, Vector3(12.9, 0.16, 1.84))
	_sprite("res://assets/props/flowerpot_yellow.png", 0.034, Vector3(4.0, 0.16, 1.84))
	_sprite("res://assets/props/flowerpot_red.png", 0.034, Vector3(21.8, 0.16, 1.84))
	_sprite("res://assets/props/crate_apples.png", 0.034, Vector3(5.6, 0.0, -2.45))
	_sprite("res://assets/props/barrel.png", 0.036, Vector3(1.9, 0.0, -2.6))
	_sprite("res://assets/props/sack.png", 0.036, Vector3(2.3, 0.0, -2.2))
	_sprite("res://assets/props/crate.png", 0.036, Vector3(20.1, 0.0, -2.55))
	_sprite("res://assets/props/crate.png", 0.036, Vector3(20.05, 0.47, -2.6))
	_sprite("res://assets/props/sack.png", 0.036, Vector3(24.0, 0.0, -2.4))
	_sprite("res://assets/props/barrel.png", 0.036, Vector3(29.6, 0.0, -2.7))
	_sprite("res://assets/props/crate_apples.png", 0.034, Vector3(28.8, 0.0, -2.15))   # --- R5 WORLD: (era -2.2: el mismo plano que el barril del puesto de Lupo)
	# humo de la chimenea de la tienda   # --- R5 WORLD: (era la de la panadería, que ya no está)
	var smoke := GPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 4.0
	smoke.preprocess = 4.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.3, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.12, 0.05, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color = Color(1.0, 0.98, 0.95, 0.55)
	pm.color_ramp = _fade_ramp()
	smoke.process_material = pm
	smoke.draw_pass_1 = _particle_quad("res://assets/fx/smoke.png", 0.05)
	smoke.position = Vector3(-4.55, SHOP_H + 3.3, FACADE_Z - 1.45)   # --- R5 WORLD: (era Vector3(2.95, 8.0, FACADE_Z - 2.0))
	smoke.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)

# ------------------------------------------------------------------ la alquimista

func _build_alchemist() -> void:
	alchemist = Actor.new()
	add_child(alchemist)
	alchemist.setup("alquimista")
	walker = Walker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.speed = 3.0
	walker.auto_speed = 3.6
	var st := {"tienda": {"x": SHOP_DOOR_X, "face": -1, "zone": Vector2(X0 - 1.0, -0.6), "name": "Back to the shop"}}
	for v in STALL_X:
		var sx: float = STALL_X[v]
		st[v] = {"x": sx + 1.3, "face": -1, "zone": Vector2(sx - 1.4, sx + 2.0), "name": Data.VENDORS[v]["stall"]}
	walker.stations = st
	walker.setup(alchemist, [Vector2(X0, LANE_Z), Vector2(X1, LANE_Z)], SHOP_DOOR_X + 0.6, 1)
	walker.station_reached.connect(func(id): station_reached.emit(id))
	walker.station_left.connect(func(id): station_left.emit(id))

func _pick_floor() -> void:
	var a := Area3D.new()
	a.name = "Floor"
	a.monitoring = false
	a.monitorable = false
	a.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(X1 - X0 + 6.0, 0.1, 5.4)
	cs.shape = bs
	cs.position = Vector3((X0 + X1) / 2.0, -0.05, -0.5)
	a.add_child(cs)
	a.input_event.connect(func(_cam, ev, pos, _n, _i):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if walker.can_walk.is_valid() and walker.can_walk.call():
				walker.go_to(clampf(pos.x, X0, X1)))
	add_child(a)

## Llega desde la tienda: aparece en su puerta y baja a la calle.
func enter(intro := true) -> void:
	camera.current = true
	_refresh_facade()   # --- R5 WORLD
	walker.frozen = intro
	walker.teleport(SHOP_DOOR_X + 0.7, 1)
	if intro:
		alchemist.position = Vector3(SHOP_DOOR_X, 0, FACADE_Z + 0.25)
		alchemist.face(1)
	snap_camera()
	_scatter_crowd()
	_enter_gen += 1
	if intro:
		_step_out(_enter_gen)

func _step_out(gen: int) -> void:
	await alchemist.walk_to(walker.point(SHOP_DOOR_X + 0.7), 2.4)
	if gen != _enter_gen:
		return
	# ya está en el punto del carril donde la dejó enter(): sigue desde ahí (sin cancelar un clic hecho mientras bajaba)
	walker.frozen = false

## Se va: entra por la puerta de su tienda (main.gd funde a negro mientras tanto).
func enter_shop_door() -> void:
	walker.frozen = true
	alchemist.walk_to(Vector3(SHOP_DOOR_X, 0, FACADE_Z + 0.25), 2.4)

func leave() -> void:
	_hover_off(_hover)
	walker.stop()
	walker.frozen = false

# ------------------------------------------------------------------ estaciones (puestos y puerta)

func _station_press(id: String) -> void:
	if can_use.is_valid() and not can_use.call(id):
		return
	use_station(id)

## Camina hasta el puesto (o la puerta) y emite station_clicked al llegar.
func use_station(id: String) -> bool:
	if not await walker.go_station(id):
		return false
	station_clicked.emit(id)
	return true

func go_station(id: String) -> bool:
	return await walker.go_station(id)

func at_station(id: String) -> bool:
	return walker.current == id

## El vendedor saluda a la alquimista cuando llega a su puesto.
func greet(v: String) -> void:
	if not vendors.has(v):
		return
	var a: Actor = vendors[v]
	a.face(1)
	a.hop(1, 0.12)
	a.emote(["heart", "note", "sparkle"].pick_random(), 1.4)

func set_station_label(id: String, text: String) -> void:
	_label_text[id] = text

func _hover_on(id: String, n: Node3D, h: float) -> void:
	_hover = id
	_label.text = _label_text.get(id, walker.stations[id]["name"] if walker.stations.has(id) else id)
	_label.global_position = n.global_position + Vector3(0, h, 0.4)
	_label.visible = true

func _hover_off(id: String) -> void:
	if _hover == id and _label:
		_hover = ""
		_label.visible = false

## Puestos y puerta para el cursor del mando (LB / RB): [[Node3D, altura], ...].
func pad_picks() -> Array:
	var out := []
	for id in station_nodes:
		out.append([station_nodes[id], 1.3])
	return out

func screen_pos(p: Vector3) -> Vector2:
	return camera.unproject_position(p)

func _cam_goal() -> float:
	return clampf(alchemist.position.x + alchemist.facing * 0.6, CAM_X0, CAM_X1)

func snap_camera() -> void:
	_cam_x = _cam_goal()

# ------------------------------------------------------------------ gente que pasea

func _build_crowd() -> void:
	var used := {}
	for v in STALL_X:
		used[vendor_sprite(v)] = true
	var pool := []
	for id in CROWD:
		if not used.has(id) and _has_sprite(id):
			pool.append(id)
	pool.shuffle()
	if pool.size() < 8:
		# hasta que existan los dibujos del elenco nuevo, también pasean los sprites que hacen de vendedor
		for id in CROWD:
			if used.has(id) and _has_sprite(id) and not pool.has(id):
				pool.append(id)
	for i in mini(CROWD_MAX, pool.size()):
		var a := Actor.new()
		add_child(a)
		a.setup(pool[i])
		a.quiet = true
		var passer := i % 3 == 2
		# --- R5 WORLD: cada vecino tiene su propia profundidad dentro del carril, de 2,4 en 2,4 cm (-10,8..+10,8 cm),
		# contando el desvío de 0-3,5 cm que Actor ya le da al dibujo: dos que se paran o caminan por el mismo carril
		# nunca quedan en el mismo plano (al cruzarse, su borde temblaba). Antes iban al carril ± 10-12 cm al azar.
		var dz: float = (i - (CROWD_MAX - 1) / 2.0) * 0.024 - a.sprite.position.z
		var n := {"a": a, "x": 0.0, "z": 0.0, "tx": 0.0, "tz": 0.0, "speed": randf_range(1.0, 1.5),
			"wait": 0.0, "pass": passer, "greet": randf_range(2.0, 6.0), "dz": dz}
		npcs.append(n)
	_scatter_crowd()

## Reparte a la gente por la calle (al llegar al mercado).
func _scatter_crowd() -> void:
	var i := 0
	for n in npcs:
		n["x"] = randf_range(X0 + 2.0, X1 + 2.0) if i % 2 == 0 else randf_range(1.0, 12.0)
		i += 1
		n["z"] = NPC_LANES.pick_random() if not n["pass"] else NPC_LANES[1 + randi() % 2]
		if absf(n["x"] - SHOP_DOOR_X) < 2.5:
			n["x"] += 4.0
		n["tx"] = n["x"]
		n["tz"] = n["z"]
		n["wait"] = randf_range(0.0, 3.0)
		var a: Actor = n["a"]
		a.position = Vector3(n["x"], 0, n["z"] + n.get("dz", 0.0))   # --- R5 WORLD: (+ dz)
		a.face(1 if randf() < 0.5 else -1)
		a.set_walking(false)

func _npc_next(n: Dictionary) -> void:
	if n["pass"]:
		# cruza el mercado de punta a punta y vuelve a entrar por el otro lado
		if n["x"] > X1 + 4.0:
			n["x"] = X0 - 8.0
		elif n["x"] < X0 - 7.0:
			n["x"] = X1 + 5.0
		n["tx"] = X1 + 5.5 if n["x"] < 10.0 else X0 - 8.5
		n["tz"] = n["z"]
		return
	if randf() < 0.4:
		# a mirar un puesto
		var v: String = STALL_X.keys().pick_random()
		n["tx"] = float(STALL_X[v]) + randf_range(-0.9, 0.9)
		n["tz"] = NPC_LANES[0]   # --- R5 WORLD: (era + randf_range(-0.1, 0.1): ahora la variedad la pone "dz")
	else:
		n["tx"] = clampf(n["x"] + randf_range(-8.0, 8.0), X0 + 1.5, X1 + 1.0)
		n["tz"] = NPC_LANES[randi() % NPC_LANES.size()]   # --- R5 WORLD: (era + randf_range(-0.12, 0.12))

func _npc_arrive(n: Dictionary) -> void:
	var a: Actor = n["a"]
	n["wait"] = randf_range(1.8, 5.5) if not n["pass"] else 0.05
	if n["pass"]:
		return
	# ¿delante de un puesto? lo mira y a veces compra algo
	for v in STALL_X:
		var sx: float = STALL_X[v]
		if absf(n["x"] - sx) < 1.3 and n["z"] < -0.8:
			a.face(-1 if n["x"] > sx - 0.35 else 1)
			if randf() < 0.45:
				a.emote(["coin", "note", "heart"].pick_random(), 1.3)
			return
	# si hay alguien cerca esperando, charlan
	for m in npcs:
		if not is_same(m, n) and m["wait"] > 0.5 and not m["pass"] and Vector2(m["x"] - n["x"], m["z"] - n["z"]).length() < 1.8:
			a.face(1 if m["x"] > n["x"] else -1)
			var b: Actor = m["a"]
			b.face(1 if n["x"] > m["x"] else -1)
			a.emote("dots", 1.5)
			m["wait"] = maxf(m["wait"], n["wait"])
			return
	if randf() < 0.15:
		a.emote(["note", "sparkle"].pick_random(), 1.2)

func _update_crowd(delta: float) -> void:
	var me := Vector2(alchemist.position.x, alchemist.position.z)
	for n in npcs:
		var a: Actor = n["a"]
		n["greet"] -= delta
		if n["wait"] > 0.0:
			n["wait"] -= delta
			# saluda a la alquimista si pasa cerca
			if n["greet"] <= 0.0 and me.distance_to(Vector2(n["x"], n["z"])) < 1.5:
				n["greet"] = randf_range(18.0, 30.0)
				a.face(1 if me.x > n["x"] else -1)
				a.emote(["heart", "note"].pick_random(), 1.4)
			if n["wait"] <= 0.0:
				_npc_next(n)
			continue
		var to := Vector2(n["tx"] - n["x"], n["tz"] - n["z"])
		var step: float = n["speed"] * delta
		if to.length() <= step:
			n["x"] = n["tx"]
			n["z"] = n["tz"]
			a.set_walking(false)
			_npc_arrive(n)
		else:
			var d := to.normalized() * step
			n["x"] += d.x
			n["z"] += d.y
			if absf(to.x) > 0.05:
				a.face(1 if to.x > 0.0 else -1)
			a.set_walking(true)
		a.position = Vector3(n["x"], 0, n["z"] + n.get("dz", 0.0))   # --- R5 WORLD: (+ dz)

# ------------------------------------------------------------------ palomas y golondrinas

func _bird_frames(path: String, w: int, h: int, anims: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var tex := _tex(path)
	for an in anims:
		sf.add_animation(an[0])
		sf.set_animation_speed(an[0], an[2])
		sf.set_animation_loop(an[0], true)
		for fi in an[1]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(fi * w, 0, w, h)
			sf.add_frame(an[0], at)
	return sf

func _build_pigeons() -> void:
	var sf := _bird_frames("res://assets/props/pigeon.png", 12, 10, [["peck", [0, 1, 0, 0], 3.0], ["fly", [2, 3], 11.0]])
	var homes := [Vector3(11.2, 0, -1.7), Vector3(12.0, 0, -1.9), Vector3(14.1, 0, -1.6), Vector3(5.2, 0, 1.2),
		Vector3(18.6, 0, 1.4), Vector3(24.5, 0, 0.9), Vector3(0.8, 0, 1.0)]
	for hp in homes:
		var s := AnimatedSprite3D.new()
		s.sprite_frames = sf
		s.pixel_size = 0.03
		s.centered = false
		s.offset = Vector2(-6, 0)
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = true
		s.position = hp
		s.flip_h = randf() < 0.5
		add_child(s)
		s.play("peck")
		s.frame = randi() % 4
		s.speed_scale = randf_range(0.7, 1.3)
		pigeons.append({"s": s, "state": "ground", "vel": Vector3.ZERO, "t": randf_range(1.0, 4.0), "home": hp})

func _update_pigeons(delta: float) -> void:
	var walkers := [alchemist.position]
	for n in npcs:
		if n["wait"] <= 0.0:
			walkers.append(Vector3(n["x"], 0, n["z"]))
	for pg in pigeons:
		var s: AnimatedSprite3D = pg["s"]
		match pg["state"]:
			"ground":
				pg["t"] -= delta
				if pg["t"] <= 0.0:
					pg["t"] = randf_range(1.5, 4.0)
					s.flip_h = not s.flip_h if randf() < 0.4 else s.flip_h
					if randf() < 0.3:
						var hop := Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.15, 0.15))
						var tw := s.create_tween()
						tw.tween_property(s, "position", s.position + hop, 0.25)
				for w in walkers:
					if Vector2(w.x - s.position.x, w.z - s.position.z).length() < 1.25:
						var away := signf(s.position.x - w.x)
						if away == 0.0:
							away = 1.0
						pg["vel"] = Vector3(away * randf_range(1.8, 2.8), randf_range(2.2, 3.0), randf_range(-0.6, 0.2))
						pg["state"] = "fly"
						pg["t"] = 2.2
						s.flip_h = away < 0.0
						s.play("fly")
						if s.is_visible_in_tree() and w == walkers[0]:
							Sfx.play("page", 0.3, -14.0)
						break
			"fly":
				pg["t"] -= delta
				s.position += pg["vel"] * delta
				if pg["t"] <= 0.0:
					s.visible = false
					pg["state"] = "gone"
					pg["t"] = randf_range(6.0, 12.0)
			"gone":
				pg["t"] -= delta
				if pg["t"] <= 0.0:
					var home: Vector3 = pg["home"]
					if Vector2(alchemist.position.x - home.x, alchemist.position.z - home.z).length() < 3.0:
						pg["t"] = 2.0   # ella sigue cerca: espera un poco más
					else:
						s.position = home + Vector3(-1.5, 2.6, 0)
						s.visible = true
						s.flip_h = false
						pg["state"] = "land"
						pg["t"] = 0.9
			"land":
				pg["t"] -= delta
				var home2: Vector3 = pg["home"]
				s.position = s.position.lerp(home2, 1.0 - exp(-5.0 * delta))
				if pg["t"] <= 0.0:
					s.position = home2
					s.play("peck")
					pg["state"] = "ground"
					pg["t"] = randf_range(1.0, 3.0)

func _update_swallows(delta: float) -> void:
	_swallow_t -= delta
	if _swallow_t > 0.0:
		return
	_swallow_t = randf_range(7.0, 14.0)
	if _swallow_frames == null:
		_swallow_frames = _bird_frames("res://assets/props/swallow.png", 12, 7, [["fly", [0, 1], 9.0]])
	var sf := _swallow_frames
	var count := randi_range(2, 4)
	var y := randf_range(4.0, 4.7)
	var x_from := _cam_x + 9.0
	for i in count:
		var s := AnimatedSprite3D.new()
		s.sprite_frames = sf
		s.pixel_size = 0.035
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = false
		s.flip_h = true
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(x_from + i * randf_range(0.6, 1.2), y + randf_range(-0.3, 0.3), randf_range(-1.5, 0.5))
		add_child(s)
		s.play("fly")
		var dur := randf_range(2.6, 3.4)
		var tw := s.create_tween()
		tw.tween_property(s, "position", s.position + Vector3(-19.0, randf_range(-0.4, 0.8), 0), dur)
		tw.tween_callback(s.queue_free)

# ------------------------------------------------------------------ cada cuadro

func _process(delta: float) -> void:
	_t += delta
	if alchemist == null:
		return
	_cam_x = lerpf(_cam_x, _cam_goal(), 1.0 - exp(-2.6 * delta))
	var off := Vector3(_cam_x, 0.0, 0.0)
	camera.position = _cam_base + off + Vector3(sin(_t * 0.11) * 0.08, sin(_t * 0.17) * 0.04, 0.0)
	camera.look_at(_cam_target + off, Vector3.UP)
	fill.position.x = _cam_x + 0.5
	_update_crowd(delta)
	_update_pigeons(delta)
	_update_swallows(delta)
