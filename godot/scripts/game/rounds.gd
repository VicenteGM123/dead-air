# Round flow (ARCHITECTURE §10, GDD §7 entirely, §13 step 3 spawn override). Port of src/game/rounds.js.
#
# Fields: round, special (false | 'hullabaloo'), phase ('pregame' | 'active' | 'intermission'), count (zombies in
#   this round, specials included), toSpawn (left to spawn), killsThisRound, totalKills, paused, timer (seconds
#   left in pregame/intermission), hullabalooIndex (k of the last Hullabaloo Hour), nextHullabaloo (round number),
#   token (id of the current round's spawns: zombies carry it as z.fromRound).
# Methods: startRound(n), pauseSpawning(bool), onZombieKilled(z), requeue(z | typeId) (anti-stuck despawns),
#   rollTunedInSpeed() (GDD §7.3 roll with the 60 % super-sprint cap of this round), isHullabaloo(r), nextSpecial
#   (getter: false | 'hullabaloo' for round + 1), forceForecaster() (spawn one now, counting toward the round: EE
#   step 3 override / 'egg:need_forecaster'). startRound(n) in the middle of a round (debug.setRound) first clears
#   the old round's zombies (static puff, no points, no kills).
# Exported formulas (static, callable as Rounds.zombieHp(r) etc.): zombieCount(r), zombieHp(r), spawnInterval(r),
#   rollSpeed(r, rand), hullabalooCount(k), hullabalooHp(k, r), forecasterCount(r), bigShotScheduled(r).
# Flow: game start -> round 1 (or params.round) after T.rounds.firstRoundDelay; each round opens with the round sting
#   (sting_round_start, minor sting_round_start_13 on round 13 + event round:thirteen), the first spawn comes
#   T.rounds.firstSpawnDelay later, then one spawn per spawnInterval(r) (0.8 s in Hullabaloo) while fewer than
#   T.rounds.maxAlive (10 in Hullabaloo) are alive. The round ends when `count` of its zombies were killed (anti-stuck
#   despawns are requeued), then a T.rounds.intermission (12 s after a Hullabaloo Hour) break: sting_round_end,
#   music 'intermission'. The decorative TVs (right_back / hullabaloo) are switched by screens.gd on round:end /
#   round:start (it reads nextSpecial). Tube grenades +T.player.grenadesPerRound from round 2 (weapons.addGrenades,
#   skipped when weapons.gd already granted them on round:start).
# Specials: Hullabaloo Hour (first on round 5 or 6, then every 4–5 rounds; Sock Hoppers only; count
#   min(8 + 4(k−1), 24), HP 350 then max(350, 0.4·HP(r)); telegraphed during the intermission before it (round:end
#   next.special, round:telegraph), lilac lights over 2 s, sting_hullabaloo_intro; the last sock drops FULL REEL then
#   sting_hullabaloo_end). Mix-ins: Forecasters from r7 at 20–70 % of the queue (max 2 alive, 3 from r15), Big Shots
#   on rounds 10, 13, 16… at 50 % / 75 % (2 from r20, +10 % extra chance from r12, pushed off Hullabaloo rounds),
#   Sock Hoppers 10 % of spawns from r12 (15 % from r20). EE: while game.egg.forceForecaster, every round has at least
#   one Forecaster and, past 60 % of the queue with none alive and no Stray Storm (egg.stormActive / egg.storm), one
#   spawns immediately.
# Music: 'hullabaloo' in Hullabaloo Hour, 'round' from round 10 once powered, 'ambient' otherwise; 'intermission'
#   bossa between rounds once powered. Nothing is changed while game.boss is active.
# Events: round:start {round, special}, round:end {round, special, intermission, next:{round, special}},
#   round:telegraph {round, special:'hullabaloo', seconds} (the Hullabaloo telegraph starts), round:thirteen {round}.
#
# Port notes: `round` keeps its JS name although it shadows the global round() (use roundf/floorf here). Colours are
#   lerped in linear space like THREE.Color (Godot Colors hold sRGB). try/catch guards became explicit checks.
# MP: the host runs everything above and sends rounds.net_start(r, special, count, token, hullIdx, nextHull, first,
#   maxAlive) / rounds.net_end(r, special, intermission, nextHull, hullIdx, kills, totalKills) to the clients, which
#   mirror the fields and run the presentation half (_applyStart / _applyEnd: tint, round:* events, their own grenade
#   grant, stings, music); a client never starts a round itself. Zombies per round x [1, 1.5, 2, 2.5] for 1..4
#   session players (MP_COUNT_MUL; interval and HP unscaled). killsBy {peer id: kills} on every peer (team summary;
#   clients mirror it from the replicated kills).
class_name Rounds
extends RefCounted

