extends Node
## El estado de la partida de Secondhand Stars (autoload "Game"): día, créditos, reputación, piezas, el estante de
## cosas reparadas, las estadísticas del día y el guardado en JSON.
## --- SS SEED: la semilla escribió el CONTRATO (SS_BRIEF §3); CORE es el dueño de este archivo y lo completa (el
## flujo del día, las reglas). Las otras líneas solo lo usan a través de esta API:
##   variables:  day, credits, rep, dues_goal (300), parts {part_id: n}, shelf [{"item", "stars"}], today {...}
##   funciones:  has_part(id), take_part(id) -> bool, add_part(id, n := 1), add_credits(n), save_game(), load_game()
## Extras de la semilla (documentados en NOTES.txt): junk (cosas rotas de las cápsulas, para reparar y vender),
## add_rep(), spend_credits(), shelf_add() / shelf_take(), stat(), reset_today(), next_day(), dues_met(), volúmenes.
## Reglas de quién toca qué: BenchUI llama a take_part() al cambiar una pieza (y lo cuenta en parts_used);
## HaggleUI y PodUI NO tocan Game (quien los abre aplica el trato: créditos, piezas, el estante).
## --- SS CORE: lo nuevo (bloques marcados): la partida entera de 3 días (las cápsulas de cada mañana, los puntos del
## cartel de la estrella, el historial de cada día para la pantalla final, dónde sigue "Continue"), los consejos ya
## vistos y los ajustes de volumen en su propio archivo (sobreviven a una partida nueva).

signal credits_changed(total: int, delta: int)
signal rep_changed(total: int, delta: int)
signal parts_changed
signal shelf_changed
signal junk_changed
signal day_started(day: int)

const SAVE_PATH := "user://secondhand_save.json"
const SETTINGS_PATH := "user://secondhand_settings.json"   # --- SS CORE
const SAVE_VERSION := 3   # --- SS2: 3 = la temporada (mejoras, cuotas en partes, historias, el tablero) (2 = el prototipo)

var day := 1
var credits := 0
var rep := 0
var dues_goal := 300
var parts := {}            # part_id -> cuántas hay en el cajón
var shelf: Array = []      # cosas reparadas a la venta: [{"item": "radio", "stars": 2}, ...]
var junk: Array = []       # cosas rotas sin reparar (de las cápsulas): [{"item": "radio", "fault": "tuner"}, ...]
var today := {}            # estadísticas del día (ver reset_today)
# ajustes (se guardan con la partida y en SETTINGS_PATH)
var music_volume := 0.8
var sfx_volume := 0.9
# --- SS CORE: la partida
var run_seed := 0          # semilla de la partida (las cápsulas de los días 2 y 3 salen de aquí: Continue = las mismas)
var sign_points := 0       # puntas encendidas del cartel de la estrella (una por día bueno; 0..Data.SIGN_POINTS)
var resume := "morning"    # dónde sigue "Continue": "morning" (la calle) | "open" (la tienda a las 9) | "done" (terminó)
var intro_seen := false
var pods_today: Array = [] # las cápsulas que quedan en el puesto de Raker esta mañana
var history: Array = []    # las estadísticas de cada día cerrado (la pantalla final las suma)
var tips_seen := {}        # consejos del tutorial ya mostrados
var last_summary := {}     # el libro de cuentas de la última noche (para mostrarlo otra vez)
# --- end SS CORE
# --- SS2 SEASON
var mode := "campaign"        # "campaign" (días 1..SeasonData.LAST_DAY) | "endless" (después de la noche del cometa)
var fittings: Array = []      # ids comprados (SeasonData.FITTINGS), en orden de compra
var fittings_new: Array = []  # comprados y todavía no mostrados (se revelan al abrir la tienda)
var dues_paid: Array = []     # noches en que se pagó a tiempo: [3, 6]
var debt := 0                 # lo que quedó debiendo (+10 %): se suma a la próxima cuota
var late_marks := 0           # cuotas atrasadas (el sello LATE)
var flags := {}               # hilos de historia (§5.5)
var beats_seen := {}          # beat_id -> true
var unlocked := {}            # id -> día en que se abrió ("New today")
var ending_seen := false      # la noche del cometa de la noche 10 ya se jugó
var crown_seen := false       # la versión campeona ya se jugó (en la noche 10, o la primera noche #1 del modo sin fin)
var charity_day := -99        # último día con cápsula de regalo
var migrated_from := 0        # versión de la partida cargada (2 = el prototipo): la nota, una vez
# --- end SS2 SEASON

