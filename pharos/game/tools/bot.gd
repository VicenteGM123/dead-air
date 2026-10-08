extends Node
## Autoplayer for balance tests. It plays like a reasonable human: by day it grows the economy and builds where the
## marked beaches say the next night will strike, upgrades the lighthouse when it opens useful plots, and blows the
## horn when the coins run out; by night it fights on the most dangerous front and falls back to heal when hurt.
##
##   godot --headless --path . -- bot=1 speed=3 [build=greedy|econ|defense|lazy|miser|none] [fight=2|1|0]
##       [bless=id,id] [rseed=N] [quit=1] [retry=N] [human=1]
##   build: greedy = balanced human (default) · econ = economy first · defense = defenses only · lazy = careless:
##          spends its coins on whatever plots it walks past, no plan · miser = spends at most half of its coins
##          each day · none = never builds.
##   fight: 2 = good player (combo, lens flash, beam, retreats to heal) · 1 = casual (combo + beam, nearest enemy,
##          never retreats) · 0 = never fights (stays by the horn). Fight 1 and 2 dash out of the Hydra's violet
##          ground marks once they have seen them (~0.25 s).
##   human=1: no hidden information: only sees creatures within 30 m and waits at the plaza between groups.
##   retry=N: on a defeat, press "Reintentar la noche" up to N times (checks that the dusk state comes back).
##   tests: checks=1 (verify every blessing's numbers, then quit) · info=1 (dump lanes and plots, then quit)
##          prebuild=barracks:2,wall:1 (force-build those plots) · debug=1 (log hero and hoplites every 3 s)
##          crittest=<name> (run res://tools/crit_<name>.gd instead of playing)
##          plus main.gd's startnight=N, village=1, pl=N, coins=N, hpmult=X.
## Logs one "[bot] NIGHT" line per night and a final "[bot] RESULT" line; "[bot] WARN" lines flag suspected bugs
## (creatures stuck or walking past a standing wall, Fanós stuck, nights that never end, dawn not restoring the
## village). Balance summaries parse these line formats: keep them stable.

const PHASES := ["BOOT", "TITLE", "DAY", "DUSK", "NIGHT", "DAWN", "BLESSING", "VICTORY", "DEFEAT"]
const BLESS_PREF := ["athena", "artemis", "hephaestus", "apollo", "demeter", "ares", "zeus", "poseidon", "hestia", "hermes"]

var main: Node
var hero: Hero
var _speed := 3.0
var _fight := 2
var _plan := "greedy"
var _target_spot: BuildSpot = null
var _phase_t := 0.0
var _game_t := 0.0
var _log_t := 0.0
var _scan_t := 0.0
var _retreat := false
var _horn_t := 0.0
var _budget := 0
var _day_spent := 0
var _day_coins := 0
var _econ_spent := 0
var _done := false
# Per-night bookkeeping.
var _n := {}
var _night_start_t := 0.0
var _seen := {} # enemy -> [last pos, still seconds]
var _tower_cd := {}
var _soldier_cd := {}
var _warned := {}
var _results: Array = []
var _last_pos := Vector3.ZERO
var _cur_target: Unit = null
var _idle_t := 0.0
var _force_side := 0.0
var _force_t := 0.0
var _last_side := 1.0
var _prog_best := INF
var _prog_t := 0.0
var _stuck_t := 0.0
var _retries := 0
var _human := false
var _retry_expect := {}


func _ready() -> void:
	main = get_parent()
	hero = main.hero
	_speed = float(Game.arg("speed", "3"))
	_fight = int(Game.arg("fight", "2"))
	_plan = Game.arg("build", "greedy")
	_retries = int(Game.arg("retry", "0"))
	_human = Game.arg("human", "0") == "1"
	if Game.arg("rseed", "") != "":
		seed(int(Game.arg("rseed")))
	var crit := "res://tools/crit_%s.gd" % String(Game.arg("crittest", ""))
	if Game.arg("crittest", "") != "" and ResourceLoader.exists(crit):
		add_child(load(crit).new())
		set_physics_process(false)
		return
	Game.time_scale_target = _speed
	Game.phase_changed.connect(_on_phase)
	hero.damaged.connect(_on_hero_hurt)
	# prebuild=barracks:2,tower:1 · force-build every unlocked plot of those types at that level (tests).
	for it in String(Game.arg("prebuild", "")).split(",", false):
		var kv := (it as String).split(":")
		for sp in main.spots:
			if sp.type == kv[0] and sp.is_unlocked():
				sp.force_build(int(kv[1]) if kv.size() > 1 else 1)
	for id in String(Game.arg("bless", "")).split(",", false):
		if Data.BLESSINGS.has(id):
			Game.take_blessing(id)
	if not Game.blessings.is_empty():
		for sp in main.spots:
			if sp.building:
				sp.building.refresh_max_hp()
		hero.refresh_stats()
	# goto=x,z · put Fanós there (screenshots); idle=1 · the bot does nothing at all.
	if Game.arg("goto", "") != "":
		var xz := String(Game.arg("goto")).split(",")
		hero.teleport(Vector3(float(xz[0]), 0, float(xz[1])))
		main.rig.snap()
	if Game.arg("info", "0") == "1":
		_dump_info()
	if Game.arg("checks", "0") == "1":
		set_physics_process(false)
		_checks()
		return
	Game.message.connect(_on_message)
	print("[bot] start build=%s fight=%d speed=%.1f coins=%d blessings=%s" % [_plan, _fight, _speed, Game.coins, str(Game.blessings)])
	if Game.phase == Game.Phase.DAY:
		_on_phase(Game.Phase.DAY)


# --- phases ------------------------------------------------------------------------------------------------

func _on_phase(p: int) -> void:
	_phase_t = 0.0
	_target_spot = null
	match p:
		Game.Phase.DAY:
			_check_dawn()
			_day_spent = 0
			_econ_spent = 0
			_day_coins = Game.coins
			_budget = Game.coins if _plan != "miser" else Game.coins / 2
			if not _retry_expect.is_empty():
				_check_retry()
		Game.Phase.NIGHT:
			_begin_night()
		Game.Phase.DAWN:
			_end_night()
		Game.Phase.BLESSING:
			call_deferred("_pick_blessing")
		Game.Phase.VICTORY, Game.Phase.DEFEAT:
			if p == Game.Phase.DEFEAT and Game.phase == Game.Phase.DEFEAT:
				_end_night(true)
				if _retries > 0:
					_retries -= 1
					_retry_later()
					return
			_summary(p == Game.Phase.VICTORY)


