# SOCK HOPPER (`sock_hopper`, Hootie's "Sockettes") type module — GDD §8.2, §5.9, §7.5 (port of
# src/actors/types/sock_hopper.js). Owned by the zombies-specials agent. Contract: the TYPE MODULE CONTRACT in
# zombie_types.gd / src/actors/zombieTypes.js (this module keeps it: id, hp, speed, build, release, update -> true
# (moves + attacks itself), updateEntry, onDamage, onDeath/updateDeath, warmup, entry).
#
# Look: the sculpted z_sock (char_runtime.buildCharacter('z_sock'), custom 5-joint chain root -> s1 -> s2 -> s3 -> head
#   (+ jaw)), baked by the Blender character pipeline (the JS art=0 / missing-bake procedural placeholder sock is a
#   placeholder-art path: not ported, SPEC §0.2). Googly pupils jiggle on springs (k 120, d 12), the body
#   squash/stretches, bends into the hop, the jaw flaps.
# Behaviour:
#   - HOPS: one hop per 0.33 s (T.zombies.sock.speed 4.5 m/s, speed15 from round 15 -> ~1.5 m hops): 24 % of the cycle
#     on the floor (landing squash 0.7 -> anticipation crouch), the rest in the air (stretch 1.3). When music plays
#     (audio music beat()), the hop period snaps to the closest eighth/quarter note and the phase locks to the beat, so
#     every sock lands on the beat (quarter-note hoppers alternate by id). Without music, socks within 2.2 m phase-lock
#     to their neighbour: packs hop in unison. Packs also keep together (cohesion) until close to the player.
#   - LEAP-BITE (T.zombies.sock: leap 2.5 m, dmg 25, cd 0.9): 0.3 s crouch-squash telegraph (tremble, jaw clamps,
#     eyes widen, giggle), then a 0.36 s leap at the spot where the player stood at launch (0.45 m arc: sidestep it or
#     jump over it). A bite chomps, knocks back and bounces the sock off you.
#   - Close but cooling down: hops around you instead of stacking into you.
#   - Entry: always squeezes UNDER boards (1.0 s, no tearing; GDD §5.9 in Hullabaloo Hour, and a 0.7 m sock fits
#     under boards any time). Screen spawns: the manager's taffy emerge.
#   - Weak point: the eyes (hit zone 'eyes' = the top 40 % of the body). It is flagged head:true (gold hitmarker,
#     headshot kill points), and onDamage normalises the weapon's own head multiplier so the eyes deal exactly ×2.
#   - Tiny Tele lure: returns false and lets the manager walk it over (the animator hops, then it sits and sways).
# Death (onDeath -> 2.3 s): puffs up, "pfffft" (sock_deflate), zig-zags through the air like a let-go balloon
#   (shrinking, air jets), flops flat on the floor, a single button clinks away, then a small static puff.
# Sounds: sock_boing (takeoff, nearest socks only, global limiter), sock_giggle (random, spotted, telegraph, after a
#   bite), sock_leap, sock_deflate. Events: zombie:attack {z, dmg} on a bite (the manager emits the others).
# Debug: z.def.debugBite(game, z) forces a leap now.
#
# Port notes (GDScript):
#   - Module-level JS state (pool, buttons, sound budget, beat cache, tint set) = static vars (one set per process,
#     like the JS module scope). JS module functions = static funcs; the default-export object = this script's
#     instance (fields + methods with the JS names).
#   - Static meshes (the flying button) come from blender/runtime/specials.py
#     (res://assets/runtime/specials/*.glb); canvas textures are redrawn with DACanvas (SPEC §6); materials are
#     created here with the same factory calls
#     as the JS (game.mats.toon ...).
#   - Also hosts the port helpers the three special modules share (registerSpecialTint is shared in the JS too):
#     collision / material / scene-graph glue. See the "port glue" section. Spring = rig.gd's Rig.Spring.
#   - charOpt.gen pool invalidation and mergeAttachments (draw-call merging, A/B tooling) are engine plumbing: not
#     ported (SPEC §0.2); pupils stay separate meshes on their pivots.
#   - Renames: parameter `round` -> `r` (GDScript builtin).
extends RefCounted

const LAYER_ZOMBIES := 1                                   # Config.LAYERS.ZOMBIES
const G := 22.0                 # m/s² (same as the manager)
const C := 0.24                 # floor fraction of the hop cycle
const BASE_P := 0.33            # s per hop (GDD)
const CROUCH := 0.3             # leap telegraph
const LEAP_T := 0.36            # leap flight
const LEAP_H := 0.45            # leap arc
const HEAR := 15.0
const DEATH := 2.3
const ASSETS := "res://assets/runtime/specials/"
const CHAR_RUNTIME := "res://scripts/art/char_runtime.gd"
const CANVAS := "res://scripts/gfx/canvas2d.gd"

static var S: Dictionary = Config.T.zombies.sock
static var R: Dictionary = Config.T.rounds

# ------------------------------------------------------------------------------------------------ module fields
var id := "sock_hopper"
var height := 0.75
var radius := 0.26
var dmg = S.dmg
var range := 1.0
var windup := CROUCH
var cd = S.cd
var spawnMode := "both"

# ------------------------------------------------------------------------------------------------ math helpers
static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func smooth(x: float) -> float:
	x = clamp01(x)
	return x * x * (3.0 - 2.0 * x)

static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func easeOutBack(x: float) -> float:
	x = clamp01(x)
	var c := 1.7
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

static func easeOutCubic(x: float) -> float:
	return 1.0 - pow(1.0 - clamp01(x), 3.0)

