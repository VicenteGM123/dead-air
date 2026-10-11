class_name ChainRing
extends StaticBody3D
## A bronze mooring ring for the chain spear: a fixed anchor (chain_kind &"ring": the hero zips to it, climbs onto
## a ledge just above it or hangs from it). Two looks:
##   ChainRing.new(stone_height)        set in a standing stone (sunk 0.6 m into the ground), the ring on the stone's
##                                      +Z face ~0.8 m under its top; the stone collides on world layer 1
##   ChainRing.new(0.0, true)           mounted: a bronze plate and the ring only, for a cliff or a wall face; the
##                                      node's origin is the plate's centre on the wall, its +Z the wall's normal
## Group "chain_anchor". Contract (docs/ARCHITECTURE.md 5.3, docs/COMBAT.md): chain_point(), chain_kind(),
## chain_normal() (the side the hero hangs on), on_chain_attach / pull / release. The spear plays the bite sound.

## Height of the stone (m); the ring sits ~0.8 m under its top. 0 when mounted.
var height := 3.4
var mounted := false
var _ring: Node3D
var _glint := 0.0
var _mi: MeshInstance3D


func _init(stone_height: float = 3.4, on_wall: bool = false) -> void:
	height = stone_height
	mounted = on_wall


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("chain_anchor")
	add_to_group("chain_ring")
	var mb := MeshBuilder.new(61 + int(height * 10.0))
	mb.vary = 0.03
	var ry := height - 0.55
	var face_z := 0.5
	if mounted:
		ry = 0.0
		face_z = 0.0
	else:
		# Standing stone: a slightly tapered, leaning slab sunk 0.6 m into the ground.
		mb.push(Transform3D(Basis.from_euler(Vector3(0.04, 0.0, -0.03)), Vector3.ZERO))
		mb.cyl(Vector3(0, -0.6, 0), height + 0.6, 0.62, 0.45, 6, Pal.ROCK, true, 0.3, Pal.LIMESTONE_DARK)
		mb.pop()
	# Bronze plate (with four rivets) and the ring hanging from it.
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, ry, face_z)))
	mb.cyl(Vector3(0, -0.04, 0), 0.08, 0.2, 0.2, 8, Pal.BRONZE_DARK)
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		mb.ico(Vector3(cos(a) * 0.14, 0.05, sin(a) * 0.14), 0.025, Pal.BRONZE, 0)
	mb.pop()
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, ry - 0.24, face_z + 0.1)))
	mb.ring(Vector3(0, -0.035, 0), 0.32, 0.24, 0.07, 14, Pal.BRONZE)
	mb.pop()
	_mi = MeshInstance3D.new()
	_mi.mesh = mb.commit()
	_mi.material_override = Materials.lowpoly()
	Materials.set_param(_mi, &"metal", 1.0)
	add_child(_mi)
	_ring = Node3D.new()
	_ring.name = "RingPoint"
	_ring.position = Vector3(0, ry - 0.24, face_z + 0.12)
	add_child(_ring)
	if not mounted:
		var col := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.6
		cs.height = height + 0.6
		col.shape = cs
		col.position = Vector3(0, (height - 0.6) * 0.5, 0)
		add_child(col)


func chain_point() -> Vector3:
	return _ring.global_position


func chain_kind() -> StringName:
	return &"ring"


## The side the ring faces (the hero hangs on this side of it).
func chain_normal() -> Vector3:
	return global_transform.basis.z


func on_chain_attach(_hero: Node) -> void:
	_glint = 1.0
	if Game.fx:
		Game.fx.call("glint", chain_point(), 1.0, Color(1.0, 0.9, 0.6), 0.3)


func on_chain_pull(_hero: Node, _dir: Vector3) -> void:
	pass


func on_chain_release(_hero: Node) -> void:
	pass


func _process(delta: float) -> void:
	if _glint > 0.0:
		_glint = maxf(0.0, _glint - delta * 3.0)
		Materials.set_param(_mi, &"flash", _glint * 0.5)