const LILAC := Color("#C9A7FF")
const LILAC_GROUND := Color("#5A3F7A")
const WARM_LILAC := -1.6          # render.post.warmth at full Hullabaloo tint (default 1 = warm 70s)

# ------------------------------------------------------------------------------------------------ formulas
static func _R() -> Dictionary:
	return Config.T.rounds

static func _jsRound(x: float) -> float:
	return floorf(x + 0.5)

static func zombieCount(r: int) -> int:
	var R := _R()
	var early: Array = R.early
	if r <= early.size():
		return int(early[maxi(1, r) - 1])
	var k := float(r - early.size())
	return mini(int(R.countCap), int(floorf(float(early[early.size() - 1]) + float(R.countA) * k + float(R.countB) * k * k)))

static func zombieHp(r: int) -> int:
	var R := _R()
	if r <= 9:
		return int(R.hpEarlyBase) + int(R.hpEarlyStep) * (maxi(1, r) - 1)
	return int(minf(float(R.hpCap), _jsRound(float(int(R.hpEarlyBase) + int(R.hpEarlyStep) * 8) * pow(float(R.hpMul), float(r - 9)))))

static func spawnInterval(r: int) -> float:
	var I: Dictionary = _R().interval
	return maxf(float(I.min), float(I.base) * pow(float(I.mul), float(r - 1)))

# Tuned-In speed tier roll (GDD §7.3) -> m/s (no cap; Rounds.rollTunedInSpeed applies the 60 % super cap).
static func rollSpeed(r: int, rand: Callable) -> float:
	var R := _R()
	var s: Dictionary = R.speedRoll
	var v: float = float(s.perRound) * r + (float(rand.call()) * 2.0 - 1.0) * float(s.jitter)
	if v < float(s.jog):
		return float(R.speeds.walk)
	if v < float(s.sprint):
		return float(R.speeds.jog)
	if v < float(s.super):
		return float(R.speeds.sprint)
	return float(R.speeds.super)

static func hullabalooCount(k: int) -> int:
	var c: Array = _R().hullabaloo.count
	return mini(int(c[0]) + int(c[1]) * (k - 1), int(c[2]))

static func hullabalooHp(k: int, r: int) -> int:
	var H: Dictionary = _R().hullabaloo
	return int(H.hpFirst) if k <= 1 else maxi(int(H.hpFirst), int(_jsRound(float(H.hpMul) * zombieHp(r))))

static func forecasterCount(r: int) -> int:
	var R := _R()
	return 0 if r < int(R.forecasterFrom) else mini(1 + int(floorf(float(r - int(R.forecasterFrom)) / 4.0)), 3)

static func bigShotScheduled(r: int) -> int:
	var R := _R()
	if r < int(R.bigShotFrom) or (r - int(R.bigShotFrom)) % int(R.bigShotEvery) != 0:
		return 0
	return 2 if r >= 20 else 1

static func _between(rand: Callable, a: int, b: int) -> int:
	return a + int(floorf(float(rand.call()) * (b - a + 1)))

# ------------------------------------------------------------------------------------------------ system
var game
var round := 0
var special = false               # false | 'hullabaloo'
var toSpawn := 0
var count := 0
var killsThisRound := 0
var totalKills := 0
var phase := "pregame"
var paused := false
var timer := 0.0
var token := 0
var hullabalooIndex := 0
var nextHullabaloo := 5
var queue: Array = []
var nextSpecial:
	get:
		return "hullabaloo" if isHullabaloo(round + 1) else false