func _ready() -> void:
	load_settings()   # --- SS CORE
	new_game_state()

## Partida nueva: día 1, los créditos y las piezas de partida (Data.START_*), estante vacío.
func new_game_state() -> void:
	day = 1
	credits = Data.START_CREDITS
	rep = 0
	dues_goal = Data.DUES_GOAL
	parts = {}
	for id in Data.START_PARTS:
		parts[id] = int(Data.START_PARTS[id])
	shelf = []
	# --- SS CORE: lo que ya estaba en el estante, la semilla, el cartel apagado, el historial vacío
	for e in Data.START_SHELF:
		shelf.append({"item": String(e["item"]), "stars": int(e["stars"])})
	run_seed = randi() % 1000000
	sign_points = 0
	resume = "morning"
	intro_seen = false
	history = []
	tips_seen = {}
	last_summary = {}
	# --- end SS CORE
	junk = []
	# --- SS2 SEASON: la temporada desde cero (Season y Ranking arman sus datos en _init: se pueden llamar ya)
	mode = "campaign"
	fittings = []
	fittings_new = []
	dues_paid = []
	debt = 0
	late_marks = 0
	flags = {}
	beats_seen = {}
	unlocked = {}
	ending_seen = false
	crown_seen = false
	charity_day = -99
	migrated_from = 0
	Season.reset()
	Ranking.reset(run_seed)
	# --- end SS2 SEASON
	reset_today()
	roll_pods()   # --- SS CORE
	_update_dues_goal()   # --- SS2 SEASON

# ------------------------------------------------------------------ piezas

func has_part(id: String) -> bool:
	return int(parts.get(id, 0)) > 0

func part_count(id: String) -> int:
	return int(parts.get(id, 0))

## Saca una pieza del cajón. false si no hay (entonces el banco hace un "parche").
func take_part(id: String) -> bool:
	if not has_part(id):
		return false
	parts[id] = int(parts[id]) - 1
	if parts[id] <= 0:
		parts.erase(id)
	stat("parts_used")
	parts_changed.emit()
	return true

func add_part(id: String, n := 1) -> void:
	if n <= 0:
		return
	parts[id] = int(parts.get(id, 0)) + n
	parts_changed.emit()

## --- SS CORE: cuántas piezas hay en el cajón (todas).
func parts_total() -> int:
	var n := 0
	for id in parts:
		n += int(parts[id])
	return n

# ------------------------------------------------------------------ créditos y reputación

## Suma (o resta, con n < 0) créditos. Lo ganado y lo gastado quedan en today ("earned" / "spent").
func add_credits(n: int) -> void:
	if n == 0:
		return
	credits += n
	if n > 0:
		stat("earned", n)
	else:
		stat("spent", -n)
	credits_changed.emit(credits, n)

func can_afford(n: int) -> bool:
	return credits >= n

## Paga n créditos si alcanzan. false (y nada cambia) si no alcanzan.
func spend_credits(n: int) -> bool:
	if n < 0 or credits < n:
		return false
	add_credits(-n)
	return true

func add_rep(n: int) -> void:
	if n == 0:
		return
	rep += n
	rep_changed.emit(rep, n)

# ------------------------------------------------------------------ estante y cosas rotas

func shelf_add(item: String, stars: int) -> void:
	shelf.append({"item": item, "stars": clampi(stars, 0, 3)})
	shelf_changed.emit()

## Saca la cosa i del estante (vendida). {} si no existe.
func shelf_take(i: int) -> Dictionary:
	if i < 0 or i >= shelf.size():
		return {}
	var d: Dictionary = shelf[i]
	shelf.remove_at(i)
	shelf_changed.emit()
	return d

## Índice de la primera cosa del estante de ese tipo (-1 si no hay).
func shelf_find(item: String) -> int:
	for i in shelf.size():
		if shelf[i].get("item", "") == item:
			return i
	return -1

