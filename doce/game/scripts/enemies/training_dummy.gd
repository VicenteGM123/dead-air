class_name TrainingDummy
extends Enemy
## Straw training dummies (arena, dummies=1). They never die (hp refills two seconds after the last hit), print
## "DUMMY hit <amount> <kind> hp <hp>" on every hit and count `hits` / keep `last_hit` for tests. Kinds:
##   &"post"      a straw man on a post under an old bronze helmet (no face): fixed; chain kind &"heavy" (the hero
##                is pulled to it); wobbles along the blow
##   &"sack"      a straw sack lashed to a little sled: chain kind &"light" (yanked to land staggered in front of
##                the hero); slides when hit
##   &"sparring"  a post with a padded club on a swinging arm: telegraphs (Enemy.telegraph: a glint, a flash),
##                then swings at a hero within reach in front (Enemy.attack_check): block it, parry it (the arm
##                is thrown back, the post reels) or roll through it. auto_attack swings every few seconds while
##                the hero is in reach; strike_soon() starts one now (tests). Every third swing is a heavy one.
##   &"straw"     a straw soldier on a little wooden foot (no post): the only one that DIES (36 hp: a full combo):
##                Enemy.die (leaves the groups: the lock-on lets go), topples along the killing blow, straw flies,
##                dissolves (corpse_time); chain kind &"light". The arena puts a new one up a few seconds later.

var kind: StringName = &"post"
var hits := 0
var last_hit := {}
## Sparring: swings on its own while the hero is within reach.
var auto_attack := true
var swings := 0
var landed := 0
var parried_count := 0
## Sparring: the verdict of the last swing (parried / blocked / dodged / hurt).
var last_verdict := &""
var _since := 0.0
var _cool := 1.2
var _strike_t := -1.0
var _heavy_swing := false


func _init(k: StringName = &"post") -> void:
	kind = k
	display_name = "Muñeco de paja"
	max_hp = 200.0
	corpse_time = -1.0
	match kind:
		&"sack":
			display_name = "Saco de paja"
			radius = 0.36
			height = 1.05
			lock_height = 0.7
			chain_weight = &"light"
			knockback_resist = 0.35
			yank_stagger = 1.0
		&"sparring":
			display_name = "Poste de entrenamiento"
			radius = 0.34
			height = 1.85
			lock_height = 1.35
			chain_weight = &"heavy"
			knockback_resist = 1.0
			parry_stagger = 1.6
		&"straw":
			display_name = "Soldado de paja"
			max_hp = 36.0
			radius = 0.3
			height = 1.75
			lock_height = 1.25
			chain_weight = &"light"
			knockback_resist = 0.6
			corpse_time = 2.4
		_:
			radius = 0.32
			height = 1.85
			lock_height = 1.35
			chain_weight = &"heavy"
			knockback_resist = 1.0


func _build() -> void:
	match kind:
		&"sack":
			rig = SackRig.new()
		&"sparring":
			rig = SparringRig.new()
		&"straw":
			rig = StrawManRig.new()
		_:
			rig = DummyRig.new()
	add_child(rig)
	var cs := CollisionShape3D.new()
	if kind == &"sack":
		var cap := CapsuleShape3D.new()
		cap.radius = 0.36
		cap.height = 1.05
		cs.shape = cap
		cs.position = Vector3(0, 0.53, 0)
	elif kind == &"straw":
		var cap2 := CapsuleShape3D.new()
		cap2.radius = 0.3
		cap2.height = 1.75
		cs.shape = cap2
		cs.position = Vector3(0, 0.875, 0)
	else:
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
	if rig.has_method("push"):
		rig.call("push", dir, clampf(float(hit.get("amount", 10.0)) / 12.0, 0.3, 2.0))
	if Game.fx:
		var at: Vector3 = hit.get("point", global_position + Vector3(0, height * 0.65, 0))
		Game.fx.call("dust", at - Vector3(0, 0.15, 0), 3, 0.25)
	print("DUMMY hit %.1f %s hp %.0f" % [float(hit.get("amount", 0.0)), str(hit.get("kind", &"")), hp])


## Never dies: hp just refills (the straw soldier does die: Enemy.die).
func die(hit: Dictionary = {}) -> void:
	if kind == &"straw":
		super.die(hit)
		return
	hp = max_hp


