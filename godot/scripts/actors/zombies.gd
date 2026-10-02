# ZombieManager (ARCHITECTURE §10, GDD §5.9–5.10, §7.4, §8 common, §8.1). Port of src/actors/zombies.js.
#
# API (game.zombies)
#   alive                     living zombies (every state but dying): Dictionaries { id, type, def, pos, vel, yaw, hp,
#                             maxHp, state, area, group, rig, animator, radius, height, speed, flags, head, headR,
#                             hitZones, anim, stun, fromRound, entry }. state: 'approach' | 'queue' | 'tear' | 'vault' |
#                             'screen' | 'chase' | 'attack'  (then 'dying' once killed; z.dead = true).
#   dying                     zombies playing their death (not targetable).
#   maxAlive                  spawn cap (T.rounds.maxAlive; Rounds lowers it to 10 in Hullabaloo Hour).
#   spawn(typeId, entryId|null, pos|null, opts?) -> z | null (null at the cap). entryId = a window/fence/gate id
#                             (level.windows) or a screen spawn id 'ss_*'; both null = pick a spawner per GDD §5.9
#                             (active areas, 8 m rule, first spawn of a game through B3). opts: { hp, speed, fromRound,
#                             silent (no static pop-in burst for pos spawns), variant (Tuned-In art id, e.g. 'z_mom': that
#                             look instead of a random one) }. A pos is snapped to the nav floor (nearest cell within 3 m).
#   damage(z, amount, info) -> killed:bool   info = { head, zone, weaponId, point, dir, knockback (m of shove),
#                             cause ('bullet'|'melee'|'grenade'|'wonder'|'tele'|...), points (false = no points),
#                             hitmarker (false = no hud.hitmarker), upgraded, corpse (false = the caller animates a clone
#                             of the body, e.g. wonder weapons: no death visuals here, removed next frame) }.
#                             Applies the zone multiplier (limb ×0.8;
#                             pass the raycast's zone, do not pre-multiply), ×2 while in a screen's glass, the type's
#                             onDamage, ONE TAKE (one hit, Big Shot ×5). Awards ALL zombie points (GDD §6.3): +10 per
#                             damaging hit (deduped per zombie per frame + weapon: a shotgun volley / ghost bullet
#                             counts once), kills 50 / head 100 / melee 130 / grenade-wonder-tele 50, + type kill bonus.
#                             Hit reaction (squash, head-spring, 0.15 s stagger), confetti + felt fluff, zmb_hit.
#   kill(z, info)             kill now (same points rules; cause 'cancelled' / 'debug' / 'boss' / 'script' give none).
#   raycast(origin, dir, maxDist) -> { z, head, dist, point, zone } | null   head sphere, torso + limb capsules
#                             (or the type's hitZones / hitTest). Screen telegraph: a sphere on the screen itself.
#   inRadius(pos, r, out=[]) -> out   (distance to the zombie's feet-to-head segment)
#   killAll(cause='cancelled') stunAll(seconds)  stun(z, s)  freezeAll(bool)  setLure(pos|null)  knockback(z, vec)
#   despawn(z, requeue=true)  despawnAll({fx})  nearest(pos, maxDist) -> z|null  count(typeId?)  roundAlive(token)
# Events: zombie:spawn {z}, zombie:hit {z, dmg, head, weaponId, point, zone, cause}, zombie:kill {z, weaponId, head,
#   melee, pos, cause}, zombie:attack {z, dmg}, zombie:despawn {z}, zombie:telegraph {z, screenId, seconds}.
# Behaviour: window entry (walk to the outside point, queue, tear 1 board / 1.2 s, vault 1.2 s; fence climb 1.5 s;
#   gate squeeze 0.8 s; screen telegraph 1.2 s via screens.telegraph + taffy emerge 1.0 s, ×2 damage in the glass),
#   flow field (nav.dir) + boid separation 0.6 m + direct chase with line of sight when close, the Tuned-In swipe
#   (0.4 s wind-up, player.hurt, 1.2 s cooldown), zombies block the player, anti-stuck (8 s neither closer on the
#   path nor walking -> silent despawn + requeue), straggler rule (last zombie > 40 m of path for 20 s -> re-enters
#   near you), lure (Tiny Tele: gather and kneel, mesmerized), stun stars, PLEASE STAND BY freeze look, ONE TAKE star
#   eyes, the Sign-On gawk (stop and look at the nearest TV for 1.5 s), death = topple back with a bounce + circling
#   stars, then 30 static quads + 12 colour-bar confetti + a fluttering ticket stub; headshot kill = the head pops off
#   like a cork (30 ms hit-stop), bounces twice and vanishes in static.
# LOD: far/off-screen zombies animate every 3rd frame, body shadows (8 nearest on screen; the rest keep their blob),
#   ticket/patch cards (< 7 m) and the eye veil + rim (< 13 m). Every mesh is on LAYERS.ZOMBIES. The stun stars and
#   the ticket stubs are two MultiMesh pools.
#
# MP (online co-op, RECONCILE R16/R17; the work lives in scripts/actors/zombies_net.gd, built by reset() only while
#   game.net.inGame — solo never creates it and runs the code above unchanged):
#   HOST simulates as solo plus: every zombie chases z.tgt (nearest targetable player by path: nav.goalIdAt, 0.4 s
#   retarget hysteresis); spawners use every present player (areas union, 8 m from all); contact hits on a remote
#   player -> zombies.net_hurt(dmg, from, kb, zid, kind) to its peer; damage(info.by) awards via
#   economy.add(n, reason, by) (the +10 dedupe key is by|shot|weapon); zombie:hit / zombie:kill payloads carry `by`
#   (kill also `wfx`); every spawn / hit / kill / despawn / stun / lure / freeze / straggler re-entry / type event /
#   gawk goes into one reliable zombies.net_ev(t, list) per client per frame; stream 'z' = 20 Hz packed snapshot.
#   CLIENT builds puppets from those messages (same def.build, host variant + scale), interpolates 100 ms behind,
#   replays the host's cues from state / mode changes (types: puppet(game, z, dt), puppetEvent(game, z, kind, args)).
#   damage() on a client = predicted local feedback + an entry of the per-frame zombies.net_dmgBatch(list); kill /
#   killAll / spawn / despawn* are host-only (no-ops); stun / knockback / setLure become stunReq / knockReq /
#   lureReq requests; freezeAll only sets the local look. hitStop on a head pop only for the local killer.
#   API: byId(id), targetOf(z), targetsList(), isRemote(p), authority(), isPuppet(), hurtTarget(p, dmg, z, kb, kind),
#   netEvent(z, kind, args). Handlers: net_ev, net_stream_z, net_dmgBatch, net_hurt, net_stunReq, net_knockReq,
#   net_lureReq.
#
# Port notes (GDScript):
#   * z records, entries, queues, popped heads and star rings are Dictionaries (JS object literals). Every field the
#     JS adds lazily is declared at spawn so dot reads work.
#   * collision.gd moveCircle(pos, delta, radius, height, stepUp, ignore, owner) cannot mutate a Vector3: it returns
#     the result Dictionary with the moved feet in "pos" and _moveCircle() stores it back into the owner (z or the
#     player; the owner also carries collision's per-body "grounded" memory, the JS WeakMap keyed by the pos object).
#     nav.dir(x, z) returns the direction (JS filled an `out` vector); nav.localField() is an object (dist / dir).
#   * Without game.scene (render not loaded) the models are parented to the game node.
#   * JS truthiness of objects: info.dir / info.point are tested against null (a Vector3.ZERO is falsy in GDScript).
#   * try/catch around type hooks is gone (a GDScript runtime error aborts only the failing hook); a type build that
#     fails (no z.group) falls back to a Tuned-In spawn like the JS catch.
#   * Not ported (SPEC §0.2 plumbing): warmup() (Game.precompile), crowdInfo() / crowd batches, charOpt A/B flags.
#   * boss.gd's wonder adapter: the JS boss replaced zombies.damage / raycast on the instance during the fight; here
#     boss.gd sets _damageHook (z, amount, info) -> null | result and _raycastHook (o, d, max, ownHit) -> hit.
#   * Node names: 'zombie:poppedHead' / 'zombie:stars' / 'zombie:tickets' use '_' (':' is invalid in Godot names).
#   * Static geometry / canvases: the stun star, the ticket stub quad + its canvas and the ONE TAKE / feed eye
#     textures are Blender runtime assets (blender/runtime/zombies.py -> res://assets/runtime/zombies/).
extends RefCounted

const TURN := 7.0               # rad/s-ish yaw easing
const ACCEL := 7.0              # 1/s velocity easing
const SEP_R := 0.6              # GDD §5.10 boid separation radius
const LOS_NEAR := 7.5           # direct chase within this distance when the path is straight and visible
const GRAVITY := 22.0
const STUCK_TIME := 8
const STRAGGLER_DIST := 40.0
const STRAGGLER_TIME := 20
const RULE_8M := 8.0
const DIE_TOPPLE := 0.55
const DIE_LIE := 1.0
const DIE_POP := 0.14
const STAGGER := 0.15
const SHADOW_MAX := 8
const CARD_LOD := 7.0            # ticket stub / patch cards drawn within this camera distance
const DETAIL_LOD := 13.0         # eye veil + rim drawn within this distance (the static eye discs always)
const ANIM_NEAR := 24.0
const GAWK := 1.5
const LEVER := Vector3(34, 1, -7)
const STAR_ASSET := "res://assets/runtime/zombies/star.glb"
const TICKET_ASSET := "res://assets/runtime/zombies/ticket.glb"

const NO_POINTS := ["cancelled", "debug", "despawn", "boss", "script", "egg"]
const SPECIAL_CAUSES := ["grenade", "explosion", "wonder", "zapper", "boom_mic", "chroma_key", "tele", "tiny_tele", "gag"]
const SPECIAL_WEAPONS := ["zapper", "boom_mic", "chroma_key", "tiny_tele", "tube_grenade"]

static func _Z() -> Dictionary:
	return Config.T.zombies

static func _P() -> Dictionary:
	return Config.T.points

static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func smooth(x: float) -> float:
	x = clamp01(x)
	return x * x * (3.0 - 2.0 * x)

static func easeOutCubic(x: float) -> float:
	return 1.0 - pow(1.0 - clamp01(x), 3.0)

static func easeOutBack(x: float) -> float:
	x = clamp01(x)
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

static func angDiff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func yawTo(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

static func _hypot(x: float, z: float) -> float:
	return sqrt(x * x + z * z)

# Ray (o, d normalized) vs sphere (c, r) -> distance or INF.
static func raySphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var q := oc.length_squared() - r * r
	var disc := b * b - q
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	return t if t >= 0.0 else (0.0 if q < 0.0 else INF)

# Ray vs capsule (segment a..b, radius r) -> distance or INF (after Inigo Quilez).
static func rayCapsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ba := b - a
	var oa := o - a
	var baba := ba.length_squared()
	var bard := ba.dot(d)
	var baoa := ba.dot(oa)
	var rdoa := d.dot(oa)
	var oaoa := oa.length_squared()
	var qa := baba - bard * bard
	var qb := baba * rdoa - baoa * bard
	var qc := baba * oaoa - baoa * baoa - r * r * baba
	if qa < 1e-9:
		return raySphere(o, d, a, r)
	var h := qb * qb - qa * qc
	if h < 0.0:
		return INF
	var t := (-qb - sqrt(h)) / qa
	var y := baoa + t * bard
	if y > 0.0 and y < baba:
		return t if t >= 0.0 else (0.0 if qc < 0.0 else INF)
	return raySphere(o, d, a if y <= 0.0 else b, r)

static func killPoints(cause, head: bool, weaponId) -> int:
	var P := _P()
	if NO_POINTS.has(cause):
		return 0
	if cause == "melee" or weaponId == "melee":
		return int(P.melee)
	if SPECIAL_CAUSES.has(cause) or SPECIAL_WEAPONS.has(weaponId):
		return int(P.special)
	return int(P.head) if head else int(P.kill)

# JS `o.k` on a Dictionary or an Object (d when missing / null).
static func _f(o, k: String, d = null):
	if o is Dictionary:
		return o.get(k, d)
	if o is Object:
		var v = o.get(k)
		return d if v == null else v
	return d

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

# Index of a record by identity (Dictionary == compares content in GDScript).
static func _idx(arr: Array, o) -> int:
	for i in arr.size():
		if is_same(arr[i], o):
			return i
	return -1

# Calls a JS-style handle method: an Object method, or a Callable stored in a Dictionary.
static func _hcall(h, m: String, args: Array = []):
	if h is Object and h.has_method(m):
		return h.callv(m, args)
	if h is Dictionary and h.get(m) is Callable and h[m].is_valid():
		return h[m].callv(args)
	return null

# object.matrixWorld whether or not the node is inside the tree.
static func _world(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.global_transform
	var t := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

static func _worldPos(n: Node3D) -> Vector3:
	return _world(n).origin

static func _quatXYZ(v: Vector3) -> Quaternion:
	return Basis.from_euler(v, EULER_ORDER_XYZ).get_rotation_quaternion()

# ------------------------------------------------------------------------------------------------ FX pools
# The stun-star mesh: Blender runtime asset (extruded 5-point star, bevelled, centred). Minimal flat prism when
# the asset has not been built yet.
static func starMesh() -> Mesh:
	var m := _glbMesh(STAR_ASSET)
	if m != null:
		return m
	push_warning("[zombies] %s missing (run blender/build_all.py --only runtime): flat star fallback" % STAR_ASSET)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for i in 10:
		var a := PI / 2.0 + (i * PI) / 5.0
		var r := 0.024 if i % 2 else 0.058
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	for zf in [0.008, -0.008]:
		for i in 10:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % 10]
			var tri := [Vector3(0, 0, zf), Vector3(p0.x, p0.y, zf), Vector3(p1.x, p1.y, zf)]
			if zf < 0.0:
				tri = [tri[0], tri[2], tri[1]]
			st.set_normal(Vector3(0, 0, signf(zf)))
			for v in tri:
				st.add_vertex(v)
	for i in 10:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % 10]
		var n := Vector3(p1.y - p0.y, p0.x - p1.x, 0).normalized()
		st.set_normal(n)
		for v in [Vector3(p0.x, p0.y, 0.008), Vector3(p0.x, p0.y, -0.008), Vector3(p1.x, p1.y, -0.008),
				Vector3(p0.x, p0.y, 0.008), Vector3(p1.x, p1.y, -0.008), Vector3(p1.x, p1.y, 0.008)]:
			st.add_vertex(v)
	return st.commit()

