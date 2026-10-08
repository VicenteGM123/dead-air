class_name ModelsBuildings
## Procedural low-poly buildings for the build spots, all on the plain lowpoly material.
## `building(type, level, seed)` returns {"mesh", "anchors", "footprint" (radius m), "height" (m)}. Origin at the
## base centre on the ground, front = +Z (the game turns houses and farms to face the plaza, towers, walls and
## barracks along their lane, docks out to sea).
##
## Anchors (local space):
##   pharos   fire (brazier bowl centre), door (on the ground at the foot of the steps, on the door's axis)
##   house    door (on the ground in front of the door)
##   farm     gate (on the ground in the gap of the front wall)
##   dock     boat_1 (+ boat_2 on level 2): mooring points on the water (y = 0), boats lie along Z; end (pier tip)
##   tower    archer (top floor, centre: the archer's feet), muzzle (bow height above it)
##   wall     left, right (the two ends, on the ground)
##   barracks rally (on the ground ~4 m in front of the porch), door
##
## Windows use Pal.WINDOW (dark by day, warm glow at night). Little `preview_*` wrappers at the bottom are for
## tools/preview.tscn.

const VARY := 0.03
## Extra named tones (loaded by path so this file never depends on the class-name cache).
const PX := preload("res://scripts/gfx/pal_extra.gd")
const LEVELS := {"pharos": 3, "house": 2, "farm": 2, "dock": 2, "tower": 3, "wall": 2, "barracks": 2}


static func building(type: String, level: int, seed_value: int) -> Dictionary:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = VARY
	var rng := ModelsNature.make_rng(seed_value, 3)
	var lv := clampi(level, 1, int(LEVELS.get(type, 1)))
	var out := {}
	match type:
		"pharos":
			out = _pharos(mb, rng, lv)
		"house":
			out = _house(mb, rng, lv)
		"farm":
			out = _farm(mb, rng, lv)
		"dock":
			out = _dock(mb, rng, lv)
		"tower":
			out = _tower(mb, rng, lv)
		"wall":
			out = _wall(mb, rng, lv)
		"barracks":
			out = _barracks(mb, rng, lv)
		_:
			push_warning("ModelsBuildings: unknown building type '%s'" % type)
			out = {"anchors": {}, "footprint": 1.0, "height": 1.0}
			_box(mb, Vector3(0, 0.5, 0), Vector3.ONE, Pal.LIMESTONE)
	out["mesh"] = mb.commit()
	return out


# --- pharos --------------------------------------------------------------------------------------------------

static func _pharos(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	var big := 0.4 if lv == 3 else 0.0
	# Stepped limestone platform.
	var y := 0.0
	var sizes := [7.2 + big, 6.4 + big, 5.6 + big]
	for i in 3:
		var w: float = sizes[i]
		var h := 0.32 if i > 0 else 0.62
		var yc := y + 0.32 - h * 0.5
		_box(mb, Vector3(0, yc, 0), Vector3(w, h, w), Pal.LIMESTONE_DARK, Pal.LIMESTONE if i < 2 else Pal.MARBLE_SHADE)
		y += 0.32
	# Paving joints on the top step.
	var tw: float = sizes[2]
	for k in [-1.0, 1.0]:
		_box(mb, Vector3(k * tw * 0.25, y + 0.005, 0), Vector3(0.05, 0.02, tw - 0.1), Pal.LIMESTONE_DARK)
		_box(mb, Vector3(0, y + 0.005, k * tw * 0.25), Vector3(tw - 0.1, 0.02, 0.05), Pal.LIMESTONE_DARK)
	var plat := y
	var o := Vector3(0, plat, 0)
	var fire_y := 0.0
	var front := 0.0 # z of the door face
	match lv:
		1:
			var prof := [
				Vector2(2.3, 0.0), Vector2(2.3, 0.4), Vector2(2.0, 0.4), Vector2(1.84, 5.9), Vector2(2.02, 6.06),
				Vector2(2.02, 6.3), Vector2(2.3, 6.42), Vector2(2.3, 6.86), Vector2(2.12, 6.86), Vector2(2.12, 6.58), Vector2(0, 6.58),
			]
			var cols := [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE, Pal.LIMESTONE, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.MARBLE, Pal.MARBLE_SHADE, Pal.MARBLE_SHADE, Pal.LIMESTONE]
			ModelsNature.lathe(mb, o, prof, 8, cols, PI / 8.0)
			_band(mb, o + Vector3(0, 3.1, 0), 1.94, 0.16, 8, Pal.MARBLE_SHADE, PI / 8.0)
			front = 2.0 * cos(PI / 8.0)
			for k in [[0.0, 2.7], [PI * 0.5, 4.4], [-PI * 0.5, 3.6], [PI, 4.9], [0.0, 4.9]]:
				_slit(mb, o, k[0], k[1], (1.84 + (2.0 - 1.84) * (1.0 - k[1] / 5.9)) * cos(PI / 8.0), 0.3, 0.8)
			ModelsNature.lathe(mb, o + Vector3(0, 6.58, 0), [Vector2(1.15, 0.0), Vector2(1.15, 0.05), Vector2(0, 0.05)], 8, Pal.LIMESTONE_DARK, PI / 8.0)
			fire_y = plat + 6.63 + _brazier(mb, o + Vector3(0, 6.63, 0), 0.78, 1.0)
		2:
			var prof := [
				Vector2(2.35, 0.0), Vector2(2.35, 0.4), Vector2(2.06, 0.4), Vector2(1.84, 5.3), Vector2(2.45, 5.62),
				Vector2(2.45, 5.8), Vector2(1.56, 5.8), Vector2(1.4, 8.95), Vector2(1.6, 9.1), Vector2(1.6, 9.3),
				Vector2(1.86, 9.4), Vector2(1.86, 9.82), Vector2(1.7, 9.82), Vector2(1.7, 9.55), Vector2(0, 9.55),
			]
			var cols := [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE,
				Pal.LIMESTONE, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.MARBLE, Pal.MARBLE_SHADE, Pal.MARBLE_SHADE, Pal.LIMESTONE]
			ModelsNature.lathe(mb, o, prof, 8, cols, PI / 8.0)
			_railing(mb, o + Vector3(0, 5.8, 0), 2.38, 0.62, 16, Pal.MARBLE, Pal.MARBLE_SHADE)
			_band(mb, o + Vector3(0, 2.9, 0), 1.98, 0.16, 8, Pal.MARBLE_SHADE, PI / 8.0)
			_band(mb, o + Vector3(0, 7.6, 0), 1.48, 0.14, 8, Pal.AEGEAN, PI / 8.0)
			front = 2.06 * cos(PI / 8.0)
			for k in [[0.0, 2.5], [PI * 0.5, 4.0], [-PI * 0.5, 3.3], [PI, 4.4]]:
				_slit(mb, o, k[0], k[1], (1.84 + (2.06 - 1.84) * (1.0 - k[1] / 5.3)) * cos(PI / 8.0), 0.3, 0.8)
			for k in [[0.0, 7.0], [PI * 0.75, 7.6], [-PI * 0.75, 7.6], [PI * 0.5, 8.2]]:
				_slit(mb, o, k[0], k[1], (1.4 + (1.56 - 1.4) * (1.0 - (k[1] - 5.8) / 3.15)) * cos(PI / 8.0), 0.26, 0.7)
			ModelsNature.lathe(mb, o + Vector3(0, 9.55, 0), [Vector2(1.1, 0.0), Vector2(1.1, 0.05), Vector2(0, 0.05)], 8, Pal.LIMESTONE_DARK, PI / 8.0)
			for i in 8:
				var fa := PI / 8.0 + TAU * float(i) / 8.0
				mb.cyl(o + Vector3(cos(fa) * 1.86, 9.82, sin(fa) * 1.86), 0.3, 0.08, 0.0, 4, Pal.BRONZE, false)
			fire_y = plat + 9.6 + _brazier(mb, o + Vector3(0, 9.6, 0), 0.74, 1.0)
		_:
			fire_y = _pharos_l3(mb, rng, o)
			front = 2.2
	# Door with a bronze-trimmed limestone frame and a little pediment.
	var dz := front
	var door_base := o + Vector3(0, 0.4, dz)
	_box(mb, door_base + Vector3(0, 1.0, 0.03), Vector3(1.4, 2.0, 0.12), Pal.LIMESTONE)
	_box(mb, door_base + Vector3(0, 0.88, 0.1), Vector3(0.95, 1.76, 0.08), Pal.AEGEAN)
	_box(mb, door_base + Vector3(0, 0.88, 0.15), Vector3(0.05, 1.7, 0.04), Pal.AEGEAN.darkened(0.2))
	_box(mb, door_base + Vector3(0, 2.06, 0.08), Vector3(1.6, 0.14, 0.22), Pal.BRONZE)
	mb.push(Transform3D(Basis(Vector3.UP, PI * 0.5), door_base + Vector3(0, 2.13, 0.08)))
	mb.roof_gable(Vector3.ZERO, 0.24, 1.6, 0.32, Pal.LIMESTONE, Pal.MARBLE_SHADE)
	mb.pop()
	_box(mb, door_base + Vector3(0.28, 0.9, 0.16), Vector3(0.08, 0.08, 0.06), Pal.BRONZE)
	_box(mb, door_base + Vector3(-0.28, 0.9, 0.16), Vector3(0.08, 0.08, 0.06), Pal.BRONZE)
	# Lamps flanking the door.
	var half: float = sizes[0] * 0.5
	for sx in [-1.0, 1.0]:
		_post_lamp(mb, Vector3(sx * 1.55, plat, dz + 0.55))
	return {
		"anchors": {"fire": Vector3(0, fire_y, 0), "door": Vector3(0, 0, half + 0.75)},
		"footprint": half,
		"height": fire_y + 1.0,
	}


## Level 3: three tiers like the great Pharos (square, octagonal, round) with bronze ornaments.
static func _pharos_l3(mb: MeshBuilder, rng: RandomNumberGenerator, o: Vector3) -> float:
	var sq := sqrt(2.0)
	# Tier 1: square, slightly battered, with corner acroteria and bronze shields.
	var p1 := [
		Vector2(2.5, 0.0), Vector2(2.5, 0.4), Vector2(2.22, 0.4), Vector2(2.02, 4.7), Vector2(2.2, 4.86),
		Vector2(2.2, 5.08), Vector2(2.36, 5.16), Vector2(2.36, 5.56), Vector2(2.2, 5.56), Vector2(2.2, 5.3), Vector2(0, 5.3),
	]
	var c1 := [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE, Pal.LIMESTONE, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.MARBLE, Pal.MARBLE_SHADE, Pal.MARBLE_SHADE, Pal.LIMESTONE]
	ModelsNature.lathe(mb, o, _sq(p1), 4, c1, PI * 0.25)
	_band(mb, o + Vector3(0, 2.5, 0), 2.14 * sq, 0.16, 4, Pal.BRONZE, PI * 0.25)
	for i in 4:
		var a := PI * 0.5 * float(i)
		var n := Vector3(sin(a), 0, cos(a))
		var t := Vector3(cos(a), 0, -sin(a))
		# corner acroterion
		var corner := o + (n + t) * 2.28 + Vector3(0, 5.56, 0)
		_box(mb, corner + Vector3(0, 0.12, 0), Vector3(0.36, 0.24, 0.36), Pal.MARBLE_SHADE)
		mb.cyl(corner + Vector3(0, 0.24, 0), 0.5, 0.17, 0.0, 4, Pal.BRONZE, false, PI * 0.25)
		# bronze shield on each face (not over the door)
		if i != 0:
			_disc_on_wall(mb, o + n * 2.08 + Vector3(0, 3.7, 0), a, 0.42, Pal.BRONZE, Pal.BRONZE_DARK)
		_slit(mb, o, a, 3.6 if i == 0 else 1.9, 2.22 - 0.2 * (3.6 if i == 0 else 1.9) / 4.3, 0.32, 0.85)
	# Tier 2: octagon on the terrace.
	var o2 := o + Vector3(0, 5.3, 0)
	var p2 := [
		Vector2(1.92, 0.0), Vector2(1.92, 0.3), Vector2(1.74, 0.3), Vector2(1.56, 4.3), Vector2(1.76, 4.45),
		Vector2(1.76, 4.62), Vector2(1.96, 4.7), Vector2(1.96, 5.0), Vector2(1.8, 5.0), Vector2(1.8, 4.8), Vector2(0, 4.8),
	]
	var c2 := [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE, Pal.LIMESTONE, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.MARBLE, Pal.BRONZE, Pal.MARBLE_SHADE, Pal.LIMESTONE]
	ModelsNature.lathe(mb, o2, p2, 8, c2, PI / 8.0)
	_band(mb, o2 + Vector3(0, 2.2, 0), 1.7, 0.14, 8, Pal.BRONZE, PI / 8.0)
	_band(mb, o2 + Vector3(0, 1.1, 0), 1.75, 0.12, 8, Pal.AEGEAN, PI / 8.0)
	for k in [[0.0, 3.2], [PI * 0.5, 2.6], [-PI * 0.5, 3.4], [PI, 2.8], [PI * 0.25, 1.6], [-PI * 0.75, 1.6]]:
		_slit(mb, o2, k[0], k[1], (1.56 + (1.74 - 1.56) * (1.0 - k[1] / 4.3)) * cos(PI / 8.0), 0.26, 0.7)
	# Tier 3: round lantern drum with bronze crown.
	var o3 := o2 + Vector3(0, 4.8, 0)
	var p3 := [
		Vector2(1.36, 0.0), Vector2(1.36, 0.22), Vector2(1.16, 0.22), Vector2(1.04, 2.1), Vector2(1.22, 2.24),
		Vector2(1.22, 2.42), Vector2(1.5, 2.5), Vector2(1.5, 2.86), Vector2(1.36, 2.86), Vector2(1.36, 2.62), Vector2(0, 2.62),
	]
	var c3 := [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE, Pal.BRONZE, Pal.BRONZE, Pal.LIMESTONE_DARK, Pal.MARBLE, Pal.MARBLE_SHADE, Pal.MARBLE_SHADE, Pal.LIMESTONE]
	ModelsNature.lathe(mb, o3, p3, 10, c3)
	_band(mb, o3 + Vector3(0, 1.0, 0), 1.12, 0.16, 10, Pal.BRONZE)
	for i in 4:
		var a: float = [0.0, TAU * 0.2, -TAU * 0.2, PI * 0.8][i]
		_slit(mb, o3, a, 1.4, 1.1 * cos(PI / 10.0), 0.22, 0.6)
	# Crown of bronze spikes on the parapet.
	for i in 10:
		var a := TAU * float(i) / 10.0 + PI * 0.1
		var p := o3 + Vector3(cos(a) * 1.43, 2.86, sin(a) * 1.43)
		mb.cyl(p, 0.42, 0.09, 0.0, 4, Pal.BRONZE, false)
	return o3.y + 2.62 + _brazier(mb, o3 + Vector3(0, 2.62, 0), 0.7, 1.0)


## Radius-to-corner conversion for square lathes (profiles authored as half-widths).
static func _sq(prof: Array) -> Array:
	var out := []
	for p in prof:
		var v: Vector2 = p
		out.append(Vector2(v.x * sqrt(2.0), v.y))
	return out


## Bronze brazier standing at `base`: a tripod and pedestal holding a wide open bowl with a coal bed. Returns the
## height of the fire anchor (bowl centre, just under the rim) above `base`.
static func _brazier(mb: MeshBuilder, base: Vector3, r: float, h: float) -> float:
	ModelsNature.lathe(mb, base, [Vector2(0.5, 0.0), Vector2(0.5, 0.1), Vector2(0.24, 0.18), Vector2(0.17, 0.55 * h), Vector2(0.3, 0.64 * h)], 6, [Pal.BRONZE_DARK, Pal.BRONZE_DARK, Pal.BRONZE, Pal.BRONZE])
	var b0 := 0.62 * h
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.3
		var foot := base + Vector3(cos(a) * r * 1.05, 0.0, sin(a) * r * 1.05)
		var knee := base + Vector3(cos(a) * r * 0.95, b0 * 0.6, sin(a) * r * 0.95)
		mb.limb(foot, knee, 0.06, 0.05, 4, Pal.BRONZE_DARK)
		mb.limb(knee, base + Vector3(cos(a) * r * 0.7, b0 + 0.22, sin(a) * r * 0.7), 0.05, 0.04, 4, Pal.BRONZE)
		_box(mb, foot + Vector3(0, 0.04, 0), Vector3(0.16, 0.08, 0.16), Pal.BRONZE_DARK)
	var bowl := [
		Vector2(0.3, 0.0), Vector2(r * 0.86, 0.2), Vector2(r * 1.06, 0.42), Vector2(r * 1.18, 0.5), Vector2(r * 0.98, 0.52),
		Vector2(r * 0.88, 0.34), Vector2(r * 0.55, 0.32), Vector2(0, 0.34),
	]
	var bc := [Pal.BRONZE, Pal.BRONZE, Pal.GOLD_DARK, Pal.BRONZE, Pal.BRONZE_DARK, Pal.WOOD_DARK, Pal.SKIN_SHADOW]
	ModelsNature.lathe(mb, base + Vector3(0, b0, 0), bowl, 8, bc, PI / 8.0)
	return b0 + 0.36


## Narrow window slit on a lathe tower: angle `a` (0 = +Z), centre height `yc` above `o`, at radius `r`.
static func _slit(mb: MeshBuilder, o: Vector3, a: float, yc: float, r: float, w: float, h: float) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, a), o + Vector3(sin(a), 0, cos(a)) * (r - 0.02) + Vector3(0, yc, 0)))
	_box(mb, Vector3(0, 0, 0.0), Vector3(w + 0.16, h + 0.16, 0.08), Pal.MARBLE_SHADE)
	_box(mb, Vector3(0, 0, 0.03), Vector3(w, h, 0.08), Pal.WINDOW)
	mb.roof_gable(Vector3(0, h * 0.5 + 0.08, 0.02), w + 0.24, 0.12, 0.14, Pal.MARBLE_SHADE)
	mb.pop()


