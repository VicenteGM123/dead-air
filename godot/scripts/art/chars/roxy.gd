# ROXY RIVERS — runtime half of src/art/chars/roxy.js (the sculpt / bake half is blender/chars -> roxy.glb).
extends RefCounted

# Head-local anchors (origin = head joint, y up, -z forward). EYE_DEFAULTS merged in.
const EYE := {
	"x": 0.064, "y": 0.228, "z": -0.128, "r": 0.046, "iris": "#8A4A22", "irisSize": 0.64, "pupilSize": 0.44, "sclera": "#FBF6EE",
	"lid": "#8E5637", "lash": "#160D0A", "lidOpen": 0.98, "lowerLid": 0.62, "lidScale": 1.04, "yaw": 0.07, "glint": 1.15, "tilt": 0.05,
}
const HS := 1.06

static func def() -> Dictionary:
	return {
		"id": "roxy",
		"name": "Roxy Rivers",
		"kind": "hero",
		# 1.70 m (+ the afro): headScale 1.3 like Duke, long dancer legs, short torso with a bare midriff.
		"rig": {"height": 1.70, "headScale": 1.3, "shoulderW": 0.36, "hipW": 0.25, "legLen": 0.84, "torsoLen": 0.44, "armLen": 0.55},
		"armOut": 0.2,
		# head costume slot on top of the afro (the puffs are a part, not counted by the runtime's hair scan)
		"slots": {"head": [0, 0.745, 0.05]},
		"poseOffset": {"hipL": [0, 0, -0.05], "hipR": [0, 0, 0.05], "footL": [0, 0, 0.05], "footR": [0, 0, -0.05]},
		"rim": {"color": "#FFD9A0", "strength": 0.45},
		"expressions": ["smile", "frown", "o_mouth"],
	}

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYE": EYE}
