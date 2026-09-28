# SKIP KOWALSKI — runtime half of src/art/chars/skip.js (the sculpt / bake half is blender/chars -> skip.glb).
extends RefCounted

# Head-local anchors (origin = head joint, y up, -z forward), in sculpt units (the head attachments hang in a group
# scaled by HS about the head joint). EYE_DEFAULTS merged in.
const EYE := {
	"x": 0.063, "y": 0.232, "z": -0.13, "r": 0.044, "iris": "#8A4E24", "irisSize": 0.64, "pupilSize": 0.44, "sclera": "#FBF6EE",
	"lid": "#F2B792", "lash": "#2A1A14", "lidOpen": 1.0, "lowerLid": 0.6, "tilt": 0, "lidScale": 1.04, "yaw": 0.07, "glint": 1.15,
}
const HS := 1.1

static func def() -> Dictionary:
	return {
		"id": "skip",
		"name": "Skip Kowalski",
		"kind": "hero",
		# 1.60 m kid: headScale 1.3 like Duke (head + cap ~0.56 m = 2.9 heads tall), short chunky torso, long legs.
		"rig": {"height": 1.60, "headScale": 1.3, "shoulderW": 0.36, "hipW": 0.23, "legLen": 0.74, "torsoLen": 0.38, "armLen": 0.5},
		"armOut": 0.2,
		"poseOffset": {"hipL": [0, 0, -0.04], "hipR": [0, 0, 0.04], "footL": [0, 0, 0.04], "footR": [0, 0, -0.04]},
		"rim": {"color": "#FFD9A0", "strength": 0.4},
		"expressions": ["smile", "frown", "o_mouth"],
	}

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYE": EYE}
