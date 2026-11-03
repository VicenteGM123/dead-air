extends SetKit
class_name ShopWorld
## --- SS CORE: la tienda, The Secondhand Star (HD-2D como la tienda de Midnight Cauldron): un taller polvoriento de
## adobe y chapa. De izquierda a derecha, del lado de Nell: el rincón del té de Kettle, el banco de reparación, la
## cajonera de piezas, el estante de cosas reparadas (a la venta) y el MOSTRADOR transversal (corre de la pared del
## fondo hacia delante y parte la tienda en dos). Del lado de los clientes: la fila (4 sitios en diagonal hacia la
## puerta), la ventana al puerto a pleno sol (naves que pasan) y la puerta. Cables y lámparas colgando, un ventilador,
## chatarra en los estantes. De noche: la lluvia de chatarra por la ventana (el libro de cuentas).
## La gente de la fila la mueve ShopDay (scripts/shop_day.gd) con QUEUE_SPOTS / P_*; aquí están los sitios, la
## puerta compartida, el estante, lo que hay sobre el banco y el mostrador, y el té de Kettle.

const WALL_Z := -4.0
const FLOOR_Z1 := 3.4
const H := 4.4
const X0 := -7.8
const X1 := 8.6
const WIN := Rect2(1.75, 1.35, 2.7, 1.7)          # hueco de la ventana (x, y, ancho, alto)
const DOOR_X0 := 5.6                               # la puerta: hueco del tamaño de la hoja de assets/props/door.png
const DOOR_PX := 0.035
const DOOR_W := 33 * 0.035                         # la hoja (sin el marco beige del dibujo): 33 x 66 píxeles
const DOOR_H := 66 * 0.035
const COUNTER_X0 := 0.0                            # el mostrador transversal
const COUNTER_X1 := 0.75
const COUNTER_Z1 := 0.25
const COUNTER_TOP := 0.84
const LANE_Z := -1.5
## Carril de Nell (x, z): de su rincón del té hasta su lado del mostrador.
const LANE := [Vector2(-7.2, -1.55), Vector2(-4.0, -1.5), Vector2(-0.42, -1.5)]
## Estaciones: x donde se para, hacia dónde mira, su zona, el nombre, la altura del aviso y dónde está (ax, az).
const STATIONS := {
	"tea": {"x": -6.7, "face": -1, "zone": Vector2(-7.4, -6.1), "name": "Tea corner", "y": 1.85, "ax": -7.0, "az": -3.3},
	"bench": {"x": -4.75, "face": -1, "zone": Vector2(-6.1, -3.75), "name": "Repair bench", "y": 2.2, "ax": -5.15, "az": -2.95},
	"drawer": {"x": -3.05, "face": -1, "zone": Vector2(-3.75, -2.25), "name": "Parts drawer", "y": 2.05, "ax": -3.05, "az": -3.55},
	"shelf": {"x": -1.45, "face": -1, "zone": Vector2(-2.25, -0.95), "name": "Shelf", "y": 2.25, "ax": -1.42, "az": -3.7},
	"counter": {"x": -0.42, "face": 1, "zone": Vector2(-0.95, 0.06), "name": "Counter", "y": 1.95, "ax": 0.38, "az": -1.5},
}
# --- la fila (del lado de los clientes) y los caminos de la puerta
const P_CUSTOMER := Vector3(1.38, 0, -1.5)        # frente al mostrador
const QUEUE_SPOTS := [Vector3(2.28, 0, -1.68), Vector3(3.12, 0, -1.88), Vector3(3.96, 0, -2.08), Vector3(4.8, 0, -2.28)]
const P_OUTSIDE := Vector3(6.18, 0, -7.2)
const P_DOOR_IN := Vector3(6.18, 0, -3.35)
const P_PEEK := Vector3(5.5, 0, -2.75)            # recién entrado (se le ve entre la fila y la puerta)
const P_EXIT_BACK := Vector3(2.0, 0, -2.85)       # quien deja el mostrador sale por detrás de la fila
## El paseo del té de Kettle: rodea la punta del mostrador y pasa por delante de la fila.
const TEA_PATH := [Vector3(-0.35, 0, 0.75), Vector3(1.05, 0, 0.75), Vector3(1.55, 0, -1.05), Vector3(4.6, 0, -1.6)]
## La noche (el libro de cuentas): Nell y Kettle junto a la ventana, la cámara la deja a la izquierda de la pantalla.
const NIGHT_NELL := Vector3(2.55, 0, -2.4)
const NIGHT_KETTLE := Vector3(3.3, 0, -1.95)
const NIGHT_CAM := Vector3(5.5, 2.3, 6.5)
const NIGHT_LOOK := Vector3(5.5, 1.9, -4.0)

var door_pivot: Node3D
var door_sprite: Sprite3D
var shelf_root: Node3D
var bench_item: Sprite3D
var counter_item: Sprite3D
var counter_actor: Actor          # quien está en el mostrador (el aviso va sobre su cabeza)
var interior_lights: Array = []   # [OmniLight3D, energía de día]
var lamp_sprites: Array = []
var _night_nodes: Array = []      # lo que solo se ve de noche (ventanitas encendidas)
var _day_only: Array = []         # lo que solo se ve de día (el sol en la ventana)
var _door_tw: Tween
var _door_users := 0
var _door_open := false
var _door_sign_open := false

func build() -> void:
	for st in build_steps():
		st.call()

## --- BOOT: el armado en pasos cortos (main.gd hace uno por cuadro al arrancar; build() los hace todos juntos).
func build_steps() -> Array[Callable]:
	return [_build_base, _build_room, _build_outside, _build_counter, _build_nell_side, _build_customer_side,
		_build_ceiling, _build_people_and_shelf, _build_round2]   # --- SS2 WORLD: + 1 paso (los 4 armados de la ronda 2)

