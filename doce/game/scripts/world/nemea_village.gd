extends RefCounted
## The village of Nemea, its pier and the boats: whitewashed houses (ModelsBuildings, scaled for the third-person
## camera) facing the lanes, a paved plaza with the well, the great plane tree and a household shrine, garden
## walls and yards with figs and pomegranates, the wooden fence along the village's north edge (broken by the
## north gate: the lion came this way), the goat pen at the forest edge smashed open, a wooden pier with
## Heracles' galley and the merchantman that will sail to Lerna, nets and boats on the beach.
##
## Everything that neither sways nor animates is merged into one static mesh (one draw call); trees go through
## NemeaProps (instanced). Collision on layer 1: boxes for houses, walls, fences, the pier deck and the ships.

const L := preload("res://scripts/world/nemea_layout.gd")
const NemeaBoat := preload("res://scripts/world/nemea_boat.gd")
const SCALE := 1.25

var world: Node3D
var t: RefCounted
var props: RefCounted
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
## Placed houses: {pos: Vector3, yaw, kind, door: Vector3}
var houses: Array = []
## Spots where a cat may live (door steps, the well, the plaza edge, garden walls).
var cat_sites: Array[Vector3] = []
## Solid footprints for the animals: [x, z, radius, height] (from every collision box and cylinder).
var solids: Array = []
var lerna_boat: Node3D = null
var tris := 0

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()


func build(w: Node3D, terrain: RefCounted, pr: RefCounted) -> void:
	world = w
	t = terrain
	props = pr
	rng.seed = 3141
	body = StaticBody3D.new()
	body.name = "VillageBody"
	body.collision_layer = 1
	body.collision_mask = 0
	world.add_child(body)
	_houses()
	_plaza()
	_garden_walls()
	_north_fence()
	_goat_pen()
	_pier_and_boats()
	_beach()
	_commit()


# --- helpers -----------------------------------------------------------------------------------------------

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, t.height_at(x, z), z)


## Appends a mesh (all surfaces, non-indexed or indexed) into the merged static mesh.
func _merge(m: Mesh, xf: Transform3D) -> void:
	if m == null:
		return
	var nb := xf.basis.orthonormalized()
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var cl: Variant = a[Mesh.ARRAY_COLOR]
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		var order := PackedInt32Array()
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			order = idx
		else:
			order.resize(v.size())
			for i in v.size():
				order[i] = i
		for i in order:
			_v.append(xf * v[i])
			_n.append((nb * nr[i]).normalized())
			_c.append((cl as PackedColorArray)[i] if cl is PackedColorArray else Color.WHITE)


func _merge_mb(mb: MeshBuilder, xf: Transform3D = Transform3D.IDENTITY) -> void:
	_merge(mb.commit(), xf)


func _box(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)
	# Footprint as a row of circles along the box's longer side.
	var ax := xf.basis.x.normalized() * size.x * 0.5
	var az := xf.basis.z.normalized() * size.z * 0.5
	var long := ax if size.x >= size.z else az
	var short := minf(size.x, size.z) * 0.5
	var n := maxi(1, int(ceil(long.length() / maxf(short, 0.2))))
	for k in n + 1:
		var u := -1.0 + 2.0 * float(k) / float(maxi(n, 1))
		var c := xf.origin + long * u * (1.0 - short / maxf(long.length(), 0.01))
		solids.append([c.x, c.z, short * 1.05, size.y])


