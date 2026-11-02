extends Node
class_name BenchDemo
## --- SS BENCH: las demos del banco, el regateo y la cápsula, y la prueba sin pantalla de las tres pantallas.
## main.gd las llama desde un bloque marcado "# --- SS BENCH" en _run_demo():
##   if BenchDemo.handles(_demo): <un fondo>; BenchDemo.run(self, _demo); return
## Demos (capturas con --shot / --frames, como las demás):
##   --demo=bench_radio | bench_bot | bench_thruster  [--step=diagnose|wrong|swap|patch|solder|test|result]
##   --demo=haggle_buy  [--step=open|counter|deal]     (el Raker vende una cápsula)
##   --demo=haggle_sell [--who=gorrum|zib|oona|pipip|rook|clatter] [--step=open|counter|deal|hover]
##   --demo=pod | pod_reveal [--step=closed|crack|open]
##   --pad: las ayudas como si se usara el mando
##   --demo=benchtest: sin pantalla, juega todo con los bots y revisa el contrato; "BENCHTEST ok fails=0", sale 0 / 1.
## --- SS2 BENCH: --demo=bench_jukebox | bench_navbox | bench_graded (la inspección) | bench_riddle (un acertijo de Old
##   Seven) | bench_favour (el pulidor de Buff) [--step=...] [--aids] (con las ayudas de todas las mejoras);
##   --demo=haggle_sell --who=singer | timekeeper | tracker --step=tell (las señales nuevas);
##   --demo=pod_wreck [--step=closed|crack|open] (el naufragio con su núcleo); benchtest cubre las 5 familias.
## Usa las pantallas de main (main.bench / main.haggle / main.pod_ui) si existen; si no, arma las suyas.

const JOBS := {
	"bench_radio": ["radio", "speaker", "zib", 11],
	"bench_bot": ["helperbot", "chip", "pipip", 23],
	"bench_thruster": ["thruster", "coil", "rook", 37],
	"bench_clatter": ["helperbot", "servo", "clatter", 41],   # --- SS MERGE: Clatter se arregla a sí mismo
	# --- SS2 BENCH
	"bench_jukebox": ["jukebox", "drum", "singer", 51],
	"bench_navbox": ["navbox", "gyro", "timekeeper", 53],
	"bench_graded": ["radio", "tuner", "inspector", 57],
	"bench_riddle": ["navbox", "needle", "hermit", 59],
	"bench_favour": ["helperbot", "servo", "rival", 61],
}
const AIDS_ALL := {"zone_k": 1.25, "pad_k": 1.4, "solder_add": 2.0, "sweep_k": 0.85}   # todas las mejoras del banco

var main: Node
var bench: BenchUI
var haggle: HaggleUI
var pod_ui: PodUI
var demo := ""
var step := ""
var _target_reached := false
var _fails: Array = []
var _checks := 0
var _last := {}
var _got := false

static func handles(d: String) -> bool:
	return d in ["bench_radio", "bench_bot", "bench_thruster", "bench_clatter", "haggle_buy", "haggle_sell", "pod", "pod_reveal", "benchtest",
		"bench_jukebox", "bench_navbox", "bench_graded", "bench_riddle", "bench_favour", "pod_wreck"]   # --- SS2 BENCH

static func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
		if a == "--" + name:
			return "1"
	return def

static func run(m: Node, d: String) -> void:
	var n := BenchDemo.new()
	n.name = "BenchDemo"
	m.add_child(n)
	n.start(m, d)

func start(m: Node, d: String) -> void:
	main = m
	demo = d
	step = arg("step", "")
	if arg("pad") != "":
		PadCursor.pad_in_use = true
	# la prueba usa pantallas propias: las de main.gd tienen conectado su flujo de relleno (al comprar abre la cápsula)
	_find_screens(demo != "benchtest")
	match demo:
		"benchtest":
			_benchtest()
		"bench_radio", "bench_bot", "bench_thruster", "bench_clatter", "bench_jukebox", "bench_navbox", "bench_graded", \
			"bench_riddle", "bench_favour":
			_demo_bench()
		"haggle_buy", "haggle_sell":
			_demo_haggle()
		"pod", "pod_reveal", "pod_wreck":
			_demo_pod()

