class_name Sea
extends Node3D
## The Aegean: a finely subdivided plane around the island (faceted waves) plus a flat skirt to the horizon.

func build() -> void:
	var inner := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(250, 250)
	pm.subdivide_width = 124
	pm.subdivide_depth = 124
	inner.mesh = pm
	inner.material_override = Materials.water()
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inner)
	var outer := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(2400, 2400)
	om.subdivide_width = 24
	om.subdivide_depth = 24
	outer.mesh = om
	outer.position.y = -0.6
	outer.material_override = Materials.water()
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outer)
