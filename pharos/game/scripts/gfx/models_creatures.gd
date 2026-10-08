class_name ModelsCreatures
## Factory for the creatures of Nyx (rigs), plus the small modelling kit they share. Every child of Nyx is made
## of night sky (shaders/nyx.gdshader): deep indigo bodies with stars inside, a soft rim, glowing slanted eyes in
## a dark void and, now and then, a little silver crescent. No faces, no mouths.

## Shared palette of the night-sky bodies (sRGB vertex colours; alpha 0.5 = self-lit).
const VOID := Color("06040F")
const BODY_LOW := Color("0A081C")
const BODY_HIGH := Color("2B2160")
const SILVER := Color(0.62, 0.6, 0.78, 0.5)
const SILVER_DIM := Color(0.42, 0.42, 0.56, 0.5)

static var _mesh_cache := {}


static func make(type: String) -> Rig:
	match type:
		"ker":
			return RigKer.new()
		"shielded":
			return RigShielded.new()
		"archer":
			return RigNyxArcher.new()
		"cyclops":
			return RigCyclops.new()
		"hydra":
			return RigHydra.new()
	return RigShade.new()


## Creatures come by dozens: their meshes are built once and shared by every instance.
static func cached(key: String, build: Callable) -> Mesh:
	var m: Mesh = _mesh_cache.get(key)
	if m == null:
		m = build.call()
		_mesh_cache[key] = m
	return m


## A slanted almond eye (self-lit). `tilt` > 0 lifts the outer corner; `side` is -1 (left) or +1 (right).
static func eye(mb: MeshBuilder, pos: Vector3, size: float, side: float, tilt: float, col: Color, depth: float = 0.5, yaw: float = 0.0) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt * side), pos))
	mb.ico(Vector3.ZERO, size, col, 0, 0.0, Vector3(1.55, 0.5, depth))
	mb.pop()


## Thin silver crescent made of short limbs, in the XY plane of the current transform (opens upward by default).
static func crescent_wire(mb: MeshBuilder, c: Vector3, r: float, thick: float, col: Color, open: float = 2.2, segs: int = 7) -> void:
	var prev := Vector3.ZERO
	for i in segs:
		var a := lerpf(-open, open, float(i) / float(segs - 1))
		var p := c + Vector3(sin(a) * r, cos(a) * r, 0)
		if i > 0:
			mb.limb(prev, p, thick, thick, 4, col)
		prev = p


## Flat crescent moon in the XY plane facing -Z, horns pointing toward +Y and -Y when `rot` = 0 (belly toward -X).
## `bulge(x, y)` is an optional Callable returning the z of the surface it lies on.
static func crescent_flat(mb: MeshBuilder, c: Vector3, r_out: float, inner_off: float, thick: float, col: Color, segs: int = 12, rot: float = 0.0) -> void:
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var r_in := r_out * 0.86
	for i in segs + 1:
		var k := float(i) / float(segs)
		# Outer arc spans the left half-circle; the inner arc is a circle shifted toward the open side.
		var a := lerpf(PI * 0.5, PI * 1.5, k)
		var po := Vector2(cos(a), sin(a)) * r_out
		var ang_in := lerpf(PI * 0.5, PI * 1.5, k)
		var pi_ := Vector2(cos(ang_in) * r_in + inner_off, sin(ang_in) * r_in * 0.98)
		# Horns meet: blend the inner arc onto the outer one at both ends.
		var e := pow(absf(k - 0.5) * 2.0, 6.0)
		pi_ = pi_.lerp(po, e)
		var rp := po.rotated(rot)
		var ri := pi_.rotated(rot)
		outer.append(c + Vector3(rp.x, rp.y, 0))
		inner.append(c + Vector3(ri.x, ri.y, 0))
	var dz := Vector3(0, 0, thick)
	for i in segs:
		# front (-Z)
		mb.quad(outer[i] - dz * 0.5, inner[i] - dz * 0.5, inner[i + 1] - dz * 0.5, outer[i + 1] - dz * 0.5, col)
		# back
		mb.quad(outer[i + 1] + dz * 0.5, inner[i + 1] + dz * 0.5, inner[i] + dz * 0.5, outer[i] + dz * 0.5, col)
		# edges
		mb.quad(outer[i] + dz * 0.5, outer[i] - dz * 0.5, outer[i + 1] - dz * 0.5, outer[i + 1] + dz * 0.5, col)
		mb.quad(inner[i + 1] + dz * 0.5, inner[i + 1] - dz * 0.5, inner[i] - dz * 0.5, inner[i] + dz * 0.5, col)


