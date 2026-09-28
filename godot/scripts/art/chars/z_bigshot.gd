# Z_BIGSHOT — BIG SHOT, the camera operator fused with his studio pedestal (GDD §8.4, STYLE_GUIDE §7): runtime half
# of src/art/chars/z_bigshot.js (sculpt / bake half, casters, tally, lensFront: blender/chars -> z_bigshot.glb). The
# trailing cable + glowing plug (his weak point) are built at runtime by actors/types/big_shot.gd.
# Custom skeleton: base (root) -> column -> torso -> head, torso -> shoulderL/R -> elbowL/R -> handL/R.
# Attachment tags: userData.wheel (caster wheels, spin about local x), userData.caster (swivel forks),
# userData.tally (the red tally lamp mesh), userData.staticEye (eyes), 'lensFront' (node at the lens glass centre,
# -z out of the lens) for the runtime iris / flash.
extends RefCounted

const HEAD_Y := 1.5
# Head-local static eyes on the camera's front face (the housing front is at z = -0.27)
const EYES := [
	{"x": 0.098, "y": 0.405, "z": -0.268, "r": 0.056, "pitch": 0.0, "yaw": -0.12, "lid": 0.34, "droop": 0.22, "depth": 0.6},
	{"x": -0.1, "y": 0.4, "z": -0.268, "r": 0.062, "pitch": 0.0, "yaw": 0.12, "lid": 0.28, "droop": 0.2, "depth": 0.6},
]
const LENS := {"y": 1.705, "r": 0.112, "z0": -0.26, "z1": -0.54}

static func casters() -> Array:
	var out := []
	for i in 3:
		var a := PI + (i * PI * 2.0) / 3.0
		out.append([sin(a) * 0.4, cos(a) * 0.4])
	return out

static func def() -> Dictionary:
	return {
		"id": "z_bigshot",
		"name": "Big Shot",
		"kind": "zombie",
		"rig": {
			"custom": true,
			"joints": [
				{"name": "base", "parent": null, "pos": [0, 0, 0], "tail": [0, 0.2, 0], "blend": 0.03, "gate": 0.5},
				{"name": "column", "parent": "base", "pos": [0, 0.2, 0], "tail": [0, 0.72, 0], "blend": 0.03, "gate": 0.2},
				{"name": "torso", "parent": "column", "pos": [0, 0.74, 0], "tail": [0, 0.5, 0], "blend": 0.06, "gate": 0.35},
				{"name": "head", "parent": "torso", "pos": [0, 0.56, 0], "tail": [0, 0.28, -0.3], "blend": 0.03, "gate": 0.3},
				{"name": "shoulderL", "parent": "torso", "pos": [-0.3, 0.42, 0.02], "blend": 0.07, "gate": 0.13},
				{"name": "elbowL", "parent": "shoulderL", "pos": [-0.08, -0.22, -0.1], "blend": 0.06, "gate": 0.11},
				{"name": "handL", "parent": "elbowL", "pos": [0.06, -0.04, -0.22], "tail": [0, 0, -0.08], "blend": 0.04, "gate": 0.1},
				{"name": "shoulderR", "parent": "torso", "pos": [0.3, 0.42, 0.02], "blend": 0.07, "gate": 0.13},
				{"name": "elbowR", "parent": "shoulderR", "pos": [0.08, -0.22, -0.1], "blend": 0.06, "gate": 0.11},
				{"name": "handR", "parent": "elbowR", "pos": [-0.06, -0.04, -0.22], "tail": [0, 0, -0.08], "blend": 0.04, "gate": 0.1},
			],
			"bindPose": {},
			"dims": {"height": 2.2, "headH": 0.5},
		},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
		"slots": {"head": {"joint": "head", "pos": [0, 0.58, -0.12]}, "handL": {"joint": "handL", "pos": [0, 0, 0]}, "handR": {"joint": "handR", "pos": [0, 0, 0]}},
	}

static func _findWheels(root: Node, out: Array) -> void:
	DAU.traverse(root, func(o):
		if o.has_meta("userData") and DAU.ud(o).get("wheel"):
			out.append(o))

# Preview animator (charview): gentle idle; speed > 0 rolls the casters. The game drives joints itself.
static func createAnimator(rig, _ctx = null) -> Rig.FnAnimator:
	var J: Dictionary = rig.joints
	var S := {"t": randf() * 10.0}
	var wheels := []
	_findWheels(rig.root, wheels)
	var a := Rig.FnAnimator.new()
	a.rig = rig
	a.updateFn = func(dt: float, st: Dictionary) -> void:
		S.t += dt
		var t: float = S.t
		if wheels.is_empty():
			_findWheels(rig.root, wheels)
		for w in wheels:
			w.rotation.x -= Rig.num(st.get("speed")) * dt / 0.062
		J.torso.rotation.z = sin(t * 1.3) * 0.03
		J.torso.rotation.x = sin(t * 0.9) * 0.02 - (0.05 if Rig.truthy(st.get("speed")) else 0.0)
		J.head.rotation.x = sin(t * 1.1 + 1.0) * 0.03
		J.head.rotation.y = sin(t * 0.7) * 0.06
	return a

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYES": EYES}
