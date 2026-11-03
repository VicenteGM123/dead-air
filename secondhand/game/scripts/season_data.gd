extends RefCounted
class_name SeasonData
## --- SS2 SEASON: los números y los textos de la temporada (SS2_DESIGN §2, §4, §5.4-5.6). Solo constantes: la lógica
## está en scripts/season.gd (autoload Season). Ids en inglés y en minúsculas; los personajes nuevos tienen ids de
## papel (rival, vendor, inspector, hermit, singer, timekeeper, tracker): sus nombres se ven en Data.CAST.
## Textos para el jugador: inglés británico, corto, cálido, un poco de humor (nada de nombres de la saga: ver §10).
## Los valores marcados (tune) son de partida: el bot los mide (NOTES.txt de la línea S).

const LAST_DAY := 10                     # el día del cometa (después: el modo sin fin, "Keep trading")
const ARRIVALS_CAP := 10                 # nunca más de 10 llegadas en un día (§2.2)
const AFTER_HOURS_MAX := 2               # arreglos de noche, después de cerrar (§2.7) (tune)
const AFTER_HOURS_BONUS := {7: 1}        # (tune) la noche antes de Bronzemoon, uno más ("Fill the shelf!")

## El calendario (§2.2). arrivals: cuántos llegan (con los invitados); generated: cuántos sale de la agenda generada
## (días >= 4); buyers: parte de los generados que compran; pods: cápsulas de Raker (sin la 3.ª de la reputación);
## pod_opts: reglas de las cápsulas de ese día; extra_pods: cápsulas especiales; guests: invitados con su hora (t en
## segundos del día abierto) y su "extra"; beats: los momentos de historia que pueden pasar ese día; navbox_bias: estos
## clientes traen brújulas el doble de seguido. Los días 1-3 usan Data.SCHEDULE tal cual (+ los invitados).
const PLAN := {
	# --- POLISH FIX (F10): los subtítulos del día 1 (era "Learn the bench") y del día 4 (repetía el título; nombra a Lune)
	1: {"title": "Opening Day", "sub": "Buy a pod, open up, fix things", "event": "", "arrivals": 6, "pods": 2, "guests": []},
	2: {"title": "Fittings for Sale", "sub": "Dolly sells fittings now", "event": "", "arrivals": 8, "pods": 2, "guests": []},
	3: {"title": "New Neighbours", "sub": "Dues tonight: 100", "event": "", "arrivals": 10, "pods": 2,
		"guests": [{"who": "timekeeper", "t": 130.0, "kind": "repair", "if_unlocked": true}]},
	4: {"title": "Music Across the Street", "sub": "Lune brings her song box", "event": "", "arrivals": 9,
		"generated": 7, "buyers": 0.35, "pods": 2, "rush": 0.45,
		"guests": [{"who": "singer", "t": 40.0, "kind": "repair", "item": "jukebox"},
			{"who": "hermit", "t": 200.0, "kind": "repair", "item": "radio", "extra": {"riddle": true}}]},
	5: {"title": "The Scour", "sub": "Pods closed. Customers stay longer.", "event": "sandstorm", "arrivals": 6,
		"generated": 5, "buyers": 0.30, "pods": 0, "rush": 0.3,
		"guests": [{"who": "rival", "t": 110.0, "kind": "favour", "extra": {"favour": true}}]},
	6: {"title": "Inspection Day", "sub": "Be tidy. Be punctual. Please.", "event": "inspection", "arrivals": 9,
		"generated": 8, "buyers": 0.35, "pods": 2, "pod_opts": {"min_parts": 3}, "rush": 0.55,
		"guests": [{"who": "inspector", "t": 80.0, "kind": "repair", "item": "radio", "extra": {"graded": true}}]},
	7: {"title": "Bigfall", "sub": "The sky dropped a big one", "event": "bigfall", "arrivals": 9, "generated": 9,
		"buyers": 0.30, "pods": 2, "rush": 0.4, "extra_pods": ["wreck"],
		"navbox_bias": ["rook", "zib", "timekeeper", "tracker"], "guests": []},
	8: {"title": "Bronzemoon", "sub": "Both moons full. Buyers everywhere.", "event": "festival", "arrivals": 9,
		"generated": 8, "buyers": 0.60, "pods": 2, "rush": 0.35,
		"guests": [{"who": "hermit", "t": 170.0, "kind": "repair", "item": "navbox", "extra": {"riddle": true}}]},
	9: {"title": "The Glasspan Derby", "sub": "Racers need thrusters by 2:30 PM", "event": "race", "arrivals": 9,
		"generated": 5, "buyers": 0.30, "pods": 2, "racers": true, "guests": []},
	10: {"title": "The Great Starfall", "sub": "Every star counts twice", "event": "finale", "arrivals": 9,
		"buyers": 0.40, "pods": 2, "extra_pods": ["bigfall"], "curtain_call": true, "guests": []},
}
## El último día de la campaña: todos los conocidos, una vez cada uno (y nadie más).
const CURTAIN_CALL := ["gorrum", "zib", "oona", "pipip", "rook", "clatter", "singer", "timekeeper", "tracker"]
## El día de la carrera: los corredores llegan primero (t) con propulsores; rook solo si le llevó la caja a tiempo.
const RACERS := [["pipip", 3.0], ["gorrum", 12.0], ["timekeeper", 24.0], ["rook|tracker", 36.0]]
## El modo sin fin (§2.6)
const ENDLESS := {"arrivals": [8, 9], "buyers": [0.35, 0.45], "pods": 2, "event_gap": [2, 3]}
const ENDLESS_POOL := ["sandstorm", "inspection", "bigfall", "festival", "race"]

