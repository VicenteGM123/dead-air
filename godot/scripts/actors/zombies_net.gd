# ZombieNet — the online co-op layer of the ZombieManager (scripts/actors/zombies.gd; RECONCILE R16/R17, MP_SPEC §7).
# Built by ZombieManager.reset() only while an MP game runs (game.net.inGame); solo never creates it, so solo runs the
# old zombies.gd code paths untouched. Owned by mp-zombies.
#
# HOST
#   * Targets: every zombie chases z.tgt (z.tgtId = peer id), the nearest targetable player BY PATH — nav.gd solves
#     one multi-source flow field seeded from targetsList() and labels every cell with the target that reached it
#     (nav.goalIdAt). A different label must hold RETARGET s before the zombie switches (never mid-swing / mid
#     ability); a target that left the set is dropped at once. Target set: net.targets(); when empty the alive, not
#     downed, not off-air players (hidden / in a commercial: zombies keep coming, hurt() refuses); else nobody (idle).
#   * Contact hits on a RemotePlayer: zombies.net_hurt(dmg, from, kb, zid, kind) to its peer (hurtRemote).
#   * Outbox: every replicated event of the frame, flushed once in late() as ONE zombies.net_ev(t, list) per client
#     (t = host time.realNow). A hit requested by a client is not echoed to that client. Entries (Arrays):
#       [EV_SPAWN, id, type, variant, scale, pos, yaw, entryId, flags (1 pos-spawn, 2 silent, 4 screen), hp, maxHp,
#        fromRound (-1 none)]
#       [EV_HIT, id, dmg, hpAfter, flags (1 head, 2 killed, 4 upgraded), zone, point|null, dir|null, cause, weaponId, by]
#       [EV_KILL, id, head, cause, weaponId, dir|null, corpse, by (-1 none), pos, wfx|null, totalKills, killsThisRound,
#        killsBy[by]]
#       [EV_DESPAWN, id, fx] · [EV_STUN, id, seconds, stars] · [EV_FREEZE, on] · [EV_LURE, pos|null, radius (-1 = INF)]
#       [EV_REENTER, id, entryId, pos, yaw, screen] · [EV_TYPE, id, kind, args] · [EV_GAWK, id, gawkT, gawkAt|null]
#   * Stream 'z' (unreliable ordered, 20 Hz; 4 Hz header-only when nothing lives), little endian:
#       header  u8 ver=1 · u8 n · u16 seq · f64 hostT (time.realNow) · u8 nT · nT x s32 target peer ids
#       zombie  u32 id · u8 state (low nibble: 0 approach 1 queue 2 tear 3 vault 4 screen/tele 5 screen/emerge
#               6 screen/drop 7 chase 8 attack) | mode << 4 (index of z.flags.mode in def.netModes) · u8 flags (1 visible,
#               2 lured, 4 anim.down, 8 stunned, 16 anim.back, 32 sock bite, 64 pose block, 128 extra block) ·
#               s16 x/y/z (cm) · u16 yaw · u8 speed (x20) · u8 attack (x255) · u8 climb (x200) · u8 target index (255
#               none) · u16 hp / maxHp (x65535)  [pose: s8 pitch (x40), u8 sx, sy, sz (x100)]  [extra: u8 len + bytes:
#               sock u8 ph (x256), u8 H (x500); forecaster s8 legYaw (x100)]
#   * Client damage batches (zombies.net_dmgBatch(list)) go through zombies.damage with info.by = the sender.
# CLIENT
#   * Puppets: built from EV_SPAWN with the same type build() and the host's variant / scale (same hit zones),
#     interpolated INTERP s behind the host clock (min-tracking offset like RemotePlayer) and extrapolated <= EXTRAP s;
#     manager state changes replay the host's one-shot cues (vault, landing, emerge, drop, swipe, tear yank); types
#     run def.puppet(game, z, dt) (mode-driven flavour) and def.puppetEvent(game, z, kind, args) for EV_TYPE. Events
#     are applied on the same timeline, except spawns, despawns, freeze, lure, the local player's own kills and
#     fcPop (at once).
#   * zombies.damage on a client = predict(): the solo LOCAL feedback (hit reaction, confetti, zmb_hit, hitmarker,
#     zombie:hit {by: localId, predicted: true}) + one request entry; flushed once per frame as
#     zombies.net_dmgBatch(list). Returns the predicted kill (no kill event: zombie:kill comes from the host).
#   * stun / knockback / setLure called on a client become requests (stunReq / knockReq / lureReq).
extends RefCounted

const INTERP := 0.1
const EXTRAP := 0.15
const SNAP_EVERY := 0.05
const IDLE_SNAP := 0.25
const RETARGET := 0.4
const LOST := 3.0
const RN := 8                    # ring samples per puppet
const NF := 12                   # floats per sample: yaw speed attack climb pitch sx sy sz ph H legYaw hpFrac
const NI := 4                    # ints per sample: state mode flags target
const STATES := ["approach", "queue", "tear", "vault", "screen", "screen", "screen", "chase", "attack"]
const PHASES := ["", "", "", "", "tele", "emerge", "drop", "", ""]
const BUSY := {"crouch": true, "leap": true, "twirl": true, "jab": true, "rushTele": true, "rush": true, "bump": true, "flashWind": true}

const EV_SPAWN := 1
const EV_HIT := 2
const EV_KILL := 3
const EV_DESPAWN := 4
const EV_STUN := 5
const EV_FREEZE := 6
const EV_LURE := 7
const EV_REENTER := 8
const EV_TYPE := 9
const EV_GAWK := 10

# Per-puppet sample ring (packed arrays written in place through methods: no per-sample allocation).
class Ring extends RefCounted:
	var n := 0
	var head := 0
	var t := PackedFloat64Array()
	var pos := PackedVector3Array()
	var f := PackedFloat32Array()
	var i := PackedInt32Array()

	func _init() -> void:
		t.resize(8)
		pos.resize(8)
		f.resize(8 * 12)
		i.resize(8 * 4)

	func clear() -> void:
		n = 0
		head = 0

	func put(tt: float, p: Vector3, yaw: float, speed: float, attack: float, climb: float, pitch: float, sx: float, sy: float,
			sz: float, ph: float, hh: float, leg: float, hpf: float, state: int, mode: int, flags: int, tgt: int) -> void:
		var s := head
		head = (head + 1) % 8
		n = mini(n + 1, 8)
		t[s] = tt
		pos[s] = p
		var o := s * 12
		f[o] = yaw
		f[o + 1] = speed
		f[o + 2] = attack
		f[o + 3] = climb
		f[o + 4] = pitch
		f[o + 5] = sx
		f[o + 6] = sy
		f[o + 7] = sz
		f[o + 8] = ph
		f[o + 9] = hh
		f[o + 10] = leg
		f[o + 11] = hpf
		var q := s * 4
		i[q] = state
		i[q + 1] = mode
		i[q + 2] = flags
		i[q + 3] = tgt

