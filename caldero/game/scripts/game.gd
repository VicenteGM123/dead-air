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
	magic_reset()   # --- MAGIC
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
	var base: int = Data.POTIONS[pid]["base"] if Data.POTIONS.has(pid) else Data.SPELLS[pid]["base"]   # --- MAGIC: también pergaminos
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

func buy_ingredient(id: String, qty: int = 1) -> bool:
	var cost: int = Data.INGREDIENTS[id]["price"] * qty
	if gold < cost or not ingredient_unlocked(id):
		return false
	add_gold(-cost)
	stock[id] = stock.get(id, 0) + qty
	stock_changed.emit()
	return true

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
	potions.sort_custom(func(a, b):
		if a["id"] != b["id"]:
			return Data.POTION_ORDER.find(a["id"]) < Data.POTION_ORDER.find(b["id"])
		return a["potency"] > b["potency"])
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
	# --- MAGIC: un pergamino devuelto vuelve a su estante
	if p.get("kind", "") == "scroll":
		return_scroll(p)
		return
	# --- end MAGIC
	potions.append(p)
	potions.sort_custom(func(a, b):
		if a["id"] != b["id"]:
			return Data.POTION_ORDER.find(a["id"]) < Data.POTION_ORDER.find(b["id"])
		return a["potency"] > b["potency"])
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
## pueblo (sin quitarle todo el día a los de siempre), luego quienes hace más que no vienen. Pergaminos: 1 al día
## (2 con renombre «Alquimista»).
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
			if Data.HEROES.has(who) and Story.wanted_kind(r) != "scroll":
				continue   # los aventureros vienen por su historia (o, a veces, por un pergamino)
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
	for w in by_who:
		var s := randf() * 3.0 + clampf(float(day - int(last_seen.get(w, -10))), 0.0, 10.0)
		if not met.has(w):
			s += 20.0
		scored.append([s, w])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	# 1ª pasada: como mucho max_new caras nuevas (para que también vengan los de siempre); 2ª: llenar lo que falte
	var max_new := maxi(1, n - 1)
	var newcomers := 0
	var scrolls_left := 2 if level() >= 2 else 1
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
			var chosen := {}
			for r in options:
				if Story.wanted_kind(r) == "scroll" and scrolls_left <= 0:
					continue
				chosen = r
				break
			if chosen.is_empty():
				continue
			if Story.wanted_kind(chosen) == "scroll":
				scrolls_left -= 1
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
		potions.append({"id": String(p["id"]), "potency": int(p["potency"])})
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

# --- MAGIC: grimorio, tintas, papel y pergaminos (Data.SPELLS, Data.MAGIC_ITEMS) ------------------------------------
# Los pergaminos se guardan y se entregan como las pociones: {"id": hechizo, "potency": int}. La potencia sale del
# papel (3 papel de trapo, 5 vitela) + 2 si el trazo de la runa fue perfecto: 3 = 1 estrella, 5 = 2, 7 = 3 (stars_for).

signal magic_changed      # materiales, páginas del grimorio, o lo abrió por primera vez
signal scrolls_changed    # el estante de pergaminos cambió

const SCROLL_CAPACITY := 6
## Lo que la maestra dejó en el cajón del escritorio (se recibe al abrir el grimorio por primera vez).
const MAGIC_STARTER := {"papel": 4, "tinta_brasa": 1, "tinta_savia": 1}

var magic_unlocked := false   # ya abrió el grimorio: desde entonces llegan clientes que piden pergaminos
var items := {}               # papel, vitela y tintas (ids de Data.MAGIC_ITEMS) -> cantidad
var scrolls: Array = []       # [{"id": hechizo, "potency": int}] el estante de pergaminos
var spell_pages := {}         # hechizo -> "new" (aprendido y sin leer) o "read"
var spells_made := {}         # hechizo -> mejor potencia inscrita
var magic_stats := {"scrolls": 0, "perfect": 0, "inks": 0}

