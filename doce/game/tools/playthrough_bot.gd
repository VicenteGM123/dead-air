extends "res://tools/nemea_bot.gd"
## The slice played from the title to the boat (ENCOUNTERS merge), in one run of the real game
## (tools/playthrough.tscn), through the hero's real input path (HeroInput.bot, Hero.debug_move, the camera aiming the
## chain spear): it never teleports him, heals him or touches a beast. One line per step, then a summary:
##   PT step <name> PASS|FAIL <details>
##   PT playthrough passed=N/M result=PASS|FAIL deaths=D time=<game s>
##   godot --headless --path . res://tools/playthrough.tscn --fixed-fps 60 --quit-after 300000 -- ptbot=1 quit=1
## Steps (docs/GDD.md "Flujo del tramo"):
##   title     the title menu, "Comenzar" (the UI's begin_game): PLAY on the pier
##   village   down the pier and up the main road into the village
##   cat       a cat petted (E held: it purrs, the hero plays "pet")
##   wolves    the forest road: the first pack (3) notices him on the way and is beaten (rolls, punishes)
##   wheat     on along the road through the wheat field west of the forest, a few steps into the wheat at a walk
##             (the free hand brushes the ears: RigHeracles.set_brush), back to the road and the broken passage's south rim
##   passage   the bronze rings: the sea stack, the north rim
##   boars     the thumb path: the boar of the first clearing (he waits in front of a standing rock: its charge
##             crashes into it) and the herd of two further on, beaten
##   altar     the Altar de la Sierra: he prays (healed, the checkpoint)
##   boulder   the meadow to cave mouth B: the boulder hauled into the crack (sealed, from inside)
##   cave      through the crack's tunnel into the arena: the lion wakes, labour I's card, the fight begins
##   lion      the fight won (dodged pounces and yanks into stone, the wrestles); fallen, he comes back from the altar
##   pelt      Heracles takes the pelt (outfit lion), the victory card, back to free roam
##   return    out through mouth A, off the escarpment, through the forest and the village to the pier
##   boat      "Zarpar": labour II's card (Lerna, próximamente), the fade, back to the title (the scene reloads)
## Args: quit=1; ptshots=<dir> (with a window: a PNG at each step and at the fights' key moments, from the gameplay
## camera; rendering is switched off in between, RenderingServer.render_loop_enabled, so a run with shots costs
## little more than a headless one); botdebug=1 (the fights traced); pt_from=<stage> is not offered on purpose: the
## playthrough always starts at the title.

## Stages of the run (a fall sends the bot back to the stage his respawn point belongs to).
enum { ROAD, PASSAGE, THUMB, ALTAR, BOULDER, LION, PELT, RETURN_TRIP, BOAT, END }

## The encounter bot's fighting policy (tools/encounter_bot.gd _fight: rolls a wind-up as it runs out, punishes
## the openings), as a helper that runs no tests of its own.
class EncHelper extends "res://tools/encounter_bot.gd":
	func _ready() -> void:
		_debug = Game.arg_on("botdebug")
		_rng.seed = 4321


## The lion bot's fighting brain (tools/lion_bot.gd _bot_tick: baits pounces into the columns, yanks it into them,
## wrestles in the windows), as a helper that runs no tests of its own.
class LionHelper extends "res://tools/lion_bot.gd":
	func _ready() -> void:
		pass


const PACK1 := Vector3(-24.0, 0.0, 14.0)
const BOAR1 := Vector3(-104.0, 0.0, -47.0)
const HERD := Vector3(-78.0, 0.0, -72.0)

var _enc: EncHelper = null
var _lb: LionHelper = null
var _results := {}
var _order: Array = []
var _deaths := 0
var _died := false
var _shots := ""
var _shot_n := 0
var _shooting := false
var _ev_n := {}
var _ev_t := {}
var _cards: Array = []
var _boss: Array = []
var _fights: Array = []
var _pt_t0 := 0.0
var _victory_t := -1.0
var _boss_t := -1.0
var _msg_t := -1.0
var _hints := 0


func _ready() -> void:
	_shots = String(Game.arg("ptshots", ""))
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	if _can_shoot():
		RenderingServer.render_loop_enabled = false
	_play.call_deferred()


func _process(delta: float) -> void:
	# (CORE's camera watch, as information; never on a freed hero after the scene reloads)
	if not is_instance_valid(hero) or not is_instance_valid(cam):
		return
	super._process(delta)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_instance_valid(hero) and _can_shoot():
		_watch_events()


# --- shots ---------------------------------------------------------------------------------------------------------

func _can_shoot() -> bool:
	return _shots != "" and DisplayServer.get_name() != "headless"


func _mark(tag: String) -> void:
	var hp := -1.0
	var at := Vector3.ZERO
	if is_instance_valid(hero):
		hp = hero.hp
		at = hero.global_position
	print("PT mark %s t=%.2f hp=%.0f at=(%.1f, %.1f, %.1f)" % [tag, _time, hp, at.x, at.y, at.z])


## A PNG of the gameplay view now (rendering switched on for a few frames). Awaited for the steps; called without
## await from the event watch (the bot's decisions go on meanwhile: game time does not depend on the render).
func _shot(tag: String) -> void:
	_mark(tag)
	if not _can_shoot() or _shooting:
		return
	_shooting = true
	RenderingServer.render_loop_enabled = true
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(_shots.path_join("pt_%02d_%s.png" % [_shot_n, tag]))
	_shot_n += 1
	RenderingServer.render_loop_enabled = false
	_shooting = false


