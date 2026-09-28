# PENNY WATTS — runtime half of src/art/chars/penny.js (the sculpt / bake half is blender/chars -> penny.glb).
extends RefCounted

# Head-local anchors (origin = head joint, y up, -z forward). EYE_DEFAULTS merged in.
const EYE := {
	"x": 0.064, "y": 0.228, "z": -0.128, "r": 0.045, "iris": "#9A5626", "irisSize": 0.66, "pupilSize": 0.44, "sclera": "#FBF6EE",
	"lid": "#F0B08E", "lash": "#1E120E", "lidOpen": 1.0, "lowerLid": 0.62, "lidScale": 1.04, "yaw": 0.07, "glint": 1.15, "tilt": 0.03,
}
const HS := 1.06

static func def() -> Dictionary:
	return {
		"id": "penny",
		"name": "Penny Watts",
		"kind": "hero",
		# 1.68 m: headScale 1.3 like Duke; long legs in tights, short torso under the turtleneck.
		"rig": {"height": 1.68, "headScale": 1.3, "shoulderW": 0.36, "hipW": 0.25, "legLen": 0.84, "torsoLen": 0.44, "armLen": 0.55},
		"armOut": 0.22,
		"poseOffset": {"hipL": [0, 0, -0.04], "hipR": [0, 0, 0.04], "footL": [0, 0, 0.04], "footR": [0, 0, -0.04]},
		"rim": {"color": "#FFD9A0", "strength": 0.4},
		"expressions": ["smile", "frown", "o_mouth"],
	}

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYE": EYE}
