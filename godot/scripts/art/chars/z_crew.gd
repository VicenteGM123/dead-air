# TUNED-IN: WZTV CREW — runtime half of src/art/chars/z_crew.js (the sculpt / bake half, ZOMBIE_MATS, the static-eye
# / ticket / patch attachments are blender/chars -> z_crew.glb). Zombie kind: cyan rim, LAYERS.ZOMBIES, 'zombie' gait.
extends RefCounted

# Head-local anchors (origin = head joint = top of the neck; y up, -z forward). Eyes kept inside the head silhouette
# (moderate yaw) with a droopy upper lid covering >= 1/3 of each disc.
const EYES := [
	{"x": 0.088, "y": 0.3, "z": -0.151, "r": 0.066, "pitch": 0.12, "yaw": -0.3, "lid": 0.36, "droop": 0.2, "depth": 0.7},
	{"x": -0.082, "y": 0.296, "z": -0.153, "r": 0.054, "pitch": 0.1, "yaw": 0.28, "lid": 0.42, "droop": 0.14, "depth": 0.7},
]
const MOUTH := {
	"pos": [0, 0.094, -0.174], "pitch": 0.48, "R": 0.05, "r": 0.0155, "open": [0.037, 0.036],
	"teeth": [
		{"x": -0.0158, "y": 0.02, "w": 0.0138, "h": 0.0175, "rot": 0.06},
		{"x": 0.0152, "y": 0.02, "w": 0.0138, "h": 0.0175, "rot": -0.05},
		{"x": 0.021, "y": -0.026, "w": 0.01, "h": 0.011, "rot": 0.12},
	],
	"tongue": {"pts": [[-0.016, -0.024, 0.016], [0.0, -0.021, 0.008], [0.014, -0.025, 0.014]], "r": 0.014, "flat": 0.5},
}

static func def() -> Dictionary:
	return {
		"id": "z_crew",
		"name": "Tuned-In: WZTV Crew",
		"kind": "zombie",
		"rig": {"height": 1.56, "headScale": 1.34, "shoulderW": 0.44, "hipW": 0.28, "legLen": 0.7, "torsoLen": 0.5},
		"armOut": 0.1,
		# hunch: spine + chest + neck ~18 deg forward on top of the zombie lean, head pushed forward (chin up to keep the
		# face readable), arms at different heights (left reaching higher, right drooping).
		"poseOffset": {
			"spine": [-0.16, 0, 0.02], "chest": [-0.14, 0.05, 0], "neck": [-0.14, 0, 0], "head": [0.36, 0.06, 0.09],
			"shoulderL": [0.2, 0, 0.02], "shoulderR": [-0.2, 0, -0.04], "elbowL": [0.12, 0, 0], "elbowR": [0.1, 0, 0],
			"handL": [-0.45, 0, 0], "handR": [-0.3, 0, 0.12],
		},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
	}

# def.anchors(ctx) (head-local anchors consumed by the attachment builders).
static func anchors(_ctx = null) -> Dictionary:
	return {"EYES": EYES, "MOUTH": MOUTH}