## An event shot: at most `n` of `tag`, `gap` s apart.
func _ev(tag: String, n: int, gap: float) -> void:
	var c := int(_ev_n.get(tag, 0))
	if c >= n or _time - float(_ev_t.get(tag, -1000.0)) < gap or _shooting:
		return
	_ev_n[tag] = c + 1
	_ev_t[tag] = _time
	_shot("%s%d" % [tag, c + 1])


## The key moments of the fights and the chain, caught as they happen.
func _watch_events() -> void:
	var hp := hero.global_position
	if hero.state == Hero.St.CHAIN and hero.chain_mode == &"zip":
		_ev("zip", 2, 4.0)
	if hero.chain_mode == &"haul":
		_ev("haul", 1, 5.0)
	if hero.rig != null and String(hero.rig.get("action")) == "don_skin":
		_ev("don_skin", 2, 1.2)
	if _boss_t >= 0.0 and _time - _boss_t > 1.2:
		_boss_t = -1.0
		_ev("boss_bar", 1, 1.0)
	if _victory_t >= 0.0 and _time - _victory_t > 2.6:
		_victory_t = -1.0
		_ev("victory_card", 1, 1.0)
	if _msg_t >= 0.0 and _time - _msg_t > 0.7:
		_msg_t = -1.0
		_ev("toast", 6, 4.0)
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e == null:
			continue
		var d := Combat.flat(e.global_position - hp).length()
		if d > 18.0:
			continue
		if e is Wolf and e.alive:
			var w := e as Wolf
			if w.st == Wolf.WINDUP and w.telegraph_left() < 0.32 and d < 8.0:
				_ev("wolf_windup", 2, 4.0)
			elif w.st == Wolf.LUNGE and d < 3.5:
				_ev("wolf_lunge", 2, 4.0)
			elif w.st == Wolf.RECOVER and hero.state == Hero.St.ATTACK and d < 3.0:
				_ev("wolf_punish", 2, 4.0)
		elif e is Boar and e.alive:
			var b := e as Boar
			if b.st == Boar.WINDUP and b.telegraph_left() < 0.5:
				_ev("boar_windup", 2, 5.0)
			elif b.st == Boar.CHARGE and d < 6.5:
				_ev("boar_charge", 2, 5.0)
			elif b.is_stunned():
				_ev("boar_stunned", 2, 5.0)
		elif e is Lion:
			var l := e as Lion
			match l.state:
				Lion.S.INTRO:
					_ev("lion_wakes", 1, 1.0)
				Lion.S.POUNCE:
					if l.pounce_phase() == Lion.P.WIND and l.telegraph_left() < 0.3:
						_ev("lion_pounce_windup", 2, 12.0)
					elif l.pounce_phase() == Lion.P.AIR:
						_ev("lion_pounce_air", 2, 12.0)
				Lion.S.SWIPE:
					if l.telegraph_left() < 0.25:
						_ev("lion_swipe", 1, 10.0)
				Lion.S.ROAR:
					if l.telegraph_left() < 0.12:
						_ev("lion_roar", 2, 15.0)
				Lion.S.PERCHED:
					_ev("lion_perched", 2, 15.0)
				Lion.S.STUNNED:
					_ev("lion_stunned", 3, 12.0)
				Lion.S.GRAPPLED:
					if hero.grapple_window_left() > 0.0:
						_ev("lion_wrestle", 3, 12.0)
				Lion.S.DOWNED:
					_ev("lion_downed", 1, 10.0)
				Lion.S.DEAD:
					_ev("lion_collapse", 2, 0.8)
			if l.alive and l.phase >= 2 and l.state == Lion.S.PROWL:
				_ev("lion_enraged", 1, 1.0)


# --- results -------------------------------------------------------------------------------------------------------

func _step(nm: String, ok: bool, details: String) -> void:
	if not _results.has(nm):
		_order.append(nm)
	_results[nm] = ok
	print("PT step %s %s t=%.0f hp=%.0f %s" % [nm, "PASS" if ok else "FAIL", _time - _pt_t0,
		hero.hp if is_instance_valid(hero) else -1.0, details])


func _finish() -> void:
	var passed := 0
	for k in _order:
		if bool(_results[k]):
			passed += 1
	print("PT camera (information, CORE's watch) min_to_head=%.2f (%s) close_max=%.2fs inside_frames=%d first_inside=%s under_water_frames=%d" % [
		_cam_min, _cam_min_at, _cam_close_max, _cam_inside, _cam_inside_at, _cam_wet])
	for f in _fights:
		print("PT fight %s" % str(f))
	print("PT playthrough passed=%d/%d result=%s deaths=%d time=%.0f s steps=%s" % [passed, _order.size(),
		"PASS" if passed == _order.size() and _order.size() >= 14 else "FAIL", _deaths, _time - _pt_t0, str(_results)])
	if Game.arg_on("quit"):
		get_tree().quit()


# --- moving --------------------------------------------------------------------------------------------------------

## The playthrough never teleports or heals him: CORE's _place (used by its boulder routine) becomes a walk there and a
## turn to `look`.
func _place(p: Vector3, look: Vector3) -> void:
	await _walk_to(p, 0.3, 10.0)
	var d := Combat.flat(look - hero.global_position)
	if d.length() > 0.01:
		hero.facing = atan2(-d.x, -d.z)
	cam.lock_on(null)
	cam.follow(hero, true)
	await _wait(0.5)


