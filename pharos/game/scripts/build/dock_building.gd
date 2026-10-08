class_name DockBuilding
extends Building
## Fishing pier: its boats bob on the water.

var boats: Array[MeshInstance3D] = []


func _on_model_changed() -> void:
	for b in boats:
		b.queue_free()
	boats.clear()
	for i in level:
		var key := "boat_%d" % (i + 1)
		if not anchors.has(key):
			continue
		var b := MeshInstance3D.new()
		b.mesh = ModelsBuildings.boat(_seed + i)
		b.material_override = Materials.lowpoly()
		b.position = anchors[key]
		add_child(b)
		boats.append(b)


func _process(delta: float) -> void:
	super(delta)
	var t := Time.get_ticks_msec() / 1000.0
	for i in boats.size():
		var b := boats[i]
		b.position.y = (anchors.get("boat_%d" % (i + 1), Vector3.ZERO) as Vector3).y + sin(t * 1.3 + i * 2.0) * 0.08
		b.rotation = Vector3(sin(t * 1.1 + i) * 0.04, 0, sin(t * 0.9 + i * 1.7) * 0.06)
