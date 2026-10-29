extends Node
class_name ShopDay
## --- SS CORE: el día abierto (5 minutos reales, un reloj de 9 AM a 6 PM, como Midnight Cauldron).
## La gente llega según la agenda del día (Data.SCHEDULE), entra por la puerta y espera en la fila DENTRO de la
## tienda (4 sitios: ShopWorld.QUEUE_SPOTS) con un reloj de arena sobre la cabeza (su paciencia). El primero pasa al
## mostrador cuando queda libre (ShopWorld.P_CUSTOMER) y espera que Nell le hable (at_counter). Si la paciencia se
## acaba, se va enfadado; si la fila está llena, se asoma, suspira y se va. A las 6 PM se cierra: la fila se va a casa,
## quien ya está siendo atendido se queda hasta terminar; cuando no queda nadie, day_over.
## main.gd decide qué pasa en el mostrador (el diálogo, el banco, el regateo) y llama a begin_talk / end_talk /
## start_work / leave. Cada visitante es un diccionario: "id", "who", "kind" ("repair" | "buy"), "item", "fault",
## "wants", "actor", "p" (paciencia 0..1), "state" ("in" entrando, "line", "step" al mostrador, "counter" esperando a
## Nell, "talk" hablando, "work" su cosa en el banco o regateando, "peek" fila llena, "out" saliendo), "line_secs",
## "counter_secs", "grumpy", "t_job" (cuándo aceptó Nell el trabajo), el camino ("path", "ev", "speed", "wait").

signal at_counter(v: Dictionary)
signal left(v: Dictionary, why: String)   # why: "angry" | "full" | "home" | "done" | "declined"
signal closing_started
signal day_over
signal line_changed(n: int)

var world: ShopWorld
var hud: Hud
var shop_t := 0.0
var running := false
var closing := false
var paused := false        # el menú de pausa (todo se detiene)
var hold := false          # el tutorial del día 1: el reloj espera hasta la primera entrega
var line: Array = []       # la fila (en orden; incluye a quien todavía está entrando)
var counter := {}          # quien está en el mostrador ({} = nadie)
var leaving: Array = []    # quienes van saliendo
var _arrivals: Array = []
var _seq := 0
var _over := false
var _last_line := -1

func setup(w: ShopWorld, h: Hud) -> void:
	world = w
	hud = h

# ------------------------------------------------------------------ abrir y cerrar

## Abre el día: la agenda, el reloj a las 9:00. El día 1 el primero entra ya y el reloj espera (tutorial).
func open_day(day: int, tutorial := false) -> void:
	clear()
	_arrivals = Data.schedule_for(day)
	running = true
	hold = tutorial
	if tutorial and not _arrivals.is_empty():
		_arrive(_arrivals.pop_front())

## Vacía la tienda: sin fila, sin nadie en el mostrador ni saliendo, el reloj a cero, la puerta cerrada.
func clear() -> void:
	var all: Array = line + leaving
	if not counter.is_empty():
		all.append(counter)
	for v in all:
		var a = v.get("actor")
		if is_instance_valid(a):
			a.queue_free()
	line = []
	leaving = []
	counter = {}
	_arrivals = []
	shop_t = 0.0
	running = false
	closing = false
	hold = false
	paused = false
	_over = false
	_last_line = -1
	if world:
		world.door_reset()
		world.counter_actor = null
		world.set_counter_item("")
	if hud:
		hud.clear_chips()

## Los minutos del reloj (540 = 9:00 AM ... 1080 = 6:00 PM).
func minutes() -> int:
	var f := clampf(shop_t / Data.DAY_SECONDS, 0.0, 1.0)
	return Data.OPEN_MIN + int(f * float(Data.CLOSE_MIN - Data.OPEN_MIN))

func is_open_now() -> bool:
	return running and not closing

func line_count() -> int:
	return line.size()

## Cuántos faltan por llegar hoy.
func pending_arrivals() -> int:
	return _arrivals.size()

## Quien espera en el mostrador a que Nell le hable ({} si nadie).
func waiting_at_counter() -> Dictionary:
	if not counter.is_empty() and String(counter["state"]) == "counter":
		return counter
	return {}

