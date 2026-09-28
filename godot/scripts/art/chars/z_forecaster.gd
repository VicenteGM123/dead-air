# THE FORECASTER — runtime half of src/art/chars/z_forecaster.js (sculpt / bake half incl. the rigid 'cloud' part:
# blender/chars -> z_forecaster.glb). src/actors/types/forecaster.js builds it with its own Animator style.
extends RefCounted

# Head-local anchors (origin = head joint; y up, -z forward)
const EYES := [
	{"x": 0.074, "y": 0.31, "z": -0.152, "r": 0.052, "pitch": 0.02, "yaw": -0.3, "lid": 0.32, "droop": 0.22, "depth": 0.7},
	{"x": -0.072, "y": 0.314, "z": -0.153, "r": 0.058, "pitch": 0.04, "yaw": 0.3, "lid": 0.26, "droop": 0.18, "depth": 0.7},
]
const MOUTH := {"y": 0.128, "z": -0.176, "w": 0.118, "h": 0.056, "top": 0.148, "R": 0.24}
const CLOUD_Y := 0.6     # cloud centre above the top of the pompadour (world: head joint + ~0.62 + 0.6)

static func def() -> Dictionary:
	return {
		"id": "z_forecaster",
		"name": "The Forecaster",
		"kind": "zombie",
		"rig": {"height": 1.74, "headScale": 1.45, "shoulderW": 0.47, "hipW": 0.28, "legLen": 0.8, "torsoLen": 0.5, "armLen": 0.64},
		"armOut": 0.16,
		"poseOffset": {"spine": [-0.04, 0, 0], "head": [0.06, 0, 0], "hipL": [0, 0, -0.03], "hipR": [0, 0, 0.03]},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
	}

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYES": EYES}
