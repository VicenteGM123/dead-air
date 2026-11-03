extends Node
## --- SS2 RANK: el Lantern Board (autoload «Ranking»): «Top 30 shops of the Amber Drift» (SS2_DESIGN §3, §8.7).
## Port de ranking.gd de Midnight Cauldron (tiendas con ritmo, deriva, tropiezos, fotos de la tabla, guardado,
## simulación) con las reglas de Secondhand Stars:
##   - las estrellas del día de Nell (day_stars) salen de Game.today: atendidos + estrellas de las reparaciones y de
##     las ventas + eventos + día limpio + atractivo de las mejoras − perdidos; el día final (la Great Starfall) cuenta
##     doble (Season.k("stars_k"));
##   - las 29 tiendas suman su ritmo cada noche (x SCALE), con su curva (constante, decae, sube, irregular), un
##     temblor diario y a veces un tropiezo (las noticias del Report en el modo sin fin);
##   - el campeón (The Gilded Gear) es la vara fija del #1: ritmo 34, el escándalo de la noche 7 (8), después 28;
##   - la rival (Shine Again, Madame Glint) sigue un guion pero se mantiene cerca: cada noche suma entre 0.85 y 1.05
##     de la «base» de Nell (su día sin los eventos), salvo la noche de la mudanza (3); el favor de Buff (+8, noche 5)
##     y el globo de cromo de la noche 8 (+12 solo si Nell iba delante);
##   - la Great Starfall dobla a Nell y a Dune Pocket, nunca a Shine Again («fixes count twice; shine doesn't»);
##   - hitos (las puntas del cartel), la línea de Rosa Reverb de cada noche, el Lantern Report (noches 3, 6, 9 y
##     después cada 3 en el modo sin fin), el premio de la noche del cometa, LATE, bonos, guardado, ranksim.
## Todo lo público empieza con _ensure(): Game.new_game_state() puede llamar a reset() antes que el _ready de aquí.
## Compila con o sin la línea S: Season, Game.flag(), Game.is_campaign(), Game.ending_seen se leen por nombre
## (_season(), _flag(), ...), así el mismo archivo sirve en el árbol de R antes del JOIN y en el juego entero.

const ME := "secondhandstar"
const SCALE := 0.75
const BOARD_NAME := "Lantern Board"
const BOARD_SUB := "Top 30 shops of the Amber Drift"
const REGION := "the Amber Drift"
const SHOW := "the Drift Signal"
const HOST := "Rosa Reverb"
const REPORT := "the Lantern Report"
const GUILD := "the Fixers' Guild"
const SIGNOFF := "That's the Signal. Keep your lights on, Drift."
const LAST_DAY := 10                 # como SeasonData.LAST_DAY (la noche del cometa)
const RIVAL := "shineagain"
const RIVAL_SCRIPT := [21, 21, 8, 32, 29, 36, 38, 40, 41, 43]   # antes de SCALE (§3.5)
const RIVAL_CLAMP := [0.85, 1.05]    # x la base de Nell esa noche; no la noche de la mudanza
const RIVAL_WOBBLE := 0.07
const RIVAL_MOVE_NIGHT := 3          # Shine Again se muda a Rustwater (sin margen esa noche)
const RIVAL_ENDLESS_K := 0.95        # modo sin fin: 0.95 x la base media de Nell de sus 3 últimas noches
const BALLOON := 18                  # noche 8, después de SCALE, solo si Nell iba delante después de la noche 7
const BALLOON_NIGHT := 8
const CHAMPION := "gildedgear"
# --- POLISH LOOK (BAL): "after" 19 -> 27 (las noches 8-10, después del escándalo): con los arreglos de la ronda de
# pulido (menos turnos muertos, cápsulas con algo adentro, manos calientes) un jugador "humano" sumaba ~30 estrellas
# más y ganaba el cometa en ~97 % de las temporadas simuladas; así vuelve a ~88 % (ranksim con la tabla medida de
# los bots), el primer #1 sigue siendo la noche 10 y el escándalo de la noche 7 sigue abriendo la puerta.
const CHAMPION_PACE := {"pace": 34, "scandal_night": 7, "scandal": 8, "after": 27, "endless": 28, "wobble": 0.06}
const DOUBLE_ON_FINALE := ["secondhandstar", "dunepocket"]
const SCRIMP := "dunepocket"
const RUSTWATER := ["secondhandstar", "shineagain", "dunepocket"]   # los tres faroles de Rustwater
const MILESTONES := [20, 15, 10, 5, 1]
const REPORT_EVERY := 3
const LATE_STARS := -3
const LATE_NIGHTS := 3
const ENDLESS_K := 0.9               # modo sin fin: todos x 0.9 salvo los que suben (CURVES[*].keeps)
const SNAPS_KEEP := 14

## Las curvas de §3.3 (antes de SCALE): grow = cuánto cambia el ritmo hasta la noche 10 (lineal desde la noche 1),
## wobble = temblor diario (±), risk = probabilidad de un tropiezo (esa noche no suma: la noticia del Report),
## keeps = conserva su ritmo en el modo sin fin (las demás x ENDLESS_K).
const CURVES := {
	"steady": {"grow": 0.0, "wobble": 0.10, "risk": 0.0, "keeps": false},
	"fading": {"grow": -0.15, "wobble": 0.10, "risk": 0.0, "keeps": false},
	"contender": {"grow": 0.15, "wobble": 0.10, "risk": 0.0, "keeps": true},
	"darkhorse": {"grow": 0.25, "wobble": 0.10, "risk": 0.0, "keeps": true},
	"rising": {"grow": 0.10, "wobble": 0.10, "risk": 0.0, "keeps": false},
	"erratic": {"grow": 0.0, "wobble": 0.22, "risk": 0.02, "keeps": false},
	"erratic_contender": {"grow": 0.15, "wobble": 0.22, "risk": 0.02, "keeps": true},
}

## Los mundos del Board (§3.2): nombre (≤ 14), la línea del tablero (≤ 70) y el color del escudo.
const WORLDS := {
	"saffra": {"name": "Saffra", "line": "Our desert world. One big amber sun. Things fall here.", "colour": "e8a83a"},
	"brindle": {"name": "Brindle", "line": "Copper-grass prairie. Ranches, wind and hoverbikes.", "colour": "b5523a"},
	"ochre": {"name": "Ochre", "line": "Clay world of potters and kilns. Every town is terracotta.", "colour": "c8743a"},
	"patina": {"name": "Patina", "line": "Green copper cliffs and rain canals. Pipe-fitters galore.", "colour": "5f9e86"},
	"thimble": {"name": "Thimble", "line": "A tiny asteroid town where everything is built small.", "colour": "c99d48"},
	"hollowmere": {"name": "Hollowmere", "line": "A quiet crater lake with tea terraces and lamp-makers.", "colour": "a98bc4"},
	"teasel": {"name": "Teasel", "line": "Orchard world of fruit, garden bots and bees.", "colour": "7da26a"},
	"brineflat": {"name": "Brineflat", "line": "Tidal salt flats and shell-roofed huts. Sea stories.", "colour": "7f8f99"},
	"hitchpost": {"name": "Hitchpost", "line": "Where the trade lanes tie up. The Fixers' Guild keeps the Board.", "colour": "f0c050"},
	"shoals": {"name": "the Shoals", "line": "A reef of old wrecks around a dead star. Big salvage crews.", "colour": "4a6a8a"},
	"moving": {"name": "on the move", "line": "A caravan of tortoises. Never in the same place twice.", "colour": "b08a5a"},
}

