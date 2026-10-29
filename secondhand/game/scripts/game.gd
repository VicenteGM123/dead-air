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
const SAVE_VERSION := 2   # --- SS CORE: 2 = con los datos de la partida (cápsulas, cartel, historial...)

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
	reset_today()
	roll_pods()   # --- SS CORE

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
	}

## Suma n a una estadística numérica del día.
func stat(key: String, n := 1) -> void:
	today[key] = int(today.get(key, 0)) + n

## Pasa al día siguiente (CORE decide cuándo; el día 3 es el último del prototipo).
func next_day() -> void:
	day += 1
	reset_today()
	roll_pods()   # --- SS CORE
	day_started.emit(day)

func is_last_day() -> bool:
	return day >= Data.DAYS

## Cuánto de la cuota del puerto (dock dues) cubren los créditos (0..1).
func dues_progress() -> float:
	return clampf(float(credits) / float(maxi(1, dues_goal)), 0.0, 1.0)

func dues_met() -> bool:
	return credits >= dues_goal

# --- SS CORE: la mañana, el cierre del día y la partida -------------------------------------------------------------

## Las cápsulas de esta mañana en el puesto de Raker: las del día 1 fijas (Data.DAY1_PODS); las demás, sorteadas con
## la semilla de la partida (BenchData.roll_pod), así Continue ofrece las mismas.
func roll_pods() -> void:
	pods_today = []
	if day <= 1:
		for p in Data.DAY1_PODS:
			pods_today.append(p.duplicate(true))
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-pods-%d" % [run_seed, day])
	for i in Data.PODS_PER_DAY:
		var pod: Dictionary = BenchData.roll_pod(rng, "pod-%d%02d" % [day, i + 1])    # el número de serie que PodUI estampa ("POD-201")
		pods_today.append(pod)
	# que no sean iguales en peso: una pesada y una liviana (la decisión tiene gracia)
	if pods_today.size() >= 2 and int(pods_today[0].get("weight", 1)) == int(pods_today[1].get("weight", 1)):
		pods_today.sort_custom(func(a, b): return int(a.get("price", 0)) > int(b.get("price", 0)))

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
	if good and sign_points < Data.SIGN_POINTS:
		sign_points += 1
	s["sign_points"] = sign_points
	s["dues"] = dues_goal
	s["dues_met"] = dues_met()
	history.append(s)
	last_summary = s
	return s

## Los totales de la partida (la pantalla final).
func totals() -> Dictionary:
	var t := {"repairs": 0, "stars": 0, "sales": 0, "earned": 0, "spent": 0, "walkouts": 0, "missed": 0,
		"customers": 0, "arrived": 0, "refurbished": 0, "pods": 0, "tips": 0, "good_days": 0, "best_day": 0, "best_net": -99999}
	for s in history:
		for k in ["repairs", "stars", "sales", "earned", "spent", "walkouts", "missed", "customers", "arrived",
				"refurbished", "pods", "tips"]:
			t[k] = int(t[k]) + int(s.get(k, 0))
		if bool(s.get("good", false)):
			t["good_days"] = int(t["good_days"]) + 1
		if int(s.get("net", 0)) > int(t["best_net"]):
			t["best_net"] = int(s.get("net", 0))
			t["best_day"] = int(s.get("day", 0))
	t["credits"] = credits
	t["rep"] = rep
	t["sign_points"] = sign_points
	t["dues_met"] = dues_met()
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
