extends Node
## The arena's autotest bot (tools/arena.tscn with autotest=1, or bot=<test,test,...>). It plays the hero through
## the real input path (HeroInput.bot virtual buttons, Hero.debug_move, input events for the lock-on, the camera
## for aiming the chain spear) and prints one line per test:
##   ARENA test <name> PASS|FAIL <details>
##   ARENA autotest passed=N/M result=PASS|FAIL
## Tests: lockon (acquire, flick to switch, release), combo (3 blows, the finisher last), heavy (charge, release:
## 30 damage, guard break), kill (a locked straw soldier cut down: slow motion, the lock lets go, he dissolves and
## a new one stands up), guard (a sparring swing on the shield), parry (guard just before the swing lands: the
## post is thrown open), dodge (roll through a swing), hurt (no guard: health lost, the hit reaction, knocked
## back), light (yank a straw sack to the hero), ledge (zip to the ring under the west cliff and climb onto it), rings (ring to ring across the sea gap, then onto the far cliff),
## beast (yank the straw bull into a pillar: stunned; wrestle it to the end), boulder (drag the boulder into the
## east doorway), ramps (foot IK: standing across and up the 30-degree ramp, each sole on the slope within 7 cm;
## then a walk up the 15-degree one), death (health to nothing: Game.hero_died, DEAD, the death action, back at the
## start with full health). "ARENA mark <tag> frame=<n>" lines tell tools/arena_strips.py which movie frames show each move.
## Throughout, a camera watch: the view must never sit inside the world (a point query on the world layer at the
## camera) nor stay within 1.2 m of the hero's head for 0.35 s or more ("ARENA test camera", counted last).
## Run headless faster than real time: godot --headless --path . res://tools/arena.tscn --fixed-fps 60
##   --quit-after 6000 -- autotest=1

const ALL := ["lockon", "combo", "heavy", "kill", "guard", "parry", "dodge", "hurt", "light", "ledge", "rings", "beast", "boulder", "ramps", "death"]

var arena: Node = null
var hero: Hero
var cam: CameraRig
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
var _pq := PhysicsPointQueryParameters3D.new()
## Frame cost (headless: scripts + physics, no drawing): sums and peaks in ms.
var _perf_n := 0
var _perf_proc := 0.0
var _perf_phys := 0.0
var _perf_proc_max := 0.0
var _perf_phys_max := 0.0


func _ready() -> void:
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta


func _process(delta: float) -> void:
	if hero == null or cam == null or cam.cam == null:
		return
	var pp := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf_n += 1
	_perf_proc += pp
	_perf_phys += ph
	_perf_proc_max = maxf(_perf_proc_max, pp)
	_perf_phys_max = maxf(_perf_phys_max, ph)
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
	_pq.position = c
	_pq.collision_mask = 1
	if not hero.get_world_3d().direct_space_state.intersect_point(_pq, 1).is_empty():
		if Game.arg_on("botdebug"):
			var hits := hero.get_world_3d().direct_space_state.intersect_point(_pq, 4)
			var names := []
			for h in hits:
				names.append(str(h["collider"].name) + "/" + str(h.get("shape", -1)))
			var o: Vector3 = cam._safe_origin()
			print("ARENA cam inside t=%.2f cam=%s origin=%s hero=%s state=%s yaw=%.1f pitch=%.1f arm=%.2f in=%s cast=%.3f focus=%s" % [_time, str(c), str(o), str(hero.global_position), hero.state_name(), cam.yaw, cam.pitch, cam._arm, str(names), cam._arm_cast(o, c), str(cam.focus)])
		_cam_inside += 1
		if _cam_inside_at == "":
			_cam_inside_at = "%s@%d" % [_cur, Engine.get_frames_drawn()]


