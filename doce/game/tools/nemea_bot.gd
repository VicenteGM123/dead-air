extends Node
## CORE's integration bot on the island of Nemea (the real World): `godot --path . -- play=1 corebot=1` (all tests)
## or `corebot=passage,boulder` (some). It plays the hero through the real input path (HeroInput.bot, debug_move,
## the camera aims the chain spear) and prints one line per test:
##   NEMEA test <name> PASS|FAIL <details>
##   NEMEA autotest passed=N/M result=PASS|FAIL
## Tests:
##   start     the hero stands on the pier at player_start(), on the floor, the camera behind him
##   passage   the broken passage: south rim -> the ring on the sea stack (lands at the foot of its stone) -> the
##             ring on the north rim (lands on the rim)
##   boulder   cave mouth B: the hero bites the boulder (out on the apron in front of the crack) from in front of the
##             crack, holds the chain and backs into the crack; the boulder rolls up to the face and seals it
##             (is_blocking(cave().seal_b, 1.2) and is_blocking(entrance_b, 2.5)) and nobody fits past it any more
##   cave      walk in through mouth A to the arena and round two pillars (camera watch)
##   swim      off the end of the pier: the hero swims, the camera stays over the water
##   walk      (not in the default list: corebot=walk) the slice's way on foot, every step checked: the pier ->
##             the village (pets a cat: the cat purrs, the hero rig plays "pet") -> the forest road -> the broken
##             passage by the two bronze rings -> the thumb and the ridge meadow -> the Altar de la Sierra (hurt
##             first: praying heals him and makes it the checkpoint; then he falls and comes back there) -> cave
##             mouth B -> the boulder hauled into the crack. `walkfast=1` (renders) teleports to 20 m before each
##             step instead of walking the long legs. Marks "NEMEA mark w_<step>" for movie frames.
## Throughout, a camera watch: the hero's head always in sight from the camera (a ray on the world layer), never
## within 1.2 m of the hero's head for 0.35 s, never under the sea ("NEMEA test camera", counted last). "NEMEA mark <tag> frame=<n>" for movie renders.

const ALL := ["start", "passage", "boulder", "cave", "swim"]

var main: Node = null
var hero: Hero
var cam: CameraRig
var world
var _time := 0.0
var _passed := 0
var _total := 0
var _cur := ""
var _cam_min := INF
var _cam_min_at := ""
var _cam_close := 0.0
var _cam_close_max := 0.0
var _cam_close_at := ""
var _cam_inside := 0
var _cam_inside_at := ""
var _cam_wet := 0
var _rq := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta


func _process(delta: float) -> void:
	if hero == null or cam == null or cam.cam == null or cam.mode != "follow":
		return
	var c := cam.cam.global_position
	var d := c.distance_to(hero.visual_position() + Vector3(0, 1.45, 0))
	if d < _cam_min:
		_cam_min = d
		_cam_min_at = _cur
	if d < 1.2:
		_cam_close += Game.real_delta(delta)
		if _cam_close > _cam_close_max:
			_cam_close_max = _cam_close
			_cam_close_at = _cur
	else:
		_cam_close = 0.0
	# the view must see the hero: nothing of the world between his head and the camera (a point query cannot tell
	# "inside" for the island's trimeshes: the terrain and the cave are open surfaces)
	var head := hero.visual_position() + Vector3(0, 1.45, 0)
	_rq.from = head
	_rq.to = c
	_rq.collision_mask = 1
	_rq.exclude = [hero.get_rid()]
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(_rq)
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(c) > 0.05:
		_cam_inside += 1
		if _cam_inside_at == "":
			_cam_inside_at = "%s@t=%.2f cam=%s head=%s hit=%s" % [_cur, _time, str(c), str(head), str(hit["position"])]
	if world != null and float(world.call("water_depth", c.x, c.z)) > 0.0 and c.y < float(world.sea_level) + 0.1:
		_cam_wet += 1


