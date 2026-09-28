# Character materials for baked SDF characters (port of src/art/charMaterial.js).
#   CharMaterial.createCharMaterial({ header, rim, envMap, globals, heroFade, aoAmount, iblDiffuse }) -> DAMaterial
#     (shaders/char.gdshader; one per character type, shared by the skinned body and its rigid parts). Per-vertex
#     inputs from the baker: colour (sRGB) + ao, cavity, material id, pattern mode, pattern coords, triplanar weights,
#     hair flow, packed morph colour deltas (blender/chars/FORMAT.md §4).
#   Per-material params (header.materials[name]): color, rough, metal, wrap, sss (skin scatter), fuzz (fabric sheen),
#     aniso (hair strand highlight), sheen + sheenExp (molded-toy hair: one broad glossy band across the flow),
#     spec (specular scale), lines (draw stitch lines), bump, cav (cavity strength), pattern.
#   Shading: half-lambert wrap, warm subsurface in the terminator, baked AO + cavity, fabric patterns sampled in REST
#     space (never swim), stitch/seam lines, Kajiya-Kay strand highlights, fresnel rim (warm heroes / cyan zombies).
#   CharMaterial.attachMaterial(opts) -> simpler material for rigid attachments (eyes, glasses, lids), cached by params
#     (shaders/char_attach.gdshaderinc variants).
#   CharMaterial.basicMaterial(opts, tex) -> THREE.MeshBasicMaterial equivalent (glints, static eyes, veils, rims:
#     godot-core's shaders/unlit.gdshaderinc).
#   CharMaterial.fromSpec(spec, imported, rimColor) -> the material of a GLB attachment surface from its "da" spec.
# Globals: uRimAmbient / uHeroFade are RenderingServer global shader parameters (godot-core declares them in
#   project.godot; ensureGlobals() adds them when missing, e.g. in isolated tests). `globals` / `envMap` options are
#   accepted for API compatibility: the globals are always shared; envMap == false disables the RoomEnvironment IBL
#   (daEnvMap global), any other value (the JS passed game.mats.envMap) keeps it.
# Every material is a DAMaterial (scripts/core/da_material.gd, godot-core): the JS-like facade (mat.color, mat.emissive,
#   mat.map, mat.opacity, mat.userData, mat.uniforms, mat.name, mat.clone()) works on character materials too (the
#   zombie tints poke mat.color / mat.emissive of the body material). kind: "char" | "attach" | "basic".
# Pattern tiles come as PNGs (godot/assets/chars/patterns) and are assembled into a Texture2DArray per layer list.
class_name CharMaterial
extends RefCounted

const NMAT := 24
const CHAR_SHADER := preload("res://shaders/char.gdshader")

static var _patternCache := {}
static var _attachCache := {}
static var _shaderCache := {}
static var _globalsChecked := false

# The global uniforms this module's shaders read (godot-core's shaders/da_common.gdshaderinc declares all of them).
const _GLOBALS := {
	"uSatEnv": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.7], "uAmber": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.08],
	"uWaveOrigin": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO], "uWaveRadius": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, -1.0],
	"uTime": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0], "uHeroFade": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
	"uRimAmbient": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0], "uOccRect": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO],
	"uOccZ": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO], "uOccAmt": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
	"uOccBox0": [RenderingServer.GLOBAL_VAR_TYPE_MAT4, Projection()], "uOccBox1": [RenderingServer.GLOBAL_VAR_TYPE_MAT4, Projection()],
	"uOccWall0": [RenderingServer.GLOBAL_VAR_TYPE_MAT4, Projection()], "uOccWall1": [RenderingServer.GLOBAL_VAR_TYPE_MAT4, Projection()],
	"daOccCam": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO], "daFogColor": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO],
	"daFogNear": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1000.0], "daFogFar": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 2000.0],
	"daEnvMap": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null], "daDFG": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null],
}

static func ensureGlobals() -> void:
	if _globalsChecked:
		return
	_globalsChecked = true
	for k in _GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + k):
			var e: Array = _GLOBALS[k]
			var v = e[1]
			if v == null:
				var img := Image.create(4, 4, false, Image.FORMAT_RGBAF)
				img.fill(Color(0, 0, 0, 1))
				v = ImageTexture.create_from_image(img)
			RenderingServer.global_shader_parameter_add(k, e[0], v)

