extends Node
## Secondhand Stars: el flujo del juego (--- SS CORE).
## título -> introducción (3 frases sobre el anillo y la lluvia de chatarra) -> MAÑANA en el Starfall Market (cápsulas
## de Raker con regateo, piezas de Mags, "Open shop" en la puerta) -> el DÍA ABIERTO (5 minutos, 9 AM - 6 PM: la fila,
## la paciencia, el mostrador: reparar en el banco / vender del estante regateando / decir que no; el té de Kettle;
## reacondicionar lo roto de las cápsulas) -> las 6 PM -> la NOCHE (el libro de cuentas, la lluvia de chatarra por la
## ventana) -> día 2, día 3 -> el DÍA DE LA CUOTA (pagada o no, lo hecho, "Thanks for playing the prototype").
## Piezas: ShopWorld / StreetWorld (scripts/world), ShopDay (la fila y el reloj), Hud, Dialogs, Screens (scripts/ui);
## BenchUI / HaggleUI / PodUI son de BENCH y se usan SOLO por su contrato (open, finished, close_now, is_open, bot_play).
## Lo que se conserva de la semilla: el post-proceso HD-2D con bandas de desenfoque CHICAS (POST_*), los ganchos de
## pruebas (--demo=<nombre>, --shot=<png> --frames=<n>, --days=<n>), PadCursor con sus Callables y el aviso con la
## tecla del aparato en uso (Hud.show_prompt / UIKit.interact_key).
## Las demos y el bot de pruebas están en scripts/demo_kit.gd (DemoKit).

enum Phase { BOOT, TITLE, INTRO, MORNING, OPEN, NIGHT, END }

const GAME_TITLE := "Secondhand Stars"
## El post-proceso HD-2D (shaders/hd2d_post.gdshader). Bandas de desenfoque CHICAS (el cliente encontró demasiado
## grandes las de Midnight Cauldron: 0.46 ± 0.22, transición 0.30). Tienda: nítido entre el 15 % y el 85 % del alto.
## Calle (el mercado: ahí el cliente notaba más el desenfoque): todavía más chicas, nítido entre el 7 % y el 85 %.
const POST_SHOP := {"focus_center": 0.5, "focus_half": 0.35, "focus_falloff": 0.13, "max_lod": 2.6, "vignette_strength": 0.3}
const POST_STREET := {"focus_center": 0.46, "focus_half": 0.39, "focus_falloff": 0.1, "max_lod": 2.4, "vignette_strength": 0.26}
const POST_SKY := {"focus_center": 0.5, "focus_half": 0.42, "focus_falloff": 0.08, "max_lod": 2.0, "vignette_strength": 0.34}

var _quitting := false
var phase := Phase.BOOT
var shop: ShopWorld
var street: StreetWorld
var world: SetKit            # el escenario activo
var day: ShopDay
var post: ColorRect
var post_mat: ShaderMaterial
var hud: Hud
var dialogs: Dialogs
var screens: Screens
var modal_root: Control
var fade: ColorRect
var pad: PadCursor
# --- BOOT: sin tipo: así sus scripts (y los de sus piezas, ~4300 líneas) no se compilan en el primer cuadro del juego,
# sino cuando se crean, con el título ya en pantalla (_make_bench / _make_haggle / _make_pod_ui)
var bench          # BenchUI
var haggle         # HaggleUI
var pod_ui         # PodUI
# --- SS2 SEASON: el tablero (RankScreens) y la noche del cometa (GalaScene): se arman escondidos de fondo y se reusan
var rank           # RankScreens
var gala           # GalaScene
var _revealing := false       # el estreno de las mejoras al abrir (cualquier tecla lo salta)
var _reveal_skip := false
var after_hours := false      # de noche, el banco después de cerrar (§2.7)
var _story_actor: Actor       # quien habla en un momento de historia en la calle (se borra al terminar)
var night_boards := 0         # (el bot) cuántas veces se abrió el tablero de la noche
var galas_played := 0         # (el bot) cuántas veces se jugó la noche del cometa
# --- end SS2 SEASON

var busy := false            # una transición o un paso automático (no se camina ni se usa nada)
var menu_open := false
var job := {}                # el trabajo del banco: {"kind": "repair"|"refurb", "v", "item", "fault", "stage", "job", "result"}
var sale := {}               # la venta en curso: {"v", "index", "item", "stars", "base"}
var pod_pick := {}           # la cápsula que se está regateando: {"index", "pod"}
var tea_running := false
var _last_minute := -1

# pruebas automáticas / capturas (el patrón de Midnight Cauldron)
var shot_path := ""
var shot_frames := 0
var frame := 0
var demo := ""
var autoplay_days := 10   # --- SS2 SEASON: la campaña (era 3)
var errors := 0

# --- BOOT: el arranque por pasos (ver _boot)
signal boot_finished
var boot_ready := false      # todo armado y calentado (también lo que se prepara con el título ya en pantalla)
var boot_screen: BootScreen
var _boot_log := false       # --bootlog: una línea por paso (las pruebas de arranque)
var _boot_us := 0            # cuándo empezó el paso actual (usec)
var _boot_t0 := 0
var _boot_steps := {}        # paso -> ms de trabajo de ese cuadro (el resumen "BOOT done")
var _boot_bg_n := 0          # pasos de fondo hechos / previstos (la barrita si alguien espera)
var _boot_bg_total := 1
var _boot_pscale := 0.5      # --- BOOT2: la parte del título llena la barra hasta la mitad; lo de fondo, el resto
var _last_input_ms := -100000
var _ship_walk_was := false   # --- SS2 SHIP: se podía caminar el cuadro anterior (el cursor del mando, ver _process)
var _warm_vp: SubViewport    # la tienda se arma y se calienta aquí (otro mundo 3D) mientras el título está en pantalla
var _boot_shot := ""         # --bootshot=<carpeta>: una captura por paso (escritorio; las pruebas de arranque)
var _boot_jump := ""         # --bootjump=night | closing (pruebas: ver _boot_test_jump)
var _draw_us := 0
var _draw_ms := 0.0          # (con --bootlog) cuánto tardó el último dibujo: ahí se compilan los shaders

func _ready() -> void:
	get_window().title = GAME_TITLE
	get_viewport().physics_object_picking = true
	_parse_args()
	if demo == "":
		_boot()   # --- BOOT: el juego de verdad arma todo de a poco, con la pantalla de carga (ver _boot)
		return
	# las demos y las pruebas: todo armado de una vez, como antes
	_make_shop()
	_make_street()
	_setup_post()
	_make_hud()
	modal_root = _layer(5)
	_make_bench()
	_make_haggle()
	_make_pod_ui()
	_make_dialogs_screens()
	_make_rank()   # --- SS2 SEASON
	_make_gala()
	_build_fade()
	_make_day()
	day.setup(shop, hud)
	_make_pad()
	Sfx.apply_volumes()
	boot_ready = true
	fade.color.a = 0.0
	if _bench_demo(demo):
		return
	if _lane_demo(demo):   # --- SS2 SEASON: las demos de las líneas de la ronda 2 (scripts/demos/*_demo.gd)
		return
	var d = load("res://scripts/demo_kit.gd").new()   # (--- BOOT: por ruta: el juego no lo compila al arrancar)
	d.name = "Demo"
	add_child(d)
	d.run(self, demo)

# --- BOOT: las piezas del armado (las demos las hacen todas juntas en _ready; el juego, de a una por cuadro en _boot)

func _make_shop() -> void:
	shop = ShopWorld.new()
	add_child(shop)
	shop.build()
	_wire_world(shop)

func _make_street() -> void:
	street = StreetWorld.new()
	add_child(street)
	street.build()
	_wire_world(street)

func _wire_world(w: SetKit) -> void:
	w.walker.can_walk = can_walk
	w.station_clicked.connect(_on_station_clicked)
	if w == shop:
		Game.shelf_changed.connect(func(): shop.refresh_shelf())

func _make_hud() -> void:
	hud = Hud.new()
	_layer(2).add_child(hud)
	hud.menu_pressed.connect(open_menu)
	hud.rank_pressed.connect(open_rank_board)   # --- SS2 SEASON: el chip del tablero
	hud.prompt_pressed.connect(func():
		if can_walk() and world and world.walker.current != "" and bool(station_verb(world.walker.current)[1]):
			use_station(world.walker.current))

func _make_bench() -> void:
	bench = load("res://scripts/ui/bench_ui.gd").new()
	modal_root.add_child(bench)
	bench.finished.connect(_on_bench_finished)

func _make_haggle() -> void:
	haggle = load("res://scripts/ui/haggle_ui.gd").new()
	modal_root.add_child(haggle)
	haggle.finished.connect(_on_haggle_finished)

func _make_pod_ui() -> void:
	pod_ui = load("res://scripts/ui/pod_ui.gd").new()
	modal_root.add_child(pod_ui)
	pod_ui.finished.connect(_on_pod_finished)

# --- SS2 SEASON: el tablero y la gala (scripts que reemplaza la línea RANK; se cargan por ruta)
func _make_rank() -> void:
	rank = load("res://scripts/ui/rank_screens.gd").new()
	rank.name = "RankScreens"
	_layer(7).add_child(rank)

func _make_gala() -> void:
	gala = load("res://scripts/world/gala_scene.gd").new()
	gala.name = "GalaScene"
	add_child(gala)

## Las demos de las líneas (S: season_demo, R: rank_demo, W: world_demo): static handles(name) / run(main, name).
func _lane_demo(name: String) -> bool:
	for lane in ["season", "rank", "world"]:
		var path := "res://scripts/demos/%s_demo.gd" % lane
		if not ResourceLoader.exists(path):
			continue
		var sc: Script = load(path)
		if sc and sc.handles(name):
			sc.run(self, name)
			return true
	return false
# --- end SS2 SEASON

func _make_dialogs_screens() -> void:
	dialogs = Dialogs.new()
	_layer(6).add_child(dialogs)
	screens = Screens.new()
	_layer(7).add_child(screens)
	screens.title_choice.connect(_on_title_choice)
	screens.intro_done.connect(_on_intro_done)
	screens.ledger_done.connect(_on_ledger_done)
	screens.closing_choice.connect(_on_closing_choice)

## ShopDay se crea antes que la tienda (no hace nada hasta setup(shop, hud) y open_day).
func _make_day() -> void:
	day = ShopDay.new()
	day.name = "ShopDay"
	add_child(day)
	day.at_counter.connect(_on_at_counter)
	day.left.connect(_on_left)
	day.closing_started.connect(_on_closing)
	day.day_over.connect(_on_day_over)

func _make_pad() -> void:
	pad = PadCursor.new()
	pad.buttons_root = _pad_root
	pad.world_picks = func(): return world.pad_picks() if world else []
	pad.camera = func(): return world.camera if world else null
	pad.modal_open = modal_open
	# --- SS SHIP: la A del mando también avanza la cápsula («A / X open») y la tarjeta del banco («A done») aunque el
	# cursor no esté sobre el botón (antes la A hacía clic en el vacío y no pasaba nada)
	# (--- BOOT: el banco y la cápsula pueden no existir todavía en el título)
	pad.dialog_waiting = func(): return dialogs.is_open() or screens.is_open() or (pod_ui != null and pod_ui.is_open()) or (bench != null and bench.is_open() and bench.step == bench.get_script().Step.RESULT) or (rank != null and rank.is_open())   # --- SS2 SEASON: A = Espacio en el tablero (pedido de RANK)
	# --- SS2 RANK: en la noche del cometa A también es Espacio (siguiente / el botón elegido), como en el tablero
	var dw: Callable = pad.dialog_waiting
	pad.dialog_waiting = func(): return dw.call() or (gala != null and gala.is_open())
	# --- end SS2 RANK
	pad.y_key = KEY_R   # --- SS2 SEASON: Y = el tablero (como la tecla R)
	add_child(pad)
	pad.device_changed.connect(func(_on): hud.hide_prompt())

## Las demos de BENCH (scripts/ui/bench_demo.gd: --demo=bench_radio | bench_bot | bench_thruster | haggle_buy |
## haggle_sell | pod | pod_reveal | benchtest, con --step=...) corren sobre el decorado de CORE en cuanto ese archivo
## está en el proyecto: el banco en la tienda abierta; el regateo y la cápsula en la calle de la mañana. Sin él, nada
## (y "pod" es la demo de DemoKit). Se carga por ruta para que este archivo compile con o sin BENCH.
func _bench_demo(name: String) -> bool:
	var path := "res://scripts/ui/bench_demo.gd"
	if not ResourceLoader.exists(path):
		return false
	var bd: Script = load(path)
	if bd == null or not bd.handles(name):
		return false
	Game.new_game_state()
	Game.day = 2
	Game.credits = 140      # (--- SS MERGE: como una mañana del día 2 del balance)
	Game.intro_seen = true
	Game.tips_seen["first_done"] = true
	if name.begins_with("bench") and name != "benchtest":
		open_shop_now()
		day.clear()
		shop.walker.teleport(ShopWorld.STATIONS["bench"]["x"], -1)
		shop.snap_camera()
	elif name == "haggle_sell":
		# --- SS MERGE: una venta se regatea en la tienda, con el cliente en el mostrador (no en la calle)
		open_shop_now()
		day.clear()
		day.running = true
		day.shop_t = 140.0
		var who := String(bd.arg("who", "gorrum"))
		var wants: Array = Data.CAST.get(who, {}).get("buys", []) + ["radio"]
		day.demo_fill([{"who": "pipip", "kind": "repair", "item": "helperbot", "fault": "cell", "p": 0.7}],
			{"who": who, "kind": "buy", "wants": [wants[0]]})
		day.begin_talk()
		day.start_work()
		shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
		shop.snap_camera()
		hud.set_clock(day.minutes(), "open")
	else:
		Game.roll_pods()
		begin_morning()
		street.walker.teleport(StreetWorld.STATIONS["pods"]["x"], 1)
		street.snap_camera()
	bd.run(self, name)
	return true

# ------------------------------------------------------------------ capas, post-proceso, fundido

func _layer(n: int) -> Control:
	var l := CanvasLayer.new()
	l.layer = n
	add_child(l)
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.theme = UIKit.theme()
	l.add_child(c)
	return c

