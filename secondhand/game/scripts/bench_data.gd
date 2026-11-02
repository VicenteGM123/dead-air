extends Node
## Datos del banco de reparación, del regateo y de las cápsulas (autoload "BenchData").
## --- SS BENCH: completo (la semilla dejó el esqueleto con la misma API). Todo el texto que se ve está en inglés,
## corto y cálido. Lo usan scripts/ui/bench_ui.gd (BenchUI), haggle_ui.gd (HaggleUI) y pod_ui.gd (PodUI); CORE lo usa
## para armar los trabajos (make_job / random_job), los tratos (make_deal), la paga (repair_pay), los precios
## (sale_price, part_price) y las cápsulas (roll_pod). Los números son un punto de partida: el balance final es de
## INTEGRATE (precios, paga, SCORE, las reglas de cada especie).
##
## Formatos del contrato (SS_BRIEF §3):
##   trabajo (BenchUI.open):  {"item", "fault", "symptom", "extras": [], "customer"}   -> make_job()
##                            (opcional: "tutorial": true = Kettle explica cada paso)
##   trato (HaggleUI.open):   {"mode": "buy" | "sell", "what", "species", "base", "customer", "name"} -> make_deal()
##                            (opcionales, por make_deal(..., extra): "item" e "stars" al vender una cosa del estante,
##                             "pod" (la cápsula de roll_pod) al comprar una: se ven su peso y su traqueteo)
##   cápsula (PodUI.open):    {"id", "weight": 1-3, "rattle": 0-2, "price", "contents": [...]}        -> roll_pod()
##   contenido de cápsula:    [{"part": "cell"}, {"item": "radio", "fault": "tuner"}, ...]
## --- SS2 BENCH: dos familias nuevas (Song box "jukebox" con TAP, Star compass "navbox" con LISTEN), 4 piezas nuevas
## (drum, coingate, gyro, needle), pistas por familia (TOOL_CLUES_BY_ITEM / WAVES_BY_ITEM), el efecto al probarla por
## familia (ITEMS[item].power_fx), las cápsulas de la temporada (roll_pod_for: wreck / bigfall / charity, el núcleo de
## lámpara {"core": true}), las reglas de regateo por personaje (haggle_rules_for: CAST[who].haggle, luego la especie;
## las especies nuevas viven en scripts/cast_data.gd y se mezclan aquí en _init) y el precio del cajón "as-is" de Mags
## (asis_price). Los datos de los personajes nuevos (líneas, acertijos, giros) están en scripts/cast_data.gd.

## Las tres familias. slots: las 4 piezas que se ven con la carcasa abierta (en este orden: s1..s4, como el
## manifest.json de ART; los números 1-4 pintados junto a cada zócalo son las teclas 1-4).
##   best_tool: la herramienta que da la pista CLARA (las otras dos dejan dos candidatos)
##   pads: los puntos a soldar (3-5); zone: el ancho de la zona verde del test (fracción del recorrido);
##   sweep: recorridos por segundo de la aguja del test; power: lo que pasa al encenderla (el test bien hecho)
const ITEMS := {
	"radio": {"name": "Street radio", "slots": ["speaker", "tuner", "cell", "chip"], "best_tool": "listen",
		"repair_pay": 13, "sale_base": 34, "pads": 3, "zone": 0.24, "sweep": 0.8,
		"kettle_tip": "Radios tell you by ear. Try LISTEN.",
		"power": "It plays! An old desert love song.", "power_fx": "notes"},
	"helperbot": {"name": "Pocket helper bot", "slots": ["servo", "chip", "lens", "cell"], "best_tool": "tap",
		"talks": true, "repair_pay": 15, "sale_base": 38, "pads": 4, "zone": 0.21, "sweep": 0.92,
		"kettle_tip": "Little bots rattle where it hurts. TAP it.",
		"power": "It sits up and beeps hello.", "power_fx": ""},
	"thruster": {"name": "Hoverbike thruster", "slots": ["coil", "nozzle", "fan", "cell"], "best_tool": "scan",
		"repair_pay": 17, "sale_base": 42, "pads": 5, "zone": 0.18, "sweep": 1.05,
		"kettle_tip": "Thrusters run hot. SCAN for the heat.",
		"power": "Whoomph! A clean blue flame.", "power_fx": "flame"},
	# --- SS2 BENCH: la rocola del Slow Orbit (TAP: un buen golpe) y la brújula de bolsillo de los pilotos (LISTEN)
	"jukebox": {"name": "Song box", "slots": ["drum", "needle", "speaker", "coingate"], "best_tool": "tap",
		"repair_pay": 19, "sale_base": 48, "pads": 4, "zone": 0.20, "sweep": 0.95,
		"kettle_tip": "Every song box needs a good thump. TAP it.",
		"power": "Clunk-whirr... and the Slow Orbit's favourite song fills the shop.", "power_fx": "lights"},
	"navbox": {"name": "Star compass", "slots": ["gyro", "needle", "lens", "chip"], "best_tool": "listen",
		"repair_pay": 22, "sale_base": 55, "pads": 5, "zone": 0.17, "sweep": 1.1,
		"kettle_tip": "A good compass sings one steady note. LISTEN.",
		"power": "The needle swings, settles... and points at the stars.", "power_fx": "stars"},
	# --- end SS2 BENCH
}
const ITEM_ORDER := ["radio", "helperbot", "thruster", "jukebox", "navbox"]   # --- SS2 BENCH: + jukebox, navbox

