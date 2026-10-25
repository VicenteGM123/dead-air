extends Node
## --- R4 RANK: el Escalafón del Gremio de Boticarios de Arvendal (autoload «Ranking»).
## Treinta tiendas de pociones de Arvendal, cada una con su dueño, su pueblo y sus puntos del Gremio. Los puntos se
## SUMAN cada día: la tienda de la alquimista («Caldero Nocturno») empieza última, con 0, y suma lo que hizo en su día
## (day_points: ventas, estrellas, renombre, pedidos de Krápido, medallas de los eventos); las rivales suman su ritmo de
## siempre, que sube o baja poco a poco (unas crecen, otras decaen), y a veces ganan una medalla o tienen un tropiezo
## (son las noticias de la Gaceta). Fizz y Chispa, el gnomo rival, se muda a su pueblo el día 5 y desde entonces la
## persigue: cuanto mejor le va a ella, más se esfuerza él.
##
## Una vez por día (commit_day, al cerrar la tienda o al dormir) se suma el día y se ordena la tabla; a la mañana
## siguiente el correo trae la línea del Escalafón (puesto, flecha, a quién pasó) y cada 5 días la Gaceta del Gremio.
## Al llegar al puesto 1 se juega el final (ending_due / mark_ending_seen) una sola vez; el Escalafón sigue después.
## --- R4 MERGE (balance con PACE + RAVEN + EVENTS): ventas 7·√(vendidas+entregas), calidad 8·estrellas, renombre 4·√(ganado),
## fama 0.10·min(renombre, 200), Krápido 3·(plumas−3) − 2·perdidos, medallas 100 / 65 / 35 / −10, − cansados. Antes (solo
## RANK): 9 / 8 / 5 / 0.15 y 150 / 95 / 50 / −10: con los días de PACE el bot llegaba al puesto 1 el día 18.
## Los datos del día se leen de Game.today con .get(): "sold", "deliveries", "deliveries_lost", "plumas", "lost_tired",
## "event" = {"medal"} (las otras pistas los añaden; sin ellos vale 0). El renombre ganado se mide como la diferencia de
## Game.renombre entre dos actualizaciones, y las estrellas del día, en las noticias pendientes de hoy (Game.pending).

const ME := "caldero"
const SAVE_V := 1
const GACETA_EVERY := 5        # la Gaceta del Gremio llega los días 5, 10, 15...
const FIZZ_ARRIVES := 5        # el día que Fizz abre su laboratorio en Valdelago (Data.CHARACTERS["fizz"]["arrives"])
const FIZZ_CHASE := 0.90       # desde ese día suma al menos esta parte del día de ella
const FIZZ_DEBUT := 35.0       # la inauguración de su laboratorio
## Puntos de una medalla de evento (Game.today["event"]["medal"]); "oro"/"gold", "plata"/"silver", "bronce"/"bronze".
const MEDAL_POINTS := {"oro": 100, "plata": 65, "bronce": 35, "ninguna": -10}   # --- R4 MERGE: antes 150 / 95 / 50 / -10 (ver day_points)
const MEDAL_NAMES := {"oro": "Gold", "plata": "Silver", "bronce": "Bronze"}   # --- R5 EN-UI: lo que se lee («Gold Medal for ...»); las claves son ids

## Pueblos de Arvendal que aparecen en el Escalafón (una línea cada uno).
const TOWNS := {
	"valdelago": {"name": "Lakevale", "lore": "Your town, at the foot of the Grey Mountain, by the lake."},
	"valmora": {"name": "Valmora", "lore": "The capital, all white towers. The Guild's hall is there."},
	"brisaclara": {"name": "Clearbreeze", "lore": "The port. Ships from every sea and the smell of salt."},
	"robledal": {"name": "Oakdale", "lore": "Oaks and wheat fields, twelve miles away. Home of the Potion Contest."},
	"alvenmoor": {"name": "Alvenmoor", "lore": "Misty moors beside old elven ruins."},
	"montana": {"name": "the Grey Mountain", "lore": "Dwarven halls under the snow; forges that never go out."},
	"hojaplata": {"name": "Silverleaf", "lore": "The elves' forest. Silver leaves and lots of quiet."},
	"rosalba": {"name": "Rosalba", "lore": "A city of gardens, noble ladies and perfumers."},
	"vadoviejo": {"name": "Oldford", "lore": "A stopover town by the river ford."},
	"molinos": {"name": "Millbrook", "lore": "Flour, wind and a slow river."},
	"cuatrocaminos": {"name": "Fourways", "lore": "An inn where the kingdom's roads meet."},
}