var _spawnT := 0.0
var _bigShotCarry := 0
var _tunedIn := 0
var _superCap := 0
var _superUsed := 0
var _spawned := 0
var _eeForcedT := 0.0
var _tint = null                  # { saved, key, k, dir, warm?, lastWarm? } while the lilac shift runs
var _thirteenT := 0.0
var _lastSockPos = null
# MP: kills per peer id (team summary), the zombie count multiplier per player count (MP_SPEC §5 / RECONCILE R16)
var killsBy := {}
const MP_COUNT_MUL := [1.0, 1.5, 2.0, 2.5]

func _init(g) -> void:
	game = g

func init() -> void:
	var ev = game.events
	ev.on("egg:need_forecaster", func(_p = null): forceForecaster())
	ev.on("power:on", func(_p = null):
		if phase == "active":
			_music())
	# The hemisphere light is recomputed by lights.gd every frame after the systems ran: tint it right before the
	# render instead.
	var r = game.render
	if r != null and r.has_method("addPrePass"):
		r.addPrePass(func(_a = null): _tintHemi())

func _tintHemi() -> void:
	var t = _tint
	var L = game.lights
	if t == null or L == null:
		return
	var hemi = _f(L, "hemi")
	if hemi == null:
		return
	var k: float = t.k * t.k * (3.0 - 2.0 * t.k)
	var c = _getColor(hemi, "color")
	if c != null:
		_setColor(hemi, "color", _lerpLinear(c, LILAC, k * 0.6))
	var gc = _getColor(hemi, "groundColor")
	if gc != null:
		_setColor(hemi, "groundColor", _lerpLinear(gc, LILAC_GROUND, k * 0.45))

func reset() -> void:
	var g = game
	var H: Dictionary = _R().hullabaloo
	round = 0
	special = false
	toSpawn = 0
	count = 0
	killsThisRound = 0
	totalKills = 0
	phase = "pregame"
	paused = false
	timer = float(_R().firstRoundDelay)
	token = 0
	hullabalooIndex = 0
	nextHullabaloo = _between(g.rand, int(H.first[0]), int(H.first[1]))
	queue = []
	_bigShotCarry = 0
	_spawned = 0
	_eeForcedT = 0.0
	killsBy = {}
	_restoreTint(true)
	if g.zombies != null:
		g.zombies.maxAlive = int(_R().maxAlive)

# special is false | 'hullabaloo' (GDScript refuses bool == String comparisons).
func _isHul() -> bool:
	return special is String and special == "hullabaloo"

func isHullabaloo(r: int) -> bool:
	return r == nextHullabaloo

# ------------------------------------------------------------------------------------------------ rounds
func startRound(n) -> void:
	var g = game
	if _cli():
		return                          # MP client: rounds come from the host (net_start)
	var H: Dictionary = _R().hullabaloo
	var r := maxi(1, int(floorf(float(n))))
	# Jumping ahead (params.round / debug.setRound): the skipped Hullabaloo Hours count (k grows as if they had been
	# played) and the schedule moves into the future.
	while nextHullabaloo < r:
		if nextHullabaloo > round:
			hullabalooIndex += 1
		nextHullabaloo += _between(g.rand, int(H.every[0]), int(H.every[1]))
	var first := round == 0
	# A jump in the middle of a round (debug.setRound): the leftovers of the old round leave in a static puff.
	var Zs = g.zombies
	if phase == "active" and Zs != null and Zs.alive.size() > 0 and Zs.has_method("despawnAll"):
		Zs.despawnAll({"fx": true, "requeue": false})
	round = r
	token += 1
	special = "hullabaloo" if isHullabaloo(r) else false
	if special:
		hullabalooIndex += 1
	queue = _buildQueue(r)
	count = queue.size()
	toSpawn = count
	killsThisRound = 0
	_spawned = 0
	phase = "active"
	timer = 0.0
	_spawnT = float(_R().firstSpawnDelay)
	_lastSockPos = null
	if g.zombies != null:
		g.zombies.maxAlive = int(H.maxAlive) if special else int(_R().maxAlive)
	# Tuned-In speed cap for this round (GDD §7.3: at most 60 % super-sprinters).
	_tunedIn = queue.filter(func(t): return t == "tuned_in").size()
	_superCap = int(floorf(float(_R().speedRoll.superCap) * _tunedIn))
	_superUsed = 0
	if _mpHost():
		g.net.toAll("rounds", "start", [r, str(special) if special else "", count, token, hullabalooIndex, nextHullabaloo, first,
			int(g.zombies.maxAlive) if g.zombies != null else int(_R().maxAlive)])
	_applyStart(r, first)

