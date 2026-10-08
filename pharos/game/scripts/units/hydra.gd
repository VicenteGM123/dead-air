class_name Hydra
extends Enemy
## Boss of the seventh night. Rises out of the sea on its beach (Data.NIGHT_WAVES), roars, and marches on the
## lighthouse: it only stops for buildings (walls, towers, houses in its way), bites Fanós and the hoplites when they
## stand in front of it (and turns on whoever keeps pestering it from the side), spits shadow orbs at towers,
## hoplites and Fanós further off, and calls its brood when wounded. Every blow is telegraphed with violet light on
## the ground: a ring fills in where a head is about to strike (the bite lands when the head does) and where each
## orb will fall. After a bite the head stays down a moment: that is the opening.

const VIOLET := Color(0.69, 0.49, 1.0) # Pal.BOSS_GLOW
## Where a head's bite lands, in the Hydra's frame (x right, z back), for the left, middle and right head: just
## behind the snout at its contact frame (measured on RigHydra's "attack": the snouts touch down 4.6-4.75 m ahead).
const BITE_POINTS := [Vector3(-0.55, 0, -4.35), Vector3(0.05, 0, -4.45), Vector3(0.7, 0, -4.35)]
## The side heads spit a little wide of the target, the middle one true.
const SPIT_SPREAD := 1.3
## Fanós or a hoplite within this angle of her heading (and within reach) gets bitten; further round, she turns on
## them after PESTER seconds.
const FRONT_DEG := 65.0
const PESTER := 1.2
## She stays put while a bite lands and the head comes back up (the punish window), then marches on.
const BITE_HOLD := 1.1

var spit_cd := 4.0
var _summons := [0.66, 0.33]
var _summon_queue := 0
var _spit_at: Unit = null
var _bite_t := -1.0
var _bite_center := Vector3.ZERO
var _marks: Array = []
var _pester_t := 0.0
var _turn_to: Unit = null


func _ready() -> void:
	super()
	# Rises from under the water for as long as the rig's "spawn" lasts, then roars on the shore line.
	spawn_time = maxf(1.0, rig.action_len)
	invuln = spawn_time + 0.2
	Sfx.play("enemy_spawn", global_position, 2.0, 0.6)
	Game.shake(0.35)


func _on_spawned() -> void:
	_roar()
	var beach := "Playa del Sur"
	if Game.island and lane < Game.island.beaches.size():
		beach = Game.island.beaches[lane]["label"]
	Game.say("La Hidra de la Noche", "Ha salido del mar por la %s" % beach, "boss")


func _roar() -> void:
	rig.play("roar")
	hold = rig.action_len
	_pending_ev = ""
	Sfx.play("hydra_roar", global_position, 4.0)
	Game.shake(0.6)


func _physics_process(delta: float) -> void:
	super(delta)
	if state == S.DEAD or state == S.SPAWN:
		return
	if _bite_t >= 0.0:
		_bite_t -= delta
		if _bite_t < 0.0:
			_bite()
	while not _summons.is_empty() and hp / max_hp <= _summons[0]:
		_summons.pop_front()
		_summon_queue += 1
	# Winding up a spit: the heads swing round to the target (she stands still meanwhile, see below).
	if rig.action == "spit" and rig.ap() < 0.47 and is_instance_valid(_spit_at):
		facing = lerp_angle(facing, Unit.yaw_to(_spit_at.global_position - global_position), 1.0 - exp(-delta * 7.0))
	# Turning on someone who kept hitting her from the side.
	if hold > 0.0 and is_instance_valid(_turn_to) and _turn_to.alive and not rig.is_busy():
		facing = lerp_angle(facing, Unit.yaw_to(_turn_to.global_position - global_position), 1.0 - exp(-delta * 5.0))
	spit_cd -= delta
	if rig.is_busy() or _bite_t >= 0.0:
		return
	if _summon_queue > 0:
		_summon_queue -= 1
		_summon()
		return
	if stun <= 0.0 and hold <= 0.0 and _bite_check(delta):
		return
	if spit_cd <= 0.0 and stun <= 0.0 and hold <= 0.0:
		var tgt := _spit_target()
		if tgt:
			spit_cd = randf_range(3.2, 4.5)
			_spit_at = tgt
			rig.play("spit")
			expect_event("release", 0.5)
			hold = maxf(hold, rig.action_len * 0.5)
		else:
			spit_cd = 1.0


## The Hydra marches on the lighthouse and only turns aside for buildings: Fanós and the hoplites never make her
## leave the lane (she bites them on the way, see _bite_check), so the climax happens in the village, under the
## towers.
func _aggro_for(u: Unit, aggro: float) -> float:
	if u.is_building:
		return super(u, aggro)
	return -1.0


