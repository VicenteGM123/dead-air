class_name ModelsAnimals
## Ambient animals: cats, goats, seagulls, dolphins, butterflies and fireflies.
##
## Each animal is ONE skinned mesh (one draw call): the parts are built with MeshBuilder and every vertex is bound
## rigidly to a bone. Rigid parts (heads, legs, wings) follow one bone each; lofted parts (cat body and tail) get one
## bone per ring, so the spine can curl and the tail bends smoothly with no gaps. Bones have no parents and their
## poses are set every frame from code (eased pose blending + gait/breathing/sway overlays; no AnimationPlayer).
## Behaviour (where to go, when to sleep) lives in scripts/world/ambient*.gd, which drives the rigs through:
##   play(action)                  cat: stand sit loaf sleep stretch pet | goat: stand graze lie sleep hop
##                                 gull: glide flap | dolphin: swim leap
##   set_locomotion(speed, _ref)   walking speed in m/s (gait, bob); the rig does not move itself
##   look(yaw, pitch)              head offset relative to the body (radians), eased
##   step(dt, on_screen)           cats and goats with `driven = true`: the owner ticks them (full pose only on
##                                 screen); otherwise they animate themselves in _process (previews)
## Model space: +Z forward (unlike the character Rig class, which faces -Z; only Ambient orients these), +Y up,
## origin on the ground under the animal. No faces: no eyes, no mouths (art direction), just ears, muzzle colour
## and silhouette.
## In game, cat rigs are also Interactables (the hero pets them by holding Interact); see AmbientCat.
##
## The static functions at the bottom (cat_orange, goat, seagull, ...) take a seed and return a ready rig; they
## are what tools/preview.tscn calls.

const CAT_COATS := {
	"orange": {"pattern": "tabby", "base": Color("EB9C4E"), "dark": Color("C76F33"), "light": Color("F8E8CC"), "ear_in": Color("F0A8A2")},
	"black": {"pattern": "solid", "base": Color("3A3644"), "light": Color("4A4458"), "ear_in": Color("8A6474")},
	"white": {"pattern": "solid", "base": Color("F7F3EB"), "light": Color("FFFDF8"), "ear_in": Color("F0A8A2")},
	"grey": {"pattern": "solid", "base": Color("9199A8"), "light": Color("C3C8D2"), "ear_in": Color("D9A0A2")},
	"calico": {"pattern": "calico", "base": Color("F7F2E8"), "dark": Color("3A3644"), "orange": Color("E8923F"), "light": Color("F7F2E8"), "ear_in": Color("F0A8A2")},
	"tuxedo": {"pattern": "tuxedo", "base": Color("34303C"), "light": Color("F6F2EA"), "ear_in": Color("8A6474")},
}
const CAT_COAT_ORDER := ["orange", "calico", "tuxedo", "grey", "white", "black"]

# Cat proportions (metres, before the per-cat scale).
const CAT_LEG := 0.15
const MUZZLE := false
## Body rings along the spine (z = arc length from the hip joint), one bone each.
const CAT_ZS := [-0.065, -0.025, 0.02, 0.07, 0.12, 0.17, 0.215, 0.25]
const CAT_TAIL_N := 6 # tail segments (CAT_TAIL_N + 1 ring bones)
const CAT_TAIL_LEN := 0.37
const CAT_TAIL_R := [0.038, 0.036, 0.033, 0.03, 0.027, 0.025, 0.023]
# Bone layout of the cat skeleton.
const CB_HEAD := 8
const CB_LEG := 9
const CB_TAIL := 13
const CAT_BONES := 13 + CAT_TAIL_N + 1

static var _cache := {}
static var _noise: FastNoiseLite


# --- shared modelling helpers ------------------------------------------------------------------------------