# The ticket stub canvas ('13 / ADMIT ONE', 256 x 140) and its PlaneGeometry(0.1, 0.055) quad are Blender runtime
# assets (blender/runtime/zombies.py: ticket.png, ticket.glb).
static func ticketTexture():
	return ZombieTypes._runtimeTex("ticket.png")

# First mesh of a runtime GLB (null when the asset has not been built).
static func _glbMesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var inst: Node = ps.instantiate()
	var found: Array = []
	DAU.traverse(inst, func(o): if o is MeshInstance3D and found.is_empty(): found.append(o.mesh))
	inst.free()
	return found[0] if not found.is_empty() else null

static func _poolMesh(scene: Node, mesh: Mesh, mat: Material, cap: int, name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))     # frustumCulled = false
	mi.visible = false
	mi.layers = 1 << Config.LAYERS.ZOMBIES
	scene.add_child(mi)
	return mi

class StarRings extends RefCounted:
	var mesh: MultiMeshInstance3D
	var rings: Array = []
	var S                       # the manager script (its static helpers)

	func _init(scene: Node) -> void:
		S = load("res://scripts/actors/zombies.gd")
		var col: Color = Color(Config.PAL.marqueeGold).srgb_to_linear() * 1.8
		var mat := ZombieTypes.basicMaterial(Color(col.r, col.g, col.b), null, "front", "zombieStars")
		mesh = S._poolMesh(scene, S.starMesh(), mat, 96, "zombie_stars")

	# z: the zombie (its head position) ; life seconds ; n stars
	func add(z: Dictionary, life: float, n := 3, r := 0.26) -> Dictionary:
		for ring in rings:
			if is_same(ring.z, z):
				ring.life = maxf(ring.life, life)
				ring.t = minf(ring.t, 0.2)
				return ring
		var ring := {"z": z, "t": 0.0, "life": life, "n": n, "r": r, "phase": randf() * 6.0}
		rings.append(ring)
		return ring

	func remove(z: Dictionary) -> void:
		rings = rings.filter(func(r): return not is_same(r.z, z))

	func clear() -> void:
		rings.clear()

	func update(dt: float) -> void:
		var k := 0
		var mm := mesh.multimesh
		for i in range(rings.size() - 1, -1, -1):
			var ring: Dictionary = rings[i]
			ring.t += dt
			var z: Dictionary = ring.z
			var grp = z.get("group")
			if ring.t >= ring.life or z.get("head") == null or (z.dead and (grp == null or grp.get_parent() == null)):
				rings.remove_at(i)
				continue
			var a: Vector3 = S._worldPos(z.head)
			a.y += (z.headR if z.headR else 0.25) * 0.95
			var grow: float = S.easeOutBack(ring.t / 0.25) * (1.0 - S.smooth((ring.t - ring.life + 0.25) / 0.25))
			for s in ring.n:
				if k >= 96:
					break
				var ang: float = ring.phase + ring.t * 5.5 + (s * PI * 2.0) / ring.n
				var b := Vector3(a.x + cos(ang) * ring.r, a.y + sin(ang * 2.0) * 0.04, a.z + sin(ang) * ring.r)
				var q: Quaternion = S._quatXYZ(Vector3(0, -ang + ring.t * 3.0, 0))
				var sc := maxf(0.001, grow)
				mm.set_instance_transform(k, Transform3D(Basis(q).scaled(Vector3(sc, sc, sc)), b))
				k += 1
		mm.visible_instance_count = k
		mesh.visible = k > 0

class Tickets extends RefCounted:
	var mesh: MultiMeshInstance3D
	var list: Array = []
	var S                       # the manager script (its static helpers)

	func _init(scene: Node) -> void:
		S = load("res://scripts/actors/zombies.gd")
		var quad: Mesh = S._glbMesh(S.TICKET_ASSET)
		var threeUV := quad != null
		if quad == null:           # asset not built yet: the same plane as an engine quad (Godot UVs, no flip)
			quad = QuadMesh.new()
			quad.size = Vector2(0.1, 0.055)
		var mat := ZombieTypes.basicMaterial(Color(0.9, 0.9, 0.9), S.ticketTexture(), "double", "zombieTicket", threeUV)
		mesh = S._poolMesh(scene, quad, mat, 24, "zombie_tickets")

	func add(pos: Vector3, floorY: float) -> void:
		if list.size() >= 24:
			list.pop_front()
		list.append({"p": pos, "floor": floorY + 0.01, "t": 0.0, "seed": randf() * 10.0, "vx": (randf() - 0.5) * 0.8,
			"vz": (randf() - 0.5) * 0.8, "landed": false})

	func clear() -> void:
		list.clear()

	func update(dt: float) -> void:
		var k := 0
		var mm := mesh.multimesh
		for i in range(list.size() - 1, -1, -1):
			var t: Dictionary = list[i]
			t.t += dt
			if t.t > 4.5:
				list.remove_at(i)
				continue
			if not t.landed:
				t.p.y -= dt * (0.55 + 0.25 * sin(t.t * 7.0 + t.seed))
				t.p.x += (t.vx + sin(t.t * 4.2 + t.seed) * 0.9) * dt
				t.p.z += (t.vz + cos(t.t * 3.7 + t.seed) * 0.9) * dt
				if t.p.y <= t.floor:
					t.p.y = t.floor
					t.landed = true
			var rx: float = -PI / 2.0 if t.landed else sin(t.t * 6.0 + t.seed) * 0.9
			var rz: float = 0.0 if t.landed else cos(t.t * 5.0 + t.seed) * 0.6
			var q: Quaternion = S._quatXYZ(Vector3(rx, t.seed + t.t * (0.0 if t.landed else 2.0), rz))
			var s := maxf(0.001, 1.0 - S.smooth((t.t - 4.0) / 0.5))
			mm.set_instance_transform(k, Transform3D(Basis(q).scaled(Vector3(s, s, s)), t.p))
			k += 1
		mm.visible_instance_count = k
		mesh.visible = k > 0

# ------------------------------------------------------------------------------------------------ manager
var game
var alive: Array = []
var dying: Array = []
var frozen := false
var lure = null                  # Vector3 | null
var lureR := INF
var maxAlive: int = int(Config.T.rounds.maxAlive)
var _uid := 0
var _firstSpawn := true
var _entries := {}               # entry id -> { front, waiting[] }
var _heads := {}                 # variant -> [popped-head proxies]
var _flying: Array = []          # active popped heads
var _stars: StarRings = null
var _tickets: Tickets = null
var _oneTake := false
var _standby := false
var _hitSfx := 0
var _frame := 0
var _camPos := Vector3.ZERO
var _order: Array = []
var _lureField = null
var _lastArea = null
# Boss fight adapters (boss.gd installs them; the JS replaced damage / raycast on the instance): see damage() / raycast().
var _damageHook := Callable()
var _raycastHook := Callable()
# MP (see the MP paragraph in the header): game.net, the companion (null in solo) and the id map.
var net = null
var _zn = null
var _byId := {}
var _despawnFx := false

func _init(g) -> void:
	game = g

func init() -> void:
	var g = game
	_stars = StarRings.new(_sceneRoot())
	_tickets = Tickets.new(_sceneRoot())
	g.events.on("power:on", func(_p = null): _signOnGawk())
	net = g.get("net")
	if net != null and net.has_method("registerStream"):
		net.registerStream("z", "zombies")

func reset() -> void:
	for z in alive.duplicate():
		_remove(z)
	for z in dying.duplicate():
		_remove(z)
	alive.clear()
	dying.clear()
	for h in _flying:
		_releaseHead(h)
	_flying.clear()
	_entries.clear()
	frozen = false
	lure = null
	_lureField = null
	maxAlive = int(Config.T.rounds.maxAlive)
	_firstSpawn = true
	_oneTake = false
	_standby = false
	ZombieTypes.setEyeMode("static")
	ZombieTypes.setZombieTint(null)
	_byId.clear()
	net = game.get("net")
	_zn = load("res://scripts/actors/zombies_net.gd").new(self) if (net != null and net.inGame) else null
	if _stars != null:
		_stars.clear()
	if _tickets != null:
		_tickets.clear()
	# Pool a few models per variant so the first wave never hitches.
	ZombieTypes.prewarmModels(game, "tuned_in", 4)
	for id in ZombieTypes.bakedZombieIds("tuned_in", game):
		_prewarmHeads(id, 1)

# ---------------------------------------------------------------------------------------------- spawning
# A fresh zombie record (every field the manager and the types read) for def; id = the current _uid.
func _record(def: Dictionary, rnd: int, opts: Dictionary) -> Dictionary:
	var z := {
		"id": _uid, "type": def.id, "def": def, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "vy": 0.0,
		"hp": 1.0, "maxHp": 1.0, "state": "chase", "area": null, "group": null, "rig": null, "animator": null, "model": null,
		"radius": float(def.get("radius", 0.36)) if def.get("radius") else 0.36,
		"height": float(def.get("height", 1.6)) if def.get("height") else 1.6,
		"speed": 1.0, "scale": 1.0, "flags": {}, "head": null, "headR": 0.25,
		"hitZones": null, "round": rnd, "fromRound": opts.get("fromRound"), "dead": false,
		"anim": {"speed": 0.0, "grounded": true, "attack": 0.0, "hurt": 0.0, "climb": 0.0, "dead": 0.0, "down": false, "turn": 0.0, "clap": 0.0},
		"cd": 0.0, "attackT": 0.0, "swung": false, "stun": 0.0, "stagger": 0.0, "dieT": 0.0, "spawnT": 0.0, "knock": Vector3.ZERO,
		"entry": null, "los": false, "losT": randf() * 0.25, "navBest": INF, "navT": 0.0, "stuckT": 0, "stragT": 0,
		"gawkT": 0.0, "gawkAt": null, "lookYaw": 0.0, "lod": 0, "animAcc": 0.0, "visible": true, "camDist": 0.0,
		"artVariant": opts.get("variant") if opts.get("variant") != null else -1,
		# fields the JS adds lazily
		"sepX": 0.0, "sepZ": 0.0, "navStraight": false, "lured": false, "stuckPos": null, "removed": false, "blob": null,
		"hitTest": null, "deathDur": null, "dieDir": null, "dissolved": false, "onScreen": false,
		"_rayFrame": -1, "_rayZone": null, "_rayHead": null, "_rayMul": null, "_fxFrame": -1, "_hitKey": null, "_hmFrame": -1,
	}
	return z

