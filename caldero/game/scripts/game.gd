extends Node
## Estado de la partida, reglas de alquimia, economía y guardado.

signal gold_changed(value: int)
signal renombre_changed(points: int, level: int)
signal level_up(level: int)
signal stock_changed
signal potions_changed
signal recipes_changed(new_id: String)
signal upgrades_changed
signal journal_changed

const SAVE_PATH := "user://caldero_save.json"
const SAVE_VERSION := 1

var gold := 40
var renombre := 0
var day := 1
var stock := {}
var potions: Array = []          # [{"id": String, "potency": int}]
var discovered := {}             # potion_id -> mejor potencia
var upgrades := {}               # upgrade_id -> true
var hero_progress := {}          # hero_id -> capítulos completados
var hero_last_day := {}          # hero_id -> día del último capítulo
var journal: Array = []          # [{"day": int, "hero": String, "text": String}]
var lucky := false
var cat_petted_day := 0
var stats := {"sold": 0, "brewed": 0, "earned": 0, "perfect": 0}
var tutorial_done := false
var music_volume := 0.7
var sfx_volume := 0.8

# Resumen del día en curso (no se guarda entre días)
var today := {"earned": 0, "renombre": 0, "sold": 0, "new_recipes": [], "journal": []}

func _ready() -> void:
	randomize()
	new_game_state()

func new_game_state() -> void:
	gold = 40
	renombre = 0
	day = 1
	stock = {}
	for id in Data.INGREDIENT_ORDER:
		stock[id] = 3 if Data.INGREDIENTS[id]["level"] == 0 else 0
	potions = []
	discovered = {"sueno_profundo": 0}
	upgrades = {}
	hero_progress = {}
	hero_last_day = {}
	for h in Data.HERO_ORDER:
		hero_progress[h] = 0
		hero_last_day[h] = -1
	journal = []
	lucky = false
	cat_petted_day = 0
	stats = {"sold": 0, "brewed": 0, "earned": 0, "perfect": 0}
	tutorial_done = false
	magic_reset()   # --- MAGIC (R3 MAGIC3: runas)
	story_reset()   # --- STORY
	reset_today()

func reset_today() -> void:
	today = {"earned": 0, "renombre": 0, "sold": 0, "new_recipes": [], "journal": []}

# ------------------------------------------------------------------ niveles y mejoras

func level() -> int:
	var lv := 0
	for i in Data.LEVELS.size():
		if renombre >= Data.LEVELS[i]["points"]:
			lv = i
	return lv

func level_name(lv: int = -1) -> String:
	if lv < 0:
		lv = level()
	return Data.LEVELS[lv]["name"]

func level_progress() -> float:
	var lv := level()
	if lv >= Data.LEVELS.size() - 1:
		return 1.0
	var a: int = Data.LEVELS[lv]["points"]
	var b: int = Data.LEVELS[lv + 1]["points"]
	return clampf(float(renombre - a) / float(b - a), 0.0, 1.0)

func has_upgrade(id: String) -> bool:
	return upgrades.get(id, false)

func cauldron_slots() -> int:
	return 3 if has_upgrade("caldero_ancho") else 2

func potion_capacity() -> int:
	return 12 if has_upgrade("estante") else 6

func customers_per_day() -> int:
	var n := 4
	if level() >= 2:
		n += 1
	if has_upgrade("campanilla"):
		n += 1
	return n

func tip_bonus() -> float:
	var b := 0.0
	if has_upgrade("alfombra"):
		b += 0.10
	if has_upgrade("farolillos"):
		b += 0.15
	return b

func potency_bonus() -> int:
	return 1 if has_upgrade("caldero_cobre") else 0

func ingredient_unlocked(id: String) -> bool:
	return Data.INGREDIENTS[id]["level"] <= level()

func unlocked_ingredients() -> Array:
	var out := []
	for id in Data.INGREDIENT_ORDER:
		if ingredient_unlocked(id):
			out.append(id)
	return out

# ------------------------------------------------------------------ alquimia

## Suma las esencias de una lista de ingredientes.
func essence_mix(ings: Array) -> Dictionary:
	var m := {}
	for id in ings:
		var ess: Dictionary = Data.INGREDIENTS[id]["ess"]
		for k in ess:
			m[k] = m.get(k, 0) + ess[k]
	return m

## Las esencias ordenadas por fuerza (empates según el orden fijo).
func ranked_essences(m: Dictionary) -> Array:
	var keys := []
	for k in Data.ESSENCE_ORDER:
		if m.get(k, 0) > 0:
			keys.append(k)
	keys.sort_custom(func(a, b):
		if m[a] != m[b]:
			return m[a] > m[b]
		return Data.ESSENCE_ORDER.find(a) < Data.ESSENCE_ORDER.find(b))
	return keys

func potion_for_pair(e1: String, e2: String) -> String:
	for pid in Data.POTIONS:
		var pair: Array = Data.POTIONS[pid]["pair"]
		if (pair[0] == e1 and pair[1] == e2) or (pair[0] == e2 and pair[1] == e1):
			return pid
	return ""

## Evalúa una mezcla. Devuelve {} si no hay suficientes esencias.
func evaluate(ings: Array) -> Dictionary:
	if ings.size() < 2:
		return {}
	var m := essence_mix(ings)
	var ranked := ranked_essences(m)
	if ranked.size() < 2:
		# una sola esencia: no forma poción
		return {"potion": "", "top": ranked, "mix": m, "potency": 0}
	var pid := potion_for_pair(ranked[0], ranked[1])
	var potency: int = m[ranked[0]] + m[ranked[1]]
	return {"potion": pid, "top": [ranked[0], ranked[1]], "mix": m, "potency": potency}