## Thin protruding ring band around a prism tower.
static func _band(mb: MeshBuilder, c: Vector3, r: float, h: float, sides: int, col: Color, rot: float = 0.0) -> void:
	ModelsNature.lathe(mb, c, [Vector2(r - 0.1, 0.0), Vector2(r + 0.05, 0.0), Vector2(r + 0.05, h), Vector2(r - 0.1, h)], sides, col, rot)


## Round bronze disc (shield/rosette) on a wall facing angle `a` (0 = +Z).
static func _disc_on_wall(mb: MeshBuilder, p: Vector3, a: float, r: float, col: Color, rim: Color) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5), p))
	mb.cyl(Vector3.ZERO, 0.06, r, r * 0.92, 8, rim, false)
	mb.cyl(Vector3(0, 0.06, 0), 0.05, r * 0.84, r * 0.3, 8, col, true)
	mb.pop()


## Railing ring: posts and a top rail around +Y at radius r.
static func _railing(mb: MeshBuilder, base: Vector3, r: float, h: float, posts: int, col: Color, rail_col: Color) -> void:
	for i in posts:
		var a := TAU * float(i) / float(posts)
		_box(mb, base + Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(0.09, h, 0.09), col)
	ModelsNature.lathe(mb, base + Vector3(0, h, 0), [Vector2(r - 0.07, 0), Vector2(r + 0.07, 0), Vector2(r + 0.07, 0.08), Vector2(r - 0.07, 0.08), Vector2(r - 0.07, 0)], posts, rail_col, PI / float(posts))


## Little marble lamp post with a glass lantern that lights up at night.
static func _post_lamp(mb: MeshBuilder, base: Vector3) -> void:
	_box(mb, base + Vector3(0, 0.15, 0), Vector3(0.42, 0.3, 0.42), Pal.MARBLE_SHADE, Pal.MARBLE)
	mb.cyl(base + Vector3(0, 0.3, 0), 0.75, 0.12, 0.1, 6, Pal.MARBLE, false)
	_box(mb, base + Vector3(0, 1.13, 0), Vector3(0.3, 0.14, 0.3), Pal.BRONZE)
	_box(mb, base + Vector3(0, 1.36, 0), Vector3(0.24, 0.32, 0.24), Pal.WINDOW)
	mb.roof_pyramid(base + Vector3(0, 1.52, 0), 0.36, 0.36, 0.22, Pal.BRONZE)


## Ember bed: warm dark coals by day (rgb), glowing at night (alpha 0 = night-glow flag).
const VINE_LEAF := Color("86A04E")
const VINE_LEAF_DARK := Color("62803E")
const GRAPES := Color("5E3C72")
const GRAPES_DARK := Color("47305A")
const EMBERS := Color(0.36, 0.16, 0.1, 0.0)


## Small bronze fire bowl on a pedestal; its coal bed glows at night.
static func _fire_bowl(mb: MeshBuilder, base: Vector3, r: float = 0.32) -> void:
	ModelsNature.lathe(mb, base, [Vector2(0.24, 0.0), Vector2(0.1, 0.12), Vector2(0.08, 0.62), Vector2(0.14, 0.7)], 5, [Pal.BRONZE_DARK, Pal.BRONZE, Pal.BRONZE])
	ModelsNature.lathe(mb, base + Vector3(0, 0.7, 0), [Vector2(0.14, 0.0), Vector2(r, 0.16), Vector2(r * 1.12, 0.24), Vector2(r * 0.86, 0.2), Vector2(0, 0.2)], 6, [Pal.BRONZE, Pal.GOLD_DARK, Pal.BRONZE_DARK, EMBERS])


## Lantern hanging from a little bronze bracket on a +Z-facing wall (`p` = bracket on the wall).
static func _wall_lantern(mb: MeshBuilder, p: Vector3) -> void:
	_plaque(mb, p + Vector3(0, 0, 0.12), Vector3(0.05, 0.05, 0.24), Pal.BRONZE_DARK)
	_box(mb, p + Vector3(0, -0.2, 0.22), Vector3(0.18, 0.26, 0.18), Pal.WINDOW)
	mb.roof_pyramid(p + Vector3(0, -0.07, 0.22), 0.24, 0.24, 0.12, Pal.BRONZE)


# --- house ---------------------------------------------------------------------------------------------------

