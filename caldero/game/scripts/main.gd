extends Node
## Flujo del juego: título, mañana (mercado), clientes, caldero, entregas y cierre del día.

enum Phase { TITLE, INTRO, MORNING, OPEN, CLOSING }

const INTRO_LINES := [
	["", "Al pie de la Montaña Gris hay un pueblo pequeño. Y en el pueblo, una tiendita de pociones con la chimenea siempre encendida."],
	["", "Tu maestra te la dejó al partir de viaje, junto con su libro de recetas, un caldero viejo y una gata dormilona llamada Miga."],
	["", "Por aquí pasan aventureros de todo el reino. Siempre necesitan algo… y no siempre saben explicarlo. Escúchalos con calma."],
]

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
var _alch_at_cauldron := false

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

	world.jar_clicked.connect(_on_jar_clicked)
	world.jar_hover.connect(func(id):
		if not ov.is_open():
			ui.show_ingredient_tooltip(id))
	world.jar_unhover.connect(func(_id): ui.hide_tooltip())
	world.cat_clicked.connect(_on_cat_clicked)
	world.book_clicked.connect(func():
		if _can_interact(true):
			ov.show_book())
	world.customer_clicked.connect(_on_customer_clicked)
	world.cauldron_clicked.connect(func():
		if _can_interact() and contents.size() >= 2:
			_on_brew())
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

	Sfx.start_ambience()
	_parse_args()
	if _demo != "":
		_run_demo()
	else:
		_show_title()

func _build_open_button() -> void:
	open_btn = UIKit.button("Abrir la tienda", func(): _open_shop(), 28)
	open_btn.custom_minimum_size = Vector2(340, 64)
	UIKit.place(open_btn, Vector2(0.5, 0), Vector2(-170, 24), Vector2(340, 64), Control.GROW_DIRECTION_BOTH)
	open_btn.visible = false
	ui.root.add_child(open_btn)

# ------------------------------------------------------------------ título y comienzo

func _show_title() -> void:
	phase = Phase.TITLE
	ui.set_gameplay_visible(false)
	ui.hide_dialog()
	open_btn.visible = false
	world.set_time(1.0, false)
	world.cat.play("sleep")
	ov.show_title(Game.has_save())

func _to_title() -> void:
	_clear_customer()
	contents.clear()
	ui.set_cauldron([])
	world.cauldron.set_liquid(Color("3b3156"))
	await _fade_to(1.0, 0.5)
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
	world.alchemist.global_position = ShopWorld.P_ALCH_COUNTER
	world.alchemist.face(1)
	_alch_at_cauldron = false
	Game.save_game()
	ui.show_banner("Día %d" % Game.day, "Mañana")
	var got := Game.morning_harvest()
	if got.size() > 0:
		ui.toast("Cosechaste 2 raíces de mandrágora y 2 lágrimas de sirena en el huerto.", UIKit.GOOD, 3.5)
	open_btn.visible = true
	await get_tree().create_timer(1.6).timeout
	if phase != Phase.MORNING:
		return
	if Game.day == 1 and not Game.tutorial_done:
		ui.show_tip("Cada mañana puedes comprar ingredientes y mejoras en el [b]Mercado[/b]. Hoy ya tienes lo necesario: pulsa [b]Abrir la tienda[/b] cuando quieras.")
	else:
		ov.show_market("morning")

func _open_shop() -> void:
	if phase != Phase.MORNING:
		return
	if ov.is_open():
		ov.close(false)
	open_btn.visible = false
	ui.hide_tip()
	phase = Phase.OPEN
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
	return Data.CHARACTERS[who]["name"]

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
	customer.setup(current["who"], Data.CHARACTERS[current["who"]]["pixel"])
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
	customer.emote("excl", 1.2)
	if not _alch_at_cauldron:
		world.alchemist.face(1)
	await get_tree().create_timer(0.5).timeout
	customer_ready = true
	_talk_request()

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
	if current["kind"] == "hero" and current.get("chapter", 0) == 0:
		text = "[color=#c9bfd9][i](%s, %s)[/i][/color]\n%s" % [who, Data.CHARACTERS[current["who"]]["title"], text]
	ui.say(who, text, choices)

func _on_customer_clicked() -> void:
	if customer_ready and not ui.dialog_open() and not busy and not ov.is_open():
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

func _go_cauldron() -> void:
	if _alch_at_cauldron:
		world.alchemist.face(-1)
		return
	_alch_at_cauldron = true
	await world.alchemist.walk_to(ShopWorld.P_ALCH_CAULDRON, 2.4)
	world.alchemist.face(-1)

func _go_counter() -> void:
	if not _alch_at_cauldron:
		world.alchemist.face(1)
		return
	_alch_at_cauldron = false
	await world.alchemist.walk_to(ShopWorld.P_ALCH_COUNTER, 2.4)
	world.alchemist.face(1)

