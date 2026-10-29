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

# --- R6 PERF: el principio del evento sin tirones ------------------------------------------------------------------
# main.gd (_ev_run_day) llama a prepare() y a warm_up() / warm_down() con la pantalla todavía en negro, antes del
# fundido de entrada. Antes, ella, la fila (o el jurado) y el HUD se armaban justo después del fundido, y la cuenta
# atrás, la primera poción, el humo del caldero o el confeti se dibujaban por primera vez a la vista: WebGL compila
# cada material nuevo la primera vez que lo dibuja (en la web, decenas o cientos de ms por shader) y Actor leía cada
# textura de vuelta desde la GPU. Ahora todo eso pasa en negro y la escena aparece ya completa.
var _prepared := false
var _keep: Array = []         # texturas que se usarán durante el evento, cargadas de antemano (se sueltan con el evento)
var _warm_state := {}

## Ella, la primera fila (o el jurado) y el HUD (antes lo hacía run() justo después del fundido de entrada).
func prepare() -> void:
	if _prepared:
		return
	_prepared = true
	var pt := PerfLog.t0()
	_prefill_heads()
	build_people()
	PerfLog.step("ev:build_people", pt)
	pt = PerfLog.t0()
	eui.show_hud(kind)
	eui.set_time(float(plan.get("time", 60)), float(plan.get("time", 60)))
	_update_hud()
	PerfLog.step("ev:show_hud", pt)

## Las caras de las tarjetas (event_ui._head: la fila, el tablero, el jurado) armadas con las filas de SpriteTops.HEAD,
## la misma regla que event_ui, pero sin get_image(): en la web cada cara nueva era un readPixels que espera a la GPU
## (~0,4 s cada uno con SwiftShader; 12 al empezar el evento). Si event_ui cambia su caché, esto no hace nada.
func _prefill_heads() -> void:
	var cache = eui.get("_head_cache") if is_instance_valid(eui) else null
	if not (cache is Dictionary):
		return
	var whos: Array = _pool.duplicate()
	whos.append_array(["alquimista", "anciano", "fizz"])
	for j in Events.JUDGES:
		whos.append(String(j["id"]))
	for r in rivals:
		whos.append(String(r.get("sprite", "")))
	for w in whos:
		if String(w) == "":
			continue
		var sid := Story.sprite_id(String(w))
		var path := "res://assets/chars/%s_idle.png" % sid
		if cache.has(sid) or not SpriteTops.HEAD.has(sid) or not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		var fw := tex.get_width() / 2
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((fw - 36) / 2, maxi(0, int(SpriteTops.HEAD[sid]) - 2), 36, 36)
		cache[sid] = at

