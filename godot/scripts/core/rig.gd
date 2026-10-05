# Character rig + procedural cartoon animator (port of src/core/rig.js; ARCHITECTURE §8/§12, GDD §3.6).
#
# Rig.createRig(spec) -> Rig.RigData { root, joints, dims, spec, base, attach(joint, obj) }. Feet at y=0, facing -z.
#   Joint names: hips, spine, chest, neck, head, shoulderL, elbowL, handL, shoulderR, elbowR, handR, hipL, kneeL,
#   footL, hipR, kneeR, footR. The head keeps its size (0.44 m x headScale); legs and torso are scaled to fit height.
#   Rotation conventions (radians): shoulder/hip.x > 0 swings the limb forward (-z), knee.x < 0 bends back,
#   elbow.x > 0 bends forward, spine.x < 0 leans forward, root faces -z.
#   Joints (and the root) are Node3D with EULER_ORDER_XYZ (three's default 'XYZ'), rest rotation identity, so game
#   code keeps writing `rig.joints.head.rotation.x = ...`, `rig.root.position.y = ...`, `rig.attach("head", node)`.
# Rig.Animator.new(rig, style) with style "hero" | "zombie" | "puppet" | { ...params } (merged over "hero", or over
#   STYLES[params.base]). animator.update(dt, state) with state = { speed, sprint, grounded, aimPitch, aimYaw,
#   aiming, recoil, reload, melee, hurt, climb, attack, dance, down, dead } plus optional extras:
#   back (walking backwards), turn (yaw rate rad/s), legYaw (strafe: legs turned toward movement, radians).
#   animator.override = func(rig, dt) | null runs after the procedural pose; animator.pose(name, weight) blends a
#   named static pose from POSES (registerPose adds more); animator.kick(amount) = squash/head-spring impulse.
#   animator.headLag {x, z} exposes the head spring for hair/antenna secondary motion. Spring is exported too.
#
# GDScript port notes:
#   * JS code assigned `animator.update = fn` to wrap or freeze an animator (charRuntime wraps it with the rest
#     offsets + face; wonder.js freezes zombies with a no-op). GDScript methods cannot be reassigned, so update()
#     dispatches to the assignable Callable field `updateFn` when it is valid (otherwise the procedural update runs):
#       JS  `const orig = a.update.bind(a); a.update = (dt, st) => {...}`  ->  `var orig = a.updateFn if
#           a.updateFn.is_valid() else a._procUpdate; a.updateFn = func(dt, st): ...`
#       JS  `a.update = () => {}` / restore            ->  `a.updateFn = func(_dt, _st): pass` / `a.updateFn = prev`
#   * JS weapons.js also wraps the hero's update to run its IK pose after everything else; here that is the
#     `postUpdate` Array of Callables (rig, dt), called in order at the very end of update() (after updateFn /
#     the procedural pose, the override and the charRuntime wrapper work).
#   * FnAnimator is the base of the custom animators returned by character definitions (createAnimator): an object
#     with the same surface (update, kick, override, updateFn) whose update is the Callable `updateFn`.
#   * Math.random() -> randf(). JS quaternion math (setFromEuler, slerp, multiply) is reproduced exactly (quatXYZ,
#     quatYXZ, slerp below) so poses match the three.js build numerically (tests: scratch rig_compare).
class_name Rig
extends RefCounted

# Damped spring (GDD §3.6: k=120, damping 12). update(dt, target) -> x. Substepped for stability.
class Spring extends RefCounted:
	var k: float
	var d: float
	var x: float
	var v: float = 0.0

	func _init(k_: float = 120.0, d_: float = 12.0, x_: float = 0.0) -> void:
		k = k_
		d = d_
		x = x_
		v = 0.0

	func update(dt: float, target: float = 0.0) -> float:
		var n: int = maxi(1, ceili(dt / (1.0 / 120.0)))
		var h: float = dt / n
		for i in n:
			v += (-k * (x - target) - d * v) * h
			x += v * h
		return x

	func kick(impulse: float) -> void:
		v += impulse

	func reset(x_: float = 0.0) -> void:
		x = x_
		v = 0.0


const JOINTS := ["hips", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "handL", "shoulderR", "elbowR",
	"handR", "hipL", "kneeL", "footL", "hipR", "kneeR", "footR"]

# The rig object ({ root, joints, dims, spec, base, attach } in JS). base = [[joint, rest position], ...] (JS Map).
class RigData extends RefCounted:
	var root: Node3D
	var joints: Dictionary = {}
	var dims: Dictionary = {}
	var spec: Dictionary = {}
	var base: Array = []

	# joint: joint name or Node3D. Like three's add(): obj leaves its previous parent, keeps its local transform.
	func attach(joint, obj: Node) -> Node:
		var j: Node = joints.get(joint) if (joint is String or joint is StringName) else joint
		if obj.get_parent() != null:
			obj.get_parent().remove_child(obj)
		j.add_child(obj)
		return obj


static func createRig(spec: Dictionary = {}) -> RigData:
	var s := {"height": 1.7, "headScale": 1.0, "shoulderW": 0.42, "hipW": 0.26, "armLen": 0.62, "legLen": 0.78, "torsoLen": 0.5}
	s.merge(spec, true)
	var height: float = s.height
	var headH: float = 0.44 * float(s.headScale)
	var neckH := 0.05
	var ankle := 0.07
	var hipDrop := 0.03
	var k: float = maxf(0.5, (height - headH - neckH - ankle) / (float(s.legLen) + float(s.torsoLen)))
	var leg: float = float(s.legLen) * k
	var torso: float = float(s.torsoLen) * k
	var arm: float = float(s.armLen) * minf(1.0, k * 1.05)
	var dims := {
		"height": height, "headH": headH, "neckH": neckH, "ankle": ankle, "torso": torso, "leg": leg, "hipsY": leg + ankle,
		"upperLeg": (leg - hipDrop) * 0.5, "lowerLeg": (leg - hipDrop) * 0.5,
		"upperArm": arm * 0.48, "foreArm": arm * 0.52, "shoulderW": float(s.shoulderW), "hipW": float(s.hipW),
		"shoulderY": torso * 0.55 - 0.06,
	}

	var j := {}
	for n in JOINTS:
		j[n] = DAU.node3d(n)
	var root := DAU.node3d("rig")
	root.add_child(j.hips)
	j.hips.position = Vector3(0, dims.hipsY, 0)
	j.hips.add_child(j.spine)
	j.hips.add_child(j.hipL)
	j.hips.add_child(j.hipR)
	j.spine.position = Vector3(0, 0.02, 0)
	j.spine.add_child(j.chest)
	j.chest.position = Vector3(0, torso * 0.45, 0)
	j.chest.add_child(j.neck)
	j.chest.add_child(j.shoulderL)
	j.chest.add_child(j.shoulderR)
	j.neck.position = Vector3(0, torso * 0.55 - 0.02, 0)
	j.neck.add_child(j.head)
	j.head.position = Vector3(0, neckH, 0)
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var sh: Node3D = j["shoulder" + side]
		var el: Node3D = j["elbow" + side]
		var ha: Node3D = j["hand" + side]
		sh.position = Vector3(sx * float(s.shoulderW) / 2.0, dims.shoulderY, 0)
		sh.add_child(el)
		el.position = Vector3(0, -dims.upperArm, 0)
		el.add_child(ha)
		ha.position = Vector3(0, -dims.foreArm, 0)
		var hp: Node3D = j["hip" + side]
		var kn: Node3D = j["knee" + side]
		var ft: Node3D = j["foot" + side]
		hp.position = Vector3(sx * float(s.hipW) / 2.0, -hipDrop, 0)
		hp.add_child(kn)
		kn.position = Vector3(0, -dims.upperLeg, 0)
		kn.add_child(ft)
		ft.position = Vector3(0, -dims.lowerLeg, 0)

	var r := RigData.new()
	r.root = root
	r.joints = j
	r.dims = dims
	r.spec = s
	for n in JOINTS:
		r.base.append([j[n], j[n].position])
	return r