## Every morning: everything destroyed overnight must stand again, squads must be back, Fanós must be whole.
func _check_dawn() -> void:
	if _results.is_empty():
		return # no night fought yet in this run
	for sp in main.spots:
		var b: Building = sp.building
		if b == null:
			continue
		if not b.alive or b.hp < b.max_hp - 0.5:
			print("[bot] WARN dawn: %s not restored (alive=%s hp=%.0f/%.0f)" % [b.type, str(b.alive), b.hp, b.max_hp])
		if b is BarracksBuilding:
			var n := 0
			for so in (b as BarracksBuilding).soldiers:
				if is_instance_valid(so) and so.alive and so.visible:
					n += 1
			if n != int(Data.building_level("barracks", b.level)["soldiers"]):
				print("[bot] WARN dawn: barracks lv%d has %d hoplites standing" % [b.level, n])
	if hero.alive and hero.hp < hero.max_hp - 0.5 and hero.state != Hero.S.DEAD:
		print("[bot] WARN dawn: Fanós not healed (%.0f/%.0f)" % [hero.hp, hero.max_hp])


## retry=N: wait for the defeat screen, then press "Reintentar la noche" (through the UI when there is one).
func _retry_later() -> void:
	var snap: Dictionary = main._snap
	_retry_expect = {"coins": snap.get("coins", -1), "night": snap.get("night", -1), "levels": [], "favor": snap.get("favor", 0.0)}
	for st in snap.get("spots", []):
		_retry_expect["levels"].append(int(st["level"]))
	await get_tree().create_timer(3.0).timeout
	print("[bot] RETRY night %d (coins back to %d)" % [int(_retry_expect["night"]) + 1, int(_retry_expect["coins"])])
	if Game.hud and Game.hud.has_method("retry_night"):
		Game.hud.retry_night()
	else:
		main.retry_night()


## After a retry: the island must be exactly as it stood at dusk.
func _check_retry() -> void:
	var bad: Array = []
	if Game.coins != int(_retry_expect["coins"]):
		bad.append("coins %d != %d" % [Game.coins, int(_retry_expect["coins"])])
	if Game.night != int(_retry_expect["night"]):
		bad.append("night %d != %d" % [Game.night, int(_retry_expect["night"])])
	var lv: Array = _retry_expect["levels"]
	for i in mini(lv.size(), main.spots.size()):
		if main.spots[i].level() != int(lv[i]):
			bad.append("%s level %d != %d" % [main.spots[i].type, main.spots[i].level(), int(lv[i])])
	if absf(hero.favor - float(_retry_expect["favor"])) > 0.01:
		bad.append("llama %.1f != %.1f" % [hero.favor, float(_retry_expect["favor"])])
	if Game.enemy_count() != 0 or not hero.alive or not Game.pharos.alive:
		bad.append("enemies=%d hero_alive=%s pharos_alive=%s" % [Game.enemy_count(), str(hero.alive), str(Game.pharos.alive)])
	print("[bot] RETRY check %s" % ("ok" if bad.is_empty() else "FAIL " + ", ".join(bad)))
	_retry_expect = {}


func _pick_blessing() -> void:
	if Game.phase != Game.Phase.BLESSING or main._offered.is_empty():
		return
	var pick: String = main._offered[0]
	for id in BLESS_PREF:
		if main._offered.has(id):
			pick = id
			break
	main.choose_blessing(pick)


func _begin_night() -> void:
	_night_start_t = _game_t
	_retreat = false
	_seen.clear()
	_n = {"night": Game.night, "pharos_max": Game.pharos.max_hp, "pharos_min": Game.pharos.hp, "hero_min": hero.hp,
		"deaths0": Game.stats["deaths"], "kills0": Game.stats["kills"], "shots": 0, "swings": 0, "lost": 0,
		"coins": Game.coins, "spawned": 0, "slowed": 0, "hydra_summons": 0, "bolts0": Game.stats["bolts"], "dead_t": 0.0}
	for sp in main.spots:
		if sp.building and sp.building.alive and not sp.building.destroyed.is_connected(_on_destroyed):
			sp.building.destroyed.connect(_on_destroyed)
		if sp.building and not sp.building.damaged.is_connected(_on_building_hurt):
			sp.building.damaged.connect(_on_building_hurt)
	if main.waves.boss_spawned.is_connected(_on_boss) == false:
		main.waves.boss_spawned.connect(_on_boss)


func _on_message(text: String, _sub: String, _kind: String) -> void:
	if text.contains("prole") and not _n.is_empty():
		_n["hydra_summons"] = int(_n.get("hydra_summons", 0)) + 1
		print("[bot]   hydra summons its brood (alive=%d left=%d)" % [Game.enemy_count(), main.waves.remaining()])


func _on_hero_hurt(_u: Unit, amount: float) -> void:
	if not _n.is_empty():
		_n["hero_dmg"] = float(_n.get("hero_dmg", 0.0)) + amount


func _on_building_hurt(u: Unit, amount: float) -> void:
	if _n.is_empty():
		return
	var dm: Dictionary = _n.get("bdmg", {})
	var k: String = (u as Building).type
	dm[k] = int(dm.get(k, 0)) + int(round(amount))
	_n["bdmg"] = dm


func _on_destroyed(b: Building) -> void:
	if Game.phase == Game.Phase.NIGHT and not _n.is_empty():
		_n["lost"] = int(_n.get("lost", 0)) + 1
		var lt: Array = _n.get("lost_types", [])
		lt.append(b.type)
		_n["lost_types"] = lt


func _on_boss(b: Node3D) -> void:
	print("[bot]   hydra rises (hp %.0f) at t=%.0fs" % [(b as Unit).max_hp, _game_t - _night_start_t])