func add_junk(item: String, fault: String) -> void:
	junk.append({"item": item, "fault": fault})
	junk_changed.emit()

func take_junk(i: int) -> Dictionary:
	if i < 0 or i >= junk.size():
		return {}
	var d: Dictionary = junk[i]
	junk.remove_at(i)
	junk_changed.emit()
	return d

# ------------------------------------------------------------------ el día

## Las estadísticas del día (el libro de cuentas de la noche las lee). CORE puede agregar claves.
func reset_today() -> void:
	today = {
		"customers": 0,       # clientes que llegaron al mostrador
		"repairs": 0,         # reparaciones entregadas
		"stars": 0,           # estrellas sumadas en esas reparaciones
		"sales": 0,           # cosas vendidas del estante
		"declined": 0,        # "no puedo" en el mostrador
		"walkouts": 0,        # se fueron sin paciencia
		"patience_lost": 0,   # --- SS CORE: clientes perdidos por esperar (se cansaron + vieron la fila llena)
		"parts_used": 0,
		"earned": 0,
		"spent": 0,
		"tea": false,         # el té de Kettle (una vez al día)
		"credits_start": credits,
		"rep_start": rep,
		# --- SS CORE
		"arrived": 0,         # entraron (o se asomaron) por la puerta
		"missed": 0,          # vieron la fila llena y se fueron
		"failed": 0,          # reparaciones que no salieron (Nell se rindió)
		"refurbished": 0,     # cosas rotas de las cápsulas reparadas y puestas en el estante
		"pods": 0,            # cápsulas compradas
		"tips": 0,            # propinas
		"repair_pay": 0,      # lo cobrado por reparaciones
		"sale_pay": 0,        # lo cobrado por ventas
		# --- end SS CORE
		# --- SS2 SEASON (§8.4: todos enteros, por stat())
		"served": 0,          # reparaciones entregadas (bien) + ventas hechas
		"repair_stars": 0,    # estrellas de las reparaciones entregadas
		"sale_stars": 0,      # estrellas de lo vendido del estante
		"event_stars": 0,     # lo de la temporada (inspección, carrera, banda, la caja...)
		"event_credits": 0,   # (créditos de los eventos: el libro de cuentas)
		"racers": 0,          # propulsores de los corredores entregados antes de las 2 PM
		"racer_stars": 0,
		"after_hours": 0,     # arreglados de noche, después de cerrar
		"patched": 0,         # reparaciones con parche
		"tea_used": 0,        # tés servidos (el viejo "tea" sigue en true si > 0)
		"fittings_spent": 0,  # lo gastado en mejoras
		"asis": 0,            # cosas compradas "tal cual"
		"dues_due": 0,
		"dues_paid": 0,
		"dues_short": 0,
		"clean": 0,           # día limpio: nadie se fue, nadie se perdió, nada falló
		# --- end SS2 SEASON
	}

## Suma n a una estadística numérica del día.
func stat(key: String, n := 1) -> void:
	today[key] = int(today.get(key, 0)) + n

## Pasa al día siguiente (main.gd decide cuándo).
func next_day() -> void:
	day += 1
	reset_today()
	roll_pods()   # --- SS CORE
	_update_dues_goal()   # --- SS2 SEASON
	day_started.emit(day)

## --- SS2 SEASON: la campaña termina en el día SeasonData.LAST_DAY (después, el modo sin fin no tiene último día).
func is_last_day() -> bool:
	return is_campaign() and day >= SeasonData.LAST_DAY

func is_campaign() -> bool:
	return mode == "campaign"

func has_fitting(id: String) -> bool:
	return id in fittings

## Una mejora comprada: queda para revelarla cuando abra la tienda (fittings_new).
func add_fitting(id: String) -> void:
	if id in fittings:
		return
	fittings.append(id)
	fittings_new.append(id)

func flag(key: String, default = null):
	return flags.get(key, default)

func set_flag(key: String, value) -> void:
	flags[key] = value

## La barra DUES del HUD: la próxima cuota + lo que se debe.
func _update_dues_goal() -> void:
	var nd: Dictionary = Season.next_dues()
	dues_goal = maxi(1, int(nd.get("amount", 0)) + int(nd.get("debt", debt)))