# '#hex' (sRGB) or [r, g, b] LINEAR floats (JS new Color(r, g, b)) -> sRGB Color for source_color uniforms.
static func srgbColor(c) -> Color:
	if c is Array:
		return Color(DAU.linearToSrgb(float(c[0])), DAU.linearToSrgb(float(c[1])), DAU.linearToSrgb(float(c[2])))
	if c is Color:
		return c
	return DAU.color(c)

static func _f(o: Dictionary, k: String, d: float) -> float:
	var v = o.get(k)
	return float(v) if v != null and not (v is bool) else d

# ------------------------------------------------------------------------------------------------ patterns
# patterns.js patternLayers: one Texture2DArray layer per distinct pattern (the baker already resolved the layers:
# header.patterns = { size, layers: [file], layerOf: [layer | -1 per matNames index] }).
static func patternLayers(header: Dictionary) -> Dictionary:
	var P = header.get("patterns")
	var layers: Array = P.get("layers", []) if P is Dictionary else []
	var layerOf: Array = P.get("layerOf", []) if P is Dictionary else []
	var key := "|".join(PackedStringArray(layers.map(func(x): return str(x)))) if not layers.is_empty() else "none"
	var tex = _patternCache.get(key)
	if tex == null:
		var images: Array[Image] = []
		for f in layers:
			var img := _loadPattern("res://assets/chars/" + str(f))
			if img == null:
				img = Image.create(512, 512, false, Image.FORMAT_RGBA8)
				img.fill(Color(1, 1, 1, 1))
			images.append(img)
		if images.is_empty():
			var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
			img.fill(Color(1, 1, 1, 1))
			images.append(img)
		for img in images:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			if not img.has_mipmaps():
				img.generate_mipmaps()
		var arr := Texture2DArray.new()
		arr.create_from_images(images)
		tex = arr
		_patternCache[key] = tex
	return {"texture": tex, "layerOf": layerOf}

# The exact pixels of the PNG (alpha = height: an imported texture may alter RGB under alpha 0 or compress it).
static func _loadPattern(path: String) -> Image:
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			var img := Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				return img
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			var img: Image = (t as Texture2D).get_image()
			if img != null and img.is_compressed():
				img.decompress()
			return img
	push_warning("[charMaterial] pattern tile missing: " + path)
	return null

