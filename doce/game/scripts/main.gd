extends Node3D
## DOCE boot and flow: BOOT -> TITLE -> PLAY (-> DEAD -> PLAY at the last altar) (-> VICTORY).
## Builds the scene in this order: TimeOfDay (golden afternoon), Sea, World.build(), Fx, Hero at
## World.player_start(), CameraRig, ToonScreen (outlines + grade, always on), UI. Hooks for the other streams:
##   world        World (scripts/world/world.gd, WORLD stream)
##   _make_ui()   the UI root (scripts/ui/ui.gd when the UI stream delivers it; until then the title placeholder)
##   spawn_encounters()   wolves / boars from World.spawn_groups(): scripts/enemies/<kind>.gd when it exists
##   victory()    called by the lion encounter
## Debug args (docs/ARCHITECTURE.md): play=1 skips the title, noui=1, tod=<mood>, cam=fly pos=x,y,z yaw=deg
## pitch=deg, seed=N, start=x,y,z (hero start), wade=<m> (start in water that deep), face=deg, dummies=1,
## phystest=1, scene=arena.

const UI_PATH := "res://scripts/ui/ui.gd"
const RESPAWN_DELAY := 3.0

var tod: TimeOfDay
var sea: Sea
var world # World, or anything with the World API (tools/arena_world.gd)
var fx: Fx
var hero: Hero
var cam: CameraRig
var toon: ToonScreen
var ui: Node = null
var _respawn_t := -1.0


func _ready() -> void:
	if Game.arg("scene", "") == "arena" and scene_file_path == "res://main.tscn":
		get_tree().change_scene_to_file.call_deferred("res://tools/arena.tscn")
		return
	Game.main = self
	Interactables.clear()
	Game.set_phase(Game.Phase.BOOT)
	var t0 := Time.get_ticks_msec()
	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	add_child(tod)
	Game.tod = tod
	tod.set_shadows(Settings.shadows())
	sea = Sea.new()
	sea.name = "Sea"
	add_child(sea)
	Game.sea = sea
	world = _make_world()
	Game.world = world
	sea.build(world.sea_level)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	Game.fx = fx
	hero = Hero.new()
	hero.name = "Hero"
	add_child(hero)
	hero.teleport(_start_transform())
	Game.hero = hero
	cam = CameraRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	Game.camera = cam
	toon = ToonScreen.new()
	toon.name = "ToonScreen"
	add_child(toon)
	toon.setup(tod)
	_make_ui()
	# Title and pause input must work while the tree is paused; the rest of the scene pauses with it.
	var gate := InputGate.new()
	gate.name = "InputGate"
	gate.main = self
	add_child(gate)
	Settings.apply_quality(get_viewport())
	spawn_encounters()
	Game.hero_died.connect(_on_hero_died)
	Game.world_ready(Time.get_ticks_msec() - t0)
	if Game.arg_on("phystest"):
		var pt: Node = load("res://tools/phys_test.gd").new()
		add_child(pt)
	if Game.arg_on("play") or Game.arg("cam", "") == "fly" or not _wants_title():
		start_game()
	else:
		show_title()


## The island (WORLD stream). tools/arena.gd overrides this with its stone arena.
func _make_world() -> Node3D:
	var w := World.new()
	w.name = "World"
	add_child(w)
	w.build(int(Game.arg("seed", "7")))
	return w


func _wants_title() -> bool:
	return true


func _start_transform() -> Transform3D:
	var xf: Transform3D = world.player_start()
	if Game.has_arg("start"):
		xf.origin = world.ground(Game.arg_vec3("start"))
	if Game.has_arg("wade"):
		# Beside the pier, from the sea towards the beach, to where the water is `wade` m deep (shallow-water tests).
		var want := Game.arg_f("wade", 0.7)
		var p := xf.origin + Vector3(-4.5, 0.0, 0.0)
		for i in 600:
			if float(world.sea_level) - float(world.height_at(p.x, p.z)) <= want:
				break
			p -= xf.basis.z * 0.25 # towards where the hero faces (the island)
		xf.origin = world.ground(p)
	if Game.has_arg("face"):
		xf.basis = Basis(Vector3.UP, deg_to_rad(Game.arg_f("face", 0.0)))
	return xf


