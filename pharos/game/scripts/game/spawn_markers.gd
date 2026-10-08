class_name SpawnMarkers
extends Node3D
## During the day, violet mist columns rise over the sea where the next night's creatures will land.

var _cols: Array = []
var _shown: Array = []
var _k: Array = []


func setup(island: Island) -> void:
	for b in island.beaches:
		var root := Node3D.new()
		add_child(root)
		var spawn: Vector3 = b["spawn"]
		root.global_position = Vector3(spawn.x, 0.0, spawn.z)
		for i in 2:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(4.5, 16.0)
			q.mesh = qm
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/mist_column.gdshader")
			q.material_override = m
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.position = Vector3(0, 8.0, 0)
			q.rotation.y = PI * 0.5 * i + PI * 0.25
			root.add_child(q)
		var ring := MeshInstance3D.new()
		var rb := MeshBuilder.new(71)
		rb.ring(Vector3.ZERO, 3.0, 2.6, 0.02, 32, Color.WHITE)
		ring.mesh = rb.commit()
		ring.material_override = Materials.glow_flat()
		ring.position = Vector3(0, 0.12, 0)
		ring.set_instance_shader_parameter("tint_color", Vector3(0.62, 0.45, 1.0))
		root.add_child(ring)
		_cols.append(root)
		_shown.append(false)
		_k.append(0.0)
		root.visible = false


func show_lanes(lanes: Array) -> void:
	for i in _cols.size():
		_shown[i] = lanes.has(i)


func hide_all() -> void:
	for i in _cols.size():
		_shown[i] = false


func shown_positions() -> Array:
	var out: Array = []
	for i in _cols.size():
		if _shown[i]:
			out.append(_cols[i].global_position)
	return out


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in _cols.size():
		_k[i] = move_toward(_k[i], 1.0 if _shown[i] else 0.0, delta * 0.8)
		var root: Node3D = _cols[i]
		root.visible = _k[i] > 0.01
		if not root.visible:
			continue
		for c in root.get_children():
			(c as MeshInstance3D).set_instance_shader_parameter("intensity", _k[i] * (0.8 + 0.2 * sin(t * 1.7 + i)))
		var ring: Node3D = root.get_child(root.get_child_count() - 1)
		ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 2.0 + i))
