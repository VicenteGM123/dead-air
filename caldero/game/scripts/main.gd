extends Node
## Flujo del juego: título, mañana (mercado), clientes, caldero, entregas y cierre del día.

enum Phase { TITLE, INTRO, MORNING, OPEN, CLOSING }

# --- STORY: el mundo es más grande (elfos, enanos, gente bestia, caballeros, magos...) y las pociones hacen efecto después
const INTRO_LINES := [
	["", "Al pie de la Montaña Gris hay un pueblo pequeño. Y en el pueblo, una tiendita de pociones con la chimenea siempre encendida."],
	["", "Tu maestra te la dejó al partir de viaje, junto con su libro de recetas, su viejo grimorio, un caldero y una gata dormilona llamada Miga."],
	["", "Por aquí pasa gente de todo el reino: elfos que recuerdan siglos, enanos de la montaña, gente bestia de las estepas, caballeros, magos errantes… Siempre necesitan algo, y no siempre saben explicarlo."],
	["", "Una poción no hace efecto en el mostrador: tus clientes se la llevan, y después te cuentan cómo les fue. Escúchalos con calma."],
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
	ui.brew_pressed.connect(_on_brew)
	ui.empty_pressed.connect(_on_empty)
	ui.slot_pressed.connect(_on_slot)
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
	# --- MAGIC: el grimorio, el estante de pergaminos (interfaz y pared de la tienda) y la tinta del caldero
	grimoire = GrimoireUI.new()
	grimoire.setup(self)
	add_child(grimoire)
	ui.magic_setup()
	world.build_scroll_rack()
	ui.scroll_pressed.connect(_on_scroll)
	ui.ink_pressed.connect(_on_brew_ink)
	grimoire.inscribed.connect(func(_s, _perfect): ui.show_rack_tab("scroll"))   # --- PREP: el pergamino nuevo, a la vista
	# --- end MAGIC

	Sfx.start_ambience()
	_parse_args()
	if _demo != "":
		_run_demo()
	else:
		await _warm_places()   # --- PREP: la biblioteca y el mercado se dibujan una vez, en negro, antes del título
		_show_title()
		_fade_to(0.0, 0.5)     # --- PREP

func _build_open_button() -> void:
	open_btn = UIKit.button("Abrir la tienda", func(): _open_shop(), 28)
	open_btn.custom_minimum_size = Vector2(340, 64)
	open_btn.visible = false
	# --- WORLD: debajo, "Ir al mercado" (o "Volver a la tienda" en el mercado)
	trip_btn = UIKit.button("Ir al mercado", func(): _on_trip_button(), 23)
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
	ui.show_banner("Día %d" % Game.day, "Mañana")
	var got := Game.morning_harvest()
	if got.size() > 0:
		ui.toast("Cosechaste 2 raíces de mandrágora y 2 lágrimas de sirena en el huerto.", UIKit.GOOD, 3.5)
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
	if Game.day == 1 and not Game.tutorial_done:
		ui.show_tip("Camina por la tienda con [b]A/D[/b], las flechas o la cruceta del mando, o haz clic en el suelo.\nCada mañana puedes salir al [b]Mercado[/b] por la puerta. Hoy ya tienes lo necesario: pulsa [b]Abrir la tienda[/b] cuando quieras.")
	elif Game.day == 2 and not in_market:
		ui.show_tip("Por la mañana, sal por la [b]puerta[/b] (o pulsa [b]Ir al mercado[/b]) y compra en los puestos del mercado. A la izquierda de la tienda está tu [b]biblioteca[/b].")
	# --- end WORLD
	# --- MAGIC: si aún no abrió el grimorio, se lo recuerda desde el día 3
	if Game.day >= 3 and not Game.magic_unlocked and not in_market and phase == Phase.MORNING:
		ui.show_tip("En la [b]biblioteca[/b], a la izquierda de la tienda, el grimorio de tu maestra brilla sobre el escritorio.\nCon papel y tinta también puedes escribir [b]pergaminos mágicos[/b].")
	# --- end MAGIC

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
	ui.toast("¡La tienda está abierta! Hoy vendrán %d clientes." % queue.size(), UIKit.GOLD_BRIGHT)
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
	if not busy and not ov.is_open() and not ui.dialog_open() and not world.at_station("mostrador"):
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
			choices.append(["hint", "Pedir una pista"])
		choices.append(["decline", "No puedo ayudarte"])
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
	ui.show_rack_tab(Story.wanted_kind(current))   # --- PREP: el estante enseña lo que pide (pociones o pergaminos)
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
			ui.show_order(who, current["text"], current["hint"] if hint_given else "")
			if current.get("tutorial", false) and tutorial_step < 0:
				tutorial_step = 0
				ui.show_tip("Greta necesita [b]Sueño Profundo[/b]: [color=#9eea9f]Vida[/color] + [color=#c9a8ff]Sombra[/color].\nToca en el estante la [b]Raíz de mandrágora[/b] (Vida 2, Sombra 1) y el [b]Hongo violeta[/b] (Sombra 2).")
		"hint":
			hint_given = true
			ui.say(who, current["hint"], [["prepare", "Entendido"], ["decline", "No puedo ayudarte"]])
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
	await world.go_station("mostrador")
# --- end WORLD

func _on_jar_clicked(id: String) -> void:
	if not _can_interact():
		if ui.dialog_open() and phase == Phase.OPEN:
			ui.toast("Primero responde a tu cliente.")
		return
	# --- WORLD: el estante está junto al caldero: si está lejos, primero camina hasta allí (los frascos que toque
	# mientras tanto se echan al llegar)
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

func _add_jar(id: String) -> void:
	# --- end WORLD
	if contents.size() >= Game.cauldron_slots():
		ui.toast("El caldero ya está lleno (%d ingredientes)." % Game.cauldron_slots(), UIKit.BAD)
		world.shake_jar(id)
		return
	if Game.stock.get(id, 0) <= 0:
		ui.toast("No te queda %s. Compra más en el Mercado." % Data.INGREDIENTS[id]["name"], UIKit.BAD)
		world.shake_jar(id)
		return
	Game.use_ingredient(id)
	contents.append(id)
	world.bump_jar(id)
	ui.hide_tooltip()
	_go_cauldron()
	var from: Vector3 = world.jars[id].global_position + Vector3(0, 0.4, 0.2)
	var to: Vector3 = ShopWorld.CAULDRON_POS + Vector3(0, 1.1, 0.0)
	ui.set_cauldron(contents)
	await world.fly(load("res://assets/icons/ing_%s.png" % id), from, to, 0.5, 0.9)
	Sfx.play("plop", 0.12, -2.0)
	var col := _mix_color(contents)
	world.cauldron.splash(col)
	world.cauldron.set_liquid(col)
	world.cauldron.set_activity(contents.size() / 3.0)
	if tutorial_step == 0 and contents.size() >= 2:
		tutorial_step = 1
		ui.show_tip("En el panel del [b]Caldero[/b] verás las esencias de la mezcla. Las dos más fuertes deciden la poción.\nCuando te guste, pulsa [b]Remover[/b].")

func _on_slot(i: int) -> void:
	if not _can_interact() or i >= contents.size():
		return
	var id: String = contents[i]
	contents.remove_at(i)
	Game.return_ingredient(id)
	ui.set_cauldron(contents)
	world.cauldron.set_liquid(_mix_color(contents))
	world.cauldron.set_activity(contents.size() / 3.0)
	Sfx.play("bubble_1", 0.1, -4.0)

func _on_empty() -> void:
	if not _can_interact() or contents.is_empty():
		return
	for id in contents:
		Game.return_ingredient(id)
	contents.clear()
	ui.set_cauldron(contents)
	world.cauldron.set_liquid(_mix_color(contents))
	world.cauldron.set_activity(0.0)
	ui.toast("Devolviste los ingredientes al estante.")

func _on_brew() -> void:
	if not _can_interact():
		return
	var r := Game.evaluate(contents)
	if r.get("potion", "") == "":
		ui.toast("Necesitas al menos dos esencias distintas.", UIKit.BAD)
		return
	if Game.potions_full():
		ui.toast("Tu estante de pociones está lleno.", UIKit.BAD)
		return
	busy = true
	ui.hide_tooltip()
	await _go_cauldron()
	ov.show_stir(1.0 + Game.level() * 0.15)
	var perfect: bool = await ov.stir_done
	var pid: String = r["potion"]
	var potency: int = int(r["potency"]) + Game.potency_bonus() + (1 if perfect else 0)
	if perfect:
		Game.stats["perfect"] += 1
	if Game.lucky:
		Game.lucky = false
		potency += 1
		ui.toast("La suerte de Miga: +1 de potencia.", UIKit.GOLD_BRIGHT)
	var col: Color = Data.POTIONS[pid]["color"]
	world.cauldron.brew_burst(col)
	Sfx.play("brew", 0.03, -2.0)
	world.alchemist.hop(1)
	var is_new := not Game.discovered.has(pid)
	contents.clear()
	ui.set_cauldron(contents)
	world.cauldron.set_liquid(Color("3b3156"))
	world.cauldron.set_activity(0.1)
	await get_tree().create_timer(0.35).timeout
	Game.add_potion(pid, potency)
	ui.show_rack_tab("potion")   # --- PREP: la poción nueva, a la vista en el estante
	var idx := Game.potion_index(pid, potency)
	world.rack_sprites[mini(idx, world.rack_sprites.size() - 1)].visible = false
	await world.fly(load("res://assets/icons/pot_%s.png" % pid), ShopWorld.CAULDRON_POS + Vector3(0, 1.3, 0.1), world.rack_slot_position(idx), 0.7, 1.0, 0.04)
	world.refresh_rack()
	if is_new:
		ui.show_banner("¡Nueva receta!", Data.POTIONS[pid]["name"])
		Sfx.play("sparkle", 0.0, -2.0)
	else:
		ui.toast("Preparaste %s (%d %s)." % [Data.POTIONS[pid]["name"], Game.stars_for(potency), "estrella" if Game.stars_for(potency) == 1 else "estrellas"])
	# --- STORY: la intuición de la alquimista (una corazonada, no una certeza)
	if customer_ready and is_instance_valid(customer) and current.get("kind", "") != "return" and Story.wanted_kind(current) == "potion":
		_intuition_brew(pid, idx)
	# --- end STORY
	if customer_ready:
		await _go_counter()
	busy = false
	if tutorial_step == 1:
		tutorial_step = 2
		# --- STORY
		ui.show_tip("¡Tu primera poción! ¿Viste cómo brilló, y cómo ronroneó Miga? Es tu intuición: crees que es lo que Greta necesita.\nEstá en tu estante (abajo a la derecha): tócala para entregársela.")
		# --- end STORY

# ------------------------------------------------------------------ entregas

func _on_potion(i: int) -> void:
	if not _can_interact():
		return
	if not customer_ready or customer == null:
		ui.toast("No hay ningún cliente esperando.")
		return
	# --- STORY: quien pide un pergamino no quiere una poción
	if Story.wanted_kind(current) == "scroll":
		ui.toast("%s necesita un pergamino, no una poción." % _char_name(current["who"]))
		ui.show_rack_tab("scroll")   # --- PREP
		return
	# --- end STORY
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
	_hand_over({"kind": "potion", "id": p["id"], "potency": p["potency"]})   # --- STORY

# --- STORY: la entrega ya no decide en el acto si funcionó: el cliente se lleva la poción y lo cuenta después
# (_hand_over). _deliver (pociones) y _deliver_scroll (MAGIC) siguen llamando a _success / _wrong:
# - una poción, correcta o no, se la lleva igual (no puede saber aún si sirve);
# - un pergamino tiene etiqueta con el nombre del hechizo: si no es el que pidió, lo nota en el acto y lo devuelve.
func _success(p: Dictionary) -> void:
	_hand_over(_item_of(p))

func _wrong(p: Dictionary) -> void:
	if String(p.get("kind", "potion")) == "scroll":
		_scroll_rejected(p)
	else:
		_hand_over(_item_of(p))

func _item_of(p: Dictionary) -> Dictionary:
	return {"kind": String(p.get("kind", "potion")), "id": String(p["id"]), "potency": int(p.get("potency", 5))}

## Un pergamino equivocado (o un pergamino a quien pidió una poción): lo lee, lo devuelve y ella puede probar otro.
func _scroll_rejected(p: Dictionary) -> void:
	var who := _char_name(current["who"])
	Game.return_potion(p)   # MAGIC: return_potion() devuelve los pergaminos a su estante
	world.refresh_rack()
	misses += 1
	customer.emote("sweat", 1.6)
	customer.shake()
	Sfx.play("sad", 0.0, -4.0)
	var line := ""
	if Game.has_method("scroll_wrong_line"):
		line = String(Game.call("scroll_wrong_line", p, current))
	if line == "":
		line = Data.WRONG_LINES.pick_random()
	if misses >= 2 and not hint_given:
		hint_given = true
		line += "\n[i]%s[/i]" % current["hint"]
	busy = false
	ui.say(who, line, [["retry", "Probaré otra cosa"], ["decline", "No puedo ayudarte"]])
# --- end STORY

# --- STORY: entregas, intuición, visitas y el correo de la mañana ------------------------------------------------

var _thought: Label3D   # lo que piensa la alquimista (sobre su cabeza)

## El cliente recibe lo que pidió (una poción o un pergamino). Solo puede juzgar lo que ve, huele y lee en la
## etiqueta: lo paga y se lo lleva. Si funcionó o no se sabrá después, por carta o cuando vuelva (Story.make_outcome);
## con esa noticia llegan la propina y el renombre. item: {"kind": "potion" o "scroll", "id", "potency"}.
func _hand_over(item: Dictionary) -> void:
	var who := _char_name(current["who"])
	var ok := String(item["id"]) == Story.wanted(current)
	var price := Story.price_of(item)
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
			col = Data.POTIONS[item["id"]]["color"]
		elif Story.spells().has(item["id"]):
			col = Story.spells()[item["id"]].get("color", col)
		world.spawn_sparkles(customer.global_position + Vector3(0, 1.05, 0.2), Color(col.r * 1.6, col.g * 1.6, col.b * 1.6), 14)
		_purr()
		_think(Story.pick(Data.INTUITION["give_match"]))
	else:
		customer.emote("question", 1.8)   # lee la etiqueta: no es lo que imaginaba (pero confía en ella)
	var note := "" if Game.day > 3 else "   [color=#a99fbf][i]Ya te contará cómo le fue.[/i][/color]"
	ui.hide_order()
	var bye := "¡Buen viaje!" if current.get("kind", "") == "hero" else "¡Que te vaya bien!"
	ui.say(who, "%s\n[color=#ffd987]+%d oro[/color]%s" % [Story.reaction(current, item, ok), price, note], [["bye", bye]])
	busy = false
	if tutorial_step == 2:
		tutorial_step = 3
		Game.tutorial_done = true
		ui.show_tip("Greta pagó la poción y se la tomará esta noche. Cómo le fue lo sabrás después: por [b]carta[/b] a la mañana siguiente o cuando vuelva a la tienda. Con las buenas noticias llegan la [b]propina[/b] y el [b]renombre[/b]; una poción equivocada trae una queja.\nSi un pedido es difícil, ¡pide una pista!")
		get_tree().create_timer(16.0).timeout.connect(func():
			if tutorial_step == 3:
				ui.hide_tip())

## MAGIC: la intuición al terminar un pergamino con un cliente esperando (como al terminar una poción).
func intuition_after_craft(kind: String, id: String) -> void:
	if customer_ready and is_instance_valid(customer) and current.get("kind", "") != "return" and Story.wanted_kind(current) == kind:
		var cname := _char_name(current["who"])
		if id == Story.wanted(current):
			_purr()
			_think(Story.pick(Data.INTUITION["brew_match"]).replace("{n}", cname))
		else:
			_think(Story.pick(Data.INTUITION["brew_unsure"]).replace("{n}", cname), false)

## Al terminar una poción con un cliente esperando: si es lo que pidió, brilla en el estante, Miga ronronea y ella lo
## piensa en voz baja. Si no, una duda. Es una corazonada, no una certeza: la respuesta llega con las noticias.
func _intuition_brew(pid: String, idx: int) -> void:
	var cname := _char_name(current["who"])
	if pid == Story.wanted(current):
		_purr()
		_glow_rack(idx)
		_think(Story.pick(Data.INTUITION["brew_match"]).replace("{n}", cname))
	else:
		_think(Story.pick(Data.INTUITION["brew_unsure"]).replace("{n}", cname), false)

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
			ui.toast("Nueva página en el Diario de viajeros.", UIKit.GOLD_BRIGHT, 3.0)
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
	phase = Phase.CLOSING
	ui.hide_order()
	ui.toast("Cerraste la tienda por hoy.", UIKit.GOLD_BRIGHT)
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
			ui.toast("Miga ronronea en su cojín: tu próxima poción tendrá +1 de potencia.", UIKit.GOLD_BRIGHT, 3.2)
		else:
			ui.toast("Miga ronronea feliz. (Dicen que con un cojín da buena suerte…)", UIKit.TEXT, 3.2)
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
					ui.toast("Ya estás en el mercado: toca un puesto para comprar.")
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
	return not ov.is_open() and not busy and not ui.dialog_open()

## Si se puede usar una estación de la tienda (ShopWorld la llama antes de caminar hasta ella).
func _can_use_station(id: String) -> bool:
	if in_market or _trip_busy or not _can_interact():
		return false
	if id == "puerta" and phase == Phase.OPEN:
		ui.toast("La tienda está abierta: el mercado tendrá que esperar a mañana.")
		return false
	return true

## La alquimista llegó a una estación que el jugador tocó (o con E).
func _on_station_clicked(id: String) -> void:
	match id:
		"biblioteca":
			_open_grimoire()
		"caldero":
			if _can_interact() and contents.size() >= 2:
				_on_brew()
		"mostrador":
			_on_customer_clicked()
		"puerta":
			if phase == Phase.MORNING:
				_go_market()
			elif phase == Phase.OPEN:
				ui.toast("La tienda está abierta: el mercado tendrá que esperar a mañana.")

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
	trip_btn.text = "Volver a la tienda" if in_market else "Ir al mercado"

## Muestra u oculta un escenario 3D (la tienda o el mercado) y lo pausa: sus clics, animaciones y sonidos.
func _set_place_on(place: Node3D, on: bool) -> void:
	place.visible = on
	place.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

## Cambia de escenario al instante (los fundidos los hacen _go_market y _leave_market).
func _switch_place(to_market: bool, intro := true) -> void:
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
		ui.show_tip("Camina por la calle y toca un [b]puesto[/b] para comprar. Para volver, entra por la puerta de tu tienda o pulsa [b]Volver a la tienda[/b].")
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

# --- MAGIC: entregar pergaminos, preparar tinta y las capturas de la magia ---------------------------------------

## Tocó un pergamino del estante de pergaminos: se entrega como una poción.
func _on_scroll(i: int) -> void:
	if not _can_interact():
		return
	if not customer_ready or customer == null:
		ui.toast("No hay ningún cliente esperando.")
		return
	_deliver_scroll(i)

## Como _deliver() con una poción: del estante al mostrador y al cliente; luego _success() o _wrong(), que reciben
## {"id", "potency", "kind": "scroll"} (ver Game.take_scroll_for_delivery). Si no era lo que pidió, vuelve al estante.
func _deliver_scroll(i: int) -> void:
	busy = true
	ui.hide_tooltip()
	var from := world.scroll_slot_position(i)
	var s := Game.take_scroll_for_delivery(i)
	if s.is_empty():
		busy = false
		return
	await _go_counter()
	var tex: Texture2D = load("res://assets/icons/spell_%s.png" % s["id"])
	await world.fly(tex, from, world.counter_potion.global_position + Vector3(0, 0.25, 0), 0.5, 0.6, 0.04)
	world.counter_potion.texture = tex
	world.counter_potion.visible = true
	Sfx.play("page", 0.05, -6.0)
	await get_tree().create_timer(0.45).timeout
	world.counter_potion.visible = false
	if not is_instance_valid(customer):
		Game.return_scroll(s)
		busy = false
		return
	await world.fly(tex, world.counter_potion.global_position + Vector3(0, 0.25, 0), customer.global_position + Vector3(0, 1.0, 0.1), 0.35, 0.3, 0.04)
	if s["id"] == current.get("scroll", ""):
		_success(s)
	else:
		_wrong(s)

## «Tinta» en el panel del caldero: la mezcla se vuelve tinta de su esencia más fuerte (Game.ink_for_mix). Se remueve
## como una poción: removido perfecto = un frasco más.
func _on_brew_ink() -> void:
	if not _can_interact():
		return
	var r := Game.ink_for_mix(contents)
	if r.is_empty():
		ui.toast("Para hacer tinta, echa al menos dos ingredientes al caldero.", UIKit.BAD)
		return
	busy = true
	ui.hide_tooltip()
	await _go_cauldron()
	ov.show_stir(1.0 + Game.level() * 0.15)
	var perfect: bool = await ov.stir_done
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
	await world.fly(load("res://assets/icons/%s.png" % ink), ShopWorld.CAULDRON_POS + Vector3(0, 1.3, 0.1), world.scroll_slot_position(1), 0.7, 1.0, 0.04)
	Game.add_item(ink, qty)
	Game.magic_stats["inks"] += qty
	ui.toast("Preparaste %s ×%d%s" % [Data.INKS[ink]["name"], qty, " (¡removido perfecto: +1!)" if perfect else "."], UIKit.GOLD_BRIGHT, 3.0)
	if customer_ready:
		await _go_counter()
	busy = false

## Capturas: --demo=grimoire (el grimorio abierto), --demo=rune (la runa a medio trazar), --demo=scrolls (el estante y
## un cliente que pide un pergamino). --demo=magictest: prueba rápida (inscribir, tinta, entregar, guardar) y sale.
func _magic_demo(name: String) -> void:
	Game.renombre = 34
	Game.hero_progress["lirien"] = 1
	Game.unlock_magic()
	Game.items = {"papel": 6, "vitela": 2, "tinta_brasa": 2, "tinta_escarcha": 1, "tinta_savia": 3, "tinta_umbra": 2, "tinta_alba": 2}
	Game.scrolls = []
	Game.add_scroll("sello_calor", 5)
	Game.add_scroll("hechizo_brotes", 3)
	Game.add_scroll("runa_calma", 7)
	Game.mark_page_read("sello_calor")
	Game.mark_page_read("hechizo_brotes")
	Game.magic_changed.emit()
	ui.refresh_hud()
	phase = Phase.MORNING
	ui.set_time_label("Mañana")
	world.set_time(0.0, false)
	match name:
		"grimoire", "rune":
			world.walker.teleport(float(ShopWorld.STATIONS["biblioteca"]["x"]), -1)
			world.snap_camera()
			await get_tree().create_timer(0.3).timeout
			if name == "grimoire":
				grimoire.show_book("pergamino_luz")
			else:
				grimoire.demo_auto = 0.58
				grimoire._inscribe("pergamino_luz")
		"scrolls":
			phase = Phase.OPEN
			world.set_time(0.3, false)
			current = Data.SCROLL_REQUESTS[0].duplicate()
			current["kind"] = "villager"
			customer = Actor.new()
			world.add_child(customer)
			customer.setup(current["who"])
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			hint_given = true
			ui.show_order(Data.CHARACTERS[current["who"]]["name"], current["text"], current["hint"])
			ui.show_rack_tab(Story.wanted_kind(current))   # --- PREP: pide un pergamino: el estante enseña los pergaminos
		"magictest":
			_magic_test()

func _magic_test() -> void:
	Engine.time_scale = 4.0
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	var s1 := Game.inscribe("sello_calor", "papel", true)
	print("MAGIC inscribe ", s1, " papel=", Game.item_count("papel"), " brasa=", Game.item_count("tinta_brasa"), " estante=", Game.scrolls.size())
	print("MAGIC sin tinta: ", Game.inscribe_problem("runa_escarcha", "vitela"))
	print("MAGIC pedidos: ", Game.scroll_requests(3).map(func(r): return [r["who"], r["scroll"]]))
	var g_buy := Game.gold
	print("MAGIC Tobías vende ", Overlays.vendor_items("tobias").map(func(it): return it["id"]), " compra=", Game.buy_item("vitela", 1), " oro -", g_buy - Game.gold)
	# tinta en el caldero: 2 raíces = Vida 4 -> 2 frascos de savia (+1 si se remueve perfecto)
	contents = ["raiz_mandragora", "raiz_mandragora"]
	print("MAGIC tinta posible ", Game.ink_for_mix(contents))
	var savia0 := Game.item_count("tinta_savia")
	_on_brew_ink()
	await get_tree().create_timer(2.0).timeout
	if ov.current == "stir":
		ov.stir_key()
	while busy:
		await get_tree().create_timer(0.2).timeout
	print("MAGIC tinta savia ", savia0, " -> ", Game.item_count("tinta_savia"), " caldero=", contents)
	# entregar: primero uno equivocado (vuelve al estante), luego el correcto
	phase = Phase.OPEN
	current = Data.SCROLL_REQUESTS[0].duplicate()
	current["kind"] = "villager"
	customer = Actor.new()
	world.add_child(customer)
	customer.setup(current["who"])
	customer.global_position = ShopWorld.P_CUSTOMER
	customer.face(-1)
	customer_ready = true
	var g0 := Game.gold
	_on_scroll(Game.scroll_index("hechizo_brotes", 3))
	while busy:
		await get_tree().create_timer(0.2).timeout
	print("MAGIC equivocado: estante=", Game.scrolls.size(), " misses=", misses, " dice=", ui.dialog_text.text)
	ui.hide_dialog()
	_on_scroll(Game.scroll_index("sello_calor", 5))
	while busy:
		await get_tree().create_timer(0.2).timeout
	print("MAGIC correcto: oro +", Game.gold - g0, " estante=", Game.scrolls.size(), " dice=", ui.dialog_text.text)
	# guardar y cargar
	var before := Game.magic_save()
	Game.save_game()
	Game.load_game()
	print("MAGIC guardado ok=", JSON.stringify(before) == JSON.stringify(Game.magic_save()), " unlocked=", Game.magic_unlocked)
	Game.delete_save()
	get_tree().quit()
# --- end MAGIC

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
		"brew":
			current = {"kind": "villager", "who": "granjero", "potion": "vigor_verde", "text": Data.VILLAGER_REQUESTS[5]["text"], "hint": Data.VILLAGER_REQUESTS[5]["hint"]}
			customer = Actor.new()
			world.add_child(customer)
			customer.setup("granjero")
			customer.global_position = ShopWorld.P_CUSTOMER
			customer.face(-1)
			customer_ready = true
			hint_given = true
			ui.show_order("Tomás", current["text"], current["hint"])
			contents = ["raiz_mandragora", "ambar_abeja"]
			ui.set_cauldron(contents)
			world.cauldron.set_liquid(_mix_color(contents), false)
			world.walker.teleport(ShopWorld.P_ALCH_CAULDRON.x, -1)   # --- WORLD
			world.snap_camera()
			ui.show_ingredient_tooltip("hongo_violeta")
		"stir":
			contents = ["hongo_violeta", "hongo_violeta"]
			world.walker.teleport(ShopWorld.P_ALCH_CAULDRON.x, -1)   # --- WORLD
			world.snap_camera()
			ov.show_stir(1.0)
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
		# --- MAGIC: capturas del grimorio, de la runa y del estante de pergaminos
		"grimoire", "rune", "scrolls", "magictest":
			_magic_demo(name)
		# --- end MAGIC
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
		# el grimorio ya está abierto (estante de pergaminos en el HUD) y ella cruza la tienda hasta el mostrador
		"walk":
			Game.renombre = 34
			Game.unlock_magic()
			Game.scrolls = []
			Game.add_scroll("sello_calor", 5)
			Game.add_scroll("runa_calma", 7)
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
			ui.show_order(Story.char_name("nyra"), current["text"], current["hint"])
			ui.show_rack_tab(Story.wanted_kind(current))   # --- PREP
			world.walker.teleport(-7.4, 1)
			world.snap_camera()
			world.go_station("mostrador")
		# --- end INTEGRATE
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
	for id in ["raiz_mandragora", "hongo_violeta"]:
		var sp := world.screen_pos(world.jars[id].global_position + Vector3(0, 0.3, 0))
		await _click_at(sp)
		await get_tree().create_timer(1.2).timeout
		print("CLICK jar ", id, " at ", sp, " -> contents=", contents)
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
	await get_tree().create_timer(0.5).timeout
	# botón Remover del panel
	var bp := ui.brew_btn.get_global_rect().get_center()
	await _click_at(bp)
	await get_tree().create_timer(1.0).timeout
	print("CLICK brew -> overlay=", ov.current)
	if ov.current == "stir":
		await _click_at(Vector2(960, 540))
	await get_tree().create_timer(4.0).timeout
	print("POTIONS ", Game.potions)
	get_tree().quit()

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
				# --- STORY: el bot no escribe pergaminos
				if Story.wanted_kind(current) == "scroll":
					_on_choice("decline")
					continue
				# --- end STORY
				var want: String = current["potion"]
				var have := -1
				for i in Game.potions.size():
					if Game.potions[i]["id"] == want:
						have = i
						break
				if have >= 0:
					_on_potion(have)
					continue
				var combo := _find_combo(want)
				if combo.is_empty():
					print("AUTOPLAY: sin receta para ", want, " stock=", Game.stock)
					errors += 1
					_on_choice("decline")
					continue
				for id in combo:
					_on_jar_clicked(id)
					await get_tree().create_timer(0.3).timeout
				_on_brew()
				await get_tree().create_timer(0.8).timeout
				if ov.current == "stir":
					ov.stir_key()
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
	get_tree().quit()

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
						Game.buy_ingredient(id, 2)
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
