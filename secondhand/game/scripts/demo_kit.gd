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
## --- SS2 SEASON: + human (el ritmo del cliente: ~35-45 s por reparación, piensa más en los dos primeros trabajos de
## cada familia, habilidad = good x 0.85) y las claves de la temporada (§8.14): fittings ("order" | "max1" | "basic"),
## asis (compra lo de "tal cual" si el estante tiene < 3), after (arreglos de noche), beats ("first" | "random"),
## close (cierra antes si se puede), income (lo que espera ganar al día: la reserva para la próxima cuota),
## eve_hold (la víspera de Bronzemoon no vende del estante mientras tenga <= 5: lo guarda para la fiesta),
## dues_guard (la noche de la cuota no gasta en cápsulas ni "tal cual" lo que le falta para pagarla).
const PROFILES := {
	"perfect": {"wait": {"bench": 0.0, "haggle": 0.0, "pod": 0.0}, "skill": {"bench": 1.0, "haggle": 1.0},
		"react": 0.0, "tea": true, "parts": true, "refurb": true, "pods": "best",
		"fittings": "order", "asis": true, "after": 2, "beats": "first", "close": true, "income": 160.0, "think_first": 1.0,
		"eve_hold": true, "dues_guard": true},
	"good": {"wait": {"bench": 17.0, "haggle": 6.0, "pod": 3.0}, "skill": {"bench": 0.85, "haggle": 0.9},
		"react": 2.0, "tea": true, "parts": true, "refurb": true, "pods": "best",
		"fittings": "order", "asis": true, "after": 2, "beats": "first", "close": true, "income": 130.0, "think_first": 1.0,
		"eve_hold": true, "dues_guard": true},
	"human": {"wait": {"bench": 25.0, "haggle": 8.0, "pod": 4.0}, "skill": {"bench": 0.72, "haggle": 0.77},
		"react": 3.0, "tea": true, "parts": true, "refurb": true, "pods": "best",
		"fittings": "max1", "asis": true, "after": 2, "beats": "random", "close": true, "income": 110.0, "think_first": 1.5,
		"dues_guard": true},
	"sloppy": {"wait": {"bench": 31.0, "haggle": 9.0, "pod": 4.0}, "skill": {"bench": 0.45, "haggle": 0.35},
		"react": 5.0, "tea": false, "parts": false, "refurb": true, "pods": "first",
		"fittings": "basic", "asis": false, "after": 1, "beats": "random", "close": false, "income": 70.0, "think_first": 1.0},
}
var bot := "perfect"
var prof: Dictionary = PROFILES["perfect"]
# --- end SS MERGE
# --- SS2 SEASON: los argumentos del bot de la campaña
var _endless := 0
var _from := 1
var _timescale := 6.0
var _seed_arg := -1

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
			_seed_arg = int(a.substr(7))
		elif a.begins_with("--endless="):   # --- SS2 SEASON
			_endless = maxi(0, int(a.substr(10)))
		elif a.begins_with("--from="):
			_from = maxi(1, int(a.substr(7)))
		elif a.begins_with("--timescale="):
			_timescale = maxf(1.0, float(a.substr(12)))
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
		"shop_idle":
			# --- POLISH FIX (F5): la tienda vacía a media mañana: la hora corre x3 con "»" (dos capturas, 5 s aparte)
			_state(2)
			m.open_shop_now()
			m.day._arrivals = []
			m.day.shop_t = 60.0
			m.hud.hide_banner()
		"buyer_empty":
			# --- POLISH FIX (F4): un comprador ante el estante vacío ("Fix theirs instead"); --step=order lo elige
			# (con la fila corta: "Fix theirs instead" solo se ofrece si esperan a lo sumo ORDER_MAX_LINE)
			_state(2)
			m.open_shop_now()
			m.day.clear()
			m.day.running = true
			m.day.shop_t = 112.0
			m.day.demo_fill([{"who": "zib", "kind": "repair", "item": "helperbot", "fault": "cell", "p": 0.8}],
				{"who": "oona", "kind": "buy", "wants": ["radio"]})
			m.shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
			m.shop.snap_camera()
			m.hud.set_clock(m.day.minutes(), "open")
			Game.shelf.clear()
			m.shop.refresh_shelf()
			await _wait(0.6)
			m.use_counter()
			if "--step=order" in OS.get_cmdline_user_args():
				await _wait(0.4)
				m.dialogs.choose("order")
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
		"flowtest":   # --- POLISH FIX (F1)
			_flowtest()
		"podtest":    # --- POLISH FIX (F3)
			_podtest()
		"idletest":   # --- POLISH FIX (F5)
			_idletest()
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

# --- POLISH FIX (F1) ------------------------------------------------ flowtest
## --demo=flowtest (sin pantalla): una ráfaga de Espacio que viene de la introducción no abre la tienda; una pulsación
## después de una pausa sí cuenta; "Open shop" con el momento de la mañana pendiente lo muestra primero y después abre.
func _flowtest() -> void:
	_watchdog(90.0)
	var fails: Array = []
	var press := func(k: Key):
		for down in [true, false]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			e.pressed = down
			Input.parse_input_event(e)
			await get_tree().process_frame
			await get_tree().process_frame
	# 1) día 2: la ráfaga de Espacio empieza en la introducción y sigue cada 1.3 s después de la mañana
	Season.debug_state(2, "good")
	Game.tips_seen["walk"] = true
	await press.call(KEY_SPACE)
	await _wait(1.3)
	m.begin_morning()
	await _wait(0.3)
	if m.street.walker.current != "door":
		fails.append("Nell no empieza en la puerta (%s)" % m.street.walker.current)
	for i in 3:
		await press.call(KEY_SPACE)
		if m.phase != m.Phase.MORNING:
			fails.append("la tecla %d de la ráfaga abrió la tienda" % (i + 1))
			break
		await _wait(1.3)
	# 2) el momento aparece en plena ráfaga: las pulsaciones de la ráfaga no lo contestan; una después de 2.5 s sí
	if not m.dialogs.is_open():
		m._run_morning_beats()
	await _until(func(): return m.dialogs.is_open(), 8.0, "el momento crate_ask")
	if String(m.dialogs.spec.get("beat", "")) != "crate_ask":
		fails.append("crate_ask no se abrió")
	await press.call(KEY_SPACE)
	if not m.dialogs.is_open() or Game.beats_seen.has("crate_ask"):
		fails.append("la ráfaga contestó el momento")
	var since: int = Time.get_ticks_msec() - m.dialogs._opened_ms
	await _wait(maxf(0.1, (2700 - since) / 1000.0))
	await press.call(KEY_SPACE)
	await _wait(0.3)
	if m.dialogs.is_open() or not Game.beats_seen.has("crate_ask"):
		fails.append("Espacio a los 2.8 s no contestó el momento")
	# 3) día 3: después de una pausa, E en la puerta con rival_hello pendiente -> el momento primero, después abre
	Season.debug_state(3, "good")
	m.begin_morning()
	await _wait(2.3)
	if not Game.beats_seen.has("rival_hello"):
		await press.call(KEY_E)
		await _wait(0.4)
		if not (m.dialogs.is_open() and String(m.dialogs.spec.get("beat", "")) == "rival_hello"):
			fails.append("E en la puerta no mostró rival_hello (dialogo=%s fase=%s)" % [m.dialogs.is_open(), _phase()])
		else:
			m.dialogs.choose("ok")
		await _until(func(): return m.phase == m.Phase.OPEN, 6.0, "la tienda abierta después del momento")
		if not Game.beats_seen.has("rival_hello"):
			fails.append("rival_hello no quedó visto")
		# la tienda recién abierta: la ráfaga de la puerta no toca el mostrador
		if m.phase == m.Phase.OPEN and not m._interact_blocked():
			fails.append("recién abierta, interact no está bloqueado")
	else:
		fails.append("rival_hello salió solo antes de los 2.3 s")
	for f in fails:
		print("FLOWTEST fail: ", f)
	print("FLOWTEST %s fails=%d errors=%d" % ["ok" if fails.is_empty() and m.errors == 0 else "FAIL", fails.size(), m.errors])
	_quit(0 if fails.is_empty() else 1)
