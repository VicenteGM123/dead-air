extends RefCounted
class_name CastData
## --- SS2 BENCH (nuevo): el elenco nuevo de la temporada (solo constantes). Ids de ROL (rival, vendor, inspector,
## hermit, singer, timekeeper, tracker): un cambio de nombre por propiedad intelectual nunca toca una ruta, una partida
## o una hoja de personaje. Los nombres que se ven viven aquí (CAST[id].name).
##
## Quién lo usa:
##   Data (S) mezcla SPECIES, CAST y LINES en sus variables en _init() (por ruta: ResourceLoader.exists), y agrega a
##     CUSTOMERS / CHAR_IDS los ids de NEW_CUSTOMERS / NEW_CHAR_IDS. CAST_ADD / LINES_ADD son agregados para clientes
##     que ya existían (las familias nuevas que traen o compran, sus frases): Data los suma (no reemplaza).
##   BenchData mezcla HAGGLE y HAGGLE_LINES en las suyas (_init) y usa RIDDLES (riddle()).
##   BenchPortrait usa PORTRAIT_ANCHORS (dónde está cada cosa en el cuadro de 64x96, para las señales del regateo).
##   Season (S) lee CAST[id].twist (el giro de cada personaje, como datos).
## Texto que se ve: inglés británico, corto, cálido. Glint dice "sweetie"; Lune dice "darling".

## Las especies nuevas (la paciencia es un factor, como en Data.SPECIES).
const SPECIES := {
	"sandglass": {"name": "Sandglass", "patience": 1.3},
	"lampwing": {"name": "Lampwing", "patience": 1.1},
	"brushtail": {"name": "Brushtail", "patience": 0.75},
	"thornfolk": {"name": "Thornfolk", "patience": 1.2},   # P1 (Barb)
}

## role: customer | guest | market | rival. brings: lo que trae roto; buys: lo que compra del estante (dos familias se
## eligen entre las desbloqueadas). patience: factor propio. haggle: clave de regla propia ("" = la de su especie).
## twist: el giro del personaje como datos (Season lo aplica).
const CAST := {
	"rival": {"name": "Madame Glint", "species": "human", "role": "rival", "brings": ["helperbot"], "buys": [],
		"patience": 1.0, "haggle": "",
		"about": "Owner of Shine Again, next door. Turquoise beehive, peach-pink coat, a loupe on a chain. Shines things. Does not fix them.",
		"twist": {"id": "favour", "item": "helperbot", "fault": "servo", "label": "Buff's buffer", "sub": "a secret favour",
			"symptom": "It won't spin. It sulks.", "power": "It spins again. Quietly. Very quietly."}},
	"vendor": {"name": "Dolly", "species": "bot", "role": "market", "brings": [], "buys": [], "patience": 1.0, "haggle": "",
		"about": "A squat old forklift bot with her face on the lift mast. Sells fittings. Very proud of lifting.",
		"twist": {"id": "fittings"}},
	"inspector": {"name": "Inspector Tolle", "full_name": "Inspector Marigold Tolle", "species": "human", "role": "guest",
		"brings": ["radio"], "buys": [], "patience": 1.2, "haggle": "",
		"about": "The Tally Office's inspector. Mustard coat, pillbox hat, round spectacles, a very fat ledger. Precise, polite, secretly kind.",
		"twist": {"id": "graded", "kettle": "Tolle's watching. Steady."}},
	"hermit": {"name": "Old Seven", "species": "bot", "role": "guest", "brings": ["radio", "navbox"], "buys": [],
		"patience": 1.5, "haggle": "",
		"about": "A walking lighthouse: the old lamp-keeper of the High Yards. Speaks slowly. Brings things that speak in riddles.",
		"twist": {"id": "riddle"}},
	"singer": {"name": "Lune", "species": "lampwing", "role": "customer", "brings": ["jukebox", "radio"],
		"buys": ["jukebox", "radio"], "patience": 1.0, "haggle": "",
		"about": "The Slow Orbit's singer: a tall, gentle moth person with wings folded like a shawl. Delighted by any light.",
		"twist": {"id": "encore", "min_stars": 3, "line_patience": 0.2, "toast": "Lune hums. The whole line relaxes."}},
	"timekeeper": {"name": "Madam Sift", "species": "sandglass", "role": "customer", "brings": ["navbox", "radio"],
		"buys": ["navbox", "jukebox", "radio"], "patience": 1.0, "haggle": "",
		"about": "The port's timekeeper: an hourglass in a brass frame. Her sand is her patience. Turns herself over, once.",
		"twist": {"id": "turnover", "patience_to": 0.5, "line": "One moment. *turns herself over* There. Where were we?"}},
	"tracker": {"name": "Warden Brisk", "species": "brushtail", "role": "customer", "brings": ["thruster", "navbox"],
		"buys": ["thruster", "navbox"], "patience": 1.0, "haggle": "",
		"about": "A Brushtail tracker for the Tally Office: runaway bots, unpaid fines. Deadpan, fair, always in a hurry.",
		"twist": {"id": "no_questions", "secs": 40.0, "pay_k": 1.3, "line": "Fast work, fair pay, no questions."}},
	# --- P1 (hojas hechas; Season decide si y cuándo aparecen)
	"dockmaster": {"name": "Dockmaster Hesk", "species": "hornback", "role": "market", "brings": [], "buys": [], "patience": 1.0,
		"haggle": "", "about": "Rustwater's dockmaster: a big Hornback in a navy coat, one brass-capped horn, a reed in her mouth. Collects the dues.",
		"twist": {"id": "dues"}},
	"buffbot": {"name": "Buff", "species": "bot", "role": "rival", "brings": [], "buys": [], "patience": 1.0, "haggle": "",
		"about": "Glint's polishing bot: thin, one leg on a caster, a swan neck with a fluffy buffing wheel. Never says a word.",
		"twist": {"id": "silent"}},
	"stampbot": {"name": "Thunk", "species": "bot", "role": "guest", "brings": [], "buys": [], "patience": 1.0, "haggle": "",
		"about": "Inspector Tolle's rubber stamp on springy legs. Says only one word.", "twist": {"id": "stamp"}},
	"farmer": {"name": "Barb", "species": "thornfolk", "role": "customer", "brings": ["helperbot", "radio"],
		"buys": ["helperbot", "radio"], "patience": 1.0, "haggle": "",
		"about": "A short barrel cactus in a straw sun hat and a seed apron, from the orchards of Teasel. Kind, a little prickly.",
		"twist": {"id": "bloom"}},
	"porter": {"name": "Barrow", "species": "bot", "role": "customer", "brings": ["jukebox", "thruster"],
		"buys": ["thruster", "helperbot"], "patience": 1.0, "haggle": "",
		"about": "A porter bot built like a wheelbarrow, with a face painted on its tray and a delivery flag. Sometimes pays in parts.",
		"twist": {"id": "parts_pay", "chance": 0.35, "n": 2}},
}

