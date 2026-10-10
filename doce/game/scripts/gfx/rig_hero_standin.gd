class_name RigHeroStandIn
extends RigHoplite
## TEMPORARY hero model: PHAROS' bronze hoplite (closed Corinthian helmet, no face) speaking the full RigHeracles
## API, so player code can be written against that contract before scripts/gfx/rig_heracles.gd exists. Hero
## loads rig_heracles.gd automatically when the HERO stream delivers it; then this file can be deleted.
##
## RigHeracles API (docs/ARCHITECTURE.md): set_locomotion, set_motion_state(&"ground"|&"air"|&"swim"|&"zip"),
## set_vertical_speed, set_guard, set_outfit(&"helmet"|&"lion"), set_spear_on_back, play(action) -> length,
## signal event(name) with impact / release / step, hand_r(), hand_l(), chain_origin(), head().
## The stand-in only approximates the poses (no real throw, grapple or pet animation).

const ACTIONS := {
	"attack1": 0.34, "attack2": 0.34, "attack3": 0.52, "heavy": 0.7, "parry": 0.3, "dodge": 0.5, "jump": 0.25,
	"land": 0.22, "hit": 0.28, "hit_heavy": 0.5, "death": 1.2, "throw": 0.45, "pull": 0.4, "grapple_start": 0.4,
	"grapple_loop": 0.6, "grapple_end": 0.5, "interact": 0.5, "pet": 1.0, "don_skin": 1.4, "victory": 1.6,
}

## The hoplite leg's sandal (leg-local): sole height, toe and heel z.
const SOLE_Y := -0.865
const SOLE_TOE := -0.175
const SOLE_HEEL := 0.075

var motion_state: StringName = &"ground"
var vertical_speed := 0.0
var guard := false
var outfit: StringName = &"helmet"
var spear_on_back := true
var _hand_r: Node3D
var _hand_l: Node3D
var _guard_k := 0.0
var _swim_k := 0.0
var _air_k := 0.0
var _last_step_sign := 0.0


func _init() -> void:
	super(false)
	scale = Vector3.ONE * 0.93


func _ready() -> void:
	super()
	_hand_r = Node3D.new()
	_hand_r.name = "hand_r"
	_hand_r.position = Vector3(0, -0.3, -0.27)
	(parts["arm_r"] as Node3D).add_child(_hand_r)
	_hand_l = Node3D.new()
	_hand_l.name = "hand_l"
	_hand_l.position = Vector3(0, -0.3, -0.27)
	(parts["arm_l"] as Node3D).add_child(_hand_l)
	# No chain spear on the back: across the cape it could only clip through it. RigHeracles carries it properly.
	set_metal(1.0)


# --- RigHeracles API -----------------------------------------------------------------------------------------

func set_motion_state(s: StringName) -> void:
	motion_state = s


func set_vertical_speed(vy: float) -> void:
	vertical_speed = vy


func set_guard(on: bool) -> void:
	guard = on


func set_outfit(o: StringName) -> void:
	outfit = o
	# Stand-in: the lion outfit just turns the cape tawny.
	cape_color = Color("C9923F") if o == &"lion" else Pal.CLOTH_RED
	if parts.has("cape"):
		for c in (parts["cape"] as Node3D).get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).mesh = _mesh_cape()


## Stand-in: remembered only (no spear model on the back).
func set_spear_on_back(v: bool) -> void:
	spear_on_back = v


func hand_r() -> Node3D:
	return _hand_r


func hand_l() -> Node3D:
	return _hand_l


func head() -> Node3D:
	return parts.get("head")


## World position the chain leaves from (the throwing hand).
func chain_origin() -> Vector3:
	return _hand_r.global_position if _hand_r and _hand_r.is_inside_tree() else global_position + Vector3(0, 1.4, 0)


func _action_length(a: String) -> float:
	return float(ACTIONS.get(a, 0.4))


## Lowest point of a hoplite leg's sandal (hip-pivot space) when the leg swings by `a` radians about X.
func _sole_low(a: float) -> float:
	var c := cos(a)
	var sn := sin(a)
	return minf(SOLE_Y * c - SOLE_TOE * sn, SOLE_Y * c - SOLE_HEEL * sn)


## Volumes for tools/clip_check.gd (part-local ellipsoids [centre, radii]): the helmet without its crest and the
## cuirass without the shoulder guards, so the checker reports real contacts only.
func clip_volume(part: String) -> Array:
	match part:
		"head":
			return [Vector3(0, 0.184, 0), Vector3(0.245, 0.299, 0.273)]
		"torso":
			return [Vector3(0, 0.27, 0), Vector3(0.28, 0.27, 0.28)]
	return []


