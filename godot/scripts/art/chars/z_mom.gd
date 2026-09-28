# TUNED-IN: AUDIENCE MOM — runtime half of src/art/chars/z_mom.js (sculpt / bake half + cat-eye glasses:
# blender/chars -> z_mom.glb).
extends RefCounted

# Head-local anchors (origin = head joint; y up, -z forward).
const EYES := [
	{"x": 0.074, "y": 0.276, "z": -0.142, "r": 0.058, "pitch": 0.06, "yaw": -0.3, "lid": 0.4, "droop": 0.2, "depth": 0.7},
	{"x": -0.072, "y": 0.28, "z": -0.142, "r": 0.061, "pitch": 0.06, "yaw": 0.3, "lid": 0.34, "droop": 0.16, "depth": 0.7},
]

# Lip ring with a soft cupid's bow on top (wider than tall): a lipstick pout, not a donut.
static func heartLips(rx: float, ry: float, n: int = 28) -> Array:
	var pts := []
	for i in range(0, n + 3):
		var a := (float(i) / n) * PI * 2.0
		var c := cos(a)
		var sn := sin(a)
		var bow := 1.0 - 0.28 * exp(-pow(c / 0.28, 2)) + 0.12 * exp(-pow((absf(c) - 0.45) / 0.25, 2)) if sn > 0.0 else 1.05
		pts.append([c * rx, sn * ry * bow, 0])
	return pts

# Puffy lipstick "O" (the lip ring is repainted with the lipstick material), 3 teeth.
static func mouth() -> Dictionary:
	return {
		"pos": [0.002, 0.128, -0.164], "pitch": 0.36, "roll": -0.06, "r": 0.0115, "lipPts": heartLips(0.036, 0.024), "open": [0.028, 0.017],
		"teeth": [
			{"x": -0.0105, "y": 0.0105, "w": 0.0092, "h": 0.0098, "rot": 0.06},
			{"x": 0.0105, "y": 0.011, "w": 0.0092, "h": 0.01, "rot": -0.08},
			{"x": -0.004, "y": -0.0125, "w": 0.0082, "h": 0.0072, "rot": -0.1, "z": 0.004},
		],
		"tongue": {"pts": [[-0.012, -0.009, 0.018], [0.0, -0.008, 0.012], [0.011, -0.01, 0.018]], "r": 0.009, "flat": 0.5},
	}

static func def() -> Dictionary:
	return {
		"id": "z_mom",
		"name": "Tuned-In: Audience Mom",
		"kind": "zombie",
		"rig": {"height": 1.56, "headScale": 1.34, "shoulderW": 0.42, "hipW": 0.29, "legLen": 0.66, "torsoLen": 0.5, "armLen": 0.62},
		"armOut": 0.1,
		# hunched, head tilted (the beehive leans), right arm reaching, left forearm (with the bag) lower
		"poseOffset": {
			"spine": [-0.12, 0, 0.03], "chest": [-0.08, -0.06, 0], "neck": [-0.1, 0, 0], "head": [0.3, 0.05, -0.12],
			"shoulderL": [-0.1, 0, 0.04], "shoulderR": [0.14, 0, -0.03], "elbowL": [0.18, 0, 0], "elbowR": [0.08, 0, 0],
			"handL": [-0.35, 0, 0.1], "handR": [-0.45, 0, 0],
		},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
	}

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYES": EYES, "MOUTH": mouth()}