## Las tiendas, ordenadas por sus puntos al empezar. score: puntos al empezar; pace: lo que suma un día normal;
## trend: cuánto cambia ese ritmo cada día (+ crece, - decae); wobble: lo que varía de un día a otro; luck: probabilidad
## diaria de ganar una medalla en una feria; risk: de tener un tropiezo. Escudos: assets/ui/rank_crest_<id>.png.
const SHOPS := [
	{"id": "alambique", "name": "The Golden Still", "owner": "Master Agata Velnor", "note": "your teacher's old rival",
		"town": "valmora", "score": 1040, "pace": 50.0, "trend": 0.0, "wobble": 0.06, "luck": 0.010, "risk": 0.0},
	{"id": "academia", "name": "The Academy Lab", "owner": "Archmage Teodric", "note": "tests the apprentices",
		"town": "valmora", "score": 975, "pace": 49.0, "trend": 0.10, "wobble": 0.07, "luck": 0.012, "risk": 0.0},
	{"id": "monasterio", "name": "The Monastery Apothecary", "owner": "Brother Celestino", "note": "Sister Elda's friend",
		"town": "robledal", "score": 925, "pace": 47.0, "trend": -0.12, "wobble": 0.06, "luck": 0.008, "risk": 0.0},
	{"id": "rosalba", "name": "Rosalba Perfumery", "owner": "Madame Odalys", "note": "Lady Vianne's perfumer",
		"town": "rosalba", "score": 875, "pace": 46.0, "trend": 0.0, "wobble": 0.16, "luck": 0.012, "risk": 0.004},
	{"id": "milfrascos", "name": "The Thousand Flasks Bazaar", "owner": "Karim", "note": "Hassim's brother",
		"town": "brisaclara", "score": 815, "pace": 43.0, "trend": 0.30, "wobble": 0.10, "luck": 0.010, "risk": 0.002},
	{"id": "martillo", "name": "Forge & Flask", "owner": "Dorna", "note": "Borin's cousin",
		"town": "montana", "score": 780, "pace": 44.0, "trend": 0.0, "wobble": 0.07, "luck": 0.010, "risk": 0.0},
	{"id": "sauce", "name": "The Silver Willow", "owner": "Aelin", "note": "Ilse's sister",
		"town": "hojaplata", "score": 650, "pace": 41.0, "trend": 0.22, "wobble": 0.09, "luck": 0.012, "risk": 0.0},
	{"id": "redoma", "name": "The Blue Vial", "owner": "Master Corvino", "note": "",
		"town": "valmora", "score": 610, "pace": 40.0, "trend": -0.25, "wobble": 0.08, "luck": 0.006, "risk": 0.004},
	{"id": "puerto", "name": "Harbor Salves", "owner": "Widow Marela", "note": "",
		"town": "brisaclara", "score": 560, "pace": 37.0, "trend": 0.05, "wobble": 0.09, "luck": 0.008, "risk": 0.002},
	{"id": "lechuza", "name": "The Wise Owl", "owner": "The Brun Sisters", "note": "",
		"town": "alvenmoor", "score": 525, "pace": 36.0, "trend": 0.0, "wobble": 0.10, "luck": 0.008, "risk": 0.002},
	{"id": "piedrahierro", "name": "Ironstone Tonics", "owner": "Thrain Ironstone", "note": "",
		"town": "montana", "score": 480, "pace": 34.0, "trend": 0.18, "wobble": 0.09, "luck": 0.008, "risk": 0.002},
	{"id": "caminoreal", "name": "King's Road Elixirs", "owner": "Jacobo Nightingale", "note": "",
		"town": "cuatrocaminos", "score": 375, "pace": 32.0, "trend": 0.0, "wobble": 0.10, "luck": 0.006, "risk": 0.003},
	{"id": "mandragora", "name": "The Happy Mandrake", "owner": "Aunt Petronila", "note": "",
		"town": "molinos", "score": 340, "pace": 30.0, "trend": -0.20, "wobble": 0.10, "luck": 0.004, "risk": 0.004},
	{"id": "paramo", "name": "Moorland Distillery", "owner": "Ulric Greymist", "note": "",
		"town": "alvenmoor", "score": 305, "pace": 29.0, "trend": 0.05, "wobble": 0.12, "luck": 0.006, "risk": 0.004},
	{"id": "plazamayor", "name": "Main Square Apothecary", "owner": "Mrs. Ines Valcarcel", "note": "",
		"town": "valmora", "score": 275, "pace": 28.0, "trend": 0.0, "wobble": 0.10, "luck": 0.006, "risk": 0.003},
	{"id": "gruka", "name": "Gruka's Brews", "owner": "Gruka", "note": "Grumm's cousin",
		"town": "brisaclara", "score": 205, "pace": 24.0, "trend": 0.30, "wobble": 0.14, "luck": 0.006, "risk": 0.006},
	{"id": "tiobolo", "name": "Uncle Bolo's Remedies", "owner": "Uncle Bolo", "note": "Kit's uncle",
		"town": "alvenmoor", "score": 185, "pace": 25.0, "trend": -0.18, "wobble": 0.25, "luck": 0.004, "risk": 0.030},
	{"id": "fizz", "name": "Fizz & Spark", "owner": "Fizz Sparklespin", "note": "and Spark, his salamander",
		"town": "robledal", "score": 160, "pace": 16.0, "trend": 0.25, "wobble": 0.20, "luck": 0.0, "risk": 0.0, "rival": true},
	{"id": "raicesrocio", "name": "Roots & Dew", "owner": "Friar Tadeo", "note": "",
		"town": "robledal", "score": 145, "pace": 22.0, "trend": 0.05, "wobble": 0.10, "luck": 0.004, "risk": 0.003},
	{"id": "cantor", "name": "The Singing Cauldron", "owner": "Minstrel Amadeo", "note": "sings to his potions",
		"town": "vadoviejo", "score": 125, "pace": 21.0, "trend": 0.0, "wobble": 0.22, "luck": 0.006, "risk": 0.006},
	{"id": "retorta", "name": "The Copper Retort", "owner": "Master Lisandro", "note": "",
		"town": "rosalba", "score": 105, "pace": 19.0, "trend": 0.10, "wobble": 0.10, "luck": 0.004, "risk": 0.003},
	{"id": "vado", "name": "Fordside Herbs", "owner": "Granny Remedy", "note": "",
		"town": "vadoviejo", "score": 88, "pace": 18.0, "trend": -0.15, "wobble": 0.10, "luck": 0.002, "risk": 0.003},
	{"id": "encina", "name": "Little Oak Potions", "owner": "Mateo Oakes", "note": "",
		"town": "molinos", "score": 55, "pace": 13.0, "trend": 0.0, "wobble": 0.12, "luck": 0.002, "risk": 0.003},
	{"id": "molino", "name": "Millhouse Syrups", "owner": "Rosa Miller", "note": "",
		"town": "molinos", "score": 42, "pace": 12.0, "trend": 0.0, "wobble": 0.12, "luck": 0.002, "risk": 0.003},
	{"id": "torcido", "name": "The Crooked Flask", "owner": "One-Eyed Hugo", "note": "",
		"town": "cuatrocaminos", "score": 30, "pace": 11.0, "trend": -0.05, "wobble": 0.18, "luck": 0.002, "risk": 0.010},
	{"id": "lunaticos", "name": "Moonstruck Salves", "owner": "Selene & Selma", "note": "",
		"town": "alvenmoor", "score": 20, "pace": 10.0, "trend": 0.0, "wobble": 0.20, "luck": 0.002, "risk": 0.005},
	{"id": "ortiz", "name": "Ortiz Buttons & Brews", "owner": "Mr. Fermin Ortiz", "note": "sells buttons and brews",
		"town": "vadoviejo", "score": 12, "pace": 8.0, "trend": 0.0, "wobble": 0.12, "luck": 0.0, "risk": 0.003},
	{"id": "gotadorada", "name": "The Golden Drop", "owner": "Clarisa Honey", "note": "",
		"town": "robledal", "score": 7, "pace": 7.0, "trend": 0.05, "wobble": 0.12, "luck": 0.002, "risk": 0.002},
	{"id": "remiendos", "name": "Patches & Potions", "owner": "Benigno the Tailor", "note": "",
		"town": "valdelago", "score": 3, "pace": 4.0, "trend": 0.0, "wobble": 0.20, "luck": 0.0, "risk": 0.002},
	{"id": "caldero", "name": "Midnight Cauldron", "owner": "You & Miga", "note": "", "town": "valdelago", "score": 0,
		"pace": 0.0, "me": true},
]

