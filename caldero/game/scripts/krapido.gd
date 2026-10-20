extends Node
class_name Krapido
## --- R4 RAVEN: Krápido («¡Kraa!» + «rápido»: pociones a pico y pluma), el reparto a domicilio por cuervo.
## Una mejora del puesto de Mabel ("krapido"): una ventanilla con percha en la pared del fondo, del lado de la
## alquimista, y una bola de cristal junto a ella (la estación "ventanilla" de shop_world.gd).
##
## El día de Krápido (solo con la tienda abierta):
##   1. Los PEDIDOS llegan primero a la bola: una campanita, la bola late. Cada pedido es una tarjeta (quién pide, la
##      poción en una línea corta, la pista en iconos, a veces una runa y un reloj: cuánto falta para que pase el cuervo).
##   2. DESPUÉS llega Graznido a la percha y espera un minuto (un reloj sobre él). Ella le da la botella del estante en
##      la ventanilla (un frasco del estante con la bola abierta o estando en la ventanilla): él la guarda en la
##      cartera, suelta una rima y se va. El cliente paga como en el mostrador y su carta llega por correo (con su
##      reseña en plumas). Si no hay nada listo, Graznido se va enojado: pedido perdido y una reseña de 1 pluma.
##   3. Las reseñas (Game.plumas(), 1 a 5) deciden cuántos pedidos llegan cada día (Game.krapido_orders_per_day()).
##   4. Al cerrar, los pedidos que falten se cancelan sin castigo.
## El tiempo: segundos de tienda abierta (se pausan con los menús de lectura); si main.gd tiene el reloj del día de
## PACE (shop_minutes(): 540 = 9:00 .. 1080 = 18:00), se usa ese reloj.
## Escribe en Game.today: "deliveries", "deliveries_lost" y "plumas" (bloque R4 RAVEN de game.gd).

signal orders_changed
signal raven_changed

const DAY_SECONDS := 300.0       # un día de tienda: 5 minutos
const FIRST_SPAWN := 10.0        # el primer pedido llega a los ~10 s de abrir
const LAST_SPAWN := 0.55         # no llegan pedidos nuevos después del 55% del día (para que el cuervo alcance)
const LEAD_MIN := 55.0           # Graznido pasa entre 55 y 80 s después de que llega el pedido
const LEAD_MAX := 80.0
const LEAD_RUNE := 15.0          # (+15 s si el pedido lleva runa: hay que ir al grimorio)
const RAVEN_WAIT := 60.0         # lo que espera en la percha
const RAVEN_GAP := 6.0           # entre una visita y la siguiente
const RUNE_CHANCE := 0.3         # pedidos con runa (si el grimorio ya está abierto y sabe alguna)
const HURRY_AT := 15.0           # cuando le quedan 15 s, se impacienta

var main                         # main.gd
var world: ShopWorld
var ball: BallUI
var raven: Raven
var orders: Array = []           # los pedidos de hoy (ver _spawn)
var day_t := 0.0                 # segundos de tienda abierta (sin el reloj de PACE)
var unseen := 0                  # pedidos nuevos que todavía no se vieron en la bola
var raven_state := "away"        # away | arriving | waiting | busy | leaving
var raven_order := {}            # el pedido que vino a buscar
var raven_left := 0.0            # segundos que le quedan en la percha
var _plan: Array = []            # cuándo llegan los pedidos que faltan (segundos de tienda)
var _seq := 0
var _next_visit := 0.0
var _hurried := false
var _active := false             # hay día de Krápido en marcha (tienda abierta y mejora comprada)
var _brewable := {}
var _closing_hold := false       # (sin PACE) la tienda espera a que terminen los pedidos

func setup(m) -> void:
	main = m
	world = m.world
	raven = Raven.new()
	raven.name = "Graznido"
	world.add_child(raven)
	ball = BallUI.new()
	ball.setup(m, self)
	m.add_child(ball)

# ------------------------------------------------------------------ el día

## La tienda abrió: si está la mejora, se planea cuándo llegan los pedidos de hoy.
func on_open() -> void:
	reset_day()
	if not Game.krapido_on():
		return
	_active = true
	_brewable = Game.brewable_potions()
	var n := Game.krapido_orders_per_day()
	var span := DAY_SECONDS * LAST_SPAWN - FIRST_SPAWN
	for i in n:
		var t := FIRST_SPAWN + span * (float(i) / float(maxi(1, n - 1)) if n > 1 else 0.0)
		_plan.append(maxf(4.0, t + randf_range(-6.0, 8.0)))
	_plan.sort()
	Game.today["plumas"] = Game.plumas()