func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/hd2d_post.gdshader")
	post.material = post_mat
	layer.add_child(post)
	set_post(POST_SHOP)

func set_post(p: Dictionary) -> void:
	for k in p:
		post_mat.set_shader_parameter(k, p[k])

func _build_fade() -> void:
	var l := CanvasLayer.new()
	l.layer = 20
	add_child(l)
	fade = ColorRect.new()
	fade.color = Color(0.03, 0.02, 0.02, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_child(fade)

func fade_to(a: float, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, t)
	await tw.finished

## Activa un escenario (el otro se apaga: ni se dibuja ni procesa).
func use_world(w: SetKit) -> void:
	for x in [shop, street]:
		if x and x != w:   # (--- BOOT: la tienda no existe todavía mientras carga el título)
			x.activate(false)
	world = w
	w.activate(true)
	set_post(POST_STREET if w == street else POST_SHOP)

# ------------------------------------------------------------------ --- BOOT: el arranque, por pasos

## Antes (ronda de SS SHIP), todo se armaba en _ready y después se dibujaban los dos escenarios de día y de noche
## detrás de un fundido negro (warmup): en la web eso era un primer cuadro de ~4 s (armado + 0,6 s de audio + ~90
## programas de shader) con la página congelada sobre el logo de Godot, y después ~5 s de negro con cuadros de 0,4-2 s.
## Ahora:
##   1. el primer cuadro solo dibuja la pantalla de carga (BootScreen: la imagen de arranque + una barra que avanza);
##   2. CARGA (con la barra): los bucles del título, la calle por partes, la interfaz del título, y los shaders de la
##      calle de día y de noche, de a una familia de shader por cuadro (_warm_world): ningún cuadro compila mucho;
##   3. el título aparece (el logo vuela a su sitio) y ya responde;
##   4. DE FONDO, un paso por cuadro (y en pausa mientras el jugador mueve el ratón o aprieta algo): la tienda se arma
##      y se calienta de día y de noche en un SubViewport con su propio mundo (no se ve), después pasa al mundo
##      principal; el banco, el regateo, la cápsula; los demás bucles de música;
##   5. si el jugador elige algo en el título antes de que termine el paso 4, el fundido a negro espera lo que falta
##      con una barrita (sigue de a un paso por cuadro).
## --- BOOT2: el cliente prefirió esperar en la carga y no después (con «Continue» el juego se sentía lento): el paso 4
## ahora va ANTES del título, todavía bajo la pantalla de carga (la barra: la primera mitad el paso 2, la segunda el 4).
## Cuando el título aparece ya está todo armado y calentado; _wait_boot ya no espera nunca.
## Lo que el calentamiento viejo evitaba (tirones al abrir la tienda, al llegar la noche, en la introducción) sigue
## evitado: todo eso se compila antes de que se use.
func _boot() -> void:
	_boot_t0 = Time.get_ticks_msec()
	_boot_us = Time.get_ticks_usec()
	if _boot_log:
		RenderingServer.frame_pre_draw.connect(func(): _draw_us = Time.get_ticks_usec())
		RenderingServer.frame_post_draw.connect(func(): _draw_ms = (Time.get_ticks_usec() - _draw_us) / 1000.0)
	phase = Phase.BOOT
	set_process(false)          # (_process usa el HUD, el banco...: todavía no existen)
	var bl := CanvasLayer.new()
	bl.layer = 30
	add_child(bl)
	boot_screen = BootScreen.new()
	bl.add_child(boot_screen)
	await _boot_step("screen")   # (el primer cuadro: solo la pantalla de carga, sin texto)
	boot_screen.set_progress(0.03, "Sweeping the stall...")
	# los bucles del título (en la web cada uno se decodifica entero: un cuadro cada uno)
	Sfx.prewarm_one("music_title")
	await _boot_step("audio_title", 0.1, "Tuning the radio...")
	Sfx.prewarm_one("amb_wind")
	await _boot_step("audio_wind", 0.13)
	# la calle (escondida mientras se arma: si no, su cámara la dibujaría a medias)
	street = StreetWorld.new()
	add_child(street)
	street.visible = false
	var steps := street.build_steps()
	for i in steps.size():
		steps[i].call()
		await _boot_step("street_%d" % i, 0.13 + 0.17 * (i + 1) / steps.size(), "Raising the awnings...")
	_wire_world(street)
	_setup_post()
	post.visible = false
	await _boot_step("post", 0.32)
	_make_hud()
	await _boot_step("hud", 0.36)
	modal_root = _layer(5)      # (el banco, el regateo y la cápsula entran aquí después)
	_make_dialogs_screens()
	_build_fade()
	fade.color.a = 0.0          # (la pantalla de carga tapa todo)
	_make_day()
	_make_pad()
	Sfx.apply_volumes()
	await _boot_step("ui", 0.4, "Polishing the stars...")
	# los shaders de la calle: de día y de noche (la introducción y el final son de noche). Nadie la ve (la tapa la
	# pantalla de carga): se dibuja a 1/4 de resolución (los shaders son los mismos; la GPU trabaja 16 veces menos).
	get_viewport().scaling_3d_scale = 0.25
	use_world(street)
	post.visible = false
	await _warm_world(street, "street_day", 0.4, 0.72, false, "flyers")
	street.set_night(true)
	await _warm_world(street, "street_night", 0.72, 0.94, false, "streaks")
	await _warm_gala_night()   # --- SS2 MERGE
	street.set_night(false)
	# --- BOOT2: lo de fondo (la tienda, el banco, el regateo, la cápsula, la música), aquí, bajo la pantalla de carga
	# (la calle sigue a 1/4 de resolución: nadie la ve)
	await _boot_background()
	# --- end BOOT2
	get_viewport().scaling_3d_scale = 1.0
	# el título, detrás de la pantalla de carga (su primer dibujo compila lo poco que le falta a la interfaz y al
	# post-proceso); su logo aparece cuando llega el de la pantalla de carga
	post.visible = true
	show_title()
	screens.show_title_logo(false)
	await _boot_step("title", 1.0, "Open for business!")
	await boot_screen.reveal(screens.title_logo_rect())
	screens.show_title_logo(true)
	boot_screen.get_parent().queue_free()
	boot_screen = null
	set_process(true)
	print("BOOT title %d ms" % (Time.get_ticks_msec() - _boot_t0))
	if _boot_jump != "":   # --- BOOT2: (pruebas) ahora después del título
		_boot_test_jump(_boot_jump)

## --- SS2 MERGE: dos cuadros más de la calle de noche, bajo la pantalla de carga. _warm_world calienta con TODAS las
## luces que se prenden después (la de los farolitos, el neón de Shine Again: SetKit.toggle_lights), así que (1) la noche
## de siempre, con esas luces apagadas (la introducción), y (2) la noche de la gala (el decorado de la final, Shine
## Again abierta, la banda, gente en los lugares de la gala con un corazón encima) compilaban sus variantes de luz
## recién en la gala (3 programas en medio de la fiesta en la web). Cada cuadro compila pocas: los dos van enteros.
func _warm_gala_night() -> void:
	var was := street.process_mode
	street.process_mode = Node.PROCESS_MODE_DISABLED
	await _warm_frame(false, "street_night_plain", 0.95)
	street.set_event("finale")
	street.set_rival_open(true)
	street.set_vendor_open(true)
	street.set_band(true)
	street.set_night(true)
	var probes: Array = []
	var ids := ["gorrum", "zib", "oona", "pipip", "rook", "clatter", "singer", "timekeeper", "tracker", "inspector",
		"hermit", "dockmaster", "raker", "mags"]
	var spots: Array = street.gala_spots()
	for i in mini(spots.size(), ids.size()):
		if not ResourceLoader.exists("res://assets/chars/%s_idle.png" % ids[i]):
			continue
		var a: Actor = street.make_actor(String(ids[i]), spots[i], 1 if i % 2 == 0 else -1)
		a.quiet = true
		a.emote("heart", 9.0)
		probes.append(a)
	await _warm_frame(false, "street_night_gala", 0.96)
	for a in probes:
		a.queue_free()
	street.set_band(false)
	street.set_vendor_open(false)
	street.set_rival_open(false)
	street.set_event("")
	street.process_mode = was

## Un paso hecho: anota cuánto trabajó en este cuadro, mueve la barra y espera el cuadro siguiente.
func _boot_step(step: String, progress := -1.0, text := "") -> void:
	var ms := (Time.get_ticks_usec() - _boot_us) / 1000.0
	_boot_steps[step] = snappedf(ms, 0.1)
	if _boot_log:
		# t desde el arranque, ms de script de este paso, ms del dibujo anterior (el del paso anterior)
		print("BOOT step %s t=%d script=%.1f prev_draw=%.1f" % [step, Time.get_ticks_msec() - _boot_t0, ms, _draw_ms])
	if _boot_shot != "":
		get_viewport().get_texture().get_image().save_png("%s/%03d_%s.png" % [_boot_shot, _boot_steps.size(), step])
	if boot_screen and progress >= 0.0:
		boot_screen.set_progress(progress * _boot_pscale if progress < 1.0 else progress, text)   # --- BOOT2: escala
	await get_tree().process_frame
	_boot_us = Time.get_ticks_usec()

## Dibuja un escenario de a una familia de shader por cuadro (SetKit.warm_groups): primero vacío (el cielo, el
## brillo, el tonemap), después cada grupo. Con la luz de ahora (llamar a set_night antes). El escenario no procesa
## mientras tanto (nada cambia de visibilidad por su cuenta). bg: con el título en pantalla (pasos de fondo).
## probe: qué cosas escondidas se calientan con una copia (SetKit.warm_groups: "all", "flyers", "streaks").
## Un grupo que proyecta sombra (con el sol con sombras) sale primero un cuadro solo en la pasada de sombra y después
## entero: así los programas de sombra y los de color se compilan en cuadros distintos (la primera vez, la sombra
## usa además la familia del material por defecto: eran 12 programas en un solo cuadro).
func _warm_world(w: SetKit, tag: String, p0: float, p1: float, bg := false, probe := "all") -> void:
	var was := w.process_mode
	w.process_mode = Node.PROCESS_MODE_DISABLED
	var groups := w.warm_groups(probe)
	var sun_shadows := w.sun != null and w.sun.visible and w.sun.shadow_enabled
	if _boot_log:
		for g in groups:
			print("BOOT group %s %s x%d (%s)" % [tag, g[0], g[1].size(), (g[1][0] as Node).name])
	await _warm_frame(bg, "%s_empty" % tag, p0)
	for i in groups.size():
		var nodes: Array = groups[i][1]
		if sun_shadows and String(groups[i][0]).ends_with("|cast"):
			var casts := {}
			for n in nodes:
				if is_instance_valid(n):
					casts[n] = n.cast_shadow
					n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					n.visible = true
			await _warm_frame(bg, "%s_%d_shadow" % [tag, i], -1.0)
			for n in casts:
				if is_instance_valid(n):
					n.cast_shadow = casts[n]
		for n in nodes:
			if is_instance_valid(n):
				n.visible = true
		await _warm_frame(bg, "%s_%d" % [tag, i], p0 + (p1 - p0) * (i + 1) / maxf(1.0, groups.size()))
	w.warm_end()
	w.process_mode = was

func _warm_frame(bg: bool, step: String, progress: float) -> void:
	if bg:
		await _bg_step(step)
	else:
		await _boot_step(step, progress)

## 4. Lo que el título no necesita, con el título ya en pantalla: un paso por cuadro.
func _boot_background() -> void:
	var t_bg := Time.get_ticks_msec()
	_boot_us = Time.get_ticks_usec()
	if boot_screen:   # --- BOOT2
		boot_screen.set_progress(_boot_pscale, "Opening the workshop...")
	# la tienda: se arma y se calienta en su propio mundo 3D (un SubViewport chico que nadie ve)
	_warm_vp = SubViewport.new()
	_warm_vp.name = "WarmShop"
	_warm_vp.size = Vector2i(320, 180)
	_warm_vp.own_world_3d = true
	_warm_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm_vp)
	# (main.shop sigue en null hasta que la tienda pase al mundo principal: nada del juego la toca mientras se calienta)
	var ws := ShopWorld.new()
	_warm_vp.add_child(ws)
	ws.visible = false
	var steps := ws.build_steps()
	_boot_bg_total = steps.size() + 50 + 22   # --- SS2 SEASON: + 4 pasos (2 scripts, el tablero, la gala)
	for i in steps.size():
		steps[i].call()
		await _bg_step("shop_%d" % i)
	ws.activate(true)
	await _warm_world(ws, "shop_day", 0.0, 0.0, true)
	ws.set_night(true)
	await _warm_world(ws, "shop_night", 0.0, 0.0, true)
	ws.set_night(false)
	ws.activate(false)
	# a su sitio: el mundo de la ventana, primero entre los hijos (como antes)
	_warm_vp.remove_child(ws)
	add_child(ws)
	move_child(ws, 0)
	_warm_vp.queue_free()
	_warm_vp = null
	shop = ws
	_wire_world(shop)
	shop.refresh_shelf()        # (si "Continue" ya cargó la partida, el estante es el de la partida)
	day.setup(shop, hud)
	await _bg_step("shop_move")
	# los scripts del banco, el regateo y la cápsula: se compilan de a uno por cuadro, de las piezas al todo (BenchUI
	# con todas sus piezas en un solo cuadro eran ~0,3 s); keep los mantiene cargados hasta crear las ventanas
	var keep: Array = []
	for f in ["bench_kit", "bench_bubble", "bench_gauge", "bench_kettle", "bench_portrait", "bench_scope", "bench_solder",
			"bench_stage", "bench_pod_view", "pod_ui", "haggle_ui", "bench_ui", "res://scripts/ui/rank_screens.gd",
			"res://scripts/world/gala_scene.gd"]:   # --- SS2 SEASON: + el tablero y la gala
		var path: String = f if f.begins_with("res://") else "res://scripts/ui/%s.gd" % f
		if ResourceLoader.exists(path):
			keep.append(load(path))
		await _bg_step("script_" + f.get_file().get_basename())
	_make_bench()
	await _bg_step("bench")
	_make_haggle()
	await _bg_step("haggle")
	_make_pod_ui()
	await _bg_step("pod_ui")
	# --- SS2 SEASON: el tablero y la gala, escondidos (se reusan; nunca new() de noche)
	_make_rank()
	await _bg_step("rank")
	_make_gala()
	await _bg_step("gala")
	# --- end SS2 SEASON
	for n in Sfx.BG_LOOPS:   # --- SS2 MERGE: la lista vive en sfx.gd (R): music_market, amb_port, music_shop
		Sfx.prewarm_one(n)
		await _bg_step("audio_" + n)
	Sfx.prewarm_report()
	boot_ready = true
	_boot_bg_n = _boot_bg_total
	var worst := ""
	var worst_ms := 0.0
	for k in _boot_steps:
		if float(_boot_steps[k]) > worst_ms:
			worst_ms = float(_boot_steps[k])
			worst = k
	print("BOOT done %d ms (background %d ms, %d steps; slowest script step %s %.0f ms)" % [Time.get_ticks_msec() - _boot_t0,
		Time.get_ticks_msec() - t_bg, _boot_steps.size(), worst, worst_ms])
	boot_finished.emit()

