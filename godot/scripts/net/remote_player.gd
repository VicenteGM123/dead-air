# RemotePlayer (MP_SPEC §3.2, RECONCILE R6/R12): another peer's player as seen on this peer — a player-like object
# that world systems read like game.player (Player, scripts/actors/player.gd), driven by its owner's 30 Hz state
# stream (net.gd, stream 'p'). Built by net.onNewGame() for every other peer; removed when the peer leaves.
#
# FIELDS (Player-compatible; world systems read them, never write): pos (feet), vel, yaw, pitch, radius (0.38),
#   height (hero rig height), health, maxHealth, alive, downed, offAir, heroId, area, invulnerable (owner's
#   invulnerable / god / grace), hidden, inCommercial, busy (owner's controlLocked), ads, sprinting, grounded, god
#   (false), stamina, controlLocked (false), mods (Player defaults), model (Node3D under game.scene), hero (the
#   heroes.gd buildHero contract: {group, rig, animator, parts {head, torso, handL, handR}, slots {head, handL, handR,
#   footL, footR, back, wristL, wristR, neck, belt}, hairBounds, def, baked, art}), rig, animator (the engine
#   Rig.Animator: animator.override / pose() / kick() work like on the local hero; the held-weapon IK runs from
#   animator.postUpdate and is skipped while animator.override is set), anim (Player.anim keys, replicated),
#   weaponId ('' = melee only), upgraded, weaponSignal ('' or hot_mic | laugh_track | cold_open; `signal` is a GDScript
#   keyword), weaponModel (the held model on hero.slots.handR, null when unarmed), weaponPose (Callable(rig, dt): the
#   fallback weapon IK, for systems that drive animator.override and want the gun pose after theirs), postAnimate
#   (Callable(remote, rdt) | invalid: called every frame right after the remote animator update — mp-combat's IK copy),
#   aimPoint (where the owner's crosshair ray lands), bodyYaw (model facing), history (Player.History: 4 s of the
#   interpolated position), blob, ext (the owner's net.setLocalExt Dictionary — the same object as
#   net.peers[id].ext), peerId, name, color, isRemote (true).
# METHODS: hurt(dmg, fromPos) -> bool — the hit is forwarded to the owner (player.net_hurt on its peer; net.net_hurt
#   until player.gd has it) when it can land: alive, not downed / off-air / hidden / in a commercial / invulnerable /
#   in its i-frames; a local i-frame window (T.player.iframes) then keeps a burst of hits from being forwarded twice.
#   knockback(vec) (forwarded: player.net_knockback). muzzle() -> Vector3, forward() -> Vector3, aimRay() ->
#   {origin, dir}, headPos() -> Vector3 (top of the head, world: name tags), teleport(x, z, yaw?) (snap + clears the
#   interpolation buffer), setWeaponModel(node | null) (attaches the held model to hero.slots.handR like
#   Player.setWeaponModel, minus the hero fade; render layer LAYER), heal(_n) / down() / revive() (no-ops: the owner
#   decides), update(rdt) (net.update, every frame in every state), free_() (removal).
# MODEL: the hero built like Player.setHero (char_runtime body + the engine rig + Animator, Player.setShadowCasting,
#   an fx blob shadow) but WITHOUT the hero-fade dither (the global uHeroFade fades the LOCAL hero when the camera
#   gets close). Every mesh of the hero and of its held weapon is on render layer LAYER = 1 (Config.LAYERS.ZOMBIES,
#   the actors layer): the gameplay camera and the CCTV feeds draw it, cameras that render layer 0 only (the sponsor
#   commercial camera, the menu room, the ending shots) do not. Hidden (model + blob) while hidden or offAir; the held
#   weapon hides while inCommercial or when the owner's weapon is hidden. The model transform is set BEFORE
#   animator.update every frame (like Player._animate). 'net:avatar' {id} is emitted after the hero model is built, so
#   systems that attach things to hero.slots (costumes, the tape reel...) can (re)attach them.
# HELD WEAPON (owned by mp-combat): when the replicated weapon (weaponId / upgraded / weaponSignal) changes and
#   game.weapons has buildRemoteHeld(remote, weaponId, upgraded, signal) -> Node3D | null, its result is attached with
#   setWeaponModel and posed by mp-combat (postAnimate). FALLBACK (no buildRemoteHeld): weapon_models.gd
#   buildModel(id, upgraded, signal) in a holder with def.scale (like weapons.gd _equip), cached per
#   id/upgrade/signal, posed by a reduced copy of weapons.gd's IK (statics HOLDS / LH_FRAMES / solveArm) from
#   animator.postUpdate: right hand on the grip, left hand on the weapon, aimed at aimPoint; hip/ADS, sprint
#   low-ready, reload tilt, recoil kick, melee pull-back. Hidden while inCommercial / hidden / offAir or when the
#   owner's held model is hidden.
# INTERPOLATION: snapshots are buffered and played INTERP_DELAY (100 ms) behind the sender's clock (mapped to the
#   local clock by a min-tracking offset: network jitter up to ~100 ms is absorbed); pos / angles / anim floats are
#   interpolated; past the newest snapshot the motion is extrapolated from its velocity for up to EXTRAP_MAX (150 ms),
#   then holds. A jump > SNAP_DIST (3 m) or a change of the owner's teleport counter snaps. Gameplay flags (alive,
#   downed, offAir, invulnerable, hidden, inCommercial, health) come from the NEWEST snapshot (no added delay).
# SOUNDS (positional, at the remote): footsteps with the same cues as the local player's player:step (audio.gd
#   _step) from the remote animator's gait phase; jump / land (from the replicated grounded flag) and hurt_grunt in
#   the hero's voice (on the replicated anim.hurt flinch).
# STATE STREAM (encodeLocal / pushState, STATE_SIZE bytes, little endian; any change bumps net.PROTOCOL):
#   0 u8 format · 1 u16 seq · 3 u32 t (ms, sender clock) · 7 f32x3 pos · 19 f16x3 vel · 25 f16 yaw · 27 f16 pitch ·
#   29 f16 bodyYaw · 31 f32x3 aimPoint · 43 f16 speed, aimPitch, aimYaw, turn, legYaw · 53 u8x8 recoil, reload,
#   melee, hurt, climb, attack, dance, dead (0..1) · 61 f16 health · 63 f16 maxHealth · 65 u8 weapon (index in
#   weapon_defs GUN_IDS, 255 = none) · 66 u8 signal · 67 u8 area (index in the sorted level.areas ids, 255 = none) ·
#   68 u8 flags0 = Player.netFlags() (1 alive, 2 downed, 4 offAir, 8 invulnerable, 16 hidden, 32 inCommercial, 64 ads,
#   128 sprinting; built from the fields while player.gd lacks netFlags) · 69 u8 flags1 (1 anim.sprint, 2 anim.grounded,
#   4 anim.aiming, 8 anim.down, 16 anim.back, 32 upgraded, 64 weapon visible, 128 i-frames) · 70 u8 flags2 (1 busy =
#   controlLocked) · 71 u8 teleport counter (player.teleports when it exists, else bumped by the sender when its
#   position jumps > 1.5 m between two sends).
class_name RemotePlayer
extends RefCounted