func _find_screens(use_main := true) -> void:
	for n in (_all(main) if use_main else []):
		if n is BenchUI and bench == null:
			bench = n
		elif n is HaggleUI and haggle == null:
			haggle = n
		elif n is PodUI and pod_ui == null:
			pod_ui = n
	if bench and haggle and pod_ui:
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	if bench == null:
		bench = BenchUI.new()
		root.add_child(bench)
	if haggle == null:
		haggle = HaggleUI.new()
		root.add_child(haggle)
	if pod_ui == null:
		pod_ui = PodUI.new()
		root.add_child(pod_ui)

func _all(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out

# ------------------------------------------------------------------ demos con pantalla

func _demo_bench() -> void:
	var j: Array = JOBS[demo]
	var job := BenchData.make_job(j[0], j[1], j[2])
	job["seed"] = j[3]
	if Data.is_self_repair(String(j[2])):
		# --- SS MERGE: como lo arma main.gd en el mostrador
		job["self"] = true
		job["label"] = String(Data.SELF_REPAIR[j[2]].get("label", "Clatter"))
		job["sub"] = String(Data.SELF_REPAIR[j[2]].get("sub", "fixing himself"))
		job["symptom"] = Data.self_symptom(String(j[2]), String(j[1]))
	# --- SS2 BENCH: las claves nuevas del trabajo
	match demo:
		"bench_graded":
			job["graded"] = true
		"bench_riddle":
			job["riddle"] = true
		"bench_favour":
			var tw: Dictionary = CastData.CAST["rival"]["twist"]
			job["label"] = String(tw["label"])
			job["sub"] = String(tw["sub"])
			job["symptom"] = String(tw["symptom"])
			job["power"] = String(tw["power"])
	if arg("aids") != "":
		job["aids"] = AIDS_ALL.duplicate()
	if step == "patch":
		Game.parts.erase(j[1])
	elif not Game.has_part(j[1]):
		Game.add_part(j[1])
	bench.open(job)
	if step == "" or step == "open":
		return
	Engine.time_scale = 5.0     # hasta llegar al paso (las capturas bajo carga tardan menos cuadros)
	bench.demo_to("swap" if step == "patch" else ("result" if step == "power" else step))   # --- SS2 BENCH: power

func _demo_haggle() -> void:
	var d := {}
	if demo == "haggle_buy":
		var pod := _sample_pod()
		d = BenchData.make_deal("buy", "Salvage pod", "raker", int(pod["price"]), {"pod": pod, "seed": 5})
	else:
		var who := arg("who", "gorrum")
		var item: String = (Data.CAST.get(who, {}).get("buys", []) + ["radio"])[0]
		d = BenchData.make_deal("sell", BenchData.item_name(item), who, BenchData.sale_price(item, 2), {"item": item, "stars": 2, "seed": 5})
	haggle.open(d)
	if step != "" and step != "open":
		Engine.time_scale = 2.0
		haggle.demo_to(step)

func _demo_pod() -> void:
	if demo == "pod_wreck":
		# --- SS2 BENCH: el naufragio del día 7 (una brújula rota, 3 piezas y un núcleo de lámpara)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		pod_ui.open(BenchData.roll_pod_for(rng, "pod-707", BenchData.ITEM_ORDER, BenchData.PART_ORDER,
			{"kind": "wreck", "force_item": "navbox", "min_parts": 3, "core": true, "price": 40}))
		if step == "crack" or step == "open":
			pod_ui.demo_to(step)
		return
	pod_ui.open(_sample_pod())
	if step == "crack" or step == "open":
		pod_ui.demo_to(step)

func _sample_pod() -> Dictionary:
	return {"id": "pod-207", "weight": 3, "rattle": 2, "price": BenchData.POD_BASE + 3 * 3 + 2 * 2,   # (--- SS MERGE: el precio del balance)
		"contents": [{"part": "speaker"}, {"part": "coil"}, {"part": "lens"}, {"item": "helperbot", "fault": "servo"}]}

## Cuadros que se espera después de llegar al paso antes de sacar la captura (que se vean el globo, el brillo...).
const SETTLE := {"diagnose": 20, "wrong": 10, "swap": 4, "patch": 30, "solder": 2, "test": 2, "result": 24, "power": 22,
	"counter": 14, "deal": 12, "hover": 45, "tell": 8, "crack": 1, "open": 10, "closed": 20}

var _settle := 0