func _run() -> void:
	for i in 10:
		await get_tree().physics_frame
	hero = arena.get("hero")
	cam = arena.get("cam")
	(arena.get("sparring") as TrainingDummy).auto_attack = false
	var list: Array = ALL
	if Game.has_arg("bot"):
		list = Array(String(Game.arg("bot")).split(",", false))
	for t in list:
		_cur = String(t)
		var ok: bool = await _run_test(String(t))
		_total += 1
		if ok:
			_passed += 1
		hero.inp.bot_clear()
		hero.debug_move = Vector2.ZERO
		await _wait(0.4)
	var cam_ok := _cam_inside == 0 and _cam_close_max < 0.35
	_total += 1
	if cam_ok:
		_passed += 1
	_result("camera", cam_ok, "min_to_head=%.2f (%s) close_max=%.2fs (%s) inside_frames=%d first_inside=%s" % [_cam_min,
		_cam_min_at, _cam_close_max, _cam_close_at, _cam_inside, _cam_inside_at])
	if _perf_n > 0:
		print("ARENA perf frames=%d process_ms avg=%.2f max=%.2f physics_ms avg=%.2f max=%.2f" % [_perf_n,
			_perf_proc / _perf_n, _perf_proc_max, _perf_phys / _perf_n, _perf_phys_max])
	print("ARENA autotest passed=%d/%d result=%s" % [_passed, _total, "PASS" if _passed == _total else "FAIL"])
	if Game.arg_on("quit"):
		get_tree().quit()


func _run_test(t: String) -> bool:
	match t:
		"lockon":
			return await _t_lockon()
		"combo":
			return await _t_combo()
		"heavy":
			return await _t_heavy()
		"kill":
			return await _t_kill()
		"guard":
			return await _t_guard()
		"parry":
			return await _t_parry()
		"dodge":
			return await _t_dodge()
		"light":
			return await _t_light()
		"ledge":
			return await _t_ledge()
		"rings":
			return await _t_rings()
		"beast":
			return await _t_beast()
		"boulder":
			return await _t_boulder()
		"ramps":
			return await _t_ramps()
		"hurt":
			return await _t_hurt()
		"death":
			return await _t_death()
	print("ARENA test %s FAIL unknown test" % t)
	return false


# --- helpers ---------------------------------------------------------------------------------------------------

func _result(nm: String, ok: bool, details: String) -> bool:
	print("ARENA test %s %s %s" % [nm, "PASS" if ok else "FAIL", details])
	return ok


func _mark(tag: String) -> void:
	print("ARENA mark %s frame=%d t=%.2f" % [tag, Engine.get_frames_drawn(), _time])


func _wait(s: float) -> void:
	var t0 := _time
	while _time - t0 < s:
		await get_tree().physics_frame


## Waits until `cond` is true or `timeout` s pass; returns whether it came true.
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


