extends Node
## Flujo del juego: título, mañana (mercado), clientes, caldero, entregas y cierre del día.

enum Phase { TITLE, INTRO, MORNING, OPEN, CLOSING }

# --- STORY: el mundo es más grande (elfos, enanos, gente bestia, caballeros, magos...) y las pociones hacen efecto después
# --- R3 MERGE: dieta de texto (una o dos frases cortas por línea)
const INTRO_LINES := [
	["", "Al pie de la Montaña Gris hay una tiendita de pociones con la chimenea siempre encendida."],
	["", "Tu maestra te la dejó al partir: su recetario, su grimorio, un caldero y Miga, una gata dormilona."],
	["", "Por aquí pasa gente de todo el reino: elfos, enanos, caballeros, magos… Siempre necesitan algo."],
	["", "Las pociones hacen efecto después: tus clientes te contarán cómo les fue."],
]
# --- end STORY

const THANKS := [
	["¡Gracias! Es justo lo que necesitaba.", "¡Muchas gracias, vecina!", "Te debo una. ¡Hasta pronto!"],
	["¡Qué buena pinta tiene! Gracias de verdad.", "Huele de maravilla. ¡Gracias!", "¡Se nota que le pusiste cariño!"],
	["¡Esto es obra de una maestra! Les hablaré a todos de tu tienda.", "¡Brilla tanto que da pena tomársela! Gracias.", "¡Increíble! Volveré seguro."],
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

# pruebas automáticas / capturas
var _shot_path := ""
var _shot_frames := 0
var _frame := 0
var _demo := ""
var _autoplay_days := 0

func _ready() -> void:
	get_viewport().physics_object_picking = true
	world = ShopWorld.new()
	add_child(world)
	world.build()
	# --- WORLD: la alquimista camina (walker.gd) y las estaciones solo funcionan cuando llega
	world.walker.can_walk = _can_walk
	world.can_use = _can_use_station
	world.station_clicked.connect(_on_station_clicked)
	market = MarketWorld.new()
	add_child(market)
	market.build()
	market.walker.can_walk = _can_walk
	market.can_use = func(_id): return _can_walk()
	market.station_clicked.connect(_on_market_station)
	_set_place_on(market, false)
	# --- end WORLD

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

	ui = GameUI.new()
	add_child(ui)
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

	world.jar_clicked.connect(_on_jar_clicked)
	world.jar_hover.connect(func(id):
		if not ov.is_open():
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
	# --- R3 MAGIC3: el libro de runas del escritorio (encanta pociones del estante) y la tinta del caldero
	grimoire = GrimoireUI.new()
	grimoire.setup(self)
	add_child(grimoire)
	ui.magic_setup()
	ui.ink_pressed.connect(_on_brew_ink)
	# --- end R3 MAGIC3

	Sfx.start_ambience()
	_parse_args()
	if _demo != "":
		_run_demo()
	else:
		await _warm_places()   # --- PREP: la biblioteca y el mercado se dibujan una vez, en negro, antes del título
		_show_title()
		_fade_to(0.0, 0.5)     # --- PREP

func _build_open_button() -> void:
	open_btn = UIKit.button("Abrir", func(): _open_shop(), 28)   # --- R3 BENCH: una palabra
	open_btn.custom_minimum_size = Vector2(340, 64)
	open_btn.visible = false
	# --- WORLD: debajo, "Ir al mercado" (o "Volver a la tienda" en el mercado)
	trip_btn = UIKit.button("Mercado", func(): _on_trip_button(), 23)   # --- R3 BENCH
	trip_btn.custom_minimum_size = Vector2(280, 50)
	trip_btn.visible = false
	top_box = UIKit.vbox(10)
	UIKit.place(top_box, Vector2(0.5, 0), Vector2(-170, 24), Vector2(340, 0), Control.GROW_DIRECTION_BOTH)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in [open_btn, trip_btn]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		top_box.add_child(b)
	ui.root.add_child(top_box)
	# --- end WORLD

# ------------------------------------------------------------------ título y comienzo

func _show_title() -> void:
	phase = Phase.TITLE
	if brew:
		brew.close_now()   # --- R3 BENCH
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
	_refresh_all()
	ui.set_gameplay_visible(true)
	ui.set_time_label("Mañana")
	world.set_time(0.0, true)
	world.cat.play("sleep")
	# --- WORLD: empieza el día detrás del mostrador; la puerta lleva al mercado por la mañana
	if in_market:
		_switch_place(false)
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.snap_camera()
	world.set_station_label("puerta", "Puerta · ir al mercado")
	_jar_queue.clear()
	_jar_trip = false   # --- INTEGRATE
	# --- end WORLD
	Game.save_game()
	# --- R3 MAGIC3: una partida vieja tenía pergaminos o papel: Tobías los compró (el oro ya está en la bolsa)
	if Game.legacy_refund > 0:
		ui.toast("Tus pergaminos viejos: +%d oro" % Game.legacy_refund, UIKit.GOLD_BRIGHT, 4.0)   # --- R3 MERGE: corto
		Game.legacy_refund = 0
	# --- end R3 MAGIC3
	ui.show_banner("Día %d" % Game.day, "Mañana")
	var got := Game.morning_harvest()
	if got.size() > 0:
		ui.toast("Huerto: +2 raíces, +2 lágrimas", UIKit.GOOD, 3.0)   # --- R3 BENCH: aviso corto
	_update_top_buttons()   # --- WORLD
	await get_tree().create_timer(1.6).timeout
	if phase != Phase.MORNING:
		return
	# --- STORY: el correo de la mañana (noticias de clientes de días anteriores), antes de los consejos
	await _morning_mail()
	if phase != Phase.MORNING:
		return
	# --- end STORY
	# --- WORLD: ya no se abre el panel del mercado: el mercado es un lugar (se va por la puerta)
	# --- R3 BENCH: consejos de una línea (cada uno sale una vez: día 1 y día 2)
	if Game.day == 1 and not Game.tutorial_done:
		ui.show_tip("Camina con [b]A/D[/b] o con un clic. Luego, [b]Abrir[/b].", 14.0)
	elif Game.day == 2 and not in_market:
		ui.show_tip("Cada mañana: compras en el [b]mercado[/b] (la puerta).", 12.0)
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
	ui.show_tip("El grimorio de tu maestra brilla en la [b]biblioteca[/b].", 12.0)

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
	world.set_station_label("puerta", "Puerta")
	# --- end WORLD
	queue = Game.plan_day()
	total_today = maxi(1, queue.size())
	served = 0
	world.set_time(0.12, true)
	ui.set_time_label("Mediodía")
	ui.toast("¡Abierto! %d clientes hoy" % queue.size(), UIKit.GOLD_BRIGHT)   # --- R3 BENCH
	await get_tree().create_timer(1.4).timeout
	_next_customer()

# ------------------------------------------------------------------ clientes

func _char_name(who: String) -> String:
	return Story.char_name(who)   # --- STORY

func _next_customer() -> void:
	if phase != Phase.OPEN:
		return
	if queue.is_empty():
		_close_day()
		return
	current = queue.pop_front()
	misses = 0
	hint_given = current.get("tutorial", false)
	customer_ready = false
	customer = Actor.new()
	world.add_child(customer)
	customer.setup(Story.sprite_id(current["who"]), Data.CHARACTERS.get(current["who"], {}).get("pixel", 0.04))   # --- STORY
	customer.global_position = ShopWorld.P_OUTSIDE
	world.open_door()
	await get_tree().create_timer(0.35).timeout
	await customer.walk_to(ShopWorld.P_DOOR_IN)
	world.close_door()
	await customer.walk_to(ShopWorld.P_DOOR_FRONT)
	await customer.walk_to(ShopWorld.P_CUSTOMER)
	if not is_instance_valid(customer):
		return
	customer.face(-1)
	customer.emote("note" if current.get("kind", "") == "return" else "excl", 1.2)   # --- STORY: quien vuelve trae noticias
	# --- INTEGRATE: si iba al estante por un frasco tocado de lejos, primero lo echa al caldero (antes se perdía)
	await _finish_jar_trip()
	if not is_instance_valid(customer):
		return
	# --- end INTEGRATE
	# --- WORLD: si está libre, la alquimista va al mostrador a atender
	if not busy and not ov.is_open() and not ui.dialog_open() and not world.at_station("mostrador") and not _brew_open():   # --- R3 BENCH
		var reached: bool = await world.go_station("mostrador")
		# --- INTEGRATE: tocó un frasco de camino: lo echa y vuelve al mostrador
		if not reached and _jar_trip:
			await _finish_jar_trip()
			if is_instance_valid(customer) and not busy and not ov.is_open() and not ui.dialog_open():
				await world.go_station("mostrador")
		# --- end INTEGRATE
		if not is_instance_valid(customer):
			return
	if world.at_station("mostrador") and not busy:
		world.alchemist.face(1)
	# --- end WORLD
	await get_tree().create_timer(0.5).timeout
	customer_ready = true
	# --- STORY: quien vuelve a contar cómo le fue
	if current.get("kind", "") == "return":
		_talk_return()
	else:
		_talk_request()
	# --- end STORY

func _talk_request() -> void:
	var who := _char_name(current["who"])
	var choices := []
	if current.get("tutorial", false):
		choices = [["prepare", "¡Enseguida!"]]
	else:
		choices = [["prepare", "Preparar"]]
		if not hint_given:
			choices.append(["hint", "¿Una pista?"])   # --- R3 MERGE: botones de dos palabras
		choices.append(["decline", "No puedo"])
	var text: String = current["text"]
	# --- STORY: quien vuelve con otro pedido, el aventurero que lo intenta de nuevo, y la presentación de cada cara nueva
	if not current.has("_prefix"):
		current["_prefix"] = ""
		if current.get("followup", false):
			current["_prefix"] = Story.pick(Data.RETURN_VISITS["follow"]) + " "
		elif current.get("retry", false):
			current["_prefix"] = Story.pick(Data.RETURN_VISITS["retry"]) + " "
	text = current["_prefix"] + text
	if not Game.met.has(current["who"]):
		Game.met[current["who"]] = true
		text = "[color=#c9bfd9][i](%s, %s)[/i][/color]\n%s" % [who, Story.char_title(current["who"]), text]
	# --- end STORY
	# --- R3 MAGIC3: aquí estaba ui.show_rack_tab(...) (PREP): ya no hay pestaña de pergaminos en el estante
	ui.say(who, text, choices)

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
			ui.order_who = String(current.get("who", ""))   # --- R3 MERGE: el retrato del ticket por su id (viajeros incluidos)
			ui.show_order(who, current["text"], current["hint"] if hint_given else "", Game.order_runes(current))   # --- R3 MAGIC3: las runas del pedido
			if current.get("tutorial", false) and tutorial_step < 0:
				tutorial_step = 0
				# --- R3 BENCH: una línea; en el banco brillan los dos frascos
				ui.show_tip("Al [b]caldero[/b]: raíz de mandrágora + hongo violeta.", 0.0)
				brew.guide(["raiz_mandragora", "hongo_violeta"])
		"hint":
			hint_given = true
			ui.say(who, current["hint"], [["prepare", "Entendido"], ["decline", "No puedo"]])   # --- R3 MERGE
		"decline":
			ui.say(who, Data.DECLINE_LINES.pick_random())
			await ui.dialog_advanced
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
	var lbl := "Mediodía"
	if t >= 0.88:
		lbl = "Noche"
	elif t >= 0.68:
		lbl = "Atardecer"
	elif t >= 0.45:
		lbl = "Tarde"
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
	ui.hide_order()
	ui.hide_dialog()

# ------------------------------------------------------------------ caldero

func _can_interact(allow_dialog := false) -> bool:
	if phase != Phase.MORNING and phase != Phase.OPEN:
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
			ui.toast("Primero responde a tu cliente.")
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

func _on_brew_closed() -> void:
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
		ui.show_tip("Las 2 esencias más fuertes deciden. Ahora, [b]Remover[/b].", 0.0)
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
		_bench_say("Falta otra esencia")
		return
	if Game.potions_full():
		_bench_say("Estante lleno")
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
		ui.toast("Suerte de Miga: +1", UIKit.GOLD_BRIGHT)
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
			ui.show_tip("¡Cuajó! Ahora, [b]Embotellar[/b].", 0.0)
	else:
		await brew_bottle()

## «Embotellar»: la poción removida va al estante (vuela hasta su hueco del HUD si el banco está abierto).
func brew_bottle() -> void:
	if brew_ready.is_empty() or busy:
		return
	var pid: String = brew_ready["potion"]
	var potency: int = int(brew_ready["potency"])
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
		ui.show_banner("¡Nueva receta!", Data.POTIONS[pid]["name"])
		Sfx.play("sparkle", 0.0, -2.0)
	else:
		ui.toast("%s %s" % [Data.POTIONS[pid]["name"], "★".repeat(Game.stars_for(potency))])
	# --- STORY: la intuición de la alquimista (una corazonada, no una certeza)
	if customer_ready and is_instance_valid(customer) and current.get("kind", "") != "return" and Story.wanted_kind(current) == "potion":
		_intuition_brew(pid, idx)
	# --- end STORY
	busy = false
	if _brew_open():
		brew.refresh()
	elif customer_ready and not _needs_rune(idx):   # --- R3 MERGE: si al pedido le falta una runa, va al escritorio, no al mostrador
		await _go_counter()
	if tutorial_step == 1:
		tutorial_step = 2
		ui.show_tip("Tócala en el [b]estante[/b] para entregarla.", 0.0)
# --- end R3 BENCH

# ------------------------------------------------------------------ entregas

func _on_potion(i: int) -> void:
	# --- R3 BENCH: tocar una poción del estante con el banco abierto cierra el banco y la entrega
	if i < 0 or i >= Game.potions.size():
		return
	if _brew_open():
		if brew.is_busy() or not customer_ready:
			if not customer_ready:
				_bench_say("No hay cliente", UIKit.TEXT)
			return
		await brew.close()
	# --- end R3 BENCH
	if not _can_interact():
		return
	if not customer_ready or customer == null:
		ui.toast("No hay cliente")   # --- R3 BENCH
		return
	# --- R3 MAGIC3: (se quitó el bloque STORY que rechazaba pociones a quien pedía un pergamino)
	_deliver(i)

func _deliver(i: int) -> void:
	busy = true
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
	Game.stats["sold"] += 1
	Game.today["sold"] += 1
	Game.schedule_outcome(Story.make_outcome(current, item, ok, price, misses))
	Sfx.play("coin", 0.05, -4.0)
	ui.fly_coins(world.screen_pos(customer.global_position + Vector3(0, 1.4, 0)), clampi(price / 4, 3, 8))
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
	var note := "" if Game.day > 3 else "   [color=#a99fbf][i]Ya te contará cómo le fue.[/i][/color]"
	ui.hide_order()
	var bye := "¡Buen viaje!" if current.get("kind", "") == "hero" else "¡Que te vaya bien!"
	var paid := "+%d oro" % price
	if rune_extra > 0:
		paid += "  [color=#c9b6ff](runa +%d)[/color]" % rune_extra   # --- R3 MAGIC3
	ui.say(who, "%s\n[color=#ffd987]%s[/color]%s" % [Story.reaction(current, item, ok), paid, note], [["bye", bye]])
	busy = false
	if tutorial_step == 2:
		tutorial_step = 3
		Game.tutorial_done = true
		ui.show_tip("Mañana sabrás cómo le fue. ¿Difícil? Pide una [b]pista[/b].", 14.0)   # --- R3 BENCH
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
			_think("Ahora, la runa de %s…" % Story.rune_name(need[0]))
			# --- R3 MERGE: con el banco abierto la idea no se ve en la tienda (la tapa el banco): la dice el banco
			if _brew_open():
				brew.say("Ahora, la runa de %s" % Story.rune_name(need[0]), UIKit.GOLD_BRIGHT, 2.4)
			if Game.magic_stats["runes"] == 0:
				ui.show_tip("La runa, en el [b]grimorio[/b] de la biblioteca.")   # --- R3 MERGE: corto
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
			ui.toast("Nueva página en el Diario", UIKit.GOLD_BRIGHT, 3.0)   # --- R3 BENCH
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
	if letters.is_empty() and rumors.is_empty():
		return
	Game.save_game()
	var first := not Game.mail_seen and not letters.is_empty()
	if not letters.is_empty():
		Game.mail_seen = true
	ov.show_mail(letters, rumors, first)
	while ov.current == "mail":
		await get_tree().process_frame
	await _show_pending_levels()

## Para las pruebas automáticas: qué elección es cada botón de despedida o de visita.
func _bot_choice(label: String) -> String:
	if label in ["¡Buen viaje!", "¡Que te vaya bien!"] or label in Data.RETURN_VISITS["bye"]:
		return "bye"
	if label in Data.RETURN_VISITS["next"]:
		return "return_next"
	return "prepare"
# --- end STORY

# ------------------------------------------------------------------ fin del día

func _close_day() -> void:
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
	ui.toast("Tienda cerrada", UIKit.GOLD_BRIGHT)   # --- R3 BENCH
	world.set_time(1.0, true)
	ui.set_time_label("Noche")
	await _go_counter()
	world.cat.play("sit")
	await get_tree().create_timer(2.2).timeout
	await _show_pending_levels()
	Game.save_game()
	ov.show_summary(Game.day, Game.today)

func _sleep() -> void:
	await _fade_to(1.0, 0.8)
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
			ui.toast("Miga ronronea: +1 a la próxima poción", UIKit.GOLD_BRIGHT, 3.0)   # --- R3 BENCH
		else:
			ui.toast("Miga ronronea feliz", UIKit.TEXT, 2.4)   # --- R3 BENCH
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
			# --- WORLD: por la mañana el mercado es un lugar; durante el día, un encargo (Pip trae los ingredientes)
			if phase == Phase.MORNING:
				if in_market:
					ui.toast("Toca un puesto")   # --- R3 BENCH
				else:
					_go_market()
			else:
				ov.show_market("day")
			# --- end WORLD
		"settings":
			ov.show_settings()

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
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE and not ov.is_open() and phase != Phase.TITLE and phase != Phase.INTRO:
			ov.show_settings()
		elif ev.keycode == KEY_R and _can_interact(true):
			ov.show_book()
		elif ev.keycode == KEY_J and _can_interact(true):
			ov.show_journal()
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
	return not ov.is_open() and not busy and not ui.dialog_open() and not _brew_open()   # --- R3 BENCH

## Si se puede usar una estación de la tienda (ShopWorld la llama antes de caminar hasta ella).
func _can_use_station(id: String) -> bool:
	if in_market or _trip_busy or not _can_interact() or _brew_open():   # --- R3 BENCH
		return false
	if id == "puerta" and phase == Phase.OPEN:
		ui.toast("El mercado, mañana")   # --- R3 BENCH
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
				ui.toast("El mercado, mañana")   # --- R3 BENCH

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
	trip_btn.text = "Tienda" if in_market else "Mercado"   # --- R3 BENCH

## Muestra u oculta un escenario 3D (la tienda o el mercado) y lo pausa: sus clics, animaciones y sonidos.
func _set_place_on(place: Node3D, on: bool) -> void:
	place.visible = on
	place.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

## Cambia de escenario al instante (los fundidos los hacen _go_market y _leave_market).
func _switch_place(to_market: bool, intro := true) -> void:
	brew.close_now()   # --- R3 BENCH
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
	world.close_door()
	world.walker.frozen = false
	_switch_place(true)
	await get_tree().create_timer(0.15).timeout
	await _fade_to(0.0, 0.6)
	ui.show_banner("Plaza del mercado", "Mañana de mercado")
	if not _market_tip_shown:
		_market_tip_shown = true
		ui.show_tip("Toca un [b]puesto[/b] para comprar.", 10.0)   # --- R3 BENCH
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
## Al arrancar, con la pantalla en negro: la cámara de la tienda mira un momento la biblioteca y el mercado se dibuja
## en tres puntos de la calle. Así WebGL compila sus materiales y shaders antes de que el jugador vaya (sin esto, la
## primera salida al mercado se trababa más de un segundo en el navegador). Son unos pocos cuadros.
func _warm_places() -> void:
	fade.color.a = 1.0
	world.cam_fixed_x = ShopWorld.CAM_X0
	world.snap_camera()
	await _frames(2)
	# --- R3 WORLD3: también el lado de los clientes (el frente de paneles del mostrador solo se ve desde ahí)
	world.cam_fixed_x = ShopWorld.CAM_X1
	world.snap_camera()
	await _frames(2)
	# --- end R3 WORLD3
	world.cam_fixed_x = INF
	world.snap_camera()
	_set_place_on(world, false)
	_set_place_on(market, true)
	market.enter(false)
	for x in [MarketWorld.X0, MarketWorld.FOUNTAIN_POS.x, MarketWorld.X1]:
		market.walker.teleport(x, 1)
		market.snap_camera()
		await _frames(2)
	market.leave()
	_set_place_on(market, false)
	_set_place_on(world, true)
	world.camera.current = true
	world.snap_camera()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
# --- end PREP

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
		_bench_say("Faltan ingredientes")   # --- R3 MERGE: en el banco si está abierto, y corto
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
	print("MAGIC carta: «", body, "» menciona la runa=", body.contains("Prisa") or body.contains("runa"), " premio=", letters[0]["reward"] if not letters.is_empty() else "")
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

func _process(_d: float) -> void:
	_frame += 1
	ui.set_day_market(phase == Phase.OPEN)   # --- R3 MERGE: el «x2» del botón Mercado (de día el encargo cuesta el doble)
	if _shot_path != "" and _frame == max(_shot_frames, 20):
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("SHOT ", _shot_path)
		if _demo != "autoplay":
			get_tree().quit()

func _run_demo() -> void:
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
				ui.show_tip("Tócala en el [b]estante[/b] para entregarla.", 0.0)
		# --- end R3 BENCH
		# --- WORLD: el mercado es un lugar; "upgrades" abre el puesto de Mabel
		"market", "upgrades", "vendor":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Mañana")
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
			ui.set_time_label("Mañana")
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
			ui.set_time_label("Mañana")
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
			ui.set_time_label("Mañana")
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
			ui.set_time_label("Mañana")
			world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
			world.snap_camera()
			await get_tree().create_timer(0.6).timeout
			world.walker.go_to(ShopWorld.COUNTER_X + 0.12, 1)
		"doorside":
			phase = Phase.MORNING
			world.set_time(0.0, false)
			ui.set_time_label("Mañana")
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
			ui.set_time_label("Mañana")
			_switch_place(true, false)
			market.walker.teleport(MarketWorld.FOUNTAIN_POS.x - 0.6, 1)
			market.snap_camera()
			if name == "fountain_close":
				market.set("_cam_base", Vector3(0.0, 2.9, 5.4))
				market.set("_cam_target", Vector3(0.0, 1.0, -3.3))
				market.camera.attributes.dof_blur_far_enabled = false
				market.camera.attributes.dof_blur_near_enabled = false
		# --- end R3 WORLD3
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
	_refresh_all()
	var days := maxi(1, _autoplay_days)
	var errors := 0
	var rune_stats := {"orders": 0, "enchanted": 0, "missing": 0}   # --- R3 MAGIC3
	for d in days:
		_begin_day()
		await get_tree().create_timer(2.0).timeout
		if ov.is_open():
			ov.close(false)
		# compra algo de stock y alguna mejora
		for id in Game.unlocked_ingredients():
			while Game.stock.get(id, 0) < 4 and Game.gold > 30:
				Game.buy_ingredient(id, 1)
		for u in Data.UPGRADE_ORDER:
			if Game.gold > Data.UPGRADES[u]["cost"] + 40:
				Game.buy_upgrade(u)
		# --- R3 MAGIC3: desde el día 2 abre el grimorio (la runa de Prisa); compra tinta para sus runas y la página de Tobías
		if Game.day >= 2 and not Game.magic_unlocked:
			await _finish_overlays()
			if not await grimoire.bot_open():
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
		_open_shop()
		while phase == Phase.OPEN:
			await get_tree().create_timer(0.5).timeout
			if ov.is_open() and ov.current == "levelup":
				ov.close()
			if customer_ready and ui.dialog_open() and not busy:
				# responder: preparar
				if ui.dialog_choices.get_child_count() > 0:
					var first: Button = ui.dialog_choices.get_child(0)
					_on_choice(_bot_choice(first.text))   # --- STORY: despedidas y visitas
				else:
					ui._advance()
				continue
			if customer_ready and not ui.dialog_open() and not busy:
				var want: String = current["potion"]
				# --- R3 MAGIC3: la poción que mejor cumple el pedido (con las runas que pide, si ya las tiene)
				var have := _bot_pick_potion(want)
				if have >= 0:
					var r := Game.next_rune_for(Game.potions[have], current)
					if r != "" and Game.enchant_problem(have, r) == "":
						var res: Dictionary = await grimoire.bot_enchant(have, r)
						if res.is_empty():
							print("AUTOPLAY: no pudo encantar ", want, " con ", r, " (", grimoire.bot_fail, ")")
							errors += 1
						else:
							rune_stats["enchanted"] += 1
						continue   # vuelve a mirar: otra runa, o entregar
					if not Game.order_runes(current).is_empty():
						rune_stats["orders"] += 1
						if r != "":
							rune_stats["missing"] += 1
					# --- end R3 MAGIC3
					_on_potion(have)
					continue
				var combo := _find_combo(want)
				if combo.is_empty():
					print("AUTOPLAY: sin receta para ", want, " stock=", Game.stock)
					errors += 1
					_on_choice("decline")
					continue
				# --- R3 BENCH: por el banco del caldero (abre al llegar, echa, remueve, embotella y lo cierra)
				for id in combo:
					_on_jar_clicked(id)
					await get_tree().create_timer(0.3).timeout
				var wait := 0.0
				while (not _brew_open() or brew.is_busy() or contents.size() < combo.size()) and wait < 6.0:
					await get_tree().create_timer(0.2).timeout
					wait += 0.2
				_on_brew()
				await get_tree().create_timer(0.8).timeout
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
				# --- end R3 BENCH
		# fin del día
		while phase != Phase.MORNING:
			await get_tree().create_timer(0.5).timeout
			if ov.current == "summary":
				print("AUTOPLAY: fin día ", Game.day, " oro=", Game.gold, " renombre=", Game.renombre, " nivel=", Game.level(), " pociones=", Game.discovered.keys())
				ov.close(false)
				_sleep()
				await get_tree().create_timer(3.0).timeout
				break
			if ov.is_open() and ov.current == "levelup":
				ov.close()
	print("AUTOPLAY DONE errors=", errors, " day=", Game.day, " gold=", Game.gold, " level=", Game.level(), " journal=", Game.journal.size(), " pending=", Game.pending.size(), " met=", Game.met.size())   # --- STORY
	print("AUTOPLAY RUNAS pedidos=", rune_stats["orders"], " encantadas=", rune_stats["enchanted"], " sin_runa=", rune_stats["missing"], " runas=", Game.known_runes(), " tintas=", Game.items)   # --- R3 MAGIC3
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
	for i in 40:
		if not ov.is_open():
			return
		ov.close()
		await get_tree().create_timer(0.3).timeout
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