# --- end POLISH FIX

# --- POLISH FIX (F5) ------------------------------------------------ idletest
## --demo=idletest (sin pantalla, tiempo real): el día 1, un jugador quieto. Gorrum (el tutorial) se va atendido y se
## mide cuántos segundos reales pasan hasta que Zib llega al mostrador (BASE: ~60 s; la meta: <= 25 s).
func _idletest() -> void:
	_watchdog(120.0)
	_state(1)
	m.open_shop_now()
	await _until(func(): return not m.day.counter.is_empty() and String(m.day.counter.get("state", "")) in ["counter", "talk"], 30.0, "Gorrum en el mostrador")
	var g: Dictionary = m.day.counter
	m.day.leave(g, "done", "")
	m._end_tutorial()
	var t0 := Time.get_ticks_msec()
	var fast_seen := false
	while Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
		fast_seen = fast_seen or m.day.fast
		var c: Dictionary = m.day.counter
		if not c.is_empty() and String(c.get("who", "")) == "zib" and String(c.get("state", "")) == "counter":
			break
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("IDLETEST %s zib_at_counter_after=%.1f s fast_forward_seen=%s shop_t=%.1f" % ["ok" if secs <= 25.0 and fast_seen else "FAIL", secs, fast_seen, m.day.shop_t])
	_quit(0 if secs <= 25.0 else 1)
# --- end POLISH FIX

# --- POLISH FIX (F3) ------------------------------------------------- podtest
## --demo=podtest (sin pantalla): las semillas 1-300 x los días 2-12 (sin la Scour): las dos primeras cápsulas nunca
## pesan igual, al menos una trae una cosa rota, y la misma partida da las mismas cápsulas dos veces.
func _podtest() -> void:
	var fails: Array = []
	var mornings := 0
	var checks := 0
	var light_first := 0
	var w_hist := {}
	for sd in range(1, 301):
		Game.new_game_state()
		Game.run_seed = sd
		for d in range(2, 13):
			Game.day = d
			var a: Array = Season.pods_for(d)
			if a.size() < 2:
				continue
			mornings += 1
			var b: Array = Season.pods_for(d)
			checks += 3
			if JSON.stringify(a) != JSON.stringify(b):
				fails.append("s%d d%d: no es determinista" % [sd, d])
			var w0 := int(a[0].get("weight", 1))
			var w1 := int(a[1].get("weight", 1))
			if w0 == w1:
				fails.append("s%d d%d: pesan igual (%d)" % [sd, d, w0])
			if w0 < w1:
				light_first += 1
			if not (Season._pod_has_item(a[0]) or Season._pod_has_item(a[1])):
				fails.append("s%d d%d: ninguna trae una cosa rota" % [sd, d])
			var k := "%d/%d" % [w0, w1]
			w_hist[k] = int(w_hist.get(k, 0)) + 1
	Game.new_game_state()
	for f in fails.slice(0, 12):
		print("PODTEST fail: ", f)
	print("PODTEST weights(first/second) ", w_hist, " light_first=", light_first)
	print("PODTEST %s mornings=%d checks=%d fails=%d" % ["ok" if fails.is_empty() else "FAIL", mornings, checks, fails.size()])
	_quit(0 if fails.is_empty() else 1)
# --- end POLISH FIX

# ------------------------------------------------------------------ savetest

## --demo=savetest (sin pantalla): la API de Game, el guardado v3 (ida y vuelta), las 3 partidas v2 del prototipo
## (SP/ss2/fixtures), un archivo basura, que los datos cuadren (agendas de 12 días, frases, elenco, piezas, mejoras,
## momentos) y la búsqueda de palabras prohibidas (§10.3) en Data, CastData, SeasonData y Ranking. --- SS2 SEASON
const FIXTURES := "/tmp/claude-0/-home-user-dead-air/84a550d9-2edd-52f7-8fa3-04790d444022/scratchpad/ss2/fixtures"