static func _house(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	if lv >= 2:
		return _house2(mb, rng)
	var w := 4.0
	var d := 3.3
	var wall_h := 2.5
	var base := 0.18
	var hd := d * 0.5
	_box(mb, Vector3(0, base * 0.5 - 0.15, 0), Vector3(w + 0.36, base + 0.3, d + 0.36), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	_box(mb, Vector3(0, base + wall_h * 0.5, 0), Vector3(w, wall_h, d), Pal.MARBLE)
	var top := base + wall_h
	_gable_roof(mb, Vector3(0, top, 0), w, hd, 1.05, 0.34, 0.24, Pal.MARBLE)
	# Front: door left of centre, a window to the right.
	var door_x := -0.75 if rng.randf() < 0.5 else 0.75
	_door(mb, Vector3(door_x, base, hd), 0.82, 1.62)
	_window(mb, Vector3(-door_x * 1.25, base + 1.35, hd), 0.62, 0.62)
	_box(mb, Vector3(door_x, 0.06, hd + 0.4), Vector3(1.1, 0.12 + 0.14, 0.5), Pal.LIMESTONE, Pal.MARBLE_SHADE)
	# Back and sides.
	_on_wall(mb, Vector3(0, base + 1.35, -hd), PI)
	_window(mb, Vector3(-0.85, 0, 0), 0.62, 0.62)
	_window(mb, Vector3(0.95, 0, 0), 0.5, 0.5)
	mb.pop()
	# Woodpile and a water jar behind the house.
	var wx := 0.15 if door_x < 0.0 else -0.15
	for i in 5:
		var row := 0 if i < 3 else 1
		var lx := wx - 0.3 + 0.3 * float(i - row * 3) + 0.15 * float(row)
		mb.limb(Vector3(lx, 0.12 + 0.22 * float(row), -hd - 0.08), Vector3(lx + 0.02, 0.12 + 0.22 * float(row), -hd - 0.62), 0.11, 0.11, 5, Pal.WOOD if i % 2 == 0 else Pal.WOOD_LIGHT)
	mb.push_at(Vector3(-wx * 8.0, 0, -hd - 0.38), rng.randf() * TAU, Vector3.ONE * 0.85)
	ModelsNature.add_amphora(mb, rng, 1.0, 2)
	mb.pop()
	_on_wall(mb, Vector3(w * 0.5, base + 1.3, 0.1), PI * 0.5)
	_window(mb, Vector3.ZERO, 0.5, 0.55)
	mb.pop()
	_on_wall(mb, Vector3(-w * 0.5, base + 1.3, -0.2), -PI * 0.5)
	_window(mb, Vector3.ZERO, 0.5, 0.55)
	mb.pop()
	# Chimney.
	var cx := 1.2 if door_x < 0.0 else -1.2
	_box(mb, Vector3(cx, top + 1.05, -0.55), Vector3(0.44, 1.3, 0.44), Pal.MARBLE)
	_box(mb, Vector3(cx, top + 1.76, -0.55), Vector3(0.56, 0.12, 0.56), Pal.MARBLE_SHADE)
	_box(mb, Vector3(cx, top + 1.86, -0.55), Vector3(0.3, 0.1, 0.3), Pal.TERRACOTTA_DARK)
	# Flower pot by the door and a bench under the window.
	_pot_plant(mb, rng, Vector3(door_x + (0.75 if door_x < 0.0 else -0.75), 0, hd + 0.35))
	_pot_plant(mb, rng, Vector3(door_x - (0.72 if door_x < 0.0 else -0.72), 0, hd + 0.32), 0.8)
	_bench(mb, Vector3(-door_x * 1.25, 0, hd + 0.38))
	return {"anchors": {"door": Vector3(door_x, 0, hd + 0.95)}, "footprint": 2.5, "height": top + 1.9}


static func _house2(mb: MeshBuilder, rng: RandomNumberGenerator) -> Dictionary:
	# Two-storey main block (left) + single-storey annex with a roof terrace (right) + pergola.
	var base := 0.18
	var mw := 3.8
	var md := 3.5
	var mx := -0.95
	var mh := 4.5
	var hd := md * 0.5
	_box(mb, Vector3(0.25, base * 0.5 - 0.15, -0.05), Vector3(6.6, base + 0.3, md + 0.46), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	_box(mb, Vector3(mx, base + mh * 0.5, 0), Vector3(mw, mh, md), Pal.MARBLE)
	_box(mb, Vector3(mx, base + 2.3, 0), Vector3(mw + 0.08, 0.12, md + 0.08), Pal.MARBLE_SHADE)
	_gable_roof(mb, Vector3(mx, base + mh, 0), mw, hd, 1.05, 0.34, 0.24, Pal.MARBLE)
	# Annex.
	var ax := 2.15
	var aw := 2.4
	var ad := 2.7
	var az := -0.35
	var ah := 2.6
	_box(mb, Vector3(ax, base + ah * 0.5, az), Vector3(aw, ah, ad), Pal.MARBLE)
	# Terrace parapet.
	var ty := base + ah
	_box(mb, Vector3(ax, ty + 0.03, az), Vector3(aw + 0.1, 0.06, ad + 0.1), Pal.MARBLE_SHADE)
	_box(mb, Vector3(ax + aw * 0.5 - 0.06, ty + 0.3, az), Vector3(0.14, 0.5, ad + 0.1), Pal.MARBLE)
	_box(mb, Vector3(ax, ty + 0.3, az - ad * 0.5 + 0.06), Vector3(aw + 0.1, 0.5, 0.14), Pal.MARBLE)
	_box(mb, Vector3(ax, ty + 0.3, az + ad * 0.5 - 0.06), Vector3(aw + 0.1, 0.5, 0.14), Pal.MARBLE)
	# Upper door from the main block onto the terrace.
	_on_wall(mb, Vector3(mx + mw * 0.5, ty, -0.35), PI * 0.5)
	_door(mb, Vector3.ZERO, 0.75, 1.55)
	mb.pop()
	# Front of the main block: door + window downstairs, two windows and a small balcony upstairs.
	var dx := mx - 0.75
	_door(mb, Vector3(dx, base, hd), 0.82, 1.65)
	_box(mb, Vector3(dx, 0.06, hd + 0.4), Vector3(1.1, 0.26, 0.5), Pal.LIMESTONE, Pal.MARBLE_SHADE)
	_window(mb, Vector3(mx + 0.85, base + 1.3, hd), 0.6, 0.62)
	_window(mb, Vector3(mx - 0.75, base + 3.45, hd), 0.6, 0.66)
	_window(mb, Vector3(mx + 0.85, base + 3.45, hd), 0.6, 0.66)
	_box(mb, Vector3(mx - 0.75, base + 2.98, hd + 0.3), Vector3(1.2, 0.1, 0.62), Pal.MARBLE_SHADE)
	for i in 6:
		_box(mb, Vector3(mx - 1.3 + float(i) * 0.22, base + 3.22, hd + 0.58), Vector3(0.05, 0.42, 0.05), Pal.AEGEAN)
	_box(mb, Vector3(mx - 0.75, base + 3.45, hd + 0.58), Vector3(1.2, 0.06, 0.07), Pal.AEGEAN)
	# Back and sides.
	_on_wall(mb, Vector3(mx, base + 1.3, -hd), PI)
	_window(mb, Vector3(-0.8, 0, 0), 0.6, 0.62)
	_window(mb, Vector3(0.8, 2.1, 0), 0.6, 0.62)
	mb.pop()
	_on_wall(mb, Vector3(mx - mw * 0.5, base + 3.4, 0), -PI * 0.5)
	_window(mb, Vector3.ZERO, 0.5, 0.55)
	mb.pop()
	_on_wall(mb, Vector3(ax + aw * 0.5, base + 1.3, az), PI * 0.5)
	_window(mb, Vector3.ZERO, 0.55, 0.58)
	mb.pop()
	# Chimney.
	_box(mb, Vector3(mx + 1.1, base + mh + 1.05, -0.6), Vector3(0.44, 1.4, 0.44), Pal.MARBLE)
	_box(mb, Vector3(mx + 1.1, base + mh + 1.8, -0.6), Vector3(0.56, 0.12, 0.56), Pal.MARBLE_SHADE)
	# Vine arbour in front of the annex.
	var pz := az + ad * 0.5 + 1.25
	var px0 := ax - aw * 0.5 + 0.2
	for sx in [px0, ax + aw * 0.5 - 0.15]:
		mb.cyl(Vector3(sx, 0, pz), 2.35, 0.08, 0.07, 6, Pal.WOOD)
	for zz in [pz, az + ad * 0.5 + 0.1]:
		_box(mb, Vector3(ax, 2.42, zz), Vector3(aw + 0.3, 0.12, 0.12), Pal.WOOD)
	for i in 5:
		_box(mb, Vector3(px0 - 0.1 + float(i) * 0.55, 2.52, (pz + az + ad * 0.5) * 0.5 + 0.1), Vector3(0.08, 0.08, 1.75), Pal.WOOD_LIGHT)
	_vine_canopy(mb, rng, Vector3(px0, 2.66, pz + 0.05), Vector3(ax + aw * 0.5, 2.6, pz - 0.1), 4, 0.42)
	_vine_canopy(mb, rng, Vector3(px0 + 0.3, 2.7, pz - 0.9), Vector3(ax + 0.6, 2.72, pz - 1.0), 2, 0.38)
	_vine_canopy(mb, rng, Vector3(px0 + 0.05, 0.45, pz + 0.05), Vector3(px0, 2.3, pz + 0.05), 3, 0.22)
	# Roof terrace: rug, little blue table and stools, a clothesline.
	_box(mb, Vector3(ax - 0.1, ty + 0.07, az + 0.15), Vector3(1.3, 0.02, 0.9), Pal.CLOTH_RED)
	_box(mb, Vector3(ax - 0.1, ty + 0.6, az + 0.15), Vector3(0.6, 0.06, 0.6), Pal.AEGEAN)
	mb.cyl(Vector3(ax - 0.1, ty + 0.06, az + 0.15), 0.52, 0.05, 0.05, 4, Pal.AEGEAN, false)
	for sx in [-0.55, 0.45]:
		mb.cyl(Vector3(ax - 0.1 + sx, ty + 0.06, az + 0.2), 0.4, 0.15, 0.14, 5, Pal.AEGEAN_LIGHT, true)
	for zz in [az - ad * 0.5 + 0.25, az + ad * 0.5 - 0.25]:
		_box(mb, Vector3(ax + aw * 0.5 - 0.3, ty + 0.75, zz), Vector3(0.07, 1.4, 0.07), Pal.WOOD)
	mb.limb(Vector3(ax + aw * 0.5 - 0.3, ty + 1.38, az - ad * 0.5 + 0.25), Vector3(ax + aw * 0.5 - 0.3, ty + 1.38, az + ad * 0.5 - 0.25), 0.015, 0.015, 3, Pal.CLOTH, false)
	var cloth_cols := [Pal.CLOTH, Pal.AEGEAN_LIGHT, Pal.CLOTH, Pal.CREST]
	for i in 3:
		var cz := az - 0.7 + float(i) * 0.65
		var cw := rng.randf_range(0.35, 0.5)
		mb.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(ax + aw * 0.5 - 0.3, ty + 1.38, cz)))
		mb.plate([Vector3(-cw * 0.5, 0, 0), Vector3(-cw * 0.5, -rng.randf_range(0.45, 0.6), 0), Vector3(cw * 0.5, -rng.randf_range(0.45, 0.6), 0), Vector3(cw * 0.5, 0, 0)], cloth_cols[(i + rng.randi() % 4) % 4])
		mb.pop()
	# Table and pots under the pergola.
	mb.cyl(Vector3(ax - 0.1, 0, pz - 0.55), 0.7, 0.06, 0.06, 5, Pal.WOOD_DARK)
	mb.cyl(Vector3(ax - 0.1, 0.7, pz - 0.55), 0.06, 0.4, 0.4, 7, Pal.MARBLE_SHADE, true)
	_pot_plant(mb, rng, Vector3(dx + 0.7, 0, hd + 0.35))
	_pot_plant(mb, rng, Vector3(ax + aw * 0.5 - 0.1, ty + 0.06, az - ad * 0.5 + 0.3), 0.8)
	_pot_plant(mb, rng, Vector3(ax - aw * 0.5 + 0.35, ty + 0.06, az - ad * 0.5 + 0.3), 0.7)
	return {"anchors": {"door": Vector3(dx, 0, hd + 0.95)}, "footprint": 3.2, "height": base + mh + 1.9}


## Chunky tiled gable roof with its ridge along X, sitting on walls of width `w` (X) whose top centre is
## `base`; `hd` = half the wall depth, `rise` = ridge height above the wall top. Also fills the gable ends.
static func _gable_roof(mb: MeshBuilder, base: Vector3, w: float, hd: float, rise: float, ov: float, gable_ov: float, wall_col: Color, col: Color = Pal.TERRACOTTA) -> void:
	var t := 0.17
	var theta := atan2(rise, hd)
	var ext := ov / cos(theta)
	var l := sqrt(hd * hd + rise * rise) + ext
	var rw := w + gable_ov * 2.0
	for sx in [-1.0, 1.0]:
		var x: float = sx * w * 0.5
		var a := base + Vector3(x, 0, hd * sx)
		var b := base + Vector3(x, 0, -hd * sx)
		mb.tri(a, b, base + Vector3(x, rise, 0), wall_col)
	var ribs := int(rw / 0.42)
	var step := rw / float(ribs)
	for side in [-1.0, 1.0]:
		var dir := Vector3(0, -sin(theta), side * cos(theta))
		var c := base + Vector3(0, rise, 0) + dir * (l * 0.5)
		mb.push(Transform3D(Basis(Vector3.RIGHT, theta * side), c))
		_box(mb, Vector3(0, t * 0.5, 0), Vector3(rw, t, l), Pal.TERRACOTTA_DARK, col)
		for i in ribs:
			_rib(mb, -rw * 0.5 + step * (float(i) + 0.5), t, -l * 0.5, l * 0.5 + 0.03, step * 0.3, 0.09, col.lightened(0.06))
		mb.pop()
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.25), base + Vector3(0, rise + t * 1.05, 0)))
	_box(mb, Vector3.ZERO, Vector3(rw + 0.06, 0.2, 0.2), Pal.TERRACOTTA_DARK)
	mb.pop()


