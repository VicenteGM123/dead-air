extends Node
## ENCOUNTERS (lane P) bot: the real hero against the real wolves and boars of Nemea (tools/encounters.tscn), played
## through the hero's real input path (HeroInput.bot virtual buttons, Hero.debug_move, the camera aiming the chain
## spear, the lock-on). One line per test, then a summary:
##   ENC test <name> PASS|FAIL <details>
##   ENC autotest passed=N/M result=PASS|FAIL
## Tests (encbot=all, or a list: encbot=yank,parry):
##   yank        the forest pack (3 wolves) circling him: the chain spear hooks one, it is yanked to land staggered
##               in front of him
##   parry       a wolf's lunge parried (guard pressed as its telegraph runs out): no damage, the wolf thrown back
##               and staggered (on_parried)
##   leash       the pack hunting him: he sprints away; past 35 m from home the pack gives up, trots home and heals
##   death       the hero falls with the pack round him (one wolf hurt): at his respawn every wolf is back at its home
##               spot with full health, the pack idle
##   pack3       the forest pack of 3 beaten with the combo and the roll (rolls when a wolf's wind-up runs out, then
##               punishes it while it recovers): all three dead, the hero alive
##   boar_parry  a boar's charge parried as the tusks arrive: the charge breaks, the boar staggered
##   boar_block  the shield held up (not a timed parry) against a boar's charge: no damage, much stamina gone, the
##               hero shoved back, the charge stopped
##   boar_yank   a boar winding up its charge hooked by the chain spear: the wind-up broken (no charge follows), the
##               boar dragged towards him and turned to face him
##   boar_crash  in front of a rock: the boar winds up and charges, he rolls aside at the last moment, the boar
##               slams into the rock (stunned) and is cut down (as many charges as it takes)
##   clip        every physics frame of a fight with a pack of 3, the 5-wolf pack hunting him and a boar crashed
##               into a rock and cut down: no beast part (muzzle, head, chest, hips, paws, tusks) inside the hero's
##               capsule (by more than 12 cm), another beast's body (15 cm), a rock, a trunk or a wall (a collider
##               may be grazed, by a paw 6 cm, by another part 3 cm, in 0.2 % of the samples at most), or the ground
##               (12 cm)
##   clip_trunk  the same checks with the 5-wolf pack hunting him beside a big trunk (its ring runs through it)
##   balance     (also in `all`) fresh packs on an open meadow, balance_n=N times (default 4): a careless hero
##               against 5 (runs at them mashing the attack, never guards or rolls) must lose at least half the runs
##               (it loses about 4 in 5);
##               a skilled one against 5 (rolls the lunges, punishes the openings) must win every run, with at least
##               40 hp left in 2 runs in 3. balance_set=c5,s5,c3 (default; g = the guard policy: mashes, but raises
##               the shield when a wolf winds up at him) picks the fights, balance_only=skilled only the skilled ones
## Debug: botdebug=1 traces the fights. "ENC mark <tag> frame=<n>" lines give the movie frames for strips;
## fastpre=1 (renders) runs each test's set-up at 4x and drops to real time at its mark.
##   godot --headless --path . res://tools/encounters.tscn --fixed-fps 60 --quit-after 60000 -- encbot=all quit=1

const ALL := ["yank", "parry", "leash", "death", "pack3", "boar_parry", "boar_block", "boar_yank", "boar_crash", "clip",
	"clip_trunk", "balance"]
## Where the hero waits for the forest pack (on the main road, north-east of it) and for the boars.
const PACK1 := Vector3(-24.0, 0.0, 14.0)
const BOAR1 := Vector3(-104.0, 0.0, -47.0)
const HERD := Vector3(-78.0, 0.0, -72.0)
## An open meadow for the balance pack (the south meadows, away from the others). FINAL: moved from (-48, 46), where the
## wheat field's farm now has its dry-stone wall (the pack's fight there put paws into the wall), to the meadow
## south-west of the field: no collider within 9 m of it or of the hero's spot 12 m south, gentle slopes.
const BALANCE_AT := Vector3(-58.0, 0.0, 64.0)

var main: Node = null
var hero: Hero
var cam: CameraRig
var world
var _time := 0.0
var _passed := 0
var _total := 0
var _cur := ""
var _debug := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_debug = Game.arg_on("botdebug")
	_rng.seed = 1234
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta


func _run() -> void:
	if Game.arg_on("fastpre"):
		Game.time_scale_target = 4.0 # renders: the set-up of each test runs fast (until its mark)
	for i in 30:
		await get_tree().physics_frame
	hero = main.get("hero")
	cam = main.get("cam")
	world = main.get("world")
	var list: Array = ALL
	var a := String(Game.arg("encbot", "all"))
	if a != "1" and a != "all":
		list = Array(a.split(",", false))
	for t in list:
		_cur = String(t)
		if Game.arg_on("fastpre"):
			Game.time_scale_target = 4.0
		var ok: bool = await _run_test(String(t))
		_total += 1
		if ok:
			_passed += 1
		hero.inp.bot_clear()
		hero.debug_move = Vector2.ZERO
		await _wait(0.5)
	print("ENC autotest passed=%d/%d result=%s" % [_passed, _total, "PASS" if _passed == _total else "FAIL"])
	if Game.arg_on("quit"):
		get_tree().quit()


func _run_test(t: String) -> bool:
	match t:
		"yank":
			return await _t_yank()
		"parry":
			return await _t_parry()
		"leash":
			return await _t_leash()
		"death":
			return await _t_death()
		"pack3":
			return await _t_pack3()
		"boar_parry":
			return await _t_boar_parry()
		"boar_crash":
			return await _t_boar_crash()
		"boar_yank":
			return await _t_boar_yank()
		"boar_block":
			return await _t_boar_block()
		"balance":
			return await _t_balance()
		"watch":
			return await _t_watch()
		"clip":
			return await _t_clip()
		"clip_trunk":
			return await _t_clip_trunk()
		"r_wolf":
			return await _r_wolf()
		"r_ring":
			return await _r_ring()
		"r_boar":
			return await _r_boar()
		"r_road":
			return await _r_road()
		"r_clearing":
			return await _r_clearing()
	print("ENC test %s FAIL unknown test" % t)
	return false


# --- helpers ---------------------------------------------------------------------------------------------------

func _result(nm: String, ok: bool, details: String) -> bool:
	print("ENC test %s %s %s" % [nm, "PASS" if ok else "FAIL", details])
	return ok


func _mark(tag: String) -> void:
	if Game.arg_on("fastpre"):
		Game.time_scale_target = 1.0 # renders: real time from the moment that matters
	print("ENC mark %s frame=%d t=%.2f" % [tag, Engine.get_frames_drawn(), _time])


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


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, float(world.call("height_at", p.x, p.z)), p.z)


## The hero at `p` (on the ground) facing `look`, alive, healthy, rested, the camera behind him.
func _place(p: Vector3, look: Vector3) -> void:
	var g := _ground(p)
	var d := Combat.flat(look - g).normalized()
	var z := -d
	var x := Vector3.UP.cross(z).normalized()
	var xf := Transform3D(Basis(x, Vector3.UP, z), g + Vector3(0, 0.05, 0))
	if hero.state != Hero.St.MOVE or not hero.is_alive():
		hero.revive(xf)
	else:
		hero.teleport(xf)
	hero.stamina = hero.max_stamina
	hero.exhausted = false
	hero.hp = hero.max_hp
	hero.invulnerable = 0.0
	cam.lock_on(null)
	cam.follow(hero, true)
	await _wait(0.3)


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