func _run() -> void:
	for i in 20:
		await get_tree().physics_frame
	hero = main.get("hero")
	cam = main.get("cam")
	world = main.get("world")
	var list: Array = ALL
	var a := String(Game.arg("corebot", "1"))
	if a != "1" and a != "all":
		list = Array(a.split(",", false))
	for t in list:
		_cur = String(t)
		var ok: bool = await _run_test(String(t))
		_total += 1
		if ok:
			_passed += 1
		hero.inp.bot_clear()
		hero.debug_move = Vector2.ZERO
		await _wait(0.4)
	var cam_ok := _cam_inside == 0 and _cam_close_max < 0.35 and _cam_wet == 0
	_total += 1
	if cam_ok:
		_passed += 1
	_result("camera", cam_ok, "min_to_head=%.2f (%s) close_max=%.2fs (%s) inside_frames=%d first_inside=%s under_water_frames=%d" % [
		_cam_min, _cam_min_at, _cam_close_max, _cam_close_at, _cam_inside, _cam_inside_at, _cam_wet])
	print("NEMEA autotest passed=%d/%d result=%s" % [_passed, _total, "PASS" if _passed == _total else "FAIL"])
	if Game.arg_on("quit"):
		get_tree().quit()


func _run_test(t: String) -> bool:
	match t:
		"start":
			return await _t_start()
		"passage":
			return await _t_passage()
		"boulder":
			return await _t_boulder()
		"cave":
			return await _t_cave()
		"boulder_search":
			return await _t_boulder_search()
		"swim":
			return await _t_swim()
		"walk":
			return await _t_walk()
	print("NEMEA test %s FAIL unknown test" % t)
	return false


# --- helpers ---------------------------------------------------------------------------------------------------

func _result(nm: String, ok: bool, details: String) -> bool:
	print("NEMEA test %s %s %s" % [nm, "PASS" if ok else "FAIL", details])
	return ok


func _mark(tag: String) -> void:
	print("NEMEA mark %s frame=%d t=%.2f" % [tag, Engine.get_frames_drawn(), _time])


func _wait(s: float) -> void:
	var t0 := _time
	while _time - t0 < s:
		await get_tree().physics_frame


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := _time
	while _time - t0 < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _tap(action: StringName, hold: float = 0.05) -> void:
	hero.inp.bot[action] = true
	await _wait(hold)
	hero.inp.bot[action] = false
	await get_tree().physics_frame


## Places the hero on the ground at `p` facing `look`, the camera behind him, at rest.
func _place(p: Vector3, look: Vector3) -> void:
	var g: Vector3 = world.call("ground", p)
	var d := Combat.flat(look - g).normalized()
	var z := -d
	var x := Vector3.UP.cross(z).normalized()
	hero.revive(Transform3D(Basis(x, Vector3.UP, z), g + Vector3(0, 0.05, 0)))
	hero.invulnerable = 0.0
	cam.lock_on(null)
	cam.follow(hero, true)
	await _wait(0.5)


func _stick_to(p: Vector3) -> Vector2:
	var d := Combat.flat(p - hero.global_position)
	if d.length() < 0.01:
		return Vector2.ZERO
	var local := cam.yaw_basis().inverse() * d.normalized()
	return Vector2(local.x, local.z).normalized()


func _walk_to(p: Vector3, tol: float, timeout: float) -> bool:
	var t0 := _time
	while _time - t0 < timeout:
		if Combat.flat(p - hero.global_position).length() <= tol:
			hero.debug_move = Vector2.ZERO
			return true
		hero.debug_move = _stick_to(p)
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	return false


## Aims the camera at an anchor and throws when it is the candidate; true when the spear bit it.
func _throw_at(anchor: Node3D, settle: float = 0.35) -> bool:
	cam.aim_at(anchor.call("chain_point"))
	await _wait(settle)
	if hero.chain_candidate != anchor:
		return false
	await _tap(&"chain")
	return await _until(func() -> bool: return hero.spear.mode == ChainSpear.STUCK and hero.spear.target == anchor, 1.5)


