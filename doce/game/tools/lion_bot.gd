extends Node
## ENCOUNTERS lane L: the Nemean Lion's test bot, loaded by scripts/encounters/lion_encounter.gd with lionbot=...
## It plays the real hero through the real input path (HeroInput.bot buttons, debug_move, the camera aiming the
## chain spear) on the island's cave, reads the lion's state like a player watching its telegraphs, and prints
##   LION test <name> PASS|FAIL <details>          one line per test
##   LION fight <case> <phase> PASS|FAIL ...        the full fights, per phase
##   LION autotest passed=N/M result=PASS|FAIL
##   LION mark <tag> frame=N                        (frames for renders)
## Run (60 fps, headless):
##   godot --headless --path . --fixed-fps 60 --quit-after 30000 -- play=1 lionbot=units quit=1
##   godot --headless --path . --fixed-fps 60 --quit-after 60000 -- play=1 lionbot=fight_sealed quit=1
##   godot --headless --path . --fixed-fps 60 --quit-after 60000 -- play=1 lionbot=fight_open quit=1
## Tests:
##   bounce        blades bounce off it (no damage, the hero recoils), the rule said once for two bounces
##   strike        its swipe lands on a hero who does nothing (health lost, knocked back); with the shield raised
##                 at the glint it is parried (the lion reels, no damage)
##   pounce        a pillar 2.5 m behind the hero, the lion pounces, he rolls aside on the leap: it slams, stunned
##   yank          the chain spear yanks it from 4.5 m off a pillar (the line passes beside it): slams, stunned
##   wrestle_win   stunned, E: squeezes in the windows, guard through the thrashes: won, 3 squeezes of damage
##   wrestle_fail  stunned, E: presses out of the windows: it throws him off (hurt, staggered, pushed away)
##   roar          the roar's wave shoves him back several metres, without damage, through his raised shield
##   perch         (phase 2) it bounds onto a rock perch; yanked off it, it falls and is stunned
##   escape        mouth B open, under half health: it runs out through the crack, vanishes out of sight, heals a
##                 little and comes back in through mouth A behind the hero with a pounce
##   lair          the hero deep in a tunnel: the lion does not follow him out of its arena
##   death_reset   the hero falls mid-fight: the lion is back in its den at full health, the boss bar gone, the
##                 boulder where it was, the hero back on his feet at his altar
##   victory       the last squeeze: it dies, Heracles takes its pelt (outfit lion), the victory, free roam, the
##                 boat to Lerna: "Zarpar" shows labour II's card and the slice ends
##   fight_sealed  the whole fight with mouth B sealed by the boulder, won with the intended mechanics
##   fight_open    the whole fight with mouth B open: it flees at half health and ambushes him from mouth A
##   careless      balance: a hero who only hacks at it (no roll, no guard, no chain) is killed, and the fight
##                 resets (the lion back in its den at full health)
## units = bounce, strike, pounce, yank, wrestle_win, wrestle_fail, roar, perch, escape, lair, death_reset, victory
## Args: quit=1 (quit after the tests), linger=<s> (play on that long after the last test, for movies), nocard=1,
## fight_t=<s> (the full fights' time limit), botdebug=1 (traces).

const UNITS := ["bounce", "strike", "pounce", "yank", "wrestle_win", "wrestle_fail", "roar", "perch", "escape", "lair", "death_reset", "victory"]

var encounter: Node = null
var hero: Hero
var cam: CameraRig
var world
var lion: Lion
var cave := {}
var _time := 0.0
var _passed := 0
var _total := 0
var _msgs: Array = []
var _cards: Array = []
var _boss_ends: Array = []
var _deaths := 0
var _boulder_home := Vector3.ZERO


func _ready() -> void:
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta


func _run() -> void:
	for i in 30:
		await get_tree().physics_frame
	hero = Game.hero
	cam = Game.camera
	world = Game.world
	lion = encounter.get("lion")
	cave = encounter.get("cave")
	Game.message.connect(func(t: String, _s: String, _k: String) -> void: _msgs.append(t))
	Game.labor_card.connect(func(i: int, _t: String) -> void: _cards.append(i))
	Game.boss_ended.connect(func(v: bool) -> void: _boss_ends.append(v))
	Game.hero_died.connect(func() -> void: _deaths += 1)
	_boulder_home = (cave["boulder"] as Node3D).global_position
	# renders of single moments: labour I's card counts as already shown (it would cover the first test)
	if Game.arg_on("nocard") and Game.ui != null and "_labors_shown" in Game.ui:
		(Game.ui.get("_labors_shown") as Dictionary)[1] = true
	var arg := String(Game.arg("lionbot", "units"))
	var list: Array = []
	for t in arg.split(",", false):
		if t == "units":
			list.append_array(UNITS)
		else:
			list.append(t)
	for t in list:
		var ok: bool = await _run_test(String(t))
		_total += 1
		if ok:
			_passed += 1
		hero.inp.bot_clear()
		hero.debug_move = Vector2.ZERO
		await _wait(0.3)
	print("LION autotest passed=%d/%d result=%s" % [_passed, _total, "PASS" if _passed == _total else "FAIL"])
	# (movies: the victory card and the free roam after the fight)
	await _wait(float(Game.arg("linger", "0")))
	if Game.arg_on("quit"):
		get_tree().quit()


func _run_test(t: String) -> bool:
	if not is_instance_valid(lion) and t != "probe":
		return _result(t, false, "the lion is gone (a test after victory?)")
	match t:
		"probe":
			return _t_probe()
		"watch":
			return await _t_watch()
		"bounce":
			return await _t_bounce()
		"strike":
			return await _t_strike()
		"pounce":
			return await _t_pounce()
		"yank":
			return await _t_yank()
		"wrestle_win":
			return await _t_wrestle(true)
		"wrestle_fail":
			return await _t_wrestle(false)
		"roar":
			return await _t_roar()
		"perch":
			return await _t_perch()
		"escape":
			return await _t_escape()
		"lair":
			return await _t_lair()
		"death_reset":
			return await _t_death_reset()
		"victory":
			return await _t_victory()
		"fight_sealed":
			return await _t_fight(true)
		"fight_open":
			return await _t_fight(false)
		"careless":
			return await _t_careless()
	print("LION test %s FAIL unknown test" % t)
	return false


# --- helpers ---------------------------------------------------------------------------------------------------

func _result(nm: String, ok: bool, details: String) -> bool:
	print("LION test %s %s %s" % [nm, "PASS" if ok else "FAIL", details])
	return ok


func _mark(tag: String) -> void:
	print("LION mark %s frame=%d t=%.2f" % [tag, Engine.get_frames_drawn(), _time])


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


func _press(action: StringName, on: bool) -> void:
	hero.inp.bot[action] = on


func _c() -> Vector3:
	return cave["arena_center"]


