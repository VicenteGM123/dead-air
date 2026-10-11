extends Node3D
## The merchantman moored at Nemea's pier that will take Heracles to Lerna (Interactable, on the pier next to
## the ship). Before the lion falls it only says the ship is waiting; after Game.boss_ended(true) the verb is
## "Zarpar": pressing it emits `sail_requested`; if nobody listens, it ends the slice itself (ENCOUNTERS lane L):
## the hero stands still, the camera pulls out over the ship and the golden sea, labour II's card ("Trabajo II ·
## La Hidra de Lerna · Lerna · próximamente", the UI's frieze), then the screen fades to black and the game goes
## back to the title (the UI's to_title(): the island is rebuilt and the title menu shows).

signal sail_requested(hero: Node)

## The Lerna ship (nemea_layout BOAT_LERNA), what the camera turns round while the card shows.
const SHIP := Vector3(8.6, 0.0, 132.0)
## Seconds (real time) from "Zarpar" to the fade, and of the fade itself.
const TEASER_HOLD := 8.6
const FADE := 1.5

var ready_to_sail := false
## The slice is ending (the teaser is on screen).
var sailing := false
var _t := 0.0
var _fade: ColorRect = null
var _layer: CanvasLayer = null
var _done := false


func _ready() -> void:
	add_to_group("boat")
	Interactables.add(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.has_signal("boss_ended") and not Game.is_connected("boss_ended", _on_boss_ended):
		Game.connect("boss_ended", _on_boss_ended)


func _exit_tree() -> void:
	Interactables.remove(self)


func _on_boss_ended(victory: bool) -> void:
	if victory:
		ready_to_sail = true


func can_interact(hero: Node) -> bool:
	return hero != null and Game.is_playing() and not sailing


func interact_position() -> Vector3:
	return global_position


func interact_range() -> float:
	return 2.4


func interact_info() -> Dictionary:
	if ready_to_sail:
		return {"title": "Barco a Lerna", "verb": "Zarpar", "desc": "Rumbo a Lerna", "progress": -1.0,
			"anchor": global_position + Vector3(0, 2.2, 0)}
	return {"title": "Barco a Lerna", "verb": "Mirar", "desc": "Zarpará cuando el León de Nemea caiga", "progress": -1.0,
		"anchor": global_position + Vector3(0, 2.2, 0)}


func interact_press(hero: Node) -> void:
	if not ready_to_sail:
		if Game.has_method("say"):
			Game.say("El barco a Lerna", "Primero, el León de Nemea.", "info")
		return
	if sailing:
		return
	if sail_requested.get_connections().is_empty():
		_set_sail(hero)
	else:
		sail_requested.emit(hero)


## The end of the slice: the teaser (labour II's card over the ship), then the title.
func _set_sail(hero: Node) -> void:
	sailing = true
	_t = 0.0
	if hero != null and "input_enabled" in hero:
		hero.set("input_enabled", false)
	var cam = Game.camera
	if cam != null and is_instance_valid(cam) and cam.has_method("set_orbit"):
		cam.call("set_orbit", SHIP + Vector3(0, 3.0, 0), 26.0, 9.0, 4.0)
		cam.set("yaw", 200.0)
	if Game.has_signal("labor_card"):
		Game.emit_signal("labor_card", 2, "La Hidra de Lerna")
	# a closing shot: the HUD fades out (the UI's own tween; the title screen keeps it hidden)
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and "hud" in ui:
		var hud = ui.get("hud")
		if hud != null and is_instance_valid(hud) and hud.has_method("show_hud"):
			hud.call("show_hud", false)


func _process(delta: float) -> void:
	if not sailing or _done:
		return
	_t += Game.real_delta(delta)
	if _t < TEASER_HOLD:
		return
	if _fade == null:
		_layer = CanvasLayer.new()
		_layer.layer = 120
		add_child(_layer)
		_fade = ColorRect.new()
		_fade.color = Color(0.03, 0.02, 0.02, 0.0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_layer.add_child(_fade)
	var k := clampf((_t - TEASER_HOLD) / FADE, 0.0, 1.0)
	_fade.color.a = k * k * (3.0 - 2.0 * k)
	if k >= 1.0:
		_done = true
		# (the lion's test bot stops here: the slice has ended)
		if Game.has_arg("lionbot"):
			return
		var ui = Game.ui
		if ui != null and is_instance_valid(ui) and ui.has_method("to_title"):
			ui.call("to_title")
		else:
			Game.args.erase("play")
			get_tree().reload_current_scene.call_deferred()