func _build_base() -> void:
	name = "ShopWorld"
	setup_camera_env(true)
	cam_x0 = -3.6
	cam_x1 = 1.4
	cam_height = 3.5
	cam_dist = 8.0
	cam_look_y = 1.25
	cam_look_z = -1.6
	cam_bias = 0.9     # desde el mostrador se ven la fila y la puerta

func _build_people_and_shelf() -> void:
	setup_nell(LANE, STATIONS, -0.42)
	setup_kettle(Vector3(-1.5, 0, -1.08))
	refresh_shelf()
	set_door_sign(false)

# ------------------------------------------------------------------ la sala

func _build_room() -> void:
	var floor_m := mat("res://assets/tex/tile.png", 0.28)
	var adobe := mat("res://assets/tex/adobe.png", 0.32, Color(0.97, 0.91, 0.85))
	var plate := mat("res://assets/tex/metal_plate.png", 0.7, Color.WHITE, 0.6)
	var rust := mat("res://assets/tex/rusted_panel.png", 0.55)
	box_b(X0 - 0.3, X1 + 0.3, -0.2, 0.0, WALL_Z - 0.3, FLOOR_Z1, floor_m)
	# la pared del fondo, con los huecos de la ventana y de la puerta (piezas que no se pisan)
	var z0 := WALL_Z - 0.3
	var z1 := WALL_Z
	var wx0 := WIN.position.x
	var wx1 := WIN.position.x + WIN.size.x
	var wy0 := WIN.position.y
	var wy1 := WIN.position.y + WIN.size.y
	var dx0 := DOOR_X0
	var dx1 := DOOR_X0 + DOOR_W
	box_b(X0, wx0, 0.0, H, z0, z1, adobe)
	box_b(wx0, wx1, 0.0, wy0, z0, z1, adobe)
	box_b(wx0, wx1, wy1, H, z0, z1, adobe)
	box_b(wx1, dx0, 0.0, H, z0, z1, adobe)
	box_b(dx0, dx1, DOOR_H, H, z0, z1, adobe)
	box_b(dx1, X1, 0.0, H, z0, z1, adobe)
	# zócalo de chapa remachada (sobresale 4 cm: nunca en el mismo plano que la pared)
	box_b(X0, wx0, 0.0, 0.75, z1, z1 + 0.04, plate)
	box_b(wx0, dx0 - 0.1, 0.0, 0.75, z1, z1 + 0.04, plate)
	box_b(dx1 + 0.1, X1, 0.0, 0.75, z1, z1 + 0.04, plate)
	# marcos de la ventana y de la puerta (chapa oscura)
	var frame_m := flat(Color(0.22, 0.34, 0.34))   # --- SS2 WORLD: marcos de chapa verde azulada (enfría el naranja)
	box_b(wx0 - 0.1, wx1 + 0.1, wy0 - 0.12, wy0, z1 - 0.02, z1 + 0.12, frame_m)
	box_b(wx0 - 0.1, wx1 + 0.1, wy1, wy1 + 0.1, z1 - 0.02, z1 + 0.08, frame_m)
	box_b(wx0 - 0.1, wx0, wy0, wy1, z1 - 0.02, z1 + 0.08, frame_m)
	box_b(wx1, wx1 + 0.1, wy0, wy1, z1 - 0.02, z1 + 0.08, frame_m)
	box_b((wx0 + wx1) / 2.0 - 0.035, (wx0 + wx1) / 2.0 + 0.035, wy0, wy1, z1 - 0.06, z1 - 0.01, frame_m)
	box_b(dx0 - 0.12, dx0, 0.0, DOOR_H + 0.12, z1 - 0.02, z1 + 0.08, frame_m)
	box_b(dx1, dx1 + 0.12, 0.0, DOOR_H + 0.12, z1 - 0.02, z1 + 0.08, frame_m)
	box_b(dx0, dx1, DOOR_H, DOOR_H + 0.12, z1 - 0.02, z1 + 0.08, frame_m)
	# paredes de los lados (adobe a la sombra, con su zócalo de chapa oxidada) y el techo (tapa el sol de arriba)
	var adobe_side := mat("res://assets/tex/adobe.png", 0.32, Color(0.78, 0.7, 0.64))
	box_b(X0 - 0.3, X0, 0.0, H, WALL_Z - 0.3, FLOOR_Z1, adobe_side)
	box_b(X1, X1 + 0.3, 0.0, H, WALL_Z - 0.3, FLOOR_Z1, adobe_side)
	box_b(X0, X0 + 0.04, 0.0, 0.75, WALL_Z, FLOOR_Z1, rust)
	box_b(X1 - 0.04, X1, 0.0, 0.75, WALL_Z, FLOOR_Z1, rust)
	box_b(X0 - 0.3, X1 + 0.3, H, H + 0.25, WALL_Z - 0.3, FLOOR_Z1 + 7.0, flat(Color(0.12, 0.09, 0.08)))
	# parches de chapa en el adobe y un caño de ventilación
	# --- SS2 WORLD: los parches y el caño se corren para la pizarra (x 5.0), el tablero de sombras (sobre el banco) y el
	# afiche del Derby (rincón del té)
	prop("scrap_patch_a", Vector3(-3.95, 3.35, z1 + 0.05), 0.035, "center")
	prop("scrap_patch_b", Vector3(7.25, 1.5, z1 + 0.05), 0.035, "center")
	prop("scrap_patch_a", Vector3(7.9, 3.0, z1 + 0.05), 0.032, "center")
	prop("vent_pipe", Vector3(-6.45, 2.9, z1 + 0.06), 0.04)


