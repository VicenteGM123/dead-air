# THE FORECASTER (`forecaster`, "Stormy Stu" clones) type module — GDD §8.3, §5.9, §13 step 4 (port of
# src/actors/types/forecaster.js). Owned by the zombies-specials agent. Contract: the TYPE MODULE CONTRACT in
# zombie_types.gd / src/actors/zombieTypes.js (id, hp, speed, build, release, update, updateEntry, onDamage,
# onDeath/updateDeath, warmup, points, spawnMode 'screen').
#
# Look: the sculpted z_forecaster (humanoid, baked) with a showman strut (Animator style: zombie gait, swinging arms,
#   a lighter wobble) + animator.override poses (pointer twirl, conducting the storm, jab, sob, umbrella dangle).
#   His baked 'cloud' part is detached into the scene: it floats 0.6 m over his head on a spring, flies, locks, strikes.
#   Static-snow eyes (the shared zombie eye material), telescoping pointer ('pointerRod' scales along its length).
# Behaviour (T.zombies.forecaster):
#   - Emerges from screen spawns (fence climbs in the Yard). Keeps 8–14 m from the player, strafing at 2.8 m/s
#     (flips side every 1.5–3 s or when blocked, backs off when closer than 8 m, closes in without line of sight).
#   - LOCAL FORECAST every 6 s, line of sight only: 0.8 s pointer twirl (fc_twirl, sparkles), the cloud flies at 9 m/s
#     to hover 3 m over where the player stood at the cast (below the ceiling), LOCKS: 1.0 s telegraph (it darkens,
#     shakes, drizzles, flickers, fc_rumble, a 1.5 m shadow circle grows on the floor), then a lightning bolt strikes the
#     circle: 40 damage + a 0.5 s static overlay when the player is inside (moving out always dodges it), flash light,
#     scorch, sparks; the cloud flies home at 6 m/s. He points at his cloud the whole time (readable).
#   - Pointer jab (40 dmg, 1.5 m, 0.35 s wind-up) when cornered; zombie:attack {z, dmg}.
#   - THE CLOUD is its own shootable (game.weapons.registerShootable, id 'fc_cloud_<z.id>', HP 50 + 10·round; bullets,
#     melee, grenades within 5 m). Popping it (anywhere, mid-cast too): a mini rainbow + colour confetti (fc_cloud_pop),
#     he SOBS for 3 s (hands on face, tears, fc_sob), then takes ×2 damage for the rest of his life, never casts again
#     and becomes a jogging melee chaser (2.4 m/s; the manager steers, he jabs).
#   - Tiny Tele lure: the manager walks him over (the cloud keeps floating).
# Death (onDeath -> 2.5 s): a polka-dot umbrella pops out of his back (fc_umbrella), snaps open over his head, he floats
#   up 3 m swinging and kicking, then pops into confetti with the harp "ta-da". +100 (points.killBonus).
#   EE (§13): killed with the cloud intact -> emits 'zombie:forecaster_storm' { pos (the cloud), z } and the cloud drifts
#   up and fades (the easter egg may spawn the Stray Storm there).
# Debug: z.def.popCloud(game, z), z.def.castNow(game, z), z.def.cloudOf(z) -> { state, hp, pos }.
#
# Port notes (GDScript): static meshes (umbrella, shadow disc, rainbow) come from
#   blender/runtime/specials.py (res://assets/runtime/specials/fc_*.glb); the canvas textures are drawn with DACanvas; the
#   lightning ribbons are rebuilt per strike here (ArrayMesh). Materials are created with the JS factory calls
#   (game.mats.toon) or as unlit StandardMaterial3D for the JS THREE.MeshBasicMaterials (SH.basic). JS
#   charOpt.gen / mergeAttachments are engine plumbing (not ported). cloneBare (warm-up clones) not needed. The JS
#   art=0 / missing-bake placeholder (buildPlaceholder) is a placeholder-art path: not ported (SPEC §0.2).
#   Renames: parameter `round` -> `r`.
extends RefCounted

const SH = preload("res://scripts/actors/types/sock_hopper.gd")
const ZT_PATH := "res://scripts/actors/zombie_types.gd"

static var F: Dictionary = Config.T.zombies.forecaster
static var R: Dictionary = Config.T.rounds
const G := 22.0
const TWIRL := 0.8
const RETURN_SPEED := 6.0
const CHASE_SPEED := 2.4
static var JAB := {"windup": 0.35, "strike": 0.12, "recover": 0.4, "range": 1.5, "dmg": Config.T.zombies.forecaster.strikeDmg, "cd": 1.4}
const DEATH := 2.5
const FLOAT_H := 3.0
const STRAFE_ACCEL := 6.0
static var SOB_TIME: float = Config.T.zombies.forecaster.sobStun
const FC_STYLE := {"base": "zombie", "arms": "swing", "arm": 0.34, "armRun": 0.22, "elbow": 0.28, "lean": 0.07, "sway": 0.07, "wobble": 0.45,
	"headLag": 1.2, "cycle": 1.05, "legSwing": 0.36, "knee": 0.4, "bob": 0.04}
const RAINBOW := ["#E4473A", "#F08A24", "#F4E03A", "#52D24A", "#3FA8E0", "#8A5AD6"]
const UP := Vector3(0, 1, 0)

# ------------------------------------------------------------------------------------------------ module fields
var id := "forecaster"
var height := 1.8
var radius := 0.38
var dmg = JAB.dmg
var range: float = JAB.range
var windup: float = JAB.windup
var cd: float = JAB.cd
var spawnMode := "screen"
var points := {"killBonus": Config.T.points.forecaster}

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

static func easeInOut(x: float) -> float:
	x = clamp01(x)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

