class_name Soldier
extends Unit
## Allied hoplite. Guards a post in front of its barracks and engages creatures that come close.

const GUARD_RADIUS := 7.0
## A doru thrust over the crest of the squad's own wall reaches this much further than a blow in the open.
const WALL_REACH := 1.3
## Where the squad stands to spear over its wall: this far behind the wall's line.
const WALL_STAND := 1.32

var barracks: Node3D = null
var slot := 0
var dmg := 8.0
var speed := 3.6
var target: Unit = null
var attack_cd := 0.0
var _retarget := 0.0
var _vel := Vector3.ZERO
var facing := 0.0
var _dead_t := 0.0


func _ready() -> void:
	team = 0
	radius = 0.42
	display_name = "Hoplita"
	rig = RigHoplite.new(true)
	add_child(rig)
	rig.event.connect(_on_rig_event)
	facing = PI


func apply_stats(hp_v: float, dmg_v: float) -> void:
	max_hp = hp_v
	if alive:
		hp = max_hp
	dmg = dmg_v


func post() -> Vector3:
	if not is_instance_valid(barracks):
		return global_position
	var rp: Vector3 = barracks.rally_point()
	var count: int = maxi(1, barracks.soldiers.size())
	var a := (float(slot) - float(count - 1) * 0.5) * 1.6
	var side: Vector3 = barracks.rally_side() if barracks.has_method("rally_side") else barracks.global_transform.basis.x.normalized()
	return rp + side * a


func revive(at: Vector3) -> void:
	if alive:
		hp = max_hp
		return
	alive = true
	hp = max_hp
	visible = true
	rig.action = ""
	rig.set_dissolve(0.0)
	rig.rotation = Vector3.ZERO
	global_position = Game.island.ground(at)
	Game.register(self, team)


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		if _dead_t > 1.0:
			rig.set_dissolve(clampf((_dead_t - 1.0) / 0.8, 0.0, 1.0))
			if _dead_t > 1.9:
				visible = false
		return
	var smul := tick_status(delta)
	poll_events()
	attack_cd = maxf(0.0, attack_cd - delta)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.3
		_pick_target()
	var goal := post()
	var move := Vector3.ZERO
	if stun > 0.0:
		pass
	elif target and is_instance_valid(target) and target.alive:
		var d := target.global_position - global_position
		d.y = 0.0
		var wall := _wall_between(target)
		var reach := radius + target.radius + 0.9 + (WALL_REACH if wall else 0.0)
		if d.length() > reach:
			if wall:
				# Hold the wall: step up right behind it, facing the creature, and wait for it to come in reach.
				var st := _wall_stand(wall, target.global_position)
				var ds := st - global_position
				ds.y = 0.0
				if ds.length() > 0.25:
					move = ds.normalized() * speed * clampf(ds.length() / 1.5, 0.35, 1.0)
				else:
					facing = lerp_angle(facing, Unit.yaw_to(d), 1.0 - exp(-delta * 12.0))
			else:
				move = _around_wall(target.global_position, d.normalized() * speed)
		else:
			facing = lerp_angle(facing, Unit.yaw_to(d), 1.0 - exp(-delta * 12.0))
			if attack_cd <= 0.0 and not rig.is_busy():
				attack_cd = 1.0
				rig.play("attack%d" % (randi() % 2 + 1))
				expect_event("impact", 0.38)
	else:
		var d := goal - global_position
		d.y = 0.0
		if d.length() > 0.4:
			move = _around_wall(goal, d.normalized() * speed * clampf(d.length() / 2.0, 0.3, 1.0))
	move *= smul
	_vel = _vel.lerp(move, 1.0 - exp(-delta * 10.0))
	if _vel.length() > 0.3:
		facing = lerp_angle(facing, Unit.yaw_to(_vel), 1.0 - exp(-delta * 10.0))
	var p := global_position + _vel * delta
	p = Separation.apply(self, p, 0)
	p = Obstacles.push_out(p, radius)
	if Game.island.is_walkable(p.x, p.z):
		global_position = Vector3(p.x, Game.island.height_at(p.x, p.z), p.z)
	rig.rotation.y = facing
	rig.set_locomotion(_vel.length(), speed)
	if not Game.is_night() and hp < max_hp:
		heal(delta * 20.0)