## Dónde ganan medallas las rivales (las noticias de la Gaceta).
const FAIRS := ["the Clearbreeze Fair", "the Oakdale Contest", "the Tournament Fair", "the Silverleaf Market",
	"the Solstice Fair in Valmora"]
## --- R5 EN-UI: las partidas de las rondas 3 y 4 guardaron en rank.news[].where estas frases en castellano (FAIRS y
## _event_where): al cargar se cambian por las de ahora. Son claves de migración, no texto que se vea.
const OLD_WHERE := {
	"la Feria de Brisaclara": "the Clearbreeze Fair", "el Concurso de Robledal": "the Oakdale Contest",
	"la Feria del Torneo": "the Tournament Fair", "el Mercado de Hojaplata": "the Silverleaf Market",
	"la Feria del Solsticio en Valmora": "the Solstice Fair in Valmora", "el Examen de la Academia": "the Academy Exam",
	"un evento del Gremio": "a Guild event", "un evento": "an event",
}
## Tropiezos ({s}: la tienda, {o}: su dueño, {t}: su pueblo). Algunas tiendas tienen el suyo (SCANDALS_BY).
const SCANDALS := ["{s}: a cauldron burst and a week of work was lost.",
	"Customers with hiccups in {t}: {s} says sorry.",
	"{s} closed for a few days: mice everywhere.",
	"Mix-up in {t}: {s} swapped two labels."]