func _savetest() -> void:
	var fails: Array = []
	var chk := func(cond: bool, what: String):
		if not cond:
			fails.append(what)
	Game.new_game_state()
	chk.call(Game.day == 1 and Game.credits == Data.START_CREDITS and Game.dues_goal == int(SeasonData.DUES[3]), "estado inicial (cuota 100 la noche 3)")
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
	Game.stat("served", 2)
	Game.stat("repair_stars", 5)
	var s := Game.close_day()
	chk.call(int(s["day"]) == 1 and Game.history.size() == 1 and s.has("rank") and int(s["rank"].get("pos", 0)) == Ranking.position(), "close_day / el tablero")
	# (la jugada del tablero suma el bono de la noche y el LATE: aquí se comparan las del día solas, como pide RANK)
	var mv: Dictionary = s["rank"]
	chk.call(int(s["day_stars"]) - int(mv.get("bonus", 0)) - int(mv.get("late", 0)) == int(Ranking.day_stars(Game.today)["total"]), "las estrellas del día")
	chk.call(Ranking.commit_day() == Ranking.last_move(), "commit_day idempotente")
	Game.next_day()
	chk.call(Game.day == 2 and Game.pods_today.size() == Season.pods_for(2).size(), "next_day / cápsulas")
	Season.on_morning()
	chk.call(Season.is_unlocked("vendor") and not Season.is_unlocked("rival"), "lo que se abre el día 2")
	Game.add_credits(200)
	chk.call(Season.buy_fitting("seats") and Game.has_fitting("seats") and "seats" in Game.fittings_new, "Liner Seats")
	chk.call(absf(Season.k("line_drain_k") - 0.75) < 0.001 and Season.n("appeal") >= 1, "los efectos de las mejoras")
	Game.set_flag("crate", "kept")
	Game.beats_seen["crate_ask"] = true
	var pods_before := JSON.stringify(Game.pods_today)
	Game.resume = "open"
	Game.tip_once("walk")
	var before := JSON.stringify(Game.to_dict())
	chk.call(Game.save_game(), "save_game")
	Game.new_game_state()
	chk.call(Game.load_game(), "load_game")
	chk.call(JSON.stringify(Game.to_dict()) == before, "ida y vuelta del JSON v3")
	chk.call(Game.day == 2 and Game.shelf.size() == 2 and Game.junk[0]["fault"] == "coil" and Game.rep == 4, "valores cargados")
	chk.call(JSON.stringify(Game.pods_today) == pods_before and Game.pods_today[0]["weight"] is int, "cápsulas guardadas (enteros)")
	chk.call(Game.history[0]["repairs"] is int and not Game.tip_once("walk"), "historial / consejos")
	chk.call(Game.has_fitting("seats") and Game.flag("crate", "") == "kept" and Game.beats_seen.has("crate_ask") and Game.migrated_from == 0, "la temporada cargada")
	chk.call(Ranking.position() == int(Game.history[0]["rank"]["pos"]), "el tablero cargado")
	chk.call(Game.can_continue(), "can_continue")
	Game.resume = "done"
	Game.save_game()
	chk.call(not Game.can_continue() and Game.save_note() == "", "no continuar una partida terminada (v3, sin nota)")
	Game.delete_save()
	chk.call(not Game.has_save(), "delete_save")
	# una partida vieja de la semilla (versión 1, sin los datos de CORE) carga con valores por defecto
	Game.from_dict({"day": 2, "credits": 77, "parts": {"cell": 1.0}, "shelf": [], "today": {"repairs": 1.0}})
	chk.call(Game.day == 2 and Game.credits == 77 and Game.pods_today.size() == Season.pods_for(2).size() and Game.migrated_from == 1, "partida de la semilla")
	# las tres partidas del prototipo (v2) y un archivo basura
	for f in ["v2_day2_morning", "v2_day3_open", "v2_done"]:
		var path := "%s/%s.json" % [FIXTURES, f]
		if not FileAccess.file_exists(path):
			fails.append("falta el fixture %s" % f)
			continue
		var txt := FileAccess.get_file_as_string(path)
		var w := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		w.store_string(txt)
		w.close()
		var d0 = JSON.parse_string(txt)
		Game.new_game_state()
		match f:
			"v2_day2_morning":
				chk.call(Game.can_continue() and Game.load_game(), "v2 día 2: carga")
				chk.call(Game.day == 2 and Game.resume == "morning" and Game.migrated_from == 2 and Game.credits == int(d0["credits"]), "v2 día 2: el mismo día")
				chk.call(Game.dues_goal == 100 and Season.next_dues()["night"] == 3, "v2 día 2: la cuota de la noche 3")
				chk.call(Season.is_unlocked("vendor") and Game.sign_points >= int(d0["sign_points"]), "v2 día 2: lo abierto y el cartel")
				chk.call(int(Ranking.last_move().get("day", 0)) == 1 and Ranking.position() < 30, "v2 día 2: el tablero rehecho")
				chk.call(Game.save_game() and Game.load_game() and Game.migrated_from == 0, "v2 día 2: se guarda como v3")
			"v2_day3_open":
				chk.call(Game.load_game() and Game.day == 3 and Game.resume == "open" and Game.migrated_from == 2, "v2 día 3 abierto")
				chk.call(Season.is_unlocked("rival") and Season.is_unlocked("asis"), "v2 día 3: Shine Again y el cajón de Mags")
				chk.call(int(Ranking.last_move().get("day", 0)) == 2 and Season.dues_due(3) == 100, "v2 día 3: el tablero y la cuota de esta noche")
			"v2_done":
				chk.call(not Game.can_continue(), "v2 terminada: no se continúa")
				chk.call(Game.save_note() == String(SeasonData.TEXT["prototype_over"]), "v2 terminada: la nota del título")
	for junk in ["not json {{", "[1, 2, 3]", ""]:
		var w2 := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		w2.store_string(junk)
		w2.close()
		Game.new_game_state()
		chk.call(not Game.load_game() and not Game.can_continue() and Game.day == 1, "archivo basura: %s" % junk)
	Game.delete_save()
	Game.new_game_state()
	# los datos
	for item in BenchData.ITEMS:
		for p in BenchData.ITEMS[item]["slots"]:
			chk.call(BenchData.PARTS.has(p), "pieza %s de %s" % [p, item])
		for fl in BenchData.FAULTS[item]:
			chk.call(fl in BenchData.ITEMS[item]["slots"], "falla %s de %s" % [fl, item])
	for id in Data.CAST:
		chk.call(Data.SPECIES.has(Data.CAST[id]["species"]), "especie de %s" % id)
	for id in Data.CHAR_IDS:
		chk.call(ResourceLoader.exists("res://assets/chars/%s_idle.png" % id) and ResourceLoader.exists("res://assets/chars/%s_walk.png" % id), "hoja de %s" % id)
	for who in Data.CUSTOMERS:
		for k in ["buy", "failed", "angry", "decline", "sold", "nodeal", "none", "full", "home"]:
			chk.call(Data.LINES.get(who, {}).has(k), "frase %s de %s" % [k, who])
		chk.call((Data.LINES.get(who, {}).get("thanks", []) as Array).size() == 4, "4 gracias de %s" % who)
	for fid in SeasonData.FITTING_ORDER:
		chk.call(SeasonData.FITTINGS.has(fid), "mejora %s" % fid)
	for bid in SeasonData.BEAT_ORDER:
		var b: Dictionary = SeasonData.BEATS[bid]
		chk.call(Data.CAST.has(String(b["who"])), "quién habla en %s" % bid)
		chk.call((b["lines"] as Array).size() == 2 and (b["options"] as Array).size() <= 2, "dos líneas y <= 2 opciones: %s" % bid)
	# las agendas de 12 días (con lo abierto de una partida típica)
	Season.debug_state(1, "good")
	for d in range(1, 13):
		Game.day = d
		Season.update_unlocks(d)
		var sch := Season.schedule_for(d)
		chk.call(sch.size() <= SeasonData.ARRIVALS_CAP and sch.size() >= 5, "llegadas del día %d: %d" % [d, sch.size()])
		for e in sch:
			chk.call(Data.CAST.has(e["who"]), "cliente %s día %d" % [e["who"], d])
			chk.call(float(e["t"]) < Data.DAY_SECONDS * 0.87, "llega a tiempo: %s día %d (t %d)" % [e["who"], d, int(e["t"])])
			if e["kind"] in ["repair", "favour"]:
				chk.call(BenchData.FAULTS.get(e["item"], {}).has(e["fault"]), "falla %s/%s día %d" % [e["item"], e["fault"], d])
			elif e["kind"] == "buy":
				chk.call(not (e["wants"] as Array).is_empty(), "quiere algo: %s día %d" % [e["who"], d])
				for w in e["wants"]:
					chk.call(BenchData.ITEMS.has(w), "quiere %s" % w)
		chk.call(Season.schedule_for(d) == sch, "la agenda del día %d es la misma dos veces" % d)
		for p in Season.pods_for(d):
			for c in p["contents"]:
				chk.call(c.has("core") or (c.has("part") and BenchData.PARTS.has(c["part"])) or (c.has("item") and BenchData.FAULTS[c["item"]].has(c["fault"])), "cápsula del día %d" % d)
	Game.new_game_state()
	# palabras prohibidas (§10.3) en los textos que se ven
	var bad := _ip_words()
	chk.call(bad.is_empty(), "palabras prohibidas: %s" % str(bad))
	print("SAVETEST %s checks_failed=%d %s" % ["ok" if fails.is_empty() else "FAIL", fails.size(), str(fails)])
	_quit(0 if fails.is_empty() else 1)

