class_name ChainRing
extends StaticBody3D
## A bronze mooring ring set in a standing stone: a fixed chain-spear anchor (chain_kind &"ring": the hero zips to
## it). The ring hangs on the stone's +Z face near its top. Group "chain_anchor"; collision on world layer 1.
## Chain contract (docs/ARCHITECTURE.md): chain_point(), chain_kind(), on_chain_attach / pull / release.

## Height of the stone (m); the ring sits ~0.5 m under its top.
var height := 3.4
var _ring: Node3D
var _glint := 0.0
var _mi: MeshInstance3D


func _init(stone_height: float = 3.4) -> void:
	height = stone_height


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("chain_anchor")
	var mb := MeshBuilder.new(61 + int(height * 10.0))
	mb.vary = 0.03
	# Standing stone: a slightly tapered, leaning slab sunk 0.6 m into the ground.
	mb.push(Transform3D(Basis.from_euler(Vector3(0.04, 0.0, -0.03)), Vector3.ZERO))
	mb.cyl(Vector3(0, -0.6, 0), height + 0.6, 0.62, 0.45, 6, Pal.ROCK, true, 0.3, Pal.LIMESTONE_DARK)
	mb.pop()
	# Bronze plate and ring on the +Z face.
	var ry := height - 0.55
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, ry, 0.5)))
	mb.cyl(Vector3(0, -0.04, 0), 0.08, 0.2, 0.2, 8, Pal.BRONZE_DARK)
	mb.pop()
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, 0.0), Vector3(0, ry - 0.24, 0.6)))
	mb.ring(Vector3(0, -0.035, 0), 0.32, 0.24, 0.07, 14, Pal.BRONZE)
	mb.pop()
	_mi = MeshInstance3D.new()
	_mi.mesh = mb.commit()
	_mi.material_override = Materials.lowpoly()
	Materials.set_param(_mi, &"metal", 1.0)
	add_child(_mi)
	_ring = Node3D.new()
	_ring.name = "RingPoint"
	_ring.position = Vector3(0, ry - 0.24, 0.62)
	add_child(_ring)
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


func on_chain_attach(_hero: Node) -> void:
	_glint = 1.0
	if Game.fx:
		Game.fx.call("hit_spark", chain_point(), Vector3.UP, 0.6)
	Sfx.play("orb_hit", chain_point(), -4.0, 1.4)


func on_chain_pull(_hero: Node, _dir: Vector3) -> void:
	pass


func on_chain_release(_hero: Node) -> void:
	pass


func _process(delta: float) -> void:
	if _glint > 0.0:
		_glint = maxf(0.0, _glint - delta * 3.0)
		Materials.set_param(_mi, &"flash", _glint * 0.5)
