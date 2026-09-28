# Runtime for baked SDF characters (port of src/art/charRuntime.js; ARCHITECTURE §8/§12 compatible).
#   CharRuntime.buildCharacter(defOrId, opts) -> CharRuntime.Character { group, rig, animator, skinnedMesh, slots, face,
#     hairBounds, parts, def, header, update(dt, state) }
#   opts: { envMap, globals (accepted, the globals are shared RenderingServer params), heroFade, animator: true|false|
#           style, layer (render layer; zombies default LAYERS.ZOMBIES), shadows: true (cast), receiveShadow: false }
# receiveShadow is FALSE for every JS character (the shaders are shadows_disabled): at game shadow-map resolution a
# character's own jaw/hair/arm shadows alias into dark smudges; the baked AO already darkens those contacts softly.
# Assets: godot/assets/chars/<id>.glb (blender/chars, format in blender/chars/FORMAT.md). The rig is rebuilt as
# Node3D joints (scripts/core/rig.gd createRig for humanoids, EULER_ORDER_XYZ, rest rotation identity like three.js)
# so the engine Animator animates it unchanged; the skinned body is driven by a Skeleton3D whose bone poses copy the
# joints' local transforms every frame (CharSkeleton, after all game updates), with Skin binds = inverse(bind-pose
# world), which is exactly three's SkinnedMesh bound to the joints in the bake's bind pose (A-pose).
# animator.update is wrapped (animator.updateFn, see rig.gd) to (1) add the character's rest offsets (def.armOut:
# arms clear the torso; def.poseOffset: {joint:[x,y,z]} additive) and (2) update the face.
# Meshes / materials are cached per character id and shared between instances (zombie crowds).
# Not ported (three.js draw-call plumbing, SPEC §0.2): mergeCharacter / mergeAttachments (opts.merge; the zombie
# builders' mergeAttachments(c) call is a no-op returning []), optimizeSkeleton(s) (bone-texture upload dedupe),
# extendSkeleton. charOpt keeps its fields for the code that reads them.
class_name CharRuntime
extends RefCounted

const FaceMod := preload("res://scripts/art/face.gd")

# Registry of character definitions (src/art/chars/index.js). Add new characters here AND bake them; characterIds()
# only lists ids that are both defined here and baked (godot/assets/chars/<id>.glb).
const INDEX := ["duke", "example_sock", "z_crew", "z_reporter", "z_disco", "z_mom", "skip", "roxy", "penny"]
# Every runtime definition file (the JS game imports z_sock / z_forecaster / z_bigshot / boss_baron directly).
const DEF_IDS := ["duke", "skip", "roxy", "penny", "z_crew", "z_reporter", "z_disco", "z_mom", "z_sock", "z_forecaster",
	"z_bigshot", "boss_baron", "example_sock"]

# Live perf flags of the JS (merge / dedupe / crowd A/B toggles; gen invalidates model pools). Kept for API parity.
static var charOpt := {"merge": true, "dedupe": true, "gen": 0, "crowd": true}

static var geoCache := {}
static var matCache := {}
static var _defs := {}

static func assetPath(id: String) -> String:
	return "res://assets/chars/%s.glb" % id

static func isBaked(id: String) -> bool:
	return ResourceLoader.exists(assetPath(id))

static func characterIds() -> Array:
	return INDEX.filter(func(id): return isBaked(id))

# JS getDef(id) = DEFS[id] (the index.js registry only).
static func getDef(id: String):
	return loadDef(id) if INDEX.has(id) else null

# The definition of any character id (JS: `import def from './chars/<id>.js'`). Cached: one object per id.
static func loadDef(id: String):
	if _defs.has(id):
		return _defs[id]
	var path := "res://scripts/art/chars/%s.gd" % id
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	var d: Dictionary = script.call("def")
	# def.anchors(ctx) / def.createAnimator(rig, ctx): Callables on the definition script's static functions (a
	# lambda kept in this static cache crashes Godot at exit, so the definition files expose static funcs).
	for m in script.get_script_method_list():
		if m.name == "anchors" or m.name == "createAnimator":
			d[m.name] = Callable(script, m.name)
	_defs[id] = d
	return d

# ------------------------------------------------------------------------------------------------ asset decode
static func _extrasDa(n: Object) -> Dictionary:
	if n == null or not n.has_meta("extras"):
		return {}
	var ex = n.get_meta("extras")
	if not (ex is Dictionary):
		return {}
	var da = ex.get("da")
	if da is String:
		var parsed = JSON.parse_string(da)
		return parsed if parsed is Dictionary else {}
	return da if da is Dictionary else {}