## Las 9 piezas (precio fijo en el puesto de Mags).
const PARTS := {
	"speaker": {"name": "Speaker", "price": 5},
	"tuner": {"name": "Tuner", "price": 6},
	"cell": {"name": "Power cell", "price": 4},
	"chip": {"name": "Logic chip", "price": 7},
	"servo": {"name": "Servo", "price": 6},
	"lens": {"name": "Lens", "price": 5},
	"coil": {"name": "Heat coil", "price": 7},
	"nozzle": {"name": "Nozzle", "price": 6},
	"fan": {"name": "Fan", "price": 5},
	# --- SS2 BENCH: las piezas de las familias nuevas (needle sirve a las dos)
	"drum": {"name": "Song drum", "price": 6},
	"coingate": {"name": "Coin gate", "price": 5},
	"gyro": {"name": "Gyro", "price": 8},
	"needle": {"name": "Needle", "price": 6},
	# --- end SS2 BENCH
}
const PART_ORDER := ["speaker", "tuner", "cell", "chip", "servo", "lens", "coil", "nozzle", "fan",
	"drum", "coingate", "gyro", "needle"]   # --- SS2 BENCH: 13 piezas

## Las fallas: cosa -> pieza rota -> lo que dice el cliente (el síntoma de la nota).
const FAULTS := {
	"radio": {"speaker": "It crackles and hisses.", "cell": "No sound at all.", "tuner": "Only plays one station.",
		"chip": "Plays songs backwards."},
	"helperbot": {"servo": "It walks in circles.", "chip": "It forgot my name.", "lens": "It bumps into everything.",
		"cell": "It won't wake up."},
	"thruster": {"coil": "Overheats after a minute.", "nozzle": "Coughs and sputters.", "fan": "Weak thrust.",
		"cell": "Won't ignite."},
	# --- SS2 BENCH
	"jukebox": {"drum": "Plays the same three notes.", "needle": "Skips every other beat.",
		"speaker": "It sings like it has a cold.", "coingate": "Eats coins. Plays nothing."},
	"navbox": {"gyro": "Spins like a top.", "needle": "Stuck on north. There is no north out here.",
		"lens": "Can't see the stars in it.", "chip": "Always points home. I'm not from here."},
	# --- end SS2 BENCH
}

## Otras maneras de decir el mismo síntoma (la primera es la de FAULTS).
const SYMPTOM_LINES := {
	"radio": {"speaker": ["It crackles and hisses.", "Sounds like frying eggs.", "All hiss, no music."],
		"cell": ["No sound at all.", "Dead quiet. Not even a click.", "It just sits there. Silent."],
		"tuner": ["Only plays one station.", "Stuck on the weather channel.", "The dial spins. The song doesn't."],
		"chip": ["Plays songs backwards.", "Every song comes out backwards.", "It sings backwards. Creepy."]},
	"helperbot": {"servo": ["It walks in circles.", "Round and round. Never forward.", "It only turns left."],
		"chip": ["It forgot my name.", "It calls me 'Unit Seven' now.", "It doesn't know me anymore."],
		"lens": ["It bumps into everything.", "It walked into the door. Twice.", "It waved at a lamp."],
		"cell": ["It won't wake up.", "Not a beep since yesterday.", "Asleep. Won't stop sleeping."]},
	"thruster": {"coil": ["Overheats after a minute.", "Gets too hot to touch.", "Smokes after one lap."],
		"nozzle": ["Coughs and sputters.", "Goes pop-pop-pop and stalls.", "Spits sand, then stalls."],
		"fan": ["Weak thrust.", "My bike barely lifts off.", "It wheezes. No push."],
		"cell": ["Won't ignite.", "Click, click, nothing.", "Dead. Not even a spark."]},
	# --- SS2 BENCH
	"jukebox": {"drum": ["Plays the same three notes.", "The song loops forever.", "It plays a song nobody wrote."],
		"needle": ["Skips every other beat.", "The song limps.", "It hiccups through the chorus."],
		"speaker": ["It sings like it has a cold.", "All hiss, no band.", "The chorus sounds like frying eggs."],
		"coingate": ["Eats coins. Plays nothing.", "It took my last credit and burped.", "Coins go in. Silence comes out."]},
	"navbox": {"gyro": ["Spins like a top.", "Points at my boots.", "It gets dizzy. I get dizzy."],
		"needle": ["Stuck on north. There is no north out here.", "The needle droops.", "It points nowhere. Very calmly."],
		"lens": ["Can't see the stars in it.", "The star chart is all smudge.", "Foggy. Like a porthole in the rain."],
		"chip": ["Always points home. I'm not from here.", "It points at the lounge. Every time.",
			"Keeps recalculating. Never stops."]},
	# --- end SS2 BENCH
}