func spawn(typeId = "tuned_in", entryId = null, pos = null, opts: Dictionary = {}):
	var g = game
	if _zn != null and _zn.client:
		return null                 # MP client: zombies come from the host (zombies_net.gd puppets)
	if alive.size() >= maxAlive:
		return null
	var def := ZombieTypes.getType(typeId if typeId != null else "tuned_in")
	var rnd: int = maxi(1, int(_f(g.rounds, "round", 1)) if g.rounds != null else 1)
	_uid += 1
	var z := _record(def, rnd, opts)
	if def.get("build") is Callable:
		def.build.call(g, z)
	if z.group == null:
		push_error("[zombies] build failed for %s" % def.id)
		if def.id != "tuned_in":
			return spawn("tuned_in", entryId, pos, opts)
		return null
	_finishBuild(z)
	var hpv = opts.get("hp")
	if hpv == null:
		hpv = def.hp.call(rnd, g) if def.get("hp") is Callable else Rounds.zombieHp(rnd)
	var hp := maxf(1.0, floorf(float(hpv) + 0.5))
	z.hp = hp
	z.maxHp = hp
	var spv = opts.get("speed")
	if spv == null:
		spv = def.speed.call(rnd, g) if def.get("speed") is Callable else Config.T.rounds.speeds.walk
	z.speed = float(spv)
	DAU.setLayerRecursive(z.group, Config.LAYERS.ZOMBIES)

	# Where does it come in?
	if pos != null:
		z.pos = _standPos(DAU.v3(pos))
		var fp: Vector3 = g.player.pos if _zn == null else _zn.facePos(z.pos)
		z.yaw = yawTo(fp.x - z.pos.x, fp.z - z.pos.z)
		z.state = "chase"
		z.area = g.level.areaAt(z.pos.x, z.pos.z)
		z.spawnT = 0.25             # quick pop-in out of a burst of static
		if not opts.get("silent", false):
			_burst(z.pos + Vector3(0, 0.8, 0), {"shape": "static", "count": 12, "speed": 1.8, "size": 0.09, "life": 0.6})
	else:
		var sp = _spawnerById(entryId) if entryId else _pickSpawner(def)
		if sp == null:
			# Nothing sensible (should not happen): drop it near the player's area like a debug spawn.
			var p: Vector3 = g.player.pos if _zn == null else _zn.facePos(Vector3.ZERO)
			z.pos = Vector3(p.x + 6, p.y, p.z)
			z.state = "chase"
		elif sp.kind == "screen":
			_beginScreen(z, sp.ss)
		else:
			_beginEntry(z, sp.win)
		_firstSpawn = false
	_addToWorld(z, pos != null, opts.get("silent", false))
	return z

# Default head node + humanoid hit zones when the type's build did not provide them.
func _finishBuild(z: Dictionary) -> void:
	if z.head == null:
		z.head = DAU.node3d()
		z.head.position = Vector3(0, z.height - z.headR, 0)
		z.group.add_child(z.head)
	if z.hitZones == null and not (z.hitTest is Callable):
		z.hitZones = ZombieTypes.humanoidHitZones({"rig": z.rig, "head": z.head, "headR": z.headR})

# Adds a built zombie to the scene and the lists (MP host: registers it and queues its spawn message).
func _addToWorld(z: Dictionary, posSpawn := false, silent := false) -> void:
	var g = game
	var G: Node3D = z.group
	G.rotation_order = EULER_ORDER_YXZ
	G.position = z.pos
	G.rotation = Vector3(0, z.yaw, 0)
	G.scale = Vector3(z.scale, z.scale, z.scale)
	_sceneRoot().add_child(G)
	z.blob = g.fx.blob(G, z.radius * 1.15) if g.fx != null else null
	alive.append(z)
	_byId[z.id] = z
	if _zn != null:
		_zn.added(z, posSpawn, silent)
	g.events.emit("zombie:spawn", {"z": z})

# Where a body given an explicit spawn pos can stand: the nav floor under it (debug.spawn may hand us the top of a
# desk or a lamp), else the nearest nav cell within 3 m.
func _standPos(pos: Vector3) -> Vector3:
	var nav = game.nav
	var out := pos
	if nav == null or not nav.has_method("heightAt"):
		return out
	var h0: float = nav.heightAt(pos.x, pos.z)
	if h0 > -INF:
		if absf(pos.y - h0) > 0.6:
			out.y = h0
		return out
	var r := 0.5
	while r <= 3.0:
		var n := maxi(8, int(floorf(r * 12.0 + 0.5)))
		for i in n:
			var a := (float(i) / n) * PI * 2.0
			var x := pos.x + cos(a) * r
			var zz := pos.z + sin(a) * r
			var h: float = nav.heightAt(x, zz)
			if h > -INF:
				return Vector3(x, h, zz)
		r += 0.5
	return out

func _spawnerById(id):
	var L = game.level
	var w = L.windows.get(id)
	if w != null:
		return {"kind": "entry", "win": w}
	var ss = L.screenSpawns.get(id)
	if ss != null:
		return {"kind": "screen", "ss": ss}
	return null

# Areas the spawners are active in: the player's area (weight 1) + areas behind its open doors (0.5).
func _activeAreas() -> Dictionary:
	if _zn != null:
		return _zn.activeAreas()        # MP: union over the players (zombies_net.gd)
	var g = game
	var L = g.level
	var here = _f(g.player, "area")
	if not here:
		here = L.areaAt(g.player.pos.x, g.player.pos.z)
	if not here:
		here = _lastArea
	if not here:
		here = "lobby"
	_lastArea = here
	var w := {here: 1.0}
	for d in L.doors.values():
		var areas = _f(d, "areas")
		if not _f(d, "open", false) or areas == null or not areas.has(here):
			continue
		var other = areas[1] if areas[0] == here else areas[0]
		if not w.has(other):
			w[other] = 0.5
	return w

# GDD §5.9 spawner choice for a type. Returns { kind:'entry', win } | { kind:'screen', ss } | null.
# opts.nearest: the nearest active spawner at least 8 m away (straggler rule) instead of a weighted pick.
func _pickSpawner(def: Dictionary, opts: Dictionary = {}):
	var g = game
	var L = g.level
	var p: Vector3 = g.player.pos
	var mode: String = def.get("spawnMode") if def.get("spawnMode") else "window"
	var nearest: bool = opts.get("nearest", false)
	if _firstSpawn and not nearest and mode != "screen" and L.windows.get("w_lobby_west") != null:
		return {"kind": "entry", "win": L.windows.w_lobby_west}
	var areas := _activeAreas()
	var cands: Array = []
	var wantEntries := mode == "window" or mode == "both"
	var wantScreens := mode == "screen" or mode == "both"
	var addEntries := func(filterFn = null) -> void:
		for w in L.windows.values():
			var wt = areas.get(_f(w, "area"))
			if not wt or (def.get("entryFilter") is Callable and not def.entryFilter.call(w)) or (filterFn != null and not filterFn.call(w)):
				continue
			var q = _entries.get(_f(w, "id"))
			var busy: int = ((1 if q.front != null else 0) + q.waiting.size()) if q != null else 0
			var ins = w.inside
			cands.append({"kind": "entry", "win": w, "pos": Vector3(float(ins[0]), 0, float(ins[2])), "weight": wt / (1.0 + busy * 0.8)})
	var addScreens := func() -> void:
		for ss in L.screenSpawns.values():
			var wt = areas.get(_f(ss, "area"))
			if not wt:
				continue
			cands.append({"kind": "screen", "ss": ss, "pos": ss.pos, "weight": wt})
	if wantEntries:
		addEntries.call()
	if wantScreens:
		addScreens.call()
		# Forecasters in the Yard use the fence climbs (GDD §5.9).
		if mode == "screen":
			addEntries.call(func(w): return _f(w, "area") == "yard" and _f(w, "type") == "fence")
	if cands.is_empty():
		if not wantEntries:
			addEntries.call()
		if not wantScreens:
			addScreens.call()
	if cands.is_empty():
		return null
	var far: Array = cands.filter(func(c): return _spD(c.pos, p) >= RULE_8M)
	if far.is_empty():
		var best = cands[0]
		var bd := -1.0
		for c in cands:
			var d := _spD(c.pos, p)
			if d > bd:
				bd = d
				best = c
		return best
	if nearest:
		var best = far[0]
		var bd := INF
		for c in far:
			var d := _spD(c.pos, p)
			if d < bd:
				bd = d
				best = c
		return best
	var sum := 0.0
	for c in far:
		sum += c.weight
	var r: float = g.rand() * sum
	for c in far:
		r -= c.weight
		if r <= 0.0:
			return c
	return far[far.size() - 1]

# Spawner distance for the 8 m rule: to the player (solo); MP: to the nearest player that is not off air.
func _spD(pos: Vector3, p: Vector3) -> float:
	if _zn != null:
		return _zn.minPlayerDist(pos)
	return _hypot(pos.x - p.x, pos.z - p.z)

func _entryQueue(id) -> Dictionary:
	var q = _entries.get(id)
	if q == null:
		q = {"front": null, "waiting": []}
		_entries[id] = q
	return q

func _beginEntry(z: Dictionary, win) -> void:
	var g = game
	var outV = _f(win, "outsidePos")
	var out: Vector3 = outV if outV is Vector3 else DAU.v3(win.outside)
	var spV = _f(win, "spawnPos")
	var sp: Vector3 = spV if spV is Vector3 else DAU.v3(win.spawn)
	var ins = win.inside
	# Scatter the spawn point a little sideways so a crowd does not stack.
	var ox: float = out.x - float(ins[0])
	var oz: float = out.z - float(ins[2])
	var ol := _hypot(ox, oz)
	if ol == 0.0:
		ol = 1.0
	var side: float = (g.rand() - 0.5) * 2.2
	z.pos = Vector3(sp.x + (-oz / ol) * side, 0, sp.z + (ox / ol) * side)
	var fy := _floorAt(z.pos.x, z.pos.z, 2.0)
	z.pos.y = fy if fy > -INF else 0.0
	var rotY = _f(win, "rotY")
	z.yaw = float(rotY) if rotY != null else yawTo(-ox, -oz)
	z.state = "approach"
	z.area = null
	var wt = _f(win, "type")
	z.entry = {"kind": "fence" if wt == "fence" else ("gate" if wt == "gate" else "window"), "id": _f(win, "id"), "win": win,
		"t": 0.0, "out": Vector3(out.x, 0, out.z), "inw": Vector3(-ox / ol, 0, -oz / ol), "slot": -1, "style": null,
		"tearT": 0.0, "inP": null, "popped": false}
	var fo := _floorAt(out.x, out.z, 2.0)
	z.entry.out.y = fo if fo > -INF else 0.0

func _beginScreen(z: Dictionary, ss) -> void:
	var g = game
	var Z := _Z()
	var rotY := float(ss.rotY)
	var sspos: Vector3 = ss.pos
	var fwd := Vector3(-sin(rotY), 0, -cos(rotY))
	z.yaw = rotY
	z.state = "screen"
	z.area = _f(ss, "area")
	var land := Vector3(sspos.x + fwd.x * 1.1, 0, sspos.z + fwd.z * 1.1)
	var fy := _floorAt(land.x, land.z, sspos.y + 0.5)
	land.y = fy if fy > -INF else 0.0
	z.entry = {"kind": "screen", "id": _f(ss, "id"), "ss": ss, "t": 0.0, "phase": "tele", "fwd": fwd, "land": land,
		"inGlass": true, "tele": null, "from": null}
	z.pos = land
	z.group.visible = false
	# screens.telegraph flares that CRT (static + growing silhouette + glass bulge) and plays screen_telegraph
	# through its TV speaker; without it we play the cue ourselves.
	var tele = null
	if g.screens != null and g.screens.has_method("telegraph"):
		tele = g.screens.telegraph(_f(ss, "id"), float(Z.screenTelegraph))
	z.entry.tele = tele
	if tele == null or _f(tele, "active", true) == false:
		_play("screen_telegraph", {"pos": sspos, "tv": true})
	g.events.emit("zombie:telegraph", {"z": z, "screenId": _f(ss, "id"), "seconds": Z.screenTelegraph})

# ------------------------------------------------------------------------------------------------ update
func update(dt: float) -> void:
	if not (dt > 0.0):
		return
	var g = game
	_frame += 1
	_hitSfx = 0
	var pu = g.powerups
	var oneTake := _puActive(pu, "one_take")
	if oneTake != _oneTake:
		_oneTake = oneTake
		ZombieTypes.setEyeMode("stars" if oneTake else "static")
	var standby := frozen and _puActive(pu, "please_stand_by")
	if standby != _standby:
		_standby = standby
		ZombieTypes.setZombieTint("standby" if standby else null)

	if _zn != null and _zn.client:
		_zn.clientTick(dt)              # MP client: puppets (interpolation, cues, animation, local body push)
	else:
		if _zn != null:
			_zn.hostPre(dt)             # MP host: target set + retargeting
		if not frozen:
			_separation()
		var list := alive
		for i in range(list.size() - 1, -1, -1):
			if i >= list.size():
				continue
			var z: Dictionary = list[i]
			if not frozen:
				_think(z, dt, i)
				if z.dead or z.removed:
					continue
				_animate(z, dt)
		if not frozen:
			_blockPlayer()
			if _zn != null:
				_zn.blockRemotes()
	_updateDying(dt)
	_updateHeads(dt)
	if _stars != null:
		_stars.update(dt)
	if _tickets != null:
		_tickets.update(dt)

static func _puActive(pu, id: String) -> bool:
	if pu == null:
		return false
	if pu.has_method("isActive"):
		return _t(pu.isActive(id))
	var act = _f(pu, "active")
	return act is Dictionary and float(act.get(id, 0)) > 0.0