## Why `anchor` is not the chain candidate (printed when a test cannot aim at it).
func _why_not(anchor: Node3D) -> String:
	var origin := hero.global_position + Vector3(0, 1.5, 0)
	var p: Vector3 = anchor.call("chain_point")
	var cf := -cam.cam.global_transform.basis.z
	var ang := rad_to_deg(cf.angle_to(p - cam.cam.global_position))
	var q := PhysicsRayQueryParameters3D.create(origin, p, 1 | 8, [hero.get_rid()])
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(q)
	var los := "clear" if hit.is_empty() else "blocked by %s at %s (%.2f m before)" % [str(hit["collider"]), str(hit["position"]), (hit["position"] as Vector3).distance_to(p)]
	return "dist=%.1f angle=%.1f los=%s cand=%s" % [origin.distance_to(p), ang, los, str(hero.chain_candidate)]


# --- tests -----------------------------------------------------------------------------------------------------

func _t_start() -> bool:
	var xf: Transform3D = world.call("player_start")
	hero.teleport(xf)
	cam.follow(hero, true)
	_mark("start")
	await _wait(1.0)
	var on_floor := hero.is_on_floor()
	var dy := absf(hero.global_position.y - xf.origin.y)
	var behind := Combat.flat(cam.cam.global_position - hero.global_position).normalized().dot(-hero.forward()) > 0.8
	var ok := on_floor and dy < 0.3 and behind
	return _result("start", ok, "on_floor=%s dy=%.2f cam_behind=%s at=%s" % [str(on_floor), dy, str(behind), str(hero.global_position)])


func _t_passage() -> bool:
	var rings: Array = world.call("anchors")
	if rings.size() < 3:
		return _result("passage", false, "rings=%d" % rings.size())
	var stack: Node3D = rings[1]
	var north: Node3D = rings[2]
	var places: Dictionary = world.call("places")
	var south_p: Vector3 = places["passage_south"]
	await _place(south_p, stack.call("chain_point"))
	_mark("passage")
	var bit_a: bool = await _throw_at(stack)
	var on_stack: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.y > 17.0, 5.0)
	var hung_a := hero.state == Hero.St.HANG
	await _wait(0.5)
	var at_a := hero.global_position
	# from the foot of the stack's stone: round to where the north ring is in sight, then throw
	var cand := false
	for k in 8:
		cam.aim_at(north.call("chain_point"))
		await _wait(0.3)
		if hero.chain_candidate == north:
			cand = true
			break
		var a := TAU * float(k) / 8.0
		var stone := Combat.flat(stack.global_position) + Vector3(0, hero.global_position.y, 0)
		await _walk_to(stone + Vector3(sin(a), 0, cos(a)) * 1.6 + Combat.flat(north.global_position - stack.global_position).normalized() * 0.8, 0.3, 1.5)
	_mark("passage2")
	var bit_b := false
	if cand:
		bit_b = await _throw_at(north, 0.1)
	var on_north: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.z < -24.0, 5.0)
	await _wait(0.4)
	var p := hero.global_position
	var ok: bool = bit_a and on_stack and cand and bit_b and on_north
	return _result("passage", ok, "bit_stack=%s landed_on_stack=%s (hang=%s at %s) north_candidate=%s bit_north=%s on_north_rim=%s at=(%.1f, %.1f, %.1f)" % [
		str(bit_a), str(on_stack), str(hung_a), str(at_a), str(cand), str(bit_b), str(on_north), p.x, p.y, p.z])


