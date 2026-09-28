# Cartoon material factory (port of src/core/materials.js; ARCHITECTURE §5/§12, GDD §3.5) + the palette.
#
# toon(color, opts)  three's MeshStandardMaterial + the onBeforeCompile patch, as shaders/toon.gdshaderinc:
#   - half-lambert "wrap" diffuse (soft GI-like falloff), optional stepped shading,
#   - fresnel rim light (the key PvZ-GW ingredient), brighter on up-facing normals,
#   - global pre-power grade: environment desaturation (uSatEnv) + amber tint (uAmber), skipped with keepColor,
#   - the Sign-On color wave: saturation restored inside uWaveRadius around uWaveOrigin and a 1 m band of
#     scrolling color-bar emissive stripes at the front (GDD §10.1),
#   - optional screen-door dither fade (heroFade) driven by the global uHeroFade (camera too close to hero),
#   - CAMERA OCCLUSION fade: a screen-door dither of whatever stands between the camera and the hero (props, the
#     tower lattice...), driven by the global uOcc* uniforms (camera.gd computes them as cam.occ, render.gd uploads
#     them for the gameplay main camera only; feeds, menus, the ending and shadows never fade). A fragment fades
#     when it is closer to the camera than the hero (by more than ~0.3 m) AND either inside an ellipse around the
#     hero's screen silhouette (a see-through window over the hero) or inside one of up to 4 occluder boxes
#     (camera.gd: props the lines to the hero cross, or right in front of the lens: they fade whole, with a smooth
#     ramp). Walls can't be in front of the hero (the camera probe stops at them). Never below the hero's feet
#     (floors, rugs), never on hero-fade materials or actors (noOcclusion).
#   Materials are cached by their params: equal requests return the same instance.
#   keepColor, fog:false, heroFade, env, wrap, steps, rim... are per-material uniforms (as in the JS program sharing).
#   opts: { rough=0.75, metal=0, emissive, emissiveIntensity=1, rim=0.35, rimColor, rimPower=2.4, wrap=0.5,
#           steps=0, map, transparent, opacity=1, side, flat, keepColor, heroFade, vertexColors, env, alphaTest,
#           depthWrite, fog=true, name }
#   Godot-only opts (texture sampling, three keeps them on the texture): mapWrap "repeat"|"clamp",
#   mapFilter "linear"|"nearest", mapFlipY (bool, default true = three's flipY for canvas textures).
# glow(color, intensity, opts)  unlit HDR emissive (feeds bloom) for bulbs/neon/LEDs (with the occlusion fade).
# screen(texture, {bulge}) CRT glass: swappable `.map`, barrel, scanlines, chroma offset, vignette, glossy sheet.
# rubberGlass(texture)     screen() with the animated vertex bulge (mat.uniforms.uBulge.value 0..0.35 m,
#                          uWobble 0..1); use screenGeometry(w, h) (plane subdivided 24x18).
# glass(color), skin(tone), basic(color, opts), bubble(color, intensity) (props/sponsors.js drop bubble).
# Global uniforms (shared by every toon material): mats.uniforms = { uSatEnv, uAmber, uWaveOrigin, uWaveRadius,
#   uTime, uHeroFade, uRimAmbient, uBars (constant; kept for other code), uOccRect, uOccZ, uOccAmt, uOccBox0/1,
#   uOccWall0/1 }: Godot global shader parameters (project.godot [shader_globals]) behind DAUniform facades, so the
#   JS access pattern is unchanged: game.mats.uniforms.uSatEnv.value = 1.0 (writes RenderingServer immediately).
#   signon.gd animates the first four; lights.gd drives uRimAmbient; render.gd writes the uOcc* ones.
# fromSpec(spec, importedMaterial) builds the material a Blender "da" material spec describes (SPEC §5.5).
# patchShader(mat, ext, uniforms): the Chromacast shader patches (ext "chroma" = props/weapons.js patchChroma,
#   "cc" = game/weaponModels.js patchCC) switch that material's shader in place, like the JS onBeforeCompile patches.
# chromacast: a field for weapons.gd to install its Callable (JS weapons.js sets game.mats.chromacast = fn(signal)).
# Engine plumbing not ported: program cache keys, lightsOnly(), the RoomEnvironment PMREM generation (baked once by
# tools/env_bake into shaders/data/room_env.res: three's own PMREM atlas, sampled with the same textureCubeUV).
extends RefCounted

const DAMat := preload("res://scripts/core/da_material.gd")
const FrontSide := 0
const BackSide := 1
const DoubleSide := 2
const AdditiveBlending := 2
const ENV_PATH := "res://shaders/data/room_env.res"

