extends SetKit
class_name StreetWorld
## --- SS CORE: la calle frente a la tienda, el Starfall Market de la mañana (HD-2D): casas de adobe y chatarra con
## cúpula, la fachada de Nell con el cartel de la estrella remendada (una punta encendida por cada día bueno: Game.
## sign_points) y su puerta ("Open shop"), el puesto de cápsulas de Raker con la tortuga de las dunas cargada de
## chatarra, el puesto de piezas de Mags, plataformas de aterrizaje con naves (una despega cada tanto), el gran sol
## ámbar y el anillo de restos en el cielo. De noche (la introducción): estrellas y la lluvia de chatarra.
## Nell camina por la calle (Walker) entre la puerta y los puestos; Kettle la sigue.

const LANE_Z := -1.6
# --- SS2 WORLD: la calle más ancha (§6.6) para la vecina (Shine Again), el patio de Dolly y el tablón (era -9.6 .. 9.0)
const LANE := [Vector2(-11.6, -1.6), Vector2(12.4, -1.6)]
const SHOP_X := -6.2           # la puerta de la tienda de Nell
const PODS_X := 2.75           # el puesto de Raker (el centro del toldo)
const PARTS_X := 8.2           # el puesto de Mags
## Raker y Mags están DELANTE, a un lado de su puesto (así se los ve enteros; detrás del mostrador solo asomaba la
## cabeza); la tortuga de las dunas, entre la casa de Nell y el puesto de Raker.
const RAKER_POS := Vector3(0.5, 0.0, -2.7)
const MAGS_POS := Vector3(5.85, 0.0, -2.7)
const STATIONS := {
	"door": {"x": -6.2, "face": -1, "zone": Vector2(-7.6, -4.8), "name": "Your shop", "y": 2.5, "ax": -6.2, "az": -4.0},
	# --- POLISH FIX (F2): Nell se para delante de las cápsulas (x 2.3, ya no encima de Raker en 0.5) y el aviso va sobre
	# el puesto; la zona de clic cubre a Raker y al puesto (RAKER_POS no se mueve: la gala lo toma prestado)
	"pods": {"x": 2.3, "face": -1, "zone": Vector2(0.0, 3.5), "name": "Raker's pods", "y": 2.0, "ax": 1.6, "az": -2.7,
		"pick": Vector3(3.0, 2.2, 1.2)},
	# --- end POLISH FIX
	"parts": {"x": 6.8, "face": -1, "zone": Vector2(5.0, 8.8), "name": "Mags's parts", "y": 2.0, "ax": 5.85, "az": -2.7},
	# --- SS2 WORLD: las tres estaciones nuevas (x, zona e id de la ronda 2: S las usa)
	"rival": {"x": -11.0, "face": -1, "zone": Vector2(-11.6, -9.9), "name": "Shine Again", "y": 2.4, "ax": -11.6, "az": -3.4},
	"fittings": {"x": 11.2, "face": -1, "zone": Vector2(10.2, 12.4), "name": "Dolly's Fittings", "y": 2.3, "ax": 11.9, "az": -3.0},
	"board": {"x": -4.0, "face": -1, "zone": Vector2(-4.7, -3.3), "name": "Notice board", "y": 2.4, "ax": -4.0, "az": -3.9},
}

var star_sign: Sprite3D
var door_sprite: Sprite3D
var raker: Actor
var mags: Actor
var tortoise: Sprite3D
var pod_sprites: Array = []     # las cápsulas sobre el mostrador de Raker (se esconden al venderlas)
var walkers: Array = []         # gente que pasa por detrás (sin pasos)
var ring: Sprite3D
var sun_sprite: Sprite3D
var _night_nodes: Array = []
var _day_nodes: Array = []
var _lamps: Array = []
var _beetle_parked: Sprite3D
var _beetle_flyer := {}
const SUN_DAY := 1.32   # --- POLISH LOOK (P2): antes 1.45 (las fachadas de frente ya no se queman)
# --- POLISH LOOK (P2): la luz de día en un solo lugar (la mañana, la vuelta después del Scour y de la noche). Antes
# todo caía en la misma banda beige clara (cielo (0.86, 0.5, 0.3) arriba, arena casi blanca): ahora un cénit de polvo
# más profundo, el horizonte ámbar de siempre, la arena un poco más oscura, más contraste y menos luz ambiente (las
# sombras bajo los puestos se leen). Un solo sol, como siempre.
const DAY_TOP := Vector3(0.62, 0.34, 0.22)       # antes (0.86, 0.5, 0.3)
const DAY_HOR := Vector3(0.94, 0.7, 0.46)         # antes (1.0, 0.8, 0.55): el mismo ámbar, menos pálido
const DAY_BRIGHT := 0.95                          # antes 1.05
const DAY_AMB := Color(0.78, 0.7, 0.66)
const DAY_AMB_E := 0.5                            # antes 0.62
const DAY_BG := Color(0.98, 0.8, 0.56)
const DAY_CONTRAST := 1.12                        # antes 1.08
const DAY_EXPOSURE := 0.86                        # antes 0.94 (la arena y las paredes ya no se queman)
const SAND_TINT := Color(0.8, 0.79, 0.77)        # antes blanco (la arena casi blanca)
const RING_DAY := Color(0.8, 0.86, 0.98)          # antes (1.05, 0.95, 0.85): de día, acero pálido (no una mancha)
const DRIFT_DAY := Color(1.3, 0.9, 0.56)          # --- POLISH LOOK (P4): la arena amontonada, tibia (no azulada)
const STORM_SUN := Color(0.7, 0.55, 0.4)            # --- POLISH LOOK (P4): el sol tapado por el polvo (antes (1.0, 0.82, 0.6))
# --- POLISH LOOK (P13): la franja lejana de dunas y mesetas (assets/props/horizon_strip.png, de ss_world.py horizon):
# corta la línea recta del piso contra el cielo. Sin luz y con alfa recortada, como el sol y el anillo (nada que
# compilar); malva polvoriento de día, violeta hondo de noche.
const HORIZON_DAY := Color(0.8, 0.58, 0.5)
const HORIZON_NIGHT := Color(0.2, 0.13, 0.27)
var _horizon: Array = []
# --- end POLISH LOOK
const NIGHT_EXPOSURE := 0.94                      # la noche (la introducción, la gala) queda como estaba
const NIGHT_CONTRAST := 1.08
var _sand_mat: StandardMaterial3D                 # la arena: SAND_TINT de día, blanca de noche (como antes)
# --- end POLISH LOOK

func build() -> void:
	for st in build_steps():
		st.call()

## --- BOOT: el armado en pasos cortos (main.gd hace uno por cuadro al arrancar; build() los hace todos juntos).
func build_steps() -> Array[Callable]:
	return [_build_base, _build_ground_and_sky, _build_far, _build_shop_facade, _build_stalls, _build_people,
		_build_nell_kettle, _build_neighbours, _build_sky_and_events]   # --- SS2 WORLD: + 2 pasos

func _build_base() -> void:
	name = "StreetWorld"
	setup_camera_env(false)
	# la luz del sol de la mañana: arriba a la derecha y un poco desde delante (ilumina las fachadas)
	sun.rotation_degrees = Vector3(-40.0, 44.0, 0.0)
	sun.light_energy = SUN_DAY   # --- POLISH LOOK (P2)
	sun.light_color = Color(1.0, 0.88, 0.7)
	cam_x0 = -6.0   # --- SS2 WORLD: la cámara llega a la vecina y al patio de Dolly (era -4.6 .. 4.4)
	cam_x1 = 6.4
	cam_height = 4.3
	cam_dist = 12.0
	cam_look_y = 2.2
	cam_look_z = -4.0
	env.ambient_light_energy = DAY_AMB_E   # --- POLISH LOOK (P2): antes 0.6
	env.tonemap_exposure = DAY_EXPOSURE   # --- POLISH LOOK (P2)
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = DAY_CONTRAST   # --- POLISH LOOK (P2)
	fill.position = Vector3(0.0, 3.4, 5.0)
	fill.light_energy = 0.3

