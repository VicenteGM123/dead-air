extends RefCounted
## --- SS2 SEASON: las demos de la línea S (capturas con --shot=<png> --frames=<n>; main._lane_demo las llama):
##   season_day_<n>   la mañana del día n (el cartel "Day 5 · The Scour", lo abierto, la calle del evento)
##   shop_day_<n>     la tienda abierta del día n con gente (el HUD "DAY n OF 10 · evento", la cuota, el chip)
##   fittings         el patio de Dolly (día 4: unas compradas, otras bloqueadas, la línea "Leaves ... · Dues ...")
##   calendar         el calendario del tablón (día 6)
##   mags_asis        el puesto de Mags con lo de "tal cual" (día 4)
##   mags_eve         el puesto de Mags la víspera de Bronzemoon (día 7: una cosa más en el cajón, más barato)
##   dues / dues_short  la cuota de la noche 3 (alcanza / no alcanza: la regla blanda)
##   beat_<id>        un momento de historia (SeasonData.BEATS)
##   after_hours      después de cerrar (Nell en el banco, el diálogo)
##   ledger / ledger10  el libro de cuentas de la noche 6 (cuota esta noche) y de la noche 10 (sin spoiler)
##   close_early      "[E] Close up early" en el mostrador (4:40 PM, nadie más) y su diálogo
##   rival_visit      la visita a Shine Again (día 4)
##   hud_pad          la tienda con el mando (los avisos "(A)", "(Y) Board")
##   title_v2done     el título con una partida terminada del prototipo (la nota "The prototype is over...")

const NAMES := ["fittings", "calendar", "mags_asis", "mags_eve", "dues", "dues_short", "after_hours", "ledger", "ledger10",
	"close_early", "rival_visit", "hud_pad", "title_v2done", "derby_podium"]

static func handles(name: String) -> bool:
	return name in NAMES or name.begins_with("season_day_") or name.begins_with("shop_day_") or name.begins_with("beat_")

