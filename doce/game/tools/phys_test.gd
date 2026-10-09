extends Node
## Physics self-test (debug arg phystest=1, added by main.gd; also works on the web with ?dev=1&play=1&phystest=1):
##  1. casts rays straight down onto the terrain body at 400 random points and compares the hit height with
##     World.height_at() (the HeightMapShape3D must use exactly the triangles of the mesh);
##  2. lets the hero settle, auto-walks it forward (camera-relative) for 2 s, then checks that it stands on the
##     floor, has not sunk into the ground and has actually moved.
## Prints one line: "DOCE phystest engine=<setting> ray_max_err=<m> on_floor=<bool> y=<m> ground=<m> moved=<m>
## state=<motion state> physics_ms=<mean physics process time per frame while walking> result=<PASS|FAIL>".

var _t := 0.0
var _phase := 0
var _start := Vector3.ZERO
var _ray_err := -1.0
var _phys_ms := 0.0
var _phys_n := 0


func _physics_process(delta: float) -> void:
	var hero: Node3D = Game.hero
	var world = Game.world
	if hero == null or world == null or not Game.is_playing():
		return
	_t += delta
	match _phase:
		0:
			if _t > 0.5:
				_ray_err = _ray_check(world)
				_start = hero.global_position
				hero.set("debug_move", Vector2(0.0, -1.0))
				_phase = 1
				_t = 0.0
		1:
			_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			_phys_n += 1
			if _t > 2.0:
				hero.set("debug_move", Vector2.ZERO)
				_phase = 2
				_t = 0.0
		2:
			if _t > 0.5:
				_report(hero, world)
				_phase = 3


func _ray_check(world) -> float:
	var space := (Game.main as Node3D).get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var worst := 0.0
	var body: Object = world.get("terrain_body")
	var b: Rect2 = world.bounds()
	var n := 0
	for i in 400:
		var x := rng.randf_range(b.position.x + 4.0, b.end.x - 4.0)
		var z := rng.randf_range(b.position.y + 4.0, b.end.y - 4.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -60.0, z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (body != null and hit["collider"] != body):
			continue
		var e := absf(float(hit["position"].y) - float(world.height_at(x, z)))
		worst = maxf(worst, e)
		n += 1
	return worst if n > 0 else -1.0


func _report(hero: Node3D, world) -> void:
	var p := hero.global_position
	var g: float = world.height_at(p.x, p.z)
	var on_floor: bool = (hero as CharacterBody3D).is_on_floor()
	var moved := Vector2(p.x - _start.x, p.z - _start.z).length()
	var swim: bool = hero.get("motion_state") == &"swim"
	var ok := _ray_err >= 0.0 and _ray_err < 0.05 and (on_floor or swim) and p.y > g - 0.06 and moved > 5.0
	print("DOCE phystest engine=%s ray_max_err=%.3f on_floor=%s y=%.2f ground=%.2f moved=%.1f state=%s physics_ms=%.2f result=%s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine"), _ray_err, on_floor, p.y, g, moved, hero.get("motion_state"),
		_phys_ms / maxf(1.0, float(_phys_n)), "PASS" if ok else "FAIL"])
