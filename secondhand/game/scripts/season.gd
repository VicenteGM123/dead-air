extends Node
## --- SS2 SEASON: la temporada (autoload "Season"): el calendario de 10 días y el modo sin fin, los planes de cada
## día, las agendas generadas, los efectos (mejoras, días especiales, reputación, marcas de historia), lo que se abre,
## las cuotas en tres partes con la regla blanda, las mejoras de Dolly, el puesto de Mags (piezas + lo de "tal cual"),
## las cápsulas (incl. el naufragio, la Gran Caída y la de regalo), las reglas de los días especiales (la inspección,
## la carrera), los momentos de historia y sus marcas. Los números y los textos están en SeasonData (season_data.gd).
## Contrato (SS2_DESIGN §8.6): plan, event, title, is_finale, k, n, schedule_for, pods_for, mags_stock, asis_for,
## unlocked_items, unlocked_parts, is_unlocked, on_morning, night_preview, rep_tier, bench_aids, add_core, dues_due,
## next_dues, collect_dues, fittings_on_sale, buy_fitting, beats, apply_beat, on_handover, on_graded, race_result,
## save_data, load_data, debug_state. Todo lo público empieza con _ensure() (Game puede llamar a reset() antes de que
## este nodo tenga su _ready, como el Ranking de Caldero).
## Nada fuera de Season nombra una mejora por su efecto: el resto del juego pregunta k(clave) / n(clave).

var state := {}            # lo que se guarda (save_data): ver _defaults()
var _built := false
var _endless_cache := {}   # run_seed -> {día: evento} del modo sin fin

func _init() -> void:
	_ensure()

func _ensure() -> void:
	if _built:
		return
	_built = true
	state = _defaults()

func _defaults() -> Dictionary:
	return {
		"morning_day": 0,      # el último día en que corrió on_morning (no se repite al cargar la partida)
		"morning": {},         # lo que dijo esa mañana (el cartel, los avisos)
		"asis_day": 0,         # el día del puesto de "tal cual" guardado
		"asis": [],            # lo que queda hoy en el cajón de "tal cual" de Mags
		"dues_done": [],       # noches en que ya se cobró la cuota (pagada o no)
		"racers": {},          # (el día de la carrera) quién entregó a tiempo: who -> estrellas
		"race_called": false,
		"race": {},            # el resultado de la carrera
		"family_jobs": {},     # familia -> trabajos hechos (el bot humano piensa más en los dos primeros)
		"close_early": false,  # hoy se cerró antes
	}

## Partida nueva (Game.new_game_state).
func reset() -> void:
	_ensure()
	state = _defaults()
	_endless_cache = {}

func _d(day: int) -> int:
	return Game.day if day < 0 else day

# ------------------------------------------------------------------ el calendario y los planes

## El plan del día (una copia): título, subtítulo, evento, llegadas, compradores, cápsulas, invitados...
func plan(day := -1) -> Dictionary:
	_ensure()
	var d := _d(day)
	var p: Dictionary
	if SeasonData.PLAN.has(d):
		p = (SeasonData.PLAN[d] as Dictionary).duplicate(true)
	else:
		# el modo sin fin: 8-9 llegadas generadas, 35-45 % compradores, un evento cada 2-3 días
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d-endless-%d" % [Game.run_seed, d])
		var ev := _endless_event(d)
		var arr: int = rng.randi_range(int(SeasonData.ENDLESS["arrivals"][0]), int(SeasonData.ENDLESS["arrivals"][1]))
		p = {"title": "Day %d" % d, "sub": SeasonData.TEXT["endless_title"], "event": ev, "arrivals": arr,
			"generated": arr, "buyers": rng.randf_range(float(SeasonData.ENDLESS["buyers"][0]), float(SeasonData.ENDLESS["buyers"][1])),
			"pods": int(SeasonData.ENDLESS["pods"]), "rush": rng.randf_range(0.3, 0.6), "guests": []}
		if ev != "":
			p["title"] = String(SeasonData.EVENTS[ev]["name"])
		match ev:
			"sandstorm":
				p["pods"] = 0
				p["arrivals"] = 6
				p["generated"] = 6
			"festival":
				p["buyers"] = 0.6
			"inspection":
				p["pod_opts"] = {"min_parts": 3}
				p["generated"] = arr - 1
				p["guests"] = [{"who": "inspector", "t": 80.0, "kind": "repair", "item": "radio", "extra": {"graded": true}}]
			"race":
				p["racers"] = true
				p["generated"] = 5
			"bigfall":
				p["extra_pods"] = ["wreck"]
	for k in ["event", "guests", "beats"]:
		if not p.has(k):
			p[k] = "" if k == "event" else []
	return p

## El evento de un día del modo sin fin ("" la mayoría): uno cada 2-3 días, nunca el mismo dos veces seguidas.
func _endless_event(d: int) -> String:
	if d <= SeasonData.LAST_DAY:
		return ""
	var key := Game.run_seed
	if not _endless_cache.has(key) or int(_endless_cache[key].get("_upto", 0)) < d:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d-endless-events" % Game.run_seed)
		var m := {}
		var cur := SeasonData.LAST_DAY
		var last := "finale"
		var upto := maxi(d, 60) + 20
		while cur < upto:
			cur += rng.randi_range(int(SeasonData.ENDLESS["event_gap"][0]), int(SeasonData.ENDLESS["event_gap"][1]))
			var pool: Array = SeasonData.ENDLESS_POOL.duplicate()
			pool.erase(last)
			last = String(pool[rng.randi() % pool.size()])
			m[cur] = last
		m["_upto"] = upto
		_endless_cache[key] = m
	return String(_endless_cache[key].get(d, ""))

func event(day := -1) -> String:
	return String(plan(day).get("event", ""))

func event_def(day := -1) -> Dictionary:
	var ev := event(day)
	return SeasonData.EVENTS.get(ev, {}) if ev != "" else {}

func title(day := -1) -> String:
	return String(plan(day).get("title", "Day %d" % _d(day)))

func subtitle(day := -1) -> String:
	return String(plan(day).get("sub", ""))

func is_finale(day := -1) -> bool:
	return event(day) == "finale"

func is_campaign_day(day := -1) -> bool:
	return _d(day) <= SeasonData.LAST_DAY

# ------------------------------------------------------------------ los efectos (§8.2)

## Todas las fuentes de efectos de ahora: las mejoras compradas, el evento de hoy, los tramos de reputación
## alcanzados (se suman) y las marcas de historia.
func _sources() -> Array:
	var out: Array = []
	for id in Game.fittings:
		if SeasonData.FITTINGS.has(id):
			out.append(SeasonData.FITTINGS[id]["effects"])
	var ed := event_def()
	if not ed.is_empty():
		out.append(ed.get("effects", {}))
	for t in SeasonData.REP_TIERS:
		if Game.rep >= int(t["rep"]):
			out.append(t["effects"])
	for f in SeasonData.FLAG_EFFECTS:
		var fe: Dictionary = SeasonData.FLAG_EFFECTS[f]
		if Game.flag(f, false) and (not fe.has("event") or event() == String(fe["event"])):
			out.append(fe["effects"])
	return out

## Un multiplicador (el producto de todas las fuentes; 1.0 si nadie lo toca).
func k(key: String) -> float:
	_ensure()
	var v := 1.0
	for e in _sources():
		if e.has(key):
			v *= float(e[key])
	return v

## Una suma entera (0 si nadie la toca): tea_uses, appeal, pods_add, free_part...
func n(key: String) -> int:
	return int(round(nf(key)))