## (Pruebas del arranque: --bootjump=night | closing salta ahí cuando terminó lo de fondo, para medir si al llegar
## todavía se compila algo. Un jugador nunca pasa argumentos.)
func _boot_test_jump(where: String) -> void:
	busy = true
	await fade_to(1.0, 0.3)
	busy = false
	Game.new_game_state()
	if where == "night":
		open_shop_now()
		show_night()
	elif where == "closing":
		show_closing()
	else:
		await _season_jump(where)   # --- SS2 SEASON: event_<id>, upgrades, bench_<family>, board, report, gala_win/lose
	fade_to(0.0, 0.5)
	print("BOOT jump %s" % where)

## Un paso de fondo: como _boot_step, pero espera también a que el jugador deje de mover el ratón o de apretar
## botones (como mucho 0,4 s), para que el título responda primero.
func _bg_step(step: String) -> void:
	_boot_bg_n += 1
	if boot_screen:   # --- BOOT2: bajo la pantalla de carga, la segunda mitad de la barra
		boot_screen.set_progress(_boot_pscale + (0.98 - _boot_pscale) * float(_boot_bg_n) / _boot_bg_total)
	await _boot_step("bg_" + step)
	var t0 := Time.get_ticks_msec()
	while boot_screen == null and Time.get_ticks_msec() - _last_input_ms < 150 and Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
	_boot_us = Time.get_ticks_usec()

func _input(ev: InputEvent) -> void:
	if not boot_ready and (ev is InputEventMouseMotion or ev is InputEventMouseButton or ev is InputEventKey or ev is InputEventJoypadButton):
		_last_input_ms = Time.get_ticks_msec()
	# --- SS2 SEASON: cualquier tecla, clic o botón salta el estreno de las mejoras
	if _revealing and ((ev is InputEventKey and ev.pressed) or (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventJoypadButton and ev.pressed)):
		_reveal_skip = true

## 5. Si algo necesita lo de fondo antes de que termine: espera (detrás del fundido) con una barrita.
func _wait_boot() -> void:
	if boot_ready:
		return
	var l := CanvasLayer.new()
	l.layer = 30
	add_child(l)
	var b := BootScreen.new()
	b.mini = true
	l.add_child(b)
	boot_screen = b
	b.set_progress(float(_boot_bg_n) / _boot_bg_total, "Getting the shop ready...")
	await boot_finished
	boot_screen = null
	l.queue_free()

# ------------------------------------------------------------------ título e introducción

func show_title() -> void:
	phase = Phase.TITLE
	close_everything()
	day.clear()
	use_world(street)
	street.set_night(false)
	street.nell.visible = true
	street.kettle.visible = true
	street.walker.teleport(StreetWorld.SHOP_X + 1.0, 1)
	street.kettle.position = Vector3(StreetWorld.SHOP_X + 0.1, 0, StreetWorld.LANE_Z + SetKit.KETTLE_DZ)
	street.refresh_sign()
	street.set_door_open_sign(false)
	street.cam_fixed = true
	street.place_camera(-2.4)
	hud.show_top(false)
	hud.hide_prompt()
	hud.clear_tip()
	hud.set_hint(false)
	screens.show_title(Game.can_continue(), Game.save_note())   # --- SS2 SEASON: la nota del prototipo terminado
	Sfx.music("title")
	Sfx.ambience("wind")

func _on_title_choice(id: String) -> void:
	if phase != Phase.TITLE or busy or dialogs.is_open():
		return
	match id:
		"settings":
			screens.suspend(true)
			dialogs.open({"kind": "menu", "can_quit": false, "title": "Settings", "sub": "Music and sound volume.",
				"resume_text": "Done"}, func(_c): screens.suspend(false))
		"continue":
			if not Game.load_game():
				Game.new_game_state()
			busy = true
			screens.hide_all()
			await fade_to(1.0, 0.35)
			await _wait_boot()   # --- BOOT: la tienda y el banco tienen que estar listos
			busy = false
			if Game.resume == "open":
				open_shop_now()
			else:
				begin_morning()
			_prewarm_today()   # --- SS2 SEASON: el bucle del evento de hoy, bajo el fundido
			fade_to(0.0, 0.5)
		"new":
			Game.new_game_state()
			Game.delete_save()
			busy = true
			screens.hide_all()
			await fade_to(1.0, 0.35)
			busy = false
			show_intro()
			fade_to(0.0, 0.8)

func show_intro() -> void:
	phase = Phase.INTRO
	use_world(street)
	set_post(POST_SKY)
	street.set_night(true)
	street.nell.visible = false
	street.kettle.visible = false
	street.cam_fixed = true
	# el cielo de noche manda: el anillo de restos y la lluvia de chatarra; las casas, abajo
	street.camera.position = Vector3(-1.0, 8.5, 14.0)
	street.camera.look_at(Vector3(-1.0, 10.5, -40.0), Vector3.UP)
	hud.show_top(false)
	hud.set_hint(false)
	screens.show_intro(SeasonData.INTRO)   # --- SS2 SEASON: las 4 líneas de la temporada
	Sfx.music("title")
	Sfx.ambience("wind")

func _on_intro_done() -> void:
	if phase != Phase.INTRO:
		return
	Game.intro_seen = true
	busy = true
	await fade_to(1.0, 0.6)
	await _wait_boot()   # --- BOOT: la introducción no necesita la tienda; la mañana sí (las cápsulas, la puerta)
	busy = false
	begin_morning()
	fade_to(0.0, 0.7)

# ------------------------------------------------------------------ la mañana (el Starfall Market)

func begin_morning() -> void:
	phase = Phase.MORNING
	close_everything()
	day.clear()
	use_world(street)
	street.set_night(false)
	street.nell.visible = true
	street.kettle.visible = true
	street.cam_fixed = false
	street.walker.teleport(StreetWorld.SHOP_X + 0.9, 1)
	street.kettle.position = Vector3(StreetWorld.SHOP_X - 0.2, 0, StreetWorld.LANE_Z + SetKit.KETTLE_DZ)
	street.snap_camera()
	street.refresh_sign()
	street.set_door_open_sign(false)
	# --- SS2 SEASON: la mañana de la temporada: lo nuevo, la pieza gratis, la cápsula de regalo, el decorado del día,
	# el cartel "Day 5 · The Scour" (+ "New today: ..."), la nota de la partida vieja, los momentos de la mañana
	var m := Season.on_morning()
	Game._update_dues_goal()
	var ev := Season.event()
	street.set_event(ev)
	street.set_vendor_open(Season.is_unlocked("vendor"))
	street.set_rival_open(Season.is_unlocked("rival"))
	street.set_upgrade_looks()
	street.set_moons("")
	# el globo de cromo de Glint (§3.5): flota todo el día 8; si Nell iba delante después de la noche 7, la noche 8
	# es la comidilla del Drift (R suma sus +12); si no, revienta y el día 9 cuelga del techo. --- SS2 MERGE: manda
	# el resultado de la noche 8 del tablero (Ranking.balloon_result(): "talk" | "popped"; sin la regla del stub)
	if Game.day == 9 and not Game.flags.has("balloon"):
		var br := Ranking.balloon_result()
		Game.set_flag("balloon", br if br != "" else "popped")
	street.set_balloon("up" if Game.day == 8 else ("popped" if Game.day == 9 and Game.flag("balloon", "") == "popped" else ""))
	street.set_band(Season.band_today())
	set_post(_street_post(ev))
	street.set_pods_left(Game.pods_today.size())
	hud.show_top(true)
	hud.refresh()
	hud.set_clock(Data.OPEN_MIN, "morning")
	var sub := Season.subtitle()
	if not (m.get("new", []) as Array).is_empty():
		sub = "New today: " + " · ".join(m["new"])
	# --- SS2 MERGE: un día sin fin sin evento se llama "Day 11" (el cartel decía "Day 11 · Day 11")
	var ttl := Season.title()
	hud.banner("Day %d" % Game.day if ttl == "Day %d" % Game.day else "Day %d · %s" % [Game.day, ttl], sub, 2.6)
	var ed := Season.event_def()
	Sfx.music("market")
	Sfx.ambience(String(ed.get("amb", "")) if String(ed.get("amb", "")) != "" else "port")
	Game.resume = "morning"
	Game.save_game()
	if not Game.history.is_empty() and int(Game.history.back().get("sign_new", 0)) > 0 and not bool(m.get("repeat", false)):
		street.celebrate_sign()
	if Game.day == 1 and Game.tip_once("walk"):
		get_tree().create_timer(2.6).timeout.connect(func():
			if phase == Phase.MORNING:
				hud.tip(Data.tip("walk", UIKit.interact_key(), "the stick" if PadCursor.pad_in_use else "A/D"), 9.0))
	elif Game.day > 1:
		get_tree().create_timer(2.6).timeout.connect(func():
			if phase == Phase.MORNING:
				street.blurt(street.raker, String(SeasonData.TEXT["raker_storm"]) if int(Season.plan().get("pods", 2)) <= 0 else Data.MARKET_LINES["raker_hello"]))
	_morning_notes(m)
	# --- end SS2 SEASON

## El puesto de Raker: las cápsulas de hoy (peso y traqueteo), elegir una y regatear.
func pods_stall() -> void:
	if int(Season.plan().get("pods", 2)) <= 0 and Game.pods_today.is_empty():   # --- SS2 SEASON: la Scour
		street.blurt(street.raker, String(SeasonData.TEXT["raker_storm"]))
		return
	if Game.pods_today.is_empty():
		street.blurt(street.raker, Data.MARKET_LINES["raker_sold_out"])
		return
	var cheapest := 9999
	for p in Game.pods_today:
		cheapest = mini(cheapest, int(p.get("price", 30)))
	if Game.credits < int(cheapest * 0.7) and cheapest > 0:   # (--- SS2 SEASON: la de regalo cuesta 0)
		street.blurt(street.raker, Data.MARKET_LINES["raker_broke"])
		hud.toast("Not enough credits for a pod.", UIKit.BAD)
		return
	var opts: Array = []
	for i in Game.pods_today.size():
		var p: Dictionary = Game.pods_today[i]
		opts.append({"id": "pod%d" % i, "text": pod_label(p), "primary": i == 0, "min_w": 340})
	opts.append({"id": "later", "text": "Not now"})
	var line := String(Data.MARKET_LINES["raker_pick"] if Game.pods_today.size() > 1 else Data.MARKET_LINES["raker_one"])
	var note := "Prices are a start. Haggle!"
	if Game.tip_once("pods"):
		note = Data.tip("pods")
	dialogs.open({"kind": "talk", "who": "raker", "title": "Raker", "sub": "Dune Raker scavenger", "line": line,
		"note": note, "options": opts, "cancel": "later", "per_row": 1}, _on_pod_choice)

func pod_label(p: Dictionary) -> String:
	var w: String = ["Light", "Heavy", "Very heavy"][clampi(int(p.get("weight", 1)) - 1, 0, 2)]
	var r: String = ["quiet", "rattles a bit", "rattles a lot"][clampi(int(p.get("rattle", 0)), 0, 2)]
	var ask := float(BenchData.HAGGLE.get("duneraker", {}).get("ask", 1.0))
	# --- SS2 SEASON: las cápsulas especiales y la lámpara de cápsulas (Pod Lamp: una cosa de adentro)
	var kind := String(p.get("kind", ""))
	var head: String = {"wreck": "WRECK · ", "bigfall": "BIG FALL · ", "charity": "FREE · "}.get(kind, "")
	var price_txt := "on the house" if kind == "charity" else "asks ~%d cr" % int(round(float(p.get("price", 30)) * ask))
	var txt := "%s%s · %s · %s" % [head, w, r, price_txt]
	if Season.n("pod_peek") > 0:
		txt += "\n" + Season.pod_peek_text(p)
	return txt
	# --- end SS2 SEASON

func _on_pod_choice(id: String) -> void:
	if not id.begins_with("pod"):
		return
	var i := int(id.substr(3))
	if i < 0 or i >= Game.pods_today.size():
		return
	var pod: Dictionary = Game.pods_today[i]
	# --- SS2 SEASON: la cápsula de regalo no se regatea: se abre ya
	if String(pod.get("kind", "")) == "charity" or int(pod.get("price", 30)) <= 0:
		Game.pods_today.remove_at(i)
		Game.stat("pods")
		street.set_pods_left(Game.pods_today.size())
		street.blurt(street.raker, String(SeasonData.TEXT["raker_charity"]))
		pod_ui.open(pod)
		return
	# --- end SS2 SEASON
	pod_pick = {"index": i, "pod": pod}
	var deal := BenchData.make_deal("buy", "Wreck pod" if String(pod.get("kind", "")) == "wreck" else "Salvage pod", "raker", int(pod.get("price", 30)))
	deal["pod"] = pod.duplicate(true)      # (opcional en el contrato: la pantalla puede mostrar la cápsula)
	haggle.open(deal)