func _t_boulder() -> bool:
	var cave: Dictionary = world.call("cave")
	var boulder: Node3D = cave["boulder"]
	var mp: Vector3 = cave["entrance_b"]
	var out: Vector3 = Combat.flat(cave["dir_b"]).normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	var seal: Vector3 = cave.get("seal_b", mp + out * 1.5)
	if boulder == null or not boulder.has_method("is_blocking"):
		return _result("boulder", false, "no boulder")
	# The boulder waits out on the apron in front of the crack. From the apron between it and the crack (the first
	# spot, walking out from the crack, with a clear line to it), facing it: bite, hold the chain and back into the
	# crack; the boulder rolls up to the face over the opening and seals it.
	var bp := boulder.global_position
	await _place(_throw_spot(boulder, mp, out), bp)
	cam.aim_at(boulder.call("chain_point"))
	await _wait(0.4)
	var cand := hero.chain_candidate == boulder
	if not cand:
		print("NEMEA boulder not aimed: " + _why_not(boulder))
	_mark("boulder")
	hero.inp.bot[&"chain"] = true
	var hauling: bool = await _until(func() -> bool: return hero.chain_mode == &"haul", 1.5)
	var goal := mp - out * 3.2
	var t0 := _time
	var sealed := false
	while _time - t0 < 20.0:
		var far := Combat.flat(goal - hero.global_position).length()
		hero.debug_move = _stick_to(goal) if far > 0.4 else Vector2.ZERO
		if Game.arg_on("botdebug") and Engine.get_physics_frames() % 30 == 0:
			var hr := hero.global_position - mp
			var br := boulder.global_position - mp
			print("NEMEA haul t=%.1f hero(out %.1f, side %.1f) boulder(out %.1f, side %.1f) mode=%s state=%s speed=%.2f" % [_time - t0,
				hr.dot(out), hr.dot(side), br.dot(out), br.dot(side), hero.chain_mode, hero.state_name(), float(boulder.call("speed"))])
		if boulder.call("is_blocking", seal, 1.2) and float(boulder.call("speed")) < 0.15 and _time - t0 > 1.0:
			sealed = true
			break
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	await _wait(0.6)
	hero.inp.bot[&"chain"] = false
	await _wait(0.8)
	var bo := Combat.flat(boulder.global_position - mp)
	var still: bool = boulder.call("is_blocking", mp, 2.5) and boulder.call("is_blocking", seal, 1.2)
	# the crack is shut: a hero outside cannot walk in past it any more
	var shut := not _walkable_past(boulder, mp, out)
	var ok: bool = cand and hauling and sealed and still and shut
	return _result("boulder", ok, "candidate=%s hauling=%s sealed=%s still=%s shut=%s boulder (out %.2f, side %.2f) from the mouth, %.2f m from seal_b, hero at (out %.1f, side %.1f)" % [
		str(cand), str(hauling), str(sealed), str(still), str(shut), bo.dot(out), bo.dot(side), Combat.flat(boulder.global_position - seal).length(),
		(hero.global_position - mp).dot(out), (hero.global_position - mp).dot(side)])


## True when a capsule like the hero's fits through between the boulder and the opening (a few lateral offsets
## from just outside the boulder into the crack).
func _walkable_past(boulder: Node3D, mp: Vector3, out: Vector3) -> bool:
	var side := Vector3(-out.z, 0.0, out.x)
	var space := hero.get_world_3d().direct_space_state
	var sh := CapsuleShape3D.new()
	sh.radius = 0.36
	sh.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1 | 8
	q.exclude = [hero.get_rid()]
	var bo := Combat.flat(boulder.global_position - mp).dot(out)
	for lat in [-1.6, -0.8, 0.0, 0.8, 1.6]:
		var from: Vector3 = mp + out * (bo + 2.2) + side * float(lat) + Vector3(0, 1.0, 0)
		from.y = float(world.call("height_at", from.x, from.z)) + 1.0
		var to: Vector3 = mp - out * 1.5 + Vector3(0, 1.0, 0)
		q.transform = Transform3D(Basis.IDENTITY, from)
		q.motion = to - from
		var r := space.cast_motion(q)
		if r[0] >= 0.999:
			return true
	return false


## A spot on the apron of mouth B with a clear line to the boulder (walking from the crack out towards it).
func _throw_spot(boulder: Node3D, mp: Vector3, out: Vector3) -> Vector3:
	var bp := boulder.global_position
	var space := hero.get_world_3d().direct_space_state
	for k in 12:
		var cand_p: Vector3 = world.call("ground", mp + out * 0.6 + Combat.flat(bp - mp) * (0.05 + 0.04 * float(k)))
		var q := PhysicsRayQueryParameters3D.create(cand_p + Vector3(0, 1.5, 0), boulder.call("chain_point"), 1, [hero.get_rid()])
		if space.intersect_ray(q).is_empty():
			return cand_p
	return mp + out * 2.2