const PlayerScript = preload("res://scripts/actors/player.gd")
const W = preload("res://scripts/game/weapons.gd")
const WD = preload("res://scripts/game/weapon_defs.gd")
const WM = preload("res://scripts/game/weapon_models.gd")
const HEROES_PATH := "res://scripts/actors/heroes.gd"

const LAYER := 1                 # Config.LAYERS.ZOMBIES (see the header)
const INTERP_DELAY := 0.1
const EXTRAP_MAX := 0.15
const SNAP_DIST := 3.0
const RING := 24
const FORMAT := 1
const STATE_SIZE := 72
const SIGNALS := ["", "hot_mic", "laugh_track", "cold_open"]
const ANIM_U8 := ["recoil", "reload", "melee", "hurt", "climb", "attack", "dance", "dead"]
const UP := Vector3(0, 1, 0)
# flags0 (Player.netFlags layout, mp-players)
const F_ALIVE := 1
const F_DOWNED := 2
const F_OFFAIR := 4
const F_INVULN := 8
const F_HIDDEN := 16
const F_COMMERCIAL := 32
const F_ADS := 64
const F_SPRINTING := 128
# flags1
const A_SPRINT := 1
const A_GROUNDED := 2
const A_AIMING := 4
const A_DOWN := 8
const A_BACK := 16
const F_UPGRADED := 32
const F_WEAPONVIS := 64
const F_IFRAMES := 128
# flags2
const F_BUSY := 1

static var _areaIds: Array = []

var game
var peerId := 0
var name := ""
var color := "#FFFFFF"
var isRemote := true
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var bodyYaw := 0.0
var radius := 0.38
var height := 1.75
var health := 150.0
var maxHealth := 150.0
var alive := true
var downed := false
var offAir := false
var heroId = null
var area = null
var invulnerable := false
var hidden := false
var inCommercial := false
var busy := false
var ads := false
var sprinting := false
var grounded := true
var god := false
var controlLocked := false
var stamina := 4.0
var mods: Dictionary
var model: Node3D = null
var hero = null
var rig = null
var animator = null
var anim := {"speed": 0.0, "sprint": false, "grounded": true, "aimPitch": 0.0, "aimYaw": 0.0, "aiming": true, "recoil": 0.0,
	"reload": 0.0, "melee": 0.0, "hurt": 0.0, "climb": 0.0, "attack": 0.0, "dance": 0.0, "down": false, "dead": 0.0, "back": false,
	"turn": 0.0, "legYaw": 0.0}
var weaponId := ""
var upgraded := false
var weaponSignal := ""
var weaponModel: Node3D = null
var weaponPose: Callable
var postAnimate: Callable = Callable()
var aimPoint := Vector3.ZERO
var history = null
var blob = null
var ext := {}

