extends Node
class_name DemoKit
## --- SS CORE: las demos (capturas a 1280x720 de cada pantalla) y las pruebas sin pantalla. main.gd la crea con
## --demo=<nombre> y le pasa a sí mismo (m). Patrón de Midnight Cauldron: --shot=<png> --frames=<n> guarda la imagen
## y sale; --days=<n> para el bot.
##   pantallas:  title, intro, market (día 2, Raker habla), market_door ("[E] Open shop"), parts (el puesto de Mags),
##               pods (la elección de cápsula), shop (la fila de 4 + alguien en el mostrador + "[E] Repair"),
##               shop_pad (lo mismo con el mando: "(A) Repair"), counter (el diálogo de una reparación), sell (el de una
##               compra), walk, tea (Kettle sirve té), drawer, shelf, menu, bench / haggle / pod (las pantallas de
##               BENCH sobre la tienda), closing_time (las 6 PM), ledger (el libro de cuentas de noche), closing
##               (la pantalla final, cuota pagada), closing_short (no alcanzó)
##   pruebas:    savetest, smoke, autoplay (el bot juega los 3 días por el flujo real: título, introducción, mañana,
##               regateo, cápsula, Mags, abrir, mostrador, banco, ventas, té, reacondicionar, cierre, libro de
##               cuentas, pantalla final; cuenta los errores del contrato y del flujo).

var m   # main.gd
var _rng := RandomNumberGenerator.new()
## --pace=real: el bot tarda como una persona en cada pantalla de BENCH (antes de su bot_play): así se prueban la
## fila, la paciencia y el té con el tiempo real de una reparación (20-40 s). Por defecto (--pace=fast) no espera.
var pace := "fast"
const PACE_REAL := {"bench": 30.0, "haggle": 7.0, "pod": 3.0}
## --- SS MERGE: perfiles de jugador para el balance (--bot=perfect | good | sloppy; por defecto perfect = el bot de
## CORE, sin esperas). wait: segundos (de juego) que "piensa" en cada pantalla antes de su bot_play (más los ~8-10 s
## del propio bot en el banco); skill: lo que se le pasa a bot_play (banco: piezas equivocadas, soldadura torcida,
## aguja corrida; regateo: aceptar enseguida); react: lo que tarda en ir al mostrador cuando alguien espera;
## tea / parts / refurb: si usa el té de Kettle, si compra piezas a Mags y si reacondiciona lo roto; pods: "best"
## (la más pesada que alcance) | "first" (la primera, a lo que pida) | "none".
##   good   = una persona que entendió el juego: ~25-30 s por reparación, casi siempre 3 estrellas, regatea.
##   sloppy = una persona distraída: ~40-45 s por reparación, se equivoca de pieza, suelda torcido, acepta el primer
##            precio, no usa el té ni compra piezas.
const PROFILES := {
	"perfect": {"wait": {"bench": 0.0, "haggle": 0.0, "pod": 0.0}, "skill": {"bench": 1.0, "haggle": 1.0},
		"react": 0.0, "tea": true, "parts": true, "refurb": true, "pods": "best"},
	"good": {"wait": {"bench": 17.0, "haggle": 6.0, "pod": 3.0}, "skill": {"bench": 0.85, "haggle": 0.9},
		"react": 2.0, "tea": true, "parts": true, "refurb": true, "pods": "best"},
	"sloppy": {"wait": {"bench": 31.0, "haggle": 9.0, "pod": 4.0}, "skill": {"bench": 0.45, "haggle": 0.35},
		"react": 5.0, "tea": false, "parts": false, "refurb": true, "pods": "first"},
}
var bot := "perfect"
var prof: Dictionary = PROFILES["perfect"]
# --- end SS MERGE