func _face(look: Vector3) -> void:
	var d := Combat.flat(look - hero.global_position)
	if d.length() > 0.01:
		hero.facing = atan2(-d.x, -d.z)
	cam.follow(hero, true)
	await _wait(0.4)


## The waypoint of `pts` to head for now: the nearest one, or the next one when he is already past it.
func _nearest_ahead(pts: Array[Vector2]) -> int:
	var p := Vector2(hero.global_position.x, hero.global_position.z)
	var best := 0
	var bd := INF
	for k in pts.size():
		var d := p.distance_to(pts[k])
		if d < bd:
			bd = d
			best = k
	if best + 1 < pts.size() and (p - pts[best]).dot(pts[best + 1] - pts[best]) > 0.0:
		best += 1
	return best


## Beasts hunting him now: every member of a pack that is alerted or hunting with one of them within 25 m.
func _threats() -> Array:
	var out: Array = []
	var hp := hero.global_position
	for n in get_tree().get_nodes_in_group("beast_pack"):
		var pk := n as BeastPack
		if pk == null or pk.cleared or not (pk.state == BeastPack.ALERT or pk.state == BeastPack.HUNT):
			continue
		var near := false
		for m in pk.alive_members():
			if Combat.flat((m as Node3D).global_position - hp).length() < 25.0:
				near = true
		if near:
			for m in pk.alive_members():
				if not out.has(m):
					out.append(m)
	return out


func _fight_now(foes: Array, why: String, rock_spot: Vector3 = Vector3.INF) -> Dictionary:
	hero.debug_move = Vector2.ZERO
	hero.inp.bot_clear()
	var kinds := {}
	for f in foes:
		var k := "wolf" if f is Wolf else ("boar" if f is Boar else "beast")
		kinds[k] = int(kinds.get(k, 0)) + 1
	_mark("fight_%s" % why)
	var hp0 := hero.hp
	var st: Dictionary
	if kinds.size() == 1 and kinds.has("boar"):
		st = await _boar_fight(foes, 150.0, rock_spot)
	else:
		st = await _enc._fight(foes, 150.0, false)
	st["why"] = why
	st["foes"] = kinds
	st["hp0"] = hp0
	_fights.append(st)
	print("PT fight %s %s won=%s time=%.1f hp %.0f->%.0f hurt=%d rolls=%d perfect=%d parries=%d crashes=%d" % [why, str(kinds),
		str(st["won"]), float(st["time"]), hp0, hero.hp, int(st.get("bites", 0)), int(st.get("rolls", 0)), int(st.get("perfect", 0)),
		int(st.get("parries", 0)), int(st.get("crashes", 0))])
	return st


