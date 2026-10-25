extends Node
class_name EventGame
## --- R4 EVENTS: el evento en marcha (lo crea main.gd el día del evento, con el escenario ya puesto). Las reglas:
##   academia: la profesora pide N pociones iguales de una receta (en la pizarra) y hay un reloj grande. Cada poción
##     de la receta que ella embotella la recoge el alumno que está primero en la fila. Puntos = estrellas de cada
##     poción (+1 por cada 10 s que sobren si termina antes). Una poción que no es la del examen se queda en el estante.
##   concurso: tres rondas; en cada una, un tema («Algo para dormir»...). Ella deduce la poción, la prepara y toca la
##     del estante para presentarla (si se acaba el tiempo, se presenta sola la que mejor encaje). Tres jurados dan de
##     1 a 5 estrellas con una frase; Fizz y dos rivales también puntúan. El puesto final da la medalla.
##   torneo: caballeros y escuderos hacen fila en su puesto (6 sitios) pidiendo vigor, curación o valor; cada uno con
##     su paciencia. Lo que ella embotella (o tiene en el estante) se lo lleva el primero de la fila que lo pidió.
##     Puntos = estrellas + 1 si le sobraba más del 60 % de su paciencia; además, propinas en oro.
## El banco del caldero es el de la tienda (main.gd: open_brew, _on_brew, brew_bottle) en modo evento; el inventario
## de la tienda está guardado aparte (Game.events_stash) y el caldero usa la despensa del evento. main.gd avisa:
## on_bottled() al embotellar y on_shelf_click() al tocar una poción del estante. Al terminar emite finished(resultado).

signal finished(result: Dictionary)
signal _round_done

const WALK_SPEED := 2.4
const LINE_MAX := 6
# --- R5 EN-UI: en el concurso, la clave de ella en totals es un id (antes la palabra «Tú»); ME_NAME es lo que se lee
const ME := "me"
const ME_NAME := "You"
# --- end R5 EN-UI

var main                      # main.gd
var eui: EventUI
var ev: Dictionary            # el evento aceptado (Game.ev_booked)
var kind := ""
var plan: Dictionary = {}
var tier := 0
var scene: Node3D
var her: Actor
var running := false          # el reloj corre
var over := false             # terminó (ya no se cuenta nada)
var started := false
var time_left := 0.0
var time_total := 0.0
var score := 0
var cuts := {}
var mk := {}                  # nombre del marcador -> posición global
var mk_face := {}             # nombre del marcador -> 1 (mira a la derecha), -1 (a la izquierda) o 0 (meta "face")
var line: Array = []          # la fila: [{a: Actor, who, want, pat, pat_max, slot, state, arrived, bar, fill, icon}]
var leaving: Array = []       # los que se van: [{a, to}]
var to_spawn := 0             # visitantes que aún no llegaron (feria) o alumnos que faltan por entrar (academia)
var next_spawn := 0.0
var spawned := 0
var served := 0
var lost := 0
var tips := 0
var delivered := 0
var bonus := 0
var _pool: Array = []
var _pool_i := 0
var _wants: Array = []        # feria: los pedidos posibles ["vigor", "curacion", "valor"]
# concurso
var themes: Array = []
var round_i := 0
var presented := {}
var totals := {}              # nombre -> estrellas (ella: la clave ME)
var rivals: Array = []        # Fizz y dos puestos (Events.rivals_for: con los letreros del escenario si los trae)
var history: Array = []       # por ronda: {"theme", "potion", "scores"}
var judges: Array = []        # Actor de cada jurado
var _first_present_tip := true

static var _white: Texture2D

func setup(m, ui_: EventUI, ev_: Dictionary, scene_: Node3D) -> void:
	main = m
	eui = ui_
	ev = ev_
	kind = String(ev.get("kind", "academia"))
	plan = ev.get("plan", {})
	if plan.is_empty():
		plan = Events.plan(kind, int(ev.get("tier", 0)))
	tier = int(ev.get("tier", 0))
	scene = scene_
	var names := ["Player", "Bench"]
	for i in LINE_MAX:
		names.append("Queue%d" % i)
	for i in 3:
		names.append("Judge%d" % i)
	for n in names:
		var node := scene.get_node_or_null(n) as Node3D
		mk[n] = node.global_position if node else Vector3(-2.0 + 1.1 * names.find(n), 0.0, -1.2)
		mk_face[n] = int(node.get_meta("face", 0)) if node else 0
	cuts = Events.cuts(kind, plan)
	rivals = Events.rivals_for(scene)
	_pool = Array(Events.info(kind)["visitors"]).duplicate()
	_pool.shuffle()
	if _pool.is_empty():
		_pool = ["pip"]

