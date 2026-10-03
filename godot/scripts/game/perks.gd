# DEAD AIR — perks: the 5 sponsors' effects, costumes and INSTANT REPLAY (port of src/game/perks.js; ARCHITECTURE §10,
# GDD §4 costume slots, §11, §14 "costume = perk display", §18.9). Owned by the sponsors agent (with sponsors.gd,
# scripts/ui/commercial.gd).
#
# API (game.perks)
#   list (owned perk ids, purchase order) · max (T.perks.limit = 4; INF after the Morning Show) · gold (bool)
#   has(id) · give(id, { pop = true, emit = true, costume = true }) -> bool   (debug.perk(id) = give: instant, no commercial)
#   remove(id, { poof = true }) -> bool (alias lose(id))   emits perk:lose {perkId}
#   onLethal() -> bool   called by player.hurt at 0 HP: with Replay-Ade (or the gold one, once per round) it plays
#                        INSTANT REPLAY and returns true; otherwise false (the player dies)
#   attachCostume(id, { pop }) / detachCostume(id, { poof })   costume pieces on the hero slots (sponsors.gd pops it
#                        during the commercial's star wipe, then calls give(id, { costume:false, pop:false }))
#   setGold(on) · morningShow()  (Sign-Off reward: every sponsor free + permanent, gold-leaf costumes, no limit, the
#                        gold Replay-Ade triggers once per round and is never consumed)
#   replayActive (bool) · debugReplay() (forces an Instant Replay now, owned or not)
# EFFECTS (exact, GDD §11) are written into game.player.mods (composable: multiplicative mods are divided back out on loss):
#   wobble_up      maxHealth 300 (T.player.hpWobble), knockback ×0.5, noFlinch (hit flinch replaced by a damped jelly
#                  squash-stretch of the whole hero + helmet, "bwoing" by audio.gd), faint green jelly rim light on the
#                  hero materials. Tube-grenade self-damage ×0.5 is applied by weapons.gd (perks.has).
#   jump_cut       reloadSpeed ×0.5 and swapSpeed ×0.5 (time multipliers), throwSpeed 1.3 (weapons.gd also reads has()).
#   roller_boogie  unlimitedSprint (+ unlimitedStamina alias), moveSpeed/sprintSpeed ×1.08 (4.97 / 7.34 m/s),
#                  sprintToFire 0.10, reloadWhileSprinting; the sprint becomes skating strides (push and glide, the
#                  hero rides 0.118 m higher on the wheels) with a faint sparkle trail and the skate_roll loop.
#   double_vision  fireRate ×1.2, ghostBullets (weapons.gd does the +50 % ghost image, doubled tracers, the cyan/magenta
#                  gun fringe and the Zapper chain), a smile "ting" + glint on the toothbrush every 6 s.
#   replay_ade     INSTANT REPLAY (below). At most 3 purchases per game (sponsors.gd counts purchases, sold-out set).
# INSTANT REPLAY: 0.3 s world pause + the sports-replay "13" wipe (commercial.gd) and the HUD "◀◀" bug (replay:start /
#   replay:end); the hero rewinds along player.history (newest -> the oldest walkable sample, up to 4 s) at 4× (1.0 s)
#   with cyan afterimage ghosts, VHS tracking lines, health rewinding 0 -> full, while the world runs at time.scale 0.1;
#   lands at full HP with a shockwave (zombies within 5 m knocked back 3 m + stunned 2 s), invulnerable from the trigger
#   until 2 s after landing; Replay-Ade is consumed (wristbands vanish in a puff, the whistle drops and bounces) unless
#   gold. Emits player:revive {selfRevive:true} and perk:lose {perkId:'replay_ade'}. Carried EE items are untouched.
#   TEMPORARY STATE: the replay's VHS look is a render fx layer (render.setFx('replay', ...) refreshed every frame with
#   a short ttl), never a write to render.post; time.scale is restored only while it still holds the value the replay
#   wrote. _endReplay() is the ONE cleanup path (fx layer, time.scale, overlay, ghosts, control, replay:end) and runs
#   on landing, reset, menu/game over/victory, an exception inside the replay and a stuck-replay watchdog.
# Also exported: PERK_IDS, COSTUMES, Sparkles (a tiny real-dt particle pool: world FX freeze at time.scale 0),
#   cloneHero(hero, skip) / copyPose(hero, ghost) (frozen pose copies for ghosts and duplicates).
#
# PORT NOTES
#   * warmup() (Game.precompile samples) is engine plumbing: not ported.
#   * _wrapAnimator wraps the animator's assignable update (rig.gd animator.updateFn: GDScript cannot rebind a
#     method), exactly like the JS `a.update = function (dt, st) { orig(dt, st); self._skatePose(...) }`.
#   * The dropped referee whistle is a Blender asset (blender/runtime/sponsors.py -> assets/runtime/sponsors/whistle.glb).
#   * JS try/catch inside the replay: a replay that errors keeps being stepped until the watchdog (6 s) finishes it.
#   * Renames (§3.2): none. player.history.get(i) is called as history.get_(i) (the player port's rename of `get`).
# MP (RECONCILE R4/R5; behind net.inGame — solo unchanged): perks are per player and local (mods, max 4, Replay-Ade
#   limits). The loadout goes to the teammates as net ext "perks" ([perkIds]) + "perksGold" (bool); every peer dresses
#   the other avatars (_syncRemote on net:ext / net:avatar: costume pieces on RemotePlayer.hero slots, render layer 1,
#   no hero fade, pop / poof sparkles, skates lift). loadoutOf(peer) / remoteHas(peer, id); clearAll(opts) (bleed-out:
#   every perk with a poof; gold Morning Show perks are permanent unless opts.force) / loseAll(). Instant Replay never
#   writes time.scale in MP (the hero alone rewinds while the world runs); control lock / protection go through
#   player.lock / protect("replay", on) when they exist; the landing shockwave is perks.net_shockwave(pos) (owner ->
#   host: knockback + stun there) and perks.net_replayFx(kind, pos, consumed) (owner -> others: 'start' rewind sound,
#   'land' ring + bursts). perk:gain / perk:lose / replay:start / replay:end / player:revive carry `by` in MP.
#   Teammates' looks (mp-onair, _updateRemotes): Roller Boogie skating strides on their animators (+ sparkle trail,
#   skate roll at their feet) while they sprint, Wobble-Up jelly rim on their materials + jelly spring (hits, jumps,
#   landings), Instant Replay afterimages along their rewind ('start' .. 'land') and the whistle drop when their
#   Replay-Ade is consumed; _forgetRemote(id) undoes them (leave / rebuilt avatar / new game).
extends RefCounted

const Commercial = preload("res://scripts/ui/commercial.gd")

const PERK_IDS := ["replay_ade", "wobble_up", "jump_cut", "roller_boogie", "double_vision"]
const COSTUMES := {
	"replay_ade": "costume_wristbands", "wobble_up": "costume_jelly_helmet", "jump_cut": "costume_oven_mitt",
	"roller_boogie": "costume_skates", "double_vision": "costume_toothbrush",
}
const SKATE_LIFT := 0.118
const REWIND_SCALE := 0.1            # world speed during the rewind (only the replay ever uses it)
const REPLAY_FX := "replay"          # render fx layer owner
const REPLAY_FX_TTL := 0.25          # s: the layer drops by itself if the replay stops refreshing it
const REPLAY_WATCHDOG := 6.0         # s: a replay still running after this (no debug hold) is force-finished
const JELLY_RIM := Color("#6CFF8A")
const TAU := PI * 2.0

static func _clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func _smooth(a: float, b: float, x: float) -> float:
	var t := _clamp01((x - a) / (b - a))
	return t * t * (3.0 - 2.0 * t)

static func _easeOutBack(x: float, k: float = 2.2) -> float:
	return 1.0 + (k + 1.0) * pow(x - 1.0, 3.0) + k * pow(x - 1.0, 2.0)

static func _wrap(a: float) -> float:
	return atan2(sin(a), cos(a))

