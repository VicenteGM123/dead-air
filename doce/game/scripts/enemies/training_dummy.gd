class_name TrainingDummy
extends Enemy
## A straw training dummy on a post with an old bronze helmet (no face): takes hits forever, flashes white, wobbles
## on its post (a damped spring pushed along the hit direction) and logs what hit it. Fixed in the ground: never
## moves, never dies (its hp refills two seconds after the last hit). For combat tests (tools/arena.tscn).
## Chain: &"heavy" (the hero is pulled to it). Prints "DUMMY hit <amount> <kind> hp <hp>" on every hit.

var hits := 0
var last_hit := {}
var _since := 0.0


func _init() -> void:
	display_name = "Muñeco de paja"
	max_hp = 200.0
	radius = 0.32
	height = 1.85
	lock_height = 1.35
	chain_weight = &"heavy"
	knockback_resist = 1.0
	corpse_time = -1.0


func _build() -> void:
	rig = DummyRig.new()
	add_child(rig)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.34
	cyl.height = 1.9
	cs.shape = cyl
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)


func _modify_damage(_hit: Dictionary, amount: float) -> float:
	return amount


func _on_hurt(hit: Dictionary) -> void:
	hits += 1
	last_hit = hit
	_since = 0.0
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	(rig as DummyRig).push(dir, clampf(float(hit.get("amount", 10.0)) / 12.0, 0.3, 2.0))
	var at := global_position + Vector3(0, 1.25, 0) - Vector3(dir.x, 0, dir.z).normalized() * 0.3
	if Game.fx:
		Game.fx.call("hit_spark", at, -dir, 0.8)
		Game.fx.call("dust", global_position + Vector3(0, 1.1, 0), 3, 0.3)
	Sfx.play("hit_%d" % (1 + hits % 3), global_position, -2.0, randf_range(0.9, 1.1))
	print("DUMMY hit %.1f %s hp %.0f" % [float(hit.get("amount", 0.0)), str(hit.get("kind", &"")), hp])


## Never dies: hp just refills.
func die(_hit: Dictionary = {}) -> void:
	hp = max_hp


func _think(delta: float) -> Vector3:
	_since += delta
	if _since > 2.0 and hp < max_hp:
		hp = max_hp
	return Vector3.ZERO


## The dummy's look: crossed feet, a post, a straw body with a rope belt and a crossbar for arms, a straw head
## under a dented bronze Corinthian helmet (dark eye slits only).
class DummyRig extends Rig:
	var _tilt := Vector2.ZERO # x: pitch, y: roll (radians)
	var _tilt_v := Vector2.ZERO

	func _ready() -> void:
		var mb := MeshBuilder.new(5)
		mb.vary = 0.03
		# Feet: two crossed planks on the ground, and the post.
		mb.block(Vector3(0, 0.0, 0), Vector3(1.1, 0.1, 0.16), Pal.WOOD_DARK)
		mb.block(Vector3(0, 0.0, 0), Vector3(0.16, 0.1, 1.1), Pal.WOOD_DARK)
		mb.cyl(Vector3(0, 0.0, 0), 1.0, 0.09, 0.08, 6, Pal.WOOD)
		add_part("base", mb.commit())
		var body := MeshBuilder.new(6)
		body.vary = 0.05
		var straw := Color("D9C88E")
		var straw_dark := Color("BFA868")
		body.lathe([Vector2(0.18, -0.1), Vector2(0.3, 0.05), Vector2(0.33, 0.35), Vector2(0.28, 0.62), Vector2(0.12, 0.72)], 9,
			func(c: Vector3, ring: int, side: int) -> Color: return straw if (ring + side) % 3 != 0 else straw_dark)
		body.cyl(Vector3(0, 0.22, 0), 0.07, 0.335, 0.335, 9, Pal.WOOD_LIGHT) # rope belt
		body.limb(Vector3(-0.62, 0.55, 0), Vector3(0.62, 0.55, 0), 0.05, 0.05, 6, Pal.WOOD) # arms
		body.ico(Vector3(-0.66, 0.55, 0), 0.1, straw, 0)
		body.ico(Vector3(0.66, 0.55, 0), 0.1, straw, 0)
		body.cyl(Vector3(0, 0.7, 0), 0.12, 0.07, 0.07, 6, Pal.WOOD)
		add_part("body", body.commit(), "base", Vector3(0, 1.0, 0))
		var head := MeshBuilder.new(7)
		head.vary = 0.02
		head.sphere(Vector3(0, 0.0, 0), 0.2, straw, 8, 5)
		head.sphere(Vector3(0, 0.06, 0), 0.215, Pal.BRONZE, 10, 6, Vector3(1.0, 1.05, 1.08))
		head.box(Vector3(0.07, 0.04, -0.215), Vector3(0.08, 0.035, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(-0.07, 0.04, -0.215), Vector3(0.08, 0.035, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(0, -0.06, -0.22), Vector3(0.05, 0.12, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(0, 0.27, 0.0), Vector3(0.05, 0.12, 0.42), Pal.CREST)
		add_part("head", head.commit(), "body", Vector3(0, 0.95, 0))
		set_metal(1.0)

	## Knock the body over along `dir` (world), `k` ~ 0.3 light .. 2 heavy.
	func push(dir: Vector3, k: float) -> void:
		var local := global_transform.basis.inverse() * Vector3(dir.x, 0.0, dir.z)
		# A positive x rotation tips the top towards +Z; a positive z rotation tips it towards -X.
		_tilt_v += Vector2(local.z, -local.x) * 3.2 * k

	func _animate(delta: float) -> void:
		# Damped spring back to upright.
		var acc := -_tilt * 60.0 - _tilt_v * 5.0
		_tilt_v += acc * delta
		_tilt += _tilt_v * delta
		_tilt = _tilt.limit_length(0.5)
		(parts["body"] as Node3D).rotation = Vector3(_tilt.x, 0.0, _tilt.y)
		(parts["head"] as Node3D).rotation = Vector3(_tilt.x * 0.4, 0.0, _tilt.y * 0.4)