func stars_for(potency: int) -> int:
	if potency >= 7:
		return 3
	if potency >= 5:
		return 2
	return 1

func price_for(pid: String, potency: int, misses: int) -> Dictionary:
	var base: int = Data.POTIONS[pid]["base"]   # --- R3 MAGIC3: ya no hay pergaminos (las runas pagan aparte: rune_bonus)
	var mult: float = [1.0, 1.0, 1.35, 1.75][stars_for(potency)]
	var price := int(round(base * mult))
	var tip_mult := 1.0 - 0.2 * mini(misses, 2)
	var tip := int(round(base * 0.25 * tip_mult + base * tip_bonus()))
	return {"price": price, "tip": maxi(tip, 0)}

## Pociones que se pueden preparar con lo desbloqueado y el tamaño del caldero.
func brewable_potions() -> Dictionary:
	var ings := unlocked_ingredients()
	var found := {}
	var n := ings.size()
	for i in n:
		for j in range(i, n):
			var r := evaluate([ings[i], ings[j]])
			if r.get("potion", "") != "":
				found[r["potion"]] = true
			if cauldron_slots() >= 3:
				for k in range(j, n):
					var r3 := evaluate([ings[i], ings[j], ings[k]])
					if r3.get("potion", "") != "":
						found[r3["potion"]] = true
	return found

# ------------------------------------------------------------------ economía e inventario

func add_gold(v: int) -> void:
	gold = maxi(0, gold + v)
	if v > 0:
		stats["earned"] += v
		today["earned"] += v
	gold_changed.emit(gold)

func add_renombre(v: int) -> void:
	var before := level()
	renombre += v
	today["renombre"] += v
	renombre_changed.emit(renombre, level())
	var after := level()
	if after > before:
		for lv in range(before + 1, after + 1):
			level_up.emit(lv)

func buy_ingredient(id: String, qty: int = 1, day_order := false) -> bool:   # --- R3 PAPER: day_order = encargo de día (x2)
	var cost: int = market_price(id, day_order) * qty   # --- R3 PAPER
	if gold < cost or not ingredient_unlocked(id):
		return false
	add_gold(-cost)
	stock[id] = stock.get(id, 0) + qty
	stock_changed.emit()
	return true

# --- R3 PAPER: el precio del mercado ---------------------------------------------------------------------------
## Lo que cuesta una unidad en el mercado. Por la mañana, en el puesto: el precio normal. Durante el día, el encargo
## que trae Pip («Encargo al mercado», day_order = true) cuesta el doble: es para lo que falte de última hora.
## La usan el panel del mercado (lo que se ve) y buy_ingredient (lo que se cobra). Sirve también para MAGIC_ITEMS.
const DAY_ORDER_MULT := 2

func market_price(id: String, day_order := false) -> int:
	var base := 0
	if Data.INGREDIENTS.has(id):
		base = int(Data.INGREDIENTS[id]["price"])
	else:
		var mi = Data.get("MAGIC_ITEMS")
		if mi is Dictionary and mi.has(id):
			base = int(mi[id].get("price", 0))
	return base * (DAY_ORDER_MULT if day_order else 1)
# --- end R3 PAPER

func use_ingredient(id: String) -> bool:
	if stock.get(id, 0) <= 0:
		return false
	stock[id] -= 1
	stock_changed.emit()
	return true

func return_ingredient(id: String) -> void:
	stock[id] = stock.get(id, 0) + 1
	stock_changed.emit()

func buy_upgrade(id: String) -> bool:
	var u: Dictionary = Data.UPGRADES[id]
	if has_upgrade(id) or gold < u["cost"] or level() < u["level"]:
		return false
	add_gold(-u["cost"])
	upgrades[id] = true
	upgrades_changed.emit()
	return true

func add_potion(pid: String, potency: int) -> void:
	potions.append({"id": pid, "potency": potency})
	sort_potions()   # --- R3 MAGIC3: entre pociones iguales, las sin runa primero
	stats["brewed"] += 1
	if not discovered.has(pid):
		discovered[pid] = potency
		today["new_recipes"].append(pid)
		recipes_changed.emit(pid)
	else:
		discovered[pid] = max(discovered[pid], potency)
		recipes_changed.emit("")
	potions_changed.emit()

## Devuelve una poción al estante (sin contarla como nueva).
func return_potion(p: Dictionary) -> void:
	potions.append(p)
	sort_potions()   # --- R3 MAGIC3: ya no hay pergaminos; la poción vuelve con sus runas
	potions_changed.emit()

func potion_index(pid: String, potency: int) -> int:
	for i in potions.size():
		if potions[i]["id"] == pid and potions[i]["potency"] == potency:
			return i
	return potions.size() - 1

func take_potion(index: int) -> Dictionary:
	if index < 0 or index >= potions.size():
		return {}
	var p: Dictionary = potions[index]
	potions.remove_at(index)
	potions_changed.emit()
	return p

func potions_full() -> bool:
	return potions.size() >= potion_capacity()

# ------------------------------------------------------------------ historias

func next_chapter(hero: String) -> int:
	return hero_progress.get(hero, 0)