## Una suma con decimales (tea_boost_add 0.1, solder_add en segundos).
func nf(key: String) -> float:
	_ensure()
	var v := 0.0
	for e in _sources():
		if e.has(key):
			v += float(e[key])
	return v

## Las ayudas del banco (BenchUI, clave opcional "aids" del trabajo).
func bench_aids() -> Dictionary:
	return {"zone_k": k("bench_zone_k"), "pad_k": k("bench_pad_k"), "solder_add": nf("solder_add"), "sweep_k": k("sweep_k")}

# ------------------------------------------------------------------ la reputación y lo que se abre

func rep_tier(rep := -999999) -> Dictionary:
	var r := Game.rep if rep == -999999 else rep
	var out: Dictionary = SeasonData.REP_TIERS[0]
	for t in SeasonData.REP_TIERS:
		if r >= int(t["rep"]):
			out = t
	return out

func tier_index(rep := -999999) -> int:
	return SeasonData.REP_TIERS.find(rep_tier(rep))

func is_unlocked(id: String) -> bool:
	return Game.unlocked.has(id)

## Abre lo que toca hoy (por día, o antes con reputación; el día "latest" se abre igual). Devuelve los ids nuevos.
func update_unlocks(day := -1) -> Array:
	var d := _d(day)
	var out: Array = []
	for id in SeasonData.UNLOCKS:
		if Game.unlocked.has(id):
			continue
		var u: Dictionary = SeasonData.UNLOCKS[id]
		if d >= int(u["day"]) and (Game.rep >= int(u["rep"]) or d >= int(u["latest"])):
			Game.unlocked[id] = d
			out.append(id)
	return out

## Las familias del banco que existen (BenchData.ITEMS) y están abiertas, en el orden del banco.
func unlocked_items() -> Array:
	var out: Array = []
	for it in BenchData.ITEM_ORDER:
		var item := String(it)
		if item in SeasonData.BASE_FAMILIES or is_unlocked(item):
			out.append(item)
	return out

## Las piezas de las familias abiertas (en el orden del cajón).
func unlocked_parts() -> Array:
	var want := {}
	for item in unlocked_items():
		for p in BenchData.ITEMS[item]["slots"]:
			want[String(p)] = true
	var out: Array = []
	for p in BenchData.PART_ORDER:
		if want.has(String(p)):
			out.append(String(p))
	return out

## Los clientes que pueden venir (generados): los de siempre + los nuevos ya abiertos.
func customers() -> Array:
	var out: Array = SeasonData.BASE_CUSTOMERS.duplicate()
	for id in ["singer", "timekeeper", "tracker"]:
		if is_unlocked(id):
			out.append(id)
	return out

# ------------------------------------------------------------------ la mañana

## La mañana del día (una vez por día: al cargar la partida no se repite): lo nuevo, la pieza gratis del Parts Wall,
## la cápsula de regalo, el aviso de Kettle de los días especiales. {"new": [nombres], "free_part", "charity",
## "kettle", "tier", "repeat"}.
func on_morning() -> Dictionary:
	_ensure()
	if int(state.get("morning_day", 0)) == Game.day:
		var again: Dictionary = (state.get("morning", {}) as Dictionary).duplicate(true)
		again["repeat"] = true
		return again
	var res := {"new": [], "free_part": "", "charity": false, "kettle": "", "repeat": false}
	for id in update_unlocks():
		res["new"].append(String(SeasonData.UNLOCKS[id]["name"]))
	# la pieza gratis: de una familia que viene hoy (la que menos hay en el cajón)
	if n("free_part") > 0:
		var p := _free_part()
		if p != "":
			Game.add_part(p)
			res["free_part"] = p
	# la cápsula de regalo: sin créditos, sin piezas y sin nada roto (una vez cada 3 días)
	if _needs_charity():
		var pod := _charity_pod()
		Game.pods_today.append(pod)
		Game.charity_day = Game.day
		res["charity"] = true
	var ed := event_def()
	if not ed.is_empty():
		res["kettle"] = String(ed.get("kettle", ""))
	state["family_jobs"] = state.get("family_jobs", {})
	state["race_called"] = false
	state["racers"] = {}
	state["close_early"] = false
	state["morning_day"] = Game.day
	state["morning"] = res.duplicate(true)
	return res

func _free_part() -> String:
	var fams := {}
	for e in schedule_for(Game.day):
		if String(e.get("kind", "")) == "repair":
			fams[String(e.get("item", "radio"))] = true
	if fams.is_empty():
		fams = {"radio": true}
	var best := ""
	var best_n := 999
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-free-%d" % [Game.run_seed, Game.day])
	var cand: Array = []
	for f in fams:
		for p in BenchData.ITEMS[f]["slots"]:
			if not cand.has(String(p)):
				cand.append(String(p))
	cand.shuffle()
	for p in cand:
		if Game.part_count(p) < best_n:
			best_n = Game.part_count(p)
			best = p
	return best

func _needs_charity() -> bool:
	if int(plan().get("pods", 2)) <= 0:
		return false
	# --- POLISH FIX (F6): el día del cometa nadie se queda sin cápsula por haber pagado la cuota de la noche 9: si no
	# alcanza para la más barata (a precio de lista: regatear con lo justo no es una noche final) y no hay nada roto,
	# Raker guarda una (sin mirar piezas ni los 3 días). (Con 0.7 x precio, el bot apurado con 15 cr no compraba nada.)
	if Game.is_last_day() and Game.junk.is_empty() and not Game.pods_today.is_empty():
		var cheapest := 9999
		for p in Game.pods_today:
			cheapest = mini(cheapest, int(p.get("price", 30)))
		if Game.credits < cheapest:
			return true
	# --- end POLISH FIX
	var c: Dictionary = SeasonData.CHARITY
	return Game.credits < int(c["credits_below"]) and Game.parts_total() < int(c["parts_below"]) and Game.junk.is_empty() \
		and Game.day - Game.charity_day >= int(c["every"])

func _charity_pod() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-charity-%d" % [Game.run_seed, Game.day])
	var pod := _roll_pod(rng, "pod-gift", {"kind": "charity", "broken_p": 1.0, "min_parts": 2, "max_parts": 2, "price": 0})
	pod["kind"] = "charity"
	pod["price"] = 0
	return pod

## La línea del pie del tablero para la noche del día dado: lo que viene mañana.
func night_preview(day := -1) -> String:
	var d := _d(day)
	var ev := event(d + 1)
	if ev != "":
		return String(SeasonData.EVENTS[ev]["preview"])
	if d + 1 <= SeasonData.LAST_DAY:
		return "Tomorrow: %s." % title(d + 1)
	return ""

## La línea larga (el anuncio de la noche anterior; el "tiempo" del Lantern Report).
func announce(day := -1) -> String:
	var ev := event(_d(day) + 1)
	return String(SeasonData.EVENTS[ev]["announce"]) if ev != "" else ""

## Lo que hay que decodificar esta noche para mañana (Sfx.LATE_LOOPS): el bucle del evento de mañana.
func tomorrow_loops(day := -1) -> Array:
	var ev := event(_d(day) + 1)
	var out: Array = []
	if ev != "":
		var e: Dictionary = SeasonData.EVENTS[ev]
		if String(e.get("music", "")) != "":
			out.append(String(e["music"]))
		if String(e.get("amb", "")) != "":
			out.append(String(e["amb"]))
	return out

# ------------------------------------------------------------------ la agenda del día (§2.2)

