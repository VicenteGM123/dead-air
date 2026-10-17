extends "res://tools/arena.gd"
## FX lane demo: the arena (the real hero, gameplay camera, toon screen, straw posts) with a driver that plays the
## hero's blows at a straw post through the bot input path and calls the feel tools the way the move tables will
## (trail style per blow, Fx.slash_mark at the contact, Game.kick along the cut, Game.fov_punch on the closing
## blows, Fx.slam for a chop into the ground and a dash's landing, the new sounds). The base moveset has no thrust:
## a stand-in sword (the hero's own hidden for that beat) thrusts at the post to show the &"thrust" trail and the
## pierce flash.
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --write-movie <dir>/f.png --fixed-fps 30 --quit-after 400 res://tools/fx_demo.tscn \
##     -- noui=1 quit=1 [demo=a,b,...]
## Beats (demo=, default all, in this order): combo (light, light, finisher), heavy (the charged spin), thrust,
## (not in the default list: air, the combo and the heavy swung at nothing in the open: each trail's whole arc)
## slam (a chop's slam on stone, power 1; on sand and on grass beside the hero; a dash's landing, power 0.6).
## Also (tools/fx_demo_world.tscn, the island): slamw (the same slams on the world's own ground), slam1 (one chop's
## slam there), beach (the hero taken to the sand by the pier), probe (prints the ground kinds round the beach and
## the wolves' clearing).
## Prints "FXDEMO mark <tag> frame=<n>" (n = the movie frame: frames since the first one drawn) at each beat's
## start, each contact and each slam; "FXDEMO done" at the end (then quits with quit=1).

const ALL_BEATS := ["combo", "heavy", "thrust", "slam"]


func spawn_encounters() -> void:
	super.spawn_encounters()
	var d := Driver.new()
	d.name = "FxDemo"
	d.arena = self
	add_child(d)


