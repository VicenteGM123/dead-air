class_name Boulder
extends CharacterBody3D
## The big round boulder by the lion's cave: the chain spear drags it along the ground towards the hero
## (chain_kind &"boulder") and the hero can shove it by holding interact. Rolls as it moves. Movable layer 4;
## blocked by the world, the hero, enemies and other movables, so it never passes through anything.
## STUB behaviour (CORE refines the drag feel with the chain spear): on_chain_pull(hero, dir) drags it along `dir`
## at DRAG_SPEED for a moment; is_blocking(point) tells the lion encounter whether a cave mouth is closed.

const RADIUS := 1.3
const DRAG_SPEED := 3.2
const PUSH_SPEED := 1.4
const GRAVITY := 22.0

var _drag := Vector3.ZERO
var _mesh: MeshInstance3D
var _pushing := false


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.5
	add_to_group("chain_anchor")
	add_to_group("boulder")
	var mb := MeshBuilder.new(77)
	mb.vary = 0.04
	mb.ico(Vector3.ZERO, RADIUS, Pal.ROCK, 1, 0.07, Vector3(1.0, 0.95, 1.0), Pal.ROCK_DARK)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mb.commit()
	_mesh.material_override = Materials.lowpoly()
	_mesh.position = Vector3(0, RADIUS * 0.95, 0)
	add_child(_mesh)
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RADIUS * 0.97
	col.shape = sh
	col.position = Vector3(0, RADIUS * 0.95, 0)
	add_child(col)
	Interactables.add(self)


func _exit_tree() -> void:
	Interactables.remove(self)


# --- chain anchor --------------------------------------------------------------------------------------------

func chain_point() -> Vector3:
	return global_position + Vector3(0, RADIUS, 0)


func chain_kind() -> StringName:
	return &"boulder"


func on_chain_attach(_hero: Node) -> void:
	Sfx.play("structure_hit", chain_point(), -6.0, 0.7)


## Drags the boulder along `dir` (horizontal part; normally towards the hero) for a short while.
func on_chain_pull(_hero: Node, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() > 1e-4:
		_drag = d.normalized() * DRAG_SPEED


func on_chain_release(_hero: Node) -> void:
	pass


## True when the boulder sits within `radius` m (XZ) of `point`, e.g. a cave mouth it seals.
func is_blocking(point: Vector3, radius: float = 2.5) -> bool:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length() < radius


# --- interactable: shove it ----------------------------------------------------------------------------------

func can_interact(hero: Node) -> bool:
	return Game.phase == Game.Phase.PLAY and hero is Node3D and (hero as Node3D).global_position.y < global_position.y + RADIUS


func interact_position() -> Vector3:
	return global_position


func interact_range() -> float:
	return RADIUS + 1.3


func interact_info() -> Dictionary:
	return {"title": "Roca", "verb": "Empujar", "desc": "Pesa como un buey", "progress": -1.0,
		"anchor": global_position + Vector3(0, RADIUS * 2.0 + 0.5, 0)}


func interact_hold(_delta: float, hero: Node) -> void:
	var away := global_position - (hero as Node3D).global_position
	away.y = 0.0
	if away.length_squared() > 1e-4:
		_drag = away.normalized() * PUSH_SPEED
		_pushing = true


func interact_release(_hero: Node) -> void:
	_pushing = false


func _physics_process(delta: float) -> void:
	velocity.x = _drag.x
	velocity.z = _drag.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	_drag = _drag.move_toward(Vector3.ZERO, delta * (2.0 if _pushing else 5.0))
	# Roll: rotate about the axis perpendicular to the motion by distance / radius.
	var moved := global_position - before
	moved.y = 0.0
	var dist := moved.length()
	if dist > 1e-4:
		var axis := Vector3.UP.cross(moved / dist).normalized()
		_mesh.transform.basis = Basis(axis, dist / RADIUS) * _mesh.transform.basis
		_mesh.transform.basis = _mesh.transform.basis.orthonormalized()