func parts_stall() -> void:
	# --- SS2 SEASON: el surtido de hoy (hasta 8, con la rebaja de la Scour) y el cajón de "tal cual" (desde el día 3)
	var asis := Season.asis_for()
	var line := String(SeasonData.TEXT["mags_storm"]) if Season.n("part_price_add") < 0 else String(Data.MARKET_LINES["mags_hello"])
	if Season.event(Game.day + 1) == "festival" and not asis.is_empty():
		line = String(SeasonData.TEXT["mags_eve"])
	dialogs.open({"kind": "parts", "width": 780, "stock": Season.mags_stock(), "asis": asis, "line": line})
	if not asis.is_empty() and Game.tip_once("asis"):
		hud.tip(Data.tip("asis"), 6.0)

# ------------------------------------------------------------------ abrir la tienda

func open_shop() -> void:
	if phase != Phase.MORNING or busy:
		return
	busy = true
	street.set_door_open_sign(true)
	Sfx.play("bell", 0.04, -6.0)
	hud.clear_tip()
	await fade_to(1.0, 0.4)
	busy = false
	open_shop_now()
	fade_to(0.0, 0.5)

func open_shop_now() -> void:
	phase = Phase.OPEN
	close_everything()
	Season.on_morning()   # --- SS2 SEASON: (idempotente) lo que se abre hoy, si la partida se cargó ya abierta
	Game._update_dues_goal()
	Game.resume = "open"
	Game.save_game()
	use_world(shop)
	shop.set_night(false)
	shop.walker.frozen = false
	shop.cam_fixed = false
	shop.set_door_sign(true)
	shop.refresh_shelf()
	shop.set_bench_item("")
	shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
	shop.kettle.position = Vector3(-1.4, 0, ShopWorld.LANE_Z + SetKit.KETTLE_DZ)
	shop.kettle_follow = true
	shop.snap_camera()
	job = {}
	sale = {}
	tea_running = false
	_last_minute = -1
	var tutorial := Game.day == 1 and not Game.tips_seen.has("first_done")
	# --- SS2 SEASON: la tienda de hoy: las mejoras, el decorado del evento, las cosas de las historias; el estreno de
	# las mejoras nuevas (la cámara va a cada una) ANTES de que abra el día
	var ev := Season.event()
	shop.refresh_upgrades()
	shop.set_event(ev if ev in ["sandstorm", "festival", "finale"] else "")
	shop.set_window_sky("")
	shop.set_chalk(0)
	_story_props()
	hud.show_top(true)
	hud.refresh()
	hud.set_clock(Data.OPEN_MIN, "open")
	hud.set_line(0, Data.MAX_LINE)
	if not Game.fittings_new.is_empty():
		await _reveal_new_fittings()
		if phase != Phase.OPEN:
			return
	if Season.band_today() and not Game.flag("band_stars_%d" % Game.day, false):
		Game.set_flag("band_stars_%d" % Game.day, true)
		Game.stat("event_stars", SeasonData.BAND_STARS)
	# --- end SS2 SEASON
	day.open_day(Game.day, tutorial)
	hud.banner("Open!", "We close at 6 PM")
	var music := String(Season.event_def().get("music", ""))
	Sfx.music(music if music != "" else "shop")
	var amb := String(Season.event_def().get("amb", ""))
	Sfx.ambience(amb if amb != "" else "port")
	if not Game.junk.is_empty() and not tutorial and Game.tip_once("junk"):
		get_tree().create_timer(3.2).timeout.connect(func():
			if phase == Phase.OPEN:
				hud.tip(Data.tip("junk"), 7.0))
	_open_notes()   # --- SS2 SEASON

# ------------------------------------------------------------------ el mostrador

func _on_at_counter(_v: Dictionary) -> void:
	if day.hold and Game.tip_once("open"):
		hud.tip(Data.tip("open"), 0.0)
	if shop.walker.current == "counter":
		shop.nell.face(1)

func use_counter() -> void:
	if job.get("kind", "") == "repair":
		match String(job.get("stage", "")):
			"done", "failed":
				handover()
			"accepted":
				go_bench_job()
		return
	var v := day.waiting_at_counter()
	if v.is_empty():
		hud.toast("No one at the counter yet.")
		return
	talk(v)

## El diálogo del mostrador: lo que trae o lo que quiere, y qué hace Nell.
func talk(v: Dictionary) -> void:
	day.begin_talk()
	hud.clear_tip()
	var who := String(v["who"])
	# --- SS2 SEASON: los momentos al llegar al mostrador (Tolle y la caja) y el favor secreto de Glint
	var ex: Dictionary = v.get("extra", {})
	for b in Season.beats(Game.day, "open", {"at_counter": who}):
		busy = true
		await _beat(b)
		busy = false
		if day.counter.is_empty() or int(day.counter.get("id", -1)) != int(v["id"]):
			return
	if String(v.get("kind", "")) == "favour" or bool(ex.get("favour", false)):
		_favour_talk(v)
		return
	# --- end SS2 SEASON
	var sp: Dictionary = Data.SPECIES.get(Data.species_of(who), {})
	var sub := String(sp.get("name", ""))
	if bool(v.get("grumpy", false)):
		sub += " · grumpy from waiting"
	if String(v["kind"]) == "repair":
		var j := BenchData.make_job(String(v["item"]), String(v["fault"]), who)
		if day.hold:
			j["tutorial"] = true               # (opcional: el primer trabajo del día 1, Kettle explica más)
		_job_keys(j, v)   # --- SS2 SEASON: graded, riddle, aids
		# --- SS MERGE: Clatter viene a arreglarse A SÍ MISMO (no trae nada): el banco lo dice (job "self")
		var me := Data.is_self_repair(who)
		if me:
			var sr: Dictionary = Data.SELF_REPAIR[who]
			j["self"] = true
			j["label"] = String(sr.get("label", Data.char_name(who)))
			j["sub"] = String(sr.get("sub", "fixing himself"))
			var sym := Data.self_symptom(who, String(v["fault"]))
			if sym != "":
				j["symptom"] = sym
		# --- end SS MERGE
		var note := ""
		if Game.tip_once("counter"):
			note = Data.tip("counter")
		elif me:
			note = "No gadget this time: Clatter wants himself fixed. He opens his chest panel on the bench."
		# --- SS2 SEASON: lo que hace distinto este trabajo
		elif bool(ex.get("graded", false)):
			note = Data.tip("graded")
		elif bool(ex.get("riddle", false)):
			note = "Old Seven speaks in riddles. The tools still tell the truth."
		elif ex.has("deadline_min"):
			note = "A racer: the thruster must be back by %s." % String(SeasonData.RACE["deadline_text"])
		# --- end SS2 SEASON
		dialogs.open({"kind": "talk", "who": who, "sub": sub, "line": Data.line(who, "bring", String(v["item"])),
			"tag": String(j.get("symptom", "")), "tag_head": "A RIDDLE" if bool(j.get("riddle", false)) else "", "item": "" if me else String(v["item"]), "note": note,
			"options": [{"id": "repair", "text": "Fix him" if me else "Repair it", "primary": true, "min_w": 170},
				{"id": "decline", "text": "Not today", "min_w": 150}], "cancel": "later"},
			func(c): _on_talk_choice(v, c, j))
	else:
		var opts: Array = []
		var wants: Array = v.get("wants", [])
		var seen := {}
		for i in Game.shelf.size():
			var e: Dictionary = Game.shelf[i]
			var item := String(e.get("item", ""))
			var key := "%s%d" % [item, int(e.get("stars", 0))]
			if item in wants and not seen.has(key) and opts.size() < 3:
				seen[key] = true
				opts.append({"id": "sell%d" % i, "text": "Sell %s %s" % [BenchData.item_name(item), stars_text(int(e.get("stars", 0)))],
					"primary": opts.is_empty(), "min_w": 250})
		var note := ""
		if opts.is_empty():
			var names := []
			for w in wants:
				names.append(BenchData.item_name(String(w)))
			note = "Nothing on your shelf they want (%s)." % " or ".join(names)
		elif Game.tip_once("shelf"):
			note = Data.tip("shelf")
		opts.append({"id": "none", "text": "Sorry, none" if not opts.is_empty() else "Sorry, none today", "primary": opts.is_empty(), "min_w": 170})
		dialogs.open({"kind": "talk", "who": who, "sub": sub, "line": Data.line(who, "buy"), "note": note,
			"options": opts, "cancel": "later", "per_row": 2}, func(c): _on_talk_choice(v, c, {}))

static func stars_text(n: int) -> String:
	var s := ""
	for i in 3:
		s += "★" if i < n else "☆"
	return s

func _on_talk_choice(v: Dictionary, c: String, j: Dictionary) -> void:
	if day.counter.is_empty() or int(day.counter.get("id", -1)) != int(v["id"]):
		return   # se fue mientras tanto (las 6 PM)
	match c:
		"repair":
			day.start_work()
			job = {"kind": "repair", "v": v, "item": String(v["item"]), "fault": String(v["fault"]), "stage": "accepted",
				"job": j, "result": {}}
			shop.set_counter_item("")
			go_bench_job()
		"decline", "none":
			Game.stat("declined")
			day.leave(v, "declined", Data.line(String(v["who"]), "decline" if c == "decline" else "none"))
			_end_tutorial()
		"later", "":
			day.end_talk()
		_:
			if c.begins_with("sell"):
				var i := int(c.substr(4))
				if i < 0 or i >= Game.shelf.size():
					day.end_talk()
					return
				var e: Dictionary = Game.shelf[i]
				var base := int(round(BenchData.sale_price(String(e["item"]), int(e["stars"])) * Season.k("sale_k")))   # --- SS2 SEASON
				day.start_work()
				sale = {"v": v, "index": i, "item": String(e["item"]), "stars": int(e["stars"]), "base": base}
				var deal := BenchData.make_deal("sell", BenchData.item_name(String(e["item"])), String(v["who"]), base)
				deal["item"] = String(e["item"])    # (opcionales: el dibujo de la cosa y sus estrellas)
				deal["stars"] = int(e["stars"])
				haggle.open(deal)

# ------------------------------------------------------------------ el banco

## Lleva el trabajo aceptado al banco (Nell camina sola; si el jugador la mueve, el trabajo espera en el mostrador).
func go_bench_job() -> void:
	if job.is_empty() or String(job.get("stage", "")) != "accepted":
		return
	shop.set_bench_item("" if bool(job.get("job", {}).get("self", false)) else String(job["item"]))   # (--- SS MERGE: Clatter)
	if shop.walker.current != "bench":
		busy = true
		var ok: bool = await shop.walker.go_station("bench")
		busy = false
		if not ok or phase != Phase.OPEN:
			return
	if job.is_empty() or String(job.get("stage", "")) != "accepted":
		return
	job["stage"] = "bench"
	shop.nell.face(-1)
	if bool(job["job"].get("graded", false)) and Game.tip_once("graded"):
		hud.tip(Data.tip("graded"), 5.0)   # --- SS2 SEASON
	bench.open(job["job"])

func use_bench() -> void:
	if not job.is_empty():
		if String(job.get("kind", "")) == "repair" and String(job.get("stage", "")) == "accepted":
			go_bench_job()
		elif String(job.get("stage", "")) in ["done", "failed"]:
			hud.toast("Take it back to the counter.")
		return
	if Game.junk.is_empty():
		hud.toast("Nothing to fix. Take a job at the counter.")
		return
	if Game.junk.size() == 1:
		refurb(0)
		return
	var opts: Array = []
	for i in mini(Game.junk.size(), 4):
		var jk: Dictionary = Game.junk[i]
		opts.append({"id": "j%d" % i, "text": BenchData.item_name(String(jk["item"])), "primary": i == 0, "min_w": 220})
	opts.append({"id": "later", "text": "Later"})
	dialogs.open({"kind": "talk", "who": "nell", "title": "Refurbish", "sub": "Broken finds from the pods",
		"line": "Which one goes on the bench?", "options": opts, "cancel": "later", "per_row": 2}, func(c):
			if String(c).begins_with("j"):
				refurb(int(String(c).substr(1))))

## Reacondicionar una cosa rota de las cápsulas: al banco; si sale bien, al estante.
func refurb(i: int) -> void:
	var jk := Game.take_junk(i)
	if jk.is_empty():
		return
	job = {"kind": "refurb", "item": String(jk["item"]), "fault": String(jk["fault"]), "stage": "bench", "result": {}}
	shop.set_bench_item(String(jk["item"]))
	shop.nell.face(-1)
	var rj := BenchData.make_job(String(jk["item"]), String(jk["fault"]), "")
	rj["aids"] = Season.bench_aids()   # --- SS2 SEASON: las mejoras del banco también para reacondicionar
	bench.open(rj)

func _on_bench_finished(r: Dictionary) -> void:
	check_keys("bench", r, ["ok", "stars", "time", "fault_found", "patched", "parts_used"])
	shop.set_bench_item("")
	if job.is_empty():
		return
	var ok := bool(r.get("ok", false))
	var stars := clampi(int(r.get("stars", 0)), 0, 3)
	if bool(r.get("patched", false)):
		Game.stat("patched")   # --- SS2 SEASON
	if String(job["kind"]) == "refurb":
		if ok:
			Game.shelf_add(String(job["item"]), stars)
			Game.stat("refurbished")
			if after_hours:
				Game.stat("after_hours")   # --- SS2 SEASON
			hud.toast("%s %s is on the shelf." % [BenchData.item_name(String(job["item"])), stars_text(stars)], UIKit.GOOD)
			shop.kettle.emote("star", 1.2)
		else:
			Game.add_junk(String(job["item"]), String(job["fault"]))
			hud.toast("Not this time. It goes back on the junk pile.")
		job = {}
		return
	if String(job["kind"]) == "favour":
		_favour_done(r)   # --- SS2 SEASON
		return
	job["result"] = r
	job["stage"] = "done" if ok else "failed"
	if ok:
		shop.kettle.emote("steam", 1.0)
	# vuelve sola al mostrador a entregarlo
	if phase == Phase.OPEN:
		busy = true
		var back: bool = await shop.walker.go_station("counter")
		busy = false
		if back and not job.is_empty() and String(job.get("stage", "")) in ["done", "failed"]:
			handover()