## La tienda cierra: los pedidos pendientes se cancelan sin castigo y Graznido se va.
func on_close() -> void:
	if not _active and orders.is_empty() and raven_state == "away":
		return
	var had := orders.size()
	_active = false
	_plan.clear()
	orders.clear()
	unseen = 0
	if ball.is_open():
		ball.close_now()
	if raven_state == "busy":
		pass   # (le están dando la botella: la entrega termina sola y él se va)
	elif raven_state != "away":
		var waiting := raven_state == "waiting"
		raven_state = "leaving"
		raven_order = {}
		if waiting:
			raven.say(Story.pick(Data.RAVEN_LINES["closed"]), 2.2)
		_leave_later(1.6 if waiting else 0.0)
	world.krapido_glow_level = 0.0
	orders_changed.emit()
	raven_changed.emit()
	if had > 0:
		main.ui.toast("Krápido: pedidos cancelados", UIKit.MUTED, 2.6)

## Todo a cero (empieza la mañana, vuelve al título, demos).
func reset_day() -> void:
	_active = false
	_closing_hold = false
	orders.clear()
	_plan.clear()
	unseen = 0
	day_t = 0.0
	_next_visit = 0.0
	raven_state = "away"
	raven_order = {}
	raven_left = 0.0
	if raven:
		raven.hide_now()
	if world:
		world.krapido_glow_level = 0.0
		world.krapido_hatch(false)
	if ball and ball.is_open():
		ball.close_now()
	orders_changed.emit()
	raven_changed.emit()

func active() -> bool:
	return _active

## El reloj de Krápido: segundos de tienda abierta (o la hora de PACE convertida a segundos).
func now() -> float:
	if main.has_method("shop_minutes"):
		return (float(main.shop_minutes()) - 540.0) / 540.0 * DAY_SECONDS
	return day_t

## Los menús de lectura (recetario, diario, correo, ajustes, el escalafón...) paran el reloj; los de trabajo no (la
## bola, el banco del caldero, el grimorio encantando, el removido y el encargo al mercado).
const WORK_PANELS := ["grimoire", "stir", "market"]

func _paused() -> bool:
	if main.has_method("clock_paused"):   # --- R4 MERGE: la misma regla que el reloj del día de PACE (y su tutorial)
		return main.in_market or main.clock_paused()
	return main.in_market or (main.ov.is_open() and not WORK_PANELS.has(String(main.ov.current)))

func _process(delta: float) -> void:
	if not _active or not main.is_open_phase():
		return
	var paused := _paused()
	if not paused:
		day_t += delta
	var t := now()
	while not _plan.is_empty() and t >= float(_plan[0]):
		_plan.pop_front()
		_spawn(t)
	if raven_state == "away" and t >= _next_visit:
		var o := _next_due(t)
		if not o.is_empty():
			_visit(o)
	if raven_state == "waiting":
		if not paused:
			raven_left -= delta
		raven.set_wait(raven_left / RAVEN_WAIT)
		if raven_left <= HURRY_AT and not _hurried:
			_hurried = true
			raven.say(Story.pick(Data.RAVEN_LINES["hurry"]), 2.2)
			Sfx.play("kraa", 0.06, -8.0)
		if raven_left <= 0.0:
			_lost()
	world.krapido_glow_level = 2.0 if raven_state == "waiting" else (1.0 if unseen > 0 else 0.0)

# ------------------------------------------------------------------ pedidos

## Quién puede pedir ahora: ya llegó al pueblo, no espera noticias, no está hoy en la fila del mostrador ni pidió
## ya por Krápido, y su poción se puede preparar.
func _candidates() -> Array:
	var busy_who := {}
	# --- R4 SHIP: con el día de PACE, main.queue es TODA la gente del día (desde la apertura): excluirla entera dejaba
	# la bola casi vacía (de 3 pedidos planeados llegaban 0-1). Los «de más» del día (los que no tienen hora: solo entran
	# si la tienda queda vacía) pueden pedir por cuervo en su lugar (_spawn los quita de la lista); quien tiene hora,
	# los aventureros, las visitas con noticias y el tutorial siguen fuera.
	var arr = main.get("_arrivals")
	var sched: int = (arr as Array).size() if arr is Array else main.queue.size()
	for i in main.queue.size():
		var q: Dictionary = main.queue[i]
		if i >= sched and String(q.get("kind", "")) == "villager" and not q.get("tutorial", false):
			continue
		busy_who[String(q.get("who", ""))] = true
	if not main.current.is_empty():
		busy_who[String(main.current.get("who", ""))] = true
	for v in (main.get("line") if main.get("line") is Array else []):   # --- R4 MERGE: quien ya espera en la fila de PACE
		busy_who[String((v as Dictionary).get("req", {}).get("who", ""))] = true
	var cv = main.get("_counter_v")   # --- R4 SHIP: y quien va de la fila al mostrador (todavía no es main.current)
	if cv is Dictionary and not (cv as Dictionary).is_empty():
		busy_who[String((cv as Dictionary).get("req", {}).get("who", ""))] = true
	for o in orders:
		busy_who[String(o["who"])] = true
	var out := []
	for r in Data.KRAPIDO_ORDERS:
		var who := String(r["who"])
		if busy_who.has(who) or not Game.story_free(who):
			continue
		if int(Data.CHARACTERS.get(who, {}).get("arrives", 1)) > Game.day:
			continue
		if not _brewable.has(String(r["potion"])):
			continue
		out.append(r)
	return out