var _ring: Array = []
var _head := 0
var _count := 0
var _offset := 0.0
var _hasOffset := false
var _lastSeq := -1
var _lastTp := -1
var _iframes := false
var _weaponVis := true
var _hitCool := 0.0
var _held := {}               # weapon key -> {holder, model, def, leftHand, butt, muzzle}
var _weaponKey := ""
var _wId := ""
var _wUp := false
var _wSig := ""
var _muzzle: Node3D = null
var _stepIndex := 0
var _adsW := 0.0
var _sprintW := 0.0
var _busyW := 0.0
var _ownHeld := false          # the held model is our fallback build (posed by _poseWeapon)
var _prevGrounded := true
var _airVy := 0.0
var _prevHurt := 0.0
var _voice := -1

func _init(g, id: int, heroId_, name_: String, color_: String) -> void:
	game = g
	peerId = id
	name = name_
	color = color_
	heroId = heroId_
	var P: Dictionary = Config.T.player
	health = float(P.hp)
	maxHealth = float(P.hp)
	stamina = float(P.stamina)
	mods = {"moveSpeed": 1.0, "sprintSpeed": 1.0, "reloadSpeed": 1.0, "fireRate": 1.0, "damage": 1.0, "maxHealth": P.hp,
		"regenDelay": P.regenDelay, "regenRate": P.regenRate, "adsSpeed": 1.0, "meleeDamage": 1.0,
		"knockback": 1.0, "unlimitedSprint": false, "sprintToFire": P.sprintToFire, "swapSpeed": 1.0}
	history = PlayerScript.History.new(40, 0.1)
	for i in RING:
		_ring.append({"t": 0.0, "seq": 0, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "bodyYaw": 0.0,
			"aim": Vector3.ZERO, "speed": 0.0, "aimPitch": 0.0, "aimYaw": 0.0, "turn": 0.0, "legYaw": 0.0,
			"u8": PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0]), "f1": 0, "snap": false})
	weaponPose = func(rg, dt: float) -> void: _poseWeapon(rg, dt, true)
	model = DAU.node3d("remote_player_%d" % id)
	if g.scene != null:
		g.scene.add_child(model)
	_buildHero()

# ------------------------------------------------------------------------------------------------ model
func _buildHero() -> void:
	var c = buildRemoteHero(heroId, game)
	if c == null:
		push_warning("[net] remote hero '%s' could not be built" % str(heroId))
		return
	hero = c
	rig = c.rig
	animator = c.animator
	var def: Dictionary = c.def
	if def.get("rig") is Dictionary and def.rig.get("height") != null:
		height = float(def.rig.height)
	PlayerScript.setShadowCasting(c.group, 0.12)
	DAU.setLayerRecursive(c.group, LAYER)
	model.add_child(c.group)
	if game.fx != null and game.fx.has_method("blob"):
		blob = game.fx.blob(model, 0.42)
	if animator != null and "postUpdate" in animator:
		animator.postUpdate.append(func(rg, dt): _poseWeapon(rg, dt, false))
	if game.events != null:
		game.events.emit("net:avatar", {"id": peerId})

# Heroes.buildBakedHero without the hero-fade materials (a remote hero must not dither with the LOCAL camera fade).
static func buildRemoteHero(id, game):
	if not ResourceLoader.exists(HEROES_PATH):
		return null
	var H = load(HEROES_PATH)
	var def: Dictionary = H._heroDef(id)
	if not H.hasBakedHero(def.id, game):
		return null
	var M = game.mats if game != null else null
	var c = CharRuntime.buildCharacter(def.id, {"envMap": M.get("envMap") if M != null else null, "globals": true, "heroFade": false, "merge": true})
	if c == null or c.animator == null:
		return null
	for k in H.SLOT_NAMES:
		if c.slots == null or not c.slots.has(k):
			return null
	var J: Dictionary = c.rig.joints
	var D: Dictionary = c.rig.dims
	var head := DAU.node3d("part:headCenter")
	head.position = Vector3(0, float(D.headH) * 0.5, 0)
	J.head.add_child(head)
	c.group.name = "remote_hero_%s" % def.id
	return {
		"group": c.group, "rig": c.rig, "animator": c.animator,
		"parts": {"head": head, "torso": J.chest, "handL": J.handL, "handR": J.handR},
		"slots": c.slots, "hairBounds": c.hairBounds, "def": def, "baked": true, "art": c,
	}

func free_() -> void:
	if blob != null:
		blob.remove()
		blob = null
	if animator != null and "postUpdate" in animator:
		animator.postUpdate.clear()
	for k in _held:
		var h: Dictionary = _held[k]
		if is_instance_valid(h.holder) and h.holder.get_parent() == null:
			h.holder.free()
	_held.clear()
	weaponModel = null
	if model != null and is_instance_valid(model):
		if model.get_parent() != null:
			model.get_parent().remove_child(model)
		model.queue_free()
	model = null
	hero = null
	rig = null
	animator = null

# ------------------------------------------------------------------------------------------------ per frame
func update(rdt: float) -> void:
	_hitCool = maxf(0.0, _hitCool - rdt)
	_sample(Time.get_ticks_usec() / 1000000.0)
	if model == null:
		return
	var vis := not (hidden or offAir)
	if model.visible != vis:
		model.visible = vis
	if blob != null:
		blob.visible = vis
	if hero == null or animator == null:
		return
	model.position = pos
	model.rotation.y = bodyYaw
	if weaponModel != null and is_instance_valid(weaponModel):
		var wv := _weaponVis and not inCommercial
		if weaponModel.visible != wv:
			weaponModel.visible = wv
	if vis:
		animator.update(rdt, anim)
		if postAnimate.is_valid():
			postAnimate.call(self, rdt)
		_footsteps()
		_sounds()
	history.tick(rdt, pos, yaw, area)