var M                            # the ZombieManager
var game
var net
var client := false
var applying := false            # true while a host message is being applied on a client (lets the guarded APIs run)
# host
var _ob: Array = []
var _obEx: Array = []
var _snapAcc := 0.0
var _snapSeq := 0
var _sbuf := PackedByteArray()
var _tids: Array = []
var _tset: Array = []
var _tsetFrame := -1
var _warned := {}
# client
var _req: Array = []
var _tl: Array = []
var _off := 0.0
var _hasOff := false
var _lastSeq := -1
var _tin := PackedInt32Array()
var _i0 := -1
var _i1 := -1
var _k := 0.0
var _ex := 0.0
var _areaT := 0.0
var _lastArea := {}

func _init(m) -> void:
	M = m
	game = m.game
	net = m.net
	client = net != null and net.isClient
	_tin.resize(8)

static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func _warnOnce(k: String, msg: String) -> void:
	if not _warned.has(k):
		_warned[k] = true
		push_warning(msg)

# ================================================================================================ shared helpers
# Players that count for spawners (alive or downed, never off air) — RECONCILE R6.
func _present() -> Array:
	var out: Array = []
	for p in net.players():
		if p != null and p.get("offAir") != true and (p.alive or p.get("downed") == true):
			out.append(p)
	return out

func facePos(from: Vector3) -> Vector3:
	var best = null
	var bd := INF
	for p in net.players():
		if p == null or p.get("offAir") == true:
			continue
		var d: float = (p.pos as Vector3).distance_squared_to(from)
		if d < bd:
			bd = d
			best = p
	if best == null:
		best = game.player
	return best.pos if best != null else Vector3.ZERO

func minPlayerDist(pos: Vector3) -> float:
	var bd := INF
	for p in _present():
		var d: float = M._hypot(pos.x - p.pos.x, pos.z - p.pos.z)
		if d < bd:
			bd = d
	if bd == INF and game.player != null:
		bd = M._hypot(pos.x - game.player.pos.x, pos.z - game.player.pos.z)
	return bd

# Spawner areas: every present player's area (weight 1) + the areas behind their open doors (0.5).
func activeAreas() -> Dictionary:
	var L = game.level
	var w := {}
	var heres: Array = []
	for p in _present():
		var id := int(net.idOf(p))
		var here = M._f(p, "area")
		if not here:
			here = L.areaAt(p.pos.x, p.pos.z)
		if not here:
			here = _lastArea.get(id)
		if not here:
			here = "lobby"
		_lastArea[id] = here
		w[here] = 1.0
		heres.append(here)
	if heres.is_empty():
		w["lobby"] = 1.0
		heres.append("lobby")
	for here in heres:
		for d in L.doors.values():
			var areas = M._f(d, "areas")
			if not M._f(d, "open", false) or areas == null or not areas.has(here):
				continue
			var other = areas[1] if areas[0] == here else areas[0]
			if not w.has(other):
				w[other] = 0.5
	return w

# ================================================================================================ HOST
func targetsList() -> Array:
	var fr := int(game.time.frame)
	if fr == _tsetFrame:
		return _tset
	_tsetFrame = fr
	_tset.clear()
	for p in net.targets():
		_tset.append(p)
	if _tset.is_empty():
		for p in net.players():
			if p != null and p.alive and p.get("downed") != true and p.get("offAir") != true:
				_tset.append(p)
	return _tset

func targetOf(z):
	if client:
		var id := int(z.get("tgtId", 0))
		return net.playerById(id) if id != 0 else null
	return z.get("tgt")

func hostPre(dt: float) -> void:
	var T := targetsList()
	for z in M.alive:
		_retarget(z, dt, T)

func _busy(z: Dictionary) -> bool:
	if z.state == "attack":
		return true
	var m = z.flags.get("mode")
	return m is String and BUSY.has(m)

func _retarget(z: Dictionary, dt: float, T: Array) -> void:
	var cur := int(z.get("tgtId", 0))
	var curP = net.playerById(cur) if cur != 0 else null
	if curP != null and not T.has(curP):
		curP = null
	var cand := 0
	var nav = game.nav
	if nav != null and nav.has_method("goalIdAt"):
		cand = int(nav.goalIdAt(z.pos.x, z.pos.z))
		if cand != 0:
			var cp = net.playerById(cand)
			if cp == null or not T.has(cp):
				cand = 0
	if cand == 0:
		var best = null
		var bd := INF
		for p in T:
			var d: float = (p.pos as Vector3).distance_squared_to(z.pos)
			if d < bd:
				bd = d
				best = p
		cand = int(net.idOf(best)) if best != null else 0
	if curP == null:
		z["tgtId"] = cand
		z["tgtT"] = 0.0
	elif cand != 0 and cand != cur:
		if _busy(z):
			z["tgtT"] = 0.0
		else:
			z["tgtT"] = float(z.get("tgtT", 0.0)) + dt
			if z.tgtT >= RETARGET:
				z["tgtId"] = cand
				z["tgtT"] = 0.0
	else:
		z["tgtT"] = 0.0
	var id := int(z.tgtId)
	z["tgt"] = net.playerById(id) if id != 0 else null

# No target at all (everyone down / off air): stand, fall, keep the bookkeeping.
func idle(z: Dictionary, dt: float) -> void:
	z.anim.speed = 0.0
	z.anim.attack = 0.0
	if z.state == "attack":
		z.state = "chase"
	M._fall(z, dt)
	M._bookkeep(z, dt)
	M._place(z)

func hurtRemote(p, dmg, z, kb, kind) -> bool:
	if p == null or not p.alive or p.get("downed") == true or p.get("offAir") == true or p.get("hidden") == true \
			or p.get("inCommercial") == true or p.get("invulnerable") == true:
		return false
	var id := int(net.idOf(p))
	if id == 0 or id == net.localId:
		return false
	net.toPeer(id, "zombies", "hurt", [float(dmg), z.pos, kb if kb is Vector3 else Vector3.ZERO, int(z.id), str(kind)])
	return true