func _cyl(r: float, h: float, base: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	cs.position = base + Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	solids.append([base.x, base.z, r, h])


## Nearest point on any path to p (XZ), or p itself.
func _nearest_path(p: Vector2) -> Vector2:
	var best := INF
	var bp := p
	for pd in t.paths:
		for q: Vector2 in (pd["pts"] as PackedVector2Array):
			var d := q.distance_squared_to(p)
			if d < best:
				best = d
				bp = q
	return bp


# --- houses ------------------------------------------------------------------------------------------------

func _houses() -> void:
	var i := 0
	for hd in L.HOUSES:
		var c: Vector2 = hd[0]
		var kind: int = hd[2]
		var sc: float = hd[3]
		# Face the nearest lane (or the plaza).
		var target := _nearest_path(c)
		if c.distance_to(L.PLAZA) < 22.0:
			target = L.PLAZA
		var dir := (target - c).normalized()
		var yaw := atan2(dir.x, dir.y)
		var info: Dictionary = ModelsBuildings.building("house", 2 if kind == 1 else 1, 700 + i * 17)
		var p := _ground(c.x, c.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * sc), p)
		_merge(info["mesh"], xf)
		var door: Vector3 = xf * (info["anchors"]["door"] as Vector3)
		houses.append({"pos": p, "yaw": yaw, "kind": kind, "door": door, "scale": sc})
		cat_sites.append(_ground(door.x, door.z))
		# Pots by the door and a few amphoras against the wall.
		var dm := MeshBuilder.new(600 + i)
		dm.vary = 0.03
		var side_v := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
		for sgn in [-1.0, 1.0]:
			var pp: Vector3 = door + side_v * float(sgn) * rng.randf_range(0.95, 1.25) - Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.35)
			if rng.randf() < 0.8:
				ModelsBuildings._pot_plant(dm, rng, _ground(pp.x, pp.z), rng.randf_range(1.0, 1.3))
		if i % 3 == 0:
			var ap: Vector3 = p + Basis(Vector3.UP, yaw) * Vector3(-2.3 * sc, 0, 1.9 * sc)
			for k in 2 + rng.randi() % 2:
				dm.push_at(_ground(ap.x + k * 0.45, ap.z + (k % 2) * 0.3), rng.randf() * TAU)
				ModelsNature.add_amphora(dm, rng, rng.randf_range(0.8, 1.0), 1)
				dm.pop()
		_merge_mb(dm)
		# Collision: the walls (roof overhangs and pots stay walk-round decoration).
		var bx := Basis(Vector3.UP, yaw)
		if kind == 1:
			_box(Vector3(3.9, 6.6, 3.6) * sc, Transform3D(bx, p + bx * (Vector3(-0.95, 3.0, 0) * sc)))
			_box(Vector3(2.5, 3.0, 2.8) * sc, Transform3D(bx, p + bx * (Vector3(2.15, 1.4, -0.35) * sc)))
			_box(Vector3(6.7, 0.5, 4.0) * sc, Transform3D(bx, p + bx * (Vector3(0.25, 0.0, -0.05) * sc)))
		else:
			_box(Vector3(4.1, 4.8, 3.4) * sc, Transform3D(bx, p + bx * (Vector3(0, 2.2, 0) * sc)))
			_box(Vector3(4.4, 0.5, 3.7) * sc, Transform3D(bx, p + bx * (Vector3(0, 0.0, 0) * sc)))
		t.splat_ao(Vector2(p.x, p.z), (4.2 if kind == 1 else 3.2) * sc, 0.35)
		t.splat_soil(Vector2(door.x, door.z), 1.6, 0.5)
		t.splat_nograss(Vector2(p.x, p.z), (3.9 if kind == 1 else 2.9) * sc)
		props.reserve(Vector2(p.x, p.z), (4.6 if kind == 1 else 3.6) * sc)
		i += 1


# --- plaza -------------------------------------------------------------------------------------------------

