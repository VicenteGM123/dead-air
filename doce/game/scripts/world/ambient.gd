class_name Ambient
extends Node3D
## Ambient life on Nemea: cats about the village (door steps, the well, the plaza, the stalls; the hero pets them
## by holding Interact), goats grazing the hills — a nervous herd scattered round the smashed pen at the forest's
## edge, one on the east hill, one on the thumb —, gulls gliding over the coast, dolphin pods leaping offshore,
## butterflies over the flower drifts by day (fireflies at night).
##
##   setup(world, seed)     spawn everything (once, after World.build() made the props and the village)
##   set_night(v)           0 day .. 1 night (TimeOfDay.night_amount()): cats curl up, goats lie down, gulls leave
##   set_hero(hero)         cats glance at / walk up to the hero, goats step out of the way (Game.hero is picked
##                          up by itself when nobody calls this)
##   nearest_cat(pos, r)    nearest pettable cat rig within r metres, or null
##   set_paused(p)          freeze all ambient life (the tree pause freezes it too)
##
## Where animals may go: dry, gentle ground, never through anything solid (the props' and the village's solid
## footprints: trunks, rocks, shrubs, houses, walls, fences, stalls, the well). Cats keep to the village; goats keep
## to their pasture, away from the roads, the forest, the beaches and the cliff edges. Water is never walkable.
## Only animals on screen are re-posed every frame; the others keep living (behaviour timers) for free.
## Rigs and meshes: scripts/gfx/models_animals.gd. Behaviour: ambient_cat.gd, ambient_goat.gd, ambient_sky.gd
## (gulls), ambient_sea.gd (dolphins), ambient_bugs.gd (butterflies, fireflies), ambient_fx.gd (hearts, splashes).

const L := preload("res://scripts/world/nemea_layout.gd")
const OBS_CELL := 3.0
const OBS_MARGIN := 2.3 # largest radius free_at() / _tree_near() are queried with
const CAT_H := 0.55 # what hangs lower than this blocks a cat
const GOAT_H := 1.2
const EXTRA_SFX := true # meows and gull cries besides the purr and the splash
const CAT_COATS := ["orange", "grey", "calico", "tuxedo", "white", "black"]
## Coats of each herd (a "kid:" prefix makes a kid that follows the first adult).
const HERDS := [["white", "brown", "kid:white", "pied"], ["pied", "cream", "kid:brown"], ["brown", "white", "cream"]]
## Pastures: [centre, search radius]. The first herd scattered from the smashed pen, near the forest's edge.
const PASTURES := [[Vector2(33, 30), 14.0], [Vector2(72, -14), 22.0], [Vector2(-126, -48), 20.0]]
## Cats live within this distance of the plaza.
const VILLAGE_R := 50.0

var world: Node3D = null # World
var terrain: RefCounted = null # NemeaTerrain
var island: IslandAdapter
var hero: Node3D = null
var night := 0.0
var paused := false
var cats: Array[AmbientCat] = []
var goats: Array[AmbientGoat] = []
var sky: AmbientSky
var sea: AmbientSea
var bugs: AmbientBugs
var fx: AmbientFx
var rng := RandomNumberGenerator.new()
## Flower patches (from the props): butterflies visit them, cats do not lie down on them.
var flowers := PackedVector3Array()
## Tree positions (from the props): fireflies gather round them.
var trees := PackedVector3Array()
## Where the player spends the start of the game (the plaza): butterflies prefer flowers near it.
var focus := Vector3.ZERO

var _path_d := PackedFloat32Array() # terrain fields, cached (sampled bilinearly like NemeaTerrain.field)
var _forest_w := PackedFloat32Array()
var _cave_w := PackedFloat32Array()
var _sd := PackedFloat32Array()
var _pad_w := PackedFloat32Array()
var _solid := PackedVector4Array() # x, z, radius, height (what stands lower than an animal's height blocks it)
var _grid := {} # Vector2i -> PackedVector4Array
var _keep_clear := PackedVector3Array() # x, z, r: interactables cats keep clear of (altars, the boat, the boulder)
var _ok := false
var _cam: Camera3D = null
var _vp := Vector2(1280, 720)


func _init() -> void:
	name = "Ambient"


# --- API ---------------------------------------------------------------------------------------------------