## Los días especiales (§5.4). effects: las claves de efecto (§8.2) mientras dura el día; fault_bias: las fallas que
## más salen (60 % de las veces); mags_extra: piezas que Mags trae ese día; announce: la línea de la noche anterior
## (el pie del tablero y el tiempo del Lantern Report); preview: la línea corta de "Tomorrow: ..."; kettle: el aviso
## de Kettle por la mañana; flavour: lo que dice 1 de cada 3 clientes al irse; music / amb: lo que suena (Sfx).
const EVENTS := {
	"sandstorm": {"name": "The Scour", "effects": {"patience_k": 1.4, "part_price_add": -2},
		"fault_bias": ["nozzle", "fan", "speaker", "lens", "drum"], "pods": 0, "dressing": "sandstorm", "music": "",
		"amb": "storm", "icon": "event_sandstorm",
		"announce": "Scour warning over Saffra tomorrow. Tie down your tortoises.",
		"preview": "Tomorrow: the Scour. Pods closed, but nobody's in a hurry.",
		"kettle": "Kettle ties a rag round his spout. Wise kettle.",   # --- POLISH FIX (F10): Kettle está a la vista
		"flavour": "Close the door! You're letting the desert in."},
	"inspection": {"name": "Inspection Day", "effects": {}, "fault_bias": [], "dressing": "inspection", "music": "",
		"amb": "", "icon": "event_inspection",
		"announce": "Tally Office notice: inspections tomorrow. Smile at the stamp.",   # --- POLISH FIX (F10): 75 -> 62 (el Report pide <= 70)
		"preview": "Tomorrow: a Tally Office inspection. Be tidy.",
		"kettle": "Kettle practises looking innocent. Kettle has nothing to declare.",   # --- POLISH FIX (F10)
		"flavour": ""},
	"bigfall": {"name": "Bigfall", "effects": {}, "fault_bias": [], "dressing": "bigfall", "music": "", "amb": "",
		"icon": "event_bigfall", "mags_extra": ["gyro", "needle"],
		"announce": "Sky-watch: a big shadow on the Ring tonight. Keep your hats on.",
		"preview": "Tomorrow: something big falls. Raker will have a wreck.",
		"kettle": "The whole street shakes. Kettle rattles his lid at the sky.",   # --- POLISH FIX (F10)
		"flavour": "Big one last night. Gorrum felt it in his horns."},
	"festival": {"name": "Bronzemoon", "effects": {"sale_k": 1.2}, "fault_bias": [], "dressing": "festival",
		"music": "festival", "amb": "", "icon": "event_festival",
		"announce": "Both moons full tomorrow. Bronzemoon, Rustwater! Lanterns out!",
		"preview": "Tomorrow: Bronzemoon. Buyers everywhere. Fill the shelf!",
		"kettle": "Kettle whistles along with the band. Mostly in tune.",
		"flavour": "On Bronzemoon night, everyone's a little bit golden."},
	"race": {"name": "The Glasspan Derby", "effects": {}, "fault_bias": ["coil", "nozzle", "fan", "cell"],
		"dressing": "race", "music": "race", "amb": "", "icon": "event_race",
		"announce": "Glasspan Derby tomorrow. Rustwater's bikes are coughing already.",
		"preview": "Tomorrow: the Glasspan Derby. Racers need thrusters by 2:30 PM.",
		"kettle": "Kettle bets on Pipip. Kettle has no money. Kettle bets anyway.",
		"flavour": ""},
	"finale": {"name": "The Great Starfall", "effects": {"patience_k": 1.3, "tea_uses": 1, "stars_k": 2.0},
		"fault_bias": [], "dressing": "finale", "music": "", "amb": "", "icon": "event_finale",
		"announce": "Tomorrow the Great Starfall: every fix counts twice. Lanterns out!",
		"preview": "Tomorrow: the Great Starfall. Every fix counts twice.",
		"kettle": "Kettle polishes the star sign. With steam.",
		"flavour": ""},
}
## Kettle la noche antes de Bronzemoon (además del anuncio).
const KETTLE_BEFORE_FESTIVAL := "Bronzemoon tomorrow. Buyers everywhere. Fill the shelf!"