## Exploration (corebot=boulder_search): from which spot does a steady pull bring the boulder into mouth B?
## Tries pull spots round the apron (out 0.5..4, side -4..4), 7 s each, and prints where the boulder ends.
func _t_boulder_search() -> bool:
	var cave: Dictionary = world.call("cave")
	var boulder: Node3D = cave["boulder"]
	var mp: Vector3 = cave["entrance_b"]
	var out: Vector3 = Combat.flat(cave["dir_b"]).normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	var home := boulder.global_position
	var best := INF
	for so in [-4.0, -2.5, -1.0, 0.0, 1.0]:
		for oo in [-1.5, 0.5, 2.0, 3.5]:
			boulder.global_position = home
			(boulder as CharacterBody3D).velocity = Vector3.ZERO
			var spot: Vector3 = world.call("ground", mp + out * oo + side * so)
			# throw from where the line is clear (near the spot)
			await _place(_throw_spot(boulder, mp, out), home)
			cam.aim_at(boulder.call("chain_point"))
			await _wait(0.4)
			if hero.chain_candidate != boulder:
				print("NEMEA search spot(out %.1f, side %.1f): no aim" % [oo, so])
				continue
			hero.inp.bot[&"chain"] = true
			await _until(func() -> bool: return hero.chain_mode == &"haul", 1.5)
			var t0 := _time
			while _time - t0 < 7.0 and hero.chain_mode == &"haul":
				hero.debug_move = _stick_to(spot) if Combat.flat(spot - hero.global_position).length() > 0.4 else Vector2.ZERO
				await get_tree().physics_frame
			hero.debug_move = Vector2.ZERO
			hero.inp.bot[&"chain"] = false
			await _wait(0.3)
			var bo := Combat.flat(boulder.global_position - mp)
			var hr := Combat.flat(hero.global_position - mp)
			best = minf(best, bo.length())
			print("NEMEA search spot(out %.1f, side %.1f) hero_reached(out %.1f, side %.1f) boulder(out %.2f, side %.2f) dist=%.2f" % [oo, so, hr.dot(out), hr.dot(side), bo.dot(out), bo.dot(side), bo.length()])
	boulder.global_position = home
	return _result("boulder_search", best < 2.6, "best=%.2f" % best)


func _t_cave() -> bool:
	var cave: Dictionary = world.call("cave")
	var ma: Vector3 = cave["entrance_a"]
	var out: Vector3 = Combat.flat(cave["dir_a"]).normalized()
	var c: Vector3 = cave["arena_center"]
	await _place(ma + out * 4.0, ma)
	_mark("cave")
	var t_in: bool = await _walk_to(ma - out * 3.0, 0.8, 8.0)
	var t_arena: bool = await _walk_to(c, 1.5, 14.0)
	# round two pillars
	var pillars: Array = cave["pillars"]
	var rounded := 0
	for i in mini(2, pillars.size()):
		var pp: Vector3 = pillars[i]
		var side := Combat.flat(pp - c).normalized().cross(Vector3.UP)
		for k in 3:
			var a := float(k) / 3.0 * PI
			var goal := pp + (Combat.flat(c - pp).normalized() * cos(a) + side * sin(a)) * 2.6
			if await _walk_to(goal, 0.7, 4.0):
				rounded += 1
	var ok := t_in and t_arena and rounded >= 4
	return _result("cave", ok, "in=%s arena=%s pillar_legs=%d/6 at=%s" % [str(t_in), str(t_arena), rounded, str(hero.global_position)])


func _t_swim() -> bool:
	var dock: Vector3 = world.call("boat_dock")
	var xf: Transform3D = world.call("player_start")
	var f := -xf.basis.z
	# off the end of the pier, away from the island (the pier runs out to sea against the start's facing)
	var sea_dir := -f
	var p := dock + sea_dir * 4.0
	for k in 20:
		if float(world.call("water_depth", p.x, p.z)) > 2.5:
			break
		p += sea_dir * 1.5
	hero.teleport(Transform3D(Basis(Vector3.UP, atan2(-sea_dir.x, -sea_dir.z)), Vector3(p.x, float(world.sea_level) + 0.5, p.z)))
	cam.follow(hero, true)
	_mark("swim")
	var swimming: bool = await _until(func() -> bool: return hero.motion_state == &"swim", 3.0)
	# swim back towards the shore for a few seconds
	hero.debug_move = Vector2(0.0, 1.0)
	await _wait(2.5)
	hero.debug_move = Vector2.ZERO
	var still := hero.motion_state == &"swim"
	var ok: bool = swimming and still
	return _result("swim", ok, "swimming=%s still_swimming=%s at=%s depth=%.1f" % [str(swimming), str(still), str(hero.global_position),
		float(world.call("water_depth", hero.global_position.x, hero.global_position.z))])