const STYLES := {
	"hero": {
		"cycle": 1.6, "cycleK": 0.3, "bob": 0.05, "squash": 0.035, "legSwing": 0.42, "legRun": 0.4, "knee": 0.55, "arm": 0.55,
		"armRun": 0.35, "elbow": 0.35, "lean": 0.1, "twist": 0.13, "sway": 0.035, "breathe": 0.01, "headLag": 1, "arms": "swing",
		"alignHand": true, "wobble": 0, "randomPhase": false,
	},
	"zombie": {
		"cycle": 1.15, "cycleK": 0.25, "bob": 0.035, "squash": 0.03, "legSwing": 0.3, "legRun": 0.32, "knee": 0.3, "arm": 0.12,
		"armRun": 0.12, "elbow": 0.12, "lean": 0.22, "twist": 0.06, "sway": 0.13, "breathe": 0.012, "headLag": 1.4, "arms": "forward",
		"alignHand": false, "wobble": 1, "randomPhase": true,
	},
	"puppet": {
		"cycle": 1.3, "cycleK": 0.2, "bob": 0.12, "squash": 0.1, "legSwing": 0.5, "legRun": 0.3, "knee": 0.8, "arm": 0.9,
		"armRun": 0.3, "elbow": 0.6, "lean": 0.05, "twist": 0.15, "sway": 0.08, "breathe": 0.02, "headLag": 2, "arms": "floppy",
		"alignHand": false, "wobble": 0.5, "randomPhase": true,
	},
}

# Named static poses: joint -> [x, y, z] Euler (XYZ). Blended with animator.pose(name, weight).
# Heads are BIG (baked heroes: headScale 1.3 = 0.57 m, Roxy's afro ~0.72 m wide, Penny's hair curtains to the chest,
# arms only 0.43-0.5 m): every pose that lifts a hand keeps it OUT to the side. Shoulder z > 0 swings the RIGHT arm
# out (left arm: z < 0); with XYZ order a raised arm (x ~ PI) keeps that z lean, so a negative z on a raised right arm
# leans it in over the head (the old point / shoulder / wave went through the face). Clearance is measured per hero
# (tools/scenarios/fix3_poseview.js, surface to surface, incl. hair / afro / glasses / earrings, and through the
# menu's blend-in): point >= 6 cm, shoulder >= 8 cm, wave >= 6 cm, thumbsup >= 13 cm, fingerguns / shrug >= 10 cm.
static var POSES := _makePoses()

static func _makePoses() -> Dictionary:
	var P := {
		# disco point to the sky: right arm up and out (~48 deg from vertical, a little forward), clear of the afro; left
		# hand on the hip, hips kicked, torso and head leaning away from the arm, chin up toward the hand
		"point": {"shoulderR": [2.7, 0, 0.82], "elbowR": [0.1, 0, 0], "handR": [0, 1.3, 0], "shoulderL": [-0.2, 0, -0.55], "elbowL": [1.75, 0, 0],
			"hips": [0, 0, 0.08], "spine": [0, 0, 0.06], "head": [0.25, -0.15, 0.1]},
		# double thumbs-up at chest height, hands apart (the old inward version put both hands in front of the chin)
		# (char-polish: wrists bent back so the fists stand upright and the thumbs point straight up)
		"thumbsup": {"shoulderR": [0.8, 0, 0.25], "elbowR": [1.5, 0, 0], "shoulderL": [0.8, 0, -0.25], "elbowL": [1.5, 0, 0], "head": [0.1, 0, 0.12],
			"handR": [-0.7, 0, 0], "handL": [-0.7, 0, 0]},
		# hip-level finger guns aimed at the viewer, elbows bent, a cocky lean back + head tilt (char-polish: the arms used
		# to stick straight at the camera, hands hiding the chest)
		"fingerguns": {"shoulderR": [0.65, 0, 0.32], "elbowR": [0.95, 0, 0], "shoulderL": [0.65, 0, -0.32], "elbowL": [0.95, 0, 0], "chest": [0, 0.2, 0],
			"spine": [-0.04, 0, 0], "head": [-0.06, 0.12, 0.1]},
		# (wrench) on the shoulder: elbow out to the side at chest height, forearm folded back up, the hand resting palm-up
		# at the front of the shoulder beside the jaw (outside the hair curtain, not at the face); left hand on the hip
		"shoulder": {"shoulderR": [0.82, -0.53, 0.95], "elbowR": [2.55, 0, 0], "handR": [-0.9, 0.8, 0], "shoulderL": [-0.2, 0, -0.55], "elbowL": [1.75, 0, 0],
			"head": [0.05, 0.1, 0.06]},
		"shrug": {"shoulderR": [0.4, 0, -0.9], "elbowR": [1.5, 0, 0], "shoulderL": [0.4, 0, 0.9], "elbowL": [1.5, 0, 0], "head": [0, 0, 0.2]},
		# upper arm out to the side and slightly up, forearm up: the hand waves beside the head, not over it
		"wave": {"shoulderR": [1.56, 0.29, 1.1], "elbowR": [1.14, 0, 0]},
	}
	# Each hero's signature commercial pose (menu channels, the ending's freeze-frame, sponsors' double_vision).
	P.commercial_skip = P.thumbsup
	P.commercial_roxy = P.point
	P.commercial_penny = P.shoulder
	P.commercial_duke = P.fingerguns
	return P

static func registerPose(name: String, joints: Dictionary) -> void:
	POSES[name] = joints

# Hand shapes of the named poses (char-polish): baked heroes carry one rigid hand part per shape (open, thumb, gun,
# grip, fist; blender/chars/defs/_hands.py) and show the shape requested this frame (animator.hand(side, shape);
# scripts/art/char_runtime.gd CharSkeleton applies it). A pose blended at weight >= 0.5 requests its shapes.
static var POSE_HANDS := {
	"thumbsup": {"L": "thumb", "R": "thumb"},
	"fingerguns": {"L": "gun", "R": "gun"},
	"point": {"R": "gun"},
	"commercial_skip": {"L": "thumb", "R": "thumb"},
	"commercial_roxy": {"R": "gun"},
	"commercial_duke": {"L": "gun", "R": "gun"},
}

# Hand shapes of a pose given as its joint Dictionary (sponsors.gd poses the rig directly with POSES.<name>).
static func poseHands(P) -> Dictionary:
	for k in POSE_HANDS:
		if is_same(POSES.get(k), P):
			return POSE_HANDS[k]
	return {}