## La carrera (§5.4): los propulsores de los corredores entregados antes de las 2 PM (minuto 840); a las 3 PM se corre.
## (tune, lane S) la hora límite pasó de las 2 PM a las 2:30 PM: el perfil humano solo llegaba a 2 corredores.
const RACE := {"deadline_min": 870, "deadline_text": "2:30 PM", "call_min": 900, "podium_n": 3, "podium_avg": 2.3, "finished_n": 2,
	"podium": {"stars": 10, "credits": 50}, "finished": {"stars": 4}}
const RACE_LINES := {
	"call": "And they're off-off-off!",
	"podium": "Glasspan Derby: {winner} wins on a Secondhand Star bike! +10 ★, +50 cr, a cup.",
	"finished": "Everyone finished the Derby. Rustwater cheers! +4 ★",
	"none": "The Derby's run. A Brindle crew takes the cup. Dust everywhere.",
	"pipip": ["We finished! Digger finished! We're... finished. Happily.", "We finished! Digger finished! We're... finished. Happily.",
		"Third! That's... a number! Thank you!", "I WON? Sorry. I mean... I won! Sorry!"],
}
## La inspección (§5.4): el trabajo calificado de Tolle.
const GRADES := {
	"certified": {"min": 3, "stars": 8, "credits": 30, "rep": 0, "name": "Approved"},
	"pass": {"min": 2, "stars": 3, "credits": 0, "rep": 0, "name": "Satisfactory"},
	"noted": {"min": 0, "stars": 0, "credits": 0, "rep": -2, "name": "Noted"},
}
const GRADE_LINES := {"certified": "Approved. Thunk, the big stamp.", "pass": "Satisfactory. In triplicate.",
	"noted": "Noted. Room for improvement.", "failed": "Form Nine. Please read it. All of it."}
## La banda en la puerta en Bronzemoon: +4 ★ ("local favourite").
const BAND_STARS := 4