func lateUpdate(_dt = null) -> void:
	_lod()
	if _zn != null:
		_zn.late()                      # MP: host event outbox + snapshot stream; client damage batch

# Boid separation (GDD §5.10: radius 0.6 m) among grounded zombies.
func _separation() -> void:
	var L := alive
	for z in L:
		z.sepX = 0.0
		z.sepZ = 0.0
	for i in L.size():
		var a: Dictionary = L[i]
		if a.state != "chase" and a.state != "attack":
			continue
		for j in range(i + 1, L.size()):
			var b: Dictionary = L[j]
			if b.state != "chase" and b.state != "attack":
				continue
			var dx: float = a.pos.x - b.pos.x
			var dz: float = a.pos.z - b.pos.z
			var rr := maxf(SEP_R, (a.radius + b.radius) * 0.95)
			var d2 := dx * dx + dz * dz
			if d2 >= rr * rr or absf(a.pos.y - b.pos.y) > 1.0:
				continue
			var d := sqrt(d2)
			if d == 0.0:
				d = 1e-3
			var k := (rr - d) / rr
			var nx: float = dx / d if d2 > 1e-8 else randf() - 0.5
			var nz: float = dz / d if d2 > 1e-8 else randf() - 0.5
			a.sepX += nx * k
			a.sepZ += nz * k
			b.sepX -= nx * k
			b.sepZ -= nz * k

func _think(z: Dictionary, dt: float, _index: int) -> void:
	var g = game
	z.cd = maxf(0.0, z.cd - dt)
	z.stagger = maxf(0.0, z.stagger - dt)
	z.anim.hurt = maxf(0.0, z.anim.hurt - dt / 0.25)
	if z.spawnT > 0.0:
		z.spawnT = maxf(0.0, z.spawnT - dt)
	# Knockback shove (decays).
	if z.knock.length_squared() > 1e-4 and (z.state == "chase" or z.state == "attack"):
		_moveCircle(z, z.knock * dt, z.radius, z.height, 0.45)
		z.knock *= exp(-dt * 9.0)
	match z.state:
		"approach", "queue":
			_approach(z, dt)
		"tear":
			_tear(z, dt)
		"vault":
			_vault(z, dt)
		"screen":
			_screen(z, dt)
		_:
			_chase(z, dt)
	if z.dead or z.removed:
		return
	if z.state != "chase" and z.state != "attack" and z.def.get("updateEntry") is Callable:
		z.def.updateEntry.call(g, z, dt)

# --- window / fence / gate entry --------------------------------------------------------------------
func _approach(z: Dictionary, dt: float) -> void:
	var e: Dictionary = z.entry
	var q := _entryQueue(e.id)
	# Target: the outside point when it is our turn, else a waiting slot further out.
	if q.front == null:
		q.front = z
	if not is_same(q.front, z) and _idx(q.waiting, z) < 0:
		q.waiting.append(z)
	var slot: int = -1 if is_same(q.front, z) else _idx(q.waiting, z)
	var tgt: Vector3 = e.out
	if slot >= 0:
		var back := 0.95 + slot * 0.75
		var side := (1.0 if slot % 2 else -1.0) * 0.45
		tgt += e.inw * -back
		tgt.x += -e.inw.z * side
		tgt.z += e.inw.x * side
	var dx: float = tgt.x - z.pos.x
	var dz: float = tgt.z - z.pos.z
	var d := _hypot(dx, dz)
	var sp := minf(z.speed, 3.2)
	var rotY := float(_f(e.win, "rotY", 0.0))
	if d > 0.06:
		var step := minf(d, sp * dt)
		z.pos.x += (dx / d) * step
		z.pos.z += (dz / d) * step
		var fy := _floorAt(z.pos.x, z.pos.z, z.pos.y + 0.5)
		if fy > -INF:
			z.pos.y += (fy - z.pos.y) * minf(1.0, dt * 12.0)
		_turnTo(z, yawTo(dx, dz) if d > 0.4 else rotY, dt)
		z.anim.speed = sp if d > 0.2 else sp * d / 0.2
		z.state = "queue" if slot >= 0 else "approach"
	else:
		z.anim.speed = 0.0
		_turnTo(z, rotY, dt)
		if slot < 0:
			_arrive(z)
		else:
			z.state = "queue"
	_place(z)

# Reached the outside point: tear the boards, or the type's own entry style.
func _arrive(z: Dictionary) -> void:
	var g = game
	var e: Dictionary = z.entry
	var win = e.win
	var style = null
	if z.def.get("entry") is Callable:
		style = z.def.entry.call(g, z, win)
	e.style = style if style is Dictionary else null
	e.t = 0.0
	style = e.style
	var wtype = _f(win, "type")
	if style != null and style.get("style") == "blast" and wtype == "boarded":
		var n = _hcall(win, "breakAll")
		if n != null and int(n) > 0:
			var wp = _f(win, "pos")
			var a: Vector3 = wp if wp is Vector3 else e.out
			a.y = float(_f(win, "sill", 0.0)) + 0.9
			_burst(a, {"shape": "confetti", "count": 18, "colors": [Config.PAL.teak, Config.PAL.walnut, Config.PAL.cream, Config.PAL.skyTop], "speed": 5})
			_burst(a, {"shape": "puff", "count": 8, "size": 0.3})
			if g.fx != null:
				g.fx.shake(0.25, 0.3)
		z.state = "vault"
		return
	if wtype == "boarded" and float(_f(win, "boards", 0)) > 0 and not (style != null and style.get("tear") == false):
		z.state = "tear"
		e.tearT = 0.0
		return
	z.state = "vault"
	_play("window_vault", {"pos": z.pos})

func _tear(z: Dictionary, dt: float) -> void:
	var e: Dictionary = z.entry
	var win = e.win
	_turnTo(z, float(_f(win, "rotY", 0.0)), dt)
	var T0 := float(_Z().boardTear)
	var prev: float = e.tearT
	e.tearT += dt
	# One pull per board: arms rise (anticipation) and yank at 55 %.
	var ph: float = fmod(e.tearT, T0) / T0
	var pph: float = fmod(prev, T0) / T0
	z.anim.attack = minf(0.99, ph)
	z.anim.speed = 0.0
	if pph < 0.55 and ph >= 0.55:
		if float(_f(win, "boards", 0)) > 0 and _hcall(win, "breakBoard"):
			_kick(z, 0.5)
			if randf() < 0.35:
				_play("zmb_groan", {"pos": z.pos, "rate": 1.1})
	if float(_f(win, "boards", 0)) <= 0 and ph < 0.2:
		z.anim.attack = 0.0
		z.state = "vault"
		e.t = 0.0
		_play("window_vault", {"pos": z.pos})
	_place(z)

func _vault(z: Dictionary, dt: float) -> void:
	var Z := _Z()
	var e: Dictionary = z.entry
	var win = e.win
	var st = e.style
	var kind: String
	if st != null and st.get("style"):
		kind = st.style
	else:
		kind = "fence" if e.kind == "fence" else ("gate" if e.kind == "gate" else "vault")
	var dur: float
	if st != null and st.get("time"):
		dur = float(st.time)
	else:
		dur = float(Z.fence) if kind == "fence" else (float(Z.gate) if kind == "gate" else (1.5 if kind == "blast" else float(Z.vault)))
	e.t += dt
	var u := clamp01(e.t / dur)
	var outP: Vector3 = e.out
	var ins = win.inside
	if e.inP == null:
		var iy: float = float(ins[1]) if ins[1] else 0.0
		var fy := _floorAt(float(ins[0]), float(ins[2]), iy + 0.8)
		e.inP = Vector3(float(ins[0]), fy if fy > -INF else iy, float(ins[2]))
	var inP: Vector3 = e.inP
	var sill := float(_f(win, "sill", 0.0))
	var h: float
	var y: float
	var pitch := 0.0
	var sx := 1.0
	var sy := 1.0
	var climb := 0.0
	if kind == "fence":
		var wtop = _f(win, "top")
		var top: float = outP.y + (float(wtop) if wtop else 3.0) + 0.15
		if u < 0.6:
			h = 0.45 * smooth(u / 0.6)
			y = outP.y + (top - outP.y) * easeOutCubic(u / 0.6)
			climb = 0.02 + u
		elif u < 0.75:
			var k := (u - 0.6) / 0.15
			h = 0.45 + 0.3 * k
			y = top + sin(k * PI) * 0.12
			pitch = -0.5 * sin(k * PI)
			climb = 0.7
		else:
			var k := (u - 0.75) / 0.25
			h = 0.75 + 0.25 * k
			y = top + (inP.y - top) * k * k
	elif kind == "gate" or kind == "squeeze" or kind == "toothpaste" or kind == "blast":
		h = smooth(u)
		var lift := maxf(0.0, sill + 0.05) if kind == "squeeze" else 0.0
		y = outP.y + (inP.y - outP.y) * h + sin(u * PI) * lift
		var k := sin(u * PI)
		if kind == "gate":
			sx = 1.0 - 0.45 * k
			sy = 1.0 + 0.08 * k
		elif kind == "squeeze":
			sy = 1.0 - 0.6 * k
			sx = 1.0 + 0.35 * k
		else:
			sx = 1.0 - 0.5 * k
			sy = 1.0 + 0.25 * k
		if u >= 1.0 and not e.popped:
			e.popped = true
			_kick(z, 1.2)
	else:
		# Window vault: climb onto the sill, over, drop inside.
		var top: float = maxf(outP.y, inP.y) + (sill + 0.12 if sill > 0.05 else 0.28)
		if u < 0.45:
			h = 0.36 * smooth(u / 0.45)
			y = outP.y + (top - outP.y) * easeOutCubic(u / 0.45)
			climb = 0.05 + u
		elif u < 0.7:
			var k := (u - 0.45) / 0.25
			h = 0.36 + 0.34 * k
			y = top + sin(k * PI) * 0.1
			pitch = -0.55 * sin(k * PI)
			climb = 0.5
		else:
			var k := (u - 0.7) / 0.3
			h = 0.7 + 0.3 * k
			y = top + (inP.y - top) * k * k
	z.pos = Vector3(outP.x + (inP.x - outP.x) * h, y, outP.z + (inP.z - outP.z) * h)
	z.anim.climb = climb
	z.anim.speed = 0.0 if climb > 0.0 else 1.2
	z.anim.attack = 0.0
	_turnTo(z, float(_f(win, "rotY", 0.0)), dt)
	_place(z, pitch, sx, sy)
	if u >= 1.0:
		_landInside(z)

func _landInside(z: Dictionary) -> void:
	var e: Dictionary = z.entry
	var q = _entries.get(e.id)
	if q != null and is_same(q.front, z):
		q.front = q.waiting.pop_front() if q.waiting.size() > 0 else null
		if q.front != null:
			q.front.state = "approach"
	z.state = "chase"
	z.anim.climb = 0.0
	z.area = _f(e.win, "area")
	z.vy = 0.0
	z.entry = null
	z.navBest = INF
	z.navT = 0.0
	_kick(z, 1.0)
	_burst(z.pos + Vector3(0, 0.05, 0), {"shape": "puff", "count": 4, "size": 0.16, "speed": 1.2, "colors": ["#E8DCC8", "#CDBFA8"]})
	_place(z)

# --- screen spawns: telegraph, taffy emerge, drop -----------------------------------------------------
func _screen(z: Dictionary, dt: float) -> void:
	var g = game
	var Z := _Z()
	var e: Dictionary = z.entry
	var ss = e.ss
	var sspos: Vector3 = ss.pos
	e.t += dt
	var f: Vector3 = e.fwd
	if e.phase == "tele":
		if e.t >= float(Z.screenTelegraph):
			e.phase = "emerge"
			e.t = 0.0
			e.tele = null             # expired on the screens side (its handle may be pooled and reused)
			z.group.visible = true
			_play("screen_emerge", {"pos": sspos})
		return
	if e.phase == "emerge":
		var u := clamp01(e.t / float(Z.screenEmerge))
		var s := 0.1 + 0.9 * easeOutBack(u)
		var k := sin(u * PI)
		# Feet stay in the glass; the body leans out of the screen head-first and snaps back like taffy.
		z.pos = Vector3(sspos.x - f.x * 0.05 + f.x * 0.25 * u, sspos.y - 0.25 * s, sspos.z - f.z * 0.05 + f.z * 0.25 * u)
		z.yaw = float(ss.rotY)
		_place(z, -1.25 * (1.0 - 0.35 * u), s * (1.0 - 0.3 * k), s * (1.0 + 0.45 * k), s * (1.0 + 0.25 * k))
		z.anim.speed = 0.0
		z.anim.climb = 0.3 + u * 0.6
		if u >= 1.0:
			e.phase = "drop"
			e.t = 0.0
			e.inGlass = false
			e.from = z.pos
		return
	# drop: swing the feet out and down to the floor in front of the screen, landing squash.
	var u := clamp01(e.t / 0.42)
	var from: Vector3 = e.from
	var to: Vector3 = e.land
	z.pos = Vector3(from.x + (to.x - from.x) * smooth(u), from.y + (to.y - from.y) * u * u + sin(u * PI) * 0.25, from.z + (to.z - from.z) * smooth(u))
	z.anim.climb = 0.0
	_place(z, -1.25 * 0.65 * (1.0 - easeOutCubic(u)))
	if u >= 1.0:
		z.state = "chase"
		z.entry = null
		var ar = g.level.areaAt(z.pos.x, z.pos.z)
		if ar:
			z.area = ar
		_kick(z, 1.2)
		_burst(z.pos + Vector3(0, 0.05, 0), {"shape": "static", "count": 10, "speed": 1.6})
		_place(z)

