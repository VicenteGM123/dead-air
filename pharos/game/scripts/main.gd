extends Node3D
## Boots PHAROS and runs the day / night loop.

var tod: TimeOfDay
var island: Island
var sea: Sea
var rig: CameraRig
var props: Props
var fx: Fx
var projectiles: Projectiles
var units_root: Node3D
var spots_root: Node3D
var spots: Array[BuildSpot] = []
var pharos_spot: BuildSpot
var hero: Hero
var horn: NightHorn
var waves: WaveDirector
var markers: SpawnMarkers
var ambient: Node3D = null
var ui: Node = null
var bot: Node = null
var _offered: Array = []
var _title_t := 0.0
var _seq := 0
var _snap := {} # the island at the last dusk (Game.snapshot()), for "Reintentar la noche"


func _ready() -> void:
	Game.main = self
	Obstacles.clear()
	Interactables.clear()
	WallBuilding.clear_registry()
	Game.reset()
	var t0 := Time.get_ticks_msec()
	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	add_child(tod)
	tod.set_shadows(Settings.shadows())
	island = Island.new()
	island.name = "Island"
	add_child(island)
	island.generate(int(Game.arg("seed", "7")))
	Game.island = island
	sea = Sea.new()
	sea.name = "Sea"
	add_child(sea)
	sea.build()
	props = Props.new()
	props.name = "Props"
	add_child(props)
	props.build(island)
	var grass := Grass.new()
	grass.name = "Grass"
	add_child(grass)
	grass.build(island, props)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	Game.fx = fx
	projectiles = Projectiles.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)
	Game.projectiles = projectiles
	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	spots_root = Node3D.new()
	spots_root.name = "Spots"
	add_child(spots_root)
	markers = SpawnMarkers.new()
	markers.name = "SpawnMarkers"
	add_child(markers)
	markers.setup(island)
	waves = WaveDirector.new()
	waves.name = "Waves"
	waves.units_root = units_root
	add_child(waves)
	waves.night_cleared.connect(_on_night_cleared)
	rig = CameraRig.new()
	rig.name = "Camera"
	add_child(rig)
	Game.rig = rig
	_build_spots()
	horn = NightHorn.new()
	horn.name = "NightHorn"
	add_child(horn)
	horn.global_position = island.ground(Vector3(-4.6, 0, 5.9))
	horn.rotation.y = 0.5
	horn.blown.connect(call_night)
	hero = Hero.new()
	hero.name = "Hero"
	units_root.add_child(hero)
	hero.teleport(Vector3(0, 0, 9.5))
	hero.facing = PI
	Game.hero = hero
	_make_ambient()
	_make_ui()
	Settings.apply_quality(get_viewport())
	print("PHAROS world ready in %d ms" % (Time.get_ticks_msec() - t0))
	if Game.arg("shot", "") != "" and Game.arg("shot") in ["overview", "island"]:
		_static_shot(Game.arg("shot"))
		return
	if Game.arg("test", "0") == "1" or Game.arg("bot", "0") == "1" or Game.arg("play", "0") == "1":
		start_game()
	else:
		show_title()
	if Game.arg("bot", "0") == "1":
		bot = load("res://tools/bot.gd").new()
		add_child(bot)


func _make_ambient() -> void:
	if not ResourceLoader.exists("res://scripts/world/ambient.gd"):
		return
	var scr: Script = load("res://scripts/world/ambient.gd")
	ambient = scr.new()
	ambient.name = "Ambient"
	add_child(ambient)
	if ambient.has_method("setup"):
		ambient.call("setup", island)
	if ambient.has_method("set_hero"):
		ambient.call("set_hero", hero)


func _make_ui() -> void:
	if not ResourceLoader.exists("res://scripts/ui/ui.gd"):
		return
	ui = load("res://scripts/ui/ui.gd").new()
	ui.name = "UI"
	add_child(ui)
	Game.hud = ui


func _build_spots() -> void:
	var i := 0
	for sd in island.spots:
		var sp := BuildSpot.new()
		sp.setup(sd, 100 + i * 13)
		sp.name = "Spot_%s_%d" % [sd["type"], i]
		spots_root.add_child(sp)
		sp.global_position = sd["pos"]
		spots.append(sp)
		if sd["type"] == "pharos":
			pharos_spot = sp
		i += 1


