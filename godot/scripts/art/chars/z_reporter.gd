# TUNED-IN: FIELD REPORTER — runtime half of src/art/chars/z_reporter.js (sculpt / bake half: blender/chars ->
# z_reporter.glb).
extends RefCounted

const HEAD_DY := -0.04   # the whole head sits a bit lower on the (long) neck than the rig's head joint

# Head-local anchors (origin = head joint; y up, -z forward).
const EYES := [
	{"x": 0.073, "y": 0.334, "z": -0.141, "r": 0.056, "pitch": 0.03, "yaw": -0.34, "lid": 0.4, "droop": 0.26, "depth": 0.72},
	{"x": -0.07, "y": 0.34, "z": -0.142, "r": 0.064, "pitch": 0.05, "yaw": 0.32, "lid": 0.3, "droop": 0.2, "depth": 0.72},
]

static func lipLoop(rx: float, ry: float, n: int = 22) -> Array:
	var pts := []
	for i in range(0, n + 3):
		var a := (float(i) / n) * PI * 2.0
		pts.append([cos(a) * rx, sin(a) * ry * (0.9 if sin(a) > 0.0 else 1.1), 0])
	return pts

static func mouth() -> Dictionary:
	return {
		"pos": [0.008, 0.152, -0.158], "pitch": 0.28, "roll": -0.12, "r": 0.0135, "lipPts": lipLoop(0.047, 0.026), "open": [0.04, 0.02],
		"teeth": [
			{"x": -0.017, "y": 0.013, "w": 0.0115, "h": 0.012, "rot": 0.1},
			{"x": 0.011, "y": 0.0125, "w": 0.0105, "h": 0.0115, "rot": -0.18},
		],
		"tongue": {"pts": [[-0.004, -0.002, 0.014], [-0.002, -0.014, -0.008], [0.004, -0.036, -0.02], [0.008, -0.056, -0.016]], "r": [0.015, 0.018, 0.02, 0.016], "flat": 0.45},
	}

static func def() -> Dictionary:
	var MOUTH := mouth()
	return {
		"id": "z_reporter",
		"name": "Tuned-In: Field Reporter",
		"kind": "zombie",
		"rig": {"height": 1.68, "headScale": 1.4, "shoulderW": 0.4, "hipW": 0.27, "legLen": 0.9, "torsoLen": 0.48, "armLen": 0.7},
		"armOut": 0.1,
		"poseOffset": {"spine": [-0.06, 0, 0], "chest": [-0.06, 0, 0], "head": [0.16, 0, -0.1], "handL": [-0.5, 0, 0], "handR": [-0.35, 0, 0]},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
		"anchors": func(_ctx): return {"EYES": EYES, "MOUTH": MOUTH},
	}