## Las cuotas del muelle (§2.5): tres partes, en las noches 3, 6 y 9 (tune). Sin fin: una cuota cada 3 noches.
const DUES := {3: 100, 6: 200, 9: 300}
const UPKEEP := {"every": 3, "amount": 250, "first": 12}
## La regla blanda: si no alcanza, Hesk se lleva todo menos 15; lo que falta (+10 %) pasa a la próxima; LATE −3 ★.
const SOFT_RULE := {"keep": 15, "late_fee_k": 0.10, "late_stars": -3}
const HESK := {
	"name": "Dockmaster Hesk", "sub": "Dock dues",
	"ask": "Dues tonight: {due} cr.",
	"ask_short": "Dues tonight: {due} cr. You have {have}.",
	"paid": {3: "Fine. Now go make that lantern shine.",
		6: "The Tally Office raised MY dues. So I'm raising nothing. This time.",
		9: "Paid in full. Hm. Don't make it a habit, you'll ruin my reputation."},
	"paid_upkeep": "Paid. The dock thanks you. Grudgingly.",
	"short": "Short? I'll carry it. With interest. I collect favours too.",
	"party": "Pay me after the party. I'm not a monster.",
}

## Las mejoras (§4.1): las vende Dolly en el patio "Fittings" desde el día 2, a precio fijo. effects: claves de §8.2.
## (tune, lane S) precios ~60 % de los del diseño (720 -> 445 en total): con lo que gana de verdad un buen jugador
## (~100-110 cr netos al día, como el prototipo) las 8 a 720 no entraban antes del día 9 (ver NOTES, balance).
## desc: la línea corta del aviso al estrenarla ("New: Liner Seats · the line waits longer"); detail: lo que dice la
## fila del diálogo de Dolly.
const FITTINGS := {
	"samovar": {"name": "Kettle's Samovar", "cost": 30, "day": 2, "rep": 0,
		"effects": {"tea_uses": 1, "tea_boost_add": 0.1, "appeal": 1},
		"desc": "tea twice a day", "detail": "Tea twice a day, and each pour calms the line a bit more."},
	"seats": {"name": "Liner Seats", "cost": 35, "day": 2, "rep": 0, "effects": {"line_drain_k": 0.75, "appeal": 1},
		"desc": "the line waits longer", "detail": "Salvaged liner seats. The line's patience drains slower."},
	"podlamp": {"name": "Pod Lamp", "cost": 50, "day": 2, "rep": 0, "effects": {"pod_peek": 1, "appeal": 1},
		"desc": "peek inside Raker's pods", "detail": "A scanner lamp: each pod's label shows one thing inside."},
	"coolcoil": {"name": "Cool Coil", "cost": 45, "day": 3, "rep": 0, "effects": {"solder_add": 2, "sweep_k": 0.85, "appeal": 1},
		"desc": "a cool bench is a steady hand", "detail": "Solder timer +2 s, and the test needle swings slower."},
	"display": {"name": "Display Case", "cost": 70, "day": 3, "rep": 15,
		"effects": {"buyers_add": 1, "sale_k": 1.1, "shelf_slots": 2, "appeal": 1},
		"desc": "shelf prices up, one more buyer", "detail": "Shelf prices +10 %. One more buyer when 3+ items are out."},
	"partswall": {"name": "Parts Wall", "cost": 55, "day": 4, "rep": 0, "effects": {"free_part": 1, "appeal": 1},
		"desc": "a free part every morning", "detail": "One free part each morning, for a job coming in today."},
	"loupe": {"name": "Loupe Lamp", "cost": 75, "day": 4, "rep": 15, "effects": {"bench_pad_k": 1.4, "bench_zone_k": 1.25, "appeal": 1},
		"desc": "bigger pads, wider green", "detail": "Solder pads 40 % bigger, the green zone 25 % wider."},
	"neon": {"name": "Neon Star", "cost": 85, "day": 5, "rep": 35, "effects": {"arrivals_add": 1, "repair_k": 1.1, "appeal": 2},
		"desc": "they saw the sign", "detail": "One more customer on quiet days. Repairs pay +10 %."},
}
const FITTING_ORDER := ["samovar", "seats", "podlamp", "coolcoil", "display", "partswall", "loupe", "neon"]
const DOLLY := {
	"name": "Dolly", "sub": "Fittings · lifted and installed",
	"hello": "Fittings! Everything a shop needs except customers. Those you earn.",
	"bought": "Lifted, carried, installed before you open.",
	"broke": "Credits first. I lift, I don't lend.",
	"locked": "Come back when the port knows your name.",
	"all": "You've bought me out. I'll go lift something heavy.",
	"closed": "Fittings open tomorrow. I'm still unpacking.",
	"kettle": "Long lines? The seats. Thirsty line? You know which.",
}