func difficulty_hp_mult() -> float:
	return float(Game.arg("hpmult", "1.0"))


# --- flow --------------------------------------------------------------------------------------------------

func show_title() -> void:
	Game.set_phase(Game.Phase.TITLE)
	tod.set_state(Game.arg("titletod", "golden"))
	hero.visible = false
	hero.input_enabled = false
	pharos_spot.force_build(1)
	Game.pharos = pharos_spot.building
	_title_village(true)
	rig.free_mode = true
	rig.fov = 38.0
	_title_t = 0.0
	Sfx.music("title")
	if ui and ui.has_method("show_title"):
		ui.show_title()


## The title screen shows Delos in its glory; the game itself starts from the lone lighthouse.
func _title_village(on: bool) -> void:
	if on:
		Game.pharos_level = 3
		pharos_spot.building.level = 1
		for i in 2:
			pharos_spot.building.upgrade()
		var lv := {"house": 2, "farm": 2, "dock": 1, "tower": 3, "wall": 2, "barracks": 1}
		for sp in spots:
			if sp.type != "pharos":
				sp.force_build(lv.get(sp.type, 1))
		return
	for sp in spots:
		if sp.type == "pharos" or sp.building == null:
			continue
		if sp.building is BarracksBuilding:
			for sol in (sp.building as BarracksBuilding).soldiers:
				if is_instance_valid(sol):
					sol.queue_free()
		Obstacles.remove_owner(sp.building)
		sp.building.queue_free()
		sp.building = null
		sp.paid = 0
	Game.pharos_level = 1
	if pharos_spot.building and pharos_spot.building.level > 1:
		Obstacles.remove_owner(pharos_spot.building)
		pharos_spot.building.queue_free()
		pharos_spot.building = null
	pharos_spot.force_build(1)
	Game.pharos = pharos_spot.building
	for sp in spots:
		sp._update_visibility(true)
		sp._marker.visible = sp.is_unlocked() and sp.building == null


func start_game() -> void:
	_seq += 1
	if Game.phase == Game.Phase.TITLE:
		_title_village(false)
	Game.reset()
	Game.set_phase(Game.Phase.DAY)
	pharos_spot.force_build(1)
	Game.pharos = pharos_spot.building
	hero.visible = true
	hero.input_enabled = true
	hero.alive = true
	hero.max_hp = hero.max_hp_stat()
	hero.hp = hero.max_hp
	hero.teleport(Vector3(0, 0, 9.5))
	hero.facing = PI
	rig.free_mode = false
	rig.target = hero
	rig.fov = 34.0
	rig.distance = 27.0
	rig.pitch_deg = 52.0
	rig.yaw_deg = 0.0
	rig.snap()
	tod.set_state("day")
	Game.coins_changed.emit(Game.coins, 0)
	_debug_setup()
	begin_day(true)
	_snap = Game.snapshot()
	if int(Game.arg("startnight", "0")) > 0:
		Game.night = int(Game.arg("startnight")) - 1
		await get_tree().create_timer(0.3).timeout
		call_night()


## Test helper for screenshots: a pack of creatures already at the edge of the village (on the last night, the
## Hydra herself rises there instead of out at sea).
func _debug_near_fight() -> void:
	if Game.night >= Data.NIGHTS:
		waves._groups = waves._groups.filter(func(g): return g[2] != "hydra")
		waves.spawn("hydra", 0, island.lane_length(0) - 30.0)
		return
	var kinds := ["shade", "shade", "shade", "ker", "shielded", "shade", "archer", "shade", "cyclops"]
	for i in kinds.size():
		# Just outside the southern wall plot (s 56), so a built wall meets them.
		waves.spawn(kinds[i], 0, island.lane_length(0) - 27.0 + float(i % 3) * 1.6)


## Test helpers: village=1 pre-builds the island, pl=N sets the lighthouse level.
func _debug_setup() -> void:
	var pl := int(Game.arg("pl", "1"))
	if pl > 1:
		for i in pl - 1:
			pharos_spot.building.upgrade()
	if Game.arg("village", "0") != "1":
		return
	var lv := {"house": 2, "farm": 1, "dock": 1, "tower": 2, "wall": 2, "barracks": 1}
	for sp in spots:
		if sp.type == "pharos" or not sp.is_unlocked():
			continue
		sp.force_build(lv.get(sp.type, 1))