# ------------------------------------------------------------------ montaje

## Ella en su puesto y, según el evento, el jurado o la primera fila de alumnos.
func build_people() -> void:
	her = Actor.new()
	scene.add_child(her)
	her.setup("alquimista", 0.04)
	her.global_position = mk["Player"]
	her.face(_face_at("Player", mk["Queue0"]))
	match kind:
		"academia":
			to_spawn = int(plan.get("n", 6))
			for i in mini(LINE_MAX, to_spawn):
				_spawn_visitor(String(plan.get("potion", "")), -1.0, true)
		"concurso":
			for i in Events.JUDGES.size():
				var j: Dictionary = Events.JUDGES[i]
				var a := Actor.new()
				scene.add_child(a)
				a.setup(Story.sprite_id(String(j["id"])), 0.04)
				a.global_position = mk["Judge%d" % i]
				a.face(_face_at("Judge%d" % i, mk["Player"]))
				judges.append(a)
			her.face(_face_at("Player", mk["Judge1"]))
		"torneo":
			to_spawn = int(plan.get("k", 10))
			_wants = ["vigor", "curacion", "valor"]

## El principio: la anfitriona habla, la cuenta atrás y a trabajar.
func run() -> void:
	build_people()
	eui.show_hud(kind)
	eui.set_time(float(plan.get("time", 60)), float(plan.get("time", 60)))
	_update_hud()
	var host := String(Events.info(kind)["host_name"])
	main.ui.say(host, Events.line(kind, "intro", ev))
	await main.ui.dialog_advanced
	main.ui.hide_dialog()
	if kind == "concurso":
		await _run_concurso()
	else:
		_set_board()
		await eui.countdown()
		time_total = float(plan.get("time", 90))
		time_left = time_total
		started = true
		running = true
		next_spawn = 1.0
		_open_bench()
		while not over:
			await get_tree().process_frame
	await _finish()

func _open_bench() -> void:
	if not main._brew_open():
		main.open_brew()
	eui.set_bench_button(false)

# ------------------------------------------------------------------ cada cuadro

func _process(delta: float) -> void:
	_move_people(delta)
	if not running or over:
		return
	if main.ov.is_open() or main.ui.dialog_open():
		return   # leer el recetario o los ajustes para el reloj (como en la tienda)
	time_left -= delta
	eui.set_time(time_left, time_total)
	match kind:
		"torneo":
			_tick_torneo(delta)
		"academia":
			pass
	eui.set_bench_button(not main._brew_open())
	if time_left <= 0.0:
		time_left = 0.0
		eui.set_time(0.0, time_total)
		if kind == "concurso":
			_auto_present()
		else:
			_end_play()
	_update_line_hud()

## Mueve a la gente hacia su sitio (la fila avanza, entran y se van) sin tweens que se pisen.
func _move_people(delta: float) -> void:
	for v in line:
		var a: Actor = v["a"]
		if not is_instance_valid(a):
			continue
		var goal: Vector3 = mk["Queue%d" % int(v["slot"])]
		var d := a.global_position.distance_to(goal)
		if d > 0.03:
			a.set_walking(true)
			a.face_towards(goal)
			a.global_position = a.global_position.move_toward(goal, WALK_SPEED * delta)
		elif not bool(v["arrived"]):
			a.set_walking(false)
			a.face(_face_at("Queue%d" % int(v["slot"]), mk["Player"]))
			v["arrived"] = true
		_place_bar(v)
	for v in leaving.duplicate():
		var a2: Actor = v["a"]
		if not is_instance_valid(a2):
			leaving.erase(v)
			continue
		var to: Vector3 = v["to"]
		a2.set_walking(true)
		a2.face_towards(to)
		a2.global_position = a2.global_position.move_toward(to, WALK_SPEED * 1.15 * delta)
		if a2.global_position.distance_to(to) < 0.05:
			leaving.erase(v)
			a2.queue_free()

## Hacia dónde mira quien está en un marcador: su meta "face" (los escenarios de EVENTS-SCENES la ponen) o, si no
## tiene, hacia un punto (ella, el jurado...).
func _face_at(marker: String, toward: Vector3) -> int:
	var f := int(mk_face.get(marker, 0))
	if f != 0:
		return f
	return 1 if toward.x >= mk.get(marker, Vector3.ZERO).x else -1

