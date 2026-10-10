extends "res://scripts/main.gd"
## World tour (integration tool for the island of Nemea, run in the real game: hero, camera, toon screen, UI off):
##
##  Walk check (headless is fine): a bot drives the hero (Hero.debug_move, camera-relative like the stick) from
##  the pier along the main road to the broken passage, crosses it the way the chain spear will (a teleport to
##  the north rim: the zip is CORE's), then along the thumb path to the ridge meadow, into cave mouth A, across
##  the arena and out through mouth B. Reports falls through the ground, stuck spots (and what blocks), skipped
##  waypoints and the route time.
##    godot --headless --path . res://tools/world_tour.tscn --quit-after 40000 -- walk=1
##
##  Route probe (headless): route=x,z;x,z;... drives the hero from the first point through the others without
##  skipping (a stuck hero stays stuck) and prints "ROUTE reached|blocked <where>": e.g. proof that a cliff
##  cannot be walked up.
##
##  Shots (needs a window): each named shot places the hero and the follow camera (or a fly camera), waits for
##  things to settle, saves <outdir>/<name>.png and prints the frame's draw calls / primitives / objects.
##    xvfb-run ... godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tools/world_tour.tscn \
##      --quit-after 20000 -- shots=pier,village,forest outdir=/abs/dir [settle=24]
##  Shot names: pier village forest passage altar cave_a cave_b arena swim overview (and cats goats paws).
##  breakdown=1 also hides one category at a time (grass, terrain, trees, rocks and shrubs, village, cave, sea,
##  characters) and prints what each costs in that view. quality=0|1|2 overrides Settings' quality for the run
##  (not saved; 1 is the web default) before the world is built.

const L := preload("res://scripts/world/nemea_layout.gd")

## name: [hero xz, hero facing (deg, 0 = north, 90 = west), camera yaw offset (deg), camera pitch (deg),
##        camera distance (m), fov]
const SHOTS := {
	"pier": [Vector2(14, 130), 0.0, 0.0, -12.0, 5.5, 60.0],
	"village": [Vector2(4, 84), 14.0, 0.0, -14.0, 6.5, 60.0],
	"forest": [Vector2(-16, 30), 34.0, 0.0, -12.0, 6.5, 60.0],
	"passage": [Vector2(-113, 2), 0.0, -14.0, -12.0, 6.5, 60.0],
	"altar": [Vector2(-6, -72), 166.0, 0.0, -14.0, 7.0, 60.0],
	"cave_a": [Vector2(-34, -82), -34.0, 0.0, -10.0, 7.0, 60.0],
	"cave_b": [Vector2(40, -83), 37.0, 0.0, -10.0, 7.0, 60.0],
	"arena": [Vector2(6, -108.5), 46.0, 0.0, -14.0, 5.5, 62.0],
	"swim": [Vector2(-40, 116), 69.0, 0.0, -10.0, 6.5, 60.0],
	"cats": [Vector2(5, 89), 34.0, 0.0, -18.0, 5.0, 60.0],
	"goats": [Vector2(20, 42), -43.0, 0.0, -14.0, 6.5, 60.0],
	"paws": [Vector2(14.5, 12.0), 10.0, 0.0, -24.0, 6.0, 60.0],
}
## Fly-camera shots: [camera position, look target, fov].
const FLY := {
	"overview": [Vector3(30, 175, 300), Vector3(-5, 0, -10), 42.0],
	"passage_high": [Vector3(-92, 48, 22), Vector3(-114, 18, -13), 55.0],
}

var _walk_log: Array[String] = []


func _wants_title() -> bool:
	return false


func _ready() -> void:
	if not Game.has_arg("noui"):
		Game.args["noui"] = "1"
	if Game.has_arg("quality"):
		Settings.ensure()
		Settings.data["quality"] = clampi(int(Game.arg("quality")), 0, 2)
	super._ready()
	if Game.arg_on("walk"):
		_walk.call_deferred()
	elif String(Game.arg("route", "")) != "":
		_route.call_deferred(String(Game.arg("route")))
	elif String(Game.arg("shots", "")) != "":
		_shots.call_deferred(String(Game.arg("shots")).split(",", false))


# --- shots ---------------------------------------------------------------------------------------------------------

