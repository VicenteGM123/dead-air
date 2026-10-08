class_name ModelsNature
## Static low-poly nature props and small decorative objects for the island. Each public builder takes a seed
## (variation) and returns an ArrayMesh whose origin is at the base centre, on the ground (y = 0); "front" is +Z.
## Plants use the foliage material (wind sway), everything else the plain lowpoly one: see `material_for()`.
##
## Every model has an `add_*` twin that draws into an existing MeshBuilder at its current transform, so the
## buildings reuse them (olive trees in the farm, amphoras on the dock...). Layout randomness comes from its own
## RandomNumberGenerator, so the per-face shading noise (mb.rng) never changes a model's shape.
##
## The geometry helpers at the bottom (lathe, blob, box5, fluted_shaft, hull...) are shared with ModelsBuildings.

const VARY := 0.03
## Extra named tones (loaded by path so this file never depends on the class-name cache).
const PX := preload("res://scripts/gfx/pal_extra.gd")
## Wind sway for knee-high plants (trees and bushes use Materials.foliage()'s default).
const SMALL_PLANT_SWAY := 0.08

const PLANTS := ["olive_tree", "cypress", "stone_pine", "bush"]
const SMALL_PLANTS := ["flowers_lavender", "flowers_poppy", "flowers_daisy", "grass_tuft"]


static func material_for(model_name: String) -> Material:
	if model_name in PLANTS:
		return Materials.foliage()
	if model_name in SMALL_PLANTS:
		return Materials.foliage(SMALL_PLANT_SWAY)
	return Materials.lowpoly()


static func _begin(seed_value: int) -> MeshBuilder:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = VARY
	return mb