## Las 30 tiendas (§3.3) en el orden de los escudos (assets/ui/crests.png). start / pace antes de SCALE.
## --- SS2 RANK: el ritmo de los aspirantes (thimble, pipeworks, rollingbazaar, couriercorner, bikebolt) y de
## glassblown bajó respecto de §3.3 para cumplir la guarda de §3.3 («en la semilla mediana ninguna tienda termina la
## noche 10 por encima de The Gilded Gear»): con los ritmos del diseño Courier Corner terminaba en ~342 y Thimble en
## ~318, por encima del campeón (~312). Ver NOTES (ranksim) para los números de antes y después.
const SHOPS := [
	{"id": "gildedgear", "name": "The Gilded Gear", "owner": "Orrin Vale", "species": "human", "world": "hitchpost",
		"start": 120, "pace": 34, "curve": "champion", "line": "Keeps the Fixers' Guild's clocks. Never late."},
	{"id": "deepsalvage", "name": "Halvard Deepsalvage", "owner": "Big Halvard", "species": "Hornback", "world": "shoals",
		"start": 96, "pace": 17, "curve": "fading", "line": "Three salvage tugs and one enormous hat."},
	{"id": "patienthand", "name": "The Patient Hand", "owner": "Miss Wynna", "species": "Glimmerfolk", "world": "hollowmere",
		"start": 93, "pace": 19, "curve": "steady", "line": "One repair a day. Perfect, every time."},
	{"id": "longcounter", "name": "The Long Counter", "owner": "Abel Marrowby", "species": "human", "world": "hitchpost",
		"start": 90, "pace": 21, "curve": "fading", "line": "Forty metres of counter. Nobody at the far end."},
	{"id": "kilnworks", "name": "Kilnworks Restorations", "owner": "Granny Terra", "species": "Thornfolk", "world": "ochre",
		"start": 90, "pace": 23, "curve": "steady", "line": "Glues pots, bots and broken hearts."},
	{"id": "hornpost", "name": "Hornback Trading Post", "owner": "Aunt Brakka", "species": "Hornback", "world": "brindle",
		"start": 87, "pace": 11, "curve": "fading", "line": "Gorrum's aunt. Also never says yes first."},
	{"id": "brineswap", "name": "Brineflat Swap", "owner": "Captain Tamsin Shell", "species": "human", "world": "brineflat",
		"start": 87, "pace": 11, "curve": "fading", "line": "Salvage, salt and sea stories."},
	{"id": "fogbellows", "name": "Fog & Bellows", "owner": "Uncle Augustin", "species": "Bottlefog", "world": "patina",
		"start": 86, "pace": 11, "curve": "fading", "line": "Suits, seals and pressure valves."},
	{"id": "glassblown", "name": "Glassblown Clocks", "owner": "Old Tick", "species": "Sandglass", "world": "saffra",
		"start": 83, "pace": 23, "curve": "steady", "line": "Fixes clocks. Takes its time. All of it."},
	{"id": "thimble", "name": "Thimble & Thread", "owner": "the Tock twins", "species": "Burrowers", "world": "thimble",
		"start": 80, "pace": 26, "curve": "contender", "line": "Tiny tools for tiny worlds."},
	{"id": "clockpantry", "name": "The Clockwork Pantry", "owner": "Missus Tidy", "species": "bot", "world": "thimble",
		"start": 75, "pace": 14, "curve": "steady", "line": "Run entirely by a bot. Alarmingly tidy."},
	{"id": "pipeworks", "name": "Patina Pipeworks", "owner": "Ned Hale", "species": "human", "world": "patina",
		"start": 74, "pace": 23, "curve": "contender", "line": "Pumps, pipes and the odd song box."},
	{"id": "rollingbazaar", "name": "The Rolling Bazaar", "owner": "the Tumble clan", "species": "Dune Rakers", "world": "moving",
		"start": 74, "pace": 24, "curve": "erratic_contender", "line": "A shop on twelve tortoises."},
	{"id": "couriercorner", "name": "Courier Corner", "owner": "Zaz", "species": "Quill", "world": "hitchpost",
		"start": 74, "pace": 26, "curve": "darkhorse", "line": "Repairs while you wait. You will not wait."},
	{"id": "orchard", "name": "The Mended Orchard", "owner": "the Orchard Co-op", "species": "mixed", "world": "teasel",
		"start": 72, "pace": 13, "curve": "steady", "line": "Fixes garden bots. Pays in fruit."},
	{"id": "unittwelve", "name": "Unit Twelve's Spares", "owner": "Unit Twelve", "species": "bot", "world": "hitchpost",
		"start": 69, "pace": 12, "curve": "steady", "line": "Sorts screws by size. All day. Happily."},
	{"id": "bikebolt", "name": "Brindle Bike & Bolt", "owner": "Dusty Marlowe", "species": "human", "world": "brindle",
		"start": 68, "pace": 25, "curve": "contender", "line": "Hoverbikes, saddles and sorry-about-the-noise."},
	{"id": "drybell", "name": "Dry Bell Diggings", "owner": "Tibbet", "species": "Burrower", "world": "saffra",
		"start": 54, "pace": 13, "curve": "steady", "line": "Fixes drills. Apologises a lot."},
	{"id": "moonmoth", "name": "Moonmoth Lamps", "owner": "Old Wick", "species": "Lampwing", "world": "hollowmere",
		"start": 51, "pace": 12, "curve": "steady", "line": "Lamps only. Open only at night."},
	{"id": "tinpot", "name": "Tinpot Repairs", "owner": "Tad Tinpot", "species": "human", "world": "ochre",
		"start": 48, "pace": 11, "curve": "steady", "line": "Small fixes. Big opinions."},
	{"id": "pricklyparts", "name": "Prickly Parts", "owner": "Cholla Jo", "species": "Thornfolk", "world": "saffra",
		"start": 44, "pace": 10, "curve": "steady", "line": "Please don't lean on the counter."},
	{"id": "shineagain", "name": "Shine Again", "owner": "Madame Glint & Buff", "species": "human and bot", "world": "hitchpost",
		"start": 64, "pace": 0, "curve": "rival", "line": "We don't fix it. We make it sparkle."},
	{"id": "gutter", "name": "Gutter & Gear", "owner": "Scrap Sal", "species": "human", "world": "shoals",
		"start": 33, "pace": 10, "curve": "erratic", "line": "Will fix anything. Has fixed nothing."},
	{"id": "halfhalf", "name": "Half & Half", "owner": "Polly Nim", "species": "Quill", "world": "teasel",
		"start": 30, "pace": 9, "curve": "fading", "line": "Half price. Half working."},
	{"id": "honestholt", "name": "Honest Holt's", "owner": "Holt", "species": "human", "world": "brindle",
		"start": 26, "pace": 8, "curve": "erratic", "line": "Not honest. Possibly not Holt."},
	{"id": "lastbolt", "name": "The Last Bolt", "owner": "Granny Pruett", "species": "human", "world": "brineflat",
		"start": 22, "pace": 7, "curve": "fading", "line": "Retiring soon. Has said so for thirty years."},
	{"id": "oddsendings", "name": "Odds & Endings", "owner": "the Mumbles", "species": "Bottlefogs", "world": "patina",
		"start": 14, "pace": 6, "curve": "steady", "line": "Sells halves of things. Ask about the other half."},
	{"id": "fennel", "name": "Fennel's Fences", "owner": "Fennel", "species": "Thornfolk", "world": "teasel",
		"start": 10, "pace": 5, "curve": "steady", "line": "Fixes fences. Mostly fences."},
	{"id": "dunepocket", "name": "Dune Pocket", "owner": "Little Scrimp", "species": "Dune Raker", "world": "saffra",
		"start": 5, "pace": 3, "curve": "rising", "line": "A blanket, a kid and a very big dream."},
	{"id": "secondhandstar", "name": "The Secondhand Star", "owner": "Nell & Kettle", "species": "human and bot", "world": "saffra",
		"start": 0, "pace": 0, "curve": "player", "line": "Fixed here. Properly."},
]

