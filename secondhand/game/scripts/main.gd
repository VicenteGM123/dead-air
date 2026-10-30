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
var autoplay_days := 3
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
	_build_fade()
	_make_day()
	day.setup(shop, hud)
	_make_pad()
	Sfx.apply_volumes()
	boot_ready = true
	fade.color.a = 0.0
	if _bench_demo(demo):
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
	pad.dialog_waiting = func(): return dialogs.is_open() or screens.is_open() or (pod_ui != null and pod_ui.is_open()) or (bench != null and bench.is_open() and bench.step == bench.get_script().Step.RESULT)
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
	_boot_bg_total = steps.size() + 50 + 18
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
			"bench_stage", "bench_pod_view", "pod_ui", "haggle_ui", "bench_ui"]:
		var path := "res://scripts/ui/%s.gd" % f
		if ResourceLoader.exists(path):
			keep.append(load(path))
		await _bg_step("script_" + f)
	_make_bench()
	await _bg_step("bench")
	_make_haggle()
	await _bg_step("haggle")
	_make_pod_ui()
	await _bg_step("pod_ui")
	for n in ["music_market", "amb_port", "music_shop"]:
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
	screens.show_title(Game.can_continue())
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
	screens.show_intro(Data.INTRO)
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
	street.set_pods_left(Game.pods_today.size())
	hud.show_top(true)
	hud.refresh()
	hud.set_clock(Data.OPEN_MIN, "morning")
	hud.banner("Day %d" % Game.day, "Morning at the Starfall Market")
	Sfx.music("market")
	Sfx.ambience("port")
	Game.resume = "morning"
	Game.save_game()
	if Game.day == 1 and Game.tip_once("walk"):
		get_tree().create_timer(2.6).timeout.connect(func():
			if phase == Phase.MORNING:
				hud.tip(Data.tip("walk", UIKit.interact_key(), "the stick" if PadCursor.pad_in_use else "A/D"), 9.0))
	elif Game.day > 1:
		get_tree().create_timer(2.6).timeout.connect(func():
			if phase == Phase.MORNING:
				street.blurt(street.raker, Data.MARKET_LINES["raker_hello"]))

## El puesto de Raker: las cápsulas de hoy (peso y traqueteo), elegir una y regatear.
func pods_stall() -> void:
	if Game.pods_today.is_empty():
		street.blurt(street.raker, Data.MARKET_LINES["raker_sold_out"])
		return
	var cheapest := 9999
	for p in Game.pods_today:
		cheapest = mini(cheapest, int(p.get("price", 30)))
	if Game.credits < int(cheapest * 0.7):
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
	return "%s · %s · asks ~%d cr" % [w, r, int(round(float(p.get("price", 30)) * ask))]

func _on_pod_choice(id: String) -> void:
	if not id.begins_with("pod"):
		return
	var i := int(id.substr(3))
	if i < 0 or i >= Game.pods_today.size():
		return
	var pod: Dictionary = Game.pods_today[i]
	pod_pick = {"index": i, "pod": pod}
	var deal := BenchData.make_deal("buy", "Salvage pod", "raker", int(pod.get("price", 30)))
	deal["pod"] = pod.duplicate(true)      # (opcional en el contrato: la pantalla puede mostrar la cápsula)
	haggle.open(deal)