## Roof-tile rib: a triangular prism lying along Z on the plane y = `y0` (half width `hw`, height `rh`).
static func _rib(mb: MeshBuilder, x: float, y0: float, z0: float, z1: float, hw: float, rh: float, col: Color) -> void:
	var a0 := Vector3(x - hw, y0, z0)
	var a1 := Vector3(x - hw, y0, z1)
	var b0 := Vector3(x + hw, y0, z0)
	var b1 := Vector3(x + hw, y0, z1)
	var t0 := Vector3(x, y0 + rh, z0)
	var t1 := Vector3(x, y0 + rh, z1)
	mb.quad(a0, a1, t1, t0, col)
	mb.quad(b0, t0, t1, b1, col.darkened(0.06))
	mb.tri(a1, b1, t1, col)
	mb.tri(b0, a0, t0, col)


## Starts a wall-local frame: +Z points out of the wall. Remember to mb.pop().
static func _on_wall(mb: MeshBuilder, p: Vector3, yaw: float) -> void:
	mb.push_at(p, yaw)


## Window on a +Z-facing wall at `p` (pane centre): frame, glowing pane, sill and open blue shutters.
static func _window(mb: MeshBuilder, p: Vector3, w: float, h: float, shutters: bool = true) -> void:
	_plaque(mb, p + Vector3(0, 0, 0.03), Vector3(w + 0.14, h + 0.14, 0.06), Pal.MARBLE_SHADE)
	_plaque(mb, p + Vector3(0, 0, 0.05), Vector3(w, h, 0.06), Pal.WINDOW)
	_plaque(mb, p + Vector3(0, -h * 0.5 - 0.06, 0.08), Vector3(w + 0.24, 0.07, 0.16), Pal.LIMESTONE)
	if shutters:
		for sx in [-1.0, 1.0]:
			_plaque(mb, p + Vector3(sx * (w * 0.5 + 0.2), 0, 0.05), Vector3(0.28, h + 0.06, 0.06), Pal.AEGEAN)


## Door on a +Z-facing wall, `p` = bottom centre on the wall surface.
static func _door(mb: MeshBuilder, p: Vector3, w: float, h: float, col: Color = Pal.AEGEAN) -> void:
	_plaque(mb, p + Vector3(0, h * 0.5 + 0.05, 0.03), Vector3(w + 0.2, h + 0.14, 0.06), Pal.MARBLE_SHADE)
	_plaque(mb, p + Vector3(0, h * 0.5, 0.06), Vector3(w, h, 0.06), col)
	_plaque(mb, p + Vector3(0, h * 0.62, 0.095), Vector3(w * 0.7, 0.06, 0.02), col.darkened(0.2))
	_plaque(mb, p + Vector3(w * 0.3, h * 0.48, 0.11), Vector3(0.06, 0.06, 0.04), Pal.BRONZE)


## Wall-mounted slab centred on `c`: front (+Z), top and sides only (the back sits in the wall).
static func _plaque(mb: MeshBuilder, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p0 := c + Vector3(-h.x, -h.y, -h.z)
	var p1 := c + Vector3(h.x, -h.y, -h.z)
	var p2 := c + Vector3(h.x, -h.y, h.z)
	var p3 := c + Vector3(-h.x, -h.y, h.z)
	var p4 := c + Vector3(-h.x, h.y, -h.z)
	var p5 := c + Vector3(h.x, h.y, -h.z)
	var p6 := c + Vector3(h.x, h.y, h.z)
	var p7 := c + Vector3(-h.x, h.y, h.z)
	mb.quad(p3, p2, p6, p7, col)
	mb.quad(p4, p7, p6, p5, col)
	mb.quad(p2, p1, p5, p6, col)
	mb.quad(p0, p3, p7, p4, col)


## Terracotta pot with flowering herbs.
static func _pot_plant(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, s: float = 1.0) -> void:
	ModelsNature.lathe(mb, p, ModelsNature._scaled([Vector2(0, 0), Vector2(0.14, 0), Vector2(0.2, 0.3), Vector2(0.24, 0.33), Vector2(0.17, 0.36), Vector2(0, 0.36)], s), 5, [Pal.TERRACOTTA, Pal.TERRACOTTA, Pal.TERRACOTTA_DARK, Pal.TERRACOTTA_DARK, Pal.WOOD_DARK])
	ModelsNature.blob(mb, rng, p + Vector3(0, 0.3 * s, 0), ModelsNature._scaled([Vector2(0.24, 0), Vector2(0.18, 0.24), Vector2(0, 0.34)], s), 5, 0.15, Pal.GRASS_DARK, Pal.CYPRESS)
	var col: Color = [Pal.POPPY, Pal.LAVENDER, Pal.CREST, Pal.DAISY][rng.randi() % 4]
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf()
		mb.cyl(p + Vector3(cos(a) * 0.12, 0.5, sin(a) * 0.12) * s, 0.12 * s, 0.09 * s, 0.0, 4, col, false, rng.randf())


## Wooden bench against a wall (seat along X).
static func _bench(mb: MeshBuilder, p: Vector3) -> void:
	_box(mb, p + Vector3(0, 0.42, 0), Vector3(1.2, 0.08, 0.36), Pal.WOOD_LIGHT)
	for sx in [-0.5, 0.5]:
		_box(mb, p + Vector3(sx, 0.2, 0), Vector3(0.08, 0.4, 0.3), Pal.WOOD)


## Chain of grapevine lumps from `a` to `b` (vine leaves with a few dark bunches hanging below), slightly drooping.
## (A vine arbour rather than bougainvillea, which only reached the Mediterranean in the 19th century.)
static func _vine_canopy(mb: MeshBuilder, rng: RandomNumberGenerator, a: Vector3, b: Vector3, n: int, r: float) -> void:
	var prof := [Vector2(0, -0.62), Vector2(0.78, -0.4), Vector2(1.0, 0.02), Vector2(0.7, 0.42), Vector2(0, 0.56)]
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a.lerp(b, t) + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.12, 0.12))
		var light := (i + rng.randi() % 3) % 3 != 0
		var rr := r * rng.randf_range(0.85, 1.15)
		ModelsNature.blob(mb, rng, p, ModelsNature._scaled(prof, rr), 5, 0.16, VINE_LEAF if light else VINE_LEAF_DARK, VINE_LEAF_DARK if light else Pal.CYPRESS, -0.3)
		# A bunch of grapes or two hanging under the leaves (only up on the arbour).
		if r >= 0.3:
			for k in 1 + rng.randi() % 2:
				var g := p + Vector3(rng.randf_range(-0.5, 0.5) * rr, -rr * 0.62 - 0.2, rng.randf_range(-0.4, 0.4) * rr)
				mb.cyl(g, 0.22, 0.0, 0.085, 5, GRAPES if k == 0 else GRAPES_DARK, false, rng.randf())


# --- farm ----------------------------------------------------------------------------------------------------

static func _farm(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	var half := 5.0
	# Low dry-stone border with a gate gap at the front.
	_rubble_wall(mb, rng, Vector3(-half, 0, -half), Vector3(half, 0, -half))
	_rubble_wall(mb, rng, Vector3(-half, 0, -half), Vector3(-half, 0, half))
	_rubble_wall(mb, rng, Vector3(half, 0, -half), Vector3(half, 0, half))
	_rubble_wall(mb, rng, Vector3(-half, 0, half), Vector3(-0.9, 0, half))
	_rubble_wall(mb, rng, Vector3(0.9, 0, half), Vector3(half, 0, half))
	for sx in [-1.0, 1.0]:
		_box(mb, Vector3(sx * 0.98, 0.3, half), Vector3(0.38, 1.0, 0.52), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	# Hut with an olive press in the back-left corner.
	var hx := -3.3
	var hz := -3.35
	_box(mb, Vector3(hx, 0.8, hz), Vector3(2.3, 2.2, 1.9), Pal.LIMESTONE, Pal.LIMESTONE)
	_gable_roof(mb, Vector3(hx, 1.9, hz), 2.3, 0.95, 0.6, 0.22, 0.16, Pal.LIMESTONE)
	_door(mb, Vector3(hx + 0.4, 0, hz + 0.95), 0.7, 1.4, Pal.WOOD)
	_wall_lantern(mb, Vector3(hx - 0.3, 1.55, hz + 0.95))
	_on_wall(mb, Vector3(hx + 1.15, 1.15, hz), PI * 0.5)
	_window(mb, Vector3.ZERO, 0.4, 0.4, false)
	mb.pop()
	# Olive press: round basin, upright millstone, wooden beam.
	var px := -1.2
	var pz := -3.4
	ModelsNature.lathe(mb, Vector3(px, -0.2, pz), [Vector2(0.85, 0), Vector2(0.85, 0.7), Vector2(0.7, 0.7), Vector2(0.7, 0.56), Vector2(0, 0.56)], 7, [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.LIMESTONE_DARK, PX.SOIL])
	mb.push(Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.BACK, PI * 0.5), Vector3(px + 0.3, 0.36 + 0.42, pz)))
	mb.cyl(Vector3(0, -0.12, 0), 0.24, 0.42, 0.42, 7, Pal.ROCK)
	mb.pop()
	mb.cyl(Vector3(px, 0.36, pz), 0.75, 0.07, 0.07, 5, Pal.WOOD_DARK, false)
	mb.limb(Vector3(px, 0.95, pz), Vector3(px + 1.3, 0.85, pz + 0.5), 0.06, 0.05, 4, Pal.WOOD)
	# Orchard: small olive trees in rows, each in its hoed basin.
	var spots: Array[Vector2] = []
	for row in 3:
		for col in 3:
			if row == 0 and col < 2:
				continue
			spots.append(Vector2(-2.6 + 2.6 * float(col), -2.4 + 2.5 * float(row)))
	if lv >= 2:
		spots.append(Vector2(-3.5, -0.3))
		spots.append(Vector2(3.6, -3.5))
	else:
		spots.remove_at(spots.size() - 1)
	for p in spots:
		var c := Vector3(p.x + rng.randf_range(-0.2, 0.2), 0, p.y + rng.randf_range(-0.2, 0.2))
		mb.disc(c + Vector3(0, 0.03, 0), 0.95, 6, PX.SOIL)
		mb.push_at(c, rng.randf() * TAU)
		ModelsNature.add_olive_tree(mb, rng, rng.randf_range(0.72, 0.8), 2)
		mb.pop()
	if lv >= 2:
		# Harvest: jars by the hut, baskets of olives, a ladder against a tree.
		for i in 2:
			mb.push_at(Vector3(hx + 1.5 + float(i) * 0.48, 0, hz + 1.35 + float(i) * 0.2), rng.randf() * TAU, Vector3.ONE * (1.0 if i == 0 else 0.82))
			ModelsNature.add_amphora(mb, rng, 1.0, 2)
			mb.pop()
		_basket(mb, rng, Vector3(1.35, 0, 3.55))
		_basket(mb, rng, Vector3(-1.75, 0, 2.15))
		mb.push(Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -0.32), Vector3(2.0, 0, 1.0)))
		for sx in [-0.2, 0.2]:
			_box(mb, Vector3(sx, 1.1, 0), Vector3(0.06, 2.2, 0.06), Pal.WOOD_LIGHT)
		for i in 4:
			_box(mb, Vector3(0, 0.4 + float(i) * 0.5, 0), Vector3(0.4, 0.05, 0.05), Pal.WOOD_LIGHT)
		mb.pop()
	return {"anchors": {"gate": Vector3(0, 0, half)}, "footprint": 4.6, "height": 3.0}


## Low rubble wall between two ground points (the farm border): a run of rough stones with uneven tops, sunk
## deep enough to sit on gently sloping ground.
static func _rubble_wall(mb: MeshBuilder, rng: RandomNumberGenerator, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	var yaw := atan2(d.x, d.z)
	mb.push(Transform3D(Basis(Vector3.UP, yaw), a))
	var z := 0.0
	var cols := [Pal.ROCK, Pal.LIMESTONE_DARK, PX.ROCK_MID, Pal.LIMESTONE_DARK]
	while z < l - 0.05:
		var sl := minf(rng.randf_range(0.8, 1.45), l - z)
		var h := rng.randf_range(0.42, 0.58)
		_box(mb, Vector3(rng.randf_range(-0.03, 0.03), h * 0.5 - 0.15, z + sl * 0.5), Vector3(0.5 * rng.randf_range(0.9, 1.08), h + 0.3, sl - 0.05), cols[rng.randi() % cols.size()], null, Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04), rng.randf_range(-0.06, 0.06)))
		z += sl
	mb.pop()