## El puerto a pleno sol detrás de la ventana y de la puerta: arena, casas con cúpula, una plataforma con su nave, el
## cielo ámbar; naves que pasan. De noche, la lluvia de chatarra.
func _build_outside() -> void:
	var sand := mat("res://assets/tex/sand.png", 0.5)
	box_b(-8.0, 26.0, -0.2, 0.0, -16.2, WALL_Z - 0.3, sand)
	# el cielo con su horizonte de dunas (lejos): por la ventana se ve sobre todo cielo, y abajo las cúpulas
	var sky := sky_backdrop(Vector2(44.0, 15.0), Vector3(6.0, 6.8, -16.4))
	sky.name = "ShopSky"
	var sm: ShaderMaterial = sky.material_override
	sm.set_shader_parameter("horizon", 0.885)
	sm.set_shader_parameter("bright", 1.12)
	sm.set_shader_parameter("star_grid", Vector2(110.0, 38.0))
	# el sol de la tarde en la ventana
	var sun_s := prop("sun", Vector3(8.2, 2.35, -16.3), 0.011, "center", 0, false)
	sun_s.modulate = Color(1.3, 1.15, 0.95)
	sun_s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_day_only.append(sun_s)
	# cúpulas sobre el horizonte, una antena y un carguero posado en su plataforma
	for d in [[-1.2, 1.0], [3.0, 1.15], [5.4, 0.85], [7.4, 1.3], [10.4, 1.0], [12.6, 0.9]]:
		var x: float = d[0]
		var w: float = d[1]
		prop("dome_cap", Vector3(x, 0.0, -15.6), w * 2.0 / 88.0)
		var lit := prop("round_window", Vector3(x - w * 0.3, w * 0.42, -15.55), 0.012, "center", 0, false)
		lit.modulate = Color(1.7, 1.3, 0.7)
		lit.visible = false
		_night_nodes.append(lit)
	prop("antenna_mast", Vector3(6.4, 0.0, -15.2), 0.024)
	prop("ship_hammerhead", Vector3(9.1, 0.0, -14.6), 0.018, "bottom")
	# naves que pasan por la ventana: el correo aguja (rápido, alto) y el escarabajo (más bajo, despacio)
	add_flyer("ship_needle", 0.02, Vector3(-6.0, 2.62, -10.5), Vector3(17.0, 2.85, -10.5), 4.0, 19.0, Vector3(-1.85, 0.0, -0.02), 90.0, 4.0)
	add_flyer("ship_beetle", 0.022, Vector3(18.0, 2.25, -13.0), Vector3(-6.0, 2.05, -13.0), 9.0, 27.0, Vector3(1.45, -0.1, -0.02), -90.0, 12.0)
	# la lluvia de chatarra por la ventana (de noche: la cámara de la noche la ve por la ventana)
	setup_streaks(AABB(Vector3(-3.0, 1.9, -14.8), Vector3(7.5, 1.7, 0.3)), 5, 0.034)

# ------------------------------------------------------------------ el mostrador

func _build_counter() -> void:
	var rust := mat("res://assets/tex/rusted_panel.png", 0.75)
	var wood := mat("res://assets/tex/wood.png", 0.7)
	var plate := mat("res://assets/tex/metal_plate.png", 0.9, Color.WHITE, 0.6)
	var cx0 := COUNTER_X0 + 0.05
	var cx1 := COUNTER_X1 - 0.05
	box_b(cx0, cx1, 0.0, COUNTER_TOP - 0.06, WALL_Z, COUNTER_Z1 - 0.04, rust)
	box_b(COUNTER_X0, COUNTER_X1, COUNTER_TOP - 0.06, COUNTER_TOP, WALL_Z, COUNTER_Z1, wood)
	# un zócalo de chapa al pie (del lado de los clientes) y una caja de cobro sobre la tabla
	box_b(cx1, cx1 + 0.03, 0.0, 0.22, WALL_Z + 0.05, COUNTER_Z1 - 0.1, plate)
	box_b(0.12, 0.58, COUNTER_TOP, COUNTER_TOP + 0.2, -3.4, -2.9, flat(Color(0.33, 0.38, 0.36)))
	box_b(0.16, 0.54, COUNTER_TOP + 0.2, COUNTER_TOP + 0.24, -3.36, -3.0, flat(Color(0.86, 0.6, 0.26)))
	# lo que el cliente dejó sobre el mostrador (un sprite de su cosa)
	counter_item = sprite("res://assets/items/radio_closed.png", 0.0075, Vector3(0.42, COUNTER_TOP, -1.2))
	counter_item.visible = false

# ------------------------------------------------------------------ el lado de Nell

func _build_nell_side() -> void:
	# el rincón del té de Kettle (izquierda)
	prop("tea_station", Vector3(-7.0, 0.0, -3.3))
	# el banco de reparación (y lo que tiene encima cuando hay trabajo)
	prop("workbench", Vector3(-5.15, 0.0, -2.95))
	bench_item = sprite("res://assets/items/radio_closed.png", 0.0075, Vector3(-4.75, 0.79, -2.88))
	bench_item.visible = false
	# la cajonera de piezas
	prop("parts_cabinet", Vector3(-3.05, 0.0, -3.55))
	# el estante de cosas reparadas (a la venta): metal, tres tablas; las cosas se ponen en refresh_shelf()
	var metal := mat("res://assets/tex/metal_plate.png", 1.2, Color(0.82, 0.8, 0.78), 0.55)
	var sx0 := -2.1
	var sx1 := -0.72
	var sz0 := -3.95
	var sz1 := -3.45
	for x in [sx0, sx1 - 0.06]:
		box_b(x, x + 0.06, 0.0, 2.05, sz0 + 0.02, sz0 + 0.08, metal)
		box_b(x, x + 0.06, 0.0, 2.05, sz1 - 0.08, sz1 - 0.02, metal)
	for y in [0.5, 1.05, 1.6]:
		box_b(sx0, sx1, y - 0.05, y, sz0, sz1, metal)
	shelf_root = Node3D.new()
	shelf_root.name = "ShelfItems"
	add_child(shelf_root)
	var sign := Label3D.new()
	sign.text = "FIXED · FOR SALE"
	UIKit.load_fonts()
	# --- POLISH LOOK (P8): un tablón pintado a mano (madera oscura con canto, letras color crema con la letra de mano)
	# en vez de texto de interfaz sobre una tabla clara que se perdía en la pared. Mismo material que las paredes
	# (mat/flat triplanar): nada nuevo que compilar. El texto sigue siendo texto (regla del README).
	sign.font = UIKit.font_hand
	sign.font_size = 64
	sign.pixel_size = 0.0028
	sign.modulate = Color(0.97, 0.9, 0.72)
	sign.outline_size = 0
	sign.position = Vector3((sx0 + sx1) / 2.0, 2.205, sz0 + 0.05)
	sign.shaded = true
	var board := box_b(sx0 - 0.04, sx1 + 0.04, 2.05, 2.36, sz0, sz0 + 0.03, mat("res://assets/tex/wood.png", 0.7, Color(0.44, 0.34, 0.26)))
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trim := flat(Color(0.2, 0.13, 0.09))
	for yy in [Vector2(2.03, 2.06), Vector2(2.35, 2.38)]:   # el canto de arriba y de abajo, un poco más adelante
		var t := box_b(sx0 - 0.05, sx1 + 0.05, yy.x, yy.y, sz0, sz0 + 0.04, trim)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign)
	# --- end POLISH LOOK
	# una caja de chatarra al pie del banco y otra al frente (profundidad)
	prop("crate", Vector3(-6.45, 0.0, -1.95), 0.03)
	prop("crate_stack", Vector3(-7.3, 0.0, 1.6), 0.032)

