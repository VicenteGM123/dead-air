# Player controller (port of src/actors/player.js; ARCHITECTURE §9/§12, GDD §6.2/§16): movement, health, stamina,
# hero model & animation.
#
# Fields: pos (feet), vel, yaw, pitch, radius, height, health, maxHealth, alive, downed, heroId, hero (buildHero
#   result), rig, animator, model, sprinting, ads, grounded, area, stamina, god, invulnerable (external: set by
#   commercials / Instant Replay), controlLocked (no look/move input: debug cameras, cutscenes), mods (perks &
#   power-ups write these; read every frame), anim (animator state: weapons write recoil/reload/melee 0..1),
#   history (4 s ring buffer, 0.1 s samples: get_(i), at(secondsAgo)).
# Methods: setHero(id), setWeaponModel(node|null) (attached to hero slots.handR), hurt(dmg, fromPos) -> bool,
#   heal(n), knockback(vec), down(), revive(selfRevive), aimRay() -> {origin, dir}, muzzle() -> Vector3,
#   forward() -> Vector3, teleport(x, z, yaw?).
#   (GDScript: THREE's out-parameter methods return their values instead — Vector3 is a value type, SPEC §3.3.
#   aimRay(outOrigin, outDir) -> Dictionary {origin, dir}; muzzle(out) / forward(out) -> Vector3; the optional
#   arguments are accepted and ignored.)
# setHero: placeholder heroes were merged into one rigid-skinned mesh per material in the JS (geo.skinRig: a
# draw-call budget); that merge is engine plumbing and is not ported (SPEC §0.2). Baked heroes were never merged.
# Lethal damage asks game.perks.onLethal() first (true = handled, e.g. Instant Replay), else game.gameOver().
# Also owns render.post.damage (GDD §14 "signal loss" = 1 - HP/max, eased).
# Movement uses world dt (frozen at time.scale 0); look, the hero animation and the model use real dt.
# Move input comes from input.move() (keyboard digital axes or the gamepad's analog left stick: a light push walks
# slower, sprint is always full speed); look adds input.lookDelta().snapYaw/snapPitch (pad aim assist) unscaled.
# Sounds: player:step {foot, sprint, surface} / jump / land / hurt are voiced by audio.gd's event hookups.
# Renames (SPEC §3.2): History.get -> History.get_ (Object.get). The JS module scratch objects `_look` / `_move`
# (named like the methods) are the members `_lookBuf` / `_moveBuf`.
# MP (online co-op, MP_SPEC §4 + RECONCILE R6/R12; every MP path is guarded, solo runs the code above unchanged):
#   Fields: offAir (bled out: alive = false, model hidden, spectating), hidden (out of the shared world for a cutscene:
#   not targetable, model hidden for the others), inCommercial (performing a sponsor commercial: settable, also true
#   while sponsors.inCommercial), teleports (int, +1 on every teleport(): remote avatars snap instead of sliding),
#   spectate (the RemotePlayer followed while off-air, null otherwise: net.viewPlayer() reads it), mp (PlayerMP,
#   scripts/actors/player_mp.gd: down / revive / bleed-out / spectate / respawn + the host's team table; null in solo).
#   Keyed locks for MP cutscenes: lock(key, on) / protect(key, on); controlLocked / invulnerable read as "the plain
#   field (solo writers) OR any held key", so every reader (weapons, the net stream...) sees them. isLockKey(key).
#   netFlags() -> int (the state stream's flag byte: 1 alive, 2 downed, 4 offAir, 8 invulnerable (or god or grace),
#   16 hidden, 32 inCommercial, 64 ads, 128 sprinting).
#   Lethal damage in MP: perks.onLethal() first (Instant Replay), else mp.goDown() (downed, bleed-out; never
#   game.gameOver() from here). A downed player can look around (camera low) but not move / shoot / interact.
#   Messages (sys "player", handlers below, all validated): hurt (dmg, fromPos) / knockback (vec) from the host
#   (RemotePlayer forwarding); the life-cycle messages downReq / reviveStart / reviveStop / reviveDone (requests) and
#   downed / reviveState / revived / offAir / respawn (host broadcasts) are handled by PlayerMP (see its header).
extends RefCounted

const PlayerMPScript = preload("res://scripts/actors/player_mp.gd")