## The pack of `kind` whose home is nearest `p`.
func _pack_at(p: Vector3, kind: StringName) -> BeastPack:
	var best: BeastPack = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("beast_pack"):
		var bp := n as BeastPack
		if bp == null or bp.kind != kind:
			continue
		var d := Combat.flat(bp.home - p).length()
		if d < bd:
			bd = d
			best = bp
	return best


func _alive(arr: Array) -> Array:
	var out: Array = []
	for e in arr:
		if Combat.is_alive(e):
			out.append(e)
	return out


## Walks up to the pack until it notices him (HUNT).
func _provoke(pk: BeastPack, timeout: float = 8.0) -> bool:
	var t0 := _time
	while _time - t0 < timeout:
		if pk.state == BeastPack.HUNT:
			hero.debug_move = Vector2.ZERO
			return true
		if Combat.flat(pk.home - hero.global_position).length() > 9.0:
			hero.debug_move = _stick_to(pk.home) * 0.5 # walking
		else:
			hero.debug_move = Vector2.ZERO
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	return pk.state == BeastPack.HUNT


## A pack back at home, healthy and idle (after a fight, a leash or a reset), waiting at most `timeout` s.
func _settle(pk: BeastPack, timeout: float) -> bool:
	return await _until(func() -> bool: return _settled(pk), timeout)


func _settled(pk: BeastPack) -> bool:
	if pk.state != BeastPack.IDLE:
		return false
	for m in pk.alive_members():
		var e := m as Enemy
		# home: idle again, wandering round its spot (within its 4 m wander radius)
		if e.hp < e.max_hp or Combat.flat(e.get("home_spot") - e.global_position).length() > 4.6:
			return false
	return true


## Puts a pack back to rest (full health, home) by hand: only between tests, never inside one.
func _reset_pack(pk: BeastPack) -> void:
	if pk == null:
		return
	pk._do_reset()
	await _wait(0.2)


# --- the fighting policy -----------------------------------------------------------------------------------------

## Fights the beasts in `foes` until they are dead, the hero is dead or `timeout`. careless: runs at the nearest
## mashing the attack (no guard, no roll). Else skilled: rolls aside as a wind-up runs out (wolves: 0.30 s before the
## bite; boars: as the charge arrives), punishes whatever recovers, is staggered or lands in front of him with the
## combo, never chases a wolf round the ring.
func _fight(foes: Array, timeout: float, careless: bool, guard: bool = false) -> Dictionary:
	var stats := {"won": false, "time": 0.0, "hp": 0.0, "rolls": 0, "perfect": 0, "blows": 0, "bites": 0, "hurt_taken": 0.0}
	var hp0 := hero.hp
	var perfect := [0]
	var cb_p := func() -> void: perfect[0] += 1
	hero.perfect_dodge.connect(cb_p)
	var hurt := [0]
	var cb_h := func(_h: Dictionary) -> void: hurt[0] += 1
	hero.hurt.connect(cb_h)
	var t0 := _time
	var roll_cd := 0.0
	var atk_cd := 0.0
	var trace_t := 0.0
	while _time - t0 < timeout:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		roll_cd -= dt
		atk_cd -= dt
		var alive := _alive(foes)
		if alive.is_empty():
			stats["won"] = true
			break
		if not hero.is_alive():
			break
		var hp_ := hero.global_position
		# the nearest foe
		var near: Node3D = null
		var nd := INF
		for e in alive:
			var d := Combat.flat((e as Node3D).global_position - hp_).length()
			if d < nd:
				nd = d
				near = e
		if _debug:
			trace_t -= dt
			if trace_t <= 0.0:
				trace_t = 0.5
				var s := ""
				for e in alive:
					var ex := ""
					if e is Wolf:
						ex = " ev%d hp%.0f" % [(e as Wolf).evades, (e as Wolf).hp]
					s += " %s:%s(%.1f%s)" % [e.name.right(4), String(e.call("state_name")), Combat.flat((e as Node3D).global_position - hp_).length(), ex]
				print("ENC fight t=%.1f hp=%.0f st=%.0f hero=%s%s" % [_time - t0, hero.hp, hero.stamina, String(hero.state_name()), s])
		if careless and guard:
			# the shield up while a beast winds up at him or leaps (the guard turns him to a threat in view)
			var danger := false
			for e in alive:
				var de := Combat.flat((e as Node3D).global_position - hp_).length()
				if e is Wolf and de < 7.0 and ((e as Wolf).st == Wolf.WINDUP or ((e as Wolf).st == Wolf.LUNGE and not (e as Wolf)._bit)):
					danger = true
				elif e is Boar and de < 14.0 and (e as Boar).st in [Boar.WINDUP, Boar.CHARGE, Boar.GORE]:
					danger = true
			hero.inp.bot[&"guard"] = danger
			if danger:
				hero.inp.bot[&"attack"] = false
				hero.debug_move = Vector2.ZERO
				continue
		if careless:
			if nd > 1.9:
				hero.debug_move = _stick_to(near.global_position)
			else:
				hero.debug_move = Vector2.ZERO
			if atk_cd <= 0.0 and nd < 3.2:
				atk_cd = 0.1
				hero.inp.bot[&"attack"] = not hero.inp.bot[&"attack"]
			continue
		# skilled: 1) the attack that is about to land
		var threat: Node3D = null
		for e in alive:
			if e is Wolf:
				var w := e as Wolf
				if w.st == Wolf.WINDUP and w.telegraph_left() <= 0.3 and w.telegraph_left() > 0.0:
					threat = w
			elif e is Boar:
				var b := e as Boar
				if b.st == Boar.CHARGE and not b._ch_resolved:
					var d2 := Combat.flat(hp_ - b.global_position)
					var along := d2.dot(b._ch_dir)
					var lat := (d2 - b._ch_dir * along).length()
					if along > 0.0 and lat < 1.3 and (along - 0.36 - Boar.HIT_REACH) / maxf(b._ch_speed, 1.0) < 0.3:
						threat = b
				elif b.st == Boar.GORE and b.telegraph_left() <= 0.3 and b.telegraph_left() > 0.0:
					threat = b
		if threat != null and roll_cd <= 0.0 and hero.state != Hero.St.DODGE and hero.stamina >= 22.0:
			var away := Combat.flat(hp_ - threat.global_position).normalized()
			var side := Vector3(-away.z, 0.0, away.x)
			# roll to the side with fewer foes
			var s_left := 0.0
			for e in alive:
				if e != threat:
					s_left += signf(side.dot(Combat.flat((e as Node3D).global_position - hp_)))
			if s_left > 0.0:
				side = -side
			hero.inp.bot[&"attack"] = false
			hero.debug_move = _stick_to(hp_ + side * 3.0)
			await _tap(&"dodge", 0.04)
			stats["rolls"] += 1
			roll_cd = 0.5
			if _debug:
				print("ENC fight roll from %s at t=%.2f" % [threat.name, _time - t0])
			continue
		# 2) something to punish: recovering, staggered, stunned, yanked or simply in reach while not winding up
		var prey: Node3D = null
		var pd := INF
		for e in alive:
			var en := e as Enemy
			var d3 := Combat.flat(en.global_position - hp_).length()
			var open := en.stagger > 0.0 or en.is_stunned() or en.is_yanked()
			if e is Wolf:
				open = open or (e as Wolf).st in [Wolf.RECOVER, Wolf.BACKOFF]
			elif e is Boar:
				open = open or (e as Boar).st in [Boar.RECOVER, Boar.SKID]
			var reach := 5.0 if open else 2.2
			if d3 < reach and d3 < pd and not (e is Boar and (e as Boar).st == Boar.WINDUP and d3 > 2.0):
				pd = d3
				prey = e
		if prey != null and hero.state != Hero.St.DODGE:
			if pd > 2.1:
				hero.debug_move = _stick_to(prey.global_position)
			else:
				hero.debug_move = _stick_to(prey.global_position) * 0.3
			if atk_cd <= 0.0 and pd < 3.0:
				atk_cd = 0.1
				hero.inp.bot[&"attack"] = not hero.inp.bot[&"attack"]
				if hero.inp.bot[&"attack"]:
					stats["blows"] += 1
			continue
		hero.inp.bot[&"attack"] = false
		# 3) nothing to do: hold the ground, face the nearest
		hero.debug_move = Vector2.ZERO
	hero.inp.bot_clear()
	hero.debug_move = Vector2.ZERO
	hero.perfect_dodge.disconnect(cb_p)
	hero.hurt.disconnect(cb_h)
	stats["time"] = _time - t0
	stats["hp"] = hero.hp
	stats["perfect"] = perfect[0]
	stats["bites"] = hurt[0]
	stats["hurt_taken"] = hp0 - hero.hp
	return stats


