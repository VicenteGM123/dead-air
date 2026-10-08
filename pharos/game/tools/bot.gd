extends Node
## Autoplayer for tests: builds in a sensible order by day, fights at night, logs the run.
##   godot --headless --path . -- bot=1 speed=4 [build=greedy|none] [fight=1]

var main: Node
var hero: Hero
var _target_spot: BuildSpot = null
var _phase_t := 0.0
var _log_t := 0.0
var _speed := 1.0
var _fight := true
var _plan := "greedy"
var _night_log := {}
var _start_ms := 0
var _wait_t := 0.0
var _last_phase := -1

const ORDER := ["tower", "house", "wall", "barracks", "pharos", "farm", "house", "tower", "dock", "wall", "tower", "barracks", "house", "farm", "dock"]


func _ready() -> void:
	main = get_parent()
	hero = main.hero
	_speed = float(Game.arg("speed", "4"))
	_fight = Game.arg("fight", "1") == "1"
	_plan = Game.arg("build", "greedy")
	Game.time_scale_target = _speed
	_start_ms = Time.get_ticks_msec()
	Game.phase_changed.connect(_on_phase)
	print("[bot] start, coins=%d speed=%.1f" % [Game.coins, _speed])


func _on_phase(p: int) -> void:
	_phase_t = 0.0
	var names := ["BOOT", "TITLE", "DAY", "DUSK", "NIGHT", "DAWN", "BLESSING", "VICTORY", "DEFEAT"]
	print("[bot] t=%.0fs phase=%s night=%d coins=%d pharosHP=%s heroHP=%.0f kills=%d" % [
		(Time.get_ticks_msec() - _start_ms) / 1000.0 * _speed, names[p], Game.night, Game.coins,
		str(snapped(Game.pharos.hp, 1)) if Game.pharos else "-", hero.hp, Game.stats["kills"]])
	if p == Game.Phase.BLESSING:
		await get_tree().create_timer(0.5).timeout
		var pick: String = main._offered[0]
		print("[bot] blessing -> %s" % pick)
		main.choose_blessing(pick)
	elif p == Game.Phase.VICTORY or p == Game.Phase.DEFEAT:
		_summary(p == Game.Phase.VICTORY)


func _summary(win: bool) -> void:
	var built := []
	for sp in main.spots:
		if sp.building:
			built.append("%s%d%s" % [sp.type, sp.building.level, "" if sp.building.alive else "x"])
	print("[bot] RESULT %s nights=%d kills=%d deaths=%d coins=%d blessings=%s" % ["VICTORY" if win else "DEFEAT", Game.night, Game.stats["kills"], Game.stats["deaths"], Game.coins, str(Game.blessings)])
	print("[bot] buildings: %s" % " ".join(built))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _physics_process(delta: float) -> void:
	_phase_t += delta
	Game.time_scale_target = _speed
	match Game.phase:
		Game.Phase.DAY:
			_day(delta)
		Game.Phase.NIGHT:
			_night(delta)
		_:
			hero.touch_move = Vector2.ZERO
	_log_t -= delta
	if _log_t <= 0.0 and Game.phase == Game.Phase.NIGHT:
		_log_t = 10.0
		print("[bot]   night %d: alive=%d remaining=%d pharos=%.0f heroHP=%.0f favor=%.0f" % [Game.night, Game.enemy_count(), main.waves.remaining(), Game.pharos.hp, hero.hp, hero.favor])


func _next_spot() -> BuildSpot:
	if _plan == "none":
		return null
	for t in ORDER:
		for sp: BuildSpot in main.spots:
			if sp.type != t or not sp.is_unlocked() or sp.is_maxed():
				continue
			if sp.type == "pharos" and Game.night < 1:
				continue
			# Only upgrade non-pharos things once everything of that type exists.
			if sp.level() >= 1 and sp.type != "pharos" and _has_empty(t):
				continue
			if sp.cost() - sp.paid <= Game.coins:
				return sp
	return null


func _has_empty(t: String) -> bool:
	for sp: BuildSpot in main.spots:
		if sp.type == t and sp.is_unlocked() and sp.level() == 0:
			return true
	return false


func _day(delta: float) -> void:
	if _phase_t < 0.5:
		return
	if _target_spot == null or _target_spot.is_maxed() or _target_spot.cost() - _target_spot.paid > Game.coins:
		_target_spot = _next_spot()
	if _target_spot:
		if _go_to(_target_spot.global_position, _target_spot.interact_range() * 0.6):
			var lv := _target_spot.level()
			_target_spot.interact_hold(delta, hero)
			if _target_spot.level() != lv:
				print("[bot]   built %s -> lv%d (coins %d)" % [_target_spot.type, _target_spot.level(), Game.coins])
				_target_spot = null
		return
	# Nothing affordable: blow the horn.
	if _go_to(main.horn.global_position, 1.6):
		_wait_t += delta
		if _wait_t > 0.3:
			_wait_t = 0.0
			main.call_night()


func _go_to(p: Vector3, tol: float) -> bool:
	var d := p - hero.global_position
	d.y = 0.0
	if d.length() <= tol:
		hero.touch_move = Vector2.ZERO
		return true
	hero.touch_move = Vector2(d.x, d.z).normalized()
	# Teleport if stuck far away (test convenience).
	if _phase_t > 6.0 and d.length() > tol:
		hero.teleport(p - d.normalized() * tol * 0.5)
		_phase_t = 0.6
	return false


func _night(_delta: float) -> void:
	if not _fight or hero.state == Hero.S.DEAD:
		hero.touch_move = Vector2.ZERO
		return
	var e := Game.nearest(1, hero.global_position, 60.0, func(u): return not u.is_flying or true)
	if e == null:
		var back := Vector3(0, 0, 9.0) - hero.global_position
		hero.touch_move = Vector2(back.x, back.z).normalized() if back.length() > 2.0 else Vector2.ZERO
		return
	var d: Vector3 = e.global_position - hero.global_position
	d.y = 0.0
	if d.length() > 2.2:
		hero.touch_move = Vector2(d.x, d.z).normalized()
	else:
		hero.touch_move = Vector2.ZERO
		if hero.state == Hero.S.NORMAL:
			if hero.favor >= hero.favor_max():
				hero._start_cast()
			elif hero.bash_cd <= 0.0 and randf() < 0.2:
				hero._start_bash(d.normalized())
			else:
				hero._start_attack(d.normalized())
		elif hero.state == Hero.S.ATTACK and hero.rig.ap() > 0.5:
			hero.combo_queued = true