# three r186 DFG LUT (DFGLUTData.js: 16x16 RG half floats, LinearFilter, ClampToEdge).
const DFG_DATA := [
	0x30b5, 0x3ad1, 0x314c, 0x3a4d, 0x33d2, 0x391c, 0x35ef, 0x3828, 0x37f3, 0x36a6, 0x38d1, 0x3539, 0x3979, 0x3410, 0x39f8, 0x3252, 0x3a53, 0x30f0, 0x3a94, 0x2fc9, 0x3abf, 0x2e35, 0x3ada, 0x2d05, 0x3ae8, 0x2c1f, 0x3aed, 0x2ae0, 0x3aea, 0x29d1, 0x3ae1, 0x28ff,
	0x3638, 0x38e4, 0x364a, 0x38ce, 0x3699, 0x385e, 0x374e, 0x372c, 0x3839, 0x35a4, 0x38dc, 0x3462, 0x396e, 0x32c4, 0x39de, 0x3134, 0x3a2b, 0x3003, 0x3a59, 0x2e3a, 0x3a6d, 0x2ce1, 0x3a6e, 0x2bba, 0x3a5f, 0x2a33, 0x3a49, 0x290a, 0x3a2d, 0x2826, 0x3a0a, 0x26e8,
	0x3894, 0x36d7, 0x3897, 0x36c9, 0x38a3, 0x3675, 0x38bc, 0x35ac, 0x38ee, 0x349c, 0x393e, 0x3332, 0x3997, 0x3186, 0x39e2, 0x3038, 0x3a13, 0x2e75, 0x3a29, 0x2cf5, 0x3a2d, 0x2bac, 0x3a21, 0x29ff, 0x3a04, 0x28bc, 0x39dc, 0x2790, 0x39ad, 0x261a, 0x3978, 0x24fa,
	0x39ac, 0x34a8, 0x39ac, 0x34a3, 0x39ae, 0x3480, 0x39ae, 0x3423, 0x39b1, 0x330e, 0x39c2, 0x31a9, 0x39e0, 0x3063, 0x39fc, 0x2eb5, 0x3a0c, 0x2d1d, 0x3a14, 0x2bcf, 0x3a07, 0x29ff, 0x39e9, 0x28a3, 0x39be, 0x273c, 0x3989, 0x25b3, 0x394a, 0x2488, 0x3907, 0x2345,
	0x3a77, 0x3223, 0x3a76, 0x321f, 0x3a73, 0x3204, 0x3a6a, 0x31b3, 0x3a58, 0x3114, 0x3a45, 0x303b, 0x3a34, 0x2eb6, 0x3a26, 0x2d31, 0x3a1e, 0x2bef, 0x3a0b, 0x2a0d, 0x39ec, 0x28a1, 0x39c0, 0x271b, 0x3987, 0x2580, 0x3944, 0x2449, 0x38fa, 0x22bd, 0x38ac, 0x2155,
	0x3b07, 0x2fca, 0x3b06, 0x2fca, 0x3b00, 0x2fb8, 0x3af4, 0x2f7c, 0x3adb, 0x2eea, 0x3ab4, 0x2e00, 0x3a85, 0x2cec, 0x3a5e, 0x2bc5, 0x3a36, 0x2a00, 0x3a0d, 0x2899, 0x39dc, 0x2707, 0x39a0, 0x2562, 0x395a, 0x2424, 0x390b, 0x2268, 0x38b7, 0x20fd, 0x385f, 0x1fd1,
	0x3b69, 0x2cb9, 0x3b68, 0x2cbb, 0x3b62, 0x2cbb, 0x3b56, 0x2cae, 0x3b3b, 0x2c78, 0x3b0d, 0x2c0a, 0x3acf, 0x2ae3, 0x3a92, 0x2998, 0x3a54, 0x2867, 0x3a17, 0x26d0, 0x39d3, 0x253c, 0x3989, 0x2402, 0x3935, 0x2226, 0x38dc, 0x20bd, 0x387d, 0x1f54, 0x381d, 0x1db3,
	0x3ba9, 0x296b, 0x3ba8, 0x296f, 0x3ba3, 0x297b, 0x3b98, 0x2987, 0x3b7f, 0x2976, 0x3b4e, 0x2927, 0x3b0e, 0x2895, 0x3ac2, 0x27b7, 0x3a73, 0x263b, 0x3a23, 0x24e7, 0x39d0, 0x239b, 0x3976, 0x21d9, 0x3917, 0x207e, 0x38b2, 0x1ee7, 0x384b, 0x1d53, 0x37c7, 0x1c1e,
	0x3bd2, 0x25cb, 0x3bd1, 0x25d3, 0x3bcd, 0x25f0, 0x3bc2, 0x261f, 0x3bad, 0x2645, 0x3b7d, 0x262d, 0x3b3e, 0x25c4, 0x3aec, 0x250f, 0x3a93, 0x243a, 0x3a32, 0x22ce, 0x39d0, 0x215b, 0x3969, 0x202a, 0x38fe, 0x1e6e, 0x388f, 0x1cf1, 0x381f, 0x1b9b, 0x3762, 0x19dd,
	0x3be9, 0x21ab, 0x3be9, 0x21b7, 0x3be5, 0x21e5, 0x3bdd, 0x2241, 0x3bc9, 0x22a7, 0x3ba0, 0x22ec, 0x3b62, 0x22cd, 0x3b0f, 0x2247, 0x3aae, 0x2175, 0x3a44, 0x2088, 0x39d4, 0x1f49, 0x3960, 0x1dbe, 0x38e9, 0x1c77, 0x3870, 0x1ae8, 0x37f1, 0x1953, 0x3708, 0x181b,
	0x3bf6, 0x1cea, 0x3bf6, 0x1cfb, 0x3bf3, 0x1d38, 0x3bec, 0x1dbd, 0x3bda, 0x1e7c, 0x3bb7, 0x1f25, 0x3b7d, 0x1f79, 0x3b2c, 0x1f4c, 0x3ac6, 0x1ea6, 0x3a55, 0x1dbb, 0x39da, 0x1cbd, 0x395a, 0x1b9d, 0x38d8, 0x1a00, 0x3855, 0x18ac, 0x37ab, 0x173c, 0x36b7, 0x1598,
	0x3bfc, 0x1736, 0x3bfc, 0x1759, 0x3bf9, 0x17e7, 0x3bf4, 0x1896, 0x3be4, 0x1997, 0x3bc6, 0x1aa8, 0x3b91, 0x1b84, 0x3b43, 0x1bd2, 0x3ade, 0x1b8a, 0x3a65, 0x1acd, 0x39e2, 0x19d3, 0x3957, 0x18cd, 0x38ca, 0x17b3, 0x383e, 0x1613, 0x376d, 0x14bf, 0x366f, 0x135e,
	0x3bff, 0x101b, 0x3bff, 0x1039, 0x3bfc, 0x10c8, 0x3bf9, 0x1226, 0x3bea, 0x1428, 0x3bcf, 0x1584, 0x3b9f, 0x16c5, 0x3b54, 0x179a, 0x3af0, 0x17ce, 0x3a76, 0x1771, 0x39ea, 0x16a4, 0x3956, 0x15a7, 0x38bf, 0x14a7, 0x3829, 0x1379, 0x3735, 0x11ea, 0x362d, 0x10a1,
	0x3c00, 0x061b, 0x3c00, 0x066a, 0x3bfe, 0x081c, 0x3bfa, 0x0a4c, 0x3bed, 0x0d16, 0x3bd5, 0x0fb3, 0x3ba9, 0x114d, 0x3b63, 0x127c, 0x3b01, 0x132f, 0x3a85, 0x1344, 0x39f4, 0x12d2, 0x3957, 0x120d, 0x38b5, 0x1122, 0x3817, 0x103c, 0x3703, 0x0ed3, 0x35f0, 0x0d6d,
	0x3c00, 0x007a, 0x3c00, 0x0089, 0x3bfe, 0x011d, 0x3bfb, 0x027c, 0x3bf0, 0x04fa, 0x3bda, 0x0881, 0x3bb1, 0x0acd, 0x3b6f, 0x0c97, 0x3b10, 0x0d7b, 0x3a93, 0x0df1, 0x39fe, 0x0def, 0x3959, 0x0d8a, 0x38af, 0x0ce9, 0x3808, 0x0c31, 0x36d5, 0x0af0, 0x35b9, 0x09a3,
	0x3c00, 0x0000, 0x3c00, 0x0001, 0x3bff, 0x0015, 0x3bfb, 0x0059, 0x3bf2, 0x00fd, 0x3bdd, 0x01df, 0x3bb7, 0x031c, 0x3b79, 0x047c, 0x3b1d, 0x05d4, 0x3aa0, 0x06d5, 0x3a08, 0x075a, 0x395d, 0x075e, 0x38aa, 0x06f7, 0x37f4, 0x0648, 0x36ac, 0x0576, 0x3586, 0x049f,
]

