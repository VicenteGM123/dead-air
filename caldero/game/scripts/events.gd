extends RefCounted
class_name Events
## --- R4 EVENTS: los eventos. Cada pocos días llega por carta una invitación (la Academia de Magia de Valmora, el
## Concurso de Pociones de Robledal, la Feria del Torneo de Brisaclara) con quién invita, qué es, el día, el premio, el
## riesgo, la inscripción y la dificultad. Se acepta (se paga la inscripción) o se rechaza. Si se acepta, ese día no
## se abre la tienda: ella viaja, juega el evento en su escenario (scripts/event_game.gd, scripts/ui/event_ui.gd y
## EventScenes) y vuelve de noche con una medalla (oro, plata, bronce) o sin nada (eso cuesta renombre). La
## inscripción se pierde siempre.
## Aquí: el catálogo, el calendario, quién puede invitar (renombre), los premios y los riesgos, el jurado del concurso,
## los rivales y los textos. El estado (la invitación que espera respuesta, el evento reservado, el historial y los
## trofeos) vive en game.gd (bloque R4 EVENTS). Los números del balance están en NOTES.txt de la lane.

const KINDS := ["academia", "concurso", "torneo"]
const FIRST_DAY := 2          # la primera invitación (el día 1 es el del primer cliente)
const LEAD := 2               # días entre la carta y el evento («pasado mañana»)
const FIRST_GAP := 4          # de la primera invitación a la segunda
const GAP_MIN := 4            # después, una cada 4 a 6 días
const GAP_MAX := 6

## Medallas: el id va en Game.today["event"]["medal"] (contrato con RANK); el nombre es lo que se lee.
const MEDALS := ["gold", "silver", "bronze", "none"]
const MEDAL_WORD := {"gold": "gold", "silver": "silver", "bronze": "bronze", "none": "no medal"}
const MEDAL_TITLE := {"gold": "Gold Medal", "silver": "Silver Medal", "bronze": "Bronze Medal", "none": "No Medal"}
const MEDAL_COLOR := {"gold": Color("e8b74a"), "silver": Color("c9d3e0"), "bronze": Color("c98a52"), "none": Color("8f8698")}

## El catálogo. "host": quién invita y presenta (su sprite); "seal": el sello de lacre de la carta (assets/ui);
## "min_renombre" / "min_day": desde cuándo puede invitarla; "fee": inscripción [base, por nivel]; "gold_k": cuánto
## del oro de la medalla (la feria ya paga propinas); "hard": +1 a la dificultad. Textos cortos (dieta de la ronda 3).
const CATALOG := {
	"academia": {
		"name": "Academy Exam", "long": "The Academy of Magic Exam", "place": "Valmora",
		"host": "roxa", "host_name": "Roxa", "host_title": "Academy teacher", "seal": "evui_seal_academia",
		"min_renombre": 0, "min_day": 2, "fee": [10, 8], "gold_k": 1.0, "hard": 0,
		"what": "{n} identical potions, against the clock.",
		"hello": "Dear colleague,",
		"body": "My students have an exam, and each one needs a potion. Up for brewing them against the clock?",
		"sign": "Roxa, (substitute) teacher at the Academy",
		"intro": "Welcome! {n} students, {n} potions of {p}. Don't let the cauldron go cold!",
		"end": {"gold": "Top marks!", "silver": "Everyone passed!", "bronze": "A pass… by a whisker.",
			"none": "Oops. My students missed their exam."},
		"crowd": ["roxa", "tobias", "anselmo", "anciano", "lirien", "elda"],
		"visitors": ["pip", "kit", "wren", "sylwen", "zaria", "nyra", "marta", "aldric"],
	},
	"concurso": {
		"name": "Oakdale Contest", "long": "The Oakdale Potion Contest", "place": "Oakdale",
		"host": "elda", "host_name": "Sister Elda", "host_title": "contest judge", "seal": "evui_seal_concurso",
		"min_renombre": 12, "min_day": 5, "fee": [14, 9], "gold_k": 1.15, "hard": 1,
		"what": "3 rounds, 3 themes, 3 judges. Fizz is in.",
		"hello": "Dear sister,",
		"body": "Oakdale is holding its Potion Contest: three rounds, one theme each. Lirien is a guest judge. Fizz has already signed up…",
		"sign": "Sister Elda, of Oakdale",
		"intro": "Welcome to the Contest! Three rounds, one theme per round. Present your best potion.",
		"end": {"gold": "First place! All of Oakdale is cheering.", "silver": "Second place! So close.",
			"bronze": "Third place. Well done!", "none": "No luck this year, child."},
		"crowd": ["fizz", "panadera", "granjero", "anciano", "marta", "mabel", "vianne", "hassim", "borin", "pip"],
		"visitors": [],
	},
	"torneo": {
		"name": "Tournament Fair", "long": "The Clearbreeze Tournament Fair", "place": "Clearbreeze",
		"host": "isolde", "host_name": "Dame Isolde", "host_title": "captain of the Order of Dawn", "seal": "evui_seal_torneo",
		"min_renombre": 6, "min_day": 5, "fee": [16, 10], "gold_k": 0.6, "hard": 1,
		"what": "A stall at the fair: knights in a hurry.",
		"hello": "To the honorable alchemist,",
		"body": "The Order of Dawn is holding its tournament and offers you a stall at the fair. My knights pay well… if they don't have to wait.",
		"sign": "Isolde of Clearbreeze, captain of the Order of Dawn",
		"intro": "Your stall is ready! They want vigor, healing and courage. Don't keep them waiting.",
		"end": {"gold": "The Order of Dawn thanks you!", "silver": "Good work! My knights are happy.",
			"bronze": "You did it. Some waited too long.", "none": "My knights left thirsty."},
		"crowd": ["isolde", "vianne", "hassim", "mabel", "anselmo", "panadera", "granjero", "nyra", "borin"],
		"visitors": ["aldric", "brann", "ragnar", "bram", "pip", "kit", "wren", "sylwen"],
	},
}