static func angDiff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func yawTo(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

static func wrapHalf(x: float) -> float:
	return x - jsRound(x)

# Math.round (JS rounds .5 toward +inf)
static func jsRound(x: float) -> float:
	return floorf(x + 0.5)

static func hpAt(r: float) -> float:
	if r <= 9:
		return R.hpEarlyBase + R.hpEarlyStep * (maxf(1.0, r) - 1.0)
	return minf(R.hpCap, jsRound((R.hpEarlyBase + R.hpEarlyStep * 8) * pow(R.hpMul, r - 9.0)))

static func num(d, key: String, def := 0.0) -> float:
	if d == null:
		return def
	var v = d.get(key) if (d is Dictionary or d is Object) else null
	if v == null or not (v is float or v is int or v is bool):
		return def
	return float(v)

# ------------------------------------------------------------------------------------------------ port glue
# (shared with forecaster.gd / big_shot.gd: `const SH = preload(".../sock_hopper.gd")`)

# level.col.moveCircle(z.pos, delta, ...) mutates pos in JS: collision.gd returns the moved feet in "pos", stored
# back into z.pos here; z is the owner (collision.gd remembers "grounded" per owner, the JS per pos object).
# Returns the (reused) result Dictionary ({onGround, hitWall, groundY, hitCeiling, normal, pos}): read it at once.
static func moveZ(g, z: Dictionary, delta: Vector3, rad: float, h: float, stepUp := 0.45) -> Dictionary:
	var col = colOf(g)
	if col == null:
		z.pos = z.pos + delta
		return {"onGround": false, "hitWall": false, "groundY": -INF, "hitCeiling": false}
	var r = col.moveCircle(z.pos, delta, rad, h, stepUp, null, z)
	if r is Dictionary:
		if r.has("pos"):
			z.pos = r.pos
		return r
	if r is Vector3:
		z.pos = r
	return {"onGround": false, "hitWall": false, "groundY": -INF, "hitCeiling": false}

static func colOf(g):
	if g == null or g.level == null:
		return null
	return g.level.get("col")

static func floorAt(g, x: float, zz: float, yFrom: float) -> float:
	var col = colOf(g)
	if col == null:
		return -INF
	var fy = col.floorAt(x, zz, yFrom)
	return float(fy) if fy != null else -INF

static func lineOfSight(g, a: Vector3, b: Vector3) -> bool:
	var col = colOf(g)
	if col == null or not col.has_method("lineOfSight"):
		return true
	return bool(col.lineOfSight(a, b))

# JS nav.dir(x, z, out) -> out (unit XZ toward the goal, 0 if unreachable); nav.gd returns the Vector3.
static func navDir(g, x: float, zz: float) -> Vector3:
	if g == null or g.nav == null:
		return Vector3.ZERO
	var r = g.nav.dir(x, zz)
	return r if r is Vector3 else Vector3.ZERO

static func audioPlay(g, cue: String, opts := {}):
	if g == null or g.audio == null:
		return null
	return g.audio.play(cue, opts)

static func burst(g, pos: Vector3, opts: Dictionary) -> void:
	if g != null and g.fx != null:
		g.fx.burst(pos, opts)

static func setLayers(n: Node) -> void:
	DAU.setLayerRecursive(n, Config.LAYERS.ZOMBIES)

static func noShadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func setCast(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func isSkinned(n) -> bool:
	return n is MeshInstance3D and ((n as MeshInstance3D).skin != null or not (n as MeshInstance3D).skeleton.is_empty())

# game.scene (render.scene, the 3D world root), or the game node while render is missing (like zombies.gd).
static func sceneRoot(game) -> Node:
	if game == null:
		return null
	return game.scene if game.scene != null else game

# three's parent.add(child): re-parents.
static func addTo(parent: Node, child: Node) -> void:
	if parent == null or child == null:
		return
	if child.get_parent() == parent:
		return
	DAU.detach(child)
	parent.add_child(child)

# Object3D.getObjectByName (also the Godot-sanitised form of names with ':').
static func byName(root: Node, nm: String) -> Node:
	if root == null:
		return null
	var n := DAU.byName(root, nm)
	if n == null and nm.contains(":"):
		n = DAU.byName(root, nm.replace(":", "_"))
	return n

static func worldPos(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else n.transform.origin

# obj.localToWorld(v)
static func toWorld(n: Node3D, v: Vector3) -> Vector3:
	return n.to_global(v) if n.is_inside_tree() else n.transform * v

static func camPos(g) -> Vector3:
	if g == null or g.camera == null:
		return Vector3.ZERO
	return g.camera.global_position if g.camera.is_inside_tree() else g.camera.position

static func camQuat(g) -> Quaternion:
	if g == null or g.camera == null:
		return Quaternion.IDENTITY
	var b: Basis = g.camera.global_transform.basis if g.camera.is_inside_tree() else g.camera.transform.basis
	return b.get_rotation_quaternion()

# ---- glTF runtime assets (blender/runtime/specials.py)
static var _scenes := {}

static func loadScene(nm: String) -> Node3D:
	var path := ASSETS + nm + ".glb"
	var ps = _scenes.get(path)
	if ps == null:
		if not ResourceLoader.exists(path):
			push_warning("[specials] missing runtime asset %s (run blender/build_all.py --only runtime)" % path)
			return null
		ps = load(path)
		_scenes[path] = ps
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	# JS parts are rotated with three's default 'XYZ' Euler order.
	DAU.traverse(n, func(o):
		if o is Node3D:
			(o as Node3D).rotation_order = EULER_ORDER_XYZ)
	return n

# the Mesh resource of the node named nm inside the asset scene (shared geometry, like the JS module-level geometries)
static var _meshes := {}
static func loadMesh(asset: String, nm: String) -> Mesh:
	var key := asset + "/" + nm
	if _meshes.has(key):
		return _meshes[key]
	var root := loadScene(asset)
	var mesh: Mesh = null
	if root != null:
		var n := byName(root, nm)
		if n == null:
			DAU.traverse(root, func(o):
				if mesh == null and o is MeshInstance3D and String(o.name).begins_with(nm):
					mesh = o.mesh)
		elif n is MeshInstance3D:
			mesh = n.mesh
		root.free()
	_meshes[key] = mesh
	return mesh

# the albedo texture of a node's imported material (the Blender asset carries the canvas textures too)
static func glbTex(asset: String, nm: String) -> Texture2D:
	var root := loadScene(asset)
	if root == null:
		return null
	var t: Texture2D = null
	var n := byName(root, nm)
	if n is MeshInstance3D and n.mesh != null and n.mesh.get_surface_count() > 0:
		var m: Material = n.mesh.surface_get_material(0)
		if m is BaseMaterial3D:
			t = (m as BaseMaterial3D).albedo_texture
	root.free()
	return t

# document.createElement('canvas') -> DACanvas (scripts/gfx/canvas2d.gd, SPEC §6); null while it is missing.
static var _canvases: Array = []      # keeps the canvases (and their textures) alive
static func newCanvas(w: int, h: int):
	if not ResourceLoader.exists(CANVAS):
		return null
	var C = load(CANVAS)
	if C == null or not C.can_instantiate():
		return null
	var c = C.new(w, h)
	_canvases.append(c)
	return c

# a mesh whose surfaces are the first surfaces of `meshes` (three multi-material groups on one geometry)
static func joinMeshes(meshes: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	for me in meshes:
		if me != null and me.get_surface_count() > 0:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, me.surface_get_arrays(0))
	return am

# game.mats.toon(color, opts) (null while materials.gd is missing)
static func toon(game, color: String, opts := {}):
	var M = game.mats if game != null else null
	if M == null or not M.has_method("toon"):
		return null
	return M.toon(color, opts)

# ---- materials
# new THREE.MeshBasicMaterial({...}) with a LINEAR colour (new THREE.Color(r, g, b) / Color(hex).multiplyScalar(k)):
# a private copy of game.mats.basic(...) (a DAMaterial, cached there: the JS created one per model and mutates it),
# or an unlit StandardMaterial3D while materials.gd is missing.
# opts: map, transparent, opacity, additive, depthWrite, side ('double'), fog, vertexColors, renderOrder
static func basic(game, lin: Color, opts := {}) -> Material:
	var M = game.mats if game != null else null
	var dm = null
	if M != null and M.has_method("basic"):
		var o := {}
		for k in ["map", "transparent", "opacity", "depthWrite", "side", "fog", "vertexColors"]:
			if opts.has(k):
				o[k] = opts[k]
		if opts.get("additive", false):
			o.blending = 2          # THREE.AdditiveBlending
		var base = M.basic("#ffffff", o)
		if base != null:
			dm = base.clone()
	if dm != null:
		dm.color = Color(lin.r, lin.g, lin.b).linear_to_srgb()
		if opts.has("renderOrder"):
			dm.render_priority = clampi(int(opts.renderOrder), -128, 127)
			if dm.twin != null:
				dm.twin.render_priority = dm.render_priority
		return dm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var a: float = opts.get("opacity", 1.0)
	var c := Color(lin.r, lin.g, lin.b).linear_to_srgb()
	m.albedo_color = Color(c.r, c.g, c.b, a)
	if opts.get("map") != null:
		m.albedo_texture = opts.map
		# three CanvasTexture flipY: the three uv (Godot's uv on these meshes) samples the canvas at (u, 1 - v)
		m.uv1_scale = Vector3(1, -1, 1)
		m.uv1_offset = Vector3(0, 1, 0)
	if opts.get("transparent", false) or opts.get("additive", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if opts.get("additive", false):
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if opts.get("depthWrite", true) == false:
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if opts.get("side", "front") == "double":
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if opts.get("fog", true) == false:
		m.disable_fog = true
	if opts.get("vertexColors", false):
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = false
	if opts.has("renderOrder"):
		m.render_priority = clampi(int(opts.renderOrder), -128, 127)
	return m

static func hexLin(hex: String, k := 1.0) -> Color:
	var c := Color(hex).srgb_to_linear()
	return Color(c.r * k, c.g * k, c.b * k)

# THREE material .color / .emissive (LINEAR colours) and .opacity of a basic / toon / character material:
# DAMaterial facades (materials.gd: color / emissive are sRGB Colors there), else the zombie registry's accessors
# (zombie_types.gd: BaseMaterial3D albedo/emission, ShaderMaterial Color uniforms sRGB, vec3 linear).
static func setColorLin(mat: Material, lin: Color) -> void:
	if mat == null:
		return
	if mat is DAMaterial:
		var a: float = (mat as DAMaterial).color.a
		var c := Color(lin.r, lin.g, lin.b).linear_to_srgb()
		(mat as DAMaterial).color = Color(c.r, c.g, c.b, a)
	else:
		ZombieTypes.matSetColor(mat, lin)

static func getColorLin(mat: Material) -> Color:
	if mat is DAMaterial:
		return (mat as DAMaterial).color.srgb_to_linear()
	var c = ZombieTypes.matGetColor(mat) if mat != null else null
	return c if c is Color else Color(1, 1, 1)

static func setOpacity(mat: Material, a: float) -> void:
	if mat == null:
		return
	if mat is DAMaterial:
		(mat as DAMaterial).opacity = a
	elif mat is BaseMaterial3D:
		var c: Color = (mat as BaseMaterial3D).albedo_color
		c.a = a
		(mat as BaseMaterial3D).albedo_color = c
	elif mat is ShaderMaterial:
		var p := _param(mat, ["uOpacity", "opacity", "alpha"])
		if p != "":
			mat.set_shader_parameter(p, a)

static func getOpacity(mat: Material) -> float:
	if mat is DAMaterial:
		return (mat as DAMaterial).opacity
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color.a
	if mat is ShaderMaterial:
		var p := _param(mat, ["uOpacity", "opacity", "alpha"])
		if p != "":
			var v = mat.get_shader_parameter(p)
			return float(v) if v != null else 1.0
	return 1.0

# material.emissive (linear) — toon materials
static func setEmissiveLin(mat: Material, lin: Color) -> void:
	if mat == null:
		return
	if mat is DAMaterial:
		(mat as DAMaterial).emissive = Color(lin.r, lin.g, lin.b).linear_to_srgb()
		return
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).emission_enabled = true
	ZombieTypes.matSetEmissive(mat, lin)

static func getEmissiveLin(mat: Material):
	if mat is DAMaterial:
		return (mat as DAMaterial).emissive.srgb_to_linear()
	return ZombieTypes.matGetEmissive(mat) if mat != null else null

static var _paramCache := {}
static func _param(mat: ShaderMaterial, names: Array) -> String:
	if mat.shader == null:
		return ""
	var key := str(mat.shader.get_instance_id()) + ":" + ",".join(names)
	if _paramCache.has(key):
		return _paramCache[key]
	var found := ""
	var list: Array = mat.shader.get_shader_uniform_list()
	for nm in names:
		for u in list:
			if u.name == nm:
				found = nm
				break
		if found != "":
			break
	_paramCache[key] = found
	return found

# the material a MeshInstance3D draws with (override, surface override, mesh surface)
static func meshMat(mi: MeshInstance3D) -> Material:
	if mi == null:
		return null
	if mi.material_override != null:
		return mi.material_override
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return null
	var m := mi.get_surface_override_material(0)
	return m if m != null else mi.mesh.surface_get_material(0)

# a per-instance copy of a MeshInstance3D's material (JS materials created per build; Godot shares imported ones)
static func ownMat(mi: MeshInstance3D) -> Material:
	var m := meshMat(mi)
	if m == null:
		return null
	var own := m.duplicate()
	mi.material_override = own
	return own

# ---- character runtime (chars-godot: scripts/art/char_runtime.gd)
static func charRuntime():
	if not ResourceLoader.exists(CHAR_RUNTIME):
		return null
	var s = load(CHAR_RUNTIME)
	return s

static func charBaked(game, charId: String) -> bool:
	if game.params.get("art") == 0:
		return false
	if charRuntime() == null:
		return false
	return ResourceLoader.exists("res://assets/chars/%s.glb" % charId)

# buildCharacter(defOrId, opts) -> { group, rig, animator, skinnedMesh, slots, face, parts, def, header }
static func buildChar(game, charId: String, opts: Dictionary):
	var CR = charRuntime()
	if CR == null:
		return null
	var o := {"envMap": game.mats.get("envMap") if game.mats != null else null,
		"globals": game.mats.get("uniforms") if game.mats != null else null, "layer": Config.LAYERS.ZOMBIES}
	o.merge(opts, true)
	var c = CR.buildCharacter(charId, o)
	if c is Object and not (c is Dictionary) and c.get("group") != null:
		# a class instance: read the JS fields into a Dictionary view
		var d := {}
		for k in ["group", "rig", "animator", "skinnedMesh", "slots", "face", "parts", "def", "header"]:
			d[k] = c.get(k)
		return d
	return c

# rig.joints / dims readers (rig may be a Dictionary or an object)
static func rigJoints(rig) -> Dictionary:
	if rig == null:
		return {}
	var j = rig.get("joints")
	return j if j is Dictionary else {}

static func rigRoot(rig) -> Node3D:
	return rig.get("root") if rig != null else null

static func rigDims(rig):
	return rig.get("dims") if rig != null else null

# ------------------------------------------------------------------------------------------------ shared helpers
# Music beat ({ bpm, beat }) while a real music state plays, cached per frame.
static var beatFrame := -1
static var beatVal = null

static func musicBeat(g):
	if beatFrame == int(g.time.frame):
		return beatVal
	beatFrame = int(g.time.frame)
	beatVal = null
	var a = g.audio
	if a == null:
		return null
	var st = null
	var b = null
	if a.has_method("musicBeat"):
		st = "x"
		b = a.musicBeat()
	else:
		var m = a.get("_music")
		if m == null:
			return null
		st = m.get("state")
		if st != null and st != "" and st != "ambient" and st != "silence" and st != "title":
			if m is Object and m.has_method("beat"):
				b = m.beat()
			elif m is Dictionary and m.get("beat") is Callable:
				b = m.beat.call()
		else:
			return null
	if b is Dictionary and num(b, "bpm") > 0.0 and b.get("beat") != null and is_finite(float(b.beat)):
		beatVal = b
	return beatVal

# Global sound limiter (the audio engine has a voice budget; a pack of 10 socks would boing 30 times a second).
static var budget := {"boing": 0.0, "t": 0.0, "giggle": 0.0}

static func refill(g) -> void:
	var now: float = g.time.now
	if now - budget.t > 0.11:
		budget.t = now
		budget.boing = minf(2.0, budget.boing + 1.0)
		budget.giggle = minf(1.0, budget.giggle + 0.05)

# The weapon's own head multiplier (weapons pre-multiply it into the amount for head hits).
static func weaponHeadMul(g, weaponId) -> float:
	if weaponId == null or weaponId == "":
		return 1.0
	var w = g.weapons
	var d = null
	if w != null:
		var defs = w.get("defs")
		if defs is Dictionary:
			d = defs.get(weaponId)
		if d == null and w.has_method("def"):
			d = w.def(weaponId)
	var h := num(d, "head", 0.0) if d != null else 0.0
	return h if h > 0.0 else 1.0

static func losTo(g, z: Dictionary, p) -> bool:
	var a := Vector3(z.pos.x, z.pos.y + 0.5, z.pos.z)
	var b := Vector3(p.pos.x, p.pos.y + 1.0, p.pos.z)
	return lineOfSight(g, a, b)

# ------------------------------------------------------------------------------------------------ model
static var pool: Array = []
static var buttonMesh: Mesh = null
static var buttonMats = null
static var buttons: Array = []            # flying buttons { mesh, vel, spin, t, floor, bounces }
static var bakedWarned := false

static func hasBaked(game) -> bool:
	return charBaked(game, "z_sock")

static func buildBakedModel(game):
	var c = buildChar(game, "z_sock", {"animator": false})
	if c == null or c.get("group") == null:
		return null
	var J := rigJoints(c.rig)
	var eyes := {}
	var group: Node3D = c.group
	DAU.traverse(group, func(o):
		var ud := DAU.ud(o) if o.has_meta("userData") else {}
		if ud.get("googlyPupil") and not (o is MeshInstance3D):
			ud.noMerge = true
			eyes[ud.googlyPupil] = {"pivot": o, "base": o.position}
		if o is MeshInstance3D:
			setCast(o, isSkinned(o)))
	var whites: Array = []
	DAU.traverse(group, func(o):
		var ud := DAU.ud(o) if o.has_meta("userData") else {}
		if String(o.name).begins_with("googly") and not (o is MeshInstance3D) and not ud.get("googlyPupil"):
			whites.append(o))
	for side in eyes:
		(eyes[side].pivot as Node3D).rotation_order = EULER_ORDER_XYZ
	# mergeAttachments (draw-call merging) is engine plumbing: the pupils keep their own meshes on the pivots.
	var bodies: Array = []
	DAU.traverse(group, func(o):
		if isSkinned(o):
			if o == c.get("skinnedMesh"):
				bodies.append(o)
			else:
				noShadow(o))
	if c.get("skinnedMesh") != null:
		registerSpecialTint(game, meshMat(c.skinnedMesh))
	return finishModel(game, group, c.rig, J, eyes, whites, bodies, true)

static func finishModel(game, group: Node3D, rig, J: Dictionary, eyes: Dictionary, whites: Array, bodies: Array, baked: bool) -> Dictionary:
	var head := DAU.node3d("part_headCenter")
	head.position = Vector3(0, 0.06, -0.07)
	(J.head as Node3D).add_child(head)
	group.name = "zombie_sock_hopper"
	setLayers(group)
	return {"group": group, "rig": rig, "J": J, "eyes": eyes, "whites": whites, "bodies": bodies, "head": head,
		"headR": 0.17, "baked": baked, "cards": [], "def": {"id": "sock_hopper"}, "variant": "z_sock" if baked else "placeholder"}

static func acquire(game):
	var want := hasBaked(game)
	for i in range(pool.size() - 1, -1, -1):
		if pool[i].baked == want:
			var m = pool[i]
			pool.remove_at(i)
			return m
	if want:
		var m = buildBakedModel(game)
		if m != null:
			return m
		if not bakedWarned:
			bakedWarned = true
			push_warning("[sock_hopper] baked sock failed")
	# the art=0 / no-bake procedural placeholder is not ported (SPEC §0.2): without baked art the type cannot
	# build and the manager spawns a Tuned-In instead (like zombie_types.gd)
	return null

static func resetPose(m: Dictionary) -> void:
	var g: Node3D = m.group
	g.visible = true
	g.position = Vector3.ZERO
	g.rotation = Vector3.ZERO
	g.scale = Vector3.ONE
	var root := rigRoot(m.rig)
	root.position = Vector3.ZERO
	root.rotation = Vector3.ZERO
	root.scale = Vector3.ONE
	for j in m.J.values():
		if j != null:
			j.rotation = Vector3.ZERO
			j.scale = Vector3.ONE
	for e in m.eyes.values():
		e.pivot.position = e.base
		e.pivot.rotation = Vector3.ZERO
		e.pivot.scale = Vector3.ONE
	for w in m.whites:
		w.scale = Vector3.ONE

# ------------------------------------------------------------------------------------------------ buttons (death)
# Geometry: specials/sock_button.glb (CylinderGeometry(0.03, 0.03, 0.01, 18): side / caps meshes, joined back into
# one two-surface mesh); the 64x64 cap canvas is drawn with DACanvas (the Blender asset's copy if it is missing).
static var buttonTex = null

static func buttonAssets(game) -> void:
	if buttonMesh != null:
		return
	var c = newCanvas(64, 64)
	if c != null:
		var x = c.getContext("2d")
		x.fillStyle = "#E8A92E"
		x.fillRect(0, 0, 64, 64)
		x.strokeStyle = "#B97A14"
		x.lineWidth = 6
		x.beginPath()
		x.arc(32, 32, 24, 0, PI * 2)
		x.stroke()
		x.fillStyle = "#6B4A12"
		for dd in [[-7, -7], [7, -7], [-7, 7], [7, 7]]:
			x.beginPath()
			x.arc(32 + dd[0], 32 + dd[1], 4, 0, PI * 2)
			x.fill()
		buttonTex = c.texture
	else:
		buttonTex = glbTex("sock_button", "sock_button_cap")
	var side = toon(game, "#D99A22", {"rough": 0.35, "keepColor": true, "rim": 0.4})
	var cap = toon(game, "#ffffff", {"rough": 0.35, "keepColor": true, "map": buttonTex, "rim": 0.3, "name": "sockButtonCap"})
	buttonMesh = joinMeshes([loadMesh("sock_button", "sock_button_side"), loadMesh("sock_button", "sock_button_cap")])
	buttonMats = [side, cap, cap]

static func makeButtonMesh() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.rotation_order = EULER_ORDER_XYZ
	mesh.mesh = buttonMesh
	if buttonMesh != null and buttonMats != null:
		for sfc in mini(buttonMesh.get_surface_count(), 2):
			mesh.set_surface_override_material(sfc, buttonMats[sfc])
	return mesh

static func popButton(game, pos: Vector3, dir: Vector3) -> void:
	buttonAssets(game)
	var b = null
	for q in buttons:
		if not q.live:
			b = q
			break
	if b == null:
		if buttons.size() >= 6:
			b = buttons[0]
		else:
			var mesh := makeButtonMesh()
			mesh.name = "sock_button"
			noShadow(mesh)
			mesh.layers = 1 << Config.LAYERS.ZOMBIES
			b = {"mesh": mesh, "vel": Vector3.ZERO, "spin": Vector3.ZERO, "live": false}
			buttons.append(b)
	b.live = true
	b.t = 0.0
	b.bounces = 0
	b.mesh.position = pos
	b.mesh.scale = Vector3.ONE
	b.vel = Vector3(dir.x * 1.6 + (randf() - 0.5) * 0.8, 2.6 + randf(), dir.z * 1.6 + (randf() - 0.5) * 0.8)
	b.spin = Vector3(8 + randf() * 8, randf() * 4, 6 + randf() * 6)
	var fy := floorAt(game, pos.x, pos.z, pos.y + 0.3)
	b.floor = (fy if fy > -INF else pos.y) + 0.005
	addTo(sceneRoot(game), b.mesh)

# PLEASE STAND BY look for the specials' own materials (zombie_types' setZombieTint only knows the materials it built):
# the same test-card grey (colour ×0.5 + a lilac emissive lift) while zombies are frozen by the power-up. Shared by the
# three special modules (forecaster.gd / big_shot.gd preload this script).
static var tintMats: Array = []
static var tintGames := {}
static var tintOn := false

static func registerSpecialTint(game, mat: Material) -> void:
	if mat == null or tintMats.has(mat):
		return
	tintMats.append(mat)
	mat.set_meta("zsBase", {"color": getColorLin(mat), "emissive": getEmissiveLin(mat)})
	if tintOn:
		applySpecialTint(mat, true)
	var gid: int = game.get_instance_id()
	if tintGames.has(gid):
		return
	tintGames[gid] = true
	addPrePass(game, func():
		var pu = game.powerups
		var Zs = game.zombies
		var on := false
		if Zs != null and Zs.get("frozen") and pu != null:
			if pu.has_method("isActive"):
				on = bool(pu.isActive("please_stand_by"))
			else:
				var act = pu.get("active")
				on = act is Dictionary and num(act, "please_stand_by") > 0.0
		if on == tintOn:
			return
		tintOn = on
		for m in tintMats:
			applySpecialTint(m, on))

static func applySpecialTint(mat: Material, on: bool) -> void:
	if not mat.has_meta("zsBase"):
		return
	var b: Dictionary = mat.get_meta("zsBase")
	setColorLin(mat, b.color)
	if b.emissive != null:
		setEmissiveLin(mat, b.emissive)
	if on:
		var c: Color = b.color
		setColorLin(mat, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5))
		if b.emissive != null:
			setEmissiveLin(mat, Color(0.2, 0.2, 0.25))

# render.addPrePass(fn) (runs before the main render every frame); without it, the scene tree's process_frame.
static func addPrePass(game, fn: Callable) -> void:
	var wrap := func(_renderer = null): fn.call()
	if game.render != null and game.render.has_method("addPrePass"):
		game.render.addPrePass(wrap)
	elif game.is_inside_tree():
		game.get_tree().process_frame.connect(wrap)

# Buttons outlive their sock: one per-game ticker (render pre-pass, world dt) moves them; cleared on a new game.
static var tickers := {}

static func ensureTicker(game) -> void:
	var gid: int = game.get_instance_id()
	if tickers.has(gid):
		return
	tickers[gid] = true
	addPrePass(game, func(): updateButtons(game, float(game.time.dt)))
	game.events.on("game:start", func(_e = null):
		for b in buttons:
			b.live = false
			DAU.detach(b.mesh))

static func updateButtons(game, dt: float) -> void:
	if not (dt > 0.0):
		return
	for b in buttons:
		if not b.live:
			continue
		b.t += dt
		var m: MeshInstance3D = b.mesh
		if b.bounces < 3:
			b.vel.y -= G * dt
			m.position += b.vel * dt
			m.rotation.x += b.spin.x * dt
			m.rotation.y += b.spin.y * dt
			m.rotation.z += b.spin.z * dt
			if m.position.y < b.floor and b.vel.y < 0:
				m.position.y = b.floor
				b.bounces += 1
				b.vel.y *= -0.42
				b.vel.x *= 0.6
				b.vel.z *= 0.6
				b.spin *= 0.5
				audioPlay(game, "grenade_bounce", {"pos": m.position, "rate": 1.9 + b.bounces * 0.25, "vol": 0.45 / b.bounces})
				if b.bounces >= 3:
					m.rotation = Vector3(0, m.rotation.y, 0)
					m.position.y = b.floor + 0.005
		if b.t > 3.2:
			m.scale = Vector3.ONE * maxf(0.001, 1.0 - (b.t - 3.2) / 0.3)
			if b.t > 3.5:
				b.live = false
				DAU.detach(m)

# ------------------------------------------------------------------------------------------------ animator
# The manager calls animator.update(dt, z.anim) every (LOD) frame and animator.kick(amount) on hits. The pose reads
# the hop state the behaviour keeps in z.flags; when the behaviour does not run (approach, stun, lure), it advances
# a hop cycle from z.anim.speed itself.
class SockAnimator extends RefCounted:
	var z: Dictionary
	var mod: Script                # this module's script (inner classes cannot call the outer static funcs)
	var override = null            # (the manager's resetModelPose clears animator.override)

	func _init(z_: Dictionary, mod_: Script) -> void:
		z = z_
		mod = mod_

	func update(dt: float, st = null) -> void:
		mod.poseSock(z, z.flags, dt, st if st is Dictionary else {})

	func kick(amount := 1.0) -> void:
		var f: Dictionary = z.flags
		f.sq.kick(-3.2 * amount)
		f.bend.kick(3.0 * amount)
		for e in f.eyeS:
			e.y.kick(-7.0 * amount)
			e.x.kick((randf() - 0.5) * 9.0 * amount)

static func makeAnimator(z: Dictionary, mod: Script):
	return SockAnimator.new(z, mod)

static func poseSock(z: Dictionary, f: Dictionary, dt: float, st: Dictionary) -> void:
	var m = z.get("model")
	if m == null:
		return
	var J: Dictionary = m.J
	var root := rigRoot(m.rig)
	f.t += dt
	var u: float = f.ph
	var arc := 0.0
	var sy := 1.0
	var lean := 0.0
	var jaw := 0.06
	var inAir := false
	var speed := num(st, "speed")
	if not f.driven:
		# Not driven by update(): hop from the manager's movement speed (approach, lure, emerge...) or idle bounce.
		if speed > 0.3:
			f.ph = fmod(f.ph + dt / BASE_P, 1.0)
			u = f.ph
		else:
			u = -1.0
	f.driven = false
	var H: float = f.H if num(f, "H") != 0.0 else 0.26
	if f.mode == "crouch":
		var k := clamp01(f.mt / CROUCH)
		sy = lerp_(0.9, 0.58, easeOutCubic(k))
		lean = 0.28 * k
		jaw = 0.0
		root.position.x = sin(f.t * 70.0) * 0.012 * k
	elif f.mode == "leap":
		var k := clamp01(f.mt / LEAP_T)
		arc = f.leapArc
		sy = lerp_(0.6, 1.38, easeOutCubic(k / 0.15)) if k < 0.15 else lerp_(1.38, 1.12, (k - 0.15) / 0.85)
		lean = -0.42
		jaw = maxf(0.0, 0.9 - f.bitT * 9.0) if f.bit else 0.95
		inAir = true
	elif f.mode == "recover":
		var k := clamp01(f.mt / 0.26)
		sy = lerp_(0.62, 1.0, easeOutBack(k))
		lean = 0.1 * (1.0 - k)
		jaw = 0.1
	elif u >= 0.0:
		if u < C:
			var k := u / C
			sy = lerp_(0.7, 1.03, easeOutBack(k / 0.45)) if k < 0.45 else lerp_(1.03, 0.86, smooth((k - 0.45) / 0.55))
			lean = 0.08 * (1.0 - k)
		else:
			var s := (u - C) / (1.0 - C)
			arc = H * 4.0 * s * (1.0 - s)
			if s < 0.12:
				sy = lerp_(0.86, 1.3, easeOutCubic(s / 0.12))
			elif s < 0.55:
				sy = lerp_(1.3, 1.04, smooth((s - 0.12) / 0.43))
			else:
				sy = lerp_(1.04, 1.16, pow((s - 0.55) / 0.45, 2.0))
			lean = -0.13 * minf(1.0, speed / 3.0 + 0.4)
			jaw = 0.06 + 0.22 * sin(s * PI)
			inAir = true
	else:
		# Idle: a slow breathing bob and a curious sway.
		sy = 1.0 + sin(f.t * 3.1 + z.id) * 0.03
		jaw = 0.05 + maxf(0.0, sin(f.t * 4.3 + z.id)) * 0.1
	var down: bool = bool(st.get("down", false))
	if down:
		sy = 0.86 + sin(f.t * 2.4) * 0.03
		lean = 0.12
		jaw = 0.3
	if num(st, "climb") > 0.0:
		lean = -0.2 * sin(f.t * 12.0)
		jaw = 0.4
	# Springs: squash (hits/landings), bend (whip), googly pupils.
	var sq: float = f.sq.update(dt, 0.0)
	var bend: float = f.bend.update(dt, lean)
	sy *= 1.0 + sq
	sy = maxf(0.4, sy)
	var sx := 1.0 / sqrt(sy)
	if f.mode != "crouch":
		root.position.x = 0.0
	root.position.y = arc
	root.scale = Vector3(sx, sy, sx)
	var turn := clampf(num(st, "turn"), -6.0, 6.0)
	var hurt := num(st, "hurt")
	var wob := sin(f.t * 5.3 + z.id * 1.7) * 0.05
	for n in ["s1", "s2", "s3"]:
		J[n].rotation.x = bend * 0.34 + hurt * 0.1
		J[n].rotation.z = -turn * 0.018 + wob * 0.5
	J.head.rotation.x = -bend * 0.55 + (-0.08 if inAir else 0.04) - hurt * 0.2
	J.head.rotation.z = wob + (sin(f.t * 2.4) * 0.2 if down else 0.0)
	J.jaw.rotation.x = jaw
	# Googly eyes: gravity pulls the pupils down, flight floats them, turns fling them sideways.
	var k := 0.024
	var i := 0
	for side in ["L", "R"]:
		var e = m.eyes.get(side)
		var s = f.eyeS[i]
		i += 1
		if e == null:
			continue
		var ty := 0.25 if inAir else -0.55
		var tx := clampf(-turn * 0.12, -0.8, 0.8) + (cos(f.t * 3.0 + i) * 0.6 if down else 0.0)
		var px: float = s.x.update(dt, tx)
		var py: float = s.y.update(dt, sin(f.t * 3.0 + i) * 0.6 if down else ty)
		var l := sqrt(px * px + py * py)
		if l > 1.0:
			px /= l
			py /= l
			s.x.x = px
			s.y.x = py
			s.x.v *= -0.4
			s.y.v *= -0.4
		var base: Vector3 = e.base
		e.pivot.position = Vector3(base.x + px * k, base.y + py * k, base.z)
		var ps := 0.7 if f.mode == "crouch" else 1.0
		e.pivot.scale = Vector3(ps, ps, 1.0)
	var ws := 1.14 if f.mode == "crouch" else 1.0
	for w in m.whites:
		w.scale = Vector3.ONE * ws

# ------------------------------------------------------------------------------------------------ behaviour
static func beginLeap(g, z: Dictionary, f: Dictionary) -> void:
	var p = g.player
	f.mode = "leap"
	f.mt = 0.0
	f.bit = false
	f.bitT = 0.0
	var dx: float = p.pos.x - z.pos.x
	var dz: float = p.pos.z - z.pos.z
	var d := maxf(0.3, sqrt(dx * dx + dz * dz))
	var dist := minf(d + 0.6, S.leap + 0.6)
	f.leapV = Vector3((dx / d) * dist / LEAP_T, 0.0, (dz / d) * dist / LEAP_T)
	z.yaw = yawTo(dx, dz)
	f.leapArc = 0.0
	audioPlay(g, "sock_leap", {"pos": z.pos, "rate": 0.95 + randf() * 0.15})
	audioPlay(g, "zmb_swipe", {"pos": z.pos, "rate": 1.4, "vol": 0.6})
	burst(g, Vector3(z.pos.x, z.pos.y + 0.04, z.pos.z), {"shape": "puff", "count": 3, "size": 0.055, "speed": 1.6, "life": 0.3, "colors": ["#EDE6D6", "#D8CDB8"]})

static func doLeap(g, z: Dictionary, f: Dictionary, dt: float) -> void:
	var p = g.player
	f.mt += dt
	var k := clamp01(f.mt / LEAP_T)
	f.leapArc = LEAP_H * 4.0 * k * (1.0 - k)
	if f.bit:
		f.bitT += dt
	var d: Vector3 = f.leapV * dt
	z.vy -= G * dt
	d.y = z.vy * dt
	moveZ(g, z, d, 0.22, 0.72, 0.45)
	var fy := floorAt(g, z.pos.x, z.pos.z, z.pos.y + 0.3)
	if fy > -INF and z.pos.y <= fy + 0.001:
		z.vy = 0.0
	# Bite: the mouth against the player's body capsule (feet +0.25 .. +1.5).
	if not f.bit and p.alive:
		var mouthY: float = z.pos.y + f.leapArc + 0.55
		var mx: float = z.pos.x - sin(z.yaw) * 0.22
		var mz: float = z.pos.z - cos(z.yaw) * 0.22
		var hd := Vector2(p.pos.x - mx, p.pos.z - mz).length()
		var lo: float = p.pos.y + 0.2
		var hi: float = p.pos.y + 1.5
		var vy := (lo - mouthY) if mouthY < lo else ((mouthY - hi) if mouthY > hi else 0.0)
		var pr := num(p, "radius", 0.0)
		if Vector2(hd, vy).length() < (pr if pr != 0.0 else 0.38) + 0.2:
			f.bit = true
			f.bitT = 0.0
			if p.hurt(S.dmg, z.pos):
				g.events.emit("zombie:attack", {"z": z, "dmg": S.dmg})
				var v := Vector3(p.pos.x - z.pos.x, 0.0, p.pos.z - z.pos.z).normalized() * 6.0
				if p.has_method("knockback"):
					p.knockback(v)
			audioPlay(g, "zmb_hit", {"pos": z.pos, "rate": 1.7, "vol": 0.8})
			f.leapV = f.leapV * -0.35        # bounce off
			f.sq.kick(-2.5)
			if budget.giggle >= 0.5:
				budget.giggle -= 0.5
				audioPlay(g, "sock_giggle", {"pos": z.pos, "rate": 1.1, "delay": 0.25})
	if f.mt >= LEAP_T:
		f.mode = "recover"
		f.mt = 0.0
		f.leapArc = 0.0
		z.cd = S.cd
		f.sq.kick(-2.0)
		burst(g, Vector3(z.pos.x, z.pos.y + 0.04, z.pos.z), {"shape": "puff", "count": 3, "size": 0.05, "speed": 1.3, "life": 0.3, "colors": ["#EDE6D6", "#D8CDB8"]})

# Hop direction chosen at takeoff: straight at the player when visible, else the flow field; separation, pack
# cohesion, and circling when close but cooling down.
static func chooseHop(g, z: Dictionary, f: Dictionary, dist: float, dx: float, dz: float) -> void:
	var d := Vector3.ZERO
	if f.los and dist < 9.0:
		d = Vector3(dx / dist, 0.0, dz / dist)
	else:
		d = navDir(g, z.pos.x, z.pos.z)
		if d.length_squared() < 1e-6:
			d = Vector3(dx / maxf(1e-3, dist), 0.0, dz / maxf(1e-3, dist))
	if dist < 1.7 and z.cd > 0:
		var side: float = f.side
		d = Vector3(-dz / dist * side - dx / dist * 0.35, 0.0, dx / dist * side - dz / dist * 0.35)
	# Pack cohesion (far from the player): steer a little toward nearby socks.
	if dist > 5.0:
		var cx := 0.0
		var cz := 0.0
		var n := 0
		for o in g.zombies.alive:
			if o == z or o.type != "sock_hopper":
				continue
			var ox: float = o.pos.x - z.pos.x
			var oz: float = o.pos.z - z.pos.z
			var d2 := ox * ox + oz * oz
			if d2 > 0.8 and d2 < 12.0:
				cx += ox
				cz += oz
				n += 1
		if n:
			var l := sqrt(cx * cx + cz * cz)
			if l == 0.0:
				l = 1.0
			d.x += (cx / l) * 0.25
			d.z += (cz / l) * 0.25
	d.x += num(z, "sepX") * 0.9
	d.z += num(z, "sepZ") * 0.9
	var l2 := sqrt(d.x * d.x + d.z * d.z)
	if l2 == 0.0:
		l2 = 1.0
	d.x /= l2
	d.z /= l2
	# Hop length: average speed = z.speed; do not land on the player's toes when a bite is not ready.
	var L: float = z.speed * f.P
	if dist < 1.7 + L and z.cd <= 0:
		L = maxf(0.35, minf(L, dist - 1.4))
	f.H = clampf(0.12 + 0.12 * L, 0.15, 0.34)
	var air: float = f.P * (1.0 - C)
	f.vx = d.x * L / air
	f.vz = d.z * L / air
	f.face = yawTo(d.x, d.z)

static func hopPeriod(g, z: Dictionary, f: Dictionary) -> Dictionary:
	var b = musicBeat(g)
	if b != null:
		var beatDur := 60.0 / float(b.bpm)
		var perBeat := 2.0 if absf(log(beatDur / 2.0 / BASE_P)) < absf(log(beatDur / BASE_P)) else 1.0
		var off := 0.5 if perBeat == 1.0 and int(z.id) % 2 != 0 else 0.0
		return {"P": beatDur / perBeat, "target": fposmod(float(b.beat) * perBeat + off, 1.0), "beat": true}
	# No music: phase-lock to the nearest sock within 2.2 m that spawned earlier (packs hop in unison).
	var best = null
	var bd := 2.2 * 2.2
	for o in g.zombies.alive:
		if o == z or o.type != "sock_hopper" or o.id > z.id or o.get("flags") == null or o.flags.get("ph") == null:
			continue
		var ox: float = o.pos.x - z.pos.x
		var oz: float = o.pos.z - z.pos.z
		var d2 := ox * ox + oz * oz
		if d2 < bd:
			bd = d2
			best = o
	return {"P": f.freeP, "target": best.flags.ph if best != null else null, "beat": false}

static func updateSock(g, z: Dictionary, dt: float) -> bool:
	var f: Dictionary = z.flags
	var p = g.player
	var Zs = g.zombies
	refill(g)
	z.gawkT = 0.0
	if Zs.get("lure") != null and z.get("lured"):       # Tiny Tele: the manager walks it over and sits it down
		f.mode = "hop"
		return false
	f.driven = true
	var dx: float = p.pos.x - z.pos.x
	var dz: float = p.pos.z - z.pos.z
	var dist := maxf(1e-3, sqrt(dx * dx + dz * dz))
	var dy: float = p.pos.y - z.pos.y
	f.losT -= dt
	if f.losT <= 0:
		f.losT = 0.25
		f.los = losTo(g, z, p) if dist < 16.0 else false
	# Flavour: giggles.
	f.giggleT -= dt
	if not f.spotted and f.los and dist < 12.0:
		f.spotted = true
		if budget.giggle >= 0.5:
			budget.giggle -= 0.5
			audioPlay(g, "sock_giggle", {"pos": z.pos, "rate": 0.95 + randf() * 0.25})
	elif f.giggleT <= 0:
		f.giggleT = 3.0 + randf() * 5.0
		if dist < HEAR and budget.giggle >= 1.0:
			budget.giggle -= 1.0
			audioPlay(g, "sock_giggle", {"pos": z.pos, "rate": 0.9 + randf() * 0.35, "vol": 0.7})

	if f.mode == "crouch":
		f.mt += dt
		var want := yawTo(dx, dz)
		z.yaw += angDiff(want, z.yaw) * minf(1.0, dt * 16.0)
		stickToFloor(g, z, dt)
		if f.mt >= CROUCH:
			beginLeap(g, z, f)
		return true
	if f.mode == "leap":
		doLeap(g, z, f, dt)
		return true
	if f.mode == "recover":
		f.mt += dt
		stickToFloor(g, z, dt)
		if f.mt >= 0.26:
			f.mode = "hop"
			f.ph = C * 0.5
		return true

	# Hop cycle (phase-locked to the beat or the pack).
	var hper := hopPeriod(g, z, f)
	f.P = hper.P
	var prev: float = f.ph
	if hper.beat:
		# Music: the phase IS the beat grid (audio clock), so the lock holds even when game time lags real time;
		# switching into it blends the old phase away over ~0.25 s.
		if not f.beatLock:
			f.beatLock = true
			f.beatOff = wrapHalf(f.ph - hper.target)
		f.beatOff *= exp(-dt * 4.0)
		f.ph = hper.target + f.beatOff
	else:
		f.beatLock = false
		f.ph += dt / f.P
		if hper.target != null:
			f.ph += wrapHalf(hper.target - f.ph) * minf(1.0, dt * 3.5)
	f.ph = fposmod(f.ph, 1.0)
	var landed: bool = prev > 0.75 and f.ph < 0.25
	var tookOff: bool = prev < C and f.ph >= C and prev > C * 0.25
	if landed:
		f.sq.kick(-1.2)
		for e in f.eyeS:
			e.y.kick(-5.0)
		f.vx = 0.0
		f.vz = 0.0
	var onFloor: bool = f.ph < C
	# Leap-bite: from the floor, in range, visible, cooled down.
	if onFloor and p.alive and z.cd <= 0 and z.spawnT <= 0 and dist <= S.leap and absf(dy) < 1.0 and f.los:
		f.mode = "crouch"
		f.mt = 0.0
		f.vx = 0.0
		f.vz = 0.0
		f.side = -1.0 if randf() < 0.5 else 1.0
		if budget.giggle >= 0.4:
			budget.giggle -= 0.4
			audioPlay(g, "sock_giggle", {"pos": z.pos, "rate": 1.25, "vol": 0.8})
		stickToFloor(g, z, dt)
		return true
	if tookOff:
		chooseHop(g, z, f, dist, dx, dz)
		if dist < HEAR and budget.boing >= 1.0:
			budget.boing -= 1.0
			audioPlay(g, "sock_boing", {"pos": z.pos, "rate": f.pitch, "vol": 0.5})
	if onFloor:
		var want: float = f.face if f.get("face") != null else yawTo(dx, dz)
		z.yaw += angDiff(yawTo(dx, dz) if dist < 3.0 else want, z.yaw) * minf(1.0, dt * 12.0)
		z.anim.turn = 0.0
		stickToFloor(g, z, dt)
		z.anim.speed = 0.0
	else:
		var prevYaw: float = z.yaw
		z.yaw += angDiff(f.face if f.get("face") != null else z.yaw, z.yaw) * minf(1.0, dt * 8.0)
		z.anim.turn = (z.yaw - prevYaw) / maxf(dt, 1e-4)
		z.vy -= G * dt
		var r := moveZ(g, z, Vector3(f.vx * dt, z.vy * dt, f.vz * dt), 0.22, 0.72, 0.45)
		if r.get("onGround"):
			z.vy = 0.0
		if r.get("hitWall"):
			f.vx *= 0.5
			f.vz *= 0.5
		z.anim.speed = sqrt(f.vx * f.vx + f.vz * f.vz)
	# Anti-stuck bookkeeping is the manager's (nav distance); circling close to the player counts as progress there.
	return true

static func stickToFloor(g, z: Dictionary, dt: float) -> void:
	z.vy -= G * dt
	var r := moveZ(g, z, Vector3(0.0, z.vy * dt, 0.0), 0.22, 0.72, 0.45)
	if r.get("onGround"):
		z.vy = 0.0

# ------------------------------------------------------------------------------------------------ death
static func startDeath(g, z: Dictionary) -> void:
	var f: Dictionary = z.flags
	var d := {
		"vel": Vector3((randf() - 0.5) * 2.0, 5.2, (randf() - 0.5) * 2.0),
		"heading": randf() * PI * 2.0, "zigT": 0.1, "spin": 16.0 * (-1.0 if randf() < 0.5 else 1.0), "roll": 0.0,
		"phase": "fly", "flopT": 0.0, "jetT": 0.0, "button": false, "yaw": z.yaw, "floor": z.pos.y, "pitch": 0.0,
		"dissolved": false,
	}
	f.death = d
	var fy := floorAt(g, z.pos.x, z.pos.z, z.pos.y + 0.3)
	d.floor = fy if fy > -INF else z.pos.y
	audioPlay(g, "sock_deflate", {"pos": z.pos, "rate": 0.95 + randf() * 0.15})
	burst(g, Vector3(z.pos.x, z.pos.y + 0.5, z.pos.z), {"shape": "confetti", "count": 8, "speed": 3, "colors": ["#E0392F", "#F7C630", "#2F63D8", "#EDE0C4"]})

static func updateDeath_(g, z: Dictionary, dt: float, t: float) -> void:
	var f: Dictionary = z.flags
	var d = f.get("death")
	var m = z.get("model")
	if d == null or m == null:
		return
	var G0: Node3D = z.group
	var root := rigRoot(m.rig)
	var J: Dictionary = m.J
	var s := 1.0
	var sy := 1.0
	var sx := 1.0
	G0.rotation_order = EULER_ORDER_YXZ
	if d.phase == "fly":
		# 0-0.12 s: puff up; then zig-zag like a let-go balloon, shrinking, jets from the cuff.
		var inflate := easeOutBack(t / 0.12) if t < 0.12 else 1.0
		s = 1.0 + 0.25 * inflate if t < 0.12 else lerp_(1.25, 0.55, clamp01((t - 0.12) / 0.95))
		if t >= 0.12:
			d.zigT -= dt
			if d.zigT <= 0:
				d.zigT = 0.1 + randf() * 0.07
				d.heading += (-1.0 if randf() < 0.5 else 1.0) * (1.0 + randf() * 1.1)
				var up := 2.6 + randf() * 2.2 if t < 0.75 else -1.5 - randf()
				var sp := 3.6 + randf() * 1.6
				d.vel = Vector3(cos(d.heading) * sp, up, sin(d.heading) * sp)
				if randf() < 0.6:
					audioPlay(g, "sock_boing", {"pos": z.pos, "rate": 1.6 + randf() * 0.5, "vol": 0.25})
			d.jetT -= dt
			if d.jetT <= 0:
				d.jetT = 0.05
				var a: Vector3 = z.pos + d.vel * -0.05
				a.y += 0.12
				burst(g, a, {"shape": "puff", "count": 1, "size": 0.045, "speed": 0.6, "life": 0.3, "colors": ["#F4F1E8", "#E6DCCB"]})
		if t > 0.9:
			d.vel.y -= G * 0.8 * dt
		if z.pos.y > d.floor + 2.8 and d.vel.y > 0:
			d.vel.y = 0.0
		# moveCircle with the vertical step too (a zero delta.y would snap it back onto the floor).
		var r := moveZ(g, z, Vector3(d.vel.x * dt, d.vel.y * dt, d.vel.z * dt), 0.15, 0.3, 0.05)
		if r.get("hitWall"):
			d.heading += PI
			d.vel.x *= -1.0
			d.vel.z *= -1.0
		if r.get("hitCeiling") and d.vel.y > 0:
			d.vel.y = -0.5
		var gy = r.get("groundY")
		if gy != null and float(gy) > -INF:
			d.floor = float(gy)
		d.yaw += d.spin * dt * (1.0 if t < 0.9 else 0.4)
		d.roll = sin(t * 17.0) * 0.7
		d.pitch = sin(t * 11.0) * 0.6
		if t > 0.5 and r.get("onGround") and d.vel.y <= 0:
			z.pos.y = d.floor
			d.phase = "flop"
			d.flopT = 0.0
			audioPlay(g, "zmb_hit", {"pos": z.pos, "rate": 0.55, "vol": 0.45})
			burst(g, Vector3(z.pos.x, d.floor + 0.05, z.pos.z), {"shape": "puff", "count": 4, "size": 0.06, "speed": 1.5, "life": 0.35, "colors": ["#EDE6D6", "#D8CDB8"]})
		root.position = Vector3.ZERO
		root.scale = Vector3(s, s, s)
		G0.rotation = Vector3(d.pitch, d.yaw, d.roll)
		for n in ["s1", "s2", "s3"]:
			J[n].rotation.x = sin(t * 20.0 + n.length()) * 0.25
			J[n].rotation.z = cos(t * 17.0 + n.length()) * 0.2
		J.jaw.rotation.x = 0.6
		for side in ["L", "R"]:
			var e = m.eyes.get(side)
			if e != null:
				var a := t * 30.0 * (1.0 if side == "L" else -1.0)
				e.pivot.position = Vector3(e.base.x + cos(a) * 0.02, e.base.y + sin(a) * 0.02, e.base.z)
	else:
		# Flat on the floor like a deflated sock (lying along its length), a little bounce, then static.
		d.flopT += dt
		var k: float = d.flopT
		var bounce := sin((k / 0.25) * PI) * 0.06 * (1.0 - k / 0.25) if k < 0.25 else 0.0
		var flat := lerp_(0.8, 0.28, easeOutCubic(k / 0.12)) if k < 0.12 else 0.28
		s = 0.62
		sx = s * (1.1 if k < 0.12 else 1.22)
		sy = s * 1.05
		root.position = Vector3.ZERO
		root.scale = Vector3(sx, sy, s * flat)
		G0.rotation = Vector3(PI / 2.0 - 0.05, d.yaw, 0.0)   # on its back: googly eyes up
		z.pos.y = d.floor + 0.02 + bounce
		for n in ["s1", "s2", "s3"]:
			J[n].rotation.x = 0.0
			J[n].rotation.z = 0.12
		J.jaw.rotation.x = 0.35
		if not d.button and k > 0.05:
			d.button = true
			popButton(g, Vector3(z.pos.x, d.floor + 0.08, z.pos.z), Vector3(sin(d.yaw), 0.0, cos(d.yaw)))
		if k > 0.85 and not d.dissolved:
			d.dissolved = true
			burst(g, Vector3(z.pos.x, d.floor + 0.1, z.pos.z), {"shape": "static", "count": 14, "speed": 1.6, "size": 0.08, "life": 0.7})
			audioPlay(g, "zmb_death_static", {"pos": z.pos, "vol": 0.5})
		if k > 0.85:
			var q := 1.0 - smooth((k - 0.85) / 0.15)
			root.scale *= maxf(0.001, q)
	G0.position = z.pos
	var zs := num(z, "scale", 1.0)
	if zs == 0.0:
		zs = 1.0
	G0.scale = Vector3(zs, zs, zs)

# ------------------------------------------------------------------------------------------------ module
func hp(r = 1, _game = null) -> float:
	return jsRound(S.hpMix * hpAt(maxf(1.0, float(r))))

func speed(r = 1, _game = null) -> float:
	return float(S.speed15) if float(r) >= 15.0 else float(S.speed)

# A 0.7 m sock squeezes under the boards (1.0 s) instead of tearing them.
func entry(_game, _z, win):
	if win != null and win.get("type") == "boarded":
		return {"tear": false, "time": 1.0, "style": "squeeze"}
	return null

func build(game, z: Dictionary) -> void:
	var m = acquire(game)
	if m == null:
		return
	resetPose(m)
	z.model = m
	z.group = m.group
	z.rig = m.rig
	z.head = m.head
	z.headR = m.headR
	z.height = 0.75
	z.scale = 0.95 + randf() * 0.1
	var J: Dictionary = m.J
	z.hitZones = [
		{"shape": "sphere", "bone": J.head, "offset": [0, 0.06, -0.07], "r": 0.175, "zone": "eyes", "head": true, "mul": 1},
		{"shape": "capsule", "bone": J.root, "offset": [0, 0.05, 0], "bone2": J.s3, "offset2": [0, 0.06, 0], "r": 0.12, "zone": "torso", "head": false, "mul": 1},
	]
	var f: Dictionary = z.flags
	f.ph = randf()
	f.freeP = BASE_P * (0.95 + randf() * 0.1)
	f.P = f.freeP
	f.pitch = 0.9 + randf() * 0.3
	f.mode = "hop"
	f.mt = 0.0
	f.t = randf() * 10.0
	f.vx = 0.0
	f.vz = 0.0
	f.H = 0.26
	f.los = false
	f.losT = randf() * 0.25
	f.giggleT = 2.0 + randf() * 5.0
	f.side = -1.0 if randf() < 0.5 else 1.0
	f.sq = Rig.Spring.new(260, 15)
	f.bend = Rig.Spring.new(120, 12)
	f.eyeS = [0, 1].map(func(_i): return {"x": Rig.Spring.new(120, 12), "y": Rig.Spring.new(120, 12, -0.55)})
	f.driven = false
	f.spotted = false
	f.beatLock = false
	f.beatOff = 0.0
	f.face = null
	f.bit = false
	f.bitT = 0.0
	f.leapArc = 0.0
	f.leapV = Vector3.ZERO
	z.animator = makeAnimator(z, get_script())
	ensureTicker(game)
	if m.bodies:
		for b in m.bodies:
			setCast(b, true)
	m.cards = []

func release(_game, z: Dictionary) -> void:
	var m = z.get("model")
	if m == null:
		return
	DAU.detach(m.group)
	resetPose(m)
	if pool.size() < 24:
		pool.append(m)
	z.model = null

func update(game, z: Dictionary, dt: float) -> bool:
	return updateSock(game, z, dt)

# Eyes (the top 40 %) deal exactly ×2: weapons pre-multiply their own head multiplier for head:true zones.
func onDamage(game, _z, amount: float, info = null) -> float:
	if info is Dictionary and info.get("zone") == "eyes" and info.get("head"):
		var cause = info.get("cause")
		var hm := weaponHeadMul(game, info.get("weaponId")) if (cause == "bullet" or not cause) else 1.0
		return (amount / hm) * 2.0
	return amount

func onDeath(game, z: Dictionary, _info = null):
	var e = z.get("entry")
	if e is Dictionary and e.get("kind") == "screen" and e.get("phase") == "tele":
		return null
	startDeath(game, z)
	return DEATH

func updateDeath(game, z: Dictionary, dt: float, t: float) -> void:
	updateDeath_(game, z, dt, t)

# Game.precompile samples (shader warm-up is engine plumbing in Godot; kept for the contract).
func warmup(game) -> Array:
	var out: Array = []
	if pool.is_empty():
		var m = acquire(game)
		if m != null:
			pool.append(m)
	if not pool.is_empty():
		out.append(pool[0].group)
	buttonAssets(game)
	out.append(makeButtonMesh())
	return out

func debugBite(_game, z) -> bool:
	if z == null or z.get("dead"):
		return false
	z.cd = 0.0
	z.flags.mode = "crouch"
	z.flags.mt = 0.0
	return true