var game
var PAL := Config.PAL
var uniforms := {}
var envMap: Texture2D = null
var dfgLUT: Texture2D = null
var chromacast = null           # weapons.gd installs a Callable(signal) -> material (JS game.mats.chromacast)
var _cache := {}
var _specCache := {}
var _shaders := {}
var _warned := {}

func _init(g) -> void:
	game = g
	var bars: Array = []
	for h in Config.PAL.BARS:
		bars.append(Color(h))
	# Pre-power defaults (GDD §3.3); machines/signon restore 1.0 / 0.0 at Sign-On (or power=1).
	var Z := Projection(Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)
	for e in [["uSatEnv", 0.7], ["uAmber", 0.08], ["uWaveOrigin", Vector3.ZERO], ["uWaveRadius", -1.0], ["uTime", 0.0],
			["uHeroFade", 1.0], ["uRimAmbient", 1.0], ["uOccRect", Vector4.ZERO], ["uOccZ", Vector4.ZERO], ["uOccAmt", 0.0],
			["uOccBox0", Z], ["uOccBox1", Z], ["uOccWall0", Z], ["uOccWall1", Z]]:
		var u = DAMat.DAUniform.new(e[0], e[1], null, true)
		u.value = e[1]
		uniforms[e[0]] = u
	uniforms["uBars"] = DAMat.DAUniform.new("uBars", bars)   # constant in the shaders (materials.js BARS_GLSL)
	_initEnv()