## La Academia pide pociones iguales de una receta de dos ingredientes iguales: potencia 6 (2 estrellas); un removido
## perfecto la sube a 7 (3 estrellas). [poción, ingrediente]: solo las que ya puede preparar (ingrediente desbloqueado).
const ACADEMIA_RECIPES := [
	["sueno_profundo", "raiz_mandragora"], ["ojo_nocturno", "hongo_violeta"], ["tonico_brio", "ambar_abeja"],
	["elixir_alba", "pluma_fenix"], ["velo_invernal", "escarcha_luna"], ["vigor_verde", "polvo_estrella"],
]

## Los temas del concurso: "fit" = qué tan bien encaja cada poción (2 = justo lo que pide el tema, 1 = se acerca).
const THEMES := [
	{"id": "dormir", "text": "Something sleepy", "fit": {"sueno_profundo": 2, "balsamo_helado": 1}},
	{"id": "valiente", "text": "Something brave", "fit": {"tonico_brio": 2, "elixir_alba": 1, "vigor_verde": 1}},
	{"id": "dulce", "text": "Something sweet", "fit": {"tonico_brio": 2, "vigor_verde": 1, "ojo_nocturno": 1}},
	{"id": "noche", "text": "Something for the night", "fit": {"ojo_nocturno": 2, "velo_invernal": 1, "sueno_profundo": 1}},
	{"id": "fresco", "text": "Something cool", "fit": {"balsamo_helado": 2, "brebaje_lucido": 1, "velo_invernal": 1}},
	{"id": "pensar", "text": "Something clever", "fit": {"brebaje_lucido": 2, "ojo_nocturno": 1}},
	{"id": "viaje", "text": "Something for a long trip", "fit": {"vigor_verde": 2, "tonico_brio": 1, "elixir_alba": 1}},
	{"id": "frio", "text": "Something for the cold", "fit": {"elixir_alba": 2, "pocion_clima": 2, "tonico_brio": 1}},
	{"id": "sigilo", "text": "Something to stay unseen", "fit": {"velo_invernal": 2, "humo_furtivo": 2, "ojo_nocturno": 1}},
	{"id": "sanar", "text": "Something healing", "fit": {"elixir_alba": 2, "balsamo_helado": 2, "vigor_verde": 1}},
]