## La reputación (§4.2): cada tramo suma sus efectos a los de los anteriores.
const REP_TIERS := [
	{"id": "newcomer", "rep": 0, "name": "Newcomer", "effects": {}, "unlocks": ""},
	{"id": "known", "rep": 15, "name": "Known in Rustwater", "effects": {"pods_add": 1},
		"unlocks": "a third pod at Raker's, Madam Sift, two new fittings"},
	{"id": "trusted", "rep": 35, "name": "Trusted", "effects": {"asis_add": 1},
		"unlocks": "two as-is finds at Mags's, Warden Brisk, the Neon Star"},
	{"id": "favourite", "rep": 60, "name": "Port Favourite", "effects": {"repair_k": 1.1},
		"unlocks": "repairs pay +10 %. They ask for you by name"},
	{"id": "legend", "rep": 90, "name": "Legend of the Drift", "effects": {"appeal": 1},
		"unlocks": "+1 ★ a day, and a little gold on the sign"},
]

## Lo que se abre (§4.3): por día, y algunos antes con reputación (latest = el día en que se abre igual).
## kind: place | market | family | customer. name: lo que dice el cartel de la mañana ("New today: ...").
const UNLOCKS := {
	"vendor": {"kind": "place", "day": 2, "rep": 0, "latest": 2, "name": "Dolly's Fittings"},
	"rival": {"kind": "place", "day": 3, "rep": 0, "latest": 3, "name": "Shine Again next door"},
	"asis": {"kind": "market", "day": 3, "rep": 0, "latest": 3, "name": "Mags's as-is bin"},
	"jukebox": {"kind": "family", "day": 4, "rep": 0, "latest": 4, "name": "Song boxes"},
	"navbox": {"kind": "family", "day": 7, "rep": 0, "latest": 7, "name": "Star compasses"},
	"timekeeper": {"kind": "customer", "day": 3, "rep": 15, "latest": 5, "name": "Madam Sift"},
	"singer": {"kind": "customer", "day": 5, "rep": 0, "latest": 5, "name": "Lune"},
	"tracker": {"kind": "customer", "day": 5, "rep": 35, "latest": 7, "name": "Warden Brisk"},
}
## Las familias del prototipo (siempre abiertas) y los clientes de siempre.
const BASE_FAMILIES := ["radio", "helperbot", "thruster"]
const BASE_CUSTOMERS := ["gorrum", "zib", "oona", "pipip", "rook", "clatter"]
## Las piezas de cada familia nueva (para Mags y el Parts Wall cuando la familia existe).
const MAGS_CORE := ["cell", "chip"]
const MAGS_MAX := 8
const ASIS_EVE_BONUS := 2                # (tune) la víspera de Bronzemoon Mags vacía el cajón: dos cosas más
const ASIS_EVE_K := 0.7                  # (tune) y lo deja más barato (la víspera viene justo después de la cuota de la noche 6)
const STORM_SALE_MIN := 2
const POD_PRICES := {"wreck": 40, "bigfall": 45, "charity": 0}
const CHARITY := {"credits_below": 15, "parts_below": 2, "every": 3}

