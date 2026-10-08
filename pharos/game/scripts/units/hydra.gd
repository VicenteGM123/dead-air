class_name Hydra
extends Enemy
## Boss of the seventh night. Crawls out of the sea on the southern beach; bites anything in front of it,
## spits shadow orbs at towers and the Keeper, and calls shades when wounded.

var spit_cd := 4.0
var _summons := [0.66, 0.33]
var _roared := false


func _ready() -> void:
	super()
	invuln = 2.5
	Sfx.play("hydra_roar", global_position, 4.0)
	Game.shake(0.5)


func _physics_process(delta: float) -> void:
	super(delta)
	if state == S.DEAD or state == S.SPAWN:
		return
	if not _roared and _t > 2.5:
		_roared = true
		Game.say("La Hidra de la Noche", "Ha salido del mar por la Playa del Sur", "boss")
	spit_cd -= delta
	if spit_cd <= 0.0 and not rig.is_busy() and stun <= 0.0:
		var tgt := _spit_target()
		if tgt:
			spit_cd = randf_range(3.2, 4.5)
			facing = Unit.yaw_to(tgt.global_position - global_position)
			_spit_at = tgt
			rig.play("spit")
		else:
			spit_cd = 1.0
	while not _summons.is_empty() and hp / max_hp <= _summons[0]:
		_summons.pop_front()
		_summon()


var _spit_at: Unit = null


func _spit_target() -> Unit:
	var best: Unit = null
	var best_d := 15.0
	for u in Game.units[0]:
		if not is_instance_valid(u) or not u.alive:
			continue
		if not (u is TowerBuilding or u is Hero or u is Soldier):
			continue
		var d: float = u.flat_dist(global_position)
		if d < best_d and d > 4.0:
			best_d = d
			best = u
	return best


func _on_rig_event(ev: String) -> void:
	if state == S.DEAD:
		return
	if ev == "release" and _spit_at and is_instance_valid(_spit_at):
		var from := global_position + Vector3(0, 4.0, 0) + Unit.dir_of_yaw(facing) * 2.0
		for i in 3:
			var off := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
			Game.projectiles.orb(from, _spit_at, 18.0, self)
			if i == 0:
				continue
			# Spread shots land around the target.
			var last: Dictionary = Game.projectiles._items[Game.projectiles._items.size() - 1]
			last["to"] = last["to"] + off
		Sfx.play("hydra_spit", from, 2.0)
		return
	if ev == "impact":
		# Bite: a wide arc in front.
		var center := global_position + Unit.dir_of_yaw(facing) * (radius + 1.6)
		for u in Game.query(0, center, 3.0):
			var m := float(data.get("building_mult", 1.0)) if u.is_building else 1.0
			u.take_damage(float(data["dmg"]) * m, self, 3.5, "bite")
		Sfx.play("cyclops_stomp", center, 2.0, 0.8)
		Game.shake(0.45)
		if Game.fx:
			Game.fx.ring(center, 3.0, Color(0.7, 0.5, 1.0, 0.8), 0.45)
			Game.fx.dust(center, 12, 2.0)


func _summon() -> void:
	rig.play("roar")
	Sfx.play("hydra_roar", global_position, 3.0, 0.9)
	Game.shake(0.6)
	Game.say("La Hidra llama a su prole", "", "boss")
	if Game.main and Game.main.waves:
		for i in 5:
			var e: Enemy = Game.main.waves.spawn("shade" if i < 4 else "shielded", lane)
			e.s = maxf(0.0, s - 3.0 - i * 0.8)
			e.global_position = _lane_point(e.s)


func _on_death() -> void:
	super()
	Sfx.play("hydra_roar", global_position, 6.0, 0.6)
	Game.shake(1.0)
	Game.hitstop(0.25)
	if Game.fx:
		Game.fx.smoke(global_position + Vector3(0, 2.0, 0), 24, Color(0.3, 0.22, 0.5, 0.9))
		Game.fx.motes(global_position + Vector3(0, 2.5, 0), 40, Pal.BOSS_GLOW)
		Game.fx.flash_screen(Color(0.8, 0.7, 1.0), 0.6)
	Game.say("La Hidra ha caído", "", "boss")