const SCANDALS_BY := {
	"tiobolo": ["Uncle Bolo sold maple syrup as “elixir of youth.”", "Uncle Bolo, caught selling bottled puddle water."],
	"cantor": ["Minstrel Amadeo lost his voice: no song, no potions."],
	"torcido": ["The Crooked Flask sold flasks… crooked ones. And empty."],
	"rosalba": ["A Madame Odalys perfume left a countess smelling of cabbage."],
	"redoma": ["The Blue Vial loses its best apprentice."],
}

# ------------------------------------------------------------------ estado

var seed0 := 0
var scores := {}          # id -> puntos del Gremio (float)
var pace := {}            # id -> ritmo de hoy (las rivales; deriva)
var prev_pos := {}        # id -> puesto antes de la última actualización (las flechas del tablón)
var snaps: Array = []     # últimas tablas: [{"day", "pos": {id: puesto}}] (la Gaceta mira 5 días atrás)
var hist: Array = []      # ella, día a día: [{"day", "pos", "pts", "score"}]
var news: Array = []      # noticias: [{"day", "id", "kind", ...}]
var last_day := 0         # último día sumado
var ren_base := 0         # Game.renombre en la última actualización (el renombre ganado se mide desde ahí)
var last_move := {}       # la última actualización: {"day", "pos", "prev", "delta", "points", "parts", "passed", "passed_by"}
var news_day := 0         # la mañana en que el correo trae last_move
var gaceta_seen := 0      # último día en que se leyó la Gaceta
var ending_seen := false  # el final del puesto 1 ya se jugó
var _ready_state := false

func _ready() -> void:
	if not _ready_state:
		reset()

## Partida nueva: la tabla de siempre, ella última con 0 puntos.
func reset() -> void:
	seed0 = randi() % 1000000
	scores = {}
	pace = {}
	for s in SHOPS:
		scores[s["id"]] = float(s["score"])
		pace[s["id"]] = float(s["pace"])
	_ready_state = true
	snaps = []
	hist = []
	news = []
	last_day = 0
	ren_base = 0
	last_move = {}
	news_day = 0
	gaceta_seen = 0
	ending_seen = false
	prev_pos = positions()

# ------------------------------------------------------------------ consultas

func shop(id: String) -> Dictionary:
	for s in SHOPS:
		if s["id"] == id:
			return s
	return {}

## El pueblo de una tienda (Fizz se muda a Valdelago el día que llega).
func town_of(id: String) -> String:
	if id == "fizz" and _today() >= FIZZ_ARRIVES:
		return "valdelago"
	return String(shop(id).get("town", ""))

func town_name(town: String) -> String:
	return String(TOWNS.get(town, {}).get("name", town.capitalize()))

func town_lore(town: String) -> String:
	return String(TOWNS.get(town, {}).get("lore", ""))

func shop_name(id: String) -> String:
	return String(shop(id).get("name", id))

## Los ids ordenados por puntos (empates: el orden de SHOPS; ella, al final de su empate).
func order() -> Array:
	_ensure()
	var ids: Array = []
	for s in SHOPS:
		ids.append(s["id"])
	var idx := {}
	for i in ids.size():
		idx[ids[i]] = i
	ids.sort_custom(func(a, b):
		var sa := float(scores.get(a, 0.0))
		var sb := float(scores.get(b, 0.0))
		if absf(sa - sb) > 0.001:
			return sa > sb
		return int(idx[a]) < int(idx[b]))
	return ids

## id -> puesto (1 = el mejor).
func positions() -> Dictionary:
	var out := {}
	var o := order()
	for i in o.size():
		out[o[i]] = i + 1
	return out

func position(id := ME) -> int:
	return int(positions().get(id, SHOPS.size()))

func score(id := ME) -> int:
	_ensure()
	return int(round(float(scores.get(id, 0.0))))

func size() -> int:
	return SHOPS.size()

## La tabla para el tablón y la Gaceta: una fila por tienda, del puesto 1 al 30.
## {"id", "name", "owner", "note", "town", "town_name", "score", "pos", "delta" (+ subió, - bajó), "me", "rival"}
func table() -> Array:
	var out: Array = []
	var o := order()
	for i in o.size():
		out.append(row(o[i], i + 1))
	return out

func row(id: String, pos := -1) -> Dictionary:
	var s := shop(id)
	if pos < 0:
		pos = position(id)
	var t := town_of(id)
	return {"id": id, "name": String(s.get("name", id)), "owner": String(s.get("owner", "")), "note": String(s.get("note", "")),
		"town": t, "town_name": town_name(t), "score": score(id), "pos": pos,
		"delta": int(prev_pos.get(id, pos)) - pos, "me": id == ME, "rival": bool(s.get("rival", false))}

# ------------------------------------------------------------------ el día de ella