## Las tres herramientas del diagnóstico (key: la tecla).
const TOOLS := {
	"listen": {"name": "Listen", "key": "L", "about": "Run it and listen: a sound and a waveform."},
	"tap": {"name": "Tap", "key": "T", "about": "Tap the casing: the loose part rattles."},
	"scan": {"name": "Scan", "key": "S", "about": "Heat scan: the bad part glows."},
}
const TOOL_ORDER := ["listen", "tap", "scan"]

## La pista CLARA de cada herramienta sobre cada pieza rota (sale cuando es la mejor herramienta de la familia;
## están todas para que cualquier combinación tenga texto).
const TOOL_CLUES := {
	"listen": {"speaker": "A dry hiss from the speaker cone.", "tuner": "Same station, over and over. The tuner's stuck.",
		"cell": "Silence. Not even a hum. No power from the cell.", "chip": "The tune runs backwards. The chip is scrambled.",
		"servo": "A grinding whirr from the servo.", "lens": "A thin whine: the lens can't focus.",
		"coil": "A rising electric buzz from the coil.", "nozzle": "Pop. Pop-pop. Sputter. It's the nozzle.",
		"fan": "A tired, slow whoosh from the fan.",
		# --- SS2 BENCH
		"drum": "Three notes, again and again.", "coingate": "A coin rattles, then silence.",
		"gyro": "The gyro's note wobbles up and down.", "needle": "A tiny tick-tick: the needle's catching."},
	"tap": {"speaker": "The speaker cone buzzes when tapped.", "tuner": "The tuner dial wobbles in its socket.",
		"cell": "Clunk. The cell is loose in its clip.", "chip": "Tap... and the chip blinks, confused.",
		"servo": "The servo rattles like a loose tooth.", "lens": "The lens rattles in its ring.",
		"coil": "The coil ticks and pings. Cracked.", "nozzle": "Grit shakes out of the nozzle.",
		"fan": "A fan blade ticks against the cage.",
		# --- SS2 BENCH
		"drum": "Thump: the drum slips on its spindle.", "coingate": "Clunk. A coin is stuck in the gate.",
		"gyro": "The gyro wobbles in its ring.", "needle": "The needle arm jumps when you thump it."},
	"scan": {"speaker": "The speaker coil runs hot.", "tuner": "A hot spot on the tuner.",
		"cell": "The cell is stone cold. Empty.", "chip": "The chip glows in a strange pattern.",
		"servo": "One servo runs hot.", "lens": "The lens motor runs hot.",
		"coil": "The coil glows bright orange!", "nozzle": "A hot ring around the nozzle.",
		"fan": "The fan motor runs hot and slow.",
		# --- SS2 BENCH
		"drum": "The drum motor runs hot.", "coingate": "The coin gate's motor runs warm.",
		"gyro": "The gyro bearing runs hot.", "needle": "Nothing hot. The needle's just stuck."},
}
## --- SS2 BENCH: la misma pieza dice otra cosa en otra familia (clue() mira aquí primero).
const TOOL_CLUES_BY_ITEM := {
	"jukebox": {"tap": {"speaker": "The horn speaker buzzes when thumped."},
		"scan": {"needle": "Nothing hot. The arm's just loose."}},
	"navbox": {"listen": {"chip": "A busy chirr: the chip keeps recalculating."}},
}
## Las otras dos herramientas no ven claro: dejan dos candidatos (la falla y un "señuelo"); cada una un señuelo
## distinto, así usar las dos permite deducirla.
const TOOL_MUDDLED := {
	"listen": "Hard to place by ear.",
	"tap": "Two spots rattle a little.",
	"scan": "Two spots run warm.",
}
## LISTEN: la forma de la onda en la pantalla según la pieza rota (bench_scope.gd la dibuja).
const WAVES := {"speaker": "hiss", "tuner": "drone", "cell": "flat", "chip": "reverse", "servo": "grind",
	"lens": "whine", "coil": "buzz", "nozzle": "sputter", "fan": "slow",
	"gyro": "wobble", "needle": "tick", "drum": "loop", "coingate": "clunk"}   # --- SS2 BENCH: + 4 ondas
## --- SS2 BENCH: la onda de una pieza en una familia concreta (el chip de la brújula no canta al revés: recalcula).
const WAVES_BY_ITEM := {"navbox": {"chip": "chirr"}}
## SCAN: la pieza rota está caliente (1) o fría (-1).
const HEAT := {"cell": -1}

## Lo que dice el bot de bolsillo (habla): antes de arreglarlo (al tocarlo) y después (al probarlo). %s = el cliente.
const BOT_TALK := {
	"servo": {"before": "Forward! ...Left. Left again.", "after": "Look! Straight lines!"},
	"chip": {"before": "Hello, Unit Seven.", "after": "Hello, %s! I missed you."},
	"lens": {"before": "Is that a wall? Ow.", "after": "I can see! Nice eyebrows."},
	"cell": {"before": "...zzz...", "after": "Bzzt! Good morning!"},
	"tap": ["Ow.", "Hey!", "Ow. Ow.", "Rude."],
}