func _ground(p: Vector3) -> Vector3:
	return world.call("ground", p)


## The floor under `p`: the first world surface a ray from 2.5 m above it meets (the pier's deck, not the sea bed
## under it), else the terrain.
func _floor_under(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p - Vector3(0, 30.0, 0), 1)
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else _ground(p)


func _place(p: Vector3, look: Vector3, on_floor: bool = false) -> void:
	var g := _floor_under(p) if on_floor else _ground(p)
	var d := Combat.flat(look - g).normalized()
	var z := -d
	var x := Vector3.UP.cross(z).normalized()
	hero.revive(Transform3D(Basis(x, Vector3.UP, z), g + Vector3(0, 0.05, 0)))
	hero.invulnerable = 0.0
	hero.inp.bot_clear()
	hero.debug_move = Vector2.ZERO
	cam.lock_on(null)
	cam.follow(hero, true)
	await _wait(0.3)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := Combat.flat(to - from)
	return atan2(-d.x, -d.z)


func _stick_to(p: Vector3) -> Vector2:
	var d := Combat.flat(p - hero.global_position)
	if d.length() < 0.01:
		return Vector2.ZERO
	return _stick_dir(d.normalized())


func _stick_dir(d: Vector3) -> Vector2:
	var local := cam.yaw_basis().inverse() * Combat.flat(d).normalized()
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


## A roll along `dir` (world, horizontal): the stick that way and a tap of dodge.
func _roll(dir: Vector3) -> void:
	hero.debug_move = _stick_dir(dir)
	await get_tree().physics_frame
	await _tap(&"dodge", 0.05)
	await _wait(0.12)
	hero.debug_move = Vector2.ZERO


## The pillar nearest to `p` (index), and the radius of a column at `y` m over the floor.
func _pillar_r(i: int, y: float = 0.8) -> float:
	var cb = world.get("cave_builder")
	if cb != null and i < (cb.pillar_cols as Array).size():
		return float(cb.call("_prof_r", cb.pillar_cols[i], y)) * 1.08
	return 1.2


## Throws the chain spear at the lion (camera aimed at it): true when it bit.
func _throw_at_lion(settle: float = 0.25) -> bool:
	cam.lock_on(null)
	cam.aim_at(lion.chain_point())
	await _wait(settle)
	cam.aim_at(lion.chain_point())
	await get_tree().physics_frame
	if hero.chain_candidate != lion:
		return false
	await _tap(&"chain")
	return await _until(func() -> bool: return hero.spear.mode == ChainSpear.STUCK and hero.spear.target == lion, 1.2)


## The wrestle from the hero's side: squeeze (attack) in each window, guard held while a thrash winds up. `good`
## false: presses out of the windows instead. Returns when it is over.
func _wrestle(good: bool, timeout: float = 16.0) -> void:
	var t0 := _time
	var last_window := 0.0
	var pressed_in := false
	var bad := 0
	while hero.is_grappling() and _time - t0 < timeout:
		var w := hero.grapple_window_left()
		var thrash: float = lion.telegraph_left() if is_instance_valid(lion) else 0.0
		hero.inp.bot[&"guard"] = thrash > 0.0 and w <= 0.0
		if good:
			if w > 0.0 and not pressed_in and w < float(lion.PH[clampi(lion.phase, 0, 2)]["window"]) - 0.06:
				pressed_in = true
				await _tap(&"attack", 0.03)
			if w <= 0.0:
				pressed_in = false
		else:
			# out of the windows: just after one closed
			if last_window > 0.0 and w <= 0.0 and bad < 3:
				await _wait(0.12)
				if hero.grapple_window_left() <= 0.0:
					bad += 1
					await _tap(&"attack", 0.03)
		last_window = w
		_view_sample()
		_held_at = hero.global_position
		await get_tree().physics_frame
	hero.inp.bot[&"guard"] = false


## The wrestle seen from the gameplay camera: is the hero (head and chest) hidden behind the lion's head and mane or
## its body? Counted per physics frame (the view metric of the wrestle tests).
var _view_frames := 0
var _held_at := Vector3.ZERO
var _view_hidden := 0
var _view_part := 0
var _view_by_head := 0
var _view_by_body := 0
var _view_offs := {}
var _seg_pts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])


