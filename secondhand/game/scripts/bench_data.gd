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

## Las tres familias. slots: las 4 piezas que se ven con la carcasa abierta (en este orden: s1..s4, como el
## manifest.json de ART; los números 1-4 pintados junto a cada zócalo son las teclas 1-4).
##   best_tool: la herramienta que da la pista CLARA (las otras dos dejan dos candidatos)
##   pads: los puntos a soldar (3-5); zone: el ancho de la zona verde del test (fracción del recorrido);
##   sweep: recorridos por segundo de la aguja del test; power: lo que pasa al encenderla (el test bien hecho)
const ITEMS := {
	"radio": {"name": "Street radio", "slots": ["speaker", "tuner", "cell", "chip"], "best_tool": "listen",
		"repair_pay": 13, "sale_base": 34, "pads": 3, "zone": 0.24, "sweep": 0.8,
		"kettle_tip": "Radios tell you by ear. Try LISTEN.",
		"power": "It plays! An old desert love song."},
	"helperbot": {"name": "Pocket helper bot", "slots": ["servo", "chip", "lens", "cell"], "best_tool": "tap",
		"talks": true, "repair_pay": 15, "sale_base": 38, "pads": 4, "zone": 0.21, "sweep": 0.92,
		"kettle_tip": "Little bots rattle where it hurts. TAP it.",
		"power": "It sits up and beeps hello."},
	"thruster": {"name": "Hoverbike thruster", "slots": ["coil", "nozzle", "fan", "cell"], "best_tool": "scan",
		"repair_pay": 17, "sale_base": 42, "pads": 5, "zone": 0.18, "sweep": 1.05,
		"kettle_tip": "Thrusters run hot. SCAN for the heat.",
		"power": "Whoomph! A clean blue flame."},
}
const ITEM_ORDER := ["radio", "helperbot", "thruster"]

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
}
const PART_ORDER := ["speaker", "tuner", "cell", "chip", "servo", "lens", "coil", "nozzle", "fan"]

## Las fallas: cosa -> pieza rota -> lo que dice el cliente (el síntoma de la nota).
const FAULTS := {
	"radio": {"speaker": "It crackles and hisses.", "cell": "No sound at all.", "tuner": "Only plays one station.",
		"chip": "Plays songs backwards."},
	"helperbot": {"servo": "It walks in circles.", "chip": "It forgot my name.", "lens": "It bumps into everything.",
		"cell": "It won't wake up."},
	"thruster": {"coil": "Overheats after a minute.", "nozzle": "Coughs and sputters.", "fan": "Weak thrust.",
		"cell": "Won't ignite."},
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
		"fan": "A tired, slow whoosh from the fan."},
	"tap": {"speaker": "The speaker cone buzzes when tapped.", "tuner": "The tuner dial wobbles in its socket.",
		"cell": "Clunk. The cell is loose in its clip.", "chip": "Tap... and the chip blinks, confused.",
		"servo": "The servo rattles like a loose tooth.", "lens": "The lens rattles in its ring.",
		"coil": "The coil ticks and pings. Cracked.", "nozzle": "Grit shakes out of the nozzle.",
		"fan": "A fan blade ticks against the cage."},
	"scan": {"speaker": "The speaker coil runs hot.", "tuner": "A hot spot on the tuner.",
		"cell": "The cell is stone cold. Empty.", "chip": "The chip glows in a strange pattern.",
		"servo": "One servo runs hot.", "lens": "The lens motor runs hot.",
		"coil": "The coil glows bright orange!", "nozzle": "A hot ring around the nozzle.",
		"fan": "The fan motor runs hot and slow."},
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
	"lens": "whine", "coil": "buzz", "nozzle": "sputter", "fan": "slow"}
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
const HAGGLE := {
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
const HAGGLE_LINES := {
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
		out["text"] = String(TOOL_CLUES.get(tool, {}).get(fault, "That one."))
		out["wave"] = String(WAVES.get(fault, "hum"))
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
	return v

## Texto corto de un contenido de cápsula ("Power cell", "Street radio (broken)").
func content_name(c: Dictionary) -> String:
	if c.has("part"):
		return part_name(c["part"])
	if c.has("item"):
		return "%s (broken)" % item_name(c["item"])
	return "?"