## Extras opcionales del escenario (EVENTS-SCENES): el público se alegra o se lamenta.
func _cheer(good: bool) -> void:
	if is_instance_valid(scene) and scene.has_method("cheer"):
		scene.call("cheer", good)

## Un personaje que el escenario puso solo (la profesora, Fizz...), o null.
func _fixed(id: String) -> Actor:
	if not is_instance_valid(scene):
		return null
	var f = scene.get("fixed")
	if f is Dictionary and f.has(id) and is_instance_valid(f[id]):
		return f[id] as Actor
	return null

## Por donde entran y salen: más allá del último sitio de la fila.
func _exit_point() -> Vector3:
	var q4: Vector3 = mk["Queue4"]
	var q5: Vector3 = mk["Queue5"]
	var dir := (q5 - q4)
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3(1, 0, 0)
	# --- R4 MERGE (EVENTS + SCENES): al menos 5 m más allá de Queue5 y, si ese punto aún se ve (el torneo: justo en el
	# borde derecho), un poco más lejos, hasta salir del encuadre: nadie aparece ni desaparece a la vista
	dir = dir.normalized()
	var k := 5.0
	var cam: Camera3D = scene.get_node_or_null("Camera") as Camera3D if is_instance_valid(scene) else null
	if cam and cam.is_inside_tree():
		var vr := cam.get_viewport().get_visible_rect().grow(90.0)
		while k < 12.0 and vr.has_point(cam.unproject_position(q5 + dir * k + Vector3(0, 0.8, 0))):
			k += 0.5
	return q5 + dir * k
	# --- end R4 MERGE

# ------------------------------------------------------------------ la fila (academia y feria)

func _next_who() -> String:
	var w := String(_pool[_pool_i % _pool.size()])
	_pool_i += 1
	return w

## Llega alguien a la fila (al primer sitio libre). want: la poción que pide. pat < 0: sin paciencia.
func _spawn_visitor(want: String, pat: float, instant := false) -> void:
	if line.size() >= LINE_MAX:
		return
	var who := _next_who()
	var a := Actor.new()
	scene.add_child(a)
	a.setup(Story.sprite_id(who), 0.04)
	a.quiet = true
	var slot := line.size()
	a.global_position = mk["Queue%d" % slot] if instant else _exit_point()
	var v := {"a": a, "who": who, "want": want, "pat": pat, "pat_max": pat, "slot": slot, "state": "wait", "arrived": instant,
		"t": 0.0}
	if pat >= 0.0 or kind == "torneo":
		_make_bar(v)
	line.append(v)
	spawned += 1
	to_spawn -= 1

## Una barra de paciencia (y lo que pide) sobre la cabeza.
func _make_bar(v: Dictionary) -> void:
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	var a: Actor = v["a"]
	var holder := Node3D.new()
	scene.add_child(holder)
	var bg := _quad_sprite(Color(0.16, 0.1, 0.07, 0.9), Vector3(0.72, 0.11, 1.0), 9)
	holder.add_child(bg)
	var fill := _quad_sprite(Color("6fbf5a"), Vector3(0.64, 0.06, 1.0), 10)
	holder.add_child(fill)
	var ic := Sprite3D.new()
	ic.texture = load("res://assets/icons/pot_%s.png" % String(v["want"])) if ResourceLoader.exists("res://assets/icons/pot_%s.png" % String(v["want"])) else null
	ic.pixel_size = 0.03
	ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ic.no_depth_test = true
	ic.render_priority = 10
	ic.shaded = false
	ic.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ic.position = Vector3(0, 0.36, 0)
	holder.add_child(ic)
	v["bar"] = holder
	v["fill"] = fill
	v["bar_bg"] = bg
	holder.visible = float(v["pat_max"]) > 0.0 or kind == "academia"
	bg.visible = float(v["pat_max"]) > 0.0
	fill.visible = float(v["pat_max"]) > 0.0
	_place_bar(v)

