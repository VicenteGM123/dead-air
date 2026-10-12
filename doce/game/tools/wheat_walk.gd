extends "res://scripts/main.gd"
## The free hand in the wheat (FINAL, the client's "Gladiator" shot): the real game with the hero walking through
## the wheat field, westwards into the low sun, his left hand out over the ears (Hero._feed_brush ->
## RigHeracles.set_brush). It prints what the brush does and, with a window, saves PNGs from the gameplay camera and
## from a low cinematic camera that tracks him (rendering is switched off between the shots: cheap).
##   xvfb-run ... godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tools/wheat_walk.tscn \
##     --fixed-fps 30 --quit-after 3000 -- outdir=/abs/dir [noui=1] [run=1]
## Headless (no shots) it is a test: "WHEAT brush ... result=PASS|FAIL" (the hand goes out within 2 s of walking
## into the wheat, its fingers end within 12 cm of the ears' tops, the shield it carries up the arm stays clear of his
## body (shield_clip), it is back in when he leaves the field or draws his guard). seq=<n> [seqcam=low|close|game]: once
## the hand is out, <n> consecutive frames at 15 fps instead of the stills (for a GIF), then quits.

const START := Vector2(-46.0, 27.0)
const FACE := 90.0 # west, into the sun

var _out := ""
var _n := 0
var _t := 0.0
var _log: Array[String] = []
var _cine: Camera3D = null


func _wants_title() -> bool:
	return false


func _ready() -> void:
	if not Game.has_arg("noui"):
		Game.args["noui"] = "1"
	Game.args["nohints"] = "1"
	super._ready()
	_out = String(Game.arg("outdir", ""))
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	if _shooting():
		RenderingServer.render_loop_enabled = false
	_run.call_deferred()


func _shooting() -> bool:
	return _out != "" and DisplayServer.get_name() != "headless"


func _physics_process(delta: float) -> void:
	_t += delta


func _wait(s: float) -> void:
	var t0 := _t
	while _t - t0 < s:
		await get_tree().physics_frame


func _shot(tag: String) -> void:
	var r: RigHeracles = hero.rig
	var hl := r.hand_l().global_position
	var wheat: Object = world.get("wheat")
	var top := 0.0
	if wheat != null:
		top = float(wheat.call("ear_top", hl.x, hl.z)) + float(world.call("height_at", hl.x, hl.z))
	print("WHEAT shot %s t=%.2f brush=%.2f speed=%.2f hand_y_over_ears=%.3f in_field=%.2f" % [tag, _t, r.brush_amount(),
		Vector2(hero.velocity.x, hero.velocity.z).length(), hl.y - top, float(wheat.call("in_field", hl.x, hl.z)) if wheat else 0.0])
	if not _shooting():
		return
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(_out.path_join("wheat_%02d_%s.png" % [_n, tag]))
	_n += 1
	RenderingServer.render_loop_enabled = false


## A low camera following him: behind and to his left, at the height of the ears, looking past his hand along the
## field into the sun (or `side`: level with his hand, from the left, a little ahead).
func _cine_cam(kind: String) -> void:
	if _cine == null:
		_cine = Camera3D.new()
		_cine.fov = 40.0
		add_child(_cine)
	_cine.current = true
	_place_cine(kind)


func _place_cine(kind: String) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(FACE))
	var fwd := -b.z
	var left := -b.x
	var p := hero.rig.global_position
	var eye: Vector3
	var at: Vector3
	match kind:
		"side":
			eye = p + left * 1.7 + fwd * 2.3 + Vector3(0, 1.65, 0)
			at = p + left * 0.35 + Vector3(0, 1.0, 0)
		"close":
			eye = p + left * 0.95 - fwd * 1.5 + Vector3(0, 1.12, 0)
			at = p + left * 0.55 + fwd * 1.2 + Vector3(0, 0.98, 0)
		_:
			eye = p + left * 1.1 - fwd * 2.6 + Vector3(0, 0.95, 0)
			at = p + left * 0.35 + fwd * 2.0 + Vector3(0, 1.05, 0)
	_cine.global_position = eye
	_cine.look_at(at, Vector3.UP)


func _process(_delta: float) -> void:
	if _cine != null and _cine.current and hero != null:
		_place_cine(String(_cine.get_meta(&"kind", "")))