## Wicker basket full of olives.
static func _basket(mb: MeshBuilder, _rng: RandomNumberGenerator, p: Vector3) -> void:
	ModelsNature.lathe(mb, p, [Vector2(0, 0), Vector2(0.24, 0), Vector2(0.3, 0.3), Vector2(0.26, 0.3), Vector2(0.26, 0.22), Vector2(0, 0.25)], 6, [Pal.WOOD_LIGHT, Pal.WOOD_LIGHT, Pal.WOOD, Pal.WOOD, Pal.CYPRESS_DARK])


# --- dock ----------------------------------------------------------------------------------------------------

static func _dock(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	var length := 9.0 if lv == 1 else 12.0
	var w := 3.0
	var deck := 0.5
	# Stone abutment on the beach.
	_box(mb, Vector3(0, -0.15, -0.5), Vector3(w + 0.6, 1.2, 1.6), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	_box(mb, Vector3(0, -0.2, -1.3), Vector3(w + 0.2, 0.9, 0.8), Pal.ROCK, Pal.LIMESTONE_DARK)
	# Planks across, alternating tones.
	var n := int(length / 0.42)
	var pl := length / float(n)
	for i in n:
		var z := pl * (float(i) + 0.5)
		var col := Pal.WOOD_LIGHT if i % 3 != 1 else Pal.WOOD
		var jitter := rng.randf_range(-0.06, 0.06)
		_box(mb, Vector3(jitter, deck - 0.05, z), Vector3(w + rng.randf_range(-0.1, 0.12), 0.1, pl - 0.04), col)
	# Stringers and posts.
	for sx in [-1.0, 1.0]:
		_box(mb, Vector3(sx * (w * 0.5 - 0.3), deck - 0.18, length * 0.5), Vector3(0.2, 0.16, length), Pal.WOOD_DARK)
	var bays := int(ceil(length / 3.0))
	for i in bays + 1:
		var z := minf(float(i) * 3.0 + 0.2, length - 0.2)
		for sx in [-1.0, 1.0]:
			var tall := (i == bays) or (i % 2 == 1)
			var top := deck + (0.55 if tall else -0.1)
			mb.cyl(Vector3(sx * (w * 0.5 - 0.05), -1.4, z), top + 1.4, 0.15, 0.13, 6, Pal.WOOD_DARK, true)
			if tall:
				mb.cyl(Vector3(sx * (w * 0.5 - 0.05), top, z), 0.06, 0.16, 0.12, 6, Pal.WOOD)
			mb.cyl(Vector3(sx * (w * 0.5 - 0.05), -0.12, z), 0.18, 0.16, 0.16, 6, Pal.SAND_WET, false)
		# Cross bracing under the deck.
		_box(mb, Vector3(0, deck - 0.3, z), Vector3(w, 0.14, 0.14), Pal.WOOD_DARK)
	# Lantern post at the tip (lights up at night).
	var tip := length - 0.35
	mb.cyl(Vector3(w * 0.5 - 0.3, deck, tip), 1.7, 0.08, 0.07, 6, Pal.WOOD)
	_box(mb, Vector3(w * 0.5 - 0.3, deck + 1.78, tip), Vector3(0.26, 0.3, 0.26), Pal.WINDOW)
	mb.roof_pyramid(Vector3(w * 0.5 - 0.3, deck + 1.93, tip), 0.34, 0.34, 0.2, Pal.BRONZE)
	_box(mb, Vector3(w * 0.5 - 0.3, deck + 1.62, tip), Vector3(0.3, 0.06, 0.3), Pal.BRONZE)
	# Clutter: rope coil, crate, fish basket, amphora.
	mb.ring(Vector3(-w * 0.5 + 0.5, deck, 2.6), 0.26, 0.1, 0.1, 7, Pal.CLOTH)
	_crate(mb, rng, Vector3(-w * 0.5 + 0.55, deck, 4.4), 0.6)
	_basket(mb, rng, Vector3(-w * 0.5 + 0.45, deck, 5.3))
	mb.push_at(Vector3(w * 0.5 - 0.45, deck, 1.6), rng.randf() * TAU, Vector3.ONE * 0.85)
	ModelsNature.add_amphora(mb, rng, 1.0, 1)
	mb.pop()
	var anchors := {"boat_1": Vector3(w * 0.5 + 1.15, 0, 5.4), "end": Vector3(0, deck, length)}
	if lv >= 2:
		anchors["boat_2"] = Vector3(-w * 0.5 - 1.15, 0, 9.0)
		# Fish-drying rack: two A-frames with a pole and hanging fish, plus a net and stacked crates.
		var rz := 7.4
		for zz in [rz - 1.1, rz + 1.1]:
			for sx in [-1.0, 1.0]:
				mb.limb(Vector3(0.75 + sx * 0.35, deck, zz), Vector3(0.75, deck + 1.65, zz), 0.05, 0.04, 4, Pal.WOOD)
		mb.limb(Vector3(0.75, deck + 1.6, rz - 1.25), Vector3(0.75, deck + 1.6, rz + 1.25), 0.045, 0.045, 4, Pal.WOOD_LIGHT)
		for i in 6:
			var fz := rz - 0.85 + float(i) * 0.34
			mb.push(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(0.75, deck + 1.3, fz)))
			mb.plate([Vector3(0, 0.28, 0), Vector3(0.1, 0.1, 0), Vector3(0, -0.12, 0), Vector3(-0.1, 0.1, 0)], Pal.MARBLE_SHADE)
			mb.plate([Vector3(0, -0.1, 0), Vector3(0.09, -0.2, 0), Vector3(-0.09, -0.2, 0)], Pal.ROCK)
			mb.pop()
		ModelsNature.blob(mb, rng, Vector3(-0.75, deck - 0.02, 8.3), [Vector2(0.55, 0), Vector2(0.5, 0.16), Vector2(0.3, 0.32), Vector2(0, 0.38)], 6, 0.2, Pal.AEGEAN_LIGHT, Pal.AEGEAN, -0.2, Pal.AEGEAN_LIGHT.lightened(0.08), 0.9)
		for k in 4:
			var fa := TAU * float(k) / 4.0 + 0.4
			_box(mb, Vector3(-0.75 + cos(fa) * 0.42, deck + 0.18 + float(k % 2) * 0.08, 8.3 + sin(fa) * 0.42), Vector3(0.12, 0.08, 0.12), Pal.CLOTH, null, Vector3(0.2, fa, 0.3))
		_crate(mb, rng, Vector3(-w * 0.5 + 0.5, deck, 10.2), 0.62)
		_crate(mb, rng, Vector3(-w * 0.5 + 0.55, deck + 0.62, 10.2), 0.5)
		_crate(mb, rng, Vector3(-w * 0.5 + 1.2, deck, 10.4), 0.55)
		mb.ring(Vector3(w * 0.5 - 0.5, deck, 10.8), 0.26, 0.1, 0.1, 7, Pal.CLOTH)
	return {"anchors": anchors, "footprint": 1.6, "height": deck + 2.1}


## Wooden crate with slats, sitting on `p`.
static func _crate(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, s: float) -> void:
	var yaw := rng.randf_range(-0.3, 0.3)
	mb.push_at(p, yaw)
	_box(mb, Vector3(0, s * 0.5, 0), Vector3(s, s, s), Pal.WOOD_LIGHT, Pal.WOOD)
	_box(mb, Vector3(0, s * 0.5, 0), Vector3(s + 0.03, s * 0.16, s + 0.03), Pal.WOOD)
	_box(mb, Vector3(0, s - 0.03, 0), Vector3(s + 0.04, 0.07, s + 0.04), Pal.WOOD)
	mb.pop()


## Small fishing boat for the dock (origin at the waterline, bow towards +Z): hull, mast with a furled lateen
## sail and a pennant, nets and a basket.
static func boat(seed_value: int) -> ArrayMesh:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = VARY
	var rng := ModelsNature.make_rng(seed_value, 5)
	var length := 3.8
	mb.push_at(Vector3(0, -0.28, 0))
	ModelsNature.add_boat_hull(mb, rng, length, 1.4, 0.66)
	mb.pop()
	var mz := 0.55
	mb.limb(Vector3(0, -0.1, mz), Vector3(0, 3.1, mz), 0.06, 0.045, 5, Pal.WOOD)
	_box(mb, Vector3(0, 3.12, mz), Vector3(0.1, 0.08, 0.1), Pal.WOOD_DARK)
	mb.plate([Vector3(0, 3.1, mz), Vector3(0, 2.86, mz), Vector3(0.0, 2.98, mz - 0.55)], Pal.CREST)
	# Furled lateen yard: long spar with the sail bundled along it.
	var y0 := Vector3(0.05, 0.55, -1.35)
	var y1 := Vector3(0.05, 2.95, mz + 1.1)
	mb.limb(y0, y1, 0.04, 0.03, 4, Pal.WOOD_LIGHT)
	var m0 := y0.lerp(y1, 0.12)
	var m1 := y0.lerp(y1, 0.5)
	var m2 := y0.lerp(y1, 0.88)
	mb.limb(m0 + Vector3(0.04, 0, 0), m1 + Vector3(0.06, -0.02, 0), 0.06, 0.13, 5, Pal.CLOTH, false)
	mb.limb(m1 + Vector3(0.06, -0.02, 0), m2 + Vector3(0.04, 0, 0), 0.13, 0.05, 5, Pal.CLOTH, false)
	# Nets heaped in the stern and a fish basket.
	ModelsNature.blob(mb, rng, Vector3(0, 0.1, -1.05), [Vector2(0.42, 0), Vector2(0.38, 0.12), Vector2(0.15, 0.22), Vector2(0, 0.23)], 6, 0.2, Pal.AEGEAN_LIGHT, Pal.AEGEAN, -0.3)
	_basket(mb, rng, Vector3(0.15, 0.08, -0.25))
	return mb.commit()


# --- tower ---------------------------------------------------------------------------------------------------

static func _tower(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	var floor_y := 0.0
	var top_y := 0.0
	var rot := PI / 8.0
	match lv:
		1:
			var h := 3.75
			var prof := [Vector2(1.5, -0.3), Vector2(1.5, 0.25), Vector2(1.4, 0.25), Vector2(1.3, h)]
			ModelsNature.lathe(mb, Vector3.ZERO, prof, 8, [Pal.ROCK, Pal.LIMESTONE_DARK, Pal.LIMESTONE_DARK], rot)
			_stones(mb, rng, 1.4, 1.3, 0.4, h - 0.2, 14)
			# Corbel beams and the plank deck.
			for i in 8:
				var a := TAU * float(i) / 8.0 + rot + PI / 8.0
				var d := Vector3(cos(a), 0, sin(a))
				mb.push(Transform3D(Basis(Vector3.UP, -a), d * 1.35 + Vector3(0, h - 0.14, 0)))
				_box(mb, Vector3.ZERO, Vector3(0.5, 0.18, 0.16), Pal.WOOD_DARK)
				mb.pop()
			ModelsNature.lathe(mb, Vector3(0, h - 0.05, 0), [Vector2(0, 0), Vector2(1.72, 0), Vector2(1.72, 0.2), Vector2(0, 0.2)], 8, [Pal.WOOD, Pal.WOOD, Pal.WOOD_LIGHT], rot)
			floor_y = h + 0.15
			for k in 4:
				var zz := -1.05 + 0.7 * float(k)
				var half_chord := 1.59 - maxf(0.0, absf(zz) - 0.66)
				_box(mb, Vector3(0, floor_y + 0.005, zz), Vector3(half_chord * 2.0 - 0.1, 0.02, 0.05), Pal.WOOD_DARK)
			_wood_rail(mb, Vector3(0, floor_y, 0), 1.62, 0.9, 8, rot)
			# A barrel and a basket of arrows against the rail.
			ModelsNature.lathe(mb, Vector3(-0.95, floor_y, -0.8), [Vector2(0, 0), Vector2(0.24, 0), Vector2(0.28, 0.3), Vector2(0.24, 0.6), Vector2(0, 0.6)], 6, [Pal.WOOD_DARK, Pal.WOOD, Pal.WOOD, Pal.WOOD_LIGHT])
			_basket(mb, rng, Vector3(0.95, floor_y, -0.85))
			for k in 4:
				var q := Vector3(0.95 + rng.randf_range(-0.1, 0.1), floor_y + 0.1, -0.85 + rng.randf_range(-0.1, 0.1))
				mb.limb(q, q + Vector3(rng.randf_range(-0.12, 0.12), 0.75, rng.randf_range(-0.12, 0.12)), 0.018, 0.018, 3, Pal.WOOD_LIGHT, false)
			_door(mb, Vector3(0, 0.25, 1.4 * cos(PI / 8.0) - 0.02), 0.72, 1.45, Pal.WOOD)
			var lp := Vector3(cos(rot) * 1.62, floor_y, sin(rot) * 1.62)
			mb.cyl(lp, 1.45, 0.05, 0.04, 4, Pal.WOOD_DARK, false)
			mb.limb(lp + Vector3(0, 1.4, 0), lp + Vector3(0.3, 1.4, 0.12), 0.03, 0.03, 3, Pal.WOOD_DARK, false)
			_box(mb, lp + Vector3(0.32, 1.2, 0.13), Vector3(0.18, 0.24, 0.18), Pal.WINDOW)
			mb.roof_pyramid(lp + Vector3(0.32, 1.32, 0.13), 0.24, 0.24, 0.1, Pal.BRONZE)
			# Ladder up the back.
			mb.push_at(Vector3(0, 0, -1.42), PI)
			mb.push(Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(0, 0, 0.1)))
			for sx in [-0.24, 0.24]:
				_box(mb, Vector3(sx, (h + 0.3) * 0.5, 0), Vector3(0.07, h + 0.3, 0.07), Pal.WOOD_LIGHT)
			for i in 8:
				_box(mb, Vector3(0, 0.35 + float(i) * 0.45, 0), Vector3(0.5, 0.05, 0.06), Pal.WOOD_LIGHT)
			mb.pop()
			mb.pop()
			top_y = floor_y + 0.95
		2:
			var h := 5.4
			var prof := [
				Vector2(1.62, -0.3), Vector2(1.62, 0.3), Vector2(1.5, 0.3), Vector2(1.36, h - 0.3), Vector2(1.66, h),
				Vector2(1.66, h + 0.62), Vector2(1.46, h + 0.62), Vector2(1.46, h + 0.1), Vector2(0, h + 0.1),
			]
			var cols := [Pal.ROCK, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.WOOD]
			ModelsNature.lathe(mb, Vector3.ZERO, prof, 8, cols, rot)
			_stones(mb, rng, 1.5, 1.36, 0.5, h - 0.6, 18)
			_band(mb, Vector3(0, 2.7, 0), 1.43, 0.14, 8, Pal.LIMESTONE, rot)
			floor_y = h + 0.1
			_merlons(mb, Vector3(0, h + 0.62, 0), 1.56, 8, 0.48, 0.24, Pal.LIMESTONE_DARK, Pal.LIMESTONE, rot)
			_door(mb, Vector3(0, 0.3, 1.5 * cos(PI / 8.0) - 0.02), 0.8, 1.6, Pal.WOOD)
			for k in [[PI * 0.5, 3.3], [-PI * 0.5, 2.6], [PI, 3.6]]:
				_slit(mb, Vector3.ZERO, k[0], k[1], (1.36 + 0.14 * (1.0 - k[1] / h)) * cos(PI / 8.0), 0.22, 0.65)
			_banner(mb, Vector3(0, h + 0.45, 1.66 * cos(PI / 8.0) + 0.02), 0.0, 0.85, 2.3, Pal.AEGEAN, Pal.MARBLE, Pal.BRONZE)
			top_y = h + 1.1
		_:
			var h := 6.8
			var prof := [
				Vector2(1.75, -0.3), Vector2(1.75, 0.45), Vector2(1.58, 0.45), Vector2(1.42, h - 0.32), Vector2(1.72, h),
				Vector2(1.72, h + 0.66), Vector2(1.52, h + 0.66), Vector2(1.52, h + 0.1), Vector2(0, h + 0.1),
			]
			var cols := [Pal.LIMESTONE_DARK, Pal.LIMESTONE, Pal.MARBLE, Pal.LIMESTONE, Pal.BRONZE, Pal.MARBLE_SHADE, Pal.MARBLE, Pal.LIMESTONE]
			ModelsNature.lathe(mb, Vector3.ZERO, prof, 8, cols, rot)
			_band(mb, Vector3(0, 0.45, 0), 1.6, 0.12, 8, Pal.BRONZE, rot)
			_band(mb, Vector3(0, 3.5, 0), 1.5, 0.14, 8, Pal.BRONZE, rot)
			_band(mb, Vector3(0, h - 0.5, 0), 1.45, 0.1, 8, Pal.AEGEAN, rot)
			floor_y = h + 0.1
			_merlons(mb, Vector3(0, h + 0.66, 0), 1.62, 8, 0.5, 0.26, Pal.MARBLE, Pal.MARBLE_SHADE, rot, Pal.BRONZE)
			_door(mb, Vector3(0, 0.45, 1.58 * cos(PI / 8.0) - 0.02), 0.85, 1.7, Pal.AEGEAN)
			_box(mb, Vector3(0, 2.32, 1.58 * cos(PI / 8.0) + 0.03), Vector3(1.15, 0.14, 0.14), Pal.BRONZE)
			for k in [[PI * 0.5, 4.6], [-PI * 0.5, 4.2], [PI, 2.8], [PI, 5.0], [0.0, 4.6]]:
				_slit(mb, Vector3.ZERO, k[0], k[1], (1.42 + 0.16 * (1.0 - k[1] / h)) * cos(PI / 8.0), 0.24, 0.7)
			var face := 1.72 * cos(PI / 8.0) + 0.02
			for sgn in [-1.0, 1.0]:
				var a: float = sgn * PI * 0.25
				_banner(mb, Vector3(sin(a) * face, h + 0.45, cos(a) * face), a, 0.75, 2.6, Pal.AEGEAN, Pal.GOLD, Pal.BRONZE)
			top_y = h + 1.25
	return {
		"anchors": {"archer": Vector3(0, floor_y, 0), "muzzle": Vector3(0, floor_y + 1.35, 0)},
		"footprint": 1.6 if lv == 1 else 1.7,
		"height": top_y,
	}


## Rough stones studding a tapering prism tower (radius r0 at y0 .. r1 at y1).
static func _stones(mb: MeshBuilder, rng: RandomNumberGenerator, r0: float, r1: float, y0: float, y1: float, n: int) -> void:
	for i in n:
		var y := rng.randf_range(y0, y1)
		var k := (y - y0) / (y1 - y0)
		var r := lerpf(r0, r1, k) * cos(PI / 8.0)
		var face := rng.randi() % 8
		var a := TAU * float(face) / 8.0 + rng.randf_range(-0.22, 0.22)
		mb.push(Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * r + Vector3(0, y, 0)))
		_box(mb, Vector3.ZERO, Vector3(rng.randf_range(0.3, 0.55), rng.randf_range(0.18, 0.28), 0.1), [Pal.ROCK, PX.ROCK_MID, Pal.LIMESTONE][rng.randi() % 3])
		mb.pop()