# --- tests -------------------------------------------------------------------------------------------------------

func _t_yank() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	if pk == null:
		return _result("yank", false, "no forest pack")
	await _reset_pack(pk)
	await _place(pk.home + Vector3(6.0, 0, 16.0), pk.home)
	var hunted := await _provoke(pk)
	# a wolf of the ring, 4-9 m away, in sight
	var target: Wolf = null
	var t0 := _time
	while _time - t0 < 6.0 and target == null:
		await get_tree().physics_frame
		for m in pk.alive_members():
			var w := m as Wolf
			var d := Combat.flat(w.global_position - hero.global_position).length()
			if w.st == Wolf.CIRCLE and d > 4.0 and d < 9.0 and w.stagger <= 0.0:
				target = w
				break
	if target == null:
		return _result("yank", false, "hunted=%s no wolf in the ring" % str(hunted))
	var cand := false
	for i in 20:
		cam.aim_at(target.chain_point())
		await get_tree().physics_frame
		if hero.chain_candidate == target:
			cand = true
			break
	_mark("yank")
	await _tap(&"chain")
	var yanked: bool = await _until(func() -> bool: return target.is_yanked(), 1.5)
	var landed: bool = await _until(func() -> bool: return not target.is_yanked(), 1.5)
	var d := Combat.flat(target.global_position - hero.global_position)
	var in_front := d.length() > 0.1 and d.normalized().dot(hero.forward()) > 0.6
	var staggered := target.stagger > 0.3
	await _wait(0.6)
	var ok := hunted and cand and yanked and landed and d.length() < 2.9 and in_front and staggered
	return _result("yank", ok, "hunted=%s candidate=%s yanked=%s landed=%s dist=%.2f in_front=%s staggered=%s" % [str(hunted),
		str(cand), str(yanked), str(landed), d.length(), str(in_front), str(staggered)])


func _t_parry() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	await _reset_pack(pk)
	await _place(pk.home + Vector3(6.0, 0, 16.0), pk.home)
	var hunted := await _provoke(pk)
	var parried_by := [null]
	var cb := func(src: Node) -> void: parried_by[0] = src
	hero.parried.connect(cb)
	var hp0 := hero.hp
	var attacker: Wolf = null
	var pressed := false
	var t0 := _time
	_mark("parry")
	while _time - t0 < 14.0 and parried_by[0] == null:
		await get_tree().physics_frame
		if attacker == null:
			for m in pk.alive_members():
				var w := m as Wolf
				if w.st == Wolf.WINDUP:
					attacker = w
					cam.lock_on(w)
					break
			continue
		if attacker.st != Wolf.WINDUP and attacker.st != Wolf.LUNGE:
			# interrupted or over without our parry: wait for the next one
			hero.inp.bot[&"guard"] = false
			attacker = null
			pressed = false
			await _wait(0.45)
			continue
		if not pressed and attacker.telegraph_left() <= 0.1:
			pressed = true
			hero.inp.bot[&"guard"] = true
	var w2: Wolf = parried_by[0] as Wolf
	await _wait(0.12)
	var staggered := w2 != null and w2.stagger > 0.6
	var anim := String((w2.rig as RigWolf).action) if w2 != null else ""
	await _wait(0.5)
	hero.inp.bot[&"guard"] = false
	hero.parried.disconnect(cb)
	cam.lock_on(null)
	var ok := hunted and w2 != null and staggered and anim == "stagger" and hero.hp == hp0
	return _result("parry", ok, "hunted=%s parried=%s staggered=%s anim=%s hp %.0f->%.0f" % [str(hunted),
		w2.name if w2 else "none", str(staggered), anim, hp0, hero.hp])


func _t_leash() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	await _reset_pack(pk)
	await _place(pk.home + Vector3(6.0, 0, 16.0), pk.home)
	var hunted := await _provoke(pk)
	var hurt_w := pk.alive_members()[0] as Wolf
	hurt_w.hp = hurt_w.max_hp - 14.0 # (a wound to heal on the way home)
	await _wait(1.0)
	# sprint away along the road to the north gate, until 42 m from home
	var away := Vector3(-4.0, 0.0, 54.0)
	_mark("leash")
	hero.inp.bot[&"sprint"] = true
	var gave_up := false
	var t0 := _time
	while _time - t0 < 16.0:
		await get_tree().physics_frame
		hero.debug_move = _stick_to(away) if Combat.flat(pk.home - hero.global_position).length() < 44.0 else Vector2.ZERO
		if pk.state == BeastPack.RETURN:
			gave_up = true
		if gave_up and hero.debug_move == Vector2.ZERO:
			break
	hero.inp.bot[&"sprint"] = false
	hero.debug_move = Vector2.ZERO
	var dist := Combat.flat(pk.home - hero.global_position).length()
	if _debug:
		for i in 22:
			var line := "ENC leash t=%d" % i
			for m in pk.alive_members():
				var w := m as Wolf
				line += " %s:%s(%.1f m, det %d, v %.1f)" % [w.name.right(4), w.state_name(), Combat.flat(w.home_spot - w.global_position).length(),
					w.nav.detours, Vector2(w.velocity.x, w.velocity.z).length()]
			print(line)
			await _wait(1.0)
	var home: bool = await _settle(pk, 20.0)
	if not home:
		for m in pk.alive_members():
			var w := m as Wolf
			print("ENC leash wolf %s st=%s from_home=%.2f hp=%.0f/%.0f pos=%s vel=%s" % [w.name, w.state_name(),
				Combat.flat(w.home_spot - w.global_position).length(), w.hp, w.max_hp, str(w.global_position), str(w.velocity)])
		print("ENC leash pack state=%s" % pk.state_name())
	var healed := hurt_w.hp >= hurt_w.max_hp
	var ok := hunted and gave_up and home and healed and hero.is_alive()
	return _result("leash", ok, "hunted=%s gave_up=%s hero_from_home=%.1f home_idle=%s healed=%s hero_hp=%.0f" % [str(hunted),
		str(gave_up), dist, str(home), str(healed), hero.hp])