func _press_event(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


## Places the hero at `p` facing `look` (and the camera behind him), at rest.
func _place(p: Vector3, look: Vector3) -> void:
	var d := Combat.flat(look - p).normalized()
	var z := -d
	var x := Vector3.UP.cross(z).normalized()
	if hero.state != Hero.St.MOVE or not hero.is_alive():
		hero.revive(Transform3D(Basis(x, Vector3.UP, z), p))
	else:
		hero.teleport(Transform3D(Basis(x, Vector3.UP, z), p))
	hero.stamina = hero.max_stamina
	hero.exhausted = false
	hero.hp = hero.max_hp
	hero.invulnerable = 0.0
	cam.lock_on(null)
	cam.follow(hero, true)
	await _wait(0.35)


## The stick that walks the hero towards `p` (camera relative).
func _stick_to(p: Vector3) -> Vector2:
	var d := Combat.flat(p - hero.global_position)
	if d.length() < 0.01:
		return Vector2.ZERO
	var local := cam.yaw_basis().inverse() * d.normalized()
	return Vector2(local.x, local.z).normalized()


func _walk_to(p: Vector3, tol: float, timeout: float) -> bool:
	var t0 := _time
	while _time - t0 < timeout:
		var d := Combat.flat(p - hero.global_position).length()
		if d <= tol:
			hero.debug_move = Vector2.ZERO
			return true
		hero.debug_move = _stick_to(p)
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	return false


# --- tests -----------------------------------------------------------------------------------------------------

func _t_lockon() -> bool:
	var posts: Array = arena.get("dummies")
	var s: Dictionary = arena.get("world").call("spots")
	await _place(s["start"], (posts[1] as Node3D).global_position)
	var changes: Array = []
	var cb := func(t: Node) -> void: changes.append(t)
	Game.lock_changed.connect(cb)
	cam.aim_at((posts[1] as Node3D).global_position + Vector3(0, 1.3, 0))
	await _wait(0.2)
	_mark("lockon")
	await _press_event("lock_on")
	await _wait(0.4)
	var first := cam.lock_target
	# a flick of the right stick to the right: the next target on that side
	Input.action_press("look_right", 1.0)
	await _wait(0.12)
	Input.action_release("look_right")
	await _wait(0.5)
	var second := cam.lock_target
	# walk round it locked on: the hero keeps facing it
	hero.debug_move = Vector2(1.0, 0.0)
	await _wait(1.0)
	hero.debug_move = Vector2.ZERO
	var facing_ok := false
	if second:
		var to := Combat.flat(second.global_position - hero.global_position).normalized()
		facing_ok = to.dot(hero.forward()) > 0.9
	await _press_event("lock_on")
	await _wait(0.3)
	var released := cam.lock_target == null
	Game.lock_changed.disconnect(cb)
	var ok: bool = first != null and second != null and first != second and released and facing_ok and changes.size() >= 3
	return _result("lockon", ok, "first=%s second=%s strafe_facing=%s released=%s signals=%d" % [
		first.name if first else "null", second.name if second else "null", str(facing_ok), str(released), changes.size()])


func _t_combo() -> bool:
	var post: TrainingDummy = (arena.get("dummies") as Array)[1]
	await _place(post.global_position + Vector3(0, 0, 2.2), post.global_position)
	var h0 := post.hits
	var attacks: Array = []
	var cb := func(_t: Node, h: Dictionary) -> void: attacks.append(String(h.get("attack", "")))
	hero.blow_landed.connect(cb)
	_mark("combo")
	await _tap(&"attack")
	await _wait(0.3)
	await _tap(&"attack")
	await _wait(0.3)
	await _tap(&"attack")
	await _wait(1.1)
	hero.blow_landed.disconnect(cb)
	var n := post.hits - h0
	var ok: bool = n >= 3 and attacks.size() >= 3 and attacks[0] == "attack1" and attacks[1] == "attack2" and attacks[2] == "attack3"
	return _result("combo", ok, "hits=%d blows=%s" % [n, str(attacks)])


func _t_heavy() -> bool:
	var post: TrainingDummy = (arena.get("dummies") as Array)[1]
	await _place(post.global_position + Vector3(0, 0, 2.1), post.global_position)
	var h0 := post.hits
	var st0 := hero.stamina
	_mark("heavy")
	hero.inp.bot[&"attack"] = true
	var charging: bool = await _until(func() -> bool: return hero.state == Hero.St.CHARGE, 0.4)
	await _wait(0.5)
	var charged := hero.melee.charged
	hero.inp.bot[&"attack"] = false
	await _wait(1.0)
	var last: Dictionary = post.last_hit
	var ok: bool = charging and charged and post.hits > h0 and float(last.get("amount", 0.0)) >= 30.0 and bool(last.get("guard_break", false))
	return _result("heavy", ok, "charging=%s charged=%s amount=%.0f stamina %.0f->%.0f" % [str(charging), str(charged),
		float(last.get("amount", 0.0)), st0, hero.stamina])


## Lock on to a straw soldier and cut him down with the combo: he dies on the finisher (36 hp), the killing blow
## brings slow motion, the lock lets go by itself, he leaves the groups, topples, dissolves and is freed; a new one
## stands up at the same spot.
func _t_kill() -> bool:
	var men: Array = arena.get("straw")
	var man: TrainingDummy = men[0]
	if not Combat.is_alive(man):
		await _until(func() -> bool: return Combat.is_alive((arena.get("straw") as Array)[0]), 5.0)
		man = (arena.get("straw") as Array)[0]
	await _place(man.global_position + Vector3(0, 0, 2.2), man.global_position)
	cam.aim_at(man.lock_point())
	await _wait(0.15)
	await _press_event("lock_on")
	await _wait(0.2)
	var locked := cam.lock_target == man
	var released := [false]
	var cb := func(t: Node) -> void:
		if t == null:
			released[0] = true
	Game.lock_changed.connect(cb)
	var slow := [false]
	var watch := func() -> void:
		if Engine.time_scale < 0.9 and Engine.time_scale > Game.HITSTOP_SCALE + 0.01:
			slow[0] = true
	get_tree().process_frame.connect(watch)
	_mark("kill")
	await _tap(&"attack")
	await _wait(0.3)
	await _tap(&"attack")
	await _wait(0.3)
	await _tap(&"attack")
	var dead: bool = await _until(func() -> bool: return not man.is_alive(), 1.5)
	await _wait(0.6)
	var left_groups := not man.is_in_group("lockable") and not man.is_in_group("damageable") and not man.is_in_group("chain_anchor")
	get_tree().process_frame.disconnect(watch)
	Game.lock_changed.disconnect(cb)
	var man_id := man.get_instance_id()
	man = null
	var freed: bool = await _until(func() -> bool: return instance_from_id(man_id) == null, 3.0)
	var back: bool = await _until(func() -> bool: return Combat.is_alive((arena.get("straw") as Array)[0]), 3.0)
	var ok: bool = locked and dead and released[0] and slow[0] and left_groups and freed and back
	return _result("kill", ok, "locked=%s dead=%s lock_released=%s slowmo=%s left_groups=%s freed=%s respawned=%s" % [str(locked),
		str(dead), str(released[0]), str(slow[0]), str(left_groups), str(freed), str(back)])


func _sparring_spot() -> TrainingDummy:
	var sp: TrainingDummy = arena.get("sparring")
	return sp


func _t_guard() -> bool:
	var sp := _sparring_spot()
	await _place(sp.global_position + Vector3(0, 0, 1.9), sp.global_position)
	await _wait(0.4)
	hero.inp.bot[&"guard"] = true
	await _wait(0.6) # long past the parry window
	var hp0 := hero.hp
	var st0 := hero.stamina
	_mark("guard")
	sp.strike_soon(0.6)
	await _wait(1.0)
	hero.inp.bot[&"guard"] = false
	var ok: bool = sp.last_verdict == &"blocked" and hero.hp == hp0 and hero.stamina < st0
	return _result("guard", ok, "verdict=%s hp %.0f->%.0f stamina %.0f->%.0f" % [sp.last_verdict, hp0, hero.hp, st0, hero.stamina])


func _t_parry() -> bool:
	var sp := _sparring_spot()
	await _place(sp.global_position + Vector3(0, 0, 1.9), sp.global_position)
	await _wait(0.6)
	var p0 := sp.parried_count
	var hp0 := hero.hp
	_mark("parry")
	sp.strike_soon(0.6)
	# the club lands 0.6 + 0.09 s from now: raise the shield 0.09 s before
	await _wait(0.6)
	hero.inp.bot[&"guard"] = true
	await _wait(0.6)
	hero.inp.bot[&"guard"] = false
	var ok: bool = sp.last_verdict == &"parried" and sp.parried_count > p0 and hero.hp == hp0
	return _result("parry", ok, "verdict=%s parried=%d hp %.0f->%.0f" % [sp.last_verdict, sp.parried_count, hp0, hero.hp])


func _t_dodge() -> bool:
	var sp := _sparring_spot()
	await _place(sp.global_position + Vector3(0, 0, 1.7), sp.global_position)
	await _wait(1.6) # the post recovers from the parry
	var hp0 := hero.hp
	var perfect := [false]
	var cb := func() -> void: perfect[0] = true
	hero.perfect_dodge.connect(cb)
	_mark("dodge")
	sp.strike_soon(0.6)
	await _wait(0.47)
	hero.debug_move = Vector2(1.0, 0.0)
	await _tap(&"dodge", 0.05)
	await _wait(0.3)
	hero.debug_move = Vector2.ZERO
	await _wait(0.6)
	hero.perfect_dodge.disconnect(cb)
	var ok: bool = hero.hp == hp0 and (sp.last_verdict == &"dodged" or sp.last_verdict == &"miss")
	return _result("dodge", ok, "verdict=%s perfect=%s hp %.0f->%.0f" % [sp.last_verdict, str(perfect[0]), hp0, hero.hp])


## No guard: the club lands: health lost, the hit reaction (STAGGER, rig hit / hit_heavy), knocked back.
func _t_hurt() -> bool:
	var sp := _sparring_spot()
	await _place(sp.global_position + Vector3(0, 0, 1.9), sp.global_position)
	await _wait(1.0)
	var hp0 := hero.hp
	var p0 := hero.global_position
	var states: Array = []
	var cb := func(st: StringName) -> void: states.append(st)
	hero.state_changed.connect(cb)
	_mark("hurt")
	sp.strike_soon(0.6)
	var hurt: bool = await _until(func() -> bool: return hero.hp < hp0, 1.4)
	var react := String(hero.rig.action)
	await _wait(0.6)
	hero.state_changed.disconnect(cb)
	var pushed := Combat.flat(hero.global_position - p0).length()
	var ok: bool = hurt and states.has(&"stagger") and react.begins_with("hit") and pushed > 0.05
	return _result("hurt", ok, "hp %.0f->%.0f reaction=%s states=%s pushed=%.2f m verdict=%s" % [hp0, hero.hp, react, str(states), pushed, sp.last_verdict])


## Health to nothing: Game.hero_died, the DEAD phase, the death action; main.gd brings him back (full health,
## PLAY) after its respawn delay.
func _t_death() -> bool:
	var sp := _sparring_spot()
	await _place(sp.global_position + Vector3(0, 0, 1.9), sp.global_position)
	await _wait(1.0)
	var died := [false]
	var cb := func() -> void: died[0] = true
	Game.hero_died.connect(cb)
	hero.hp = 1.0
	_mark("death")
	sp.strike_soon(0.6)
	var dead: bool = await _until(func() -> bool: return not hero.is_alive(), 1.5)
	var phase_dead := Game.phase == Game.Phase.DEAD
	var anim := String(hero.rig.action)
	var back: bool = await _until(func() -> bool: return hero.is_alive() and Game.phase == Game.Phase.PLAY, 6.0)
	Game.hero_died.disconnect(cb)
	var ok: bool = dead and died[0] and phase_dead and anim == "death" and back and hero.hp >= hero.max_hp
	return _result("death", ok, "dead=%s signal=%s phase_dead=%s anim=%s respawned=%s hp=%.0f" % [str(dead), str(died[0]), str(phase_dead), anim, str(back), hero.hp])


func _t_light() -> bool:
	var sack: TrainingDummy = (arena.get("sacks") as Array)[0]
	var s: Dictionary = arena.get("world").call("spots")
	sack.teleport(arena.get("world").call("ground", (s["sacks"] as Array)[0]), PI * 0.5)
	var from := sack.global_position + Vector3(0, 0, 12.0)
	await _place(from, sack.global_position)
	cam.aim_at(sack.chain_point())
	await _wait(0.3)
	var cand := hero.chain_candidate == sack
	_mark("light")
	await _tap(&"chain")
	var stuck: bool = await _until(func() -> bool: return hero.spear.mode == ChainSpear.STUCK or hero.chain_mode == &"yank", 1.5)
	await _wait(1.6)
	var d := Combat.flat(sack.global_position - hero.global_position).length()
	var in_front := Combat.flat(sack.global_position - hero.global_position).normalized().dot(hero.forward()) > 0.7
	var ok: bool = cand and stuck and d < 2.9 and in_front
	return _result("light", ok, "candidate=%s stuck=%s dist=%.2f in_front=%s" % [str(cand), str(stuck), d, str(in_front)])


func _ring(nm: String) -> ChainRing:
	return arena.get("world").get_node(nm) as ChainRing


func _t_ledge() -> bool:
	var s: Dictionary = arena.get("world").call("spots")
	var ring := _ring("RingLedge")
	await _place(s["ledge_throw"], ring.chain_point())
	cam.aim_at(ring.chain_point())
	await _wait(0.3)
	var cand := hero.chain_candidate == ring
	_mark("ledge")
	await _tap(&"chain")
	var zipped: bool = await _until(func() -> bool: return hero.motion_state == &"zip", 1.5)
	if Game.arg_on("botdebug"):
		for k in 6:
			await get_tree().process_frame
			print("ARENA chain links=%d visible=%s hand=%s tip=%s" % [hero.spear._mm.visible_instance_count, str(hero.spear._mmi.visible), str(hero.rig.chain_origin()), str(hero.spear._tip)])
	var landed: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.y > 4.5, 5.0)
	var p := hero.global_position
	var ok: bool = cand and zipped and landed and p.x < -23.2
	return _result("ledge", ok, "candidate=%s zipped=%s on_top=%s at=(%.1f, %.1f, %.1f)" % [str(cand), str(zipped), str(landed), p.x, p.y, p.z])


