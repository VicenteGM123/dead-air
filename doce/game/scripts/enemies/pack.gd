class_name BeastPack
extends Node
## The shared brain of a wolf pack or a boar herd (ENCOUNTERS, lane P): scripts/enemies/wolf.gd and boar.gd join
## the pack of their spawn group when main.spawn_encounters() teleports them (members of one World.spawn_groups()
## entry stand within JOIN_R of each other; groups are tens of metres apart).
##
##   IDLE    every member wanders round its own home spot (where it was spawned)
##   ALERT   the hero came within AGGRO_R of a member, or hurt / hooked one: the alpha howls (once per pack, the
##           wolf_howl) while the others run in; HUNT after ALERT_TIME
##   HUNT    wolves encircle the hero (ring slots round him, drifting so the ring turns); ATTACK TOKENS: only the
##           member holding one may attack (one at a time; two for packs of 4+ alive, the second only once the first
##           has bitten or missed); TOKEN_CD s between attacks; boars share the same token for their charges
##   RETURN  the hero ran more than LEASH m from home (for LEASH_GRACE s), or fell: the members trot home, healing,
##           and the pack is IDLE again once they are all there
## When the hero dies every surviving member is reset at his respawn: teleported to its home spot, full health,
## IDLE (and the next alert does not howl again). Killed members stay dead (the pack only shrinks); when none is left
## the pack is `cleared` and stops thinking.
## Members implement (duck-typed): home_spot, member_ready() -> bool, begin_attack(), attack_phase() -> int
## (0 none, 1 winding up, 2 struck / recovering), pack_alerted(howl: bool), pack_return(), pack_reset(),
## pack_size_k() -> float (the alpha is the biggest).

enum { IDLE, ALERT, HUNT, RETURN }
const STATE_NAMES: Array[StringName] = [&"idle", &"alert", &"hunt", &"return"]

## Members spawned within this distance of a pack's home join it (m).
const JOIN_R := 18.0
## The hero within this of a member (m) alerts the pack.
const AGGRO_R := 15.0
## Leash: the hero further than this from home (m) for LEASH_GRACE s and the pack gives up.
const LEASH := 35.0
const LEASH_GRACE := 0.8
## Going home, the pack only turns back for a hero within this of home (no ping-pong at the leash's edge).
const REAGGRO := 26.0
const ALERT_TIME := 0.9
## Seconds between two attacks (scaled per attack, see _next_cd()).
const TOKEN_CD := 1.15
## Packs with this many members alive (or more) may have two attackers (the second only after the first struck).
const TWO_TOKENS_AT := 4
const SECOND_CHANCE := 0.65
## Ring of the encircling wolves: drift speed (rad/s) and how far ahead (rad) a member's slot leads it.
const RING_SPEED := 0.32
const RING_LEAD := 0.45

signal state_changed(state: int)

var kind: StringName = &"wolf"
var members: Array = []
## The centre of the members' home spots.
var home := Vector3.ZERO
var state := IDLE
var state_t := 0.0
var attackers: Array = []
var token_cd := 0.0
var howled := false
var cleared := false
## Hunt stats (tests, tuning): attacks granted (tokens), wind-ups shown, bites / blows that hurt the hero, hops
## back out of a swing.
var attacks := 0
var windups := 0
var hits := 0
var evades := 0
var ring_dir := 1.0
var _ring_flip_t := 6.0
var _ring_t := 0.0
var _second_ok := false
var _leash_t := 0.0
var _reset_pending := false
var _rng := RandomNumberGenerator.new()


func _init(k: StringName = &"wolf") -> void:
	kind = k
	_rng.randomize()
	ring_dir = -1.0 if _rng.randf() < 0.5 else 1.0


func _ready() -> void:
	add_to_group("beast_pack")
	process_physics_priority = -10 # think before the members
	if not Game.hero_died.is_connected(_on_hero_died):
		Game.hero_died.connect(_on_hero_died)


## Whether the island's beasts take part in this run: `enemies=0` removes them; CORE's island bot (`corebot=...`, the
## slice walk and the traversal tests, which do not fight) runs without them unless `enemies=1` is given.
static func enabled() -> bool:
	if Game.arg("enemies", "") == "0":
		return false
	if Game.has_arg("corebot") and not Game.arg_on("enemies"):
		return false
	return true