static func _cached(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


## Tube along +Z through elliptical cross-sections (zs/rx/ry/yo arrays, same length). The ends close with fans to
## points cap0 behind the first section and cap1 beyond the last one. Default rotation puts a flat face on top.
static func loft(mb: MeshBuilder, zs: Array, rx: Array, ry: Array, yo: Array, sides: int, col: Color, cap0: float, cap1: float, rot: float = INF) -> void:
	if rot == INF:
		rot = fposmod(PI * 0.5 - PI / float(sides), TAU / float(sides))
	var rings: Array = []
	for k in zs.size():
		var ring := PackedVector3Array()
		for i in sides:
			var a := rot + TAU * float(i) / float(sides)
			ring.append(Vector3(cos(a) * float(rx[k]), sin(a) * float(ry[k]) + float(yo[k]), float(zs[k])))
		rings.append(ring)
	for k in zs.size() - 1:
		var r0: PackedVector3Array = rings[k]
		var r1: PackedVector3Array = rings[k + 1]
		for i in sides:
			var j := (i + 1) % sides
			mb.quad(r0[i], r0[j], r1[j], r1[i], col)
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[zs.size() - 1]
	var t0 := Vector3(0, float(yo[0]), float(zs[0]) - cap0)
	var t1 := Vector3(0, float(yo[zs.size() - 1]), float(zs[zs.size() - 1]) + cap1)
	for i in sides:
		var j := (i + 1) % sides
		mb.tri(t0, first[j], first[i], col)
		mb.tri(t1, last[i], last[j], col)


## Flat polygon facing +Y with its own colour on each side (wings, flukes, ears). Points in order, convex.
static func poly2(mb: MeshBuilder, pts: Array, top: Color, bottom: Color) -> void:
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var n := (b - a).cross(c - a)
		if n.y >= 0.0:
			mb.tri(a, b, c, top)
			mb.tri(a, c, b, bottom)
		else:
			mb.tri(a, c, b, top)
			mb.tri(a, b, c, bottom)


## Recolours every triangle added since vertex index `from` with fn.call(centroid, normal) -> Color, plus a small
## per-facet brightness variation (derived from the normal, so the two halves of a quad match).
static func paint(mb: MeshBuilder, from: int, fn: Callable, vary: float = 0.035) -> void:
	var cols := mb._c
	mb._c = PackedColorArray()
	var vs := mb._v
	var ns := mb._n
	var i := from
	while i + 2 < vs.size():
		var cen := (vs[i] + vs[i + 1] + vs[i + 2]) / 3.0
		var n := ns[i]
		var col: Color = fn.call(cen, n)
		if vary > 0.0:
			var h := sin(n.x * 127.1 + n.y * 311.7 + n.z * 74.7 + cen.x * 3.1) * 43758.5453
			var k := 1.0 + (h - floorf(h) - 0.5) * 2.0 * vary
			col = Color(clampf(col.r * k, 0.0, 1.0), clampf(col.g * k, 0.0, 1.0), clampf(col.b * k, 0.0, 1.0), col.a)
		cols[i] = col
		cols[i + 1] = col
		cols[i + 2] = col
		i += 3
	mb._c = cols


static func noise3(p: Vector3, seed_value: int) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise.seed = seed_value
	return _noise.get_noise_3dv(p)


static func _mi(mesh: Mesh, parent: Node3D, shadow: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = Materials.lowpoly()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m




## A skinned mesh under construction: geometry goes into `mb`, then rigid() / rings() bind every vertex added since
## the last call to a bone. Bones are unparented; a bone's bind is the inverse of its rest origin, so a lofted ring
## built at z = zs[k] sits at the bone's origin.
class SkinBuild:
	var mb: MeshBuilder
	var vb := PackedInt32Array()
	var binds: Array[Transform3D] = []

	func _init(seed_value: int = 1) -> void:
		mb = MeshBuilder.new(seed_value)

	func add_bone(rest_origin: Vector3 = Vector3.ZERO) -> int:
		binds.append(Transform3D(Basis.IDENTITY, -rest_origin))
		return binds.size() - 1

	func mark() -> int:
		return mb._v.size()

	## Everything added since the last bind follows `bone`.
	func rigid(bone: int) -> void:
		while vb.size() < mb._v.size():
			vb.append(bone)

	## Everything added since the last bind goes to the ring (bones first..first+zs.size()-1) nearest in z.
	func rings(first: int, zs: Array) -> void:
		for i in range(vb.size(), mb._v.size()):
			var z := mb._v[i].z
			var best := 0
			var bd := INF
			for k in zs.size():
				var d := absf(z - float(zs[k]))
				if d < bd:
					bd = d
					best = k
			vb.append(first + best)

	## [ArrayMesh, Skin]
	func commit() -> Array:
		rigid(0)
		var n := mb._v.size()
		var bones := PackedInt32Array()
		bones.resize(n * 4)
		var w := PackedFloat32Array()
		w.resize(n * 4)
		for i in n:
			bones[i * 4] = vb[i]
			w[i * 4] = 1.0
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mb._v
		arrays[Mesh.ARRAY_NORMAL] = MeshBuilder.smooth_normals(mb._v, mb._n, MeshBuilder.TOON_SMOOTH_DEG)
		arrays[Mesh.ARRAY_COLOR] = mb._c
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = w
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var skin := Skin.new()
		for b in binds.size():
			skin.add_bind(b, binds[b])
		return [m, skin]


static func _cached_skin(key: String, build: Callable) -> Array:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


## Skeleton (`count` unparented bones) + one skinned MeshInstance3D under `parent`. `box` is the culling box in the
## rig's space (skinned bounds are not tracked per frame).
static func _skinned(parent: Node3D, data: Array, count: int, shadow: bool, box: AABB) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for i in count:
		sk.add_bone("b%d" % i)
	parent.add_child(sk)
	var m := MeshInstance3D.new()
	m.name = "Mesh"
	m.mesh = data[0]
	m.skin = data[1]
	m.material_override = Materials.lowpoly()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.custom_aabb = box
	sk.add_child(m)
	m.skeleton = NodePath("..")
	return sk


## Frame for a tube ring: +Z along `dir`, X carried over from the previous ring (parallel transport, no twist).
static func ring_basis(dir: Vector3, prev_x: Vector3) -> Basis:
	var x := prev_x - dir * prev_x.dot(dir)
	if x.length_squared() < 1e-6:
		x = Vector3.UP.cross(dir)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, dir.cross(x), dir)


# --- cats --------------------------------------------------------------------------------------------------

## Coat colour of a cat facet. `role` is the part (body, head, muzzle, ear, leg, paw, tail), p/n the facet centroid
## and normal in that part's space, k a role parameter (tail: band index, ear: side).
static func cat_color(coat: Dictionary, role: String, p: Vector3, n: Vector3, k: float = 0.0) -> Color:
	var base: Color = coat["base"]
	var light: Color = coat.get("light", base)
	var dark: Color = coat.get("dark", base)
	match String(coat["pattern"]):
		"tabby":
			match role:
				"body":
					if n.y < -0.5:
						return light
					if n.z > 0.55 and p.y < 0.02:
						return light # bib
					if int(k) % 2 == 1 and n.y > -0.3 and absf(n.z) < 0.8:
						return dark
					return base
				"head":
					if n.y < -0.35 and n.z > -0.3:
						return light # chin
					if n.y > 0.45 and n.z > -0.35 and absf(p.x) < 0.075 and int(floorf((p.x + 0.2) / 0.034)) % 2 == 0:
						return dark # forehead stripes
					return base
				"muzzle":
					return light
				"ear":
					return dark if p.y > 0.165 else base
				"leg":
					return dark if int(floorf(-p.y / 0.05)) % 2 == 1 and n.y > -0.5 else base
				"paw":
					return light
				"tail":
					return dark if int(k) % 2 == 1 else base
			return base
		"tuxedo":
			match role:
				"body":
					if n.y < -0.35:
						return light
					if n.z > 0.35 and p.y < 0.05:
						return light
					return base
				"head":
					if n.y < -0.3 and n.z > -0.2:
						return light
					return base
				"muzzle", "paw":
					return light
			return base
		"calico":
			var orange: Color = coat["orange"]
			match role:
				"body":
					if n.y < -0.3:
						return base
					# Sampled per quad (normal + ring band) so patches follow the facets.
					var v := noise3(Vector3(n.x * 0.55, n.y * 0.55, k * 0.3), 17)
					if v > 0.18:
						return orange
					if v < -0.32:
						return dark
					return base
				"head":
					if n.y < -0.3 and n.z > -0.2:
						return base
					if p.x > 0.02 and n.y > -0.25 and n.z < 0.6:
						return orange
					if p.x < -0.03 and n.y > 0.35 and p.z < 0.02:
						return dark
					return base
				"ear":
					return orange if k > 0.0 else dark
				"tail":
					return dark if int(k) % 3 == 1 else orange
			return base
	# solid
	match role:
		"body":
			return light if n.y < -0.55 else base
		"muzzle":
			return base.lerp(light, 0.6)
		"head":
			return base.lerp(light, 0.5) if (n.y < -0.4 and n.z > -0.2) else base
	return base



## The whole cat as one skinned mesh: [ArrayMesh, Skin]. Bones: 0-7 body rings, 8 head, 9-12 legs (FL FR HL HR),
## 13.. tail rings (root to tip).
static func cat_skin(coat_name: String) -> Array:
	return _cached_skin("cat_" + coat_name, func() -> Array: return _build_cat(coat_name))


static func _build_cat(coat_name: String) -> Array:
	var coat: Dictionary = CAT_COATS.get(coat_name, CAT_COATS["orange"])
	var sb := SkinBuild.new(coat_name.hash())
	var mb := sb.mb
	# Body: a loft along the spine, origin at the hip joint, chest towards +Z.
	var zs := CAT_ZS
	for z in zs:
		sb.add_bone(Vector3(0, 0, float(z)))
	loft(mb, zs, [0.086, 0.108, 0.119, 0.122, 0.121, 0.117, 0.108, 0.09],
		[0.088, 0.11, 0.12, 0.122, 0.12, 0.12, 0.114, 0.098], [0.012, 0.005, 0.001, 0.0, 0.0, 0.005, 0.01, 0.013], 8, Color.WHITE, 0.05, 0.05)
	paint(mb, 0, func(p: Vector3, n: Vector3) -> Color:
		var band := 0
		for z in zs:
			if p.z > float(z):
				band += 1
		return cat_color(coat, "body", p, n, float(band)))
	sb.rings(0, zs)
	# Head (origin at the neck joint): round, big ears, a soft muzzle. No eyes, no mouth.
	sb.add_bone()
	var c := Vector3(0, 0.10, 0.07)
	var s := sb.mark()
	mb.ico(c, 0.14, Color.WHITE, 1, 0.0, Vector3(1.12, 0.92, 0.98))
	paint(mb, s, func(p: Vector3, n: Vector3) -> Color: return cat_color(coat, "head", p - c, n))
	if MUZZLE:
		s = sb.mark()
		mb.ico(c + Vector3(0, -0.032, 0.104), 0.046, Color.WHITE, 0, 0.0, Vector3(1.32, 0.66, 0.86))
		paint(mb, s, func(p: Vector3, n: Vector3) -> Color: return cat_color(coat, "muzzle", p - c, n))
	for sx in [-1.0, 1.0]:
		var side: float = sx
		mb.push(Transform3D(Basis(Vector3.BACK, -side * 0.30) * Basis(Vector3.RIGHT, -0.10), c + Vector3(side * 0.074, 0.092, -0.008)))
		s = sb.mark()
		var r := 0.058
		var h := 0.112
		mb.cyl(Vector3.ZERO, h, r, 0.0, 3, Color.WHITE, true, deg_to_rad(30.0))
		paint(mb, s, func(p: Vector3, n: Vector3) -> Color: return cat_color(coat, "ear", p - c, n, side), 0.0)
		# Inner ear on the front face.
		var b0 := Vector3(cos(deg_to_rad(30.0)), 0, sin(deg_to_rad(30.0))) * r
		var b1 := Vector3(cos(deg_to_rad(150.0)), 0, sin(deg_to_rad(150.0))) * r
		var ap := Vector3(0, h, 0)
		var nf := (ap - b0).cross(b1 - b0).normalized()
		var g := (b0 + b1 + ap) / 3.0 - Vector3(0, 0.012, 0)
		var sh := 0.58
		mb.tri(g + (b0 - g) * sh + nf * 0.004, g + (ap - g) * sh + nf * 0.004, g + (b1 - g) * sh + nf * 0.004, coat["ear_in"])
		mb.pop()
	sb.rigid(CB_HEAD)
	# Legs (origin at the shoulder / hip joint, hanging down -Y). The rig scales them in Y to reach the ground.
	for i in 4:
		sb.add_bone()
		s = sb.mark()
		mb.limb(Vector3(0, 0.03, 0), Vector3(0, -CAT_LEG + 0.02, 0), 0.044, 0.039, 6, Color.WHITE)
		paint(mb, s, func(p: Vector3, n: Vector3) -> Color: return cat_color(coat, "leg", p, n))
		s = sb.mark()
		mb.ico(Vector3(0, -CAT_LEG + 0.02, 0.012), 0.042, Color.WHITE, 0, 0.0, Vector3(1.05, 0.55, 1.3))
		paint(mb, s, func(p: Vector3, n: Vector3) -> Color: return cat_color(coat, "paw", p, n))
		sb.rigid(CB_LEG + i)
	# Tail: a tapered tube along +Z (root to tip), one bone per ring.
	var seg := CAT_TAIL_LEN / float(CAT_TAIL_N)
	var tz := []
	var trx := []
	var tyo := []
	for k in CAT_TAIL_N + 1:
		tz.append(seg * float(k))
		trx.append(CAT_TAIL_R[k])
		tyo.append(0.0)
		sb.add_bone(Vector3(0, 0, seg * float(k)))
	s = sb.mark()
	loft(mb, tz, trx, trx, tyo, 6, Color.WHITE, 0.012, 0.026)
	paint(mb, s, func(p: Vector3, n: Vector3) -> Color:
		return cat_color(coat, "tail", p, n, float(clampi(int(p.z / seg), 0, CAT_TAIL_N - 1))))
	sb.rings(CB_TAIL, tz)
	return sb.commit()


# --- goats -------------------------------------------------------------------------------------------------

const GOAT_COATS := {
	"white": {"base": Color("F1EDE3"), "light": Color("E6D9CF"), "dark": Color("D9D0C1"), "horn": Color("A8957A"), "hoof": Color("4A3F38"), "patch": false},
	"brown": {"base": Color("93603F"), "light": Color("CDA172"), "dark": Color("66432D"), "horn": Color("CFC1A6"), "hoof": Color("3A302A"), "patch": false},
	"cream": {"base": Color("E4CFA4"), "light": Color("F4E8CF"), "dark": Color("C4AC80"), "horn": Color("7B6A57"), "hoof": Color("4A3F38"), "patch": false},
	"pied": {"base": Color("F1EDE3"), "light": Color("E6D9CF"), "dark": Color("93603F"), "horn": Color("6E6052"), "hoof": Color("3A302A"), "patch": true},
}
const GOAT_LEG := 0.30


static func goat_color(coat: Dictionary, role: String, p: Vector3, n: Vector3) -> Color:
	var base: Color = coat["base"]
	var light: Color = coat["light"]
	var dark: Color = coat["dark"]
	var pied: bool = coat["patch"]
	match role:
		"body":
			if pied and n.y > -0.5 and noise3(Vector3(n.x * 0.6, n.y * 0.6, p.z * 3.2), 5) > -0.02:
				return dark
			if n.y < -0.6:
				return base.lerp(light, 0.5)
			return base
		"head", "neck":
			return dark if pied else base
		"muzzle":
			return light if not pied else dark.lerp(light, 0.5)
		"ear":
			return dark if pied else base
		"ear_in":
			return Color("D9A79E")
		"leg":
			return base if pied else base.lerp(dark, 0.4)
		"hoof":
			return coat["hoof"]
		"horn":
			return coat["horn"]
		"beard":
			return base.darkened(0.1) if not pied else base
	return base


## The whole goat as one skinned mesh: [ArrayMesh, Skin]. Bones: 0 body, 1 head (with neck), 2-5 legs.
static func goat_skin(coat_name: String, kid: bool) -> Array:
	return _cached_skin("goat_%s_%s" % [coat_name, kid], func() -> Array:
		var sb := SkinBuild.new(coat_name.hash())
		for part in ["body", "head_kid" if kid else "head", "leg", "leg", "leg", "leg"]:
			_add_goat_part(sb.mb, coat_name, part)
			sb.rigid(sb.add_bone())
		return sb.commit())


static func _add_goat_part(mb: MeshBuilder, coat_name: String, part: String) -> void:
	var coat: Dictionary = GOAT_COATS.get(coat_name, GOAT_COATS["white"])
	var s0 := mb._v.size()
	match part:
		"body":
			# Body space: origin at the body centre.
			var zs := [-0.30, -0.24, -0.12, 0.0, 0.12, 0.22, 0.29]
			loft(mb, zs, [0.12, 0.165, 0.185, 0.19, 0.185, 0.17, 0.135],
				[0.13, 0.17, 0.19, 0.195, 0.195, 0.185, 0.15], [0.03, 0.01, -0.01, -0.02, 0.0, 0.025, 0.04], 8, Color.WHITE, 0.06, 0.05)
			paint(mb, s0, func(p: Vector3, n: Vector3) -> Color:
				# Snap z to the middle of the ring band so both triangles of a quad agree.
				var zc := -0.36
				for k in zs.size() - 1:
					if p.z > float(zs[k]) and p.z <= float(zs[k + 1]):
						zc = (float(zs[k]) + float(zs[k + 1])) * 0.5
				if p.z > float(zs[zs.size() - 1]):
					zc = 0.34
				return goat_color(coat, "body", Vector3(p.x, p.y, zc), n))
			var s := mb._v.size()
			mb.limb(Vector3(0, 0.10, -0.32), Vector3(0, 0.24, -0.40), 0.042, 0.008, 5, Color.WHITE)
			paint(mb, s, func(p: Vector3, n: Vector3) -> Color: return goat_color(coat, "body", p, n))
		"head", "head_kid":
			# Head space: origin at the neck pivot. Neck up-forward, head tilted nose-down.
			var kid := part == "head_kid"
			mb.limb(Vector3(0, -0.05, -0.04), Vector3(0, 0.19, 0.08), 0.088, 0.072, 6, Color.WHITE)
			paint(mb, s0, func(p: Vector3, n: Vector3) -> Color: return goat_color(coat, "neck", p, n))
			var hx := Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0, 0.22, 0.09))
			var inv := hx.affine_inverse()
			mb.push(hx)
			var s := mb._v.size()
			loft(mb, [-0.06, 0.02, 0.10, 0.165], [0.074, 0.084, 0.07, 0.052], [0.085, 0.092, 0.076, 0.056], [0.0, 0.0, -0.005, -0.01], 6, Color.WHITE, 0.03, 0.03)
			paint(mb, s, func(p: Vector3, n: Vector3) -> Color:
				return goat_color(coat, "muzzle" if (inv * p).z > 0.125 else "head", p, n))
			for sx in [-1.0, 1.0]:
				var e: float = sx
				var ear := [Vector3(e * 0.055, 0.05, -0.035), Vector3(e * 0.06, 0.055, 0.025), Vector3(e * 0.15, 0.0, 0.015), Vector3(e * 0.175, -0.025, -0.015), Vector3(e * 0.14, -0.005, -0.045)]
				poly2(mb, ear, goat_color(coat, "ear", Vector3.ZERO, Vector3.UP), goat_color(coat, "ear_in", Vector3.ZERO, Vector3.UP))
				if not kid:
					var hp := [Vector3(e * 0.034, 0.065, -0.035), Vector3(e * 0.046, 0.13, -0.075), Vector3(e * 0.058, 0.16, -0.15), Vector3(e * 0.064, 0.135, -0.22)]
					var hr := [0.027, 0.02, 0.013, 0.004]
					for k in 3:
						mb.limb(hp[k], hp[k + 1], hr[k], hr[k + 1], 5, coat["horn"])
				else:
					mb.cyl(Vector3(e * 0.034, 0.06, -0.03), 0.04, 0.022, 0.006, 5, coat["horn"])
			var s2 := mb._v.size()
			mb.limb(Vector3(0, -0.055, 0.11), Vector3(0, -0.13, 0.075), 0.026, 0.004, 4, Color.WHITE)
			paint(mb, s2, func(p: Vector3, n: Vector3) -> Color: return goat_color(coat, "beard", p, n))
			mb.pop()
		"leg":
			mb.limb(Vector3(0, 0.04, 0), Vector3(0, -GOAT_LEG + 0.05, 0), 0.05, 0.04, 5, Color.WHITE)
			paint(mb, s0, func(p: Vector3, n: Vector3) -> Color: return goat_color(coat, "leg", p, n))
			mb.block(Vector3(0, -GOAT_LEG, 0.008), Vector3(0.078, 0.062, 0.09), coat["hoof"])


