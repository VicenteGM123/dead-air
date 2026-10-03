# Weapons: arsenal, firing, reload, swap, melee, tube grenades, shootables, held-weapon pose + gun FX
# (port of src/game/weapons.js; ARCHITECTURE §4/§10/§12, GDD §6.2, §9.1–§9.3, §9.5, §11 perk hooks, §14 no-hint UI,
# §15 cues, §16 controls). Owned by the weapons engineer. Data: weapon_defs.gd; models: weapon_models.gd (prop library
# wrapper).
#
# FIELDS  defs (WEAPON_DEFS) · slots [{ id, upgraded, signal, mag, reserve, fired }] · current (index; -1 = melee only)
#   maxSlots (2) · grenades (0..4) · teles (0..3) · reloading (bool) · swapping (bool) · spread (current crosshair
#   spread in degrees, hip/ADS + bloom) · aimPoint (Vector3: where the crosshair ray lands) · aimDist
#   hit (while zombies.damage runs from a weapon: { weaponId, upgraded, signal, cause, primary, head } else null;
#   signal-colour listeners on zombie:hit read it) · lastShot { weaponId, upgraded, signal, time, hits, kills }
# ARSENAL API
#   give(id, { upgraded=false, source='debug', signal=null }) -> bool   emits weapon:acquire {weaponId, upgraded, source}.
#       Guns: a free slot, else replaces the held one; owning it already = full ammo refill (keeps an upgrade).
#       'tube_grenade' refills grenades to 4, 'tiny_tele' sets teles to 3. Equips with a quick raise.
#   has(id) · currentDef() · currentSlot() · slotOf(id) -> slot|null · refill(id) -> bool (mag + reserve full)
#   refillAll() (FULL REEL: every slot full, grenades 4, Tiny Teles 3 if ever owned) · addGrenades(n)
#   upgradeCurrent(signal | { signal, source }) -> bool (Chromacast model, full upgraded ammo; emits weapon:acquire
#       source 'uplink') · upgrade(id, signal) · setSignal(id, signal)
#   remove(id) / take(id) -> removed slot data | null (the Uplink yank: auto-switches to the other weapon, or to
#       melee only) · takeCurrent()
#   buildModel(id, upgraded=false, signal=null) -> Node3D (fresh instance, HAND convention, see weapon_models.gd)
#   switchTo(index) (animated swap) · cancelReload()
# SHOOTABLES (ARCHITECTURE §10) — non-zombie things that react to bullets/melee:
#   registerShootable({ id, raycast: Callable(origin, dir, maxDist) -> { dist, point } | null, onHit: Callable(info),
#       blocksBullet=true, melee=true, bullets=true }) -> entry · unregisterShootable(id)
#   info = { id, point, dir, weaponId, upgraded, melee:bool, damage, head:false, cause }. Every bullet ray (pellets,
#   pierce), the aim ray and every melee sweep test zombies + shootables + level and hit the nearest. Emits
#   weapon:hit_shootable {id, ...info}. A non-blocking shootable is hit and the bullet flies on.
#   traceRay(origin, dir, maxDist, { zombies=true, shootables=true, level=true, melee=false, blockingOnly=false }) -> nearest
#       { kind:'zombie'|'shootable'|'level', dist, point, normal?, z?, head?, zone?, entry?, tag? } | null (helper)
#   damageZombie(z, amount, opts) -> killed   zombies.damage + the points fallback below (other systems may reuse;
#       it passes hitmarker:false unless opts.hitmarker is true). Hit zones: each ray's zone multiplier (limb ×0.8,
#       custom zones) is applied per pellet and the aggregate is passed with its dominant zone, so zombies.damage
#       ends with exactly sum(ray damage × zone mul).
# HUD: currentSpread() (degrees, for the crosshair ticks). Economy helpers: defOf(id, upgraded), refillAmmo(id),
#   refillGrenades(max).
# POINTS (GDD §6.3): one zombies.damage call per zombie per shot event (pellets / Double Vision ghost / pierce
#   aggregated), so the "+10 per zombie per shot event" rule holds whoever awards it (zombies.damage does today). If
#   it added no points (economy.points unchanged), weapons adds them: hit +10, kill 50 / head 100 / melee 130 /
#   grenade 50. hud.hitmarker(head, kill) once per shot event. The crosshair aim point ignores pass-through
#   shootables (traceRay blockingOnly): it is where the bullet stops.
# WONDER WEAPONS (def.fire === 'custom': zapper, boom_mic, chroma_key) are delegated to game.wonder (wonder.gd):
#   game.wonder.fire(weaponId, ctx) every frame while the weapon is held and not swapping/meleeing/throwing/raising,
#     ctx = { def, upgraded, signal, slot, origin, dir (camera-centre ray, origin at the player's depth), muzzle (world),
#       aimPoint, aimDist, triggerDown, triggerPressed, triggerReleased, ads, dt, ready, model (held Node3D), weapons,
#       time }. The trigger flags are gated by "may fire now" (not sprinting, sprint-to-fire elapsed, not reloading;
#       a press made too early is buffered 0.22 s); triggerReleased is the raw release (Boom Mic playback).
#     The wonder system owns ammo (slot.mag--), empty-mag reloads, dry fire and emits its own weapon:fire; weapons
#     adds the held-model recoil spring + a little shake + crosshair bloom when it returns truthy (if it returns
#     truthy without emitting weapon:fire, weapons emits it and kicks the camera: { kick, shake, recoil, noEvent }).
#   game.wonder.reload(weaponId, ctx) on R -> seconds (0 / false = refused): the wonder system runs the reload
#     (timing, ammo, weapon:reload, cues, part animation); weapons mirrors wonder.reloading / reloadProgress for the
#     pose (weapons.reloading). Optional hooks: game.wonder.holster(weaponId, ctx) / equip(weaponId, ctx).
#   Without game.wonder: a hitscan fallback fires and weapons runs the reload itself (one warning).
#   Q: weapons takes one Tiny Tele (teles--), plays the left-hand wind-up (a Tiny Tele model in the hand) and calls
#     game.wonder.throwTele(ctx) at the release, ctx = { origin (left hand), dir, velocity, aimPoint }; false gives
#     it back. weapons._handlesTele = true tells the wonder system not to read Q itself.
# PLAYER MODS read every frame (_eff()): fireRate (×rate), reloadSpeed / swapSpeed (time multipliers: 0.5 = twice as
#   fast; values > 1 are read as speeds), sprintToFire (s), damage, meleeDamage, ghostBullets. When a perk is owned
#   but its mod is untouched, the perk itself applies (perks.has): double_vision = fire rate ×1.2 + ghost bullets
#   (+50% on each zombie a bullet/pellet hits, doubled cyan/magenta tracers, a cyan/magenta ghost fringe on the held
#   gun), jump_cut = reload/swap ×0.5 + throws 30% faster + reloads skip frames (splice flash + jumpcut_snip),
#   roller_boogie = 0.10 s sprint-to-fire + reload while sprinting (also mods.reloadWhileSprinting / unlimitedSprint).
# CONTROLS (GDD §16): LMB fire (semi / pump / 3-round burst / auto; held auto keeps the exact rpm at any frame rate),
#   RMB aim (player+camera), R reload (firing interrupts the pump's shell-by-shell reload), 1/2(/3)/wheel/'weaponNext' (pad Y) swap
#   (T.player.swap 0.6 s), V melee (150, 0.7 s, 1.6 m reach, lunge up to 2.5 m to the zombie under the
#   crosshair), G hold to cook / release to throw a tube grenade (1.8 s fuse from the press), Q Tiny Tele.
#   No firing while sprinting; T.player.sprintToFire after it. +2 grenades at every round start after the first (max 4).
# POSE: the held model hangs on hero slots.handR (through a holder that applies def.scale); after the procedural
#   animation (a Callable appended once per hero animator to animator.postUpdate — the JS wrapped animator.update —
#   skipped while another system owns animator.override) a two-bone IK puts the grip in the right hand and the left
#   hand on the weapon's leftHand point, aimed at the crosshair point, with hip/ADS, recoil springs, reload/swap/
#   sprint/melee/throw layers. Melee swings per hero (MELEE_PROPS.swing: Duke chop, Skip/Penny bonk, Roxy slap) with
#   a chest coil/whip and the hero prop in the left hand.
# EVENTS emitted: weapon:fire {weaponId, upgraded} · weapon:reload {weaponId} · weapon:empty {weaponId} (dry fire)
#   · weapon:switch {weaponId} · weapon:acquire {weaponId, upgraded, source} · weapon:melee {hit} ·
#   weapon:hit_shootable {id, ...info} · weapon:grenade {pos} (explosion).
# SOUNDS: audio.gd voices fire / dry_fire / weapon_swap / melee / wallbuy from the events; this file plays reload_*,
#   wpn_pump_rack, grenade_throw / grenade_bounce / grenade_explode, jumpcut_snip, studio_flash (the wonder system
#   plays its own wonder cues and tele_throw).
# MP: (online co-op; mp-combat, RECONCILE R17/R18) the companion scripts/game/weapons_net.gd (`weapons.mp`) exists only
#   while an MP game runs (built by reset() when net.inGame; null in solo, so every MP branch is `mp != null`).
#   Hits on zombies keep going through zombies.damage (the R17 funnel: a client's call predicts + forwards; in MP the
#   info carries `shot` (per-shot dedupe) and `by`; the "points unchanged" fallback is off). Shootable hits on a
#   client go to the host (weapons.net_shootableHits [[id, point, dir, weaponId, upgraded, melee, damage, cause]];
#   the host runs onHit with info.by; an entry with `clientHit: true` keeps its onHit on the shooter). Grenades: the
#   thrower simulates its projectile (weapons.net_nade(nid, origin, vel, fuse) -> others draw a copy), self-damage is
#   local, the blast is a host-decided area action (_blastDamage on the host; a client sends weapons.net_nadeBoom(nid,
#   pos, inHand, dmgMul); host -> all weapons.net_nadeFx(by, nid, pos, inHand); weapon:grenade carries `by` (+ remote)).
#   The kill marker of a client comes with the host's zombie:kill (the predicted kill only shows a hit).
#   Observers: stream 'wfx' (shots / melee / wind-ups / wonder launches, format in weapons_net.gd). Randomness: _r()
#   = game.rand() in solo (same calls, same order), a per-peer stream in MP. Remote avatars:
#   buildRemoteHeld(remote, id, upgraded, signal) (+ remote.postAnimate IK pose). resetLoadout() (alias loadout()):
#   respawn kit. Arsenal messages host -> one peer: give(id, opts) · take(id) · takeCurrent() · upgrade(id, signal,
#   source) · refillAll() · addGrenades(n) · resetLoadout(); weapons.net_confirm(hits, head) host -> thrower.
#
# Port notes (GDScript):
#   * No renames of JS members. The fx pool helpers are GunFX (inner class, instance `fx`); the shared FX particle
#     meshes/materials come from fx.gd statics (FXS).
#   * Zombie records (Dictionaries) are compared by identity with is_same(): the per-shot aggregation (JS Map keyed
#     by zombie) is two parallel Arrays, the pierce hit-set an Array.
#   * `this.slots[this.current]` with current = -1 is undefined in JS; _slotAt() keeps that (GDScript's [-1] would
#     read the last slot).
#   * try/catch around other systems' callbacks are straight calls (GDScript aborts only the failing call).
#   * Canvas textures (muzzle star, rings) are drawn with the Canvas2D emulation (DACanvas).
extends RefCounted

const WD = preload("res://scripts/game/weapon_defs.gd")
const WM = preload("res://scripts/game/weapon_models.gd")
const FXS = preload("res://scripts/fx/fx.gd")

const MAX_RANGE := 80.0
const PIERCE_MUL := 0.7
const UP := Vector3(0, 1, 0)
const X_AXIS := Vector3(1, 0, 0)
const Y_AXIS := Vector3(0, 1, 0)
const Z_AXIS := Vector3(0, 0, 1)
const ORIGIN := Vector3.ZERO

static func smooth(a: float, b: float, x: float) -> float:
	return DAU.smoothstep3(x, a, b)

static func easeOutBack(x: float, s := 1.7) -> float:
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

static func easeInOut(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

# THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z)) (order 'XYZ').
static func qEuler(x: float, y: float, z: float) -> Quaternion:
	return Basis.from_euler(Vector3(x, y, z), EULER_ORDER_XYZ).get_rotation_quaternion()

static func v3a(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

# JS `x || d` for numeric fields of records (missing / null / 0 -> d).
static func _num(o, k: String, d: float) -> float:
	if o == null:
		return d
	var v = o.get(k)
	if v == null or not (v is float or v is int) or float(v) == 0.0:
		return d
	return float(v)

static func _finite(v) -> bool:
	return (v is float or v is int) and is_finite(float(v))

static func _isFalse(v) -> bool:
	return typeof(v) == TYPE_BOOL and v == false

# JS truthiness of a wonder-callback return value (an object is truthy even when empty).
static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is Dictionary or v is Object:
		return true
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String or v is StringName:
		return v != ""
	return true

# Imported glTF nodes use YXZ Euler order: switch a JS-rotated node to three's 'XYZ' keeping its transform.
static func _xyzOrder(n: Node3D) -> void:
	if n.rotation_order == EULER_ORDER_XYZ:
		return
	var t := n.transform
	n.rotation_order = EULER_ORDER_XYZ
	n.transform = t

static func _nodeWorldQ(n: Node3D) -> Quaternion:
	return n.global_basis.get_rotation_quaternion()

# ============================================================================================ two-bone IK
# Arm reach from the shoulder (world metres, current pose).
static func armReach(sh: Node3D, el: Node3D, ha: Node3D) -> float:
	var S := sh.global_position
	var E := el.global_position
	var H := ha.global_position
	return S.distance_to(E) + E.distance_to(H)

# Solves shoulder/elbow so the hand joint reaches `target` (world), elbow bent toward `pole` (world direction), then
# sets the hand's world rotation to handQ. The rig bends elbows around local +x (forward = -z), bones along -y.
static func solveArm(sh: Node3D, el: Node3D, ha: Node3D, target: Vector3, pole: Vector3, handQ = null) -> void:
	var S := sh.global_position
	var E := el.global_position
	var H := ha.global_position
	var a := S.distance_to(E)
	var b := E.distance_to(H)
	if a < 1e-4 or b < 1e-4:
		return
	var D := target - S
	var d := D.length()
	if d < 1e-5:
		return
	D /= d
	d = clampf(d, absf(a - b) + 1e-3, (a + b) * 0.9995)
	var cosA := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sinA := sqrt(1.0 - cosA * cosA)
	var PP := pole + D * (-pole.dot(D))
	if PP.length_squared() < 1e-8:
		PP = Vector3(0, -1, 0) + D * D.y
	PP = PP.normalized()
	E = S + D * (a * cosA) + PP * (a * sinA)
	var T := S + D * d
	var U := (E - S) / a
	var F := (T - E) / b
	var cosT := clampf(U.dot(F), -1.0, 1.0)
	var W := F + U * (-cosT)
	if W.length_squared() < 1e-8:
		W = -PP + U * PP.dot(U)
	W = W.normalized()
	var Y := -U
	var Z := -W
	var X := Y.cross(Z).normalized()
	var qs := Basis(X, Y, Z).get_rotation_quaternion()
	var qp := _nodeWorldQ(sh.get_parent() as Node3D)
	sh.quaternion = qp.inverse() * qs
	el.quaternion = Quaternion(X_AXIS, acos(cosT))
	if handQ != null:
		var qe := (qs * el.quaternion).inverse()
		ha.quaternion = qe * (handQ as Quaternion)

# Static helpers reachable from the inner classes (they cannot call the outer script's static functions).
class GX:
	static func qEuler(x: float, y: float, z: float) -> Quaternion:
		return Basis.from_euler(Vector3(x, y, z), EULER_ORDER_XYZ).get_rotation_quaternion()

	static func num(o: Dictionary, k: String, d: float) -> float:
		var v = o.get(k)
		if v == null or not (v is float or v is int) or float(v) == 0.0:
			return d
		return float(v)

	# ============================================================================================ canvas textures
	static func _makeCanvas(w: int, h: int):
		if not ResourceLoader.exists("res://scripts/gfx/canvas2d.gd"):
			return null
		var C = load("res://scripts/gfx/canvas2d.gd")
		return C.new(w, h) if C != null else null

	static func canvasTex(size: int, draw: Callable) -> Texture2D:
		var c = _makeCanvas(size, size)
		if c == null:
			return FXS.new(null)._fallbackRadial()
		draw.call(c.getContext("2d"), size)
		return c.texture

	static func starTex() -> Texture2D:
		return canvasTex(128, func(g, s: int):
			var h: float = s / 2.0
			var rg = g.createRadialGradient(h, h, 0, h, h, h)
			rg.addColorStop(0, "rgba(255,255,255,1)"); rg.addColorStop(0.18, "rgba(255,250,230,1)")
			rg.addColorStop(0.45, "rgba(255,220,150,0.55)"); rg.addColorStop(1, "rgba(255,170,80,0)")
			g.fillStyle = rg
			g.beginPath()
			var n := 8
			for i in n * 2 + 1:
				var a := (float(i) / (n * 2)) * PI * 2.0
				var r := h * 0.3 if i % 2 else h * (1.0 if i % 4 == 0 else 0.72)
				if i == 0:
					g.moveTo(h + cos(a) * r, h + sin(a) * r)
				else:
					g.lineTo(h + cos(a) * r, h + sin(a) * r)
			g.fill()
			var core = g.createRadialGradient(h, h, 0, h, h, h * 0.35)
			core.addColorStop(0, "rgba(255,255,255,1)"); core.addColorStop(1, "rgba(255,255,255,0)")
			g.fillStyle = core
			g.fillRect(0, 0, s, s))

	static func ringTex(rainbow: bool) -> Texture2D:
		return canvasTex(128, func(g, s: int):
			var h: float = s / 2.0
			if rainbow and g.has_method("createConicGradient"):
				var cg = g.createConicGradient(0, h, h)
				var bars: Array = Config.BARS if Config.BARS else ["#fff", "#ff0", "#0ff", "#0f0", "#f0f", "#f00", "#00f"]
				for i in bars.size():
					cg.addColorStop(float(i) / bars.size(), bars[i])
				cg.addColorStop(1, bars[0])
				g.fillStyle = cg
			else:
				g.fillStyle = "#ffffff"
			g.fillRect(0, 0, s, s)
			g.globalCompositeOperation = "destination-in"
			var rg = g.createRadialGradient(h, h, 0, h, h, h)
			rg.addColorStop(0, "rgba(0,0,0,0)"); rg.addColorStop(0.62, "rgba(0,0,0,0)"); rg.addColorStop(0.78, "rgba(0,0,0,1)")
			rg.addColorStop(0.88, "rgba(0,0,0,0.9)"); rg.addColorStop(1, "rgba(0,0,0,0)")
			g.fillStyle = rg
			g.fillRect(0, 0, s, s))

	# JS additive(map, vertexColors): MeshBasicMaterial white, additive, DoubleSide, no depth write, no fog.
	static func additive(map: Texture2D = null) -> ShaderMaterial:
		return FXS.additiveMaterial(Color(1, 1, 1), map, "double")

	# JS instanced(): hidden, count 0, all instance colours white.
	static func instanced(scene: Node, geo: Mesh, mat: Material, cap: int, name: String) -> Dictionary:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = geo
		mm.instance_count = cap
		mm.visible_instance_count = 0
		for i in cap:
			mm.set_instance_color(i, Color(1, 1, 1))
		var mi := MultiMeshInstance3D.new()
		mi.name = name.replace(":", "_")
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))   # frustumCulled = false
		mi.visible = false
		scene.add_child(mi)
		return {"mesh": mi, "mm": mm, "cap": cap}

	static func _setCount(M: Dictionary, n: int) -> void:
		M.mm.visible_instance_count = n
		M.mesh.visible = n > 0



