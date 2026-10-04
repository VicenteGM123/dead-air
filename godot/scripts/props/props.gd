# Prop library: the runtime half of src/props/kit.js (buildProp / cloneProp / listProps / propMeta) + index.js
# (placeProp), loading the Blender-built glTFs (SPEC §5.4/§5.5) instead of running the JS builders.
#
#   build(id, opts = {}) -> Node3D       JS buildProp(id, game, opts): the variant of godot/assets/props/index.json
#                                        whose opts deep-equal the request (numbers within 1e-6, key order
#                                        irrelevant); else the variant of that id sharing the most keys (warns once).
#                                        A fresh instance (cached PackedScene); its materials are the DEAD AIR
#                                        materials of the "da" specs (mats.fromSpec, shared like the JS cache; CRT
#                                        screens get their own material per instance); DAU.ud(root) = the JS root
#                                        userData ({id, size, colliders, screens:[{mesh, group, id?}], lightAnchors,
#                                        parts:{name: Node3D}, interact, anchors, ...} with {"__node"} refs resolved),
#                                        DAU.ud(child) = the child flags (noMerge, noShadow, screenGroup, ...).
#   place(parent, id, o = {}) -> Node3D  JS placeProp(game, parent, id, { pos:[x,y,z], rotY=0, opts, area,
#                                        colliders=true, lights=true, screens=true, tag='prop' }): world colliders
#                                        are the AABBs of the rotated local boxes (game.level.col.addBox), light anchors
#                                        go to game.lights.addAnchor, screens to game.screens.register.
#   cloneProp(src) -> Node3D             JS cloneProp: duplicate with the userData node refs remapped.
#   listProps(category = null), propMeta(id)   ids known to the index (meta from the index entries when present).
#   loadRuntime(path) -> Node3D, prepare(root) -> root   the same conversion for other Blender GLBs
#                                        (godot/assets/runtime/...): materials + userData + node flags.
# Aliases with the JS names: buildProp(id, opts), placeProp(parent, id, o).
# userData values {"__node": name} -> that Node3D, {"__material": spec} -> mats.fromSpec(spec) (JS Material refs, e.g.
# bc_on_air lampMats).
# Node flags from "da": castShadow -> cast_shadow, visible:false, layers (three layer mask = VisualInstance3D
# layers), rotationOrder (default XYZ on every node, like three), instanceColor (InstancedMesh children:
# per-instance shader parameter "instanceColor"), renderOrder / receiveShadow kept in DAU.ud.
extends RefCounted

const ROOT := "res://assets/props/"
const DAMat := preload("res://scripts/core/da_material.gd")

var game
var index := {}              # id -> [{key, opts}]
var _scenes := {}            # glb path -> PackedScene
var _recipes := {}           # glb path -> { converted: bool, screens: [[path, surface, spec]] }
var _warned := {}

func _init(g) -> void:
	game = g
	_loadIndex()

func init() -> void:
	if index.is_empty():
		_loadIndex()

func _loadIndex() -> void:
	var p := ROOT + "index.json"
	if not FileAccess.file_exists(p):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if d is Dictionary:
		index = d

# ------------------------------------------------------------------------------------------------ registry
func propMeta(id: String):
	var list = index.get(id)
	if list == null:
		return null
	var m := {"id": id, "category": "misc", "tags": [], "size": null, "desc": "", "cache": true, "hero": false}
	if list.size() > 0 and list[0] is Dictionary and list[0].get("meta") is Dictionary:
		m.merge(list[0].meta, true)
	return m

func listProps(category = null) -> Array:
	var out: Array = []
	for id in index:
		var m = propMeta(id)
		if category == null or m.category == category:
			out.append(m)
	return out