func _build_nell_kettle() -> void:
	setup_nell(LANE, STATIONS, SHOP_X + 0.9)
	setup_kettle(Vector3(SHOP_X - 0.1, 0, LANE_Z + KETTLE_DZ))
	refresh_sign()

func _build_ground_and_sky() -> void:
	var sand := mat("res://assets/tex/sand.png", 0.45, SAND_TINT)   # --- POLISH LOOK (P2)
	_sand_mat = sand
	box_b(-60.0, 60.0, -0.2, 0.0, -70.0, 10.0, sand)
	var sky := sky_backdrop(Vector2(170.0, 46.0), Vector3(0.0, 16.0, -52.0))
	sky.name = "StreetSky"
	var sm: ShaderMaterial = sky.material_override
	sm.set_shader_parameter("day_top", DAY_TOP)   # --- POLISH LOOK (P2)
	sm.set_shader_parameter("day_hor", DAY_HOR)
	sm.set_shader_parameter("bright", DAY_BRIGHT)
	# el anillo de restos (el astillero viejo) y el sol grande, ámbar
	ring = prop("sky_ring", RING_POS, RING_PX, "center", 0, false)   # --- SS2 WORLD: el anillo v2 (fino, roto, inclinado)
	ring.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	ring.modulate = RING_DAY   # --- POLISH LOOK (P2)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun_sprite = prop("sun", Vector3(15.5, 8.0, -51.0), 0.05, "center", 0, false)
	sun_sprite.modulate = Color(1.25, 1.12, 0.95)
	sun_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_day_nodes.append(sun_sprite)
	# --- POLISH LOOK (P13): dos tramos de 85 m, justo delante del fondo del cielo, apoyados bajo el piso
	for hx in [-42.5, 42.5]:
		var hz := sprite("res://assets/props/horizon_strip.png", 0.166, Vector3(hx, -0.35, -51.3), "bottom", null, false)
		hz.modulate = HORIZON_DAY
		hz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_horizon.append(hz)
	# --- end POLISH LOOK
	# la lluvia de chatarra en el cielo (de noche)
	setup_streaks(AABB(Vector3(-24.0, 7.0, -48.0), Vector3(44.0, 9.0, 1.0)), 11, 0.1)

## Lo de atrás: casas con cúpula, el tanque de agua, antenas, las plataformas con sus naves, naves que despegan.
func _build_far() -> void:
	var adobe := mat("res://assets/tex/adobe.png", 0.3)
	var adobe_d := mat("res://assets/tex/adobe.png", 0.3, Color(0.86, 0.8, 0.76))
	var rust := mat("res://assets/tex/rusted_panel.png", 0.5)
	for d in [[-19.0, -13.0, 3.0, adobe], [-12.5, -16.5, 2.4, adobe_d], [13.0, -13.5, 2.8, adobe], [19.5, -17.0, 3.2, adobe_d],
			[6.5, -19.0, 2.2, adobe_d], [-4.0, -21.0, 2.0, adobe_d], [26.0, -12.0, 2.6, adobe]]:
		var x: float = d[0]
		var z: float = d[1]
		var w: float = d[2]
		box_b(x - w, x + w, 0.0, w * 1.05, z - w, z + w, d[3])
		prop("dome_cap", Vector3(x, w * 1.05 - 0.05, z + w + 0.02), w * 2.0 / 88.0)
		var wx := x - w * 0.42
		prop("round_window", Vector3(wx, w * 0.6, z + w + 0.03), 0.028, "center")
		var lit := prop("round_window", Vector3(wx, w * 0.6, z + w + 0.035), 0.028, "center", 0, false)
		lit.modulate = Color(1.7, 1.3, 0.7)
		lit.visible = false
		_night_nodes.append(lit)
		prop("scrap_patch_b", Vector3(x + w * 0.45, w * 0.42, z + w + 0.03), 0.034, "center")
	prop("well_tower", Vector3(3.4, 0.0, -15.0), 0.056)
	prop("antenna_mast", Vector3(10.2, 2.9, -11.4), 0.05)
	prop("antenna_mast", Vector3(-15.5, 3.1, -11.0), 0.045)
	box_b(9.0, 11.6, 0.0, 2.9, -12.4, -10.4, rust)
	# las plataformas de aterrizaje, en alto sobre patas de chapa (así se ven por encima de las cúpulas): el
	# carguero cabeza de martillo posado a la izquierda; a la derecha, el escarabajo, que despega cada tanto
	_landing_pad(Vector3(-14.0, 0.0, -31.0), 5.2, 5.2, rust)
	var freighter := prop("ship_hammerhead", Vector3(-14.0, 5.2, -30.7), 0.05, "bottom")
	freighter.name = "Freighter"
	_day_nodes.append(freighter)   # de noche ya despegó (la introducción y el final miran el anillo, sin naves)
	_landing_pad(Vector3(10.5, 0.0, -27.0), 4.0, 3.4, rust)
	_beetle_parked = prop("ship_beetle", Vector3(10.5, 3.4, -26.7), 0.05, "bottom")
	_beetle_parked.name = "BeetleParked"
	_beetle_flyer = add_flyer("ship_beetle", 0.05, Vector3(10.5, 5.2, -26.7), Vector3(5.0, 24.0, -34.0), 7.0, 34.0, Vector3(2.9, -0.1, -0.02), -90.0, 9.0, "takeoff")
	# el correo aguja cruza el cielo
	add_flyer("ship_needle", 0.05, Vector3(-40.0, 14.0, -44.0), Vector3(40.0, 16.0, -44.0), 6.5, 23.0, Vector3(-4.4, 0.0, -0.05), 90.0, 3.0)

## Una plataforma de aterrizaje en alto: un disco de chapa sobre cuatro patas y una escalera de servicio.
func _landing_pad(c: Vector3, r: float, h: float, leg_m: Material) -> void:
	var pad_m := mat("res://assets/tex/metal_plate.png", 0.35, Color(0.8, 0.77, 0.72), 0.6)
	cylinder(Vector3(c.x, h - 0.35, c.z), r, 0.35, pad_m, null, 28)
	cylinder(Vector3(c.x, h - 0.55, c.z), r * 0.8, 0.2, flat(Color(0.3, 0.26, 0.24)), null, 20)
	for dx in [-0.55, 0.55]:
		for dz in [-0.45, 0.45]:
			box_b(c.x + dx * r - 0.22, c.x + dx * r + 0.22, 0.0, h - 0.5, c.z + dz * r - 0.22, c.z + dz * r + 0.22, leg_m)
	# luces de aterrizaje en el borde (ámbar)
	for k in 5:
		var a := -PI * 0.15 - k * PI * 0.175
		var lp := Vector3(c.x + cos(a) * r * 0.98, h + 0.02, c.z - sin(a) * r * 0.98)
		box_b(lp.x - 0.12, lp.x + 0.12, lp.y, lp.y + 0.12, lp.z - 0.12, lp.z + 0.12, flat(Color(1.0, 0.7, 0.3), true), null, false)