## Los efectos de las marcas de historia (§8.2): band solo el día del festival.
const FLAG_EFFECTS := {
	"band": {"event": "festival", "effects": {"patience_k": 1.25}},
	"paid_in_full": {"effects": {"appeal": 1}},
	"clatter_job": {"effects": {"patience_k": 1.1}},   # (P1) Clatter barre la tienda: la fila espera un poco más
}
## (P1) La oferta del día de Mags (desde Trusted): una pieza a -40 %.
const MAGS_DEAL := {"rep": 35, "k": 0.6}
## (P1) El trabajo de Clatter: si sus 3+ arreglos promediaron >= 2 estrellas, la noche 6 pide trabajo.
const CLATTER_JOB := {"min_n": 3, "min_avg": 2.0}

## Las mañas de los clientes nuevos (§5.3; por id de papel: así un cambio de nombre no toca nada).
const TWISTS := {
	"singer": {"kind": "encore", "stars": 3, "line_patience": 0.2, "toast": "Lune hums. The whole line relaxes."},
	"timekeeper": {"kind": "turnover", "back_to": 0.5, "line": "One moment. *turns herself over* There. Where were we?"},
	"tracker": {"kind": "quick", "secs": 40.0, "pay_k": 1.3, "toast": "No questions asked: +30 %."},
}

## El favor secreto de Glint (§5.5): el cepillo de Buff en el banco (la vista del robot de bolsillo).
const FAVOUR_JOB := {"item": "helperbot", "fault": "servo", "label": "Buff's buffer", "sub": "a secret favour",
	"symptom": "It won't spin. It sulks.", "pay": 40, "bonus": 8}