## Boars, the way the slice teaches them (docs/ENCOUNTERS.md 1.5: dodge the charge into a standing rock, or parry it):
## a charge met at `rock_spot` (in front of a standing rock) is rolled aside at the last moment (it runs on into the
## rock: stunned), every other charge and gore is parried (the guard pressed as the tusks arrive, the lock turning him
## to it); a staggered, stunned or recovering boar within reach takes the combo. (The encounter bot's roll-and-punish
## policy does not kill a boar in the open: a dodged charge skids it 3.5 m past him and it recovers in 0.7-1.0 s.)
func _boar_fight(foes: Array, timeout: float, rock_spot: Vector3 = Vector3.INF) -> Dictionary:
	var stats := {"won": false, "time": 0.0, "parries": 0, "crashes": 0, "rolls": 0, "bites": 0, "perfect": 0}
	var hurt := [0]
	var cb_h := func(_h: Dictionary) -> void: hurt[0] += 1
	hero.hurt.connect(cb_h)
	var parried := [0]
	var cb_p := func(_a: Node) -> void: parried[0] += 1
	hero.parried.connect(cb_p)
	var crash0 := 0
	for f in foes:
		crash0 += (f as Boar).crashes
	var t0 := _time
	var guard_t := -1.0
	var rolled_for: Node = null
	var atk_cd := 0.0
	while _time - t0 < timeout:
		await get_tree().physics_frame
		atk_cd -= get_physics_process_delta_time()
		var alive := _enc._alive(foes)
		if alive.is_empty():
			stats["won"] = true
			break
		if not hero.is_alive():
			break
		var hp_ := hero.global_position
		if Game.arg_on("botdebug") and int(_time * 60.0) % 60 == 0:
			var line := "PT boars t=%.1f hero=%s hp=%.0f st=%.0f lock=%s" % [_time - t0, hero.state_name(), hero.hp, hero.stamina,
				str(cam.lock_target.name if cam.lock_target else "-")]
			for e in alive:
				var bb := e as Boar
				line += " | %s %s d=%.1f hp=%.0f stg=%.2f tok=%s pk=%s" % [bb.name.right(4), bb.state_name(),
					Combat.flat(bb.global_position - hp_).length(), bb.hp, bb.stagger, str(bb.pack.holds_token(bb) if bb.pack else false),
					String(bb.pack.state_name()) if bb.pack else "-"]
			print(line)
		# a parry's guard: held 0.45 s, then let go
		if guard_t >= 0.0 and _time - guard_t > 0.45:
			hero.inp.bot[&"guard"] = false
			guard_t = -1.0
		# 1) a charge or a gore about to land
		var threat: Boar = null
		var ttc := INF
		var windup: Boar = null
		for e in alive:
			var b := e as Boar
			if b.st == Boar.CHARGE and not b._ch_resolved:
				var d := Combat.flat(hp_ - b.global_position)
				var along := d.dot(b._ch_dir)
				var lat := (d - b._ch_dir * along).length()
				if along > 0.0 and lat < 1.4:
					var tt := (along - 0.36 - Boar.HIT_REACH) / maxf(b._ch_speed, 1.0)
					if tt < ttc:
						ttc = tt
						threat = b
			elif b.st == Boar.GORE and b.telegraph_left() > 0.0 and b.telegraph_left() < ttc:
				ttc = b.telegraph_left()
				threat = b
			elif b.st == Boar.WINDUP:
				windup = b
		if threat != null:
			hero.inp.bot[&"attack"] = false
			hero.debug_move = Vector2.ZERO
			if cam.lock_target != threat:
				cam.lock_on(threat)
			var at_rock := rock_spot != Vector3.INF and threat.st == Boar.CHARGE and Combat.flat(hp_ - rock_spot).length() < 1.8
			if at_rock and rolled_for != threat and ttc <= 0.24 and hero.stamina >= 22.0:
				rolled_for = threat
				rock_spot = Vector3.INF
				var side := Vector3(-threat._ch_dir.z, 0.0, threat._ch_dir.x)
				hero.debug_move = _stick_to(hp_ + side * 3.0)
				await _tap(&"dodge", 0.04)
				hero.debug_move = Vector2.ZERO
				stats["rolls"] += 1
			elif not at_rock and ttc <= 0.09 and guard_t < 0.0:
				hero.inp.bot[&"guard"] = true
				guard_t = _time
			continue
		if guard_t >= 0.0:
			continue
		# 2) a wind-up: the lock turns him to it; he stands (at the rock when he is at it)
		if windup != null:
			hero.inp.bot[&"attack"] = false
			if cam.lock_target != windup:
				cam.lock_on(windup)
			hero.debug_move = Vector2.ZERO
			continue
		# 3) punish: staggered, stunned or recovering within reach
		var prey: Boar = null
		var pd := INF
		var near: Boar = null
		var nd := INF
		for e in alive:
			var b := e as Boar
			var d3 := Combat.flat(b.global_position - hp_).length()
			if d3 < nd:
				nd = d3
				near = b
			var open := b.stagger > 0.0 or b.is_stunned() or b.st == Boar.RECOVER or b.st == Boar.SKID
			if open and d3 < 6.0 and d3 < pd:
				pd = d3
				prey = b
		if prey != null:
			if cam.lock_target != prey:
				cam.lock_on(prey)
			hero.debug_move = _stick_to(prey.global_position) if pd > 2.0 else Vector2.ZERO
			if atk_cd <= 0.0 and pd < 3.0:
				atk_cd = 0.1
				hero.inp.bot[&"attack"] = not hero.inp.bot[&"attack"]
			continue
		# 4) nothing to do: stand, facing the nearest
		hero.inp.bot[&"attack"] = false
		hero.debug_move = Vector2.ZERO
		if near != null and cam.lock_target != near:
			cam.lock_on(near)
	hero.inp.bot_clear()
	hero.debug_move = Vector2.ZERO
	cam.lock_on(null)
	hero.hurt.disconnect(cb_h)
	hero.parried.disconnect(cb_p)
	var crashes := 0
	for f in foes:
		if is_instance_valid(f):
			crashes += (f as Boar).crashes
	stats["time"] = _time - t0
	stats["bites"] = hurt[0]
	stats["parries"] = parried[0]
	stats["crashes"] = crashes - crash0
	return stats


## Follows XZ waypoints (CORE's _follow: a waypoint counts once close or passed, a step to the side round a trunk or a
## stone when stuck), stopping to fight whatever hunts him on the way, then on from the nearest waypoint ahead.
## False on a fall, a timeout or 4 s stuck.
func _travel(pts: Array[Vector2], timeout: float, sprint: bool = false) -> bool:
	if pts.is_empty():
		return true
	var t0 := _time
	var i := _nearest_ahead(pts)
	var still := 0.0
	var side_t := 0.0
	var side_sgn := 1.0
	var unsticks := 0
	var last := hero.global_position
	while i < pts.size():
		if not hero.is_alive():
			hero.debug_move = Vector2.ZERO
			return false
		if _time - t0 > timeout:
			hero.debug_move = Vector2.ZERO
			hero.inp.bot[&"sprint"] = false
			print("PT travel timeout at %s heading to %s" % [str(hero.global_position.snapped(Vector3.ONE * 0.1)), str(pts[i])])
			return false
		var foes := _threats()
		if not foes.is_empty():
			hero.inp.bot[&"sprint"] = false
			var tf := _time
			await _fight_now(foes, _cur)
			t0 += _time - tf
			if not hero.is_alive():
				return false
			i = _nearest_ahead(pts)
			still = 0.0
			last = hero.global_position
			continue
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
			var dirv := to.normalized()
			hero.debug_move = _stick_to(p + dirv.cross(Vector3.UP) * side_sgn * 2.0 + dirv * 0.3)
			side_t -= get_physics_process_delta_time()
		else:
			hero.debug_move = _stick_to(tgt)
		hero.inp.bot[&"sprint"] = sprint and hero.stamina > 30.0
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		var moved := Combat.flat(hero.global_position - last).length()
		last = hero.global_position
		still = still + dt if moved < 0.5 * dt else 0.0
		if still > 0.8 and side_t <= 0.0 and unsticks < 8:
			unsticks += 1
			side_t = 0.6
			side_sgn = -side_sgn
		if still > 4.0:
			print("PT travel stuck at %s heading to %s: state=%s motion=%s" % [str(hero.global_position.snapped(Vector3.ONE * 0.1)), str(pts[i]),
				hero.state_name(), str(hero.motion_state)])
			hero.debug_move = Vector2.ZERO
			hero.inp.bot[&"sprint"] = false
			return false
	hero.debug_move = Vector2.ZERO
	hero.inp.bot[&"sprint"] = false
	return true