func run(main, name: String) -> void:
	m = main
	_rng.seed = 2207
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pace="):
			pace = a.substr(7)
		elif a.begins_with("--bot=") and PROFILES.has(a.substr(6)):   # --- SS MERGE
			bot = a.substr(6)
			prof = PROFILES[bot]
		elif a.begins_with("--seed="):
			_rng.seed = int(a.substr(7))
			seed(int(a.substr(7)))
	match name:
		"title":
			m.show_title()
		"intro":
			Game.new_game_state()
			m.show_intro()
		"market":
			_state(2)
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["pods"]["x"] - 0.2, 1)
			m.street.snap_camera()
		"tutorial":
			# el primer día: el consejo de caminar y comprar (etiqueta de papel bajo la placa)
			_state(1)
			m.begin_morning()
		"first_customer":
			# el primer cliente del día 1 entra y llega al mostrador (el reloj espera: tutorial)
			_state(1)
			m.open_shop_now()
		"settings":
			Game.new_game_state()
			m.show_title()
			await _wait(0.3)
			m._on_title_choice("settings")
		"market_door":
			_state(1)
			Game.tips_seen["walk"] = true
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["door"]["x"] + 0.3, -1)
			m.street.snap_camera()
		"parts":
			_state(2)
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["parts"]["x"], 1)
			m.street.snap_camera()
			await _wait(0.4)
			m.parts_stall()
		"pods":
			_state(1)
			Game.tips_seen["walk"] = true
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["pods"]["x"], 1)
			m.street.snap_camera()
			await _wait(0.4)
			m.pods_stall()
		"shop", "shop_pad":
			if name == "shop_pad":
				PadCursor.pad_in_use = true
			_shop_scene()
		"counter":
			_shop_scene()
			await _wait(0.6)
			m.use_counter()
		"sell":
			_shop_scene({"who": "oona", "kind": "buy", "wants": ["radio"]})
			await _wait(0.6)
			m.use_counter()
		"counter_clatter":
			# --- SS MERGE: Clatter viene a que lo arreglen a él (sin cosa en el mostrador)
			_shop_scene({"who": "clatter", "kind": "repair", "item": "helperbot", "fault": "servo"})
			await _wait(0.6)
			m.use_counter()
		"walk":
			_shop_scene()
			m.shop.walker.teleport(ShopWorld.STATIONS["tea"]["x"], 1)
			m.shop.snap_camera()
			m.shop.walker.go_to(-1.0)
		"tea":
			_shop_scene()
			await _wait(0.3)
			m.use_tea()
		"drawer":
			_shop_scene()
			m.shop.walker.teleport(ShopWorld.STATIONS["drawer"]["x"], -1)
			m.show_drawer()
		"shelf":
			_shop_scene()
			m.shop.walker.teleport(ShopWorld.STATIONS["shelf"]["x"], -1)
			m.show_shelf()
		"menu":
			_shop_scene()
			await _wait(0.3)
			m.open_menu()
		"bench":
			_shop_scene()
			m.shop.walker.teleport(ShopWorld.STATIONS["bench"]["x"], -1)
			m.bench.open(BenchData.make_job("radio", "speaker", "gorrum"))
		"haggle":
			_shop_scene({"who": "zib", "kind": "buy", "wants": ["radio"]})
			var deal := BenchData.make_deal("sell", "Street radio", "zib", BenchData.sale_price("radio", 2))
			deal["item"] = "radio"
			deal["stars"] = 2
			m.haggle.open(deal)
		"pod":
			_state(1)
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["pods"]["x"], 1)
			m.pod_ui.open(Game.pods_today[0])
		"closing_time":
			_shop_scene()
			m.day.shop_t = Data.DAY_SECONDS - 0.5
		"ledger":
			_state(2)
			Game.credits = 236    # 140 por la mañana + 150 - 54: los números del libro cuadran (--- SS MERGE: el balance)
			Game.rep = 18         # 10 + 8 de hoy
			_fake_day({"customers": 7, "arrived": 8, "repairs": 5, "stars": 13, "sales": 2, "walkouts": 1, "patience_lost": 1,
				"parts_used": 4, "refurbished": 1, "tips": 4, "pods": 2, "repair_pay": 86, "sale_pay": 60}, 150, 54, 8)
			m.open_shop_now()
			m.day.clear()
			m.show_night()
		"closing", "closing_short":
			_state(3)
			var paid := name == "closing"
			_fake_history(paid)
			m.show_closing()
		"night":
			_state(1)
			m.show_night()
			m.screens.hide_all()
		"market_wide":
			# (revisión del decorado) la calle desde más lejos: plataformas, naves, el anillo
			_state(2)
			m.begin_morning()
			m.hud.show_top(false)
			m.street.walker.teleport(-2.6, 1)   # --- SS SHIP: Nell en la calle, entre su puerta y las cápsulas (sin aviso que tape el cartel)
			m.street.cam_fixed = true
			m.street.camera.position = Vector3(0.0, 7.0, 22.0)
			m.street.camera.look_at(Vector3(0.0, 4.0, -20.0), Vector3.UP)
		"savetest":
			_savetest()
		"smoke":
			_smoke()
		"autoplay":
			_autoplay()
		_:
			push_warning("demo desconocida: %s" % name)
			m.show_title()

