# DUKE DALTON — runtime half of src/art/chars/duke.js (default hero). The sculpt / bake half (shapes, materials,
# parts, attachments geometry) is blender/chars (exported to godot/assets/chars/duke.glb); this file keeps what the
# JS runtime reads from the definition: id, name, kind, rig spec, armOut, poseOffset, rim, anchors, expressions.
extends RefCounted

# Head-local anchors (origin = head joint, y up, -z forward). EYE_DEFAULTS (chars/_face.js) merged in.
const EYE := {
	"x": 0.066, "y": 0.25, "z": -0.14, "r": 0.046, "iris": "#6A3C1C", "irisSize": 0.6, "pupilSize": 0.46, "sclera": "#FBF6EE",
	"lid": "#F3B590", "lash": "#2A1A14", "lidOpen": 1.0, "lowerLid": 0.6, "tilt": 0, "lidScale": 1.04, "yaw": 0.07, "glint": 1.1,
}

static func def() -> Dictionary:
	return {
		"id": "duke",
		"name": "Duke Dalton",
		"kind": "hero",
		# headScale 1.3 = 3 heads tall (STYLE_GUIDE §1). src/actors/heroes.js + GDD §4 must use the same spec.
		"rig": {"height": 1.80, "headScale": 1.3, "shoulderW": 0.44, "hipW": 0.27, "legLen": 0.82, "torsoLen": 0.46, "armLen": 0.55},
		"armOut": 0.22,
		"poseOffset": {"hipL": [0, 0, -0.045], "hipR": [0, 0, 0.045], "footL": [0, 0, 0.045], "footR": [0, 0, -0.045]},
		"rim": {"color": "#FFD9A0", "strength": 0.4},
		"anchors": func(_ctx): return {"EYE": EYE},
		"expressions": ["smile", "frown", "o_mouth"],
	}