func _plaza() -> void:
	var c := L.PLAZA
	var y := -INF
	for k in 24:
		var a := TAU * k / 24.0
		for r in [0.0, 3.0, 6.0, L.PLAZA_R - 0.3]:
			y = maxf(y, t.height_at(c.x + cos(a) * r, c.y + sin(a) * r))
	y += 0.04
	var mb := MeshBuilder.new(77)
	mb.vary = 0.03
	var r0 := 0.0
	var ring := 0
	while r0 < L.PLAZA_R - 0.05:
		var r1 := minf(L.PLAZA_R, r0 + (1.6 if ring == 0 else 1.15))
		var segs := maxi(6, int(TAU * (r0 + r1) * 0.5 / 1.3))
		var off := rng.randf() * TAU
		for i in segs:
			var a0 := off + TAU * float(i) / segs + 0.012
			var a1 := off + TAU * float(i + 1) / segs - 0.012
			var ri := r0 + 0.04
			var ro := r1 - 0.04
			var u := rng.randf()
			var col := Pal.MARBLE_SHADE if u > 0.6 else (Pal.LIMESTONE if u > 0.25 else Pal.LIMESTONE.lerp(Pal.LIMESTONE_DARK, 0.5))
			if ring == 2:
				col = Pal.TERRACOTTA.lerp(Pal.LIMESTONE, 0.35) # a terracotta ring round the centre
			if r1 >= L.PLAZA_R - 0.01:
				col = Pal.LIMESTONE_DARK
			var p0 := Vector3(cos(a0) * ri, y, sin(a0) * ri)
			var p1 := Vector3(cos(a1) * ri, y, sin(a1) * ri)
			var p2 := Vector3(cos(a1) * ro, y, sin(a1) * ro)
			var p3 := Vector3(cos(a0) * ro, y, sin(a0) * ro)
			if ri < 0.1:
				mb.tri(Vector3(0, y, 0), p3, p2, col)
			else:
				mb.quad(p0, p3, p2, p1, col)
		r0 = r1
		ring += 1
	# The paving's bed (its top just under the slabs, so the joints read dark).
	mb.cyl(Vector3(0, y - 0.6, 0), 0.585, L.PLAZA_R, L.PLAZA_R, 40, Pal.LIMESTONE_DARK.darkened(0.35), true)
	mb.ring(Vector3(0, y - 0.3, 0), L.PLAZA_R + 0.25, L.PLAZA_R - 0.02, 0.36, 48, Pal.LIMESTONE_DARK.darkened(0.06))
	_merge_mb(mb, Transform3D(Basis.IDENTITY, Vector3(c.x, 0, c.y)))
	_box(Vector3(L.PLAZA_R * 1.4, 0.6, L.PLAZA_R * 1.4), Transform3D(Basis.IDENTITY, Vector3(c.x, y - 0.3, c.y)))
	t.splat_nograss(c, L.PLAZA_R + 0.4)
	# The well.
	var wp := Vector3(L.WELL.x, y - 0.02, L.WELL.y)
	_merge(ModelsNature.well(5), Transform3D(Basis(Vector3.UP, 0.4), wp))
	_cyl(0.95, 1.2, wp)
	cat_sites.append(wp + Vector3(1.6, 0, 0.6))
	# The great plane tree, with a stone seat round its trunk.
	var pt := Vector3(L.PLANE_TREE.x, y, L.PLANE_TREE.y)
	props.tree("plane_tree", pt.x, pt.z, 1.25, 0, true)
	var sb := MeshBuilder.new(78)
	sb.vary = 0.03
	sb.ring(Vector3(0, 0, 0), 1.9, 1.35, 0.45, 16, Pal.LIMESTONE)
	_merge_mb(sb, Transform3D(Basis.IDENTITY, pt))
	_cyl(1.9, 0.45, pt)
	cat_sites.append(pt + Vector3(-1.6, 0.45, 0.8))
	# The household shrine: a herm with offerings.
	var sp := _ground(L.SHRINE.x, L.SHRINE.y)
	_merge(ModelsNature.herm_shrine(9), Transform3D(Basis(Vector3.UP, 0.6), sp))
	_cyl(0.6, 2.0, sp)
	# Benches round the plaza edge (between the roads and the stalls).
	for k in 2:
		var a := deg_to_rad(-68.0 if k == 0 else 128.0)
		var bp := Vector3(c.x + cos(a) * (L.PLAZA_R - 1.0), y, c.y + sin(a) * (L.PLAZA_R - 1.0))
		var bm := MeshBuilder.new(90 + k)
		ModelsBuildings._bench(bm, Vector3.ZERO)
		_merge_mb(bm, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), bp))
		_box(Vector3(1.2, 0.46, 0.4), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), bp + Vector3(0, 0.23, 0)))
	cat_sites.append(Vector3(c.x + 6.0, y, c.y - 5.0))
	# Market stalls with striped awnings, facing the plaza's centre, between the roads.
	var stripes := [Pal.CREST, Pal.AEGEAN, Pal.GOLD_DARK]
	var angles := [30.0, 108.0, 190.0]
	for k in 3:
		var a := deg_to_rad(float(angles[k]))
		var stall_p := Vector3(c.x + cos(a) * 7.0, y, c.y + sin(a) * 7.0)
		var to_c := Vector3(c.x, y, c.y) - stall_p
		var yaw := atan2(to_c.x, to_c.z)
		var sxf := Transform3D(Basis(Vector3.UP, yaw), stall_p)
		_merge(ModelsBuildings.market_stall(500 + k, stripes[k]), sxf)
		_box(Vector3(2.6, 2.2, 1.7), Transform3D(sxf.basis, sxf * Vector3(0, 1.1, 0)))
		cat_sites.append(sxf * Vector3(1.7, 0, 0.6))
	# Potted flowers round the plaza's rim.
	var pm := MeshBuilder.new(520)
	pm.vary = 0.03
	for k in 9:
		var a := deg_to_rad(-25.0 + k * 40.0 + rng.randf_range(-6.0, 6.0))
		var near_road := false
		for ra in [-100.0, 68.0, -14.0, 148.0, 30.0, 108.0, 190.0, -68.0, 128.0]:
			if absf(angle_difference(a, deg_to_rad(float(ra)))) < deg_to_rad(13.0):
				near_road = true
		if near_road:
			continue
		ModelsBuildings._pot_plant(pm, rng, Vector3(c.x + cos(a) * (L.PLAZA_R - 0.45), y, c.y + sin(a) * (L.PLAZA_R - 0.45)), rng.randf_range(1.1, 1.4))
	_merge_mb(pm)