var P: Dictionary = Config.T.player
var JUMP_V: float = sqrt(2.0 * float(Config.T.player.gravity) * float(Config.T.player.jump))
const ACCEL := 42.0
const DECEL := 34.0
const AIR := 0.3
const STEP_UP := 0.45
const SPRINT_FWD := 0.35 # forward axis needed to sprint (keyboard W = 1; the stick may sprint ~70 deg off-axis)
const HEROES_PATH := "res://scripts/actors/heroes.gd"

static func wrapAngle(a: float) -> float:
	return atan2(sin(a), cos(a))

static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0 and not is_nan(float(v))
	if v is String or v is StringName:
		return v != ""
	return true

# o.k for a Dictionary or an Object (null when missing).
static func _g(o, k: String) -> Variant:
	if o is Dictionary:
		return o.get(k)
	if o is Object:
		return o.get(k)
	return null

# ARCHITECTURE §5: only meshes bigger than ~0.3 m cast shadows (eyes, lids, buttons would each add a shadow-pass
# draw call for nothing). Skinned bodies always cast. (receiveShadow = false is a material flag in Godot: the hero
# materials own it.)
static var _sphereCache := {}

static func setShadowCasting(root: Node, minRadius: float) -> void:
	var start: Transform3D = (root as Node3D).transform if root is Node3D else Transform3D.IDENTITY
	_shadowWalk(root, start, minRadius)

static func _shadowWalk(n: Node, world: Transform3D, minRadius: float) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.skin != null:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elif mi.mesh != null:
			var b := world.basis
			var scale := sqrt(maxf(b.x.length_squared(), maxf(b.y.length_squared(), b.z.length_squared())))
			var on := _boundingRadius(mi.mesh) * scale >= minRadius
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		if c is Node3D:
			_shadowWalk(c, world * (c as Node3D).transform, minRadius)
		else:
			_shadowWalk(c, world, minRadius)

# geometry.boundingSphere.radius (THREE: centre = bbox centre, radius = farthest vertex).
static func _boundingRadius(mesh: Mesh) -> float:
	var key := mesh.get_instance_id()
	if _sphereCache.has(key):
		return _sphereCache[key]
	var aabb := mesh.get_aabb()
	var c := aabb.get_center()
	var r2 := 0.0
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts = arr[Mesh.ARRAY_VERTEX] if arr.size() > Mesh.ARRAY_VERTEX else null
			if verts is PackedVector3Array:
				for v in verts:
					r2 = maxf(r2, (v - c).length_squared())
	else:
		r2 = (aabb.size * 0.5).length_squared()
	var r := sqrt(r2)
	_sphereCache[key] = r
	return r