## Los ids nuevos para Data.CUSTOMERS (los que pueden entrar a la tienda) y Data.CHAR_IDS (con hoja de personaje).
const NEW_CUSTOMERS := ["singer", "timekeeper", "tracker", "hermit", "inspector", "rival"]
const NEW_CHAR_IDS := ["rival", "vendor", "inspector", "hermit", "singer", "timekeeper", "tracker"]
## P1: hojas y datos listos (Season los agrega a CUSTOMERS cuando los use: Barb rep 25 desde el día 4, Barrow rep 10
## desde el día 2, §4.3).
const P1_CUSTOMERS := ["farmer", "porter"]
const P1_CHAR_IDS := ["dockmaster", "buffbot", "stampbot", "farmer", "porter"]

## Agregados a clientes que ya existían (Data los SUMA a sus brings / buys): las familias nuevas (§5.1).
const CAST_ADD := {
	"oona": {"brings": ["jukebox"], "buys": ["jukebox"]},
	"rook": {"brings": ["navbox"], "buys": ["navbox"]},
	"zib": {"brings": ["navbox"], "buys": ["navbox"]},
}
## Frases que les faltan a los clientes de siempre para las familias nuevas (se suman a Data.LINES[who][key]).
const LINES_ADD := {
	"oona": {"bring": {"jukebox": "My song box remembers one song, dear. Only one. I know the feeling."}},
	"rook": {"bring": {"navbox": "Compass thinks every lane leads home. Sweet thought. Wrong."}},
	"zib": {"bring": {"navbox": "Compass is spinning-spinning! I'll get lost! Hurry-hurry!"}},
}