## Las puntas del cartel (§3.7): la línea del libro de cuentas y del tablero.
const MILESTONE_LINES := ["", "One point lit. Rustwater noticed.", "Two points. The Raker waves first now.",
	"Top ten in the Drift. Kettle is unbearable.", "Four points. Glint bought sunglasses.",
	"All five. And something brass on the way."]

## Rosa Reverb, cada noche (§3.8; ≤ 80 caracteres ya rellena). {o} / {O} = el puesto en palabras.
const ROSA := {
	"first": "New on the Board: The Secondhand Star, Rustwater. {O}, and glowing.",
	"up": "The Secondhand Star, Rustwater: up {n}, to {o}!",
	"down": "The Secondhand Star: down {n}, to {o}. Chin up, dune.",
	"same": "The Secondhand Star holds at {o}.",
	"pass_rival": "Fix beats shine! The Secondhand Star passes Shine Again.",
	"rival_back": "Shine Again polishes past the Secondhand Star. Buff seen gloating.",
	"pass_scrimp": "Two Rustwater lanterns climbing. The kid's taking notes.",
	"top20": "A shop on a dune joins the top twenty.",
	"top10": "Top ten, from a sand port. The Drift takes notice.",
	"left3": "Three lights left above Rustwater.",
	"left2": "Two lights left above Rustwater.",
	"left1": "One light left above Rustwater.",
	"top1": "The Secondhand Star tops the Lantern Board! Lanterns up, Rustwater!",
	"balloon_up": "Shine Again's chrome balloon: the whole Drift is looking up.",
	"balloon_pop": "Shine Again's chrome balloon pops over the market. Buff inconsolable.",
	"eve": "Secondhand Star: {o} tonight. Tomorrow counts double, Rustwater!",   # --- POLISH FIX (F6)
}

## El Lantern Report (§3.9): 7 líneas de ≤ 70 caracteres con los nombres más largos. Los tres primeros, escritos.
const REPORT1 := {
	"top": "On top: {first}. Nothing ever changes up there. Yet.",
	"nell_up": "Secondhand Star: up {n} in three nights, to {o}!",   # --- POLISH FIX (F10): la temporada, no esta noche
	"nell": "Rustwater's Secondhand Star: {o} and fixing hard.",
	"news": "Shine Again moves to Rustwater. Glint: 'I watch. Closely.'",
	"scandal": "Honest Holt sells the same bike to three people. On a Tuesday.",
	"lost_crate": "Lost: one crate. Sealed. Humming. Finder, keep it quiet.",
	"ad": "Shine Again: why fix it when you can shine it?",
	"weather": "Clear skies. The Slow Orbit's song box is stuck again. Loudly.",
}
const REPORT2 := {
	"top": "On top: {first}. Rising: {mover}.",
	"nell": "{leader} leads the Rustwater race by {gap} ★.",
	"news": "Tally Office inspects Rustwater. Tolle: '{grade}.'",
	"scandal": "Scrap Sal fixes nothing again. A record streak.",
	"lost": "Lost: a lamp. A very old lamp. Ask for Seven.",
	"weather": "Sky-watch: a big shadow on the Ring tonight. Keep your hats on.",
}
const REPORT3 := {
	"top": "Clocks ran fast at the Gilded Gear. On top: {first}.",
	"nell": "Rustwater race: {leader} by {gap} ★. One night left.",
	"podium": "Glasspan Derby: {winner} wins on a Secondhand Star bike!",
	"no_podium": "Glasspan Derby: a Brindle crew takes the cup. Dust everywhere.",
	"scandal": "Shine Again asks the Fixers' Guild to count polish twice. Denied.",
	"found": "Found: one lamp core. Glows when nobody's looking.",
	"ad": "The Slow Orbit: cold drinks, warm band, no sand on the dance floor.",
	"weather": "Tomorrow the Great Starfall: every fix counts twice. Lanterns out!",
}
const GRADES := {"certified": "Approved", "pass": "Satisfactory", "noted": "Noted"}
## Los pools del modo sin fin (como SCANDALS_BY de Caldero). {s} tienda, {o} dueño, {w} mundo, {n} número.
const POOL_TOP := ["On top: {first}. For now.", "On top: {first}. The Drift wonders how.",
	"On top: {first}. Polishing the comet already."]
const POOL_TOP_ME := ["On top: the Secondhand Star. Rustwater won't stop humming.",
	"On top: the Secondhand Star. The comet still shines."]
const POOL_NELL := "Rustwater's Secondhand Star: {o} on the Board."
const POOL_HEADLINES := ["{s} fixes a 90-year-old tug. The tug says thanks.",
	"Big week on {w}: {s} up {n} places.",
	"{o} opens a second counter. Customers confused.",
	"{s} shuts for a week. The owner took a holiday.",
	"{s} wins the {w} Fixers' Fair. Again.",
	"Fixers' Guild: {s} is 'worryingly tidy'."]
const POOL_SCANDALS := ["{s} sold a toaster as a compass. It finds jam.",
	"{s} glued a bot back together. Upside down.",
	"{s}: only polka now. Nobody stops dancing.",
	"Tally Office fines {s}: right form, wrong colour."]
const SCANDALS_BY := {
	"honestholt": "Honest Holt sells the same bike to three people. On a Tuesday.",
	"gutter": "Scrap Sal fixes nothing again. A record streak.",
	"longcounter": "A Long Counter clerk lost behind the counter. Found on day three.",
	"clockpantry": "The Clockwork Pantry closes for spring cleaning. It is not spring.",
	"halfhalf": "Half & Half sells half a radio. Full price.",
	"shineagain": "Shine Again's 'new' radios are old radios. Very shiny old radios.",
}
const POOL_ADS := ["Tally Office reminder: a happy form is a filled form.",
	"Thimble & Thread: tiny tools for tiny worlds.",
	"Mags's Parts: fixed prices. Haggle with the sand.",
	"Halvard Deepsalvage: we tow anything. Even your mood.",
	"The Slow Orbit: cold drinks, warm band, no sand on the dance floor.",
	"Shine Again: why fix it when you can shine it?"]
const WEATHER_CLEAR := "Clear skies over Saffra. Hats optional."

## El premio de la noche del cometa (§3.10).
const AWARDS := {
	"champion": {"title": "The Brass Comet", "line": "First on the Lantern Board. The comet is yours."},
	"rising": {"title": "Rising Lantern of the Drift", "line": "The comet is a few good days away."},
	"rookie": {"title": "Rookie of the Season", "line": "A shop to watch next season."},
	"newshop": {"title": "Best New Shop in Rustwater", "line": "Every lantern starts small."},
}

const ORD := ["zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
	"eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
	"nineteenth", "twentieth", "twenty-first", "twenty-second", "twenty-third", "twenty-fourth", "twenty-fifth",
	"twenty-sixth", "twenty-seventh", "twenty-eighth", "twenty-ninth", "thirtieth"]

# ------------------------------------------------------------------ estado

var seed0 := 0
var scores := {}          # id -> estrellas de la temporada (float)
var prev_scores := {}     # id -> antes de la última noche (el tablero de la noche gira desde aquí)
var prev_pos := {}        # id -> puesto antes de la última noche
var committed := 0        # la última noche contada (Game.day)
var nights := 0           # cuántas noches se contaron
var best_pos := 30        # el mejor puesto de Nell (las puntas del cartel)
var _last_move := {}
var _bonus := {}          # id -> estrellas para la próxima noche (después del margen de la rival)
var _late := 0            # noches que le quedan al sello LATE en nuestra fila
var _late_pending := false
var reports_read: Array = []
var base_hist: Array = [] # la base de Nell de cada noche (el ritmo de la rival en el modo sin fin)
var hist: Array = []      # Nell, noche a noche: [{"night", "pos", "stars", "score"}]
var snaps: Array = []     # las últimas tablas: [{"night", "pos": {id: puesto}}]
var news: Array = []      # tropiezos de las rivales: [{"night", "id", "kind"}]
var balloon := ""         # el globo de cromo de la noche 8: "" | "talk" (le fue bien) | "popped"
var _used := {}           # segmento del Report -> índice de la última línea (nunca la misma dos veces seguidas)
var debug_flags := {}     # (pruebas: ranktest y las demos del Report) marcas de historia que ganan a Game.flags
var _built := false