func begin_day(first: bool = false) -> void:
	Game.set_phase(Game.Phase.DAY)
	markers.show_lanes(Data.night_lanes(Game.night + 1))
	Sfx.music("day")
	if first:
		Game.say("Delos", "La última luz del Egeo", "title")
	else:
		Game.say("Día %d" % (Game.night + 1), "Construye antes de que caiga la noche", "day")


func call_night() -> void:
	if Game.phase != Game.Phase.DAY:
		return
	# The island as it stands now is where "Reintentar la noche" brings the player back to.
	_snap = Game.snapshot()
	var seq := _seq
	Game.set_phase(Game.Phase.DUSK)
	Sfx.play("night_horn", horn.global_position, 2.0)
	Sfx.music("")
	tod.transition_to("golden", 1.4)
	tod.transition_to("dusk", 1.6)
	tod.transition_to("night", 1.6)
	Game.say("Cae la noche", "Noche %d de %d" % [Game.night + 1, Data.NIGHTS], "night")
	await get_tree().create_timer(4.2).timeout
	if seq != _seq or Game.phase != Game.Phase.DUSK:
		return
	markers.hide_all()
	Game.night += 1
	Game.set_phase(Game.Phase.NIGHT)
	waves.start_night(Game.night)
	if Game.arg("nearfight", "0") == "1":
		_debug_near_fight()
	Sfx.music("boss" if Game.night == Data.NIGHTS else "night")


func _on_night_cleared() -> void:
	if Game.phase != Game.Phase.NIGHT:
		return
	var seq := _seq
	Game.set_phase(Game.Phase.DAWN)
	tod.transition_to("dawn", 2.6)
	tod.transition_to("day", 2.4)
	Sfx.music("")
	Sfx.play("stinger_dawn")
	if Game.night >= Data.NIGHTS:
		Game.say("Amanece sobre Delos", "La Hidra ha caído. La luz perdura.", "dawn")
	else:
		Game.say("Amanece", "Has sobrevivido a la noche %d" % Game.night, "dawn")
	await get_tree().create_timer(2.2).timeout
	if seq != _seq:
		return
	if Game.night < Data.NIGHTS:
		_dawn_rewards() # after the last night the coins would be useless: straight on to the victory
	await get_tree().create_timer(2.6).timeout
	if seq != _seq:
		return
	if Game.night >= Data.NIGHTS:
		victory()
	else:
		offer_blessings()


func _dawn_rewards() -> void:
	var total := 0
	for sp in spots:
		var b := sp.building
		if b == null:
			continue
		var inc := b.income()
		if inc > 0:
			total += inc
			fx.coin_burst(b.global_position + Vector3(0, b.height * 0.6, 0), mini(inc, 8))
		b.restore()
		if b is BarracksBuilding:
			(b as BarracksBuilding).revive_squad()
	if total > 0:
		Game.add_coins(total)
		Sfx.play("income")
		Game.say("+%d dracmas" % total, "Las casas, los olivares y los muelles pagan su tributo", "coins")
	hero.heal(9999.0)


func offer_blessings() -> void:
	Game.set_phase(Game.Phase.BLESSING)
	var pool: Array = []
	for id in Data.BLESSINGS:
		if not Game.has_blessing(id):
			pool.append(id)
	pool.shuffle()
	_offered = pool.slice(0, 3)
	if ui and ui.has_method("show_blessings"):
		ui.show_blessings(_offered)
	else:
		choose_blessing(_offered[0])


func choose_blessing(id: String) -> void:
	if Game.phase != Game.Phase.BLESSING:
		return
	Game.take_blessing(id)
	Sfx.play("blessing")
	for sp in spots:
		if sp.building:
			sp.building.refresh_max_hp()
	hero.refresh_stats()
	var b: Dictionary = Data.BLESSINGS[id]
	Game.say(b["god"], b["title"], "blessing")
	begin_day()