# ------------------------------------------------------------------------------------------------ stitch lines
static func linesTexture(stitches: Array, chunks: Array) -> ImageTexture:
	var n: int = maxi(1, stitches.size())
	var w: int = n * 4 + chunks.size() * 2 + 1
	var data := PackedFloat32Array()
	data.resize(w * 4)
	for i in stitches.size():
		var s: Array = stitches[i]
		var c := DAU.color(s[10])
		var lin := Color(DAU.srgbToLinear(c.r), DAU.srgbToLinear(c.g), DAU.srgbToLinear(c.b))
		var mask := 0
		var mats = s[11] if s.size() > 11 else null
		if mats is Array:
			for m in mats:
				mask |= 1 << int(m)
		var vals := [s[0], s[1], s[2], s[7], s[3], s[4], s[5], s[6], lin.r, lin.g, lin.b, s[8], s[9], mask, 0, 0]
		for k in 16:
			data[i * 16 + k] = float(vals[k])
	for i in chunks.size():
		var c: Array = chunks[i]
		var o: int = (stitches.size() * 4 + i * 2) * 4
		for k in 6:
			data[o + k] = float(c[k])
	var img := Image.create_from_data(w, 1, false, Image.FORMAT_RGBAF, data.to_byte_array())
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------------------------------------ body material
# o: { header, rim, envMap, globals, heroFade, aoAmount = 1, iblDiffuse = 0.3 }
static func createCharMaterial(o: Dictionary) -> DAMaterial:
	ensureGlobals()
	var header: Dictionary = o.header
	var matNames: Array = header.get("matNames", [])
	var materials: Dictionary = header.get("materials", {})
	var mats := []
	for n in matNames:
		mats.append(materials.get(n, {}))
	var pl := patternLayers(header)
	var layerOf: Array = pl.layerOf
	var A := PackedVector4Array()
	var B := PackedVector4Array()
	var C := PackedVector4Array()
	var D := PackedVector4Array()
	for i in NMAT:
		var m: Dictionary = mats[i] if i < mats.size() else {}
		var pat = m.get("pattern")
		var layer := float(layerOf[i]) if i < layerOf.size() and layerOf[i] != null else -1.0
		var pscale := 0.1
		if pat is Dictionary and pat.get("scale") != null and float(pat.scale) != 0.0:
			pscale = float(pat.scale)
		A.append(Vector4(_f(m, "rough", 0.6), _f(m, "metal", 0.0), layer, pscale))
		B.append(Vector4(_f(m, "wrap", 0.45), _f(m, "sss", 0.0), _f(m, "fuzz", 0.0), _f(m, "aniso", 0.0)))
		C.append(Vector4(_f(m, "spec", 1.0), 1.0 if Rig.truthy(m.get("lines")) else 0.0, _f(m, "bump", 0.35 if pat != null else 0.0), _f(m, "cav", 1.0)))
		D.append(Vector4(_f(m, "sheen", 0.0), _f(m, "sheenExp", 70.0), 0.0, 0.0))
	var stitches: Array = header.get("stitches", []) if header.get("stitches") != null else []
	var chunks: Array = header.get("stitchChunks", []) if header.get("stitchChunks") != null else []
	var kind: String = header.get("kind", "hero") if header.get("kind") != null else "hero"
	var rim = o.get("rim")
	var rimC = rim.get("color") if rim is Dictionary and rim.get("color") != null else ("#8FF3FF" if kind == "zombie" else "#FFD9A0")
	var rimS: float = float(rim.strength) if rim is Dictionary and rim.get("strength") != null else (0.3 if kind == "zombie" else 0.35)
	var mat := DAMaterial.new()
	mat.kind = "char"
	mat.shader = CHAR_SHADER
	mat.name = "char:%s" % header.get("id", "")
	mat.set_shader_parameter("uMatA", A)
	mat.set_shader_parameter("uMatB", B)
	mat.set_shader_parameter("uMatC", C)
	mat.set_shader_parameter("uMatD", D)
	mat.set_shader_parameter("uPatterns", pl.texture)
	mat.set_shader_parameter("uLines", linesTexture(stitches, chunks))
	mat.set_shader_parameter("uLineCount", stitches.size())
	mat.set_shader_parameter("uChunkCount", chunks.size())
	mat.set_shader_parameter("uRimColor", srgbColor(rimC))
	mat.set_shader_parameter("uRimStrength", rimS)
	mat.set_shader_parameter("uAOAmount", _f(o, "aoAmount", 1.0))
	mat.set_shader_parameter("uDebug", 0)
	mat.set_shader_parameter("uIBLDiffuse", _f(o, "iblDiffuse", 0.3))
	mat.set_shader_parameter("uEnv", 0.0 if (o.get("envMap") is bool and o.envMap == false) else 0.8)
	mat.set_shader_parameter("uFade", 1.0 if Rig.truthy(o.get("heroFade")) else 0.0)
	mat.color = Color(1, 1, 1)
	mat.emissive = Color(0, 0, 0)
	# JS mat.userData.uniforms (local uniforms + the shared globals), as DAMaterial uniform facades
	var U := {}
	for n in ["uMatA", "uMatB", "uMatC", "uMatD", "uPatterns", "uLines", "uLineCount", "uChunkCount", "uRimColor", "uRimStrength",
			"uAOAmount", "uDebug", "uIBLDiffuse"]:
		U[n] = DAMaterial.DAUniform.new(n, mat.get_shader_parameter(n), mat)
	for n in ["uRimAmbient", "uHeroFade"]:
		U[n] = DAMaterial.DAUniform.new(n, 1.0, null, true)
	mat.userData.uniforms = U
	return mat

# ------------------------------------------------------------------------------------------------ attachments
static func _variantShader(include: String, modes: String, defines: Array) -> Shader:
	var key := include + "|" + modes + "|" + ",".join(PackedStringArray(defines))
	var sh = _shaderCache.get(key)
	if sh == null:
		var code := "shader_type spatial;\nrender_mode %s;\n" % modes
		for d in defines:
			code += "#define %s\n" % d
		code += "#include \"%s\"\n" % include
		sh = Shader.new()
		sh.code = code
		_shaderCache[key] = sh
	return sh

static func _cull(side) -> String:
	if side is String:
		return {"front": "cull_back", "back": "cull_front", "double": "cull_disabled"}.get(side, "cull_back")
	if side is int or side is float:
		return ["cull_back", "cull_front", "cull_disabled"][clampi(int(side), 0, 2)]
	return "cull_back"