# jump / land / hurt grunt at the remote (audio.gd plays the local player's from player:jump / land / hurt).
func _sounds() -> void:
	var A = game.audio
	if A == null or not A.has_method("play"):
		return
	if grounded != _prevGrounded:
		if not grounded and vel.y > 1.0:
			A.play("jump", {"pos": pos})
		elif grounded and _airVy < -2.0:
			A.play("land", {"pos": pos, "vol": clampf(-_airVy / 10.0, 0.35, 1.0)})
		_prevGrounded = grounded
	if not grounded:
		_airVy = minf(_airVy, vel.y) if vel.y < 0.0 else vel.y
	else:
		_airVy = 0.0
	var hu := float(anim.hurt)
	if hu > 0.6 and _prevHurt <= 0.6 and alive:
		A.play("hurt_grunt", {"pos": pos, "base": _heroVoice(A)})
	_prevHurt = hu

# audio.gd HERO_VOICE[heroId] (a script constant: read through the script's constant map once).
func _heroVoice(A) -> int:
	if _voice < 0:
		_voice = 200
		var scr = A.get_script()
		var hv = scr.get_script_constant_map().get("HERO_VOICE") if scr != null else null
		if hv is Dictionary and hv.has(heroId):
			_voice = int(hv[heroId])
	return _voice

func _footsteps() -> void:
	var idx := int(floorf(float(animator.phase) / PI))
	if idx == _stepIndex:
		return
	_stepIndex = idx
	if not grounded or float(anim.speed) < 0.8:
		return
	var A = game.audio
	if A == null or not A.has_method("play"):
		return
	var level = game.level
	var surface = null
	if level != null and level.has_method("surfaceAt"):
		surface = level.surfaceAt(pos.x, pos.z, pos.y)
	if surface == null or surface == "":
		var ar = level.areas.get(area) if level != null and area != null else null
		surface = ar.get("floor") if ar != null else null
	if surface == null or surface == "":
		surface = "carpet"
	var cues = A.get("cues")
	var id := "step_" + str(surface)
	if cues is Dictionary and not cues.has(id):
		id = "step_tile"
	A.play(id, {"pos": pos, "vol": 1.0 if sprinting else 0.75, "rate": 0.93 + randf() * 0.14, "foot": idx & 1})

# ------------------------------------------------------------------------------------------------ stream (send)
# The local player's state into buf (resized to STATE_SIZE); st = {lastPos, tp} keeps the sender's teleport detector.
static func encodeLocal(g, buf: PackedByteArray, seq: int, tms: int, st: Dictionary) -> PackedByteArray:
	if buf.size() != STATE_SIZE:
		buf.resize(STATE_SIZE)
	var p = g.player
	var a: Dictionary = p.anim
	buf.encode_u8(0, FORMAT)
	buf.encode_u16(1, seq & 0xFFFF)
	buf.encode_u32(3, tms & 0xFFFFFFFF)
	var ps: Vector3 = p.pos
	buf.encode_float(7, ps.x)
	buf.encode_float(11, ps.y)
	buf.encode_float(15, ps.z)
	var v: Vector3 = p.vel
	buf.encode_half(19, v.x)
	buf.encode_half(21, v.y)
	buf.encode_half(23, v.z)
	buf.encode_half(25, p.yaw)
	buf.encode_half(27, p.pitch)
	# the body yaw spring is unwrapped (grows with every full turn): wrap it, half floats lose precision far from 0
	buf.encode_half(29, wrapf(p.model.rotation.y if p.model != null else p.yaw, -PI, PI))
	var W_ = g.weapons
	var ap = W_.get("aimPoint") if W_ != null else null
	var aim: Vector3 = ap if ap is Vector3 and ap != Vector3.ZERO else ps + Vector3(-sin(p.yaw) * 10.0, 1.5, -cos(p.yaw) * 10.0)
	buf.encode_float(31, aim.x)
	buf.encode_float(35, aim.y)
	buf.encode_float(39, aim.z)
	buf.encode_half(43, float(a.speed))
	buf.encode_half(45, float(a.aimPitch))
	buf.encode_half(47, float(a.aimYaw))
	buf.encode_half(49, float(a.turn))
	buf.encode_half(51, float(a.legYaw))
	for i in ANIM_U8.size():
		buf.encode_u8(53 + i, int(clampf(float(a.get(ANIM_U8[i], 0.0)), 0.0, 1.0) * 255.0 + 0.5))
	buf.encode_half(61, p.health)
	buf.encode_half(63, p.maxHealth)
	var slot = W_.currentSlot() if W_ != null and W_.has_method("currentSlot") else null
	var wi := WD.GUN_IDS.find(slot.id) if slot != null else -1
	buf.encode_u8(65, wi if wi >= 0 else 255)
	var si := SIGNALS.find(str(slot.get("signal"))) if slot != null and slot.get("signal") else 0
	buf.encode_u8(66, maxi(0, si))
	var ai := areaIds(g).find(p.area) if p.area != null else -1
	buf.encode_u8(67, ai if ai >= 0 else 255)
	var f0: int
	if p.has_method("netFlags"):
		f0 = int(p.netFlags()) & 0xFF
	else:
		f0 = (F_ALIVE if p.alive else 0) | (F_DOWNED if p.downed else 0) | (F_OFFAIR if p.get("offAir") == true else 0) \
			| (F_INVULN if (p.invulnerable or p.god) else 0) | (F_HIDDEN if p.get("hidden") == true else 0) \
			| (F_COMMERCIAL if _inCommercialLocal(g, p) else 0) | (F_ADS if p.ads else 0) | (F_SPRINTING if p.sprinting else 0)
	buf.encode_u8(68, f0)
	var wm = p.get("weaponModel")
	var f1 := (A_SPRINT if a.sprint else 0) | (A_GROUNDED if a.grounded else 0) | (A_AIMING if a.aiming else 0) \
		| (A_DOWN if a.down else 0) | (A_BACK if a.get("back") else 0) | (F_UPGRADED if slot != null and slot.upgraded else 0) \
		| (F_WEAPONVIS if wm is Node3D and is_instance_valid(wm) and (wm as Node3D).visible else 0) \
		| (F_IFRAMES if float(p.get("_iframes") if p.get("_iframes") != null else 0.0) > 0.0 else 0)
	buf.encode_u8(69, f1)
	buf.encode_u8(70, F_BUSY if p.controlLocked else 0)
	var tp = p.get("teleports")
	if not (tp is int):
		var lp = st.get("lastPos")
		if lp is Vector3 and (lp as Vector3).distance_to(ps) > 1.5:
			st.tp = (int(st.get("tp", 0)) + 1) & 0xFF
		tp = st.get("tp", 0)
	st.lastPos = ps
	buf.encode_u8(71, int(tp) & 0xFF)
	return buf