func _end_night(defeat: bool = false) -> void:
	if _n.is_empty():
		return
	var built := _village()
	var line := "[bot] NIGHT %d %s  dur=%.0fs  pharos_min=%.0f%%  lost=%d  hero_deaths=%d  hero_min=%.0f  hero_dmg=%.0f  kills=%d  tower_shots=%d  hoplite_swings=%d  coins_before=%d  village=%s" % [
		int(_n["night"]), "DEFEAT" if defeat else "ok", _game_t - _night_start_t, 100.0 * float(_n["pharos_min"]) / maxf(1.0, float(_n["pharos_max"])),
		int(_n["lost"]), Game.stats["deaths"] - int(_n["deaths0"]), float(_n["hero_min"]), float(_n.get("hero_dmg", 0.0)), Game.stats["kills"] - int(_n["kills0"]),
		int(_n["shots"]), int(_n["swings"]), int(_n["coins"]), built]
	print(line)
	print("[bot]   n%d building damage %s lost_types=%s" % [int(_n["night"]), str(_n.get("bdmg", {})), str(_n.get("lost_types", []))])
	var lost_inc := 0
	for t in _n.get("lost_types", []):
		if t == "house" or t == "farm" or t == "dock":
			lost_inc += int(Data.building_level(t, 1).get("income", 0))
	print("[bot]   n%d beams=%d hero_dead=%.0fs econ_lost=%d" % [int(_n["night"]), Game.stats["bolts"] - int(_n.get("bolts0", 0)), float(_n.get("dead_t", 0.0)), lost_inc])
	_results.append(line)
	_n = {}


func _village() -> String:
	var counts := {}
	var lv_sum := 0
	var n := 0
	for sp in main.spots:
		if sp.building and sp.type != "pharos":
			counts[sp.type] = int(counts.get(sp.type, 0)) + 1
			lv_sum += sp.building.level
			n += 1
	var unlocked := 0
	for sp in main.spots:
		if sp.is_unlocked() and sp.type != "pharos":
			unlocked += 1
	return "pl%d %d/%d plots (%d/%d total) lv%d %s" % [Game.pharos_level, n, unlocked, n, main.spots.size() - 1, lv_sum, str(counts)]


func _summary(win: bool) -> void:
	if _done:
		return
	_done = true
	var built := []
	for sp in main.spots:
		if sp.building:
			built.append("%s%d%s" % [sp.type, sp.building.level, "" if sp.building.alive else "x"])
	print("[bot] RESULT %s build=%s fight=%d night=%d time=%.0fs kills=%d deaths=%d coins_earned=%d coins=%d built=%d upgrades=%d blessings=%s" % [
		"VICTORY" if win else "DEFEAT", _plan, _fight, Game.night, _game_t, Game.stats["kills"], Game.stats["deaths"],
		Game.stats["coins_earned"], Game.coins, Game.stats["built"], Game.stats["upgrades"], str(Game.blessings)])
	print("[bot] buildings: %s" % " ".join(built))
	if Game.arg("quit", "1") == "1":
		await get_tree().create_timer(1.0 * _speed).timeout
		get_tree().quit()


# --- per frame ---------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Game.arg("idle", "0") == "1":
		return
	_phase_t += delta
	_game_t += delta
	if Game.phase != Game.Phase.DEFEAT and Game.phase != Game.Phase.VICTORY:
		Game.time_scale_target = _speed
	match Game.phase:
		Game.Phase.DAY:
			_day(delta)
		Game.Phase.NIGHT:
			_night(delta)
			_watch(delta)
		_:
			hero.touch_move = Vector2.ZERO
	if Game.arg("hlog", "0") == "1":
		_hydra_log()
	_log_t -= delta
	if _log_t <= 0.0 and Game.phase == Game.Phase.NIGHT:
		_log_t = 15.0 if Game.arg("debug", "0") != "1" else 3.0
		var tg := "-"
		if is_instance_valid(_cur_target) and _cur_target.alive:
			var tp := _cur_target.global_position
			tg = "%s@%.1fm(%.0f,%.0f h=%.1f st=%d)" % [(_cur_target as Enemy).type if _cur_target is Enemy else "?", _cur_target.flat_dist(hero.global_position),
				tp.x, tp.z, Game.island.height_at(tp.x, tp.z), (_cur_target as Enemy).state if _cur_target is Enemy else -1]
		print("[bot]   n%d t=%.0fs alive=%d left=%d pharos=%.0f hero=%.0f%s favor=%.0f pos=(%.0f,%.0f) st=%d tgt=%s" % [Game.night, _game_t - _night_start_t,
			Game.enemy_count(), main.waves.remaining(), Game.pharos.hp, hero.hp, " (retreat)" if _retreat else "", hero.favor,
			hero.global_position.x, hero.global_position.z, hero.state, tg])
		if is_instance_valid(main.waves.boss) and (main.waves.boss as Unit).alive:
			var h: Enemy = main.waves.boss
			print("[bot]      hydra hp=%.0f/%.0f r=%.1f s=%.1f state=%d target=%s" % [h.hp, h.max_hp, Vector2(h.global_position.x, h.global_position.z).length(),
				h.s, h.state, h.target.display_name if is_instance_valid(h.target) else "-"])
		if Game.arg("debug", "0") == "1":
			print("[bot]      hero pos=(%.1f,%.1f) state=%d move=%s" % [hero.global_position.x, hero.global_position.z, hero.state, str(hero.touch_move)])
			for u in Game.units[1]:
				if is_instance_valid(u) and u.alive and u is Enemy and (u as Enemy).is_flying:
					var k: Enemy = u
					print("[bot]      ker pos=(%.1f,%.1f) s=%.1f state=%d target=%s hp=%.0f" % [k.global_position.x, k.global_position.z, k.s, k.state, k.target.display_name if is_instance_valid(k.target) else "-", k.hp])
			for sp in main.spots:
				if sp.building is BarracksBuilding:
					for so in (sp.building as BarracksBuilding).soldiers:
						var st: Soldier = so
						print("[bot]      hoplite lane=%d alive=%s hp=%.0f pos=(%.1f,%.1f) post=(%.1f,%.1f) target=%s cd=%.2f busy=%s" % [sp.lane, str(st.alive), st.hp,
							st.global_position.x, st.global_position.z, st.post().x, st.post().z,
							(str(st.target.type) + "@%.1f" % st.target.flat_dist(st.global_position)) if is_instance_valid(st.target) and st.target is Enemy else "-",
							st.attack_cd, str(st.rig.is_busy())])


