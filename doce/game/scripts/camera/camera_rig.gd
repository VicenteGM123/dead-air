class_name CameraRig
extends Node3D
## Third-person camera (CORE): a pivot that follows the hero at shoulder height and an arm out to the Camera3D.
##  - collision: a sphere (CAM_RADIUS) cast along the arm on the world layer every frame: the camera never ends
##    inside rocks, trunks or cave walls; it comes in at once and eases back out; in tight places (walls close on
##    both sides) the arm is shorter;
##  - look: mouse while captured (a click on the game captures it; Esc releases it), right stick with a curve;
##    Settings mouse_sens / pad_sens / invert_x / invert_y; look input ignores hit-stop and slow motion;
##  - follow: tight in XZ with a little lead in the direction of travel, softer in Y; gentle recentring behind a
##    moving hero after RECENTER_AFTER s without look input; pulled back a little when foes are near;
##  - lock-on (Tab / middle click / R3): the lockable nearest the screen centre within LOCK_RANGE (in sight);
##    frames hero and target; a flick of the right stick or the mouse switches to the next target on that side;
##    released on a press, on death, beyond LOCK_KEEP or out of sight; Game.lock_changed(target);
##  - feel: trauma shake (Game.shake -> add_trauma; Settings "shake"), nudge(dir, amount) on blows, FOV kicks
##    when sprinting (set_sprint) and zipping along the chain (set_zip);
##  - modes: "follow" (the game), "orbit" (title), "fly" (free camera: WASD + mouse, E / Q, Shift).
## Angles: yaw 0 = camera behind a hero facing -Z (north), increasing anticlockwise seen from above; pitch < 0
## looks down. Moved in _process (after the hero and its rig); physics interpolation off.

const PIVOT_HEIGHT := 1.55
const PITCH_MIN := -68.0
const PITCH_MAX := 38.0
const MOUSE_DEG_PER_PX := 0.14
const PAD_DEG_PER_S := 185.0
const LOCK_RANGE := 25.0
const LOCK_KEEP := 30.0
const CAM_RADIUS := 0.3
const RECENTER_AFTER := 1.4
const FOV_SPRINT := 5.0
const FOV_ZIP := 9.0
## The arm is this much shorter while zipping (with the wider view the hero would shrink to a dot).
const ZIP_ARM := 0.82

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
var _arm := 5.5
var _lead := Vector3.ZERO
var _nudge := Vector3.ZERO
var _nudge_v := Vector3.ZERO
var _fov_now := 60.0
var _zip := false
var _zip_k := 0.0
var _sprint := false
var _combat_k := 0.0
var _combat_t := 0.0
var _foes_near := 0
var _tight := 0.0
## A framed target (lock-on or interest) while the hero is in a narrow passage: see _process_follow.
var _framed_narrow := false
var _narrow_k := 0.0
var _narrow_t := 0.0
## Over-the-shoulder offset (m, to the right) in a fight and when locked on, so the foe in front of the hero is not
## hidden behind him; eased in and out (exploration stays centred, Wind Waker style).
var _side := 0.0
const SIDE_COMBAT := 0.7
const SIDE_LOCK := 0.8
const PITCH_COMBAT := -24.0
## Locked on, the camera sits this many degrees round behind the hero's RIGHT shoulder (the same side as the
## shoulder offset, so the two add up instead of cancelling): the hero stands left of centre and the target shows
## clearly to his right, past the sword arm, never hidden behind his back (tools_scratch/frame_calc.py: ~100 px
## apart at 2.5 m, 1280 x 720).
const LOCK_YAW_OFFSET := 18.0
## Not locked on, the hero's camera_interest() (the foe the sword is busy with, a foe being wrestled, the boulder
## on the chain, a foe being yanked) is kept in view the same way, from further round when wrestling (a side view
## of the struggle).
const INTEREST_YAW := 32.0
## How fast (1/s) the soft framing turns the view to it, and its top speed (degrees/s: a foe behind the hero is
## brought round in a smooth 1.5 s pan, never a whip-pan; a 30-degree adjustment still takes only ~0.3 s).
const INTEREST_RATE := 6.0
const INTEREST_TURN_MAX := 120.0
## The lock-on framing's top turning speed (degrees/s).
const LOCK_TURN_MAX := 220.0
## The soft framing does not turn the view while the hero rolls, nor this long (s) after.
const DODGE_HOLD := 0.4
var _dodge_hold := 0.0
const INTEREST_YAW_GRAPPLE := 48.0
## The wrestle's view: closer and lower.
const DIST_GRAPPLE := 4.8
const PITCH_GRAPPLE := -14.0
## The arm never settles shorter than this when another way round is clear: blocked closer (a pillar or a trunk
## between the hero and the view) the view swings round the obstacle by the nearest clear ORBIT_STEPS angle.
const MIN_ARM := 1.7
const ORBIT_STEPS := [20.0, -20.0, 40.0, -40.0, 65.0, -65.0, 95.0, -95.0]
## Which shoulder the framing sits behind: +1 right (default), -1 left. Changed only while framing a target whose
## line of sight is blocked on the current side and clear on the other (a pillar between the view and the lion),
## and kept afterwards (the shoulder offset of the free combat view uses it too), so the view never flips back and
## forth.
var _frame_sign := 1.0
var _frame_check := 0.0
var _orbit := 0.0
var _orbit_scan := 0.0
var _blocked := 0.0
var _raise := false
var _lock_lost := 0.0
var _flick_x := 0.0
## Sideways mouse motion (px) of the current frame while locked on (summed over its events).
var _flick_frame := 0.0
## Mouse flick to switch the lock target: px of quick sideways motion, the speed that counts (px/s over a frame),
## the leak (1/s). A flick of 80-90 px within ~0.1 s switches; a slow drift of the hand (a few px a frame) never
## counts, however long it goes on.
const FLICK_PX := 80.0
const FLICK_SPEED := 500.0
const FLICK_LEAK := 6.0
var _stick_armed := true
var _sphere := SphereShape3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _thin := SphereShape3D.new()
var _thin_q := PhysicsShapeQueryParameters3D.new()
var _ray_q := PhysicsRayQueryParameters3D.new()
var _origin_q := PhysicsShapeQueryParameters3D.new()
## The arm's start is clear of the world (checked once a frame): see _clear_len.
var _origin_free := true
## The fallback cast's radius when the arm is cut beside the hero: just covers the near plane.
const THIN_RADIUS := 0.13
## Whiskers: arms this many degrees either side, and how fast (deg/s) the view drifts from a cut side.
const WHISKER := 16.0
const WHISKER_RATE := 70.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 10 # after the hero and the world have moved this frame
	# The SpringArm3D is kept as the camera's holder (the documented API); the collision is our own sphere cast.
	spring = SpringArm3D.new()
	spring.name = "SpringArm"
	spring.collision_mask = 0
	spring.spring_length = 0.0
	add_child(spring)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov
	cam.near = 0.08
	cam.far = 2500.0
	spring.add_child(cam)
	cam.current = true
	# ~15 Hz: a jolt that reads as a shake, not per-frame jitter
	_noise.frequency = 0.6
	_sphere.radius = CAM_RADIUS
	_shape_q.shape = _sphere
	_shape_q.collision_mask = 1
	_thin.radius = THIN_RADIUS
	_thin_q.shape = _thin
	_thin_q.collision_mask = 1
	_ray_q.collision_mask = 1
	_origin_q.shape = _sphere
	_origin_q.collision_mask = 1
	_fov_now = fov
	_dbg = Game.arg_on("camdebug")
	if Game.arg("cam", "") == "fly":
		set_fly(Game.arg_vec3("pos", Vector3(0, 60, 200)), Game.arg_f("yaw", 0.0), Game.arg_f("pitch", -20.0))
	else:
		yaw = Game.arg_f("yaw", yaw)
		pitch = Game.arg_f("pitch", pitch)