## Llega un pedido a la bola: campanita, la bola late y aparece su tarjeta.
func _spawn(t: float) -> void:
	var cand := _candidates()
	if cand.is_empty():
		return
	# primero quien hace más que no pide (para que no se repitan siempre los mismos)
	cand.shuffle()
	# --- R4 SHIP: y antes, quien está libre en el pueblo; después, los «de más» del día (ver _candidates)
	var tier := {}
	for q in main.queue:
		tier[String((q as Dictionary).get("who", ""))] = 1
	cand.sort_custom(func(a, b):
		var ta := int(tier.get(String(a["who"]), 0))
		var tb := int(tier.get(String(b["who"]), 0))
		if ta != tb:
			return ta < tb
		return int(Game.last_seen.get(String(a["who"]), -10)) < int(Game.last_seen.get(String(b["who"]), -10)))
	var r: Dictionary = cand[0]
	# --- R4 SHIP: si era uno de los «de más» del día, pide por cuervo en su lugar: sale de la lista (no viene además)
	for i in main.queue.size():
		var q: Dictionary = main.queue[i]
		if String(q.get("who", "")) == String(r["who"]) and String(q.get("kind", "")) == "villager" and not q.get("tutorial", false):
			main.queue.remove_at(i)
			break
	_seq += 1
	var o := {"id": _seq, "who": String(r["who"]), "potion": String(r["potion"]), "line": String(r["line"]),
		"good": String(r.get("good", "")), "fail": String(r.get("fail", "")), "runes": [],
		"ess": Array(Data.POTIONS[String(r["potion"])]["pair"]), "t0": t, "state": "incoming"}
	if Game.rune_orders_today() > 0 and randf() < RUNE_CHANCE:
		var kr := Game.known_runes()
		if not kr.is_empty():
			o["runes"] = [kr.pick_random()]
	var lead := randf_range(LEAD_MIN, LEAD_MAX) + (LEAD_RUNE if not o["runes"].is_empty() else 0.0)
	o["lead"] = lead
	o["pickup"] = t + lead
	orders.append(o)
	Game.last_seen[o["who"]] = Game.day
	unseen += 1
	Game.krapido_stats["orders"] = int(Game.krapido_stats.get("orders", 0)) + 1
	Sfx.play("ball_chime", 0.03, -5.0)
	world.krapido_sparkle()
	if not Game.krapido_seen:
		main.ui.show_tip("¡Un pedido en la [b]bola de cristal[/b]!", 8.0)
	orders_changed.emit()

## El pedido que Graznido viene a buscar ahora (el de recogida más temprana que ya tocó).
func _next_due(t: float) -> Dictionary:
	var best := {}
	for o in orders:
		if String(o["state"]) == "incoming" and float(o["pickup"]) <= t:
			if best.is_empty() or float(o["pickup"]) < float(best["pickup"]):
				best = o
	return best

## Segundos que faltan para que Graznido pase por este pedido (0 si ya le tocó y espera turno).
func time_to_pickup(o: Dictionary) -> float:
	return maxf(0.0, float(o.get("pickup", 0.0)) - now())

## Lo que se manda a Story / Game: el pedido como si fuera de un cliente del mostrador.
func req_of(o: Dictionary) -> Dictionary:
	return {"who": o["who"], "kind": "villager", "potion": o["potion"], "text": o["line"], "good": o.get("good", ""),
		"fail": o.get("fail", ""), "runes": o.get("runes", []).duplicate()}

# ------------------------------------------------------------------ Graznido