func _view_sample() -> void:
	if cam == null or cam.cam == null or not is_instance_valid(lion) or lion._r == null:
		return
	var lens: Vector3 = cam.cam.global_position
	var f := lion.forward()
	var lp := lion.global_position
	var head: Vector3 = lion._r.head().global_position
	var a := lp + f * 0.8 + Vector3(0, 0.95, 0)
	var b := lp - f * 0.95 + Vector3(0, 0.95, 0)
	var hid := 0
	for qv in [hero.global_position + Vector3(0, 1.7, 0), hero.global_position + Vector3(0, 1.25, 0)]:
		var q: Vector3 = qv
		var seg: Vector3 = q - lens
		var u: float = clampf((head - lens).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		# (the head and its flared ruff: ~0.65 m round the skull)
		var by_head: bool = (lens + seg * u).distance_to(head) < 0.65 and u < 0.97
		var by_body: bool = Combat.seg_seg_dist2(lens, q, a, b, _seg_pts) < 0.55 * 0.55
		if by_head or by_body:
			hid += 1
		if by_head:
			_view_by_head += 1
		if by_body:
			_view_by_body += 1
	if Game.arg_on("viewtrace") and _view_frames % 8 == 0:
		var side_v := f.rotated(Vector3.UP, PI * 0.5)
		var loc := func(v: Vector3) -> String:
			var r := v - lp
			return "(f %.2f s %.2f y %.2f)" % [r.dot(f), r.dot(side_v), r.y]
		print("VIEW %d lens %s hero %s head %s hid %d off %s crane %s" % [_view_frames, loc.call(lens), loc.call(hero.global_position),
			loc.call(head), hid, str(cam.get("_grap_off")), str(cam.get("_grap_crane"))])
	var key := "%s%d" % ["crane" if bool(cam.get("_grap_crane")) else "", int(cam.get("_grap_off"))]
	_view_offs[key] = int(_view_offs.get(key, 0)) + 1
	_view_frames += 1
	if hid == 2:
		_view_hidden += 1
	elif hid == 1:
		_view_part += 1


## Walks up to the stunned lion and grabs it (E). True when the wrestle started.
func _grab(timeout: float = 5.0) -> bool:
	var t0 := _time
	while _time - t0 < timeout:
		if not is_instance_valid(lion) or not lion.can_grapple(hero):
			hero.debug_move = Vector2.ZERO
			return false
		if hero.interact_target == lion:
			hero.debug_move = Vector2.ZERO
			await _tap(&"interact", 0.05)
			if await _until(func() -> bool: return hero.is_grappling(), 0.4):
				return true
		else:
			# towards the side of its neck
			var f := lion.forward()
			var side := f.rotated(Vector3.UP, PI * 0.5)
			if side.dot(Combat.flat(hero.global_position - lion.global_position)) < 0.0:
				side = -side
			hero.debug_move = _stick_to(lion.global_position + f * 1.1 + side * 1.6)
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	return false


# --- tests ------------------------------------------------------------------------------------------------------

func _t_probe() -> bool:
	var c: Vector3 = cave["arena_center"]
	print("LION probe center=%s radius=%s" % [str(c), str(cave.get("arena_radius"))])
	for k in ["entrance_a", "entrance_b", "inner_a", "inner_b", "seal_b", "dir_a", "dir_b", "lion_spawn"]:
		print("LION probe %s=%s" % [k, str(cave.get(k))])
	var ps: Array = cave["pillars"]
	for i in ps.size():
		var p: Vector3 = ps[i]
		var rel := p - c
		print("LION probe pillar %d at %s r=%.2f ang=%.1f deg radius@0.8=%.2f" % [i, str(p), Vector2(rel.x, rel.z).length(), rad_to_deg(atan2(rel.z, rel.x)), _pillar_r(i)])
	for o: Dictionary in encounter.get("outcrops"):
		print("LION probe perch %s" % str(o))
	return _result("probe", true, "")


func _t_watch() -> bool:
	await _place(_c() + Vector3(0, 0, 4.0), _c() + Vector3(0, 0, -8))
	var states: Array = []
	lion.lion_state.connect(func(s: StringName) -> void: states.append("%.1f:%s" % [_time, s]))
	await _wait(float(Game.arg("watch_t", "30")))
	print("LION watch states: %s" % " ".join(states))
	print("LION watch enc=%s hp=%.0f hero_hp=%.0f pounces=%d swipes=%d bites=%d roars=%d last_pounce=%s" % [encounter.call("state_name"),
		lion.hp, hero.hp, lion.pounces, lion.swipes, lion.bites, lion.roars, lion.last_pounce])
	return _result("watch", true, "")


## Two sword blows on the stunned lion: deflected, no damage, the hero recoils; the rule said once.
func _t_bounce() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var lp := c + Vector3(-1.5, 0, -1.0)
	var said0: int = encounter.get("rule_says")
	var msgs0 := _msgs.count("Su piel no la corta el bronce")
	encounter.call("debug_fight", lp, PI * 0.5, 30.0)
	lion.debug_hold = true
	lion.debug_stun(8.0)
	# the hero at the lion's flank, facing it
	var side := lion.forward().rotated(Vector3.UP, PI * 0.5)
	await _place(lion.global_position + side * 2.4, lion.global_position)
	var hp0 := lion.hp
	_mark("bounce")
	var recoils := 0
	for k in 2:
		await _tap(&"attack", 0.05)
		var r: bool = await _until(func() -> bool: return hero.rig.action == "recoil", 1.0)
		if r:
			recoils += 1
		await _wait(0.9)
	await _wait(0.3)
	var said: int = int(encounter.get("rule_says")) - said0
	var msgs := _msgs.count("Su piel no la corta el bronce") - msgs0
	var ok := lion.hp == hp0 and lion.bounces >= 2 and recoils == 2 and said <= 1 and int(encounter.get("rule_says")) == 1 and msgs <= 1
	lion.debug_hold = false
	return _result("bounce", ok, "lion_hp %.0f -> %.0f bounces=%d hero_recoils=%d rule_said_total=%d rule_messages=%d" % [hp0, lion.hp, lion.bounces, recoils, int(encounter.get("rule_says")), _msgs.count("Su piel no la corta el bronce")])


## The swipe from the front: it hurts a hero who does nothing; the guard raised as the glint fades parries it.
func _t_strike() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var L := c + Vector3(0, 0, -1.5)
	var H := c + Vector3(0, 0, 1.4)
	encounter.call("debug_fight", L, _yaw_to(L, H), 30.0)
	lion.debug_hold = true
	await _place(H, L)
	var hp0 := hero.hp
	var at0 := hero.global_position
	_mark("strike")
	lion.force(&"swipe")
	await _until(func() -> bool: return lion.state != Lion.S.SWIPE, 2.5)
	await _wait(0.3)
	var lost := hp0 - hero.hp
	var pushed := Combat.flat(hero.global_position - at0).length()
	await _wait(1.0)
	# the parry
	encounter.call("debug_fight", L, _yaw_to(L, H), 30.0)
	lion.debug_hold = true
	await _place(H, L)
	var parries := [0]
	var cb := func(_a: Node) -> void: parries[0] += 1
	hero.parried.connect(cb)
	var hp1 := hero.hp
	_mark("parry")
	lion.force(&"swipe")
	await _until(func() -> bool: return lion.telegraph_left() > 0.0 and lion.telegraph_left() < 0.1, 1.5)
	_press(&"guard", true)
	await _wait(0.45)
	var reeled := lion.stagger > 0.2 and lion.state == Lion.S.PROWL
	_press(&"guard", false)
	await _wait(0.5)
	hero.parried.disconnect(cb)
	lion.debug_hold = false
	var ok: bool = lost >= 13.0 and pushed > 0.3 and parries[0] == 1 and hero.hp == hp1 and reeled
	return _result("strike", ok, "swipe on a still hero: -%.0f hp, pushed %.2f m; parried=%d (lion reeling=%s) hp %.0f -> %.0f" % [lost, pushed,
		parries[0], str(reeled), hp1, hero.hp])


## A pillar 2.5 m behind the hero, the lion 8.5 m in front: it pounces, he rolls aside as it leaves the ground.
func _t_pounce() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var ps: Array = cave["pillars"]
	var c := _c()
	var best := -1
	for i in ps.size():
		var p: Vector3 = ps[i]
		if best < 0 or absf(Combat.flat(p - c).length() - 7.5) < 0.6:
			best = i
	var P: Vector3 = ps[best]
	var u := Combat.flat(c - P).normalized()
	var H := P + u * (_pillar_r(best) + 1.25)
	var L := H + u * 8.5
	await _place(H, L)
	var slams0 := lion.pounce_slams
	var cracks0 := _cracks()
	encounter.call("debug_fight", L, _yaw_to(L, H), 30.0)
	await _wait(0.4)
	_mark("pounce")
	lion.force(&"pounce")
	var leapt: bool = await _until(func() -> bool: return lion.in_pounce_flight(), 2.5)
	var side := Vector3(-u.z, 0, u.x)
	if leapt:
		await _roll(side)
	var stunned: bool = await _until(func() -> bool: return lion.is_stunned(), 2.0)
	_mark("pounce_slam")
	await _wait(0.5)
	var ok := leapt and stunned and lion.pounce_slams == slams0 + 1 and lion.last_pounce != &"hit" and _cracks() > cracks0
	return _result("pounce", ok, "pillar=%d hero_to_pillar=%.2f leapt=%s last_pounce=%s pounce_slams=%d stunned=%s lion_state=%s hero_hp=%.0f column cracks %d -> %d" % [best,
		Combat.flat(H - P).length(), str(leapt), lion.last_pounce, lion.pounce_slams, str(stunned), lion.state_name(), hero.hp, cracks0, _cracks()])


## Crack stages the lion's slams have grown on the columns so far (nemea_cave.gd crack_at).
func _cracks() -> int:
	var cb = world.get("cave_builder")
	if cb == null:
		return 0
	var n := 0
	for v in (cb.get("pillar_damage") as PackedInt32Array):
		n += v
	return n


## COMBAT.md 6.5's recipe: the lion 4.5 m from a pillar, the hero 11 m away on a line 21 degrees off the pillar
## (the spear flies past it); the yank's slide bends into the pillar: stunned.
func _t_yank() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var ps: Array = cave["pillars"]
	var c := _c()
	var ok := false
	var details := ""
	for i in [1, 2, 3, 0, 4]:
		var P: Vector3 = ps[i]
		var out := Combat.flat(P - c).normalized()
		# the lion between the pillar and the wall, the hero beyond the pillar towards the centre, a little off
		# its line (the spear flies past the pillar; the slide bends into it)
		var L := P + out * 3.7
		var to_p := Combat.flat(P - L).normalized()
		if not _lion_fits(L, to_p):
			details += "pillar=%d no room; " % i
			continue
		for sgn in [1.0, -1.0]:
			var w := to_p.rotated(Vector3.UP, deg_to_rad(23.0) * sgn)
			var H := L + w * 10.0
			if Combat.flat(H - c).length() > 11.5:
				continue
			encounter.call("debug_fight", L, _yaw_to(L, H), 30.0)
			lion.debug_hold = true
			await _place(H, L)
			var slams0 := lion.yank_slams
			_mark("yank")
			var bit: bool = await _throw_at_lion()
			var stunned := false
			if bit:
				if Game.arg_on("botdebug"):
					var l0 := lion.global_position
					for k in 30:
						await get_tree().physics_frame
						if k % 3 == 0:
							print("LION yankdbg k=%d lion=%s slide=%s state=%s pillar_d=%.2f hero_state=%s mode=%s" % [k, str(lion.global_position - l0), str(lion._slide_v), lion.state_name(),
								Combat.flat(P - lion.global_position).length(), hero.state_name(), hero.chain_mode])
				stunned = await _until(func() -> bool: return lion.is_stunned(), 2.5)
			details += "pillar=%d side=%d bit=%s stunned=%s yank_slams=%d; " % [i, int(sgn), str(bit), str(stunned), lion.yank_slams]
			if bit:
				ok = stunned and lion.yank_slams == slams0 + 1
				_mark("yank_slam")
				await _wait(0.6)
				lion.debug_hold = false
				return _result("yank", ok, details)
	lion.debug_hold = false
	return _result("yank", false, details + "(no throw)")


## Room for the lion's body at `p` facing `f` (its three capsules clear of the world, the rocks and the boulder).
func _lion_fits(p: Vector3, f: Vector3) -> bool:
	var space := hero.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 1.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1 | 8
	for z in [-1.12, -0.1, 0.88]:
		q.transform = Transform3D(Basis.IDENTITY, _ground(p) + Vector3(0, 0.85, 0) - f * z)
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true


func _t_wrestle(win: bool) -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var L := c + Vector3(1.0, 0, 2.0)
	encounter.call("debug_fight", L, 0.3, 30.0)
	lion.debug_hold = true
	lion.debug_stun(6.0)
	await _place(L + lion.forward().rotated(Vector3.UP, PI * 0.5) * 3.0 + lion.forward() * 1.0, L)
	var hp0 := lion.hp
	var won0 := lion.wrestles_won
	var lost0 := lion.wrestles_lost
	var hero_hp0 := hero.hp
	_view_frames = 0
	_view_hidden = 0
	_view_part = 0
	_view_by_head = 0
	_view_by_body = 0
	_view_offs = {}
	var grabbed: bool = await _grab()
	_mark("wrestle_win" if win else "wrestle_fail")
	if grabbed:
		await _wrestle(win)
	# (thrown from where he held it: the last spot of the wrestle; the farthest he got before a press still in the
	# attack buffer swings him back at it)
	var at0 := _held_at
	var moved := 0.0
	var tw := _time
	while _time - tw < 0.6:
		moved = maxf(moved, Combat.flat(hero.global_position - at0).length())
		await get_tree().physics_frame
	lion.debug_hold = false
	if win:
		var ok := grabbed and lion.wrestles_won == won0 + 1 and is_equal_approx(hp0 - lion.hp, Lion.SQUEEZE_DMG * 3.0) and hero.is_alive()
		var det := "grabbed=%s won=%d squeezes=%d lion_hp %.1f -> %.1f lion_state=%s hero_stamina=%.0f view: hero hidden %d%% / partly %d%% of %d frames" % [str(grabbed),
			lion.wrestles_won - won0, lion.squeezes, hp0, lion.hp, lion.state_name(), hero.stamina,
			100 * _view_hidden / maxi(1, _view_frames), 100 * _view_part / maxi(1, _view_frames), _view_frames]
		if Game.arg_on("botdebug"):
			det += " (by head %d, body %d; camera offsets %s)" % [_view_by_head, _view_by_body, str(_view_offs)]
		return _result("wrestle_win", ok, det)
	var ok2 := grabbed and lion.wrestles_lost == lost0 + 1 and lion.hp == hp0 and hero.hp < hero_hp0 and moved > 1.2
	return _result("wrestle_fail", ok2, "grabbed=%s lost=%d misses=%d lion_hp %.1f -> %.1f hero_hp %.0f -> %.0f thrown=%.2f m hero_state=%s" % [str(grabbed),
		lion.wrestles_lost - lost0, lion.misses, hp0, lion.hp, hero_hp0, hero.hp, moved, hero.state_name()])


func _t_roar() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var L := c + Vector3(0, 0, -3.0)
	var H := c + Vector3(0, 0, 2.5)
	encounter.call("debug_fight", L, _yaw_to(L, H), 30.0)
	lion.debug_hold = true
	await _place(H, L)
	# the shield raised: the roar is unblockable
	_press(&"guard", true)
	await _wait(0.3)
	var hp0 := hero.hp
	var at0 := hero.global_position
	_mark("roar")
	lion.force(&"roar")
	var waved: bool = await _until(func() -> bool: return lion.state == Lion.S.ROAR and lion._hit_done, 2.5)
	await _wait(1.0)
	_press(&"guard", false)
	var pushed := Combat.flat(hero.global_position - at0).dot(Combat.flat(H - L).normalized())
	lion.debug_hold = false
	var ok := waved and lion.last_roar_shoved and pushed > 2.0 and hero.hp == hp0
	return _result("roar", ok, "wave=%s shoved=%s pushed_back=%.2f m hero_hp %.0f -> %.0f" % [str(waved), str(lion.last_roar_shoved), pushed, hp0, hero.hp])


## Phase 2: onto a rock perch; the chain yanks it off: it falls and is stunned.
func _t_perch() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	encounter.call("debug_fight", c + Vector3(0, 0, -2.0), 0.0, 30.0)
	lion.phase = 1
	await _place(c + Vector3(0, 0, 3.0), c)
	lion.force(&"perch")
	var perched: bool = await _until(func() -> bool: return lion.state == Lion.S.PERCHED, 9.0)
	lion._perch_wait = 99.0
	var o: Dictionary = (encounter.get("outcrops") as Array)[lion._perch]
	_mark("perched")
	var bit := false
	if perched:
		# a throwing spot in front of the rock with the lion in sight
		var center: Vector3 = o["center"]
		var inward := Combat.flat(c - center).normalized()
		for dist in [7.5, 9.0, 6.0]:
			await _walk_to(center + inward * dist, 0.5, 5.0)
			lion._perch_wait = 99.0
			bit = await _throw_at_lion(0.3)
			if bit:
				break
	var stunned := false
	if bit:
		stunned = await _until(func() -> bool: return lion.is_stunned(), 3.0)
	_mark("perch_fall")
	await _wait(0.4)
	lion.debug_hold = false
	var ok := perched and bit and stunned and lion.fall_stuns >= 1
	return _result("perch", ok, "perched=%s bit=%s fell_stunned=%s fall_stuns=%d lion_state=%s" % [str(perched), str(bit), str(stunned), lion.fall_stuns, lion.state_name()])


## Mouth B open and the lion under half health: out through the crack, gone, back in through mouth A with a pounce.
func _t_escape() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var b: Node3D = cave["boulder"]
	b.global_position = _boulder_home
	await _wait(0.4)
	var open: bool = encounter.call("mouth_b_open")
	var c := _c()
	var inner_b: Vector3 = cave["inner_b"]
	var to_b := Combat.flat(inner_b - c).normalized()
	var L := c + to_b * 5.0
	encounter.call("debug_fight", L, _yaw_to(L, inner_b), 30.0)
	lion.hp = lion.max_hp * 0.45
	lion.phase = 1
	await _place(c - to_b * 2.5, L)
	var hp0 := lion.hp
	_mark("escape")
	lion.force(&"escape")
	var t0 := _time
	var log_t := -1.0
	var gone := false
	while _time - t0 < 16.0:
		if lion.state == Lion.S.AWAY:
			gone = true
			break
		if Game.arg_on("botdebug") and _time - log_t > 0.5:
			log_t = _time
			print("LION escdbg t=%.1f pos=%s route_i=%d/%d state=%s blocked=%.2f" % [_time - t0, str(lion.global_position.snapped(Vector3.ONE * 0.1)),
				lion._route_i, lion._route.size(), lion.state_name(), lion._blocked_t])
		await get_tree().physics_frame
	var esc_t := _time - t0
	var healed := lion.hp > hp0
	_mark("escaped")
	# he waits in the middle of the arena looking at the crack it left by: it comes back in behind him
	await _place(c, c + to_b * 5.0)
	var t1 := _time
	var back: bool = await _until(func() -> bool: return lion.state == Lion.S.AMBUSH, 12.0)
	var back_t := _time - t1
	var inner_a: Vector3 = cave["inner_a"]
	var from_a := back and Combat.flat(lion.global_position - inner_a).length() < Combat.flat(lion.global_position - inner_b).length()
	_mark("ambush")
	var pounced: bool = await _until(func() -> bool: return lion.state == Lion.S.POUNCE, 10.0)
	if pounced:
		await _until(func() -> bool: return lion.in_pounce_flight(), 2.0)
		await _roll(_dodge_side(lion.global_position, hero.global_position))
	await _wait(1.5)
	var ok := open and gone and healed and back and from_a and pounced
	return _result("escape", ok, "mouth_b_open=%s gone=%s in %.1f s healed %.0f -> %.0f back_in=%s after %.1f s through_a=%s pounced=%s" % [str(open),
		str(gone), esc_t, hp0, lion.hp, str(back), back_t, str(from_a), str(pounced)])


## The hero retreats deep into tunnel A: the lion stays in its arena (it guards it, it does not follow him out).
func _t_lair() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var inner_a: Vector3 = cave["inner_a"]
	var ent_a: Vector3 = cave["entrance_a"]
	var spot := inner_a.lerp(ent_a, 0.55)
	encounter.call("debug_fight", c, _yaw_to(c, spot), 0.5)
	await _place(spot, c)
	var far := 0.0
	var t0 := _time
	while _time - t0 < 6.0:
		far = maxf(far, Combat.flat(lion.global_position - c).length())
		await get_tree().physics_frame
	var hero_d := Combat.flat(hero.global_position - c).length()
	var ok := far <= Lion.LAIR_R + 1.0 and hero.is_alive() and hero.hp >= hero.max_hp
	return _result("lair", ok, "hero %.1f m from the centre (in tunnel A), the lion at most %.1f m from it (lair %.1f) hero_hp=%.0f" % [hero_d, far, Lion.LAIR_R, hero.hp])


func _t_death_reset() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var b: Node3D = cave["boulder"]
	var b0 := b.global_position
	encounter.call("debug_fight", c + Vector3(0, 0, -3.0), 0.0, 30.0)
	lion.hp = 200.0
	lion.phase = 1
	await _place(c + Vector3(0, 0, 3.0), c)
	var ends0 := _boss_ends.count(false)
	var deaths0 := _deaths
	# he prayed at the altar nearest the cave on his way (the Altar de la Sierra): he comes back there
	var altar: Node3D = null
	for a in world.call("altars"):
		if altar == null or Combat.flat((a as Node3D).global_position - c).length() < Combat.flat(altar.global_position - c).length():
			altar = a
	var cp0 = Game.checkpoint
	Game.checkpoint = altar
	var back_at: Vector3 = (altar.call("respawn_transform") as Transform3D).origin if altar != null else Vector3.INF
	_mark("death")
	hero.invulnerable = 0.0
	hero.take_hit(Combat.make_hit(500.0, &"blunt", Vector3.BACK, 2.0, 1.0, lion))
	var died: bool = await _until(func() -> bool: return _deaths > deaths0, 1.0)
	var reset: bool = await _until(func() -> bool: return lion.state == Lion.S.DEN and lion.hp == lion.max_hp, 4.0)
	var phase_ok: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY and hero.is_alive(), 6.0)
	var at_altar := back_at != Vector3.INF and Combat.flat(hero.global_position - back_at).length() < 2.0
	var ok: bool = died and reset and phase_ok and at_altar and lion.phase == 0 and _boss_ends.count(false) == ends0 + 1 and b.global_position.distance_to(b0) < 0.05 \
		and String(encounter.call("state_name")) == "idle"
	var res := _result("death_reset", ok, "died=%s lion_reset=%s (state=%s hp=%.0f phase=%d) boss_ended_false=%d hero_back=%s at the altar '%s'=%s boulder_moved=%.3f enc=%s" % [str(died),
		str(reset), lion.state_name(), lion.hp, lion.phase, _boss_ends.count(false) - ends0, str(phase_ok), str(altar.get("title") if altar else "-"), str(at_altar),
		b.global_position.distance_to(b0), str(encounter.call("state_name"))])
	Game.checkpoint = cp0
	return res