func _place(name_s: String) -> void:
	if FLY.has(name_s):
		var f: Array = FLY[name_s]
		var p: Vector3 = f[0]
		var at: Vector3 = f[1]
		var d := at - p
		var yaw := rad_to_deg(atan2(-d.x, -d.z))
		var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		cam.set_fly(p, yaw, pitch)
		cam.cam.fov = float(f[2])
		# Overviews look from far away: push the haze back so the island reads (gameplay keeps the mood's fog).
		RenderingServer.global_shader_parameter_set("g_fog_near", 380.0)
		RenderingServer.global_shader_parameter_set("g_fog_far", 1300.0)
		return
	var s: Array = SHOTS.get(name_s, SHOTS["pier"])
	var xz: Vector2 = s[0]
	var face: float = s[1]
	var p: Vector3 = world.ground(Vector3(xz.x, 0.0, xz.y))
	# On top of whatever solid is there (pier deck, plaza paving...).
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(xz.x, 120.0, xz.y), Vector3(xz.x, -20.0, xz.y), 1))
	if not hit.is_empty() and name_s != "arena":
		p = hit["position"]
	if name_s == "swim":
		# Out from the beach until the water is deep enough to swim (> 1.3 m), facing along the coast.
		var q := Vector3(xz.x, 0.0, xz.y)
		for k in 60:
			if float(world.height_at(q.x, q.z)) < -1.9:
				break
			q.z += 0.5
		p = Vector3(q.x, 0.0, q.z)
	hero.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(face)), p))
	cam.follow(hero)
	cam.yaw = face + float(s[2])
	cam.pitch = float(s[3])
	cam.distance = float(s[4])
	cam.cam.fov = float(s[5])
	cam.snap()


func _shots(names: PackedStringArray) -> void:
	var out_dir := String(Game.arg("outdir", OS.get_user_data_dir()))
	var settle := int(Game.arg("settle", "24"))
	for n in names:
		_place(n)
		for i in settle:
			await get_tree().process_frame
			if i == settle / 2 and not FLY.has(n):
				cam.snap()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(n + ".png"))
		var h: Vector3 = hero.global_position
		print("SHOT %s drawcalls=%d primitives=%d objects=%d process_ms=%.1f physics_ms=%.1f hero=%s state=%s" % [n,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			str(h.snapped(Vector3.ONE * 0.1)), String(hero.motion_state)])
		if Game.arg_on("breakdown"):
			await _breakdown(n)
		if FLY.has(n):
			cam.follow(hero)
			if Game.tod and Game.tod.has_method("set_state"):
				Game.tod.call("set_state", Game.arg("tod", "golden"))
	get_tree().quit()


# --- walk check ----------------------------------------------------------------------------------------------------

func _wlog(s: String) -> void:
	print("WALK " + s)


func _pts(path_index: int, from_i: int = 0, to_i: int = -1) -> Array[Vector2]:
	var pts: Array = L.PATHS[path_index][0]
	var out: Array[Vector2] = []
	var last := pts.size() - 1 if to_i < 0 else to_i
	for i in range(from_i, last + 1):
		out.append(pts[i])
	return out


func _walk() -> void:
	await get_tree().create_timer(1.0).timeout
	var c: Dictionary = world.cave()
	var ac: Vector3 = c["arena_center"]
	var ea: Vector3 = c["entrance_a"]
	var eb: Vector3 = c["entrance_b"]
	# Leg 1: pier -> village -> forest -> west ramp -> the passage's south rim (main road, PATHS[0]).
	var leg1: Array[Vector2] = [Vector2(14, 118)]
	leg1.append_array(_pts(0))
	# Leg 2 (after the crossing): north rim -> boar clearing -> ridge meadow (PATHS[1] to the fork), mouth A
	# (PATHS[2]), the tunnel, the arena, tunnel B and out to the boulder's apron.
	var leg2: Array[Vector2] = _pts(1, 0, 8)
	leg2.append_array(_pts(2, 1))
	var out_a := (Vector2(ea.x, ea.z) - Vector2(ac.x, ac.z)).normalized()
	var out_b := (Vector2(eb.x, eb.z) - Vector2(ac.x, ac.z)).normalized()
	leg2.append(Vector2(ea.x, ea.z))
	leg2.append(Vector2(ac.x, ac.z) + out_a * 6.0)
	leg2.append(Vector2(ac.x, ac.z) + Vector2(-out_a.y, out_a.x) * 3.0)
	leg2.append(Vector2(ac.x, ac.z) + out_b * 6.0)
	leg2.append(Vector2(eb.x, eb.z))
	leg2.append(Vector2(eb.x, eb.z) + out_b * 6.0)
	var t0 := Time.get_ticks_msec()
	var r1 := await _drive(leg1, "pier -> passage south rim")
	# The crossing: the chain spear's zip (CORE) is simulated by a teleport onto the north rim.
	var north: Vector3 = world.ground(Vector3(L.PASS_NORTH.x, 0.0, L.PASS_NORTH.y))
	hero.teleport(Transform3D(Basis(Vector3.UP, PI), north))
	cam.follow(hero)
	_wlog("crossing: teleport to the north rim %s (stands in for the chain zip)" % str(north.snapped(Vector3.ONE * 0.1)))
	await get_tree().create_timer(0.5).timeout
	var r2 := await _drive(leg2, "north rim -> meadow -> mouth A -> arena -> mouth B")
	var total_t: float = r1["time"] + r2["time"]
	var total_d: float = r1["dist"] + r2["dist"]
	var issues: int = r1["stuck"] + r2["stuck"] + r1["fell"] + r2["fell"] + r1["skipped"] + r2["skipped"]
	_wlog("SUMMARY route time %.1f s (game), %.0f m walked, stuck %d, skipped %d, below ground %d, real %d ms -> %s" % [
		total_t, total_d, r1["stuck"] + r2["stuck"], r1["skipped"] + r2["skipped"], r1["fell"] + r2["fell"], Time.get_ticks_msec() - t0,
		"PASS" if issues == 0 else "ISSUES"])
	get_tree().quit()