## La fachada de la tienda de Nell: adobe y chapa, la puerta, la placa con el nombre y el cartel de la estrella.
func _build_shop_facade() -> void:
	var adobe := mat("res://assets/tex/adobe.png", 0.3, Color(1.0, 0.95, 0.9))
	var plate := mat("res://assets/tex/metal_plate.png", 0.6, Color.WHITE, 0.6)
	var rust := mat("res://assets/tex/rusted_panel.png", 0.55)
	var x0 := -10.4
	var x1 := -2.4
	box_b(x0, x1, 0.0, 3.7, -8.0, -4.0, adobe)
	box_b(x0, x1, 3.7, 3.95, -8.1, -3.85, rust)
	# zócalo de chapa a los lados de la puerta
	box_b(x0, SHOP_X - 0.85, 0.0, 0.7, -4.0, -3.96, plate)
	box_b(SHOP_X + 0.85, x1, 0.0, 0.7, -4.0, -3.96, plate)
	# la puerta (el dibujo entero, con su marco beige): CLOSED de mañana
	door_sprite = prop("door", Vector3(SHOP_X, 0.0, -3.95), 0.035, "bottom", 0)
	door_sprite.name = "ShopDoor"
	prop("shop_plate", Vector3(SHOP_X, 3.3, -3.94), 0.02, "center")
	prop("round_window", Vector3(-8.7, 1.9, -3.95), 0.034, "center")
	# --- SS2 WORLD: la ventana redonda de la derecha deja su lugar al tablón de anuncios (x -4.0); el parche, más arriba
	prop("scrap_patch_a", Vector3(-9.3, 0.95, -3.95), 0.036, "center")
	prop("scrap_patch_b", Vector3(-2.95, 2.75, -3.95), 0.034, "center")
	prop("vent_pipe", Vector3(-9.4, 3.95, -6.0), 0.045)
	prop("crate_stack", Vector3(-2.9, 0.0, -3.4), 0.03)
	# el cartel de la estrella remendada, en un poste sobre el techo
	box_b(SHOP_X - 0.06, SHOP_X + 0.06, 3.9, 4.3, -5.0, -4.88, flat(Color(0.25, 0.22, 0.2)))
	star_sign = prop("star_sign_0", Vector3(SHOP_X, 4.0, -4.82), 0.031)
	star_sign.name = "StarSign"
	# una lámpara junto a la puerta (de noche)
	var l := omni(Vector3(SHOP_X + 1.0, 2.6, -3.3), Color(1.0, 0.72, 0.42), 0.0, 4.5)
	_lamps.append(l)
	# la casa vecina de la izquierda, con cúpula
	box_b(-17.0, -10.6, 0.0, 3.0, -9.0, -4.6, mat("res://assets/tex/adobe.png", 0.3, Color(0.92, 0.86, 0.8)))
	# --- SS2 WORLD: la casa de al lado es Shine Again desde el día 3 (_build_neighbours): su cúpula, su puerta en arco y
	# su ventana se guardan para cambiarlas
	_nb_dome = prop("dome_cap", Vector3(-13.8, 2.95, -4.58), 6.0 / 88.0)
	_nb_old.append(prop("arch_door", Vector3(-12.2, 0.0, -4.57), 0.045))
	_nb_old.append(prop("round_window", Vector3(-15.4, 1.8, -4.57), 0.03, "center"))

## Los dos puestos: cápsulas (Raker, con la tortuga) y piezas (Mags).
func _build_stalls() -> void:
	prop("stall_canopy_red", Vector3(PODS_X, 0.0, -3.3), 0.045)
	tortoise = prop("tortoise", Vector3(-1.3, 0.0, -3.7), 0.0222)
	tortoise.name = "Tortoise"
	for i in 3:
		var p := sprite("res://assets/items/pod_closed.png", 0.0115, Vector3(PODS_X - 0.8 + i * 0.66, 0.84, -3.18))
		p.name = "Pod%d" % i
		pod_sprites.append(p)
	prop("stall_canopy_teal", Vector3(PARTS_X, 0.0, -3.3), 0.045)
	var parts := ["cell", "coil", "lens", "speaker"]
	for i in parts.size():
		sprite("res://assets/parts/%s.png" % parts[i], 0.0125, Vector3(PARTS_X - 0.95 + i * 0.58, 0.86, -3.18))
	prop("crate_stack", Vector3(PARTS_X + 2.6, 0.0, -3.6), 0.03)
	prop("crate", Vector3(PARTS_X + 2.0, 0.0, -2.9), 0.03)
	prop("crate", Vector3(PODS_X + 2.35, 0.0, -3.4), 0.028)
	# un cobertizo de chapa a la derecha
	var rust := mat("res://assets/tex/rusted_panel.png", 0.5)
	box_b(11.0, 14.8, 0.0, 3.0, -7.5, -4.4, rust)
	prop("vent_pipe", Vector3(13.6, 3.0, -5.6), 0.04)
	for i in 2:
		var ll := omni(Vector3(PODS_X + i * (PARTS_X - PODS_X), 2.7, -2.6), Color(1.0, 0.74, 0.46), 0.0, 4.0)
		_lamps.append(ll)

## La gente del puerto: Raker y Mags en sus puestos, y dos o tres clientes que pasean por detrás.
func _build_people() -> void:
	raker = make_actor("raker", RAKER_POS, 1)
	mags = make_actor("mags", MAGS_POS, 1)
	# (detrás de los puestos, a la derecha de la tortuga: nunca dentro de una casa ni detrás de la tortuga)
	for spec in [["oona", 4.0, -8.6, 0.55], ["gorrum", 9.5, -9.0, 0.42], ["pipip", 6.5, -9.4, 0.7]]:
		var a := make_actor(spec[0], Vector3(spec[1], 0.0, spec[2]), 1)
		a.quiet = true
		walkers.append({"a": a, "speed": spec[3], "dir": 1 if randf() < 0.5 else -1, "x0": 2.6, "x1": 13.0, "pause": randf_range(0.0, 3.0)})

## Las frases de Raker y Mags van más arriba: sobre su cabeza ya está el aviso "[E] Buy pods".
func _blurt_lift(a: Node3D) -> float:
	return 0.6 if a == raker or a == mags else 0.0

## Las puntas encendidas del cartel (Game.sign_points) y el cartel de la puerta (OPEN al abrir).
func refresh_sign() -> void:
	var n := clampi(Game.sign_points, 0, 5)
	# --- SS2 WORLD: las texturas ya cargadas al armar (nada de cargar en el camino); con el cometa puesto (la noche del
	# cometa o después de la corona) se ve el cartel con la cola de bronce
	star_sign.texture = _sign_tex[n] if n < _sign_tex.size() else load("res://assets/props/star_sign_%d.png" % n)
	var comet := _comet_on or Game.crown_seen
	star_sign.visible = not comet
	# (P1) Legend of the Drift: el cartel con un ribete dorado (sin arte nuevo: un tinte dorado)
	var legend := String(Season.rep_tier().get("id", "")) == "legend"
	star_sign.modulate = Color(1.3, 1.12, 0.62) if legend else Color.WHITE
	if comet_sign:
		comet_sign.visible = comet

func set_door_open_sign(open: bool) -> void:
	door_sprite.frame = 1 if open else 0

## Cuántas cápsulas quedan en el puesto (las que se ven sobre el mostrador).
func set_pods_left(n: int) -> void:
	for i in pod_sprites.size():
		pod_sprites[i].visible = i < n

func set_night(on: bool) -> void:
	super.set_night(on)
	sun.visible = true
	sun.light_energy = 0.35 if on else SUN_DAY
	sun.light_color = Color(0.62, 0.66, 1.0) if on else Color(1.0, 0.88, 0.7)
	sun.shadow_enabled = not on
	for n in _night_nodes:
		n.visible = on
	for n in _day_nodes:
		n.visible = not on
	for l in _lamps:
		(l as OmniLight3D).light_energy = 1.4 if on else 0.0
	# --- POLISH LOOK (P2): de día, las constantes DAY_* (la noche no cambia: la arena, la exposición y el contraste
	# vuelven a los de antes en _apply_storm_light)
	if _sand_mat:
		_sand_mat.albedo_color = Color.WHITE if on else SAND_TINT
	ring.modulate = Color(0.85, 0.85, 1.25) if on else RING_DAY
	for hz in _horizon:   # --- POLISH LOOK (P13)
		(hz as Sprite3D).modulate = HORIZON_NIGHT if on else HORIZON_DAY
	env.ambient_light_color = Color(0.36, 0.36, 0.6) if on else DAY_AMB
	env.ambient_light_energy = 0.55 if on else DAY_AMB_E
	env.background_color = Color(0.05, 0.04, 0.1) if on else DAY_BG
	for w in walkers:
		(w["a"] as Actor).visible = not on and (w["a"] as Actor).get_meta("active", true)
	_apply_sky2()   # --- SS2 WORLD: las lunas, las lámparas del anillo, las luces de la fiesta y del neón