func parts_stall() -> void:
	dialogs.open({"kind": "parts", "width": 760})

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
	day.open_day(Game.day, tutorial)
	hud.show_top(true)
	hud.refresh()
	hud.set_clock(Data.OPEN_MIN, "open")
	hud.set_line(0, Data.MAX_LINE)
	hud.banner("Open!", "We close at 6 PM")
	Sfx.music("shop")
	Sfx.ambience("port")
	if not Game.junk.is_empty() and not tutorial and Game.tip_once("junk"):
		get_tree().create_timer(3.2).timeout.connect(func():
			if phase == Phase.OPEN:
				hud.tip(Data.tip("junk"), 7.0))

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
	var sp: Dictionary = Data.SPECIES.get(Data.species_of(who), {})
	var sub := String(sp.get("name", ""))
	if bool(v.get("grumpy", false)):
		sub += " · grumpy from waiting"
	if String(v["kind"]) == "repair":
		var j := BenchData.make_job(String(v["item"]), String(v["fault"]), who)
		if day.hold:
			j["tutorial"] = true               # (opcional: el primer trabajo del día 1, Kettle explica más)
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
		dialogs.open({"kind": "talk", "who": who, "sub": sub, "line": Data.line(who, "bring", String(v["item"])),
			"tag": String(j.get("symptom", "")), "item": "" if me else String(v["item"]), "note": note,
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
				var base := BenchData.sale_price(String(e["item"]), int(e["stars"]))
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
	bench.open(BenchData.make_job(String(jk["item"]), String(jk["fault"]), ""))

func _on_bench_finished(r: Dictionary) -> void:
	check_keys("bench", r, ["ok", "stars", "time", "fault_found", "patched", "parts_used"])
	shop.set_bench_item("")
	if job.is_empty():
		return
	var ok := bool(r.get("ok", false))
	var stars := clampi(int(r.get("stars", 0)), 0, 3)
	if String(job["kind"]) == "refurb":
		if ok:
			Game.shelf_add(String(job["item"]), stars)
			Game.stat("refurbished")
			hud.toast("%s %s is on the shelf." % [BenchData.item_name(String(job["item"])), stars_text(stars)], UIKit.GOOD)
			shop.kettle.emote("star", 1.2)
		else:
			Game.add_junk(String(job["item"]), String(job["fault"]))
			hud.toast("Not this time. It goes back on the junk pile.")
		job = {}
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
		day.leave(v, "done", Data.line(who, "thanks", stars), Color(0.85, 1.0, 0.8))
	else:
		Game.stat("failed")
		Game.add_rep(Data.REP_GAVE_UP)
		hud.toast("No luck with that one. %s takes it back." % Data.char_name(who), UIKit.BAD)
		day.leave(v, "done", Data.line(who, "failed"))
	job = {}
	_end_tutorial()

## El primer cliente del día 1 ya se fue (atendido o no): el reloj arranca.
func _end_tutorial() -> void:
	if day.hold:
		day.hold = false
		Game.tips_seen["first_done"] = true
		hud.tip(Data.tip("clock"), 6.0)

func repair_pay(item: String, stars: int, secs: float) -> int:
	if BenchData.has_method("repair_pay"):
		return int(BenchData.repair_pay(item, stars, secs))
	return int(round(30.0 * [0.35, 0.7, 1.0, 1.3][stars]))

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
			Game.add_rep(Data.REP_SALE)
			var extra := ""
			var barter := String(r.get("barter", ""))
			if barter != "" and BenchData.PARTS.has(barter):
				# --- SS MERGE: el trueque de Mother Oona trae barter_n piezas (contrato de HaggleUI), no siempre una
				var bn := maxi(1, int(r.get("barter_n", 1)))
				Game.add_part(barter, bn)
				extra = (" + a %s" % BenchData.part_name(barter).to_lower()) if bn == 1 else (" + %d %ss" % [bn, BenchData.part_name(barter).to_lower()])
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
	for c in contents:
		if not (c is Dictionary):
			contract_error("pod: contenido que no es un diccionario: %s" % str(c))
			continue
		if c.has("part"):
			Game.add_part(String(c["part"]))
		elif c.has("item"):
			Game.add_junk(String(c["item"]), String(c.get("fault", "")))
			broken = true
		got.append(BenchData.content_name(c))
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
	if bool(Game.today.get("tea", false)) or not someone or tea_running:
		shop.kettle.hop(1)
		Sfx.play("whistle", 0.08, -10.0)
		hud.toast(Data.KETTLE_TEA_DONE if bool(Game.today.get("tea", false)) else String(Data.KETTLE_TALK[randi() % Data.KETTLE_TALK.size()]))
		return
	Game.today["tea"] = true
	tea_running = true
	Sfx.play("tea", 0.02, -4.0)
	hud.toast(Data.KETTLE_TEA, UIKit.GOOD)
	await shop.tea_walk(func(i): day.tea_boost(i))
	tea_running = false

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
	var s := Game.close_day()
	street.refresh_sign()
	screens.show_ledger(s, Game.is_last_day())
	Sfx.music("title")
	Sfx.ambience("wind")

func _on_ledger_done() -> void:
	if phase != Phase.NIGHT:
		return
	busy = true
	await fade_to(1.0, 0.5)
	busy = false
	if Game.is_last_day():
		show_closing()
	else:
		Game.next_day()
		begin_morning()
	fade_to(0.0, 0.6)

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
	dialogs.open({"kind": "menu", "sub": sub}, func(c):
		menu_open = false
		day.paused = false
		if c == "title":
			to_title())

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
	return _work_ui_open() or dialogs.is_open() or screens.is_open() or menu_open

## --- BOOT: el banco, el regateo o la cápsula abiertos (en el título pueden no existir todavía).
func _work_ui_open() -> bool:
	return (bench != null and bench.is_open()) or (haggle != null and haggle.is_open()) or (pod_ui != null and pod_ui.is_open())

func can_walk() -> bool:
	return (phase == Phase.MORNING or phase == Phase.OPEN) and not modal_open() and not busy and fade.color.a < 0.6

## La capa cuyos botones toca el mando ahora (PadCursor.buttons_root).
func _pad_root() -> Control:
	if dialogs.is_open():
		return dialogs
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
	elif phase == Phase.OPEN:
		match id:
			"counter":
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
				return ["Buy pods", true] if not Game.pods_today.is_empty() else ["Sold out", false]
			"parts":
				return ["Buy parts", true]
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
					return ["Repair" if String(v["kind"]) == "repair" else "Sell", true]
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
				if not bool(Game.today.get("tea", false)) and someone and not tea_running:
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
		if day.line_count() >= 3 and not bool(Game.today.get("tea", false)) and not day.hold and Game.tip_once("tea"):
			hud.tip(Data.tip("tea", UIKit.interact_key()), 7.0)
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