## El jurado del concurso (en los marcadores Judge0..Judge2 del escenario). "likes": lo que más le importa.
const JUDGES := [
	{"id": "elda", "name": "Sister Elda", "likes": "tema"},
	{"id": "lirien", "name": "Lirien", "likes": "removido", "guest": true},
	{"id": "grumm", "name": "Grumm", "likes": "potencia"},
]
## Lo que dice cada jurado según las estrellas que da (1..5).
const JUDGE_LINES := {
	"elda": ["This is off-theme, child.", "Not quite the theme…", "It'll do. Barely.", "Smart choice.", "Just what the theme asked for!"],
	"lirien": ["Not what we asked for, dear.", "Stirred in a hurry.", "Correct. It lacks soul.", "Very fine. Almost elven.", "Exquisite. It shines like the moon."],
	"grumm": ["Grumm doesn't get this.", "Bland. Needs more kick.", "Drinkable.", "Tasty. Grumm wants more.", "Whoa! Now THAT has flavor!"],
}
## Los rivales del concurso (la media de estrellas por jurado: base + por nivel). Fizz es el rival de siempre: con un
## nivel 1 saca ~37 de 45 (para ganarle hay que presentar la poción del tema, bien removida, casi en cada ronda). Los otros dos son tiendas
## del Escalafón (RANK); si el escenario trae sus propios letreros (EventScenes.CON_RIVALS), se usan esos nombres.
const RIVALS := [
	{"id": "fizz", "name": "Fizz", "sprite": "fizz", "base": 3.85, "per_tier": 0.3},
	{"id": "raicesrocio", "name": "Roots & Dew", "sprite": "", "base": 2.9, "per_tier": 0.3},
	{"id": "vado", "name": "Fordside Herbs", "sprite": "", "base": 2.5, "per_tier": 0.3},
]
const FIZZ_LINES := {"high": ["Ha! Beat THAT!", "Gnome science, ladies!", "Take that!"],
	"low": ["Bah. The judges don't understand science.", "It was an experimental potion!", "My cauldron was in a bad mood."]}

## La feria del torneo: lo que piden los caballeros (y la poción que lo cura). Curación es Bálsamo Helado al principio
## y Elixir del Alba cuando ya hay plumas de fénix.
const TORNEO_WANTS := {
	"vigor": {"name": "Vigor", "potion": "vigor_verde"},
	"curacion": {"name": "Healing", "potion": "balsamo_helado", "potion_up": "elixir_alba"},
	"valor": {"name": "Courage", "potion": "tonico_brio"},
}
## La receta más simple de cada poción (el cartel del puesto en la feria, la pizarra de la Academia).
const SIMPLE_RECIPE := {
	"vigor_verde": ["raiz_mandragora", "ambar_abeja"], "balsamo_helado": ["raiz_mandragora", "lagrima_sirena"],
	"elixir_alba": ["pluma_fenix", "raiz_mandragora"], "tonico_brio": ["ambar_abeja", "ambar_abeja"],
	"sueno_profundo": ["raiz_mandragora", "raiz_mandragora"], "ojo_nocturno": ["hongo_violeta", "hongo_violeta"],
	"velo_invernal": ["escarcha_luna", "escarcha_luna"],
}
## Ingredientes raros (premio de las medallas: el mejor que ya puede usar) y páginas de runas que se pueden ganar.
const RARE := ["ceniza_dragon", "polvo_estrella", "escarcha_luna", "pluma_fenix"]
const PAGE_RUNES := ["calma", "duracion", "frescor", "dulzor"]

# ------------------------------------------------------------------ catálogo

static func info(kind: String) -> Dictionary:
	return CATALOG.get(kind, CATALOG["academia"])

static func ev_name(kind: String, long := false) -> String:
	return String(info(kind)["long" if long else "name"])

static func potion_name(pid: String) -> String:
	return String(Data.POTIONS.get(pid, {}).get("name", pid))

static func ing_name(id: String) -> String:
	return String(Data.INGREDIENTS.get(id, {}).get("name", id))

## Inscripción del evento (se paga al aceptar).
static func fee(kind: String, tier: int) -> int:
	var f: Array = info(kind)["fee"]
	return int(f[0]) + int(f[1]) * tier

## Dificultad en estrellas (1 a 3): sube con el nivel del evento; el concurso y la feria empiezan en 2.
static func difficulty(kind: String, tier: int) -> int:
	return clampi(1 + (1 if tier >= 2 else 0) + int(info(kind)["hard"]), 1, 3)

