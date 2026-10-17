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
	var base: int = Data.POTIONS[pid]["base"]
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
func plan_day() -> Array:
	var queue := []
	var brewable := brewable_potions()
	var total := customers_per_day()
	if day == 1 and not tutorial_done:
		var t: Dictionary = Data.TUTORIAL_REQUEST.duplicate()
		t["kind"] = "villager"
		t["tutorial"] = true
		queue.append(t)
	# aventureros disponibles
	var heroes := []
	for h in Data.HERO_ORDER:
		if hero_available(h, brewable):
			heroes.append(h)
	heroes.shuffle()
	var max_heroes := 2 if day > 1 else 1
	var hero_slots := []
	for h in heroes.slice(0, max_heroes):
		var ch: Dictionary = Data.HEROES[h][next_chapter(h)]
		hero_slots.append({"kind": "hero", "who": h, "potion": ch["potion"], "text": ch["text"], "hint": ch["hint"],
			"thanks": ch["thanks"], "chapter": next_chapter(h)})
	# vecinos
	var pool := []
	for r in Data.VILLAGER_REQUESTS:
		if brewable.has(r["potion"]):
			pool.append(r)
	pool.shuffle()
	var villagers := []
	var vi := 0
	while queue.size() + hero_slots.size() + villagers.size() < total and pool.size() > 0:
		var r: Dictionary = pool[vi % pool.size()].duplicate()
		r["kind"] = "villager"
		villagers.append(r)
		vi += 1
	# mezclar: los héroes no van primero el día 1
	var rest := villagers + hero_slots
	rest.shuffle()
	# evitar el mismo vecino dos veces seguidas cuando se pueda
	for i in range(1, rest.size()):
		if rest[i]["who"] == rest[i - 1]["who"]:
			for j in range(i + 1, rest.size()):
				if rest[j]["who"] != rest[i - 1]["who"]:
					var tmp = rest[i]
					rest[i] = rest[j]
					rest[j] = tmp
					break
	queue.append_array(rest)
	return queue.slice(0, total)

func morning_harvest() -> Array:
	var got := []
	if has_upgrade("huerto"):
		stock["raiz_mandragora"] = stock.get("raiz_mandragora", 0) + 2
		stock["lagrima_sirena"] = stock.get("lagrima_sirena", 0) + 2
		got = ["raiz_mandragora", "lagrima_sirena"]
		stock_changed.emit()
	return got

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
	reset_today()
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
