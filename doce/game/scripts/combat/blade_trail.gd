class_name BladeTrail
extends MeshInstance3D
## The smear a sword leaves while it cuts (anime / Wind Waker): a crescent between the blade and its tip over the
## last fraction of a second, drawn as crisp bands (shaders/trail.gdshader): a solid leading-edge stroke along the
## path of the tip (camera-facing, so it reads even when the blade swings towards or away from the view), and a
## body that fills the swept arc from about a third of the blade out to the tip, opaque on the tip side and clear on
## the inner edge, with a coloured accent band along the tip. Older parts of the arc narrow towards the tip and the
## tail fades, so the crescent tapers to a point and is gone LIFE s after the blade passed (never a blob over the
## hero or the foe). World space, top level.
## `style` picks the look (STYLES):
##   &"light"     white / cream, thin bright core, quick (0.15 s): the combo's cuts
##   &"finisher"  wider (from a fifth of the blade), a warm gold leading edge, a little longer (0.19 s): the closing
##                blows
##   &"heavy"     the charged spin: a full golden ring (0.34 s: the whole turn stays drawn)
##   &"thrust"    a straight lance-like streak along the blade's travel instead of a crescent, and a pierce ring
##                round the point that bursts open where the thrust stops (it reads from behind the hero, where
##                the lance itself is foreshortened) (0.16 s)
## The old `heavy` bool still works: true sets the heavy style, false clears it (back to light; other styles stay).
## It is drawn pulled VIEW_PULL m towards the camera (`view_pull`: same place on screen, nearer in depth), so the
## arc shows over the hero's own body and the foe it cuts (from behind him, a backhand's blade is behind his back)
## while walls and pillars further than that still hide it.
## Usage: trail.style = &"finisher"; trail.active = true while the blade's active frames run (the rig's
## blade_segment() is sampled every frame, after the rig has posed: process_priority). Between samples the arc is
## rounded with a Catmull-Rom spline (a 50-degree step between two frames at 24 fps still draws a smooth curve).
## Rebuilt into an ImmediateMesh each frame while visible (two strips, a few dozen to ~200 vertices; nothing when
## idle).

const MAX_SAMPLES := 64
## Seconds a sample stays in the ribbon (the light style; each style has its own `life`).
const LIFE := 0.14
## Metres the ribbon is drawn towards the camera (depth only).
const VIEW_PULL := 1.3
## The arc between two samples is split so no piece is longer than this (m, along the tip's path).
const SUB_LEN := 0.09
const SUB_MAX := 8
## A new sample only when the tip moved this far (m) since the last one.
const MIN_STEP := 0.015

## Per style: life (s); inner = where the fresh body's inner edge sits along the blade (0 hilt .. 1 tip) and
## inner_old where the oldest part's does (the crescent narrows towards the tip as it ages; `taper` shapes it);
## line_w = the leading-edge stroke's width (m, at the fresh end; it thins to a third at the tail); colours (sRGB)
## and the shader's band settings (see trail.gdshader). Thrust: lance_w = the lance's width (m), point = how far (m)
## its point runs ahead of the tip; ring_r0 / ring_r1 / ring_w = the pierce ring's radius while the tip drives on and
## once it has stopped (m), and its stroke width (m).
const STYLES := {
	&"light": {"life": 0.15, "inner": 0.34, "inner_old": 0.9, "taper": 0.75, "line_w": 0.036,
		"line": Color(1.0, 1.0, 1.0), "body": Color(1.0, 0.97, 0.9), "accent": Color(1.0, 1.0, 0.98),
		"body_a": 0.68, "accent_w": 0.28, "accent_a": 0.96, "body_soft": 0.22, "tail": 0.3, "age_a": 0.45},
	&"finisher": {"life": 0.19, "inner": 0.22, "inner_old": 0.84, "taper": 0.6, "line_w": 0.062,
		"line": Color(1.0, 0.76, 0.27), "body": Color(1.0, 0.92, 0.72), "accent": Color(1.0, 0.99, 0.93),
		"body_a": 0.58, "accent_w": 0.3, "accent_a": 0.96, "body_soft": 0.2, "tail": 0.3, "age_a": 0.45},
	&"heavy": {"life": 0.34, "inner": 0.4, "inner_old": 0.8, "taper": 0.5, "line_w": 0.06,
		"line": Color(1.0, 0.99, 0.92), "body": Color(1.0, 0.85, 0.5), "accent": Color(1.0, 0.7, 0.2),
		"body_a": 0.55, "accent_w": 0.36, "accent_a": 0.93, "body_soft": 0.2, "tail": 0.35, "age_a": 0.35},
	&"thrust": {"life": 0.16, "inner": 0.5, "inner_old": 0.9, "taper": 0.7, "line_w": 0.034,
		"line": Color(1.0, 1.0, 1.0), "body": Color(1.0, 0.96, 0.86), "accent": Color(1.0, 1.0, 0.97),
		"body_a": 0.6, "accent_w": 0.4, "accent_a": 0.95, "body_soft": 0.3, "tail": 0.3, "age_a": 0.3,
		"lance_w": 0.26, "point": 0.32, "ring_r0": 0.07, "ring_r1": 0.36, "ring_w": 0.04},
}

