extends Node
## Datos del juego (autoload "Data"): las reglas fijas del prototipo, los lugares, las especies, el elenco con sus
## frases, la agenda de los 3 días y los textos de la historia.
## --- SS CORE: dueño de este archivo. Los datos del banco de reparación y del regateo (cosas, piezas, fallas,
## síntomas, precios de las piezas, reglas de cada especie) están en scripts/bench_data.gd (BENCH).
## Ids internos en inglés y en minúsculas; los textos que se ven, en inglés corto y cálido (sin nombres ni palabras
## de la saga de las estrellas: "bot", nunca la otra palabra; ver la lista del brief).

const GAME_TITLE := "Secondhand Stars"
const SHOP_NAME := "The Secondhand Star"
const PORT_NAME := "Rustwater"
const PLANET_NAME := "Saffra"

# --- el prototipo: 3 días, pagar la cuota del puerto (dock dues) al final del día 3 --------------------------------
const DAYS := 3
const DUES_GOAL := 300
const DAY_SECONDS := 300.0        # el día abierto dura 5 minutos reales
const OPEN_MIN := 540             # 9:00 AM
const CLOSE_MIN := 1080           # 6:00 PM
const MAX_LINE := 4               # la fila dentro de la tienda
const START_CREDITS := 50        # (--- SS MERGE: balance, era 40)
const START_PARTS := {"cell": 2, "speaker": 1, "servo": 1}   # (balance: INTEGRATE)
## Lo que ya estaba en el estante el primer día (algo para vender a la primera clienta que compra).
const START_SHELF := [{"item": "radio", "stars": 2}]

# --- la paciencia (segundos a factor 1.0; cada especie la multiplica: SPECIES.patience) ---------------------------
const LINE_PATIENCE := 80.0       # en la fila
const COUNTER_PATIENCE := 45.0    # en el mostrador, hasta que Nell le habla
const WORK_DRAIN := 0.22          # mientras su cosa está en el banco se cansa mucho más despacio...
const WORK_FLOOR := 0.12          # ...y nunca se va (espera su cosa)
const TEA_BOOST := 0.5            # el té de Kettle (una vez al día): +50 % de paciencia a la fila
const GRUMPY_BELOW := 0.3         # llega al mostrador con menos de esto: de mal humor (sin propina)

# --- la mañana, la reputación y el cartel ------------------------------------------------------------------------
const PODS_PER_DAY := 2           # cápsulas en el puesto de Raker cada mañana
## Lo que suma o resta a la reputación cada cosa (estrellas 0..3 de una reparación).
const REP_STARS := [-1, 0, 1, 2]
const REP_SALE := 1
const REP_WALKOUT := -1
const REP_GAVE_UP := -1
## Un día es "bueno" si la reputación sube al menos esto: el cartel de la estrella enciende una punta.
const GOOD_DAY_REP := 3
const SIGN_POINTS := 5            # puntas del cartel (assets/props/star_sign_<n>.png, n = 0..5)
const SPEED_TIP_SECS := 45.0      # Zib deja propina si su arreglo (desde que lo acepta) tarda menos que esto
const SPEED_TIP := 4

const PLACES := {
	"shop": {"name": "The Secondhand Star", "about": "Nell's repair shop: counter, bench, parts drawer, shelf."},
	"street": {"name": "Starfall Market", "about": "The street outside at dawn: the pod stall, the parts stall."},
	"port": {"name": "Rustwater", "about": "A dusty spaceport on the desert planet Saffra."},
}

## Especies (la paciencia es un factor: 1.0 = normal).
const SPECIES := {
	"human": {"name": "Human", "patience": 1.0},
	"bot": {"name": "Bot", "patience": 1.2},
	"hornback": {"name": "Hornback", "patience": 1.3},
	"quill": {"name": "Quill", "patience": 0.7},
	"glimmerfolk": {"name": "Glimmerfolk", "patience": 1.4},
	"burrower": {"name": "Burrower", "patience": 1.0},
	"duneraker": {"name": "Dune Raker", "patience": 1.0},
}