# --- public ------------------------------------------------------------------------------------------------

func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)


## A small push of the view along `dir` (world) that springs back: the weight of a blow.
func nudge(dir: Vector3, amount: float) -> void:
	if not bool(Settings.get_v("shake")):
		return
	_nudge_v += dir.normalized() * amount * 9.0


## Wider view while zipping along the chain.
func set_zip(on: bool) -> void:
	_zip = on


## Slightly wider view while sprinting.
func set_sprint(on: bool) -> void:
	_sprint = on


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
		_lead = Vector3.ZERO
		_arm = distance
	_place(0.0, true)


## Points the view at a world point (tests and the arena bot aim the chain spear with it).
func aim_at(p: Vector3) -> void:
	var d := p - focus
	if d.length() < 0.01:
		return
	yaw = rad_to_deg(atan2(-d.x, -d.z))
	pitch = clampf(rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())), PITCH_MIN, PITCH_MAX)
	_look_idle = 0.0


## Locks onto `t` (tests); null releases.
func lock_on(t: Node3D) -> void:
	if t == null:
		_release_lock()
		return
	lock_target = t
	_lock_lost = 0.0
	Game.lock_changed.emit(t)


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
		if lock_target and mode == "follow":
			# locked: a sideways flick of the mouse switches target (counted once a frame: _flick_tick)
			flick_motion(rel.x)
		else:
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


## Sideways mouse motion while locked on (px; tests call it directly).
func flick_motion(dx: float) -> void:
	_flick_frame += dx


## Once a frame while locked on: the frame's sideways motion counts only when it is quick (faster than FLICK_SPEED
## px/s), the sum leaks away (FLICK_LEAK per second), and past FLICK_PX the lock moves to the next target that side.
func _flick_tick(real_dt: float) -> void:
	if absf(_flick_frame) / maxf(real_dt, 1e-3) > FLICK_SPEED:
		_flick_x += _flick_frame
	_flick_frame = 0.0
	if absf(_flick_x) > FLICK_PX:
		_switch_lock(signf(_flick_x))
		_flick_x = 0.0
	_flick_x *= exp(-real_dt * FLICK_LEAK)


# --- lock-on -------------------------------------------------------------------------------------------------

func _lock_point(t: Node3D) -> Vector3:
	return t.call("lock_point") if t.has_method("lock_point") else t.global_position


## The lockable nearest the screen centre (side == 0) or the nearest on that side of the current target
## (side -1 left, +1 right), within LOCK_RANGE of the hero, in front of the camera and in sight.
func _pick_lock(side: float = 0.0) -> Node3D:
	var from := _target_pos() + Vector3(0, 1.2, 0)
	var vp := get_viewport().get_visible_rect().size
	var centre := vp * 0.5
	var cur_x := centre.x
	if side != 0.0 and lock_target and is_instance_valid(lock_target):
		cur_x = cam.unproject_position(_lock_point(lock_target)).x
	var best: Node3D = null
	var best_score := INF
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("lockable"):
		var t := n as Node3D
		if t == null or t == target or t == lock_target or not Combat.is_alive(t):
			continue
		var p := _lock_point(t)
		var dist := from.distance_to(p)
		if dist > LOCK_RANGE or dist < 0.5:
			continue
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var score: float
		if side == 0.0:
			var nd := (sp - centre) / vp.y
			if absf(nd.x) > 0.9 or absf(nd.y) > 0.7:
				continue
			score = nd.length() + dist / LOCK_RANGE * 0.35
		else:
			var dx := (sp.x - cur_x) * side
			if dx < 12.0:
				continue
			score = dx / vp.y + absf(sp.y - centre.y) / vp.y * 0.5 + dist / LOCK_RANGE * 0.2
		if score >= best_score:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, p, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(p) > 0.8:
			continue
		best_score = score
		best = t
	return best


func _acquire_lock() -> void:
	var best := _pick_lock(0.0)
	if best:
		lock_target = best
		_lock_lost = 0.0
		Game.lock_changed.emit(best)


func _switch_lock(side: float) -> void:
	var t := _pick_lock(side)
	if t:
		lock_target = t
		_lock_lost = 0.0
		Game.lock_changed.emit(t)


func _release_lock() -> void:
	if lock_target != null:
		lock_target = null
		Game.lock_changed.emit(null)