## Double-sided ribbon between two matched polylines (wings, fins, capes). `col` is a Color or a
## Callable(k: float, edge: float) -> Color, k = 0..1 along the strip, edge = 0 on `a`, 1 on `b`.
static func strip(mb: MeshBuilder, a: Array, b: Array, col: Variant, double_sided: bool = true) -> void:
	var n := mini(a.size(), b.size())
	for i in n - 1:
		var k := (float(i) + 0.5) / float(n - 1)
		var c: Color = col.call(k, 0.5) if col is Callable else col
		var p0: Vector3 = a[i]
		var p1: Vector3 = a[i + 1]
		var q1: Vector3 = b[i + 1]
		var q0: Vector3 = b[i]
		mb.tri(p0, p1, q1, c)
		mb.tri(p0, q1, q0, c)
		if double_sided:
			mb.tri(p0, q1, p1, c)
			mb.tri(p0, q0, q1, c)


## Body colour of the night-sky creatures: darker at the hem, lighter up high.
static func sky_grad(y: float, top: float, low: Color = BODY_LOW, high: Color = BODY_HIGH) -> Color:
	var k := clampf(y / top, 0.0, 1.0)
	return low.lerp(high, k * k)


## Right-handed frame whose Z is `z_hint` and whose X follows `x_axis` (projected). For placing flat details
## (eyes, ornaments) on curved surfaces without flipping their winding.
static func frame(x_axis: Vector3, z_hint: Vector3) -> Basis:
	var z := z_hint.normalized()
	var x := (x_axis - z * x_axis.dot(z)).normalized()
	return Basis(x, z.cross(x), z)


## Bone binding along a chain built straight up +Y: bone j sits at y = j * seg. Vertices are rigid to a bone in
## the middle of its segment and blend smoothly around each joint. Returns Vector3(bone_a, bone_b, weight_b).
static func chain_weight(p: Vector3, seg: float, count: int) -> Vector3:
	var u := p.y / seg
	var j := clampi(roundi(u), 0, count - 1)
	if j == 0:
		return Vector3(0, 0, 0)
	var k := clampf(u - float(j) + 0.5, 0.0, 1.0)
	return Vector3(j - 1, j, k * k * (3.0 - 2.0 * k))


## Commits several builders as one skinned mesh. `parts` = [[MeshBuilder, binding], ...] where binding is an int
## (every vertex rigid to that bone) or a Callable(v: Vector3) -> Vector3(bone_a, bone_b, weight_b).
static func commit_skinned(parts: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for part in parts:
		var mb: MeshBuilder = part[0]
		var bind: Variant = part[1]
		for i in mb._v.size():
			var p: Vector3 = mb._v[i]
			v.append(p)
			n.append(mb._n[i])
			c.append(mb._c[i])
			if bind is int:
				bones.append_array([bind, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
			else:
				var r: Vector3 = (bind as Callable).call(p)
				bones.append_array([int(r.x), int(r.y), 0, 0])
				weights.append_array([1.0 - r.z, r.z, 0.0, 0.0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A chain of `count` bones straight up +Y (bone j at y = j * seg) under `parent`, skinning `mesh`. The mesh
## instance is registered on `rig` (flash, dissolve, tint) and gets a generous fixed AABB (no per-frame bounds).
static func make_chain(rig: Rig, parent: Node3D, count: int, seg: float, mesh: Mesh, mat: Material, shadow: bool = true) -> Skeleton3D:
	var sk := Skeleton3D.new()
	parent.add_child(sk)
	for i in count:
		var b := sk.add_bone("b%d" % i)
		if i > 0:
			sk.set_bone_parent(b, b - 1)
			sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, Vector3(0, seg, 0)))
			sk.set_bone_pose_position(b, Vector3(0, seg, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	rig.meshes.append(mi)
	return sk