# --- chase + attack -------------------------------------------------------------------------------------
func _chase(z: Dictionary, dt: float) -> void:
	var g = game
	var p = g.player if _zn == null else z.tgt
	if p == null:
		_zn.idle(z, dt)                 # MP: nobody to chase (everyone down / off air)
		return
	var ppos: Vector3 = p.pos
	if z.stun > 0.0:
		z.stun -= dt
		z.anim.speed = 0.0
		z.anim.attack = 0.0
		if z.state == "attack":
			z.state = "chase"
		_fall(z, dt)
		_place(z)
		return
	# Lure (Tiny Tele): only zombies within its PATH radius (GDD §9.3) are lured; once lured they stay lured.
	if lure != null and not z.lured and _lureField != null and _lfDist(z.pos.x, z.pos.z) <= lureR:
		z.lured = true
	# Type behaviour first (specials may take over).
	if z.def.get("update") is Callable:
		var handled: bool = z.def.update.call(g, z, dt) == true
		if z.dead or z.removed:
			return
		if handled:
			_bookkeep(z, dt)
			_place(z)
			return
	if z.gawkT > 0.0:
		z.gawkT -= dt
		if z.gawkT < GAWK:
			z.anim.speed = 0.0
			z.vel *= exp(-dt * 8.0)
			_fall(z, dt)
			_place(z)
			return

	var lureP = lure if lure != null and z.lured else null
	var goal: Vector3 = lureP if lureP != null else ppos
	var dx: float = goal.x - z.pos.x
	var dz: float = goal.z - z.pos.z
	var dist := _hypot(dx, dz)
	var dy: float = goal.y - z.pos.y

	if z.state == "attack":
		_attack(z, dt, dist, dy)
		_bookkeep(z, dt)
		_place(z)
		return

	# Mesmerized by a lure (Tiny Tele): kneel in a ring around it.
	if lureP != null and dist < 2.3:
		z.anim.down = true
		z.anim.speed = 0.0
		z.vel *= exp(-dt * 10.0)
		_turnTo(z, yawTo(dx, dz), dt)
		_fall(z, dt)
		_place(z)
		return
	z.anim.down = false

	# In reach and nothing solid in between (a thin wall between two rooms must not let a swipe through).
	var rangeV := float(z.def.range)
	if lureP == null and p.alive and dist < rangeV and absf(dy) < 1.2 and z.cd <= 0.0 and z.spawnT <= 0.0 and \
			_los(Vector3(z.pos.x, z.pos.y + z.height * 0.6, z.pos.z), Vector3(ppos.x, ppos.y + 1.0, ppos.z)):
		z.state = "attack"
		z.attackT = 0.0
		z.swung = false
		_attack(z, dt, dist, dy)
		_place(z)
		return

	# Line of sight (refreshed every 0.25 s, staggered).
	z.losT -= dt
	if z.losT <= 0.0:
		z.losT = 0.25
		if dist < 16.0 and lureP == null:
			var a := Vector3(z.pos.x, z.pos.y + z.height * 0.85, z.pos.z)
			var b := Vector3(ppos.x, ppos.y + 1.4, ppos.z)
			z.los = _los(a, b)
			z.navStraight = z.los and _navDist(z.pos.x, z.pos.z) < dist * 1.3 + 1.0
		else:
			z.los = false
			z.navStraight = false
	# Steering: straight at you when close and visible, else the flow field.
	var dir: Vector3
	if lureP == null and z.los and z.navStraight and dist < LOS_NEAR and absf(dy) < 0.7:
		dir = Vector3(dx, 0, dz).normalized()
	else:
		if lureP != null and _lureField != null:
			dir = _lfDir(z.pos.x, z.pos.z)
		else:
			dir = _navDir(z.pos.x, z.pos.z)
		if dir.length_squared() < 1e-6 and dist > 1e-3:
			dir = Vector3(dx / dist, 0, dz / dist)
	var speed: float = z.speed * (0.25 if z.stagger > 0.0 else 1.0) * (0.0 if z.spawnT > 0.0 else 1.0)
	if lureP == null and dist < rangeV * 0.78:
		speed = 0.0
	# Desired velocity + separation.
	var sepW := maxf(1.2, z.speed * 0.9)
	var cx: float = dir.x * speed + z.sepX * sepW
	var cz: float = dir.z * speed + z.sepZ * sepW
	var k := 1.0 - exp(-dt * ACCEL)
	z.vel.x += (cx - z.vel.x) * k
	z.vel.z += (cz - z.vel.z) * k
	# Face the movement; face the player when close.
	var face: float
	if dist < 2.2 and lureP == null:
		face = yawTo(dx, dz)
	elif z.vel.x * z.vel.x + z.vel.z * z.vel.z > 0.04:
		face = yawTo(z.vel.x, z.vel.z)
	else:
		face = z.yaw
	_turnTo(z, face, dt)
	_move(z, dt)
	z.anim.speed = _hypot(z.vel.x, z.vel.z)
	_bookkeep(z, dt)
	_place(z)

func _move(z: Dictionary, dt: float) -> void:
	z.vy -= GRAVITY * dt
	var r := _moveCircle(z, Vector3(z.vel.x * dt, z.vy * dt, z.vel.z * dt), z.radius, z.height, 0.45)
	if r.get("onGround", false):
		z.vy = 0.0
	z.anim.grounded = true

func _fall(z: Dictionary, dt: float) -> void:
	z.vel.x *= exp(-dt * 10.0)
	z.vel.z *= exp(-dt * 10.0)
	_move(z, dt)

func _attack(z: Dictionary, dt: float, dist: float, dy: float) -> void:
	var g = game
	var p = g.player if _zn == null else z.tgt
	var TI: Dictionary = _Z().tunedIn
	var wind: float = float(z.def.windup) if z.def.get("windup") else float(TI.windup)
	var total := wind * 2.5
	var prev: float = z.attackT
	z.attackT += dt
	z.anim.attack = minf(0.99, z.attackT / total)
	z.anim.speed = 0.0
	z.vel *= exp(-dt * 10.0)
	if z.attackT < wind:
		_turnTo(z, yawTo(p.pos.x - z.pos.x, p.pos.z - z.pos.z), dt * 1.5)
	# Swipe: a small lunge while the arms come down.
	if z.attackT >= wind and z.attackT < wind + 0.18:
		var delta := Vector3(-sin(z.yaw) * 1.3 * dt, 0, -cos(z.yaw) * 1.3 * dt)
		if dist > 0.85:
			_moveCircle(z, delta, z.radius, z.height, 0.45)
	if prev < wind and z.attackT >= wind:
		_play("zmb_swipe", {"pos": z.pos})
	if not z.swung and z.attackT >= wind + 0.06:
		z.swung = true
		z.cd = float(z.def.cd) if z.def.get("cd") != null else float(TI.cd)
		var fwdDot: float = (-sin(z.yaw) * (p.pos.x - z.pos.x) + -cos(z.yaw) * (p.pos.z - z.pos.z)) / maxf(1e-3, dist)
		var rng: float = float(z.def.range) if z.def.get("range") else 1.3
		if not (lure != null and z.lured) and p.alive and dist < rng + 0.35 and absf(dy) < 1.3 and fwdDot > 0.3:
			var dmg = z.def.dmg if z.def.get("dmg") != null else TI.dmg
			if _zn != null and p != g.player:
				# MP: the victim's own peer applies the hit (zombies.net_hurt)
				var rkb: Vector3 = p.pos - z.pos
				rkb.y = 0.0
				_zn.hurtRemote(p, dmg, z, rkb.normalized() * 2.2, "")
			elif p.hurt(dmg, z.pos):
				g.events.emit("zombie:attack", {"z": z, "dmg": dmg})
				var kb: Vector3 = p.pos - z.pos
				kb.y = 0.0
				kb = kb.normalized() * 2.2
				if p.has_method("knockback"):
					p.knockback(kb)
	_fall(z, dt)
	if z.attackT >= total:
		z.state = "chase"
		z.anim.attack = 0.0

# Area, anti-stuck and the straggler rule (chase states only).
func _bookkeep(z: Dictionary, dt: float) -> void:
	var g = game
	var p = g.player if _zn == null else z.tgt
	var ar = g.level.areaAt(z.pos.x, z.pos.z)
	if ar:
		z.area = ar
	z.navT += dt
	if z.navT < 1.0:
		return
	z.navT = 0.0
	var nd := _navDist(z.pos.x, z.pos.z)
	var near := p != null and _hypot(p.pos.x - z.pos.x, p.pos.z - z.pos.z) < 3.0
	# Anti-stuck (GDD §5.10): nav distance has not decreased for 8 s while not attacking. A zombie that keeps walking
	# (>= 35 % of its speed over the last second) is chasing a kiting player, not stuck: training circles keep the
	# path length constant for much longer than 8 s.
	if z.stuckPos == null:
		z.stuckPos = z.pos
	var walked := _hypot(z.pos.x - z.stuckPos.x, z.pos.z - z.stuckPos.z) >= maxf(0.25, 0.35 * z.speed)
	z.stuckPos = z.pos
	var lured: bool = lure != null and z.lured
	if nd < z.navBest - 0.4 or walked or near or lured or z.state == "attack" or z.stun > 0.0 or z.gawkT > 0.0:
		z.navBest = minf(z.navBest, nd)
		if near or lured or walked:
			z.navBest = nd
		z.stuckT = 0
	else:
		z.stuckT += 1
		if z.stuckT >= STUCK_TIME:
			despawn(z, true)
			return
	# Straggler rule: last zombie of a round, > 40 m of path away for 20 s -> re-enter near the player.
	var R = g.rounds
	if R != null and R.phase == "active" and R.toSpawn == 0 and z.fromRound != null and roundAlive(z.fromRound) == 1 and nd > STRAGGLER_DIST:
		z.stragT += 1
		if z.stragT >= STRAGGLER_TIME:
			_restraggle(z)
	else:
		z.stragT = 0

func _restraggle(z: Dictionary) -> void:
	var d: Dictionary = z.def
	if d.get("spawnMode") == "screen":
		d = d.duplicate()
		d.spawnMode = "both"
	var sp = _pickSpawner(d, {"nearest": true})
	z.stragT = 0
	if sp == null:
		return
	z.navBest = INF
	z.vel = Vector3.ZERO
	if sp.kind == "screen":
		_beginScreen(z, sp.ss)
	else:
		_beginEntry(z, sp.win)
	_place(z)
	if _zn != null:
		_zn.outReenter(z)

func _turnTo(z: Dictionary, yaw: float, dt: float) -> void:
	var d := angDiff(yaw, z.yaw)
	var step := d * minf(1.0, dt * TURN)
	z.yaw += step
	z.anim.turn = step / dt if dt > 0.0 else 0.0

# Writes pos/yaw (+ entry pitch / squash) to the model.
func _place(z: Dictionary, pitch := 0.0, sx := 1.0, sy := 1.0, sz := 1.0) -> void:
	var G: Node3D = z.group
	G.position = z.pos
	G.rotation_order = EULER_ORDER_YXZ
	G.rotation = Vector3(pitch, z.yaw, 0)
	var s: float = z.scale
	if z.spawnT > 0.0:
		s *= easeOutBack(1.0 - z.spawnT / 0.25)
	G.scale = Vector3(s * sx, s * sy, s * (sx if sz == 1.0 else sz))
	if _zn != null:
		# MP: the snapshot carries the last entry pose (pitch / squash) to the puppets
		z["pP"] = pitch
		z["pX"] = sx
		z["pY"] = sy
		z["pZ"] = sz

# Keep the player out of zombie bodies (shared push: zombies are solid, crowds can pin you).
func _blockPlayer() -> void:
	var g = game
	var p = g.player
	if p == null or not p.alive:
		return
	if _zn != null and (p.get("downed") == true or p.get("offAir") == true):
		return
	var prad := float(_f(p, "radius", 0.38))
	var px := 0.0
	var pz := 0.0
	for z in alive:
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
		_moveCircle(z, Vector3(-(dx / d) * o * 0.4, 0, -(dz / d) * o * 0.4), z.radius, z.height, 0.45)
		z.group.position = z.pos
	if px != 0.0 or pz != 0.0:
		_moveCircle(p, Vector3(px, 0, pz), prad, float(_f(p, "height", 1.75)), 0.45)