func _quad_sprite(col: Color, sc: Vector3, prio: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _white
	s.pixel_size = 0.25
	s.scale = sc
	s.modulate = col
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.render_priority = prio
	s.shaded = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s

func _place_bar(v: Dictionary) -> void:
	if not v.has("bar"):
		return
	var a: Actor = v["a"]
	var holder: Node3D = v["bar"]
	if not is_instance_valid(a) or not is_instance_valid(holder):
		return
	holder.global_position = a.global_position + Vector3(0, a.top_height() + 0.32, 0.05)
	var pm := float(v["pat_max"])
	if pm > 0.0:
		var f := clampf(float(v["pat"]) / pm, 0.0, 1.0)
		var fill: Sprite3D = v["fill"]
		fill.scale.x = 0.64 * maxf(0.02, f)
		fill.position.x = -0.32 * (1.0 - f)   # pegada a la izquierda (el cuadro mide 1 m a escala 1)
		fill.modulate = Color("d24a3c").lerp(Color("e2b84a"), clampf(f * 2.0, 0.0, 1.0)).lerp(Color("6fbf5a"), clampf(f * 2.0 - 1.0, 0.0, 1.0))

## Se va de la fila (servido o cansado): los de detrás avanzan un sitio.
func _leave(v: Dictionary, happy: bool) -> void:
	var a: Actor = v["a"]
	line.erase(v)
	if v.has("bar") and is_instance_valid(v["bar"]):
		v["bar"].queue_free()
	for i in line.size():
		line[i]["slot"] = i
		line[i]["arrived"] = false
	if is_instance_valid(a):
		a.emote("heart" if happy else "sweat", 1.2)
		if happy:
			a.hop(1)
		leaving.append({"a": a, "to": _exit_point()})

## Una poción vuela de ella a quien la recoge.
func _fly3d(pid: String, to: Actor) -> void:
	if not is_instance_valid(her) or not is_instance_valid(to):
		return
	var s := Sprite3D.new()
	s.texture = load("res://assets/icons/pot_%s.png" % pid)
	s.pixel_size = 0.035
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.render_priority = 5
	scene.add_child(s)
	var from := her.global_position + Vector3(0, 1.1, 0.1)
	var dest := to.global_position + Vector3(0, 1.0, 0.1)
	s.global_position = from
	var tw := s.create_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(s):
			var p := from.lerp(dest, t)
			p.y += sin(t * PI) * 0.7
			s.global_position = p
			s.rotation.z = t * TAU * 0.5, 0.0, 1.0, 0.5)
	tw.tween_callback(s.queue_free)

# ------------------------------------------------------------------ el estante del evento

## Busca en el estante (Game.potions del evento) una poción con ese id (la de más potencia).
func _shelf_find(pid: String) -> int:
	var best := -1
	for i in Game.potions.size():
		if String(Game.potions[i]["id"]) == pid and (best < 0 or int(Game.potions[i]["potency"]) > int(Game.potions[best]["potency"])):
			best = i
	return best

## main.gd: una poción recién embotellada (ya está en el estante del evento).
func on_bottled(pid: String, potency: int, perfect: bool) -> void:
	# marca la poción con su removido (el concurso lo juzga)
	for p in Game.potions:
		if String(p["id"]) == pid and int(p["potency"]) == potency and not p.has("ev_tag"):
			p["ev_tag"] = true
			p["perfect"] = perfect
			break
	var cau = scene.get("cauldron") if is_instance_valid(scene) else null
	if cau is Cauldron and Data.POTIONS.has(pid):
		(cau as Cauldron).brew_burst(Data.POTIONS[pid]["color"])
	if over:
		return
	match kind:
		"academia":
			_academia_bottled(pid, potency)
		"torneo":
			_torneo_serve_all()
		"concurso":
			if _first_present_tip and running:
				_first_present_tip = false
				main._bench_say("Tap it on the shelf to present it", UIKit.GOLD_BRIGHT)

## main.gd: tocó la poción i del estante.
func on_shelf_click(i: int) -> void:
	if over or i < 0 or i >= Game.potions.size():
		return
	match kind:
		"concurso":
			if running:
				_present(i)
		"torneo":
			var pid := String(Game.potions[i]["id"])
			for v in line:
				if v["state"] == "wait" and bool(v["arrived"]) and String(v["want"]) == pid:
					_serve_torneo(v, i)
					return
			_give_away(i)
		"academia":
			_give_away(i)   # (las del examen las recogen solos: en el estante solo quedan las que no son)

## Una poción que nadie pidió deja sitio en el estante: se la regala al público.
func _give_away(i: int) -> void:
	var p := Game.take_potion(i)
	if p.is_empty():
		return
	Sfx.play("plop", 0.05, -6.0)
	main.ui.toast("%s: for the crowd" % Events.potion_name(String(p["id"])), UIKit.TEXT, 1.8)

# ------------------------------------------------------------------ academia