# --- the walk (corebot=walk) -------------------------------------------------------------------------------------

const NL := preload("res://scripts/world/nemea_layout.gd")
var _walk_ok := {}


func _wstep(nm: String, ok: bool, details: String) -> void:
	_walk_ok[nm] = ok
	print("NEMEA walk %s %s %s" % [nm, "PASS" if ok else "FAIL", details])


## The waypoints of layout path `i` (from index a to b, inclusive; b < 0: to the end).
func _path_pts(i: int, a: int = 0, b: int = -1) -> Array[Vector2]:
	var pts: Array = NL.PATHS[i][0]
	var out: Array[Vector2] = []
	for k in range(a, (pts.size() - 1 if b < 0 else b) + 1):
		out.append(pts[k])
	return out


## Drives the hero along XZ waypoints (a waypoint counts once close, or once passed along the route). With
## `walkfast=1` it first teleports to `fast_m` metres (along the route) before its end. Returns true when the last
## waypoint is reached; stuck (barely moving) for 4 s fails.
func _follow(pts: Array[Vector2], timeout: float, fast_m: float = 20.0) -> bool:
	if pts.is_empty():
		return true
	if Game.arg_on("walkfast"):
		# skip to fast_m before the end (along the polyline)
		var left := fast_m
		var k := pts.size() - 1
		var at := pts[k]
		while k > 0:
			var seg := pts[k - 1].distance_to(pts[k])
			if seg >= left:
				at = pts[k].lerp(pts[k - 1], left / seg)
				break
			left -= seg
			k -= 1
			at = pts[k]
		var nxt := pts[mini(k, pts.size() - 1)]
		var d := Vector3(nxt.x - at.x, 0, nxt.y - at.y)
		var g: Vector3 = world.call("ground", Vector3(at.x, 0, at.y))
		var bas := Basis(Vector3.UP, atan2(-d.x, -d.z)) if d.length() > 0.1 else hero.global_transform.basis
		hero.teleport(Transform3D(bas, g + Vector3(0, 0.05, 0)))
		cam.follow(hero, true)
		var rest: Array[Vector2] = []
		for j in range(k, pts.size()):
			rest.append(pts[j])
		pts = rest
		await _wait(0.3)
	var i := 0
	var t0 := _time
	var still := 0.0
	var side_t := 0.0
	var side_sgn := 1.0
	var unsticks := 0
	var last := hero.global_position
	while i < pts.size():
		if _time - t0 > timeout:
			hero.debug_move = Vector2.ZERO
			print("NEMEA walk timeout at %s heading to %s" % [str(hero.global_position.snapped(Vector3.ONE * 0.1)), str(pts[i])])
			return false
		var p := hero.global_position
		var tgt := Vector3(pts[i].x, p.y, pts[i].y)
		var to := Combat.flat(tgt - p)
		var passed := false
		if i + 1 < pts.size():
			var seg := Vector3(pts[i + 1].x - pts[i].x, 0, pts[i + 1].y - pts[i].y)
			passed = to.length() < 4.0 and Combat.flat(p - tgt).dot(seg) > 0.0
		if to.length() < (1.4 if i < pts.size() - 1 else 1.0) or passed:
			i += 1
			continue
		if side_t > 0.0:
			# unsticking: a step to the side of the way (round a stone or a trunk), then on again
			var dirv := to.normalized()
			hero.debug_move = _stick_to(p + dirv.cross(Vector3.UP) * side_sgn * 2.0 + dirv * 0.3)
			side_t -= get_physics_process_delta_time()
		else:
			hero.debug_move = _stick_to(tgt)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		var moved := Combat.flat(hero.global_position - last).length()
		last = hero.global_position
		still = still + dt if moved < 0.5 * dt else 0.0
		if still > 0.8 and side_t <= 0.0 and unsticks < 6:
			unsticks += 1
			side_t = 0.6
			side_sgn = -side_sgn
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + to.normalized() * 1.2, 1 | 8, [hero.get_rid()])
			var hit := hero.get_world_3d().direct_space_state.intersect_ray(q)
			print("NEMEA walk blocked at %s towards %s by %s: a step to the side" % [str(p.snapped(Vector3.ONE * 0.1)), str(pts[i]), str(hit.get("collider", "nothing at chest height"))])
		if still > 4.0:
			print("NEMEA walk stuck at %s heading to %s: state=%s spear=%s chain_mode=%s move=%s vel=%s floor=%s motion=%s input=%s" % [str(hero.global_position.snapped(Vector3.ONE * 0.1)), str(pts[i]),
				hero.state_name(), str(hero.spear.mode), str(hero.chain_mode), str(hero.debug_move), str(hero.velocity.snapped(Vector3.ONE * 0.01)), str(hero.is_on_floor()), str(hero.motion_state), str(hero.input_enabled)])
			hero.debug_move = Vector2.ZERO
			return false
	hero.debug_move = Vector2.ZERO
	return true