# --- animation ----------------------------------------------------------------------------------------
func _animate(z: Dictionary, dt: float) -> void:
	var a = z.animator
	if a == null:
		return
	z.animAcc += dt
	# LOD: far or off-screen zombies animate every 3rd frame (the spring integrator substeps the bigger dt).
	if z.lod > 0 and (_frame + z.id) % 3 != 0:
		return
	var step: float = z.animAcc
	z.animAcc = 0.0
	a.update(step, z.anim)
	var J = _f(z.rig, "joints")
	if J == null or _f(J, "shoulderL") == null:
		return
	# Clap (Tuned-In, every 4th step): hands swing together.
	var clap := float(z.anim.get("clap", 0.0))
	if clap > 0.0:
		J.shoulderL.rotation.z += clap * 0.32
		J.shoulderR.rotation.z -= clap * 0.32
		J.elbowL.rotation.x += clap * 0.25
		J.elbowR.rotation.x += clap * 0.25
	# Gawk at the nearest TV (Sign-On), or look at the lure.
	var hj = _f(J, "head")
	if z.gawkT > 0.0 and z.gawkT < GAWK and z.gawkAt != null and hj != null:
		var want := angDiff(yawTo(z.gawkAt.x - z.pos.x, z.gawkAt.z - z.pos.z), z.yaw)
		var w := sin(clamp01(z.gawkT / GAWK) * PI)
		hj.rotation.y += clampf(want, -1.1, 1.1) * minf(1.0, w * 2.0)
		hj.rotation.x -= 0.12 * w
	if z.anim.down and lure != null and z.lured and hj != null:
		hj.rotation.z += sin(game.time.now * 3.0 + z.id) * 0.18

# --- LOD (after the camera moved) ----------------------------------------------------------------------
func _lod() -> void:
	var g = game
	var cam: Camera3D = g.camera
	if cam == null or not cam.is_inside_tree():
		return
	_camPos = cam.global_position
	var frustum: Array = cam.get_frustum()
	var list := alive
	# Shadows: the SHADOW_MAX nearest visible zombies keep their body shadow; the rest rely on the blob.
	var order := _order
	order.clear()
	for z in list:
		z.camDist = z.pos.distance_to(_camPos)
		var c := Vector3(z.pos.x, z.pos.y + z.height * 0.5, z.pos.z)
		var r: float = z.height * 0.8
		var inside := true
		for pl in frustum:
			if (pl as Plane).distance_to(c) > r:
				inside = false
				break
		z.onScreen = inside
		z.lod = 0 if z.onScreen and z.camDist < ANIM_NEAR else 1
		if z.onScreen:
			order.append(z)
	order.sort_custom(func(a, b): return a.camDist < b.camDist)
	for z in list:
		var m = z.model
		var bodies = _f(m, "bodies") if m != null else null
		if bodies:
			var cast: bool = z.onScreen and _idx(order, z) < SHADOW_MAX
			for b in bodies:
				if is_instance_valid(b):
					b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cards = _f(m, "cards") if m != null else null
		if cards is Array and cards.size() > 0:
			var vis: bool = z.camDist < CARD_LOD
			for c in cards:
				if is_instance_valid(c):
					c.visible = vis
		var det = _f(m, "details") if m != null else null
		if det is Array and det.size() > 0:
			var vis: bool = z.camDist < DETAIL_LOD or _oneTake      # ONE TAKE stars live on the veil
			for c in det:
				if is_instance_valid(c):
					c.visible = vis
	order.clear()

# ------------------------------------------------------------------------------------------------ damage
func damage(z, amount, info: Dictionary = {}) -> bool:
	var g = game
	# boss.gd's wonder adapter (the JS wrapped this method while the Baron fight runs): the boss proxy goes to him.
	if _damageHook.is_valid():
		var hr = _damageHook.call(z, amount, info)
		if hr != null:
			return _t(hr)
	if z == null or z.dead or z.removed or not (float(amount) > 0.0):
		return false
	if _zn != null and _zn.client and not _zn.applying:
		return _zn.predict(z, amount, info)     # MP client: local feedback + request (zombies_net.gd)
	# MP: the attacker (peer id) that gets the points; host-local damage defaults to the host's own player.
	var by = info.get("by")
	if _zn != null:
		if by == null:
			by = net.localId
		z["lastHitBy"] = by
	var frame: int = g.time.frame
	var zone = info.get("zone")
	var head = info.get("head")
	var mul := 1.0
	var zoneMul = null
	if zone == null and z._rayFrame == frame:
		zone = z._rayZone
		zoneMul = z._rayMul
		if head == null:
			head = z._rayHead
	if head == null:
		head = zone == "head"
	head = _t(head)
	if zone == null:
		zone = "head" if head else "torso"
	if zoneMul == null:
		zoneMul = 0.8 if zone == "limb" else _zoneMul(z, zone)
	mul *= float(zoneMul)
	if z.state == "screen" and z.entry != null and z.entry.get("inGlass"):
		mul *= float(_Z().screenMul)
	var dmg: float = float(amount) * mul
	var full := info.duplicate()
	full.head = head
	full.zone = zone
	if z.def.get("onDamage") is Callable:
		var r = z.def.onDamage.call(g, z, dmg, full)
		if (r is float or r is int) and is_finite(float(r)):
			dmg = float(r)
	if _oneTake and z.type != "boss_baron":
		if z.def.get("oneTakeMul"):
			dmg *= float(z.def.oneTakeMul)
		else:
			dmg = maxf(dmg, z.hp)
	if not (dmg > 0.0):
		return false
	z.hp -= dmg
	var killed: bool = z.hp <= 0.0
	var weaponId = info.get("weaponId")
	var cause = info.get("cause")
	if not cause:
		cause = "melee" if weaponId == "melee" else "bullet"

	# Reaction: squash + head spring, lean back, 0.15 s stagger, shove.
	if not killed:
		z.anim.hurt = 1.0
		z.stagger = maxf(z.stagger, STAGGER)
		_kick(z, minf(1.2, 0.45 + dmg / maxf(60.0, z.maxHp) * 1.5))
	var idir = info.get("dir")
	if info.get("knockback") and idir != null:
		var kb: float = minf(3.0, float(info.knockback)) * (0.25 if z.type == "big_shot" else 1.0)
		z.knock.x += idir.x * kb * 9.0
		z.knock.z += idir.z * kb * 9.0
	# Hit FX: confetti + felt fluff (never blood).
	var ipoint = info.get("point")
	if ipoint != null and z._fxFrame != frame:
		z._fxFrame = frame
		var bo := {"shape": "confetti", "count": 5, "speed": 3, "size": 0.055, "cone": 1.3, "life": 0.9}
		if idir != null:
			bo.dir = -DAU.v3(idir)
		_burst(ipoint, bo)
		_burst(ipoint, {"shape": "puff", "count": 2, "size": 0.09, "life": 0.45, "speed": 1.2, "colors": ["#E4F2E6", "#F4F1E8"]})
	if not killed and _hitSfx < 2:
		_hitSfx += 1
		_play("zmb_hit", {"pos": ipoint if ipoint != null else z.pos, "rate": 0.9 + randf() * 0.25})

	var hev := {"z": z, "dmg": dmg, "head": head, "weaponId": weaponId, "point": ipoint if ipoint != null else z.pos,
		"zone": zone, "cause": cause, "upgraded": _t(info.get("upgraded", false))}
	if _zn != null:
		hev.by = by
		for k in ["signal", "primary", "ghost", "shot"]:
			if info.has(k):
				hev[k] = info[k]
		_zn.outHit(z, dmg, head, zone, ipoint, idir, cause, weaponId, by, killed, info)
	g.events.emit("zombie:hit", hev)
	# Points (GDD §6.3).
	if info.get("points") != false and not NO_POINTS.has(cause):
		if not killed:
			var key := "%d|%s" % [frame, weaponId]
			if _zn != null:
				var shot = info.get("shot")
				key = "%s|%s|%s" % [str(by), str(shot if shot != null else frame), weaponId]
			if z._hitKey != key:
				z._hitKey = key
				_addPoints(_P().hit, "hit", by)
	if info.get("hitmarker") != false and g.hud != null and g.hud.has_method("hitmarker") and z._hmFrame != frame \
			and (_zn == null or by == net.localId):
		z._hmFrame = frame
		g.hud.hitmarker(head, killed)
	if killed:
		full.weaponId = weaponId
		full.cause = cause
		if _zn != null:
			full.by = by
		_kill(z, full, info.get("points") != false)
	return killed

func _zoneMul(z: Dictionary, zone) -> float:
	if z.hitZones == null:
		return 1.0
	for hz in z.hitZones:
		if hz.get("zone") == zone:
			return float(hz.mul) if hz.get("mul") != null else 1.0
	return 1.0

func kill(z, info: Dictionary = {}) -> bool:
	if z == null or z.dead or z.removed:
		return false
	if _zn != null and _zn.client and not _zn.applying:
		return false                    # MP client: only the host kills
	var full := {"cause": "script"}
	full.merge(info, true)
	_kill(z, full, info.get("points") != false)
	return true

func _kill(z: Dictionary, info: Dictionary, award: bool) -> void:
	var g = game
	var cause = info.get("cause")
	if not cause:
		cause = "bullet"
	var head := _t(info.get("head", false))
	var melee: bool = cause == "melee" or info.get("weaponId") == "melee"
	z.hp = 0.0
	z.dead = true
	z.state = "dying"
	z.dieT = 0.0
	z.anim.attack = 0.0
	z.anim.climb = 0.0
	z.anim.down = false
	z.anim.hurt = 0.6
	var i := _idx(alive, z)
	if i >= 0:
		alive.remove_at(i)
	dying.append(z)
	_leaveEntry(z)
	if z.blob != null:
		_hcall(z.blob, "remove")
		z.blob = null
	if _stars != null:
		_stars.remove(z)
	var by = info.get("by")
	if award and (_zn == null or not _zn.client):
		var pts := killPoints(cause, head, info.get("weaponId"))
		if pts > 0:
			_addPoints(pts, "kill", by)
			var pd = z.def.get("points")
			var bonus = pd.get("killBonus") if pd is Dictionary else null
			if bonus:
				_addPoints(bonus, "kill_bonus", by)
	# Custom death (specials) or the default topple. info.corpse === false: another system (wonder weapons) animates
	# a clone of the body, so no death visuals here (the type's onDeath still runs for its side effects).
	var corpse: bool = info.get("corpse") != false
	var dur = null
	if z.def.get("onDeath") is Callable:
		dur = z.def.onDeath.call(g, z, info)
	var inTele: bool = z.entry != null and z.entry.get("kind") == "screen" and z.entry.get("phase") == "tele"
	var idir = info.get("dir")
	if not corpse:
		z.deathDur = 0.0
	elif (dur is float or dur is int) and dur >= 0:
		z.deathDur = float(dur)
	elif inTele:
		# Killed inside the screen during the telegraph: it fizzles out in the glass.
		z.deathDur = 0.0
		if z.entry.tele != null:
			_hcall(z.entry.tele, "cancel")
		var sp: Vector3 = z.entry.ss.pos
		_burst(sp, {"shape": "static", "count": 24, "speed": 2.2})
		_burst(sp, {"shape": "confetti", "count": 10, "colors": Config.BARS})
		_play("zmb_death_static", {"pos": sp, "tv": true})
	else:
		z.deathDur = null
		z.dieDir = Vector3(idir.x, 0, idir.z).normalized() if idir != null else Vector3(sin(z.yaw), 0, cos(z.yaw))
		# Topple backward = away from the shooter: turn the body most of the way toward the shot.
		if idir != null:
			z.yaw += angDiff(yawTo(-idir.x, -idir.z), z.yaw) * 0.6
		z.vy = 0.0
		if head and cause != "cancelled":
			_popHead(z, _zn == null or by == null or by == net.localId)
		_burst(z.pos + Vector3(0, z.height * 0.75, 0), {"shape": "confetti", "count": 10, "speed": 3.5})
		if z.group.visible and _stars != null:
			_stars.add(z, DIE_LIE + 0.1, 3, 0.24 * z.scale)
		_play("zmb_head_pop" if head else "zmb_groan", {"pos": z.pos, "rate": 1.0 if head else 0.7, "vol": 1.0 if head else 0.7})
	var kev := {"z": z, "weaponId": info.get("weaponId"), "head": head, "melee": melee, "pos": z.pos, "cause": cause}
	if _zn != null:
		kev.by = by
		kev.wfx = info.get("wfx")
		z["killBy"] = by
	g.events.emit("zombie:kill", kev)
	if _zn != null and _zn.client:
		return                          # MP client: the round bookkeeping is the host's
	if g.rounds != null and g.rounds.has_method("onZombieKilled"):
		g.rounds.onZombieKilled(z)
	if _zn != null:
		_zn.outKill(z, info, by)

