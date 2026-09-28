# Face controller for baked characters (port of the runtime half of src/art/face.js).
#   Face.FaceController: blink(), setLook(x, y) (-1..1), lookAt(worldPos|null), setExpression(name, weight),
#     update(dt) (auto blink, eye darts, smoothing). Expressions: neutral, smile, frown, o_mouth, wink, angry
#     (+ any morph names baked for the character). Drives lids, brows (rigid parts) and morph targets.
# The attachment builders of face.js (makeAttachBuilder: eyes / aviators / glasses / hoops / mesh, eyeTexture) build
# geometry: they are the Blender half (blender/chars, exported in godot/assets/chars/<id>.glb). char_runtime.gd
# reparents the exported eye nodes and registers them here with addEye({side, root, ball, upper, lower, cap, E}).
# Morph targets = the body's blend shapes; the JS morph COLOURS (mouth interior) are the char shader's instance
# uniform uMorphW (blend weights of morphs 0..2), kept equal to the blend shape values here.
extends RefCounted

const EXPR := {
	"neutral": {},
	# smiles reach the eyes: the cheeks push the lower lids up (~15-20 % of the eye opening)
	"smile": {"lid": -0.04, "lower": 0.36, "brow": [0.004, 0.0], "morph": {"smile": 1}},
	"frown": {"lid": -0.06, "brow": [-0.004, -0.14], "morph": {"frown": 1}},
	"o_mouth": {"lid": 0.1, "lower": -0.05, "brow": [0.01, 0.1], "morph": {"o_mouth": 1}},
	"wink": {"lidL": -1, "lower": 0.32, "brow": [0.003, 0], "morph": {"smile": 0.8}},
	"angry": {"lid": -0.18, "brow": [-0.006, -0.32], "morph": {"frown": 0.8}},
	# STYLE_GUIDE §4 presets (heroes: the sculpted base face is the warm soft smile = 'neutral')
	"determined": {"lid": -0.1, "brow": [-0.003, -0.12], "morph": {"frown": 0.35}},
	"hurt": {"lid": -0.25, "lower": 0.1, "brow": [0.004, 0.22], "morph": {"o_mouth": 0.6, "frown": 0.3}},
	"grin": {"lid": -0.04, "lower": 0.36, "brow": [0.004, 0.0], "morph": {"smile": 1}},
	"surprised": {"lid": 0.12, "lower": -0.06, "brow": [0.012, 0.1], "morph": {"o_mouth": 1}},
}
const EXPRESSIONS := ["neutral", "smile", "frown", "o_mouth", "wink", "angry", "determined", "hurt", "grin", "surprised"]
const ZERO2 := [0.0, 0.0]
const NO_MORPH := {}


