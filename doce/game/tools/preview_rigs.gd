extends Object
## Static helpers so tools/preview.tscn can show character rigs, e.g.
##   godot --path . res://tools/preview.tscn -- script=res://tools/preview_rigs.gd fns=hero,hero_run,dummy cam=low
## The hero is rig_heracles.gd when the HERO stream has delivered it, else the stand-in. Add the beasts here as the
## BESTIARY stream delivers them (wolf, boar, lion).

static func _hero_rig() -> Rig:
	var path := "res://scripts/gfx/rig_heracles.gd"
	if ResourceLoader.exists(path):
		return (load(path) as Script).new()
	return RigHeroStandIn.new()


static func hero(_seed: int) -> Node3D:
	return _hero_rig()


static func hero_run(_seed: int) -> Node3D:
	var r := _hero_rig()
	r.set_locomotion(6.2, 6.2)
	return r


## pose=<action>:<seconds> on the preview command line poses any of these; hero_pose cycles a few actions by seed.
static func hero_pose(seed_value: int) -> Node3D:
	var r := _hero_rig()
	var acts := ["attack1", "attack3", "heavy", "parry", "dodge", "throw"]
	var a: String = acts[(seed_value / 7) % acts.size()]
	r.ready.connect(func():
		r.play(a)
		r.action_t = r.action_len * 0.5
		r.process_mode = Node.PROCESS_MODE_DISABLED
		r._animate(0.1))
	return r


static func dummy(_seed: int) -> Node3D:
	return TrainingDummy.DummyRig.new()