func _process(delta: float) -> void:
	super._process(delta)
	# --- POLISH FIX (F9): la Scour sopla: una ráfaga cada 12-18 s mientras se ve la calle de día
	if _event == "sandstorm" and not night and visible:
		_gust_t -= delta
		if _gust_t <= 0.0:
			_gust_t = randf_range(12.0, 18.0)
			Sfx.play("gust", 0.08, -8.0)
	# --- end POLISH FIX
	# el escarabajo posado desaparece mientras despega (es el mismo)
	if _beetle_parked and not _beetle_flyer.is_empty():
		_beetle_parked.visible = not night and not (_beetle_flyer["s"] as Sprite3D).visible
	_update_sky2(delta)   # --- SS2 WORLD
	_update_departures(delta)
	for w in walkers:
		var a: Actor = w["a"]
		if not a.visible:
			continue
		if float(w["pause"]) > 0.0:
			w["pause"] = float(w["pause"]) - delta
			if float(w["pause"]) <= 0.0:
				a.set_walking(true)
			continue
		a.position.x += float(w["speed"]) * int(w["dir"]) * delta
		a.face(int(w["dir"]))
		if a.position.x > float(w["x1"]) or a.position.x < float(w["x0"]):
			w["dir"] = -int(w["dir"])
			w["pause"] = randf_range(1.5, 5.0)
			a.set_walking(false)
		elif randf() < delta * 0.05:
			w["pause"] = randf_range(1.0, 3.0)
			a.set_walking(false)


# ==================================================================================================================
# --- SS2 WORLD: la calle de la ronda 2 (SS2_DESIGN §6.6, §6.7, §8.10). Todo lo que puede aparecer se arma escondido
# en los 3 pasos nuevos (_build_sky2, _build_neighbours, _build_event_dressing) y queda anotado en warm_extra; después
# solo cambian visibilidad, cuadro, textura ya cargada, color, posición, escala y la energía de las luces.

const RING_POS := Vector3(-4.0, 10.0, -50.5)
const RING_PX := 0.06
## Las lunas: Copper (grande, cobre rosado, arriba a la izquierda) y Tin (chica, plata azulada, arriba a la derecha),
## altas en el cielo de noche (nunca dos discos bajos sobre un horizonte naranja).
const COPPER_POS := Vector3(-14.5, 11.9, -50.0)
const TIN_POS := Vector3(16.5, 12.4, -50.0)
const SIGN_POS := Vector3(SHOP_X, 4.0, -4.82)
## El orden en que las lámparas del anillo quedan fijas: primero la 7 ("Lamp Seven", la de Old Seven).
const RING_LAMP_ORDER := [6, 0, 3, 5, 1, 4, 2]
## The Low Moons, junto a la fachada de Nell del lado de Shine Again (detrás del carril, fuera de las zonas).
const BAND_POS := Vector3(-8.75, 0.0, -3.05)
## Los 14 sitios del público de la gala frente a la fachada de Nell, de la puerta hacia afuera: 11 a la derecha de la
## puerta (fila de adelante z -1.1 y de atrás z -2.7, en tresbolillo) y 3 a la izquierda, más allá de la banda (nadie
## delante de la banda ni de la puerta: ahí van Nell, Kettle y quien tenga su momento).
const GALA_SPOTS := [Vector3(-5.2, 0.0, -1.1), Vector3(-4.8, 0.0, -2.7), Vector3(-4.3, 0.0, -1.1), Vector3(-3.9, 0.0, -2.7),
	Vector3(-3.4, 0.0, -1.1), Vector3(-3.0, 0.0, -2.75), Vector3(-2.5, 0.0, -1.1), Vector3(-2.1, 0.0, -2.8),
	Vector3(-1.6, 0.0, -1.15), Vector3(-1.2, 0.0, -2.85), Vector3(-0.7, 0.0, -1.2), Vector3(-10.9, 0.0, -1.3),
	Vector3(-11.7, 0.0, -1.0), Vector3(-11.3, 0.0, -2.6)]

var comet_sign: Sprite3D          # el cartel con el Brass Comet (sin luz: brilla); escondido hasta la gala / la corona
# --- POLISH LOOK (P3): la noche del cometa (de noche y con el evento "finale": la gala, su calentamiento)
var gala_key: OmniLight3D
const GALA_KEY_POS := Vector3(-3.6, 1.6, 1.2)      # delante del público, a la altura del pecho
const GALA_KEY_COL := Color(1.0, 0.74, 0.46)       # ámbar de farol
const GALA_KEY_E := 1.2
const GALA_AMB := Color(0.52, 0.42, 0.62)          # la noche de siempre es (0.36, 0.36, 0.6) a 0.55: más tibia y violeta
const GALA_AMB_E := 0.62
# --- end POLISH LOOK
var moon_copper: Sprite3D
var moon_tin: Sprite3D
var ring_lamps: Array = []        # 7 Sprite3D (2 cuadros: encendida / apagada)
var sparks: Array = []            # 12 chispas de la gala (sin partículas: sprites con tween)
var band: Sprite3D
var lanterns: Array = []          # las guirnaldas de faroles (Bronzemoon, la Gran Lluvia)
var lantern_light: OmniLight3D    # UNA luz para todos los faroles (0 -> 1.2 de noche)
var _halos: Array = []
var _sign_tex: Array = []
var _comet_on := false
var _moon_kind := ""              # "" / "normal": Copper gibosa, Tin media; "full": las dos llenas con halo de bronce
var _ring_steady := -1            # cuántas lámparas del anillo fijas (-1: automático: la 7 si Old Seven tiene 3 núcleos)
var _ring_rest := "blink"         # las demás: "blink" (titilan despacio, cada una a su ritmo) | "dark"
var _event := ""
var _gust_t := 5.0   # --- POLISH FIX (F9): la próxima ráfaga de la Scour (s)
var _band_on := false
var _extra_walkers: Array = []    # más gente paseando el día de la Gran Lluvia (y set_crowd)
var _crowd := 0
var _spark_tw: Tween
var _pop_tw: Tween
var _nb_dome: Sprite3D            # la cúpula de la casa de al lado (blanca cuando es Shine Again)
var _nb_old: Array = []           # la puerta en arco y la ventana de la casa de adobe (se esconden con Shine Again)
var _shine_closed: Node3D         # días 1-2: tapiada, "COMING SOON"
var _shine_open: Node3D           # desde el día 3: Shine Again
var _shine_neon: Label3D
var _shine_light: OmniLight3D     # el neón de Shine Again de noche (0 -> 0.8)
var _rival_open := false
var _balloon: Sprite3D
var _balloon_state := ""
var _yard: Node3D                 # el patio de Dolly (desde el día 2)
var _poster: Sprite3D             # el afiche del próximo evento en el tablón
var _poster_icon: Sprite3D
var _event_icons := {}            # id -> Texture2D (cargadas al armar: nada de cargar en el camino)
var _awning: Sprite3D
var _neon_win: Sprite3D
var _dress := {}                  # id del evento -> Node3D con su decorado
var _day_only_ev: Array = []      # (del decorado de un evento) solo de día
var _night_only_ev: Array = []    # (del decorado de un evento) solo de noche
var _bobbers: Array = []          # [Sprite3D, y] que suben y bajan despacio
var _sand_layer: CanvasLayer      # the Scour: la arena que pasa delante de todo (2D, material por defecto)
var _sand_rect: TextureRect
var _drifts: Array = []           # --- POLISH LOOK (P4): la arena amontonada del Scour (su propio tinte, no el de _flats)
var _sand_t := 0.0
var _env_base := {}               # la luz de día de la calle (para volver después del Scour)
var _flats: Array = []            # lo acostado en el piso sin luz (alfombra, arena): su color a mano de día y de noche

## Paso nuevo 2: el cielo de la ronda 2 y el decorado de los días especiales.
func _build_sky_and_events() -> void:
	_build_sky2()
	_build_event_dressing()

