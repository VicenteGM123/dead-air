extends RefCounted
## --- SS2 WORLD: las demos de la línea W (capturas con --shot=<png> --frames=<n>; main._lane_demo las llama):
##   shop_base            la tienda de día con gente (el taller vivido: primer plano, pared del fondo, rayo de sol)
##   shop_all_fittings    la tienda con las 8 mejoras y todas las cosas de las historias (día 9)
##   shop_reveal          el estreno de una mejora (el pop, las chispas; --who=<id> elige cuál, por defecto neon)
##   shop_night_moons     la ventana de noche con las dos lunas (--who=bigfall|bronzemoon|starfall para las variantes)
##   shop_event_<id>      la tienda el día del evento (sandstorm, festival, finale)
##   shop_wide            la tienda entera desde lejos (revisión del decorado)
##   street_d1 / street_d3   la calle el día 1 (la vecina tapiada, el patio cerrado) y el día 3 (Shine Again abierta)
##   street_event_<id>    la calle el día del evento (sandstorm, inspection, bigfall, festival, race, finale)
##   street_band          The Low Moons junto a la puerta (Bronzemoon)
##   street_balloon       el globo de cromo de Glint (día 8; --who=popped: el día 9 caído)
##   street_night_moons   la calle de noche: las dos lunas, el anillo v2 y sus lámparas
##   street_comet         la gala en la calle (la noche 10): cometa, 7 lámparas, faroles, banda, público, chispas
##   street_wide / street_left / street_right   la calle desde lejos / la vecina / el patio de Dolly
##   sky_intro            el cielo de la introducción (el anillo v2, las lunas)

const NAMES := ["shop_base", "shop_all_fittings", "shop_reveal", "shop_night_moons", "shop_wide", "street_d1", "street_d3",
	"street_band", "street_balloon", "street_night_moons", "street_comet", "street_wide", "street_left", "street_right",
	"sky_intro"]

static func handles(name: String) -> bool:
	return name in NAMES or name.begins_with("shop_event_") or name.begins_with("street_event_")

