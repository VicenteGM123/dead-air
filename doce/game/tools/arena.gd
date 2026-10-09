extends "res://scripts/main.gd"
## Combat test arena: the same game (hero, camera, toon screen, sea, golden light) on a round stone platform by the
## sea (tools/arena_world.gd) with three bronze rings, a boulder, a pillar and three training dummies. No title.
##   godot --path . res://tools/arena.tscn          (or the game with scene=arena; on the web ?dev=1&scene=arena)
## Debug args work as in the game (tod=..., cam=fly pos=... yaw=... pitch=..., noui=1), plus autotest=1: lock on the
## nearest dummy (Game.lock_changed), walk up to it and swing three times; prints "ARENA ..." lines.

const ArenaWorld := preload("res://tools/arena_world.gd")

var dummies: Array = []


func _make_world() -> Node3D:
	var w: Node3D = ArenaWorld.new()
	w.name = "ArenaWorld"
	add_child(w)
	w.call("build", 1)
	return w


func _wants_title() -> bool:
	return false


func spawn_encounters() -> void:
	for i in 3:
		var d := TrainingDummy.new()
		d.name = "Dummy_%d" % i
		add_child(d)
		d.teleport(world.ground(Vector3((i - 1) * 3.2, 0.0, -4.0 - absf(i - 1) * 1.2)), PI) # facing the hero
		dummies.append(d)


var _auto_t := 0.0
var _auto_step := 0
var _swings := 0


func _physics_process(delta: float) -> void:
	if not Game.arg_on("autotest") or not Game.is_playing():
		return
	_auto_t += delta
	match _auto_step:
		0:
			if _auto_t > 0.5:
				Game.lock_changed.connect(func(t: Node) -> void: print("ARENA lock_changed -> %s" % (t.name if t else "null")))
				cam.call("_acquire_lock")
				_auto_step = 1
		1:
			var t: Node3D = cam.lock_target
			if t == null:
				print("ARENA autotest FAIL: no lock target")
				_auto_step = 9
				return
			var d := Vector2(t.global_position.x - hero.global_position.x, t.global_position.z - hero.global_position.z).length()
			hero.debug_move = Vector2(0.0, -1.0) if d > 1.6 else Vector2.ZERO
			if d <= 1.6 or _auto_t > 8.0:
				hero.debug_move = Vector2.ZERO
				_auto_step = 2
				_auto_t = 0.0
		2:
			if _auto_t > 0.55:
				_auto_t = 0.0
				hero.attack()
				_swings += 1
				if _swings >= 3:
					_auto_step = 3
		3:
			if _auto_t > 1.0:
				var hits := 0
				for dm in dummies:
					hits += int(dm.hits)
				print("ARENA autotest swings=%d dummy_hits=%d hero_hp=%.0f result=%s" % [_swings, hits, hero.hp, "PASS" if hits >= 3 else "FAIL"])
				_auto_step = 9