# ------------------------------------------------------------------------------------------------ variants
static func _deepEq(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 1e-6
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _deepEq(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deepEq(a[i], b[i]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	if typeof(a) != typeof(b):
		if (a is String or a is StringName) and (b is String or b is StringName):
			return str(a) == str(b)
		return false
	return a == b

func _variant(id: String, opts: Dictionary):
	var list = index.get(id)
	if list == null or list.is_empty():
		return null
	for v in list:
		if _deepEq(v.get("opts", {}), opts):
			return v
	var best = list[0]
	var bestN := -1
	for v in list:
		var o: Dictionary = v.get("opts", {})
		var n := 0
		for k in opts:
			if o.has(k) and _deepEq(o[k], opts[k]):
				n += 1
		n -= absi(o.size() - opts.size()) * 0   # ties: first listed
		if n > bestN:
			bestN = n
			best = v
	var wk := "%s|%s" % [id, JSON.stringify(opts)]
	if not _warned.has(wk):
		_warned[wk] = true
		push_warning("[props] no variant of '%s' for %s: using %s" % [id, JSON.stringify(opts), best.key])
	return best

# ------------------------------------------------------------------------------------------------ build
# Builds a prop (a fresh instance of its variant's GLB, converted). Unknown ids return null (JS throws).
func build(id: String, opts: Dictionary = {}) -> Node3D:
	var v = _variant(id, opts)
	if v == null:
		if not _warned.has("id:" + id):
			_warned["id:" + id] = true
			push_error("[props] unknown prop \"%s\"" % id)
		return null
	var root := _instantiate(ROOT + str(v.key) + ".glb")
	if root == null:
		return null
	_normalizeUserData(root, id)
	return root

func buildProp(id: String, opts: Dictionary = {}) -> Node3D:
	return build(id, opts)

func loadRuntime(path: String) -> Node3D:
	return _instantiate(path)

# The glTF scene's single top node is the asset root (the JS Group); it is detached from the importer wrapper.
func _instantiate(path: String) -> Node3D:
	var ps: PackedScene = _scenes.get(path)
	if ps == null:
		if not ResourceLoader.exists(path):
			if not _warned.has(path):
				_warned[path] = true
				push_error("[props] missing asset %s" % path)
			return null
		ps = load(path)
		if ps == null:
			if not _warned.has(path):
				_warned[path] = true
				push_error("[props] cannot load %s" % path)
			return null
		_scenes[path] = ps
	var wrap := ps.instantiate()
	var root: Node3D
	if wrap.get_child_count() == 1 and wrap.get_child(0) is Node3D and not wrap.has_meta("extras"):
		root = wrap.get_child(0)
		wrap.remove_child(root)
		wrap.free()
	else:
		root = wrap
	_prepare(root, path)
	return root

func prepare(root: Node) -> Node:
	_prepare(root, "")
	return root

func _prepare(root: Node, key: String) -> void:
	var recipe = _recipes.get(key) if key != "" else null
	var first: bool = recipe == null
	if first:
		recipe = {"screens": []}
		if key != "":
			_recipes[key] = recipe
	var nodes: Array = []
	_collect(root, nodes)
	var byName := {}
	for n in nodes:
		byName[str(n.name)] = n
	# materials: converted once into the shared imported meshes; CRT screens get a material per instance
	if first:
		for n in nodes:
			if n is MeshInstance3D and n.mesh != null:
				for i in n.mesh.get_surface_count():
					var im: Material = n.mesh.surface_get_material(i)
					var spec = _spec(im)
					if spec == null:
						continue
					var k := str(spec.get("kind", "toon"))
					if k == "screen" or k == "rubberGlass":
						recipe.screens.append([root.get_path_to(n), i, spec, im])
					else:
						n.mesh.surface_set_material(i, game.mats.fromSpec(spec, im))
	for s in recipe.screens:
		var n = root.get_node_or_null(s[0])
		if n is MeshInstance3D:
			n.set_surface_override_material(s[1], game.mats.fromSpec(s[2], s[3]))
	# node flags + userData
	for n in nodes:
		if n is Node3D:
			n.rotation_order = EULER_ORDER_XYZ
		var da = _nodeDa(n)
		if da == null:
			continue
		if n == root:
			DAU.ud(n).merge(_resolve(da, byName, true), true)
		else:
			DAU.ud(n).merge(da, true)
		_applyFlags(n, da)

static func _collect(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)

static func _spec(m: Material):
	if m == null or not m.has_meta("extras"):
		return null
	var ex = m.get_meta("extras")
	var da = ex.get("da") if ex is Dictionary else null
	if da is String:
		da = JSON.parse_string(da)
	return da if da is Dictionary else null

static func _nodeDa(n: Node):
	if not n.has_meta("extras"):
		return null
	var ex = n.get_meta("extras")
	var da = ex.get("da") if ex is Dictionary else null
	if da is String:
		da = JSON.parse_string(da)
	return da if da is Dictionary else null

func _applyFlags(n: Node, da: Dictionary) -> void:
	if da.get("visible") == false and n is Node3D:
		n.visible = false
	if n is GeometryInstance3D and da.has("castShadow"):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if da.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is VisualInstance3D and da.get("layers") != null:
		n.layers = int(da.layers)
	if n is Node3D and da.get("rotationOrder") != null:
		var ro := {"XYZ": EULER_ORDER_XYZ, "XZY": EULER_ORDER_XZY, "YXZ": EULER_ORDER_YXZ, "YZX": EULER_ORDER_YZX,
			"ZXY": EULER_ORDER_ZXY, "ZYX": EULER_ORDER_ZYX}
		n.rotation_order = ro.get(str(da.rotationOrder), EULER_ORDER_XYZ)
	var ic = da.get("instanceColor")
	if ic is Array and ic.size() >= 3:
		var c := Color(float(ic[0]), float(ic[1]), float(ic[2])).linear_to_srgb()
		DAU.traverse(n, func(o):
			if o is GeometryInstance3D:
				DAU.setInstanceColor(o as GeometryInstance3D, c))

# Root userData: {"__node": name} -> the node, parts {name: "<node name>"} -> nodes, screens [{node}] -> {mesh}.
func _resolve(v, byName: Dictionary, top := false):
	if v is Dictionary:
		if v.size() == 1 and v.has("__node"):
			return _node(byName, str(v.__node))
		if v.size() == 1 and v.has("__material"):
			return game.mats.fromSpec(v.__material, null) if game.mats != null else null
		var o := {}
		for k in v:
			if top and k == "parts" and v[k] is Dictionary:
				var parts := {}
				for pk in v[k]:
					var pv = v[k][pk]
					parts[pk] = _node(byName, str(pv)) if pv is String else _resolve(pv, byName)
				o[k] = parts
			elif top and k == "screens" and v[k] is Array:
				var scr: Array = []
				for s in v[k]:
					var s2 := {}
					if s is Dictionary:
						for sk in s:
							if sk == "node":
								s2["mesh"] = _node(byName, str(s[sk])) if s[sk] != null else null
							else:
								s2[sk] = _resolve(s[sk], byName)
					scr.append(s2)
				o[k] = scr
			else:
				o[k] = _resolve(v[k], byName)
		return o
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_resolve(x, byName))
		return a
	return v

func _node(byName: Dictionary, name: String):
	var n = byName.get(name)
	if n == null:
		n = byName.get(name.validate_node_name())
	if n == null:
		n = byName.get(name.replace(".", "_").replace(":", "_"))
	if n == null and not _warned.has("node:" + name):
		_warned["node:" + name] = true
		push_warning("[props] node '%s' referenced by userData not found" % name)
	return n

func _normalizeUserData(g: Node3D, id: String) -> void:
	var u := DAU.ud(g)
	if not u.get("id"):
		u["id"] = id
	for k in ["colliders", "screens", "lightAnchors"]:
		if not (u.get(k) is Array):
			u[k] = []
	if not (u.get("parts") is Dictionary):
		u["parts"] = {}
	if not u.has("interact"):
		u["interact"] = null
	if u.get("size") == null:
		var bb := _localAabb(g)
		u["size"] = [_r3(bb.size.x), _r3(bb.size.y), _r3(bb.size.z)]

static func _r3(n: float) -> float:
	return roundf(n * 1000.0) / 1000.0

static func _localAabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var t: Transform3D = e[1]
		if n is VisualInstance3D:
			var bb: AABB = t * (n as VisualInstance3D).get_aabb()
			if first:
				out = bb
				first = false
			else:
				out = out.merge(bb)
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, t * (c as Node3D).transform])
	return out