func setup(w: Node3D, seed_value: int = 1234) -> void:
	world = w
	terrain = w.get("terrain")
	_path_d = terrain.get("path_d")
	_forest_w = terrain.get("forest_w")
	_cave_w = terrain.get("cave_w")
	_sd = terrain.get("sd")
	_pad_w = terrain.get("pad_w")
	island = IslandAdapter.new(w)
	rng.seed = seed_value
	for c in get_children():
		c.queue_free()
	cats.clear()
	goats.clear()
	focus = w.call("ground", Vector3(L.PLAZA.x, 0, L.PLAZA.y))
	_read_solids()
	_build_keep_clear()
	fx = AmbientFx.new()
	fx.name = "Fx"
	add_child(fx)
	_spawn_cats()
	_spawn_goats()
	sky = AmbientSky.new()
	sky.name = "Gulls"
	add_child(sky)
	sky.setup(self, 6)
	sea = AmbientSea.new()
	sea.name = "Dolphins"
	add_child(sea)
	sea.setup(self)
	bugs = AmbientBugs.new()
	bugs.name = "Bugs"
	add_child(bugs)
	bugs.setup(self)
	_ok = true


func set_night(v: float) -> void:
	night = clampf(v, 0.0, 1.0)


func set_hero(h: Node3D) -> void:
	hero = h