# The presentation half of a round start (host and MP clients): tint, round:start, grenades, stings, music, 13.
func _applyStart(r: int, first: bool) -> void:
	var g = game
	if special and _tint == null:
		_startTint()
	# Grenades: +2 per round from round 2 (the start kit covers round 1). weapons.gd may grant them itself on
	# round:start; then the count already moved and we leave it alone.
	var w = g.weapons
	var nades = null
	if w != null:
		var gv = w.get("grenades")
		if gv is int or gv is float:
			nades = gv
	g.events.emit("round:start", {"round": r, "special": special})
	if not first and (nades == null or w.get("grenades") == nades):
		_grantGrenades()
	if not _bossActive():
		_audioPlay("sting_round_start_13" if r == 13 else "sting_round_start")
		_music()
	if r == 13:
		g.events.emit("round:thirteen", {"round": r})
		_thirteenT = 6.0

# Spawn queue of type ids (specials count toward N, GDD §7.1/§7.6).
func _buildQueue(r: int) -> Array:
	var g = game
	var rand: Callable = g.rand
	var R := _R()
	if _isHul():
		# A Big Shot scheduled on a Hullabaloo round moves to the next round.
		_bigShotCarry += bigShotScheduled(r)
		var hq: Array = []
		hq.resize(_mpCount(hullabalooCount(hullabalooIndex)))
		hq.fill("sock_hopper")
		return hq
	var n := _mpCount(zombieCount(r))
	var q: Array = []
	q.resize(n)
	q.fill("tuned_in")
	var taken := {0: true}
	var place := func(type: String, at: float) -> void:
		var i: int = clampi(int(_jsRound(at)), 1, n - 1)
		var k := 0
		while k < n and taken.has(i):
			i = (i + 1) % n
			if i == 0:
				i = 1
			k += 1
		if taken.has(i):
			return
		taken[i] = true
		q[i] = type
	# Big Shots: 50 % / 75 % of the queue.
	var bs := bigShotScheduled(r) + _bigShotCarry
	_bigShotCarry = 0
	if bs == 0 and r >= 12 and float(rand.call()) < float(R.bigShotExtra):
		bs = 1
	bs = mini(bs, 3)
	for f in [0.5, 0.75, 0.9].slice(0, bs):
		place.call("big_shot", n * f)
	# Forecasters: random points 20–70 % of the queue (EE step 3 override: at least one).
	var fc := forecasterCount(r)
	if _eeForce() and fc < 1:
		fc = 1
	for k in fc:
		place.call("forecaster", n * (0.2 + float(rand.call()) * 0.5))
	# Sock Hoppers mixed in from round 12.
	if r >= int(R.sockMixFrom):
		var p: float = float(R.sockMix[1]) if r >= 20 else float(R.sockMix[0])
		for i in range(1, n):
			if not taken.has(i) and float(rand.call()) < p:
				taken[i] = true
				q[i] = "sock_hopper"
	return q

func pauseSpawning(on) -> void:
	paused = _t(on)

# GDD §7.3 per-zombie tier roll with the round's 60 % super-sprint cap (excess become sprinters).
func rollTunedInSpeed() -> float:
	var g = game
	var R := _R()
	var v := rollSpeed(maxi(1, round if round else 1), g.rand)
	if v >= float(R.speeds.super):
		if _superUsed >= _superCap:
			return float(R.speeds.sprint)
		_superUsed += 1
	return v

func onZombieKilled(z) -> void:
	var g = game
	totalKills += 1
	var by = z.get("killBy") if z is Dictionary else null
	if by != null:
		killsBy[by] = int(killsBy.get(by, 0)) + 1
	if phase != "active" or z == null or z.get("fromRound") != token:
		return
	killsThisRound += 1
	if z.type == "sock_hopper":
		_lastSockPos = z.pos
	if killsThisRound >= count:
		if _isHul():
			# The last Sock Hopper always drops FULL REEL, then "…and now back to our program".
			var pos: Vector3 = _lastSockPos if _lastSockPos != null else z.pos
			var pu = g.powerups
			if pu != null and pu.has_method("dropGuaranteed"):
				pu.dropGuaranteed("full_reel", pos)
			elif pu != null and pu.has_method("drop"):
				pu.drop("full_reel", pos)
			_audioPlay("sting_hullabaloo_end")
		_endRound()