static func make_rng(seed_value: int, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_value * 92821 + salt * 7919 + 17)
	return r


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
	add_bush(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Rounded Mediterranean shrub (mastic / myrtle / oleander), ~1 m; some seeds carry pink or white flowers.
static func add_bush(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var kind := rng.randi() % 3
	var col := Pal.PINE if kind != 1 else Pal.OLIVE_LEAF_DARK
	var n := 2 + rng.randi() % 2
	var a0 := rng.randf() * TAU
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var d := 0.0 if i == 0 else rng.randf_range(0.45, 0.6) * s
		var r := (0.68 if i == 0 else rng.randf_range(0.46, 0.55)) * s
		var c := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var prof := [Vector2(0, 0), Vector2(0.86, 0.04), Vector2(1.0, 0.45), Vector2(0.72, 0.92), Vector2(0, 1.12)]
		blob(mb, rng, c, _scaled(prof, r), 7, 0.12, col if i > 0 else col.lightened(0.04), Pal.CYPRESS, -0.15)
		centres.append(c)
		radii.append(r)
	if kind == 0:
		return
	var flower := Pal.BOUGAINVILLEA if kind == 2 else Pal.DAISY
	for i in 8:
		var k := i % n
		var c: Vector3 = centres[k]
		var r: float = radii[k]
		var a := rng.randf() * TAU
		var el := rng.randf_range(0.3, 1.05)
		var p := c + Vector3(cos(a) * sin(el) * r * 0.92, 0.45 * r + cos(el) * r * 0.62, sin(a) * sin(el) * r * 0.92)
		mb.ico(p, 0.085 * s, flower, 0, 0.0, Vector3(1, 0.7, 1))


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


## Three grey-green cushions bristling with purple flower spikes (~0.8 m across).
static func add_lavender(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var a0 := rng.randf() * TAU
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0 + rng.randf_range(-0.3, 0.3)
		var d := rng.randf_range(0.17, 0.22) * s
		var c := Vector3(cos(a) * d, 0, sin(a) * d)
		var r := rng.randf_range(0.19, 0.23) * s
		var prof := [Vector2(0, -0.02), Vector2(r, 0.0), Vector2(r * 0.95, r * 0.5), Vector2(r * 0.5, r * 0.88), Vector2(0, r)]
		blob(mb, rng, c, prof, 6, 0.14, Pal.OLIVE_LEAF, Pal.OLIVE_LEAF_DARK)
		for k in 6:
			var b := a0 + TAU * float(k) / 6.0 + rng.randf_range(-0.4, 0.4)
			var el := rng.randf_range(0.15, 0.8)
			var dir := Vector3(cos(b) * sin(el), cos(el), sin(b) * sin(el))
			var head := c + Vector3(0, r * 0.3, 0) + dir * (r * rng.randf_range(1.0, 1.35))
			var hl := rng.randf_range(0.14, 0.2) * s
			mb.limb(head, head + dir * hl, 0.05 * s, 0.0, 4, Pal.LAVENDER, false)
			mb.limb(head + dir * 0.01, head - dir * 0.05 * s, 0.05 * s, 0.0, 4, Pal.LAVENDER.darkened(0.18), false)


static func flowers_poppy(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_poppies(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## A tuft of grass with red poppies on thin stems (~0.8 m across).
static func add_poppies(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	_grass_blades(mb, rng, 12, 0.3 * s, 0.32 * s, [Pal.GRASS, Pal.GRASS_DARK, Pal.GRASS_LIGHT])
	var n := 6 + rng.randi() % 3
	for i in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.05, 0.34) * s
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := rng.randf_range(0.32, 0.55) * s
		var top := base + Vector3(cos(a) * 0.07, h, sin(a) * 0.07)
		mb.limb(base, top, 0.012 * s, 0.01 * s, 3, Pal.GRASS_DARK, false)
		cup(mb, rng, top, 0.095 * s, 0.055 * s, 5, Pal.POPPY, Pal.SKIN_SHADOW)


static func flowers_daisy(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_daisies(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Low leafy clump scattered with white daisies (~0.8 m across).
static func add_daisies(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var a0 := rng.randf() * TAU
	for i in 3:
		var a := a0 + TAU * float(i) / 3.0
		var d := rng.randf_range(0.14, 0.22) * s
		var r := rng.randf_range(0.17, 0.22) * s
		var prof := [Vector2(r, 0.0), Vector2(r * 0.75, r * 0.45), Vector2(0, r * 0.6)]
		blob(mb, rng, Vector3(cos(a) * d, -0.02, sin(a) * d), prof, 5, 0.18, Pal.GRASS, Pal.GRASS_DARK)
	_grass_blades(mb, rng, 6, 0.3 * s, 0.22 * s, [Pal.GRASS_DARK, Pal.GRASS])
	for i in 9:
		var a := a0 + TAU * float(i) / 9.0 + rng.randf_range(-0.3, 0.3)
		var d := (0.12 + 0.24 * float(i % 3) / 2.0) * s
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var top := base + Vector3(0, rng.randf_range(0.14, 0.3) * s, 0)
		mb.limb(base, top, 0.012 * s, 0.012 * s, 3, Pal.GRASS_DARK, false)
		var r := rng.randf_range(0.06, 0.075) * s
		var rot := rng.randf() * TAU
		mb.cyl(top, 0.014 * s, r * 0.9, r, 6, Pal.MARBLE_SHADE, false, rot)
		mb.disc(top + Vector3(0, 0.014 * s, 0), r, 6, Pal.DAISY)
		mb.cyl(top + Vector3(0, 0.014 * s, 0), 0.03 * s, r * 0.4, 0.0, 4, Pal.GOLD, false, rot)


static func grass_tuft(seed_value: int) -> ArrayMesh:
	var mb := _begin(seed_value)
	add_grass_tuft(mb, make_rng(seed_value), 1.0)
	return mb.commit()


## Clump of sharp grass blades, green or summer-dry (~0.5 m).
static func add_grass_tuft(mb: MeshBuilder, rng: RandomNumberGenerator, s: float = 1.0) -> void:
	var dry := rng.randf() < 0.35
	var cols: Array = [Pal.GRASS, Pal.GRASS_LIGHT, Pal.GRASS_DARK] if not dry else [Pal.GRASS_DRY, Pal.GRASS_LIGHT, Pal.GRASS]
	_grass_blades(mb, rng, 15 + rng.randi() % 5, 0.2 * s, rng.randf_range(0.42, 0.58) * s, cols, 1.4)


static func _grass_blades(mb: MeshBuilder, rng: RandomNumberGenerator, n: int, spread: float, h: float, cols: Array, width: float = 1.0) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		var base := Vector3(cos(a) * d, -0.02, sin(a) * d)
		var out := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.24) * h / 0.4
		var tip := base + out + Vector3(0, h * rng.randf_range(0.6, 1.1), 0)
		var col: Color = cols[i % cols.size()]
		mb.limb(base, tip, 0.035 * h / 0.4 * width, 0.0, 3, col, false)


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
				var ny := n.normalized().y
				if ny < under:
					fc = col_low
				elif col_top != null and ny > top_thr:
					fc = col_top
			mb.quad(lo[i], hi[i], hi[k], lo[k], fc)


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