var _h_action := ""


## hlog=1: one line per Hydra action (with the frame number, to pick screenshot frames).
func _hydra_log() -> void:
	var h: Node = main.waves.boss
	if not is_instance_valid(h):
		return
	var a: String = (h as Enemy).rig.action
	if a != _h_action:
		_h_action = a
		print("[hlog] frame=%d t=%.1f action=%s hero_d=%.1f hydra=(%.1f,%.1f) zones=%d" % [Engine.get_process_frames(), _game_t - _night_start_t, a,
			(h as Enemy).flat_dist(hero.global_position), (h as Node3D).global_position.x, (h as Node3D).global_position.z, h.danger_zones().size()])


# --- day ---------------------------------------------------------------------------------------------------

func _day(delta: float) -> void:
	if _phase_t < 0.8:
		return
	if _target_spot != null and not _valid_target(_target_spot):
		_target_spot = null
	if _target_spot == null:
		_target_spot = _next_spot()
	if _target_spot:
		if _go_to(_target_spot.global_position, _target_spot.interact_range() - 0.25):
			var lv := _target_spot.level()
			var before := Game.coins
			_target_spot.interact_hold(delta, hero)
			_day_spent += before - Game.coins
			if _is_econ(_target_spot):
				_econ_spent += before - Game.coins
			if _target_spot.level() != lv:
				print("[bot]   day %d: %s -> lv%d (coins left %d)" % [Game.night + 1, _target_spot.type, _target_spot.level(), Game.coins])
				_target_spot = null
				_phase_t = 0.8
		return
	# Nothing worth buying: blow the horn.
	if _go_to(main.horn.global_position, main.horn.interact_range() - 0.4):
		_horn_t += delta
		main.horn.interact_hold(delta, hero)
	else:
		_horn_t = 0.0


func _valid_target(sp: BuildSpot) -> bool:
	if not sp.can_interact(hero):
		return false
	return sp.cost() - sp.paid <= Game.coins


func _affordable(sp: BuildSpot) -> bool:
	if not sp.can_interact(hero):
		return false
	var c := sp.cost() - sp.paid
	if c > Game.coins:
		return false
	if _plan == "miser" and _day_spent + c > _budget:
		return false
	return true


func _next_spot() -> BuildSpot:
	if _plan == "none":
		return null
	if _plan == "lazy":
		return _careless_spot()
	var econ: Array = []
	var defense: Array = []
	var fill: Array = []
	var save_for: BuildSpot = null
	for sp in main.spots:
		if not sp.is_unlocked() or sp.is_maxed():
			continue
		if sp.building and not sp.building.alive:
			continue
		var sc := _score(sp)
		if sc <= 0.0:
			continue
		if not _affordable(sp):
			# A plot we really need but cannot pay yet: keep the coins for it (if it will be affordable tomorrow).
			if sc >= 100.0 and sp.cost() - sp.paid <= Game.coins + _expected_income() + 2:
				save_for = sp
			continue
		if sc < 5.0:
			fill.append([sc, sp])
		elif _is_econ(sp):
			econ.append([sc, sp])
		else:
			defense.append([sc, sp])
	var by_score := func(a, b): return a[0] > b[0]
	econ.sort_custom(by_score)
	defense.sort_custom(by_score)
	fill.sort_custom(by_score)
	if save_for:
		# Only urgent defences for tonight still get bought while saving.
		if not defense.is_empty() and defense[0][0] >= 85.0 and defense[0][1] != save_for:
			return defense[0][1]
		return null
	# What tonight cannot wait for (the lighthouse level that opens tonight's beach) comes first.
	if not defense.is_empty() and defense[0][0] >= 100.0:
		return defense[0][1]
	# A share of each morning's coins goes to the economy while it still has time to pay back.
	for it in econ:
		var c: int = it[1].cost() - it[1].paid
		if float(_econ_spent + c) <= _econ_share() * float(_day_coins) + 0.5:
			return it[1]
	if not defense.is_empty():
		return defense[0][1]
	if not econ.is_empty():
		return econ[0][1]
	if not fill.is_empty() and _plan != "lazy":
		return fill[0][1]
	return null


## build=lazy: spends what it has on whatever plot is nearest, no plan (it never saves for the lighthouse).
func _careless_spot() -> BuildSpot:
	var best: BuildSpot = null
	var best_d := INF
	for sp in main.spots:
		if not sp.is_unlocked() or sp.is_maxed() or not _affordable(sp):
			continue
		if sp.building and not sp.building.alive:
			continue
		var d: float = sp.global_position.distance_to(hero.global_position) + randf() * 12.0
		if d < best_d:
			best_d = d
			best = sp
	return best


func _is_econ(sp: BuildSpot) -> bool:
	return sp.type == "house" or sp.type == "farm" or sp.type == "dock"


func _econ_share() -> float:
	var paydays := Data.NIGHTS - Game.night - 1
	match _plan:
		"econ":
			return 0.9 if paydays >= 2 else 0.0
		"defense":
			return 0.0
	return clampf(0.15 * float(paydays - 1), 0.0, 0.65)


func _expected_income() -> int:
	var t := 0
	for sp in main.spots:
		if sp.building:
			t += sp.building.income()
	return t