static func _findHeader(n: Node) -> Dictionary:
	var da := _extrasDa(n)
	if da.has("bones"):
		return da
	for c in n.get_children():
		var h := _findHeader(c)
		if not h.is_empty():
			return h
	return {}

static func decoded(id: String) -> Dictionary:
	var d = geoCache.get(id)
	if d != null:
		return d
	if not isBaked(id):
		push_error("charRuntime: '%s' is not baked (python3 blender/build_all.py --only chars --id %s)" % [id, id])
		return {}
	var scene: PackedScene = load(assetPath(id))
	var inst: Node = scene.instantiate()
	# the glTF root node `<id>` (header in extras.da) is the scene root or its child, depending on the importer
	var header := _findHeader(inst)
	var body: MeshInstance3D = inst.find_child("body", true, false) as MeshInstance3D
	d = {"header": header, "scene": scene, "parts": {}, "bindNames": [], "hair": header.get("hair", {})}
	if body != null:
		d.body = _rebuildMesh(body.mesh as ArrayMesh)
		var names := []
		var sk: Skin = body.skin
		var skel := body.get_node_or_null(body.skeleton) as Skeleton3D
		if sk != null:
			for i in sk.get_bind_count():
				var bn := String(sk.get_bind_name(i))
				if bn == "" and skel != null and sk.get_bind_bone(i) >= 0:
					bn = skel.get_bone_name(sk.get_bind_bone(i))
				names.append(bn)
		else:
			names = header.get("bones", []).duplicate()
		d.bindNames = names
	var parts: Dictionary = header.get("parts", {}) if header.get("parts") is Dictionary else {}
	for name in parts:
		var p: Dictionary = parts[name]
		var node := inst.find_child(str(p.get("node", "part_" + name)), true, false) as MeshInstance3D
		if node != null:
			d.parts[name] = _rebuildMesh(node.mesh as ArrayMesh)
	inst.free()
	geoCache[id] = d
	return d

# The imported body / part mesh + what the char shader needs that Godot cannot give it: CUSTOM3 = the rest (bind)
# position (Godot skins and morphs before vertex(): the JS vRest), TANGENT = the hair flow direction (skinned by
# Godot like the JS `skinMatrix * flow`). Vertex order, blend shapes and every other channel are kept.
static func _rebuildMesh(src: ArrayMesh) -> ArrayMesh:
	if src == null:
		return null
	var arrays := src.surface_get_arrays(0)
	var bs := src.surface_get_blend_shape_arrays(0)
	var fmt := src.surface_get_format(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := verts.size()
	var c3 := PackedFloat32Array()
	c3.resize(n * 4)
	for i in n:
		var v := verts[i]
		c3[i * 4] = v.x
		c3[i * 4 + 1] = v.y
		c3[i * 4 + 2] = v.z
	arrays[Mesh.ARRAY_CUSTOM3] = c3
	var c1 = arrays[Mesh.ARRAY_CUSTOM1]
	var tan := PackedFloat32Array()
	tan.resize(n * 4)
	for i in n:
		var f := Vector3(1, 0, 0)
		if c1 is PackedFloat32Array and (c1 as PackedFloat32Array).size() >= n * 4:
			var g := Vector3(c1[i * 4 + 1], c1[i * 4 + 2], c1[i * 4 + 3])
			if g.length_squared() > 1e-8:
				f = g.normalized()
		tan[i * 4] = f.x
		tan[i * 4 + 1] = f.y
		tan[i * 4 + 2] = f.z
		tan[i * 4 + 3] = 1.0
	arrays[Mesh.ARRAY_TANGENT] = tan
	var flags := 0
	for k in 4:
		var shift: int = Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS
		var cf: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT if k == 3 else ((fmt >> shift) & Mesh.ARRAY_FORMAT_CUSTOM_MASK)
		if arrays[Mesh.ARRAY_CUSTOM0 + k] != null:
			flags |= cf << shift
	flags |= fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for b in bs:
		b[Mesh.ARRAY_TANGENT] = tan
	var m := ArrayMesh.new()
	m.blend_shape_mode = src.blend_shape_mode
	for i in src.get_blend_shape_count():
		m.add_blend_shape(src.get_blend_shape_name(i))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, bs, {}, flags)
	m.resource_name = src.resource_name
	return m

