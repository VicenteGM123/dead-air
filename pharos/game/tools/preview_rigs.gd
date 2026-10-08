extends Object
## Static helpers so tools/preview.tscn can show character rigs.

static func hero(_seed: int) -> Node3D:
	return RigHero.new()


static func soldier(_seed: int) -> Node3D:
	return RigHoplite.new(true)


static func shade(_seed: int) -> Node3D:
	return RigShade.new()


static func shade_attack(_seed: int) -> Node3D:
	var r := RigShade.new()
	r.ready.connect(func(): r.play("attack"); r.action_t = 0.62)
	return r


static func hero_run(_seed: int) -> Node3D:
	var r := RigHero.new()
	r.set_locomotion(6.0, 6.2)
	return r


static func night_scene(_seed: int) -> Node3D:
	var root := Node3D.new()
	var h := RigHero.new()
	root.add_child(h)
	h.rotation.y = PI * 0.85
	for i in 3:
		var s := RigShade.new()
		root.add_child(s)
		s.position = Vector3(-1.2 + i * 1.6, 0, -3.2 - (i % 2) * 0.8)
		s.rotation.y = PI * 0.0 + (i - 1) * 0.3
	return root


static func hero_back_run(_seed: int) -> Node3D:
	var r := RigHero.new()
	r.set_locomotion(5.5, 6.2)
	return r


static func hero_pose(seed_value: int) -> Node3D:
	var r := RigHero.new()
	var acts := ["attack1", "attack3", "bash", "cast", "rest"]
	var a: String = acts[(seed_value / 7) % acts.size()]
	r.ready.connect(func(): r.play(a); r.action_t = r.action_len * 0.5; r.process_mode = Node.PROCESS_MODE_DISABLED; r._animate(0.1))
	return r