# Zombies are pushed off remote players' bodies (the owner pushes its own player out of the puppets).
func blockRemotes() -> void:
	for p in net.players():
		if p == null or p == game.player or not p.alive or p.get("downed") == true or p.get("offAir") == true or p.get("hidden") == true:
			continue
		var prad := float(M._f(p, "radius", 0.38))
		var pp: Vector3 = p.pos
		for z in M.alive:
			if z.state != "chase" and z.state != "attack":
				continue
			if absf(pp.y - z.pos.y) > 1.2:
				continue
			var dx: float = pp.x - z.pos.x
			var dz: float = pp.z - z.pos.z
			var rr: float = prad + z.radius * 0.9
			var d2 := dx * dx + dz * dz
			if d2 >= rr * rr:
				continue
			var d := sqrt(d2)
			if d == 0.0:
				d = 1e-3
			var o := rr - d
			M._moveCircle(z, Vector3(-(dx / d) * o * 0.4, 0, -(dz / d) * o * 0.4), z.radius, z.height, 0.45)
			z.group.position = z.pos

# economy.add(n, reason, by) routes the award to the attacker (RECONCILE R1/R15).
func award(e, n, reason: String, by) -> void:
	if by == null:
		by = net.localId
	if e.has_method("add") and e.get_method_argument_count("add") >= 3:
		e.add(n, reason, by)
	elif int(by) == net.localId:
		e.add(n, reason)
	else:
		_warnOnce("award", "[zombies] economy.add(n, reason, to) missing: points for remote players are dropped")

# --- registration + outbox
func added(z: Dictionary, posSpawn: bool, silent: bool) -> void:
	if client:
		return
	z["tgtId"] = 0
	z["tgtT"] = 0.0
	z["tgt"] = null
	z["_gk"] = 0.0
	if not z.has("pP"):
		z["pP"] = 0.0
		z["pX"] = 1.0
		z["pY"] = 1.0
		z["pZ"] = 1.0
	var v = z.model.get("variant") if z.model is Dictionary else null
	var e = z.get("entry")
	var entryId := ""
	var fl := 0
	if posSpawn:
		fl |= 1
		if silent:
			fl |= 2
	elif e is Dictionary:
		entryId = str(e.get("id", ""))
		if e.get("kind") == "screen":
			fl |= 4
	_out([EV_SPAWN, int(z.id), str(z.type), str(v) if v != null else "", float(z.scale), z.pos, float(z.yaw), entryId, fl,
		float(z.hp), float(z.maxHp), int(z.fromRound) if z.fromRound != null else -1])

func _out(e: Array, ex := 0) -> void:
	_ob.append(e)
	_obEx.append(ex)

func outHit(z, dmg, head, zone, point, dir, cause, weaponId, by, killed, info: Dictionary) -> void:
	if client:
		return
	var fl := (1 if head else 0) | (2 if killed else 0) | (4 if M._t(info.get("upgraded", false)) else 0)
	_out([EV_HIT, int(z.id), float(dmg), float(maxf(0.0, z.hp)), fl, str(zone), point if point is Vector3 else null,
		dir if dir is Vector3 else null, str(cause), str(weaponId) if weaponId != null else "", int(by) if by != null else -1],
		int(by) if (info.get("_req") == true and by != null) else 0)

func outKill(z, info: Dictionary, by) -> void:
	var R = game.rounds
	var kb := 0
	if R != null and by != null and R.get("killsBy") is Dictionary:
		kb = int(R.killsBy.get(int(by), 0))
	var d = info.get("dir")
	_out([EV_KILL, int(z.id), M._t(info.get("head", false)), str(info.get("cause", "bullet")), str(info.get("weaponId")) if info.get("weaponId") != null else "",
		d if d is Vector3 else null, info.get("corpse") != false, int(by) if by != null else -1, z.pos, info.get("wfx"),
		int(R.totalKills) if R != null else 0, int(R.killsThisRound) if R != null else 0, kb])

func outDespawn(z, fx: bool) -> void:
	_out([EV_DESPAWN, int(z.id), fx])

func outStun(z, seconds: float) -> void:
	var stars: bool = seconds > 0.4 and (z.state == "chase" or z.state == "attack")
	_out([EV_STUN, int(z.id), float(seconds), stars])

func outFreeze(on: bool) -> void:
	_out([EV_FREEZE, on])

func outLure(pos, radius: float) -> void:
	_out([EV_LURE, pos, float(radius) if is_finite(radius) else -1.0])

func outReenter(z) -> void:
	var e = z.get("entry")
	_out([EV_REENTER, int(z.id), str(e.get("id", "")) if e is Dictionary else "", z.pos, float(z.yaw), e is Dictionary and e.get("kind") == "screen"])

func outType(z, kind: String, args: Array) -> void:
	_out([EV_TYPE, int(z.id), kind, args])

func request(method: String, args: Array) -> void:
	net.toHost("zombies", method, args)

func late() -> void:
	if client:
		if not _req.is_empty():
			net.toHost("zombies", "dmgBatch", [_req])
			_req = []
		return
	_flush()
	_snapshot(float(game.time.realDt))

func _flush() -> void:
	if _ob.is_empty():
		return
	var t := float(game.time.realNow)
	for id in net.peers:
		if id == net.localId:
			continue
		var list: Array = []
		for k in _ob.size():
			if _obEx[k] != id:
				list.append(_ob[k])
		if not list.is_empty():
			net.toPeer(id, "zombies", "ev", [t, list])
	_ob.clear()
	_obEx.clear()

static func stateCode(z: Dictionary) -> int:
	match z.state:
		"approach":
			return 0
		"queue":
			return 1
		"tear":
			return 2
		"vault":
			return 3
		"screen":
			var e = z.get("entry")
			var ph = e.get("phase") if e is Dictionary else "tele"
			return 5 if ph == "emerge" else (6 if ph == "drop" else 4)
		"attack":
			return 8
	return 7

static func _q8(v: float, k: float) -> int:
	return clampi(int(roundf(v * k)), 0, 255)

static func _s16(v: float) -> int:
	return clampi(int(roundf(v * 100.0)), -32768, 32767)