## La agenda de un día: días 1-3 = Data.SCHEDULE (+ los invitados); 4+ generada; con los extras de las mejoras.
## Cada entrada: {"t", "who", "kind": "repair"|"buy"|"favour", "item", "fault", "wants", "extra": {}}.
func schedule_for(day: int) -> Array:
	_ensure()
	var p := plan(day)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-sched-%d" % [Game.run_seed, day])
	var out: Array = []
	if day <= Data.SCHEDULE.size():
		for e in Data.SCHEDULE[day - 1]:
			var x: Dictionary = (e as Dictionary).duplicate(true)
			x["extra"] = {}
			out.append(x)
	elif bool(p.get("curtain_call", false)):
		out = _curtain_call(rng, p)
	elif bool(p.get("racers", false)):
		out = _racers(rng)
		var gen := _generated(rng, int(p.get("generated", 5)), float(p.get("buyers", 0.3)), 0.0, p, 60.0)
		# un comprador a los 45 s; los demás después de los 60 s
		if not gen.is_empty():
			var bi := -1
			for i in gen.size():
				if String(gen[i]["kind"]) == "buy":
					bi = i
					break
			if bi < 0:
				bi = 0
				gen[0] = _buy_entry(rng, String(gen[0]["who"]), 45.0)
			gen[bi]["t"] = 45.0
		out.append_array(gen)
	else:
		out = _generated(rng, int(p.get("generated", p.get("arrivals", 8))), float(p.get("buyers", 0.35)), float(p.get("rush", 0.45)), p)
	# los invitados del plan
	for g in p.get("guests", []):
		if bool(g.get("if_unlocked", false)) and not is_unlocked(String(g["who"])):
			continue
		out.append(_guest(rng, g))
	# los extras de las mejoras (al abrir): el Neon Star solo con lugar; el Display Case solo con estante lleno
	var extras_rng := RandomNumberGenerator.new()
	extras_rng.seed = hash("%d-extras-%d" % [Game.run_seed, day])
	if n("arrivals_add") > 0 and out.size() <= 9 and out.size() < SeasonData.ARRIVALS_CAP and not bool(p.get("curtain_call", false)):
		var e1 := _one_generated(extras_rng, out, 0.3, p)
		e1["t"] = extras_rng.randf_range(0.2, 0.7) * Data.DAY_SECONDS
		out.append(e1)
	if n("buyers_add") > 0 and Game.shelf.size() >= 3 and out.size() < SeasonData.ARRIVALS_CAP and not bool(p.get("curtain_call", false)):
		var who := _pick_who(extras_rng, out, true)
		var e2 := _buy_entry(extras_rng, who, extras_rng.randf_range(0.25, 0.75) * Data.DAY_SECONDS)
		out.append(e2)
	# una falla que no es de su familia (red de seguridad de los datos del plan) y el tope de llegadas
	for e in out:
		_fix_fault(e, rng)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	while out.size() > SeasonData.ARRIVALS_CAP:
		out.pop_back()
	return out

## Las horas de llegada de n clientes generados: repartidas entre el 4 % y el 86 % del día, con una hora punta de 3
## en 25 s (rush = la fracción del día donde cae; 0 = sin hora punta).
func _times(rng: RandomNumberGenerator, count: int, rush: float, t_min := 0.0) -> Array:
	var t0 := maxf(0.04 * Data.DAY_SECONDS, t_min)
	var t1 := 0.86 * Data.DAY_SECONDS
	var ts: Array = []
	var in_rush := 3 if rush > 0.0 and count >= 5 else 0
	var rt := rush * Data.DAY_SECONDS
	for i in in_rush:
		ts.append(rt + i * 11.0 + rng.randf_range(0.0, 3.0))
	var rest := count - in_rush
	for i in rest:
		var a := t0 + (t1 - t0) * float(i) / maxf(1.0, float(rest))
		var b := t0 + (t1 - t0) * float(i + 1) / maxf(1.0, float(rest))
		var t := rng.randf_range(a, b)
		# lejos de la hora punta
		if in_rush > 0 and absf(t - rt) < 14.0:
			t = clampf(t + 30.0, t0, t1)
		ts.append(t)
	ts.sort()
	return ts

func _generated(rng: RandomNumberGenerator, count: int, buyers: float, rush: float, p: Dictionary, t_min := 0.0) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var ts := _times(rng, count, rush, t_min)
	var n_buy := int(round(count * buyers))
	# quiénes compran: barajado con el rng de la partida (shuffle() usaría el azar global: Continue no daría lo mismo)
	var kinds: Array = []
	var idx: Array = []
	for i in count:
		idx.append(i)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	for i in count:
		kinds.append("repair")
	for i in n_buy:
		kinds[idx[i]] = "buy"
	for i in count:
		var who := _pick_who(rng, out, kinds[i] == "buy")
		if kinds[i] == "buy" and who == "":
			kinds[i] = "repair"
			who = _pick_who(rng, out, false)
		var e := _buy_entry(rng, who, ts[i]) if kinds[i] == "buy" else _repair_entry(rng, who, ts[i], p)
		out.append(e)
	return out

func _one_generated(rng: RandomNumberGenerator, so_far: Array, buyers: float, p: Dictionary) -> Dictionary:
	var buy := rng.randf() < buyers
	var who := _pick_who(rng, so_far, buy)
	if buy and who != "":
		return _buy_entry(rng, who, 0.0)
	return _repair_entry(rng, _pick_who(rng, so_far, false), 0.0, p)

## Quién viene: de los clientes abiertos, nadie dos veces seguidas, como mucho 2 visitas al día; los nuevos de hoy
## valen doble. buyer: solo quien compra algo de las familias abiertas.
func _pick_who(rng: RandomNumberGenerator, so_far: Array, buyer: bool) -> String:
	var counts := {}
	for e in so_far:
		counts[String(e["who"])] = int(counts.get(String(e["who"]), 0)) + 1
	var last := String(so_far[-1]["who"]) if not so_far.is_empty() else ""
	var pool: Array = []
	var weights: Array = []
	for id in customers():
		if id == last or int(counts.get(id, 0)) >= 2:
			continue
		if buyer and _wants_for(id).is_empty():
			continue
		if not buyer and _brings_for(id).is_empty():
			continue
		pool.append(id)
		weights.append(2.0 if int(Game.unlocked.get(id, -1)) == Game.day else 1.0)
	if pool.is_empty():
		for id in customers():
			if (buyer and not _wants_for(id).is_empty()) or (not buyer and not _brings_for(id).is_empty()):
				pool.append(id)
				weights.append(1.0)
	if pool.is_empty():
		return "" if buyer else "gorrum"
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for i in pool.size():
		r -= float(weights[i])
		if r <= 0.0:
			return String(pool[i])
	return String(pool[-1])

## Lo que trae roto un cliente (sus "brings" de las familias abiertas; con su familia de respaldo si no existe).
func _brings_for(who: String) -> Array:
	var out: Array = []
	var open := unlocked_items()
	for it in Data.CAST.get(who, {}).get("brings", []):
		var item := String(it)
		if item in open:
			out.append(item)
	return out

# --- POLISH FIX (F4): un comprador sin nada que comprar encarga un arreglo de lo suyo (la misma partida, la misma cosa)
func order_for(who: String, vid: int) -> Dictionary:
	var items := _brings_for(who)
	if items.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-order-%d-%d" % [Game.run_seed, Game.day, vid])
	var item := String(items[rng.randi() % items.size()])
	return {"item": item, "fault": _fault(rng, item, plan())}
# --- end POLISH FIX

func _wants_for(who: String) -> Array:
	var out: Array = []
	var open := unlocked_items()
	for it in Data.CAST.get(who, {}).get("buys", []):
		var item := String(it)
		if item in open:
			out.append(item)
	return out