# --- yards and walls ---------------------------------------------------------------------------------------

## A whitewashed garden wall behind every other house (a yard with a fig, a pomegranate or an oleander).
func _garden_walls() -> void:
	var trees := ["fig_tree", "pomegranate", "oleander", "fig_tree", "pomegranate"]
	for k in houses.size():
		if k % 2 == 1:
			continue
		var hs: Dictionary = houses[k]
		var p: Vector3 = hs["pos"]
		var yaw: float = hs["yaw"]
		var sc: float = hs["scale"]
		var bx := Basis(Vector3.UP, yaw)
		var back := 2.4 * sc if int(hs["kind"]) == 1 else 2.0 * sc
		var w := 6.5 if int(hs["kind"]) == 1 else 5.5
		var d := 4.5
		# Yard corners in house space (behind the house: -Z).
		var a := Vector3(-w * 0.5, 0, -back)
		var b := Vector3(-w * 0.5, 0, -back - d)
		var c := Vector3(w * 0.5, 0, -back - d)
		var e := Vector3(w * 0.5, 0, -back)
		var runs := [[a, b], [b, c], [c, e]]
		var ok := true
		for run in runs:
			var m: Vector3 = p + bx * ((run[0] + run[1]) * 0.5)
			if t.field(t.path_d, m.x, m.z) < 1.0:
				ok = false
		if not ok:
			continue
		for ri in runs.size():
			var run: Array = runs[ri]
			var w0: Vector3 = p + bx * (run[0] as Vector3)
			var w1: Vector3 = p + bx * (run[1] as Vector3)
			_wall(w0, w1, 1.0, ri == 1)
		var yc: Vector3 = p + bx * Vector3(rng.randf_range(-1.0, 1.0), 0, -back - d * 0.5)
		props.tree(trees[k % trees.size()], yc.x, yc.z, rng.randf_range(0.9, 1.1), -1, true)
		cat_sites.append(p + bx * Vector3(w * 0.5 + 0.6, 0, -back - 0.6))


