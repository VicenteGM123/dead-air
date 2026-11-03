extends RefCounted
## --- SS2 RANK: las demos y pruebas de la línea R (main._lane_demo las llama: static handles(name) / run(main, name);
## antes del JOIN corren con scripts/demos/rank_stage.tscn, que es main.gd con este gancho):
##   ranktest      presupuestos de texto (§8.7), la tabla, commit idempotente, guardar / cargar, rebuild_from_history,
##                 la rival (margen, mudanza, favor, globo), el x2 de la final, LATE, el premio, los Reports, ordinales,
##                 la búsqueda de palabras prohibidas (§10.3) en los textos de Ranking
##   rankui        las pantallas por su API y por teclas de verdad (Esc, E, R, flechas): abrir, saltar, cerrar, auto,
##                 la señal done una vez por pantalla
##   ranksim       --sims=500 --profile=human|good|perfect|sloppy|all [--table=<json>] [--days=10] [--seed0=N]
##                 el modelo del Board con las estrellas por día de cada perfil (PROVISIONAL hasta que S publique su
##                 STARS TABLE; --table=<json> {"human": [[media, sd], ...] x 12 días, ...} la reemplaza)
##   rank_night    el tablero de la noche (noche 6 de una partida buena) con el split-flap, después de que asienta
##   rank_board    el tablero entero (día 7, mañana) con la fila de Nell elegida
##   rank_board_pad  el mismo con el mando (avisos "(B)", cursor sobre una fila)
##   report_1..4   el Lantern Report de las noches 3, 6, 9 y 12 (el primero del modo sin fin)
## Capturas: --shot=<png> --frames=<n> (main.gd las guarda). --step=flip captura el tablero a medio girar.

const NAMES := ["ranktest", "ranksim", "rankui", "rank_night", "rank_board", "rank_board_pad", "report_1", "report_2", "report_3",
	"report_4", "rank_night_late", "rank_night_top", "gala_win", "gala_lose", "gala_far", "galatest"]

## Las estrellas por día de cada perfil (provisional, §4.6: los días medidos del prototipo + el diseño): base = el día
## sin eventos ni el x2 (atendidos + estrellas + limpio + atractivo − perdidos), ev = estrellas de eventos (certificado,
## banda, Derby), sd = desvío relativo de un día, run_sd = desvío del jugador entero (un buen día suele venir con otro),
## key = probabilidad de la llave de Rook (+6, noche 10), favour = probabilidad del favor a Glint (+8 para ella, noche 5).
## La noche 10 (la Great Starfall) vale (base + ev) x 2. S publica la tabla medida (STARS TABLE) y --table la usa.
const PROVISIONAL := {
	"perfect": {"base": [27, 33, 36, 36, 29, 39, 41, 41, 44, 46, 44, 44], "ev": [0, 0, 0, 0, 0, 8, 0, 4, 10, 0, 0, 0],
		"sd": 0.08, "run_sd": 0.03, "key": 1.0, "favour": 1.0},
	"good": {"base": [24, 29, 32, 32, 26, 35, 37, 37, 40, 42, 40, 40], "ev": [0, 0, 0, 0, 0, 7, 0, 4, 9, 0, 0, 0],
		"sd": 0.12, "run_sd": 0.04, "key": 0.9, "favour": 1.0},
	"human": {"base": [20, 24, 27, 27, 22, 30, 31, 31, 34, 36, 34, 34], "ev": [0, 0, 0, 0, 0, 4, 0, 3, 6, 0, 0, 0],
		"sd": 0.15, "run_sd": 0.05, "key": 0.5, "favour": 0.5},
	"sloppy": {"base": [13, 15, 16, 16, 14, 18, 18, 19, 20, 22, 20, 20], "ev": [0, 0, 0, 0, 0, 1, 0, 1, 2, 0, 0, 0],
		"sd": 0.20, "run_sd": 0.06, "key": 0.2, "favour": 0.5},
}
const PROFILES := ["perfect", "good", "human", "sloppy"]
## Con --table (las estrellas medidas por S / el JOIN, que ya traen los eventos dentro): las estrellas de eventos
## medidas por noche (certificado 8 / aprobado 3 + caja declarada 4 la noche 6, la banda 4 la noche 8, el Derby 10 / 4
## la noche 9), solo para separar la "base" del margen de Glint; key / favour = lo que hicieron los bots del JOIN.
const EV_MEASURED := {
	"perfect": {"ev": [0, 0, 0, 0, 0, 6, 0, 4, 10, 0, 0, 0], "key": 1.0, "favour": 1.0},
	"good": {"ev": [0, 0, 0, 0, 0, 6, 0, 4, 10, 0, 0, 0], "key": 1.0, "favour": 1.0},
	"human": {"ev": [0, 0, 0, 0, 0, 7, 0, 3, 10, 0, 0, 0], "key": 0.5, "favour": 0.5},
	"sloppy": {"ev": [0, 0, 0, 0, 0, 4, 0, 0, 4, 0, 0, 0], "key": 0.0, "favour": 1.0},
}

## (§10.3) palabras que no pueden aparecer en ningún texto del Board.
const FORBIDDEN := ["droid", "jedi", "sith", "lightsaber", "blaster", "tatooine", "mos", "jawa", "tusken", "raider",
	"sand people", "sandcrawler", "podrace", "podracer", "speeder", "landspeeder", "swoop", "vaporator", "moisture farm",
	"cantina", "hutt", "wookiee", "ewok", "gungan", "holonet", "holocron", "hologram", "hyperspace", "hyperdrive",
	"lightspeed", "parsec", "repulsor", "spice", "sabacc", "kessel", "corellian", "mandalorian", "mando", "coruscant",
	"naboo", "endor", "hoth", "dagobah", "jakku", "skywalker", "kenobi", "falcon", "x-wing", "tie fighter",
	"death star", "star destroyer", "wayfinder", "outer rim", "mid rim", "inner rim", "core worlds", "wild space",
	"senate", "empire", "imperial", "rebel", "rebels", "republic", "moff", "trooper", "bounty", "astromech",
	"protocol bot", "power converter", "bacta", "carbonite", "kyber", "beskar", "nerf", "bantha", "dewback", "krayt",
	"womp rat", "mynock", "porg", "concord", "hammerhead", "bellwether", "hitchhiker", "fix-it", "saltmarch",
	"saltmarsh", "dustline", "lumi", "fennick", "collector", "42"]