# ------------------------------------------------------------------ escenas preparadas

## Una partida en el día dado, con algo en el cajón, en el estante y una cosa rota.
func _state(day: int) -> void:
	Game.new_game_state()
	Game.day = day
	Game.intro_seen = true
	Game.credits = [0, Data.START_CREDITS, 140, 236][clampi(day, 0, 3)]   # (--- SS MERGE: los números del balance)
	Game.rep = [0, 0, 10, 19][clampi(day, 0, 3)]
	Game.sign_points = maxi(0, day - 1)
	for t in Data.TIPS:
		if day > 1:
			Game.tips_seen[t] = true
	if day > 1:
		Game.tips_seen["first_done"] = true
		Game.add_part("chip", 1)
		Game.add_part("fan", 1)
		Game.shelf_add("helperbot", 3)
		Game.shelf_add("thruster", 1)
		Game.add_junk("radio", "tuner")
	Game.reset_today()
	Game.roll_pods()

## La tienda abierta (día 2, sin tutorial) con 4 en la fila y alguien en el mostrador; Nell en el mostrador.
func _shop_scene(at_counter := {"who": "gorrum", "kind": "repair", "item": "radio", "fault": "speaker"}) -> void:
	_state(2)
	m.open_shop_now()
	m.day.clear()
	m.day.running = true
	m.day.shop_t = 112.0
	var line := []
	for e in [{"who": "zib", "kind": "buy", "wants": ["radio"], "p": 0.42}, {"who": "oona", "kind": "repair", "item": "radio", "fault": "tuner", "p": 0.86},
			{"who": "pipip", "kind": "repair", "item": "helperbot", "fault": "cell", "p": 0.64},
			{"who": "rook", "kind": "repair", "item": "thruster", "fault": "coil", "p": 0.2},
			{"who": "clatter", "kind": "repair", "item": "helperbot", "fault": "servo", "p": 0.7}]:
		if e["who"] != at_counter.get("who", "") and line.size() < 4:
			line.append(e)
	m.day.demo_fill(line, at_counter)
	m.shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
	m.shop.snap_camera()
	m.hud.set_clock(m.day.minutes(), "open")

## Las estadísticas de un día ya jugado (para el libro de cuentas).
func _fake_day(st: Dictionary, earned: int, spent: int, rep_delta: int) -> void:
	Game.reset_today()
	Game.today["credits_start"] = Game.credits - earned + spent
	Game.today["rep_start"] = Game.rep - rep_delta
	for k in st:
		Game.today[k] = st[k]
	Game.today["earned"] = earned
	Game.today["spent"] = spent

func _fake_history(paid: bool) -> void:
	Game.history = []
	# (--- SS MERGE: como los bots del balance: "good" ~360, "sloppy" ~240)
	var nets := [[115, 25, 4], [150, 55, 5], [175, 50, 4]] if paid else [[100, 35, 3], [95, 30, 1], [85, 25, 1]]
	var credits := Data.START_CREDITS
	for d in 3:
		var e: int = nets[d][0]
		var sp: int = nets[d][1]
		credits += e - sp
		Game.history.append({"day": d + 1, "repairs": [3, 5, 6][d] - (0 if paid else 1), "stars": [6, 11, 14][d] - (0 if paid else 4),
			"sales": [1, 2, 2][d] if paid else [1, 1, 1][d], "earned": e, "spent": sp, "walkouts": [0, 1, 1][d] + (0 if paid else 1), "missed": 0,
			"customers": [5, 7, 8][d], "arrived": [6, 8, 9][d], "refurbished": [0, 1, 1][d], "pods": 1, "tips": [0, 8, 4][d],
			"good": int(nets[d][2]) >= Data.GOOD_DAY_REP, "net": e - sp})
	Game.credits = credits
	Game.rep = 12 if paid else 4
	Game.sign_points = 3 if paid else 0

## Salir de una prueba sin sonidos a medio arrancar (si no, Godot avisa de flujos de audio "still in use" al cerrar).
func _quit(code: int) -> void:
	m.quit_clean(code)

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

# ------------------------------------------------------------------ savetest