var active := false
## The rig whose blade_segment() is sampled every frame while active (anything with that method).
var rig: Node3D = null
## The look of the next cuts (see STYLES).
var style: StringName = &"light":
	set = set_style
## Old API: the heavy blow's spin (true = style &"heavy").
var heavy: bool:
	get:
		return style == &"heavy"
	set(v):
		if v:
			set_style(&"heavy")
		elif style == &"heavy":
			set_style(&"light")

var _root := PackedVector3Array()
var _tip := PackedVector3Array()
var _age := PackedFloat32Array()
var _count := 0
var _im: ImmediateMesh
var _mat: ShaderMaterial
var _drawn := false
var _st: Dictionary = STYLES[&"light"]
# the dense arc (columns after subdivision), reused every frame
var _cr := PackedVector3Array()
var _ct := PackedVector3Array()
var _cf := PackedFloat32Array()


func _init() -> void:
	_im = ImmediateMesh.new()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/trail.gdshader") as Shader
	_mat.set_shader_parameter("view_pull", VIEW_PULL)
	_mat.render_priority = 10
	_apply_style()


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _mat
	extra_cull_margin = 64.0
	_root.resize(MAX_SAMPLES)
	_tip.resize(MAX_SAMPLES)
	_age.resize(MAX_SAMPLES)
	global_transform = Transform3D.IDENTITY


func set_style(s: StringName) -> void:
	if not STYLES.has(s):
		push_warning("BladeTrail: unknown style '%s' (light used)" % s)
		s = &"light"
	style = s
	_st = STYLES[s]
	_apply_style()


func _apply_style() -> void:
	if _mat == null:
		return
	var st := _st
	for k in ["line", "body", "accent"]:
		var c: Color = st[k]
		_mat.set_shader_parameter(k + "_col", Vector3(c.r, c.g, c.b))
	for k in ["body_a", "accent_w", "accent_a", "body_soft", "tail", "age_a"]:
		_mat.set_shader_parameter(k, float(st[k]))


## Adds the blade's current root and tip (world). Ignored while inactive.
func sample(root: Vector3, tip: Vector3) -> void:
	if not active:
		return
	if _count > 0 and _tip[_count - 1].distance_squared_to(tip) < MIN_STEP * MIN_STEP:
		return
	if _root.size() < MAX_SAMPLES:
		_root.resize(MAX_SAMPLES)
		_tip.resize(MAX_SAMPLES)
		_age.resize(MAX_SAMPLES)
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
	var life := float(_st["life"])
	# age and drop old samples
	var keep := 0
	for i in _count:
		var a := _age[i] + delta
		if a < life:
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
	_densify(life)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := cam.global_position if cam else _tip[_count - 1] + Vector3(0, 2, 5)
	_im.clear_surfaces()
	if style == &"thrust":
		_draw_lance(eye)
	else:
		_draw_body()
	_draw_line(eye)
	if style == &"thrust":
		_draw_ring()
	_drawn = true


## The samples rounded into a dense arc: _cr / _ct (root and tip) and _cf (freshness 1 now .. 0 oldest).
func _densify(life: float) -> void:
	_cr.clear()
	_ct.clear()
	_cf.clear()
	for i in _count - 1:
		var i0 := maxi(i - 1, 0)
		var i3 := mini(i + 2, _count - 1)
		var n := clampi(ceili(_tip[i].distance_to(_tip[i + 1]) / SUB_LEN), 1, SUB_MAX)
		var f0 := 1.0 - _age[i] / life
		var f1 := 1.0 - _age[i + 1] / life
		for j in n:
			var s := float(j) / float(n)
			_cr.append(_catmull(_root[i0], _root[i], _root[i + 1], _root[i3], s))
			_ct.append(_catmull(_tip[i0], _tip[i], _tip[i + 1], _tip[i3], s))
			_cf.append(lerpf(f0, f1, s))
	_cr.append(_root[_count - 1])
	_ct.append(_tip[_count - 1])
	_cf.append(1.0 - _age[_count - 1] / life)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, s: float) -> Vector3:
	var s2 := s * s
	var s3 := s2 * s
	return 0.5 * ((2.0 * p1) + (p2 - p0) * s + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * s3)