# Anti-stuck despawn / straggler: the zombie goes back into this round's queue.
func requeue(zOrType) -> void:
	var z = zOrType if zOrType is Dictionary else null
	var type = z.type if z != null else zOrType
	if phase != "active" or (z != null and z.get("fromRound") != token):
		return
	queue.push_front(type if type else "tuned_in")
	toSpawn += 1
	_spawnT = minf(_spawnT, 1.0)

# EE step 3 override: one Forecaster right now, counting toward the round.
func forceForecaster():
	var g = game
	if phase != "active" or _bossActive() or g.zombies == null:
		return null
	var z = g.zombies.spawn("forecaster", null, null, {"fromRound": token})
	if z != null:
		count += 1
		_spawned += 1
	return z

func _endRound() -> void:
	var g = game
	var R := _R()
	var wasSpecial = special
	phase = "intermission"
	timer = float(R.hullabaloo.intermission) if wasSpecial else float(R.intermission)
	if _mpHost():
		g.net.toAll("rounds", "end", [round, str(wasSpecial) if wasSpecial else "", timer, nextHullabaloo, hullabalooIndex,
			killsThisRound, totalKills])
	_applyEnd(wasSpecial)

# The presentation half of a round end (host and MP clients).
func _applyEnd(wasSpecial) -> void:
	var g = game
	var R := _R()
	var next := {"round": round + 1, "special": "hullabaloo" if isHullabaloo(round + 1) else false}
	g.events.emit("round:end", {"round": round, "special": wasSpecial, "intermission": timer, "next": next})
	if g.zombies != null:
		g.zombies.maxAlive = int(R.maxAlive)
	if wasSpecial:
		_restoreTint()
	# The decorative TVs (WE'LL BE RIGHT BACK / Hootie's intro) are switched by screens.gd on round:end/start.
	if not _bossActive():
		if not wasSpecial:
			_audioPlay("sting_round_end")
		if next.special:
			_telegraphHullabaloo(next.round)
		else:
			_audioMusic("intermission" if _powered() else "ambient")

# The intermission before a Hullabaloo Hour: every decorative TV on Hootie's intro, lilac lights, organ + hoots.
func _telegraphHullabaloo(r: int) -> void:
	var g = game
	_startTint()
	_audioPlay("sting_hullabaloo_intro")
	_audioMusic("hullabaloo")
	g.events.emit("round:telegraph", {"round": r, "special": "hullabaloo", "seconds": timer})

func update(dt: float) -> void:
	var g = game
	_updateTint(dt)
	if _thirteenT > 0.0:
		_thirteenT -= dt
	if _cli():
		if phase != "active":
			timer = maxf(0.0, timer - dt)   # display only: the host starts the next round
		return
	if _bossActive():
		return
	if phase != "active":
		timer -= dt
		if timer <= 0.0:
			var first = g.params.get("round")
			var isNum: bool = first is int or first is float
			startRound(first if round == 0 and isNum and first >= 1 else round + 1)
		return
	if paused:
		return
	# EE step 3 override: past 60 % of the queue with no Forecaster and no Stray Storm -> one now.
	if _eeForce():
		_eeForcedT -= dt
		var Zs0 = g.zombies
		if _eeForcedT <= 0.0 and _spawned >= 0.6 * count and Zs0 != null and Zs0.count("forecaster") == 0 and not queue.has("forecaster") and not _stormActive():
			_eeForcedT = 20.0
			forceForecaster()
	if toSpawn <= 0:
		return
	_spawnT -= dt
	if _spawnT > 0.0:
		return
	var Zs = g.zombies
	if Zs == null or Zs.alive.size() >= Zs.maxAlive:
		_spawnT = 0.1
		return
	var i := _nextIndex()
	if i < 0:
		_spawnT = 0.25
		return
	var type: String = queue[i]
	var opts := {"fromRound": token}
	if _isHul() and type == "sock_hopper":
		opts.hp = hullabalooHp(hullabalooIndex, round)
	var z = Zs.spawn(type, null, null, opts)
	if z == null:
		_spawnT = 0.2
		return
	queue.remove_at(i)
	toSpawn = queue.size()
	_spawned += 1
	_spawnT = float(_R().hullabaloo.interval) if _isHul() else spawnInterval(round)