## Los puntos del Gremio que suma su día (ver el comentario de arriba). t: Game.today (o un diccionario de prueba).
## "stars_avg" (opcional): las estrellas medias del día, si otra pista ya las lleva (si no, salen de Game.pending).
## Devuelve {"total", "parts": {"ventas", "calidad", "renombre", "fama", "krapido", "medalla", "perdidos"}, "medal"}.
func day_points(t: Dictionary = {}) -> Dictionary:
	if t.is_empty():
		t = Game.today
	var sold := maxi(0, int(t.get("sold", 0)))
	var deliveries := maxi(0, int(t.get("deliveries", 0)))
	var lost := maxi(0, int(t.get("deliveries_lost", 0)))
	var plumas := float(t.get("plumas", 0.0))
	var tired := maxi(0, int(t.get("lost_tired", 0)))
	var dren := Game.renombre - ren_base
	var medal := medal_of(t.get("event", {}))
	var parts := {
		"ventas": 7.0 * sqrt(float(sold + deliveries)),   # --- R4 MERGE: 9 -> 7 (con PACE vende 12-18 al día, no 4-6)
		"calidad": 8.0 * (clampf(float(t["stars_avg"]), 0.0, 3.0) if t.has("stars_avg") else quality_today()),
		"renombre": 4.0 * sqrt(float(dren)) if dren > 0 else 2.0 * float(dren),   # --- R4 MERGE: 5 -> 4
		"fama": 0.10 * float(mini(Game.renombre, 200)),   # --- R4 MERGE: 0.15 -> 0.10 (con PACE el renombre llega a 200 hacia el día 9)
		"krapido": (3.0 * (plumas - 3.0) if deliveries > 0 and plumas > 0.0 else 0.0) - 2.0 * float(lost),
		"medalla": float(MEDAL_POINTS.get(medal, 0)) if medal != "" else 0.0,
		"perdidos": -float(tired),
	}
	var total := 0.0
	for k in parts:
		parts[k] = roundf(float(parts[k]))
		total += float(parts[k])
	return {"total": maxi(0, int(total)), "parts": parts, "medal": medal}

## Estrellas medias de lo que vendió hoy (una poción equivocada cuenta 0): las noticias pendientes de hoy.
func quality_today() -> float:
	var n := 0
	var sum := 0.0
	for o in Game.pending:
		if o is Dictionary and int(o.get("day", -1)) == Game.day and String(o.get("item_kind", "potion")) == "potion":
			n += 1
			if bool(o.get("ok", false)):
				sum += clampf(float(o.get("stars", 1)), 0.0, 3.0)
	return sum / float(n) if n > 0 else 0.0

## La medalla de un evento: "oro", "plata", "bronce", "ninguna" o "" (no hubo evento). Acepta "gold"/"silver"/"bronze".
func medal_of(ev) -> String:
	if not (ev is Dictionary) or ev.is_empty():
		return ""
	var raw = ev.get("medal", "")
	var m := "" if raw == null else str(raw).to_lower().strip_edges()
	match m:
		"oro", "gold":
			return "oro"
		"plata", "silver":
			return "plata"
		"bronce", "bronze":
			return "bronce"
	return "ninguna"

# ------------------------------------------------------------------ la actualización del día

## Suma el día (una sola vez por día: se puede llamar al cerrar y otra vez al dormir). Devuelve last_move.
func commit_day() -> Dictionary:
	_ensure()
	var day := _today()
	if day <= last_day:
		return last_move
	var before := positions()
	var mine := day_points()
	var her := float(mine["total"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed0, day])
	_advance_rivals(day, her, rng)
	scores[ME] = float(scores.get(ME, 0.0)) + her
	var after := positions()
	var p0 := int(before.get(ME, size()))
	var p1 := int(after.get(ME, size()))
	var passed: Array = []
	var passed_by: Array = []
	for id in after:
		if id == ME:
			continue
		if int(before[id]) < p0 and int(after[id]) > p1:
			passed.append(id)
		elif int(before[id]) > p0 and int(after[id]) < p1:
			passed_by.append(id)
	passed.sort_custom(func(a, b): return int(after[a]) < int(after[b]))
	passed_by.sort_custom(func(a, b): return int(after[a]) < int(after[b]))
	if MEDAL_NAMES.has(mine["medal"]):
		news.append({"day": day, "id": ME, "kind": "medal", "medal": mine["medal"], "where": _event_where()})
	if p1 == 1 and p0 > 1:
		news.append({"day": day, "id": ME, "kind": "first"})
	prev_pos = before
	snaps.append({"day": day, "pos": after})
	while snaps.size() > 8:
		snaps.pop_front()
	hist.append({"day": day, "pos": p1, "pts": int(mine["total"]), "score": score(ME)})
	while hist.size() > 400:
		hist.pop_front()
	while news.size() > 60:
		news.pop_front()
	last_move = {"day": day, "pos": p1, "prev": p0, "delta": p0 - p1, "points": int(mine["total"]), "parts": mine["parts"],
		"medal": mine["medal"], "passed": passed, "passed_by": passed_by, "score": score(ME)}
	last_day = day
	news_day = day + 1
	ren_base = Game.renombre
	# para el resumen de la noche (la hoja de cuentas de PACE puede leerlo con Game.today.get("rank", {}))
	Game.today["rank"] = last_move.duplicate()
	return last_move