func _snapshot(dt: float) -> void:
	_snapAcc += dt
	var list: Array = M.alive
	var period := SNAP_EVERY if not list.is_empty() else IDLE_SNAP
	if _snapAcc < period:
		return
	_snapAcc = minf(_snapAcc - period, period)
	if net.peers.size() < 2:
		return
	_tids.clear()
	for z in list:
		var id := int(z.get("tgtId", 0))
		if id != 0 and not _tids.has(id) and _tids.size() < 8:
			_tids.append(id)
	var need := 13 + 4 * _tids.size() + list.size() * 30
	if _sbuf.size() < need:
		_sbuf.resize(need)
	var b := _sbuf
	b.encode_u8(0, 1)
	b.encode_u16(2, _snapSeq)
	_snapSeq = (_snapSeq + 1) & 0xFFFF
	b.encode_double(4, float(game.time.realNow))
	b.encode_u8(12, _tids.size())
	var o := 13
	for id in _tids:
		b.encode_s32(o, int(id))
		o += 4
	var cnt := 0
	var lureOn: bool = M.lure != null
	for z in list:
		if cnt >= 255 or z.removed or z.dead:
			continue
		# gawk replication (sign-on / uplink set z.gawkT host-side)
		var gk: float = z.gawkT
		if gk > float(z.get("_gk", 0.0)) + 0.05:
			_out([EV_GAWK, int(z.id), gk, z.gawkAt])
		z["_gk"] = gk
		cnt += 1
		var f: Dictionary = z.flags
		var def: Dictionary = z.def
		var mode := 0
		var nm = def.get("netModes")
		if nm is Array and f.get("mode") != null:
			mode = maxi(0, nm.find(f.mode)) & 15
		var fl := 0
		if z.group != null and z.group.visible:
			fl |= 1
		if lureOn and z.lured:
			fl |= 2
		if z.anim.get("down", false):
			fl |= 4
		if z.stun > 0.0:
			fl |= 8
		if z.anim.get("back", false):
			fl |= 16
		if f.get("bit", false) == true:
			fl |= 32
		var pP := float(z.get("pP", 0.0))
		var pX := float(z.get("pX", 1.0))
		var pY := float(z.get("pY", 1.0))
		var pZ := float(z.get("pZ", 1.0))
		var pose := absf(pP) > 1e-3 or absf(pX - 1.0) > 1e-3 or absf(pY - 1.0) > 1e-3 or absf(pZ - 1.0) > 1e-3
		if pose:
			fl |= 64
		var extra := 0
		if z.type == "sock_hopper":
			extra = 2
		elif z.type == "forecaster":
			extra = 1
		if extra > 0:
			fl |= 128
		b.encode_u32(o, int(z.id))
		b.encode_u8(o + 4, (stateCode(z) & 15) | (mode << 4))
		b.encode_u8(o + 5, fl)
		b.encode_s16(o + 6, _s16(z.pos.x))
		b.encode_s16(o + 8, _s16(z.pos.y))
		b.encode_s16(o + 10, _s16(z.pos.z))
		b.encode_u16(o + 12, int(fposmod(z.yaw, TAU) / TAU * 65536.0) & 0xFFFF)
		b.encode_u8(o + 14, _q8(float(z.anim.get("speed", 0.0)), 20.0))
		b.encode_u8(o + 15, _q8(float(z.anim.get("attack", 0.0)), 255.0))
		b.encode_u8(o + 16, _q8(float(z.anim.get("climb", 0.0)), 200.0))
		var ti := _tids.find(int(z.get("tgtId", 0)))
		b.encode_u8(o + 17, ti if ti >= 0 else 255)
		b.encode_u16(o + 18, clampi(int(z.hp / maxf(1.0, z.maxHp) * 65535.0), 0, 65535))
		o += 20
		if pose:
			b.encode_s8(o, clampi(int(roundf(pP * 40.0)), -127, 127))
			b.encode_u8(o + 1, _q8(pX, 100.0))
			b.encode_u8(o + 2, _q8(pY, 100.0))
			b.encode_u8(o + 3, _q8(pZ, 100.0))
			o += 4
		if extra > 0:
			b.encode_u8(o, extra)
			if z.type == "sock_hopper":
				b.encode_u8(o + 1, int(fposmod(float(f.get("ph", 0.0)), 1.0) * 256.0) & 255)
				b.encode_u8(o + 2, _q8(float(f.get("H", 0.26)), 500.0))
			else:
				b.encode_s8(o + 1, clampi(int(roundf(float(z.anim.get("legYaw", 0.0)) * 100.0)), -127, 127))
			o += 1 + extra
	b.encode_u8(1, cnt)
	net.stream("z", b.slice(0, o))

# --- client requests applied on the host
func onDmgBatch(list) -> void:
	if client or not (list is Array) or not ["playing", "down"].has(game.state):
		return
	var by := int(net.sender)
	for e in list:
		if not (e is Array) or e.size() < 11 or not (e[0] is int):
			continue
		var z = M._byId.get(e[0])
		if z == null or z.dead or z.removed:
			continue
		var amount = e[1]
		if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount) <= 0.0 or float(amount) > 1e7:
			continue
		var bits: int = e[2] if e[2] is int else 0
		var info := {"head": (bits & 1) != 0, "zone": str(e[3]), "by": by, "_req": true, "hitmarker": false,
			"shot": e[9] if e[9] is int else 0}
		if str(e[4]) != "":
			info.weaponId = str(e[4])
		if e[5] is Vector3:
			info.point = e[5]
		if e[6] is Vector3:
			info.dir = e[6]
		if (e[7] is float or e[7] is int) and float(e[7]) > 0.0:
			info.knockback = clampf(float(e[7]), 0.0, 6.0)
		if str(e[8]) != "":
			info.cause = str(e[8])
		if bits & 2:
			info.upgraded = true
		if bits & 4:
			info.points = false
		if bits & 8:
			info.primary = false
		if bits & 16:
			info.ghost = true
		if str(e[10]) != "":
			info.signal = str(e[10])
		M.damage(z, float(amount), info)

# ================================================================================================ VICTIM
# zombies.net_hurt on the victim's peer: the solo hit pattern on the local player.
func onHurt(dmg, fromPos, kb, zid, kind) -> void:
	var p = game.player
	if p == null or not (dmg is float or dmg is int) or not ["playing", "down"].has(game.state):
		return
	if p.hurt(clampf(float(dmg), 0.0, 1000.0), fromPos if fromPos is Vector3 else null):
		var ev := {"z": M._byId.get(zid) if zid is int else null, "dmg": dmg}
		if kind is String and kind != "":
			ev.kind = kind
		game.events.emit("zombie:attack", ev)
		if kb is Vector3 and kb.length_squared() > 0.0 and p.has_method("knockback"):
			p.knockback(kb)
		if kind == "rush" and game.fx != null:
			game.fx.shake(0.35, 0.3)

# ================================================================================================ CLIENT
func _renderT(now: float) -> float:
	return now - _off - INTERP