func _visit(o: Dictionary) -> void:
	raven_state = "arriving"
	raven_order = o
	world.krapido_hatch(true)
	await get_tree().create_timer(0.45).timeout
	if raven_state != "arriving":
		return
	await raven.fly_in(ShopWorld.KRAPIDO_PERCH)
	if raven_state != "arriving" or not orders.has(o):
		return
	o["state"] = "waiting"
	raven_state = "waiting"
	raven_left = RAVEN_WAIT
	_hurried = false
	Sfx.play("kraa", 0.06, -4.0)
	raven.say(Story.pick(Data.RAVEN_LINES["arrive"]), 2.4)
	main.ui.toast("¡Graznido en la ventanilla!", UIKit.GOLD_BRIGHT, 2.6)
	orders_changed.emit()
	raven_changed.emit()

## Se fue sin nada: pedido perdido y una reseña de una pluma.
func _lost() -> void:
	var o := raven_order
	raven_state = "leaving"
	raven_order = {}
	orders.erase(o)
	Game.today["deliveries_lost"] = int(Game.today.get("deliveries_lost", 0)) + 1
	Game.krapido_stats["lost"] = int(Game.krapido_stats.get("lost", 0)) + 1
	Game.krapido_add_review(String(o.get("who", "")), 1, true)
	raven.set_wait(-1.0)
	raven.angry()
	raven.say(Story.pick(Data.RAVEN_LINES["angry"]), 2.6)
	main.ui.toast("Pedido perdido · 1 pluma", UIKit.BAD, 2.8)
	orders_changed.emit()
	raven_changed.emit()
	Game.save_game()
	_leave_later(1.8)

