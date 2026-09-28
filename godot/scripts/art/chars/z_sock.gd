# Z_SOCK — the SOCK HOPPER (GDD §8.2, STYLE_GUIDE §7): runtime half of src/art/chars/z_sock.js (sculpt / bake half
# and the googly-eye attachments: blender/chars -> z_sock.glb).
# Custom skeleton (custom:true): root -> s1 -> s2 -> s3 -> head (+ jaw, child of head). The type module
# (actors/types/sock_hopper.gd) drives every joint itself (hop squash/stretch, lean, bite, deflate); createAnimator
# below is a small idle/hop loop for previews.
# Attachment tags the runtime looks for: userData.googlyEye ('L'|'R', the white), userData.googlyPupil ('L'|'R').
extends RefCounted

# Head-local eye anchors (head joint at y = 0.53, z = 0). The eyes sit on top of the head looking forward.
const EYES := {"x": 0.064, "y": 0.158, "z": -0.118, "r": 0.06, "pitch": 0.42}

static func def() -> Dictionary:
	return {
		"id": "z_sock",
		"name": "Sock Hopper",
		"kind": "zombie",
		"rig": {
			"custom": true,
			"joints": [
				{"name": "root", "parent": null, "pos": [0, 0, 0], "tail": [0, 0.13, 0], "blend": 0.06, "gate": 0.22},
				{"name": "s1", "parent": "root", "pos": [0, 0.13, 0], "blend": 0.07, "gate": 0.22},
				{"name": "s2", "parent": "s1", "pos": [0, 0.13, 0], "blend": 0.07, "gate": 0.22},
				{"name": "s3", "parent": "s2", "pos": [0, 0.13, 0], "blend": 0.07, "gate": 0.22},
				{"name": "head", "parent": "s3", "pos": [0, 0.14, 0], "tail": [0, 0.03, -0.2], "blend": 0.07, "gate": 0.22},
				{"name": "jaw", "parent": "head", "pos": [0, -0.012, -0.02], "tail": [0, -0.02, -0.18], "blend": 0.035, "gate": 0.16},
			],
			"bindPose": {},
			"dims": {"height": 0.72, "headH": 0.2},
		},
		"rim": {"color": "#8FF3FF", "strength": 0.3},
		"slots": {"head": {"joint": "head", "pos": [0, 0.17, -0.06]}},
		"anchors": func(_ctx): return {"EYES": EYES},
		"createAnimator": func(rig, _ctx): return createAnimator(rig),
	}

# Preview animator (charview): idle sway, or a hop loop when speed > 0. The game drives joints itself.
static func createAnimator(rig) -> Rig.FnAnimator:
	var J: Dictionary = rig.joints
	var S := {"t": randf() * 10.0}
	var a := Rig.FnAnimator.new()
	a.rig = rig
	a.updateFn = func(dt: float, st: Dictionary) -> void:
		S.t += dt
		var t: float = S.t
		var moving: bool = Rig.num(st.get("speed")) > 0.1
		var ph := fmod(t / 0.33, 1.0)
		var air := sin(ph * PI) if moving else 0.0
		rig.root.position.y = air * 0.14
		var sy := (0.75 if (ph < 0.12 or ph > 0.9) else 1.0 + air * 0.25) if moving else 1.0 + sin(t * 3.0) * 0.02
		rig.root.scale = Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))
		for n in ["s1", "s2", "s3"]:
			J[n].rotation.x = (-0.08 if moving else 0.0) + sin(t * 4.0 + n.length()) * 0.05
			J[n].rotation.z = sin(t * 2.3 + n.length()) * 0.04
		J.head.rotation.x = 0.1 - air * 0.2 if moving else sin(t * 2.0) * 0.05
		var at := Rig.num(st.get("attack"))
		J.jaw.rotation.x = 0.5 * sin(minf(1.0, at) * PI) if at != 0.0 else 0.05 + maxf(0.0, sin(t * 5.0)) * 0.08
	return a