## Fuerza el cierre (el reloj llega a las 6 PM ya: pruebas y capturas).
func force_close() -> void:
	shop_t = Data.DAY_SECONDS
	hold = false

# ------------------------------------------------------------------ llegar, la fila, el mostrador

func _visitor(e: Dictionary) -> Dictionary:
	_seq += 1
	var who := String(e.get("who", "zib"))
	var f := Data.patience_of(who)
	return {"id": _seq, "who": who, "kind": String(e.get("kind", "repair")), "item": String(e.get("item", "")),
		"fault": String(e.get("fault", "")), "wants": e.get("wants", []), "actor": null, "p": 1.0, "state": "in",
		"line_secs": Data.LINE_PATIENCE * f, "counter_secs": Data.COUNTER_PATIENCE * f, "grumpy": false,
		"t_job": -1.0, "path": [], "ev": [], "speed": 1.7, "wait": 0.0, "fidget": randf_range(5.0, 9.0)}

func _arrive(e: Dictionary) -> void:
	var v := _visitor(e)
	var a := world.make_actor(String(v["who"]), ShopWorld.P_OUTSIDE, -1)
	v["actor"] = a
	Game.stat("arrived")
	world.door_hold()
	if line.size() >= Data.MAX_LINE:
		# la fila está llena: se asoma, suspira y se va
		v["state"] = "peek"
		Game.stat("missed")
		Game.stat("patience_lost")
		_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_PEEK], ["", "release"], 1.6)
		leaving.append(v)
		return
	line.append(v)
	_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_PEEK, _spot(line.size() - 1)], ["", "release", ""])
	_advance()

func _spot(i: int) -> Vector3:
	return ShopWorld.QUEUE_SPOTS[clampi(i, 0, ShopWorld.QUEUE_SPOTS.size() - 1)]

## Si el mostrador está libre, el primero de la fila pasa (si esperó demasiado, llega de mal humor: sin propina).
func _advance() -> void:
	if not counter.is_empty() or line.is_empty() or closing:
		return
	var v: Dictionary = line.pop_front()
	counter = v
	v["grumpy"] = float(v["p"]) < Data.GRUMPY_BELOW
	v["p"] = 1.0
	v["state"] = "step"
	_retarget(v, ShopWorld.P_CUSTOMER, 0.15)
	_shift()

func _shift() -> void:
	for i in line.size():
		var w: Dictionary = line[i]
		var target := _spot(i)
		var path: Array = w["path"]
		var a: Actor = w["actor"]
		var dest: Vector3 = path.back() if not path.is_empty() else (a.global_position if is_instance_valid(a) else target)
		if dest.distance_to(target) > 0.05:
			_retarget(w, target, 0.25 + 0.2 * float(i))

## Cambia a dónde va (si todavía está entrando, primero termina de cruzar la puerta).
func _retarget(v: Dictionary, target: Vector3, delay := 0.0) -> void:
	var path: Array = v["path"]
	var ev: Array = v["ev"]
	var k := ev.find("release")
	if k >= 0:
		v["path"] = path.slice(0, k + 1) + [target]
		v["ev"] = ev.slice(0, k + 1) + [""]
	else:
		if path.is_empty():
			v["wait"] = delay
		v["path"] = [target]
		v["ev"] = [""]

func _path(v: Dictionary, pts: Array, evs: Array, speed := 1.7) -> void:
	v["path"] = pts.duplicate()
	v["ev"] = evs.duplicate()
	v["speed"] = speed

## Un paso de quien camina (velocidad fija, sin tweens: se le puede cambiar el camino a mitad).
func _move(v: Dictionary, delta: float) -> void:
	var a = v.get("actor")
	if not is_instance_valid(a):
		return
	if float(v["wait"]) > 0.0:
		v["wait"] = float(v["wait"]) - delta
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
			_reached(v)
		return
	a.global_position += to / d * step
	a.set_walking(true)
	if absf(to.x) > 0.04:
		a.face(1 if to.x > 0.0 else -1)