## --- SS MERGE: lo mismo cuando el bot del banco es el propio cliente (Clatter viene a arreglarse a sí mismo).
const BOT_TALK_SELF := {
	"servo": {"before": "Forward... left. Left again. Squeak.", "after": "Straight lines! And not one squeak."},
	"chip": {"before": "I am... Unit... Someone?", "after": "I am Clatter! I remember everything. Mostly."},
	"lens": {"before": "Is that a wall? Ow. Sorry, wall.", "after": "I can see! You have a smudge on your nose."},
	"cell": {"before": "...zzz... savings... zzz...", "after": "Bzzt! I am awake. Good morning, again."},
	"power": "Clatter stands up straight. No squeak.",
}
# --- end SS MERGE

## Kettle (el ayudante con forma de pava): silbido = diagnóstico correcto, "hmm" = equivocado, y consejos.
const KETTLE := {
	"whistle": ["Fweee!", "Fweeet!", "Tweee!"],
	"hmm": ["Hmm.", "Hmm... no.", "Hmmm. Not that."],
	"hello": ["What've we got?", "Ooh, a fixer-upper.", "Let's have a look."],
	"swap": "Pop a new one in.",
	"patch": "No spare? Tape and hope!",
	"solder": "Steady hand now.",
	"test": "Moment of truth...",
	"done": ["Uh-oh.", "It'll do.", "Nice work!", "Good as new!"],
	"giveup": "Another time.",
}
## Consejos de Kettle en el tutorial (job "tutorial": true), uno por paso.
const KETTLE_TUTORIAL := {
	"diagnose": "Read the note. Use a tool, then click the bad part.",
	"swap": "Grab a new one from the drawer. No spare? Patch it.",
	"solder": "Run the iron over the pads, in order.",
	"test": "Stop the needle in the green!",
}

## Las estrellas de una reparación: se parte de 3.0 y se resta; stars = cuántos umbrales de SCORE.stars se pasan.
##   wrong: cada pieza equivocada; wrong_secs: segundos que suma al tiempo; patch: sin pieza nueva;
##   cold: soldadura sin terminar a tiempo; mess: x (1 - prolijidad); test: según dónde paró la aguja.
const SCORE := {"wrong": 0.5, "wrong_secs": 2.0, "patch": 1.0, "cold": 1.0, "mess": 1.0,
	"test": {"perfect": 0.0, "good": 0.25, "ok": 0.75, "miss": 1.5}, "stars": [0.7, 1.6, 2.5]}