## Los momentos de historia (§5.5). who: quién habla (su retrato); day / phase: cuándo ("morning" en la calle,
## "open" en la tienda, "night" después del tablero); trigger: "" (al empezar la fase), "after_handover" (después de
## entregarle algo a who), "at_counter" (cuando who llega al mostrador), "minute" (a esa hora); need: condiciones
## sobre las marcas ({"crate": ["kept"]}); lines: las dos líneas; lines_low: si la entrega tuvo menos de min_stars;
## options: [{id, text, set, stars, credits, toast, reply, prop}]; must_choose: Esc / B no la cierra (§5.5).
const BEATS := {
	"crate_ask": {"who": "rook", "day": 2, "phase": "morning", "trigger": "", "need": {},
		"lines": ["Hold this for me? Few days.", "Don't open it. Don't sell it. Don't let the Tally Office see it."],
		"options": [{"id": "keep", "text": "Keep it", "set": {"crate": "kept"}, "prop": {"crate": true},
				"toast": "The crate goes in the tea corner. Kettle sits on it."},
			{"id": "refuse", "text": "Not my business", "set": {"crate": "refused"}, "reply": "Fair. I'll ask the tortoise."}],
		"must_choose": true},
	"rival_hello": {"who": "rival", "day": 3, "phase": "morning", "trigger": "", "need": {},
		"lines": ["Neighbour! Love the... patches. Very handmade.", "At Shine Again we don't fix things, sweetie. We make them sparkle."],
		"options": [{"id": "ok", "text": "Nice to meet you"}]},
	"seven_first": {"who": "hermit", "day": 4, "phase": "open", "trigger": "after_handover", "need": {}, "min_stars": 2,
		"lines": ["...hmmmm. Good hands.", "Lamp Seven is dark. The Yards fall crooked. Keep this. It wants to go home."],
		"lines_low": ["...hmmm. Not yet.", "I will come back when the moons are full."],
		"core": "seven4", "options": [{"id": "ok", "text": "I'll keep it safe"}], "options_low": [{"id": "ok", "text": "Goodbye"}]},
	"glint_favour": {"who": "rival", "day": 5, "phase": "open", "trigger": "favour", "need": {},
		"lines": ["Hypothetically. Buff's buffer won't spin.", "I don't... do insides. Could you? Quietly?"],
		"options": [{"id": "fix", "text": "Fix it quietly · 40 cr"},
			{"id": "refuse", "text": "Not a chance", "set": {"favour": "refused"}, "reply": "Fine. Buff, we polish through it."}],
		"must_choose": true},
	"tolle_crate": {"who": "inspector", "day": 6, "phase": "open", "trigger": "at_counter", "need": {"crate": ["kept"]},
		"lines": ["Inspector Tolle, Tally Office. I'm only counting everything.", "...Is that crate humming?"],
		"options": [{"id": "stool", "text": "It's Kettle's stool", "set": {"crate": "covered"}},
			{"id": "declare", "text": "Declare it", "set": {"crate": "declared"}, "stars": 4, "credits": 30,
				"prop": {"crate": false}, "toast": "Declared. Tolle takes the crate. +30 cr, +4 ★ for civic spirit."}],
		"must_choose": true},
	"seven_waking": {"who": "hermit", "day": 7, "phase": "morning", "trigger": "", "need": {},
		"lines": ["...The Yards are waking.", "Watch the Glasspan. Find what fell."],
		"options": [{"id": "ok", "text": "I'll look"}]},
	"rook_pickup": {"who": "rook", "day": 8, "phase": "morning", "trigger": "", "need": {"crate": ["kept", "covered"]},
		"lines": ["Still in one piece? You're a legend.", "It's the Low Moons' old reels. The Tally Office hates a good tune."],
		"set": {"crate": "delivered", "band": true}, "prop": {"crate": false},
		"toast": "The band owes you. Today they play at your door.",
		"options": [{"id": "ok", "text": "Enjoy the music"}]},
	"band_lune": {"who": "singer", "day": 8, "phase": "morning", "trigger": "", "need": {"band": [false, null]},
		"need_fix": 2, "lines": ["You fixed our song box, darling.", "Today the Low Moons play at your door."],
		"set": {"band": true}, "toast": "The Low Moons play at your door today.",
		"options": [{"id": "ok", "text": "Lovely"}]},
	"seven_cores": {"who": "hermit", "day": 8, "phase": "open", "trigger": "after_handover", "need": {}, "min_stars": 2,
		"lines": ["Little kettle. You poured tea for the night shift.", "You were always early."],
		"lines_low": ["...Not yet. The sky is patient.", "...Another night, then."],
		"core": "seven8", "toast": "Kettle whistles a tune nobody has heard before.",
		"options": [{"id": "ok", "text": "Goodnight, Seven"}], "options_low": [{"id": "ok", "text": "Goodbye"}]},
	"clatter_job": {"who": "clatter", "day": 6, "phase": "night", "trigger": "", "need": {}, "need_clatter": true,
		"lines": ["I have run out of savings. And of things to break.", "May I work here? I sweep. Slowly."],
		"options": [{"id": "hire", "text": "Welcome aboard", "set": {"clatter_job": true}, "prop": {"clatter": true},
				"toast": "Clatter sweeps the shop. The line waits a little longer."},
			{"id": "no", "text": "Not just now", "reply": "Understood. I will sweep outside. For free."}],
		"must_choose": true},
	"rook_key": {"who": "rook", "day": 9, "phase": "night", "trigger": "", "need": {"crate": ["delivered"]},
		"lines": ["Won the pilots' heat. On luck and your solder.", "Keep the key. It starts anything. Mostly."],
		"set": {"rook_key": true}, "bonus": 6, "prop": {"key": true},
		"toast": "Rook's lucky key goes on the trophy shelf. +6 ★ tomorrow.",
		"options": [{"id": "ok", "text": "Thanks, Rook"}]},
}
## El orden en que se miran los momentos de una misma fase.
const BEAT_ORDER := ["crate_ask", "rival_hello", "seven_waking", "rook_pickup", "band_lune", "seven_first",
	"seven_cores", "glint_favour", "tolle_crate", "clatter_job", "rook_key"]