## A whitewashed rubble wall from a to b (on the ground), height h, with a gap in the middle if `gate`.
func _wall(a: Vector3, b: Vector3, h: float, gate: bool) -> void:
	var dir := b - a
	dir.y = 0.0
	var l := dir.length()
	if l < 0.3:
		return
	var yaw := atan2(dir.x, dir.z)
	var bx := Basis(Vector3.UP, yaw)
	var segs: Array = [[0.0, l]]
	if gate and l > 3.0:
		segs = [[0.0, l * 0.5 - 0.7], [l * 0.5 + 0.7, l]]
	for sg in segs:
		var s0: float = sg[0]
		var s1: float = sg[1]
		var mb := MeshBuilder.new(int(a.x * 13.0 + a.z * 7.0) + int(s0 * 10.0))
		mb.vary = 0.03
		var n := maxi(1, int(ceil((s1 - s0) / 1.0)))
		for i in n:
			var u0 := s0 + (s1 - s0) * float(i) / n
			var u1 := s0 + (s1 - s0) * float(i + 1) / n
			var pa := a + dir.normalized() * u0
			var pb := a + dir.normalized() * u1
			var ya: float = t.height_at(pa.x, pa.z)
			var yb: float = t.height_at(pb.x, pb.z)
			var lo := minf(ya, yb) - 0.35
			var mid := (u0 + u1) * 0.5
			ModelsNature.box5(mb, Vector3(0, lo + (h + 0.35 + absf(ya - yb)) * 0.5, mid), Vector3(0.42, h + 0.35 + absf(ya - yb), u1 - u0 + 0.02), Pal.MARBLE, Pal.MARBLE_SHADE)
		_merge_mb(mb, Transform3D(bx, Vector3(a.x, 0, a.z)))
		var cm := a + dir.normalized() * (s0 + s1) * 0.5
		_box(Vector3(0.45, h + 0.4, s1 - s0), Transform3D(bx, Vector3(cm.x, t.height_at(cm.x, cm.z) + h * 0.5 - 0.1, cm.z)))
		var p0 := Vector2(a.x, a.z) + Vector2(dir.x, dir.z).normalized() * s0
		var p1 := Vector2(a.x, a.z) + Vector2(dir.x, dir.z).normalized() * s1
		t.splat_nograss(p0, 0.35, p1)
		t.splat_ao(p0, 0.9, 0.35, p1)


# --- fences ------------------------------------------------------------------------------------------------

## A line of wooden fence segments along `pts`; `broken(i)` picks the kind (0 intact, 1 broken, 2 smashed).
func _fence_line(pts: Array, broken: Callable) -> void:
	var idx := 0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var l := a.distance_to(b)
		var n := maxi(1, int(round(l / 3.0)))
		for j in n:
			var p0 := a.lerp(b, float(j) / n)
			var p1 := a.lerp(b, float(j + 1) / n)
			var mid := (p0 + p1) * 0.5
			var dir := (p1 - p0).normalized()
			var kind: int = broken.call(idx, mid)
			idx += 1
			if t.field(t.path_d, mid.x, mid.y) < 0.4:
				continue
			# The fence model runs along X: yaw so that local X follows dir.
			var yaw := atan2(-dir.y, dir.x)
			var y: float = t.height_at(mid.x, mid.y)
			var sx := p0.distance_to(p1) / 3.0
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sx, 1.0, 1.0)), Vector3(mid.x, y - 0.02, mid.y))
			props.place_mesh("wood_fence", kind, xf, false)
			if kind < 2:
				_box(Vector3(3.0 * sx, 1.15, 0.22), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, y + 0.55, mid.y)))
			t.splat_nograss(p0, 0.25, p1)