func magic_reset() -> void:
	magic_unlocked = false
	items = {}
	scrolls = []
	spell_pages = {}
	spells_made = {}
	magic_stats = {"scrolls": 0, "perfect": 0, "inks": 0}
	_mark_known_pages()
	magic_changed.emit()
	scrolls_changed.emit()

## Las páginas que ya se saben quedan como nuevas sin anunciarlas (al empezar, o con una partida vieja).
func _mark_known_pages() -> void:
	for id in Data.SPELL_ORDER:
		if spell_known(id) and not spell_pages.has(id):
			spell_pages[id] = "new"

## Primera vez que abre el grimorio: recibe los materiales del cajón y aprende las páginas que ya le tocan.
func unlock_magic() -> void:
	if magic_unlocked:
		return
	magic_unlocked = true
	for id in MAGIC_STARTER:
		items[id] = item_count(id) + MAGIC_STARTER[id]
	for id in Data.SPELL_ORDER:
		if spell_known(id) and not spell_pages.has(id):
			spell_pages[id] = "new"
	magic_changed.emit()

# ------------------------------------------------ materiales (el puesto de Tobías los vende con buy_item / item_count)

func item_count(id: String) -> int:
	return int(items.get(id, 0))

func buy_item(id: String, qty: int = 1) -> bool:
	if not Data.MAGIC_ITEMS.has(id):
		return false
	var cost: int = Data.MAGIC_ITEMS[id]["price"] * qty
	if gold < cost:
		return false
	add_gold(-cost)
	add_item(id, qty)
	return true

func add_item(id: String, qty: int = 1) -> void:
	items[id] = maxi(0, item_count(id) + qty)
	magic_changed.emit()

# ------------------------------------------------ páginas del grimorio

## Se aprende con el renombre de Data.SPELLS[id]["level"], o antes si un viajero la regala ("gift").
func spell_known(id: String) -> bool:
	var s: Dictionary = Data.SPELLS[id]
	if level() >= int(s["level"]):
		return true
	var g: Dictionary = s.get("gift", {})
	return not g.is_empty() and int(hero_progress.get(g["hero"], 0)) >= int(g["chapter"])

func known_spells() -> Array:
	var out := []
	for id in Data.SPELL_ORDER:
		if spell_known(id):
			out.append(id)
	return out

## Páginas recién aprendidas que todavía no se anunciaron (las marca como nuevas en el grimorio).
func new_spell_pages() -> Array:
	var out := []
	for id in Data.SPELL_ORDER:
		if spell_known(id) and not spell_pages.has(id):
			spell_pages[id] = "new"
			out.append(id)
	if not out.is_empty():
		magic_changed.emit()
	return out

func page_is_new(id: String) -> bool:
	return spell_pages.get(id, "") == "new"

func mark_page_read(id: String) -> void:
	if page_is_new(id):
		spell_pages[id] = "read"

## Hay alguna página nueva sin leer (el grimorio del escritorio brilla).
func has_new_pages() -> bool:
	for id in spell_pages:
		if spell_pages[id] == "new":
			return true
	return false

# ------------------------------------------------ inscribir pergaminos

## Materiales de un pergamino: {material: cantidad} = 1 hoja (papel o vitela) + las tintas del hechizo.
func spell_cost(id: String, paper: String) -> Dictionary:
	var c := {paper: 1}
	var inks: Dictionary = Data.SPELLS[id]["inks"]
	for k in inks:
		c[k] = int(c.get(k, 0)) + int(inks[k])
	return c

## "" si se puede inscribir ahora; si no, el motivo (texto para el jugador).
func inscribe_problem(id: String, paper: String) -> String:
	if not spell_known(id):
		return "Todavía no puedes leer esta página."
	if scrolls_full():
		return "Tu estante de pergaminos está lleno (%d)." % scroll_capacity()
	var c := spell_cost(id, paper)
	var miss := []
	for k in c:
		if item_count(k) < c[k]:
			miss.append(Data.MAGIC_ITEMS[k]["name"])
	if not miss.is_empty():
		return "Te falta: %s." % ", ".join(miss)
	return ""