## --demo=savetest (sin pantalla): la API de Game, el guardado JSON (ida y vuelta, con la partida de 3 días), que los
## datos cuadren (agenda, frases, elenco, piezas) y las reglas del día.
func _savetest() -> void:
	var fails: Array = []
	var chk := func(cond: bool, what: String):
		if not cond:
			fails.append(what)
	Game.new_game_state()
	chk.call(Game.day == 1 and Game.credits == Data.START_CREDITS and Game.dues_goal == Data.DUES_GOAL, "estado inicial")
	chk.call(Game.pods_today.size() == Data.DAY1_PODS.size(), "cápsulas del día 1")
	Game.add_credits(25)
	chk.call(Game.credits == Data.START_CREDITS + 25 and int(Game.today["earned"]) == 25, "add_credits")
	chk.call(Game.spend_credits(10) and not Game.spend_credits(999999), "spend_credits")
	Game.add_part("fan", 2)
	chk.call(Game.has_part("fan") and Game.part_count("fan") == 2, "add_part / has_part")
	chk.call(Game.take_part("fan") and Game.take_part("fan") and not Game.take_part("fan") and not Game.has_part("fan"), "take_part")
	Game.shelf_add("radio", 2)
	Game.add_junk("thruster", "coil")
	Game.add_rep(4)
	Game.stat("repairs", 2)
	var s := Game.close_day()
	chk.call(int(s["day"]) == 1 and bool(s["good"]) and Game.sign_points == 1 and Game.history.size() == 1, "close_day / cartel")
	Game.next_day()
	chk.call(Game.day == 2 and Game.pods_today.size() == Data.PODS_PER_DAY, "next_day / cápsulas sorteadas")
	var pods_before := JSON.stringify(Game.pods_today)
	Game.resume = "open"
	Game.tip_once("walk")
	var before := JSON.stringify(Game.to_dict())
	chk.call(Game.save_game(), "save_game")
	Game.new_game_state()
	chk.call(Game.load_game(), "load_game")
	chk.call(JSON.stringify(Game.to_dict()) == before, "ida y vuelta del JSON")
	chk.call(Game.day == 2 and Game.shelf.size() == 2 and Game.junk[0]["fault"] == "coil" and Game.rep == 4, "valores cargados")
	chk.call(JSON.stringify(Game.pods_today) == pods_before and Game.pods_today[0]["weight"] is int, "cápsulas guardadas (enteros)")
	chk.call(Game.history[0]["repairs"] is int and Game.sign_points == 1 and not Game.tip_once("walk"), "historial / consejos")
	chk.call(Game.can_continue(), "can_continue")
	Game.resume = "done"
	Game.save_game()
	chk.call(not Game.can_continue(), "no continuar una partida terminada")
	Game.delete_save()
	chk.call(not Game.has_save(), "delete_save")
	# una partida vieja de la semilla (versión 1, sin los datos de CORE) carga con valores por defecto
	Game.from_dict({"day": 2, "credits": 77, "parts": {"cell": 1.0}, "shelf": [], "today": {"repairs": 1.0}})
	chk.call(Game.day == 2 and Game.credits == 77 and Game.pods_today.size() == Data.PODS_PER_DAY, "partida de la semilla")
	# los datos
	for item in BenchData.ITEMS:
		for p in BenchData.ITEMS[item]["slots"]:
			chk.call(BenchData.PARTS.has(p), "pieza %s de %s" % [p, item])
		for f in BenchData.FAULTS[item]:
			chk.call(f in BenchData.ITEMS[item]["slots"], "falla %s de %s" % [f, item])
	for id in Data.CAST:
		chk.call(Data.SPECIES.has(Data.CAST[id]["species"]), "especie de %s" % id)
		chk.call(BenchData.HAGGLE.has(Data.CAST[id]["species"]), "regateo de %s" % id)
	for id in Data.CHAR_IDS:
		chk.call(ResourceLoader.exists("res://assets/chars/%s_idle.png" % id) and ResourceLoader.exists("res://assets/chars/%s_walk.png" % id), "hoja de %s" % id)
	chk.call(Data.SCHEDULE.size() == Data.DAYS, "agenda de %d días" % Data.DAYS)
	var counts := []
	for d in Data.DAYS:
		var sch := Data.schedule_for(d + 1)
		counts.append(sch.size())
		for e in sch:
			chk.call(Data.CUSTOMERS.has(e["who"]), "cliente %s" % e["who"])
			chk.call(float(e["t"]) < Data.DAY_SECONDS * 0.85, "llega a tiempo: %s día %d" % [e["who"], d + 1])
			if e["kind"] == "repair":
				chk.call(BenchData.FAULTS.get(e["item"], {}).has(e["fault"]), "falla %s/%s" % [e["item"], e["fault"]])
				chk.call(Data.line(e["who"], "bring", e["item"]) != "", "frase bring %s/%s" % [e["who"], e["item"]])
			else:
				for w in e["wants"]:
					chk.call(BenchData.ITEMS.has(w), "quiere %s" % w)
	chk.call(counts[0] >= 6 and counts[-1] <= 9 and counts[0] <= counts[1] and counts[1] <= counts[2], "agenda 6-9 creciente %s" % str(counts))
	for who in Data.CUSTOMERS:
		for k in ["buy", "failed", "angry", "decline", "sold", "nodeal", "none", "full", "home"]:
			chk.call(Data.LINES[who].has(k), "frase %s de %s" % [k, who])
		chk.call((Data.LINES[who]["thanks"] as Array).size() == 4, "4 gracias de %s" % who)
	for p in Data.DAY1_PODS:
		for c in p["contents"]:
			chk.call((c.has("part") and BenchData.PARTS.has(c["part"])) or (c.has("item") and BenchData.FAULTS[c["item"]].has(c["fault"])), "cápsula del día 1")
	# palabras prohibidas (la lista del brief) en los textos que se ven
	var bad := _ip_words()
	chk.call(bad.is_empty(), "palabras prohibidas: %s" % str(bad))
	print("SAVETEST %s checks_failed=%d %s" % ["ok" if fails.is_empty() else "FAIL", fails.size(), str(fails)])
	_quit(0 if fails.is_empty() else 1)

