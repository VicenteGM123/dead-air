# World surfaces, runtime half (port of the runtime parts of src/world/surfaces.js).
#
# The station's canvas textures and the batch / plain materials built from them are generated offline by
# blender/world/surfaces.py (same textures, same material specs, same tile sizes) and arrive inside the world GLBs
# (every material carries its JS factory spec as the custom property "da", SPEC §5.5). What the game needs at
# runtime lives here:
#   AREA_STYLE[areaId] = { floor, wall:{ base, wainscot?, wainscotH?, rail?, baseboard, crown? }, ceiling,
#     fixtures:'panels'|'cans'|'grid', lightPre (emergency color or null = dark), lightPost, gridY? }
#   EXTERIOR_STYLE = { base, wainscot, wainscotH, cap }
#   createSurfaces(game) -> Surfaces: get(key) -> { mat, tile:[u,v], key } | null, plain(key) -> Material | null,
#     AREA_STYLE, EXTERIOR_STYLE. The materials are the converted ones of the imported level (level.gd registers
#     them while it converts the GLB materials: batch meshes -> get(), their non-vertex-colour twins -> plain()).
#   applyDa(game, root, surf=null)  converts every imported material under `root` with game.mats.fromSpec(spec,
#     importedMaterial) and applies the node "da" custom properties (userData via DAU.ud, castShadow, visible).
#   matFromSpec(game, spec, base) -> Material  one spec (e.g. an alternate material stored in a node's
#     "da".mats: fixture pre/post, ON AIR dark/lit, keypad on/off, beacons dark/lit), taking the texture from
#     `base` (the imported material of that node). Falls back to a StandardMaterial3D look when materials.gd
#     (game.mats.fromSpec) is not available.
extends RefCounted

const AREA_STYLE := {
	"lobby": {
		"floor": "shag_orange",
		"wall": {"base": "wood_walnut", "baseboard": "trim_chocolate", "crown": "trim_teak"},
		"ceiling": "ceiling_tile", "fixtures": "cans", "lightPre": "#FFB45A", "lightPost": "#FFC98A",
	},
	"newsroom": {
		"floor": "vinyl_news",
		"wall": {"base": "paint_news", "wainscot": "wood_teak", "wainscotH": 1.1, "rail": "trim_chocolate", "baseboard": "trim_chocolate", "crown": "trim_cream"},
		"ceiling": "ceiling_tile", "fixtures": "panels", "lightPre": null, "lightPost": "#E8F5E1",
	},
	"green_room": {
		"floor": "shag_avocado",
		"wall": {"base": "paint_avocado", "wainscot": "wood_olive", "wainscotH": 1.0, "rail": "trim_mustard", "baseboard": "trim_chocolate", "crown": "trim_cream"},
		"ceiling": "ceiling_tile", "fixtures": "panels", "lightPre": null, "lightPost": "#FFE6C0",
	},
	"studio_a": {
		"floor": "concrete_studio",
		"wall": {"base": "paint_studio", "wainscot": "quilt_plum", "wainscotH": 3.0, "rail": "trim_black", "baseboard": "trim_black"},
		"ceiling": "ceiling_studio", "fixtures": "grid", "gridY": 6.5, "lightPre": null, "lightPost": "#FFC4E4",
	},
	"studio_b": {
		"floor": "wood_maple",
		"wall": {"base": "paint_lilac", "wainscot": "quilt_pink", "wainscotH": 2.2, "rail": "trim_cream", "baseboard": "trim_cream"},
		"ceiling": "ceiling_studio_b", "fixtures": "grid", "gridY": 5.0, "lightPre": null, "lightPost": "#FFF1C9",
	},
	"master_control": {
		"floor": "vinyl_mc",
		"wall": {"base": "block_mc", "baseboard": "trim_black", "crown": "trim_steel"},
		"ceiling": "ceiling_tile_mc", "fixtures": "panels", "lightPre": null, "lightPost": "#DDF3FF",
	},
	"yard": {"floor": "gravel"},
}

const EXTERIOR_STYLE := {"base": "brick", "wainscot": "block_ext", "wainscotH": 0.6, "cap": "trim_coping"}


class Surfaces extends RefCounted:
	var game
	var AREA_STYLE: Dictionary
	var EXTERIOR_STYLE: Dictionary
	var _get := {}      # key -> { mat, tile, key }
	var _plain := {}    # key -> Material

	func get_(key: String):
		return _get.get(key)

	func plain(key: String):
		return _plain.get(key)

	func register(key: String, mat: Material, tile, isPlain: bool) -> void:
		if isPlain:
			if not _plain.has(key):
				_plain[key] = mat
		elif not _get.has(key):
			_get[key] = {"mat": mat, "tile": tile, "key": key}


static func createSurfaces(game) -> Surfaces:
	var s := Surfaces.new()
	s.game = game
	s.AREA_STYLE = AREA_STYLE
	s.EXTERIOR_STYLE = EXTERIOR_STYLE
	return s