func _target_ok() -> bool:
	return super() and target.is_building


## Bites Fanós or a hoplite standing in front of her; turns on one that keeps at her flank. True when it acted.
func _bite_check(delta: float) -> bool:
	if attack_cd > 0.0:
		return false
	var fwd := Unit.dir_of_yaw(facing)
	var front: Unit = null
	var front_d := INF
	var flank: Unit = null
	for u in Game.units[0]:
		if not is_instance_valid(u) or not u.alive or u.is_building:
			continue
		var d: Vector3 = u.global_position - global_position
		d.y = 0.0
		var dist: float = d.length() - u.radius
		if dist > radius + float(data["range"]):
			continue
		if d.length() < 0.01 or rad_to_deg(fwd.angle_to(d.normalized())) <= FRONT_DEG:
			if dist < front_d:
				front_d = dist
				front = u
		elif flank == null or u is Hero:
			flank = u
	if front:
		_pester_t = 0.0
		_turn_to = null
		attack_cd = float(data["rate"]) * randf_range(0.9, 1.1)
		rig.play(_attack_anim())
		_on_attack_started()
		return true
	if flank:
		_pester_t += delta
		if _pester_t >= PESTER:
			_pester_t = 0.0
			_turn_to = flank
			hold = maxf(hold, 0.7)
			return true
	else:
		_pester_t = maxf(0.0, _pester_t - delta)
	return false


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


# --- bite --------------------------------------------------------------------------------------------------

## The base class has just started "attack": mark the ground where the striking head will land and bite from our
## own clock when it gets there (meanwhile the Hydra holds still and does not turn, so the mark stays true).
func _on_attack_started() -> void:
	_pending_ev = ""
	var head := 1
	if rig is RigHydra:
		head = (rig as RigHydra).strike_head()
	var p: Vector3 = BITE_POINTS[clampi(head, 0, 2)]
	var b := Basis(Vector3.UP, facing)
	_bite_center = global_position + b * p
	_bite_center.y = Game.island.height_at(_bite_center.x, _bite_center.z)
	_bite_t = float(data.get("bite_at", 0.66))
	hold = maxf(hold, BITE_HOLD)
	_turn_to = null
	_mark(_bite_center, float(data.get("bite_radius", 3.0)), _bite_t)


func _bite() -> void:
	var r := float(data.get("bite_radius", 3.0))
	for u in Game.query(0, _bite_center, r):
		var m := 1.0
		if u.is_building:
			m = float(data.get("building_mult", 1.0))
		elif u is Hero:
			m = float(data.get("hero_mult", 1.0))
		u.take_damage(float(data["dmg"]) * m, self, 3.5, "bite")
	Sfx.play("cyclops_stomp", _bite_center, 2.0, 0.8)
	Game.shake(0.45)
	if Game.fx:
		Game.fx.ring(_bite_center, r, Color(VIOLET, 0.9), 0.45)
		Game.fx.dust(_bite_center, 12, 2.0)


# --- spit --------------------------------------------------------------------------------------------------

func _on_rig_event(ev: String) -> void:
	if state == S.DEAD or not accept_event(ev):
		return
	# The bite lands from _bite()'s clock; only the spit follows the rig.
	if ev == "release":
		_spit()


## One orb from each head's snout: the middle one at the target, the side ones a little wide of it. Each landing
## spot glows violet on the ground until its orb comes down.
func _spit() -> void:
	if _spit_at == null or not is_instance_valid(_spit_at) or not _spit_at.alive:
		return
	var right := Basis(Vector3.UP, facing) * Vector3.RIGHT
	var dmg := float(data.get("spit_dmg", 18.0))
	for i in 3:
		var from := global_position + Vector3(0, 4.0, 0) + Unit.dir_of_yaw(facing) * 2.0
		if rig is RigHydra:
			from = (rig as RigHydra).snout_position(i)
		var off := Vector3.ZERO
		if i != 1:
			off = right * (float(i - 1) * SPIT_SPREAD) + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		var it: Dictionary = Game.projectiles.orb(from, _spit_at, dmg, self, off)
		if not it.is_empty():
			var to: Vector3 = it["to"]
			_mark(Vector3(to.x, Game.island.height_at(to.x, to.z), to.z), 1.0, float(it["dur"]))
	Sfx.play("hydra_spit", global_position, 2.0)


# --- brood -------------------------------------------------------------------------------------------------