func _on_death(hit: Dictionary) -> void:
	var dir: Vector3 = hit.get("dir", -forward())
	if rig is StrawManRig:
		(rig as StrawManRig).fall(dir)
	if Game.fx:
		var at: Vector3 = hit.get("point", global_position + Vector3(0, 1.1, 0))
		Game.fx.call("smoke", at, 6, Color(0.85, 0.77, 0.52))
		Game.fx.call("dust", global_position, 5, 0.6)
	Sfx.play("body_fall", global_position, -4.0, 1.25)
	print("DUMMY straw down")


func _think(delta: float) -> Vector3:
	_since += delta
	if _since > 2.0 and hp < max_hp and kind != &"straw":
		hp = max_hp
	if kind != &"sparring":
		return Vector3.ZERO
	var hero = Game.hero
	if hero == null or not is_instance_valid(hero):
		return Vector3.ZERO
	face_towards(hero.global_position, delta, 3.0)
	_cool -= delta
	var dist := Combat.flat(hero.global_position - global_position).length()
	if auto_attack and _cool <= 0.0 and telegraph_t <= 0.0 and _strike_t < 0.0 and dist < 2.9 and hero.is_alive():
		strike_soon()
	return Vector3.ZERO


## Sparring: wind up now (a 0.6 s telegraph), then swing.
func strike_soon(windup: float = 0.6) -> void:
	if kind != &"sparring" or not alive:
		return
	swings += 1
	_heavy_swing = swings % 3 == 0
	_cool = 2.6
	(rig as SparringRig).windup(windup)
	telegraph(windup, (rig as SparringRig).club_point(), "", 1.3 if _heavy_swing else 1.0)


func _on_telegraph_done() -> void:
	if kind != &"sparring":
		return
	(rig as SparringRig).strike()
	_strike_t = 0.09 # the club reaches the front


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _strike_t >= 0.0:
		_strike_t -= delta
		if _strike_t < 0.0:
			_swing_hits()


func _swing_hits() -> void:
	var dmg := 16.0 if _heavy_swing else 8.0
	var h := Combat.make_hit(dmg, &"blunt", Vector3.ZERO, 7.0 if _heavy_swing else 3.5, 0.6 if _heavy_swing else 0.3, self, {"attack": &"club"})
	var n := attack_check(2.45, 75.0, h)
	landed += n
	if bool(h.get("parried", false)):
		last_verdict = &"parried"
	elif bool(h.get("dodged", false)):
		last_verdict = &"dodged"
	elif bool(h.get("blocked", false)):
		last_verdict = &"blocked"
		(rig as SparringRig).blocked()
	elif n > 0:
		last_verdict = &"hurt"
		Sfx.play("hit_%d" % randi_range(1, 3), global_position + Vector3(0, 1.4, 0), -3.0, 0.8)
	else:
		last_verdict = &"miss"
	Sfx.play("swing_2", global_position + Vector3(0, 1.4, 0), -6.0, 0.8)


func _on_parried(_hero: Node) -> void:
	parried_count += 1
	_strike_t = -1.0
	if rig is SparringRig:
		(rig as SparringRig).parried()


## The straw man's look: crossed feet, a post, a straw body with a rope belt and a crossbar for arms, a straw head
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
			func(_c: Vector3, ring: int, side: int) -> Color: return straw if (ring + side) % 3 != 0 else straw_dark)
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