## Merlons standing on a parapet ring (one per face of an n-gon of apothem `r`).
static func _merlons(mb: MeshBuilder, base: Vector3, r: float, n: int, h: float, thick: float, col: Color, top: Color, rot: float, cap: Variant = null) -> void:
	for i in n:
		var a := rot + TAU * (float(i) + 0.5) / float(n)
		var d := Vector3(cos(a), 0, sin(a))
		var wdt := 2.0 * r * tan(PI / float(n)) * 0.55
		mb.push(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), base + d * (r - thick * 0.5)))
		_box(mb, Vector3(0, h * 0.5, 0), Vector3(wdt, h, thick), col, top)
		if cap != null:
			_box(mb, Vector3(0, h + 0.04, 0), Vector3(wdt + 0.06, 0.08, thick + 0.06), cap)
		mb.pop()


## Wooden railing around an n-gon deck.
static func _wood_rail(mb: MeshBuilder, base: Vector3, r: float, h: float, n: int, rot: float) -> void:
	var pts: Array[Vector3] = []
	for i in n:
		var a := rot + TAU * float(i) / float(n)
		pts.append(base + Vector3(cos(a) * r, 0, sin(a) * r))
	for i in n:
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[(i + 1) % n]
		mb.cyl(p, h + 0.08, 0.07, 0.06, 5, Pal.WOOD_DARK, true)
		mb.limb(p + Vector3(0, h, 0), q + Vector3(0, h, 0), 0.05, 0.05, 4, Pal.WOOD, false)
		mb.limb(p + Vector3(0, h * 0.5, 0), q + Vector3(0, h * 0.5, 0), 0.04, 0.04, 4, Pal.WOOD, false)


## Hanging banner: a bronze rod across the top, cloth hanging down with a swallowtail and an emblem disc.
## `p` = top centre (on the wall surface), facing angle `a` (0 = +Z).
static func _banner(mb: MeshBuilder, p: Vector3, a: float, w: float, h: float, col: Color, emblem: Color, rod: Color) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, a), p))
	_box(mb, Vector3(0, 0.05, 0.04), Vector3(w + 0.26, 0.08, 0.08), rod)
	for sx in [-1.0, 1.0]:
		_box(mb, Vector3(sx * (w * 0.5 + 0.13), 0.05, 0.04), Vector3(0.1, 0.14, 0.14), rod)
	var hw := w * 0.5
	mb.plate([Vector3(-hw, 0, 0.06), Vector3(-hw, -h, 0.06), Vector3(0, -h + 0.32, 0.06), Vector3(hw, -h, 0.06), Vector3(hw, 0, 0.06)], col, false)
	mb.plate([Vector3(-hw, 0, 0.02), Vector3(hw, 0, 0.02), Vector3(hw, -h, 0.02), Vector3(0, -h + 0.32, 0.02), Vector3(-hw, -h, 0.02)], col.darkened(0.2), false)
	# Trim band and emblem.
	_box(mb, Vector3(0, -0.22, 0.07), Vector3(w, 0.07, 0.02), emblem)
	mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -h * 0.45, 0.07)))
	mb.cyl(Vector3.ZERO, 0.02, w * 0.26, w * 0.26, 6, emblem, false)
	mb.disc(Vector3(0, 0.02, 0), w * 0.26, 6, emblem)
	mb.pop()
	mb.pop()


# --- wall ----------------------------------------------------------------------------------------------------