## Un día de las rivales: su ritmo deriva, suman su día y a veces ganan una medalla o tropiezan. Fizz, desde que llega
## a Valdelago, suma al menos FIZZ_CHASE del día de ella.
func _advance_rivals(day: int, her: float, rng: RandomNumberGenerator) -> void:
	for s in SHOPS:
		var id: String = s["id"]
		if id == ME:
			continue
		var b0 := float(s["pace"])
		pace[id] = clampf(float(pace.get(id, b0)) + float(s.get("trend", 0.0)) + rng.randfn(0.0, 0.15), b0 * 0.4, b0 * 1.8)
		var d := float(pace[id]) * (1.0 + rng.randfn(0.0, float(s.get("wobble", 0.1))))
		var roll := rng.randf()
		var pick := rng.randi()
		if roll < float(s.get("luck", 0.0)):
			var m: String = ["oro", "plata", "bronce"][pick % 3]
			d += [80.0, 50.0, 27.0][pick % 3]   # --- R4 MERGE: antes 120 / 75 / 40 (la misma proporción que las medallas de ella)
			news.append({"day": day, "id": id, "kind": "medal", "medal": m, "where": FAIRS[(pick / 3) % FAIRS.size()]})
		elif roll > 1.0 - float(s.get("risk", 0.0)):
			d -= 40.0 + float(pick % 31)
			news.append({"day": day, "id": id, "kind": "scandal", "n": pick % 97})
		if id == "fizz" and day == FIZZ_ARRIVES - 1:
			# la noche antes de abrir en Valdelago: la inauguración (la Gaceta del día 5 lo cuenta)
			d += FIZZ_DEBUT
			news.append({"day": day, "id": id, "kind": "move"})
		elif id == "fizz" and day >= FIZZ_ARRIVES:
			var chase := FIZZ_CHASE * her * (1.0 + rng.randfn(0.0, 0.06))
			d = maxf(d, chase)
			if rng.randf() < 0.05:
				d = 0.0
				news.append({"day": day, "id": id, "kind": "boom"})
		scores[id] = float(scores.get(id, 0.0)) + maxf(-60.0, d)

## Dónde fue el evento de hoy (si EVENTS dejó su "kind": academia / concurso / torneo).
func _event_where() -> String:
	var ev = Game.today.get("event", {})
	var kind := String(ev.get("kind", "")) if ev is Dictionary else ""
	match kind:
		"academia":
			return "the Academy Exam"
		"concurso":
			return "the Oakdale Contest"
		"torneo":
			return "the Tournament Fair"
	return "a Guild event"

# ------------------------------------------------------------------ el correo de la mañana

## Hay línea del Escalafón en el correo de hoy (después de cada día jugado).
func has_morning_news() -> bool:
	return news_day == _today() and not last_move.is_empty()

## La línea de la mañana: {"pos", "prev", "delta", "points", "passed": [nombres], "passed_by": [nombres], "size"}.
func morning_line() -> Dictionary:
	if last_move.is_empty():
		return {}
	var m := last_move.duplicate()
	m["passed"] = last_move.get("passed", []).map(func(id): return shop_name(String(id)))
	m["passed_by"] = last_move.get("passed_by", []).map(func(id): return shop_name(String(id)))
	m["size"] = size()
	return m

# ------------------------------------------------------------------ la Gaceta del Gremio

## Toca la Gaceta esta mañana (cada GACETA_EVERY días, si ya hubo días jugados y no se leyó hoy).
func gaceta_due() -> bool:
	var d := _today()
	return d >= GACETA_EVERY and d % GACETA_EVERY == 0 and gaceta_seen < d and last_day > 0

func mark_gaceta_read() -> void:
	gaceta_seen = _today()

## La página de la Gaceta: {"edition", "day", "top": [10 filas], "me": fila, "headlines": [{"title", "text", "who", "crest"}]}
func gaceta() -> Dictionary:
	var t := table()
	var me := row(ME)
	var d := _today()
	var top: Array = t.slice(0, 10)
	for r in top:
		r["delta"] = delta_since(String(r["id"]), GACETA_EVERY)
	me["delta"] = delta_since(ME, GACETA_EVERY)
	var g := {"edition": maxi(1, d / GACETA_EVERY), "day": d, "top": top, "me": me, "headlines": headlines(2)}
	return g

## Cuántos puestos subió (+) o bajó (-) una tienda en los últimos `days` días (las tablas guardadas en snaps).
func delta_since(id: String, days: int) -> int:
	if snaps.is_empty():
		return 0
	var now: Dictionary = snaps[-1]["pos"]
	var then: Dictionary = {}
	for sn in snaps:
		if int(sn["day"]) <= int(snaps[-1]["day"]) - days:
			then = sn["pos"]
	if then.is_empty():
		then = prev_pos if snaps.size() <= 1 else snaps[0]["pos"]
	return int(then.get(id, now.get(id, 0))) - int(now.get(id, 0))