func _process(_d: float) -> void:
	if step == "" or step == "open" and demo.begins_with("bench_"):
		return
	if not _target_reached:
		var done := false
		if demo.begins_with("bench_") and bench:
			match step:
				"diagnose":
					done = bench.step == BenchUI.Step.DIAGNOSE and not bench._busy and bench._scope.mode != "idle"
				"wrong":
					done = bench.step == BenchUI.Step.DIAGNOSE and bench._wrong >= 1
				"swap", "patch":
					done = bench.step == BenchUI.Step.SWAP and not bench._busy
				"solder":
					done = bench.step == BenchUI.Step.SOLDER and bench._solder.lit() >= 2
				"test":
					done = bench.step == BenchUI.Step.TEST and bench._gauge._t > 1.1
				"result":
					done = bench.step == BenchUI.Step.RESULT
				"power":   # --- SS2 BENCH: el efecto al probarla (luces, estrellas, notas, llama)
					done = bench.step == BenchUI.Step.TEST and bench._power_line != ""
		elif demo.begins_with("haggle") and haggle:
			done = (step == "deal" and haggle._done) or (step == "counter" and haggle._round >= 1) or step == "hover" or \
				(step == "tell" and haggle.demo_ready)
		elif demo.begins_with("pod") and pod_ui:
			done = (step == "crack" and pod_ui._view.state == "opening" and pod_ui._view._t >= 1.12) or \
				(step == "open" and pod_ui._view.state == "done") or step == "closed"
		if done:
			_target_reached = true
			Engine.time_scale = 1.0
		return
	# capturas: con --shot, la demo la saca sola un rato después de llegar al paso (main.gd la saca en --frames)
	var shot := arg("shot")
	if shot == "" or _settle < 0:
		return
	_settle += 1
	if _settle >= int(SETTLE.get(step, 10)):
		_settle = -1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		print("SHOT ", shot, " (", demo, " ", step, ")")
		get_tree().quit(0)

# ------------------------------------------------------------------ la prueba sin pantalla

func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		print("BENCHTEST FAIL ", what)

func _on_result(r) -> void:
	_last = r if r is Dictionary else {"contents": r}
	_got = true

func _wait_result(ui, secs: float) -> bool:
	var t := 0.0
	while not _got and t < secs:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return _got and not ui.is_open()