# zombies.damage on a client: the solo local feedback + a request (RECONCILE R17).
func predict(z, amount, info: Dictionary) -> bool:
	var g = game
	var frame: int = g.time.frame
	var zone = info.get("zone")
	var head = info.get("head")
	var zoneMul = null
	if zone == null and z._rayFrame == frame:
		zone = z._rayZone
		zoneMul = z._rayMul
		if head == null:
			head = z._rayHead
	if head == null:
		head = zone == "head"
	head = M._t(head)
	if zone == null:
		zone = "head" if head else "torso"
	if zoneMul == null:
		zoneMul = 0.8 if zone == "limb" else M._zoneMul(z, zone)
	var mul := float(zoneMul)
	if z.state == "screen" and z.entry != null and z.entry.get("inGlass"):
		mul *= float(M._Z().screenMul)
	var dmg: float = float(amount) * mul
	var full: Dictionary = info.duplicate()
	full.head = head
	full.zone = zone
	if z.def.get("onDamage") is Callable:
		var r = z.def.onDamage.call(g, z, dmg, full)
		if (r is float or r is int) and is_finite(float(r)):
			dmg = float(r)
	var hp0 := float(z.get("hpPred", z.hp))
	if M._oneTake and z.type != "boss_baron":
		if z.def.get("oneTakeMul"):
			dmg *= float(z.def.oneTakeMul)
		else:
			dmg = maxf(dmg, hp0)
	if not (dmg > 0.0):
		return false
	var killed := hp0 - dmg <= 0.0
	z["hpPred"] = maxf(0.0, hp0 - dmg)
	z["_reqT"] = _now()
	var weaponId = info.get("weaponId")
	var cause = info.get("cause")
	if not cause:
		cause = "melee" if weaponId == "melee" else "bullet"
	if not killed:
		z.anim.hurt = 1.0
		M._kick(z, minf(1.2, 0.45 + dmg / maxf(60.0, z.maxHp) * 1.5))
	var idir = info.get("dir")
	var ipoint = info.get("point")
	_hitFx(z, ipoint, idir, frame)
	if not killed and M._hitSfx < 2:
		M._hitSfx += 1
		M._play("zmb_hit", {"pos": ipoint if ipoint != null else z.pos, "rate": 0.9 + randf() * 0.25})
	g.events.emit("zombie:hit", {"z": z, "dmg": dmg, "head": head, "weaponId": weaponId, "point": ipoint if ipoint != null else z.pos,
		"zone": zone, "cause": cause, "upgraded": M._t(info.get("upgraded", false)), "by": net.localId, "predicted": true})
	if info.get("hitmarker") != false and g.hud != null and g.hud.has_method("hitmarker") and z._hmFrame != frame:
		z._hmFrame = frame
		g.hud.hitmarker(head, killed)
	var bits := (1 if head else 0) | (2 if M._t(info.get("upgraded", false)) else 0) | (4 if info.get("points") == false else 0) \
		| (8 if info.get("primary") == false else 0) | (16 if M._t(info.get("ghost", false)) else 0)
	var shot = info.get("shot")
	var kb = info.get("knockback")
	_req.append([int(z.id), float(amount), bits, str(zone), str(weaponId) if weaponId != null else "",
		DAU.v3(ipoint) if ipoint != null else null, DAU.v3(idir) if idir != null else null,
		float(kb) if (kb is float or kb is int) else 0.0, str(cause), int(shot) if shot is int else frame,
		str(info.get("signal")) if info.get("signal") != null else ""])
	return killed

func _hitFx(z, ipoint, idir, frame: int) -> void:
	if ipoint == null or z._fxFrame == frame:
		return
	z._fxFrame = frame
	var bo := {"shape": "confetti", "count": 5, "speed": 3, "size": 0.055, "cone": 1.3, "life": 0.9}
	if idir != null:
		bo.dir = -DAU.v3(idir)
	M._burst(ipoint, bo)
	M._burst(ipoint, {"shape": "puff", "count": 2, "size": 0.09, "life": 0.45, "speed": 1.2, "colors": ["#E4F2E6", "#F4F1E8"]})

# --- events from the host
func onEvents(t, list) -> void:
	if not (list is Array):
		return
	var tt := float(t) if (t is float or t is int) else 0.0
	var now := _now()
	for e in list:
		if not (e is Array) or e.is_empty() or not (e[0] is int):
			continue
		var code: int = e[0]
		var at_once: bool = code == EV_SPAWN or code == EV_DESPAWN or code == EV_FREEZE or code == EV_LURE \
			or (code == EV_KILL and e.size() > 7 and e[7] is int and e[7] == net.localId) \
			or (code == EV_TYPE and e.size() > 2 and e[2] == "fcPop")
		if at_once and _tl.is_empty():
			_apply(e, tt)
		elif code == EV_SPAWN or code == EV_DESPAWN:
			_apply(e, tt)               # never delayed (snapshots refer to them)
		else:
			_tl.append([tt, e, now])

func _runTimeline(rt: float, now: float) -> void:
	while not _tl.is_empty():
		var q: Array = _tl[0]
		if _hasOff and float(q[0]) > rt and now - float(q[2]) < 0.35:
			break
		_tl.pop_front()
		_apply(q[1], float(q[0]))

func _apply(e: Array, t: float) -> void:
	applying = true
	match int(e[0]):
		EV_SPAWN:
			if e.size() >= 12:
				_spawnPuppet(e, t)
		EV_HIT:
			if e.size() >= 12:
				_applyHit(e)
		EV_KILL:
			if e.size() >= 13:
				_applyKill(e)
		EV_DESPAWN:
			var z = M._byId.get(e[1]) if e.size() >= 3 else null
			if z != null and not z.removed:
				if e[2] == true and z.group != null and z.group.visible:
					M._burst(z.pos + Vector3(0, 0.8, 0), {"shape": "static", "count": 16, "speed": 2})
				M.despawn(z, false)
		EV_STUN:
			var z = M._byId.get(e[1]) if e.size() >= 4 else null
			if z != null and not z.dead:
				z.stun = maxf(z.stun, float(e[2]))
				if e[3] == true and M._stars != null:
					M._stars.add(z, float(e[2]), 3, 0.22 * z.scale)
		EV_FREEZE:
			M.frozen = e.size() >= 2 and e[1] == true
		EV_LURE:
			if e.size() >= 3:
				M.lure = e[1] if e[1] is Vector3 else null
				M.lureR = float(e[2]) if float(e[2]) >= 0.0 else INF
				M._lureField = null
				if M.lure == null:
					for z in M.alive:
						z.anim.down = false
						z.lured = false
		EV_REENTER:
			var z = M._byId.get(e[1]) if e.size() >= 6 else null
			if z != null and not z.dead and e[3] is Vector3:
				_reenter(z, str(e[2]), e[3], float(e[4]), e[5] == true, t)
		EV_TYPE:
			var z = M._byId.get(e[1]) if e.size() >= 4 else null
			if z != null and z.def.get("puppetEvent") is Callable:
				z.def.puppetEvent.call(game, z, str(e[2]), e[3] if e[3] is Array else [])
		EV_GAWK:
			var z = M._byId.get(e[1]) if e.size() >= 4 else null
			if z != null and not z.dead:
				z.gawkT = float(e[2])
				z.gawkAt = e[3] if e[3] is Vector3 else null
	applying = false

