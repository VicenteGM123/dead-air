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


static func water() -> ShaderMaterial:
	return _shader_mat("water", "res://shaders/water.gdshader")


## Additive, unshaded glow (halos around fires, magic, fireflies).
static func glow_add() -> ShaderMaterial:
	return _shader_mat("glow_add", "res://shaders/glow.gdshader")


## Additive flat glow without falloff (ground rings, telegraphs).
static func glow_flat() -> ShaderMaterial:
	return _shader_mat("glow_flat", "res://shaders/glow.gdshader", {"billboard": false, "uv_falloff": false, "pull": 0.0})


## Alpha-blended unshaded vertex colour (dust, smoke, decals, UI rings in the world).
static func fx_alpha() -> ShaderMaterial:
	return _shader_mat("fx_alpha", "res://shaders/fx.gdshader")