func _benchtest() -> void:
	Engine.time_scale = 8.0
	var watchdog := get_tree().create_timer(240.0, true, false, true)
	watchdog.timeout.connect(func():
		print("BENCHTEST watchdog")
		get_tree().quit(2))
	bench.finished.connect(_on_result)
	haggle.finished.connect(_on_result)
	pod_ui.finished.connect(_on_result)
	_data_checks()
	# 1) el banco: las 12 fallas con repuesto (3 estrellas, la pieza usada), luego sin repuesto (parche)
	for item in BenchData.ITEM_ORDER:
		for fault in BenchData.FAULTS[item]:
			Game.new_game_state()
			Game.add_part(fault, 1)
			var before := Game.part_count(fault)
			var r := await _bench_run(BenchData.make_job(item, fault, "zib"), 1.0)
			_check(r.get("ok", false) and int(r.get("stars", -1)) == 3, "bench %s/%s: 3 estrellas con skill 1 (%s)" % [item, fault, str(r)])
			_check(r.get("fault_found", false) and not r.get("patched", true), "bench %s/%s: encontrada, sin parche" % [item, fault])
			_check(r.get("parts_used", []) == [fault] and Game.part_count(fault) == before - 1, "bench %s/%s: take_part una vez" % [item, fault])
			_check(r.has_all(["ok", "stars", "time", "fault_found", "patched", "parts_used"]), "bench %s/%s: claves del contrato" % [item, fault])
	for item in BenchData.ITEM_ORDER:
		Game.new_game_state()
		Game.parts.clear()
		var fault: String = BenchData.FAULTS[item].keys()[1]
		var r := await _bench_run(BenchData.make_job(item, fault, "rook"), 1.0)
		_check(r.get("ok", false) and r.get("patched", false) and r.get("parts_used", ["x"]).is_empty() and int(r.get("stars", -1)) == 2,
			"bench %s sin repuesto: parche, 2 estrellas (%s)" % [item, str(r)])
	# un bot torpe: menos estrellas
	Game.new_game_state()
	var worst := 3
	for i in 4:
		Game.add_part("tuner", 1)
		var r2 := await _bench_run(BenchData.make_job("radio", "tuner", "gorrum"), 0.2)
		_check(r2.get("ok", false), "bench torpe termina")
		worst = mini(worst, int(r2.get("stars", 3)))
	_check(worst <= 2, "bench torpe: alguna vez menos de 3 estrellas (peor %d)" % worst)
	# 2) el banco con el teclado: T (la mejor del bot), la tecla del zócalo, E (cambiar), soldador automático,
	#    Espacio en el verde, Intro (listo)
	Game.new_game_state()
	Game.add_part("lens", 1)
	_got = false
	bench.open(BenchData.make_job("helperbot", "lens", "pipip"))
	await _sleep(0.6)
	_key(KEY_T)
	await _sleep(0.8)
	_check(bench._scope.mode == "tap" and bool(bench._scope.data.get("clear", false)), "teclado: T usa TAP (pista clara en el bot)")
	_key(KEY_1)
	await _sleep(0.6)
	_check(bench._wrong == 1, "teclado: 1 = pieza equivocada (servo)")
	_key(KEY_3)
	await _until(func(): return bench.step == BenchUI.Step.SWAP and not bench._busy, 5.0)
	_key(KEY_E)
	await _until(func(): return bench.step == BenchUI.Step.SOLDER and not bench._busy, 5.0)
	_check(bench._parts_used == ["lens"], "teclado: E cambia la pieza")
	bench._solder.auto_until = 1.0
	await _until(func(): return bench.step == BenchUI.Step.TEST and bench._gauge._t > 0.7, 15.0)
	await _until(func(): return absf(bench._gauge._u - bench._gauge.zone_c) < 0.06, 6.0)
	_key(KEY_SPACE)
	await _until(func(): return bench.step == BenchUI.Step.RESULT, 8.0)
	_key(KEY_ENTER)
	var ok := await _wait_result(bench, 3.0)
	_check(ok and _last.get("ok", false) and int(_last.get("wrong", 0)) == 1 and int(_last.get("stars", 0)) >= 2,
		"teclado: reparación completa con 1 error (%s)" % str(_last))
	# 3) rendirse con Esc dos veces; cerrar sin señal
	_got = false
	bench.open(BenchData.make_job("thruster", "fan", "rook"))
	await _sleep(0.3)
	_key(KEY_ESCAPE)
	await _sleep(0.2)
	_check(bench._confirm and bench.is_open(), "Esc pide confirmación")
	_key(KEY_ESCAPE)
	ok = await _wait_result(bench, 2.0)
	_check(ok and not _last.get("ok", true), "Esc Esc = rendirse (ok false)")
	_got = false
	bench.open(BenchData.make_job("radio", "chip", "oona"))
	bench.bot_play()
	await _sleep(0.6)
	bench.close_now()
	await _sleep(2.0)
	_check(not _got and not bench.is_open(), "close_now cierra sin finished (y corta el bot)")
	# 4) el regateo: todas las especies en los dos modos, con el bot
	for who in ["gorrum", "zib", "oona", "pipip", "rook", "clatter", "raker", "mags"]:
		for mode in ["buy", "sell"]:
			Game.new_game_state()
			_got = false
			haggle.open(BenchData.make_deal(mode, "Street radio", who, 50))
			haggle.bot_play()
			ok = await _wait_result(haggle, 12.0)
			_check(ok and _last.has_all(["deal", "price", "mood"]), "haggle %s/%s: contrato (%s)" % [who, mode, str(_last)])
			if ok and _last.get("deal", false) and not _last.has("barter"):
				var p := int(_last["price"])
				_check(p > 20 and p < 90, "haggle %s/%s: precio razonable %d" % [who, mode, p])
	# el Hornback se ofende con un sí rápido
	_got = false
	haggle.open(BenchData.make_deal("sell", "Hoverbike thruster", "gorrum", 60, {"seed": 3}))
	var offer := haggle._price
	await _sleep(0.2)
	_key(KEY_ENTER)
	ok = await _wait_result(haggle, 4.0)
	_check(ok and _last.get("deal", false) and int(_last["price"]) < offer, "Hornback: sí rápido = peor precio (%d < %d)" % [int(_last.get("price", 0)), offer])
	# Oona: trueque (tecla 1)
	_got = false
	haggle.open(BenchData.make_deal("sell", "Street radio", "oona", 44, {"seed": 4}))
	await _sleep(0.2)
	_check(haggle._barter != "", "Oona ofrece trueque")
	_key(KEY_1)
	ok = await _wait_result(haggle, 4.0)
	_check(ok and _last.get("deal", false) and _last.has("barter") and int(_last.get("barter_n", 0)) >= 1 and int(_last["price"]) == 0,
		"trueque: barter + barter_n, price 0 (%s)" % str(_last))
	# Quill: propina por rapidez (una contraoferta que acepta enseguida)
	_got = false
	haggle.open(BenchData.make_deal("sell", "Street radio", "zib", 44, {"seed": 6}))
	await _sleep(0.2)
	_key(KEY_1)
	ok = await _wait_result(haggle, 4.0)
	if ok and _last.get("deal", false):
		_check(int(_last.get("tip", 0)) > 0, "Quill: propina por trato rápido")
	# Rook: si nadie hace nada, despega (sin trato)
	_got = false
	haggle.open(BenchData.make_deal("sell", "Hoverbike thruster", "rook", 60))
	ok = await _wait_result(haggle, 40.0)
	_check(ok and not _last.get("deal", true), "Rook: el despegue lo lleva (sin trato)")
	# Clatter: dice el presupuesto y nunca paga más
	_got = false
	haggle.open(BenchData.make_deal("sell", "Pocket helper bot", "clatter", 60, {"seed": 8}))
	var budget := floori(haggle._limit)
	await _sleep(0.2)
	_key(KEY_3)
	await _sleep(0.7)
	_key(KEY_ENTER)
	ok = await _wait_result(haggle, 4.0)
	_check(ok and int(_last.get("price", 999)) <= budget, "Clatter: nunca más que el presupuesto (%d <= %d)" % [int(_last.get("price", 0)), budget])
	# ...y FAIR (tecla 2) es justo el presupuesto que dijo: lo paga
	_got = false
	haggle.open(BenchData.make_deal("sell", "Pocket helper bot", "clatter", 60, {"seed": 8}))
	budget = floori(haggle._limit)
	await _sleep(0.2)
	_key(KEY_2)
	ok = await _wait_result(haggle, 4.0)
	_check(ok and _last.get("deal", false) and int(_last.get("price", 0)) == budget, "Clatter: FAIR = el presupuesto (%d == %d)" % [int(_last.get("price", 0)), budget])
	# 5) la cápsula
	for s in [1, 2, 3, 7]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var pod := BenchData.roll_pod(rng)
		_got = false
		pod_ui.open(pod)
		pod_ui.bot_play()
		ok = await _wait_result(pod_ui, 6.0)
		_check(ok and _last.get("contents", []) == pod["contents"], "pod %d: devuelve el contenido" % s)
	_got = false
	pod_ui.open({"id": "pod_x", "weight": 2, "rattle": 0, "price": 30})
	await _sleep(0.2)
	_key(KEY_SPACE)
	await _sleep(3.0)
	_key(KEY_E)
	ok = await _wait_result(pod_ui, 3.0)
	_check(ok and _last.get("contents", []).size() >= 2, "pod sin contenido: se sortea al abrir; teclado Espacio / E")
	await _ss2_tests()   # --- SS2 BENCH
	Engine.time_scale = 1.0
	print("BENCHTEST %s checks=%d fails=%d %s" % ["ok" if _fails.is_empty() else "FAIL", _checks, _fails.size(), str(_fails)])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _bench_run(job: Dictionary, skill: float) -> Dictionary:
	_got = false
	bench.open(job)
	bench.bot_play(skill)
	var ok := await _wait_result(bench, 30.0)
	if not ok:
		_check(false, "bench %s/%s: el bot no terminó" % [job["item"], job["fault"]])
		bench.close_now()
		return {}
	return _last