# rig.js shares ONE module-level THREE.Euler (_e) between _applyPoses (`_e.set(x, y, z)`, which keeps the Euler's
# current order) and _alignHand (`_e.set(pitch, yaw, roll, 'YXZ')`). So once any animator has aligned a hand, every
# later named pose (all animators) is read as 'YXZ'. Reproduced as is (same poses as the web build).
static var _eOrder := "XYZ"


# ------------------------------------------------------------------------------------------------ three.js math
# Quaternion.setFromEuler for order 'XYZ' (three's default) and 'YXZ'.
static func quatXYZ(x: float, y: float, z: float) -> Quaternion:
	var c1 := cos(x / 2.0)
	var c2 := cos(y / 2.0)
	var c3 := cos(z / 2.0)
	var s1 := sin(x / 2.0)
	var s2 := sin(y / 2.0)
	var s3 := sin(z / 2.0)
	return Quaternion(s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3)

static func quatYXZ(x: float, y: float, z: float) -> Quaternion:
	var c1 := cos(x / 2.0)
	var c2 := cos(y / 2.0)
	var c3 := cos(z / 2.0)
	var s1 := sin(x / 2.0)
	var s2 := sin(y / 2.0)
	var s3 := sin(z / 2.0)
	return Quaternion(s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 - s1 * s2 * c3, c1 * c2 * c3 + s1 * s2 * s3)

# three's Quaternion.slerp(qb, t) (acos slerp, lerp + normalize for small angles).
static func slerp(a: Quaternion, qb: Quaternion, t: float) -> Quaternion:
	var x := qb.x
	var y := qb.y
	var z := qb.z
	var w := qb.w
	var dot := a.x * x + a.y * y + a.z * z + a.w * w
	if dot < 0.0:
		x = -x
		y = -y
		z = -z
		w = -w
		dot = -dot
	var s := 1.0 - t
	if dot < 0.9995:
		var theta := acos(dot)
		var sn := sin(theta)
		s = sin(s * theta) / sn
		t = sin(t * theta) / sn
		return Quaternion(a.x * s + x * t, a.y * s + y * t, a.z * s + z * t, a.w * s + w * t)
	var q := Quaternion(a.x * s + x * t, a.y * s + y * t, a.z * s + z * t, a.w * s + w * t)
	var l := sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
	if l == 0.0:
		return Quaternion(0, 0, 0, 1)
	return Quaternion(q.x / l, q.y / l, q.z / l, q.w / l)

# three's object.quaternion of an XYZ-order node (kept in sync with object.rotation).
static func quatOf(n: Node3D) -> Quaternion:
	var r := n.rotation
	return quatXYZ(r.x, r.y, r.z)