static func _arg(key: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

static func run(m, name: String) -> void:
	var tree: SceneTree = m.get_tree()
	if name.begins_with("street_event_"):
		var ev := name.substr(13)
		Season.debug_state(_event_day(ev), "good")
		_morning(m)
		var x := {"sandstorm": 0.6, "inspection": -2.0, "bigfall": 4.0, "festival": -4.4, "race": 4.0, "finale": -3.0}
		_street_at(m, float(x.get(ev, 0.0)))
		return
	if name.begins_with("shop_event_"):
		var ev2 := name.substr(11)
		Season.debug_state(_event_day(ev2), "good")
		await _shop(m, true)
		return
	match name:
		"shop_base":
			Season.debug_state(4, "good")
			await _shop(m, true)
		"shop_all_fittings":
			Season.debug_state(9, "good")
			_all_fittings()
			Game.set_flag("crate", "kept")
			Game.set_flag("grade", "certified")
			Game.set_flag("race", "podium")
			Game.set_flag("rook_key", true)
			Game.set_flag("band", true)
			Game.set_flag("paid_in_full", true)
			Game.set_flag("cores", 3)
			await _shop(m, false)
		"shop_reveal":
			Season.debug_state(6, "good")
			var who := _arg("who", "neon")
			for id in SeasonData.FITTING_ORDER:
				if id != who and not Game.has_fitting(id) and SeasonData.FITTING_ORDER.find(id) < 5:
					Game.fittings.append(id)
			if not Game.has_fitting(who):
				Game.fittings.append(who)
			Game.fittings_new = [who]
			m.open_shop_now()
		"shop_night_moons":
			var kind := _arg("who", "moons")
			Season.debug_state({"moons": 4, "bigfall": 6, "bronzemoon": 8, "starfall": 10}.get(kind, 4), "good")
			Game.fittings_new = []
			Game.junk = []
			m.open_shop_now()
			m.day.clear()
			m.show_night()
			m.screens.hide_all()
			m.shop.set_window_sky(kind)
		"shop_wide":
			Season.debug_state(9, "good")
			_all_fittings()
			await _shop(m, false)
			m.shop.cam_fixed = true
			m.shop.camera.position = Vector3(0.6, 4.6, 13.0)
			m.shop.camera.look_at(Vector3(0.6, 1.6, -3.0), Vector3.UP)
			m.hud.show_top(false)
		"street_d1":
			Season.debug_state(1, "good")
			_morning(m)
			_street_at(m, -6.0)
		"street_d3":
			Season.debug_state(3, "good")
			_morning(m)
			_street_at(m, -6.0)
		"street_band":
			Season.debug_state(8, "good")
			Game.set_flag("band", true)
			_morning(m)
			m.street.set_band(true)
			_street_at(m, -5.6)
		"street_balloon":
			var popped := _arg("who", "") == "popped"
			Season.debug_state(9 if popped else 8, "good")
			if popped:
				Game.set_flag("balloon", "popped")
			_morning(m)
			m.street.set_balloon("popped" if popped else "up")
			_street_at(m, -6.0)
		"street_night_moons":
			Season.debug_state(4, "good")
			_morning(m)
			m.street.set_night(true)
			m.street.set_moons(_arg("who", ""))
			m.street.cam_fixed = true
			m.street.place_camera(-2.0)
			m.hud.show_top(false)
			m.hud.set_hint(false)
		"street_comet":
			Season.debug_state(10, "good")
			Game.set_flag("cores", 3)
			_morning(m)
			m.hud.show_top(false)
			m.hud.set_hint(false)
			var st = m.street
			st.set_night(true)
			st.set_event("finale")
			st.set_moons(_arg("who", "full"))
			st.set_band(true)
			st.set_comet(true)
			st.set_ring_lamps(7)
			st.walker.teleport(StreetWorld.SHOP_X + 0.2, 1)
			st.kettle.position = Vector3(StreetWorld.SHOP_X - 0.6, 0, StreetWorld.LANE_Z + 0.3)
			var who := ["gorrum", "zib", "oona", "pipip", "rook", "clatter", "raker", "mags", "singer", "timekeeper", "tracker",
				"vendor", "inspector", "rival"]
			var spots: Array = st.gala_spots()
			for i in mini(who.size(), spots.size()):
				var a: Actor = st.make_actor(who[i], spots[i], -1 if Vector3(spots[i]).x > StreetWorld.SHOP_X else 1)
				a.quiet = true
			st.cam_fixed = true
			st.place_camera(-5.0)
			await tree.create_timer(0.9).timeout
			st.play_sparks()
		"street_wide":
			Season.debug_state(int(_arg("who", "8")), "good")
			_morning(m)
			m.hud.show_top(false)
			m.street.walker.teleport(-2.6, 1)
			m.street.cam_fixed = true
			m.street.camera.position = Vector3(0.0, 7.0, 24.0)
			m.street.camera.look_at(Vector3(0.0, 4.0, -20.0), Vector3.UP)
		"street_left":
			Season.debug_state(int(_arg("who", "4")), "good")
			_morning(m)
			_street_at(m, -11.0)
		"street_right":
			Season.debug_state(int(_arg("who", "4")), "good")
			_morning(m)
			_street_at(m, 11.2)
		"sky_intro":
			Game.new_game_state()
			m.show_intro()
			m.screens.hide_all()

## El día de un evento (el primero del calendario que lo tiene).
static func _event_day(ev: String) -> int:
	for k in SeasonData.PLAN:
		if String(SeasonData.PLAN[k].get("event", "")) == ev:
			return int(k)
	return 4

static func _all_fittings() -> void:
	for id in SeasonData.FITTING_ORDER:
		if not Game.has_fitting(id):
			Game.fittings.append(id)
	Game.fittings_new = []

static func _morning(m) -> void:
	Game.beats_seen["crate_ask"] = true
	Game.beats_seen["rival_hello"] = true
	Game.beats_seen["seven_waking"] = true
	Game.beats_seen["rook_pickup"] = true
	Game.tips_seen["walk"] = true
	m.begin_morning()
	m.hud.hide_banner()

static func _street_at(m, x: float) -> void:
	m.street.walker.teleport(x, 1)
	m.street.snap_camera()

## La tienda abierta con gente (como season_demo shop_day): línea de 3 y uno en el mostrador.
static func _shop(m, people: bool) -> void:
	Game.fittings_new = []
	m.open_shop_now()
	await m.get_tree().process_frame
	m.day.clear()
	if not people:
		m.shop.walker.teleport(ShopWorld.STATIONS["counter"]["x"], 1)
		m.shop.snap_camera()
		return
	m.day.running = true
	m.day.shop_t = 112.0
	var sch: Array = Season.schedule_for(Game.day)
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