## The crescent: from the inner edge (which slides out towards the tip as the arc ages) to the tip.
func _draw_body() -> void:
	var inner := float(_st["inner"])
	var inner_old := float(_st["inner_old"])
	var taper := float(_st["taper"])
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for j in _ct.size():
		var f := clampf(_cf[j], 0.0, 1.0)
		var u_in := lerpf(inner_old, inner, pow(f, taper))
		_im.surface_set_uv2(Vector2(0.0, 0.0))
		_im.surface_set_uv(Vector2(0.0, f))
		_im.surface_add_vertex(_cr[j].lerp(_ct[j], u_in))
		_im.surface_set_uv(Vector2(1.0, f))
		_im.surface_add_vertex(_ct[j])
	_im.surface_end()


## The thrust: a lance along the tip's path, camera-facing, widest just behind the tip and tapering back along the
## travel, with a point running ahead of the tip.
func _draw_lance(eye: Vector3) -> void:
	var n := _ct.size()
	var w := float(_st["lance_w"])
	var head := _ct[n - 1] - _ct[n - 2]
	var travel := head.normalized() if head.length() > 1e-4 else (_ct[n - 1] - _cr[n - 1]).normalized()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for j in n + 1:
		var p: Vector3
		var f: float
		var hw: float
		if j < n:
			p = _ct[j]
			f = clampf(_cf[j], 0.0, 1.0)
			hw = 0.5 * w * pow(f, 1.6)
		else:
			p = _ct[n - 1] + travel * float(_st["point"])
			f = 1.0
			hw = 0.0
		var side := _side(j, p, eye, travel)
		_im.surface_set_uv2(Vector2(0.5, 0.0))
		_im.surface_set_uv(Vector2(0.0, f))
		_im.surface_add_vertex(p - side * hw)
		_im.surface_set_uv(Vector2(1.0, f))
		_im.surface_add_vertex(p + side * hw)
	_im.surface_end()


## The thrust's pierce ring: a thin circle round the lance's point, square to its travel, small while the tip drives
## on; where the thrust stops it bursts open (ring_r0 -> ring_r1) and fades with the newest sample. From behind the
## hero (the lance foreshortened to a dot) it is a circle facing the camera: the stab reads.
func _draw_ring() -> void:
	var n := _ct.size()
	var head := _ct[n - 1] - _ct[n - 2]
	if head.length() < 1e-4:
		return
	var travel := head.normalized()
	var f := clampf(_cf[n - 1], 0.0, 1.0)
	var k := 1.0 - f
	var r := lerpf(float(_st["ring_r0"]), float(_st["ring_r1"]), 1.0 - (1.0 - k) * (1.0 - k))
	var w := float(_st["ring_w"]) * (0.5 + 0.5 * f)
	var c := _ct[n - 1] + travel * float(_st["point"]) * 0.45
	var x := travel.cross(Vector3.UP if absf(travel.y) < 0.9 else Vector3.RIGHT).normalized()
	var y := travel.cross(x).normalized()
	const SEG := 28
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in SEG + 1:
		var a := TAU * float(i) / float(SEG)
		var d := x * cos(a) + y * sin(a)
		_im.surface_set_uv2(Vector2(1.0, 0.0))
		_im.surface_set_uv(Vector2(0.0, f))
		_im.surface_add_vertex(c + d * (r - w * 0.5))
		_im.surface_set_uv(Vector2(1.0, f))
		_im.surface_add_vertex(c + d * (r + w * 0.5))
	_im.surface_end()


## The leading edge: a camera-facing stroke along the tip's path (thinning to a third at the tail).
func _draw_line(eye: Vector3) -> void:
	var n := _ct.size()
	var lw := float(_st["line_w"])
	var head := _ct[n - 1] - _ct[n - 2]
	var travel := head.normalized() if head.length() > 1e-4 else Vector3.FORWARD
	var thrust := style == &"thrust"
	var last := n + (1 if thrust else 0)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for j in last:
		var p: Vector3
		var f: float
		if j < n:
			p = _ct[j]
			f = clampf(_cf[j], 0.0, 1.0)
		else:
			p = _ct[n - 1] + travel * float(_st["point"]) * 0.8
			f = 1.0
		var hw := 0.5 * lw * (0.33 + 0.67 * f)
		if j == last - 1 and thrust:
			hw = 0.0
		var side := _side(j, p, eye, travel)
		_im.surface_set_uv2(Vector2(1.0, 0.0))
		_im.surface_set_uv(Vector2(0.0, f))
		_im.surface_add_vertex(p - side * hw)
		_im.surface_set_uv(Vector2(1.0, f))
		_im.surface_add_vertex(p + side * hw)
	_im.surface_end()


## The unit vector across the path at column `j` (point `p`), in the plane facing the eye.
func _side(j: int, p: Vector3, eye: Vector3, fallback: Vector3) -> Vector3:
	var n := _ct.size()
	var a := _ct[clampi(j - 1, 0, n - 1)]
	var b := _ct[clampi(j + 1, 0, n - 1)]
	var tg := b - a
	if tg.length_squared() < 1e-8:
		tg = fallback
	var s := tg.cross(eye - p)
	if s.length_squared() < 1e-10:
		s = tg.cross(Vector3.UP)
	return s.normalized()