func _run() -> void:
	await _wait(0.5)
	var p: Vector3 = world.ground(Vector3(START.x, 0.0, START.y))
	hero.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(FACE)), p))
	cam.follow(hero)
	cam.yaw = FACE
	cam.pitch = -14.0
	cam.snap()
	await _wait(0.6)
	var run := Game.arg_on("run")
	var mag := 1.0 if run else 0.45
	var out_t := -1.0
	var max_b := 0.0
	var best_gap := 9.0
	hero.debug_move = Vector2(0.0, -mag)
	var walk_t0 := _t
	# walking in: the hand goes out
	var clip := 0.0
	while _t - walk_t0 < 3.4:
		await get_tree().process_frame
		var b: float = hero.rig.brush_amount()
		max_b = maxf(max_b, b)
		if out_t < 0.0 and b > 0.8:
			out_t = _t - walk_t0
		clip = maxf(clip, _shield_clip())
	if int(Game.arg("seq", "0")) > 0:
		await _sequence(int(Game.arg("seq", "0")), String(Game.arg("seqcam", "low")))
		get_tree().quit()
		return
	await _shot("game_a")
	await _wait(0.45)
	await _shot("game_b")
	await _wait(0.45)
	await _shot("game_c")
	var gaps: Array[float] = []
	for kind in ["low", "close"]:
		_cine_cam(kind)
		_cine.set_meta(&"kind", kind)
		await _wait(0.2)
		await _shot("cine_%s_a" % kind)
		await _wait(0.4)
		await _shot("cine_%s_b" % kind)
		var r: RigHeracles = hero.rig
		var hl := r.hand_l().global_position
		var top := float(world.wheat.call("ear_top", hl.x, hl.z)) + float(world.height_at(hl.x, hl.z))
		gaps.append(hl.y - top)
	_cine.current = false
	cam.cam.current = true
	for g in gaps:
		best_gap = minf(best_gap, absf(g))
	# guard: the hand comes back to the shield
	hero.inp.bot[&"guard"] = true
	await _wait(0.6)
	var b_guard: float = hero.rig.brush_amount()
	hero.inp.bot[&"guard"] = false
	await _wait(1.6)
	# out of the field (back east, to the forest's edge): the hand comes in
	hero.debug_move = Vector2.ZERO
	hero.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(FACE)), world.ground(Vector3(-28.0, 0.0, 34.0))))
	await _wait(0.2)
	hero.debug_move = Vector2(0.0, -mag)
	await _wait(1.0)
	var b_out: float = hero.rig.brush_amount()
	hero.debug_move = Vector2.ZERO
	var ok := out_t >= 0.0 and out_t < 2.6 and b_guard < 0.15 and b_out < 0.05 and best_gap < 0.12 and clip < 0.01
	print("WHEAT brush out_after=%.2f s max=%.2f guard=%.2f outside=%.2f hand_vs_ears=%s shield_clip=%.3f m result=%s" % [out_t, max_b,
		b_guard, b_out, str(gaps), clip, "PASS" if ok else "FAIL"])
	get_tree().quit()


## How deep (m) the shield's rim and its inner lip go into the body's volumes this frame (the rig's own keep-out
## capsules: torso, helmet, hips, thighs; and the left pauldron, a 0.1 m ball on the shoulder): 0 when clear.
func _shield_clip() -> float:
	var r: RigHeracles = hero.rig
	if r.brush_amount() <= 0.01:
		return 0.0
	var piv := r._piv["farm_l_s"] as Node3D
	var rest: Vector3 = r._rest[RigHeracles.FARM_L]
	var fr: Transform3D = piv.transform * RigHeracles.shield_xf(Transform3D(Basis.IDENTITY, rest), rest)
	var paul: Vector3 = r._bx[RigHeracles.PAUL_L].origin
	var worst := 0.0
	for k in 20:
		var a := TAU * float(k) / 20.0
		for q in [Vector3(cos(a) * RigHeracles.SHIELD_R * 1.03, 0.0, sin(a) * RigHeracles.SHIELD_R * 1.03), Vector3(cos(a) * RigHeracles.SHIELD_R * 0.9, -0.03, sin(a) * RigHeracles.SHIELD_R * 0.9)]:
			var p: Vector3 = fr * q
			var d1 := (r._keep_out(p, 0.0) as Vector3).distance_to(p)
			var d2 := 0.1 - p.distance_to(paul)
			if Game.arg_on("clipdebug") and maxf(d1, d2) > 0.005:
				print("WHEAT clip t=%.2f brush=%.2f action=%s k=%d inner=%s body=%.3f paul=%.3f p=%s" % [_t, r.brush_amount(), r.action, k, str(q.y < 0.0), d1, d2, str(p.snapped(Vector3.ONE * 0.01))])
			worst = maxf(worst, maxf(d1, d2))
	return worst


## <n> consecutive frames from camera `kind` (low / close: the cinematic ones, game: the gameplay camera), one every
## other physics frame (15 fps at --fixed-fps 30).
func _sequence(n: int, kind: String) -> void:
	if kind != "game":
		_cine_cam(kind)
		_cine.set_meta(&"kind", kind)
	await _wait(0.1)
	for i in n:
		if _shooting():
			RenderingServer.render_loop_enabled = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img != null and not img.is_empty():
				img.save_png(_out.path_join("seq_%03d.png" % i))
			RenderingServer.render_loop_enabled = false
		await get_tree().physics_frame
		await get_tree().physics_frame
	print("WHEAT seq %d frames (%s)" % [n, kind])