## El elenco: una hoja de 64x96 cada uno en assets/chars/<id>_idle.png (2 cuadros) y <id>_walk.png (4 cuadros).
## role: player | sidekick | customer | market. brings: lo que trae roto; buys: lo que compra del estante.
## patience: factor propio (además del de la especie; Rook: su nave sale pronto).
const CAST := {
	"nell": {"name": "Nell", "species": "human", "role": "player",
		"about": "A young mechanic. Buys junk at dawn, fixes it, sells it secondhand."},
	"kettle": {"name": "Kettle", "species": "bot", "role": "sidekick",
		"about": "A knee-high tea-kettle bot. Whistles when Nell's guess is right; pours tea once a day."},
	"gorrum": {"name": "Gorrum", "species": "hornback", "role": "customer", "brings": ["thruster", "radio"], "buys": ["thruster", "radio"],
		"about": "A huge horned trader in a dusty poncho. Slow, stubborn. Never says yes to the first price."},
	"zib": {"name": "Zib", "species": "quill", "role": "customer", "brings": ["helperbot", "radio"], "buys": ["radio", "helperbot"],
		"about": "A lanky four-armed courier with a quill crest and goggles. Impatient; tips for speed."},
	"oona": {"name": "Mother Oona", "species": "glimmerfolk", "role": "customer", "brings": ["radio", "helperbot"], "buys": ["radio", "helperbot"],
		"about": "A jelly-dome head full of glowing thoughts, elegant robes. Patient; offers a part instead of credits."},
	"pipip": {"name": "Pipip", "species": "burrower", "role": "customer", "brings": ["helperbot", "thruster"], "buys": ["helperbot", "thruster"],
		"about": "A small mole-like miner with a hard-hat lamp and big goggles. Shy; pays in small coins."},
	"rook": {"name": "Rook Varga", "species": "human", "role": "customer", "brings": ["thruster", "radio"], "buys": ["thruster", "radio"],
		"patience": 0.85, "about": "A weathered pilot with ship keys. His patience runs on his ship's departure time."},
	"clatter": {"name": "Clatter", "species": "bot", "role": "customer", "brings": ["helperbot"], "buys": [],
		"about": "An old, tall service bot with a lampshade head and a squeaky knee. Walks in to get himself fixed; pays from his own savings."},
	"raker": {"name": "Raker", "species": "duneraker", "role": "market",
		"about": "A friendly salamander-like scavenger with a wide hat, a tool apron and a huge pack of junk. Sells sealed pods."},
	"mags": {"name": "Mags", "species": "human", "role": "market",
		"about": "A stocky parts seller with a welding visor pushed up. Fixed prices."},
}
const CUSTOMERS := ["gorrum", "zib", "oona", "pipip", "rook", "clatter"]
const MARKET_CAST := ["raker", "mags"]
## Todos los ids con hoja de personaje (el arte de ART llega con estos nombres).
const CHAR_IDS := ["nell", "kettle", "gorrum", "zib", "oona", "pipip", "rook", "clatter", "raker", "mags"]