# First queue entry whose type is not at its alive cap (Forecasters 2 / 3 from r15, Big Shots 1 / 2 from r20).
func _nextIndex() -> int:
	var Zs = game.zombies
	var r := round
	var capF := 3 if r >= 15 else 2
	var capB := 2 if r >= 20 else 1
	for i in queue.size():
		var t: String = queue[i]
		if t == "forecaster" and Zs.count("forecaster") >= capF:
			continue
		if t == "big_shot" and Zs.count("big_shot") >= capB:
			continue
		return i
	return -1

# ------------------------------------------------------------------------------------------------ MP
func _cli() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isClient

func _mpHost() -> bool:
	var n = game.get("net")
	return n != null and n.inGame and n.isHost

# Zombies per round x [1, 1.5, 2, 2.5] for 1..4 players in the session (counted at round start).
func _mpCount(n: int) -> int:
	var nt = game.get("net")
	if nt == null or not nt.inGame:
		return n
	var k: int = clampi(nt.players().size(), 1, MP_COUNT_MUL.size())
	return int(floorf(float(n) * float(MP_COUNT_MUL[k - 1]) + 0.5))

# Host -> clients (net.toAll): a round starts. The client mirrors the host's fields and plays the presentation.
func net_start(r, sp, cnt, tok, hIdx, nextHull, first, maxAl) -> void:
	if not _cli() or game.net.sender != 1 or not (r is int) or not (cnt is int):
		return
	round = r
	special = str(sp) if (sp is String and sp != "") else false
	count = cnt
	toSpawn = cnt
	token = int(tok)
	hullabalooIndex = int(hIdx)
	nextHullabaloo = int(nextHull)
	killsThisRound = 0
	phase = "active"
	timer = 0.0
	if game.zombies != null and (maxAl is int):
		game.zombies.maxAlive = maxAl
	_applyStart(r, first == true)

# Host -> clients: the round ended (the client's counters are resynced too).
func net_end(r, sp, intermission, nextHull, hIdx, kills, total) -> void:
	if not _cli() or game.net.sender != 1 or not (r is int):
		return
	round = r
	special = str(sp) if (sp is String and sp != "") else false
	var wasSpecial = special
	phase = "intermission"
	timer = float(intermission)
	nextHullabaloo = int(nextHull)
	hullabalooIndex = int(hIdx)
	killsThisRound = int(kills)
	totalKills = int(total)
	toSpawn = 0
	_applyEnd(wasSpecial)

# ------------------------------------------------------------------------------------------------ helpers
func _music() -> void:
	if _bossActive():
		return
	if _isHul():
		_audioMusic("hullabaloo")
	else:
		_audioMusic("round" if round >= 10 and _powered() else "ambient")

func _powered() -> bool:
	var g = game
	return bool((g.machines != null and _f(g.machines, "powerOn", false)) or (g.level != null and _f(g.level, "powered", false)))

func _bossActive() -> bool:
	var b = game.boss
	return _t(b != null and (_f(b, "active", false) or _f(b, "running", false) or _f(b, "fighting", false)))

func _eeForce() -> bool:
	var e = game.egg
	return _t(e != null and _f(e, "forceForecaster", false))

func _stormActive() -> bool:
	var e = game.egg
	if e == null:
		return false
	if _f(e, "stormActive", false):
		return true
	var s = _f(e, "storm")
	return s != null and not (s is bool and s == false) and _f(s, "active", true) != false

func _grantGrenades() -> void:
	var w = game.weapons
	var n: int = int(Config.T.player.grenadesPerRound)
	if w == null:
		return
	if w.has_method("addGrenades"):
		w.addGrenades(n)   # JS passes (n, 'round'); weapons.addGrenades(n) takes one argument
	else:
		var gv = w.get("grenades")
		if gv is int or gv is float:
			w.set("grenades", mini(int(Config.T.player.grenadesMax), int(gv) + n))

func _audioPlay(id: String, opts := {}) -> void:
	var a = game.audio
	if a != null and a.has_method("play"):
		a.play(id, opts)

