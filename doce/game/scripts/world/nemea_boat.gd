extends Node3D
## The merchantman moored at Nemea's pier that will take Heracles to Lerna (Interactable, on the pier next to
## the ship). Before the lion falls it only says the ship is waiting; after Game.boss_ended(true) the verb is
## "Zarpar": pressing it emits `sail_requested` (main.gd ends the slice: the labour card "II · La Hidra de
## Lerna"); if nobody listens, it raises Game.labor_card itself.

signal sail_requested(hero: Node)

var ready_to_sail := false


func _ready() -> void:
	add_to_group("boat")
	Interactables.add(self)
	if Game.has_signal("boss_ended") and not Game.is_connected("boss_ended", _on_boss_ended):
		Game.connect("boss_ended", _on_boss_ended)


func _exit_tree() -> void:
	Interactables.remove(self)


func _on_boss_ended(victory: bool) -> void:
	if victory:
		ready_to_sail = true


func can_interact(hero: Node) -> bool:
	return hero != null and Game.is_playing()


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
	if sail_requested.get_connections().is_empty():
		if Game.has_signal("labor_card"):
			Game.emit_signal("labor_card", 2, "La Hidra de Lerna")
	else:
		sail_requested.emit(hero)