# --- end SS2 SEASON

## Cuánto de la cuota del puerto (dock dues) cubren los créditos (0..1).
func dues_progress() -> float:
	return clampf(float(credits) / float(maxi(1, dues_goal)), 0.0, 1.0)

func dues_met() -> bool:
	return credits >= dues_goal

# --- SS CORE: la mañana, el cierre del día y la partida -------------------------------------------------------------

## Las cápsulas de esta mañana en el puesto de Raker: las del día 1 fijas (Data.DAY1_PODS); las demás, sorteadas con
## la semilla de la partida, así Continue ofrece las mismas. --- SS2 SEASON: las arma Season.pods_for (solo familias
## abiertas; el naufragio del día 7, la Gran Caída del día 10; ninguna el día de la Scour).
func roll_pods() -> void:
	pods_today = Season.pods_for(day)

## Cierra el día: arma el resumen del libro de cuentas, decide si fue un día bueno (enciende una punta del cartel) y
## lo guarda en el historial. Devuelve el resumen.
func close_day() -> Dictionary:
	var s := today.duplicate(true)
	s["day"] = day
	s["credits"] = credits
	s["rep"] = rep
	s["net"] = credits - int(today.get("credits_start", credits))
	s["rep_delta"] = rep - int(today.get("rep_start", rep))
	s["avg_stars_x10"] = int(round(10.0 * float(today.get("stars", 0)) / float(maxi(1, int(today.get("repairs", 0))))))
	var good := int(s["rep_delta"]) >= Data.GOOD_DAY_REP
	s["good"] = good
	# --- SS2 SEASON: el día limpio, la noche del tablero, las puntas del cartel por hitos (no por días buenos), el
	# tramo de reputación nuevo
	var clean := int(today.get("walkouts", 0)) == 0 and int(today.get("missed", 0)) == 0 and int(today.get("failed", 0)) == 0
	today["clean"] = 1 if clean else 0
	s["clean"] = today["clean"]
	var tier_before := String(Season.rep_tier(int(today.get("rep_start", rep)))["id"])
	var tier_now: Dictionary = Season.rep_tier()
	if String(tier_now["id"]) != tier_before and int(tier_now["rep"]) > int(Season.rep_tier(int(today.get("rep_start", rep)))["rep"]):
		s["tier"] = String(tier_now["id"])
	var sign_before := sign_points
	var move: Dictionary = Ranking.commit_day()
	s["rank"] = move.duplicate(true)
	s["day_stars"] = int(move.get("stars", 0))
	sign_points = clampi(maxi(sign_points, Ranking.milestone_points()), 0, Data.SIGN_POINTS)
	s["sign_new"] = sign_points if sign_points > sign_before else 0
	s["sign_points"] = sign_points
	var nd: Dictionary = Season.next_dues()
	s["dues_tonight"] = Season.dues_due(day)
	s["dues_next"] = nd.duplicate()
	s["dues"] = dues_goal
	s["dues_met"] = credits >= dues_goal
	s["mode"] = mode
	# --- end SS2 SEASON
	history.append(s)
	last_summary = s
	return s

## Los totales de la partida (la pantalla final).
func totals() -> Dictionary:
	var t := {"repairs": 0, "stars": 0, "sales": 0, "earned": 0, "spent": 0, "walkouts": 0, "missed": 0,
		"customers": 0, "arrived": 0, "refurbished": 0, "pods": 0, "tips": 0, "good_days": 0, "best_day": 0, "best_net": -99999,
		"season_stars": 0, "best_stars": 0, "best_stars_day": 0, "after_hours": 0, "served": 0}   # --- SS2 SEASON
	for s in history:
		for k in ["repairs", "stars", "sales", "earned", "spent", "walkouts", "missed", "customers", "arrived",
				"refurbished", "pods", "tips", "after_hours", "served"]:
			t[k] = int(t[k]) + int(s.get(k, 0))
		if bool(s.get("good", false)):
			t["good_days"] = int(t["good_days"]) + 1
		if int(s.get("net", 0)) > int(t["best_net"]):
			t["best_net"] = int(s.get("net", 0))
			t["best_day"] = int(s.get("day", 0))
		# --- SS2 SEASON: las estrellas de la temporada y el mejor día del tablero
		t["season_stars"] = int(t["season_stars"]) + int(s.get("day_stars", 0))
		if int(s.get("day_stars", 0)) > int(t["best_stars"]):
			t["best_stars"] = int(s.get("day_stars", 0))
			t["best_stars_day"] = int(s.get("day", 0))
	t["credits"] = credits
	t["rep"] = rep
	t["sign_points"] = sign_points
	t["dues_met"] = dues_met()
	# --- SS2 SEASON
	t["fittings"] = fittings.size()
	t["dues_on_time"] = Season.dues_on_time()
	t["position"] = Ranking.position()
	t["score"] = Ranking.score()
	t["cores"] = int(flag("cores", 0))
	# --- end SS2 SEASON
	return t