# The RoomEnvironment PMREM atlas (materials.js envMap) and three's DFG LUT as global samplers.
func _initEnv() -> void:
	var raw := PackedByteArray()
	raw.resize(DFG_DATA.size() * 2)
	for i in DFG_DATA.size():
		raw.encode_u16(i * 2, DFG_DATA[i])
	var img := Image.create_from_data(16, 16, false, Image.FORMAT_RGH, raw)
	dfgLUT = ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("daDFG", dfgLUT)
	if ResourceLoader.exists(ENV_PATH):
		envMap = load(ENV_PATH)
	if envMap == null:
		push_warning("[materials] %s missing: RoomEnvironment reflections disabled (run tools/env_bake)" % ENV_PATH)
		var b := Image.create(4, 4, false, Image.FORMAT_RGBAH)
		b.fill(Color(0, 0, 0, 1))
		envMap = ImageTexture.create_from_image(b)
	RenderingServer.global_shader_parameter_set("daEnvMap", envMap)

func update(_dt = 0.0) -> void:
	uniforms.uTime.value = game.time.realNow

# ------------------------------------------------------------------------------------------------ helpers
# JS `opts.k ?? def`
static func _o(opts: Dictionary, k: String, def):
	var v = opts.get(k)
	return def if v == null else v

# JS `!!v`
static func _t(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return true

static func _side(v) -> int:
	if v is String:
		match v:
			"back", "BackSide":
				return BackSide
			"double", "DoubleSide":
				return DoubleSide
		return FrontSide
	return int(v) if v != null else FrontSide

static func _hex(c) -> String:
	if c is String:
		return c
	return "#" + DAU.color(c).to_html(false)

static func _keyVal(v):
	if v is Texture2D:
		return "tex:%d" % v.get_instance_id()
	if v is Object:
		return "obj:%d" % v.get_instance_id()
	if v is int:
		return float(v)
	if v is Color:
		return "#" + v.to_html(true)
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _keyVal(v[k])
		return o
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_keyVal(x))
		return a
	return v

func _key(kind: String, color, p: Dictionary) -> String:
	return "%s|%s|%s" % [kind, str(color), JSON.stringify(_keyVal(p))]

# Shader for a (kind, variant, pass) combination: render_mode + defines + the kind's include.
func _shader(kind: String, vk: Dictionary, back_pass := false) -> Shader:
	var transparent: bool = vk.transparent or vk.additive
	var sd: int = vk.side
	var cull := "cull_back"
	var back := false
	if back_pass or sd == BackSide:
		cull = "cull_front"
		back = true
	elif sd == DoubleSide:
		cull = "cull_disabled"
	var depth := "depth_draw_opaque"
	if not vk.depthWrite:
		depth = "depth_draw_never"
	elif transparent:
		depth = "depth_draw_always"
	var blend := "blend_add" if vk.additive else "blend_mix"
	var modes := [cull, depth, blend, "fog_disabled"]
	var defs: Array = []
	var inc := "res://shaders/toon.gdshaderinc"
	if kind == "glow" or kind == "basic":
		modes.push_front("unshaded")
		inc = "res://shaders/unlit.gdshaderinc"
		if kind == "glow":
			defs.append("DA_GLOW")
	if transparent:
		defs.append("DA_TRANSPARENT")
	if back and kind == "toon":
		defs.append("DA_BACK")
	if vk.ext == "chroma":
		defs.append("DA_CHROMA")
	elif vk.ext == "cc":
		defs.append("DA_CC")
	var key := "%s|%s|%s" % [kind, ",".join(modes), ",".join(defs)]
	var sh: Shader = _shaders.get(key)
	if sh != null:
		return sh
	var code := "shader_type spatial;\nrender_mode %s;\n" % ", ".join(modes)
	for d in defs:
		code += "#define %s\n" % d
	code += "#include \"%s\"\n" % inc
	sh = Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh

# (Re)builds the shader(s) of a material from its variantKey: DoubleSide transparent toon/glow/basic draw back faces
# (this material) then front faces (next_pass twin), like three's two-pass DoubleSide transparency.
func _applyVariant(mat) -> void:
	var vk: Dictionary = mat.variantKey
	if mat.kind != "toon" and mat.kind != "glow" and mat.kind != "basic":
		return
	var transparent: bool = vk.transparent or vk.additive
	var twoPass: bool = transparent and vk.side == DoubleSide and mat.kind == "toon"
	mat.shader = _shader(mat.kind, vk, twoPass)
	if twoPass:
		if mat.twin == null:
			mat.twin = ShaderMaterial.new()
		mat.twin.shader = _shader(mat.kind, {"transparent": vk.transparent, "side": FrontSide, "depthWrite": vk.depthWrite,
			"additive": vk.additive, "ext": vk.ext})
		for p in mat.shader.get_shader_uniform_list():
			var v = mat.get_shader_parameter(p.name)
			if v != null:
				mat.twin.set_shader_parameter(p.name, v)
		mat.next_pass = mat.twin
	elif mat.twin != null:
		mat.twin = null
		mat.next_pass = null