func _spawnPuppet(e: Array, t: float) -> void:
	var id: int = e[1]
	if M._byId.has(id):
		return
	var g = game
	var type := str(e[2])
	var def := ZombieTypes.getType(type)
	var opts := {}
	if str(e[3]) != "":
		opts.variant = str(e[3])
	if e[11] is int and e[11] >= 0:
		opts.fromRound = e[11]
	var rnd: int = maxi(1, int(g.rounds.round) if g.rounds != null else 1)
	var z: Dictionary = M._record(def, rnd, opts)
	z.id = id
	if def.get("build") is Callable:
		def.build.call(g, z)
	if z.group == null:
		_warnOnce("build:" + type, "[zombies] puppet build failed for %s" % type)
		return
	M._finishBuild(z)
	z.hp = float(e[9])
	z.maxHp = maxf(1.0, float(e[10]))
	z.scale = float(e[4])
	DAU.setLayerRecursive(z.group, Config.LAYERS.ZOMBIES)
	z.pos = e[5] if e[5] is Vector3 else Vector3.ZERO
	z.yaw = float(e[6])
	var fl: int = e[8] if e[8] is int else 0
	var entryId := str(e[7])
	if fl & 1:
		z.state = "chase"
		z.area = g.level.areaAt(z.pos.x, z.pos.z)
		z.spawnT = 0.25
		if not (fl & 2):
			M._burst(z.pos + Vector3(0, 0.8, 0), {"shape": "static", "count": 12, "speed": 1.8, "size": 0.09, "life": 0.6})
	elif fl & 4:
		var ss = g.level.screenSpawns.get(entryId)
		if ss != null:
			M._beginScreen(z, ss)
		else:
			z.state = "chase"
	else:
		var w = g.level.windows.get(entryId)
		if w != null:
			_puppetEntry(z, w)
		else:
			z.state = "chase"
	_initPuppet(z, t)
	M._addToWorld(z)

func _initPuppet(z: Dictionary, t: float) -> void:
	var R := Ring.new()
	z["_ring"] = R
	z["hpPred"] = z.hp
	z["_reqT"] = -10.0
	z["_seen"] = _now()
	z["tgtId"] = 0
	z["_pst"] = stateCode(z)
	z["_pat"] = 0.0
	z["_pyaw"] = z.yaw
	z["_ppos"] = z.pos
	R.put(t, z.pos, z.yaw, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.26, 0.0, z.hp / maxf(1.0, z.maxHp), z._pst, 0, 1, 0)

# The entry record of a window / fence / gate (zombies._beginEntry without the scatter: the host sent the pos).
func _puppetEntry(z: Dictionary, win) -> void:
	var outV = M._f(win, "outsidePos")
	var out: Vector3 = outV if outV is Vector3 else DAU.v3(win.outside)
	var ins = win.inside
	var ox: float = out.x - float(ins[0])
	var oz: float = out.z - float(ins[2])
	var ol: float = M._hypot(ox, oz)
	if ol == 0.0:
		ol = 1.0
	z.state = "approach"
	z.area = null
	var wt = M._f(win, "type")
	z.entry = {"kind": "fence" if wt == "fence" else ("gate" if wt == "gate" else "window"), "id": M._f(win, "id"), "win": win,
		"t": 0.0, "out": Vector3(out.x, 0, out.z), "inw": Vector3(-ox / ol, 0, -oz / ol), "slot": -1, "style": null,
		"tearT": 0.0, "inP": null, "popped": false}
	var fo: float = M._floorAt(out.x, out.z, 2.0)
	z.entry.out.y = fo if fo > -INF else 0.0

func _reenter(z: Dictionary, entryId: String, pos: Vector3, yaw: float, screen: bool, t: float) -> void:
	var g = game
	z.pos = pos
	z.yaw = yaw
	z.vel = Vector3.ZERO
	if screen:
		var ss = g.level.screenSpawns.get(entryId)
		if ss != null:
			M._beginScreen(z, ss)
	else:
		var w = g.level.windows.get(entryId)
		if w != null:
			_puppetEntry(z, w)
	z.pos = pos
	var R = z.get("_ring")
	if R != null:
		R.clear()
		z["_pst"] = stateCode(z)
		R.put(t, pos, yaw, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.26, 0.0, z.hp / maxf(1.0, z.maxHp), z._pst, 0, 1, int(z.get("tgtId", 0)))
	M._place(z)

func _applyHit(e: Array) -> void:
	var z = M._byId.get(e[1])
	if z == null or z.dead or z.removed:
		return
	var by = e[10] if (e[10] is int and e[10] >= 0) else null
	var hp := float(e[3])
	z.hp = hp
	z["hpPred"] = minf(float(z.get("hpPred", hp)), hp) if _now() - float(z.get("_reqT", -10.0)) < 0.4 else hp
	var fl: int = e[4] if e[4] is int else 0
	var head := (fl & 1) != 0
	var killed := (fl & 2) != 0
	var dmg := float(e[2])
	var point = e[6]
	var dir = e[7]
	if by != null and by == net.localId:
		return                          # our own prediction already showed it
	var frame: int = game.time.frame
	if not killed:
		z.anim.hurt = 1.0
		M._kick(z, minf(1.2, 0.45 + dmg / maxf(60.0, z.maxHp) * 1.5))
	_hitFx(z, point, dir, frame)
	if not killed and M._hitSfx < 2:
		M._hitSfx += 1
		M._play("zmb_hit", {"pos": point if point is Vector3 else z.pos, "rate": 0.9 + randf() * 0.25})
	game.events.emit("zombie:hit", {"z": z, "dmg": dmg, "head": head, "weaponId": e[9] if str(e[9]) != "" else null,
		"point": point if point is Vector3 else z.pos, "zone": e[5], "cause": e[8], "upgraded": (fl & 4) != 0, "by": by})

func _applyKill(e: Array) -> void:
	var z = M._byId.get(e[1])
	var R = game.rounds
	var by = e[7] if (e[7] is int and e[7] >= 0) else null
	if R != null:
		R.totalKills = int(e[10])
		if z != null and z.get("fromRound") == R.token:
			R.killsThisRound = int(e[11])
		if by != null and R.get("killsBy") is Dictionary:
			R.killsBy[by] = int(e[12])
	if z == null or z.dead or z.removed:
		return
	var info := {"cause": e[3], "head": e[2] == true, "weaponId": e[4] if str(e[4]) != "" else null, "by": by}
	if e[5] is Vector3:
		info.dir = e[5]
	if e[6] == false:
		info.corpse = false
	var wfx = e[9]
	if wfx != null:
		info.wfx = wfx
		var W = game.get("wonder")
		if W != null and W.has_method("corpseFx"):
			W.corpseFx(z, wfx, by)
	if e[8] is Vector3 and (e[8] as Vector3).distance_to(z.pos) > 1.5:
		z.pos = e[8]
	M._kill(z, info, false)

