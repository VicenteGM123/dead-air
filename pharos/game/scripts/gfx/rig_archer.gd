class_name RigArcher
extends Rig
## Tower archer (toxotes): hooded in Aegean blue, a recurve bow. Faceless: the hood shadows the face.


func _ready() -> void:
	add_part("body", _mesh_body())
	add_part("bow_arm", _mesh_bow_arm(), "body", Vector3(-0.22, 1.08, -0.05))
	add_part("draw_arm", _mesh_draw_arm(), "body", Vector3(0.22, 1.08, -0.02))
	scale = Vector3.ONE * 0.95


func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(31)
	mb.vary = 0.03
	mb.limb(Vector3(-0.1, 0.0, 0), Vector3(-0.1, 0.55, 0), 0.08, 0.09, 5, Pal.WOOD_DARK)
	mb.limb(Vector3(0.1, 0.0, 0), Vector3(0.1, 0.55, 0), 0.08, 0.09, 5, Pal.WOOD_DARK)
	mb.cyl(Vector3(0, 0.45, 0), 0.75, 0.3, 0.24, 7, Pal.AEGEAN, true, 0.2)
	mb.cyl(Vector3(0, 0.62, 0), 0.08, 0.27, 0.27, 7, Pal.WOOD_DARK)
	# Hood and the shadow inside it.
	mb.ico(Vector3(0, 1.38, 0.02), 0.22, Pal.AEGEAN_LIGHT, 1, 0.04, Vector3(1.0, 1.1, 1.08))
	mb.limb(Vector3(0, 1.5, 0.1), Vector3(0, 1.48, 0.3), 0.1, 0.0, 5, Pal.AEGEAN_LIGHT)
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.1), Vector3(0, 1.34, -0.2)))
	mb.cyl(Vector3.ZERO, 0.04, 0.13, 0.12, 8, Pal.SKIN_SHADOW)
	mb.pop()
	# Quiver.
	mb.limb(Vector3(0.1, 0.8, 0.22), Vector3(-0.12, 1.3, 0.24), 0.07, 0.07, 6, Pal.WOOD)
	for i in 3:
		mb.limb(Vector3(-0.1 + i * 0.03, 1.28, 0.24), Vector3(-0.14 + i * 0.03, 1.42, 0.25), 0.012, 0.012, 3, Pal.CLOTH)
	return mb.commit()


func _mesh_bow_arm() -> Mesh:
	var mb := MeshBuilder.new(33)
	mb.limb(Vector3.ZERO, Vector3(0, -0.05, -0.45), 0.06, 0.05, 5, Pal.AEGEAN)
	# Recurve bow, vertical, held at the end of the arm.
	var c := Vector3(0, -0.05, -0.5)
	var prev := c + Vector3(0, -0.55, 0.12)
	for i in range(1, 7):
		var k := float(i) / 6.0
		var y := lerpf(-0.55, 0.55, k)
		var z := 0.12 - (1.0 - pow(2.0 * k - 1.0, 2.0)) * 0.18
		var p := c + Vector3(0, y, z)
		mb.limb(prev, p, 0.022, 0.022, 4, Pal.WOOD_DARK)
		prev = p
	mb.limb(c + Vector3(0, -0.55, 0.12), c + Vector3(0, 0.55, 0.12), 0.006, 0.006, 3, Pal.CLOTH)
	return mb.commit()


func _mesh_draw_arm() -> Mesh:
	var mb := MeshBuilder.new(35)
	mb.limb(Vector3.ZERO, Vector3(-0.1, -0.05, -0.32), 0.06, 0.05, 5, Pal.AEGEAN)
	return mb.commit()


func _action_length(a: String) -> float:
	return 0.45 if a == "shoot" else 0.4


func _animate(_delta: float) -> void:
	var body: Node3D = parts["body"]
	var draw: Node3D = parts["draw_arm"]
	body.position.y = sin(t * 2.0) * 0.01
	draw.position.z = -0.02
	if action == "shoot":
		var p := ap()
		var k := 1.0 - Rig.smooth(p * 2.0) if p < 0.5 else Rig.smooth((p - 0.5) * 2.0)
		draw.position.z = -0.02 + (1.0 - k) * 0.25
		body.rotation.x = -0.05 * (1.0 - k)