func _lock_valid(dt: float) -> bool:
	if lock_target == null or not Combat.is_alive(lock_target):
		return false
	var from := _target_pos() + Vector3(0, 1.2, 0)
	var p := _lock_point(lock_target)
	if from.distance_to(p) > LOCK_KEEP:
		return false
	# out of sight for a while
	_ray_q.from = from
	_ray_q.to = p
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_q)
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(p) > 0.8:
		_lock_lost += dt
	else:
		_lock_lost = 0.0
	return _lock_lost < 2.0


# --- per frame -----------------------------------------------------------------------------------------------

func _target_pos() -> Vector3:
	if target == null or not is_instance_valid(target):
		return focus - Vector3(0, PIVOT_HEIGHT, 0)
	if target.has_method("visual_position"):
		return target.call("visual_position")
	return target.global_position


func _process(delta: float) -> void:
	var real_dt := minf(Game.real_delta(delta), 0.1) # look input ignores hit-stop and slow motion
	# the shake's clock runs in real time: a blow's shake plays through its hit-stop (the freeze frame shudders)
	_t += real_dt
	match mode:
		"follow":
			_process_follow(delta, real_dt)
		"orbit":
			yaw += orbit_speed * delta
			var y := deg_to_rad(yaw)
			focus = orbit_center
			global_position = orbit_center + Vector3(sin(y), 0, cos(y)) * orbit_radius + Vector3(0, orbit_height, 0)
			look_at(orbit_center, Vector3.UP)
			spring.position = Vector3.ZERO
			cam.position = Vector3.ZERO
		"fly":
			_process_fly(real_dt)
	trauma = maxf(0.0, trauma - real_dt * 1.7)
	_apply_shake()
	_cut_props(real_dt)