## Busca palabras de la saga en todos los textos de Data (y en los nombres de BenchData).
func _ip_words() -> Array:
	var words := ["droid", "jedi", "force", "lightsaber", "blaster", "tatooine", "mos ", "jawa", "tusken", "sandcrawler",
		"podracer", "speeder", "vaporator", "moisture", "cantina", "hutt", "wookiee", "sith", "rebel", "empire", "galaxy",
		"skywalker", "r2", "c-3po", "bb-8", "x-wing", "tie fighter", "falcon", "star destroyer"]
	var blob := ""
	for d in [Data.LINES, Data.MARKET_LINES, Data.TIPS, Data.CAST, Data.PLACES, Data.SPECIES]:
		blob += JSON.stringify(d).to_lower() + " "
	for a in [Data.INTRO, Data.KETTLE_TALK, [Data.KETTLE_TEA, Data.KETTLE_TEA_DONE]]:
		blob += JSON.stringify(a).to_lower() + " "
	var out := []
	for w in words:
		if blob.find(w) >= 0:
			out.append(w)
	return out

# ------------------------------------------------------------------ smoke

## --demo=smoke (sin pantalla): cada pantalla y cada camino corto del flujo, con las pantallas de BENCH por su bot.
func _smoke() -> void:
	Engine.time_scale = 4.0
	_watchdog(120.0)
	Game.delete_save()
	m.show_title()
	await _wait(0.3)
	_expect(m.screens.current == "title", "título")
	m.show_intro()
	await _wait(0.5)
	m.screens.press("skip")
	await _until(func(): return _phase() == "MORNING" and not m.busy, 8.0, "mañana tras la introducción")
	_expect(Game.save_game() and Game.has_save(), "guardado de la mañana")
	m.parts_stall()
	_expect(m.dialogs.is_open() and m.dialogs.buy_part("cell"), "comprar en el puesto de Mags")
	m.dialogs.choose("close")
	m.pods_stall()
	_expect(m.dialogs.is_open(), "el puesto de cápsulas")
	m.dialogs.choose("pod0")
	await _bot_ui(m.haggle, "haggle")
	await _bot_ui(m.pod_ui, "pod", true)
	m.open_shop()
	await _until(func(): return _phase() == "OPEN" and not m.busy, 8.0, "abrir la tienda")
	await _until(func(): return not m.day.waiting_at_counter().is_empty(), 20.0, "el primer cliente en el mostrador")
	m.use_counter()
	_expect(m.dialogs.is_open() and "repair" in m.dialogs.option_ids(), "diálogo del mostrador")
	m.dialogs.choose("repair")
	await _bot_ui(m.bench, "bench")
	await _until(func(): return m.job.is_empty() and not m.busy, 15.0, "entregar la reparación")
	_expect(int(Game.today.get("repairs", 0)) + int(Game.today.get("failed", 0)) == 1, "una reparación entregada")
	m.show_drawer()
	m.dialogs.choose("close")
	m.show_shelf()
	m.dialogs.choose("close")
	m.open_menu()
	_expect(m.dialogs.is_open() and m.day.paused, "menú de pausa")
	m.dialogs.choose("resume")
	m.day.force_close()
	await _until(func(): return _phase() == "NIGHT", 30.0, "el cierre y la noche")
	_expect(m.screens.current == "ledger", "libro de cuentas")
	m.screens.press("next")
	await _until(func(): return _phase() == "MORNING" and not m.busy, 8.0, "día 2")
	_expect(Game.day == 2, "día 2")
	m.show_closing()
	_expect(m.screens.current == "closing", "pantalla final")
	m.screens.press("title")
	await _until(func(): return _phase() == "TITLE", 8.0, "volver al título")
	Game.delete_save()
	print("SMOKE %s errors=%d frames=%d credits=%d" % ["ok" if m.errors == 0 else "FAIL", m.errors, m.frame, Game.credits])
	_quit(0 if m.errors == 0 else 1)