func hero_available(hero: String, brewable: Dictionary) -> bool:
	var c := next_chapter(hero)
	var chapters: Array = Data.HEROES[hero]
	if c >= chapters.size():
		return false
	if hero_last_day.get(hero, -1) >= day:
		return false
	var ch: Dictionary = chapters[c]
	return level() >= ch["level"] and brewable.has(ch["potion"])

func complete_chapter(hero: String) -> Dictionary:
	var c := next_chapter(hero)
	var ch: Dictionary = Data.HEROES[hero][c]
	hero_progress[hero] = c + 1
	hero_last_day[hero] = day
	var entry := {"day": day, "hero": hero, "chapter": c, "text": ch["journal"]}
	journal.append(entry)
	today["journal"].append(entry)
	var gift: Dictionary = ch.get("gift", {})
	if gift.has("gold"):
		add_gold(gift["gold"])
	if gift.has("item"):
		stock[gift["item"]] = stock.get(gift["item"], 0) + gift.get("qty", 1)
		stock_changed.emit()
	journal_changed.emit()
	return gift

## Crea la fila de clientes del día.
# --- STORY: primero, quienes vuelven a contar cómo les fue (visitas: no cuentan en el total; algunas traen otro
# pedido); después, los aventureros y los vecinos y viajeros del pueblo (cada día llegan caras nuevas: "arrives" en
# Data.CHARACTERS). Nadie viene dos veces el mismo día, ni quien espera noticias o está ofendido por una queja.
func plan_day() -> Array:
	var queue := []
	var brewable := brewable_potions()
	var total := customers_per_day()
	var taken := {}
	if day == 1 and not tutorial_done:
		var t: Dictionary = Data.TUTORIAL_REQUEST.duplicate()
		t["kind"] = "villager"
		t["tutorial"] = true
		queue.append(t)
		taken[t["who"]] = true
	# visitas con noticias (como mucho 2 al día)
	var visits := []
	var follows := 0
	for o in due_visits(2):
		if taken.has(o["who"]):
			continue
		var v := {"kind": "return", "who": o["who"], "outcome": o}
		var f := _follow_request(o, brewable)
		if not f.is_empty():
			v["follow"] = f
			follows += 1
		visits.append(v)
		taken[o["who"]] = true
	# aventureros (no los que esperan noticias de su capítulo)
	var heroes := []
	for h in Data.HERO_ORDER:
		if hero_available(h, brewable) and story_free(h) and not taken.has(h):
			heroes.append(h)
	heroes.shuffle()
	var hero_slots := []
	for h in heroes.slice(0, 2 if day > 1 else 1):
		hero_slots.append(_hero_request(h, next_chapter(h)))
		taken[h] = true
	# vecinos y viajeros
	var villagers := _pick_villagers(maxi(0, total - queue.size() - hero_slots.size() - follows), brewable, taken)
	var rest := villagers + hero_slots
	rest.shuffle()
	for v in visits:
		rest.insert(randi() % (rest.size() + 1), v)
	queue.append_array(rest)
	return queue
# --- end STORY

func morning_harvest() -> Array:
	var got := []
	if has_upgrade("huerto"):
		stock["raiz_mandragora"] = stock.get("raiz_mandragora", 0) + 2
		stock["lagrima_sirena"] = stock.get("lagrima_sirena", 0) + 2
		got = ["raiz_mandragora", "lagrima_sirena"]
		stock_changed.emit()
	return got

# --- STORY: las noticias llegan después ---------------------------------------------------------------------
# Una poción no hace efecto en el mostrador: el cliente paga el precio y se la lleva. Cómo le fue lo cuenta después,
# por carta (el correo de la mañana) o volviendo a la tienda, y con la noticia llegan la propina, el renombre, los
# regalos y la página del diario. Si la poción no era la correcta llega una queja: se le devuelve el dinero, baja un
# poco el renombre y tarda unos días en volver. Los textos los arma scripts/story.gd.

var pending: Array = []          # noticias por llegar (ver Story.make_outcome): {"id", "who", "ok", "via", "due", ...}
var away := {}                   # who -> día desde el que vuelve a venir (tras una queja)
var last_seen := {}              # who -> último día que vino con un pedido
var met := {}                    # who -> true: ya se presentó en la tienda
var recent_requests: Array = []  # claves de pedidos recientes (Story.request_key), para no repetirlos pronto
var hero_retry := {}             # aventurero -> true: su último capítulo salió mal y volverá a intentarlo
var mail_seen := false           # ya leyó su primer correo (el panel deja de explicar cómo funciona)
var _outcome_seq := 0

func story_reset() -> void:
	pending = []
	away = {}
	last_seen = {}
	met = {}
	recent_requests = []
	hero_retry = {}
	mail_seen = false
	_outcome_seq = 0

func story_save() -> Dictionary:
	return {"pending": pending, "away": away, "last_seen": last_seen, "met": met, "recent": recent_requests,
		"hero_retry": hero_retry, "mail_seen": mail_seen, "seq": _outcome_seq}

func story_load(d: Dictionary) -> void:
	story_reset()
	for o in d.get("pending", []):
		if o is Dictionary and o.has("who"):
			var e: Dictionary = o.duplicate(true)
			for k in ["id", "potency", "stars", "price", "day", "tip", "renombre", "due", "chapter"]:
				if e.has(k):
					e[k] = int(e[k])
			e["ok"] = bool(e.get("ok", false))
			pending.append(e)
	for k in d.get("away", {}):
		away[k] = int(d["away"][k])
	for k in d.get("last_seen", {}):
		last_seen[k] = int(d["last_seen"][k])
	for k in d.get("met", {}):
		met[k] = true
	for k in d.get("recent", []):
		recent_requests.append(String(k))
	for k in d.get("hero_retry", {}):
		hero_retry[k] = true
	mail_seen = bool(d.get("mail_seen", false))
	_outcome_seq = int(d.get("seq", 0))
	for o in pending:
		_outcome_seq = maxi(_outcome_seq, int(o.get("id", 0)))

