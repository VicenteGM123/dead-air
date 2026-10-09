class_name CameraRig
extends Node3D
## Third-person orbit camera: a pivot that follows the hero at shoulder height, a SpringArm3D (collides with world
## layer 1, so rocks and slopes push the camera in instead of hiding the hero) and the Camera3D at its end.
##  - mouse look while the mouse is captured: a click on the game captures it (the browser's pointer lock on the
##    web), Esc releases it (the browser does that by itself on the web); right stick look on a gamepad;
##    sensitivity and inversion from Settings (mouse_sens, pad_sens, invert_x, invert_y);
##  - smooth follow (tight horizontally, softer vertically so jumps do not jerk the view), pitch limits, a gentle
##    auto-recentre behind the hero while running with no look input;
##  - lock-on (Tab / middle click / R3): picks the lockable in front of the camera, keeps hero and target framed,
##    and emits Game.lock_changed(target) (null when released, lost or dead);
##  - trauma shake (Game.shake -> add_trauma) through the camera's h/v offsets, so it never fights the spring arm;
##  - modes: "follow" (the game), "orbit" (title: slow turn around `focus`), "fly" (free camera for renders and
##    inspection: WASD + mouse, E / Q up / down, Shift fast; debug args cam=fly pos=x,y,z yaw=deg pitch=deg).
##    In follow mode pitch=deg sets the starting pitch (the camera starts behind the hero).
## Angles: yaw 0 = camera behind a hero facing -Z (north), increasing anticlockwise seen from above; pitch < 0 looks
## down. The rig is moved in _process and its physics interpolation is off; the hero's visual is interpolated by
## the hero itself.

const PIVOT_HEIGHT := 1.55
const PITCH_MIN := -68.0
const PITCH_MAX := 38.0
const MOUSE_DEG_PER_PX := 0.14
const PAD_DEG_PER_S := 170.0
const LOCK_RANGE := 24.0
const LOCK_KEEP := 30.0

var mode := "follow"
var target: Node3D = null
var yaw := 0.0 # degrees
var pitch := -14.0 # degrees
var distance := 5.5
var fov := 60.0
var focus := Vector3.ZERO
var trauma := 0.0
var lock_target: Node3D = null
## Title orbit: centre, radius, height and angular speed (deg/s).
var orbit_center := Vector3.ZERO
var orbit_radius := 60.0
var orbit_height := 22.0
var orbit_speed := 3.0

var spring: SpringArm3D
var cam: Camera3D
var _noise := FastNoiseLite.new()
var _t := 0.0
var _look_idle := 0.0
var _fly_pos := Vector3.ZERO
var _vy_focus := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 10 # after the hero and the world have moved this frame
	spring = SpringArm3D.new()
	spring.name = "SpringArm"
	spring.collision_mask = 1
	var sph := SphereShape3D.new()
	sph.radius = 0.28
	spring.shape = sph
	spring.margin = 0.08
	spring.spring_length = distance
	add_child(spring)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov
	cam.near = 0.08
	cam.far = 2500.0
	spring.add_child(cam)
	cam.current = true
	_noise.frequency = 2.0
	if Game.arg("cam", "") == "fly":
		set_fly(Game.arg_vec3("pos", Vector3(0, 60, 200)), Game.arg_f("yaw", 0.0), Game.arg_f("pitch", -20.0))
	else:
		yaw = Game.arg_f("yaw", yaw)
		pitch = Game.arg_f("pitch", pitch)


# --- public ------------------------------------------------------------------------------------------------

func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)


## Horizontal basis of the view (for camera-relative movement): -z = forward on the ground, x = right.
func yaw_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw))


func is_fly() -> bool:
	return mode == "fly"


## Follow `t` (the hero), placed right behind it.
func follow(t: Node3D, snap_behind: bool = true) -> void:
	target = t
	mode = "follow"
	if snap_behind and t:
		var f: float = float(t.get("facing")) if "facing" in t else 0.0
		yaw = rad_to_deg(f)
		pitch = clampf(Game.arg_f("pitch", -14.0), PITCH_MIN, PITCH_MAX)
	snap()