func _newMat(kind: String) -> DAMaterial:
	var m := DAMaterial.new()
	m.kind = kind
	m.mats = self
	return m

# ------------------------------------------------------------------------------------------------ toon
# Cartoon standard material (see header for opts).
func toon(color = "#ffffff", opts: Dictionary = {}) -> DAMaterial:
	var hex := _hex(color)
	var p := {
		"rough": _o(opts, "rough", 0.75),
		"metal": _o(opts, "metal", 0.0),
		"emissive": _o(opts, "emissive", null),
		"emissiveIntensity": _o(opts, "emissiveIntensity", 1.0),
		"rim": _o(opts, "rim", 0.35),
		"rimColor": _o(opts, "rimColor", "#FFE9CC"),
		"rimPower": _o(opts, "rimPower", 2.4),
		"wrap": _o(opts, "wrap", 0.5),
		"steps": _o(opts, "steps", 0.0),
		"map": _o(opts, "map", null),
		"transparent": _t(opts.get("transparent")),
		"opacity": _o(opts, "opacity", 1.0),
		"side": _side(_o(opts, "side", FrontSide)),
		"flat": _t(opts.get("flat")),
		"keepColor": _t(opts.get("keepColor")),
		"heroFade": _t(opts.get("heroFade")),
		"vertexColors": _t(opts.get("vertexColors")),
		"env": _o(opts, "env", null),
		"alphaTest": _o(opts, "alphaTest", 0.0),
		"depthWrite": _o(opts, "depthWrite", true),
		"fog": _o(opts, "fog", true),
		"name": _o(opts, "name", ""),
	}
	for k in ["mapWrap", "mapFilter", "mapFlipY"]:
		if opts.get(k) != null:
			p[k] = opts[k]
	var key := _key("toon", hex, p)
	var mat = _cache.get(key)
	if mat != null:
		return mat

	mat = _newMat("toon")
	mat.variantKey = {"transparent": p.transparent, "side": p.side, "depthWrite": _t(p.depthWrite), "additive": false, "ext": ""}
	_applyVariant(mat)
	mat.color = DAU.color(hex)
	mat.setParam("uRough", float(p.rough))
	mat.setParam("uMetal", float(p.metal))
	mat.opacity = float(p.opacity)
	mat.setParam("uFlat", 1.0 if p.flat else 0.0)
	mat.vertexColors = p.vertexColors
	mat.alphaTest = float(p.alphaTest)
	mat.name = p.name if str(p.name) != "" else "toon:%s" % hex
	if _t(p.emissive):
		mat.emissive = DAU.color(p.emissive)
		mat.emissiveIntensity = float(p.emissiveIntensity)
	var envAmount: float
	if p.env != null:
		envAmount = float(p.env)
	elif float(p.metal) > 0.0:
		envAmount = 1.0
	elif float(p.rough) < 0.5:
		envAmount = 0.3 * (1.0 - float(p.rough))
	else:
		envAmount = 0.0
	mat.setParam("uEnv", maxf(0.0, envAmount))
	_patchToon(mat, p)
	mat.userData["daToon"] = {"color": hex, "params": p}
	mat.mapWrap = str(p.get("mapWrap", ""))
	mat.mapFilter = str(p.get("mapFilter", ""))
	var tex = p.map
	if tex != null and p.has("mapFlipY"):
		tex.set_meta("flipY", _t(p.mapFlipY))
	mat.map = tex
	_cache[key] = mat
	return mat

func _patchToon(mat, p: Dictionary) -> void:
	var local := {
		"uWrap": float(p.wrap),
		"uSteps": float(p.steps),
		"uRimStrength": float(p.rim),
		"uRimPower": float(p.rimPower),
		"uRimColor": DAU.color(p.rimColor),
		"uKeep": 1.0 if p.keepColor else 0.0,     # keepColor: skip the pre-power grade / colour wave
		"uFogK": 1.0 if _t(p.fog) else 0.0,        # fog:false
		"uDaFade": 1.0 if p.heroFade else 0.0,     # heroFade: dithered by uHeroFade, never occlusion-faded (2: neither)
	}
	var U := {}
	for k in local:
		U[k] = DAMat.DAUniform.new(k, local[k], mat)
		mat.setParam(k, local[k])
	mat.userData["uniforms"] = U

# Actors never take part in the camera-occlusion fade (a zombie behind the hero stays solid, attachments included):
# flags every plain toon material under root (uDaFade 0 -> 2; hero-fade materials keep theirs). camera.gd calls it
# for spawned zombies and the boss. A material shared with level props stops fading there too (none known).
func noOcclusion(root) -> void:
	if root == null or not (root is Node):
		return
	DAU.traverse(root, func(o):
		for m in meshMaterials(o):
			if m is DAMaterial:
				var u = m.userData.get("uniforms")
				if u is Dictionary and u.has("uDaFade") and float(u.uDaFade.value) == 0.0:
					u.uDaFade.value = 2.0)