## Lo que trae cada medalla (tier: nivel del evento 0..3): oro, renombre (negativo: lo que cuesta no medallar),
## puntos del escalafón del Gremio y si trae un objeto.
static func reward(kind: String, medal: String, tier: int) -> Dictionary:
	var k: float = float(info(kind)["gold_k"])
	var t := float(tier)
	var pts := medal_points(medal)
	match medal:
		"gold":
			return {"gold": int(round((100.0 + 45.0 * t) * k)), "renombre": 10 + 3 * tier, "points": pts, "item": true}
		"silver":
			return {"gold": int(round((55.0 + 25.0 * t) * k)), "renombre": 6 + 2 * tier, "points": pts, "item": false}
		"bronze":
			return {"gold": int(round((25.0 + 12.0 * t) * k)), "renombre": 3 + tier, "points": pts, "item": false}
	return {"gold": 0, "renombre": -(4 + tier), "points": pts, "item": false}

## Puntos del Gremio de una medalla: los mismos que suma el Escalafón (RANK: Ranking.MEDAL_POINTS, con nombres en
## castellano). Si el autoload Ranking está, se leen de allí; si no, esta copia.
const MEDAL_POINTS := {"gold": 100, "silver": 65, "bronze": 35, "none": -10}   # --- R4 MERGE: = Ranking.MEDAL_POINTS (antes 150 / 95 / 50)
const _MEDAL_ES := {"gold": "oro", "silver": "plata", "bronze": "bronce", "none": "ninguna"}

static func medal_points(medal: String) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var rk: Node = tree.root.get_node_or_null("Ranking") if tree and tree.root else null
	if rk and rk.get_script():
		var mp = rk.get_script().get_script_constant_map().get("MEDAL_POINTS", null)
		if mp is Dictionary and mp.has(_MEDAL_ES.get(medal, "")):
			return int(mp[_MEDAL_ES[medal]])
	return int(MEDAL_POINTS.get(medal, 0))

## Los rivales del concurso con los nombres de los letreros del escenario, si los trae (EventScenes.CON_RIVALS: Fizz y
## dos puestos, en orden); si no, los de RIVALS.
static func rivals_for(scene: Node) -> Array:
	var out := []
	for r in RIVALS:
		out.append((r as Dictionary).duplicate())
	if scene == null or scene.get_script() == null:
		return out
	var cr = scene.get_script().get_script_constant_map().get("CON_RIVALS", null)
	if not cr is Dictionary:
		return out
	var i := 1
	for key in cr:
		if String(key) == "fizz" or i >= out.size():
			continue
		var nm := String(cr[key]).get_slice("·", 0).strip_edges()
		if nm != "":
			out[i]["name"] = nm
		i += 1
	return out

# ------------------------------------------------------------------ calendario

## Las clases de evento que pueden invitarla hoy (por su renombre y el día).
static func eligible() -> Array:
	var out := []
	for k in KINDS:
		var c: Dictionary = CATALOG[k]
		if Game.renombre >= int(c["min_renombre"]) and Game.day >= int(c["min_day"]):
			out.append(k)
	return out

## ¿Llega hoy una invitación nueva? Nunca con otra esperando respuesta o con un evento ya aceptado.
static func invite_due() -> bool:
	return Game.ev_invite.is_empty() and Game.ev_booked.is_empty() and Game.day >= Game.ev_next

## Prepara la invitación de hoy (la deja en Game.ev_invite) y programa la próxima. {} si nadie puede invitarla.
## force_kind: para las pruebas (--demo=event_invite).
static func make_invite(force_kind := "") -> Dictionary:
	var kinds := eligible()
	if force_kind != "":
		kinds = [force_kind]
	if kinds.is_empty():
		Game.ev_next = Game.day + 1
		return {}
	var pick: Array = kinds.duplicate()
	if pick.size() > 1 and pick.has(Game.ev_last_kind):
		pick.erase(Game.ev_last_kind)   # no la misma dos veces seguidas
	var fresh: Array = pick.filter(func(k): return not _done_kind(k))
	var kind: String = String((fresh if not fresh.is_empty() else pick).pick_random())
	var tier := clampi(Game.level(), 0, 3)
	var day := Game.day + LEAD
	if day >= Game.PACE_MARKET_EVERY and day % Game.PACE_MARKET_EVERY == 0:   # --- R4 MERGE: nunca el día de mercado de PACE
		day += 1
	var inv := {"id": "%s_%d" % [kind, day], "kind": kind, "day": day, "sent": Game.day, "tier": tier,
		"fee": fee(kind, tier), "difficulty": difficulty(kind, tier), "plan": plan(kind, tier)}
	Game.ev_invite = inv
	Game.ev_count += 1
	Game.ev_next = Game.day + (FIRST_GAP if Game.ev_count == 1 else randi_range(GAP_MIN, GAP_MAX))
	Game.ev_last_kind = kind
	return inv