func _data_checks() -> void:
	for item in BenchData.ITEM_ORDER:
		var slots: Array = BenchData.ITEMS[item]["slots"]
		_check(slots.size() == 4, "%s: 4 zócalos" % item)
		for fault in BenchData.FAULTS[item]:
			var decoys := []
			for t in BenchData.TOOL_ORDER:
				var c := BenchData.clue(item, fault, t, 5)
				var clear: bool = String(t) == BenchData.best_tool(item)
				_check(bool(c["clear"]) == clear, "clue %s/%s/%s: clara solo con la mejor" % [item, fault, t])
				_check(String(c["text"]) != "", "clue %s/%s/%s: texto" % [item, fault, t])
				var strong := 0
				for v in c["strength"]:
					if float(v) > 0.01:
						strong += 1
				_check(strong == (1 if clear else 2), "clue %s/%s/%s: %d candidatos" % [item, fault, t, strong])
				if not clear:
					decoys.append(int(c["decoy"]))
			_check(decoys.size() == 2 and decoys[0] != decoys[1], "clue %s/%s: señuelos distintos %s" % [item, fault, str(decoys)])
	for sp in BenchData.HAGGLE:
		for key in ["open_sell", "reject", "accept", "final", "walk"]:
			_check(BenchData.haggle_line(sp, key, [10, 12]) != "", "línea %s/%s" % [sp, key])
	_check(BenchData.stars_for(3.0) == 3 and BenchData.stars_for(2.0) == 2 and BenchData.stars_for(1.0) == 1 and BenchData.stars_for(0.2) == 0, "stars_for")

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