func _t_death() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	await _reset_pack(pk)
	await _place(pk.home + Vector3(6.0, 0, 16.0), pk.home)
	var hunted := await _provoke(pk)
	await _wait(1.5)
	var hurt_w := pk.alive_members()[0] as Wolf
	hurt_w.hp = hurt_w.max_hp * 0.5
	var spots: Array = []
	for m in pk.alive_members():
		spots.append((m as Node3D).global_position)
	_mark("death")
	# felled where he stands (the blow of a wolf)
	hero.take_hit(Combat.make_hit(999.0, &"blunt", Vector3.FORWARD, 3.0, 0.6, hurt_w))
	var dead := not hero.is_alive()
	var back: bool = await _until(func() -> bool: return hero.is_alive() and Game.phase == Game.Phase.PLAY, 8.0)
	await _wait(0.3)
	var all_home := true
	var full := true
	var idle := pk.state == BeastPack.IDLE
	for m in pk.alive_members():
		var w := m as Wolf
		if Combat.flat(w.home_spot - w.global_position).length() > 1.0 or w.st != Wolf.IDLE:
			all_home = false
		if w.hp < w.max_hp:
			full = false
	var ok := hunted and dead and back and all_home and full and idle and pk.alive_count() == 3
	return _result("death", ok, "hunted=%s dead=%s respawned=%s wolves_home=%s full_hp=%s pack_idle=%s alive=%d" % [str(hunted),
		str(dead), str(back), str(all_home), str(full), str(idle), pk.alive_count()])


func _t_pack3() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	await _reset_pack(pk)
	# along the road from the north gate, as a player comes
	await _place(Vector3(-14.0, 0, 33.0), pk.home)
	_mark("pack3")
	var hunted := await _provoke(pk, 10.0)
	var foes := pk.alive_members()
	var n0 := foes.size()
	var st := await _fight(foes, 90.0, false)
	var ok := hunted and n0 == 3 and bool(st["won"]) and hero.is_alive()
	return _result("pack3", ok, "hunted=%s wolves=%d won=%s time=%.1fs hero_hp=%.0f bitten=%d rolls=%d perfect_dodges=%d presses=%d attacks=%d" % [
		str(hunted), n0, str(st["won"]), float(st["time"]), float(st["hp"]), int(st["bites"]), int(st["rolls"]),
		int(st["perfect"]), int(st["blows"]), pk.attacks])


func _boar_of(pk: BeastPack) -> Boar:
	for m in pk.alive_members():
		return m as Boar
	return null


func _t_boar_parry() -> bool:
	var pk := _pack_at(HERD, &"boar")
	if pk == null:
		return _result("boar_parry", false, "no herd")
	await _reset_pack(pk)
	var b := _boar_of(pk)
	# in the open, 10 m from it, the line clear
	var spot := _open_spot(b.global_position, 9.5)
	await _place(spot, b.global_position)
	var parried_by := [null]
	var cb := func(src: Node) -> void: parried_by[0] = src
	hero.parried.connect(cb)
	var hp0 := hero.hp
	var pressed := false
	var charger: Boar = null
	var t0 := _time
	_mark("boar_parry")
	while _time - t0 < 16.0 and parried_by[0] == null and hero.is_alive():
		await get_tree().physics_frame
		if charger == null:
			for m in pk.alive_members():
				if (m as Boar).st == Boar.WINDUP:
					charger = m as Boar
					cam.lock_on(charger)
			continue
		if charger.st != Boar.CHARGE and charger.st != Boar.WINDUP:
			hero.inp.bot[&"guard"] = false
			charger = null
			pressed = false
			continue
		if charger.st == Boar.CHARGE and not pressed:
			var d := Combat.flat(hero.global_position - charger.global_position)
			var along := d.dot(charger._ch_dir)
			var ttc := (along - 0.36 - Boar.HIT_REACH) / maxf(charger._ch_speed, 1.0)
			if ttc <= 0.09:
				pressed = true
				hero.inp.bot[&"guard"] = true
	var pb: Boar = parried_by[0] as Boar
	await _wait(0.15)
	var staggered := pb != null and pb.stagger > 1.0
	var stopped := pb != null and pb.st != Boar.CHARGE
	var anim := String((pb.rig as RigBoar).action) if pb != null else ""
	await _wait(0.4)
	hero.inp.bot[&"guard"] = false
	hero.parried.disconnect(cb)
	cam.lock_on(null)
	var ok := pb != null and staggered and stopped and anim == "stagger" and hero.hp == hp0
	return _result("boar_parry", ok, "parried=%s staggered=%s charge_broken=%s anim=%s hp %.0f->%.0f result=%s" % [
		pb.name if pb else "none", str(staggered), str(stopped), anim, hp0, hero.hp, pb.last_charge_result if pb else &""])


func _t_boar_block() -> bool:
	var pk := _pack_at(HERD, &"boar")
	if pk == null:
		return _result("boar_block", false, "no herd")
	await _reset_pack(pk)
	var b0 := _boar_of(pk)
	await _place(_open_spot(b0.global_position, 10.0), b0.global_position)
	var b: Boar = null
	var t0 := _time
	while _time - t0 < 12.0 and b == null:
		await get_tree().physics_frame
		for m in pk.alive_members():
			if (m as Boar).st == Boar.WINDUP:
				b = m as Boar
	if b == null:
		return _result("boar_block", false, "no wind-up")
	cam.lock_on(b)
	# the shield up early (the parry window long gone when the tusks arrive)
	hero.inp.bot[&"guard"] = true
	var hp0 := hero.hp
	var st0 := hero.stamina
	_mark("boar_block")
	var res: bool = await _until(func() -> bool: return b.last_charge_result != &"", 6.0)
	var at := hero.global_position
	var min_st := hero.stamina
	var tt := _time
	while _time - tt < 0.6:
		min_st = minf(min_st, hero.stamina)
		await get_tree().physics_frame
	var pushed := Combat.flat(hero.global_position - at).length()
	hero.inp.bot[&"guard"] = false
	cam.lock_on(null)
	var blocked := b.last_charge_result == &"blocked"
	var ok := res and blocked and hero.hp == hp0 and st0 - min_st >= 30.0 and pushed >= 0.4 and b.st != Boar.CHARGE
	await _wait(0.3)
	return _result("boar_block", ok, "result=%s hp %.0f->%.0f stamina %.0f->%.0f pushed=%.2f m boar=%s" % [String(b.last_charge_result),
		hp0, hero.hp, st0, min_st, pushed, b.state_name()])


func _t_boar_yank() -> bool:
	var pk := _pack_at(HERD, &"boar")
	if pk == null:
		return _result("boar_yank", false, "no herd")
	await _reset_pack(pk)
	var b0 := _boar_of(pk)
	await _place(_open_spot(b0.global_position, 10.0), b0.global_position)
	# the first boar that winds up its charge
	var b: Boar = null
	var t0 := _time
	while _time - t0 < 12.0 and b == null:
		await get_tree().physics_frame
		for m in pk.alive_members():
			if (m as Boar).st == Boar.WINDUP:
				b = m as Boar
	if b == null:
		return _result("boar_yank", false, "no wind-up")
	var charges0 := b.charges
	var cand := false
	for i in 20:
		cam.aim_at(b.chain_point())
		await get_tree().physics_frame
		if hero.chain_candidate == b:
			cand = true
			break
	var from := b.global_position
	var d0 := Combat.flat(hero.global_position - from).length()
	_mark("boar_yank")
	await _tap(&"chain")
	var slid: bool = await _until(func() -> bool: return b.is_sliding(), 1.5)
	var broken := b.st != Boar.WINDUP and b.st != Boar.CHARGE
	await _until(func() -> bool: return not b.is_sliding(), 2.0)
	var d1 := Combat.flat(hero.global_position - b.global_position).length()
	var to_h := Combat.flat(hero.global_position - b.global_position).normalized()
	var faces := b.forward().dot(to_h) > 0.8
	# no charge out of the broken wind-up
	await _wait(0.4)
	var no_charge := b.st != Boar.CHARGE and b.charges == charges0
	var ok := cand and slid and broken and d0 - d1 > 1.2 and faces and no_charge
	await _wait(0.3)
	return _result("boar_yank", ok, "candidate=%s slid=%s windup_broken=%s pulled=%.2f m faces_him=%s no_charge=%s" % [str(cand),
		str(slid), str(broken), d0 - d1, str(faces), str(no_charge)])