static func handles(name: String) -> bool:
	return name in NAMES

static func run(m, name: String) -> void:
	match name:
		"ranktest":
			await _ranktest(m)
		"ranksim":
			await _ranksim(m)
		"rankui":
			await _rankui(m)
		"galatest":
			await _galatest(m)
		"gala_win", "gala_lose", "gala_far":
			await _gala_demo(m, name)
		_:
			await _screen_demo(m, name)

static func arg(key: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

# ================================================================== ranktest

static func _ranktest(m) -> void:
	var fails: Array = []
	var checks := [0]
	var chk := func(ok: bool, what: String) -> void:
		checks[0] += 1
		if not ok:
			fails.append(what)
			print("RANKTEST FAIL ", what)
	var R = Ranking
	R.debug_flags = {}
	# --- la tabla
	chk.call(R.SHOPS.size() == 30, "30 tiendas (%d)" % R.SHOPS.size())
	var ids := {}
	for s in R.SHOPS:
		ids[String(s["id"])] = true
		chk.call(String(s["name"]).length() <= 24, "nombre ≤ 24: %s" % s["name"])
		chk.call(String(s["owner"]).length() <= 22, "dueño ≤ 22: %s" % s["owner"])
		chk.call(String(s["line"]).length() <= 60, "frase ≤ 60: %s" % s["line"])
		chk.call(R.WORLDS.has(String(s["world"])), "mundo de %s" % s["id"])
		chk.call(R.CURVES.has(String(s["curve"])) or String(s["curve"]) in ["champion", "rival", "player"], "curva de %s" % s["id"])
	chk.call(ids.size() == 30 and ids.has(R.ME) and ids.has(R.RIVAL) and ids.has(R.CHAMPION) and ids.has(R.SCRIMP), "ids únicos y los cuatro de siempre")
	chk.call(String(R.SHOPS[-1]["id"]) == R.ME, "Nell la última de SHOPS (escudo 30)")
	for w in R.WORLDS:
		chk.call(String(R.WORLDS[w]["name"]).length() <= 14, "mundo ≤ 14: %s" % w)
		chk.call(String(R.WORLDS[w]["line"]).length() <= 70, "línea del mundo ≤ 70: %s" % w)
	R.reset(77)
	chk.call(R.position() == 30 and R.score() == 0, "empieza #30 con 0")
	var t0: Array = R.table()
	chk.call(t0.size() == 30 and String(t0[0]["id"]) == R.CHAMPION, "el campeón arriba al empezar")
	var sorted_ok := true
	for i in range(1, t0.size()):
		if int(t0[i]["score"]) > int(t0[i - 1]["score"]) or int(t0[i]["pos"]) != i + 1:
			sorted_ok = false
	chk.call(sorted_ok, "tabla ordenada")
	chk.call(R.milestone_points() == 0 and R.next_above().get("gap", 0) > 0, "sin puntas, alguien arriba")
	# --- las estrellas del día (el ejemplo de §3.4: 9 + 12 + 9 + 8 + 0 + 5 − 1 = 42)
	var ex := {"served": 9, "repairs": 5, "sales": 4, "repair_stars": 12, "sale_stars": 9, "event_stars": 8,
		"walkouts": 1, "appeal": 5, "stars_k": 1.0}
	var dsx: Dictionary = R.day_stars(ex)
	chk.call(int(dsx["total"]) == 42 and int(dsx["base"]) == 34, "el ejemplo de §3.4 = 42 (base 34): %s" % str(dsx))
	var bd: String = R.breakdown({"stars": 42, "parts": dsx["parts"]})
	# --- POLISH FIX (F10): cada parte con signo y estrella ("repairs 17" parecía una cantidad)
	chk.call(bd.begins_with("Tonight +42 ★ · repairs +17★ · sales +13★ · events +8★ · fittings +5★"), "el desglose: %s" % bd)
	ex["stars_k"] = 2.0
	chk.call(int(R.day_stars(ex)["total"]) == 84, "la final x2")
	# --- commit idempotente y el primer movimiento
	var day0 := Game.day
	var today0: Dictionary = Game.today.duplicate(true)
	Game.day = 1
	Game.today = {"served": 6, "repairs": 5, "sales": 1, "repair_stars": 13, "sale_stars": 2, "appeal": 0, "stars_k": 1.0}
	var mv: Dictionary = R.commit_day()
	var mv2: Dictionary = R.commit_day()
	chk.call(mv == mv2 and R.nights == 1, "commit idempotente")
	chk.call(int(mv["stars"]) == 24 and int(mv["pos"]) < 30 and int(mv["delta"]) == 30 - int(mv["pos"]), "noche 1: %s" % str(mv.get("pos")))
	chk.call(String(mv["line"]).begins_with("New on the Board") and String(mv["line"]).length() <= 80, "la línea de la noche 1: %s" % mv["line"])
	chk.call(R.table(true).size() == 30 and int(R.row(R.ME, true)["pos"]) == 30, "la tabla de antes (prev)")
	# --- guardar / cargar (JSON de ida y vuelta)
	for n in range(2, 6):
		Game.day = n
		Game.today = {"served": 8, "repairs": 6, "sales": 2, "repair_stars": 16, "sale_stars": 5, "appeal": 2, "stars_k": 1.0}
		R.commit_day()
	var sd: Dictionary = R.save_data()
	var js := JSON.stringify(sd)
	var tab_before := JSON.stringify(R.table())
	var mv_before := JSON.stringify(R.last_move())
	R.reset(5)
	R.load_data(JSON.parse_string(js))
	chk.call(JSON.stringify(R.table()) == tab_before, "la tabla cargada")
	chk.call(JSON.stringify(R.last_move()) == mv_before, "el último movimiento cargado")
	chk.call(R.committed == 5 and R.nights == 5 and R.path().size() == 5, "noches cargadas")
	Game.day = 5
	chk.call(R.commit_day() == R.last_move(), "commit después de cargar = el mismo")
	# --- rebuild_from_history (una partida del prototipo)
	var hst := [{"day": 1, "repairs": 5, "sales": 1, "stars": 13, "walkouts": 0, "missed": 0},
		{"day": 2, "repairs": 6, "sales": 2, "stars": 15, "walkouts": 1, "missed": 3}]
	R.rebuild_from_history(hst)
	chk.call(R.committed == 2 and R.score() == (5 + 1 + 13 + 2) + (6 + 2 + 15 + 4 - 1 - 2), "rebuild_from_history (%d)" % R.score())
	# --- la rival: mudanza sin margen, margen las demás noches, el favor (+8), el globo, sin x2 en la final
	R.reset(9)
	var base := 30
	var rv: Array = []
	for n in range(1, 11):
		if n == 5:
			R.add_bonus(R.RIVAL, 8)
		var before := float(R.scores[R.RIVAL])
		var me_before := float(R.scores[R.ME])
		var fin := n == 10
		R._commit(n, base * (2 if fin else 1), base, {})
		rv.append(float(R.scores[R.RIVAL]) - before)
		if n == 8:
			chk.call(R.balloon in ["talk", "popped"], "el globo de la noche 8")
			var led := me_before > float(R.prev_scores[R.RIVAL])
			chk.call((R.balloon == "talk") == led, "el globo sigue a quién iba delante")
	chk.call(rv[2] < 0.85 * base, "noche 3: la mudanza sin margen (%.1f)" % rv[2])
	for n in [0, 1, 3, 5, 6, 8]:
		chk.call(rv[n] >= 0.85 * base - 0.01 and rv[n] <= 1.05 * base + 0.01, "noche %d: la rival dentro del margen (%.1f)" % [n + 1, rv[n]])
	chk.call(rv[4] >= 0.85 * base + 8 - 0.01 and rv[4] <= 1.05 * base + 8.01, "noche 5: el favor de Buff (+8)")
	chk.call(rv[9] <= 1.05 * base + 0.01, "noche 10: la rival no dobla (%.1f)" % rv[9])
	# Dune Pocket dobla la noche 10
	R.reset(9)
	var dp: Array = []
	for n in range(1, 11):
		var b0 := float(R.scores[R.SCRIMP])
		R._commit(n, 20, 20, {})
		dp.append(float(R.scores[R.SCRIMP]) - b0)
	chk.call(dp[9] > dp[8] * 1.6, "Dune Pocket dobla la noche 10 (%.1f -> %.1f)" % [dp[8], dp[9]])
	# --- el campeón: el escándalo de la noche 7
	R.reset(3)
	var ch: Array = []
	for n in range(1, 11):
		var c0 := float(R.scores[R.CHAMPION])
		R._commit(n, 20, 20, {})
		ch.append(float(R.scores[R.CHAMPION]) - c0)
	chk.call(ch[6] < 8 * 0.75 * 1.07 and ch[5] > 30 * 0.75, "el escándalo de la noche 7 (%.1f)" % ch[6])
	# --- LATE: el sello 3 noches y −3 una vez en la próxima noche
	R.reset(4)
	R._commit(1, 20, 20, {})
	R.mark_late()
	chk.call(bool(R.row(R.ME)["late"]), "LATE en la fila")
	var s0 := R.score()
	var lm: Dictionary = R._commit(2, 20, 20, {})
	chk.call(R.score() - s0 == 17 and int(lm["late"]) == -3, "LATE −3 una vez")
	R._commit(3, 20, 20, {})
	chk.call(bool(R.row(R.ME)["late"]), "LATE sigue la noche 3")
	R._commit(4, 20, 20, {})
	chk.call(not bool(R.row(R.ME)["late"]), "LATE se va después de 3 noches")
	# --- bonos (la llave de Rook)
	R.reset(4)
	R.add_bonus(R.ME, 6)
	var bm: Dictionary = R._commit(1, 20, 20, {})
	chk.call(int(bm["stars"]) == 26 and int(bm["bonus"]) == 6, "el bono de Nell")
	# --- hitos y premio
	R.reset(4)
	R.best_pos = 12
	chk.call(R.milestone_points() == 2, "hitos: top 15 = 2 puntas")
	R.best_pos = 1
	chk.call(R.milestone_points() == 5, "hitos: #1 = 5 puntas")
	R.reset(4)
	for n in range(1, 4):
		R._commit(n, 5, 5, {})
	var aw: Dictionary = R.award()
	chk.call(String(aw["id"]) == "newshop" and int(aw["place"]) >= 16, "premio por puesto bajo: %s" % str(aw))
	R.scores[R.ME] = 10000.0
	chk.call(String(R.award()["id"]) == "champion" and R.position() == 1, "premio campeón")
	chk.call(R.next_above().is_empty(), "nadie arriba del #1")
	# --- report_due: noches 3, 6, 9 y 12, 15...; nunca 10 ni 11
	var due: Array = []
	for n in range(1, 19):
		Game.day = n
		R.reports_read = []
		if R.report_due():
			due.append(n)
	chk.call(due == [3, 6, 9, 12, 15, 18], "noches del Report: %s" % str(due))
	# --- los Reports: 7 líneas ≤ 70 (con los nombres más largos y con las variantes de las marcas)
	var flag_sets := [{}, {"crate": "kept", "grade": "certified", "race": "podium", "cores": 3, "favour": "done"},
		{"crate": "refused", "grade": "noted", "race": "finished", "cores": 1}]
	for fs in flag_sets:
		R.debug_flags = fs
		R.reset(21)
		for n in range(1, 19):
			R._commit(n, 25 + n, 25 + n, {})
			if n % 3 == 0 and n != 10:
				Game.day = n
				var rep: Dictionary = R.report(n)
				chk.call(rep["lines"].size() == 7, "Report de la noche %d: 7 líneas" % n)
				for ln in rep["lines"]:
					chk.call(String(ln["text"]).length() <= 70 and String(ln["text"]).length() > 8, "Report %d ≤ 70: %s" % [n, ln["text"]])
					chk.call(not "{" in String(ln["text"]), "Report %d sin huecos: %s" % [n, ln["text"]])
				chk.call(String(rep["lines"][6]["text"]) == R.SIGNOFF, "la despedida")
	R.debug_flags = {}
	# los moldes con los nombres más largos posibles (24 / 22 / 14 letras, 3 cifras, el ordinal más largo)
	var longest := {"first": "X".repeat(24), "mover": "X".repeat(24), "leader": "X".repeat(24), "gap": "999",
		"grade": "Satisfactory", "winner": "X".repeat(12), "s": "X".repeat(24), "o": "X".repeat(22), "w": "X".repeat(14),
		"n": "999"}
	var long_ord := ""
	for w in R.ORD:
		if String(w).length() > long_ord.length():
			long_ord = String(w)
	for tbl in [R.REPORT1, R.REPORT2, R.REPORT3]:
		for k in tbl:
			var vals := longest.duplicate()
			if "{o}" in String(tbl[k]) and not "{s}" in String(tbl[k]):
				vals["o"] = long_ord
			chk.call(R.fill(tbl[k], vals).length() <= 70, "molde del Report ≤ 70: %s" % tbl[k])
	for pool in [R.POOL_TOP, R.POOL_TOP_ME, R.POOL_HEADLINES, R.POOL_SCANDALS, R.POOL_ADS, [R.POOL_NELL, R.WEATHER_CLEAR]]:
		for k in pool:
			var vals2 := longest.duplicate()
			if k == R.POOL_NELL:
				vals2["o"] = long_ord
			chk.call(R.fill(k, vals2).length() <= 70, "molde del pool ≤ 70: %s" % k)
	for k in R.SCANDALS_BY:
		chk.call(String(R.SCANDALS_BY[k]).length() <= 70, "escándalo ≤ 70: %s" % k)
	for k in R.ROSA:
		var t: String = R.fill(R.ROSA[k], {"n": "29", "o": long_ord, "O": long_ord.capitalize()})
		chk.call(t.length() <= 80, "Rosa ≤ 80: %s" % t)
	for k in R.MILESTONE_LINES:
		chk.call(String(k).length() <= 60, "línea de hito ≤ 60: %s" % k)
	for k in R.RANK_CHATTER:
		for ln in R.RANK_CHATTER[k]:
			chk.call(String(ln).length() <= 60, "comentario de cliente ≤ 60: %s" % ln)
	chk.call(R.ord_word(27) == "twenty-seventh" and R.ord_word(1) == "first" and R.ord_word(31) == "31st", "ordinales")
	# --- palabras prohibidas en todos los textos de Ranking (constantes)
	var consts: Dictionary = (R.get_script() as Script).get_script_constant_map()
	var texts: Array = []
	_collect_texts(consts, texts)
	var bad := []
	for tx in texts:
		var low := String(tx).to_lower()
		for wd in FORBIDDEN:
			var re := RegEx.create_from_string("(^|[^a-z0-9])" + String(wd).replace("-", "\\-") + "($|[^a-z0-9])")
			if re.search(low):
				bad.append("%s in «%s»" % [wd, tx])
	chk.call(bad.is_empty(), "palabras prohibidas: %s" % str(bad))
	# --- ending_due
	R.reset(4)
	Game.day = R.LAST_DAY
	chk.call(R.ending_due() or Game.get("ending_seen") == true, "la noche 10 es la del cometa")
	# --- fast_forward
	R.reset(4)
	R.fast_forward(6, [22, 26, 30, 32, 30, 42])
	chk.call(R.committed == 6 and R.nights == 6, "fast_forward 6 noches")
	# --- simulate no toca la partida
	var keep := JSON.stringify(R.save_data())
	var sim: Array = R.simulate(10, func(_n): return 30)
	chk.call(sim.size() == 10 and JSON.stringify(R.save_data()) == keep, "simulate no toca la partida")
	Game.day = day0
	Game.today = today0
	R.reset(Game.run_seed)
	print("RANKTEST %s checks=%d fails=%d" % ["ok" if fails.is_empty() else "FAILED", checks[0], fails.size()])
	m.quit_clean(0 if fails.is_empty() else 1)

static func _collect_texts(v, out: Array) -> void:
	if v is String:
		if " " in v or v.length() > 3:
			out.append(v)
	elif v is Dictionary:
		for k in v:
			_collect_texts(v[k], out)
	elif v is Array:
		for x in v:
			_collect_texts(x, out)

# ================================================================== ranksim

## Las estrellas de Nell de cada noche para una corrida (perfil + RNG): [{"total", "base", "key", "favour"}].
static func _nell_days(p: Dictionary, r: RandomNumberGenerator, days: int, table = null) -> Array:
	var out: Array = []
	var skill := 1.0 + r.randfn(0.0, float(p["run_sd"]))
	var key := r.randf() < float(p["key"])
	var favour := r.randf() < float(p["favour"])
	for i in days:
		var k := 2.0 if i + 1 == Ranking.LAST_DAY else 1.0
		var ev_m := float(p["ev"][mini(i, p["ev"].size() - 1)])
		var ev := maxf(0.0, ev_m * (1.0 + r.randfn(0.0, 0.35))) if ev_m > 0 else 0.0
		var base: float
		if table != null:
			# la tabla medida de S: [media, sd] del total (la final ya x2)
			var row: Array = table[mini(i, table.size() - 1)]
			var tot := float(row[0]) * skill + r.randfn(0.0, float(row[1]))
			base = maxf(0.0, tot / k - ev)
		else:
			var b := float(p["base"][mini(i, p["base"].size() - 1)])
			base = maxf(0.0, b * skill * (1.0 + r.randfn(0.0, float(p["sd"]))))
		var total := int(round((base + ev) * k))
		out.append({"total": total, "base": int(round(base)), "key": key, "favour": favour})
	return out

static func _ranksim(m) -> void:
	var sims := int(arg("sims", "500"))
	var days := int(arg("days", "10"))
	var prof := arg("profile", "all")
	var seed0 := int(arg("seed0", "1000"))
	var tables := {}
	var tpath := arg("table", "")
	if tpath != "":
		var raw = JSON.parse_string(FileAccess.get_file_as_string(tpath))
		if raw is Dictionary:
			tables = raw
			print("RANKSIM table ", tpath, " profiles ", tables.keys())
	var profs: Array = PROFILES if prof == "all" else [prof]
	var R = Ranking
	var keep := R.save_data()
	print("RANKSIM sims=%d days=%d SCALE=%.2f champion=%s rival_start=%d script=%s" % [sims, days, R.SCALE,
		str(R.CHAMPION_PACE), int(R.shop(R.RIVAL)["start"]), str(R.RIVAL_SCRIPT)])
	for pf in profs:
		var p: Dictionary = PROVISIONAL[pf].duplicate(true)
		var tb = tables.get(pf, null)
		if tb != null:
			p.merge(EV_MEASURED[pf], true)
		var firsts := {20: [], 15: [], 10: [], 5: [], 1: []}
		var final_pos: Array = []
		var totals: Array = []
		var champ10: Array = []
		var other10: Array = []
		var rival_gap9: Array = []
		var rival_gap3: Array = []
		var glint_first_pass: Array = []
		var swaps: Array = []
		var guard_bad := 0
		var all10: Array = []
		var glint_beats := 0
		var first1_min := 99
		var per_night_pos := []
		var per_night_gap := []
		for n in days:
			per_night_pos.append([])
			per_night_gap.append([])
		for i in sims:
			var r := RandomNumberGenerator.new()
			r.seed = seed0 + i * 7919
			var nd := _nell_days(p, r, days, tb)
			var fn := func(night: int):
				var d: Dictionary = nd[night - 1]
				if night == 5 and bool(d["favour"]):
					R.add_bonus(R.RIVAL, 8)
				if night == R.LAST_DAY and bool(d["key"]):
					R.add_bonus(R.ME, 6)
				return d
			var res: Array = R.simulate(days, fn, seed0 + i)
			var got := {20: 0, 15: 0, 10: 0, 5: 0, 1: 0}
			var lead_prev := false
			var sw := 0
			var first_pass := 0
			for row in res:
				var nn := int(row["night"])
				for mk in got:
					if got[mk] == 0 and int(row["pos"]) <= int(mk):
						got[mk] = nn
				per_night_pos[nn - 1].append(int(row["pos"]))
				per_night_gap[nn - 1].append(int(row["rival_gap"]))
				var lead := int(row["rival_gap"]) < 0
				if nn >= 3:
					if lead and first_pass == 0:
						first_pass = nn
					if nn > 3 and lead != lead_prev:
						sw += 1
					lead_prev = lead
				if nn == 3:
					rival_gap3.append(int(row["rival_gap"]))
				if nn == 9:
					rival_gap9.append(int(row["rival_gap"]))
			for mk in got:
				firsts[mk].append(got[mk] if got[mk] > 0 else 99)
			var last: Dictionary = res[mini(days, R.LAST_DAY) - 1]
			final_pos.append(int(last["pos"]))
			totals.append(int(last["score"]))
			var sc: Dictionary = last["scores"]
			var sc_me := sc.duplicate()
			sc_me[R.ME] = float(last["score"])
			all10.append(sc_me)
			champ10.append(int(round(float(sc[R.CHAMPION]))))
			var mx := 0.0
			for id in sc:
				if id != R.CHAMPION and id != R.ME and id != R.RIVAL:
					mx = maxf(mx, float(sc[id]))
			other10.append(int(round(mx)))
			if mx > float(sc[R.CHAMPION]):
				guard_bad += 1
			if float(sc[R.RIVAL]) > float(sc[R.ME]):
				glint_beats += 1
			first1_min = mini(first1_min, got[1] if got[1] > 0 else 99)
			glint_first_pass.append(first_pass if first_pass > 0 else 99)
			swaps.append(sw)
		var p1 := 0
		var p815 := 0
		for fp in final_pos:
			if fp == 1:
				p1 += 1
			if fp >= 8 and fp <= 15:
				p815 += 1
		var within15 := 0
		for g in rival_gap9:
			if absi(int(g)) <= 15:
				within15 += 1
		print("RANKSIM %-7s P(#1 n10)=%5.1f%%  first top20 %s · top15 %s · top10 %s · top5 %s · #1 %s" % [pf,
			100.0 * p1 / sims, _q(firsts[20]), _q(firsts[15]), _q(firsts[10]), _q(firsts[5]), _q(firsts[1])])
		print("RANKSIM %-7s night-10 place %s (#8-#15 %4.1f%%) · Nell total %s · Gilded Gear %s (bar = %.0f%% of Nell's median) · best other (not Glint) %s · guard broken %d/%d · Glint above Nell at n10 %d/%d · earliest #1 night %s" % [pf,
			_q(final_pos), 100.0 * p815 / sims, _q(totals, false), _q(champ10, false), 100.0 * _med(champ10) / maxf(1.0, _med(totals)),
			_q(other10, false), guard_bad, sims, glint_beats, sims, "never" if first1_min >= 99 else str(first1_min)])
		print("RANKSIM %-7s Glint gap after n3 %s · before the finale (n9) %s (within ±15: %4.1f%%) · Nell first leads Glint %s · lead swaps %s" % [pf,
			_q(rival_gap3, false), _q(rival_gap9, false), 100.0 * within15 / sims, _q(glint_first_pass), _q(swaps)])
		# --- SS2 MERGE: cuántas corridas llegan al #1 por primera vez en cada noche (la cola de "nunca antes de la 8")
		var fd := {}
		for f1 in firsts[1]:
			fd[int(f1)] = int(fd.get(int(f1), 0)) + 1
		var fl := "RANKSIM %-7s first #1 by night:" % pf
		var ks: Array = fd.keys()
		ks.sort()
		for k in ks:
			fl += " %s=%d" % ["never" if int(k) >= 99 else "n%d" % int(k), int(fd[k])]
		print(fl)
		# --- end SS2 MERGE
		var line := "RANKSIM %-7s median place by night:" % pf
		var gl := "RANKSIM %-7s median Glint gap by night:" % pf
		for n in days:
			line += " %d" % int(_med(per_night_pos[n]))
			gl += " %+d" % int(_med(per_night_gap[n]))
		print(line)
		print(gl)
		if pf == profs[0] or pf == "sloppy":
			var med_line := "RANKSIM %-7s median night-10 scores:" % pf
			var meds: Array = []
			for s in R.SHOPS:
				var sid := String(s["id"])
				var arr: Array = []
				for sc10 in all10:
					arr.append(int(round(float(sc10.get(sid, 0.0)))))
				meds.append([_med(arr), sid])
			meds.sort_custom(func(a, b): return a[0] > b[0])
			for mm in meds:
				med_line += " %s %d ·" % [mm[1], int(mm[0])]
			print(med_line)
	R.load_data(keep)
	m.quit_clean(0)

static func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

## "med [p10-p90]" de una lista de enteros (con nights: 99 = nunca).
static func _q(a: Array, nights := true) -> String:
	if a.is_empty():
		return "-"
	var b := a.duplicate()
	b.sort()
	var f := func(x): return "never" if (nights and int(x) >= 99) else str(int(x))
	return "%s [%s-%s]" % [f.call(b[b.size() / 2]), f.call(b[int(b.size() * 0.1)]), f.call(b[mini(b.size() - 1, int(b.size() * 0.9))])]


# ================================================================== rankui

static func _key(tree: SceneTree, code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await tree.process_frame

static func _rankui(m) -> void:
	var tree: SceneTree = m.get_tree()
	var fails: Array = []
	var chk := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
			print("RANKUI FAIL ", what)
	var rs := screens(m)
	var dones := [0]
	rs.done.connect(func(): dones[0] += 1)
	Game.day = 6
	var mv := play_to(6, "good", 11)
	await tree.process_frame
	# el tablero de la noche: E antes de 1.5 s no cierra; Esc salta la animación; Esc otra vez cierra
	rs.open_night(mv)
	await tree.process_frame
	chk.call(rs.is_open(), "night abierto")
	await _key(tree, KEY_E)
	chk.call(rs.is_open() and rs._animating, "E antes de 1.5 s no hace nada")
	await _key(tree, KEY_ESCAPE)
	chk.call(rs.is_open() and not rs._animating, "Esc salta el giro")
	await _key(tree, KEY_E)
	chk.call(rs.is_open(), "E antes de 1.5 s no cierra")
	await tree.create_timer(1.6).timeout
	await _key(tree, KEY_E)
	chk.call(not rs.is_open() and dones[0] == 1, "E después de 1.5 s cierra (done %d)" % dones[0])
	# press(): next salta y después cierra; close cierra
	rs.open_night(mv)
	rs.press("next")
	chk.call(rs.is_open(), "press(next) primero termina el giro")
	rs.press("next")
	chk.call(not rs.is_open() and dones[0] == 2, "press(next) después cierra")
	# auto: se cierra solo
	rs.auto = true
	rs.open_night(mv)
	var t0 := Time.get_ticks_msec()
	while rs.is_open() and Time.get_ticks_msec() - t0 < 9000:
		await tree.process_frame
	chk.call(not rs.is_open() and dones[0] == 3, "auto cierra el tablero de la noche (%d ms, t=%.2f anim=%s proc=%s paused=%s)" % [Time.get_ticks_msec() - t0, rs._t, rs._animating, rs.is_processing(), tree.paused])
	rs.open_report(Ranking.report(6))
	t0 = Time.get_ticks_msec()
	while rs.is_open() and Time.get_ticks_msec() - t0 < 9000:
		await tree.process_frame
	chk.call(not rs.is_open() and dones[0] == 4, "auto cierra el Report")
	rs.auto = false
	# el Report: E termina de imprimir, E cierra; Esc cierra enseguida
	rs.open_report(Ranking.report(6))
	await tree.process_frame
	await _key(tree, KEY_E)
	chk.call(rs.is_open() and not rs._animating, "E termina de imprimir")
	await _key(tree, KEY_E)
	chk.call(not rs.is_open() and dones[0] == 5, "E cierra el Report")
	rs.open_report(Ranking.report(6))
	await tree.process_frame
	await _key(tree, KEY_ESCAPE)
	chk.call(not rs.is_open() and dones[0] == 6, "Esc cierra el Report")
	# el tablero entero: flechas eligen, R cierra (no el mismo cuadro), Esc cierra
	rs.open_board()
	await tree.process_frame
	var sel0: int = rs._b_sel
	await _key(tree, KEY_DOWN)
	chk.call(rs._b_sel == mini(sel0 + 1, 29), "abajo elige la fila siguiente")
	await _key(tree, KEY_RIGHT)
	chk.call(rs._b_sel >= 15 or sel0 + 1 >= 15, "derecha pasa a la otra columna")
	await tree.create_timer(0.3).timeout
	await _key(tree, KEY_R)
	chk.call(not rs.is_open() and dones[0] == 7, "R cierra el tablero")
	rs.open_board()
	await tree.process_frame
	await _key(tree, KEY_ESCAPE)
	chk.call(not rs.is_open() and dones[0] == 8, "Esc cierra el tablero")
	rs.open_board()
	rs.close_now()
	rs.close_now()
	chk.call(dones[0] == 9, "close_now dos veces = un done")
	# las filas del tablero son botones visibles (el cursor del mando salta entre ellas con LB / RB)
	rs.open_board()
	await tree.process_frame
	var btns := 0
	for r in rs._b_rows:
		if (r["btn"] as Button).is_visible_in_tree() and (r["btn"] as Button).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			btns += 1
	chk.call(btns == 30, "30 filas tocables (%d)" % btns)
	rs.close_now()
	print("RANKUI %s fails=%d" % ["ok" if fails.is_empty() else "FAILED", fails.size()])
	m.quit_clean(0 if fails.is_empty() else 1)

# ================================================================== las pantallas (capturas)

## RankScreens del juego (main.rank después del JOIN) o uno propio (el árbol de R antes del JOIN).
static func screens(m) -> Control:
	var rs = m.get("rank")
	if rs != null:
		return rs
	if m.has_meta("rank_demo_screens"):
		return m.get_meta("rank_demo_screens")
	var sc = load("res://scripts/ui/rank_screens.gd").new()
	sc.name = "RankScreens"
	m._layer(7).add_child(sc)
	m.set_meta("rank_demo_screens", sc)
	return sc

## Una partida "good" hasta la noche n (la tabla provisional, semilla fija): el movimiento de esa noche.
static func play_to(night: int, prof := "good", seed := 11, last_parts := {}) -> Dictionary:
	var R = Ranking
	R.reset(seed)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var nd := _nell_days(PROVISIONAL[prof], r, night)
	var mv := {}
	for i in night:
		if i + 1 == 5:
			R.add_bonus(R.RIVAL, 8)
		var d: Dictionary = nd[i]
		var parts := {}
		if i + 1 == night and not last_parts.is_empty():
			parts = last_parts
		else:
			parts = {"repairs": int(d["base"] * 0.55), "sales": int(d["base"] * 0.3), "events": int(d["total"]) - int(d["base"]),
				"appeal": i / 2, "clean": 0, "lost": 0}
		mv = R._commit(i + 1, int(d["total"]), int(d["base"]), parts)
	return mv

static func _screen_demo(m, name: String) -> void:
	var tree: SceneTree = m.get_tree()
	var R = Ranking
	var rs := screens(m)
	rs.auto = false
	if name == "rank_board_pad":
		PadCursor.pad_in_use = true
	if name.begins_with("rank_night"):
		var night := 6
		var parts := {"repairs": 21, "sales": 13, "events": 8, "appeal": 5, "clean": 0, "lost": -1}
		if name == "rank_night_top":
			night = 9
		Game.day = night
		var mv := play_to(night, "good", 11, parts)
		if name == "rank_night_late":
			R.mark_late()
		_night_backdrop(m)
		await tree.process_frame
		rs.open_night(mv)
		# --- POLISH LOOK (P11): --step=sweep: la captura sale a mitad del barrido ámbar de la fila de Nell
		if arg("step", "") == "sweep":
			while rs._animating:
				await tree.process_frame
			await tree.create_timer(0.32).timeout
			m.shot_frames = m.frame + 1
		# --- end POLISH LOOK
		return
	if name.begins_with("rank_board"):
		Game.day = 7
		play_to(6, "good", 11)
		m.begin_morning()
		await tree.process_frame
		rs.open_board()
		if name == "rank_board_pad":
			await tree.create_timer(0.4).timeout
			rs.select_row(R.position() - 1)
		return
	if name.begins_with("report_"):
		var ed := int(name.substr(7))
		var night2 := ed * 3
		R.debug_flags = {"crate": "kept", "grade": "certified", "race": "podium", "cores": 2, "favour": "done"}
		Game.day = night2
		play_to(night2, "good", 11)
		_night_backdrop(m)
		await tree.process_frame
		rs.open_report(R.report(night2))
		return

# ================================================================== la noche del Brass Comet (GalaScene)

## El estado de la noche 10 para la gala: "win" (Nell #1, todos los hilos bien, 3 núcleos), "lose" (#2-#4, la caja
## declarada, 2 núcleos, aprobado), "far" (sloppy, #13 o así, la caja rechazada, una cuota corta). Devuelve si es #1.
static func gala_state(kind: String) -> bool:
	var prof := String({"win": "good", "lose": "human", "far": "sloppy"}[kind])
	Season.debug_state(10, prof)
	var R = Ranking
	if kind == "win":
		R.fast_forward(1, [96])
	elif kind == "lose":
		# la noche 10 justa para quedar #2-#4 a unas estrellas del primero (el modelo es casi determinista)
		var keep: Dictionary = R.save_data()
		for st in range(74, 8, -4):
			R.load_data(keep)
			R.fast_forward(1, [st])
			var top: Dictionary = R.table()[0]
			if R.position() >= 2 and R.position() <= 4 and int(top["score"]) - R.score() >= 5:
				break
	else:
		R.fast_forward(1, [28])
	var fl: Dictionary = {"win": {"crate": "delivered", "grade": "certified", "band": true, "race": "podium", "paid_in_full": true,
			"cores": 3, "favour": "done"},
		"lose": {"crate": "declared", "grade": "pass", "band": false, "race": "podium", "paid_in_full": true, "cores": 2,
			"favour": "refused"},
		"far": {"crate": "refused", "grade": "pass", "band": false, "race": "finished", "paid_in_full": false, "cores": 1,
			"favour": "refused"}}[kind]
	for k in fl:
		Game.set_flag(k, fl[k])
	Game.debt = 34 if kind == "far" else 0
	# (capturas) una historia de 10 días para el resumen de la tarjeta: lo de un día típico de cada perfil
	var per: Array = {"win": [6, 4, 236], "lose": [5, 3, 168], "far": [4, 1, 92]}[kind]
	var spd: Array = Season.TYPICAL[prof]["stars"]
	Game.history.clear()
	for d in 10:
		Game.history.append({"day": d + 1, "repairs": int(per[0]) + d % 2, "sales": int(per[1]) + (d % 3) / 2,
			"earned": int(per[2]) + 7 * (d % 4), "stars": 12, "day_stars": int(spd[d])})
	Game.sign_points = maxi(Game.sign_points, R.milestone_points())
	return R.position() == 1

## --demo=gala_win | gala_lose | gala_far [--step=count_done|walk_done|comet_on|ring_|clatter:|card|credits|end]
## [--pad=1]: la gala de verdad (sobre la calle de W si está) hasta ese momento, quieta, y la captura (main la guarda
## con --shot; el cuadro lo fija la demo cuando la escena ya se asentó).
static func _gala_demo(m, name: String) -> void:
	var tree: SceneTree = m.get_tree()
	var g = m.get("gala")
	var step := arg("step", "card")
	PadCursor.pad_in_use = arg("pad", "") == "1"
	var champ := gala_state(name.substr(5))
	# --- SS2 MERGE: la calle como la deja la mañana del día 10 (Shine Again abierta, el patio de Dolly, las mejoras)
	m.street.set_rival_open(Season.is_unlocked("rival"))
	m.street.set_vendor_open(Season.is_unlocked("vendor"))
	m.street.set_upgrade_looks()
	# --- end SS2 MERGE
	print("GALA DEMO %s step=%s place=%d champion=%s" % [name, step, Ranking.position(), str(champ)])
	m.screens.hide_all()
	g.auto = false
	g.demo_stop = step
	g.play(m, champ)
	var t := 0.0
	while not g.frozen and t < 120.0:
		await tree.create_timer(0.5).timeout
		t += 0.5
		var target_stage := step in ["card", "credits", "end"]
		if g.stage == "beats" and target_stage:
			g.press("skip")
		elif g.stage == "card" and step in ["credits", "end"]:
			g.press("next")
		elif g.stage == "credits" and step == "end":
			g.press("next")
		elif g.stage == "beats" and t > 1.0:
			g.press("next")
	await tree.create_timer(float(arg("hold", "1.8"))).timeout   # --- POLISH LOOK (P3): --hold=0.6: la tarjeta contando
	print("GALA DEMO frozen=%s stage=%s log=%s" % [str(g.frozen), g.stage, str(g.beats_log)])
	if m.shot_path != "":
		m.shot_frames = m.frame + 2
	else:
		m.quit_clean(0)

## --demo=galatest: la gala por su API y por teclas de verdad: las dos versiones, Esc salta a la tarjeta, E sigue, las
## flechas eligen, el mando (B = Esc), el clic, close_now, la calle vuelve a como estaba, reusarla dos veces.
static func _galatest(m) -> void:
	var tree: SceneTree = m.get_tree()
	var fails: Array = []
	var checks := [0]
	var chk := func(ok: bool, what: String) -> void:
		checks[0] += 1
		if not ok:
			fails.append(what)
			print("GALATEST FAIL ", what)
	var g = m.get("gala")
	chk.call(g != null and g is GalaScene, "main.gala es GalaScene")
	var st = m.street
	var dones := [0, ""]
	g.finished.connect(func(c: String):
		dones[0] = int(dones[0]) + 1
		dones[1] = c)
	# el elenco se hizo al arrancar (uno por cuadro)
	await tree.create_timer(1.0).timeout
	chk.call(bool(g._prebuilt) and g._actors.size() >= 9, "elenco hecho al arrancar (%d actores)" % g._actors.size())
	var raker_pos: Vector3 = st.raker.global_position
	# 1. campeona, auto: el cometa, las 7 lámparas (3 núcleos), devuelve keep
	var champ: bool = gala_state("win")
	chk.call(champ, "estado win: Nell #1")
	g.auto = true
	var c1: String = await g.play(m, true)
	chk.call(c1 == "keep" and dones[0] == 1 and dones[1] == "keep", "auto campeona -> keep (%s)" % c1)
	chk.call("comet_on" in g.beats_log and "ring_7" in g.beats_log and "card" in g.beats_log and "end" in g.beats_log,
		"campeona: cometa, 7 lámparas, tarjeta, placa (%s)" % str(g.beats_log))
	var tolle := false
	for e in g.beats_log:
		if String(e).begins_with("inspector: By the authority"):
			tolle = true
	chk.call(tolle, "Tolle certifica")
	chk.call(not g.is_open() and not g._layer.visible, "cerrada y escondida")
	chk.call(not st.walker.frozen and not st.cam_fixed and bool(st.kettle_follow), "la calle vuelve a la normalidad")
	chk.call(st.raker.global_position.distance_to(raker_pos) < 0.01, "Raker vuelve a su puesto")
	var hidden := true
	for id in g._actors:
		if g._actors[id].visible:
			hidden = false
	chk.call(hidden, "el elenco propio, escondido")
	# las líneas del epílogo según los hilos (win: Rook entregó, Hesk pagó, Lune con banda, Clatter, Pipip con copa)
	var epi: String = " | ".join(g.beats_log)
	chk.call("rook: The band owes you" in epi and "dockmaster: On MY dock" in epi and "singer: This one's" in epi
		and "pipip: Digger says" in epi and "clatter:" in epi, "epílogo de la campeona")
	# 2. todavía no, con teclas: Esc salta a la tarjeta, E sigue (créditos), Esc los salta, flecha a Title, E elige
	gala_state("lose")
	var place := Ranking.position()
	chk.call(place >= 2 and place <= 4, "estado lose: #%d" % place)
	g.auto = false
	var res := [""]
	var run := func():
		res[0] = await g.play(m, false)
	run.call()
	await tree.create_timer(2.6).timeout   # (el fundido + la radio)
	chk.call(g.is_open() and g.stage == "beats", "abierta, en los momentos")
	chk.call(m._pad_root() == g.pad_root(), "main._pad_root = la capa de la gala")
	chk.call(bool(m.pad.dialog_waiting.call()), "A = Espacio mientras la gala está abierta")
	await _key(tree, KEY_ESCAPE)
	await tree.create_timer(0.6).timeout
	chk.call(g.stage == "card" and g._card.visible, "Esc salta a la tarjeta (%s)" % g.stage)
	chk.call(not "comet_on" in g.beats_log, "sin cometa en la versión todavía no")
	chk.call(g._card_title.text == String(Ranking.award()["title"]), "el premio por puesto: %s" % g._card_title.text)
	await _key(tree, KEY_E)
	await tree.create_timer(0.4).timeout
	chk.call(g.stage == "credits", "E: los créditos (%s)" % g.stage)
	await _key(tree, KEY_ESCAPE)
	await tree.create_timer(0.4).timeout
	chk.call(g.stage == "end" and g._end.visible, "Esc salta los créditos (%s)" % g.stage)
	chk.call(g._end_keep.text == "Keep trading: chase the comet", "el botón de la versión todavía no")
	await _key(tree, KEY_RIGHT)
	chk.call(g._end_sel == 1, "derecha elige Title")
	await _key(tree, KEY_E)
	await tree.create_timer(0.5).timeout
	chk.call(res[0] == "title" and dones[0] == 2 and not g.is_open(), "E en Title -> title (%s)" % res[0])
	# 3. el mando: B (Esc por PadCursor) salta; X (Espacio) sigue; A con el gancho = Espacio elige el primario
	gala_state("far")
	chk.call(Ranking.position() > 5, "estado far: #%d (fila aparte)" % Ranking.position())
	res[0] = ""
	run.call()
	await tree.create_timer(2.2).timeout
	await _joy(tree, JOY_BUTTON_X)
	await tree.create_timer(0.3).timeout
	await _joy(tree, JOY_BUTTON_B)
	await tree.create_timer(0.6).timeout
	chk.call(g.stage == "card", "mando: B salta a la tarjeta (%s)" % g.stage)
	chk.call(bool(g._count_me["box"].visible) or "countdown" in g.beats_log, "la fila aparte de Nell (o la cuenta empezó)")
	await _joy(tree, JOY_BUTTON_A)
	await tree.create_timer(0.4).timeout
	chk.call(g.stage == "credits", "mando: A sigue (%s)" % g.stage)
	await _joy(tree, JOY_BUTTON_B)
	await tree.create_timer(0.4).timeout
	chk.call(g.stage == "end", "mando: B salta los créditos (%s)" % g.stage)
	await _joy(tree, JOY_BUTTON_A)
	await tree.create_timer(0.5).timeout
	chk.call(res[0] == "keep" and not g.is_open(), "mando: A elige Keep trading (%s)" % res[0])
	# 4. el ratón: un clic en el fondo sigue; close_now termina enseguida con keep
	gala_state("lose")
	res[0] = ""
	run.call()
	await tree.create_timer(2.2).timeout
	var n0: int = g.beats_log.size()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(640, 300)
	g._on_root_input(ev)
	await tree.create_timer(0.3).timeout
	chk.call(g.beats_log.size() > n0, "un clic adelanta el momento")
	g.close_now()
	await tree.create_timer(0.5).timeout
	chk.call(res[0] == "keep" and not g.is_open() and dones[0] == 4, "close_now -> keep (%s)" % res[0])
	print("GALATEST %s checks=%d fails=%d" % ["ok" if fails.is_empty() else "FAILED", checks[0], fails.size()])
	m.quit_clean(0 if fails.is_empty() else 1)

static func _joy(tree: SceneTree, b: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = pressed
		Input.parse_input_event(e)
		await tree.process_frame
	await tree.process_frame

## La tienda de noche detrás (como después del libro de cuentas), sin el libro.
static func _night_backdrop(m) -> void:
	m.open_shop_now()
	m.show_night()
	m.screens.hide_all()