## How much a human would want this plot right now (0 = not at all).
func _score(sp: BuildSpot) -> float:
	var lv := sp.level()
	var t := sp.type
	var nights_left := Data.NIGHTS - Game.night # nights still to fight, including tonight
	var paydays := nights_left - 1 # dawns that still pay before the last night
	var tonight := Data.night_lanes(Game.night + 1)
	var soon: Array = []
	for k in [2, 3]:
		for l in Data.night_lanes(Game.night + k):
			if not soon.has(l):
				soon.append(l)
	match t:
		"house", "farm", "dock":
			if _plan == "defense":
				return 0.0
			var inc_now := 0 if lv == 0 else int(Data.building_level(t, lv)["income"])
			var inc_next := int(Data.building_level(t, lv + 1)["income"]) + Game.income_bonus(t)
			var gain := float(inc_next - inc_now)
			var c := float(sp.cost())
			var profit := gain * paydays - c
			if profit <= 0.0:
				return 2.0 # still fills the island when nothing else is left
			var s := 40.0 + 6.0 * gain * paydays / c
			if _plan == "econ":
				s += 40.0
			if lv >= 1:
				s -= 12.0
			return s
		"pharos":
			# The lighthouse opens plots: a must when a beach that is about to be attacked has no tower plot yet.
			var unlocks := 0
			var opens_tonight := false
			var opens_soon := false
			for o in main.spots:
				if o.ring != lv + 1:
					continue
				unlocks += 1
				if o.lane < 0 or not (o.type == "tower" or o.type == "wall") or _lane_has_open_tower(o.lane):
					continue
				if tonight.has(o.lane):
					opens_tonight = true
				elif soon.has(o.lane):
					opens_soon = true
			if opens_tonight:
				return 110.0
			if opens_soon and Game.night >= 1:
				return 75.0
			if nights_left <= 1:
				return 5.0
			return 50.0 + unlocks * 1.5
		"tower", "wall", "barracks":
			if _plan == "econ" and Game.night < 2:
				return 1.0
			var base: float = {"tower": 70.0, "wall": 62.0, "barracks": 66.0}[t]
			if Game.night == 0 and t == "barracks":
				base = 30.0
			if tonight.has(sp.lane):
				base += 20.0 if lv == 0 else 0.0
				base -= 8.0 * lv
				# Outer towers (far down the lane) are a luxury.
				if sp.global_position.length() > 30.0:
					base -= 25.0
				return base
			if soon.has(sp.lane):
				return base - 25.0 - 8.0 * lv
			return base - 45.0 - 8.0 * lv
	return 1.0


func _lane_has_open_tower(l: int) -> bool:
	for sp in main.spots:
		if sp.lane == l and sp.type == "tower" and sp.is_unlocked() and sp.global_position.length() < 30.0:
			return true
	return false


func _go_to(p: Vector3, tol: float) -> bool:
	var d := p - hero.global_position
	d.y = 0.0
	if d.length() <= tol:
		hero.touch_move = Vector2.ZERO
		return true
	_walk(d)
	# Walking around big buildings is not what we are testing: hop if it takes too long.
	if _phase_t > 9.0:
		var to := p - d.normalized() * maxf(tol - 0.6, 0.2)
		print("[bot] WARN day navigation: hop from (%.1f,%.1f) to (%.1f,%.1f), %.1f m" % [hero.global_position.x, hero.global_position.z, to.x, to.z, d.length()])
		hero.teleport(to)
		_phase_t = 0.8
	return false


# --- night -------------------------------------------------------------------------------------------------

func _night(_delta: float) -> void:
	if not _n.is_empty():
		_n["pharos_min"] = minf(float(_n["pharos_min"]), Game.pharos.hp)
		if hero.alive:
			_n["hero_min"] = minf(float(_n["hero_min"]), hero.hp)
	if hero.state == Hero.S.DEAD:
		hero.touch_move = Vector2.ZERO
		_retreat = false
		if not _n.is_empty():
			_n["dead_t"] = float(_n.get("dead_t", 0.0)) + _delta
		return
	if _fight >= 1 and _avoid_marks():
		return
	if _fight == 0:
		_go_to_soft(main.horn.global_position + Vector3(1.5, 0, 1.0), 1.0)
		return
	var hpr := hero.hp_ratio()
	if _fight >= 2:
		# Fall back to heal when hurt, but not while something is tearing at the lighthouse: then the Faro needs
		# Fanós more than Fanós needs his health (a human would not wait 20 s by the plaza either).
		var faro_in_danger := _faro_attacked()
		if _retreat and (hpr > 0.65 or faro_in_danger):
			_retreat = false
		elif not _retreat and hpr < (0.15 if faro_in_danger else 0.3):
			_retreat = true
	var e := _pick_target()
	if _retreat:
		var close := Game.nearest(1, hero.global_position, 2.2)
		if close == null:
			_go_to_soft(Vector3(0, 0, 8.5), 1.0)
			return
		e = close
	_cur_target = e
	if e == null:
		_idle_spot()
		return
	_fight_enemy(e)
	# Bug watch: Fanós standing still, far from the creature he is after.
	if hero.touch_move == Vector2.ZERO and hero.state == Hero.S.NORMAL and e.flat_dist(hero.global_position) > 1.7 + e.radius + 1.0 \
			and Game.island.is_walkable(e.global_position.x, e.global_position.z):
		_idle_t += get_physics_process_delta_time()
		if _idle_t > 4.0 and not _warned.has("idle_%d" % Game.night):
			_warned["idle_%d" % Game.night] = true
			var tp := e.global_position
			print("[bot] WARN hero idle at (%.1f,%.1f) h=%.2f while chasing %s at (%.1f,%.1f) h=%.2f walkable=%s" % [hero.global_position.x,
				hero.global_position.z, Game.island.height_at(hero.global_position.x, hero.global_position.z), (e as Enemy).type if e is Enemy else "?",
				tp.x, tp.z, Game.island.height_at(tp.x, tp.z), str(Game.island.is_walkable(tp.x, tp.z))])
	else:
		_idle_t = 0.0


## The Hydra's violet ground marks: once seen (~0.25 s), step out of them (the steam dash when it is ready).
func _avoid_marks() -> bool:
	var h: Node = main.waves.boss
	if not is_instance_valid(h) or not h.has_method("danger_zones"):
		return false
	for z in h.danger_zones():
		var c: Vector3 = z[0]
		var r: float = z[1]
		var age: float = z[3]
		var d := Vector3(hero.global_position.x - c.x, 0, hero.global_position.z - c.z)
		if d.length() > r + hero.radius + 0.3 or age < 0.25:
			continue
		var out := d.normalized() if d.length() > 0.1 else Unit.dir_of_yaw(hero.facing + PI)
		if hero.dodge_cd <= 0.0 and hero.state != Hero.S.DODGE and hero.state != Hero.S.CAST:
			hero._start_dodge(out)
		hero.touch_move = Vector2(out.x, out.z)
		return true
	return false


func _faro_attacked() -> bool:
	for u in Game.query(1, Game.pharos.global_position, 9.0, false):
		var en := u as Enemy
		if en and en.target == Game.pharos:
			return true
	return false