# --- snapshots
func onSnapshot(data: PackedByteArray) -> void:
	if data.size() < 13 or data.decode_u8(0) != 1:
		return
	var seq := data.decode_u16(2)
	if _lastSeq >= 0 and ((seq - _lastSeq) & 0xFFFF) >= 0x8000:
		return
	_lastSeq = seq
	var ht := data.decode_double(4)
	var now := _now()
	var d := now - ht
	if not _hasOff or d < _off or absf(d - _off) > 5.0:
		_off = d
		_hasOff = true
	else:
		_off += (d - _off) * 0.01
	var n := data.decode_u8(1)
	var nT := mini(data.decode_u8(12), 8)
	var o := 13
	for i in nT:
		_tin[i] = data.decode_s32(o)
		o += 4
	var sz := data.size()
	for k in n:
		if o + 20 > sz:
			break
		var id := data.decode_u32(o)
		var sm := data.decode_u8(o + 4)
		var fl := data.decode_u8(o + 5)
		var p := Vector3(data.decode_s16(o + 6) / 100.0, data.decode_s16(o + 8) / 100.0, data.decode_s16(o + 10) / 100.0)
		var yaw := data.decode_u16(o + 12) / 65536.0 * TAU
		var speed := data.decode_u8(o + 14) / 20.0
		var attack := data.decode_u8(o + 15) / 255.0
		var climb := data.decode_u8(o + 16) / 200.0
		var ti := data.decode_u8(o + 17)
		var hpf := data.decode_u16(o + 18) / 65535.0
		o += 20
		var pitch := 0.0
		var sx := 1.0
		var sy := 1.0
		var szz := 1.0
		if fl & 64:
			if o + 4 > sz:
				break
			pitch = data.decode_s8(o) / 40.0
			sx = data.decode_u8(o + 1) / 100.0
			sy = data.decode_u8(o + 2) / 100.0
			szz = data.decode_u8(o + 3) / 100.0
			o += 4
		var ex0 := -1
		var len := 0
		if fl & 128:
			if o + 1 > sz:
				break
			len = data.decode_u8(o)
			ex0 = o + 1
			o += 1 + len
			if o > sz:
				break
		var z = M._byId.get(id)
		if z == null or z.dead or z.removed or z.get("_ring") == null:
			continue
		var ph := 0.0
		var hh := 0.26
		var leg := 0.0
		if ex0 >= 0:
			if z.type == "sock_hopper" and len >= 2:
				ph = data.decode_u8(ex0) / 256.0
				hh = data.decode_u8(ex0 + 1) / 500.0
			elif z.type == "forecaster" and len >= 1:
				leg = data.decode_s8(ex0) / 100.0
		var tgt: int = _tin[ti] if ti < nT else 0
		z._seen = now
		z._ring.put(ht, p, yaw, speed, attack, climb, pitch, sx, sy, szz, ph, hh, leg, hpf, sm & 15, sm >> 4, fl, tgt)

# Sets _i0 / _i1 / _k / _ex for render time rt.
func _find(R, rt: float) -> void:
	_i0 = -1
	_i1 = -1
	_k = 0.0
	_ex = 0.0
	if R.n == 0:
		return
	var newest: int = (R.head - 1 + RN) % RN
	if rt >= R.t[newest]:
		_i0 = newest
		_ex = clampf(rt - R.t[newest], 0.0, EXTRAP)
		return
	for j in range(1, R.n):
		var s: int = (R.head - 1 - j + RN * 2) % RN
		if R.t[s] <= rt:
			_i0 = s
			_i1 = (s + 1) % RN
			var span: float = R.t[_i1] - R.t[s]
			_k = clampf((rt - R.t[s]) / span, 0.0, 1.0) if span > 1e-5 else 1.0
			return
	_i0 = (R.head - R.n + RN) % RN

func clientTick(dt: float) -> void:
	var now := _now()
	var rt := _renderT(now)
	_runTimeline(rt, now)
	_areaT -= dt
	var areaNow := _areaT <= 0.0
	if areaNow:
		_areaT = 0.5
	var list: Array = M.alive
	for i in range(list.size() - 1, -1, -1):
		if i >= list.size():
			continue
		var z: Dictionary = list[i]
		if z.dead or z.removed:
			continue
		if now - float(z.get("_seen", now)) > LOST and _hasOff:
			_warnOnce("lost", "[zombies] a puppet stopped receiving snapshots: removed")
			applying = true
			M.despawn(z, false)
			applying = false
			continue
		if M.frozen:
			continue
		if z.get("puppetHold") != true:
			_puppet(z, dt, rt, areaNow)
		M._animate(z, dt)
	_blockLocal()