func _reached(v: Dictionary) -> void:
	var a: Actor = v["actor"]
	match String(v["state"]):
		"in", "line":
			v["state"] = "line"
			a.face(-1)
		"step":
			v["state"] = "counter"
			a.face(-1)
			Game.stat("customers")
			world.counter_actor = a
			if String(v["kind"]) == "repair" and not Data.is_self_repair(String(v["who"])):   # (--- SS MERGE: Clatter no trae nada)
				world.set_counter_item(String(v["item"]))
			a.emote("excl", 1.2)
			Sfx.play("blip", 0.06, -8.0)
			at_counter.emit(v)
		"peek":
			a.face(-1)
			a.emote("dots", 1.2)
			world.blurt(a, Data.line(String(v["who"]), "full"), Color(1.0, 0.86, 0.7))
			await get_tree().create_timer(1.3).timeout
			if is_instance_valid(a):
				v["state"] = "out"
				_path(v, [ShopWorld.P_DOOR_IN, ShopWorld.P_OUTSIDE], ["hold", "release"], 1.8)
				left.emit(v, "full")
		"out":
			leaving.erase(v)
			a.queue_free()

# ------------------------------------------------------------------ lo que hace main.gd en el mostrador

## Nell le habla (el diálogo está abierto): no se cansa mientras tanto.
func begin_talk() -> void:
	if not counter.is_empty() and String(counter["state"]) == "counter":
		counter["state"] = "talk"

## Cerró el diálogo sin decidir: vuelve a esperar.
func end_talk() -> void:
	if not counter.is_empty() and String(counter["state"]) == "talk":
		counter["state"] = "counter"

## Nell aceptó (reparar en el banco, o regatear una venta): espera su cosa, se cansa muy despacio y no se va.
func start_work() -> void:
	if counter.is_empty():
		return
	counter["state"] = "work"
	counter["t_job"] = shop_t
	if hud:
		hud.remove_chip(int(counter["id"]))

## Se va (atendido, rechazado, cansado o a casa): sale por detrás de la fila y por la puerta.
## say: lo que dice al irse (vacío = la frase de su porqué).
func leave(v: Dictionary, why: String, say := "", col := Color(1.0, 0.95, 0.85)) -> void:
	if v.is_empty() or String(v.get("state", "")) == "out":
		return
	var was_counter := not counter.is_empty() and int(counter["id"]) == int(v["id"])
	if was_counter:
		counter = {}
		world.counter_actor = null
		world.set_counter_item("")
	line.erase(v)
	v["state"] = "out"
	leaving.append(v)
	if hud:
		hud.remove_chip(int(v["id"]))
	var a: Actor = v["actor"]
	var text := say if say != "" else Data.line(String(v["who"]), {"angry": "angry", "home": "home", "declined": "decline"}.get(why, why))
	if why == "angry":
		Game.stat("walkouts")
		Game.stat("patience_lost")
		Game.add_rep(Data.REP_WALKOUT)
		a.emote("angry", 1.2)
		col = Color(1.0, 0.62, 0.52)
	elif why == "home":
		a.emote("dots", 1.0)
	world.blurt(a, text, col)
	var pts: Array = []
	var evs: Array = []
	if was_counter:
		pts = [ShopWorld.P_EXIT_BACK, ShopWorld.P_PEEK, ShopWorld.P_DOOR_IN, ShopWorld.P_OUTSIDE]
		evs = ["", "hold", "", "release"]
	else:
		pts = [ShopWorld.P_PEEK, ShopWorld.P_DOOR_IN, ShopWorld.P_OUTSIDE]
		evs = ["hold", "", "release"]
	_path(v, pts, evs, 1.9 if why == "angry" else 1.7)
	v["wait"] = 0.9   # dice su frase y se va
	left.emit(v, why)
	if was_counter:
		_advance()
	else:
		_shift()