class FaceController extends RefCounted:
	var eyes: Array = []        # [{ side, root, ball, upper, lower, cap, E }]
	var brows: Array = []       # [{ mesh (the part pivot), side, base: Vector3, baseRot: Vector3 }]
	var mesh: MeshInstance3D = null
	var look := Vector2()
	var lookTarget := Vector2()
	var lookWorld = null        # Vector3 | null
	var blinkT: float
	var blinkPhase := -1.0
	var expr := "neutral"
	var exprW := 1.0
	var cur := {"lid": 0.0, "lidL": 0.0, "lidR": 0.0, "lower": 0.0, "brow": [0.0, 0.0]}
	var auto := true
	var _t := 0.0
	var _morphList: Array = []  # [[name, blend shape index], ...] (JS Object.entries(morphTargetDictionary))
	var _morphW := Vector3.ZERO

	func _init() -> void:
		blinkT = 2.0 + randf() * 3.0

	func addEye(e: Dictionary) -> void:
		eyes.append(e)
		_applyLids(e, 0.0, 0.0)

	func addBrow(m: Node3D, side: String) -> void:
		brows.append({"mesh": m, "side": side, "base": m.position, "baseRot": m.rotation})

	func setMesh(m: MeshInstance3D) -> void:
		mesh = m
		_morphList = []
		if m != null and m.mesh is ArrayMesh:
			var am := m.mesh as ArrayMesh
			for i in am.get_blend_shape_count():
				_morphList.append([String(am.get_blend_shape_name(i)), i])

	func blink() -> void:
		blinkPhase = 0.0

	func setLook(x: float, y: float) -> void:
		lookWorld = null
		lookTarget = Vector2(maxf(-1.0, minf(1.0, x)), maxf(-1.0, minf(1.0, y)))

	func lookAt(p) -> void:
		lookWorld = p if p is Vector3 else null

	func _hasMorph(name: String) -> bool:
		for e in _morphList:
			if e[0] == name:
				return true
		return false

	func setExpression(name: String, w: float = 1.0) -> void:
		expr = name if (EXPR.has(name) or _hasMorph(name)) else "neutral"
		exprW = w

	func _applyLids(e: Dictionary, closeU: float, lowerUp: float) -> void:
		var E: Dictionary = e.E
		# Upper lid: front edge elevation (rad) from openness; 0 = edge at the eye center.
		var open: float = E.get("lidOpen", 0.7) if E.get("lidOpen") != null else 0.7
		var elev := lerpf(-0.12, 0.62, open) - closeU * (lerpf(-0.12, 0.62, open) + 0.14)
		var cap: float = e.cap
		e.upper.rotation.x = elev + (cap - PI / 2.0)
		var lowerLid: float = E.get("lowerLid", 0.25) if E.get("lowerLid") != null else 0.25
		var low := -lowerLid * 1.2 + lowerUp
		e.lower.rotation.x = low - (cap - PI / 2.0)

	func update(dt: float, _headObj = null) -> void:
		_t += dt
		# auto blink
		if auto:
			blinkT -= dt
			if blinkT <= 0.0:
				blink()
				blinkT = 2.2 + randf() * 3.5
			if randf() < dt * 0.25:
				lookTarget = Vector2((randf() - 0.5) * 0.8, (randf() - 0.5) * 0.4)
		var bl := 0.0
		if blinkPhase >= 0.0:
			blinkPhase += dt / 0.16
			bl = blinkPhase * 2.0 if blinkPhase < 0.5 else maxf(0.0, 2.0 - blinkPhase * 2.0)
			if blinkPhase >= 1.0:
				blinkPhase = -1.0
		var X: Dictionary = EXPR.get(expr, {})
		var w := exprW
		var k := 1.0 - exp(-dt * 14.0)
		var c := cur
		c.lid += (float(X.get("lid", 0.0)) * w - c.lid) * k
		c.lidL += (float(X.get("lidL", 0.0)) * w - c.lidL) * k
		c.lidR += (float(X.get("lidR", 0.0)) * w - c.lidR) * k
		c.lower += (float(X.get("lower", 0.0)) * w - c.lower) * k
		var bw: Array = X.get("brow", ZERO2)
		c.brow[0] += (float(bw[0]) * w - c.brow[0]) * k
		c.brow[1] += (float(bw[1]) * w - c.brow[1]) * k
		look = look.lerp(lookTarget, 1.0 - exp(-dt * 18.0))
		var lid: float = c.lid
		for e in eyes:
			var extra: float = c.lidL if e.side == "L" else c.lidR
			var close := minf(1.0, maxf(0.0, bl + maxf(0.0, -extra) - minf(0.0, lid) * 1.5))
			var openMore := maxf(0.0, lid) * 1.5
			_applyLids(e, close - openMore * 0.5, c.lower)
			e.ball.rotation = Vector3(-look.y * 0.35, -look.x * 0.5, 0.0)
		for b in brows:
			b.mesh.position.y = b.base.y + c.brow[0]
			b.mesh.rotation.z = b.baseRot.z + c.brow[1] * (-1.0 if b.side == "L" else 1.0)
		if mesh != null and not _morphList.is_empty():
			var target: Dictionary = X.get("morph", NO_MORPH)
			for e in _morphList:
				var name: String = e[0]
				var i: int = e[1]
				var tv = target.get(name)
				var t := (float(tv) if tv != null and float(tv) != 0.0 else (1.0 if expr == name else 0.0)) * w
				var inf := mesh.get_blend_shape_value(i)
				inf += (t - inf) * k
				mesh.set_blend_shape_value(i, inf)
				if i < 3:
					_morphW[i] = inf
			# morph colours (char shader): same influences
			mesh.set_instance_shader_parameter("uMorphW", _morphW)