## Lo que dice cada uno (las mismas claves que Data.LINES): bring (por familia), buy, thanks (0..3 estrellas), failed,
## angry, decline, sold, nodeal, none, full, home. Algunos tienen claves propias (la inspectora: certified / pass /
## noted; Glint: ahead / behind / neutral / hello, en la calle; Dolly: las de su puesto).
const LINES := {
	"singer": {
		"bring": {"jukebox": "Darling, the Slow Orbit's song box plays one song. Forever. The band is losing it.",
			"radio": "My radio hums in the dark. I like the hum. I'd like the music too."},
		"buy": "Anything that glows, darling? Or sings?",
		"thanks": ["It's... dim. Thank you.", "Soft and warm. Thank you.", "Lovely. It glows a little.",
			"Oh, it sings! Come hear us at the Slow Orbit."],
		"failed": "Still quiet. Never mind, darling. I'll hum for it.",
		"angry": "The lamps outside are calling me. Sorry.",
		"decline": "Another night, then, darling.",
		"sold": "It's perfect. It's going right by the stage.",
		"nodeal": "Too bright a price for me, darling.",
		"none": "Nothing that glows? I'll come back at dusk.",
		"full": "So many people. I'll float back later.",
		"home": "Closing? But the night just started!",
	},
	"timekeeper": {
		"bring": {"navbox": "My compass points at noon. Every hour. That is not how compasses work.",
			"radio": "My radio's time signal is three seconds late. Unacceptable. Charming, but unacceptable."},
		"buy": "Something reliable, please. Punctual, if possible.",
		"thanks": ["It works. Eventually.", "Adequate. Nearly on time.", "Precise work. I'm impressed.",
			"Perfect timing, Nell. Truly."],
		"failed": "Still late. Like everyone else today.",
		"angry": "I've run out. Literally.",
		"decline": "Understood. I'll make time elsewhere.",
		"sold": "Agreed. On the dot.",
		"nodeal": "That price is ahead of its time.",
		"none": "Nothing? I'll come back at a quarter past.",
		"full": "A line. I'll return at a quieter minute.",
		"home": "Six o'clock exactly. Good evening.",
		"turnover": "One moment. *turns herself over* There. Where were we?",
	},
	"tracker": {
		"bring": {"thruster": "Thruster. I chase things for a living. It doesn't.",
			"navbox": "My compass points at whoever owes the most. Lately, nobody."},
		"buy": "Something fast. No questions.",
		"thanks": ["Works. Noted.", "Fair work.", "Fast work, fair pay, no questions.",
			"Clean job. I'd hire you. I can't. Forms."],
		"failed": "Still broken. I'll write it up. Kindly.",
		"angry": "Can't wait. Someone's running.",
		"decline": "Fine. I'll chase it on foot.",
		"sold": "Done. No receipt needed.",
		"nodeal": "Too steep. I've got fines to collect.",
		"none": "Nothing fast? Then I'm off.",
		"full": "Line's long. I'll circle back.",
		"home": "Closed. The fines can wait. They always do.",
		"reward": "The reward's twelve credits. The paperwork's worth more.",
	},
	"hermit": {
		"bring": {"radio": "...hmmm. The Yards' night radio. It forgets.",
			"navbox": "...This one found the lanes for us. Now it is lost."},
		"buy": "...I only carry things. I do not buy them.",
		"thanks": ["...hmm.", "...Good hands.", "...Good hands. Gentle.", "...Like the night shift. Thank you."],
		"failed": "...Not yet. The sky is patient.",
		"angry": "...I will come back when the moons are full.",
		"decline": "...Another night.",
		"sold": "...It will be well kept.",
		"nodeal": "...No matter.",
		"none": "...Another night.",
		"full": "...Many lights in here. I will wait.",
		"home": "...Closing. The lamps are lit. Good.",
		"lamps": "I still work the guide lamps. They nudge what falls.",
	},
	"inspector": {
		"bring": {"radio": "Inspector Tolle, Tally Office. My radio only reads tariff tables. Even I have limits."},
		"buy": "Inspectors do not shop on duty. Officially.",
		"thanks": ["Form Nine. Please read it. All of it.", "Noted. Room for improvement.", "Satisfactory. In triplicate.",
			"Approved. Thunk, the big stamp."],
		"failed": "Form Nine. Please read it. All of it.",
		"angry": "I have other shops to count. Good day.",
		"decline": "Declined. I'll note that. Neutrally.",
		"sold": "Purchase recorded.",
		"nodeal": "Not within my allowance.",
		"none": "Nothing to inspect, then.",
		"full": "A queue. I'll return when it's orderly.",
		"home": "Closing time. Correctly observed.",
		"certified": "Approved. Thunk, the big stamp.",
		"pass": "Satisfactory. In triplicate.",
		"noted": "Noted. Room for improvement.",
	},
	"rival": {
		"bring": {"helperbot": "Hypothetically. Buff's buffer won't spin. I don't... do insides."},
		"buy": "Me? Buy secondhand? Sweetie. ...What's that shiny one?",
		"thanks": ["It spins. Sort of. Not a word, sweetie.", "It spins! Don't tell anyone.", "Good. Very good. Ugh.",
			"Flawless. I hate that. Thank you, sweetie."],
		"failed": "Still sulking. Buff, we polish through it.",
		"angry": "I don't queue, sweetie. Shine Again never queues.",
		"decline": "Fine. Buff, we polish through it.",
		"sold": "Lovely. I'll make it sparkle.",
		"nodeal": "For that? I'd rather polish a rock, sweetie.",
		"none": "Nothing shiny? How very you.",
		"full": "A line? How quaint. I'll come back.",
		"home": "Closing already? Shine Again never sleeps, sweetie.",
		"hello": "Neighbour! Love the... patches. Very handmade.",
		"ahead": "Back on top, sweetie. It's the sparkle.",
		"behind": "You passed me? Hm. Buff, polish faster.",
		"neutral": "Shine sells, sweetie. Fix... also sells. Annoyingly.",
	},
	"farmer": {
		"bring": {"helperbot": "My garden bot waters the rocks and ignores the beans. Help?",
			"radio": "My radio only gets the weather. Wrong planet's weather."},
		"buy": "Something sturdy for the orchard, love? A helper or a radio.",
		"thanks": ["Prickly job. Thank you anyway.", "It'll do till harvest.", "Lovely. Like rain on a dry day.",
			"Perfect! You've a green thumb for metal."],
		"failed": "Still wilting. Ah well. So do I, in summer.",
		"angry": "I've roots to water. Goodbye.",
		"decline": "No harm. I'll ask the bees.",
		"sold": "Done. I'll bring you a melon.",
		"nodeal": "Too dear for a farmer, love.",
		"none": "Nothing? I'll come back after the harvest.",
		"full": "Crowded as a seed tray. Later.",
		"home": "Closing? Same as my flowers at dusk.",
	},
	"porter": {
		"bring": {"jukebox": "Delivery for the bench! One song box, stuck on one tune.",
			"thruster": "My push-thruster wheezes on hills. Hills are most of my job."},
		"buy": "One working thing, please! I will carry it home myself.",
		"thanks": ["Received. Slightly wobbly.", "Received. Good enough to roll.", "Received in excellent condition!",
			"Five stars! I would rate you higher. I cannot count higher."],
		"failed": "Return to sender. Understood.",
		"angry": "My next delivery is waiting. Rolling off.",
		"decline": "Understood. I will roll elsewhere.",
		"sold": "Loaded! Thank you!",
		"nodeal": "Too heavy for my budget.",
		"none": "Empty shelf. Empty tray. We match.",
		"full": "Line full. I will park outside.",
		"home": "Closed. I will deliver myself home.",
		"parts": "Short on credits. Will you take parts? Good parts.",
	},
	"dockmaster": {
		"paid3": "Fine. Now go make that lantern shine.",
		"paid6": "The Tally Office raised MY dues. So I'm raising nothing. This time.",
		"paid9": "Paid in full. Hm. Don't make it a habit, you'll ruin my reputation.",
		"short": "Short? I'll carry it. With interest. I collect favours too.",
		"party": "Pay me after the party. I'm not a monster.",
	},
	"stampbot": {"stamp": "THUNK."},
	"vendor": {
		"hello": "Fittings! Everything a shop needs except customers. Those you earn.",
		"bought": "Lifted, carried, installed by morning.",
		"broke": "Credits first. I lift, I don't lend.",
		"locked": "Come back when the port knows your name.",
		"all": "You've bought me out. I'll go lift something heavy.",
	},
}