func _pick_target() -> void:
	if target and is_instance_valid(target) and target.alive and target.flat_dist(post()) < GUARD_RADIUS + 3.0:
		return
	target = null
	var best_d := GUARD_RADIUS
	var at := post()
	for e in Game.units[1]:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: float = e.flat_dist(at)
		# Keres fly over the squad: the hoplites only raise their spears at those that swoop in close.
		if e.is_flying and d > 4.5:
			continue
		if d < best_d:
			best_d = d
			target = e


func _rig_event_fallback(ev: String) -> void:
	_on_rig_event(ev)


func _on_rig_event(ev: String) -> void:
	if ev != "impact" or not alive or not accept_event(ev):
		return
	if target and is_instance_valid(target) and target.alive:
		var reach := radius + target.radius + 1.4 + (WALL_REACH if _wall_between(target) else 0.0)
		if flat_dist(target.global_position) <= reach:
			target.take_damage(dmg, self, 0.5, "melee")
			Sfx.play("soldier_hit", global_position, -10.0, randf_range(0.9, 1.15))
			if Game.fx:
				Game.fx.hit_spark(target.global_position + Vector3(0, 1.0, 0), Unit.dir_of_yaw(facing), 0.6)


## The squad's own lane wall (alive), if `t` is on its far side and we are on the near one.
func _wall_between(t: Node3D) -> WallBuilding:
	var w := _lane_wall()
	if w == null:
		return null
	if w.side_of(global_position) > 0.0 and w.side_of(t.global_position) < 0.0:
		return w
	return null


func _lane_wall() -> WallBuilding:
	if not is_instance_valid(barracks) or int(barracks.lane) < 0:
		return null
	return WallBuilding.blocking(int(barracks.lane), -1.0e9, 1.0e9)


## Right behind the wall, across from `at` (clear of the palisade's props).
func _wall_stand(w: WallBuilding, at: Vector3) -> Vector3:
	var lx := (w.global_transform.affine_inverse() * at).x
	lx = clampf(lx, -WallBuilding.HALF + 0.9, WallBuilding.HALF - 0.9)
	if w.level == 1:
		for px in [-2.7, 0.0, 2.7]:
			if absf(lx - px) < 0.45:
				lx = px + (0.45 if lx >= px else -0.45)
	return w.global_transform * Vector3(lx, 0, WALL_STAND)


## A standing wall between us and `dest` (we are outside it, say after chasing a creature through the breach before
## the wall was rebuilt at dawn): walk round its nearer end instead of pushing into it.
func _around_wall(dest: Vector3, want: Vector3) -> Vector3:
	var w := _lane_wall()
	if w == null or want.length() < 0.01:
		return want
	var inv := w.global_transform.affine_inverse()
	var a := inv * global_position
	var b := inv * dest
	if signf(a.z) == signf(b.z) or absf(a.z) > 4.0:
		return want
	# Where the straight way would cross the wall's line: beyond its ends there is nothing to walk round.
	var xc := lerpf(a.x, b.x, a.z / (a.z - b.z))
	if absf(xc) > WallBuilding.HALF + 0.7:
		return want
	var ex := (WallBuilding.HALF + 1.2) * (1.0 if xc >= 0.0 else -1.0)
	var corner := Vector3(ex, 0, signf(a.z) * 0.9)
	if Vector2(a.x - corner.x, a.z - corner.z).length() < 0.6:
		corner = Vector3(ex, 0, signf(b.z) * 1.4)
	var d := w.global_transform * corner - global_position
	d.y = 0.0
	return d.normalized() * want.length() if d.length() > 0.01 else want


func _on_hurt(_amount: float, _from: Node3D, _kind: String) -> void:
	if not rig.is_busy():
		rig.play("hit")


func _on_death() -> void:
	_dead_t = 0.0
	rig.play("death")
	Game.unregister(self, team)
	Sfx.play("soldier_hit", global_position, -4.0, 0.7)