# World transform of a node whether or not it is inside the scene tree (object.matrixWorld).
static func worldTransform(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.global_transform
	var t := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

# object.getWorldQuaternion (matrixWorld.decompose: columns divided by their lengths).
static func worldQuat(n: Node3D) -> Quaternion:
	var b := worldTransform(n).basis
	var sx := b.x.length()
	if b.determinant() < 0.0:
		sx = -sx
	var m := Basis(b.x / sx, b.y / b.y.length(), b.z / b.z.length())
	return _quatFromBasis(m)

# three's Quaternion.setFromRotationMatrix (m = pure rotation).
static func _quatFromBasis(m: Basis) -> Quaternion:
	# three elements: m11 = col0.x, m12 = col1.x, m13 = col2.x, m21 = col0.y ...
	var m11 := m.x.x
	var m12 := m.y.x
	var m13 := m.z.x
	var m21 := m.x.y
	var m22 := m.y.y
	var m23 := m.z.y
	var m31 := m.x.z
	var m32 := m.y.z
	var m33 := m.z.z
	var tr := m11 + m22 + m33
	if tr > 0.0:
		var s := 0.5 / sqrt(tr + 1.0)
		return Quaternion((m32 - m23) * s, (m13 - m31) * s, (m21 - m12) * s, 0.25 / s)
	elif m11 > m22 and m11 > m33:
		var s := 2.0 * sqrt(1.0 + m11 - m22 - m33)
		return Quaternion(0.25 * s, (m12 + m21) / s, (m13 + m31) / s, (m32 - m23) / s)
	elif m22 > m33:
		var s := 2.0 * sqrt(1.0 + m22 - m11 - m33)
		return Quaternion((m12 + m21) / s, 0.25 * s, (m23 + m32) / s, (m13 - m31) / s)
	var s := 2.0 * sqrt(1.0 + m33 - m11 - m22)
	return Quaternion((m13 + m31) / s, (m23 + m32) / s, 0.25 * s, (m21 - m12) / s)

static func _conj(q: Quaternion) -> Quaternion:
	return Quaternion(-q.x, -q.y, -q.z, q.w)

static func easeOutBounce(x: float) -> float:
	var n := 7.5625
	var d := 2.75
	if x < 1.0 / d:
		return n * x * x
	if x < 2.0 / d:
		x -= 1.5 / d
		return n * x * x + 0.75
	if x < 2.5 / d:
		x -= 2.25 / d
		return n * x * x + 0.9375
	x -= 2.625 / d
	return n * x * x + 0.984375

static func smooth(a: float, b: float, x: float) -> float:
	return DAU.smoothstep3(x, a, b)

# JS `v || 0` for animator state values (null / false / missing -> 0, true -> 1).
static func num(v) -> float:
	if v == null:
		return 0.0
	if v is bool:
		return 1.0 if v else 0.0
	if v is int or v is float:
		return float(v)
	return 0.0

# JS truthiness.
static func truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String or v is StringName:
		return v != ""
	return true

static func lerpRot(obj: Node3D, x: float, y: float, z: float, a: float) -> void:
	var r := obj.rotation
	obj.rotation = Vector3(r.x + (x - r.x) * a, r.y + (y - r.y) * a, r.z + (z - r.z) * a)


class Animator extends RefCounted:
	var rig
	var p: Dictionary
	var seed: float
	var phase: float
	var t: float
	var move := 0.0       # eased locomotion weight
	var run := 0.0        # eased run factor
	var aimW := 0.0
	var air := 0.0
	var override = null   # Callable (rig, dt) | null
	var updateFn: Callable = Callable()   # assignable `update` (see the header)
	var postUpdate: Array = []            # Callables (rig, dt) run at the end of update() (weapons IK pose)
	var _poses := {}
	var hands := {}                       # side 'L'/'R' -> [shape, process frame] (hand(); POSE_HANDS)
	var _grounded := true
	var _hurt := 0.0
	var squash: Rig.Spring
	var headLag := {"x": 0.0, "z": 0.0}
	var _lagX: Rig.Spring
	var _lagZ: Rig.Spring
	var _prevBob := 0.0
	var _bobVel := 0.0
	var wob: Dictionary

	func _init(rig_, style = "hero") -> void:
		rig = rig_
		var custom = style if style is Dictionary else null
		var baseName = (custom.get("base") if Rig.truthy(custom.get("base")) else "hero") if custom != null else style
		p = (Rig.STYLES.get(baseName, Rig.STYLES.hero) as Dictionary).duplicate(true)
		if custom != null:
			p.merge(custom, true)
		seed = randf() * 1000.0
		phase = randf() * PI * 2.0 if Rig.truthy(p.randomPhase) else 0.0
		t = randf() * 10.0 if Rig.truthy(p.randomPhase) else 0.0
		squash = Rig.Spring.new(260, 15)
		_lagX = Rig.Spring.new(120, 12)
		_lagZ = Rig.Spring.new(120, 12)
		# Per-instance gait character (zombies shamble differently).
		var wobble: float = p.wobble
		wob = {
			"amp": 1.0 + (randf() - 0.5) * 0.5 * wobble,
			"tilt": (randf() - 0.5) * 0.35 * wobble,
			"armL": (randf() - 0.5) * 0.4 * wobble,
			"armR": (randf() - 0.5) * 0.4 * wobble,
			"speed": 1.0 + (randf() - 0.5) * 0.3 * wobble,
		}

	func pose(name: String, weight: float = 1.0) -> void:
		if weight <= 0.0 or not Rig.POSES.has(name):
			_poses.erase(name)
		else:
			_poses[name] = weight

	# Request a hand shape for this frame (side 'L' | 'R'; 'open' | 'thumb' | 'gun' | 'grip' | 'fist'). Without a
	# request in the last frame the hand shows 'open'.
	func hand(side: String, shape: String) -> void:
		hands[side] = [shape, Engine.get_process_frames()]

	func kick(amount: float = 1.0) -> void:
		squash.kick(-3.2 * amount)
		_lagX.kick(4.0 * amount)

	func update(dt: float, st: Dictionary = {}) -> void:
		stamp = Engine.get_process_frames()
		if updateFn.is_valid():
			updateFn.call(dt, st)
		else:
			_procUpdate(dt, st)
		for fn in postUpdate:
			if fn is Callable and (fn as Callable).is_valid():
				(fn as Callable).call(rig, dt)

	func _procUpdate(dt: float, st: Dictionary = {}) -> void:
		if _fast < 0:
			_fastInit()
		if _fast == 1:
			_procFast(dt, st, false)
		else:
			_procSlow(dt, st)

	# ---- perf: fast path of the procedural pose (humanoid rigs: rig.base = the 17 JOINTS in order) --------------
	# The pose is accumulated in typed locals with the same arithmetic in the same order as the generic path
	# (_procSlow; Vector3 components are float32 exactly like the Node3D fields they stand for) and every joint is
	# written once at the end instead of reset + read-modify-write per layer. Style params / wobble cached as floats
	# (p.arms is read every update: the Forecaster switches it at run time).
	# With restOn (char_runtime: rest offsets + face folded in, see charUpdate) and no named pose / override /
	# hand alignment this frame, the rest offsets are added to the locals before the single write.
	var _fast := -1                       # -1 not checked yet, 0 generic path, 1 fast path
	var _jn: Array[Node3D] = []
	var _jbase := PackedVector3Array()
	var _rootN: Node3D = null
	var _pCycle := 0.0
	var _pCycleK := 0.0
	var _pBob := 0.0
	var _pSquash := 0.0
	var _pLegSwing := 0.0
	var _pLegRun := 0.0
	var _pKnee := 0.0
	var _pArm := 0.0
	var _pArmRun := 0.0
	var _pElbow := 0.0
	var _pLean := 0.0
	var _pTwist := 0.0
	var _pSway := 0.0
	var _pBreathe := 0.0
	var _pHeadLag := 0.0
	var _pWobble := 0.0
	var _pAlign := false
	var _wAmp := 1.0
	var _wTilt := 0.0
	var _wArmL := 0.0
	var _wArmR := 0.0
	var _wSpeed := 1.0
	var _dLeg := 0.0
	var stamp := -1                       # process frame of the last update() (CharSkeleton lazy sync)
	# posStatic: only update() (its override / poses) moves the joints other than the hips (pooled zombie models): their
	# rest positions are re-checked only after an update that ran such external code
	var posStatic := false
	var _posTouched := true
	# char_runtime wrapper state (charUpdate): rest offsets (def.armOut / def.poseOffset) + the face
	var restOn := false
	var restArmOut := 0.0
	var restOffs = null                   # [[Node3D, [x, y, z]], ...] (generic path) | null
	var _offV := PackedVector3Array()     # the same offsets per JOINTS index (fast path)
	var _offMask := 0
	var face = null

	func _fastInit() -> void:
		_fast = 0
		var J = rig.joints
		var B: Array = rig.base
		if not (J is Dictionary) or B.size() != Rig.JOINTS.size() or not (rig.root is Node3D):
			return
		var jn: Array[Node3D] = []
		var jb := PackedVector3Array()
		for i in B.size():
			var e: Array = B[i]
			if not (e[0] is Node3D) or not is_same(e[0], J.get(Rig.JOINTS[i])):
				return
			jn.append(e[0])
			jb.append(e[1])
		_jn = jn
		_jbase = jb
		_rootN = rig.root
		_pCycle = float(p.cycle)
		_pCycleK = float(p.cycleK)
		_pBob = float(p.bob)
		_pSquash = float(p.squash)
		_pLegSwing = float(p.legSwing)
		_pLegRun = float(p.legRun)
		_pKnee = float(p.knee)
		_pArm = float(p.arm)
		_pArmRun = float(p.armRun)
		_pElbow = float(p.elbow)
		_pLean = float(p.lean)
		_pTwist = float(p.twist)
		_pSway = float(p.sway)
		_pBreathe = float(p.breathe)
		_pHeadLag = float(p.headLag)
		_pWobble = float(p.wobble)
		_pAlign = Rig.truthy(p.alignHand)
		_wAmp = float(wob.amp)
		_wTilt = float(wob.tilt)
		_wArmL = float(wob.armL)
		_wArmR = float(wob.armR)
		_wSpeed = float(wob.speed)
		_dLeg = float(rig.dims.leg) if rig.dims is Dictionary and rig.dims.get("leg") != null else 0.0
		_offV.resize(jn.size())
		_offMask = 0
		if restOffs is Array:
			for o in restOffs:
				var k := jn.find(o[0])
				if k < 0:
					_fast = 0
					return
				var e: Array = o[1]
				_offV[k] = Vector3(e[0], e[1], e[2])
				_offMask |= 1 << k
		_fast = 1

	# char_runtime's update wrapper (updateFn): the procedural pose, the rest offsets, the face.
	func charUpdate(dt: float, st: Dictionary = {}) -> void:
		if _fast < 0:
			_fastInit()
		if _fast == 1:
			_procFast(dt, st, true)
		else:
			_procSlow(dt, st)
			CharRuntime.applyRestOffsets(rig.joints, restArmOut, restOffs)
		if face != null:
			face.update(dt)

	static func _lerpV(r: Vector3, x: float, y: float, z: float, a: float) -> Vector3:
		return Vector3(r.x + (x - r.x) * a, r.y + (y - r.y) * a, r.z + (z - r.z) * a)

	static func _n(v) -> float:
		if v is float:
			return v
		if v == null:
			return 0.0
		return Rig.num(v)

	func _procFast(dt: float, st: Dictionary, rest: bool) -> void:
		t += dt
		var tt := t
		var speed := _n(st.get("speed"))
		var gv = st.get("grounded", true)
		var grounded: bool = not (gv is bool and gv == false)
		var dn := 1.0 - exp(-dt * 10.0)
		var arms = p.arms
		var armsFwd: bool = arms == "forward"
		var hipsP: Vector3 = _jbase[0]
		var rHips := Vector3.ZERO
		var rSpine := Vector3.ZERO
		var rChest := Vector3.ZERO
		var rHead := Vector3.ZERO
		var rShL := Vector3.ZERO
		var rElL := Vector3.ZERO
		var rShR := Vector3.ZERO
		var rElR := Vector3.ZERO
		var rHipL := Vector3.ZERO
		var rKnL := Vector3.ZERO
		var rFtL := Vector3.ZERO
		var rHipR := Vector3.ZERO
		var rKnR := Vector3.ZERO
		var rFtR := Vector3.ZERO
		var rootRot := Vector3.ZERO

		var moving := clampf(speed / 1.2, 0.0, 1.0) if grounded else 0.0
		move += (moving - move) * dn
		run += (clampf(speed / 4.6, 0.0, 1.5) - run) * dn
		aimW += ((1.0 if Rig.truthy(st.get("aiming")) else 0.0) - aimW) * (1.0 - exp(-dt * 14.0))
		air += ((0.0 if grounded else 1.0) - air) * (1.0 - exp(-dt * 12.0))
		var w := move
		var rn := run
		var ai := air

		if grounded and not _grounded:
			squash.kick(-3.4)
		if not grounded and _grounded:
			squash.kick(1.8)
		_grounded = grounded
		var hurt := _n(st.get("hurt"))
		if hurt > _hurt + 0.3:
			squash.kick(-2.6)
			_lagX.kick(-5)
		_hurt = hurt

		var cycle: float = (_pCycle + _pCycleK * speed) / _wSpeed
		phase += (-1.0 if Rig.truthy(st.get("back")) else 1.0) * dt * (speed / cycle) * PI * 2.0 * (1.0 if grounded else 0.25)
		var ph := phase
		var sn := sin(ph)
		var cs := cos(ph)

		# Legs.
		var legA: float = (_pLegSwing + _pLegRun * rn) * w * _wAmp
		var kneeA: float = (_pKnee + 0.9 * rn) * w
		rHipL.x = sn * legA
		rHipR.x = -sn * legA
		rKnL.x = -(0.08 + maxf(0.0, cs) * kneeA) - 0.06 * w
		rKnR.x = -(0.08 + maxf(0.0, -cs) * kneeA) - 0.06 * w
		rFtL.x = -(rHipL.x + rKnL.x) * 0.7
		rFtR.x = -(rHipR.x + rKnR.x) * 0.7

		# Body bounce.
		var pass_ := pow(absf(cs), 0.7)
		var bob: float = w * _pBob * (0.6 + rn * 0.6) * (pass_ - 0.5)
		hipsP.y += bob
		_bobVel = (bob - _prevBob) / maxf(dt, 1e-4)
		_prevBob = bob
		var contact := pow(1.0 - absf(cs), 5.0) * w
		var sq := squash.update(dt, 0.0)
		var sy: float = 1.0 + sq - contact * _pSquash
		var rootScale := Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))

		# Torso.
		var lean := _pLean
		var sway := _pSway
		var twist := _pTwist
		rSpine.x = -(0.03 + lean * (0.4 + rn)) * w - (lean * 0.6 if armsFwd else 0.0)
		var turn := _n(st.get("turn"))
		rSpine.z = clampf(-turn * 0.05, -0.2, 0.2) + cs * sway * w * 0.5
		rHips.y = -sn * twist * 0.6 * w
		rChest.y = sn * twist * w * (0.5 + rn)
		rHips.z = cs * sway * w
		var legYaw := _n(st.get("legYaw")) * w
		rHips.y += legYaw
		rSpine.y -= legYaw
		var breatheP := _pBreathe
		var breathe := 1.0 + breatheP + breatheP * sin(tt * PI * 2.0 * 0.3)
		var chestScale := Vector3(1.0 + (breathe - 1.0) * 0.5, breathe, 1.0 + (breathe - 1.0) * 0.7)

		# Arms.
		var armA: float = (_pArm + _pArmRun * rn) * w
		if armsFwd:
			var sw := sin(tt * 1.4 * _wSpeed + seed) * 0.12
			rShL = Vector3(PI / 2.0 - 0.22 + sw + sn * armA + _wArmL, 0, 0.12)
			rShR = Vector3(PI / 2.0 - 0.22 - sw - sn * armA + _wArmR, 0, -0.12)
			rElL.x = 0.12 + sin(tt * 2.1 + seed) * 0.08
			rElR.x = 0.12 + cos(tt * 2.3 + seed) * 0.08
		else:
			var flop := sin(tt * 5.0 + seed) * 0.25 if arms == "floppy" else 0.0
			rShL = Vector3(-sn * armA + flop, 0, 0.1 + 0.05 * (1.0 - w))
			rShR = Vector3(sn * armA - flop, 0, -0.1 - 0.05 * (1.0 - w))
			var elbow := _pElbow
			rElL.x = 0.15 + (elbow + rn * 0.5) * w + maxf(0.0, -sn) * 0.3 * w
			rElR.x = 0.15 + (elbow + rn * 0.5) * w + maxf(0.0, sn) * 0.3 * w
			var idle := (1.0 - w) * sin(tt * 1.9) * 0.03
			rShL.x += idle
			rShR.x -= idle

		# Air pose.
		if ai > 0.01:
			rHipL.x += 0.55 * ai
			rKnL.x -= 0.9 * ai
			rHipR.x += 0.15 * ai
			rKnR.x -= 0.45 * ai
			rShL.z += 0.45 * ai
			rShR.z -= 0.45 * ai

		# Aiming.
		var pitch := _n(st.get("aimPitch"))
		var yaw := _n(st.get("aimYaw"))
		rSpine.y += yaw
		if aimW > 0.001:
			var a := aimW
			var lift := pitch * 0.85
			rShR = _lerpV(rShR, PI / 2.0 + lift - 0.28, 0, -0.05, a)
			rElR.x = lerpf(rElR.x, 0.3, a)
			rShL = _lerpV(rShL, PI / 2.0 + lift - 0.55, 0, 0.62, a)
			rElL.x = lerpf(rElL.x, 0.85, a)
			rChest.x += pitch * 0.25 * a
		rHead.x += pitch * 0.35 + (1.0 - aimW) * 0.04
		rHead.y += yaw * 0.25

		# Recoil / reload / melee layers.
		var rec := _n(st.get("recoil"))
		if rec > 0.0:
			rChest.x += rec * 0.1
			rShR.x += rec * 0.35
			rShL.x += rec * 0.25
		var rl := _n(st.get("reload"))
		var rarc := sin(PI * rl) if rl > 0.0 and rl < 1.0 else 0.0
		if rarc > 0.0:
			rShL.x -= rarc * 1.0
			rElL.x += rarc * 0.6
			rShR.x -= rarc * 0.35
			rHead.x -= rarc * 0.25
		var ml := _n(st.get("melee"))
		if ml > 0.0 and ml < 1.0:
			var wind := Rig.smooth(0, 0.25, ml)
			var strike := Rig.smooth(0.25, 0.45, ml)
			var back := Rig.smooth(0.55, 1, ml)
			var k := wind * (1.0 - back)
			rChest.y += (0.45 * wind - 0.9 * strike) * (1.0 - back)
			rShR.x = lerpf(rShR.x, lerpf(2.7, 0.9, strike), k)
			rShR.z -= 0.5 * k
			rElR.x = lerpf(rElR.x, lerpf(1.4, 0.2, strike), k)
			rSpine.x -= 0.15 * strike * (1.0 - back)

		# Zombie attack.
		var at := _n(st.get("attack"))
		if at > 0.0 and at < 1.0:
			var up := Rig.smooth(0, 0.4, at) * (1.0 - Rig.smooth(0.4, 0.6, at))
			var down := Rig.smooth(0.4, 0.6, at) * (1.0 - Rig.smooth(0.75, 1, at))
			rShL.x += 1.1 * up - 0.9 * down
			rShR.x += 1.1 * up - 0.9 * down
			rSpine.x += 0.2 * up - 0.35 * down
			rootScale.y *= 1.0 - 0.08 * up

		# Hurt.
		var hu := hurt
		if hu > 0.0:
			rSpine.x += hu * 0.28
			rHead.x += hu * 0.3
			hipsP.z += hu * 0.06

		# Climb.
		var cl := _n(st.get("climb"))
		if cl > 0.0:
			var c := sin(cl * PI * 6.0)
			rShL = _lerpV(rShL, 2.6 + c * 0.35, 0, 0.2, 1)
			rShR = _lerpV(rShR, 2.6 - c * 0.35, 0, -0.2, 1)
			rHipL.x += maxf(0.0, c) * 1.1
			rKnL.x -= maxf(0.0, c) * 1.4
			rHipR.x += maxf(0.0, -c) * 1.1
			rKnR.x -= maxf(0.0, -c) * 1.4

		# Dance.
		var da := _n(st.get("dance"))
		if da > 0.0:
			var b := sin(tt * PI * 4.0)
			rHips.z += b * 0.12 * da
			hipsP.x += b * 0.04 * da
			rChest.z -= b * 0.1 * da
			rShR.x += (2.6 if b > 0.0 else 0.4) * da * 0.6
			rShR.z -= 0.3 * da
			rKnL.x -= maxf(0.0, b) * 0.4 * da
			rKnR.x -= maxf(0.0, -b) * 0.4 * da

		# Down.
		if Rig.truthy(st.get("down")):
			hipsP.y -= _dLeg * 0.55
			rHipL.x += 1.4
			rKnL.x -= 2.2
			rHipR.x += 0.3
			rKnR.x -= 1.6
			rSpine.x -= 0.35
			rHead.x -= 0.3

		# Head lag springs.
		var headLagP := _pHeadLag
		var wobble := _pWobble
		var lx := _lagX.update(dt, -_bobVel * 0.06 * headLagP)
		var lz := _lagZ.update(dt, -turn * 0.03 * headLagP + (sin(tt * 0.9 + seed) * 0.12 * wobble if wobble != 0.0 else 0.0))
		headLag.x = lx
		headLag.z = lz
		rHead.x += lx
		rHead.z += lz + _wTilt

		# Dead.
		var de := _n(st.get("dead"))
		if de > 0.0:
			rootRot.x = (PI / 2.0) * Rig.easeOutBounce(minf(1.0, de))
			rShL.x = lerpf(rShL.x, 2.6, de)
			rShR.x = lerpf(rShR.x, 2.6, de)

		var ovOn: bool = override is Callable and (override as Callable).is_valid()
		var alignOn: bool = _pAlign and aimW > 0.001 and not (ml > 0.0 and ml < 1.0)
		# rest offsets folded in (nothing reads the joints between the pose and them on this path)
		var restNow: bool = rest and _poses.is_empty() and not ovOn and not alignOn
		var om := 0
		if restNow:
			if restArmOut != 0.0:
				var fl := maxf(0.0, 1.0 - absf(rShL.x) / 1.3)
				var fr := maxf(0.0, 1.0 - absf(rShR.x) / 1.3)
				rShL.z -= restArmOut * fl
				rShR.z += restArmOut * fr
			om = _offMask
		var O := _offV

		# Single write per joint (positions other than the hips only when something else moved them).
		var jn := _jn
		var jb := _jbase
		var R := _rootN
		if R.rotation != rootRot:
			R.rotation = rootRot
		if R.position != Vector3.ZERO:
			R.position = Vector3.ZERO
		R.scale = rootScale
		var n: Node3D = jn[0]
		if n.position != hipsP:
			n.position = hipsP
		n.rotation = rHips if (om & 1) == 0 else rHips + O[0]
		if not posStatic or _posTouched:
			for i in range(1, 17):
				n = jn[i]
				if n.position != jb[i]:
					n.position = jb[i]
		jn[1].rotation = rSpine if (om & 2) == 0 else rSpine + O[1]
		n = jn[2]
		n.rotation = rChest if (om & 4) == 0 else rChest + O[2]
		n.scale = chestScale
		jn[3].rotation = Vector3.ZERO if (om & 8) == 0 else O[3]
		jn[4].rotation = rHead if (om & 16) == 0 else rHead + O[4]
		jn[5].rotation = rShL if (om & 32) == 0 else rShL + O[5]
		jn[6].rotation = rElL if (om & 64) == 0 else rElL + O[6]
		jn[7].rotation = Vector3.ZERO if (om & 128) == 0 else O[7]
		jn[8].rotation = rShR if (om & 256) == 0 else rShR + O[8]
		jn[9].rotation = rElR if (om & 512) == 0 else rElR + O[9]
		jn[10].rotation = Vector3.ZERO if (om & 1024) == 0 else O[10]
		jn[11].rotation = rHipL if (om & 2048) == 0 else rHipL + O[11]
		jn[12].rotation = rKnL if (om & 4096) == 0 else rKnL + O[12]
		jn[13].rotation = rFtL if (om & 8192) == 0 else rFtL + O[13]
		jn[14].rotation = rHipR if (om & 16384) == 0 else rHipR + O[14]
		jn[15].rotation = rKnR if (om & 32768) == 0 else rKnR + O[15]
		jn[16].rotation = rFtR if (om & 65536) == 0 else rFtR + O[16]

		_posTouched = ovOn or alignOn or not _poses.is_empty()
		_applyPoses()
		if alignOn:
			_alignHand(pitch, yaw, rarc)
		if ovOn:
			(override as Callable).call(rig, dt)
		if rest and not restNow:
			CharRuntime.applyRestOffsets(rig.joints, restArmOut, restOffs)

	# The generic path (any rig): reset to rest, then each layer reads and writes the joints.
	func _procSlow(dt: float, st: Dictionary = {}) -> void:
		var J: Dictionary = rig.joints
		var D: Dictionary = rig.dims
		t += dt
		var tt := t
		var speed := Rig.num(st.get("speed"))
		var gv = st.get("grounded", true)
		var grounded: bool = not (gv is bool and gv == false)
		var dn := 1.0 - exp(-dt * 10.0)

		# Reset joints to rest.
		for e in rig.base:
			e[0].position = e[1]
			e[0].rotation = Vector3.ZERO
		rig.root.rotation = Vector3.ZERO
		rig.root.position = Vector3.ZERO
		J.chest.scale = Vector3.ONE

		# Eased blend weights.
		var moving := clampf(speed / 1.2, 0.0, 1.0) if grounded else 0.0
		move += (moving - move) * dn
		run += (clampf(speed / 4.6, 0.0, 1.5) - run) * dn
		aimW += ((1.0 if Rig.truthy(st.get("aiming")) else 0.0) - aimW) * (1.0 - exp(-dt * 14.0))
		air += ((0.0 if grounded else 1.0) - air) * (1.0 - exp(-dt * 12.0))
		var w := move
		var rn := run
		var ai := air

		# Landing / takeoff squash-stretch (GDD §3.6: 0.85 y / 1.1 xz over ~120 ms).
		if grounded and not _grounded:
			squash.kick(-3.4)
		if not grounded and _grounded:
			squash.kick(1.8)
		_grounded = grounded
		var hurt := Rig.num(st.get("hurt"))
		if hurt > _hurt + 0.3:
			squash.kick(-2.6)
			_lagX.kick(-5)
		_hurt = hurt

		# Gait phase.
		var cycle: float = (float(p.cycle) + float(p.cycleK) * speed) / float(wob.speed)
		phase += (-1.0 if Rig.truthy(st.get("back")) else 1.0) * dt * (speed / cycle) * PI * 2.0 * (1.0 if grounded else 0.25)
		var ph := phase
		var sn := sin(ph)
		var cs := cos(ph)

		# Legs.
		var legA: float = (float(p.legSwing) + float(p.legRun) * rn) * w * float(wob.amp)
		var kneeA: float = (float(p.knee) + 0.9 * rn) * w
		J.hipL.rotation.x = sn * legA
		J.hipR.rotation.x = -sn * legA
		J.kneeL.rotation.x = -(0.08 + maxf(0.0, cs) * kneeA) - 0.06 * w
		J.kneeR.rotation.x = -(0.08 + maxf(0.0, -cs) * kneeA) - 0.06 * w
		J.footL.rotation.x = -(J.hipL.rotation.x + J.kneeL.rotation.x) * 0.7
		J.footR.rotation.x = -(J.hipR.rotation.x + J.kneeR.rotation.x) * 0.7

		# Body bounce: highest when the legs pass, lowest (squashed) at footfall.
		var pass_ := pow(absf(cs), 0.7)
		var bob: float = w * float(p.bob) * (0.6 + rn * 0.6) * (pass_ - 0.5)
		J.hips.position.y += bob
		_bobVel = (bob - _prevBob) / maxf(dt, 1e-4)
		_prevBob = bob
		var contact := pow(1.0 - absf(cs), 5.0) * w
		var sq := squash.update(dt, 0.0)
		var sy: float = 1.0 + sq - contact * float(p.squash)
		rig.root.scale = Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))

		# Torso: lean, counter-twist, waddle.
		var lean: float = p.lean
		var sway: float = p.sway
		var twist: float = p.twist
		J.spine.rotation.x = -(0.03 + lean * (0.4 + rn)) * w - (lean * 0.6 if p.arms == "forward" else 0.0)
		var turn := Rig.num(st.get("turn"))
		J.spine.rotation.z = clampf(-turn * 0.05, -0.2, 0.2) + cs * sway * w * 0.5
		J.hips.rotation.y = -sn * twist * 0.6 * w
		J.chest.rotation.y = sn * twist * w * (0.5 + rn)
		J.hips.rotation.z = cs * sway * w
		# Strafe: legs face the movement, the upper body counter-rotates to keep facing the aim.
		var legYaw := Rig.num(st.get("legYaw")) * w
		J.hips.rotation.y += legYaw
		J.spine.rotation.y -= legYaw
		var breatheP: float = p.breathe
		var breathe := 1.0 + breatheP + breatheP * sin(tt * PI * 2.0 * 0.3)
		J.chest.scale = Vector3(1.0 + (breathe - 1.0) * 0.5, breathe, 1.0 + (breathe - 1.0) * 0.7)

		# Arms.
		var armA: float = (float(p.arm) + float(p.armRun) * rn) * w
		if p.arms == "forward":
			var sw := sin(tt * 1.4 * float(wob.speed) + seed) * 0.12
			J.shoulderL.rotation = Vector3(PI / 2.0 - 0.22 + sw + sn * armA + float(wob.armL), 0, 0.12)
			J.shoulderR.rotation = Vector3(PI / 2.0 - 0.22 - sw - sn * armA + float(wob.armR), 0, -0.12)
			J.elbowL.rotation.x = 0.12 + sin(tt * 2.1 + seed) * 0.08
			J.elbowR.rotation.x = 0.12 + cos(tt * 2.3 + seed) * 0.08
		else:
			var flop := sin(tt * 5.0 + seed) * 0.25 if p.arms == "floppy" else 0.0
			J.shoulderL.rotation = Vector3(-sn * armA + flop, 0, 0.1 + 0.05 * (1.0 - w))
			J.shoulderR.rotation = Vector3(sn * armA - flop, 0, -0.1 - 0.05 * (1.0 - w))
			var elbow: float = p.elbow
			J.elbowL.rotation.x = 0.15 + (elbow + rn * 0.5) * w + maxf(0.0, -sn) * 0.3 * w
			J.elbowR.rotation.x = 0.15 + (elbow + rn * 0.5) * w + maxf(0.0, sn) * 0.3 * w
			# Idle: arms drift a little.
			var idle := (1.0 - w) * sin(tt * 1.9) * 0.03
			J.shoulderL.rotation.x += idle
			J.shoulderR.rotation.x -= idle

		# Air pose: tuck legs, arms out.
		if ai > 0.01:
			J.hipL.rotation.x += 0.55 * ai
			J.kneeL.rotation.x -= 0.9 * ai
			J.hipR.rotation.x += 0.15 * ai
			J.kneeR.rotation.x -= 0.45 * ai
			J.shoulderL.rotation.z += 0.45 * ai
			J.shoulderR.rotation.z -= 0.45 * ai

		# Aiming: weapon forward with both hands, pitch with the view, upper-body twist.
		var pitch := Rig.num(st.get("aimPitch"))
		var yaw := Rig.num(st.get("aimYaw"))
		J.spine.rotation.y += yaw
		if aimW > 0.001:
			var a := aimW
			var lift := pitch * 0.85
			Rig.lerpRot(J.shoulderR, PI / 2.0 + lift - 0.28, 0, -0.05, a)
			J.elbowR.rotation.x = lerpf(J.elbowR.rotation.x, 0.3, a)
			Rig.lerpRot(J.shoulderL, PI / 2.0 + lift - 0.55, 0, 0.62, a)
			J.elbowL.rotation.x = lerpf(J.elbowL.rotation.x, 0.85, a)
			J.chest.rotation.x += pitch * 0.25 * a
		J.head.rotation.x += pitch * 0.35 + (1.0 - aimW) * 0.04
		J.head.rotation.y += yaw * 0.25

		# Recoil / reload / melee layers.
		var rec := Rig.num(st.get("recoil"))
		if rec > 0.0:
			J.chest.rotation.x += rec * 0.1
			J.shoulderR.rotation.x += rec * 0.35
			J.shoulderL.rotation.x += rec * 0.25
		var rl := Rig.num(st.get("reload"))
		var rarc := sin(PI * rl) if rl > 0.0 and rl < 1.0 else 0.0
		if rarc > 0.0:
			J.shoulderL.rotation.x -= rarc * 1.0
			J.elbowL.rotation.x += rarc * 0.6
			J.shoulderR.rotation.x -= rarc * 0.35
			J.head.rotation.x -= rarc * 0.25
		var ml := Rig.num(st.get("melee"))
		if ml > 0.0 and ml < 1.0:
			var wind := Rig.smooth(0, 0.25, ml)
			var strike := Rig.smooth(0.25, 0.45, ml)
			var back := Rig.smooth(0.55, 1, ml)
			var k := wind * (1.0 - back)
			J.chest.rotation.y += (0.45 * wind - 0.9 * strike) * (1.0 - back)
			J.shoulderR.rotation.x = lerpf(J.shoulderR.rotation.x, lerpf(2.7, 0.9, strike), k)
			J.shoulderR.rotation.z -= 0.5 * k
			J.elbowR.rotation.x = lerpf(J.elbowR.rotation.x, lerpf(1.4, 0.2, strike), k)
			J.spine.rotation.x -= 0.15 * strike * (1.0 - back)

		# Zombie attack: arms rise (anticipation), squash, then swipe down.
		var at := Rig.num(st.get("attack"))
		if at > 0.0 and at < 1.0:
			var up := Rig.smooth(0, 0.4, at) * (1.0 - Rig.smooth(0.4, 0.6, at))
			var down := Rig.smooth(0.4, 0.6, at) * (1.0 - Rig.smooth(0.75, 1, at))
			J.shoulderL.rotation.x += 1.1 * up - 0.9 * down
			J.shoulderR.rotation.x += 1.1 * up - 0.9 * down
			J.spine.rotation.x += 0.2 * up - 0.35 * down
			rig.root.scale.y *= 1.0 - 0.08 * up

		# Hurt: lean back, stagger.
		var hu := hurt
		if hu > 0.0:
			J.spine.rotation.x += hu * 0.28
			J.head.rotation.x += hu * 0.3
			J.hips.position.z += hu * 0.06

		# Climb (windows/fences): alternating reach.
		var cl := Rig.num(st.get("climb"))
		if cl > 0.0:
			var c := sin(cl * PI * 6.0)
			Rig.lerpRot(J.shoulderL, 2.6 + c * 0.35, 0, 0.2, 1)
			Rig.lerpRot(J.shoulderR, 2.6 - c * 0.35, 0, -0.2, 1)
			J.hipL.rotation.x += maxf(0.0, c) * 1.1
			J.kneeL.rotation.x -= maxf(0.0, c) * 1.4
			J.hipR.rotation.x += maxf(0.0, -c) * 1.1
			J.kneeR.rotation.x -= maxf(0.0, -c) * 1.4

		# Dance (disco): hip sway and alternating point.
		var da := Rig.num(st.get("dance"))
		if da > 0.0:
			var b := sin(tt * PI * 4.0)
			J.hips.rotation.z += b * 0.12 * da
			J.hips.position.x += b * 0.04 * da
			J.chest.rotation.z -= b * 0.1 * da
			J.shoulderR.rotation.x += (2.6 if b > 0.0 else 0.4) * da * 0.6
			J.shoulderR.rotation.z -= 0.3 * da
			J.kneeL.rotation.x -= maxf(0.0, b) * 0.4 * da
			J.kneeR.rotation.x -= maxf(0.0, -b) * 0.4 * da

		# Down: kneel and slump.
		if Rig.truthy(st.get("down")):
			J.hips.position.y -= float(D.leg) * 0.55
			J.hipL.rotation.x += 1.4
			J.kneeL.rotation.x -= 2.2
			J.hipR.rotation.x += 0.3
			J.kneeR.rotation.x -= 1.6
			J.spine.rotation.x -= 0.35
			J.head.rotation.x -= 0.3

		# Secondary motion: the head lags the torso on springs (60 ms feel) and exposes the lag for hair.
		var headLagP: float = p.headLag
		var wobble: float = p.wobble
		var lx := _lagX.update(dt, -_bobVel * 0.06 * headLagP)
		var lz := _lagZ.update(dt, -turn * 0.03 * headLagP + (sin(tt * 0.9 + seed) * 0.12 * wobble if wobble != 0.0 else 0.0))
		headLag.x = lx
		headLag.z = lz
		J.head.rotation.x += lx
		J.head.rotation.z += lz + float(wob.tilt)

		# Dead: topple backward with a bounce.
		var de := Rig.num(st.get("dead"))
		if de > 0.0:
			rig.root.rotation.x = (PI / 2.0) * Rig.easeOutBounce(minf(1.0, de))
			J.shoulderL.rotation.x = lerpf(J.shoulderL.rotation.x, 2.6, de)
			J.shoulderR.rotation.x = lerpf(J.shoulderR.rotation.x, 2.6, de)

		_applyPoses()
		if Rig.truthy(p.alignHand) and aimW > 0.001 and not (ml > 0.0 and ml < 1.0):
			_alignHand(pitch, yaw, rarc)
		if override is Callable and (override as Callable).is_valid():
			(override as Callable).call(rig, dt)

	func _applyPoses() -> void:
		if _poses.is_empty():
			return
		var J: Dictionary = rig.joints
		for name in _poses:
			var weight: float = _poses[name]
			var pose = Rig.POSES.get(name)
			if pose == null:
				continue
			if weight >= 0.5 and Rig.POSE_HANDS.has(name):
				var hs: Dictionary = Rig.POSE_HANDS[name]
				for side in hs:
					hand(side, hs[side])
			for jn in pose:
				var obj = J.get(jn)
				if obj == null:
					continue
				var r: Array = pose[jn]
				var q := Rig.quatXYZ(r[0], r[1], r[2]) if Rig._eOrder == "XYZ" else Rig.quatYXZ(r[0], r[1], r[2])
				obj.quaternion = Rig.slerp(Rig.quatOf(obj), q, minf(1.0, weight))

	# Orient handR so the held weapon points exactly along the aim (whatever the arm pose).
	func _alignHand(pitch: float, yaw: float, reloadArc: float) -> void:
		var J: Dictionary = rig.joints
		var root: Node3D = rig.root
		var rq := Rig.worldQuat(root)
		# World quaternion of handR's parent (elbowR) through the joint chain.
		var q2 := rq * Rig.quatOf(J.hips) * Rig.quatOf(J.spine) * Rig.quatOf(J.chest) * Rig.quatOf(J.shoulderR) * Rig.quatOf(J.elbowR)
		# Target: body yaw (root) + aim yaw, view pitch, with a reload roll.
		Rig._eOrder = "YXZ"
		var q := rq * Rig.quatYXZ(pitch, yaw, -reloadArc * 0.7)
		var target := Rig._conj(q2) * q
		J.handR.quaternion = Rig.slerp(Rig.quatOf(J.handR), target, aimW)


# Base of the custom animators of character definitions (createAnimator): `updateFn` (dt, st) does the work.
class FnAnimator extends RefCounted:
	var rig
	var override = null
	var updateFn: Callable = Callable()
	var kickFn: Callable = Callable()
	var postUpdate: Array = []

	var stamp := -1                       # process frame of the last update() (CharSkeleton lazy sync)

	func update(dt: float, st: Dictionary = {}) -> void:
		stamp = Engine.get_process_frames()
		if updateFn.is_valid():
			updateFn.call(dt, st)
		for fn in postUpdate:
			if fn is Callable and (fn as Callable).is_valid():
				(fn as Callable).call(rig, dt)

	func kick(amount: float = 1.0) -> void:
		if kickFn.is_valid():
			kickFn.call(amount)