func _process_follow(delta: float, real_dt: float) -> void:
	# right stick (a flick switches the lock target)
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
	if lock_target:
		if absf(look.x) < 0.3:
			_stick_armed = true
		elif absf(look.x) > 0.75 and _stick_armed:
			_stick_armed = false
			_switch_lock(signf(look.x))
		_flick_tick(real_dt)
		_look_idle += real_dt
	elif look.length() > 0.0:
		var k := PAD_DEG_PER_S * float(Settings.get_v("pad_sens")) * real_dt
		var sx := -1.0 if bool(Settings.get_v("invert_x")) else 1.0
		var sy := -1.0 if bool(Settings.get_v("invert_y")) else 1.0
		# a response curve: fine aim near the centre, full speed at the edge
		yaw -= look.x * absf(look.x) * k * sx
		pitch = clampf(pitch - look.y * absf(look.y) * k * 0.75 * sy, PITCH_MIN, PITCH_MAX)
		_look_idle = 0.0
	else:
		_look_idle += real_dt
	if lock_target and not _lock_valid(real_dt):
		_release_lock()
	var tp := _target_pos()
	var vel := Vector3.ZERO
	if target and "velocity" in target:
		vel = target.get("velocity")
	# lead: a little ahead of where the hero is going
	var hv := Vector3(vel.x, 0.0, vel.z)
	_lead = _lead.lerp(hv.limit_length(9.0) * 0.07, 1.0 - exp(-real_dt * 2.5))
	var goal := tp + Vector3(0, PIVOT_HEIGHT, 0) + _lead
	var want_dist := distance
	# foes near: pull back a little so the fight reads
	_combat_t -= real_dt
	if _combat_t <= 0.0:
		_combat_t = 0.3
		_foes_near = _count_foes(tp, 11.0)
	_combat_k = move_toward(_combat_k, 1.0 if _foes_near > 0 else 0.0, real_dt * (1.6 if _foes_near > 0 else 0.6))
	want_dist += 0.9 * _combat_k
	var interest: Node3D = null
	if lock_target == null and target is Hero:
		interest = (target as Hero).camera_interest()
	_dodge_hold = maxf(0.0, _dodge_hold - real_dt)
	if target is Hero and (target as Hero).is_dodging():
		_dodge_hold = DODGE_HOLD
	var grappling := target is Hero and (target as Hero).state == Hero.St.GRAPPLE
	if not grappling:
		_grap_crane = false
		_grap_scan = 0.0
	# framing a target (lock-on or interest): from behind the shoulder on the side it can be seen from
	if lock_target:
		_update_frame_sign(real_dt, tp, _lock_point(lock_target), LOCK_YAW_OFFSET, maxf(want_dist, 5.2))
	elif interest != null and grappling:
		# the wrestle is framed close and from the side: the angle round them with the most room (pillars round a
		# stunned beast would otherwise crowd the lens), or from above them (the crane)
		_pick_grapple_offset(real_dt, tp, interest.global_position + Vector3(0, 1.0, 0))
		if absf(_grap_off) > 0.1:
			_frame_sign = signf(_grap_off)
	elif interest != null:
		_update_frame_sign(real_dt, tp, interest.global_position + Vector3(0, 1.0, 0), INTEREST_YAW, 6.2)
	# the chain spear thrown, flying, zipping, climbing or hanging (not locked on, nothing else framed): the view
	# turns CHAIN_YAW round to the side of the chain arm (the left: the fist the chain runs from) and over that
	# shoulder, so the chain crosses the screen on a diagonal instead of running away down the view axis behind his
	# back; the other side when the left one is blocked
	var hero_t: Hero = target as Hero if target is Hero else null
	var chain_p := Vector3.INF
	var chaining := false
	if hero_t != null and lock_target == null and interest == null:
		chain_p = hero_t.chain_focus()
		chaining = chain_p != Vector3.INF or hero_t.state == Hero.St.HANG
		if chain_p != Vector3.INF:
			_update_chain_sign(real_dt, tp, chain_p)
	var guard_up := hero_t != null and hero_t.guarding and lock_target == null
	# in a narrow passage (walls close on both sides: mouth B's crack, the cave's tunnels) the soft framings sit
	# straight behind the hero, along the passage: turned round or over a shoulder the arm would only be cut short
	# by the walls and squeezed into his helmet (integration: hauling the boulder into the crack)
	# (measured across the line to what is framed, or across the view when nothing is: a passage seen at an angle
	# from its mouth still counts)
	var narrow := 0.0
	if not grappling:
		var across := Vector3.ZERO
		if lock_target != null:
			across = _lock_point(lock_target) - tp
		elif interest != null:
			across = interest.global_position - tp
		elif hero_t != null and hero_t.chain_focus() != Vector3.INF:
			across = hero_t.chain_focus() - tp
		_narrow_t -= real_dt
		if _narrow_t <= 0.0:
			_narrow_t = 0.1
			_narrow_k = _tight_across(across) if across.length() > 0.5 else _tight
		narrow = smoothstep(0.05, 0.25, _narrow_k)
	# (and the obstacle steering leaves the view to that framing: in a passage it would swing the arm round to the
	# open side, which is the far side of what is framed)
	_framed_narrow = narrow > 0.5 and (lock_target != null or interest != null)
	var side_goal := (SIDE_LOCK if (lock_target or interest) else SIDE_COMBAT * _combat_k) * _frame_sign
	if chaining:
		side_goal = CHAIN_SIDE * _chain_sign
	if not lock_target:
		side_goal *= 1.0 - narrow
	if guard_up and not grappling:
		# the raised shield (left arm) shows past his body: no offset to the right while guarding
		side_goal = minf(side_goal, 0.0) if not chaining else side_goal
	if grappling:
		side_goal = 0.0 # the wrestle is a centred two-shot
	_side = lerpf(_side, side_goal, 1.0 - exp(-real_dt * (CHAIN_RATE if chaining else 3.0)))
	if not lock_target and _combat_k > 0.0 and _look_idle > 1.0:
		# in a fight, a slightly higher view reads positions better (only while the player leaves the camera)
		pitch = lerpf(pitch, minf(pitch, PITCH_COMBAT), 1.0 - exp(-real_dt * 1.2 * _combat_k))
	if lock_target:
		var lp := _lock_point(lock_target)
		var to := lp - tp
		var sep := Vector2(to.x, to.z).length()
		to.y = 0.0
		if to.length() > 0.3:
			var want_yaw := rad_to_deg(atan2(-to.x, -to.z)) + LOCK_YAW_OFFSET * _frame_sign
			_turn_yaw(want_yaw, 6.0, LOCK_TURN_MAX, real_dt)
			var want_pitch := clampf(-15.0 - (lp.y - tp.y - 1.0) * 2.5 - sep * 0.15, -34.0, -4.0)
			pitch = lerpf(pitch, want_pitch, 1.0 - exp(-real_dt * 3.0))
		goal = goal.lerp((tp + lp) * 0.5 + Vector3(0, PIVOT_HEIGHT * 0.65, 0), clampf(0.15 + sep * 0.012, 0.15, 0.35))
		want_dist = maxf(want_dist, clampf(4.6 + sep * 0.3, 5.2, 8.5))
	elif interest != null:
		# a soft lock on what the hero fights, wrestles or hauls, while the player leaves the camera alone
		var ip := interest.global_position + Vector3(0, 1.0, 0)
		var to_i := ip - tp
		to_i.y = 0.0
		# (the first blows of a fight turn the view at once: a blow aimed or landed in the last 0.6 s skips the wait
		# for the look input to rest, unless the player is turning the view right now)
		var engaged := target is Hero and (target as Hero)._clock < (target as Hero).melee.engaged_until
		var idle_need := 0.05 if engaged else 0.4
		if to_i.length() > 0.5 and _look_idle > idle_need and _dodge_hold <= 0.0:
			# (never while he rolls, nor just after: a roll away from the foe must not swing the view round)
			var off := absf(_grap_off) if grappling else (GUARD_INTEREST_YAW if guard_up else INTEREST_YAW) * (1.0 - narrow)
			var want_yaw := rad_to_deg(atan2(-to_i.x, -to_i.z)) + off * _frame_sign
			_turn_yaw(want_yaw, 4.0 if grappling else INTEREST_RATE, INTEREST_TURN_MAX * (3.0 if _framed_narrow else 1.0), real_dt)
			var want_pitch := -22.0
			if grappling:
				want_pitch = PITCH_CRANE if _grap_crane else PITCH_GRAPPLE
			pitch = lerpf(pitch, want_pitch, 1.0 - exp(-real_dt * 2.0))
		if grappling:
			goal = goal.lerp((tp + Vector3(0, PIVOT_HEIGHT, 0) + ip) * 0.5, 0.85)
		else:
			goal = goal.lerp((tp + ip) * 0.5 + Vector3(0, PIVOT_HEIGHT * 0.5, 0), clampf(0.1 + to_i.length() * 0.015, 0.1, 0.3))
		# the wrestle is framed close, from the side and low (a struggle of weights), or from above the pillars when
		# no side has room (the crane); the rest from a little back
		if grappling:
			want_dist = DIST_CRANE if _grap_crane else DIST_GRAPPLE
		else:
			want_dist = maxf(want_dist, 6.2)
	elif chain_p != Vector3.INF and hero_t.state != Hero.St.HANG:
		# the chain on a diagonal (see above): the line to what it flies to or pulls him to, turned CHAIN_YAW round
		var to_c := chain_p - tp
		to_c.y = 0.0
		if to_c.length() > 1.0 and _look_idle > 0.2:
			var want_c := rad_to_deg(atan2(-to_c.x, -to_c.z)) + CHAIN_YAW * _chain_sign * (1.0 - narrow)
			_turn_yaw(want_c, CHAIN_RATE, INTEREST_TURN_MAX, real_dt)
	elif target and _look_idle > RECENTER_AFTER:
		# recentre behind a moving hero, slowly (not after a dodge: a roll sideways must not swing the view; and
		# barely in a fight, where the player places the view)
		var spd := hv.length()
		var dodging: bool = target.has_method("is_dodging") and bool(target.call("is_dodging"))
		if spd > 2.5 and "facing" in target and not dodging:
			var want := rad_to_deg(float(target.get("facing")))
			var rate := 0.7 * clampf(spd / 6.0, 0.4, 1.4) * (1.0 - 0.75 * _combat_k)
			yaw = rad_to_deg(lerp_angle(deg_to_rad(yaw), deg_to_rad(want), 1.0 - exp(-real_dt * rate)))
	# follow: tight in XZ, softer in Y
	var kxz := 1.0 - exp(-delta * 14.0)
	focus.x = lerpf(focus.x, goal.x, kxz)
	focus.z = lerpf(focus.z, goal.z, kxz)
	var ky := 1.0 - exp(-delta * 7.0)
	focus.y = lerpf(focus.y, goal.y, ky)
	if absf(focus.y - goal.y) > 3.0:
		focus.y = goal.y - signf(goal.y - focus.y) * 3.0
	# tight places: shorter arm
	_tight = lerpf(_tight, _measure_tight(), 1.0 - exp(-real_dt * 3.0))
	want_dist *= lerpf(1.0, 0.68, _tight)
	_zip_k = move_toward(_zip_k, 1.0 if _zip else 0.0, real_dt * 3.0)
	want_dist *= lerpf(1.0, ZIP_ARM, _zip_k)
	distance_now = want_dist
	_place(real_dt, false)
	_fade_occluders(real_dt)