# Same material with some params overridden (e.g. {heroFade:true}); non-toon materials are returned as-is.
func variant(mat, extra: Dictionary):
	if not (mat is DAMaterial):
		return mat
	var d = mat.userData.get("daToon")
	if d == null:
		return mat
	var p: Dictionary = d.params.duplicate()
	p.merge(extra, true)
	return toon(d.color, p)

# Swap every toon material under `root` to its heroFade variant (the player's hero + held weapon).
# Meshes with other materials get userData.daHideOnFade so the player can hide them when faded.
func applyHeroFade(root) -> void:
	DAU.traverse(root, func(o):
		if not (o is MeshInstance3D):
			return
		var n := meshMaterialCount(o)
		for i in n:
			var m = meshMaterial(o, i)
			if m is DAMaterial and m.userData.has("daToon"):
				setMeshMaterial(o, i, variant(m, {"heroFade": true}))
			else:
				DAU.ud(o)["daHideOnFade"] = true)

# ------------------------------------------------------------------------------------------------ mesh material slots
# JS mesh.material on a Godot MeshInstance3D: material_override when set (geo.mesh), else the surface override,
# else the mesh's own surface material.
static func meshMaterialCount(o) -> int:
	if not (o is MeshInstance3D):
		return 0
	if o.material_override != null or o.mesh == null:
		return 1 if o.material_override != null else 0
	return o.mesh.get_surface_count()

static func meshMaterial(o, i := 0) -> Material:
	if o.material_override != null:
		return o.material_override
	var m: Material = o.get_surface_override_material(i)
	if m == null and o.mesh != null and i < o.mesh.get_surface_count():
		m = o.mesh.surface_get_material(i)
	return m

static func setMeshMaterial(o, i: int, m: Material) -> void:
	if o.material_override != null:
		o.material_override = m
	else:
		o.set_surface_override_material(i, m)

static func meshMaterials(o) -> Array:
	var out: Array = []
	for i in meshMaterialCount(o):
		var m := meshMaterial(o, i)
		if m != null:
			out.append(m)
	return out

# ------------------------------------------------------------------------------------------------ unlit
# Unlit HDR emissive (bloom threshold is ~0.8). opts: { transparent, opacity, additive, map, fog=true, side }
func glow(color = "#ffffff", intensity := 2.0, opts: Dictionary = {}) -> DAMaterial:
	var kp := {"intensity": intensity}
	kp.merge(opts, true)
	var key := _key("glow", color, kp)
	var mat = _cache.get(key)
	if mat != null:
		return mat
	mat = _newMat("glow")
	var additive := _t(opts.get("additive"))
	mat.variantKey = {"transparent": _t(opts.get("transparent")) or additive, "side": _side(_o(opts, "side", FrontSide)),
		"depthWrite": not additive, "additive": additive, "ext": ""}
	_applyVariant(mat)
	mat.color = DAU.color(color)
	mat.intensity = float(intensity)
	mat.opacity = float(_o(opts, "opacity", 1.0))
	mat.name = "glow:%s" % str(color)
	var fk := DAMat.DAUniform.new("uFogK", 1.0 if _t(_o(opts, "fog", true)) else 0.0, mat)
	mat.setParam("uFogK", fk.value)
	mat.userData["daFogK"] = fk
	for k in ["mapWrap", "mapFilter"]:
		if opts.get(k) != null:
			mat.set(k, str(opts[k]))
	var tex = _o(opts, "map", null)
	if tex != null and opts.get("mapFlipY") != null:
		tex.set_meta("flipY", _t(opts.mapFlipY))
	mat.map = tex
	_cache[key] = mat
	return mat

# Plain unlit color (UI-ish props, backdrops). Cached. opts: MeshBasicMaterial options (map, fog, vertexColors,
# transparent, opacity, side, depthWrite, alphaTest, blending, name).
func basic(color = "#ffffff", opts: Dictionary = {}) -> DAMaterial:
	var key := _key("basic", color, opts)
	var mat = _cache.get(key)
	if mat != null:
		return mat
	mat = _newMat("basic")
	var bl = opts.get("blending")
	var additive: bool = bl == AdditiveBlending or bl == "additive"
	mat.variantKey = {"transparent": _t(opts.get("transparent")) or additive, "side": _side(_o(opts, "side", FrontSide)),
		"depthWrite": _t(_o(opts, "depthWrite", true)), "additive": additive, "ext": ""}
	_applyVariant(mat)
	mat.color = DAU.color(color)
	mat.setParam("uIntensity", 1.0)
	mat.opacity = float(_o(opts, "opacity", 1.0))
	mat.vertexColors = _t(opts.get("vertexColors"))
	mat.alphaTest = float(_o(opts, "alphaTest", 0.0))
	mat.setParam("uFogK", 1.0 if _t(_o(opts, "fog", true)) else 0.0)
	mat.name = str(_o(opts, "name", ""))
	for k in ["mapWrap", "mapFilter"]:
		if opts.get(k) != null:
			mat.set(k, str(opts[k]))
	var tex = _o(opts, "map", null)
	if tex != null and opts.get("mapFlipY") != null:
		tex.set_meta("flipY", _t(opts.mapFlipY))
	mat.map = tex
	_cache[key] = mat
	return mat