func _pick_target() -> Unit:
	var ph: Vector3 = Game.pharos.global_position
	var best: Unit = null
	var best_s := INF
	for u in Game.units[1]:
		if not is_instance_valid(u) or not u.alive:
			continue
		var dh: float = u.flat_dist(hero.global_position)
		if _human and dh > 30.0:
			continue
		var s := dh
		if _fight >= 2:
			var dp: float = u.flat_dist(ph)
			s = dh + dp * 0.7
			var en := u as Enemy
			if en and en.state == Enemy.S.ATTACK and en.target and en.target.is_building:
				s -= 10.0
			if en and en.state == Enemy.S.SPAWN:
				s += 6.0
		if s < best_s:
			best_s = s
			best = u
	return best


func _fight_enemy(e: Unit) -> void:
	var d: Vector3 = e.global_position - hero.global_position
	d.y = 0.0
	var reach := 1.7 + e.radius
	var good := _fight >= 2
	# Dodge out of a big swing that is about to land.
	if good and hero.state == Hero.S.NORMAL and hero.dodge_cd <= 0.0:
		var heavy := _heavy_threat()
		if heavy:
			var away := hero.global_position - heavy.global_position
			away.y = 0.0
			hero._start_dodge(away.normalized())
			return
	if hero.state == Hero.S.NORMAL and hero.favor >= hero.favor_max():
		var near := Game.query(1, hero.global_position, Data.HERO["beam_radius"] * 0.8, false).size()
		var boss := e is Hydra and d.length() < 7.0
		if near >= (3 if good else 1) or boss:
			hero.touch_move = Vector2.ZERO
			hero._start_cast()
			return
	if d.length() > reach and not Game.island.is_walkable(e.global_position.x, e.global_position.z) and hero.state == Hero.S.NORMAL:
		# Still in the water: wait for it at the shore.
		var shore := e.global_position
		for i in 12:
			shore = shore.lerp(hero.global_position, 0.25)
			if Game.island.is_walkable(shore.x, shore.z):
				break
		_go_to_soft(shore, 1.5)
		return
	if d.length() > reach:
		_walk(d)
		if hero.state == Hero.S.ATTACK and hero.rig.ap() > 0.5 and Game.nearest(1, hero.global_position, 2.6) != null:
			hero.combo_queued = true
		return
	hero.touch_move = Vector2.ZERO
	match hero.state:
		Hero.S.NORMAL:
			if good and hero.bash_cd <= 0.0 and (_count_front(d.normalized()) >= 2 or e.is_heavy or (e is Enemy and (e as Enemy).data.get("ranged", false))):
				hero._start_bash(d.normalized())
			else:
				hero._start_attack(d.normalized())
		Hero.S.ATTACK:
			if hero.rig.ap() > 0.5:
				hero.combo_queued = true


func _count_front(dir: Vector3) -> int:
	var c := 0
	for u in Game.query(1, hero.global_position, 4.0, false):
		var dd: Vector3 = u.global_position - hero.global_position
		dd.y = 0.0
		if dd.length() < 0.3 or rad_to_deg(dir.angle_to(dd.normalized())) < 60.0:
			c += 1
	return c


func _heavy_threat() -> Unit:
	for u in Game.query(1, hero.global_position, 6.0, false):
		var en := u as Enemy
		if en == null or not en.is_heavy or en.target != hero:
			continue
		if en.rig.is_busy() and en.rig.action != "" and en.rig.action != "hit" and en.rig.ap() < 0.45 and en.flat_dist(hero.global_position) < en._reach(hero) + 0.8:
			return en
	return null


func _idle_spot() -> void:
	if _human:
		_go_to_soft(Vector3(0, 0, 8.0), 2.0)
		return
	# Wait where the next group will come ashore (the beaches were marked during the day).
	var lane := 0
	var g: Array = main.waves._groups
	if not g.is_empty():
		lane = int(g[0][1])
	elif not main.waves._streams.is_empty():
		lane = int(main.waves._streams[0]["lane"])
	var p: Vector3 = Game.island.lane_point_at_radius(lane, 17.0)
	_go_to_soft(p, 2.0)


## Steer like a player would: walk around buildings instead of pushing into them.
func _walk(d: Vector3) -> void:
	var dt := get_physics_process_delta_time()
	var dir := Vector3(d.x, 0, d.z).normalized()
	var from := hero.global_position
	var goal_d := Vector2(d.x, d.z).length()
	# The nearest building in the way: walk along its edge, on the side that turns least (or the forced side).
	var best_along := INF
	var block_c := Vector3.ZERO
	var block_r := 0.0
	for o in Obstacles.list:
		var c: Vector3 = o[0]
		var r: float = float(o[1]) + hero.radius + 0.35
		var to_c := Vector3(c.x - from.x, 0, c.z - from.z)
		var dist := to_c.length()
		if dist > r + 3.0 or dist - r > goal_d:
			continue
		var along := to_c.dot(dir)
		if along <= 0.0 or along >= best_along:
			continue
		if (to_c - dir * along).length() >= r:
			continue
		best_along = along
		block_c = c
		block_r = r
	if best_along < INF:
		var to_c := Vector3(block_c.x - from.x, 0, block_c.z - from.z)
		var cross := dir.x * to_c.z - dir.z * to_c.x
		var sgn := (1.0 if cross > 0.0 else -1.0) if _force_side == 0.0 else _force_side
		_last_side = sgn
		var side := Vector3(to_c.z, 0, -to_c.x).normalized() * sgn
		var k := clampf((block_r + 3.0 - to_c.length()) / 3.0, 0.0, 1.0)
		dir = (dir * (1.0 - k) + side * k).normalized()
	hero.touch_move = Vector2(dir.x, dir.z)
	# A human notices when Fanós is not getting anywhere: try the other way round, and in the end step past.
	_force_t = maxf(0.0, _force_t - dt)
	if _force_t <= 0.0:
		_force_side = 0.0
	if goal_d < _prog_best - 0.5 or absf(goal_d - _prog_best) > 6.0 or best_along == INF:
		_prog_best = goal_d
		_prog_t = 0.0
	else:
		_prog_t += dt
		if _prog_t > 1.5 and _force_t <= 0.0 and best_along < INF:
			_force_side = -_last_side
			_force_t = 3.0
		if _prog_t > 6.0 and best_along < INF:
			if not _warned.has("nav_%d" % Game.night):
				_warned["nav_%d" % Game.night] = true
				print("[bot] WARN bot navigation: no way round at (%.1f,%.1f), hopping (goal %.1f m away)" % [from.x, from.z, goal_d])
			hero.teleport(from + Vector3(d.x, 0, d.z).normalized() * minf(2.0, goal_d))
			_prog_t = 0.0
	var moved := hero.global_position.distance_to(_last_pos)
	_last_pos = hero.global_position
	if moved < 0.01 and hero.state == Hero.S.NORMAL:
		_stuck_t += dt
		if _stuck_t > 3.0 and not _warned.has("hero_stuck_%d" % Game.night):
			_warned["hero_stuck_%d" % Game.night] = true
			print("[bot] WARN hero stuck at (%.1f,%.1f) heading (%.2f,%.2f) phase=%d" % [from.x, from.z, dir.x, dir.z, Game.phase])
	else:
		_stuck_t = 0.0