## The pack of kind `k` whose home is within JOIN_R of `e` (still idle, not cleared), or a new one beside `e`.
static func join(e: Node3D, k: StringName) -> BeastPack:
	var best: BeastPack = null
	var best_d := JOIN_R
	for n in e.get_tree().get_nodes_in_group("beast_pack"):
		var p := n as BeastPack
		if p == null or p.kind != k or p.cleared or p.state != IDLE or (not p.members.is_empty() and p.alive_count() == 0):
			continue
		var d := Combat.flat(p.home - e.global_position).length()
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		best = BeastPack.new(k)
		best.name = "%sPack" % String(k).capitalize()
		e.get_parent().add_child(best)
		best.home = e.global_position
	best._add(e)
	return best


func _add(e: Node3D) -> void:
	if members.has(e):
		return
	members.append(e)
	var c := Vector3.ZERO
	var n := 0
	for m in members:
		if is_instance_valid(m):
			c += m.get("home_spot") if "home_spot" in m else (m as Node3D).global_position
			n += 1
	if n > 0:
		home = c / float(n)


# --- queries ---------------------------------------------------------------------------------------------------

func alive_members() -> Array:
	var out: Array = []
	for m in members:
		if is_instance_valid(m) and (m as Enemy).is_alive():
			out.append(m)
	return out


func alive_count() -> int:
	var n := 0
	for m in members:
		if is_instance_valid(m) and (m as Enemy).is_alive():
			n += 1
	return n


func is_hunting() -> bool:
	return state == ALERT or state == HUNT


func state_name() -> StringName:
	return STATE_NAMES[state]


## The alpha: the biggest member alive (it howls).
func alpha() -> Node3D:
	var best: Node3D = null
	var bk := -1.0
	for m in alive_members():
		var k := float(m.call("pack_size_k")) if m.has_method("pack_size_k") else 1.0
		if k > bk:
			bk = k
			best = m
	return best


func holds_token(e: Node) -> bool:
	return attackers.has(e)


## One-shot hints for the first fights (toasts through Game.say, once per run, only while playing; `nohints=1` turns
## them off): the first wolf wind-up, the first opening after a lunge that missed, the first boar charge.
const HINTS := {
	&"wolf_windup": ["Rueda con {dodge} o cúbrete con {guard}", "El lobo se agazapa y gruñe antes de saltar", "shield"],
	&"wolf_open": ["¡Ahora! Golpea con {attack}", "Tras un salto fallido, el lobo queda expuesto", "sword"],
	&"boar_windup": ["Esquiva la embestida con {dodge}", "Si choca contra una roca, quedará aturdido", "shield"],
}
static var _hinted := {}


static func hint(key: StringName) -> void:
	if _hinted.has(key) or not HINTS.has(key) or Game.arg_on("nohints") or not hero_ok():
		return
	_hinted[key] = true
	var h: Array = HINTS[key]
	Game.say(String(h[0]), String(h[1]), String(h[2]))


static func hero_ok() -> bool:
	var h = Game.hero
	return h != null and is_instance_valid(h) and h.is_alive() and Game.phase == Game.Phase.PLAY


# --- events from the members -----------------------------------------------------------------------------------

## A member noticed the hero, or was hurt / hooked (`by`): the hunt starts (with a howl the first time).
func alert(by: Node = null) -> void:
	if cleared or not hero_ok() or state == ALERT or state == HUNT:
		return
	if state == RETURN and Combat.flat(Game.hero.global_position - home).length() > LEASH:
		return # going home: a blow from beyond the leash does not bring them back (no pulling them across the map)
	var howl := not howled and kind == &"wolf" and alive_count() > 1
	howled = true
	var howler: Node = null
	if howl:
		howler = alpha()
		if howler == by:
			# the one that was hit does not stop to howl: another one does
			for m in alive_members():
				if m != by:
					howler = m
					break
	_set_state(ALERT if howl else HUNT)
	token_cd = maxf(token_cd, 1.4 if howl else 0.7)
	_leash_t = 0.0
	for m in alive_members():
		m.call("pack_alerted", m == howler)


## An attack is over (bit, missed, parried, interrupted): the token goes back with a pause before the next one.
func release(e: Node, cd_scale: float = 1.0) -> void:
	if not attackers.has(e):
		return
	attackers.erase(e)
	if attackers.is_empty():
		token_cd = maxf(token_cd, _next_cd() * cd_scale)
	else:
		token_cd = maxf(token_cd, 0.35)