## Entrega la cosa reparada: paga según estrellas y rapidez (+ las reglas de cada especie) y se va.
func handover() -> void:
	if job.is_empty():
		return
	var v: Dictionary = job["v"]
	var r: Dictionary = job.get("result", {})
	var who := String(v["who"])
	var item := String(job["item"])
	shop.nell.face(1)
	if String(job["stage"]) == "done":
		var stars := clampi(int(r.get("stars", 0)), 0, 3)
		# lo que tardó desde que aceptó el trabajo (el reloj del día; con el bot acelerado, el tiempo del banco)
		# (--- SS MERGE: también con el bot acelerado: el reloj del día es tiempo de juego, como el del banco; así el
		# bot mide igual que una persona, caminatas incluidas)
		var secs := maxf(1.0, day.shop_t - float(v.get("t_job", day.shop_t)))
		var pay := repair_pay(item, stars, secs)
		# --- SS2 SEASON: lo que paga de más la reputación y el Neon Star, las mañas de los clientes nuevos, los
		# corredores, la nota de Tolle
		var tw := Season.on_handover(v, stars, secs, day.minutes())
		pay = maxi(1, int(round(pay * Season.k("repair_k") * float(tw.get("pay_k", 1.0)))))
		# --- end SS2 SEASON
		Game.stat("job_secs", int(round(secs)))   # --- SS MERGE: para el balance (segundos de cada trabajo, sumados)
		var tip := 0
		match who:
			"pipip":
				pay = int(round(pay * 0.85))      # monedas chicas
			"zib":
				if secs <= Data.SPEED_TIP_SECS and stars >= 2 and not bool(v.get("grumpy", false)):
					tip = Data.SPEED_TIP          # propina por rapidez
			"gorrum":
				if stars >= 3:
					tip = 2                       # le gusta el trabajo bien hecho
		Game.add_credits(pay + tip)
		Game.stat("repairs")
		Game.stat("stars", stars)
		Game.stat("repair_pay", pay)
		Game.stat("served")              # --- SS2 SEASON (§8.4)
		Game.stat("repair_stars", stars)
		shop.set_chalk(int(Game.today.get("repairs", 0)))
		if tip > 0:
			Game.stat("tips", tip)
		Game.add_rep(int(Data.REP_STARS[stars]))
		var a: Actor = v["actor"]
		if is_instance_valid(a):
			hud.fly_coins(shop.camera.unproject_position(a.global_position + Vector3(0, 1.3, 0)), clampi((pay + tip) / 6, 3, 8))
			a.emote("heart" if stars >= 2 else "dots", 1.2)
		Sfx.play("coins", 0.05, -2.0)
		var msg := "+%d cr" % pay + ((" (+%d tip)" % tip) if tip > 0 else "")
		var what := Data.char_name(who) if Data.is_self_repair(who) else BenchData.item_name(item)   # (--- SS MERGE)
		hud.toast("%s · %s %s" % [msg, what, stars_text(stars)], UIKit.GOOD)
		var say := String(tw.get("say", "")) if String(tw.get("say", "")) != "" else Data.line(who, "thanks", stars)
		# --- SS2 MERGE: la charla del tablero (Ranking.RANK_CHATTER, P1 de R): 1 de cada 4 entregas contentas, cuando
		# Nell ya está entre las 20 del Lantern Board, el cliente comenta el puesto en vez de dar las gracias
		if String(tw.get("say", "")) == "" and stars >= 2 and not who in ["hermit", "inspector", "rival"]:
			var cseed := absi(hash("%d-%s-%d" % [Game.day, who, int(Game.today.get("repairs", 0))]))
			if cseed % 4 == 0:
				var ch := Ranking.chatter(cseed / 4)
				if ch != "":
					say = ch
		# --- end SS2 MERGE
		day.leave(v, "done", say, Color(0.85, 1.0, 0.8))
		_after_handover(v, stars, true, tw)   # --- SS2 SEASON
	else:
		Game.stat("failed")
		Game.add_rep(Data.REP_GAVE_UP)
		hud.toast("No luck with that one. %s takes it back." % Data.char_name(who), UIKit.BAD)
		day.leave(v, "done", Data.line(who, "failed"))
		_after_handover(v, 0, false, {})   # --- SS2 SEASON
	job = {}
	_end_tutorial()

## El primer cliente del día 1 ya se fue (atendido o no): el reloj arranca.
func _end_tutorial() -> void:
	if day.hold:
		day.hold = false
		Game.tips_seen["first_done"] = true
		hud.tip(Data.tip("clock"), 6.0)

func repair_pay(item: String, stars: int, secs: float) -> int:
	return int(BenchData.repair_pay(item, stars, secs))

# ------------------------------------------------------------------ el regateo y las cápsulas

func _on_haggle_finished(r: Dictionary) -> void:
	check_keys("haggle", r, ["deal", "price", "mood"])
	var deal := bool(r.get("deal", false))
	var price := maxi(0, int(r.get("price", 0)))
	if not sale.is_empty():
		# una venta del estante
		var v: Dictionary = sale["v"]
		var who := String(v["who"])
		if deal:
			var idx := _find_shelf(String(sale["item"]), int(sale["stars"]), int(sale["index"]))
			if idx >= 0:
				Game.shelf_take(idx)
			Game.add_credits(price)
			Game.stat("sales")
			Game.stat("sale_pay", price)
			Game.stat("served")                           # --- SS2 SEASON (§8.4)
			Game.stat("sale_stars", int(sale["stars"]))
			Game.add_rep(Data.REP_SALE)
			var extra := ""
			var barter := String(r.get("barter", ""))
			if barter != "" and BenchData.PARTS.has(barter):
				# --- SS MERGE: el trueque de Mother Oona trae barter_n piezas (contrato de HaggleUI), no siempre una
				var bn := maxi(1, int(r.get("barter_n", 1)))
				Game.add_part(barter, bn)
				extra = (" + a %s" % BenchData.part_name(barter).to_lower()) if bn == 1 else (" + %d %ss" % [bn, BenchData.part_name(barter).to_lower()])
				extra = extra.replace("lenss", "lenses")   # --- SS2 SHIP: el plural de "lens" ("Traded: ... for 3 lenses")
			Sfx.play("coins", 0.05, -2.0)
			var a: Actor = v["actor"]
			if is_instance_valid(a):
				hud.fly_coins(shop.camera.unproject_position(a.global_position + Vector3(0, 1.3, 0)), 5)
			if price <= 0 and extra != "":
				hud.toast("Traded: %s for%s" % [BenchData.item_name(String(sale["item"])), extra.substr(2)], UIKit.GOOD)
			else:
				hud.toast("Sold: %s for %d cr%s" % [BenchData.item_name(String(sale["item"])), price, extra], UIKit.GOOD)
			day.leave(v, "done", Data.line(who, "sold"), Color(0.85, 1.0, 0.8))
		else:
			day.leave(v, "done", Data.line(who, "nodeal"))
		sale = {}
		return
	if not pod_pick.is_empty():
		# una cápsula de Raker
		var pick := pod_pick
		pod_pick = {}
		if not deal:
			street.blurt(street.raker, Data.MARKET_LINES["raker_nodeal"])
			return
		if not Game.spend_credits(price):
			street.blurt(street.raker, Data.MARKET_LINES["raker_broke"])
			hud.toast("Not enough credits for that price.", UIKit.BAD)
			return
		var idx2 := int(pick["index"])
		if idx2 >= 0 and idx2 < Game.pods_today.size():
			Game.pods_today.remove_at(idx2)
		Game.stat("pods")
		street.set_pods_left(Game.pods_today.size())
		street.blurt(street.raker, Data.MARKET_LINES["raker_after"])
		pod_ui.open(pick["pod"])

func _find_shelf(item: String, stars: int, hint: int) -> int:
	if hint >= 0 and hint < Game.shelf.size() and Game.shelf[hint].get("item", "") == item and int(Game.shelf[hint].get("stars", -1)) == stars:
		return hint
	for i in Game.shelf.size():
		if Game.shelf[i].get("item", "") == item and int(Game.shelf[i].get("stars", -1)) == stars:
			return i
	return Game.shelf_find(item)

func _on_pod_finished(contents: Array) -> void:
	var got := []
	var broken := false
	var core := false
	for c in contents:
		if not (c is Dictionary):
			contract_error("pod: contenido que no es un diccionario: %s" % str(c))
			continue
		if c.has("part"):
			Game.add_part(String(c["part"]))
		elif c.has("item"):
			Game.add_junk(String(c["item"]), String(c.get("fault", "")))
			broken = true
		elif c.has("core"):
			# --- SS2 SEASON: el núcleo de lámpara del naufragio (no es una pieza: es de la historia de Old Seven)
			Season.add_core("wreck")
			core = true
			got.append("Lamp core")
			continue
		got.append(BenchData.content_name(c))
	if core:
		hud.toast(SeasonData.CORE_TOAST, UIKit.GOOD, 3.5)
	if got.is_empty():
		hud.toast("The pod was empty. Rakers!")
		return
	hud.toast("From the pod: " + ", ".join(got), UIKit.TEXT, 4.0)
	if broken and phase == Phase.MORNING and not Game.tips_seen.has("junk"):
		Game.tips_seen["junk"] = true
		hud.tip(Data.tip("junk"), 6.0)

# ------------------------------------------------------------------ el té de Kettle, el cajón, el estante

func use_tea() -> void:
	var someone := day.line_count() > 0 or not day.counter.is_empty()
	var out := not tea_left()   # --- SS2 SEASON: el Samovar (y el último día) dan un té más
	if out or not someone or tea_running:
		shop.kettle.hop(1)
		Sfx.play("whistle", 0.08, -10.0)
		hud.toast(Data.KETTLE_TEA_DONE if out else String(Data.KETTLE_TALK[randi() % Data.KETTLE_TALK.size()]))
		return
	Game.today["tea"] = true
	Game.stat("tea_used")
	tea_running = true
	Sfx.play("tea", 0.02, -4.0)
	hud.toast(Data.KETTLE_TEA, UIKit.GOOD)
	var boost := Data.TEA_BOOST + Season.nf("tea_boost_add")
	await shop.tea_walk(func(i): day.tea_boost(i, boost))
	tea_running = false

## --- SS2 SEASON: ¿queda té hoy? (1 + Season.n("tea_uses") por día)
func tea_left() -> bool:
	return int(Game.today.get("tea_used", 0)) < 1 + Season.n("tea_uses")

func show_drawer() -> void:
	var rows: Array = []
	for p in BenchData.PART_ORDER:
		var n := Game.part_count(String(p))
		if n > 0:
			rows.append({"icon": "res://assets/parts/%s.png" % p, "text": BenchData.part_name(String(p)), "sub": "x%d" % n})
	for jk in Game.junk:
		rows.append({"icon": "res://assets/items/%s_closed.png" % jk["item"], "scale": 0.6, "text": BenchData.item_name(String(jk["item"])),
			"sub": "broken: refurbish at the bench", "warm": true})
	dialogs.open({"kind": "info", "title": "Parts drawer", "sub": "A real part beats a patch. Mags sells parts in the morning.",
		"rows": rows, "empty": "Empty! Buy parts from Mags in the morning.", "columns": 3, "width": 720})

func show_shelf() -> void:
	var rows: Array = []
	for e in Game.shelf:
		var item := String(e.get("item", ""))
		rows.append({"icon": "res://assets/items/%s_closed.png" % item, "scale": 0.6, "text": BenchData.item_name(item),
			"sub": "%s · about %d cr" % [stars_text(int(e.get("stars", 0))), BenchData.sale_price(item, int(e.get("stars", 0)))]})
	dialogs.open({"kind": "info", "title": "Shelf: fixed and for sale", "sub": "Buyers at the counter pick from here. More stars, better price.",
		"rows": rows, "empty": "Empty. Refurbish broken pod finds at the bench.", "columns": 2, "width": 640})

# ------------------------------------------------------------------ el cierre y la noche

func _on_closing() -> void:
	hud.banner("6 PM", "Closing time")
	hud.set_clock(Data.CLOSE_MIN, "closing")
	Sfx.play("bell", 0.02, -6.0)

func _on_left(_v: Dictionary, why: String) -> void:
	if why == "angry" and Game.tip_once("line"):
		hud.tip(Data.tip("line"), 6.0)

func _on_day_over() -> void:
	if phase != Phase.OPEN:
		return
	# (quien espera su cosa no se va: el día no termina con un trabajo a medias.) Si Nell todavía está en el banco
	# reacondicionando algo, o con una ventana abierta, el día espera a que termine.
	while bench.is_open() or haggle.is_open() or pod_ui.is_open() or dialogs.is_open() or busy:
		await get_tree().create_timer(0.25).timeout
		if phase != Phase.OPEN:
			return
	job = {}
	sale = {}
	busy = true
	await get_tree().create_timer(1.0).timeout
	await fade_to(1.0, 0.6)
	busy = false
	show_night()
	fade_to(0.0, 0.8)

func show_night() -> void:
	phase = Phase.NIGHT
	close_everything()
	use_world(shop)
	shop.set_night(true)
	shop.set_door_sign(false)
	shop.door_reset()
	# Nell y Kettle miran por la ventana la lluvia de chatarra (las cápsulas de mañana); el libro, a la derecha
	shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], -1)
	shop.walker.frozen = true      # (si no, el carril la vuelve a poner en su sitio)
	shop.kettle_follow = false
	shop.nell.position = ShopWorld.NIGHT_NELL
	shop.nell.face(1)
	shop.kettle.position = ShopWorld.NIGHT_KETTLE
	shop.kettle.face(1)
	shop.kettle.set_walking(false)
	shop.cam_fixed = true
	shop.night_camera()
	hud.show_top(false)
	hud.set_clock(Data.CLOSE_MIN, "night")
	hud.set_hint(false)
	hud.clear_tip()
	# --- SS2 SEASON: la ventana de noche (las dos lunas; la gran estela la noche antes de Bigfall, Bronzemoon...), la
	# música de noche; DESPUÉS DE CERRAR el banco para el estante (sin reloj); recién entonces se cierra el día (el
	# tablero cuenta lo de la noche) y el libro de cuentas (sin la fila del tablero en la noche final: sin spoiler)
	shop.set_window_sky(_window_sky())
	Sfx.music("night")
	Sfx.ambience("wind")
	if not Game.junk.is_empty():
		await _after_hours()
		if phase != Phase.NIGHT:
			return
	var s := Game.close_day()
	street.refresh_sign()
	var ln := Ranking.ledger_line(s.get("rank", {}))
	if Ranking.ending_due():
		ln = String(SeasonData.TEXT["signal_counting"])
	s["board_line"] = ln
	s["preview"] = Season.night_preview(Game.day)
	if Game.day == 7:
		s["kettle"] = SeasonData.KETTLE_BEFORE_FESTIVAL
	if Game.day == 1:
		s["dues_note"] = String(SeasonData.TEXT["dues_note_d1"])
	screens.show_ledger(s, false)
	_prewarm_tomorrow()
	# --- end SS2 SEASON