func scroll_potency(paper: String, perfect: bool) -> int:
	return int(Data.PAPERS[paper]["potency"]) + (2 if perfect else 0)

## Gasta los materiales y deja el pergamino en el estante. Devuelve {"id", "potency"} (o {} si no se pudo).
func inscribe(id: String, paper: String, perfect: bool) -> Dictionary:
	if inscribe_problem(id, paper) != "":
		return {}
	var c := spell_cost(id, paper)
	for k in c:
		items[k] = item_count(k) - int(c[k])
	var pot := scroll_potency(paper, perfect)
	magic_stats["scrolls"] += 1
	if perfect:
		magic_stats["perfect"] += 1
	spells_made[id] = maxi(int(spells_made.get(id, 0)), pot)
	var s := add_scroll(id, pot)
	magic_changed.emit()
	return s

# ------------------------------------------------ el estante de pergaminos

func scroll_capacity() -> int:
	return SCROLL_CAPACITY

func scrolls_full() -> bool:
	return scrolls.size() >= scroll_capacity()

func _sort_scrolls() -> void:
	scrolls.sort_custom(func(a, b):
		if a["id"] != b["id"]:
			return Data.SPELL_ORDER.find(a["id"]) < Data.SPELL_ORDER.find(b["id"])
		return a["potency"] > b["potency"])

func add_scroll(id: String, potency: int) -> Dictionary:
	var s := {"id": id, "potency": potency}
	scrolls.append(s)
	_sort_scrolls()
	scrolls_changed.emit()
	return s

func scroll_index(id: String, potency: int) -> int:
	for i in scrolls.size():
		if scrolls[i]["id"] == id and scrolls[i]["potency"] == potency:
			return i
	return scrolls.size() - 1

func take_scroll(index: int) -> Dictionary:
	if index < 0 or index >= scrolls.size():
		return {}
	var s: Dictionary = scrolls[index]
	scrolls.remove_at(index)
	scrolls_changed.emit()
	return s

## Vuelve al estante (por ejemplo, un pergamino que el cliente no quiso). Acepta el diccionario de la entrega.
func return_scroll(s: Dictionary) -> void:
	scrolls.append({"id": String(s["id"]), "potency": int(s["potency"])})
	_sort_scrolls()
	scrolls_changed.emit()

## Saca un pergamino del estante para entregarlo: como una poción ({"id", "potency"}) más "kind": "scroll".
## main.gd lo pasa a _success / _wrong igual que una poción.
func take_scroll_for_delivery(index: int) -> Dictionary:
	var s := take_scroll(index)
	if s.is_empty():
		return s
	var d := s.duplicate()
	d["kind"] = "scroll"
	return d

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

# ------------------------------------------------ clientes que piden pergaminos

## Cambia algunos vecinos del día por clientes que piden un pergamino: 1 al día (2 con renombre «Alquimista»),
## solo desde que abrió el grimorio. 'others': los demás clientes del día (para no repetir a nadie).
func magic_scroll_customers(villagers: Array, others: Array = []) -> Array:
	if not magic_unlocked or villagers.is_empty():
		return villagers
	var n := mini(1 + (1 if level() >= 2 else 0), villagers.size())
	var taken := {}
	for r in others:
		taken[r["who"]] = true
	for i in villagers.size() - n:
		taken[villagers[i]["who"]] = true
	var picks := scroll_requests(n, taken)
	var out := villagers.duplicate()
	for i in picks.size():
		out[out.size() - 1 - i] = picks[i]
	return out

