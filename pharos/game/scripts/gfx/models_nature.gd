class_name ModelsNature
## Static low-poly nature props and small decorative objects for the island. Each public builder takes a seed
## (variation) and returns an ArrayMesh whose origin is at the base centre, on the ground (y = 0); "front" is +Z.
## Plants use the foliage material (wind sway), everything else the plain lowpoly one: see `material_for()`.
##
## Every model has an `add_*` twin that draws into an existing MeshBuilder at its current transform, so the
## buildings reuse them (olive trees in the farm, amphoras on the dock...). Layout randomness comes from its own
## RandomNumberGenerator, so the per-face shading noise (mb.rng) never changes a model's shape.
##
## Flora of Delos in late spring (Landscape spec v1): olive, cypress, holm oak, oriental plane, Aleppo pine, fig,
## almond, pomegranate, laurel, Leto's palm, tamarisk, juniper; maquis (bush), oleander, cistus, broom, thyme
## cushions, giant reed, sea lily; crops (grapevine rows, wheat) and the farmland stonework (terrace walls,
## threshing floor, beehives, well, spring basin); the instanced grass clump.
##
## Species with named kinds take the kind from the seed: kind = posmod(seed, N) (see each builder's doc), so
## seeds 0, 1, 2... give kinds 0, 1, 2... `info()` gives each species' size at scale 1 for placement.
##
## The geometry helpers at the bottom (lathe, blob, box5, fluted_shaft, hull...) are shared with ModelsBuildings.

const VARY := 0.03
## Extra named tones (loaded by path so this file never depends on the class-name cache).
const PX := preload("res://scripts/gfx/pal_extra.gd")
## Wind sway for knee-high plants (trees and bushes use Materials.foliage()'s default).
const SMALL_PLANT_SWAY := 0.08

const PLANTS := [
	"olive_tree", "cypress", "stone_pine", "bush", "holm_oak", "plane_tree", "aleppo_pine", "fig_tree",
	"almond_tree", "pomegranate", "laurel_tree", "date_palm", "tamarisk", "juniper", "oleander", "broom_shrub",
	"cistus_shrub", "giant_reed",
]
const SMALL_PLANTS := [
	"flowers_lavender", "flowers_poppy", "flowers_daisy", "grass_tuft", "thyme_cushion", "flowers_anemone",
	"sea_lily", "grapevine_row", "wheat_patch",
]
## Per-species wind sway (Materials.foliage(amount)): big trees move slowly, wispy and knee-high plants more.
const SWAY := {
	"plane_tree": 0.03, "date_palm": 0.03, "juniper": 0.03, "thyme_cushion": 0.03, "grapevine_row": 0.03,
	"tamarisk": 0.06, "broom_shrub": 0.06,
	"giant_reed": 0.08, "wheat_patch": 0.08, "sea_lily": 0.08, "grass_tuft": 0.08, "flowers_lavender": 0.08,
	"flowers_poppy": 0.08, "flowers_daisy": 0.08, "flowers_anemone": 0.08,
}
## Models that should not cast shadows (they get a ground-map AO splat instead).
const NO_SHADOW := [
	"thyme_cushion", "flowers_lavender", "flowers_poppy", "flowers_daisy", "flowers_anemone", "grass_tuft",
	"grass_clump", "sea_lily", "wheat_patch",
]
## Size of each species at placement scale 1 (metres), measured from the meshes: `h` total height, `h0` crown
## base (lowest foliage), `r` canopy / footprint radius, `obstacle` trunk radius for Obstacles (0 = walkable),
## `ao` ground-map contact-AO strength. Used by Props for the occlusion rule, spacing, AO splats and grass skirts.
const INFO := {
	"olive_tree": {"h": 2.9, "h0": 1.2, "r": 1.65, "obstacle": 0.4, "ao": 0.35},
	"cypress": {"h": 5.6, "h0": 0.3, "r": 0.8, "obstacle": 0.35, "ao": 0.35},
	"stone_pine": {"h": 6.4, "h0": 4.4, "r": 3.5, "obstacle": 0.45, "ao": 0.35},
	"holm_oak": {"h": 4.4, "h0": 1.45, "r": 2.3, "obstacle": 0.5, "ao": 0.35},
	"plane_tree": {"h": 6.9, "h0": 2.6, "r": 4.4, "obstacle": 0.6, "ao": 0.45},
	"aleppo_pine": {"h": 6.4, "h0": 3.6, "r": 2.8, "obstacle": 0.35, "ao": 0.35},
	"fig_tree": {"h": 3.1, "h0": 1.05, "r": 2.2, "obstacle": 0.4, "ao": 0.35},
	"almond_tree": {"h": 3.9, "h0": 1.8, "r": 1.8, "obstacle": 0.3, "ao": 0.3},
	"pomegranate": {"h": 2.3, "h0": 0.75, "r": 1.2, "obstacle": 0.3, "ao": 0.3},
	"laurel_tree": {"h": 3.7, "h0": 0.4, "r": 1.5, "obstacle": 0.35, "ao": 0.3},
	"date_palm": {"h": 7.7, "h0": 5.2, "r": 2.8, "obstacle": 0.35, "ao": 0.3},
	"tamarisk": {"h": 3.8, "h0": 1.2, "r": 2.3, "obstacle": 0.35, "ao": 0.3},
	"juniper": {"h": 2.3, "h0": 0.25, "r": 1.3, "obstacle": 0.0, "ao": 0.3},
	"bush": {"h": 0.8, "h0": 0.1, "r": 0.8, "obstacle": 0.0, "ao": 0.3},
	"oleander": {"h": 2.3, "h0": 0.45, "r": 1.0, "obstacle": 0.35, "ao": 0.3},
	"cistus_shrub": {"h": 0.9, "h0": 0.0, "r": 0.65, "obstacle": 0.0, "ao": 0.3},
	"broom_shrub": {"h": 1.55, "h0": 0.3, "r": 0.6, "obstacle": 0.0, "ao": 0.3},
	"giant_reed": {"h": 3.3, "h0": 0.0, "r": 1.1, "obstacle": 0.0, "ao": 0.25},
	"thyme_cushion": {"h": 0.45, "h0": 0.0, "r": 0.46, "obstacle": 0.0, "ao": 0.25},
	"sea_lily": {"h": 0.3, "h0": 0.0, "r": 0.38, "obstacle": 0.0, "ao": 0.0},
	"grapevine_row": {"h": 1.05, "h0": 0.55, "r": 2.45, "obstacle": 0.0, "ao": 0.2},
	"wheat_patch": {"h": 0.62, "h0": 0.0, "r": 1.5, "obstacle": 0.0, "ao": 0.15},
	"terrace_wall": {"h": 0.6, "h0": 0.0, "r": 1.5, "obstacle": 0.0, "ao": 0.45},
	"threshing_floor": {"h": 0.35, "h0": 0.0, "r": 3.2, "obstacle": 0.0, "ao": 0.0},
	"beehives": {"h": 0.77, "h0": 0.0, "r": 1.2, "obstacle": 1.0, "ao": 0.3},
	"well": {"h": 1.6, "h0": 0.0, "r": 1.6, "obstacle": 0.8, "ao": 0.45},
	"spring_basin": {"h": 0.66, "h0": 0.0, "r": 1.4, "obstacle": 1.0, "ao": 0.4},
}


static func material_for(model_name: String) -> Material:
	if model_name == "grass_clump":
		# Materials.grass() belongs to the grass system; looked up dynamically so this file never depends on it.
		var mats: Script = load("res://scripts/gfx/materials.gd")
		for m in mats.get_script_method_list():
			if m["name"] == "grass":
				return mats.call("grass")
		return Materials.foliage(SMALL_PLANT_SWAY)
	if model_name in PLANTS or model_name in SMALL_PLANTS:
		var fallback := 0.045 if model_name in PLANTS else SMALL_PLANT_SWAY
		return Materials.foliage(SWAY.get(model_name, fallback))
	return Materials.lowpoly()


## True for the models that should cast shadows (trees, shrubs over ~0.6 m, walls, rocks, structures).
static func casts_shadow(model_name: String) -> bool:
	return not (model_name in NO_SHADOW or model_name.begins_with("flowers") or model_name.begins_with("grass"))


## Size data for a species at scale 1 (see INFO); unknown names get a small generic footprint.
static func info(model_name: String) -> Dictionary:
	return INFO.get(model_name, {"h": 1.0, "h0": 0.0, "r": 0.6, "obstacle": 0.0, "ao": 0.3})


static func _begin(seed_value: int) -> MeshBuilder:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = VARY
	return mb


static func make_rng(seed_value: int, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_value * 92821 + salt * 7919 + 17)
	return r


# --- species colours (sRGB, from the landscape spec; species-only, so they live here and not in Pal) -----------

const HOLM_BARK := Color("6A5442")
const HOLM := Color("4F6440")
const HOLM_LOW := Color("3A4A30")
const HOLM_TOP := Color("687C52")
const PLANE_BARK_PALE := Color("C9BFA2")
const PLANE_BARK_OLIVE := Color("9A9478")
const PLANE_LIMB := Color("B8AE90")
const PLANE := Color("7A9A50")
const PLANE_LOW := Color("5C7A3E")
const PLANE_TOP := Color("8EAA62")
const ALEPPO_BARK := Color("7A5E4A")
const ALEPPO_BARK_LIGHT := Color("8A7468")
const ALEPPO := Color("728C50")
const ALEPPO_TOP := Color("86A062")
const FIG_BARK := Color("9C9488")
const FIG_BARK_LIGHT := Color("B3AC9F")
const FIG := Color("6A8C46")
const FIG_LOW := Color("52743A")
const FIG_TOP := Color("80A058")
const ALMOND_BARK := Color("5E4A3C")
const ALMOND := Color("8FA868")
const ALMOND_LOW := Color("6F8A50")
const ALMOND_TOP := Color("A3BA7C")
const ALMOND_FRUIT := Color("B9C98C")
const BLOSSOM := Color("F6E6EA")
const BLOSSOM_LOW := Color("EBB8C8")
const POMEG_BARK := Color("7A5E48")
const POMEG := Color("5F8A3C")
const POMEG_LOW := Color("4A6E30")
const POMEG_TOP := Color("78A04E")
const POMEG_FLOWER := Color("E2502E")
const POMEG_FLOWER_DARK := Color("B83A22")
const LAUREL := Color("4E6B3A")
const LAUREL_LOW := Color("3A522C")
const LAUREL_TOP := Color("63824A")
const PALM_BARK := Color("8A7356")
const PALM_BARK_DARK := Color("725E46")
const PALM := Color("6E8E4A")
const PALM_LOW := Color("55743C")
const PALM_TIP := Color("86A25E")
const PALM_DEAD := Color("A08A5E")
const TAMARISK_BARK := Color("6F5A4C")
const TAMARISK_TWIG := Color("7E6A5A")
const TAMARISK := Color("879E7A")
const TAMARISK_LOW := Color("66805A")
const TAMARISK_TOP := Color("A0B38C")
const TAMARISK_PINK := Color("E3A3B8")
const TAMARISK_PINK_LOW := Color("BC8696")
const TAMARISK_PINK_TOP := Color("EDBFCD")
const JUNIPER_BARK := Color("8A8276")
const JUNIPER := Color("56704A")
const JUNIPER_LOW := Color("3F5438")
const JUNIPER_TOP := Color("6E8660")
const KERMES := Color("4F6440")
const KERMES_LOW := Color("3A4A30")
const MYRTLE := Color("5E8048")
const VINE_BARK := Color("6B5040")
const GRAPE := Color("9FB04A")
const SOIL_TOP := Color("B8936E")
const WHEAT := Color("D2B45A")
const WHEAT_LIT := Color("E3CB7E")
const WHEAT_STALK := Color("A39A4E")
const WHEAT_BASE := Color("B5B060")
const BARLEY := Color("CFC07A")
const BARLEY_LIT := Color("E0D396")
const BARLEY_STALK := Color("A2A05C")
const THYME := Color("7E8A55")
const THYME_LOW := Color("5F6A40")
const THYME_TOP := Color("96A266")
const THYME_FLOWER := Color("C9A0C8")
const BURNET := Color("84854F")
const BURNET_LOW := Color("646640")
const BURNET_TOP := Color("9E9A60")
const SAGE := Color("94A274")
const SAGE_LOW := Color("737F58")
const SAGE_TOP := Color("AAB88A")
const SAGE_FLOWER := Color("E8C340")
const CISTUS := Color("768A56")
const CISTUS_LOW := Color("5C6E44")
const CISTUS_TOP := Color("8EA068")
const CISTUS_PINK := Color("E07A9E")
const BROOM := Color("E8C340")
const BROOM_LOW := Color("C9A02C")
const BROOM_STEM := Color("6F8A3E")
const OLEANDER := Color("5E7A44")
const OLEANDER_LOW := Color("46603A")
const OLEANDER_TOP := Color("739058")
const OLEANDER_PINK := Color("E07A9E")
const OLEANDER_PINK_LIGHT := Color("F29AB8")
const OLEANDER_DEEP := Color("D45A88")
const REED := Color("8FA85A")
const REED_LEAF := Color("6F8A44")
const REED_LEAF_LIT := Color("A3B86E")
const REED_PLUME := Color("D8CBA0")
const SEA_LILY := Color("8FA88A")
const SEA_LILY_LIT := Color("A7BBA0")
const SEA_LILY_TRUMPET := Color("E8E0C0")
const LAV_HEAD_LOW := Color("7A60B0")
const LAV_BRACT := Color("C2B0EA")
const ROSETTE := Color("5E7A3A")
const ROSETTE_LIGHT := Color("6E8A46")
const TUFT_BASE := Color("8C9058")
const TUFT_MID := Color("B2AE6A")
const TUFT_TIP := Color("D9C88E")
const TUFT_SEED := Color("E3D6A6")
const MOSS := Color("5E7A3A")
const WATER := Color("5FB9B2")
const WATER_RIM := Color("4E9E9A")
const WATER_FALL := Color("9FDAD3")
const WELL_WATER := Color("2A3440")
const HIVE_LIT := Color("D27850")


# --- trees ---------------------------------------------------------------------------------------------------