# ------------------------------------------------------------------ el lado de los clientes

func _build_customer_side() -> void:
	# la puerta: la hoja del dibujo (sin su marco beige) en una bisagra; se abre hacia dentro cuando alguien pasa
	door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	door_pivot.position = Vector3(DOOR_X0, 0.0, WALL_Z - 0.12)
	add_child(door_pivot)
	door_sprite = Sprite3D.new()
	door_sprite.texture = load("res://assets/props/door.png")
	door_sprite.region_enabled = true
	door_sprite.region_rect = Rect2(6, 6, 33, 66)
	door_sprite.pixel_size = DOOR_PX
	door_sprite.centered = false
	door_sprite.offset = Vector2(0, 0)
	door_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	door_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	door_sprite.double_sided = true
	door_pivot.add_child(door_sprite)
	# estante de chatarra y cajones (a la derecha de la puerta)
	prop("junk_shelf", Vector3(7.7, 0.0, -3.62))
	prop("crate_stack", Vector3(7.85, 0.0, -1.2), 0.03)
	prop("crate", Vector3(7.2, 0.0, 1.9), 0.032)

func _build_ceiling() -> void:
	# cables colgando, tres lámparas (luz cálida) y un ventilador que gira
	# (los cables van por la pared del fondo y no por el techo: arriba de todo los borra el desenfoque)
	prop("cables", Vector3(-2.3, 3.2, WALL_Z + 0.07), 0.024, "top")
	for spec in [[-5.0, -2.5, true], [-1.6, -2.4, false], [0.6, -1.8, false], [3.7, -2.3, false]]:
		var lx: float = spec[0]
		var lz: float = spec[1]
		var lamp := prop("lamp_hanging", Vector3(lx, H - 0.02, lz), 0.034, "top", 0, false)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp_sprites.append(lamp)
		var l := omni(Vector3(lx, 2.85, lz + 0.2), Color(1.0, 0.72, 0.42), 1.5, 5.2, bool(spec[2]))
		interior_lights.append([l, 1.5])

# --- POLISH LOOK (P15): las lámparas colgantes se mecen apenas (±1,5°, lento, cada una a su ritmo): la tienda no se
# ve congelada entre clientes. Solo con la tienda a la vista; la luz no se mueve (sin sombra que temble).
const LAMP_SWAY_DEG := 1.5

func _process(delta: float) -> void:
	super._process(delta)
	if lamp_sprites.is_empty() or not is_visible_in_tree():
		return
	for i in lamp_sprites.size():
		var l: Sprite3D = lamp_sprites[i]
		l.rotation.z = deg_to_rad(LAMP_SWAY_DEG) * sin(_t * (0.55 + 0.08 * i) + i * 1.7)
# --- end POLISH LOOK

# ------------------------------------------------------------------ el estante, el banco y el mostrador

## Pone en el estante las cosas de Game.shelf (hasta 6: dos por tabla), con sus estrellas. --- SS2 WORLD: con el
## Display Case, la 7.ª y la 8.ª van a la vitrina (shelf_slots()).
func refresh_shelf() -> void:
	if shelf_root == null:
		return
	for c in shelf_root.get_children():
		c.queue_free()
	var slots := [Vector2(-1.75, 1.6), Vector2(-1.08, 1.6), Vector2(-1.75, 1.05), Vector2(-1.08, 1.05), Vector2(-1.75, 0.5), Vector2(-1.08, 0.5)]
	_refresh_case()
	UIKit.load_fonts()
	for i in mini(Game.shelf.size(), slots.size()):
		var e: Dictionary = Game.shelf[i]
		var p: Vector2 = slots[i]
		var s := sprite("res://assets/items/%s_closed.png" % e.get("item", "radio"), 0.0072, Vector3(p.x, p.y, -3.66), "bottom", shelf_root)
		s.name = "Item%d" % i
		var st := Label3D.new()
		var stars := ""
		for k in 3:
			stars += "★" if k < int(e.get("stars", 0)) else "☆"
		st.text = stars
		st.font = UIKit.font_bold
		st.font_size = 28
		st.pixel_size = 0.0045
		st.modulate = Color(1.0, 0.78, 0.34)
		st.outline_size = 8
		st.outline_modulate = Color(0.12, 0.08, 0.05)
		st.position = Vector3(p.x, p.y + 0.05, -3.4)
		st.shaded = false
		shelf_root.add_child(st)

func set_bench_item(item: String) -> void:
	if item == "":
		bench_item.visible = false
		return
	bench_item.texture = load("res://assets/items/%s_closed.png" % item)
	bench_item.visible = true