func _route(spec: String) -> void:
	var pts: Array[Vector2] = []
	for part in spec.split(";", false):
		var xy := part.split(",")
		pts.append(Vector2(float(xy[0]), float(xy[1])))
	var start: Vector3 = world.ground(Vector3(pts[0].x, 0.0, pts[0].y))
	hero.teleport(Transform3D(Basis.IDENTITY, start))
	cam.follow(hero)
	await get_tree().create_timer(0.5).timeout
	pts.remove_at(0)
	var r := await _drive(pts, "route probe", false)
	var p: Vector3 = hero.global_position
	var end := pts[pts.size() - 1]
	var ok := Vector2(p.x, p.z).distance_to(end) < 2.0
	print("ROUTE %s: hero at %s, %.1f m from the last point, stuck %d" % ["reached" if ok else "blocked", str(p.snapped(Vector3.ONE * 0.1)), Vector2(p.x, p.z).distance_to(end), r["stuck"]])
	get_tree().quit()


## Drives the hero through `pts` (XZ waypoints). Returns {time, dist, stuck, skipped, fell}. Without `skip`, a
## stuck hero gives up after 8 s instead of being teleported on.
func _drive(pts: Array[Vector2], label: String, skip: bool = true) -> Dictionary:
	var res := {"time": 0.0, "dist": 0.0, "stuck": 0, "skipped": 0, "fell": 0}
	_wlog("leg '%s': %d waypoints from %s" % [label, pts.size(), str(hero.global_position.snapped(Vector3.ONE * 0.1))])
	var i := 0
	var last_p: Vector3 = hero.global_position
	var still_t := 0.0
	var wp_t := 0.0
	var fell_flag := false
	var jump_t := -1.0
	while i < pts.size():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		res["time"] += dt
		wp_t += dt
		var p: Vector3 = hero.global_position
		var target := pts[i]
		var to := target - Vector2(p.x, p.z)
		var reach := 1.4 if i < pts.size() - 1 else 1.0
		# A waypoint counts once it is close, or once the hero has passed it along the route.
		var passed := false
		if i + 1 < pts.size():
			var seg := pts[i + 1] - target
			passed = to.length() < 4.0 and (Vector2(p.x, p.z) - target).dot(seg) > 0.0
		if to.length() < reach or passed:
			i += 1
			wp_t = 0.0
			continue
		var w := to.normalized()
		var b: Basis = cam.yaw_basis()
		var bx := Vector2(b.x.x, b.x.z)
		var bz := Vector2(b.z.x, b.z.z)
		hero.debug_move = Vector2(w.dot(bx), w.dot(bz))
		var moved := Vector2(p.x - last_p.x, p.z - last_p.z).length()
		res["dist"] += moved
		last_p = p
		# Below the ground (falling through the terrain) while not swimming.
		var g: float = world.height_at(p.x, p.z)
		if p.y < g - 0.5 and hero.motion_state != &"swim" and not fell_flag:
			fell_flag = true
			res["fell"] += 1
			_wlog("BELOW GROUND at %s (ground %.2f)" % [str(p.snapped(Vector3.ONE * 0.1)), g])
		elif p.y >= g - 0.2:
			fell_flag = false
		# Stuck: barely moving for 1.5 s.
		if moved < 0.6 * dt:
			still_t += dt
		else:
			still_t = 0.0
		if jump_t >= 0.0:
			jump_t += dt
			if jump_t > 0.25:
				Input.action_release("jump")
				jump_t = -1.0
		if still_t > 1.5 and still_t - dt <= 1.5:
			res["stuck"] += 1
			_wlog("STUCK at %s heading to waypoint %d %s: %s" % [str(p.snapped(Vector3.ONE * 0.1)), i, str(target), _what_blocks(p, Vector3(w.x, 0, w.y))])
			Input.action_press("jump")
			jump_t = 0.0
		if not skip and still_t > 8.0:
			break
		if wp_t > to.length() / 2.0 + 8.0 or still_t > 5.0:
			if not skip:
				break
			res["skipped"] += 1
			_wlog("SKIPPED waypoint %d %s (still %.1f s): teleported there" % [i, str(target), still_t])
			hero.teleport(Transform3D(hero.global_transform.basis, world.ground(Vector3(target.x, 0.0, target.y))))
			still_t = 0.0
			wp_t = 0.0
			last_p = hero.global_position
			i += 1
	hero.debug_move = Vector2.ZERO
	_wlog("leg '%s' done: %.1f s, %.0f m, stuck %d, skipped %d, below ground %d, ends at %s" % [label, res["time"], res["dist"], res["stuck"], res["skipped"], res["fell"], str(hero.global_position.snapped(Vector3.ONE * 0.1))])
	return res