static func olive_tree(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_olive_tree(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Gnarled grey-brown trunk forking into two or three boughs under a wide, silvery, lumpy canopy (~3 m tall,


## ~3 m across). `lod` 1 is cheaper (≈170 tris), `lod` 2 is the orchard version (≈85 tris).
static func add_olive_tree(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, lod: int = 0) -> void:
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var bark := PX.OLIVE_BARK
	var p0 := Vector3(0, -0.2, 0)
	var p1 := (Vector3(0, 1.0, 0) + lean * 0.8) * s
	if lod >= 2:
		mb.limb(p0, p1, 0.25 * s, 0.17 * s, 5, bark, false)
		var b0 := rng.randf() * TAU
		var lp := [Vector2(0, -0.42), Vector2(0.92, -0.2), Vector2(0.78, 0.34), Vector2(0, 0.52)]
		for i in 2:
			var a := b0 + PI * float(i) + rng.randf_range(-0.3, 0.3)
			var tip := p1 + Vector3(cos(a) * 0.62, rng.randf_range(0.65, 0.85), sin(a) * 0.62) * s
			mb.limb(p1, tip, 0.13 * s, 0.07 * s, 4, bark, false)
			blob(mb, rng, tip + Vector3(0, 0.1, 0) * s, _scaled(lp, rng.randf_range(0.9, 1.0) * s), 5, 0.12, Pal.OLIVE_LEAF, Pal.OLIVE_LEAF_DARK, -0.1, Pal.OLIVE_LEAF.lightened(0.07), 0.86)
		blob(mb, rng, p1 + Vector3(0, 1.25, 0) * s - lean * 0.3 * s, _scaled(lp, 0.88 * s), 5, 0.12, Pal.OLIVE_LEAF.lightened(0.04), Pal.OLIVE_LEAF_DARK, -0.1, Pal.OLIVE_LEAF.lightened(0.09), 0.86)
		return
	mb.cyl(Vector3(0, -0.1, 0), 0.36 * s, 0.38 * s, 0.21 * s, 5, bark, false, rng.randf() * TAU)
	mb.limb(p0, p1, 0.26 * s, 0.18 * s, 5 if lod > 0 else 6, bark, false)
	var boughs := 2 + (rng.randi() % 2 if lod == 0 else 0)
	var a0 := rng.randf() * TAU
	var tips: Array[Vector3] = []
	for i in boughs:
		var a := a0 + TAU * float(i) / float(boughs) + rng.randf_range(-0.35, 0.35)
		var tip := p1 + Vector3(cos(a) * 0.68, rng.randf_range(0.7, 0.9), sin(a) * 0.68) * s
		mb.limb(p1, tip, 0.14 * s, 0.07 * s, 4 if lod > 0 else 5, bark, false)
		tips.append(tip)
	var top := p1 + Vector3(0, 1.3, 0) * s - lean * 0.4 * s
	var sides := 5 if lod > 0 else 6
	for t in tips:
		_lump(mb, rng, t + Vector3(0, 0.12, 0) * s, rng.randf_range(0.86, 0.98) * s, sides, Pal.OLIVE_LEAF, Pal.OLIVE_LEAF_DARK)
	_lump(mb, rng, top, 0.9 * s, sides + 1, Pal.OLIVE_LEAF.lightened(0.05), Pal.OLIVE_LEAF_DARK)
	if lod == 0 and boughs == 2:
		var oa := a0 + PI * 0.5
		_lump(mb, rng, p1 + Vector3(cos(oa) * 1.0, 0.55, sin(oa) * 1.0) * s, 0.6 * s, 6, Pal.OLIVE_LEAF, Pal.OLIVE_LEAF_DARK)


## Rounded foliage lump, a little flattened, darker underneath.
static func _lump(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, sides: int, col: Color, col_low: Color) -> void:
	var prof := [Vector2(0, -0.44), Vector2(0.72, -0.36), Vector2(1.0, -0.04), Vector2(0.84, 0.32), Vector2(0.42, 0.56), Vector2(0, 0.62)]
	blob(mb, rng, c, _scaled(prof, r), sides, 0.12, col, col_low, -0.1, col.lightened(0.07), 0.86)


static func cypress(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_cypress(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Tall dark-green flame, widest a third of the way up (4.8–6.4 m).
static func add_cypress(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var h := rng.randf_range(4.8, 6.4) * s
	var r := rng.randf_range(0.62, 0.76) * s
	mb.cyl(Vector3(0, -0.2, 0), 0.7, 0.16 * s, 0.13 * s, 5, Pal.WOOD_DARK, false)
	var prof := [
		Vector2(0, 0.28), Vector2(r * 0.72, 0.32), Vector2(r * 0.98, h * 0.2), Vector2(r, h * 0.38),
		Vector2(r * 0.8, h * 0.6), Vector2(r * 0.45, h * 0.83), Vector2(0, h),
	]
	var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
	mb.push(Transform3D(Basis.from_euler(lean), Vector3.ZERO))
	blob(mb, rng, Vector3.ZERO, prof, 7, 0.07, Pal.CYPRESS, Pal.CYPRESS_DARK, -0.25)
	mb.pop()


static func stone_pine(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_stone_pine(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Umbrella pine: tall, slightly curved reddish trunk under a wide, flat-topped canopy (6–7 m).
static func add_stone_pine(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var h := rng.randf_range(4.9, 5.6) * s
	var la := rng.randf() * TAU
	var lean := Vector3(cos(la), 0, sin(la)) * rng.randf_range(0.5, 0.9) * s
	var p0 := Vector3(0, -0.2, 0)
	var p1 := Vector3(0, h * 0.55, 0) + lean * 0.35
	var p2 := Vector3(0, h, 0) + lean
	mb.cyl(Vector3(0, -0.1, 0), 0.35 * s, 0.32 * s, 0.2 * s, 6, Pal.WOOD_DARK, false)
	mb.limb(p0, p1, 0.22 * s, 0.17 * s, 6, Pal.WOOD, false)
	mb.limb(p1, p2, 0.17 * s, 0.12 * s, 6, Pal.WOOD, false)
	var a0 := rng.randf() * TAU
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0
		mb.limb(p2 - Vector3(0, 0.45, 0) * s, p2 + Vector3(cos(a) * 1.3, 0.4, sin(a) * 1.3) * s, 0.1 * s, 0.05 * s, 4, Pal.WOOD_DARK, false)
	var cc := p2 + Vector3(0, 0.45, 0) * s
	var prof := [Vector2(0, -0.3), Vector2(2.0, -0.24), Vector2(2.55, 0.08), Vector2(2.1, 0.44), Vector2(0.9, 0.64), Vector2(0, 0.68)]
	blob(mb, rng, cc, _scaled(prof, s), 9, 0.09, Pal.PINE.lightened(0.03), Pal.CYPRESS, -0.15)
	# Lumps around the rim break the circle into a cloud-like outline.
	for i in 4:
		var a := a0 + 0.5 + TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3)
		var c := cc + Vector3(cos(a) * 2.05, rng.randf_range(-0.05, 0.12), sin(a) * 2.05) * s
		var lp := [Vector2(0, -0.26), Vector2(0.95, -0.2), Vector2(1.1, 0.06), Vector2(0.7, 0.34), Vector2(0, 0.42)]
		blob(mb, rng, c, _scaled(lp, s * rng.randf_range(0.85, 1.05)), 7, 0.1, Pal.PINE, Pal.CYPRESS, -0.15)


static func bush(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_bush(mb, make_rng(seed_value), 1.0, posmod(seed_value, 3))
	return mb.commit()


## Goat-browsed evergreen maquis dome of the wild ring (0.75–0.9 m tall, 1.5–1.9 m wide, ≤ 130 tris), its


## underside clipped into a clean browse line at 0.1 m. kind = seed % 3: 0 lentisk, 1 kermes oak (darker),
## 2 myrtle in flower (white dots). `kind` -1 picks one from the rng.
static func add_bush(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, kind: int = -1) -> void:
	if kind < 0:
		kind = rng.randi() % 3
	var col: Color = [Pal.PINE, KERMES, MYRTLE][kind]
	var low: Color = [Pal.CYPRESS, KERMES_LOW, Pal.CYPRESS][kind]
	var a0 := rng.randf() * TAU
	var prof := [Vector2(0, 0), Vector2(0.86, 0.04), Vector2(1.0, 0.45), Vector2(0.72, 0.92), Vector2(0, 1.12)]
	var faces: Array = []
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0 + rng.randf_range(-0.3, 0.3)
		var d := 0.0 if i == 0 else rng.randf_range(0.34, 0.42) * s
		var r := (0.62 if i == 0 else rng.randf_range(0.42, 0.48)) * s
		var c := Vector3(cos(a) * d, 0.1 * s, sin(a) * d)
		var lc := col.lightened(0.04) if i == 0 else col
		faces.append_array(_blob_f(mb, rng, c, _scaled(prof, r), 6 if i < 2 else 5, 0.12, lc, low, -0.15, lc.lightened(0.07), 0.86))
	if kind == 2:
		var up := _upper(faces, 0.25)
		for i in 8:
			var f: Array = up[rng.randi() % up.size()]
			_dot(mb, rng, f[0] + (f[1] as Vector3) * 0.02, 0.06 * s, Pal.DAISY, Vector3(1, 0.7, 1))


# --- trees of Delos (landscape spec v1) ------------------------------------------------------------------------

static func holm_oak(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_holm_oak(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Quercus ilex, the darkest broadleaf: a dense, egg-shaped dome wider than tall on a short thick trunk that forks at


## ~1.1 m into 2–3 limbs; goats browse the skirt into a flat line at ~1.45 m (≈4.4 m tall, ≈4.5 m wide, ≤ 240 tris).
## kind = seed % 2: 1 is a little narrower and taller with two limbs.
static func add_holm_oak(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var fork := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(1.0, 1.2), rng.randf_range(-0.12, 0.12)) * s
	mb.cyl(Vector3(0, -0.15 * s, 0), 0.4 * s, 0.42 * s, 0.29 * s, 6, HOLM_BARK.darkened(0.1), false, rng.randf() * TAU)
	mb.limb(Vector3(0, -0.2 * s, 0), fork, 0.28 * s, 0.2 * s, 6, HOLM_BARK, false)
	var a0 := rng.randf() * TAU
	var limbs := 3 if variant == 0 else 2
	for i in limbs:
		var a := a0 + TAU * float(i) / float(limbs) + rng.randf_range(-0.3, 0.3)
		mb.limb(fork - Vector3(0, 0.08, 0) * s, fork + Vector3(cos(a) * 0.85, 1.05, sin(a) * 0.85) * s, 0.17 * s, 0.09 * s, 4, HOLM_BARK, false)
	var skirt := rng.randf_range(1.4, 1.5) * s
	var r := (1.95 if variant == 0 else 1.78) * s
	var sy := 1.2 if variant == 0 else 1.32
	var c := Vector3(fork.x * 0.5, skirt + 0.35 * r * sy, fork.z * 0.5)
	_crown(mb, rng, c, r, 8, HOLM, HOLM_LOW, HOLM_TOP, 0.1, sy)
	# Shoulder puffs and a crowning one make the bumpy, slightly egg-shaped outline.
	var n := 3 if variant == 0 else 2
	for i in n:
		var a := a0 + 0.6 + TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25)
		var d := rng.randf_range(1.15, 1.3) * s
		_puff(mb, rng, c + Vector3(cos(a) * d, rng.randf_range(0.35, 0.6) * s, sin(a) * d), rng.randf_range(1.05, 1.2) * s, 6, HOLM, HOLM_LOW, HOLM_TOP, 0.12, 1.05)
	_puff(mb, rng, c + Vector3(rng.randf_range(-0.25, 0.25), 1.2 if variant == 0 else 1.35, rng.randf_range(-0.25, 0.25)) * s, rng.randf_range(1.2, 1.3) * s, 6, HOLM.lightened(0.03), HOLM_LOW, HOLM_TOP, 0.12, 1.05)


static func plane_tree(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_plane_tree(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Platanus orientalis, the great village-square tree: a short massive trunk in pale camouflage bark on a flared


## root plinth splits at 2.2 m into three thick spreading limbs under a huge, broad, slightly flat-topped dome of
## six big overlapping lumps (≈7 m tall, ≈8.4 m wide, crown base 2.6 m so the hero walks under it; ≤ 330 tris).
static func add_plane_tree(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var bark := [PLANE_BARK_PALE, PLANE_BARK_OLIVE, PLANE_BARK_PALE, PLANE_BARK_PALE.darkened(0.05), PLANE_BARK_OLIVE, PLANE_BARK_PALE.lightened(0.04), PLANE_BARK_OLIVE.lightened(0.05)]
	_bark(mb, Vector3(0, -0.2 * s, 0), Vector3(0, 0.32 * s, 0), 0.8 * s, 0.56 * s, 7, bark, null, 0.3, rng.randf() * TAU)
	var fork := Vector3(rng.randf_range(-0.12, 0.12), 2.2, rng.randf_range(-0.12, 0.12)) * s
	_bark(mb, Vector3(0, 0.25 * s, 0), fork, 0.55 * s, 0.4 * s, 7, bark, null, 0.3, rng.randf() * TAU)
	var limb_cols := [PLANE_LIMB, PLANE_BARK_PALE, PLANE_LIMB, PLANE_BARK_OLIVE.lightened(0.08), PLANE_LIMB, PLANE_BARK_PALE]
	var a0 := rng.randf() * TAU
	# Lower ring: three broad lumps resting on the limbs, their flat undersides at the crown base.
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0 + rng.randf_range(-0.15, 0.15)
		var rr := rng.randf_range(2.05, 2.2) * s
		var c := Vector3(cos(a) * 2.35 * s, 2.6 * s + 0.35 * rr * 0.9, sin(a) * 2.35 * s)
		_bark(mb, fork - Vector3(0, 0.2, 0) * s, Vector3(cos(a) * 1.7 * s, 3.3 * s, sin(a) * 1.7 * s), 0.34 * s, 0.17 * s, 6, limb_cols, null, 0.3, rng.randf() * TAU)
		_crown(mb, rng, c, rr, 7, PLANE.darkened(0.03), PLANE_LOW, PLANE_TOP, 0.1, 0.9, 0.35, 0.68, 0.8, -0.3)
	# Upper ring between them and the crowning lump, sunk deep into the ring below so the dome reads as one mass.
	for i in 2:
		var a := a0 + PI / 3.0 + PI * float(i) + rng.randf_range(-0.3, 0.3)
		_puff(mb, rng, Vector3(cos(a) * 1.3, 4.45, sin(a) * 1.3) * s, rng.randf_range(2.0, 2.1) * s, 7, PLANE, PLANE_LOW, PLANE_TOP, 0.1, 0.92)
	_puff(mb, rng, Vector3(rng.randf_range(-0.3, 0.3), 5.5, rng.randf_range(-0.3, 0.3)) * s, 2.35 * s, 8, PLANE.lightened(0.04), PLANE_LOW, PLANE_TOP, 0.1, 0.92)


static func aleppo_pine(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_aleppo_pine(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Pinus halepensis, the wind-bent headland pine: a slender S-curved trunk, bare for its lower 60 %, carrying an


## open, irregular crown of flat-topped cloud pads stacked asymmetrically, with sky between them (≈6.4 m tall,
## ≈5 m wide, ≤ 280 tris). The mesh leans 5° towards +Z (placement adds 8–14° more, away from the meltemi).
## kind = seed % 2 changes the pad layout.
static func add_aleppo_pine(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var h := rng.randf_range(5.8, 6.4) * s
	mb.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(5.0)), Vector3.ZERO))
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var p0 := Vector3(0, -0.2 * s, 0)
	var p1 := Vector3(0.26 * side * s, h * 0.42, 0.05 * s)
	var p2 := Vector3(-0.1 * side * s, h * 0.78, 0.12 * s)
	var trunk := [p0, p1, p2]
	var bark := [ALEPPO_BARK, ALEPPO_BARK_LIGHT, ALEPPO_BARK, ALEPPO_BARK.darkened(0.06), ALEPPO_BARK_LIGHT, ALEPPO_BARK]
	_bark(mb, p0, p1, 0.21 * s, 0.15 * s, 6, bark, null, 0.3, rng.randf() * TAU)
	_bark(mb, p1, p2, 0.15 * s, 0.1 * s, 5, bark, null, 0.3, rng.randf() * TAU)
	# [height fraction, offset from the trunk, angle, radius, thickness]
	var pads: Array = [[0.62, 1.25, 0.0, 1.3, 0.8], [0.7, 1.3, 2.5, 1.05, 0.72], [0.79, 0.9, 4.3, 1.4, 0.85], [0.86, 0.85, 1.2, 0.95, 0.7], [0.92, 0.2, 3.2, 1.2, 0.8]]
	if variant == 1:
		pads = [[0.61, 1.35, 0.0, 1.3, 0.8], [0.72, 1.1, 3.0, 1.45, 0.86], [0.83, 0.95, 4.8, 1.15, 0.74], [0.93, 0.2, 1.6, 1.05, 0.78]]
	var a0 := rng.randf() * TAU
	var top_c := p2
	for pd in pads:
		var y: float = pd[0] * h
		var a: float = a0 + pd[2] + rng.randf_range(-0.25, 0.25)
		var off: float = pd[1] * s * rng.randf_range(0.9, 1.1)
		var r: float = pd[3] * s * rng.randf_range(0.92, 1.08)
		var t: float = pd[4] * s
		var c := _along(trunk, y) + Vector3(cos(a) * off, 0, sin(a) * off)
		c.y = y
		if off > 0.6 * s:
			mb.limb(_along(trunk, y - 0.9 * s), c + Vector3(0, 0.1 * s, 0), 0.09 * s, 0.045 * s, 4, ALEPPO_BARK, false)
		else:
			top_c = c
		# A cloud pad: rounded underside, puffy rim, nearly flat top.
		_blob_f(mb, rng, c, [Vector2(0, -0.06 * s), Vector2(r * 0.8, 0.02 * s), Vector2(r, t * 0.38), Vector2(r * 0.74, t * 0.86), Vector2(0, t)], 7, 0.18, ALEPPO, Pal.PINE, -0.3, ALEPPO_TOP, 0.84, 0.25)
	# Leader from the trunk top into the crowning pad.
	if top_c.y > p2.y:
		mb.limb(p2, top_c + Vector3(0, 0.1 * s, 0), 0.1 * s, 0.06 * s, 4, ALEPPO_BARK, false)
	mb.pop()


static func fig_tree(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_fig_tree(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Ficus carica, the garden and stream-bank tree: low, wider than tall, a broad umbrella of big coarse lumps over


## 3–4 smooth pale stems splaying from the ground (≈3.2 m tall, ≈4.3 m wide, ≤ 220 tris). kind = seed % 2: 0 has
## four stems, 1 three.
static func add_fig_tree(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var n := 4 if variant == 0 else 3
	var a0 := rng.randf() * TAU
	var lumps: Array = []
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var sp := deg_to_rad(rng.randf_range(30.0, 40.0))
		var l := rng.randf_range(1.45, 1.7) * s
		var base := Vector3(cos(a) * 0.12, -0.1, sin(a) * 0.12) * s
		var top := base + Vector3(cos(a) * sin(sp), cos(sp), sin(a) * sin(sp)) * l
		_bark(mb, base, top, 0.12 * s, 0.08 * s, 5, [FIG_BARK], FIG_BARK_LIGHT, 0.2)
		lumps.append([top + Vector3(0, 0.22, 0) * s, rng.randf_range(1.1, 1.22) * s])
	if n == 3:
		# Fill the widest gap so the umbrella stays round.
		var a := a0 + PI / 3.0
		lumps.append([Vector3(cos(a) * 0.95, 1.55, sin(a) * 0.95) * s, 1.05 * s])
	for L in lumps:
		_crown(mb, rng, L[0], L[1], 6, FIG, FIG_LOW, FIG_TOP, 0.15, 0.95, 0.38, 0.66, 0.78, -0.3)
	_puff(mb, rng, Vector3(rng.randf_range(-0.2, 0.2), 2.25, rng.randf_range(-0.2, 0.2)) * s, 1.4 * s, 6, FIG.lightened(0.03), FIG_LOW, FIG_TOP, 0.15, 0.95)


static func almond_tree(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_almond_tree(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Prunus dulcis, the orchard tree: an upright vase; a dark rough trunk forks at 0.9 m into 3–4 ascending branches
## carrying six rounded, separated lumps (an airy crown with sky between them). In early May the blossom is long
## gone: light yellow-green leaves (one or two paler lumps of new growth) and a sprinkle of young velvety fruit.
## kind = seed % 2: 0 two pale lumps and 12 fruits, 1 one and 8 (≈3.8 m tall, ≈3.4 m wide, ≤ 240 tris).
static func add_almond_tree(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var fork := Vector3(rng.randf_range(-0.08, 0.08), 0.9, rng.randf_range(-0.08, 0.08)) * s
	mb.limb(Vector3(0, -0.15 * s, 0), fork, 0.16 * s, 0.12 * s, 5, ALMOND_BARK, false)
	var n := 3 + rng.randi() % 2
	var mids := 5 - n
	var a0 := rng.randf() * TAU
	var lumps: Array = []
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25)
		var out := rng.randf_range(0.85, 1.0)
		var tip := fork + Vector3(cos(a) * out, rng.randf_range(1.75, 2.05), sin(a) * out) * s
		mb.limb(fork, tip, 0.1 * s, 0.05 * s, 4, ALMOND_BARK, false)
		lumps.append([tip + Vector3(cos(a) * 0.12, 0.2, sin(a) * 0.12) * s, rng.randf_range(0.74, 0.86) * s])
		if mids > 0 and i % 2 == 0:
			mids -= 1
			var b := a + (0.8 if i == 0 else -0.8)
			var root := fork.lerp(tip, 0.35)
			var mid := root + Vector3(cos(b) * 0.6, 0.4, sin(b) * 0.6) * s
			mb.limb(root, mid, 0.06 * s, 0.035 * s, 4, ALMOND_BARK, false)
			lumps.append([mid + Vector3(0, 0.16, 0) * s, rng.randf_range(0.6, 0.68) * s])
	lumps.append([fork + Vector3(rng.randf_range(-0.15, 0.15), 2.55, rng.randf_range(-0.15, 0.15)) * s, 0.72 * s])
	var white: Array[int] = []
	white.append(rng.randi() % lumps.size())
	if variant == 0:
		white.append((white[0] + 1 + rng.randi() % (lumps.size() - 1)) % lumps.size())
	var green_faces: Array = []
	for i in lumps.size():
		var L: Array = lumps[i]
		if i in white:
			green_faces.append_array(_lump4(mb, rng, L[0], L[1], 6, ALMOND_TOP, ALMOND, null, 0.14))
		else:
			green_faces.append_array(_lump4(mb, rng, L[0], L[1], 6, ALMOND, ALMOND_LOW, null, 0.14))
	var up := _upper(green_faces, 0.0)
	for i in (12 if variant == 0 else 8):
		var f: Array = up[rng.randi() % up.size()]
		_dot(mb, rng, f[0] + (f[1] as Vector3) * 0.02, 0.05 * s, ALMOND_FRUIT if i % 3 != 0 else ALMOND_FRUIT.darkened(0.12))


static func pomegranate(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_pomegranate(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Punica granatum, a small garden tree-shrub in May flower: a compact, slightly upright oval of three glossy lumps


## over 2–4 thin stems, sprinkled with scarlet-orange flowers on its outer upper surface (≈2.5 m tall, ≈2.3 m wide,
## ≤ 200 tris). No fruit (wrong season).
static func add_pomegranate(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var n := 2 + rng.randi() % 3
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.4, 0.4)
		mb.limb(Vector3(cos(a) * 0.06, -0.1, sin(a) * 0.06) * s, Vector3(cos(a) * 0.3, 0.95, sin(a) * 0.3) * s, 0.06 * s, 0.045 * s, 4, POMEG_BARK, false)
	var faces: Array = []
	for i in 2:
		var a := a0 + PI * float(i) + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(0.86, 0.94) * s
		faces.append_array(_crown(mb, rng, Vector3(cos(a) * 0.36 * s, 1.12 * s, sin(a) * 0.36 * s), r, 6, POMEG, POMEG_LOW, POMEG_TOP, 0.13, 1.1, 0.4, 0.66, 0.74, -0.3))
	faces.append_array(_puff(mb, rng, Vector3(cos(a0 + PI * 0.5) * 0.12, 1.72, sin(a0 + PI * 0.5) * 0.12) * s, rng.randf_range(0.78, 0.84) * s, 6, POMEG.lightened(0.03), POMEG_LOW, POMEG_TOP, 0.13, 1.12))
	var up := _upper(faces, 0.15)
	var k := 13 + rng.randi() % 3
	for i in k:
		var f: Array = up[rng.randi() % up.size()]
		_dot(mb, rng, f[0] + (f[1] as Vector3) * 0.02, rng.randf_range(0.065, 0.075) * s, POMEG_FLOWER_DARK if i < 3 else POMEG_FLOWER, Vector3(1, 0.8, 1))


static func laurel_tree(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_laurel_tree(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Laurus nobilis, Apollo's tree by the temenos: a dense, dark, glossy egg-cone with a slightly pointed tip, foliage


## from 0.4 m up over three barely visible stems: a lower, rounder cousin of the cypress (≈3.7 m, ≤ 180 tris).
static func add_laurel_tree(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	s *= rng.randf_range(0.95, 1.06)
	var a0 := rng.randf() * TAU
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0
		mb.limb(Vector3(cos(a) * 0.08, -0.1, sin(a) * 0.08) * s, Vector3(cos(a) * 0.3, 0.75, sin(a) * 0.3) * s, 0.07 * s, 0.05 * s, 4, ALMOND_BARK, false)
	# One egg-cone body, then two bulges that break its outline.
	var prof := [
		Vector2(0, 0.4), Vector2(0.95, 0.48), Vector2(1.4, 1.05), Vector2(1.38, 1.75), Vector2(1.08, 2.5),
		Vector2(0.55, 3.2), Vector2(0, 3.7),
	]
	blob(mb, rng, Vector3.ZERO, _scaled(prof, s), 7, 0.1, LAUREL, LAUREL_LOW, -0.3, LAUREL_TOP, 0.82)
	for i in 2:
		var a := a0 + 0.9 + PI * float(i) + rng.randf_range(-0.3, 0.3)
		_puff(mb, rng, Vector3(cos(a) * 0.75, 1.45 + 0.8 * float(i), sin(a) * 0.75) * s, (0.82 - 0.14 * float(i)) * s, 6, LAUREL.lightened(0.02), LAUREL_LOW, LAUREL_TOP, 0.12, 1.15)


static func date_palm(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_date_palm(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Leto's sacred palm (Phoenix theophrasti): one slender, banded, gently S-curved trunk leaning 6° towards +Z


## (yaw it towards the sacred basin), a crown of ten arching, drooping fronds and three upright young ones over a
## short skirt of dead fronds (≈6 m trunk, ≈7 m overall, ≤ 300 tris).
static func add_date_palm(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var h := rng.randf_range(5.8, 6.2) * s
	mb.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(6.0)), Vector3.ZERO))
	mb.cyl(Vector3(0, -0.15 * s, 0), 0.6 * s, 0.38 * s, 0.24 * s, 6, PALM_BARK_DARK, false, rng.randf() * TAU)
	var pts: Array = []
	var ph := rng.randf() * TAU
	for k in 6:
		var t := float(k) / 5.0
		pts.append(Vector3(sin(t * PI * 1.3 + ph) * 0.18 * s - sin(ph) * 0.18 * s, t * h, 0.0))
	for k in 5:
		var t0 := float(k) / 5.0
		var t1 := float(k + 1) / 5.0
		mb.limb(pts[k] + Vector3(0, -0.02, 0), pts[k + 1], lerpf(0.22, 0.17, t0) * s, lerpf(0.22, 0.17, t1) * s, 6, PALM_BARK if k % 2 == 0 else PALM_BARK_DARK, false)
	var top: Vector3 = pts[5]
	_lump4(mb, rng, top + Vector3(0, 0.1, 0) * s, 0.34 * s, 6, PALM_LOW, PALM_BARK_DARK, PALM)
	var a0 := rng.randf() * TAU
	# Dead skirt: short brown fronds hanging under the crown.
	for i in 5:
		var a := a0 + TAU * float(i) / 5.0 + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0, sin(a))
		var lat := Vector3(-d.z, 0, d.x)
		var b := top + d * 0.16 * s - Vector3(0, 0.08, 0) * s
		_leaf2(mb, b - lat * 0.1 * s, b + lat * 0.1 * s, b + d * 0.42 * s - Vector3(0, 0.7, 0) * s, PALM_DEAD, PALM_DEAD.darkened(0.15))
	for i in 13:
		var young := i >= 10
		var a := a0 + 0.3 + (TAU * float(i) / 10.0 if not young else TAU * float(i - 10) / 3.0 + 0.5) + rng.randf_range(-0.12, 0.12)
		if young:
			_frond(mb, top + Vector3(0, 0.15, 0) * s, a, deg_to_rad(rng.randf_range(62.0, 72.0)), deg_to_rad(rng.randf_range(10.0, 18.0)), rng.randf_range(1.5, 1.8) * s, 0.36 * s, 2)
		else:
			_frond(mb, top + Vector3(0, 0.12, 0) * s, a, deg_to_rad(rng.randf_range(30.0, 46.0)), deg_to_rad(rng.randf_range(32.0, 44.0)), rng.randf_range(2.2, 2.6) * s, 0.5 * s, 3)
	mb.pop()


## One feather-palm frond along a polyline that bends down by `droop` at each joint (`segs` 2 or 3 segments),


## folded along its rib like an inverted V, widest at its middle and pointed at the tip.
static func _frond(mb: MeshBuilder, base: Vector3, az: float, el: float, droop: float, length: float, width: float, segs: int = 2) -> void:
	var dh := Vector3(cos(az), 0, sin(az))
	var lat := Vector3(-dh.z, 0, dh.x)
	var rib: Array[Vector3] = [base + dh * 0.1]
	var widths: Array[float] = [0.0]
	var e := el
	for k in segs:
		var d := dh * cos(e) + Vector3.UP * sin(e)
		rib.append(rib[k] + d * length / float(segs))
		widths.append(0.0 if k == segs - 1 else width * (1.0 if k == 0 or segs == 2 else 0.8))
		e -= droop
	for k in segs:
		var a: Vector3 = rib[k]
		var b: Vector3 = rib[k + 1]
		var d := (b - a).normalized()
		var up := lat.cross(d).normalized()
		if up.y < 0.0:
			up = -up
		var col := PALM if k == 0 else (PALM_TIP if k == segs - 1 else PALM.lerp(PALM_TIP, 0.5))
		var wa := widths[k] * 0.5
		var wb := widths[k + 1] * 0.5
		var al := a + lat * wa - up * wa * 0.45
		var ar := a - lat * wa - up * wa * 0.45
		var bl := b + lat * wb - up * wb * 0.45
		var br := b - lat * wb - up * wb * 0.45
		if wa <= 0.0:
			_leaf2(mb, a, bl, b, col, PALM_LOW)
			_leaf2(mb, a, b, br, col.darkened(0.05), PALM_LOW)
		elif wb <= 0.0:
			_leaf2(mb, a, al, b, col, PALM_LOW)
			_leaf2(mb, a, b, ar, col.darkened(0.05), PALM_LOW)
		else:
			_leaf2(mb, a, al, bl, col, PALM_LOW)
			_leaf2(mb, a, bl, b, col, PALM_LOW)
			_leaf2(mb, a, b, br, col.darkened(0.05), PALM_LOW)
			_leaf2(mb, a, br, ar, col.darkened(0.05), PALM_LOW)


static func tamarisk(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_tamarisk(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Tamarix smyrnensis behind every beach: the most transparent tree. One or two twisted trunks lean 5–8° towards +Z


## and split into thin branches carrying six small, flat, feathery lumps with drooping edges and hanging sprays;
## two lumps carry soft pink plumes on top (≈4 m tall, ≈4.2 m wide, crown base 1.25 m, ≤ 260 tris).
## kind = seed % 2: 0 two trunks, 1 one.
static func add_tamarisk(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	mb.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(5.0, 8.0))), Vector3.ZERO))
	var forks: Array = []
	var trunks := 2 if variant == 0 else 1
	var ta := rng.randf() * TAU
	for t in trunks:
		var a := ta + PI * float(t)
		var b0 := Vector3(cos(a) * 0.14, -0.15, sin(a) * 0.14) * s if trunks == 2 else Vector3(0, -0.15 * s, 0)
		var k := b0 + Vector3(cos(a) * 0.2 + rng.randf_range(-0.1, 0.1), 0.75, sin(a) * 0.2 + rng.randf_range(-0.1, 0.1)) * s
		if t == 0:
			var f := k + Vector3(-cos(a) * 0.22 + rng.randf_range(-0.1, 0.1), rng.randf_range(0.6, 0.75), -sin(a) * 0.22) * s
			mb.limb(b0, k, 0.17 * s, 0.13 * s, 4, TAMARISK_BARK, false)
			mb.limb(k, f, 0.13 * s, 0.09 * s, 4, TAMARISK_BARK, false)
			forks.append(f)
		else:
			mb.limb(b0, k, 0.14 * s, 0.1 * s, 4, TAMARISK_BARK, false)
			forks.append(k)
	# Flat lumps whose rims droop below their centre, twisted so the facets stay irregular.
	var prof := [Vector2(0, -0.06), Vector2(1.0, -0.3), Vector2(0.8, 0.08), Vector2(0, 0.24)]
	var n := 6
	var a0 := rng.randf() * TAU
	var p0 := rng.randi() % n
	var pink := [p0, (p0 + 2 + rng.randi() % 3) % n]
	var strands := 3
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var lvl := float(i % 3) / 2.0
		var y := lerpf(1.65, 3.55, lvl) + rng.randf_range(-0.12, 0.12)
		var d := lerpf(1.35, 0.5, lvl) * rng.randf_range(0.9, 1.08)
		var r := lerpf(1.0, 0.85, lvl) * rng.randf_range(0.92, 1.06) * s
		var c := Vector3(cos(a) * d, y, sin(a) * d) * s
		var f: Vector3 = forks[i % forks.size()]
		mb.limb(f, c - Vector3(0, 0.06, 0) * s, 0.06 * s, 0.025 * s, 3, TAMARISK_TWIG, false)
		if i in pink:
			# A plume lump: muted pink body, pink top and a few upright racemes.
			# Spring bloom: a green feathery lump crowned with a spray of slim pink racemes (no pink plates).
			var pf := _blob_f(mb, rng, c, _scaled(prof, r), 6, 0.2, TAMARISK, TAMARISK_LOW, -0.2, TAMARISK_TOP, 0.72, 0.35)
			var up := _upper(pf, 0.55)
			for k in 6:
				var f2: Array = up[rng.randi() % up.size()]
				var n2: Vector3 = f2[1]
				_spindle(mb, f2[0] - n2 * 0.08 * s, (n2 + Vector3.UP * 1.2).normalized(), rng.randf_range(0.42, 0.6) * s, 0.12 * s, 3, TAMARISK_PINK_TOP, TAMARISK_PINK)
		else:
			_blob_f(mb, rng, c, _scaled(prof, r), 6, 0.2, TAMARISK, TAMARISK_LOW, -0.2, TAMARISK_TOP, 0.72, 0.35)
		# Weeping sprays hang from the outer rim of the lower lumps.
		if lvl < 0.9:
			for k in 2:
				if strands <= 0:
					break
				strands -= 1
				var sa := a + rng.randf_range(-0.9, 0.9)
				var p := c + Vector3(cos(sa) * r * 0.75, -0.18 * s, sin(sa) * r * 0.75)
				var dn := Vector3(cos(sa) * 0.35, -1.0, sin(sa) * 0.35)
				_spindle(mb, p - dn.normalized() * 0.08 * s, dn, rng.randf_range(0.65, 0.9) * s, 0.15 * s, 3, TAMARISK, TAMARISK_LOW)
	mb.pop()


static func juniper(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_juniper(mb, make_rng(seed_value), 1.0, posmod(seed_value, 3))
	return mb.commit()


## Juniperus phoenicea / macrocarpa on cliff tops and dune backs: a dense, irregular, wind-sheared cone, low on its


## windward north (-Z) side and streaming towards +Z, with a bleached contorted trunk showing at the windward base
## (keep yaw within ±25° so all stream south). kind = seed % 3: 0 tall (≈2.5 m), 1 bushy (≈2 m), 2 low dune mat
## (≈1 m tall, ≈2.5 m long). ≤ 160 tris.
static func add_juniper(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	s *= rng.randf_range(0.95, 1.1)
	var mat := variant == 2
	var t0 := Vector3(rng.randf_range(-0.1, 0.1), -0.12, -0.42) * s
	var t1 := Vector3(rng.randf_range(0.1, 0.22), 0.24 if not mat else 0.12, -0.62) * s
	var t2 := Vector3(rng.randf_range(-0.12, 0.02), 0.62 if not mat else 0.3, -0.3) * s
	mb.limb(t0, t1, 0.12 * s, 0.09 * s, 4, JUNIPER_BARK, false)
	mb.limb(t1, t2, 0.09 * s, 0.06 * s, 4, JUNIPER_BARK.lightened(0.06), false)
	var prof: Array
	var zs := 1.0
	match variant:
		0:
			prof = [Vector2(0, 0.3), Vector2(0.72, 0.34), Vector2(1.0, 0.7), Vector2(0.94, 1.15), Vector2(0.7, 1.6), Vector2(0.38, 2.05), Vector2(0, 2.45)]
		1:
			prof = [Vector2(0, 0.26), Vector2(0.85, 0.3), Vector2(1.1, 0.62), Vector2(1.04, 1.0), Vector2(0.78, 1.38), Vector2(0.4, 1.72), Vector2(0, 1.95)]
		_:
			prof = [Vector2(0, 0.08), Vector2(0.9, 0.12), Vector2(1.08, 0.34), Vector2(0.98, 0.58), Vector2(0.62, 0.8), Vector2(0, 0.95)]
			zs = 1.35
	# One body, sheared downwind (+Z), then two bulges on the lee side break its outline.
	mb.push(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0.3), Vector3(0, 0, zs)), Vector3(0, 0, 0.08 * s)))
	blob(mb, rng, Vector3.ZERO, _scaled(prof, s), 7, 0.13, JUNIPER, JUNIPER_LOW, -0.4, JUNIPER_TOP, 0.82, 0.15)
	var top: Vector2 = prof[prof.size() - 1]
	for i in 2:
		var a := PI * 0.5 + rng.randf_range(-0.3, 0.3) + (1.15 if i == 0 else -1.15)
		var y := top.y * (0.3 + 0.18 * float(i))
		var rr: float = (0.68 - 0.1 * float(i)) * (0.75 if mat else 1.0)
		_puff(mb, rng, Vector3(cos(a) * 0.8, y, sin(a) * 0.8) * s, rr * s, 6, JUNIPER.lightened(0.03), JUNIPER_LOW, JUNIPER_TOP, 0.16, 0.9 if not mat else 0.7)
	mb.pop()


# --- shrubs and phrygana -----------------------------------------------------------------------------------------

static func thyme_cushion(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_thyme_cushion(mb, make_rng(seed_value), 1.0, posmod(seed_value, 3))
	return mb.commit()


## The phrygana unit: a knee-high rounded cushion of two overlapping lumpy blobs (0.35–0.5 m tall, 0.85–1.0 m


## wide, ≤ 70 tris). kind = seed % 3: 0 thyme with pale pink-purple flower dots, 1 spiny burnet (rustier, no
## flowers), 2 sage / Phlomis (lighter grey-green, yellow dots).
static func add_thyme_cushion(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, kind: int = 0) -> void:
	var col: Color = [THYME, BURNET, SAGE][kind]
	var low: Color = [THYME_LOW, BURNET_LOW, SAGE_LOW][kind]
	var top: Color = [THYME_TOP, BURNET_TOP, SAGE_TOP][kind]
	var a := rng.randf() * TAU
	var d := Vector3(cos(a), 0, sin(a))
	var h := rng.randf_range(0.35, 0.5) * s
	var faces := _dome(mb, rng, d * 0.08 * s, rng.randf_range(0.34, 0.42) * s, h, 6, 0.2, col, low, top, 0.22)
	faces.append_array(_dome(mb, rng, -d * 0.17 * s, rng.randf_range(0.28, 0.33) * s, h * rng.randf_range(0.72, 0.85), 5, 0.2, col.lightened(0.03), low, top, 0.22))
	if kind == 1:
		return
	var up := _upper(faces, 0.4)
	for i in (5 if kind == 0 else 3):
		var f: Array = up[rng.randi() % up.size()]
		_dot(mb, rng, f[0] + (f[1] as Vector3) * 0.015, 0.05 * s, THYME_FLOWER if kind == 0 else SAGE_FLOWER, Vector3(1, 0.7, 1))


static func cistus_shrub(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_cistus_shrub(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Rock-rose in May flower: a loose rounded clump of three grey-green lumps strewn with flat five-petalled flowers


## laid on its surface (0.75–0.95 m tall, 1.1–1.3 m wide, ≤ 130 tris). kind = seed % 2: 0 pink Cistus creticus,
## 1 white C. salviifolius, both with gold centres.
static func add_cistus_shrub(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, kind: int = 0) -> void:
	var a0 := rng.randf() * TAU
	var faces: Array = []
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0 + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(0.4, 0.47) * s
		var hh := (rng.randf_range(0.82, 0.95) if i == 0 else rng.randf_range(0.6, 0.75)) * s
		faces.append_array(_dome(mb, rng, Vector3(cos(a), 0, sin(a)) * 0.24 * s, r, hh, 5, 0.16, CISTUS if i > 0 else CISTUS.lightened(0.03), CISTUS_LOW, CISTUS_TOP, 0.3))
	var up := _upper(faces, 0.35)
	var petal: Color = CISTUS_PINK if kind == 0 else Pal.DAISY
	for i in 11:
		var f: Array = up[rng.randi() % up.size()]
		var n: Vector3 = f[1]
		_flower_disc(mb, rng, f[0] + n * 0.03, n, 0.085 * s * rng.randf_range(0.9, 1.1), 5, petal if i % 4 != 3 else petal.lightened(0.08), Pal.GOLD)


static func broom_shrub(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_broom_shrub(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Spanish broom in flower, the strongest yellow of the wild slopes: an upright fountain of green rush stems whose


## upper half is wrapped in elongated yellow flower masses (1.3–1.75 m tall, 1.0–1.3 m wide, ≤ 140 tris).
## kind = seed % 2: 0 six stems, 1 seven.
static func add_broom_shrub(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var n := 6 + variant
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.35, 0.35)
		var sp := deg_to_rad(rng.randf_range(9.0, 22.0))
		var l := rng.randf_range(1.2, 1.65) * s
		var d := Vector3(cos(a) * sin(sp), cos(sp), sin(a) * sin(sp))
		var base := Vector3(cos(a) * 0.06, -0.05, sin(a) * 0.06) * s
		mb.limb(base, base + d * l, 0.035 * s, 0.0, 4, BROOM_STEM, false)
		for k in 2:
			var t := 0.48 + 0.24 * float(k) + rng.randf_range(0.0, 0.08)
			var r := rng.randf_range(0.075, 0.095) * s
			var ln := rng.randf_range(0.36, 0.46) * s
			_spindle(mb, base + d * (l * t - ln * 0.3), d, ln, r, 4, BROOM if k == 1 or i % 2 == 0 else BROOM.darkened(0.04), BROOM_LOW)


static func oleander(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_oleander(mb, make_rng(seed_value), 1.0, posmod(seed_value, 3))
	return mb.commit()


## Nerium oleander, the stream and well shrub: a dense, upright-oval, multi-stemmed clump of dark leathery foliage


## with clusters of flowers on its outer top (1.9–2.4 m tall, 1.6–1.9 m wide, ≤ 200 tris). kind = seed % 3: 0 pink,
## 1 deep pink, 2 white.
static func add_oleander(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, kind: int = 0) -> void:
	s *= rng.randf_range(0.94, 1.06)
	var a0 := rng.randf() * TAU
	for i in 2:
		var a := a0 + PI * float(i) + 0.4
		mb.limb(Vector3(cos(a) * 0.08, -0.08, sin(a) * 0.08) * s, Vector3(cos(a) * 0.24, 0.62, sin(a) * 0.24) * s, 0.05 * s, 0.035 * s, 3, Pal.WOOD, false)
	var faces: Array = []
	var prof := [Vector2(0, 0.42), Vector2(0.6, 0.48), Vector2(0.9, 0.85), Vector2(0.92, 1.3), Vector2(0.78, 1.72), Vector2(0.45, 2.08), Vector2(0, 2.3)]
	faces.append_array(_blob_f(mb, rng, Vector3.ZERO, _scaled(prof, s), 7, 0.17, OLEANDER, OLEANDER_LOW, -0.4, OLEANDER_TOP, 0.82, 0.3))
	var pa := a0 + 1.2 + rng.randf_range(-0.3, 0.3)
	faces.append_array(_puff(mb, rng, Vector3(cos(pa) * 0.3, 1.5, sin(pa) * 0.3) * s, 0.62 * s, 6, OLEANDER.lightened(0.02), OLEANDER_LOW, OLEANDER_TOP, 0.15, 1.1))
	var fc: Array = [[OLEANDER_PINK, OLEANDER_PINK_LIGHT], [OLEANDER_DEEP, OLEANDER_DEEP.lightened(0.1)], [Pal.DAISY, Pal.MARBLE_SHADE]][kind]
	# Flowers come in clusters on the outer, upper faces.
	var up := _upper(faces, 0.3)
	for c in 5:
		var f0: Array = up[rng.randi() % up.size()]
		var c0: Vector3 = f0[0]
		var n0: Vector3 = f0[1]
		var tang := n0.cross(Vector3.UP if absf(n0.y) < 0.95 else Vector3.RIGHT).normalized()
		var bit := n0.cross(tang).normalized()
		for k in (4 if c < 3 else 2):
			var o := (tang * cos(float(k) * 2.1) + bit * sin(float(k) * 2.1)) * 0.12 * s
			_dot(mb, rng, c0 + n0 * 0.03 + o * (0.0 if k == 0 else 1.0), rng.randf_range(0.09, 0.11) * s, fc[k % 2], Vector3(1, 0.75, 1))


static func giant_reed(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_giant_reed(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Arundo donax in the lower gully: a fan of straight canes (2.4–3.4 m) from a 0.8 m base, with drooping strap


## leaves and three buff plumes (≤ 200 tris). kind = seed % 2: 1 is a little shorter and denser.
static func add_giant_reed(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var n := 11 if variant == 0 else 12
	var tops: Array = []
	for i in n:
		var a := rng.randf() * TAU
		var dd := sqrt(rng.randf()) * 0.4
		var base := Vector3(cos(a) * dd, -0.1, sin(a) * dd) * s
		var tilt := deg_to_rad(2.0 + 9.0 * dd / 0.4)
		var d := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
		var hh := rng.randf_range(2.4, 3.4) * s * (0.92 if variant == 1 else 1.0)
		var top := base + d * hh
		mb.limb(base, top, 0.03 * s, 0.015 * s, 3, REED if i % 3 != 0 else REED.darkened(0.06), false)
		tops.append([top, d, hh])
		for k in 4:
			var t := 0.3 + 0.16 * float(k) + rng.randf_range(0.0, 0.06)
			var p := base + d * hh * t
			var la := rng.randf() * TAU
			var dh := Vector3(cos(la), 0, sin(la))
			var lat := Vector3(-dh.z, 0, dh.x)
			var ll := rng.randf_range(0.5, 0.7) * s
			var tip := p + dh * ll * 0.85 + Vector3(0, rng.randf_range(-0.12, 0.08), 0) * s
			_leaf2(mb, p + lat * 0.035 * s, p - lat * 0.035 * s, tip, REED_LEAF_LIT, REED_LEAF)
	tops.sort_custom(func(x, y): return x[2] > y[2])
	for i in 3:
		var T: Array = tops[i]
		var d: Vector3 = T[1]
		var bend := (d + Vector3(d.x, 0, d.z).normalized() * 0.5).normalized()
		_spindle(mb, T[0] - d * 0.06 * s, bend, 0.36 * s, 0.07 * s, 4, REED_PLUME, REED_PLUME.darkened(0.12))


static func sea_lily(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_sea_lily(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2) == 1)
	return mb.commit()


## Pancratium maritimum on the upper beach: a fan of arching blue-green strap leaves; seed % 2 == 1 adds one or two


## white star flowers with pale trumpets on 0.3 m stalks (≤ 70 tris).
static func add_sea_lily(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, flowering: bool = false) -> void:
	var n := 5 + rng.randi() % 3
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25)
		var l := rng.randf_range(0.25, 0.38) * s
		var dh := Vector3(cos(a), 0, sin(a))
		var lat := Vector3(-dh.z, 0, dh.x) * 0.02 * s
		var b := dh * 0.03 * s
		var m := b + dh * l * 0.4 + Vector3(0, l * 0.55, 0)
		var t := m + dh * l * 0.6 + Vector3(0, -l * 0.12, 0)
		_leaf2(mb, b - lat, b + lat, m + lat, SEA_LILY_LIT, SEA_LILY)
		_leaf2(mb, b - lat, m + lat, m - lat, SEA_LILY_LIT, SEA_LILY)
		_leaf2(mb, m - lat, m + lat, t, SEA_LILY_LIT.lightened(0.04), SEA_LILY)
	if not flowering:
		return
	for k in 1 + rng.randi() % 2:
		var a := rng.randf() * TAU
		var top := Vector3(cos(a) * 0.05, rng.randf_range(0.28, 0.33), sin(a) * 0.05) * s
		var lat := Vector3(-sin(a), 0, cos(a)) * 0.008 * s
		_leaf2(mb, lat, -lat, top, SEA_LILY_LIT, SEA_LILY)
		var rot := rng.randf() * TAU
		for i in 6:
			var b := rot + TAU * float(i) / 6.0
			var o := Vector3(cos(b), 0, sin(b))
			var w := Vector3(-o.z, 0, o.x) * 0.012 * s
			mb.tri(top + w, top + o * 0.07 * s + Vector3(0, 0.012, 0) * s, top - w, Pal.DAISY)
		mb.cyl(top, 0.04 * s, 0.006 * s, 0.026 * s, 4, SEA_LILY_TRUMPET, false, rot)


# --- rocks ---------------------------------------------------------------------------------------------------

static func rock_small(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_rock_small(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## A knee-high stone (~0.8 m) with a pebble or two.
static func add_rock_small(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var r := rng.randf_range(0.36, 0.48) * s
	chunk(mb, rng, Vector3(0, -0.05, 0), r, r * rng.randf_range(0.85, 1.1), 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK)
	var n := 1 + rng.randi() % 2
	for i in n:
		var a := rng.randf() * TAU
		var rr := r * rng.randf_range(0.32, 0.45)
		chunk(mb, rng, Vector3(cos(a), 0, sin(a)) * (r + rr * 0.9) + Vector3(0, -0.03, 0), rr, rr * 0.9, 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK)


static func rock_large(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_rock_large(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Big weathered boulder (1.5–2.5 m) with smaller blocks around it, for cliffs and hillsides.
static func add_rock_large(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var r := rng.randf_range(0.8, 1.05) * s
	var h := r * rng.randf_range(1.35, 1.7)
	chunk(mb, rng, Vector3(0, -0.25, 0), r, h, 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK, true)
	var a := rng.randf() * TAU
	var r2 := r * rng.randf_range(0.55, 0.68)
	chunk(mb, rng, Vector3(cos(a), 0, sin(a)) * (r * 0.9 + r2 * 0.5) + Vector3(0, -0.15, 0), r2, r2 * 1.25, 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK, true)
	var a2 := a + rng.randf_range(1.8, 2.6)
	var r3 := r * 0.32
	chunk(mb, rng, Vector3(cos(a2), 0, sin(a2)) * (r + r3 * 0.7) + Vector3(0, -0.04, 0), r3, r3 * 0.9, 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK)


static func beach_rock(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_beach_rock(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Low, rounded, sea-darkened rocks half buried in the sand at the waterline (~2 m group).
static func add_beach_rock(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var r := rng.randf_range(0.65, 0.85) * s
	var prof := [Vector2(r * 0.95, 0), Vector2(r * 1.04, r * 0.24), Vector2(r * 0.82, r * 0.52), Vector2(r * 0.4, r * 0.68), Vector2(0, r * 0.72)]
	mb.push(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))) * Basis.from_scale(Vector3(1.25, 1, 0.9)), Vector3(0, -0.14, 0)))
	blob(mb, rng, Vector3.ZERO, prof, 6, 0.14, Pal.ROCK_DARK, PX.ROCK_WET, -0.05, Pal.ROCK, 0.85, 0.3)
	mb.pop()
	var n := 2 + rng.randi() % 2
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.4, 0.4)
		var rr := r * rng.randf_range(0.32, 0.5)
		var p := Vector3(cos(a), 0, sin(a)) * (r + rr * rng.randf_range(0.5, 1.3))
		chunk(mb, rng, p + Vector3(0, -0.06, 0), rr, rr * 0.65, 5, Pal.ROCK_DARK, PX.ROCK_WET, Pal.ROCK)


## Chunky angular rock: a jittered, tilted, squashed prism with a sun-bleached top. Origin at its base centre.
static func chunk(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, h: float, sides: int, col: Color, col_low: Color, col_top: Color, tall: bool = false) -> void:
	var prof: Array
	if tall:
		prof = [Vector2(r * 0.9, 0), Vector2(r * 1.02, h * 0.36), Vector2(r * 0.9, h * 0.72), Vector2(r * 0.5, h * 0.96), Vector2(0, h)]
	else:
		prof = [Vector2(r * 0.9, 0), Vector2(r, h * 0.48), Vector2(r * 0.6, h * 0.94), Vector2(0, h)]
	var tilt := Vector3(rng.randf_range(-0.16, 0.16), rng.randf() * TAU, rng.randf_range(-0.16, 0.16))
	var sq := Vector3(rng.randf_range(1.0, 1.35), 1.0, rng.randf_range(0.78, 1.0))
	mb.push(Transform3D(Basis.from_euler(tilt) * Basis.from_scale(sq), c))
	blob(mb, rng, Vector3.ZERO, prof, sides, 0.2, col, col_low, -0.3, col_top, 0.82, 0.35)
	mb.pop()


# --- flowers and grass ---------------------------------------------------------------------------------------

static func flowers_lavender(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_lavender(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## French lavender (Lavandula stoechas) of the wild ring: a small grey-green cushion bristling with short stalks,


## each ending in a fat purple head with two pale "rabbit-ear" bracts (0.35–0.45 m tall, ≤ 80 tris).
static func add_lavender(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var r := 0.22 * s
	blob(mb, rng, Vector3(0, -0.02, 0), [Vector2(r, 0), Vector2(r * 0.8, r * 0.62), Vector2(0, r * 1.05)], 5, 0.16, Pal.OLIVE_LEAF, Pal.OLIVE_LEAF_DARK, -0.1, Pal.OLIVE_LEAF.lightened(0.06), 0.8)
	var a0 := rng.randf() * TAU
	for k in 6:
		var b := a0 + TAU * float(k) / 6.0 + rng.randf_range(-0.35, 0.35)
		var el := rng.randf_range(0.12, 0.55)
		var dir := Vector3(cos(b) * sin(el), cos(el), sin(b) * sin(el))
		var root := Vector3(cos(b) * r * 0.35, r * 0.7, sin(b) * r * 0.35)
		var top := root + dir * rng.randf_range(0.11, 0.17) * s
		var lat := Vector3(-sin(b), 0, cos(b)) * 0.008 * s
		_leaf2(mb, root - lat, root + lat, top, Pal.OLIVE_LEAF_DARK, Pal.OLIVE_LEAF_DARK)
		var hl := rng.randf_range(0.1, 0.13) * s
		_spindle(mb, top - dir * 0.01 * s, dir, hl * 1.15, 0.044 * s, 3, Pal.LAVENDER, LAV_HEAD_LOW)
		var tip := top + dir * hl * 0.92
		for e in [-1.0, 1.0]:
			var side: Vector3 = lat.normalized() * e
			mb.tri(tip, tip + (dir * 0.045 + side * 0.03) * s, tip + side * 0.016 * s, LAV_BRACT)


static func flowers_poppy(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_poppies(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## A red poppy patch (~0.7 m across): a few grass blades and 5–7 open red cups with dark hearts on thin stems,


## plus a bud or two, clustered so drifts read as red patches, never confetti (0.25–0.45 m, ≤ 80 tris).
static func add_poppies(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	_blades(mb, rng, 5, 0.22 * s, Vector2(0.18, 0.26) * s, [Pal.GRASS_DARK, Pal.GRASS], Vector2(15, 35), 0.035 * s)
	var n := 5 + rng.randi() % 3
	var a0 := rng.randf() * TAU
	for i in n + 2:
		var a := a0 + TAU * float(i) / float(n + 2) + rng.randf_range(-0.3, 0.3)
		var d := rng.randf_range(0.04, 0.3) * s
		var base := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var bud := i >= n
		var h := (rng.randf_range(0.18, 0.28) if bud else rng.randf_range(0.25, 0.45)) * s
		var top := base + Vector3(cos(a) * 0.06 * s, h, sin(a) * 0.06 * s)
		var lat := Vector3(-sin(a), 0, cos(a)) * 0.01 * s
		mb.tri(base - lat, top, base + lat, Pal.GRASS_DARK)
		if bud:
			_dot(mb, rng, top, 0.03 * s, Pal.GRASS_DARK, Vector3(1, 1.4, 1))
		else:
			_cup_in(mb, rng, top, 0.085 * s * rng.randf_range(0.9, 1.1), 0.05 * s, 5, Pal.POPPY, Pal.SKIN_SHADOW)


static func flowers_daisy(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_daisies(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## A white chamomile patch (~0.7 m across) for village and meadow drifts: two small leafy blobs and eight


## upward-facing white flowers with gold centres on single-triangle stems (0.12–0.26 m, ≤ 80 tris). The white
## heads catch the moonlight at night.
static func add_daisies(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var a0 := rng.randf() * TAU
	for i in 2:
		var a := a0 + PI * float(i)
		var r := 0.15 * s * rng.randf_range(0.9, 1.1)
		var prof := [Vector2(r, 0.0), Vector2(r * 0.72, r * 0.48), Vector2(0, r * 0.62)]
		blob(mb, rng, Vector3(cos(a) * 0.1, -0.02, sin(a) * 0.1) * s, prof, 5, 0.18, Pal.GRASS if i == 0 else Pal.GRASS_DARK, Pal.GRASS_DARK)
	for i in 8:
		var a := a0 + TAU * float(i) / 8.0 + rng.randf_range(-0.3, 0.3)
		var d := (0.1 + 0.2 * float(i % 3) / 2.0) * s * rng.randf_range(0.9, 1.15)
		var base := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var top := base + Vector3(0, rng.randf_range(0.12, 0.26) * s, 0)
		var lat := Vector3(-sin(a), 0, cos(a)) * 0.008 * s
		mb.tri(base - lat, top, base + lat, Pal.GRASS_DARK)
		var tilt := Vector3(rng.randf_range(-0.26, 0.26), 1.0, rng.randf_range(-0.26, 0.26))
		_flower_disc(mb, rng, top, tilt, rng.randf_range(0.05, 0.065) * s, 6, Pal.DAISY, Pal.GOLD)


static func flowers_anemone(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_anemones(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Anemone coronaria under the olive rows, in the temenos and on the gully banks: a low dark rosette with 6–7 open


## cups of mixed colours on short stems (0.1–0.22 m, ≤ 80 tris). kind = seed % 2: 0 violet / pink / white,
## 1 scarlet / violet / white.
static func add_anemones(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, kind: int = 0) -> void:
	var a0 := rng.randf() * TAU
	for i in 2:
		var a := a0 + PI * float(i)
		var r := 0.12 * s * rng.randf_range(0.9, 1.15)
		blob(mb, rng, Vector3(cos(a) * 0.08, -0.02, sin(a) * 0.08) * s, [Vector2(r, 0.0), Vector2(r * 0.7, r * 0.3), Vector2(0, r * 0.42)], 5, 0.2, ROSETTE if i == 0 else ROSETTE_LIGHT, ROSETTE)
	var cols: Array = [Pal.LAVENDER, Pal.BOUGAINVILLEA, Pal.LAVENDER, Pal.DAISY, Pal.BOUGAINVILLEA, Pal.LAVENDER, Pal.BOUGAINVILLEA]
	if kind == 1:
		cols = [Pal.POPPY, Pal.LAVENDER, Pal.POPPY, Pal.DAISY, Pal.LAVENDER, Pal.POPPY, Pal.LAVENDER]
	var n := 6 + rng.randi() % 2
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.35, 0.35)
		var d := rng.randf_range(0.06, 0.26) * s
		var base := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var top := base + Vector3(cos(a) * 0.03 * s, rng.randf_range(0.1, 0.22) * s, sin(a) * 0.03 * s)
		var lat := Vector3(-sin(a), 0, cos(a)) * 0.008 * s
		mb.tri(base - lat, top, base + lat, ROSETTE)
		_cup_in(mb, rng, top, rng.randf_range(0.07, 0.08) * s, 0.03 * s, 5, cols[i], Pal.SKIN_SHADOW)


static func grass_tuft(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_grass_tuft(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Bunchgrass accent (Hyparrhenia / feather grass) at rock bases and on cliff tops: nine thin blades running from a


## dark base to dry straw tips, splayed 20–45°, and three thin seed stalks with pale heads (≤ 0.38 m, ≤ 60 tris).
## kind = seed % 2: 1 is drier.
static func add_grass_tuft(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, kind: int = 0) -> void:
	var tip_col := TUFT_TIP if kind == 1 else TUFT_MID.lerp(TUFT_TIP, 0.4)
	var a0 := rng.randf() * TAU
	for i in 9:
		var a := a0 + TAU * float(i) / 9.0 + rng.randf_range(-0.25, 0.25)
		var dh := Vector3(cos(a), 0, sin(a))
		var lat := Vector3(-dh.z, 0, dh.x) * 0.025 * s
		var base := dh * rng.randf_range(0.0, 0.07) * s + Vector3(0, -0.02, 0)
		var h := rng.randf_range(0.24, 0.36) * s
		var sp := deg_to_rad(rng.randf_range(20.0, 45.0))
		var tip := base + dh * h * tan(sp) + Vector3(0, h, 0)
		if i % 2 == 0:
			# Bent blade: a dark lower half and a dry tip.
			var mid := base + dh * h * tan(sp) * 0.35 + Vector3(0, h * 0.55, 0)
			_leaf2(mb, base - lat, base + lat, mid + lat * 0.6, TUFT_BASE, TUFT_BASE.darkened(0.1))
			_leaf2(mb, base - lat, mid + lat * 0.6, mid - lat * 0.6, TUFT_BASE, TUFT_BASE.darkened(0.1))
			_leaf2(mb, mid - lat * 0.6, mid + lat * 0.6, tip, tip_col, TUFT_MID.darkened(0.08))
		else:
			_leaf2(mb, base - lat, base + lat, tip, TUFT_MID if i % 4 == 1 else TUFT_BASE.lerp(TUFT_MID, 0.5), TUFT_BASE)
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0 + 0.5
		var dh := Vector3(cos(a), 0, sin(a))
		var lat := Vector3(-dh.z, 0, dh.x) * 0.006 * s
		var top := dh * 0.07 * s + Vector3(0, rng.randf_range(0.3, 0.35) * s, 0)
		_leaf2(mb, -lat, lat, top, TUFT_MID, TUFT_BASE)
		mb.limb(top - dh * 0.01 * s, top + (dh * 0.25 + Vector3.UP).normalized() * 0.05 * s, 0.014 * s, 0.0, 3, TUFT_SEED, false)


## Fan of single-triangle grass blades (two-sided): `n` blades within `spread`, heights in `hr`, splay in `spl`


## degrees, base width `w`.
static func _blades(mb: MeshBuilder, rng: RandomNumberGenerator, n: int, spread: float, hr: Vector2, cols: Array, spl: Vector2, w: float) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var dh := Vector3(cos(a), 0, sin(a))
		var base := dh * sqrt(rng.randf()) * spread * 0.4 + Vector3(0, -0.02, 0)
		var h := rng.randf_range(hr.x, hr.y)
		var tip := base + dh * h * tan(deg_to_rad(rng.randf_range(spl.x, spl.y))) + Vector3(0, h, 0)
		var lat := Vector3(-dh.z, 0, dh.x) * w * 0.5
		var col: Color = cols[i % cols.size()]
		_leaf2(mb, base - lat, base + lat, tip, col, col.darkened(0.1))


static func _grass_blades(mb: MeshBuilder, rng: RandomNumberGenerator, n: int, spread: float, h: float, cols: Array, width: float = 1.0) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		var base := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var out := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.24) * h / 0.4
		var tip := base + out + Vector3(0, h * rng.randf_range(0.6, 1.1), 0)
		var col: Color = cols[i % cols.size()]
		mb.limb(base, tip, 0.035 * h / 0.4 * width, 0.0, 3, col, false)


## The instanced meadow tuft of the grass system (scripts/world/grass.gd): eight single-triangle blades of mixed
## length fanned out from a tight base (short ones form the carpet, long ones the tufts' tips) and two head
## triangles at the tips of the two longest blades, which the shader shows as seed heads or flowers or hides.
## 10 triangles / 30 vertices, non-indexed, <= 0.32 m tall. Raw arrays because it needs UVs: UV = (head flag,
## t) with t = 0 at the root and 1 at the tip; normals (0, 1, 0); colours white (the shader takes the root
## colour from INSTANCE_CUSTOM and the tip from the instance colour). The seed only jitters the blades.
static func grass_clump(seed_value: int) -> ArrayMesh:
	var rng := make_rng(seed_value, 41)
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var heights := [0.32, 0.17, 0.25, 0.12, 0.28, 0.15, 0.21, 0.11]
	var splays := [12.0, 38.0, 22.0, 48.0, 16.0, 42.0, 30.0, 52.0]
	var apex: Array[Vector3] = []
	var perp: Array[Vector3] = []
	for i in 8:
		var a := deg_to_rad(45.0 * float(i) + 17.0 * float(i % 3) + rng.randf_range(-14.0, 14.0))
		var d := Vector3(cos(a), 0, sin(a))
		var p := Vector3(-d.z, 0, d.x)
		var base := d * rng.randf_range(0.02, 0.08) - Vector3(0, 0.015, 0)
		var h: float = heights[i]
		var tip := base + d * h * tan(deg_to_rad(splays[i])) + Vector3(0, h, 0)
		var w := 0.04 if h > 0.2 else 0.046
		v.append_array([base - p * w, tip, base + p * w])
		uv.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(0, 0)])
		apex.append(tip)
		perp.append(p)
	for i in [0, 4]:
		var t: Vector3 = apex[i]
		var p: Vector3 = perp[i]
		v.append_array([t - p * 0.026 - Vector3(0, 0.012, 0), t + Vector3(0, 0.045, 0), t + p * 0.026 - Vector3(0, 0.012, 0)])
		uv.append_array([Vector2(1, 1), Vector2(1, 1), Vector2(1, 1)])
	return _grass_arrays(v, uv)


## Meadow flowers for the grass system: three sprigs of different heights, each a thin stem and a flat
## four-point head facing up (two triangles), plus two short leaves. 11 triangles, <= 0.24 m tall, same UV
## convention as grass_clump (heads have UV.x = 1); the shader colours the heads from a palette index.
static func grass_flowers(seed_value: int) -> ArrayMesh:
	var rng := make_rng(seed_value, 43)
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var hs := [0.22, 0.16, 0.12]
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf_range(-0.4, 0.4)
		var d := Vector3(cos(a), 0, sin(a))
		var p := Vector3(-d.z, 0, d.x)
		var base := d * rng.randf_range(0.04, 0.09) - Vector3(0, 0.015, 0)
		var h: float = hs[i]
		var top := base + d * rng.randf_range(0.02, 0.05) + Vector3(0, h, 0)
		v.append_array([base - p * 0.014, top, base + p * 0.014])
		uv.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(0, 0)])
		var r: float = [0.052, 0.046, 0.04][i]
		var rot := rng.randf() * TAU
		var q: Array[Vector3] = []
		for k in 4:
			var ang := rot + TAU * float(k) / 4.0
			var rr := r if k % 2 == 0 else r * 0.8
			q.append(top + Vector3(cos(ang) * rr, 0.004 * float(k % 2), sin(ang) * rr))
		v.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
		for k in 6:
			uv.append(Vector2(1, 1))
	for i in 2:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var p := Vector3(-d.z, 0, d.x)
		var base := -Vector3(0, 0.015, 0)
		var tip := d * 0.09 + Vector3(0, 0.07, 0)
		v.append_array([base - p * 0.03, tip, base + p * 0.03])
		uv.append_array([Vector2(0, 0), Vector2(0, 0.5), Vector2(0, 0)])
	return _grass_arrays(v, uv)


static func _grass_arrays(v: PackedVector3Array, uv: PackedVector2Array) -> ArrayMesh:
	var n := PackedVector3Array()
	var c := PackedColorArray()
	for i in v.size():
		n.append(Vector3.UP)
		c.append(Color.WHITE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# --- ruins ---------------------------------------------------------------------------------------------------

static func ruin_column(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_ruin_column(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Broken standing fluted marble column on its plinth, with its missing drum at its foot (2.3–3.5 m).
static func add_ruin_column(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var h := rng.randf_range(1.9, 3.0) * s
	var r := 0.36 * s
	box5(mb, Vector3(0, 0.1 * s, 0), Vector3(1.05, 0.36, 1.05) * s, Pal.MARBLE_SHADE, Pal.MARBLE, Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.03, 0.03)))
	mb.cyl(Vector3(0, 0.28 * s, 0), 0.08 * s, 0.47 * s, 0.47 * s, 8, Pal.MARBLE_SHADE, false)
	mb.cyl(Vector3(0, 0.36 * s, 0), 0.08 * s, 0.47 * s, 0.4 * s, 8, Pal.MARBLE, false)
	mb.push(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.04, 0.04))), Vector3(0, 0.44 * s, 0)))
	fluted_shaft(mb, rng, Vector3.ZERO, h, r, r * 0.9, 8, Pal.MARBLE, Pal.LIMESTONE, 0.45 * s)
	mb.pop()
	# The missing drum lies at its foot, end on to the camera more often than not.
	var a := rng.randf_range(0.3, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
	var p := Vector3(sin(a), 0, cos(a)) * 1.15 * s
	mb.push(Transform3D(Basis(Vector3.UP, a + rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, r * 0.82, 0)))
	fluted_shaft(mb, rng, Vector3(0, -0.3 * s, 0), 0.6 * s, r * 0.9, r * 0.9, 8, Pal.MARBLE, Pal.LIMESTONE, 0.0, true)
	mb.pop()
	_grass_blades(mb, rng, 6, 0.55 * s, 0.36 * s, [Pal.GRASS, Pal.GRASS_DARK, Pal.GRASS_DRY], 1.3)


static func ruin_fallen(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_ruin_fallen(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## A toppled column: drums scattered in a loose line, and its capital landed upright at the end (~3.5 m).
static func add_ruin_fallen(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var r := 0.36 * s
	var n := 2 + rng.randi() % 2
	var x := -1.5 * s
	for i in n:
		var l := rng.randf_range(0.7, 0.95) * s
		var yaw := rng.randf_range(-0.6, 0.6) + (0.0 if i % 2 == 0 else rng.randf_range(0.5, 1.0))
		var c := Vector3(x + 0.45 * s, r * 0.82, rng.randf_range(-0.25, 0.25) * s)
		mb.push(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI * 0.5) * Basis(Vector3.UP, rng.randf() * TAU), c))
		fluted_shaft(mb, rng, Vector3(0, -l * 0.5, 0), l, r, r, 8, Pal.MARBLE, Pal.LIMESTONE, 0.0, true)
		mb.pop()
		x += rng.randf_range(0.95, 1.2) * s
	# Doric capital, landed the right way up and half sunk.
	mb.push(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))), Vector3(x + 0.35 * s, -0.06 * s, rng.randf_range(-0.2, 0.2) * s)))
	doric_capital(mb, Vector3.ZERO, r * 1.05, Pal.MARBLE, Pal.MARBLE_SHADE)
	mb.pop()
	_grass_blades(mb, rng, 7, 1.3 * s, 0.34 * s, [Pal.GRASS, Pal.GRASS_DARK, Pal.GRASS_DRY], 1.3)


static func ruin_base(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_ruin_base(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Fragment of a temple's stepped platform with broken column stubs (~4.6 × 3 m).
static func add_ruin_base(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var lost := rng.randi() % 2
	# Lower step: two rows of limestone blocks; the front right one has slid off.
	for row in 2:
		for i in 4:
			var x := (-1.73 + 1.15 * float(i)) * s
			var z := (0.68 - 1.4 * float(row)) * s
			var tilt := Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.03, 0.03))
			if row == 0 and i == 3:
				box5(mb, Vector3(x + 0.3 * s, 0.04 * s, z + 0.55 * s), Vector3(1.08, 0.28, 1.3) * s, Pal.LIMESTONE_DARK, Pal.LIMESTONE, Vector3(0.12, 0.45, 0.1))
				continue
			box5(mb, Vector3(x, 0.08 * s, z), Vector3(1.1, 0.3 + rng.randf_range(-0.03, 0.03), 1.36) * s, Pal.LIMESTONE_DARK, Pal.LIMESTONE, tilt)
	# Upper step (stylobate): marble blocks, the right end lost on some seeds.
	for row in 2:
		for i in 3:
			if i == 2 and lost == 1 and row == 0:
				continue
			var x := (-1.15 + 1.15 * float(i)) * s
			var z := (0.25 - 1.0 * float(row)) * s
			var tilt := Vector3(rng.randf_range(-0.025, 0.025), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.025, 0.025))
			box5(mb, Vector3(x, 0.36 * s, z), Vector3(1.1, 0.26 + rng.randf_range(-0.02, 0.03), 0.96) * s, Pal.MARBLE_SHADE, Pal.MARBLE, tilt)
	var heights := [1.35, 0.5, 0.9]
	var k0 := rng.randi() % 3
	for i in 3:
		var x := (-1.15 + 1.15 * float(i)) * s
		var h: float = heights[(i + k0) % 3] * s * rng.randf_range(0.85, 1.1)
		fluted_shaft(mb, rng, Vector3(x, 0.49 * s, -0.75 * s), h, 0.34 * s, 0.33 * s, 7, Pal.MARBLE, Pal.LIMESTONE, 0.3 * s)
	# A fragment that fell off the front.
	box5(mb, Vector3(rng.randf_range(-1.2, 0.6), 0.1, 1.85) * s, Vector3(0.6, 0.24, 0.42) * s, Pal.MARBLE_SHADE, Pal.MARBLE, Vector3(0.15, rng.randf() * TAU, -0.1))
	_grass_blades(mb, rng, 8, 2.2 * s, 0.36 * s, [Pal.GRASS, Pal.GRASS_DARK, Pal.GRASS_DRY], 1.3)


# --- objects -------------------------------------------------------------------------------------------------

static func amphora(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	var rng := make_rng(seed_value)
	add_amphora(mb, rng, 1.0)
	if rng.randf() < 0.6:
		mb.push_at(Vector3(0.42, 0, 0.12), rng.randf() * TAU, Vector3.ONE * 0.7)
		add_amphora(mb, rng, 1.0, 1)
		mb.pop()
	return mb.commit()


## Terracotta storage amphora (~0.85 m) with a painted band and two handles. `lod` 1: no handles (≈90 tris);


## `lod` 2: five-sided jar for crowded scenes (≈50 tris).
static func add_amphora(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, lod: int = 0) -> void:
	var body := Pal.TERRACOTTA
	var band := Pal.TERRACOTTA_DARK
	if lod >= 2:
		var cheap := [Vector2(0, 0), Vector2(0.11, 0), Vector2(0.25, 0.32), Vector2(0.2, 0.56), Vector2(0.085, 0.68), Vector2(0.105, 0.82), Vector2(0, 0.8)]
		lathe(mb, Vector3.ZERO, _scaled(cheap, s), 5, [body, body, band, body, body, Pal.WOOD_DARK], rng.randf() * TAU)
		return
	var sides := 7 if lod == 0 else 6
	var prof := [
		Vector2(0, 0), Vector2(0.1, 0), Vector2(0.21, 0.2), Vector2(0.25, 0.4),
		Vector2(0.21, 0.55), Vector2(0.09, 0.66), Vector2(0.075, 0.79), Vector2(0.105, 0.83),
		Vector2(0.065, 0.85), Vector2(0, 0.8),
	]
	var cols := [body, body, body, band, body, body, body, band, Pal.WOOD_DARK]
	lathe(mb, Vector3.ZERO, _scaled(prof, s), sides, cols, rng.randf() * TAU)
	if lod > 0:
		return
	for side in [-1.0, 1.0]:
		var p0 := Vector3(0.07 * side, 0.75, 0) * s
		var p1 := Vector3(0.19 * side, 0.73, 0) * s
		var p2 := Vector3(0.19 * side, 0.55, 0) * s
		mb.limb(p0, p1, 0.026 * s, 0.026 * s, 4, body, false)
		mb.limb(p1, p2, 0.026 * s, 0.026 * s, 4, body, false)


static func stone_fence(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_stone_fence(mb, make_rng(seed_value), 3.0)
	return mb.commit()


## Dry-stone wall segment along X, centred on the origin (tiles end to end every `length` metres).
static func add_stone_fence(mb: MeshBuilder, rng: RandomNumberGenerator, length: float = 3.0, h: float = 0.75, thick: float = 0.55) -> void:
	var cols := [Pal.ROCK, Pal.LIMESTONE_DARK, PX.ROCK_MID, Pal.ROCK, Pal.LIMESTONE]
	var rows := [[0.0, 0.34], [0.3, 0.26]]
	for row in rows:
		var y0: float = row[0]
		var rh: float = row[1]
		var x := -length * 0.5
		while x < length * 0.5 - 0.08:
			var sl := minf(rng.randf_range(0.34, 0.66), length * 0.5 - x)
			var sh := rh * rng.randf_range(0.85, 1.15)
			var tilt := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.09, 0.09))
			var col: Color = cols[rng.randi() % cols.size()]
			var depth := thick * rng.randf_range(0.88, 1.04) * (1.0 - y0 * 0.25)
			box5(mb, Vector3(x + sl * 0.5, y0 + sh * 0.5, rng.randf_range(-0.04, 0.04)), Vector3(sl - 0.05, sh, depth), col, null, tilt)
			x += sl
	# Capstones: flat slabs, a little uneven.
	var x := -length * 0.5
	while x < length * 0.5 - 0.08:
		var sl := minf(rng.randf_range(0.42, 0.7), length * 0.5 - x)
		var tilt := Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.1, 0.1))
		var col: Color = [Pal.LIMESTONE_DARK, Pal.ROCK, Pal.LIMESTONE][rng.randi() % 3]
		box5(mb, Vector3(x + sl * 0.5, h - 0.08, rng.randf_range(-0.03, 0.03)), Vector3(sl - 0.06, 0.17, thick * rng.randf_range(0.72, 0.86)), col, null, tilt)
		x += sl


static func driftwood(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_driftwood(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Sun-bleached log with its root ball, lying on the sand (~2 m).
static func add_driftwood(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var l := rng.randf_range(1.7, 2.3) * s
	var bend := rng.randf_range(-0.35, 0.35)
	var p0 := Vector3(-l * 0.5, 0.17 * s, 0)
	var p1 := Vector3(-l * 0.05, 0.14 * s, bend * 0.5 * s)
	var p2 := Vector3(l * 0.5, 0.08 * s, -bend * 0.2 * s)
	mb.limb(p0, p1, 0.2 * s, 0.15 * s, 6, Pal.ROCK, true)
	mb.limb(p1, p2, 0.15 * s, 0.07 * s, 6, Pal.LIMESTONE_DARK, true)
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(-0.45, cos(a) * 0.9, sin(a)).normalized()
		if d.y < -0.3:
			d.y = -0.3
		mb.limb(p0 + d * 0.1 * s, p0 + d * rng.randf_range(0.42, 0.6) * s, 0.08 * s, 0.015 * s, 4, Pal.ROCK, false)
	var q := p1.lerp(p2, rng.randf_range(0.3, 0.55))
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	mb.limb(q, q + Vector3(0.32, 0.25, 0.38 * side) * s, 0.06 * s, 0.015 * s, 4, Pal.LIMESTONE_DARK, false)


static func herm_shrine(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_herm_shrine(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Roadside shrine: a squared herm pillar carrying a little temple-shaped lamp box whose glass front glows at


## night, a small altar with a bronze offering bowl, flowers and a jar at its foot. No face anywhere.
static func add_herm_shrine(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	box5(mb, Vector3(0, 0.06, 0) * s, Vector3(1.4, 0.2, 1.2) * s, Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	box5(mb, Vector3(0, 0.21, -0.2) * s, Vector3(0.7, 0.14, 0.62) * s, Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	# Herm pillar.
	mb.cyl(Vector3(0, 0.28, -0.2) * s, 0.98 * s, 0.27 * s, 0.23 * s, 4, Pal.MARBLE, false, PI * 0.25)
	mb.cyl(Vector3(0, 0.62, -0.2) * s, 0.07 * s, 0.26 * s, 0.255 * s, 4, Pal.AEGEAN, false, PI * 0.25)
	box5(mb, Vector3(0, 1.3, -0.2) * s, Vector3(0.5, 0.08, 0.5) * s, Pal.MARBLE_SHADE)
	# Lamp box: a tiny temple with a glowing front.
	box5(mb, Vector3(0, 1.53, -0.2) * s, Vector3(0.48, 0.4, 0.42) * s, Pal.MARBLE)
	box5(mb, Vector3(0, 1.53, 0.012) * s, Vector3(0.3, 0.27, 0.02) * s, Pal.WINDOW)
	box5(mb, Vector3(0, 1.36, 0.02) * s, Vector3(0.38, 0.05, 0.05) * s, Pal.BRONZE)
	mb.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 1.73, -0.2) * s))
	mb.roof_gable(Vector3.ZERO, 0.56 * s, 0.6 * s, 0.2 * s, Pal.TERRACOTTA, Pal.MARBLE_SHADE, 1.0)
	mb.pop()
	box5(mb, Vector3(0, 1.85, 0.08) * s, Vector3(0.07, 0.07, 0.07) * s, Pal.BRONZE, null, Vector3(0, 0, PI * 0.25))
	# Altar with a bronze bowl.
	box5(mb, Vector3(0, 0.36, 0.33) * s, Vector3(0.5, 0.4, 0.38) * s, Pal.LIMESTONE, Pal.MARBLE_SHADE)
	lathe(mb, Vector3(0, 0.56, 0.33) * s, _scaled([Vector2(0, 0), Vector2(0.07, 0), Vector2(0.15, 0.08), Vector2(0.12, 0.08), Vector2(0, 0.03)], s), 7, Pal.BRONZE)
	# Offerings at the foot.
	mb.push_at(Vector3(0.48, 0.16, -0.22) * s, rng.randf() * TAU, Vector3.ONE * 0.6 * s)
	add_amphora(mb, rng, 1.0, 2)
	mb.pop()
	var flower_cols := [Pal.BOUGAINVILLEA, Pal.POPPY, Pal.DAISY, Pal.LAVENDER]
	for i in 6:
		var a := PI * 0.12 + PI * 0.76 * float(i) / 5.0
		var p := Vector3(cos(a) * 0.56, 0.17, 0.16 + sin(a) * 0.36) * s
		mb.ico(p, 0.065 * s, flower_cols[(i + rng.randi() % 2) % flower_cols.size()], 0, 0.0, Vector3(1, 0.6, 1))
	blob(mb, rng, Vector3(-0.45, 0.14, -0.3) * s, _scaled([Vector2(0.2, 0), Vector2(0.17, 0.12), Vector2(0, 0.18)], s), 5, 0.15, Pal.OLIVE_LEAF, Pal.OLIVE_LEAF_DARK)


static func boat_small(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	var rng := make_rng(seed_value)
	mb.push(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(0.1, 0.16) * (1.0 if rng.randf() < 0.5 else -1.0))), Vector3(0, -0.06, 0)))
	add_boat_hull(mb, rng, 3.6, 1.35, 0.62)
	# Oars resting across the thwarts.
	for side in [-1.0, 1.0]:
		var a := Vector3(0.18 * side, 0.6, -1.2)
		var b := Vector3(0.32 * side, 0.68, 1.15)
		mb.limb(a, b, 0.03, 0.03, 4, Pal.WOOD_LIGHT, false)
		mb.push(Transform3D(Basis.looking_at(b - a, Vector3.UP), b))
		box5(mb, Vector3(0, 0, -0.02), Vector3(0.16, 0.025, 0.5), Pal.WOOD_LIGHT)
		mb.pop()
	mb.pop()
	# Anchor stone and a coil of rope on the sand.
	mb.ring(Vector3(0.95, 0, 0.9), 0.2, 0.08, 0.07, 6, Pal.LIMESTONE_DARK)
	chunk(mb, rng, Vector3(-0.95, -0.02, -0.7), 0.16, 0.18, 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK)
	return mb.commit()


## Double-ended Greek fishing hull (caïque): bow towards +Z, keel at y = 0 amidships, with thwarts and


## floorboards. `style` picks the paint (−1 = from the rng).
static func add_boat_hull(mb: MeshBuilder, rng: RandomNumberGenerator, length: float, beam: float, depth: float, style: int = -1) -> void:
	if style < 0:
		style = rng.randi() % 3
	var schemes := [
		{"band": Pal.AEGEAN, "side": Pal.MARBLE, "bottom": Pal.CLOTH_RED, "rim": Pal.AEGEAN_LIGHT},
		{"band": Pal.MARBLE, "side": Pal.AEGEAN, "bottom": Pal.MARBLE_SHADE, "rim": Pal.CREST},
		{"band": Pal.CREST, "side": Pal.MARBLE, "bottom": Pal.AEGEAN, "rim": Pal.AEGEAN},
	]
	var sc: Dictionary = schemes[style % schemes.size()]
	hull(mb, length, beam, depth, sc["band"], sc["side"], sc["bottom"], sc["rim"], Pal.WOOD_LIGHT)
	for t in [-0.45, 0.22]:
		var w := (_hull_half_width(t, beam) - 0.07) * 0.96
		box5(mb, Vector3(0, depth - 0.1 + 0.24 * t * t, t * length * 0.5), Vector3(w * 2.0, 0.05, 0.22), Pal.WOOD)
	box5(mb, Vector3(0, 0.12, 0), Vector3(0.36, 0.05, length * 0.55), Pal.WOOD)


# --- crops and farmland stonework --------------------------------------------------------------------------------

static func grapevine_row(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_grapevine_row(mb, make_rng(seed_value), posmod(seed_value, 3))
	return mb.commit()


## A bush-vine row segment (ancient practice, no wires): four free-standing goblet vines along X, 1.2 m apart (row


## 4.8 m, centred), each tied to a single wooden stake, over a low tilled soil ridge so the row reads as a line from
## the gameplay camera (canopy ≈0.95 m, ≤ 300 tris). kind = seed % 3: 0 full row, 1 one young vine, 2 one missing.
static func add_grapevine_row(mb: MeshBuilder, rng: RandomNumberGenerator, variant: int = 0) -> void:
	# Tilled ridge: a low flat-topped prism (no ends).
	var hl := 2.45
	var y := 0.06
	mb.quad(Vector3(-hl, y, -0.18), Vector3(-hl, y, 0.18), Vector3(hl, y, 0.18), Vector3(hl, y, -0.18), SOIL_TOP)
	mb.quad(Vector3(-hl, -0.02, 0.35), Vector3(hl, -0.02, 0.35), Vector3(hl, y, 0.18), Vector3(-hl, y, 0.18), PX.SOIL)
	mb.quad(Vector3(hl, -0.02, -0.35), Vector3(-hl, -0.02, -0.35), Vector3(-hl, y, -0.18), Vector3(hl, y, -0.18), PX.SOIL)
	var odd := rng.randi() % 4
	var grapes := 2
	for i in 4:
		var x := -1.8 + 1.2 * float(i) + rng.randf_range(-0.07, 0.07)
		var z := rng.randf_range(-0.05, 0.05)
		var sx := x + 0.13 + rng.randf_range(-0.03, 0.03)
		var lean := deg_to_rad(3.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		mb.limb(Vector3(sx, -0.08, z - 0.08), Vector3(sx + sin(lean) * 1.05, 0.97, z - 0.08), 0.024, 0.02, 3, Pal.WOOD_LIGHT, false)
		if variant == 2 and i == odd:
			continue
		var k := 0.6 if variant == 1 and i == odd else 1.0
		var head := Vector3(x + rng.randf_range(-0.07, 0.07), rng.randf_range(0.3, 0.4) * k, z + rng.randf_range(-0.05, 0.05))
		mb.limb(Vector3(x, -0.05, z), head, 0.06, 0.05, 3, VINE_BARK, false)
		var a0 := rng.randf() * TAU
		for j in 3:
			var a := a0 + TAU * float(j) / 3.0 + rng.randf_range(-0.3, 0.3)
			mb.limb(head, head + Vector3(cos(a) * 0.2, 0.24, sin(a) * 0.14) * k, 0.035, 0.025, 3, VINE_BARK, false)
		var dx := rng.randf_range(0.08, 0.13)
		_lump4(mb, rng, head + Vector3(dx, 0.4, rng.randf_range(-0.03, 0.03)) * Vector3(1, k, 1), rng.randf_range(0.42, 0.47) * k, 5, FIG, FIG_LOW, FIG_TOP, 0.14)
		_lump4(mb, rng, head + Vector3(-dx, 0.33, rng.randf_range(-0.03, 0.03)) * Vector3(1, k, 1), rng.randf_range(0.4, 0.44) * k, 5, FIG.lightened(0.03), FIG_LOW, FIG_TOP, 0.14)
		if grapes > 0 and k == 1.0 and rng.randf() < 0.6:
			grapes -= 1
			_dot(mb, rng, head + Vector3(rng.randf_range(-0.2, 0.2), 0.16, 0.3), 0.06, GRAPE, Vector3(0.9, 1.3, 0.9))


static func wheat_patch(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_wheat_patch(mb, make_rng(seed_value), posmod(seed_value, 2))
	return mb.commit()


## A 3 × 2.5 m bed of ripening wheat (kind 0) or paler barley (kind 1) for the terrace strips: five sown ridges
## along local X (the contour) with dark green-gold furrows between them, each ridge a ragged gable of stalks
## (green-gold foot, golden ears on top, tapering at both ends), a few ear tufts above the line and poppies along
## the +Z (downhill) edge. Reads as a striped field from the gameplay camera and as a standing crop from the low
## title camera (<= 170 tris, <= 0.62 m tall).
static func add_wheat_patch(mb: MeshBuilder, rng: RandomNumberGenerator, variant: int = 0) -> void:
	var ear := WHEAT if variant == 0 else BARLEY
	var lit := WHEAT_LIT if variant == 0 else BARLEY_LIT
	var foot := WHEAT_STALK if variant == 0 else BARLEY_STALK
	var xs := [-1.42, -0.5, 0.5, 1.42]
	for r in 5:
		var zc := -1.0 + 0.5 * float(r) + rng.randf_range(-0.03, 0.03)
		var tops: Array[Vector3] = []
		for k in 4:
			var end := k == 0 or k == 3
			var h := (rng.randf_range(0.36, 0.42) if end else rng.randf_range(0.5, 0.6))
			tops.append(Vector3(xs[k] + (rng.randf_range(-0.06, 0.06) if not end else 0.0), h, zc + rng.randf_range(-0.04, 0.04)))
		for k in 3:
			var a: Vector3 = tops[k]
			var b: Vector3 = tops[k + 1]
			for side in [-1.0, 1.0]:
				var a0 := Vector3(a.x, -0.04, zc + side * 0.24)
				var b0 := Vector3(b.x, -0.04, zc + side * 0.24)
				var am := Vector3(a.x, a.y * 0.45, lerpf(zc + side * 0.24, a.z, 0.45))
				var bm := Vector3(b.x, b.y * 0.45, lerpf(zc + side * 0.24, b.z, 0.45))
				var top_col := lit if side > 0.0 else ear
				if side < 0.0:
					mb.quad(a0, am, bm, b0, foot)
					mb.quad(am, a, b, bm, top_col)
				else:
					mb.quad(a0, b0, bm, am, foot)
					mb.quad(am, bm, b, a, top_col)
		# Blunt ends.
		for k in [0, 3]:
			var t: Vector3 = tops[k]
			var sx := -1.0 if k == 0 else 1.0
			var l := Vector3(t.x + sx * 0.04, -0.04, zc - 0.24)
			var rr := Vector3(t.x + sx * 0.04, -0.04, zc + 0.24)
			if k == 0:
				mb.tri(l, rr, t, foot)
			else:
				mb.tri(rr, l, t, foot)
		# Ear tufts breaking the ridge line.
		for i in 2:
			var u := rng.randf_range(0.15, 2.85)
			var kk := clampi(int(u), 0, 2)
			var p: Vector3 = (tops[kk] as Vector3).lerp(tops[kk + 1], u - float(kk))
			var tilt := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			mb.push(Transform3D(Basis.from_euler(tilt), p + Vector3(0, -0.05, 0)))
			mb.cyl(Vector3.ZERO, rng.randf_range(0.13, 0.18), 0.04, 0.0, 3, lit, false, rng.randf() * TAU)
			mb.pop()
	for i in 2 + rng.randi() % 3:
		var p := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(1.3, 1.42))
		_dot(mb, rng, p + Vector3(0, 0.16, 0), 0.05, Pal.POPPY, Vector3(1, 0.8, 1))


## Bilinear height on a 4 × 4 grid of top vertices (u, w in 0..3 along i, j).
static func _grid_at(g: Array, u: float, w: float) -> Vector3:
	var i := clampi(int(u), 0, 2)
	var j := clampi(int(w), 0, 2)
	var fu := u - float(i)
	var fw := w - float(j)
	var a: Vector3 = g[i][j]
	var b: Vector3 = g[i][j + 1]
	var c: Vector3 = g[i + 1][j + 1]
	var d: Vector3 = g[i + 1][j]
	return a.lerp(d, fu).lerp(b.lerp(c, fu), fw)


## Vertical quad from the ground segment p0..p1 rising h0 / h1, wound to face away from the origin (outer walls).
static func _wall(mb: MeshBuilder, p0: Vector3, p1: Vector3, h0: float, h1: float, col: Color) -> void:
	var t0 := p0 + Vector3(0, h0, 0)
	var t1 := p1 + Vector3(0, h1, 0)
	var n := (t0 - p0).cross(t1 - p0)
	var out := Vector3(p0.x + p1.x, 0, p0.z + p1.z)
	if n.dot(out) >= 0.0:
		mb.quad(p0, t0, t1, p1, col)
	else:
		mb.quad(p1, t1, t0, p0, col)


static func terrace_wall(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_terrace_wall(mb, make_rng(seed_value), 3.0)
	return mb.commit()


## Dry-stone retaining wall (pezoula) for a terrace riser: one 3 m segment along X, centred; its front (+Z, downhill)


## is battered back 6° into the hill and its back is buried, so only fronts, tops and joints are drawn (≤ 140 tris).
## Base at y = 0, top 0.6 m flush with the upper bench. Two courses of irregular stones (none longer than 0.66 m, so
## placement may stretch it in X and Y) under flat capstones whose shadow line makes the terraces read; the end
## stones sit a little lower so runs finish naturally.
static func add_terrace_wall(mb: MeshBuilder, rng: RandomNumberGenerator, length: float = 3.0) -> void:
	var cols := [Pal.ROCK, Pal.LIMESTONE_DARK, PX.ROCK_MID, Pal.ROCK, Pal.LIMESTONE]
	var half := length * 0.5
	mb.push(Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(6.0)), Vector3.ZERO))
	var rows := [[0.0, 0.26, 0.5], [0.22, 0.3, 0.46]]
	for ri in rows.size():
		var y0: float = rows[ri][0]
		var rh: float = rows[ri][1]
		var depth: float = rows[ri][2]
		var x := -half
		var first := true
		while x < half - 0.06:
			var sl := minf(rng.randf_range(0.34, 0.66), half - x)
			if first and ri == 1:
				sl = rng.randf_range(0.2, 0.34)
			if half - x - sl < 0.2:
				sl = half - x
			var last := x + sl >= half - 0.06
			var sh := rh * rng.randf_range(0.86, 1.12) * (0.9 if (first or last) and ri == 1 else 1.0)
			var col: Color = cols[rng.randi() % cols.size()]
			if rng.randf() < 0.15:
				col = col.darkened(0.12)
			var tilt := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.07, 0.07))
			var fz := 0.12 + rng.randf_range(-0.03, 0.03)
			var mask := ST_FRONT | ST_LEFT | (ST_TOP if ri == 1 else 0) | (ST_RIGHT if last else 0)
			_stone(mb, Vector3(x + sl * 0.5, y0 + sh * 0.5, fz - depth * 0.5), Vector3(sl - 0.05, sh, depth), col, col.lightened(0.05), tilt, mask)
			x += sl
			first = false
	# Capstones: flat slabs, the end ones set a little lower.
	var x := -half
	var first := true
	while x < half - 0.06:
		var sl := minf(rng.randf_range(0.42, 0.66), half - x)
		if half - x - sl < 0.25:
			sl = half - x
		var last := x + sl >= half - 0.06
		var drop := 0.05 if first or last else rng.randf_range(-0.015, 0.015)
		var tilt := Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.07, 0.07))
		var col: Color = [Pal.LIMESTONE_DARK, Pal.ROCK, Pal.LIMESTONE][rng.randi() % 3]
		_stone(mb, Vector3(x + sl * 0.5, 0.54 - drop, 0.14 - 0.25 + rng.randf_range(-0.02, 0.02)), Vector3(sl - 0.05, 0.12, 0.5), col.darkened(0.06), col, tilt, ST_FRONT | ST_TOP | ST_LEFT | (ST_RIGHT if last else 0))
		x += sl
		first = false
	mb.pop()


static func threshing_floor(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_threshing_floor(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Aloni: a circular stone threshing floor 6 m across on flattened ground. A centre disc and two rings of radial


## slabs (9 + 16) with dark joints, a curb of upright edge stones, a heap of golden straw and chaff and a wooden
## winnowing fork propped on the rim (floor top 0.06 m above the ground; walkable; ≤ 340 tris).
static func add_threshing_floor(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	mb.disc(Vector3(0, 0.015, 0), 3.12 * s, 12, Pal.ROCK_DARK)
	var r0 := 0.68 * s
	mb.cyl(Vector3(0, 0.0, 0), 0.075, r0, r0, 7, Pal.LIMESTONE_DARK, false)
	mb.disc(Vector3(0, 0.075, 0), r0, 7, Pal.LIMESTONE)
	for ring in [[0.72, 1.86, 9], [1.9, 2.92, 16]]:
		var ra: float = ring[0] * s
		var rb: float = ring[1] * s
		var n: int = ring[2]
		var a0 := rng.randf() * TAU
		var gap := 0.04 * s / ((ra + rb) * 0.5)
		for k in n:
			var a1 := a0 + TAU * float(k) / float(n) + gap * 0.5
			var a2 := a0 + TAU * float(k + 1) / float(n) - gap * 0.5
			var u := rng.randf()
			var col: Color = Pal.LIMESTONE_DARK if u < 0.45 else (Pal.ROCK if u < 0.8 else Pal.LIMESTONE)
			var gx := rng.randf_range(-0.035, 0.035)
			var tj := [gx + rng.randf_range(-0.02, 0.02), gx + rng.randf_range(-0.02, 0.02), -gx + rng.randf_range(-0.02, 0.02), -gx + rng.randf_range(-0.02, 0.02)]
			_sector(mb, Vector3.ZERO, ra, rb, a1, a2, 0.0, 0.065, col.darkened(0.12), col, SEC_TOP | SEC_OUT, tj)
	# Curb of upright edge stones.
	var b0 := rng.randf() * TAU
	for k in 18:
		var a1 := b0 + TAU * float(k) / 18.0 + 0.02
		var a2 := b0 + TAU * float(k + 1) / 18.0 - 0.02
		var hh := rng.randf_range(0.2, 0.3) * s
		var u := rng.randf()
		var col: Color = Pal.ROCK if u < 0.5 else (PX.ROCK_MID if u < 0.8 else Pal.LIMESTONE_DARK)
		var tj := [rng.randf_range(-0.04, 0.03), rng.randf_range(-0.04, 0.03), rng.randf_range(-0.04, 0.03), rng.randf_range(-0.04, 0.03)]
		_sector(mb, Vector3.ZERO, 2.95 * s, rng.randf_range(3.15, 3.22) * s, a1, a2, -0.05, hh, col, col.lightened(0.06), SEC_TOP | SEC_OUT | SEC_IN, tj)
	# Heap of straw and chaff, off centre.
	var ha := rng.randf() * TAU
	var hc := Vector3(cos(ha) * 1.2, 0.05, sin(ha) * 1.2) * s
	blob(mb, rng, hc, _scaled([Vector2(0.7, 0), Vector2(0.6, 0.15), Vector2(0.34, 0.29), Vector2(0, 0.35)], s), 7, 0.16, WHEAT, WHEAT_STALK, -0.2, WHEAT_LIT, 0.75)
	# Winnowing fork: its butt on the floor, the shaft propped over the curb, three tines up and out.
	var fa := ha + PI * 0.6
	var dh := Vector3(cos(fa), 0, sin(fa))
	var lat := Vector3(-dh.z, 0, dh.x)
	var butt := dh * 2.15 * s + Vector3(0, 0.07, 0)
	var rest := dh * 3.05 * s + Vector3(0, 0.33, 0)
	var crotch := dh * 3.55 * s + Vector3(0, 0.52, 0)
	mb.limb(butt, rest, 0.03 * s, 0.03 * s, 3, Pal.WOOD_LIGHT, false)
	mb.limb(rest, crotch, 0.03 * s, 0.028 * s, 3, Pal.WOOD_LIGHT, false)
	var fd := (crotch - butt).normalized()
	for t in 3:
		var o := lat * (float(t) - 1.0) * 0.09 * s
		mb.limb(crotch, crotch + fd * 0.42 * s + o + Vector3(0, 0.04, 0), 0.016 * s, 0.008 * s, 3, Pal.WOOD_LIGHT.darkened(0.08), false)


static func beehives(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_beehives(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Three horizontal terracotta hives of the Vari type lying side by side on a low dry-stone bench, their lids and


## entrance notches facing +Z, each weighted with a flat stone (bench 2.4 × 0.35 × 0.55 m; ≤ 220 tris).
static func add_beehives(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	box5(mb, Vector3(-0.6, 0.175, 0.0) * s, Vector3(1.18, 0.35, 0.55) * s, Pal.ROCK, Pal.LIMESTONE_DARK, Vector3(0, rng.randf_range(-0.03, 0.03), 0))
	box5(mb, Vector3(0.6, 0.17, 0.01) * s, Vector3(1.18, 0.34, 0.53) * s, PX.ROCK_MID, Pal.LIMESTONE_DARK, Vector3(0, rng.randf_range(-0.03, 0.03), 0))
	var r := 0.18 * s
	var yc := 0.35 * s + r
	for i in 3:
		var x := (-0.42 + 0.42 * float(i)) * s + rng.randf_range(-0.02, 0.02) * s
		var zb := -0.36 * s
		var zf := 0.44 * s
		var cols := func(lit: bool) -> Array:
			# 7 faces; the two facing up take the lit stripe.
			var out: Array = []
			for f in 7:
				var am := TAU * (float(f) + 0.5) / 7.0
				out.append(HIVE_LIT if lit and sin(am) > 0.55 else Pal.TERRACOTTA)
			return out
		var axis_rot := PI * 0.5
		# Body along Z: back band, body with a lit stripe on top, front band.
		_tube_z(mb, Vector3(x, yc, zb), Vector3(x, yc, zb + 0.07 * s), r, 7, [Pal.TERRACOTTA_DARK])
		_tube_z(mb, Vector3(x, yc, zb + 0.07 * s), Vector3(x, yc, zf - 0.07 * s), r, 7, cols.call(true))
		_tube_z(mb, Vector3(x, yc, zf - 0.07 * s), Vector3(x, yc, zf), r * 1.04, 7, [Pal.TERRACOTTA_DARK])
		# Back cap and front lid (n-gon fans), entrance notch at the foot of the lid.
		var back: Array = []
		var front: Array = []
		for f in 7:
			var a := TAU * float(f) / 7.0 + axis_rot
			back.append(Vector3(x + cos(a) * r, yc + sin(a) * r, zb))
			front.append(Vector3(x + cos(a) * r * 1.04, yc + sin(a) * r * 1.04, zf + 0.004))
		for f in range(1, 6):
			mb.tri(back[0], back[f + 1], back[f], Pal.TERRACOTTA_DARK)
			mb.tri(front[0], front[f], front[f + 1], Pal.TERRACOTTA_DARK.darkened(0.06))
		var nb := Vector3(x, yc - r * 0.72, zf + 0.012)
		mb.quad(nb + Vector3(-0.03, -0.015, 0) * s, nb + Vector3(0.03, -0.015, 0) * s, nb + Vector3(0.03, 0.015, 0) * s, nb + Vector3(-0.03, 0.015, 0) * s, Pal.SKIN_SHADOW)
		box5(mb, Vector3(x, yc + r + 0.02 * s, rng.randf_range(-0.05, 0.08) * s), Vector3(0.36, 0.06, 0.28) * s, Pal.ROCK, Pal.LIMESTONE_DARK, Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.06, 0.06)))


## Tube along an arbitrary axis (no caps), faces coloured in turn from `cols`; face 0 starts at +X and runs


## towards +Y, so for a tube along +Z the upper faces are the middle of the list.
static func _tube_z(mb: MeshBuilder, a: Vector3, b: Vector3, r: float, sides: int, cols: Array) -> void:
	for f in sides:
		var a0 := TAU * float(f) / float(sides)
		var a1 := TAU * float(f + 1) / float(sides)
		var d0 := Vector3(cos(a0), sin(a0), 0) * r
		var d1 := Vector3(cos(a1), sin(a1), 0) * r
		mb.quad(a + d0, a + d1, b + d1, b + d0, cols[f % cols.size()])


static func well(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_well(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## The village well by the great plane (front +Z towards the plaza): a round dry-stone well-head capped by a smooth


## limestone rim around dark water, a wooden frame with a pulley and a rope down to a hanging jar, and a stone
## trough with an amphora at its foot (≤ 300 tris).
static func add_well(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var cols := [Pal.ROCK, Pal.LIMESTONE_DARK, PX.ROCK_MID, Pal.ROCK, Pal.LIMESTONE]
	# Two courses of nine stones (running bond), only their outer faces: the rim covers their tops.
	for course in 2:
		var y0 := 0.0 if course == 0 else 0.36 * s
		var y1 := 0.38 * s if course == 0 else 0.76 * s
		var off := TAU / 18.0 * float(course)
		for k in 9:
			var a1 := off + TAU * float(k) / 9.0
			var a2 := off + TAU * float(k + 1) / 9.0
			var col: Color = cols[rng.randi() % cols.size()]
			_sector(mb, Vector3.ZERO, 0.0, rng.randf_range(0.66, 0.7) * s, a1, a2, y0 - (0.05 if course == 0 else 0.0), y1 + rng.randf_range(-0.015, 0.015), col, col, SEC_OUT)
	# Inner wall (seen looking in) and the dark water.
	for k in 9:
		var a1 := TAU * float(k) / 9.0
		var a2 := TAU * float(k + 1) / 9.0
		_sector(mb, Vector3.ZERO, 0.5 * s, 0.6 * s, a1, a2, 0.45 * s, 0.77 * s, PX.ROCK_WET, PX.ROCK_WET, SEC_IN)
	mb.disc(Vector3(0, 0.5 * s, 0), 0.52 * s, 9, WELL_WATER)
	mb.ring(Vector3(0, 0.76 * s, 0), 0.72 * s, 0.5 * s, 0.1 * s, 9, Pal.LIMESTONE)
	# Frame, pulley, rope and the hanging jar.
	for side in [-1.0, 1.0]:
		box5(mb, Vector3(0.82 * side, 0.8, 0.0) * s, Vector3(0.1, 1.6, 0.1) * s, Pal.WOOD, Pal.WOOD_DARK, Vector3(0, 0, -0.025 * side))
	box5(mb, Vector3(0, 1.56, 0) * s, Vector3(1.86, 0.1, 0.1) * s, Pal.WOOD, Pal.WOOD_LIGHT)
	mb.push(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.03 * s, 1.38 * s, 0)))
	mb.cyl(Vector3.ZERO, 0.06 * s, 0.12 * s, 0.12 * s, 6, Pal.WOOD_DARK, true)
	mb.pop()
	mb.limb(Vector3(0, 1.38, 0.12) * s, Vector3(0, 1.0, 0.12) * s, 0.012 * s, 0.012 * s, 3, Pal.LIMESTONE_DARK, false)
	mb.push_at(Vector3(0, 0.63, 0.12) * s, rng.randf() * TAU, Vector3.ONE * 0.45 * s)
	add_amphora(mb, rng, 1.0, 2)
	mb.pop()
	# Stone trough beside it, its long side towards the plaza, and an amphora at its foot.
	mb.push_at(Vector3(1.32, 0, 0.32) * s, PI * 0.5 + rng.randf_range(-0.1, 0.1), Vector3.ONE * s)
	box5(mb, Vector3(0, 0.175, 0), Vector3(1.0, 0.35, 0.4), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	mb.quad(Vector3(-0.42, 0.352, -0.13), Vector3(-0.42, 0.352, 0.13), Vector3(0.42, 0.352, 0.13), Vector3(0.42, 0.352, -0.13), WATER)
	mb.pop()
	mb.push_at(Vector3(1.7, 0, 0.95) * s, rng.randf() * TAU, Vector3.ONE * s)
	add_amphora(mb, rng, 1.0, 2)
	mb.pop()


static func spring_basin(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_spring_basin(mb, make_rng(seed_value), 1.0, posmod(seed_value, 2))
	return mb.commit()


## Krene, a stone spring basin 2.2 m wide: a low curved wall of seven dressed limestone blocks around a water


## surface at 0.32 m with a mossy waterline and loose stones outside. kind = seed % 2: 0 horseshoe basin closed by a
## back slab with a small bronze spout and a falling water strip towards +Z (yaw the spout downstream); 1 round
## sacred basin without spout (≤ 170 tris).
static func add_spring_basin(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0, variant: int = 0) -> void:
	var c := Vector3(0, 0, 0.1 if variant == 0 else 0.0) * s
	var span := deg_to_rad(276.0) if variant == 0 else TAU
	var start := PI * 0.5 - span * 0.5
	for k in 7:
		var a1 := start + span * float(k) / 7.0 + 0.012
		var a2 := start + span * float(k + 1) / 7.0 - 0.012
		var hh := rng.randf_range(0.43, 0.47) * s
		_sector(mb, c, 0.8 * s, 1.1 * s, a1, a2, -0.1, hh, Pal.LIMESTONE_DARK, Pal.LIMESTONE, SEC_ALL, [0.0, 0.0, -0.01, -0.01])
	# Water: bright centre, darker rim.
	var wy := 0.32 * s
	var inner: Array = []
	var outer: Array = []
	for k in 7:
		var a := TAU * float(k) / 7.0
		inner.append(c + Vector3(cos(a) * 0.48 * s, wy, sin(a) * 0.48 * s))
		outer.append(c + Vector3(cos(a) * 0.84 * s, wy, sin(a) * 0.84 * s))
	_fan_up(mb, inner, WATER)
	for k in 7:
		var j := (k + 1) % 7
		mb.quad(outer[k], inner[k], inner[j], outer[j], WATER_RIM)
	for k in 6:
		var a := start + span * (float(k) + 0.5) / 6.0 + rng.randf_range(-0.15, 0.15)
		_dot(mb, rng, c + Vector3(cos(a) * 0.8, wy + 0.01, sin(a) * 0.8) * Vector3(s, 1, s), 0.08 * s, MOSS, Vector3(1.5, 0.5, 1.5))
	if variant == 0:
		box5(mb, Vector3(0, 0.4, -0.66) * s, Vector3(1.2, 0.9, 0.3) * s, Pal.LIMESTONE_DARK, Pal.LIMESTONE)
		mb.limb(Vector3(0, 0.66, -0.5) * s, Vector3(0, 0.64, -0.3) * s, 0.03 * s, 0.03 * s, 4, Pal.BRONZE, true)
		mb.quad(Vector3(0.025, 0.63, -0.29) * s, Vector3(-0.025, 0.63, -0.29) * s, Vector3(-0.035 * s, wy, -0.22 * s), Vector3(0.035 * s, wy, -0.22 * s), WATER_FALL)
	for k in 3:
		var a := rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.3, 1.6) * s
		if variant == 0 and p.z < -0.4 * s:
			p.z = -p.z
		box5(mb, p + Vector3(0, 0.05, 0) * s, Vector3(rng.randf_range(0.2, 0.32), 0.14, rng.randf_range(0.16, 0.26)) * s, Pal.ROCK, Pal.LIMESTONE_DARK, Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15)))


# --- shared geometry helpers ---------------------------------------------------------------------------------

static func _scaled(prof: Array, k: float) -> Array:
	var out := []
	for p in prof:
		out.append((p as Vector2) * k)
	return out


## Surface of revolution around +Y. `profile` holds Vector2(radius, height) in order; start/end it at radius 0 to


## close it. A profile that goes up the outside and back down the inside (bowls, jars) gets correct normals on
## both surfaces. `cols` is one Color or one per segment.
static func lathe(mb: MeshBuilder, base: Vector3, profile: Array, sides: int, cols: Variant, rot: float = 0.0) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var col: Color
		if cols is Array:
			col = cols[mini(i, (cols as Array).size() - 1)]
		else:
			col = cols
		mb.cyl(base + Vector3(0, p0.y, 0), p1.y - p0.y, p0.x, p1.x, sides, col, false, rot)


## Jittered surface of revolution for organic shapes (foliage, rocks). Vertices are shared between faces, so the


## surface stays closed. Faces whose normal's y is below `under` get `col_low`; above `top_thr`, `col_top`.
## `twist` turns each ring by a random angle (radians) so facets stop lining up (rocks).
static func blob(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, profile: Array, sides: int, jitter: float, col: Color, col_low: Color, under: float = -0.2, col_top: Variant = null, top_thr: float = 0.8, twist: float = 0.0) -> void:
	_blob_f(mb, rng, c, profile, sides, jitter, col, col_low, under, col_top, top_thr, twist)


## Box without its bottom face (it always rests on something), centred on `c`, optionally rotated (euler YXZ).
static func box5(mb: MeshBuilder, c: Vector3, size: Vector3, col: Color, top_col: Variant = null, rot: Vector3 = Vector3.ZERO) -> void:
	var rotated := rot != Vector3.ZERO
	if rotated:
		mb.push(Transform3D(Basis.from_euler(rot), c))
		c = Vector3.ZERO
	var h := size * 0.5
	var p0 := c + Vector3(-h.x, -h.y, -h.z)
	var p1 := c + Vector3(h.x, -h.y, -h.z)
	var p2 := c + Vector3(h.x, -h.y, h.z)
	var p3 := c + Vector3(-h.x, -h.y, h.z)
	var p4 := c + Vector3(-h.x, h.y, -h.z)
	var p5 := c + Vector3(h.x, h.y, -h.z)
	var p6 := c + Vector3(h.x, h.y, h.z)
	var p7 := c + Vector3(-h.x, h.y, h.z)
	var tc: Color = col if top_col == null else top_col
	mb.quad(p4, p7, p6, p5, tc)
	mb.quad(p3, p2, p6, p7, col)
	mb.quad(p1, p0, p4, p5, col)
	mb.quad(p2, p1, p5, p6, col)
	mb.quad(p0, p3, p7, p4, col)
	if rotated:
		mb.pop()


## Fluted column shaft along +Y (star cross-section). `broken` > 0 snaps the top along a slanted, jagged


## break up to that deep; `both_caps` also closes the bottom (lying drums).
static func fluted_shaft(mb: MeshBuilder, rng: RandomNumberGenerator, base: Vector3, h: float, r0: float, r1: float, flutes: int, col: Color, cap_col: Color, broken: float = 0.0, both_caps: bool = false) -> void:
	var n := flutes * 2
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	var bd := rng.randf() * TAU
	for i in n:
		var a := TAU * float(i) / float(n)
		var k := 1.0 if i % 2 == 0 else 0.86
		var d := Vector3(cos(a), 0, sin(a))
		bot.append(base + d * r0 * k)
		var th := h
		if broken > 0.0:
			th -= broken * (0.5 + 0.5 * cos(a - bd)) * rng.randf_range(0.75, 1.0) + rng.randf() * broken * 0.15
		top.append(base + Vector3(0, th, 0) + d * r1 * k)
	for i in n:
		var j := (i + 1) % n
		mb.quad(bot[i], top[i], top[j], bot[j], col)
	var ct := base + Vector3(0, h, 0)
	if broken > 0.0:
		ct = base + Vector3(0, h - broken * 0.55, 0)
	for i in n:
		var j := (i + 1) % n
		mb.tri(ct, top[j], top[i], cap_col)
		if both_caps:
			mb.tri(base, bot[i], bot[j], cap_col)


## Doric capital (necking, echinus and square abacus) with its base at `base`.
static func doric_capital(mb: MeshBuilder, base: Vector3, r: float, col: Color, side_col: Color) -> void:
	mb.cyl(base, 0.1, r * 0.92, r * 0.92, 8, side_col, false)
	mb.cyl(base + Vector3(0, 0.1, 0), 0.15, r * 0.92, r * 1.34, 8, col, true)
	box5(mb, base + Vector3(0, 0.25 + 0.09, 0), Vector3(r * 2.9, 0.18, r * 2.9), side_col, col)


## Upward-opening flower cup (poppies) with a dark heart.
static func cup(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, h: float, sides: int, col: Color, heart: Color) -> void:
	var rot := rng.randf() * TAU
	var rim: Array[Vector3] = []
	for i in sides:
		var a := rot + TAU * float(i) / float(sides)
		rim.append(c + Vector3(cos(a) * r, h, sin(a) * r))
	for i in sides:
		var j := (i + 1) % sides
		mb.tri(c, rim[j], rim[i], col)
		mb.tri(c, rim[i], rim[j], col.darkened(0.2))
	mb.cyl(c + Vector3(0, h * 0.3, 0), h * 0.6, r * 0.32, 0.0, 4, heart, false)


static func _hull_half_width(t: float, beam: float) -> float:
	return beam * 0.5 * pow(maxf(0.0, 1.0 - pow(absf(t), 2.2)), 0.6)


## Lofted double-ended hull, bow towards +Z, keel bottom at y = 0 amidships; open on top, with inner planking


## and a gunwale cap. Colours: band (just under the gunwale), side (topsides), bottom (below the bilge), rim, inside.
static func hull(mb: MeshBuilder, length: float, beam: float, depth: float, band: Color, side: Color, bottom: Color, rim: Color, inside: Color) -> void:
	var stations := 7
	var outer: Array = []
	var inner: Array = []
	var th := 0.07
	for si in stations:
		var t := -1.0 + 2.0 * float(si) / float(stations - 1)
		var z := t * length * 0.5
		var w := _hull_half_width(t, beam)
		var g := depth + 0.24 * t * t
		var k := 0.22 * pow(absf(t), 3.0)
		var stripe := g - 0.14
		var bilge := k + (g - k) * 0.4
		outer.append([Vector3(w, g, z), Vector3(w * 0.995, stripe, z), Vector3(w * 0.82, bilge, z), Vector3(0, k, z)])
		var wi := maxf(0.0, w - th)
		inner.append([Vector3(wi, g, z), Vector3(wi * 0.76, k + th + (g - k) * 0.3, z), Vector3(0, k + th, z)])
	var panel := [band, side, bottom]
	for si in stations - 1:
		var o0: Array = outer[si]
		var o1: Array = outer[si + 1]
		for p in 3:
			var a: Vector3 = o0[p]
			var b: Vector3 = o1[p]
			var c: Vector3 = o1[p + 1]
			var d: Vector3 = o0[p + 1]
			mb.quad(a, b, c, d, panel[p])
			mb.quad(_mx(a), _mx(d), _mx(c), _mx(b), panel[p])
		var i0: Array = inner[si]
		var i1: Array = inner[si + 1]
		for p in 2:
			var a: Vector3 = i0[p]
			var b: Vector3 = i1[p]
			var c: Vector3 = i1[p + 1]
			var d: Vector3 = i0[p + 1]
			mb.quad(a, d, c, b, inside)
			mb.quad(_mx(a), _mx(b), _mx(c), _mx(d), inside)
		var ra: Vector3 = o0[0]
		var rb: Vector3 = o1[0]
		var rc: Vector3 = i1[0]
		var rd: Vector3 = i0[0]
		mb.quad(ra, rd, rc, rb, rim)
		mb.quad(_mx(ra), _mx(rb), _mx(rc), _mx(rd), rim)
	# Stem and stern posts.
	for e in [-1.0, 1.0]:
		var g := depth + 0.24
		box5(mb, Vector3(0, g - 0.05, e * (length * 0.5 - 0.06)), Vector3(0.09, 0.32, 0.16), rim)


static func _mx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


# --- flora helpers -----------------------------------------------------------------------------------------------

## Foliage mass with a flat underside (a browse or shade line `flat`·r below its centre, `brim`·r wide), widest


## just above the centre and domed on top (`top`·r). Three tones: underside (normal.y < `under`), body, sunlit top
## (normal.y > 0.8). `sy` stretches it vertically. 6·sides triangles. Returns its faces (see _blob_f).
static func _crown(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, sides: int, col: Color, col_low: Color, col_top: Color, jitter: float = 0.12, sy: float = 1.0, flat: float = 0.35, top: float = 0.68, brim: float = 0.86, under: float = -0.1) -> Array:
	var prof := [
		Vector2(0, -flat * sy), Vector2(brim, (-flat + 0.06) * sy), Vector2(1.0, 0.06 * sy),
		Vector2(0.72, (top - 0.22) * sy), Vector2(0, top * sy),
	]
	return _blob_f(mb, rng, c, _scaled(prof, r), sides, jitter, col, col_low, under, col_top, 0.8)


## Rounded foliage puff (no flat brim) for the inner and upper lumps of a crown, so stacked lumps merge into one


## mass instead of reading as plates; only its true underside takes the dark tone. 6·sides triangles.
static func _puff(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, sides: int, col: Color, col_low: Color, col_top: Color, jitter: float = 0.12, sy: float = 1.0) -> Array:
	var prof := [Vector2(0, -0.5 * sy), Vector2(0.74, -0.36 * sy), Vector2(1.0, 0.02 * sy), Vector2(0.76, 0.42 * sy), Vector2(0, 0.64 * sy)]
	return _blob_f(mb, rng, c, _scaled(prof, r), sides, jitter, col, col_low, -0.42, col_top, 0.82)


## Same as blob() but returns the faces it emitted as [centre: Vector3, normal: Vector3] (local to the current


## transform), so flowers and blossom can be set exactly on the foliage surface.
static func _blob_f(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, profile: Array, sides: int, jitter: float, col: Color, col_low: Color, under: float = -0.2, col_top: Variant = null, top_thr: float = 0.8, twist: float = 0.0) -> Array:
	var faces: Array = []
	var rot := rng.randf() * TAU
	var rings: Array = []
	for p in profile:
		var pv: Vector2 = p
		var row: Array[Vector3] = []
		rot += rng.randf_range(-twist, twist)
		for i in sides:
			var a := rot + TAU * float(i) / float(sides)
			var r := pv.x * (1.0 + rng.randf_range(-jitter, jitter))
			var y := pv.y + (rng.randf_range(-jitter, jitter) * pv.x * 0.5 if pv.x > 0.0 else 0.0)
			row.append(c + Vector3(cos(a) * r, y, sin(a) * r))
		rings.append(row)
	for j in rings.size() - 1:
		var lo: Array[Vector3] = rings[j]
		var hi: Array[Vector3] = rings[j + 1]
		for i in sides:
			var k := (i + 1) % sides
			var n := (hi[i] - lo[i]).cross(hi[k] - lo[i]) + (hi[k] - lo[i]).cross(lo[k] - lo[i])
			var fc := col
			if n.length_squared() > 1e-12:
				var nn := n.normalized()
				if nn.y < under:
					fc = col_low
				elif col_top != null and nn.y > top_thr:
					fc = col_top
				faces.append([(lo[i] + hi[i] + hi[k] + lo[k]) * 0.25, nn])
			mb.quad(lo[i], hi[i], hi[k], lo[k], fc)
	return faces


## Small rounded foliage lump (4·sides triangles) for airy crowns, vines and shrubs.
static func _lump4(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, sides: int, col: Color, col_low: Color, col_top: Variant = null, jitter: float = 0.12, sy: float = 1.0) -> Array:
	var prof := [Vector2(0, -0.5 * sy), Vector2(0.92, -0.17 * sy), Vector2(0.86, 0.3 * sy), Vector2(0, 0.62 * sy)]
	return _blob_f(mb, rng, c, _scaled(prof, r), sides, jitter, col, col_low, -0.3, col_top, 0.8)


## Low lumpy dome sitting on the ground, open underneath (cushions, clumps): radius r, height h, 5·sides


## triangles; `twist` turns its rings so the facets stay irregular (plants, not rocks).
static func _dome(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, h: float, sides: int, jitter: float, col: Color, col_low: Color, col_top: Variant = null, twist: float = 0.35) -> Array:
	var prof := [Vector2(r * 0.9, -0.03), Vector2(r, h * 0.36), Vector2(r * 0.66, h * 0.82), Vector2(0, h)]
	return _blob_f(mb, rng, c, prof, sides, jitter, col, col_low, -0.05, col_top, 0.86, twist)


## Faces of `faces` whose normal.y is at least `min_ny` (all of them if none qualifies).
static func _upper(faces: Array, min_ny: float) -> Array:
	var out: Array = []
	for f in faces:
		if (f[1] as Vector3).y >= min_ny:
			out.append(f)
	return out if not out.is_empty() else faces


## Speck of colour (flowers, blossom, berries): a tiny cone of `sides` triangles, randomly turned; `sq` squashes it.
static func _dot(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, r: float, col: Color, sq: Vector3 = Vector3.ONE, sides: int = 3) -> void:
	mb.push(Transform3D(Basis.from_scale(sq) * Basis(Vector3.UP, rng.randf() * TAU), p))
	mb.cyl(Vector3(0, -r * 0.45, 0), r * 1.45, r, 0.0, sides, col, false)
	mb.pop()


## Elongated double cone from `p` along `axis` (flower spikes, buds, plumes): `sides`·2 triangles, upper half


## `col`, lower half `col_low`.
static func _spindle(mb: MeshBuilder, p: Vector3, axis: Vector3, length: float, r: float, sides: int, col: Color, col_low: Color) -> void:
	var d := axis.normalized()
	var mid := p + d * length * 0.42
	mb.limb(p, mid, 0.0, r, sides, col_low, false)
	mb.limb(mid, p + d * length, r, 0.0, sides, col, false)


## Two-sided triangle: `up` on the face whose normal points upward, `down` on the other.
static func _leaf2(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, up: Color, down: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.y >= 0.0:
		mb.tri(a, b, c, up)
		mb.tri(a, c, b, down)
	else:
		mb.tri(a, b, c, down)
		mb.tri(a, c, b, up)


## Convex fan facing +Y from points given in increasing angle (n - 2 triangles).
static func _fan_up(mb: MeshBuilder, pts: Array, col: Color) -> void:
	for i in range(1, pts.size() - 1):
		mb.tri(pts[0], pts[i + 1], pts[i], col)


## Tapered cylinder like mb.limb() (no caps) whose faces take their colours in turn from `cols`; faces whose


## outward direction points up more than `thr` take `light` instead (sunlit bark on leaning stems).
static func _bark(mb: MeshBuilder, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, cols: Array, light: Variant = null, thr: float = 0.25, rot: float = 0.0) -> void:
	var dir := b - a
	var l := dir.length()
	if l < 0.0001:
		return
	var y := dir / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	for i in sides:
		var a0 := rot + TAU * float(i) / float(sides)
		var a1 := rot + TAU * float(i + 1) / float(sides)
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var col: Color = cols[i % cols.size()]
		if light != null and (d0 + d1).normalized().y > thr:
			col = light
		mb.quad(a + d0 * r0, b + d0 * r1, b + d1 * r1, a + d1 * r0, col)


## Annular-sector block around `c` (paving slabs, curbs, basin walls, well stones): radii r0..r1, angles a0..a1
## (dir = (cos a, 0, sin a)), from y0 up to y1 (+ per-corner top offsets `tj`: inner-a0, inner-a1, outer-a0,
## outer-a1). `faces` is a mask of SEC_* flags. No bottom.
const SEC_TOP := 1
const SEC_OUT := 2
const SEC_IN := 4
const SEC_END0 := 8
const SEC_END1 := 16
const SEC_ALL := 31


static func _sector(mb: MeshBuilder, c: Vector3, r0: float, r1: float, a0: float, a1: float, y0: float, y1: float, col: Color, top_col: Color, faces: int = SEC_ALL, tj: Array = [0.0, 0.0, 0.0, 0.0]) -> void:
	var d0 := Vector3(cos(a0), 0, sin(a0))
	var d1 := Vector3(cos(a1), 0, sin(a1))
	var ib0 := c + d0 * r0 + Vector3(0, y0, 0)
	var ib1 := c + d1 * r0 + Vector3(0, y0, 0)
	var ob0 := c + d0 * r1 + Vector3(0, y0, 0)
	var ob1 := c + d1 * r1 + Vector3(0, y0, 0)
	var it0 := c + d0 * r0 + Vector3(0, y1 + tj[0], 0)
	var it1 := c + d1 * r0 + Vector3(0, y1 + tj[1], 0)
	var ot0 := c + d0 * r1 + Vector3(0, y1 + tj[2], 0)
	var ot1 := c + d1 * r1 + Vector3(0, y1 + tj[3], 0)
	if faces & SEC_TOP:
		mb.quad(ot0, it0, it1, ot1, top_col)
	if faces & SEC_OUT:
		mb.quad(ob0, ot0, ot1, ob1, col)
	if faces & SEC_IN and r0 > 0.001:
		mb.quad(ib1, it1, it0, ib0, col)
	if faces & SEC_END0:
		mb.quad(ib0, it0, ot0, ob0, col)
	if faces & SEC_END1:
		mb.quad(ob1, ot1, it1, ib1, col)


## Box (centre `c`, euler `rot`) emitting only the faces in `mask`: 1 front (+Z), 2 top, 4 left (-X), 8 right
## (+X), 16 back (-Z). Dry-stone walls only show their front and top.
const ST_FRONT := 1
const ST_TOP := 2
const ST_LEFT := 4
const ST_RIGHT := 8
const ST_BACK := 16


static func _stone(mb: MeshBuilder, c: Vector3, size: Vector3, col: Color, top_col: Color, rot: Vector3, mask: int) -> void:
	mb.push(Transform3D(Basis.from_euler(rot), c))
	var h := size * 0.5
	var p0 := Vector3(-h.x, -h.y, -h.z)
	var p1 := Vector3(h.x, -h.y, -h.z)
	var p2 := Vector3(h.x, -h.y, h.z)
	var p3 := Vector3(-h.x, -h.y, h.z)
	var p4 := Vector3(-h.x, h.y, -h.z)
	var p5 := Vector3(h.x, h.y, -h.z)
	var p6 := Vector3(h.x, h.y, h.z)
	var p7 := Vector3(-h.x, h.y, h.z)
	if mask & ST_TOP:
		mb.quad(p4, p7, p6, p5, top_col)
	if mask & ST_FRONT:
		mb.quad(p3, p2, p6, p7, col)
	if mask & ST_BACK:
		mb.quad(p1, p0, p4, p5, col)
	if mask & ST_RIGHT:
		mb.quad(p2, p1, p5, p6, col)
	if mask & ST_LEFT:
		mb.quad(p0, p3, p7, p4, col)
	mb.pop()


## Upward-opening flower cup seen from above: only its inner faces, plus a dark heart (sides + 1 triangles).
static func _cup_in(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, h: float, sides: int, col: Color, heart: Color) -> void:
	var rot := rng.randf() * TAU
	var rim: Array[Vector3] = []
	for i in sides:
		var a := rot + TAU * float(i) / float(sides)
		rim.append(c + Vector3(cos(a) * r, h, sin(a) * r))
	for i in sides:
		mb.tri(c, rim[(i + 1) % sides], rim[i], col if i % 2 == 0 else col.darkened(0.06))
	var hr := r * 0.3
	var hc := c + Vector3(0, h * 0.45, 0)
	mb.tri(hc + Vector3(hr, 0, 0), hc + Vector3(-hr * 0.5, 0, -hr * 0.87), hc + Vector3(-hr * 0.5, 0, hr * 0.87), heart)


## Basis whose Y axis is `n` (for discs laid on a surface).
static func _basis_y(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Flat n-gon flower (n - 2 triangles) on its own plane at `p` facing `n`, with a single-triangle centre.
static func _flower_disc(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, n: Vector3, r: float, sides: int, col: Color, centre: Color) -> void:
	mb.push(Transform3D(_basis_y(n), p))
	var rot := rng.randf() * TAU
	var pts: Array = []
	for i in sides:
		var a := rot + TAU * float(i) / float(sides)
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	_fan_up(mb, pts, col)
	var cr := r * 0.42
	mb.tri(Vector3(cr, 0.012, 0), Vector3(-cr * 0.5, 0.012, -cr * 0.87), Vector3(-cr * 0.5, 0.012, cr * 0.87), centre)
	mb.pop()


## Polyline trunk sampler: position on the segments p[0]..p[n] at height y (extrapolates past the ends).
static func _along(pts: Array, y: float) -> Vector3:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		if y <= b.y or i == pts.size() - 2:
			var t := (y - a.y) / maxf(b.y - a.y, 0.001)
			return a.lerp(b, t)
	return pts[pts.size() - 1]