func _leaveEntry(z: Dictionary) -> void:
	if z.entry == null or z.entry.get("kind") == "screen":
		return
	var q = _entries.get(z.entry.id)
	if q == null:
		return
	if is_same(q.front, z):
		q.front = q.waiting.pop_front() if q.waiting.size() > 0 else null
		if q.front != null and q.front.state == "queue":
			q.front.state = "approach"
	else:
		var k: int = _idx(q.waiting, z)
		if k >= 0:
			q.waiting.remove_at(k)

func _updateDying(dt: float) -> void:
	var g = game
	for i in range(dying.size() - 1, -1, -1):
		if i >= dying.size():
			continue
		var z: Dictionary = dying[i]
		z.dieT += dt
		if z.deathDur != null:
			if z.def.get("updateDeath") is Callable:
				z.def.updateDeath.call(g, z, dt, z.dieT)
			if z.dieT >= z.deathDur:
				dying.remove_at(i)
				_remove(z)
			continue
		var t: float = z.dieT
		# Topple backward with a bounce, sliding a little with the hit.
		z.anim.dead = minf(1.0, t / DIE_TOPPLE)
		z.anim.speed = 0.0
		z.anim.hurt = maxf(0.0, z.anim.hurt - dt / 0.3)
		if t < 0.3 and z.dieDir != null:
			var delta: Vector3 = z.dieDir * ((0.3 - t) * 2.2 * dt)
			delta.y = 0.0
			_moveCircle(z, delta, z.radius * 0.6, 0.5, 0.45)
		# Died mid-air (vault, fence, screen): fall to the floor below.
		var fy := _floorAt(z.pos.x, z.pos.z, z.pos.y + 0.1)
		if fy > -INF and z.pos.y > fy + 0.01:
			z.vy -= GRAVITY * dt
			z.pos.y = maxf(fy, z.pos.y + z.vy * dt)
			if z.pos.y <= fy:
				_kick(z, 0.8)
		else:
			z.vy = 0.0
		if z.animator != null:
			z.animator.update(dt, z.anim)
		var s: float = z.scale
		if t > DIE_LIE:
			var k := clamp01((t - DIE_LIE) / DIE_POP)
			s *= 1.0 - smooth(k)
			if not z.dissolved:
				_dissolve(z)
		var G: Node3D = z.group
		G.position = z.pos
		G.rotation_order = EULER_ORDER_YXZ
		G.rotation = Vector3(0, z.yaw, 0)
		var wide := 1.0 + (0.3 if t > DIE_LIE else 0.0)
		G.scale = Vector3(s * wide, maxf(0.001, s), s * wide)
		if t >= DIE_LIE + DIE_POP:
			dying.remove_at(i)
			_remove(z)

# 30 static quads + 12 colour-bar confetti; the ticket stub flutters down.
func _dissolve(z: Dictionary) -> void:
	z.dissolved = true
	if not z.group.visible:
		return
	var a: Vector3 = z.pos + Vector3(0, 0.35, 0)
	_burst(a, {"shape": "static", "count": 30, "speed": 2.4, "size": 0.1, "life": 0.9})
	_burst(a, {"shape": "confetti", "count": 12, "colors": Config.BARS, "speed": 3.2})
	_play("zmb_death_static", {"pos": z.pos})
	if z.type == "tuned_in" and _tickets != null:
		var b: Vector3 = z.pos + Vector3(0, 0.55, 0)
		var fy := _floorAt(z.pos.x, z.pos.z, z.pos.y + 0.5)
		_tickets.add(b, fy if fy > -INF else z.pos.y)

func _remove(z: Dictionary) -> void:
	if z.removed:
		return
	z.removed = true
	if is_same(_byId.get(z.id), z):
		_byId.erase(z.id)
	var g = game
	_leaveEntry(z)
	if z.entry != null and z.entry.get("kind") == "screen" and z.entry.get("phase") == "tele" and z.entry.get("tele") != null:
		_hcall(z.entry.tele, "cancel")
	if z.blob != null:
		_hcall(z.blob, "remove")
		z.blob = null
	if _stars != null:
		_stars.remove(z)
	if z.def.get("release") is Callable:
		z.def.release.call(g, z)
	elif z.model is Dictionary and z.model.get("group") != null:
		ZombieTypes.releaseModel(z.model)
	if z.group != null:
		DAU.detach(z.group)

# --- head cork-pop -------------------------------------------------------------------------------------
func _headProxy(variant):
	var list = _heads.get(variant)
	while list != null and list.size() > 0:
		var h = list.pop_back()
		if int(h.model.get("gen", 0)) == ZombieTypes.modelGen():
			return h
	return _buildHead(variant)

func _buildHead(variant):
	var g = game
	var m = ZombieTypes.buildVariant(g, "tuned_in", variant)
	if m == null:
		return null
	var J = _f(m.rig, "joints")
	if J == null or _f(J, "neck") == null:
		return null
	# Collapse everything but the head: hips ~0, neck ×1/ε restores the head at full size.
	var EPS := 1e-3
	J.hips.scale = Vector3(EPS, EPS, EPS)
	J.neck.scale = Vector3(1.0 / EPS, 1.0 / EPS, 1.0 / EPS)
	for c in m.get("cards", []):
		c.visible = false
	for b in m.get("bodies", []):
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	DAU.traverse(m.group, func(o):
		if o is GeometryInstance3D:
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			o.extra_cull_margin = 16384.0)          # frustumCulled = false
	var pivot := DAU.node3d("zombie_poppedHead")
	pivot.add_child(m.group)
	var hc := _worldPos(m.head)
	m.group.position -= hc
	DAU.setLayerRecursive(pivot, Config.LAYERS.ZOMBIES)
	return {"pivot": pivot, "model": m, "variant": variant, "vel": Vector3.ZERO, "spin": Vector3.ZERO, "t": 0.0, "bounces": 0,
		"floor": 0.0, "r": 0.25, "baseS": 0.0, "endT": 0.0}

func _prewarmHeads(variant, n: int) -> void:
	var list = _heads.get(variant)
	if list == null:
		list = []
		_heads[variant] = list
	for i in range(list.size() - 1, -1, -1):
		if int(list[i].model.get("gen", 0)) != ZombieTypes.modelGen():
			list.remove_at(i)
	while list.size() < n:
		var h = _buildHead(variant)
		if h == null:
			break
		list.append(h)

func _releaseHead(h: Dictionary) -> void:
	DAU.detach(h.pivot)
	var list = _heads.get(h.variant)
	if list == null:
		list = []
		_heads[h.variant] = list
	if list.size() < 4 and int(h.model.get("gen", 0)) == ZombieTypes.modelGen():
		list.append(h)

# local: the kill is the local player's (MP: only the killer feels the 30 ms hit-stop).
func _popHead(z: Dictionary, local := true) -> void:
	var g = game
	var J = _f(z.rig, "joints")
	if J == null or _f(J, "head") == null or z.model == null:
		var a0: Vector3 = _worldPos(z.head) if z.head != null else z.pos
		_burst(a0, {"shape": "static", "count": 14})
		if local:
			g.hitStop(0.03)
		return
	var a := _worldPos(z.head)
	var q := _world(J.head).basis.get_rotation_quaternion()
	J.head.scale = Vector3(0.001, 0.001, 0.001)
	if local:
		g.hitStop(0.03)
	_burst(a, {"shape": "static", "count": 12, "speed": 2, "size": 0.07})
	_burst(a, {"shape": "star", "count": 5, "speed": 3})
	var variant = _f(z.model, "variant")
	var h = _headProxy(variant) if variant else null
	if h == null:
		return
	h.pivot.position = a
	h.pivot.quaternion = q
	h.pivot.scale = Vector3(z.scale, z.scale, z.scale)
	var back: Vector3 = z.dieDir if z.dieDir != null else Vector3(0, 0, 1)
	h.vel = Vector3(back.x * 1.6 + (randf() - 0.5), 5.2 + randf() * 1.2, back.z * 1.6 + (randf() - 0.5))
	h.spin = Vector3(-6.0 - randf() * 6.0, (randf() - 0.5) * 8.0, (randf() - 0.5) * 6.0)
	h.t = 0.0
	h.bounces = 0
	h.floor = _floorAt(a.x, a.z, a.y)
	if not (h.floor > -INF):
		h.floor = z.pos.y
	h.r = z.headR * z.scale
	_sceneRoot().add_child(h.pivot)
	_flying.append(h)