## Lo que aparece más tarde se crea una vez a la vista de la cámara (con la pantalla en negro) para que se dibuje y se
## compile ahora: la poción que vuela, la barra de paciencia, el humo y los destellos del caldero, el confeti, las
## caritas, las letras grandes de la cuenta atrás, «+3 ★», la pizarra y las caras de las tarjetas. También carga las
## texturas y los cuadros de quienes pueden llegar a la fila. Devuelve lo que warm_down() quita.
## Con `tree`, va por partes: un cuadro entre una y otra (cada parte compila lo suyo en su cuadro; sin `tree`, todo de
## una vez). Lo ya creado se queda a la vista hasta warm_down().
func warm_up(tree: SceneTree = null) -> Array:
	var junk: Array = []
	_warm_t = PerfLog.t0()
	# los sprites de quienes pueden venir (cuadros y fila de la cabeza) y las texturas de pociones y caritas
	var ids: Array = []
	for w in _pool:
		ids.append(Story.sprite_id(String(w)))
	Actor.preload_ids(ids)
	for e in ["heart", "sweat", "note", "dots", "sparkle", "star", "excl", "question", "coin"]:
		if ResourceLoader.exists("res://assets/icons/emote_%s.png" % e):
			_keep.append(Actor.emote_texture(e))
	for pid in Data.POTIONS:
		var pp := "res://assets/icons/pot_%s.png" % pid
		if ResourceLoader.exists(pp):
			_keep.append(load(pp))
	# las caras de las tarjetas de la fila, del tema y del jurado (event_ui las recorta leyendo la textura de la GPU)
	if eui.has_method("_head"):
		var faces: Array = _pool.duplicate()
		for j in Events.JUDGES:
			faces.append(String(j["id"]))
		for r in rivals:
			faces.append(String(r.get("sprite", "")))
		for w in faces:
			if String(w) != "":
				eui.call("_head", String(w))
	await _warm_step(tree, "preload")
	if not is_instance_valid(scene) or not is_instance_valid(her):
		return junk
	var scene_had := _child_ids(scene)
	var pid := _warm_potion()
	# la poción que vuela y una barra de paciencia (sobre ella)
	var to: Actor = her
	if not line.is_empty() and is_instance_valid(line[0]["a"]):
		to = line[0]["a"]
	elif not judges.is_empty() and is_instance_valid(judges[0]):
		to = judges[0]
	_fly3d(pid, to)
	_make_bar({"a": her, "want": pid, "pat": 1.0, "pat_max": 1.0})
	await _warm_step(tree, "potion")
	if not is_instance_valid(scene) or not is_instance_valid(her):
		return junk
	# el humo, los destellos y la salpicadura del caldero (se esconden después: sus propios timers los borran)
	var cau = scene.get("cauldron")
	if cau is Cauldron:
		var cau_had := _child_ids(cau)
		(cau as Cauldron).brew_burst(Color(0.6, 0.9, 0.5))
		(cau as Cauldron).splash(Color(0.6, 0.9, 0.5))
		(cau as Cauldron)._flash = 0.0
		for c in cau.get_children():
			if not cau_had.has(c.get_instance_id()):
				_warm_state[c] = "hide"
	await _warm_step(tree, "cauldron")
	if not is_instance_valid(scene) or not is_instance_valid(her):
		return junk
	# el confeti del público (EventScenes) y una carita sobre ella
	if scene.has_method("warm_up"):
		scene.call("warm_up")
	her.emote("heart", 0.0)
	for c in scene.get_children():
		if not scene_had.has(c.get_instance_id()):
			junk.append(c)
	await _warm_step(tree, "scene")
	if not is_instance_valid(eui):
		return junk
	# el HUD: las letras grandes (cuenta atrás, «Time!»), «+3 ★» y la pizarra
	var big = eui.get("big")
	if big is Label:
		_warm_state["big"] = [big.text, big.modulate.a]
		big.text = "3 2 1 Go! Time! Done!"
		big.modulate.a = 1.0
	var root_had := _child_ids(eui.root)
	eui.pop("+0123456789 ★ time")
	for c in eui.root.get_children():
		if not root_had.has(c.get_instance_id()):
			junk.append(c)
	await _warm_step(tree, "hud_text")
	if not is_instance_valid(eui):
		return junk
	if kind == "concurso":
		var th: Array = themes
		round_i = 1
		themes = [Events.THEMES[0]]
		_set_board()
		round_i = 0
		themes = th
	else:
		_set_board()
	# las letras de la tarjeta del tema del concurso (Round 1 of 3 / “...”)
	if kind == "concurso":
		var layer := CanvasLayer.new()
		layer.layer = 7
		add_child(layer)
		var v := UIKit.vbox(6)
		v.add_child(PaperKit.head("Round 1 of 3", 40, Color("7a1d18"), HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(PaperKit.hand("“%s”" % String(Events.THEMES[0]["text"]), 66, EventUI.INK, true, HORIZONTAL_ALIGNMENT_CENTER))
		layer.add_child(v)
		junk.append(layer)
	PerfLog.step("ev:warm board", _warm_t)
	# --- R6 MERGE: las letras de la tarjeta del jurado (concurso) y de la de resultados (los tres), debajo del mapa
	# quieto, un grupo de tamaños por cuadro; warm_down() las quita (ver card_letter_groups)
	for g in card_letter_groups(kind):
		var lay := card_letter_layer(g)
		add_child(lay)
		junk.append(lay)
		await _warm_step(tree, "cards")
		if not is_instance_valid(eui):
			return junk
	# --- end R6 MERGE
	return junk

# --- R6 MERGE: las letras de las tarjetas que salen a mitad del evento. La primera tarjeta del jurado (event_ui
# show_jury: versalitas y manuscrita a varios tamaños) subía ~170 páginas de la caché de letras en un solo cuadro a la
# vista (1.5-2.4 s bloqueado con SwiftShader); la de resultados (show_results), lo mismo al final. La manuscrita
# (Caveat) cambia la forma de cada letra según sus vecinas: un abecedario no basta, van los textos de verdad.

## Los textos de las tarjetas a su letra y tamaño, en grupos (uno por cuadro): [[estilo, tamaño, texto], ...];
## estilo "head" (versalitas), "hand", "handb" (manuscrita, negrita), "wood" (botón de madera) o "ui" (Alegreya negrita:
## la tira de premios).
static func card_letter_groups(kind_: String) -> Array:
	var groups := []
	if kind_ == "concurso":
		var rounds := []
		var i := 0
		for th in Events.THEMES:
			rounds.append("Round %d · “%s”" % [i % 3 + 1, String(th["text"])])
			i += 1
		var names := []
		for j in Events.JUDGES:
			names.append(String(j["name"]))
		var said := ["“Nothing to taste…”"]
		for id in Events.JUDGE_LINES:
			for ln in Events.JUDGE_LINES[id]:
				said.append("“%s”" % String(ln))
		var pots := []
		for pid in Data.POTIONS:
			pots.append(Events.potion_name(String(pid)))
		var rivals_ := [ME_NAME, "· perfect stir"]
		for r in Events.RIVALS:
			rivals_.append(String(r["name"]))
		var fizz := ["+0123456789  ·  ★"]
		for k in Events.FIZZ_LINES:
			for ln in Events.FIZZ_LINES[k]:
				fizz.append("Fizz: “%s”" % String(ln))
		groups.append([["head", 38, "\n".join(rounds)], ["head", 30, "  ".join(names)], ["hand", 24, "guest judge  judge"],
			["hand", 27, "\n".join(said)]])
		groups.append([["handb", 36, "\n".join(pots)], ["handb", 34, "You presented nothing."], ["handb", 30, "\n".join(rivals_)],
			["hand", 28, "\n".join(fizz)], ["wood", 32, "Next round  See results"]])
	# la tarjeta de resultados
	var ends := []
	var info: Dictionary = Events.info(kind_)
	for m in (info.get("end", {}) as Dictionary):
		ends.append("“%s”" % String(info["end"][m]))
	var rows := ["Potions delivered  Points (stars)  Finished early", "Served  Walked out  Tips"]
	for k in 4:
		rows.append("%s  %s" % [UIKit.ordinal(k + 1), ME_NAME])
	groups.append([["head", 38, Events.ev_name(kind_, true)], ["handb", 58, "\n".join(Events.MEDAL_TITLE.values())]])
	groups.append([["hand", 30, "\n".join(ends)], ["hand", 32, "\n".join(rows)], ["handb", 36, "0123456789 / + ★"],
		["wood", 34, "Head home"], ["ui", 36, "+0123456789 -  Trophy"]])
	return groups

## Una capa debajo del mapa del viaje (15) con los textos de un grupo (a escala pequeña para que quepan en pantalla:
## la caché de letras va por tamaño de letra, no por la escala del nodo).
static func card_letter_layer(group: Array) -> CanvasLayer:
	var lay := CanvasLayer.new()
	lay.layer = 7
	var gv := UIKit.vbox(0)
	gv.scale = Vector2(0.4, 0.4)
	for it in group:
		var st := String(it[0])
		var sz := int(it[1])
		var tx := String(it[2])
		if st == "head":
			gv.add_child(PaperKit.head(tx, sz))
		elif st == "ui":
			gv.add_child(UIKit.label(tx, sz, UIKit.TEXT, UIKit.font_bold))
		elif st == "wood":
			var b := PaperKit.wood_button(tx, func(): pass, sz)
			b.disabled = true
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gv.add_child(b)
		else:
			gv.add_child(PaperKit.hand(tx, sz, EventUI.INK, st == "handb"))
	lay.add_child(gv)
	return lay
# --- end R6 MERGE

var _warm_t := 0

## Entre dos partes de warm_up(): anota lo que costó la parte y, con `tree`, espera al cuadro siguiente.
func _warm_step(tree: SceneTree, label: String) -> void:
	PerfLog.step("ev:warm " + label, _warm_t)
	if tree != null:
		await tree.process_frame
	_warm_t = PerfLog.t0()

## Quita lo de warm_up() y deja el HUD como estaba (la pizarra sale después de la anfitriona, como siempre).
func warm_down(junk: Array) -> void:
	for n in junk:
		if is_instance_valid(n):
			n.queue_free()
	for k in _warm_state:
		if is_instance_valid(k) and k is Node3D and _warm_state[k] == "hide":
			(k as Node3D).visible = false
			if k is GPUParticles3D:
				(k as GPUParticles3D).emitting = false
	var big = eui.get("big") if is_instance_valid(eui) else null
	if big is Label and _warm_state.has("big"):
		big.text = _warm_state["big"][0]
		big.modulate.a = _warm_state["big"][1]
	_warm_state.clear()
	if is_instance_valid(eui):
		eui.set_board("")
	if is_instance_valid(her):
		her.clear_emote()
	if is_instance_valid(scene) and scene.has_method("warm_down"):
		scene.call("warm_down")

## Si el evento se corta a mitad del precalentamiento (volver al título en esos pocos cuadros), el HUD queda como estaba.
func _exit_tree() -> void:
	if not _warm_state.is_empty():
		warm_down([])

func _child_ids(n: Node) -> Dictionary:
	var d := {}
	for c in n.get_children():
		d[c.get_instance_id()] = true
	return d

## Una poción que sale en este evento (para calentar su icono y sus materiales).
func _warm_potion() -> String:
	match kind:
		"academia":
			return String(plan.get("potion", "sueno_profundo"))
		"torneo":
			return Events.torneo_potion("vigor", tier)
	return "sueno_profundo"
# --- end R6 PERF

## El principio: la anfitriona habla, la cuenta atrás y a trabajar.
func run() -> void:
	prepare()   # --- R6 PERF: ella, la fila y el HUD (ya armados detrás del negro si main.gd llamó a prepare())
	var pt := PerfLog.t0()   # --- R6 PERF
	var host := String(Events.info(kind)["host_name"])
	main.ui.say(host, Events.line(kind, "intro", ev))
	PerfLog.step("ev:host_say", pt)   # --- R6 PERF
	await main.ui.dialog_advanced
	main.ui.hide_dialog()
	PerfLog.mark("ev:host_done")   # --- R6 PERF
	if kind == "concurso":
		await _run_concurso()
	else:
		_set_board()
		PerfLog.mark("ev:countdown")   # --- R6 PERF
		await eui.countdown()
		PerfLog.mark("ev:go")   # --- R6 PERF
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
	var pt := PerfLog.t0()   # --- R6 PERF
	if not main._brew_open():
		main.open_brew()
	eui.set_bench_button(false)
	PerfLog.step("ev:open_bench", pt)   # --- R6 PERF

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
	var pt := PerfLog.t0()   # --- R6 PERF
	if is_instance_valid(scene) and scene.has_method("cheer"):
		scene.call("cheer", good)
	PerfLog.step("ev:cheer", pt)   # --- R6 PERF

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
	var pt := PerfLog.t0()   # --- R6 PERF
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
	PerfLog.step("ev:spawn " + who, pt)   # --- R6 PERF

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
	PerfLog.mark("ev:fly3d " + pid)   # --- R6 PERF
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
	PerfLog.mark("ev:bottled " + pid)   # --- R6 PERF
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