## A spot `dist` m from `from` on fairly flat open ground with a clear line to it (tries 16 directions).
func _open_spot(from: Vector3, dist: float) -> Vector3:
	var space := hero.get_world_3d().direct_space_state
	for k in 16:
		var a := TAU * float(k) / 16.0
		var p := _ground(from + Vector3(cos(a), 0.0, sin(a)) * dist)
		if absf(p.y - from.y) > 1.2 or float(world.call("slope_at", p.x, p.z)) > 0.12 or bool(world.call("is_water", p.x, p.z)):
			continue
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.6, 0), p + Vector3(0, 0.6, 0), 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var cs := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 1.0
		cs.shape = sph
		cs.collision_mask = 1
		cs.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.2, 0))
		if not space.intersect_shape(cs, 1).is_empty():
			continue
		return p
	return from + Vector3(dist, 0, 0)


## A rock near `c` to stand in front of: [rock centre, hero spot] or [] (uses the World's prop list: tools only).
func _rock_spot(c: Vector3, b: Boar) -> Array:
	var props = world.get("props")
	if props == null:
		return []
	var space := hero.get_world_3d().direct_space_state
	var best: Array = []
	var best_s := INF
	for s in props.get("solids"):
		var rp := Vector3(float(s[0]), 0.0, float(s[1]))
		var rr := float(s[2])
		var rh := float(s[3])
		if rr < 0.45 or rr > 3.0 or rh < 0.6 or rh > 50.0:
			continue
		var dc := Combat.flat(rp - c).length()
		if dc > 22.0:
			continue
		rp = _ground(rp)
		var to_b := Combat.flat(b.global_position - rp)
		if to_b.length() < 7.0:
			continue
		var dir := to_b.normalized()
		var spot := _ground(rp + dir * (rr + 1.5))
		var db := Combat.flat(b.global_position - spot).length()
		if db < 6.0 or db > 15.0 or absf(spot.y - b.global_position.y) > 1.5:
			continue
		# the rock must really be there (a collider right behind the spot) and the way to the boar clear
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.6, 0), spot + Vector3(0, 0.6, 0) - dir * (rr + 2.5), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["collider"] as Node) == world.get("terrain_body"):
			continue
		var q2 := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 0.6, 0), b.global_position + Vector3(0, 0.6, 0), 1)
		if not space.intersect_ray(q2).is_empty():
			continue
		var sc := absf(db - 10.0) + absf(spot.y - b.global_position.y) * 2.0
		if sc < best_s:
			best_s = sc
			best = [rp, spot]
	return best


func _t_boar_crash() -> bool:
	var pk := _pack_at(BOAR1, &"boar")
	if pk == null:
		return _result("boar_crash", false, "no boar")
	await _reset_pack(pk)
	var b := _boar_of(pk)
	var crashes0 := b.crashes
	var stunned_seen := false
	var tries := 0
	var hp0 := hero.hp
	var t0 := _time
	var rock_info := ""
	while Combat.is_alive(b) and tries < 4 and hero.is_alive():
		tries += 1
		var rs := _rock_spot(pk.home, b)
		if rs.is_empty():
			return _result("boar_crash", false, "no rock in front of which to stand near %s" % str(pk.home))
		rock_info = "rock=(%.1f,%.1f)" % [(rs[0] as Vector3).x, (rs[0] as Vector3).z]
		await _place(rs[1], b.global_position)
		hero.hp = maxf(hero.hp, 60.0)
		if tries == 1:
			_mark("boar_crash")
		# wait for the charge, roll aside at the last moment
		var rolled := false
		var tw := _time
		while _time - tw < 12.0 and hero.is_alive():
			await get_tree().physics_frame
			if b.st == Boar.CHARGE and not rolled:
				var d := Combat.flat(hero.global_position - b.global_position)
				var along := d.dot(b._ch_dir)
				var ttc := (along - 0.36 - Boar.HIT_REACH) / maxf(b._ch_speed, 1.0)
				if ttc <= 0.24:
					rolled = true
					var side := Vector3(-b._ch_dir.z, 0.0, b._ch_dir.x)
					hero.debug_move = _stick_to(hero.global_position + side * 3.0)
					await _tap(&"dodge", 0.04)
					hero.debug_move = Vector2.ZERO
			if b.is_stunned():
				stunned_seen = true
				break
			if rolled and b.st in [Boar.RECOVER, Boar.READY] and not b.is_stunned():
				break
		if b.is_stunned():
			_mark("boar_stunned")
			# cut it down while it is dazed
			await _fight([b], b.stun + 0.6, false)
		elif rolled:
			await _wait(0.5)
	var killed := not Combat.is_alive(b)
	var ok := b.crashes > crashes0 and stunned_seen and killed and hero.is_alive()
	return _result("boar_crash", ok, "%s charges=%d crashes=%d stunned=%s killed=%s tries=%d time=%.1fs hero_hp %.0f->%.0f" % [rock_info,
		b.charges, b.crashes - crashes0, str(stunned_seen), str(killed), tries, _time - t0, hp0, hero.hp])


## A fresh pack of `n` wolves at `at` (the balance tests).
func _spawn_pack(at: Vector3, n: int) -> BeastPack:
	var first: Wolf = null
	for i in n:
		var w := Wolf.new()
		main.add_child(w)
		var a := TAU * float(i) / float(n)
		w.teleport(_ground(at + Vector3(cos(a), 0.0, sin(a)) * 4.5), _rng.randf() * TAU)
		if first == null:
			first = w
	await _wait(0.2)
	return first.pack


func _t_balance() -> bool:
	var at := _ground(BALANCE_AT)
	var n := int(Game.arg_f("balance_n", 4.0))
	# which fights: <policy><pack size>: c careless (runs at them mashing, never guards or rolls), g guard (mashes but
	# raises the shield when a wolf winds up at him), s skilled (rolls the lunges, punishes the openings)
	var set_ := Array(String(Game.arg("balance_set", "c5,s5,c3")).split(",", false))
	var res := {}
	for f in set_:
		res[f] = {"won": 0, "hp": 0.0, "bites": 0, "comfy": 0, "runs": 0, "time": 0.0}
	var details := ""
	for rep in n:
		details += " [%d:" % rep
		for f in set_:
			var pol := String(f).substr(0, 1)
			var cnt := int(String(f).substr(1))
			var r := await _balance_fight(at, cnt, {"c": "careless", "g": "guard", "s": "skilled"}.get(pol, "skilled"),
				"balance_" + String(f))
			var d: Dictionary = res[f]
			d["runs"] += 1
			d["bites"] += int(r["bites"])
			d["time"] += float(r["time"])
			if bool(r["won"]):
				d["won"] += 1
				d["hp"] += float(r["hp"])
				if float(r["hp"]) >= 40.0:
					d["comfy"] += 1
			details += " %s %s hp %.0f (%d bites, %.0fs)" % [f, "won" if bool(r["won"]) else "lost", float(r["hp"]),
				int(r["bites"]), float(r["time"])]
		details += "]"
	var summary := ""
	for f in set_:
		var d: Dictionary = res[f]
		summary += " %s: won %d/%d avg_hp_won=%.0f bites_avg=%.1f time_avg=%.0fs |" % [f, int(d["won"]), n,
			float(d["hp"]) / maxf(1.0, float(d["won"])), float(d["bites"]) / n, float(d["time"]) / n]
	# careless against 5 must lose most fights (it does about 4 in 5: at least half of the runs here, so that the odd
	# lucky run does not fail the test); skilled against 5 must win every time, comfortably (>= 40 hp) at least 2
	# runs in 3
	var ok := true
	if res.has("c5"):
		ok = ok and (n - int(res["c5"]["won"])) * 2 >= n
	if res.has("s5"):
		ok = ok and int(res["s5"]["won"]) == n and int(res["s5"]["comfy"]) * 3 >= n * 2
	return _result("balance", ok, "runs=%d%s%s" % [n, summary, details])