## Regateo por especie (las "señales" hacen del regateo una habilidad; HaggleUI las implementa).
##   ask: cuánto pide de entrada al VENDERLE a Nell (x base); offer: cuánto ofrece de entrada al COMPRARLE (x base);
##   floor / ceiling: lo mínimo que acepta al vender / lo máximo que paga al comprar (x base, +-4 % al azar);
##   temper: cuánto baja el ánimo con cada contraoferta rechazada; rounds: contraofertas posibles (2-3);
##   give: cuánto se acerca a su límite después de rechazar una (0..1);
##   tell: la señal que se ve; habit: el consejo para el jugador (etiqueta de papel); rule: la regla especial.
## --- SS2 BENCH: HAGGLE y HAGGLE_LINES son variables (se arman en _init con las filas de las especies nuevas de
## scripts/cast_data.gd: sandglass, lampwing, brushtail). Quien lee BenchData.HAGGLE[...] ve todas.
const HAGGLE_BASE := {
	"hornback": {"ask": 1.35, "offer": 0.7, "floor": 0.95, "ceiling": 1.15, "temper": 0.12, "rounds": 3, "give": 0.3,
		"tell": "Snorts and stamps when you're close to his limit.",
		"habit": "Hornbacks hate a quick yes. Always counter once.",
		"rule": "insulted_by_quick_yes"},   # aceptar a la primera lo ofende: el precio empeora
	"quill": {"ask": 1.25, "offer": 0.8, "floor": 0.9, "ceiling": 1.2, "temper": 0.25, "rounds": 2, "give": 0.5,
		"tell": "His crest flickers when he's bluffing.",
		"habit": "Quills bluff. A flickering crest isn't final.",
		"rule": "tips_for_speed"},           # impaciente: una propina si el trato se cierra rápido
	"glimmerfolk": {"ask": 1.15, "offer": 0.85, "floor": 0.9, "ceiling": 1.1, "temper": 0.08, "rounds": 3, "give": 0.4,
		"tell": "Her thoughts glow warmer when she likes your price.",
		"habit": "Glimmerfolk glow warm at a price they like.",
		"rule": "barter_first"},             # propone primero un trueque: una pieza en vez de créditos
	"burrower": {"ask": 1.1, "offer": 0.75, "floor": 0.85, "ceiling": 1.0, "temper": 0.2, "rounds": 2, "give": 0.5,
		"tell": "Hides behind the goggles when the price scares him.",
		"habit": "Burrowers are shy. A big ask scares them off.",
		"rule": "small_coins"},              # tímido, paga en monedas chicas; un precio alto lo asusta (más enojo)
	"human": {"ask": 1.2, "offer": 0.8, "floor": 0.9, "ceiling": 1.15, "temper": 0.15, "rounds": 3, "give": 0.45,
		"tell": "Checks the time when he's in a hurry.",
		"habit": "Pilots pay up as launch gets close. Don't miss it.",
		"rule": "departure_clock"},          # Rook: un reloj de despegue; apurado paga más; si llega a 0 se va
	"bot": {"ask": 1.0, "offer": 0.9, "floor": 1.0, "ceiling": 1.0, "temper": 0.0, "rounds": 1, "give": 0.0,
		"tell": "Calculates out loud.",
		"habit": "Bots don't bluff. The budget is the budget.",
		"rule": "fixed_savings"},            # Clatter dice su presupuesto: acepta hasta ahí, nunca más
	"duneraker": {"ask": 1.3, "offer": 0.7, "floor": 0.85, "ceiling": 1.1, "temper": 0.15, "rounds": 3, "give": 0.4,
		"tell": "Flicks a tongue when you've hit a good price.",
		"habit": "A Raker's tongue flick means a good price.",
		"rule": "pods_sealed"},              # vende cápsulas cerradas (pistas: peso y traqueteo)
}
## Lo que dice cada especie. %d = un precio (el bot "open_sell" lleva dos: presupuesto y oferta), %s = una pieza.
const HAGGLE_LINES_BASE := {
	"hornback": {"open_sell": ["Hrm. %d credits.", "%d. Good price. Hrm."], "open_buy": ["%d. Not a coin less."],
		"reject": ["Hrrm. No. %d.", "Too far. %d."], "accept": ["Hrm. Deal.", "Good. Deal."],
		"final": ["%d. That is all."], "walk": ["Hmph. Too much talk."],
		"insulted": ["No haggle? Insulting. %d, then."], "tell": "*snorts and stamps*"},
	"quill": {"open_sell": ["%d credits, quick-quick!", "%d! Deal? Quick!"], "open_buy": ["%d, quick-quick!"],
		"reject": ["Fine, fine! %d. Final offer!", "%d! Final! Really!"], "accept": ["Done! Zip-zip!", "Deal! Gotta fly!"],
		"final": ["%d. Really, truly final."], "walk": ["Too slow! Gotta fly!"], "tip": ["Fast deal! Have a tip."],
		"tell": "*crest flickers*", "steady": "*crest holds still*"},
	"glimmerfolk": {"barter": ["Would you take %s instead of credits, dear?", "How about %s, dear? Instead of credits."],
		"open_sell": ["Then %d credits, dear.", "%d credits, if you please."], "open_buy": ["%d credits, dear."],
		"reject": ["Mm. %d, perhaps.", "Let me think... %d."], "accept": ["Lovely. A fair trade.", "How nice. Agreed."],
		"final": ["%d is my last thought on it."], "walk": ["Another day, dear."],
		"tell": "*thoughts glow warm*", "cool": "*thoughts turn cool*", "mild": "*thoughts flicker*"},
	"burrower": {"open_sell": ["Um... %d? In coins?", "I have %d... in small coins."], "open_buy": ["Um. %d?"],
		"reject": ["Oh. Um. %d?", "M-maybe %d?"], "accept": ["Th-thank you!", "Oh! Thank you!"],
		"final": ["That's... all my coins. %d."], "walk": ["S-sorry. Too much for me."],
		"coins": "*counts it out in small coins*", "tell": "*hides behind his goggles*"},
	"human": {"open_sell": ["%d. Quick, my ship leaves soon.", "I'll give you %d. Clock's running."],
		"open_buy": ["%d. Take it or leave it."], "reject": ["%d. Clock's ticking.", "Fine. %d."],
		"accept": ["Deal. Gotta run.", "Done. Thanks, kid."], "final": ["%d. Last call."],
		"walk": ["That's my launch. Keep it."], "hurry": ["Launch is close. Okay, okay."], "tell": "*checks the time*"},
	"bot": {"open_sell": ["CALCULATING. BUDGET %d. OFFER %d."], "open_buy": ["CALCULATING. PRICE %d."],
		"reject": ["OVER BUDGET. OFFER STANDS: %d."], "accept": ["TRANSACTION LOGGED. THANK YOU."],
		"final": ["OFFER STANDS: %d."], "walk": ["NO AGREEMENT. GOODBYE."], "tell": "*calculates out loud*"},
	"duneraker": {"open_buy": ["Fresh from last night's starfall! %d.", "Sealed and lucky! %d credits."],
		"open_sell": ["Ooh. %d for it?"], "reject": ["Ha! %d, friend.", "Cheeky! %d."],
		"accept": ["Sold! May it rattle with treasure.", "Deal! A lucky pod, that one."],
		"final": ["%d, and that's a kindness."], "walk": ["No worries. More fall every night!"],
		"tell": "*flicks a tongue*"},
}
var HAGGLE: Dictionary = {}
var HAGGLE_LINES: Dictionary = {}