func _t_rings() -> bool:
	var s: Dictionary = arena.get("world").call("spots")
	var a := _ring("RingStack")
	var b := _ring("RingFar")
	await _place(s["gap_throw"], a.chain_point())
	cam.aim_at(a.chain_point())
	await _wait(0.3)
	var cand_a := hero.chain_candidate == a
	_mark("rings")
	await _tap(&"chain")
	var hang: bool = await _until(func() -> bool: return hero.state == Hero.St.HANG, 3.0)
	await _wait(0.4)
	cam.aim_at(b.chain_point())
	await _wait(0.25)
	var cand_b := hero.chain_candidate == b
	_mark("rings2")
	await _tap(&"chain")
	var landed: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.y > 4.8, 5.0)
	var p := hero.global_position
	var ok: bool = cand_a and hang and cand_b and landed and p.z < -48.0
	return _result("rings", ok, "cand_a=%s hang=%s cand_b=%s landed=%s at=(%.1f, %.1f, %.1f)" % [str(cand_a), str(hang), str(cand_b), str(landed), p.x, p.y, p.z])


func _t_beast() -> bool:
	var s: Dictionary = arena.get("world").call("spots")
	var beast: Enemy = arena.get("beast")
	beast.teleport(arena.get("world").call("ground", s["beast"]), 0.0)
	beast.stun = 0.0
	beast.stagger = 0.0
	await _place(s["beast_throw"], beast.chain_point())
	cam.aim_at(beast.chain_point())
	await _wait(0.35)
	var cand := hero.chain_candidate == beast
	var slams0: int = beast.get("slams")
	var wins0: int = beast.get("wins")
	_mark("beast")
	await _tap(&"chain")
	var slammed: bool = await _until(func() -> bool: return int(beast.get("slams")) > slams0, 2.5)
	var stunned := beast.is_stunned()
	await _wait(0.3)
	# walk up to it and grab it
	var near: bool = await _walk_to(beast.global_position, beast.radius + 1.3, 3.0)
	await _wait(0.1)
	_mark("grapple")
	await _tap(&"interact")
	var grappling: bool = await _until(func() -> bool: return hero.state == Hero.St.GRAPPLE, 0.5)
	# the wrestle: squeeze in the windows, brace (guard) against the thrashes
	var t0 := _time
	var squeezed := 0
	while hero.state == Hero.St.GRAPPLE and _time - t0 < 16.0:
		var warned: bool = beast.get("_warned") or beast.telegraph_t > 0.0
		hero.inp.bot[&"guard"] = warned
		if hero._cue_left > 0.0 and hero._cue_left < 0.42:
			await _tap(&"attack", 0.04)
			squeezed += 1
			continue
		await get_tree().physics_frame
	hero.inp.bot[&"guard"] = false
	await _wait(0.8)
	var won := int(beast.get("wins")) > wins0
	var ok: bool = cand and slammed and stunned and near and grappling and won
	return _result("beast", ok, "candidate=%s slammed=%s stunned=%s near=%s grappled=%s presses=%d won=%s hero_stamina=%.0f" % [
		str(cand), str(slammed), str(stunned), str(near), str(grappling), squeezed, str(won), hero.stamina])