## Guarda la noticia de una entrega (la arma Story.make_outcome).
func schedule_outcome(o: Dictionary) -> void:
	_outcome_seq += 1
	o["id"] = _outcome_seq
	pending.append(o)

func has_pending(who: String) -> bool:
	for o in pending:
		if o["who"] == who:
			return true
	return false

## Si alguien puede venir hoy con un pedido nuevo: no espera noticias ni está ofendido por una queja.
func story_free(who: String) -> bool:
	return not has_pending(who) and int(away.get(who, 0)) <= day

## Las cartas que llegan hoy. Se sacan de la lista: hay que resolverlas (resolve_outcome) y guardar.
func take_due_letters() -> Array:
	var out := []
	var keep := []
	for o in pending:
		if String(o.get("via", "letter")) != "visit" and int(o.get("due", 0)) <= day:
			out.append(o)
		else:
			keep.append(o)
	pending = keep
	out.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	return out

## Las visitas que tocan hoy. Siguen en la lista hasta que la visita ocurre (resolve_visit).
func due_visits(max_n: int) -> Array:
	var out := []
	for o in pending:
		if String(o.get("via", "")) == "visit" and int(o.get("due", 0)) <= day:
			out.append(o)
	out.sort_custom(func(a, b): return int(a["due"]) < int(b["due"]))
	return out.slice(0, max_n)

## Llegó la visita: saca su noticia de la lista y la resuelve ({} si ya no estaba).
func resolve_visit(id: int) -> Dictionary:
	for i in pending.size():
		if int(pending[i].get("id", -1)) == id:
			var o: Dictionary = pending[i]
			pending.remove_at(i)
			return resolve_outcome(o)
	return {}

## Aplica lo que trae una noticia y devuelve el resumen para mostrarlo (Story.reward_line):
## {"tip", "gift_gold", "renombre" (negativo si bajó), "items": [{"id", "qty"}], "journal", "refund", "away", "gift_text"}
func resolve_outcome(o: Dictionary) -> Dictionary:
	var res := {"tip": 0, "gift_gold": 0, "renombre": 0, "items": [], "journal": false, "refund": 0, "away": 0, "gift_text": ""}
	var who := String(o.get("who", ""))
	var hero := String(o.get("req_kind", "")) == "hero" and Data.HEROES.has(who)
	if o.get("ok", false):
		var tip := int(o.get("tip", 0))
		if tip > 0:
			add_gold(tip)
			res["tip"] = tip
		if hero:
			var c := int(o.get("chapter", next_chapter(who)))
			if c == next_chapter(who) and c < Data.HEROES[who].size():
				var gift := complete_chapter(who)
				res["journal"] = true
				res["gift_gold"] = int(gift.get("gold", 0))
				if gift.has("item"):
					res["items"].append({"id": gift["item"], "qty": int(gift.get("qty", 1))})
			hero_retry.erase(who)
		elif String(o.get("grade", "")) == "great":
			var g: Dictionary = Data.CHARACTERS.get(who, {}).get("gift", {})
			if g.has("item"):
				var item := String(g["item"])
				var qty := int(g.get("qty", 1))
				if Data.INGREDIENTS.has(item) and ingredient_unlocked(item):
					stock[item] = stock.get(item, 0) + qty
					stock_changed.emit()
					res["items"].append({"id": item, "qty": qty})
				else:
					add_gold(5 * qty)
					res["gift_gold"] += 5 * qty
			if g.has("gold"):
				add_gold(int(g["gold"]))
				res["gift_gold"] += int(g["gold"])
			res["gift_text"] = String(g.get("text", ""))
		var gain := int(o.get("renombre", 0))
		if gain > 0:
			add_renombre(gain)
			res["renombre"] = gain
	else:
		var refund := mini(int(o.get("price", 0)), gold)
		if refund > 0:
			add_gold(-refund)
			res["refund"] = refund
		res["renombre"] = -lose_renombre(1)
		if hero:
			hero_last_day[who] = day + 1
			hero_retry[who] = true
		else:
			away[who] = day + 3
			res["away"] = 3
	return res

## Baja el renombre sin perder el nivel ya alcanzado. Devuelve cuánto bajó.
func lose_renombre(v: int) -> int:
	var before := renombre
	renombre = maxi(int(Data.LEVELS[level()]["points"]), renombre - v)
	if renombre != before:
		renombre_changed.emit(renombre, level())
	return before - renombre

## El pedido de un aventurero para su capítulo c.
func _hero_request(h: String, c: int) -> Dictionary:
	var ch: Dictionary = Data.HEROES[h][c]
	var r := {"kind": "hero", "who": h, "potion": ch["potion"], "text": ch["text"], "hint": ch["hint"],
		"thanks": ch["thanks"], "chapter": c}
	for k in ["react", "fail", "via", "plan"]:
		if ch.has(k):
			r[k] = ch[k]
	if hero_retry.get(h, false):
		r["retry"] = true
	return r