# --- seagulls ----------------------------------------------------------------------------------------------

const GULL_WHITE := Color("F7F6F2")
const GULL_GREY := Color("B3BDCA")
const GULL_DARK := Color("2D2B36")
const GULL_BEAK := Color("F2C14E")


## The gull as one skinned mesh: [ArrayMesh, Skin]. Bones: 0 body, 1-2 inner wings (r, l), 3-4 outer wings (r, l).
static func gull_skin() -> Array:
	return _cached_skin("gull", func() -> Array:
		var sb := SkinBuild.new(3)
		for part in ["body", "wing_in_r", "wing_in_l", "wing_out_r", "wing_out_l"]:
			_add_gull_part(sb.mb, part)
			sb.rigid(sb.add_bone())
		return sb.commit())


static func _add_gull_part(mb: MeshBuilder, part: String) -> void:
	var s0 := mb._v.size()
	match part:
		"body":
			loft(mb, [-0.22, -0.14, -0.04, 0.06, 0.13, 0.19, 0.235], [0.03, 0.066, 0.086, 0.083, 0.06, 0.063, 0.043],
				[0.022, 0.058, 0.08, 0.078, 0.06, 0.065, 0.045], [0.012, 0.0, 0.0, 0.008, 0.035, 0.056, 0.052], 8, Color.WHITE, 0.03, 0.035)
			paint(mb, s0, func(p: Vector3, n: Vector3) -> Color: return GULL_GREY if (n.y > 0.55 and p.z < 0.09) else GULL_WHITE, 0.02)
			mb.limb(Vector3(0, 0.046, 0.255), Vector3(0, 0.034, 0.335), 0.022, 0.006, 4, GULL_BEAK)
			poly2(mb, [Vector3(-0.055, 0.012, -0.19), Vector3(0.055, 0.012, -0.19), Vector3(0.07, 0.016, -0.30), Vector3(-0.07, 0.016, -0.30)], GULL_WHITE, GULL_WHITE)
		"wing_in_r", "wing_in_l":
			var sx := 1.0 if part.ends_with("r") else -1.0
			poly2(mb, [Vector3(0, 0, 0.075), Vector3(sx * 0.30, 0, 0.055), Vector3(sx * 0.30, 0, -0.10), Vector3(0, 0, -0.13)], GULL_GREY, GULL_WHITE)
		"wing_out_r", "wing_out_l":
			var sx := 1.0 if part.ends_with("r") else -1.0
			poly2(mb, [Vector3(0, 0, 0.055), Vector3(sx * 0.19, 0, 0.032), Vector3(sx * 0.21, 0, -0.085), Vector3(0, 0, -0.10)], GULL_GREY, GULL_WHITE)
			poly2(mb, [Vector3(sx * 0.19, 0, 0.032), Vector3(sx * 0.34, 0, -0.03), Vector3(sx * 0.21, 0, -0.085)], GULL_DARK, GULL_DARK)


