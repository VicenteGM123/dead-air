# EXAMPLE (kit test, not final art): runtime half of src/art/chars/example_sock.js — a sock puppet on a custom
# 5-joint chain, showing the non-humanoid path: custom rig, zombie kind (cyan rim, ZOMBIES layer), cylindrical
# stripe pattern, eyes, custom animator. (Sculpt / bake half: blender/chars -> example_sock.glb.)
extends RefCounted

const SEG := 0.13
const EYE := {
	"x": 0.045, "y": 0.07, "z": -0.08, "r": 0.034, "iris": "#1E1622", "irisSize": 0.5, "pupilSize": 0.7, "sclera": "#FBF6EE",
	"lid": "#F4F1E8", "lash": "#2A1A14", "lidOpen": 0.8, "lowerLid": 0.1, "tilt": 0,
}

static func def() -> Dictionary:
	return {
		"id": "example_sock",
		"name": "Sock (kit example)",
		"kind": "zombie",
		"rig": {
			"custom": true,
			"joints": [
				{"name": "root", "parent": null, "pos": [0, 0.02, 0], "tail": [0, SEG, 0], "blend": 0.05, "gate": 0.2},
				{"name": "s1", "parent": "root", "pos": [0, SEG, 0], "blend": 0.05, "gate": 0.2},
				{"name": "s2", "parent": "s1", "pos": [0, SEG, 0], "blend": 0.05, "gate": 0.2},
				{"name": "s3", "parent": "s2", "pos": [0, SEG, 0], "blend": 0.05, "gate": 0.2},
				{"name": "head", "parent": "s3", "pos": [0, SEG, 0], "tail": [0, 0.12, -0.05], "blend": 0.05, "gate": 0.2},
			],
			"bindPose": {},
		},
		"slots": {"head": {"joint": "head", "pos": [0, 0.14, 0]}},
		"createAnimator": func(rig, _ctx): return createAnimator(rig),
	}

static func createAnimator(rig) -> Rig.FnAnimator:
	var J: Dictionary = rig.joints
	var S := {"t": randf() * 10.0}
	var a := Rig.FnAnimator.new()
	a.rig = rig
	a.updateFn = func(dt: float, st: Dictionary) -> void:
		S.t += dt
		var t: float = S.t
		var moving := Rig.truthy(st.get("speed"))
		var hop := absf(sin(t * (7.0 if moving else 3.0)))
		rig.root.position.y = hop * (0.12 if moving else 0.03)
		for n in ["s1", "s2", "s3", "head"]:
			J[n].rotation.x = sin(t * 5.0 + n.length()) * 0.12 - (0.08 if moving else 0.0)
			J[n].rotation.z = sin(t * 3.1 + n.length()) * 0.06
	return a