func _academia_bottled(pid: String, potency: int) -> void:
	if pid != String(plan.get("potion", "")):
		main._bench_say("That's not the exam potion!", UIKit.BAD)
		Sfx.play("sad", 0.05, -8.0)
		return
	if line.is_empty() or delivered >= int(plan.get("n", 6)):
		return
	var idx := Game.find_potion({"id": pid, "potency": potency})
	if idx < 0:
		idx = _shelf_find(pid)
	if idx < 0:
		return
	var p := Game.take_potion(idx)
	var st := Game.stars_for(int(p.get("potency", potency)))
	delivered += 1
	score += st
	var v: Dictionary = line[0]
	v["state"] = "served"
	_fly3d(pid, v["a"])
	Sfx.play("coin", 0.05, -6.0)
	eui.pop("+%d ★" % st, UIKit.GOLD_BRIGHT if st >= 3 else UIKit.TEXT)
	_leave(v, true)
	# entra el siguiente alumno (si faltan)
	if to_spawn > 0:
		_spawn_visitor(String(plan.get("potion", "")), -1.0)
	_update_hud()
	if delivered >= int(plan.get("n", 6)):
		bonus = int(floor(time_left / 10.0))
		score += bonus
		if bonus > 0:
			eui.pop("+%d time" % bonus, Color("8fe08a"))
		_end_play()

# ------------------------------------------------------------------ feria del torneo

func _tick_torneo(delta: float) -> void:
	# llegan caballeros (cada uno pide algo); si la fila está llena se van
	next_spawn -= delta
	if to_spawn > 0 and next_spawn <= 0.0:
		var span := maxf(20.0, time_total - 25.0)
		next_spawn = (span / float(int(plan.get("k", 10)))) * randf_range(0.7, 1.3)
		var want: String = _wants.pick_random()
		var pid := Events.torneo_potion(want, tier)
		var knight := randf() < 0.6
		var pat := (30.0 if knight else 22.0) * (1.0 - 0.05 * tier)
		if line.size() >= LINE_MAX:
			to_spawn -= 1
			spawned += 1
			lost += 1
			main.ui.toast("Line full: someone left", UIKit.BAD, 1.6)
		else:
			_spawn_visitor(pid, pat)
	# la paciencia baja (desde que llegó a la fila)
	for v in line.duplicate():
		if v["state"] != "wait" or not bool(v["arrived"]):
			continue
		v["pat"] = float(v["pat"]) - delta
		v["t"] = float(v["t"]) + delta
		if float(v["pat"]) <= 0.0:
			v["state"] = "lost"
			lost += 1
			Sfx.play("sad", 0.05, -8.0)
			_cheer(false)
			_leave(v, false)
			_update_hud()
	_torneo_serve_all()
	# se acabó: nadie más por llegar y la fila vacía
	if to_spawn <= 0 and line.is_empty():
		_end_play()

## Quien está en la fila y ya llegó a su sitio se lleva lo que pidió si está en el estante (el primero de la fila primero).
func _torneo_serve_all() -> void:
	for v in line.duplicate():
		if v["state"] != "wait" or not bool(v["arrived"]):
			continue
		var idx := _shelf_find(String(v["want"]))
		if idx >= 0:
			_serve_torneo(v, idx)

func _serve_torneo(v: Dictionary, idx: int) -> void:
	var p := Game.take_potion(idx)
	if p.is_empty():
		return
	var st := Game.stars_for(int(p.get("potency", 4)))
	var fast := float(v["pat"]) >= float(v["pat_max"]) * 0.6
	var pts := st + (1 if fast else 0)
	score += pts
	served += 1
	var tip := 2 + 2 * st + (2 if fast else 0)
	tips += tip
	Game.add_gold(tip)
	v["state"] = "served"
	_fly3d(String(p["id"]), v["a"])
	Sfx.play("coin", 0.05, -5.0)
	eui.pop("+%d%s" % [pts, " fast!" if fast else ""], UIKit.GOLD_BRIGHT if fast else UIKit.TEXT)
	_leave(v, true)
	_update_hud()

# ------------------------------------------------------------------ concurso

