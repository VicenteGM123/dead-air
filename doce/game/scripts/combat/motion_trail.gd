class_name MotionTrail
extends MeshInstance3D
## A camera-facing ribbon of light behind something fast (CORE: the thrown chain spear): the last `life` seconds of
## a point's path, widest and brightest at the head and thinning to nothing at the tail, so a throw reads even when
## the spear flies straight away from the camera (its own mesh is then only a few pixels). World space, top level.
## Usage: `active = true` while it flies and add_point(p) every drawn frame; it fades out by itself.
## The ribbon is rebuilt into an ImmediateMesh each frame (a few dozen vertices; nothing kept alive when idle).

const MAX_POINTS := 24

## Seconds a point stays in the ribbon.
var life := 0.14
## Half-width of the ribbon at its head (m).
var width := 0.075
var color := Color(1.0, 0.94, 0.78)
var active := false
var _p := PackedVector3Array()
var _age := PackedFloat32Array()
var _n := 0
var _im: ImmediateMesh
var _drawn := false


func _ready() -> void:
	top_level = true
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fx.gdshader") as Shader
	material_override = m
	extra_cull_margin = 64.0
	_p.resize(MAX_POINTS)
	_age.resize(MAX_POINTS)
	global_transform = Transform3D.IDENTITY


## Adds the head's current position (world). Ignored while inactive.
func add_point(p: Vector3) -> void:
	if not active:
		return
	if _n > 0 and _p[_n - 1].distance_squared_to(p) < 0.0004:
		return
	if _n >= MAX_POINTS:
		for i in MAX_POINTS - 1:
			_p[i] = _p[i + 1]
			_age[i] = _age[i + 1]
		_n = MAX_POINTS - 1
	_p[_n] = p
	_age[_n] = 0.0
	_n += 1


func clear() -> void:
	_n = 0


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	var keep := 0
	for i in _n:
		var a := _age[i] + delta
		if a < life:
			_p[keep] = _p[i]
			_age[keep] = a
			keep += 1
	_n = keep
	if _n < 2:
		if _drawn:
			_im.clear_surfaces()
			_drawn = false
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else _p[_n - 1] + Vector3(0, 0, 5)
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Color()
	for i in _n:
		# along the path (the segment to the next point; the last point uses the one before)
		var d := (_p[i + 1] - _p[i]) if i + 1 < _n else (_p[i] - _p[i - 1])
		var side := d.cross(eye - _p[i])
		side = side.normalized() if side.length_squared() > 1e-10 else Vector3.UP
		# age fades it; the tail (oldest) also thins to a point
		var k := clampf(1.0 - _age[i] / life, 0.0, 1.0)
		var pos_k := float(i) / float(_n - 1)
		var w := width * k * (0.25 + 0.75 * pos_k)
		var l := _p[i] - side * w
		var r := _p[i] + side * w
		var c := Color(color.r, color.g, color.b, minf(1.0, k * (0.35 + 0.75 * pos_k)))
		if i > 0:
			_tri(prev_l, prev_r, r, prev_c, prev_c, c)
			_tri(prev_l, r, l, prev_c, c, c)
		prev_l = l
		prev_r = r
		prev_c = c
	_im.surface_end()
	_drawn = true


func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_im.surface_set_color(ca)
	_im.surface_add_vertex(a)
	_im.surface_set_color(cb)
	_im.surface_add_vertex(b)
	_im.surface_set_color(cc)
	_im.surface_add_vertex(c)