# ------------------------------------------------------------------ el bot de los 3 días

var _bot_log := []

## --demo=autoplay [--days=N]: juega la partida entera por el flujo real (como un jugador: camina a cada estación y la
## usa; las pantallas de BENCH se juegan con su bot_play()). Errores: los del contrato (main.contract_error) y los del
## flujo (algo que no se abrió, un día que no terminó, un guardado que no vuelve igual).
func _autoplay() -> void:
	Engine.time_scale = 6.0
	_watchdog(900.0)
	Game.delete_save()
	m.show_title()
	await _wait(0.4)
	m.screens.press("new")
	await _until(func(): return _phase() == "INTRO", 6.0, "la introducción")
	await _wait(1.5)
	m.screens.press("skip")
	var days := mini(maxi(1, m.autoplay_days), Data.DAYS)
	for d in days:
		await _until(func(): return _phase() == "MORNING" and not m.busy and m.fade.color.a < 0.5, 10.0, "la mañana del día %d" % (d + 1))
		if _phase() != "MORNING":
			break
		_expect(Game.day == d + 1, "día %d (Game.day=%d)" % [d + 1, Game.day])
		if d > 0:
			# la partida se guardó esta mañana: cargarla da lo mismo
			var cr := Game.credits
			var parts := Game.parts_total()
			_expect(Game.can_continue() and Game.load_game() and Game.credits == cr and Game.parts_total() == parts and Game.resume == "morning", "Continue el día %d" % (d + 1))
		await _bot_morning()
		await _until(func(): return _phase() == "OPEN" and not m.busy, 10.0, "abrir el día %d" % (d + 1))
		await _bot_open_day()
		await _until(func(): return _phase() == "NIGHT" and m.screens.current == "ledger", 30.0, "el libro de cuentas del día %d" % (d + 1))
		var s: Dictionary = Game.last_summary
		_expect(int(s.get("day", 0)) == d + 1 and Game.history.size() == d + 1, "resumen del día %d" % (d + 1))
		var line := "AUTOPLAY day=%d credits=%d rep=%d earned=%d (repairs %d, sales %d, tips %d, job %ds avg) spent=%d repairs=%d stars=%d sales=%d declined=%d walkouts=%d missed=%d pods=%d refurb=%d parts=%d shelf=%d junk=%d tea=%s good=%s" % [
			Game.day, Game.credits, Game.rep, int(s.get("earned", 0)), int(s.get("repair_pay", 0)), int(s.get("sale_pay", 0)),
			int(s.get("tips", 0)), int(s.get("job_secs", 0)) / maxi(1, int(s.get("repairs", 0)) + int(s.get("failed", 0))), int(s.get("spent", 0)), int(s.get("repairs", 0)),
			int(s.get("stars", 0)), int(s.get("sales", 0)), int(s.get("declined", 0)), int(s.get("walkouts", 0)),
			int(s.get("missed", 0)), int(s.get("pods", 0)), int(s.get("refurbished", 0)), Game.parts_total(), Game.shelf.size(),
			Game.junk.size(), str(s.get("tea", false)), str(s.get("good", false))]
		print(line)
		await _wait(0.6)
		if d < days - 1 or Game.is_last_day():
			m.screens.press("next")
	if Game.is_last_day():
		await _until(func(): return _phase() == "END" and m.screens.current == "closing", 10.0, "la pantalla final")
		var t := Game.totals()
		_expect(not Game.can_continue(), "la partida terminada no se continúa")
		print("AUTOPLAY end bot=%s dues_met=%s credits=%d/%d repairs=%d stars=%d sales=%d walkouts=%d missed=%d earned=%d spent=%d tips=%d good_days=%d sign=%d" % [bot, str(t["dues_met"]),
			Game.credits, Game.dues_goal, int(t["repairs"]), int(t["stars"]), int(t["sales"]), int(t["walkouts"]), int(t["missed"]),
			int(t["earned"]), int(t["spent"]), int(t["tips"]), int(t["good_days"]), int(t["sign_points"])])
		await _wait(0.5)
		m.screens.press("title")
		await _until(func(): return _phase() == "TITLE", 6.0, "volver al título")
	Game.delete_save()
	print("AUTOPLAY done days=%d errors=%d pace=%s bot=%s log=%s" % [days, m.errors, pace, bot, str(_bot_log)])
	_quit(0 if m.errors == 0 else 1)