static func _done_kind(kind: String) -> bool:
	for h in Game.ev_history:
		if String(h.get("kind", "")) == kind:
			return true
	return false

## Acepta la invitación: paga la inscripción y la reserva. false si no le alcanza el oro.
static func accept() -> bool:
	var inv: Dictionary = Game.ev_invite
	if inv.is_empty() or Game.gold < int(inv["fee"]):
		return false
	Game.add_gold(-int(inv["fee"]))
	Game.ev_booked = inv
	Game.ev_invite = {}
	Game.ev_answers.append({"id": String(inv["id"]), "kind": String(inv["kind"]), "accepted": true, "day": Game.day})
	return true

## Rechaza la invitación (sin castigo: «quizá la próxima vez»).
static func reject() -> void:
	var inv: Dictionary = Game.ev_invite
	if inv.is_empty():
		return
	Game.ev_answers.append({"id": String(inv["id"]), "kind": String(inv["kind"]), "accepted": false, "day": Game.day})
	Game.ev_invite = {}

## Hoy se juega el evento reservado.
static func today_is_event() -> bool:
	return not Game.ev_booked.is_empty() and int(Game.ev_booked.get("day", -1)) == Game.day

# ------------------------------------------------------------------ cada evento: su plan

## Lo concreto de cada evento (se decide al invitar; los temas del concurso y los pedidos de la feria, al empezar).
static func plan(kind: String, tier: int) -> Dictionary:
	match kind:
		"academia":
			var opts := []
			for r in ACADEMIA_RECIPES:
				if Game.ingredient_unlocked(String(r[1])):
					opts.append(r)
			if opts.is_empty():
				opts = [ACADEMIA_RECIPES[0]]
			var r: Array = opts.pick_random()
			var n := 8 + 2 * tier
			return {"potion": String(r[0]), "ing": String(r[1]), "n": n, "time": 10 + 6 * n}
		"concurso":
			return {"rounds": 3, "time": maxi(36, 46 - 3 * tier)}
		"torneo":
			return {"k": 12 + 2 * tier, "time": 100 + 10 * tier}
	return {}

## La despensa que pone el evento (el inventario de la tienda se guarda aparte: Game.events_stash).
static func pantry(ev: Dictionary) -> Dictionary:
	var kind := String(ev["kind"])
	var p: Dictionary = ev.get("plan", {})
	var tier := int(ev.get("tier", 0))
	var out := {}
	for id in Data.INGREDIENT_ORDER:
		out[id] = 0
	match kind:
		"academia":
			for id in Data.INGREDIENT_ORDER:
				if Game.ingredient_unlocked(id) and int(Data.INGREDIENTS[id]["level"]) == 0:
					out[id] = 3
			out[String(p.get("ing", "raiz_mandragora"))] = 2 * int(p.get("n", 6)) + 3
		"concurso":
			for id in Data.INGREDIENT_ORDER:
				if Game.ingredient_unlocked(id):
					out[id] = 4 if int(Data.INGREDIENTS[id]["level"]) == 0 else 3
		"torneo":
			var k := int(p.get("k", 10))
			out["raiz_mandragora"] = k + 4
			out["ambar_abeja"] = k + 6
			out["lagrima_sirena"] = k / 2 + 3
			out["hongo_violeta"] = 3
			if torneo_potion("curacion", tier) == "elixir_alba":
				out["pluma_fenix"] = k / 2 + 3
	return out

## La poción de cada pedido de la feria según el nivel.
static func torneo_potion(want: String, tier: int) -> String:
	var w: Dictionary = TORNEO_WANTS.get(want, TORNEO_WANTS["vigor"])
	if w.has("potion_up") and tier >= 1 and Game.ingredient_unlocked("pluma_fenix"):
		return String(w["potion_up"])
	return String(w["potion"])