static func _inCommercialLocal(g, p) -> bool:
	var v = p.get("inCommercial")
	if v != null:
		return v == true
	var s = g.get("sponsors")
	return s != null and s.get("inCommercial") == true

# Sorted level area ids (the same list on every peer: same level).
static func areaIds(g) -> Array:
	if _areaIds.is_empty() and g.level != null and g.level.get("areas") is Dictionary:
		_areaIds = g.level.areas.keys()
		_areaIds.sort()
	return _areaIds

# ------------------------------------------------------------------------------------------------ stream (receive)
func pushState(data: PackedByteArray, now: float) -> void:
	if data.size() < STATE_SIZE or data.decode_u8(0) != FORMAT:
		return
	var seq := data.decode_u16(1)
	if _lastSeq >= 0 and ((seq - _lastSeq) & 0xFFFF) >= 0x8000:
		return   # older than what we have (the channel is ordered; a reconnect resets the sequence)
	_lastSeq = seq
	var t := data.decode_u32(3) / 1000.0
	var d := now - t
	if not _hasOffset or d < _offset:
		_offset = d
		_hasOffset = true
	else:
		_offset += (d - _offset) * 0.01      # slow upward drift (clock drift, a congested route)
	var prev = _ring[(_head - 1 + RING) % RING] if _count > 0 else null
	var s: Dictionary = _ring[_head]
	_head = (_head + 1) % RING
	_count = mini(_count + 1, RING)
	s.t = t
	s.seq = seq
	s.pos = Vector3(data.decode_float(7), data.decode_float(11), data.decode_float(15))
	s.vel = Vector3(data.decode_half(19), data.decode_half(21), data.decode_half(23))
	s.yaw = data.decode_half(25)
	s.pitch = data.decode_half(27)
	s.bodyYaw = data.decode_half(29)
	s.aim = Vector3(data.decode_float(31), data.decode_float(35), data.decode_float(39))
	s.speed = data.decode_half(43)
	s.aimPitch = data.decode_half(45)
	s.aimYaw = data.decode_half(47)
	s.turn = data.decode_half(49)
	s.legYaw = data.decode_half(51)
	var u8: PackedFloat32Array = s.u8
	for i in ANIM_U8.size():
		u8[i] = data.decode_u8(53 + i) / 255.0
	s.u8 = u8
	s.f1 = data.decode_u8(69)
	var tp := data.decode_u8(71)
	s.snap = (_lastTp >= 0 and tp != _lastTp) or (prev != null and (prev.pos as Vector3).distance_to(s.pos) > SNAP_DIST)
	_lastTp = tp
	# gameplay state: newest wins (no interpolation delay)
	health = data.decode_half(61)
	maxHealth = data.decode_half(63)
	var wi := data.decode_u8(65)
	weaponId = WD.GUN_IDS[wi] if wi < WD.GUN_IDS.size() else ""
	var si := data.decode_u8(66)
	weaponSignal = SIGNALS[si] if si < SIGNALS.size() else ""
	var ai := data.decode_u8(67)
	var ids := areaIds(game)
	area = ids[ai] if ai < ids.size() else area
	var f0 := data.decode_u8(68)
	alive = (f0 & F_ALIVE) != 0
	downed = (f0 & F_DOWNED) != 0
	offAir = (f0 & F_OFFAIR) != 0
	invulnerable = (f0 & F_INVULN) != 0
	hidden = (f0 & F_HIDDEN) != 0
	inCommercial = (f0 & F_COMMERCIAL) != 0
	ads = (f0 & F_ADS) != 0
	sprinting = (f0 & F_SPRINTING) != 0
	var f1: int = s.f1
	upgraded = (f1 & F_UPGRADED) != 0
	_weaponVis = (f1 & F_WEAPONVIS) != 0
	_iframes = (f1 & F_IFRAMES) != 0
	busy = (data.decode_u8(70) & F_BUSY) != 0
	if s.snap:
		_snapTo(s)