## The village's north fence: intact on the flanks, broken and smashed near the gate (the lion came through).
func _north_fence() -> void:
	var west := [Vector2(-46, 66), Vector2(-36, 58), Vector2(-20, 55.5), Vector2(-7.5, 54.5)]
	var east := [Vector2(-0.5, 54.0), Vector2(14, 53.5), Vector2(30, 56), Vector2(44, 62)]
	_fence_line(west, func(i: int, m: Vector2) -> int: return 2 if m.x > -14.0 else (1 if i % 4 == 2 else 0))
	_fence_line(east, func(i: int, m: Vector2) -> int: return 1 if m.x < 6.0 else (2 if i == 3 else 0))
	# Gate posts: two stone pillars, one gate leaf torn off and lying on the grass.
	var mb := MeshBuilder.new(310)
	mb.vary = 0.03
	for gp: Vector2 in [Vector2(-7.0, 54.4), Vector2(-1.0, 54.0)]:
		var y: float = t.height_at(gp.x, gp.y)
		mb.block(Vector3(gp.x, y - 0.4, gp.y), Vector3(0.7, 2.3, 0.7), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
		mb.block(Vector3(gp.x, y + 1.9, gp.y), Vector3(0.85, 0.18, 0.85), Pal.LIMESTONE, Pal.MARBLE)
		_box(Vector3(0.7, 2.4, 0.7), Transform3D(Basis.IDENTITY, Vector3(gp.x, y + 0.8, gp.y)))
	var leaf := Vector3(-8.2, t.height_at(-8.2, 51.5) + 0.08, 51.5)
	mb.push(Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.06), leaf))
	for i in 5:
		ModelsNature.box5(mb, Vector3(-1.2 + i * 0.6, 0.7, 0), Vector3(0.12, 1.4, 0.06), Pal.WOOD, Pal.WOOD_LIGHT)
	ModelsNature.box5(mb, Vector3(0, 1.1, 0.04), Vector3(2.8, 0.12, 0.05), Pal.WOOD_DARK)
	ModelsNature.box5(mb, Vector3(0, 0.3, 0.04), Vector3(2.8, 0.12, 0.05), Pal.WOOD_DARK)
	mb.pop()
	_merge_mb(mb)


## The goat pen at the forest edge: a ring of fence, smashed open on the north side, the trough knocked over,
## tufts of wool on the splinters. The goats have scattered (AmbientGoat herds graze round it, nervous).
func _goat_pen() -> void:
	var c := L.GOAT_PEN
	var pts: Array = []
	for k in 13:
		var a := TAU * float(k) / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * 6.0)
	_fence_line(pts, func(i: int, m: Vector2) -> int:
		if m.y < c.y - 3.0:
			return 2 if absf(m.x - c.x) < 3.5 else 1
		return 0)
	var mb := MeshBuilder.new(320)
	mb.vary = 0.03
	var tp := _ground(c.x + 2.0, c.y + 1.5)
	mb.push(Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.BACK, 1.2), tp + Vector3(0, 0.3, 0)))
	ModelsNature.box5(mb, Vector3(0, 0, 0), Vector3(1.6, 0.4, 0.5), Pal.WOOD, Pal.WOOD_DARK)
	mb.pop()
	# Hay heap and wool tufts.
	ModelsNature.blob(mb, rng, _ground(c.x - 2.5, c.y + 2.0), [Vector2(1.1, 0), Vector2(0.9, 0.35), Vector2(0.4, 0.6), Vector2(0, 0.65)], 7, 0.15, Color("D9C27A"), Color("B59A55"), -0.3)
	for k in 6:
		var a := rng.randf_range(-2.4, -0.7)
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(5.6, 6.6)
		mb.ico(_ground(p.x, p.y) + Vector3(0, rng.randf_range(0.1, 0.9), 0), rng.randf_range(0.07, 0.12), Color("F2EEE4"), 0, 0.2)
	_merge_mb(mb)
	t.splat_soil(c, 5.5, 0.55)


# --- pier and boats ----------------------------------------------------------------------------------------