func _what_blocks(p: Vector3, fwd: Vector3) -> String:
	var sp := get_world_3d().direct_space_state
	var out := []
	for hgt in [0.3, 1.0, 1.7]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, hgt, 0), p + Vector3(0, hgt, 0) + fwd * 1.5, 1 | 8)
		q.exclude = [hero.get_rid()]
		var hit := sp.intersect_ray(q)
		if not hit.is_empty():
			out.append("%s at %.1f m (h %.1f, n %s)" % [(hit["collider"] as Node).name, (hit["position"] as Vector3).distance_to(p + Vector3(0, hgt, 0)), hgt, str((hit["normal"] as Vector3).snapped(Vector3.ONE * 0.01))])
	var g: float = world.height_at(p.x + fwd.x, p.z + fwd.z) - world.height_at(p.x, p.z)
	return ("%s; ground rises %.2f m in the next metre, slope_y %.2f" % [", ".join(out) if not out.is_empty() else "no collider in front", g, (world.normal_at(p.x + fwd.x, p.z + fwd.z) as Vector3).y])


## Hides one category of the scene at a time and prints what it costs in this view (draw calls, primitives).
func _breakdown(shot: String) -> void:
	var cats := {
		"grass": func(c: Node) -> bool: return c is Grass,
		"terrain": func(c: Node) -> bool: return String(c.name).begins_with("Terrain"),
		"trees": func(c: Node) -> bool: return c is MultiMeshInstance3D,
		"rocks+shrubs": func(c: Node) -> bool: return c is MeshInstance3D and (String(c.name).begins_with("rocks") or String(c.name).begins_with("shrubs") or String(c.name).begins_with("flowers")),
		"village": func(c: Node) -> bool: return c.name == "Village",
		"cave": func(c: Node) -> bool: return String(c.name).begins_with("Cave") or String(c.name).begins_with("Tunnel") or String(c.name).begins_with("Mouth") or String(c.name).begins_with("Crest") or String(c.name).begins_with("Light") or String(c.name).begins_with("Shaft") or String(c.name).begins_with("Spire"),
		"fauna": func(c: Node) -> bool: return c.name == "Ambient",
		"other world": func(c: Node) -> bool: return c is Node3D and not (c is CollisionObject3D),
	}
	var base_dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var base_pr := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var line := "BREAKDOWN %s total dc=%d pr=%d |" % [shot, base_dc, base_pr]
	var done := {}
	var hidden_all: Array[Node3D] = []
	for cat in cats:
		var hidden := 0
		for c in world.get_children():
			if done.has(c) or not (c is Node3D) or not (c as Node3D).visible:
				continue
			if (cats[cat] as Callable).call(c):
				(c as Node3D).visible = false
				hidden_all.append(c)
				done[c] = true
				hidden += 1
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var pr := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		line += " %s: dc %d pr %d (%d nodes) |" % [cat, base_dc - dc, base_pr - pr, hidden]
		base_dc = dc
		base_pr = pr
	line += " rest (sea, sky, hero, toon passes): dc %d pr %d" % [base_dc, base_pr]
	print(line)
	for c in hidden_all:
		c.visible = true