## Busca las palabras de la saga (§10.3: palabras enteras, sin mayúsculas salvo "Force") en Data, CastData, SeasonData
## y Ranking, y los dígitos "42" en las frases.
func _ip_words() -> Array:
	var words := ["droid", "jedi", "sith", "lightsaber", "blaster", "tatooine", "mos", "jawa", "tusken", "raider",
		"sand people", "sandcrawler", "podrace", "podracer", "speeder", "landspeeder", "swoop", "vaporator", "moisture farm",
		"cantina", "hutt", "wookiee", "ewok", "gungan", "holonet", "holocron", "hologram", "holo", "hyperspace", "hyperdrive",
		"lightspeed", "parsec", "repulsor", "spice", "sabacc", "kessel", "corellian", "mandalorian", "mando", "coruscant",
		"naboo", "endor", "hoth", "dagobah", "jakku", "skywalker", "kenobi", "falcon", "x-wing", "tie fighter", "death star",
		"star destroyer", "wayfinder", "outer rim", "mid rim", "inner rim", "core worlds", "wild space", "senate", "empire",
		"imperial", "rebel", "rebels", "republic", "moff", "trooper", "bounty", "astromech", "protocol bot", "power converter",
		"bacta", "carbonite", "kyber", "beskar", "nerf", "bantha", "dewback", "krayt", "womp rat", "mynock", "porg", "concord",
		"hammerhead", "bellwether", "hitchhiker", "fix-it", "saltmarch", "saltmarsh", "dustline", "lumi", "fennick", "collector"]
	var blob := ""
	for d in [Data.LINES, Data.MARKET_LINES, Data.TIPS, Data.CAST, Data.PLACES, Data.SPECIES, Data.RIDDLES]:
		blob += JSON.stringify(d) + " "
	for a in [Data.INTRO, Data.KETTLE_TALK, [Data.KETTLE_TEA, Data.KETTLE_TEA_DONE]]:
		blob += JSON.stringify(a) + " "
	var sd: Dictionary = (load("res://scripts/season_data.gd") as Script).get_script_constant_map()
	for k in sd:
		blob += JSON.stringify(sd[k]) + " "
	var rk: Dictionary = (Ranking.get_script() as Script).get_script_constant_map()
	for k in ["SHOPS", "WORLDS", "BOARD_NAME", "REGION", "SHOW", "REPORT"]:
		if rk.has(k):
			blob += JSON.stringify(rk[k]) + " "
	for k in ["REPORTS", "LINES", "ROSA", "SCANDALS", "HEADLINES", "ADS", "POOLS"]:
		if rk.has(k):
			blob += JSON.stringify(rk[k]) + " "
	if ResourceLoader.exists(Data.CAST_DATA_PATH):
		var cd: Dictionary = (load(Data.CAST_DATA_PATH) as Script).get_script_constant_map()
		for k in cd:
			blob += JSON.stringify(cd[k]) + " "
	blob = blob.replace("\\n", " ").replace("ship_hammerhead", "")
	var low := blob.to_lower()
	var out := []
	var re := RegEx.new()
	for w in words:
		re.compile("(?<![a-z0-9_])" + w.replace("-", "\\-") + "(?![a-z0-9_])")
		if re.search(low) != null:
			out.append(w)
	re.compile("(?<![A-Za-z])Force(?![A-Za-z])")
	if re.search(blob) != null:
		out.append("Force")
	re.compile("(?<![0-9])42(?![0-9])")
	var lines_blob := JSON.stringify(Data.LINES) + JSON.stringify(sd.get("BEATS", {})) + JSON.stringify(sd.get("TEXT", {}))
	if re.search(lines_blob) != null:
		out.append("42")
	return out

# ------------------------------------------------------------------ smoke

