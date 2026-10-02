# BIG SHOT (`big_shot`, the camera operator fused with his studio pedestal) type module — GDD §8.4, §5.9, §10.0
# (port of src/actors/types/big_shot.js). Owned by the zombies-specials agent. Contract: the TYPE MODULE CONTRACT in
# zombie_types.gd / src/actors/zombieTypes.js (id, hp, speed, build, release, update -> true, updateEntry,
# entryFilter/entry, hitTest, onDamage, onDeath/updateDeath, warmup, points, oneTakeMul).
#
# Look: the sculpted z_bigshot (custom rig base -> column -> torso -> head + arms), baked. Runtime parts: caster wheels
#   that roll and swivel, the red tally lamp (blinks), a lens iris + glow at 'lensFront', a flash sprite, and the
#   trailing CABLE (verlet rope, one dynamic tube) ending in a PLUG with glowing prongs (his weak point).
# Behaviour (T.zombies.bigShot):
#   - Rolls at 1.6 m/s (heavy turning, bs_roll loop). Enters through boarded windows / the gate: blows every board out
#     at once (the manager's 'blast' entry + a flashbulb pop here) and squeezes through like toothpaste (1.5 s).
#   - DOLLY RUSH (within 12 m with line of sight, 8 s cooldown): 1.0 s telegraph (wheels screech and spin in place,
#     tally blinks, he rears back, dust), then charges straight at 9 m/s for up to 1.5 s: 70 damage + 4 m knockback
#     (zombie:attack {z, dmg, kind:'rush'}), bowls other zombies aside. Hitting a wall: bs_wall_bonk, DIZZY 2 s (the
#     camera head spins, stars; manager stun) and ×1.5 damage from every side meanwhile. Otherwise a smoking skid.
#   - FLASH (9 s cooldown, 20 m, line of sight): 1.0 s wind-up (the lens iris opens with the rising whine), then POP:
#     if the player's camera forward is within 60° of the direction to him, a 1.5 s whiteout (hud.whiteout, else
#     render.post.whiteout) + 20 damage, and every decorative TV freezes on the flinch frame for 3 s
#     (screens.override('flinch', …, 3)). Looking away fully negates it. Emits 'zombie:flash' { z, pos, hit }.
#   - Close bump (not in the GDD list, keeps him dangerous when hugged): 0.5 s rear-back, lurch, 35 damage, 2 s cd.
# Damage (onDamage): shots from his front (the camera housing faces the shot, within 60°) ×0.4, sides/back ×1, the
#   PLUG ×3 (its own shootable 'bs_plug_<z.id>' routed into zombies.damage with zone 'plug', head:true = gold
#   hitmarker), dizzy ×1.5 from every side. ONE TAKE ×5 (oneTakeMul, applied by the manager).
# Death (onDeath -> 2.4 s): the camera head pops in a giant flashbulb burst (bs_death, flash light, mild screen flash,
#   glass sparks), film unspools everywhere as tube spaghetti (12 simulated film strips), the pedestal telescopes down
#   and tips over, static dissolve. +500 (points.killBonus). His FIRST death each game drops FULL REEL
#   (powerups.dropGuaranteed('full_reel', pos), else powerups.drop).
# Debug: z.def.forceRush(game, z), z.def.forceFlash(game, z), z.def.plugOf(z) -> world position of the plug.
#
# Port notes (GDScript): static meshes (iris blades, lens glow disc, flash card, plug body / prongs / halo) come from
#   blender/runtime/specials.py (res://assets/runtime/specials/bs_*.glb; the flare / film canvases are drawn with
#   DACanvas); the cable tube and the film spaghetti are rebuilt every frame here (ArrayMesh, the
#   JS per-frame BufferGeometry writes; triangle winding flipped to Godot's clockwise front faces). Materials: the JS
#   factory calls (game.mats.toon) or unlit StandardMaterial3D for the JS THREE.MeshBasicMaterials (SH.basic).
#   charOpt.gen / mergeAttachments / cloneBare are engine plumbing (not ported). The JS art=0 / missing-bake
#   primitive placeholder (buildPlaceholderRig) is a placeholder-art path: not ported (SPEC §0.2).
#   Renames: parameter `round` -> `r`.
extends RefCounted

const SH = preload("res://scripts/actors/types/sock_hopper.gd")

static var B: Dictionary = Config.T.zombies.bigShot
static var RU: Dictionary = Config.T.zombies.bigShot.rush
static var FL: Dictionary = Config.T.zombies.bigShot.flash
static var R: Dictionary = Config.T.rounds
const G := 22.0
const TURN := 2.6             # rad/s max yaw rate while rolling (heavy)
const RADIUS := 0.55
const HEIGHT := 2.2
const WHEEL_R := 0.062
const BUMP_RANGE := 1.7
const BUMP_WINDUP := 0.5
const BUMP_CD := 2.0
# { range, windup, dmg: Math.round(RU.dmg / 2), cd }
static var BUMP := {"range": BUMP_RANGE, "windup": BUMP_WINDUP, "dmg": floorf(float(Config.T.zombies.bigShot.rush.dmg) / 2.0 + 0.5), "cd": BUMP_CD}
const ABILITY_GAP := 1.6
const CABLE_N := 11
const CABLE_SEG := 0.13
const CABLE_R := 0.022
const FILM_N := 12
const FILM_P := 9
const DEATH := 2.4
const UP := Vector3(0, 1, 0)

# ------------------------------------------------------------------------------------------------ module fields
var id := "big_shot"
var height := HEIGHT
var radius := RADIUS
var dmg = Config.T.zombies.bigShot.rush.dmg
var range: float = BUMP_RANGE
var windup: float = BUMP_WINDUP
var cd: float = BUMP_CD
var spawnMode := "window"
var points := {"killBonus": Config.T.points.bigShot}
var oneTakeMul := 5
var netModes := ["roll", "rushTele", "rush", "skid", "flashWind", "bump"]   # MP: wire enum of z.flags.mode

static func clamp01(x: float) -> float:
	return SH.clamp01(x)

static func smooth(x: float) -> float:
	return SH.smooth(x)

static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func easeOutBack(x: float) -> float:
	return SH.easeOutBack(x)

static func easeOutCubic(x: float) -> float:
	return SH.easeOutCubic(x)

static func easeOutBounce(x: float) -> float:
	x = clamp01(x)
	var n := 7.5625
	var d := 2.75
	if x < 1.0 / d:
		return n * x * x
	if x < 2.0 / d:
		x -= 1.5 / d
		return n * x * x + 0.75
	if x < 2.5 / d:
		x -= 2.25 / d
		return n * x * x + 0.9375
	x -= 2.625 / d
	return n * x * x + 0.984375