func _v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Walks up to a pack until it notices him, then fights it to the end (several rounds if it breaks off).
func _hunt_pack(pk: BeastPack, why: String, timeout: float = 200.0, rock_spot: Vector3 = Vector3.INF) -> bool:
	var t0 := _time
	while pk != null and pk.alive_count() > 0 and hero.is_alive() and _time - t0 < timeout:
		var foes := _threats()
		if not foes.is_empty():
			await _fight_now(foes, why, rock_spot)
			rock_spot = Vector3.INF
			continue
		var tgt: Vector3 = pk.home
		for m in pk.alive_members():
			tgt = (m as Node3D).global_position
			break
		if Combat.flat(tgt - hero.global_position).length() > 3.0:
			hero.debug_move = _stick_to(tgt)
		else:
			hero.debug_move = Vector2.ZERO
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	return pk == null or pk.alive_count() == 0


# --- the run -------------------------------------------------------------------------------------------------------

func _play() -> void:
	for i in 20:
		await get_tree().physics_frame
	hero = main.get("hero")
	cam = main.get("cam")
	world = main.get("world")
	_pt_t0 = _time
	_enc = EncHelper.new()
	_enc.name = "EncHelper"
	add_child(_enc)
	_enc.main = main
	_enc.hero = hero
	_enc.cam = cam
	_enc.world = world
	Game.hero_died.connect(func() -> void:
		_deaths += 1
		_died = true
		_mark("hero_died"))
	Game.labor_card.connect(func(i: int, t: String) -> void:
		_cards.append(i)
		print("PT labour card %d %s" % [i, t]))
	Game.boss_started.connect(func(nm: String, _b: Node) -> void:
		_boss.append("start")
		_boss_t = _time
		print("PT boss_started %s" % nm))
	Game.boss_ended.connect(func(v: bool) -> void:
		_boss.append("end_%s" % str(v))
		print("PT boss_ended victory=%s" % str(v)))
	Game.message.connect(func(t: String, s: String, k: String) -> void:
		_hints += 1
		_msg_t = _time
		print("PT message [%s] %s / %s" % [k, t, s]))
	Game.phase_changed.connect(func(ph: int) -> void:
		if ph == Game.Phase.VICTORY:
			_victory_t = _time)
	# --- the title, "Comenzar"
	_cur = "title"
	var title_ok: bool = await _until(func() -> bool: return Game.phase == Game.Phase.TITLE, 5.0)
	await _wait(1.6)
	await _shot("title")
	var ui = Game.ui
	if ui != null and ui.has_method("begin_game"):
		ui.call("begin_game")
	else:
		main.call("start_game")
	var play_ok: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY, 4.0)
	await _wait(1.2)
	var start: Transform3D = world.call("player_start")
	var on_pier := Combat.flat(hero.global_position - start.origin).length() < 0.6 and hero.is_on_floor()
	await _shot("pier")
	_step("title", title_ok and play_ok and on_pier, "title=%s play=%s on_the_pier=%s" % [str(title_ok), str(play_ok), str(on_pier)])
	# --- the village
	_cur = "village"
	var leg: Array[Vector2] = [Vector2(14, 120), Vector2(14, 108)]
	leg.append_array(_path_pts(0, 0, 4))
	var ok := await _travel(leg, 60.0)
	await _shot("village")
	_step("village", ok, "at %s" % str(hero.global_position.snapped(Vector3.ONE * 0.1)))
	# --- a cat
	_cur = "cat"
	await _pet_cat()
	# --- the road, the wolves, the fields, the passage, the thumb, the altar, the boulder, the lion, the way back
	var stage := ROAD
	var guard := 0
	while stage < END and guard < 30:
		guard += 1
		_died = false
		var sok := false
		match stage:
			ROAD:
				sok = await _st_road()
			PASSAGE:
				sok = await _st_passage()
			THUMB:
				sok = await _st_thumb()
			ALTAR:
				sok = await _st_altar()
			BOULDER:
				sok = await _st_boulder()
			LION:
				sok = await _st_lion()
			PELT:
				sok = await _st_pelt()
			RETURN_TRIP:
				sok = await _st_return()
			BOAT:
				sok = await _st_boat()
		if stage == BOAT:
			break
		if _died or not hero.is_alive():
			# fallen: back at the last altar he prayed at (or the pier); on from the stage that starts there
			var back: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY and hero.is_alive(), 12.0)
			await _wait(0.6)
			_shot("respawn")
			print("PT respawned=%s at %s checkpoint=%s (stage %d)" % [str(back), str(hero.global_position.snapped(Vector3.ONE * 0.1)),
				str(Game.checkpoint.get("title") if Game.checkpoint != null else "none"), stage])
			stage = _stage_after_respawn()
			continue
		if not sok:
			print("PT abort at stage %d" % stage)
			break
		stage += 1
	await _wait(0.5)
	_finish()


## Where a respawned hero picks the run up again.
func _stage_after_respawn() -> int:
	var cp = Game.checkpoint
	if cp == null or not is_instance_valid(cp):
		return ROAD
	var cave: Dictionary = world.call("cave")
	var sealed: bool = (cave["boulder"] as Node3D).call("is_blocking", cave["seal_b"], 1.2)
	return LION if sealed else BOULDER