## La mañana: una cápsula (la más pesada que alcance), una pieza de Mags si sobra, y abrir.
func _bot_morning() -> void:
	var st: StreetWorld = m.street
	# --- SS MERGE: las cápsulas según el perfil (una o dos: la segunda si sobra para una pieza y un margen)
	var tries := 0
	while not Game.pods_today.is_empty() and String(prof["pods"]) != "none" and tries < 2:
		tries += 1
		if tries == 2 and (String(prof["pods"]) != "best" or Game.credits < 60):
			break
		if await st.walker.go_station("pods"):
			m.use_station("pods")
			await _wait(0.2)
			if m.dialogs.is_open():
				var best := ""
				var best_w := -1
				for i in Game.pods_today.size():
					var p: Dictionary = Game.pods_today[i]
					var ask := int(round(float(p.get("price", 30)) * float(BenchData.HAGGLE["duneraker"]["ask"])))
					if String(prof["pods"]) == "first":
						if Game.credits >= ask:
							best = "pod%d" % i
							break
					elif int(p.get("weight", 1)) > best_w and Game.credits >= int(p.get("price", 30)) + 4:
						best_w = int(p.get("weight", 1))
						best = "pod%d" % i
				m.dialogs.choose(best if best != "" else "later")
				if best != "":
					await _bot_ui(m.haggle, "haggle")
					await _bot_ui(m.pod_ui, "pod", true)
				else:
					break
			elif Game.credits >= 20:
				_err("el puesto de cápsulas no abrió su diálogo")
	# --- end SS MERGE
	if bool(prof["parts"]) and Game.credits >= 45:   # (--- SS MERGE: según el perfil)
		if await st.walker.go_station("parts"):
			m.use_station("parts")
			await _wait(0.2)
			if m.dialogs.is_open():
				# lo que más falta: la pieza de la que menos hay (entre las que más se rompen); hasta dos si sobra
				# (--- SS MERGE: dos, y solo con margen: las piezas son baratas pero la cuota manda)
				for k in 2:
					var want := "cell"
					for p in ["cell", "chip", "lens", "tuner", "coil", "servo", "fan"]:
						if Game.part_count(p) < Game.part_count(want):
							want = p
					if Game.part_count(want) > 0 or Game.credits < 40 + BenchData.part_price(want):
						break
					if not m.dialogs.buy_part(want):
						_err("no se pudo comprar %s con %d cr" % [want, Game.credits])
					await _wait(0.2)
				m.dialogs.choose("close")
			else:
				_err("el puesto de Mags no abrió")
	if await st.walker.go_station("door"):
		m.use_station("door")
	else:
		_err("no llegó a la puerta")