func _on_ledger_done() -> void:
	if phase != Phase.NIGHT:
		return
	await _night_chain()   # --- SS2 SEASON: la cuota, el tablero, el Report, los momentos de la noche, la gala

func show_closing() -> void:
	phase = Phase.END
	close_everything()
	use_world(street)
	street.set_night(true)
	street.nell.visible = true
	street.kettle.visible = true
	street.walker.teleport(StreetWorld.SHOP_X + 0.9, -1)
	street.kettle.position = Vector3(StreetWorld.SHOP_X + 1.8, 0, StreetWorld.LANE_Z + SetKit.KETTLE_DZ)
	street.refresh_sign()
	street.set_door_open_sign(false)
	street.cam_fixed = true
	street.place_camera(-3.6)
	hud.show_top(false)
	hud.set_hint(false)
	Game.resume = "done"
	Game.save_game()
	screens.show_closing(Game.totals())
	Sfx.music("title")
	Sfx.ambience("wind")
	if Game.dues_met():
		Sfx.play("good", 0.0, -2.0)

func _on_closing_choice(id: String) -> void:
	if phase != Phase.END:
		return
	busy = true
	await fade_to(1.0, 0.4)
	busy = false
	if id == "again":
		Game.new_game_state()
		Game.intro_seen = true
		begin_morning()
	else:
		show_title()
	fade_to(0.0, 0.5)

# ------------------------------------------------------------------ el menú de pausa

func open_menu() -> void:
	if phase not in [Phase.MORNING, Phase.OPEN] or menu_open or dialogs.is_open() or bench.is_open() or haggle.is_open() or pod_ui.is_open():
		return
	menu_open = true
	day.paused = true
	hud.hide_prompt()
	# por la mañana no corre ningún reloj: otra línea (la del reloj solo con la tienda abierta)
	var sub := "The clock stops while this is open." if phase == Phase.OPEN else "The market waits for you. Take your time."
	dialogs.open({"kind": "menu", "sub": sub, "calendar": true}, func(c):
		menu_open = false
		day.paused = false
		if c == "title":
			to_title()
		elif c == "calendar":
			open_calendar())   # --- SS2 SEASON

func to_title() -> void:
	busy = true
	await fade_to(1.0, 0.35)
	busy = false
	show_title()
	fade_to(0.0, 0.5)

## Cierra todo lo abierto (al cambiar de fase).
func close_everything() -> void:
	for m in [bench, haggle, pod_ui]:
		if m and m.is_open():   # (--- BOOT: en el título pueden no existir todavía)
			m.close_now()
	if dialogs.is_open():
		dialogs.close_now()
	if rank and rank.is_open():   # --- SS2 SEASON
		rank.close_now()
	menu_open = false
	day.paused = false
	screens.hide_all()
	hud.hide_prompt()
	hud.hide_banner()
	hud.clear_chips()
	job = {}
	sale = {}
	pod_pick = {}
	for w in [shop, street]:
		if w:
			w.walker.stop()

# ------------------------------------------------------------------ estaciones, el aviso "[E] ..." y la entrada

func modal_open() -> bool:
	return _work_ui_open() or dialogs.is_open() or screens.is_open() or menu_open or (rank != null and rank.is_open()) \
		or (gala != null and gala.is_open())   # --- SS2 SEASON

## --- BOOT: el banco, el regateo o la cápsula abiertos (en el título pueden no existir todavía).
func _work_ui_open() -> bool:
	return (bench != null and bench.is_open()) or (haggle != null and haggle.is_open()) or (pod_ui != null and pod_ui.is_open())

func can_walk() -> bool:
	return (phase == Phase.MORNING or phase == Phase.OPEN) and not modal_open() and not busy and fade.color.a < 0.6

## La capa cuyos botones toca el mando ahora (PadCursor.buttons_root).
func _pad_root() -> Control:
	if dialogs.is_open():
		return dialogs
	if rank != null and rank.is_open():   # --- SS2 SEASON
		return rank
	# --- SS2 RANK: la noche del cometa (sus botones: Continue, Keep trading, Title; LB / RB saltan entre ellos)
	if gala != null and gala.is_open() and gala.has_method("pad_root"):
		return gala.pad_root()
	# --- end SS2 RANK
	if screens.is_open():
		return screens
	if _work_ui_open():
		return modal_root
	return hud

func _on_station_clicked(id: String) -> void:
	if not can_walk() or world == null:
		return
	if await world.walker.go_station(id):
		var vb := station_verb(id)
		if bool(vb[1]):
			use_station(id)

func use_station(id: String) -> void:
	if not can_walk():
		return
	if phase == Phase.MORNING:
		match id:
			"door":
				open_shop()
			"pods":
				pods_stall()
			"parts":
				parts_stall()
			"fittings":   # --- SS2 SEASON
				fittings_stall()
			"rival":
				visit_rival()
			"board":
				open_calendar()
	elif phase == Phase.OPEN:
		match id:
			"counter":
				if _can_close_early():   # --- SS2 SEASON
					ask_close_early()
				else:
					use_counter()
			"bench":
				use_bench()
			"drawer":
				show_drawer()
			"shelf":
				show_shelf()
			"tea":
				use_tea()

## El verbo del aviso de una estación ahora ("" = sin aviso) y si se puede usar (false = aviso apagado, sin tecla).
func station_verb(id: String) -> Array:
	if phase == Phase.MORNING:
		match id:
			"door":
				return ["Open shop", true]
			"pods":
				if int(Season.plan().get("pods", 2)) <= 0 and Game.pods_today.is_empty():
					return ["Closed: Scour", false]   # --- SS2 SEASON
				return ["Buy pods", true] if not Game.pods_today.is_empty() else ["Sold out", false]
			"parts":
				return ["Buy parts", true]
			# --- SS2 SEASON: el patio de Dolly, la vecina, el tablón de anuncios
			"fittings":
				return ["Fittings", true] if Season.is_unlocked("vendor") else ["Opens tomorrow", false]
			"rival":
				return ["Visit", true] if Season.is_unlocked("rival") else ["Coming soon", false]
			"board":
				return ["Read", true]
			# --- end SS2 SEASON
	elif phase == Phase.OPEN:
		match id:
			"counter":
				if job.get("kind", "") == "repair":
					match String(job.get("stage", "")):
						"done", "failed":
							return ["Hand over", true]
						"accepted":
							return ["Repair", true]
					return ["Working...", false]
				var v := day.waiting_at_counter()
				if not v.is_empty():
					if String(v["kind"]) == "favour":
						return ["Talk", true]   # --- SS2 SEASON: el favor de Glint
					return ["Repair" if String(v["kind"]) == "repair" else "Sell", true]
				if _can_close_early():
					return ["Close up early", true]   # --- SS2 SEASON
				if not sale.is_empty():
					return ["Haggling...", false]
				# --- SS SHIP: quien se acaba de ir sigue en el mostrador despidiéndose ("Lovely work, little star."): sin
				# el cartel "No one at the counter" encima de su frase
				if Time.get_ticks_msec() - day.counter_left_ms < 2800:
					return ["", false]
				return ["No one at the counter", false]
			"bench":
				if job.get("kind", "") == "repair" and String(job.get("stage", "")) == "accepted":
					return ["Repair", true]
				if not job.is_empty():
					return ["Busy", false]
				if not Game.junk.is_empty():
					return ["Refurbish", true]
				return ["Nothing to fix", false]
			"drawer":
				return ["Check parts", true]
			"shelf":
				return ["Check shelf", true]
			"tea":
				var someone := day.line_count() > 0 or not day.counter.is_empty()
				if tea_left() and someone and not tea_running:   # --- SS2 SEASON
					return ["Tea", true]
				return ["Talk", true]
	return ["", false]

## El aviso sobre la estación donde está Nell: "[E] Repair" (o "[A] Repair" con el mando). Sigue al punto.
func _update_prompt() -> void:
	if world == null or not can_walk():
		hud.hide_prompt()
		return
	var id := world.walker.current
	if id == "":
		hud.hide_prompt()
		return
	var vb := station_verb(id)
	var p := world.prompt_point(id)
	if world.camera.is_position_behind(p):
		hud.hide_prompt()
		return
	hud.show_prompt(world.camera.unproject_position(p), String(vb[0]), bool(vb[1]), world.walker.is_walking())

func _unhandled_input(ev: InputEvent) -> void:
	if phase != Phase.MORNING and phase != Phase.OPEN:
		return
	if modal_open() or busy:
		return
	# --- SS2 SEASON: R (o Y del mando) = el tablero entero (nunca sobre el banco, el regateo, la cápsula o un diálogo)
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_R:
		open_rank_board()
		get_viewport().set_input_as_handled()
		return
	# --- end SS2 SEASON
	if ev.is_action_pressed("interact") and not ev.is_echo():
		if world.walker.current != "":
			var vb := station_verb(world.walker.current)
			if bool(vb[1]):
				use_station(world.walker.current)
			get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("back") and not ev.is_echo():
		open_menu()
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		# un clic en el suelo: caminar hasta ahí (un clic en una estación lo maneja station_clicked)
		var x := world.floor_x_at(get_viewport().get_mouse_position())
		if not is_nan(x):
			world.walker.go_to(x)

func _process(_d: float) -> void:
	frame += 1
	# --- SS2 SHIP: de vuelta a caminar (se cerró una ventana o Nell camina con el stick), el cursor del mando se esconde
	# y A vuelve a ser "interactuar". Antes, después de usar LB / RB (el tablero, una pieza de Mags) el cursor quedaba a
	# la vista y A hacía clic donde había quedado: el aviso decía "[A] Buy pods" y A no abría nada.
	var walk_now := can_walk()
	if PadCursor.active and walk_now and world != null and (not _ship_walk_was or world.walker._input_dir() != 0.0):
		pad.hide_cursor()
	_ship_walk_was = walk_now
	# --- end SS2 SHIP
	_update_prompt()
	if modal_open():
		hud.hide_banner()
	hud.set_covered(_work_ui_open())   # --- SS MERGE (--- BOOT: _work_ui_open)
	if phase == Phase.OPEN and day.running:
		var m := day.minutes()
		if m / 5 != _last_minute:
			_last_minute = m / 5
			hud.set_clock(m, "closing" if day.closing else "open")
		hud.set_line(day.line_count(), Data.MAX_LINE)
		if day.line_count() >= 3 and tea_left() and not day.hold and Game.tip_once("tea"):
			hud.tip(Data.tip("tea", UIKit.interact_key()), 7.0)
		_season_tick(m)   # --- SS2 SEASON: la carrera (las 2 PM, las 3 PM), cerrar antes
	hud.set_hint(can_walk(), "Sound: click or press a key" if pad.needs_gesture else "")
	if shot_path != "" and frame == maxi(shot_frames, 20):
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("SHOT ", shot_path)
		if demo != "autoplay":
			quit_clean(0)