## Quien vuelve con buenas noticias a veces trae otro pedido (los aventureros, su siguiente capítulo).
func _follow_request(o: Dictionary, brewable: Dictionary) -> Dictionary:
	if not o.get("ok", false):
		return {}
	var who := String(o["who"])
	if String(o.get("req_kind", "")) == "hero":
		var c := int(o.get("chapter", 0)) + 1
		if Data.HEROES.has(who) and c < Data.HEROES[who].size():
			var ch: Dictionary = Data.HEROES[who][c]
			if level() >= int(ch["level"]) and brewable.has(ch["potion"]) and randf() < 0.65:
				var r := _hero_request(who, c)
				r.erase("retry")
				return r
		return {}
	if randf() > 0.45:
		return {}
	var opts := []
	for r in Story.request_pool():
		if String(r.get("who", "")) == who and Story.request_ok(r, brewable) and not recent_requests.has(Story.request_key(r)):
			opts.append(r)
	if opts.is_empty():
		return {}
	var q: Dictionary = opts.pick_random().duplicate()
	q["kind"] = "villager"
	_note_request(q)
	return q

## Elige n vecinos o viajeros distintos con un pedido que se pueda cumplir hoy. Primero quienes acaban de llegar al
## pueblo (sin quitarle todo el día a los de siempre), luego quienes hace más que no vienen. Pedidos con runas: 1 al
## día (2 con renombre «Alquimista»).   # --- R3 MAGIC3
func _pick_villagers(n: int, brewable: Dictionary, taken: Dictionary) -> Array:
	var out := []
	if n <= 0:
		return out
	var by_who := {}
	for pass_i in 2:   # 1ª pasada: sin pedidos recientes; 2ª (si faltan): se permiten
		by_who.clear()
		for r in Story.request_pool():
			var who := String(r.get("who", ""))
			if who == "" or taken.has(who) or not story_free(who):
				continue
			if Data.HEROES.has(who) and order_runes(r).is_empty():
				continue   # los aventureros vienen por su historia (o, a veces, por una poción con runas)   # --- R3 MAGIC3
			if int(Data.CHARACTERS.get(who, {}).get("arrives", 1)) > day:
				continue
			if int(r.get("level", 0)) > level() or int(r.get("day", 0)) > day:
				continue
			if not Story.request_ok(r, brewable):
				continue
			if pass_i == 0 and recent_requests.has(Story.request_key(r)):
				continue
			if not by_who.has(who):
				by_who[who] = []
			by_who[who].append(r)
		if by_who.size() >= n:
			break
	var scored := []
	var runes_left := rune_orders_today()   # --- R3 MAGIC3: pedidos con runas hoy (1; 2 con renombre «Alquimista»)
	for w in by_who:
		var s := randf() * 3.0 + clampf(float(day - int(last_seen.get(w, -10))), 0.0, 10.0)
		if not met.has(w):
			s += 20.0
		# --- R3 MAGIC3: quien puede traer un pedido con runas pasa un poco antes (para que lleguen los del día)
		if runes_left > 0 and by_who[w].any(func(r): return not order_runes(r).is_empty()):
			s += 6.0
		scored.append([s, w])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	# 1ª pasada: como mucho max_new caras nuevas (para que también vengan los de siempre); 2ª: llenar lo que falte
	var max_new := maxi(1, n - 1)
	var newcomers := 0
	var picked := {}
	for cap_pass in 2:
		for e in scored:
			if out.size() >= n:
				break
			var w: String = e[1]
			if picked.has(w):
				continue
			if cap_pass == 0 and not met.has(w):
				if newcomers >= max_new:
					continue
				newcomers += 1
			var options: Array = by_who[w].duplicate()
			options.shuffle()
			# --- R3 MAGIC3: mientras falten pedidos con runas hoy, primero los de runas; cumplida la cuota, ninguno más
			if runes_left > 0:
				options.sort_custom(func(a, b): return order_runes(a).size() > order_runes(b).size())
			var chosen := {}
			for r in options:
				if not order_runes(r).is_empty() and runes_left <= 0:
					continue
				chosen = r
				break
			if chosen.is_empty():
				continue
			if not order_runes(chosen).is_empty():
				runes_left -= 1
			# --- end R3 MAGIC3
			var q: Dictionary = chosen.duplicate()
			q["kind"] = "villager"
			out.append(q)
			picked[w] = true
			_note_request(q)
	return out

func _note_request(r: Dictionary) -> void:
	recent_requests.append(Story.request_key(r))
	while recent_requests.size() > 40:
		recent_requests.pop_front()
	last_seen[String(r.get("who", ""))] = day
# --- end STORY

