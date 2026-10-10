extends RefCounted
## The broken passage over the sea inlet between the palm and the thumb, and the altars.
##
## The old stone bridge fell long ago: its abutments still stand on both rims, the arch snapped off in mid air,
## and a sea stack rises from the water half-way across (where its pier stood). Three bronze rings on standing
## stones (ChainRing, scripts/props/chain_ring.gd) carry Heracles across with the chain spear: one on the south
## rim for the way back, one on the stack's flat top, one on the north rim. Each gap is ~10 m, each ring stands
## on walkable ground and faces the side you zip from.
##
## Altars (Altar, scripts/props/altar.gd) stand on the three viewpoints of the layout, their front (+Z, where the
## hero respawns) turned to the safe side.

const L := preload("res://scripts/world/nemea_layout.gd")

var world: Node3D
var t: RefCounted
var props: RefCounted
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var rings: Array = []
var altars: Array = []
var ring_info: Array = [] # [{pos, faces, landing}]


func build(w: Node3D, terrain: RefCounted, pr: RefCounted) -> void:
	world = w
	t = terrain
	props = pr
	rng.seed = 808
	body = StaticBody3D.new()
	body.name = "PassageBody"
	body.collision_layer = 1
	body.collision_mask = 0
	world.add_child(body)
	_stack_and_bridge()
	_rings()
	_altars()


func _mi(m: Mesh, xf: Transform3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat if mat != null else Materials.lowpoly()
	mi.transform = xf
	world.add_child(mi)
	return mi


func _stack_and_bridge() -> void:
	# The sea stack: a layered pillar with a flat top to land on.
	var mb := MeshBuilder.new(1201)
	mb.vary = 0.03
	ModelsNature.add_sea_stack(mb, ModelsNature.make_rng(1201), 3.7, L.PASS_STACK_TOP)
	var sm := mb.commit()
	var sp := Vector3(L.PASS_STACK.x, 0.0, L.PASS_STACK.y)
	_mi(sm, Transform3D(Basis.IDENTITY, sp))
	var cs := CollisionShape3D.new()
	cs.shape = sm.create_convex_shape(true, false)
	cs.position = sp
	body.add_child(cs)
	# Other sea stacks round the island.
	for st in L.STACKS:
		var c: Vector2 = st[0]
		var smb := MeshBuilder.new(1210 + int(c.x))
		smb.vary = 0.03
		ModelsNature.add_sea_stack(smb, ModelsNature.make_rng(1210 + int(c.x)), float(st[1]), float(st[2]), false)
		var m := smb.commit()
		var p := Vector3(c.x, 0.0, c.y)
		_mi(m, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		var cs2 := CollisionShape3D.new()
		cs2.shape = m.create_convex_shape(true, false)
		cs2.position = p
		body.add_child(cs2)
	# Bridge abutments on both rims, the broken arch reaching over the water.
	for rim in [[L.PASS_SOUTH, PI], [L.PASS_NORTH, 0.0]]:
		var p2: Vector2 = rim[0]
		var yaw: float = rim[1]
		# Find the rim edge: walk towards the inlet until the ground drops.
		var dir := Vector2(sin(yaw), cos(yaw))
		var q := p2
		for k in 40:
			var nq := q + dir * 0.25
			if t.height_at(nq.x, nq.y) < t.height_at(p2.x, p2.y) - 1.5:
				break
			q = nq
		var y: float = t.height_at(q.x, q.y)
		var bm := MeshBuilder.new(1220 + int(yaw * 10.0))
		bm.vary = 0.03
		ModelsNature.add_bridge_end(bm, ModelsNature.make_rng(1220 + int(yaw * 10.0)))
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y, q.y) - Vector3(dir.x, 0, dir.y) * 0.6)
		_mi(bm.commit(), xf)
		# Deck stub collision (walkable to the break) and the abutment block.
		var dc := CollisionShape3D.new()
		var db := BoxShape3D.new()
		db.size = Vector3(3.5, 0.3, 2.8)
		dc.shape = db
		dc.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0.75))
		body.add_child(dc)
		props.reserve(Vector2(xf.origin.x, xf.origin.z), 3.5)


## The rings: [stone base (xz), facing (yaw: the ring's face turns towards +Z of the stone), stone height].
func _rings() -> void:
	var defs := [
		# South rim, for the way back from the stack (faces north, towards the stack).
		[L.PASS_SOUTH + Vector2(2.2, -0.5), PI, 3.2, "Paso roto (sur)"],
		# On the stack's flat top (faces south: you zip to it from the south rim).
		[L.PASS_STACK, 0.0, 2.9, "Paso roto (farallón)"],
		# North rim (faces south, towards the stack).
		[L.PASS_NORTH + Vector2(-1.6, 1.0), 0.0, 3.2, "Paso roto (norte)"],
	]
	var scr: Script = load("res://scripts/props/chain_ring.gd") if ResourceLoader.exists("res://scripts/props/chain_ring.gd") else null
	for d in defs:
		var p2: Vector2 = d[0]
		var yaw: float = d[1]
		var hgt: float = d[2]
		var y: float = t.height_at(p2.x, p2.y)
		if p2 == L.PASS_STACK:
			y = L.PASS_STACK_TOP + 0.06
		var ring: Node3D
		if scr != null:
			ring = scr.new(hgt)
		else:
			ring = Node3D.new()
			ring.add_to_group("chain_anchor")
		ring.name = "Ring_%d" % rings.size()
		world.add_child(ring)
		ring.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p2.x, y, p2.y))
		rings.append(ring)
		ring_info.append({"pos": Vector3(p2.x, y, p2.y), "yaw": yaw, "label": d[3]})
		props.reserve(p2, 1.6)


func _altars() -> void:
	var scr: Script = load("res://scripts/props/altar.gd") if ResourceLoader.exists("res://scripts/props/altar.gd") else null
	for al in L.ALTARS:
		var p2: Vector2 = al[0]
		var yaw: float = al[1]
		var p := Vector3(p2.x, t.height_at(p2.x, p2.y), p2.y)
		var altar: Node3D
		if scr != null:
			altar = scr.new()
			altar.set("title", al[2])
		else:
			altar = Node3D.new()
		altar.name = "Altar_%d" % altars.size()
		world.add_child(altar)
		altar.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
		altars.append(altar)
		# A ring of old columns and cypresses round each altar (the viewpoint's landmark).
		for k in 3:
			var a := yaw + PI + (float(k) - 1.0) * 0.9
			var q := p2 + Vector2(sin(a), cos(a)) * rng.randf_range(5.0, 6.0)
			if t.normal_at(q.x, q.y).y < 0.9 or t.height_at(q.x, q.y) < 2.0:
				continue
			if k == 1:
				props.place_mesh("ruin_column", k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, t.height_at(q.x, q.y) - 0.1, q.y)), true)
			else:
				props.tree("cypress", q.x, q.y, rng.randf_range(0.95, 1.15))
		t.splat_soil(p2, 2.6, 0.5)
		t.splat_nograss(p2, 2.0)