func set_orbit(center: Vector3, radius: float, height: float, speed_deg: float = 3.0) -> void:
	mode = "orbit"
	orbit_center = center
	orbit_radius = radius
	orbit_height = height
	orbit_speed = speed_deg
	_release_lock()


func set_fly(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	mode = "fly"
	_fly_pos = pos
	yaw = yaw_deg
	pitch = pitch_deg
	_release_lock()


## Jump straight to the goal (after teleports, at the start).
func snap() -> void:
	if target and mode == "follow":
		focus = _target_pos() + Vector3(0, PIVOT_HEIGHT, 0)
	_place(0.0)


# --- input ---------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if (mode == "follow" and Game.is_playing()) or mode == "fly":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Game.capture_msec = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		var k := MOUSE_DEG_PER_PX * float(Settings.get_v("mouse_sens"))
		var sx := -1.0 if bool(Settings.get_v("invert_x")) else 1.0
		var sy := -1.0 if bool(Settings.get_v("invert_y")) else 1.0
		yaw -= rel.x * k * sx
		pitch = clampf(pitch - rel.y * k * sy, PITCH_MIN, PITCH_MAX)
		_look_idle = 0.0
	if event.is_action_pressed("lock_on") and mode == "follow" and Game.is_playing():
		if lock_target:
			_release_lock()
		else:
			_acquire_lock()


# --- lock-on -------------------------------------------------------------------------------------------------

func _acquire_lock() -> void:
	var best: Node3D = null
	var best_score := INF
	var fwd := -cam.global_transform.basis.z
	var from := _target_pos()
	for n in get_tree().get_nodes_in_group("lockable"):
		var t := n as Node3D
		if t == null or t == target or (t.has_method("is_alive") and not t.is_alive()):
			continue
		var p: Vector3 = t.call("lock_point") if t.has_method("lock_point") else t.global_position
		var d := p - from
		var dist := d.length()
		if dist > LOCK_RANGE or dist < 0.5:
			continue
		var facing := fwd.dot((p - cam.global_position).normalized())
		if facing < 0.35:
			continue
		var score := dist * (2.0 - facing)
		if score < best_score:
			best_score = score
			best = t
	if best:
		lock_target = best
		Game.lock_changed.emit(best)


func _release_lock() -> void:
	if lock_target != null:
		lock_target = null
		Game.lock_changed.emit(null)


func _lock_valid() -> bool:
	if lock_target == null or not is_instance_valid(lock_target) or not lock_target.is_inside_tree():
		return false
	if lock_target.has_method("is_alive") and not lock_target.is_alive():
		return false
	return _target_pos().distance_to(lock_target.global_position) < LOCK_KEEP


# --- per frame -----------------------------------------------------------------------------------------------

func _target_pos() -> Vector3:
	if target == null or not is_instance_valid(target):
		return focus - Vector3(0, PIVOT_HEIGHT, 0)
	if target.has_method("visual_position"):
		return target.call("visual_position")
	return target.global_position


func _process(delta: float) -> void:
	_t += delta
	var real_dt := delta / maxf(Engine.time_scale, 0.001) # look input ignores hit-stop and slow motion
	match mode:
		"follow":
			_process_follow(delta, real_dt)
		"orbit":
			yaw += orbit_speed * delta
			var y := deg_to_rad(yaw)
			focus = orbit_center
			global_position = orbit_center + Vector3(sin(y), 0, cos(y)) * orbit_radius + Vector3(0, orbit_height, 0)
			look_at(orbit_center, Vector3.UP)
			spring.spring_length = 0.0
			spring.rotation = Vector3.ZERO
			cam.position = Vector3.ZERO
		"fly":
			_process_fly(real_dt)
	trauma = maxf(0.0, trauma - delta * 1.7)
	_apply_shake()


func _process_follow(delta: float, real_dt: float) -> void:
	# Right stick.
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
	if look.length() > 0.0:
		var k := PAD_DEG_PER_S * float(Settings.get_v("pad_sens")) * real_dt
		var sx := -1.0 if bool(Settings.get_v("invert_x")) else 1.0
		var sy := -1.0 if bool(Settings.get_v("invert_y")) else 1.0
		yaw -= look.x * absf(look.x) * k * sx
		pitch = clampf(pitch - look.y * absf(look.y) * k * 0.8 * sy, PITCH_MIN, PITCH_MAX)
		_look_idle = 0.0
	else:
		_look_idle += real_dt
	if lock_target and not _lock_valid():
		_release_lock()
	var tp := _target_pos()
	var goal := tp + Vector3(0, PIVOT_HEIGHT, 0)
	if lock_target:
		# Frame both: look from behind the hero towards the target, a little from above.
		var lp: Vector3 = lock_target.call("lock_point") if lock_target.has_method("lock_point") else lock_target.global_position
		var to := lp - tp
		to.y = 0.0
		if to.length() > 0.3:
			var want_yaw := rad_to_deg(atan2(-to.x, -to.z))
			yaw = rad_to_deg(lerp_angle(deg_to_rad(yaw), deg_to_rad(want_yaw), 1.0 - exp(-real_dt * 8.0)))
			pitch = lerpf(pitch, clampf(-16.0 - (lp.y - tp.y) * 2.0, PITCH_MIN, -6.0), 1.0 - exp(-real_dt * 4.0))
		goal = goal.lerp((tp + lp) * 0.5 + Vector3(0, PIVOT_HEIGHT * 0.6, 0), 0.25)
	elif target and _look_idle > 1.2:
		# Auto-recentre behind a running hero, slowly.
		var spd: float = Vector2(target.velocity.x, target.velocity.z).length() if "velocity" in target else 0.0
		if spd > 3.0 and "facing" in target:
			var want := rad_to_deg(float(target.get("facing")))
			yaw = rad_to_deg(lerp_angle(deg_to_rad(yaw), deg_to_rad(want), 1.0 - exp(-real_dt * 0.8 * (spd / 6.0))))
	# Follow: tight in XZ, softer in Y (critically damped toward the goal height).
	var kxz := 1.0 - exp(-delta * 16.0)
	focus.x = lerpf(focus.x, goal.x, kxz)
	focus.z = lerpf(focus.z, goal.z, kxz)
	var ky := 1.0 - exp(-delta * 7.0)
	focus.y = lerpf(focus.y, goal.y, ky)
	if absf(focus.y - goal.y) > 3.0:
		focus.y = goal.y - signf(goal.y - focus.y) * 3.0
	_place(delta)


func _place(_delta: float) -> void:
	if mode != "follow":
		return
	global_position = focus
	rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	spring.rotation = Vector3.ZERO
	spring.spring_length = distance
	cam.fov = fov


func _process_fly(dt: float) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	var mv := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		mv -= b.z
	if Input.is_physical_key_pressed(KEY_S):
		mv += b.z
	if Input.is_physical_key_pressed(KEY_A):
		mv -= b.x
	if Input.is_physical_key_pressed(KEY_D):
		mv += b.x
	if Input.is_physical_key_pressed(KEY_E):
		mv += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		mv -= Vector3.UP
	var spd := 60.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 15.0
	_fly_pos += mv.normalized() * spd * dt if mv.length() > 0.0 else Vector3.ZERO
	global_position = _fly_pos
	rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	spring.spring_length = 0.0
	spring.rotation = Vector3.ZERO
	cam.position = Vector3.ZERO
	cam.fov = fov
	focus = _fly_pos


func _apply_shake() -> void:
	var s := trauma * trauma
	if s <= 0.0001:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		cam.rotation.z = 0.0
		return
	cam.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * s * 0.35
	cam.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * s * 0.35
	cam.rotation.z = _noise.get_noise_2d(_t * 30.0, 50.0) * s * 0.05
