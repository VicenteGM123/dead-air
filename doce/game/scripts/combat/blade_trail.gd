class_name BladeTrail
extends MeshInstance3D
## The crescent a sword leaves while it cuts (Wind Waker): a ribbon between the blade and its tip over the last
## few frames: a white leading edge at the tip, a cool core down the blade (gold for the heavy spin), fading
## towards the hilt and with age. World space, top level.
## It is drawn pulled VIEW_PULL m towards the camera (fx.gdshader `view_pull`: same place on screen, nearer in
## depth), so the arc shows over the hero's own body and the foe it cuts (from behind him, a backhand's blade is
## behind his back) while walls and pillars further than that still hide it.
## Usage: trail.active = true while the blade's active frames run (the rig's blade is sampled every frame).
## The ribbon is rebuilt into an ImmediateMesh each frame (a few dozen vertices; nothing kept alive when idle).

const MAX_SAMPLES := 20
## Seconds a sample stays in the ribbon.
const LIFE := 0.2
## Metres the ribbon is drawn towards the camera (depth only).
const VIEW_PULL := 1.3
## The inner edge of a fresh sample along the blade (0 hilt .. 1 tip); old samples narrow towards the tip.
const INNER := 0.1
const INNER_OLD := 0.6

var active := false
## The rig whose blade_segment() is sampled every frame while active (after the rig has posed: process_priority).
var rig: Node3D = null
## The heavy blow's spin: a cool core instead of the warm one.
var heavy := false
var _root := PackedVector3Array()
var _tip := PackedVector3Array()
var _age := PackedFloat32Array()
var _count := 0
var _im: ImmediateMesh
var _drawn := false

## A white leading edge; a cool sky-blue core for the light blows (Wind Waker's crescent: it stands out against the
## warm golden-hour palette, the sand and the hero's red cape) and a gold one for the charged spin.
const EDGE := Color(1.0, 1.0, 1.0)
const CORE := Color(0.66, 0.86, 1.0)
const CORE_HEAVY := Color(1.0, 0.8, 0.36)


func _ready() -> void:
	top_level = true
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fx.gdshader") as Shader
	m.set_shader_parameter("view_pull", VIEW_PULL)
	m.render_priority = 10
	material_override = m
	extra_cull_margin = 64.0
	_root.resize(MAX_SAMPLES)
	_tip.resize(MAX_SAMPLES)
	_age.resize(MAX_SAMPLES)
	global_transform = Transform3D.IDENTITY


## Adds the blade's current root and tip (world). Ignored while inactive.
func sample(root: Vector3, tip: Vector3) -> void:
	if not active:
		return
	if _count > 0 and _tip[_count - 1].distance_squared_to(tip) < 0.0004:
		return
	if _count >= MAX_SAMPLES:
		for i in MAX_SAMPLES - 1:
			_root[i] = _root[i + 1]
			_tip[i] = _tip[i + 1]
			_age[i] = _age[i + 1]
		_count = MAX_SAMPLES - 1
	_root[_count] = root
	_tip[_count] = tip
	_age[_count] = 0.0
	_count += 1


func clear() -> void:
	_count = 0


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	if active and rig != null and rig.has_method("blade_segment"):
		var seg: PackedVector3Array = rig.call("blade_segment")
		sample(seg[0], seg[1])
	# age and drop old samples
	var keep := 0
	for i in _count:
		var a := _age[i] + delta
		if a < LIFE:
			_root[keep] = _root[i]
			_tip[keep] = _tip[i]
			_age[keep] = a
			keep += 1
	_count = keep
	if _count < 2:
		if _drawn:
			_im.clear_surfaces()
			_drawn = false
		return
	var core := CORE_HEAVY if heavy else CORE
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _count - 1:
		var k0 := 1.0 - _age[i] / LIFE
		var k1 := 1.0 - _age[i + 1] / LIFE
		# three rows: the inner edge (clear), the warm core, the white edge at the tip
		var u0 := lerpf(INNER_OLD, INNER, k0)
		var u1 := lerpf(INNER_OLD, INNER, k1)
		var r0 := _root[i].lerp(_tip[i], u0)
		var r1 := _root[i + 1].lerp(_tip[i + 1], u1)
		var m0 := _root[i].lerp(_tip[i], lerpf(u0, 1.0, 0.62))
		var m1 := _root[i + 1].lerp(_tip[i + 1], lerpf(u1, 1.0, 0.62))
		var t0 := _tip[i]
		var t1 := _tip[i + 1]
		var ci := Color(core.r, core.g, core.b, 0.0)
		var cm0 := Color(core.r, core.g, core.b, minf(1.0, 0.95 * k0))
		var cm1 := Color(core.r, core.g, core.b, minf(1.0, 0.95 * k1))
		var ct0 := Color(EDGE.r, EDGE.g, EDGE.b, minf(1.0, 1.2 * k0))
		var ct1 := Color(EDGE.r, EDGE.g, EDGE.b, minf(1.0, 1.2 * k1))
		_tri(r0, m0, m1, ci, cm0, cm1)
		_tri(r0, m1, r1, ci, cm1, ci)
		_tri(m0, t0, t1, cm0, ct0, ct1)
		_tri(m0, t1, m1, cm0, ct1, cm1)
	_im.surface_end()
	_drawn = true


func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_im.surface_set_color(ca)
	_im.surface_add_vertex(a)
	_im.surface_set_color(cb)
	_im.surface_add_vertex(b)
	_im.surface_set_color(cc)
	_im.surface_add_vertex(c)
