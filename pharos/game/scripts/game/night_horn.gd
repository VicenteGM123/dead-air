class_name NightHorn
extends Node3D
## A bronze salpinx on a stand at the edge of the plaza. Holding Interact blows it and calls the night.

signal blown

const HOLD := 0.9

var _hold := 0.0
var _mesh: MeshInstance3D
var _halo: MeshInstance3D


func _ready() -> void:
	var mb := MeshBuilder.new(61)
	mb.vary = 0.03
	# Stand: a small marble pedestal with a wooden post and a crossbar.
	mb.cyl(Vector3.ZERO, 0.35, 0.42, 0.38, 6, Pal.MARBLE_SHADE)
	mb.cyl(Vector3(0, 0.35, 0), 0.08, 0.34, 0.34, 6, Pal.MARBLE)
	mb.limb(Vector3(0, 0.4, 0), Vector3(0, 1.55, 0), 0.07, 0.06, 6, Pal.WOOD)
	mb.limb(Vector3(-0.35, 1.45, 0), Vector3(0.35, 1.45, 0), 0.05, 0.05, 5, Pal.WOOD_DARK)
	# The horn: a long bronze trumpet resting on the crossbar, bell to the sea.
	mb.limb(Vector3(-0.5, 1.56, 0.05), Vector3(0.45, 1.66, 0.05), 0.03, 0.04, 6, Pal.BRONZE)
	mb.limb(Vector3(0.45, 1.66, 0.05), Vector3(0.68, 1.7, 0.05), 0.04, 0.17, 8, Pal.BRONZE.lightened(0.1))
	# Violet ribbons: the colour of the night it calls.
	mb.plate([Vector3(-0.3, 1.45, 0.06), Vector3(-0.22, 1.45, 0.06), Vector3(-0.3, 1.0, 0.1)], Pal.NYX_BODY_LIGHT)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mb.commit()
	_mesh.material_override = Materials.lowpoly()
	add_child(_mesh)
	_halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	_halo.mesh = q
	_halo.material_override = Materials.glow_add()
	_halo.position = Vector3(0.6, 1.7, 0.05)
	Materials.set_param(_halo, "tint_color", Vector3(0.7, 0.6, 1.0))
	Materials.set_param(_halo, "intensity", 0.0)
	add_child(_halo)
	Interactables.add(self)
	Obstacles.add(global_position, 0.45, self)


func _exit_tree() -> void:
	Interactables.remove(self)


func can_interact(_hero: Node) -> bool:
	return Game.phase == Game.Phase.DAY


func interact_position() -> Vector3:
	return global_position


func interact_range() -> float:
	return 2.4


func interact_info() -> Dictionary:
	return {"title": "Cuerno de la noche", "verb": "Llamar a la noche", "desc": "Noche %d de %d. Las criaturas saldrán del mar por las playas marcadas." % [Game.night + 1, Data.NIGHTS],
		"cost": 0, "paid": 0, "afford": true, "progress": _hold / HOLD, "denied": false, "anchor": global_position + Vector3(0, 2.4, 0), "kind": "horn"}


func interact_hold(delta: float, _hero: Node) -> void:
	_hold += delta
	if _hold >= HOLD:
		_hold = 0.0
		blown.emit()


func interact_release(_hero: Node) -> void:
	_hold = 0.0


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var on := Game.phase == Game.Phase.DAY
	var night: float = Game.main.tod.night_amount() if Game.main and Game.main.tod else 0.0
	Materials.set_param(_halo, "intensity", (0.1 + 0.08 * sin(t * 2.5) + 0.3 * night) * (1.0 if on else 0.0) + _hold * 1.2)