func _go_to_soft(p: Vector3, tol: float) -> void:
	var d := p - hero.global_position
	d.y = 0.0
	if d.length() <= tol:
		hero.touch_move = Vector2.ZERO
	else:
		_walk(d)


# --- bug watch ---------------------------------------------------------------------------------------------

func _watch(delta: float) -> void:
	# Tower shots and hoplite swings (their cooldowns jump up when they act).
	for sp in main.spots:
		var b: Building = sp.building
		if b is TowerBuilding:
			var cd: float = (b as TowerBuilding).cd
			if cd > float(_tower_cd.get(b, 0.0)) + 0.2:
				_n["shots"] = int(_n.get("shots", 0)) + 1
			_tower_cd[b] = cd
		elif b is BarracksBuilding:
			for s in (b as BarracksBuilding).soldiers:
				if not is_instance_valid(s):
					continue
				var acd: float = s.attack_cd
				if acd > float(_soldier_cd.get(s, 0.0)) + 0.2:
					_n["swings"] = int(_n.get("swings", 0)) + 1
				_soldier_cd[s] = acd
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 2.0
	for u in Game.units[1]:
		if not is_instance_valid(u) or not u.alive:
			continue
		var en := u as Enemy
		if en == null:
			continue
		var rec: Array = _seen.get(en, [en.global_position, 0.0, en.s])
		if rec.size() < 3:
			rec.append(en.s)
		# A walker must never get past a standing wall on its lane.
		if not en.is_flying and en.state == Enemy.S.WALK and en.s > float(rec[2]) + 0.01:
			var w := WallBuilding.blocking(en.lane, float(rec[2]) - 1.0, en.s - 1.0)
			if w and not _warned.has("wall_%d" % en.get_instance_id()):
				_warned["wall_%d" % en.get_instance_id()] = true
				print("[bot] WARN %s walked past a standing wall on lane %d (s %.1f -> %.1f, wall at %.1f)" % [en.type, en.lane, float(rec[2]), en.s, w.lane_s])
		rec[2] = en.s
		var moved: float = en.flat_dist(rec[0])
		var busy := en.state == Enemy.S.ATTACK or en.state == Enemy.S.SPAWN or en.stun > 0.0
		if moved < 0.6 and not busy:
			rec[1] = float(rec[1]) + 2.0
		else:
			rec[1] = 0.0
		rec[0] = en.global_position
		_seen[en] = rec
		if float(rec[1]) >= 10.0 and not _warned.has(en):
			_warned[en] = true
			print("[bot] WARN stuck %s lane=%d state=%d s=%.1f/%.1f pos=(%.1f,%.1f) target=%s" % [en.type, en.lane, en.state, en.s,
				Game.island.lane_length(en.lane), en.global_position.x, en.global_position.z, str(en.target.display_name) if is_instance_valid(en.target) else "-"])
	if _game_t - _night_start_t > 300.0 and not _warned.has("long"):
		_warned["long"] = true
		print("[bot] WARN night %d has lasted 300 s (alive=%d left=%d)" % [Game.night, Game.enemy_count(), main.waves.remaining()])
		for u in Game.units[1]:
			if is_instance_valid(u) and u.alive and u is Enemy:
				var tg: Unit = u.target if is_instance_valid(u.target) else null
				print("[bot]      %s state=%d pos=(%.1f,%.1f) s=%.1f h=%.1f busy=%s action=%s target=%s tpos=%s hero=(%.1f,%.1f) hero_state=%d" % [u.type, u.state,
					u.global_position.x, u.global_position.z, u.s, Game.island.height_at(u.global_position.x, u.global_position.z), str(u.rig.is_busy()), u.rig.action,
					tg.display_name if tg else "-", str(tg.global_position) if tg else "-", hero.global_position.x, hero.global_position.z, hero.state])


func _dump_info() -> void:
	var isl: Island = Game.island
	for l in isl.lanes.size():
		var b: Dictionary = isl.beaches[l]
		print("[info] lane %d %s len=%.1f spawn=(%.1f,%.1f) landing=(%.1f,%.1f)" % [l, b["name"], isl.lane_length(l), b["spawn"].x, b["spawn"].z, b["landing"].x, b["landing"].z])
	for sp in main.spots:
		var extra := ""
		if sp.lane >= 0:
			var q: Vector3 = sp.global_position
			extra = " lane_s=%.1f lane_dist=%.1f" % [isl.lane_project(sp.lane, q), q.distance_to(isl.lane_sample(sp.lane, isl.lane_project(sp.lane, q)))]
		print("[info] spot %s ring=%d lane=%d pos=(%.1f,%.1f) r=%.1f%s" % [sp.type, sp.ring, sp.lane, sp.global_position.x, sp.global_position.z, Vector2(sp.global_position.x, sp.global_position.z).length(), extra])
	# Low ground inside the island (Fanós cannot walk where height < -0.55).
	var holes := 0
	for x in range(-60, 61):
		for z in range(-60, 61):
			var r := Vector2(x, z).length()
			if r > 48.0 or isl.is_walkable(x, z):
				continue
			var c := isl.coast_at(rad_to_deg(Island.angle_of(x, z)))
			if r < c - 3.0:
				holes += 1
				if holes <= 40:
					print("[info] inland non-walkable (%d,%d) r=%.1f coast=%.1f h=%.2f" % [x, z, r, c, isl.height_at(x, z)])
	print("[info] inland non-walkable cells: %d" % holes)
	for sp in main.spots:
		if sp.type == "barracks":
			sp.force_build(1)
			var b: BarracksBuilding = sp.building
			var rp := b.rally_point()
			var ls := isl.lane_project(sp.lane, rp)
			print("[info] barracks lane=%d rally=(%.1f,%.1f) r=%.1f dist_to_lane=%.1f" % [sp.lane, rp.x, rp.z, Vector2(rp.x, rp.z).length(), rp.distance_to(isl.lane_sample(sp.lane, ls))])
	get_tree().quit()