# ------------------------------------------------------------------ guardado

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var d := {
		"version": SAVE_VERSION, "gold": gold, "renombre": renombre, "day": day, "stock": stock,
		"potions": potions, "discovered": discovered, "upgrades": upgrades, "hero_progress": hero_progress,
		"hero_last_day": hero_last_day, "journal": journal, "lucky": lucky, "cat_petted_day": cat_petted_day,
		"stats": stats, "tutorial_done": tutorial_done, "music_volume": music_volume, "sfx_volume": sfx_volume,
	}
	d["magic"] = magic_save()   # --- MAGIC
	d["story"] = story_save()   # --- STORY: noticias pendientes, quién vino, quién está ofendido
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	new_game_state()
	gold = int(d.get("gold", gold))
	renombre = int(d.get("renombre", 0))
	day = int(d.get("day", 1))
	for k in d.get("stock", {}):
		stock[k] = int(d["stock"][k])
	potions = []
	for p in d.get("potions", []):
		# --- R3 MAGIC3: con sus runas (las de una partida vieja no tienen)
		var pd := {"id": String(p["id"]), "potency": int(p["potency"])}
		for k in ["rune", "rune2"]:
			if p is Dictionary and Data.RUNES.has(String(p.get(k, ""))):
				pd[k] = String(p[k])
				pd[k + "_stars"] = clampi(int(p.get(k + "_stars", 1)), 1, 3)
		if Data.POTIONS.has(pd["id"]):
			potions.append(pd)
		# --- end R3 MAGIC3
	discovered = {}
	for k in d.get("discovered", {}):
		discovered[k] = int(d["discovered"][k])
	upgrades = d.get("upgrades", {})
	for k in d.get("hero_progress", {}):
		hero_progress[k] = int(d["hero_progress"][k])
	for k in d.get("hero_last_day", {}):
		hero_last_day[k] = int(d["hero_last_day"][k])
	journal = []
	for e in d.get("journal", []):
		journal.append({"day": int(e["day"]), "hero": String(e["hero"]), "chapter": int(e.get("chapter", 0)), "text": String(e["text"])})
	lucky = bool(d.get("lucky", false))
	cat_petted_day = int(d.get("cat_petted_day", 0))
	var st: Dictionary = d.get("stats", {})
	for k in stats:
		stats[k] = int(st.get(k, 0))
	tutorial_done = bool(d.get("tutorial_done", true))
	music_volume = float(d.get("music_volume", music_volume))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	var md = d.get("magic", {})   # --- MAGIC
	magic_load(md if md is Dictionary else {})   # --- MAGIC
	story_load(d.get("story", {}))   # --- STORY
	reset_today()
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# --- R3 MAGIC3: el libro de runas (Data.RUNES): runas que se inscriben en la ETIQUETA de una poción del estante -------
# Una poción puede llevar runas: {"id", "potency", "rune", "rune_stars", "rune2", "rune2_stars"} (la etiqueta tiene un
# hueco; dos desde el renombre «Maestra de pociones»). El grimorio del escritorio (scripts/ui/grimoire_ui.gd) las
# inscribe con enchant(); algunos clientes las piden (Data.RUNE_REQUESTS, "runes"); al entregar, cada runa pedida que
# va en la etiqueta paga un extra según sus estrellas (rune_bonus) y la que falta baja la propina de la noticia
# (scripts/story.gd). Ya no hay pergaminos: las partidas viejas se convierten al cargar (magic_load).

signal magic_changed      # tintas, páginas del grimorio, o lo abrió por primera vez

## Lo que la maestra dejó en el cajón del escritorio (se recibe al abrir el grimorio por primera vez, con la runa de Prisa).
const MAGIC_STARTER := {"tinta_brasa": 2}
## Lo que paga una runa pedida según sus estrellas (x su "value"): 1 estrella, 2, 3.
const RUNE_STAR_MULT := [0.0, 0.6, 1.0, 1.5]
## Partidas viejas (pergaminos): hechizo -> runa, y lo que vale lo que ya no existe (se devuelve en oro al cargar).
const LEGACY_SPELL_RUNE := {"sello_calor": "prisa", "hechizo_brotes": "dulzor", "runa_calma": "calma", "pergamino_luz": "duracion",
	"runa_escarcha": "frescor", "mensaje_alado": "alas", "talisman_umbra": "sigilo", "sello_protector": "fuerza"}
const LEGACY_SCROLL_BASE := {"sello_calor": 16, "hechizo_brotes": 16, "runa_calma": 20, "pergamino_luz": 20, "runa_escarcha": 22,
	"mensaje_alado": 26, "talisman_umbra": 28, "sello_protector": 34}
const LEGACY_ITEM_PRICE := {"papel": 2, "vitela": 6}

var magic_unlocked := false   # ya abrió el grimorio: desde entonces llegan pedidos con runas
var items := {}               # tintas y páginas compradas (ids de Data.MAGIC_ITEMS) -> cantidad
var rune_pages := {}          # runa -> "new" (aprendida y sin leer) o "read"
var magic_stats := {"runes": 0, "perfect": 0, "inks": 0}
var legacy_refund := 0        # oro devuelto al cargar una partida vieja (pergaminos, papel): main.gd lo avisa y lo pone a 0

func magic_reset() -> void:
	magic_unlocked = false
	items = {}
	rune_pages = {}
	magic_stats = {"runes": 0, "perfect": 0, "inks": 0}
	legacy_refund = 0
	magic_changed.emit()

## Primera vez que abre el grimorio: la nota de la maestra, la tinta del cajón y las páginas que ya le tocan (Prisa,
## y las que ya ganó con su renombre o le regalaron). Quedan como nuevas (brillan en el libro).
func unlock_magic() -> void:
	if magic_unlocked:
		return
	magic_unlocked = true
	for id in MAGIC_STARTER:
		items[id] = item_count(id) + MAGIC_STARTER[id]
	for id in Data.RUNE_ORDER:
		if rune_known(id) and not rune_pages.has(id):
			rune_pages[id] = "new"
	magic_changed.emit()

## El escritorio brilla: el grimorio todavía no se abrió (desde el día 2) o hay páginas sin leer.
func desk_glows() -> bool:
	return (not magic_unlocked and day >= 2) or has_new_pages()

# ------------------------------------------------ tintas (y la página de Tobías)