# 4 s position ring buffer for Instant Replay (GDD §11: 40 samples every 0.1 s).
class History extends RefCounted:
	var n: int
	var step: float
	var samples: Array = []
	var head := -1
	var count := 0
	var _acc := 0.0

	func _init(n_: int = 40, step_: float = 0.1) -> void:
		n = n_
		step = step_
		for i in n:
			samples.append({"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "area": null})

	func clear() -> void:
		head = -1
		count = 0
		_acc = 0.0

	func push(pos: Vector3, yaw: float, area) -> void:
		head = (head + 1) % n
		var s: Dictionary = samples[head]
		s.x = pos.x
		s.y = pos.y
		s.z = pos.z
		s.yaw = yaw
		s.area = area
		count = mini(n, count + 1)

	func tick(dt: float, pos: Vector3, yaw: float, area) -> void:
		_acc += dt
		while _acc >= step:
			_acc -= step
			push(pos, yaw, area)

	# i-th newest sample (0 = newest) or null. (JS get: renamed, Object.get)
	func get_(i: int) -> Variant:
		if i < 0 or i >= count:
			return null
		return samples[(head - i + n) % n]

	# Sample about `seconds` ago (clamped to the oldest). Returns the sample ({x, y, z, yaw, area}; the JS also
	# copied its position into `out`: read sample.x/y/z instead).
	func at(seconds: float, _out = null) -> Variant:
		if count == 0:
			return null
		return get_(mini(count - 1, int(floorf(seconds / step + 0.5))))


var game
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var knock := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var radius := 0.38
var height := 1.75
var health: float = 150.0
var maxHealth: float = 150.0
var alive := true
var downed := false
var heroId = null
var hero = null
var rig = null
var animator = null
var model: Node3D
var sprinting := false
var ads := false
var grounded := true
var area = null
var stamina: float = 4.0
var god := false
# invulnerable / controlLocked: the plain values (solo writers: commercials, Instant Replay, the ending, debug cameras)
# OR any key held through protect() / lock() (MP cutscenes, RECONCILE R6).
var invulnerable: bool:
	get:
		return _invulnerable or not _protects.is_empty()
	set(v):
		_invulnerable = v
var controlLocked: bool:
	get:
		return _controlLocked or not _locks.is_empty()
	set(v):
		_controlLocked = v
var mods: Dictionary
# MP (see the header)
var offAir := false
var hidden := false
var inCommercial: bool:
	get:
		if _inCommercial:
			return true
		var s = game.get("sponsors") if game != null else null
		return s != null and s.get("inCommercial") == true
	set(v):
		_inCommercial = v
var teleports := 0
var spectate = null
var mp = null
var _invulnerable := false
var _controlLocked := false
var _inCommercial := false
var _locks := {}
var _protects := {}
var anim := {"speed": 0.0, "sprint": false, "grounded": true, "aimPitch": 0.0, "aimYaw": 0.0, "aiming": true, "recoil": 0.0,
	"reload": 0.0, "melee": 0.0, "hurt": 0.0, "climb": 0.0, "attack": 0.0, "dance": 0.0, "down": false, "dead": 0.0, "back": false,
	"turn": 0.0, "legYaw": 0.0}
var history: History
var weaponModel: Node3D = null
var blob = null
var _muzzle: Node3D = null
var _iframes := 0.0
var _sinceHurt := 99.0
var _sinceSprint := 99.0
var _exhausted := false
var _modelYaw
var _faceYaw := 0.0
var _stepIndex := 0
var _damage := 0.0
var _hidden := false
var _lookBuf := {"yaw": 0.0, "pitch": 0.0, "snapYaw": 0.0, "snapPitch": 0.0}  # JS module scratch `_look`
var _moveBuf := {"x": 0.0, "y": 0.0}  # JS module scratch `_move`

func _init(g) -> void:
	game = g
	health = float(P.hp)
	maxHealth = float(P.hp)
	model = DAU.node3d("player")
	stamina = float(P.stamina)
	mods = _defaultMods()
	history = History.new(40, 0.1)
	_modelYaw = Rig.Spring.new(170.0, 17.0)

func _defaultMods() -> Dictionary:
	return {"moveSpeed": 1.0, "sprintSpeed": 1.0, "reloadSpeed": 1.0, "fireRate": 1.0, "damage": 1.0, "maxHealth": P.hp,
		"regenDelay": P.regenDelay, "regenRate": P.regenRate, "adsSpeed": 1.0, "meleeDamage": 1.0,
		"knockback": 1.0, "unlimitedSprint": false, "sprintToFire": P.sprintToFire, "swapSpeed": 1.0}

func init() -> void:
	if game.scene != null and model.get_parent() == null:
		game.scene.add_child(model)
	if game.fx != null and game.fx.has_method("blob"):
		blob = game.fx.blob(model, 0.42)

func reset() -> void:
	var g = game
	mods = _defaultMods()
	maxHealth = float(mods.maxHealth)
	health = maxHealth
	alive = true
	downed = false
	god = _truthy(g.params.get("god"))
	invulnerable = false
	stamina = float(P.stamina)
	_exhausted = false
	_iframes = 0.0
	_sinceHurt = 99.0
	vel = Vector3.ZERO
	knock = Vector3.ZERO
	sprinting = false
	ads = false
	for k in ["recoil", "reload", "melee", "hurt", "climb", "attack", "dance", "dead"]:
		anim[k] = 0.0
	anim.down = false
	_spawn()
	history.clear()
	_damage = 0.0
	# MP: the last game's keyed locks / flags, then the life-cycle helper (built only for an MP game)
	_locks.clear()
	_protects.clear()
	_inCommercial = false
	hidden = false
	offAir = false
	spectate = null
	var n = g.get("net")
	if n != null and n.inGame:
		if mp == null:
			mp = PlayerMPScript.new(self, g)
		mp.reset()
	elif mp != null:
		mp.dispose()
		mp = null

func _spawn() -> void:
	var level = game.level
	var want = game.params.get("area")
	var x := 0.0
	var z := 4.0
	var y := 0.0
	var spawn = level.anchors.get("player_spawn") if level != null and level.get("anchors") != null else null
	if want != null and level != null and level.areas.get(want) != null:
		var r: Array = level.areas[want].rect
		var w := _walkableNear((float(r[0]) + float(r[2])) / 2.0, (float(r[1]) + float(r[3])) / 2.0)
		x = w.x
		z = w.y
	elif spawn != null:
		var sp: Vector3 = DAU.v3(spawn.pos)
		x = sp.x
		z = sp.z
		y = float(spawn.get("rotY")) if spawn.get("rotY") != null else 0.0
	teleport(x, z, y)
	pitch = -0.08

# Nearest nav-walkable point to (x, z) on growing rings (0.5 m steps, up to 8 m); (x, z) if none.
func _walkableNear(x: float, z: float) -> Vector2:
	var nav = game.nav
	if nav == null:
		return Vector2(x, z)
	for ri in 17:
		var r := ri * 0.5
		var n := 1 if r == 0.0 else int(ceilf((2.0 * PI * r) / 0.5))
		for i in n:
			var a := (float(i) / n) * PI * 2.0
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if nav.walkable(px, pz):
				return Vector2(px, pz)
	return Vector2(x, z)

func teleport(x: float, z: float, yaw_ = null) -> void:
	var level = game.level
	var col = level.col if level != null else null
	var f: float = col.floorAt(x, z, 50.0) if col != null else -INF
	pos = Vector3(x, f if f > -INF else 0.0, z)
	if yaw_ != null:
		yaw = float(yaw_)
		_faceYaw = yaw
		_modelYaw.reset(yaw)
	vel = Vector3.ZERO
	if level != null:
		var a = level.areaAt(x, z)
		area = a if _truthy(a) else area
	model.position = pos
	model.rotation.y = _modelYaw.x
	teleports += 1   # MP: remote avatars snap to the new position (state stream)

func setHero(id) -> void:
	var g = game
	var old = null
	if hero != null and _g(hero, "group") != null and hero.group.get_parent() == model:
		old = hero.group
		model.remove_child(old)
	heroId = id
	hero = null
	rig = null
	animator = null
	if ResourceLoader.exists(HEROES_PATH):
		var H = load(HEROES_PATH)
		if H != null:
			hero = H.buildHero(id, g)
	if hero == null:
		_freeHero(old)
		return
	rig = hero.rig
	animator = hero.animator
	setShadowCasting(hero.group, 0.12)
	if g.mats != null and g.mats.has_method("applyHeroFade"):
		g.mats.applyHeroFade(hero.group)
	# Placeholder heroes: the JS merged them into one rigid-skinned mesh per material (geo.skinRig, draw calls only;
	# not ported, SPEC §0.2). Baked heroes are one skinned mesh + face attachments whose lids/pupils animate.
	model.add_child(hero.group)
	if weaponModel != null:
		setWeaponModel(weaponModel)
	_freeHero(old)

# The replaced hero model (garbage in the JS): freed at the end of the frame, after anything still wanted (the
# weapon holder, re-attached above; whatever another system moves during this frame's resets) left it.
func _freeHero(old) -> void:
	if old != null and is_instance_valid(old):
		old.queue_free()

func setWeaponModel(group) -> void:
	if weaponModel != null and is_instance_valid(weaponModel) and weaponModel.get_parent() != null:
		weaponModel.get_parent().remove_child(weaponModel)
	weaponModel = group if group != null else null
	_muzzle = null
	if group == null or hero == null:
		return
	if game.mats != null and game.mats.has_method("applyHeroFade"):
		game.mats.applyHeroFade(group)
	setShadowCasting(group, 0.08)
	if group.get_parent() != null:
		group.get_parent().remove_child(group)
	hero.slots.handR.add_child(group)
	var m = DAU.byName(group, "muzzle")
	_muzzle = m as Node3D if m is Node3D else null

func forward(_out = null) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

# Camera ray (the crosshair is the exact screen centre): { origin, dir }.
func aimRay(_outOrigin = null, _outDir = null) -> Dictionary:
	var cam: Camera3D = game.camera
	if cam == null:
		return {"origin": pos + Vector3(0.0, 1.5, 0.0), "dir": forward()}
	var t: Transform3D = cam.global_transform if cam.is_inside_tree() else cam.transform
	return {"origin": t.origin, "dir": -t.basis.z.normalized()}

func muzzle(_out = null) -> Vector3:
	var m: Node3D = _muzzle
	if m == null and hero != null:
		m = hero.slots.handR
	if m == null or not is_instance_valid(m):
		return Vector3(pos.x, pos.y + 1.3, pos.z)
	if m.is_inside_tree():
		return m.global_position
	return Rig.worldTransform(m).origin

func hurt(dmg: float, fromPos = null) -> bool:
	var g = game
	if not alive or downed or god or invulnerable or _iframes > 0.0:
		return false
	if g.state != "playing":
		return false
	if mp != null and mp.blocksDamage():   # MP: off-air, revive / respawn grace
		return false
	health -= dmg
	_iframes = float(P.iframes)
	_sinceHurt = 0.0
	anim.hurt = 1.0
	g.events.emit("player:hurt", {"dmg": dmg, "from": fromPos})
	if g.cam != null:
		g.cam.shake(minf(0.5, 0.15 + dmg / 200.0), 0.35)
	if health <= 0.0:
		health = 0.0
		var handled = g.perks.onLethal() if g.perks != null and g.perks.has_method("onLethal") else false
		if not _truthy(handled):
			if mp != null:
				mp.goDown(fromPos)   # MP: downed (bleed-out; the host decides game over)
			else:
				alive = false
				g.gameOver()
	return true

func heal(n: float) -> void:
	if not alive:
		return
	health = minf(maxHealth, health + n)
	game.events.emit("player:heal", {})

func knockback(vec: Vector3) -> void:
	knock += vec * float(mods.knockback)

# MP cutscene locks (RECONCILE R6): every key held locks control / protects from damage; release with on = false.
func lock(key: String, on: bool = true) -> void:
	if on:
		_locks[key] = true
	else:
		_locks.erase(key)

func protect(key: String, on: bool = true) -> void:
	if on:
		_protects[key] = true
	else:
		_protects.erase(key)

func isLockKey(key: String) -> bool:
	return _locks.has(key) or _protects.has(key)

# MP: the state stream's flag byte (RemotePlayer F_* layout).
func netFlags() -> int:
	var f := 0
	if alive:
		f |= 1
	if downed:
		f |= 2
	if offAir:
		f |= 4
	if invulnerable or god or (mp != null and mp.graceT > 0.0):
		f |= 8
	if hidden:
		f |= 16
	if inCommercial:
		f |= 32
	if ads:
		f |= 64
	if sprinting:
		f |= 128
	return f

# MP: a hit / knockback the host decided for this player (RemotePlayer.hurt / knockback forwarding). Host only.
func net_hurt(dmg = 0.0, fromPos = null) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.sender != 1 or not (dmg is float or dmg is int):
		return
	hurt(clampf(float(dmg), 0.0, 1000.0), fromPos if fromPos is Vector3 else null)

func net_knockback(vec = null) -> void:
	var n = game.get("net")
	if n == null or not n.inGame or n.sender != 1 or not (vec is Vector3) or downed or not alive:
		return
	knockback(vec)

# MP life-cycle messages (PlayerMP, scripts/actors/player_mp.gd): requests to the host, then the host's broadcasts.
func net_downReq(pos = null) -> void:
	if mp != null:
		mp.net_downReq(pos)

func net_reviveStart(target = 0) -> void:
	if mp != null:
		mp.net_reviveStart(target)

func net_reviveStop(target = 0) -> void:
	if mp != null:
		mp.net_reviveStop(target)

func net_reviveDone(target = 0) -> void:
	if mp != null:
		mp.net_reviveDone(target)

func net_downed(id = 0, pos = null, bleed = 0.0) -> void:
	if mp != null:
		mp.net_downed(id, pos, bleed)

func net_reviveState(id = 0, reviver = 0, left = 0.0) -> void:
	if mp != null:
		mp.net_reviveState(id, reviver, left)

func net_revived(id = 0, reviver = 0) -> void:
	if mp != null:
		mp.net_revived(id, reviver)

func net_offAir(id = 0) -> void:
	if mp != null:
		mp.net_offAir(id)

func net_respawn(id = 0, pos = null, yaw = 0.0) -> void:
	if mp != null:
		mp.net_respawn(id, pos, yaw)

func down() -> void:
	if downed:
		return
	downed = true
	anim.down = true
	game.setState("down")
	game.events.emit("player:down", {})

func revive(selfRevive: bool = false) -> void:
	downed = false
	alive = true
	anim.down = false
	anim.dead = 0.0
	health = maxHealth
	_sinceHurt = 99.0
	if game.state == "down":
		game.setState("playing")
	game.events.emit("player:revive", {"selfRevive": selfRevive})

func update(dt: float) -> void:
	var g = game
	var rdt: float = g.time.realDt
	if maxHealth != float(mods.maxHealth):
		maxHealth = float(mods.maxHealth)
		health = minf(health, maxHealth)
	if mp != null:
		mp.update(dt, rdt)   # MP: life cycle, revive items, spectating (an off-air player rides along)
	var locked := controlLocked
	var control := alive and not downed and not locked
	var override = g.render.get("cameraOverride") if g.render != null else null
	if control and not _truthy(override) and g.state == "playing":
		_look()
	elif mp != null and downed and alive and not locked and not _truthy(override) and g.state == "playing":
		_look()   # MP: a downed player still looks around
	if dt > 0.0 and control:
		_move(dt)
	elif dt > 0.0 and mp != null and downed:
		_move(dt, false)   # MP downed: no input, gravity / floor only
	if dt > 0.0:
		_vitals(dt)
	if not offAir:
		_animate(rdt)

func _look() -> void:
	var d: Dictionary = game.input.lookDelta(_lookBuf)
	var k := 0.65 if ads else 1.0
	# snapYaw / snapPitch: the gamepad aim-assist snap (already an exact angle, not scaled by ADS)
	yaw = wrapAngle(yaw + float(d.yaw) * k + float(d.get("snapYaw", 0.0)))
	pitch = clampf(pitch + float(d.pitch) * k + float(d.get("snapPitch", 0.0)), -1.25, 1.1)

# useInput = false (MP downed): no move / aim / sprint / jump input, only gravity, knockback decay and the floor.
func _move(dt: float, useInput: bool = true) -> void:
	var g = game
	var input = g.input
	# keyboard: digital -1/0/1 axes; gamepad: the analog left stick (magnitude <= 1 scales the speed)
	var mv = input.move(_moveBuf) if input.has_method("move") else null
	var fwdIn: float = float(mv.y) if mv != null else (1.0 if input.down("forward") else 0.0) - (1.0 if input.down("back") else 0.0)
	var strIn: float = float(mv.x) if mv != null else (1.0 if input.down("right") else 0.0) - (1.0 if input.down("left") else 0.0)
	if not useInput:
		fwdIn = 0.0
		strIn = 0.0
	var mag := sqrt(fwdIn * fwdIn + strIn * strIn)
	ads = input.down("aim") and useInput

	# Sprint + stamina (GDD §6.2: 4 s, refill 1 s after stopping, full in 3 s).
	var unlimited := _truthy(mods.unlimitedSprint)
	var canSprint := unlimited or (not _exhausted and stamina > 0.0)
	sprinting = useInput and input.down("sprint") and fwdIn > SPRINT_FWD and not ads and canSprint
	if sprinting:
		_sinceSprint = 0.0
		if not unlimited:
			stamina -= dt
			if stamina <= 0.0:
				stamina = 0.0
				_exhausted = true
	else:
		_sinceSprint += dt
		if _sinceSprint >= float(P.staminaDelay):
			stamina = minf(float(P.stamina), stamina + dt * (float(P.stamina) / float(P.staminaRefill)))
		if _exhausted and stamina >= float(P.stamina) * 0.25:
			_exhausted = false

	# Target speed.
	var def = g.weapons.currentDef() if g.weapons != null and g.weapons.has_method("currentDef") else null
	var mv_ = _g(def, "move") if def != null else null
	var weaponMul: float = float(mv_) if _truthy(mv_) else 1.0
	var speed: float
	if ads:
		speed = float(P.ads) * float(mods.moveSpeed)
	elif sprinting:
		speed = float(P.sprint) * float(mods.sprintSpeed)
	else:
		# backpedal share: 1 whenever a keyboard move includes S (as before); the stick blends by its angle
		var back := clampf((-fwdIn / minf(1.0, mag)) * 1.5, 0.0, 1.0) if mag > 1e-4 else 0.0
		speed = lerpf(float(P.run), float(P.backpedal), back) * float(mods.moveSpeed)
	speed *= weaponMul

	var _fwd := forward()
	var _right := Vector3(-_fwd.z, 0.0, _fwd.x)
	var _wish := _fwd * fwdIn + _right * strIn
	# analog sticks keep their magnitude (walk slower with a light push); sprint is always full speed
	if _wish.length_squared() > 1.0 or (sprinting and _wish.length_squared() > 1e-6):
		_wish = _wish.normalized()
	_wish *= speed

	# Acceleration-based horizontal motion (air control 0.3).
	var air := 1.0 if grounded else AIR
	var rate := (ACCEL if _wish.length_squared() > 0.0 else DECEL) * air
	var _hv := Vector3(_wish.x - vel.x, 0.0, _wish.z - vel.z)
	var dl := _hv.length()
	var maxStep := rate * dt
	if dl > maxStep:
		_hv *= maxStep / dl
	vel.x += _hv.x
	vel.z += _hv.z

	if useInput and input.pressed("jump") and grounded:
		vel.y = JUMP_V
		grounded = false
		g.events.emit("player:jump", {})
	# Exact constant-acceleration step: the 1.1 m apex holds at any frame rate.
	var vy0 := vel.y
	vel.y -= float(P.gravity) * dt
	knock *= exp(-dt * 6.0)

	var _delta := Vector3((vel.x + knock.x) * dt, (vy0 + vel.y) * 0.5 * dt, (vel.z + knock.z) * dt)
	var col = g.level.get("col") if g.level != null else null
	var wasGrounded := grounded
	var expectY := pos.y + _delta.y
	var res = _moveCircle(col, _delta)
	var onGround := _truthy(res.onGround)
	if not onGround and wasGrounded and vel.y <= 0.0 and col != null:
		# Walk down steps/ramps instead of hopping off them.
		var f: float = col.floorAt(pos.x, pos.z, pos.y)
		if f > -INF and pos.y - f <= STEP_UP:
			pos.y = f
			onGround = true
	if onGround:
		if not wasGrounded and vel.y < -2.0:
			g.events.emit("player:land", {"speed": -vel.y})
		vel.y = maxf(vel.y, -1.0)
	elif vel.y > 0.0 and pos.y < expectY - 1e-4:
		vel.y = 0.0  # head bump
	grounded = onGround
	var a = g.level.areaAt(pos.x, pos.z) if g.level != null else null
	area = a if _truthy(a) else area
	history.tick(dt, pos, yaw, area)

# collision.moveCircle(pos, delta, radius, height, stepUp) mutated pos in the JS; the GDScript collision returns the
# moved feet position in res.pos and remembers "grounded" per owner (this player object) — see collision.gd.
# (No level/collision loaded — an incomplete port only: free motion over a y = 0 floor.)
func _moveCircle(col, delta: Vector3) -> Variant:
	if col == null:
		pos += delta
		var on := pos.y <= 0.0
		if on:
			pos.y = 0.0
		return {"onGround": on, "hitWall": false, "groundY": 0.0, "normal": Vector3.ZERO, "hitCeiling": false, "pos": pos}
	var res = col.moveCircle(pos, delta, radius, height, STEP_UP, null, self)
	pos = res.pos
	return res

func _vitals(dt: float) -> void:
	_iframes = maxf(0.0, _iframes - dt)
	_sinceHurt += dt
	if alive and not downed and _sinceHurt >= float(mods.regenDelay) and health < maxHealth:
		health = minf(maxHealth, health + float(mods.regenRate) * dt)
	# Signal-loss post effect follows missing health (eased so hits read as a pulse).
	var target := 1.0 - health / maxHealth if alive else 1.0
	if mp != null:
		target = mp.damageTarget(target)   # MP: downed = fading signal (bleed-out), off-air = the teammate's clear feed
	_damage += (target - _damage) * (1.0 - exp(-dt * (14.0 if target > _damage else 3.0)))
	if game.render != null and game.render.get("post") is Dictionary:
		game.render.post.damage = _damage

func _animate(rdt: float) -> void:
	if animator == null:
		return
	model.position = pos

	# Facing: aim direction while moving/aiming/firing; idle free-look turns the body past ~60 degrees.
	var hs := Vector2(vel.x, vel.z).length()
	var firing: bool = float(anim.recoil) > 0.05 or float(anim.melee) > 0.0
	if sprinting and hs > 0.5:
		_faceYaw = atan2(-vel.x, -vel.z)
	elif hs > 0.4 or ads or firing:
		_faceYaw = yaw
	elif absf(wrapAngle(yaw - _faceYaw)) > 1.05:
		_faceYaw = yaw
	var cur: float = _modelYaw.x
	var target := cur + wrapAngle(_faceYaw - cur)
	_modelYaw.update(rdt, target)
	model.rotation.y = _modelYaw.x
	var turn: float = _modelYaw.v if rdt > 0.0 else 0.0

	# Movement relative to the body for strafing legs / backpedal.
	var my: float = _modelYaw.x
	var fx := -sin(my)
	var fz := -cos(my)
	var lz := vel.x * fx + vel.z * fz
	var lx := vel.x * -fz + vel.z * fx
	var back := lz < -0.3 and hs > 0.5
	var legYaw := clampf(atan2(lx, -lz) if back else atan2(-lx, lz), -1.1, 1.1) * 0.75 if hs > 0.5 and not sprinting else 0.0

	var a := anim
	a.speed = hs if grounded else 0.0
	a.sprint = sprinting
	a.grounded = grounded
	a.aimPitch = pitch
	a.aimYaw = clampf(wrapAngle(yaw - my), -1.1, 1.1)
	a.aiming = not sprinting and weaponModel != null and not downed
	a.back = back
	a.turn = turn
	a.legYaw = legYaw
	a.hurt = maxf(0.0, float(a.hurt) - rdt / 0.3)
	if not alive:
		a.dead = minf(1.0, float(a.dead) + rdt / 0.9)
	animator.update(rdt, a)
	_footsteps()

func _footsteps() -> void:
	var g = game
	var idx := int(floorf(float(animator.phase) / PI))
	if idx == _stepIndex:
		return
	_stepIndex = idx
	if not grounded or float(anim.speed) < 0.8:
		return
	var level = g.level
	var surface = null
	if level.has_method("surfaceAt"):
		surface = level.surfaceAt(pos.x, pos.z, pos.y)
	if not _truthy(surface):
		var ar = level.areas.get(area) if area != null else null
		surface = ar.get("floor") if ar != null else null
	if not _truthy(surface):
		surface = "carpet"
	g.events.emit("player:step", {"foot": idx & 1, "sprint": sprinting, "surface": surface})

func lateUpdate(_dt: float = 0.0) -> void:
	# Hero fade when the camera gets closer than 0.8 m (dithered via the global uHeroFade uniform).
	var g = game
	if hero == null:
		return
	var d: float = float(g.cam.heroDistance) if g.cam != null else 3.0
	if offAir:
		d = 3.0   # MP: the hidden hero; the camera follows a teammate (whose model never uses the hero fade)
	var fade := DAU.smoothstep3(d, 0.35, 0.8)
	_setHeroFade(fade)
	# Parts that cannot dither (glow eyes, glasses, art attachments) hide as soon as the dither starts.
	var hide := fade < 0.9
	if hide != _hidden:
		_hidden = hide
		DAU.traverse(model, func(o: Node) -> void:
			if o.has_meta("userData") and _truthy(o.get_meta("userData").get("daHideOnFade")) and o is Node3D:
				o.visible = not hide)

# g.mats.uniforms.uHeroFade.value = fade (materials.gd owns the global uniforms and uploads them).
func _setHeroFade(fade: float) -> void:
	var M = game.mats
	if M == null:
		return
	var U = M.get("uniforms")
	var u = U.get("uHeroFade") if U is Dictionary else null
	if u != null:
		u.value = fade