## El cielo de la ronda 2 (lunas, lámparas del anillo, el cartel con el cometa, las chispas).
func _build_sky2() -> void:
	for n in 6:
		_sign_tex.append(load("res://assets/props/star_sign_%d.png" % n))
	comet_sign = glow("star_sign_comet", SIGN_POS + Vector3(0.0, 0.0, 0.012))
	comet_sign.name = "CometSign"
	comet_sign.offset.x = -float(props_info.get("star_sign_comet", {}).get("star_cx", 92))
	later(comet_sign)
	for spec in [[COPPER_POS, 1.0], [TIN_POS, 0.42]]:
		var h := glow("moon_halo", Vector3(spec[0]) + Vector3(0.0, 0.0, -0.25), 0.05 * float(spec[1]))
		h.name = "MoonHalo"
		_halos.append(later(h))
	moon_copper = later(glow("moon_copper", COPPER_POS, -1.0, "", 1)) as Sprite3D
	moon_copper.name = "MoonCopper"
	moon_tin = later(glow("moon_tin", TIN_POS, -1.0, "", 2)) as Sprite3D
	moon_tin.name = "MoonTin"
	var info: Dictionary = props_info.get("sky_ring", {})
	var sz: Array = info.get("size", [512, 150])
	for uv in info.get("lamps", []):
		var p := RING_POS + Vector3((float(uv[0]) - float(sz[0]) / 2.0) * RING_PX, -(float(uv[1]) - float(sz[1]) / 2.0) * RING_PX, 0.08)
		var l := glow("ring_lamp", p, 0.15)
		l.name = "RingLamp%d" % ring_lamps.size()
		ring_lamps.append(later(l))
	for i in 12:
		var s := soft("spark", SIGN_POS)
		s.name = "Spark%d" % i
		sparks.append(later(s))

## Paso nuevo 1: los vecinos (Shine Again, el patio de Dolly, los tablones, el Slow Orbit, la banda, el globo).
func _build_neighbours() -> void:
	UIKit.load_fonts()
	# --- Shine Again (la casa de la izquierda): días 1-2 tapiada con un afiche; desde el día 3, esmalte blanco
	var boarded := Node3D.new()
	boarded.name = "ShineBoarded"
	add_child(boarded)
	prop("boarded_poster", Vector3(-12.2, 0.0, -4.52), -1.0, "", 0, true, boarded)
	box_b(-15.6, -13.1, 2.2, 2.62, -4.6, -4.54, mat("res://assets/tex/wood.png", 0.6, Color(0.95, 0.88, 0.78)), boarded)
	boarded.add_child(_label3d("COMING SOON · SHINE AGAIN", Vector3(-14.35, 2.41, -4.53), 26, 0.0052, Color(0.72, 0.24, 0.42), UIKit.font_bold))
	_shine_closed = boarded
	var shine := Node3D.new()
	shine.name = "ShineAgain"
	add_child(shine)
	var enamel := mat("res://assets/tex/enamel.png", 0.55, Color(1.0, 1.0, 1.0), 0.5)
	box_b(-17.06, -10.54, 0.0, 3.06, -9.06, -4.54, enamel, shine)
	box_b(-17.1, -10.5, 3.06, 3.2, -9.1, -4.5, flat(Color(0.93, 0.48, 0.66)), shine)
	prop("shine_facade", Vector3(-13.8, 0.0, -4.5), -1.0, "", 0, true, shine)
	prop("shine_star", Vector3(-11.67, 3.55, -4.46), -1.0, "", 0, true, shine)
	box_b(-15.15, -12.15, 2.36, 2.86, -4.5, -4.47, flat(Color(0.12, 0.1, 0.18)), shine)
	_shine_neon = _label3d("SHINE AGAIN", Vector3(-13.65, 2.61, -4.45), 40, 0.0062, Color(1.0, 0.55, 0.8), UIKit.font_bold)
	_shine_neon.outline_size = 10
	_shine_neon.outline_modulate = Color(0.25, 0.85, 0.8)
	shine.add_child(_shine_neon)
	var carpet := glow("shine_carpet", Vector3(-11.67, 0.012, -3.3), -1.0, "", 0, shine)
	carpet.rotation_degrees.x = -90.0
	_flats.append(carpet)
	for x in [-12.45, -10.85]:
		prop("chrome_plant", Vector3(x, 0.0, -4.25), -1.0, "", 0, true, shine)
	_shine_open = shine
	later(shine)
	_shine_light = toggle_omni(Vector3(-12.8, 2.5, -3.3), Color(1.0, 0.55, 0.8), 0.8, 5.0)
	_shine_light.name = "ShineNeonLight"
	# el globo de cromo de Glint (día 8 inflado sobre el techo; día 9 caído si reventó)
	_balloon = prop("glint_balloon", Vector3(-14.5, 3.15, -4.35))
	_balloon.name = "GlintBalloon"
	animate_bob(_balloon)
	later(_balloon)
	_rival = make_actor("rival", Vector3(-10.4, 0.0, -3.0), 1)
	_rival.visible = false
	# --- el patio de Dolly (donde estaba el cobertizo oxidado): toldo verde agua, cajones con mejoras, el cartel
	var yard := Node3D.new()
	yard.name = "DollyYard"
	add_child(yard)
	var canopy := prop("stall_canopy_teal", Vector3(12.9, 0.0, -3.55), 0.045, "", 0, true, yard)
	canopy.modulate = Color(0.78, 0.98, 1.12)
	prop("vendor_crates", Vector3(14.25, 0.0, -2.75), -1.0, "", 0, true, yard)
	box_b(11.85, 13.95, 3.3, 3.78, -3.52, -3.46, mat("res://assets/tex/wood.png", 0.6, Color(0.95, 0.9, 0.8)), yard)
	for x in [12.05, 13.75]:
		box_b(x - 0.04, x + 0.04, 3.1, 3.3, -3.5, -3.46, flat(Color(0.3, 0.25, 0.22)), yard)
	yard.add_child(_label3d("FITTINGS", Vector3(12.9, 3.53, -3.44), 64, 0.0062, Color(0.16, 0.36, 0.36), UIKit.font_hand))
	_yard = yard
	later(yard)
	_vendor = make_actor("vendor", Vector3(12.4, 0.0, -2.9), -1)
	_vendor.visible = false
	# --- el tablón de anuncios (fachada de Nell, x -4.0): corcho, calendario y el afiche del próximo evento
	prop("notice_board", Vector3(-4.0, 1.72, -3.93))
	_poster = prop("poster_frame", Vector3(-3.62, 1.7, -3.9))
	_poster_icon = sprite("res://assets/ui/event_race.png", 0.015, Vector3(-3.62, 1.76, -3.885), "center")
	_poster_icon.name = "PosterIcon"
	for ev in ["sandstorm", "inspection", "bigfall", "festival", "race", "finale"]:
		var path := "res://assets/ui/event_%s.png" % ev
		if ResourceLoader.exists(path):
			_event_icons[ev] = load(path)
	later(_poster)
	later(_poster_icon)
	# --- el tablero de salidas (entre la fachada de Nell y la tortuga, detrás del carril): filas fijas en la mono
	var dep_x := -0.95
	var dep_z := -6.6
	for x in [dep_x - 1.1, dep_x + 1.1]:
		box_b(x - 0.05, x + 0.05, 0.0, 2.25, dep_z - 0.05, dep_z + 0.05, flat(Color(0.26, 0.24, 0.24)))
	prop("departure_board", Vector3(dep_x, 2.1, dep_z + 0.07))
	for r in DEP_ROWS.size():
		var lb := _label3d(DEP_ROWS[r][0], Vector3(dep_x - 1.04, 3.05 - 0.18 * r, dep_z + 0.09), 24, 0.0034, Color(0.95, 0.88, 0.68), UIKit.font_mono)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lb.outline_size = 0
		add_child(lb)
		_dep_labels.append(lb)
	# --- el Slow Orbit (la cúpula del fondo a la derecha): el planeta de neón, su nombre y la puerta cálida
	glow("lounge_sign", Vector3(13.0, 3.95, -10.6)).modulate = Color(1.5, 1.35, 1.35)
	var ln := _label3d("THE SLOW ORBIT", Vector3(13.0, 4.85, -10.6), 40, 0.0075, Color(1.0, 0.86, 0.62), UIKit.font_bold)
	add_child(ln)
	box_b(13.4, 14.4, 0.0, 1.7, -10.72, -10.66, flat(Color(1.0, 0.72, 0.4), true), null, false)
	# --- The Low Moons (Bronzemoon con `band`, la gala)
	band = prop("band_trio", BAND_POS)
	band.name = "LowMoons"
	animate(band, 2.2)
	later(band)
	# --- lo que se ve desde la calle de las mejoras: el toldo del Cool Coil y la estrella de neón de la ventana
	_awning = prop("facade_awning", Vector3(SHOP_X, 3.08, -3.72))
	_awning.name = "CoolCoilAwning"
	later(_awning)
	_neon_win = glow("neon_street", Vector3(-8.7, 1.9, -3.93))
	_neon_win.name = "NeonWindow"
	animate(_neon_win, 1.3)
	later(_neon_win)