# Transparent glossy glass (display cases, booth glass, aviators). Cached.
func glass(color = "#CFE8FF", opts: Dictionary = {}) -> DAMaterial:
	return toon(color, {
		"rough": 0.05, "transparent": true, "opacity": _o(opts, "opacity", 0.22), "rim": 0.6, "rimColor": "#ffffff",
		"rimPower": 2.0, "env": 1.2, "depthWrite": false, "keepColor": _o(opts, "keepColor", true),
		"side": _o(opts, "side", DoubleSide), "name": "glass",
	})

# Skin: softer wrap, warm rim, always full color.
func skin(tone = "#F2B48C", opts: Dictionary = {}) -> DAMaterial:
	var o := {"rough": 0.58, "wrap": 0.7, "rim": 0.35, "rimColor": Config.PAL.rimHero, "keepColor": true}
	o.merge(opts, true)
	return toon(tone, o)

# props/sponsors.js bubbleMat: additive fresnel shell of the power-up drops. Cached.
func bubble(color = "#ffffff", intensity := 1.1) -> DAMaterial:
	var key := _key("bubble", color, {"intensity": intensity})
	var mat = _cache.get(key)
	if mat != null:
		return mat
	mat = _newMat("bubble")
	mat.shader = load("res://shaders/bubble.gdshader")
	mat.variantKey = {"transparent": true, "side": FrontSide, "depthWrite": false, "additive": true, "ext": ""}
	mat.color = DAU.color(color)
	mat.intensity = float(intensity)
	mat.uniforms = {"uColor": DAMat.DAUniform.new("uColor", mat.color, mat), "uTime": uniforms.uTime,
		"uIntensity": DAMat.DAUniform.new("uIntensity", float(intensity), mat)}
	mat.name = "bubble:%s" % str(color)
	_cache[key] = mat
	return mat

# ------------------------------------------------------------------------------------------------ screens
# CRT screen material (NOT cached: ScreenManager swaps `.map` per screen at runtime).
# opts: { bulge=0, barrel=0.06, scan=0.35, bright=1.35, chroma=1.5 (px), vignette=0.8, gloss=1, lines=120,
#         w=1, h=0.75 (plane size, for the bulge normal) }
func screen(texture = null, opts: Dictionary = {}) -> DAMaterial:
	var mat := _newMat("screen")
	mat.shader = load("res://shaders/screen.gdshader")
	var u := {
		"uBulge": float(_o(opts, "bulge", 0.0)),
		"uWobble": 0.0,
		"uSize": Vector2(float(_o(opts, "w", 1.0)), float(_o(opts, "h", 0.75))),
		"uBarrel": float(_o(opts, "barrel", 0.06)),
		"uScan": float(_o(opts, "scan", 0.35)),
		"uBright": float(_o(opts, "bright", 1.35)),
		"uChroma": float(_o(opts, "chroma", 1.5)),
		"uVignette": float(_o(opts, "vignette", 0.8)),
		"uGloss": float(_o(opts, "gloss", 1.0)),
		"uLines": float(_o(opts, "lines", 120.0)),
		"uTexel": Vector2(1.0 / 256.0, 1.0 / 256.0),
		"uTint": Color(1, 1, 1),
	}
	for k in u:
		mat.uniforms[k] = DAMat.DAUniform.new(k, u[k], mat)
		mat.setParam(k, u[k])
	mat.uniforms["uTime"] = uniforms.uTime
	for k in uniforms:
		if str(k).begins_with("uOcc"):
			mat.uniforms[k] = uniforms[k]
	mat.name = "crt"
	mat.map = texture
	return mat

# Rubber-glass screen (GDD §3.5): animate mat.uniforms.uBulge.value (0..0.35 m) / uWobble (0..1).
func rubberGlass(texture = null, opts: Dictionary = {}) -> DAMaterial:
	var o := {"bulge": 0.03, "barrel": 0.04, "scan": 0.3}
	o.merge(opts, true)
	return screen(texture, o)

# Plane subdivided 24x18 for bulging screens (cached per size).
func screenGeometry(w := 0.8, h := 0.6) -> Mesh:
	return DAGeo.plane(w, h, 24, 18)