func _init() -> void:
	_ensure()

func _ensure() -> void:
	if _built:
		return
	_built = true
	_reset_scores()

func _reset_scores() -> void:
	scores = {}
	for s in SHOPS:
		scores[String(s["id"])] = float(s["start"]) * (1.0 if String(s["id"]) == ME else SCALE)
	prev_scores = scores.duplicate()
	prev_pos = _positions()
	committed = 0
	nights = 0
	_last_move = {}
	_bonus = {}
	_late = 0
	_late_pending = false
	best_pos = int(prev_pos.get(ME, SHOPS.size()))
	reports_read = []
	base_hist = []
	hist = []
	snaps = []
	news = []
	balloon = ""
	_used = {}

## Partida nueva (Game.new_game_state). seed: la semilla de la partida (Game.run_seed), así Continue ve lo mismo.
func reset(seed := -1) -> void:
	_built = true
	seed0 = seed if seed >= 0 else randi() % 1000000
	_reset_scores()

# ------------------------------------------------------------------ lo que se lee de las otras líneas (por nombre)

func _season() -> Node:
	return get_node_or_null("/root/Season") if is_inside_tree() else null

## Season.k(key) (un producto; 1.0 si no hay Season). Sin Season, la Great Starfall igual dobla el día 10.
func _sk(key: String, night := -1) -> float:
	var s := _season()
	if s != null and s.has_method("k"):
		return float(s.call("k", key))
	if key == "stars_k" and _is_finale(Game.day if night < 0 else night):
		return 2.0
	return 1.0

func _sn(key: String) -> int:
	var s := _season()
	if s != null and s.has_method("n"):
		return int(s.call("n", key))
	return 0

func _is_finale(night: int) -> bool:
	var s := _season()
	if s != null and s.has_method("is_finale"):
		return bool(s.call("is_finale", night))
	return night == LAST_DAY

func _flag(key: String, def = null):
	if debug_flags.has(key):
		return debug_flags[key]
	if Game.has_method("flag"):
		return Game.call("flag", key, def)
	return def

func _is_campaign() -> bool:
	if Game.has_method("is_campaign"):
		return bool(Game.call("is_campaign"))
	return Game.day <= LAST_DAY

func _game_bool(key: String) -> bool:
	var v = Game.get(key)
	return bool(v) if v != null else false

# ------------------------------------------------------------------ las estrellas de un día (§3.4)

## Las estrellas del día de Nell. t: Game.today (o un diccionario de prueba). Devuelve {"total", "base", "parts"}:
## base = el día sin los eventos (lo que la rival copia); total = (base + eventos) x stars_k (la final, x2).
## parts: served, repairs (reparaciones + sus estrellas), sales (ventas + sus estrellas), events, clean, appeal,
## lost (negativo), finale (lo que suma el x2), other (atendidos que no son ni reparación ni venta).
func day_stars(t: Dictionary = {}) -> Dictionary:
	_ensure()
	var d: Dictionary = t if not t.is_empty() else Game.today
	var rep_n := maxi(0, int(d.get("repairs", 0)))
	var sale_n := maxi(0, int(d.get("sales", 0)))
	var served := maxi(0, int(d.get("served", rep_n + sale_n)))
	var rep := maxi(0, int(d.get("repair_stars", d.get("stars", 0))))
	var sal := maxi(0, int(d.get("sale_stars", 0)))
	var ev := int(d.get("event_stars", 0))
	var walk := maxi(0, int(d.get("walkouts", 0)))
	var failed := maxi(0, int(d.get("failed", 0)))
	var missed := maxi(0, int(d.get("missed", 0)))
	var clean := 1 if walk == 0 and missed == 0 and failed == 0 else 0
	if d.has("clean"):
		clean = 1 if int(d["clean"]) > 0 else 0
	var appeal := int(d.get("appeal", _sn("appeal")))
	var lost := walk + failed + mini(missed, 2)
	var day := served + rep + sal + ev + 3 * clean + appeal - lost
	var base := day - ev
	var k := float(d.get("stars_k", _sk("stars_k")))
	var total := int(round(day * k))
	var other := served - rep_n - sale_n
	return {"total": total, "base": base, "parts": {"served": served, "repairs": rep_n + rep, "sales": sale_n + sal,
		"events": ev, "clean": 3 * clean, "appeal": appeal, "lost": -lost, "finale": total - day, "other": other}}

# ------------------------------------------------------------------ la noche: todas las tiendas suman

## Cuenta la noche (una vez por Game.day): las estrellas de Nell, las de todas las tiendas, el movimiento.
## Devuelve el movimiento: {"day", "pos", "prev", "delta", "stars", "score", "parts", "passed": [ids],
## "passed_by": [ids], "next": {"id", "name", "gap"}, "rival": {"pos", "gap"}, "milestone": 0..5,
## "milestone_new": 0..5, "line": la línea de Rosa, "late": -3 | 0, "bonus", "balloon"}.
func commit_day() -> Dictionary:
	_ensure()
	if committed == Game.day and committed > 0 and not _last_move.is_empty():
		return _last_move
	var ds := day_stars()
	return _commit(Game.day, int(ds["total"]), int(ds["base"]), ds["parts"])

func _commit(night: int, my_stars: int, my_base: int, parts := {}) -> Dictionary:
	prev_scores = scores.duplicate()
	var before := _positions()
	var prev := int(before.get(ME, SHOPS.size()))
	var milestones_before := milestone_points()
	var finale := _is_finale(night)
	var stars := my_stars
	var late_now := 0
	if _late_pending:
		late_now = LATE_STARS
		stars += LATE_STARS
		_late_pending = false
	var bonus_me := int(_bonus.get(ME, 0))
	stars += bonus_me
	scores[ME] = float(scores[ME]) + stars
	base_hist.append(my_base)
	var balloon_now := ""
	for s in SHOPS:
		var id := String(s["id"])
		if id == ME:
			continue
		var add := _night_of(s, night, my_base, finale)
		if id == RIVAL and night == BALLOON_NIGHT and _is_campaign_night(night):
			if float(prev_scores[ME]) > float(prev_scores[RIVAL]):
				add += BALLOON
				balloon_now = "talk"
			else:
				balloon_now = "popped"
		add += float(_bonus.get(id, 0))
		scores[id] = float(scores[id]) + maxf(0.0, add)
	if balloon_now != "":
		balloon = balloon_now
	_bonus = {}
	if _late > 0:
		_late -= 1
	committed = night
	nights += 1
	var after := _positions()
	var pos := int(after[ME])
	var passed: Array = []
	var passed_by: Array = []
	for id in after:
		if id == ME:
			continue
		var was_above := int(before[id]) < prev
		var now_above := int(after[id]) < pos
		if was_above and not now_above:
			passed.append(id)
		elif not was_above and now_above:
			passed_by.append(id)
	passed.sort_custom(func(a, b): return int(after[a]) < int(after[b]))
	passed_by.sort_custom(func(a, b): return int(after[a]) < int(after[b]))
	prev_pos = before
	best_pos = mini(best_pos, pos)
	snaps.append({"night": night, "pos": after})
	while snaps.size() > SNAPS_KEEP:
		snaps.pop_front()
	hist.append({"night": night, "pos": pos, "stars": stars, "score": score()})
	while hist.size() > 400:
		hist.pop_front()
	while news.size() > 60:
		news.pop_front()
	var ms := milestone_points()
	var p2: Dictionary = parts.duplicate()
	if late_now != 0:
		p2["late"] = late_now
	if bonus_me != 0:
		p2["bonus"] = bonus_me
	var rp := int(after[RIVAL])
	_last_move = {"day": night, "pos": pos, "prev": prev, "delta": prev - pos, "stars": stars, "score": score(),
		"parts": p2, "passed": passed, "passed_by": passed_by, "next": next_above(),
		"rival": {"pos": rp, "gap": int(round(float(scores[RIVAL]) - float(scores[ME])))},
		"milestone": ms, "milestone_new": ms if ms > milestones_before else 0,
		"late": late_now, "bonus": bonus_me, "balloon": balloon_now, "finale": finale,
		"line": _rosa(night, prev, pos, passed, passed_by, milestones_before, balloon_now)}
	return _last_move