const TOLLE_CRATE_AFTER := {"kept": "Stools are exempt under Form Six. Lucky stool. Carry on.",
	"seized": "Confiscated. Form Nine.", "seized_stars": -5}
const CORE_TOAST := "A lamp core. It glows when nobody's looking."

## Lo que dice el retrato de quien habla en un momento de historia (en vez de la especie).
const ROLE_SUB := {"rival": "Shine Again, next door", "inspector": "Tally Office", "hermit": "Lamp-keeper of the Yards",
	"singer": "Singer at the Slow Orbit", "vendor": "Fittings", "rook": "Pilot", "dockmaster": "Dock dues",
	"timekeeper": "The port's timekeeper", "tracker": "Tally Office warden", "kettle": "Your kettle"}

## La visita a la vecina (estación "rival" de la calle, desde el día 3): su frase según quién va delante.
const RIVAL_VISIT := {"ahead": "Back on top, sweetie. It's the sparkle.", "behind": "You passed me? Hm. Buff, polish faster.",
	"neutral": "Shine sells, sweetie. Fix... also sells. Annoyingly.",
	"closed": "Shine Again opens on day 3. The poster says so. Loudly."}

## Textos sueltos de la temporada (§5.6 y la interfaz de S).
const INTRO := [
	"Every night, the old shipyard in the sky drops a little more of itself on Saffra.",
	"At dawn the Rakers sell what fell. Nell fixes it, and sells it secondhand.",
	"Out in the Amber Drift, thirty shops chase the same light: the top of the Lantern Board.",
	"Nell's shop is thirtieth. And the dock dues are due. No pressure.",
]
const TIPS := {
	"board": "The Lantern Board: thirty shops. Every happy customer is a star. {board} Board.",
	"fittings": "Fittings show up in the shop and help every day.",
	"dues": "Dues come in three parts. The bar shows the next one.",
	"asis": "Mags's as-is bin: cheap broken things to fix and sell.",
	"close": "Nobody left? {key} Close up early at the counter.",
	"graded": "Tolle grades this one. Take your time.",
	"deadline": "Racers leave at 2:30 PM. Fix their thrusters first.",
	"afterhours": "After hours: fix junk for the shelf. No clock, no line.",
	"migrated": "New: a 10-day season, the Lantern Board and fittings. Dues now come in three parts.",
}
const TEXT := {
	"dues_note_d1": "Dock dues come in three parts: 100 on night 3, 200 on night 6, 300 on night 9.",
	"after_title": "After hours",
	"after_line": "The line's gone. The moons are up. One more?",
	"after_sleep": "Sleep",
	"after_done": "Kettle's asleep. So should you be.",
	"close_line": "Nobody's left and nobody's coming. Close up early?",
	"close_yes": "Close up",
	"close_no": "Not yet",
	"raker_storm": "Too windy for pods. The tortoise refuses.",
	"raker_charity": "On the house. Pay me back in stories.",
	"mags_asis": "As-is. No refunds, no questions, no idea.",
	"mags_storm": "Storm sale! Everything's two off. The sand gets in anyway.",
	"mags_eve": "Bronzemoon tomorrow. Clearing the bin, cheap. Fix fast, sell high.",
	"choose_one": "Choose one: 1 or 2",
	"choose_one_pad": "Choose one: point at it and press A",
	"prototype_over": "The prototype is over. A whole season awaits: New game.",
	"title_footer": "Season one  ·  keyboard, mouse or pad",
	"signal_counting": "The Signal is counting...",
	"board_stub": "The Lantern Board opens tonight.",
	"endless_title": "Keep trading",
	"upkeep_sub": "Dock upkeep",
}
## Las líneas del cartel de la estrella (una punta por cada hito del tablero, §3.7).
const SIGN_LINES := ["", "One point lit. Rustwater noticed.", "Two points. The Raker waves first now.",
	"Top ten in the Drift. Kettle is unbearable.", "Four points. Glint bought sunglasses.",
	"All five. And something brass on the way."]