func item_count(id: String) -> int:
	return int(items.get(id, 0))

## Compra en el puesto de Tobías. Las páginas ("max": 1) se compran una vez: enseñan su runa.
func buy_item(id: String, qty: int = 1) -> bool:
	if not Data.MAGIC_ITEMS.has(id):
		return false
	var it: Dictionary = Data.MAGIC_ITEMS[id]
	var mx := int(it.get("max", 0))
	if mx > 0:
		qty = mini(qty, mx - item_count(id))
		if qty <= 0:
			return false
	var cost: int = int(it["price"]) * qty
	if gold < cost:
		return false
	add_gold(-cost)
	add_item(id, qty)
	return true

func add_item(id: String, qty: int = 1) -> void:
	items[id] = maxi(0, item_count(id) + qty)
	magic_changed.emit()

func rune_ink(rune: String) -> String:
	return String(Data.RUNES[rune]["ink"]) if Data.RUNES.has(rune) else ""

# ------------------------------------------------ páginas del grimorio

## Si ya sabe la runa: la nota de la maestra ("starter"), su renombre ("level"), el regalo de un viajero ("gift") o la
## página de Tobías ("shop"). Todo, desde que abrió el grimorio. Las de una partida vieja están en rune_pages.
func rune_known(id: String) -> bool:
	if not magic_unlocked or not Data.RUNES.has(id):
		return false
	if rune_pages.has(id):
		return true
	var r: Dictionary = Data.RUNES[id]
	if r.get("starter", false) or level() >= int(r.get("level", 99)):
		return true
	if r.has("shop") and item_count(String(r["shop"])) > 0:
		return true
	var g: Dictionary = r.get("gift", {})
	return not g.is_empty() and int(hero_progress.get(g["hero"], 0)) >= int(g["chapter"])

func known_runes() -> Array:
	var out := []
	for id in Data.RUNE_ORDER:
		if rune_known(id):
			out.append(id)
	return out

## Páginas recién aprendidas que todavía no se anunciaron (las marca como nuevas en el grimorio).
func new_rune_pages() -> Array:
	var out := []
	for id in Data.RUNE_ORDER:
		if rune_known(id) and not rune_pages.has(id):
			rune_pages[id] = "new"
			out.append(id)
	if not out.is_empty():
		magic_changed.emit()
	return out

func page_is_new(id: String) -> bool:
	return rune_pages.get(id, "") == "new"

func mark_page_read(id: String) -> void:
	if page_is_new(id):
		rune_pages[id] = "read"
		magic_changed.emit()

func has_new_pages() -> bool:
	for id in rune_pages:
		if rune_pages[id] == "new":
			return true
	return false

# ------------------------------------------------ runas en la etiqueta

## Huecos de la etiqueta: 1 (2 desde el renombre «Maestra de pociones», cuando llegan pedidos de dos runas).
func label_slots() -> int:
	return 2 if level() >= 3 else 1

## Las runas de una poción: [{"id", "stars"}], en el orden en que se inscribieron.
func potion_runes(p: Dictionary) -> Array:
	var out := []
	for k in ["rune", "rune2"]:
		var id := String(p.get(k, ""))
		if id != "":
			out.append({"id": id, "stars": clampi(int(p.get(k + "_stars", 1)), 1, 3)})
	return out

func potion_rune_ids(p: Dictionary) -> Array:
	return potion_runes(p).map(func(r): return r["id"])

## Las runas que pide un cliente (su ticket): ids de Data.RUNES.
func order_runes(req: Dictionary) -> Array:
	var out := []
	var rs = req.get("runes", [])
	if rs is Array:
		for r in rs:
			if Data.RUNES.has(String(r)):
				out.append(String(r))
	return out

## La siguiente runa que le falta a esa poción para ese pedido ("" si no le falta ninguna).
func next_rune_for(p: Dictionary, req: Dictionary) -> String:
	var have := potion_rune_ids(p)
	for r in order_runes(req):
		if not have.has(r):
			return r
	return ""

## "" si se puede inscribir esa runa en esa poción; si no, el motivo: "none" (no hay poción), "page" (no sabe la
## runa), "same" (ya la lleva), "full" (la etiqueta no tiene hueco) o "ink" (no le queda esa tinta).
func enchant_problem(index: int, rune: String) -> String:
	if index < 0 or index >= potions.size():
		return "none"
	if not rune_known(rune):
		return "page"
	var have := potion_rune_ids(potions[index])
	if have.has(rune):
		return "same"
	if have.size() >= label_slots():
		return "full"
	if item_count(rune_ink(rune)) <= 0:
		return "ink"
	return ""

## Inscribe la runa en la poción del estante (gasta 1 frasco de su tinta). stars: el trazo (1 a 3). Devuelve la poción
## encantada ({} si no se pudo). El estante se reordena: búscala después con find_potion().
func enchant(index: int, rune: String, stars: int) -> Dictionary:
	if enchant_problem(index, rune) != "":
		return {}
	var ink := rune_ink(rune)
	items[ink] = item_count(ink) - 1
	var p: Dictionary = potions[index]
	var k := "rune" if String(p.get("rune", "")) == "" else "rune2"
	p[k] = rune
	p[k + "_stars"] = clampi(stars, 1, 3)
	magic_stats["runes"] += 1
	if stars >= 3:
		magic_stats["perfect"] += 1
	sort_potions()
	potions_changed.emit()
	magic_changed.emit()
	return p

