class_name ToonScreen
extends Node
## The Wind Waker screen passes, always on (port of the style test's tools/style_toon.gd):
##  - ink outlines + rim light: a full-screen quad parented to the active camera (shaders/toon_edges.gdshader,
##    drawn in the transparent pass from the depth buffer);
##  - final grade: bloom, light leak from the sun's side, vibrance, split toning, vignette
##    (shaders/toon_post.gdshader on a CanvasLayer under the UI).
## The cel lighting, palette, sea and sky live in the shaders and in TimeOfDay's moods; each frame this node reads
## the current mood (rim colour and strength, line tint, bloom, leak, saturation) from TimeOfDay.current().
##
## Usage: var ts := ToonScreen.new(); add_child(ts); ts.setup(tod)   (follows whichever Camera3D is current)
## Debug: noedges=1 / nopost=1 hide a pass, edgedebug=1 shows the line (red) and rim (green) masks,
## stats=1 prints primitives / draw calls once.

## Below the UI (CanvasLayers at 0 and up) so the grade only touches the 3D view.
const POST_LAYER := -1

var tod: TimeOfDay
var edges: MeshInstance3D
var edges_mat: ShaderMaterial
var post_layer: CanvasLayer
var post_mat: ShaderMaterial
var _frames := 0


func setup(time_of_day: TimeOfDay) -> void:
	tod = time_of_day


func _ready() -> void:
	edges = MeshInstance3D.new()
	edges.name = "ToonEdges"
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	edges.mesh = qm
	edges.extra_cull_margin = 16384.0
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edges_mat = ShaderMaterial.new()
	edges_mat.shader = load("res://shaders/toon_edges.gdshader")
	edges_mat.render_priority = 100
	edges_mat.set_shader_parameter("debug", float(Game.arg("edgedebug", "0")))
	edges.material_override = edges_mat
	edges.position = Vector3(0, 0, -1.0)
	edges.visible = not Game.arg_on("noedges")

	post_layer = CanvasLayer.new()
	post_layer.name = "ToonPost"
	post_layer.layer = POST_LAYER
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/toon_post.gdshader")
	post_mat.set_shader_parameter("debug_mip", float(Game.arg("mipdebug", "-1")))
	rect.material = post_mat
	post_layer.add_child(rect)
	post_layer.visible = not Game.arg_on("nopost")


func _exit_tree() -> void:
	if is_instance_valid(edges) and not edges.is_queued_for_deletion():
		edges.queue_free()


## Keeps the edge quad on the current camera (title orbit, follow camera, fly camera...).
func _attach(cam: Camera3D) -> void:
	if edges.get_parent() == cam:
		return
	if edges.get_parent():
		edges.get_parent().remove_child(edges)
	cam.add_child(edges)
	edges.position = Vector3(0, 0, -maxf(cam.near * 2.0, 0.2))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_attach(cam)
	_frames += 1
	if Game.arg_on("stats") and _frames == 30:
		var rs := RenderingServer
		print("TOON STATS primitives=%d drawcalls=%d objects=%d" % [rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	if tod == null or not is_instance_valid(tod):
		return
	var m: Dictionary = tod.current()
	if m.is_empty():
		return
	var to_light := TimeOfDay.dir_from(m["elev"], m["azim"])
	edges_mat.set_shader_parameter("light_dir", to_light)
	edges_mat.set_shader_parameter("rim_color", m["rim"])
	edges_mat.set_shader_parameter("rim_strength", m["rim_k"])
	edges_mat.set_shader_parameter("line_tint", m["line"])
	post_mat.set_shader_parameter("bloom", m["bloom"])
	# Light leak: the light's direction seen from the camera, pushed just outside the frame.
	var v := cam.global_transform.basis.inverse() * to_light
	var sd := Vector2(v.x, -v.y)
	if sd.length() > 0.001:
		sd = sd.normalized()
	post_mat.set_shader_parameter("leak_pos", Vector2(0.5, 0.5) + sd * Vector2(0.62, 0.75))
	post_mat.set_shader_parameter("leak_col", m["rim"])
	post_mat.set_shader_parameter("leak_k", m.get("leak", 0.0))
	post_mat.set_shader_parameter("sat", m["sat"])