## Foes are not on the camera's collision layer (the view never swings round a wolf), so one that comes between the
## lens and the hero, or right up to the lens, would hide him: its body fades out (a screen-door dither, Rig.set_fade)
## to FADE_TO, eased at FADE_RATE per second, and back when it is out of the way. Never the beast he is wrestling.
const FADE_TO := 0.55
const FADE_RATE := 8.0
const FADE_LINE := 0.4
const FADE_LENS := 1.5
var _faded: Array[Node3D] = []
var _fade_pts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])


func _fade_occluders(real_dt: float) -> void:
	if target == null or not is_inside_tree():
		return
	var lens := cam.global_position
	var head := _target_pos() + Vector3(0, 1.45, 0)
	var held: Node3D = null
	if target is Hero and (target as Hero).state == Hero.St.GRAPPLE:
		held = (target as Hero).grapple_target
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not ("rig" in e):
			continue
		var r = e.get("rig")
		if not (r is Node3D) or not (r as Node3D).has_method("set_fade"):
			continue
		var want := 0.0
		if e != held and Combat.is_alive(e) and e.global_position.distance_to(lens) < 12.0:
			for vol in Combat.hurt_volumes(e):
				var a: Vector3 = vol[0]
				var b: Vector3 = vol[1]
				var rr: float = vol[2]
				var d_line := sqrt(Combat.seg_seg_dist2(lens, head, a, b, _fade_pts)) - rr
				var d_lens := sqrt(Combat.seg_seg_dist2(lens, lens, a, b, _fade_pts)) - rr
				if d_line < FADE_LINE or d_lens < FADE_LENS:
					want = FADE_TO
					break
		var cur: float = float((r as Node3D).call("get_fade"))
		if want > 0.0 or cur > 0.0:
			(r as Node3D).call("set_fade", move_toward(cur, want, real_dt * FADE_RATE))
			if want > 0.0 and not _faded.has(e):
				_faded.append(e)
	# bodies that left the group (dead, freed) keep no fade
	for i in range(_faded.size() - 1, -1, -1):
		var f := _faded[i]
		if not is_instance_valid(f):
			_faded.remove_at(i)
		elif not f.is_in_group("enemy") or not Combat.is_alive(f):
			var fr = f.get("rig")
			if fr is Node3D and (fr as Node3D).has_method("set_fade"):
				(fr as Node3D).call("set_fade", 0.0)
			_faded.remove_at(i)


## World props in group "camera_cut" (each a GeometryInstance3D with a lowpoly material: the arena's pillars, the
## lion cave's) are cut away where they come between the lens and what the view frames (lowpoly.gdshader `cut_*`, a
## screen door): within CUT_R m of the line from the lens to the hero's chest (in a wrestle: to the middle of the two
## heads, CUT_R_WRESTLE) and at least 0.7 m nearer the lens than that point, and within CUT_LENS m of the lens, at
## CUT_MAX strength (eased at CUT_RATE per second; off on the title's orbit and in the free camera). Props further
## than CUT_RANGE m from the lens are left alone.
const CUT_R := 0.8
const CUT_R_WRESTLE := 1.2
const CUT_LENS := 2.6
const CUT_MAX := 0.8
const CUT_RATE := 5.0
const CUT_RANGE := 14.0
var _cut_k := 0.0
var _cut_on: Array[GeometryInstance3D] = []


func _cut_props(real_dt: float) -> void:
	if not is_inside_tree():
		return
	var want := 1.0 if (mode == "follow" and target != null and is_instance_valid(target)) else 0.0
	_cut_k = move_toward(_cut_k, want, real_dt * CUT_RATE)
	var nodes := get_tree().get_nodes_in_group("camera_cut")
	if nodes.is_empty() and _cut_on.is_empty():
		return
	var lens := cam.global_position
	var subject := _target_pos() + Vector3(0, 1.2, 0)
	var r := CUT_R
	if target is Hero and (target as Hero).state == Hero.St.GRAPPLE and Combat.is_alive((target as Hero).grapple_target):
		subject = (subject + (target as Hero).grapple_target.global_position + Vector3(0, 1.1, 0)) * 0.5
		r = CUT_R_WRESTLE
	var live: Array[GeometryInstance3D] = []
	for n in nodes:
		var gi := n as GeometryInstance3D
		if gi == null or not gi.is_inside_tree():
			continue
		var box := gi.global_transform * gi.get_aabb()
		var near := box.grow(CUT_RANGE).has_point(lens)
		if not near or _cut_k <= 0.0:
			continue
		Materials.set_param(gi, &"cut_k", CUT_MAX * _cut_k)
		Materials.set_param(gi, &"cut_a", lens)
		Materials.set_param(gi, &"cut_b", subject)
		Materials.set_param(gi, &"cut_r", r)
		Materials.set_param(gi, &"cut_lens", CUT_LENS)
		live.append(gi)
	# props that left the range (or the group): solid again
	for gi in _cut_on:
		if is_instance_valid(gi) and not live.has(gi):
			Materials.set_param(gi, &"cut_k", 0.0)
	_cut_on = live