func _t_victory() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var L := c + Vector3(1.0, 0, 1.0)
	encounter.call("debug_fight", L, 0.4, 30.0)
	lion.phase = 2
	lion.hp = Lion.SQUEEZE_DMG
	lion.debug_hold = true
	lion.debug_stun(6.0)
	await _place(L + lion.forward().rotated(Vector3.UP, -PI * 0.5) * 3.0 + lion.forward(), L)
	var grabbed: bool = await _grab()
	_mark("victory_wrestle")
	if grabbed:
		await _wrestle(true)
	var dead := not lion.alive
	_mark("lion_dead")
	var pelt: bool = await _until(func() -> bool: return hero.outfit == &"lion" and hero.rig.outfit == &"lion", 8.0)
	_mark("don_skin")
	var vic: bool = await _until(func() -> bool: return Game.phase == Game.Phase.VICTORY, 6.0)
	_mark("victory")
	var roam: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY, 14.0)
	var boat: Node3D = world.call("boat")
	var ready_ok := boat != null and bool(boat.get("ready_to_sail"))
	# to the pier: "Zarpar"
	var dock: Vector3 = boat.global_position
	await _place(dock + Vector3(1.4, 0, 0), dock, true)
	var aimed: bool = await _until(func() -> bool: return hero.interact_target == boat, 2.0)
	var cards0 := _cards.count(2)
	await _tap(&"interact", 0.05)
	_mark("boat")
	var teaser: bool = await _until(func() -> bool: return _cards.count(2) == cards0 + 1 and bool(boat.get("sailing")), 2.0)
	await _wait(3.0)
	_mark("teaser")
	var ended: bool = await _until(func() -> bool: return bool(boat.get("_done")), 12.0)
	var ok := grabbed and dead and pelt and vic and roam and ready_ok and aimed and teaser and ended
	return _result("victory", ok, "grabbed=%s lion_dead=%s pelt=%s (outfit=%s) victory=%s free_roam=%s boat_ready=%s zarpar=%s teaser_card=%s slice_ended=%s" % [str(grabbed),
		str(dead), str(pelt), str(hero.outfit), str(vic), str(roam), str(ready_ok), str(aimed), str(teaser), str(ended)])


