# DAU: tiny shared helpers for the JS -> GDScript port (no JS counterpart; engine glue only).
# THREE.MathUtils equivalents keep THREE's argument order (smoothstep(x, min, max) is NOT Godot's smoothstep(from,
# to, x)), plus converters between the JS data shapes ([x,y,z] arrays, '#hex' strings, userData) and Godot types.
class_name DAU

# ------------------------------------------------------------------------------------------------ THREE.MathUtils
static func smoothstep3(x: float, min_v: float, max_v: float) -> float:
	if x <= min_v:
		return 0.0
	if x >= max_v:
		return 1.0
	x = (x - min_v) / (max_v - min_v)
	return x * x * (3.0 - 2.0 * x)

static func smootherstep3(x: float, min_v: float, max_v: float) -> float:
	if x <= min_v:
		return 0.0
	if x >= max_v:
		return 1.0
	x = (x - min_v) / (max_v - min_v)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

# THREE.MathUtils.damp: frame-rate independent exponential approach.
static func damp(x: float, y: float, lambda_v: float, dt: float) -> float:
	return lerp(x, y, 1.0 - exp(-lambda_v * dt))

static func euclideanModulo(n: float, m: float) -> float:
	return fmod(fmod(n, m) + m, m)

static func mapLinear(x: float, a1: float, a2: float, b1: float, b2: float) -> float:
	return b1 + (x - a1) * (b2 - b1) / (a2 - a1)

static func inverseLerp(x: float, y: float, value: float) -> float:
	return (value - x) / (y - x) if x != y else 0.0

static func pingpong(x: float, length: float = 1.0) -> float:
	return length - absf(euclideanModulo(x, length * 2.0) - length)

static func randFloat(low: float, high: float) -> float:
	return low + randf() * (high - low)

static func randFloatSpread(r: float) -> float:
	return r * (0.5 - randf())

static func randInt(low: int, high: int) -> int:
	return low + int(floor(randf() * (high - low + 1)))

static func fract(x: float) -> float:
	return x - floorf(x)

# performance.now() in ms.
static func nowMs() -> float:
	return Time.get_ticks_usec() / 1000.0

# ------------------------------------------------------------------------------------------------ data shapes
# [x,y,z] | Vector3 | {x,y,z} -> Vector3 (missing y = 0, like the JS v3 helpers).
static func v3(p) -> Vector3:
	if p is Vector3:
		return p
	if p is Array or p is PackedFloat32Array or p is PackedFloat64Array:
		return Vector3(float(p[0]), float(p[1]) if p.size() > 1 and p[1] != null else 0.0, float(p[2]) if p.size() > 2 else 0.0)
	if p is Dictionary:
		return Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0)))
	return Vector3.ZERO

static func arr3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

# CSS/three colour input -> Color. Accepts Color, '#rgb', '#rrggbb', '#rrggbbaa', 'rgb()/rgba()', 0xRRGGBB ints.
static func color(c) -> Color:
	if c is Color:
		return c
	if c is int:
		return Color.hex((c << 8) | 0xFF)
	if c is String:
		var s: String = c.strip_edges()
		if s.begins_with("rgb"):
			var inner := s.substr(s.find("(") + 1).trim_suffix(")")
			var parts := inner.split(",")
			var a := float(parts[3]) if parts.size() > 3 else 1.0
			return Color(float(parts[0]) / 255.0, float(parts[1]) / 255.0, float(parts[2]) / 255.0, a)
		return Color.from_string(s, Color.WHITE)
	return Color.WHITE

static func hex(c: Color) -> String:
	return "#" + c.to_html(false)

# sRGB <-> linear (THREE.Color stores linear components when colour management is on).
static func srgbToLinear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)

static func linearToSrgb(c: float) -> float:
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055

# ------------------------------------------------------------------------------------------------ scene graph
# A Node3D whose Euler order matches three.js ('XYZ'); every node our code rotates should use this order.
static func node3d(name: String = "") -> Node3D:
	var n := Node3D.new()
	n.rotation_order = EULER_ORDER_XYZ
	if name != "":
		n.name = name
	return n

# object.userData: a Dictionary stored as the node's "userData" meta (props.gd fills it from the glTF extras).
static func ud(n: Object) -> Dictionary:
	if n == null:
		return {}
	if not n.has_meta("userData"):
		n.set_meta("userData", {})
	return n.get_meta("userData")

# three's object.layers.set(layer) on a whole subtree (only that layer).
static func setLayerRecursive(n: Node, layer: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 << layer
	for c in n.get_children():
		setLayerRecursive(c, layer)

# object.traverse(fn)
static func traverse(n: Node, fn: Callable) -> void:
	fn.call(n)
	for c in n.get_children():
		traverse(c, fn)

# First descendant (or self) whose name matches (object.getObjectByName).
static func byName(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	return n.find_child(name, true, false)

# World position of a node (object.getWorldPosition).
static func worldPos(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else n.transform.origin

# Removes a node from its parent (object.removeFromParent) without freeing it.
static func detach(n: Node) -> void:
	if n and n.get_parent():
		n.get_parent().remove_child(n)

# ------------------------------------------------------------------------------------------------ web / Compatibility
# True under the Compatibility (GL / WebGL2) renderer, the only one the web build has.
static var _compat = null
static func isCompat() -> bool:
	if _compat == null:
		_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	return _compat

# o.set_instance_shader_parameter("instanceColor", srgb). Under Compatibility the toon / unlit shaders declare
# instanceColor as a plain material uniform (the per-instance uniform buffer is too small for the level), so the
# instance gets its own copy of its ShaderMaterials (made once) and the colour is set on those.
static func setInstanceColor(o: GeometryInstance3D, srgb: Color) -> void:
	if not isCompat():
		o.set_instance_shader_parameter("instanceColor", srgb)
		return
	if o.material_override is ShaderMaterial:
		o.material_override = _ownMat(o.material_override, o)
		(o.material_override as ShaderMaterial).set_shader_parameter("instanceColor", srgb)
		return
	if o is MeshInstance3D and (o as MeshInstance3D).mesh != null:
		var mi := o as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			if m is ShaderMaterial:
				m = _ownMat(m, o)
				mi.set_surface_override_material(s, m)
				(m as ShaderMaterial).set_shader_parameter("instanceColor", srgb)

static func _ownMat(m: ShaderMaterial, o: Object) -> ShaderMaterial:
	if m.get_meta("_daInstOwn", 0) == o.get_instance_id():
		return m   # already this node's own copy (a duplicated node shares it until it gets one of its own)
	var d := m.duplicate() as ShaderMaterial
	d.set_meta("_daInstOwn", o.get_instance_id())
	return d