## Tres temas distintos para el concurso: cada uno con al menos una poción que encaje del todo y que pueda preparar
## con la despensa (lo desbloqueado y el tamaño de su caldero).
static func pick_themes(n := 3) -> Array:
	var brewable := Game.brewable_potions()
	var ok := []
	for th in THEMES:
		for pid in th["fit"]:
			if int(th["fit"][pid]) == 2 and brewable.has(pid):
				ok.append(th)
				break
	ok.shuffle()
	if ok.size() < n:
		for th in THEMES:
			if ok.size() >= n:
				break
			if not ok.has(th):
				ok.append(th)
	return ok.slice(0, n)

## Lo bien que encaja una poción con un tema (0, 1 o 2).
static func fit(theme: Dictionary, pid: String) -> int:
	return int(theme.get("fit", {}).get(pid, 0))

# ------------------------------------------------------------------ medallas

## Academia: la suma de estrellas de las pociones entregadas (+1 por cada 10 s que sobren si terminó). Máximo 3 x N.
const ACADEMIA_CUTS := {"gold": 0.9, "silver": 0.66, "bronze": 0.42}
## Feria: por caballero atendido, sus estrellas + 1 si le sobraba más del 60 % de su paciencia. Máximo 4 x K.
const TORNEO_CUTS := {"gold": 0.7, "silver": 0.45, "bronze": 0.3}

## Los puntos que hacen falta para cada medalla (para la barra del HUD y el resultado).
static func cuts(kind: String, ev_plan: Dictionary) -> Dictionary:
	match kind:
		"academia":
			var mx := 3 * int(ev_plan.get("n", 6))
			return {"max": mx, "gold": int(ceil(mx * ACADEMIA_CUTS["gold"])), "silver": int(ceil(mx * ACADEMIA_CUTS["silver"])),
				"bronze": int(ceil(mx * ACADEMIA_CUTS["bronze"]))}
		"torneo":
			var mx2 := 4 * int(ev_plan.get("k", 10))
			return {"max": mx2, "gold": int(ceil(mx2 * TORNEO_CUTS["gold"])), "silver": int(ceil(mx2 * TORNEO_CUTS["silver"])),
				"bronze": int(ceil(mx2 * TORNEO_CUTS["bronze"]))}
	return {"max": 45, "gold": 0, "silver": 0, "bronze": 0}

static func medal_for(score: int, c: Dictionary) -> String:
	for m in ["gold", "silver", "bronze"]:
		if score >= int(c[m]):
			return m
	return "none"

## Concurso: el puesto (1..4) da la medalla.
static func medal_for_place(place: int) -> String:
	return ["gold", "silver", "bronze"][place - 1] if place >= 1 and place <= 3 else "none"

## Lo que da un jurado (1 a 5 estrellas) a la poción presentada para un tema. p: {"id", "potency", "perfect"}.
## Sin poción: 0. Si no encaja con el tema, como mucho 2.
static func judge(judge_id: String, theme: Dictionary, p: Dictionary) -> int:
	if p.is_empty():
		return 0
	var f := fit(theme, String(p.get("id", "")))
	var stars := Game.stars_for(int(p.get("potency", 4)))
	var perfect := bool(p.get("perfect", false))
	var s := 1.0 + float(f) + (stars - 1) * 0.8 + (0.5 if perfect else 0.0)
	match judge_id:
		"elda":
			s += 0.4 if f == 2 else -0.4
		"lirien":
			s += 0.5 if perfect else -0.3
		"grumm":
			s += 0.35 * (stars - 2)
	s += randf_range(-0.45, 0.45)
	var out := clampi(int(round(s)), 1, 5)
	return mini(out, 2) if f == 0 else out

## Las estrellas de un rival en una ronda (tres jurados).
static func rival_round(r: Dictionary, tier: int) -> Array:
	var m: float = float(r["base"]) + float(r["per_tier"]) * tier
	var out := []
	for j in 3:
		out.append(clampi(int(round(m + randf_range(-1.0, 1.0))), 1, 5))
	return out

# ------------------------------------------------------------------ resultados

## El premio en objeto: una página de runa que aún no tiene (sobre todo en la Academia) o dos del mejor ingrediente
## raro que ya puede usar (si no hay, tres de ámbar).
static func pick_item(kind: String, medal: String) -> Dictionary:
	if medal == "gold" and (kind == "academia" or randf() < 0.35):
		for r in PAGE_RUNES:
			if not Game.rune_pages.has(r) and not Game.rune_known(r):
				return {"page": r}
	var qty := 2 if medal == "gold" else 1
	for id in RARE:
		if Game.ingredient_unlocked(id):
			return {"id": id, "qty": qty}
	return {"id": "ambar_abeja", "qty": qty + 1}