## --demo=smoke (sin pantalla): cada pantalla y cada camino corto del flujo, con las pantallas de BENCH por su bot.
## --- SS2 SEASON: + después de cerrar, el tablero (R), el calendario, Dolly, la vecina, la cuota, la gala, "Keep trading".
func _smoke() -> void:
	Engine.time_scale = 4.0
	_watchdog(240.0)
	m.rank.auto = true
	m.gala.auto = true
	Game.delete_save()
	m.show_title()
	await _wait(0.3)
	_expect(m.screens.current == "title", "título")
	m.show_intro()
	await _wait(0.5)
	m.screens.press("skip")
	await _until(func(): return _phase() == "MORNING" and not m.busy, 8.0, "mañana tras la introducción")
	_expect(Game.save_game() and Game.has_save(), "guardado de la mañana")
	await _wait(1.0)
	m.parts_stall()
	_expect(m.dialogs.is_open() and m.dialogs.buy_part("cell"), "comprar en el puesto de Mags")
	m.dialogs.choose("close")
	m.pods_stall()
	_expect(m.dialogs.is_open(), "el puesto de cápsulas")
	m.dialogs.choose("pod0")
	await _bot_ui(m.haggle, "haggle")
	await _bot_ui(m.pod_ui, "pod", true)
	m.open_calendar()
	_expect(m.dialogs.is_open() and String(m.dialogs.spec.get("kind", "")) == "calendar", "el calendario")
	m.dialogs.choose("close")
	m.open_rank_board()
	# (el de RANK, con auto, se cierra solo al rato; el stub enseguida)
	await _until(func(): return not m.rank.is_open(), 8.0, "el tablero se cierra solo (auto)")
	m.open_shop()
	await _until(func(): return _phase() == "OPEN" and not m.busy, 8.0, "abrir la tienda")
	await _until(func(): return not m.day.waiting_at_counter().is_empty(), 20.0, "el primer cliente en el mostrador")
	m.use_counter()
	_expect(m.dialogs.is_open() and "repair" in m.dialogs.option_ids(), "diálogo del mostrador")
	m.dialogs.choose("repair")
	await _bot_ui(m.bench, "bench")
	await _until(func(): return m.job.is_empty() and not m.busy, 15.0, "entregar la reparación")
	_expect(int(Game.today.get("repairs", 0)) + int(Game.today.get("failed", 0)) == 1, "una reparación entregada")
	_expect(int(Game.today.get("served", 0)) == int(Game.today.get("repairs", 0)), "served")
	m.show_drawer()
	m.dialogs.choose("close")
	m.show_shelf()
	m.dialogs.choose("close")
	m.open_menu()
	_expect(m.dialogs.is_open() and m.day.paused and "calendar" in m.dialogs.option_ids(), "menú de pausa (con el calendario)")
	m.dialogs.choose("resume")
	Game.add_junk("radio", "tuner")
	m.day.force_close()
	await _until(func(): return _phase() == "NIGHT" and m.dialogs.is_open(), 30.0, "después de cerrar")
	_expect(String(m.dialogs.spec.get("title", "")) == String(SeasonData.TEXT["after_title"]), "el diálogo de después de cerrar")
	m.dialogs.choose("sleep")
	await _until(func(): return m.screens.current == "ledger", 10.0, "libro de cuentas")
	_expect(String(Game.last_summary.get("board_line", "")) != "", "la fila del tablero en el libro")
	m.screens.press("next")
	await _until(func(): return _phase() == "MORNING" and not m.busy, 12.0, "día 2")
	_expect(Game.day == 2 and m.night_boards == 1, "día 2 (un tablero de noche)")
	# Dolly el día 2
	await _until(func(): return not m.dialogs.is_open() and not m.busy, 20.0, "la mañana libre")
	while m.dialogs.is_open():
		m.dialogs.choose(m.dialogs.option_ids()[0])
		await _wait(0.3)
	await _wait(8.0)
	while m.dialogs.is_open():
		m.dialogs.choose(m.dialogs.option_ids()[0])
		await _wait(0.5)
	Game.add_credits(100)
	m.fittings_stall()
	_expect(m.dialogs.is_open() and String(m.dialogs.spec.get("kind", "")) == "fittings", "el patio de Dolly")
	_expect(m.dialogs.buy_fitting("samovar") and Game.has_fitting("samovar"), "comprar el Samovar")
	_expect(not m.dialogs.buy_fitting("display"), "el Display Case todavía no (día 3, rep 15)")
	m.dialogs.choose("close")
	m.visit_rival()
	_expect(not m.dialogs.is_open(), "Shine Again todavía cerrada el día 2")
	# la noche 3: la cuota
	Season.debug_state(3, "good")
	Game.credits = 60
	m.open_shop_now()
	await _until(func(): return _phase() == "OPEN" and not m.busy, 8.0, "abrir el día 3")
	m.day.force_close()
	await _until(func(): return _phase() == "NIGHT", 30.0, "la noche 3")
	while m.screens.current != "ledger":
		if m.dialogs.is_open():
			m.dialogs.choose("sleep")
		await _wait(0.3)
	m.screens.press("next")
	await _until(func(): return m.dialogs.is_open(), 6.0, "la cuota de la noche 3")
	_expect(m.dialogs.option_ids() == ["pay"], "pagar la cuota")
	m.dialogs.choose("pay")
	await _wait(0.4)
	_expect(Game.debt > 0 and Game.late_marks == 1, "la regla blanda: deuda y LATE (%d cr, %d)" % [Game.debt, Game.late_marks])
	m.dialogs.choose("ok")
	await _until(func(): return _phase() == "MORNING" and Game.day == 4 and not m.busy, 12.0, "día 4")
	# la noche 10: la gala, sin tablero; Keep trading -> el día 11
	Season.debug_state(10, "good")
	m.open_shop_now()
	await _until(func(): return _phase() == "OPEN" and not m.busy, 8.0, "abrir el día 10")
	m.day.force_close()
	await _until(func(): return _phase() == "NIGHT", 30.0, "la noche 10")
	while m.screens.current != "ledger":
		if m.dialogs.is_open():
			m.dialogs.choose("sleep")
		await _wait(0.3)
	_expect(String(Game.last_summary.get("board_line", "")) == String(SeasonData.TEXT["signal_counting"]), "sin spoiler en el libro de la noche 10")
	var boards := int(m.night_boards)
	m.screens.press("next")
	await _until(func(): return _phase() == "MORNING" and Game.day == 11 and not m.busy, 20.0, "Keep trading: el día 11")
	_expect(m.galas_played == 1 and int(m.night_boards) == boards and Game.mode == "endless" and Game.ending_seen, "la gala una vez, sin tablero")
	m.show_closing()
	_expect(m.screens.current == "closing", "pantalla final (la vieja)")
	m.screens.press("title")
	await _until(func(): return _phase() == "TITLE", 8.0, "volver al título")
	Game.delete_save()
	print("SMOKE %s errors=%d frames=%d credits=%d" % ["ok" if m.errors == 0 else "FAIL", m.errors, m.frame, Game.credits])
	_quit(0 if m.errors == 0 else 1)

# ------------------------------------------------------------------ el bot de la campaña (--- SS2 SEASON)

var _bot_log := []
var _trace := OS.get_cmdline_user_args().has("--trace")
var _stars_by_day := {}      # día -> estrellas del tablero (la tabla de NOTES)
var _shelf_d8 := -1