func _init() -> void:
	HAGGLE = HAGGLE_BASE.duplicate(true)
	HAGGLE_LINES = HAGGLE_LINES_BASE.duplicate(true)
	HAGGLE.merge(CastData.HAGGLE, true)
	HAGGLE_LINES.merge(CastData.HAGGLE_LINES, true)
# --- end SS2 BENCH

## Palabras del ánimo (0..1) para la pantalla.
const MOODS := [[0.72, "Happy"], [0.48, "Fine"], [0.25, "Annoyed"], [0.0, "Fuming"]]

## Cápsulas de chatarra (el puesto de los rakers): peso 1-3 (más cosas), traqueteo 0-2 (más probable una cosa rota).
const POD_BASE := 13          # precio base de una cápsula (se regatea) (--- SS MERGE: balance, era 22)
const POD_PARTS := Vector2i(2, 3)
const POD_BROKEN := 0.6       # --- SS MERGE: probabilidad de una cosa rota adentro (era 0.45: el estante quedaba vacío)
const POD_WEIGHT := ["light", "heavy", "very heavy"]
const POD_RATTLE := ["quiet", "a little", "a lot"]

# ------------------------------------------------------------------ ayudas

func item_name(item: String) -> String:
	return ITEMS.get(item, {}).get("name", item.capitalize())

func part_name(part: String) -> String:
	return PARTS.get(part, {}).get("name", part.capitalize())

func part_price(part: String) -> int:
	return int(PARTS.get(part, {}).get("price", 10))

func tool_name(tool: String) -> String:
	return TOOLS.get(tool, {}).get("name", tool.capitalize())

## La herramienta que da la pista clara para esa familia.
func best_tool(item: String) -> String:
	return String(ITEMS.get(item, {}).get("best_tool", "listen"))

## El síntoma (la frase del cliente) de una falla. variant: -1 = al azar entre SYMPTOM_LINES.
func symptom(item: String, fault: String, variant := 0) -> String:
	var lines: Array = SYMPTOM_LINES.get(item, {}).get(fault, [])
	if lines.is_empty():
		return FAULTS.get(item, {}).get(fault, "It's broken.")
	if variant < 0:
		return lines[randi() % lines.size()]
	return lines[clampi(variant, 0, lines.size() - 1)]

## Un trabajo para el banco (el formato del contrato de BenchUI.open).
func make_job(item: String, fault: String, customer := "", extras: Array = []) -> Dictionary:
	return {"item": item, "fault": fault, "symptom": symptom(item, fault), "extras": extras.duplicate(), "customer": customer}

