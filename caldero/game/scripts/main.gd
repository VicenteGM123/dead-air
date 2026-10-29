extends Node
## Flujo del juego: título, mañana (mercado), clientes, caldero, entregas y cierre del día.

enum Phase { TITLE, INTRO, MORNING, OPEN, CLOSING, EVENT }   # --- R4 EVENTS: EVENT = el día de un evento (no se abre la tienda)

# --- R4 PACE: el día abierto dura 5 minutos (un reloj de 9:00 a 18:00). Para las otras partes (el cuervo, el escalafón):
signal shop_opened     # se abrió la tienda: empieza a correr el reloj (shop_minutes() = 540)
signal shop_closing    # dieron las 18:00: ya no entra nadie (se atiende a quien está en el mostrador)
# --- end R4 PACE

# --- STORY: el mundo es más grande (elfos, enanos, gente bestia, caballeros, magos...) y las pociones hacen efecto después
# --- R3 MERGE: dieta de texto (una o dos frases cortas por línea)
const INTRO_LINES := [
	["", "At the foot of the Grey Mountain, in Arvendal, there's a little potion shop whose fire never goes out."],   # --- R4 RANK: Arvendal
	["", "Your teacher left it to you: her recipe book, her grimoire, a cauldron and Miga, a sleepy cat."],
	["", "Folks from all over the kingdom pass through: elves, dwarves, knights, mages… They always need something."],
	["", "Potions work later: your customers will tell you how it went."],
	["", "The Arvendal Apothecaries' Guild ranks the thirty best shops. Yours is dead last… for now."],   # --- R4 RANK
]
# --- end STORY

const THANKS := [
	["Thank you! Just what I needed.", "Thanks so much, neighbor!", "I owe you one. See you soon!"],
	["It looks great! Thank you, really.", "It smells wonderful. Thanks!", "You can tell you put love into it!"],
	["This is a master's work! I'll tell everyone about your shop.", "It shines so much it's a shame to drink it! Thank you.", "Amazing! I'll be back for sure."],
]

var world: ShopWorld
var ui: GameUI
var ov: Overlays
var post: ColorRect
var fade: ColorRect
var phase := Phase.TITLE
var queue: Array = []
var current := {}
var customer: Actor
var customer_ready := false
var misses := 0
var hint_given := false
var contents: Array = []
var busy := false
var served := 0
var total_today := 1
var pending_levels: Array = []
var tutorial_step := -1
var open_btn: Button
var pad: PadCursor
# --- WORLD: caminar por la tienda, estaciones y el viaje al mercado
var market: MarketWorld
var in_market := false          # la alquimista está en el mercado (la tienda está escondida y en pausa)
var _trip_busy := false         # yendo o volviendo del mercado (fundido)
var trip_btn: Button            # "Ir al mercado" / "Volver a la tienda"
var top_box: VBoxContainer
var _jar_queue: Array = []      # frascos tocados de lejos: se echan al llegar al caldero
var _jar_trip := false          # --- INTEGRATE: va al estante por frascos tocados de lejos (un cliente espera a que los eche)
var _market_tip_shown := false
# --- end WORLD
var grimoire: GrimoireUI   # --- MAGIC: el grimorio del escritorio (scripts/ui/grimoire_ui.gd)
# --- R3 BENCH: el banco del caldero (scripts/ui/brew_ui.gd) y la poción removida que espera a ser embotellada
var brew: BrewUI
var brew_ready := {}       # {"potion", "potency", "perfect"} o {} (se embotella con «Embotellar» o al cerrar el banco)
# --- end R3 BENCH
var krapido: Krapido       # --- R4 RAVEN: Krápido, el reparto por cuervo (scripts/krapido.gd: la bola, Graznido, los pedidos)
# --- R4 EVENTS: los eventos (scripts/events.gd, scripts/event_game.gd, scripts/ui/event_ui.gd, EventScenes)
var events_ui: EventUI
var ev_game: EventGame
var ev_scene: Node3D
var _ev_morning_done := false
# --- end R4 EVENTS

# pruebas automáticas / capturas
var _shot_path := ""
var _shot_frames := 0
var _frame := 0
var _demo := ""
var _autoplay_days := 0
var _stats := false   # --- R4 SCENES: --stats

## --- R5 EN-UI: el título que se ve (ventana de escritorio y pestaña del navegador). application/config/name sigue
## siendo «Caldero Nocturno» en project.godot: de ese nombre sale la carpeta user:// de escritorio (las partidas
## guardadas); la página web lo pone desde el principio con html/head_include (export_presets.cfg).
const GAME_TITLE := "Midnight Cauldron"
# --- end R5 EN-UI

func _ready() -> void:
	get_window().title = GAME_TITLE   # --- R5 EN-UI (en la web también cambia document.title)
	get_viewport().physics_object_picking = true
	# --- BOOT: los argumentos primero (antes iban al final de _ready): con --demo=... todo se arma de un tirón como
	# antes (las pruebas y capturas no cambian); si no, el arranque va en pasos (_boot) con la pantalla de carga viva.
	_parse_args()
	if _demo != "":
		world = ShopWorld.new()
		add_child(world)
		world.build()
		_bs_world_hooks()
		for step in _boot_steps():
			step.call()
		_booted = true
		Sfx.start_ambience()
		BootScreen.close(0.0)
		_run_demo()
		return
	_boot()
	# --- end BOOT

# --- BOOT: el arranque en pasos ---------------------------------------------------------------------------------
# Lo que antes hacía _ready de un tirón, en el orden de siempre, partido en pasos. Con --demo, _ready los llama todos
# seguidos; en el juego, _boot() deja pasar un cuadro entre uno y otro (la pantalla de carga se mueve y la página
# responde). Ningún paso cambió por dentro: son los mismos trozos de antes.

func _bs_world_hooks() -> void:
	# --- WORLD: la alquimista camina (walker.gd) y las estaciones solo funcionan cuando llega
	world.walker.can_walk = _can_walk
	world.can_use = _can_use_station
	world.station_clicked.connect(_on_station_clicked)

func _bs_market() -> void:
	market = MarketWorld.new()
	add_child(market)
	market.build()
	market.walker.can_walk = _can_walk
	market.can_use = func(_id): return _can_walk()
	market.station_clicked.connect(_on_market_station)
	_set_place_on(market, false)
	# --- end WORLD

func _bs_post() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/hd2d_post.gdshader")
	post.material = sm
	post_layer.add_child(post)


func _bs_ui() -> void:
	ui = GameUI.new()
	add_child(ui)

func _bs_overlays() -> void:
	ov = Overlays.new()
	add_child(ov)
	# --- R3 BENCH: el banco del caldero (capa 4, debajo del HUD)
	brew = BrewUI.new()
	brew.setup(self)
	add_child(brew)
	brew.opened.connect(_on_brew_opened)
	brew.closed.connect(_on_brew_closed)
	# --- end R3 BENCH
	_build_open_button()
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.01, 0.04, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade)
	# mando: cursor virtual y botones (ver scripts/ui/pad_cursor.gd)
	pad = PadCursor.new()
	pad.ui = ui
	pad.ov = ov
	pad.world = world
	pad.market = market   # --- WORLD
	pad.brew = brew       # --- R3 BENCH
	add_child(pad)

func _bs_krapido() -> void:
	# --- R4 RAVEN: Krápido (la ventanilla del cuervo y la bola de cristal; la medalla del HUD)
	krapido = Krapido.new()
	krapido.name = "Krapido"
	add_child(krapido)
	krapido.setup(self)
	pad.ball = krapido.ball
	# --- end R4 RAVEN

func _bs_wire() -> void:
	world.jar_clicked.connect(_on_jar_clicked)
	world.jar_hover.connect(func(id):
		if not ov.is_open() and not world.hover_blocked():   # --- R3 SHIP: no con el banco abierto (selección vieja)
			ui.show_ingredient_tooltip(id))
	world.jar_unhover.connect(func(_id): ui.hide_tooltip())
	world.cat_clicked.connect(_on_cat_clicked)
	world.book_clicked.connect(func():
		if _can_interact(true):
			ov.show_book())
	# --- WORLD: el cliente, el mostrador y el caldero son estaciones (ver _on_station_clicked)
	# --- R3 BENCH: Remover, Vaciar y los huecos del caldero están en el banco (brew_ui.gd llama a main)
	ui.potion_pressed.connect(_on_potion)
	ui.choice_made.connect(_on_choice)
	ui.menu_pressed.connect(_on_menu)
	ov.new_game.connect(_start_new)
	ov.continue_game.connect(_continue)
	ov.open_shop.connect(_open_shop)
	ov.sleep.connect(_sleep)
	ov.to_title.connect(_to_title)
	ov.closed.connect(_on_overlay_closed)
	Game.level_up.connect(func(lv):
		pending_levels.append(lv)
		world.refresh_jars()
		for id in Data.INGREDIENT_ORDER:
			if Data.INGREDIENTS[id]["level"] == lv:
				world.spawn_sparkles(world.jars[id].global_position + Vector3(0, 0.4, 0.2), Color(1.6, 1.5, 1.0), 24))
	Game.stock_changed.connect(func(): world.refresh_jars())
	Game.potions_changed.connect(func(): world.refresh_rack())
	Game.upgrades_changed.connect(_on_upgrades_changed)

func _bs_magic() -> void:
	# --- R3 MAGIC3: el libro de runas del escritorio (encanta pociones del estante) y la tinta del caldero
	grimoire = GrimoireUI.new()
	grimoire.setup(self)
	add_child(grimoire)
	ui.magic_setup()
	ui.ink_pressed.connect(_on_brew_ink)
	# --- end R3 MAGIC3

func _bs_events() -> void:
	_ev_setup()   # --- R4 EVENTS
	_perf_prefill_faces()   # --- R6 PERF
	_r6_setup()   # --- R6 UI: los avisos de acción, el dispositivo (teclado, ratón, mando) y --glyphs= (MERGE6: el último, su GlyphWatcher ve la entrada primero)

## Los pasos después de la tienda (ShopWorld se arma aparte: en el juego, repartido en cuadros con build_sliced).
func _boot_steps() -> Array[Callable]:
	return [_bs_market, _bs_post, _bs_ui, _bs_overlays, _bs_krapido, _bs_wire, _bs_magic, _bs_events]

var boot_warm: BootWarm   # el precalentamiento de después del título (scripts/boot_warm.gd)
var _booted := false      # ya están todos los pasos (main._process y la entrada esperan a esto)