## checks=1: verify that every blessing really changes the numbers it promises, then quit.
func _checks() -> void:
	var fails := 0
	var house: BuildSpot = null
	var farm: BuildSpot = null
	var wall: BuildSpot = null
	var tower: BuildSpot = null
	for sp in main.spots:
		if not sp.is_unlocked():
			continue
		if sp.type == "house" and house == null:
			house = sp
		elif sp.type == "farm" and farm == null:
			farm = sp
		elif sp.type == "wall" and wall == null:
			wall = sp
		elif sp.type == "tower" and tower == null:
			tower = sp
	for sp in [house, farm, wall, tower]:
		sp.force_build(1)
	var t: TowerBuilding = tower.building
	var base := {"pharos_hp": Game.pharos.max_hp, "house_hp": house.building.max_hp, "wall_hp": wall.building.max_hp,
		"house_inc": house.building.income(), "farm_inc": farm.building.income(), "t_range": t.range_stat(), "t_rate": t.rate_stat(),
		"t_dmg": t.dmg_stat(), "hero_hp": hero.max_hp_stat(), "hero_speed": hero.speed_stat(), "hero_dmg": hero.dmg_mult()}
	var expect := {
		"athena": {"pharos_hp": 1.3, "house_hp": 1.3, "wall_hp": 1.3},
		"hestia": {"pharos_hp": 1.25, "house_inc": "+2"},
		"hephaestus": {"wall_hp": 1.6, "t_dmg": 1.2},
		"artemis": {"t_range": "+2", "t_rate": 0.8},
		"apollo": {"hero_hp": "+40"},
		"hermes": {"hero_speed": 1.2},
		"ares": {"hero_dmg": 1.3},
		"demeter": {"farm_inc": "+4"},
	}
	for id in expect:
		Game.blessings.clear()
		Game.take_blessing(id)
		for sp in main.spots:
			if sp.building:
				sp.building.refresh_max_hp()
		var now := {"pharos_hp": Game.pharos.max_hp, "house_hp": house.building.max_hp, "wall_hp": wall.building.max_hp,
			"house_inc": house.building.income(), "farm_inc": farm.building.income(), "t_range": t.range_stat(), "t_rate": t.rate_stat(),
			"t_dmg": t.dmg_stat(), "hero_hp": hero.max_hp_stat(), "hero_speed": hero.speed_stat(), "hero_dmg": hero.dmg_mult()}
		for k in expect[id]:
			var e: Variant = expect[id][k]
			var want: float
			if e is String:
				want = float(base[k]) + float((e as String).substr(1))
			else:
				want = float(base[k]) * float(e)
			var ok := absf(float(now[k]) - want) < 0.01
			if not ok:
				fails += 1
			print("[check] %-10s %-10s %8.2f -> %8.2f (want %8.2f) %s" % [id, k, float(base[k]), float(now[k]), want, "ok" if ok else "FAIL"])
	# Zeus: favor gain and beam damage.
	Game.blessings.clear()
	hero.favor = 0.0
	hero.add_favor(10.0)
	var f0 := hero.favor
	Game.take_blessing("zeus")
	hero.favor = 0.0
	hero.add_favor(10.0)
	print("[check] zeus       favor      %8.2f -> %8.2f (want %8.2f) %s" % [f0, hero.favor, f0 * 1.35, "ok" if absf(hero.favor - f0 * 1.35) < 0.01 else "FAIL"])
	if absf(hero.favor - f0 * 1.35) >= 0.01:
		fails += 1
	# Poseidon: not slowed while still in the sea, slowed for 6 s once ashore.
	Game.blessings.clear()
	Game.take_blessing("poseidon")
	var sea: Enemy = main.waves.spawn("shade", 0)
	var land: Enemy = main.waves.spawn("shade", 0, sea._land_s + 0.3)
	await get_tree().create_timer(1.4).timeout
	var ok_sea := sea.slow < 0.01
	var ok_land := land.slow >= 0.44 and land.slow_t > 4.0
	print("[check] poseidon   at sea     %8.2f (want 0) %s" % [sea.slow, "ok" if ok_sea else "FAIL"])
	print("[check] poseidon   ashore     %8.2f for %.1fs %s" % [land.slow, land.slow_t, "ok" if ok_land else "FAIL"])
	if not ok_sea:
		fails += 1
	if not ok_land:
		fails += 1
	sea.queue_free()
	land.queue_free()
	# Hermes: the steam dash goes 30 % further.
	Game.blessings.clear()
	var d0: float = await _dash_distance()
	Game.take_blessing("hermes")
	var d1: float = await _dash_distance()
	var ok_h := absf(d1 / maxf(d0, 0.01) - 1.3) < 0.08
	print("[check] hermes     dash       %8.2f -> %8.2f (want x1.30) %s" % [d0, d1, "ok" if ok_h else "FAIL"])
	if not ok_h:
		fails += 1
	Game.blessings.clear()
	print("[check] DONE fails=%d" % fails)
	get_tree().quit()


## One real steam dash on the open plaza: how far Fanós travels.
func _dash_distance() -> float:
	hero.teleport(Vector3(-1.0, 0, 13.0))
	hero.state = Hero.S.NORMAL
	hero.vel = Vector3.ZERO
	hero.dodge_cd = 0.0
	await get_tree().physics_frame
	var from := hero.global_position
	hero._start_dodge(Vector3(1, 0, 0))
	while hero.state == Hero.S.DODGE:
		await get_tree().physics_frame
	for i in 10:
		await get_tree().physics_frame
	return Vector2(hero.global_position.x - from.x, hero.global_position.z - from.z).length()