# --- animation -----------------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	# The hoplite's own actions cover the attacks, dodge, hit and death; map the others onto them.
	var real := action
	match action:
		"heavy":
			action = "attack3"
		"parry":
			action = "bash"
		"hit_heavy":
			action = "hit"
		"victory", "don_skin":
			action = "cheer"
		"throw", "pull", "interact", "pet", "grapple_start", "grapple_loop", "grapple_end", "jump", "land":
			action = ""
	super(delta)
	action = real
	# The hoplite marks "impact" at a fixed 0.38 s, after its quick strikes end: mark it at the blow instead.
	if action in ["attack1", "attack2", "attack3", "heavy"]:
		_mark("impact", action_len * 0.42)
	var body: Node3D = parts["body"]
	var torso: Node3D = parts["torso"]
	var arm_r: Node3D = parts["arm_r"]
	var arm_l: Node3D = parts["arm_l"]
	var leg_l: Node3D = parts["leg_l"]
	var leg_r: Node3D = parts["leg_r"]
	var shield: Node3D = parts["shield"]
	# The hoplite holds its aspis so close that the rim cuts into the left shoulder and the cuirass: hold it a
	# little further out and turned outwards (the parry brings it in front on purpose).
	shield.position = Vector3(-0.2, -0.3, -0.3)
	if action != "parry":
		shield.rotation.y += 0.25
	# Guard: shield up in front.
	_guard_k = move_toward(_guard_k, 1.0 if guard else 0.0, delta * 10.0)
	if _guard_k > 0.0 and action == "":
		arm_l.rotation = Rig.lerp_angle_v(arm_l.rotation, Vector3(1.25, 0.15, 0.0), _guard_k)
		shield.rotation = Rig.lerp_angle_v(shield.rotation, Vector3(-1.2, -0.05, 0.0), _guard_k)
	# Air: legs tucked a little, arms out for balance.
	_air_k = move_toward(_air_k, 1.0 if motion_state == &"air" or motion_state == &"zip" else 0.0, delta * 8.0)
	if _air_k > 0.0:
		var up := clampf(vertical_speed / 6.0, -1.0, 1.0)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -0.5 + 0.25 * up, _air_k)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.25 - 0.35 * up, _air_k)
		arm_l.rotation.z = lerpf(arm_l.rotation.z, -0.5, _air_k * 0.6)
		if motion_state == &"zip":
			torso.rotation.x = lerpf(torso.rotation.x, -0.45, _air_k)
	# Swim: lean forward, slow strokes (the water hides the legs).
	_swim_k = move_toward(_swim_k, 1.0 if motion_state == &"swim" else 0.0, delta * 4.0)
	if _swim_k > 0.0:
		var st := sin(t * 3.4)
		torso.rotation.x = lerpf(torso.rotation.x, -0.55, _swim_k)
		arm_r.rotation = Rig.lerp_angle_v(arm_r.rotation, Vector3(1.4 + st * 0.6, 0.0, 0.3), _swim_k)
		arm_l.rotation = Rig.lerp_angle_v(arm_l.rotation, Vector3(1.4 - st * 0.6, 0.0, -0.3), _swim_k)
		body.position.y = lerpf(body.position.y, -0.12, _swim_k)
	# Extra one-shot poses the hoplite does not have.
	if action != "":
		var p := ap()
		match action:
			"jump":
				body.position.y -= 0.12 * sin(p * PI) * (1.0 - p)
			"land":
				var k := sin(p * PI)
				body.position.y -= 0.16 * k
				torso.rotation.x += 0.25 * k
			"interact", "pet":
				var k := sin(minf(p * 2.0, 1.0) * PI * 0.5) * (1.0 - smooth((p - 0.7) / 0.3))
				torso.rotation.x += 0.45 * k
				arm_l.rotation = Rig.lerp_angle_v(arm_l.rotation, Vector3(1.1, 0.0, 0.0), k)
			"throw":
				var k := strike_curve(p, 0.45, 0.6)
				arm_r.rotation = Rig.lerp_angle_v(arm_r.rotation, Vector3(2.6 - 1.4 * maxf(k, 0.0), 0.0, 0.2), clampf(absf(k) * 1.5, 0.0, 1.0))
				torso.rotation.y += -0.4 * k
				_mark("release", 0.55)
			"pull":
				var k := sin(p * PI)
				torso.rotation.x -= 0.3 * k
				arm_r.rotation = Rig.lerp_angle_v(arm_r.rotation, Vector3(0.9, 0.0, 0.1), k)
				body.position.z += 0.1 * k
			"grapple_start", "grapple_loop", "grapple_end":
				var k := 1.0 if action == "grapple_loop" else (smooth(p) if action == "grapple_start" else 1.0 - smooth(p))
				torso.rotation.x += 0.6 * k
				arm_r.rotation = Rig.lerp_angle_v(arm_r.rotation, Vector3(1.6, 0.0, -0.4), k)
				arm_l.rotation = Rig.lerp_angle_v(arm_l.rotation, Vector3(1.6, 0.0, 0.4), k)
				# The aspis would lie flat over the raised forearm, into the helmet: turn it edge-on, facing outwards
				# on the outside of the left arm.
				shield.rotation = Rig.lerp_angle_v(shield.rotation, Vector3(0.0, PI * 0.5, 0.0), k)
				shield.position = shield.position.lerp(Vector3(-0.16, -0.32, -0.25), k)
				body.position.y -= 0.2 * k
	# Run cycle: the hoplite's legs are straight, so at full stride both feet left the ground and it seemed to glide.
	# Drop the hips so the lower foot stays planted (which also gives the stride its bounce).
	if action == "" and motion_state == &"ground" and _air_k <= 0.0 and _swim_k <= 0.0:
		var low := minf(_sole_low(leg_l.rotation.x), _sole_low(leg_r.rotation.x))
		body.position.y = SOLE_Y - low
	# Footstep events from the run cycle.
	var s := sin(_run_phase)
	if speed > 0.3 and motion_state == &"ground" and signf(s) != _last_step_sign:
		_last_step_sign = signf(s)
		event.emit("step")