func on_member_died(e: Node) -> void:
	attackers.erase(e)
	token_cd = maxf(token_cd, 0.6)
	if alive_count() == 0:
		cleared = true
		attackers.clear()
		set_physics_process(false)


## The pause before the next attack: big packs press harder; a small pack (the forest road's first one, 3 wolves:
## the fight that teaches the roll and the combo) leaves a little more time between its attacks; the last one alone
## is warier.
func _next_cd() -> float:
	var n := alive_count()
	var k := 1.0
	if n >= 4:
		k = 0.6
	elif n == 1:
		k = 1.35
	elif members.size() <= 3:
		k = 1.2
	return TOKEN_CD * k * _rng.randf_range(0.8, 1.3)


# --- the ring --------------------------------------------------------------------------------------------------

## Where member `e` should stand round the hero (its ring slot): the members keep their order round him, evenly
## spaced, and the slots lead each one a little in the drift direction, so the ring turns. `r` its radius.
func slot_for(e: Node3D, r: float) -> Vector3:
	var hp: Vector3 = Game.hero.global_position
	var ang := float(e.get_meta(&"slot_ang", atan2(e.global_position.z - hp.z, e.global_position.x - hp.x)))
	return hp + Vector3(cos(ang), 0.0, sin(ang)) * r


func _update_ring() -> void:
	var ringed: Array = []
	for m in members:
		if is_instance_valid(m) and (m as Enemy).is_alive() and m.has_method("wants_slot") and bool(m.call("wants_slot")):
			ringed.append(m)
	var n := ringed.size()
	if n == 0:
		return
	var hp: Vector3 = Game.hero.global_position
	var angs: Array = []
	for m in ringed:
		var p := (m as Node3D).global_position
		angs.append([atan2(p.z - hp.z, p.x - hp.x), m])
	angs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var spacing := TAU / float(n)
	var sx := 0.0
	var sy := 0.0
	for i in n:
		var a := float(angs[i][0]) - spacing * float(i)
		sx += cos(a)
		sy += sin(a)
	var base := atan2(sy, sx)
	for i in n:
		var m: Node = angs[i][1]
		m.set_meta(&"slot_ang", base + spacing * float(i) + ring_dir * RING_LEAD)


# --- per tick ----------------------------------------------------------------------------------------------------

func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_t = 0.0
	if s != HUNT and s != ALERT:
		attackers.clear()
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	if cleared:
		return
	if alive_count() == 0:
		# every member dead or gone (freed): nothing left to lead
		cleared = true
		attackers.clear()
		set_physics_process(false)
		return
	state_t += delta
	token_cd = maxf(0.0, token_cd - delta)
	for i in range(attackers.size() - 1, -1, -1):
		var a = attackers[i]
		if not is_instance_valid(a) or not (a as Enemy).is_alive():
			attackers.remove_at(i)
	var ok := hero_ok()
	if _reset_pending:
		if ok:
			_do_reset()
		return
	match state:
		IDLE:
			if ok and _hero_near(AGGRO_R) and Combat.flat(Game.hero.global_position - home).length() < LEASH:
				alert(null)
			elif ok and kind == &"wolf":
				_ambient_howl(delta)
		ALERT:
			if not ok:
				_give_up()
			elif state_t >= ALERT_TIME:
				_set_state(HUNT)
			else:
				_ring_tick(delta)
		HUNT:
			if not ok:
				_give_up()
				return
			if Combat.flat(Game.hero.global_position - home).length() > LEASH:
				_leash_t += delta
				if _leash_t >= LEASH_GRACE:
					_give_up()
					return
			else:
				_leash_t = 0.0
			_ring_tick(delta)
			_grant_tokens()
		RETURN:
			if ok and Combat.flat(Game.hero.global_position - home).length() < REAGGRO and _hero_near(AGGRO_R * 0.8):
				alert(null)
				return
			var all_home := true
			for m in members:
				if is_instance_valid(m) and (m as Enemy).is_alive() and not bool(m.call("is_home")):
					all_home = false
					break
			if all_home:
				_set_state(IDLE)


func _ring_tick(delta: float) -> void:
	_ring_flip_t -= delta
	if _ring_flip_t <= 0.0:
		_ring_flip_t = _rng.randf_range(5.0, 9.0)
		ring_dir = -ring_dir
	_ring_t -= delta
	if _ring_t <= 0.0:
		_ring_t = 0.2
		_update_ring()