## A straw sack (a rough body with a tied neck and a red rag) lashed to a little wooden sled.
class SackRig extends Rig:
	var _tilt := Vector2.ZERO
	var _tilt_v := Vector2.ZERO

	func _ready() -> void:
		var straw := Color("D9C88E")
		var straw_dark := Color("BFA868")
		var sled := MeshBuilder.new(21)
		sled.vary = 0.03
		for sx in [-1.0, 1.0]:
			sled.block(Vector3(0.24 * sx, 0.0, 0.0), Vector3(0.08, 0.07, 1.0), Pal.WOOD_DARK)
			sled.block(Vector3(0.24 * sx, 0.03, -0.52), Vector3(0.08, 0.06, 0.12), Pal.WOOD_DARK)
		for i in 4:
			sled.block(Vector3(0, 0.07, -0.36 + 0.24 * i), Vector3(0.62, 0.04, 0.14), Pal.WOOD)
		add_part("sled", sled.commit())
		var body := MeshBuilder.new(22)
		body.vary = 0.05
		body.lathe([Vector2(0.2, 0.0), Vector2(0.34, 0.12), Vector2(0.36, 0.45), Vector2(0.3, 0.72), Vector2(0.16, 0.86), Vector2(0.06, 0.92)], 9,
			func(_c: Vector3, ring: int, side: int) -> Color: return straw if (ring + side) % 3 != 0 else straw_dark)
		body.cyl(Vector3(0, 0.74, 0), 0.06, 0.19, 0.19, 9, Pal.WOOD_LIGHT) # rope round the neck
		body.cyl(Vector3(0, 0.3, 0), 0.06, 0.365, 0.365, 9, Pal.WOOD_LIGHT) # rope round the belly
		body.ico(Vector3(0, 0.98, 0), 0.1, straw_dark, 0) # the tuft
		body.block(Vector3(0.0, 0.5, -0.3), Vector3(0.36, 0.3, 0.1), Pal.CREST) # a red rag
		add_part("body", body.commit(), "sled", Vector3(0, 0.09, 0))

	func push(dir: Vector3, k: float) -> void:
		var local := global_transform.basis.inverse() * Vector3(dir.x, 0.0, dir.z)
		_tilt_v += Vector2(local.z, -local.x) * 2.6 * k

	func _animate(delta: float) -> void:
		var acc := -_tilt * 50.0 - _tilt_v * 4.5
		_tilt_v += acc * delta
		_tilt += _tilt_v * delta
		_tilt = _tilt.limit_length(0.45)
		(parts["body"] as Node3D).rotation = Vector3(_tilt.x, 0.0, _tilt.y)