func _puppet(z: Dictionary, dt: float, rt: float, areaNow: bool) -> void:
	var R = z.get("_ring")
	if R == null:
		return
	_find(R, rt)
	if _i0 < 0:
		return
	var a := _i0
	var b := _i1 if _i1 >= 0 else a
	var k := _k
	var p0: Vector3 = R.pos[a]
	var np: Vector3
	if _i1 >= 0:
		np = p0.lerp(R.pos[b], k)
	elif _ex > 0.0 and R.n >= 2:
		var pa: int = (a - 1 + RN) % RN
		var dtv: float = R.t[a] - R.t[pa]
		if dtv > 1e-4 and dtv < 0.5:
			var v: Vector3 = (p0 - R.pos[pa]) / dtv
			np = Vector3(p0.x + v.x * _ex, p0.y, p0.z + v.z * _ex)
		else:
			np = p0
	else:
		np = p0
	var fa: int = a * NF
	var fb: int = b * NF
	var y0: float = R.f[fa]
	var nyaw: float = y0 + M.angDiff(R.f[fb], y0) * k
	# derived velocity / turn rate (Big Shot casters, roll sound, the animator's turn lean)
	if dt > 0.0:
		var pv: Vector3 = z.get("_ppos", np)
		var v2: Vector3 = (np - pv) / dt
		v2.y = 0.0
		z.vel = z.vel.lerp(v2, minf(1.0, dt * 10.0))
		z.anim.turn = M.angDiff(nyaw, float(z.get("_pyaw", nyaw))) / dt
	z["_ppos"] = np
	z["_pyaw"] = nyaw
	z.pos = np
	z.yaw = nyaw
	var an: Dictionary = z.anim
	an.speed = lerpf(R.f[fa + 1], R.f[fb + 1], k)
	var att: float = lerpf(R.f[fa + 2], R.f[fb + 2], k)
	an.climb = lerpf(R.f[fa + 3], R.f[fb + 3], k)
	var pitch: float = lerpf(R.f[fa + 4], R.f[fb + 4], k)
	var sx: float = lerpf(R.f[fa + 5], R.f[fb + 5], k)
	var sy: float = lerpf(R.f[fa + 6], R.f[fb + 6], k)
	var sz: float = lerpf(R.f[fa + 7], R.f[fb + 7], k)
	var qa: int = a * NI
	var state: int = R.i[qa]
	var mode: int = R.i[qa + 1]
	var fl: int = R.i[qa + 2]
	z["tgtId"] = R.i[qa + 3]
	# hp: the newest sample
	var newest: int = (R.head - 1 + RN) % RN
	var hp: float = R.f[newest * NF + 11] * z.maxHp
	z.hp = hp
	if _now() - float(z.get("_reqT", -10.0)) >= 0.4:
		z["hpPred"] = hp
	else:
		z["hpPred"] = minf(float(z.get("hpPred", hp)), hp)
	z.lured = (fl & 2) != 0
	an.down = (fl & 4) != 0
	if (fl & 8) != 0:
		z.stun = maxf(z.stun, 0.05)
	# discrete state changes -> the host's one-shot cues
	var pst := int(z.get("_pst", state))
	if state != pst:
		_stateFx(z, pst, state)
		z["_pst"] = state
	z.state = STATES[clampi(state, 0, 8)]
	if state >= 4 and state <= 6 and z.entry is Dictionary:
		z.entry.phase = PHASES[state]
	# cues inside a state (anim.attack crossings)
	var pat := float(z.get("_pat", 0.0))
	if state == 2 and pat < 0.55 and att >= 0.55:
		M._kick(z, 0.5)
		if randf() < 0.35:
			M._play("zmb_groan", {"pos": z.pos, "rate": 1.1})
	elif state == 8 and pat < 0.4 and att >= 0.4:
		M._play("zmb_swipe", {"pos": z.pos})
	z["_pat"] = att
	an.attack = att
	# local timers
	an.hurt = maxf(0.0, float(an.get("hurt", 0.0)) - dt / 0.25)
	if z.spawnT > 0.0:
		z.spawnT = maxf(0.0, z.spawnT - dt)
	if z.gawkT > 0.0:
		z.gawkT = maxf(0.0, z.gawkT - dt)
	if z.stun > 0.0:
		z.stun = maxf(0.0, z.stun - dt)
	if areaNow and state >= 7:
		var ar = game.level.areaAt(z.pos.x, z.pos.z)
		if ar:
			z.area = ar
	# type state + flavour
	var def: Dictionary = z.def
	var nm = def.get("netModes")
	if nm is Array and mode < nm.size():
		z.flags.mode = nm[mode]
	if z.type == "sock_hopper":
		var f: Dictionary = z.flags
		var bb: int = b * NF
		var ph0: float = R.f[fa + 8]
		var dph: float = fposmod(R.f[bb + 8] - ph0 + 0.5, 1.0) - 0.5
		f["netPh"] = fposmod(ph0 + dph * k, 1.0)
		f["netH"] = R.f[fa + 9]
		f["netBit"] = (fl & 32) != 0
	elif z.type == "forecaster":
		an.legYaw = lerpf(R.f[fa + 10], R.f[fb + 10], k)
		an.back = (fl & 16) != 0
	if state <= 6:
		if def.get("updateEntry") is Callable:
			def.updateEntry.call(game, z, dt)
	elif def.get("puppet") is Callable:
		def.puppet.call(game, z, dt)
	M._place(z, pitch, sx, sy, sz)

# Host cues replayed at the state changes of the interpolated stream.
func _stateFx(z: Dictionary, from: int, to: int) -> void:
	var e = z.get("entry")
	if to == 3 and from <= 2:
		var st = null
		if e is Dictionary and z.def.get("entry") is Callable:
			st = z.def.entry.call(game, z, e.win)
			e.style = st if st is Dictionary else null
		if not (st is Dictionary and st.get("style") == "blast"):
			M._play("window_vault", {"pos": z.pos})
	if from == 3 and to >= 7:
		var kind = e.get("kind") if e is Dictionary else null
		var st2 = e.get("style") if e is Dictionary else null
		var sname = st2.get("style") if st2 is Dictionary else null
		if kind == "gate" or sname == "squeeze" or sname == "toothpaste" or sname == "blast":
			M._kick(z, 1.2)
		M._kick(z, 1.0)
		M._burst(z.pos + Vector3(0, 0.05, 0), {"shape": "puff", "count": 4, "size": 0.16, "speed": 1.2, "colors": ["#E8DCC8", "#CDBFA8"]})
		if e is Dictionary and e.get("win") != null:
			z.area = M._f(e.win, "area")
		z.anim.climb = 0.0
		z.entry = null
		return
	if from == 4 and to != 4:
		if z.group != null:
			z.group.visible = true
		if e is Dictionary:
			e.tele = null
		if to == 5 and e is Dictionary and e.get("ss") != null:
			M._play("screen_emerge", {"pos": e.ss.pos})
	if to == 6 and e is Dictionary:
		e.inGlass = false
	if from >= 4 and from <= 6 and to >= 7:
		M._kick(z, 1.2)
		M._burst(z.pos + Vector3(0, 0.05, 0), {"shape": "static", "count": 10, "speed": 1.6})
		z.entry = null
		var ar = game.level.areaAt(z.pos.x, z.pos.z)
		if ar:
			z.area = ar

# The player half of zombies._blockPlayer: the local player is pushed out of the puppets' bodies.
func _blockLocal() -> void:
	var p = game.player
	if p == null or not p.alive or p.get("downed") == true or p.get("offAir") == true:
		return
	var prad := float(M._f(p, "radius", 0.38))
	var px := 0.0
	var pz := 0.0
	for z in M.alive:
		if z.state != "chase" and z.state != "attack":
			continue
		if absf(p.pos.y - z.pos.y) > 1.2:
			continue
		var dx: float = p.pos.x - z.pos.x
		var dz: float = p.pos.z - z.pos.z
		var rr: float = prad + z.radius * 0.9
		var d2 := dx * dx + dz * dz
		if d2 >= rr * rr:
			continue
		var d := sqrt(d2)
		if d == 0.0:
			d = 1e-3
		var o := rr - d
		px += (dx / d) * o * 0.6
		pz += (dz / d) * o * 0.6
	if px != 0.0 or pz != 0.0:
		M._moveCircle(p, Vector3(px, 0, pz), prad, float(M._f(p, "height", 1.75)), 0.45)