func nearest_cat(pos: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius * radius
	for c in cats:
		var d := (c.pos.x - pos.x) * (c.pos.x - pos.x) + (c.pos.z - pos.z) * (c.pos.z - pos.z)
		if d <= best_d and c.is_pettable():
			best_d = d
			best = c.rig
	return best


func set_paused(p: bool) -> void:
	paused = p
	process_mode = Node.PROCESS_MODE_DISABLED if p else Node.PROCESS_MODE_INHERIT


# --- queries used by the behaviours -------------------------------------------------------------------------

## Island angle convention (the behaviours use it): degrees, 0 = +Z (south), 90 = +X (east).
static func angle_of(x: float, z: float) -> float:
	return fposmod(rad_to_deg(atan2(x, z)), 360.0)


func hero_pos() -> Vector3:
	if hero != null and is_instance_valid(hero) and hero.is_inside_tree() and hero.visible:
		return hero.global_position
	return Vector3.INF


## The hero, if within `r` metres (XZ) of p: the only walker on Nemea.
func walker_near(p: Vector3, r: float) -> Vector3:
	var h := hero_pos()
	if h.is_finite() and (h.x - p.x) * (h.x - p.x) + (h.z - p.z) * (h.z - p.z) < r * r:
		return h
	return Vector3.INF


## True when the hero stands within reach of something else he can use (an altar, the boat, the boulder): cats
## then leave him be instead of coming over to greet him (and stealing the Interact prompt).
func hero_at_work() -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	var hp := hero.global_position
	for it in Interactables.list:
		if not is_instance_valid(it) or it is ModelsAnimals.CatRig or not it.has_method("can_interact"):
			continue
		var ip: Vector3 = it.call("interact_position")
		if Vector2(ip.x - hp.x, ip.z - hp.z).length() < float(it.call("interact_range")) + 1.0 and bool(it.call("can_interact", hero)):
			return true
	return false


## True when another cat is (or is heading) within `r` metres of p.
func cat_crowded(p: Vector3, r: float, me: AmbientCat) -> bool:
	for c in cats:
		if c == me:
			continue
		if _d2(c.pos, p) < r * r or ((c.state == AmbientCat.WALK or c.state == AmbientCat.BED) and _d2(c.target, p) < r * r):
			return true
	return false


static func _d2(a: Vector3, b: Vector3) -> float:
	return (a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)


## Nearest living enemy (wolf, boar, lion) within `r` metres (XZ), or Vector3.INF: animals run from them.
func threat_near(p: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := r * r
	for e in get_tree().get_nodes_in_group("enemy"):
		var n := e as Node3D
		if n == null or not is_instance_valid(n) or (n.has_method("is_alive") and not bool(n.call("is_alive"))):
			continue
		var q := n.global_position
		var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d < bd:
			bd = d
			best = q
	return best


## Nothing solid within `r` of (x, z) for an animal `height` metres tall.
func free_at(x: float, z: float, r: float, height: float) -> bool:
	var cell: Variant = _grid.get(Vector2i(floori(x / OBS_CELL), floori(z / OBS_CELL)))
	if cell == null:
		return true
	for o in (cell as PackedVector4Array):
		if o.w >= 0.0 and o.w < height * 0.25:
			continue # a low thing (a fallen fence rail, a bone) does not block
		var dx := x - o.x
		var dz := z - o.y
		var rr := o.z + r
		if dx * dx + dz * dz < rr * rr:
			return false
	return true


## True when a tree trunk stands within `r` of (x, z) (goats graze the open, not under the trees).
func _tree_near(x: float, z: float, r: float) -> bool:
	var cell: Variant = _grid.get(Vector2i(floori(x / OBS_CELL), floori(z / OBS_CELL)))
	if cell == null:
		return false
	for o in (cell as PackedVector4Array):
		if o.w < 50.0:
			continue
		var dx := x - o.x
		var dz := z - o.y
		if dx * dx + dz * dz < r * r:
			return true
	return false


## True when a low solid prop (shrub, rock, wall) stands at (x, z): butterflies fly over it.
func low_prop_at(x: float, z: float, r: float = 0.15) -> bool:
	var cell: Variant = _grid.get(Vector2i(floori(x / OBS_CELL), floori(z / OBS_CELL)))
	if cell == null:
		return false
	for o in (cell as PackedVector4Array):
		if o.w < 0.0 or o.w > 2.5:
			continue
		var dx := x - o.x
		var dz := z - o.y
		var rr := o.z + r
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


## Bilinear sample of a terrain field (same grid as NemeaTerrain: 1 m cells over [-EXT, EXT]^2).
static func _fieldv(a: PackedFloat32Array, x: float, z: float) -> float:
	const N := L.N
	var fx := clampf((x + L.EXT) / L.CELL, 0.0, N - 1.0001)
	var fz := clampf((z + L.EXT) / L.CELL, 0.0, N - 1.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	return lerpf(lerpf(a[i], a[i + 1], tx), lerpf(a[i + N], a[i + N + 1], tx), tz)


## Dry, gentle ground (no water, no cliff).
func _land_ok(x: float, z: float, min_h: float, max_slope: float) -> bool:
	if float(world.call("height_at", x, z)) < min_h:
		return false
	return float(world.call("slope_at", x, z)) <= max_slope


## Where a cat may walk: the village, dry and gentle ground, clear of everything solid.
func cat_ok(p: Vector3) -> bool:
	if Vector2(p.x - focus.x, p.z - focus.z).length() > VILLAGE_R:
		return false
	if not _land_ok(p.x, p.z, 1.0, 0.2):
		return false
	return free_at(p.x, p.z, 0.28, CAT_H)


## Where a cat may walk at night: as cat_ok, but never on a road.
func cat_night_ok(p: Vector3) -> bool:
	return _fieldv(_path_d, p.x, p.z) > 0.7 and cat_ok(p)


## Where a cat may settle (home, wander goals): off the roads, not on flowers, a little apart from the altars,
## the boat and the boulder (so the cat is not the nearest thing to Interact with there).
func cat_rest_ok(p: Vector3) -> bool:
	if _fieldv(_path_d, p.x, p.z) < 1.3:
		return false
	for k in _keep_clear:
		if (p.x - k.x) * (p.x - k.x) + (p.z - k.y) * (p.z - k.y) < k.z * k.z:
			return false
	for f in flowers:
		if (p.x - f.x) * (p.x - f.x) + (p.z - f.z) * (p.z - f.z) < 0.5:
			return false
	return float(world.call("slope_at", p.x, p.z)) < 0.12 and cat_ok(p)


## Where a cat may sleep: as cat_rest_ok, well away from the roads.
func cat_bed_ok(p: Vector3) -> bool:
	return _fieldv(_path_d, p.x, p.z) > 3.0 and cat_rest_ok(p)


## Where a goat may be: open pasture (meadow or garrigue), away from the roads, the village, the forest's trees,
## the cave, the beaches and the cliff edges.
func goat_ok(p: Vector3) -> bool:
	var x := p.x
	var z := p.z
	if not _land_ok(x, z, 1.5, 0.12):
		return false
	if Vector2(x - focus.x, z - focus.z).length() < 46.0:
		return false
	if _fieldv(_path_d, x, z) < 3.5 or _fieldv(_cave_w, x, z) > 0.0 or _tree_near(x, z, 2.2):
		return false
	if _fieldv(_sd, x, z) < 8.0 or _fieldv(_pad_w, x, z) > 0.2:
		return false
	return free_at(x, z, 0.5, GOAT_H)


## Straight walk from a to b stays on valid ground (sampled every 0.4 m).
func path_ok(a: Vector3, b: Vector3, ok: Callable) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, int(ceil(d / 0.4)))
	for i in range(1, n + 1):
		if not ok.call(a.lerp(b, float(i) / float(n))):
			return false
	return true


## Pushes p out of any solid footprint (radius r).
func push_out(p: Vector3, r: float) -> Vector3:
	var cell: Variant = _grid.get(Vector2i(floori(p.x / OBS_CELL), floori(p.z / OBS_CELL)))
	if cell == null:
		return p
	for o in (cell as PackedVector4Array):
		var dx := p.x - o.x
		var dz := p.z - o.y
		var rr := o.z + r
		var d2 := dx * dx + dz * dz
		if d2 < rr * rr:
			var d := sqrt(d2)
			if d < 0.001:
				dx = 1.0
				dz = 0.0
				d = 1.0
			p.x = o.x + dx / d * rr
			p.z = o.y + dz / d * rr
	return p


## Height of the ground triangle under (x, z) (paws on the facets).
func ground_y(x: float, z: float) -> float:
	return float(world.call("height_at", x, z))


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, float(world.call("height_at", p.x, p.z)), p.z)


## True when p is (nearly) in view of the game camera.
func on_screen(p: Vector3, margin: float = 140.0) -> bool:
	if _cam == null:
		return true
	if _cam.is_position_behind(p):
		return false
	var s := _cam.unproject_position(p)
	return s.x > -margin and s.y > -margin and s.x < _vp.x + margin and s.y < _vp.y + margin


## Direction the afternoon sun comes from (island angle convention, radians): cats sun themselves on that side.
static func sun_angle() -> float:
	var st: Dictionary = TimeOfDay.STATES
	var mood: Dictionary = st.get("golden", st.get("day", {}))
	return deg_to_rad(float(mood.get("azim", 250.0)))


# --- solids ------------------------------------------------------------------------------------------------

## The solid footprints animals walk round: the props' (trunks, rocks, shrubs) and the village's (houses, walls,
## fences, stalls, the well, the pier).
func _read_solids() -> void:
	_solid = PackedVector4Array()
	flowers = PackedVector3Array()
	trees = PackedVector3Array()
	var pr: Variant = world.get("props")
	if pr != null:
		for s in (pr.get("solids") as Array):
			_solid.append(Vector4(float(s[0]), float(s[1]), float(s[2]), float(s[3])))
		flowers = pr.get("flowers")
		trees = pr.get("trees")
		for tp in trees:
			_solid.append(Vector4(tp.x, tp.z, 0.45, 99.0))
	var vil: Variant = world.get("village")
	if vil != null:
		for s in (vil.get("solids") as Array):
			_solid.append(Vector4(float(s[0]), float(s[1]), float(s[2]), float(s[3])))
	_grid.clear()
	for o in _solid:
		var rr := o.z + OBS_MARGIN
		for cx in range(floori((o.x - rr) / OBS_CELL), floori((o.x + rr) / OBS_CELL) + 1):
			for cz in range(floori((o.y - rr) / OBS_CELL), floori((o.y + rr) / OBS_CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = PackedVector4Array()
				var arr: PackedVector4Array = _grid[key]
				arr.append(o)
				_grid[key] = arr


func _build_keep_clear() -> void:
	_keep_clear = PackedVector3Array()
	for it in Interactables.list:
		var n := it as Node3D
		if n == null or not is_instance_valid(n) or n is ModelsAnimals.CatRig:
			continue
		var p := n.global_position if n.is_inside_tree() else n.position
		_keep_clear.append(Vector3(p.x, p.z, 3.0))


# --- cats --------------------------------------------------------------------------------------------------

func _spawn_cats() -> void:
	var sites: Array = []
	var vil: Variant = world.get("village")
	if vil != null:
		for s in (vil.get("cat_sites") as Array):
			sites.append(s)
	# Spread the homes: farthest from the other cats first, nearer the plaza on ties.
	for coat in CAT_COATS:
		var home := Vector3.INF
		var best_s := -INF
		for s in sites:
			var p: Vector3 = s
			var q := _settle(p)
			if not q.is_finite():
				continue
			var md := 14.0
			for c in cats:
				md = minf(md, c.home.distance_to(q))
			if md < 4.0:
				continue
			var score := md - Vector2(q.x - focus.x, q.z - focus.z).length() * 0.15 + rng.randf() * 1.5
			if coat == "orange":
				# Zorba, the plaza cat, waits by the road from the pier (the first cat the player meets).
				score = -Vector2(q.x - 4.0, q.z - 86.0).length()
			if score > best_s:
				best_s = score
				home = q
		if not home.is_finite():
			continue
		var cat := AmbientCat.new(self, coat, home, rng.randi())
		cats.append(cat)


## A valid resting spot at or near p (within 2.5 m), or INF.
func _settle(p: Vector3) -> Vector3:
	var g := ground(p)
	if cat_rest_ok(g):
		return g
	for k in 16:
		var a := TAU * float(k) / 16.0
		for d in [0.8, 1.6, 2.5]:
			var q := ground(p + Vector3(cos(a), 0, sin(a)) * float(d))
			if cat_rest_ok(q):
				return q
	return Vector3.INF


# --- goats -------------------------------------------------------------------------------------------------

func _spawn_goats() -> void:
	for hi in HERDS.size():
		var pc: Vector2 = PASTURES[hi][0]
		var pr: float = PASTURES[hi][1]
		# The roomiest valid spot in the pasture.
		var best := Vector3.INF
		var best_room := -999
		for k in 70:
			var a := rng.randf() * TAU
			var c := ground(Vector3(pc.x, 0, pc.y) + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * pr)
			if not goat_ok(c):
				continue
			var room := 0
			for j in 12:
				var b := TAU * float(j) / 12.0
				for rr in [2.5, 5.0]:
					if goat_ok(ground(c + Vector3(cos(b), 0, sin(b)) * float(rr))):
						room += 1
			# Roomy, but near the pasture's centre (the pen herd must be seen from the lane).
			var score := room - int(Vector2(c.x - pc.x, c.z - pc.y).length() * 0.6)
			if score > best_room:
				best_room = score
				best = c
		if not best.is_finite():
			continue
		var mother: AmbientGoat = null
		var coats: Array = HERDS[hi]
		for gi in coats.size():
			var coat: String = coats[gi]
			var kid := coat.begins_with("kid:")
			if kid:
				coat = coat.substr(4)
			var p := Vector3.INF
			for tries in 40:
				var a := rng.randf() * TAU
				# The pen herd is scattered (nervous, spread out); the others keep together.
				var spread := 7.0 if hi == 0 else 4.0
				var q := ground(best + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, spread))
				if not goat_ok(q):
					continue
				var clear := true
				for g in goats:
					if g.pos.distance_to(q) < 1.8:
						clear = false
				if clear:
					p = q
					break
			if not p.is_finite():
				continue
			var goat := AmbientGoat.new(self, coat, p, best, rng.randi(), kid)
			if kid:
				goat.mother = mother
			elif mother == null:
				mother = goat
			goats.append(goat)


# --- per frame ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ok:
		return
	if hero == null:
		var h: Variant = Game.get("hero")
		if h is Node3D and is_instance_valid(h):
			hero = h
	var tod: Variant = Game.get("tod")
	if tod != null and is_instance_valid(tod) and (tod as Object).has_method("night_amount"):
		night = clampf(float(tod.call("night_amount")), 0.0, 1.0)
	var dt := minf(delta, 0.1)
	_cam = get_viewport().get_camera_3d()
	_vp = get_viewport().get_visible_rect().size
	for c in cats:
		c.tick(dt)
	for c in cats:
		c.rig.step(dt, on_screen(c.pos))
	for g in goats:
		g.tick(dt)
	for g in goats:
		g.rig.step(dt, on_screen(g.pos))


## The island seen as the behaviours expect it (PHAROS' Island API): the coast radius per bearing, heights.
class IslandAdapter extends RefCounted:
	const LY := preload("res://scripts/world/nemea_layout.gd")
	var w: Node3D
	var spots: Array = []
	var _coast := PackedFloat32Array()

	func _init(world: Node3D) -> void:
		w = world
		var t: RefCounted = world.get("terrain")
		var sd: PackedFloat32Array = t.get("sd")
		_coast.resize(360)
		for deg in 360:
			var a := deg_to_rad(float(deg))
			var dir := Vector2(sin(a), cos(a))
			var last := 30.0
			var r := 0.0
			while r < 185.0:
				var q := dir * r
				if Ambient._fieldv(sd, q.x, q.y) > 0.0 and not _islet(q):
					last = r
				r += 1.0
			_coast[deg] = last

	static func _islet(q: Vector2) -> bool:
		for isl in LY.ISLETS:
			var c: Vector2 = isl[0]
			var rr: Vector2 = isl[1]
			var dx := (q.x - c.x) / (rr.x + 4.0)
			var dz := (q.y - c.y) / (rr.y + 4.0)
			if dx * dx + dz * dz < 1.0:
				return true
		return false

	## Distance from the island's centre to its outermost shore along a bearing (degrees, 0 = south).
	func coast_at(deg: float) -> float:
		var f := fposmod(deg, 360.0)
		var i := int(f) % 360
		return lerpf(_coast[i], _coast[(i + 1) % 360], f - floorf(f))

	func height_at(x: float, z: float) -> float:
		return float(w.call("height_at", x, z))

	func facet_height_at(x: float, z: float) -> float:
		return float(w.call("height_at", x, z))

	func spot_sd_at(_x: float, _z: float) -> float:
		return 99.0