## El arranque del juego: la pantalla de carga (BootScreen, ya en pantalla desde el primer cuadro: scripts/boot.gd)
## tapa todo mientras se arma la tienda en pasos de un cuadro, se encienden los sonidos de fondo de a uno y la tienda se
## muestra por partes (pocos materiales nuevos por cuadro: los shaders se compilan repartidos, no todos en un cuadro de
## varios segundos). Solo lo que necesita el título. Después: el título, la pantalla de carga se funde, y lo demás que
## antes se precalentaba en negro (la biblioteca, los efectos, las letras de los eventos, el mercado) lo hace BootWarm
## repartido en cuadros mientras el jugador ya ve el título.
func _boot() -> void:
	var tree := get_tree()
	_bm("main:start")
	BootScreen.progress(0.56)
	world = ShopWorld.new()
	world.visible = false   # no se dibuja (ni compila nada) hasta _boot_reveal_world
	add_child(world)
	await world.build_sliced(tree)
	_bs_world_hooks()
	_bm("world")
	var steps := _boot_steps()
	for i in steps.size():
		BootScreen.progress(0.58 + 0.12 * i / float(steps.size()))
		await tree.process_frame
		var st := PerfLog.t0()
		steps[i].call()
		PerfLog.step("boot:step%d script" % i, st)
		if post:
			post.visible = false   # el desenfoque (lee la pantalla entera) se enciende al final, bajo la pantalla de carga
		_bm("step%d" % i)
	_booted = true
	# los sonidos de fondo, de a uno por cuadro: en la web cada uno se decodifica entero la primera vez que suena
	for p in [Sfx.fire, Sfx.night, Sfx.music]:
		await tree.process_frame
		if not (p as AudioStreamPlayer).playing:
			(p as AudioStreamPlayer).play()
	Sfx.start_ambience()
	await tree.process_frame
	_bm("ambience")
	BootScreen.progress(0.72)
	await _boot_reveal_world(0.72, 0.96)
	_bm("revealed")
	post.visible = true
	_show_title()
	await tree.process_frame   # el título y el desenfoque, dibujados (y compilados) bajo la pantalla de carga
	await tree.process_frame
	_bm("title:shown")
	BootScreen.close(0.45)
	await get_tree().create_timer(0.45).timeout
	_bm("title:faded_in")
	if not OS.get_cmdline_user_args().has("--nobootwarm"):   # (medición: sin el precalentamiento de después)
		boot_warm = BootWarm.start(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bootcheck"):
			_boot_check(a.substr(12) if a.begins_with("--bootcheck=") else "new")

## Muestra la tienda por partes: cada cuadro solo lo que trae un material nuevo (cada material nuevo = varios
## programas de shader, uno por cada pasada y luz que lo toca, que WebGL enlaza en ese cuadro sin soltar la página). Con
## las luces y la noche del título desde el principio: lo que se compila es lo que el título usa. Mientras tanto la
## tienda se dibuja a un cuarto de resolución (la tapa la pantalla de carga): los cuadros cuestan menos.
func _boot_reveal_world(p0: float, p1: float) -> void:
	var tree := get_tree()
	world.set_time(1.0, false)   # la noche del título (como _show_title)
	var hidden := {}
	BootWarm.hide_layers(world, hidden)
	var vp := get_viewport()
	var scale0 := vp.scaling_3d_scale
	vp.scaling_3d_scale = 0.5
	world.visible = true
	var items := BootWarm.items_of(world)
	var total := maxi(1, items.size())
	var seen := {}
	var budget := 1   # firmas de material nuevas por cuadro (las de shader propio o partículas pesan doble)
	await tree.process_frame   # (el primer cuadro con la tienda: las luces, el entorno, el cielo; sin objetos)
	var last := Time.get_ticks_usec()
	while not items.is_empty():
		var before := seen.size()
		var group := BootWarm.take_group(items, seen, budget, 32 * budget)
		for n in group:
			BootWarm.restore_layers(n, hidden)
		_bm("reveal %d nodes, +%d keys (budget %d)" % [group.size(), seen.size() - before, budget])
		BootScreen.progress(lerpf(p0, p1, 1.0 - items.size() / float(total)))
		await tree.process_frame
		# con una tarjeta rápida (cuadros cortos aun compilando) van más materiales por cuadro; si no, uno
		var now := Time.get_ticks_usec()
		budget = mini(budget + 1, 4) if now - last < 50000 else 1
		last = now
	BootWarm.restore_layers(world, hidden)
	vp.scaling_3d_scale = scale0
## (pruebas, con --perflog) --bootcheck[=new|continue]: el arranque de verdad (no es una demo) y, cuando BootWarm
## termina, lo que un jugador hace primero: «Start» (la introducción, pasada con el mismo aviso que el clic) o
## «Continue» (la partida guardada), la mañana en la tienda, la biblioteca, la puerta, el mercado (un puesto), de vuelta
## y los efectos del caldero. Cada paso deja una marca «check:...»: en la web, webboot.mjs cuenta los programas de
## shader que se enlazan entre marca y marca (lo que BootWarm no cubrió se ve ahí). --nobootwarm: sin BootWarm.
func _boot_check(mode: String) -> void:
	if is_instance_valid(boot_warm):
		await boot_warm.wait_done(600.0)
	PerfLog.mark("check:warm_done")
	await get_tree().create_timer(1.0).timeout
	print("BOOTCHECK title has_save=", Game.has_save(), " current=", ov.current)
	ov.close(false)
	if mode == "continue":
		_continue()
	else:
		_start_new()
	PerfLog.mark("check:start")
	var t := 0.0
	while phase != Phase.MORNING and t < 120.0:
		await get_tree().create_timer(0.6).timeout
		t += 0.6
		if phase == Phase.INTRO:
			ui.dialog_advanced.emit()
	PerfLog.mark("check:morning")
	print("BOOTCHECK morning day=", Game.day, " gold=", Game.gold)
	await get_tree().create_timer(6.0).timeout
	for i in 6:   # el correo de la mañana y los consejos
		if ov.is_open():
			ov.close()
		await get_tree().create_timer(0.8).timeout
	Game.tutorial_done = true
	PerfLog.mark("check:walk")
	await get_tree().create_timer(2.0).timeout
	PerfLog.mark("check:library")
	await world.go_station("biblioteca")
	await get_tree().create_timer(3.0).timeout
	PerfLog.mark("check:door")
	await world.go_station("puerta")
	await get_tree().create_timer(3.0).timeout
	PerfLog.mark("check:market")
	await _go_market()
	await get_tree().create_timer(3.0).timeout
	PerfLog.mark("check:stall")
	await market.use_station("ilse")
	await get_tree().create_timer(3.0).timeout
	ov.close()
	PerfLog.mark("check:back")
	await _leave_market()
	await get_tree().create_timer(3.0).timeout
	PerfLog.mark("check:cauldron")
	await world.go_station("caldero")
	world.cauldron.brew_burst(Color(0.6, 0.9, 0.5))
	world.cauldron.splash(Color(0.6, 0.9, 0.5))
	world.spawn_sparkles(world.cauldron.global_position + Vector3(0.6, 1.2, 0.4), Color(1.6, 1.5, 1.0), 8)
	world.spawn_hearts(world.cauldron.global_position + Vector3(1.1, 1.2, 0.4))
	world.alchemist.emote("heart")
	await get_tree().create_timer(3.0).timeout
	PerfLog.mark("check:end")
	print("BOOTCHECK done")
	if DisplayServer.get_name() == "headless":
		get_tree().quit()

## (con --perflog) la hora de cada paso del arranque: «M ... boot:<paso> ticks=<ms desde que arrancó el motor>»
func _bm(step: String) -> void:
	if PerfLog.on:
		PerfLog.mark("boot:%s ticks=%d" % [step, Time.get_ticks_msec()])
# --- end BOOT

func _build_open_button() -> void:
	# --- R6 UI: arriba al centro, una sola fila a la altura de la placa y de la barra de la derecha: la acción principal
	# («Open shop», con la campanilla y su tecla O) y otra más tranquila («Market» con la cesta, o en el mercado «Back to
	# shop» con la casita; tecla M). Son HudButton (scripts/ui/hud_button.gd): pergamino sobre nogal, el principal con aro
	# de latón; la misma forma, altura y letra; estados normal, encima, pulsado, desactivado (durante el viaje) y el aro
	# del cursor del mando. Antes: dos bloques lisos uno encima del otro (UIKit.button «Open» 340x64 y «Market» 280x50).
	open_btn = HudButton.make("primary", "Open shop", "r6_ico_bell", "open", func(): _open_shop())
	open_btn.set_meta("top", "open")
	open_btn.visible = false
	# --- WORLD: al lado, "Ir al mercado" (o "Volver a la tienda" en el mercado)
	trip_btn = HudButton.make("secondary", "Market", "hud_market", "market", func(): _on_trip_button())
	trip_btn.set_meta("top", "trip")
	trip_btn.visible = false
	top_box = UIKit.vbox(0)
	UIKit.place(top_box, Vector2(0.5, 0), Vector2(-320, GameUI.HUD_TOP), Vector2(640, 0), Control.GROW_DIRECTION_BOTH)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_child(row)
	for b in [open_btn, trip_btn]:
		(b as HudButton).set_tall()   # 66 de alto: a la altura de la barra de la derecha (arriba los dos a HUD_TOP)
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(b)
	ui.root.add_child(top_box)
	# --- end WORLD
	# --- end R6 UI

# ------------------------------------------------------------------ título y comienzo

func _show_title() -> void:
	phase = Phase.TITLE
	if events_ui:
		events_ui.refresh_reminder(false)   # --- R4 EVENTS
	if brew:
		brew.close_now()   # --- R3 BENCH
	if krapido:   # --- R4 RAVEN
		krapido.reset_day()   # --- R4 RAVEN
	if in_market:
		_switch_place(false)   # --- WORLD
	ui.set_gameplay_visible(false)
	ui.hide_dialog()
	open_btn.visible = false
	trip_btn.visible = false   # --- WORLD
	world.set_time(1.0, false)
	world.cat.play("sleep")
	ov.show_title(Game.has_save())

func _to_title() -> void:
	_ev_abort()   # --- R4 EVENTS: si estaba en un evento, vuelve todo a la tienda
	_clear_customer()
	contents.clear()
	brew_ready = {}   # --- R3 BENCH
	ui.set_cauldron([])
	world.cauldron.set_liquid(Color("3b3156"))
	await _fade_to(1.0, 0.5)
	if in_market:
		_switch_place(false)   # --- WORLD
	_show_title()
	await _fade_to(0.0, 0.6)

func _start_new() -> void:
	Game.delete_save()
	Game.new_game_state()
	Sfx.apply_volumes()
	_refresh_all()
	phase = Phase.INTRO
	world.set_time(0.0, true)
	await get_tree().create_timer(0.6).timeout
	for l in INTRO_LINES:
		ui.say(l[0], l[1])
		await ui.dialog_advanced
	ui.hide_dialog()
	_begin_day()

func _continue() -> void:
	if not Game.load_game():
		_start_new()
		return
	Sfx.apply_volumes()
	_refresh_all()
	_begin_day()

func _refresh_all() -> void:
	world.refresh_trophies()   # --- R4 EVENTS
	world.refresh_jars()
	world.refresh_rack()
	world.refresh_upgrades()
	ui.refresh_hud()
	ui.refresh_potions()
	ui.set_cauldron(contents)

func _fade_to(a: float, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, t)
	await tw.finished

# ------------------------------------------------------------------ la mañana

func _begin_day() -> void:
	phase = Phase.MORNING
	Game.reset_today()
	busy = false
	krapido.reset_day()   # --- R4 RAVEN
	_refresh_all()
	ui.set_gameplay_visible(true)
	ui.set_time_label("Morning")
	ui.set_clock_visible(false)   # --- R4 PACE: la mañana no tiene reloj (empieza a correr al abrir)
	if events_ui:
		events_ui.refresh_reminder()   # --- R4 SHIP: la etiqueta del evento, recalculada para hoy (el día del evento decía «Mañana» durante el correo)
	world.set_time(0.0, true)
	world.cat.play("sleep")
	# --- WORLD: empieza el día detrás del mostrador; la puerta lleva al mercado por la mañana
	if in_market:
		_switch_place(false)
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	world.set_station_label("puerta", "Door · to the market")
	EndingScene.place_trophy(world)   # --- R4 RANK: el caldero de oro del Gremio, si ya llegó al puesto 1
	_jar_queue.clear()
	_jar_trip = false   # --- INTEGRATE
	# --- end WORLD
	Game.save_game()
	# --- R3 MAGIC3: una partida vieja tenía pergaminos o papel: Tobías los compró (el oro ya está en la bolsa)
	if Game.legacy_refund > 0:
		ui.toast("Your old scrolls: +%d gold" % Game.legacy_refund, UIKit.GOLD_BRIGHT, 4.0)   # --- R3 MERGE: corto
		Game.legacy_refund = 0
	# --- end R3 MAGIC3
	ui.show_banner("Day %d" % Game.day, "Market day" if Game.pace_market_day() and not Events.today_is_event() else "Morning")   # --- R4 PACE (R4 MERGE: no el día de un evento)
	var got := Game.morning_harvest()
	if got.size() > 0:
		ui.toast("Garden: +2 roots, +2 tears", UIKit.GOOD, 3.0)   # --- R3 BENCH: aviso corto
	_update_top_buttons()   # --- WORLD
	await get_tree().create_timer(1.6).timeout
	if phase != Phase.MORNING:
		return
	# --- STORY: el correo de la mañana (noticias de clientes de días anteriores), antes de los consejos
	_ev_morning_done = false   # --- R4 EVENTS
	await _ev_invite_first()   # --- R4 MERGE: la invitación va primero (pide una decisión); después, el resto del correo
	if phase != Phase.MORNING:
		return
	await _morning_mail()
	if phase != Phase.MORNING:
		return
	# --- end STORY
	# --- R4 EVENTS: la invitación de la mañana (Aceptar / Rechazar) y, si hoy es el día del evento, el evento entero
	var _ev_day: bool = await _ev_morning()
	if _ev_day or phase != Phase.MORNING:
		return
	# --- end R4 EVENTS
	# --- WORLD: ya no se abre el panel del mercado: el mercado es un lugar (se va por la puerta)
	# --- R3 BENCH: consejos de una línea (cada uno sale una vez: día 1 y día 2)
	if Game.day == 1 and not Game.tutorial_done:
		ui.show_tip("Walk with [b]A/D[/b] or a click. Then, [b]Open shop[/b].", 14.0)   # --- R6 UI: el botón se llama así ahora
	elif Game.day == 2 and not in_market:
		ui.show_tip("Every morning: go shopping at the [b]market[/b] (out the door).", 12.0)
	# --- end R3 BENCH
	# --- end WORLD
	# --- R3 MAGIC3: si aún no abrió el grimorio, se lo recuerda desde el día 2 (una línea)
	# --- R3 MERGE: una sola vez, sin pisar el consejo del mercado del día 2 (ese día sale al volver del mercado)
	if Game.day >= 3:
		_grimoire_tip()
	# --- end R3 MAGIC3

## --- R3 MERGE: el recordatorio del grimorio (una vez por partida abierta, mientras no lo haya abierto).
var _grim_tip_shown := false
func _grimoire_tip() -> void:
	if _grim_tip_shown or Game.magic_unlocked or in_market or phase != Phase.MORNING:
		return
	_grim_tip_shown = true
	ui.show_tip("Your teacher's grimoire is glowing in the [b]library[/b].", 12.0)

func _open_shop() -> void:
	if phase != Phase.MORNING:
		return
	if in_market or _trip_busy:
		return   # --- WORLD: primero hay que volver a la tienda
	if ov.is_open():
		ov.close(false)
	open_btn.visible = false
	ui.hide_tip()
	phase = Phase.OPEN
	# --- WORLD
	_update_top_buttons()
	world.set_station_label("puerta", "Door")
	# --- end WORLD
	# --- R4 PACE: la gente del día y a qué hora llega cada uno; el reloj empieza en las 9:00 (ver _pace_open)
	_pace_open()
	# --- end R4 PACE
	krapido.on_open()   # --- R4 RAVEN: los pedidos a domicilio de hoy (solo con la tienda abierta; reloj de PACE)

# ------------------------------------------------------------------ clientes

func _char_name(who: String) -> String:
	return Story.char_name(who)   # --- STORY

## --- R4 PACE: ya no llegan de uno en uno al terminar el anterior: entran solos según el reloj y esperan en la fila
## (bloque R4 PACE: _pace_arrive, _pace_advance, _pace_at_counter, que hace lo que hacía esta función al llegar al
## mostrador). Esto queda para quien lo llame: si la tienda está vacía entra el siguiente, y el primero de la fila pasa.
func _next_customer() -> void:
	if phase != Phase.OPEN:
		return
	if line.is_empty() and _counter_v.is_empty() and not queue.is_empty() and _pace_on and not _pace_closing:
		_pace_arrive()
	_pace_advance()
# --- end R4 PACE

func _talk_request() -> void:
	var who := _char_name(current["who"])
	var choices := []
	if current.get("tutorial", false):
		choices = [["prepare", "Right away!"]]
	else:
		choices = [["prepare", "Brew it"]]
		if not hint_given:
			choices.append(["hint", "A hint?"])   # --- R3 MERGE: botones de dos palabras
		choices.append(["decline", "I can't"])
	var text: String = current["text"]
	# --- STORY: quien vuelve con otro pedido, el aventurero que lo intenta de nuevo, y la presentación de cada cara nueva
	if not current.has("_prefix"):
		current["_prefix"] = ""
		if current.get("followup", false):
			current["_prefix"] = Story.pick(Data.RETURN_VISITS["follow"]) + " "
		elif current.get("retry", false):
			current["_prefix"] = Story.pick(Data.RETURN_VISITS["retry"]) + " "
		if _counter_v.get("grumpy", false):   # --- R4 PACE: esperó mucho en la fila
			current["_prefix"] = Story.pick(PACE_LINES["grumpy"]) + " " + String(current["_prefix"])
	text = current["_prefix"] + text
	var head := who
	if not Game.met.has(current["who"]):
		Game.met[current["who"]] = true
		# --- R3 SHIP: la primera vez, su oficio junto al nombre (era una línea más: «(Greta, panadera)», el nombre dos veces)
		var role := Story.char_title(current["who"])
		head = "%s · %s" % [who, role] if role != "" else who
	# --- end STORY
	# --- R3 MAGIC3: aquí estaba ui.show_rack_tab(...) (PREP): ya no hay pestaña de pergaminos en el estante
	ui.say(head, text, choices)

func _on_customer_clicked() -> void:
	if customer_ready and not ui.dialog_open() and not busy and not ov.is_open():
		if current.get("kind", "") == "return":   # --- STORY
			_talk_return()
		else:
			_talk_request()

func _on_choice(id: String) -> void:
	var who := _char_name(current.get("who", "panadera"))
	match id:
		"prepare", "retry":
			ui.hide_dialog()
			_pace_ordered()   # --- R4 PACE: ya pidió: desde ahora gasta paciencia en el mostrador (barra del ticket)
			ui.order_who = String(current.get("who", ""))   # --- R3 MERGE: el retrato del ticket por su id (viajeros incluidos)
			ui.show_order(who, current["text"], current["hint"] if hint_given else "", Game.order_runes(current))   # --- R3 MAGIC3: las runas del pedido
			if current.get("tutorial", false) and tutorial_step < 0:
				tutorial_step = 0
				# --- R3 BENCH: una línea; en el banco brillan los dos frascos
				ui.show_tip("To the [b]cauldron[/b]: mandrake root + violet mushroom.", 0.0)
				brew.guide(["raiz_mandragora", "hongo_violeta"])
		"hint":
			hint_given = true
			ui.say(who, current["hint"], [["prepare", "Got it"], ["decline", "I can't"]])   # --- R3 MERGE
		"decline":
			var vid := _pace_decline()   # --- R4 PACE: no se cansa mientras se despide (y cuenta como no atendido)
			ui.say(who, Data.DECLINE_LINES.pick_random())
			await ui.dialog_advanced
			if _pace_still(vid):   # --- R4 PACE: el mismo cliente (no el siguiente de la fila)
				_customer_leave()
		"bye":
			_customer_leave()
		# --- STORY: quien volvió con noticias trae otro pedido
		"return_next":
			var f: Dictionary = current.get("follow", {})
			if f.is_empty():
				_customer_leave()
				return
			current = f.duplicate()
			current["followup"] = true
			misses = 0
			hint_given = false
			_talk_request()
		# --- end STORY

func _customer_leave() -> void:
	ui.hide_dialog()
	ui.hide_order()
	customer_ready = false
	served += 1
	# --- R4 PACE: con la tienda abierta el que se va sale por detrás de la fila (su propio paso, sin esperar) y el
	# primero de la fila pasa al mostrador enseguida; la luz del día la lleva el reloj
	if not _counter_v.is_empty():
		var v := _counter_v
		_counter_v = {}
		customer = null
		current = {}
		ui.set_order_patience(-1.0)
		_pace_count_leave(v)
		_pace_exit(v, 1.7)
		Game.save_game()
		if _pace_closing:
			await _show_pending_levels()
			if phase == Phase.OPEN and _counter_v.is_empty():
				_close_day()
			return
		_pace_advance()
		await _show_pending_levels()
		return
	# --- end R4 PACE
	var t := 0.12 + 0.88 * float(served) / float(total_today)
	world.set_time(t, true)
	_update_time_label(t)
	var c := customer
	customer = null
	if is_instance_valid(c):
		world.open_door()
		await c.walk_to(ShopWorld.P_DOOR_FRONT)
		await c.walk_to(ShopWorld.P_DOOR_IN)
		await c.walk_to(ShopWorld.P_OUTSIDE)
		world.close_door()
		c.queue_free()
	Game.save_game()
	await _show_pending_levels()
	await get_tree().create_timer(0.9).timeout
	_next_customer()

func _update_time_label(t: float) -> void:
	var lbl := "Midday"
	if t >= 0.88:
		lbl = "Night"
	elif t >= 0.68:
		lbl = "Dusk"
	elif t >= 0.45:
		lbl = "Afternoon"
	ui.set_time_label(lbl)

func _show_pending_levels() -> void:
	while pending_levels.size() > 0:
		var lv: int = pending_levels.pop_front()
		ov.show_level_up(lv)
		await ov.closed

func _clear_customer() -> void:
	if is_instance_valid(customer):
		customer.queue_free()
	customer = null
	customer_ready = false
	queue.clear()
	_pace_clear()   # --- R4 PACE: la fila, los que salían, el reloj y la puerta
	ui.hide_order()
	ui.hide_dialog()

# ------------------------------------------------------------------ caldero

func _can_interact(allow_dialog := false) -> bool:
	if phase != Phase.MORNING and phase != Phase.OPEN and phase != Phase.EVENT:   # --- R4 EVENTS: también en el evento
		return false
	if ov.is_open() or busy:
		return false
	if ui.dialog_open() and not allow_dialog:
		return false
	return true

func _mix_color(c: Array) -> Color:
	if c.is_empty():
		return Color("3b3156")
	var m := Game.essence_mix(c)
	var col := Color(0, 0, 0)
	var tot := 0.0
	for e in m:
		col += Data.ESSENCES[e]["color"] * float(m[e])
		tot += m[e]
	col = col / tot
	var r := Game.evaluate(c)
	if r.get("potion", "") != "":
		col = col.lerp(Data.POTIONS[r["potion"]]["color"], 0.6)
	return col

# --- WORLD: camina por el carril hasta la estación (walker.gd)
func _go_cauldron() -> void:
	await world.go_station("caldero")

# --- INTEGRATE: espera a que termine de echar los frascos que tocó de lejos (_on_jar_clicked)
func _finish_jar_trip() -> void:
	while _jar_trip and is_instance_valid(customer):
		await get_tree().process_frame
# --- end INTEGRATE

func _go_counter() -> void:
	if _brew_open():
		return   # --- R3 BENCH: con el banco abierto se queda en el caldero
	await world.go_station("mostrador")
# --- end WORLD

func _on_jar_clicked(id: String) -> void:
	if not _can_interact():
		if ui.dialog_open() and phase == Phase.OPEN:
			ui.toast("Answer your customer first.")
		return
	# --- WORLD: el estante está junto al caldero: si está lejos, primero camina hasta allí (los frascos que toque
	# mientras tanto se echan al llegar)
	# --- R3 BENCH: al llegar se abre el banco del caldero y ese frasco se echa allí (open_brew / brew.throw)
	if not world.at_station("caldero"):
		_jar_queue.append(id)
		if _jar_queue.size() > 1:
			return
		_jar_trip = true   # --- INTEGRATE
		var ok: bool = await world.go_station("caldero")
		var q := _jar_queue.duplicate()
		_jar_queue.clear()
		if ok:
			for j in q:
				if not _can_interact():
					break
				_add_jar(j)
				await get_tree().create_timer(0.18).timeout
		_jar_trip = false   # --- INTEGRATE
		return
	_add_jar(id)

# --- R3 BENCH: el banco del caldero ----------------------------------------------------------------------------
# El estado vive aquí (contents, brew_ready); brew_ui.gd lo dibuja y anima, y llama a estas funciones.

## Echa un frasco desde fuera del banco (el estante de la tienda, el bot): abre el banco y lo echa allí.
func _add_jar(id: String) -> void:
	if not _can_interact():
		return
	open_brew()
	brew.throw(id)

## El banco está abierto.
func _brew_open() -> bool:
	return brew != null and brew.is_open()

# --- R4 RAVEN: para Krápido (y la bola): la bola está abierta; en qué parte del día estamos
func _ball_open() -> bool:
	return krapido != null and krapido.ball_open()

func is_open_phase() -> bool:
	return phase == Phase.OPEN

func is_morning_phase() -> bool:
	return phase == Phase.MORNING
# --- end R4 RAVEN

## Abre el banco del caldero (ella ya está en el caldero).
func open_brew() -> void:
	if _brew_open() or not _can_interact() or in_market:
		return
	ui.hide_tooltip()
	world.walker.stop()
	world.alchemist.face(-1)
	brew.open()

func _on_brew_opened() -> void:
	ui.set_bench_mode(true)
	top_box.visible = false
	# --- R3 SHIP: con el banco abierto, ni el letrero de las estaciones ni el aviso de los frascos (la selección 3D de
	# Godot sigue con la última posición del ratón y los encendía detrás del banco); ver ShopWorld.block_hover
	world.block_hover(true)
	ui.hide_tooltip()
	# --- end R3 SHIP

func _on_brew_closed() -> void:
	world.block_hover(false)   # --- R3 SHIP: el letrero vuelve cuando el ratón se mueve sobre la tienda
	ui.set_bench_mode(false)
	top_box.visible = true
	_update_top_buttons()

## Echa un ingrediente: "" si entró; si no, por qué ("lleno", "agotado", "listo": hay una poción sin embotellar,
## "ocupado"). Lo anima brew_ui.gd (BrewUI.throw).
func brew_add(id: String) -> String:
	if not _can_interact():
		return "ocupado"
	if not brew_ready.is_empty():
		return "listo"
	if contents.size() >= Game.cauldron_slots():
		return "lleno"
	if Game.stock.get(id, 0) <= 0:
		return "agotado"
	Game.use_ingredient(id)
	contents.append(id)
	world.bump_jar(id)
	var col := _mix_color(contents)
	world.cauldron.splash(col)
	world.cauldron.set_liquid(col)
	world.cauldron.set_activity(contents.size() / 3.0)
	ui.set_cauldron(contents)
	if tutorial_step == 0 and contents.size() >= 2:
		tutorial_step = 1
		ui.show_tip("The 2 strongest essences decide. Now, [b]Stir[/b].", 0.0)
	return ""

## Saca el ingrediente del hueco i (vuelve al estante). Devuelve su id ("" si no se pudo).
func brew_take(i: int) -> String:
	if not _can_interact() or i < 0 or i >= contents.size() or not brew_ready.is_empty():
		return ""
	var id: String = contents[i]
	contents.remove_at(i)
	Game.return_ingredient(id)
	ui.set_cauldron(contents)
	world.cauldron.set_liquid(_mix_color(contents))
	world.cauldron.set_activity(contents.size() / 3.0)
	return id

func _on_slot(i: int) -> void:
	brew_take(i)

func _on_empty() -> void:
	if not _can_interact() or contents.is_empty() or not brew_ready.is_empty():
		return
	for id in contents:
		Game.return_ingredient(id)
	contents.clear()
	ui.set_cauldron(contents)
	world.cauldron.set_liquid(_mix_color(contents))
	world.cauldron.set_activity(0.0)
	Sfx.play("bubble_2", 0.1, -6.0)

## Un aviso corto: en el banco si está abierto (sobre el caldero); si no, abajo como siempre.
func _bench_say(text: String, col := UIKit.BAD) -> void:
	if _brew_open():
		brew.say(text, col)
	else:
		ui.toast(text, col)

## El minijuego de remover: sobre el caldero del banco si está abierto; si no, el de Overlays. true = perfecto.
func _stir(kind := "potion") -> bool:
	var difficulty := 1.0 + Game.level() * 0.15
	if _brew_open():
		return await brew.stir(difficulty, kind)
	ov.show_stir(difficulty)
	return await ov.stir_done

## «Remover»: el minijuego; la poción cuaja en el caldero y espera a «Embotellar» (brew_ready). Con el banco
## cerrado (el bot, o desde fuera) se embotella sola, como antes.
func _on_brew() -> void:
	if not _can_interact() or not brew_ready.is_empty():
		return
	var r := Game.evaluate(contents)
	if r.get("potion", "") == "":
		_bench_say("Needs another essence")
		return
	if Game.potions_full():
		_bench_say("Shelf full")
		return
	busy = true
	ui.hide_tooltip()
	if not _brew_open():
		await _go_cauldron()
	var perfect: bool = await _stir("potion")
	var pid: String = r["potion"]
	var potency: int = int(r["potency"]) + Game.potency_bonus() + (1 if perfect else 0)
	if perfect:
		Game.stats["perfect"] += 1
	if Game.lucky:
		Game.lucky = false
		potency += 1
		ui.toast("Miga's luck: +1", UIKit.GOLD_BRIGHT)
	var col: Color = Data.POTIONS[pid]["color"]
	world.cauldron.brew_burst(col)
	Sfx.play("brew", 0.03, -2.0)
	world.alchemist.hop(1)
	contents.clear()
	brew_ready = {"potion": pid, "potency": potency, "perfect": perfect}
	world.cauldron.set_liquid(col)
	world.cauldron.set_activity(0.6)
	busy = false
	ui.set_cauldron(contents)
	if _brew_open():
		brew.show_ready()
		if tutorial_step == 1:
			ui.show_tip("Brewed! Now, [b]Bottle[/b] it.", 0.0)
	else:
		await brew_bottle()

## «Embotellar»: la poción removida va al estante (vuela hasta su hueco del HUD si el banco está abierto).
func brew_bottle() -> void:
	if brew_ready.is_empty() or busy:
		return
	var pid: String = brew_ready["potion"]
	var potency: int = int(brew_ready["potency"])
	var _ev_perfect := bool(brew_ready.get("perfect", false))   # --- R4 EVENTS: el jurado del concurso lo mira
	brew_ready = {}
	busy = true
	var is_new := not Game.discovered.has(pid)
	Game.add_potion(pid, potency)
	var idx := Game.potion_index(pid, potency)
	world.cauldron.set_liquid(Color("3b3156"))
	world.cauldron.set_activity(0.1)
	Sfx.play("plop", 0.05, -2.0)
	if _brew_open():
		ui.hold_potion_slot(idx)
		brew.refresh()
		await brew.fly_bottle(pid, ui.potion_slot_center(idx))
		ui.release_potion_slot()
		Sfx.play("click", 0.05, -4.0)
	else:
		world.rack_sprites[mini(idx, world.rack_sprites.size() - 1)].visible = false
		await world.fly(load("res://assets/icons/pot_%s.png" % pid), ShopWorld.CAULDRON_POS + Vector3(0, 1.3, 0.1), world.rack_slot_position(idx), 0.7, 1.0, 0.04)
	world.refresh_rack()
	if is_new:
		ui.show_banner("New recipe!", Data.POTIONS[pid]["name"])
		Sfx.play("sparkle", 0.0, -2.0)
	else:
		ui.toast("%s %s" % [Data.POTIONS[pid]["name"], "★".repeat(Game.stars_for(potency))])
	# --- STORY: la intuición de la alquimista (una corazonada, no una certeza)
	if customer_ready and is_instance_valid(customer) and current.get("kind", "") != "return" and Story.wanted_kind(current) == "potion":
		_intuition_brew(pid, idx)
	# --- end STORY
	# --- R4 EVENTS: en un evento, la poción embotellada sigue sus reglas (la recoge un alumno, se la lleva un caballero...)
	if phase == Phase.EVENT and is_instance_valid(ev_game):
		ev_game.on_bottled(pid, potency, _ev_perfect)
	# --- end R4 EVENTS
	busy = false
	if _brew_open():
		brew.refresh()
	elif customer_ready and not _needs_rune(idx):   # --- R3 MERGE: si al pedido le falta una runa, va al escritorio, no al mostrador
		await _go_counter()
	if tutorial_step == 1:
		tutorial_step = 2
		ui.show_tip("Tap it on the [b]shelf[/b] to hand it over.", 0.0)
# --- end R3 BENCH

# ------------------------------------------------------------------ entregas

func _on_potion(i: int) -> void:
	# --- R4 EVENTS: en un evento, tocar una poción del estante es presentarla (concurso) o dársela a quien la pidió
	if phase == Phase.EVENT:
		if is_instance_valid(ev_game):
			ev_game.on_shelf_click(i)
		return
	# --- end R4 EVENTS
	# --- R3 BENCH: tocar una poción del estante con el banco abierto cierra el banco y la entrega
	if i < 0 or i >= Game.potions.size():
		return
	if krapido.take_potion(i):   # --- R4 RAVEN: Graznido espera en la ventanilla: la poción es para él
		return
	var vid := int(_counter_v.get("id", -1))   # --- R4 PACE: a quién se la iba a dar
	if _brew_open():
		if brew.is_busy() or not customer_ready:
			if not customer_ready:
				_bench_say("No customer", UIKit.TEXT)
			return
		await brew.close()
		if not _pace_still(vid):   # --- R4 PACE: se fue mientras cerraba el banco (no se la da al siguiente)
			return
	# --- end R3 BENCH
	if not _can_interact():
		return
	if not customer_ready or customer == null:
		ui.toast("No customer")   # --- R3 BENCH
		return
	# --- R3 MAGIC3: (se quitó el bloque STORY que rechazaba pociones a quien pedía un pergamino)
	_deliver(i)

func _deliver(i: int) -> void:
	busy = true
	_pace_set_serving(true)   # --- R4 PACE: mientras se la entrega, ya no se cansa
	ui.hide_tooltip()
	var from := world.rack_slot_position(i)
	var p := Game.take_potion(i)
	world.refresh_rack()
	await _go_counter()
	var tex: Texture2D = load("res://assets/icons/pot_%s.png" % p["id"])
	await world.fly(tex, from, world.counter_potion.global_position + Vector3(0, 0.25, 0), 0.5, 0.6, 0.04)
	world.counter_potion.texture = tex
	world.counter_potion.visible = true
	Sfx.play("click", 0.05, -6.0)
	await get_tree().create_timer(0.45).timeout
	world.counter_potion.visible = false
	if not is_instance_valid(customer):
		busy = false
		_pace_set_serving(false)   # --- R4 PACE
		return
	await world.fly(tex, world.counter_potion.global_position + Vector3(0, 0.25, 0), customer.global_position + Vector3(0, 1.0, 0.1), 0.35, 0.3, 0.04)
	_hand_over(_item_of(p))   # --- STORY (R3 MAGIC3: con las runas de su etiqueta)

# --- STORY: la entrega ya no decide en el acto si funcionó: el cliente se lleva la poción y lo cuenta después
# (_hand_over). Correcta o no, se la lleva igual (no puede saber aún si sirve). --- R3 MAGIC3: ya no hay pergaminos.
func _success(p: Dictionary) -> void:
	_hand_over(_item_of(p))

func _wrong(p: Dictionary) -> void:
	_hand_over(_item_of(p))

## La poción que se entrega, con las runas de su etiqueta ("rune", "rune_stars", "rune2", "rune2_stars").
func _item_of(p: Dictionary) -> Dictionary:
	var it := {"kind": "potion", "id": String(p["id"]), "potency": int(p.get("potency", 5))}
	for k in ["rune", "rune_stars", "rune2", "rune2_stars"]:   # --- R3 MAGIC3
		if p.has(k):
			it[k] = p[k]
	return it
# --- end STORY

# --- STORY: entregas, intuición, visitas y el correo de la mañana ------------------------------------------------

var _thought: Label3D   # lo que piensa la alquimista (sobre su cabeza)

## El cliente recibe lo que pidió (una poción o un pergamino). Solo puede juzgar lo que ve, huele y lee en la
## etiqueta: lo paga y se lo lleva. Si funcionó o no se sabrá después, por carta o cuando vuelva (Story.make_outcome);
## con esa noticia llegan la propina y el renombre. item: {"kind": "potion", "id", "potency"} y sus runas ("rune"...).
func _hand_over(item: Dictionary) -> void:
	var who := _char_name(current["who"])
	var ok := String(item["id"]) == Story.wanted(current)
	var price := Story.price_of(item, current)   # --- R3 MAGIC3: más lo que pagan las runas pedidas
	var rune_extra := Game.rune_bonus(item, current)   # --- R3 MAGIC3
	var stars := Game.stars_for(int(item.get("potency", 5)))
	Game.add_gold(price)
	var speed_tip := _pace_handed(price)   # --- R4 PACE: atendido; si aún le sobraba paciencia, propina por rapidez
	if speed_tip > 0:
		Game.add_gold(speed_tip)   # --- R4 PACE
	Game.stats["sold"] += 1
	Game.today["sold"] += 1
	Game.schedule_outcome(Story.make_outcome(current, item, ok, price, misses))
	Sfx.play("coin", 0.05, -4.0)
	ui.fly_coins(world.screen_pos(customer.global_position + Vector3(0, 1.4, 0)), clampi((price + speed_tip) / 4, 3, 9))   # --- R4 PACE
	if ok:
		# la intuición: brilla en sus manos, Miga ronronea, y ella tiene un buen presentimiento
		customer.hop(1)
		customer.emote("sparkle" if stars == 3 else "note", 1.8)
		var col := Color(1.0, 0.85, 0.5)
		if Data.POTIONS.has(item["id"]):
			col = Data.POTIONS[item["id"]]["color"]   # --- R3 MAGIC3: (sin el color de los hechizos: ya no hay pergaminos)
		world.spawn_sparkles(customer.global_position + Vector3(0, 1.05, 0.2), Color(col.r * 1.6, col.g * 1.6, col.b * 1.6), 14)
		_purr()
		_think(Story.pick(Data.INTUITION["give_match"]))
	else:
		customer.emote("question", 1.8)   # lee la etiqueta: no es lo que imaginaba (pero confía en ella)
	# --- R3 SHIP: el recordatorio solo el día 1 (en la entrega del tutorial ya lo dice el consejo de arriba)
	var note := "" if (Game.day > 1 or tutorial_step == 2) else "   [color=#a99fbf][i]You'll hear how it went.[/i][/color]"
	ui.hide_order()
	var bye := "Safe travels!" if current.get("kind", "") == "hero" else "Good luck!"
	var paid := "+%d gold" % price
	if rune_extra > 0:
		paid += "  [color=#c9b6ff](rune +%d)[/color]" % rune_extra   # --- R3 MAGIC3
	if speed_tip > 0:   # --- R4 PACE: la propina por rapidez, con el reloj de arena
		paid += "  [img=26]res://assets/icons/emote_hourglass_4.png[/img][color=#9eea9f]+%d[/color]" % speed_tip
	ui.say(who, "%s\n[color=#ffd987]%s[/color]%s" % [Story.reaction(current, item, ok), paid, note], [["bye", bye]])
	busy = false
	if current.get("tutorial", false):
		Game.tutorial_done = true   # --- R4 PACE: entregado el pedido del tutorial, el reloj empieza a correr
	if tutorial_step == 2:
		tutorial_step = 3
		Game.tutorial_done = true
		ui.show_tip("You'll hear how it went tomorrow. Stuck? Ask for a [b]hint[/b].", 14.0)   # --- R3 BENCH
		get_tree().create_timer(16.0).timeout.connect(func():
			if tutorial_step == 3:
				ui.hide_tip())

## --- R3 MAGIC3: la intuición al encantar una poción con un cliente esperando: si ya es lo que pidió (poción y runas),
## Miga ronronea y ella lo piensa. Lo llama el grimorio al cerrar el libro.
func intuition_after_enchant(p: Dictionary) -> void:
	if customer_ready and is_instance_valid(customer) and current.get("kind", "") != "return":
		if String(p.get("id", "")) == Story.wanted(current) and Game.next_rune_for(p, current) == "":
			_purr()
			_think(Story.pick(Data.INTUITION["brew_match"]).replace("{n}", _char_name(current["who"])))

## Al terminar una poción con un cliente esperando: si es lo que pidió, brilla en el estante, Miga ronronea y ella lo
## piensa en voz baja. Si no, una duda. Es una corazonada, no una certeza: la respuesta llega con las noticias.
func _intuition_brew(pid: String, idx: int) -> void:
	var cname := _char_name(current["who"])
	if pid == Story.wanted(current):
		_purr()
		_glow_rack(idx)
		# --- R3 MAGIC3: si el pedido lleva runas, ella piensa en la que falta (se inscribe en el grimorio)
		var need: Array = Game.order_runes(current)
		if not need.is_empty():
			# --- R3 MERGE: con el banco abierto la idea no se ve en la tienda (la tapa el banco): la dice el banco
			# --- R3 SHIP: y entonces no la piensa además (salía dos veces: el banco y un aviso)
			if _brew_open():
				brew.say("Now, the %s rune" % Story.rune_name(need[0]), UIKit.GOLD_BRIGHT, 2.4)
			else:
				_think("Now, the %s rune…" % Story.rune_name(need[0]))
			if Game.magic_stats["runes"] == 0:
				ui.show_tip("Add the rune at the library [b]grimoire[/b].")   # --- R3 MERGE: corto
			return
		# --- end R3 MAGIC3
		_think(Story.pick(Data.INTUITION["brew_match"]).replace("{n}", cname))
	else:
		_think(Story.pick(Data.INTUITION["brew_unsure"]).replace("{n}", cname), false)

## --- R3 MERGE: la poción del estante idx es la del pedido del cliente que espera y aún le falta una runa.
func _needs_rune(idx: int) -> bool:
	if idx < 0 or idx >= Game.potions.size() or not customer_ready or current.get("kind", "") == "return":
		return false
	var p: Dictionary = Game.potions[idx]
	return String(p.get("id", "")) == Story.wanted(current) and Game.next_rune_for(p, current) != ""

## Un brillo suave en el frasco del estante.
func _glow_rack(idx: int) -> void:
	if world.rack_sprites.is_empty():
		return
	var s: Sprite3D = world.rack_sprites[clampi(idx, 0, world.rack_sprites.size() - 1)]
	world.spawn_sparkles(s.global_position + Vector3(0, 0.3, 0.1), Color(1.7, 1.5, 0.9), 14)
	var tw := create_tween()
	for i in 3:
		tw.tween_property(s, "modulate", Color(1.8, 1.6, 1.15), 0.3)
		tw.tween_property(s, "modulate", Color.WHITE, 0.45)

## Miga ronronea (buena señal).
func _purr() -> void:
	if in_market or not is_instance_valid(world.cat):
		return
	world.cat.play("happy")
	Sfx.play("purr", 0.05, -3.0)
	world.spawn_hearts(world.cat.global_position + Vector3(0, 0.7, 0.1))
	get_tree().create_timer(2.6).timeout.connect(func():
		if is_instance_valid(world.cat):
			world.cat.play("sit" if phase == Phase.CLOSING else "sleep"))

## Lo que piensa la alquimista: unas palabras en cursiva sobre su cabeza, que suben y se desvanecen.
func _think(text: String, good := true) -> void:
	if in_market or text == "" or not is_instance_valid(world.alchemist):
		return
	# --- R3 SHIP: con el banco del caldero abierto el texto 3D quedaba borroso detrás del banco: va como aviso
	if _brew_open():
		ui.toast(text, Color(1.0, 0.9, 0.62) if good else Color(0.84, 0.8, 0.95), 2.8)
		return
	# --- end R3 SHIP
	if is_instance_valid(_thought):
		_thought.queue_free()
	UIKit.load_fonts()
	var l := Label3D.new()
	l.text = text
	l.font = UIKit.font_italic
	l.font_size = 44
	l.pixel_size = 0.005
	l.outline_size = 12
	l.outline_modulate = Color(0.08, 0.05, 0.12)
	l.modulate = Color(1.0, 0.9, 0.62) if good else Color(0.84, 0.8, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 9
	l.shaded = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.alchemist.add_child(l)
	_thought = l
	# justo sobre su cabeza (top_height: la parte visible del sprite, si actor.gd la tiene)
	var head: float = world.alchemist.call("top_height") if world.alchemist.has_method("top_height") else world.alchemist.height()
	var y0 := head + 0.12
	l.position = Vector3(0, y0, 0.1)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.25)
	tw.tween_property(l, "position:y", y0 + 0.2, 3.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(3.1)
	tw.chain().tween_callback(l.queue_free)

## Quien vuelve a la tienda a contar cómo le fue: la noticia, lo que trae (propina, renombre, regalos, una página
## del diario) y, a veces, otro pedido.
func _talk_return() -> void:
	var o: Dictionary = current["outcome"]
	var who := _char_name(current["who"])
	if not current.has("result"):
		_pace_told()   # --- R4 PACE: ya contó sus noticias (atendido; su espera termina aquí)
		var res := Game.resolve_visit(int(o.get("id", -1)))
		current["result"] = res
		current["visit_text"] = Story.visit_text(o, res)
		if is_instance_valid(customer):
			customer.hop(2)
			customer.emote("heart", 2.0)
			world.spawn_hearts(customer.global_position + Vector3(0, 1.9, 0.1))
			var gold_in := int(res.get("tip", 0)) + int(res.get("gift_gold", 0))
			if gold_in > 0:
				Sfx.play("coin", 0.05, -4.0)
				ui.fly_coins(world.screen_pos(customer.global_position + Vector3(0, 1.4, 0)), clampi(gold_in / 3, 3, 10))
		if res.get("journal", false):
			ui.toast("New page in the Journal", UIKit.GOLD_BRIGHT, 3.0)   # --- R3 BENCH
		Game.save_game()
	var line := Story.reward_line(current["result"])
	var text: String = current["visit_text"] + ("\n" + line if line != "" else "")
	if current.has("follow"):
		ui.say(who, text, [["return_next", Story.pick(Data.RETURN_VISITS["next"])]])
	else:
		ui.say(who, text, [["bye", Story.pick(Data.RETURN_VISITS["bye"])]])

## Por la mañana, antes de abrir: las cartas que trajo Pip (noticias de clientes de días anteriores) y los rumores
## del pueblo (quién llegó hoy). Aplica lo que traen las cartas y las muestra en el panel "Correo de la mañana".
func _morning_mail() -> void:
	var letters := []
	for o in Game.take_due_letters():
		letters.append(Story.letter(o, Game.resolve_outcome(o)))
	var rumors := Story.rumors_today()
	var rank_news := Ranking.has_morning_news()   # --- R4 RANK: la línea del Escalafón (cada mañana tras un día jugado)
	if letters.is_empty() and rumors.is_empty() and not rank_news:   # --- R4 RANK
		return
	Game.save_game()
	var first := not Game.mail_seen and not letters.is_empty()
	if not letters.is_empty():
		Game.mail_seen = true
	ov.show_mail(letters, rumors, first)
	while ov.current == "mail":
		await get_tree().process_frame
	# --- R4 RANK: la primera línea del Escalafón hace brillar su botón; cada 5 días llega la Gaceta del Gremio
	if rank_news and Ranking.hist.size() == 1:
		ui.pulse_rank_button()
	if Ranking.gaceta_due() and ov.current == "" and phase == Phase.MORNING:
		ov.show_gaceta()
		while ov.current == "gaceta":
			await get_tree().process_frame
		Ranking.mark_gaceta_read()
	# --- end R4 RANK
	await _show_pending_levels()

## Para las pruebas automáticas: qué elección es cada botón (despedida, visita, pedido).
## --- R5 EN-UI: game_ui.say() guarda en cada botón su id ("prepare", "hint", "decline", "bye", "return_next"): el bot lo
## lee de ahí y ya no compara textos (que ahora están en inglés y cambian con los datos). Sin id: "prepare".
func _bot_choice(b: Control) -> String:
	if b == null or not b.has_meta("choice"):
		return "prepare"
	var id := String(b.get_meta("choice"))
	return id if id in ["bye", "return_next"] else "prepare"   # (como antes: lo demás se contesta con «prepare»)
# --- end R5 EN-UI
# --- end STORY

# ------------------------------------------------------------------ fin del día

func _close_day() -> void:
	_pace_end()   # --- R4 PACE: el reloj se detiene, la fila queda vacía y se anota el boca a boca de mañana
	krapido.on_close()   # --- R4 RAVEN: los pedidos pendientes se cancelan sin castigo
	# --- R3 BENCH: se cierra el banco (la poción removida, si la hay, se embotella)
	if not brew_ready.is_empty():
		var br := brew_ready
		brew_ready = {}
		Game.add_potion(br["potion"], int(br["potency"]))
		world.cauldron.set_liquid(Color("3b3156"))
	brew.close_now()
	# --- end R3 BENCH
	phase = Phase.CLOSING
	ui.hide_order()
	ui.toast("Shop closed", UIKit.GOLD_BRIGHT)   # --- R3 BENCH
	world.set_time(1.0, true)
	ui.set_time_label("Night")
	await _go_counter()
	world.cat.play("sit")
	await get_tree().create_timer(2.2).timeout
	await _show_pending_levels()
	Ranking.commit_day()   # --- R4 RANK: el día suma en el Escalafón (una vez; la hoja de la noche muestra el puesto)
	Game.save_game()
	ov.show_summary(Game.day, Game.today)

func _sleep() -> void:
	Ranking.commit_day()   # --- R4 RANK: por si el día no pasó por _close_day (un evento): suma una sola vez
	await _fade_to(1.0, 0.8)
	# --- R4 RANK: llegó al puesto 1: el final (fiesta en la tienda y créditos) y luego la mañana siguiente
	if Ranking.ending_due():
		await _play_ending()
	# --- end R4 RANK
	Game.day += 1
	world.set_time(0.0, false)
	for id in contents:
		Game.return_ingredient(id)
	contents.clear()
	world.cauldron.set_liquid(Color("3b3156"), false)
	await get_tree().create_timer(0.4).timeout
	_begin_day()
	await _fade_to(0.0, 0.9)

# ------------------------------------------------------------------ gata, menú, mejoras

func _on_cat_clicked() -> void:
	if phase == Phase.TITLE or ov.is_open():
		return
	world.cat.play("happy")
	world.spawn_hearts(world.cat.global_position + Vector3(0, 0.7, 0.1))
	Sfx.play("purr", 0.05, 0.0)
	if Game.cat_petted_day < Game.day:
		Game.cat_petted_day = Game.day
		if Game.has_upgrade("cojin"):
			Game.lucky = true
			ui.toast("Miga purrs: +1 to your next potion", UIKit.GOLD_BRIGHT, 3.0)   # --- R3 BENCH
		else:
			ui.toast("Miga purrs happily", UIKit.TEXT, 2.4)   # --- R3 BENCH
	get_tree().create_timer(2.6).timeout.connect(func():
		if phase != Phase.CLOSING:
			world.cat.play("sleep")
		else:
			world.cat.play("sit"))

func _on_menu(id: String) -> void:
	if ov.is_open() or phase == Phase.TITLE or phase == Phase.INTRO:
		return
	ui.hide_tooltip()
	match id:
		"book":
			ov.show_book()
		"journal":
			ov.show_journal()
		"market":
			if phase == Phase.EVENT:   # --- R4 EVENTS: hoy no hay mercado (el caldero usa la despensa del evento)
				ui.toast("No market today")
				return
			# --- WORLD: por la mañana el mercado es un lugar; durante el día, un encargo (Pip trae los ingredientes)
			if phase == Phase.MORNING:
				if in_market:
					ui.toast("Tap a stall")   # --- R3 BENCH
				else:
					_go_market()
			else:
				ov.show_market("day")
			# --- end WORLD
		"settings":
			ov.show_settings()
		"rank":
			ov.show_ranking()   # --- R4 RANK: el tablón del Gremio

func _on_overlay_closed(_id: String) -> void:
	pass

func _on_upgrades_changed() -> void:
	ui.refresh_potions()
	ui.set_cauldron(contents)
	for id in Data.UPGRADE_ORDER:
		if Game.has_upgrade(id) and world.upgrade_nodes.has(id) and not world.upgrade_nodes[id][0].visible:
			world.reveal_upgrade(id)
	world.refresh_upgrades()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and (phase == Phase.MORNING or phase == Phase.OPEN or phase == Phase.CLOSING):
		if not brew_ready.is_empty():   # --- R3 BENCH: la poción removida sin embotellar no se pierde
			Game.add_potion(brew_ready["potion"], int(brew_ready["potency"]))
			brew_ready = {}
		for id in contents:
			Game.return_ingredient(id)
		contents.clear()
		Game.save_game()

func _unhandled_input(ev: InputEvent) -> void:
	if not _booted:   # --- BOOT: todavía armándose
		return
	# --- R6 UI: E / Espacio hacen lo que dice el aviso de acción (PromptBrain); O abre la tienda; M va al mercado (o
	# vuelve, o de día abre el encargo); Tab abre el estante con el banco abierto
	if ev is InputEventKey and ev.pressed and not ev.echo and _r6_key(ev):
		get_viewport().set_input_as_handled()
		return
	# --- end R6 UI
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE and not ov.is_open() and phase != Phase.TITLE and phase != Phase.INTRO:
			ov.show_settings()
		elif ev.keycode == KEY_R and _can_interact(true):
			ov.show_book()
		elif ev.keycode == KEY_J and _can_interact(true):
			ov.show_journal()
		elif ev.keycode == KEY_E and phase == Phase.EVENT:   # --- R4 EVENTS: E abre el caldero del evento
			_ev_open_bench()
		elif ev.keycode == KEY_G and _can_interact(true):   # --- R4 RANK: G = el Escalafón del Gremio
			ov.show_ranking()
			get_viewport().set_input_as_handled()
		# --- WORLD: E usa la estación donde está
		elif ev.keycode == KEY_E and _can_walk():
			if in_market:
				if market.walker.current != "":
					market.use_station(market.walker.current)
			elif world.current_station() != "":
				world.use_station(world.current_station())
		# --- end WORLD

# --- WORLD: caminar, estaciones y el viaje al mercado ----------------------------------------------------

## Si el jugador puede mover a la alquimista ahora (teclas, cruceta, clic en el suelo).
func _can_walk() -> bool:
	if _trip_busy or (phase != Phase.MORNING and phase != Phase.OPEN):
		return false
	return not ov.is_open() and not busy and not ui.dialog_open() and not _brew_open() and not _ball_open() and not ui.picker_open()   # --- R3 BENCH (R4 RAVEN: la bola) (R6 UI: ni eligiendo en el estante)

## Si se puede usar una estación de la tienda (ShopWorld la llama antes de caminar hasta ella).
func _can_use_station(id: String) -> bool:
	if in_market or _trip_busy or not _can_interact() or _brew_open() or _ball_open():   # --- R3 BENCH (R4 RAVEN: la bola)
		return false
	if id == "puerta" and phase == Phase.OPEN:
		ui.toast("Market: tomorrow")   # --- R3 BENCH
		return false
	return true

## La alquimista llegó a una estación que el jugador tocó (o con E).
func _on_station_clicked(id: String) -> void:
	match id:
		"biblioteca":
			_open_grimoire()
		"caldero":
			open_brew()   # --- R3 BENCH: el banco del caldero
		"mostrador":
			_on_customer_clicked()
		"puerta":
			if phase == Phase.MORNING:
				_go_market()
			elif phase == Phase.OPEN:
				ui.toast("Market: tomorrow")   # --- R3 BENCH
		"ventanilla":   # --- R4 RAVEN: la bola de cristal de Krápido
			krapido.open_ball()

## MAGIC: el grimorio del escritorio de la biblioteca (ella ya está frente al escritorio).
func _open_grimoire() -> void:
	# --- MAGIC
	if grimoire:
		grimoire.open()
	# --- end MAGIC

func _on_trip_button() -> void:
	if in_market:
		_leave_market()
	else:
		_go_market()

func _update_top_buttons() -> void:
	var morning := phase == Phase.MORNING
	open_btn.visible = morning and not in_market
	trip_btn.visible = morning
	# --- R6 UI: en el mercado, «Back to shop» con la casita; en la tienda, «Market» con la cesta (los dos con la tecla M)
	(trip_btn as HudButton).set_label("Back to shop" if in_market else "Market")
	(trip_btn as HudButton).set_icon_name("r6_ico_home" if in_market else "hud_market")
	open_btn.disabled = _trip_busy
	trip_btn.disabled = _trip_busy
	# --- end R6 UI

## Muestra u oculta un escenario 3D (la tienda o el mercado) y lo pausa: sus clics, animaciones y sonidos.
func _set_place_on(place: Node3D, on: bool) -> void:
	place.visible = on
	place.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

## Cambia de escenario al instante (los fundidos los hacen _go_market y _leave_market).
func _switch_place(to_market: bool, intro := true) -> void:
	brew.close_now()   # --- R3 BENCH
	krapido.ball.close_now()   # --- R4 RAVEN
	in_market = to_market
	_set_place_on(world, not to_market)
	_set_place_on(market, to_market)
	ui.hide_tooltip()
	if to_market:
		market.enter(intro)
	else:
		market.leave()
		world.camera.current = true
		world.walker.teleport(ShopWorld.STATIONS["puerta"]["x"], -1)
		world.snap_camera()
	ui.set_shop_panels_visible(not to_market)
	Sfx.set_place("market" if to_market else "shop")
	_update_top_buttons()

## Por la mañana: camina hasta la puerta, sale y aparece en la calle del mercado.
func _go_market() -> void:
	if phase != Phase.MORNING or in_market or _trip_busy or market == null:
		return
	if ov.is_open() or busy:
		return
	if not world.at_station("puerta") or absf(world.walker.x - float(ShopWorld.STATIONS["puerta"]["x"])) > 0.3:
		if not await world.go_station("puerta"):
			return
	if phase != Phase.MORNING or in_market or _trip_busy:
		return
	_trip_busy = true
	ui.hide_tip()
	ui.hide_tooltip()
	world.open_door()
	world.walker.frozen = true
	await world.alchemist.walk_to(ShopWorld.P_DOOR_IN, 2.2)
	await _fade_to(1.0, 0.45)
	# --- BOOT: si el precalentamiento de después del título (BootWarm) todavía no pasó por el mercado, lo hace ahora, en
	# negro y repartido en cuadros (un negro un poco más largo la primera vez en vez de un tirón con el mercado a la vista)
	if is_instance_valid(boot_warm) and not boot_warm.market_done:
		await boot_warm.warm_market()
	# --- end BOOT
	world.close_door()
	world.walker.frozen = false
	_switch_place(true)
	await get_tree().create_timer(0.15).timeout
	await _fade_to(0.0, 0.6)
	ui.show_banner("Market Square")   # --- R3 SHIP: sin el subtítulo («Mañana de mercado» repetía lo mismo)
	if not _market_tip_shown:
		_market_tip_shown = true
		ui.show_tip("Tap a [b]stall[/b] to buy.", 10.0)   # --- R3 BENCH
	_trip_busy = false

## Vuelve a la tienda: camina hasta su puerta en la calle, fundido, y entra por la puerta de la tienda.
func _leave_market() -> void:
	if not in_market or _trip_busy:
		return
	if ov.is_open():
		ov.close(false)
	ui.hide_tip()
	if not market.walker.at_station("tienda"):
		if not await market.go_station("tienda"):
			return
	if not in_market or _trip_busy:
		return
	_trip_busy = true
	market.enter_shop_door()
	await _fade_to(1.0, 0.45)
	_switch_place(false)
	world.open_door()
	world.walker.frozen = true
	world.alchemist.position = ShopWorld.P_DOOR_IN
	world.alchemist.face(-1)
	world.snap_camera()
	await _fade_to(0.0, 0.5)
	await world.alchemist.walk_to(world.walker.point(float(ShopWorld.STATIONS["puerta"]["x"])), 2.2)
	world.walker.frozen = false
	world.walker.teleport(float(ShopWorld.STATIONS["puerta"]["x"]), -1)
	world.close_door()
	_trip_busy = false
	_update_top_buttons()
	if Game.day >= 2:
		_grimoire_tip()   # --- R3 MERGE: de vuelta del mercado, el recordatorio del grimorio

## En el mercado: llegó a un puesto (abre el panel de ese vendedor) o a la puerta de la tienda (vuelve).
func _on_market_station(id: String) -> void:
	if id == "tienda":
		_leave_market()
		return
	if phase != Phase.MORNING or ov.is_open() or _trip_busy:
		return
	market.greet(id)
	ov.show_market("morning", id)

## Prueba rápida del viaje al mercado (--demo=trip): sale, compra en un puesto y vuelve.
func _trip_check() -> void:
	await get_tree().create_timer(0.5).timeout
	await _go_market()
	print("TRIP mercado=", in_market, " cámara=", market.camera.current)
	await get_tree().create_timer(2.5).timeout
	await market.use_station("ilse")
	await get_tree().create_timer(0.6).timeout
	print("TRIP panel=", ov.current, " puesto=", market.walker.current)
	ov.close()
	await _leave_market()
	print("TRIP tienda=", not in_market, " estación=", world.current_station(), " cámara=", world.camera.current)
	get_tree().quit()
# --- end WORLD

# --- PREP: precalentar la biblioteca y el mercado ---------------------------------------------------------------
# --- BOOT: antes, al arrancar y en negro, la cámara de la tienda miraba la biblioteca, el mercado se dibujaba en tres
# puntos de la calle y se lanzaban los efectos (_warm_shop_effects), las letras de los eventos (_warm_event_text) y las
# texturas de los papeles (_preload_ui_art), todo ANTES del título y en pocos cuadros enormes. Ahora eso lo hace
# BootWarm (scripts/boot_warm.gd) después del título, repartido. Esta función queda para las demos de medición
# (--demo=perf_event, m6_fontprobe, m6_juryprobe): hace lo mismo que el juego y espera a que termine.
func _warm_places() -> void:
	fade.color.a = 1.0
	if not is_instance_valid(boot_warm):
		boot_warm = BootWarm.start(self)
	await boot_warm.wait_done(300.0)
# --- end BOOT

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# --- BOOT: _warm_shop_effects, _warm_event_text y _preload_ui_art (R6 PERF / R6 MERGE) se mudaron a BootWarm
# (scripts/boot_warm.gd: _step_shop_effects, _step_text, _step_ui_art), que los hace después del título.
# --- end PREP

# --- R6 PERF: las caras recortadas del ticket del pedido y de la bola de cristal. game_ui y ball_ui buscan la fila de
# la cabeza leyendo la textura de vuelta de la GPU (get_image) la primera vez que ven a cada personaje: en la web es un
# readPixels que espera a la tarjeta gráfica (un tirón cuando llega cada cliente nuevo). SpriteTops.HEAD tiene esas
# filas precalculadas con la misma regla: se cargan en sus cachés al arrancar y ya no leen nada.
func _perf_prefill_faces() -> void:
	for holder in [ui, krapido.ball if krapido else null]:
		if holder == null:
			continue
		for key in ["_portrait_top", "_head_cache"]:
			var d = holder.get(key)
			if d is Dictionary:
				for sid in SpriteTops.HEAD:
					if not d.has(sid):
						d[sid] = int(SpriteTops.HEAD[sid])
# --- end R6 PERF

# --- R6 PERF: el desenfoque de arriba y abajo (shaders/hd2d_post.gdshader) por escenario. La fuerza del desenfoque es la
# misma de siempre; lo que cambia es cuánto de la pantalla cubre: cada escenario dice dónde va su banda nítida y qué
# tan rápido se pasa a borroso (post_params() en ShopWorld, MarketWorld y EventScenes; el mercado es el que más se
# abre, porque la gente camina abajo). main.gd mira la cámara activa en cada cuadro y solo cambia los parámetros
# cuando cambia la cámara (la tienda, el mercado, un evento, el final). --post=centro,mitad,caída[,lod] los fuerza
# (para probar valores).
const POST_DEFAULT := {"focus_center": 0.46, "focus_half": 0.22, "focus_falloff": 0.30, "max_lod": 2.6}   # el de antes
var _post_cam: Camera3D
var _post_force := {}

func _post_follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == _post_cam or post == null:
		return
	_post_cam = cam
	var p: Dictionary = POST_DEFAULT
	var n: Node = cam
	while n != null:
		if n.has_method("post_params"):
			p = n.call("post_params")
			break
		n = n.get_parent()
	apply_post(p)

## Pone los parámetros del desenfoque (los que falten quedan como estaban).
func apply_post(p: Dictionary) -> void:
	var sm := post.material as ShaderMaterial
	if sm == null:
		return
	for k in p:
		sm.set_shader_parameter(k, p[k])
	for k in _post_force:
		sm.set_shader_parameter(k, _post_force[k])
# --- end R6 PERF

# --- R3 MAGIC3: la tinta del caldero, las capturas de la magia y la prueba rápida ------------------------------------
# (Ya no hay pergaminos: las runas se inscriben en la etiqueta de las pociones del estante, en el grimorio del
# escritorio de la biblioteca, y se entregan con la poción como siempre: _deliver -> _hand_over.)

## «Tinta» en el caldero: la mezcla se vuelve tinta de su esencia más fuerte (Game.ink_for_mix). Se remueve como una
## poción: removido perfecto = un frasco más.
func _on_brew_ink() -> void:
	if not _can_interact():
		return
	var r := Game.ink_for_mix(contents)
	if r.is_empty():
		_bench_say("Not enough ingredients")   # --- R3 MERGE: en el banco si está abierto, y corto
		return
	busy = true
	ui.hide_tooltip()
	await _go_cauldron()
	var perfect: bool = await _stir("ink")   # --- R3 BENCH: en el banco del caldero si está abierto
	var ink: String = r["ink"]
	var qty: int = int(r["qty"]) + (1 if perfect else 0)
	var col: Color = Data.INKS[ink]["color"]
	world.cauldron.brew_burst(col)
	Sfx.play("brew", 0.03, -2.0)
	world.alchemist.hop(1)
	contents.clear()
	ui.set_cauldron(contents)
	world.cauldron.set_liquid(Color("3b3156"))
	world.cauldron.set_activity(0.1)
	await get_tree().create_timer(0.35).timeout
	await world.fly(load("res://assets/icons/%s.png" % ink), ShopWorld.CAULDRON_POS + Vector3(0, 1.3, 0.1), world.alchemist.global_position + Vector3(0, 1.2, 0.1), 0.6, 0.8, 0.04)
	Game.add_item(ink, qty)
	Game.magic_stats["inks"] += qty
	ui.toast("%s ×%d" % [Data.INKS[ink]["name"], qty], UIKit.GOLD_BRIGHT, 2.6)
	if customer_ready:
		await _go_counter()
	busy = false

## Estado de las capturas de la magia: el grimorio abierto, varias runas aprendidas, tintas y una poción encantada.
func _magic_state() -> void:
	Game.renombre = 34
	Game.hero_progress["lirien"] = 1
	Game.unlock_magic()
	Game.items = {"tinta_brasa": 2, "tinta_escarcha": 1, "tinta_savia": 3, "tinta_umbra": 2, "tinta_alba": 2, "pagina_dulzor": 1}
	Game.new_rune_pages()
	for id in ["prisa", "dulzor", "calma"]:
		Game.mark_page_read(id)
	Game.potions = [{"id": "sueno_profundo", "potency": 7}, {"id": "sueno_profundo", "potency": 5, "rune": "calma", "rune_stars": 3},
		{"id": "balsamo_helado", "potency": 4}, {"id": "ojo_nocturno", "potency": 6, "rune": "prisa", "rune_stars": 2}]
	Game.sort_potions()
	Game.potions_changed.emit()
	Game.magic_changed.emit()
	ui.refresh_hud()

## Un cliente esperando en el mostrador con un pedido con runas (para las capturas y la prueba).
func _magic_customer(who: String, runes: Array) -> void:
	for q in Data.RUNE_REQUESTS:
		if q["who"] == who and q["runes"] == runes and current.is_empty():
			current = q.duplicate()
	current["kind"] = "villager"
	Game.met[who] = true
	customer = Actor.new()
	world.add_child(customer)
	customer.setup(Story.sprite_id(who))
	customer.global_position = ShopWorld.P_CUSTOMER
	customer.face(-1)
	customer_ready = true
	hint_given = true
	ui.show_order(_char_name(who), current["text"], current["hint"], Game.order_runes(current))

## Capturas: --demo=grimoire (el libro de runas, hojeando), --demo=enchant (encantando una poción: la runa a medio
## trazar en la etiqueta), --demo=ticket (el mostrador: un pedido con runa y el estante con pociones encantadas).
## --demo=magictest: prueba rápida (aprender, preparar, encantar, entregar, la carta) y sale. --demo=oldsave: carga una
## partida de antes (con pergaminos) y sale.
func _magic_demo(name: String) -> void:
	if name == "magictest":
		_magic_test()
		return
	if name == "oldsave":
		_old_save_test()
		return
	if name == "firstbook":   # la primera vez: la nota de la maestra sobre el libro
		phase = Phase.MORNING
		world.walker.teleport(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
		world.snap_camera()
		await get_tree().create_timer(0.3).timeout
		grimoire.open()
		return
	_magic_state()
	match name:
		"grimoire", "enchant", "enchanted":
			world.walker.teleport(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
			world.snap_camera()
			if name != "grimoire":
				_magic_customer("lupo", ["calma"])
				world.walker.teleport(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
				world.snap_camera()
			await get_tree().create_timer(0.3).timeout
			if name == "grimoire":
				grimoire.show_book("calma")
			else:
				grimoire.demo_auto = 0.58 if name == "enchant" else 1.0
				grimoire.show_book("calma", "enchant", Game.potion_index("sueno_profundo", 7))
				await get_tree().create_timer(0.5).timeout
				grimoire.pick_ink("tinta_umbra")
				await get_tree().create_timer(0.3).timeout
				grimoire.start_trace()
		"ticket":
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
			_magic_customer("lupo", ["calma"])

## --demo=magictest: aprende una página, prepara, encanta con un trazo perfecto, entrega y lee la carta de la mañana.
func _magic_test() -> void:
	Engine.time_scale = 4.0
	Game.delete_save()
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 2
	Game.gold = 60
	for id in Data.INGREDIENT_ORDER:
		Game.stock[id] = 4 if Game.ingredient_unlocked(id) else 0
	_refresh_all()
	phase = Phase.MORNING
	# 1) aprender: el grimorio (la nota de la maestra trae la runa de Prisa) y la página de Tobías (Dulzor)
	world.walker.teleport(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
	world.snap_camera()
	grimoire.open()
	await get_tree().create_timer(0.6).timeout
	print("MAGIC grimorio: panel=", ov.current, " abierto=", Game.magic_unlocked, " runas=", Game.known_runes(), " brasa=", Game.item_count("tinta_brasa"), " nota=", grimoire.note_visible())
	grimoire.dismiss_note()
	ov.close()
	var bought := Game.buy_item("pagina_dulzor", 5)
	var again := Game.buy_item("pagina_dulzor", 1)
	print("MAGIC página de Tobías: compra=", bought, " otra vez=", again, " runas=", Game.known_runes(), " oro=", Game.gold, " vende=", Overlays.vendor_items("tobias").map(func(it): return it["id"]))
	await get_tree().create_timer(0.8).timeout
	# 2) un pedido con runa: Greta quiere Bálsamo Helado con la runa de Prisa
	phase = Phase.OPEN
	world.walker.teleport(ShopWorld.P_ALCH_CAULDRON.x, -1)
	world.snap_camera()
	_magic_customer("panadera", ["prisa"])
	print("MAGIC pedido: ", current["potion"], " runas=", Game.order_runes(current), " ticket=", ui.order_mods_ids())
	# 3) preparar: dos lágrimas de sirena (Escarcha + Vida = Bálsamo Helado)
	for id in ["lagrima_sirena", "lagrima_sirena"]:
		_add_jar(id)
		await get_tree().create_timer(0.3).timeout
	# --- R3 MERGE: el caldero es el banco de UI-BENCH: se remueve en el banco, se embotella y se cierra (como el bot)
	var wait := 0.0
	while (not _brew_open() or brew.is_busy() or contents.size() < 2) and wait < 6.0:
		await get_tree().create_timer(0.2).timeout
		wait += 0.2
	_on_brew()
	await get_tree().create_timer(1.6).timeout
	if brew._stir:
		brew._stir.press()
	elif ov.current == "stir":
		ov.stir_key()
	while busy:
		await get_tree().create_timer(0.2).timeout
	if not brew_ready.is_empty():
		await brew_bottle()
	if _brew_open():
		await brew.close()
	# --- end R3 MERGE
	var idx := -1
	for i in Game.potions.size():
		if Game.potions[i]["id"] == "balsamo_helado" and Game.potion_runes(Game.potions[i]).is_empty():
			idx = i
	print("MAGIC preparada: ", Game.potions[idx] if idx >= 0 else {})
	# 4) encantar en el escritorio: el libro en modo encantar, la tinta de brasa y el trazo (perfecto, cursor automático)
	var res: Dictionary = await grimoire.bot_enchant(idx, "prisa")
	print("MAGIC encantada: ", res, " brasa=", Game.item_count("tinta_brasa"), " estrellas=", res.get("rune_stars", 0))
	# 5) entregar
	var g0 := Game.gold
	var i2 := Game.find_potion(res)
	_on_potion(i2)
	while busy:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.5).timeout
	ui._advance()
	print("MAGIC entrega: oro +", Game.gold - g0, " (runa +", Game.rune_bonus(res, current), ") dice=", ui.dialog_text.text.replace("\n", " / "))
	# 6) la mañana siguiente: la carta cuenta cómo le fue la runa
	var o: Dictionary = Game.pending.back()
	o["via"] = "letter"
	o["due"] = Game.day + 1
	Game.day += 1
	var letters := []
	for o2 in Game.take_due_letters():
		letters.append(Story.letter(o2, Game.resolve_outcome(o2)))
	var body: String = letters[0]["body"] if not letters.is_empty() else ""
	print("MAGIC carta: «", body, "» menciona la runa=", body.contains("Haste") or body.contains("rune"), " premio=", letters[0]["reward"] if not letters.is_empty() else "")
	# 7) una runa que falta: la carta lo dice y la propina baja
	var it_plain := {"kind": "potion", "id": "balsamo_helado", "potency": 6}
	var o3 := Story.make_outcome(current, it_plain, true, Story.price_of(it_plain, current))
	var o4 := Story.make_outcome(current, res, true, Story.price_of(res, current))
	print("MAGIC sin runa: propina ", o3["tip"], " vs ", o4["tip"], " renombre ", o3["renombre"], " vs ", o4["renombre"], " carta=«", Story.rune_line(o3), "»")
	# 8) guardar y cargar
	var before := Game.magic_save()
	var pots := JSON.stringify(Game.potions)
	Game.save_game()
	Game.load_game()
	print("MAGIC guardado ok=", JSON.stringify(before) == JSON.stringify(Game.magic_save()), " pociones ok=", pots == JSON.stringify(Game.potions))
	Game.delete_save()
	get_tree().quit()

## --demo=oldsave: una partida de la versión anterior (pergaminos en el estante, papel, vitela, páginas de hechizos y
## noticias de pergaminos pendientes) se carga sin errores: lo que ya no existe se devuelve en oro.
func _old_save_test() -> void:
	Engine.time_scale = 4.0
	var d := {"version": 1, "gold": 50, "renombre": 14, "day": 4, "stock": {"raiz_mandragora": 2, "lagrima_sirena": 1},
		"potions": [{"id": "sueno_profundo", "potency": 5}, {"id": "vigor_verde", "potency": 4}], "discovered": {"sueno_profundo": 5, "vigor_verde": 4},
		"upgrades": {}, "hero_progress": {"lirien": 1}, "hero_last_day": {"lirien": 2}, "journal": [], "lucky": false,
		"cat_petted_day": 3, "stats": {"sold": 6, "brewed": 7, "earned": 120, "perfect": 2}, "tutorial_done": true,
		"music_volume": 0.7, "sfx_volume": 0.8,
		"magic": {"unlocked": true, "items": {"papel": 3, "vitela": 1, "tinta_brasa": 2, "tinta_savia": 1},
			"scrolls": [{"id": "sello_calor", "potency": 5}, {"id": "runa_calma", "potency": 7}],
			"pages": {"sello_calor": "read", "hechizo_brotes": "new", "runa_calma": "read", "pergamino_luz": "new", "mensaje_alado": "new"},
			"made": {"sello_calor": 5}, "stats": {"scrolls": 3, "perfect": 1, "inks": 2}},
		"story": {"pending": [
			{"id": 1, "who": "granjero", "req_kind": "villager", "item_kind": "scroll", "item": "sello_calor", "wanted": "sello_calor",
				"ok": true, "via": "letter", "due": 4, "potency": 5, "stars": 2, "price": 22, "tip": 5, "renombre": 2, "day": 3,
				"grade": "good", "good": "¡La casa estuvo tibia toda la semana!"},
			{"id": 2, "who": "marta", "req_kind": "villager", "item_kind": "potion", "item": "ojo_nocturno", "wanted": "sello_calor",
				"ok": false, "via": "letter", "due": 4, "potency": 5, "stars": 2, "price": 18, "tip": 0, "renombre": 0, "day": 3,
				"grade": "bad", "fail": "La abuela siguió con frío."}],
			"met": {"granjero": true, "marta": true}, "seq": 2}}
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f = null
	var ok := Game.load_game()
	print("OLDSAVE cargada=", ok, " oro=", Game.gold, " (devuelto ", Game.legacy_refund, ") tintas=", Game.items, " páginas=", Game.rune_pages,
		" runas=", Game.known_runes(), " pociones=", Game.potions, " stats=", Game.magic_stats)
	_refresh_all()
	_begin_day()
	await get_tree().create_timer(3.0).timeout
	print("OLDSAVE mañana: panel=", ov.current, " pendientes=", Game.pending.size(), " oro=", Game.gold)
	Game.delete_save()
	get_tree().quit()
# --- end R3 MAGIC3

# --- R4 EVENTS: los eventos -------------------------------------------------------------------------------------
# La invitación llega con el correo (overlays.gd show_invitation): Aceptar paga la inscripción y reserva el día. Ese día
# no se abre la tienda: el mapa del viaje, el escenario del evento (EventScenes.build), el juego (EventGame), la tarjeta
# de resultados y, de noche en la tienda, las cuentas del día con la medalla. Mientras dura, el inventario de la tienda
# está guardado aparte (Game.events_stash) y el banco del caldero está en modo evento (BrewUI.set_event_mode).

var _ev_answer := -1        # la respuesta a la invitación abierta: 1 acepta, 0 rechaza, -1 todavía nada
var _ev_active := false     # el escenario del evento está puesto (la tienda escondida)
var _bot_ev_errors := 0
var bot_skill := 0.8        # el bot de los eventos acierta el removido con esta probabilidad (--evskill=)
var bot_delay := 0.0        # segundos de «reacción humana» antes de cada acción (--evdelay=; el balance en NOTES.txt)
var bot_smart := 1.0        # concurso: probabilidad de elegir la poción que mejor encaja con el tema (--evsmart=)
var bot_maxscale := 3.0     # velocidad máxima del juego mientras el bot remueve (--evmaxscale=)

func _ev_setup() -> void:
	events_ui = EventUI.new()
	events_ui.setup(self)
	add_child(events_ui)
	events_ui.bench_pressed.connect(_ev_open_bench)
	pad.events_ui = events_ui
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--evskill="):
			bot_skill = clampf(float(a.substr(10)), 0.0, 1.0)
		elif a.begins_with("--evdelay="):
			bot_delay = maxf(0.0, float(a.substr(10)))
		elif a.begins_with("--evsmart="):
			bot_smart = clampf(float(a.substr(10)), 0.0, 1.0)
		elif a.begins_with("--evmaxscale="):
			bot_maxscale = maxf(1.0, float(a.substr(13)))

## Después del correo. true si hoy es el día de un evento (y entonces lo juega entero, hasta las cuentas de la noche).
func _ev_morning() -> bool:
	# recargó la noche de un evento ya jugado: directo a las cuentas
	if Game.ev_done_day == Game.day and Game.ev_booked.is_empty() and not Game.ev_history.is_empty():
		Events.today_entry(Game.ev_history.back())
		await _ev_night(false)
		return true
	if not Game.ev_booked.is_empty() and int(Game.ev_booked.get("day", 0)) < Game.day:
		Game.ev_booked = {}   # (no debería pasar: el día del evento no se salta)
	if Events.today_is_event():
		await _ev_run_day()
		return true
	if not Game.ev_invite.is_empty() or Events.invite_due():
		var inv: Dictionary = Game.ev_invite if not Game.ev_invite.is_empty() else Events.make_invite()
		if not inv.is_empty():
			Game.save_game()
			await _ev_ask(inv)
	if phase == Phase.MORNING:
		events_ui.refresh_reminder()
		if not Game.ev_booked.is_empty() and int(Game.ev_booked.get("day", 0)) == Game.day + 1:
			ui.show_tip("Tomorrow: [b]%s[/b]. No shop that day." % Events.ev_name(String(Game.ev_booked["kind"])), 12.0)
	_ev_morning_done = true
	return false

## --- R4 MERGE: el orden del correo de la mañana: primero la invitación (pide una decisión: Aceptar / Rechazar), después
## el correo (cartas de clientes y de Krápido, con la línea del Escalafón arriba), la Gaceta cada 5 días y, si hoy es el
## día del evento, el evento (_ev_morning). Aquí solo la invitación: _ev_morning ya no la encuentra pendiente.
func _ev_invite_first() -> void:
	if Events.today_is_event() or Game.ev_done_day == Game.day:
		return
	if not Game.ev_invite.is_empty() or Events.invite_due():
		var inv: Dictionary = Game.ev_invite if not Game.ev_invite.is_empty() else Events.make_invite()
		if not inv.is_empty():
			Game.save_game()
			await _ev_ask(inv)
			await get_tree().create_timer(1.3).timeout   # un momento para leer «¡Inscrita!» antes del correo
			ui.clear_toasts()
# --- end R4 MERGE

## La invitación en papel; espera la respuesta. Cerrarla sin contestar (solo puede pasar desde el código) es rechazarla.
func _ev_ask(inv: Dictionary) -> void:
	_ev_answer = -1
	var cb := func(acc: bool): _ev_answer = 1 if acc else 0
	ov.invite_answered.connect(cb)
	ov.show_invitation(inv)
	while ov.current == "invite":
		await get_tree().process_frame
	await get_tree().process_frame
	if ov.invite_answered.is_connected(cb):
		ov.invite_answered.disconnect(cb)
	if _ev_answer == 1 and Events.accept():
		Sfx.play("coin", 0.05, -4.0)
		var bk: Dictionary = Game.ev_booked
		ui.toast("Signed up! %s, Day %d" % [Events.ev_name(String(bk["kind"])), int(bk["day"])], UIKit.GOLD_BRIGHT, 3.2)
	else:
		Events.reject()
		ui.toast("Maybe next time", UIKit.TEXT, 2.4)
	Game.save_game()
	ui.refresh_hud()

## El día del evento: el viaje, el escenario, el juego, los resultados y la vuelta a casa de noche.
func _ev_run_day() -> void:
	# --- BOOT: el precalentamiento de después del título tiene que haber terminado (siempre, salvo que el evento llegue a
	# los pocos segundos de empezar: entonces sigue unos cuadros más, con la tienda todavía a la vista)
	if is_instance_valid(boot_warm) and not boot_warm.done:
		await boot_warm.wait_done(30.0)
	# --- end BOOT
	var ev: Dictionary = Game.ev_booked.duplicate(true)
	var kind := String(ev.get("kind", "academia"))
	phase = Phase.EVENT
	_update_top_buttons()
	ui.hide_tip()
	ui.hide_order()
	events_ui.refresh_reminder(false)
	PerfLog.mark("ev:day " + kind)   # --- R6 PERF
	ui.show_banner(Events.ev_name(kind), "No shop today")
	await get_tree().create_timer(1.8).timeout
	if phase != Phase.EVENT:
		return
	PerfLog.mark("ev:travel")   # --- R6 PERF
	_ev_prebuild(kind)   # --- R6 PERF: el escenario se arma por partes mientras el carro va de camino
	_ev_hide_shop_under_map()   # --- R6 PERF: y la tienda, tapada por el mapa, deja de dibujarse
	await events_ui.travel(kind)
	# --- R6 PERF: el escenario se arma y se precalienta mientras el mapa del viaje sigue en pantalla: el carro ya llegó
	# y el mapa está quieto (tapa todo). Antes se armaba entero en un cuadro después del fundido a negro (0,15 s y 4
	# cuadros) y la gente, el HUD y los efectos se armaban o se compilaban ya a la vista (los tirones). Ahora: armado
	# por partes durante el viaje (_ev_prebuild), mostrado por partes bajo el mapa (reveal_gradually: los shaders se
	# compilan en varios cuadros medianos), la gente, el HUD y los efectos de después dibujados una vez (warm_up), y
	# solo entonces el fundido a negro y el de entrada, sin nada pesado en medio (el negro dura dos cuadros).
	while _ev_pre.get("busy", false):
		await get_tree().process_frame
	if phase != Phase.EVENT:
		_ev_drop_prebuilt()
		if not _ev_active:
			world.visible = true
		return
	PerfLog.mark("ev:build_under_map")
	var pt := PerfLog.t0()
	_ev_enter_scene(ev)
	PerfLog.step("ev:enter_scene", pt)
	await _ev_warm_hidden()
	if phase != Phase.EVENT:
		return
	PerfLog.mark("ev:fade_out")
	await _fade_to(1.0, 0.35)
	PerfLog.mark("ev:black")
	events_ui.end_travel()
	await _frames(2)
	if phase != Phase.EVENT:
		return
	PerfLog.mark("ev:fade_in")
	await _fade_to(0.0, 0.6)
	PerfLog.mark("ev:visible")
	# --- end R6 PERF
	await _ev_play(ev)

# --- R6 PERF: el principio del evento sin tirones. Con el escenario todavía tapado (el mapa del viaje ya quieto encima):
# ella, la fila o el jurado y el HUD se arman (EventGame.prepare) y lo que sale en los primeros segundos se dibuja una
# vez y se quita (EventGame.warm_up / warm_down: la poción que vuela, el humo del caldero, el confeti, las caritas, la
# cuenta atrás, «+3 ★», la pizarra, las caras de las tarjetas). WebGL compila cada material la primera vez que lo dibuja:
# así lo hace aquí, tapado, y no a la vista. Antes estas cosas aparecían después del fundido de entrada (un tirón al ver
# la escena, otro en la cuenta atrás y otro con la primera poción).
func _ev_warm_hidden() -> void:
	var g := ev_game
	if not is_instance_valid(g):
		return
	if ev_scene is EventScenes:   # el escenario (y su público) en unos 8 cuadros: los shaders, repartidos
		await (ev_scene as EventScenes).reveal_gradually(get_tree())
	if not is_instance_valid(g) or phase != Phase.EVENT:
		return
	g.prepare()
	await _frames(2)          # el escenario, la gente y el HUD se dibujan (y se compilan) aquí
	if not is_instance_valid(g) or phase != Phase.EVENT:
		return
	var junk: Array = await g.warm_up(get_tree())   # por partes, un cuadro cada una
	await _frames(2)          # los efectos de más tarde, dibujados una vez más
	if is_instance_valid(g):
		g.warm_down(junk)
	await _frames(2)          # dos cuadros tranquilos antes del fundido de entrada
	PerfLog.mark("ev:warm_done")
# --- end R6 PERF

# --- R6 PERF: el escenario armado por partes durante el viaje (EventScenes.build_async), fuera del árbol hasta que
# _ev_enter_scene lo pone. Si el día del evento se corta antes (volver al título), se borra cuando termina de armarse.
var _ev_pre := {}   # {"kind", "busy": se está armando, "scene": Node3D}

func _ev_prebuild(kind: String) -> void:
	_ev_drop_prebuilt()
	var job := {"kind": kind, "busy": true, "scene": null}
	_ev_pre = job
	var pt := PerfLog.t0()
	var sc: Node3D = await EventScenes.build_async(kind, get_tree())
	PerfLog.step("ev:prebuild " + kind, pt)
	job["busy"] = false
	if is_same(_ev_pre, job):
		job["scene"] = sc
	else:
		sc.free()   # nadie lo va a usar

## Mientras el mapa del viaje tapa toda la pantalla, la tienda de detrás no se dibuja (eran ~460 llamadas de dibujo por
## cuadro que nadie veía: el carro va más suave y el armado por partes tiene más sitio). _ev_enter_scene la deja
## escondida igual (y _ev_leave_scene la vuelve a mostrar).
func _ev_hide_shop_under_map() -> void:
	for i in 240:   # el mapa aparece en 0,35 s (y tapa todo cuando ya es opaco); cuadros y no segundos: en un equipo lento
		await get_tree().process_frame   # el fundido puede tardar más cuadros, pero no más segundos de juego
		if phase != Phase.EVENT or _ev_active:
			return
		var bg = events_ui.get("_map_bg")
		if bg is CanvasItem and is_instance_valid(bg) and (bg as CanvasItem).modulate.a >= 0.999:
			world.visible = false
			return

func _ev_take_prebuilt(kind: String) -> Node3D:
	if _ev_pre.get("busy", false) or String(_ev_pre.get("kind", "")) != kind:
		return null
	var sc = _ev_pre.get("scene")
	_ev_pre = {}
	return sc if is_instance_valid(sc) else null

func _ev_drop_prebuilt() -> void:
	if _ev_pre.get("busy", false):
		_ev_pre = {}   # el que se está armando se borra solo al terminar (ya no es el de _ev_pre)
		return
	var sc = _ev_pre.get("scene")
	if is_instance_valid(sc) and not (sc as Node).is_inside_tree():
		(sc as Node).free()
	_ev_pre = {}
# --- end R6 PERF

## Pone el escenario del evento (la tienda queda escondida y en pausa), la despensa y el juego.
func _ev_enter_scene(ev: Dictionary) -> void:
	var kind := String(ev.get("kind", "academia"))
	if is_instance_valid(ev_scene):
		ev_scene.queue_free()
	var pt := PerfLog.t0()   # --- R6 PERF
	ev_scene = _ev_take_prebuilt(kind)   # --- R6 PERF: el que se armó durante el viaje (si no, se arma aquí)
	if ev_scene == null:
		ev_scene = EventScenes.build(kind)
	PerfLog.step("ev:build " + kind, pt)   # --- R6 PERF
	pt = PerfLog.t0()   # --- R6 PERF
	add_child(ev_scene)
	PerfLog.step("ev:add_child", pt)   # --- R6 PERF
	_ev_active = true
	_set_place_on(world, false)
	var cam := ev_scene.get_node_or_null("Camera") as Camera3D
	if cam:
		cam.make_current()
	pt = PerfLog.t0()   # --- R6 PERF
	if ev_scene.has_method("set_crowd"):
		ev_scene.call("set_crowd", Array(Events.info(kind)["crowd"]))
	PerfLog.step("ev:set_crowd", pt)   # --- R6 PERF
	pt = PerfLog.t0()   # --- R6 PERF
	Sfx.set_place("market" if kind != "academia" else "shop")
	ui.set_time_label("Midday")
	brew.close_now()
	contents.clear()
	brew_ready = {}
	Game.events_stash(Events.pantry(ev))
	brew.set_event_mode(true)
	ui.set_shop_panels_visible(true)
	if is_instance_valid(ev_game):
		ev_game.queue_free()
	PerfLog.step("ev:stash_bench_mode", pt)   # --- R6 PERF
	pt = PerfLog.t0()   # --- R6 PERF
	ev_game = EventGame.new()
	ev_game.name = "EventGame"
	add_child(ev_game)
	ev_game.setup(self, events_ui, ev, ev_scene)
	PerfLog.step("ev:game_setup", pt)   # --- R6 PERF

## El juego y lo que viene después (resultados, vuelta a casa, las cuentas).
func _ev_play(ev: Dictionary) -> void:
	var game := ev_game
	game.run()
	var res: Dictionary = await game.finished
	if phase != Phase.EVENT or not is_instance_valid(game):
		return
	await _ev_end(ev, res)

func _ev_end(ev: Dictionary, res: Dictionary) -> void:
	var kind := String(ev.get("kind", "academia"))
	brew.close_now()
	brew_ready = {}
	contents.clear()
	brew.set_event_mode(false)
	Game.events_unstash()
	var rw := Events.apply_result(ev, res)
	Game.save_game()
	ui.refresh_hud()
	print("EVENTO ", kind, " medalla=", res.get("medal", ""), " puntos=", res.get("score", 0), " premio=", rw)
	events_ui.show_results({"kind": kind, "medal": String(res.get("medal", "none")), "rows": res.get("rows", []), "reward": rw,
		"line": String(res.get("line", ""))})
	await events_ui.results_closed
	if phase != Phase.EVENT:
		return
	await _fade_to(1.0, 0.6)
	_ev_leave_scene()
	await _ev_night(true)

func _ev_leave_scene() -> void:
	events_ui.hide_hud()
	if is_instance_valid(ev_game):
		ev_game.queue_free()
	ev_game = null
	if is_instance_valid(ev_scene):
		ev_scene.queue_free()
	ev_scene = null
	if _ev_active:
		_ev_active = false
		_set_place_on(world, true)
		world.camera.current = true
		Sfx.set_place("shop")

## De noche en la tienda: el trofeo nuevo brilla en su repisa y las cuentas del día (con la medalla).
func _ev_night(from_black := true) -> void:
	phase = Phase.CLOSING
	_update_top_buttons()
	_refresh_all()
	world.set_time(1.0, false)
	ui.set_time_label("Night")
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	world.cat.play("sit")
	var won: bool = String(Game.today.get("event", {}).get("medal", "none")) != "none"
	if from_black:
		await _fade_to(0.0, 0.8)
	if won:
		world.refresh_trophies(true)
		Sfx.play("sparkle", 0.0, -4.0)
	await get_tree().create_timer(1.2).timeout
	await _show_pending_levels()
	Ranking.commit_day()   # --- R4 MERGE (RANK + EVENTS): el día del evento suma en el Escalafón antes de las cuentas
	Game.save_game()
	ov.show_summary(Game.day, Game.today)

## Volver al título en medio de un evento: todo vuelve a la tienda (el inventario incluido); el evento se repite al cargar.
func _ev_abort() -> void:
	if events_ui:
		events_ui._close_modal()
		events_ui.end_travel()
		events_ui.refresh_reminder(false)
	if not Game.ev_stash.is_empty():
		brew.close_now()
		brew_ready = {}
		contents.clear()
		Game.events_unstash()
	if brew:
		brew.set_event_mode(false)
	_ev_leave_scene()

## «Caldero» (o E) durante el evento: vuelve a abrir el banco.
func _ev_open_bench() -> void:
	if phase == Phase.EVENT and is_instance_valid(ev_game) and ev_game.running and not _brew_open():
		open_brew()

# --- R6 PERF: demos para medir los tirones (con --perflog=<archivo>, o =console en la web) -------------------------
## --demo=perf_event --evkind=academia|concurso|torneo [--evplay=20]: como en el juego. El arranque precalienta la
## tienda y el mercado en negro (_warm_places), unos segundos de mañana en la tienda y luego el día del evento entero
## (cartel, mapa del viaje, negro, escenario, la anfitriona, la cuenta atrás) y --evplay segundos de juego con el bot.
## --demo=perf_tour: la primera vez de cada pantalla, una tras otra (banco, grimorio, recetario, diario, el mercado y un
## puesto, la bola de cristal, el Escalafón, abrir la tienda con el primer cliente y el final del puesto 1).
func _perf_demo(name: String) -> void:
	var args := _ev_args()
	_ev_demo_state(20)
	phase = Phase.MORNING
	_update_top_buttons()
	if name == "perf_tour":
		Game.upgrades["krapido"] = true
		_refresh_all()
	PerfLog.mark("perf:warm_places")
	await _warm_places()
	PerfLog.mark("perf:fade_in")
	await _fade_to(0.0, 0.5)
	PerfLog.mark("perf:morning")
	await get_tree().create_timer(3.0).timeout
	if name == "perf_event":
		var kind := String(args.get("evkind", "academia"))
		Events.make_invite(kind)
		Game.ev_booked = Game.ev_invite
		Game.ev_invite = {}
		Game.ev_booked["day"] = Game.day
		Game.gold -= int(Game.ev_booked["fee"])
		phase = Phase.MORNING
		_bot_play_event.call_deferred(false)
		_ev_run_day()
		var t := 0.0
		while (ev_game == null or not ev_game.started) and t < 120.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		PerfLog.mark("perf:play")
		await get_tree().create_timer(float(args.get("evplay", "20"))).timeout
	else:
		await _perf_tour()
	PerfLog.mark("perf:end")
	PerfLog.stop()
	get_tree().quit()

## Cada paso: lo abre, espera, lo cierra y espera (los cuadros de en medio son los que importan).
func _perf_tour() -> void:
	var steps := [
		["bench", func(): open_brew(), func(): brew.close_now()],
		["grimoire", func(): grimoire.open(), func(): ov.close()],
		["recipes", func(): ov.show_book(), func(): ov.close()],
		["journal", func(): ov.show_journal(), func(): ov.close()],
		["ball", func(): krapido.ball.open(), func(): krapido.ball.close_now()],
		["ranking", func(): ov.show_ranking(), func(): ov.close()],
	]
	if String(_ev_args().get("evtour", "")) == "market":   # --evtour=market: solo el mercado, la tienda y el final
		steps = []
	for st in steps:
		for k in 2:   # la primera vez y la segunda (lo que cuesta solo la primera vez es lo que se puede precalentar)
			PerfLog.mark("tour:%s open%d" % [st[0], k + 1])
			var t := PerfLog.t0()
			st[1].call()
			PerfLog.step("tour:%s open%d_call" % [st[0], k + 1], t)
			await get_tree().create_timer(2.0).timeout
			PerfLog.mark("tour:%s close" % st[0])
			st[2].call()
			await get_tree().create_timer(1.0).timeout
	# el mercado: sale por la puerta, un puesto y vuelve
	PerfLog.mark("tour:market go")
	await _go_market()
	PerfLog.mark("tour:market in")
	await get_tree().create_timer(2.0).timeout
	PerfLog.mark("tour:stall")
	await market.use_station("ilse")
	await get_tree().create_timer(2.0).timeout
	ov.close()
	PerfLog.mark("tour:market back")
	await _leave_market()
	await get_tree().create_timer(1.5).timeout
	# abrir la tienda: el reloj, el primer cliente entra y llega al mostrador
	PerfLog.mark("tour:open shop")
	_open_shop()
	await get_tree().create_timer(14.0).timeout
	# el final del puesto 1 (en automático), desde negro
	PerfLog.mark("tour:ending")
	phase = Phase.CLOSING
	await _fade_to(1.0, 0.5)
	_play_ending(true)
	await get_tree().create_timer(45.0).timeout   # el final entero (confeti y créditos incluidos)
	PerfLog.mark("tour:ending end")
# --- end R6 PERF

# ------------------------------------------------ demos, prueba rápida y bot de los eventos

func _ev_args() -> Dictionary:
	var o := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ev"):
			var kv := a.substr(2).split("=")
			o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return o

## Un estado de partida para las demos de eventos (día 5, renombre «Boticaria»).
## Números creíbles para la tarjeta de la demo de resultados: la medalla pedida cuadra con los cortes del evento.
func _ev_demo_numbers(medal: String) -> void:
	var g := ev_game
	var c: Dictionary = g.cuts
	match g.kind:
		"academia":
			var n := int(g.plan.get("n", 8))
			var stars := {"gold": int(c["gold"]), "silver": int(c["silver"]) + 1, "bronze": int(c["bronze"]) + 1,
				"none": maxi(0, int(c["bronze"]) - 3)}
			g.delivered = n if medal == "gold" else clampi(int(round(float(stars[medal]) / 2.4)), 1, n - 1)
			g.bonus = 2 if medal == "gold" else 0
			g.score = int(stars[medal]) + g.bonus
		"torneo":
			var k := int(g.plan.get("k", 12))
			var pts := {"gold": int(c["gold"]) + 2, "silver": int(c["silver"]) + 2, "bronze": int(c["bronze"]) + 1,
				"none": maxi(0, int(c["bronze"]) - 4)}
			g.score = int(pts[medal])
			g.served = clampi(int(round(g.score / 3.1)), 0, k)
			g.lost = k - g.served
			g.tips = g.served * 7
		"concurso":
			var mine := {"gold": 41, "silver": 34, "bronze": 28, "none": 21}
			var rn: Array = []
			for r in g.rivals:
				rn.append(String(r["name"]))
			g.totals = {EventGame.ME: int(mine.get(medal, 30)), rn[0]: 38, rn[1]: 31, rn[2]: 25}   # --- R5 EN-UI: id, no «Tú»

func _ev_demo_state(renombre := 20) -> void:
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 5
	Game.gold = 160
	Game.renombre = renombre
	Game.upgrades = {"alfombra": true, "cojin": true}
	for pid in ["sueno_profundo", "ojo_nocturno", "balsamo_helado", "vigor_verde", "tonico_brio", "velo_invernal"]:
		Game.discovered[pid] = 5
	for id in Data.INGREDIENT_ORDER:
		Game.stock[id] = 4 if Game.ingredient_unlocked(id) else 0
	_refresh_all()
	ui.set_gameplay_visible(true)
	world.set_time(0.0, false)
	ui.set_time_label("Morning")

func _ev_demo(name: String) -> void:
	var args := _ev_args()
	if name == "eventtest":
		_ev_test()
		return
	if name == "event_padtest":
		_ev_padtest()
		return
	_ev_demo_state(int(args.get("evrenombre", "20")))
	var kind := name.trim_prefix("event_")
	match name:
		"event_academia", "event_concurso", "event_torneo":
			Events.make_invite(kind)
			Game.ev_booked = Game.ev_invite
			Game.ev_invite = {}
			Game.ev_booked["day"] = Game.day
			Game.gold -= int(Game.ev_booked["fee"])
			if args.has("evbot"):
				Engine.time_scale = float(args.get("evscale", "1"))
				_bot_play_event.call_deferred(args.has("evquit"))
			elif args.has("evscale"):   # --- R4 MERGE: también sin el bot (capturas: la fila del torneo a los 30 s)
				Engine.time_scale = float(args.get("evscale", "1"))
			if args.has("evwatch"):   # --- R4 MERGE: sin bot: pasa la línea del anfitrión y cierra el banco (se ve la escena)
				_ev_demo_watch.call_deferred()
			if args.has("evskip"):
				phase = Phase.EVENT
				_ev_enter_scene(Game.ev_booked.duplicate(true))
				await _ev_play(Game.ev_booked.duplicate(true))
			else:
				phase = Phase.MORNING
				await _ev_run_day()
		"event_invite":
			phase = Phase.MORNING
			Game.day = int(args.get("evday", "2"))
			Game.renombre = int(args.get("evrenombre", "3"))
			Game.gold = 64
			ui.refresh_hud()
			var inv := Events.make_invite(String(args.get("evkind", "")))
			await _ev_ask(inv)
		"event_night":
			# la noche de un evento: el trofeo nuevo brilla en la repisa y las cuentas con la medalla
			Game.ev_trophies = [{"kind": "academia", "medal": "gold", "day": 1}, {"kind": String(args.get("evkind", "torneo")), "medal": String(args.get("evmedal", "silver")), "day": Game.day}]
			Game.reset_today()
			Game.today["earned"] = 134
			Game.today["renombre"] = 9
			var h := {"id": "torneo_5", "kind": String(args.get("evkind", "torneo")), "day": Game.day, "medal": String(args.get("evmedal", "silver")), "points": 33, "tier": 1}
			Events.today_entry(h)
			await _ev_night(false)
		"event_reminder":
			# un día de tienda con un evento aceptado: la etiqueta bajo el HUD
			phase = Phase.MORNING
			Events.make_invite("academia")
			Events.accept()
			_update_top_buttons()
			events_ui.refresh_reminder()
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
		"event_map":
			phase = Phase.MORNING
			await events_ui.show_map_still(String(args.get("evkind", "torneo")), float(args.get("evp", "0.6")))
		"event_trophies":
			phase = Phase.MORNING
			Game.ev_trophies = [{"kind": "academia", "medal": "gold", "day": 4}, {"kind": "torneo", "medal": "bronze", "day": 9},
				{"kind": "concurso", "medal": "silver", "day": 13}, {"kind": "concurso", "medal": "gold", "day": 18}]
			world.walker.teleport(float(ShopWorld.STATIONS["puerta"]["x"]) - 0.6, 1)
			world.snap_camera()
			world.refresh_trophies(true)
		"event_results", "event_jury":
			var k2 := String(args.get("evkind", "concurso" if name == "event_jury" else "academia"))
			Events.make_invite(k2)
			var ev: Dictionary = Game.ev_invite
			Game.ev_invite = {}
			ev["day"] = Game.day
			Game.ev_booked = ev
			phase = Phase.EVENT
			_ev_enter_scene(ev)
			ev_game.build_people()
			events_ui.show_hud(k2)
			if name == "event_jury":
				var th: Dictionary = Events.THEMES[0]
				var pot := {"id": "sueno_profundo", "potency": 7, "perfect": true}
				var sc := [Events.judge("elda", th, pot), Events.judge("lirien", th, pot), Events.judge("grumm", th, pot)]
				var lines := []
				for i in 3:
					lines.append(String(Events.JUDGE_LINES[String(Events.JUDGES[i]["id"])][sc[i] - 1]))
				var rn: Array = []
				for r in ev_game.rivals:
					rn.append(String(r["name"]))
				var mine: int = int(sc[0]) + int(sc[1]) + int(sc[2])
				ev_game.totals = {EventGame.ME: mine, rn[0]: 11, rn[1]: 9, rn[2]: 8}   # --- R5 EN-UI: id, no «Tú»
				ev_game._update_line_hud()
				await get_tree().create_timer(0.4).timeout
				events_ui.show_jury({"round": 1, "theme": String(th["text"]), "potion": pot, "scores": sc, "lines": lines,
					"table": [{"name": EventGame.ME_NAME, "round": mine, "total": mine, "me": true}, {"name": rn[0], "round": 11, "total": 11},
						{"name": rn[1], "round": 9, "total": 9}, {"name": rn[2], "round": 8, "total": 8}],
					"last": false, "fizz_line": "Bah. The judges don't understand science."})
			else:
				var medal := String(args.get("evmedal", "gold"))
				_ev_demo_numbers(medal)
				var res := ev_game.result()
				res["medal"] = medal
				res["line"] = String(Events.info(k2)["end"][medal])
				Game.events_unstash()
				var rw := Events.apply_result(ev, res)
				await get_tree().create_timer(0.4).timeout
				events_ui.show_results({"kind": k2, "medal": medal, "rows": res["rows"], "reward": rw, "line": res["line"]})

## --demo=eventtest: las reglas sin pantalla (calendario, aceptar / rechazar, guardar y cargar, la despensa, premios,
## jurado, medallas). Imprime EVENTTEST ... y sale.
func _ev_test() -> void:
	var ok := true
	Game.delete_save()
	Game.new_game_state()
	Game.tutorial_done = true
	var due1 := Events.invite_due()
	Game.day = 2
	var due2 := Events.invite_due()
	var inv := Events.make_invite()
	print("EVENTTEST día1 due=", due1, " día2 due=", due2, " inv=", inv.get("kind"), " para el día ", inv.get("day"), " cuota=", inv.get("fee"), " próxima=", Game.ev_next, " plan=", inv.get("plan"))
	# --- R4 MERGE: el evento nunca cae en día de mercado de PACE (el día 4 lo es): pasa al día siguiente
	var ev_day := 2 + Events.LEAD
	if ev_day >= Game.PACE_MARKET_EVERY and ev_day % Game.PACE_MARKET_EVERY == 0:
		ev_day += 1
	ok = ok and not due1 and due2 and inv.get("kind") == "academia" and int(inv.get("day")) == ev_day and Game.ev_next == 6
	var g0 := Game.gold
	var acc := Events.accept()
	print("EVENTTEST acepta=", acc, " oro ", g0, " -> ", Game.gold, " reservado=", Game.ev_booked.get("id"), " hoy_evento=", Events.today_is_event(), " otra_invitacion=", Events.invite_due())
	ok = ok and acc and Game.gold == g0 - int(inv["fee"]) and not Events.today_is_event() and not Events.invite_due()
	# guardar con la despensa del evento puesta: se guarda el inventario de la tienda
	var shop_stock: Dictionary = Game.stock.duplicate()
	Game.events_stash(Events.pantry(Game.ev_booked))
	var pantry_raiz := int(Game.stock.get("raiz_mandragora", 0))
	Game.save_game()
	Game.events_unstash()
	Game.load_game()
	print("EVENTTEST guardar durante el evento: despensa raíz=", pantry_raiz, " cargado raíz=", Game.stock.get("raiz_mandragora"), " (tienda ", shop_stock.get("raiz_mandragora"), ") reservado=", Game.ev_booked.get("id"), " plan=", Game.ev_booked.get("plan"))
	ok = ok and int(Game.stock.get("raiz_mandragora", -1)) == int(shop_stock.get("raiz_mandragora", -2)) and String(Game.ev_booked.get("id", "")) == String(inv["id"])
	ok = ok and Game.ev_booked["plan"]["n"] is int and Game.ev_booked["day"] is int
	Game.day = ev_day   # --- R4 MERGE (antes 4)
	print("EVENTTEST día ", ev_day, " hoy_evento=", Events.today_is_event())
	ok = ok and Events.today_is_event()
	# premios por medalla
	for m in Events.MEDALS:
		Game.reset_today()
		var r0 := Game.renombre
		var gg := Game.gold
		var rw := Events.apply_result(inv, {"medal": m, "score": 10})
		print("EVENTTEST medalla ", m, ": oro +", Game.gold - gg, " renombre ", Game.renombre - r0, " premio=", rw, " today.event=", Game.today.get("event"))
		var te: Dictionary = Game.today.get("event", {})
		ok = ok and te.has("id") and te.has("kind") and te.has("medal") and te.has("points") and String(te["medal"]) == m
		Game.renombre = 20
	print("EVENTTEST trofeos=", Game.ev_trophies.size(), " historial=", Game.ev_history.size())
	ok = ok and Game.ev_trophies.size() == 3 and Game.ev_history.size() == 4
	# jurado: tema justo, 3 estrellas y removido perfecto -> 4-5; sin poción -> 0; otro tema -> como mucho 2
	var th: Dictionary = Events.THEMES[0]
	var hi := []
	var no := []
	var off := []
	for i in 20:
		hi.append(Events.judge("lirien", th, {"id": "sueno_profundo", "potency": 7, "perfect": true}))
		off.append(Events.judge("grumm", th, {"id": "tonico_brio", "potency": 7, "perfect": true}))
	no.append(Events.judge("elda", th, {}))
	print("EVENTTEST jurado justo=", hi, " fuera_de_tema=", off, " nada=", no)
	ok = ok and hi.min() >= 4 and off.max() <= 2 and no[0] == 0
	print("EVENTTEST cortes academia(8)=", Events.cuts("academia", {"n": 8}), " torneo(12)=", Events.cuts("torneo", {"k": 12}))
	# el calendario en 40 días (renombre que crece unos 5 al día)
	Game.new_game_state()
	var days := []
	for d in range(1, 41):
		Game.day = d
		Game.renombre = d * 5
		if Events.invite_due():
			var iv := Events.make_invite()
			if not iv.is_empty():
				days.append("%d:%s(t%d)" % [d, iv["kind"], iv["tier"]])
				if days.size() % 2 == 1:
					Events.accept()
				else:
					Events.reject()
		if not Game.ev_booked.is_empty() and int(Game.ev_booked["day"]) == d:
			Events.apply_result(Game.ev_booked, {"medal": "silver"})
	print("EVENTTEST calendario 40 días: ", days)
	ok = ok and days.size() >= 6 and days.size() <= 10
	Game.delete_save()
	print("EVENTTEST ", "OK" if ok else "FALLO")
	get_tree().quit()

## --demo=event_padtest: el mando y el teclado en las pantallas de los eventos (sin ventana). Imprime PADTEST ... y sale.
func _ev_padtest() -> void:
	var ok := true
	_ev_demo_state()
	phase = Phase.MORNING
	await get_tree().create_timer(0.3).timeout
	# 1) la invitación: el mando ve Aceptar / Rechazar; Esc no la cierra; A sobre «Aceptar» la acepta
	var inv := Events.make_invite("academia")
	_ev_ask(inv)
	await get_tree().create_timer(0.5).timeout
	var names: Array = pad._buttons().map(func(b): return String(b.text))
	_ev_key(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	print("PADTEST invitación: botones=", names, " tras Esc sigue=", ov.current)
	ok = ok and names.has("Accept") and names.has("Decline") and ov.current == "invite"
	var acc_btn: Control = ov.current_node.find_child("Aceptar", true, false)
	await _ev_pad_tap(acc_btn.get_global_rect().get_center())
	await get_tree().create_timer(0.4).timeout
	print("PADTEST A en Aceptar: panel=", ov.current, " reservado=", Game.ev_booked.get("id", ""))
	ok = ok and ov.current == "" and not Game.ev_booked.is_empty()
	# 2) el evento: con el banco cerrado, el mando ve «Caldero»; E lo abre
	Game.ev_booked["day"] = Game.day
	phase = Phase.EVENT
	_ev_enter_scene(Game.ev_booked.duplicate(true))
	ev_game.build_people()
	events_ui.show_hud("academia")
	ev_game.running = true
	ev_game.started = true
	ev_game.time_total = 60.0
	ev_game.time_left = 60.0
	await get_tree().create_timer(0.3).timeout
	var hud_names: Array = pad._buttons().map(func(b): return String(b.text))
	_ev_key(KEY_E)
	await get_tree().create_timer(0.5).timeout
	print("PADTEST evento: botones=", hud_names, " E abre el banco=", _brew_open(), " sin Tinta=", not brew.btns["ink"].visible)
	ok = ok and hud_names.has("Cauldron") and _brew_open() and not brew.btns["ink"].visible
	# 3) el mercado del menú no abre en el evento
	_on_menu("market")
	print("PADTEST mercado en el evento: panel=", ov.current)
	ok = ok and ov.current == ""
	# 4) la tarjeta de resultados: el mando solo ve «Volver a casa»; Espacio la cierra
	brew.close_now()
	ev_game.running = false
	ev_game.over = true
	var res := ev_game.result()
	Game.events_unstash()
	var rw := Events.apply_result(Game.ev_booked, res)
	events_ui.show_results({"kind": "academia", "medal": String(res["medal"]), "rows": res["rows"], "reward": rw, "line": String(res["line"])})
	await get_tree().create_timer(0.5).timeout
	var card_names: Array = pad._buttons().map(func(b): return String(b.text))
	var closed := [false]
	events_ui.results_closed.connect(func(): closed[0] = true, CONNECT_ONE_SHOT)
	_ev_key(KEY_SPACE)
	await get_tree().create_timer(0.3).timeout
	print("PADTEST resultados: botones=", card_names, " Espacio cierra=", closed[0], " medalla=", res["medal"])
	ok = ok and card_names == ["Head home"] and closed[0]
	print("PADTEST ", "OK" if ok else "FALLO")
	get_tree().quit()

func _ev_key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

## Un toque del botón A del mando sobre un punto (como PadCursor: mueve su cursor y pulsa).
func _ev_pad_tap(at: Vector2) -> void:
	pad._show(true)
	pad._move_to(at)
	await get_tree().physics_frame
	pad._on_button(JOY_BUTTON_A, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	pad._on_button(JOY_BUTTON_A, false)
	await get_tree().physics_frame

## --- R4 MERGE: el perro guardián del bot. Un día normal del bot dura ~30-80 s de mañana, 300 s de tienda y unos segundos
## de noche (un evento, hasta ~250 s). Si el mismo día y la misma fase siguen 600 s (tiempo de juego), imprime el estado
## («AUTOPLAY ATASCO ...»: qué panel, el banco, la bola, el cuervo, el reloj...), lo cuenta como error y desatasca
## (cierra paneles, la bola y el banco). Solo para las pruebas: el juego normal no lo usa.
var _bot_stuck := 0
func _bot_watchdog() -> void:
	var last_day := -1
	var last_phase := -1
	var t := 0.0
	while is_inside_tree():
		await get_tree().create_timer(5.0).timeout
		if Game.day != last_day or phase != last_phase:
			last_day = Game.day
			last_phase = phase
			t = 0.0
			continue
		t += 5.0
		if t < 600.0:
			continue
		t = 0.0
		_bot_stuck += 1
		print("AUTOPLAY ATASCO día ", Game.day, " fase=", Phase.keys()[phase], " panel=", ov.current, " ocupada=", busy,
			" diálogo=", ui.dialog_open(), " banco=", _brew_open(), " bola=", _ball_open(), " cuervo=", krapido.raven_state,
			" reloj=", "%.0f" % shop_t, " pausa=", clock_paused(), " cerrando=", _pace_closing, " mostrador=",
			String(_counter_v.get("state", "")) if not _counter_v.is_empty() else "-", " fila=", line.size(),
			" cliente_listo=", customer_ready, " evento=", is_instance_valid(ev_game))
		if ov.is_open():
			ov.close(false)
		if _ball_open():
			krapido.ball.close_now()
		if _brew_open():
			brew.close_now()
		busy = false
# --- end R4 MERGE

## El bot y la invitación: acepta la primera de la partida y rechaza las siguientes.
func _bot_events_morning() -> void:
	# --- R4 MERGE: la invitación llega antes que el correo: el bot la contesta cuando aparece y cierra lo demás
	# (correo, Gaceta, subidas de nivel) hasta que termina la mañana de los eventos (_ev_morning_done) o empieza el evento
	var t := 0.0
	var answered := false
	while t < 24.0 and not _ev_morning_done and phase == Phase.MORNING:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if ov.current == "invite":
			if answered:
				continue
			answered = true
			var acc := _bot_ev_accept_all or not Game.ev_answers.any(func(a): return bool(a.get("accepted", false)))
			if acc and Game.gold < int(Game.ev_invite.get("fee", 0)):
				acc = false
			await get_tree().create_timer(0.5).timeout
			print("AUTOPLAY: invitación día ", Game.day, " ", Game.ev_invite.get("id", ""), " cuota ", Game.ev_invite.get("fee", 0), " oro ", Game.gold, " -> ", "acepta" if acc else "rechaza")
			if not ov.answer_invitation(acc) and not ov.answer_invitation(false):
				print("AUTOPLAY: no pudo contestar la invitación")
				_bot_ev_errors += 1
		elif ov.current == "levelup":
			ov.close()
		elif ov.is_open():
			ov.close(false)

var _bot_ev_accept_all := false   # --- R4 MERGE: --evaccept=all: el bot acepta todas las invitaciones que puede pagar (balance)
var _bot_load_path := ""   # --- R4 MERGE: --loadsave=<ruta>: la partida desde la que sigue el bot
# --- end R4 MERGE

## El bot juega el evento: prepara lo que hace falta, remueve (acierta con bot_skill), embotella, presenta (concurso)
## y cierra la tarjeta de resultados. quit: sale del juego al terminar (las demos con --evbot --evquit).
func _bot_play_event(quit := false) -> void:
	var scale0 := Engine.time_scale
	var t := 0.0
	while (ev_game == null or not ev_game.started) and t < 60.0:
		if ui.dialog_open():
			ui._advance()
		await get_tree().create_timer(0.3).timeout
		t += 0.3
	if ev_game == null:
		print("AUTOPLAY: el evento no empezó")
		_bot_ev_errors += 1
		return
	Engine.time_scale = minf(scale0, bot_maxscale)   # el removido necesita cuadros
	var g := ev_game
	var brewed := 0
	var dumb_round := -1   # concurso: la ronda en que se equivoca de tema (bot_smart)
	var dumb_pick := ""
	while is_instance_valid(g) and not g.over:
		if ui.dialog_open():
			ui._advance()
			await get_tree().create_timer(0.3).timeout
			continue
		if events_ui.modal_open():
			events_ui.press_default()
			await get_tree().create_timer(0.4).timeout
			continue
		if not g.running:
			await get_tree().create_timer(0.25).timeout
			continue
		var want := g.bot_want()
		if g.kind == "concurso" and want != "":
			if dumb_round != g.round_i:
				dumb_round = g.round_i
				dumb_pick = g.bot_want_other(want) if randf() > bot_smart else ""
			if dumb_pick != "":
				want = dumb_pick
		if want == "":
			if g.kind == "concurso":
				g._auto_present()
			await get_tree().create_timer(0.3).timeout
			continue
		var combo := g.bot_combo(want)
		if combo.is_empty() or Game.potions_full():
			await get_tree().create_timer(0.5).timeout
			continue
		await _bot_ev_brew(combo)
		brewed += 1
		if is_instance_valid(g) and g.kind == "concurso" and g.running:
			var i := g._shelf_find(want)
			if i >= 0:
				_on_potion(i)
	# el final: la anfitriona, la tarjeta de resultados
	t = 0.0
	while phase == Phase.EVENT and t < 60.0:
		if ui.dialog_open():
			ui._advance()
		elif events_ui.modal_kind() == "jury":
			events_ui.press_default()
		elif events_ui.modal_kind() == "results":
			print("AUTOPLAY EVENTO ", Game.today.get("event", {}), " preparadas=", brewed, " habilidad=", bot_skill)
			await get_tree().create_timer(1.5).timeout
			if quit:
				get_tree().quit()
				return
			events_ui.press_default()
			break
		await get_tree().create_timer(0.3).timeout
		t += 0.3
	Engine.time_scale = scale0

func _bot_ev_brew(combo: Array) -> void:   # --- R4 EVENTS (merge: was _bot_brew; PACE's bot has its own _bot_brew)
	if bot_delay > 0.0:
		await get_tree().create_timer(bot_delay * randf_range(0.7, 1.3)).timeout
	if not _brew_open():
		open_brew()
		await get_tree().create_timer(0.35).timeout
	if not _brew_open():
		return
	if not brew_ready.is_empty():
		await brew_bottle()
	if not contents.is_empty():
		_on_empty()
		await get_tree().create_timer(0.3).timeout
	for id in combo:
		brew.throw(id)
		await get_tree().create_timer(0.18 + bot_delay * 0.35).timeout
	var w := 0.0
	while (brew.is_busy() or contents.size() < combo.size()) and w < 4.0:
		await get_tree().create_timer(0.1).timeout
		w += 0.1
	if contents.size() < combo.size() or not _brew_open():
		return
	if bot_delay > 0.0:
		await get_tree().create_timer(bot_delay * 0.5).timeout
	_on_brew()
	await _bot_stir()
	w = 0.0
	while busy and w < 10.0:
		await get_tree().create_timer(0.1).timeout
		w += 0.1
	if bot_delay > 0.0:
		await get_tree().create_timer(bot_delay * 0.5).timeout
	if not brew_ready.is_empty():
		await brew_bottle()

func _bot_stir() -> void:
	var w := 0.0
	while brew._stir == null and w < 3.0:
		await get_tree().process_frame
		w += get_process_delta_time()
	var g: StirGame = brew._stir
	if g == null:
		return
	if randf() < bot_skill:
		while is_instance_valid(g) and not g.done:
			var a := fposmod(g.angle, TAU)
			if a > g.zone_start + 0.05 and a < g.zone_start + g.zone_size - 0.05:
				g.press()
				break
			await get_tree().process_frame
	else:
		await get_tree().create_timer(randf_range(0.3, 2.4)).timeout
		if is_instance_valid(g) and not g.done:
			g.press()
# --- end R4 EVENTS

# ------------------------------------------------------------------ capturas y pruebas automáticas

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--demo="):
			_demo = a.substr(7)
		elif a.begins_with("--days="):
			_autoplay_days = int(a.substr(7))
		elif a.begins_with("--bot="):
			_bot = a.substr(6)   # --- R4 PACE: el bot rápido ("good") o el lento ("slow")
		elif a.begins_with("--film="):
			_film_dir = a.substr(7)   # --- R4 PACE: una captura cada --film_every cuadros (para revisar el día abierto)
		elif a.begins_with("--film_every="):
			_film_every = int(a.substr(13))   # --- R4 PACE
		elif a == "--krapido":   # --- R4 RAVEN: el bot juega con la Ventanilla Krápido comprada desde el día 1
			_krapido_bot = true
		elif a == "--stats":   # --- R4 SCENES: imprime llamadas de dibujo y objetos al sacar la captura
			_stats = true
		elif a == "--evaccept=all":   # --- R4 MERGE: el bot acepta todas las invitaciones (balance del Escalafón)
			_bot_ev_accept_all = true
		elif a.begins_with("--loadsave="):   # --- R4 MERGE: el bot empieza desde una partida guardada (ruta absoluta)
			_bot_load_path = a.substr(11)
		# --- R5 MERGE: --textlog=<archivo>: anota todo el texto que se ve (scripts/textlog.gd; solo para pruebas)
		elif a.begins_with("--textlog="):
			TextLog.start(self, a.substr(10))
		# --- end R5 MERGE
		# --- R6 PERF: --perflog=<archivo> (o «console» en la web): los tiempos de cada cuadro y de cada paso medido
		elif a.begins_with("--perflog="):
			PerfLog.start(self, a.substr(10))
		elif a.begins_with("--post="):   # --post=centro,mitad,caída[,lod]: fuerza el desenfoque (para probar valores)
			var v := a.substr(7).split(",")
			var keys := ["focus_center", "focus_half", "focus_falloff", "max_lod"]
			for i in mini(v.size(), keys.size()):
				_post_force[keys[i]] = float(v[i])
			_post_cam = null
		# --- end R6 PERF

func _process(_d: float) -> void:
	_frame += 1
	if not _booted:   # --- BOOT: todavía armándose (la pantalla de carga tapa todo)
		return
	_post_follow_camera()   # --- R6 PERF: la banda nítida del desenfoque según el escenario que se ve
	ui.set_day_market(phase == Phase.OPEN)   # --- R3 MERGE: el «x2» del botón Mercado (de día el encargo cuesta el doble)
	if open_btn and open_btn.disabled != _trip_busy:   # --- R6 UI: los botones de arriba, desactivados mientras va o vuelve
		open_btn.disabled = _trip_busy
		trip_btn.disabled = _trip_busy
	_pace_process(_d)   # --- R4 PACE: el reloj, las llegadas, la fila y la paciencia
	if _shot_path != "" and _frame == max(_shot_frames, 20):
		if _stats:   # --- R4 SCENES
			print("STATS draw_calls=%d objects=%d primitives=%d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("SHOT ", _shot_path)
		if _demo != "autoplay":
			get_tree().quit()

func _run_demo() -> void:
	if _demo.begins_with("r6_"):   # --- R6 UI: capturas y pruebas de los avisos y los botones (bloque R6 UI, al final)
		_r6_demo(_demo)
		return
	if _demo.begins_with("m6_"):   # --- R6 MERGE: las pruebas de la unión (bloque R6 MERGE, al final)
		_m6_demo(_demo)
		return
	match _demo:
		"title":
			_show_title()
		"autoplay":
			_autoplay()
		"clicktest":
			_clicktest()
		"newgame":
			_start_new()
		"tutorial":
			_tutorial_demo()
		# --- R4 EVENTS: --demo=event_academia | event_concurso | event_torneo (directo al evento), event_invite (la carta),
		# event_results, event_jury, event_map, event_trophies (capturas) y eventtest (prueba rápida de las reglas)
		"event_academia", "event_concurso", "event_torneo", "event_invite", "event_results", "event_jury", "event_map", "event_trophies", "eventtest", "event_night", "event_reminder", "event_padtest":
			_ev_demo(_demo)
		# --- end R4 EVENTS
		# --- R4 MERGE: capturas del juego unido (la tienda con la fila, el reloj, Krápido y el Escalafón) y la prueba de
		# los puntos del Escalafón con un día de cada tipo
		"merge_shop", "merge_rankcheck", "merge_morning", "merge_ledger":
			_merge_demo(_demo)
		# --- end R4 MERGE
		# --- R6 PERF: --demo=perf_event (--evkind=academia|concurso|torneo) y --demo=perf_tour: medir los tirones
		"perf_event", "perf_tour":
			_perf_demo(_demo)
		# --- end R6 PERF
		_:
			_demo_scene(_demo)

func _demo_scene(name: String) -> void:
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 3
	Game.gold = 120
	Game.renombre = 14
	Game.upgrades = {"alfombra": true, "cojin": true, "huerto": true, "farolillos": true}
	Game.discovered["ojo_nocturno"] = 6
	Game.discovered["balsamo_helado"] = 5
	Game.potions = [{"id": "ojo_nocturno", "potency": 6}, {"id": "balsamo_helado", "potency": 4}, {"id": "sueno_profundo", "potency": 7}]
	for id in Data.INGREDIENT_ORDER:
		Game.stock[id] = 4 if Game.ingredient_unlocked(id) else 0
	phase = Phase.OPEN
	_refresh_all()
	ui.set_gameplay_visible(true)
	world.set_time(0.45 if name != "night" else 0.95, false)
	_update_time_label(0.45)
	match name:
		"dialog", "night":
			current = {"kind": "hero", "who": "lirien", "potion": "ojo_nocturno", "text": Data.HEROES["lirien"][0]["text"], "hint": Data.HEROES["lirien"][0]["hint"], "thanks": "", "chapter": 0}
			customer = Actor.new()
			world.add_child(customer)
			customer.setup("lirien")
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			_talk_request()
		# --- R3 BENCH: el banco del caldero. "brew": Tomás espera y hay dos ingredientes; "bench": vacío;
		# "bench3": tres ingredientes (caldero ancho); "stir" / "benchstir": removiendo; "ticket": un cliente con su
		# ticket (pista en iconos); "hud": la tienda en el mostrador con el HUD nuevo (estante con runas si existen)
		"brew", "bench", "bench3", "stir", "benchstir", "benchready", "benchink":
			if name == "benchink":
				Game.unlock_magic()
				ov.close(false)
			if name == "bench3" or name == "benchstir" or name == "benchready":
				Game.upgrades["caldero_ancho"] = true
			if name != "bench":
				current = {"kind": "villager", "who": "granjero", "potion": "vigor_verde", "text": Data.VILLAGER_REQUESTS[5]["text"], "hint": Data.VILLAGER_REQUESTS[5]["hint"]}
				customer = Actor.new()
				world.add_child(customer)
				customer.setup(Story.sprite_id("granjero"))
				customer.global_position = ShopWorld.P_CUSTOMER
				customer.face(-1)
				customer_ready = true
				hint_given = true
				ui.order_who = "granjero"
				ui.show_order(Story.char_name("granjero"), current["text"], current["hint"])
			world.walker.teleport(ShopWorld.STATIONS["caldero"]["x"], -1)
			world.snap_camera()
			await get_tree().create_timer(0.3).timeout
			open_brew()
			var ings: Array = []
			match name:
				"brew":
					ings = ["raiz_mandragora", "ambar_abeja"]
				"bench3", "benchstir", "benchready":
					ings = ["raiz_mandragora", "hongo_violeta", "ambar_abeja"]
				"benchink":
					ings = ["ceniza_dragon" if Game.ingredient_unlocked("ceniza_dragon") else "ambar_abeja", "ambar_abeja"]
				"stir":
					ings = ["hongo_violeta", "ambar_abeja"]
			for id in ings:
				brew.throw(id)
				await get_tree().create_timer(0.25).timeout
			await get_tree().create_timer(0.7).timeout
			if name == "stir" or name == "benchstir" or name == "benchready":
				_on_brew()
				if name == "benchready":
					await get_tree().create_timer(0.6).timeout
					if brew._stir:
						brew._stir.press()
			elif name == "bench":
				brew._on_jar_hover("hongo_violeta", true)
		"stirold":
			ov.show_stir(1.0)
		"ticket", "hud":
			Game.potions = [{"id": "vigor_verde", "potency": 7, "rune": "prisa", "rune_stars": 3}, {"id": "ojo_nocturno", "potency": 6}, {"id": "balsamo_helado", "potency": 4, "rune": "calma", "rune_stars": 2}, {"id": "sueno_profundo", "potency": 5}]
			Game.potions_changed.emit()
			var who := "panadera" if name == "ticket" else "nyra"
			for q in Data.VILLAGER_REQUESTS:
				if q["who"] == who and current.is_empty() and (who != "panadera" or q["potion"] == "sueno_profundo"):
					current = q.duplicate()
			current["kind"] = "villager"
			customer = Actor.new()
			world.add_child(customer)
			customer.setup(Story.sprite_id(who))
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			hint_given = true
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
			ui.order_who = who
			ui.show_order(Story.char_name(who), current["text"], current["hint"], ["prisa", "calma"] if name == "ticket" else [])
			if name == "hud":
				ui.show_tip("Tap it on the [b]shelf[/b] to hand it over.", 0.0)
		# --- end R3 BENCH
		# --- WORLD: el mercado es un lugar; "upgrades" abre el puesto de Mabel
		"market", "upgrades", "vendor":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			_switch_place(true, false)
			if name == "market":
				market.walker.teleport(5.6, 1)
				market.snap_camera()
				market.walker.go_to(9.0)
			else:
				ov.show_market("morning", "mabel" if name == "upgrades" else "ilse")
		"trip":
			phase = Phase.MORNING
			_update_top_buttons()
			_trip_check()
		"library":
			phase = Phase.MORNING
			ui.set_time_label("Morning")
			world.set_time(0.0, false)
			world.walker.teleport(-7.2, -1)
			world.snap_camera()
			world.go_station("biblioteca")
		"overview":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			world.walker.teleport(-11.0, 1)
			world.cam_fixed_x = -4.1
			world._cam_base = Vector3(0.0, 6.6, 25.0)
			world._cam_target = Vector3(0.0, 1.9, -2.0)
			world.camera.attributes.dof_blur_far_enabled = false
			world.camera.attributes.dof_blur_near_enabled = false
		# --- end WORLD
		# --- R3 MAGIC3: capturas del libro de runas, del encantamiento y del ticket con runa; pruebas de la magia
		# --- R3 MERGE: "ticket" ya era una demo de UI-BENCH (va antes en este match): la de MAGIC3 es "runeticket"
		"grimoire", "enchant", "enchanted", "runeticket", "magictest", "oldsave", "firstbook":
			_magic_demo("ticket" if name == "runeticket" else name)
		# --- end R3 MAGIC3
		# --- R3 MERGE: el encargo de día (UI-PAPER: precios x2) abierto en la tienda, con un cliente esperando
		"dayorder":
			Game.gold = 140
			ov.show_market("day")
		# --- R3 MERGE: la carta de la mañana que cuenta cómo le fue a la runa (Greta: su pedido con Prisa, 3 estrellas)
		"runeletter":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			Game.unlock_magic()
			ov.close(false)
			var rq: Dictionary = {}
			for q in Data.RUNE_REQUESTS:
				if q["who"] == "panadera" and rq.is_empty():
					rq = q.duplicate()
			rq["kind"] = "villager"
			var rit := {"kind": "potion", "id": String(rq["potion"]), "potency": 7, "rune": String(rq["runes"][0]), "rune_stars": 3}
			var ro := Story.make_outcome(rq, rit, true, Story.price_of(rit, rq))
			ro["via"] = "letter"
			ro["due"] = Game.day
			Game.schedule_outcome(ro)
			_morning_mail()
		# --- STORY: el correo de la mañana, la reacción al recibir una poción y una visita con noticias (capturas)
		"mail", "complaint":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			var demo_items := [["panadera", "sueno_profundo", 8, true], ["nyra", "tonico_brio", 5, true], ["granjero", "vigor_verde", 6, false]]
			if name == "complaint":
				demo_items = [["granjero", "vigor_verde", 6, false]]
			for d in demo_items:
				var r: Dictionary = {}
				for q in Data.VILLAGER_REQUESTS:
					if q["who"] == d[0] and q["potion"] == d[1]:
						r = q.duplicate()
				r["kind"] = "villager"
				var it := {"kind": "potion", "id": "ojo_nocturno" if not d[3] else d[1], "potency": d[2]}
				var o := Story.make_outcome(r, it, d[3], Story.price_of(it))
				o["via"] = "letter"
				o["due"] = Game.day
				Game.schedule_outcome(o)
			_morning_mail()
		"react", "visit":
			var who := "marta" if name == "react" else "lirien"
			customer = Actor.new()
			world.add_child(customer)
			customer.setup(Story.sprite_id(who))
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
			if name == "react":
				for q in Data.VILLAGER_REQUESTS:
					if q["who"] == who and q["potion"] == "sueno_profundo":
						current = q.duplicate()
				current["kind"] = "villager"
				Game.met[who] = true
				_hand_over({"kind": "potion", "id": "sueno_profundo", "potency": 8})
			else:
				var req := Game._hero_request("lirien", 0)
				var it := {"kind": "potion", "id": "ojo_nocturno", "potency": 6}
				var o := Story.make_outcome(req, it, true, Story.price_of(it))
				o["via"] = "visit"
				Game.schedule_outcome(o)
				current = {"kind": "return", "who": who, "outcome": o}
				_talk_return()
			get_tree().create_timer(0.6).timeout.connect(func(): ui._advance())
		# --- end STORY
		# --- INTEGRATE: la tienda mientras ella camina (captura): una clienta del elenco nuevo espera en el mostrador,
		# el grimorio ya está abierto y ella cruza la tienda hasta el mostrador
		"walk":
			Game.renombre = 34
			Game.unlock_magic()   # --- R3 MAGIC3: sin pergaminos
			ui.refresh_hud()
			for q in Data.VILLAGER_REQUESTS:
				if q["who"] == "nyra" and current.is_empty():
					current = q.duplicate()
			current["kind"] = "villager"
			customer = Actor.new()
			world.add_child(customer)
			customer.setup(Story.sprite_id("nyra"))
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			hint_given = true
			ui.show_order(Story.char_name("nyra"), current["text"], current["hint"])   # --- R3 MAGIC3: (sin show_rack_tab)
			world.walker.teleport(-7.4, 1)
			world.snap_camera()
			world.go_station("mostrador")
		# --- end INTEGRATE
		# --- R3 WORLD3: capturas del mostrador transversal. "counter": ella de su lado y una clienta del otro, con el
		# pedido ("deliver": además le entrega la primera poción del estante: la poción aparece sobre el mostrador);
		# "flap": por la mañana, ella cruza el mostrador por la trampilla camino de la puerta (se para en el hueco)
		"counter", "deliver":
			for q in Data.VILLAGER_REQUESTS:
				if q["who"] == "nyra" and current.is_empty():
					current = q.duplicate()
			current["kind"] = "villager"
			customer = Actor.new()
			world.add_child(customer)
			customer.setup(Story.sprite_id("nyra"))
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			hint_given = true
			ui.show_order(Story.char_name("nyra"), current["text"], current["hint"])
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
			if name == "deliver":
				await get_tree().create_timer(0.5).timeout
				_deliver(0)
		"flap":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
			await get_tree().create_timer(0.6).timeout
			world.walker.go_to(ShopWorld.COUNTER_X + 0.12, 1)
		"doorside":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			world.walker.teleport(float(ShopWorld.STATIONS["puerta"]["x"]), -1)
			world.snap_camera()
		# prueba del teclado: mantiene D (tecla física, como el jugador) desde su sitio del mostrador hasta el lado de la
		# puerta, cruzando la trampilla, y vuelve con A; imprime dónde está, en qué sector y cómo está la trampilla
		"walktest":
			phase = Phase.MORNING
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			await get_tree().create_timer(0.3).timeout
			for key in [KEY_D, KEY_A]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				ev.keycode = key
				ev.pressed = true
				Input.parse_input_event(ev)
				for i in 12:
					await get_tree().create_timer(0.25).timeout
					var p := world.alchemist.position
					print("WALK %s t=%.2f x=%.2f z=%.2f sector=%s flap=%.0f cam=%.2f" % [OS.get_keycode_string(key), i * 0.25,
						p.x, p.z, world.current_station(), rad_to_deg(world._flap_a), world._cam_x])
				ev = ev.duplicate()
				ev.pressed = false
				Input.parse_input_event(ev)
				await get_tree().create_timer(0.3).timeout
			get_tree().quit()
		# la fuente del mercado: "fountain" = la vista del juego con ella junto a la plaza; "fountain_close" = de cerca
		"fountain", "fountain_close":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			_switch_place(true, false)
			market.walker.teleport(MarketWorld.FOUNTAIN_POS.x - 0.6, 1)
			market.snap_camera()
			if name == "fountain_close":
				market.set("_cam_base", Vector3(0.0, 2.9, 5.4))
				market.set("_cam_target", Vector3(0.0, 1.0, -3.3))
				market.camera.attributes.dof_blur_far_enabled = false
				market.camera.attributes.dof_blur_near_enabled = false
		# --- end R3 WORLD3
		# --- R4 PACE: la fila, el reloj, quien se cansa, la fila llena, el cierre y el libro de cuentas
		"queue", "annoyed", "fullqueue", "closing", "ledger", "pacetest", "pacelate":
			_pace_demo(name)
		# --- end R4 PACE
		# --- R4 RAVEN: capturas y pruebas de Krápido (la ventanilla, la bola de cristal, Graznido)
		"krapido_shop", "krapido_ball", "krapido_take", "krapido_arrive", "krapido_counter", "krapido_market", "krapido_letter", "krapido_test", "krapido_input", "krapido_empty":
			_krapido_demo(name)
		# --- end R4 RAVEN
		# --- R5 EN-UI: capturas de los papeles que no tenían demo: los ajustes y el «Start over?» del título
		"settings":
			ov.show_settings()
		"confirm":
			ui.set_gameplay_visible(false)
			ov.show_title(true)
			ov._confirm_new(true)
		# --- end R5 EN-UI
		"book":
			ov.show_book()
		"journal":
			Game.hero_progress["lirien"] = 1
			Game.hero_progress["bram"] = 2
			Game.journal = [{"day": 1, "hero": "lirien", "chapter": 0, "text": Data.HEROES["lirien"][0]["journal"]},
				{"day": 1, "hero": "bram", "chapter": 0, "text": Data.HEROES["bram"][0]["journal"]},
				{"day": 2, "hero": "bram", "chapter": 1, "text": Data.HEROES["bram"][1]["journal"]}]
			ov.show_journal()
		"summary":
			Game.today = {"earned": 86, "renombre": 9, "sold": 4, "new_recipes": ["ojo_nocturno"], "journal": [{"day": 3, "hero": "lirien", "text": Data.HEROES["lirien"][0]["journal"]}]}
			world.set_time(1.0, false)
			ov.show_summary(3, Game.today)
		"levelup":
			ov.show_level_up(2)
		# --- R4 RANK: el Escalafón del Gremio. "ranking": el tablón a mitad de camino (día 12); "rankmail": el correo con la
		# línea del Escalafón; "gaceta": la Gaceta del día 10; "ranksummary": la hoja de la noche con el puesto;
		# "ending": la fiesta del puesto 1 en automático (capturas a distintos cuadros) y los créditos; "credits": solo
		# los créditos; "rankpad": el tablón elegido con el teclado (↓ ↓ → ↑)
		"ranking", "rankmail", "gaceta", "gaceta5", "ranksummary", "ending", "credits", "rankpad", "rankinput", "ranktrophy", "rankmailtop":
			_rank_demo(name)
		# --- end R4 RANK
		# --- R4 SCENES: los escenarios de los eventos (--demo=scene_academia / scene_concurso / scene_torneo)
		"scene_academia", "scene_concurso", "scene_torneo":
			_scenes_demo(name.substr(6))
		"scenes_check":
			_scenes_check()
		# --- end R4 SCENES
		# --- R5 WORLD: el comprobador de las paredes que tiemblan (z-fighting) en todas las vistas 3D:
		# --demo=zcheck --view=<vista> [--out=<carpeta>] [--shots [--zonly]] [--film] [--signs] [--stills] [--web]
		# (ver scripts/world/zcheck.gd)
		"zcheck":
			ZCheck.run(self)
		# --- end R5 WORLD

# --- R4 SCENES: vista previa de los escenarios de los eventos (scripts/world/event_scenes.gd) -----------------------
## El escenario de un evento como lo verá el juego: la tienda escondida, la cámara del escenario, ella en su puesto
## (marcador "Player"), público (set_crowd), la fila de visitantes en "Queue0".."Queue5" y, en el concurso, el jurado
## en "Judge0".."Judge2". Sin el HUD de la tienda (el HUD del evento es de EVENTS-LOGIC). --cheer: el público celebra.
## Como en el catálogo de EVENTS-LOGIC (events.gd: crowd, visitors y el jurado), para que la captura sea lo que se verá.
const SCENES_DEMO_CROWD := {
	"academia": ["roxa", "tobias", "anselmo", "anciano", "lirien", "elda"],
	"concurso": ["fizz", "panadera", "granjero", "anciano", "marta", "mabel", "vianne", "hassim", "borin", "pip"],
	"torneo": ["isolde", "vianne", "hassim", "mabel", "anselmo", "panadera", "granjero", "nyra", "borin"],
}
const SCENES_DEMO_QUEUE := {
	"academia": ["pip", "kit", "wren", "sylwen", "zaria", "nyra"],
	"concurso": [],
	"torneo": ["aldric", "brann", "ragnar", "bram", "pip", "kit"],
}
const SCENES_DEMO_JUDGES := ["elda", "lirien", "grumm"]

func _scenes_demo(kind: String) -> void:
	var sc: Node3D = EventScenes.build(kind)
	add_child(sc)
	_set_place_on(world, false)
	_set_place_on(market, false)
	(sc.get_node("Camera") as Camera3D).make_current()
	ui.set_gameplay_visible(false)
	ui.hide_dialog()
	open_btn.visible = false
	trip_btn.visible = false
	var her := Actor.new()
	her.name = "Alquimista"
	sc.add_child(her)
	her.setup("alquimista")
	var pm: Marker3D = sc.get_node("Player")
	her.position = pm.position
	her.face(int(pm.get_meta("face", 1)))
	var q_ids: Array = SCENES_DEMO_QUEUE[kind]
	var used := {}
	for i in q_ids.size():
		var qm: Marker3D = sc.get_node("Queue%d" % i)
		var a := Actor.new()
		sc.add_child(a)
		a.setup(Story.sprite_id(q_ids[i]))
		a.quiet = true
		a.position = qm.position
		a.face(int(qm.get_meta("face", -1)))
		used[q_ids[i]] = true
	if kind == "concurso":
		var judges: Array = SCENES_DEMO_JUDGES
		for i in 3:
			var jm: Marker3D = sc.get_node("Judge%d" % i)
			var j := Actor.new()
			sc.add_child(j)
			j.setup(Story.sprite_id(judges[i]))
			j.quiet = true
			j.position = jm.position
			j.face(int(jm.get_meta("face", -1)))
			used[judges[i]] = true
	var ids: Array = []
	for id in SCENES_DEMO_CROWD[kind]:
		if not used.has(id):
			ids.append(id)
	var placed: Array = sc.set_crowd(ids)
	print("SCENES %s: público=%d/%d fila=%d" % [kind, placed.size(), sc.crowd_capacity(), q_ids.size()])
	# para ajustar la cámara: --cam=x,y,z,mx,my,mz (posición y punto al que mira) y --fov=grados
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cam="):
			var v: PackedFloat64Array = arg.substr(6).split_floats(",")
			if v.size() == 6:
				sc.set_view(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
		elif arg.begins_with("--fov="):
			(sc.get_node("Camera") as Camera3D).fov = float(arg.substr(6))
	if "--cheer" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		sc.cheer(true)

## --demo=scenes_check (funciona sin pantalla, --headless): construye los tres escenarios, comprueba los nodos del
## contrato (Player, Bench, Queue0..Queue5, Judge0..Judge2 en el concurso, Camera), set_crowd y cheer; imprime
## "SCENES CHECK errors=N" y sale.
func _scenes_check() -> void:
	var errors := 0
	for kind in EventScenes.KINDS:
		var t0 := Time.get_ticks_msec()
		var sc: Node3D = EventScenes.build(kind)
		var ms := Time.get_ticks_msec() - t0
		add_child(sc)
		var need := ["Player", "Bench", "Camera"]
		for i in 6:
			need.append("Queue%d" % i)
		if kind == "concurso":
			for i in 3:
				need.append("Judge%d" % i)
		for n in need:
			var node := sc.get_node_or_null(n)
			var ok: bool = node != null and ((node is Camera3D) if n == "Camera" else (node is Marker3D))
			if ok and n != "Camera" and not node.has_meta("face"):
				ok = false
			if not ok:
				errors += 1
				print("SCENES CHECK %s: falta o no sirve %s" % [kind, n])
		var placed: Array = sc.set_crowd(["lirien", "bram", "kit", "no_existe", "lirien"])
		if placed.size() != 4:
			errors += 1
			print("SCENES CHECK %s: set_crowd puso %d (esperaba 4)" % [kind, placed.size()])
		var again: Array = sc.set_crowd(["pip"])
		if again.size() != 1:
			errors += 1
		sc.cheer(true)
		sc.cheer(false)
		for i in 3:
			await get_tree().process_frame
		print("SCENES CHECK %s: ok (construido en %d ms, %d nodos, público hasta %d)" % [kind, ms, _count_nodes(sc), sc.crowd_capacity()])
		sc.queue_free()
		await get_tree().process_frame
	print("SCENES CHECK errors=%d" % errors)
	get_tree().quit()

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
# --- end R4 SCENES

func _tutorial_demo() -> void:
	Engine.time_scale = 3.0
	_start_new()
	for i in 3:
		await get_tree().create_timer(1.5).timeout
		ui._advance()
		ui._advance()
	await get_tree().create_timer(3.0).timeout
	_open_shop()
	while not customer_ready:
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(2.0).timeout
	ui._advance()
	_on_choice("prepare")
	Engine.time_scale = 1.0
	await get_tree().create_timer(1.0).timeout
	_shot_frames = _frame + 3

## Simula clics reales del ratón sobre los frascos, el caldero y la gata para comprobar el picking 3D.
func _clicktest() -> void:
	Game.new_game_state()
	Game.tutorial_done = true
	phase = Phase.MORNING
	_refresh_all()
	ui.set_gameplay_visible(true)
	await get_tree().create_timer(1.0).timeout
	# --- R3 BENCH: la gata primero (con el banco abierto la tienda no se toca); el primer frasco se toca en la tienda
	# (camina, abre el banco y lo echa) y el segundo ya en el estante del banco
	await _clicktest_cat()
	for id in ["raiz_mandragora", "hongo_violeta"]:
		var sp := world.screen_pos(world.jars[id].global_position + Vector3(0, 0.3, 0))
		if _brew_open():
			sp = brew.jar_btns[id].get_global_rect().get_center()
		await _click_at(sp)
		await get_tree().create_timer(1.6).timeout
		print("CLICK jar ", id, " at ", sp, " -> contents=", contents, " bench=", _brew_open())
	# --- end R3 BENCH
	await get_tree().create_timer(0.5).timeout
	# --- R3 BENCH: el botón «Remover» del banco, un clic para acertar y «Embotellar»
	print("CLICK bench open=", _brew_open())
	var bp: Vector2 = brew.btns["stir"].get_global_rect().get_center()
	await _click_at(bp)
	await get_tree().create_timer(1.0).timeout
	print("CLICK brew -> stirring=", brew._stir != null)
	if brew._stir:
		await _click_at(Vector2(960, 540))
	await get_tree().create_timer(2.0).timeout
	print("CLICK ready=", brew_ready)
	await _click_at(brew.btns["bottle"].get_global_rect().get_center())
	await get_tree().create_timer(2.0).timeout
	print("POTIONS ", Game.potions)
	get_tree().quit()

func _clicktest_cat() -> void:
	var cp := world.screen_pos(world.cat.global_position + Vector3(0, 0.25, 0))
	var from := world.camera.project_ray_origin(cp)
	var dir := world.camera.project_ray_normal(cp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 50.0)
	q.collide_with_areas = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	print("RAY cat ", cp, " hit=", hit.get("collider"), " parent=", hit.get("collider").get_parent() if hit.has("collider") else null)
	await _click_at(cp)
	await get_tree().create_timer(0.3).timeout
	print("CLICK cat -> petted_day=", Game.cat_petted_day)

func _click_at(sp0: Vector2) -> void:
	var vp := get_viewport()
	# convertir de coordenadas del viewport a coordenadas de la ventana
	var sp := vp.get_final_transform() * sp0
	var mm := InputEventMouseMotion.new()
	mm.position = sp
	mm.global_position = sp
	Input.parse_input_event(mm)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = sp
	down.global_position = sp
	Input.parse_input_event(down)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = sp
	up.global_position = sp
	Input.parse_input_event(up)
	await get_tree().physics_frame

## Juega días completos solo, para detectar errores. Elige siempre la receta correcta.
func _autoplay() -> void:
	Engine.time_scale = 6.0
	Game.new_game_state()
	if _bot_load_path != "":   # --- R4 MERGE: --loadsave=<archivo>: el bot sigue una partida guardada (p. ej. de la ronda 3)
		var src := FileAccess.get_file_as_string(_bot_load_path)
		var fw := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		fw.store_string(src)
		fw = null
		var ok_load := Game.load_game()
		print("AUTOPLAY partida cargada=", ok_load, " de ", _bot_load_path, " día=", Game.day, " oro=", Game.gold, " renombre=", Game.renombre,
			" nivel=", Game.level(), " pociones=", Game.potions.size(), " runas=", Game.known_runes(), " pendientes=", Game.pending.size(),
			" escalafón=", Ranking.position(), "/", Ranking.size(), " plumas=", "%.2f" % Game.plumas(), " eventos=", Game.ev_count,
			" boca_a_boca=", Game.pace_wom, " krápido=", Game.krapido_on())
	if _krapido_bot:   # --- R4 RAVEN: con la Ventanilla Krápido desde el día 1 (--krapido)
		Game.upgrades["krapido"] = true
	_rank_bot_start()   # --- R4 RANK: --rankstart=N (probar el final dentro del bucle del bot)
	_bot_watchdog()   # --- R4 MERGE: si un día se atasca, imprime el estado, lo cuenta como error y desatasca
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--evtoday="):   # --- R4 MERGE (prueba): un evento reservado para el primer día del bot
			Events.make_invite(a.substr(10))
			Game.ev_booked = Game.ev_invite
			Game.ev_invite = {}
			Game.ev_booked["day"] = Game.day
			if Ranking.hist.size() > 0:   # con --rankstart: 20 puntos detrás de la primera (la medalla la pone primera)
				var best := 0.0
				for id in Ranking.scores:
					if id != Ranking.ME:
						best = maxf(best, float(Ranking.scores[id]))
				Ranking.scores[Ranking.ME] = best - 20.0
	_refresh_all()
	var days := maxi(1, _autoplay_days)
	var errors := 0
	var rune_stats := {"orders": 0, "enchanted": 0, "missing": 0}   # --- R3 MAGIC3
	var pace_rows: Array = []   # --- R4 PACE: una fila por día (llegaron, atendidos, se cansaron, fila llena...)
	print("AUTOPLAY bot=", _bot)   # --- R4 PACE
	for d in days:
		# --- R4 MERGE: después de la noche, _sleep() ya empezó el día siguiente: antes el bot lo empezaba otra vez (dos
		# mañanas a la vez: dos invitaciones, dos correos, y la segunda podía seguir con la tienda ya abierta)
		while _ending_running:   # --- R4 MERGE: nunca empezar un día mientras se juega el final del puesto 1
			await get_tree().create_timer(0.5).timeout
		if d == 0 or phase != Phase.MORNING:
			_begin_day()
		await get_tree().create_timer(2.0).timeout
		if ov.is_open() and ov.current != "invite":   # --- R4 EVENTS: la invitación se contesta (abajo)
			ov.close(false)
		# --- R4 EVENTS: la invitación (acepta la primera, rechaza la siguiente) y el día del evento (lo juega entero)
		await _bot_events_morning()
		if phase == Phase.EVENT:
			await _bot_play_event()
			while phase != Phase.MORNING:
				await get_tree().create_timer(0.5).timeout
				if ov.current == "summary":
					print("AUTOPLAY: fin día ", Game.day, " (evento) oro=", Game.gold, " renombre=", Game.renombre, " nivel=", Game.level(), " evento=", Game.today.get("event", {}))
					_bot_rank_line()   # --- R4 MERGE: el puesto también la noche del evento
					ov.close(false)
					_sleep()
					await get_tree().create_timer(3.0).timeout
					while _ending_running:   # --- R4 MERGE: llegó al puesto 1 la noche de un evento: el final termina antes
						await get_tree().create_timer(0.5).timeout   # (si no, el bot empezaba un día durante la fiesta)
					break
				if ov.is_open() and ov.current == "levelup":
					ov.close()
			continue
		# --- end R4 EVENTS
		# compra algo de stock y alguna mejora
		var keep := 5 if _bot == "good" else 4   # --- R4 PACE: el bot rápido compra un poco más (días con más gente)
		for id in Game.unlocked_ingredients():
			while Game.stock.get(id, 0) < keep and Game.gold > 30:   # --- R4 PACE: keep (antes 4)
				Game.buy_ingredient(id, 1)
		for u in Data.UPGRADE_ORDER:
			if Game.gold > Data.UPGRADES[u]["cost"] + 40:
				Game.buy_upgrade(u)
		# --- R3 MAGIC3: desde el día 2 abre el grimorio (la runa de Prisa); compra tinta para sus runas y la página de Tobías
		if Game.day >= 2 and not Game.magic_unlocked:
			await _finish_overlays()
			var opened_g: bool = await grimoire.bot_open()
			if not opened_g:   # --- R4 RAVEN: un segundo correo (los rumores) pudo abrirse mientras caminaba: otra vez
				await _finish_overlays()
				opened_g = await grimoire.bot_open()
			if not opened_g:
				print("AUTOPLAY: no pudo abrir el grimorio")
				errors += 1
			print("AUTOPLAY: grimorio abierto, runas=", Game.known_runes())
		if Game.magic_unlocked:
			if Game.gold > 45 and not Game.rune_known("dulzor"):
				Game.buy_item("pagina_dulzor")
			for r in Game.known_runes():
				while Game.item_count(Game.rune_ink(r)) < 2 and Game.gold > 30:
					Game.buy_item(Game.rune_ink(r))
		await _finish_overlays()
		# --- end R3 MAGIC3
		# --- R4 PACE: la mañana no tiene reloj: el bot rápido deja hechas algunas pociones de las que más se piden
		if _bot == "good" and Game.tutorial_done:
			await _bot_prebrew(3)
		_open_shop()
		errors += await _bot_open_day(rune_stats)   # --- R4 PACE: atiende con el reloj corriendo (ver más abajo)
		# fin del día
		while phase != Phase.MORNING:
			await get_tree().create_timer(0.5).timeout
			if ov.current == "summary":
				print("AUTOPLAY: fin día ", Game.day, " oro=", Game.gold, " renombre=", Game.renombre, " nivel=", Game.level(), " pociones=", Game.discovered.keys())
				# --- R4 PACE: la fila de este día
				var td := Game.today
				var row := "día %d  llegaron %2d  atendidos %2d  cansados %2d  fila_llena %2d  al_cerrar %d  sin_atender %d  espera %4.1f s  oro +%d  propinas %d  renombre %+d (-%d)  nivel %d  demanda %d/%d" % [
					Game.day, int(td.get("arrived", 0)), int(td.get("served", 0)), int(td.get("lost_tired", 0)),
					int(td.get("lost_full", 0)), int(td.get("lost_closed", 0)), int(td.get("declined", 0)),
					float(td.get("avg_wait", 0.0)), int(td.get("earned", 0)), int(td.get("speed_tips", 0)),
					int(td.get("renombre", 0)), int(td.get("renombre_lost", 0)), Game.level(),
					int(td.get("planned", 0)), int(td.get("roster", 0))]
				pace_rows.append(row)
				print("PACE ", _bot, " ", row)
				# --- end R4 PACE
				print("AUTOPLAY: krapido día ", Game.day, " entregas=", Game.today.get("deliveries", 0), " perdidas=", Game.today.get("deliveries_lost", 0), " plumas=", "%.2f" % float(Game.today.get("plumas", 0.0)))   # --- R4 RAVEN
				_bot_rank_line()   # --- R4 RANK
				ov.close(false)
				_sleep()
				await get_tree().create_timer(3.0).timeout
				while _ending_running:   # --- R4 RANK: el final (en automático) termina antes del día siguiente
					await get_tree().create_timer(0.5).timeout
				break
			if ov.is_open() and ov.current == "levelup":
				ov.close()
	errors += int(_bot_k["errors"])   # --- R4 RAVEN
	print("AUTOPLAY DONE errors=", errors + _bot_ev_errors + _bot_stuck, " day=", Game.day, " gold=", Game.gold, " level=", Game.level(), " journal=", Game.journal.size(), " pending=", Game.pending.size(), " met=", Game.met.size())   # --- STORY
	print("AUTOPLAY RUNAS pedidos=", rune_stats["orders"], " encantadas=", rune_stats["enchanted"], " sin_runa=", rune_stats["missing"], " runas=", Game.known_runes(), " tintas=", Game.items)   # --- R3 MAGIC3
	print("PACE TABLA bot=", _bot, " boca_a_boca=", snappedf(Game.pace_wom, 0.01))   # --- R4 PACE
	for r in pace_rows:
		print("PACE  ", r)
	print("AUTOPLAY KRAPIDO pedidos=", Game.krapido_stats["orders"], " entregados=", Game.krapido_stats["delivered"], " perdidos=", Game.krapido_stats["lost"],
		" plumas=", "%.2f" % Game.plumas(), " reseñas=", Game.krapido_reviews.map(func(r): return r["plumas"]), " errores_ventanilla=", _bot_k["errors"], " preparadas=", _bot_k["brewed"])   # --- R4 RAVEN
	print("AUTOPLAY EVENTOS invitaciones=", Game.ev_count, " respuestas=", Game.ev_answers, " jugados=", Game.ev_history, " trofeos=", Game.ev_trophies.size(), " errores_evento=", _bot_ev_errors)   # --- R4 EVENTS
	print("AUTOPLAY RANK puestos=", Ranking.hist.map(func(e): return int(e["pos"])), " final_visto=", Ranking.ending_seen)   # --- R4 RANK
	get_tree().quit()

# --- R3 MAGIC3: el bot elige la poción del estante: la del pedido con más runas pedidas y ninguna de más.
func _bot_pick_potion(want: String) -> int:
	var best := -1
	var best_k := -INF
	var need: Array = Game.order_runes(current)
	for i in Game.potions.size():
		var q: Dictionary = Game.potions[i]
		if q["id"] != want:
			continue
		var k := 0.0
		for r in Game.potion_rune_ids(q):
			k += 10.0 if need.has(r) else -1.0
		if k > best_k:
			best_k = k
			best = i
	return best

## Espera a que no quede ningún panel abierto (el correo, una subida de nivel...): el bot los cierra.
func _finish_overlays() -> void:
	# --- R4 PACE: la subida de nivel sale un cuadro DESPUÉS de cerrar el correo (_morning_mail): solo termina tras
	# unos cuadros seguidos sin panel (antes, a veces, el bot llegaba al grimorio con la subida de nivel abierta)
	var quiet := 0
	for i in 60:
		if not ov.is_open() or ov.current == "invite":   # --- R4 EVENTS: la invitación la contesta _bot_events_morning
			quiet += 1
			if quiet >= 4:
				return
			await get_tree().process_frame
			continue
		quiet = 0
		ov.close()
		await get_tree().create_timer(0.3).timeout
	# --- end R4 PACE
# --- end R3 MAGIC3

func _find_combo(want: String) -> Array:
	var ings := Game.unlocked_ingredients()
	var best := []
	var best_p := -1
	var n := ings.size()
	for i in n:
		for j in range(i, n):
			var c := [ings[i], ings[j]]
			var r := Game.evaluate(c)
			if r.get("potion", "") == want and _have(c) and r["potency"] > best_p:
				best = c
				best_p = r["potency"]
			if Game.cauldron_slots() >= 3:
				for k in range(j, n):
					var c3 := [ings[i], ings[j], ings[k]]
					var r3 := Game.evaluate(c3)
					if r3.get("potion", "") == want and _have(c3) and r3["potency"] > best_p:
						best = c3
						best_p = r3["potency"]
	if best.is_empty():
		# compra lo necesario
		for i in n:
			for j in range(i, n):
				var c := [ings[i], ings[j]]
				if Game.evaluate(c).get("potion", "") == want:
					for id in c:
						Game.buy_ingredient(id, 2, true)   # --- R3 MERGE: a mitad del día es el encargo (x2, UI-PAPER)
					if _have(c):
						return c
	return best

func _have(c: Array) -> bool:
	var need := {}
	for id in c:
		need[id] = need.get(id, 0) + 1
	for id in need:
		if Game.stock.get(id, 0) < need[id]:
			return false
	return true

# --- R4 PACE: el día abierto (5 minutos, de 9:00 a 18:00), la fila dentro de la tienda y la paciencia ----------------
# Al abrir, Game.plan_day arma la gente del día (quienes vuelven con noticias, aventureros y vecinos: el bloque STORY)
# y Game.pace_schedule dice a qué hora llega cada uno. Entran por la puerta y esperan en fila del lado de los clientes
# (ShopWorld.QUEUE_SPOTS). El primero pasa al mostrador cuando queda libre, y allí todo sigue como antes (lo que pide,
# el ticket, el caldero, la entrega). Cada uno tiene paciencia (un reloj de arena sobre la cabeza; la del mostrador,
# también en el ticket): se gasta mientras corre el reloj y, si se acaba, se va enfadado. Si la fila está llena, quien
# llega se asoma, suspira y se va. A las 18:00 se cierra: la fila se va a casa y se atiende a quien está en el
# mostrador; después, el libro de cuentas. El reloj se detiene con los menús de lectura (recetario, diario, correo,
# ajustes, el escalafón, el libro de runas para hojear) y sigue con los de trabajo (el banco del caldero, encantar en
# el grimorio, el encargo al mercado, la bola de cristal); no corre mientras se atiende el pedido del tutorial (día 1).
# Cada visitante es un diccionario: "id", "req" (su pedido, como los de plan_day), "actor", "p" (paciencia 0..1),
# "state" ("in" entrando, "line" en la fila, "step" pasando al mostrador, "counter", "peek" asomado a la fila llena,
# "out" saliendo), "line_secs" / "counter_secs" (cuánto aguanta), "t_in" (shop_t al entrar), "path" / "ev" / "speed" /
# "wait_move" (su caminar), "bubble" (el reloj de arena), "fidget", "ordered", "serving", "handed", "told", "declined",
# "t_served", "grumpy", "tutorial".

const PACE_IDLE_PULL := 6.0                    # segundos con la tienda vacía: entra uno de los de más (la ve libre)
const PACE_WORK_PANELS := ["market", "stir"]   # paneles de Overlays que NO detienen el reloj (y el grimorio al encantar)
const PACE_LINES := {
	"full": ["So many people!", "Phew, it's packed…", "Another day."],
	"tired": ["I'm leaving!", "So slow!", "I'm running late.", "Some other day."],
	"tired_counter": ["I can't wait any longer!", "Sorry, I have to go.", "I'm done waiting!"],
	"home": ["Back tomorrow.", "Aw, they closed.", "Tomorrow, then."],
	"grumpy": ["Finally!", "About time!", "Phew, at last."],
}

var shop_t := 0.0               # segundos de tienda abierta (0 .. Game.PACE_DAY_SECONDS)
var line: Array = []            # quienes esperan dentro, en orden
var _counter_v := {}            # el visitante del mostrador ({} si no hay)
var _leaving: Array = []        # quienes van saliendo (o se asoman a la fila llena y se van)
var _arrivals: Array = []       # a qué hora (shop_t) llega cada uno de los que faltan
var _pace_on := false           # la tienda está abierta y el reloj anda
var _pace_closing := false      # dieron las 18:00
var _pace_seq := 0
var _idle_t := 0.0
var _light_t := 0.0
var _last_chime := 0
var _tick_step := 0
var _pace_streams := {}
var _pace_players: Array = []
var _bot := "good"              # el perfil del bot de pruebas (--bot=good / --bot=slow)

## Los minutos del reloj de la tienda, desde la medianoche: 540 (9:00) al abrir ... 1080 (18:00) al cerrar. Antes de
## abrir da 540; de noche, 1080.
func shop_minutes() -> int:
	if phase == Phase.CLOSING:
		return Game.PACE_CLOSE_MIN
	if phase != Phase.OPEN:
		return Game.PACE_OPEN_MIN
	var f := clampf(shop_t / Game.PACE_DAY_SECONDS, 0.0, 1.0)
	return Game.PACE_OPEN_MIN + int(f * float(Game.PACE_CLOSE_MIN - Game.PACE_OPEN_MIN))

## El reloj de la tienda está detenido: hay un menú de lectura abierto, o se atiende el pedido del tutorial.
func clock_paused() -> bool:
	if _pace_tut_hold():
		return true
	if not ov.is_open():
		return false
	if ov.current in PACE_WORK_PANELS:
		return false
	if ov.current == "grimoire" and grimoire and grimoire.mode == "enchant":
		return false
	return true

## El primer día, hasta entregar el pedido del tutorial, el reloj espera.
func _pace_tut_hold() -> bool:
	return Game.day == 1 and not Game.tutorial_done

## La tienda está abierta y todavía no dieron las 18:00 (para el cuervo y quien lo necesite).
func shop_open() -> bool:
	return phase == Phase.OPEN and _pace_on and not _pace_closing

# ------------------------------------------------ abrir, llegar, la fila

## Abre el día: la gente del día y a qué hora llega; el reloj, a las 9:00.
func _pace_open() -> void:
	_pace_clear()
	var n := Game.pace_arrivals_today()
	queue = Game.plan_day(n + Game.pace_spares())
	# si el pueblo no da para tanto (quien espera noticias no viene), los que iban a volver mañana vienen hoy
	var short := n + Game.pace_spares() - queue.size()
	if short > 0 and not (Game.day == 1 and not Game.tutorial_done):
		for e in Game.pace_early_visits(mini(short, 3), queue):
			queue.insert(randi_range(mini(1, queue.size()), queue.size()), e)
	Game.today["planned"] = n               # cuántos tenían hora (la demanda del día)
	Game.today["roster"] = queue.size()     # cuántos podían venir (con los de más; el pueblo pone el tope)
	total_today = maxi(1, queue.size())
	served = 0
	_arrivals = Game.pace_schedule(mini(n, queue.size()))
	world.set_time(0.12, true)
	_update_time_label(0.12)
	ui.set_clock_visible(true)
	ui.set_clock(Game.PACE_OPEN_MIN, "open")
	ui.set_queue(0, 1.0)
	if Game.pace_market_day():
		ui.toast("Market day! Expect a crowd", UIKit.GOLD_BRIGHT, 3.0)
	else:
		ui.toast("Open! We close at %s" % UIKit.clock_words(Game.PACE_CLOSE_MIN), UIKit.GOLD_BRIGHT)   # --- R5 EN-UI: «6 PM»
	await get_tree().create_timer(1.2).timeout
	if phase != Phase.OPEN:
		return
	_pace_on = true
	shop_opened.emit()
	# el pedido del tutorial entra ya (el reloj espera a que se lo entregue); el siguiente, al poco de entregarlo
	if not queue.is_empty() and queue[0].get("tutorial", false):
		if not _arrivals.is_empty():
			_arrivals.pop_front()
		if not _arrivals.is_empty():
			_arrivals[0] = minf(float(_arrivals[0]), 10.0)
		_pace_arrive()

## La tienda vacía: sin fila, sin nadie en el mostrador ni saliendo, el reloj a cero y la puerta cerrada.
func _pace_clear() -> void:
	var all: Array = line + _leaving
	if not _counter_v.is_empty():
		all.append(_counter_v)
	for v in all:
		var a = v.get("actor")
		if is_instance_valid(a):
			a.queue_free()
	line = []
	_leaving = []
	_counter_v = {}
	_arrivals = []
	shop_t = 0.0
	_pace_on = false
	_pace_closing = false
	_idle_t = 0.0
	_light_t = 0.0
	_last_chime = 0
	_tick_step = 0
	world.door_reset()
	ui.set_order_patience(-1.0)
	ui.set_queue(0, 1.0)

func _pace_visitor(req: Dictionary) -> Dictionary:
	_pace_seq += 1
	return {"id": _pace_seq, "req": req, "actor": null, "p": 1.0, "state": "in",
		"line_secs": Game.pace_line_secs(req), "counter_secs": Game.pace_counter_secs(req), "t_in": shop_t,
		"path": [], "ev": [], "speed": 1.7, "wait_move": 0.0, "bubble": null, "fidget": randf_range(4.0, 8.0),
		"ordered": false, "serving": false, "handed": false, "told": false, "declined": false, "t_served": -1.0,
		"grumpy": false, "tutorial": bool(req.get("tutorial", false))}

func _pace_spot(i: int) -> Vector3:
	return ShopWorld.QUEUE_SPOTS[clampi(i, 0, ShopWorld.QUEUE_SPOTS.size() - 1)]

## Llega el siguiente de la lista del día: entra por la puerta y se pone al final de la fila (o, si está llena, se
## asoma, suspira y se va).
func _pace_arrive() -> void:
	if queue.is_empty() or phase != Phase.OPEN or _pace_closing:
		return
	var req: Dictionary = queue.pop_front()
	var who := String(req.get("who", ""))
	var v := _pace_visitor(req)
	var a := Actor.new()
	world.add_child(a)
	a.setup(Story.sprite_id(who), Data.CHARACTERS.get(who, {}).get("pixel", 0.04))
	a.global_position = ShopWorld.P_OUTSIDE
	v["actor"] = a
	Game.today["arrived"] = int(Game.today.get("arrived", 0)) + 1
	_idle_t = 0.0
	world.door_hold()
	if line.size() >= Game.PACE_QUEUE_MAX:
		v["state"] = "peek"
		Game.today["lost_full"] = int(Game.today.get("lost_full", 0)) + 1
		_pace_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_PEEK], ["", "release"], 1.5)
		_leaving.append(v)
		return
	line.append(v)
	_pace_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_PEEK, _pace_spot(line.size() - 1)], ["", "release", ""])
	if not v["tutorial"]:
		v["bubble"] = world.hourglass_for(a)
		_pace_tip("clock", "The clock is ticking: we close at [b]%s[/b]." % UIKit.clock_words(Game.PACE_CLOSE_MIN))   # --- R5 EN-UI
		if line.size() >= 2:
			_pace_tip("line", "Wait too long and [b]they leave[/b].")
	_pace_advance()

## Si el mostrador está libre, el primero de la fila pasa (su paciencia se renueva: ya lo atienden; si esperó demasiado
## llega de mal humor) y los demás avanzan un sitio, uno detrás de otro.
func _pace_advance() -> void:
	if phase != Phase.OPEN or not _counter_v.is_empty() or line.is_empty():
		return
	var v: Dictionary = line.pop_front()
	_counter_v = v
	v["grumpy"] = not v["tutorial"] and float(v["p"]) < 0.3
	v["p"] = 0.75 if v["grumpy"] else 1.0
	v["state"] = "step"
	if is_instance_valid(v.get("bubble")):
		v["bubble"].visible = false
	_pace_retarget(v, ShopWorld.P_CUSTOMER, 0.15)
	_pace_shift()

## Los de la fila van a su sitio (alguien la dejó), uno detrás de otro.
func _pace_shift() -> void:
	for i in line.size():
		var w: Dictionary = line[i]
		var target := _pace_spot(i)
		var path: Array = w["path"]
		var a: Actor = w["actor"]
		var dest: Vector3 = path.back() if not path.is_empty() else (a.global_position if is_instance_valid(a) else target)
		if dest.distance_to(target) > 0.05:
			_pace_retarget(w, target, 0.3 + 0.22 * float(i))

## Cambia a dónde va: si todavía está entrando, primero termina de cruzar la puerta.
func _pace_retarget(v: Dictionary, target: Vector3, delay := 0.0) -> void:
	var path: Array = v["path"]
	var ev: Array = v["ev"]
	var k := ev.find("release")
	if k >= 0:
		v["path"] = path.slice(0, k + 1) + [target]
		v["ev"] = ev.slice(0, k + 1) + [""]
	else:
		if path.is_empty():
			v["wait_move"] = delay
		v["path"] = [target]
		v["ev"] = [""]

func _pace_path(v: Dictionary, pts: Array, evs: Array, speed := 1.7) -> void:
	v["path"] = pts.duplicate()
	v["ev"] = evs.duplicate()
	v["speed"] = speed

## Un paso de quien camina (a velocidad fija, sin tweens: se le puede cambiar el camino a mitad).
func _pace_move(v: Dictionary, delta: float) -> void:
	var a = v.get("actor")
	if not is_instance_valid(a):
		return
	if float(v["wait_move"]) > 0.0:
		v["wait_move"] = float(v["wait_move"]) - delta
		return
	var path: Array = v["path"]
	if path.is_empty():
		return
	var target: Vector3 = path[0]
	var to: Vector3 = target - a.global_position
	to.y = 0.0
	var d := to.length()
	var step := float(v["speed"]) * delta
	if d <= maxf(step, 0.001):
		a.global_position = target
		path.pop_front()
		var ev: Array = v["ev"]
		var e: String = String(ev.pop_front()) if not ev.is_empty() else ""
		if e == "release":
			world.door_release()
		elif e == "hold":
			world.door_hold()
		if path.is_empty():
			a.set_walking(false)
			_pace_reached(v)
		return
	a.global_position += to / d * step
	a.set_walking(true)
	if absf(to.x) > 0.04:
		a.face(1 if to.x > 0.0 else -1)

func _pace_reached(v: Dictionary) -> void:
	var a: Actor = v["actor"]
	match String(v["state"]):
		"in", "line":
			v["state"] = "line"
			a.face(-1)
		"step":
			_pace_at_counter(v)
		"peek":
			_pace_peek(v)
		"out":
			_pace_remove(_leaving, v)
			a.queue_free()

## Llegó al mostrador: lo que antes hacía _next_customer al llegar (ella va a atender si está libre y él habla).
func _pace_at_counter(v: Dictionary) -> void:
	var vid := int(v["id"])
	if not _pace_still(vid) or phase != Phase.OPEN:
		return
	v["state"] = "counter"
	current = v["req"]
	customer = v["actor"]
	misses = 0
	hint_given = current.get("tutorial", false)
	customer_ready = false
	customer.face(-1)
	customer.emote("note" if current.get("kind", "") == "return" else "excl", 1.2)   # --- STORY: quien vuelve trae noticias
	# --- INTEGRATE: si iba al estante por un frasco tocado de lejos, primero lo echa al caldero
	await _finish_jar_trip()
	if not _pace_still(vid) or phase != Phase.OPEN:
		return
	# --- WORLD: si está libre, la alquimista va al mostrador a atender
	if not busy and not ov.is_open() and not ui.dialog_open() and not world.at_station("mostrador") and not _brew_open() and not _ball_open():   # --- R4 RAVEN (merge): ni con la bola abierta
		var reached: bool = await world.go_station("mostrador")
		if not reached and _jar_trip:
			await _finish_jar_trip()
			if _pace_still(vid) and not busy and not ov.is_open() and not ui.dialog_open():
				await world.go_station("mostrador")
		if not _pace_still(vid) or phase != Phase.OPEN:
			return
	if world.at_station("mostrador") and not busy:
		world.alchemist.face(1)
	await get_tree().create_timer(0.5).timeout
	if not _pace_still(vid) or phase != Phase.OPEN:
		return
	customer_ready = true
	if current.get("kind", "") == "return":   # --- STORY: quien vuelve a contar cómo le fue
		_talk_return()
	else:
		_talk_request()

## La fila está llena: se queda mirando un momento desde la puerta, suspira y se va.
func _pace_peek(v: Dictionary) -> void:
	var a: Actor = v["actor"]
	a.face(-1)
	a.emote("sigh", 1.4)
	world.blurt(a, Story.pick(PACE_LINES["full"]))
	_pace_sfx("pace_sigh", -9.0)
	await get_tree().create_timer(1.4).timeout
	if not is_instance_valid(a) or String(v["state"]) != "peek":
		return
	v["state"] = "out"
	world.door_hold()
	_pace_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_OUTSIDE], ["", "release"], 1.6)

## Sale de la tienda: un paso atrás (por detrás de la fila), la puerta y fuera. Si aún estaba entrando, se da la vuelta.
func _pace_exit(v: Dictionary, speed := 1.7, delay := 0.0) -> void:
	var holding := (v["ev"] as Array).has("release")   # no terminó de entrar: la puerta sigue abierta por él
	v["state"] = "out"
	if is_instance_valid(v.get("bubble")):
		v["bubble"].visible = false
	var a = v.get("actor")
	if not is_instance_valid(a):
		_pace_remove(_leaving, v)
		return
	if holding:
		_pace_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_OUTSIDE], ["", "release"], speed)
	else:
		var p: Vector3 = a.global_position
		var back := ShopWorld.P_EXIT_BACK if p.distance_to(ShopWorld.P_CUSTOMER) < 0.35 else Vector3(clampf(p.x, 2.2, 4.6), 0.0, -2.42)
		_pace_path(v, [back, ShopWorld.P_DOOR_IN, ShopWorld.P_OUTSIDE], ["hold", "", "release"], speed)
	v["wait_move"] = delay
	if not _pace_has(_leaving, v):
		_leaving.append(v)

func _pace_has(arr: Array, v: Dictionary) -> bool:
	for w in arr:
		if int(w["id"]) == int(v["id"]):
			return true
	return false

func _pace_remove(arr: Array, v: Dictionary) -> void:
	for i in arr.size():
		if int(arr[i]["id"]) == int(v["id"]):
			arr.remove_at(i)
			return

## Sigue siendo el mismo visitante en el mostrador (vid = su id; -1 = ninguno, como en las capturas).
func _pace_still(vid: int) -> bool:
	return int(_counter_v.get("id", -1)) == vid

# ------------------------------------------------ en el mostrador: pedir, entregar, irse

## Pidió (Preparar): desde ahora gasta paciencia en el mostrador, que se ve en el ticket.
func _pace_ordered() -> void:
	var v := _counter_v
	if v.is_empty() or v.get("ordered", false):
		return
	v["ordered"] = true
	v["counter_secs"] = Game.pace_counter_secs(current)
	if is_instance_valid(v.get("bubble")) and not v["tutorial"]:
		v["bubble"].visible = true

## Mientras se le entrega la poción no se cansa (on = false si la entrega no llegó a hacerse).
func _pace_set_serving(on: bool) -> void:
	if not _counter_v.is_empty():
		_counter_v["serving"] = on

## No se le puede atender: se despide (no se cansa mientras tanto). Devuelve su id (-1 si no hay visitante).
func _pace_decline() -> int:
	if _counter_v.is_empty():
		return -1
	_counter_v["declined"] = true
	_counter_v["serving"] = true
	return int(_counter_v["id"])

## Recibió su poción: queda atendido. Devuelve la propina por rapidez (según la paciencia que le quedaba).
func _pace_handed(price: int) -> int:
	var v := _counter_v
	if v.is_empty():
		return 0
	v["handed"] = true
	v["serving"] = true
	if float(v["t_served"]) < 0.0:
		v["t_served"] = shop_t
	if is_instance_valid(v.get("bubble")):
		v["bubble"].visible = false
	if v["tutorial"] or not v.get("ordered", false):
		return 0
	var tip := Game.pace_speed_tip(price, float(v["p"]))
	if tip > 0:
		Game.today["speed_tips"] = int(Game.today.get("speed_tips", 0)) + tip
	return tip

## Quien volvió a contar cómo le fue ya lo contó: atendido (si además pide algo, eso es otro pedido).
func _pace_told() -> void:
	var v := _counter_v
	if v.is_empty():
		return
	v["told"] = true
	if float(v["t_served"]) < 0.0:
		v["t_served"] = shop_t

## Al irse del mostrador: atendido (y cuánto esperó) o no atendido.
func _pace_count_leave(v: Dictionary) -> void:
	if v.get("handed", false) or v.get("told", false):
		Game.pace_served(float(v["t_served"]) - float(v["t_in"]), not v["tutorial"])
	elif v.get("declined", false):
		Game.today["declined"] = int(Game.today.get("declined", 0)) + 1

# ------------------------------------------------ la paciencia

## Se gasta mientras corre el reloj: en la fila, siempre; en el mostrador, desde que pidió hasta que recibe la poción.
func _pace_drain(delta: float) -> void:
	for v in line.duplicate():
		if v["tutorial"]:
			continue
		v["p"] = float(v["p"]) - delta / float(v["line_secs"])
		if float(v["p"]) <= 0.0:
			_pace_annoyed(v)
	var c := _counter_v
	if not c.is_empty() and c.get("ordered", false) and not c.get("serving", false) and not c["tutorial"]:
		c["p"] = float(c["p"]) - delta / float(c["counter_secs"])
		if float(c["p"]) <= 0.0:
			_pace_annoyed(c)

## Se le acabó la paciencia: se va enfadado (la nubecita, una frase y un bufido), baja un poco el renombre y tarda en
## volver. Si estaba en el mostrador se va su ticket y pasa el siguiente; si estaba en la fila, los de atrás avanzan.
func _pace_annoyed(v: Dictionary) -> void:
	var at_counter := _pace_still(int(v["id"]))
	if at_counter:
		_counter_v = {}
		customer_ready = false
		customer = null
		current = {}
		ui.hide_order()
		ui.set_order_patience(-1.0)
		if ui.dialog_open():
			ui.hide_dialog()
	else:
		_pace_remove(line, v)
	v["p"] = 0.0
	var lost := Game.pace_annoyed(v["req"])
	var a = v.get("actor")
	if is_instance_valid(a):
		a.emote("angry", 2.0)
		a.shake()
		world.blurt(a, Story.pick(PACE_LINES["tired_counter" if at_counter else "tired"]), Color(1.0, 0.42, 0.32))
	_pace_sfx("pace_huff", -5.0)
	if lost > 0:
		ui.toast("−%d renown" % lost, UIKit.BAD, 2.2)
	_pace_exit(v, 2.0, 0.7)
	Game.save_game()
	if at_counter and _pace_closing:
		# ya eran más de las 18:00: era el último; se cierra el día como cuando sale el último atendido
		await get_tree().create_timer(1.8).timeout
		if phase == Phase.OPEN and _counter_v.is_empty():
			_close_day()
	elif at_counter:
		_pace_advance()
	else:
		_pace_shift()

## Quien espera en la fila no se queda quieto: mira el reloj de la pared, se balancea; si se impacienta, suspira o se
## enfada (la nubecita) y patea el suelo.
func _pace_fidget(v: Dictionary, delta: float) -> void:
	if String(v["state"]) != "line" or not (v["path"] as Array).is_empty() or v["tutorial"]:
		return
	v["fidget"] = float(v["fidget"]) - delta
	if float(v["fidget"]) > 0.0:
		return
	var a = v.get("actor")
	if not is_instance_valid(a):
		return
	var p := float(v["p"])
	if p < 0.25:
		a.emote("angry", 0.9)
		a.shake()
		if randf() < 0.35:
			_pace_sfx("pace_sigh", -15.0, 0.12)
		v["fidget"] = randf_range(3.5, 5.5)
	elif p < 0.5:
		_pace_glance(v)
		a.emote("sweat" if randf() < 0.5 else "dots", 1.1)
		v["fidget"] = randf_range(5.0, 8.0)
	else:
		if randf() < 0.6:
			_pace_glance(v)
		else:
			a.hop(1, 0.06)
		v["fidget"] = randf_range(6.0, 11.0)

## Mira la hora en el reloj de la pared (junto a la puerta) y vuelve a mirar al mostrador.
func _pace_glance(v: Dictionary) -> void:
	var a: Actor = v["actor"]
	a.face(1 if ShopWorld.P_WALL_CLOCK.x > a.global_position.x + 0.1 else -1)
	get_tree().create_timer(1.4).timeout.connect(func():
		if is_instance_valid(a) and String(v["state"]) == "line" and (v["path"] as Array).is_empty():
			a.face(-1))

## Quien ya pidió y espera su poción en el mostrador también se impacienta (sin tapar el diálogo).
func _pace_fidget_counter(v: Dictionary, delta: float) -> void:
	if not v.get("ordered", false) or v.get("serving", false) or v["tutorial"] or ui.dialog_open():
		return
	v["fidget"] = float(v["fidget"]) - delta
	if float(v["fidget"]) > 0.0:
		return
	var a = v.get("actor")
	if not is_instance_valid(a):
		return
	var p := float(v["p"])
	if p < 0.25:
		a.emote("angry", 0.9)
		a.shake()
		v["fidget"] = randf_range(3.5, 5.0)
	elif p < 0.5:
		a.emote("sweat" if randf() < 0.5 else "dots", 1.1)
		v["fidget"] = randf_range(5.0, 8.0)
	else:
		v["fidget"] = randf_range(4.0, 7.0)

# ------------------------------------------------ el reloj, la luz del día y el cierre

var _film_dir := ""
var _film_every := 60
var _film_n := 0

func _pace_process(delta: float) -> void:
	# (pruebas) --film=<carpeta>: capturas cada _film_every cuadros mientras la tienda está abierta
	if _film_dir != "" and phase == Phase.OPEN and _pace_on and _frame % maxi(1, _film_every) == 0 and _film_n < 400:
		_film_n += 1
		get_viewport().get_texture().get_image().save_png("%s/f%04d_d%d_%s.png" % [_film_dir, _film_n, Game.day, ("%d%02d" % [shop_minutes() / 60, shop_minutes() % 60])])
	# quienes caminan (entran, avanzan, salen) se mueven siempre, aunque el reloj esté detenido
	var walkers: Array = line + _leaving
	if not _counter_v.is_empty():
		walkers.append(_counter_v)
	for v in walkers:
		_pace_move(v, delta)
	if phase != Phase.OPEN or not _pace_on:
		return
	var paused := clock_paused()
	if not paused and not _pace_closing:
		shop_t = minf(shop_t + delta, Game.PACE_DAY_SECONDS)
		while not _arrivals.is_empty() and float(_arrivals[0]) <= shop_t and not _pace_closing:
			_arrivals.pop_front()
			_pace_arrive()
		_pace_idle(delta)
		_pace_drain(delta)
		for v in line.duplicate():
			_pace_fidget(v, delta)
		if not _counter_v.is_empty():
			_pace_fidget_counter(_counter_v, delta)
		_pace_bells()
		if shop_t >= Game.PACE_DAY_SECONDS:
			_pace_close_time()
	elif not paused:
		# pasadas las 18:00 el reloj ya no anda, pero quien pidió en el mostrador sigue esperando y puede cansarse: una
		# noche sin nada que darle siempre termina (antes se quedaba allí para siempre)
		_pace_drain(delta)
		if not _counter_v.is_empty():
			_pace_fidget_counter(_counter_v, delta)
	_pace_light(delta)
	_pace_hud(paused)

## La tienda lleva un rato vacía: entra alguien que pasaba y la vio libre (de los de más del día, Game.pace_spares).
## Los que tenían hora siguen llegando a su hora (la hora punta no se deshace): atender rápido trae más gente.
func _pace_idle(delta: float) -> void:
	if not (line.is_empty() and _counter_v.is_empty()):
		_idle_t = 0.0
		return
	_idle_t += delta
	if _idle_t < PACE_IDLE_PULL or shop_t > Game.PACE_DAY_SECONDS * Game.PACE_LAST_ARRIVAL:
		return
	_idle_t = 0.0
	if queue.size() > _arrivals.size():
		_pace_arrive()

## A las 17:00 una campanada (la última hora); desde las 17:40, el tic del reloj cada 5 minutos.
func _pace_bells() -> void:
	var m := shop_minutes()
	if m >= 1020 and _last_chime < 1:
		_last_chime = 1
		_pace_sfx("pace_chime", -7.0, 0.0)
		ui.toast("Last hour", Color(1.0, 0.74, 0.52), 2.4)
	if m >= 1060:
		var step := m / 5
		if step != _tick_step:
			_tick_step = step
			_pace_sfx("pace_tick", -11.0, 0.03)

## La luz sigue al reloj: de la mañana (0.12) a la noche (0.92), poco a poco.
func _pace_light(delta: float) -> void:
	_light_t += delta
	if _light_t < 0.4:
		return
	_light_t = 0.0
	var goal := 0.12 + 0.8 * clampf(shop_t / Game.PACE_DAY_SECONDS, 0.0, 1.0)
	if absf(world.time_t - goal) > 0.002:
		world.set_time(lerpf(world.time_t, goal, 0.35), false)
	_update_time_label(goal)

## El HUD: el reloj, cuántos esperan (y el peor), el ticket y los relojes de arena.
func _pace_hud(paused: bool) -> void:
	var m := shop_minutes()
	var state := "open"
	if _pace_closing:
		state = "closed"
	elif paused and not _pace_tut_hold():
		state = "paused"
	elif m >= 1020:
		state = "late"
	ui.set_clock(m, state)
	var worst := 1.0
	for v in line:
		worst = minf(worst, float(v["p"]))
	ui.set_queue(line.size(), worst)
	var t := Time.get_ticks_msec() / 1000.0
	for v in line:
		world.set_hourglass(v.get("bubble"), float(v["p"]), t)
	var c := _counter_v
	if not c.is_empty() and c.get("ordered", false) and not c.get("serving", false) and not c["tutorial"]:
		ui.set_order_patience(float(c["p"]))
		world.set_hourglass(c.get("bubble"), float(c["p"]), t)
	else:
		ui.set_order_patience(-1.0)

## Las 18:00: suena la campana, ya no entra nadie y la fila se va a casa. A quien está en el mostrador se le atiende;
## después, el libro de cuentas.
func _pace_close_time() -> void:
	if _pace_closing:
		return
	_pace_closing = true
	shop_t = Game.PACE_DAY_SECONDS
	_arrivals.clear()
	shop_closing.emit()
	krapido.on_close()   # --- R4 MERGE (RAVEN on PACE's clock): a las 18:00 los pedidos pendientes se cancelan sin castigo
	_pace_sfx("pace_bell", -3.0, 0.0)
	ui.set_clock(Game.PACE_CLOSE_MIN, "closed")
	ui.show_banner("Closing time!")
	var k := 0
	for v in line.duplicate():
		Game.today["lost_closed"] = int(Game.today.get("lost_closed", 0)) + 1
		var a = v.get("actor")
		if is_instance_valid(a):
			a.emote("sigh" if k % 2 == 0 else "zz", 1.6)
			if k == 0:
				world.blurt(a, Story.pick(PACE_LINES["home"]))
		_pace_exit(v, 1.6, 0.35 + 0.3 * float(k))
		k += 1
	line.clear()
	ui.set_queue(0, 1.0)
	if _counter_v.is_empty():
		await get_tree().create_timer(1.8).timeout
		if phase == Phase.OPEN and _counter_v.is_empty():
			_close_day()
	elif not _counter_v.get("handed", false) and not _counter_v.get("told", false):
		ui.show_tip("Serve whoever is at the [b]counter[/b].", 7.0)

## Fin del día abierto (lo llama _close_day): el reloj se detiene, quien quede se va, y el boca a boca de mañana.
func _pace_end() -> void:
	if not _pace_on and line.is_empty() and _counter_v.is_empty():
		return
	_pace_on = false
	for v in line.duplicate():
		_pace_exit(v, 1.6)
	line.clear()
	if not _counter_v.is_empty():
		_pace_exit(_counter_v, 1.6)
		_counter_v = {}
	Game.pace_end_day()
	ui.set_clock(Game.PACE_CLOSE_MIN, "closed")
	ui.set_queue(0, 1.0)
	ui.set_order_patience(-1.0)

# ------------------------------------------------ sonidos y consejos

## Un sonido del reloj y de la fila (assets/audio/pace_*.ogg, tools/arte/pace_audio.py), por el bus de efectos.
func _pace_sfx(name: String, db := 0.0, pitch_var := 0.05) -> void:
	if not _pace_streams.has(name):
		var path := "res://assets/audio/%s.ogg" % name
		_pace_streams[name] = load(path) if ResourceLoader.exists(path) else null
	var st: AudioStream = _pace_streams[name]
	if st == null:
		return
	var p: AudioStreamPlayer = null
	for q in _pace_players:
		if not q.playing:
			p = q
			break
	if p == null:
		if _pace_players.size() >= 4:
			p = _pace_players[0]
		else:
			p = AudioStreamPlayer.new()
			p.bus = "SFX"
			add_child(p)
			_pace_players.append(p)
	p.stream = st
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()

## Un consejo de una línea, una sola vez por partida (Game.pace_seen).
func _pace_tip(key: String, text: String, secs := 9.0) -> void:
	if Game.pace_seen.has(key):
		return
	Game.pace_seen[key] = true
	ui.show_tip(text, secs)
# --- end R4 PACE

# --- R4 PACE: capturas y prueba del día abierto ---------------------------------------------------------------------
## --demo=queue: la fila (cuatro esperando y Nyra en el mostrador con su ticket; el reloj a las 13:20).
## --demo=annoyed: a Pip se le acaba la paciencia en la fila y se va enfadado (captura a ~1,5 s).
## --demo=fullqueue: la fila está llena; Hassim se asoma, suspira y se va.
## --demo=closing: dan las 18:00; la fila se va a casa (Nyra, en el mostrador, se queda).
## --demo=ledger: el libro de cuentas de la noche.
## --demo=pacetest: prueba sin pantalla: un día corto de reloj con la fila, quien se cansa, la fila llena y el cierre.
func _pace_demo(name: String) -> void:
	Game.day = 5
	Game.renombre = 20
	ui.refresh_hud()
	if name == "ledger":
		phase = Phase.CLOSING
		world.set_time(1.0, false)
		ui.set_time_label("Night")
		Game.today = {"earned": 142, "renombre": 7, "sold": 9, "new_recipes": ["velo_invernal"],
			"journal": [{"day": 5, "hero": "lirien", "text": Data.HEROES["lirien"][0]["journal"]}],
			"arrived": 14, "served": 9, "lost_tired": 2, "lost_full": 1, "lost_closed": 2, "declined": 0,
			"avg_wait": 27.4, "speed_tips": 16, "renombre_lost": 2, "wait_n": 8, "wait_sum": 219.2}
		Game.pending = [{"id": 1, "who": "granjero"}, {"id": 2, "who": "nyra"}, {"id": 3, "who": "anciano"}]
		ov.show_summary(Game.day, Game.today)
		return
	if name == "pacetest":
		_pace_test()
		return
	if name == "pacelate":
		_pace_test_late()
		return
	phase = Phase.OPEN
	_pace_clear()
	queue = []
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	shop_t = 297.0 if name == "closing" else 144.0
	world.set_time(0.12 + 0.8 * shop_t / Game.PACE_DAY_SECONDS, false)
	_update_time_label(0.12 + 0.8 * shop_t / Game.PACE_DAY_SECONDS)
	ui.set_clock_visible(true)
	_pace_on = true
	# en el mostrador: Nyra, que ya pidió (su ticket con la barra de paciencia)
	var req := _pace_demo_req("nyra")
	var cv := _pace_demo_visitor(req, ShopWorld.P_CUSTOMER, 0.56)
	cv["state"] = "counter"
	cv["ordered"] = true
	cv["counter_secs"] = Game.pace_counter_secs(req)
	_counter_v = cv
	current = req
	customer = cv["actor"]
	customer_ready = true
	hint_given = true
	ui.order_who = "nyra"
	ui.show_order(Story.char_name("nyra"), String(req["text"]), String(req["hint"]), Game.order_runes(req))
	cv["bubble"].visible = true
	var rows := [["granjero", 0.88], ["anciano", 0.64], ["marta", 0.42], ["pip", 0.19]]
	if name == "annoyed":
		rows = [["granjero", 0.84], ["anciano", 0.6], ["pip", 0.012]]
	for i in rows.size():
		var v := _pace_demo_visitor(_pace_demo_req(rows[i][0]), _pace_spot(i), rows[i][1])
		line.append(v)
	if name == "fullqueue":
		queue = [_pace_demo_req("hassim")]
		await get_tree().create_timer(0.3).timeout
		_pace_arrive()

## El primer pedido de esa persona en VILLAGER_REQUESTS (para las capturas).
func _pace_demo_req(who: String) -> Dictionary:
	for q in Data.VILLAGER_REQUESTS:
		if q["who"] == who:
			var r: Dictionary = q.duplicate()
			r["kind"] = "villager"
			return r
	return {"kind": "villager", "who": who, "potion": "sueno_profundo", "text": "…", "hint": ""}

## Alguien ya esperando en su sitio (sin entrar por la puerta), con esa paciencia.
func _pace_demo_visitor(req: Dictionary, pos: Vector3, p: float) -> Dictionary:
	var v := _pace_visitor(req)
	var a := Actor.new()
	world.add_child(a)
	a.setup(Story.sprite_id(String(req["who"])))
	a.global_position = pos
	a.face(-1)
	v["actor"] = a
	v["state"] = "line"
	v["p"] = p
	v["t_in"] = shop_t - 20.0
	v["fidget"] = randf_range(0.5, 3.0)
	v["bubble"] = world.hourglass_for(a)
	return v

## --demo=pacetest: un día de reloj corto, sin pantalla: entran 6 (la fila se llena: uno se asoma y se va), uno se
## cansa, se atiende a dos con pociones del estante y a las 18:00 la fila se va a casa. Imprime cada paso y sale.
func _pace_test() -> void:
	Engine.time_scale = 4.0
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 3
	Game.potions = [{"id": "sueno_profundo", "potency": 6}, {"id": "vigor_verde", "potency": 6}, {"id": "ojo_nocturno", "potency": 6}]
	_refresh_all()
	phase = Phase.MORNING
	_open_shop()
	await get_tree().create_timer(1.5).timeout
	# seis llegan seguidos: cuatro a la fila, uno al mostrador... y el sexto ve la fila llena
	queue = []
	for who in ["granjero", "anciano", "marta", "pip", "nyra", "grumm"]:
		queue.append(_pace_demo_req(who))
	_arrivals = []
	for i in 6:
		_pace_arrive()
		await get_tree().create_timer(0.6).timeout
	await get_tree().create_timer(4.0).timeout
	print("PACETEST fila=", line.size(), " mostrador=", _counter_v.get("req", {}).get("who", ""), " llena=", Game.today["lost_full"], " llegaron=", Game.today["arrived"], " reloj=", shop_minutes())
	# Pip se cansa (le quitamos la paciencia)
	for v in line:
		if v["req"]["who"] == "pip":
			v["p"] = 0.01
	await get_tree().create_timer(1.0).timeout
	print("PACETEST cansados=", Game.today["lost_tired"], " fila=", line.size(), " renombre_perdido=", Game.today["renombre_lost"])
	# atender a dos: pide, se le da una poción del estante y se va
	for k in 2:
		var w := 0.0
		while not (customer_ready and ui.dialog_open()) and w < 12.0:
			await get_tree().create_timer(0.25).timeout
			w += 0.25
		_on_choice("prepare")
		await get_tree().create_timer(1.0).timeout
		var p0 := float(_counter_v.get("p", -1.0))
		_on_potion(0)
		w = 0.0
		while not (ui.dialog_open() and _counter_v.get("handed", false)) and w < 12.0:
			await get_tree().create_timer(0.25).timeout
			w += 0.25
		print("PACETEST entrega ", k, ": paciencia=", snappedf(p0, 0.01), " propina rapidez total=", Game.today["speed_tips"], " dice=", ui.dialog_text.text.replace("\n", " / "))
		_on_choice("bye")
		await get_tree().create_timer(0.5).timeout
	print("PACETEST atendidos=", Game.today["served"], " espera media=", snappedf(float(Game.today["avg_wait"]), 0.1), " s fila=", line.size())
	# las 18:00
	shop_t = Game.PACE_DAY_SECONDS - 1.0
	var w2 := 0.0
	var said_no := false
	while phase == Phase.OPEN and w2 < 30.0:
		await get_tree().create_timer(0.5).timeout
		w2 += 0.5
		if customer_ready and ui.dialog_open() and ui.dialog_choices.get_child_count() > 0 and not said_no:
			said_no = true
			_on_choice("decline")
		elif ui.dialog_open() and ui.dialog_choices.get_child_count() == 0:
			ui._advance()
	print("PACETEST cierre: fase=", phase, " a casa=", Game.today["lost_closed"], " sin atender=", Game.today["declined"], " panel=", ov.current, " reloj=", shop_minutes(), " boca a boca=", snappedf(Game.pace_wom, 0.01))
	print("PACETEST today=", Game.today)
	# guardar y cargar: el boca a boca y los consejos vistos se guardan; una partida sin "pace" carga con 0
	var wom := Game.pace_wom
	Game.pace_seen["prueba"] = true
	Game.save_game()
	Game.load_game()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	raw.erase("pace")
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f = null
	var wom_after := Game.pace_wom
	var seen_after := Game.pace_seen.has("prueba")
	var ok_old := Game.load_game()
	print("PACETEST guardado: boca a boca ", snappedf(wom, 0.01), " -> ", snappedf(wom_after, 0.01), " consejos=", seen_after,
		" | partida sin pace: carga=", ok_old, " boca a boca=", Game.pace_wom, " today=", Game.today.has("served"))
	Game.delete_save()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

## --demo=pacelate (headless): pasadas las 18:00 queda alguien en el mostrador que ya pidió y no hay nada que darle:
## se cansa igual (su paciencia sigue) y el día se cierra solo; antes se quedaba allí para siempre.
func _pace_test_late() -> void:
	Engine.time_scale = 4.0
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 3
	Game.renombre = 20
	Game.potions = []
	_refresh_all()
	phase = Phase.MORNING
	_open_shop()
	await get_tree().create_timer(1.5).timeout
	queue = [_pace_demo_req("granjero"), _pace_demo_req("anciano")]
	_arrivals = []
	for i in 2:
		_pace_arrive()
		await get_tree().create_timer(0.6).timeout
	var w := 0.0
	while not (customer_ready and ui.dialog_open()) and w < 12.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	_on_choice("prepare")
	await get_tree().create_timer(0.5).timeout
	shop_t = Game.PACE_DAY_SECONDS - 0.5
	await get_tree().create_timer(2.0).timeout
	print("PACELATE 18:00: cerrando=", _pace_closing, " fila=", line.size(), " a casa=", Game.today["lost_closed"],
		" mostrador=", _counter_v.get("req", {}).get("who", ""), " pidió=", _counter_v.get("ordered", false), " fase=", phase)
	var p0 := float(_counter_v.get("p", -1.0))
	await get_tree().create_timer(2.0).timeout
	var p1 := float(_counter_v.get("p", -1.0))
	print("PACELATE la paciencia sigue tras las 18:00: ", snappedf(p0, 0.001), " -> ", snappedf(p1, 0.001))
	if not _counter_v.is_empty():
		_counter_v["p"] = 0.02
	w = 0.0
	while phase == Phase.OPEN and w < 20.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	await get_tree().create_timer(3.0).timeout
	print("PACELATE fin: fase=", phase, " cansados=", Game.today["lost_tired"], " a casa=", Game.today["lost_closed"],
		" renombre_perdido=", Game.today["renombre_lost"], " panel=", ov.current)
	Game.delete_save()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
# --- end R4 PACE

# --- R4 PACE: el bot con el reloj corriendo -------------------------------------------------------------------------
# Dos perfiles (--bot=good / --bot=slow), con tiempos de una persona: leer lo que dice el cliente, pensar la receta,
# tocar los frascos, remover, entregar, despedirse. El rápido además deja pociones hechas por la mañana y en los ratos
# libres; el lento lee despacio, a veces pide una pista, busca la receta en el recetario y no adelanta nada.
const BOT_TIMES := {
	"good": {"read": 2.2, "think": 1.5, "jar": 0.6, "stir": 1.0, "give": 0.8, "bye": 1.0, "pre": 0.6},
	"slow": {"read": 5.5, "think": 8.0, "jar": 1.6, "stir": 1.8, "give": 2.4, "bye": 2.6, "pre": 3.0},
}

func _bot_wait(kind: String) -> void:
	var tb: Dictionary = BOT_TIMES.get(_bot, BOT_TIMES["good"])
	await get_tree().create_timer(float(tb.get(kind, 1.0)) * randf_range(0.75, 1.25)).timeout

## Atiende el día abierto hasta que cierra. Devuelve los errores.
func _bot_open_day(rune_stats: Dictionary) -> int:
	var errors := 0
	var slow := _bot == "slow"
	while phase == Phase.OPEN:
		await get_tree().create_timer(0.25).timeout
		if ov.is_open():
			if ov.current == "levelup" or ov.current == "mail":
				ov.close()
			continue
		# --- R4 RAVEN (merge: moved here from the old serve loop): la ventanilla primero (Graznido espera un minuto);
		# si no hay nadie en el mostrador, prepara lo que el cuervo vendrá a buscar
		if krapido.active() and not busy and not ui.dialog_open() and not ov.is_open():
			if await _bot_krapido():
				continue
		# --- end R4 RAVEN
		if customer_ready and ui.dialog_open():
			if not busy:
				await _bot_answer()
			continue
		if customer_ready and not busy and _counter_v.get("ordered", false) and current.has("potion"):
			var vid := int(_counter_v.get("id", -1))
			var want := String(current["potion"])
			var have := _bot_pick_potion(want)
			if have >= 0:
				# --- R3 MAGIC3: con la runa que pide, si se puede inscribir
				var r := Game.next_rune_for(Game.potions[have], current)
				if r != "" and Game.enchant_problem(have, r) == "":
					var res: Dictionary = await grimoire.bot_enchant(have, r)
					if res.is_empty():
						if _pace_still(vid):
							print("AUTOPLAY: no pudo encantar ", want, " con ", r, " (", grimoire.bot_fail, ")")
							errors += 1
					else:
						rune_stats["enchanted"] += 1
					continue
				await _bot_wait("give")
				if not _pace_still(vid) or not customer_ready or busy or ui.dialog_open():
					continue
				have = _bot_pick_potion(want)
				if have < 0:
					continue
				if not Game.order_runes(current).is_empty():
					rune_stats["orders"] += 1
					if Game.next_rune_for(Game.potions[have], current) != "":
						rune_stats["missing"] += 1
				_on_potion(have)
				continue
			# hay que prepararla: pensar la receta (el lento la busca en el recetario)
			await _bot_wait("think")
			if not _pace_still(vid) or not customer_ready or ui.dialog_open() or busy:
				continue
			var combo := _find_combo(want)
			if combo.is_empty() or Game.potions_full():
				print("AUTOPLAY: sin receta (o sin sitio) para ", want, " stock=", Game.stock, " estante=", Game.potions.size())
				if combo.is_empty():
					errors += 1
				_on_choice("decline")
				continue
			await _bot_brew(combo)
			continue
		# un rato libre: el bot rápido adelanta pociones de las que más se piden
		if not slow and not busy and not ui.dialog_open() and (_counter_v.is_empty() or not _counter_v.get("ordered", false)):
			await _bot_prebrew(1)
	return errors

## Contesta lo que dice el cliente del mostrador (tras leerlo: primero espera a que se termine de escribir).
func _bot_answer() -> void:
	var vid := int(_counter_v.get("id", -1))
	var tw := 0.0
	while ui.dialog_open() and ui._typing and tw < 8.0:
		await get_tree().create_timer(0.1).timeout
		tw += 0.1
	var choice := ""
	if ui.dialog_choices.get_child_count() > 0:
		choice = _bot_choice(ui.dialog_choices.get_child(0))   # --- R5 EN-UI: por id
	await _bot_wait("bye" if choice == "bye" or choice == "return_next" else "read")
	if not (customer_ready and ui.dialog_open() and _pace_still(vid)) or busy:
		return
	if ui.dialog_choices.get_child_count() == 0:
		ui._advance()
		return
	choice = _bot_choice(ui.dialog_choices.get_child(0))   # --- R5 EN-UI: por id
	if _bot == "slow" and choice == "prepare" and not hint_given and randf() < 0.35:
		for b in ui.dialog_choices.get_children():
			if String(b.get_meta("choice", "")) == "hint":   # --- R5 EN-UI: por id (antes el texto «¿Una pista?»)
				_on_choice("hint")
				return
	_on_choice(choice)

## Prepara una poción en el banco del caldero, con los tiempos del perfil. false si no se pudo (alguien habló).
func _bot_brew(combo: Array) -> bool:
	if not brew_ready.is_empty():
		await brew_bottle()
	if not contents.is_empty():
		_on_empty()
	for id in combo:
		if ui.dialog_open():
			break
		_on_jar_clicked(id)
		await _bot_wait("jar")
	var wait := 0.0
	while (not _brew_open() or brew.is_busy() or contents.size() < combo.size()) and wait < 6.0:
		await get_tree().create_timer(0.2).timeout
		wait += 0.2
		if ui.dialog_open() and contents.size() < combo.size():
			break
	if contents.size() < combo.size():
		if _brew_open() and not brew.is_busy():
			await brew.close()
		return false
	_on_brew()
	await _bot_wait("stir")
	if brew._stir:
		brew._stir.press()
	elif ov.current == "stir":
		ov.stir_key()
	var w2 := 0.0
	while busy and w2 < 10.0:
		await get_tree().create_timer(0.2).timeout
		w2 += 0.2
	if not brew_ready.is_empty():
		await brew_bottle()
	if _brew_open():
		await brew.close()
	return true

## Deja hechas hasta k pociones de las que más se piden (sin llenar el estante: quedan 2 huecos), solo con lo que hay.
func _bot_prebrew(k: int) -> void:
	for i in k:
		if Game.potion_capacity() - Game.potions.size() <= 2 or busy or ui.dialog_open() or ov.is_open():
			return
		var pid := _bot_prebrew_pick()
		if pid == "":
			return
		await _bot_wait("pre")
		if busy or ui.dialog_open() or ov.is_open():
			return
		var combo := _bot_combo_in_stock(pid)
		if combo.is_empty():
			return
		await _bot_brew(combo)

## La poción que más se pide entre la gente que ya llegó al pueblo y se puede preparar con lo que hay (menos si ya
## hay alguna en el estante).
func _bot_prebrew_pick() -> String:
	var brewable := Game.brewable_potions()
	var freq := {}
	for r in Story.request_pool():
		var who := String(r.get("who", ""))
		if int(Data.CHARACTERS.get(who, {}).get("arrives", 1)) > Game.day or int(r.get("level", 0)) > Game.level():
			continue
		var pid := String(r.get("potion", ""))
		if brewable.has(pid):
			freq[pid] = int(freq.get(pid, 0)) + 1
	var best := ""
	var best_s := -1.0
	for pid in freq:
		var have := 0
		for p in Game.potions:
			if p["id"] == pid:
				have += 1
		var s := float(freq[pid]) / (1.0 + 2.5 * float(have))
		if s > best_s and not _bot_combo_in_stock(pid).is_empty():
			best_s = s
			best = pid
	return best

## Como _find_combo, pero sin comprar nada (solo con los ingredientes que hay).
func _bot_combo_in_stock(want: String) -> Array:
	var ings := Game.unlocked_ingredients()
	var best := []
	var best_p := -1
	var n := ings.size()
	for i in n:
		for j in range(i, n):
			var c := [ings[i], ings[j]]
			var r := Game.evaluate(c)
			if r.get("potion", "") == want and _have(c) and int(r["potency"]) > best_p:
				best = c
				best_p = int(r["potency"])
	return best
# --- end R4 PACE

# --- R4 RAVEN: Krápido: el bot en la ventanilla, capturas y la prueba de la lógica -----------------------------------
var _krapido_bot := false                              # --krapido: el bot compra la ventanilla desde el día 1
var _bot_k := {"errors": 0, "brewed": 0, "handed": 0}

## El bot y Krápido: si Graznido espera, le da la poción de su pedido (la prepara si no la tiene; la encanta si pide
## runa y hay tiempo); si no, y el mostrador está libre, prepara lo que el cuervo vendrá a buscar. true si hizo algo.
func _bot_krapido() -> bool:
	var o: Dictionary = krapido.bot_target()
	if o.is_empty():
		return false
	var want := String(o["potion"])
	var req: Dictionary = krapido.req_of(o)
	var have := -1
	var best_k := -INF
	for i in Game.potions.size():
		if Game.potions[i]["id"] != want:
			continue
		var kk := 0.0
		for r in Game.potion_rune_ids(Game.potions[i]):
			kk += 10.0 if Game.order_runes(req).has(r) else -1.0
		if kk > best_k:
			best_k = kk
			have = i
	var for_raven: bool = krapido.raven_waiting() and int(krapido.raven_order.get("id", -1)) == int(o["id"])
	if for_raven:
		if have >= 0:
			var r := Game.next_rune_for(Game.potions[have], req)
			if r != "" and Game.enchant_problem(have, r) == "" and krapido.raven_left > 30.0:
				var res: Dictionary = await grimoire.bot_enchant(have, r)
				if res.is_empty():
					print("AUTOPLAY: krapido no pudo encantar ", want, " con ", r)
					_bot_k["errors"] += 1
				return true
			if not world.at_station("ventanilla"):
				if not await world.go_station("ventanilla"):
					return true   # (la interrumpieron, p. ej. llegó un cliente: se reintenta)
			if not world.at_station("ventanilla") or not krapido.raven_waiting():
				return true
			var before := int(Game.today.get("deliveries", 0))
			_on_potion(have)
			var w := 0.0
			while (busy or krapido.raven_state == "busy") and w < 12.0:
				await get_tree().create_timer(0.2).timeout
				w += 0.2
			if int(Game.today.get("deliveries", 0)) == before:
				print("AUTOPLAY: krapido no entregó ", want, " (estado ", krapido.raven_state, ")")
				_bot_k["errors"] += 1
			else:
				_bot_k["handed"] += 1
			return true
		if Game.potions_full():
			return false
		return await _bot_k_brew(want)
	# no espera todavía: con el mostrador libre, adelanta la poción
	if have < 0 and not customer_ready and not Game.potions_full():
		return await _bot_k_brew(want)
	return false

## El bot prepara una poción en el banco del caldero (como para el mostrador).
## (R4 merge: was _bot_brew(want); renamed — PACE's _bot_brew(combo) brews with the bot's human timings)
func _bot_k_brew(want: String) -> bool:
	var combo := _find_combo(want)
	if combo.is_empty():
		return false
	var n0 := Game.potions.size()
	await _bot_brew(combo)
	if Game.potions.size() > n0:
		_bot_k["brewed"] += 1
	return true

## Capturas (--demo=krapido_*) y la prueba de la lógica (--demo=krapido_test).
##   krapido_shop    la tienda con la ventanilla: Graznido en la percha, la bola late, ella junto a la bola
##   krapido_ball    la bola abierta con 3 pedidos (uno con runa) y Graznido esperando
##   krapido_take    Graznido recibe la botella (sale a mitad de la entrega: --frames elige el momento)
##   krapido_arrive  Graznido llega volando por la ventanilla
##   krapido_counter el mostrador con la medalla de Krápido en el HUD (el cuervo espera)
##   krapido_market  el puesto de Mabel con la Ventanilla Krápido
##   krapido_letter  el correo: la carta de un pedido a domicilio, con la reseña en plumas
func _krapido_demo(name: String) -> void:
	if name == "krapido_test":
		_krapido_test()
		return
	if name == "krapido_input":
		_krapido_input_test()
		return
	if name == "krapido_empty":   # la bola por la mañana: sin pedidos todavía
		Game.upgrades["krapido"] = true
		_refresh_all()
		phase = Phase.MORNING
		world.set_time(0.0, false)
		ui.set_time_label("Morning")
		world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
		world.snap_camera()
		await get_tree().create_timer(0.4).timeout
		krapido.open_ball()
		return
	if name == "krapido_market":
		Game.gold = 180
		Game.upgrades.erase("krapido")
		_refresh_all()
		phase = Phase.MORNING
		world.set_time(0.0, false)
		ui.set_time_label("Morning")
		_switch_place(true, false)
		ov.show_market("morning", "mabel")
		return
	Game.upgrades["krapido"] = true
	_refresh_all()
	if name == "krapido_letter":
		phase = Phase.MORNING
		world.set_time(0.0, false)
		ui.set_time_label("Morning")
		var r: Dictionary = Data.KRAPIDO_ORDERS[0]
		var req := {"who": r["who"], "kind": "villager", "potion": r["potion"], "text": r["line"], "good": r["good"], "fail": r["fail"], "runes": []}
		var it := {"kind": "potion", "id": String(r["potion"]), "potency": 5}
		var o := Story.make_outcome(req, it, true, Story.price_of(it, req))
		o["via"] = "letter"
		o["due"] = Game.day
		o["krapido"] = true
		o["krapido_wait"] = 12.0
		Game.schedule_outcome(o)
		_morning_mail()
		return
	Game.unlock_magic()
	ov.close(false)
	Game.potions = [{"id": "sueno_profundo", "potency": 7}, {"id": "balsamo_helado", "potency": 6},
		{"id": "vigor_verde", "potency": 5, "rune": "prisa", "rune_stars": 3}, {"id": "ojo_nocturno", "potency": 6}]
	Game.sort_potions()
	Game.potions_changed.emit()
	Game.krapido_reviews = [{"who": "anciano", "plumas": 5, "day": 2, "lost": false}, {"who": "pip", "plumas": 4, "day": 2, "lost": false}]
	krapido.demo_orders(3, name != "krapido_arrive", "prisa")
	if name == "krapido_counter":
		world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	else:
		world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
	world.snap_camera()
	await get_tree().create_timer(0.4).timeout
	match name:
		"krapido_ball":
			krapido.open_ball()
		"krapido_take":
			var want := String(krapido.raven_order.get("potion", ""))
			var idx := 0
			for i in Game.potions.size():
				if Game.potions[i]["id"] == want:
					idx = i
			_on_potion(idx)
		"krapido_arrive":
			krapido.orders[0]["pickup"] = krapido.now()
			krapido._next_visit = 0.0
		"krapido_counter":   # lo que dice Graznido también se lee desde el mostrador
			krapido.raven.say(Data.RAVEN_LINES["angry"][2], 8.0)

## --demo=krapido_input: teclado y mando en la bola. E abre la bola (ella está en la ventanilla), → elige la poción del
## pedido de Graznido, Intro se la da; luego el mando: LB / RB saltan entre lo tocable de la bola y B la cierra.
func _krapido_input_test() -> void:
	Engine.time_scale = 2.0
	Game.upgrades["krapido"] = true
	Game.unlock_magic()
	ov.close(false)
	Game.potions = [{"id": "sueno_profundo", "potency": 7}, {"id": "balsamo_helado", "potency": 6},
		{"id": "vigor_verde", "potency": 5}, {"id": "ojo_nocturno", "potency": 6}, {"id": "tonico_brio", "potency": 6}]
	Game.sort_potions()
	_refresh_all()
	krapido.demo_orders(3, true)
	world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
	world.snap_camera()
	await get_tree().create_timer(0.5).timeout
	_tap_key(KEY_E)
	await get_tree().create_timer(0.5).timeout
	print("INPUT E abre la bola=", krapido.ball_open(), " estación=", world.current_station())
	var want := String(krapido.raven_order.get("potion", ""))
	var idx := -1
	for i in Game.potions.size():
		if Game.potions[i]["id"] == want and idx < 0:
			idx = i
	for code in [KEY_RIGHT, KEY_RIGHT, KEY_LEFT]:
		_tap_key(code)
		await get_tree().create_timer(0.1).timeout
	print("INPUT → → ← elegida=", krapido.ball._sel, " (esperada 1)")
	for i in absi(idx - krapido.ball._sel):
		_tap_key(KEY_RIGHT if idx > krapido.ball._sel else KEY_LEFT)
		await get_tree().create_timer(0.1).timeout
	print("INPUT → elegida=", krapido.ball._sel, " (la del pedido: ", idx, " ", want, ")")
	var d0 := int(Game.today.get("deliveries", 0))
	_tap_key(KEY_ENTER)
	var w := 0.0
	while krapido.raven_state != "away" and w < 15.0:
		await get_tree().create_timer(0.2).timeout
		w += 0.2
	print("INPUT Intro entrega=", int(Game.today.get("deliveries", 0)) - d0, " bola cerrada=", not krapido.ball_open(), " cuervo=", krapido.raven_state)
	# el mando: abrir otra vez con E, saltar con RB, cerrar con B
	_tap_key(KEY_E)
	await get_tree().create_timer(0.5).timeout
	var n := pad._targets().size()
	var seen := {}
	for i in 6:
		pad._on_button(JOY_BUTTON_RIGHT_SHOULDER, true)
		pad._on_button(JOY_BUTTON_RIGHT_SHOULDER, false)
		await get_tree().create_timer(0.25).timeout
		seen[str(pad._pos.round())] = true
	print("INPUT mando: bola abierta=", krapido.ball_open(), " tocables=", n, " RB visitó=", seen.size(), " cursor=", PadCursor.active)
	pad._on_button(JOY_BUTTON_B, true)
	pad._on_button(JOY_BUTTON_B, false)
	await get_tree().create_timer(0.5).timeout
	print("INPUT B cierra la bola=", not krapido.ball_open())
	get_tree().quit()

func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

## --demo=krapido_test: llega un pedido, Graznido lo busca y se lleva la poción correcta (paga, la carta queda
## pendiente); el siguiente se pierde (reseña de 1 pluma); al cerrar se cancelan los que falten sin castigo; la
## carta trae la reseña en plumas; guardar y cargar conserva las reseñas. Imprime KRAPIDO ... y sale.
func _krapido_test() -> void:
	Engine.time_scale = 8.0
	Game.delete_save()
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 3
	Game.gold = 100
	Game.renombre = 14
	Game.upgrades = {"krapido": true}
	for id in Data.INGREDIENT_ORDER:
		Game.stock[id] = 6 if Game.ingredient_unlocked(id) else 0
	_refresh_all()
	print("KRAPIDO inicio plumas=", Game.plumas(), " pedidos/día=", Game.krapido_orders_per_day(), " estación=", world.walker.stations.has("ventanilla"),
		" zona caldero=", world.walker.stations["caldero"]["zone"], " ventanilla visible=", world.krapido_node.visible)
	phase = Phase.OPEN
	shop_t = 0.0   # --- R4 MERGE: Krápido sigue el reloj de PACE (shop_minutes): aquí corre sin clientes (sin _pace_open)
	_pace_closing = false
	_pace_on = true
	krapido.on_open()
	print("KRAPIDO plan=", krapido._plan)
	var w := 0.0
	while krapido.orders.is_empty() and w < 40.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	var o: Dictionary = krapido.orders[0] if not krapido.orders.is_empty() else {}
	print("KRAPIDO pedido: ", o.get("who", "?"), " quiere ", o.get("potion", "?"), " runas=", o.get("runes", []), " «", o.get("line", ""), "» llega en ", "%.0f" % krapido.time_to_pickup(o), " s  hoy=", Game.today)
	# 1) se prepara su poción (con la runa si la pide) y se espera a Graznido
	var pot := {"id": String(o["potion"]), "potency": 7}
	if not o["runes"].is_empty():
		pot["rune"] = o["runes"][0]
		pot["rune_stars"] = 3
	Game.potions.append(pot)
	Game.sort_potions()
	Game.potions_changed.emit()
	o["pickup"] = krapido.now() + 1.0
	w = 0.0
	while not krapido.raven_waiting() and w < 20.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	print("KRAPIDO cuervo espera=", krapido.raven_waiting(), " pedido=", krapido.raven_order.get("who", ""), " tapa=", world._krapido_hatch_goal, " brillo=", world.krapido_glow_level)
	world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
	var g0 := Game.gold
	var pend0 := Game.pending.size()
	_on_potion(Game.find_potion(pot))
	w = 0.0
	while krapido.raven_state != "away" and w < 20.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	var out: Dictionary = Game.pending.back() if Game.pending.size() > pend0 else {}
	print("KRAPIDO entrega: oro +", Game.gold - g0, " entregas=", Game.today["deliveries"], " carta pendiente=", out.get("krapido", false), " via=", out.get("via", ""), " due=", out.get("due", 0), " ok=", out.get("ok", false), " espera=", "%.1f" % float(out.get("krapido_wait", -1)), " cuervo=", krapido.raven_state)
	# 2) el siguiente pedido se pierde
	if krapido.orders.is_empty():
		krapido._spawn(krapido.now())
	var o2: Dictionary = krapido.orders[0] if not krapido.orders.is_empty() else {}
	o2["pickup"] = krapido.now()
	krapido._next_visit = 0.0
	w = 0.0
	while not krapido.raven_waiting() and w < 20.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	krapido.raven_left = 0.3
	w = 0.0
	while krapido.raven_state != "away" and w < 20.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	print("KRAPIDO perdido: perdidos=", Game.today["deliveries_lost"], " reseñas=", Game.krapido_reviews.map(func(r): return r["plumas"]), " plumas=", "%.2f" % Game.plumas(), " hoy.plumas=", "%.2f" % float(Game.today["plumas"]))
	# 3) al cerrar, los pendientes se cancelan sin castigo
	krapido._spawn(krapido.now())
	var n_before := krapido.orders.size()
	var lost_before := int(Game.today["deliveries_lost"])
	krapido.on_close()
	print("KRAPIDO cierre: pedidos antes=", n_before, " después=", krapido.orders.size(), " perdidos igual=", int(Game.today["deliveries_lost"]) == lost_before, " activo=", krapido.active())
	# 4) la carta del pedido entregado: la reseña en plumas
	if not out.is_empty():
		Game.pending.erase(out)
		var res := Game.resolve_outcome(out)
		var L := Story.letter(out, res)
		print("KRAPIDO carta: reseña=", res.get("plumas", 0), " plumas=", "%.2f" % Game.plumas(), " premio tiene plumas=", String(L["reward"]).contains("pluma_full"), " cuerpo=«", String(L["body"]).replace("\n", " / "), "»")
	# 5) un pedido equivocado: 1 pluma
	var bad := Story.make_outcome(krapido.req_of(o), {"kind": "potion", "id": "ojo_nocturno" if o["potion"] != "ojo_nocturno" else "sueno_profundo", "potency": 7}, false, 10)
	bad["krapido"] = true
	print("KRAPIDO equivocada: reseña=", Game.krapido_review(bad))
	# 6) guardar y cargar
	var before := JSON.stringify(Game.krapido_save())
	Game.save_game()
	Game.load_game()
	print("KRAPIDO guardado ok=", before == JSON.stringify(Game.krapido_save()), " plumas=", "%.2f" % Game.plumas(), " stats=", Game.krapido_stats)
	# 7) una partida vieja (sin Krápido) carga
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f = null
	d.erase("krapido")
	f = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f = null
	print("KRAPIDO partida vieja: carga=", Game.load_game(), " plumas=", "%.2f" % Game.plumas(), " reseñas=", Game.krapido_reviews.size())
	Game.delete_save()
	get_tree().quit()
# --- end R4 RAVEN

# --- R4 RANK: el Escalafón del Gremio de Boticarios de Arvendal (scripts/ranking.gd), el final del puesto 1 --------
var _ending_running := false

## El final del puesto 1 (scripts/world/ending_scene.gd): la fiesta en la tienda y los créditos. Empieza y termina con la
## pantalla en negro; después _sleep() sigue con la mañana siguiente. En el bot y en las demos avanza solo.
func _play_ending(auto := false) -> void:
	_ending_running = true
	var e := EndingScene.new()
	e.auto = auto or _demo == "autoplay"
	add_child(e)
	await e.play(self)
	e.queue_free()
	Ranking.mark_ending_seen()
	_ending_running = false

## Para el bot: una línea con el puesto del día.
func _bot_rank_line() -> void:
	var mv: Dictionary = Ranking.last_move
	var ml: Dictionary = Ranking.morning_line()
	print("AUTOPLAY RANK día ", Game.day, " puesto=", Ranking.position(), " (", mv.get("prev", 0), "->", mv.get("pos", 0), ") +",
		mv.get("points", 0), " pts=", Ranking.score(), " partes=", mv.get("parts", {}), " pasó=", ml.get("passed", []),
		" la_pasaron=", ml.get("passed_by", []), " fizz=", Ranking.position("fizz"))

## --- R4 RANK: el bot con --rankstart=N: el Escalafón ya lleva N días y ella va primera por poco (el final se juega al
## dormir el primer día del bot, en automático). La tienda es una partida nueva en el día N+1.
func _rank_bot_start() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rankstart="):
			_rank_sim(int(a.substr(12)))
			Ranking.scores[Ranking.ME] = float(Ranking.scores[Ranking.order()[1]]) + 60.0
			Game.renombre = 0
			Ranking.ren_base = 0
			print("AUTOPLAY RANK inicio: día ", Game.day, " puesto=", Ranking.position(), " pts=", Ranking.score())

## Días de prueba para las demos: un día bueno (5-6 ventas, ~2.6 estrellas, +15 de renombre).
func _rank_sim(days: int) -> void:
	Ranking.simulate(days, func(d):
		return {"sold": 5 if d < 8 else 6, "stars_avg": minf(2.8, 2.0 + 0.06 * d), "earned": 0, "renombre": 0, "new_recipes": [], "journal": []}, 15)

func _rank_demo(name: String) -> void:
	Game.day = 1
	Game.renombre = 0
	Ranking.reset()
	ui.refresh_hud()
	# --ts=3: el tiempo del juego va 3 veces más rápido (capturas del final con el renderizador por software)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ts="):
			Engine.time_scale = maxf(0.1, float(arg.substr(5)))
	get_tree().create_timer(0.05).timeout.connect(func(): ui.refresh_hud())
	match name:
		"ranking", "rankpad":
			_rank_sim(11)
			Game.renombre = 165
			ui.refresh_hud()
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			await get_tree().create_timer(0.3).timeout
			ov.show_ranking()
			if name == "rankpad":
				await get_tree().create_timer(0.8).timeout
				for k in [KEY_DOWN, KEY_DOWN, KEY_RIGHT, KEY_UP]:
					var ev := InputEventKey.new()
					ev.keycode = k
					ev.physical_keycode = k
					ev.pressed = true
					Input.parse_input_event(ev)
					await get_tree().create_timer(0.25).timeout
		"rankmail":
			_rank_sim(8)
			ui.refresh_hud()
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			var r: Dictionary = {}
			for q in Data.VILLAGER_REQUESTS:
				if q["who"] == "panadera" and q["potion"] == "sueno_profundo" and r.is_empty():
					r = q.duplicate()
			r["kind"] = "villager"
			var it := {"kind": "potion", "id": "sueno_profundo", "potency": 7}
			var o := Story.make_outcome(r, it, true, Story.price_of(it))
			o["via"] = "letter"
			o["due"] = Game.day
			Game.schedule_outcome(o)
			_morning_mail()
		"gaceta", "gaceta5":
			_rank_sim(9 if name == "gaceta" else 4)
			ui.refresh_hud()
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			await get_tree().create_timer(0.3).timeout
			ov.show_gaceta()
		"ranksummary":
			_rank_sim(6)
			Game.today = {"earned": 96, "renombre": 14, "sold": 6, "new_recipes": [], "journal": [], "stars_avg": 2.6}
			Game.renombre += 14
			Ranking.commit_day()
			world.set_time(1.0, false)
			ov.show_summary(Game.day, Game.today)
		"ending", "credits":
			_rank_sim(29)
			Ranking.scores[Ranking.ME] = float(Ranking.scores[Ranking.order()[0]]) + 40.0
			Ranking.last_day = Game.day
			phase = Phase.CLOSING
			ui.set_gameplay_visible(false)
			if name == "credits":
				ov.show_credits()
				return
			fade.color.a = 1.0
			await _play_ending(true)
			print("ENDING done visto=", Ranking.ending_seen, " trofeo=", world.has_node("RankTrophy"))
		# la tienda de día con el caldero de oro en el mostrador (después del final) y una clienta esperando
		"ranktrophy":
			_rank_sim(31)
			Ranking.mark_ending_seen()
			EndingScene.place_trophy(world)
			for q in Data.VILLAGER_REQUESTS:
				if q["who"] == "nyra" and current.is_empty():
					current = q.duplicate()
			current["kind"] = "villager"
			customer = Actor.new()
			world.add_child(customer)
			customer.setup(Story.sprite_id("nyra"))
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			hint_given = true
			ui.order_who = "nyra"
			ui.show_order(Story.char_name("nyra"), current["text"], current["hint"])
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
		# la mañana después de llegar al 1: «¡La mejor tienda de Arvendal!»
		"rankmailtop":
			_rank_sim(29)
			Ranking.scores[Ranking.ME] = float(Ranking.scores[Ranking.order()[0]]) - 5.0
			Game.today = {"sold": 6, "stars_avg": 2.8}
			Game.renombre += 25
			Ranking.commit_day()
			Game.day += 1
			ui.refresh_hud()
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			_morning_mail()
		# ratón, teclado y mando: clic de verdad en el botón del HUD, G, Esc y el botón B del mando
		"rankinput":
			_rank_sim(6)
			phase = Phase.MORNING
			world.set_time(0.0, false)
			await get_tree().create_timer(0.5).timeout
			var bp: Vector2 = ui.rank_btn.get_global_rect().get_center()
			await _click_at(bp)
			await get_tree().create_timer(0.4).timeout
			print("RANKINPUT click HUD -> ", ov.current)
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			Input.parse_input_event(esc)
			await get_tree().create_timer(0.4).timeout
			print("RANKINPUT Esc -> '", ov.current, "'")
			for i in 2:
				var g := InputEventKey.new()
				g.keycode = KEY_G
				g.physical_keycode = KEY_G
				g.pressed = true
				Input.parse_input_event(g)
				await get_tree().create_timer(0.4).timeout
				var gu := g.duplicate()
				gu.pressed = false
				Input.parse_input_event(gu)
				await get_tree().create_timer(0.2).timeout
				print("RANKINPUT G -> '", ov.current, "'")
			Input.parse_input_event(g_key(true))
			await get_tree().create_timer(0.4).timeout
			print("RANKINPUT G (abre) -> '", ov.current, "' botones del mando=", pad._buttons().size())
			var jb := InputEventJoypadButton.new()
			jb.button_index = JOY_BUTTON_B
			jb.pressed = true
			Input.parse_input_event(jb)
			await get_tree().create_timer(0.4).timeout
			var jb2 := jb.duplicate()
			jb2.pressed = false
			Input.parse_input_event(jb2)
			await get_tree().create_timer(0.3).timeout
			print("RANKINPUT mando B -> '", ov.current, "'")
			get_tree().quit()

func g_key(pressed: bool) -> InputEventKey:
	var g := InputEventKey.new()
	g.keycode = KEY_G
	g.physical_keycode = KEY_G
	g.pressed = pressed
	return g
# --- end R4 RANK

# --- R4 MERGE: capturas y pruebas del juego unido ----------------------------------------------------------------------
## --demo=merge_shop: la tienda abierta a las 13:20 del día 6: Nyra en el mostrador con su ticket (la barra de paciencia),
## cuatro en la fila con sus relojes de arena, la ventanilla Krápido con Graznido esperando y tres pedidos en la bola, el
## reloj y la gente en la placa del HUD, el botón del Escalafón en el menú. Opciones: --ball (la bola abierta), --bench (el
## banco del caldero abierto), --window (ella junto a la ventanilla), --booked (un evento reservado para mañana: la etiqueta).
## --demo=merge_rankcheck: los puntos del Escalafón de un día de tienda (PACE), uno con Krápido (RAVEN) y uno de evento
## (EVENTS), con Ranking.day_points (sin pantalla; imprime y sale).
func _merge_demo(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if name == "merge_rankcheck":
		_merge_rankcheck()
		return
	if name == "merge_morning":
		_merge_morning(args)
		return
	if name == "merge_ledger":
		_merge_ledger(args)
		return
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 1
	Game.gold = 212
	Game.renombre = 9
	Ranking.simulate(5, func(_d): return {"sold": 9, "stars_avg": 2.6}, 3)   # cinco días jugados: ella sube en el Escalafón
	Game.upgrades = {"alfombra": true, "cojin": true, "huerto": true, "estante": true, "krapido": true}
	for id in Data.INGREDIENT_ORDER:
		Game.stock[id] = 4 if Game.ingredient_unlocked(id) else 0
	Game.unlock_magic()
	Game.potions = [{"id": "sueno_profundo", "potency": 7}, {"id": "balsamo_helado", "potency": 6},
		{"id": "vigor_verde", "potency": 5, "rune": "prisa", "rune_stars": 3}, {"id": "ojo_nocturno", "potency": 6}]
	Game.sort_potions()
	Game.krapido_reviews = [{"who": "anciano", "plumas": 5, "day": 4, "lost": false}, {"who": "pip", "plumas": 4, "day": 5, "lost": false}]
	if args.has("--booked"):
		Game.ev_booked = {"id": "torneo_7", "kind": "torneo", "day": 7, "sent": 5, "tier": 1, "fee": 26, "difficulty": 2,
			"plan": Events.plan("torneo", 1)}
	ov.close(false)
	_refresh_all()
	ui.set_gameplay_visible(true)
	ui.refresh_hud()
	phase = Phase.OPEN
	_pace_clear()
	queue = []
	_update_top_buttons()
	shop_t = 144.0
	world.set_time(0.12 + 0.8 * shop_t / Game.PACE_DAY_SECONDS, false)
	_update_time_label(0.12 + 0.8 * shop_t / Game.PACE_DAY_SECONDS)
	ui.set_clock_visible(true)
	_pace_on = true
	var req := _pace_demo_req("nyra")
	var cv := _pace_demo_visitor(req, ShopWorld.P_CUSTOMER, 0.48)
	cv["state"] = "counter"
	cv["ordered"] = true
	cv["counter_secs"] = Game.pace_counter_secs(req)
	_counter_v = cv
	current = req
	customer = cv["actor"]
	customer_ready = true
	hint_given = true
	ui.order_who = "nyra"
	ui.show_order(Story.char_name("nyra"), String(req["text"]), String(req["hint"]), Game.order_runes(req))
	cv["bubble"].visible = true
	var rows := [["granjero", 0.86], ["anciano", 0.62], ["marta", 0.4], ["pip", 0.2]]
	for i in rows.size():
		line.append(_pace_demo_visitor(_pace_demo_req(rows[i][0]), _pace_spot(i), rows[i][1]))
	krapido.demo_orders(3, true, "prisa")
	if args.has("--window") or args.has("--ball"):
		world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
	else:
		world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	events_ui.refresh_reminder()
	await get_tree().create_timer(0.4).timeout
	if args.has("--ball"):
		krapido.open_ball()
	elif args.has("--bench"):
		open_brew()

## --demo=merge_morning: la mañana del día 6 en orden: la invitación primero (Aceptar / Rechazar), después el correo
## (la línea del Escalafón arriba, la carta de un pedido de Krápido con sus plumas y la de un cliente del mostrador).
## --noinvite: sin invitación (el correo sale primero). --answer: contesta la invitación (acepta) al segundo.
func _merge_morning(args: PackedStringArray) -> void:
	Game.new_game_state()
	Game.tutorial_done = true
	Game.mail_seen = true
	Game.day = 1
	Game.renombre = 6
	Ranking.simulate(5, func(_d): return {"sold": 9, "stars_avg": 2.6}, 3)
	Game.gold = 140
	Game.upgrades["krapido"] = true
	var r: Dictionary = Data.KRAPIDO_ORDERS[0]
	var req := {"who": r["who"], "kind": "villager", "potion": r["potion"], "text": r["line"], "good": r["good"], "fail": r["fail"], "runes": []}
	var it := {"kind": "potion", "id": String(r["potion"]), "potency": 6}
	var o := Story.make_outcome(req, it, true, Story.price_of(it, req))
	o["via"] = "letter"
	o["due"] = Game.day
	o["krapido"] = true
	o["krapido_wait"] = 14.0
	Game.schedule_outcome(o)
	var vr := _pace_demo_req("granjero")
	var it2 := {"kind": "potion", "id": String(vr["potion"]), "potency": 6}
	var o2 := Story.make_outcome(vr, it2, true, Story.price_of(it2, vr))
	o2["via"] = "letter"
	o2["due"] = Game.day
	Game.schedule_outcome(o2)
	Game.ev_next = Game.day + (5 if args.has("--noinvite") else 0)
	_refresh_all()
	if args.has("--answer"):
		_merge_answer_later()
	_begin_day()

## --demo=event_<kind> --evwatch: (capturas) avanza la línea del anfitrión y, cuando el evento ya corre, cierra el banco
## como haría quien quiere mirar la escena: se ve la fila, el jurado y el HUD del evento.
func _ev_demo_watch() -> void:
	while not (is_instance_valid(ev_game) and ev_game.started):
		if ui.dialog_waiting():
			ui._advance()
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(0.6).timeout
	if _brew_open():
		brew.close_now()

func _merge_answer_later() -> void:
	while ov.current != "invite":
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	ov.answer_invitation(true)

## --demo=merge_ledger: el libro de cuentas de la noche del día 6 con todo: la fila de PACE, Krápido (RAVEN) y el
## Escalafón (RANK, ya sumado). --event: la noche de un evento (la medalla, «Tienda cerrada», el sello de la medalla).
func _merge_ledger(args: PackedStringArray) -> void:
	Game.new_game_state()
	Game.tutorial_done = true
	Game.day = 1
	Game.renombre = 6
	Ranking.simulate(5, func(_d): return {"sold": 9, "stars_avg": 2.6}, 3)
	Game.upgrades["krapido"] = true
	Game.reset_today()
	phase = Phase.CLOSING
	world.set_time(1.0, false)
	ui.set_time_label("Night")
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	if args.has("--event"):
		Game.ev_trophies = [{"kind": "academia", "medal": "gold", "day": Game.day}]
		var h := {"id": "academia_6", "kind": "academia", "day": Game.day, "medal": "gold", "points": 150, "tier": 1}
		Events.today_entry(h)
		Game.today["earned"] = 145
		Game.renombre += 13
		Game.today["renombre"] = 13
		world.refresh_trophies(true)
	else:
		var td := {"earned": 318, "renombre": 9, "sold": 14, "arrived": 17, "served": 14, "lost_tired": 1, "lost_full": 2,
			"lost_closed": 0, "declined": 0, "avg_wait": 26.5, "speed_tips": 41, "renombre_lost": 1, "deliveries": 3,
			"deliveries_lost": 1, "plumas": 4.1, "new_recipes": [], "journal": []}
		for k in td:
			Game.today[k] = td[k]
		Game.renombre += 8
	Ranking.commit_day()
	_refresh_all()
	ov.show_summary(Game.day, Game.today)

## Los puntos del Escalafón con un día de cada tipo (los números de Game.today que escriben PACE, RAVEN y EVENTS).
func _merge_rankcheck() -> void:
	Game.new_game_state()
	Game.renombre = 20
	Ranking.ren_base = 8
	var days := {
		"tienda (PACE)": {"earned": 260, "renombre": 8, "sold": 13, "served": 13, "lost_tired": 2, "lost_full": 1, "avg_wait": 24.0},
		"tienda + Krápido (RAVEN)": {"earned": 300, "renombre": 8, "sold": 13, "served": 13, "lost_tired": 2, "deliveries": 3, "deliveries_lost": 1, "plumas": 4.2},
		"evento (EVENTS, oro)": {"earned": 120, "renombre": 13, "sold": 0, "event": {"id": "academia_5", "kind": "academia", "medal": "gold", "points": 150}},
		"evento (EVENTS, sin medalla)": {"earned": 0, "renombre": -4, "sold": 0, "event": {"id": "concurso_9", "kind": "concurso", "medal": "none", "points": -10}},
	}
	for k in days:
		Game.renombre = Ranking.ren_base + int(days[k]["renombre"])   # el renombre ganado ese día
		var r: Dictionary = Ranking.day_points(days[k])
		print("RANKCHECK ", k, " total=", r.get("total", 0), " partes=", r.get("parts", {}), " medalla=", r.get("medal", ""))
	get_tree().quit()
# --- end R4 MERGE

# --- R6 UI: los avisos de acción, los botones de arriba y las teclas nuevas ------------------------------------------
# PromptBrain (scripts/ui/prompt_brain.gd) mira cada cuadro dónde está ella y qué se puede hacer, y PromptUI dibuja el
# aviso («E  Give potion · Space  Talk») sobre la persona o la estación; Glyphs sabe si lo último fue el teclado, el
# ratón o el mando (y dibuja su tecla o su botón). Teclas: E y Espacio = lo que dice el aviso; O = abrir la tienda;
# M = el mercado (ir, volver, o de día el encargo); Tab = el estante con el banco abierto; en el diálogo 1 / 2 / 3; en
# el estante para elegir ← → y E. El mando: A hace el aviso (o toca donde está su cursor), X la segunda acción.
var prompt_brain: PromptBrain

func _r6_setup() -> void:
	prompt_brain = PromptBrain.new()
	prompt_brain.name = "PromptBrain"
	add_child(prompt_brain)
	prompt_brain.setup(self)
	pad.brain = prompt_brain
	for a in OS.get_cmdline_user_args():
		if a == "--r6dbg":   # (depuración) dónde va cada aviso y qué lo empujó
			PromptUI.debug = true
		if a.begins_with("--glyphs="):   # (capturas y pruebas) fija el dispositivo de los glifos
			Glyphs.forced = a.substr(9)
			Glyphs.device = Glyphs.forced
			Glyphs.gen += 1
	# el vigilante del dispositivo va el último: su _input llega antes que el de nadie (también antes que PadCursor)
	var gw := Glyphs.GlyphWatcher.new()
	gw.name = "GlyphWatcher"
	add_child(gw)

## La fase como palabra (PromptBrain y PadCursor no ven el enum): "TITLE", "INTRO", "MORNING", "OPEN", "CLOSING", "EVENT".
func r6_phase() -> String:
	return Phase.keys()[phase]

## E / Espacio / Tab / O / M. true si la tecla hizo algo (entonces no sigue).
func _r6_key(ev: InputEventKey) -> bool:
	match ev.keycode:
		KEY_E:
			return prompt_brain.press("interact")
		KEY_SPACE:
			return prompt_brain.press("alt")
		KEY_TAB:
			return prompt_brain.press("shelf")
		KEY_O:
			if phase == Phase.MORNING and open_btn.is_visible_in_tree() and not open_btn.disabled and _r6_hands_free():
				_open_shop()
				return true
		KEY_M:
			if not _r6_hands_free():
				return false
			if phase == Phase.MORNING and trip_btn.is_visible_in_tree() and not trip_btn.disabled:
				_on_trip_button()
				return true
			if phase == Phase.OPEN:
				_on_menu("market")   # de día: el encargo de Pip (x2)
				return true
	return false

## Nada abierto ni a medias (para las teclas de los botones de arriba).
func _r6_hands_free() -> bool:
	return not ov.is_open() and not ui.dialog_open() and not busy and not _trip_busy and not _brew_open() and not _ball_open() and not ui.picker_open()

# ------------------------------------------------ capturas (--demo=r6_<escena> [--glyphs=keys|mouse|pad] [--hover=...])
## Una partida de prueba: día 3, tres pociones distintas en el estante, el grimorio abierto (el escritorio dice
## «Enchant»), con o sin la ventanilla del cuervo.
func _r6_state(krapido_on := false) -> void:
	Game.new_game_state()
	Game.tutorial_done = true
	Game.mail_seen = true
	Game.day = 3
	Game.gold = 140
	Game.renombre = 14
	Game.upgrades = {"alfombra": true, "cojin": true, "huerto": true, "farolillos": true}
	if krapido_on:
		Game.upgrades["krapido"] = true
	Game.unlock_magic()
	Game.potions = [{"id": "ojo_nocturno", "potency": 6}, {"id": "balsamo_helado", "potency": 4}, {"id": "sueno_profundo", "potency": 7}]
	Game.sort_potions()
	for id in Data.INGREDIENT_ORDER:
		Game.stock[id] = 4 if Game.ingredient_unlocked(id) else 0
	ov.close(false)
	_refresh_all()
	world.refresh_upgrades()
	ui.set_gameplay_visible(true)
	ui.refresh_hud()

func _r6_morning(x: float, face := 1) -> void:
	phase = Phase.MORNING
	world.set_time(0.0, false)
	ui.set_time_label("Morning")
	ui.set_clock_visible(false)
	world.set_station_label("puerta", "Door · to the market")
	_update_top_buttons()
	world.walker.teleport(x, face)
	world.snap_camera()

## La tienda abierta a media mañana con alguien en el mostrador (ordered: ya pidió; si no, todavía no) y tres en la fila.
func _r6_open_day(who: String, ordered: bool, queue_n := 3) -> void:
	phase = Phase.OPEN
	_pace_clear()
	queue = []
	_update_top_buttons()
	shop_t = 110.0
	world.set_time(0.12 + 0.8 * shop_t / Game.PACE_DAY_SECONDS, false)
	_update_time_label(0.12 + 0.8 * shop_t / Game.PACE_DAY_SECONDS)
	ui.set_clock_visible(true)
	_pace_on = true
	var req := _pace_demo_req(who)
	var cv := _pace_demo_visitor(req, ShopWorld.P_CUSTOMER, 0.8)
	cv["fidget"] = 9999.0
	cv["state"] = "counter"
	cv["ordered"] = ordered
	cv["counter_secs"] = Game.pace_counter_secs(req) * 3.0
	cv["line_secs"] = 600.0
	_counter_v = cv
	current = req
	customer = cv["actor"]
	customer_ready = true
	hint_given = true
	if ordered:
		ui.order_who = who
		ui.show_order(Story.char_name(who), String(req["text"]), String(req["hint"]), Game.order_runes(req))
		cv["bubble"].visible = true
	else:
		cv["bubble"].visible = false
	var rows := [["granjero", 0.9], ["anciano", 0.6], ["pip", 0.35], ["marta", 0.75]]
	for i in mini(queue_n, rows.size()):
		var v := _pace_demo_visitor(_pace_demo_req(rows[i][0]), _pace_spot(i), rows[i][1])
		v["line_secs"] = 600.0
		v["fidget"] = 9999.0
		line.append(v)
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()

## (r6_concurso) ya corriendo y con el banco cerrado, una poción en el estante para presentar.
func _r6_concurso_potion() -> void:
	while not (is_instance_valid(ev_game) and ev_game.started and ev_game.running and not _brew_open()):
		await get_tree().create_timer(0.2).timeout
	Game.potions = [{"id": "sueno_profundo", "potency": 7}]
	Game.potions_changed.emit()

func _r6_demo(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if name == "r6_prompttest":
		await _r6_prompttest()
		return
	_r6_state(name in ["r6_window", "r6_orders"])
	match name:
		"r6_morning":   # de mañana detrás del mostrador: «Open shop» y los botones de arriba
			_r6_morning(ShopWorld.P_ALCH_COUNTER.x, 1)
		"r6_door":   # de mañana junto a la puerta: «Go to market»
			_r6_morning(float(ShopWorld.STATIONS["puerta"]["x"]), 1)
		"r6_cauldron":
			_r6_morning(float(ShopWorld.STATIONS["caldero"]["x"]), -1)
		"r6_desk":
			_r6_morning(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
		"r6_market", "r6_marketdoor":   # el mercado: en el puesto de Borin («Buy») o en la puerta de la tienda
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			_switch_place(true, false)
			if name == "r6_market":
				market.walker.teleport(float(MarketWorld.STALL_X["borin"]) + 1.3, -1)
			else:
				market.walker.teleport(MarketWorld.SHOP_DOOR_X, -1)
			market.snap_camera()
		"r6_talk":   # ya pidió pero el estante está vacío: «Talk» (pedir una pista o decir que no)
			Game.potions = []
			Game.potions_changed.emit()
			_r6_open_day("nyra", true)
		"r6_give", "r6_picker":   # ya pidió y hay tres pociones distintas: «Give potion · Talk» (o el estante abierto)
			_r6_open_day("nyra", true)
			if name == "r6_picker":
				await get_tree().create_timer(0.3).timeout
				ui.open_picker("Give")
				ui._pick_move(1)
		"r6_give1":   # una sola clase de poción: «Give» con su icono
			var want := String(_pace_demo_req("nyra")["potion"])
			Game.potions = [{"id": want, "potency": 7}]
			Game.potions_changed.emit()
			_r6_open_day("nyra", true)
		"r6_dialog":   # lo que pide, con las respuestas y sus teclas
			_r6_open_day("nyra", false)
			_talk_request()
		"r6_window", "r6_orders":   # la ventanilla del cuervo: «Hand over» (espera) o «Read orders»
			_r6_open_day("nyra", true, 2)
			krapido.demo_orders(3, name == "r6_window")
			krapido._active = true
			world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
			world.snap_camera()
		"r6_bench":   # el banco con dos ingredientes en la olla: las teclas de los frascos, Remover y cerrar
			_r6_open_day("nyra", true)
			world.walker.teleport(float(ShopWorld.STATIONS["caldero"]["x"]), -1)
			world.snap_camera()
			await get_tree().create_timer(0.2).timeout
			open_brew()
			await get_tree().create_timer(0.8).timeout
			for id in ["raiz_mandragora", "hongo_violeta"]:
				brew.throw(id)
				await get_tree().create_timer(0.7).timeout
		"r6_concurso":   # el concurso corriendo con una poción en el estante: «Space  Present» sobre el estante
			_ev_demo_state(20)
			Events.make_invite("concurso")
			Game.ev_booked = Game.ev_invite
			Game.ev_invite = {}
			Game.ev_booked["day"] = Game.day
			phase = Phase.EVENT
			_ev_enter_scene(Game.ev_booked.duplicate(true))
			_ev_demo_watch.call_deferred()
			_r6_concurso_potion.call_deferred()
			await _ev_play(Game.ev_booked.duplicate(true))
		"r6_benchgive":   # el banco abierto con alguien esperando: «Tab  Give» sobre el estante
			_r6_open_day("nyra", true)
			world.walker.teleport(float(ShopWorld.STATIONS["caldero"]["x"]), -1)
			world.snap_camera()
			await get_tree().create_timer(0.2).timeout
			open_brew()
		"r6_ledger":
			Game.reset_today()
			for k in {"earned": 212, "renombre": 8, "sold": 9, "arrived": 11, "served": 9, "lost_tired": 1, "avg_wait": 22.0}:
				Game.today[k] = {"earned": 212, "renombre": 8, "sold": 9, "arrived": 11, "served": 9, "lost_tired": 1, "avg_wait": 22.0}[k]
			phase = Phase.CLOSING
			world.set_time(1.0, false)
			ui.set_time_label("Night")
			_update_top_buttons()
			ov.show_summary(Game.day, Game.today)
		"r6_mail":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Morning")
			_update_top_buttons()
			for who in ["panadera", "granjero"]:
				var r := _pace_demo_req(who)
				var it := {"kind": "potion", "id": String(r["potion"]), "potency": 7}
				var o := Story.make_outcome(r, it, true, Story.price_of(it, r))
				o["via"] = "letter"
				o["due"] = Game.day
				Game.schedule_outcome(o)
			_morning_mail()
		"r6_title":
			ui.set_gameplay_visible(false)
			ov.show_title(true)
		"r6_vendor":   # (resume 3) el puesto de Ilse con el teclado: Tab marca el segundo botón (el aro y la placa de abajo)
			_r6_morning(float(ShopWorld.STATIONS["puerta"]["x"]), 1)
			ov.show_market("morning", "ilse")
			await get_tree().create_timer(0.5).timeout
			for i in 2:
				await _r6_tap(KEY_TAB)
		"r6_invite":   # (resume 3) la invitación con sus teclas 1 / 2
			_r6_morning(ShopWorld.P_ALCH_COUNTER.x, 1)
			ov.show_invitation(Events.make_invite("academia"))
	# --hover=<botón>: el cursor (el del mando con --glyphs=pad) encima de un botón, para ver su estado y su tooltip
	for a in args:
		if a.begins_with("--hover="):
			await get_tree().create_timer(0.6).timeout
			_r6_hover(a.substr(8))

func _r6_hover(what: String) -> void:
	var c: Control = null
	match what:
		"open":
			c = open_btn
		"trip":
			c = trip_btn
		"choice2":
			c = ui.dialog_choices.get_child(1) if ui.dialog_choices.get_child_count() > 1 else null
		_:
			for b in ui.menu_box.get_children():
				if String(b.get_meta("menu", "")) == what:
					c = b
	if c == null:
		return
	var at := c.get_global_rect().get_center()
	if Glyphs.device == "pad":
		pad._show(true)
		pad._move_to(at)
	else:
		var mm := InputEventMouseMotion.new()
		mm.position = get_viewport().get_final_transform() * at
		mm.global_position = mm.position
		Input.parse_input_event(mm)

# ------------------------------------------------ la prueba de los avisos (--demo=r6_prompttest, sin ventana)
var _r6_bad := 0

func _r6_check(what: String, ok: bool, extra = "") -> void:
	if not ok:
		_r6_bad += 1
	print("R6TEST %s %s %s" % ["ok  " if ok else "FAIL", what, str(extra)])

func _r6_wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _r6_tap(code: Key, from_pad := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		if from_pad:
			e.device = PadCursor.PAD_DEVICE
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame

func _r6_pad(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var e2 := e.duplicate()
	e2.pressed = false
	Input.parse_input_event(e2)
	await get_tree().process_frame
	await get_tree().process_frame

func _r6_prompt(id: String) -> String:
	var cur := prompt_brain.current()
	if not cur.has(id):
		return ""
	return " · ".join((cur[id] as Array).map(func(a): return String(a[1])))

func _r6_prompttest() -> void:
	Engine.time_scale = 2.0
	_r6_state(true)
	# 1) el dispositivo: tecla -> teclado, ratón que se mueve -> ratón, botón del mando -> mando
	await _r6_tap(KEY_SHIFT)
	await _r6_tap(KEY_K)
	var k_dev := Glyphs.device
	for i in 6:
		var mm := InputEventMouseMotion.new()
		mm.relative = Vector2(9, 0)
		mm.position = Vector2(400 + i * 9, 300)
		Input.parse_input_event(mm)
	await get_tree().process_frame
	var m_dev := Glyphs.device
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_LEFT_STICK
	jb.pressed = true
	Input.parse_input_event(jb)
	await get_tree().process_frame
	var p_dev := Glyphs.device
	_r6_check("dispositivo tecla/ratón/mando", k_dev == "keys" and m_dev == "mouse" and p_dev == "pad", [k_dev, m_dev, p_dev])
	pad._show(false)
	await _r6_tap(KEY_K)
	# 2) de mañana detrás del mostrador: «Open shop»; los botones de arriba; O abre la tienda
	_r6_morning(ShopWorld.P_ALCH_COUNTER.x, 1)
	await _r6_wait(0.3)
	_r6_check("mañana mostrador", _r6_prompt("counter") == "Open shop", _r6_prompt("counter"))
	_r6_check("botones de arriba", open_btn.visible and trip_btn.visible and open_btn.text == "Open shop" and trip_btn.text == "Market", [open_btn.text, trip_btn.text])
	await _r6_tap(KEY_O)
	_r6_check("O abre la tienda", phase == Phase.OPEN, r6_phase())
	_pace_clear()
	krapido.reset_day()
	# 3) de mañana: caldero «Brew» (E abre el banco), escritorio «Enchant» (E abre el grimorio), puerta «Go to market»
	_r6_morning(float(ShopWorld.STATIONS["caldero"]["x"]), -1)
	await _r6_wait(0.3)
	_r6_check("caldero", _r6_prompt("cauldron") == "Brew", _r6_prompt("cauldron"))
	await _r6_tap(KEY_E)
	await _r6_wait(0.6)
	_r6_check("E abre el banco", _brew_open(), _brew_open())
	# (resume 3) en el banco: 1 echa el primer ingrediente y Supr vacía el caldero (su tecla en el botón «Empty»)
	await _r6_tap(KEY_1)
	await _r6_wait(1.0)
	var n1 := contents.size()
	await _r6_tap(KEY_DELETE)
	await _r6_wait(0.8)
	_r6_check("banco: 1 echa, Supr vacía", n1 >= 1 and contents.is_empty(), [n1, contents.size()])
	brew.close_now()
	_r6_morning(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
	await _r6_wait(0.3)
	_r6_check("escritorio", _r6_prompt("desk") == "Enchant", _r6_prompt("desk"))
	await _r6_tap(KEY_E)
	await _r6_wait(0.6)
	_r6_check("E abre el grimorio", ov.current == "grimoire", ov.current)
	ov.close()
	await _r6_wait(0.3)
	_r6_morning(float(ShopWorld.STATIONS["puerta"]["x"]), 1)
	await _r6_wait(0.3)
	_r6_check("puerta", _r6_prompt("door") == "Go to market", _r6_prompt("door"))
	# 4) M va al mercado; en el puesto «Buy» y E abre el puesto; Esc lo cierra; M vuelve a la tienda
	await _r6_tap(KEY_M)
	var w := 0.0
	while not in_market and w < 8.0:
		await _r6_wait(0.2)
		w += 0.2
	_r6_check("M va al mercado", in_market and trip_btn.text == "Back to shop", [in_market, trip_btn.text])
	while _trip_busy or market.walker.frozen:
		await _r6_wait(0.1)
	market.walker.teleport(float(MarketWorld.STALL_X["ilse"]) + 1.3, -1)
	await _r6_wait(0.3)
	_r6_check("puesto", _r6_prompt("stall") == "Buy", _r6_prompt("stall"))
	await _r6_tap(KEY_E)
	await _r6_wait(0.8)
	_r6_check("E abre el puesto", ov.current == "market", ov.current)
	await _r6_tap(KEY_ESCAPE)
	await _r6_wait(0.3)
	market.walker.teleport(MarketWorld.SHOP_DOOR_X, -1)
	await _r6_wait(0.3)
	_r6_check("puerta de la tienda", _r6_prompt("shopdoor") == "Back to shop", _r6_prompt("shopdoor"))
	await _r6_tap(KEY_M)
	w = 0.0
	while (in_market or _trip_busy) and w < 10.0:
		await _r6_wait(0.2)
		w += 0.2
	_r6_check("M vuelve a la tienda", not in_market and trip_btn.text == "Market", [in_market, trip_btn.text])
	# 5) la tienda abierta: el cliente ya pidió y hay tres pociones: «Give potion · Talk»; E abre el estante, → elige,
	# E se la da (la entrega de siempre)
	_r6_state(true)
	_r6_open_day("nyra", true)
	await _r6_wait(0.4)
	_r6_check("mostrador con pociones", _r6_prompt("counter") == "Give potion · Talk", _r6_prompt("counter"))
	await _r6_tap(KEY_E)
	_r6_check("E abre el estante", ui.picker_open(), ui.picker_open())
	await _r6_wait(0.1)
	_r6_check("aviso del estante", _r6_prompt("picker") == "Choose · Give · Back", _r6_prompt("picker"))
	await _r6_tap(KEY_RIGHT)
	var sel := ui.picker_index()
	await _r6_tap(KEY_D)
	_r6_check("→ y D eligen", sel == 1 and ui.picker_index() == 2 and not world.walker.is_walking(), [sel, ui.picker_index()])
	await _r6_tap(KEY_A)
	var given_id := String(Game.potions[ui.picker_index()]["id"])
	var n0 := Game.potions.size()
	await _r6_tap(KEY_E)
	w = 0.0
	while not bool(_counter_v.get("handed", false)) and w < 6.0:
		await _r6_wait(0.2)
		w += 0.2
	_r6_check("E se la da", Game.potions.size() == n0 - 1 and bool(_counter_v.get("handed", false)), [given_id, Game.potions.size()])
	var served0 := served
	await _r6_wait(0.3)
	await _r6_tap(KEY_E)   # (la despedida: E termina de escribirla...)
	await _r6_wait(0.2)
	await _r6_tap(KEY_E)   # (...y E elige la única respuesta: se va)
	await _r6_wait(2.5)
	_r6_check("E se despide (pasa el siguiente de la fila)", served == served0 + 1, [served0, served])
	# 6) Espacio = «Talk»: el diálogo con sus respuestas; 2 pide la pista; 1 «Got it»
	ui.hide_dialog()
	_r6_state(true)
	_r6_open_day("nyra", true)
	hint_given = false
	await _r6_wait(0.4)
	await _r6_tap(KEY_SPACE)
	await _r6_wait(0.2)
	await _r6_tap(KEY_SPACE)   # termina de escribirse
	var labels: Array = ui.dialog_choices.get_children().map(func(b): return String(b.text))
	_r6_check("Espacio habla (respuestas)", ui.dialog_open() and labels == ["Brew it", "A hint?", "I can't"], labels)
	await _r6_tap(KEY_2)
	await _r6_wait(0.2)
	_r6_check("2 pide la pista", hint_given and ui.dialog_open(), hint_given)
	await _r6_tap(KEY_ENTER)
	await _r6_wait(0.1)
	await _r6_tap(KEY_1)
	_r6_check("1 «Got it»", not ui.dialog_open() and ui.order_card.visible, ui.dialog_open())
	# 7) el mando: A (sin cursor encima de nada) abre el estante, la cruceta elige, A la da; X habla; B cierra el estante
	_r6_state(true)
	_r6_open_day("nyra", true)
	Glyphs.forced = ""
	await _r6_wait(0.4)
	pad._show(false)
	await _r6_pad(JOY_BUTTON_A)
	_r6_check("mando A abre el estante", ui.picker_open(), [ui.picker_open(), Glyphs.device])
	await _r6_pad(JOY_BUTTON_DPAD_RIGHT)
	_r6_check("cruceta elige", ui.picker_index() == 1, ui.picker_index())
	await _r6_pad(JOY_BUTTON_B)
	_r6_check("B cierra el estante", not ui.picker_open(), ui.picker_open())
	await _r6_pad(JOY_BUTTON_X)
	await _r6_wait(0.2)
	_r6_check("X habla", ui.dialog_open(), ui.dialog_open())
	await _r6_pad(JOY_BUTTON_A)   # termina de escribirse (A avanza el diálogo)
	await _r6_wait(0.1)
	pad._park(true)
	await _r6_pad(JOY_BUTTON_A)   # sin cursor: la primera respuesta («Brew it»)
	await _r6_wait(0.2)
	_r6_check("A elige la primera respuesta", not ui.dialog_open(), ui.dialog_open())
	await _r6_pad(JOY_BUTTON_A)
	await _r6_wait(0.1)
	await _r6_pad(JOY_BUTTON_DPAD_RIGHT)
	await _r6_pad(JOY_BUTTON_A)
	w = 0.0
	while not bool(_counter_v.get("handed", false)) and w < 6.0:
		await _r6_wait(0.2)
		w += 0.2
	_r6_check("mando: A, cruceta, A se la da", bool(_counter_v.get("handed", false)), Game.potions.size())
	# 8) los botones de arriba y la barra de la derecha: tamaño, alineación y tooltips con su tecla
	var bar_ok := true
	for b in ui.menu_box.get_children():
		bar_ok = bar_ok and b is HudButton and (b as Control).size == Vector2(66, 66) and (b as HudButton).tip_title != ""
	_r6_check("barra de la derecha", bar_ok and ui.rank_btn is HudButton, ui.menu_box.get_child_count())
	# 9) la bola con el mando: A en la ventanilla la abre, la cruceta elige en la bandeja y A le da la poción a Graznido
	_r6_state(true)
	ui.hide_dialog()
	_r6_open_day("nyra", true, 0)
	krapido.demo_orders(3, true)
	krapido._active = true
	var want := String(krapido.raven_order.get("potion", ""))
	Game.potions.append({"id": want, "potency": 6})
	Game.sort_potions()
	_refresh_all()
	world.walker.teleport(float(ShopWorld.KRAPIDO_STATION["x"]), -1)
	world.snap_camera()
	await _r6_wait(0.4)
	_r6_check("ventanilla Hand over", _r6_prompt("window") == "Hand over", [_r6_prompt("window"), world.current_station(), prompt_brain._free(),
		world.walker.frozen, world.walker._has_target, ov.current, ui.dialog_open(), busy, krapido.active(), r6_phase()])
	await _r6_pad(JOY_BUTTON_A)
	await _r6_wait(0.6)
	_r6_check("A abre la bola", krapido.ball_open(), krapido.ball_open())
	var idx := -1
	for i in Game.potions.size():
		if String(Game.potions[i]["id"]) == want and idx < 0:
			idx = i
	var s0: int = krapido.ball._sel
	await _r6_pad(JOY_BUTTON_DPAD_RIGHT)
	var s1: int = krapido.ball._sel
	_r6_check("cruceta elige en la bandeja", s1 == mini(s0 + 1, Game.potions.size() - 1) and krapido.ball.keys_row.visible, [s0, s1])
	var guard := 0
	while krapido.ball._sel != idx and guard < 8:
		await _r6_pad(JOY_BUTTON_DPAD_RIGHT if idx > krapido.ball._sel else JOY_BUTTON_DPAD_LEFT)
		guard += 1
	var d0 := int(Game.today.get("deliveries", 0))
	await _r6_pad(JOY_BUTTON_A)
	var wk := 0.0
	while krapido.raven_state != "away" and wk < 8.0:
		await _r6_wait(0.2)
		wk += 0.2
	_r6_check("A se la da a Graznido", int(Game.today.get("deliveries", 0)) == d0 + 1, [want, idx, krapido.raven_state])
	# (resume 3) los papeles con el teclado: Tab marca un botón y Intro lo pulsa (el puesto de Ilse: un «+» compra);
	# la invitación: 2 la rechaza (Intro sola no la acepta)
	krapido.ball.close_now()
	pad._show(false)
	await _r6_tap(KEY_K)
	Game.gold = 500
	ov.show_market("morning", "ilse")
	await _r6_wait(0.4)
	var kb: Array = ov._kf_buttons()
	var plus := -1
	for i in kb.size():
		if (kb[i] is Button) and String((kb[i] as Button).text).begins_with("+"):
			plus = i
			break
	var g0 := Game.gold
	for i in plus + 1:
		await _r6_tap(KEY_TAB)
	var marked: int = ov._kf_i
	await _r6_tap(KEY_ENTER)
	await _r6_wait(0.2)
	_r6_check("papel: Tab marca, Intro compra", plus >= 0 and marked == plus and Game.gold < g0 and ov._kf_hint.visible, [plus, marked, g0, Game.gold])
	ov.close(false)
	await _r6_wait(0.2)
	var said := []
	var cb := func(acc: bool): said.append(acc)
	ov.invite_answered.connect(cb)
	ov.show_invitation(Events.make_invite("academia"))
	await _r6_wait(0.4)
	await _r6_tap(KEY_ENTER)
	var still := ov.current == "invite"
	await _r6_tap(KEY_2)
	_r6_check("invitación: Intro no acepta, 2 rechaza", still and said == [false] and ov.current != "invite", [still, said, ov.current])
	ov.invite_answered.disconnect(cb)
	print("R6TEST ", "OK" if _r6_bad == 0 else "FALLO (%d)" % _r6_bad)
	get_tree().quit()
# --- end R6 UI

# --- R6 MERGE: los dos carriles juntos ------------------------------------------------------------------------------
# --demo=m6_evprompt --evkind=academia|concurso|torneo: el día del evento entero como en el juego (el cartel, el mapa
# del viaje con el escenario que PERF arma por partes y precalienta debajo, el negro, el fundido de entrada) y después,
# con el teclado como un jugador: la línea del anfitrión, la cuenta atrás, el banco, el botón «Cauldron» y los avisos
# (en el concurso «Space Present» sobre el estante). Mira en cada cuadro que ningún aviso salga mientras el mapa o el
# negro tapan la escena, que el HUD esté completo y limpio (sin restos del precalentamiento) en el primer cuadro a la
# vista y cuánto tardan el HUD y los avisos desde ese cuadro. Imprime M6TEST ... y sale.
var _m6_bad := 0
var _m6_log := {}

func _m6_check(what: String, ok: bool, extra = "") -> void:
	if not ok:
		_m6_bad += 1
	print("M6TEST %s %s %s" % ["ok  " if ok else "FAIL", what, str(extra)])

func _m6_demo(name: String) -> void:
	match name:
		"m6_evprompt":
			await _m6_evprompt()
		"m6_fontprobe":
			await _m6_fontprobe()
		"m6_juryprobe":
			await _m6_juryprobe()
	get_tree().quit()

## (sonda) los tamaños/contornos que la caché de las fuentes tiene, con cuántas letras y texturas.
func _m6_font_state(tag: String) -> void:
	var ts := TextServerManager.get_primary_interface()
	PaperKit.load_fonts()
	var fonts: Array = [UIKit.font_regular, UIKit.font_bold, UIKit.font_italic, UIKit.font_sc, UIKit.font_sc_bold,
		PaperKit.font_hand, PaperKit.font_hand_bold]
	var k := 0
	while k < fonts.size():   # y sus respaldos
		for fb in (fonts[k] as Font).fallbacks:
			if not fonts.has(fb):
				fonts.append(fb)
		k += 1
	var rids := []
	for f in fonts:
		for rid in (f as Font).get_rids():
			if rids.has(rid):
				continue
			rids.append(rid)
			for sz in ts.font_get_size_cache_list(rid):
				print("M6FONT %s | %s/%s %s glyphs=%d tex=%d" % [tag, ts.font_get_name(rid), ts.font_get_style_name(rid), sz,
					ts.font_get_glyph_list(rid, sz).size(), ts.font_get_texture_count(rid, sz)])

## --demo=m6_fontprobe: el arranque (con su precalentamiento), el banco abierto y el aviso del concurso: qué entradas de
## la caché de letras aparecen con el aviso (las que el precalentamiento no cubrió).
func _m6_fontprobe() -> void:
	_ev_demo_state(20)
	phase = Phase.MORNING
	_update_top_buttons()
	await _warm_places()
	await _frames(3)
	_m6_font_state("1warm")
	print("M6MARK bench ", Time.get_ticks_msec())
	open_brew()
	await _r6_wait(1.0)
	_m6_font_state("2bench")
	print("M6MARK tip ", Time.get_ticks_msec())
	brew.say("Tap it on the shelf to present it", UIKit.GOLD_BRIGHT)
	await _r6_wait(1.0)
	_m6_font_state("3tip")
	print("M6MARK end ", Time.get_ticks_msec(), " perf:end")

## --demo=m6_juryprobe [--m6nocards] [--m6results]: el arranque, las letras de las tarjetas como en EventGame.warm_up
## y la tarjeta del jurado del concurso (o la de resultados de la academia): qué entradas de la caché de letras trae la
## tarjeta que el precalentamiento no cubrió.
func _m6_juryprobe() -> void:
	var results := OS.get_cmdline_user_args().has("--m6results")
	_ev_demo_state(20)
	phase = Phase.MORNING
	_update_top_buttons()
	await _warm_places()
	if not OS.get_cmdline_user_args().has("--m6nocards"):
		for g in EventGame.card_letter_groups("academia" if results else "concurso"):
			var lay := EventGame.card_letter_layer(g)
			add_child(lay)
			await _frames(2)
			lay.queue_free()
	await _frames(2)
	_m6_font_state("1warm")
	if results:
		events_ui.show_hud("academia")
		events_ui.show_results({"kind": "academia", "medal": "gold", "reward": {"gold": 145, "renombre": 13, "trophy": true},
			"rows": [["res://assets/icons/pot_sueno_profundo.png", "Potions delivered", "10 / 10"],
				["res://assets/icons/emote_star.png", "Points (stars)", "27 / 30"], ["paper_i_hourglass", "Finished early", "+2"]],
			"line": String(Events.info("academia")["end"]["gold"])})
		await _r6_wait(3.0)
		_m6_font_state("2jury")
		print("M6MARK end perf:end")
		return
	events_ui.show_hud("concurso")
	var th: Dictionary = Events.THEMES[0]
	events_ui.show_jury({"round": 1, "theme": String(th["text"]), "potion": {"id": "sueno_profundo", "potency": 7, "perfect": true},
		"scores": [4, 3, 5], "lines": [Events.JUDGE_LINES["elda"][3], Events.JUDGE_LINES["lirien"][2], Events.JUDGE_LINES["grumm"][4]],
		"table": [{"name": "You", "round": 12, "total": 12, "me": true}, {"name": "Fizz", "round": 11, "total": 11},
			{"name": "Roots & Dew", "round": 9, "total": 9}, {"name": "Fordside Herbs", "round": 8, "total": 8}],
		"last": false, "fizz_line": Events.FIZZ_LINES["low"][0]})
	await _r6_wait(3.0)
	_m6_font_state("2jury")
	print("M6MARK end perf:end")

## true mientras el mapa del viaje (opaco) o el negro tapan la pantalla.
func _m6_covered() -> bool:
	var bg = events_ui.get("_map_bg")
	if bg is CanvasItem and is_instance_valid(bg) and (bg as CanvasItem).is_visible_in_tree() and (bg as CanvasItem).modulate.a >= 0.999:
		return true
	return fade.color.a >= 0.999

## Cada cuadro, mientras dura la prueba: avisos con la escena tapada, el primer cuadro a la vista, el HUD, los avisos.
func _m6_watch() -> void:
	var t := 0.0
	var f := 0
	while is_inside_tree() and not _m6_log.get("stop", false):
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.001)
		f += 1
		var plates: Array = ui.prompts.visible_prompts()
		var acts := prompt_brain.has_action("interact") or prompt_brain.has_action("alt")
		if _ev_active and not _m6_log.has("enter"):
			_m6_log["enter"] = [f, t]
		var cov := _m6_covered()
		if _ev_active and cov and (not plates.is_empty() or acts):
			_m6_log["covered_prompt"] = int(_m6_log.get("covered_prompt", 0)) + 1
		if _ev_active and fade.color.a > 0.001 and fade.color.a < 0.999 and _m6_log.has("black"):
			if not plates.is_empty():
				_m6_log["fading_prompt"] = int(_m6_log.get("fading_prompt", 0)) + 1
		if _ev_active and fade.color.a >= 0.999 and not _m6_log.has("black"):
			_m6_log["black"] = [f, t]
		if _m6_log.has("black") and not _m6_log.has("visible") and fade.color.a <= 0.001:
			_m6_log["visible"] = [f, t]
			_m6_log["hud_at_visible"] = events_ui.root.visible and events_ui.plate.is_visible_in_tree()
			var big = events_ui.get("big")
			_m6_log["big_at_visible"] = String(big.text) if big is Label else ""
			var junk := 0
			for c in events_ui.root.get_children():
				if c is Label and String((c as Label).text).find("0123456789") >= 0:
					junk += 1
			_m6_log["junk_at_visible"] = junk
			_m6_log["board_at_visible"] = events_ui.board.visible if events_ui.get("board") is Control else false
		if _m6_log.has("visible") and not _m6_log.has("dialog") and ui.dialog_open():
			_m6_log["dialog"] = [f, t]
		if is_instance_valid(ev_game) and ev_game.running and not _m6_log.has("running"):
			_m6_log["running"] = [f, t]
		if _m6_log.has("running") and not _m6_log.has("act") and acts:
			_m6_log["act"] = [f, t]

func _m6_evprompt() -> void:
	var args := _ev_args()
	var kind := String(args.get("evkind", "academia"))
	_ev_demo_state(20)
	Events.make_invite(kind)
	Game.ev_booked = Game.ev_invite
	Game.ev_invite = {}
	Game.ev_booked["day"] = Game.day
	Game.gold -= int(Game.ev_booked["fee"])
	phase = Phase.MORNING
	_update_top_buttons()
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	Glyphs.forced = ""
	await _r6_tap(KEY_K)   # (el teclado: los glifos son teclas)
	_m6_watch()
	_ev_run_day()
	# la línea del anfitrión: E la termina de escribir y la pasa (como un jugador)
	var w := 0.0
	while not (is_instance_valid(ev_game) and ev_game.running) and w < 120.0:
		if ui.dialog_open():
			await _r6_tap(KEY_E)
		await _r6_wait(0.25)
		w += 0.25
	_m6_check("evento corriendo", is_instance_valid(ev_game) and ev_game.running, [kind, w])
	_m6_check("ningún aviso con la escena tapada (mapa o negro)", int(_m6_log.get("covered_prompt", 0)) == 0 and int(_m6_log.get("fading_prompt", 0)) == 0,
		[_m6_log.get("covered_prompt", 0), _m6_log.get("fading_prompt", 0)])
	_m6_check("HUD completo en el primer cuadro a la vista", bool(_m6_log.get("hud_at_visible", false)), _m6_log.get("visible", []))
	_m6_check("sin restos del precalentamiento", int(_m6_log.get("junk_at_visible", 1)) == 0 and String(_m6_log.get("big_at_visible", "x")).find("Go! Time!") < 0
		and not bool(_m6_log.get("board_at_visible", true)), [_m6_log.get("junk_at_visible"), _m6_log.get("big_at_visible"), _m6_log.get("board_at_visible")])
	var vis: Array = _m6_log.get("visible", [0, 0.0])
	var dl: Array = _m6_log.get("dialog", [0, 99.0])
	_m6_check("la línea del anfitrión sale al verse la escena", float(dl[1]) - float(vis[1]) < 0.3, [vis, dl])
	# go: el banco se abre solo; Esc lo cierra; el botón «Cauldron» con su tecla; E lo vuelve a abrir
	w = 0.0
	while not _brew_open() and w < 10.0:
		await _r6_wait(0.1)
		w += 0.1
	var act: Array = _m6_log.get("act", [0, 99.0])
	var run: Array = _m6_log.get("running", [0, 0.0])
	_m6_check("banco abierto al empezar", _brew_open(), [run, act])
	await _r6_tap(KEY_ESCAPE)
	await _r6_wait(0.4)
	if _brew_open():
		brew.close_now()
		await _r6_wait(0.3)
		_m6_check("Esc cierra el banco", false, "")
	var bb: Control = events_ui.bench_btn
	_m6_check("botón Cauldron a la vista con su tecla", bb.is_visible_in_tree() and bb is HudButton and String((bb as Button).text) == "Cauldron"
		and prompt_brain.has_action("interact"), [bb.is_visible_in_tree(), (bb as Button).text])
	await _r6_tap(KEY_E)
	await _r6_wait(0.5)
	_m6_check("E abre el banco", _brew_open(), "")
	if kind == "concurso":
		# una poción en el estante con el banco cerrado: «Space  Present» sobre el estante; Espacio abre el estante
		# («Present»); E la presenta (el jurado)
		brew.close_now()
		await _r6_wait(0.3)
		Game.potions = [{"id": "sueno_profundo", "potency": 7}]
		Game.potions_changed.emit()
		await _r6_wait(0.4)
		var plates: Array = ui.prompts.visible_prompts()
		var shelf := plates.filter(func(p): return String(p["id"]) == "shelf")
		_m6_check("concurso: aviso Present sobre el estante", _r6_prompt("shelf") == "Present" and shelf.size() == 1, [_r6_prompt("shelf"), plates.map(func(p): return p["text"])])
		await _r6_tap(KEY_SPACE)
		await _r6_wait(0.2)
		_m6_check("Espacio abre el estante (Present)", ui.picker_open() and ui.picker_verb() == "Present", [ui.picker_open(), ui.picker_verb()])
		await _r6_tap(KEY_E)
		w = 0.0
		while not events_ui.modal_open() and w < 10.0:
			await _r6_wait(0.2)
			w += 0.2
		_m6_check("E la presenta (el jurado)", events_ui.modal_open() and not ui.picker_open(), [events_ui.modal_kind() if events_ui.has_method("modal_kind") else "", w])
	_m6_log["stop"] = true
	act = _m6_log.get("act", [0, 99.0])
	print("M6TEST tiempos (s de juego) negro=", _m6_log.get("black"), " vista=", vis, " anfitrión=", dl, " corriendo=", run, " aviso E=", act)
	print("M6TEST ", "OK" if _m6_bad == 0 else "FALLO (%d)" % _m6_bad)
# --- end R6 MERGE