## Titulares de los últimos días: uno sobre ella (si hay algo que contar) y otro sobre las rivales.
func headlines(n := 2) -> Array:
	var d := _today()
	var ed := maxi(1, d / GACETA_EVERY)
	var since := d - GACETA_EVERY   # las noches de los últimos 5 días (la del día anterior incluida)
	var recent := news.filter(func(e): return int(e.get("day", 0)) >= since)
	var mine: Array = []
	var others: Array = []
	var me_pos := position(ME)
	# 1) ella: el puesto 1, una medalla, lo que subió en estos días
	for e in recent:
		if e["id"] == ME and e["kind"] == "first":
			mine.append({"title": "Midnight Cauldron Tops the Rankings!", "text": "The Arvendal Apothecaries' Guild is already polishing the golden cauldron.", "who": "alquimista", "crest": ME, "w": 100})
		elif e["id"] == ME and e["kind"] == "medal":
			mine.append({"title": "%s Medal for Midnight Cauldron" % MEDAL_NAMES.get(e["medal"], e["medal"]), "text": "It was at %s. Lakevale talks of nothing else." % String(e.get("where", "an event")), "who": "alquimista", "crest": ME, "w": 80})
	var risers := _risers(GACETA_EVERY)
	if not risers.is_empty() and risers[0][0] == ME and int(risers[0][1]) >= 3:
		var rt: Array = ["Midnight Cauldron Climbs Fastest", "Midnight Cauldron Keeps Climbing", "Who's Behind Midnight Cauldron?", "Midnight Cauldron, Unstoppable"]
		mine.append({"title": rt[ed % rt.size()], "text": "Up %d places in %d days. Now %s in Arvendal." % [int(risers[0][1]), GACETA_EVERY, UIKit.ordinal(me_pos)], "who": "alquimista", "crest": ME, "w": 60})
	# 2) Fizz: se muda, explota o le pisa los talones
	var fizz_pos := position("fizz")
	for e in recent:
		if e["id"] == "fizz" and e["kind"] == "move":
			others.append({"title": "Fizz & Spark Moves to Lakevale", "text": "“I'm here to beat the potion lady,” says the gnome.", "who": "fizz", "crest": "fizz", "w": 90})
		elif e["id"] == "fizz" and e["kind"] == "boom":
			others.append({"title": "Another Explosion at Fizz & Spark", "text": "“It was on purpose,” Fizz insists, eyebrows singed.", "who": "fizz", "crest": "fizz", "w": 55})
	if absi(fizz_pos - me_pos) <= 2 and d >= FIZZ_ARRIVES:
		if fizz_pos > me_pos:
			others.append({"title": "Fizz & Spark Hot on Midnight Cauldron's Heels", "text": "“I'll pass her this week,” the gnome promises.", "who": "fizz", "crest": "fizz", "w": 50})
		else:
			others.append({"title": "Fizz & Spark Ahead of Midnight Cauldron", "text": "“Get used to it,” says Fizz. Spark says nothing.", "who": "fizz", "crest": "fizz", "w": 50})
	# 3) las rivales: medallas y tropiezos
	for e in recent:
		var id := String(e["id"])
		if id == ME or id == "fizz":
			continue
		var s := shop(id)
		if e["kind"] == "medal":
			others.append({"title": "%s Medal for %s" % [MEDAL_NAMES.get(e["medal"], e["medal"]), s["name"]], "text": "It was at %s. Party time for %s in %s." % [String(e.get("where", "")), String(s["owner"]), town_name(town_of(id))], "who": "", "crest": id, "w": 40 + (20 if e["medal"] == "oro" else 0)})
		elif e["kind"] == "scandal":
			var lines: Array = SCANDALS_BY.get(id, SCANDALS)
			var text := String(lines[int(e.get("n", 0)) % lines.size()]).replace("{s}", String(s["name"])).replace("{o}", String(s["owner"])).replace("{t}", town_name(town_of(id)))
			others.append({"title": "Mishap at %s" % s["name"], "text": text, "who": "", "crest": id, "w": 45})
	if not risers.is_empty():
		for r in risers:
			if r[0] != ME and r[0] != "fizz" and int(r[1]) >= 2:
				others.append({"title": "%s on the Rise" % shop_name(r[0]), "text": "Up %d places in %d days." % [int(r[1]), GACETA_EVERY], "who": "", "crest": r[0], "w": 30})
				break
	# 4) si no pasó nada: la de siempre en la cima
	var top: String = order()[0]
	if top != ME:
		var tt: Array = ["%s Stays on Top", "No One Can Topple %s", "%s, Number One for Another Week"]
		others.append({"title": String(tt[ed % tt.size()]) % shop_name(top), "text": _top_quote(top), "who": "", "crest": top, "w": 10})
	mine.sort_custom(func(a, b): return int(a["w"]) > int(b["w"]))
	others.sort_custom(func(a, b): return int(a["w"]) > int(b["w"]))
	var out: Array = []
	if not mine.is_empty():
		out.append(mine[0])
	for h in others:
		if out.size() >= n:
			break
		out.append(h)
	for h in mine.slice(1):
		if out.size() >= n:
			break
		out.append(h)
	return out