## --demo=autoplay [--days=10] [--endless=2] [--bot=perfect|good|human|sloppy] [--seed=N] [--from=N] [--timescale=6]:
## juega la campaña entera por el flujo real (como un jugador: camina a cada estación y la usa; las pantallas de BENCH
## con su bot_play(); los diálogos de la temporada con dialogs.choose(); el tablero y la gala con auto). Errores: los
## del contrato y los del flujo (algo que no se abrió, un día que no terminó, un guardado que no vuelve igual, la
## cuota que no se cobró, la gala que no se abrió una vez la noche 10).
func _autoplay() -> void:
	Engine.time_scale = _timescale
	_watchdog(7200.0)   # (una máquina cargada: hasta 2 h reales)
	m.rank.auto = true
	m.gala.auto = true
	Game.delete_save()
	var last_day := mini(maxi(1, m.autoplay_days), SeasonData.LAST_DAY) if m.autoplay_days < 99 else SeasonData.LAST_DAY
	var stop_day := last_day + (_endless if last_day >= SeasonData.LAST_DAY else 0)
	m.show_title()
	await _wait(0.4)
	if _from > 1:
		# --from=N: una partida típica en la mañana del día N (Season.debug_state), guardada, y Continue
		Season.debug_state(_from, "human" if bot == "human" else ("sloppy" if bot == "sloppy" else "good"))
		Game.resume = "morning"
		Game.save_game()
		m.show_title()
		await _wait(0.3)
		m.screens.press("continue")
	else:
		m.screens.press("new")
		await _until(func(): return _phase() == "INTRO", 6.0, "la introducción")
		await _wait(1.5)
		m.screens.press("skip")
	var galas_before := int(m.galas_played)
	var start := Game.day if _from > 1 else 1
	for d in range(start, stop_day + 1):
		await _until(func(): return _phase() == "MORNING" and not m.busy and m.fade.color.a < 0.5, 20.0, "la mañana del día %d" % d)
		if _phase() != "MORNING":
			break
		_expect(Game.day == d, "día %d (Game.day=%d)" % [d, Game.day])
		if d > start:
			_check_reload(d)
		await _bot_morning()
		await _until(func(): return _phase() == "OPEN" and not m.busy, 30.0, "abrir el día %d" % d)
		if d == 8 and _from < 8:   # --- SS2 MERGE: con --from=8 el estante es el del estado típico (no lo llenó el bot)
			_shelf_d8 = Game.shelf.size()
			if bot == "good" and _shelf_d8 < 5:
				_err("el estante tiene %d cosas al abrir el día 8 (el bot good necesita >= 5)" % _shelf_d8)
		await _bot_open_day()
		await _bot_night()
		var s: Dictionary = Game.last_summary
		_expect(int(s.get("day", 0)) == d, "resumen del día %d" % d)
		var move: Dictionary = s.get("rank", {})
		_expect(int(move.get("pos", -1)) == Ranking.position(), "el puesto del tablero (%d) == Ranking.position() (%d)" % [int(move.get("pos", -1)), Ranking.position()])
		_stars_by_day[d] = int(s.get("day_stars", 0))
		var due_tonight := Season.dues_due(d)
		var boards_before := int(m.night_boards)
		var gala_before := int(m.galas_played)
		var ending := Ranking.ending_due()
		await _wait(0.5)
		m.screens.press("next")
		await _bot_night_chain(d)
		if due_tonight > 0:
			_expect(d in Season.state.get("dues_done", []), "la cuota de la noche %d se cobró" % d)
		if d == SeasonData.LAST_DAY:
			_expect(ending, "la noche 10 es la noche del cometa")
			_expect(int(m.galas_played) == gala_before + 1, "la gala se jugó una vez la noche 10 (%d)" % (int(m.galas_played) - gala_before))
			_expect(int(m.night_boards) == boards_before, "sin tablero de noche la noche 10")
		elif ending:
			_expect(int(m.night_boards) == boards_before, "sin tablero la noche de la corona")
		var line := "CAMPAIGN day=%d event=%s rank=%d stars=%d score=%d credits=%d dues=%s fittings=%d rep=%d tier=%s served=%d walkouts=%d" % [
			d, Season.event(d) if Season.event(d) != "" else "-", int(move.get("pos", 30)), int(s.get("day_stars", 0)), int(move.get("score", 0)),
			Game.credits, _dues_word(d), Game.fittings.size(), Game.rep, String(Season.rep_tier()["id"]), int(s.get("served", 0)), int(s.get("walkouts", 0))]
		print(line)
		print("ECON day=%d earned=%d repairs=%d sales=%d tips=%d events=%d spent=%d fittings_spent=%d repairs_n=%d sales_n=%d stars_avg=%.2f shelf=%d junk=%d refurb=%d after=%d asis=%d declined=%d missed=%d job_s=%d arrived=%d patched=%d racers=%d/%d" % [
			d, int(s.get("earned", 0)), int(s.get("repair_pay", 0)), int(s.get("sale_pay", 0)), int(s.get("tips", 0)), int(s.get("event_credits", 0)),
			int(s.get("spent", 0)), int(s.get("fittings_spent", 0)), int(s.get("repairs", 0)), int(s.get("sales", 0)),
			float(s.get("avg_stars_x10", 0)) / 10.0, Game.shelf.size(), Game.junk.size(), int(s.get("refurbished", 0)), int(s.get("after_hours", 0)),
			int(s.get("asis", 0)), int(s.get("declined", 0)), int(s.get("missed", 0)),
			int(s.get("job_secs", 0)) / maxi(1, int(s.get("repairs", 0)) + int(s.get("failed", 0))), int(s.get("arrived", 0)), int(s.get("patched", 0)),
			int(s.get("racers", 0)), int(s.get("racer_stars", 0))])
		if _phase() == "TITLE":
			break
	_expect(int(m.galas_played) - galas_before <= 2, "la gala se jugó %d veces" % (int(m.galas_played) - galas_before))
	# el final: menú -> volver al título
	await _until(func(): return _phase() == "MORNING" and not m.busy and m.fade.color.a < 0.5, 20.0, "la última mañana")
	if _phase() == "MORNING":
		m.open_menu()
		await _wait(0.2)
		_expect(m.dialogs.is_open(), "el menú")
		m.dialogs.choose("title")
		await _until(func(): return _phase() == "TITLE", 8.0, "volver al título")
	var tt := Game.totals()
	print("CAMPAIGN end bot=%s seed=%d rank=%d award=%s dues_on_time=%d/3 fittings=%d sign=%d cores=%d score=%d best_rank=%d errors=%d" % [
		bot, _seed_arg, Ranking.position(), String(Ranking.award().get("id", "")), Season.dues_on_time(), Game.fittings.size(),
		Game.sign_points, int(Game.flag("cores", 0)), Ranking.score(), int(Ranking.get("best_pos") if Ranking.get("best_pos") != null else 0), m.errors])
	var st: Array = []
	for d in _stars_by_day:
		st.append("%d:%d" % [d, int(_stars_by_day[d])])
	print("STARS bot=%s seed=%d %s" % [bot, _seed_arg, " ".join(st)])
	print("FLAGS %s" % JSON.stringify(Game.flags))
	Game.delete_save()
	print("AUTOPLAY done days=%d errors=%d pace=%s bot=%s log=%s" % [_stars_by_day.size(), m.errors, pace, bot, str(_bot_log)])
	_quit(0 if m.errors == 0 else 1)

func _dues_word(d: int) -> String:
	if Season.dues_of(d) <= 0:
		return "-"
	return "paid" if d in Game.dues_paid else "late"

## La partida de esta mañana se guardó: cargarla da lo mismo (créditos, piezas, mejoras, puesto, marcas).
func _check_reload(d: int) -> void:
	var before := {"credits": Game.credits, "parts": Game.parts_total(), "fittings": Game.fittings.duplicate(),
		"pos": Ranking.position(), "score": Ranking.score(), "flags": JSON.stringify(Game.flags), "day": Game.day,
		"pods": JSON.stringify(Game.pods_today), "rep": Game.rep}
	if not (Game.can_continue() and Game.load_game()):
		_err("Continue el día %d: no cargó" % d)
		return
	var after := {"credits": Game.credits, "parts": Game.parts_total(), "fittings": Game.fittings.duplicate(),
		"pos": Ranking.position(), "score": Ranking.score(), "flags": JSON.stringify(Game.flags), "day": Game.day,
		"pods": JSON.stringify(Game.pods_today), "rep": Game.rep}
	for k in before:
		if str(before[k]) != str(after[k]):
			_err("Continue el día %d: %s %s != %s" % [d, k, str(before[k]), str(after[k])])
	_expect(Game.resume == "morning", "Continue el día %d: resume=%s" % [d, Game.resume])

## Responde lo que esté abierto mientras espera algo (momentos, la cuota, después de cerrar, el banco de noche...).
func _bot_any_ui() -> bool:
	if _trace and (m.dialogs.is_open() or (m.bench != null and m.bench.is_open())):
		_tr("ui dialog=%s %s" % [str(m.dialogs.is_open()), str(m.dialogs.option_ids()) if m.dialogs.is_open() else ""])
	if m.bench != null and m.bench.is_open():
		await _bot_ui(m.bench, "bench")
		return true
	if m.haggle != null and m.haggle.is_open():
		await _bot_ui(m.haggle, "haggle")
		return true
	if m.pod_ui != null and m.pod_ui.is_open():
		await _bot_ui(m.pod_ui, "pod", true)
		return true
	if m.dialogs.is_open():
		await _wait(0.3)
		if m.dialogs.is_open():
			_bot_dialog()
		return true
	return false

