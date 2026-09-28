# TUNED-IN: DISCO TEEN — runtime half of src/art/chars/z_disco.js (sculpt / bake half: blender/chars -> z_disco.glb).
extends RefCounted

# Head-local anchors (origin = head joint; y up, -z forward). Droopy, mismatched (right eye bigger).
const EYES := [
	{"x": 0.071, "y": 0.282, "z": -0.128, "r": 0.062, "pitch": 0.06, "yaw": -0.3, "lid": 0.38, "droop": 0.22, "depth": 0.7},
	{"x": -0.068, "y": 0.276, "z": -0.13, "r": 0.054, "pitch": 0.06, "yaw": 0.28, "lid": 0.44, "droop": 0.16, "depth": 0.7},
]

static func lipLoop(rx: float, ry: float, n: int = 22) -> Array:
	var pts := []
	for i in range(0, n + 3):
		var a := (float(i) / n) * PI * 2.0
		pts.append([cos(a) * rx, sin(a) * ry, 0])
	return pts

# Open "O" mouth, 3 big square teeth (GDD §8.1): two up top with a gap, one below.
static func mouth() -> Dictionary:
	return {
		"pos": [-0.004, 0.142, -0.158], "pitch": 0.4, "roll": 0.08, "r": 0.015, "lipPts": lipLoop(0.044, 0.037), "open": [0.037, 0.032],
		"teeth": [
			{"x": -0.013, "y": 0.017, "w": 0.0105, "h": 0.0135, "rot": 0.08},
			{"x": 0.012, "y": 0.0175, "w": 0.0105, "h": 0.013, "rot": -0.1},
			{"x": 0.002, "y": -0.021, "w": 0.0095, "h": 0.0095, "rot": 0.06, "z": 0.004},
		],
		"tongue": {"pts": [[-0.014, -0.014, 0.018], [0.0, -0.012, 0.012], [0.013, -0.015, 0.018]], "r": 0.012, "flat": 0.5},
	}

static func def() -> Dictionary:
	var MOUTH := mouth()
	return {
		"id": "z_disco",
		"name": "Tuned-In: Disco Teen",
		"kind": "zombie",
		"rig": {"height": 1.54, "headScale": 1.3, "shoulderW": 0.38, "hipW": 0.25, "legLen": 0.86, "torsoLen": 0.44, "armLen": 0.64},
		"armOut": 0.1,
		# hunch + head pushed forward (chin up: the chin is the gag) + a disco hip pop; right arm locked in the point
		# (added on top of the zombie arms-forward pose), left arm reaching lower.
		"poseOffset": {
			"spine": [-0.08, 0, -0.05], "chest": [-0.07, 0.1, 0.03], "neck": [-0.08, 0, 0], "head": [0.26, -0.08, 0.1],
			"hips": [0, 0, 0.06],
			"shoulderR": [1.5, 0, 0.76], "elbowR": [0.2, 0, 0], "handR": [0.12, 0, 0],
			"shoulderL": [-0.08, 0, 0.02], "elbowL": [0.1, 0, 0], "handL": [-0.45, 0, 0],
			"hipL": [0, 0, -0.07], "hipR": [0, 0, 0.06], "footL": [0, 0, 0.07], "footR": [0, 0, -0.06],
		},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
		"anchors": func(_ctx): return {"EYES": EYES, "MOUTH": MOUTH},
	}