# attachMaterial(o): o = { color, rough, metal, map (Texture2D), mapWrap, mapFilter, flipY, transparent, opacity, depthWrite, side,
#   envMap, envIntensity, emissive, emissiveIntensity, vertexColors, polygonOffset, physical, clearcoat,
#   clearcoatRough, rimColor, rim, globals, wrap, sss, iblDiffuse, renderOrder }
static func attachMaterial(o: Dictionary = {}) -> DAMaterial:
	ensureGlobals()
	var ko := {}
	for k in o:
		var v = o[k]
		ko[k] = ("tex:%d" % v.get_instance_id()) if v is Texture2D else (Rig.truthy(v) if k == "globals" else v)
	var key := JSON.stringify(ko, "", true)
	var m = _attachCache.get(key)
	if m != null:
		return m
	var transparent := Rig.truthy(o.get("transparent"))
	var dw = o.get("depthWrite")
	var depthWrite: bool = (dw as bool) if dw is bool else not transparent
	var modes := "%s, %s, blend_mix, fog_disabled, shadows_disabled" % [_cull(o.get("side")),
		("depth_draw_always" if depthWrite else "depth_draw_never") if transparent else ("depth_draw_opaque" if depthWrite else "depth_draw_never")]
	var defines := []
	if transparent:
		defines.append("DA_TRANSPARENT")
	if _cull(o.get("side")) == "cull_front":
		defines.append("DA_BACK")
	var physical := Rig.truthy(o.get("physical"))
	if physical:
		defines.append("DA_CC")
	m = DAMaterial.new()
	m.kind = "attach"
	m.shader = _variantShader("res://shaders/char_attach.gdshaderinc", modes, defines)
	m.variantKey = {"transparent": transparent, "side": _sideInt(o.get("side")), "depthWrite": depthWrite, "additive": false, "ext": ""}
	m.color = srgbColor(o.get("color", "#ffffff") if o.get("color") != null else "#ffffff")
	m.set_shader_parameter("uOpacity", _f(o, "opacity", 1.0))
	m.set_shader_parameter("uRough", _f(o, "rough", 0.5))
	m.set_shader_parameter("uMetal", _f(o, "metal", 0.0))
	m.emissive = srgbColor(o.get("emissive") if o.get("emissive") != null else "#000000")
	m.set_shader_parameter("uEmissiveIntensity", _f(o, "emissiveIntensity", 1.0))
	var env = o.get("envMap")
	m.set_shader_parameter("uEnv", 0.0 if (env == null or (env is bool and env == false)) else _f(o, "envIntensity", 1.0))
	m.set_shader_parameter("uVColor", 1.0 if Rig.truthy(o.get("vertexColors")) else 0.0)
	m.set_shader_parameter("uRimColor", srgbColor(o.get("rimColor") if o.get("rimColor") != null else "#FFD9A0"))
	m.set_shader_parameter("uRimStrength", _f(o, "rim", 0.3))
	m.set_shader_parameter("uWrapA", _f(o, "wrap", 0.45))
	m.set_shader_parameter("uSSSA", _f(o, "sss", 0.0))
	m.set_shader_parameter("uIBLA", _f(o, "iblDiffuse", 0.3))
	if physical:
		m.set_shader_parameter("uClearcoat", _f(o, "clearcoat", 1.0))
		m.set_shader_parameter("uClearcoatRough", _f(o, "clearcoatRough", 0.05))
	_setMapTex(m, o)
	m.render_priority = clampi(int(_f(o, "renderOrder", 0.0)), -128, 127)
	var U := {}
	for n in ["uRimColor", "uRimStrength", "uWrapA", "uSSSA", "uIBLA"]:
		U[n] = DAMaterial.DAUniform.new(n, m.get_shader_parameter(n), m)
	U["uRimAmbient"] = DAMaterial.DAUniform.new("uRimAmbient", 1.0, null, true)
	m.userData.uniforms = U
	_attachCache[key] = m
	return m

static func _sideInt(side) -> int:
	return {"cull_back": 0, "cull_front": 1, "cull_disabled": 2}.get(_cull(side), 0)

# The canvas texture of a GLB material: o.map (Texture2D), o.mapWrap ("repeat"|"clamp"), o.mapFilter
# ("linear"|"nearest"), o.flipY (three's flipY: the PNG is stored top-down as drawn -> sample at (u, 1 - v)).
static func _setMapTex(m: DAMaterial, o: Dictionary) -> void:
	var tex = o.get("map")
	if tex is Texture2D:
		m.mapWrap = str(o.get("mapWrap")) if o.get("mapWrap") != null else "clamp"
		m.mapFilter = str(o.get("mapFilter")) if o.get("mapFilter") != null else "linear"
		var t: Texture2D = tex
		t.set_meta("flipY", Rig.truthy(o.get("flipY")))
		m.map = t