func _repair_entry(rng: RandomNumberGenerator, who: String, t: float, p: Dictionary) -> Dictionary:
	var items := _brings_for(who)
	if items.is_empty():
		items = ["radio"]
	var pool: Array = items.duplicate()
	if who in p.get("navbox_bias", []) and "navbox" in items:
		pool.append("navbox")
	var item := String(pool[rng.randi() % pool.size()])
	return {"t": t, "who": who, "kind": "repair", "item": item, "fault": _fault(rng, item, p), "extra": {}}

func _buy_entry(rng: RandomNumberGenerator, who: String, t: float) -> Dictionary:
	var w := _wants_for(who)
	if w.is_empty():
		w = ["radio", "helperbot"]
	# dos familias (como en el prototipo): las suyas, en un orden propio
	var out: Array = []
	var pool: Array = w.duplicate()
	while not pool.is_empty() and out.size() < 2:
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return {"t": t, "who": who, "kind": "buy", "wants": out, "extra": {}}

## Una falla: al azar, o (días especiales) 60 % de las veces de las que el evento favorece.
func _fault(rng: RandomNumberGenerator, item: String, p: Dictionary) -> String:
	var fam := item
	var faults: Array = BenchData.FAULTS.get(fam, {}).keys()
	if faults.is_empty():
		return ""
	var ev := String(p.get("event", ""))
	if ev != "" and rng.randf() < 0.6:
		var bias: Array = []
		for f in SeasonData.EVENTS[ev].get("fault_bias", []):
			if String(f) in faults:
				bias.append(String(f))
		if not bias.is_empty():
			return String(bias[rng.randi() % bias.size()])
	return String(faults[rng.randi() % faults.size()])

func _guest(rng: RandomNumberGenerator, g: Dictionary) -> Dictionary:
	var who := String(g["who"])
	var e := {"t": float(g["t"]), "who": who, "kind": String(g.get("kind", "repair")), "extra": (g.get("extra", {}) as Dictionary).duplicate(true)}
	if e["kind"] == "repair":
		var item := String(g.get("item", ""))
		if item == "":
			var b := _brings_for(who)
			item = String(b[rng.randi() % b.size()]) if not b.is_empty() else "radio"
		e["item"] = item
		e["fault"] = _fault(rng, item, {})
	elif e["kind"] == "favour":
		var fj: Dictionary = SeasonData.FAVOUR_JOB
		e["item"] = String(fj["item"])
		e["fault"] = String(fj["fault"])
	elif e["kind"] == "buy":
		e["wants"] = _wants_for(who)
	return e