func _pier_and_boats() -> void:
	var x := L.PIER_A.x
	var z0 := L.PIER_A.y
	var z1 := L.PIER_B.y
	var deck := L.PIER_DECK
	var hw := L.PIER_HALF_W
	var mb := MeshBuilder.new(91)
	mb.vary = 0.04
	var length := z1 - z0
	var planks := int(length / 0.5)
	for i in planks:
		var zc := z0 + (i + 0.5) * length / planks
		var col := Pal.WOOD_LIGHT if i % 3 != 0 else Pal.WOOD
		mb.block(Vector3(x + rng.randf_range(-0.05, 0.05), deck - 0.1, zc), Vector3(hw * 2.0, 0.1, length / planks - 0.05), col)
	# T-head at the sea end.
	var tz := z1 - 4.0
	for i in 8:
		var zc := tz + (i + 0.5) * 0.5
		mb.block(Vector3(x, deck - 0.1, zc), Vector3(7.0, 0.1, 0.45), Pal.WOOD_LIGHT if i % 3 != 0 else Pal.WOOD)
	for sx in [-1.0, 1.0]:
		mb.block(Vector3(x + sx * (hw - 0.12), deck - 0.32, (z0 + z1) * 0.5), Vector3(0.18, 0.22, length), Pal.WOOD_DARK)
	# Posts every 3 m down to the sea floor, bollards on the T.
	var zc2 := z0 + 1.0
	while zc2 <= z1:
		for sx in [-1.0, 1.0]:
			var px: float = x + sx * (hw - 0.1)
			var y0: float = t.height_at(px, zc2) - 0.6
			mb.limb(Vector3(px, y0, zc2), Vector3(px, deck + (0.35 if zc2 > tz else 0.0), zc2), 0.14, 0.12, 6, Pal.WOOD_DARK)
		zc2 += 3.0
	for bx in [-3.2, 3.2]:
		for bz in [tz + 0.4, tz + 3.6]:
			var y0b: float = t.height_at(x + bx, bz) - 0.6
			mb.limb(Vector3(x + bx, y0b, bz), Vector3(x + bx, deck + 0.45, bz), 0.15, 0.13, 6, Pal.WOOD_DARK)
	# A lantern post at the end.
	mb.limb(Vector3(x - 3.0, deck, z1 - 0.3), Vector3(x - 3.0, deck + 2.6, z1 - 0.3), 0.07, 0.06, 5, Pal.WOOD_DARK)
	mb.box(Vector3(x - 3.0, deck + 2.75, z1 - 0.3), Vector3(0.32, 0.36, 0.32), Pal.FIRE)
	mb.roof_pyramid(Vector3(x - 3.0, deck + 2.93, z1 - 0.3), 0.42, 0.42, 0.22, Pal.BRONZE_DARK)
	# Amphoras and a coil of rope.
	for k in 3:
		mb.push_at(Vector3(x + 1.1 + k * 0.5, deck, z0 + 4.0 + (k % 2) * 0.4), rng.randf() * TAU)
		ModelsNature.add_amphora(mb, rng, 1.0, 1)
		mb.pop()
	mb.ring(Vector3(x - 1.0, deck, tz + 1.8), 0.32, 0.12, 0.12, 8, Color("D6BE88"))
	_merge_mb(mb)
	_box(Vector3(hw * 2.0, 0.3, length), Transform3D(Basis.IDENTITY, Vector3(x, deck - 0.15, (z0 + z1) * 0.5)))
	_box(Vector3(7.0, 0.3, 4.0), Transform3D(Basis.IDENTITY, Vector3(x, deck - 0.15, tz + 2.0)))
	t.splat_nograss(Vector2(x, z0), 2.5, Vector2(x, z0 + 6.0))
	# Heracles' galley (east side) and the merchantman for Lerna (west side).
	var g: Dictionary = ModelsBuildings.ship(0, 21)
	var gxf := Transform3D(Basis(Vector3.UP, 0.04), L.BOAT_HERACLES)
	_merge(g["mesh"], gxf)
	_box(Vector3(float(g["beam"]) * 0.8, 2.2, float(g["length"]) * 0.9), Transform3D(gxf.basis, L.BOAT_HERACLES + Vector3(0, 0.3, 0)))
	var m: Dictionary = ModelsBuildings.ship(1, 33)
	var mxf := Transform3D(Basis(Vector3.UP, PI - 0.05), L.BOAT_LERNA)
	_merge(m["mesh"], mxf)
	_box(Vector3(float(m["beam"]) * 0.8, 2.4, float(m["length"]) * 0.9), Transform3D(mxf.basis, L.BOAT_LERNA + Vector3(0, 0.3, 0)))
	# Mooring lines from the bollards to the ships.
	var lm := MeshBuilder.new(95)
	lm.limb(Vector3(x + 3.2, deck + 0.4, tz + 0.4), L.BOAT_HERACLES + Vector3(-0.6, 1.0, -3.8), 0.025, 0.025, 4, Color("D6BE88"), false)
	lm.limb(Vector3(x + 3.2, deck + 0.4, tz + 3.6), L.BOAT_HERACLES + Vector3(-0.6, 1.1, 4.2), 0.025, 0.025, 4, Color("D6BE88"), false)
	lm.limb(Vector3(x - 3.2, deck + 0.4, tz + 0.4), L.BOAT_LERNA + Vector3(0.7, 1.2, 3.6), 0.025, 0.025, 4, Color("D6BE88"), false)
	_merge_mb(lm)
	# The Lerna boat as an interactable (sail on after the lion).
	lerna_boat = NemeaBoat.new()
	lerna_boat.name = "BoatToLerna"
	world.add_child(lerna_boat)
	lerna_boat.global_position = L.BOAT_DOCK