# --- balance: the careless hero ------------------------------------------------------------------------------------

func _t_careless() -> bool:
	encounter.call("debug_reset")
	await _wait(0.2)
	var c := _c()
	var dir_a: Vector3 = Combat.flat(cave["dir_a"]).normalized()
	var inner_a: Vector3 = cave["inner_a"]
	await _place(inner_a - dir_a * 1.0, c)
	var hits := {}
	var cb := func(h: Dictionary) -> void:
		var k := String(h.get("attack", "?"))
		hits[k] = int(hits.get(k, 0)) + 1
	hero.hurt.connect(cb)
	var deaths0 := _deaths
	var ends0 := _boss_ends.count(false)
	var t0 := _time
	_mark("careless")
	while _deaths == deaths0 and _time - t0 < 150.0:
		var to_l := Combat.flat(lion.global_position - hero.global_position)
		if lion.is_fighting() and to_l.length() < 3.2:
			hero.debug_move = Vector2.ZERO
			hero.facing = atan2(-to_l.x, -to_l.z)
			await _tap(&"attack", 0.05)
			await _wait(0.25)
		else:
			hero.debug_move = _stick_to(lion.global_position) if to_l.length() > 2.6 else Vector2.ZERO
			await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	var t_dead := _time - t0
	hero.hurt.disconnect(cb)
	var died := _deaths > deaths0
	var reset: bool = await _until(func() -> bool: return lion.state == Lion.S.DEN and lion.hp == lion.max_hp, 5.0)
	var back: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY and hero.is_alive(), 8.0)
	var ok: bool = died and reset and back and _boss_ends.count(false) == ends0 + 1 and lion.bounces > 0
	return _result("careless", ok, "killed=%s after %.0f s, hits taken %s, blades bounced %d, lion reset=%s hero back=%s" % [str(died), t_dead,
		str(hits), lion.bounces, str(reset), str(back)])