# ------------------------------------------------------------------------------------------ imported materials
static func parseDa(v) -> Variant:
	if v is String:
		var p = JSON.parse_string(v)
		return p if p is Dictionary else null
	if v is Dictionary:
		return v
	return null

static func nodeDa(n: Object) -> Variant:
	if n == null or not n.has_meta("extras"):
		return null
	var ex = n.get_meta("extras")
	return parseDa(ex.get("da")) if ex is Dictionary else null

static func matDa(m: Material) -> Variant:
	if m == null or not m.has_meta("extras"):
		return null
	var ex = m.get_meta("extras")
	return parseDa(ex.get("da")) if ex is Dictionary else null

static func matFromSpec(game, spec, base: Material) -> Material:
	if spec == null:
		return base
	if game != null and game.mats != null and game.mats.has_method("fromSpec"):
		var m = game.mats.fromSpec(spec, base)
		if m != null:
			return m
	return _fallback(spec, base)

# Stand-in look when materials.gd is missing: colour, emission for glow, alpha, the imported texture.
static func _fallback(spec: Dictionary, base: Material) -> Material:
	var m := StandardMaterial3D.new()
	var kind: String = spec.get("kind", "toon")
	var opts: Dictionary = spec.get("opts", {}) if spec.get("opts") is Dictionary else {}
	var c := DAU.color(spec.get("color", "#ffffff"))
	m.albedo_color = c
	if base is BaseMaterial3D and (base as BaseMaterial3D).albedo_texture != null:
		m.albedo_texture = (base as BaseMaterial3D).albedo_texture
	elif spec.get("mapFile") is String and ResourceLoader.exists(spec.mapFile):
		m.albedo_texture = load(spec.mapFile)
	m.roughness = float(opts.get("rough", 0.75))
	m.metallic = float(opts.get("metal", 0.0))
	if opts.get("vertexColors", false):
		m.vertex_color_use_as_albedo = true
	if kind == "glow" or kind == "basic":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if kind == "glow":
			var k := float(spec.get("intensity", opts.get("intensity", 2.0)))
			m.albedo_color = Color(c.r * k, c.g * k, c.b * k)
	if opts.get("transparent", false) or opts.get("additive", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = float(opts.get("opacity", 1.0))
		if opts.get("additive", false):
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if float(opts.get("alphaTest", 0.0)) > 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = float(opts.alphaTest)
	var side = opts.get("side", "front")
	if side == "double" or side == 2:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif side == "back" or side == 1:
		m.cull_mode = BaseMaterial3D.CULL_FRONT
	if opts.get("emissive") != null and opts.get("emissive") is String:
		m.emission_enabled = true
		m.emission = DAU.color(opts.emissive)
		m.emission_energy_multiplier = float(opts.get("emissiveIntensity", 1.0))
	return m

# Converts every imported material under `root` (game.mats.fromSpec) and applies the nodes' "da" properties.
# surf (optional) receives the converted batch / plain materials by surface key (material spec opts.name or
# the node name batch_<group>_<key>).
static func applyDa(game, root: Node, surf = null) -> void:
	var cache := {}
	DAU.traverse(root, func(n):
		var da: Variant = nodeDa(n)
		if da != null:
			var u := DAU.ud(n)
			for k in da:
				u[k] = da[k]
			if n is Node3D and da.get("visible") == false:
				n.visible = false
		if n is GeometryInstance3D:
			var cast = da.get("castShadow") if da != null else null
			if cast != null:
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var src: Material = mi.mesh.surface_get_material(i)
				if src == null:
					continue
				var conv: Material
				if cache.has(src):
					conv = cache[src]
				else:
					var spec = matDa(src)
					conv = matFromSpec(game, spec, src) if spec != null else src
					cache[src] = conv
					if surf != null and spec != null and spec.get("surface") is String:
						surf.register(spec.surface, conv, spec.get("tile"), not spec.get("opts", {}).get("vertexColors", false))
				if da != null and da.get("renderOrder") != null and conv != null:
					# three renderOrder (lamp pools: 2) -> render_priority of this node's own copy
					conv = conv.duplicate()
					conv.render_priority = clampi(int(da.renderOrder), -128, 127)
				if conv != src:
					mi.set_surface_override_material(i, conv)
	)

# The material a mesh node currently draws (override > surface 0).
static func meshMat(mi: MeshInstance3D) -> Material:
	if mi == null:
		return null
	if mi.material_override != null:
		return mi.material_override
	var m := mi.get_surface_override_material(0)
	if m != null:
		return m
	return mi.mesh.surface_get_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null

# The imported (unconverted) material of a mesh node's first surface: the texture source for alternate specs.
static func importedMat(mi: MeshInstance3D) -> Material:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return null
	return mi.mesh.surface_get_material(0)