# ------------------------------------------------------------------------------------------------ clone
# JS cloneProp: a deep copy whose userData node references point at the copy's nodes.
func cloneProp(src: Node3D) -> Node3D:
	var c: Node3D = src.duplicate()
	var map := {}
	_walk2(src, c, map)
	for a in map:
		var b: Node = map[a]
		if a.has_meta("userData"):
			b.set_meta("userData", _remap(a.get_meta("userData"), map))
	return c

static func _walk2(a: Node, b: Node, map: Dictionary) -> void:
	map[a] = b
	for i in mini(a.get_child_count(), b.get_child_count()):
		_walk2(a.get_child(i), b.get_child(i), map)

static func _remap(v, map: Dictionary):
	if v is Node:
		return map.get(v, v)
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_remap(x, map))
		return a
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _remap(v[k], map)
		return o
	return v

# ------------------------------------------------------------------------------------------------ placeProp
func place(parent: Node, id: String, o: Dictionary = {}) -> Node3D:
	var pos = o.get("pos", [0, 0, 0])
	var rotY := float(o.get("rotY", 0.0))
	var opts: Dictionary = o.get("opts", {}) if o.get("opts") is Dictionary else {}
	var area = o.get("area")
	var tag = o.get("tag", "prop")
	var g := build(id, opts)
	if g == null:
		return null
	var p := DAU.v3(pos)
	g.position = Vector3(p.x, p.y, p.z)
	g.rotation = Vector3(0, rotY, 0)
	parent.add_child(g)
	var M: Transform3D = g.global_transform if g.is_inside_tree() else _worldOf(g)
	var u := DAU.ud(g)
	var col = game.level.get("col") if game.level != null else null
	if o.get("colliders", true) and col != null:
		for c in u.colliders:
			var mn := DAU.v3(c.min)
			var mx := DAU.v3(c.max)
			var bb := AABB()
			for i in 8:
				var v := M * Vector3(mx.x if i & 1 else mn.x, mx.y if i & 2 else mn.y, mx.z if i & 4 else mn.z)
				if i == 0:
					bb = AABB(v, Vector3.ZERO)
				else:
					bb = bb.expand(v)
			var copts := {"tag": tag}
			if c.get("opts") is Dictionary:
				copts.merge(c.opts, true)
			col.addBox(DAU.arr3(bb.position), DAU.arr3(bb.end), copts)
	if o.get("lights", true) and game.lights != null and game.lights.has_method("addAnchor"):
		for a in u.lightAnchors:
			var la: Dictionary = a.duplicate()
			la["pos"] = DAU.arr3(M * DAU.v3(a.pos))
			la["area"] = a.get("area") if a.get("area") != null else area
			game.lights.addAnchor(la)
	if o.get("screens", true) and game.screens != null and game.screens.has_method("register"):
		for s in u.screens:
			game.screens.register(s.get("mesh"), s.get("group") if s.get("group") else "scr_decor", {"id": s.id} if s.get("id") else {})
	return g

func placeProp(parent: Node, id: String, o: Dictionary = {}) -> Node3D:
	return place(parent, id, o)

static func _worldOf(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