## El tablero de salidas: 5 filas fijas y, de vez en cuando, una cambia de estado (P1: "flips").
const DEP_ROWS := [["HITCHPOST ..... ON TIME", "HITCHPOST ..... BOARDING"], ["BRINDLE ....... BOARDING", "BRINDLE ....... DEPARTED"],
	["THE SHOALS .... DELAYED (TUG)", "THE SHOALS .... DELAYED (MORE TUG)"], ["OCHRE ......... CANCELLED (KILN FIRE)", "OCHRE ......... CANCELLED (STILL)"],
	["LEDGER ........ FORMS REQUIRED", "LEDGER ........ FORMS IN TRIPLICATE"]]
var _dep_labels: Array = []
var _dep_state: Array = [0, 0, 0, 0, 0]
var _dep_wait := 22.0

func _update_departures(delta: float) -> void:
	if _dep_labels.is_empty() or night:
		return
	_dep_wait -= delta
	if _dep_wait > 0.0:
		return
	_dep_wait = randf_range(20.0, 30.0)
	var r := randi() % _dep_labels.size()
	_dep_state[r] = 1 - int(_dep_state[r])
	var lb: Label3D = _dep_labels[r]
	var tw := create_tween()
	tw.tween_property(lb, "scale:y", 0.05, 0.08)
	tw.tween_callback(func(): lb.text = DEP_ROWS[r][_dep_state[r]])
	tw.tween_property(lb, "scale:y", 1.0, 0.08)
	if is_visible_in_tree():
		Sfx.play("flap", 0.05, -22.0)

## Un cartel de texto en el mundo (sin luz, sin billboard: la familia de las etiquetas de la tienda).
func _label3d(text: String, pos: Vector3, size: int, px: float, col: Color, font: Font) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 6
	l.outline_modulate = Color(0.1, 0.07, 0.06)
	l.shaded = false
	l.position = pos
	return l

## Un sprite que sube y baja despacio (el globo).
func animate_bob(s: Sprite3D) -> void:
	_bobbers.append([s, s.position.y])

## El decorado de los días especiales (todo escondido hasta su día).
func _build_event_dressing() -> void:
	# las guirnaldas de faroles (Bronzemoon, la Gran Lluvia): sobre el techo de Nell, del cartel hacia los bordes, y
	# entre los dos puestos; sprites sin luz y UNA luz para todos
	for spec in [[Vector3(-8.35, 5.0, -4.35), 0.02, 7.0], [Vector3(-4.05, 5.0, -4.35), 0.02, -7.0], [Vector3(5.5, 3.62, -3.75), 0.026, 0.0]]:
		var s := glow("lantern_string", spec[0], float(spec[1]), "top")
		s.rotation_degrees.z = float(spec[2])
		s.name = "Lanterns"
		lanterns.append(later(s))
	lantern_light = toggle_omni(Vector3(-5.6, 3.6, -2.2), Color(1.0, 0.78, 0.5), 1.2, 9.0)
	lantern_light.name = "LanternLight"
	# --- POLISH LOOK (P3): la luz de frente de la noche del cometa (las caras del público: antes siluetas azul marino
	# contra la fachada). Una omni más sin sombra; existe desde el arranque pero ESCONDIDA, no como toggle_omni (que
	# _warm_world enciende en cada cuadro de calentamiento de la calle: una pasada de luz más sobre el piso, la fachada y
	# la gente en ~20 cuadros, ~0,3 s de arranque en GL por software). _warm_gala_night la ve encendida por el evento
	# (final + noche), la única vez que se prende: ahí se calientan sus variantes (bootjump gala_win/gala_lose = BASE).
	gala_key = omni(GALA_KEY_POS, GALA_KEY_COL, GALA_KEY_E, 9.0)
	gala_key.visible = false
	gala_key.name = "GalaKeyLight"
	# --- end POLISH LOOK
	# más gente paseando por detrás el día de la Gran Lluvia
	for spec in [["zib", 3.2, -8.9, 0.8], ["rook", 11.6, -9.2, 0.5], ["clatter", 7.6, -8.7, 0.35]]:
		var a := make_actor(spec[0], Vector3(spec[1], 0.0, spec[2]), 1)
		a.quiet = true
		a.set_meta("active", false)
		a.visible = false
		_extra_walkers.append(a)
		walkers.append({"a": a, "speed": spec[3], "dir": -1, "x0": 2.6, "x1": 13.0, "pause": randf_range(0.0, 3.0)})
	# --- the Scour: lona sobre el puesto de Raker, trapos que flamean, arena amontonada, la capa de arena que pasa
	var storm := _dress_node("sandstorm")
	prop("stall_tarp", Vector3(PODS_X, 0.0, -2.98), -1.0, "", 0, true, storm)
	for spec in [[Vector3(0.95, 3.0, -2.95), 0], [Vector3(6.4, 3.0, -2.95), 1], [Vector3(10.1, 3.0, -2.95), 0], [Vector3(-2.5, 3.5, -3.8), 1]]:
		var f := prop("cloth_flap", spec[0], -1.0, "", int(spec[1]), true, storm)
		animate(f, 5.0)
	for spec in [[Vector3(-7.4, 0.014, -3.4), 1.0], [Vector3(-3.0, 0.014, -3.2), 0.8], [Vector3(4.4, 0.014, -2.9), 1.2], [Vector3(9.4, 0.014, -2.95), 0.9]]:
		var d := glow("sand_drift", spec[0], 0.03 * float(spec[1]), "center", 1, storm)
		d.rotation_degrees.x = -90.0
		_drifts.append(d)   # --- POLISH LOOK (P4): antes en _flats (tinte (1.12, 1.0, 0.84): junto a la arena cálida se leían
		# como charcos gris azulados); ahora DRIFT_DAY, del color de la arena al sol
	_sand_layer = CanvasLayer.new()
	_sand_layer.name = "SandOverlay"
	_sand_layer.layer = 1
	_sand_layer.visible = false
	add_child(_sand_layer)
	_sand_rect = TextureRect.new()
	_sand_rect.texture = load("res://assets/tex/sand_blow.png")
	_sand_rect.stretch_mode = TextureRect.STRETCH_TILE
	_sand_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sand_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- POLISH LOOK (P4): un velo de polvo tibio parejo debajo (ColorRect: el material 2D de siempre) y la arena que
	# pasa más espesa (0.42 -> 0.55): el Scour se lee como tormenta
	var veil := ColorRect.new()
	veil.name = "DustVeil"
	veil.color = Color(0.86, 0.6, 0.36, 0.16)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.size = Vector2(1920 + 512, 1080 + 512)
	_sand_layer.add_child(veil)
	_sand_rect.modulate = Color(1.0, 0.88, 0.7, 0.55)
	# --- end POLISH LOOK
	_sand_rect.size = Vector2(1920 + 512, 1080 + 512)
	_sand_layer.add_child(_sand_rect)
	# --- la inspección: el estandarte de la Tally Office en un poste entre los dos puestos
	var insp := _dress_node("inspection")
	box_b(-10.02, -9.94, 0.0, 3.75, -3.62, -3.54, flat(Color(0.28, 0.25, 0.24)), insp)
	box_b(-9.98, -8.85, 3.62, 3.68, -3.62, -3.56, flat(Color(0.28, 0.25, 0.24)), insp)
	prop("tally_banner", Vector3(-9.42, 3.6, -3.55), -1.0, "", 0, true, insp)
	insp.add_child(_label3d("TALLY OFFICE", Vector3(-9.42, 3.86, -3.53), 30, 0.005, Color(0.95, 0.85, 0.5), UIKit.font_bold))
	# --- Bigfall: la columna de humo en el horizonte (de noche, el resplandor)
	var big := _dress_node("bigfall")
	var smoke := prop("smoke_column", Vector3(-1.5, 0.0, -44.0), -1.0, "", 0, false, big)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	animate(smoke, 1.6)
	_day_only_ev.append(smoke)
	var wg := glow("wreck_glow", Vector3(-1.5, 0.0, -43.8), -1.0, "", 0, big)
	wg.modulate = Color(1.6, 1.25, 1.0)
	_night_only_ev.append(wg)
	# --- Bronzemoon: banderines, estandartes de las dos lunas (los faroles, el globo y la banda van aparte)
	var fest := _dress_node("festival")
	var b1 := prop("bunting", Vector3(-0.8, 3.85, -3.95), 0.018, "", 0, true, fest)
	b1.rotation_degrees.z = -9.0
	prop("bunting", Vector3(5.45, 3.05, -3.7), 0.024, "", 0, true, fest)
	prop("bunting", Vector3(9.3, 3.3, -9.2), 0.03, "", 0, true, fest)
	for x in [-1.95, 10.55]:
		box_b(x - 0.04, x + 0.04, 0.0, 3.3, -3.62, -3.54, flat(Color(0.3, 0.26, 0.24)), fest)
		box_b(x - 0.04, x + 0.62, 3.26, 3.32, -3.62, -3.56, flat(Color(0.3, 0.26, 0.24)), fest)
		prop("moon_banner", Vector3(x + 0.36, 3.26, -3.55), -1.0, "", 0, true, fest)
	# --- el Glasspan Derby: banderines entre las cúpulas y el arco de largada más allá de las plataformas
	var race := _dress_node("race")
	prop("flag_race", Vector3(5.45, 3.05, -3.7), 0.024, "", 0, true, race)
	prop("flag_race", Vector3(9.4, 3.3, -9.2), 0.03, "", 0, true, race)
	prop("flag_race", Vector3(-15.5, 3.4, -10.4), 0.03, "", 0, true, race)
	prop("race_gate", Vector3(-8.6, 0.0, -27.0), -1.0, "", 0, true, race)
	# (P1) dos hoverbikes del Derby cruzan el cielo, bajas sobre las cúpulas, solo ese día
	for k in 2:
		var d := add_flyer("flyer_bike", 0.05, Vector3(-46.0, 5.4 + k * 0.9, -30.0 - k * 2.0), Vector3(46.0, 5.8 + k * 0.7, -30.0 - k * 2.0),
			4.2 + k * 0.6, 7.5, Vector3(-1.62, 0.0, -0.02), 90.0, 1.5 + k * 1.1)
		d["event"] = "race"
		(d["s"] as Sprite3D).frame = k