## Los acertijos de Old Seven (la nota del cliente, con la cabecera "A RIDDLE"): la mejor herramienta sigue diciendo
## la verdad.
const RIDDLES := {
	"radio": {"speaker": "It speaks through a mouthful of sand.", "tuner": "It remembers only one voice.",
		"cell": "It sleeps, and will not dream.", "chip": "It hums of yesterday."},
	"navbox": {"gyro": "It dances when it should stand.", "needle": "It points, and will not let go.",
		"lens": "It sees the stars through fog.", "chip": "It knows every road but the one ahead."},
}

## El regateo de las especies nuevas (mismas claves que BenchData.HAGGLE). Las tres usan la regla "generic" de
## HaggleUI: tell_fx (la señal en el retrato: still | flutter | ears) y tell_when ("near" = su precio está a menos de
## tell_near x base de su límite; "bluff" = una contraoferta que todavía no es la final).
const HAGGLE := {
	"sandglass": {"ask": 1.15, "offer": 0.82, "floor": 0.92, "ceiling": 1.12, "temper": 0.1, "rounds": 3, "give": 0.4,
		"tell": "Her sand stops falling when she bluffs.",
		"habit": "A Sandglass bluffs with her sand still. Watch it fall.",
		"rule": "generic", "tell_fx": "still", "tell_when": "bluff"},
	"lampwing": {"ask": 1.2, "offer": 0.78, "floor": 0.9, "ceiling": 1.18, "temper": 0.12, "rounds": 3, "give": 0.45,
		"tell": "Her wings flutter at a price she loves.",
		"habit": "A Lampwing flutters at a price she loves.",
		"rule": "generic", "tell_fx": "flutter", "tell_when": "near", "tell_near": 0.06},
	"brushtail": {"ask": 1.25, "offer": 0.8, "floor": 0.95, "ceiling": 1.1, "temper": 0.22, "rounds": 2, "give": 0.5,
		"tell": "Her ears go flat near her limit.",
		"habit": "Brushtails flatten their ears before they walk.",
		"rule": "generic", "tell_fx": "ears", "tell_when": "near", "tell_near": 0.08},
	# P1 (Barb): florece cerca de su límite; una contraoferta FIRM la eriza (se enoja un poco más)
	"thornfolk": {"ask": 1.2, "offer": 0.82, "floor": 0.92, "ceiling": 1.12, "temper": 0.1, "rounds": 3, "give": 0.4,
		"tell": "A pink bud blooms at a price she likes.",
		"habit": "A Thornfolk blooms at a price she likes. Firm asks make her bristle.",
		"rule": "generic", "tell_fx": "bloom", "tell_when": "near", "tell_near": 0.06, "firm_fx": "bristle", "firm_temper": 0.06},
}
const HAGGLE_LINES := {
	"sandglass": {"open_sell": ["%d credits. Precisely.", "I can offer %d. On the dot."], "open_buy": ["%d, please. Exactly."],
		"reject": ["Hm. %d. That is final.", "%d. Final. Truly."], "accept": ["Agreed. And on time.", "Done. Precisely."],
		"final": ["%d. And that is the actual final."], "walk": ["Time's up, I'm afraid."],
		"tell": "*her sand stops falling*", "steady": "*her sand trickles on*"},
	"lampwing": {"open_sell": ["%d, darling?", "Would %d do, darling?"], "open_buy": ["%d, darling."],
		"reject": ["Mm. %d?", "%d, then. For the glow."], "accept": ["Lovely. It's mine now.", "Oh, yes. Lovely."],
		"final": ["%d is all my sequins, darling."], "walk": ["Too bright for me, darling."],
		"tell": "*wings flutter*"},
	"brushtail": {"open_sell": ["%d. Quick.", "%d credits. No questions."], "open_buy": ["%d. Take it."],
		"reject": ["%d. Counter.", "%d. I'm moving on soon."], "accept": ["Done.", "Deal. Logged."],
		"final": ["%d. Last offer. Truly."], "walk": ["Not worth the paperwork."],
		"tell": "*ears flatten*"},
	"thornfolk": {"open_sell": ["%d, love. Fair's fair.", "I'll give you %d."], "open_buy": ["%d, love."],
		"reject": ["%d, then. Don't push.", "Hm. %d."], "accept": ["Done. Like picking a ripe one.", "Lovely. Deal."],
		"final": ["%d. That's the whole crop."], "walk": ["Too prickly for me."],
		"tell": "*a bud blooms*", "bristle": "*bristles*"},
}

## Dónde está cada cosa en el cuadro de 64x96 (mirando a la derecha), en píxeles del cuadro: head (el globo), y las
## zonas de las señales: sand (la arena que cae: el cuello del reloj), wings (las alas: el aleteo), ears (las orejas:
## se aplastan). Medidos sobre las hojas de ss_cast2.py.
const PORTRAIT_ANCHORS := {
	"rival": {"head": Vector2(32, 34)},
	"vendor": {"head": Vector2(48, 60)},
	"inspector": {"head": Vector2(32, 44)},
	"hermit": {"head": Vector2(32, 17)},
	"singer": {"head": Vector2(32, 34), "wings": Rect2(19, 40, 26, 24)},
	"timekeeper": {"head": Vector2(32, 45), "sand": Vector2(32, 61)},
	"tracker": {"head": Vector2(31, 39), "ears": Rect2(23, 23, 19, 9)},
	"dockmaster": {"head": Vector2(30, 32)},
	"buffbot": {"head": Vector2(36, 43)},
	"stampbot": {"head": Vector2(31, 80)},
	"farmer": {"head": Vector2(31, 70), "bud": Vector2(22, 65)},
	"porter": {"head": Vector2(32, 67)},
}