func on_pharos_destroyed() -> void:
	if Game.phase == Game.Phase.DEFEAT or Game.phase == Game.Phase.VICTORY:
		return
	_seq += 1
	var seq := _seq
	Game.set_phase(Game.Phase.DEFEAT)
	waves.stop()
	Sfx.music("")
	Sfx.play("stinger_defeat")
	Game.time_scale_target = 0.35
	rig.target = Game.pharos
	rig.distance = 40.0
	await get_tree().create_timer(1.2).timeout
	if seq != _seq:
		return
	Game.time_scale_target = 1.0
	if ui and ui.has_method("show_end"):
		ui.show_end(false)


func victory() -> void:
	Game.set_phase(Game.Phase.VICTORY)
	Sfx.play("stinger_victory")
	Sfx.music("title")
	if hero.alive and hero.state != Hero.S.DEAD:
		hero.rig.play("cheer")
	if ui and ui.has_method("show_end"):
		ui.show_end(true)


## True when "Reintentar la noche" has a dusk to go back to.
func can_retry() -> bool:
	return not _snap.is_empty()


## "Reintentar la noche" (defeat screen): back to the day before the lost night, exactly as the island stood when
## the horn was blown: same coins, buildings, lighthouse, blessings and Llama; the creatures are gone, everything
## razed stands again and Fanós is relit by the lighthouse. Nothing is lost but the night itself.
func retry_night() -> void:
	if _snap.is_empty():
		return
	_seq += 1
	Game.paused = false
	get_tree().paused = false
	waves.stop()
	for u in units_root.get_children():
		if u is Enemy:
			Game.unregister(u, 1)
			u.queue_free()
	projectiles.clear()
	Game.restore_snapshot(_snap)
	var states: Array = _snap.get("spots", [])
	for i in mini(spots.size(), states.size()):
		spots[i].set_state(states[i])
	Game.pharos = pharos_spot.building
	Game.pharos_level = pharos_spot.level()
	Game.pharos_level_changed.emit(Game.pharos_level)
	hero.reset_for_retry(float(_snap.get("favor", 0.0)))
	tod.transition_to("dawn", 1.0)
	tod.transition_to("day", 1.4)
	rig.free_mode = false
	rig.target = hero
	rig.snap()
	begin_day()


func restart() -> void:
	Game.paused = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func on_enemy_killed(_e: Node) -> void:
	pass


# --- per frame ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ambient and ambient.has_method("set_night"):
		ambient.call("set_night", tod.night_amount())
	if Game.phase == Game.Phase.TITLE:
		_title_t += delta
		rig.focus = Vector3(0, 4.0, 0)
		rig.yaw_deg = 200.0 + _title_t * 2.2
		rig.pitch_deg = 21.0
		rig.distance = 62.0
	elif hero and Game.phase != Game.Phase.DEFEAT and not rig.free_mode:
		var ahead := hero.vel * 0.35
		rig.look_ahead = rig.look_ahead.lerp(Vector3(ahead.x, 0, ahead.z), 1.0 - exp(-delta * 2.0))
		var zoom := 27.0 + (4.0 if Game.phase == Game.Phase.NIGHT else 0.0)
		if is_instance_valid(waves.boss) and waves.boss.alive:
			zoom = 36.0
		rig.distance = lerpf(rig.distance, zoom, 1.0 - exp(-delta * 1.2))


func _static_shot(kind: String) -> void:
	Game.set_phase(Game.Phase.DAY)
	pharos_spot.force_build(int(Game.arg("pl", "1")))
	Game.pharos = pharos_spot.building
	tod.set_state(Game.arg("tod", "day"))
	rig.free_mode = true
	match kind:
		"overview":
			rig.focus = Vector3(0, 0, 4)
			rig.distance = 150.0
			rig.pitch_deg = 60.0
			rig.fov = 40.0
		"island":
			rig.focus = Vector3(0, 3, 0)
			rig.distance = 80.0
			rig.pitch_deg = 30.0
			rig.yaw_deg = float(Game.arg("yaw", "20"))
			rig.fov = 40.0
	rig.snap()


func _input(event: InputEvent) -> void:
	# Debug camera for screenshots: cam=x,z,dist,pitch,yaw
	pass