## Un consejo del tutorial se muestra una sola vez: true la primera vez que se pide.
func tip_once(key: String) -> bool:
	if tips_seen.has(key):
		return false
	tips_seen[key] = true
	return true
# --- end SS CORE

# ------------------------------------------------------------------ guardado (JSON en user://)

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"day": day,
		"credits": credits,
		"rep": rep,
		"dues_goal": dues_goal,
		"parts": parts.duplicate(),
		"shelf": shelf.duplicate(true),
		"junk": junk.duplicate(true),
		"today": today.duplicate(true),
		"settings": {"music_volume": music_volume, "sfx_volume": sfx_volume},
		# --- SS CORE
		"run_seed": run_seed,
		"sign_points": sign_points,
		"resume": resume,
		"intro_seen": intro_seen,
		"pods_today": pods_today.duplicate(true),
		"history": history.duplicate(true),
		"tips_seen": tips_seen.duplicate(),
		"last_summary": last_summary.duplicate(true),
		# --- end SS CORE
		# --- SS2 SEASON
		"mode": mode,
		"fittings": fittings.duplicate(),
		"fittings_new": fittings_new.duplicate(),
		"dues_paid": dues_paid.duplicate(),
		"debt": debt,
		"late_marks": late_marks,
		"flags": flags.duplicate(true),
		"beats_seen": beats_seen.duplicate(),
		"unlocked": unlocked.duplicate(),
		"ending_seen": ending_seen,
		"crown_seen": crown_seen,
		"charity_day": charity_day,
		"season": Season.save_data(),
		"rank": Ranking.save_data(),
		# --- end SS2 SEASON
	}