## El día abierto: atender el mostrador, el banco, el té y lo roto de las cápsulas hasta que cierre.
func _bot_open_day() -> void:
	var sh: ShopWorld = m.shop
	var guard := 0
	while _phase() == "OPEN":
		guard += 1
		if guard > 6000:
			_err("el día abierto no termina")
			return
		await _wait(0.25)
		if m.busy or m.menu_open:
			continue
		if m.bench.is_open():
			await _bot_ui(m.bench, "bench")
			continue
		if m.haggle.is_open():
			await _bot_ui(m.haggle, "haggle")
			continue
		if m.dialogs.is_open():
			_bot_dialog()
			continue
		if not m.job.is_empty():
			var stage := String(m.job.get("stage", ""))
			if stage == "accepted":
				m.go_bench_job()
			elif stage in ["done", "failed"]:
				if await sh.walker.go_station("counter"):
					m.use_station("counter")
			continue
		if not m.day.waiting_at_counter().is_empty():
			if float(prof["react"]) > 0.0:
				await _wait(float(prof["react"]) * _rng.randf_range(0.7, 1.3))   # --- SS MERGE: lo que tarda en reaccionar
			if await sh.walker.go_station("counter"):
				m.use_station("counter")
			continue
		# el té: con la fila larga
		if bool(prof["tea"]) and m.day.line_count() >= 2 and String(m.station_verb("tea")[0]) == "Tea":
			if await sh.walker.go_station("tea"):
				m.use_station("tea")
				_bot_log.append("tea day %d" % Game.day)
			continue
		# lo roto de las cápsulas: si no hay nadie en camino al mostrador
		if bool(prof["refurb"]) and not Game.junk.is_empty() and m.day.counter.is_empty() and m.day.line_count() == 0 and not m.day.closing:
			if await sh.walker.go_station("bench"):
				m.use_station("bench")
			continue
		# nada que hacer: esperar junto al mostrador
		if sh.walker.current != "counter" and not sh.walker.is_walking():
			sh.walker.go_station("counter")

## Elige en el diálogo abierto como un jugador razonable.
func _bot_dialog() -> void:
	var ids: Array = m.dialogs.option_ids()
	var kind := String(m.dialogs.spec.get("kind", ""))
	if kind in ["info", "parts"]:
		m.dialogs.choose("close")
		return
	if kind == "menu":
		m.dialogs.choose("resume")
		return
	if "repair" in ids:
		m.dialogs.choose("repair")
		return
	for id in ids:
		if String(id).begins_with("sell"):
			m.dialogs.choose(id)
			return
	for id in ids:
		if String(id).begins_with("j"):
			m.dialogs.choose(id)
			return
	if "none" in ids:
		m.dialogs.choose("none")
		return
	if "later" in ids:
		m.dialogs.choose("later")
		return
	m.dialogs.choose(ids[0] if not ids.is_empty() else "")

## Espera a que una pantalla del contrato se abra, la deja jugar sola (bot_play) y espera a que se cierre.
func _bot_ui(ui, what: String, optional := false) -> void:
	for i in 40:
		if ui.is_open():
			break
		await _wait(0.05)
	if not ui.is_open():
		if not optional:
			_err("%s: no se abrió" % what)
		return
	await _wait(0.3)
	if pace == "real":
		await _wait(float(PACE_REAL.get(what, 2.0)) * _rng.randf_range(0.8, 1.2))
	elif float(prof["wait"].get(what, 0.0)) > 0.0:
		await _wait(float(prof["wait"][what]) * _rng.randf_range(0.85, 1.15))   # --- SS MERGE: el perfil
	if not ui.is_open():
		return
	if what in ["bench", "haggle"]:
		ui.bot_play(float(prof["skill"][what]))
	else:
		ui.bot_play()
	for i in 1200:
		if not ui.is_open():
			return
		await _wait(0.05)
	_err("%s: bot_play() no la cerró" % what)
	ui.close_now()

# ------------------------------------------------------------------ ayudas

func _phase() -> String:
	return String(m.Phase.keys()[m.phase])

func _until(cond: Callable, secs: float, what: String) -> void:
	var t := 0.0
	while not cond.call():
		await _wait(0.1)
		t += 0.1
		if t > secs:
			_err("esperando %s (fase %s)" % [what, _phase()])
			return

func _expect(cond: bool, what: String) -> void:
	if not cond:
		_err("falló: " + what)

func _err(msg: String) -> void:
	m.errors += 1
	push_warning("BOT: " + msg)
	print("BOT ERROR ", msg)

func _watchdog(secs: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = secs
	t.ignore_time_scale = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(func():
		print("WATCHDOG: atascado después de %d s (fase %s, errors=%d)" % [int(secs), _phase(), m.errors + 1])
		get_tree().quit(2))
	t.start()