## Lo que dice cada cliente. bring: al traer algo roto (por familia); buy: al pedir algo del estante;
## thanks: al recibir la reparación según las estrellas (0..3); failed: si Nell no pudo; angry: se cansó de esperar;
## decline: Nell no puede atenderlo; sold / nodeal / none: la venta (hecha, sin trato, no hay nada en el estante);
## full: la fila está llena; home: dieron las 6 y se va a casa.
const LINES := {
	"gorrum": {
		"bring": {"radio": "My radio is sick. Fix it. Not fast. Right.",
			"thruster": "Thruster. My hoverbike sulks. Gorrum does not like sulking."},
		"buy": "Gorrum needs a thruster. Or a radio. A good one. Show me.",   # --- SS SHIP: compra de dos familias (lo dice)
		"thanks": ["Hrm. It works. A little.", "It works. Mostly. Hrm.", "It works. Gorrum is satisfied.",
			"Hrm! Good work. Gorrum will tell the herd."],
		"failed": "Still broken. Gorrum is not angry. Gorrum is disappointed.",
		"angry": "Too slow. Gorrum goes.",
		"decline": "Hrm. Another day.",
		"sold": "Fair. Gorrum is surprised.",
		"nodeal": "Too much. Gorrum keeps his credits.",
		"none": "Nothing? Hrm. Tomorrow.",
		"full": "Too many people. Gorrum hates crowds.",
		"home": "Closed? Hrm. Tomorrow.",
	},
	"zib": {
		"bring": {"helperbot": "Quick-quick! My helper's broken and I've got six drops before noon!",
			"radio": "Radio's busted! I need the dock news, hurry-hurry!"},
		"buy": "Need something that works! Radio, helper, anything! Fast!",
		"thanks": ["Uh. Okay. Bye!", "Eh, it'll do. Bye-bye!", "Good-good! Gotta fly!", "Zoom! Here's a tip for speed!"],
		"failed": "Still broken?! No time, gotta go!",
		"angry": "No time, no time! Bye!",
		"decline": "Okay-okay, somewhere else!",
		"sold": "Deal-deal! Gone!",
		"nodeal": "Nope! Too pricey!",
		"none": "None? Okay, bye!",
		"full": "A line? No time for lines!",
		"home": "Closed?! Tomorrow, first thing!",
	},
	"oona": {
		"bring": {"radio": "No hurry, little star. My radio only remembers one song.",
			"helperbot": "My little helper has forgotten itself. It happens to us all."},
		"buy": "I would like a radio, dear, or a little helper bot. Something with a warm voice.",   # --- SS SHIP
		"thanks": ["Oh. Well, it tried its best. So did you.", "It hums a little crooked. Thank you, dear.",
			"Lovely work, little star.", "Wonderful. My thoughts are glowing for you."],
		"failed": "Some things stay broken a while. I understand.",
		"angry": "Even patience has a bottom, dear.",
		"decline": "Another day, then. The sky is in no hurry.",
		"sold": "A fair trade between friends.",
		"nodeal": "Let us keep our friendship, and our credits.",
		"none": "Nothing today? I will come back after the next starfall.",
		"full": "So many visitors. I will come back later.",
		"home": "Closed already? Good night, little star.",
	},
	"pipip": {
		"bring": {"helperbot": "Um. Hello. My helper is... not helping. Sorry.",
			"thruster": "My drill bike makes a sad noise. Is that bad? Sorry."},
		"buy": "Do you... maybe... have a helper bot? Or a thruster? A small one?",   # --- SS SHIP
		"thanks": ["Oh. It's... fine! Thank you.", "Thank you! Here. Small coins. Sorry.",
			"Thank you! It's all in small coins, sorry.", "Oh! Oh wow! Thank you! Sorry about the coins."],
		"failed": "Oh. That's okay. It was old.",
		"angry": "I'll... come back. Maybe.",
		"decline": "Oh. Okay. Sorry for asking.",
		"sold": "Thank you! I counted the coins twice.",
		"nodeal": "Oh, that's... too many coins.",
		"none": "Oh. That's okay!",
		"full": "So many people... I'll come back.",
		"home": "Oh, you're closing. Sorry!",
	},
	"rook": {
		"bring": {"thruster": "Thruster coughs like my uncle. Ship leaves at two. No pressure.",
			"radio": "Radio's dead. I like to know who's following me."},
		"buy": "Need a thruster that won't quit over the dunes. Or a radio for the trip. Got one?",   # --- SS SHIP
		"thanks": ["If I crash, I'm haunting you.", "Good enough to fly. Thanks, kid.", "Smooth. Thanks, Nell.",
			"Purrs like new. You're wasted on this rock, Nell."],
		"failed": "Still coughing. I'll hum along.",
		"angry": "Ship won't wait. Neither can I.",
		"decline": "Fair. I'll trust the tape.",
		"sold": "Pleasure doing business.",
		"nodeal": "Too rich for me. Today.",
		"none": "Nothing? I'll limp home.",
		"full": "Busy, huh? I'll come back.",
		"home": "Closed. Story of my life.",
	},
	"clatter": {
		"bring": {"helperbot": "Greetings. I would like to be repaired, please. Me. I have savings."},   # --- SS SHIP: llega por la tarde ("Good morning" a las 2 PM),
		"buy": "I am only browsing. With my eyes. I have two.",
		"thanks": ["A small squeak remains. I will name it.", "Better. My savings and I thank you.",
			"Much better. I shall squeak no more.", "Splendid. I feel twenty years younger. Nineteen."],
		"failed": "Still squeaking. It is my song now.",
		"angry": "I will return when I have more minutes.",
		"decline": "Understood. I will oil myself and hope.",
		"sold": "A fine purchase. My savings weep.",
		"nodeal": "My savings say no.",
		"none": "Then I will browse the air.",
		"full": "A line. I will come back. Slowly.",
		"home": "Closed. I will wait outside until morning. Joking.",
	},
}