## La mañana: los momentos de historia, las cápsulas, Mags (+ lo de "tal cual"), Dolly, el tablón (el día 2), abrir.
func _bot_morning() -> void:
	var st: StreetWorld = m.street
	# los avisos y los momentos de la mañana (aparecen solos al rato): esperarlos y contestarlos
	var t := 0.0
	while t < 40.0:
		if await _bot_any_ui():
			t = 0.0
			continue
		if Season.beats(Game.day, "morning").is_empty() and t > 1.0:
			break
		await _wait(0.25)
		t += 0.25
	# Dolly primero (las mejoras son para toda la temporada), con la reserva para la próxima cuota; la víspera de
	# Bronzemoon los que guardan el estante (eve_hold) van primero a Mags y a las cápsulas y a Dolly después
	var festival_eve := Season.event(Game.day + 1) == "festival"
	var stock_first := festival_eve and bool(prof.get("eve_hold", false))
	if not stock_first:
		await _bot_dolly()
	if festival_eve:
		await _bot_mags()
	# las cápsulas según el perfil (la de regalo siempre; una o dos: la segunda si sobra para una pieza y un margen)
	var tries := 0
	while not Game.pods_today.is_empty() and String(prof["pods"]) != "none" and tries < 3:
		tries += 1
		var has_gift := false
		for p in Game.pods_today:
			if String(p.get("kind", "")) == "charity":
				has_gift = true
		if tries >= 2 and not has_gift and (String(prof["pods"]) != "best" or Game.credits < 60):
			break
		if not await _walk("pods"):
			break
		m.use_station("pods")
		await _wait(0.2)
		if not m.dialogs.is_open():
			if Game.credits >= 20:
				_err("el puesto de cápsulas no abrió su diálogo")
			break
		var best := ""
		var best_w := -1
		var gift := false
		for i in Game.pods_today.size():
			var p: Dictionary = Game.pods_today[i]
			if String(p.get("kind", "")) == "charity":
				best = "pod%d" % i
				gift = true
				break
			var ask := int(round(float(p.get("price", 30)) * float(BenchData.HAGGLE["duneraker"]["ask"])))
			if _dues_guard(int(p.get("price", 30))):
				continue
			if String(prof["pods"]) == "first":
				if Game.credits >= ask:
					best = "pod%d" % i
					break
			elif int(p.get("weight", 1)) > best_w and Game.credits >= int(p.get("price", 30)) + 4:
				best_w = int(p.get("weight", 1))
				best = "pod%d" % i
		m.dialogs.choose(best if best != "" else "later")
		if best == "":
			break
		if not gift:
			await _bot_ui(m.haggle, "haggle")
		await _bot_ui(m.pod_ui, "pod", true)
		_bot_log.append("pod d%d %s" % [Game.day, "gift" if gift else best])
	if not festival_eve:
		await _bot_mags()
	if stock_first:
		await _bot_dolly()
	# el tablón de anuncios (el calendario) una vez, el día 2; la vecina el día 3
	if Game.day == 2 and await _walk("board"):
		m.use_station("board")
		await _wait(0.3)
		_expect(m.dialogs.is_open() and String(m.dialogs.spec.get("kind", "")) == "calendar", "el calendario del tablón")
		m.dialogs.choose("close")
	if Game.day == 3 and await _walk("rival"):
		m.use_station("rival")
		await _wait(0.3)
		_expect(m.dialogs.is_open(), "la visita a Shine Again")
		m.dialogs.choose("ok")
	while await _bot_any_ui():
		pass
	if await _walk("door"):
		m.use_station("door")
	else:
		_err("no llegó a la puerta")

func _tr(msg: String) -> void:
	if _trace:
		print("TRACE d%d %s %s" % [Game.day, _phase(), msg])

## Dolly: las mejoras según el perfil, guardando para la próxima cuota.
func _bot_dolly() -> void:
	if Season.is_unlocked("vendor") and String(prof.get("fittings", "")) != "":
		var cand := _fitting_to_buy()
		if cand != "":
			if await _walk("fittings"):
				m.use_station("fittings")
				await _wait(0.3)
				if m.dialogs.is_open() and String(m.dialogs.spec.get("kind", "")) == "fittings":
					var bought := 0
					while cand != "" and (String(prof["fittings"]) != "max1" or bought < 1):
						if not m.dialogs.buy_fitting(cand):
							_err("Dolly no vendió %s con %d cr" % [cand, Game.credits])
							break
						bought += 1
						_bot_log.append("fit d%d %s" % [Game.day, cand])
						await _wait(0.2)
						cand = _fitting_to_buy()
					m.dialogs.choose("close")
				else:
					_err("el patio de Dolly no abrió")

## Mags: las piezas que faltan (con margen) y lo de "tal cual" si el estante está flaco (o la víspera de Bronzemoon).
func _bot_mags() -> void:
	if bool(prof["parts"]) or bool(prof.get("asis", false)):
		if await _walk("parts"):
			m.use_station("parts")
			await _wait(0.2)
			if m.dialogs.is_open():
				if bool(prof["parts"]) and Game.credits >= 45:
					var stock: Array = []
					for e in m.dialogs.spec.get("stock", []):
						stock.append(String(e["part"]))
					for k in 2:
						var want := ""
						for p in ["cell", "chip", "lens", "tuner", "coil", "servo", "fan", "speaker", "nozzle", "drum", "coingate", "gyro", "needle"]:
							if p in stock and (want == "" or Game.part_count(p) < Game.part_count(want)):
								want = p
						if want == "" or Game.part_count(want) > 0 or Game.credits < 40 + BenchData.part_price(want) + _reserve_now() * 0.2:
							break
						if not m.dialogs.buy_part(want):
							_err("no se pudo comprar %s con %d cr" % [want, Game.credits])
						await _wait(0.2)
				# lo de "tal cual": con el estante flaco, o la víspera de Bronzemoon (Kettle: "Fill the shelf!")
				if bool(prof.get("asis", false)) and (Game.shelf.size() < 3 or Season.event(Game.day + 1) == "festival"):
					var asis: Array = m.dialogs.spec.get("asis", [])
					for k in asis.size():
						if Game.shelf.size() + Game.junk.size() >= (7 if Season.event(Game.day + 1) == "festival" else 4):
							break
						var cushion := 0 if Season.event(Game.day + 1) == "festival" else 30 + int(_reserve_now() * 0.3)
						if Game.credits >= int(asis[k]["price"]) + cushion and not _dues_guard(int(asis[k]["price"])):
							if m.dialogs.buy_asis(k):
								_bot_log.append("asis d%d %s" % [Game.day, String(asis[k]["item"])])
						await _wait(0.2)
				m.dialogs.choose("close")
			else:
				_err("el puesto de Mags no abrió")

## Camina a una estación de la calle o la tienda (contestando lo que se abra por el camino).
func _walk(id: String) -> bool:
	_tr("walk " + id)
	for k in 3:
		while await _bot_any_ui():
			pass
		if m.world == null:
			return false
		if await m.world.walker.go_station(id):
			if not m.modal_open():
				return true
		await _wait(0.2)
	return false

## Cuánto guardar para la próxima cuota: la cuota menos el 70 % de lo que espera ganar hasta esa noche (§8.14).
## La noche de la cuota (3, 6, 9) los perfiles que planean (dues_guard) no gastan en cápsulas ni en lo de "tal cual"
## lo que les haga falta esta noche (la cuota menos el 70 % de lo que esperan ganar hoy): el HUD la muestra todo el día.
func _dues_guard(price: int) -> bool:
	if not bool(prof.get("dues_guard", false)):
		return false
	if int(Season.next_dues()["night"]) != Game.day:
		return false
	return float(Game.credits - price) < _reserve_now()

func _reserve_now() -> float:
	var nd := Season.next_dues()
	if int(nd["night"]) <= 0:
		return 0.0
	var days_left := maxi(1, int(nd["night"]) - Game.day + 1)
	return maxf(0.0, float(int(nd["amount"]) + int(nd["debt"])) - 0.7 * float(prof.get("income", 100.0)) * days_left)