func _pet_cat() -> void:
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
		_step("cat", false, "no cats")
		return
	var reached := false
	var t0 := _time
	while _time - t0 < 25.0:
		var cp: Vector3 = cat.get("pos")
		if Combat.flat(cp - hero.global_position).length() < 1.05:
			reached = true
			break
		hero.debug_move = _stick_to(cp)
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	await _wait(0.2)
	var target_is_cat: bool = hero.interact_target == cat.get("rig")
	hero.inp.bot[&"interact"] = true
	var saw_pet := false
	var purred := false
	var shot := false
	t0 = _time
	while _time - t0 < 2.4:
		await get_tree().physics_frame
		if String(hero.rig.get("action")) == "pet":
			saw_pet = true
		if int(cat.get("state")) == 6:
			purred = true
		if saw_pet and not shot and _time - t0 > 1.0:
			shot = true
			await _shot("cat")
	hero.inp.bot[&"interact"] = false
	await _wait(0.5)
	_step("cat", reached and target_is_cat and saw_pet and purred, "reached=%s target_is_cat=%s hero_rig_pet=%s purred=%s (%.1f m away)" % [
		str(reached), str(target_is_cat), str(saw_pet), str(purred), best])


## The main road from wherever he is to the passage's south rim: the forest, the first wolf pack, the fields.
func _st_road() -> bool:
	var pk := _enc._pack_at(PACK1, &"wolf")
	var road := _path_pts(0)
	# the forest edge (north gate) first, for its picture
	var to_forest: Array[Vector2] = []
	for k in road.size():
		to_forest.append(road[k])
		if k == 6:
			break
	_cur = "road"
	var ok := true
	if _nearest_ahead(road) <= 6:
		ok = await _travel(to_forest, 60.0)
		if not ok:
			return false
		await _shot("forest_road")
	# on along the road: the pack notices him by its clearing
	_cur = "wolves"
	var to_fields: Array[Vector2] = []
	for k in range(0, 10):
		to_fields.append(road[k])
	if _nearest_ahead(road) <= 9:
		ok = await _travel(to_fields, 90.0)
		if not ok:
			return false
	# (if they never came out, he goes to them)
	if pk != null and pk.alive_count() > 0:
		ok = await _hunt_pack(pk, "wolves")
		if not ok:
			return false
	await _wait(0.4)
	await _shot("wolves_beaten")
	_step("wolves", pk != null and pk.alive_count() == 0 and hero.is_alive(), "pack=%s alive=%d attacks=%d bites=%d" % [
		str(pk != null), pk.alive_count() if pk else -1, pk.attacks if pk else 0, pk.hits if pk else 0])
	# the fields west of the forest (where the wheat field is planned) and the west ramp to the rim
	_cur = "wheat"
	var to_wheat: Array[Vector2] = []
	for k in range(9, 12):
		to_wheat.append(road[k])
	ok = await _travel(to_wheat, 40.0)
	if not ok:
		return false
	await _shot("fields")
	# FINAL: off the road a few steps into the wheat at a walk: the free hand goes out over the ears (Gladiator)
	var brush := await _brush_walk([Vector2(-60.0, 23.0), Vector2(-71.0, 27.0)])
	var rest: Array[Vector2] = []
	for k in range(12, road.size()):
		rest.append(road[k])
	ok = await _travel(rest, 60.0)
	await _shot("south_rim")
	_step("wheat", ok and brush > 0.8, "at %s, through the wheat field: the hand brushed the ears (brush %.2f)" % [str(hero.global_position.snapped(Vector3.ONE * 0.1)), brush])
	return ok and brush > 0.8


## FINAL: walks (stick at 0.45: walking pace) through `pts` and returns how far the hand's brush went (0..1); a shot when
## it is fully out.
func _brush_walk(pts: Array) -> float:
	var best := 0.0
	var shot := false
	for q: Vector2 in pts:
		var p: Vector3 = world.call("ground", Vector3(q.x, 0.0, q.y))
		var t0 := _time
		while _time - t0 < 20.0 and Combat.flat(p - hero.global_position).length() > 0.6:
			hero.debug_move = _stick_to(p) * 0.45
			await get_tree().physics_frame
			var b: float = hero.rig.brush_amount()
			best = maxf(best, b)
			if b > 0.95 and not shot:
				shot = true
				_shot("wheat_brush")
	hero.debug_move = Vector2.ZERO
	return best


## The broken passage by the two bronze rings (CORE's walk moves).
func _st_passage() -> bool:
	_cur = "passage"
	var rings: Array = world.call("anchors")
	var stack: Node3D = rings[1]
	var north: Node3D = rings[2]
	var south_p: Vector3 = (world.call("places") as Dictionary)["passage_south"]
	await _place(south_p, stack.call("chain_point"))
	cam.aim_at(stack.call("chain_point"))
	await _wait(0.35)
	await _shot("passage_aim")
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
	await _shot("passage_stack")
	var bit_b := false
	if cand:
		bit_b = await _throw_at(north, 0.1)
	var on_north: bool = await _until(func() -> bool: return hero.state == Hero.St.MOVE and hero.is_on_floor() and hero.global_position.z < -24.0, 5.0)
	await _wait(0.4)
	await _shot("passage_north")
	var ok: bool = bit_a and on_stack and cand and bit_b and on_north
	_step("passage", ok, "bit_stack=%s on_stack=%s north_cand=%s bit_north=%s on_north_rim=%s" % [str(bit_a), str(on_stack), str(cand), str(bit_b), str(on_north)])
	return ok