# Field of a Dictionary or Object (the JS `a?.b`).
static func _f(o, k: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		return o.get(k, def)
	if o is Object:
		var v = o.get(k)
		return def if v == null else v
	return def

# Method call guarded like the JS `a?.m?.(...)`.
static func _m(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Object:
		if o.has_method(m):
			return o.callv(m, args)
		var c = o.get(m)
		if c is Callable and c.is_valid():
			return c.callv(args)
		return null
	if o is Dictionary and o.get(m) is Callable:
		return o[m].callv(args)
	return null

static func _wpos(n: Node3D) -> Vector3:
	if n.is_inside_tree():
		return n.global_position
	var x := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			x = (p as Node3D).transform * x
		p = p.get_parent()
	return x.origin

static func _gxf(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.global_transform
	var x := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

# THREE.Color (colour-managed, linear) from a CSS colour.
static func _lin(c) -> Color:
	var s := DAU.color(c)
	return Color(DAU.srgbToLinear(s.r), DAU.srgbToLinear(s.g), DAU.srgbToLinear(s.b), s.a)

# Frees a node that left the scene for good (JS lets the GC take it).
static func _drop(n) -> void:
	if n is Node and is_instance_valid(n):
		DAU.detach(n)
		n.queue_free()

# ============================================================================================ Sparkles
# Real-dt particle pool (camera-facing quads): 'star' (additive glow stars) and 'puff' (soft discs). Used by the
# commercial gags (the world is frozen there, so fx particles would not move) and the costume pops.
static func starTexture():
	return Commercial.canvasTex(64, 64, func(x, _w, _h):
		var g = x.createRadialGradient(32, 32, 0, 32, 32, 32)
		g.addColorStop(0, "rgba(255,255,255,1)")
		g.addColorStop(0.18, "rgba(255,255,255,0.85)")
		g.addColorStop(0.45, "rgba(255,255,255,0.12)")
		g.addColorStop(1, "rgba(255,255,255,0)")
		x.fillStyle = g
		x.fillRect(0, 0, 64, 64)
		x.fillStyle = "rgba(255,255,255,0.95)"
		x.beginPath()
		for i in 8:
			var a := (i / 8.0) * TAU - PI / 2.0
			var r := 5.0 if i % 2 else 31.0
			var px := 32.0 + cos(a) * r
			var py := 32.0 + sin(a) * r
			if i:
				x.lineTo(px, py)
			else:
				x.moveTo(px, py)
		x.closePath()
		x.fill())

static func puffTexture():
	return Commercial.canvasTex(64, 64, func(x, _w, _h):
		var g = x.createRadialGradient(28, 26, 2, 32, 32, 31)
		g.addColorStop(0, "rgba(255,255,255,1)")
		g.addColorStop(0.6, "rgba(240,236,228,0.9)")
		g.addColorStop(0.85, "rgba(220,214,204,0.5)")
		g.addColorStop(1, "rgba(220,214,204,0)")
		x.fillStyle = g
		x.fillRect(0, 0, 64, 64))

class Pool extends RefCounted:
	var cap: int
	var n := 0
	var mesh: MultiMeshInstance3D
	var mm: MultiMesh
	var p := PackedVector3Array()
	var v := PackedVector3Array()
	var life := PackedFloat32Array()
	var age := PackedFloat32Array()
	var size := PackedFloat32Array()
	var grav := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var spin := PackedFloat32Array()
	var grow := PackedFloat32Array()
	var col: Array = []

	func _init(scene: Node, mat: Material, capacity: int) -> void:
		cap = capacity
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = cap
		mm.visible_instance_count = 0
		mesh = MultiMeshInstance3D.new()
		mesh.name = "sparkles"
		mesh.multimesh = mm
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.extra_cull_margin = 16384.0      # frustumCulled = false
		mesh.visible = false
		for arr in [p, v]:
			arr.resize(cap)
		for arr in [life, age, size, grav, drag, spin, grow]:
			arr.resize(cap)
		col.resize(cap)
		for i in cap:
			col[i] = Color(1, 1, 1)
		if scene:
			scene.add_child(mesh)

	func add(x: float, y: float, z: float, vx: float, vy: float, vz: float, lf: float, sz: float, gr: float, dg: float, color: Color, sp: float, gw: float) -> void:
		var i := n
		if n < cap:
			n += 1
		else:
			i = int(floor(randf() * cap))
		p[i] = Vector3(x, y, z)
		v[i] = Vector3(vx, vy, vz)
		life[i] = lf
		age[i] = 0.0
		size[i] = sz
		grav[i] = gr
		drag[i] = dg
		col[i] = color
		spin[i] = sp
		grow[i] = gw

	func update(dt: float, cam: Node3D, additive: bool) -> void:
		if n == 0:
			if mesh.visible:
				mesh.visible = false
				mm.visible_instance_count = 0
			return
		var q := Quaternion.IDENTITY
		if cam:
			q = (cam.global_transform.basis if cam.is_inside_tree() else cam.transform.basis).get_rotation_quaternion()
		var i := 0
		while i < n:
			age[i] += dt
			if age[i] >= life[i]:
				n -= 1
				var j := n
				if i != j:
					p[i] = p[j]
					v[i] = v[j]
					life[i] = life[j]
					age[i] = age[j]
					size[i] = size[j]
					grav[i] = grav[j]
					drag[i] = drag[j]
					col[i] = col[j]
					spin[i] = spin[j]
					grow[i] = grow[j]
				continue
			var d := exp(-drag[i] * dt)
			var vv := v[i]
			vv.x *= d
			vv.y = vv.y * d - grav[i] * dt
			vv.z *= d
			v[i] = vv
			p[i] = p[i] + vv * dt
			i += 1
		for k2 in n:
			var k := age[k2] / life[k2]
			var fade := (1.0 - k) * minf(1.0, k * 8.0 + 0.3) if additive else 1.0
			var s: float = size[k2] * ((0.6 + 0.4 * sin(minf(1.0, k * 3.0) * PI * 0.5)) * (1.0 - k * 0.3) if additive else (1.0 + grow[k2] * k) * (1.0 - _smooth(0.6, 1.0, k)))
			var qq := q
			if spin[k2] != 0.0:
				qq = q * Quaternion(Vector3(0, 0, 1), spin[k2] * age[k2])
			mm.set_instance_transform(k2, Transform3D(Basis(qq).scaled(Vector3(s, s, s)), p[k2]))
			var c: Color = col[k2]
			mm.set_instance_color(k2, Color(c.r * fade, c.g * fade, c.b * fade, 1.0))
		mm.visible_instance_count = n
		mesh.visible = true

	func clear() -> void:
		n = 0
		mm.visible_instance_count = 0
		mesh.visible = false

	static func _smooth(a: float, b: float, x: float) -> float:
		var t := clampf((x - a) / (b - a), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)

class Sparkles extends RefCounted:
	var star: Pool
	var puff: Pool

	func _init(game, cap: int = 180) -> void:
		var PerksLib = load("res://scripts/game/perks.gd")
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = PerksLib.starTexture()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sm.vertex_color_use_as_albedo = true
		sm.vertex_color_is_srgb = false
		sm.disable_fog = true
		sm.render_priority = 5
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_texture = PerksLib.puffTexture()
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		pm.vertex_color_use_as_albedo = true
		pm.vertex_color_is_srgb = false
		pm.disable_fog = true
		pm.render_priority = 5
		star = Pool.new(game.scene, sm, cap)
		puff = Pool.new(game.scene, pm, int(round(cap / 2.0)))

	# o: { count, color|colors, speed, size, life, gravity, drag, kind:'star'|'puff', dir:Vector3, cone (0..1), spread (m), spin, grow }
	func emit(pos: Vector3, o: Dictionary = {}) -> void:
		var pool: Pool = puff if o.get("kind") == "puff" else star
		var n: int = int(o.get("count", 8))
		var cols: Array = o.get("colors") if o.get("colors") else [o.get("color", "#FFE27A")]
		for i in n:
			var dx := randf() * 2.0 - 1.0
			var dy := randf() * 2.0 - 1.0
			var dz := randf() * 2.0 - 1.0
			var L := Vector3(dx, dy, dz).length()
			if L == 0.0:
				L = 1.0
			dx /= L
			dy /= L
			dz /= L
			if o.get("dir") != null:
				var dir: Vector3 = o.dir
				var c: float = o.get("cone", 0.4)
				dx = dir.x + dx * c
				dy = dir.y + dy * c
				dz = dir.z + dz * c
				var L2 := Vector3(dx, dy, dz).length()
				if L2 == 0.0:
					L2 = 1.0
				dx /= L2
				dy /= L2
				dz /= L2
			var sp: float = float(o.get("speed", 2.0)) * (0.5 + randf() * 0.7)
			var sr: float = o.get("spread", 0.0)
			var spinV: float = float(o.spin) if o.get("spin") != null else (randf() - 0.5) * 6.0
			pool.add(pos.x + (randf() - 0.5) * sr, pos.y + (randf() - 0.5) * sr, pos.z + (randf() - 0.5) * sr,
				dx * sp, dy * sp, dz * sp, float(o.get("life", 0.7)) * (0.7 + randf() * 0.6), float(o.get("size", 0.12)) * (0.7 + randf() * 0.6),
				float(o.get("gravity", 1.5)), float(o.get("drag", 2.2)), _linc(cols[i % cols.size()]), spinV, float(o.get("grow", 1.2)))

	func update(dt: float, cam: Node3D) -> void:
		star.update(dt, cam, true)
		puff.update(dt, cam, false)

	func clear() -> void:
		star.clear()
		puff.clear()

	static func _linc(c) -> Color:
		var s := DAU.color(c)
		return Color(DAU.srgbToLinear(s.r), DAU.srgbToLinear(s.g), DAU.srgbToLinear(s.b), 1.0)

# ============================================================================================ hero clones
static func _parallel(a: Node, b: Node, fn: Callable) -> void:
	fn.call(a, b)
	var n := mini(a.get_child_count(), b.get_child_count())
	for i in n:
		_parallel(a.get_child(i), b.get_child(i), fn)

static func _isSkinned(m: MeshInstance3D) -> bool:
	if m.skin != null:
		return true
	if m.mesh != null and m.mesh.get_surface_count() > 0 and m.mesh is ArrayMesh:
		return ((m.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES) != 0
	return false

# Bounding-sphere radius of a mesh (its AABB half diagonal).
static func _radius(m: MeshInstance3D) -> float:
	if m.mesh == null:
		return 0.0
	return m.mesh.get_aabb().size.length() * 0.5

# Frozen copy of the hero model (own joints, skinned meshes bound to the copy's skeleton). skip: objects left out
# (held weapon). Returns { group, root, joints{name->Node3D}, meshes[], hero, skeletons[[src, dup]] } with the source
# materials (swap them yourself).
static func cloneHero(hero, skip: Array = []) -> Dictionary:
	var src: Node3D = hero.group
	var detached := []
	for s in skip:
		if s is Node and s.get_parent():
			var par: Node = s.get_parent()
			detached.append([s, par, s.get_index()])
			par.remove_child(s)
	var group: Node3D = src.duplicate(0)      # no scripts, signals or groups: a frozen copy
	var map := {}
	_parallel(src, group, func(a, b): map[a] = b)
	# the JS clone runs with every userData emptied (the copies carry none)
	DAU.traverse(group, func(o):
		if o.has_meta("userData"):
			o.remove_meta("userData"))
	for e in detached:
		e[1].add_child(e[0])
		e[1].move_child(e[0], mini(e[2], e[1].get_child_count() - 1))
	var meshes := []
	var skeletons := []
	for a in map:
		var b = map[a]
		if b is Skeleton3D:
			skeletons.append([a, b])
		if b is MeshInstance3D:
			var mi := b as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 16384.0          # frustumCulled = false
			mi.layers = 1                            # layers.set(0)
			meshes.append(mi)
	var joints := {}
	var rig = hero.rig
	var J = _f(rig, "joints", {})
	for name in J:
		joints[name] = map.get(J[name])
	return {"group": group, "root": map.get(_f(rig, "root")), "joints": joints, "meshes": meshes, "hero": hero, "skeletons": skeletons}

static func copyPose(hero, ghost: Dictionary) -> void:
	var J = hero.rig.joints
	for n in ghost.joints:
		var a = J.get(n) if J is Dictionary else _f(J, n)
		var b = ghost.joints[n]
		if a == null or b == null:
			continue
		b.transform = a.transform
	var r = hero.rig.root
	if ghost.root and r:
		ghost.root.transform = r.transform
	ghost.group.transform = hero.group.transform
	# a skeleton the Godot character runtime drives from the joints: copy the bone poses as well
	for pr in ghost.get("skeletons", []):
		var s: Skeleton3D = pr[0]
		var d: Skeleton3D = pr[1]
		if not is_instance_valid(s) or not is_instance_valid(d):
			continue
		for i in mini(s.get_bone_count(), d.get_bone_count()):
			d.set_bone_pose(i, s.get_bone_pose(i))

# ============================================================================================ Perks
var game
var list: Array = []
var max: float = 4
var gold := false
var replayActive := false
var _costumes := {}               # perkId -> { pieces:[{obj, slot, scale}], gold }
var _applied := {"move": 1.0, "sprint": 1.0, "fire": 1.0, "reload": 1.0, "swap": 1.0, "knock": 1.0}
var _rim := {}                    # material -> { param, color, strength }
var _rimHero = null
var _jelly := {"x": 0.0, "v": 0.0}
var _skate := {"w": 0.0, "phase": 0.0, "sparkT": 0.0, "loop": null}
var _wrapped := {}
var _ting := 3.0
var _pops: Array = []             # costume pop animations { obj, base, t }
var _whistles: Array = []
var _rings: Array = []
var _ghosts: Array = []           # replay afterimages (pool)
var _ghostHero = null
var _invulnT := 0.0
var _goldReplayRound := -1
var _scaleSet = null              # the time.scale value the replay wrote last (null: it holds none)
var _fxKnobs := {"roll": 0.0, "chroma": 0.0, "scanlines": 0.0, "saturation": 1.0}   # the replay's render fx layer
var sparkles = null
var debugHoldAt = null
var _rp = null
var _ringMat = null
var _ringGeo: ArrayMesh = null

var _remote := {}                 # MP: peerId -> {hero, gold, costumes: {perkId -> pieces}} (teammates' costumes)
var _batch := false               # MP: clearAll() sends one loadout at the end
var _rGhosts := {}                # MP: peer -> {hero, list (_makeGhosts), t, ghostT, on} teammates' replay afterimages
var _rWrapped := {}               # MP: teammates' animators wrapped for the skating strides (instance id -> true)

func _init(g) -> void:
	game = g
	max = float(Config.T.perks.limit)

func _net():
	return game.get("net") if game != null else null

func _mp() -> bool:
	var n = _net()
	return n != null and bool(n.inGame)

# MP cutscene lock / protection of the local player (mp-players' keyed API; plain fields without it).
func _lock(p, on: bool) -> void:
	if p == null:
		return
	if _mp() and p.has_method("lock"):
		p.lock("replay", on)
	else:
		p.controlLocked = on

func _protect(p, on: bool) -> void:
	if p == null:
		return
	if _mp() and p.has_method("protect"):
		p.protect("replay", on)
	else:
		p.invulnerable = on

# Event payload: MP events carry the acting peer (RECONCILE R7); solo payloads stay as they were.
func _ev(d: Dictionary) -> Dictionary:
	if _mp():
		d["by"] = int(_net().localId)
	return d

func init() -> void:
	var g = game
	var ev = g.events
	sparkles = Sparkles.new(g)
	# MP: teammates' perk loadouts (net ext "perks") dress their avatars
	ev.on("net:ext", func(p = null):
		if p is Dictionary and (p.get("key") == "perks" or p.get("key") == "perksGold"):
			_syncRemote(int(p.get("id", 0))))
	ev.on("net:avatar", func(p = null):
		if p is Dictionary:
			_syncRemote(int(p.get("id", 0))))
	ev.on("net:peer", func(p = null):
		if p is Dictionary and not p.get("joined", true):
			_forgetRemote(int(p.get("id", 0))))
	ev.on("player:hurt", func(_p = null): _onHurt())
	ev.on("player:land", func(p = null):
		if has("wobble_up"):
			_jelly.v -= minf(4.0, float(_f(p, "speed", 6.0)) * 0.35))
	ev.on("player:jump", func(_p = null):
		if has("wobble_up"):
			_jelly.v += 1.6)
	ev.on("state", func(e = null):
		if e and (e.to == "menu" or e.to == "gameover" or e.to == "victory"):
			_endReplay(true))

func reset() -> void:
	_endReplay(true)
	for id in _costumes.keys():
		detachCostume(id, {"poof": false})
	_restoreRim()
	list.clear()
	max = float(Config.T.perks.limit)
	gold = false
	_goldReplayRound = -1
	_applied = {"move": 1.0, "sprint": 1.0, "fire": 1.0, "reload": 1.0, "swap": 1.0, "knock": 1.0}
	_jelly.x = 0.0
	_jelly.v = 0.0
	_skate.w = 0.0
	_skateLoop(false)
	_ting = 3.0
	_pops.clear()
	for w in _whistles:
		_drop(w.obj)
	_whistles.clear()
	for r in _rings:
		_drop(r.mesh)
	_rings.clear()
	_invulnT = 0.0
	if sparkles:
		sparkles.clear()
	var hero = _f(game.player, "hero")
	if hero:
		hero.group.position.y = 0.0
		hero.group.scale = Vector3.ONE
	for id in _remote.keys() + _rGhosts.keys():
		_forgetRemote(id)     # (MP: the avatars are rebuilt for the new game; net:avatar re-dresses them)
	if _mp():
		_batch = false
		_syncExt()

# ------------------------------------------------------------------------------------------ ownership
func has(perkId: String) -> bool:
	return list.has(perkId)

func give(perkId: String, opts: Dictionary = {}) -> bool:
	var pop: bool = opts.get("pop", true)
	var emit: bool = opts.get("emit", true)
	var costume: bool = opts.get("costume", true)
	if not PERK_IDS.has(perkId) or has(perkId) or list.size() >= max:
		return false
	list.append(perkId)
	if costume and not _costumes.has(perkId):
		attachCostume(perkId, {"pop": pop})
	_applyMods()
	if perkId == "wobble_up":
		_tintRim(true)
	if emit:
		game.events.emit("perk:gain", _ev({"perkId": perkId}))
	_syncExt()
	return true

func remove(perkId: String, opts: Dictionary = {}) -> bool:
	var poof: bool = opts.get("poof", true)
	var i := list.find(perkId)
	if i < 0:
		return false
	list.remove_at(i)
	detachCostume(perkId, {"poof": poof})
	_applyMods()
	if perkId == "wobble_up":
		_restoreRim()
	if perkId == "roller_boogie":
		_skateLoop(false)
	game.events.emit("perk:lose", _ev({"perkId": perkId}))
	_syncExt()
	return true

func lose(perkId: String) -> bool:
	return remove(perkId)

# MP bleed-out (mp-players): every perk goes with a costume poof. The Morning Show's gold perks are permanent and
# stay (opts.force removes them too). Returns how many were removed.
func clearAll(opts: Dictionary = {}) -> int:
	if gold and not opts.get("force", false):
		return 0
	var n := 0
	_batch = true
	for id in list.duplicate():
		if remove(id, opts):
			n += 1
	_batch = false
	_syncExt()
	return n

func loseAll() -> int:
	return clearAll({"poof": true})

# ------------------------------------------------------------------------------------------ MP loadout
# Our loadout for the teammates' copies of our hero (net ext "perks" = [perkIds], "perksGold" = bool).
func _syncExt() -> void:
	if _batch or not _mp():
		return
	var net = _net()
	if not net.has_method("setLocalExt"):
		return
	net.setLocalExt("perks", list.duplicate())
	net.setLocalExt("perksGold", true if gold else null)

# A teammate's perk ids (empty when unknown).
func loadoutOf(peer) -> Array:
	var net = _net()
	if net == null or not net.active or int(peer) == int(net.localId):
		return list.duplicate()
	var e = net.extOf(int(peer)) if net.has_method("extOf") else {}
	var l = e.get("perks") if e is Dictionary else null
	return l.duplicate() if l is Array else []

func remoteHas(peer, perkId: String) -> bool:
	return loadoutOf(peer).has(perkId)

# Dresses a teammate's avatar with the costume pieces of its loadout (pop on gains, poof on losses).
func _syncRemote(id: int) -> void:
	var net = _net()
	if net == null or not net.inGame or id == int(net.localId) or id <= 0:
		return
	var rp = net.playerById(id)
	var hero = _f(rp, "hero")
	if rp == null or hero == null or not (_f(hero, "group") is Node3D):
		return
	var want: Array = loadoutOf(id)
	var e = net.extOf(id)
	var g: bool = bool(e.get("perksGold", false)) if e is Dictionary else false
	var R = _remote.get(id)
	var pop := true
	if R == null or not is_same(R.hero, hero):
		if R != null:
			_forgetRemote(id)
		R = {"hero": hero, "gold": g, "costumes": {}}
		_remote[id] = R
		pop = false                        # a (re)built avatar: dress it quietly
	if R.gold != g:
		for pid in R.costumes.keys():
			_undress(R.costumes[pid], pid, false)
		R.costumes.clear()
		R.gold = g
	for pid in R.costumes.keys():
		if not want.has(pid):
			_undress(R.costumes[pid], pid, true)
			R.costumes.erase(pid)
	for pid in want:
		if COSTUMES.has(pid) and not R.costumes.has(pid):
			var pieces = _dressHero(hero, pid, g, pop, false)
			if pieces != null:
				R.costumes[pid] = pieces
				if pop and sparkles:
					for pc in pieces:
						sparkles.emit(_wpos(pc.obj), {"count": 14, "colors": ["#FFE27A", "#FFFFFF", "#FF9EDB", "#7FE7FF"], "speed": 2.4, "size": 0.13, "life": 0.7, "gravity": 0.8})
	hero.group.position.y = SKATE_LIFT if R.costumes.has("roller_boogie") else 0.0
	# Wobble-Up's jelly rim on the avatar's own materials (restored on loss / leave / new game)
	if R.costumes.has("wobble_up") and R.get("rim") == null:
		R.rim = {}
		_rimInto(hero.group, R.rim)
	elif not R.costumes.has("wobble_up") and R.get("rim") != null:
		_restoreRimOf(R.rim)
		R.rim = null

# Sign-Off reward (GDD §13 Morning Show): all five, gold leaf, permanent, no limit.
func morningShow() -> Array:
	max = INF
	setGold(true)
	for id in PERK_IDS:
		give(id, {"pop": true})
	return list.duplicate()

func setGold(on) -> void:
	gold = bool(on)
	for id in _costumes.keys():
		detachCostume(id, {"poof": false})
		attachCostume(id, {"pop": true})
	_syncExt()

# ------------------------------------------------------------------------------------------ player.mods
func _applyMods() -> void:
	var p = game.player
	if p == null or _f(p, "mods") == null:
		return
	var m = p.mods
	var A := _applied
	var mul := func(k: String, field: String, want: float) -> void:
		var raw = m.get(field)
		var cur: float = float(raw) if (raw is float or raw is int) and is_finite(float(raw)) and float(raw) > 0.0 else 1.0
		m[field] = (cur / A[k]) * want
		A[k] = want
	var TP = Config.T.perks
	var roller := has("roller_boogie")
	var jump := has("jump_cut")
	var dv := has("double_vision")
	var wob := has("wobble_up")
	mul.call("move", "moveSpeed", float(TP.roller.speedMul) if roller else 1.0)
	mul.call("sprint", "sprintSpeed", float(TP.roller.speedMul) if roller else 1.0)
	mul.call("fire", "fireRate", float(TP.doubleVision.fireRate) if dv else 1.0)
	mul.call("reload", "reloadSpeed", float(TP.jumpCut.reload) if jump else 1.0)
	mul.call("swap", "swapSpeed", float(TP.jumpCut.swap) if jump else 1.0)
	mul.call("knock", "knockback", 0.5 if wob else 1.0)
	var newMax: float = float(Config.T.player.hpWobble) if wob else float(Config.T.player.hp)
	var oldMax: float = float(m.get("maxHealth")) if m.get("maxHealth") else float(Config.T.player.hp)
	m.maxHealth = newMax
	# the extra jelly HP comes filled (no 'signal loss' flash when you buy it); losing it clamps
	if newMax > oldMax and p.alive:
		p.maxHealth = newMax
		p.health = minf(newMax, p.health + (newMax - oldMax))
	m.noFlinch = wob
	m.unlimitedSprint = roller
	m.unlimitedStamina = roller
	m.reloadWhileSprinting = roller
	m.sprintToFire = float(TP.roller.sprintToFire) if roller else float(Config.T.player.sprintToFire)
	m.ghostBullets = dv
	m.ghostMul = float(TP.doubleVision.ghost) if dv else 0.0
	m.throwSpeed = 1.3 if jump else 1.0
	if roller:
		p.stamina = Config.T.player.stamina

# ------------------------------------------------------------------------------------------ costumes
func _slotFit(perkId: String, slot: String, hero) -> float:
	if perkId == "wobble_up" and slot == "head":
		var hbv = _f(hero, "hairBounds")
		var hb: float = float(hbv) if (hbv is float or hbv is int) and is_finite(float(hbv)) and float(hbv) > 0.0 else 0.27
		return clampf(((hb * 1.05) / 0.25) * 0.82, 0.95, 1.45)
	if perkId == "replay_ade" and slot == "neck":
		return 1.4     # the lanyard + whistle sit outside the collar
	return 1.0

func attachCostume(perkId: String, opts: Dictionary = {}) -> bool:
	var pop: bool = opts.get("pop", true)
	var g = game
	var hero = _f(g.player, "hero")
	if hero == null or not COSTUMES.has(perkId):
		return false
	if _costumes.has(perkId):
		detachCostume(perkId, {"poof": false})
	var pieces = _dressHero(hero, perkId, gold, pop, true)
	if pieces == null:
		return false
	_costumes[perkId] = {"pieces": pieces, "gold": gold}
	if pop:
		for pc in pieces:
			if sparkles:
				sparkles.emit(_wpos(pc.obj), {"count": 14, "colors": ["#FFE27A", "#FFFFFF", "#FF9EDB", "#7FE7FF"], "speed": 2.4, "size": 0.13, "life": 0.7, "gravity": 0.8})
	return true

# The costume pieces of perkId on a hero's slots (-> [{obj, slot, scale}] | null). local = the local hero (hero-fade
# dither); a teammate's avatar (MP) gets its pieces on RemotePlayer's render layer instead.
func _dressHero(hero, perkId: String, goldLeaf: bool, pop: bool, local: bool):
	var g = game
	var prop = _m(g.props, "build", [COSTUMES[perkId] + ("_gold" if goldLeaf else ""), {}])
	if not (prop is Node3D):
		push_warning("[perks] costume build failed " + perkId)
		return null
	load("res://scripts/game/sponsors.gd").resolveRefs(prop, DAU.ud(prop))
	var parts = DAU.ud(prop).get("parts", {})
	var pieces := []
	var slots = _f(hero, "slots")
	if parts is Dictionary:
		for slot in parts:
			var obj = parts[slot]
			var target = _f(slots, slot)
			if target == null or not (obj is Node3D):
				continue
			DAU.detach(obj)
			obj.position = Vector3(0, -0.045 if slot == "head" else 0.0, -0.035 if slot == "neck" else 0.0)   # helmet onto the hair, lanyard out of the shirt
			obj.rotation = Vector3.ZERO
			var s := _slotFit(perkId, slot, hero)
			obj.scale = Vector3.ONE * s
			if local:
				_m(g.mats, "applyHeroFade", [obj])
			else:
				DAU.setLayerRecursive(obj, 1)       # RemotePlayer.LAYER (actors): never in layer-0-only shots
			DAU.traverse(obj, func(o):
				if o is MeshInstance3D:
					DAU.ud(o).costume = perkId)
			target.add_child(obj)
			pieces.append({"obj": obj, "slot": slot, "scale": s})
			if pop:
				_pops.append({"obj": obj, "base": s, "t": 0.0})
				obj.scale = Vector3.ONE * 0.001
	_drop(prop)        # the gallery root (its parts moved onto the hero)
	if perkId == "roller_boogie":
		hero.group.position.y = SKATE_LIFT
	return pieces

func detachCostume(perkId: String, opts: Dictionary = {}) -> bool:
	var poof: bool = opts.get("poof", true)
	var c = _costumes.get(perkId)
	if c == null:
		return false
	_costumes.erase(perkId)
	var g = game
	_undress(c.pieces, perkId, poof)
	var hero = _f(g.player, "hero")
	if perkId == "roller_boogie" and hero:
		hero.group.position.y = 0.0
	return true

func _undress(pieces: Array, perkId: String, poof: bool) -> void:
	var g = game
	for pc in pieces:
		if not is_instance_valid(pc.obj):
			continue
		if poof and pc.obj.get_parent():
			var v := _wpos(pc.obj)
			var cols := ["#F4C81E", "#2F5BD3", "#FFFFFF"] if perkId == "replay_ade" else ["#F4F1E8", "#FFE27A"]
			_m(g.fx, "burst", [v, {"shape": "puff", "count": 6, "colors": cols, "speed": 1.4, "size": 0.1, "life": 0.5}])
			if sparkles:
				sparkles.emit(v, {"kind": "puff", "count": 5, "colors": cols, "speed": 1.2, "size": 0.12, "life": 0.45, "gravity": -0.5})
		var i := -1
		for k in _pops.size():
			if _pops[k].obj == pc.obj:
				i = k
				break
		if i >= 0:
			_pops.remove_at(i)
		_drop(pc.obj)

# Every material of a mesh (override, surface overrides, mesh surfaces).
static func _materialsOf(mi: MeshInstance3D) -> Array:
	var out := []
	if mi.material_override:
		out.append(mi.material_override)
	if mi.mesh:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m and not out.has(m):
				out.append(m)
	return out

static func _hasParam(sm: ShaderMaterial, name: String) -> bool:
	if sm.shader == null:
		return false
	for u in sm.shader.get_shader_uniform_list():
		if u.name == name:
			return true
	return false

# Wobble-Up: a faint green jelly rim on every hero material (restored on loss / new game).
func _tintRim(on: bool) -> void:
	var hero = _f(game.player, "hero")
	if not on or hero == null:
		return
	_restoreRim()
	_rimHero = hero
	_rimInto(hero.group, _rim)

# Tints every hero material under `group` with the jelly rim, remembering the originals in `store`.
func _rimInto(group: Node, store: Dictionary) -> void:
	DAU.traverse(group, func(o):
		if not (o is MeshInstance3D) or DAU.ud(o).get("costume"):
			return
		for mat in _materialsOf(o):
			if not (mat is ShaderMaterial) or store.has(mat) or not _hasParam(mat, "uRimColor"):
				continue
			var cur = mat.get_shader_parameter("uRimColor")
			var strength = mat.get_shader_parameter("uRimStrength") if _hasParam(mat, "uRimStrength") else null
			store[mat] = {"color": cur, "strength": strength}
			var c: Color = cur if cur is Color else (Color(cur.x, cur.y, cur.z) if cur is Vector3 else Color.WHITE)
			var t: Color = c.lerp(JELLY_RIM, 0.42)
			mat.set_shader_parameter("uRimColor", Vector3(t.r, t.g, t.b) if cur is Vector3 else t))

func _restoreRim() -> void:
	_restoreRimOf(_rim)
	_rimHero = null

static func _restoreRimOf(store: Dictionary) -> void:
	for mat in store:
		if not is_instance_valid(mat):
			continue
		var s: Dictionary = store[mat]
		mat.set_shader_parameter("uRimColor", s.color)
		if s.strength != null:
			mat.set_shader_parameter("uRimStrength", s.strength)
	store.clear()

# ------------------------------------------------------------------------------------------ hits
func _onHurt() -> void:
	var p = game.player
	if not has("wobble_up") or p == null:
		return
	p.anim.hurt = 0.0                 # no hit flinch: the jelly wobble replaces it
	_jelly.v -= 5.5

# ------------------------------------------------------------------------------------------ lethal
func onLethal() -> bool:
	if replayActive:
		return true
	var g = game
	var round_n = _f(g.rounds, "round", 0)
	var goldOk: bool = gold and has("replay_ade") and _goldReplayRound != round_n
	if not has("replay_ade") and not goldOk:
		return false
	if gold:
		_goldReplayRound = round_n
	_startReplay(not gold)
	return true

# Tests: freeze the replay at t seconds into phase ('pause' | 'rewind' | 'land'); null releases it.
func debugHold(phase, t = 0.0):
	debugHoldAt = {"phase": phase, "t": t} if phase else null
	return {"phase": _rp.phase, "t": _rp.t} if _rp != null else null

func debugReplay() -> bool:
	if replayActive:
		return false
	_startReplay(has("replay_ade") and not gold)
	return true

# player.history.get(i) (renamed get_ in the player port; a raw ring buffer is read directly).
static func _hget(h, i: int):
	if h == null:
		return null
	if h is Object and h.has_method("get_"):
		return h.get_(i)
	var cnt: int = int(_f(h, "count", 0))
	if i < 0 or i >= cnt:
		return null
	var n: int = int(_f(h, "n", 40))
	return h.samples[(int(h.head) - i + n) % n]

func _startReplay(consume: bool) -> void:
	var g = game
	var p = g.player
	var R = Config.T.perks.replay
	# path: current position, then history samples newest -> the oldest walkable one (<= 4 s)
	var pts := [{"x": p.pos.x, "y": p.pos.y, "z": p.pos.z, "yaw": p.yaw}]
	var h = _f(p, "history")
	var n := mini(int(_f(h, "count", 0)), int(round(float(R.rewind) / 0.1)))
	var target := -1
	var valid := func(s) -> bool:
		if s == null:
			return false
		if g.nav and g.nav.has_method("walkable") and not g.nav.walkable(s.x, s.z):
			return false
		var boss = g.boss
		if boss and _f(boss, "active") and boss.has_method("inArena") and not boss.inArena(s.x, s.z):
			return false
		return true
	for i in range(n - 1, -1, -1):
		if valid.call(_hget(h, i)):
			target = i
			break
	for i in range(0, target + 1):
		var s = _hget(h, i)
		pts.append({"x": s.x, "y": s.y, "z": s.z, "yaw": s.yaw})
	var steps := maxi(1, pts.size() - 1)
	# Nothing of render.post is snapshotted: the replay's look is its own fx layer (render.setFx), so ending it can
	# never write back somebody else's transient (the HUD's hurt pulse made the vertical roll stick forever).
	var s0: float = g.time.scale
	_rp = {
		"t": 0.0, "age": 0.0, "phase": "pause", "consume": consume, "pts": pts, "landed": false,
		"dur": maxf(0.6, (steps * 0.1) / float(R.speed)),
		"prev": p.pos, "ghostT": 0.0, "yaw": p.yaw,
		"scale0": s0 if s0 > 0 and s0 != REWIND_SCALE else 1.0,     # world speed to resume at landing
		"health0": maxf(0.0, p.health),
	}
	replayActive = true
	_protect(p, true)
	_lock(p, true)
	p.vel = Vector3.ZERO
	if not _mp():
		_setScale(0.0)            # MP: no world freeze (RECONCILE R5): only the hero rewinds
	_replayFx(1.0, 0.0, 0.0, 0.0)
	g.events.emit("replay:start", _ev({}))
	if _mp():
		_net().toOthers("perks", "replayFx", ["start", p.pos, false])
	_m(g.audio, "play", ["replay_wipe", {}])
	_m(g.cam, "shake", [0.25, 0.3])
	_ensureGhosts()

# time.scale writes of the replay are remembered, so the replay only ever restores a value it still owns.
func _setScale(v: float) -> void:
	game.time.scale = v
	_scaleSet = v

func _restoreScale(to: float) -> void:
	var g = game
	if _scaleSet != null and g.time.scale == _scaleSet:
		g.time.scale = to if to > 0 else 1.0
	_scaleSet = null

# The replay's VHS look as a render fx layer, refreshed every frame (short ttl: it drops by itself if the replay
# ever stops refreshing it). saturation multiplies render.post.saturation; the others combine with max().
func _replayFx(sat: float, roll: float, chroma: float, scanlines: float) -> void:
	var r = game.render
	if r == null or not r.has_method("setFx"):
		return
	var k := _fxKnobs
	k.saturation = sat
	k.roll = roll
	k.chroma = chroma
	k.scanlines = scanlines
	r.setFx(REPLAY_FX, k, {"ttl": REPLAY_FX_TTL})

func _updateReplay(rdt: float) -> void:
	var rp = _rp
	if rp == null:
		_endReplay(false)
		return
	rp.age += rdt
	if debugHoldAt == null and rp.age > REPLAY_WATCHDOG:
		push_warning("[perks] Instant Replay watchdog: force-finished after %.1f s in %s" % [rp.age, rp.phase])
		_finishReplay()
		return
	_stepReplay(rdt)

func _stepReplay(rdt: float) -> void:
	var g = game
	var p = g.player
	var rp: Dictionary = _rp
	rp.t += rdt
	var H = debugHoldAt
	if H != null and H.phase == rp.phase and rp.t > H.t:
		rp.t = float(H.t)
	var ov = Commercial.getOverlay()
	if rp.phase == "pause":
		var k: float = rp.t / 0.3
		ov.draw({"mode": "replay", "t": rp.t, "wipe": _clamp01(k), "tracking": _smooth(0.5, 1.0, k) * 0.6, "flash": 0.5 if rp.t < 0.05 else 0.0})
		_replayFx(1.0 - 0.35 * _smooth(0.0, 0.3, rp.t), 0.0, 0.0, 0.0)
		if rp.t >= 0.3:
			rp.phase = "rewind"
			rp.t = 0.0
			if not _mp():
				_setScale(REWIND_SCALE)
			_m(g.audio, "play", ["replay_rewind", {}])
		return
	if rp.phase == "rewind":
		var u := _clamp01(rp.t / rp.dur)
		var e := 2.0 * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 2.0) / 2.0
		var f: float = e * (rp.pts.size() - 1)
		var i := mini(rp.pts.size() - 2, int(floor(f)))
		var k: float = f - i
		var a: Dictionary = rp.pts[maxi(0, i)]
		var b: Dictionary = rp.pts[mini(rp.pts.size() - 1, i + 1)]
		p.pos = Vector3(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k)
		rp.yaw += _wrap(a.yaw + _wrap(b.yaw - a.yaw) * k - rp.yaw) * (1.0 - exp(-rdt * 10.0))
		p.yaw = rp.yaw
		if rdt > 0:
			p.vel = ((p.pos - rp.prev) / rdt).limit_length(14.0)
		p.vel.y = 0.0
		rp.prev = p.pos
		p.model.position = p.pos
		p.grounded = true
		p.health = rp.health0 + (p.maxHealth - rp.health0) * _smooth(0.0, 0.55, u)   # the damage rewinds too
		var ar = _m(g.level, "areaAt", [p.pos.x, p.pos.z])
		if ar:
			p.area = ar
		rp.ghostT -= rdt
		if rp.ghostT <= 0:
			rp.ghostT = 0.085
			_spawnGhost()
		_replayFx(0.72, 0.16 * (1.0 - u), 2.6, 0.7)
		ov.draw({"mode": "replay", "t": rp.t, "wipe": -1.0, "tracking": 0.75 + 0.25 * sin(rp.t * 17.0)})
		if u >= 1:
			_landReplay()
		return
	if rp.phase == "land":
		var k: float = rp.t / 0.35
		ov.draw({"mode": "replay", "t": rp.t, "wipe": -1.0, "tracking": 0.4 * (1.0 - k), "flash": 0.75 * (1.0 - _clamp01(k * 1.6))})
		if rp.t >= 0.35:
			_endReplay(false)

# Interrupted (exception / watchdog): land now if it has not landed yet (full HP, shockwave, perk consumed),
# then the normal cleanup.
func _finishReplay() -> void:
	var rp = _rp
	if rp != null and not rp.landed:
		_landReplay()
		var p = game.player
		if p:
			p.health = p.maxHealth
			p.alive = true
	_endReplay(false)

func _landReplay() -> void:
	var g = game
	var p = g.player
	var R = Config.T.perks.replay
	var rp: Dictionary = _rp
	rp.phase = "land"
	rp.t = 0.0
	rp.landed = true
	_restoreScale(rp.scale0)
	_m(g.render, "clearFx", [REPLAY_FX])
	p.vel = Vector3.ZERO
	p.health = p.maxHealth
	p.alive = true
	_lock(p, false)
	var h = _f(p, "history")
	_m(h, "clear")
	_m(h, "push", [p.pos, p.yaw, p.area])
	_invulnT = float(R.invuln)
	# shockwave: zombies within 5 m knocked back 3 m and stunned 2 s (MP: the host applies it — a world mutation)
	if _mp():
		_net().toHost("perks", "shockwave", [p.pos])
		_net().toOthers("perks", "replayFx", ["land", p.pos, rp.consume and has("replay_ade")])
	else:
		_shockwave(p.pos)
	_ring(p.pos, float(R.knock))
	var up: Vector3 = p.pos
	up.y = p.pos.y + 1.0
	_m(g.fx, "burst", [up, {"shape": "star", "count": 14, "speed": 5, "size": 0.16, "life": 0.8, "colors": ["#FFE27A", "#FFFFFF", "#7FE7FF"]}])
	_m(g.fx, "burst", [p.pos, {"shape": "puff", "count": 12, "speed": 3.5, "size": 0.3, "life": 0.7, "dir": Vector3(0, 0.2, 0), "cone": 1}])
	_m(g.cam, "shake", [0.55, 0.45])
	_m(g.audio, "play", ["studio_flash", {}])
	_m(g.audio, "play", ["crowd_ooh", {"vol": 0.6}])
	if rp.consume and has("replay_ade"):
		_dropWhistle()
		remove("replay_ade", {"poof": true})
	g.events.emit("player:revive", _ev({"selfRevive": true}))

func _shockwave(pos: Vector3) -> void:
	var g = game
	var R = Config.T.perks.replay
	var zs = _m(g.zombies, "inRadius", [pos, float(R.knock), []])
	if zs is Array:
		for z in zs:
			var v: Vector3 = z.pos - pos
			v.y = 0.0
			if v.length_squared() < 1e-4:
				v = Vector3(randf() - 0.5, 0, randf() - 0.5)
			v = v.normalized() * 3.0
			_m(g.zombies, "knockback", [z, v])
			_m(g.zombies, "stun", [z, float(R.stun)])

# owner -> host: an Instant Replay landed at pos: knock back + stun the zombies around it.
func net_shockwave(pos = null) -> void:
	var net = _net()
	if net == null or not net.isHost or not net.inGame or not (pos is Vector3):
		return
	_shockwave(pos)

# owner -> others: a teammate's replay ('start' | 'land' at pos; consumed = its Replay-Ade is gone).
func net_replayFx(kind = "", pos = null, _consumed = false) -> void:
	var net = _net()
	if net == null or not net.inGame or not (pos is Vector3) or int(net.sender) == int(net.localId):
		return
	var g = game
	var rg = _rGhosts.get(int(net.sender))
	if str(kind) == "land":
		if rg != null:
			rg.on = false
		var rp = net.playerById(int(net.sender))
		var neck = _f(_f(_f(rp, "hero"), "slots"), "neck")
		if _consumed and neck is Node3D and rp.model != null:
			_dropWhistleAt(neck, rp.model.rotation.y)          # (its Replay-Ade is gone: the whistle drops)
		_ring(pos, float(Config.T.perks.replay.knock))
		var up: Vector3 = pos + Vector3(0, 1.0, 0)
		_m(g.fx, "burst", [up, {"shape": "star", "count": 14, "speed": 5, "size": 0.16, "life": 0.8, "colors": ["#FFE27A", "#FFFFFF", "#7FE7FF"]}])
		_m(g.fx, "burst", [pos, {"shape": "puff", "count": 12, "speed": 3.5, "size": 0.3, "life": 0.7, "dir": Vector3(0, 0.2, 0), "cone": 1}])
		_m(g.audio, "play", ["studio_flash", {"pos": pos, "vol": 0.7}])
	elif str(kind) == "start":
		_m(g.audio, "play", ["replay_rewind", {"pos": pos, "vol": 0.7}])
		# cyan afterimages along its rewind (the hero zips back through the position stream from 0.3 s)
		var rp = net.playerById(int(net.sender))
		var hero = _f(rp, "hero")
		if hero != null and rp.model != null:
			if rg == null or not is_same(rg.hero, hero):
				if rg != null:
					for gh in rg.list:
						_drop(gh.holder)
				rg = {"hero": hero, "list": _makeGhosts(hero, rp.weaponModel)}
				_rGhosts[int(net.sender)] = rg
			rg.t = 0.0
			rg.ghostT = 0.0
			rg.on = true

# THE cleanup path: every temporary state the replay may hold, whatever phase it reached. Idempotent. hard = the
# run is over (reset / menu / game over / victory): a world speed the replay still holds goes back to 1.
func _endReplay(hard: bool) -> void:
	var g = game
	var rp = _rp
	var was: bool = replayActive or rp != null
	_rp = null
	replayActive = false
	_m(g.render, "clearFx", [REPLAY_FX])
	if hard:
		if _scaleSet != null or g.time.scale == REWIND_SCALE:
			g.time.scale = 1.0
		_scaleSet = null
	else:
		_restoreScale(rp.scale0 if rp != null else 1.0)
	for gh in _ghosts:
		gh.t = -1.0
		gh.group.visible = false
	if hard and _mp() and g.player:
		_protect(g.player, false)         # MP: the keyed protection never outlives the run
		_lock(g.player, false)
	if not was:
		return
	if g.player:
		_lock(g.player, false)
	if not _f(g.sponsors, "inCommercial", false):
		Commercial.getOverlay().clear()   # a running commercial redraws its own bezel every frame
	g.events.emit("replay:end", _ev({}))

# Afterimage pool: frozen pose copies of the hero, additive cyan, fading.
func _ensureGhosts() -> void:
	var p = game.player
	var hero = _f(p, "hero")
	if hero == null:
		return
	if _ghostHero == hero and _ghosts.size() > 0:
		return
	for gh in _ghosts:
		_drop(gh.holder)
	_ghostHero = hero
	_ghosts = _makeGhosts(hero, _f(p, "weaponModel"))

# 7 afterimages of a hero (the local one, or a teammate's avatar: MP), hidden until spawned.
func _makeGhosts(hero, wm) -> Array:
	var ghosts := []
	for i in 7:
		var c: Dictionary = cloneHero(hero, [wm])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(Color("#7FEFFF"), 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.disable_fog = true
		for m in c.meshes:
			m.material_override = mat
			if not _isSkinned(m) and _radius(m) < 0.03:
				m.visible = false
		var holder := DAU.node3d("replay_ghost")
		holder.add_child(c.group)
		holder.visible = false
		game.scene.add_child(holder)
		var e := c.duplicate()
		e.holder = holder
		e.group = holder
		e.mat = mat
		e.t = -1.0
		ghosts.append(e)
	return ghosts

func _spawnGhost() -> void:
	var p = game.player
	_spawnGhostIn(_ghosts, p.hero, p.model)

func _spawnGhostIn(ghosts: Array, hero, model: Node3D) -> void:
	var gh = null
	for x in ghosts:
		if x.t < 0:
			gh = x
			break
	if gh == null and ghosts.size() > 0:
		gh = ghosts[0]
		for x in ghosts:
			if x.t > gh.t:
				gh = x
	if gh == null:
		return
	copyPose(hero, gh)          # (gh.group is the holder, like the JS {...c, holder, group: holder})
	gh.holder.position = model.position
	gh.holder.quaternion = model.quaternion
	gh.holder.visible = true
	gh.t = 0.0
	var hue: String = [Config.PAL.gelCyan, "#FFFFFF", Config.PAL.gelMagenta][int(floor(randf() * 3))]
	var c := Color(hue)
	gh.mat.albedo_color = Color(c.r, c.g, c.b, gh.mat.albedo_color.a)

func _updateGhosts(rdt: float) -> void:
	_tickGhosts(_ghosts, rdt)

func _tickGhosts(ghosts: Array, rdt: float) -> void:
	for gh in ghosts:
		if gh.t < 0:
			continue
		gh.t += rdt
		var k: float = gh.t / 0.5
		var c: Color = gh.mat.albedo_color
		gh.mat.albedo_color = Color(c.r, c.g, c.b, 0.45 * (1.0 - k))
		if k >= 1:
			gh.t = -1.0
			gh.holder.visible = false

# RingGeometry(0.02, 1, 64, 1) with u = radius, rotated flat (rotateX(-PI/2)).
static func _buildRingGeo() -> ArrayMesh:
	var inner := 0.02
	var outer := 1.0
	var seg := 64
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in 2:
		var r := inner + (outer - inner) * j
		for i in seg + 1:
			var a := float(i) / seg * TAU
			var x := r * cos(a)
			var y := r * sin(a)
			verts.append(Vector3(x, 0, -y))
			uvs.append(Vector2(Vector2(x, y).length(), 0.5))
	for i in seg:
		var a := i
		var b := i + seg + 1
		var c := i + seg + 2
		var d := i + 1
		idx.append_array([a, b, d, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _ring(pos: Vector3, radius: float) -> void:
	var g = game
	if _ringMat == null:
		_ringMat = Commercial.canvasTex(256, 8, func(x, _w, _h):
			var gr = x.createLinearGradient(0, 0, 256, 0)
			gr.addColorStop(0, "rgba(255,255,255,0)")
			gr.addColorStop(0.75, "rgba(255,240,170,0.5)")
			gr.addColorStop(0.93, "rgba(255,255,255,1)")
			gr.addColorStop(1, "rgba(255,255,255,0)")
			x.fillStyle = gr
			x.fillRect(0, 0, 256, 8))
		_ringGeo = _buildRingGeo()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _ringMat is Texture2D:
		mat.albedo_texture = _ringMat
		mat.texture_repeat = false
	mat.albedo_color = Color("#FFE9A0")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.render_priority = 4
	var mesh := MeshInstance3D.new()
	mesh.name = "replay_ring"
	mesh.mesh = _ringGeo
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(pos.x, pos.y + 0.06, pos.z)
	g.scene.add_child(mesh)
	_rings.append({"mesh": mesh, "mat": mat, "t": 0.0, "r": radius})

func _updateRings(rdt: float) -> void:
	for i in range(_rings.size() - 1, -1, -1):
		var r: Dictionary = _rings[i]
		r.t += rdt
		var k: float = r.t / 0.45
		var s: float = 0.3 + (r.r - 0.3) * (1.0 - pow(1.0 - _clamp01(k), 3.0))
		r.mesh.scale = Vector3(s, 1, s)
		var c: Color = r.mat.albedo_color
		r.mat.albedo_color = Color(c.r, c.g, c.b, 1.0 - _smooth(0.5, 1.0, k))
		if k >= 1:
			_drop(r.mesh)
			_rings.remove_at(i)

# The referee whistle drops off the lanyard and bounces away (Replay-Ade consumed).
func _dropWhistle() -> void:
	var g = game
	var hero = _f(g.player, "hero")
	var neck = _f(_f(hero, "slots"), "neck")
	if not (neck is Node3D):
		return
	_dropWhistleAt(neck, g.player.model.rotation.y)

# The whistle leaves `neck` (a hero's neck slot) and bounces away ahead of a body facing `yaw`.
func _dropWhistleAt(neck: Node3D, yaw: float) -> void:
	var g = game
	var grp: Node3D = load("res://scripts/game/sponsors.gd").loadRuntimeAsset(g, "res://assets/runtime/sponsors/whistle.glb")
	if grp == null:
		return
	grp.rotation_order = EULER_ORDER_XYZ
	grp.position = _wpos(neck) + Vector3(0, -0.15, 0)
	g.scene.add_child(grp)
	var fx := -sin(yaw)
	var fz := -cos(yaw)
	_whistles.append({"obj": grp, "v": Vector3(fx * 1.6 + (randf() - 0.5), 2.6, fz * 1.6 + (randf() - 0.5)), "spin": Vector3(7, 3, 5), "t": 0.0, "bounces": 0})

func _updateWhistles(rdt: float) -> void:
	var col = _f(game.level, "col")
	for i in range(_whistles.size() - 1, -1, -1):
		var w: Dictionary = _whistles[i]
		w.t += rdt
		w.v.y -= 18.0 * rdt
		var obj: Node3D = w.obj
		obj.position += w.v * rdt
		obj.rotation += w.spin * rdt
		var floor_v = col.floorAt(obj.position.x, obj.position.z, obj.position.y + 0.2) if col and col.has_method("floorAt") else 0.0
		var fy: float = (float(floor_v) if floor_v != null and is_finite(float(floor_v)) else 0.0) + 0.03
		if obj.position.y < fy and w.v.y < 0:
			obj.position.y = fy
			if w.bounces < 3:
				w.v = Vector3(w.v.x * 0.6, -w.v.y * 0.45, w.v.z * 0.6)
				w.spin = w.spin * 0.6
				w.bounces += 1
				_m(game.audio, "play", ["grenade_bounce", {"pos": obj.position, "rate": 1.9, "vol": 0.5}])
			else:
				w.v = Vector3.ZERO
				w.spin = Vector3.ZERO
		if w.t > 3.2:
			var s := maxf(0.001, 1.0 - (w.t - 3.2) / 0.3)
			obj.scale = Vector3.ONE * s
			if w.t > 3.5:
				_drop(obj)
				_whistles.remove_at(i)

# ------------------------------------------------------------------------------------------ update
func update(dt: float) -> void:
	var g = game
	var p = g.player
	var rdt: float = g.time.realDt if g.time.realDt else 0.0
	if p == null:
		return
	if replayActive:
		_updateReplay(rdt)
	# Only the rewind ever runs the world at 0.1: without a replay that value is a leftover (e.g. an effect that
	# started mid-rewind saved it and restored it later), never a wanted state.
	elif g.time.scale == REWIND_SCALE:
		g.time.scale = 1.0
		_scaleSet = null
	if _invulnT > 0:
		_invulnT -= rdt
		if _invulnT <= 0 and not replayActive and _mp():
			_protect(p, false)             # (MP: keyed — a commercial holds its own key)
		elif _invulnT <= 0 and not replayActive and not _f(g.sponsors, "inCommercial", false):
			p.invulnerable = false
	# Roller Boogie skating strides (legs after the procedural + weapon pose).
	var an = _f(p, "animator")
	if an is Object and not _wrapped.has(an.get_instance_id()):
		_wrapAnimator(an)
	if _rimHero != null and _rimHero != _f(p, "hero"):
		_restoreRim()
		if has("wobble_up"):
			_tintRim(true)
	_updateJelly(rdt)
	_updateSkate(dt, rdt)
	_updatePops(rdt)
	_updateGhosts(rdt)
	if not _remote.is_empty() or not _rGhosts.is_empty():
		_updateRemotes(rdt)
	_updateRings(rdt)
	_updateWhistles(rdt)
	if has("double_vision") and dt > 0:
		_ting -= dt
		if _ting <= 0:
			_ting = 6.0
			_smileTing()
	var cam = _f(g.render, "cameraOverride")
	if cam == null:
		cam = g.camera
	if sparkles:
		sparkles.update(rdt, cam)

func _updatePops(rdt: float) -> void:
	for i in range(_pops.size() - 1, -1, -1):
		var pp: Dictionary = _pops[i]
		if not is_instance_valid(pp.obj):
			_pops.remove_at(i)
			continue
		pp.t += rdt
		var k := _clamp01(pp.t / 0.38)
		pp.obj.scale = Vector3.ONE * maxf(0.001, pp.base * _easeOutBack(k, 2.6))
		if k >= 1:
			pp.obj.scale = Vector3.ONE * pp.base
			_pops.remove_at(i)

# Damped jelly spring on the whole hero (+ the helmet wobbles twice as much).
func _updateJelly(rdt: float) -> void:
	var hero = _f(game.player, "hero")
	if hero == null:
		return
	var J := _jelly
	if not has("wobble_up") and absf(J.x) < 1e-3 and absf(J.v) < 1e-3:
		if hero.group.scale.y != 1.0:
			hero.group.scale = Vector3.ONE
		return
	var n := maxi(1, int(ceil(rdt / (1.0 / 120.0))))
	var h := rdt / n
	for i in n:
		J.v += (-190.0 * J.x - 7.5 * J.v) * h
		J.x += J.v * h
	J.x = clampf(J.x, -0.35, 0.35)
	var y: float = 1.0 + J.x * 0.55
	var xz := 1.0 / sqrt(maxf(0.3, y))
	hero.group.scale = Vector3(xz, y, xz)
	var helm = _costumes.get("wobble_up")
	if helm:
		for pc in helm.pieces:
			var popping := false
			for pp in _pops:
				if pp.obj == pc.obj:
					popping = true
					break
			if popping or not is_instance_valid(pc.obj):
				continue
			var hy: float = 1.0 + J.x * 1.3 + sin(game.time.realNow * 9.0) * 0.012
			var hxz := 1.0 / sqrt(maxf(0.3, hy))
			pc.obj.scale = Vector3(pc.scale * hxz, pc.scale * hy, pc.scale * hxz)

func _smileTing() -> void:
	var g = game
	var c = _costumes.get("double_vision")
	var p = g.player
	_m(g.audio, "play", ["smile_ting", {"pos": p.pos, "vol": 0.55}])
	var pc = c.pieces[0] if c and c.pieces.size() > 0 else null
	if pc == null or not is_instance_valid(pc.obj):
		return
	var v: Vector3 = _gxf(pc.obj) * Vector3(-0.24, 0.36, 0.08)
	if sparkles:
		sparkles.emit(v, {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.42, "life": 0.45, "gravity": 0, "spin": 5})
		sparkles.emit(v, {"count": 4, "colors": [Config.PAL.gelCyan, Config.PAL.gelMagenta], "speed": 0.6, "size": 0.09, "life": 0.5, "gravity": 0})

# ------------------------------------------------------------------------------------------ skating
# Roller Boogie skating strides: wrap each hero animator once (legs after the procedural + weapon pose). The rig
# port's assignable update (animator.updateFn) is the JS `a.update = function (dt, st) {...}` (see rig.gd).
func _wrapAnimator(a) -> void:
	_wrapped[a.get_instance_id()] = true
	var orig: Callable = Callable()
	var uf = a.get("updateFn")
	if uf is Callable and (uf as Callable).is_valid():
		orig = uf
	elif a.has_method("_procUpdate"):
		orig = Callable(a, "_procUpdate")
	if not orig.is_valid() or not ("updateFn" in a):
		return
	a.updateFn = func(dt, st = {}):
		orig.call(dt, st)
		_skatePose(a.rig, dt)       # cosmetic only

func _skatePose(rig, _dt: float) -> void:
	_skatePoseS(rig, _skate)

func _skatePoseS(rig, S: Dictionary) -> void:
	var w: float = S.w
	if w <= 0.001:
		return
	var J = rig.joints
	var ph: float = S.phase
	var s := sin(ph)
	var c := cos(ph)
	var pushL := maxf(0.0, s)
	var pushR := maxf(0.0, -s)
	# push-and-glide: the pushing leg extends back and out, the gliding leg bends and carries the weight
	J.hipL.rotation = Vector3(lerpf(J.hipL.rotation.x, 0.25 - pushL * 0.75, w), J.hipL.rotation.y, lerpf(J.hipL.rotation.z, -pushL * 0.42, w))
	J.hipR.rotation = Vector3(lerpf(J.hipR.rotation.x, 0.25 - pushR * 0.75, w), J.hipR.rotation.y, lerpf(J.hipR.rotation.z, pushR * 0.42, w))
	J.kneeL.rotation.x = lerpf(J.kneeL.rotation.x, -0.55 + pushL * 0.35, w)
	J.kneeR.rotation.x = lerpf(J.kneeR.rotation.x, -0.55 + pushR * 0.35, w)
	J.footL.rotation.x = lerpf(J.footL.rotation.x, 0.3 - pushL * 0.1, w)
	J.footR.rotation.x = lerpf(J.footR.rotation.x, 0.3 - pushR * 0.1, w)
	J.hips.position.y -= 0.07 * w
	J.hips.position.x += c * 0.05 * w
	J.hips.rotation.z += -c * 0.07 * w
	rig.root.rotation.z += c * 0.06 * w

func _updateSkate(dt: float, rdt: float) -> void:
	var g = game
	var p = g.player
	var S := _skate
	var on: bool = has("roller_boogie") and p.sprinting and p.grounded and not _f(g.sponsors, "inCommercial", false) and not replayActive
	S.w += ((1.0 if on else 0.0) - S.w) * (1.0 - exp(-rdt * 9.0))
	if on:
		S.phase += rdt * 5.2
	_skateLoop(on and dt > 0)
	var hero = _f(p, "hero")
	if not on or dt <= 0 or hero == null:
		return
	S.sparkT -= dt
	if S.sparkT > 0:
		return
	S.sparkT = 0.06
	var foot = hero.slots.footL if sin(S.phase) > 0 else hero.slots.footR
	if not (foot is Node3D):
		return
	var v := _wpos(foot)
	v.y = p.pos.y + 0.06
	_m(g.fx, "burst", [v, {"shape": "star", "count": 1, "speed": 0.4, "size": 0.055, "life": 0.45, "gravity": -0.4, "colors": ["#FF9EDB", "#7FE7FF", "#FFE27A"]}])

func _skateLoop(on: bool) -> void:
	var S := _skate
	var a = game.audio
	if on and S.loop == null and a and a.has_method("loop"):
		S.loop = a.loop("skate_roll", {"vol": 0.45})
	elif not on and S.loop != null:
		_m(S.loop, "stop", [0.15])
		S.loop = null
	if S.loop != null and on:
		_m(S.loop, "setPos", [game.player.pos])

# ------------------------------------------------------------------------------------------ MP: teammates' looks
# A teammate's perk looks on its avatar (cosmetic, from its loadout + streamed state): Roller Boogie skating strides
# (its animator wrapped like ours) + sparkle trail + skate roll at its feet while it sprints, Wobble-Up's jelly spring
# (kicked by its hits, jumps and landings; the helmet wobbles twice as much), Instant Replay afterimages along its
# rewind (perks.net_replayFx 'start' .. 'land').
func _updateRemotes(rdt: float) -> void:
	var net = _net()
	if net == null:
		return
	for id in _remote.keys():
		var R: Dictionary = _remote[id]
		var rp = net.playerById(id)
		var S = R.get("skate")
		if S == null:
			S = {"w": 0.0, "phase": 0.0, "sparkT": 0.0, "loop": null}
			R.skate = S
		if rp == null or not is_same(_f(rp, "hero"), R.hero) or rp.model == null:
			_skateLoopR(S, false, Vector3.ZERO)
			continue
		var hero = R.hero
		var cs: Dictionary = R.costumes
		var an = rp.animator
		if cs.has("roller_boogie") and an is Object and not _rWrapped.has(an.get_instance_id()):
			_wrapRemote(an, int(id))
		var on: bool = cs.has("roller_boogie") and rp.sprinting and rp.grounded and not rp.inCommercial and rp.model.visible and not rp.downed
		S.w += ((1.0 if on else 0.0) - S.w) * (1.0 - exp(-rdt * 9.0))
		if on:
			S.phase += rdt * 5.2
		_skateLoopR(S, on, rp.pos)
		if on:
			S.sparkT -= rdt
			if S.sparkT <= 0:
				S.sparkT = 0.06
				var foot = hero.slots.footL if sin(S.phase) > 0 else hero.slots.footR
				if foot is Node3D:
					var v := _wpos(foot)
					v.y = rp.pos.y + 0.06
					_m(game.fx, "burst", [v, {"shape": "star", "count": 1, "speed": 0.4, "size": 0.055, "life": 0.45, "gravity": -0.4, "colors": ["#FF9EDB", "#7FE7FF", "#FFE27A"]}])
		# Wobble-Up jelly spring
		var J = R.get("jelly")
		if J == null:
			J = {"x": 0.0, "v": 0.0, "hp": rp.health, "gr": rp.grounded}
			R.jelly = J
		if cs.has("wobble_up"):
			if rp.health < J.hp - 0.5:
				J.v -= 5.5
			if J.gr and not rp.grounded:
				J.v += 1.6
			elif not J.gr and rp.grounded:
				J.v -= 2.1
		J.hp = rp.health
		J.gr = rp.grounded
		if not cs.has("wobble_up") and absf(J.x) < 1e-3 and absf(J.v) < 1e-3:
			if hero.group.scale.y != 1.0 and not rp.inCommercial:
				hero.group.scale = Vector3.ONE
		else:
			var n := maxi(1, int(ceil(rdt / (1.0 / 120.0))))
			var h := rdt / n
			for i in n:
				J.v += (-190.0 * J.x - 7.5 * J.v) * h
				J.x += J.v * h
			J.x = clampf(J.x, -0.35, 0.35)
			var y: float = 1.0 + J.x * 0.55
			var xz := 1.0 / sqrt(maxf(0.3, y))
			hero.group.scale = Vector3(xz, y, xz)
			var helm = cs.get("wobble_up")
			if helm is Array:
				for pc in helm:
					if not is_instance_valid(pc.obj) or _popping(pc.obj):
						continue
					var hy: float = 1.0 + J.x * 1.3 + sin(game.time.realNow * 9.0) * 0.012
					var hxz := 1.0 / sqrt(maxf(0.3, hy))
					pc.obj.scale = Vector3(pc.scale * hxz, pc.scale * hy, pc.scale * hxz)
	# Instant Replay afterimages
	for id in _rGhosts.keys():
		var rg: Dictionary = _rGhosts[id]
		_tickGhosts(rg.list, rdt)
		if not rg.get("on", false):
			continue
		rg.t += rdt
		var rp = net.playerById(id)
		if rp == null or rp.model == null or not is_same(rp.hero, rg.hero) or rg.t > 2.5:
			rg.on = false
			continue
		if rg.t >= 0.3:
			rg.ghostT -= rdt
			if rg.ghostT <= 0:
				rg.ghostT = 0.085
				_spawnGhostIn(rg.list, rp.hero, rp.model)

func _popping(obj) -> bool:
	for pp in _pops:
		if pp.obj == obj:
			return true
	return false

# Skating strides on a teammate's animator (after its procedural + weapon pose), from its _remote entry's state.
func _wrapRemote(a, id: int) -> void:
	_rWrapped[a.get_instance_id()] = true
	var orig: Callable = Callable()
	var uf = a.get("updateFn")
	if uf is Callable and (uf as Callable).is_valid():
		orig = uf
	elif a.has_method("_procUpdate"):
		orig = Callable(a, "_procUpdate")
	if not orig.is_valid() or not ("updateFn" in a):
		return
	var R0 = _remote.get(id)
	var hero = R0.hero if R0 != null else null
	a.updateFn = func(dt, st = {}):
		orig.call(dt, st)
		var R = _remote.get(id)
		if R != null and is_same(R.hero, hero) and R.get("skate") != null:
			_skatePoseS(a.rig, R.skate)       # cosmetic only

func _skateLoopR(S: Dictionary, on: bool, pos: Vector3) -> void:
	var a = game.audio
	if on and S.loop == null and a and a.has_method("loop"):
		S.loop = a.loop("skate_roll", {"vol": 0.35, "pos": pos})
	elif not on and S.loop != null:
		_m(S.loop, "stop", [0.15])
		S.loop = null
	if S.loop != null and on:
		_m(S.loop, "setPos", [pos])

# A teammate's looks go (it left, its avatar was rebuilt, or a new game): rim restored, skate loop stopped, ghosts freed.
func _forgetRemote(id: int) -> void:
	var R = _remote.get(id)
	_remote.erase(id)
	if R != null:
		if R.get("rim") != null:
			_restoreRimOf(R.rim)
			R.rim = null
		if R.get("skate") != null:
			_skateLoopR(R.skate, false, Vector3.ZERO)
	var rg = _rGhosts.get(id)
	_rGhosts.erase(id)
	if rg != null:
		for gh in rg.list:
			_drop(gh.holder)