## La próxima mejora que compraría este perfil ("" = ninguna hoy).
func _fitting_to_buy() -> String:
	var mode := String(prof.get("fittings", "order"))
	for f in Season.fittings_on_sale():
		if bool(f["owned"]) or bool(f["locked"]):
			continue
		if mode == "basic" and not (String(f["id"]) in ["samovar", "seats"]):
			continue
		if Game.credits - int(f["cost"]) >= _reserve_now() + 40.0:   # (40: lo de las cápsulas de hoy)
			return String(f["id"])
		return ""   # en orden: si la primera que falta no alcanza, espera
	return ""

## El día abierto: atender el mostrador, el banco, el té, lo roto de las cápsulas, cerrar antes si se puede.
func _bot_open_day() -> void:
	var sh: ShopWorld = m.shop
	var guard := 0
	while _phase() == "OPEN":
		guard += 1
		if guard > 9000:
			_err("el día abierto no termina")
			return
		await _wait(0.25)
		if _trace and guard % 20 == 0:
			_tr("open busy=%s menu=%s job=%s dlg=%s bench=%s line=%d counter=%s min=%d running=%s closing=%s pend=%d walking=%s cur=%s" % [
				str(m.busy), str(m.menu_open), str(m.job.get("stage", "")), str(m.dialogs.is_open()), str(m.bench.is_open()),
				m.day.line_count(), str(m.day.counter.get("state", "-")), m.day.minutes(), str(m.day.running), str(m.day.closing),
				m.day.pending_arrivals(), str(sh.walker.is_walking()), sh.walker.current])
		# (un momento de historia abre su diálogo con busy = true: se contesta igual, como lo haría una persona)
		if m.dialogs.is_open():
			await _wait(0.2)
			if m.dialogs.is_open():
				_bot_dialog()
			continue
		if m.busy or m.menu_open:
			continue
		if m.bench.is_open():
			await _bot_ui(m.bench, "bench")
			continue
		if m.haggle.is_open():
			await _bot_ui(m.haggle, "haggle")
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
				await _wait(float(prof["react"]) * _rng.randf_range(0.7, 1.3))
			if await sh.walker.go_station("counter"):
				m.use_station("counter")
			continue
		# el té: con la fila larga
		if bool(prof["tea"]) and m.day.line_count() >= 2 and String(m.station_verb("tea")[0]) == "Tea":
			if await sh.walker.go_station("tea"):
				m.use_station("tea")
				_bot_log.append("tea day %d" % Game.day)
			continue
		# cerrar antes (desde las 4 PM, sin nadie más)
		if bool(prof.get("close", false)) and m._can_close_early():
			if await sh.walker.go_station("counter"):
				m.use_station("counter")
				await _wait(0.2)
				if m.dialogs.is_open():
					m.dialogs.choose("close")
					_bot_log.append("close d%d %s" % [Game.day, Hud.clock_text(m.day.minutes())])
			continue
		# lo roto de las cápsulas: si no hay nadie en camino al mostrador
		if bool(prof["refurb"]) and not Game.junk.is_empty() and m.day.counter.is_empty() and m.day.line_count() == 0 and not m.day.closing:
			if await sh.walker.go_station("bench"):
				m.use_station("bench")
			continue
		# nada que hacer: esperar junto al mostrador
		if sh.walker.current != "counter" and not sh.walker.is_walking():
			sh.walker.go_station("counter")

## La noche hasta el libro de cuentas: después de cerrar (los arreglos de noche según el perfil).
func _bot_night() -> void:
	var t := 0.0
	var fixed := 0
	while t < 120.0:
		if _phase() == "NIGHT" and m.screens.current == "ledger":
			return
		if m.bench != null and m.bench.is_open():
			await _bot_ui(m.bench, "bench")
			fixed += 1
			t = 0.0
			continue
		if m.dialogs.is_open():
			await _wait(0.3)
			if not m.dialogs.is_open():
				continue
			var ids: Array = m.dialogs.option_ids()
			if "sleep" in ids:
				var pick := "sleep"
				if fixed < int(prof.get("after", 2)) + int(SeasonData.AFTER_HOURS_BONUS.get(Game.day, 0)):
					for id in ids:
						if String(id).begins_with("j"):
							pick = String(id)
							break
				m.dialogs.choose(pick)
			else:
				_bot_dialog()
			t = 0.0
			continue
		await _wait(0.25)
		t += 0.25
	_err("el libro de cuentas del día %d no apareció (fase %s)" % [Game.day, _phase()])

## Después del libro de cuentas: la cuota, el tablero (auto), los momentos de la noche, la gala, hasta la mañana.
func _bot_night_chain(d: int) -> void:
	var t := 0.0
	while t < 90.0:
		if (_phase() == "MORNING" and Game.day == d + 1 and not m.busy) or _phase() == "TITLE":
			return
		if m.dialogs.is_open():
			await _wait(0.3)
			if m.dialogs.is_open():
				_bot_dialog()
			t = 0.0
			continue
		await _wait(0.25)
		t += 0.25
	_err("la noche %d no terminó (fase %s)" % [d, _phase()])

## Elige en el diálogo abierto como un jugador razonable (los momentos: la primera opción o al azar, según el perfil).
func _bot_dialog() -> void:
	var ids: Array = m.dialogs.option_ids()
	var kind := String(m.dialogs.spec.get("kind", ""))
	if kind in ["info", "parts", "fittings", "calendar"]:
		m.dialogs.choose("close")
		return
	if kind == "menu":
		m.dialogs.choose("resume")
		return
	if String(m.dialogs.spec.get("beat", "")) != "":
		var pick: String = ids[0] if not ids.is_empty() else ""
		if String(prof.get("beats", "first")) == "random" and ids.size() > 1:
			pick = String(ids[_rng.randi() % ids.size()])
		_bot_log.append("beat %s=%s" % [String(m.dialogs.spec["beat"]), pick])
		m.dialogs.choose(pick)
		return
	for want in ["pay", "ok", "close", "repair", "order"]:   # --- POLISH FIX (F4): "Fix theirs instead"
		if want in ids:
			m.dialogs.choose(want)
			return
	# la víspera de Bronzemoon el bueno guarda el estante para mañana (60 % compradores, venta x1.2; el calendario lo dice)
	var eve_hold := bool(prof.get("eve_hold", false)) and Season.event(Game.day + 1) == "festival" and Game.shelf.size() <= 5 and "none" in ids
	for id in ids:
		if String(id).begins_with("sell") and not eve_hold:
			m.dialogs.choose(id)
			return
	if eve_hold and ids.any(func(x): return String(x).begins_with("sell")):
		_bot_log.append("eve hold d%d" % Game.day)
		m.dialogs.choose("none")
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
	var w := float(prof["wait"].get(what, 0.0))
	if what == "bench" and m.job.get("item", "") != "" and Season.family_jobs(String(m.job["item"])) < 2:
		w *= float(prof.get("think_first", 1.0))   # el humano piensa más los dos primeros de cada familia
	if pace == "real":
		await _wait(float(PACE_REAL.get(what, 2.0)) * _rng.randf_range(0.8, 1.2))
	elif w > 0.0:
		await _wait(w * _rng.randf_range(0.85, 1.15))
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