## Salir de una prueba o una captura sin sonidos a medio arrancar (si no, Godot avisa al cerrar de flujos de audio
## "still in use"): calla la música y el ambiente, espera a que el hilo de audio los suelte y sale.
func quit_clean(code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	Sfx.process_mode = Node.PROCESS_MODE_DISABLED
	for p in Sfx.find_children("", "AudioStreamPlayer", true, false):
		p.stop()
		p.stream = null
	await get_tree().create_timer(0.3, true, false, true).timeout
	get_tree().quit(code)

# ------------------------------------------------------------------ errores del contrato y argumentos

func check_keys(what: String, r: Dictionary, keys: Array) -> void:
	for k in keys:
		if not r.has(k):
			contract_error("%s: al resultado le falta '%s' (%s)" % [what, k, str(r)])

func contract_error(msg: String) -> void:
	errors += 1
	push_warning("CONTRATO: " + msg)
	print("CONTRACT ERROR ", msg)

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			shot_frames = int(a.substr(9))
		elif a.begins_with("--demo="):
			demo = a.substr(7)
		elif a.begins_with("--days="):
			autoplay_days = maxi(1, int(a.substr(7)))
		elif a == "--bootlog":
			_boot_log = true   # --- BOOT
		elif a.begins_with("--bootshot="):
			_boot_shot = a.substr(11)
		elif a.begins_with("--bootjump="):
			_boot_jump = a.substr(11)
		elif a == "--pad=1" and demo != "":
			PadCursor.pad_in_use = true   # --- SS2 MERGE: capturas de cualquier demo con los avisos del mando

# ==================================================================================================================
# --- SS2 SEASON: la temporada en el flujo (SS2_DESIGN §8.11): la mañana, el estreno de las mejoras, los días
# especiales, los momentos de historia, después de cerrar, la cadena de la noche (la cuota, el tablero, el Report, la
# gala), el tablero con R / Y, Dolly, la vecina, el calendario, cerrar antes. Todo lo de la temporada lo decide Season.
# ==================================================================================================================

## El post-proceso de la calle con el del evento de hoy (StreetWorld.EVENT_POST de WORLD).
func _street_post(ev: String) -> Dictionary:
	var p := POST_STREET.duplicate()
	var ep: Dictionary = StreetWorld.EVENT_POST.get(ev, {}) if ev != "" else {}
	p.merge(ep, true)
	return p

## Los avisos de la mañana (uno por vez) y después los momentos de historia de la mañana, uno por uno.
func _morning_notes(m: Dictionary) -> void:
	var notes: Array = []
	if Game.migrated_from > 0 and Game.tip_once("migrated"):
		notes.append([String(SeasonData.TIPS["migrated"]), UIKit.ACCENT])
	if String(m.get("kettle", "")) != "" and not bool(m.get("repeat", false)):
		notes.append([String(m["kettle"]), UIKit.TEXT])
	if String(m.get("free_part", "")) != "" and not bool(m.get("repeat", false)):
		notes.append(["Parts Wall: a spare %s" % BenchData.part_name(String(m["free_part"])).to_lower(), UIKit.GOOD])
	if bool(m.get("charity", false)) and not bool(m.get("repeat", false)):
		notes.append(["Raker saved a pod for you. On the house.", UIKit.GOOD])
	var day_now := Game.day
	await get_tree().create_timer(2.8).timeout
	for nt in notes:
		if phase != Phase.MORNING or Game.day != day_now:
			return
		hud.toast(String(nt[0]), nt[1], 3.2)
		await get_tree().create_timer(3.4).timeout
	if phase != Phase.MORNING or Game.day != day_now:
		return
	# los consejos de la temporada (una vez cada uno): el tablero el día 2 (después de la primera noche), las cuotas
	# el día 3 (la primera se cobra esa noche); el de las mejoras sale con el primer estreno
	if Game.day >= 2 and Game.tip_once("board"):
		hud.tip(Data.tip("board"), 6.0)
	elif Game.day >= 3 and Game.tip_once("dues"):
		hud.tip(Data.tip("dues"), 6.0)
	await _morning_beats()

func _morning_beats() -> void:
	# (de a uno: cada momento puede cambiar las marcas que decide el siguiente)
	for _i in 6:
		var bs := Season.beats(Game.day, "morning")
		if bs.is_empty():
			return
		var b: Dictionary = bs[0]
		# espera a que Nell esté libre (sin otra ventana abierta)
		var t := 0.0
		while (modal_open() or busy) and t < 30.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
			if phase != Phase.MORNING:
				return
		if phase != Phase.MORNING:
			return
		busy = true
		await _beat(b)
		busy = false

## Lo que dice al abrir: la nota de la partida vieja, los consejos de la carrera y de cerrar antes.
func _open_notes() -> void:
	if Game.migrated_from > 0 and Game.tip_once("migrated"):
		hud.toast(String(SeasonData.TIPS["migrated"]), UIKit.ACCENT, 4.0)
	if Season.event() == "race" and Game.tip_once("deadline"):
		get_tree().create_timer(2.6).timeout.connect(func():
			if phase == Phase.OPEN:
				hud.tip(Data.tip("deadline"), 6.0))

## Las cosas de las historias en la tienda (W: set_story_prop), según las marcas.
func _story_props() -> void:
	shop.set_story_prop("crate", Game.flag("crate", "") in ["kept", "covered"])
	shop.set_story_prop("certificate", Game.flag("grade", "") == "certified")
	shop.set_story_prop("cup", Game.flag("race", "") == "podium")
	shop.set_story_prop("key", bool(Game.flag("rook_key", false)))
	shop.set_story_prop("ribbon", bool(Game.flag("band", false)) and Game.day >= 8)
	shop.set_story_prop("plaque", bool(Game.flag("paid_in_full", false)))
	shop.set_story_prop("cores", int(Game.flag("cores", 0)))
	shop.set_story_prop("band", Season.band_today())

func _apply_props(props: Dictionary) -> void:
	for k in props:
		shop.set_story_prop(String(k), props[k])

## El estreno de las mejoras compradas esta mañana: la cámara va a cada una, un pop, un aviso (cualquier tecla salta).
func _reveal_new_fittings() -> void:
	busy = true
	_revealing = true
	_reveal_skip = false
	for id in Game.fittings_new.duplicate():
		if not SeasonData.FITTINGS.has(id):
			continue
		shop.cam_fixed = true
		if not _reveal_skip:
			await _glide_camera(shop.upgrade_point(id).x, 0.6)
		shop.reveal_upgrade(id)
		var f: Dictionary = SeasonData.FITTINGS[id]
		hud.toast("New: %s · %s" % [String(f["name"]), String(f["desc"])], UIKit.GOOD, 2.2)
		Sfx.play("upgrade", 0.02, -4.0)
		if not _reveal_skip:
			var t := 0.0
			while t < 1.0 and not _reveal_skip:
				await get_tree().process_frame
				t += get_process_delta_time()
	Game.fittings_new.clear()
	shop.cam_fixed = false
	shop.snap_camera()
	_revealing = false
	busy = false
	if Game.tip_once("fittings"):
		hud.tip(Data.tip("fittings"), 5.0)

func _glide_camera(x: float, secs: float) -> void:
	var from := shop.camera.position.x
	var tw := create_tween()
	tw.tween_method(func(v: float): shop.place_camera(v), from, clampf(x, shop.cam_x0 - 1.5, shop.cam_x1 + 1.5), secs).set_trans(Tween.TRANS_SINE)
	await tw.finished

## Las claves opcionales del trabajo del banco (BenchUI, §8.9): calificado, acertijo, las ayudas de las mejoras.
func _job_keys(j: Dictionary, v: Dictionary) -> void:
	var ex: Dictionary = v.get("extra", {})
	j["aids"] = Season.bench_aids()
	if bool(ex.get("graded", false)):
		j["graded"] = true
	if bool(ex.get("riddle", false)):
		var rd := Data.riddle(String(v.get("item", "")), String(v.get("fault", "")))
		if rd != "":
			j["riddle"] = true
			j["symptom"] = rd
	if ex.has("deadline_min"):
		j["deadline"] = true

## El favor secreto de Glint (día 5): el momento con sus dos opciones es el diálogo del mostrador.
func _favour_talk(v: Dictionary) -> void:
	var bs := Season.beats(Game.day, "open", {"favour": String(v["who"])})
	if bs.is_empty():
		day.leave(v, "declined", Data.line(String(v["who"]), "decline"))
		return
	busy = true
	var c: String = await _beat(bs[0])
	busy = false
	if day.counter.is_empty() or int(day.counter.get("id", -1)) != int(v["id"]):
		return
	if c == "fix":
		var fj: Dictionary = SeasonData.FAVOUR_JOB
		var j := BenchData.make_job(String(fj["item"]), String(fj["fault"]), String(v["who"]))
		j["label"] = String(fj["label"])
		j["sub"] = String(fj["sub"])
		j["symptom"] = String(fj["symptom"])
		j["aids"] = Season.bench_aids()
		day.start_work()
		job = {"kind": "favour", "v": v, "item": String(fj["item"]), "fault": String(fj["fault"]), "stage": "accepted",
			"job": j, "result": {}}
		shop.set_counter_item("")
		go_bench_job()
	else:
		day.leave(v, "declined", String(SeasonData.BEATS["glint_favour"]["options"][1].get("reply", "")))

## El cepillo de Buff, hecho: 40 cr si salió (≥ 1 ★), el bono de Glint en el tablero (+8 esta noche).
func _favour_done(r: Dictionary) -> void:
	var v: Dictionary = job["v"]
	var ok := bool(r.get("ok", false)) and int(r.get("stars", 0)) >= 1
	job = {}
	if phase == Phase.OPEN:
		busy = true
		await shop.walker.go_station("counter")
		busy = false
	if ok:
		var fj: Dictionary = SeasonData.FAVOUR_JOB
		Game.add_credits(int(fj["pay"]))
		Game.stat("repair_pay", int(fj["pay"]))
		Game.stat("repairs")
		Game.stat("served")
		Game.stat("repair_stars", clampi(int(r.get("stars", 0)), 0, 3))
		Game.set_flag("favour", "done")
		Ranking.add_bonus(Ranking.RIVAL, int(fj["bonus"]))
		Sfx.play("coins", 0.05, -2.0)
		hud.toast("+%d cr · Buff's buffer spins again. Glint owes you." % int(fj["pay"]), UIKit.GOOD)
		day.leave(v, "done", Data.line(String(v["who"]), "thanks", clampi(int(r.get("stars", 0)), 0, 3)), Color(0.85, 1.0, 0.8))
	else:
		Game.set_flag("favour", "failed")
		Game.stat("failed")
		day.leave(v, "done", Data.line(String(v["who"]), "failed"))

## Después de entregar: la mañas (bis de Lune, el pago rápido de Brisk), la nota de Tolle, los momentos de Old Seven.
func _after_handover(v: Dictionary, stars: int, ok: bool, tw: Dictionary) -> void:
	var who := String(v["who"])
	var ex: Dictionary = v.get("extra", {})
	if float(tw.get("line_patience", 0.0)) > 0.0:
		for i in day.line_count():
			day.tea_boost(i + 1, float(tw["line_patience"]))
	if String(tw.get("toast", "")) != "":
		get_tree().create_timer(1.6).timeout.connect(func(): hud.toast(String(tw["toast"]), UIKit.GOOD, 2.6))
	if bool(ex.get("graded", false)):
		var g := Season.on_graded(stars, ok)
		Sfx.play("stamp", 0.02, -3.0)
		var a: Actor = v.get("actor")
		if is_instance_valid(a):
			shop.blurt(a, String(g["line"]), Color(1.0, 0.92, 0.6))
		var bits: Array = ["Tally Office: %s" % String(g["name"])]
		if int(g["stars"]) > 0:
			bits.append("+%d ★" % int(g["stars"]))
		if int(g["credits"]) > 0:
			bits.append("+%d cr" % int(g["credits"]))
		if int(g["rep"]) < 0:
			bits.append("%d rep" % int(g["rep"]))
		get_tree().create_timer(1.2).timeout.connect(func(): hud.toast(" · ".join(bits), UIKit.GOOD if String(g["grade"]) != "noted" else UIKit.TEXT, 3.0))
		_apply_props(g.get("prop", {}))
		if String(g.get("crate_line", "")) != "":
			get_tree().create_timer(3.6).timeout.connect(func(): hud.toast("Tolle: \"%s\"" % String(g["crate_line"]), UIKit.TEXT, 3.5))
	var bs := Season.beats(Game.day, "open", {"after_handover": who, "stars": stars if ok else 0})
	if not bs.is_empty():
		await get_tree().create_timer(1.4).timeout
		for b in bs:
			var t := 0.0
			while (modal_open() or busy) and t < 20.0:
				await get_tree().create_timer(0.25).timeout
				t += 0.25
			if phase != Phase.OPEN:
				return
			day.paused = true
			busy = true
			await _beat(b)
			busy = false
			day.paused = false

## Cada cuadro con la tienda abierta: la carrera (a las 2 PM se van los corredores; a las 3 PM se corre).
func _season_tick(minute: int) -> void:
	if Season.event() == "race" and not bool(Season.state.get("race_called", false)) and minute >= int(SeasonData.RACE["call_min"]):
		_race_call()
	if Game.tips_seen.has("first_done") and _can_close_early() and Game.tip_once("close"):
		hud.tip(Data.tip("close", UIKit.interact_key()), 6.0)

func _race_call() -> void:
	var r := Season.race_result()
	hud.banner("The Glasspan Derby", "Zib: \"%s\"" % String(SeasonData.RACE_LINES["call"]), 2.4)
	Sfx.play("cheer", 0.02, -3.0)
	await get_tree().create_timer(3.0).timeout
	hud.toast(String(r["line"]), UIKit.GOOD if String(r["result"]) != "none" else UIKit.TEXT, 4.0)
	if String(r.get("pipip_line", "")) != "":
		await get_tree().create_timer(4.2).timeout
		hud.toast("Pipip: \"%s\"" % String(r["pipip_line"]), UIKit.TEXT, 3.5)
	_story_props()

## Cerrar antes (desde las 4 PM, sin nadie en la fila ni en el mostrador, sin trabajo y sin nadie más por llegar).
func _can_close_early() -> bool:
	return phase == Phase.OPEN and day.running and not day.closing and not day.hold and day.minutes() >= 960 \
		and day.line_count() == 0 and day.counter.is_empty() and day.leaving.is_empty() and job.is_empty() \
		and sale.is_empty() and day.pending_arrivals() == 0

func ask_close_early() -> void:
	dialogs.open({"kind": "talk", "who": "nell", "title": "Close up early", "sub": "%s" % Hud.clock_text(day.minutes()),
		"line": String(SeasonData.TEXT["close_line"]), "options": [{"id": "close", "text": String(SeasonData.TEXT["close_yes"]), "primary": true, "min_w": 170},
			{"id": "no", "text": String(SeasonData.TEXT["close_no"]), "min_w": 150}], "cancel": "no"}, func(c):
		if c == "close" and _can_close_early():
			Season.state["close_early"] = true
			day.force_close())

## Lo que se ve por la ventana de noche (W: set_window_sky).
func _window_sky() -> String:
	match Game.day:
		6:
			return "bigfall"
		8:
			return "bronzemoon"
		10:
			return "starfall"
	return "moons"

## Después de cerrar (§2.7): Nell en el banco, Kettle dormido; hasta 2 arreglos para el estante, sin reloj ni fila.
func _after_hours() -> void:
	after_hours = true
	var bx: float = ShopWorld.STATIONS["bench"]["x"]
	shop.walker.frozen = false
	shop.walker.teleport(bx, -1)
	shop.walker.frozen = true
	shop.nell.face(-1)
	shop.kettle.position = Vector3(-6.6, 0, ShopWorld.LANE_Z + SetKit.KETTLE_DZ)
	shop.kettle.emote("zz", 0.0)
	shop.cam_fixed = true
	shop.place_camera(clampf(bx + shop.cam_bias, shop.cam_x0, shop.cam_x1))
	await get_tree().create_timer(0.6).timeout
	if Game.tip_once("afterhours"):
		hud.tip(Data.tip("afterhours"), 6.0)
	var done := 0
	var max_n := SeasonData.AFTER_HOURS_MAX + int(SeasonData.AFTER_HOURS_BONUS.get(Game.day, 0))
	while done < max_n and not Game.junk.is_empty() and phase == Phase.NIGHT:
		var opts: Array = []
		for i in mini(Game.junk.size(), 3):
			opts.append({"id": "j%d" % i, "text": "Fix: %s" % BenchData.item_name(String(Game.junk[i]["item"])), "primary": i == 0, "min_w": 220})
		opts.append({"id": "sleep", "text": String(SeasonData.TEXT["after_sleep"]), "min_w": 140})
		dialogs.open({"kind": "talk", "who": "kettle", "title": String(SeasonData.TEXT["after_title"]),
			"sub": "%d of %d tonight" % [done + 1, max_n], "line": String(SeasonData.TEXT["after_line"]),
			"options": opts, "cancel": "sleep", "per_row": 2})
		var c: String = await dialogs.closed
		if not c.begins_with("j") or phase != Phase.NIGHT:
			break
		refurb(int(c.substr(1)))
		if not bench.is_open():
			break
		await bench.finished
		await get_tree().process_frame
		done += 1
	if done >= max_n and not Game.junk.is_empty():
		hud.toast(String(SeasonData.TEXT["after_done"]), UIKit.TEXT, 2.6)
	shop.kettle.clear_emote()
	after_hours = false
	job = {}
	# de vuelta a la ventana (el libro de cuentas)
	shop.walker.frozen = false
	shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], -1)
	shop.walker.frozen = true
	shop.nell.position = ShopWorld.NIGHT_NELL
	shop.nell.face(1)
	shop.kettle.position = ShopWorld.NIGHT_KETTLE
	shop.kettle.face(1)
	shop.night_camera()
	hud.clear_tip()