## Turns the view's yaw towards `want_deg` (exponential ease at `rate` per second) no faster than `max_speed`
## degrees per second.
func _turn_yaw(want_deg: float, rate: float, max_speed: float, real_dt: float) -> void:
	var d := wrapf(want_deg - yaw, -180.0, 180.0)
	var step := d * (1.0 - exp(-real_dt * rate))
	var cap := max_speed * real_dt
	yaw += clampf(step, -cap, cap)


## Desired arm length this frame (before collision).
var distance_now := 5.5

## The chain's view (see _process_follow): this many degrees round and this far over the chain arm's shoulder,
## eased in at CHAIN_RATE per second.
const CHAIN_YAW := 25.0
const CHAIN_SIDE := 1.2
const CHAIN_RATE := 6.0
## While guarding (not locked on) the soft framing sits less far round: the shield on his left arm shows.
const GUARD_INTEREST_YAW := 14.0
## -1: the chain's view sits behind the left shoulder (the chain arm), +1 the right one (the left side blocked).
var _chain_sign := -1.0
var _chain_check := 0.0


## Every 0.25 s while the chain's view is on: the left side (the chain arm) unless it is blocked and the right is
## clear; back to the left as soon as it is clear again.
func _update_chain_sign(real_dt: float, tp: Vector3, cp: Vector3) -> void:
	_chain_check -= real_dt
	if _chain_check > 0.0:
		return
	_chain_check = 0.25
	if _frame_clear(tp, cp, CHAIN_YAW, maxf(distance_now, 4.0), -1.0, 0.55):
		_chain_sign = -1.0
	elif _frame_clear(tp, cp, CHAIN_YAW, maxf(distance_now, 4.0), 1.0, 0.55):
		_chain_sign = 1.0


## While framing a target (lock-on or interest) at `fp`: every 0.25 s, is it in sight from where the view sits now
## (behind the current shoulder)? If not, and it would be from the other shoulder, change sides.
func _update_frame_sign(real_dt: float, tp: Vector3, fp: Vector3, off: float, dist: float, need: float = 0.6) -> void:
	_frame_check -= real_dt
	if _frame_check > 0.0:
		return
	_frame_check = 0.25
	if _frame_clear(tp, fp, off, dist, _frame_sign, need):
		return
	if _frame_clear(tp, fp, off, dist, -_frame_sign, need):
		_frame_sign = -_frame_sign


## Whether the framing view on shoulder side `sgn` would work: the arm from the hero's head out to it mostly clear
## (not cut under 60 % by a pillar or a wall beside him) and `fp` in sight from there (world layer).
func _frame_clear(tp: Vector3, fp: Vector3, off: float, dist: float, sgn: float, need: float = 0.6) -> bool:
	var to := fp - tp
	to.y = 0.0
	if to.length() < 0.3 or not is_inside_tree():
		return true
	var yc := deg_to_rad(rad_to_deg(atan2(-to.x, -to.z)) + off * sgn)
	var bb := Basis.from_euler(Vector3(deg_to_rad(pitch), yc, 0.0))
	var cp := tp + Vector3(0, PIVOT_HEIGHT, 0) + bb * Vector3(SIDE_LOCK * sgn, 0.0, dist)
	_exclude_target()
	var space := get_world_3d().direct_space_state
	var head := tp + Vector3(0, PIVOT_HEIGHT - 0.15, 0)
	# the arm as the camera sees it (its sphere, not a thin ray): a pillar beside the line crowds the view too
	if _arm_cast(head, cp) < need:
		return false
	_ray_q.from = cp
	_ray_q.to = fp
	var hit := space.intersect_ray(_ray_q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(fp) < 0.8


## The wrestle's view: every 0.4 s, of the angles round the struggle (GRAPPLE_OFFSETS, degrees from straight
## behind the hero), the one whose arm is clearest, with room round the lens and the beast in sight, near 48.
const GRAPPLE_OFFSETS := [48.0, -48.0, 32.0, -32.0, 66.0, -66.0, 85.0, -85.0, 16.0, -16.0, 110.0, -110.0]
## No side view scores this well (pillars round a beast stunned against one: the lens would be crowded or the hold
## hidden): a crane shot from over the pillars instead (pitch, arm, angles round).
const GRAPPLE_MIN_SCORE := 1.5
const PITCH_CRANE := -40.0
const DIST_CRANE := 5.5
const CRANE_OFFSETS := [60.0, -60.0, 35.0, -35.0, 85.0, -85.0, 0.0, 120.0, -120.0]
var _grap_off := 48.0
var _grap_crane := false
var _grap_scan := 0.0
var _room := SphereShape3D.new()
var _room_q := PhysicsShapeQueryParameters3D.new()


func _pick_grapple_offset(real_dt: float, tp: Vector3, fp: Vector3) -> void:
	_grap_scan -= real_dt
	if _grap_scan > 0.0:
		return
	_grap_scan = 0.4
	var best := -INF
	var best_off := _grap_off
	for o in GRAPPLE_OFFSETS:
		var off: float = o
		var sc := _frame_score(tp, fp, off, DIST_GRAPPLE, PITCH_GRAPPLE)
		if is_equal_approx(off, _grap_off) and not _grap_crane:
			sc += 0.2 # keep the current view unless another is clearly better
		if sc > best:
			best = sc
			best_off = off
	if best >= GRAPPLE_MIN_SCORE - (0.0 if _grap_crane else 0.15):
		_grap_off = best_off
		_grap_crane = false
		return
	# crowded on every side: look down on the struggle from over the pillars
	var cbest := -INF
	var coff := _grap_off
	for o in CRANE_OFFSETS:
		var off2: float = o
		var sc2 := _frame_score(tp, fp, off2, DIST_CRANE, PITCH_CRANE)
		if _grap_crane and is_equal_approx(off2, _grap_off):
			sc2 += 0.2
		if sc2 > cbest:
			cbest = sc2
			coff = off2
	if cbest > best:
		_grap_off = coff
		_grap_crane = true
	else:
		_grap_off = best_off
		_grap_crane = false


func _frame_score(tp: Vector3, fp: Vector3, off: float, dist: float, pitch_deg: float) -> float:
	var to := fp - tp
	to.y = 0.0
	if to.length() < 0.3 or not is_inside_tree():
		return 0.0
	_exclude_target()
	var yc := deg_to_rad(rad_to_deg(atan2(-to.x, -to.z)) + off)
	var bb := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), yc, 0.0))
	var head := tp + Vector3(0, PIVOT_HEIGHT - 0.15, 0)
	# the two-shot: the camera looks at the middle of the struggle from `dist` away
	var mid := (tp + Vector3(0, PIVOT_HEIGHT, 0) + fp) * 0.5
	var cp := mid + bb * Vector3(0.0, 0.0, dist)
	var clear := _arm_cast(head, cp)
	var cam_p := head + (cp - head) * clear
	var sc := clear * 2.0
	var space := get_world_3d().direct_space_state
	# room round the lens: a pillar right beside the camera fills half the frame
	_room.radius = 1.1
	_room_q.shape = _room
	_room_q.collision_mask = 1
	_room_q.exclude = _ex
	_room_q.transform = Transform3D(Basis.IDENTITY, cam_p)
	if not space.intersect_shape(_room_q, 1).is_empty():
		sc -= 0.9
	# both of them in sight from there: the hero's head and the beast's
	for q in [head, fp]:
		_ray_q.from = cam_p
		_ray_q.to = q
		var hit := space.intersect_ray(_ray_q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(q) > 0.6:
			sc -= 1.2
	# the hold itself (the beast's head locked in his arms, in front of his chest) not hidden behind his own back
	if target is Hero:
		var h := target as Hero
		var hold := tp + h.forward() * 0.45 + Vector3(0, 1.17, 0)
		var d2 := Combat.seg_seg_dist2(cam_p, hold, tp + Vector3(0, 0.95, 0), tp + Vector3(0, 1.6, 0), _hold_pts)
		if d2 < 0.3 * 0.3:
			sc -= 1.0
	return sc - absf(absf(off) - 48.0) / 150.0


var _hold_pts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])