# --- dolphins ----------------------------------------------------------------------------------------------

const DOLPHIN_TOP := Color("566F8E")
const DOLPHIN_MID := Color("7D96B1")
const DOLPHIN_BELLY := Color("CAD6DF")


## The dolphin as one skinned mesh: [ArrayMesh, Skin]. Bones: 0 body, 1 flukes.
static func dolphin_skin() -> Array:
	return _cached_skin("dolphin", func() -> Array:
		var sb := SkinBuild.new(9)
		for part in ["body", "flukes"]:
			_add_dolphin_part(sb.mb, part)
			sb.rigid(sb.add_bone())
		return sb.commit())


static func _dolphin_col(n: Vector3) -> Color:
	if n.y > 0.3:
		return DOLPHIN_TOP
	if n.y < -0.35:
		return DOLPHIN_BELLY
	return DOLPHIN_MID


static func _add_dolphin_part(mb: MeshBuilder, part: String) -> void:
	var s0 := mb._v.size()
	match part:
		"body":
			# Origin at the body centre; the flukes hang off the tail stock at z = -0.92.
			loft(mb, [-0.92, -0.75, -0.5, -0.2, 0.15, 0.45, 0.66, 0.8], [0.045, 0.085, 0.15, 0.205, 0.22, 0.195, 0.15, 0.09],
				[0.075, 0.12, 0.18, 0.225, 0.23, 0.2, 0.15, 0.09], [0.07, 0.05, 0.03, 0.01, 0.0, 0.0, 0.012, 0.0], 8, Color.WHITE, 0.03, 0.05)
			paint(mb, s0, func(_p: Vector3, n: Vector3) -> Color: return _dolphin_col(n), 0.025)
			var s := mb._v.size()
			mb.limb(Vector3(0, -0.035, 0.80), Vector3(0, -0.05, 1.0), 0.06, 0.036, 6, Color.WHITE)
			mb.ico(Vector3(0, -0.05, 1.0), 0.036, Color.WHITE, 0)
			paint(mb, s, func(_p: Vector3, n: Vector3) -> Color: return _dolphin_col(n), 0.0)
			mb.plate([Vector3(0, 0.19, 0.22), Vector3(0, 0.33, 0.07), Vector3(0, 0.5, -0.13), Vector3(0, 0.42, -0.14), Vector3(0, 0.21, -0.17)], DOLPHIN_TOP)
			for sx in [-1.0, 1.0]:
				var e: float = sx
				poly2(mb, [Vector3(e * 0.17, -0.09, 0.44), Vector3(e * 0.37, -0.21, 0.29), Vector3(e * 0.33, -0.2, 0.21), Vector3(e * 0.16, -0.11, 0.31)], DOLPHIN_MID, DOLPHIN_BELLY)
		"flukes":
			for sx in [-1.0, 1.0]:
				var e: float = sx
				var a := Vector3(0, 0, 0.04)
				var b := Vector3(e * 0.31, 0, -0.13)
				var c := Vector3(e * 0.27, 0, -0.22)
				var d := Vector3(e * 0.08, 0, -0.12)
				var f := Vector3(0, 0, -0.15)
				poly2(mb, [a, b, d], DOLPHIN_TOP, DOLPHIN_MID)
				poly2(mb, [d, b, c], DOLPHIN_TOP, DOLPHIN_MID)
				poly2(mb, [a, d, f], DOLPHIN_TOP, DOLPHIN_MID)


# --- butterflies, fireflies, fx ----------------------------------------------------------------------------

## One butterfly wing (+X side) with half of the body; white so a MultiMesh instance colour (or the `tint`
## material parameter, see Materials.set_param) colours it. Both faces are identical, so the other wing is the same mesh rotated by PI
## around the body axis (no mirroring needed).
static func butterfly_wing() -> ArrayMesh:
	return _cached("butterfly_wing", func() -> ArrayMesh:
		var mb := MeshBuilder.new(5)
		var w := Color(1, 1, 1)
		var tip := Color(0.42, 0.40, 0.44)
		poly2(mb, [Vector3(0.006, 0, 0.035), Vector3(0.105, 0, 0.085), Vector3(0.09, 0, -0.005), Vector3(0.006, 0, -0.012)], w, w)
		poly2(mb, [Vector3(0.105, 0, 0.085), Vector3(0.155, 0, 0.07), Vector3(0.13, 0, 0.0), Vector3(0.09, 0, -0.005)], tip, tip)
		poly2(mb, [Vector3(0.006, 0, -0.012), Vector3(0.10, 0, -0.03), Vector3(0.085, 0, -0.09), Vector3(0.03, 0, -0.1), Vector3(0.006, 0, -0.06)], w, w)
		mb.box(Vector3(0.006, 0, -0.012), Vector3(0.013, 0.018, 0.13), Color(0.16, 0.14, 0.16))
		return mb.commit())


## Camera-facing quad (XY plane, size 1) with UVs for the glow / fx shaders; `col` is the vertex colour.
static func quad_mesh(col: Color = Color.WHITE) -> ArrayMesh:
	return _cached("quad_%s" % col.to_html(), func() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_uv(uvs[i])
			st.set_normal(Vector3.BACK)
			st.add_vertex(pts[i])
		return st.commit())