func _snapTo(s: Dictionary) -> void:
	# drop the older snapshots: the next frames play from this one
	for i in range(1, _count):
		var o: Dictionary = _ring[(_head - 1 - i + RING * 2) % RING]
		o.t = -INF
	pos = s.pos
	yaw = s.yaw
	bodyYaw = s.bodyYaw
	history.clear()

# Plays the buffer INTERP_DELAY behind the sender's clock.
func _sample(now: float) -> void:
	if _count == 0:
		return
	var rt := now - _offset - INTERP_DELAY
	var newest: Dictionary = _ring[(_head - 1 + RING) % RING]
	var s0 = null
	var s1 = null
	if rt >= float(newest.t):
		s0 = newest
	else:
		for i in range(1, _count):
			var s: Dictionary = _ring[(_head - 1 - i + RING * 2) % RING]
			if float(s.t) == -INF:
				break
			if float(s.t) <= rt:
				s0 = s
				s1 = _ring[(_head - i + RING * 2) % RING]
				break
		if s0 == null:
			# older than the buffer (just joined / after a snap): the oldest usable one
			for i in range(_count - 1, -1, -1):
				var s: Dictionary = _ring[(_head - 1 - i + RING * 2) % RING]
				if float(s.t) != -INF:
					s0 = s
					break
	if s0 == null:
		return
	if s1 == null or s1.snap:
		var ex := clampf(rt - float(s0.t), 0.0, EXTRAP_MAX) if s1 == null else 0.0
		_apply(s0, s0, 0.0, ex)
		return
	var span := float(s1.t) - float(s0.t)
	var k := clampf((rt - float(s0.t)) / span, 0.0, 1.0) if span > 1e-5 else 1.0
	_apply(s0, s1, k, 0.0)

func _apply(s0: Dictionary, s1: Dictionary, k: float, ex: float) -> void:
	var p0: Vector3 = s0.pos
	var v0: Vector3 = s0.vel
	if ex > 0.0:
		pos = p0 + v0 * ex
		if (s0.f1 & A_GROUNDED) != 0:
			pos.y = p0.y
	else:
		pos = p0.lerp(s1.pos, k)
	vel = v0.lerp(s1.vel, k)
	yaw = lerp_angle(float(s0.yaw), float(s1.yaw), k)
	pitch = lerpf(float(s0.pitch), float(s1.pitch), k)
	bodyYaw = lerp_angle(float(s0.bodyYaw), float(s1.bodyYaw), k)
	aimPoint = (s0.aim as Vector3).lerp(s1.aim, k)
	var a := anim
	a.speed = lerpf(float(s0.speed), float(s1.speed), k)
	a.aimPitch = lerpf(float(s0.aimPitch), float(s1.aimPitch), k)
	a.aimYaw = lerpf(float(s0.aimYaw), float(s1.aimYaw), k)
	a.turn = lerpf(float(s0.turn), float(s1.turn), k)
	a.legYaw = lerpf(float(s0.legYaw), float(s1.legYaw), k)
	var u0: PackedFloat32Array = s0.u8
	var u1: PackedFloat32Array = s1.u8
	for i in ANIM_U8.size():
		a[ANIM_U8[i]] = lerpf(u0[i], u1[i], k)
	var f1: int = s1.f1 if k >= 0.5 else s0.f1
	a.sprint = (f1 & A_SPRINT) != 0
	a.grounded = (f1 & A_GROUNDED) != 0
	a.aiming = (f1 & A_AIMING) != 0
	a.down = (f1 & A_DOWN) != 0
	a.back = (f1 & A_BACK) != 0
	grounded = a.grounded
	_setWeapon()