static func angDiff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func yawTo(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

static func hpAt(r: float) -> float:
	return SH.hpAt(r)

# Ray helpers (o origin, d unit dir) -> distance or INF.
static func raySphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var e := o - c
	var b := e.dot(d)
	var q := e.length_squared() - r * r
	var disc := b * b - q
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	return t if t >= 0.0 else (0.0 if q < 0.0 else INF)

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

static func weaponHeadMul(g, weaponId) -> float:
	if weaponId == null or weaponId == "":
		return 1.0
	var w = g.weapons
	var defs = w.get("defs") if w != null else null
	var d = defs.get(weaponId) if defs is Dictionary else null
	var h := SH.num(d, "head", 0.0) if d != null else 0.0
	return h if h > 0.0 else 1.0

# three's Matrix4.lookAt(eye = 0, target = d, up) rotation: local -z along d.
static func lookBasis(d: Vector3, up := UP) -> Basis:
	var zz := -d
	if zz.length_squared() == 0.0:
		zz.z = 1.0
	zz = zz.normalized()
	var xx := up.cross(zz)
	if xx.length_squared() == 0.0:
		if absf(up.z) == 1.0:
			zz.x += 0.0001
		else:
			zz.z += 0.0001
		zz = zz.normalized()
		xx = up.cross(zz)
	xx = xx.normalized()
	var yy := zz.cross(xx)
	return Basis(xx, yy, zz)

# ------------------------------------------------------------------------------------------------ shared assets
# flareTexture / filmAssets: the JS canvases, drawn with DACanvas (scripts/gfx/canvas2d.gd; the Blender asset's flare
# copy is used while it is missing). bladeGeometry, plug body / prongs, lens glow disc, flare plane:
# specials/bs_lens.glb, specials/bs_plug.glb.
static var filmMat: Material = null
static var bladeGeo: Mesh = null
static var plugAssets = null
static var warned := false
static var pool: Array = []
static var games := {}   # game instance id -> { reelDropped }

static func gameState(game) -> Dictionary:
	var gid: int = game.get_instance_id()
	var s = games.get(gid)
	if s == null:
		s = {"reelDropped": false}
		games[gid] = s
		game.events.on("game:start", func(_e = null): s.reelDropped = false)
		# rolling loops go quiet while the zombies are frozen (PLEASE STAND BY) or the game is paused
		SH.addPrePass(game, func():
			var Zs = game.zombies
			if Zs == null or not (Zs.get("frozen") or not (float(game.time.dt) > 0.0)):
				return
			for z in Zs.alive:
				if z.type == "big_shot" and z.flags.get("rollSnd") != null and z.flags.rollSnd.has_method("setVol"):
					z.flags.rollSnd.setVol(0, 0.1))
	return s

static var flareTex = null
static var filmTex = null

static func flareTexture():
	if flareTex != null:
		return flareTex
	var c = SH.newCanvas(128, 128)
	if c == null:
		flareTex = SH.glbTex("bs_lens", "bs_flare")
		return flareTex
	var g = c.getContext("2d")
	var grd = g.createRadialGradient(64, 64, 0, 64, 64, 64)
	grd.addColorStop(0, "rgba(255,255,255,1)")
	grd.addColorStop(0.2, "rgba(255,250,235,0.9)")
	grd.addColorStop(0.5, "rgba(255,236,200,0.35)")
	grd.addColorStop(1, "rgba(255,230,190,0)")
	g.fillStyle = grd
	g.fillRect(0, 0, 128, 128)
	# 6-point star streaks
	g.globalCompositeOperation = "lighter"
	g.strokeStyle = "rgba(255,255,255,0.55)"
	g.lineWidth = 3
	for i in 3:
		var a := (i * PI) / 3.0
		g.beginPath()
		g.moveTo(64 - cos(a) * 62, 64 - sin(a) * 62)
		g.lineTo(64 + cos(a) * 62, 64 + sin(a) * 62)
		g.stroke()
	flareTex = c.texture
	return flareTex

# The film strip texture (64x256, wrapT repeat) on a MeshStandardMaterial (DoubleSide, roughness 0.35, metalness 0.1).
static func filmAssets() -> void:
	if filmMat != null:
		return
	var c = SH.newCanvas(64, 256)
	if c != null:
		var g = c.getContext("2d")
		g.fillStyle = "#3A2418"
		g.fillRect(0, 0, 64, 256)
		g.fillStyle = "#6B4A30"
		for y in range(0, 256, 64):
			g.fillRect(14, y + 6, 36, 52)           # frames
		g.fillStyle = "#E8D8B8"
		for y in range(4, 256, 16):
			g.fillRect(3, y, 6, 8)                  # sprocket holes
			g.fillRect(55, y, 6, 8)
		filmTex = c.texture
	var m := StandardMaterial3D.new()
	m.albedo_texture = filmTex
	m.texture_repeat = true
	# three CanvasTexture flipY: sample the canvas at (u, 1 - v) of the three uv
	m.uv1_scale = Vector3(1, -1, 1)
	m.uv1_offset = Vector3(0, 1, 0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.35
	m.metallic = 0.1
	m.resource_name = "bsFilm"
	filmMat = m

static func bladeGeometry() -> Mesh:
	if bladeGeo == null:
		bladeGeo = SH.loadMesh("bs_lens", "bs_blades")
	return bladeGeo

static func getPlugAssets(game):
	if plugAssets != null:
		return plugAssets
	plugAssets = {
		"body": SH.loadMesh("bs_plug", "bs_plugBody"),
		"prong": SH.loadMesh("bs_plug", "bs_prongs"),
		"rubber": SH.toon(game, "#26232A", {"rough": 0.6, "keepColor": true, "rim": 0.35}),
		"cable": SH.toon(game, "#1F1C22", {"rough": 0.55, "keepColor": true, "rim": 0.3, "name": "bsCable"}),
	}
	return plugAssets

# ------------------------------------------------------------------------------------------------ model
static func hasBaked(game) -> bool:
	return SH.charBaked(game, "z_bigshot")

static func buildBakedRig(game):
	var c = SH.buildChar(game, "z_bigshot", {"animator": false})
	if c == null or c.get("group") == null:
		return null
	var zt = load("res://scripts/actors/zombie_types.gd") if ResourceLoader.exists("res://scripts/actors/zombie_types.gd") else null
	var eyes = zt.zombieEyeMaterial() if zt != null and zt.has_method("zombieEyeMaterial") else null
	var wheels: Array = []
	var casters: Array = []
	var h := {"tally": null, "lens": null}
	DAU.traverse(c.group, func(o):
		var ud := DAU.ud(o) if o.has_meta("userData") else {}
		if o is MeshInstance3D and ud.get("staticEye") and eyes != null:
			(o as MeshInstance3D).material_override = eyes
		if o is MeshInstance3D:
			SH.setCast(o, SH.isSkinned(o))
		if ud.get("wheel"):
			wheels.append(o)
			ud.noMerge = true
			(o as Node3D).rotation_order = EULER_ORDER_XYZ
		if ud.get("caster"):
			casters.append(o)
			ud.noMerge = true
			(o as Node3D).rotation_order = EULER_ORDER_XYZ
		if ud.get("tally"):
			h.tally = o
			ud.noMerge = true
		if String(o.name) == "lensFront":
			h.lens = o)
	# mergeAttachments (draw-call merging) is engine plumbing: not ported.
	var bodies: Array = []
	DAU.traverse(c.group, func(o):
		if SH.isSkinned(o):
			if o == c.get("skinnedMesh"):
				bodies.append(o)
			else:
				SH.noShadow(o))
	if c.get("skinnedMesh") != null:
		SH.registerSpecialTint(game, SH.meshMat(c.skinnedMesh))
	# the JS attachment builder makes a new tally material per character: a per-model copy (Godot shares imports)
	if h.tally is MeshInstance3D:
		SH.ownMat(h.tally)
	return {"group": c.group, "rig": c.rig, "J": SH.rigJoints(c.rig), "wheels": wheels, "casters": casters, "tally": h.tally,
		"lens": h.lens, "bodies": bodies, "baked": true}

static func buildModel(game, baked: bool):
	var b = buildBakedRig(game) if baked else null
	if b == null:
		return null
	var m: Dictionary = b.duplicate()
	m.def = {"id": "big_shot"}
	m.variant = "z_bigshot" if baked else "placeholder"
	m.cards = []
	var J: Dictionary = m.J
	# head centre (stars ring, generic queries)
	var head := DAU.node3d("part_headCenter")
	head.position = Vector3(0, 0.27, -0.05)
	(J.head as Node3D).add_child(head)
	m.head = head
	m.headR = 0.3
	m.tallyMat = SH.meshMat(m.tally) if m.tally is MeshInstance3D else null
	m.tallyBase = SH.getColorLin(m.tallyMat) if m.tallyMat != null else null
	# Lens: glow disc + iris blades (open with the flash wind-up) + a flash sprite.
	var lens: Node3D = m.lens if m.lens != null else J.head
	var glowMat = SH.basic(game, Color(0.05, 0.07, 0.1), {"transparent": true, "opacity": 0.95, "depthWrite": false, "fog": false})
	glowMat.resource_name = "bsLensGlow"
	m.glow = MeshInstance3D.new()
	m.glow.name = "bsLensGlow"
	m.glow.mesh = SH.loadMesh("bs_lens", "bs_lensGlow")
	m.glow.material_override = glowMat
	m.glow.rotation_order = EULER_ORDER_XYZ
	m.glow.rotation.y = PI
	m.glow.position.z = -0.012
	SH.noShadow(m.glow)
	lens.add_child(m.glow)
	var bladeMat = SH.toon(game, "#14171F", {"rough": 0.35, "metal": 0.4, "keepColor": true, "rim": 0.2})
	m.blades = MeshInstance3D.new()
	m.blades.name = "bsBlades"
	m.blades.mesh = bladeGeometry()
	m.blades.material_override = bladeMat
	m.blades.rotation_order = EULER_ORDER_XYZ
	m.blades.position.z = -0.016
	m.blades.rotation.y = PI
	lens.add_child(m.blades)
	var flareMat = SH.basic(game, Color(3, 3, 3), {"map": flareTexture(), "transparent": true, "depthWrite": false, "additive": true, "fog": false, "renderOrder": 5})
	flareMat.resource_name = "bsFlare"
	m.flare = MeshInstance3D.new()
	m.flare.name = "bsFlare"
	m.flare.mesh = SH.loadMesh("bs_lens", "bs_flare")
	m.flare.material_override = flareMat
	m.flare.visible = false
	SH.noShadow(m.flare)
	# Cable + plug (world space while alive).
	var P = getPlugAssets(game)
	m.cable = MeshInstance3D.new()
	m.cable.mesh = ArrayMesh.new()
	m.cable.material_override = P.cable
	m.cable.extra_cull_margin = 16384.0     # frustumCulled = false
	SH.noShadow(m.cable)
	m.cable.name = "bs_cable"
	m.plug = DAU.node3d("bs_plug")
	var body := MeshInstance3D.new()
	body.mesh = P.body
	body.material_override = P.rubber
	m.plug.add_child(body)
	var prongMat = SH.basic(game, SH.hexLin("#FFB23A", 2.6))
	prongMat.resource_name = "bsProng"
	m.prongMat = prongMat
	var prongs := MeshInstance3D.new()
	prongs.mesh = P.prong
	prongs.material_override = prongMat
	m.plug.add_child(prongs)   # both prongs, one draw
	var haloMat = SH.basic(game, SH.hexLin("#FFA030", 1.2), {"map": flareTexture(), "transparent": true, "depthWrite": false, "additive": true, "fog": false})
	m.halo = MeshInstance3D.new()
	m.halo.name = "bs_halo"
	m.halo.mesh = SH.loadMesh("bs_plug", "bs_halo")
	m.halo.material_override = haloMat
	m.halo.position.z = -0.08
	m.plug.add_child(m.halo)
	DAU.traverse(m.plug, func(o): SH.noShadow(o))
	m.cablePts = []
	m.cablePrev = []
	for i in CABLE_N:
		m.cablePts.append(Vector3.ZERO)
		m.cablePrev.append(Vector3.ZERO)
	# Film spaghetti (death): one dynamic ribbon mesh.
	filmAssets()
	m.film = MeshInstance3D.new()
	m.film.mesh = ArrayMesh.new()
	m.film.material_override = filmMat
	m.film.extra_cull_margin = 16384.0
	SH.noShadow(m.film)
	m.film.visible = false
	m.film.name = "bs_film"
	m.strips = []
	for s in FILM_N:
		var st := {"p": [], "q": [], "v": Vector3.ZERO, "w": 0.05, "curl": 0.0}
		for i in FILM_P:
			st.p.append(Vector3.ZERO)
			st.q.append(Vector3.ZERO)
		m.strips.append(st)
	for o in [m.flare, m.cable, m.plug, m.film]:
		SH.setLayers(o)
	SH.setLayers(m.group)
	m.group.name = "zombie_big_shot"
	m.rest = []
	for j in J.values():
		if j != null:
			(j as Node3D).rotation_order = EULER_ORDER_XYZ
			m.rest.append([j, j.position])
	return m

static func acquire(game):
	var want := hasBaked(game)
	for i in range(pool.size() - 1, -1, -1):
		if pool[i].baked == want:
			var m = pool[i]
			pool.remove_at(i)
			return m
	if want:
		var m = buildModel(game, true)
		if m != null:
			return m
		if not warned:
			warned = true
			push_warning("[big_shot] baked model failed")
	# the art=0 / no-bake primitive pedestal placeholder is not ported (SPEC §0.2): the manager spawns a Tuned-In
	return null

static func resetModel(m: Dictionary) -> void:
	var g: Node3D = m.group
	g.visible = true
	g.position = Vector3.ZERO
	g.rotation = Vector3.ZERO
	g.scale = Vector3.ONE
	var root := SH.rigRoot(m.rig)
	root.position = Vector3.ZERO
	root.rotation = Vector3.ZERO
	root.scale = Vector3.ONE
	for jp in m.rest:
		jp[0].position = jp[1]
		jp[0].rotation = Vector3.ZERO
		jp[0].scale = Vector3.ONE
	for o in [m.flare, m.cable, m.plug, m.film]:
		DAU.detach(o)
	m.flare.visible = false
	m.film.visible = false
	m.cable.visible = true
	m.plug.visible = true
	m.glow.scale = Vector3.ONE
	SH.setColorLin(m.glow.material_override, Color(0.05, 0.07, 0.1))
	m.blades.scale = Vector3.ONE
	if m.tallyMat != null and m.tallyBase != null:
		SH.setColorLin(m.tallyMat, m.tallyBase)
	SH.setColorLin(m.prongMat, SH.hexLin("#FFB23A", 2.6))
	m.halo.visible = true

# ------------------------------------------------------------------------------------------------ cable
static func cableAnchor(z: Dictionary) -> Vector3:
	var s := SH.num(z, "scale", 1.0)
	if s == 0.0:
		s = 1.0
	var sy := sin(z.yaw)
	var cy := cos(z.yaw)
	# behind the base: local (0, 0.14, +0.4) rotated by yaw
	return Vector3(z.pos.x + sy * 0.4 * s, z.pos.y + 0.14 * s, z.pos.z + cy * 0.4 * s)

static func initCable(z: Dictionary) -> void:
	var m = z.model
	var a := cableAnchor(z)
	var bx := sin(z.yaw)
	var bz := cos(z.yaw)
	for i in CABLE_N:
		m.cablePts[i] = Vector3(a.x + bx * CABLE_SEG * i, z.pos.y + CABLE_R + 0.01, a.z + bz * CABLE_SEG * i)
		m.cablePrev[i] = m.cablePts[i]
	m.cablePts[0] = a
	m.cablePrev[0] = a

static func tickCable(game, z: Dictionary, dt: float, limp := false) -> void:
	var m = z.get("model")
	if m == null:
		return
	var P: Array = m.cablePts
	var Q: Array = m.cablePrev
	var floorY: float = z.pos.y + CABLE_R + 0.005
	if not limp:
		var a := cableAnchor(z)
		if a.distance_squared_to(P[0]) > 4.0:
			initCable(z)     # teleported (straggler re-entry, debug): re-lay the cable
		P[0] = a
	Q[0] = P[0]
	var h := minf(dt, 1.0 / 30.0)
	for i in range(1, CABLE_N):
		var p: Vector3 = P[i]
		var q: Vector3 = Q[i]
		var onFloor := p.y <= floorY + 0.004
		var damp := 0.72 if onFloor else 0.985
		var vx := (p.x - q.x) * damp
		var vy := (p.y - q.y) * 0.985
		var vz := (p.z - q.z) * damp
		Q[i] = p
		p.x += vx
		p.y += vy - G * h * h
		p.z += vz
		if p.y < floorY:
			p.y = floorY
		P[i] = p
	for it in 5:
		for i in CABLE_N - 1:
			var a: Vector3 = P[i]
			var b: Vector3 = P[i + 1]
			var d := b - a
			var l := d.length()
			if l == 0.0:
				l = 1e-6
			var diff := (l - CABLE_SEG) / l
			if i == 0 and not limp:
				b += d * -diff
			else:
				a += d * (diff * 0.5)
				b += d * (-diff * 0.5)
			P[i] = a
			P[i + 1] = b
		for i in range(1, CABLE_N):
			if P[i].y < floorY:
				P[i].y = floorY
	writeCable(m)
	# plug at the end, oriented along the last segment, prongs pointing away
	var ea: Vector3 = P[CABLE_N - 2]
	var eb: Vector3 = P[CABLE_N - 1]
	var dd := eb - ea
	var plug: Node3D = m.plug
	if dd.length_squared() > 1e-8:
		dd = dd.normalized()
		plug.position = eb + dd * 0.04
		plug.quaternion = lookBasis(dd).get_rotation_quaternion()   # local -z (the prongs) along the cable end
	var t := SH.num(z.flags, "t")
	var pulse := 0.85 + sin(t * 7.0) * 0.15
	m.halo.quaternion = plug.quaternion.inverse() * SH.camQuat(game)
	m.halo.scale = Vector3.ONE * (0.001 if limp else pulse)

static var _cableIdx := PackedInt32Array()

static func writeCable(m: Dictionary) -> void:
	var P: Array = m.cablePts
	var rings := (CABLE_N - 1) * 2 + 1
	var rad := 6
	if _cableIdx.is_empty():
		for i in rings - 1:
			for k in rad:
				var a := i * rad + k
				var b2 := i * rad + ((k + 1) % rad)
				var c2 := a + rad
				var d2 := b2 + rad
				# three (a, c2, b2, b2, c2, d2) counter-clockwise -> Godot clockwise front faces
				_cableIdx.append_array([a, b2, c2, b2, d2, c2])
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(rings * rad)
	nrm.resize(rings * rad)
	var prevN = null
	for r in rings:
		var i := r >> 1
		var odd := r & 1
		var c := Vector3.ZERO
		if not odd:
			c = P[i]
		else:
			# midpoint pulled toward a Catmull-Rom position (smooth sag)
			var p0: Vector3 = P[maxi(0, i - 1)]
			var p1: Vector3 = P[i]
			var p2: Vector3 = P[i + 1]
			var p3: Vector3 = P[mini(CABLE_N - 1, i + 2)]
			c = p1 * 0.5625 + p2 * 0.5625 + p0 * -0.0625 + p3 * -0.0625
		var nA: Vector3 = P[mini(CABLE_N - 1, i + 1)]
		var nB: Vector3 = P[maxi(0, i - (0 if odd else 1))]
		var b := nA - nB
		if b.length_squared() < 1e-10:
			b = Vector3(0, 0, 1)
		b = b.normalized()
		var n := b.cross(UP)
		if n.length_squared() < 1e-6:
			n = Vector3(1, 0, 0)
		n = n.normalized()
		if prevN != null and n.dot(prevN) < 0.0:
			n = -n
		prevN = n
		var bi := n.cross(b).normalized()
		for k in rad:
			var ang := (float(k) / rad) * PI * 2.0
			var cx := cos(ang)
			var sx := sin(ang)
			var nv := n * cx + bi * sx
			var o := r * rad + k
			pos[o] = c + nv * CABLE_R
			nrm[o] = nv
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = _cableIdx
	var am: ArrayMesh = m.cable.mesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

static func plugWorld(z: Dictionary) -> Vector3:
	var m = z.get("model")
	return m.plug.position if m != null else z.pos

static func registerPlug(game, z: Dictionary) -> void:
	var W = game.weapons
	var f: Dictionary = z.flags
	f.plugId = "bs_plug_" + str(z.id)
	if W == null or not W.has_method("registerShootable"):
		return
	W.registerShootable({
		"id": f.plugId,
		"raycast": func(o: Vector3, d: Vector3, mx: float):
			if z.get("dead") or z.get("removed") or z.get("model") == null or (z.state != "chase" and z.state != "attack"):
				return null
			var t := raySphere(o, d, z.model.plug.position, 0.12)
			return {"dist": t, "point": o + d * t} if t <= mx else null,
		"onHit": func(info):
			if z.get("dead") or not (SH.num(info, "damage") > 0.0):
				return
			game.zombies.damage(z, info.damage, {"zone": "plug", "head": true, "point": info.get("point"), "dir": info.get("dir"), "weaponId": info.get("weaponId"), "by": info.get("by"),
				"upgraded": info.get("upgraded"), "cause": "melee" if info.get("melee") else (info.get("cause") if info.get("cause") else "bullet")})
			SH.burst(game, info.point if info.get("point") != null else z.model.plug.position, {"shape": "spark", "count": 8, "speed": 4, "colors": ["#FFE08A", "#FFB23A", "#FFFFFF"]}),
		"blocksBullet": true,
		"melee": true,
	})

static func unregisterPlug(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	if f.get("plugId") == null:
		return
	if game.weapons != null and game.weapons.has_method("unregisterShootable"):
		game.weapons.unregisterShootable(f.plugId)
	f.plugId = null

# ------------------------------------------------------------------------------------------------ hit test
static func makeHitTest(z: Dictionary) -> Callable:
	return func(o: Vector3, d: Vector3, mx: float):
		var m = z.get("model")
		if m == null:
			return null
		var J: Dictionary = m.J
		var s := SH.num(z, "scale", 1.0)
		if s == 0.0:
			s = 1.0
		var st := {"best": INF, "zone": null}
		var test := func(t: float, zn: String):
			if t < st.best:
				st.best = t
				st.zone = zn
		# camera housing + lens
		test.call(raySphere(o, d, SH.toWorld(J.head, Vector3(0, 0.28, 0.02)), 0.3 * s), "camera")
		test.call(rayCapsule(o, d, SH.toWorld(J.head, Vector3(0, 0.205, -0.25)), SH.toWorld(J.head, Vector3(0, 0.205, -0.6)), 0.14 * s), "camera")
		# torso + arms
		test.call(rayCapsule(o, d, SH.toWorld(J.torso, Vector3(0, 0.14, 0)), SH.toWorld(J.torso, Vector3(0, 0.42, 0.02)), 0.33 * s), "torso")
		# column + base
		test.call(rayCapsule(o, d, SH.toWorld(J.base, Vector3(0, 0.18, 0)), SH.toWorld(J.column, Vector3(0, 0.62, 0)), 0.15 * s), "body")
		test.call(rayCapsule(o, d, SH.toWorld(J.base, Vector3(0, 0.1, -0.25)), SH.toWorld(J.base, Vector3(0, 0.1, 0.25)), 0.3 * s), "body")
		if st.zone == null or st.best > mx:
			return null
		return {"dist": st.best, "zone": st.zone, "head": false, "mul": 1}

# ------------------------------------------------------------------------------------------------ animator
class BigShotAnimator extends RefCounted:
	var z: Dictionary
	var mod: Script
	var override = null          # (the manager's resetModelPose clears animator.override)

	func _init(z_: Dictionary, mod_: Script) -> void:
		z = z_
		mod = mod_

	func update(dt: float, st = null) -> void:
		mod.poseBigShot(z, z.flags, dt, st if st is Dictionary else {})

	func kick(amount := 1.0) -> void:
		z.flags.sq.kick(-2.2 * amount)
		z.flags.lean.kick(2.5 * amount)

static func poseBigShot(z: Dictionary, f: Dictionary, dt: float, st: Dictionary) -> void:
	var m = z.get("model")
	if m == null:
		return
	var g = f.get("game")
	var J: Dictionary = m.J
	var root := SH.rigRoot(m.rig)
	f.t += dt
	var t: float = f.t
	for jp in m.rest:
		jp[0].position = jp[1]
		jp[0].rotation = Vector3.ZERO
	J.column.scale = Vector3.ONE
	J.head.scale = Vector3.ONE
	var lean := 0.0
	var headYaw := 0.0
	var headPitch := 0.0
	var jitter := 0.0
	var wheelSpin := 0.0
	var colScale := 1.0
	var speed := SH.num(st, "speed")
	var mode = f.mode
	# aim the camera head at the player (MP: the zombie's target)
	var tp = SH.target(g, z) if g != null else null
	if tp != null:
		var p: Vector3 = tp.pos
		headYaw = clampf(angDiff(yawTo(p.x - z.pos.x, p.z - z.pos.z), z.yaw), -0.9, 0.9)
		var dh := Vector2(p.x - z.pos.x, p.z - z.pos.z).length()
		headPitch = clampf(atan2(p.y + 1.3 - (z.pos.y + 1.75), maxf(0.5, dh)), -0.4, 0.3)
	var blink := 1
	if mode == "rushTele":
		var k := clamp01(f.mt / RU.tele)
		lean = 0.26 * smooth(k / 0.3)
		jitter = 0.012 + 0.02 * k
		wheelSpin = 38.0
		blink = int(floorf(t * 18.0)) % 2
		colScale = 1.0 - 0.06 * k
	elif mode == "rush":
		lean = -0.3
		colScale = 0.92
		headYaw *= 0.2
		blink = int(floorf(t * 18.0)) % 2
	elif mode == "skid":
		lean = 0.22 * (1.0 - clamp01(f.mt / 0.45))
		jitter = 0.01
		blink = int(floorf(t * 10.0)) % 2
	elif mode == "flashWind":
		var k := clamp01(f.mt / FL.windup)
		lean = 0.08 * k
		blink = int(floorf(t * (6.0 + k * 10.0))) % 2
	elif mode == "bump":
		var k: float = f.mt / BUMP.windup
		lean = 0.2 * smooth(k) if k < 1.0 else -0.35 * sin(clamp01((f.mt - BUMP.windup) / 0.3) * PI)
	var dizzy: bool = SH.num(z, "stun") > 0.0
	if dizzy:
		blink = 1 if randf() < 0.3 else 0
		headPitch = -0.15
	# springs
	var sq: float = f.sq.update(dt, 0.0)
	var lz: float = f.lean.update(dt, lean + (-0.04 if speed > 0.3 else 0.0))
	var sy := 1.0 + sq
	root.scale = Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))
	root.position.x = sin(t * 90.0) * jitter if jitter else 0.0
	root.position.y = absf(sin(t * 9.0)) * 0.006 if speed > 0.3 and mode == "roll" else 0.0
	J.column.scale.y = colScale
	J.torso.rotation.x = lz * 0.8
	J.torso.rotation.z = sin(t * 1.3 + z.id) * 0.025
	var breathe := 1.0 + sin(t * PI * 2.0 * 0.3) * 0.015
	J.torso.scale = Vector3(breathe, 1.0 + (breathe - 1.0) * 0.5, breathe)
	# head: aim (lagged), dizzy spin, hurt jolt
	f.hy += (headYaw - f.hy) * minf(1.0, dt * 5.0)
	f.hp += (headPitch - f.hp) * minf(1.0, dt * 5.0)
	if dizzy:
		f.spin += dt * (6.0 + 10.0 * clamp01(SH.num(z, "stun") / 2.0))
	else:
		f.spin *= exp(-dt * 6.0)
	J.head.rotation = Vector3(f.hp - lz * 0.5 - SH.num(st, "hurt") * 0.15, f.hy + f.spin, sin(t * 1.1) * 0.02 + (sin(t * 8.0) * 0.12 if dizzy else 0.0))
	# arms grip the pan handles: follow the head a little
	J.shoulderL.rotation.x = -f.hp * 0.3 + lz * 0.3
	J.shoulderR.rotation.x = -f.hp * 0.3 + lz * 0.3
	J.shoulderL.rotation.y = f.hy * 0.25
	J.shoulderR.rotation.y = f.hy * 0.25
	# wheels roll / screech; casters swivel toward the travel direction
	var roll := (speed + wheelSpin) * dt / WHEEL_R
	for w in m.wheels:
		w.rotation.x -= roll
	var vx: float = z.vel.x
	var vz: float = z.vel.z
	if vx * vx + vz * vz > 0.04:
		var travel := angDiff(yawTo(vx, vz), z.yaw)
		f.caster += angDiff(travel, f.caster) * minf(1.0, dt * 6.0)
	for c in m.casters:
		c.rotation.y = f.caster
	# tally lamp
	if m.tallyMat != null and m.tallyBase != null:
		var on := 0 if z.get("dead") else blink
		var tb: Color = m.tallyBase
		var kk := 1.0 if on else 0.12
		SH.setColorLin(m.tallyMat, Color(tb.r * kk, tb.g * kk, tb.b * kk))
	# flash sprite / lens glow decay (here: the animator also runs while he is stunned)
	if f.flareT >= 0 and g != null:
		f.flareT += dt
		var k: float = f.flareT / 0.28
		m.flare.position = lensWorld(z)
		m.flare.quaternion = SH.camQuat(g)
		m.flare.scale = Vector3.ONE * maxf(0.01, 3.2 * easeOutCubic(k * 2.0) * (1.0 - smooth(k)))
		if k >= 1.0:
			f.flareT = -1.0
			m.flare.visible = false
			DAU.detach(m.flare)
	if f.mode != "flashWind":
		f.iris += (0.0 - f.iris) * minf(1.0, dt * 3.0)
		f.glow += (0.0 - f.glow) * minf(1.0, dt * 2.5)
	# lens iris / glow
	var ir: float = f.iris
	m.blades.visible = ir > 0.02 or SH.num(z, "camDist") < 12.0
	m.blades.scale = Vector3.ONE * lerp_(0.42, 1.28, ir)
	m.blades.rotation.z = ir * 1.4
	var gl: float = f.glow
	m.glow.scale = Vector3.ONE * lerp_(0.35, 1.0, ir)
	SH.setColorLin(m.glow.material_override, Color(lerp_(0.05, 3.2, gl), lerp_(0.07, 3.0, gl), lerp_(0.1, 2.6, gl)))
	# cable follows (when update() did not already tick it this frame)
	if g != null and f.get("cableFrame") != g.time.frame:
		tickCable(g, z, dt)

# ------------------------------------------------------------------------------------------------ behaviour
static func losTo(game, from: Vector3, p) -> bool:
	return SH.lineOfSight(game, from, Vector3(p.pos.x, p.pos.y + 1.4, p.pos.z))

static func lensWorld(z: Dictionary) -> Vector3:
	var m = z.get("model")
	if m != null and m.get("lens") != null:
		return SH.worldPos(m.lens)
	return Vector3(z.pos.x, z.pos.y + 1.7, z.pos.z)

static func move(game, z: Dictionary, dt: float, rad := RADIUS) -> Dictionary:
	z.vy -= G * dt
	var r := SH.moveZ(game, z, Vector3(z.vel.x * dt, z.vy * dt, z.vel.z * dt), rad, HEIGHT, 0.35)
	if r.get("onGround"):
		z.vy = 0.0
	return r

static func turnToward(z: Dictionary, want: float, rate: float, dt: float) -> void:
	var d := angDiff(want, z.yaw)
	var step := clampf(d, -rate * dt, rate * dt)
	z.yaw += step
	z.anim.turn = step / dt if dt > 0 else 0.0

static func startRush(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	f.mode = "rushTele"
	f.mt = 0.0
	f.dustT = 0.0
	SH.audioPlay(game, "bs_rush", {"pos": z.pos})

static func startFlash(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	f.mode = "flashWind"
	f.mt = 0.0
	SH.audioPlay(game, "bs_flash_charge", {"pos": z.pos})

static func flashPop(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	var m = z.model
	var p = game.player
	var a := lensWorld(z)
	SH.audioPlay(game, "bs_flash_pop", {"pos": a})
	if game.fx != null:
		game.fx.flashLight(a, "#FFF4E0", 28, 0.16)
	SH.burst(game, a, {"shape": "star", "count": 6, "speed": 3, "colors": ["#FFFFFF", "#FFF3B0"]})
	f.flareT = 0.0
	f.glow = 1.0
	m.flare.visible = true
	m.flare.position = a
	SH.addTo(SH.sceneRoot(game), m.flare)
	# Does it land? camera forward within 60° of the direction to him, line of sight, in range.
	var cam: Camera3D = game.camera
	var cp := SH.camPos(game)
	var b: Vector3 = -(cam.global_transform.basis.z if cam.is_inside_tree() else cam.transform.basis.z).normalized()
	var c := a - cp
	var dist := c.length()
	c = c.normalized()
	var ang := acos(clampf(b.dot(c), -1.0, 1.0))
	var hit := false
	if p.alive and dist <= FL.range + 2 and ang <= deg_to_rad(FL.cone):
		hit = SH.lineOfSight(game, a, cp) or SH.lineOfSight(game, a, Vector3(p.pos.x, p.pos.y + 1.5, p.pos.z))
	if hit:
		if game.hud != null and game.hud.has_method("whiteout"):
			game.hud.whiteout(FL.white, 1)
		elif game.render != null and game.render.get("post") is Dictionary:
			game.render.post.whiteout = 1
		if p.hurt(FL.dmg, z.pos):
			game.events.emit("zombie:attack", {"z": z, "dmg": FL.dmg, "kind": "flash"})
		if game.screens != null and game.screens.has_method("override"):
			game.screens.override("flinch", null, 3)
	game.events.emit("zombie:flash", {"z": z, "pos": a, "hit": hit})
	SH.netEvent(game, z, "bsFlash", [])     # MP: every peer pops the flash and judges its own player (victim-side)
	f.lastFlashHit = hit

static func casterDust(game, m: Dictionary, size: float, speed: float, life: float, colors: Array) -> void:
	for c in m.casters:
		SH.burst(game, SH.worldPos(c), {"shape": "puff", "count": 1, "size": size, "speed": speed, "life": life, "colors": colors})

static func updateBigShot(game, z: Dictionary, dt: float) -> bool:
	var f: Dictionary = z.flags
	var p = SH.target(game, z)
	if p == null:
		return false
	var Zs = game.zombies
	z.gawkT = 0.0
	f.rushCd -= dt
	f.flashCd -= dt
	f.gap -= dt
	var m = z.model
	# rolling sound follows him
	if f.get("rollSnd") != null:
		if f.rollSnd.has_method("setPos"):
			f.rollSnd.setPos(z.pos)
		if f.rollSnd.has_method("setVol"):
			f.rollSnd.setVol(clamp01(Vector2(z.vel.x, z.vel.z).length() / 3.0) * 0.8 + (0.4 if f.mode == "rush" else 0.0), 0.1)
	var dx: float = p.pos.x - z.pos.x
	var dz: float = p.pos.z - z.pos.z
	var dist := maxf(1e-3, sqrt(dx * dx + dz * dz))
	f.losT -= dt
	if f.losT <= 0:
		f.losT = 0.25
		f.los = losTo(game, Vector3(z.pos.x, z.pos.y + 1.7, z.pos.z), p) if dist < 24.0 else false
	if Zs.get("lure") != null and z.get("lured") and (f.mode == "roll" or f.mode == "skid"):
		f.mode = "roll"
		tickCable(game, z, dt)
		f.cableFrame = game.time.frame
		return false

	match f.mode:
		"rushTele":
			f.mt += dt
			z.vel = z.vel * exp(-dt * 10.0)
			move(game, z, dt)
			if f.mt < RU.tele - 0.12:
				turnToward(z, yawTo(dx, dz), 5.0, dt)
			f.dustT -= dt
			if f.dustT <= 0:
				f.dustT = 0.07
				casterDust(game, m, 0.04, 1.4, 0.3, ["#D8CDB8", "#BFB3A0"])
			z.anim.speed = 0.0
			z.navBest = INF
			if f.mt >= RU.tele:
				f.mode = "rush"
				f.mt = 0.0
				f.rushDir = Vector3(-sin(z.yaw), 0.0, -cos(z.yaw))
				f.rushHit = false
				if z.get("animator") != null:
					z.animator.kick(0.6)
		"rush":
			f.mt += dt
			var sp: float = RU.speed * smooth(f.mt / 0.12)
			z.vel = Vector3(f.rushDir.x * sp, 0.0, f.rushDir.z * sp)
			var bx: float = z.pos.x
			var bz: float = z.pos.z
			var r := move(game, z, dt)
			var moved := Vector2(z.pos.x - bx, z.pos.z - bz).length()
			z.anim.speed = sp
			f.trailT = SH.num(f, "trailT") - dt
			if f.trailT <= 0:
				f.trailT = 0.06
				casterDust(game, m, 0.045, 0.8, 0.3, ["#D8CDB8", "#BFB3A0"])
			var dCam := SH.camPos(game).distance_to(z.pos)
			if dCam < 9.0 and game.fx != null:
				game.fx.shake(0.06 * (1.0 - dCam / 9.0), 0.1)
			# bowl other zombies aside
			for o in Zs.alive:
				if o == z or o.type == "big_shot":
					continue
				var ox: float = o.pos.x - z.pos.x
				var oz: float = o.pos.z - z.pos.z
				if ox * ox + oz * oz < 1.3 * 1.3 and absf(o.pos.y - z.pos.y) < 1.2:
					var side := signf(ox * -f.rushDir.z + oz * f.rushDir.x)
					if side == 0.0:
						side = 1.0
					Zs.knockback(o, Vector3(f.rushDir.x * 0.4 - f.rushDir.z * side * 0.5, 0.0, f.rushDir.z * 0.4 + f.rushDir.x * side * 0.5))
					if o.get("animator") != null and o.animator.has_method("kick"):
						o.animator.kick(0.8)
			# the player (MP: whichever target he runs into)
			var hp_ = null
			if not f.rushHit:
				for q in SH.victims(game, p):
					if q == null or not q.alive:
						continue
					var qd := Vector2(q.pos.x - z.pos.x, q.pos.z - z.pos.z).length()
					var qr := SH.num(q, "radius", 0.0)
					if qd < RADIUS + (qr if qr != 0.0 else 0.38) + 0.2 and absf(q.pos.y - z.pos.y) < 1.5:
						hp_ = q
						break
			if hp_ != null:
				p = hp_
				f.rushHit = true
				SH.netEvent(game, z, "bsHit", ["rush"])
				if SH.isRemote(game, p):
					var rx: float = p.pos.x - z.pos.x
					var rz: float = p.pos.z - z.pos.z
					var rl := Vector2(rx, rz).length()
					if rl == 0.0:
						rl = 1.0
					game.zombies.hurtTarget(p, RU.dmg, z, Vector3(f.rushDir.x * 0.7 + (rx / rl) * 0.3, 0.0, f.rushDir.z * 0.7 + (rz / rl) * 0.3).normalized() * (RU.knock * 6.0), "rush")
				elif p.hurt(RU.dmg, z.pos):
					game.events.emit("zombie:attack", {"z": z, "dmg": RU.dmg, "kind": "rush"})
					var kx: float = p.pos.x - z.pos.x
					var kz: float = p.pos.z - z.pos.z
					var kl := Vector2(kx, kz).length()
					if kl == 0.0:
						kl = 1.0
					# 4 m of knockback: the player's knock decays at exp(-6 t) -> v0 = 6 * 4
					var a: Vector3 = Vector3(f.rushDir.x * 0.7 + (kx / kl) * 0.3, 0.0, f.rushDir.z * 0.7 + (kz / kl) * 0.3).normalized() * (RU.knock * 6.0)
					if p.has_method("knockback"):
						p.knockback(a)
				SH.audioPlay(game, "bs_wall_bonk", {"pos": z.pos, "rate": 1.25, "vol": 0.8})
				if game.fx != null and not SH.isRemote(game, p):
					game.fx.shake(0.35, 0.3)
				f.mode = "skid"
				f.mt = 0.0
				f.skidV = sp * 0.35
				SH.audioPlay(game, "bs_squeak", {"pos": z.pos})
			# a wall: dizzy
			elif r.get("hitWall") and moved < sp * dt * 0.5 and f.mt > 0.1:
				f.mode = "roll"
				f.rushCd = RU.cd
				f.gap = ABILITY_GAP + RU.dizzy
				z.vel = Vector3.ZERO
				f.dizzyUntil = game.time.now + RU.dizzy
				Zs.stun(z, RU.dizzy)
				SH.netEvent(game, z, "bsBonk", [])
				SH.audioPlay(game, "bs_wall_bonk", {"pos": z.pos})
				if z.get("animator") != null:
					z.animator.kick(1.4)
				var a := lensWorld(z)
				SH.burst(game, a, {"shape": "star", "count": 7, "speed": 2.4})
				SH.burst(game, a, {"shape": "spark", "count": 10, "speed": 5})
				var dC := SH.camPos(game).distance_to(z.pos)
				if game.fx != null:
					game.fx.shake(0.3 * (1.0 - dC / 12.0) + 0.08 if dC < 12.0 else 0.05, 0.35)
				# bounce back a little
				z.knock = Vector3(-f.rushDir.x * 2.5, 0.0, -f.rushDir.z * 2.5)
			else:
				if f.mt >= RU.time:
					f.mode = "skid"
					f.mt = 0.0
					f.skidV = sp
					SH.audioPlay(game, "bs_squeak", {"pos": z.pos})
				z.navBest = INF
		"skid":
			f.mt += dt
			var k := clamp01(f.mt / 0.45)
			var sp: float = f.skidV * (1.0 - k) * (1.0 - k)
			z.vel = Vector3(f.rushDir.x * sp, 0.0, f.rushDir.z * sp)
			move(game, z, dt)
			z.anim.speed = sp
			f.trailT = SH.num(f, "trailT") - dt
			if f.trailT <= 0 and sp > 0.5:
				f.trailT = 0.05
				casterDust(game, m, 0.05, 1.0, 0.35, ["#CFC6B6", "#AFA595"])
			if k >= 1.0:
				f.mode = "roll"
				f.rushCd = RU.cd
				f.gap = ABILITY_GAP
			z.navBest = INF
		"flashWind":
			f.mt += dt
			z.vel = z.vel * exp(-dt * 8.0)
			move(game, z, dt)
			turnToward(z, yawTo(dx, dz), 3.0, dt)
			var k := clamp01(f.mt / FL.windup)
			f.iris = smooth(k)
			f.glow = 0.15 + 0.55 * k * k
			z.anim.speed = 0.0
			z.navBest = INF
			if f.mt >= FL.windup:
				flashPop(game, z)
				f.mode = "roll"
				f.flashCd = FL.cd
				f.gap = ABILITY_GAP
		"bump":
			f.mt += dt
			if f.mt < BUMP.windup:
				turnToward(z, yawTo(dx, dz), 4.0, dt)
				z.vel = z.vel * exp(-dt * 10.0)
			elif f.mt < BUMP.windup + 0.25:
				var fx := -sin(z.yaw)
				var fz := -cos(z.yaw)
				z.vel = Vector3(fx * 2.6, 0.0, fz * 2.6)
				if not f.bumped and f.mt >= BUMP.windup + 0.08:
					f.bumped = true
					var fwd := (fx * dx + fz * dz) / dist
					if p.alive and dist < BUMP.range + 0.4 and fwd > 0.3 and absf(p.pos.y - z.pos.y) < 1.4:
						SH.netEvent(game, z, "bsHit", ["bump"])
						if SH.isRemote(game, p):
							game.zombies.hurtTarget(p, BUMP.dmg, z, Vector3(dx / dist, 0.0, dz / dist) * 12.0, "bump")
						elif p.hurt(BUMP.dmg, z.pos):
							game.events.emit("zombie:attack", {"z": z, "dmg": BUMP.dmg, "kind": "bump"})
							var a := Vector3(dx / dist, 0.0, dz / dist) * 12.0
							if p.has_method("knockback"):
								p.knockback(a)
						SH.audioPlay(game, "bs_wall_bonk", {"pos": z.pos, "rate": 1.4, "vol": 0.6})
			else:
				z.vel = z.vel * exp(-dt * 10.0)
			move(game, z, dt)
			z.anim.speed = Vector2(z.vel.x, z.vel.z).length()
			if f.mt >= BUMP.windup + 0.6:
				f.mode = "roll"
				z.cd = BUMP.cd
		_:
			rollStep(game, z, f, p, dt, dist, dx, dz)
	tickCable(game, z, dt)
	f.cableFrame = game.time.frame
	return true

# the JS `default:` branch of updateBigShot (roll: abilities first, then steering)
static func rollStep(game, z: Dictionary, f: Dictionary, p, dt: float, dist: float, dx: float, dz: float) -> void:
	if p.alive and f.gap <= 0 and z.spawnT <= 0 and f.los:
		var canRush: bool = f.rushCd <= 0 and dist <= RU.range and dist > 2.4
		var canFlash: bool = f.flashCd <= 0 and dist <= FL.range
		if canRush and canFlash:
			if dist > 7.0 or randf() < 0.5:
				startFlash(game, z)
			else:
				startRush(game, z)
			return
		if canRush:
			startRush(game, z)
			return
		if canFlash:
			startFlash(game, z)
			return
	if p.alive and dist < BUMP.range and z.cd <= 0 and absf(p.pos.y - z.pos.y) < 1.4:
		f.mode = "bump"
		f.mt = 0.0
		f.bumped = false
		SH.audioPlay(game, "bs_squeak", {"pos": z.pos, "rate": 1.2})
		return
	# steer: straight when visible and close, else the flow field
	var d := Vector3.ZERO
	if f.los and dist < 10.0:
		d = Vector3(dx / dist, 0.0, dz / dist)
	else:
		d = SH.navDir(game, z.pos.x, z.pos.z)
		if d.length_squared() < 1e-6:
			d = Vector3(dx / dist, 0.0, dz / dist)
	d.x += SH.num(z, "sepX") * 0.6
	d.z += SH.num(z, "sepZ") * 0.6
	var want := yawTo(d.x, d.z)
	turnToward(z, want, TURN, dt)
	# rolls forward along his facing (a dolly does not strafe); slows while turning hard
	var align := maxf(0.0, cos(angDiff(want, z.yaw)))
	var sp: float = (0.0 if dist < 1.6 else z.speed) * (0.35 + 0.65 * align)
	var k := 1.0 - exp(-dt * 3.0)
	z.vel.x += (-sin(z.yaw) * sp - z.vel.x) * k
	z.vel.z += (-cos(z.yaw) * sp - z.vel.z) * k
	move(game, z, dt)
	z.anim.speed = Vector2(z.vel.x, z.vel.z).length()

# ------------------------------------------------------------------------------------------------ death
static func startDeath(game, z: Dictionary, _info) -> void:
	var f: Dictionary = z.flags
	var m = z.model
	f.mode = "dying"
	unregisterPlug(game, z)
	if f.get("rollSnd") != null:
		if f.rollSnd.has_method("stop"):
			f.rollSnd.stop(0.2)
		f.rollSnd = null
	var d := {"t": 0.0, "tip": -1.0 if randf() < 0.5 else 1.0, "dissolved": false, "clunk": false}
	f.death = d
	var a := SH.worldPos(m.head)
	d.headPos = a
	# flashbulb burst
	SH.audioPlay(game, "bs_death", {"pos": a})
	if game.fx != null:
		game.fx.flashLight(a, "#FFF6E6", 34, 0.22)
	SH.burst(game, a, {"shape": "spark", "count": 22, "speed": 7, "colors": ["#FFFFFF", "#DDF6FF", "#9FE0FF"]})
	SH.burst(game, a, {"shape": "static", "count": 18, "speed": 3, "size": 0.09})
	SH.burst(game, a, {"shape": "star", "count": 8, "speed": 3.4})
	SH.burst(game, a, {"shape": "confetti", "count": 14, "speed": 4, "colors": ["#5C7E97", "#EADFC4", "#E2452F", "#232126"]})
	f.flareT = 0.0
	m.flare.visible = true
	m.flare.position = a
	SH.addTo(SH.sceneRoot(game), m.flare)
	var cp := SH.camPos(game)
	if cp.distance_to(a) < 26.0:
		var see := SH.lineOfSight(game, a, cp)
		if see and game.hud != null and game.hud.has_method("whiteout"):
			game.hud.whiteout(0.45, 0.55)
	if game.fx != null:
		game.fx.shake(0.25, 0.3)
	# film spaghetti
	for s in FILM_N:
		var st = m.strips[s]
		var ang := (float(s) / FILM_N) * PI * 2.0 + randf() * 0.4
		var up := 3.5 + randf() * 3.5
		var out := 2.4 + randf() * 2.8
		st.v = Vector3(cos(ang) * out, up, sin(ang) * out)
		st.w = 0.045 + randf() * 0.012
		st.curl = (randf() - 0.5) * 6.0
		for i in FILM_P:
			var pp := a
			pp.y -= i * 0.01
			st.p[i] = pp
			st.q[i] = pp
	m.film.visible = true
	SH.addTo(SH.sceneRoot(game), m.film)
	SH.setColorLin(m.prongMat, Color(0.25, 0.2, 0.15))
	m.halo.visible = false
	# FULL REEL on his first death this game
	var gs := gameState(game)
	if not gs.reelDropped and SH.authority(game):
		gs.reelDropped = true
		var pu = game.powerups
		var pos := Vector3(z.pos.x, z.pos.y + 0.6, z.pos.z)
		if pu != null and pu.has_method("dropGuaranteed"):
			pu.dropGuaranteed("full_reel", pos)
		elif pu != null and pu.has_method("drop"):
			pu.drop("full_reel", pos)

static var _filmIdx := PackedInt32Array()
static var _filmUv := PackedVector2Array()

static func updateFilm(_game, z: Dictionary, dt: float, t: float) -> void:
	var m = z.model
	var floorY: float = z.pos.y + 0.012
	var h := minf(dt, 1.0 / 30.0)
	var segL := 0.16
	for st in m.strips:
		var P: Array = st.p
		var Q: Array = st.q
		# head: explicit velocity (frame-rate independent flight), bounces and slides on the floor
		var p0: Vector3 = P[0]
		var v: Vector3 = st.v
		v.y -= 14.0 * dt
		p0 += v * dt
		if p0.y < floorY:
			p0.y = floorY
			if v.y < 0.0:
				v.y *= -0.25
			v.x *= exp(-dt * 7.0)
			v.z *= exp(-dt * 7.0)
		st.v = v
		P[0] = p0
		Q[0] = p0
		for i in range(1, FILM_P):
			var p: Vector3 = P[i]
			var q: Vector3 = Q[i]
			var onF := p.y <= floorY + 0.003
			var damp := 0.6 if onF else 0.99
			var vx := (p.x - q.x) * damp
			var vy := (p.y - q.y) * 0.99
			var vz := (p.z - q.z) * damp
			Q[i] = p
			p.x += vx
			p.y += vy - 16.0 * h * h
			p.z += vz
			if p.y < floorY:
				p.y = floorY
			P[i] = p
		for it in 3:
			for i in FILM_P - 1:
				var a: Vector3 = P[i]
				var b: Vector3 = P[i + 1]
				var d := b - a
				var l := d.length()
				if l == 0.0:
					l = 1e-6
				if l <= segL:
					continue          # film can bunch up (curls) but not stretch
				var diff := (l - segL) / l
				if i > 0:
					a += d * (diff * 0.3)
				b += d * (-diff * (0.7 if i > 0 else 1.0))
				P[i] = a
				P[i + 1] = b
	# write ribbons (flat strips twisting with a curl)
	var fv := FILM_N * FILM_P * 2
	if _filmIdx.is_empty():
		_filmUv.resize(fv)
		for s in FILM_N:
			for i in FILM_P:
				var k := (s * FILM_P + i) * 2
				_filmUv[k] = Vector2(0.0, i * 0.5)
				_filmUv[k + 1] = Vector2(1.0, i * 0.5)
				if i < FILM_P - 1:
					_filmIdx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	pos.resize(fv)
	nrm.resize(fv)
	var shrink := 1.0 - smooth((t - 1.9) / 0.4)
	for s in FILM_N:
		var st = m.strips[s]
		for i in FILM_P:
			var p: Vector3 = st.p[i]
			var nA: Vector3 = st.p[mini(FILM_P - 1, i + 1)]
			var nB: Vector3 = st.p[maxi(0, i - 1)]
			var b := nA - nB
			if b.length_squared() < 1e-10:
				b = Vector3(0, 0, 1)
			b = b.normalized()
			var tw: float = st.curl * i * 0.18 + t * st.curl * 0.3
			var c := Vector3(cos(tw), 0.35, sin(tw)).normalized()
			var e := b.cross(c)
			if e.length_squared() < 1e-6:
				e = Vector3(1, 0, 0)
			e = e.normalized()
			var w: float = st.w * shrink
			var k := (s * FILM_P + i) * 2
			pos[k] = Vector3(p.x - e.x * w, p.y - e.y * w + 0.003, p.z - e.z * w)
			pos[k + 1] = Vector3(p.x + e.x * w, p.y + e.y * w + 0.003, p.z + e.z * w)
			var nn := e.cross(b).normalized()
			nrm[k] = nn
			nrm[k + 1] = nn
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = _filmUv
	arr[Mesh.ARRAY_INDEX] = _filmIdx
	var am: ArrayMesh = m.film.mesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

static func updateDeath_(game, z: Dictionary, dt: float, t: float) -> void:
	var f: Dictionary = z.flags
	var m = z.get("model")
	var d = f.get("death")
	if d == null or m == null:
		return
	d.t = t
	var J: Dictionary = m.J
	var root := SH.rigRoot(m.rig)
	var G0: Node3D = z.group
	# flare
	if f.flareT >= 0:
		f.flareT += dt
		var k: float = f.flareT / 0.35
		m.flare.quaternion = SH.camQuat(game)
		m.flare.scale = Vector3.ONE * maxf(0.01, 5.5 * easeOutCubic(k * 2.5) * (1.0 - smooth(k)))
		if k >= 1.0:
			f.flareT = -1.0
			m.flare.visible = false
			DAU.detach(m.flare)
	# the camera head pops: swell, then gone
	var hs := 1.0 + t / 0.06 * 0.35 if t < 0.06 else 0.001
	J.head.scale = Vector3.ONE * hs
	# slump: torso folds forward, arms drop, the column telescopes down
	var sl := smooth(t / 0.5)
	J.torso.rotation.x = 0.55 * sl
	J.torso.rotation.z = 0.12 * sl * d.tip
	for S in ["L", "R"]:
		J["shoulder" + S].rotation.x = -0.5 * sl
		J["elbow" + S].rotation.x = 0.4 * sl
	J.column.scale.y = 1.0 - 0.38 * smooth((t - 0.1) / 0.6)
	# tip over (bounce) at 0.8 s
	var tip := easeOutBounce((t - 0.8) / 0.55) * (PI / 2.0 - 0.12)
	root.rotation = Vector3.ZERO
	root.position = Vector3.ZERO
	G0.position = z.pos
	G0.rotation_order = EULER_ORDER_YXZ
	G0.rotation = Vector3(0, z.yaw, 0)
	if t > 0.8:
		# pivot around the base edge: rotate about local z, lift the pivot so the base edge stays on the floor
		root.rotation.z = tip * d.tip
		root.position.x = -sin(tip) * 0.05 * d.tip
		root.position.y = sin(tip) * 0.42
		if not d.clunk and t > 1.05:
			d.clunk = true
			SH.audioPlay(game, "bs_wall_bonk", {"pos": z.pos, "rate": 0.7, "vol": 0.7})
			SH.burst(game, Vector3(z.pos.x, z.pos.y + 0.1, z.pos.z), {"shape": "puff", "count": 6, "size": 0.07, "speed": 2.0, "life": 0.45})
			if game.fx != null:
				game.fx.shake(0.12, 0.2)
	var s := SH.num(z, "scale", 1.0)
	if s == 0.0:
		s = 1.0
	if t > 1.95:
		if not d.dissolved:
			d.dissolved = true
			var a := Vector3(z.pos.x, z.pos.y + 0.4, z.pos.z)
			SH.burst(game, a, {"shape": "static", "count": 30, "speed": 2.4, "size": 0.1, "life": 0.9})
			SH.burst(game, a, {"shape": "confetti", "count": 12, "speed": 3.2})
			SH.audioPlay(game, "zmb_death_static", {"pos": z.pos})
		s *= maxf(0.001, 1.0 - smooth((t - 1.95) / 0.2))
	G0.scale = Vector3(s, s, s)
	for w in m.wheels:
		w.rotation.x -= dt * 4.0 * maxf(0.0, 1.0 - t)
	if m.tallyMat != null:
		SH.setColorLin(m.tallyMat, Color(0.1, 0.02, 0.02))
	SH.setColorLin(m.glow.material_override, Color(0.02, 0.02, 0.03))
	tickCable(game, z, dt, true)
	updateFilm(game, z, dt, t)

# ------------------------------------------------------------------------------------------------ module
func hp(r = 1, _game = null) -> float:
	return maxf(B.hpMul * hpAt(maxf(1.0, float(r))), B.hpMin)

func speed(_r = 1, _game = null) -> float:
	return float(B.speed)

# Boarded windows and the gate only; every board blows out at once, then the toothpaste squeeze (1.5 s).
func entryFilter(w) -> bool:
	return w != null and (w.get("type") == "boarded" or w.get("type") == "gate")

func entry(_game = null, _z = null, _win = null):
	return {"tear": false, "time": 1.5, "style": "blast"}

func build(game, z: Dictionary) -> void:
	var m = acquire(game)
	if m == null:
		return
	resetModel(m)
	z.model = m
	z.group = m.group
	z.rig = m.rig
	z.head = m.head
	z.headR = m.headR
	z.height = HEIGHT
	z.radius = RADIUS
	z.scale = 1.0
	z.hitZones = null
	z.hitTest = makeHitTest(z)
	var f: Dictionary = z.flags
	f.game = game
	f.mode = "roll"
	f.mt = 0.0
	f.t = randf() * 10.0
	f.rushCd = 3.0 + randf() * 2.0
	f.flashCd = 4.5 + randf() * 2.0
	f.gap = 1.5
	f.los = false
	f.losT = randf() * 0.25
	f.iris = 0.0
	f.glow = 0.0
	f.flareT = -1.0
	f.hy = 0.0
	f.hp = 0.0
	f.spin = 0.0
	f.caster = 0.0
	f.sq = Rig.Spring.new(200, 14)
	f.lean = Rig.Spring.new(90, 11)
	f.cableInit = false
	f.cableFrame = -1
	f.dizzyUntil = 0.0
	f.blasted = false
	f.rushDir = Vector3(0, 0, -1)
	f.rushHit = false
	f.bumped = false
	f.skidV = 0.0
	f.dustT = 0.0
	z.animator = BigShotAnimator.new(z, get_script())
	gameState(game)
	SH.addTo(SH.sceneRoot(game), m.cable)
	SH.addTo(SH.sceneRoot(game), m.plug)
	registerPlug(game, z)
	f.rollSnd = game.audio.loop("bs_roll", {"pos": Vector3.ZERO, "vol": 0}) if game.audio != null and game.audio.has_method("loop") else null

func release(game, z: Dictionary) -> void:
	var m = z.get("model")
	unregisterPlug(game, z)
	if z.flags.get("rollSnd") != null:
		if z.flags.rollSnd.has_method("stop"):
			z.flags.rollSnd.stop(0.1)
		z.flags.rollSnd = null
	if m == null:
		return
	DAU.detach(m.group)
	resetModel(m)
	if pool.size() < 4:
		pool.append(m)
	z.model = null

func update(game, z: Dictionary, dt: float) -> bool:
	if not z.flags.cableInit:
		z.flags.cableInit = true
		initCable(z)
	return updateBigShot(game, z, dt)

func updateEntry(game, z: Dictionary, dt: float) -> void:
	var f: Dictionary = z.flags
	if not f.cableInit:
		f.cableInit = true
		initCable(z)
	if f.get("rollSnd") != null and f.rollSnd.has_method("setPos"):
		f.rollSnd.setPos(z.pos)
		if f.rollSnd.has_method("setVol"):
			f.rollSnd.setVol(0.6 if z.state == "approach" else 0.2, 0.1)
	# The blast: a flashbulb pop as every board blows out, a squeak for the toothpaste squeeze.
	if z.state == "vault" and not f.blasted:
		f.blasted = true
		var e = z.get("entry")
		var w = e.get("win") if e is Dictionary else null
		var wpos = w.get("pos") if w != null else null
		var sill := SH.num(w, "sill") if w != null else 0.0
		var a := Vector3(wpos.x if wpos != null else z.pos.x, sill + 1.2, wpos.z if wpos != null else z.pos.z)
		SH.audioPlay(game, "bs_flash_pop", {"pos": a})
		SH.audioPlay(game, "bs_squeak", {"pos": a, "delay": 0.25})
		if game.fx != null:
			game.fx.flashLight(a, "#FFF4E0", 18, 0.14)
		f.glow = 1.0
	f.glow += (0.0 - f.glow) * minf(1.0, dt * 2.5)
	tickCable(game, z, dt)
	f.cableFrame = game.time.frame

# MP client puppet (zombies_net.gd): the replicated mode drives the pose; the cues updateBigShot plays at the mode
# changes are replayed here (dust, sounds, lens charge, roll loop). Cosmetic only.
func puppet(game, z: Dictionary, dt: float) -> void:
	var f: Dictionary = z.flags
	var m = z.model
	if not f.cableInit:
		f.cableInit = true
		initCable(z)
	var mode = f.mode
	if f.get("pMode") != mode:
		match mode:
			"rushTele":
				f.dustT = 0.0
				SH.audioPlay(game, "bs_rush", {"pos": z.pos})
			"rush":
				f.rushDir = Vector3(-sin(z.yaw), 0.0, -cos(z.yaw))
				if z.get("animator") != null:
					z.animator.kick(0.6)
			"skid":
				SH.audioPlay(game, "bs_squeak", {"pos": z.pos})
			"flashWind":
				SH.audioPlay(game, "bs_flash_charge", {"pos": z.pos})
			"bump":
				SH.audioPlay(game, "bs_squeak", {"pos": z.pos, "rate": 1.2})
		f.pMode = mode
		f.mt = 0.0
	else:
		f.mt += dt
	var sp := Vector2(z.vel.x, z.vel.z).length()
	match mode:
		"rushTele":
			f.dustT -= dt
			if f.dustT <= 0:
				f.dustT = 0.07
				casterDust(game, m, 0.04, 1.4, 0.3, ["#D8CDB8", "#BFB3A0"])
		"rush":
			f.trailT = SH.num(f, "trailT") - dt
			if f.trailT <= 0:
				f.trailT = 0.06
				casterDust(game, m, 0.045, 0.8, 0.3, ["#D8CDB8", "#BFB3A0"])
			var dCam := SH.camPos(game).distance_to(z.pos)
			if dCam < 9.0 and game.fx != null:
				game.fx.shake(0.06 * (1.0 - dCam / 9.0), 0.1)
		"skid":
			f.trailT = SH.num(f, "trailT") - dt
			if f.trailT <= 0 and sp > 0.5:
				f.trailT = 0.05
				casterDust(game, m, 0.05, 1.0, 0.35, ["#CFC6B6", "#AFA595"])
		"flashWind":
			var k := clamp01(f.mt / FL.windup)
			f.iris = smooth(k)
			f.glow = 0.15 + 0.55 * k * k
	if f.get("rollSnd") != null:
		if f.rollSnd.has_method("setPos"):
			f.rollSnd.setPos(z.pos)
		if f.rollSnd.has_method("setVol"):
			f.rollSnd.setVol(clamp01(sp / 3.0) * 0.8 + (0.4 if mode == "rush" else 0.0), 0.1)

func puppetEvent(game, z: Dictionary, kind: String, args: Array) -> void:
	var f: Dictionary = z.flags
	match kind:
		"bsFlash":
			if z.get("model") != null:
				flashPop(game, z)
		"bsBonk":
			f.dizzyUntil = game.time.now + RU.dizzy
			SH.audioPlay(game, "bs_wall_bonk", {"pos": z.pos})
			if z.get("animator") != null:
				z.animator.kick(1.4)
			var a := lensWorld(z)
			SH.burst(game, a, {"shape": "star", "count": 7, "speed": 2.4})
			SH.burst(game, a, {"shape": "spark", "count": 10, "speed": 5})
			var dC := SH.camPos(game).distance_to(z.pos)
			if game.fx != null:
				game.fx.shake(0.3 * (1.0 - dC / 12.0) + 0.08 if dC < 12.0 else 0.05, 0.35)
		"bsHit":
			var bump: bool = args.size() > 0 and args[0] == "bump"
			SH.audioPlay(game, "bs_wall_bonk", {"pos": z.pos, "rate": 1.4 if bump else 1.25, "vol": 0.6 if bump else 0.8})

# front ×0.4 / sides+back ×1 / plug ×3 / dizzy ×1.5 from every side.
func onDamage(game, z: Dictionary, amount: float, info = null) -> float:
	var f: Dictionary = z.flags
	if not (info is Dictionary):
		info = {}
	if info.get("zone") == "plug":
		return amount * B.plug
	if SH.num(f, "dizzyUntil") != 0.0 and game.time.now < f.dizzyUntil:
		var hm0 := weaponHeadMul(game, info.get("weaponId")) if info.get("head") else 1.0
		return (amount / hm0) * RU.dizzyMul
	var dx := 0.0
	var dz := 0.0
	if info.get("dir") != null:
		dx = -info.dir.x
		dz = -info.dir.z
	else:
		# MP: the attacker's position (info.by) instead of the local player's
		var src = game.player
		var by = info.get("by")
		if by != null and game.get("net") != null and game.net.inGame and game.net.playerById(int(by)) != null:
			src = game.net.playerById(int(by))
		dx = src.pos.x - z.pos.x
		dz = src.pos.z - z.pos.z
	var l := sqrt(dx * dx + dz * dz)
	if l == 0.0:
		l = 1.0
	var facing: float = z.yaw + SH.num(f, "hy")
	var fwd := (-sin(facing) * dx - cos(facing) * dz) / l
	var hm := weaponHeadMul(game, info.get("weaponId")) if info.get("head") else 1.0   # no head multiplier on him (only the plug)
	return (amount / hm) * (B.front if fwd > 0.5 else 1.0)

func onDeath(game, z: Dictionary, info = null):
	startDeath(game, z, info)
	return DEATH

func updateDeath(game, z: Dictionary, dt: float, t: float) -> void:
	updateDeath_(game, z, dt, t)

# Game.precompile samples (shader warm-up is engine plumbing in Godot; kept for the contract).
func warmup(game) -> Array:
	var out: Array = []
	if pool.is_empty():
		var m0 = acquire(game)
		if m0 != null:
			pool.append(m0)
	if pool.is_empty():
		return out
	var m = pool[0]
	out.append(m.group)
	var s: Array = [m.flare.duplicate(), m.cable.duplicate(), m.plug.duplicate(), m.film.duplicate()]
	for o in s:
		o.visible = true
	out.append_array(s)
	return out

# ---- debug helpers
func forceRush(_game, z) -> bool:
	if z == null or z.get("dead"):
		return false
	z.flags.rushCd = 0.0
	z.flags.flashCd = maxf(z.flags.flashCd, 3.0)
	z.flags.gap = 0.0
	z.flags.los = true
	return true

func forceFlash(_game, z) -> bool:
	if z == null or z.get("dead"):
		return false
	z.flags.flashCd = 0.0
	z.flags.rushCd = maxf(z.flags.rushCd, 3.0)
	z.flags.gap = 0.0
	z.flags.los = true
	return true

func plugOf(z):
	return z.model.plug.position if z != null and z.get("model") != null else null