# Double Vision ghost: same screen position, depth pushed 12 cm back along the view ray.
const GHOST_CODE := """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled;
uniform vec3 color : source_color = vec3(1.0);
uniform float opacity = 0.55;
void vertex() {
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	mv.xyz *= ( 1.0 + 0.12 / max( 0.3, length( mv.xyz ) ) );
	POSITION = PROJECTION_MATRIX * mv;
}
void fragment() {
	ALBEDO = color;
	ALPHA = opacity;
}
"""
static var _ghostShader: Shader = null

static func ghostMaterial(c: String) -> ShaderMaterial:
	if _ghostShader == null:
		_ghostShader = Shader.new()
		_ghostShader.code = GHOST_CODE
	var m := ShaderMaterial.new()
	m.shader = _ghostShader
	m.set_shader_parameter("color", DAU.color(c))
	m.set_shader_parameter("opacity", 0.55)
	return m

# ============================================================================================ gun FX pools
# Moving tracer streaks, muzzle stars (camera-facing card + side flame), expanding rings (rainbow / tinted) and
# ejected casings / shells with a little bounce physics. Every pool is one MultiMeshInstance3D, hidden while empty.
class GunFX extends RefCounted:
	var game
	var streakMesh: Dictionary
	var streaks: Array = []
	var cardMesh: Dictionary
	var flameMesh: Dictionary
	var cards: Array = []
	var ringMesh: Dictionary
	var rings: Dictionary
	var casing: Dictionary

	func _init(g) -> void:
		game = g
		var scene: Node = g.scene if g.scene != null else Node3D.new()
		# streaks: tapered cylinder along +z, dark tail -> bright head (vertex colours) x instance colour
		var sg = FXS.GeoData.cylinder(0.5, 0.5, 1, 6, true).rotateX(PI / 2).translate(0, 0, 0.5)
		sg.col.resize(sg.pos.size())
		for i in sg.pos.size():
			var k: float = 0.08 + 0.92 * sg.pos[i].z
			sg.col[i] = Color(k * k, k * k, k * k, 1.0)
		streakMesh = GX.instanced(scene, sg.toMesh(), GX.additive(null), 128, "wpn:streaks")
		streaks = []
		for i in 128:
			streaks.append({"on": false, "from": Vector3.ZERO, "dir": Vector3.ZERO, "dist": 0.0, "t": 0.0, "speed": 0.0, "len": 0.0, "width": 0.0,
				"color": Color(1, 1, 1), "flicker": 0, "wob": 0.0, "life": 0.0, "still": false})
		# muzzle / hit stars
		var star := GX.starTex()
		cardMesh = GX.instanced(scene, FXS.planeMesh(1, 1), GX.additive(star), 32, "wpn:cards")
		var a = FXS.GeoData.plane(1, 1).rotateY(PI / 2)
		var b = FXS.GeoData.plane(1, 1).rotateY(PI / 2).rotateZ(PI / 2)
		var cross = FXS.GeoData.merge([a, b]).translate(0, 0, -0.5)
		flameMesh = GX.instanced(scene, cross.toMesh(), GX.additive(star), 32, "wpn:flames")
		cards = []
		for i in 32:
			cards.append({"life": 0.0, "max": 1.0, "pos": Vector3.ZERO, "dir": Vector3.ZERO, "size": 0.0, "spin": 0.0, "color": Color(1, 1, 1), "flame": false, "grow": 0.0})
		# rings
		var rg := FXS.planeMesh(1, 1)
		ringMesh = {"rainbow": GX.instanced(scene, rg, GX.additive(GX.ringTex(true)), 16, "wpn:rings_rainbow"), "white": GX.instanced(scene, rg, GX.additive(GX.ringTex(false)), 24, "wpn:rings")}
		rings = {"rainbow": [], "white": []}
		for k in ["rainbow", "white"]:
			for i in ringMesh[k].cap:
				rings[k].append({"life": 0.0, "max": 1.0, "pos": Vector3.ZERO, "q": Quaternion.IDENTITY, "r0": 0.0, "r1": 1.0, "color": Color(1, 1, 1), "face": false})
		# casings
		var M = g.mats
		var brassGeo = FXS.GeoData.cylinder(0.014, 0.014, 0.045, 8).rotateX(PI / 2)
		var shellA = FXS.GeoData.cylinder(0.022, 0.022, 0.06, 10).translate(0, 0.012, 0)
		var shellB = FXS.GeoData.cylinder(0.0235, 0.0235, 0.024, 10).translate(0, -0.03, 0)
		var shellGeo = mergeColored([[shellA, "#D8322B"], [shellB, "#E2A93A"]]).rotateX(PI / 2)
		var brassMat = M.toon("#E2A93A", {"metal": 0.8, "rough": 0.28, "keepColor": true, "name": "wpn:brass"}) if M != null else FXS.basicMaterial({})
		var shellMat = M.toon("#ffffff", {"vertexColors": true, "rough": 0.35, "keepColor": true, "name": "wpn:shell"}) if M != null else FXS.basicMaterial({})
		casing = {
			"brass": _phys(scene, brassGeo.toMesh(), brassMat, 40),
			"shell": _phys(scene, shellGeo.toMesh(), shellMat, 24),
		}

	func _phys(scene: Node, geo: Mesh, mat: Material, cap: int) -> Dictionary:
		var mesh := GX.instanced(scene, geo, mat, cap, "wpn:casings")
		var list: Array = []
		for i in cap:
			list.append({"life": 0.0, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "q": Quaternion.IDENTITY, "axis": Vector3(1, 0, 0), "spin": 0.0, "floor": 0.0, "bounced": 0})
		return {"mesh": mesh, "list": list, "head": 0}

	static func mergeColored(parts: Array):
		var list: Array = []
		for p in parts:
			list.append(p[0].setColor(FXS.lin(p[1])))
		return FXS.GeoData.merge(list)

	func reset() -> void:
		for s in streaks:
			s.on = false
		for c in cards:
			c.life = 0.0
		for k in rings:
			for r in rings[k]:
				r.life = 0.0
		for k in casing:
			for c in casing[k].list:
				c.life = 0.0

	# Bullet streak from `from` to `to`: flies at style.speed, length style.len; delay (s) staggers pellets.
	func streak(from: Vector3, to: Vector3, style: Dictionary, color = null, delay := 0.0, offset = null) -> void:
		var s = null
		for x in streaks:
			if not x.on:
				s = x
				break
		if s == null:
			s = streaks[int(randf() * streaks.size())]
		s.on = true
		s.from = from
		if offset != null:
			s.from += offset
		s.dir = to - s.from
		s.dist = s.dir.length()
		if s.dist < 0.05:
			s.on = false
			return
		s.dir /= s.dist
		s.speed = GX.num(style, "speed", 160)
		s.len = GX.num(style, "len", 2.5)
		s.width = GX.num(style, "width", 0.03)
		var c: Color = FXS.lin(color if color else (style.color if style.get("color") else "#FFE9A8"))
		var boost := GX.num(style, "boost", 2.6)
		s.color = Color(c.r * boost, c.g * boost, c.b * boost, 1.0)
		s.flicker = 1 if style.get("style") == "scratch" else 0
		s.wob = 0.02 if style.get("style") == "scratch" else 0.0
		s.t = -delay
		s.still = false

	# A short static bar (film-splice line, flashbulb glints): lives `life` s.
	func bar(from: Vector3, to: Vector3, width: float, color, life := 0.06) -> void:
		var s = null
		for x in streaks:
			if not x.on:
				s = x
				break
		if s == null:
			s = streaks[0]
		s.on = true
		s.from = from
		s.dir = to - from
		s.dist = s.dir.length()
		if s.dist < 1e-3:
			s.on = false
			return
		s.dir /= s.dist
		s.len = s.dist
		s.width = width
		var c: Color = FXS.lin(color)
		s.color = Color(c.r * 2.5, c.g * 2.5, c.b * 2.5, 1.0)
		s.flicker = 0
		s.wob = 0.0
		s.still = true
		s.t = 0.0
		s.life = life

	# Muzzle flash: camera-facing star + a flame cross along the barrel.
	func flash(pos: Vector3, dir: Vector3, size: float, color, life := 0.06) -> void:
		_card(pos, dir, size, color, false, life, 0.0)
		_card(pos, dir, size * 1.25, color, true, life * 0.9, 0.0)

	# Hit spark card (white pop at the impact).
	func pop(pos: Vector3, size: float, color, life := 0.07) -> void:
		_card(pos, Vector3(0, 1, 0), size, color, false, life, 1.6)

	func _card(pos: Vector3, dir: Vector3, size: float, color, flame: bool, life: float, grow: float) -> void:
		var c = cards[0]
		for x in cards:
			if x.life <= 0.0:
				c = x
				break
			elif x.life < c.life:
				c = x
		c.life = life
		c.max = life
		c.pos = pos
		c.dir = dir
		c.size = size
		c.spin = randf() * PI * 2.0
		var col: Color = FXS.lin(color)
		var k := 2.2 if flame else 2.8
		c.color = Color(col.r * k, col.g * k, col.b * k, 1.0)
		c.flame = flame
		c.grow = grow

	# Expanding ring: normal = facing direction; face = true -> faces the camera instead.
	func ring(pos: Vector3, normal: Vector3, r0: float, r1: float, life: float, color, rainbow := false) -> void:
		var list: Array = rings["rainbow" if rainbow else "white"]
		var r = list[0]
		for x in list:
			if x.life <= 0.0:
				r = x
				break
			elif x.life < r.life:
				r = x
		r.life = life
		r.max = life
		r.pos = pos
		r.q = FXS.M3.quatFromUnitVectors(Vector3(0, 0, 1), normal.normalized())
		r.r0 = r0
		r.r1 = r1
		var col: Color = FXS.lin(color if color else "#ffffff")
		var k := 2.2 if rainbow else 2.4
		r.color = Color(col.r * k, col.g * k, col.b * k, 1.0)

	func eject(kind: String, pos: Vector3, vel: Vector3) -> void:
		var P = casing.get(kind)
		if P == null:
			return
		var c = P.list[P.head]
		P.head = (P.head + 1) % P.list.size()
		c.life = 1.6
		c.pos = pos
		c.vel = vel
		c.q = GX.qEuler(randf() * 6, randf() * 6, randf() * 6)
		c.axis = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		c.spin = 14 + randf() * 16
		var col = game.level.get("col") if game.level != null else null
		var f: float = col.floorAt(pos.x, pos.z, pos.y) if col != null else -INF
		c.floor = f + 0.015 if f > -INF else pos.y - 1.4
		c.bounced = 0

	func update(dt: float, camera: Node3D) -> void:
		# streaks
		var SM: MultiMesh = streakMesh.mm
		var n := 0
		for s in streaks:
			if not s.on:
				continue
			var tail: float
			var head: float
			if s.still:
				s.life -= dt
				if s.life <= 0.0:
					s.on = false
					continue
				tail = 0.0
				head = s.dist
			else:
				s.t += dt
				if s.t < 0.0:
					continue
				head = minf(s.dist, s.t * s.speed)
				tail = maxf(0.0, s.t * s.speed - s.len)
				if tail >= s.dist:
					s.on = false
					continue
			var len := head - tail
			if len <= 1e-3:
				continue
			var a: Vector3 = s.from + s.dir * tail
			if s.wob:
				a.x += (randf() - 0.5) * s.wob
				a.y += (randf() - 0.5) * s.wob
			var q := FXS.M3.quatFromUnitVectors(Vector3(0, 0, 1), s.dir)
			var w: float = s.width * (0.6 + randf() * 0.8 if s.flicker else 1.0)
			SM.set_instance_transform(n, Transform3D(Basis(q) * Basis.from_scale(Vector3(w, w, len)), a))
			var col: Color = s.color
			if s.flicker:
				var m := 0.5 + randf() * 0.9
				col = Color(col.r * m, col.g * m, col.b * m, 1.0)
			SM.set_instance_color(n, col)
			n += 1
		GX._setCount(streakMesh, n)

		# cards + flames
		var nc := 0
		var nf := 0
		var CM: MultiMesh = cardMesh.mm
		var FM: MultiMesh = flameMesh.mm
		var camQ: Quaternion = camera.global_basis.get_rotation_quaternion() if camera != null else Quaternion.IDENTITY
		for c in cards:
			if c.life <= 0.0:
				continue
			c.life -= dt
			if c.life <= 0.0:
				continue
			var k: float = 1.0 - c.life / c.max
			var pop: float = 0.7 + k * 1.6 if k < 0.25 else 1.1 - (k - 0.25) * 0.6
			var s: float = c.size * pop * (1.0 + c.grow * k)
			var f := 1.0 - k * k
			var col := Color(c.color.r * f, c.color.g * f, c.color.b * f, 1.0)
			if c.flame:
				var q := FXS.M3.quatFromUnitVectors(Vector3(0, 0, 1), -c.dir) * Quaternion(Vector3(0, 0, 1), c.spin)
				FM.set_instance_transform(nf, Transform3D(Basis(q) * Basis.from_scale(Vector3(s * 0.55, s * 0.55, s * 1.3)), c.pos))
				FM.set_instance_color(nf, col)
				nf += 1
			else:
				var q := camQ * Quaternion(Vector3(0, 0, 1), c.spin)
				CM.set_instance_transform(nc, Transform3D(Basis(q) * Basis.from_scale(Vector3(s, s, s)), c.pos))
				CM.set_instance_color(nc, col)
				nc += 1
		GX._setCount(cardMesh, nc)
		GX._setCount(flameMesh, nf)

		# rings
		for key in ["rainbow", "white"]:
			var RM: Dictionary = ringMesh[key]
			var mm: MultiMesh = RM.mm
			var nr := 0
			for r in rings[key]:
				if r.life <= 0.0:
					continue
				r.life -= dt
				if r.life <= 0.0:
					continue
				var k: float = 1.0 - r.life / r.max
				var e := 1.0 - pow(1.0 - k, 3.0)
				var s: float = (r.r0 + (r.r1 - r.r0) * e) * 2.0
				mm.set_instance_transform(nr, Transform3D(Basis(r.q) * Basis.from_scale(Vector3(s, s, s)), r.pos))
				var f := pow(1.0 - k, 1.5)
				mm.set_instance_color(nr, Color(r.color.r * f, r.color.g * f, r.color.b * f, 1.0))
				nr += 1
			GX._setCount(RM, nr)

		# casings
		for key in casing:
			var C: Dictionary = casing[key]
			var mm: MultiMesh = C.mesh.mm
			var nn := 0
			for c in C.list:
				if c.life <= 0.0:
					continue
				c.life -= dt
				if c.life <= 0.0:
					continue
				c.vel.y -= 16.0 * dt
				c.pos += c.vel * dt
				if c.pos.y < c.floor:
					c.pos.y = c.floor
					if c.vel.y < -1.2 and c.bounced < 3:
						c.vel.y = -c.vel.y * 0.38
						c.vel.x *= 0.55
						c.vel.z *= 0.55
						c.spin *= 0.6
						c.bounced += 1
					else:
						c.vel = Vector3.ZERO
						c.spin *= 0.8
				c.q = Quaternion(c.axis, c.spin * dt) * c.q
				var s: float = c.life / 0.3 if c.life < 0.3 else 1.0
				mm.set_instance_transform(nn, Transform3D(Basis(c.q) * Basis.from_scale(Vector3(1.3 * s, 1.3 * s, 1.3 * s)), c.pos))
				nn += 1
			GX._setCount(C.mesh, nn)