## One balance fight: a fresh pack of `count` at `at`, the hero 16 m off; the survivors are removed afterwards.
func _balance_fight(at: Vector3, count: int, policy: String, tag: String) -> Dictionary:
	if not hero.is_alive() or Game.phase != Game.Phase.PLAY:
		await _until(func() -> bool: return hero.is_alive() and Game.phase == Game.Phase.PLAY, 8.0)
	var pk := await _spawn_pack(at, count)
	await _place(at + Vector3(0, 0, 16.0), at)
	await _provoke(pk)
	_mark(tag)
	var foes := pk.alive_members()
	var r := await _fight(foes, 90.0, policy != "skilled", policy == "guard")
	r["reason"] = "won" if bool(r["won"]) else ("dead" if not hero.is_alive() else "timeout")
	r["won"] = bool(r["won"]) and hero.is_alive()
	print("ENC balance %s %s time=%.1fs hp=%.0f bitten=%d attacks=%d windups=%d bites=%d evades=%d rolls=%d alive_left=%d" % [tag,
		String(r["reason"]), float(r["time"]), float(r["hp"]), int(r["bites"]), pk.attacks, pk.windups, pk.hits, pk.evades,
		int(r["rolls"]), pk.alive_count()])
	for m in pk.alive_members():
		(m as Node).queue_free()
	await _until(func() -> bool: return hero.is_alive() and Game.phase == Game.Phase.PLAY, 8.0)
	await _wait(0.4)
	return r


## No test: stands by the forest pack and lets it hunt him (renders of the ring, the feints, the attacks).
func _t_watch() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	await _place(Vector3(-14.0, 0, 33.0), pk.home)
	_mark("watch")
	var hunted := await _provoke(pk, 10.0)
	hero.invulnerable = 999.0
	await _wait(float(Game.arg_f("watch_s", 12.0)))
	hero.invulnerable = 0.0
	return _result("watch", hunted, "hunted=%s attacks=%d" % [str(hunted), pk.attacks])


# --- renders (no pass / fail): the moments the strips and shots need, from the gameplay camera ----------------------
# ENC mark lines name the frames: render with --write-movie, fastpre=1 (the set-up at 4x), noui=1.

## Prints a mark whenever a beast of `foes` changes state (the strip's beats), for `seconds`, while `fight` runs;
## every 3rd frame a "ENC track" line: the frame, the hero's and each beast's position on screen (crops for strips).
func _beats(foes: Array, seconds: float) -> void:
	var last := {}
	var t0 := _time
	var vc := get_viewport().get_camera_3d()
	while _time - t0 < seconds:
		if Engine.get_frames_drawn() % 3 == 0 and vc != null:
			var line := "ENC track frame=%d hero=%s" % [Engine.get_frames_drawn(), _scr(vc, hero.global_position + Vector3(0, 1.0, 0))]
			for e in foes:
				if is_instance_valid(e):
					line += " %s=%s" % [String(e.name).right(4), _scr(vc, (e as Node3D).global_position + Vector3(0, 0.5, 0))]
			print(line)
		for e in foes:
			if not is_instance_valid(e):
				continue
			var nm := String(e.call("state_name")) if Combat.is_alive(e) else "dead"
			if (e as Enemy).is_stunned():
				nm = "stunned"
			if last.get(e, "") != nm:
				last[e] = nm
				_mark("%s_%s" % [String(e.name).right(4), nm])
		await get_tree().physics_frame


## A pack of 3: a wolf winds up, lunges, he rolls, it lands open and he punishes it (skilled fight). render_at=road:
## the forest pack on its road (the camera looks through tree crowns there), else a fresh pack on an open meadow.
func _r_wolf() -> bool:
	var pk: BeastPack = null
	if String(Game.arg("render_at", "meadow")) == "road":
		pk = _pack_at(PACK1, &"wolf")
		await _reset_pack(pk)
		pk.howled = true # (no howl: straight to the hunt)
		await _place(Vector3(-14.0, 0.0, 33.0), pk.home)
	else:
		var at := _ground(BALANCE_AT)
		pk = await _spawn_pack(at, 3)
		pk.howled = true
		await _place(at + Vector3(0, 0, 9.0), at)
	var foes := pk.alive_members()
	pk.alert(null)
	_mark("r_wolf")
	_beats(foes, float(Game.arg_f("render_s", 9.0)))
	await _fight(foes, float(Game.arg_f("render_s", 9.0)), false)
	return true


## The 5-wolf pack circling him (its attack tokens held back: only the ring and the feints).
func _r_ring() -> bool:
	var pk := _pack_at(Vector3(6.0, 0.0, -30.0), &"wolf")
	await _reset_pack(pk)
	pk.howled = true
	await _place(pk.home + Vector3(-3.0, 0, 8.0), pk.home)
	pk.alert(null)
	hero.invulnerable = 999.0
	var t0 := _time
	var marked := false
	while _time - t0 < float(Game.arg_f("render_s", 8.0)):
		pk.token_cd = 5.0
		if not marked and pk.state == BeastPack.HUNT and _time - t0 > 1.0:
			marked = true
			_mark("r_ring")
			_beats(pk.alive_members(), float(Game.arg_f("render_s", 8.0)))
		cam.pitch = lerpf(cam.pitch, -36.0, 0.05)
		await get_tree().physics_frame
	hero.invulnerable = 0.0
	return true


## In front of a rock: the boar's wind-up, the charge, his roll aside, the crash into the rock, the stun, his blows.
func _r_boar() -> bool:
	var pk := _pack_at(BOAR1, &"boar")
	await _reset_pack(pk)
	var b := _boar_of(pk)
	var rs := _rock_spot(pk.home, b)
	if rs.is_empty():
		return _result("r_boar", false, "no rock")
	await _place(rs[1], b.global_position)
	_mark("r_boar")
	_beats([b], 12.0)
	var rolled := false
	var tw := _time
	while _time - tw < 9.0 and hero.is_alive() and not b.is_stunned():
		await get_tree().physics_frame
		if b.st == Boar.CHARGE and not rolled:
			var d := Combat.flat(hero.global_position - b.global_position)
			var ttc := (d.dot(b._ch_dir) - 0.36 - Boar.HIT_REACH) / maxf(b._ch_speed, 1.0)
			if ttc <= 0.24:
				rolled = true
				_mark("r_boar_roll")
				hero.debug_move = _stick_to(hero.global_position + Vector3(-b._ch_dir.z, 0.0, b._ch_dir.x) * 3.0)
				await _tap(&"dodge", 0.04)
				hero.debug_move = Vector2.ZERO
	if b.is_stunned():
		await _fight([b], b.stun + 0.4, false)
	await _wait(0.5)
	return true