# ------------------------------------------------------------------------------------------------ held weapon
func _setWeapon() -> void:
	if weaponId == _wId and upgraded == _wUp and weaponSignal == _wSig:
		return
	_wId = weaponId
	_wUp = upgraded
	_wSig = weaponSignal
	var key := "" if weaponId == "" else "%s|%d|%s" % [weaponId, 1 if upgraded else 0, weaponSignal]
	_weaponKey = key
	if hero == null:
		return
	var Wp = game.weapons
	if Wp != null and Wp.has_method("buildRemoteHeld"):
		_ownHeld = false
		setWeaponModel(Wp.buildRemoteHeld(self, weaponId, upgraded, weaponSignal) if key != "" else null)
		return
	_ownHeld = true
	_detachWeapon()
	if key == "":
		return
	var h = _held.get(key)
	if h == null:
		var def = WD.weaponDef(weaponId, upgraded)
		if def == null:
			return
		var m: Node3D = WM.buildModel(weaponId, upgraded, weaponSignal if weaponSignal != "" else null, game)
		var holder := DAU.node3d("weaponHolder")
		holder.quaternion = W.RH_FRAME.inverse()
		var sc: float = float(def.get("scale", 1.0)) if def.get("scale") else 1.0
		holder.scale = Vector3(sc, sc, sc)
		holder.add_child(m)
		PlayerScript.setShadowCasting(holder, 0.08)
		DAU.setLayerRecursive(holder, LAYER)
		var u := DAU.ud(m)
		var mz = DAU.byName(m, "muzzle")
		h = {"holder": holder, "model": m, "def": def,
			"leftHand": W.v3a(u.leftHand) if u.get("leftHand") != null else Vector3(0, 0, -0.15),
			"butt": W.v3a(u.butt) if u.get("butt") != null else Vector3(0, 0.08, 0.05),
			"muzzle": mz as Node3D if mz is Node3D else null}
		_held[key] = h
	hero.slots.handR.add_child(h.holder)
	weaponModel = h.holder
	_muzzle = h.muzzle

func _detachWeapon() -> void:
	if weaponModel != null and is_instance_valid(weaponModel) and weaponModel.get_parent() != null:
		weaponModel.get_parent().remove_child(weaponModel)
	weaponModel = null
	_muzzle = null

# Reduced weapons.gd _pose: right hand on the grip, left hand on the weapon, aimed at aimPoint. Runs from
# animator.postUpdate (skipped while another system drives animator.override, unless called as weaponPose).
func _poseWeapon(rg, dt: float, forced: bool) -> void:
	if animator == null or hero == null or not alive or downed or offAir:
		return
	if not forced:
		var ov = animator.override
		if ov != null and not (ov is Callable and not (ov as Callable).is_valid()):
			return
	if not _ownHeld:
		return
	var h = _held.get(_weaponKey)
	if h == null or weaponModel == null or not weaponModel.visible:
		return
	var J: Dictionary = rg.joints
	if not (J.chest as Node3D).is_inside_tree():
		return
	var def: Dictionary = h.def
	var hold: Dictionary = W.HOLDS.get(def.get("hold") if def.get("hold") else "pistol", W.HOLDS.pistol)
	var dh = rg.dims.get("height") if rg.dims is Dictionary else null
	var hs: float = (float(dh) if dh else 1.8) / 1.8
	var e := 1.0 - exp(-dt * 14.0)
	_adsW += ((1.0 if ads else 0.0) - _adsW) * e
	_sprintW += ((1.0 if (sprinting and float(anim.speed) > 0.5) else 0.0) - _sprintW) * (1.0 - exp(-dt * 8.0))
	_busyW += ((1.0 if float(anim.melee) > 0.0 else 0.0) - _busyW) * e
	var adsK := _adsW
	var sprint := _sprintW
	var busyK := _busyW
	# upper body: bladed stance for long guns, pitch follow
	var blade: float = float(hold.chest) * (1.0 - sprint)
	J.chest.rotation.y += blade
	J.head.rotation.y -= blade * 0.8
	J.spine.rotation.x += pitch * 0.12 * (1.0 - sprint)
	var M := ((J.shoulderR as Node3D).global_position + (J.shoulderL as Node3D).global_position) * 0.5
	var qBody := Quaternion(UP, model.rotation.y)
	var aimDir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var a := aimPoint - M
	if a.length_squared() < 16.0 or a.dot(aimDir) < 0.0:
		a = aimDir * 8.0
	var qAim := Basis.looking_at(a.normalized(), UP).get_rotation_quaternion()
	var off: Vector3 = W.v3a(hold.hip).lerp(W.v3a(hold.ads), adsK) * hs
	var qGun := qAim
	if hold.get("pitch"):
		qGun = qGun * Quaternion(Vector3(1, 0, 0), float(hold.pitch) * (1.0 - adsK))
	var grip: Vector3
	if hold.mode == "butt":
		var sc: float = (h.holder as Node3D).scale.x
		grip = M + qAim * off - qGun * ((h.butt as Vector3) * sc)
	else:
		grip = M + qAim * off
	var rc := float(anim.recoil)
	if rc > 0.0:
		grip += qGun * Vector3(0, 0, 0.05 * rc * hs)
		qGun = qGun * W.qEuler(0.22 * rc, 0, 0)
	var u := float(anim.reload)
	if u > 0.0:
		var rl := W.smooth(0, 0.14, u) * (1.0 - W.smooth(0.86, 1, u))
		grip += qAim * (Vector3(-0.08, -0.07, 0.1) * (rl * hs))
		qGun = qGun * W.qEuler(0.45 * rl, 0.25 * rl, -0.55 * rl)
	if sprint > 0.001:
		var c := qBody * (Vector3(0.12, -0.36, -0.2) * hs) + M
		grip = grip.lerp(c, sprint)
		qGun = qGun.slerp(qBody * W.qEuler(-0.55, 0.75, 0.25), sprint)
	if busyK > 0.001:
		var c := qBody * (Vector3(0.2, -0.28, -0.06) * hs) + M
		grip = grip.lerp(c, busyK)
		qGun = qGun.slerp(qAim * W.qEuler(-0.6, 0.55, 0.2), busyK)
	var qHand := qGun * W.RH_FRAME
	var slotR: Vector3 = hero.slots.handR.position
	W.solveArm(J.shoulderR, J.elbowR, J.handR, grip - qHand * slotR, qBody * W.v3a(hold.poleR), qHand)
	# left hand on the weapon (slides back along it when out of reach)
	if busyK > 0.5:
		return
	var reach := W.armReach(J.shoulderL, J.elbowL, J.handL) * 0.985
	var shoulderL: Vector3 = (J.shoulderL as Node3D).global_position
	var mt: Transform3D = (h.model as Node3D).global_transform
	var lh: Vector3 = h.leftHand
	var target := mt * lh
	if target.distance_to(shoulderL) > reach + 0.02:
		var b := Vector3(lh.x, lh.y, maxf(lh.z, -0.02))
		var lo := 0.0
		var hi := 1.0
		for i in 8:
			var m := (lo + hi) / 2.0
			if (mt * b.lerp(lh, m)).distance_to(shoulderL) <= reach:
				lo = m
			else:
				hi = m
		target = mt * b.lerp(lh, lo)
	var qL: Quaternion = mt.basis.get_rotation_quaternion() * W.LH_FRAMES.get(hold.lh, W.LH_FRAMES.under)
	var slotL: Vector3 = hero.slots.handL.position
	W.solveArm(J.shoulderL, J.elbowL, J.handL, target - qL * slotL, qBody * W.v3a(hold.poleL), qL)