# ============================================================================================ holds (pose data)
# Offsets in the aim frame (x right, y up, -z forward) from the midpoint of the shoulders, metres at 1.8 m hero
# height. 'grip' places the grip; 'butt' places the stock end. chest: bladed stance yaw (rad); lh: left-hand frame.
const HOLDS := {
	"pistol": {"mode": "grip", "hip": [0.1, -0.05, -0.43], "ads": [0.07, -0.01, -0.42], "chest": -0.12, "poleR": [0.8, -1, 0.3], "poleL": [-0.6, -1, 0.2], "lh": "cup"},
	"rifle": {"mode": "butt", "hip": [0.17, -0.08, 0.02], "ads": [0.12, -0.02, 0.0], "chest": -0.42, "poleR": [1, -0.75, 0.35], "poleL": [-0.25, -1, 0.1], "lh": "under"},
	"lmg": {"mode": "butt", "hip": [0.19, -0.2, 0.08], "ads": [0.14, -0.1, 0.04], "chest": -0.4, "poleR": [1, -0.6, 0.4], "poleL": [-0.2, -1, 0.1], "lh": "under"},
	"remote": {"mode": "grip", "hip": [0.13, -0.06, -0.45], "ads": [0.09, -0.02, -0.46], "chest": -0.1, "poleR": [0.8, -1, 0.3], "poleL": [-0.6, -1, 0.2], "lh": "cup"},
	"pole": {"mode": "grip", "hip": [0.16, -0.2, -0.12], "ads": [0.13, -0.13, -0.14], "chest": -0.35, "poleR": [1, -0.6, 0.4], "poleL": [-0.25, -1, 0.1], "lh": "under", "pitch": 0.1},
	"cannon": {"mode": "grip", "hip": [0.16, -0.17, -0.22], "ads": [0.12, -0.1, -0.24], "chest": -0.3, "poleR": [1, -0.6, 0.4], "poleL": [-0.4, -1, 0.1], "lh": "side"},
}
static var LH_FRAMES := {
	"cup": qEuler(0.55, 0, 0.35),
	"under": qEuler(0, 0.35, PI / 2),
	"side": qEuler(0, 0, 0.15),
}
static var RH_FRAME := qEuler(0, 0, 0)
# Melee swings of the left hand, aim frame from the shoulders' midpoint (x right, y up, -z forward), 1.8 m hero:
# wind-up point, arc control point, hit point; hand euler at wind-up / hit. twist = chest yaw (wind, hit).
const SWINGS := {
	"chop": {"wind": [-0.36, 0.32, 0.1], "ctrl": [-0.22, 0.2, -0.5], "hit": [0.12, -0.14, -0.6], "rotW": [-0.9, 0, 1.2], "rotH": [0.4, 0, 1.2], "twist": [0.35, -0.3]},
	"bonk": {"wind": [-0.16, 0.46, 0.1], "ctrl": [-0.1, 0.42, -0.42], "hit": [0.02, -0.1, -0.62], "rotW": [-1.5, 0, 0.3], "rotH": [0.5, 0, 0.3], "twist": [0.2, -0.2]},
	"slap": {"wind": [-0.52, 0.08, 0.02], "ctrl": [-0.25, 0.06, -0.62], "hit": [0.3, -0.02, -0.48], "rotW": [0, 0.9, 1.4], "rotH": [0, -0.6, 1.4], "twist": [0.45, -0.4]},
}
const BELT_L := Vector3(-0.14, -0.62, -0.02)      # left hip pouch, body frame from the shoulders' midpoint

# ============================================================================================ the system
var game
var defs: Dictionary
var slots: Array = []
var current := -1
var maxSlots := 2
var grenades := 0
var teles := 0
var teleOwned := false
var reloading := false
var swapping := false
var spread := 2.5
var aimPoint := Vector3.ZERO
var aimDist := 20.0
var aimOrigin := Vector3.ZERO
var aimDir := Vector3(0, 0, -1)
var aimHit = null
var hit = null
var lastShot := {"weaponId": null, "upgraded": false, "signal": null, "time": 0.0, "hits": 0, "kills": 0}
var shootables := {}
var fx: GunFX = null

var _held := {}          # model cache key -> { holder, model, def, leftHand, butt, muzzle, parts, rest, ghosts }
var _heldKey = null
var _cool := 0.0
var _burst := 0
var _pumpT := 0.0        # pump action animation 0..1 (after a shot)
var _pumpRacked := true
var _pumpDur := 0.6
var _autoReloadT := -1.0
var _sinceSprint := 99.0
var _bloom := 0.0
var _adsW := 0.0
var _sprintW := 0.0
var _busyW := 0.0        # gun pulled back (melee / throw)
var _reload := {"t": 0.0, "total": 1.0, "kind": "mag", "shells": 0, "shellT": 0.0, "started": false, "cues": 0, "snips": 0, "stage": 0, "wonder": false}
var _swap := {"t": 0.0, "total": 0.6, "to": -1, "swapped": true}
var _raise := 1.0        # 0..1 raise-in after equip
var _melee := {"t": -1.0, "hit": false, "cd": 0.0, "lungeDist": 0.0, "target": null, "prop": null, "propHero": null}
var _nade := {"state": "none", "t": 0.0, "cook": 0.0, "released": false, "model": null}
var _tele := {"t": -1.0, "thrown": false, "model": null}
var _recoil := {"back": 0.0, "vb": 0.0, "rise": 0.0, "vr": 0.0, "roll": 0.0, "vroll": 0.0}
var _fireHeld := false
var _grenadeRound = 0
var _roundsSeen := 0
var _grenadesAtEnd = null
var _projectiles: Array = []
var _aggKeys: Array = []     # zombie records (identity)  } JS Map _agg
var _aggVals: Array = []     # aggregates                 }
var _aggPool: Array = []
var _hitSet: Array = []
var _hitList: Array = []
var _warned := {}
var _wrapped := {}           # animator instance ids (JS WeakSet)
var _poseFn: Callable
var _ctx := {}
var _teleCtx := {}
var _effMods := {}
var _pressBuf := 0.0         # trigger press buffered while not ready (sprint-to-fire, cooldown, raise)
var _inWonder := false       # inside game.wonder.fire(): detects the wonder system's own weapon:fire
var _wonderEmitted := false
var _handlesTele := true     # tells game.wonder that Q is read here (its self-drive skips it)
# MP (scripts/game/weapons_net.gd): built by reset() only while an MP game runs (null in solo: every MP path is
# behind `mp != null`)
const NET_PATH := "res://scripts/game/weapons_net.gd"
var mp = null
var _mpRand := Callable()
var _shotSeq := 0
var _endKind := 0            # MP: how the last _traceBullet ended (wfx shot record)
var _endNormal := Vector3.ZERO

func _init(g) -> void:
	game = g
	defs = WD.WEAPON_DEFS
	_poseFn = func(rig, dt): _poseSafe(rig, dt)
	_ctx = {"def": null, "upgraded": false, "signal": null, "slot": null, "origin": Vector3.ZERO, "dir": Vector3.ZERO, "muzzle": Vector3.ZERO,
		"aimPoint": Vector3.ZERO, "aimDist": 0.0, "triggerDown": false, "triggerPressed": false, "triggerReleased": false, "ads": false, "dt": 0.0,
		"ready": false, "model": null, "weapons": self, "time": 0.0, "duration": 0.0, "velocity": Vector3.ZERO}
	_teleCtx = {"origin": Vector3.ZERO, "dir": Vector3.ZERO, "velocity": Vector3.ZERO, "aimPoint": Vector3.ZERO, "weapons": self}
	game.events.on("round:start", func(e): _onRoundStart(e if e is Dictionary else {}))
	game.events.on("round:end", func(_e): _grenadesAtEnd = grenades)
	game.events.on("weapon:fire", func(_e):
		if _inWonder:
			_wonderEmitted = true)
	if game.mats != null and "chromacast" in game.mats and game.mats.chromacast == null:
		var gg = game
		game.mats.chromacast = func(sig_): return WM.chromacast(gg, sig_)

# ------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	fx = GunFX.new(game)
	var n = game.get("net")
	if n != null and n.has_method("registerStream"):
		n.registerStream("wfx", "weapons")   # MP: observers' shot / melee / wind-up stream (weapons_net.gd)

func reset() -> void:
	slots.clear()
	current = -1
	maxSlots = 2
	grenades = WD.WEAPON_DEFS.tube_grenade.start
	teles = 0
	teleOwned = false
	reloading = false
	swapping = false
	hit = null
	_cool = 0.0
	_burst = 0
	_pumpT = 0.0
	_pumpRacked = true
	_autoReloadT = -1.0
	_bloom = 0.0
	_raise = 1.0
	_swap.t = 0.0
	_swap.to = -1
	_swap.swapped = true
	_melee.t = -1.0
	_melee.cd = 0.0
	_nade.state = "none"
	_tele.t = -1.0
	if _tele.model != null:
		_tele.model.visible = false
	_grenadeRound = 0
	_roundsSeen = 0
	_grenadesAtEnd = null
	for pr in _projectiles:
		_removeProjectile(pr)
	_projectiles.clear()
	if fx != null:
		fx.reset()
	if _melee.prop != null:
		DAU.detach(_melee.prop)
		_melee.prop.queue_free()
		_melee.prop = null
		_melee.propHero = null
	if _nade.model != null:
		_nade.model.visible = false
	game.player.setWeaponModel(null)
	_heldKey = null
	give("revolver_38", {"source": "start"})
	_raise = 1.0
	_mpReset()

# MP: the weapons_net companion exists only while an MP game runs (net.inGame is already true in the MP newGame's
# resets); solo / lobby -> null, so every MP path is skipped.
func _mpReset() -> void:
	var n = game.get("net")
	if n != null and n.inGame:
		if mp == null:
			mp = load(NET_PATH).new(self)
		_mpRand = Rng.mulberry32(int(game.seed_value) ^ (int(n.localId) * 7919 + 104729))
		mp.reset()
	elif mp != null:
		mp.dispose()
		mp = null

func _onRoundStart(e: Dictionary) -> void:
	var r = e.get("round", 0)
	if r == null:
		r = 0
	_roundsSeen += 1
	if _roundsSeen <= 1 or r == _grenadeRound:
		_grenadeRound = r
		return
	_grenadeRound = r
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var base: int = _grenadesAtEnd if _grenadesAtEnd != null else grenades
	grenades = maxi(grenades, mini(G.carry, base + G.perRound))
	_grenadesAtEnd = null

# ------------------------------------------------------------------------------------------ arsenal API
func _slotAt(i: int) -> Variant:
	return slots[i] if i >= 0 and i < slots.size() else null

func currentSlot() -> Variant:
	return _slotAt(current)

func currentDef() -> Variant:
	var s = _slotAt(current)
	return WD.weaponDef(s.id, s.upgraded) if s != null else null

func has(id) -> bool:
	for s in slots:
		if s.id == id:
			return true
	return false

func slotOf(id) -> Variant:
	for s in slots:
		if s.id == id:
			return s
	return null

func _indexOf(id) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i].id == id:
			return i
	return -1

func buildModel(id, upgraded := false, sig_ = null) -> Node3D:
	return WM.buildModel(id, upgraded, sig_, game)

func give(id, opts := {}) -> bool:
	var upgraded: bool = _truthy(opts.get("upgraded"))
	var source = opts.get("source", "debug") if opts.get("source") != null else "debug"
	var sig_ = opts.get("signal")
	var g = game
	var base = WD.WEAPON_DEFS.get(id)
	if base == null:
		return false
	if id == "tube_grenade":
		grenades = base.carry
		g.events.emit("weapon:acquire", {"weaponId": id, "upgraded": false, "source": source})
		return true
	if id == "tiny_tele":
		teles = base.carry
		teleOwned = true
		g.events.emit("weapon:acquire", {"weaponId": id, "upgraded": false, "source": source})
		return true
	if not WD.isGunDef(base):
		return false
	var i := _indexOf(id)
	var up: bool = upgraded or (i >= 0 and slots[i].upgraded)
	var def: Dictionary = WD.weaponDef(id, up)
	var sig = (sig_ if sig_ else (slots[i]["signal"] if i >= 0 else null)) if up else null
	if i < 0:
		if slots.size() < maxSlots:
			slots.append(null)
			i = slots.size() - 1
		else:
			i = maxi(0, current)
		if _slotAt(i) != null and i == current:
			_holster()
	var prev = slots[i]
	_swap.t = 0.0
	swapping = false
	slots[i] = {"id": id, "upgraded": up, "signal": sig, "mag": def.mag, "reserve": def.reserve, "fired": (prev.get("fired", 0) if prev != null and prev.id == id else 0)}
	_equip(i, true)
	g.events.emit("weapon:acquire", {"weaponId": id, "upgraded": up, "source": source})
	return true

func refill(id) -> bool:
	var s = slotOf(id)
	if s == null:
		return false
	var def: Dictionary = WD.weaponDef(s.id, s.upgraded)
	s.mag = def.mag
	s.reserve = def.reserve
	return true

func refillAll() -> void:
	for s in slots:
		var def: Dictionary = WD.weaponDef(s.id, s.upgraded)
		s.mag = def.mag
		s.reserve = def.reserve
	grenades = WD.WEAPON_DEFS.tube_grenade.carry
	if teleOwned:
		teles = WD.WEAPON_DEFS.tiny_tele.carry
	if reloading:
		cancelReload()

func addGrenades(n := 1) -> int:
	grenades = clampi(grenades + n, 0, WD.WEAPON_DEFS.tube_grenade.carry)
	return grenades

func refillGrenades(max_v = null) -> int:
	var m: int = WD.WEAPON_DEFS.tube_grenade.carry if max_v == null else int(max_v)
	grenades = clampi(m, 0, WD.WEAPON_DEFS.tube_grenade.carry)
	return grenades

func refillAmmo(id) -> bool:
	return refill(id)

func defOf(id, upgraded := false) -> Variant:
	return WD.weaponDef(id, upgraded)

# Crosshair spread in degrees (hip/ADS lerp + bloom + movement), read by the HUD ticks.
func currentSpread() -> float:
	return spread

func upgradeCurrent(arg = null) -> bool:
	var opts: Dictionary = {"signal": arg} if arg is String else (arg if arg is Dictionary else {})
	var s = _slotAt(current)
	if s == null:
		return false
	var sig = opts.get("signal") if opts.get("signal") != null else s.get("signal")
	return upgrade(s.id, sig, opts.source if opts.get("source") else "uplink")

func upgrade(id, sig_ = null, source := "uplink") -> bool:
	var i := _indexOf(id)
	if i < 0 or not WD.weaponDef(id, true).get("isUpgraded", false):
		return false
	var def: Dictionary = WD.weaponDef(id, true)
	slots[i].upgraded = true
	slots[i]["signal"] = sig_ if sig_ else null
	slots[i].mag = def.mag
	slots[i].reserve = def.reserve
	if i == current:
		_equip(i, true)
	game.events.emit("weapon:acquire", {"weaponId": id, "upgraded": true, "source": source})
	return true

func setSignal(id, sig_) -> bool:
	var s = slotOf(id)
	if s == null or not s.upgraded:
		return false
	s["signal"] = sig_ if sig_ else null
	if is_same(_slotAt(current), s):
		_equip(current, false)
	return true

func remove(id) -> Variant:
	var i := _indexOf(id)
	if i < 0:
		return null
	var s: Dictionary = slots[i]
	var wasCurrent := i == current
	if wasCurrent:
		_holster()
	slots.remove_at(i)
	_swap.t = 0.0
	swapping = false
	if slots.size() == 0:
		current = -1
		cancelReload()
		game.player.setWeaponModel(null)
		_heldKey = null
	elif wasCurrent:
		var next := mini(i, slots.size() - 1)
		current = -1
		_equip(next, true)
		game.events.emit("weapon:switch", {"weaponId": slots[next].id})
	elif current > i:
		current -= 1
	return s.duplicate()

func take(id) -> Variant:
	return remove(id)

func takeCurrent() -> Variant:
	var s = _slotAt(current)
	return remove(s.id) if s != null else null

func switchTo(index: int) -> bool:
	if _slotAt(index) == null or index == current or _swap.t > 0.0:
		return false
	cancelReload()
	_burst = 0
	_swap.total = Config.T.player.swap * _eff().swap
	_swap.t = 1e-4
	_swap.to = index
	_swap.swapped = false
	swapping = true
	game.events.emit("weapon:switch", {"weaponId": slots[index].id})
	return true

func cancelReload() -> void:
	if reloading:
		_restoreParts()
	reloading = false
	_reload.t = 0.0
	var a = game.player.get("anim") if game.player != null else null
	if a != null:
		a.reload = 0

# Held model for slot i (cached per id / upgrade / signal).
func _equip(i: int, raise: bool) -> void:
	var g = game
	var p = g.player
	var s = _slotAt(i)
	if s == null:
		return
	if current != i and _slotAt(current) != null:
		_holster()
	current = i
	cancelReload()
	_burst = 0
	_cool = maxf(_cool, 0.05)
	var key := "%s|%s|%s" % [s.id, 1 if s.upgraded else 0, s["signal"] if s["signal"] else ""]
	var h = _held.get(key)
	if h == null:
		var def: Dictionary = WD.weaponDef(s.id, s.upgraded)
		var model: Node3D = WM.buildModel(s.id, s.upgraded, s["signal"], g)
		var holder := DAU.node3d("weaponHolder")
		holder.quaternion = RH_FRAME.inverse()
		var sc: float = _num(def, "scale", 1.0)
		holder.scale = Vector3(sc, sc, sc)
		holder.add_child(model)
		var u := DAU.ud(model)
		var mz: Node = DAU.byName(model, "muzzle")
		h = {"holder": holder, "model": model, "def": def,
			"leftHand": v3a(u.leftHand) if u.get("leftHand") != null else Vector3(0, 0, -0.15),
			"butt": v3a(u.butt) if u.get("butt") != null else Vector3(0, 0.08, 0.05),
			"muzzle": (mz as Node3D).position if mz is Node3D else Vector3(0, 0.08, -0.3),
			"parts": u.get("parts") if u.get("parts") is Dictionary else {}, "rest": {}, "ghosts": null}
		for k in h.parts:
			var o = h.parts[k]
			if o is Node3D:
				_xyzOrder(o)
				h.rest[o] = {"pos": o.position, "rot": o.rotation, "scale": o.scale, "visible": o.visible}
		_held[key] = h
	h.def = WD.weaponDef(s.id, s.upgraded)
	_heldKey = key
	_restoreParts()
	p.setWeaponModel(h.holder)
	if raise:
		_raise = 0.0
	_pumpRacked = true
	_pumpT = 0.0
	if h.def.get("fire") == "custom":
		_wonderCall("equip", s.id)

func _holder() -> Variant:
	return _held.get(_heldKey) if _heldKey != null else null

