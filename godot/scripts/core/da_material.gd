# DAMaterial: the ShaderMaterial every DEAD AIR material factory returns (materials.gd toon / glow / basic / screen /
# bubble), with a JS-like facade so ports of code that pokes THREE materials stay line-by-line:
#   mat.color / mat.emissive       Color (sRGB, like Color("#hex"); THREE.Color keeps LINEAR values: when porting JS
#                                  colour arithmetic exactly, work on c.srgb_to_linear() and convert back)
#   mat.emissiveIntensity, mat.opacity, mat.alphaTest, mat.vertexColors, mat.intensity (glow)
#   mat.map                        Texture2D or null (textures are sampled with three's flipY unless the texture has
#                                  meta "flipY" = false; wrap/filter from meta "wrap" ("repeat"|"clamp") / "filter"
#                                  ("linear"|"nearest") or mat.mapWrap / mat.mapFilter)
#   mat.mapOffset / mat.mapRepeat   Vector2 (three map.offset / map.repeat; the repeat of textures.gd repeat() is
#                                  picked up from the texture meta "repeat")
#   mat.transparent, mat.side (FrontSide 0 / BackSide 1 / DoubleSide 2), mat.depthWrite, mat.additive
#                                  (compile-time in Godot: setting them switches the shader variant)
#   mat.uniforms.uX.value = v      ShaderMaterial.uniforms facade (screen: uBulge, uWobble, uBright, uTint ...)
#   mat.userData                   JS material.userData (daToon {color, params}, uniforms (toon locals: uWrap uSteps
#                                  uRimStrength uRimPower uRimColor uKeep uFogK uDaFade), chroma / chromacast ...)
#   mat.name, mat.kind ("toon" | "glow" | "basic" | "screen" | "bubble"), mat.clone()
# DoubleSide transparent materials draw like three: back faces first (this material, cull_front), then front faces
# (next_pass twin, cull_back); every parameter set goes to both.
class_name DAMaterial
extends ShaderMaterial

const FrontSide := 0
const BackSide := 1
const DoubleSide := 2
const NormalBlending := 1
const AdditiveBlending := 2

# Per-uniform facade: `value` reads the last value, writing it sets the shader parameter (global ones go to
# RenderingServer.global_shader_parameter_set).
class DAUniform extends RefCounted:
	var name: String
	var mat: WeakRef = null
	var isGlobal := false
	var _v = null
	var value:
		get:
			return _v
		set(v):
			_v = v
			if isGlobal:
				RenderingServer.global_shader_parameter_set(name, v)
			elif mat != null:
				var m = mat.get_ref()
				if m != null:
					m.setParam(name, v)
	func _init(n: String, v = null, m = null, glob := false) -> void:
		name = n
		_v = v
		isGlobal = glob
		if m != null:
			mat = weakref(m)

var kind := ""
var name := "":
	set(v):
		name = v
		resource_name = v
var userData := {}
var uniforms := {}
var mats = null                      # the Materials system (shader variants)
var variantKey := {"transparent": false, "side": FrontSide, "depthWrite": true, "additive": false, "ext": ""}
var mapWrap := ""                    # "" = from the texture meta (default clamp), else "repeat" | "clamp"
var mapFilter := ""                  # "" = from the texture meta (default linear), else "linear" | "nearest"
var twin: ShaderMaterial = null      # front-face pass of a DoubleSide transparent material

var _mapOffset := Vector2.ZERO
var _mapRepeat := Vector2.ONE
var _color := Color(1, 1, 1)
var _emissive := Color(0, 0, 0)
var _map: Texture2D = null

var color: Color:
	get:
		return _color
	set(v):
		_color = v
		setParam("uColor", v)
var emissive: Color:
	get:
		return _emissive
	set(v):
		_emissive = v
		setParam("uEmissive", v)
var emissiveIntensity: float:
	get:
		return float(getParam("uEmissiveIntensity", 1.0))
	set(v):
		setParam("uEmissiveIntensity", v)
var intensity: float:
	get:
		return float(getParam("uIntensity", 1.0))
	set(v):
		setParam("uIntensity", v)
var opacity: float:
	get:
		return float(getParam("uOpacity", 1.0))
	set(v):
		setParam("uOpacity", v)
var alphaTest: float:
	get:
		return float(getParam("uAlphaTest", 0.0))
	set(v):
		setParam("uAlphaTest", v)
var vertexColors: bool:
	get:
		return float(getParam("uVColor", 0.0)) > 0.5
	set(v):
		setParam("uVColor", 1.0 if v else 0.0)