func _is_campaign_night(night: int) -> bool:
	return night <= LAST_DAY

## Un RNG por tienda y noche (no depende del orden de las llamadas: Continue ve lo mismo).
func _rng(id: String, night: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%s|%d" % [seed0, id, night])
	return r

## Lo que suma una tienda esa noche (ya x SCALE; la rival, con su margen).
func _night_of(s: Dictionary, night: int, my_base: int, finale: bool) -> float:
	var id := String(s["id"])
	var r := _rng(id, night)
	var curve := String(s["curve"])
	if curve == "champion":
		var p := float(CHAMPION_PACE["pace"])
		var sn := int(CHAMPION_PACE["scandal_night"])
		if night > LAST_DAY:
			p = float(CHAMPION_PACE["endless"])
		elif night == sn:
			p = float(CHAMPION_PACE["scandal"])
		elif night > sn:
			p = float(CHAMPION_PACE["after"])
		var w := float(CHAMPION_PACE["wobble"])
		return p * SCALE * (1.0 + r.randf_range(-w, w))
	if curve == "rival":
		var raw: float
		if night <= RIVAL_SCRIPT.size():
			raw = float(RIVAL_SCRIPT[night - 1]) * SCALE * (1.0 + r.randf_range(-RIVAL_WOBBLE, RIVAL_WOBBLE))
		else:
			var last3: Array = base_hist.slice(maxi(0, base_hist.size() - 3))
			var sum := 0.0
			for b in last3:
				sum += float(b)
			raw = RIVAL_ENDLESS_K * sum / maxf(1.0, float(last3.size()))
		if night == RIVAL_MOVE_NIGHT:
			return raw
		var base := maxf(1.0, float(my_base))
		return clampf(raw, RIVAL_CLAMP[0] * base, RIVAL_CLAMP[1] * base)
	var c: Dictionary = CURVES.get(curve, CURVES["steady"])
	var f := clampf(float(night - 1) / float(LAST_DAY - 1), 0.0, 1.0)
	var pace := float(s["pace"]) * (1.0 + float(c["grow"]) * f)
	if night > LAST_DAY and not bool(c["keeps"]):
		pace *= ENDLESS_K
	var w2 := float(c["wobble"])
	var v := pace * SCALE * (1.0 + r.randf_range(-w2, w2))
	if float(c["risk"]) > 0.0 and r.randf() < float(c["risk"]):
		v = 0.0
		news.append({"night": night, "id": id, "kind": "stumble"})
	if finale and id in DOUBLE_ON_FINALE:
		v *= 2.0
	return v

## La línea de Rosa Reverb de esta noche (§3.8), por prioridad.
func _rosa(night: int, prev: int, pos: int, passed: Array, passed_by: Array, ms_before: int, balloon_now: String) -> String:
	var t := ""
	if nights == 1:
		t = String(ROSA["first"])
	elif balloon_now == "talk":
		t = String(ROSA["balloon_up"])
	elif balloon_now == "popped":
		t = String(ROSA["balloon_pop"])
	elif pos == 1 and prev > 1:
		t = String(ROSA["top1"])
	elif RIVAL in passed:
		t = String(ROSA["pass_rival"])
	elif RIVAL in passed_by:
		t = String(ROSA["rival_back"])
	elif pos <= 4 and prev > 4:
		t = String(ROSA["left%d" % (pos - 1)]) if pos > 1 else String(ROSA["top1"])
	elif pos <= 10 and prev > 10:
		t = String(ROSA["top10"])
	elif pos <= 20 and prev > 20:
		t = String(ROSA["top20"])
	elif SCRIMP in passed:
		t = String(ROSA["pass_scrimp"])
	elif pos < prev:
		t = String(ROSA["up"])
	elif pos > prev:
		t = String(ROSA["down"])
	else:
		t = String(ROSA["same"])
	# --- POLISH FIX (F6): la víspera del cometa, si Nell no va primera: todavía se puede (mañana cuenta doble)
	if night == LAST_DAY - 1 and pos > 1:
		t = String(ROSA["eve"])
	# --- end POLISH FIX
	var ow := ord_word(pos)
	return fill(t, {"n": str(absi(prev - pos)), "o": ow, "O": ow.left(1).to_upper() + ow.substr(1)})

# ------------------------------------------------------------------ lo que se lee

func last_move() -> Dictionary:
	_ensure()
	return _last_move

## Los ids ordenados por estrellas (empates: Nell primero, después el orden de SHOPS).
func order(prev := false) -> Array:
	_ensure()
	var sc: Dictionary = prev_scores if prev else scores
	var ids: Array = []
	var idx := {}
	for i in SHOPS.size():
		ids.append(String(SHOPS[i]["id"]))
		idx[String(SHOPS[i]["id"])] = i
	ids.sort_custom(func(a, b):
		var sa := float(sc.get(a, 0.0))
		var sb := float(sc.get(b, 0.0))
		if absf(sa - sb) > 0.001:
			return sa > sb
		if a == ME:
			return true
		if b == ME:
			return false
		return int(idx[a]) < int(idx[b]))
	return ids

func _positions(prev := false) -> Dictionary:
	var out := {}
	var o := order(prev)
	for i in o.size():
		out[o[i]] = i + 1
	return out

## La tabla del tablero, del 1 al 30 (prev = la de antes de la última noche: el tablero de la noche gira desde ahí).
func table(prev := false) -> Array:
	_ensure()
	var out: Array = []
	var o := order(prev)
	var top := float((prev_scores if prev else scores)[o[0]])
	for i in o.size():
		out.append(_row(String(o[i]), i + 1, prev, top))
	return out

## Una fila: {"id", "name", "owner", "species", "world", "world_name", "world_line", "colour", "line", "score", "pos",
## "delta" (+ subió), "me", "rival", "late", "lantern": 0..3 (brillo por franja de estrellas), "crest": índice}.
func row(id: String, prev := false) -> Dictionary:
	_ensure()
	var o := order(prev)
	var p := o.find(id) + 1
	if p <= 0:
		return {}
	return _row(id, p, prev, float((prev_scores if prev else scores)[o[0]]))

func _row(id: String, p: int, prev: bool, top: float) -> Dictionary:
	var s := shop(id)
	var w := world_of(id, committed - (1 if prev else 0))
	var wi: Dictionary = WORLDS.get(w, {})
	var sc := float((prev_scores if prev else scores).get(id, 0.0))
	var k := sc / maxf(1.0, top)
	var lantern := 3 if k >= 0.75 else (2 if k >= 0.5 else (1 if k >= 0.25 else 0))
	var pp: Dictionary = prev_pos if not prev else {}
	return {"id": id, "name": String(s.get("name", id)), "owner": String(s.get("owner", "")),
		"species": String(s.get("species", "")), "world": w, "world_name": String(wi.get("name", w)),
		"world_line": String(wi.get("line", "")), "colour": String(wi.get("colour", "c8a060")),
		"line": String(s.get("line", "")), "score": int(round(sc)), "pos": p,
		"delta": int(pp.get(id, p)) - p, "me": id == ME, "rival": id == RIVAL,
		"late": id == ME and _late > 0, "lantern": lantern, "crest": crest_index(id)}

func shop(id: String) -> Dictionary:
	for s in SHOPS:
		if String(s["id"]) == id:
			return s
	return {}

func shop_name(id: String) -> String:
	return String(shop(id).get("name", id))

func crest_index(id: String) -> int:
	for i in SHOPS.size():
		if String(SHOPS[i]["id"]) == id:
			return i
	return SHOPS.size() - 1

## El mundo de una tienda esa noche (Shine Again se muda a Saffra la noche 3).
func world_of(id: String, night := -1) -> String:
	var n := committed if night < 0 else night
	if id == RIVAL and n >= RIVAL_MOVE_NIGHT:
		return "saffra"
	return String(shop(id).get("world", ""))

func world_name(w: String) -> String:
	return String(WORLDS.get(w, {}).get("name", w))

func position(id := ME) -> int:
	_ensure()
	return order().find(id) + 1

func score(id := ME) -> int:
	_ensure()
	return int(round(float(scores.get(id, 0.0))))

## La tienda de arriba: {"id", "name", "world_name", "gap"} ({} si Nell es la #1).
func next_above() -> Dictionary:
	_ensure()
	var o := order()
	var i := o.find(ME)
	if i <= 0:
		return {}
	var id := String(o[i - 1])
	return {"id": id, "name": shop_name(id), "world_name": world_name(world_of(id)),
		"gap": maxi(1, int(ceil(float(scores[id]) - float(scores[ME]))))}

## Las puntas del cartel: top 20, 15, 10, 5 y #1 (por el mejor puesto alcanzado).
func milestone_points() -> int:
	_ensure()
	var n := 0
	for m in MILESTONES:
		if best_pos <= int(m):
			n += 1
	return n

func milestone_line(n: int) -> String:
	return String(MILESTONE_LINES[clampi(n, 0, MILESTONE_LINES.size() - 1)])

## (P1, para S) lo que un cliente comenta del tablero al recoger lo suyo, según el puesto de Nell (y si va delante de
## Glint). "" antes de que Nell entre al top 20. S decide cuándo decirlo (p. ej. 1 de cada 4 entregas, en un blurt).
const RANK_CHATTER := {
	"top20": ["Heard you on the Drift Signal last night. Not bad!", "Top twenty, from a sand port. Who knew?"],
	"top10": ["Top ten in the Drift? From Rustwater? Lovely.", "My cousin on Brindle heard your name. Twice."],
	"top5": ["Only a few lanterns above you now. Go on, then.", "Top five! Mind you don't get posh about it."],
	"first": ["First on the Lantern Board. I knew you when.", "Number one, and still fixing my radio. Bless."],
	"glint": ["Shine Again's fuming. Best thing all week.", "Fix beats shine, I always say. Well, today I do."],
}

func chatter(seed := 0) -> String:
	_ensure()
	var p := position()
	var key := ""
	if p == 1:
		key = "first"
	elif p <= 5:
		key = "top5"
	elif p <= 10:
		key = "top10"
	elif p <= 20:
		key = "top20"
	if key == "":
		return ""
	if committed >= RIVAL_MOVE_NIGHT and score(RIVAL) < score() and seed % 3 == 2:
		key = "glint"
	var pool: Array = RANK_CHATTER[key]
	return String(pool[absi(seed) % pool.size()])

## El puesto de Nell después de una noche (0 = antes de empezar: 30).
func pos_at(night: int, id := ME) -> int:
	if night <= 0:
		return order_at_start().find(id) + 1
	for i in range(snaps.size() - 1, -1, -1):
		if int(snaps[i]["night"]) <= night:
			return int(snaps[i]["pos"].get(id, SHOPS.size()))
	return order_at_start().find(id) + 1

func order_at_start() -> Array:
	var ids: Array = []
	for s in SHOPS:
		ids.append(String(s["id"]))
	return ids

## El camino de Nell: [{"night", "pos", "stars", "score"}] (el tablero entero dibuja la línea).
func path() -> Array:
	_ensure()
	return hist.duplicate(true)

func ledger_line(move: Dictionary) -> String:
	if move.is_empty():
		return ""
	var d := int(move.get("delta", 0))
	var arrow := ("▲%d" % d) if d > 0 else (("▼%d" % -d) if d < 0 else "=")
	return "%+d ★ tonight · #%d %s" % [int(move.get("stars", 0)), int(move.get("pos", 30)), arrow]

## El desglose de esta noche bajo la fila de Nell: "Tonight +51 ★ · repairs 22 · sales 13 · events 8 · fittings 6 · lost −1".
func breakdown(move: Dictionary) -> String:
	if move.is_empty():
		return ""
	var p: Dictionary = move.get("parts", {})
	var bits: Array = ["Tonight %+d ★" % int(move.get("stars", 0))]
	for k in [["repairs", "repairs"], ["sales", "sales"], ["events", "events"], ["appeal", "fittings"],
			["clean", "clean day"], ["bonus", "bonus"], ["finale", "Starfall x2"], ["late", "late"], ["lost", "lost"]]:
		var v := int(p.get(k[0], 0))
		if v != 0:
			# --- POLISH FIX (F10): con signo y estrella en cada parte ("repairs +10★"; "repairs 10" parecía una cantidad)
			bits.append("%s %s★" % [k[1], ("+%d" % v) if v > 0 else ("–%d" % -v)])   # ("–": "−" no está en las fuentes; web)
	return " · ".join(bits)

# ------------------------------------------------------------------ el Lantern Report (§3.9)

func report_edition(night := -1) -> int:
	var d := Game.day if night < 0 else night
	return maxi(1, d / REPORT_EVERY)

func report_due() -> bool:
	_ensure()
	var d := Game.day
	if d in reports_read:
		return false
	if d <= LAST_DAY - 1:
		return d % REPORT_EVERY == 0
	return d > LAST_DAY and (d - (LAST_DAY - 1)) % REPORT_EVERY == 0

func mark_report_read() -> void:
	_ensure()
	if not (Game.day in reports_read):
		reports_read.append(Game.day)

## El Report de esta noche: {"edition", "night", "lines": [{"seg", "text", "note"}], "nell_line_index"}.
## seg: top | nell | news | scandal | ad | weather | signoff. note: el lápiz de Nell en el margen ("us!", "ha!").
func report(night := -1) -> Dictionary:
	_ensure()
	var d := Game.day if night < 0 else night
	var ed := report_edition(d)
	var t := table()
	var first := String(t[0]["name"])
	var lines: Array = []
	match ed:
		1:
			var climbed := pos_at(d - REPORT_EVERY) - position()
			lines = [{"seg": "top", "text": fill(REPORT1["top"], {"first": first})},
				{"seg": "nell", "text": fill(REPORT1["nell_up"] if climbed > 0 else REPORT1["nell"],
					{"n": str(climbed), "o": ord_word(position())}), "note": "us!"},
				{"seg": "news", "text": REPORT1["news"]},
				{"seg": "scandal", "text": REPORT1["scandal"], "note": "ha!"},
				{"seg": "ad", "text": REPORT1["lost_crate"] if String(_flag("crate", "")) in ["kept", "covered"] else REPORT1["ad"]},
				{"seg": "weather", "text": REPORT1["weather"]},
				{"seg": "signoff", "text": SIGNOFF}]
		2:
			var rw := rustwater_race()
			lines = [{"seg": "top", "text": fill(REPORT2["top"], {"first": first, "mover": _mover(d)})},
				{"seg": "nell", "text": fill(REPORT2["nell"], {"leader": rw["leader_name"], "gap": str(rw["gap"])}),
					"note": "us!" if String(rw["leader"]) == ME else "soon."},
				{"seg": "news", "text": fill(REPORT2["news"], {"grade": String(GRADES.get(String(_flag("grade", "")), "Noted"))})},
				{"seg": "scandal", "text": REPORT2["scandal"]},
				{"seg": "ad", "text": REPORT2["lost"]},
				{"seg": "weather", "text": REPORT2["weather"]},
				{"seg": "signoff", "text": SIGNOFF}]
		3:
			var rw3 := rustwater_race()
			var podium := String(_flag("race", "")) == "podium"
			lines = [{"seg": "top", "text": fill(REPORT3["top"], {"first": first})},
				{"seg": "nell", "text": fill(REPORT3["nell"], {"leader": rw3["leader_name"], "gap": str(rw3["gap"])}),
					"note": "us!" if String(rw3["leader"]) == ME else "next!"},   # --- POLISH FIX (F10): era "tomorrow."
				{"seg": "news", "text": fill(REPORT3["podium"], {"winner": race_winner()}) if podium else REPORT3["no_podium"],
					"note": "Digger!" if podium else ""},
				{"seg": "scandal", "text": REPORT3["scandal"], "note": "ha!"},
				{"seg": "ad", "text": REPORT3["found"] if int(_flag("cores", 0)) < 3 else REPORT3["ad"]},
				{"seg": "weather", "text": REPORT3["weather"]},
				{"seg": "signoff", "text": SIGNOFF}]
		_:
			lines = _report_pools(d, ed, first)
	return {"edition": ed, "night": d, "lines": lines, "nell_line_index": 1}

## La carrera de Rustwater: los tres faroles del puerto (Nell, Shine Again desde la noche 3, Dune Pocket).
func rustwater_race() -> Dictionary:
	var best := ""
	var second := ""
	for id in RUSTWATER:
		if id == RIVAL and committed < RIVAL_MOVE_NIGHT:
			continue
		if best == "" or float(scores[id]) > float(scores[best]):
			second = best
			best = id
		elif second == "" or float(scores[id]) > float(scores[second]):
			second = id
	var gap := int(round(float(scores[best]) - float(scores.get(second, 0.0)))) if second != "" else 0
	return {"leader": best, "leader_name": shop_name(best), "second": second, "gap": mini(999, maxi(0, gap))}

## Quién ganó el Glasspan Derby con una moto de la tienda (Season.race_result si existe; si no, Pipip).
func race_winner() -> String:
	var s := _season()
	var who := "pipip"
	if s != null and s.has_method("race_result"):
		var rr = s.call("race_result")
		if rr is Dictionary and String(rr.get("winner", "")) != "":
			who = String(rr["winner"])
	var c: Dictionary = Data.CAST.get(who, {})
	var nm := String(c.get("name", who.capitalize())) if not c.is_empty() else who
	return nm.left(12)

## La tienda que más subió en las últimas noches (sin contar a Nell).
func _mover(night: int) -> String:
	var best := ""
	var best_d := 0
	for s in SHOPS:
		var id := String(s["id"])
		if id == ME:
			continue
		var dv := pos_at(night - REPORT_EVERY, id) - position(id)
		if dv > best_d or (dv == best_d and dv > 0 and position(id) < position(best)):
			best = id
			best_d = dv
	if best == "":
		best = "couriercorner"
	return shop_name(best)

## Los Reports del modo sin fin: una línea por segmento de los pools, nunca la misma dos veces seguidas.
func _report_pools(night: int, ed: int, first: String) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|report|%d" % [seed0, ed])
	var top := table()
	var o := order()
	var others: Array = []
	for id in o:
		if id != ME and id != RIVAL and id != CHAMPION:
			others.append(id)
	var pick := func(pool: Array, seg: String) -> int:
		var last := int(_used.get(seg, -1))
		var i := r.randi() % pool.size()
		if i == last:
			i = (i + 1) % pool.size()
		_used[seg] = i
		return i
	# 1. arriba
	var l1 := ""
	if String(top[0]["id"]) == ME:
		l1 = String(POOL_TOP_ME[ed % POOL_TOP_ME.size()])
	else:
		l1 = fill(POOL_TOP[ed % POOL_TOP.size()], {"first": first})
	# 3. titular: la que más subió si subió de verdad; si no, uno del pool con una tienda al azar
	var climber := ""
	var climb := 0
	for id in others:
		var dv := pos_at(night - REPORT_EVERY, id) - position(id)
		if dv > climb:
			climber = id
			climb = dv
	var hi: int = pick.call(POOL_HEADLINES, "headline")
	if hi == 1 and climb < 2:
		hi = 0
	var hs := climber if (hi == 1 and climber != "") else String(others[r.randi() % others.size()])
	var l3 := fill(POOL_HEADLINES[hi], {"s": shop_name(hs), "o": String(shop(hs)["owner"]),
		"w": world_name(world_of(hs)), "n": str(climb)})
	# 4. escándalo: un tropiezo de verdad de las últimas noches con su línea propia, o una del pool
	var l4 := ""
	for e in news:
		if int(e["night"]) > night - REPORT_EVERY and SCANDALS_BY.has(String(e["id"])) and String(e["id"]) != RIVAL:
			l4 = String(SCANDALS_BY[String(e["id"])])
	if l4 == "":
		var own: Array = SCANDALS_BY.keys()
		if String(_flag("favour", "")) != "done":
			own.erase(RIVAL)
		if r.randf() < 0.4:
			l4 = String(SCANDALS_BY[own[r.randi() % own.size()]])
		else:
			var si: int = pick.call(POOL_SCANDALS, "scandal")
			l4 = fill(POOL_SCANDALS[si], {"s": shop_name(String(others[r.randi() % others.size()]))})
	if String(_used.get("scandal_line", "")) == l4:
		l4 = fill(POOL_SCANDALS[(int(_used.get("scandal", 0)) + 1) % POOL_SCANDALS.size()], {"s": shop_name(String(others[0]))})
	_used["scandal_line"] = l4
	# 5. anuncio
	var l5 := String(POOL_ADS[pick.call(POOL_ADS, "ad")])
	# 6. el tiempo: el anuncio del evento de mañana (Season.announce) o cielo despejado
	var l6 := WEATHER_CLEAR
	var s := _season()
	if s != null and s.has_method("announce"):
		var a := String(s.call("announce", night))
		if a != "":
			l6 = a
	return [{"seg": "top", "text": l1},
		{"seg": "nell", "text": fill(POOL_NELL, {"o": ord_word(position())}), "note": "us!"},
		{"seg": "news", "text": l3}, {"seg": "scandal", "text": l4}, {"seg": "ad", "text": l5},
		{"seg": "weather", "text": l6}, {"seg": "signoff", "text": SIGNOFF}]

# ------------------------------------------------------------------ el final, LATE, bonos

## La noche del cometa toca esta noche: en la campaña, la noche 10 (una vez); en el modo sin fin, la primera noche #1
## si la corona no se vio todavía. Esa noche no hay tablero ni Report (sin spoiler).
func ending_due() -> bool:
	_ensure()
	if _is_campaign():
		return Game.day == LAST_DAY and not _game_bool("ending_seen")
	return position() == 1 and not _game_bool("crown_seen")

## El premio por puesto: {"id": "champion"|"rising"|"rookie"|"newshop", "title", "line", "winner", "winner_name", "place"}.
func award() -> Dictionary:
	_ensure()
	var p := position()
	var id := "champion"
	if p >= 16:
		id = "newshop"
	elif p >= 6:
		id = "rookie"
	elif p >= 2:
		id = "rising"
	var top := String(order()[0])
	return {"id": id, "title": String(AWARDS[id]["title"]), "line": String(AWARDS[id]["line"]), "winner": top,
		"winner_name": shop_name(top), "place": p}

## El resumen de la temporada para la tarjeta del premio (la gala lo suma a Game.totals()).
func season_recap() -> Dictionary:
	_ensure()
	var best_stars := 0
	var best_night := 0
	for h in hist:
		if int(h["stars"]) > best_stars:
			best_stars = int(h["stars"])
			best_night = int(h["night"])
	return {"place": position(), "score": score(), "passed": SHOPS.size() - position(), "best_stars": best_stars,
		"best_night": best_night, "best_pos": best_pos, "nights": nights}

## El sello LATE en nuestra fila por 3 noches y −3 ★ una vez (en la próxima noche contada).
func mark_late() -> void:
	_ensure()
	_late = LATE_NIGHTS
	_late_pending = true

## Estrellas extra para la próxima noche (después del margen de la rival): el favor de Buff, la llave de Rook.
func add_bonus(id: String, stars: int) -> void:
	_ensure()
	_bonus[id] = int(_bonus.get(id, 0)) + stars

## Lo que pasó con el globo de cromo la noche 8: "" | "talk" | "popped" (la calle lo cuelga del techo el día 9).
func balloon_result() -> String:
	return balloon

## --from=N: cuenta N noches con estas estrellas (la tabla de S: una por día, la final ya x2).
func fast_forward(n: int, stars_per_day: Array) -> void:
	_ensure()
	for i in n:
		var st := int(stars_per_day[mini(i, stars_per_day.size() - 1)]) if not stars_per_day.is_empty() else 25
		var night := committed + 1
		var base := st / 2 if _is_finale(night) else st
		_commit(night, st, base, {})

# ------------------------------------------------------------------ guardar

func save_data() -> Dictionary:
	_ensure()
	return {"v": 1, "seed": seed0, "scores": scores.duplicate(), "prev_scores": prev_scores.duplicate(),
		"prev_pos": prev_pos.duplicate(), "committed": committed, "nights": nights, "best_pos": best_pos,
		"last_move": _last_move.duplicate(true), "bonus": _bonus.duplicate(), "late": _late,
		"late_pending": _late_pending, "reports_read": reports_read.duplicate(), "base_hist": base_hist.duplicate(),
		"hist": hist.duplicate(true), "snaps": snaps.duplicate(true), "news": news.duplicate(true), "balloon": balloon,
		"used": _used.duplicate()}

func load_data(d) -> void:
	_ensure()
	if not (d is Dictionary) or not d.has("scores"):
		return
	_reset_scores()
	seed0 = int(d.get("seed", seed0))
	for key in ["scores", "prev_scores"]:
		var src = d.get(key, {})
		if src is Dictionary:
			var dst: Dictionary = scores if key == "scores" else prev_scores
			for id in src:
				if dst.has(String(id)):
					dst[String(id)] = float(src[id])
	if not d.has("prev_scores"):
		prev_scores = scores.duplicate()
	prev_pos = {}
	var pp = d.get("prev_pos", {})
	if pp is Dictionary:
		for id in pp:
			prev_pos[String(id)] = int(pp[id])
	committed = int(d.get("committed", 0))
	nights = int(d.get("nights", 0))
	_last_move = _ints(d.get("last_move", {}))
	for k in ["passed", "passed_by"]:
		if _last_move.has(k) and _last_move[k] is Array:
			_last_move[k] = (_last_move[k] as Array).map(func(x): return String(x))
	_bonus = {}
	var bn = d.get("bonus", {})
	if bn is Dictionary:
		for id in bn:
			_bonus[String(id)] = int(bn[id])
	_late = int(d.get("late", 0))
	_late_pending = bool(d.get("late_pending", false))
	best_pos = int(d.get("best_pos", position()))
	reports_read = []
	for x in d.get("reports_read", []):
		reports_read.append(int(x))
	base_hist = []
	for x in d.get("base_hist", []):
		base_hist.append(int(x))
	hist = []
	for h in d.get("hist", []):
		if h is Dictionary:
			hist.append({"night": int(h.get("night", 0)), "pos": int(h.get("pos", 30)), "stars": int(h.get("stars", 0)),
				"score": int(h.get("score", 0))})
	snaps = []
	for s in d.get("snaps", []):
		if s is Dictionary and s.get("pos") is Dictionary:
			var pos := {}
			for id in s["pos"]:
				pos[String(id)] = int(s["pos"][id])
			snaps.append({"night": int(s.get("night", 0)), "pos": pos})
	news = []
	for e in d.get("news", []):
		if e is Dictionary and e.has("id"):
			news.append({"night": int(e.get("night", 0)), "id": String(e["id"]), "kind": String(e.get("kind", "stumble"))})
	balloon = String(d.get("balloon", ""))
	_used = {}
	var u = d.get("used", {})
	if u is Dictionary:
		for k in u:
			_used[String(k)] = u[k] if u[k] is String else int(u[k])

## JSON devuelve los números como float: los enteros vuelven a ser int (también dentro de listas y diccionarios).
func _ints(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x): return _ints(x))
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	return v