## Aplica el resultado del evento (con el inventario de la tienda ya devuelto): oro, renombre, objeto, trofeo,
## historial, y escribe Game.today["event"] (contrato: {"id", "kind", "medal", "points"} + "name", "tier", "place").
## res: {"medal", "score", "place", "tips", ...} (EventGame). Devuelve lo que dio, para la tarjeta de resultados.
static func apply_result(ev: Dictionary, res: Dictionary) -> Dictionary:
	var kind := String(ev.get("kind", "academia"))
	var tier := int(ev.get("tier", 0))
	var medal := String(res.get("medal", "none"))
	var rw := reward(kind, medal, tier)
	var out := {"gold": 0, "renombre": 0, "points": int(rw["points"]), "items": [], "page": "", "trophy": medal != "none",
		"tips": int(res.get("tips", 0)), "fee": int(ev.get("fee", 0))}
	if int(rw["gold"]) > 0:
		Game.add_gold(int(rw["gold"]))
		out["gold"] = int(rw["gold"])
	if int(rw["renombre"]) > 0:
		Game.add_renombre(int(rw["renombre"]))
		out["renombre"] = int(rw["renombre"])
	elif int(rw["renombre"]) < 0:
		out["renombre"] = -Game.lose_renombre(-int(rw["renombre"]))
	if bool(rw["item"]) or (medal == "silver" and randf() < 0.4):
		var it := pick_item(kind, medal)
		if it.has("page"):
			Game.rune_pages[String(it["page"])] = "new"
			Game.magic_changed.emit()
			out["page"] = String(it["page"])
		else:
			var id := String(it["id"])
			Game.stock[id] = int(Game.stock.get(id, 0)) + int(it["qty"])
			Game.stock_changed.emit()
			out["items"].append({"id": id, "qty": int(it["qty"])})
	if medal != "none":
		Game.ev_trophies.append({"kind": kind, "medal": medal, "day": Game.day, "tier": tier})
	var entry := {"id": String(ev.get("id", "%s_%d" % [kind, Game.day])), "kind": kind, "day": Game.day, "medal": medal,
		"points": int(out["points"]), "tier": tier, "place": int(res.get("place", 0)), "score": int(res.get("score", 0))}
	Game.ev_history.append(entry)
	Game.ev_booked = {}
	Game.ev_done_day = Game.day
	today_entry(entry)
	return out

## Escribe el evento del día en Game.today (también al recargar la noche de un evento).
static func today_entry(h: Dictionary) -> void:
	Game.today["event"] = {"id": String(h.get("id", "")), "kind": String(h.get("kind", "")), "medal": String(h.get("medal", "none")),
		"points": int(h.get("points", 0)), "name": ev_name(String(h.get("kind", "academia")), true), "tier": int(h.get("tier", 0)),
		"place": int(h.get("place", 0))}

## Medallas ganadas (para el diario o el escalafón): {"gold": n, "silver": n, "bronze": n}.
static func medal_counts() -> Dictionary:
	var out := {"gold": 0, "silver": 0, "bronze": 0, "none": 0}
	for h in Game.ev_history:
		var m := String(h.get("medal", "none"))
		out[m] = int(out.get(m, 0)) + 1
	return out

# ------------------------------------------------------------------ textos

## Una frase del catálogo con sus huecos ({n} pociones, {p} la poción...).
static func line(kind: String, key: String, ev: Dictionary = {}) -> String:
	var t := String(info(kind).get(key, ""))
	var p: Dictionary = ev.get("plan", {})
	return t.replace("{n}", str(int(p.get("n", 6)))).replace("{p}", potion_name(String(p.get("potion", ""))))

## «Día 4 · pasado mañana».
static func when_text(day: int) -> String:
	var d := day - Game.day
	var rel := "today" if d <= 0 else ("tomorrow" if d == 1 else ("in 2 days" if d == 2 else "in %d days" % d))
	return "Day %d · %s" % [day, rel]

static func stars_text(n: int, of := 3) -> String:
	return "★".repeat(clampi(n, 0, of)) + "☆".repeat(maxi(0, of - n))