static func _wall(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	var half := 4.0
	if lv == 1:
		# Palisade of sharpened stakes, lashed to two rails on the inner (+Z) side and propped by struts.
		var x := -half + 0.15
		var i := 0
		while x <= half - 0.12:
			var r := rng.randf_range(0.13, 0.16)
			var h := rng.randf_range(1.85, 2.15)
			var lean := Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.05, 0.02))
			mb.push(Transform3D(Basis.from_euler(lean), Vector3(x, 0, rng.randf_range(-0.04, 0.04))))
			mb.cyl(Vector3(0, -0.3, 0), h + 0.3, r, r * 0.92, 6, Pal.WOOD if i % 3 != 1 else Pal.WOOD_DARK, false, rng.randf())
			mb.cyl(Vector3(0, h, 0), 0.34, r * 0.92, 0.0, 6, Pal.WOOD_LIGHT, false, rng.randf())
			mb.pop()
			x += r * 2.0 + 0.01
			i += 1
		for y in [0.55, 1.45]:
			mb.limb(Vector3(-half, y, 0.2), Vector3(half, y + rng.randf_range(-0.06, 0.06), 0.2), 0.09, 0.09, 6, Pal.WOOD_DARK)
		for k in 3:
			var sx := -2.7 + 2.7 * float(k)
			mb.limb(Vector3(sx, 0, 1.25), Vector3(sx + 0.1, 1.5, 0.28), 0.08, 0.07, 5, Pal.WOOD_DARK)
			# rope lashings
			for y in [0.55, 1.45]:
				_box(mb, Vector3(sx, y, 0.2), Vector3(0.1, 0.22, 0.24), Pal.CLOTH)
		# Spikes angled out towards the enemy side.
		for k in 5:
			var sx := -3.2 + 1.6 * float(k) + rng.randf_range(-0.2, 0.2)
			mb.limb(Vector3(sx, 0.0, -0.3), Vector3(sx + rng.randf_range(-0.15, 0.15), 0.85, -1.05), 0.08, 0.0, 5, Pal.WOOD_LIGHT, false)
		return {"anchors": {"left": Vector3(-half, 0, 0), "right": Vector3(half, 0, 0)}, "footprint": 0.6, "height": 2.4}
	# Level 2: limestone curtain wall with crenellations, end piers and rubble at the foot.
	var h := 2.15
	var t := 0.95
	var courses := 4
	for c in courses:
		var y0 := -0.3 + float(c) * (h + 0.3) / float(courses)
		var ch := (h + 0.3) / float(courses)
		var x := -half + 0.45 + (0.0 if c % 2 == 0 else -0.35)
		while x < half - 0.45:
			var x0 := maxf(x, -half + 0.45)
			var bl := rng.randf_range(0.8, 1.3)
			var x1 := minf(x + bl, half - 0.45)
			var col: Color = [Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.LIMESTONE][rng.randi() % 3] if c > 0 else Pal.LIMESTONE_DARK
			_box(mb, Vector3((x0 + x1) * 0.5, y0 + ch * 0.5, 0), Vector3(x1 - x0 - 0.04, ch - 0.035, t - float(c) * 0.03), col, Pal.LIMESTONE)
			x = x1
	# Walkway and merlons along both faces (taller on the outside, -Z).
	_box(mb, Vector3(0, h + 0.06, 0), Vector3(2.0 * half - 0.85, 0.12, t + 0.1), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	var m := 6
	for k in m:
		var mx := -half + 0.95 + (2.0 * half - 1.9) * float(k) / float(m - 1)
		_box(mb, Vector3(mx, h + 0.5, -t * 0.5 + 0.14), Vector3(0.62, 0.78, 0.28), Pal.LIMESTONE, Pal.MARBLE_SHADE)
	_box(mb, Vector3(0, h + 0.27, t * 0.5 - 0.1), Vector3(2.0 * half - 0.9, 0.32, 0.2), Pal.LIMESTONE, Pal.MARBLE_SHADE)
	# End piers.
	for sx in [-1.0, 1.0]:
		var px: float = sx * (half - 0.45)
		_box(mb, Vector3(px, (h + 1.0 - 0.3) * 0.5 - 0.3 + 0.15, 0), Vector3(0.9, h + 1.0 + 0.3, t + 0.3), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
		_box(mb, Vector3(px, h + 0.92, 0), Vector3(1.04, 0.14, t + 0.44), Pal.MARBLE_SHADE)
		mb.roof_pyramid(Vector3(px, h + 0.99, 0), 0.8, t + 0.2, 0.32, Pal.LIMESTONE)
	# Rubble at the foot (both sides).
	for k in 9:
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := Vector3(rng.randf_range(-half + 0.8, half - 0.8), -0.05, side * (t * 0.5 + rng.randf_range(0.15, 0.45)))
		ModelsNature.chunk(mb, rng, p, rng.randf_range(0.14, 0.26), rng.randf_range(0.14, 0.24), 5, Pal.ROCK, Pal.ROCK_DARK, Pal.LIMESTONE_DARK)
	return {"anchors": {"left": Vector3(-half, 0, 0), "right": Vector3(half, 0, 0)}, "footprint": 0.8, "height": h + 1.3}


# --- barracks ------------------------------------------------------------------------------------------------

static func _barracks(mb: MeshBuilder, rng: RandomNumberGenerator, lv: int) -> Dictionary:
	var big := lv >= 2
	var w := 5.0 if not big else 6.4
	var d := 4.2 if not big else 5.0
	var cols_n := 4 if not big else 6
	var hd := d * 0.5
	var col_h := 2.35 if not big else 2.6
	var porch := 1.35
	# Two-step stylobate.
	_box(mb, Vector3(0, 0.0, 0), Vector3(w + 0.6, 0.36, d + 0.6), Pal.LIMESTONE_DARK, Pal.LIMESTONE)
	_box(mb, Vector3(0, 0.27, 0), Vector3(w + 0.2, 0.18, d + 0.2), Pal.LIMESTONE, Pal.MARBLE_SHADE)
	var base := 0.36
	# Cella.
	var cella_d := d - porch
	var cz := -hd + cella_d * 0.5
	_box(mb, Vector3(0, base + col_h * 0.5, cz), Vector3(w - 0.3, col_h, cella_d), Pal.MARBLE)
	_door(mb, Vector3(0, base, cz + cella_d * 0.5), 1.0, 1.75, Pal.WOOD)
	for sx in [-1.0, 1.0]:
		_window(mb, Vector3(sx * (w * 0.5 - 0.95), base + 1.35, cz + cella_d * 0.5), 0.5, 0.55, false)
	for sx in [-1.0, 1.0]:
		_on_wall(mb, Vector3(sx * (w - 0.3) * 0.5, base + 1.35, cz), sx * PI * 0.5)
		_window(mb, Vector3.ZERO, 0.5, 0.55, false)
		mb.pop()
	# Back wall (often the side the camera sees): windows and hoplite shields hung between them.
	_on_wall(mb, Vector3(0, base + 1.35, -hd), PI)
	for sx in [-1.0, 1.0]:
		_window(mb, Vector3(sx * w * 0.3, 0, 0), 0.5, 0.6, false)
	var shield_x := [0.0] if not big else [-0.55, 0.55]
	for k in shield_x.size():
		var sxx: float = shield_x[k]
		mb.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sxx, 0.15, 0.02)))
		mb.cyl(Vector3.ZERO, 0.06, 0.38, 0.36, 8, Pal.BRONZE, false)
		mb.cyl(Vector3(0, 0.06, 0), 0.04, 0.36, 0.18, 8, [Pal.CREST, Pal.AEGEAN][k % 2], false)
		mb.disc(Vector3(0, 0.1, 0), 0.18, 8, Pal.BRONZE)
		mb.pop()
	mb.pop()
	# Porch columns.
	var col_z := hd - 0.3
	for i in cols_n:
		var x := -w * 0.5 + 0.38 + (w - 0.76) * float(i) / float(cols_n - 1)
		_column(mb, Vector3(x, base, col_z), col_h, 0.19)
	# Entablature: architrave, painted frieze, cornice.
	var ey := base + col_h
	_box(mb, Vector3(0, ey + 0.13, 0), Vector3(w, 0.26, d), Pal.MARBLE_SHADE)
	_box(mb, Vector3(0, ey + 0.38, 0), Vector3(w + 0.02, 0.24, d + 0.02), Pal.CLOTH_RED)
	for i in int(w / 0.55):
		var x := -w * 0.5 + 0.275 + 0.55 * float(i)
		_box(mb, Vector3(x, ey + 0.38, hd + 0.02), Vector3(0.16, 0.24, 0.04), Pal.AEGEAN)
	_box(mb, Vector3(0, ey + 0.56, 0), Vector3(w + 0.24, 0.12, d + 0.24), Pal.MARBLE)
	# Roof: ridge along Z so the pediment faces the front.
	var ry := ey + 0.62
	mb.push_at(Vector3(0, ry, 0), PI * 0.5)
	_gable_roof(mb, Vector3.ZERO, d + 0.24, (w + 0.24) * 0.5, 1.0 if not big else 1.15, 0.22, 0.12, Pal.MARBLE)
	mb.pop()
	# Bronze shield in the pediment.
	_disc_on_wall(mb, Vector3(0, ry + 0.42, hd + 0.13), 0.0, 0.3, Pal.BRONZE, Pal.BRONZE_DARK)
	# Acroteria.
	for sx in [-1.0, 1.0]:
		mb.cyl(Vector3(sx * (w * 0.5 + 0.05), ry, hd + 0.12), 0.32, 0.11, 0.0, 4, Pal.BRONZE, false)
	# Banners.
	var banner_x := [0.0] if not big else [-1.15, 1.15]
	for bx in banner_x:
		_banner(mb, Vector3(bx, ey - 0.05, col_z + 0.1), 0.0, 0.62, 1.6, Pal.CREST, Pal.GOLD, Pal.BRONZE)
	# Fire bowls flanking the approach (they light up at night).
	for sx in [-1.0, 1.0]:
		_fire_bowl(mb, Vector3(sx * (w * 0.5 + 0.15), 0, hd + 0.75))
	# Weapon rack with spears and round shields on the right; lvl2 adds a second one on the left.
	_weapon_rack(mb, rng, Vector3(w * 0.5 + 0.55, 0, 0.2), -PI * 0.5)
	if big:
		_weapon_rack(mb, rng, Vector3(-w * 0.5 - 0.55, 0, -0.4), PI * 0.5)
		# Training post with a shield (no face) and a crate of javelins.
		mb.cyl(Vector3(2.0, 0, hd + 1.9), 1.7, 0.1, 0.09, 6, Pal.WOOD)
		_box(mb, Vector3(2.0, 1.25, hd + 1.9), Vector3(0.9, 0.1, 0.1), Pal.WOOD)
		_disc_on_wall(mb, Vector3(2.0, 1.0, hd + 2.0), 0.0, 0.34, Pal.AEGEAN, Pal.BRONZE)
		_crate(mb, rng, Vector3(-2.2, 0, hd + 1.4), 0.6)
		for k in 4:
			mb.limb(Vector3(-2.35 + float(k) * 0.1, 0.4, hd + 1.35), Vector3(-2.4 + float(k) * 0.12, 1.55, hd + 1.25 + float(k % 2) * 0.1), 0.025, 0.02, 4, Pal.WOOD_LIGHT, false)
	var front := hd + 0.3
	return {
		"anchors": {"rally": Vector3(0, 0, front + 3.6), "door": Vector3(0, 0, front + 0.6)},
		"footprint": 2.9 if not big else 3.5,
		"height": ry + (1.15 if big else 1.0) + 0.25,
	}


## Doric column: base slab, octagonal shaft, capital.
static func _column(mb: MeshBuilder, base: Vector3, h: float, r: float) -> void:
	_box(mb, base + Vector3(0, 0.06, 0), Vector3(r * 2.8, 0.12, r * 2.8), Pal.MARBLE_SHADE)
	mb.cyl(base + Vector3(0, 0.12, 0), h - 0.4, r, r * 0.86, 7, Pal.MARBLE, false)
	mb.cyl(base + Vector3(0, h - 0.28, 0), 0.12, r * 0.86, r * 1.25, 7, Pal.MARBLE, false)
	_box(mb, base + Vector3(0, h - 0.08, 0), Vector3(r * 2.9, 0.16, r * 2.9), Pal.MARBLE_SHADE, Pal.MARBLE)


## A-frame weapon rack: spears leaning on a rail and two round shields at its foot. Faces +Z after `yaw`.
static func _weapon_rack(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, yaw: float) -> void:
	mb.push_at(p, yaw)
	for sx in [-0.65, 0.65]:
		mb.limb(Vector3(sx, 0, -0.25), Vector3(sx, 1.3, 0), 0.05, 0.045, 4, Pal.WOOD_DARK, false)
		mb.limb(Vector3(sx, 0, 0.25), Vector3(sx, 1.3, 0), 0.05, 0.045, 4, Pal.WOOD_DARK, false)
	mb.limb(Vector3(-0.8, 1.2, 0), Vector3(0.8, 1.2, 0), 0.04, 0.04, 4, Pal.WOOD, false)
	mb.limb(Vector3(-0.8, 0.35, 0), Vector3(0.8, 0.35, 0), 0.04, 0.04, 4, Pal.WOOD, false)
	for i in 4:
		var x := -0.5 + float(i) * 0.33
		var a := Vector3(x, 0, 0.22)
		var b := Vector3(x + rng.randf_range(-0.05, 0.05), 2.3, -0.08)
		mb.limb(a, b, 0.025, 0.025, 4, Pal.WOOD_LIGHT, false)
		mb.limb(b, b + (b - a).normalized() * 0.28, 0.05, 0.0, 4, Pal.BRONZE, false)
	var shield_cols := [Pal.CREST, Pal.AEGEAN, Pal.BRONZE]
	for i in 2:
		var sp := Vector3(-0.36 + float(i) * 0.75, 0.42, 0.42)
		mb.push(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)) * Basis(Vector3.RIGHT, PI * 0.5 - 0.25), sp))
		mb.cyl(Vector3.ZERO, 0.06, 0.4, 0.38, 8, Pal.BRONZE, false)
		mb.cyl(Vector3(0, 0.06, 0), 0.04, 0.38, 0.2, 8, shield_cols[(i + rng.randi() % 3) % 3], false)
		mb.disc(Vector3(0, 0.1, 0), 0.2, 8, Pal.BRONZE)
		mb.pop()
	mb.pop()