## Flat heart sticker (XY plane, ~1 m wide): pink centre on a white rim. For the fx billboard material.
static func heart_mesh() -> ArrayMesh:
	return _cached("heart", func() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var layers := [[1.0, Color("FFF6F2")], [0.74, Color("F0619E")]]
		for layer in layers:
			var k: float = layer[0]
			var col: Color = layer[1]
			var ring: Array[Vector3] = []
			for i in 24:
				var a := TAU * float(i) / 24.0
				var x := 16.0 * pow(sin(a), 3.0)
				var y := 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
				ring.append(Vector3(x, y + 2.5, 0) / 34.0 * k)
			var cen := Vector3(0, 0.08, 0) * k
			for i in 24:
				for v in [cen, ring[i], ring[(i + 1) % 24]]:
					st.set_color(col)
					st.set_uv(Vector2(0.5, 0.5))
					st.set_normal(Vector3.BACK)
					st.add_vertex(v)
		return st.commit())


const FIREFLY := Color(0.80, 1.0, 0.42)
const BUTTERFLY_COLORS := [Color("F2A23C"), Color("F4D65A"), Color("F7F3EA"), Color("86B6E8"), Color("B9A2E2"), Color("F2A23C")]


## Butterfly wing angle over time: quick downstroke, slower upstroke, a short glide now and then.
static func butterfly_flap(t: float) -> float:
	var f := fposmod(t * 4.2, 1.0)
	var s := smoothstep(0.0, 0.35, f) * (1.0 - smoothstep(0.35, 1.0, f))
	var glide := smoothstep(0.6, 0.9, sin(t * 0.7) * 0.5 + 0.5)
	return lerpf(0.1 + 1.25 * s, 0.35, glide * 0.8)


static var _fx_mats := {}


## fx.gdshader (alpha blended, unshaded) as a camera-facing billboard; `soft` rounds quads into dots.
static func fx_billboard(soft: bool) -> ShaderMaterial:
	var key := "soft" if soft else "hard"
	if not _fx_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/fx.gdshader")
		m.set_shader_parameter("billboard", true)
		m.set_shader_parameter("soft_round", soft)
		_fx_mats[key] = m
	return _fx_mats[key]


# --- rigs --------------------------------------------------------------------------------------------------

## Base rig: a set of named poses (channel tables) blended with eased transitions, plus locomotion and look state.
class AnimalRig extends Node3D:
	## Optional behaviour object (scripts/world/ambient_*.gd); pet() and is_pettable() are forwarded to it.
	var brain: Object = null
	## True when the owner calls step() every frame (Ambient poses only what is on screen); previews leave it off
	## and the rig animates itself.
	var driven := false
	var t := 0.0
	var speed := 0.0
	var spd := 0.0
	var phase := 0.0
	var walk_k := 0.0
	var stride := 0.3
	var look_yaw := 0.0
	var look_pitch := 0.0
	var ly := 0.0
	var lp := 0.0
	var action := ""
	var ch := PackedFloat32Array()
	var _names := PackedStringArray()
	var _tables: Array[PackedFloat32Array] = []
	var _w := PackedFloat32Array()
	var _w0 := PackedFloat32Array()
	var _target := 0
	var _tt := 1.0
	var _tdur := 0.5

	## names: channel names; defaults: name -> value; poses: pose -> {channel: value}.
	func _setup_poses(names: Array, defaults: Dictionary, poses: Dictionary, start: String) -> void:
		ch.resize(names.size())
		for pname in poses:
			var tb := PackedFloat32Array()
			tb.resize(names.size())
			var pd: Dictionary = poses[pname]
			for i in names.size():
				tb[i] = float(pd.get(names[i], defaults[names[i]]))
			_names.append(pname)
			_tables.append(tb)
		_w.resize(_tables.size())
		_w0.resize(_tables.size())
		_w.fill(0.0)
		_target = maxi(0, _names.find(start))
		_w[_target] = 1.0
		action = start

	## Blend to a pose. `blend` = transition time (s); 0 snaps. Unknown names are ignored.
	func play(a: String, blend: float = -1.0) -> void:
		var i := _names.find(a)
		if i < 0:
			return
		action = a
		if blend < 0.0:
			blend = 0.55
		if blend == 0.0 or t <= 0.0:
			_w.fill(0.0)
			_w[i] = 1.0
			_target = i
			_tt = 1.0
			_blend()
			return
		if i == _target and _tt >= 1.0:
			return
		_w0 = _w.duplicate()
		_target = i
		_tt = 0.0
		_tdur = blend

	func set_locomotion(s: float, _ref: float = 6.0) -> void:
		speed = maxf(s, 0.0)

	func look(yaw: float, pitch: float = 0.0) -> void:
		look_yaw = yaw
		look_pitch = pitch

	func pet() -> void:
		if brain and brain.has_method("pet"):
			brain.call("pet")
		else:
			play("pet")

	func is_pettable() -> bool:
		if brain and brain.has_method("is_pettable"):
			return bool(brain.call("is_pettable"))
		return false

	func _blend() -> void:
		ch.fill(0.0)
		var nc := ch.size()
		for i in _tables.size():
			var wi := _w[i]
			if wi < 0.0005:
				continue
			var tb := _tables[i]
			for c in nc:
				ch[c] += tb[c] * wi

	func _process(delta: float) -> void:
		if not driven:
			animate(minf(delta, 0.1))

	## Called by the owner every frame when `driven`: full pose on screen, only timers and blends off screen.
	func step(dt: float, on_screen: bool) -> void:
		if on_screen:
			animate(dt)
		else:
			advance(dt)

	func animate(dt: float) -> void:
		advance(dt)
		_blend()
		_pose(dt)

	## Time, pose blend weights, gait and look easing (no bone work).
	func advance(dt: float) -> void:
		t += dt
		if _tt < 1.0:
			_tt = minf(1.0, _tt + dt / _tdur)
			var k := _tt * _tt * (3.0 - 2.0 * _tt)
			for i in _w.size():
				_w[i] = lerpf(_w0[i], 1.0 if i == _target else 0.0, k)
		spd = lerpf(spd, speed, 1.0 - exp(-dt * 7.0))
		phase = fposmod(phase + dt * spd / stride * TAU, TAU)
		walk_k = lerpf(walk_k, clampf(spd / 0.18, 0.0, 1.0), 1.0 - exp(-dt * 9.0))
		var e := 1.0 - exp(-dt * 4.5)
		ly = lerpf(ly, look_yaw, e)
		lp = lerpf(lp, look_pitch, e)
		_advance(dt)

	func _advance(_dt: float) -> void:
		pass

	func _pose(_dt: float) -> void:
		pass

	func weight(pose: String) -> float:
		var i := _names.find(pose)
		return _w[i] if i >= 0 else 0.0