## Carga un diccionario guardado (JSON: los números llegan como float y se pasan a int).
func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	credits = int(d.get("credits", Data.START_CREDITS))
	rep = int(d.get("rep", 0))
	dues_goal = int(d.get("dues_goal", Data.DUES_GOAL))
	parts = {}
	var p: Dictionary = d.get("parts", {})
	for id in p:
		if int(p[id]) > 0:
			parts[str(id)] = int(p[id])
	shelf = []
	for e in d.get("shelf", []):
		if e is Dictionary:
			shelf.append({"item": str(e.get("item", "")), "stars": int(e.get("stars", 0))})
	junk = []
	for e in d.get("junk", []):
		if e is Dictionary:
			junk.append({"item": str(e.get("item", "")), "fault": str(e.get("fault", ""))})
	reset_today()
	var t: Dictionary = d.get("today", {})
	for k in t:
		var v = t[k]
		today[k] = int(v) if v is float else v
	# --- SS CORE: los volúmenes ya no vienen de la partida (viven en SETTINGS_PATH: valen para todas)
	# --- SS CORE (partidas de la semilla, versión 1: valores por defecto)
	run_seed = int(d.get("run_seed", randi() % 1000000))
	sign_points = clampi(int(d.get("sign_points", 0)), 0, Data.SIGN_POINTS)
	resume = str(d.get("resume", "morning"))
	intro_seen = bool(d.get("intro_seen", true))
	pods_today = _ints(d.get("pods_today", []))
	history = _ints(d.get("history", []))
	tips_seen = d.get("tips_seen", {}).duplicate() if d.get("tips_seen", {}) is Dictionary else {}
	last_summary = _ints(d.get("last_summary", {}))
	if not d.has("pods_today"):
		roll_pods()
	# --- end SS CORE
	# --- SS2 SEASON: la temporada (las partidas del prototipo, versión 2, cargan con valores por defecto: el mismo
	# día de la campaña, las cuotas en tres partes desde ahora, el tablero rehecho con su historial)
	var v := int(d.get("version", 1))
	migrated_from = v if v < SAVE_VERSION else 0
	mode = str(d.get("mode", "campaign"))
	if mode != "endless":
		mode = "campaign"
	fittings = []
	for id in d.get("fittings", []):
		if SeasonData.FITTINGS.has(str(id)) and not (str(id) in fittings):
			fittings.append(str(id))
	fittings_new = []
	for id in d.get("fittings_new", []):
		if str(id) in fittings and not (str(id) in fittings_new):
			fittings_new.append(str(id))
	dues_paid = []
	for x in d.get("dues_paid", []):
		dues_paid.append(int(x))
	debt = maxi(0, int(d.get("debt", 0)))
	late_marks = maxi(0, int(d.get("late_marks", 0)))
	flags = _ints(d["flags"]) if d.get("flags") is Dictionary else {}
	beats_seen = {}
	if d.get("beats_seen") is Dictionary:
		for k in d["beats_seen"]:
			beats_seen[str(k)] = true
	unlocked = {}
	if d.get("unlocked") is Dictionary:
		for k in d["unlocked"]:
			unlocked[str(k)] = int(d["unlocked"][k])
	ending_seen = bool(d.get("ending_seen", false))
	crown_seen = bool(d.get("crown_seen", false))
	charity_day = int(d.get("charity_day", -99))
	if not today.has("tea_used") or int(today.get("tea_used", 0)) == 0:
		today["tea_used"] = 1 if bool(today.get("tea", false)) else 0
	for k in ["served", "repair_stars", "sale_stars", "event_stars"]:
		today[k] = int(today.get(k, 0))
	Season.load_data(d.get("season", {}))
	if d.get("rank") is Dictionary and (d["rank"] as Dictionary).has("scores"):
		Ranking.load_data(d["rank"])
	else:
		Ranking.reset(run_seed)
		Ranking.rebuild_from_history(history)
	if migrated_from > 0 and migrated_from < SAVE_VERSION:
		# el prototipo: lo que ya pasó cuenta para lo que se abre; las puntas del cartel no bajan
		for dd in range(1, day + 1):
			Season.update_unlocks(dd)
		sign_points = clampi(maxi(sign_points, Ranking.milestone_points()), 0, Data.SIGN_POINTS)
	_update_dues_goal()
	# --- end SS2 SEASON

## --- SS CORE: JSON devuelve todos los números como float; los enteros vuelven a ser int (también dentro de listas y
## diccionarios: las cápsulas y el historial).
func _ints(v):
	if v is float:
		return int(v) if v == floorf(v) else v
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_ints(e))
		return out
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = _ints(v[k])
		return o
	return v

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Game.save_game: no se pudo escribir %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true

func load_game() -> bool:
	if not has_save():
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if not (d is Dictionary):
		push_warning("Game.load_game: partida ilegible en %s" % SAVE_PATH)
		return false
	from_dict(d)
	parts_changed.emit()
	shelf_changed.emit()
	junk_changed.emit()
	credits_changed.emit(credits, 0)
	rep_changed.emit(rep, 0)
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# --- SS CORE: "Continue" solo si la partida guardada no terminó.
func can_continue() -> bool:
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d is Dictionary and str(d.get("resume", "morning")) != "done"

## --- SS2 SEASON: la nota del título una vez: una partida terminada del prototipo (versión 2, "done") no se continúa
## ("The prototype is over. A whole season awaits: New game."). "" si no hay nada que decir.
func save_note() -> String:
	if not has_save():
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d is Dictionary and int(d.get("version", 1)) < SAVE_VERSION and str(d.get("resume", "")) == "done":
		return String(SeasonData.TEXT["prototype_over"])
	return ""

## Los volúmenes en su propio archivo (valen para todas las partidas).
func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"music_volume": music_volume, "sfx_volume": sfx_volume}))
		f.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if d is Dictionary:
		music_volume = clampf(float(d.get("music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(d.get("sfx_volume", sfx_volume)), 0.0, 1.0)
# --- end SS CORE