func _count_foes(p: Vector3, r: float) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var e3 := e as Node3D
		if e3 and Combat.is_alive(e3) and e3.global_position.distance_to(p) < r:
			n += 1
	return n


## 0 in the open .. 1 with walls close on both sides of the hero's head across `dir` (horizontal): a passage
## running along `dir` (the line to what the view frames).
func _tight_across(dir: Vector3) -> float:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-4:
		return 0.0
	var space := get_world_3d().direct_space_state
	var x := d.normalized().cross(Vector3.UP)
	_exclude_target()
	var o := _safe_origin()
	var dl := _ray_len(space, o, o - x * 2.4)
	var dr := _ray_len(space, o, o + x * 2.4)
	return clampf(1.0 - maxf(dl, dr) / 2.4, 0.0, 1.0)


## 0 in the open .. 1 with walls close on both sides of the pivot (and a roof).
func _measure_tight() -> float:
	var space := get_world_3d().direct_space_state
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	_exclude_target()
	var o := _safe_origin()
	var dl := _ray_len(space, o, o - b.x * 2.4)
	var dr := _ray_len(space, o, o + b.x * 2.4)
	var du := _ray_len(space, o, o + Vector3.UP * 2.4)
	var side := 1.0 - maxf(dl, dr) / 2.4
	var roof := 1.0 - du / 2.4
	return clampf(maxf(side, roof * 0.7), 0.0, 1.0)


func _ray_len(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> float:
	_ray_q.from = a
	_ray_q.to = b
	var hit := space.intersect_ray(_ray_q)
	return a.distance_to(b) if hit.is_empty() else a.distance_to(hit["position"])


func _place(real_dt: float, instant: bool) -> void:
	if mode != "follow":
		return
	global_position = focus
	rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	var want := distance_now if not instant else distance
	var b := global_transform.basis
	var want_cam := focus + b * Vector3(_side, 0.0, want)
	# the arm: a sphere cast on the world layer from the hero's head (inside his capsule, so always clear of the
	# world, unlike the pivot, which leads and shifts sideways) out to the wanted camera point
	var origin := _safe_origin()
	var full := origin.distance_to(want_cam)
	var safe := full
	if is_inside_tree():
		_exclude_target()
		_origin_q.transform = Transform3D(Basis.IDENTITY, origin)
		_origin_free = get_world_3d().direct_space_state.intersect_shape(_origin_q, 1).is_empty()
		safe = _clear_len(origin, want_cam, full)
		if safe < 1.0 and not instant and want > MIN_ARM + 0.5:
			# squeezed into the hero all at once (he brushed past a pillar at speed): rather than a frame inside his
			# helmet, jump round to the nearest clear side (up to 65 degrees) this very frame
			var need := maxf(MIN_ARM + 0.9, want * 0.6)
			for i in 6:
				var off: float = ORBIT_STEPS[i]
				if _clear_at(origin, want, off) >= need:
					yaw += off
					_orbit = 0.0
					rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
					b = global_transform.basis
					want_cam = focus + b * Vector3(_side, 0.0, want)
					full = origin.distance_to(want_cam)
					safe = _clear_len(origin, want_cam, full)
					break
	if instant or safe < _arm:
		_arm = safe
	else:
		# eases back out; fast while still in the hero's face
		var out_rate := 2.6 + 9.0 * clampf(1.0 - _arm / MIN_ARM, 0.0, 1.0)
		_arm = lerpf(_arm, safe, 1.0 - exp(-real_dt * out_rate))
	_arm = minf(_arm, full)
	if not instant and is_inside_tree():
		_steer_round(real_dt, origin, want, safe)
	var cam_world := origin
	if full > 1e-4:
		cam_world = origin + (want_cam - origin) * (_arm / full)
	# the nudge: a damped spring on the view's position
	_nudge_v += (-_nudge * 160.0 - _nudge_v * 18.0) * real_dt
	_nudge += _nudge_v * real_dt
	var local_nudge := b.inverse() * _nudge
	spring.position = b.inverse() * (cam_world - focus) + local_nudge
	spring.rotation = Vector3.ZERO
	cam.position = Vector3.ZERO
	var want_fov := fov + (FOV_SPRINT if _sprint else 0.0) + (FOV_ZIP if _zip else 0.0)
	_fov_now = want_fov if instant else lerpf(_fov_now, want_fov, 1.0 - exp(-real_dt * (6.0 if _zip else 3.0)))
	cam.fov = _fov_now
	if _dbg:
		print("CAM f=%d focus=%s yaw=%.1f pitch=%.1f arm=%.2f want=%.2f safe=%.2f full=%.2f cam=%s ts=%.3f tp=%s" % [Engine.get_process_frames(), str(focus), yaw, pitch, _arm, want, safe, full, str(cam.global_position), Engine.time_scale, str(_target_pos())])



## The cast's start: the hero's head, inside his capsule (the cast skips him), so never inside the world.
func _safe_origin() -> Vector3:
	return _target_pos() + Vector3(0, PIVOT_HEIGHT - 0.15, 0)


var _ex: Array[RID] = []
var _ex_for: Object = null


func _exclude_target() -> void:
	if _ex_for == target:
		return
	_ex_for = target
	_ex.clear()
	if target is CollisionObject3D:
		_ex.append((target as CollisionObject3D).get_rid())
	_shape_q.exclude = _ex
	_thin_q.exclude = _ex
	_ray_q.exclude = _ex
	_origin_q.exclude = _ex


## The clear fraction (0..1) of a sphere cast from `a` to `b` on the world layer (`thin`: THIN_RADIUS).
func _arm_cast(a: Vector3, b: Vector3, thin: bool = false) -> float:
	var q := _thin_q if thin else _shape_q
	q.transform = Transform3D(Basis.IDENTITY, a)
	q.motion = b - a
	var r := get_world_3d().direct_space_state.cast_motion(q)
	return r[0] if r.size() >= 1 else 1.0


## Clear length (m) of the arm from `origin` to `to` (`full` long): the camera sphere, or when that is cut short
## beside the hero (a pillar he brushes past), a thin one that may still find the view clear, grazing it (it still
## covers the near plane).
func _clear_len(origin: Vector3, to: Vector3, full: float) -> float:
	if not _origin_free:
		# the head itself is pressed into the world (moved without collision: a scripted move, a beast's anchor):
		# a cast starting inside a body skips that whole body (Jolt), so the arm is a ray instead, to the first
		# surface it meets, less the camera's radius
		_ray_q.from = origin
		_ray_q.to = to
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray_q)
		return full if hit.is_empty() else maxf(0.0, origin.distance_to(hit["position"]) - CAM_RADIUS)
	var safe := full * _arm_cast(origin, to)
	if safe < MIN_ARM:
		safe = maxf(safe, full * _arm_cast(origin, to, true))
	return safe