class CatRig extends AnimalRig:
	const CH := ["hx", "hy", "hz", "bp", "br", "by", "crl", "arc", "fa", "fl", "fg", "ha", "hl", "hg", "hu", "hf", "hs", "hp",
		"hyw", "hr", "tp", "ty", "tc", "ts", "tg", "tsw", "tsp", "bre", "look", "pur"]
	enum { HX, HY, HZ, BP, BR, BY, CRL, ARC, FA, FL, FG, HA, HL, HG, HU, HF, HS, HP, HYW, HR, TP, TY, TC, TS, TG, TSW, TSP,
		BRE, LOOK, PUR }
	## Channels: hip joint position (hx hy hz), body pitch/roll/yaw at the hip (bp br by), spine curl (crl, rad/m,
	## sideways) and arch (arc, rad/m, chest up), front/hind leg angle from vertical, fixed length and "reach the
	## ground" blend (fa fl fg / ha hl hg), head offsets (hu hf hs) pitch yaw roll (hp hyw hr), tail pitch at the root
	## and its curvature (tp, tc rad/m), tail yaw at the root and its curvature (ty, ts rad/m), tail on the ground
	## (tg), tail sway amount/speed (tsw tsp), breathing (bre), how much look() turns the head (look), purring (pur).
	const DEFAULT := {"hx": 0.0, "hy": 0.205, "hz": -0.09, "bp": 0.03, "br": 0.0, "by": 0.0, "crl": 0.0, "arc": 0.0,
		"fa": 0.0, "fl": 1.0, "fg": 1.0, "ha": 0.0, "hl": 1.0, "hg": 1.0,
		"hu": 0.0, "hf": 0.0, "hs": 0.0, "hp": 0.06, "hyw": 0.0, "hr": 0.0,
		"tp": 1.2, "ty": 0.0, "tc": 2.4, "ts": 0.0, "tg": 0.0, "tsw": 0.2, "tsp": 2.2, "bre": 0.35, "look": 1.0, "pur": 0.0}
	const SIT := {"hy": 0.105, "hz": -0.12, "bp": 0.62, "arc": 1.7, "fa": 0.05, "ha": 1.3, "hl": 0.85, "hg": 0.0,
		"hu": 0.0, "hf": -0.03, "hp": 0.1, "ty": 0.9, "ts": 6.5, "tg": 1.0, "tsw": 0.05, "tsp": 1.3, "bre": 0.55}
	const POSES := {
		"stand": {},
		"sit": SIT,
		"loaf": {"hy": 0.115, "hz": -0.09, "bp": 0.0, "fa": 1.42, "fl": 0.55, "fg": 0.0, "ha": 1.45, "hl": 0.6, "hg": 0.0,
			"hu": -0.035, "hf": -0.01, "hp": 0.0, "ty": 0.9, "ts": 5.0, "tg": 1.0, "tsw": 0.05, "tsp": 1.0,
			"bre": 0.7, "look": 0.6},
		"sleep": {"hy": 0.1, "hz": -0.05, "bp": 0.0, "br": 0.22, "by": 0.0, "crl": 5.6, "fa": 1.42, "fl": 0.45, "fg": 0.0,
			"ha": 1.45, "hl": 0.5, "hg": 0.0, "hu": -0.075, "hf": -0.02, "hs": -0.03, "hp": -0.3, "hyw": 1.25, "hr": 0.45,
			"ty": -1.0, "ts": -5.0, "tg": 1.0, "tsw": 0.025, "tsp": 0.7, "bre": 1.0, "look": 0.0},
		"stretch": {"hy": 0.235, "hz": -0.12, "bp": -0.34, "arc": -0.8, "fa": 0.95, "ha": -0.12, "hu": -0.02, "hf": 0.05,
			"hp": 0.45, "tp": 1.0, "tc": 3.6, "tsw": 0.05, "tsp": 1.0, "bre": 0.0, "look": 0.0},
		"pet": {"hy": 0.105, "hz": -0.12, "bp": 0.62, "arc": 1.7, "fa": 0.05, "ha": 1.3, "hl": 0.85, "hg": 0.0,
			"hu": 0.01, "hf": -0.025, "hp": 0.42, "ty": 0.9, "ts": 6.5, "tg": 1.0, "tsw": 0.03, "tsp": 1.3, "bre": 0.55,
			"look": 0.4, "pur": 1.0},
	}
	# Attachment points in spine-frame space.
	const SHOULDER_S := 0.195
	const LEG_OFF := Vector3(0.068, -0.058, 0.0)
	const NECK_S := 0.235
	const NECK_OFF := Vector3(0.0, 0.07, 0.0)
	const TAIL_S := -0.085
	const TAIL_OFF := Vector3(0.0, 0.045, 0.0)
	## Arc lengths where spine frames are needed, swept once each way from the hip: the hip, the body rings
	## (CAT_ZS), the shoulder, the neck and the tail root. RING_AT maps each CAT_ZS entry to its sweep index.
	const SWEEP := [0.0, 0.02, 0.07, 0.12, 0.17, SHOULDER_S, 0.215, NECK_S, 0.25, -0.025, -0.065, TAIL_S]
	const RING_AT := [10, 9, 1, 2, 3, 4, 6, 8]
	const SW_HIP := 0
	const SW_SHOULDER := 5
	const SW_NECK := 7
	const SW_TAIL := 11

	var coat := ""
	var skel: Skeleton3D
	var tail_len := CAT_TAIL_LEN
	var _rng := RandomNumberGenerator.new()
	var _hip := Vector3.ZERO
	var _base := Basis.IDENTITY
	var _crl := 0.0
	var _arc := 0.0
	var _tp := PackedVector3Array()
	var _td := PackedVector3Array()
	var _sf: Array[Transform3D] = []
	## World-ish (rig space) head transform, updated every frame (hearts spawn above it).
	var head_xf := Transform3D.IDENTITY

	func _init(coat_name: String = "orange", seed_value: int = 1) -> void:
		coat = coat_name
		name = "Cat_" + coat_name
		_rng.seed = seed_value
		stride = 0.3
		skel = ModelsAnimals._skinned(self, ModelsAnimals.cat_skin(coat), CAT_BONES, true,
			AABB(Vector3(-0.55, -0.05, -0.6), Vector3(1.1, 0.75, 1.2)))
		tail_len = CAT_TAIL_LEN * _rng.randf_range(0.9, 1.1)
		_tp.resize(CAT_TAIL_N + 1)
		_td.resize(CAT_TAIL_N)
		_sf.resize(SWEEP.size())
		t = 0.0
		_setup_poses(CH, DEFAULT, POSES, "stand")
		_blend()
		_pose(0.0)

	## Head position in world space (for hearts and prompts).
	func head_position() -> Vector3:
		return global_transform * (head_xf * Vector3(0, 0.12, 0.07))

	# --- Interactables interface (forwarded to the AmbientCat behaviour) ---

	func _enter_tree() -> void:
		if brain != null:
			Interactables.add(self)

	func _exit_tree() -> void:
		Interactables.remove(self)

	func can_interact(hero: Node) -> bool:
		return brain != null and bool(brain.call("can_interact", hero))

	func interact_position() -> Vector3:
		return global_position

	func interact_range() -> float:
		return float(brain.call("interact_range")) if brain != null else 1.6

	func interact_info() -> Dictionary:
		return brain.call("interact_info") if brain != null else {}

	func interact_hold(delta: float, hero: Node) -> void:
		if brain != null:
			brain.call("interact_hold", delta, hero)

	func interact_release(hero: Node) -> void:
		if brain != null:
			brain.call("interact_release", hero)

	# --- posing ---

	## Spine orientation at arc length s from the hip joint (s < 0 runs back towards the tail): the body curls
	## sideways (crl) and arches (arc) at a constant rate per metre.
	func _sb(s: float) -> Basis:
		return _base * Basis(Vector3.UP, _crl * s) * Basis(Vector3.RIGHT, -_arc * s)

	## Spine frames at the SWEEP arc lengths, integrated (midpoint rule) forward and back from the hip.
	func _sweep() -> void:
		var p := _hip
		var prev := 0.0
		_sf[0] = Transform3D(_sb(0.0), p)
		for i in range(1, SWEEP.size()):
			var s: float = SWEEP[i]
			if i == 9:
				p = _hip
				prev = 0.0
			p += _sb((prev + s) * 0.5).z * (s - prev)
			_sf[i] = Transform3D(_sb(s), p)
			prev = s

	static func _yaw_of(b: Basis) -> float:
		return atan2(b.z.x, b.z.z)

	func _pose(dt: float) -> void:
		var c := ch
		var wk := walk_k * clampf(1.0 - absf(c[BP]) * 1.5, 0.0, 1.0)
		var ph := phase
		var by := c[BY]
		# Spine.
		_hip = Vector3(c[HX], c[HY] + wk * 0.012 * cos(2.0 * ph), c[HZ])
		_base = Basis(Vector3.UP, by) * Basis(Vector3.RIGHT, -c[BP]) * Basis(Vector3.BACK, c[BR] + wk * 0.035 * sin(ph))
		_crl = c[CRL]
		_arc = c[ARC]
		_sweep()
		var breath := 1.0 + sin(t * 2.3) * 0.03 * c[BRE]
		var bscale := Basis.from_scale(Vector3(breath, breath, 1.0))
		for k in CAT_ZS.size():
			var f := _sf[RING_AT[k]]
			skel.set_bone_pose(k, Transform3D(f.basis * bscale, f.origin))
		var fs := _sf[SW_SHOULDER]
		var fh := _sf[SW_HIP]
		# Legs: FL, FR, HL, HR. Trot: diagonal pairs.
		var amp := 0.55 * wk
		for i in 4:
			var front := i < 2
			var sx := -1.0 if i % 2 == 0 else 1.0
			var fr := fs if front else fh
			var j := fr * (LEG_OFF * Vector3(sx, 1, 1))
			var off := 0.0 if (i == 0 or i == 3) else PI
			var sw := sin(ph + off)
			var a := (c[FA] if front else c[HA]) + amp * sw
			var auto_len := clampf(j.y / maxf(cos(a), 0.35) / CAT_LEG, 0.35, 2.4)
			var sc := lerpf(c[FL] if front else c[HL], auto_len, c[FG] if front else c[HG])
			sc *= 1.0 - 0.22 * wk * maxf(0.0, cos(ph + off))
			var lb := Basis(Vector3.UP, _yaw_of(fr.basis)) * Basis(Vector3.RIGHT, -a) * Basis.from_scale(Vector3(1.0, sc, 1.0))
			skel.set_bone_pose(CB_LEG + i, Transform3D(lb, j))
		# Head.
		var fn := _sf[SW_NECK]
		var lk := c[LOOK]
		var pur := c[PUR]
		var nyaw := _yaw_of(fn.basis)
		var neck := fn * NECK_OFF + Basis(Vector3.UP, nyaw) * Vector3(c[HS], c[HU] + wk * 0.008 * cos(2.0 * ph + 0.7), c[HF])
		var hyaw := nyaw + c[HYW] + ly * lk
		var hpitch := c[HP] + lp * lk + pur * 0.08 * sin(t * 2.6)
		var hroll := c[HR] + pur * 0.22 * sin(t * 1.7)
		head_xf = Transform3D(Basis(Vector3.UP, hyaw) * Basis(Vector3.RIGHT, -hpitch) * Basis(Vector3.BACK, hroll), neck)
		skel.set_bone_pose(CB_HEAD, head_xf)
		# Tail: a chain of short segments; pitch and yaw change along it (tc, ts per metre) with a travelling sway
		# wave. tg = 1 lays it on the ground (each segment dips just enough to reach it), so it can wrap the body.
		var seg := tail_len / float(CAT_TAIL_N)
		var sw_amp := c[TSW] + pur * 0.05
		var sp := c[TSP]
		var tg := c[TG]
		var ft := _sf[SW_TAIL]
		var p := ft * TAIL_OFF
		var yaw := _yaw_of(ft.basis) + c[TY] + sw_amp * sin(t * sp)
		_tp[0] = p
		for k in CAT_TAIL_N:
			var r: float = CAT_TAIL_R[k + 1]
			var air := c[TP] + c[TC] * seg * float(k) + (wk * 0.06 * sin(ph * 2.0) if k == 0 else 0.0)
			var flat := -asin(clampf((p.y - r) / seg, 0.0, 1.0))
			var pitch := lerpf(air, flat, tg)
			var d := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, -1)
			_td[k] = d
			p += d * seg
			p.y = maxf(p.y, r)
			_tp[k + 1] = p
			yaw += c[TS] * seg + sw_amp * 0.9 * sin(t * sp - float(k + 1) * 0.55) * 0.6 + pur * 0.04 * sin(t * 13.0 + float(k))
		var x := Basis(Vector3.UP, _yaw_of(ft.basis)).x
		for k in CAT_TAIL_N + 1:
			var dir: Vector3
			if k == 0:
				dir = _td[0]
			elif k == CAT_TAIL_N:
				dir = (_tp[k] - _tp[k - 1]).normalized()
			else:
				dir = ((_tp[k] - _tp[k - 1]).normalized() + (_tp[k + 1] - _tp[k]).normalized()).normalized()
			var rb := ModelsAnimals.ring_basis(dir, x)
			x = rb.x
			skel.set_bone_pose(CB_TAIL + k, Transform3D(rb, _tp[k]))