## Pedidos de pergaminos posibles hoy: hechizos ya aprendidos, personajes que existen (nombre y sprite) y los
## capítulos que pidan ("needs"). Devuelve copias listas para la fila ("kind": "villager", "potion": "").
func scroll_requests(n: int, taken_in: Dictionary = {}) -> Array:
	var taken := taken_in.duplicate()
	var pool := []
	for r in Data.SCROLL_REQUESTS:
		var who: String = r["who"]
		if taken.has(who) or not spell_known(r["scroll"]) or not Data.CHARACTERS.has(who):
			continue
		if not ResourceLoader.exists("res://assets/chars/%s_idle.png" % who):
			continue
		var need: Dictionary = r.get("needs", {})
		if not need.is_empty() and int(hero_progress.get(need["hero"], 0)) < int(need["chapter"]):
			continue
		pool.append(r)
	pool.shuffle()
	var out := []
	for r in pool:
		if out.size() >= n:
			break
		if taken.has(r["who"]):
			continue
		var q: Dictionary = r.duplicate()
		q["kind"] = "villager"
		if not q.has("potion"):
			q["potion"] = ""
		taken[r["who"]] = true
		out.append(q)
	return out

## Lo que dice el cliente al recibir el pergamino que pidió: lee la etiqueta y nota la tinta (todavía no lo usó).
func scroll_react_line(s: Dictionary) -> String:
	var d: Dictionary = Data.SPELLS[s["id"]]
	var stars := stars_for(int(s["potency"]))
	var heads := ["¡%s, justo lo que necesitaba!", "¡%s! Y con qué letra tan bonita.", "¡%s! Nunca había visto un trazo tan firme."]
	var react: Array = d.get("react", [""])
	return (heads[stars - 1] % d["name"]) + " " + str(react.pick_random())

## Lo que dice el cliente si no es lo que pidió (un pergamino se reconoce en el acto: tiene etiqueta).
## Devuelve "" cuando no hay pergaminos de por medio (se usa el texto de siempre).
func scroll_wrong_line(p: Dictionary, req: Dictionary) -> String:
	var is_scroll: bool = p.get("kind", "") == "scroll"
	var wants_scroll: bool = req.get("scroll", "") != ""
	if is_scroll and wants_scroll:
		return Data.SCROLL_WRONG_LINES.pick_random() % Data.SPELLS[p["id"]]["name"]
	if is_scroll:
		return Data.POTION_NOT_SCROLL
	if wants_scroll:
		return Data.SCROLL_NOT_POTION
	return ""

# ------------------------------------------------ guardado (save_game / load_game lo llaman)

func magic_save() -> Dictionary:
	return {"unlocked": magic_unlocked, "items": items, "scrolls": scrolls, "pages": spell_pages,
		"made": spells_made, "stats": magic_stats}

func magic_load(d: Dictionary) -> void:
	magic_unlocked = bool(d.get("unlocked", false))
	items = {}
	var it = d.get("items", {})
	if it is Dictionary:
		for k in it:
			if Data.MAGIC_ITEMS.has(k):
				items[k] = int(it[k])
	scrolls = []
	var sc = d.get("scrolls", [])
	if sc is Array:
		for s in sc:
			if s is Dictionary and Data.SPELLS.has(String(s.get("id", ""))):
				scrolls.append({"id": String(s["id"]), "potency": int(s.get("potency", 3))})
	_sort_scrolls()
	spell_pages = {}
	var pg = d.get("pages", {})
	if pg is Dictionary:
		for k in pg:
			if Data.SPELLS.has(k):
				spell_pages[k] = String(pg[k])
	spells_made = {}
	var mk = d.get("made", {})
	if mk is Dictionary:
		for k in mk:
			if Data.SPELLS.has(k):
				spells_made[k] = int(mk[k])
	var st = d.get("stats", {})
	for k in magic_stats:
		magic_stats[k] = int(st.get(k, 0)) if st is Dictionary else 0
	if spell_pages.is_empty():
		_mark_known_pages()
	magic_changed.emit()
	scrolls_changed.emit()
# --- end MAGIC