func _make_ui() -> void:
	if Game.arg_on("noui"):
		return
	var path := UI_PATH if ResourceLoader.exists(UI_PATH) else "res://scripts/ui/title_card.gd"
	ui = (load(path) as Script).new()
	ui.name = "UI"
	add_child(ui)
	Game.ui = ui


## Wolves and boars from the world's spawn groups, once their scripts exist (ENCOUNTERS stream). dummies=1 adds
## three training dummies in front of the hero for quick combat tests.
func spawn_encounters() -> void:
	for g in world.spawn_groups():
		var path := "res://scripts/enemies/%s.gd" % String(g["kind"])
		if not ResourceLoader.exists(path):
			continue
		var scr := load(path) as Script
		for i in int(g["count"]):
			var a := TAU * float(i) / maxf(1.0, float(g["count"]))
			var e: Node3D = scr.new()
			add_child(e)
			var c: Vector3 = g["center"]
			var p: Vector3 = world.ground(c + Vector3(cos(a), 0.0, sin(a)) * float(g["radius"]) * 0.5)
			if e.has_method("teleport"):
				e.call("teleport", p, randf() * TAU)
			else:
				e.global_position = p
	if Game.arg_on("dummies"):
		var xf := hero.global_transform
		for i in 3:
			var d := TrainingDummy.new()
			add_child(d)
			var off := Vector3((i - 1) * 2.6, 0.0, -5.0 - absf(i - 1) * 1.0)
			d.teleport(world.ground(xf * off), hero.facing + PI)


# --- flow ------------------------------------------------------------------------------------------------------

func show_title() -> void:
	Game.set_phase(Game.Phase.TITLE)
	hero.input_enabled = false
	cam.set_orbit(world.ground(Vector3(0, 0, 40)) + Vector3(0, 6, 0), 150.0, 48.0, 2.0)
	cam.yaw = 160.0
	Sfx.music("title")
	if ui and ui.has_method("show_title"):
		ui.call("show_title")


func start_game() -> void:
	Game.set_phase(Game.Phase.PLAY)
	hero.input_enabled = true
	if cam.mode != "fly":
		cam.follow(hero)
	Sfx.music("day")
	if ui and ui.has_method("show_play"):
		ui.call("show_play")


## The hero fell: back at the last altar (or the start) after a short pause.
func _on_hero_died() -> void:
	if Game.phase != Game.Phase.PLAY:
		return
	Game.set_phase(Game.Phase.DEAD)
	Game.slowmo(0.4, 1.0)
	_respawn_t = RESPAWN_DELAY


func _respawn() -> void:
	var xf: Transform3D = world.player_start()
	if Game.checkpoint != null and is_instance_valid(Game.checkpoint) and Game.checkpoint.has_method("respawn_transform"):
		xf = Game.checkpoint.call("respawn_transform")
	hero.revive(xf)
	cam.follow(hero)
	Game.set_phase(Game.Phase.PLAY)


## Called by the lion encounter when the labour is done.
func victory() -> void:
	Game.set_phase(Game.Phase.VICTORY)
	Sfx.play("stinger_victory")
	if hero.rig:
		hero.rig.play("victory")


func _process(delta: float) -> void:
	if _respawn_t > 0.0:
		_respawn_t -= delta / maxf(Engine.time_scale, 0.01)
		if _respawn_t <= 0.0:
			_respawn()


func _gate_input(event: InputEvent) -> void:
	if Game.phase == Game.Phase.TITLE:
		var go: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed)
		if go:
			get_viewport().set_input_as_handled()
			start_game()
		return
	if event.is_action_pressed("pause") and (Game.phase == Game.Phase.PLAY or Game.paused):
		get_viewport().set_input_as_handled()
		Game.set_paused(not Game.paused)
		if ui and ui.has_method("show_pause"):
			ui.call("show_pause", Game.paused)


## Receives input even while the tree is paused (title "press any key", pause toggle) and hands it to main.
class InputGate extends Node:
	var main: Node

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _unhandled_input(event: InputEvent) -> void:
		main.call("_gate_input", event)