## Clear arm length (m) with the view turned `off` degrees round.
func _clear_at(origin: Vector3, want: float, off: float) -> float:
	var bb := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw + off), 0.0))
	var to := focus + bb * Vector3(_side, 0.0, want)
	return _clear_len(origin, to, origin.distance_to(to))


## Blocked close to the hero (a pillar, a trunk, a corner between him and the view): swing round the obstacle to
## the nearest clear angle, or raise the view over it. It starts as soon as the arm is cut under `need` (before
## the view is in the hero's face, as he walks past a pillar). Looking round by hand cancels the swing (unless the
## view stays blocked for a while or is squeezed into the hero).
func _steer_round(real_dt: float, origin: Vector3, want: float, safe: float) -> void:
	if _framed_narrow:
		_orbit = 0.0
		_raise = false
		_blocked = 0.0
		return
	var need := maxf(MIN_ARM + 0.9, want * 0.6)
	if safe < need and want > MIN_ARM + 0.5:
		_blocked += real_dt
	else:
		_blocked = 0.0
		_raise = false
	var squeezed := safe < 1.0 # the view is in the hero's helmet: no waiting for the player
	if _look_idle < 0.05 and _blocked < 0.6 and not squeezed:
		_orbit = 0.0
	_orbit_scan -= real_dt
	if _blocked > 0.0 and _orbit_scan <= 0.0 and (_look_idle > 0.3 or _blocked > 0.6 or squeezed):
		_orbit_scan = 0.15
		_orbit = 0.0
		_raise = safe < MIN_ARM
		for off: float in ORBIT_STEPS:
			if _clear_at(origin, want, off) >= need:
				_orbit = off
				_raise = false
				break
	if _orbit != 0.0:
		var rate := 360.0 if safe < MIN_ARM else 180.0
		var stp := clampf(_orbit, -rate * real_dt, rate * real_dt)
		yaw += stp
		_orbit -= stp
		if absf(_orbit) < 0.5:
			_orbit = 0.0
	elif _raise:
		# nowhere round is clear (a narrow passage): look down from higher up instead
		pitch = move_toward(pitch, -48.0, 70.0 * real_dt)
	elif _blocked == 0.0 and _look_idle > 0.5 and want > MIN_ARM + 0.5:
		# whiskers: the arm turned WHISKER degrees either way; drift away from a side that is cut short (a pillar
		# the hero is walking past) before the arm itself is
		var wl := _clear_at(origin, want, -WHISKER)
		var wr := _clear_at(origin, want, WHISKER)
		var push := clampf(1.0 - wr / need, 0.0, 1.0) - clampf(1.0 - wl / need, 0.0, 1.0)
		yaw -= push * WHISKER_RATE * real_dt


var _dbg := false


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
	spring.position = Vector3.ZERO
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
	# the noise gives the jolt's direction; its size is kept between 60 and 100 % of the full swing (simplex noise
	# alone often sits near 0 for a few frames: the same blow would shake 1 px one time and 5 px the next)
	var n := Vector2(_noise.get_noise_2d(_t * 40.0, 0.0), _noise.get_noise_2d(0.0, _t * 40.0)) * 1.6
	var l := n.length()
	if l > 1.0:
		n /= l
	elif l > 1e-4 and l < 0.6:
		n *= 0.6 / l
	cam.h_offset = n.x * s * 0.35
	cam.v_offset = n.y * s * 0.35
	cam.rotation.z = _noise.get_noise_2d(_t * 30.0, 50.0) * s * 0.05