static func run(m, name: String) -> void:
	var tree: SceneTree = m.get_tree()
	if name.begins_with("season_day_"):
		var d := int(name.substr(11))
		Season.debug_state(d, "good")
		m.begin_morning()
		m.street.walker.teleport(StreetWorld.SHOP_X + 2.5, 1)
		m.street.snap_camera()
		# --- POLISH LOOK (P1): --say2: Nell contesta a la vez que Raker (dos globos: uno sobre el otro, nunca encimados)
		if "--say2" in OS.get_cmdline_user_args():
			tree.create_timer(2.7).timeout.connect(func():
				m.street.blurt(m.street.nell, "Morning, Raker! Save me a heavy one."))
		# --- end POLISH LOOK
		return
	if name.begins_with("shop_day_") or name == "hud_pad":
		var d2 := int(name.substr(9)) if name != "hud_pad" else 6
		if name == "hud_pad":
			PadCursor.pad_in_use = true
		Season.debug_state(d2, "good")
		await _open(m)
		m.day.clear()
		m.day.running = true
		m.day.shop_t = 112.0
		var sch: Array = Season.schedule_for(d2)
		var line: Array = []
		var counter := {}
		for e in sch:
			if e["kind"] == "favour":
				continue
			if counter.is_empty() and e["kind"] == "repair":
				counter = e.duplicate(true)
				continue
			if line.size() < 3:
				var x: Dictionary = e.duplicate(true)
				x["p"] = 0.4 + 0.15 * line.size()
				line.append(x)
		m.day.demo_fill(line, counter)
		m.shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
		m.shop.snap_camera()
		m.hud.set_clock(m.day.minutes(), "open")
		m.hud.refresh()
		# --- POLISH LOOK (P7): --fly: un "+3★" sale del cliente del mostrador hacia el chip cada 0,9 s (la captura lo
		# agarra en vuelo)
		if "--fly" in OS.get_cmdline_user_args():
			var t := Timer.new()
			t.wait_time = 0.9
			m.add_child(t)
			t.timeout.connect(func():
				var a = m.day.counter.get("actor") if m.day.counter is Dictionary else null
				var at := Vector2(700, 330)
				if a is Node3D and is_instance_valid(a):
					at = m.shop.camera.unproject_position((a as Node3D).global_position + Vector3(0, 2.3, 0))
				m.hud.fly_stars(at, 3))
			t.start()
		# --- end POLISH LOOK
		return
	if name.begins_with("beat_"):
		var id := name.substr(5)
		var b: Dictionary = SeasonData.BEATS.get(id, SeasonData.BEATS["crate_ask"])
		Season.debug_state(int(b["day"]), "good")
		if String(b["phase"]) == "morning":
			m.begin_morning()
			await tree.create_timer(0.3).timeout
			m.hud.hide_banner()
		elif String(b["phase"]) == "night":
			await _open(m)
			m.day.clear()
			m.show_night()
			await tree.create_timer(0.4).timeout
			m.screens.hide_all()
		else:
			await _open(m)
			m.day.clear()
		var bd := {"id": id, "who": String(b["who"]), "lines": b["lines"], "options": b["options"],
			"must_choose": bool(b.get("must_choose", false)), "low": false}
		m._beat(bd)
		return
	match name:
		"derby_podium":
			# --- POLISH LOOK (P14): el Derby con podio (tres corredores, promedio 2,7 ★): el cartel PODIUM! y la cámara
			# que va a la copa. --step=glide: la captura sale cuando la copa ya apareció
			Season.debug_state(9, "good")
			await _open(m)
			m.day.clear()
			m.day.running = true
			m.day.shop_t = 140.0
			m.hud.set_clock(m.day.minutes(), "open")
			Game.today["racers"] = 3
			Game.today["racer_stars"] = 8
			Season.state["racers"] = {"zib": 3, "brisk": 3, "pipip": 2}
			Season.state["race_called"] = false
			m._race_call()
			if "--step=glide" in OS.get_cmdline_user_args():
				while not m.derby_gliding:
					await tree.process_frame
				await tree.create_timer(1.1).timeout
				m.shot_frames = m.frame + 1
			return
		"title_v2done":
			var src := "/tmp/claude-0/-home-user-dead-air/84a550d9-2edd-52f7-8fa3-04790d444022/scratchpad/ss2/fixtures/v2_done.json"
			if FileAccess.file_exists(src):
				var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
				f.store_string(FileAccess.get_file_as_string(src))
				f.close()
			m.show_title()
		"fittings":
			Season.debug_state(4, "good")
			Game.credits = 160
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["fittings"]["x"], 1)
			m.street.snap_camera()
			await tree.create_timer(0.3).timeout
			m.hud.hide_banner()
			m.fittings_stall()
		"calendar":
			Season.debug_state(6, "good")
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["board"]["x"], 1)
			m.street.snap_camera()
			await tree.create_timer(0.3).timeout
			m.hud.hide_banner()
			m.open_calendar()
		"mags_asis", "mags_eve":
			Season.debug_state(4 if name == "mags_asis" else 7, "good")
			Game.rep = maxi(Game.rep, 40)
			Season.state["asis_day"] = 0
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["parts"]["x"], 1)
			m.street.snap_camera()
			await tree.create_timer(0.3).timeout
			m.hud.hide_banner()
			m.parts_stall()
		"rival_visit":
			Season.debug_state(4, "good")
			m.begin_morning()
			m.street.walker.teleport(StreetWorld.STATIONS["rival"]["x"], -1)
			m.street.snap_camera()
			await tree.create_timer(0.3).timeout
			m.hud.hide_banner()
			m.visit_rival()
		"dues", "dues_short":
			Season.debug_state(3, "good")
			Game.credits = 186 if name == "dues" else 64
			Game.junk = []
			await _open(m)
			m.day.clear()
			_fake_today(m)
			m.show_night()
			await tree.create_timer(0.6).timeout
			m.screens.press("next")
		"after_hours":
			Season.debug_state(4, "good")
			Game.junk = [{"item": "radio", "fault": "tuner"}, {"item": "thruster", "fault": "coil"}]
			if "--twins" in OS.get_cmdline_user_args():   # --- POLISH FIX (F11): dos iguales (las etiquetas con el síntoma)
				Game.junk = [{"item": "thruster", "fault": "fan"}, {"item": "thruster", "fault": "coil"}, {"item": "radio", "fault": "tuner"}]
			await _open(m)
			m.day.clear()
			_fake_today(m)
			m.show_night()
		"ledger", "ledger10":
			var d3 := 6 if name == "ledger" else 10
			Season.debug_state(d3, "good")
			Game.junk = []
			await _open(m)
			m.day.clear()
			_fake_today(m)
			m.show_night()
		"close_early":
			Season.debug_state(5, "good")
			await _open(m)
			m.day.clear()
			m.day.running = true
			m.day.shop_t = 0.88 * Data.DAY_SECONDS
			m.shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
			m.shop.snap_camera()
			m.hud.set_clock(m.day.minutes(), "open")
			await tree.create_timer(1.4).timeout
			if OS.get_cmdline_user_args().has("--step=dialog"):
				m.ask_close_early()

static func _open(m) -> void:
	Game.fittings_new = []
	m.open_shop_now()
	await m.get_tree().process_frame

## Un día ya jugado (para el libro de cuentas): números de una partida "good".
static func _fake_today(_m) -> void:
	var st := {"customers": 8, "arrived": 9, "repairs": 6, "stars": 16, "sales": 3, "walkouts": 1, "patience_lost": 1,
		"parts_used": 4, "refurbished": 2, "tips": 4, "pods": 2, "repair_pay": 104, "sale_pay": 96, "served": 9,
		"repair_stars": 16, "sale_stars": 7, "after_hours": 1, "fittings_spent": 0, "event_stars": 8, "event_credits": 30}
	Game.today["credits_start"] = Game.credits - 180 + 40
	Game.today["rep_start"] = Game.rep - 9
	for k in st:
		Game.today[k] = st[k]
	Game.today["earned"] = 234
	Game.today["spent"] = 54