## The thumb path: the boar of the first clearing (charged into a standing rock), the herd of two, on to the altar.
func _st_thumb() -> bool:
	_cur = "boars"
	var path := _path_pts(1)
	var b1 := _enc._pack_at(BOAR1, &"boar")
	var herd := _enc._pack_at(HERD, &"boar")
	var ok := true
	if b1 != null and b1.alive_count() > 0:
		# from the rim landing (out of the boar's notice) to a standing rock of its clearing: its charge will be
		# rolled aside there, into the rock
		var b := _enc._boar_of(b1)
		var rs: Array = _enc._rock_spot(b1.home, b) if b != null else []
		var spot := Vector3.INF
		if not rs.is_empty():
			spot = rs[1]
			var t0 := _time
			while _time - t0 < 12.0 and Combat.flat(spot - hero.global_position).length() > 0.4:
				if b.st == Boar.WINDUP or b.st == Boar.CHARGE:
					break
				hero.debug_move = _stick_to(spot)
				await get_tree().physics_frame
			hero.debug_move = Vector2.ZERO
			await _shot("boar_clearing")
		ok = await _hunt_pack(b1, "boar", 200.0, spot)
		if not ok:
			return false
	await _shot("boar_beaten")
	if herd != null and herd.alive_count() > 0:
		var to_herd: Array[Vector2] = []
		for k in range(1, 5):
			to_herd.append(path[k])
		ok = await _travel(to_herd, 60.0)
		if not ok:
			return false
		ok = await _hunt_pack(herd, "herd")
		if not ok:
			return false
	await _wait(0.4)
	await _shot("herd_beaten")
	var crashes := 0
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Boar:
			crashes += (n as Boar).crashes
	_step("boars", (b1 == null or b1.alive_count() == 0) and (herd == null or herd.alive_count() == 0) and hero.is_alive(),
		"clearing_boar_dead=%s herd_dead=%s (boars still in the tree that crashed into stone: %d)" % [str(b1 != null and b1.alive_count() == 0),
		str(herd != null and herd.alive_count() == 0), crashes])
	# on to the ridge meadow
	var rest: Array[Vector2] = []
	for k in range(4, path.size()):
		rest.append(path[k])
	ok = await _travel(rest, 80.0)
	return ok


func _sierra() -> Node3D:
	for al in world.call("altars"):
		if String(al.get("title")) == "Altar de la Sierra":
			return al
	return null


func _st_altar() -> bool:
	_cur = "altar"
	var altar := _sierra()
	if altar == null:
		_step("altar", false, "no Altar de la Sierra")
		return false
	var front: Vector3 = altar.global_transform * Vector3(0, 0, 2.0)
	await _walk_to(front, 0.5, 10.0)
	await _face(altar.global_position)
	var hp0 := hero.hp
	var target_is_altar: bool = hero.interact_target == altar
	await _tap(&"interact", 0.1)
	await _wait(0.5)
	await _shot("altar")
	await _wait(0.8)
	var healed: bool = hero.hp >= hero.max_hp - 0.01
	var checkpoint: bool = Game.checkpoint == altar
	_step("altar", target_is_altar and healed and checkpoint, "target_is_altar=%s healed=%s (hp %.0f -> %.0f) checkpoint=%s" % [
		str(target_is_altar), str(healed), hp0, hero.hp, str(checkpoint)])
	return target_is_altar and checkpoint


## The meadow path to mouth B and the boulder hauled into the crack (CORE's boulder routine, walking, no teleport).
func _st_boulder() -> bool:
	_cur = "boulder"
	var cave: Dictionary = world.call("cave")
	var eb: Vector3 = cave["entrance_b"]
	var out: Vector3 = Combat.flat(cave["dir_b"]).normalized()
	var leg := _path_pts(3)
	leg.append(Vector2(eb.x + out.x * 2.5, eb.z + out.z * 2.5))
	var ok := await _travel(leg, 60.0)
	if not ok:
		return false
	await _face((cave["boulder"] as Node3D).global_position)
	await _shot("mouth_b")
	var sealed: bool = await _t_boulder()
	await _shot("sealed")
	_step("boulder", sealed, "(the boulder line above)")
	return sealed