class GoatRig extends AnimalRig:
	const CH := ["hy", "bp", "br", "fa", "fl", "fg", "ha", "hl", "hg", "np", "ny", "nr", "nu", "bre", "look"]
	enum { HY, BP, BR, FA, FL, FG, HA, HL, HG, NP, NY, NR, NU, BRE, LOOK }
	const DEFAULT := {"hy": 0.415, "bp": 0.0, "br": 0.0, "fa": 0.0, "fl": 1.0, "fg": 1.0, "ha": 0.0, "hl": 1.0, "hg": 1.0,
		"np": -0.05, "ny": 0.0, "nr": 0.0, "nu": 0.0, "bre": 0.3, "look": 1.0}
	const POSES := {
		"stand": {},
		"graze": {"bp": -0.07, "fa": 0.1, "np": 1.25, "nu": -0.03, "look": 0.25},
		"lie": {"hy": 0.19, "fa": -1.45, "fl": 0.5, "fg": 0.0, "ha": 1.45, "hl": 0.5, "hg": 0.0, "np": -0.15, "bre": 0.6},
		"sleep": {"hy": 0.185, "br": 0.08, "fa": -1.45, "fl": 0.5, "fg": 0.0, "ha": 1.45, "hl": 0.5, "hg": 0.0, "np": 0.75,
			"ny": 1.15, "nr": 0.25, "nu": -0.06, "bre": 1.0, "look": 0.0},
	}
	const SHOULDER := Vector3(0.105, -0.11, 0.2)
	const HIP := Vector3(0.105, -0.11, -0.2)
	const NECK := Vector3(0.0, 0.08, 0.235)

	var coat := ""
	var kid := false
	var skel: Skeleton3D
	var _hop := 1.0
	var _hop_dur := 0.42

	func _init(coat_name: String = "white", _seed_value: int = 1, is_kid: bool = false) -> void:
		coat = coat_name
		kid = is_kid
		name = "Kid_" + coat_name if kid else "Goat_" + coat_name
		stride = 0.42 if kid else 0.55
		skel = ModelsAnimals._skinned(self, ModelsAnimals.goat_skin(coat, kid), 6, true,
			AABB(Vector3(-0.6, -0.05, -0.7), Vector3(1.2, 1.1, 1.5)))
		if kid:
			scale = Vector3.ONE * 0.6
		_setup_poses(CH, DEFAULT, POSES, "stand")
		_blend()
		_pose(0.0)

	## "hop" is a one-shot overlay (a little jump) on top of the current pose.
	func play(a: String, blend: float = -1.0) -> void:
		if a == "hop":
			_hop = 0.0
			return
		super.play(a, blend)

	func is_hopping() -> bool:
		return _hop < 1.0

	func _advance(dt: float) -> void:
		if _hop < 1.0:
			_hop = minf(1.0, _hop + dt / _hop_dur)

	func _pose(_dt: float) -> void:
		var c := ch
		var wk := walk_k
		var ph := phase
		var hop_y := 0.0
		var tuck := 0.0
		if _hop < 1.0:
			tuck = sin(_hop * PI)
			hop_y = tuck * (0.26 if kid else 0.2)
		var center := Vector3(0, c[HY] + wk * 0.016 * cos(2.0 * ph) + hop_y, 0)
		var bb := Basis(Vector3.RIGHT, -c[BP] - tuck * 0.12) * Basis(Vector3.BACK, c[BR] + wk * 0.03 * sin(ph))
		var bx := Transform3D(bb, center)
		var breath := sin(t * 1.9) * 0.025 * c[BRE]
		skel.set_bone_pose(0, Transform3D(bb * Basis.from_scale(Vector3(1.0 + breath, 1.0 + breath, 1.0)), center))
		var amp := 0.42 * wk
		for i in 4:
			var front := i < 2
			var sx := -1.0 if i % 2 == 0 else 1.0
			var j := bx * ((SHOULDER if front else HIP) * Vector3(sx, 1, 1))
			var off := 0.0 if (i == 0 or i == 3) else PI
			var a := (c[FA] if front else c[HA]) + amp * sin(ph + off) + tuck * (0.55 if front else -0.55)
			var auto_len := clampf((j.y - hop_y) / maxf(cos(a), 0.35) / GOAT_LEG, 0.35, 1.6)
			var sc := lerpf(c[FL] if front else c[HL], auto_len, c[FG] if front else c[HG])
			sc = lerpf(sc, 0.8, tuck)
			sc *= 1.0 - 0.18 * wk * maxf(0.0, cos(ph + off))
			skel.set_bone_pose(2 + i, Transform3D(Basis(Vector3.RIGHT, -a) * Basis.from_scale(Vector3(1.0, sc, 1.0)), j))
		var neck := bx * NECK + Vector3(0, c[NU], 0)
		var lk := c[LOOK]
		var hb := Basis(Vector3.UP, c[NY] + ly * lk) * Basis(Vector3.RIGHT, c[NP] - lp * lk + wk * 0.06 * sin(ph * 2.0) - tuck * 0.3) * Basis(Vector3.BACK, c[NR])
		if kid:
			hb = hb * Basis.from_scale(Vector3.ONE * 1.22)
		skel.set_bone_pose(1, Transform3D(hb, neck))