# Double Vision (GDD §11): a faint cyan / magenta duplicate of the held weapon trails 3 cm to each side (they lag
# the recoil a little, like a TV ghost). Built lazily per held model, additive, hidden without the perk.
func _updateGhosts(on: bool) -> void:
	var h = _holder()
	for hh in _held.values():
		if hh.ghosts != null and (not is_same(hh, h) or not on):
			for gm in hh.ghosts:
				gm.visible = false
	if h == null or not on or _slotAt(current) == null:
		return
	if h.ghosts == null:
		var s = _slotAt(current)
		var list: Array = []
		for c in ["#5FF4FF", "#FF5FD2"]:
			var gm: Node3D = WM.buildModel(s.id, s.upgraded, s["signal"], game)
			if gm == null:
				_warnOnce("ghost", "buildModel failed")
				continue
			# depth pushed 12 cm back along the view ray (same screen position): where it overlaps the real gun it fails
			# the depth test, so only the offset fringe around the gun's silhouette glows (the TV ghosting look)
			var mat := ghostMaterial(c)
			DAU.traverse(gm, func(o):
				if o.name == "muzzle":
					o.name = "muzzle_ghost"
				if o is GeometryInstance3D:
					(o as GeometryInstance3D).material_override = mat
					(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			gm.name = "weaponGhost"
			h.holder.add_child(gm)
			list.append(gm)
		h.ghosts = list
	var t: float = game.time.now
	var sc: float = h.holder.scale.x if h.holder.scale.x != 0.0 else 1.0
	var R := _recoil
	for i in h.ghosts.size():
		var gm: Node3D = h.ghosts[i]
		var side := -1.0 if i else 1.0
		gm.visible = true
		var pos: Vector3 = h.model.position
		pos.x += side * (0.032 + 0.008 * sin(t * 3.1 + i * 2)) / sc
		pos.y += side * 0.006 / sc
		pos.z += (-R.back * 0.55 + 0.004 * sin(t * 2.3 + i)) / sc
		gm.position = pos
		gm.quaternion = h.model.quaternion

func _holster() -> void:
	var s = _slotAt(current)
	if s == null:
		return
	var d = WD.weaponDef(s.id, s.upgraded)
	if d != null and d.get("fire") == "custom":
		_wonderCall("holster", s.id)

func _restoreParts() -> void:
	var h = _holder()
	if h == null:
		return
	for o in h.rest:
		if not is_instance_valid(o):
			continue
		var r: Dictionary = h.rest[o]
		o.position = r.pos
		o.rotation = r.rot
		o.scale = r.scale
		o.visible = r.visible

# ------------------------------------------------------------------------------------------ shootables
func registerShootable(entry) -> Variant:
	if not (entry is Dictionary) or not entry.get("id") or not (entry.get("raycast") is Callable):
		return null
	var e := {"blocksBullet": true, "melee": true, "bullets": true, "onHit": func(_info): pass}
	e.merge(entry, true)
	shootables[e.id] = e
	return e

func unregisterShootable(id) -> bool:
	var key = id.id if (id is Dictionary and id.get("id")) else id
	return shootables.erase(key)

# Nearest shootable along a ray (kind 'bullets' | 'melee'); skip = entry to ignore (non-blocking pass-through).
# blockingOnly: ignore pass-through entries (the crosshair aim point is where the bullet stops).
func _castShootables(o: Vector3, d: Vector3, maxDist: float, kind := "bullets", skip = null, blockingOnly := false) -> Variant:
	var best = null
	var bestD := maxDist
	for e in shootables.values():
		if is_same(e, skip) or _isFalse(e.get(kind)) or (blockingOnly and _isFalse(e.get("blocksBullet"))):
			continue
		var h = e.raycast.call(o, d, bestD)
		if h != null and h.get("dist") != null and h.dist >= 0 and h.dist <= bestD:
			bestD = h.dist
			best = {"entry": e, "dist": h.dist, "point": h.point if h.get("point") != null else o + d * h.dist}
	return best

func _hitShootable(e: Dictionary, point: Vector3, dir: Vector3, weaponId, upgraded, damage: float, melee: bool, cause: String) -> void:
	var info := {"id": e.id, "point": point, "dir": dir, "weaponId": weaponId, "upgraded": _truthy(upgraded), "melee": melee, "damage": damage, "head": false, "cause": cause}
	if mp != null and mp.shootableHit(e, info):
		return   # MP client: sent to the host (weapons.net_shootableHits), which runs onHit with info.by
	if e.get("onHit") is Callable:
		e.onHit.call(info)
	game.events.emit("weapon:hit_shootable", info.duplicate())

func traceRay(origin: Vector3, dir: Vector3, maxDist := MAX_RANGE, opts := {}) -> Variant:
	var g = game
	var zombies: bool = opts.get("zombies", true)
	var shoot: bool = opts.get("shootables", true)
	var level: bool = opts.get("level", true)
	var melee: bool = opts.get("melee", false)
	var blockingOnly: bool = opts.get("blockingOnly", false)
	var best = null
	if level and g.level != null and g.level.get("col") != null:
		var w = g.level.col.raycast(origin, dir, maxDist)
		if w != null:
			best = {"kind": "level", "dist": w.dist, "point": w.point, "normal": w.normal, "tag": w.get("tag")}
	var lim: float = best.dist if best != null else maxDist
	if zombies and g.zombies != null and g.zombies.has_method("raycast"):
		var z = g.zombies.raycast(origin, dir, lim)
		if z != null and z.dist <= lim:
			best = {"kind": "zombie", "dist": z.dist, "point": z.point, "z": z.z, "head": _truthy(z.get("head")),
				"zone": z.zone if z.get("zone") else ("head" if z.get("head") else "torso")}
	if shoot and shootables.size():
		var s = _castShootables(origin, dir, best.dist if best != null else maxDist, "melee" if melee else "bullets", null, blockingOnly)
		if s != null:
			best = {"kind": "shootable", "dist": s.dist, "point": s.point, "entry": s.entry}
	return best

# zombies.damage + the points fallback (GDD §6.3) + hit info for listeners. Returns killed.
func damageZombie(z, amount: float, opts := {}) -> bool:
	var g = game
	if z == null or g.zombies == null or not g.zombies.has_method("damage"):
		return false
	var econ = g.economy
	var before = econ.points if econ != null else 0
	hit = {"weaponId": opts.get("weaponId") if opts.get("weaponId") else null, "upgraded": _truthy(opts.get("upgraded", false)), "signal": opts.get("signal") if opts.get("signal") else null,
		"cause": opts.get("cause") if opts.get("cause") else "bullet", "primary": not _isFalse(opts.get("primary")), "head": _truthy(opts.get("head", false))}
	# hitmarker: weapons shows one hud.hitmarker per shot event itself (pass hitmarker:true to let zombies do it).
	# zone: always explicit, or zombies.damage would take the zone of this frame's crosshair ray on that zombie.
	var o := {"hitmarker": false}
	o.merge(opts, true)
	if not o.has("zone") or o.zone == null:
		o.zone = "head" if o.get("head") else "torso"
	if mp != null:
		o.shot = _shotSeq                  # MP: "+10 per damaging hit" dedupe per shot event (RECONCILE R17)
		if not o.has("by"):
			o.by = g.net.localId
	var killed := _truthy(g.zombies.damage(z, amount, o))
	hit = null
	if mp == null and econ != null and not _isFalse(opts.get("points")) and econ.points == before:
		var pts: Dictionary = Config.T.points
		if not killed:
			econ.add(pts.hit, "hit")
		else:
			var c = opts.get("cause")
			econ.add(pts.melee if c == "melee" else (pts.special if (c == "grenade" or c == "explosive") else (pts.head if opts.get("head") else pts.kill)), "kill")
	return killed

# ------------------------------------------------------------------------------------------ update
func update(dt: float) -> void:
	var g = game
	var p = g.player
	var input = g.input
	if p == null:
		return
	_wrapAnimator()
	if mp != null:
		mp.update(dt)
	if dt <= 0.0:
		return
	var a: Dictionary = p.anim
	a.recoil = maxf(0.0, a.recoil - dt * 6.0)
	_cool = maxf(-dt, _cool - dt)      # may dip one frame below 0: the carry keeps auto fire rates exact
	_melee.cd = maxf(0.0, _melee.cd - dt)
	_sinceSprint = 0.0 if p.sprinting else _sinceSprint + dt
	_raise = minf(1.0, _raise + dt / 0.28)
	_updateRecoil(dt)
	_updateAim()
	_updateProjectiles(dt)
	_updateGhosts(_eff().ghost)

	var control: bool = p.alive and not p.downed and not p.controlLocked and g.state == "playing" and input != null
	if mp != null and g.get("mpPaused") == true:
		control = false
	var fireDown: bool = control and input.down("fire")
	var firePressed: bool = control and input.pressed("fire")
	var fireReleased := _fireHeld and not fireDown
	_fireHeld = fireDown
	# a press made while the gun can't fire yet (sprint-to-fire, cooldown, raise) fires as soon as it can
	_pressBuf = 0.22 if firePressed else (maxf(0.0, _pressBuf - dt) if control else 0.0)

	# smoothed pose weights
	var k := 1.0 - exp(-dt / 0.06)
	_adsW += ((1.0 if p.ads else 0.0) - _adsW) * k
	_sprintW += ((1.0 if p.sprinting else 0.0) - _sprintW) * (1.0 - exp(-dt / 0.09))
	var busy: bool = _melee.t >= 0.0 or _nade.state != "none" or _tele.t >= 0.0
	_busyW += ((1.0 if busy else 0.0) - _busyW) * (1.0 - exp(-dt / 0.05))

	_updateSwap(dt)
	_updateMelee(dt, control and input.pressed("melee"))
	_updateGrenade(dt, control and input.down("grenade"), control and input.pressed("grenade"))
	_updateTele(dt, control and input.pressed("tactical"))
	if control and not busy and _swap.t <= 0.0:
		_readSwapInput(input)
	_updateReload(dt, control and input.pressed("reload"), firePressed)
	_updatePump(dt)

	var s = _slotAt(current)
	var def = currentDef()
	_updateSpread(dt, def, p)
	if s == null or def == null:
		return
	var blocked: bool = not control or _swap.t > 0.0 or busy or _raise < 0.6
	var ready: bool = not blocked and not p.sprinting and _sinceSprint >= maxf(0.0, _eff().sprintToFire) and not reloading

	var press := _pressBuf > 0.0
	if def.get("fire") == "custom":
		_updateWonder(dt, s, def, fireDown, press, fireReleased, ready, blocked)
		return
	if _autoReloadT >= 0.0:
		_autoReloadT -= dt
		if _autoReloadT < 0.0 and s.mag == 0 and s.reserve > 0 and not reloading and not busy and _swap.t <= 0.0:
			_startReload(s, def)
	if p.sprinting or blocked:
		_burst = 0
	if not ready or _cool > 0.0:
		return
	var pumpBusy: bool = def.mode == "pump" and not _pumpRacked
	if pumpBusy:
		return
	var pull := false
	if def.mode == "auto":
		pull = fireDown or press
	elif def.mode == "burst":
		if _burst > 0:
			pull = true
		elif press:
			_burst = def.burst
			pull = true
	else:
		pull = press
	if not pull:
		return
	_pressBuf = 0.0
	if s.mag <= 0:
		_burst = 0
		if s.reserve > 0:
			_startReload(s, def)
		elif press:
			_dryFire(s)
		return
	_fire(s, def)

func lateUpdate(dt = 0.0) -> void:
	if mp != null:
		mp.lateUpdate(dt if dt != null else 0.0)
	if fx != null:
		fx.update(dt if dt != null else 0.0, game.camera)

func _warnOnce(key: String, err = null) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[weapons] %s %s" % [key, str(err) if err != null else ""])

# Weapon randomness (spread, kick jitter, cosmetics): game.rand() in solo (same calls, same order); in an MP game a
# per-peer stream (clients never consume the shared world stream; MP: header).
func _r() -> float:
	if mp != null and _mpRand.is_valid():
		return _mpRand.call()
	return game.rand()

func _wonderCall(fn: String, id, ctx = null) -> Variant:
	var W = game.wonder
	if W == null or not W.has_method(fn):
		return null
	return W.call(fn, id, ctx if ctx != null else _fillCtx(0.0))

# ------------------------------------------------------------------------------------------ aim
# Crosshair ray: camera position (last frame) + this frame's look direction; starts at the player's depth so
# nothing between the camera and the hero is hit. aimPoint = nearest of level / zombies / shootables (80 m).
func _updateAim() -> void:
	var g = game
	var p = g.player
	var cam: Node3D = g.camera
	var cc = g.cam
	var kY = cc.get("_kickY") if cc != null else null
	var kP = cc.get("_kickP") if cc != null else null
	var yaw: float = p.yaw + (kY if kY else 0.0)
	var pitch: float = clampf(p.pitch + (kP if kP else 0.0), -1.35, 1.25)
	aimDir = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var a: Vector3 = cam.global_position if cam != null else p.pos + Vector3(0, 1.6, 0)
	var b: Vector3 = p.pos
	b.y = p.pos.y + 1.35
	var t0 := maxf(0.0, (b - a).dot(aimDir))
	aimOrigin = a + aimDir * t0
	var h = traceRay(aimOrigin, aimDir, MAX_RANGE, {"blockingOnly": true})
	var dist: float = maxf(0.05, h.dist) if h != null else MAX_RANGE
	aimPoint = aimOrigin + aimDir * dist
	aimDist = dist
	aimHit = h

func _updateSpread(dt: float, def, p) -> void:
	if def == null:
		spread = 1.0
		return
	_bloom = maxf(0.0, _bloom - dt * 1.6)
	var base := lerpf(def.spread[0], def.spread[1], _adsW)
	var moving := 1.0 if Vector2(p.vel.x, p.vel.z).length() > 0.6 else 0.0
	var air := 1.0 if p.grounded else 1.6
	spread = base * air * (1.0 + _bloom * 0.6 + moving * 0.12 * (1.0 - _adsW))

# ------------------------------------------------------------------------------------------ swapping
func _readSwapInput(input) -> void:
	if slots.size() < 2:
		return
	var want := -1
	var mouse = input.get("mouse")
	var wheel = mouse.get("wheel") if mouse != null else 0
	if input.pressed("weapon1"):
		want = 0
	elif input.pressed("weapon2"):
		want = 1
	elif input.pressed("weapon3"):
		want = 2
	elif input.pressed("weaponNext"):
		want = (current + 1) % slots.size()   # gamepad Y
	elif wheel:
		want = (current + (1 if wheel > 0 else slots.size() - 1)) % slots.size()
	if want >= 0 and want != current and _slotAt(want) != null:
		switchTo(want)

func _updateSwap(dt: float) -> void:
	var S := _swap
	if S.t <= 0.0:
		return
	S.t += dt
	if not S.swapped and S.t >= S.total * 0.45:
		S.swapped = true
		if _slotAt(S.to) != null:
			_equip(S.to, false)
		_play("reload_mag", {"vol": 0.35, "rate": 1.4})
	if S.t >= S.total:
		S.t = 0.0
		swapping = false

func _play(id: String, opts := {}) -> void:
	if game.audio != null:
		game.audio.play(id, opts)

# ------------------------------------------------------------------------------------------ firing
func _dryFire(s: Dictionary) -> void:
	_cool = 0.28
	_recoil.vr += 1.2
	game.events.emit("weapon:empty", {"weaponId": s.id})

func _fire(s: Dictionary, def: Dictionary) -> void:
	var g = game
	var p = g.player
	var eff := _eff()
	var rate := maxf(0.1, eff.fireRate)
	s.mag -= 1
	s.fired = s.get("fired", 0) + 1
	var interval: float = 60.0 / float(def.rpm) / rate
	# held auto / mid-burst: keep the time already overdue this frame (frame-rate independent rpm)
	var carry := minf(0.0, _cool) if ((def.mode == "auto" and _fireHeld) or (def.mode == "burst" and _burst < def.get("burst", 0))) else 0.0
	if def.mode == "burst":
		_burst -= 1
		_cool = (interval if _burst > 0 else float(def.burstGap) / rate) + carry
	elif def.mode == "pump":
		_cool = float(def.pumpTime) / rate
		_pumpT = 0.0
		_pumpRacked = false
		_pumpDur = maxf(0.3, float(def.pumpTime) / rate - 0.12)
	else:
		_cool = interval + carry
	_bloom = minf(1.0, _bloom + (0.12 if def.mode == "auto" else 0.3))

	# muzzle -> crosshair point, with a muzzle obstruction check (gun poking through a wall)
	var muzzle: Vector3 = p.muzzle()
	var b: Vector3 = p.pos
	b.y = p.pos.y + 1.3
	var origin := muzzle
	var c := muzzle - b
	var blockD := c.length()
	if blockD > 1e-3:
		c /= blockD
		var w = g.level.col.raycast(b, c, blockD)
		if w != null:
			origin = w.point - c * 0.05
	var d := aimPoint - origin
	var toAim := d.length()
	if toAim < 0.4 or aimDist < 0.6:
		d = aimDir
	else:
		d /= toAim
	var baseDir := d
	var r := baseDir.cross(UP)
	if r.length_squared() < 1e-6:
		r = Vector3(1, 0, 0)
	r = r.normalized()
	var u := r.cross(baseDir).normalized()

	var pellets: int = int(def.get("pellets", 1)) if def.get("pellets") else 1
	var spreadRad := deg_to_rad(spread)
	var ghost: bool = eff.ghost
	var shot := _beginShot(s, def)
	var style: Dictionary = def.get("tracer") if def.get("tracer") is Dictionary else {}
	var col = _tracerColor(s, def)
	if mp != null:
		mp.shotBegin(s, muzzle, ghost)
	for i in pellets:
		var rr: float
		var phi: float
		if pellets > 1:
			phi = (float(i) / pellets) * PI * 2.0 + _r() * 0.7
			rr = _r() * 0.25 if i == 0 else 0.45 + 0.55 * _r()
		else:
			phi = _r() * PI * 2.0
			rr = sqrt(_r())
		var t := tan(spreadRad) * rr
		var n := (baseDir + r * (cos(phi) * t) + u * (sin(phi) * t)).normalized()
		var end := _traceBullet(origin, n, def, s, shot, ghost)
		if mp != null:
			mp.shotPellet(end, _endKind, _endNormal)
		fx.streak(muzzle, end, style, col, i * 0.004 if pellets > 1 else 0.0)
		if style.get("style") == "scratch":
			var st2 := style.duplicate()
			st2.width = style.width * 0.5
			st2.len = style.len * 0.6
			fx.streak(muzzle, end, st2, "#FFD8A0", 0.01, u * 0.03)
		if ghost:
			fx.streak(muzzle, end, style, "#5FF4FF", 0.012, r * 0.035)
			fx.streak(muzzle, end, style, "#FF5FD2", 0.018, r * -0.035)
		if style.get("style") == "stars":
			for k in 2:
				var a := muzzle.lerp(end, 0.25 + _r() * 0.7)
				g.fx.burst(a, {"shape": "star", "count": 1, "speed": 0.6, "size": 0.07, "life": 0.45, "gravity": 0.5, "colors": [Config.PAL.marqueeGold, "#FFF3B0"]})
	_endShot(shot, s, def)
	if mp != null:
		mp.shotEnd(shot.every13)

	# feel: muzzle, smoke, casing, recoil, camera
	_muzzleFX(s, def, muzzle, baseDir)
	_kick(def, 1.0)
	if def.get("eject") == "brass":
		_eject("brass", 0.8)
	p.anim.recoil = 1
	g.events.emit("weapon:fire", {"weaponId": s.id, "upgraded": _truthy(s.upgraded)})
	if s.mag == 0 and s.reserve > 0:
		_autoReloadT = 0.3 if def.mode == "pump" else 0.18

func _tracerColor(s: Dictionary, def: Dictionary) -> Variant:
	if s.upgraded and s["signal"] and WD.SIGNAL_COLORS.has(s["signal"]):
		return WD.SIGNAL_COLORS[s["signal"]]
	var tr = def.get("tracer")
	if s.upgraded and not (tr is Dictionary and tr.get("color")):
		return Config.PAL.perpetua
	return tr.color if tr is Dictionary else "#FFE9A8"

func _kick(def: Dictionary, mul := 1.0) -> void:
	var g = game
	var ads := _adsW
	var kick: Array = def.kick if def.get("kick") else [0.02, 0.005]
	if g.cam != null and g.cam.has_method("kick"):
		g.cam.kick(kick[0] * mul * (1.0 - 0.35 * ads), (_r() - 0.5) * 2.0 * kick[1] * mul)
	if g.cam != null and g.cam.has_method("shake") and def.get("shake"):
		g.cam.shake(def.shake * mul * (1.0 - 0.4 * ads), 0.16)
	var rc: Array = def.recoil if def.get("recoil") else [0.04, 0.15]
	var R := _recoil
	R.vb += rc[0] * 30.0 * mul
	R.vr += rc[1] * 28.0 * mul
	R.vroll += (_r() - 0.5) * rc[1] * 18.0 * mul
	var an = game.player.animator
	if an != null and an.has_method("kick"):
		an.kick(minf(0.22, rc[0] * 1.5) * mul)

func _updateRecoil(dt: float) -> void:
	var R := _recoil
	var k := 420.0
	var d := 26.0
	var n := maxi(1, ceili(dt / (1.0 / 120.0)))
	var h := dt / n
	for i in n:
		R.vb += (-k * R.back - d * R.vb) * h
		R.back += R.vb * h
		R.vr += (-k * 0.8 * R.rise - d * R.vr) * h
		R.rise += R.vr * h
		R.vroll += (-k * R.roll - d * R.vroll) * h
		R.roll += R.vroll * h

func _muzzleFX(s: Dictionary, def: Dictionary, pos: Vector3, dir: Vector3) -> void:
	var g = game
	var f: Dictionary = def.flash if def.get("flash") is Dictionary else {"size": 0.45, "color": "#FFD27A"}
	var up := _truthy(s.upgraded)
	var sig = WD.SIGNAL_COLORS.get(s["signal"]) if (up and s["signal"]) else null
	var color = sig if sig else f.color
	fx.flash(pos, dir, f.size * (0.9 + _r() * 0.25), color, 0.045 if def.mode == "auto" else 0.065)
	if up:
		fx.ring(pos, dir, f.size * 0.18, f.size * 0.75, 0.2, "#ffffff", not sig)
		if sig:
			fx.ring(pos, dir, f.size * 0.12, f.size * 0.55, 0.16, sig, false)
	if s.id == "revolver_38" and up:
		# SPECIAL REPORT: the muzzle is a flashbulb pop
		fx.pop(pos, 0.9, "#EAF6FF", 0.1)
		g.fx.burst(pos, {"shape": "star", "count": 3, "speed": 2, "size": 0.07, "life": 0.4, "colors": ["#FFFFFF", "#BFE8FF"]})
	g.fx.flashLight(pos, color, 9 if def.get("pellets") else 6, 0.06)
	var smoke: float = float(def.get("smoke", 0)) if def.get("smoke") else 0.0
	var nSmoke := int(floor(smoke)) + (1 if _r() < fmod(smoke, 1.0) else 0)
	if nSmoke:
		g.fx.burst(pos, {"shape": "puff", "count": nSmoke, "size": 0.13 if def.get("pellets") else 0.08, "speed": 0.9, "life": 0.55, "gravity": -1.2, "drag": 3,
			"dir": dir, "cone": 0.5, "colors": ["#EDE6DA", "#D8CFC2"]})

func _eject(kind: String, speed := 1.0) -> void:
	var g = game
	var h = _holder()
	if h == null or not h.model.is_inside_tree():
		return
	var a := Vector3(0.03, h.muzzle.y * 0.9, h.butt.z * 0.1 - 0.06)
	var mt: Transform3D = h.model.global_transform
	a = mt * a
	var q: Quaternion = mt.basis.get_rotation_quaternion()
	var b := q * (Vector3(1.6 + _r() * 0.8, 1.6 + _r() * 1.2, 0.4 + _r() * 0.6) * speed)
	var pv: Vector3 = g.player.vel
	b.x += pv.x * 0.8
	b.z += pv.z * 0.8
	fx.eject(kind, a, b)

# Shot event: aggregates damage per zombie (pellets / pierce / splash / ghost) so each zombie is damaged once.
func _beginShot(s: Dictionary, def: Dictionary) -> Dictionary:
	_shotSeq += 1
	_aggPool.append_array(_aggVals)
	_aggKeys.clear()
	_aggVals.clear()
	return {"s": s, "def": def, "hits": 0, "kills": 0, "anyHead": false, "splashes": 0, "every13": false}

func _aggIndex(z) -> int:
	for i in _aggKeys.size():
		if is_same(_aggKeys[i], z):
			return i
	return -1

# dmg is already multiplied by the ray's zone multiplier (see _zoneMulOf); zone = the ray's zone name.
func _aggAdd(z, dmg: float, head: bool, point: Vector3, dir: Vector3, cause: String, zone := "torso") -> void:
	var i := _aggIndex(z)
	var a
	if i < 0:
		a = _aggPool.pop_back() if _aggPool.size() else {"dmg": 0.0, "head": 0, "body": 0, "point": Vector3.ZERO, "dir": Vector3.ZERO, "cause": "bullet", "n": 0, "zones": {}}
		a.dmg = 0.0
		a.head = 0
		a.body = 0
		a.n = 0
		a.cause = cause
		a.zones = {}
		a.point = point
		a.dir = dir
		_aggKeys.append(z)
		_aggVals.append(a)
	else:
		a = _aggVals[i]
	a.dmg += dmg
	a.zones[zone] = a.zones.get(zone, 0.0) + dmg
	if cause == "bullet":
		if head:
			a.head += 1
		else:
			a.body += 1
	if cause == "bullet" and a.cause != "bullet":
		a.cause = "bullet"
		a.point = point
	a.n += 1

# Zone multiplier of the zombie raycast hit zh (zombies.raycast leaves it on the zombie for this frame).
func _zoneMulOf(zh: Dictionary) -> float:
	if _finite(zh.get("mul")):
		return float(zh.mul)
	var z = zh.z
	if z != null and z.get("_rayFrame") == game.time.frame and _finite(z.get("_rayMul")):
		return float(z._rayMul)
	return _explicitZoneMul(z, zh.get("zone"))

# The multiplier zombies.damage applies for an explicitly passed zone (limb 0.8, else z.hitZones, else 1).
func _explicitZoneMul(z, zone) -> float:
	if zone == "limb":
		return 0.8
	if z != null and z.get("hitZones") is Array:
		for hz in z.hitZones:
			if hz.get("zone") == zone:
				return float(hz.mul) if _finite(hz.get("mul")) else 1.0
	return 1.0

func _endShot(shot: Dictionary, s: Dictionary, def: Dictionary) -> void:
	var g = game
	var anyHead := false
	var anyKill := false
	var hits := 0
	var upgraded := _truthy(s.upgraded)
	for idx in _aggKeys.size():
		var z = _aggKeys[idx]
		var a: Dictionary = _aggVals[idx]
		var head: bool = a.head > 0 and a.head >= a.body
		var knock: float = 0.25 * a.n if def.get("pellets") else 0.5
		# dominant zone (most damage); divide by what zombies.damage multiplies for it -> total = sum(ray dmg × zone mul)
		var zone := "head" if head else "torso"
		var zd := -1.0
		for kk in a.zones:
			if a.zones[kk] > zd:
				zd = a.zones[kk]
				zone = kk
		if head:
			zone = "head" if a.zones.has("head") else zone
		var zm := _explicitZoneMul(z, zone)
		if not (zm > 0.0):
			continue
		var killed := damageZombie(z, a.dmg / zm, {"head": head, "zone": zone, "weaponId": s.id, "point": a.point, "dir": a.dir, "knockback": knock, "cause": a.cause,
			"upgraded": upgraded, "signal": s["signal"] if s["signal"] else null, "pellets": a.n, "launch": def.get("launch", 0)})
		hits += 1
		if head:
			anyHead = true
		if killed:
			anyKill = true
			if def.get("launch") and g.fx != null and not (mp != null and mp.isClient()):
				g.fx.burst(a.point, {"shape": "star", "count": 4, "speed": 3, "size": 0.1, "colors": [Config.PAL.marqueeGold, "#FFF3B0"]})
		# hit read: white pop + sparks; head = gold stars
		fx.pop(a.point, 0.42 if head else 0.3, "#FFE27A" if head else "#FFFFFF", 0.07)
		if mp != null:
			mp.shotZombie(a.point, head)
		var back: Vector3 = -a.dir
		g.fx.burst(a.point, {"shape": "spark", "count": 7 if head else 4, "dir": back, "cone": 0.9, "speed": 5, "life": 0.2, "size": 0.035})
		if head:
			g.fx.burst(a.point, {"shape": "star", "count": 2, "speed": 2.2, "size": 0.08, "life": 0.5})
		if def.get("pageHits"):
			g.fx.burst(a.point, {"shape": "confetti", "count": 7, "speed": 3, "size": 0.11, "life": 1.2, "colors": ["#F4F1E8", "#E6DCCB", "#FFFFFF", "#D9D2C2"], "dir": back, "cone": 1.3})
	if hits and g.hud != null and g.hud.has_method("hitmarker"):
		g.hud.hitmarker(anyHead, anyKill and not (mp != null and mp.isClient()))   # MP client: the kill marker comes with the host's kill
	var L := lastShot
	L.weaponId = s.id
	L.upgraded = upgraded
	L["signal"] = s["signal"] if s["signal"] else null
	L.time = g.time.now
	L.hits = hits
	L.kills = 1 if anyKill else 0
	_aggPool.append_array(_aggVals)
	_aggKeys.clear()
	_aggVals.clear()

func _hitSetHas(z) -> bool:
	for x in _hitSet:
		if is_same(x, z):
			return true
	return false

# One bullet / pellet: zombies (pierce), shootables, level. Returns the end point (for the tracer).
func _traceBullet(origin: Vector3, dir: Vector3, def: Dictionary, s: Dictionary, shot: Dictionary, ghost: bool) -> Vector3:
	var g = game
	var Z = g.zombies
	var wall = g.level.col.raycast(origin, dir, MAX_RANGE)
	var maxD: float = wall.dist if wall != null else MAX_RANGE
	var dmg: float = float(def.dmg) * _num(g.player.mods, "damage", 1.0) * (1.0 + WD.GHOST_MUL if ghost else 1.0)
	var pierce: int = int(def.get("pierce", 0)) if def.get("pierce") else 0
	_hitSet.clear()
	var from := 0.0
	var skipEntry = null
	for iter in 12:
		var a := origin + dir * from
		var left := maxD - from
		if left <= 0.0:
			break
		var zh = Z.raycast(a, dir, left) if (Z != null and Z.has_method("raycast")) else null
		var zd: float = from + zh.dist if zh != null else INF
		var sh = _castShootables(a, dir, minf(left, zh.dist if zh != null else left), "bullets", skipEntry) if shootables.size() else null
		var sd: float = from + sh.dist if sh != null else INF
		if sh != null and sd <= zd:
			_hitShootable(sh.entry, sh.point, dir, s.id, s.upgraded, dmg * _falloff(def, sd), false, "bullet")
			fx.pop(sh.point, 0.22, "#FFFFFF", 0.06)
			if not _isFalse(sh.entry.get("blocksBullet")):
				_endKind = 2
				_bulletEnd(sh.point, s, def, shot, null)
				return sh.point
			skipEntry = sh.entry
			from = sd + 0.02
			continue
		if zh != null:
			if _hitSetHas(zh.z):
				from = zd + 0.08
				continue
			_hitSet.append(zh.z)
			var head := _truthy(zh.get("head"))
			var d: float = dmg * _falloff(def, zd) * (float(def.head) if head else 1.0) * _zoneMulOf(zh)
			_aggAdd(zh.z, d, head, zh.point, dir, "bullet", zh.zone if zh.get("zone") else ("head" if head else "torso"))
			if pierce > 0:
				pierce -= 1
				dmg *= PIERCE_MUL
				from = zd + 0.08
				continue
			_endKind = 1
			_bulletEnd(zh.point, s, def, shot, zh.z)
			return zh.point
		break
	if wall != null:
		var sk := _surfaceKind(wall)
		g.fx.impact(wall.point, wall.normal, sk)
		if mp != null:
			_endKind = 3 + maxi(0, ["wall", "wood", "metal", "glass"].find(sk))
			_endNormal = wall.normal
		_bulletEnd(wall.point, s, def, shot, null)
		return wall.point
	_endKind = 0
	return origin + dir * minf(MAX_RANGE, 60.0)

func _falloff(def: Dictionary, dist: float) -> float:
	var f = def.get("falloff")
	if not (f is Array):
		return 1.0
	var k := clampf((dist - f[0]) / maxf(1e-3, f[1] - f[0]), 0.0, 1.0)
	return lerpf(1.0, f[2], k)

func _surfaceKind(h: Dictionary) -> String:
	var tag = h.get("tag")
	if tag == "glass":
		return "glass"
	if tag == "door" or tag == "platform" or tag == "prop":
		return "wood"
	if tag == "rail" or tag == "lattice" or tag == "fence":
		return "metal"
	if tag == "floor" and game.level.has_method("surfaceAt"):
		var s = game.level.surfaceAt(h.point.x, h.point.z, h.point.y)
		if s == "wood":
			return "wood"
		if s == "metal":
			return "metal"
	return "wall"

# Bullet end effects: SPECIAL REPORT flashbulb splash, 24-HOUR MARATHON 13th-round explosive.
func _bulletEnd(point: Vector3, s: Dictionary, def: Dictionary, shot: Dictionary, directZ) -> void:
	var dm := _num(game.player.mods, "damage", 1.0)
	if def.get("splash") is Dictionary and def.splash.get("dmg"):
		_splash(point, def.splash.dmg * dm, def.splash.r, def.splash.min, directZ, "splash", "#EAF6FF")
	if def.get("every13") is Dictionary and int(s.fired) % 13 == 0 and not shot.every13:
		shot.every13 = true
		_splash(point, def.every13.dmg * dm, def.every13.r, 1.0, null, "explosive", "#FFE08A")

func _splash(point: Vector3, dmg: float, r: float, minMul: float, skipZ, cause: String, color: String) -> void:
	var g = game
	_hitList.clear()
	var list: Array = g.zombies.inRadius(point, r + 0.6, _hitList) if (g.zombies != null and g.zombies.has_method("inRadius")) else []
	for z in list:
		if is_same(z, skipZ):
			continue
		var a: Vector3 = z.pos
		a.y = z.pos.y + _num(z, "height", 1.7) * 0.5
		var d := maxf(0.0, a.distance_to(point) - _num(z, "radius", 0.35))
		if d > r:
			continue
		_aggAdd(z, dmg * lerpf(1.0, minMul, d / r), false, a, (a - point).normalized(), cause)
	fx.pop(point, r * 0.9, color, 0.12)
	fx.ring(point, (game.camera.global_position - point).normalized(), 0.15, r * 0.7, 0.22, color, false)
	g.fx.burst(point, {"shape": "star", "count": 6, "speed": 3.5, "size": 0.08, "life": 0.5, "colors": ["#FFFFFF", color]})
	g.fx.flashLight(point, color, 10, 0.12)
	_play("studio_flash", {"pos": point, "vol": 0.8})

# ------------------------------------------------------------------------------------------ pump action
func _updatePump(dt: float) -> void:
	if _pumpRacked:
		return
	var def = currentDef()
	if def == null or def.mode != "pump":
		_pumpRacked = true
		return
	var prev := _pumpT
	_pumpT += dt / (_pumpDur if _pumpDur else 0.6)
	if prev < 0.25 and _pumpT >= 0.25:
		_play("wpn_pump_rack", {"vol": 0.9})
		_eject("shell", 0.9)
	if _pumpT >= 1.0:
		_pumpT = 1.0
		_pumpRacked = true

# ------------------------------------------------------------------------------------------ reload
# Effective weapon modifiers: player.mods as written by perks / power-ups, falling back to the perk itself when a
# perk is owned but its mod was left untouched (Double Vision x1.2 rate + ghost bullets, Jump Cut x0.5 reload / swap,
# Roller Boogie 0.10 s sprint-to-fire), so either convention works and nothing applies twice.
func _perkHas(id: String) -> bool:
	var pk = game.perks
	return pk != null and pk.has_method("has") and _truthy(pk.has(id))

func _eff() -> Dictionary:
	var m: Dictionary = game.player.mods
	var E := _effMods
	var TP: Dictionary = Config.T.perks
	var fr = m.get("fireRate")
	E.fireRate = float(fr) if _finite(fr) and fr > 0 else 1.0
	if E.fireRate == 1.0 and _perkHas("double_vision"):
		E.fireRate = TP.doubleVision.fireRate
	E.ghost = _truthy(m.get("ghostBullets")) or _perkHas("double_vision")
	E.reload = timeMul(m.get("reloadSpeed"))
	if E.reload == 1.0 and _perkHas("jump_cut"):
		E.reload = TP.jumpCut.reload
	E.swap = timeMul(m.get("swapSpeed"))
	if E.swap == 1.0 and _perkHas("jump_cut"):
		E.swap = TP.jumpCut.swap
	var stf = m.get("sprintToFire")
	E.sprintToFire = float(stf) if _finite(stf) else float(Config.T.player.sprintToFire)
	if E.sprintToFire == float(Config.T.player.sprintToFire) and _perkHas("roller_boogie"):
		E.sprintToFire = TP.roller.sprintToFire
	return E

func _reloadAllowedWhileSprinting() -> bool:
	var m: Dictionary = game.player.mods
	return _truthy(m.get("reloadWhileSprinting")) or _truthy(m.get("unlimitedSprint")) or _truthy(m.get("unlimitedStamina")) or _perkHas("roller_boogie")

func _updateReload(dt: float, pressedR: bool, firePressed: bool) -> void:
	var g = game
	var p = g.player
	var s = _slotAt(current)
	var def = currentDef()
	if s == null or def == null:
		return
	if not reloading:
		if pressedR and s.mag < def.mag and s.reserve > 0 and _swap.t <= 0.0 and _melee.t < 0.0 and _nade.state == "none":
			if def.get("fire") == "custom" and _fireHeld:
				return
			_startReload(s, def)
		return
	if _reload.wonder:
		_syncWonderReload(s, def)
		return
	# interrupt a shell-by-shell reload by firing
	if def.reloadKind == "shell" and firePressed and s.mag > 0:
		cancelReload()
		_pumpRacked = true
		return
	if p.sprinting and not _reloadAllowedWhileSprinting():
		return   # paused while sprinting
	var R := _reload
	var mul: float = _eff().reload
	R.t += dt
	if def.reloadKind == "shell":
		var start: float = def.reload * mul
		var per: float = def.shellReload * mul
		if R.t >= start:
			var k := int(floor((R.t - start) / per))
			while R.shells < k and s.mag < def.mag and s.reserve > 0:
				s.mag += 1
				s.reserve -= 1
				R.shells += 1
				_play(def.reloadCue if def.get("reloadCue") else "reload_shell", {"vol": 0.9, "rate": 0.95 + _r() * 0.1})
			if s.mag >= def.mag or s.reserve <= 0:
				if R.shells > 0 and (R.t - start) - R.shells * per > -per * 0.05:
					_finishReload(s, def, false)
		p.anim.reload = clampf(R.t / R.total, 0.0, 0.999)
		_jumpCutSnips(R.t / R.total)
		return
	var u: float = R.t / R.total
	p.anim.reload = minf(0.999, u)
	_reloadParts(def, u)
	_reloadCues(def, u)
	_jumpCutSnips(u)
	if u >= 1.0:
		_finishReload(s, def, true)

func _startReload(s: Dictionary, def: Dictionary) -> bool:
	if reloading or s.mag >= def.mag or s.reserve <= 0:
		return false
	var g = game
	var mul: float = _eff().reload
	var R := _reload
	R.t = 0.0
	R.shells = 0
	R.cues = 0
	R.snips = 0
	R.kind = def.reloadKind
	R.wonder = false
	R.total = (def.reload + def.shellReload * (def.mag - s.mag)) * mul if def.reloadKind == "shell" else def.reload * mul
	if def.get("fire") == "custom":
		var ctx := _fillCtx(0.0)
		ctx.duration = R.total
		var r = _wonderCall("reload", s.id, ctx)
		if _isFalse(r) or (r is int or r is float) and r == 0:
			return false
		if (r is int or r is float) and r > 0:
			# game.wonder owns this reload (timing, ammo, weapon:reload, cues, part animation); weapons mirrors it for the pose
			R.wonder = true
			R.total = float(r)
			reloading = true
			_autoReloadT = -1.0
			_burst = 0
			return true
	reloading = true
	_autoReloadT = -1.0
	_burst = 0
	g.events.emit("weapon:reload", {"weaponId": s.id})
	if def.reloadKind == "speedloader":
		_play("reload_speedloader", {"vol": 0.5, "rate": 1.3})
	return true

# Mirrors a reload run by game.wonder (started by us or by the wonder system on an empty trigger pull).
func _syncWonderReload(s: Dictionary, def: Dictionary) -> void:
	var W = game.wonder
	var R := _reload
	var on: bool = W != null and _truthy(W.get("reloading")) and W.get("reloadId") == s.id
	if on:
		if not reloading or not R.wonder:
			reloading = true
			R.wonder = true
			R.t = 0.0
			R.cues = 0
			R.snips = 0
			R.kind = def.reloadKind
			R.total = _num(def, "reload", 1.0) * _eff().reload
			_autoReloadT = -1.0
		var rp = W.get("reloadProgress")
		var k := clampf(float(rp) if _finite(rp) else R.t / R.total, 0.0, 1.0)
		R.t = k * R.total
		_jumpCutSnips(k)
	elif reloading and R.wonder:
		reloading = false
		R.wonder = false
		R.t = 0.0
		_raise = minf(_raise, 0.75)

func _finishReload(s: Dictionary, def: Dictionary, full: bool) -> void:
	if full:
		var n := mini(def.mag - s.mag, s.reserve)
		s.mag += n
		s.reserve -= n
	cancelReload()
	_pumpRacked = true
	_raise = minf(_raise, 0.75)

const RELOAD_BEATS := {"mag": [0.18, 0.66], "belt": [0.12, 0.45, 0.8], "speedloader": [0.2, 0.62], "battery": [0.15, 0.62], "reel": [0.2, 0.7], "goo": [0.2, 0.68]}

# Sounds at the right beats of each reload kind.
func _reloadCues(def: Dictionary, u: float) -> void:
	var R := _reload
	var beats: Array = RELOAD_BEATS.get(def.reloadKind, [0.5])
	while R.cues < beats.size() and u >= beats[R.cues]:
		var i: int = R.cues
		R.cues += 1
		var cue: String = def.reloadCue if def.get("reloadCue") else "reload_mag"
		_play(cue, {"vol": 0.9, "rate": 0.9 if i == 0 else 1.1})
		if def.reloadKind == "speedloader" and i == 0:
			for k in 6:
				_ejectDrum(k)
		if def.reloadKind == "mag" and i == 0:
			_dropMagFX()

func _ejectDrum(k: int) -> void:
	var g = game
	var h = _holder()
	if h == null or not h.model.is_inside_tree():
		return
	var a: Vector3 = h.model.global_transform * Vector3(-0.04, 0.09, -0.05 + (k % 3) * 0.01)
	var b := Vector3((_r() - 0.5) * 1.2, -0.5 - _r(), (_r() - 0.5) * 1.2)
	fx.eject("brass", a, b)

func _dropMagFX() -> void:
	var h = _holder()
	if h == null or not h.model.is_inside_tree():
		return
	var a: Vector3 = h.model.global_transform * Vector3(0, -0.12, -0.08)
	game.fx.burst(a, {"shape": "puff", "count": 2, "size": 0.05, "speed": 0.4, "life": 0.3, "colors": ["#D8CFC2"]})

# Jump Cut Coffee: reloads visibly skip frames (a white splice flash + "snip-tk").
func _jumpCutSnips(u: float) -> void:
	if not _perkHas("jump_cut"):
		return
	var R := _reload
	var at := [0.3, 0.62]
	while R.snips < at.size() and u >= at[R.snips]:
		R.snips += 1
		_play("jumpcut_snip", {"vol": 0.8})
		var h = _holder()
		if h == null or not h.model.is_inside_tree():
			continue
		var mt: Transform3D = h.model.global_transform
		fx.bar(mt * Vector3(-0.12, 0.18, -0.1), mt * Vector3(0.12, -0.12, -0.1), 0.012, "#FFFFFF", 0.07)
		fx.pop(mt.origin, 0.35, "#FFFFFF", 0.05)

# Part animation for the current reload (u 0..1): mag drop/insert, drum swing, cover, battery, reels, goo.
func _reloadParts(_def: Dictionary, u: float) -> void:
	var h = _holder()
	if h == null:
		return
	reloadPartsOf(h, u)

# (static: weapons_net.gd plays the same part animation on teammates' held copies from their streamed reload progress)
static func reloadPartsOf(h: Dictionary, u: float) -> void:
	var P2: Dictionary = h.parts
	var rest: Dictionary = h.rest
	var inOut := func(a: float, b: float, c: float, d: float) -> float: return smooth(a, b, u) * (1.0 - smooth(c, d, u))
	var mag = P2.get("mag")
	if mag is Node3D and rest.has(mag):
		var r: Dictionary = rest[mag]
		var out := smooth(0.15, 0.3, u)
		var back := smooth(0.52, 0.72, u)
		var drop := out * 0.3 if out < 1.0 else (1.0 - back) * 0.3
		mag.position = r.pos - Vector3(0, drop, 0)
		mag.visible = not (u > 0.3 and u < 0.52)
	var drum = P2.get("drum")
	if drum is Node3D and rest.has(drum):
		var r: Dictionary = rest[drum]
		var k: float = inOut.call(0.08, 0.2, 0.74, 0.84)
		drum.position = r.pos - Vector3(0.045 * k, 0, 0)
		drum.rotation.z = r.rot.z + ((u - 0.74) * 40.0 if u > 0.74 else 0.0)
	var cover = P2.get("cover")
	if cover is Node3D and rest.has(cover):
		var r: Dictionary = rest[cover]
		cover.rotation.x = r.rot.x - 1.1 * inOut.call(0.05, 0.16, 0.82, 0.92)
	var battery = P2.get("battery")
	if battery is Node3D and rest.has(battery):
		var r: Dictionary = rest[battery]
		var k: float = inOut.call(0.08, 0.16, 0.55, 0.7)
		battery.position = r.pos + Vector3(0, 0.03 * sin(k * PI), 0.09 * k)
		battery.visible = not (u > 0.3 and u < 0.5)
	var goo = P2.get("goo")
	if goo is Node3D and rest.has(goo):
		var r: Dictionary = rest[goo]
		var k: float = inOut.call(0.1, 0.25, 0.6, 0.75)
		goo.position = r.pos + Vector3(0, 0.12 * k, 0)
		goo.visible = not (u > 0.3 and u < 0.5)
	for nm in ["reelL", "reelR"]:
		var o = P2.get(nm)
		if o is Node3D and rest.has(o):
			o.rotation.y = rest[o].rot.y + u * 30.0

# ------------------------------------------------------------------------------------------ wonder weapons
func _fillCtx(dt: float) -> Dictionary:
	var g = game
	var p = g.player
	var c := _ctx
	var s = _slotAt(current)
	var h = _holder()
	c.def = WD.weaponDef(s.id, s.upgraded) if s != null else null
	c.upgraded = s != null and _truthy(s.upgraded)
	c["signal"] = (s["signal"] if s["signal"] else null) if s != null else null
	c.slot = s
	c.origin = aimOrigin
	c.dir = aimDir
	c.muzzle = p.muzzle()
	c.aimPoint = aimPoint
	c.aimDist = aimDist
	c.ads = _truthy(p.ads)
	c.dt = dt
	c.model = h.model if h != null else null
	c.time = g.time.now
	return c

# Wonder weapons: game.wonder.fire every frame while held (not while swapping / meleeing / throwing / raising).
# The trigger reaches it only when the weapon may fire (not sprinting, sprint-to-fire elapsed, not reloading);
# a press made while not ready is buffered (0.22 s). Wonder owns ammo, empty-mag reloads, dry fire and its
# own weapon:fire / weapon:reload events (the header of wonder.gd); weapons mirrors its reload for the
# pose and adds the held-model recoil spring.
func _updateWonder(dt: float, s: Dictionary, def: Dictionary, down: bool, pressed: bool, released: bool, ready: bool, blocked: bool) -> void:
	var g = game
	var W = g.wonder
	var hasW: bool = W != null and W.has_method("fire")
	if hasW:
		_syncWonderReload(s, def)
	if hasW:
		if blocked:
			return
		var ctx := _fillCtx(dt)
		var pr := ready and pressed
		ctx.triggerDown = ready and (down or pr)
		ctx.triggerPressed = pr
		ctx.triggerReleased = released
		ctx.ready = ready
		if pr:
			_pressBuf = 0.0
		_inWonder = true
		_wonderEmitted = false
		var r = W.fire(s.id, ctx)
		_inWonder = false
		if _truthy(r):
			_wonderFired(s, def, r, _wonderEmitted)
		_syncWonderReload(s, def)
		# an emptied battery / reel / cartridge reloads by itself shortly after the trigger is let go (like the guns)
		if s.mag == 0 and s.reserve > 0 and not reloading and not down and ready:
			_autoReloadT = 0.35 if _autoReloadT < 0.0 else _autoReloadT - dt
			if _autoReloadT <= 0.0:
				_autoReloadT = -1.0
				_startReload(s, def)
		elif s.mag > 0:
			_autoReloadT = -1.0
		return
	# Fallback while game.wonder is not installed: a plain hitscan zap (weapons runs its reload).
	if _autoReloadT >= 0.0:
		_autoReloadT -= dt
		if _autoReloadT < 0.0 and s.mag == 0 and s.reserve > 0 and not reloading and not down:
			_startReload(s, def)
	if not ready or _cool > 0.0 or not pressed:
		return
	_pressBuf = 0.0
	if s.mag <= 0:
		if s.reserve > 0:
			_startReload(s, def)
		else:
			_dryFire(s)
		return
	_warnOnce("wonder-missing", "game.wonder is not installed: wonder weapons use a hitscan fallback")
	var fb: Dictionary = def.duplicate()
	fb.merge({"pellets": 1, "pierce": 2, "falloff": null, "head": 1, "dmg": def.dmg if def.get("dmg") else 1000, "spread": [2, 1],
		"tracer": {"color": "#9CFF57", "width": 0.06, "len": 4, "speed": 150}, "flash": {"size": 0.6, "color": "#9CFF57"}, "mode": "semi", "smoke": 0, "eject": null}, true)
	_fire(s, fb)

# r: true | { kick, shake, recoil, noEvent }. emitted: the wonder system already emitted weapon:fire (and kicked
# the camera itself), so only the held-model spring, a touch of shake and the crosshair bloom are added here.
func _wonderFired(s: Dictionary, def: Dictionary, r, emitted := false) -> void:
	var g = game
	var o: Dictionary = r if r is Dictionary else {}
	var mul: float = float(o.kick) if o.get("kick") != null else 1.0
	if emitted:
		var rc: Array = o.recoil if o.get("recoil") != null else (def.recoil if def.get("recoil") != null else [0.04, 0.15])
		var R := _recoil
		R.vb += rc[0] * 30.0 * mul
		R.vr += rc[1] * 22.0 * mul
		R.vroll += (_r() - 0.5) * rc[1] * 14.0 * mul
		var sh = o.shake if o.get("shake") != null else def.get("shake")
		if sh and g.cam != null and g.cam.has_method("shake"):
			g.cam.shake(sh * 0.6 * mul * (1.0 - 0.4 * _adsW), 0.16)
	else:
		var d2: Dictionary = def.duplicate()
		d2.shake = o.shake if o.get("shake") != null else def.get("shake")
		d2.recoil = o.recoil if o.get("recoil") != null else def.get("recoil")
		_kick(d2, mul)
		if not o.get("noEvent"):
			g.events.emit("weapon:fire", {"weaponId": s.id, "upgraded": _truthy(s.upgraded)})
	g.player.anim.recoil = 1
	_bloom = minf(1.0, _bloom + 0.3)

# ------------------------------------------------------------------------------------------ melee
func _updateMelee(dt: float, pressed: bool) -> void:
	var g = game
	var p = g.player
	var M := _melee
	var D: Dictionary = WD.WEAPON_DEFS.melee
	if M.t < 0.0:
		if not pressed or M.cd > 0.0 or _nade.state != "none" or _tele.t >= 0.0 or _swap.t > 0.0:
			return
		cancelReload()
		_burst = 0
		M.t = 0.0
		M.hit = false
		M.cd = D.cd
		M.target = null
		# lunge toward the zombie under the crosshair (GDD §6.2: up to 2.5 m)
		var z = _meleeTarget(D.reach + D.lunge)
		if z != null:
			var dx: float = z.pos.x - p.pos.x
			var dz: float = z.pos.z - p.pos.z
			var dist := Vector2(dx, dz).length()
			var need := clampf(dist - _num(z, "radius", 0.35) - 0.55, 0.0, D.lunge)
			if need > 0.15 and p.get("knock") != null:
				p.knock += Vector3(dx / dist, 0, dz / dist) * (need * 6.2)
			M.target = z
		_attachMeleeProp(true)
		p.anim.melee = 1e-4
		if mp != null:
			mp.event(mp.K_MELEE)
		return
	M.t += dt
	var u: float = M.t / D.time
	p.anim.melee = 1e-4
	if not M.hit and u >= D.hitAt:
		M.hit = true
		var h := _meleeStrike()
		g.events.emit("weapon:melee", {"hit": h})
	if u >= 1.0:
		M.t = -1.0
		p.anim.melee = 0
		_attachMeleeProp(false)
		_raise = minf(_raise, 0.7)

func _meleeTarget(range_v: float) -> Variant:
	var g = game
	var p = g.player
	if g.zombies == null or g.zombies.get("alive") == null:
		return null
	var fx_ := aimDir.x
	var fz := aimDir.z
	var fl := Vector2(fx_, fz).length()
	if fl == 0.0:
		fl = 1.0
	var best = null
	var bestScore := INF
	for z in g.zombies.alive:
		if z.state == "dying":
			continue
		var dx: float = z.pos.x - p.pos.x
		var dz: float = z.pos.z - p.pos.z
		var dy: float = z.pos.y - p.pos.y
		var d := Vector2(dx, dz).length()
		if d > range_v + _num(z, "radius", 0.35) or absf(dy) > 1.6:
			continue
		var cosv := (dx * fx_ + dz * fz) / (d * fl) if d > 1e-3 else 1.0
		if cosv < (0.35 if d < 1.4 else 0.88):
			continue
		var a := Vector3(p.pos.x, p.pos.y + 1.1, p.pos.z)
		var b := Vector3(z.pos.x, z.pos.y + 1.1, z.pos.z)
		if not g.level.col.lineOfSight(a, b):
			continue
		var score := d * (1.6 - cosv)
		if score < bestScore:
			bestScore = score
			best = z
	return best

func _meleeStrike() -> bool:
	var g = game
	var p = g.player
	var D: Dictionary = WD.WEAPON_DEFS.melee
	var z = _meleeTarget(D.reach + 0.25)
	if z == null:
		var t = _melee.target
		if t != null and t.state != "dying" and Vector2(t.pos.x - p.pos.x, t.pos.z - p.pos.z).length() < D.reach + _num(t, "radius", 0.35) + 0.3:
			z = t
	var c := Vector3(aimDir.x, 0, aimDir.z).normalized()
	if z != null:
		var a := Vector3(z.pos.x, z.pos.y + _num(z, "height", 1.7) * 0.62, z.pos.z)
		if mp != null:
			_shotSeq += 1
		var killed := damageZombie(z, D.dmg * _num(p.mods, "meleeDamage", 1.0), {"head": false, "weaponId": "melee", "point": a, "dir": c, "knockback": 2.5, "cause": "melee", "melee": true})
		if g.hud != null and g.hud.has_method("hitmarker"):
			g.hud.hitmarker(false, killed and not (mp != null and mp.isClient()))
		fx.pop(a, 0.6, "#FFFFFF", 0.09)
		if mp != null:
			mp.meleeHit(1, a)
		fx.ring(a, (g.camera.global_position - a).normalized(), 0.1, 0.55, 0.18, "#FFE27A", false)
		g.fx.burst(a, {"shape": "star", "count": 5, "speed": 3, "size": 0.1, "life": 0.5})
		g.fx.burst(a, {"shape": "spark", "count": 8, "dir": c, "cone": 0.8, "speed": 6, "life": 0.2})
		if g.cam != null and g.cam.has_method("shake"):
			g.cam.shake(0.22, 0.2)
		g.hitStop(0.06 if killed else 0.04)
		return true
	# shootables (Telly bump, toys): a small fan of rays at chest height
	var o: Vector3 = p.pos
	o.y = p.pos.y + 1.2
	var best = null
	for i in range(-2, 3):
		var d := c.rotated(UP, i * 0.3)
		d.y = clampf(aimDir.y, -0.5, 0.5)
		d = d.normalized()
		var wall = g.level.col.raycast(o, d, D.reach + 0.5)
		var sh = _castShootables(o, d, wall.dist if wall != null else D.reach + 0.5, "melee")
		if sh != null and (best == null or sh.dist < best.dist):
			best = sh.duplicate()
			best.dir = d
	if best != null:
		_hitShootable(best.entry, best.point, best.dir, "melee", false, D.dmg * _num(p.mods, "meleeDamage", 1.0), true, "melee")
		fx.pop(best.point, 0.5, "#FFFFFF", 0.08)
		if mp != null:
			mp.meleeHit(2, best.point)
		g.fx.burst(best.point, {"shape": "star", "count": 4, "speed": 2.5, "size": 0.09, "life": 0.45})
		if g.cam != null and g.cam.has_method("shake"):
			g.cam.shake(0.18, 0.18)
		g.hitStop(0.04)
		return true
	return false

func _attachMeleeProp(on: bool) -> void:
	var g = game
	var p = g.player
	var M := _melee
	if p.hero == null:
		return
	var handL: Node3D = p.hero.slots.handL
	if on:
		if M.propHero != p.heroId:
			if M.prop != null:
				DAU.detach(M.prop)
				M.prop.queue_free()
			M.prop = WM.buildMeleeProp(p.heroId, g)
			M.propHero = p.heroId
			if M.prop != null:
				M.prop.scale = Vector3(1.15, 1.15, 1.15)
				M.prop.quaternion = qEuler(0, PI, 0)
				g.mats.applyHeroFade(M.prop)
		if M.prop != null and M.prop.get_parent() != handL:
			DAU.detach(M.prop)
			handL.add_child(M.prop)
		if M.prop != null:
			M.prop.visible = true
	elif M.prop != null:
		M.prop.visible = false

# ------------------------------------------------------------------------------------------ grenades
func _jumpCutMul() -> float:
	return 0.7 if _perkHas("jump_cut") else 1.0

func _updateGrenade(dt: float, down: bool, pressed: bool) -> void:
	var p = game.player
	var N := _nade
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	if N.state == "none":
		if not pressed or grenades <= 0 or _melee.t >= 0.0 or _tele.t >= 0.0 or _swap.t > 0.0:
			return
		cancelReload()
		_burst = 0
		N.state = "cook"
		N.t = 0.0
		N.cook = 0.0
		grenades -= 1
		_showNade(true)
		if mp != null:
			mp.event(mp.K_COOK)
		_play("reload_mag", {"vol": 0.4, "rate": 1.6})
		return
	N.cook += dt
	if N.state == "cook":
		N.t += dt
		if N.cook >= G.fuse:            # cooked too long: it goes off in the hand
			_showNade(false)
			var a: Vector3 = p.hero.slots.handL.global_position if p.hero != null else p.pos
			_explode(a, true)
			N.state = "recover"
			N.t = 0.0
			return
		if not down and N.t > 0.12:
			N.state = "throw"
			N.t = 0.0
			N.released = false
		_animateNadeModel(N.cook / G.fuse)
		return
	if N.state == "throw":
		var dur := 0.36 * _jumpCutMul()
		N.t += dt
		_animateNadeModel(N.cook / G.fuse)
		if not N.released and N.t >= dur * 0.42:
			N.released = true
			_showNade(false)
			_launchGrenade(N.cook)
		if N.t >= dur:
			N.state = "recover"
			N.t = 0.0
		return
	if N.state == "recover":
		N.t += dt
		if N.t >= 0.16:
			N.state = "none"
			_raise = minf(_raise, 0.7)

func _showNade(on: bool) -> void:
	var g = game
	var p = g.player
	var N := _nade
	if p.hero == null:
		return
	if N.model == null:
		N.model = WM.buildGrenadeModel(g)
		N.model.scale = Vector3(1.25, 1.25, 1.25)
		g.mats.applyHeroFade(N.model)
	var handL: Node3D = p.hero.slots.handL
	if on and N.model.get_parent() != handL:
		DAU.detach(N.model)
		handL.add_child(N.model)
	N.model.visible = on

# Tiny Tele in the left hand during the Q wind-up (hidden at release: the wonder system spawns the live one).
func _showTele(on: bool) -> void:
	var g = game
	var p = g.player
	var TT := _tele
	if p.hero == null:
		return
	if TT.model == null and on:
		TT.model = WM.buildTeleModel(g)
		TT.model.scale = Vector3(0.9, 0.9, 0.9)
		TT.model.quaternion = qEuler(0, PI, 0)
		g.mats.applyHeroFade(TT.model)
	if TT.model == null:
		return
	var handL: Node3D = p.hero.slots.handL
	if on and TT.model.get_parent() != handL:
		DAU.detach(TT.model)
		handL.add_child(TT.model)
	TT.model.visible = on

func _animateNadeModel(k: float) -> void:
	var m = _nade.model
	if m == null:
		return
	var parts = DAU.ud(m).get("parts")
	if not (parts is Dictionary):
		return
	var fil = parts.get("filament")
	if fil is Node3D:
		fil.visible = sin(game.time.now * (18.0 + k * 60.0)) > -0.3

func _launchGrenade(cooked: float) -> void:
	var g = game
	var p = g.player
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var origin: Vector3 = p.hero.slots.handL.global_position
	var a := aimPoint - origin
	var d := a.length()
	var dir := a / d if d > 0.5 else aimDir
	var speed: float = G.throwSpeed
	var vel := dir * speed + UP * float(G.throwUp)
	vel.x += p.vel.x * 0.5
	vel.z += p.vel.z * 0.5
	var model: Node3D = WM.buildGrenadeModel(g)
	_xyzOrder(model)
	model.scale = Vector3(1.25, 1.25, 1.25)
	model.position = origin
	g.scene.add_child(model)
	var pool = g.fx.lightPool(origin, 0.8, "#FF8A2E", 0.35) if g.fx.has_method("lightPool") else null
	_projectiles.append({"kind": "grenade", "pos": origin, "vel": vel, "fuse": G.fuse - cooked, "model": model,
		"spin": Vector3(_r() * 14 - 7, _r() * 10 + 6, _r() * 8 - 4), "rest": false, "pool": pool, "bounceT": 0.0})
	if mp != null:
		_projectiles[-1].nid = mp.nadeThrown(origin, vel, G.fuse - cooked)
	_play("grenade_throw", {"pos": origin})

func _updateProjectiles(dt: float) -> void:
	var g = game
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var i := _projectiles.size() - 1
	while i >= 0:
		var pr: Dictionary = _projectiles[i]
		pr.fuse -= dt
		pr.bounceT -= dt
		if not pr.rest:
			pr.vel.y -= G.gravity * dt
			var step: float = pr.vel.length() * dt
			if step > 1e-5:
				var d: Vector3 = pr.vel / pr.vel.length()
				var w = g.level.col.raycast(pr.pos, d, step + G.radiusBody)
				var zh = g.zombies.raycast(pr.pos, d, step + G.radiusBody) if (g.zombies != null and g.zombies.has_method("raycast")) else null
				if w != null and (zh == null or w.dist <= zh.dist):
					_bounce(pr, w.point, w.normal, w.dist, d)
				elif zh != null:
					var n := Vector3(pr.pos.x - zh.z.pos.x, 0.3, pr.pos.z - zh.z.pos.z).normalized()
					_bounce(pr, zh.point, n, zh.dist, d, 0.25)
				else:
					pr.pos += pr.vel * dt
			pr.model.rotation.x += pr.spin.x * dt
			pr.model.rotation.y += pr.spin.y * dt
			pr.model.rotation.z += pr.spin.z * dt
			if pr.pos.y < -20.0:
				pr.fuse = 0.0
		pr.model.position = pr.pos
		var parts = DAU.ud(pr.model).get("parts")
		var fil = parts.get("filament") if parts is Dictionary else null
		if fil is Node3D:
			fil.visible = sin(g.time.now * (30.0 + (1.0 - pr.fuse / G.fuse) * 70.0)) > -0.2
		if pr.pool != null:
			pr.pool.set_({"pos": Vector3(pr.pos.x, g.level.col.floorAt(pr.pos.x, pr.pos.z, pr.pos.y + 0.1) + 0.02, pr.pos.z), "intensity": 0.25 + 0.2 * randf()})
		if pr.get("remote"):
			# MP: an observer's copy of another player's grenade: its blast comes with weapons.net_nadeFx (the host
			# blows it up itself when the thrower is gone or silent 2 s past the fuse: mp.orphanBoom)
			if pr.fuse <= 0.0 and mp != null and mp.orphanBoom(pr):
				_removeProjectile(pr)
				_projectiles.remove_at(i)
			elif pr.fuse < -2.0:
				_removeProjectile(pr)
				_projectiles.remove_at(i)
		elif pr.fuse <= 0.0:
			_explode(pr.pos, false, pr.get("nid", -1))
			_removeProjectile(pr)
			_projectiles.remove_at(i)
		i -= 1

func _bounce(pr: Dictionary, point: Vector3, normal: Vector3, _dist: float, _dir: Vector3, rest = null) -> void:
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	pr.pos = point + normal * (G.radiusBody + 0.005)
	var vn: float = pr.vel.dot(normal)
	var v5 := normal * vn
	pr.vel = (pr.vel - v5) * float(G.friction) + v5 * -(float(rest) if rest != null else float(G.restitution))
	pr.spin *= 0.7
	var sp: float = pr.vel.length()
	if absf(vn) > 1.6 and pr.bounceT <= 0.0:
		_play("grenade_bounce", {"pos": pr.pos, "vol": clampf(absf(vn) / 8.0, 0.25, 1.0)})
		pr.bounceT = 0.08
	if normal.y > 0.6 and sp < 1.2:
		pr.rest = true
		pr.vel = Vector3.ZERO
		pr.model.rotation = Vector3(PI / 2, pr.model.rotation.y, 0)

func _removeProjectile(pr: Dictionary) -> void:
	if pr.model != null and is_instance_valid(pr.model):
		DAU.detach(pr.model)
		pr.model.queue_free()
	if pr.pool != null:
		pr.pool.remove()

# Tube grenade blast. Solo: damage, self-damage, FX in the original order. MP (RECONCILE R17: a host-decided area
# action): the host resolves the victims (its own grenades here, a client's through weapons.net_nadeBoom), the
# thrower takes its own self-damage, every peer plays the FX (others through weapons.net_nadeFx).
func _explode(pos: Vector3, inHand: bool, nid := -1) -> void:
	var g = game
	var p = g.player
	var base := _blastBase(_num(p.mods, "damage", 1.0))
	if mp == null or not mp.isClient():
		_blastDamage(pos, base, g.net.localId if mp != null else null)
	var pd := _blastSelf(pos, base)
	_blastFx(pos, inHand, pd, g.net.localId if mp != null else null)
	if mp != null:
		mp.nadeExploded(nid, pos, inHand, _num(p.mods, "damage", 1.0))

func _blastBase(dmgMul: float) -> float:
	var g = game
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var rnd = g.rounds.get("round") if g.rounds != null else null
	var round_v: int = maxi(1, int(rnd) if rnd else 1)
	return (G.dmgBase + G.dmgPerRound * round_v) * dmgMul

# Zombies in the radius with line of sight + the boss. by: attacker peer id (MP) or null (solo). -> [hits, kills]
func _blastDamage(center: Vector3, base: float, by = null) -> Array:
	var g = game
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var r: float = G.radius
	_hitList.clear()
	var list: Array = g.zombies.inRadius(center, r + 0.8, _hitList).duplicate() if (g.zombies != null and g.zombies.has_method("inRadius")) else []
	var hits := 0
	var kills := 0
	if by != null:
		_shotSeq += 1
	for z in list:
		var a: Vector3 = z.pos
		a.y = z.pos.y + _num(z, "height", 1.7) * 0.5
		var d := a.distance_to(center)
		if d > r + _num(z, "radius", 0.35):
			continue
		var b := center
		b.y = center.y + 0.15
		if not g.level.col.lineOfSight(b, a):
			continue
		var k := clampf(d / r, 0.0, 1.0)
		var dmg := base * lerpf(1.0, G.edgeMul, k)
		var dir := a - center
		dir.y = 0.4
		dir = dir.normalized()
		var o := {"head": false, "weaponId": "tube_grenade", "point": a, "dir": dir, "knockback": 4.0 * (1.0 - k) + 1.0, "cause": "grenade"}
		if by != null:
			o.by = by
		if damageZombie(z, dmg, o):
			kills += 1
		hits += 1
	if hits and g.hud != null and g.hud.has_method("hitmarker") and (by == null or by == g.net.localId):
		g.hud.hitmarker(false, kills > 0)
	# bosses and anything else that wants blast damage
	var boss = g.boss
	var bp = null
	if boss != null:
		bp = boss.get("pos")
		if bp == null and boss.get("group") != null:
			bp = boss.group.position
	if boss != null and bp is Vector3 and (boss.get("active") or boss.get("alive")) and boss.has_method("damage") and bp.distance_to(center) < r + 2.0:
		var bo := {"weaponId": "tube_grenade", "point": center, "cause": "grenade"}
		if by != null:
			bo.by = by
		boss.damage(base * 0.5, bo)
	return [hits, kills]

# Self damage (GDD §9.3: at most 40, x0.5 with Wobble-Up): the local player only (no friendly fire). -> distance
func _blastSelf(center: Vector3, base: float) -> float:
	var p = game.player
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var r: float = G.radius
	var pa: Vector3 = p.pos
	pa.y = p.pos.y + 0.9
	var pd := pa.distance_to(center)
	if pd < r:
		var wob: float = G.wobbleSelf if _perkHas("wobble_up") else 1.0
		var dmg := minf(G.selfMax, base * lerpf(1.0, G.edgeMul, pd / r)) * wob
		p.hurt(dmg, center)
		if p.has_method("knockback"):
			var kb := pa - center
			kb.y = 0.0
			p.knockback(kb.normalized() * (5.0 * (1.0 - pd / r)))
	return pd

# FX: orange puff cloud of spheres, sparks, glass shards, scorch, shockwave ring, light, shake (pd = distance to the
# local player). by: MP thrower id (added to weapon:grenade, RECONCILE R7) or null (solo payload unchanged).
func _blastFx(center: Vector3, inHand: bool, pd: float, by = null) -> void:
	var g = game
	var G: Dictionary = WD.WEAPON_DEFS.tube_grenade
	var r: float = G.radius
	g.fx.burst(center, {"shape": "puff", "count": 16, "size": 0.5, "speed": 4.2, "life": 0.8, "gravity": -1.5, "drag": 3.2, "colors": ["#FF8A2E", "#FFB347", "#FFD27A", "#E3662B"]})
	g.fx.burst(center, {"shape": "puff", "count": 9, "size": 0.55, "speed": 2.2, "life": 1.5, "gravity": -1.2, "drag": 2.5, "colors": ["#6A5A68", "#8A7A80", "#5A4A5A"]})
	g.fx.burst(center, {"shape": "spark", "count": 34, "speed": 13, "life": 0.45, "size": 0.05})
	g.fx.burst(center, {"shape": "star", "count": 8, "speed": 5, "size": 0.06, "life": 0.7, "colors": ["#DDF3FF", "#FFFFFF", "#BFE8FF"]})
	fx.pop(center, 2.6, "#FFB347", 0.14)
	fx.ring(Vector3(center.x, g.level.col.floorAt(center.x, center.z, center.y + 0.3) + 0.08, center.z), UP, 0.4, r, 0.4, "#FF9A3C", false)
	var fy: float = g.level.col.floorAt(center.x, center.z, center.y + 0.3)
	if fy > -INF and center.y - fy < 1.5:
		g.fx.decal(Vector3(center.x, fy + 0.01, center.z), UP, "scorch", 2.6)
	g.fx.flashLight(center, "#FF9A3C", 22, 0.28)
	if g.cam != null and g.cam.has_method("shake"):
		g.cam.shake(clampf(0.75 * (1.0 - pd / 16.0), 0.1, 0.75), 0.5)
	_play("grenade_explode", {"pos": center})
	var ev := {"pos": center, "inHand": _truthy(inHand)}
	if by != null:
		ev.by = by
		if by != g.net.localId:
			ev.remote = true
	g.events.emit("weapon:grenade", ev)

# ------------------------------------------------------------------------------------------ Tiny Tele (Q)
func _updateTele(dt: float, pressed: bool) -> void:
	var g = game
	var p = g.player
	var TT := _tele
	if TT.t < 0.0:
		if not pressed or teles <= 0 or _melee.t >= 0.0 or _nade.state != "none" or _swap.t > 0.0:
			return
		if g.wonder == null or not g.wonder.has_method("throwTele"):
			return
		cancelReload()
		TT.t = 0.0
		TT.thrown = false
		_showTele(true)
		if mp != null:
			mp.event(mp.K_WIND)
		return
	TT.t += dt
	var dur := 0.42 * _jumpCutMul()
	if not TT.thrown and TT.t >= dur * 0.45:
		TT.thrown = true
		_showTele(false)
		var c := _teleCtx
		c.origin = p.hero.slots.handL.global_position if p.hero != null else p.pos
		c.dir = (aimPoint - c.origin).normalized()
		c.velocity = c.dir * (11.0 / _jumpCutMul()) + UP * 3.5
		c.aimPoint = aimPoint
		# take it first: the wonder system then sees the count already dropped and does not consume a second one
		var before := teles
		teles = maxi(0, teles - 1)
		var ok = g.wonder.throwTele(c)
		if _isFalse(ok):
			teles = before      # (the wonder system plays tele_throw itself)
	if TT.t >= dur:
		TT.t = -1.0
		_raise = minf(_raise, 0.7)

# ------------------------------------------------------------------------------------------ pose (IK)
# Hooks the hero animator once so the weapon pose runs after the procedural animation (and after the baked-art
# rest offsets): the JS wrapped animator.update; rig.gd runs animator.postUpdate Callables at the end of update().
# Skipped while another system drives animator.override (commercial pantomimes, replays).
func _wrapAnimator() -> void:
	var a = game.player.animator
	if a == null:
		return
	var id: int = a.get_instance_id()
	if _wrapped.has(id):
		return
	_wrapped[id] = true
	if not ("postUpdate" in a):
		_warnOnce("pose", "animator has no postUpdate hook")
		return
	a.postUpdate.append(func(rig, dt):
		var ov = a.override
		if ov == null or (ov is Callable and not (ov as Callable).is_valid()):
			_poseFn.call(rig, dt))

func _poseSafe(rig, dt: float) -> void:
	_pose(rig, dt)

func _pose(rig, _dt: float) -> void:
	var g = game
	var p = g.player
	if p.hero == null or not p.alive or p.downed:
		return
	var J: Dictionary = rig.joints
	var h = _holder()
	var hasGun: bool = h != null and is_same(p.weaponModel, h.holder) and _slotAt(current) != null
	var leftBusy: bool = _melee.t >= 0.0 or _nade.state != "none" or _tele.t >= 0.0
	if not hasGun and not leftBusy:
		return
	if not (J.chest as Node3D).is_inside_tree():
		return
	var def = h.def if hasGun else null
	var hold: Dictionary = HOLDS.get(def.get("hold") if def != null and def.get("hold") else "pistol", HOLDS.pistol)
	var dh = rig.dims.get("height") if rig.dims is Dictionary else null
	var hs: float = (float(dh) if dh else 1.8) / 1.8
	var ads := _adsW
	var sprint := _sprintW
	var busy := _busyW

	# upper body: bladed stance for long guns, extra pitch follow
	var pitch: float = p.pitch
	var blade: float = hold.chest * (1.0 - sprint) * (1.0 if hasGun else 0.0)
	J.chest.rotation.y += blade + _meleeTwist()
	J.head.rotation.y -= blade * 0.8
	J.spine.rotation.x += pitch * 0.12 * (1.0 - sprint)

	# frames: body yaw + aim (toward the crosshair point, at least 4 m out)
	var v1: Vector3 = J.shoulderR.global_position
	var v2: Vector3 = J.shoulderL.global_position
	var M := (v1 + v2) * 0.5
	var qBody := Quaternion(UP, p.model.rotation.y)
	var a := aimPoint - M
	if a.length_squared() < 16.0 or a.dot(aimDir) < 0.0:
		a = aimOrigin + aimDir * (maxf(aimDist, 4.0) + 2.0) - M
	var qAim := Basis.looking_at(a.normalized(), UP).get_rotation_quaternion()

	if hasGun:
		# grip / butt anchor
		var off: Vector3 = v3a(hold.hip).lerp(v3a(hold.ads), ads) * hs
		var qGun := qAim
		if hold.get("pitch"):
			qGun = qGun * Quaternion(X_AXIS, hold.pitch * (1.0 - ads))
		var grip: Vector3
		if hold.mode == "butt":
			var sc: float = h.holder.scale.x
			var c: Vector3 = qGun * (h.butt * sc)
			grip = M + qAim * off - c
		else:
			grip = M + qAim * off

		# layers: recoil, reload tilt, pump, swap/raise, sprint low-ready, busy (melee / throw)
		var R := _recoil
		grip += qGun * Vector3(0, 0, R.back * hs)
		qGun = qGun * qEuler(R.rise, 0, R.roll)
		var rl := _reloadPoseWeight() if reloading else 0.0
		if rl > 0.0:
			grip += qAim * (Vector3(-0.08, -0.07, 0.1) * (rl * hs))
			qGun = qGun * qEuler(0.45 * rl, 0.25 * rl, -0.55 * rl)
		var lower := _swapLower()
		if lower > 0.0:
			grip += qAim * (Vector3(0.04, -0.32, 0.14) * (lower * hs))
			qGun = qGun * qEuler(-1.15 * lower, 0.35 * lower, 0)
		if sprint > 0.001:
			var c := qBody * (Vector3(0.12, -0.36, -0.2) * hs) + M
			var q3 := qBody * qEuler(-0.55, 0.75, 0.25)
			grip = grip.lerp(c, sprint)
			qGun = qGun.slerp(q3, sprint)
		if busy > 0.001:
			var c := qBody * (Vector3(0.2, -0.28, -0.06) * hs) + M
			var q3 := qAim * qEuler(-0.6, 0.55, 0.2)
			grip = grip.lerp(c, busy)
			qGun = qGun.slerp(q3, busy)

		# right arm: palm centre (slot) on the grip
		var qHand := qGun * RH_FRAME
		var slotR: Vector3 = p.hero.slots.handR.position
		var d := grip - qHand * slotR
		var handPole := qBody * v3a(hold.poleR)
		solveArm(J.shoulderR, J.elbowR, J.handR, d, handPole, qHand)

	# left arm: on the weapon (clamped to reach), or melee / throw / reload paths
	_poseLeft(J, h if hasGun else null, hold, M, qAim, qBody, hs)

func _swingStyle() -> String:
	var hp = WD.MELEE_PROPS.get(game.player.heroId)
	return hp.swing if hp != null and hp.get("swing") else "chop"

# Chest yaw for the melee swing: coil on the wind-up, whip through on the strike.
func _meleeTwist() -> float:
	if _melee.t < 0.0:
		return 0.0
	var u: float = _melee.t / WD.WEAPON_DEFS.melee.time
	var S: Dictionary = SWINGS.get(_swingStyle(), SWINGS.chop)
	var wind := smooth(0, 0.28, u)
	var strike := smooth(0.28, 0.46, u)
	var back := smooth(0.62, 1, u)
	return lerpf(S.twist[0] * wind, S.twist[1], strike) * (1.0 - back)

func _reloadPoseWeight() -> float:
	var R := _reload
	var u: float = R.t / R.total if R.total > 0 else 0.0
	return smooth(0, 0.14, u) * (1.0 - smooth(0.86, 1, u))

func _swapLower() -> float:
	var S := _swap
	var lower := 0.0
	if S.t > 0.0:
		var u: float = S.t / S.total
		lower = easeInOut(u / 0.45) if u < 0.45 else 1.0 - easeOutBack(clampf((u - 0.45) / 0.55, 0.0, 1.0), 1.4)
	if _raise < 1.0:
		lower = maxf(lower, 1.0 - easeOutBack(_raise, 1.6))
	return clampf(lower, -0.15, 1.0)

func _poseLeft(J: Dictionary, h, hold: Dictionary, M: Vector3, qAim: Quaternion, qBody: Quaternion, hs: float) -> void:
	var p = game.player
	var target := Vector3.ZERO
	var qL := Quaternion.IDENTITY
	var reach := armReach(J.shoulderL, J.elbowL, J.handL) * 0.985
	var shoulderL: Vector3 = J.shoulderL.global_position
	var wOnGun := 1.0 if h != null else 0.0

	# point on the weapon (slides back along the gun when the support point is out of reach)
	if h != null:
		var mt: Transform3D = h.model.global_transform
		var lh: Vector3 = h.leftHand
		var a := mt * lh
		if a.distance_to(shoulderL) > reach + 0.02:
			var b := Vector3(lh.x, lh.y, maxf(lh.z, -0.02))
			var lo := 0.0
			var hi := 1.0
			for i in 8:
				var m := (lo + hi) / 2.0
				var c := mt * b.lerp(lh, m)
				if c.distance_to(shoulderL) <= reach:
					lo = m
				else:
					hi = m
			a = mt * b.lerp(lh, lo)
		target = a
		qL = mt.basis.get_rotation_quaternion() * LH_FRAMES.get(hold.lh, LH_FRAMES.under)

	# reload path: weapon -> belt pouch -> magwell -> weapon
	if h != null and reloading:
		var R := _reload
		var u: float = R.t / R.total if R.total > 0 else 0.0
		var belt := 0.0
		if R.kind == "shell":
			var def: Dictionary = h.def
			var start: float = def.reload * _eff().reload
			var per: float = def.shellReload * _eff().reload
			var tt: float = R.t - start
			belt = smooth(0, start, R.t) * 0.6 if tt < 0.0 else sin(clampf(fmod(tt, per) / per, 0.0, 1.0) * PI)
		else:
			belt = smooth(0.14, 0.32, u) * (1.0 - smooth(0.5, 0.72, u))
		var b := qBody * (BELT_L * hs) + M
		target = target.lerp(b, belt)
		if belt > 0.01:
			qL = qL.slerp(qBody, belt * 0.8)

	# melee: hero swing with the left hand (per hero: Duke chops bare-handed, Skip / Penny bonk, Roxy slaps the LP)
	var Mw: Dictionary = WD.WEAPON_DEFS.melee
	if _melee.t >= 0.0:
		var u: float = _melee.t / Mw.time
		var S: Dictionary = SWINGS.get(_swingStyle(), SWINGS.chop)
		var wind := smooth(0, 0.28, u)
		var back := smooth(0.62, 1, u)
		var k := smooth(0.28, 0.46, u)
		var strike := k * k * (3.0 - 2.0 * k) if k < 1.0 else 1.0     # snappy strike
		var b := v3a(S.wind) * hs
		var c := v3a(S.ctrl) * hs
		var d := v3a(S.hit) * hs
		# quadratic arc wind -> ctrl -> hit, a small follow-through overshoot after the hit
		var o := strike + 0.12 * sin(PI * smooth(0.46, 0.7, u))
		var a0 := (1.0 - o) * (1.0 - o)
		var a1 := 2.0 * (1.0 - o) * o
		var a2 := o * o
		var v5 := qAim * Vector3(b.x * a0 + c.x * a1 + d.x * a2, b.y * a0 + c.y * a1 + d.y * a2, b.z * a0 + c.z * a1 + d.z * a2) + M
		var w := maxf(wind, strike) * (1.0 - back)
		if h != null:
			target = target.lerp(v5, w)
		else:
			target = v5
		wOnGun = 1.0 if h != null else w
		var q2 := qAim * qEuler(lerpf(S.rotW[0], S.rotH[0], strike), lerpf(S.rotW[1], S.rotH[1], strike), lerpf(S.rotW[2], S.rotH[2], strike))
		qL = qL.slerp(q2, w if h != null else 1.0)

	# grenade / Tiny Tele: hold near the chest, wind up overhand, throw forward
	var N := _nade
	var throwing: bool = N.state != "none" or _tele.t >= 0.0
	if throwing:
		var wind := 0.0
		var fwd := 0.0
		var hold2 := 1.0
		if N.state == "cook":
			hold2 = smooth(0, 0.12, N.t)
			wind = 0.35 * hold2
		elif N.state == "throw" or _tele.t >= 0.0:
			var dur := (0.36 if N.state == "throw" else 0.42) * _jumpCutMul()
			var u: float = (N.t if N.state == "throw" else _tele.t) / dur
			wind = lerpf(0.35, 1.0, smooth(0, 0.3, u)) if u < 0.3 else 1.0 - smooth(0.3, 0.5, u)
			fwd = smooth(0.28, 0.55, u) * (1.0 - smooth(0.8, 1, u))
			hold2 = 1.0 - smooth(0.85, 1, u)
		elif N.state == "recover":
			hold2 = 1.0 - smooth(0, 0.16, N.t)
		var b := qAim * (Vector3(-0.24, -0.02, -0.26) * hs) + M           # hold
		var c := qAim * (Vector3(-0.32, 0.34, 0.24) * hs) + M             # wind-up
		var d := qAim * (Vector3(-0.06, 0.1, -0.6) * hs) + M              # release
		b = b.lerp(c, wind).lerp(d, fwd)
		if h != null:
			target = target.lerp(b, hold2)
		else:
			target = b
		wOnGun = 1.0 if h != null else hold2
		var q2 := qAim * qEuler(0.4 - fwd * 0.9, 0, 0.3)
		qL = qL.slerp(q2, hold2 if h != null else 1.0)
	if wOnGun <= 0.001:
		return

	var slotL: Vector3 = p.hero.slots.handL.position
	var dd := target - qL * slotL
	var handPole := qBody * v3a(hold.poleL)
	solveArm(J.shoulderL, J.elbowL, J.handL, dd, handPole, qL)

# reloadSpeed / swapSpeed: time multipliers (0.5 = twice as fast, T.perks.jumpCut); values > 1 are read as speeds.
static func timeMul(v) -> float:
	if not _finite(v) or float(v) <= 0.0:
		return 1.0
	return float(v) if float(v) <= 1.0 else 1.0 / float(v)

# ============================================================================================ MP (see the header)
# Remote avatar held weapon (RemotePlayer calls it when the replicated weapon changes; RECONCILE R18): the model is
# built and cached by weapons_net.gd, which also sets remote.postAnimate (the IK pose). null = unarmed / no MP.
func buildRemoteHeld(remote, id, upgraded = false, sig_ = "") -> Variant:
	if mp == null or remote == null or id == null or str(id) == "":
		return null
	return mp.buildRemoteHeld(remote, str(id), _truthy(upgraded), str(sig_) if sig_ != null else "")

# MP respawn kit (off-air -> next round, mp-players): revolver + the starting grenades, no Tiny Teles, no upgrades /
# wonder weapons; keeps the round bookkeeping and the projectiles in flight.
func resetLoadout() -> void:
	cancelReload()
	var W = game.wonder
	var s = _slotAt(current)
	if s != null and W != null and W.has_method("holster"):
		W.holster(s.id)
	slots.clear()
	current = -1
	swapping = false
	_swap.t = 0.0
	_swap.to = -1
	_swap.swapped = true
	_burst = 0
	_melee.t = -1.0
	_nade.state = "none"
	if _nade.model != null:
		_nade.model.visible = false
	_tele.t = -1.0
	if _tele.model != null:
		_tele.model.visible = false
	if _melee.prop != null:
		_melee.prop.visible = false
	grenades = WD.WEAPON_DEFS.tube_grenade.start
	teles = 0
	teleOwned = false
	game.player.setWeaponModel(null)
	_heldKey = null
	give("revolver_38", {"source": "start"})
	_raise = 1.0

func loadout() -> void:
	resetLoadout()

# ---- messages (validated; sender = net.sender)
# Arsenal remote API: the host (machines / economy / story) reaches one peer's own inventory with net.toPeer.
func net_give(id, opts = null) -> void:
	if not (id is String) or not WD.WEAPON_DEFS.has(id):
		return
	var o: Dictionary = opts.duplicate() if opts is Dictionary else {}
	if o.get("signal") is String and (o.signal == "" or not WD.SIGNAL_COLORS.has(o.signal)):
		o.erase("signal")
	give(id, o)

func net_take(id) -> void:
	if id is String:
		take(id)

func net_takeCurrent() -> void:
	takeCurrent()

func net_upgrade(id, sig_ = null, source = "uplink") -> void:
	if id is String:
		upgrade(id, sig_ if (sig_ is String and WD.SIGNAL_COLORS.has(sig_)) else null, str(source))

func net_refillAll() -> void:
	refillAll()

func net_addGrenades(n) -> void:
	if n is int or n is float:
		addGrenades(int(n))

func net_resetLoadout() -> void:
	resetLoadout()

# Client -> host: shootable hits tested on the shooter's peer; the host runs each entry's onHit with info.by.
func net_shootableHits(list) -> void:
	if mp != null:
		mp.onShootableHits(list)

# Owner -> others: a thrown grenade (cosmetic copy until the blast message).
func net_nade(nid, origin, vel, fuse) -> void:
	if mp != null:
		mp.onNade(nid, origin, vel, fuse)

# Client -> host: its grenade went off (the host resolves the victims).
func net_nadeBoom(nid, pos, inHand, dmgMul = 1.0) -> void:
	if mp != null:
		mp.onNadeBoom(nid, pos, inHand, dmgMul)

# Host -> all: a grenade blast (FX + weapon:grenade on observers).
func net_nadeFx(by, nid, pos, inHand) -> void:
	if mp != null:
		mp.onNadeFx(by, nid, pos, inHand)

# Host -> thrower: hit marker for host-resolved hits of its area actions (kills come with zombie:kill).
func net_confirm(hits, head = false) -> void:
	if mp != null and (hits is int or hits is float) and hits > 0 and game.hud != null and game.hud.has_method("hitmarker"):
		game.hud.hitmarker(head == true, false)

# Observer stream (owner -> others, unreliable): shots, melee, wind-ups, wonder launches (weapons_net.gd format).
func net_stream_wfx(from, data) -> void:
	if mp != null and data is PackedByteArray:
		mp.onStream(int(from), data)