# --- the whole fight -----------------------------------------------------------------------------------------------

func _t_fight(sealed: bool) -> bool:
	var case := "sealed" if sealed else "open"
	encounter.call("debug_reset")
	await _wait(0.2)
	var b: Node3D = cave["boulder"]
	b.global_position = cave["seal_b"] if sealed else _boulder_home
	await _wait(0.5)
	var b_open: bool = encounter.call("mouth_b_open")
	var c := _c()
	var dir_a: Vector3 = Combat.flat(cave["dir_a"]).normalized()
	var inner_a: Vector3 = cave["inner_a"]
	await _place(inner_a - dir_a * 1.0, c)
	_mark("fight_" + case)
	var t0 := _time
	var deaths0 := _deaths
	var phase_seen := 0
	var phase_t := t0
	var results: Array = []
	var escaped_seen := false
	var ambush_seen := false
	var log_t := 0.0
	_bot_reset()
	_view_frames = 0
	_view_hidden = 0
	_view_part = 0
	_view_by_head = 0
	_view_by_body = 0
	_view_offs = {}
	_stall_t = _time
	_stall_hp = -1.0
	while is_instance_valid(lion) and lion.alive and _time - t0 < float(Game.arg("fight_t", "720")):
		await _bot_tick()
		if is_instance_valid(lion):
			_st_won = lion.wrestles_won
			_st_lost = lion.wrestles_lost
			_st_pounce = lion.pounce_slams
			_st_yank = lion.yank_slams
			_st_fall = lion.fall_stuns
		if lion.phase > phase_seen:
			phase_seen = lion.phase
			var line := "LION fight %s phase%d PASS t=%.1f s (%.1f s) wrestles_won=%d lost=%d slams pounce=%d yank=%d fall=%d hero_hp=%.0f deaths=%d" % [case, phase_seen,
				_time - t0, _time - phase_t, lion.wrestles_won, lion.wrestles_lost, lion.pounce_slams, lion.yank_slams, lion.fall_stuns, hero.hp, _deaths - deaths0]
			print(line)
			results.append(line)
			phase_t = _time
		if lion.escaped and not escaped_seen:
			escaped_seen = true
			print("LION fight %s escape at hp=%.0f%% t=%.1f" % [case, lion.hp_frac() * 100.0, _time - t0])
			_mark("escape")
		if lion.ambushes > 0 and not ambush_seen:
			ambush_seen = true
			print("LION fight %s ambush t=%.1f" % [case, _time - t0])
			_mark("ambush")
		# a fight going nowhere (no damage for 45 s): what each of them is doing, every 5 s
		if is_instance_valid(lion) and (lion.hp != _stall_hp or lion.phase != _stall_ph):
			_stall_hp = lion.hp
			_stall_ph = lion.phase
			_stall_t = _time
		if _time - _stall_t > 45.0 and _time - _stall_log > 5.0:
			_stall_log = _time
			print("LION stall t=%.1f lion=%s st=%.1f pp=%s leap=%s fl_t=%.2f/%.2f floor=%s vel=%s at=%s perch=%d cool=%.1f stun=%.1f | hero=%s at=%s mode=%s" % [
				_time - t0, lion.state_name(), lion.state_t, str(lion.get("_pp")), str(lion.get("_leap_mode")), float(lion.get("_fl_t")),
				float(lion.get("_fl_T")), str(lion.is_on_floor()), str(lion.velocity.snapped(Vector3.ONE * 0.1)),
				str((lion.global_position - c).snapped(Vector3.ONE * 0.1)), int(lion.get("_perch")), float(lion.get("_cool")), lion.stun,
				hero.state_name(), str((hero.global_position - c).snapped(Vector3.ONE * 0.1)), _mode])
		if Game.arg_on("botdebug") and _time - log_t > 2.0:
			log_t = _time
			print("LION bot t=%.1f lion=%s hp=%.0f phase=%d hero=%s hp=%.0f d=%.1f mode=%s lion_at=%s hero_at=%s" % [_time - t0, lion.state_name(), lion.hp, lion.phase,
				hero.state_name(), hero.hp, Combat.flat(lion.global_position - hero.global_position).length(), _mode,
				str((lion.global_position - c).snapped(Vector3.ONE * 0.1)), str((hero.global_position - c).snapped(Vector3.ONE * 0.1))])
	hero.debug_move = Vector2.ZERO
	hero.inp.bot_clear()
	var won := not is_instance_valid(lion) or not lion.alive
	var deaths := _deaths - deaths0
	for ph in range(phase_seen + 1, 3):
		print("LION fight %s phase%d FAIL not reached (t=%.1f s)" % [case, ph, _time - t0])
	print("LION fight %s phase3 %s t=%.1f s (%.1f s) deaths=%d wrestles_won=%d lost=%d slams pounce=%d yank=%d fall=%d hero_hp=%.0f" % [case,
		"PASS" if won else "FAIL", _time - t0, _time - phase_t, deaths, _st_won, _st_lost, _st_pounce, _st_yank, _st_fall, hero.hp])
	print("LION fight %s wrestle view: hero hidden %d%% / partly %d%% of %d frames (by head %d, body %d; camera offsets %s)" % [case,
		100 * _view_hidden / maxi(1, _view_frames), 100 * _view_part / maxi(1, _view_frames), _view_frames, _view_by_head, _view_by_body,
		str(_view_offs)])
	var esc_ok := escaped_seen and ambush_seen if not sealed else not escaped_seen
	print("LION fight %s escape_rule %s mouth_b_open=%s escaped=%s ambushed=%s" % [case, "PASS" if esc_ok else "FAIL", str(b_open), str(escaped_seen), str(ambush_seen)])
	var pelt: bool = await _until(func() -> bool: return hero.outfit == &"lion", 10.0) if won else false
	var ok := won and deaths == 0 and esc_ok and pelt
	return _result("fight_" + case, ok, "won=%s in %.0f s deaths=%d escape_rule=%s pelt=%s" % [str(won), _time - t0, deaths, str(esc_ok), str(pelt)])