class Driver extends Node:
	var arena: Node = null
	var hero: Hero
	var cam: CameraRig
	var post: Node3D
	var _time := 0.0
	var _prev_tip := Vector3.ZERO
	var _cut := Vector3.ZERO
	var _blow := &""
	var _stand: StandIn = null
	var _frame0 := -1

	func _ready() -> void:
		process_priority = 30 # after the rig (the blade's motion this frame)
		_run.call_deferred()

	func _physics_process(delta: float) -> void:
		_time += delta

	func _process(_delta: float) -> void:
		if _frame0 < 0:
			_frame0 = Engine.get_process_frames()
		if hero == null:
			return
		var seg := hero.rig.blade_segment()
		if _prev_tip != Vector3.ZERO and seg[1].distance_to(_prev_tip) > 0.02:
			_cut = seg[1] - _prev_tip
		_prev_tip = seg[1]
		# the trail's style per blow (the move tables' `trail` key)
		var nm: StringName = hero.melee.cur.get("name", &"") if not hero.melee.cur.is_empty() else &""
		if nm != _blow:
			_blow = nm
			match String(nm):
				"attack1", "attack2":
					hero.melee.trail.style = &"light"
				"attack3":
					hero.melee.trail.style = &"finisher"
				"heavy":
					hero.melee.trail.style = &"heavy"

	func _mark(tag: String) -> void:
		print("FXDEMO mark %s frame=%d t=%.2f" % [tag, Engine.get_process_frames() - maxi(_frame0, 0), _time])

	func _wait(s: float) -> void:
		var t0 := _time
		while _time - t0 < s:
			await get_tree().physics_frame

	func _tap(action: StringName, hold: float = 0.05) -> void:
		hero.inp.bot[action] = true
		await _wait(hold)
		hero.inp.bot[action] = false
		await get_tree().physics_frame

	func _place(p: Vector3, look: Vector3) -> void:
		var d := Combat.flat(look - p).normalized()
		var z := -d
		var x := Vector3.UP.cross(z).normalized()
		hero.teleport(Transform3D(Basis(x, Vector3.UP, z), p))
		hero.stamina = hero.max_stamina
		hero.exhausted = false
		hero.hp = hero.max_hp
		cam.lock_on(null)
		cam.follow(hero, true)
		await _wait(0.3)

	func _run() -> void:
		while arena.get("hero") == null or arena.get("cam") == null:
			await get_tree().process_frame
		hero = arena.get("hero")
		cam = arena.get("cam")
		await get_tree().process_frame
		post = _find_post()
		var sp = arena.get("sparring")
		if sp is TrainingDummy:
			(sp as TrainingDummy).auto_attack = false
		hero.blow_landed.connect(_on_blow)
		await _wait(0.5)
		var beats: Array = ALL_BEATS
		if Game.has_arg("demo"):
			beats = Array(String(Game.arg("demo")).split(",", false))
		for b in beats:
			match String(b):
				"combo":
					await _beat_combo()
				"air":
					await _beat_air()
				"heavy":
					await _beat_heavy()
				"thrust":
					await _beat_thrust()
				"slam":
					await _beat_slam()
				"slamw":
					await _beat_slam_world()
				"slam1":
					_mark("slam1")
					_slam(hero.global_position + hero.forward() * 1.3 + hero.forward().cross(Vector3.UP).normalized() * 0.5, 1.0, "")
					Game.hitstop(0.06)
					await _wait(1.0)
				"beach":
					await _beat_beach()
				"probe":
					_probe()
		_mark("done")
		print("FXDEMO done")
		if Game.arg_on("quit"):
			get_tree().quit()

	# --- the beats ---------------------------------------------------------------------------------------------

	func _beat_combo() -> void:
		await _place(post.global_position + Vector3(0, 0, 2.3), post.global_position)
		_mark("combo")
		await _tap(&"attack")
		await _wait(0.3)
		await _tap(&"attack")
		await _wait(0.3)
		await _tap(&"attack")
		await _wait(1.0)

	## The combo and the heavy swung at nothing, in the open (each trail's whole arc, no hit-stop cutting it).
	func _beat_air() -> void:
		await _place(post.global_position + Vector3(0, 0, 4.5), post.global_position + Vector3(0, 0, 14.0))
		_mark("air")
		await _tap(&"attack")
		await _wait(0.3)
		await _tap(&"attack")
		await _wait(0.3)
		await _tap(&"attack")
		await _wait(1.0)
		_mark("air_heavy")
		hero.inp.bot[&"attack"] = true
		await _wait(0.75)
		hero.inp.bot[&"attack"] = false
		await _wait(1.0)

	func _beat_heavy() -> void:
		await _place(post.global_position + Vector3(0, 0, 2.1), post.global_position)
		_mark("heavy")
		hero.inp.bot[&"attack"] = true
		await _wait(0.75)
		hero.inp.bot[&"attack"] = false
		await _wait(1.1)

	## The stand-in: the hero's sword hidden, a sword thrust from his right hip at the post (0.1 s out, a beat held,
	## back), the trail in its thrust style; at full reach the contact's calls.
	func _beat_thrust() -> void:
		await _place(post.global_position + Vector3(0.25, 0, 1.9), post.global_position + Vector3(0.25, 0, 0))
		var sw: Node3D = hero.rig.get("_sword")
		if sw:
			sw.visible = false
		_stand = StandIn.new()
		add_child(_stand)
		var trail := BladeTrail.new()
		trail.rig = _stand
		trail.process_priority = 20
		trail.style = &"thrust"
		add_child(trail)
		var fwd := hero.forward()
		var right := fwd.cross(Vector3.UP).normalized()
		var base := hero.global_position + right * 0.3 + Vector3(0, 1.05, 0)
		var a := base - fwd * 0.35
		var b := base + fwd * 0.75 + Vector3(0, 0.08, 0)
		_stand.pose(a, fwd)
		_mark("thrust")
		await _wait(0.25)
		Sfx.play("swing_thrust", hero.global_position + Vector3(0, 1.2, 0), -3.0)
		trail.active = true
		var t0 := _time
		while _time - t0 < 0.1:
			var k := clampf((_time - t0) / 0.1, 0.0, 1.0)
			_stand.pose(a.lerp(b, 1.0 - (1.0 - k) * (1.0 - k)), fwd)
			await get_tree().physics_frame
		_stand.pose(b, fwd)
		var tip := b + fwd * 1.0
		var point := post.global_position + Vector3(0.0, tip.y - post.global_position.y, 0.0) - fwd * 0.22
		_mark("thrust_hit")
		Game.fx.impact(point, fwd, 1.0)
		Game.fx.slash_mark(point, fwd, 1.5, Color(1.0, 0.8, 0.42))
		Sfx.play("hit_thrust", point, -1.0)
		Game.hitstop(0.1)
		Game.shake(0.4)
		Game.kick(fwd, 1.0)
		Game.fov_punch(2.5, 0.25)
		await _wait(0.06)
		trail.active = false
		await _wait(0.25)
		var t1 := _time
		while _time - t1 < 0.2:
			_stand.pose(b.lerp(a, clampf((_time - t1) / 0.2, 0.0, 1.0)), fwd)
			await get_tree().physics_frame
		await _wait(0.3)
		_stand.queue_free()
		trail.queue_free()
		if sw:
			sw.visible = true
		await _wait(0.2)

	## Slams: a chop biting the stone in front of the hero, a little to his right (power 1: kick down, shake,
	## hit-stop); then on sand and on grass (the surface forced: the arena is all stone) beside him, where his body
	## does not hide them; then a dash's landing at his feet (0.6).
	func _beat_slam() -> void:
		await _place(post.global_position + Vector3(-1.6, 0, 2.8), post.global_position + Vector3(-1.6, 0, 0))
		var fwd := hero.forward()
		var right := fwd.cross(Vector3.UP).normalized()
		_mark("slam")
		_slam(hero.global_position + fwd * 1.3 + right * 0.35, 1.0, "")
		Game.hitstop(0.06)
		await _wait(1.2)
		_mark("slam_sand")
		_slam(hero.global_position + fwd * 0.9 + right * 1.6, 1.0, "sand")
		await _wait(1.2)
		_mark("slam_grass")
		_slam(hero.global_position + fwd * 0.9 - right * 1.6, 1.0, "grass")
		await _wait(1.2)
		_mark("slam_dash")
		_slam(hero.global_position + fwd * 0.3, 0.6, "")
		await _wait(1.2)

	## The world's own ground (the island): a chop's slam in front of the hero (a little to his right), one beside him,
	## a landing at his feet; the dust and the chunks take the ground's kind.
	func _beat_slam_world() -> void:
		var fwd := hero.forward()
		var right := fwd.cross(Vector3.UP).normalized()
		_mark("slamw")
		_slam(hero.global_position + fwd * 1.3 + right * 0.35, 1.0, "")
		Game.hitstop(0.06)
		await _wait(1.0)
		_mark("slamw_side")
		_slam(hero.global_position + fwd * 0.9 + right * 1.6, 1.0, "")
		await _wait(1.0)
		_mark("slamw_dash")
		_slam(hero.global_position + fwd * 0.3, 0.6, "")
		await _wait(1.0)

	## Prints the world's ground kind on a grid round the pier's beach and the wolves' clearing (choosing spots).
	func _probe() -> void:
		var w = arena.get("world")
		if w == null or not w.has_method("surface_at"):
			return
		for zone in [[Vector2(-8.0, 88.0), Vector2(36.0, 112.0)], [Vector2(-36.0, 2.0), Vector2(-12.0, 26.0)]]:
			var lo: Vector2 = zone[0]
			var hi: Vector2 = zone[1]
			var z := lo.y
			while z <= hi.y:
				var row := ""
				var x := lo.x
				while x <= hi.x:
					var g: Vector3 = w.call("ground", Vector3(x, 0, z))
					row += String(w.call("surface_at", g + Vector3(0, 0.05, 0))).substr(0, 2) + " "
					x += 4.0
				print("FXDEMO probe z=%5.1f x=%5.1f.. %s" % [z, lo.x, row])
				z += 3.0

	## To the sand by the pier (the island), facing inland.
	func _beat_beach() -> void:
		var w = arena.get("world")
		var p := Vector3(2.0, 0.0, 109.0)
		if w != null and w.has_method("ground"):
			p = w.call("ground", p)
		await _place(p, p + Vector3(0, 0, -5))
		_mark("beach surf=%s" % (String(w.call("surface_at", p + Vector3(0, 0.05, 0))) if w != null and w.has_method("surface_at") else "?"))
		await _wait(0.3)

	func _slam(p: Vector3, power: float, surf: String) -> void:
		Game.fx.slam(p, power, surf)
		Sfx.play("slam", p, -1.0 if power >= 1.0 else -5.0)
		Game.shake(0.3 * power)
		Game.kick(Vector3.DOWN, power)

	## The straw post the blows are aimed at: the arena's middle post, or (the island, dummies=1) the training dummy
	## nearest to the hero.
	func _find_post() -> Node3D:
		var ds = arena.get("dummies")
		if ds is Array and (ds as Array).size() > 1:
			return (ds as Array)[1]
		var best: Node3D = null
		for c in arena.get_children():
			if c is TrainingDummy and (best == null or c.global_position.distance_to(hero.global_position) < best.global_position.distance_to(hero.global_position)):
				best = c
		return best

	# --- the contact's calls (what the move tables will ask for) -----------------------------------------------

	func _on_blow(_foe: Node, h: Dictionary) -> void:
		var point: Vector3 = h.get("point", hero.global_position + hero.forward() * 1.2 + Vector3(0, 1.0, 0))
		var cut := _cut if _cut.length() > 0.01 else hero.forward()
		var nm := String(h.get("attack", ""))
		_mark("hit_" + nm)
		match nm:
			"attack1", "attack2":
				Game.fx.slash_mark(point, cut, 1.0)
				Game.kick(cut, 0.6)
			"attack3":
				Game.fx.slash_mark(point, cut, 1.5, Color(1.0, 0.8, 0.42))
				Game.kick(cut.normalized() + Vector3.DOWN * 0.4, 1.0)
				Game.fov_punch(2.5, 0.25)
			"heavy":
				Game.fx.slash_mark(point, cut, 1.8, Color(1.0, 0.72, 0.28))
				Game.kick(cut, 1.2)
				Game.fov_punch(3.0, 0.3)


## A sword on its own (the thrust's stand-in): the hero's sword meshes, blade along -Z of its own transform, with
## blade_segment() like the rig's (root and tip, world) for a BladeTrail.
class StandIn extends Node3D:
	var _seg := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])

	func _ready() -> void:
		var ms: Array = RigHeracles.sword_meshes()
		for m in ms:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = Materials.lowpoly()
			add_child(mi)

	## The grip at `grip`, the blade pointing along `dir`.
	func pose(grip: Vector3, dir: Vector3) -> void:
		var z := -dir.normalized()
		var x := Vector3.UP.cross(z).normalized()
		global_transform = Transform3D(Basis(x, z.cross(x), z), grip)

	func blade_segment() -> PackedVector3Array:
		_seg[0] = global_transform * Vector3(0, 0, -0.1)
		_seg[1] = global_transform * Vector3(0, 0, RigHeracles.SWORD_TIP + 0.005)
		return _seg