func _audioMusic(id: String) -> void:
	var a = game.audio
	if a != null and a.has_method("music"):
		a.music(id)

# Lilac light shift (GDD §7.5): every point-light anchor, the key light and the hemisphere (see _tintHemi) lerp
# toward #C9A7FF over 2 s.
func _startTint() -> void:
	if _tint != null:
		_tint.dir = 1          # still fading back: turn around (keeps the true originals)
		return
	var L = game.lights
	if L == null:
		return
	var anchors = _f(L, "anchors")
	if anchors == null:
		return
	var saved: Array = []
	for a in (anchors.values() if anchors is Dictionary else anchors):
		if _f(a, "flash", false):
			continue
		var c = _getColor(a, "color")
		if c == null:
			continue
		saved.append({"a": a, "orig": c, "last": c})
	var key = _f(L, "key")
	_tint = {"saved": saved, "key": _getColor(key, "color") if key != null else null, "k": 0.0, "dir": 1}

func _restoreTint(instant := false) -> void:
	var t = _tint
	if t == null:
		return
	if instant:
		t.k = 0.0
		_applyTint()
		_tint = null
		return
	t.dir = -1

func _updateTint(dt: float) -> void:
	var t = _tint
	if t == null:
		return
	t.k = clampf(t.k + (t.dir * dt) / 2.0, 0.0, 1.0)
	_applyTint()
	if t.dir < 0 and t.k <= 0.0:
		_tint = null

func _applyTint() -> void:
	var t = _tint
	var L = game.lights
	if t == null or L == null:
		return
	var k: float = t.k * t.k * (3.0 - 2.0 * t.k) * 0.8
	for s in t.saved:
		# Somebody else changed this light meanwhile (power on, EE): let go of it.
		var cur = _getColor(s.a, "color")
		if cur != s.last:
			s.orig = cur
		var nc := _lerpLinear(s.orig, LILAC, k)
		_setColor(s.a, "color", nc)
		s.last = nc
	var key = _f(L, "key")
	if t.key != null and key != null:
		_setColor(key, "color", _lerpLinear(t.key, LILAC, k * 0.7))
	# The station's lighting is mostly image-based, so the light colours alone barely read: the grade's warm 70s
	# tint also swings to a cool lilac (render.post.warmth; someone else writing it meanwhile becomes the new base).
	var R = game.render
	var P = _f(R, "post") if R != null else null
	if P is Dictionary and (P.get("warmth") is float or P.get("warmth") is int):
		if not t.has("warm") or (t.has("lastWarm") and float(P.warmth) != t.lastWarm):
			t.warm = float(P.warmth)
		P.warmth = t.warm + (WARM_LILAC - t.warm) * (k / 0.8)
		t.lastWarm = float(P.warmth)

# THREE.Color.lerp works on linear components; Godot Colors (Light3D.light_color, Color("#hex")) hold sRGB.
static func _lerpLinear(a: Color, b: Color, t: float) -> Color:
	return a.srgb_to_linear().lerp(b.srgb_to_linear(), t).linear_to_srgb()

# JS truthiness (!!v): null/false/0/NaN/"" are false; objects, arrays and dictionaries are true.
static func _t(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0 and not is_nan(v)
	if v is String or v is StringName:
		return v != ""
	return true

# Reads a field of a Dictionary or an Object (null when missing), like JS `o.k`.
static func _f(o, k: String, d = null):
	if o is Dictionary:
		return o.get(k, d)
	if o is Object:
		var v = o.get(k)
		return d if v == null else v
	return d

# THREE light/anchor colours: a Light3D keeps it in light_color (a hemisphere emulation may use ground_color).
static func _getColor(o, k: String):
	if o is Light3D and k == "color":
		return (o as Light3D).light_color
	var v = _f(o, k)
	if v == null and k == "groundColor":
		v = _f(o, "ground_color")
	return v if v is Color else null

static func _setColor(o, k: String, c: Color) -> void:
	if o is Light3D and k == "color":
		(o as Light3D).light_color = c
		return
	if o is Dictionary:
		o[k] = c
	elif o is Object:
		if k == "groundColor" and o.get("groundColor") == null and o.get("ground_color") != null:
			o.set("ground_color", c)
		else:
			o.set(k, c)