## El té de Kettle: i = 0 el mostrador, 1.. la fila. Devuelve true si había alguien.
func tea_boost(i: int) -> bool:
	var v := {}
	if i == 0:
		v = counter
	elif i - 1 < line.size():
		v = line[i - 1]
	if v.is_empty() or String(v.get("state", "")) == "out":
		return false
	v["p"] = minf(1.0, float(v["p"]) + Data.TEA_BOOST)
	var a: Actor = v["actor"]
	if is_instance_valid(a):
		a.emote("heart", 1.2)
	return true

## (demos y capturas) Pone gente de una vez: entries en la fila (en sus sitios, con la paciencia dada en "p") y, si
## counter_e no está vacío, alguien ya en el mostrador esperando a Nell.
func demo_fill(entries: Array, counter_e := {}) -> void:
	if not counter_e.is_empty() and counter.is_empty():
		var v := _visitor(counter_e)
		v["actor"] = world.make_actor(String(v["who"]), ShopWorld.P_CUSTOMER, -1)
		v["state"] = "step"
		counter = v
		_reached(v)
	for e in entries:
		if line.size() >= Data.MAX_LINE:
			break
		var w := _visitor(e)
		w["actor"] = world.make_actor(String(w["who"]), _spot(line.size()), -1)
		w["state"] = "line"
		w["p"] = float(e.get("p", 0.8))
		line.append(w)

# ------------------------------------------------------------------ cada cuadro

func _process(delta: float) -> void:
	if not running:
		return
	if not paused:
		if not hold:
			shop_t = minf(shop_t + delta, Data.DAY_SECONDS)
		# llega quien tiene hora
		while not closing and not _arrivals.is_empty() and float(_arrivals[0]["t"]) <= shop_t and not hold:
			_arrive(_arrivals.pop_front())
		_patience(delta)
		if not closing and shop_t >= Data.DAY_SECONDS:
			_close()
	for v in line + leaving:
		_move(v, 0.0 if paused else delta)
	if not counter.is_empty():
		_move(counter, 0.0 if paused else delta)
	_update_chips()
	if line.size() != _last_line:
		_last_line = line.size()
		line_changed.emit(line.size())
	if closing and not _over and counter.is_empty() and line.is_empty() and leaving.is_empty():
		_over = true
		running = false
		day_over.emit()

func _patience(delta: float) -> void:
	if hold:
		return
	for v in line.duplicate():
		if String(v["state"]) in ["in", "line"]:
			v["p"] = float(v["p"]) - delta / float(v["line_secs"])
			if float(v["p"]) <= 0.0:
				leave(v, "angry")
	if counter.is_empty():
		return
	match String(counter["state"]):
		"counter":
			counter["p"] = float(counter["p"]) - delta / float(counter["counter_secs"])
			if float(counter["p"]) <= 0.0:
				leave(counter, "angry")
		"work":
			counter["p"] = maxf(Data.WORK_FLOOR, float(counter["p"]) - delta * Data.WORK_DRAIN / float(counter["counter_secs"]))

## A las 6 PM: la fila se va a casa; quien espera en el mostrador sin que Nell le haya hablado, también.
func _close() -> void:
	closing = true
	for v in line.duplicate():
		leave(v, "home")
	if not counter.is_empty() and String(counter["state"]) in ["counter", "step"]:
		leave(counter, "home")
	closing_started.emit()

## Los relojes de arena sobre las cabezas (la fila y quien espera en el mostrador).
func _update_chips() -> void:
	if hud == null or world == null or world.camera == null:
		return
	var show_all := not paused
	for v in line:
		_chip(v, show_all)
	if not counter.is_empty():
		_chip(counter, show_all and String(counter["state"]) in ["counter", "step"])

func _chip(v: Dictionary, on: bool) -> void:
	var a = v.get("actor")
	if not is_instance_valid(a):
		return
	var p: Vector3 = a.global_position + Vector3(0.0, a.top_height() + 0.18, 0.0)
	if not on or world.camera.is_position_behind(p) or a.emote_sprite.visible:
		hud.set_chip(int(v["id"]), Vector2.ZERO, float(v["p"]), false)
		return
	hud.set_chip(int(v["id"]), world.camera.unproject_position(p), float(v["p"]), true)