var _stall_hp := -1.0
var _stall_ph := -1
var _stall_t := 0.0
var _stall_log := 0.0
var _st_won := 0
var _st_lost := 0
var _st_pounce := 0
var _st_yank := 0
var _st_fall := 0


# The fight bot: reads the lion like a player reads its telegraphs. Two plans, switched every ~15 s and at each
# phase: "bait" (stand in front of a pillar, roll aside as the pounce leaves the ground: it flies on into the stone)
# and "yank" (find a spot from which the chain draws it into a pillar beside it, and pull).
var _mode := ""
var _plan := "bait"
var _plan_t := 0.0
var _rolled_for := -1
var _pounce_id := 0
var _last_state := -1
var _throw_cd := 0.0
var _spot_t := 0.0
var _yank_at := Vector3.INF


func _bot_reset() -> void:
	_mode = ""
	_plan = "bait"
	_plan_t = 0.0
	_rolled_for = -1
	_pounce_id = 0
	_last_state = -1
	_throw_cd = 0.0
	_spot_t = 0.0
	_yank_at = Vector3.INF


func _bot_tick() -> void:
	var dt := get_physics_process_delta_time()
	_throw_cd -= dt
	_plan_t += dt
	if not hero.is_alive():
		_mode = "dead"
		hero.debug_move = Vector2.ZERO
		await get_tree().physics_frame
		return
	if lion.state != _last_state:
		if lion.state == Lion.S.POUNCE:
			_pounce_id += 1
		_last_state = lion.state
	if hero.is_grappling():
		_mode = "wrestle"
		await _wrestle(true)
		# a fresh plan after each wrestle, now and then the other one
		_plan_t = 0.0
		if randf() < 0.5:
			_plan = "yank" if _plan == "bait" else "bait"
		return
	if _plan_t > 15.0:
		_plan_t = 0.0
		_plan = "yank" if _plan == "bait" else "bait"
	var L := lion.global_position
	var H := hero.global_position
	var to_l := Combat.flat(L - H)
	var d := to_l.length()
	match lion.state:
		Lion.S.STUNNED:
			_mode = "grab"
			if lion.can_grapple(hero):
				await _grab(3.0)
				return
		Lion.S.POUNCE:
			_mode = "pounce"
			var pp := lion.pounce_phase()
			var wind_end := pp == Lion.P.WIND and lion.telegraph_left() < (0.12 if lion._short else 0.05)
			if (pp == Lion.P.AIR or wind_end) and _rolled_for != _pounce_id and d < 16.0:
				_rolled_for = _pounce_id
				await _roll(_dodge_side(L, H))
				return
			if pp == Lion.P.WIND:
				hero.debug_move = Vector2.ZERO
				await get_tree().physics_frame
				return
		Lion.S.SWIPE, Lion.S.BITE:
			_mode = "strike"
			if d < 5.0 and lion.telegraph_left() < 0.3 and lion.telegraph_left() > 0.0:
				await _roll(-to_l.normalized() if d > 0.1 else -lion.forward())
				return
		Lion.S.ROAR:
			_mode = "roar"
			if d < 9.0 and lion.telegraph_left() < 0.22 and lion.telegraph_left() > 0.0:
				await _roll(-to_l.normalized() if d > 0.1 else Vector3.BACK)
				return
		Lion.S.PERCHED:
			_mode = "perched"
			if _throw_cd <= 0.0 and d < 16.0:
				_throw_cd = 1.5
				if await _throw_at_lion(0.15):
					return
		Lion.S.ESCAPE:
			# (let it go: the test wants the ambush; a yank that hauls it back would end the escape, the lion turning on him)
			if not lion._escape_strike:
				_mode = "let_go"
				hero.debug_move = _stick_to(_c() + Vector3(0, 0, 2.0)) if Combat.flat(_c() - H).length() > 3.0 else Vector2.ZERO
				await get_tree().physics_frame
				return
		Lion.S.AWAY:
			_mode = "away"
			hero.debug_move = _stick_to(_c() + Vector3(0, 0, 2.0)) if Combat.flat(_c() - H).length() > 3.0 else Vector2.ZERO
			await get_tree().physics_frame
			return
	# a yank into a pillar right now (whatever the plan, if it lines up)
	if _throw_cd <= 0.0 and _yank_chance():
		_throw_cd = 2.0
		_mode = "yank"
		if await _throw_at_lion(0.12):
			return
	var spot := H
	if _plan == "yank" and lion.state in [Lion.S.PROWL, Lion.S.RECOVER, Lion.S.DOWNED]:
		_mode = "yank_hunt"
		_spot_t -= dt
		if _spot_t <= 0.0:
			_spot_t = 0.25
			_yank_at = _yank_spot(L)
		spot = _yank_at if _yank_at != Vector3.INF else _bait_spot(L)
	else:
		# a pillar right behind him as the lion sees him (bait its pounce into it), not too close to it
		_mode = "bait"
		spot = _bait_spot(L)
	if d < 4.0 and lion.state == Lion.S.PROWL:
		# too close: step away (it swipes here)
		spot = H - to_l.normalized() * 3.0
	var gap := Combat.flat(spot - H).length()
	hero.debug_move = _stick_to(spot) if gap > 0.35 else Vector2.ZERO
	await get_tree().physics_frame


