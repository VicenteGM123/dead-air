class_name Enemy
extends CharacterBody3D
## Base class for everything the hero fights (wolves, boars, the lion, the training dummy). Implements the
## combat contracts of docs/ARCHITECTURE.md so subclasses only add a body, a rig and a brain:
##   damageable  group "damageable", take_hit(hit) -> bool, is_alive() -> bool, team (1)
##   lockable    group "lockable", lock_point() -> Vector3
##   chain       group "chain_anchor", chain_point(), chain_kind() (chain_weight), on_chain_attach / pull / release
## hit = {amount: float, kind: &"blade"|&"blunt"|&"chain"|&"grapple"|&"fire", dir: Vector3, knockback: float,
##        stagger: float, source: Node}
##
## Physics: enemies layer 3, colliding with the world, the hero, other enemies and movable props. The visual
## (`rig`, any Node3D, usually a Rig) is top-level and drawn interpolated between physics ticks, so motion stays
## smooth at any frame rate.
##
## Subclass hooks (override what you need):
##   _build()                  add the rig (set `rig`) and, if the default capsule does not fit, the collision
##   _think(delta) -> Vector3  desired horizontal velocity this tick (AI); called only while alive and not staggered
##   _modify_damage(hit, amount) -> float   e.g. the lion takes 0 from blades (return 0 = no damage, no flinch)
##   _on_hurt(hit), _on_blocked(hit), _on_death(hit)
##   corpse_time               seconds the body stays after death (0 = remove at once, < 0 = keep)

signal hurt(hit: Dictionary)
signal died(enemy: Enemy)

const GRAVITY := 24.0
const KNOCKBACK_DECAY := 18.0
const CHAIN_PULL_SPEED := 9.0

var team := 1
var display_name := "Enemigo"
var max_hp := 30.0
var hp := 30.0
var alive := true
## Capsule size used by the default collision (m).
var radius := 0.45
var height := 1.2
## lock_point() height above the origin (m).
var lock_height := 0.9
## chain_kind(): &"light" (pulled to the hero), &"heavy" (the hero is pulled to it).
var chain_weight: StringName = &"light"
## 0 = full knockback, 1 = immovable.
var knockback_resist := 0.0
var corpse_time := 4.0
## Seconds left of stagger (no thinking, no attacks).
var stagger := 0.0
## Seconds left during which hits are ignored.
var invulnerable := 0.0
## Yaw the visual faces (model forward = -Z).
var facing := 0.0
var rig: Node3D = null

var _kb := Vector3.ZERO
var _chain_pull := Vector3.ZERO
var _chain_hero: Node = null
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _vis_yaw := 0.0
var _death_t := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("enemy")
	add_to_group("damageable")
	add_to_group("lockable")
	add_to_group("chain_anchor")
	hp = max_hp
	_build()
	if not _has_shape():
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(height, radius * 2.0)
		cs.shape = cap
		cs.position = Vector3(0, cap.height * 0.5, 0)
		add_child(cs)
	if rig:
		rig.top_level = true
	_curr_pos = global_position
	_prev_pos = _curr_pos
	_vis_yaw = facing


func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return true
	return false


## Moves the enemy (and its visual) without interpolating the jump.
func teleport(p: Vector3, yaw: float = facing) -> void:
	global_position = p
	facing = yaw
	_vis_yaw = yaw
	_prev_pos = p
	_curr_pos = p
	velocity = Vector3.ZERO
	_sync_visual(1.0)


# --- contracts -----------------------------------------------------------------------------------------------

func take_hit(hit: Dictionary) -> bool:
	if not alive or invulnerable > 0.0:
		return false
	var amount := _modify_damage(hit, float(hit.get("amount", 0.0)))
	if amount <= 0.0:
		_on_blocked(hit)
		return false
	hp = maxf(0.0, hp - amount)
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	dir.y = 0.0
	if dir.length_squared() > 1e-6:
		_kb = dir.normalized() * float(hit.get("knockback", 0.0)) * (1.0 - knockback_resist)
	stagger = maxf(stagger, float(hit.get("stagger", 0.0)))
	if rig and rig.has_method("hit_flash"):
		rig.call("hit_flash", 1.0)
	hurt.emit(hit)
	_on_hurt(hit)
	if hp <= 0.0:
		die(hit)
	return true


func is_alive() -> bool:
	return alive


func lock_point() -> Vector3:
	return global_position + Vector3(0, lock_height, 0)


func chain_point() -> Vector3:
	return global_position + Vector3(0, height * 0.6, 0)


func chain_kind() -> StringName:
	return chain_weight


func on_chain_attach(hero: Node) -> void:
	_chain_hero = hero
	stagger = maxf(stagger, 0.35)


## Light enemies are yanked along `dir` (towards the hero); heavy ones stay put (the hero flies to them).
func on_chain_pull(_hero: Node, dir: Vector3) -> void:
	if chain_weight == &"light":
		var d := Vector3(dir.x, 0.0, dir.z)
		if d.length_squared() > 1e-6:
			_chain_pull = d.normalized() * CHAIN_PULL_SPEED * (1.0 - knockback_resist)
			stagger = maxf(stagger, 0.3)


func on_chain_release(_hero: Node) -> void:
	_chain_hero = null


func die(hit: Dictionary = {}) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	remove_from_group("lockable")
	remove_from_group("chain_anchor")
	remove_from_group("damageable")
	# Corpses do not block the hero.
	collision_layer = 0
	collision_mask = 1
	if rig and rig.has_method("play"):
		rig.call("play", "death")
	_on_death(hit)
	died.emit(self)


# --- hooks ---------------------------------------------------------------------------------------------------

func _build() -> void:
	pass


func _think(_delta: float) -> Vector3:
	return Vector3.ZERO


func _modify_damage(_hit: Dictionary, amount: float) -> float:
	return amount


func _on_hurt(_hit: Dictionary) -> void:
	pass


func _on_blocked(_hit: Dictionary) -> void:
	pass


func _on_death(_hit: Dictionary) -> void:
	pass


# --- simulation ----------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_prev_pos = _curr_pos
	invulnerable = maxf(0.0, invulnerable - delta)
	stagger = maxf(0.0, stagger - delta)
	var want := Vector3.ZERO
	if alive and stagger <= 0.0:
		want = _think(delta)
	velocity.x = want.x + _kb.x + _chain_pull.x
	velocity.z = want.z + _kb.z + _chain_pull.z
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -1.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
	move_and_slide()
	_kb = _kb.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	_chain_pull = _chain_pull.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * 0.6 * delta)
	_curr_pos = global_position
	if not alive and corpse_time >= 0.0:
		_death_t += delta
		if _death_t >= corpse_time:
			queue_free()


func _process(delta: float) -> void:
	_vis_yaw = lerp_angle(_vis_yaw, facing, 1.0 - exp(-delta * 14.0))
	_sync_visual(Engine.get_physics_interpolation_fraction())


func _sync_visual(frac: float) -> void:
	if rig == null:
		return
	rig.global_position = _prev_pos.lerp(_curr_pos, frac)
	rig.global_rotation = Vector3(0.0, _vis_yaw, 0.0)