func _updateHeads(dt: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var h: Dictionary = _flying[i]
		h.t += dt
		var pv: Node3D = h.pivot
		h.vel.y -= 18.0 * dt
		pv.position += h.vel * dt
		pv.quaternion = pv.quaternion * _quatXYZ(h.spin * dt)
		var fy: float = h.floor + h.r * 0.9
		if pv.position.y < fy and h.vel.y < 0.0:
			pv.position.y = fy
			h.bounces += 1
			h.vel.y = -h.vel.y * 0.45
			h.vel.x *= 0.6
			h.vel.z *= 0.6
			h.spin *= 0.55
			pv.scale *= Vector3(1.15, 0.8, 1.15)
			_play("zmb_hit", {"pos": pv.position, "rate": 1.5 + h.bounces * 0.2, "vol": 0.6})
		# Squash recovers.
		var target := 1.0
		if pv.scale.x > 0.0:
			if not h.baseS:
				h.baseS = pv.scale.y
			target = h.baseS
		pv.scale = pv.scale.lerp(Vector3(target, target, target), minf(1.0, dt * 10.0))
		if h.bounces >= 2 and not h.endT:
			h.endT = h.t + 0.18
		if (h.endT and h.t >= h.endT) or h.t > 2.2:
			var P0 := pv.position
			_burst(P0, {"shape": "static", "count": 18, "speed": 1.8, "size": 0.09})
			_burst(P0, {"shape": "puff", "count": 4, "size": 0.14, "colors": ["#DDE3EA", "#F4F1E8"]})
			_play("zmb_death_static", {"pos": P0, "vol": 0.6})
			_flying.remove_at(i)
			h.baseS = 0.0
			h.endT = 0.0
			_releaseHead(h)

# ------------------------------------------------------------------------------------------------ queries
func raycast(origin: Vector3, dir: Vector3, maxDist := 80.0):
	var frame: int = game.time.frame
	var best = null
	var bestInfo = null
	var bd := maxDist
	for z in alive:
		if z.removed:
			continue
		if z.state == "screen" and z.entry != null and z.entry.get("phase") == "tele":
			var t := raySphere(origin, dir, z.entry.ss.pos, 0.42)
			if t <= bd:
				bd = t
				best = z
				bestInfo = {"zone": "torso", "head": false, "mul": 1.0}
			continue
		var c := Vector3(z.pos.x, z.pos.y + z.height * z.scale * 0.5, z.pos.z)
		var R: float = z.height * z.scale * 0.62 + 0.35
		if raySphere(origin, dir, c, R) > bd:
			continue
		var h = _rayZombie(z, origin, dir, bd)
		if h != null and float(h.dist) <= bd:
			bd = float(h.dist)
			best = z
			bestInfo = {"zone": h.get("zone"), "head": _t(h.get("head", false)), "mul": h.get("mul", 1.0)}
	var res = null
	if best != null:
		best._rayFrame = frame
		best._rayZone = bestInfo.zone
		best._rayHead = bestInfo.head
		best._rayMul = bestInfo.mul
		res = {"z": best, "head": bestInfo.head, "dist": bd, "point": origin + dir * bd, "zone": bestInfo.zone}
	# boss.gd's wonder adapter (the JS wrapped this method while the Baron fight runs): may return his proxy's hit.
	if _raycastHook.is_valid():
		return _raycastHook.call(origin, dir, maxDist, res)
	return res

func _rayZombie(z: Dictionary, o: Vector3, d: Vector3, maxD: float):
	if z.hitTest is Callable and z.hitTest.is_valid():
		return z.hitTest.call(o, d, maxD)
	var zones = z.hitZones
	var bt := INF
	var be := INF
	var bz = null
	if zones == null:
		var hc := _worldPos(z.head)
		var th := raySphere(o, d, hc, z.headR)
		var a: Vector3 = z.pos + Vector3(0, 0.25, 0)
		var b: Vector3 = z.pos + Vector3(0, z.height - z.headR * 2.0, 0)
		var tb := rayCapsule(o, d, a, b, z.radius * 0.75)
		if th == INF and tb == INF:
			return null
		var isHead := th <= tb
		return {"dist": minf(th, tb), "head": isHead, "zone": "head" if isHead else "torso", "mul": 1.0}
	for hz in zones:
		var bone = hz.get("bone")
		if bone == null or not is_instance_valid(bone):
			continue
		var off = hz.get("offset")
		var a: Vector3 = _world(bone) * (DAU.v3(off) if off != null else Vector3.ZERO)
		var t: float
		var r: float = float(hz.r) * z.scale
		if hz.get("shape") == "capsule":
			var o2 = hz.get("offset2")
			var b2 = hz.get("bone2")
			var bn: Node3D = b2 if b2 != null else bone
			var b: Vector3 = _world(bn) * (DAU.v3(o2) if o2 != null else Vector3.ZERO)
			t = rayCapsule(o, d, a, b, r)
		else:
			t = raySphere(o, d, a, r)
		# Head wins near-ties (the head sphere overlaps the neck end of the torso).
		var te := t - 0.06 if hz.get("head") else t
		if te < be:
			be = te
			bt = t
			bz = hz
	if bz == null or bt > maxD:
		return null
	return {"dist": bt, "zone": bz.get("zone"), "head": _t(bz.get("head", false)), "mul": bz.mul if bz.get("mul") != null else 1.0}

func inRadius(pos: Vector3, r: float, out: Array = []) -> Array:
	out.clear()
	for z in alive:
		if z.removed:
			continue
		var y0: float = z.pos.y
		var y1: float = z.pos.y + z.height * z.scale
		var dy := y0 - pos.y if pos.y < y0 else (pos.y - y1 if pos.y > y1 else 0.0)
		var dx: float = pos.x - z.pos.x
		var dz: float = pos.z - z.pos.z
		var d: float = sqrt(dx * dx + dz * dz + dy * dy) - z.radius * 0.5
		if d <= r:
			out.append(z)
	return out

func nearest(pos: Vector3, maxDist := INF):
	var best = null
	var bd := maxDist
	for z in alive:
		var d: float = z.pos.distance_to(pos)
		if d < bd:
			bd = d
			best = z
	return best

func count(typeId = null) -> int:
	if not typeId:
		return alive.size()
	var n := 0
	for z in alive:
		if z.type == typeId:
			n += 1
	return n

# Living zombies spawned by the round with this token.
func roundAlive(token) -> int:
	var n := 0
	for z in alive:
		if z.fromRound == token:
			n += 1
	return n

# ------------------------------------------------------------------------------------------------ control
func killAll(cause = "cancelled") -> void:
	if _zn != null and _zn.client:
		return
	for z in alive.duplicate():
		if z.type != "boss_baron":
			_kill(z, {"cause": cause}, false)

func stun(z, seconds: float) -> void:
	if z == null or z.dead:
		return
	if _zn != null and _zn.client and not _zn.applying:
		_zn.request("stunReq", [int(z.id), float(seconds)])
		return
	if _zn != null:
		_zn.outStun(z, seconds)
	z.stun = maxf(z.stun, seconds)
	if z.state == "attack":
		z.state = "chase"
		z.anim.attack = 0.0
	if seconds > 0.4 and (z.state == "chase" or z.state == "attack") and _stars != null:
		_stars.add(z, seconds, 3, 0.22 * z.scale)

func stunAll(seconds: float) -> void:
	for z in alive:
		stun(z, seconds)

func knockback(z, vec) -> void:
	if z == null or z.dead:
		return
	if _zn != null and _zn.client:
		_zn.request("knockReq", [int(z.id), DAU.v3(vec)])
		return
	z.knock.x += vec.x * 9.0
	z.knock.z += vec.z * 9.0

func freezeAll(on) -> void:
	frozen = _t(on)
	if _zn != null and not _zn.client:
		_zn.outFreeze(frozen)           # MP: clients get the look (a client call only sets its local flag)

# setLure(pos|null, radius = INF): radius = PATH distance (metres) inside which zombies are lured (Tiny Tele 15);
# INF keeps the old behaviour (every zombie, via nav.setGoalOverride).
func setLure(pos, radius := INF) -> void:
	if _zn != null and _zn.client and not _zn.applying:
		_zn.request("lureReq", [DAU.v3(pos) if pos != null else Vector3.ZERO, pos != null, float(radius) if is_finite(radius) else -1.0])
		return
	lure = DAU.v3(pos) if pos != null else null
	lureR = radius
	_lureField = null
	var nav = game.nav
	if lure != null and is_finite(radius) and nav != null and nav.has_method("localField"):
		nav.setGoalOverride(null)
		_lureField = nav.localField(lure.x, lure.z, radius)
		for z in alive:
			z.lured = _lfDist(z.pos.x, z.pos.z) <= radius
	else:
		if nav != null:
			nav.setGoalOverride(lure)
		for z in alive:
			z.lured = lure != null
	if lure == null:
		for z in alive:
			z.anim.down = false
			z.lured = false
	if _zn != null and not _zn.client:
		_zn.outLure(lure, lureR)

# Silent removal: no points, no kill event. requeue = the round spawns it again (anti-stuck).
func despawn(z, requeue := true) -> void:
	if z == null or z.removed:
		return
	if _zn != null and _zn.client and not _zn.applying:
		return                          # MP client: only the host despawns
	var g = game
	if _zn != null and not _zn.client:
		_zn.outDespawn(z, _despawnFx)
	var i := _idx(alive, z)
	if i >= 0:
		alive.remove_at(i)
	var j := _idx(dying, z)
	if j >= 0:
		dying.remove_at(j)
	z.dead = true
	_remove(z)
	g.events.emit("zombie:despawn", {"z": z})
	if requeue and z.fromRound != null and g.rounds != null and g.rounds.has_method("requeue"):
		g.rounds.requeue(z)

# Everything dissolves into static without points (boss intro, game scripts).
func despawnAll(opts: Dictionary = {}) -> void:
	var fx: bool = opts.get("fx", true)
	var requeue: bool = opts.get("requeue", false)
	if _zn != null and _zn.client:
		return
	for z in alive.duplicate():
		if fx and z.group.visible:
			_burst(z.pos + Vector3(0, 0.8, 0), {"shape": "static", "count": 16, "speed": 2})
		_despawnFx = fx
		despawn(z, requeue)
		_despawnFx = false

# Sign-On (GDD §7.8): living zombies stop and turn their heads toward the nearest TV for 1.5 s as the wave passes.
func _signOnGawk() -> void:
	if _zn != null and _zn.client:
		return                          # MP: host only (the snapshot packer replicates gawks)
	var g = game
	var L = g.level
	if L == null:
		return
	var anc = _f(_f(L, "anchors"), "sign_on_lever")
	var lp = _f(anc, "pos") if anc != null else null
	var lever: Vector3 = lp if lp is Vector3 else LEVER
	var ssd = _f(L, "screenSpawns", {})
	var screens: Array = ssd.values() if ssd is Dictionary else []
	for z in alive:
		if z.state != "chase":
			continue
		var delay := maxf(0.0, z.pos.distance_to(lever) / 15.0 - 2.6)
		z.gawkT = GAWK + minf(2.5, delay)
		var best = null
		var bd := INF
		for s in screens:
			var d: float = s.pos.distance_to(z.pos)
			if d < bd:
				bd = d
				best = s.pos
		z.gawkAt = best if best != null else lever

# ------------------------------------------------------------------------------------------------ port glue
func _sceneRoot() -> Node:
	return game.scene if game.scene != null else game

func _col():
	var L = game.level
	return _f(L, "col") if L != null else null

# level.col.moveCircle: see the port notes (result Dictionary, the moved feet in "pos", stored back into owner.pos).
# owner = the object whose pos the JS passed (z / the player): collision.gd remembers "grounded" on it.
func _moveCircle(owner, delta: Vector3, radius: float, height: float, stepUp := 0.45) -> Dictionary:
	var col = _col()
	if col == null:
		owner.pos = owner.pos + delta
		return {"onGround": false}
	var r = col.moveCircle(owner.pos, delta, radius, height, stepUp, null, owner)
	if r is Dictionary:
		if r.has("pos"):
			owner.pos = r.pos
		return r
	if r is Vector3:
		owner.pos = r
	return {"onGround": false}

func _floorAt(x: float, zz: float, yFrom: float) -> float:
	var col = _col()
	if col == null:
		return -INF
	var fy = col.floorAt(x, zz, yFrom)
	return float(fy) if fy != null else -INF

func _los(a: Vector3, b: Vector3) -> bool:
	var col = _col()
	if col == null or not col.has_method("lineOfSight"):
		return true
	return _t(col.lineOfSight(a, b))

func _navDir(x: float, zz: float) -> Vector3:
	var nav = game.nav
	if nav == null:
		return Vector3.ZERO
	var r = nav.dir(x, zz)
	return r if r is Vector3 else Vector3.ZERO

func _navDist(x: float, zz: float) -> float:
	var nav = game.nav
	if nav == null:
		return INF
	return float(nav.dist(x, zz))

# nav.localField() -> { dist(x, z), dir(x, z) } (Callables in a Dictionary, or an object with those methods).
func _lfDist(x: float, zz: float) -> float:
	var r = _hcall(_lureField, "dist", [x, zz])
	return float(r) if r != null else INF

func _lfDir(x: float, zz: float) -> Vector3:
	var r = _hcall(_lureField, "dir", [x, zz])
	return r if r is Vector3 else Vector3.ZERO

func _kick(z: Dictionary, amount: float) -> void:
	var a = z.animator
	if a is Object and a.has_method("kick"):
		a.kick(amount)

func _burst(pos: Vector3, opts: Dictionary) -> void:
	var fx = game.fx
	if fx != null:
		fx.burst(pos, opts)

func _play(id: String, opts: Dictionary = {}) -> void:
	var a = game.audio
	if a != null:
		a.play(id, opts)

func _addPoints(n, reason: String, by = null) -> void:
	var e = game.economy
	if e == null:
		return
	if _zn != null:
		_zn.award(e, n, reason, by)     # MP host: economy.add(n, reason, by) routes to the attacker
		return
	e.add(n, reason)

# ------------------------------------------------------------------------------------------------ MP API
# (see the MP paragraph in the header; the work happens in zombies_net.gd, these are thin wrappers)
func byId(id):
	return _byId.get(int(id)) if (id is int or id is float) else null

# The player-like this zombie chases: game.player in solo; MP host z.tgt; MP client the snapshot's target.
func targetOf(z):
	if _zn == null:
		return game.player
	return _zn.targetOf(z) if z != null else null

# The players zombies may chase this frame (solo: [game.player]). Shared array: read only.
func targetsList() -> Array:
	if _zn == null:
		return [game.player]
	return _zn.targetsList()

func isRemote(p) -> bool:
	return p != null and p is Object and p.get("isRemote") == true

# May this peer decide zombie outcomes (solo / MP host)?
func authority() -> bool:
	return _zn == null or not _zn.client

func isPuppet() -> bool:
	return _zn != null and _zn.client

# MP host: a contact hit on a RemotePlayer, applied on its owner's peer (zombies.net_hurt). Returns false when it
# cannot land (host view). Solo / local player: the solo call pattern.
func hurtTarget(p, dmg, z, kb = null, kind := "") -> bool:
	if p == null:
		return false
	if _zn != null and isRemote(p):
		return _zn.hurtRemote(p, dmg, z, kb, kind)
	if p.hurt(dmg, z.pos):
		var ev := {"z": z, "dmg": dmg}
		if kind != "":
			ev.kind = kind
		game.events.emit("zombie:attack", ev)
		if kb is Vector3 and p.has_method("knockback"):
			p.knockback(kb)
		return true
	return false

# MP host: a type-specific event for the puppets (def.puppetEvent(game, z, kind, args) on every client).
func netEvent(z, kind: String, args: Array = []) -> void:
	if _zn != null and not _zn.client and z != null:
		_zn.outType(z, kind, args)

# --- net handlers (game.net dispatch: zombies.net_<method>)
func net_ev(t, list) -> void:
	if _zn != null and _zn.client and net.sender == 1:
		_zn.onEvents(t, list)

func net_stream_z(_from, data) -> void:
	if _zn != null and _zn.client and data is PackedByteArray:
		_zn.onSnapshot(data)

func net_dmgBatch(list) -> void:
	if _zn != null and not _zn.client:
		_zn.onDmgBatch(list)

func net_hurt(dmg, fromPos = null, kb = null, zid = 0, kind = "") -> void:
	if _zn != null and net.sender == 1:
		_zn.onHurt(dmg, fromPos, kb, zid, kind)

func net_stunReq(id, seconds) -> void:
	if _zn != null and not _zn.client and (seconds is float or seconds is int):
		var z = byId(id)
		if z != null and not z.dead:
			stun(z, clampf(float(seconds), 0.0, 10.0))

func net_knockReq(id, vec) -> void:
	if _zn != null and not _zn.client and vec is Vector3:
		var z = byId(id)
		if z != null and not z.dead:
			knockback(z, vec.limit_length(8.0))

func net_lureReq(pos, on = true, radius = -1.0) -> void:
	if _zn != null and not _zn.client and pos is Vector3 and (radius is float or radius is int):
		setLure(pos if on else null, float(radius) if float(radius) >= 0.0 else INF)