# Local transform of `n` relative to `root` (product of the locals below root; root excluded).
static func _relTransform(n: Node3D, root: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

static func material(id: String, header: Dictionary, def: Dictionary, opts: Dictionary) -> DAMaterial:
	var env: bool = not (opts.get("envMap") is bool and opts.envMap == false)
	var key := "%s|%s|%d|%d" % [id, "env" if env else "", 1 if Rig.truthy(opts.get("heroFade")) else 0, 1 if Rig.truthy(opts.get("globals")) else 0]
	var m = matCache.get(key)
	if m == null:
		m = CharMaterial.createCharMaterial({"header": header, "rim": def.get("rim"), "envMap": env,
			"globals": opts.get("globals"), "heroFade": Rig.truthy(opts.get("heroFade"))})
		matCache[key] = m
	return m

# ------------------------------------------------------------------------------------------------ build
static func buildCharacter(defOrId, opts: Dictionary = {}) -> Character:
	var def = loadDef(defOrId) if (defOrId is String or defOrId is StringName) else defOrId
	if not (def is Dictionary):
		push_error("charRuntime: unknown character '%s'" % str(defOrId))
		return null
	var id: String = def.id
	var D := decoded(id)
	if D.is_empty() or D.get("body") == null:
		push_error("charRuntime: '%s' has no baked body" % id)
		return null
	var header: Dictionary = D.header
	var R := RigBuild.buildRig(def)
	var rig: Rig.RigData = R.rig
	var J: Dictionary = R.joints

	# Bone inverses in the bake's bind pose (root at identity).
	RigBuild.applyBindPose(R)
	var bindWorld := {}
	for n in R.bones:
		bindWorld[n] = _relTransform(J[n], rig.root)
	RigBuild.resetPose(R)

	var mat := material(id, header, def, opts)
	var skel := CharSkeleton.new()
	skel.name = "skeleton"
	var boneIndex := {}
	for n in R.bones:
		boneIndex[n] = skel.get_bone_count()
		skel.add_bone(n)
	for n in R.bones:
		var p = R.parents[n]
		if p != null:
			skel.set_bone_parent(boneIndex[n], boneIndex[p])
		skel.set_bone_rest(boneIndex[n], Transform3D(Basis(), J[n].position))
		skel.joints.append(J[n])
	rig.root.add_child(skel)
	if D.get("skin") == null:
		var sk := Skin.new()
		for bn in D.bindNames:
			if bindWorld.has(bn):
				sk.add_named_bind(bn, bindWorld[bn].affine_inverse())
			else:
				push_warning("charRuntime: '%s' skin joint '%s' is not a rig joint" % [id, bn])
				sk.add_named_bind(bn, Transform3D())
		D.skin = sk
	var mesh := MeshInstance3D.new()
	mesh.name = "char:%s" % id
	mesh.mesh = D.body
	mesh.skin = D.skin
	skel.add_child(mesh)
	mesh.skeleton = NodePath("..")
	mesh.material_override = mat
	var shadows: bool = not (opts.get("shadows") is bool and opts.shadows == false)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skel.sync()

	var face = FaceMod.FaceController.new()
	var morphs: Array = header.get("morphs", []) if header.get("morphs") is Array else []
	if not morphs.is_empty():
		face.setMesh(mesh)

	# Rigid baked parts (brows, props): world bind geometry, re-expressed in the joint's local frame via a pivot.
	var parts := {}
	var hparts: Dictionary = header.get("parts", {}) if header.get("parts") is Dictionary else {}
	for name in hparts:
		var p: Dictionary = hparts[name]
		var boneName: String = p.get("bone") if p.get("bone") != null else "head"
		var joint: Node3D = J.get(boneName, J.get("head"))
		if not bindWorld.has(boneName) or not D.parts.has(name):
			continue
		var inv: Transform3D = (bindWorld[boneName] as Transform3D).affine_inverse()
		var pivotL: Vector3 = inv * DAU.v3(p.pivot)
		var pivot := DAU.node3d("part:%s" % name)
		pivot.position = pivotL
		var pm := MeshInstance3D.new()
		pm.mesh = D.parts[name]
		pm.name = name
		# mesh local = inv(bind) * world, then minus pivot
		pm.transform = Transform3D(Basis(), -pivotL) * inv
		pm.material_override = mat
		pm.cast_shadow = mesh.cast_shadow
		pivot.add_child(pm)
		joint.add_child(pivot)
		parts[name] = pivot
		if String(name).begins_with("brow"):
			face.addBrow(pivot, "L" if String(name).ends_with("L") else "R")

	# Attachments (built by the Blender half; reparented to their joints with their JS local transforms)
	var rim = def.get("rim")
	var rimColor = rim.color if rim is Dictionary and rim.get("color") != null else ("#8FF3FF" if def.get("kind") == "zombie" else "#FFD9A0")
	var env: bool = not (opts.get("envMap") is bool and opts.envMap == false)
	var actx := {"rimColor": rimColor, "envMap": env}
	var inst: Node = (D.scene as PackedScene).instantiate()
	var attList: Array = header.get("attachments", []) if header.get("attachments") is Array else []
	for aname in attList:
		var node := inst.find_child(str(aname), true, false) as Node3D
		if node == null:
			push_warning("charRuntime: '%s' attachment '%s' missing" % [id, aname])
			continue
		var da := _extrasDa(node)
		var joint: Node3D = J.get(da.get("joint", "head"), null)
		if joint == null:
			joint = J.get("head", rig.root)
		node.get_parent().remove_child(node)
		_setupAttachment(node, da, true, actx)
		joint.add_child(node)
	inst.free()

	# Face: eyes exported by the Blender builder (header.face.eyes: node names + cap + E)
	var hface = header.get("face")
	if hface is Dictionary and hface.get("eyes") is Array:
		for e in hface.eyes:
			var root := rig.root.find_child(str(e.root), true, false)
			var ball := rig.root.find_child(str(e.ball), true, false)
			var upper := rig.root.find_child(str(e.upper), true, false)
			var lower := rig.root.find_child(str(e.lower), true, false)
			if root == null or ball == null or upper == null or lower == null:
				push_warning("charRuntime: '%s' eye nodes missing (%s)" % [id, str(e)])
				continue
			face.addEye({"side": e.side, "root": root, "ball": ball, "upper": upper, "lower": lower,
				"cap": float(e.get("cap", PI * 0.53)), "E": e.get("E", {})})

	# Slots (ARCHITECTURE §12)
	var dims: Dictionary = rig.dims
	var hb: Dictionary = D.hair if D.hair is Dictionary else {}
	var top: float = hb.get("top", 0.3)
	var cz: float = hb.get("cz", 0.0)
	var S: Dictionary = def.get("slots", {}) if def.get("slots") is Dictionary else {}
	var slots := {}
	if R.humanoid:
		slots = {
			"head": _slot(J.head, "head", S.get("head", [0, top, cz]), rig),
			"handL": _slot(J.handL, "handL", S.get("handL", [0, -0.07, 0]), rig),
			"handR": _slot(J.handR, "handR", S.get("handR", [0, -0.07, 0]), rig),
			"footL": _slot(J.footL, "footL", S.get("footL", [0, -0.04, -0.05]), rig),
			"footR": _slot(J.footR, "footR", S.get("footR", [0, -0.04, -0.05]), rig),
			"back": _slot(J.chest, "back", S.get("back", [0, float(dims.torso) * 0.15, 0.13]), rig),
			"wristL": _slot(J.elbowL, "wristL", S.get("wristL", [0, -float(dims.foreArm) * 0.85, 0]), rig),
			"wristR": _slot(J.elbowR, "wristR", S.get("wristR", [0, -float(dims.foreArm) * 0.85, 0]), rig),
			"neck": _slot(J.neck, "neck", S.get("neck", [0, 0, 0]), rig),
			"belt": _slot(J.hips, "belt", S.get("belt", [0, 0.05, -0.12]), rig),
		}
	else:
		for k in S:
			var v: Dictionary = S[k]
			slots[k] = _slot(J.get(v.get("joint")), k, v.get("pos", [0, 0, 0]), rig)

	# Animator (humanoids use the engine Animator unchanged, wrapped for rest offsets + face)
	var animator = null
	var aopt = opts.get("animator", true)
	if R.humanoid and not (aopt is bool and aopt == false):
		var style
		if aopt is String or aopt is StringName or aopt is Dictionary:
			style = aopt
		else:
			style = def.get("animStyle") if def.get("animStyle") != null else ("zombie" if def.get("kind") == "zombie" else "hero")
		animator = Rig.Animator.new(rig, style)
		var orig := Callable(animator, "_procUpdate")
		var armOut: float = def.armOut if def.get("armOut") != null else 0.15
		# [joint, [x, y, z]] pairs resolved once
		var offs = null
		if def.get("poseOffset") is Dictionary:
			offs = []
			for n in def.poseOffset:
				if J.has(n):
					offs.append([J[n], def.poseOffset[n]])
		var fc = face
		animator.updateFn = func(dt: float, st: Dictionary) -> void:
			orig.call(dt, st)
			CharRuntime.applyRestOffsets(J, armOut, offs)
			fc.update(dt)
	elif def.get("createAnimator") is Callable:
		animator = (def.createAnimator as Callable).call(rig, {"face": face})

	var group := DAU.node3d("char:%s" % id)
	group.add_child(rig.root)
	var layer = opts.get("layer")
	if layer == null and def.get("kind") == "zombie":
		layer = Config.LAYERS.ZOMBIES
	if layer != null:
		DAU.setLayerRecursive(group, int(layer))
	DAU.traverse(group, func(o):
		if o is MeshInstance3D:
			DAU.ud(o).keepColor = true)

	var res := Character.new()
	res.group = group
	res.rig = rig
	res.animator = animator
	res.skinnedMesh = mesh
	res.slots = slots
	res.face = face
	res.hairBounds = float(hb.get("radius", 0.2))
	res.parts = parts
	res.def = def
	res.header = header
	return res

static func _slot(parent: Node3D, name: String, pos, rig) -> Node3D:
	var o := DAU.node3d("slot:%s" % name)
	o.position = DAU.v3(pos)
	(parent if parent != null else rig.root).add_child(o)
	return o

# Top attachment node: JS local transform in the joint frame (da.local); every node of the subtree: XYZ Euler order,
# userData, castShadow / visible / renderOrder, materials converted from their "da" specs.
static func _setupAttachment(node: Node, da: Dictionary, top: bool, actx: Dictionary) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		# XYZ Euler order first, then (re)set the transform so .rotation is re-derived in that order
		var t := n3.transform
		n3.rotation_order = EULER_ORDER_XYZ
		if top and da.get("local") is Dictionary:
			var L: Dictionary = da.local
			var q = L.get("quat")
			var s = L.get("scale")
			var basis := Basis(Quaternion(q[0], q[1], q[2], q[3])) if q is Array else Basis()
			if s is Array:
				basis = basis * Basis.from_scale(DAU.v3(s))
			t = Transform3D(basis, DAU.v3(L.get("pos", [0, 0, 0])))
		n3.transform = t
		if da.get("visible") is bool:
			n3.visible = da.visible
	if da.get("userData") is Dictionary:
		DAU.ud(node).merge(da.userData, true)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if da.get("castShadow") is bool:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if da.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ctx := actx.duplicate()
		if da.get("renderOrder") != null:
			ctx.renderOrder = da.renderOrder
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var im: Material = mi.get_active_material(i)
				var spec := _extrasDa(im)
				if not spec.is_empty():
					mi.set_surface_override_material(i, CharMaterial.fromSpec(spec, im, ctx))
	for c in node.get_children():
		_setupAttachment(c, _extrasDa(c), false, actx)

# Arms: push out from the torso while hanging (fades as the arm swings up/forward); plus custom offsets.
static func applyRestOffsets(J: Dictionary, armOut: float, offs) -> void:
	if armOut != 0.0:
		var fl := maxf(0.0, 1.0 - absf(J.shoulderL.rotation.x) / 1.3)
		var fr := maxf(0.0, 1.0 - absf(J.shoulderR.rotation.x) / 1.3)
		J.shoulderL.rotation.z -= armOut * fl
		J.shoulderR.rotation.z += armOut * fr
	if offs != null:
		for i in offs.size():
			var j: Node3D = offs[i][0]
			var e: Array = offs[i][1]
			j.rotation += Vector3(e[0], e[1], e[2])

# Draw-call merging of the JS (not ported, SPEC §0.2): kept so the zombie builders' calls port 1:1.
static func mergeAttachments(_c, _opts: Dictionary = {}) -> Array:
	return []

static func optimizeSkeleton(skeleton):
	return skeleton

static func optimizeSkeletons(_root) -> void:
	pass


# The result of buildCharacter (the JS returned a plain object with an update method).
class Character extends RefCounted:
	var group: Node3D
	var rig
	var animator
	var skinnedMesh: MeshInstance3D
	var slots: Dictionary
	var face
	var hairBounds: float
	var parts: Dictionary
	var def: Dictionary
	var header: Dictionary

	func update(dt: float, state: Dictionary = {}) -> void:
		if animator != null:
			animator.update(dt, state)
		else:
			face.update(dt)


# Skeleton3D whose bone poses follow the rig's Node3D joints (bone i = joints[i]); synced every frame after all the
# game's updates (process_priority 1000; the JS skeleton read bone.matrixWorld at render time).
class CharSkeleton extends Skeleton3D:
	var joints: Array = []

	func _init() -> void:
		process_priority = 1000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		set_process(true)

	func _process(_delta: float) -> void:
		sync()

	func sync() -> void:
		for i in joints.size():
			var j: Node3D = joints[i]
			set_bone_pose_position(i, j.position)
			set_bone_pose_rotation(i, j.quaternion)
			set_bone_pose_scale(i, j.scale)