## (beauty) The first fight on the forest road: the pack round him on the road, seen from up the road (a fixed
## camera over the road; its tokens held back: the ring and the feints).
func _r_road() -> bool:
	var pk := _pack_at(PACK1, &"wolf")
	await _reset_pack(pk)
	var spot := _ground(Vector3(-20.5, 0.0, 22.5))
	await _place(spot, pk.home)
	pk.alert(null)
	hero.invulnerable = 999.0
	# up the road (it runs from (-14, 33) down to (-22, 20) here), 11 m back and 4.5 m up
	var rd := Vector3(-8.0, 0.0, -13.0).normalized()
	var cp := _ground(spot - rd * 11.0) + Vector3(0, 4.5, 0)
	var d := spot + Vector3(0, 0.8, 0) - cp
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	var t0 := _time
	var marked := false
	while _time - t0 < float(Game.arg_f("render_s", 6.0)):
		pk.token_cd = 5.0
		if not marked and pk.state == BeastPack.HUNT and _time - t0 > 2.0:
			marked = true
			cam.set_fly(cp, yaw, pitch)
			_mark("r_road")
		await get_tree().physics_frame
	cam.follow(hero, true)
	hero.invulnerable = 0.0
	return true


## (beauty) A boar clearing on the thumb path: the hero walks up to one of the herd of two; it notices him and winds up
## its charge, its standing rocks round the clearing; a fixed camera from behind and beside him.
func _r_clearing() -> bool:
	var pk := _pack_at(HERD, &"boar")
	await _reset_pack(pk)
	var b := _boar_of(pk)
	var bp := b.global_position
	# the hero west of it, the camera south of them both looking north (the ridge and the massif behind): two profiles
	var hp_ := _ground(bp + Vector3(-6.5, 0.0, 1.5))
	await _place(hp_, bp)
	var mid := (hp_ + bp) * 0.5 + Vector3(0, 0.6, 0)
	var cp := _ground(bp + Vector3(-3.5, 0.0, 7.5)) + Vector3(0, 2.6, 0)
	var d := mid - cp
	cam.set_fly(cp, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	_mark("r_clearing")
	_beats([b], float(Game.arg_f("render_s", 3.0)))
	await _wait(float(Game.arg_f("render_s", 3.0)))
	cam.follow(hero, true)
	return true


func _scr(vc: Camera3D, p: Vector3) -> String:
	if vc.is_position_behind(p):
		return "-"
	var q := vc.unproject_position(p)
	return "%d,%d" % [int(q.x), int(q.y)]


# --- clipping -------------------------------------------------------------------------------------------------------

const CLIP_HERO_R := 0.36
const CLIP_HERO_H := 1.8
## Grazes of a world collider tolerated (m): a paw, any other part.
const WORLD_GRAZE_PAW := 0.06
const WORLD_GRAZE := 0.03


## Samples every physics frame while `stats["on"]`: each beast's markers (muzzle, head, chest, hips, paws; the boar's
## tusks) against the hero's capsule, the other beasts' hurt capsules, the world (a point inside a layer-1 shape that
## is not the terrain: a rock, a trunk, a wall) and the ground (a paw more than 6 cm under it, the body under it).
func _clip_watch(beasts: Array, stats: Dictionary) -> void:
	var space := hero.get_world_3d().direct_space_state
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = 1
	var tb = world.get("terrain_body")
	var sq := PhysicsShapeQueryParameters3D.new()
	var tiny := SphereShape3D.new()
	tiny.radius = 0.005
	sq.shape = tiny
	sq.collision_mask = 1
	if tb != null:
		pq.exclude = [(tb as CollisionObject3D).get_rid()]
		sq.exclude = pq.exclude
	var rays0 := PackNav.feet_rays
	var f0 := Engine.get_process_frames()
	while bool(stats["on"]):
		await get_tree().physics_frame
		if not bool(stats["on"]):
			break # (switched off while it waited: the test may have teleported the beasts home this very frame)
		stats["frames"] += 1
		stats["feet_rays"] = float(PackNav.feet_rays - rays0) / maxf(1.0, float(Engine.get_process_frames() - f0))
		var ha := hero.global_position + Vector3(0, CLIP_HERO_R, 0)
		var hb := hero.global_position + Vector3(0, CLIP_HERO_H - CLIP_HERO_R, 0)
		for e in beasts:
			if not Combat.is_alive(e) or (e as Enemy).is_yanked():
				continue
			var r = (e as Enemy).rig
			if r == null:
				continue
			var names: Array = [&"muzzle", &"head", &"chest", &"hips"]
			if e is Boar:
				names.append(&"tusks")
			var pts: Array = []
			for nm in names:
				var m: Node3D = r.q.marker(nm)
				if m != null:
					pts.append([String(nm), m.global_position])
			for i in 4:
				pts.append(["paw", (r.call("paw", i) as Node3D).global_position])
			for pt in pts:
				stats["samples"] += 1
				var nm: String = pt[0]
				var p: Vector3 = pt[1]
				# the hero
				var d := _seg_dist(p, ha, hb)
				if hero.is_alive() and d < float(stats["hero_min_d"]):
					stats["hero_min_d"] = d
					stats["hero_min_what"] = "%s %s %s" % [e.name.right(4), nm, String(e.call("state_name"))]
				var depth := CLIP_HERO_R - d
				if hero.is_alive() and depth > 0.05:
					stats["hero"] += 1
					if depth > float(stats["hero_max"]):
						stats["hero_max"] = depth
						stats["hero_what"] = "%s %s %s" % [e.name.right(4), nm, String(e.call("state_name"))]
				# the other beasts
				for e2 in beasts:
					if e2 == e or not Combat.is_alive(e2):
						continue
					for v in (e2 as Enemy).hurt_volumes():
						var dv: float = float(v[2]) - _seg_dist(p, v[0], v[1])
						if dv > 0.08:
							stats["beast"] += 1
							if dv > float(stats["beast_max"]):
								stats["beast_max"] = dv
								stats["beast_what"] = "%s %s %s into %s %s at %s" % [e.name.right(4), nm, String(e.call("state_name")),
									e2.name.right(4), String(e2.call("state_name")), str(p.snapped(Vector3.ONE * 0.1))]
				# the world (rocks, trunks): any body part inside one fails; a paw at the end of its stride grazing a
				# trunk it walks past is counted apart
				pq.position = p
				var inside := space.intersect_point(pq, 1)
				if not inside.is_empty():
					# how deep (a tiny sphere's contact with the shape) and into what
					sq.transform = Transform3D(Basis.IDENTITY, p)
					var pairs := space.collide_shape(sq, 4)
					var dep := 0.0
					for k in range(0, pairs.size() - 1, 2):
						dep = maxf(dep, (pairs[k] as Vector3).distance_to(pairs[k + 1]) - 0.005)
					# a graze of a collider (a rock's hull, a trunk's cylinder: a little bigger than what is drawn) is
					# counted apart: a paw by up to 6 cm, the head or the body by up to 3 cm; deeper fails
					if dep <= (WORLD_GRAZE_PAW if nm == "paw" else WORLD_GRAZE):
						stats["world_paw"] += 1
					else:
						stats["world"] += 1
					var sh := ""
					var col = inside[0].get("collider")
					var sid := int(inside[0].get("shape", 0))
					if col is CollisionObject3D:
						var so := (col as CollisionObject3D).shape_owner_get_owner((col as CollisionObject3D).shape_find_owner(sid))
						if so is CollisionShape3D and (so as CollisionShape3D).shape != null:
							sh = (so as CollisionShape3D).shape.get_class().replace("Shape3D", "")
							if (so as CollisionShape3D).shape is CylinderShape3D:
								var cpos := (so as CollisionShape3D).global_position
								var eo := (e as Node3D).global_position
								sh += " (body %.2f m from it, obst=%d, v=%.1f)" % [Vector2(eo.x - cpos.x, eo.z - cpos.z).length() - ((so as CollisionShape3D).shape as CylinderShape3D).radius,
									(e.get("nav") as PackNav)._obst.size() / 2 if e.get("nav") != null else -1, Vector2((e as Enemy).velocity.x, (e as Enemy).velocity.z).length()]
					if dep >= float(stats["world_depth"]):
						stats["world_depth"] = dep
						stats["world_what"] = "%s %s %s at %s in %s %.3f m" % [e.name.right(4), nm, String(e.call("state_name")),
							str(p.snapped(Vector3.ONE * 0.1)), sh, dep]
				# the ground
				var gy := float(world.call("height_at", p.x, p.z))
				var under := gy - p.y
				if nm == "paw":
					stats["paw_min"] = minf(float(stats["paw_min"]), -under)
					stats["paw_max"] = maxf(float(stats["paw_max"]), -under)
				var lim := 0.06 if nm == "paw" else 0.0
				if under > lim:
					stats["ground"] += 1
					if under > float(stats["ground_max"]):
						stats["ground_max"] = under
						stats["ground_what"] = "%s %s %s" % [e.name.right(4), nm, String(e.call("state_name"))]


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _clip_stats() -> Dictionary:
	return {"on": true, "frames": 0, "hero_min_d": 9.0, "hero_min_what": "", "paw_min": 9.0, "paw_max": -9.0, "samples": 0,
		"world_paw": 0, "world_depth": 0.0, "feet_rays": 0.0,
		"hero": 0, "hero_max": 0.0, "hero_what": "", "beast": 0, "beast_max": 0.0,
		"beast_what": "", "world": 0, "world_what": "", "ground": 0, "ground_max": 0.0, "ground_what": ""}


## A skilled fight against a fresh pack of 3 on the meadow, the 5-wolf pack hunting him in its clearing (he stands,
## invulnerable), then a boar charged into a rock and cut down: no beast part inside the hero (12 cm), another beast
## (15 cm), the ground (12 cm) or a rock, a trunk or a wall (none; a collider, a little bigger than what is drawn,
## may be grazed by a paw by 6 cm, by another part by 3 cm, in 0.2 % of the samples at most).
func _t_clip() -> bool:
	var out := ""
	var ok := true
	# 1) the pack of 3
	var at := _ground(BALANCE_AT)
	var pk := await _spawn_pack(at, 3)
	await _place(at + Vector3(0, 0, 12.0), at)
	var st := _clip_stats()
	var foes := pk.alive_members()
	_clip_watch(foes, st)
	await _provoke(pk)
	await _fight(foes, 40.0, false)
	st["on"] = false
	for m in pk.alive_members():
		(m as Node).queue_free()
	out += " pack3:" + _clip_line(st)
	ok = ok and _clip_ok(st)
	await _until(func() -> bool: return hero.is_alive() and Game.phase == Game.Phase.PLAY, 8.0)
	# 2) the 5-wolf pack in its clearing, hunting an invulnerable hero who stands still
	var pk5 := _pack_at(Vector3(6.0, 0.0, -30.0), &"wolf")
	await _reset_pack(pk5)
	await _place(pk5.home + Vector3(-3.0, 0, 8.0), pk5.home)
	var st5 := _clip_stats()
	_clip_watch(pk5.alive_members(), st5)
	await _provoke(pk5)
	hero.invulnerable = 999.0
	await _wait(12.0)
	hero.invulnerable = 0.0
	st5["on"] = false
	out += " pack5:" + _clip_line(st5)
	ok = ok and _clip_ok(st5)
	await _reset_pack(pk5)
	# 3) a boar crashed into a rock and fought (the lone one of the thumb, or one of the herd when boar_crash already
	# killed it)
	var bp := _pack_at(BOAR1, &"boar")
	if bp == null or bp.alive_count() == 0:
		bp = _pack_at(HERD, &"boar")
	await _reset_pack(bp)
	var b := _boar_of(bp)
	if b == null:
		return _result("clip", false, out + " no boar left")
	var stb := _clip_stats()
	_clip_watch(bp.alive_members(), stb)
	var rs := _rock_spot(bp.home, b)
	if not rs.is_empty():
		await _place(rs[1], b.global_position)
		var rolled := false
		var tw := _time
		while _time - tw < 10.0 and hero.is_alive() and not b.is_stunned():
			await get_tree().physics_frame
			if b.st == Boar.CHARGE and not rolled:
				var d := Combat.flat(hero.global_position - b.global_position)
				if (d.dot(b._ch_dir) - 0.36 - Boar.HIT_REACH) / maxf(b._ch_speed, 1.0) <= 0.24:
					rolled = true
					hero.debug_move = _stick_to(hero.global_position + Vector3(-b._ch_dir.z, 0.0, b._ch_dir.x) * 3.0)
					await _tap(&"dodge", 0.04)
					hero.debug_move = Vector2.ZERO
		await _fight([b], 12.0, false)
	stb["on"] = false
	out += " boar:" + _clip_line(stb)
	ok = ok and _clip_ok(stb)
	await _reset_pack(bp)
	return _result("clip", ok, out)


func _clip_ok(st: Dictionary) -> bool:
	return int(st["frames"]) > 0 and float(st["hero_max"]) <= 0.12 and float(st["beast_max"]) <= 0.15 and int(st["world"]) == 0 \
		and float(st["ground_max"]) <= 0.12 and float(st["world_paw"]) <= 0.002 * float(st["samples"])


func _clip_line(st: Dictionary) -> String:
	return " feet_rays/frame=%.1f" % float(st["feet_rays"]) + " frames=%d samples=%d closest_to_hero=%.2f (%s) paw_clearance=%.2f..%.2f hero=%d (max %.2f %s) beast=%d (max %.2f %s) world=%d grazing=%d (%s) ground=%d (max %.2f %s)" % [int(st["frames"]),
		int(st["samples"]), float(st["hero_min_d"]), st["hero_min_what"], float(st["paw_min"]), float(st["paw_max"]),
		int(st["hero"]), float(st["hero_max"]), st["hero_what"], int(st["beast"]), float(st["beast_max"]), st["beast_what"],
		int(st["world"]), int(st["world_paw"]), st["world_what"], int(st["ground"]), float(st["ground_max"]), st["ground_what"]]



## The 5-wolf pack hunting a hero who stands 5 m from a big trunk (r 0.62 m, near the pack's clearing): the ring
## runs through the trunk, the wolves strafe round it; no paw may reach into it (PackNav's clearance).
func _t_clip_trunk() -> bool:
	var trunk := Vector3(8.95, 0.0, -17.41)
	var pk5 := _pack_at(Vector3(6.0, 0.0, -30.0), &"wolf")
	await _reset_pack(pk5)
	var spot := _ground(trunk + Vector3(-5.0, 0.0, 0.5))
	await _place(spot, trunk)
	var st5 := _clip_stats()
	_clip_watch(pk5.alive_members(), st5)
	await _provoke(pk5)
	hero.invulnerable = 999.0
	await _wait(float(Game.arg_f("probe_s", 15.0)))
	hero.invulnerable = 0.0
	st5["on"] = false
	await _reset_pack(pk5)
	return _result("clip_trunk", _clip_ok(st5), "trunk:" + _clip_line(st5))