func set_counter_item(item: String) -> void:
	if item == "":
		counter_item.visible = false
		return
	counter_item.texture = load("res://assets/items/%s_closed.png" % item)
	counter_item.visible = true

## El aviso del mostrador va sobre la cabeza de quien está ahí (si hay alguien).
func prompt_point(id: String) -> Vector3:
	if id == "counter" and is_instance_valid(counter_actor):
		return counter_actor.global_position + Vector3(0.0, counter_actor.top_height() + 0.42, 0.0)
	return super.prompt_point(id)

# ------------------------------------------------------------------ la puerta

## El cartel de la puerta: OPEN (crema) o CLOSED (rojo).
func set_door_sign(open: bool) -> void:
	_door_sign_open = open
	door_sprite.region_rect = Rect2(50, 6, 33, 66) if open else Rect2(6, 6, 33, 66)

## Alguien va a pasar por la puerta: se abre (una sola vez aunque pasen varios seguidos).
func door_hold() -> void:
	_door_users += 1
	if not _door_open:
		_door_open = true
		_swing(-1.75)
		Sfx.play("bell", 0.04, -8.0)

## Ya pasó. Cuando no queda nadie en la puerta, se cierra un momento después.
func door_release() -> void:
	_door_users = maxi(0, _door_users - 1)
	if _door_users > 0:
		return
	get_tree().create_timer(0.6).timeout.connect(func():
		if _door_users == 0 and _door_open:
			_door_open = false
			_swing(0.0))

## Cerrada y sin nadie (fin del día, vuelta al título).
func door_reset() -> void:
	_door_users = 0
	_door_open = false
	if _door_tw and _door_tw.is_valid():
		_door_tw.kill()
	door_pivot.rotation.y = 0.0