# ------------------------------------------------------------------------------------------------ player-like API
func hurt(dmg: float, fromPos = null) -> bool:
	if not alive or downed or offAir or hidden or inCommercial or invulnerable or _iframes or _hitCool > 0.0:
		return false
	if game.state != "playing":
		return false
	var net = game.get("net")
	if net == null or not net.active:
		return false
	_hitCool = float(Config.T.player.iframes)
	var sys := "player" if game.player != null and game.player.has_method("net_hurt") else "net"
	net.toPeer(peerId, sys, "hurt", [float(dmg), fromPos if fromPos is Vector3 else null])
	return true   # (the flinch + grunt come with the owner's next snapshots)

func knockback(vec: Vector3) -> void:
	var net = game.get("net")
	if net == null or not net.active or offAir or not alive:
		return
	var sys := "player" if game.player != null and game.player.has_method("net_knockback") else "net"
	net.toPeer(peerId, sys, "knockback", [vec])

func heal(_n: float = 0.0) -> void:
	pass

func down() -> void:
	pass

func revive(_selfRevive: bool = false) -> void:
	pass

# Attaches `group` (or nothing) in the right hand (Player.setWeaponModel minus the hero fade). An externally built
# model (mp-combat) is not freed by this object when replaced: its owner keeps / frees it.
func setWeaponModel(group = null) -> void:
	_detachWeapon()
	if group == null or hero == null or not (group is Node3D):
		return
	var n := group as Node3D
	PlayerScript.setShadowCasting(n, 0.08)
	DAU.setLayerRecursive(n, LAYER)
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	hero.slots.handR.add_child(n)
	weaponModel = n
	var m = DAU.byName(n, "muzzle")
	_muzzle = m as Node3D if m is Node3D else null

func forward(_out = null) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func aimRay(_outOrigin = null, _outDir = null) -> Dictionary:
	var eye := pos + Vector3(0.0, height * 0.92, 0.0)
	var d := aimPoint - eye
	if d.length_squared() < 0.01:
		d = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	return {"origin": eye, "dir": d.normalized()}

func muzzle(_out = null) -> Vector3:
	var m: Node3D = _muzzle
	if m == null and hero != null:
		m = hero.slots.handR
	if m == null or not is_instance_valid(m) or not m.is_inside_tree():
		return Vector3(pos.x, pos.y + 1.3, pos.z)
	return m.global_position

func headPos() -> Vector3:
	if hero != null:
		var s = hero.slots.get("head")
		if s is Node3D and is_instance_valid(s) and (s as Node3D).is_inside_tree():
			return (s as Node3D).global_position
	return pos + Vector3(0.0, height + 0.08, 0.0)

func teleport(x: float, z: float, yaw_ = null) -> void:
	var col = game.level.get("col") if game.level != null else null
	var f: float = col.floorAt(x, z, 50.0) if col != null else -INF
	pos = Vector3(x, f if f > -INF else 0.0, z)
	if yaw_ != null:
		yaw = float(yaw_)
		bodyYaw = yaw
	vel = Vector3.ZERO
	for s in _ring:
		s.t = -INF
	_count = 0
	if game.level != null:
		var a = game.level.areaAt(x, z)
		if a != null and a != "":
			area = a
	if model != null:
		model.position = pos
		model.rotation.y = bodyYaw
	history.clear()
