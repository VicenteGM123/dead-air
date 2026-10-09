class_name Rig
extends Node3D
## Base class for procedurally animated characters (Heracles, the beasts, people). No AnimationPlayer: parts are
## pivots (add_part) posed from code every frame in _animate().
## Models face -Z (Godot forward) with +X on their right; origin on the ground between the feet. Gameplay drives a
## rig with:
##   set_locomotion(speed, max_speed)   every frame
##   play(action) -> duration           one-shot actions ("attack1", "hit", "death", ...)
##   hit_flash() / set_dissolve(v)      material feedback; set_metal(k) anime metal highlights on bronze / gold
## Rigs emit `event(name)` at key frames ("impact" when a strike lands, "release" when a projectile leaves,
## "step" on footfalls).

signal event(name: String)

var parts := {}
var meshes: Array[GeometryInstance3D] = []
var speed := 0.0
var speed_max := 5.0
var action := ""
var action_t := 0.0
var action_len := 0.0
var t := 0.0
var _flash := 0.0
var _dissolve := 0.0
var _fired := {}
## Material used by add_part (creatures override this with Materials.nyx()).
var part_material: Material = null
## This rig's own copies of its shared materials, so hit flash / dissolve / tint stay per rig (Materials.set_param).
var _own_materials := {}


func _init() -> void:
	t = randf() * 10.0


## Adds a pivot node (and a mesh under it, if given) to `parent` (a part name or "" for the root).
func add_part(part_name: String, mesh: Mesh, parent_name: String = "", pos: Vector3 = Vector3.ZERO, shadow: bool = true, mat: Material = null) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = part_name
	pivot.position = pos
	var parent: Node3D = self if parent_name == "" else parts[parent_name]
	parent.add_child(pivot)
	parts[part_name] = pivot
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _own_material(mat if mat else (part_material if part_material else Materials.lowpoly()))
		mi.set_meta(&"own_material", mi.material_override)
		if not shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		meshes.append(mi)
	return pivot


## This rig's copy of a shared material: all its parts share it, and Materials.set_param edits it in place.
func _own_material(m: Material) -> Material:
	if not (m is ShaderMaterial):
		return m
	if not _own_materials.has(m):
		_own_materials[m] = m.duplicate()
	return _own_materials[m]


## Soft additive halo (glowing eyes, fire). Returns the quad so it can be animated.
func add_glow(parent_name: String, pos: Vector3, color: Color, size: float, intensity: float = 1.0) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	q.mesh = qm
	q.material_override = Materials.glow_add()
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = pos
	Materials.set_param(q, "intensity", intensity)
	var parent: Node3D = self if parent_name == "" else parts[parent_name]
	parent.add_child(q)
	# Quad vertex colours are white: tint through the instance parameter.
	Materials.set_param(q, "tint_color", Vector3(color.r, color.g, color.b))
	return q


func set_locomotion(s: float, smax: float) -> void:
	speed = s
	speed_max = maxf(smax, 0.01)


func play(a: String) -> float:
	action = a
	action_t = 0.0
	action_len = _action_length(a)
	_fired.clear()
	return action_len


func is_busy() -> bool:
	return action != "" and action_t < action_len


## Fires `event(name)` once when the current action passes time `at`.
func _mark(name: String, at: float) -> void:
	if action_t >= at and not _fired.has(name):
		_fired[name] = true
		event.emit(name)


func _action_length(_a: String) -> float:
	return 0.4


func hit_flash(strength: float = 1.0) -> void:
	_flash = maxf(_flash, strength)
	_apply_flash()


func set_dissolve(v: float) -> void:
	_dissolve = v
	for m in meshes:
		Materials.set_param(m, "dissolve", v)


## Anime metal highlights (lowpoly.gdshader `metal`) on this rig's bronze and gold parts (0 off .. 1 full).
func set_metal(k: float) -> void:
	for m in _own_materials.values():
		var sm := m as ShaderMaterial
		if sm and sm.shader and sm.shader.resource_path == "res://shaders/lowpoly.gdshader":
			sm.set_shader_parameter("metal", k)


func set_tint(c: Color) -> void:
	for m in meshes:
		Materials.set_param(m, "tint", Vector3(c.r, c.g, c.b))


func set_shadows(on: bool) -> void:
	for m in meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_flash() -> void:
	for m in meshes:
		Materials.set_param(m, "flash", _flash)


func _process(delta: float) -> void:
	t += delta
	if action != "":
		action_t += delta
		if action_t >= action_len:
			var done := action
			action = ""
			_on_action_done(done)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 7.0)
		_apply_flash()
	_animate(delta)


func _on_action_done(_a: String) -> void:
	pass


func _animate(_delta: float) -> void:
	pass


## Normalised progress of the current action (0..1).
func ap() -> float:
	return clampf(action_t / maxf(action_len, 0.001), 0.0, 1.0)


static func ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


static func ease_in(x: float) -> float:
	return x * x


static func smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Piecewise curve helper: anticipation (0..a), strike (a..b), recovery (b..1). Returns -1..1 style pose weight.
static func strike_curve(p: float, a: float, b: float) -> float:
	if p < a:
		return -smooth(p / a) * 0.35
	if p < b:
		return lerpf(-0.35, 1.0, ease_out((p - a) / (b - a)))
	return lerpf(1.0, 0.0, smooth((p - b) / (1.0 - b)))


static func lerp_angle_v(a: Vector3, b: Vector3, k: float) -> Vector3:
	return Vector3(lerp_angle(a.x, b.x, k), lerp_angle(a.y, b.y, k), lerp_angle(a.z, b.z, k))
