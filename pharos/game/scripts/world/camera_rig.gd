class_name CameraRig
extends Node3D
## Follow camera: high three-quarter view like a diorama, smooth follow with look-ahead, trauma-based shake.

var cam: Camera3D
var target: Node3D = null
var focus := Vector3.ZERO
var pitch_deg := 52.0
var distance := 30.0
var yaw_deg := 0.0
var fov := 34.0
var look_ahead := Vector3.ZERO
var trauma := 0.0
var free_mode := false
var _noise := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = fov
	cam.near = 0.5
	cam.far = 1500.0
	add_child(cam)
	_noise.frequency = 2.0


func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)


func snap() -> void:
	if target:
		focus = target.global_position
	_place(0.0)


func _process(delta: float) -> void:
	_t += delta
	if target and not free_mode:
		var goal := target.global_position + look_ahead
		focus = focus.lerp(goal, 1.0 - exp(-delta * 4.5))
	_place(delta)
	trauma = maxf(0.0, trauma - delta * 1.6)


func _place(_delta: float) -> void:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	var pos := focus + back * distance
	cam.fov = fov
	var shake := trauma * trauma
	var off := Vector3(_noise.get_noise_2d(_t * 30.0, 0.0), _noise.get_noise_2d(0.0, _t * 30.0), 0.0) * shake * 0.9
	cam.global_position = pos + off
	cam.look_at(focus + off * 0.5, Vector3.UP)