func _summon() -> void:
	_roar()
	Game.say("La Hidra llama a su prole", "", "boss")
	if Game.main and Game.main.waves:
		# On the lane, just behind her (she may have left the lane's centre to bite a building).
		var at := Game.island.lane_project(lane, global_position) if Game.island else s
		for i in 5:
			Game.main.waves.summon("shade" if i < 4 else "shielded", lane, maxf(0.0, at - 3.2 - i * 0.8))


func _on_death() -> void:
	super()
	_bite_t = -1.0
	for m in _marks:
		if is_instance_valid(m):
			m.queue_free()
	_marks.clear()
	Sfx.play("hydra_roar", global_position, 6.0, 0.6)
	Game.shake(1.0)
	Game.hitstop(0.25)
	if Game.fx:
		Game.fx.smoke(global_position + Vector3(0, 2.0, 0), 24, Color(0.3, 0.22, 0.5, 0.9))
		Game.fx.motes(global_position + Vector3(0, 2.5, 0), 40, Pal.BOSS_GLOW)
		Game.fx.flash_screen(Color(0.8, 0.7, 1.0), 0.6)
	Game.say("La Hidra ha caído", "", "boss")


# --- telegraphs --------------------------------------------------------------------------------------------

## The violet marks still on the ground, as [centre, radius, seconds left, seconds shown]: what a player sees
## (the autoplayer steps out of them).
func danger_zones() -> Array:
	var out: Array = []
	for m in _marks:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			out.append([m.global_position, m.radius, m.dur - m.t, m.t])
	return out


func _mark(center: Vector3, r: float, dur: float) -> void:
	var host: Node = Game.fx if Game.fx else get_parent()
	if host == null:
		return
	var m := GroundMark.new()
	host.add_child(m)
	m.setup(center, r, dur, VIOLET)
	_marks = _marks.filter(func(x): return is_instance_valid(x))
	_marks.append(m)


## A violet warning painted on the ground and hugging it: an outline where the blow will land and a disc that
## fills in from the centre until it does. Lives in the world (not under the Hydra), so it stays where it was put.
class GroundMark extends Node3D:
	const SEG := 32

	var radius := 3.0
	var dur := 0.66
	var t := 0.0
	var _c := Vector3.ZERO
	var _ring: MeshInstance3D
	var _fill: MeshInstance3D

	func setup(center: Vector3, r: float, d: float, col: Color) -> void:
		radius = r
		dur = maxf(d, 0.05)
		_c = Vector3(center.x, 0.0, center.z)
		global_position = _c
		_ring = _instance(col)
		_ring.mesh = _band(radius * 0.9, radius, 1.0, 1.0)
		# The fill is a deeper violet, so the disc reads as light on the ground and the outline stays the edge.
		_fill = _instance(Color(col.r * 0.8, col.g * 0.6, col.b))
		_update()

	func _instance(col: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.material_override = Materials.glow_flat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		Materials.set_param(mi, &"tint_color", Vector3(col.r, col.g, col.b))
		Materials.set_param(mi, &"intensity", 0.0)
		return mi

	## A flat band between radii r0 and r1 laid on the terrain (vertex alpha a0 inside, a1 outside).
	func _band(r0: float, r1: float, a0: float, a1: float) -> ArrayMesh:
		var v := PackedVector3Array()
		var c := PackedColorArray()
		for i in SEG:
			var t0 := TAU * float(i) / float(SEG)
			var t1 := TAU * float(i + 1) / float(SEG)
			var d0 := Vector2(cos(t0), sin(t0))
			var d1 := Vector2(cos(t1), sin(t1))
			var q := [_pt(d0 * r0), _pt(d0 * r1), _pt(d1 * r1), _pt(d1 * r0)]
			var qa := [a0, a1, a1, a0]
			for k in [0, 1, 2, 0, 2, 3]:
				v.append(q[k])
				c.append(Color(1, 1, 1, qa[k]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_COLOR] = c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	func _pt(o: Vector2) -> Vector3:
		var x := _c.x + o.x
		var z := _c.z + o.y
		var h := 0.0
		if Game.island:
			h = maxf(Game.island.facet_height_at(x, z), Game.island.height_at(x, z))
		return Vector3(o.x, maxf(h, 0.0) + 0.12, o.y)

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		_update()

	func _update() -> void:
		var k := clampf(t / dur, 0.0, 1.0)
		var fade_in := clampf(t / 0.08, 0.0, 1.0)
		Materials.set_param(_ring, &"intensity", (0.85 + 0.25 * sin(t * 20.0)) * fade_in)
		_fill.mesh = _band(0.0, maxf(radius * 0.9 * Rig.ease_out(k), 0.05), 0.3, 0.8)
		Materials.set_param(_fill, &"intensity", (0.22 + 0.33 * k) * fade_in)