# --- beach -------------------------------------------------------------------------------------------------

func _beach() -> void:
	var mb := MeshBuilder.new(400)
	mb.vary = 0.03
	# A fishing boat drawn up on the sand, nets drying on poles, crates.
	var bp := _ground(-6.0, 106.0)
	_merge(ModelsNature.boat_small(4), Transform3D(Basis(Vector3.UP, 1.2), bp + Vector3(0, 0.05, 0)))
	_box(Vector3(1.4, 0.9, 3.6), Transform3D(Basis(Vector3.UP, 1.2), bp + Vector3(0, 0.45, 0)))
	var bp2 := _ground(30.0, 107.0)
	_merge(ModelsNature.boat_small(7), Transform3D(Basis(Vector3.UP, -1.9), bp2 + Vector3(0, 0.05, 0)))
	_box(Vector3(1.4, 0.9, 3.6), Transform3D(Basis(Vector3.UP, -1.9), bp2 + Vector3(0, 0.45, 0)))
	for k in 3:
		var px := -16.0 + k * 3.2
		var p := _ground(px, 101.0)
		mb.limb(p + Vector3(0, -0.3, 0), p + Vector3(0, 1.9, 0), 0.06, 0.05, 5, Pal.WOOD_DARK)
		if k < 2:
			var q := _ground(px + 3.2, 101.0)
			for j in 6:
				var u := float(j) / 5.0
				var a := p.lerp(q, u) + Vector3(0, 1.75 - sin(u * PI) * 0.35, 0)
				mb.limb(a, a + Vector3(0, -1.1 - sin(u * PI) * 0.2, 0.05), 0.12, 0.05, 4, Pal.AEGEAN_LIGHT if j % 2 == 0 else Pal.AEGEAN, false)
		_cyl(0.12, 2.0, p)
	for k in 4:
		var cp := _ground(19.0 + k * 0.9, 102.0 + (k % 2) * 0.8)
		ModelsBuildings._crate(mb, rng, cp, rng.randf_range(0.5, 0.65))
	_box(Vector3(3.6, 0.7, 1.6), Transform3D(Basis.IDENTITY, _ground(20.4, 102.4) + Vector3(0, 0.3, 0)))
	_merge_mb(mb)


# --- commit ------------------------------------------------------------------------------------------------

func _commit() -> void:
	if _v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Village"
	mi.mesh = m
	mi.material_override = Materials.lowpoly()
	world.add_child(mi)
	tris = _v.size() / 3