func _leave_later(delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if raven.state == "perched" or raven.state == "flying":
		await raven.fly_off()
	world.krapido_hatch(false)
	if raven_state == "leaving":
		raven_state = "away"
	_next_visit = now() + RAVEN_GAP
	raven_changed.emit()

## Graznido espera en la percha.
func raven_waiting() -> bool:
	return raven_state == "waiting"

## Un frasco del estante tocado (main._on_potion): si Graznido espera y ella está en la ventanilla (o la bola está
## abierta, o no hay nadie en el mostrador), la poción es para él. true si se la llevó Krápido (o se ignora el toque).
func take_potion(i: int) -> bool:
	if not _active or raven_state != "waiting":
		return false
	if main._brew_open() and main.customer_ready:
		return false   # (banco abierto y un cliente en el mostrador: la poción va al mostrador, como siempre)
	if not (ball.is_open() or world.at_station("ventanilla") or not main.customer_ready):
		return false
	if main.busy or i < 0 or i >= Game.potions.size():
		return true
	_hand_over(i)
	return true

## La entrega en la ventanilla: la botella vuela del estante a sus manos y de ahí al pico de Graznido.
func _hand_over(i: int) -> void:
	var o := raven_order
	main.busy = true
	raven_state = "busy"
	var waited := RAVEN_WAIT - raven_left
	raven.set_wait(-1.0)
	if ball.is_open():
		await ball.close()
	if main._brew_open():
		main.busy = false
		await main.brew.close()   # (embotella lo que hubiera removido)
		main.busy = true
	main.ui.hide_tooltip()
	if not world.at_station("ventanilla"):
		var ok: bool = await world.go_station("ventanilla")   # (camina aunque esté ocupada: go_to no mira can_walk)
		if not ok or raven_state != "busy" or i >= Game.potions.size():
			main.busy = false
			if raven_state == "busy":
				raven_state = "waiting"
			return
	world.alchemist.face(-1)
	var from := world.rack_slot_position(i)
	var p := Game.take_potion(i)
	world.refresh_rack()
	var tex: Texture2D = load("res://assets/icons/pot_%s.png" % p["id"])
	var hand := world.alchemist.global_position + Vector3(-0.15, 1.15, 0.12)
	await world.fly(tex, from, hand, 0.5, 0.6, 0.03)
	world.alchemist.hop(1)
	await world.fly(tex, hand, raven.beak_position(), 0.38, 0.3, 0.03)
	await raven.catch(tex)
	# paga como en el mostrador; la noticia (y la reseña) llega por carta
	var item: Dictionary = main._item_of(p)
	var req := req_of(o)
	var ok := String(item["id"]) == String(o["potion"])
	var price := Story.price_of(item, req)
	Game.add_gold(price)
	Sfx.play("coin", 0.05, -4.0)
	main.ui.fly_coins(world.screen_pos(raven.global_position + Vector3(0, 0.45, 0)), clampi(price / 4, 3, 8))
	var out := Story.make_outcome(req, item, ok, price, 0)
	out["via"] = "letter"
	out["due"] = Game.day + (1 if randf() < 0.7 else 2)
	out["krapido"] = true
	out["krapido_wait"] = waited
	Game.schedule_outcome(out)
	Game.today["deliveries"] = int(Game.today.get("deliveries", 0)) + 1
	Game.krapido_stats["delivered"] = int(Game.krapido_stats.get("delivered", 0)) + 1
	orders.erase(o)
	raven_order = {}
	raven_state = "leaving"
	raven.say(Story.pick(Data.RAVEN_LINES["take"]), 3.0)
	Sfx.play("kraa", 0.06, -6.0)
	if ok:
		main._purr()
		main._think(Story.pick(Data.INTUITION["give_match"]))
	main.busy = false
	orders_changed.emit()
	raven_changed.emit()
	Game.save_game()
	_leave_later(2.4)

# ------------------------------------------------------------------ sin el reloj de PACE

## (Sin el reloj del día) La fila del mostrador terminó: la tienda espera a Graznido. No llegan pedidos nuevos y los
## que faltan se adelantan (el cuervo viene enseguida). Vuelve cuando no queda ninguno.
func wait_orders() -> void:
	if not _active:
		return
	_plan.clear()
	if orders.is_empty() and raven_state == "away":
		return
	_closing_hold = true
	var t := now() + 6.0
	var incoming := orders.filter(func(o): return String(o["state"]) == "incoming")
	incoming.sort_custom(func(a, b): return float(a["pickup"]) < float(b["pickup"]))
	for o in incoming:
		o["pickup"] = minf(float(o["pickup"]), t)
		t = float(o["pickup"]) + 2.0
	main.ui.toast("Krápido: faltan pedidos", UIKit.GOLD, 2.6)
	orders_changed.emit()
	while _active and main.is_open_phase() and (not orders.is_empty() or raven_state != "away"):
		await get_tree().create_timer(0.3).timeout
	_closing_hold = false

# ------------------------------------------------------------------ la bola

## Ir a la bola (el botón de Krápido del HUD, o la estación): camina hasta la ventanilla y la abre.
func go_ball() -> void:
	if not Game.krapido_on() or main.in_market or ball.is_open():
		return
	if not main._can_interact() or main._brew_open():
		return
	if not world.at_station("ventanilla"):
		if not await world.go_station("ventanilla"):
			return
	open_ball()

func open_ball() -> void:
	if not Game.krapido_on() or ball.is_open() or main.in_market:
		return
	world.walker.stop()
	world.alchemist.face(-1)
	unseen = 0
	Game.krapido_seen = true
	ball.open()

func ball_open() -> bool:
	return ball != null and ball.is_open()

# ------------------------------------------------------------------ pruebas y capturas

## (Capturas y pruebas) Pone pedidos de mentira en la bola: n pedidos, el primero con el cuervo esperando si raven.
func demo_orders(n: int, with_raven: bool, rune := "") -> void:
	reset_day()
	_active = true
	_brewable = Game.brewable_potions()
	var picks := []
	for pass_i in 2:   # primero pociones distintas; si faltan, se repiten
		for r in Data.KRAPIDO_ORDERS:
			if picks.size() < n and _brewable.has(String(r["potion"])) and not picks.any(func(q): return q["who"] == r["who"]) \
					and (pass_i == 1 or not picks.any(func(q): return q["potion"] == r["potion"])):
				picks.append(r)
	var t := now()
	for i in picks.size():
		var r: Dictionary = picks[i]
		_seq += 1
		var o := {"id": _seq, "who": String(r["who"]), "potion": String(r["potion"]), "line": String(r["line"]),
			"good": String(r["good"]), "fail": String(r["fail"]), "runes": [], "ess": Array(Data.POTIONS[String(r["potion"])]["pair"]),
			"t0": t, "state": "incoming", "lead": 70.0, "pickup": t + 18.0 + i * 31.0}
		if i == 1 and rune != "":
			o["runes"] = [rune]
		orders.append(o)
	if with_raven and not orders.is_empty():
		var o0: Dictionary = orders[0]
		o0["state"] = "waiting"
		o0["pickup"] = t
		raven_state = "waiting"
		raven_order = o0
		raven_left = RAVEN_WAIT * 0.7
		world.krapido_hatch(true)
		raven.perch_now(ShopWorld.KRAPIDO_PERCH)
	_next_visit = INF if not with_raven else 0.0
	unseen = orders.size()
	orders_changed.emit()
	raven_changed.emit()

## (Bot) El pedido que conviene preparar ahora: el que espera el cuervo, o el próximo que va a buscar.
func bot_target() -> Dictionary:
	if raven_state == "waiting" and not raven_order.is_empty():
		return raven_order
	var best := {}
	for o in orders:
		if best.is_empty() or float(o["pickup"]) < float(best["pickup"]):
			best = o
	return best