## Where the chain draws the lion into a pillar beside it (COMBAT.md 6.5): a pillar whose face is 0.3-3 m from the
## lion's body, and the hero 8-11 m away on a line 12-20 degrees off it (the spear flies past the pillar, the slide
## bends into it), inside the arena, nearest to him. Vector3.INF when there is none.
func _yank_spot(L: Vector3) -> Vector3:
	var ps: Array = cave["pillars"]
	var H := hero.global_position
	var c := _c()
	var best := Vector3.INF
	var best_s := INF
	var space := hero.get_world_3d().direct_space_state
	for i in ps.size():
		var P: Vector3 = ps[i]
		var to_p := Combat.flat(P - L)
		var surf := to_p.length() - _pillar_r(i) - 0.55
		if surf < 0.3 or surf > 3.0:
			continue
		var u := to_p.normalized()
		for sgn in [1.0, -1.0]:
			for ang in [16.0, 20.0, 12.0]:
				var w := u.rotated(Vector3.UP, deg_to_rad(ang) * sgn)
				var off := to_p.length() * sin(deg_to_rad(ang))
				if off < _pillar_r(i, 1.2) + 0.3:
					continue
				for dist in [9.5, 8.0, 11.0]:
					var S: Vector3 = L + w * float(dist)
					if Combat.flat(S - c).length() > 11.5:
						continue
					var q := PhysicsRayQueryParameters3D.create(_ground(S) + Vector3(0, 1.5, 0), lion.chain_point(), 1 | 8)
					if not space.intersect_ray(q).is_empty():
						continue
					var sc := Combat.flat(S - H).length()
					if sc < best_s:
						best_s = sc
						best = _ground(S)
					break
	return best


## Roll perpendicular to the lion's line, to the side with more room.
func _dodge_side(L: Vector3, H: Vector3) -> Vector3:
	var u := Combat.flat(H - L).normalized()
	var side := Vector3(-u.z, 0, u.x)
	var space := hero.get_world_3d().direct_space_state
	var best := side
	var best_room := -1.0
	for s in [side, -side]:
		var q := PhysicsRayQueryParameters3D.create(H + Vector3(0, 0.8, 0), H + Vector3(0, 0.8, 0) + s * 4.5, 1 | 8, [hero.get_rid()])
		var hit := space.intersect_ray(q)
		var room := 4.5 if hit.is_empty() else H.distance_to(hit["position"])
		if room > best_room + 0.3:
			best_room = room
			best = s
	return best


## Where to stand: in front of the pillar whose far side is in line with the lion (the lion, the hero and the
## pillar in a row, the pillar 2.3 m behind him), the nearest such spot that keeps the lion 6-12 m away.
func _bait_spot(L: Vector3) -> Vector3:
	var ps: Array = cave["pillars"]
	var H := hero.global_position
	var best := H
	var best_s := INF
	for i in ps.size():
		var P: Vector3 = ps[i]
		var u := Combat.flat(L - P)
		var dl := u.length()
		if dl < 7.0:
			continue
		u = u.normalized()
		var S := P + u * (_pillar_r(i) + 1.3)
		var ld := Combat.flat(L - S).length()
		if ld < 5.5 or ld > 13.0:
			continue
		var s := Combat.flat(S - H).length() + absf(ld - 8.0) * 0.3
		if s < best_s:
			best_s = s
			best = S
	if best_s == INF:
		# none: towards the middle of the arena
		best = _c() + Combat.flat(H - _c()).limit_length(3.0)
	return best


## A pillar near the lion, within ~22 degrees of the line from it to the hero (COMBAT.md 6.5): yank it there.
func _yank_chance() -> bool:
	if not (lion.state in [Lion.S.PROWL, Lion.S.RECOVER]) or lion.is_sliding():
		return false
	var L := lion.global_position
	var H := hero.global_position
	var to_h := Combat.flat(H - L)
	if to_h.length() < 6.0 or to_h.length() > 18.0:
		return false
	var ps: Array = cave["pillars"]
	for i in ps.size():
		var P: Vector3 = ps[i]
		var to_p := Combat.flat(P - L)
		var surf := to_p.length() - _pillar_r(i) - 0.55
		if surf > 3.2 or surf < 0.2:
			continue
		var ang := rad_to_deg(to_p.angle_to(to_h))
		# far enough off the line for the spear to pass the pillar, close enough for the slide to bend into it
		var off := to_p.length() * sin(deg_to_rad(ang))
		if ang < 24.0 and off > _pillar_r(i, 1.2) + 0.25:
			return true
	return false
