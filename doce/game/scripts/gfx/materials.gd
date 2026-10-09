class_name Materials
## Shared material instances (one per look) so every mesh batches against the same few shaders.

static var _cache := {}


static func _shader_mat(key: String, path: String, params: Dictionary = {}) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


## Per-node shader parameter (instead of instance uniforms / set_instance_shader_parameter()). Godot 4.7's
## Compatibility renderer only has 256 global/instance uniform slots on WebGL 2 (16 per instance), so on the web all
## but ~14 instances would read zeros: black models and invisible glows. The first call gives the node its own copy
## of its material (and again if its material_override is replaced later); materials nobody animates stay shared.
static func set_param(gi: GeometryInstance3D, param: StringName, value: Variant) -> void:
	var m := gi.material_override as ShaderMaterial
	if m == null:
		return
	if not gi.has_meta(&"own_material") or gi.get_meta(&"own_material") != m:
		m = m.duplicate() as ShaderMaterial
		gi.material_override = m
		gi.set_meta(&"own_material", m)
	m.set_shader_parameter(param, value)


static func lowpoly() -> ShaderMaterial:
	return _shader_mat("lowpoly", "res://shaders/lowpoly.gdshader")


## Same as lowpoly but sways in the wind (trees, bushes, flowers, banners).
static func foliage(amount: float = 0.045) -> ShaderMaterial:
	return _shader_mat("foliage_%.3f" % amount, "res://shaders/lowpoly.gdshader", {"sway": amount, "wrap": 0.55})


## Creatures of Nyx: lowpoly with a cold ethereal rim light.
static func nyx(rim: Color = Color(0.35, 0.75, 1.0)) -> ShaderMaterial:
	return _shader_mat("nyx_%s" % rim.to_html(false), "res://shaders/lowpoly.gdshader", {"rim_color": rim, "rim_power": 3.5})


## Night-sky material for the creatures of Nyx. `hem` frays the bottom of the mesh into smoke (model-space y).
static func nyx_sky(rim: Color = Color("9C7BFF"), hem: float = -1.0) -> ShaderMaterial:
	return _shader_mat("nyxsky_%s_%.2f" % [rim.to_html(false), hem], "res://shaders/nyx.gdshader", {"rim_color": rim, "hem": hem})


## Soft additive light cone along +Z of the given length.
static func beam_cone(length: float, col: Color = Color(1.0, 0.86, 0.6)) -> ShaderMaterial:
	return _shader_mat("beamcone_%.1f_%s" % [length, col.to_html(false)], "res://shaders/beam_cone.gdshader", {"beam_length": length, "beam_color": col})


## Double-sided cone mesh along +Z: radius r0 at the source, r1 at `length`.
static func cone_mesh(length: float, r0: float, r1: float, sides: int = 14) -> ArrayMesh:
	var mb := MeshBuilder.new(1)
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	mb.cyl(Vector3.ZERO, length, r0, r1, sides, Color.WHITE, false)
	mb.pop()
	return mb.commit()


## The same look as a lowpoly / foliage material but without its per-instance uniforms (flash, dissolve, tint).
## The Compatibility renderer gives every GeometryInstance whose shader declares instance uniforms 16 slots of a
## 4096-slot buffer (about 250 instances for the whole scene), so static scenery that never flashes or dissolves
## (props, paths, plaza) should use this twin. Other materials are returned unchanged.
static func static_twin(m: Material) -> Material:
	var sm := m as ShaderMaterial
	if sm == null or sm.shader == null or sm.shader.resource_path != "res://shaders/lowpoly.gdshader":
		return m
	var key := "static_%d" % sm.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	if not _cache.has("_static_shader"):
		var re := RegEx.new()
		re.compile("instance\\s+uniform\\s+(\\w+)\\s+(\\w+)\\s*=\\s*([^;]+);")
		var sh := Shader.new()
		sh.code = re.sub(sm.shader.code, "const $1 $2 = $3;", true)
		_cache["_static_shader"] = sh
	var twin := ShaderMaterial.new()
	twin.shader = _cache["_static_shader"]
	for u in sm.shader.get_shader_uniform_list():
		var n: String = u["name"]
		twin.set_shader_parameter(n, sm.get_shader_parameter(n))
	_cache[key] = twin
	return twin


## Island ground: lowpoly lighting plus the ground map (contact AO, bare soil) and grass strokes.
static func terrain() -> ShaderMaterial:
	return _shader_mat("terrain", "res://shaders/terrain.gdshader")


## Instanced grass clumps (Grass): lit like the facet they grow on, wind waves, distance shrink.
static func grass() -> ShaderMaterial:
	return _shader_mat("grass", "res://shaders/grass.gdshader")


static func water() -> ShaderMaterial:
	return _shader_mat("water", "res://shaders/water.gdshader")


## Additive, unshaded glow (halos around fires, magic, fireflies).
static func glow_add() -> ShaderMaterial:
	return _shader_mat("glow_add", "res://shaders/glow.gdshader")


## TOON: additive four-point sparkle (hit sparks, motes).
static func glow_star() -> ShaderMaterial:
	return _shader_mat("glow_star", "res://shaders/glow.gdshader", {"star": true})


## Additive flat glow without falloff (ground rings, telegraphs).
static func glow_flat() -> ShaderMaterial:
	return _shader_mat("glow_flat", "res://shaders/glow.gdshader", {"billboard": false, "uv_falloff": false, "pull": 0.0})


## Alpha-blended unshaded vertex colour (dust, smoke, decals, UI rings in the world).
static func fx_alpha() -> ShaderMaterial:
	return _shader_mat("fx_alpha", "res://shaders/fx.gdshader")