static func angDiff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func yawTo(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

static func hpAt(r: float) -> float:
	return SH.hpAt(r)

static func ZT():
	return load(ZT_PATH) if ResourceLoader.exists(ZT_PATH) else null

# ------------------------------------------------------------------------------------------------ shared FX assets
# discTexture / dotsTexture: the JS canvases, drawn with DACanvas (scripts/gfx/canvas2d.gd; the Blender assets carry
# a copy used while it is missing). rainbowGeometry / umbrella geometry: specials/fc_rainbow.glb, fc_umbrella.glb.
static var umbrellaParts = null
static var boltMat: Material = null
static var glowMat: Material = null
static var serial := 0
static var warned := false

static var discTex = null
static var dotsTex = null

static func discTexture():
	if discTex != null:
		return discTex
	var c = SH.newCanvas(256, 256)
	if c == null:
		discTex = SH.glbTex("fc_disc", "fc_disc")
		return discTex
	var g = c.getContext("2d")
	var grd = g.createRadialGradient(128, 128, 10, 128, 128, 124)
	grd.addColorStop(0, "rgba(30,22,52,0.78)")
	grd.addColorStop(0.72, "rgba(34,26,62,0.62)")
	grd.addColorStop(0.86, "rgba(60,44,110,0.5)")
	grd.addColorStop(0.9, "rgba(210,200,255,0.95)")
	grd.addColorStop(0.95, "rgba(160,140,255,0.55)")
	grd.addColorStop(1, "rgba(120,100,220,0)")
	g.fillStyle = grd
	g.fillRect(0, 0, 256, 256)
	# dashed inner ring
	g.strokeStyle = "rgba(200,190,255,0.55)"
	g.lineWidth = 5
	g.setLineDash([14, 12])
	g.beginPath()
	g.arc(128, 128, 70, 0, PI * 2)
	g.stroke()
	discTex = c.texture
	return discTex

# wrapS repeat, repeat (2, 1): the repeat is baked into the canopy UVs by the Blender asset (SPEC §5.5)
static func dotsTexture():
	if dotsTex != null:
		return dotsTex
	var c = SH.newCanvas(256, 128)
	if c == null:
		dotsTex = SH.glbTex("fc_umbrella", "canopyMesh")
		return dotsTex
	var g = c.getContext("2d")
	g.fillStyle = "#E23B3B"
	g.fillRect(0, 0, 256, 128)
	g.fillStyle = "#FFF4DE"
	for y in 5:
		for x in 9:
			g.beginPath()
			g.arc(x * 30 + (y % 2) * 15 + 6, y * 28 + 12, 6.5 - y * 0.6, 0, PI * 2)
			g.fill()
	# scalloped darker hem band
	g.fillStyle = "#B8262A"
	g.fillRect(0, 118, 256, 10)
	dotsTex = c.texture
	return dotsTex

static func rainbowGeometry() -> Mesh:
	return SH.loadMesh("fc_rainbow", "fc_rainbow")

static func umbrellaAssets(game):
	if umbrellaParts != null:
		return umbrellaParts
	umbrellaParts = {
		"canopyMat": SH.toon(game, "#ffffff", {"map": dotsTexture(), "side": "double", "rough": 0.5, "rim": 0.4, "keepColor": true, "name": "fcUmbrella"}),
		"wood": SH.toon(game, "#8A5A36", {"rough": 0.45, "keepColor": true}),
		"chrome": SH.toon(game, "#D9DDE3", {"metal": 1, "rough": 0.2, "keepColor": true}),
	}
	return umbrellaParts

# Umbrella group: canopy group (y 0.42: lathe canopy + chrome tip at 0.36), chrome shaft, wooden hook (fc_umbrella.glb).
static func buildUmbrella(game) -> Node3D:
	var U = umbrellaAssets(game)
	var src := SH.loadScene("fc_umbrella")
	var g: Node3D = null
	if src != null:
		g = SH.byName(src, "fc_umbrella")
		if g != null and g != src:
			DAU.detach(g)
			src.free()
		elif g == null:
			g = src
	if g == null:
		g = DAU.node3d()
	g.name = "fc_umbrella"
	var canopy: Node3D = SH.byName(g, "canopy")
	var parts := {"canopyMesh": U.canopyMat, "tip": U.chrome, "shaft": U.chrome, "hook": U.wood}
	for nm in parts:
		var mi = SH.byName(g, nm)
		if mi is MeshInstance3D:
			mi.material_override = parts[nm]
	DAU.traverse(g, func(o):
		if o is MeshInstance3D:
			SH.noShadow(o)
			(o as MeshInstance3D).layers = 1 << Config.LAYERS.ZOMBIES)
	DAU.ud(g).canopy = canopy
	return g

# Jagged lightning ribbon (two crossed planes per segment) from a to b. Returns { pos: PackedVector3Array, idx }.
static func boltGeometry(a: Vector3, b: Vector3, jitter := 0.28, n := 9, width := 0.07) -> Dictionary:
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		if i > 0 and i < n:
			p.x += (randf() - 0.5) * jitter * 2.0
			p.z += (randf() - 0.5) * jitter * 2.0
		pts.append(p)
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	for axz in [[1.0, 0.0], [0.0, 1.0]]:
		var ax: float = axz[0]
		var az: float = axz[1]
		var base := pos.size()
		for i in n + 1:
			var w := width * (0.4 if i == n else 1.0 - 0.35 * (float(i) / n))
			var p: Vector3 = pts[i]
			pos.append(Vector3(p.x - ax * w, p.y, p.z - az * w))
			pos.append(Vector3(p.x + ax * w, p.y, p.z + az * w))
			if i < n:
				var k := base + i * 2
				idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	return {"pos": pos, "idx": idx}

static func boltMesh(geo: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = geo.pos
	arr[Mesh.ARRAY_INDEX] = geo.idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

static func boltMaterials() -> void:
	if boltMat != null:
		return
	boltMat = SH.basic(Color(2.6, 2.7, 3.2), {"side": "double", "depthWrite": false, "fog": false, "renderOrder": 3})
	boltMat.resource_name = "fcBoltCore"
	glowMat = SH.basic(Color(0.9, 0.85, 2.2), {"side": "double", "transparent": true, "opacity": 0.55, "additive": true, "depthWrite": false, "fog": false, "renderOrder": 3})
	glowMat.resource_name = "fcBoltGlow"

# ------------------------------------------------------------------------------------------------ model
static var pool: Array = []

static func hasBaked(game) -> bool:
	return SH.charBaked(game, "z_forecaster")

static func buildModel(game):
	var c = SH.buildChar(game, "z_forecaster", {"animator": FC_STYLE})
	if c == null or c.get("group") == null:
		return null
	if c.get("animator") == null:
		push_warning("[forecaster] z_forecaster has no animator")
		return null
	var zt = ZT()
	var eyes = zt.zombieEyeMaterial() if zt != null and zt.has_method("zombieEyeMaterial") else null
	var holder := {"rod": null}
	DAU.traverse(c.group, func(o):
		var ud := DAU.ud(o) if o.has_meta("userData") else {}
		if o is MeshInstance3D and ud.get("staticEye") and eyes != null:
			(o as MeshInstance3D).material_override = eyes
		if o is MeshInstance3D:
			SH.setCast(o, SH.isSkinned(o))
		if String(o.name) == "pointerRod":
			holder.rod = o
			ud.noMerge = true
			(o as Node3D).rotation_order = EULER_ORDER_XYZ)
	var parts = c.get("parts")
	var cloudPivot = parts.get("cloud") if parts is Dictionary else null
	if cloudPivot != null:
		DAU.ud(cloudPivot).noMerge = true
	# mergeAttachments (draw-call merging) is engine plumbing: not ported.
	var bodies: Array = []
	DAU.traverse(c.group, func(o):
		if SH.isSkinned(o):
			if o == c.get("skinnedMesh"):
				bodies.append(o)
			else:
				SH.noShadow(o))
	var m := baseModel(game, c.group, c.rig, c.animator, true)
	m.bodies = bodies
	# the lapel ticket stub (multi-material card) is hidden at distance by the manager's card LOD
	DAU.traverse(c.group, func(o):
		if o is MeshInstance3D and not SH.isSkinned(o) and o.mesh != null and o.mesh.get_surface_count() > 1:
			m.cards.append(o))
	if c.get("skinnedMesh") != null:
		SH.registerSpecialTint(game, SH.meshMat(c.skinnedMesh))
	m.rod = holder.rod
	if cloudPivot != null:
		setupCloud(game, m, cloudPivot)
	return m

static func baseModel(game, group: Node3D, rig, animator, baked: bool) -> Dictionary:
	var J := SH.rigJoints(rig)
	var dims = SH.rigDims(rig)
	var headR: float = (float(dims.headH) if dims != null and dims.get("headH") != null else 0.6) * 0.5
	var head: Node3D = SH.byName(group, "part:headCenter")
	if head == null:
		head = DAU.node3d("part_headCenter")
		head.position = Vector3(0, headR * 0.95, -0.02)
		(J.head as Node3D).add_child(head)
	var m := {"group": group, "rig": rig, "J": J, "animator": animator, "head": head, "headR": headR, "baked": baked,
		"def": {"id": "forecaster"}, "variant": "z_forecaster" if baked else "placeholder", "cards": [], "rod": null,
		"cloud": null, "umbrella": null, "bodies": []}
	serial += 1
	m.serial = serial
	# Per-model FX: storm shell material, shadow disc, bolt meshes, rainbow.
	m.stormMat = SH.toon(game, "#2C3046", {"transparent": true, "opacity": 0, "rough": 0.9, "rim": 0.5, "rimColor": "#A8B4FF", "keepColor": true, "depthWrite": false, "name": "fcStorm" + str(m.serial)})
	var discMat := SH.basic(Color(1, 1, 1), {"map": discTexture(), "transparent": true, "depthWrite": false, "fog": false, "renderOrder": 2})
	discMat.resource_name = "fcShadowDisc"
	m.disc = MeshInstance3D.new()
	m.disc.mesh = SH.loadMesh("fc_disc", "fc_disc")
	m.disc.material_override = discMat
	m.disc.name = "fc_shadowDisc"
	m.disc.layers = 1 << Config.LAYERS.ZOMBIES
	m.disc.visible = false
	SH.noShadow(m.disc)
	boltMaterials()
	m.boltCore = MeshInstance3D.new()
	m.boltCore.material_override = boltMat
	m.boltGlow = MeshInstance3D.new()
	m.boltGlow.material_override = glowMat
	for b in [m.boltCore, m.boltGlow]:
		b.layers = 1 << Config.LAYERS.ZOMBIES
		b.visible = false
		b.extra_cull_margin = 16384.0      # frustumCulled = false
		SH.noShadow(b)
	var rbMat := SH.basic(Color(1.1, 1.1, 1.1), {"vertexColors": true, "transparent": true, "opacity": 1.0, "depthWrite": false, "fog": false, "side": "double"})
	m.rainbow = MeshInstance3D.new()
	m.rainbow.mesh = rainbowGeometry()
	m.rainbow.material_override = rbMat
	m.rainbow.name = "fc_rainbow"
	m.rainbow.layers = 1 << Config.LAYERS.ZOMBIES
	m.rainbow.visible = false
	SH.noShadow(m.rainbow)
	SH.setLayers(group)
	group.name = "zombie_forecaster"
	return m

# the transform of node n in the frame of its ancestor anc (Object3D matrices without the scene graph)
static func xformTo(n: Node3D, anc: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var o: Node = n
	while o != null and o != anc:
		if o is Node3D:
			t = (o as Node3D).transform * t
		o = o.get_parent()
	return t

static func setupCloud(game, m: Dictionary, pivot: Node3D) -> void:
	var mesh: MeshInstance3D = null
	for o in pivot.get_children():
		if o is MeshInstance3D:
			mesh = o
			break
	var cl := {"pivot": pivot, "mesh": mesh, "local": pivot.position, "parent": pivot.get_parent(), "center": Vector3.ZERO,
		"shellG": null, "shell": null}
	pivot.rotation_order = EULER_ORDER_XYZ
	if mesh != null and mesh.mesh != null:
		cl.center = mesh.transform * mesh.mesh.get_aabb().get_center()
		# Storm shell: the same cloud geometry, dark and translucent, a bit larger around the cloud's centre.
		var sg := DAU.node3d("fc_stormShell")
		sg.position = cl.center
		sg.scale = Vector3.ONE * 1.08
		var shell := MeshInstance3D.new()
		shell.mesh = mesh.mesh
		shell.material_override = m.stormMat
		shell.transform = mesh.transform
		shell.position = mesh.position - cl.center
		SH.noShadow(shell)
		if m.stormMat is BaseMaterial3D:
			(m.stormMat as BaseMaterial3D).render_priority = 1
		sg.add_child(shell)
		pivot.add_child(sg)
		cl.shellG = sg
		cl.shell = shell
		SH.noShadow(mesh)
	# Height of the cloud centre over the feet at rest (head joint world y + local offset), for the hover target.
	var w := xformTo(pivot, m.group).origin
	cl.restY = w.y
	cl.aboveHead = w.y - xformTo(m.J.head, m.group).origin.y
	SH.setLayers(pivot)
	m.cloud = cl

static func acquire(game):
	var want := hasBaked(game)
	for i in range(pool.size() - 1, -1, -1):
		if pool[i].baked == want:
			var m = pool[i]
			pool.remove_at(i)
			return m
	if want:
		var m = buildModel(game)
		if m != null:
			return m
		if not warned:
			warned = true
			push_warning("[forecaster] baked model failed")
	# the art=0 / no-bake placeholder (humanoid placeholder + toy cloud) is not ported (SPEC §0.2): the manager
	# spawns a Tuned-In instead
	return null

static func reattachCloud(m: Dictionary) -> void:
	var cl = m.get("cloud")
	if cl == null:
		return
	var piv: Node3D = cl.pivot
	DAU.detach(piv)
	piv.position = cl.local
	piv.rotation = Vector3.ZERO
	piv.scale = Vector3.ONE
	piv.visible = true
	if cl.parent != null:
		cl.parent.add_child(piv)
	SH.setOpacity(m.stormMat, 0.0)
	SH.setEmissiveLin(m.stormMat, Color(0, 0, 0))

static func resetModel(m: Dictionary) -> void:
	var g: Node3D = m.group
	g.visible = true
	g.position = Vector3.ZERO
	g.rotation = Vector3.ZERO
	g.scale = Vector3.ONE
	if m.rig != null:
		for j in SH.rigJoints(m.rig).values():
			if j != null:
				j.scale = Vector3.ONE
		var root := SH.rigRoot(m.rig)
		root.rotation = Vector3.ZERO
		root.scale = Vector3.ONE
	if m.animator != null:
		if "override" in m.animator:
			m.animator.override = null
		var p = m.animator.get("p")
		if p is Dictionary:
			p.arms = "swing"
	if m.rod != null:
		m.rod.scale = Vector3.ONE
	for c in m.cards:
		c.visible = true
	for o in [m.disc, m.boltCore, m.boltGlow, m.rainbow]:
		DAU.detach(o)
		o.visible = false
	if m.umbrella != null:
		DAU.detach(m.umbrella)
	reattachCloud(m)

# ------------------------------------------------------------------------------------------------ cloud
static func cloudWorldCenter(z: Dictionary) -> Vector3:
	var m = z.get("model")
	var cl = m.get("cloud") if m != null else null
	if cl == null:
		return z.pos
	var piv: Node3D = cl.pivot
	var s: float = piv.scale.x
	return piv.quaternion * (cl.center * s) + piv.position

static func hoverTarget(z: Dictionary) -> Vector3:
	var f: Dictionary = z.flags
	var cl = z.model.cloud
	var s := SH.num(z, "scale", 1.0)
	if s == 0.0:
		s = 1.0
	if z.state == "screen" or z.state == "vault":
		# entries (taffy emerge, fence climb): follow the head itself, scaled with the body
		var out := SH.worldPos(z.model.J.head)
		var gs: float = z.group.scale.y if z.group.scale.y != 0.0 else 1.0
		out.y += cl.aboveHead * s * maxf(0.1, gs)
		return out
	var o := Vector3(z.pos.x, z.pos.y + cl.restY * s + sin(f.t * 2.1 + z.id) * 0.045, z.pos.z)
	# follow the head's lean a little
	o.x += -sin(z.yaw) * 0.03
	o.z += -cos(z.yaw) * 0.03
	return o

static func registerCloud(game, z: Dictionary) -> void:
	var W = game.weapons
	var f: Dictionary = z.flags
	f.shootId = "fc_cloud_" + str(z.id)
	if W == null or not W.has_method("registerShootable"):
		return
	W.registerShootable({
		"id": f.shootId,
		"raycast": func(o: Vector3, d: Vector3, mx: float):
			var c = f.get("cloud")
			if c == null or c.state == "popped" or c.state == "gone" or z.get("removed") or z.get("model") == null or not z.model.cloud.pivot.visible:
				return null
			var cc := cloudWorldCenter(z)
			var dd := o - cc
			var sc := SH.num(z, "scale", 1.0)
			var rr := 0.25 * (sc if sc != 0.0 else 1.0)
			var b := dd.dot(d)
			var q := dd.length_squared() - rr * rr
			var disc := b * b - q
			if disc < 0.0:
				return null
			var t := -b - sqrt(disc)
			if t < 0.0 or t > mx:
				return null
			return {"dist": t, "point": o + d * t},
		"onHit": func(info):
			hitCloud(game, z, SH.num(info, "damage"), info if info is Dictionary else {}),
		"blocksBullet": true,
		"melee": true,
	})

static func unregisterCloud(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	if f.get("shootId") == null:
		return
	if game.weapons != null and game.weapons.has_method("unregisterShootable"):
		game.weapons.unregisterShootable(f.shootId)
	f.shootId = null

static func hitCloud(game, z: Dictionary, dmg_: float, info := {}) -> void:
	var f: Dictionary = z.flags
	var c = f.get("cloud")
	if c == null or c.state == "popped" or c.state == "gone" or z.get("dead") or not (dmg_ > 0.0):
		return
	c.hp -= dmg_
	c.punch = 1.0
	var a := cloudWorldCenter(z)
	SH.burst(game, info.point if info.get("point") != null else a, {"shape": "puff", "count": 3, "size": 0.08, "speed": 1.4, "life": 0.4, "colors": ["#AEB6C4", "#8C94A6"]})
	SH.audioPlay(game, "zmb_hit", {"pos": a, "rate": 1.35, "vol": 0.6})
	if c.hp <= 0:
		popCloud(game, z)
	elif game.hud != null and game.hud.has_method("hitmarker"):
		game.hud.hitmarker(false, false)

static func popCloud(game, z: Dictionary) -> bool:
	var f: Dictionary = z.flags
	var c = f.get("cloud")
	var m = z.get("model")
	if c == null or c.state == "popped" or c.state == "gone" or m == null:
		return false
	var a := cloudWorldCenter(z)
	c.state = "popped"
	c.hp = 0.0
	m.cloud.pivot.visible = false
	m.disc.visible = false
	unregisterCloud(game, z)
	# Mini rainbow + colour confetti + a white puff.
	SH.burst(game, a, {"shape": "confetti", "count": 26, "speed": 4, "colors": RAINBOW})
	SH.burst(game, a, {"shape": "star", "count": 6, "speed": 2.6})
	SH.burst(game, a, {"shape": "puff", "count": 6, "size": 0.075, "speed": 2.2, "life": 0.5, "colors": ["#F4F6FA", "#D8DEE8"]})
	SH.audioPlay(game, "fc_cloud_pop", {"pos": a})
	if game.hud != null and game.hud.has_method("hitmarker"):
		game.hud.hitmarker(false, true)
	var rb: MeshInstance3D = m.rainbow
	rb.position = a
	rb.visible = true
	rb.scale = Vector3.ONE * 0.01
	SH.setOpacity(rb.material_override, 1.0)
	SH.addTo(game.scene, rb)
	f.rainbowT = 0.0
	# He sobs, then chases for the rest of his (doubled-damage) life.
	f.sobbed = true
	if not z.get("dead"):
		f.mode = "sob"
		f.mt = 0.0
		f.jab = null
		f.tearT = 0.0
		z.vel = Vector3.ZERO
		SH.audioPlay(game, "fc_sob", {"pos": z.pos})
		if z.get("animator") != null and z.animator.has_method("kick"):
			z.animator.kick(0.8)
	return true

# Cloud state machine: home (hover) -> fly -> lock (telegraph) -> strike -> return -> home. Runs every frame.
static func tickCloud(game, z: Dictionary, dt: float) -> void:
	var f: Dictionary = z.flags
	var c = f.get("cloud")
	var m = z.get("model")
	if c == null or m == null or m.get("cloud") == null:
		return
	f.cloudFrame = game.time.frame
	var cl = m.cloud
	var piv: Node3D = cl.pivot
	# rainbow fades whatever the cloud does
	var rb: MeshInstance3D = m.rainbow
	if f.get("rainbowT") != null and rb.visible:
		f.rainbowT += dt
		var k: float = f.rainbowT
		rb.scale = Vector3.ONE * maxf(0.01, 0.72 * easeOutBack(k / 0.35) * (1.0 + k * 0.15))
		rb.position.y += dt * 0.25
		var cp := SH.camPos(game)
		rb.rotation_order = EULER_ORDER_XYZ
		rb.rotation = Vector3(0, atan2(cp.x - rb.position.x, cp.z - rb.position.z), 0)
		SH.setOpacity(rb.material_override, 1.0 - smooth((k - 1.0) / 0.6))
		if k > 1.6:
			rb.visible = false
			DAU.detach(rb)
	if c.state == "popped" or c.state == "gone":
		return
	piv.visible = z.group.visible or c.state != "home"
	c.t += dt
	c.punch = maxf(0.0, SH.num(c, "punch") - dt * 5.0)
	var dark := 0.0
	var shake := 0.0
	var s := 1.0 + sin(f.t * 3.3 + z.id) * 0.03
	var yawWant: float = z.yaw if c.state == "home" else (c.faceYaw if c.get("faceYaw") != null else z.yaw)
	if c.state == "home":
		var b := hoverTarget(z)
		var k := 1.0 - exp(-dt * 9.0)
		c.pos = c.pos.lerp(b, k)
		# hard clamp: never trail more than 0.5 m (fast knockbacks, teleports)
		if c.pos.distance_squared_to(b) > 0.25:
			c.pos = b + (c.pos - b).normalized() * 0.5
	elif c.state == "fly":
		var dist: float = c.from.distance_to(c.target)
		var dur := maxf(0.15, dist / F.cloudSpeed)
		var u := clamp01(c.t / dur)
		var e := easeInOut(u)
		c.pos = c.from.lerp(c.target, e)
		c.pos.y += sin(u * PI) * minf(1.2, dist * 0.08)
		c.faceYaw = yawTo(c.target.x - c.from.x, c.target.z - c.from.z)
		s *= 1.0 + sin(u * PI) * 0.12
		if u >= 1.0:
			c.state = "lock"
			c.t = 0.0
			beginLock(game, z)
	elif c.state == "lock":
		var u := clamp01(c.t / F.telegraph)
		dark = smooth(u / 0.5)
		shake = 0.015 + 0.035 * u
		s *= 1.0 + 0.12 * smooth(u / 0.3) + sin(c.t * 40.0) * 0.02 * u
		c.pos = c.target
		var d: MeshInstance3D = m.disc
		var grow := easeOutBack(c.t / 0.35)
		var pulse := 1.0 + sin(c.t * 18.0) * 0.03 * u
		d.scale = Vector3.ONE * maxf(0.05, F.strikeR * grow * pulse)
		SH.setOpacity(d.material_override, 0.55 + 0.45 * u)
		# drizzle, then flicker inside the cloud
		c.rainT = SH.num(c, "rainT") - dt
		if c.rainT <= 0:
			c.rainT = lerp_(0.12, 0.035, u)
			var a := Vector3(c.pos.x + (randf() - 0.5) * 0.35, c.pos.y - 0.12, c.pos.z + (randf() - 0.5) * 0.2)
			SH.burst(game, a, {"shape": "goo", "count": 1, "size": 0.025, "speed": 0.4, "life": 0.6, "gravity": 16, "dir": Vector3(0, -1, 0), "cone": 0.1, "colors": ["#7FC4FF", "#B8E2FF"]})
		if u > 0.55:
			var fl := 1.4 if randf() < 0.35 else 0.0
			SH.setEmissiveLin(m.stormMat, Color(fl * 0.8, fl * 0.85, fl * 1.2))
		if c.t >= F.telegraph:
			strike(game, z)
	elif c.state == "strike":
		dark = 1.0 - smooth(c.t / 0.5) * 0.6
		c.pos = c.target
		var u := clamp01(c.t / 0.28)
		var vis: bool = u < 1.0 and (c.t < 0.06 or int(floorf(c.t * 40.0)) % 3 != 0)
		m.boltCore.visible = vis
		m.boltGlow.visible = vis
		SH.setEmissiveLin(m.stormMat, Color(1.2, 1.25, 1.6) if vis else Color(0, 0, 0))
		SH.setOpacity(m.disc.material_override, maxf(0.0, 1.0 - c.t / 0.35))
		m.disc.scale = Vector3.ONE * (F.strikeR * (1.0 + c.t * 0.3))
		if c.t >= 0.5:
			m.disc.visible = false
			m.boltCore.visible = false
			m.boltGlow.visible = false
			SH.setEmissiveLin(m.stormMat, Color(0, 0, 0))
			c.state = "return"
			c.t = 0.0
	elif c.state == "return":
		dark = maxf(0.0, 0.4 - c.t)
		var b := hoverTarget(z)
		var dv: Vector3 = b - c.pos
		var d := dv.length()
		var step := RETURN_SPEED * dt
		c.faceYaw = yawTo(dv.x, dv.z)
		if d <= step + 0.02:
			c.pos = b
			c.state = "home"
			c.t = 0.0
			c.punch = 0.8
		else:
			c.pos = c.pos + dv * (step / d)
	elif c.state == "drift":
		# his owner is gone: drift up and fade (the EE may take over from here)
		c.pos.y += dt * 0.9
		c.pos.x += sin(c.t * 1.7) * dt * 0.3
		s *= 1.0 - smooth((c.t - 0.6) / 0.6)
		dark = 0.3
		if c.t > 1.2:
			c.state = "gone"
			piv.visible = false
			return
	# write the transform
	piv.position = c.pos
	if shake:
		piv.position.x += (randf() - 0.5) * shake * 2.0
		piv.position.y += (randf() - 0.5) * shake
		piv.position.z += (randf() - 0.5) * shake * 2.0
	c.yaw += angDiff(yawWant, c.yaw) * minf(1.0, dt * 6.0)
	piv.rotation = Vector3(sin(f.t * 1.3 + z.id) * 0.06, c.yaw, sin(f.t * 1.7) * 0.05)
	var punch: float = 1.0 + sin((1.0 - c.punch) * PI * 3.0) * 0.18 * c.punch
	var zs := SH.num(z, "scale", 1.0)
	if zs == 0.0:
		zs = 1.0
	var entryS := 1.0
	if c.state == "home" and (z.state == "screen" or z.state == "vault"):
		var gs: float = z.group.scale.y if z.group.scale.y != 0.0 else 1.0
		entryS = maxf(0.1, gs) / zs
	var sc := zs * s * punch * entryS
	piv.scale = Vector3(sc * (1.0 + 0.1 * c.punch), sc * (1.0 - 0.08 * c.punch), sc)
	c.dark += (dark - c.dark) * minf(1.0, dt * 10.0)
	SH.setOpacity(m.stormMat, c.dark * 0.8)   # the grumpy face still shows through
	if cl.shellG != null:
		cl.shellG.visible = c.dark > 0.02
	if c.state != "lock" and c.state != "strike":
		SH.setEmissiveLin(m.stormMat, Color(0, 0, 0))

static func launchCloud(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	var c = f.cloud
	var p = game.player
	var col = SH.colOf(game)
	c.from = c.pos
	var target := Vector3(p.pos.x, p.pos.y + FLOAT_H, p.pos.z)
	# stay under the ceiling
	var hit = col.raycast(Vector3(p.pos.x, p.pos.y + 1.2, p.pos.z), UP, FLOAT_H + 0.5) if col != null else null
	if hit != null and hit.get("point") != null:
		target.y = minf(target.y, hit.point.y - 0.4)
	target.y = maxf(target.y, p.pos.y + 1.9)
	c.target = target
	var fy := SH.floorAt(game, p.pos.x, p.pos.z, p.pos.y + 0.5)
	c.floor = Vector3(p.pos.x, (fy if fy > -INF else p.pos.y) + 0.03, p.pos.z)
	c.state = "fly"
	c.t = 0.0
	SH.audioPlay(game, "zmb_swipe", {"pos": c.pos, "rate": 0.7, "vol": 0.6})

static func beginLock(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	var c = f.cloud
	var m = z.model
	var d: MeshInstance3D = m.disc
	d.position = c.floor
	d.scale = Vector3.ONE * 0.05
	SH.setOpacity(d.material_override, 0.5)
	d.visible = true
	SH.addTo(game.scene, d)
	SH.audioPlay(game, "fc_rumble", {"pos": c.target})

static func strike(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	var c = f.cloud
	var m = z.model
	var p = game.player
	c.state = "strike"
	c.t = 0.0
	var top := Vector3(c.target.x, c.target.y - 0.12, c.target.z)
	var bot: Vector3 = c.floor
	# bolt geometry (regenerated per strike)
	var core := boltGeometry(top, bot, 0.26, 9, 0.05)
	m.boltCore.mesh = boltMesh(core)
	# the glow: the core's zig-zag, widened
	var P: PackedVector3Array = core.pos.duplicate()
	var n := P.size() / 2
	for i in n:
		var k := i * 2
		var cx := (P[k].x + P[k + 1].x) / 2.0
		var cz := (P[k].z + P[k + 1].z) / 2.0
		P[k] = Vector3(cx + (P[k].x - cx) * 3.6, P[k].y, cz + (P[k].z - cz) * 3.6)
		P[k + 1] = Vector3(cx + (P[k + 1].x - cx) * 3.6, P[k + 1].y, cz + (P[k + 1].z - cz) * 3.6)
	m.boltGlow.mesh = boltMesh({"pos": P, "idx": core.idx})
	for b in [m.boltCore, m.boltGlow]:
		b.visible = true
		SH.addTo(game.scene, b)
	SH.audioPlay(game, "fc_lightning", {"pos": bot})
	if game.fx != null:
		game.fx.flashLight(Vector3(bot.x, bot.y + 1.0, bot.z), "#C8D4FF", 16, 0.14)
	SH.burst(game, bot, {"shape": "spark", "count": 18, "speed": 8, "colors": ["#FFFFFF", "#C8D4FF", "#9FB6FF"]})
	SH.burst(game, bot, {"shape": "static", "count": 12, "speed": 2.6, "size": 0.08})
	SH.burst(game, bot, {"shape": "puff", "count": 5, "size": 0.16, "speed": 1.6, "colors": ["#5A5F72", "#8A8FA2"]})
	if game.fx != null and game.fx.has_method("decal"):
		game.fx.decal(bot, UP, "scorch", 1.3)
	var dCam := SH.camPos(game).distance_to(bot)
	if dCam < 14.0 and game.fx != null:
		game.fx.shake(0.35 * (1.0 - dCam / 14.0) + 0.05, 0.3)
	# Damage: inside the circle (horizontally) and roughly on that floor.
	var hd := Vector2(p.pos.x - bot.x, p.pos.z - bot.z).length()
	var dy: float = p.pos.y - bot.y
	if p.alive and hd <= F.strikeR and dy > -0.8 and dy < 1.8:
		if p.hurt(F.strikeDmg, bot):
			game.events.emit("zombie:attack", {"z": z, "dmg": F.strikeDmg, "kind": "lightning"})
			# 0.5 s static overlay (the HUD owns the post knobs and decays them itself)
			if game.hud != null and game.hud.has_method("glitch"):
				game.hud.glitch(1, 0.5)
			if game.hud != null and game.hud.has_method("tear"):
				game.hud.tear("top")

# ------------------------------------------------------------------------------------------------ poses
static func makeOverride(z: Dictionary) -> Callable:
	return func(rig, dt: float):
		var f = z.get("flags")
		if f == null or z.get("model") == null:
			return
		var g = f.get("game")
		if g != null and f.get("cloudFrame") != g.time.frame and not z.get("dead"):
			tickCloud(g, z, dt)
		poseForecaster(z, rig if rig != null else z.model.rig, dt)

static func aimArm(J: Dictionary, pitch: float, yawOff: float, k: float) -> void:
	# right arm points along (pitch up from horizontal, yaw offset from the body facing)
	J.shoulderR.rotation.x = lerp_(J.shoulderR.rotation.x, PI / 2.0 + pitch, k)
	J.shoulderR.rotation.y = lerp_(J.shoulderR.rotation.y, 0.0, k)
	J.shoulderR.rotation.z = lerp_(J.shoulderR.rotation.z, -0.15 + yawOff, k)
	J.elbowR.rotation.x = lerp_(J.elbowR.rotation.x, 0.08, k)
	J.handR.rotation.x = lerp_(J.handR.rotation.x, 1.1, k)

static func poseForecaster(z: Dictionary, rig, dt: float) -> void:
	var f: Dictionary = z.flags
	var J := SH.rigJoints(rig)
	var m = z.model
	f.t += dt
	var t: float = f.t
	var rod := 0.38
	var mode = f.mode
	var cst = f.cloud.state if f.get("cloud") != null else null
	if mode == "twirl":
		var u := clamp01(f.mt / TWIRL)
		var up := easeOutBack(u / 0.25)
		# arm up over the head, forearm spinning the pointer in circles
		J.shoulderR.rotation.x = lerp_(J.shoulderR.rotation.x, 2.75, up)
		J.shoulderR.rotation.z = lerp_(J.shoulderR.rotation.z, -0.25, up)
		J.elbowR.rotation.x = 0.35 + sin(t * 26.0) * 0.35 * up
		J.elbowR.rotation.y = cos(t * 26.0) * 0.45 * up
		J.handR.rotation.x = 0.9 + sin(t * 26.0 + 1.0) * 0.3
		J.spine.rotation.x += 0.12 * up
		J.head.rotation.x += 0.28 * up
		J.shoulderL.rotation.x = lerp_(J.shoulderL.rotation.x, 0.5, up)
		J.shoulderL.rotation.z = lerp_(J.shoulderL.rotation.z, 0.9, up)
		J.elbowL.rotation.x = lerp_(J.elbowL.rotation.x, 1.2, up)
		rod = lerp_(0.38, 1.0, smooth(u / 0.3))
		# finale: snap the pointer at the player
		if u > 0.8:
			aimArm(J, 0.35, 0.0, smooth((u - 0.8) / 0.2))
	elif mode == "conduct" or ((cst == "fly" or cst == "lock" or cst == "strike") and not f.sobbed and mode != "jab"):
		# point at the cloud
		var c = f.get("cloud")
		var tgt: Vector3 = c.pos if c != null and c.get("pos") != null else z.pos
		var dx: float = tgt.x - z.pos.x
		var dz: float = tgt.z - z.pos.z
		var dy: float = tgt.y - (z.pos.y + 1.45)
		var pitch := atan2(dy, sqrt(dx * dx + dz * dz))
		var yawOff := clampf(angDiff(yawTo(dx, dz), z.yaw), -0.8, 0.8)
		aimArm(J, clampf(pitch, -0.4, 1.3), -yawOff * 0.8, 0.85)
		J.chest.rotation.y += yawOff * 0.4
		J.head.rotation.x += clampf(pitch, -0.3, 0.8) * 0.4
		var strikeK := maxf(0.0, 1.0 - c.t / 0.3) if c != null and c.state == "strike" else 0.0
		J.spine.rotation.x += 0.18 * strikeK
		rod = 1.0
	elif mode == "jab" and f.get("jab") != null:
		var j = f.jab
		var tt: float = j.t
		if tt < JAB.windup:
			var k := smooth(tt / JAB.windup)
			J.shoulderR.rotation.x = lerp_(J.shoulderR.rotation.x, -0.55, k)
			J.elbowR.rotation.x = lerp_(J.elbowR.rotation.x, 1.5, k)
			J.chest.rotation.y += 0.35 * k
			rod = lerp_(0.38, 0.6, k)
		elif tt < JAB.windup + JAB.strike:
			var k := easeOutCubic((tt - JAB.windup) / JAB.strike)
			J.shoulderR.rotation.x = lerp_(-0.55, 1.55, k)
			J.elbowR.rotation.x = lerp_(1.5, 0.02, k)
			J.handR.rotation.x = 1.2
			J.chest.rotation.y += lerp_(0.35, -0.3, k)
			J.spine.rotation.x -= 0.15 * k
			rod = 1.0
		else:
			var k := smooth((tt - JAB.windup - JAB.strike) / JAB.recover)
			J.shoulderR.rotation.x = lerp_(1.55, J.shoulderR.rotation.x, k)
			J.elbowR.rotation.x = lerp_(0.02, J.elbowR.rotation.x, k)
			J.handR.rotation.x = lerp_(1.2, 0.0, k)
			J.chest.rotation.y += -0.3 * (1.0 - k)
			rod = lerp_(1.0, 0.38, k)
	elif mode == "sob":
		var k := smooth(f.mt / 0.25) * (1.0 - smooth((f.mt - SOB_TIME + 0.3) / 0.3))
		var shk := sin(t * 22.0) * 0.06
		J.shoulderL.rotation = Vector3(lerp_(J.shoulderL.rotation.x, 2.1, k), 0.0, lerp_(J.shoulderL.rotation.z, -0.35, k))
		J.shoulderR.rotation = Vector3(lerp_(J.shoulderR.rotation.x, 2.1, k), 0.0, lerp_(J.shoulderR.rotation.z, 0.35, k))
		J.elbowL.rotation.x = lerp_(J.elbowL.rotation.x, 2.3, k)
		J.elbowR.rotation.x = lerp_(J.elbowR.rotation.x, 2.3, k)
		J.spine.rotation.x -= 0.25 * k
		J.chest.rotation.x += shk * k
		J.head.rotation.x -= (0.35 + shk) * k
		J.kneeL.rotation.x -= 0.25 * k
		J.kneeR.rotation.x -= 0.25 * k
		J.hipL.rotation.x += 0.12 * k
		J.hipR.rotation.x += 0.12 * k
		rod = 0.38
	elif mode == "dying":
		# hanging from the umbrella: both arms up, legs dangling and kicking
		var d = f.get("death")
		var dT := SH.num(d, "t") if d != null else 0.0
		var k := smooth((dT - 0.15) / 0.25)
		J.shoulderL.rotation = Vector3(lerp_(J.shoulderL.rotation.x, 3.0, k), 0.0, lerp_(J.shoulderL.rotation.z, -0.12, k))
		J.shoulderR.rotation = Vector3(lerp_(J.shoulderR.rotation.x, 3.0, k), 0.0, lerp_(J.shoulderR.rotation.z, 0.12, k))
		J.elbowL.rotation.x = lerp_(J.elbowL.rotation.x, 0.2, k)
		J.elbowR.rotation.x = lerp_(J.elbowR.rotation.x, 0.2, k)
		var kick := sin(t * 9.0) * 0.45 * k
		J.hipL.rotation.x = 0.1 + kick
		J.hipR.rotation.x = 0.1 - kick
		J.kneeL.rotation.x = -0.3 - maxf(0.0, kick)
		J.kneeR.rotation.x = -0.3 - maxf(0.0, -kick)
		J.footL.rotation.x = 0.4
		J.footR.rotation.x = 0.4
		J.head.rotation.x += 0.25 * k
		rod = 0.38
	elif cst == "home" and not f.sobbed:
		# idle showmanship: now and then an open-palm "and here's the weather" sweep with the left hand
		var ph := fmod(t + z.id * 1.7, 7.0)
		if ph < 1.2:
			var k := sin((ph / 1.2) * PI)
			J.shoulderL.rotation.x += 0.9 * k
			J.shoulderL.rotation.z += 0.7 * k
			J.elbowL.rotation.x += 0.2 * k
			J.handL.rotation.z -= 0.4 * k
	if m.rod != null:
		f.rod = rod if f.get("rod") == null else f.rod + (rod - f.rod) * minf(1.0, dt * 14.0)
		m.rod.scale = Vector3(1.0, maxf(0.3, f.rod), 1.0)

# ------------------------------------------------------------------------------------------------ behaviour
static func losTo(game, z: Dictionary, p) -> bool:
	return SH.lineOfSight(game, Vector3(z.pos.x, z.pos.y + 1.5, z.pos.z), Vector3(p.pos.x, p.pos.y + 1.4, p.pos.z))

static func startJab(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	f.prevMode = f.mode
	f.mode = "jab"
	f.jab = {"t": 0.0, "hit": false}
	SH.audioPlay(game, "zmb_swipe", {"pos": z.pos, "rate": 1.2, "vol": 0.7})

static func doJab(game, z: Dictionary, dt: float) -> void:
	var f: Dictionary = z.flags
	var j = f.jab
	var p = game.player
	j.t += dt
	var dx: float = p.pos.x - z.pos.x
	var dz: float = p.pos.z - z.pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if j.t < JAB.windup:
		z.yaw += angDiff(yawTo(dx, dz), z.yaw) * minf(1.0, dt * 10.0)
	if not j.hit and j.t >= JAB.windup + JAB.strike * 0.6:
		j.hit = true
		z.cd = JAB.cd
		var fwd: float = (-sin(z.yaw) * dx - cos(z.yaw) * dz) / maxf(1e-3, dist)
		if p.alive and dist < JAB.range + 0.35 and absf(p.pos.y - z.pos.y) < 1.3 and fwd > 0.4:
			if p.hurt(JAB.dmg, z.pos):
				game.events.emit("zombie:attack", {"z": z, "dmg": JAB.dmg, "kind": "jab"})
				var a := Vector3(dx, 0.0, dz).normalized() * 3.0
				if p.has_method("knockback"):
					p.knockback(a)
			SH.audioPlay(game, "zmb_hit", {"pos": p.pos, "rate": 1.5, "vol": 0.7})
	z.vel = z.vel * exp(-dt * 10.0)
	fall(game, z, dt)
	if j.t >= JAB.windup + JAB.strike + JAB.recover:
		f.mode = "chase" if f.sobbed else "strafe"
		f.jab = null

static func fall(game, z: Dictionary, dt: float) -> Dictionary:
	z.vy -= G * dt
	var r := SH.moveZ(game, z, Vector3(z.vel.x * dt, z.vy * dt, z.vel.z * dt), z.radius, z.height, 0.45)
	if r.get("onGround"):
		z.vy = 0.0
	return r

static func strafe(game, z: Dictionary, dt: float, dist: float, dx: float, dz: float) -> void:
	var f: Dictionary = z.flags
	var near: float = F.keep[0]
	var far: float = F.keep[1]
	var mx := 0.0
	var mz := 0.0
	var ux := dx / dist
	var uz := dz / dist
	f.sideT -= dt
	if f.sideT <= 0:
		f.side = -f.side
		f.sideT = 1.5 + randf() * 1.5
	if not f.los or dist > far:
		if f.los and dist < far + 6.0:
			mx = ux
			mz = uz
		else:
			var d := SH.navDir(game, z.pos.x, z.pos.z)
			mx = d.x
			mz = d.z
			if not mx and not mz:
				mx = ux
				mz = uz
	elif dist < near:
		mx = -ux * 0.85 + -uz * f.side * 0.5
		mz = -uz * 0.85 + ux * f.side * 0.5
	else:
		var radial := clampf((dist - (near + far) / 2.0) / 3.0, -1.0, 1.0) * 0.35
		mx = -uz * f.side + ux * radial
		mz = ux * f.side + uz * radial
	mx += SH.num(z, "sepX") * 1.2
	mz += SH.num(z, "sepZ") * 1.2
	var l := sqrt(mx * mx + mz * mz)
	if l == 0.0:
		l = 1.0
	var sp: float = z.speed
	var k := 1.0 - exp(-dt * STRAFE_ACCEL)
	z.vel.x += ((mx / l) * sp - z.vel.x) * k
	z.vel.z += ((mz / l) * sp - z.vel.z) * k
	var r := fall(game, z, dt)
	if r.get("hitWall") and f.blockT <= 0:
		f.side = -f.side
		f.sideT = 1.2 + randf()
		f.blockT = 0.5
	f.blockT -= dt
	# face the player (when visible), legs toward the movement
	var faceYaw: float = yawTo(dx, dz) if f.los else (yawTo(z.vel.x, z.vel.z) if z.vel.length_squared() > 0.05 else z.yaw)
	var prev: float = z.yaw
	z.yaw += angDiff(faceYaw, z.yaw) * minf(1.0, dt * 7.0)
	z.anim.turn = (z.yaw - prev) / maxf(dt, 1e-4)
	var spd := Vector2(z.vel.x, z.vel.z).length()
	z.anim.speed = spd
	if spd > 0.2:
		var moveYaw := yawTo(z.vel.x, z.vel.z)
		var rel := angDiff(moveYaw, z.yaw)
		var back := absf(rel) > PI * 0.6
		if back:
			rel = angDiff(moveYaw + PI, z.yaw)
		z.anim.back = back
		z.anim.legYaw = clampf(rel, -1.1, 1.1)
	else:
		z.anim.back = false
		z.anim.legYaw = 0.0
	# Holding range on purpose is not being stuck (the manager's anti-stuck watches nav distance).
	if f.los and dist < far + 3.0:
		z.navBest = INF

static func updateForecaster(game, z: Dictionary, dt: float) -> bool:
	var f: Dictionary = z.flags
	var p = game.player
	var Zs = game.zombies
	z.gawkT = 0.0
	tickCloud(game, z, dt)
	var dx: float = p.pos.x - z.pos.x
	var dz: float = p.pos.z - z.pos.z
	var dist := maxf(1e-3, sqrt(dx * dx + dz * dz))
	f.losT -= dt
	if f.losT <= 0:
		f.losT = 0.25
		f.los = losTo(game, z, p) if dist < 30.0 else false
	f.castT -= dt
	# flavour: cheesy humming
	f.humT -= dt
	if f.humT <= 0:
		f.humT = 5.0 + randf() * 5.0
		if dist < 16.0 and not f.sobbed and f.mode == "strafe":
			SH.audioPlay(game, "fc_hum", {"pos": z.pos, "rate": 0.95 + randf() * 0.1, "vol": 0.7})
	if Zs.get("lure") != null and z.get("lured") and f.mode != "sob" and f.mode != "jab":
		if f.mode == "twirl":
			f.mode = "strafe"
		z.anim.legYaw = 0.0
		z.anim.back = false
		return false

	match f.mode:
		"sob":
			f.mt += dt
			z.vel = z.vel * exp(-dt * 10.0)
			fall(game, z, dt)
			z.anim.speed = 0.0
			z.anim.legYaw = 0.0
			z.anim.back = false
			f.tearT -= dt
			if f.tearT <= 0 and z.get("head") != null:
				f.tearT = 0.09
				var a := SH.worldPos(z.head)
				a.y += 0.02
				for s in [-1.0, 1.0]:
					var b := Vector3(-cos(z.yaw) * 0.08 * s, 0.0, sin(z.yaw) * 0.08 * s) + a
					b.x += -sin(z.yaw) * 0.14
					b.z += -cos(z.yaw) * 0.14
					SH.burst(game, b, {"shape": "goo", "count": 1, "size": 0.03, "speed": 1.6, "life": 0.5, "gravity": 14, "dir": Vector3(-cos(z.yaw) * s, 0.6, sin(z.yaw) * s), "cone": 0.4, "colors": ["#6FC0FF", "#B8E6FF"]})
			if f.mt > 1.5 and not f.get("sob2"):
				f.sob2 = true
				SH.audioPlay(game, "fc_sob", {"pos": z.pos, "rate": 1.08, "vol": 0.8})
			z.navBest = INF
			if f.mt >= SOB_TIME:
				f.mode = "chase"
				z.speed = CHASE_SPEED
				if z.get("animator") != null:
					var ap = z.animator.get("p")
					if ap is Dictionary:
						ap.arms = "forward"
				SH.audioPlay(game, "zmb_groan_chase", {"pos": z.pos, "rate": 0.9})
			return true
		"jab":
			doJab(game, z, dt)
			return true
		"chase":
			z.anim.legYaw = 0.0
			z.anim.back = false
			if p.alive and dist < JAB.range and z.cd <= 0 and absf(p.pos.y - z.pos.y) < 1.2:
				startJab(game, z)
				doJab(game, z, 0.0)
				return true
			return false
		"twirl":
			f.mt += dt
			z.vel = z.vel * exp(-dt * 8.0)
			fall(game, z, dt)
			z.yaw += angDiff(yawTo(dx, dz), z.yaw) * minf(1.0, dt * 8.0)
			z.anim.speed = 0.0
			z.anim.legYaw = 0.0
			z.anim.back = false
			z.navBest = INF
			f.sparkT -= dt
			if f.sparkT <= 0 and z.model.rod != null:
				f.sparkT = 0.06
				var a := SH.toWorld(z.model.rod, Vector3(0, -0.52, 0))
				SH.burst(game, a, {"shape": "star", "count": 1, "size": 0.06, "speed": 0.8, "life": 0.45, "colors": ["#FFF3B0", "#9FD8FF", "#FFC23A"]})
			if f.mt >= TWIRL:
				if f.cloud.state == "home":
					launchCloud(game, z)
				f.mode = "strafe"
			return true
		_:
			# strafe (casting happens from here)
			if p.alive and dist < JAB.range and z.cd <= 0 and absf(p.pos.y - z.pos.y) < 1.2:
				startJab(game, z)
				doJab(game, z, 0.0)
				return true
			if not f.sobbed and f.castT <= 0 and f.cloud.state == "home" and f.los and dist < 24.0 and z.spawnT <= 0 and p.alive:
				f.mode = "twirl"
				f.mt = 0.0
				f.sparkT = 0.0
				f.castT = F.castCd
				SH.audioPlay(game, "fc_twirl", {"pos": z.pos})
				return updateForecaster(game, z, 0.0)
			strafe(game, z, dt, dist, dx, dz)
			return true
	return true

# ------------------------------------------------------------------------------------------------ death
static func startDeath(game, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	var m = z.model
	f.mode = "dying"
	f.death = {"t": 0.0, "popped": false, "opened": false, "y0": z.pos.y, "x0": z.pos.x, "z0": z.pos.z, "sway": -1.0 if randf() < 0.5 else 1.0}
	m.disc.visible = false
	m.boltCore.visible = false
	m.boltGlow.visible = false
	unregisterCloud(game, z)
	var c = f.get("cloud")
	if c != null and c.state != "popped" and c.state != "gone":
		# EE §13: killed with the cloud intact -> the Stray Storm may spawn where the cloud is.
		var a := cloudWorldCenter(z)
		game.events.emit("zombie:forecaster_storm", {"pos": a, "z": z})
		c.state = "drift"
		c.t = 0.0
	if m.umbrella == null:
		m.umbrella = buildUmbrella(game)
	var u: Node3D = m.umbrella
	u.visible = true
	u.scale = Vector3.ONE * 0.01
	SH.addTo(z.group, u)
	SH.audioPlay(game, "fc_umbrella", {"pos": z.pos})
	SH.burst(game, Vector3(z.pos.x, z.pos.y + 1.3, z.pos.z), {"shape": "puff", "count": 5, "size": 0.12, "speed": 1.6})
	if z.get("animator") != null and z.animator.has_method("kick"):
		z.animator.kick(0.9)

static func updateDeath_(game, z: Dictionary, dt: float, t: float) -> void:
	var f: Dictionary = z.flags
	var m = z.get("model")
	var d = f.get("death")
	if d == null or m == null:
		return
	d.t = t
	# cloud keeps drifting / rainbow keeps fading
	tickCloud(game, z, dt)
	var u: Node3D = m.umbrella
	var dims = SH.rigDims(m.rig)
	var H: float = float(dims.height) if dims != null and dims.get("height") != null else 1.74
	# umbrella: springs out of his back (0-0.2), swings up over his head and snaps open (0.2-0.45)
	if t < 0.2:
		var k := easeOutBack(t / 0.2)
		u.position = Vector3(0, H * 0.72, 0.28)
		u.rotation = Vector3(-0.9, 0, 0)
		u.scale = Vector3(k * 0.4, k, k * 0.4)
	else:
		var k := smooth((t - 0.2) / 0.25)
		u.position = Vector3(0, lerp_(H * 0.72, H + 0.52, k), lerp_(0.28, 0.02, k))
		u.rotation = Vector3(lerp_(-0.9, 0.0, k), 0, 0)
		var open := 0.4 if t < 0.45 else 0.4 + 0.72 * easeOutBack((t - 0.45) / 0.22)
		u.scale = Vector3(open, 1.0, open)
		if t >= 0.45 and not d.opened:
			d.opened = true
			SH.audioPlay(game, "zmb_hit", {"pos": z.pos, "rate": 1.8, "vol": 0.5})
			SH.burst(game, Vector3(z.pos.x, z.pos.y + H + 0.9, z.pos.z), {"shape": "star", "count": 4, "speed": 1.6})
	# float up 3 m with a pendulum sway
	var rise := 0.0 if t < 0.45 else FLOAT_H * easeInOut((t - 0.45) / 1.6)
	z.pos = Vector3(d.x0 + sin(t * 1.3) * 0.25 * d.sway * clamp01(t - 0.45), d.y0 + rise, d.z0)
	var G0: Node3D = z.group
	G0.position = z.pos
	var sway := sin((t - 0.45) * 3.1) * 0.14 * clamp01((t - 0.45) * 2.0)
	G0.rotation_order = EULER_ORDER_YXZ
	G0.rotation = Vector3(0, z.yaw + t * 0.4 * d.sway, sway * d.sway)
	var s := SH.num(z, "scale", 1.0)
	if s == 0.0:
		s = 1.0
	G0.scale = Vector3(s, s, s)
	if z.get("animator") != null:
		z.animator.update(dt, {"speed": 0, "grounded": false, "hurt": 0})
	if t >= 2.1 and not d.popped:
		d.popped = true
		var a := Vector3(z.pos.x, z.pos.y + H * 0.6, z.pos.z)
		SH.burst(game, a, {"shape": "confetti", "count": 40, "speed": 5.5})
		SH.burst(game, a, {"shape": "star", "count": 8, "speed": 3.5})
		SH.burst(game, a, {"shape": "puff", "count": 8, "size": 0.2, "speed": 2})
		SH.burst(game, Vector3(z.pos.x, z.pos.y + H + 0.9, z.pos.z), {"shape": "confetti", "count": 16, "speed": 3, "colors": ["#E23B3B", "#FFF4DE"]})
		SH.audioPlay(game, "fc_umbrella", {"pos": a, "rate": 1.22})
		SH.audioPlay(game, "zmb_death_static", {"pos": a, "vol": 0.4})
		G0.visible = false

# ------------------------------------------------------------------------------------------------ module
static var grenadeHooked := {}

static func hookGrenades(game) -> void:
	var gid: int = game.get_instance_id()
	if grenadeHooked.has(gid):
		return
	grenadeHooked[gid] = true
	game.events.on("weapon:grenade", func(e):
		var pos = e.get("pos") if e is Dictionary else null
		if pos == null:
			return
		for z in game.zombies.alive:
			if z.type != "forecaster" or z.flags.get("cloud") == null:
				continue
			var a := cloudWorldCenter(z)
			var d := a.distance_to(pos)
			if d <= 5.0:
				var rnd: float = game.rounds.round if game.rounds != null else 1.0
				hitCloud(game, z, (300.0 + 60.0 * rnd) * (1.0 - d / 5.0 * 0.6), {"point": a}))

func hp(r = 1, _game = null) -> float:
	return SH.jsRound(F.hpMul * hpAt(maxf(1.0, float(r))) + F.hpAdd)

func speed(_r = 1, _game = null) -> float:
	return float(F.strafe)

func build(game, z: Dictionary) -> void:
	var m = acquire(game)
	if m == null:
		return
	resetModel(m)
	z.model = m
	z.group = m.group
	z.rig = m.rig
	z.animator = m.animator
	z.head = m.head
	z.headR = m.headR
	var dims = SH.rigDims(m.rig)
	z.height = float(dims.height) if dims != null and dims.get("height") != null else 1.8
	z.scale = 0.97 + randf() * 0.06
	var zt = ZT()
	z.hitZones = zt.humanoidHitZones({"rig": m.rig, "head": m.head, "headR": m.headR}) if zt != null and zt.has_method("humanoidHitZones") else null
	var f: Dictionary = z.flags
	f.mode = "strafe"
	f.mt = 0.0
	f.t = randf() * 10.0
	f.side = -1.0 if randf() < 0.5 else 1.0
	f.sideT = 1.5 + randf() * 1.5
	f.blockT = 0.0
	f.los = false
	f.losT = randf() * 0.25
	f.castT = 2.2 + randf() * 1.2
	f.humT = 2.0 + randf() * 4.0
	f.sobbed = false
	f.game = game
	f.rod = 0.38
	f.sparkT = 0.0
	f.tearT = 0.0
	f.jab = null
	f.rainbowT = null
	f.cloudFrame = -1
	var rnd := maxf(1.0, float(game.rounds.round) if game.rounds != null and game.rounds.get("round") else 1.0)
	f.cloud = {"state": "home", "hp": F.cloudHp[0] + F.cloudHp[1] * rnd, "pos": Vector3.ZERO, "t": 0.0, "dark": 0.0, "yaw": z.yaw, "punch": 0.0}
	if m.animator != null and "override" in m.animator:
		m.animator.override = makeOverride(z)
	if m.cloud != null:
		# detach the cloud into the world; it follows on a spring
		var piv: Node3D = m.cloud.pivot
		DAU.detach(piv)
		game.scene.add_child(piv)
		piv.visible = false
		f.cloud.pos = Vector3(z.pos.x, z.pos.y + m.cloud.restY, z.pos.z)
		f.cloudInit = false
	registerCloud(game, z)
	hookGrenades(game)

func release(game, z: Dictionary) -> void:
	var m = z.get("model")
	if m == null:
		return
	unregisterCloud(game, z)
	DAU.detach(m.group)
	resetModel(m)
	if pool.size() < 6:
		pool.append(m)
	z.model = null

func update(game, z: Dictionary, dt: float) -> bool:
	if not z.flags.get("cloudInit") and z.get("model") != null and z.model.cloud != null:
		z.flags.cloudInit = true
		z.flags.cloud.pos = hoverTarget(z)
	return updateForecaster(game, z, dt)

func updateEntry(game, z: Dictionary, dt: float) -> void:
	var f: Dictionary = z.flags
	if not f.get("cloudInit") and z.get("model") != null and z.model.cloud != null:
		f.cloudInit = true
		f.cloud.pos = hoverTarget(z)
	tickCloud(game, z, dt)

func onDamage(_game, z: Dictionary, amount: float, _info = null) -> float:
	return amount * F.sobMul if z.flags.get("sobbed") else amount

func onDeath(game, z: Dictionary, _info = null):
	var e = z.get("entry")
	if e is Dictionary and e.get("kind") == "screen" and e.get("phase") == "tele":
		unregisterCloud(game, z)
		if z.get("model") != null and z.model.cloud != null:
			z.model.cloud.pivot.visible = false
		return null
	startDeath(game, z)
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
	if m.umbrella == null:
		m.umbrella = buildUmbrella(game)
	var disc: MeshInstance3D = m.disc.duplicate()
	disc.visible = true
	var rb: MeshInstance3D = m.rainbow.duplicate()
	rb.visible = true
	boltMaterials()
	var bolt := MeshInstance3D.new()
	bolt.mesh = boltMesh(boltGeometry(Vector3(0, 3, 0), Vector3.ZERO))
	bolt.material_override = boltMat
	var glow := MeshInstance3D.new()
	glow.mesh = bolt.mesh
	glow.material_override = glowMat
	if m.cloud != null and m.cloud.shellG != null:
		m.cloud.shellG.visible = true
	out.append_array([m.umbrella.duplicate(), disc, rb, bolt, glow])
	return out

# ---- debug / EE helpers (popCloud(game, z) is the static function above, callable as z.def.popCloud(game, z))
func castNow(_game, z) -> bool:
	if z == null or z.get("dead"):
		return false
	z.flags.castT = 0.0
	z.flags.los = true
	return true

func cloudOf(z):
	var c = z.flags.get("cloud") if z != null and z.get("flags") != null else null
	if c == null:
		return null
	return {"state": c.state, "hp": c.hp, "pos": cloudWorldCenter(z) if z.get("model") != null and z.model.cloud != null else null}