## Into the arena (through the crack's tunnel when he stands in it, else round by mouth A), then the fight.
func _st_lion() -> bool:
	_cur = "cave"
	var enc: Node = main.get_node_or_null("LionEncounter")
	if enc == null:
		_step("cave", false, "no lion encounter")
		return false
	var cave: Dictionary = world.call("cave")
	var lion: Lion = enc.get("lion")
	var cards0 := _cards.count(1)
	var fights0 := int(enc.get("fights"))
	var in_b := Combat.flat(hero.global_position - (cave["entrance_b"] as Vector3)).length() < 4.5 \
		and float(world.call("cave_amount", hero.global_position)) > 0.3
	var route: Array[Vector2] = []
	if in_b:
		route.append(_v2(cave["inner_b"]))
	else:
		var altar_side: Array[Vector2] = [Vector2(-6, -71), Vector2(-18, -75)]
		route.append_array(altar_side)
		route.append_array(_path_pts(2))
		route.append(_v2(cave["entrance_a"]))
		route.append(_v2(cave["inner_a"]))
	var ok := await _travel(route, 60.0)
	await _shot("tunnel")
	# into the arena until the lion wakes
	var c: Vector3 = cave["arena_center"]
	var t0 := _time
	while int(enc.get("state")) == 0 and _time - t0 < 15.0 and hero.is_alive():
		hero.debug_move = _stick_to(c)
		await get_tree().physics_frame
	hero.debug_move = Vector2.ZERO
	var woke := int(enc.get("state")) != 0
	var card_ok: bool = await _until(func() -> bool: return _cards.count(1) > cards0 or fights0 > 0, 2.0)
	_step("cave", ok and woke and (card_ok or fights0 > 0), "via=%s woke=%s labour_card=%s mouth_b_open=%s" % [
		"crack" if in_b else "mouth A", str(woke), str(_cards.count(1) > cards0), str(enc.call("mouth_b_open"))])
	if not woke:
		return false
	# the fight (the lion bot's brain)
	_cur = "lion"
	if _lb == null:
		_lb = LionHelper.new()
		_lb.name = "LionHelper"
		add_child(_lb)
	_lb.encounter = enc
	_lb.hero = hero
	_lb.cam = cam
	_lb.world = world
	_lb.lion = lion
	_lb.cave = cave
	_lb._bot_reset()
	var tf := _time
	var deaths0 := _deaths
	while is_instance_valid(lion) and lion.alive and _time - tf < 600.0:
		if not hero.is_alive() or _died:
			return false
		await _lb._bot_tick()
	hero.debug_move = Vector2.ZERO
	hero.inp.bot_clear()
	var won := not is_instance_valid(lion) or not lion.alive
	_step("lion", won and _deaths == deaths0, "won=%s in %.0f s wrestles_won=%d lost=%d slams pounce=%d yank=%d fall=%d escaped=%s" % [str(won),
		_time - tf, lion.wrestles_won if is_instance_valid(lion) else -1, lion.wrestles_lost if is_instance_valid(lion) else -1,
		lion.pounce_slams if is_instance_valid(lion) else -1, lion.yank_slams if is_instance_valid(lion) else -1,
		lion.fall_stuns if is_instance_valid(lion) else -1, str(lion.escaped) if is_instance_valid(lion) else "?"])
	return won


func _st_pelt() -> bool:
	_cur = "pelt"
	var pelt: bool = await _until(func() -> bool: return hero.outfit == &"lion" and hero.rig.outfit == &"lion", 12.0)
	await _wait(1.0)
	await _shot("pelt")
	var vic: bool = await _until(func() -> bool: return Game.phase == Game.Phase.VICTORY, 8.0)
	var roam: bool = await _until(func() -> bool: return Game.phase == Game.Phase.PLAY, 15.0)
	var boat: Node3D = world.call("boat")
	var ready := boat != null and bool(boat.get("ready_to_sail"))
	_step("pelt", pelt and vic and roam and ready, "pelt=%s victory=%s free_roam=%s boat_ready=%s boss=%s" % [str(pelt), str(vic), str(roam), str(ready), str(_boss)])
	return pelt and roam


## Out through mouth A, over the ridge meadow, off the escarpment, south through the forest (west of the second pack)
## to the main road, down through the village to the pier.
func _st_return() -> bool:
	_cur = "return"
	var cave: Dictionary = world.call("cave")
	var route: Array[Vector2] = [_v2(cave["inner_a"]), _v2(cave["entrance_a"])]
	var p2 := _path_pts(2)
	p2.reverse()
	route.append_array(p2)
	var ok := await _travel(route, 60.0)
	await _shot("out_of_the_cave")
	if not ok:
		_step("return", false, "stuck leaving the cave")
		return false
	var down: Array[Vector2] = [Vector2(-24, -66), Vector2(-28, -50)]
	ok = await _travel(down, 30.0)
	await _shot("escarpment")
	var forest: Array[Vector2] = [Vector2(-30, -30), Vector2(-32, -10), Vector2(-33, 9)]
	ok = ok and await _travel(forest, 60.0)
	await _shot("forest_back")
	var road := _path_pts(0, 0, 9)
	road.reverse()
	road.append(Vector2(14, 108))
	road.append(Vector2(14, 120))
	ok = ok and await _travel(road, 90.0, true)
	await _shot("village_back")
	_step("return", ok, "at %s" % str(hero.global_position.snapped(Vector3.ONE * 0.1)))
	return ok


func _st_boat() -> bool:
	_cur = "boat"
	var boat: Node3D = world.call("boat")
	var dock := boat.global_position
	await _walk_to(dock + Vector3(1.4, 0, 0), 0.35, 25.0)
	await _face(dock)
	var aimed: bool = await _until(func() -> bool: return hero.interact_target == boat, 2.0)
	await _shot("boat_prompt")
	var cards0 := _cards.count(2)
	await _tap(&"interact", 0.05)
	var teaser: bool = await _until(func() -> bool: return _cards.count(2) == cards0 + 1 and bool(boat.get("sailing")), 2.0)
	# the reloaded scene must not start a second bot
	Game.args.erase("ptbot")
	await _wait(3.2)
	await _shot("lerna_card")
	var old_main = main
	var faded: bool = await _until(func() -> bool: return not is_instance_valid(boat) or bool(boat.get("_done")), 14.0)
	# the scene reloads: let go of the old one
	hero = null
	cam = null
	var title: bool = await _until(func() -> bool: return Game.phase == Game.Phase.TITLE and is_instance_valid(Game.main) and Game.main != old_main, 30.0)
	await _wait(1.5)
	await _shot("title_again")
	_step("boat", aimed and teaser and faded and title, "zarpar=%s lerna_card=%s faded=%s back_to_title=%s cards=%s" % [str(aimed), str(teaser), str(faded), str(title), str(_cards)])
	return aimed and teaser and title