## Seagull: body + two-part wings. play("flap") flaps until play("glide"); flap(n) does n beats then glides.
## Banking and flight path are set by the owner (rotate/move the rig).
class GullRig extends Node3D:
	var brain: Object = null
	var t := 0.0
	var flap_target := 0.0
	var flap_k := 0.0
	var fphase := 0.0
	var flaps_left := -1
	var skel: Skeleton3D

	func _init(_seed_value: int = 1) -> void:
		name = "Gull"
		skel = ModelsAnimals._skinned(self, ModelsAnimals.gull_skin(), 5, true, AABB(Vector3(-0.8, -0.6, -0.5), Vector3(1.6, 1.2, 1.0)))
		fphase = float(_seed_value % 7)
		animate(0.0)

	func play(a: String, _blend: float = -1.0) -> void:
		flap_target = 1.0 if a == "flap" else 0.0
		flaps_left = -1

	func flap(n: int) -> void:
		flap_target = 1.0
		flaps_left = n

	func set_locomotion(_s: float, _ref: float = 6.0) -> void:
		pass

	func _process(delta: float) -> void:
		animate(minf(delta, 0.1))

	func animate(dt: float) -> void:
		t += dt
		flap_k = lerpf(flap_k, flap_target, 1.0 - exp(-dt * 6.0))
		var prev := fphase
		fphase = fposmod(fphase + dt * TAU * 2.6, TAU)
		if fphase < prev and flaps_left > 0:
			flaps_left -= 1
			if flaps_left == 0:
				flap_target = 0.0
		var s := sin(fphase)
		var glide_in := 0.13 + 0.035 * sin(t * 1.3)
		var glide_out := -0.2 + 0.03 * sin(t * 1.1 + 0.5)
		var a_in := lerpf(glide_in, 0.12 + 0.72 * s, flap_k)
		var a_out := lerpf(glide_out, -0.08 + 0.5 * sin(fphase - 0.75), flap_k)
		var by := -0.025 * s * flap_k
		skel.set_bone_pose(0, Transform3D(Basis.IDENTITY, Vector3(0, by, 0)))
		for k in 2:
			var sx := 1.0 if k == 0 else -1.0
			var w := Transform3D(Basis(Vector3.BACK, a_in * sx), Vector3(0.05 * sx, 0.045, 0.03))
			skel.set_bone_pose(1 + k, w)
			skel.set_bone_pose(3 + k, w * Transform3D(Basis(Vector3.BACK, a_out * sx), Vector3(0.30 * sx, 0, 0)))


## Dolphin: body + flukes (beat). The owner moves and pitches the rig along its leap.
class DolphinRig extends Node3D:
	var brain: Object = null
	var t := 0.0
	var beat := 0.32
	var beat_target := 0.32
	var skel: Skeleton3D

	func _init(seed_value: int = 1) -> void:
		name = "Dolphin"
		skel = ModelsAnimals._skinned(self, ModelsAnimals.dolphin_skin(), 2, true, AABB(Vector3(-0.6, -0.5, -1.3), Vector3(1.2, 1.2, 2.5)))
		t = float(seed_value % 5) * 0.3
		animate(0.0)

	func play(a: String, _blend: float = -1.0) -> void:
		beat_target = 0.1 if a == "leap" else 0.32

	func set_locomotion(_s: float, _ref: float = 6.0) -> void:
		pass

	func _process(delta: float) -> void:
		animate(minf(delta, 0.1))

	func animate(dt: float) -> void:
		t += dt
		beat = lerpf(beat, beat_target, 1.0 - exp(-dt * 4.0))
		var s := sin(t * TAU * 1.6)
		var bb := Basis(Vector3.RIGHT, -s * beat * 0.12)
		skel.set_bone_pose(0, Transform3D(bb, Vector3.ZERO))
		skel.set_bone_pose(1, Transform3D(bb * Basis(Vector3.RIGHT, s * beat), bb * Vector3(0, 0.07, -0.92)))


## Preview-only butterfly (in game they are drawn as one MultiMesh by AmbientBugs).
class ButterflyRig extends Node3D:
	var t := 0.0
	var wings: Array[MeshInstance3D] = []

	func _init(col: Color = Color("F0A040"), seed_value: int = 1) -> void:
		name = "Butterfly"
		for i in 2:
			var m := ModelsAnimals._mi(ModelsAnimals.butterfly_wing(), self, false)
			Materials.set_param(m, &"tint", Pal.lin(col))
			wings.append(m)
		t = float(seed_value) * 0.37
		position.y = 0.6
		animate(0.0)

	func play(_a: String, _blend: float = -1.0) -> void:
		pass

	func set_locomotion(_s: float, _ref: float = 6.0) -> void:
		pass

	func _process(delta: float) -> void:
		animate(minf(delta, 0.1))

	func animate(dt: float) -> void:
		t += dt
		var a := ModelsAnimals.butterfly_flap(t)
		wings[0].transform = Transform3D(Basis(Vector3.BACK, a), Vector3.ZERO)
		wings[1].transform = Transform3D(Basis(Vector3.BACK, PI - a), Vector3.ZERO)


## Preview-only firefly (in game: one MultiMesh of glow quads in AmbientBugs).
class FireflyRig extends Node3D:
	var t := 0.0
	var glow: MeshInstance3D

	func _init(seed_value: int = 1) -> void:
		name = "Firefly"
		glow = MeshInstance3D.new()
		glow.mesh = ModelsAnimals.quad_mesh(ModelsAnimals.FIREFLY)
		glow.material_override = Materials.glow_add()
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.scale = Vector3.ONE * 0.5
		glow.position.y = 0.8
		add_child(glow)
		t = float(seed_value) * 0.71

	func play(_a: String, _blend: float = -1.0) -> void:
		pass

	func set_locomotion(_s: float, _ref: float = 6.0) -> void:
		pass

	func _process(delta: float) -> void:
		t += delta
		Materials.set_param(glow, &"intensity", 0.6 + 0.5 * sin(t * 2.0))


# --- preview entry points (fn(seed) -> rig) ----------------------------------------------------------------

static func cat(coat_name: String, seed_value: int) -> CatRig:
	return CatRig.new(coat_name, seed_value)


static func cat_orange(seed_value: int) -> Node3D:
	return cat("orange", seed_value)


static func cat_black(seed_value: int) -> Node3D:
	return cat("black", seed_value)


static func cat_white(seed_value: int) -> Node3D:
	return cat("white", seed_value)


static func cat_grey(seed_value: int) -> Node3D:
	return cat("grey", seed_value)


static func cat_calico(seed_value: int) -> Node3D:
	return cat("calico", seed_value)


static func cat_tuxedo(seed_value: int) -> Node3D:
	return cat("tuxedo", seed_value)


static func goat(seed_value: int) -> Node3D:
	return GoatRig.new("white", seed_value)


static func goat_brown(seed_value: int) -> Node3D:
	return GoatRig.new("brown", seed_value)


static func goat_cream(seed_value: int) -> Node3D:
	return GoatRig.new("cream", seed_value)


static func goat_pied(seed_value: int) -> Node3D:
	return GoatRig.new("pied", seed_value)


static func goat_kid(seed_value: int) -> Node3D:
	return GoatRig.new("white" if seed_value % 2 == 1 else "brown", seed_value, true)


static func seagull(seed_value: int) -> Node3D:
	var g := GullRig.new(seed_value)
	g.position.y = 0.4
	return g


static func dolphin(seed_value: int) -> Node3D:
	var d := DolphinRig.new(seed_value)
	d.position.y = 0.4
	d.rotation.x = -0.25
	return d


static func butterfly(seed_value: int) -> Node3D:
	return ButterflyRig.new(BUTTERFLY_COLORS[seed_value % BUTTERFLY_COLORS.size()], seed_value)


static func firefly(seed_value: int) -> Node3D:
	return FireflyRig.new(seed_value)