## Una partida del prototipo (v2): cada día guardado = repairs + sales + stars + 2 x sales − walkouts − min(missed, 2).
func rebuild_from_history(history: Array) -> void:
	_ensure()
	_reset_scores()
	for s in history:
		if not (s is Dictionary):
			continue
		var st := int(s.get("repairs", 0)) + int(s.get("sales", 0)) + int(s.get("stars", 0)) + 2 * int(s.get("sales", 0)) \
			- int(s.get("walkouts", 0)) - mini(int(s.get("missed", 0)), 2)
		_commit(int(s.get("day", nights + 1)), st, st, {})

## ranksim: simula `days` noches desde cero sin tocar la partida. per_day.call(noche) -> int (las estrellas de Nell) o
## {"total", "base"} (base = sin eventos ni el x2). Devuelve una fila por noche: {"night", "pos", "score", "stars",
## "rival_gap" (+ la rival va delante), "rival_pos", "champ_gap", "champ_pos", "top", "milestone", "balloon"}.
func simulate(days: int, per_day: Callable, seed := -1) -> Array:
	_ensure()
	var keep := save_data()
	if seed >= 0:
		seed0 = seed
	_reset_scores()
	var out: Array = []
	for i in days:
		var v = per_day.call(i + 1)
		var tot := int(v["total"]) if v is Dictionary else int(v)
		var base := int(v.get("base", tot)) if v is Dictionary else tot
		var mv := _commit(i + 1, tot, base, {})
		var o := order()
		out.append({"night": i + 1, "pos": int(mv["pos"]), "score": score(), "stars": int(mv["stars"]),
			"rival_gap": int(round(float(scores[RIVAL]) - float(scores[ME]))), "rival_pos": o.find(RIVAL) + 1,
			"champ_gap": int(round(float(scores[CHAMPION]) - float(scores[ME]))), "champ_pos": o.find(CHAMPION) + 1,
			"top": String(o[0]), "milestone": milestone_points(), "balloon": String(mv.get("balloon", "")),
			"scores": scores.duplicate()})
	load_data(keep)
	return out

# ------------------------------------------------------------------ ayudas de texto

## «Twenty-seventh»: el puesto en palabras (1-30; después «31st»).
func ord_word(n: int) -> String:
	if n >= 0 and n < ORD.size():
		return String(ORD[n])
	return UIKit.ordinal(n)

## Rellena {clave} con los valores.
func fill(t: String, vals: Dictionary) -> String:
	var s := t
	for k in vals:
		s = s.replace("{%s}" % k, String(vals[k]))
	return s
