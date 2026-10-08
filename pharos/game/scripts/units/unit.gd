class_name Unit
extends Node3D
## Anything with health that fights: hero, soldiers, creatures and buildings.

signal died(u: Unit)
signal damaged(u: Unit, amount: float)

var team := 0
var hp := 100.0
var max_hp := 100.0
var radius := 0.5
var alive := true
var is_building := false
var is_flying := false
var is_heavy := false
var rig: Rig = null
var invuln := 0.0
var stun := 0.0
var slow := 0.0
var slow_t := 0.0
var knock := Vector3.ZERO
var last_hit := -100.0
var display_name := ""


func _enter_tree() -> void:
	Game.register(self, team)


func _exit_tree() -> void:
	Game.unregister(self, team)


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func take_damage(amount: float, from: Node3D = null, knockback: float = 0.0, kind: String = "melee") -> float:
	if not alive or invuln > 0.0 or amount <= 0.0:
		return 0.0
	amount = _modify_damage(amount, kind, from)
	hp -= amount
	last_hit = now()
	if rig:
		rig.hit_flash()
	if knockback > 0.0 and from and not is_building:
		var d := global_position - from.global_position
		d.y = 0.0
		if d.length() < 0.01:
			d = Vector3(randf() - 0.5, 0, randf() - 0.5)
		var k := knockback * (0.35 if is_heavy else 1.0)
		knock = d.normalized() * k * 4.0
	damaged.emit(self, amount)
	if hp <= 0.0:
		hp = 0.0
		die()
	else:
		_on_hurt(amount, from, kind)
	return amount


func _modify_damage(amount: float, _kind: String, _from: Node3D) -> float:
	return amount


func _on_hurt(_amount: float, _from: Node3D, _kind: String) -> void:
	pass


func heal(v: float) -> void:
	if alive:
		hp = minf(max_hp, hp + v)


func die() -> void:
	if not alive:
		return
	alive = false
	died.emit(self)
	_on_death()


func _on_death() -> void:
	pass


func apply_slow(amount: float, seconds: float) -> void:
	slow = maxf(slow, amount)
	slow_t = maxf(slow_t, seconds)


func hp_ratio() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func flat_dist(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()


## Tick shared timers. Returns the speed multiplier from slows.
func tick_status(delta: float) -> float:
	if invuln > 0.0:
		invuln -= delta
	if stun > 0.0:
		stun -= delta
	if slow_t > 0.0:
		slow_t -= delta
		if slow_t <= 0.0:
			slow = 0.0
	if knock.length_squared() > 0.0001:
		var step := knock * delta
		_apply_knock(step)
		knock = knock.move_toward(Vector3.ZERO, delta * 22.0)
	return 1.0 - slow


func _apply_knock(step: Vector3) -> void:
	global_position += step


static func yaw_to(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func dir_of_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))