func _run_concurso() -> void:
	themes = Events.pick_themes(int(plan.get("rounds", 3)))
	totals = {ME: 0}
	for r in rivals:
		totals[String(r["name"])] = 0
	for i in themes.size():
		round_i = i + 1
		var th: Dictionary = themes[i]
		# el estante del concurso se vacía en cada ronda (lo que sobra se lo lleva el público)
		Game.potions = []
		Game.potions_changed.emit()
		presented = {}
		_set_board()
		_update_hud()
		eui.set_time(float(plan.get("time", 44)), float(plan.get("time", 44)))
		await eui.show_theme(round_i, themes.size(), String(th["text"]))
		time_total = float(plan.get("time", 44))
		time_left = time_total
		started = true
		running = true
		_open_bench()
		await _round_done
		running = false
		eui.set_bench_button(false)
		if main._brew_open():
			main.brew_ready = {}
			main.brew.close_now()
		# el jurado
		var scores := []
		var lines := []
		for j in Events.JUDGES:
			var sc := Events.judge(String(j["id"]), th, presented)
			scores.append(sc)
			lines.append(String(Events.JUDGE_LINES[String(j["id"])][maxi(0, sc - 1)]) if sc > 0 else "Nothing to taste…")
		var mine := 0
		for sc in scores:
			mine += int(sc)
		totals[ME] = int(totals[ME]) + mine
		var table := [{"name": ME_NAME, "round": mine, "total": int(totals[ME]), "me": true}]
		var fizz_round := 0
		for r in rivals:
			var rs: Array = Events.rival_round(r, tier)
			var sum := 0
			for x in rs:
				sum += int(x)
			totals[String(r["name"])] = int(totals[String(r["name"])]) + sum
			table.append({"name": String(r["name"]), "round": sum, "total": int(totals[String(r["name"])])})
			if String(r["id"]) == "fizz":
				fizz_round = sum
		history.append({"theme": String(th["text"]), "potion": presented, "scores": scores})
		for k in judges.size():
			if is_instance_valid(judges[k]):
				judges[k].emote("heart" if int(scores[k]) >= 4 else ("note" if int(scores[k]) >= 3 else "sweat"), 1.6)
		var fl: String = Story.pick(Events.FIZZ_LINES["high" if fizz_round > mine else "low"])
		_cheer(mine >= 11)
		var fz := _fixed("fizz")
		if fz:
			fz.emote("sparkle" if fizz_round > mine else "sweat", 2.0)
			if fizz_round > mine:
				fz.hop(2)
		eui.set_line(_contestant_entries())
		await eui.show_jury({"round": round_i, "theme": String(th["text"]), "potion": presented, "scores": scores,
			"lines": lines, "table": table, "last": round_i >= themes.size(), "fizz_line": fl})
		if eui.modal_kind() == "jury":
			await eui.jury_closed   # «Siguiente ronda» (o Espacio): la tarjeta se lee con calma
	over = true

## Presenta la poción i del estante al jurado (termina la ronda para ella).
func _present(i: int) -> void:
	if not running or i < 0 or i >= Game.potions.size():
		return
	var p := Game.take_potion(i)
	presented = {"id": String(p["id"]), "potency": int(p["potency"]), "perfect": bool(p.get("perfect", false))}
	running = false
	Sfx.play("sparkle", 0.05, -4.0)
	main.ui.toast("You present: %s %s" % [Events.potion_name(String(p["id"])), "★".repeat(Game.stars_for(int(p["potency"])))], UIKit.GOLD_BRIGHT, 2.0)
	_round_done.emit()

## Se acabó el tiempo de la ronda: se presenta sola la que mejor encaje (o nada).
func _auto_present() -> void:
	if not running:
		return
	var th: Dictionary = themes[round_i - 1] if round_i >= 1 and round_i <= themes.size() else {}
	var best := -1
	var best_k := -1
	for i in Game.potions.size():
		var q: Dictionary = Game.potions[i]
		var k := Events.fit(th, String(q["id"])) * 100 + int(q["potency"])
		if k > best_k:
			best_k = k
			best = i
	if best >= 0:
		_present(best)
	else:
		presented = {}
		running = false
		main.ui.toast("Time! You presented nothing", UIKit.BAD, 2.0)
		_round_done.emit()

func _contestant_entries() -> Array:
	var out := []
	out.append({"who": "alquimista", "name": ME_NAME, "label": "%d ★" % int(totals.get(ME, 0)), "state": "wait", "pat": -1.0})
	for r in rivals:
		out.append({"who": String(r["sprite"]), "name": String(r["name"]), "label": "%d ★" % int(totals.get(String(r["name"]), 0)),
			"state": "wait", "pat": -1.0})
	return out

func place() -> int:
	var mine := int(totals.get(ME, 0))
	var p := 1
	for r in rivals:
		if int(totals.get(String(r["name"]), 0)) > mine:
			p += 1
	return p

# ------------------------------------------------------------------ el final

## Se acabó el tiempo (o ya terminó): el reloj se para y el banco se cierra.
func _end_play() -> void:
	if over:
		return
	running = false
	over = true