## The sparring post: the straw man turns on his post; one arm of his crossbar is long and ends in a padded club
## (the spinning training dummy). windup(s) turns him back, strike() spins the club through the front, parried()
## throws him back the other way. The body yaw `_spin` (0: the club to his right, +PI/2: the club in front).
class SparringRig extends Rig:
	var _tilt := Vector2.ZERO
	var _tilt_v := Vector2.ZERO
	var _spin := 0.0
	var _spin_v := 0.0
	var _mode := 0 # 0 idle, 1 windup, 2 strike, 3 parried
	var _mode_t := 0.0
	var _wind_len := 0.6

	func _ready() -> void:
		var mb := MeshBuilder.new(5)
		mb.vary = 0.03
		mb.block(Vector3(0, 0.0, 0), Vector3(1.1, 0.1, 0.16), Pal.WOOD_DARK)
		mb.block(Vector3(0, 0.0, 0), Vector3(0.16, 0.1, 1.1), Pal.WOOD_DARK)
		mb.cyl(Vector3(0, 0.0, 0), 1.0, 0.09, 0.08, 6, Pal.WOOD)
		add_part("base", mb.commit())
		var straw := Color("D9C88E")
		var straw_dark := Color("BFA868")
		var body := MeshBuilder.new(36)
		body.vary = 0.05
		body.lathe([Vector2(0.18, -0.1), Vector2(0.3, 0.05), Vector2(0.33, 0.35), Vector2(0.28, 0.62), Vector2(0.12, 0.72)], 9,
			func(_c: Vector3, ring: int, side: int) -> Color: return straw if (ring + side) % 3 != 0 else straw_dark)
		body.cyl(Vector3(0, 0.22, 0), 0.07, 0.335, 0.335, 9, Pal.WOOD_LIGHT)
		body.cyl(Vector3(0, -0.12, 0), 0.08, 0.12, 0.12, 8, Pal.WOOD_DARK) # the turning collar on the post
		# the crossbar: a short stub to the left, a long arm to the right with a padded club
		body.limb(Vector3(-0.55, 0.55, 0), Vector3(1.32, 0.55, 0), 0.05, 0.045, 6, Pal.WOOD)
		body.ico(Vector3(-0.6, 0.55, 0), 0.1, straw, 0)
		var pad := Color("C9A86A")
		body.ico(Vector3(1.42, 0.55, 0), 0.18, pad, 1, 0.05, Vector3(1.3, 1.0, 1.0), Color("A88A50"))
		body.cyl(Vector3(1.28, 0.55, 0), 0.05, 0.12, 0.12, 8, Pal.WOOD_LIGHT)
		body.cyl(Vector3(0, 0.7, 0), 0.12, 0.07, 0.07, 6, Pal.WOOD)
		add_part("body", body.commit(), "base", Vector3(0, 1.0, 0))
		var head := MeshBuilder.new(37)
		head.vary = 0.02
		head.sphere(Vector3(0, 0.0, 0), 0.2, straw, 8, 5)
		head.sphere(Vector3(0, 0.06, 0), 0.215, Pal.BRONZE, 10, 6, Vector3(1.0, 1.05, 1.08))
		head.box(Vector3(0.07, 0.04, -0.215), Vector3(0.08, 0.035, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(-0.07, 0.04, -0.215), Vector3(0.08, 0.035, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(0, -0.06, -0.22), Vector3(0.05, 0.12, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(0, 0.27, 0.0), Vector3(0.05, 0.12, 0.42), Pal.CREST)
		add_part("head", head.commit(), "body", Vector3(0, 0.95, 0))
		set_metal(1.0)

	func club_point() -> Vector3:
		return (parts["body"] as Node3D).global_transform * Vector3(1.42, 0.55, 0)

	func push(dir: Vector3, k: float) -> void:
		var local := global_transform.basis.inverse() * Vector3(dir.x, 0.0, dir.z)
		_tilt_v += Vector2(local.z, -local.x) * 2.4 * k

	func windup(seconds: float) -> void:
		_mode = 1
		_mode_t = 0.0
		_wind_len = seconds

	func strike() -> void:
		_mode = 2
		_mode_t = 0.0

	func parried() -> void:
		_mode = 3
		_mode_t = 0.0
		_spin_v = -14.0
		push(global_transform.basis.z, 1.4)

	## The club met a raised shield: it bounces back a little.
	func blocked() -> void:
		_mode = 3
		_mode_t = 0.9
		_spin_v = -7.0
		push(global_transform.basis.z, 0.5)

	func _animate(delta: float) -> void:
		var acc := -_tilt * 60.0 - _tilt_v * 5.0
		_tilt_v += acc * delta
		_tilt += _tilt_v * delta
		_tilt = _tilt.limit_length(0.5)
		_mode_t += delta
		match _mode:
			1:
				# turn back, the club drawn behind the right shoulder (the readable part), then hold
				var g := -1.05 * Rig.ease_out(minf(_mode_t / maxf(_wind_len * 0.75, 0.05), 1.0))
				_spin = lerpf(_spin, g, 1.0 - exp(-delta * 12.0))
				_spin_v = 0.0
			2:
				# spin the club through the front, overshoot to the left, settle back
				_spin = lerpf(_spin, 2.7, 1.0 - exp(-delta * 18.0))
				if _mode_t > 0.45:
					_mode = 0
					_spin_v = 0.0
			3:
				_spin_v += (-(_spin) * 25.0 - _spin_v * 2.2) * delta
				_spin += _spin_v * delta
				if _mode_t > 1.5:
					_mode = 0
			_:
				_spin = lerpf(_spin, sin(t * 0.7) * 0.12, 1.0 - exp(-delta * 2.5))
		(parts["body"] as Node3D).rotation = Vector3(_tilt.x, _spin, _tilt.y)


## The straw soldier: a straw man on two stick legs and a round wooden foot, a rope belt, a crossbar for arms, the
## same bronze helmet as the posts (dark eye slits, a red crest; no face). push() wobbles him; fall() (his death)
## topples him over the edge of his foot along the killing blow, with a little bounce, and he lies there.
class StrawManRig extends Rig:
	var _tilt := Vector2.ZERO
	var _tilt_v := Vector2.ZERO
	var _fall_t := -1.0
	var _fall_axis := Vector3.RIGHT
	var _fall_pivot := Vector3.ZERO

	func _ready() -> void:
		var straw := Color("D9C88E")
		var straw_dark := Color("BFA868")
		var foot := MeshBuilder.new(41)
		foot.vary = 0.03
		foot.cyl(Vector3(0, 0.0, 0), 0.08, 0.27, 0.25, 9, Pal.WOOD_DARK)
		foot.cyl(Vector3(0, 0.08, 0), 0.3, 0.05, 0.045, 6, Pal.WOOD)
		add_part("foot", foot.commit())
		var body := MeshBuilder.new(42)
		body.vary = 0.05
		# legs: two bundles of straw tied at the knee
		for sx in [-1.0, 1.0]:
			body.limb(Vector3(0.09 * sx, 0.1, 0.0), Vector3(0.1 * sx, 0.5, 0.0), 0.07, 0.08, 7, straw_dark)
			body.limb(Vector3(0.1 * sx, 0.5, 0.0), Vector3(0.11 * sx, 0.85, 0.0), 0.085, 0.1, 7, straw)
			body.cyl(Vector3(0.1 * sx, 0.47, 0.0), 0.05, 0.085, 0.085, 7, Pal.WOOD_LIGHT)
		body.lathe([Vector2(0.17, 0.8), Vector2(0.26, 0.92), Vector2(0.28, 1.15), Vector2(0.25, 1.38), Vector2(0.11, 1.48)], 9,
			func(_c: Vector3, ring: int, side: int) -> Color: return straw if (ring + side) % 3 != 0 else straw_dark)
		body.cyl(Vector3(0, 0.98, 0), 0.07, 0.285, 0.285, 9, Pal.WOOD_LIGHT) # rope belt
		body.block(Vector3(0.0, 1.08, -0.22), Vector3(0.36, 0.26, 0.08), Pal.CREST) # a red rag for a tunic
		body.limb(Vector3(-0.56, 1.32, 0), Vector3(0.56, 1.32, 0), 0.045, 0.045, 6, Pal.WOOD) # arms
		body.ico(Vector3(-0.6, 1.32, 0), 0.09, straw, 0)
		body.ico(Vector3(0.6, 1.32, 0), 0.09, straw, 0)
		add_part("body", body.commit(), "foot", Vector3.ZERO)
		var head := MeshBuilder.new(43)
		head.vary = 0.02
		head.sphere(Vector3(0, 0.0, 0), 0.19, straw, 8, 5)
		head.sphere(Vector3(0, 0.06, 0), 0.205, Pal.BRONZE, 10, 6, Vector3(1.0, 1.05, 1.08))
		head.box(Vector3(0.065, 0.04, -0.205), Vector3(0.075, 0.033, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(-0.065, 0.04, -0.205), Vector3(0.075, 0.033, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(0, -0.06, -0.21), Vector3(0.05, 0.11, 0.05), Pal.SKIN_SHADOW)
		head.box(Vector3(0, 0.26, 0.0), Vector3(0.05, 0.11, 0.4), Pal.CREST)
		add_part("head", head.commit(), "body", Vector3(0, 1.62, 0))
		set_metal(1.0)

	func push(dir: Vector3, k: float) -> void:
		if _fall_t >= 0.0:
			return
		var local := global_transform.basis.inverse() * Vector3(dir.x, 0.0, dir.z)
		_tilt_v += Vector2(local.z, -local.x) * 3.0 * k

	## Topples over along `dir_world` (his death): onto his back or his front, whichever is nearer the blow (so
	## the crossbar arms end up level, never through the ground), rolling over the edge of his round foot, which
	## leaves his body resting on the ground (its axis at the foot's radius, 0.26 m).
	func fall(dir_world: Vector3) -> void:
		var local := global_transform.basis.inverse() * Vector3(dir_world.x, 0.0, dir_world.z)
		var back := local.z >= 0.0
		_fall_axis = Vector3.RIGHT if back else Vector3.LEFT
		_fall_pivot = Vector3(0.0, 0.0, 0.26 if back else -0.26)
		_fall_t = 0.0

	func _action_length(a: String) -> float:
		return 0.9 if a == "death" else 0.3

	func _animate(delta: float) -> void:
		if _fall_t >= 0.0:
			# like a felled post: slow to start, quick at the end, a small bounce on the ground, then still
			_fall_t += delta
			var ang := 0.0
			var u := _fall_t / 0.5
			if u < 1.0:
				ang = PI * 0.5 * u * u
			else:
				var b := _fall_t - 0.5
				ang = PI * 0.5 - 0.13 * absf(sin(b * 9.0)) * exp(-b * 7.0)
			var bas := Basis(_fall_axis, ang)
			(parts["foot"] as Node3D).transform = Transform3D(bas, _fall_pivot - bas * _fall_pivot)
			(parts["body"] as Node3D).rotation = Vector3.ZERO
			return
		var acc := -_tilt * 55.0 - _tilt_v * 5.0
		_tilt_v += acc * delta
		_tilt += _tilt_v * delta
		_tilt = _tilt.limit_length(0.5)
		(parts["body"] as Node3D).rotation = Vector3(_tilt.x, 0.0, _tilt.y)
		(parts["head"] as Node3D).rotation = Vector3(_tilt.x * 0.4, 0.0, _tilt.y * 0.4)