func _t_boulder() -> bool:
	var s: Dictionary = arena.get("world").call("spots")
	var w = arena.get("world")
	var boulder: Boulder = w.call("cave")["boulder"]
	boulder.global_position = w.call("ground", s["boulder"]) + Vector3(0, 0.02, 0)
	boulder.velocity = Vector3.ZERO
	var door: Vector3 = s["door"]
	await _place(s["door_throw"], boulder.chain_point())
	cam.aim_at(boulder.chain_point())
	await _wait(0.35)
	var cand := hero.chain_candidate == boulder
	_mark("boulder")
	hero.inp.bot[&"chain"] = true
	var hauling: bool = await _until(func() -> bool: return hero.chain_mode == &"haul", 1.5)
	# walk away (east) with the chain held: the boulder follows into the doorway and jams there
	var away := Vector3(s["door_throw"]) + Vector3(5.0, 0, 0)
	var t0 := _time
	var sealed := false
	while _time - t0 < 14.0:
		hero.debug_move = _stick_to(away) if Combat.flat(away - hero.global_position).length() > 0.5 else Vector2.ZERO
		if boulder.is_blocking(door, 1.4):
			sealed = true
			break
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	await _wait(0.6)
	hero.inp.bot[&"chain"] = false
	await _wait(0.6)
	var bp := boulder.global_position
	var still := boulder.is_blocking(door, 1.6)
	var ok: bool = cand and hauling and sealed and still
	return _result("boulder", ok, "candidate=%s hauling=%s sealed=%s at=(%.2f, %.2f, %.2f) door_x=%.1f" % [str(cand), str(hauling), str(sealed), bp.x, bp.y, bp.z, door.x])