## La cadena de la noche (§8.11): la cuota (noches 3, 6, 9; después cada 3), el tablero de la noche, el Report, los
## momentos de la noche; la noche final (o la primera #1 del modo sin fin): sin tablero ni Report, la gala.
func _night_chain() -> void:
	busy = true
	var due := Season.dues_due(Game.day)
	if due > 0:
		await _dues_beat(due)
	var ending := Ranking.ending_due()
	if not ending:
		night_boards += 1
		rank.open_night(Game.last_summary.get("rank", {}))
		await rank.done
		if Ranking.report_due():
			rank.open_report(Ranking.report())
			await rank.done
	if Ranking.report_due():
		Ranking.mark_report_read()
	for _i in 4:
		var nb := Season.beats(Game.day, "night")
		if nb.is_empty():
			break
		await _beat(nb[0])
	if ending:
		var champion := Ranking.position() == 1
		galas_played += 1
		var choice: String = await gala.play(self, champion)
		if Game.is_campaign():
			Game.ending_seen = true
			Game.crown_seen = champion
			Game.mode = "endless"
		else:
			Game.crown_seen = true
		if choice == "title":
			Game.next_day()
			Game.resume = "morning"
			Game.save_game()
			busy = false
			to_title()
			return
	await fade_to(1.0, 0.5)
	busy = false
	Game.next_day()
	begin_morning()
	_prewarm_today()
	fade_to(0.0, 0.6)

## La cuota de esta noche con Dockmaster Hesk (o el icono de la cuota si todavía no hay su hoja): pagar (o pagar lo
## que se pueda con la regla blanda) y su respuesta.
func _dues_beat(due: int) -> void:
	var hesk: Dictionary = SeasonData.HESK
	var short := Game.credits < due
	var who := "dockmaster" if ResourceLoader.exists("res://assets/chars/dockmaster_idle.png") else ""
	var line := String(hesk["ask_short"] if short else hesk["ask"]).replace("{due}", str(due)).replace("{have}", str(Game.credits))
	var notes: Array = []
	if Game.debt > 0:
		notes.append("Includes %d cr carried over from last time." % Game.debt)
	if short:
		notes.append("Short? Hesk takes all but %d cr and carries the rest, plus 10 %%." % int(SeasonData.SOFT_RULE["keep"]))
	var pay_text := "Pay %d" % due if not short else "Pay what I can (%d)" % maxi(0, Game.credits - int(SeasonData.SOFT_RULE["keep"]))
	var upkeep := not SeasonData.DUES.has(Game.day)
	dialogs.open({"kind": "talk", "who": who, "icon": "" if who != "" else "res://assets/ui/icon_dues.png",
		"title": String(hesk["name"]), "sub": "%s · night %d" % [String(SeasonData.TEXT["upkeep_sub"]) if upkeep else String(hesk["sub"]), Game.day],
		"line": line, "note": " ".join(notes), "options": [{"id": "pay", "text": pay_text, "primary": true, "min_w": 230}],
		"cancel": "pay"})
	await dialogs.closed
	var r := Season.collect_dues()
	Sfx.play("stamp", 0.02, -3.0)
	Sfx.play("coins", 0.05, -4.0)
	Game._update_dues_goal()
	hud.refresh()
	var note2 := ""
	if bool(r.get("late", false)):
		note2 = "LATE: %d cr carried to the next dues. The Board docks you 3 ★." % int(r.get("debt", 0))
	elif bool(r.get("paid_in_full", false)):
		note2 = "PAID IN FULL. A brass plaque goes up by the door."
		shop.set_story_prop("plaque", true)
	else:
		var nd := Season.next_dues()
		if int(nd["night"]) > 0 and int(nd["night"]) <= SeasonData.LAST_DAY:
			note2 = "Next: %d cr on night %d." % [int(nd["amount"]) + int(nd["debt"]), int(nd["night"])]
	dialogs.open({"kind": "talk", "who": who, "icon": "" if who != "" else "res://assets/ui/icon_dues.png",
		"title": String(hesk["name"]), "sub": "Paid %d cr" % int(r.get("paid", 0)), "line": String(r.get("line", "")),
		"note": note2, "options": [{"id": "ok", "text": "Goodnight", "primary": true, "min_w": 170}], "cancel": "ok"})
	await dialogs.closed

## Un momento de historia (§5.5): dos líneas y hasta dos opciones (Dialogs "talk"). Uno con dos opciones no se cierra
## con Esc / B (§5.5): solo avisa "Choose one: 1 or 2". Devuelve la opción elegida.
func _beat(b: Dictionary) -> String:
	var opts: Array = []
	var src: Array = b.get("options", [])
	for i in src.size():
		opts.append({"id": String(src[i]["id"]), "text": String(src[i]["text"]), "primary": i == 0, "min_w": 200})
	if opts.is_empty():
		opts = [{"id": "ok", "text": "Okay", "primary": true, "min_w": 160}]
	var must := bool(b.get("must_choose", false)) and opts.size() > 1
	var who := String(b.get("who", ""))
	var lines: Array = b.get("lines", [])
	_beat_actor(who)
	var sp: Dictionary = Data.SPECIES.get(Data.species_of(who), {})
	var spec := {"kind": "talk", "who": who, "sub": String(SeasonData.ROLE_SUB.get(who, sp.get("name", ""))), "line": String(lines[0]) if lines.size() > 0 else "",
		"line2": String(lines[1]) if lines.size() > 1 else "", "options": opts, "per_row": 2, "beat": String(b.get("id", ""))}
	if must:
		spec["must_choose"] = true
	else:
		spec["cancel"] = String(opts[-1]["id"]) if opts.size() == 1 else String(opts[0]["id"])
	dialogs.open(spec)
	var c: String = await dialogs.closed
	if c == "":
		c = String(opts[0]["id"])
	var r := Season.apply_beat(String(b.get("id", "")), c, bool(b.get("low", false)))
	_apply_props(r.get("prop", {}))
	if int(r.get("cores", 0)) > 0:
		shop.set_story_prop("cores", int(r["cores"]))
	if String(r.get("reply", "")) != "":
		hud.toast("%s: \"%s\"" % [Data.char_name(who), String(r["reply"])], UIKit.TEXT, 3.0)
	elif String(r.get("toast", "")) != "":
		hud.toast(String(r["toast"]), UIKit.GOOD, 3.2)
	if int(r.get("stars", 0)) > 0:
		Sfx.play("good", 0.02, -6.0)
	if _story_actor and is_instance_valid(_story_actor):
		_story_actor.queue_free()
	_story_actor = null
	return c

## Quien habla en la calle aparece a un lado de Nell mientras dura el momento (los actores son lo único que se crea
## en marcha: §8.13).
func _beat_actor(who: String) -> void:
	if phase != Phase.MORNING or who == "" or who == "nell":
		return
	if who == "rival" and street.rival_actor() and street.rival_actor().visible:
		return
	var pos := Vector3(street.nell.position.x + 1.5, 0.0, StreetWorld.LANE_Z - 0.35)
	if who == "hermit":
		pos = street.hermit_spot()
	_story_actor = street.make_actor(who, pos, -1)

## El tablero entero (el chip del HUD, R, Y): de mañana y con la tienda abierta, nunca sobre otra ventana. El reloj
## espera mientras está abierto.
func open_rank_board() -> void:
	if phase not in [Phase.MORNING, Phase.OPEN] or modal_open() or _work_ui_open() or busy or menu_open or rank == null:
		return
	if Game.tip_once("board"):
		pass
	day.paused = true
	hud.hide_prompt()
	rank.open_board()
	await rank.done
	day.paused = false

## El calendario de la temporada (el tablón de la calle y el menú).
func open_calendar() -> void:
	if dialogs.is_open():
		return
	var paused_before := day.paused
	day.paused = true
	dialogs.open({"kind": "calendar"}, func(_c): day.paused = paused_before)

## El patio de Dolly: las 8 mejoras, a precio fijo (desde el día 2).
func fittings_stall() -> void:
	if not Season.is_unlocked("vendor"):
		street.blurt(street.vendor_actor() if street.vendor_actor() else street.nell, String(SeasonData.DOLLY["closed"]))
		return
	dialogs.open({"kind": "fittings", "width": 820})
	if Game.tip_once("dolly_kettle"):
		get_tree().create_timer(0.8).timeout.connect(func():
			if dialogs.is_open() and String(dialogs.spec.get("kind", "")) == "fittings":
				hud.toast("Kettle: \"%s\"" % String(SeasonData.DOLLY["kettle"]), UIKit.TEXT, 3.5))

## La vecina (desde el día 3): su frase del día y quién va delante.
func visit_rival() -> void:
	if not Season.is_unlocked("rival"):
		street.blurt(street.nell, String(SeasonData.RIVAL_VISIT["closed"]))
		return
	var gap := Ranking.score(Ranking.RIVAL) - Ranking.score()
	var key := "neutral"
	if gap > 4:
		key = "ahead"
	elif gap < -4:
		key = "behind"
	var note := "Shine Again: %d ★ ahead of you." % gap if gap > 0 else ("You lead Shine Again by %d ★." % -gap if gap < 0 else "Neck and neck with Shine Again.")
	dialogs.open({"kind": "talk", "who": "rival", "sub": "Shine Again, next door", "line": String(SeasonData.RIVAL_VISIT[key]),
		"note": note, "options": [{"id": "ok", "text": "See you, Glint", "primary": true, "min_w": 180}], "cancel": "ok"})

## La música del evento de hoy (al continuar una partida: bajo el fundido) y la de mañana (bajo el libro de cuentas).
func _prewarm_today() -> void:
	var ed := Season.event_def()
	for k in ["music", "amb"]:
		if String(ed.get(k, "")) != "":
			Sfx.prewarm_late(String(ed[k]))

func _prewarm_tomorrow() -> void:
	for alias in Season.tomorrow_loops(Game.day):
		Sfx.prewarm_late(String(alias))
	if Game.day == 1:
		Sfx.prewarm_late("night")
	if Ranking.ending_due():
		Sfx.prewarm_late("gala")

## (Pruebas: --bootjump=...) los caminos nuevos de la ronda 2, después del arranque de verdad.
func _season_jump(where: String) -> void:
	if where.begins_with("event_"):
		var ev := where.substr(6)
		var d := 5
		for k in SeasonData.PLAN:
			if String(SeasonData.PLAN[k].get("event", "")) == ev:
				d = int(k)
		Season.debug_state(d, "good")
		begin_morning()
		await get_tree().create_timer(2.0).timeout
		open_shop_now()
	elif where == "upgrades":
		Season.debug_state(9, "good")
		for id in SeasonData.FITTING_ORDER:
			if not Game.has_fitting(id):
				Game.fittings.append(id)
		Game.fittings_new = ["neon"]
		open_shop_now()
	elif where.begins_with("bench_"):
		Season.debug_state(8, "good")
		open_shop_now()
		day.clear()
		var item := where.substr(6)
		bench.open(BenchData.make_job(item, String(BenchData.FAULTS[item].keys()[0]), "gorrum"))
	elif where == "board":
		Season.debug_state(5, "good")
		begin_morning()
		await get_tree().create_timer(1.0).timeout
		open_rank_board()
	elif where == "report":
		Season.debug_state(4, "good")
		open_shop_now()
		show_night()
		await get_tree().create_timer(1.0).timeout
		rank.open_report(Ranking.report())
	elif where in ["gala_win", "gala_lose"]:
		Season.debug_state(10, "good")
		show_night()
		screens.hide_all()
		gala.play(self, where == "gala_win")
	elif where.begins_with("nightst_"):
		# --- SS2 MERGE: (pruebas) la calle de noche con partes del estado de la gala: e = el decorado de la final,
		# b = la banda, r = Shine Again abierta, n = Nell y Kettle en la puerta, c = la cámara de la gala
		var f := where.substr(8)
		Season.debug_state(10, "good")
		screens.hide_all()
		hud.show_top(false)
		use_world(street)
		street.set_night(true)
		if "e" in f:
			street.set_event("finale")
		if "b" in f:
			street.set_band(true)
		if "r" in f:
			street.set_rival_open(true)
			street.set_vendor_open(true)
		if "n" in f:
			street.walker.frozen = true
			street.kettle_follow = false
			street.nell.global_position = Vector3(StreetWorld.SHOP_X, 0.0, -2.05)
			street.kettle.global_position = Vector3(StreetWorld.SHOP_X + 0.65, 0.0, -1.75)
		if "c" in f:
			street.cam_fixed = true
			street.place_camera(-5.0)
	elif where.begins_with("galastep_"):
		# --- SS2 MERGE: (pruebas) la gala sola, quieta en un momento (count_done, walk_done, comet_on, ring_...),
		# para saber qué momento compila algo después del arranque
		Season.debug_state(10, "good")
		screens.hide_all()
		gala.demo_stop = where.substr(9)
		gala.play(self, true)
# --- end SS2 SEASON