## Un trabajo al azar (si customer tiene "brings" en Data.CAST, la cosa sale de ahí). El síntoma sale de las
## variantes (así el mismo daño no se dice siempre igual).
func random_job(customer := "", rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var pool: Array = Data.CAST.get(customer, {}).get("brings", ITEM_ORDER)
	if pool.is_empty():
		pool = ITEM_ORDER
	var item: String = pool[rng.randi() % pool.size()]
	var faults: Array = FAULTS[item].keys()
	var job := make_job(item, faults[rng.randi() % faults.size()], customer)
	var lines: Array = SYMPTOM_LINES.get(item, {}).get(job["fault"], [])
	if not lines.is_empty():
		job["symptom"] = lines[rng.randi() % lines.size()]
	return job

## Un trato para HaggleUI (el formato del contrato). extra: claves opcionales ("item", "stars", "pod"...).
func make_deal(mode: String, what: String, customer: String, base: int, extra := {}) -> Dictionary:
	var d := {"mode": mode, "what": what, "species": Data.species_of(customer), "base": base, "customer": customer,
		"name": Data.char_name(customer)}
	d.merge(extra, true)
	return d

## Lo que paga una reparación según las estrellas (0-3) y los segundos que tardó (20-40 s es lo normal).
## --- SS MERGE (balance de los 3 días): REPAY_Q y REPAY_SPEED; los segundos cuentan desde que Nell acepta el trabajo
## en el mostrador hasta que lo entrega (con las caminatas): hasta 38 s = rapidez completa.
const REPAY_Q := [0.55, 0.85, 1.0, 1.12]
const REPAY_SPEED := {"free": 38.0, "per_sec": 0.008, "min": 0.88, "max": 1.1}
func repair_pay(item: String, stars: int, seconds := 30.0) -> int:
	var base := float(ITEMS.get(item, {}).get("repair_pay", 15))
	var q: float = REPAY_Q[clampi(stars, 0, 3)]
	var sp: Dictionary = REPAY_SPEED
	var speed := clampf(float(sp["max"]) - maxf(0.0, seconds - float(sp["free"])) * float(sp["per_sec"]), float(sp["min"]), float(sp["max"]))
	return maxi(1, int(round(base * q * speed)))

## El precio de partida de una cosa reparada del estante.
func sale_price(item: String, stars: int) -> int:
	var base := float(ITEMS.get(item, {}).get("sale_base", 50))
	return int(round(base * [0.5, 0.8, 1.0, 1.2][clampi(stars, 0, 3)]))

## Las estrellas (0-3) de un puntaje (3.0 = perfecto; ver SCORE).
func stars_for(score: float) -> int:
	var n := 0
	for t in SCORE["stars"]:
		if score >= float(t) - 0.001:
			n += 1
	return n

## La pista de una herramienta para un trabajo. seed: el número del trabajo (elige los señuelos; cada herramienta
## débil tiene uno distinto). Devuelve {"tool", "clear", "fault" (índice), "decoy" (índice o -1),
## "strength": [4 x 0..1] (cuánto "salta" cada zócalo), "heat": [4 x -1..1], "wave", "text"}.
func clue(item: String, fault: String, tool: String, seed := 0) -> Dictionary:
	var slots: Array = ITEMS.get(item, {}).get("slots", [])
	var fi := slots.find(fault)
	var n := slots.size()
	var clear := tool == best_tool(item)
	var strength := []
	var heat := []
	for i in n:
		strength.append(0.0)
		heat.append(0.12)
	var out := {"tool": tool, "clear": clear, "fault": fi, "decoy": -1}
	if fi < 0:
		out["text"] = "Nothing unusual."
		out["wave"] = "hum"
	elif clear:
		strength[fi] = 1.0
		heat[fi] = float(HEAT.get(fault, 1))
		# --- SS2 BENCH: primero lo de la familia (TOOL_CLUES_BY_ITEM / WAVES_BY_ITEM)
		var by_item: Dictionary = TOOL_CLUES_BY_ITEM.get(item, {}).get(tool, {})
		out["text"] = String(by_item.get(fault, TOOL_CLUES.get(tool, {}).get(fault, "That one.")))
		out["wave"] = wave_for(item, fault)
	else:
		var others := []
		for i in n:
			if i != fi:
				others.append(i)
		var d: int = others[(absi(seed) + TOOL_ORDER.find(tool)) % others.size()]
		out["decoy"] = d
		strength[fi] = 0.55
		strength[d] = 0.55
		heat[fi] = 0.55
		heat[d] = 0.55
		# en el orden de los zócalos (el orden no delata cuál es)
		var a := part_name(slots[mini(fi, d)]).to_lower()
		var b := part_name(slots[maxi(fi, d)]).to_lower()
		out["text"] = "%s The %s or the %s?" % [TOOL_MUDDLED.get(tool, "Hard to tell."), a, b]
		out["wave"] = "mixed"
	out["strength"] = strength
	out["heat"] = heat
	return out

## Las reglas de regateo de una especie (con valores por defecto si falta alguna).
func haggle_rules(species: String) -> Dictionary:
	var r: Dictionary = HAGGLE.get("human", {}).duplicate()
	r.merge(HAGGLE.get(species, {}), true)
	return r

## Una frase de la especie (al azar entre las variantes). args: los valores para %d / %s.
func haggle_line(species: String, key: String, args: Array = []) -> String:
	var lines = HAGGLE_LINES.get(species, {}).get(key, HAGGLE_LINES["human"].get(key, ""))
	var s := ""
	if lines is Array:
		s = String(lines[randi() % lines.size()]) if not lines.is_empty() else ""
	else:
		s = String(lines)
	if args.is_empty() or not ("%" in s):
		return s
	var need := s.count("%d") + s.count("%s")
	var a := args.duplicate()
	while a.size() < need:
		a.append(a[-1])
	a.resize(need)
	return s % a

func mood_word(m: float) -> String:
	for e in MOODS:
		if m >= float(e[0]):
			return String(e[1])
	return "Fuming"

## Una cápsula cerrada con su contenido ya decidido (así el peso y el traqueteo dicen la verdad).
func roll_pod(rng: RandomNumberGenerator = null, id := "") -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var n := rng.randi_range(POD_PARTS.x, POD_PARTS.y)
	var contents: Array = []
	for i in n:
		contents.append({"part": PART_ORDER[rng.randi() % PART_ORDER.size()]})
	var broken := rng.randf() < POD_BROKEN
	if broken:
		var item: String = ITEM_ORDER[rng.randi() % ITEM_ORDER.size()]
		var faults: Array = FAULTS[item].keys()
		contents.append({"item": item, "fault": faults[rng.randi() % faults.size()]})
	var weight := clampi(n - 1 + (1 if broken else 0), 1, 3)
	var rattle := 2 if broken else (1 if n >= 3 else 0)
	return {"id": id if id != "" else "pod_%d" % rng.randi_range(100, 999), "weight": weight, "rattle": rattle,
		"price": POD_BASE + 3 * weight + 2 * rattle, "contents": contents}

## Lo que vale lo que trae una cápsula (piezas a precio de Mags + 40 % de la venta de una cosa rota).
func pod_value(pod: Dictionary) -> int:
	var v := 0
	for c in pod.get("contents", []):
		if c.has("part"):
			v += part_price(c["part"])
		elif c.has("item"):
			v += int(round(float(ITEMS.get(c["item"], {}).get("sale_base", 50)) * 0.4))
	return v   # (--- SS2 BENCH: el núcleo de lámpara no tiene precio)

## Texto corto de un contenido de cápsula ("Power cell", "Street radio (broken)").
func content_name(c: Dictionary) -> String:
	if c.has("part"):
		return part_name(c["part"])
	if c.has("item"):
		return "%s (broken)" % item_name(c["item"])
	if c.has("core"):
		return "Lamp core"      # --- SS2 BENCH
	return "?"

# ------------------------------------------------------------------ --- SS2 BENCH: la temporada

## La onda de LISTEN de una pieza en una familia (WAVES_BY_ITEM primero).
func wave_for(item: String, fault: String) -> String:
	return String(WAVES_BY_ITEM.get(item, {}).get(fault, WAVES.get(fault, "hum")))

## Lo que hace la cosa al probarla bien: "notes" | "flame" | "lights" | "stars" | "" (el bot habla).
func power_fx(item: String) -> String:
	return String(ITEMS.get(item, {}).get("power_fx", ""))

## El acertijo de Old Seven para una falla ("" si no hay: entonces vale el síntoma de siempre). Las familias sin
## acertijos propios usan los de la radio.
func riddle(item: String, fault: String) -> String:
	var r: Dictionary = CastData.RIDDLES.get(item, {})
	if r.has(fault):
		return String(r[fault])
	return String(CastData.RIDDLES.get("radio", {}).get(fault, ""))

## El precio del cajón "as-is" de Mags (una cosa rota a la vista): round(sale_base * 0.42).
func asis_price(item: String) -> int:
	return int(round(float(ITEMS.get(item, {}).get("sale_base", 40)) * 0.42))

## Las reglas de regateo de un PERSONAJE: CAST[who].haggle (una clave de regla propia) si la tiene, si no su especie;
## con los valores por defecto del humano. Mira Data.CAST y, si no está ahí, CastData.CAST.
func haggle_rules_for(who: String) -> Dictionary:
	var row: Dictionary = Data.CAST.get(who, CastData.CAST.get(who, {}))
	var key := String(row.get("haggle", ""))
	if key == "" or not HAGGLE.has(key):
		key = String(row.get("species", "human"))
	var r := haggle_rules(key)
	r["key"] = key
	return r

## La clave de las líneas de regateo de un personaje (la de su regla propia o su especie).
func haggle_key_for(who: String) -> String:
	return String(haggle_rules_for(who).get("key", "human"))

## Una cápsula de la temporada: solo familias y piezas desbloqueadas.
##   items / parts: lo que puede salir (Season.unlocked_items() / unlocked_parts()); vacío = todo.
##   opts: {"kind": "wreck" | "bigfall" | "charity", "force_item": "navbox", "min_parts": 3, "broken_p": 1.0,
##          "core": true, "price": 40}
## El peso y el traqueteo siguen diciendo la verdad (como roll_pod). El naufragio pesa 3 y traquetea 2.
func roll_pod_for(rng: RandomNumberGenerator, id: String, items: Array, parts: Array, opts := {}) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var item_pool: Array = []
	for it in items:
		if ITEMS.has(String(it)):
			item_pool.append(String(it))
	if item_pool.is_empty():
		item_pool = ITEM_ORDER.duplicate()
	var part_pool: Array = []
	for pt in parts:
		if PARTS.has(String(pt)):
			part_pool.append(String(pt))
	if part_pool.is_empty():
		part_pool = PART_ORDER.duplicate()
	var kind := String(opts.get("kind", ""))
	var n := rng.randi_range(POD_PARTS.x, POD_PARTS.y)
	n = maxi(n, int(opts.get("min_parts", 0)))
	var contents: Array = []
	for i in n:
		contents.append({"part": part_pool[rng.randi() % part_pool.size()]})
	var force := String(opts.get("force_item", ""))
	var broken := force != "" or rng.randf() < float(opts.get("broken_p", POD_BROKEN))
	if broken:
		var item: String = force if ITEMS.has(force) else item_pool[rng.randi() % item_pool.size()]
		var faults: Array = FAULTS[item].keys()
		contents.append({"item": item, "fault": faults[rng.randi() % faults.size()]})
	if bool(opts.get("core", false)):
		contents.append({"core": true})
	var weight := clampi(n - 1 + (1 if broken else 0), 1, 3)
	var rattle := 2 if broken else (1 if n >= 3 else 0)
	if kind == "wreck":
		weight = 3
		rattle = 2
	var price := POD_BASE + 3 * weight + 2 * rattle
	if opts.has("price"):
		price = int(opts["price"])
	elif kind == "charity":
		price = 0
	var pod := {"id": id if id != "" else "pod_%d" % rng.randi_range(100, 999), "weight": weight, "rattle": rattle,
		"price": price, "contents": contents}
	if kind != "":
		pod["kind"] = kind
	return pod
# --- end SS2 BENCH