## Orden del estante: como siempre (receta, potencia) y, entre iguales, las sin runa primero.
func sort_potions() -> void:
	potions.sort_custom(func(a, b):
		if a["id"] != b["id"]:
			return Data.POTION_ORDER.find(a["id"]) < Data.POTION_ORDER.find(b["id"])
		if a["potency"] != b["potency"]:
			return a["potency"] > b["potency"]
		return ",".join(potion_rune_ids(a)) < ",".join(potion_rune_ids(b)))

## Dónde quedó esa poción en el estante (mismo id, potencia y runas). -1 si no está.
func find_potion(p: Dictionary) -> int:
	var key := ",".join(potion_rune_ids(p))
	for i in potions.size():
		var q: Dictionary = potions[i]
		if q["id"] == p.get("id", "") and int(q["potency"]) == int(p.get("potency", -1)) and ",".join(potion_rune_ids(q)) == key:
			return i
	return -1

## Qué runas del pedido van en la etiqueta: {"want": [ids], "matched": [[id, estrellas]], "missing": [ids],
## "extra": [ids que no pidió]}.
func rune_check(item: Dictionary, req: Dictionary) -> Dictionary:
	var want := order_runes(req)
	var got := potion_runes(item)
	var matched := []
	var missing := []
	var extra := []
	for id in want:
		var s := 0
		for g in got:
			if g["id"] == id:
				s = int(g["stars"])
		if s > 0:
			matched.append([id, s])
		else:
			missing.append(id)
	for g in got:
		if not want.has(g["id"]):
			extra.append(g["id"])
	return {"want": want, "matched": matched, "missing": missing, "extra": extra}

## Lo que el cliente paga de más por las runas que pidió y van en la etiqueta (según sus estrellas).
func rune_bonus(item: Dictionary, req: Dictionary) -> int:
	var total := 0.0
	for m in rune_check(item, req)["matched"]:
		total += float(Data.RUNES[m[0]]["value"]) * RUNE_STAR_MULT[clampi(int(m[1]), 0, 3)]
	return int(round(total))

## Cuántos pedidos con runas puede haber hoy: ninguno sin grimorio; 1; 2 desde el renombre «Alquimista».
func rune_orders_today() -> int:
	if not magic_unlocked or known_runes().is_empty():
		return 0
	return 2 if level() >= 2 else 1

# ------------------------------------------------ tinta en el caldero

## La tinta que saldría de esta mezcla: la decide la esencia MÁS FUERTE (empates: el orden de ESSENCE_ORDER).
## Devuelve {"ink", "ess", "amount", "qty"} o {} (hacen falta al menos 2 ingredientes). Frascos: 1, +1 con 4 o más
## de esa esencia, +1 con 6 o más (y main.gd suma 1 si se remueve perfecto).
func ink_for_mix(ings: Array) -> Dictionary:
	if ings.size() < 2:
		return {}
	var m := essence_mix(ings)
	var ranked := ranked_essences(m)
	if ranked.is_empty():
		return {}
	var e: String = ranked[0]
	var amount: int = m[e]
	for k in Data.INK_ORDER:
		if Data.INKS[k]["ess"] == e:
			return {"ink": k, "ess": e, "amount": amount, "qty": 1 + (1 if amount >= 4 else 0) + (1 if amount >= 6 else 0)}
	return {}

# ------------------------------------------------ guardado (save_game / load_game lo llaman)

func magic_save() -> Dictionary:
	return {"unlocked": magic_unlocked, "items": items, "pages": rune_pages, "stats": magic_stats}

## Carga la magia. Una partida de antes (pergaminos) se convierte: los pergaminos del estante y el papel o la vitela
## se devuelven en oro (legacy_refund), las páginas de hechizos pasan a ser las de sus runas.
func magic_load(d: Dictionary) -> void:
	magic_unlocked = bool(d.get("unlocked", false))
	legacy_refund = 0
	items = {}
	var it = d.get("items", {})
	if it is Dictionary:
		for k in it:
			if Data.MAGIC_ITEMS.has(k):
				items[k] = int(it[k])
			elif LEGACY_ITEM_PRICE.has(k):
				legacy_refund += int(LEGACY_ITEM_PRICE[k]) * maxi(0, int(it[k]))
	var sc = d.get("scrolls", [])
	if sc is Array:
		for s in sc:
			if s is Dictionary:
				var base := int(LEGACY_SCROLL_BASE.get(String(s.get("id", "")), 16))
				legacy_refund += int(round(base * [1.0, 1.0, 1.35, 1.75][stars_for(int(s.get("potency", 3)))]))
	rune_pages = {}
	var pg = d.get("pages", {})
	if pg is Dictionary:
		for k in pg:
			var id := String(LEGACY_SPELL_RUNE.get(k, k))
			if Data.RUNES.has(id):
				var st := String(pg[k])
				rune_pages[id] = "new" if st == "new" and rune_pages.get(id, "new") == "new" else "read"
	var st = d.get("stats", {})
	magic_stats = {"runes": 0, "perfect": 0, "inks": 0}
	if st is Dictionary:
		magic_stats["runes"] = int(st.get("runes", st.get("scrolls", 0)))
		magic_stats["perfect"] = int(st.get("perfect", 0))
		magic_stats["inks"] = int(st.get("inks", 0))
	if legacy_refund > 0:
		gold += legacy_refund
		gold_changed.emit(gold)
	magic_changed.emit()
# --- end R3 MAGIC3
