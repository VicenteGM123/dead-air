class_name Boulder
extends CharacterBody3D
## The big round boulder by the lion's cave. The chain spear drags it along the ground towards the hero
## (chain_kind &"boulder": the hero holds the chain button and walks away, or stands and reels it in); the hero
## can also shove it by holding interact. It is heavy: it gathers speed slowly, stops quickly when nobody pulls,
## rolls as it scrapes along, raises dust, plays the `boulder_drag` loop while it moves and `boulder_thud` when it
## comes to rest or jams (a doorway narrower than it seals it: is_blocking(point) tells the lion encounter).
## Movable layer 4; blocked by the world, the hero, enemies and other movables, so it never passes through
## anything. Contract: chain_point(), chain_kind(), on_chain_attach / pull / release; Interactables (shove).

const RADIUS := 1.3
## Speed it is dragged at by the chain (m/s) and how fast it gets there / stops (m/s^2).
const DRAG_SPEED := 2.4
const DRAG_ACCEL := 7.0
const FRICTION := 11.0
const PUSH_SPEED := 1.4
const GRAVITY := 22.0

var _vel_h := Vector3.ZERO
var _pull_t := 0.0
var _pull_dir := Vector3.ZERO
var _push_t := 0.0
var _push_dir := Vector3.ZERO
var _mesh: MeshInstance3D
var _loop: Node = null
var _dust_d := 0.0
var _moving := false
var _jam_t := 0.0
var _jam_done := false
var _travel := 0.0


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
	if _loop != null and is_instance_valid(_loop):
		_loop.queue_free()
	_loop = null


# --- chain anchor --------------------------------------------------------------------------------------------

func chain_point() -> Vector3:
	return global_position + Vector3(0, RADIUS * 1.05, 0)


func chain_kind() -> StringName:
	return &"boulder"


func on_chain_attach(_hero: Node) -> void:
	_jam_done = false


## Dragged this tick along `dir` (horizontal part; towards the hero). The hero calls it every tick the chain is taut.
func on_chain_pull(_hero: Node, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() > 1e-4:
		_pull_dir = d.normalized()
		_pull_t = 0.12


func on_chain_release(_hero: Node) -> void:
	_pull_t = 0.0


## True when the boulder sits within `radius` m (XZ) of `point`, e.g. a cave mouth it seals.
func is_blocking(point: Vector3, radius: float = 2.5) -> bool:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length() < radius


func speed() -> float:
	return _vel_h.length()


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
		_push_dir = away.normalized()
		_push_t = 0.12


func interact_release(_hero: Node) -> void:
	_push_t = 0.0


# --- simulation ------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_pull_t -= delta
	_push_t -= delta
	var want := Vector3.ZERO
	if _pull_t > 0.0:
		want = _pull_dir * DRAG_SPEED
	elif _push_t > 0.0:
		want = _push_dir * PUSH_SPEED
	_vel_h = _vel_h.move_toward(want, (DRAG_ACCEL if want != Vector3.ZERO else FRICTION) * delta)
	velocity.x = _vel_h.x
	velocity.z = _vel_h.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	var moved := global_position - before
	moved.y = 0.0
	var dist := moved.length()
	var real := dist / maxf(delta, 1e-4)
	# what blocks it takes its speed away (no speed builds up against a wall)
	if real < _vel_h.length() * 0.5:
		_vel_h = moved / maxf(delta, 1e-4)
	# jammed (pulled but not moving: a doorway, a rock): a heavy thud, once
	if want != Vector3.ZERO and real < 0.2 and _travel > 0.5:
		_jam_t += delta
		if _jam_t > 0.3 and not _jam_done:
			_jam_done = true
			_thud(1.0)
	else:
		_jam_t = 0.0
		if real > 0.4:
			_jam_done = false
	# roll as it scrapes along (part rolling, part sliding)
	if dist > 1e-4:
		var axis := Vector3.UP.cross(moved / dist).normalized()
		_mesh.transform.basis = (Basis(axis, dist / RADIUS * 0.75) * _mesh.transform.basis).orthonormalized()
		_travel += dist
		_dust_d += dist
		if _dust_d > 0.35 and Game.fx:
			_dust_d = 0.0
			Game.fx.call("dust", global_position - moved.normalized() * RADIUS * 0.8, 2, 0.4)
	_update_sound(real)


func _update_sound(real: float) -> void:
	var moving := real > 0.3
	if moving and not _moving:
		_moving = true
		if _loop == null or not is_instance_valid(_loop):
			_loop = Sfx.loop("boulder_drag", self, -4.0)
	elif not moving and _moving and real < 0.12:
		_moving = false
		if _loop != null and is_instance_valid(_loop):
			_loop.queue_free()
		_loop = null
		if _travel > 0.8 and not _jam_done:
			_thud(0.6)


func _thud(k: float) -> void:
	Sfx.play("boulder_thud", global_position + Vector3(0, 0.5, 0), -6.0 + 5.0 * k, randf_range(0.92, 1.02))
	Game.shake(0.12 * k)
	if Game.fx:
		Game.fx.call("dust", global_position, int(4 + 6 * k), RADIUS)