# THREE.MeshBasicMaterial: o = { color ('#hex' | [r,g,b] linear), map (Texture2D), transparent, opacity,
#   depthWrite, side, vertexColors, name, renderOrder, mapWrap, mapFilter, flipY }. (toneMapped:false cannot be honoured
#   per material.)
static func basicMaterial(o: Dictionary = {}) -> DAMaterial:
	ensureGlobals()
	var ko := {}
	for k in o:
		var v = o[k]
		ko[k] = ("tex:%d" % v.get_instance_id()) if v is Texture2D else v
	var key := "basic|" + JSON.stringify(ko, "", true)
	var m = _attachCache.get(key)
	if m != null:
		return m
	var transparent := Rig.truthy(o.get("transparent"))
	var dw = o.get("depthWrite")
	var depthWrite: bool = (dw as bool) if dw is bool else true
	var modes := "unshaded, fog_disabled, %s, %s, blend_mix" % [_cull(o.get("side")),
		("depth_draw_always" if depthWrite else "depth_draw_never") if transparent else ("depth_draw_opaque" if depthWrite else "depth_draw_never")]
	var defines := []
	if transparent:
		defines.append("DA_TRANSPARENT")
	m = DAMaterial.new()
	m.kind = "basic"
	m.shader = _variantShader("res://shaders/unlit.gdshaderinc", modes, defines)
	m.variantKey = {"transparent": transparent, "side": _sideInt(o.get("side")), "depthWrite": depthWrite, "additive": false, "ext": ""}
	m.color = srgbColor(o.get("color") if o.get("color") != null else "#ffffff")
	m.set_shader_parameter("uIntensity", 1.0)
	m.set_shader_parameter("uOpacity", _f(o, "opacity", 1.0))
	m.set_shader_parameter("uFogK", 1.0)
	m.set_shader_parameter("uVColor", 1.0 if Rig.truthy(o.get("vertexColors")) else 0.0)
	m.set_shader_parameter("uMapFlip", 0.0)
	_setMapTex(m, o)
	if o.get("name") != null:
		m.name = str(o.name)
	m.render_priority = clampi(int(_f(o, "renderOrder", 0.0)), -128, 127)
	_attachCache[key] = m
	return m

# GLB attachment surface -> material. spec = material extras "da" (FORMAT.md §5), imported = the glTF material (its
# albedo texture is the JS canvas texture). ctx: { rimColor (builder default), envMap, renderOrder }.
static func fromSpec(spec: Dictionary, imported: Material, ctx: Dictionary = {}) -> Material:
	var o: Dictionary = (spec.get("opts", {}) as Dictionary).duplicate() if spec.get("opts") is Dictionary else {}
	# the factory colour argument sits at the spec top level (FORMAT.md §5); opts.color wins (basic: linear floats)
	if o.get("color") == null and spec.get("color") != null:
		o.color = spec.color
	o.erase("map")
	# the canvas texture: extras mapFile, else the glTF baseColorTexture (embedded)
	var tex: Texture2D = null
	var f = spec.get("mapFile")
	if f is String and f != "" and ResourceLoader.exists(f):
		tex = load(f)
	if tex == null and imported is BaseMaterial3D:
		tex = (imported as BaseMaterial3D).albedo_texture
	if tex != null:
		o.map = tex
		o.mapWrap = spec.get("mapWrap") if spec.get("mapWrap") != null else "clamp"   # three CanvasTexture default
		o.mapFilter = spec.get("mapFilter") if spec.get("mapFilter") != null else "linear"
		o.flipY = spec.get("flipY") if spec.get("flipY") != null else true   # kit convention: canvas PNGs top-down, three flipY
	if ctx.has("renderOrder"):
		o.renderOrder = ctx.renderOrder
	if spec.get("kind") == "basic":
		if o.get("name") == null and imported != null and imported.resource_name != "":
			o.name = imported.resource_name
		return basicMaterial(o)
	# attach: attachMaterial({ rimColor, globals, envMap, ...o })
	if o.get("rimColor") == null:
		o.rimColor = spec.get("rimColor") if spec.get("rimColor") != null else ctx.get("rimColor", "#FFD9A0")
	if not o.has("envMap") or o.envMap is String:
		o.envMap = ctx.get("envMap", true)
	var m := attachMaterial(o)
	if o.get("name") != null:
		m.name = str(o.name)
	elif imported != null and m.name == "":
		m.name = imported.resource_name
	return m
