# BOSS_BARON — BARON VON STATIC's body (GDD §13 step 6): runtime half of src/art/chars/boss_baron.js (the sculpt /
# bake half is blender/chars -> boss_baron.glb). Model units: actors/boss.gd scales the character x2.5. The TV head,
# the flowing cape and the static tornado are built at runtime by boss.gd.
# Custom skeleton: base (waist, root) -> chest -> head (the neck; charRuntime needs a 'head' joint);
# chest -> shoulderL/R -> elbowL/R -> handL/R. Bind pose = the joint positions below (relaxed A-pose). boss.gd rotates
# the joints itself (hover sway, arm gestures, the grab); createAnimator is only the charview preview idle.
extends RefCounted

# Bind joint positions (absolute, model units).
const JP := {
	"base": [0, 0, 0],
	"chest": [0, 0.3, 0],
	"neck": [0, 0.64, 0.01],
	"shoulder": [-0.31, 0.575, 0.01],
	"elbow": [-0.46, 0.28, -0.02],
	"hand": [-0.55, 0.0, -0.07],
}
static func rel(a: Array, b: Array) -> Array:
	return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
static func neg(p: Array) -> Array:
	return [-p[0], p[1], p[2]]

# Glove frame: local -y runs along the forearm (elbow -> hand), local +x is medial (toward the body), -z is front.
const GLOVE_ROT := [0.179, 0, -0.31]

static func def() -> Dictionary:
	return {
		"id": "boss_baron",
		"name": "Baron Von Static",
		"kind": "creature",
		"rig": {
			"custom": true,
			"joints": [
				{"name": "base", "parent": null, "pos": JP.base, "tail": [0, 0.3, 0], "blend": 0.05, "gate": 0.3},
				{"name": "chest", "parent": "base", "pos": rel(JP.chest, JP.base), "tail": [0, 0.34, 0], "blend": 0.08, "gate": 0.3},
				{"name": "head", "parent": "chest", "pos": rel(JP.neck, JP.chest), "tail": [0, 0.08, 0], "blend": 0.03, "gate": 0.1},
				{"name": "shoulderL", "parent": "chest", "pos": rel(JP.shoulder, JP.chest), "tail": rel(JP.elbow, JP.shoulder), "blend": 0.07, "gate": 0.11},
				{"name": "elbowL", "parent": "shoulderL", "pos": rel(JP.elbow, JP.shoulder), "tail": rel(JP.hand, JP.elbow), "blend": 0.06, "gate": 0.09},
				{"name": "handL", "parent": "elbowL", "pos": rel(JP.hand, JP.elbow), "tail": [-0.05, -0.2, -0.03], "blend": 0.04, "gate": 0.08},
				{"name": "shoulderR", "parent": "chest", "pos": rel(neg(JP.shoulder), JP.chest), "tail": rel(neg(JP.elbow), neg(JP.shoulder)), "blend": 0.07, "gate": 0.11},
				{"name": "elbowR", "parent": "shoulderR", "pos": rel(neg(JP.elbow), neg(JP.shoulder)), "tail": rel(neg(JP.hand), neg(JP.elbow)), "blend": 0.06, "gate": 0.09},
				{"name": "handR", "parent": "elbowR", "pos": rel(neg(JP.hand), neg(JP.elbow)), "tail": [0.05, -0.2, -0.03], "blend": 0.04, "gate": 0.08},
			],
			"bindPose": {},
			"dims": {"height": 1.2, "headH": 0.52},
		},
		"rim": {"color": "#C9A0FF", "strength": 0.45},
		"createAnimator": func(rig, _ctx): return createAnimator(rig),
	}

# charview preview only: a slow hover sway with the gloves breathing. boss.gd drives the joints in game.
static func createAnimator(rig) -> Rig.FnAnimator:
	var J: Dictionary = rig.joints
	var S := {"t": 0.0}
	var a := Rig.FnAnimator.new()
	a.rig = rig
	a.updateFn = func(dt: float, _st: Dictionary) -> void:
		S.t += dt
		var t: float = S.t
		J.chest.rotation.z = sin(t * 0.9) * 0.04
		J.chest.rotation.x = sin(t * 0.7) * 0.03
		J.shoulderL.rotation.z = -0.1 + sin(t * 1.1) * 0.06
		J.shoulderR.rotation.z = 0.1 - sin(t * 1.1 + 0.6) * 0.06
		J.elbowL.rotation.x = -0.25 + sin(t * 1.3) * 0.08
		J.elbowR.rotation.x = -0.25 + sin(t * 1.3 + 0.8) * 0.08
	return a