# ------------------------------------------------------------------------------------------------ Chromacast patches
# ext "chroma": props/weapons.js patchChroma (uniforms uChHue, uChSpread, uChLen, uChDark; chromaUV coordinates in
# UV); ext "cc": game/weaponModels.js patchCC (uCcHue, uCcSpread; object-space position). Values may be numbers,
# {value: x} dictionaries or DAUniform facades. The facades land in mat.userData.chroma / .chromacast (the JS guard).
func patchShader(mat, ext: String, u: Dictionary) -> void:
	if mat == null or not (mat is DAMaterial) or mat.kind != "toon":
		return
	var slot := "chroma" if ext == "chroma" else "chromacast"
	if mat.userData.has(slot):
		return
	mat.variantKey.ext = ext
	_applyVariant(mat)
	var F := {}
	for k in u:
		var v = u[k]
		if v is DAMat.DAUniform:
			v = v.value
		elif v is Dictionary and v.has("value"):
			v = v.value
		F[k] = DAMat.DAUniform.new(k, v, mat)
		mat.setParam(k, v)
	mat.userData[slot] = F

# ------------------------------------------------------------------------------------------------ Blender specs
# SPEC §5.5: the material a Blender "da" spec describes, built with the same factory the JS used; the albedo texture
# comes from the imported glTF material (or spec.mapFile), a gfx card (spec.card) is drawn by cards.gd.
# Cached per spec + texture (screens are never cached: ScreenManager swaps their map per screen).
func fromSpec(spec, importedMaterial = null) -> Material:
	if spec is String:
		spec = JSON.parse_string(spec)
	if not (spec is Dictionary):
		return importedMaterial
	var kind := str(spec.get("kind", "toon"))
	var color = spec.get("color", "#ffffff")
	if color == null:
		color = "#ffffff"
	var opts: Dictionary = (spec.get("opts") if spec.get("opts") is Dictionary else {}).duplicate(true)
	var tex: Texture2D = null
	var fromCard := false
	if spec.get("card") != null:
		tex = _cardTexture(str(spec.card), spec.get("cardOpts") if spec.get("cardOpts") is Dictionary else {})
		fromCard = true
	elif spec.get("map") != null or spec.get("mapFile") != null:
		if importedMaterial is BaseMaterial3D and importedMaterial.albedo_texture != null:
			tex = importedMaterial.albedo_texture
		elif spec.get("mapFile") != null and ResourceLoader.exists(str(spec.mapFile)):
			tex = load(str(spec.mapFile))
		elif not _warned.has("map:%s" % spec.get("map")):
			_warned["map:%s" % spec.get("map")] = true
			push_warning("[materials] fromSpec: texture '%s' not found" % spec.get("map"))
	var ckey := ""
	if kind != "screen" and kind != "rubberGlass":
		ckey = "%s|%d" % [JSON.stringify(spec), tex.get_instance_id() if tex != null else 0]
		var hit = _specCache.get(ckey)
		if hit != null:
			return hit
	if tex != null and kind != "screen" and kind != "rubberGlass":
		opts["map"] = tex
		if not fromCard:
			if spec.get("mapWrap") != null:
				opts["mapWrap"] = str(spec.mapWrap)
			if spec.get("mapFilter") != null:
				opts["mapFilter"] = str(spec.mapFilter)
			opts["mapFlipY"] = _t(spec.get("flipY", true))
		elif opts.get("mapWrap") == null:
			opts["mapWrap"] = "clamp"
	var mat
	match kind:
		"toon":
			mat = toon(color, opts)
		"glass":
			mat = glass(color, opts)
		"skin":
			mat = skin(color, opts)
		"glow":
			var it = _o(opts, "intensity", 2.0)
			opts.erase("intensity")
			mat = glow(color, float(it), opts)
		"basic":
			mat = basic(color, opts)
		"bubble":
			mat = bubble(color, float(_o(opts, "intensity", 1.1)))
		"chromacast":
			mat = toon(color, opts)
			var ch = spec.get("chroma")
			if ch == null:
				ch = opts.get("chroma")
			patchShader(mat, "chroma", ch if ch is Dictionary else {})
		"screen", "rubberGlass":
			var so: Dictionary = spec.get("screen") if spec.get("screen") is Dictionary else {}
			var o := opts.duplicate()
			for k in ["w", "h", "bulge", "bright"]:
				if so.get(k) != null:
					o[k] = so[k]
			mat = rubberGlass(tex, o) if kind == "rubberGlass" else screen(tex, o)
			mat.userData["screen"] = so
		_:
			if not _warned.has("kind:" + kind):
				_warned["kind:" + kind] = true
				push_warning("[materials] fromSpec: unknown kind '%s' (toon used)" % kind)
			mat = toon(color, opts)
	if spec.get("userData") is Dictionary:
		mat.userData.merge(spec.userData, true)
	if ckey != "":
		_specCache[ckey] = mat
	return mat

func _cardTexture(id: String, opts: Dictionary) -> Texture2D:
	var C = game.cards
	if C == null:
		return null
	if C is Object and C.has_method("getCard"):
		return C.getCard(id, opts)
	if C is Object and C.has_method("get_"):
		return C.get_(id, opts)
	if C is Dictionary and C.get("getCard") is Callable:
		return C.getCard.call(id, opts)
	return null