## Un grupo de decorado de un evento (escondido; set_event lo muestra).
func _dress_node(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Dress_" + id
	add_child(n)
	_dress[id] = n
	later(n)
	return n

## Lo que depende de la noche, de las lunas, del anillo, del evento y de la vecina (set_night lo llama al final).
func _apply_sky2() -> void:
	if moon_copper == null:
		return
	var full := _moon_kind == "full"
	moon_copper.visible = night
	moon_tin.visible = night
	moon_copper.frame = 0 if full else 1
	moon_tin.frame = 0 if full else 2
	for h in _halos:
		(h as Sprite3D).visible = night and full
	for l in ring_lamps:
		(l as Sprite3D).visible = night
	var fest := _event in ["festival", "finale"]
	for s in lanterns:
		(s as Sprite3D).visible = fest
		(s as Sprite3D).modulate = Color(1.55, 1.4, 1.2) if night else Color(1.0, 1.0, 1.0)
	lantern_light.light_energy = 1.2 if night and fest else 0.0
	# --- POLISH LOOK (P3): la luz de frente y el ambiente tibio solo la noche del cometa; si no, la noche de siempre
	var gala_on := night and _event == "finale"
	if gala_key:
		gala_key.visible = gala_on   # --- POLISH LOOK (P3): escondida = ni una pasada de luz cuando no es la gala
	if night:
		env.ambient_light_color = GALA_AMB if gala_on else Color(0.36, 0.36, 0.6)
		env.ambient_light_energy = GALA_AMB_E if gala_on else 0.55
	# --- end POLISH LOOK
	if _event == "finale":
		# la Gran Lluvia: el anillo brilla cálido
		ring.modulate = Color(1.25, 1.0, 0.82) if night else Color(1.25, 1.02, 0.84)
	if comet_sign:
		comet_sign.modulate = Color(1.35, 1.22, 1.0) if night else Color(1.08, 1.04, 0.98)
	# la vecina: el neón de Shine Again de noche
	if _shine_light:
		_shine_light.light_energy = 0.8 if night and _rival_open else 0.0
		_shine_neon.modulate = Color(2.0, 0.95, 1.5) if night else Color(1.0, 0.45, 0.72)
	if _neon_win:
		_neon_win.modulate = Color(1.8, 1.3, 1.6) if night else Color(1.15, 1.0, 1.1)
	for f in _flats:
		(f as Sprite3D).modulate = Color(0.38, 0.36, 0.5) if night else Color(1.12, 1.0, 0.84)
	for n in _day_only_ev:
		(n as Node3D).visible = not night
	for n in _night_only_ev:
		(n as Node3D).visible = night
	_apply_storm_light()

func _update_sky2(delta: float) -> void:
	# el globo sube y baja; la arena del Scour pasa
	for b in _bobbers:
		var s: Sprite3D = b[0]
		if s.visible and _balloon_state == "up":
			s.position.y = float(b[1]) + sin(_t * 0.9) * 0.12
	if _sand_layer and _sand_layer.visible:
		_sand_t += delta
		_sand_rect.position = Vector2(-fposmod(_sand_t * 420.0, 256.0), -fposmod(_sand_t * 60.0, 256.0))
	if not night or ring_lamps.is_empty():
		return
	var steady_n := _ring_steady
	if steady_n < 0:
		steady_n = 1 if int(Game.flag("cores", 0)) >= 3 else 0
	for i in ring_lamps.size():
		var l: Sprite3D = ring_lamps[i]
		var steady := RING_LAMP_ORDER.find(i) < steady_n
		var on := steady
		if not steady and _ring_rest == "blink":
			on = sin(_t * 0.9 + i * 1.71) > 0.35
		l.frame = 0 if on else 1
		l.modulate = Color(2.2, 1.8, 1.25) if steady else (Color(1.6, 1.35, 1.05) if on else Color(1.0, 1.0, 1.0))

## El Scour: la luz de la calle se vuelve marrón tibia y polvorienta (sol más bajo y anaranjado, cielo de polvo); el
## post-proceso solo sube la viñeta (EVENT_POST). De noche o en otro día, todo vuelve a como era.
func _apply_storm_light() -> void:
	if _env_base.is_empty():
		_env_base = {"sat": env.adjustment_saturation, "con": env.adjustment_contrast, "exp": env.tonemap_exposure}
	var storm := _event == "sandstorm" and not night
	if _sand_layer:
		_sand_layer.visible = storm and visible
	env.adjustment_saturation = 0.8 if storm else float(_env_base["sat"])
	# --- POLISH LOOK (P2): la base es la de día; de noche, los valores de siempre
	env.adjustment_contrast = 0.95 if storm else (NIGHT_CONTRAST if night else float(_env_base["con"]))
	env.tonemap_exposure = 0.88 if storm else (NIGHT_EXPOSURE if night else float(_env_base["exp"]))
	for d in _drifts:   # --- POLISH LOOK (P4)
		(d as Sprite3D).modulate = Color(0.38, 0.36, 0.5) if night else DRIFT_DAY
	if night:
		return
	sun.light_color = Color(1.0, 0.66, 0.42) if storm else Color(1.0, 0.88, 0.7)
	sun.light_energy = 0.95 if storm else SUN_DAY
	env.ambient_light_color = Color(0.72, 0.56, 0.42) if storm else DAY_AMB   # --- POLISH LOOK (P2): DAY_*
	env.background_color = Color(0.76, 0.56, 0.38) if storm else DAY_BG
	sun_sprite.modulate = STORM_SUN if storm else Color(1.25, 1.12, 0.95)   # --- POLISH LOOK (P4)
	for sm in _sky_mats:
		(sm as ShaderMaterial).set_shader_parameter("day_top", Vector3(0.56, 0.38, 0.26) if storm else DAY_TOP)
		(sm as ShaderMaterial).set_shader_parameter("day_hor", Vector3(0.8, 0.58, 0.38) if storm else DAY_HOR)

## La capa de arena 2D solo se ve con la calle activa.
func activate(on: bool) -> void:
	super.activate(on)
	if _sand_layer:
		_sand_layer.visible = on and _event == "sandstorm" and not night

# ------------------------------------------------------------------ la API (§8.10)

var _vendor: Actor
var _rival: Actor
## Los ajustes del post-proceso de cada evento (main.gd los mezcla con POST_STREET). Solo claves que POST_STREET y
## POST_SHOP también ponen (así nada queda pegado al día siguiente ni en la tienda): el tono del Scour lo da la luz de
## la propia calle (_apply_storm_light).
const EVENT_POST := {
	"sandstorm": {"vignette_strength": 0.42, "max_lod": 2.8},
	"festival": {"vignette_strength": 0.22},
	"finale": {"vignette_strength": 0.22},
}

## "" | sandstorm | inspection | bigfall | festival | race | finale. El afiche del tablón muestra el próximo evento.
func set_event(id: String) -> void:
	_event = id
	flyer_event = id
	for k in _dress:
		(_dress[k] as Node3D).visible = k == id
	_apply_walkers()
	_refresh_poster()
	_apply_sky2()

## El afiche del tablón: el pictograma del próximo día especial (hoy incluido); nada si no queda ninguno.
func _refresh_poster() -> void:
	if _poster == null:
		return
	var next := ""
	if Game.day > 0:
		for d in range(Game.day, Game.day + 4):
			var ev := String(Season.event(d)) if Season.has_method("event") else ""
			if ev != "" and _event_icons.has(ev):
				next = ev
				break
	_poster.visible = next != ""
	_poster_icon.visible = next != ""
	if next != "":
		_poster_icon.texture = _event_icons[next]

## Shine Again (desde el día 3): el frente de esmalte, el destello, el neón, la alfombra, Glint en su puerta. Antes, la
## casa de adobe tapiada con "COMING SOON".
func set_rival_open(on: bool) -> void:
	_rival_open = on
	if _rival:
		_rival.visible = on
	if _shine_open:
		_shine_open.visible = on
		_shine_closed.visible = not on
		for n in _nb_old:
			(n as Node3D).visible = not on
		_nb_dome.modulate = Color(1.28, 1.26, 1.32) if on else Color.WHITE
	_apply_sky2()

## El patio de Dolly (desde el día 2: toldo, cajones con mejoras, el cartel FITTINGS, Dolly).
func set_vendor_open(on: bool) -> void:
	if _vendor:
		_vendor.visible = on
	if _yard:
		_yard.visible = on

func rival_actor() -> Actor:
	return _rival

func vendor_actor() -> Actor:
	return _vendor

## Dónde se para Old Seven para el momento del día 7 (S lo crea con make_actor): al fondo de la calle, junto al patio.
func hermit_spot() -> Vector3:
	return Vector3(10.6, 0.0, -2.6)

## Las mejoras que se ven desde la calle: el toldo a rayas del Cool Coil sobre la puerta, la estrella de neón en la
## ventana redonda (Neon Star). El Display Case no se ve desde afuera.
func set_upgrade_looks() -> void:
	if _awning:
		_awning.visible = Game.has_fitting("coolcoil")
	if _neon_win:
		_neon_win.visible = Game.has_fitting("neon")
	_apply_sky2()

## "" | "normal": Copper gibosa y Tin media | "full": las dos llenas con su halo de bronce (Bronzemoon, la gala)
func set_moons(kind: String) -> void:
	_moon_kind = kind
	_apply_sky2()

## n de las 7 lámparas del anillo quedan fijas (la 7 primero); las demás titilan despacio (rest "blink") o se apagan
## (rest "dark"). n = -1 vuelve a lo automático (la 7 fija si Old Seven tiene sus 3 núcleos).
func set_ring_lamps(n: int, rest := "blink") -> void:
	_ring_steady = clampi(n, -1, 7)
	_ring_rest = rest
	_update_sky2(0.0)

## El Brass Comet atornillado al cartel (la gala; después de la corona queda puesto: Game.crown_seen).
func set_comet(on: bool) -> void:
	_comet_on = on
	refresh_sign()
	if on:
		_pop(comet_sign)

## La mañana de una punta nueva del cartel: un saltito y chispas.
func celebrate_sign() -> void:
	_pop(comet_sign if comet_sign and comet_sign.visible else star_sign)
	play_sparks()

func _pop(s: Sprite3D) -> void:
	if s == null:
		return
	if _pop_tw and _pop_tw.is_valid():
		_pop_tw.kill()
	s.scale = Vector3.ONE
	_pop_tw = create_tween()
	_pop_tw.tween_property(s, "scale", Vector3.ONE * 1.16, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tw.tween_property(s, "scale", Vector3.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## La lluvia de chispas de la gala (y de una punta nueva): 12 chispas que saltan del punto y caen apagándose (~1.8 s).
## at = Vector3.INF: desde el cartel de la estrella.
func play_sparks(at := Vector3.INF) -> void:
	if sparks.is_empty():
		return
	var c: Vector3 = at if at != Vector3.INF else SIGN_POS + Vector3(0.0, 1.15, 0.35)
	if _spark_tw and _spark_tw.is_valid():
		_spark_tw.kill()
	_spark_tw = create_tween().set_parallel(true)
	for i in sparks.size():
		var s: Sprite3D = sparks[i]
		var a := TAU * i / sparks.size() + randf_range(-0.25, 0.25)
		var mid := c + Vector3(cos(a) * randf_range(0.9, 1.7), sin(a) * randf_range(0.7, 1.3) + 0.5, 0.1)
		var to := mid + Vector3(randf_range(-0.35, 0.35), -randf_range(1.8, 2.8), 0.0)
		var d := randf_range(0.0, 0.3)
		s.position = c
		s.visible = true
		s.modulate = Color(1.7, 1.4, 0.95, 1.0)
		s.scale = Vector3.ONE * randf_range(0.8, 1.35)
		_spark_tw.tween_property(s, "position", mid, 0.42).set_delay(d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_spark_tw.tween_property(s, "position", to, 1.15).set_delay(d + 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_spark_tw.tween_property(s, "modulate:a", 0.0, 0.55).set_delay(d + 1.0)
	_spark_tw.chain().tween_callback(func():
		for s in sparks:
			(s as Sprite3D).visible = false)

## Los 14 sitios del público de la gala (Vector3, y = 0), de la puerta hacia afuera (ver GALA_SPOTS).
func gala_spots() -> Array:
	return GALA_SPOTS.duplicate()

## The Low Moons tocando junto a la puerta de Nell (Bronzemoon con `band`, la gala).
func set_band(on: bool) -> void:
	_band_on = on
	if band:
		band.visible = on

## El globo de cromo de Glint: "up" (día 8, flota sobre Shine Again), "popped" (día 9 si reventó: caído sobre el
## techo), "" (nada).
func set_balloon(state: String) -> void:
	_balloon_state = state
	if _balloon == null:
		return
	_balloon.visible = state in ["up", "popped"]
	_balloon.frame = 1 if state == "popped" else 0
	var y := 3.15 if state == "up" else 2.5
	_balloon.position = Vector3(-14.5 if state == "up" else -14.1, y, -4.35 if state == "up" else -4.42)
	for b in _bobbers:
		if b[0] == _balloon:
			b[1] = y

## (P1) más o menos gente paseando por detrás según el puesto en el tablero: n de los 3 paseantes extra (0..3; el
## día de la Gran Lluvia salen los 3 igual).
func set_crowd(n: int) -> void:
	_crowd = clampi(n, 0, _extra_walkers.size())
	_apply_walkers()

func _apply_walkers() -> void:
	for i in _extra_walkers.size():
		var a: Actor = _extra_walkers[i]
		var on := _event == "finale" or i < _crowd
		a.set_meta("active", on)
		a.visible = on and not night