func _t_walk() -> bool:
	_walk_ok.clear()
	var xf: Transform3D = world.call("player_start")
	hero.teleport(xf)
	cam.follow(hero, true)
	await _wait(0.8)
	# 1. the pier: down the pier to the beach, up the main road into the village
	_mark("w_pier")
	var leg: Array[Vector2] = [Vector2(14, 120), Vector2(14, 108)]
	leg.append_array(_path_pts(0, 0, 4))
	var ok := await _follow(leg, 40.0, 30.0)
	_mark("w_village")
	_wstep("village", ok, "at %s" % str(hero.global_position.snapped(Vector3.ONE * 0.1)))
	# 2. a cat near the plaza: walk up, hold interact
	var amb = world.get("ambient")
	var cat = null
	var best := INF
	if amb != null:
		for c in amb.get("cats"):
			var dc: float = Combat.flat((c.get("pos") as Vector3) - hero.global_position).length()
			if dc < best:
				best = dc
				cat = c
	if cat == null:
		_wstep("cat", false, "no cats")
	else:
		var reached := false
		var t0 := _time
		while _time - t0 < 25.0:
			var cp: Vector3 = cat.get("pos")
			var to := Combat.flat(cp - hero.global_position)
			if to.length() < 1.05:
				reached = true
				break
			hero.debug_move = _stick_to(cp)
			await get_tree().physics_frame
		hero.debug_move = Vector2.ZERO
		await _wait(0.2)
		_mark("w_cat")
		var cat_rig = cat.get("rig")
		var target_is_cat: bool = hero.interact_target == cat_rig
		hero.inp.bot[&"interact"] = true
		var saw_pet := false
		var purred := false
		t0 = _time
		while _time - t0 < 2.2:
			await get_tree().physics_frame
			if String(hero.rig.get("action")) == "pet":
				saw_pet = true
			if int(cat.get("state")) == 6:
				purred = true
		hero.inp.bot[&"interact"] = false
		await _wait(0.6)
		_wstep("cat", reached and target_is_cat and saw_pet and purred, "reached=%s target_is_cat=%s hero_rig_pet=%s cat_petted=%s (%.1f m away at the start)" % [str(reached), str(target_is_cat), str(saw_pet), str(purred), best])
	# 3. the forest road to the broken passage's south rim
	leg = _path_pts(0, 4)
	_mark("w_road")
	ok = await _follow(leg, 90.0, 26.0)
	_wstep("forest_road", ok, "at %s" % str(hero.global_position.snapped(Vector3.ONE * 0.1)))
	# 4. the passage by the rings (the passage test's moves)
	var rings: Array = world.call("anchors")
	var stack: Node3D = rings[1]
	var north: Node3D = rings[2]
	var south_p: Vector3 = (world.call("places") as Dictionary)["passage_south"]
	await _walk_to(south_p, 0.4, 6.0)
	await _place(south_p, stack.call("chain_point"))
	_mark("w_passage")
	var bit_a: bool = await _throw_at(stack)
	var on_stack: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.y > 17.0, 5.0)
	await _wait(0.4)
	var cand := false
	for k in 8:
		cam.aim_at(north.call("chain_point"))
		await _wait(0.3)
		if hero.chain_candidate == north:
			cand = true
			break
		var a := TAU * float(k) / 8.0
		var stone := Combat.flat(stack.global_position) + Vector3(0, hero.global_position.y, 0)
		await _walk_to(stone + Vector3(sin(a), 0, cos(a)) * 1.6 + Combat.flat(north.global_position - stack.global_position).normalized() * 0.8, 0.3, 1.5)
	_mark("w_passage2")
	var bit_b := false
	if cand:
		bit_b = await _throw_at(north, 0.1)
	var on_north: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.z < -24.0, 5.0)
	await _wait(0.4)
	_wstep("passage", bit_a and on_stack and cand and bit_b and on_north, "bit_stack=%s on_stack=%s north_cand=%s bit_north=%s on_north_rim=%s" % [str(bit_a), str(on_stack), str(cand), str(bit_b), str(on_north)])
	# 5. the thumb and the ridge meadow to the Altar de la Sierra; hurt first, pray, then fall and come back
	leg = _path_pts(1)
	_mark("w_thumb")
	ok = await _follow(leg, 90.0, 18.0)
	var altar: Node3D = null
	for al in world.call("altars"):
		if String(al.get("title")) == "Altar de la Sierra":
			altar = al
	if altar == null:
		_wstep("altar", false, "no Altar de la Sierra")
	else:
		var front: Vector3 = altar.global_transform * Vector3(0, 0, 2.0)
		await _walk_to(front, 0.5, 8.0)
		var to_alt := Combat.flat(altar.global_position - hero.global_position)
		hero.facing = atan2(-to_alt.x, -to_alt.z)
		await _wait(0.4)
		hero.hp = 35.0
		var target_is_altar: bool = hero.interact_target == altar
		_mark("w_altar")
		await _tap(&"interact", 0.1)
		await _wait(1.2)
		var healed: bool = hero.hp >= hero.max_hp - 0.01
		var checkpoint: bool = Game.checkpoint == altar
		_wstep("altar", ok and target_is_altar and healed and checkpoint, "walked=%s target_is_altar=%s healed=%s (hp %.0f) checkpoint=%s" % [str(ok), str(target_is_altar), str(healed), hero.hp, str(checkpoint)])
		# a fall: a blow he cannot survive, a little way down the meadow
		await _walk_to(altar.global_position + Vector3(9.0, 0, 6.0), 0.6, 6.0)
		_mark("w_fall")
		hero.take_hit(Combat.make_hit(500.0, &"blunt", -hero.forward(), 3.0, 0.6, null))
		var died: bool = await _until(func() -> bool: return Game.phase == Game.Phase.DEAD, 2.0)
		var back: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY and hero.is_alive(), 8.0)
		await _wait(0.5)
		_mark("w_respawn")
		var rp: Transform3D = altar.call("respawn_transform")
		var dist_rp := Combat.flat(hero.global_position - rp.origin).length()
		_wstep("respawn", died and back and dist_rp < 1.5 and hero.hp >= hero.max_hp - 0.01, "died=%s back=%s %.2f m from the altar's respawn point, hp=%.0f" % [str(died), str(back), dist_rp, hero.hp])
	# 6. the meadow path to cave mouth B, then the boulder into the crack
	var cave: Dictionary = world.call("cave")
	var eb: Vector3 = cave["entrance_b"]
	var out: Vector3 = Combat.flat(cave["dir_b"]).normalized()
	leg = _path_pts(3)
	leg.append(Vector2(eb.x + out.x * 2.5, eb.z + out.z * 2.5))
	_mark("w_meadow")
	ok = await _follow(leg, 60.0, 22.0)
	await _wait(0.6)
	_mark("w_cave_b")
	_wstep("cave_mouth_b", ok, "at %s, %.1f m from entrance_b" % [str(hero.global_position.snapped(Vector3.ONE * 0.1)), Combat.flat(hero.global_position - eb).length()])
	var sealed: bool = await _t_boulder()
	_mark("w_sealed")
	_wstep("boulder", sealed, "(see the boulder test line)")
	var all_ok := true
	for k in _walk_ok:
		all_ok = all_ok and bool(_walk_ok[k])
	return _result("walk", all_ok, "steps=%s" % str(_walk_ok))
