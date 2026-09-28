# Rig construction for baked characters: runtime parts of src/art/rigBuild.js (jointFrames / bone segments are the
# baker's, see blender/chars).
#   RigBuild.buildRig(def) -> R { rig, bones: [names], joints: {name: Node3D}, humanoid, bindPose, skin, def, parents }
#   RigBuild.applyBindPose(R) / RigBuild.resetPose(R): put the joints in the sculpt (bind) pose or back to rest.
# Humanoids use scripts/core/rig.gd createRig(def.rig) unchanged, so the engine Animator drives them. Custom rigs:
#   def.rig = { custom: true, joints: [{ name, parent, pos:[x,y,z] (relative to parent), tail:[x,y,z] (segment end,
#   relative), blend, gate }], bindPose }.
# Bind pose: Euler XYZ rotations per joint applied on top of rest (default: arms out ~35 deg = A-pose).
class_name RigBuild
extends RefCounted

const HUMANOID_JOINTS := ["hips", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "handL", "shoulderR", "elbowR",
	"handR", "hipL", "kneeL", "footL", "hipR", "kneeR", "footR"]

const DEFAULT_BIND := {"shoulderL": [0, 0, -0.62], "shoulderR": [0, 0, 0.62]}

# Joint blend half-width (m) with the parent bone, and gate radius for the parent-side blend (see CHARKIT.md).
const HUMANOID_SKIN := {
	"hips": {"blend": 0, "gate": 0.3},
	"spine": {"blend": 0.07, "gate": 0.35},
	"chest": {"blend": 0.08, "gate": 0.35},
	"neck": {"blend": 0.035, "gate": 0.085},
	"head": {"blend": 0.03, "gate": 0.12},
	"shoulderL": {"blend": 0.06, "gate": 0.1}, "shoulderR": {"blend": 0.06, "gate": 0.1},
	"elbowL": {"blend": 0.05, "gate": 0.08}, "elbowR": {"blend": 0.05, "gate": 0.08},
	"handL": {"blend": 0.03, "gate": 0.065}, "handR": {"blend": 0.03, "gate": 0.065},
	"hipL": {"blend": 0.07, "gate": 0.13}, "hipR": {"blend": 0.07, "gate": 0.13},
	"kneeL": {"blend": 0.06, "gate": 0.1}, "kneeR": {"blend": 0.06, "gate": 0.1},
	"footL": {"blend": 0.035, "gate": 0.09}, "footR": {"blend": 0.035, "gate": 0.09},
}

static func buildRig(def: Dictionary) -> Dictionary:
	var spec: Dictionary = def.get("rig", {}) if def.get("rig") != null else {}
	var rig: Rig.RigData
	var bones: Array
	var humanoid: bool
	var skin := {}
	if not Rig.truthy(spec.get("custom")):
		rig = Rig.createRig(spec)
		bones = HUMANOID_JOINTS.duplicate()
		humanoid = true
		skin.merge(HUMANOID_SKIN, true)
		if def.get("skin") is Dictionary:
			skin.merge(def.skin, true)
	else:
		humanoid = false
		var joints := {}
		var root := DAU.node3d("rig")
		bones = []
		for j in spec.joints:
			var o := DAU.node3d(j.name)
			o.position = DAU.v3(j.get("pos", [0, 0, 0]))
			var par: Node3D = joints[j.parent] if j.get("parent") != null else root
			par.add_child(o)
			joints[j.name] = o
			bones.append(j.name)
			skin[j.name] = {"blend": j.get("blend", 0.05), "gate": j.get("gate", 0.1)}
		rig = Rig.RigData.new()
		rig.root = root
		rig.joints = joints
		rig.dims = spec.get("dims", {}) if spec.get("dims") != null else {}
		rig.spec = spec
		for n in bones:
			rig.base.append([joints[n], joints[n].position])
	var bindPose = spec.get("bindPose")
	if bindPose == null:
		bindPose = def.get("bindPose")
	if bindPose == null:
		bindPose = DEFAULT_BIND if humanoid else {}
	var R := {"rig": rig, "bones": bones, "joints": rig.joints, "humanoid": humanoid, "bindPose": bindPose, "skin": skin, "def": def}
	var parents := {}
	for n in bones:
		var p: Node = rig.joints[n].get_parent()
		parents[n] = String(p.name) if p != null and bones.has(String(p.name)) and p != rig.root else null
	R.parents = parents
	return R

static func applyBindPose(R: Dictionary) -> void:
	for n in R.bones:
		R.joints[n].rotation = Vector3.ZERO
	for n in R.bindPose:
		var e: Array = R.bindPose[n]
		if R.joints.has(n):
			R.joints[n].rotation = Vector3(e[0], e[1], e[2])
	R.rig.root.position = Vector3.ZERO
	R.rig.root.rotation = Vector3.ZERO
	R.rig.root.scale = Vector3.ONE

static func resetPose(R: Dictionary) -> void:
	for n in R.bones:
		R.joints[n].rotation = Vector3.ZERO
