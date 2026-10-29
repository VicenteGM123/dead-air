extends SetKit
class_name StreetWorld
## --- SS CORE: la calle frente a la tienda, el Starfall Market de la mañana (HD-2D): casas de adobe y chatarra con
## cúpula, la fachada de Nell con el cartel de la estrella remendada (una punta encendida por cada día bueno: Game.
## sign_points) y su puerta ("Open shop"), el puesto de cápsulas de Raker con la tortuga de las dunas cargada de
## chatarra, el puesto de piezas de Mags, plataformas de aterrizaje con naves (una despega cada tanto), el gran sol
## ámbar y el anillo de restos en el cielo. De noche (la introducción): estrellas y la lluvia de chatarra.
## Nell camina por la calle (Walker) entre la puerta y los puestos; Kettle la sigue.

const LANE_Z := -1.6
const LANE := [Vector2(-9.6, -1.6), Vector2(9.0, -1.6)]
const SHOP_X := -6.2           # la puerta de la tienda de Nell
const PODS_X := 2.75           # el puesto de Raker (el centro del toldo)
const PARTS_X := 8.2           # el puesto de Mags
## Raker y Mags están DELANTE, a un lado de su puesto (así se los ve enteros; detrás del mostrador solo asomaba la
## cabeza); la tortuga de las dunas, entre la casa de Nell y el puesto de Raker.
const RAKER_POS := Vector3(0.5, 0.0, -2.7)
const MAGS_POS := Vector3(5.85, 0.0, -2.7)
const STATIONS := {
	"door": {"x": -6.2, "face": -1, "zone": Vector2(-7.6, -4.8), "name": "Your shop", "y": 2.5, "ax": -6.2, "az": -4.0},
	"pods": {"x": 1.45, "face": -1, "zone": Vector2(0.0, 3.5), "name": "Raker's pods", "y": 2.0, "ax": 0.5, "az": -2.7},
	"parts": {"x": 6.8, "face": -1, "zone": Vector2(5.0, 8.8), "name": "Mags's parts", "y": 2.0, "ax": 5.85, "az": -2.7},
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
const SUN_DAY := 1.45

func build() -> void:
	name = "StreetWorld"
	setup_camera_env(false)
	# la luz del sol de la mañana: arriba a la derecha y un poco desde delante (ilumina las fachadas)
	sun.rotation_degrees = Vector3(-40.0, 44.0, 0.0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.88, 0.7)
	cam_x0 = -4.6
	cam_x1 = 4.4
	cam_height = 4.3
	cam_dist = 12.0
	cam_look_y = 2.2
	cam_look_z = -4.0
	env.ambient_light_energy = 0.6
	env.tonemap_exposure = 0.94
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08
	fill.position = Vector3(0.0, 3.4, 5.0)
	fill.light_energy = 0.3
	_build_ground_and_sky()
	_build_far()
	_build_shop_facade()
	_build_stalls()
	_build_people()
	setup_nell(LANE, STATIONS, SHOP_X + 0.9)
	setup_kettle(Vector3(SHOP_X - 0.1, 0, LANE_Z + KETTLE_DZ))
	refresh_sign()

func _build_ground_and_sky() -> void:
	var sand := mat("res://assets/tex/sand.png", 0.45)
	box_b(-60.0, 60.0, -0.2, 0.0, -70.0, 10.0, sand)
	var sky := sky_backdrop(Vector2(170.0, 46.0), Vector3(0.0, 16.0, -52.0))
	sky.name = "StreetSky"
	var sm: ShaderMaterial = sky.material_override
	sm.set_shader_parameter("day_top", Vector3(0.86, 0.5, 0.3))
	sm.set_shader_parameter("day_hor", Vector3(1.0, 0.8, 0.55))
	sm.set_shader_parameter("bright", 1.05)
	# el anillo de restos (el astillero viejo) y el sol grande, ámbar
	ring = prop("sky_ring", Vector3(-4.0, 10.0, -50.5), 0.07, "center", 0, false)
	ring.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	ring.modulate = Color(1.05, 0.95, 0.85)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun_sprite = prop("sun", Vector3(15.5, 8.0, -51.0), 0.05, "center", 0, false)
	sun_sprite.modulate = Color(1.25, 1.12, 0.95)
	sun_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_day_nodes.append(sun_sprite)
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
	prop("round_window", Vector3(-3.8, 1.9, -3.95), 0.034, "center")
	prop("scrap_patch_a", Vector3(-9.3, 0.95, -3.95), 0.036, "center")
	prop("scrap_patch_b", Vector3(-3.3, 3.0, -3.95), 0.034, "center")
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
	prop("dome_cap", Vector3(-13.8, 2.95, -4.58), 6.0 / 88.0)
	prop("arch_door", Vector3(-12.2, 0.0, -4.57), 0.045)
	prop("round_window", Vector3(-15.4, 1.8, -4.57), 0.03, "center")

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
	star_sign.texture = load("res://assets/props/star_sign_%d.png" % n)

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
	ring.modulate = Color(0.85, 0.85, 1.25) if on else Color(1.05, 0.95, 0.85)
	env.ambient_light_color = Color(0.36, 0.36, 0.6) if on else Color(0.78, 0.7, 0.66)
	env.ambient_light_energy = 0.55 if on else 0.62
	env.background_color = Color(0.05, 0.04, 0.1) if on else Color(0.98, 0.8, 0.56)
	for w in walkers:
		(w["a"] as Actor).visible = not on

func _process(delta: float) -> void:
	super._process(delta)
	# el escarabajo posado desaparece mientras despega (es el mismo)
	if _beetle_parked and not _beetle_flyer.is_empty():
		_beetle_parked.visible = not night and not (_beetle_flyer["s"] as Sprite3D).visible
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