## El día de la carrera: los 4 corredores primero, con propulsores y la hora límite (las 2 PM).
func _racers(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for r in SeasonData.RACERS:
		var who := String(r[0])
		if who == "rook|tracker":
			who = "rook" if Game.flag("crate", "") == "delivered" else "tracker"
		if who in ["timekeeper", "tracker"] and not is_unlocked(who):
			who = "zib"
		out.append({"t": float(r[1]), "who": who, "kind": "repair", "item": "thruster",
			"fault": _fault(rng, "thruster", {}), "extra": {"deadline_min": int(SeasonData.RACE["deadline_min"]), "racer": true}})
	return out

## El último día: los conocidos, una vez cada uno; un 40 % compra (quien puede comprar).
func _curtain_call(rng: RandomNumberGenerator, p: Dictionary) -> Array:
	var who_list: Array = []
	for id in SeasonData.CURTAIN_CALL:
		if id in SeasonData.BASE_CUSTOMERS or is_unlocked(id) or Data.CAST.has(id):
			who_list.append(id)
	var ts := _times(rng, who_list.size(), 0.0)
	# el orden de llegada: barajado con el rng de la partida
	for i in range(who_list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = who_list[i]
		who_list[i] = who_list[j]
		who_list[j] = tmp
	var n_buy := int(round(who_list.size() * float(p.get("buyers", 0.4))))
	var out: Array = []
	var bought := 0
	for i in who_list.size():
		var who := String(who_list[i])
		if bought < n_buy and not _wants_for(who).is_empty() and rng.randf() < 0.6:
			out.append(_buy_entry(rng, who, ts[i]))
			bought += 1
		else:
			out.append(_repair_entry(rng, who, ts[i], p))
	# si faltan compradores, los últimos que pueden comprar pasan a comprar
	for i in range(out.size() - 1, -1, -1):
		if bought >= n_buy:
			break
		if String(out[i]["kind"]) == "repair" and not _wants_for(String(out[i]["who"])).is_empty():
			out[i] = _buy_entry(rng, String(out[i]["who"]), float(out[i]["t"]))
			bought += 1
	# (POLISH FIX F4: aquí la última noche los compradores querían "cualquier cosa"; se quitó por el equilibrio: con
	# dos ventas más en la noche que cuenta doble, el jugador humano ganaba el cometa en el 95 % de las simulaciones
	# (el objetivo es 65-85 %). La última noche la cubre "Fix theirs instead", como los otros días.)
	return out

## --- SS2 MERGE: el respaldo de familias (FAMILY_FALLBACK) ya no hace falta (las 5 familias existen); queda solo la
## red de seguridad: una falla que no es de la familia del objeto se cambia por una de las suyas.
func _fix_fault(e: Dictionary, rng: RandomNumberGenerator) -> void:
	if e.has("item") and String(e["item"]) != "":
		var fam := String(e["item"])
		if BenchData.FAULTS.has(fam) and not BenchData.FAULTS[fam].has(String(e.get("fault", ""))):
			e["fault"] = String(BenchData.FAULTS[fam].keys()[rng.randi() % BenchData.FAULTS[fam].size()])

# ------------------------------------------------------------------ las cápsulas de Raker

## Las cápsulas de esta mañana (Game.roll_pods delega aquí): solo familias y piezas abiertas; el día 1 las fijas.
func pods_for(day: int) -> Array:
	_ensure()
	var out: Array = []
	if day <= 1:
		for p in Data.DAY1_PODS:
			out.append((p as Dictionary).duplicate(true))
		return out
	var p := plan(day)
	var count := int(p.get("pods", 2))
	if count > 0:
		count += n("pods_add")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-pods-%d" % [Game.run_seed, day])
	for i in count:
		out.append(_roll_pod(rng, "pod-%d%02d" % [day, i + 1], p.get("pod_opts", {})))
	# que no sean iguales en peso: una pesada y una liviana (la decisión tiene gracia)
	# --- POLISH FIX (F3): antes solo se ordenaban (1 mañana de 4 ofrecía dos cápsulas idénticas). Ahora, con el mismo
	# rng (la misma partida da las mismas cápsulas): se vuelve a tirar la segunda mientras pesen igual (hasta 6 veces);
	# si siguen iguales, la segunda va al otro lado (pesada con algo roto, o liviana sin nada roto); si ninguna trae una
	# cosa rota, la segunda es la pesada. La pesada va primero.
	if out.size() >= 2:
		var po: Dictionary = p.get("pod_opts", {})
		var heavy := po.duplicate(true)
		heavy.merge({"min_parts": 3, "broken_p": 1.0}, true)
		var light := po.duplicate(true)
		light.merge({"max_parts": 2, "broken_p": 0.0}, true)
		var id2 := String(out[1].get("id", "pod-%d02" % day))
		var tries := 0
		while _pod_w(out[0]) == _pod_w(out[1]) and tries < 6:
			out[1] = _roll_pod(rng, id2, po)
			tries += 1
		if _pod_w(out[0]) == _pod_w(out[1]):
			out[1] = _roll_pod(rng, id2, heavy if _pod_w(out[0]) <= 2 else light)
		if not _pod_has_item(out[0]) and not _pod_has_item(out[1]):
			out[1] = _roll_pod(rng, id2, heavy)
		if _pod_w(out[1]) > _pod_w(out[0]):
			var a: Dictionary = out[0]
			out[0] = out[1]
			out[1] = a
	# --- end POLISH FIX
	for kind in p.get("extra_pods", []):
		out.append(_special_pod(rng, String(kind), day))
	return out

# --- POLISH FIX (F3)
func _pod_w(pod: Dictionary) -> int:
	return int(pod.get("weight", 1))

func _pod_has_item(pod: Dictionary) -> bool:
	for c in pod.get("contents", []):
		if c is Dictionary and c.has("item"):
			return true
	return false
# --- end POLISH FIX

func _special_pod(rng: RandomNumberGenerator, kind: String, day: int) -> Dictionary:
	var price := int(SeasonData.POD_PRICES.get(kind, 40))
	var opts := {"kind": kind, "min_parts": 3, "max_parts": 3, "broken_p": 1.0, "price": price, "weight": 3, "rattle": 2}
	if kind == "wreck":
		opts["force_item"] = "navbox"
		opts["core"] = int(Game.flag("cores", 0)) < 3 and not Game.flag("core_wreck", false)
	else:
		opts["force_item"] = "jukebox" if rng.randf() < 0.5 else "navbox"
	var pod := _roll_pod(rng, "pod-%d%s" % [day, kind.substr(0, 1)], opts)
	pod["kind"] = kind
	pod["price"] = price
	pod["weight"] = 3
	pod["rattle"] = 2
	return pod

## Una cápsula de las familias y piezas abiertas (BenchData.roll_pod_for de la línea BENCH; --- SS2 MERGE: sin el
## respaldo local, que ya no se usaba).
func _roll_pod(rng: RandomNumberGenerator, id: String, opts: Dictionary) -> Dictionary:
	return BenchData.roll_pod_for(rng, id, unlocked_items(), unlocked_parts(), opts.duplicate(true))

## Lo que se ve en la etiqueta de una cápsula con el Pod Lamp ("Lamp: a radio inside").
func pod_peek_text(pod: Dictionary) -> String:
	var items: Array = []
	var core := false
	for c in pod.get("contents", []):
		if c is Dictionary:
			if c.has("item"):
				items.append(BenchData.item_name(String(c["item"])).to_lower())
			elif c.has("core"):
				core = true
	if core:
		return "Lamp: it glows!"
	if not items.is_empty():
		return "Lamp: a %s inside" % String(items[0]).trim_prefix("street ").trim_prefix("pocket ").trim_prefix("hoverbike ")
	return "Lamp: parts only"

# ------------------------------------------------------------------ el puesto de Mags

## Las piezas de Mags esta mañana (hasta 8): la celda y el chip siempre, luego las de las familias de hoy, luego lo
## que el evento trae y el resto. [{"part", "price", "deal"}]
func mags_stock(day := -1) -> Array:
	_ensure()
	var d := _d(day)
	var open := unlocked_parts()
	var order: Array = []
	for p in SeasonData.MAGS_CORE:
		if p in open and not order.has(p):
			order.append(p)
	var fams: Array = []
	for e in schedule_for(d):
		if e.has("item") and not fams.has(String(e["item"])):
			fams.append(String(e["item"]))
	for f in fams:
		for p in BenchData.ITEMS.get(f, {}).get("slots", []):
			if String(p) in open and not order.has(String(p)):
				order.append(String(p))
	for p in event_def(d).get("mags_extra", []):
		if BenchData.PARTS.has(String(p)) and not order.has(String(p)):
			order.append(String(p))
	for p in open:
		if not order.has(p):
			order.append(p)
	var add := n("part_price_add")
	var out: Array = []
	for p in order:
		if out.size() >= SeasonData.MAGS_MAX:
			break
		var price := BenchData.part_price(String(p))
		if add != 0:
			price = maxi(SeasonData.STORM_SALE_MIN, price + add)
		out.append({"part": String(p), "price": price, "deal": false})
	# (P1) la oferta del día (desde Trusted): una pieza al 60 %
	if Game.rep >= int(SeasonData.MAGS_DEAL["rep"]) and not out.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d-deal-%d" % [Game.run_seed, d])
		var e: Dictionary = out[rng.randi() % out.size()]
		e["price"] = maxi(SeasonData.STORM_SALE_MIN, int(round(float(e["price"]) * float(SeasonData.MAGS_DEAL["k"]))))
		e["deal"] = true
	# en el orden del cajón (como el puesto del prototipo)
	out.sort_custom(func(a, b): return BenchData.PART_ORDER.find(a["part"]) < BenchData.PART_ORDER.find(b["part"]))
	return out

## El precio de hoy de una pieza en el puesto de Mags.
func part_price_today(part: String) -> int:
	var price := BenchData.part_price(part)
	var add := n("part_price_add")
	return maxi(SeasonData.STORM_SALE_MIN, price + add) if add != 0 else price

## El cajón de "tal cual" de Mags (desde el día 3): 1 cosa rota (2 con reputación 35). [{"item", "fault", "symptom",
## "price"}]. Lo comprado sale de la lista (se guarda con la partida).
func asis_for(day := -1) -> Array:
	_ensure()
	var d := _d(day)
	if not is_unlocked("asis"):
		return []
	if int(state.get("asis_day", 0)) != d:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d-asis-%d" % [Game.run_seed, d])
		var items := unlocked_items()
		var list: Array = []
		var count := mini(2, 1 + n("asis_add"))
		var eve := event(d + 1) == "festival"
		if eve:
			count += SeasonData.ASIS_EVE_BONUS   # la víspera de Bronzemoon: una más y más barato
		for i in count:
			var item := String(items[rng.randi() % items.size()])
			var faults: Array = BenchData.FAULTS[item].keys()
			var fault := String(faults[rng.randi() % faults.size()])
			var price := asis_price(item)
			if eve:
				price = maxi(1, int(round(float(price) * SeasonData.ASIS_EVE_K)))
			list.append({"item": item, "fault": fault, "symptom": BenchData.symptom(item, fault, rng.randi_range(0, 2)),
				"price": price})
		state["asis_day"] = d
		state["asis"] = list
	return (state["asis"] as Array).duplicate(true)

func asis_price(item: String) -> int:
	return int(BenchData.asis_price(item))

## Compra la cosa i del cajón de "tal cual" (va a lo roto). true si alcanzó.
func buy_asis(i: int) -> bool:
	var list := asis_for()
	if i < 0 or i >= list.size():
		return false
	var e: Dictionary = list[i]
	if not Game.spend_credits(int(e["price"])):
		return false
	Game.add_junk(String(e["item"]), String(e["fault"]))
	Game.stat("asis")
	(state["asis"] as Array).remove_at(i)
	return true

# ------------------------------------------------------------------ las cuotas (§2.5)

## La cuota de una noche sin la deuda (0 si esa noche no hay).
func dues_of(night: int) -> int:
	if SeasonData.DUES.has(night):
		return int(SeasonData.DUES[night])
	var u: Dictionary = SeasonData.UPKEEP
	if night >= int(u["first"]) and (night - int(u["first"])) % int(u["every"]) == 0:
		return int(u["amount"])
	return 0

## Lo que se cobra esta noche (la cuota + lo que quedó debiendo); 0 si no hay o ya se cobró.
func dues_due(night: int) -> int:
	_ensure()
	var base := dues_of(night)
	if base <= 0 or night in state.get("dues_done", []):
		return 0
	return base + Game.debt

## La próxima cuota: {"night", "amount" (sin deuda), "debt"} (night 0 si no queda ninguna... siempre queda una).
func next_dues() -> Dictionary:
	_ensure()
	var nn := Game.day
	for i in 400:
		var night := nn + i
		if dues_of(night) > 0 and not (night in state.get("dues_done", [])):
			return {"night": night, "amount": dues_of(night), "debt": Game.debt, "upkeep": not SeasonData.DUES.has(night)}
	return {"night": 0, "amount": 0, "debt": Game.debt, "upkeep": false}

## Cobra la cuota de esta noche con la regla blanda: si alcanza, se paga; si no, Hesk se lleva todo menos 15 y lo
## que falta (+10 %) queda de deuda (el sello LATE, −3 ★ una vez). {"due", "paid", "short", "debt", "late", "line"}.
func collect_dues() -> Dictionary:
	_ensure()
	var night := Game.day
	var due := dues_due(night)
	if due <= 0:
		return {}
	var out := {"night": night, "due": due, "paid": 0, "short": 0, "debt": 0, "late": false, "line": ""}
	var hesk: Dictionary = SeasonData.HESK
	if Game.credits >= due:
		Game.spend_credits(due)
		out["paid"] = due
		Game.debt = 0
		Game.dues_paid.append(night)
		out["line"] = String(hesk["paid"].get(night, hesk["paid_upkeep"]))
	else:
		var rule: Dictionary = SeasonData.SOFT_RULE
		var pay := maxi(0, Game.credits - int(rule["keep"]))
		if pay > 0:
			Game.spend_credits(pay)
		var short := due - pay
		out["paid"] = pay
		out["short"] = short
		Game.debt = int(round(short * (1.0 + float(rule["late_fee_k"]))))
		out["debt"] = Game.debt
		out["late"] = true
		Game.late_marks += 1
		Ranking.mark_late()
		out["line"] = String(hesk["short"])
	(state["dues_done"] as Array).append(night)
	Game.stat("dues_due", due)
	Game.stat("dues_paid", int(out["paid"]))
	Game.stat("dues_short", int(out["short"]))
	# las tres a tiempo: la placa "PAID IN FULL" (+1 ★ al día)
	var all_ok := true
	for nt in SeasonData.DUES:
		if not (int(nt) in Game.dues_paid):
			all_ok = false
	if all_ok and not Game.flag("paid_in_full", false):
		Game.set_flag("paid_in_full", true)
		out["paid_in_full"] = true
	# en el resumen de esta noche (el recap del final)
	Game.last_summary["dues_paid"] = int(out["paid"])
	Game.last_summary["dues_short"] = int(out["short"])
	if not Game.history.is_empty():
		Game.history[-1]["dues_paid"] = int(out["paid"])
		Game.history[-1]["dues_short"] = int(out["short"])
	return out

## Cuántas de las tres cuotas de la campaña se pagaron a tiempo.
func dues_on_time() -> int:
	var c := 0
	for nt in SeasonData.DUES:
		if int(nt) in Game.dues_paid:
			c += 1
	return c

# ------------------------------------------------------------------ las mejoras de Dolly (§4.1)

## Las 8 mejoras en su orden, con lo que hace falta: [{"id", "name", "cost", "desc", "detail", "owned", "locked",
## "why", "can_buy", "leaves"}].
func fittings_on_sale() -> Array:
	_ensure()
	var out: Array = []
	for id in SeasonData.FITTING_ORDER:
		var f: Dictionary = SeasonData.FITTINGS[id]
		var owned := Game.has_fitting(id)
		var why := ""
		if Game.day < int(f["day"]):
			why = "From day %d" % int(f["day"])
		elif Game.rep < int(f["rep"]):
			why = "Needs %s" % String(rep_tier(int(f["rep"]))["name"])
		var cost := int(f["cost"])
		out.append({"id": id, "name": String(f["name"]), "cost": cost, "desc": String(f["desc"]), "detail": String(f["detail"]),
			"owned": owned, "locked": why != "", "why": why, "can_buy": not owned and why == "" and Game.credits >= cost,
			"leaves": Game.credits - cost})
	return out

func buy_fitting(id: String) -> bool:
	_ensure()
	for f in fittings_on_sale():
		if String(f["id"]) == id:
			if not bool(f["can_buy"]):
				return false
			if not Game.spend_credits(int(f["cost"])):
				return false
			Game.add_fitting(id)
			Game.stat("fittings_spent", int(f["cost"]))
			return true
	return false

## La línea de la fila: "Leaves 85 cr · Dues 200 on night 6" (o "Leaves 85 cr" si ya no quedan cuotas).
func tradeoff_line(cost: int) -> String:
	var nd := next_dues()
	var left := Game.credits - cost
	if int(nd["night"]) > 0 and int(nd["night"]) <= SeasonData.LAST_DAY:
		return "Leaves %d cr · Dues %d on night %d" % [left, int(nd["amount"]) + int(nd["debt"]), int(nd["night"])]
	if int(nd["night"]) > 0:
		return "Leaves %d cr · Upkeep %d on night %d" % [left, int(nd["amount"]) + int(nd["debt"]), int(nd["night"])]
	return "Leaves %d cr" % left

# ------------------------------------------------------------------ los momentos de historia (§5.5)

## Los momentos que tocan ahora (no vistos): phase "morning" | "open" | "night"; ctx {"after_handover": who,
## "stars": n, "at_counter": who, "favour": who}. Cada uno: {"id", "who", "lines", "options", "must_choose", "low"}.
func beats(day: int, phase: String, ctx := {}) -> Array:
	_ensure()
	var out: Array = []
	if day > SeasonData.LAST_DAY:
		return out
	for id in SeasonData.BEAT_ORDER:
		var b: Dictionary = SeasonData.BEATS[id]
		if int(b["day"]) != day or String(b["phase"]) != phase or Game.beats_seen.has(id):
			continue
		var trig := String(b.get("trigger", ""))
		match trig:
			"":
				if not ctx.is_empty():
					continue
			"after_handover":
				if String(ctx.get("after_handover", "")) != String(b["who"]):
					continue
			"at_counter":
				if String(ctx.get("at_counter", "")) != String(b["who"]):
					continue
			"favour":
				if String(ctx.get("favour", "")) != String(b["who"]):
					continue
		var ok := true
		var need: Dictionary = b.get("need", {})
		for key in need:
			var v = Game.flag(String(key), null)
			if not (v in need[key]):
				ok = false
		if b.has("need_fix") and int(Game.flag("lune_fix", -1)) < int(b["need_fix"]):
			ok = false
		if bool(b.get("need_clatter", false)):
			var cn := int(Game.flag("clatter_n", 0))
			var cj: Dictionary = SeasonData.CLATTER_JOB
			if cn < int(cj["min_n"]) or float(Game.flag("clatter_stars", 0)) / float(maxi(1, cn)) < float(cj["min_avg"]):
				ok = false
		if not ok:
			continue
		var low := b.has("min_stars") and int(ctx.get("stars", 0)) < int(b["min_stars"])
		out.append({"id": id, "who": String(b["who"]), "lines": (b.get("lines_low" if low else "lines", []) as Array).duplicate(),
			"options": (b.get("options_low" if low and b.has("options_low") else "options", []) as Array).duplicate(true),
			"must_choose": bool(b.get("must_choose", false)), "low": low})
	return out

## Aplica la elección de un momento: las marcas, las estrellas del día, los créditos, el bono del tablero, los núcleos
## de lámpara. {"toast", "stars", "credits", "prop": {}, "reply", "cores"}.
func apply_beat(id: String, choice: String, low := false) -> Dictionary:
	_ensure()
	var out := {"toast": "", "stars": 0, "credits": 0, "prop": {}, "reply": "", "cores": int(Game.flag("cores", 0))}
	if not SeasonData.BEATS.has(id):
		return out
	var b: Dictionary = SeasonData.BEATS[id]
	Game.beats_seen[id] = true
	if not low:
		for key in b.get("set", {}):
			Game.set_flag(String(key), b["set"][key])
		if b.has("prop"):
			out["prop"].merge(b["prop"], true)
		if String(b.get("toast", "")) != "":
			out["toast"] = String(b["toast"])
		if int(b.get("bonus", 0)) != 0:
			Ranking.add_bonus(Ranking.ME, int(b["bonus"]))
		if b.has("core"):
			var c := add_core(String(b["core"]))
			out["cores"] = int(c["cores"])
			if String(c.get("toast", "")) != "" and String(out["toast"]) == "":
				out["toast"] = String(c["toast"])
	for o in b.get("options_low" if low and b.has("options_low") else "options", []):
		if String(o.get("id", "")) != choice:
			continue
		for key in o.get("set", {}):
			Game.set_flag(String(key), o["set"][key])
		if int(o.get("stars", 0)) != 0:
			Game.stat("event_stars", int(o["stars"]))
			out["stars"] = int(o["stars"])
		if int(o.get("credits", 0)) != 0:
			Game.add_credits(int(o["credits"]))
			Game.stat("event_credits", int(o["credits"]))
			out["credits"] = int(o["credits"])
		if o.has("prop"):
			out["prop"].merge(o["prop"], true)
		if String(o.get("toast", "")) != "":
			out["toast"] = String(o["toast"])
		out["reply"] = String(o.get("reply", ""))
	return out

## Un núcleo de lámpara más ("wreck" | "seven4" | "seven8"; cada fuente una vez; seven8 trae también el del día 4 si
## Nell lo perdió). {"toast", "cores"}.
func add_core(source: String) -> Dictionary:
	var srcs: Array = [source]
	if source == "seven8" and not Game.flag("core_seven4", false):
		srcs.append("seven4")
	var cores := int(Game.flag("cores", 0))
	var got := false
	for s in srcs:
		if Game.flag("core_" + s, false) or cores >= 3:
			continue
		Game.set_flag("core_" + s, true)
		cores += 1
		got = true
	Game.set_flag("cores", cores)
	if source == "wreck":
		Game.set_flag("core_wreck", true)
	return {"toast": SeasonData.CORE_TOAST if got else "", "cores": cores}

## Las mañas al entregar una reparación (§5.3) y la cuenta de los corredores. minute: la hora del reloj.
## {"pay_k", "tip", "line_patience", "stars", "toast", "say"}.
func on_handover(v: Dictionary, stars: int, secs: float, minute := -1) -> Dictionary:
	_ensure()
	var who := String(v.get("who", ""))
	var out := {"pay_k": 1.0, "tip": 0, "line_patience": 0.0, "stars": 0, "toast": "", "say": ""}
	var tw: Dictionary = SeasonData.TWISTS.get(who, {})
	match String(tw.get("kind", "")):
		"encore":
			if stars >= int(tw["stars"]):
				out["line_patience"] = float(tw["line_patience"])
				out["toast"] = String(tw["toast"])
		"quick":
			if secs <= float(tw["secs"]) and stars >= 1:
				out["pay_k"] = float(tw["pay_k"])
				out["toast"] = String(tw["toast"])
	# (P1) los arreglos de Clatter (su trabajo, la noche 6)
	if who == "clatter":
		Game.set_flag("clatter_n", int(Game.flag("clatter_n", 0)) + 1)
		Game.set_flag("clatter_stars", int(Game.flag("clatter_stars", 0)) + stars)
	# la caja de canciones de Lune del día 4 (la banda en Bronzemoon sin la caja de Rook)
	if who == "singer" and Game.day == 4:
		Game.set_flag("lune_fix", maxi(int(Game.flag("lune_fix", -1)), stars))
	# los corredores: solo cuenta lo entregado antes de las 2 PM
	var ex: Dictionary = v.get("extra", {})
	if ex.has("deadline_min") and (minute < 0 or minute <= int(ex["deadline_min"])):
		Game.stat("racers")
		Game.stat("racer_stars", stars)
		(state["racers"] as Dictionary)[who] = stars
	# los trabajos por familia (el bot humano)
	var fam := String(v.get("item", ""))
	var fj: Dictionary = state.get("family_jobs", {})
	fj[fam] = int(fj.get(fam, 0)) + 1
	state["family_jobs"] = fj
	# lo que dice uno de cada tres al irse, en los días especiales
	var fl := String(event_def().get("flavour", ""))
	if fl != "" and hash("%d-%d-%s" % [Game.run_seed, int(v.get("id", 0)), who]) % 3 == 0:
		out["say"] = fl
	return out

## El trabajo calificado de Tolle (§5.4): la nota y lo que trae; resuelve la caja tapada como "banquito".
## {"grade", "name", "stars", "credits", "rep", "line", "crate_line", "prop"}.
func on_graded(stars: int, ok := true) -> Dictionary:
	_ensure()
	var g := "noted"
	if ok and stars >= 3:
		g = "certified"
	elif ok and stars >= 2:
		g = "pass"
	var gd: Dictionary = SeasonData.GRADES[g]
	var out := {"grade": g, "name": String(gd["name"]), "stars": int(gd["stars"]), "credits": int(gd["credits"]),
		"rep": int(gd["rep"]), "line": String(SeasonData.GRADE_LINES[g if ok else "failed"]), "crate_line": "", "prop": {}}
	Game.set_flag("grade", g)
	if int(gd["stars"]) != 0:
		Game.stat("event_stars", int(gd["stars"]))
	if int(gd["credits"]) != 0:
		Game.add_credits(int(gd["credits"]))
		Game.stat("event_credits", int(gd["credits"]))
	if int(gd["rep"]) != 0:
		Game.add_rep(int(gd["rep"]))
	if g == "certified":
		out["prop"]["certificate"] = true
	if Game.flag("crate", "") == "covered":
		if ok and stars >= 2:
			out["crate_line"] = String(SeasonData.TOLLE_CRATE_AFTER["kept"])
		else:
			Game.set_flag("crate", "seized")
			Game.stat("event_stars", int(SeasonData.TOLLE_CRATE_AFTER["seized_stars"]))
			out["crate_line"] = String(SeasonData.TOLLE_CRATE_AFTER["seized"])
			out["prop"]["crate"] = false
	return out

## La carrera a las 3 PM (§5.4): ≥ 3 corredores a tiempo con un promedio ≥ 2.3 ★ → podio; 2 (o 3+ por debajo) →
## "Finished!"; menos → nada. Aplica las estrellas, los créditos y la marca (una sola vez).
## {"handed", "avg", "result", "winner", "line", "pipip_line", "stars", "credits"}.
func race_result() -> Dictionary:
	_ensure()
	if bool(state.get("race_called", false)):
		return (state.get("race", {}) as Dictionary).duplicate(true)
	var r: Dictionary = SeasonData.RACE
	var handed := int(Game.today.get("racers", 0))
	var avg := float(Game.today.get("racer_stars", 0)) / float(maxi(1, handed))
	var res := "none"
	if handed >= int(r["podium_n"]) and avg >= float(r["podium_avg"]) - 0.001:
		res = "podium"
	elif handed >= int(r["finished_n"]):
		res = "finished"
	var winner := ""
	var best := -1
	var racers: Dictionary = state.get("racers", {})
	for who in racers:
		if int(racers[who]) > best:
			best = int(racers[who])
			winner = String(who)
	var out := {"handed": handed, "avg": snappedf(avg, 0.01), "result": res, "winner": winner,
		"winner_name": Data.char_name(winner) if winner != "" else "", "stars": 0, "credits": 0, "pipip_line": ""}
	match res:
		"podium":
			out["stars"] = int(r["podium"]["stars"])
			out["credits"] = int(r["podium"]["credits"])
		"finished":
			out["stars"] = int(r["finished"]["stars"])
	out["line"] = String(SeasonData.RACE_LINES[res]).replace("{winner}", String(out["winner_name"]))
	if racers.has("pipip"):
		out["pipip_line"] = String(SeasonData.RACE_LINES["pipip"][clampi(int(racers["pipip"]), 0, 3)])
	if int(out["stars"]) != 0:
		Game.stat("event_stars", int(out["stars"]))
	if int(out["credits"]) != 0:
		Game.add_credits(int(out["credits"]))
		Game.stat("event_credits", int(out["credits"]))
	Game.set_flag("race", res)
	state["race_called"] = true
	state["race"] = out.duplicate(true)
	return out

## La banda en la puerta en Bronzemoon: +4 ★ "local favourite" (una vez, al abrir).
func band_today() -> bool:
	return event() == "festival" and Game.flag("band", false)

## Cuántos trabajos de una familia lleva hechos (el bot humano piensa más en los dos primeros).
func family_jobs(item: String) -> int:
	return int((state.get("family_jobs", {}) as Dictionary).get(item, 0))

# ------------------------------------------------------------------ guardar y cargar

func save_data() -> Dictionary:
	_ensure()
	return state.duplicate(true)

func load_data(d) -> void:
	_ensure()
	state = _defaults()
	if d is Dictionary:
		for key in d:
			if state.has(key):
				state[key] = Game._ints(d[key])
	# (los números de las listas vuelven como enteros)
	var dd: Array = []
	for x in state.get("dues_done", []):
		dd.append(int(x))
	state["dues_done"] = dd

# ------------------------------------------------------------------ (pruebas) un estado típico de un día

## --from=N: los créditos, las mejoras, las marcas y la reputación de una partida típica en la mañana del día N
## (perfil "good" | "human" | "sloppy"), y el tablero adelantado N-1 noches con las estrellas medidas (NOTES).
func debug_state(day: int, profile: String) -> void:
	_ensure()
	var p := profile if TYPICAL.has(profile) else "good"
	var t: Dictionary = TYPICAL[p]
	Game.new_game_state()
	Game.day = maxi(1, day)
	Game.intro_seen = true
	if day > SeasonData.LAST_DAY:
		Game.mode = "endless"
		Game.ending_seen = true
	for key in Data.TIPS:
		Game.tips_seen[key] = true
	for key in SeasonData.TIPS:
		Game.tips_seen[key] = true
	Game.tips_seen["first_done"] = true
	var i := clampi(day - 1, 0, 11)
	Game.credits = int(t["credits"][i])
	Game.rep = int(t["rep"][i])
	var nf_ := int(t["fittings"][i])
	for k_ in nf_:
		Game.fittings.append(SeasonData.FITTING_ORDER[k_])
	for nt in SeasonData.DUES:
		if int(nt) < day:
			Game.dues_paid.append(int(nt))
			(state["dues_done"] as Array).append(int(nt))
	for d2 in range(1, day + 1):
		update_unlocks(d2)
	if day > 2:
		Game.set_flag("crate", "kept" if p != "sloppy" else "refused")
		Game.beats_seen["crate_ask"] = true
	if day > 3:
		Game.beats_seen["rival_hello"] = true
	if day > 4:
		Game.beats_seen["seven_first"] = true
		Game.set_flag("lune_fix", 3 if p != "sloppy" else 1)
		if p != "sloppy":
			add_core("seven4")
	if day > 5:
		Game.beats_seen["glint_favour"] = true
		Game.set_flag("favour", "done" if p != "sloppy" else "refused")
	if day > 6:
		Game.beats_seen["tolle_crate"] = true
		Game.set_flag("grade", "certified" if p in ["good", "perfect"] else "pass")
		if p != "sloppy":
			Game.set_flag("crate", "covered")
	if day > 7:
		Game.beats_seen["seven_waking"] = true
		add_core("wreck")
	if day > 8:
		for b in ["rook_pickup", "band_lune", "seven_cores"]:
			Game.beats_seen[b] = true
		if p != "sloppy":
			Game.set_flag("crate", "delivered")
			Game.set_flag("band", true)
			add_core("seven8")
	if day > 9:
		Game.beats_seen["rook_key"] = true
		Game.set_flag("race", "podium" if p in ["good", "perfect"] else "finished")
	for k_ in [["cell", 2], ["chip", 1], ["speaker", 1], ["servo", 1], ["coil", 1]]:
		Game.add_part(k_[0], k_[1])
	Game.shelf_add("radio", 3)
	Game.shelf_add("helperbot", 2)
	Game.add_junk("thruster", "fan")
	Game.reset_today()
	Game.roll_pods()
	Game.dues_goal = int(next_dues()["amount"]) + Game.debt
	var spd: Array = t["stars"]
	Ranking.fast_forward(day - 1, spd)
	Game.sign_points = maxi(Game.sign_points, Ranking.milestone_points())

## Una partida típica por perfil (medida: la matriz final m7 + m5 sloppy, ver STARS TABLE en NOTES; la sacó
## work/py/typical.py): créditos y reputación en la
## mañana de cada día (1..12), mejoras compradas hasta esa mañana, estrellas de cada día.
const TYPICAL := {
	"perfect": {"credits": [50, 154, 195, 142, 167, 252, 111, 195, 508, 478, 661, 764],
		"rep": [0, 10, 20, 32, 42, 49, 61, 71, 83, 96, 108, 119], "fittings": [0, 0, 2, 4, 6, 7, 8, 8, 8, 8, 8, 8],
		"stars": [25, 28, 40, 34, 31, 47, 36, 52, 58, 98, 40, 33]},
	"good": {"credits": [50, 147, 184, 133, 171, 266, 50, 113, 385, 226, 386, 549],
		"rep": [0, 10, 19, 31, 42, 48, 56, 64, 74, 85, 96, 107], "fittings": [0, 0, 2, 4, 4, 6, 7, 7, 7, 8, 8, 8],
		"stars": [24, 28, 38, 32, 30, 38, 30, 44, 48, 92, 42, 33]},
	"human": {"credits": [50, 148, 189, 100, 162, 210, 99, 192, 396, 150, 267, 264],
		"rep": [0, 10, 16, 22, 31, 36, 44, 53, 61, 70, 78, 88], "fittings": [0, 0, 1, 2, 3, 4, 4, 4, 4, 5, 6, 7],
		"stars": [24, 18, 24, 28, 22, 36, 30, 38, 36, 74, 34, 32]},
	"sloppy": {"credits": [50, 136, 156, 120, 156, 238, 116, 152, 208, 15, 85, 118],
		"rep": [0, 5, 7, 9, 10, 10, 10, 11, 12, 12, 14, 15], "fittings": [0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
		"stars": [20, 16, 16, 13, 12, 18, 10, 16, 14, 28, 16, 13]},
}