func _swing(to: float) -> void:
	if _door_tw and _door_tw.is_valid():
		_door_tw.kill()
	_door_tw = create_tween()
	_door_tw.tween_property(door_pivot, "rotation:y", to, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ noche

func set_night(on: bool) -> void:
	super.set_night(on)
	sun.visible = not on
	for n in _night_nodes:
		n.visible = on
	for n in _day_only:
		n.visible = not on
	if _sunbeam and _event == "sandstorm":
		_sunbeam.visible = false   # --- POLISH LOOK (P4): en el Scour no entra sol por la ventana
	_apply_lamps()   # --- SS2 WORLD: (las lámparas también según el evento)
	if _door_drift:
		_door_drift.modulate = Color(0.42, 0.36, 0.42) if on else Color(0.8, 0.66, 0.55)
	if not on and not _win.is_empty():
		set_window_sky("")   # --- SS2 WORLD: de día no hay lunas en la ventana
	env.ambient_light_color = Color(0.42, 0.42, 0.62) if on else Color(0.56, 0.55, 0.62)
	env.ambient_light_energy = 0.45 if on else 0.55
	fill.light_energy = 0.32 if on else 0.45

## La cámara de la noche: la ventana con la lluvia de chatarra a la izquierda (el libro de cuentas va a la derecha).
func night_camera() -> void:
	camera.position = NIGHT_CAM
	camera.look_at(NIGHT_LOOK, Vector3.UP)

# ------------------------------------------------------------------ el té de Kettle

## Kettle rodea el mostrador y pasa por delante de la fila sirviendo té; on_pass(i) se llama al pasar por cada sitio
## (i = 0 el mostrador, 1.. la fila). Vuelve con Nell al terminar.
func tea_walk(on_pass: Callable) -> void:
	kettle_follow = false
	kettle.hop(2)
	kettle.emote("steam", 1.0)
	await get_tree().create_timer(0.5).timeout
	var pts: Array = [Vector3(-0.35, 0, 0.75), Vector3(1.05, 0, 0.75)]
	await kettle.walk_path(pts, 2.6)
	var stops := [Vector3(1.6, 0, -1.08)]
	for q in QUEUE_SPOTS:
		stops.append(Vector3(q.x + 0.15, 0, q.z + 0.42))
	for i in stops.size():
		await kettle.walk_to(stops[i], 2.4)
		on_pass.call(i)
		kettle.emote("steam", 0.6)
		await get_tree().create_timer(0.35).timeout
	await kettle.walk_path([Vector3(1.05, 0, 0.75), Vector3(-0.35, 0, 0.75)], 2.8)
	kettle_follow = true


# ==================================================================================================================
# --- SS2 WORLD: la tienda de la ronda 2 (SS2_DESIGN §6.1-6.5, §8.10): el taller vivido, las 8 mejoras, las cosas de
# las historias, la ventana de noche. Todo se arma en los 4 pasos nuevos, escondido lo que todavía no está, y queda en
# warm_extra; después solo cambian visibilidad, cuadro, color, posición, escala y la energía de las 2 luces nuevas.

## Dónde se estrena cada mejora (la cámara se desliza ahí; §4.1).
const UPGRADE_POINTS := {"samovar": Vector3(-6.95, 0.46, -3.22), "seats": Vector3(3.2, 0.0, -3.72), "podlamp": Vector3(5.15, 3.3, -3.9),
	"coolcoil": Vector3(2.9, 3.78, -2.2), "display": Vector3(1.15, 0.0, -3.7), "partswall": Vector3(-3.05, 2.55, -3.97),
	"loupe": Vector3(-5.75, 0.79, -2.9), "neon": Vector3(3.1, 2.55, -3.97)}
const SUN_BEAM_POS := Vector3(2.7, 1.45, -3.05)
const TROPHY_Y := 2.77   # la tabla del estante de los trofeos (sobre la puerta)

var upgrades := {}                # id de la mejora -> Node3D (su prop)
var story := {}                   # id de la historia -> Node3D
var _fan: Sprite3D
var _niche: Sprite3D
var _chalk: Sprite3D
var _sunbeam: Sprite3D
var _moonbeam: Sprite3D
var _door_drift: Sprite3D
var _haze: Sprite3D
var _sun_e := -1.0                # --- POLISH LOOK (P4): la energía del sol de la ventana (el Scour la baja)
var _bunting_in: Sprite3D
var _case_items: Array = []       # los 2 lugares de la vitrina (Display Case)
var _display_light: OmniLight3D   # luz nueva 1 de 2: la vitrina (0 -> 0.5)
var _neon_light: OmniLight3D      # luz nueva 2 de 2: el neón (0 -> 0.9)
var _reveal_sparks: Array = []
var _reveal_tw: Tween
var _win := {}                    # la ventana de noche: "copper", "tin", "halos", "ring", "bigfall", "streaks"
var _sky_kind := ""
var _event := ""
var _night_ok := false

## El paso nuevo (~9 ms de script): el taller vivido, las mejoras, las cosas de las historias y la ventana de noche.
func _build_round2() -> void:
	_build_clutter()
	_build_upgrades()
	_build_story_props()
	_build_window_sky()

## El taller vivido (primer plano, pared del fondo, rayo de sol, rincones).
func _build_clutter() -> void:
	var z := WALL_Z + 0.03
	# primer plano (lo borra el desenfoque de abajo): enmarca la escena sin tapar el mostrador ni la fila
	prop("fg_bike_frame", Vector3(-6.9, H - 0.02, 2.4))
	prop("fg_cable_coil", Vector3(-6.7, 0.0, 2.75))
	prop("fg_pod_shells", Vector3(-5.6, 0.0, 3.0))
	prop("fg_engine_block", Vector3(-2.65, 0.0, 3.05))
	prop("fg_oil_drum", Vector3(3.45, 0.0, 3.0))
	# la pared del fondo llena de vida
	prop("shadow_board", Vector3(-5.15, 2.75, z))
	_niche = prop("wall_niche", Vector3(-3.05, 2.55, z))
	for x in [-5.68, -1.84, 2.0, 5.84]:
		prop("pipe_run", Vector3(x, 3.72, z + 0.01))
	_chalk = prop("chalkboard", Vector3(5.03, 1.6, z))
	# --- POLISH LOOK (P8): la radio de adorno ya no cuelga sobre el estante de "a la venta" (parecía mercadería): en su
	# lugar, el afiche del Brass Comet (como el del Derby: el marco, el pictograma de R y una línea de texto), la meta
	# de la temporada a la vista; la radio pasa a la pared de la izquierda, arriba del rincón del té
	prop("radio_wall", Vector3(-6.75, 3.2, z))
	prop("poster_frame", Vector3(-0.32, 2.98, z), 0.026)
	sprite("res://assets/ui/event_finale.png", 0.017, Vector3(-0.32, 3.13, z + 0.012), "center")
	var cl := Label3D.new()
	cl.text = "THE BRASS COMET\nNIGHT 10"
	cl.font = UIKit.font_bold
	cl.font_size = 24
	cl.pixel_size = 0.0027
	cl.modulate = Color(0.55, 0.2, 0.16)
	cl.outline_size = 0
	cl.shaded = true
	cl.position = Vector3(-0.32, 2.72, z + 0.014)
	add_child(cl)
	# --- end POLISH LOOK
	prop("trophy_shelf", Vector3(6.18, 2.62, z))
	prop("coat_rack", Vector3(6.95, 0.0, -3.3))
	prop("bot_torso", Vector3(7.6, 0.0, -2.6))
	# el afiche del Glasspan Derby en el rincón del té (el pictograma de R y una línea de texto)
	prop("poster_frame", Vector3(-7.3, 2.2, z), 0.028)
	sprite("res://assets/ui/event_race.png", 0.018, Vector3(-7.3, 2.36, z + 0.012), "center")
	UIKit.load_fonts()
	var lb := Label3D.new()
	lb.text = "GLASSPAN DERBY\nDAY 9"
	lb.font = UIKit.font_bold
	lb.font_size = 24
	lb.pixel_size = 0.0026
	lb.modulate = Color(0.55, 0.2, 0.16)
	lb.outline_size = 0
	lb.shaded = true
	lb.position = Vector3(-7.32, 1.9, z + 0.014)
	add_child(lb)
	# el ventilador del techo (quieto; gira con el Cool Coil)
	_fan = prop("ceiling_fan", Vector3(2.9, H - 0.02, -2.2), 0.03, "top", 0, false)
	_fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# la arena que entra por la puerta (acostada en el piso; más grande en el Scour)
	_door_drift = glow("sand_drift", Vector3(6.05, 0.012, -3.15), 0.03, "center")
	_door_drift.rotation_degrees.x = -90.0
	_door_drift.modulate = Color(0.8, 0.66, 0.55)
	# el rayo de sol con polvo (de día) y el de luna (de noche): un cuadro inclinado de la ventana al piso, sin luz y con
	# alfa (la familia de la lluvia de chatarra), sin partículas
	_sunbeam = soft("sunbeam", SUN_BEAM_POS, 0.022)
	_sunbeam.rotation_degrees.z = -20.0
	_sunbeam.modulate = Color(1.75, 1.5, 1.15, 1.0)
	animate(_sunbeam, 1.25)
	_day_only.append(_sunbeam)
	_moonbeam = soft("moonbeam", SUN_BEAM_POS, 0.022)
	_moonbeam.rotation_degrees.z = -20.0
	_moonbeam.modulate = Color(1.4, 1.4, 1.7, 1.0)
	later(_moonbeam)
	_night_nodes.append(_moonbeam)

## Las 8 mejoras (escondidas hasta comprarlas), sus 2 luces y las chispas del estreno.
func _build_upgrades() -> void:
	upgrades["samovar"] = prop("up_samovar", UPGRADE_POINTS["samovar"])
	upgrades["seats"] = prop("up_seats", UPGRADE_POINTS["seats"])
	upgrades["podlamp"] = prop("up_podlamp", UPGRADE_POINTS["podlamp"])
	upgrades["coolcoil"] = prop("up_coolring", UPGRADE_POINTS["coolcoil"])
	var case := Node3D.new()
	case.name = "DisplayCase"
	add_child(case)
	case.position = UPGRADE_POINTS["display"]
	prop("up_display", Vector3.ZERO, -1.0, "", 0, true, case)
	for i in 2:
		var it := sprite("res://assets/items/radio_closed.png", 0.0062, Vector3(-0.25 + i * 0.5, 0.95, 0.04), "bottom", case)
		it.name = "CaseItem%d" % i
		_case_items.append(it)
	upgrades["display"] = case
	upgrades["partswall"] = prop("up_partswall", UPGRADE_POINTS["partswall"] + Vector3(0.0, 0.0, 0.03))
	upgrades["loupe"] = prop("up_loupe", UPGRADE_POINTS["loupe"])
	var neon := glow("up_neon", UPGRADE_POINTS["neon"] + Vector3(0.0, 0.0, 0.05))
	animate(neon, 0.7)
	upgrades["neon"] = neon
	for id in upgrades:
		(upgrades[id] as Node3D).name = "Up_" + id
		later(upgrades[id])
	_display_light = toggle_omni(Vector3(1.15, 1.95, -3.15), Color(1.0, 0.9, 0.72), 0.5, 2.6)
	_display_light.name = "DisplayLight"
	_neon_light = toggle_omni(Vector3(3.1, 2.3, -3.3), Color(1.0, 0.55, 0.85), 0.9, 4.6)
	_neon_light.name = "NeonLight"
	for i in 8:
		var sp := soft("spark", Vector3.ZERO, 0.03)
		sp.name = "RevealSpark%d" % i
		_reveal_sparks.append(later(sp))

## Las cosas de las historias (el cajón de Rook, el certificado, los trofeos, la placa, los núcleos,
## la banda por la ventana) y el decorado de los eventos adentro (bruma del Scour, banderines de Bronzemoon).
func _build_story_props() -> void:
	var z := WALL_Z + 0.04
	story["crate"] = prop("crate_sealed", Vector3(-7.25, 0.0, -2.4))
	story["certificate"] = prop("frame_certificate", Vector3(0.95, 2.5, z))
	story["cup"] = prop("trophy_cup", Vector3(5.75, TROPHY_Y, z + 0.06))
	story["key"] = prop("lucky_key", Vector3(6.18, TROPHY_Y, z + 0.06))
	story["ribbon"] = prop("ribbon_bronze", Vector3(6.6, TROPHY_Y, z + 0.06))
	story["plaque"] = prop("plaque_paid", Vector3(4.92, 1.0, z), 0.019)
	story["cores"] = prop("lamp_core_prop", Vector3(3.1, 1.24, -3.86))
	var band := prop("band_trio", Vector3(4.3, 0.0, -9.5))
	animate(band, 2.2)
	story["band"] = band
	for id in story:
		(story[id] as Node3D).name = "Story_" + id
		later(story[id])
	_haze = glow("window_haze", Vector3(3.1, 2.2, -3.93))
	_haze.name = "ScourHaze"
	later(_haze)
	_bunting_in = prop("bunting", Vector3(3.1, 3.02, -3.9), 0.014, "top")
	_bunting_in.name = "BuntingInside"
	later(_bunting_in)

## La ventana de noche (las lunas Copper y Tin, el anillo, la gran estela de Bigfall, la lluvia de la Gran
## Lluvia): sprites lejos, detrás de la ventana, que solo se ven de noche.
func _build_window_sky() -> void:
	var zz := -16.1
	_win["halos"] = [later(glow("moon_halo", Vector3(-0.6, 2.85, zz - 0.15), 0.022)), later(glow("moon_halo", Vector3(2.45, 3.25, zz - 0.15), 0.0095))]
	_win["copper"] = later(glow("moon_copper", Vector3(-0.6, 2.85, zz), 0.022, "", 1))
	_win["tin"] = later(glow("moon_tin", Vector3(2.45, 3.25, zz), 0.022, "", 2))
	var ring_s := glow("sky_ring", Vector3(0.9, 2.3, zz - 0.1), 0.013)
	ring_s.modulate = Color(0.85, 0.85, 1.25)
	_win["ring"] = later(ring_s)
	var big := soft("starfall", Vector3(0.6, 3.05, zz + 0.05), 0.075)
	big.modulate = Color(1.9, 1.15, 0.6, 1.0)
	_win["bigfall"] = later(big)
	var streaks: Array = []
	for spec in [[Vector3(-1.4, 3.5, zz), 0.035], [Vector3(0.4, 2.7, zz), 0.03], [Vector3(1.8, 3.6, zz), 0.04], [Vector3(2.9, 2.5, zz), 0.03],
			[Vector3(-0.2, 1.9, zz), 0.028]]:
		var st := soft("starfall", spec[0], float(spec[1]))
		st.modulate = Color(1.4, 1.2, 0.9, 1.0)
		streaks.append(later(st))
	_win["streaks"] = streaks

# ------------------------------------------------------------------ la API (§8.10)

## Las mejoras compradas, visibles (Game.has_fitting); las 2 luces por energía; el ventilador gira con el Cool Coil; la
## pared de latitas reemplaza al nicho y se llena con el cajón de piezas.
func refresh_upgrades() -> void:
	if upgrades.is_empty():
		return
	for id in upgrades:
		var n: Node3D = upgrades[id]
		n.visible = Game.has_fitting(id)
		n.scale = Vector3.ONE
	_niche.visible = not Game.has_fitting("partswall")
	var pw: Sprite3D = upgrades["partswall"]
	var pt := Game.parts_total()
	pw.frame = 0 if pt < 6 else (1 if pt < 14 else 2)
	if Game.has_fitting("coolcoil"):
		if not _anim_has(_fan):
			animate(_fan, 9.0)
	else:
		_anim_drop(_fan)
		_fan.frame = 0
	_display_light.light_energy = 0.5 if Game.has_fitting("display") else 0.0
	_neon_light.light_energy = 0.9 if Game.has_fitting("neon") else 0.0
	_refresh_case()

func _anim_has(s: Sprite3D) -> bool:
	for a in _anim_sprites:
		if a[0] == s:
			return true
	return false

func _anim_drop(s: Sprite3D) -> void:
	for a in _anim_sprites.duplicate():
		if a[0] == s:
			_anim_sprites.erase(a)

## La vitrina (Display Case): la 7.ª y la 8.ª cosa del estante, con su luz.
func _refresh_case() -> void:
	if _case_items.is_empty():
		return
	var owned := Game.has_fitting("display")
	for i in _case_items.size():
		var s: Sprite3D = _case_items[i]
		var k := 6 + i
		s.visible = owned and k < mini(Game.shelf.size(), shelf_slots())
		if s.visible:
			s.texture = load("res://assets/items/%s_closed.png" % String(Game.shelf[k].get("item", "radio")))

## El estreno de una mejora: un pop de escala y 8 chispas que saltan alrededor (sprites armados al arrancar).
func reveal_upgrade(id: String) -> void:
	var n: Node3D = upgrades.get(id)
	if n == null:
		return
	n.visible = true
	n.scale = Vector3.ONE * 0.6
	if _reveal_tw and _reveal_tw.is_valid():
		_reveal_tw.kill()
	_reveal_tw = create_tween().set_parallel(true)
	_reveal_tw.tween_property(n, "scale", Vector3.ONE * 1.12, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reveal_tw.tween_property(n, "scale", Vector3.ONE, 0.3).set_delay(0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var c := upgrade_point(id) + Vector3(0.0, 0.6 if UPGRADE_POINTS[id].y < 0.5 else 0.0, 0.25)
	for i in _reveal_sparks.size():
		var s: Sprite3D = _reveal_sparks[i]
		var a := TAU * i / _reveal_sparks.size()
		s.position = c
		s.visible = true
		s.modulate = Color(1.7, 1.45, 1.0, 1.0)
		var to := c + Vector3(cos(a) * 0.9, sin(a) * 0.7 + 0.2, 0.05)
		_reveal_tw.tween_property(s, "position", to, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_reveal_tw.tween_property(s, "modulate:a", 0.0, 0.35).set_delay(0.4)
	_reveal_tw.chain().tween_callback(func():
		for s in _reveal_sparks:
			(s as Sprite3D).visible = false)
	refresh_upgrades.call_deferred()

func upgrade_point(id: String) -> Vector3:
	return UPGRADE_POINTS.get(id, Vector3(0.0, 1.5, -3.5))

## "crate" bool, "certificate" bool, "cup" / "key" / "ribbon" bool, "plaque" bool, "cores" 0..3, "band" bool
func set_story_prop(id: String, value) -> void:
	var n: Node3D = story.get(id)
	if n == null:
		return
	if id == "cores":
		var c := clampi(int(value), 0, 3)
		n.visible = c > 0
		(n as Sprite3D).frame = c
	else:
		n.visible = bool(value)

## "" | sandstorm | festival | finale (lo de adentro): la bruma ocre en la ventana y la arena grande en la puerta; los
## banderines en la ventana; las lámparas más cálidas en la Gran Lluvia.
func set_event(id: String) -> void:
	_event = id
	if _haze == null:
		return
	_haze.visible = id == "sandstorm"
	# --- POLISH LOOK (P4): el Scour tapa el sol: sin el rayo con polvo en el piso y con la luz de la ventana a un tercio
	if _sun_e < 0.0:
		_sun_e = sun.light_energy
	sun.light_energy = _sun_e * (0.35 if id == "sandstorm" else 1.0)
	_sunbeam.visible = not night and id != "sandstorm"
	# --- end POLISH LOOK
	_door_drift.frame = 1 if id == "sandstorm" else 0
	_door_drift.pixel_size = 0.04 if id == "sandstorm" else 0.03
	_bunting_in.visible = id == "festival"
	_apply_lamps()

## Las lámparas de adentro según la noche y el evento (el Scour las baja un poco; la Gran Lluvia las calienta).
func _apply_lamps() -> void:
	var k := 1.25 if night else 1.0
	if _event == "sandstorm":
		k *= 0.85
	elif _event == "finale":
		k *= 1.1
	var col := Color(1.0, 0.66, 0.36) if _event == "finale" else Color(1.0, 0.72, 0.42)
	for pair in interior_lights:
		(pair[0] as OmniLight3D).light_energy = float(pair[1]) * k
		(pair[0] as OmniLight3D).light_color = col

## "" | "moons" | "bigfall" | "bronzemoon" | "starfall": lo que se ve por la ventana de noche (Copper gibosa y Tin
## media; la gran estela la noche antes de Bigfall; las dos llenas con halo de bronce; muchas estelas).
func set_window_sky(kind: String) -> void:
	_sky_kind = kind
	if _win.is_empty():
		return
	var on := kind != ""
	var full := kind == "bronzemoon"
	(_win["copper"] as Sprite3D).visible = on
	(_win["tin"] as Sprite3D).visible = on
	(_win["copper"] as Sprite3D).frame = 0 if full else 1
	(_win["tin"] as Sprite3D).frame = 0 if full else 2
	(_win["ring"] as Sprite3D).visible = on
	for h in _win["halos"]:
		(h as Sprite3D).visible = full
	(_win["bigfall"] as Sprite3D).visible = kind == "bigfall"
	for st in _win["streaks"]:
		(st as Sprite3D).visible = kind == "starfall"

## Cuántas cosas caben a la vista en el estante (6 + el Display Case).
func shelf_slots() -> int:
	return 6 + Season.n("shelf_slots")

## Las reparaciones de hoy en la pizarra: 0, 1-2, 3-5, 6 o más rayitas.
func set_chalk(n: int) -> void:
	if _chalk:
		_chalk.frame = 0 if n <= 0 else (1 if n <= 2 else (2 if n <= 5 else 3))