## --- SS MERGE: Clatter no trae nada: entra a que lo arreglen A ÉL (el brief) y paga de sus ahorros. Sus piezas son las
## de la familia "helperbot" del banco (servo = la rodilla que chirría, chip = la memoria, lens = el ojo de la lámpara,
## cell = la energía), pero el banco, el mostrador y la entrega dicen que es él: su nombre, sus síntomas en primera
## persona y lo que dice al probarlo (BenchData.BOT_TALK_SELF). Sin cosa en el mostrador ni en el banco 3D.
const SELF_REPAIR := {
	"clatter": {"label": "Clatter", "sub": "fixing himself",
		"symptoms": {"servo": "My knee squeaks, and I walk in circles.",
			"chip": "I forgot my own name. It starts with a C?",
			"lens": "My lamp eye is foggy. I said hello to a coat rack.",
			"cell": "I keep falling asleep in the middle of a sen..."}},
}

## El síntoma en primera persona de quien viene a arreglarse a sí mismo ("" si no es su caso).
func self_symptom(who: String, fault: String) -> String:
	return String(SELF_REPAIR.get(who, {}).get("symptoms", {}).get(fault, ""))

func is_self_repair(who: String) -> bool:
	return SELF_REPAIR.has(who)
# --- end SS MERGE

## La mañana: el puesto de cápsulas (Raker), el de piezas (Mags) y Kettle.
const MARKET_LINES := {
	"raker_hello": "Pods! Fresh from last night's starfall, still warm!",
	"raker_pick": "Two pods today. Heavy ones hold more. Rattlers hide surprises!",
	"raker_one": "One pod left. Lucky last!",
	"raker_sold_out": "All gone! The sky drops more tonight.",
	"raker_broke": "No credits, no pods, friend!",
	"raker_after": "Happy cracking!",
	"raker_nodeal": "Your loss! It's a good one.",
	"mags_hello": "Fixed prices, Nell. Haggle with the sand.",
	"mags_bought": "Good pick.",
	"mags_broke": "Credits first, sunshine.",
}
const KETTLE_TALK := [
	"Kettle whistles a happy little tune.",
	"Kettle's lid pops up. It wants to help.",
	"Kettle puffs a ring of steam. Showing off.",
	"Kettle taps your boot. Time to work.",
]
const KETTLE_TEA := "Kettle pours tea for everyone in line."
const KETTLE_TEA_DONE := "Tea's done for today. Kettle needs a nap."

## La introducción (3 frases sobre el anillo de restos y la lluvia de chatarra).
const INTRO := [
	"Every night, the old shipyard in the sky drops a little more of itself on Saffra.",
	"At dawn, scavengers sell what fell. Nell fixes it and sells it secondhand.",
	"Rustwater's landlord wants 300 credits of dock dues in three days. No pressure.",
]

## Consejos del primer día (cada uno sale una sola vez por partida). {key} = la tecla de interactuar del aparato.
const TIPS := {
	"walk": "Walk with {walk}. Buy a pod from Raker, then {key} Open shop at your door.",
	"pods": "Heavy pods hold more parts. Rattling ones often hide a broken item.",
	"open": "Your first customer! Meet them at the counter.",
	"counter": "Repair it: Nell fixes it at the bench while they wait.",
	"clock": "The clock is running: we close at 6 PM.",
	"line": "When an hourglass runs out, that customer leaves.",
	"junk": "Broken finds go to the bench: refurbish them, then sell them.",
	"tea": "Long line? Kettle pours tea once a day: {key} Tea.",
	"shelf": "Buyers want a working item from your shelf. Haggle the price.",
}