## The ankle of each foot (world) against the ground under it: the error of each sole's height (m).
func _sole_errors() -> Vector2:
	var out := Vector2.ZERO
	var space := hero.get_world_3d().direct_space_state
	for side in 2:
		var ankle: Vector3 = hero.rig.global_transform * hero.rig.foot_local(side)
		var q := PhysicsRayQueryParameters3D.create(ankle + Vector3(0, 0.6, 0), ankle - Vector3(0, 0.9, 0), 1, [hero.get_rid()])
		var hit := space.intersect_ray(q)
		var err := 9.0
		if not hit.is_empty():
			err = ankle.y - ((hit["position"] as Vector3).y + RigHeracles.P_ANKLE.y)
		if side == 0:
			out.x = err
		else:
			out.y = err
	return out


func _t_ramps() -> bool:
	# the 30-degree ramp (the second down the terrace's west side): its middle, from a ray
	var ang := deg_to_rad(30.0)
	var run := 1.6 / tan(ang)
	var mid := Vector3(12.0 - run * 0.5, 6.0, 16.3 + 2.35 + 1.0)
	var space := hero.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid - Vector3(0, 8, 0), 1))
	if hit.is_empty():
		return _result("ramps", false, "no ramp under %s" % str(mid))
	var p: Vector3 = hit["position"]
	# across the slope (facing north): one foot higher than the other
	await _place(p + Vector3(0, 0.05, 0), p + Vector3(0, 0, -3.0))
	_mark("ramps")
	await _wait(1.0)
	var across := _sole_errors()
	# facing up the slope (east)
	await _place(p + Vector3(0, 0.05, 0), p + Vector3(3.0, 0, 0))
	await _wait(1.0)
	var up := _sole_errors()
	# walk up the 15-degree ramp onto the terrace (looks only: the gait on a slope)
	var run15 := 1.6 / tan(deg_to_rad(15.0))
	await _place(Vector3(12.0 - run15 - 1.5, 1.25, 17.3), Vector3(14.0, 2.8, 17.3))
	_mark("ramps_walk")
	var top := Vector3(13.5, 2.8, 17.3)
	var t0 := _time
	while _time - t0 < 3.0 and Combat.flat(top - hero.global_position).length() > 0.6:
		hero.debug_move = _stick_to(top)
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	var climbed := hero.global_position.y > 2.6
	var worst := maxf(maxf(absf(across.x), absf(across.y)), maxf(absf(up.x), absf(up.y)))
	var ok := worst < 0.07 and climbed
	return _result("ramps", ok, "across=(%.3f, %.3f) up=(%.3f, %.3f) worst=%.3f climbed_15=%s" % [across.x, across.y, up.x, up.y, worst, str(climbed)])