func _finish() -> void:
	running = false
	over = true
	eui.set_bench_button(false)
	if main._brew_open():
		main.brew_ready = {}
		main.brew.close_now()
	eui.shout("Time!" if (kind != "concurso" and time_left <= 0.0) else "Done!", UIKit.GOLD_BRIGHT, 0.9)
	await get_tree().create_timer(1.3).timeout
	# los que quedaron en la fila se van
	for v in line.duplicate():
		_leave(v, v["state"] == "served")
	var res := result()
	_cheer(String(res["medal"]) != "none")
	var host := String(Events.info(kind)["host_name"])
	main.ui.say(host, String(Events.info(kind)["end"][String(res["medal"])]))
	await main.ui.dialog_advanced
	main.ui.hide_dialog()
	finished.emit(res)

## El resultado: {"medal", "score", ...} y las filas de la tarjeta.
func result() -> Dictionary:
	var res := {"kind": kind, "score": score, "tips": tips}
	match kind:
		"academia":
			var n := int(plan.get("n", 6))
			res["medal"] = Events.medal_for(score, cuts)
			res["delivered"] = delivered
			res["rows"] = [["res://assets/icons/pot_%s.png" % String(plan.get("potion", "sueno_profundo")), "Potions delivered", "%d / %d" % [delivered, n]],
				["res://assets/icons/emote_star.png", "Points (stars)", "%d / %d" % [score - bonus, int(cuts.get("max", 3 * n))]]]   # --- R5 SHIP: sin la propina de tiempo (va en su fila): antes «25 / 24»
			if bonus > 0:
				res["rows"].append(["paper_i_hourglass", "Finished early", "+%d" % bonus])
		"torneo":
			res["medal"] = Events.medal_for(score, cuts)
			res["served"] = served
			res["lost"] = lost
			res["rows"] = [["paper_i_person", "Served", "%d / %d" % [served, int(plan.get("k", 10))]],
				["res://assets/icons/emote_sweat.png", "Walked out", str(lost)],
				["res://assets/icons/emote_coin.png", "Tips", "+%d" % tips]]
		"concurso":
			var pl := place()
			res["place"] = pl
			res["medal"] = Events.medal_for_place(pl)
			res["score"] = int(totals.get(ME, 0))
			var rows := []
			var order: Array = totals.keys()
			order.sort_custom(func(a, b): return int(totals[a]) > int(totals[b]) or (int(totals[a]) == int(totals[b]) and a == ME))
			for k in order.size():
				var nm: String = order[k]
				# --- R5 EN-UI: «1st  You», «2nd  Fizz» (UIKit.ordinal); ella se lee «You»
				rows.append(["res://assets/icons/emote_star.png" if nm == ME else "", "%s  %s" % [UIKit.ordinal(k + 1), ME_NAME if nm == ME else nm], "%d ★" % int(totals[nm])])
			res["rows"] = rows
	res["line"] = String(Events.info(kind)["end"][String(res["medal"])])
	return res

# ------------------------------------------------------------------ el HUD

func _set_board() -> void:
	match kind:
		"academia":
			var pid := String(plan.get("potion", ""))
			var ing := String(plan.get("ing", ""))
			eui.set_board("[b]Exam recipe[/b]\n%s = %s + %s" % [_img("res://assets/icons/pot_%s.png" % pid, 44),
				_img("res://assets/icons/ing_%s.png" % ing, 40), _img("res://assets/icons/ing_%s.png" % ing, 40)])
		"torneo":
			var rows := ["[b]Your stall[/b]"]
			for w in ["vigor", "curacion", "valor"]:
				var pid := Events.torneo_potion(w, tier)
				var rec: Array = Events.SIMPLE_RECIPE.get(pid, [])
				var t := "%s %s" % [_img("res://assets/icons/pot_%s.png" % pid, 40), String(Events.TORNEO_WANTS[w]["name"])]
				if rec.size() == 2:
					t += " = %s + %s" % [_img("res://assets/icons/ing_%s.png" % rec[0], 34), _img("res://assets/icons/ing_%s.png" % rec[1], 34)]
				rows.append(t)
			eui.set_board("\n".join(rows))
		"concurso":
			if round_i >= 1 and round_i <= themes.size():
				eui.set_board("[b]Round %d of %d[/b]\n[font_size=40]“%s”[/font_size]\n[color=#5e4632]Tap it on the shelf to present it[/color]" % [round_i, themes.size(), String(themes[round_i - 1]["text"])])

func _img(path: String, h: int) -> String:
	return "[img=%d]%s[/img]" % [h, path] if ResourceLoader.exists(path) else ""