func _sleep(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return bool(cond.call())

# ------------------------------------------------------------------ --- SS2 BENCH: la temporada

func _ss2_tests() -> void:
	# los datos nuevos
	_check(BenchData.ITEM_ORDER.size() == 5 and BenchData.PART_ORDER.size() == 13, "5 familias y 13 piezas")
	for item in BenchData.ITEM_ORDER:
		_check(BenchData.ITEMS[item].has("power_fx"), "%s: power_fx" % item)
		_check(ResourceLoader.exists("res://assets/items/%s_closed.png" % item) and ResourceLoader.exists("res://assets/items/%s_open_empty.png" % item),
			"%s: arte cerrado y abierto" % item)
		for f in BenchData.FAULTS[item]:
			_check((BenchData.SYMPTOM_LINES[item][f] as Array).size() == 3, "%s/%s: 3 síntomas" % [item, f])
	for p in BenchData.PART_ORDER:
		_check(ResourceLoader.exists("res://assets/parts/%s.png" % p) and ResourceLoader.exists("res://assets/parts/%s_bad.png" % p), "arte de la pieza %s" % p)
	_check(ResourceLoader.exists("res://assets/items/lamp_core.png"), "arte del núcleo de lámpara")
	_check(ResourceLoader.exists("res://assets/icons/emote_zz.png"), "emote_zz")
	_check(BenchData.clue("jukebox", "speaker", "tap", 1)["text"] == "The horn speaker buzzes when thumped.", "pista por familia (rocola: parlante)")
	_check(BenchData.clue("navbox", "chip", "listen", 1)["wave"] == "chirr" and BenchData.clue("radio", "chip", "listen", 1)["wave"] == "reverse",
		"onda por familia (chip de la brújula = chirr)")
	_check(BenchData.clue("navbox", "gyro", "listen", 1)["wave"] == "wobble" and BenchData.clue("navbox", "needle", "listen", 1)["wave"] == "tick",
		"ondas del giroscopio y la aguja")
	var prices := []
	for it in BenchData.ITEM_ORDER:
		prices.append(BenchData.asis_price(it))
	_check(prices == [14, 16, 18, 20, 23], "precios as-is %s" % str(prices))
	_check(BenchData.content_name({"core": true}) == "Lamp core", "content_name del núcleo")
	_check(BenchData.haggle_rules_for("singer").get("rule", "") == "generic" and BenchData.haggle_rules_for("singer")["key"] == "lampwing",
		"haggle_rules_for: Lune = lampwing genérica")
	_check(BenchData.haggle_rules_for("gorrum").get("rule", "") == "insulted_by_quick_yes", "haggle_rules_for: Gorrum = hornback")
	for it in ["radio", "navbox"]:
		for f in BenchData.FAULTS[it]:
			_check(BenchData.riddle(it, f) != "", "acertijo %s/%s" % [it, f])
	for who in CastData.CAST:
		var row: Dictionary = CastData.CAST[who]
		_check(Data.SPECIES.has(row["species"]) or CastData.SPECIES.has(row["species"]), "especie de %s" % who)
		_check(ResourceLoader.exists("res://assets/chars/%s_idle.png" % who) and ResourceLoader.exists("res://assets/chars/%s_walk.png" % who), "hoja de %s" % who)
		if who in CastData.NEW_CUSTOMERS or who in CastData.P1_CUSTOMERS:
			var ln: Dictionary = CastData.LINES.get(who, {})
			for k in ["bring", "buy", "failed", "angry", "decline", "sold", "nodeal", "none", "full", "home"]:
				_check(ln.has(k), "frase %s de %s" % [k, who])
			_check((ln.get("thanks", []) as Array).size() == 4, "4 gracias de %s" % who)
			for it in row["brings"]:
				_check((ln.get("bring", {}) as Dictionary).has(it), "bring %s de %s" % [it, who])
	_check(_ip_scan().is_empty(), "palabras prohibidas en CastData / BenchData: %s" % str(_ip_scan()))
	# cápsulas de la temporada
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wreck := BenchData.roll_pod_for(rng, "w", BenchData.ITEM_ORDER, BenchData.PART_ORDER,
		{"kind": "wreck", "force_item": "navbox", "min_parts": 3, "core": true, "price": 40})
	var has_core := false
	var has_nav := false
	for c in wreck["contents"]:
		has_core = has_core or c.has("core")
		has_nav = has_nav or String(c.get("item", "")) == "navbox"
	_check(wreck["contents"].size() == 5 and has_core and has_nav and wreck["weight"] == 3 and wreck["rattle"] == 2 and wreck["price"] == 40 and wreck["kind"] == "wreck",
		"naufragio: brújula + 3 piezas + núcleo (%s)" % str(wreck))
	var locked_ok := true
	for i in 30:
		var pd := BenchData.roll_pod_for(rng, "", ["radio"], ["cell", "tuner"], {})
		for c in pd["contents"]:
			if c.has("part") and not String(c["part"]) in ["cell", "tuner"]:
				locked_ok = false
			if c.has("item") and String(c["item"]) != "radio":
				locked_ok = false
	_check(locked_ok, "roll_pod_for: solo familias y piezas desbloqueadas")
	var ch := BenchData.roll_pod_for(rng, "", [], [], {"kind": "charity"})
	_check(int(ch["price"]) == 0 and ch["kind"] == "charity", "cápsula de regalo: precio 0")
	_got = false
	pod_ui.open(wreck)
	pod_ui.bot_play()
	var ok := await _wait_result(pod_ui, 8.0)
	_check(ok and _last.get("contents", []) == wreck["contents"], "PodUI: el naufragio (5 cosas, núcleo) vuelve igual")
	# el banco: calificado, ayudas, acertijo, label ajeno
	Game.new_game_state()
	Game.add_part("tuner", 1)
	var job := BenchData.make_job("radio", "tuner", "inspector")
	job["graded"] = true
	job["aids"] = AIDS_ALL.duplicate()
	_got = false
	bench.open(job)
	_check(bench._stamp.visible, "graded: el sello se ve")
	bench.bot_play(1.0)
	await _until(func(): return bench.step == BenchUI.Step.SOLDER, 10.0)
	_check(is_equal_approx(bench._solder.time_limit, 2.2 + 1.6 * 3 + 2.0) and is_equal_approx(bench._solder.hit_r, BenchSolder.HIT_R * 1.4),
		"aids: soldadura +2 s y puntos x1.4 (%s, %s)" % [bench._solder.time_limit, bench._solder.hit_r])
	await _until(func(): return bench.step == BenchUI.Step.TEST, 15.0)
	_check(is_equal_approx(bench._gauge.zone_w, 0.24 * 1.25) and is_equal_approx(bench._gauge.speed, 0.8 * 0.85),
		"aids: zona verde x1.25 y aguja x0.85 (%s, %s)" % [bench._gauge.zone_w, bench._gauge.speed])
	ok = await _wait_result(bench, 20.0)
	_check(ok and _last.get("graded", false) and int(_last.get("stars", 0)) == 3, "graded: el resultado lo dice (%s)" % str(_last))
	Game.add_part("needle", 1)
	job = BenchData.make_job("navbox", "needle", "hermit")
	job["riddle"] = true
	_got = false
	bench.open(job)
	_check(bench._ticket_hdr.text == "A RIDDLE" and BenchData.riddle("navbox", "needle") in bench._ticket_txt.text, "riddle: la nota es el acertijo")
	_check(not bench._stamp.visible, "sin graded: sin sello")
	bench._use_tool("listen")
	_check(bool(bench._scope.data.get("clear", false)) and int(bench._scope.data.get("fault", -1)) == 1, "riddle: LISTEN dice la verdad")
	bench.close_now()
	var fj := BenchData.make_job("helperbot", "servo", "rival")
	var tw: Dictionary = CastData.CAST["rival"]["twist"]
	fj["label"] = tw["label"]
	fj["sub"] = tw["sub"]
	fj["power"] = tw["power"]
	_got = false
	bench.open(fj)
	_check(bench._head_item.text == "Buff's buffer" and not bench._talks(), "favor: el label y la cosa no habla")
	bench.bot_play(1.0)
	ok = await _wait_result(bench, 20.0)
	_check(ok and _last.get("ok", false), "favor: termina")
	# el regateo: las señales nuevas
	for who in ["singer", "timekeeper", "tracker", "farmer"]:
		var fxn := String(BenchData.haggle_rules_for(who).get("tell_fx", ""))
		var kk := KEY_3
		var seen := false
		for attempt in 4:
			Game.new_game_state()
			_got = false
			haggle.open(BenchData.make_deal("sell", "Song box", who, 50, {"seed": 20 + attempt}))
			_check(haggle._sp == BenchData.haggle_key_for(who), "%s: clave de regateo %s" % [who, haggle._sp])
			await _sleep(0.2)
			for i in 3:
				if haggle._done:
					break
				_key(kk)
				await _sleep(0.5)
				if haggle._portrait.last_fx == fxn:
					seen = true
					break
			if not haggle._done:
				haggle._walk_away()
			ok = await _wait_result(haggle, 4.0)
			if seen:
				break
		_check(seen, "%s: la señal %s se ve" % [who, fxn])
		_got = false
		haggle.open(BenchData.make_deal("sell", "Song box", who, 50))
		haggle.bot_play()
		ok = await _wait_result(haggle, 12.0)
		_check(ok and _last.has_all(["deal", "price", "mood"]), "%s: el bot regatea (%s)" % [who, str(_last)])

## Las palabras del §10.3 (palabras enteras, sin mayúsculas) en los textos del elenco nuevo y del banco.
func _ip_scan() -> Array:
	var words := ["droid", "jedi", "sith", "lightsaber", "blaster", "tatooine", "mos", "jawa", "tusken", "raider", "sandcrawler",
		"podrace", "podracer", "speeder", "landspeeder", "swoop", "vaporator", "cantina", "hutt", "wookiee", "ewok", "gungan",
		"holonet", "holocron", "hologram", "hyperspace", "hyperdrive", "lightspeed", "parsec", "repulsor", "spice", "sabacc",
		"kessel", "corellian", "mandalorian", "mando", "coruscant", "naboo", "endor", "hoth", "dagobah", "jakku", "skywalker",
		"kenobi", "falcon", "senate", "empire", "imperial", "rebel", "rebels", "republic", "moff", "trooper", "bounty",
		"astromech", "bacta", "carbonite", "kyber", "beskar", "nerf", "bantha", "dewback", "krayt", "mynock", "porg",
		"concord", "hammerhead", "bellwether", "hitchhiker", "saltmarch", "saltmarsh", "dustline", "lumi", "fennick",
		"collector", "42"]
	var strs := []
	for d in [CastData.CAST, CastData.LINES, CastData.RIDDLES, CastData.HAGGLE, CastData.HAGGLE_LINES, CastData.SPECIES,
			BenchData.ITEMS, BenchData.PARTS, BenchData.SYMPTOM_LINES, BenchData.TOOL_CLUES, BenchData.TOOL_CLUES_BY_ITEM]:
		_strings_of(d, strs)
	var blob := " ".join(strs).to_lower()
	var rx := RegEx.new()
	rx.compile("[a-z0-9-]+")
	var seen := {}
	for m in rx.search_all(blob):
		seen[m.get_string()] = true
	var out := []
	for w in words:
		if seen.has(w):
			out.append(w)
	for phrase in ["sand people", "moisture farm", "x-wing", "tie fighter", "death star", "star destroyer", "outer rim",
			"core worlds", "wild space", "protocol bot", "power converter", "womp rat", "fix-it", "inner rim", "mid rim"]:
		if blob.find(phrase) >= 0:
			out.append(phrase)
	if " ".join(strs).contains("Force"):
		out.append("Force")
	return out

## Solo los textos (los números de los datos no cuentan: "42" es el precio base del propulsor).
func _strings_of(v, out: Array) -> void:
	if v is String:
		out.append(v)
	elif v is Dictionary:
		for k in v:
			_strings_of(v[k], out)
	elif v is Array:
		for e in v:
			_strings_of(e, out)
# --- end SS2 BENCH