func _hero_near(r: float) -> bool:
	var hp: Vector3 = Game.hero.global_position
	for m in members:
		if is_instance_valid(m) and (m as Enemy).is_alive():
			var d := (m as Node3D).global_position - hp
			if Vector2(d.x, d.z).length() < r and absf(d.y) < 6.0:
				return true
	return false


func _grant_tokens() -> void:
	var flank := _flank_chance()
	if token_cd > 0.0 and not flank:
		return
	var cap := 1
	if attackers.size() == 1:
		# a second attacker only in a big pack: sometimes once the first one has struck, or at once when the hero is
		# busy swinging at another (a telegraphed bite at his back: the pack punishes button mashing)
		if alive_count() < TWO_TOKENS_AT:
			return
		if not flank and (not _second_ok or int(attackers[0].call("attack_phase")) < 2):
			return
		cap = 2
	if attackers.size() >= cap:
		return
	var best: Node = null
	var best_s := INF
	var hp: Vector3 = Game.hero.global_position
	var cf := Vector3.ZERO
	if Game.camera and is_instance_valid(Game.camera) and Game.camera.has_method("yaw_basis"):
		cf = -(Game.camera.call("yaw_basis") as Basis).z
	var hf: Vector3 = (Game.hero as Node3D).call("forward") if flank else Vector3.ZERO
	for m in members:
		if not is_instance_valid(m) or not (m as Enemy).is_alive() or attackers.has(m) or not bool(m.call("member_ready")):
			continue
		var d := Combat.flat((m as Node3D).global_position - hp)
		if flank and (d.length() > 6.5 or hf.dot(d.normalized()) > -0.1):
			continue # the flank token: only for one behind him
		var s := d.length() + _rng.randf() * 1.5
		# prefer the ones the player can see (in front of the camera): an attack from behind is still telegraphed
		# by its growl, but the view should show most of them
		if cf != Vector3.ZERO and d.length() > 0.1 and cf.dot(d.normalized()) < 0.15:
			s += 3.5
		if s < best_s:
			best_s = s
			best = m
	if best == null:
		return
	if attackers.is_empty():
		_second_ok = _rng.randf() < SECOND_CHANCE
	attackers.append(best)
	attacks += 1
	best.call("begin_attack")


## The hero is swinging at the pack (a blow or the heavy spin) in a big pack: a ready wolf behind him may go for
## his back at once (rolled once per FLANK_ROLL s).
const FLANK_CHANCE := 0.75
const FLANK_ROLL := 1.2
var _flank_t := 0.0


func _flank_chance() -> bool:
	if alive_count() < TWO_TOKENS_AT or attackers.size() >= 2:
		return false
	var h = Game.hero
	var hs := int(h.get("state")) if h != null else -1
	if hs != Hero.St.ATTACK and hs != Hero.St.HEAVY:
		return false
	if state_t < _flank_t:
		return false
	_flank_t = state_t + FLANK_ROLL
	return _rng.randf() < FLANK_CHANCE


func _give_up() -> void:
	_set_state(RETURN)
	for m in alive_members():
		m.call("pack_return")


func _on_hero_died() -> void:
	if cleared:
		return
	_reset_pending = true
	if state != IDLE:
		_give_up()
		if kind == &"wolf":
			# the alpha howls over the fallen hero before the pack trots home
			var a := alpha()
			if a != null and a.has_method("victory_howl"):
				a.call("victory_howl")


## A pack at rest howls now and then while the hero is within earshot but not yet near (the forest warns him).
const HOWL_EARSHOT := Vector2(32.0, 80.0)
var _ambient_t := 12.0


func _ambient_howl(delta: float) -> void:
	_ambient_t -= delta
	if _ambient_t > 0.0:
		return
	_ambient_t = _rng.randf_range(24.0, 40.0)
	var d := Combat.flat(Game.hero.global_position - home).length()
	if d < HOWL_EARSHOT.x or d > HOWL_EARSHOT.y:
		return
	var a := alpha()
	if a != null and a.has_method("idle_howl"):
		a.call("idle_howl")


## The hero is back (respawned): every survivor at its home spot with full health, the pack idle.
func _do_reset() -> void:
	_reset_pending = false
	attackers.clear()
	token_cd = 0.0
	_leash_t = 0.0
	_set_state(IDLE)
	for m in alive_members():
		m.call("pack_reset")