## La agenda de los 3 días: quién llega, a qué segundo del día abierto (0..DAY_SECONDS), qué trae (repair: item y
## fault) o qué quiere comprar (buy: wants). Crece de 6 a 9 clientes; el día 1 es tranquilo (el primero es el tutorial:
## el reloj espera hasta que se va). Los días 2 y 3 tienen una "hora punta" (llegan 3-4 casi juntos: la fila crece, la
## paciencia aprieta y el té de Kettle sirve de verdad).
const SCHEDULE := [
	[
		{"t": 3.0, "who": "gorrum", "kind": "repair", "item": "radio", "fault": "speaker"},
		{"t": 55.0, "who": "zib", "kind": "buy", "wants": ["radio", "helperbot"]},
		{"t": 100.0, "who": "pipip", "kind": "repair", "item": "helperbot", "fault": "cell"},
		{"t": 150.0, "who": "clatter", "kind": "repair", "item": "helperbot", "fault": "servo"},
		{"t": 162.0, "who": "rook", "kind": "repair", "item": "thruster", "fault": "nozzle"},
		{"t": 228.0, "who": "oona", "kind": "repair", "item": "radio", "fault": "tuner"},
	],
	[
		{"t": 4.0, "who": "zib", "kind": "repair", "item": "helperbot", "fault": "lens"},
		{"t": 36.0, "who": "gorrum", "kind": "buy", "wants": ["thruster", "radio"]},
		{"t": 78.0, "who": "rook", "kind": "repair", "item": "thruster", "fault": "coil"},
		{"t": 86.0, "who": "oona", "kind": "buy", "wants": ["radio", "helperbot"]},
		{"t": 95.0, "who": "pipip", "kind": "repair", "item": "thruster", "fault": "fan"},
		{"t": 165.0, "who": "clatter", "kind": "repair", "item": "helperbot", "fault": "chip"},
		{"t": 200.0, "who": "zib", "kind": "buy", "wants": ["helperbot", "radio"]},
		{"t": 236.0, "who": "gorrum", "kind": "repair", "item": "radio", "fault": "chip"},
	],
	[
		{"t": 4.0, "who": "rook", "kind": "repair", "item": "radio", "fault": "cell"},
		{"t": 24.0, "who": "pipip", "kind": "buy", "wants": ["helperbot", "thruster"]},
		{"t": 62.0, "who": "gorrum", "kind": "repair", "item": "thruster", "fault": "cell"},
		{"t": 70.0, "who": "zib", "kind": "repair", "item": "radio", "fault": "tuner"},
		{"t": 78.0, "who": "oona", "kind": "repair", "item": "helperbot", "fault": "chip"},
		{"t": 88.0, "who": "clatter", "kind": "repair", "item": "helperbot", "fault": "lens"},
		{"t": 170.0, "who": "rook", "kind": "buy", "wants": ["thruster", "radio"]},
		{"t": 200.0, "who": "zib", "kind": "repair", "item": "helperbot", "fault": "servo"},
		{"t": 238.0, "who": "oona", "kind": "buy", "wants": ["radio", "helperbot"]},
	],
]

## Las dos cápsulas del primer día (las de los días 2 y 3 se sortean con la semilla de la partida): una pesada que
## traquetea (trae una cosa rota para reparar y vender) y una liviana y quieta (solo piezas).
const DAY1_PODS := [
	{"id": "pod-101", "weight": 3, "rattle": 2, "price": 26,
		"contents": [{"part": "lens"}, {"part": "nozzle"}, {"item": "thruster", "fault": "fan"}]},
	{"id": "pod-102", "weight": 1, "rattle": 0, "price": 16,
		"contents": [{"part": "cell"}, {"part": "tuner"}]},
]

# ------------------------------------------------------------------ ayudas

func char_name(id: String) -> String:
	return CAST.get(id, {}).get("name", id.capitalize())

func species_of(id: String) -> String:
	return CAST.get(id, {}).get("species", "human")

## Factor de paciencia de un personaje (especie x el suyo propio).
func patience_of(id: String) -> float:
	var sp: Dictionary = SPECIES.get(species_of(id), {})
	return float(sp.get("patience", 1.0)) * float(CAST.get(id, {}).get("patience", 1.0))

## Una frase de un cliente (LINES[who][key]); fallback genérico si no la tiene.
func line(who: String, key: String, extra = null) -> String:
	var d: Dictionary = LINES.get(who, {})
	var v = d.get(key, null)
	if v is Dictionary:
		v = v.get(str(extra), v.values()[0] if not v.is_empty() else "")
	elif v is Array:
		v = v[clampi(int(extra if extra != null else 0), 0, v.size() - 1)] if not v.is_empty() else ""
	if v == null or str(v) == "":
		return {"bring": "Can you fix this?", "buy": "Got anything that works?", "thanks": "Thanks!",
			"failed": "Oh well.", "angry": "Too slow!", "decline": "Another time.", "sold": "Deal.",
			"nodeal": "No deal.", "none": "Nothing? Okay.", "full": "Too busy.", "home": "Closed? Tomorrow."}.get(key, "...")
	return str(v)

## La agenda de un día (1..DAYS): copia, ordenada por hora de llegada.
func schedule_for(day: int) -> Array:
	var i := clampi(day - 1, 0, SCHEDULE.size() - 1)
	var out: Array = SCHEDULE[i].duplicate(true)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out

## Un consejo con las teclas del aparato en uso.
func tip(key: String, interact := "E", walk := "A/D") -> String:
	return String(TIPS.get(key, "")).replace("{key}", "[%s]" % interact).replace("{walk}", walk)