func _on_jar_clicked(id: String) -> void:
	if not _can_interact():
		if ui.dialog_open() and phase == Phase.OPEN:
			ui.toast("Primero responde a tu cliente.")
		return
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
	var idx := Game.potion_index(pid, potency)
	world.rack_sprites[mini(idx, world.rack_sprites.size() - 1)].visible = false
	await world.fly(load("res://assets/icons/pot_%s.png" % pid), ShopWorld.CAULDRON_POS + Vector3(0, 1.3, 0.1), world.rack_slot_position(idx), 0.7, 1.0, 0.04)
	world.refresh_rack()
	if is_new:
		ui.show_banner("¡Nueva receta!", Data.POTIONS[pid]["name"])
		Sfx.play("sparkle", 0.0, -2.0)
	else:
		ui.toast("Preparaste %s (%d %s)." % [Data.POTIONS[pid]["name"], Game.stars_for(potency), "estrella" if Game.stars_for(potency) == 1 else "estrellas"])
	if customer_ready:
		await _go_counter()
	busy = false
	if tutorial_step == 1:
		tutorial_step = 2
		ui.show_tip("¡Tu primera poción! Está en tu estante (abajo a la derecha).\nTócala para entregársela a Greta.")

# ------------------------------------------------------------------ entregas

func _on_potion(i: int) -> void:
	if not _can_interact():
		return
	if not customer_ready or customer == null:
		ui.toast("No hay ningún cliente esperando.")
		return
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
	if p["id"] == current["potion"]:
		_success(p)
	else:
		_wrong(p)

func _success(p: Dictionary) -> void:
	var who := _char_name(current["who"])
	var stars := Game.stars_for(p["potency"])
	var pr := Game.price_for(p["id"], p["potency"], misses)
	var total: int = pr["price"] + pr["tip"]
	customer.hop(2)
	customer.emote("heart", 2.0)
	world.spawn_hearts(customer.global_position + Vector3(0, 1.9, 0.1))
	Sfx.play("coin", 0.05, -4.0)
	Game.add_gold(total)
	ui.fly_coins(world.screen_pos(customer.global_position + Vector3(0, 1.4, 0)), clampi(total / 4, 3, 10))
	var gain := stars + (2 if current["kind"] == "hero" else 0)
	Game.stats["sold"] += 1
	Game.today["sold"] += 1
	Game.add_renombre(gain)
	var text: String
	if current["kind"] == "hero":
		text = current["thanks"]
		var gift := Game.complete_chapter(current["who"])
		if gift.has("item"):
			ui.toast("Regalo: +%d %s" % [gift["qty"], Data.INGREDIENTS[gift["item"]]["name"]], UIKit.GOOD, 3.0)
		ui.toast("Nueva página en el Diario de viajeros.", UIKit.GOLD_BRIGHT, 3.0)
		if gift.has("gold"):
			ui.fly_coins(world.screen_pos(customer.global_position + Vector3(0, 1.4, 0)), 4)
			total += gift["gold"]
	else:
		text = THANKS[stars - 1].pick_random()
	ui.hide_order()
	ui.say(who, "%s\n[color=#ffd987]+%d oro   ·   +%d renombre[/color]" % [text, total, gain], [["bye", "¡Buen viaje!"]])
	busy = false
	if tutorial_step == 2:
		tutorial_step = 3
		Game.tutorial_done = true
		ui.show_tip("Cada venta te da [b]oro[/b] y [b]renombre[/b]. Con más renombre llegan ingredientes nuevos y aventureros con historias.\nSi un pedido es difícil, ¡pide una pista!")
		get_tree().create_timer(12.0).timeout.connect(func():
			if tutorial_step == 3:
				ui.hide_tip())

func _wrong(p: Dictionary) -> void:
	var who := _char_name(current["who"])
	Game.return_potion(p)
	world.refresh_rack()
	misses += 1
	customer.emote("sweat", 1.6)
	customer.shake()
	Sfx.play("sad", 0.0, -4.0)
	var line: String = Data.WRONG_LINES.pick_random()
	if misses >= 2 and not hint_given:
		hint_given = true
		line += "\n[i]%s[/i]" % current["hint"]
	busy = false
	ui.say(who, line, [["retry", "Probaré otra cosa"], ["decline", "No puedo ayudarte"]])

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
			ov.show_market("morning" if phase == Phase.MORNING else "day")
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
			world.alchemist.global_position = ShopWorld.P_ALCH_CAULDRON
			world.alchemist.face(-1)
			ui.show_ingredient_tooltip("hongo_violeta")
		"stir":
			contents = ["hongo_violeta", "hongo_violeta"]
			world.alchemist.global_position = ShopWorld.P_ALCH_CAULDRON
			world.alchemist.face(-1)
			ov.show_stir(1.0)
		"market":
			ov.show_market("morning")
		"upgrades":
			ov._market_tab = 1
			ov.show_market("morning")
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
					var label := first.text
					if label == "¡Buen viaje!":
						_on_choice("bye")
					else:
						_on_choice("prepare")
				else:
					ui._advance()
				continue
			if customer_ready and not ui.dialog_open() and not busy:
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
	print("AUTOPLAY DONE errors=", errors, " day=", Game.day, " gold=", Game.gold, " level=", Game.level(), " journal=", Game.journal.size())
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
