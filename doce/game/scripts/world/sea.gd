class_name Sea
extends Node3D
## The toon sea (shaders/water.gdshader): a finely subdivided plane that follows the camera in whole-cell steps (the
## waves are computed in world space, so snapping keeps the vertex grid fixed on the water and nothing swims),
## plus a coarse skirt to the horizon. Shore foam and colour bands come from the depth texture the World bakes
## (global g_water_tex over g_water_rect: R = 0 at the shoreline .. 1 in deep water).
##
##   var sea := Sea.new(); add_child(sea); sea.build()

## Inner plane size and cell (m): 280 m around the camera, 2 m facets.
const INNER := 280.0
const CELL := 2.0
const OUTER := 4000.0

var sea_level := 0.0
var _inner: MeshInstance3D
var _outer: MeshInstance3D


func build(level: float = 0.0) -> void:
	sea_level = level
	_inner = MeshInstance3D.new()
	_inner.name = "SeaNear"
	var pm := PlaneMesh.new()
	pm.size = Vector2(INNER, INNER)
	pm.subdivide_width = int(INNER / CELL) - 1
	pm.subdivide_depth = int(INNER / CELL) - 1
	_inner.mesh = pm
	_inner.material_override = Materials.water()
	_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner.extra_cull_margin = 4.0
	add_child(_inner)
	_outer = MeshInstance3D.new()
	_outer.name = "SeaFar"
	var om := PlaneMesh.new()
	om.size = Vector2(OUTER, OUTER)
	om.subdivide_width = 31
	om.subdivide_depth = 31
	_outer.mesh = om
	_outer.material_override = Materials.water()
	_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outer)
	_follow(Vector3.ZERO)


func _follow(p: Vector3) -> void:
	if _inner == null:
		return
	var step := CELL * 2.0
	_inner.global_position = Vector3(snappedf(p.x, step), sea_level, snappedf(p.z, step))
	# The skirt sits a little lower so it never pokes through the near plane; its seam is far out in the haze.
	var big := OUTER / 32.0
	_outer.global_position = Vector3(snappedf(p.x, big), sea_level - 0.3, snappedf(p.z, big))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Centre the fine plane a little ahead of the camera: right under a third-person camera, over the middle of
		# the view for a high overview.
		var f := -cam.global_transform.basis.z
		var flat := Vector3(f.x, 0.0, f.z)
		var ahead := clampf((cam.global_position.y - sea_level) * 1.5, 0.0, INNER * 0.4)
		_follow(cam.global_position + (flat.normalized() * ahead if flat.length() > 0.01 else Vector3.ZERO))
