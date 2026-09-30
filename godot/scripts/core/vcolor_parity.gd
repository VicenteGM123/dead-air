extends Node
# WebGL vertex-colour parity (engine glue, no JS module). In the JS build kit.finish gives a color attribute only to
# meshes whose material is a toon (daToon) material at build time; glow / basic / screen parts get none. When such a
# part later draws with a vertexColors material (a runtime swap: an unpowered sponsor sign or softbox, the telly lamp
# off, the yard tower beacon, ...), three.js leaves the attribute disabled and WebGL reads its constant (0, 0, 0, 1):
# the diffuse term goes black (rim, emissive and fog still apply). Godot feeds a missing COLOR as white instead.
#
# game.gd adds one of these: it watches every MeshInstance3D (the tree at start + SceneTree.node_added) whose mesh has
# surfaces without a COLOR stream that were built with a non-toon material, and the first time the node draws with a
# vertexColors material (uVColor) it gets a per-node mesh copy with a black COLOR stream on those surfaces (LODs and
# blend shapes kept). Checked once per frame, late (process_priority), so a swap made during a frame shows correctly
# in that frame. A node with the meta "vcolor_white" is skipped (JS geometry that got a white color attribute, e.g. the
# room kit's mergeInto, whose parts Godot keeps as separate meshes). Systems that swap and want it at once call VColorParity.apply(mi) (static).

const PRIORITY := 100000

var _pending: Array = []
var _watch := {}   # instance id -> {node: WeakRef, mat: last material_override, surf: [surface indices]}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = PRIORITY
	get_tree().node_added.connect(_onAdded)
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		_pending.append(n)

func _onAdded(n: Node) -> void:
	if n is MeshInstance3D:
		_pending.append(n)

func _process(_dt: float) -> void:
	if not _pending.is_empty():
		var p := _pending
		_pending = []
		for n in p:
			if is_instance_valid(n) and not _watch.has(n.get_instance_id()):
				_consider(n)
	for id in _watch.keys():
		var w: Dictionary = _watch[id]
		var n = w.node.get_ref()
		if n == null or not is_instance_valid(n):
			_watch.erase(id)
			continue
		var m = n.material_override
		if m == w.mat:
			continue
		if n.has_meta("vcolor_white"):
			_watch.erase(id)
			continue
		w.mat = m
		if isVColor(m):
			_convert(n, w.surf)
			_watch.erase(id)

func _consider(mi: MeshInstance3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null or mi.has_meta("vcolor_white"):
		return
	var surf := []
	for s in src.get_surface_count():
		if src.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR:
			continue
		var built = src.surface_get_material(s)
		if built == null:
			built = mi.material_override
		if not isToon(built):
			surf.append(s)
	if surf.is_empty():
		return
	var m = mi.material_override
	if isVColor(m):
		_convert(mi, surf)
		return
	_watch[mi.get_instance_id()] = {"node": weakref(mi), "mat": m, "surf": surf}

# A toon (daToon) material: kit.finish turned it into a vertexColors variant and gave the geometry colors.
static func isToon(m) -> bool:
	if m == null:
		return false
	if m is DAMaterial and m.userData.has("daToon"):
		return true
	return String(m.resource_name).begins_with("toon")

static func isVColor(m) -> bool:
	if not (m is ShaderMaterial):
		return false
	var v = m.get_shader_parameter("uVColor")
	return (v is float or v is int) and v > 0.5

# Immediate form for a system that swaps the material itself: every surface without a COLOR stream reads black.
static func apply(mi: MeshInstance3D) -> void:
	if mi == null or not isVColor(mi.material_override):
		return
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var surf := []
	for s in src.get_surface_count():
		if not (src.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR):
			surf.append(s)
	if not surf.is_empty():
		_convert(mi, surf)

static func _convert(mi: MeshInstance3D, surf: Array) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null or src.has_meta("vcolor_black"):
		return
	var out := ArrayMesh.new()
	out.blend_shape_mode = src.blend_shape_mode
	for i in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(i))
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if s in surf and not (src.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR):
			var col := PackedColorArray()
			col.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			col.fill(Color(0, 0, 0, 1))
			arr[Mesh.ARRAY_COLOR] = col
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr, src.surface_get_blend_shape_arrays(s), _lods(src, s, arr))
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	out.custom_aabb = src.custom_aabb
	out.set_meta("vcolor_black", true)
	mi.mesh = out

# The surface's LOD index buffers ({edge length: PackedInt32Array}) from the RenderingServer data.
static func _lods(src: ArrayMesh, s: int, arr: Array) -> Dictionary:
	var out := {}
	var d := RenderingServer.mesh_get_surface(src.get_rid(), s)
	var lods = d.get("lods", [])
	var idx = arr[Mesh.ARRAY_INDEX]
	if not (lods is Array) or lods.is_empty() or not (idx is PackedInt32Array) or idx.is_empty():
		return out
	var main: PackedByteArray = d.get("index_data", PackedByteArray())
	var w: int = main.size() / idx.size()
	for l in lods:
		var b: PackedByteArray = l.get("index_data", PackedByteArray())
		var ids := PackedInt32Array()
		if w == 2:
			ids.resize(b.size() / 2)
			for i in ids.size():
				ids[i] = b.decode_u16(i * 2)
		elif w == 4:
			ids = b.to_int32_array()
		else:
			continue
		out[float(l.get("edge_length", 0.0))] = ids
	return out