var map: Texture2D:
	get:
		return _map
	set(v):
		_setMap(v)
# three map.offset / map.repeat (kept on the texture in three; per material here): mat.mapOffset.x = t * 0.08
var mapOffset: Vector2:
	get:
		return _mapOffset
	set(v):
		_mapOffset = v
		setParam("uMapXf", Vector4(_mapRepeat.x, _mapRepeat.y, v.x, v.y))
var mapRepeat: Vector2:
	get:
		return _mapRepeat
	set(v):
		_mapRepeat = v
		setParam("uMapXf", Vector4(v.x, v.y, _mapOffset.x, _mapOffset.y))
var transparent: bool:
	get:
		return variantKey.transparent
	set(v):
		_setVariant("transparent", v)
var side: int:
	get:
		return variantKey.side
	set(v):
		_setVariant("side", v)
var depthWrite: bool:
	get:
		return variantKey.depthWrite
	set(v):
		_setVariant("depthWrite", v)
var additive: bool:
	get:
		return variantKey.additive
	set(v):
		_setVariant("additive", v)

func setParam(n: String, v) -> void:
	# perf: an unchanged value is not re-sent (each set queues a material update in the RenderingServer); the twin
	# always receives the same values (materials.gd copies them when it is created)
	var cur = get_shader_parameter(n)
	if cur != null and typeof(cur) == typeof(v) and cur == v:
		return
	set_shader_parameter(n, v)
	if twin != null:
		twin.set_shader_parameter(n, v)

func getParam(n: String, def = null):
	var v = get_shader_parameter(n)
	return def if v == null else v

func _setVariant(k: String, v) -> void:
	if variantKey.get(k) == v:
		return
	variantKey[k] = v
	if mats != null:
		mats._applyVariant(self)

# Picks the sampler for the texture's wrap/filter and three's flipY.
func _setMap(t: Texture2D) -> void:
	_map = t
	if kind == "screen":
		setParam("tScreen", t)
		setParam("uFlip", 0.0 if t != null and t.has_meta("flipY") and not t.get_meta("flipY") else 1.0)
		if t != null and t.get_width() > 0:
			setParam("uTexel", Vector2(1.0 / t.get_width(), 1.0 / t.get_height()))
		return
	for s in ["mapRL", "mapCL", "mapRN", "mapCN"]:
		setParam(s, null)
	if t == null:
		setParam("uMapMode", 0)
		return
	var wrap := mapWrap if mapWrap != "" else str(t.get_meta("wrap", "clamp"))
	var filt := mapFilter if mapFilter != "" else str(t.get_meta("filter", "linear"))
	var mode := 1
	if wrap == "repeat":
		mode = 1 if filt != "nearest" else 3
	else:
		mode = 2 if filt != "nearest" else 4
	setParam(["", "mapRL", "mapCL", "mapRN", "mapCN"][mode], t)
	if t.has_meta("repeat"):
		mapRepeat = t.get_meta("repeat")
	setParam("uMapMode", mode)
	setParam("uMapFlip", 0.0 if t.has_meta("flipY") and not t.get_meta("flipY") else 1.0)

# JS material.clone(): an independent copy (same shader variant, parameters, userData deep-copied except shared
# textures). The toon cache is not involved (like three).
func clone() -> DAMaterial:
	var m := DAMaterial.new()
	m.kind = kind
	m.mats = mats
	m.name = name
	m.variantKey = variantKey.duplicate()
	m.mapWrap = mapWrap
	m.mapFilter = mapFilter
	m.shader = shader
	m.render_priority = render_priority
	if shader != null:
		for p in shader.get_shader_uniform_list():
			var pn: String = p.name
			var v = get_shader_parameter(pn)
			if v != null:
				m.set_shader_parameter(pn, v)
	m._color = _color
	m._emissive = _emissive
	m._map = _map
	m._mapOffset = _mapOffset
	m._mapRepeat = _mapRepeat
	m.userData = userData.duplicate(true)
	# the toon locals / screen facades must point at the copy
	var lu = m.userData.get("uniforms")
	if lu is Dictionary:
		for k in lu:
			if lu[k] is DAUniform:
				lu[k] = DAUniform.new(k, lu[k].value, m)
	for k in uniforms:
		var u: DAUniform = uniforms[k]
		m.uniforms[k] = u if u.isGlobal else DAUniform.new(k, u.value, m)
	if mats != null and (variantKey.transparent and variantKey.side == DoubleSide):
		mats._applyVariant(m)
	return m