# --- spot markers and rubble -------------------------------------------------------------------------------

## Empty build spot: a low outline of flat stones in the shape of the future building (≤ 0.15 m tall) and a
## small wooden survey stake with a blue ribbon.
static func spot_marker(type: String, seed_value: int) -> ArrayMesh:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = VARY
	var rng := ModelsNature.make_rng(seed_value, 9)
	var pts: Array[Vector3] = []
	var corners: Array[Vector3] = []
	var stake := Vector3.ZERO
	match type:
		"tower":
			for i in 10:
				var a := TAU * float(i) / 10.0
				pts.append(Vector3(cos(a) * 1.55, 0, sin(a) * 1.55))
			stake = Vector3(1.4, 0, 1.4)
		"wall":
			for i in 12:
				pts.append(Vector3(-3.85 + 7.7 * float(i) / 11.0, 0, -0.35 if i % 2 == 0 else 0.35))
			stake = Vector3(4.2, 0, 0.6)
		"dock":
			for i in 5:
				pts.append(Vector3(-1.5, 0, -1.0 + float(i) * 0.5))
				pts.append(Vector3(1.5, 0, -1.0 + float(i) * 0.5))
			stake = Vector3(1.9, 0, -1.2)
		"farm":
			pts = _rect_pts(9.6, 9.6, 1.6)
			corners = _rect_corners(9.6, 9.6)
			stake = Vector3(5.3, 0, 4.4)
		"pharos":
			pts = _rect_pts(6.8, 6.8, 1.1)
			corners = _rect_corners(6.8, 6.8)
			stake = Vector3(3.9, 0, 3.2)
		"barracks":
			pts = _rect_pts(5.4, 4.6, 0.9)
			corners = _rect_corners(5.4, 4.6)
			stake = Vector3(3.1, 0, 2.0)
		_:
			pts = _rect_pts(4.4, 3.8, 0.7)
			corners = _rect_corners(4.4, 3.8)
			stake = Vector3(2.6, 0, 1.6)
	var cols := [Pal.LIMESTONE, Pal.LIMESTONE_DARK, Pal.ROCK, Pal.MARBLE_SHADE]
	if corners.size() > 0:
		for c in corners:
			box_corner(mb, rng, c)
	for p in pts:
		var r := rng.randf_range(0.15, 0.22)
		var prof := [Vector2(r, -0.06), Vector2(r * 0.8, rng.randf_range(0.06, 0.09)), Vector2(0, rng.randf_range(0.08, 0.11))]
		ModelsNature.blob(mb, rng, p + Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05)), prof, 4, 0.18, cols[rng.randi() % cols.size()], Pal.ROCK_DARK, -0.6)
	# Survey stake with a ribbon.
	mb.push_at(stake, rng.randf() * TAU)
	mb.cyl(Vector3(0, -0.2, 0), 0.95, 0.05, 0.04, 4, Pal.WOOD_LIGHT, false, PI * 0.25)
	mb.cyl(Vector3(0, 0.75, 0), 0.1, 0.045, 0.0, 4, Pal.WOOD, false, PI * 0.25)
	mb.plate([Vector3(0.03, 0.72, 0), Vector3(0.03, 0.58, 0), Vector3(0.38, 0.6, 0.06), Vector3(0.3, 0.66, 0.03), Vector3(0.4, 0.73, 0.06)], Pal.AEGEAN)
	mb.pop()
	return mb.commit()


static func _rect_corners(w: float, d: float) -> Array[Vector3]:
	return [Vector3(-w, 0, -d) * 0.5, Vector3(w, 0, -d) * 0.5, Vector3(w, 0, d) * 0.5, Vector3(-w, 0, d) * 0.5]


## Squared foundation stone marking a corner of a future building.
static func box_corner(mb: MeshBuilder, rng: RandomNumberGenerator, c: Vector3) -> void:
	_box(mb, c + Vector3(0, 0.02, 0), Vector3(0.5, 0.2, 0.5), Pal.LIMESTONE_DARK, Pal.LIMESTONE, Vector3(0, rng.randf_range(-0.2, 0.2), 0))


static func _rect_pts(w: float, d: float, step: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var nx := maxi(2, int(round(w / step)))
	var nz := maxi(2, int(round(d / step)))
	for i in nx:
		var x := -w * 0.5 + w * float(i) / float(nx)
		out.append(Vector3(x, 0, -d * 0.5))
		out.append(Vector3(-x, 0, d * 0.5))
	for i in nz:
		var z := -d * 0.5 + d * float(i) / float(nz)
		out.append(Vector3(w * 0.5, 0, z))
		out.append(Vector3(-w * 0.5, 0, -z))
	return out


## Low pile of broken blocks, roof-tile shards and planks for a building destroyed at night. Pass `span` (> 0)
## to spread it along X over that length instead (a fallen 8 m wall: rubble(footprint, seed, 8.0)).
static func rubble(footprint: float, seed_value: int, span: float = 0.0) -> ArrayMesh:
	var mb := MeshBuilder.new(seed_value)
	mb.vary = VARY
	var rng := ModelsNature.make_rng(seed_value, 13)
	if span > 0.0:
		return _rubble_line(mb, rng, span, maxf(footprint, 0.5))
	var r := clampf(footprint, 0.6, 5.0)
	var n := clampi(int(8.0 + r * 6.0), 10, 30)
	var stone := [Pal.MARBLE, Pal.MARBLE_SHADE, Pal.LIMESTONE, Pal.LIMESTONE_DARK, PX.ROCK_MID]
	# Scorched ground patch.
	ModelsNature.blob(mb, rng, Vector3(0, -0.06, 0), [Vector2(r * 0.95, 0), Vector2(r * 0.7, 0.08), Vector2(0, 0.1)], 7, 0.15, PX.SOIL, PX.SOIL)
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.8
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		var pile := 1.0 - d / (r * 0.9)
		var kind := rng.randi() % 10
		var rot := Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		if kind < 5:
			var s := rng.randf_range(0.3, 0.7) * (0.6 + pile * 0.6)
			_box(mb, p + Vector3(0, s * 0.3 + pile * 0.25, 0), Vector3(s * rng.randf_range(1.0, 1.6), s * 0.7, s), stone[rng.randi() % stone.size()], null, rot)
		elif kind < 8:
			_box(mb, p + Vector3(0, 0.08 + pile * 0.3, 0), Vector3(rng.randf_range(0.3, 0.5), 0.06, rng.randf_range(0.25, 0.4)), [Pal.TERRACOTTA, Pal.TERRACOTTA_DARK][rng.randi() % 2], null, rot)
		else:
			_box(mb, p + Vector3(0, 0.1 + pile * 0.2, 0), Vector3(rng.randf_range(0.9, 1.6), 0.1, 0.16), [Pal.WOOD, Pal.WOOD_DARK, Pal.SKIN_SHADOW][rng.randi() % 3], null, rot)
	# A stub of wall still standing.
	var sa := rng.randf() * TAU
	_box(mb, Vector3(cos(sa), 0, sin(sa)) * r * 0.7 + Vector3(0, 0.35, 0), Vector3(minf(1.4, r * 0.8), 0.9, 0.35), Pal.MARBLE, Pal.MARBLE_SHADE, Vector3(0, -sa + PI * 0.5, 0.06))
	return mb.commit()


static func _rubble_line(mb: MeshBuilder, rng: RandomNumberGenerator, span: float, depth: float) -> ArrayMesh:
	var stone := [Pal.LIMESTONE, Pal.LIMESTONE_DARK, PX.ROCK_MID, Pal.WOOD, Pal.WOOD_DARK]
	var n := clampi(int(span * 3.0), 8, 30)
	for i in n:
		var x := (rng.randf() - 0.5) * span
		var z := rng.randf_range(-depth, depth) * 1.2
		var pile := 1.0 - absf(z) / (depth * 1.3)
		var col: Color = stone[rng.randi() % stone.size()]
		var rot := Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		if col == Pal.WOOD or col == Pal.WOOD_DARK:
			_box(mb, Vector3(x, 0.1 + pile * 0.15, z), Vector3(rng.randf_range(0.8, 1.6), 0.14, 0.16), col, null, rot)
		else:
			var sz := rng.randf_range(0.3, 0.6)
			_box(mb, Vector3(x, sz * 0.3 + pile * 0.15, z), Vector3(sz * 1.3, sz * 0.7, sz), col, null, rot)
	return mb.commit()


# --- small helpers -------------------------------------------------------------------------------------------

static func _box(mb: MeshBuilder, c: Vector3, size: Vector3, col: Color, top: Variant = null, rot: Vector3 = Vector3.ZERO) -> void:
	ModelsNature.box5(mb, c, size, col, top, rot)


# --- preview wrappers (tools/preview.tscn) -------------------------------------------------------------------

static func preview_pharos_1(seed_value: int) -> Dictionary:
	return building("pharos", 1, seed_value)


static func preview_pharos_2(seed_value: int) -> Dictionary:
	return building("pharos", 2, seed_value)


static func preview_pharos_3(seed_value: int) -> Dictionary:
	return building("pharos", 3, seed_value)


static func preview_house_1(seed_value: int) -> Dictionary:
	return building("house", 1, seed_value)


static func preview_house_2(seed_value: int) -> Dictionary:
	return building("house", 2, seed_value)


static func preview_farm_1(seed_value: int) -> Dictionary:
	return building("farm", 1, seed_value)


static func preview_farm_2(seed_value: int) -> Dictionary:
	return building("farm", 2, seed_value)


static func preview_dock_1(seed_value: int) -> Dictionary:
	return _with_boats(building("dock", 1, seed_value), seed_value)


static func preview_dock_2(seed_value: int) -> Dictionary:
	return _with_boats(building("dock", 2, seed_value), seed_value)


static func preview_tower_1(seed_value: int) -> Dictionary:
	return building("tower", 1, seed_value)


static func preview_tower_2(seed_value: int) -> Dictionary:
	return building("tower", 2, seed_value)


static func preview_tower_3(seed_value: int) -> Dictionary:
	return building("tower", 3, seed_value)


static func preview_wall_1(seed_value: int) -> Dictionary:
	return building("wall", 1, seed_value)


static func preview_wall_2(seed_value: int) -> Dictionary:
	return building("wall", 2, seed_value)


static func preview_barracks_1(seed_value: int) -> Dictionary:
	return building("barracks", 1, seed_value)


static func preview_barracks_2(seed_value: int) -> Dictionary:
	return building("barracks", 2, seed_value)


static func preview_boat(seed_value: int) -> ArrayMesh:
	return boat(seed_value)


static func preview_marker_house(seed_value: int) -> ArrayMesh:
	return spot_marker("house", seed_value)


static func preview_marker_tower(seed_value: int) -> ArrayMesh:
	return spot_marker("tower", seed_value)


static func preview_marker_wall(seed_value: int) -> ArrayMesh:
	return spot_marker("wall", seed_value)


static func preview_marker_farm(seed_value: int) -> ArrayMesh:
	return spot_marker("farm", seed_value)


static func preview_marker_dock(seed_value: int) -> ArrayMesh:
	return spot_marker("dock", seed_value)


static func preview_marker_barracks(seed_value: int) -> ArrayMesh:
	return spot_marker("barracks", seed_value)


static func preview_rubble(seed_value: int) -> ArrayMesh:
	return rubble(2.6, seed_value)


static func preview_rubble_wall(seed_value: int) -> ArrayMesh:
	return rubble(0.8, seed_value, 8.0)


## Dock with its boats placed at the mooring anchors (the game spawns them separately).
static func _with_boats(d: Dictionary, seed_value: int) -> Dictionary:
	var mb := MeshBuilder.new(seed_value)
	var m: ArrayMesh = d["mesh"]
	for i in 2:
		var key := "boat_%d" % (i + 1)
		if d["anchors"].has(key):
			var bm := boat(seed_value + i)
			var arr := bm.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var off: Vector3 = d["anchors"][key]
			for k in range(0, vs.size(), 3):
				# builder re-emits tris clockwise; feed them back counter-clockwise
				mb.tri_raw(vs[k] + off, vs[k + 2] + off, vs[k + 1] + off, cs[k])
	mb.commit(m)
	return d
