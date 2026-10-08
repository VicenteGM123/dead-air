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
# Animation events (see expect_event): the event we wait for, at which normalised progress, during which action.
var _pending_ev := ""
var _pending_at := 0.0
var _pending_action := ""
var _ev_done := {}


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
		# Big creatures only blush at small blows (a boss under four towers' arrows must not strobe white).
		rig.hit_flash(1.0 if not is_heavy else clampf(amount / maxf(max_hp * 0.05, 1.0), 0.18, 1.0))
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


## A blinding blow (the lens flash, the beam) cuts short the swing under way: the blow it was winding up never
## lands (the rig switches to its flinch, so its own event mark cannot fire either).
func interrupt() -> void:
	_pending_ev = ""
	_ev_done.clear()
	if rig and rig.action != "" and rig.action != "death" and rig.action != "spawn":
		rig.play("hit")


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


## Call right after rig.play(action): the blow of that action must land exactly once at normalised progress `at`,
## whether the rig emits its event (any timing) or not. The rig's own event wins if it comes first.
func expect_event(ev: String, at: float) -> void:
	_pending_ev = ev
	_pending_at = at
	_pending_action = rig.action if rig else ""
	_ev_done.clear()


## Gate for _on_rig_event: false if this event was already handled for the current action.
func accept_event(ev: String) -> bool:
	if _ev_done.has(ev):
		return false
	_ev_done[ev] = true
	if ev == _pending_ev:
		_pending_ev = ""
	return true


## Poll once per physics tick: fires the expected event when the action reaches its mark (or ends) without it.
func poll_events() -> void:
	if _pending_ev == "" or rig == null:
		return
	var same := rig.action == _pending_action
	if same and rig.ap() < _pending_at:
		return
	var ev := _pending_ev
	_pending_ev = ""
	if same or rig.action == "":
		_rig_event_fallback(ev)


func _rig_event_fallback(_ev: String) -> void:
	pass


static func yaw_to(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func dir_of_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))