func _update_hud() -> void:
	match kind:
		"academia":
			var pid := String(plan.get("potion", ""))
			eui.set_goal("%s [b]%d / %d[/b]    %s [b]%d[/b]" % [_img("res://assets/icons/pot_%s.png" % pid, 40), delivered, int(plan.get("n", 6)),
				_img("res://assets/icons/emote_star.png", 34), score])
			eui.set_score(score, cuts)
		"torneo":
			eui.set_goal("%s [b]%d / %d[/b]    %s [b]%d[/b]    %s [b]%d[/b]" % [_img("res://assets/ui/paper_i_person.png", 34), served, int(plan.get("k", 10)),
				_img("res://assets/icons/emote_star.png", 34), score, _img("res://assets/icons/emote_coin.png", 34), tips])
			eui.set_score(score, cuts)
		"concurso":
			eui.set_goal("[b]Round %d / %d[/b]    %s [b]%d[/b]" % [maxi(1, round_i), int(plan.get("rounds", 3)), _img("res://assets/icons/emote_star.png", 34), int(totals.get(ME, 0))])
			eui.set_score(0, {})
	_update_line_hud()

func _update_line_hud() -> void:
	if kind == "concurso":
		eui.set_line(_contestant_entries())
		return
	var entries := []
	for v in line:
		var pm := float(v["pat_max"])
		entries.append({"who": String(v["who"]), "potion": String(v["want"]), "pat": (float(v["pat"]) / pm) if pm > 0.0 else -1.0,
			"state": String(v["state"])})
	eui.set_line(entries)

# ------------------------------------------------------------------ para el bot (y las pruebas)

## La poción que conviene preparar ahora ("" = nada por ahora).
func bot_want() -> String:
	match kind:
		"academia":
			return String(plan.get("potion", "")) if delivered < int(plan.get("n", 6)) else ""
		"torneo":
			var have := {}
			for p in Game.potions:
				have[String(p["id"])] = int(have.get(String(p["id"]), 0)) + 1
			for v in line:
				if v["state"] != "wait":
					continue
				var w := String(v["want"])
				if int(have.get(w, 0)) > 0:
					have[w] = int(have[w]) - 1
					continue
				return w
			return ""
		"concurso":
			if not running or round_i < 1:
				return ""
			var th: Dictionary = themes[round_i - 1]
			var best := ""
			var best_k := -1
			for pid in th["fit"]:
				var c := bot_combo(String(pid))
				if c.is_empty():
					continue
				var k := int(th["fit"][pid]) * 100 + int(Game.evaluate(c).get("potency", 0))
				if k > best_k:
					best_k = k
					best = String(pid)
			return best
	return ""

## Concurso, para el bot que se equivoca de tema: otra poción que pueda preparar (mejor si encaja un poco).
func bot_want_other(best: String) -> String:
	var th: Dictionary = themes[round_i - 1] if round_i >= 1 and round_i <= themes.size() else {}
	var near := []
	var any := []
	for pid in Data.POTION_ORDER:
		if pid == best or bot_combo(pid).is_empty():
			continue
		any.append(pid)
		if Events.fit(th, pid) == 1:
			near.append(pid)
	if not near.is_empty() and randf() < 0.6:
		return String(near.pick_random())
	return String(any.pick_random()) if not any.is_empty() else best

## Los ingredientes (de la despensa) para esa poción, la de más potencia que entre en el caldero.
func bot_combo(want: String) -> Array:
	var ings := []
	for id in Data.INGREDIENT_ORDER:
		if Game.ingredient_unlocked(id) and int(Game.stock.get(id, 0)) > 0:
			ings.append(id)
	var best := []
	var best_p := -1
	var n := ings.size()
	for i in n:
		for j in range(i, n):
			var c := [ings[i], ings[j]]
			if _have(c):
				var r := Game.evaluate(c)
				if r.get("potion", "") == want and int(r["potency"]) > best_p:
					best = c
					best_p = int(r["potency"])
			if Game.cauldron_slots() >= 3 and kind == "concurso":
				for k in range(j, n):
					var c3 := [ings[i], ings[j], ings[k]]
					if _have(c3):
						var r3 := Game.evaluate(c3)
						if r3.get("potion", "") == want and int(r3["potency"]) > best_p:
							best = c3
							best_p = int(r3["potency"])
	return best

func _have(c: Array) -> bool:
	var need := {}
	for id in c:
		need[id] = int(need.get(id, 0)) + 1
	for id in need:
		if int(Game.stock.get(id, 0)) < int(need[id]):
			return false
	return true