func _top_quote(id: String) -> String:
	if id == "alambique":
		return "“First place isn't inherited, it's earned,” says Master Agata Velnor."
	return "%s of %s won't let go of first place." % [String(shop(id).get("owner", "")), town_name(town_of(id))]

## Las que más subieron en los últimos `days` días: [[id, puestos], ...] de más a menos.
func _risers(days: int) -> Array:
	if snaps.is_empty():
		return []
	var now: Dictionary = snaps[-1]["pos"]
	var then: Dictionary = {}
	for s in snaps:
		if int(s["day"]) <= int(snaps[-1]["day"]) - days:
			then = s["pos"]
	if then.is_empty():
		then = snaps[0]["pos"] if snaps.size() > 1 else {}
	if then.is_empty():
		return []
	var out: Array = []
	for id in now:
		var dv := int(then.get(id, now[id])) - int(now[id])
		if dv > 0:
			out.append([id, dv])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return out

# ------------------------------------------------------------------ el final del puesto 1

## Llegó al puesto 1 y el final todavía no se jugó.
func ending_due() -> bool:
	return position(ME) == 1 and not ending_seen and last_day > 0

func mark_ending_seen() -> void:
	ending_seen = true

# ------------------------------------------------------------------ guardado (game.gd lo llama)

func save_data() -> Dictionary:
	_ensure()
	return {"v": SAVE_V, "seed": seed0, "scores": scores, "pace": pace, "prev": prev_pos, "snaps": snaps, "hist": hist,
		"news": news, "last": last_day, "ren_base": ren_base, "move": last_move, "news_day": news_day,
		"gaceta": gaceta_seen, "ending": ending_seen}

## Carga el Escalafón. Una partida de antes (sin "rank") empieza con la tabla de siempre y ella última.
func load_data(d) -> void:
	reset()
	if not (d is Dictionary) or d.is_empty():
		ren_base = Game.renombre
		last_day = maxi(0, Game.day - 1)
		return
	seed0 = int(d.get("seed", seed0))
	var sc = d.get("scores", {})
	if sc is Dictionary:
		for id in sc:
			if scores.has(id):
				scores[id] = float(sc[id])
	var pc = d.get("pace", {})
	if pc is Dictionary:
		for id in pc:
			if pace.has(id):
				pace[id] = float(pc[id])
	var pp = d.get("prev", {})
	if pp is Dictionary:
		for id in pp:
			if scores.has(id):
				prev_pos[id] = int(pp[id])
	snaps = []
	for s in d.get("snaps", []):
		if s is Dictionary and s.get("pos") is Dictionary:
			var pos := {}
			for id in s["pos"]:
				pos[String(id)] = int(s["pos"][id])
			snaps.append({"day": int(s.get("day", 0)), "pos": pos})
	hist = []
	for h in d.get("hist", []):
		if h is Dictionary:
			hist.append({"day": int(h.get("day", 0)), "pos": int(h.get("pos", size())), "pts": int(h.get("pts", 0)), "score": int(h.get("score", 0))})
	news = []
	for e in d.get("news", []):
		if e is Dictionary and e.has("id") and e.has("kind"):
			var ne: Dictionary = e.duplicate()
			ne["day"] = int(ne.get("day", 0))
			if ne.has("where"):   # --- R5 EN-UI: una partida de antes guardó el lugar en castellano
				ne["where"] = String(OLD_WHERE.get(String(ne["where"]), ne["where"]))
			if ne.has("n"):
				ne["n"] = int(ne["n"])
			news.append(ne)
	last_day = int(d.get("last", 0))
	ren_base = int(d.get("ren_base", Game.renombre))
	var mv = d.get("move", {})
	last_move = {}
	if mv is Dictionary and not mv.is_empty():
		last_move = mv.duplicate(true)
		for k in ["day", "pos", "prev", "delta", "points", "score"]:
			if last_move.has(k):
				last_move[k] = int(last_move[k])
	news_day = int(d.get("news_day", 0))
	gaceta_seen = int(d.get("gaceta", 0))
	ending_seen = bool(d.get("ending", false))

# ------------------------------------------------------------------ ayudas

func _today() -> int:
	return int(Game.day)

func _ensure() -> void:
	if not _ready_state:
		reset()

## Para las pruebas (--demo=ranking, gaceta, ending, ranksim): simula n días con un día de ella fijo o creciente.
## per_day: Callable(day) -> Dictionary como Game.today (sold, event...); ren_per_day: renombre ganado cada día.
func simulate(days: int, per_day: Callable, ren_per_day := 15) -> void:
	for i in days:
		var t: Dictionary = per_day.call(Game.day)
		Game.today = t
		Game.renombre += ren_per_day
		commit_day()
		Game.day += 1
	Game.reset_today()
