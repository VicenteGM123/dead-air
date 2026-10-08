class_name Ambient
extends Node3D
## Ambient life on Delos: cats by the houses, the well and the plaza (they can be petted), goats grazing the wild
## phrygana hills, gulls gliding over the coast, dolphin pods leaping offshore, butterflies over the flowers by day
## and fireflies by night.
##
##   setup(island)          spawn everything (once, after Island.generate() and Props.build())
##   set_night(v)           0 day .. 1 night (TimeOfDay.night_amount()), every frame: gulls, butterflies and
##                          dolphins leave, fireflies come out, cats curl up and goats lie down (and wake at dawn)
##   set_hero(hero)         cats glance at / walk up to the hero, goats step out of the way
##   nearest_cat(pos, r)    nearest pettable cat rig within r metres, or null (then call rig.pet())
##   set_paused(p)          freeze all ambient life (the tree pause freezes it too)
## Debug: `ambperf=1` prints the per-frame cost of the cats and goats every 300 frames.
##
## Rigs and meshes: scripts/gfx/models_animals.gd. Behaviour: ambient_cat.gd, ambient_goat.gd, ambient_sky.gd
## (gulls), ambient_sea.gd (dolphins), ambient_bugs.gd (butterflies, fireflies), ambient_fx.gd (hearts, splashes).
##
## Where animals may go: dry, gentle ground; never inside a build spot (built or not), the lighthouse base or the
## solid footprint of a prop (trunks and low crowns, shrubs, rocks, walls, vines, wheat, ruins, landmarks: read
## from Props), always pushed out of Obstacles. Cats live by the houses that stand (or by the well and the plaza
## while there are none) and sleep away from the lanes and the walls the creatures of Nyx attack; they scamper off
## when a creature comes close. Goats keep to the WILD zone, far from paths, spots, landmarks, fields and cliffs.
## Only animals on screen are re-posed every frame; the others keep living (behaviour and blend timers) for free.

const PLAZA_CORE := 5.8 # lighthouse base: nobody walks closer to the centre
const OBS_CELL := 3.0
const OBS_MARGIN := 0.7 # largest radius free_at() is queried with
const CAT_H := 0.55 # what hangs lower than this blocks a cat
const GOAT_H := 1.2
const EXTRA_SFX := true # meows and gull cries besides the purr and the splash
## Props that animals walk through (they still avoid lying down on flowers).
const WALK_THROUGH := ["flowers_", "grass_", "sea_lily"]
## Landmarks merged into Props' static mesh: [centre, radius].
const LANDMARKS := [[Landscape.WELL, 1.05], [Landscape.THRESHING, 3.5], [Landscape.BEEHIVES, 1.7], [Landscape.SPRING, 1.5],
	[Landscape.SACRED_BASIN, 1.3], [Landscape.HERM, 0.8]]
const CAT_COATS := ["orange", "grey", "calico", "tuxedo", "white", "black"]
## Coats of each herd (a "kid:" prefix makes a kid that follows the first adult).
const HERDS := [["white", "brown", "kid:white"], ["pied", "cream", "kid:brown"], ["brown", "white"]]

var island: Island
var props: Node = null
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
## Flower patches (from Props): butterflies visit them, cats do not lie down on them.
var flowers := PackedVector3Array()
## Tree positions (from Props): fireflies gather round them.
var trees := PackedVector3Array()
## Village places a cat may call home while no house stands near it: [Vector3, taken_by (AmbientCat or null)].
var village_sites: Array = []

var _solid := PackedVector4Array() # x, z, radius, clearance (0: a low prop, solid from the ground up; -1: a tree)
var _grid := {} # Vector2i -> PackedVector4Array (props and landmarks, built once)
var _dgrid := {} # Vector2i -> PackedVector4Array (Obstacles registry: buildings, trees, rocks; rebuilt on change)
var _dyn_count := -1
var _dyn_timer := 0.0
var _keep_clear := PackedVector3Array() # x, z, r: small interactables cats keep clear of (the night horn)
var _house_timer := 0.0
var _last_phase := -1
var _rehome := false
var _started := false
var _ok := false
var _cam: Camera3D = null
var _perf := OS.get_cmdline_user_args().has("ambperf=1")
var _perf_acc := PackedInt64Array([0, 0, 0, 0, 0])
var _perf_n := 0
var _vp := Vector2(1280, 720)


func _init() -> void:
	name = "Ambient"


# --- API ---------------------------------------------------------------------------------------------------

func setup(isl: Island, seed_value: int = 1234) -> void:
	island = isl
	rng.seed = seed_value
	for c in get_children():
		c.queue_free()
	cats.clear()
	goats.clear()
	_read_props()
	_build_static_grid()
	_sync_dynamic(true)
	_build_keep_clear()
	fx = AmbientFx.new()
	fx.name = "Fx"
	add_child(fx)
	_spawn_cats()
	_spawn_goats()
	sky = AmbientSky.new()
	sky.name = "Gulls"
	add_child(sky)
	sky.setup(self, 5)
	sea = AmbientSea.new()
	sea.name = "Dolphins"
	add_child(sea)
	sea.setup(self)
	bugs = AmbientBugs.new()
	bugs.name = "Bugs"
	add_child(bugs)
	bugs.setup(self)
	if not Game.phase_changed.is_connected(_on_phase):
		Game.phase_changed.connect(_on_phase)
	_last_phase = Game.phase
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

func hero_pos() -> Vector3:
	if hero != null and is_instance_valid(hero) and hero.is_inside_tree() and hero.visible:
		return hero.global_position
	return Vector3.INF


## Nearest walker of Delos (Fanós or a hoplite) within `r` metres (XZ), or Vector3.INF.
func walker_near(p: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := r * r
	for u in Game.units[0]:
		if not is_instance_valid(u) or not u.alive or u.is_building or not u.visible:
			continue
		var q: Vector3 = u.global_position
		var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d < bd:
			bd = d
			best = q
	return best


## True when Fanós stands within reach of something else he can use (a build spot, the horn): cats then leave
## him be instead of coming over to greet him (and stealing the Interact prompt).
func hero_at_work() -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	var hp := hero.global_position
	for it in Interactables.list:
		if not is_instance_valid(it) or it is ModelsAnimals.CatRig or not it.has_method("can_interact"):
			continue
		var ip: Vector3 = it.interact_position()
		if Vector2(ip.x - hp.x, ip.z - hp.z).length() < float(it.interact_range()) + 1.0 and it.can_interact(hero):
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


## Nearest living creature of Nyx within `r` metres (XZ), or Vector3.INF.
func threat_near(p: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := r * r
	for u in Game.units[1]:
		if not is_instance_valid(u) or not u.alive:
			continue
		var q: Vector3 = u.global_position
		var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d < bd:
			bd = d
			best = q
	return best


## No building footprint (built or not), lighthouse base or solid prop within `r` of (x, z) for an animal
## `height` metres tall.
func free_at(x: float, z: float, r: float, height: float) -> bool:
	if x * x + z * z < PLAZA_CORE * PLAZA_CORE:
		return false
	if island.spot_sd_at(x, z) < r + 0.2:
		return false
	var key := Vector2i(floori(x / OBS_CELL), floori(z / OBS_CELL))
	var cell: Variant = _grid.get(key)
	if cell != null:
		for o in (cell as PackedVector4Array):
			if o.w >= height:
				continue
			var dx := x - o.x
			var dz := z - o.y
			var rr := o.z + r
			if dx * dx + dz * dz < rr * rr:
				return false
	cell = _dgrid.get(key)
	if cell != null:
		for o in (cell as PackedVector4Array):
			var dx := x - o.x
			var dz := z - o.y
			var rr := o.z + r
			if dx * dx + dz * dz < rr * rr:
				return false
	return true


## True when a low solid prop (shrub, rock, wall, vine row, wheat, ruin) stands at (x, z): butterflies fly over it.
func low_prop_at(x: float, z: float, r: float = 0.15) -> bool:
	var cell: Variant = _grid.get(Vector2i(floori(x / OBS_CELL), floori(z / OBS_CELL)))
	if cell == null:
		return false
	for o in (cell as PackedVector4Array):
		if o.w < 0.0:
			continue
		var dx := x - o.x
		var dz := z - o.y
		var rr := o.z + r
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


## Where a cat may walk: dry, gentle ground (no beach, no cliff), clear of everything solid.
func cat_ok(p: Vector3) -> bool:
	if not island.is_walkable(p.x, p.z) or island.height_at(p.x, p.z) < 0.4:
		return false
	var zn := island.zone_at(p.x, p.z)
	if zn == Landscape.SEA or zn == Landscape.BEACH or zn == Landscape.CLIFF or zn == Landscape.DUNE:
		return false
	if island.slope_at(p.x, p.z) > 0.2:
		return false
	return free_at(p.x, p.z, 0.28, CAT_H)


## Where a cat may walk at night: as cat_ok, but never on a lane.
func cat_night_ok(p: Vector3) -> bool:
	return island.lane_dist_at(p.x, p.z) > Island.LANE_W + 0.7 and cat_ok(p)


## Where a cat may settle (home, wander goals): off the paths, not on flowers, and a little apart from the build
## spots and the night horn (so the cat is not the nearest thing to Interact with while building).
func cat_rest_ok(p: Vector3) -> bool:
	if island.lane_dist_at(p.x, p.z) < Island.LANE_W + 1.3 or island.spot_sd_at(p.x, p.z) < 1.6:
		return false
	for k in _keep_clear:
		if (p.x - k.x) * (p.x - k.x) + (p.z - k.y) * (p.z - k.y) < k.z * k.z:
			return false
	for f in flowers:
		if (p.x - f.x) * (p.x - f.x) + (p.z - f.z) * (p.z - f.z) < 0.5:
			return false
	return island.slope_at(p.x, p.z) < 0.12 and cat_ok(p)


## Where a cat may sleep: as cat_rest_ok, and well away from the lanes and from the buildings the creatures of
## Nyx come to attack.
func cat_bed_ok(p: Vector3) -> bool:
	return island.lane_dist_at(p.x, p.z) > 5.0 and island.spot_sd_at(p.x, p.z) > 2.3 and cat_rest_ok(p)


## Where a goat may be: the wild hills, far from paths, spots, landmarks, fields, beaches and cliff edges.
func goat_ok(p: Vector3) -> bool:
	var x := p.x
	var z := p.z
	if island.zone_at(x, z) != Landscape.WILD or island.height_at(x, z) < 0.8:
		return false
	if island.lane_dist_at(x, z) < 5.0 or island.spot_sd_at(x, z) < 4.0 or island.landmark_at(x, z) < 3.0:
		return false
	if island.slope_at(x, z) > 0.12:
		return false
	var ang := Island.angle_of(x, z)
	if island.coast_at(ang) - Vector2(x, z).length() < 6.0:
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


## Obstacles.push_out() through the grid (same result for r <= OBS_MARGIN, a fraction of the cost).
func push_out(p: Vector3, r: float) -> Vector3:
	var cell: Variant = _dgrid.get(Vector2i(floori(p.x / OBS_CELL), floori(p.z / OBS_CELL)))
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


## Height of the rendered terrain triangle under p (paws on the facets, not on the smoothed grid).
func ground_y(x: float, z: float) -> float:
	return island.facet_height_at(x, z)


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, island.height_at(p.x, p.z), p.z)


## True when p is (nearly) in view of the game camera.
func on_screen(p: Vector3, margin: float = 140.0) -> bool:
	if _cam == null:
		return true
	if _cam.is_position_behind(p):
		return false
	var s := _cam.unproject_position(p)
	return s.x > -margin and s.y > -margin and s.x < _vp.x + margin and s.y < _vp.y + margin


## Direction the midday sun comes from (island angle convention: 0 = +Z south, 90 = +X east).
static func sun_angle() -> float:
	return deg_to_rad(float(TimeOfDay.STATES["day"]["azim"]))


# --- props, obstacles --------------------------------------------------------------------------------------

## Reads the layout Props made (per batch transforms; MultiMesh read-back as a fallback) into solid circles,
## flower patches and tree positions.
func _read_props() -> void:
	_solid = PackedVector4Array()
	flowers = PackedVector3Array()
	trees = PackedVector3Array()
	var pr: Node = null
	if Game.main != null and is_instance_valid(Game.main):
		var v: Variant = Game.main.get("props")
		if v is Node:
			pr = v
	if pr == null and get_parent() != null:
		pr = get_parent().get_node_or_null("Props")
	props = pr
	if pr != null:
		var batches: Variant = pr.get("_batches")
		if batches is Dictionary and not (batches as Dictionary).is_empty():
			for key in batches:
				var b: Variant = batches[key]
				if b is Dictionary and (b as Dictionary).get("mesh") is Mesh and (b as Dictionary).get("xforms") is Array:
					_add_batch(String(key).get_slice("#", 0), b["mesh"], b["xforms"])
		else:
			for c in pr.get_children():
				var mmi := c as MultiMeshInstance3D
				if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
					continue
				var xs: Array = []
				for i in mmi.multimesh.instance_count:
					xs.append(mmi.transform * mmi.multimesh.get_instance_transform(i))
				_add_batch(String(mmi.name).get_slice("#", 0), mmi.multimesh.mesh, xs)
	for lm in LANDMARKS:
		var c2: Vector2 = lm[0]
		_solid.append(Vector4(c2.x, c2.y, float(lm[1]), 0.0))


func _add_batch(fn: String, mesh: Mesh, xfs: Array) -> void:
	for w in WALK_THROUGH:
		if fn.begins_with(w):
			if fn.begins_with("flowers_"):
				for x in xfs:
					flowers.append((x as Transform3D).origin)
			return
	var ab := mesh.get_aabb()
	var tree: Array = Landscape.TREES.get(fn, [])
	for x in xfs:
		var xf: Transform3D = x
		var o := xf.origin
		var sc := xf.basis.get_scale()
		if not tree.is_empty():
			# Trunk, plus the ground the crown hides from the game camera (pitch 52, looking north: a crown
			# between heights h0 and h1 hides the ground up to h * 0.78 m north of it), so nobody lives unseen
			# under a tree. Tall narrow crowns (cypress) and high ones (plane tree, palms) hide little.
			var s := (absf(sc.x) + absf(sc.z)) * 0.5
			trees.append(o)
			_solid.append(Vector4(o.x, o.z, maxf(float(tree[3]) * s, 0.25) + 0.12, -1.0))
			var cr := float(tree[0]) * s
			var h0 := float(tree[2]) * s
			var h1 := float(tree[1]) * s
			var mid := minf((h0 + h1) * 0.5, h0 + 2.0)
			_solid.append(Vector4(o.x, o.z - mid * 0.78 * 0.6, cr * 0.85 + minf(h1 - h0, 3.0) * 0.25, -1.0))
			continue
		var hx := ab.size.x * 0.5 * absf(sc.x)
		var hz := ab.size.z * 0.5 * absf(sc.z)
		if maxf(hx, hz) < 0.08:
			continue
		var c := xf * Vector3(ab.position.x + ab.size.x * 0.5, 0.0, ab.position.z + ab.size.z * 0.5)
		var lo := maxf(hx, hz)
		var sh := maxf(minf(hx, hz), 0.12)
		if lo > sh * 1.7:
			# Long things (walls, vine rows, fallen columns, boats): a row of circles along the long axis.
			var axis: Vector3 = (xf.basis.x if hx >= hz else xf.basis.z).normalized()
			var n := int(ceil((lo - sh) / sh))
			for k in n + 1:
				var u := lerpf(-lo + sh, lo - sh, float(k) / float(maxi(n, 1)))
				var p := c + axis * u
				_solid.append(Vector4(p.x, p.z, sh * 1.08, 0.0))
		else:
			_solid.append(Vector4(c.x, c.z, lo * 0.88, 0.0))


func _build_static_grid() -> void:
	_grid.clear()
	for o in _solid:
		_grid_add(_grid, o)


## Rebuilds the grid of the shared Obstacles registry when it changes (buildings built or destroyed).
func _sync_dynamic(force: bool = false) -> void:
	var n := Obstacles.list.size()
	if not force and n == _dyn_count:
		return
	_dyn_count = n
	_dgrid.clear()
	for e in Obstacles.list:
		var c: Vector3 = e[0]
		_grid_add(_dgrid, Vector4(c.x, c.z, float(e[1]), 0.0))


func _grid_add(g: Dictionary, o: Vector4) -> void:
	var rr := o.z + OBS_MARGIN
	for cx in range(floori((o.x - rr) / OBS_CELL), floori((o.x + rr) / OBS_CELL) + 1):
		for cz in range(floori((o.y - rr) / OBS_CELL), floori((o.y + rr) / OBS_CELL) + 1):
			var key := Vector2i(cx, cz)
			if not g.has(key):
				g[key] = PackedVector4Array()
			var arr: PackedVector4Array = g[key]
			arr.append(o)
			g[key] = arr


func _build_keep_clear() -> void:
	_keep_clear = PackedVector3Array()
	for it in Interactables.list:
		var n := it as Node3D
		if n == null or not is_instance_valid(n) or n is ModelsAnimals.CatRig or n is BuildSpot:
			continue
		var p := n.global_position if n.is_inside_tree() else n.position
		_keep_clear.append(Vector3(p.x, p.z, 3.0))


# --- cats --------------------------------------------------------------------------------------------------

func _spawn_cats() -> void:
	var sun := sun_angle()
	village_sites.clear()
	for coat in CAT_COATS:
		var home := Vector3.INF
		var site := -1
		match String(coat):
			"orange":
				# Zorba, the lighthouse cat: on the south edge of the plaza, where Fanós starts the game.
				home = _find_spot(Vector3.ZERO, 7.4, 8.6, deg_to_rad(-22.0), 0.35, cat_rest_ok)
			"grey":
				# Nefeli lives by the well.
				home = _find_spot(Vector3(Landscape.WELL.x, 0, Landscape.WELL.y), 1.5, 2.1, sun, 1.2, cat_rest_ok)
			_:
				# House cats wait in the village until there are houses to move in by.
				if village_sites.is_empty():
					_make_village_sites()
				site = _spread_village_site()
				if site >= 0:
					home = village_sites[site][0]
		if not home.is_finite():
			home = _find_spot(Vector3.ZERO, 8.0, 13.0, rng.randf() * TAU, PI, cat_rest_ok)
		if not home.is_finite():
			continue
		var cat := AmbientCat.new(self, coat, home, rng.randi())
		cat.house_cat = coat != "orange" and coat != "grey"
		if site >= 0:
			village_sites[site][1] = cat
		cats.append(cat)
	_update_houses(true)


## Places around the plaza and the village landmarks where a cat can live while no house stands.
func _make_village_sites() -> void:
	village_sites.clear()
	var cands: Array[Vector3] = []
	var anchors := [[Vector2(-7.0, 16.0), 2.2, 3.0], [Landscape.HERM, 1.6, 2.4], [Vector2(-14.0, 3.4), 1.6, 2.4],
		[Vector2(2.8, -14.2), 1.4, 2.6], [Vector2(20.3, -0.4), 1.4, 2.2], [Vector2(10.6, 18.3), 1.4, 2.2]]
	for a in anchors:
		var c: Vector2 = a[0]
		var p := _find_spot(Vector3(c.x, 0, c.y), a[1], a[2], sun_angle(), PI, cat_rest_ok)
		if p.is_finite():
			cands.append(p)
	for k in 10:
		var p2 := _find_spot(Vector3.ZERO, 7.8, 10.5, TAU * float(k) / 10.0 + 0.3, 0.25, cat_rest_ok)
		if p2.is_finite():
			cands.append(p2)
	for p in cands:
		var far := true
		for s in village_sites:
			if (s[0] as Vector3).distance_to(p) < 4.0:
				far = false
				break
		if far:
			village_sites.append([p, null])


## The free village site farthest from the other cats' homes (ties: nearer the lighthouse).
func _spread_village_site() -> int:
	var best := -1
	var best_s := -INF
	for i in village_sites.size():
		var s: Array = village_sites[i]
		if s[1] != null:
			continue
		var p: Vector3 = s[0]
		var md := 12.0
		for c in cats:
			md = minf(md, c.home.distance_to(p))
		var score := md - Vector2(p.x, p.z).length() * 0.2
		if score > best_s:
			best_s = score
			best = i
	return best


## A free village site, nearest to `near`.
func _free_village_site(near: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in village_sites.size():
		var s: Array = village_sites[i]
		if s[1] != null:
			continue
		var d := (s[0] as Vector3).distance_to(near)
		if d < bd:
			bd = d
			best = i
	return best


## Random point around `anchor` between rmin and rmax metres, within `spread` of angle `ang`, that passes `ok`
## and keeps 2.5 m from the other cats' homes (or INF).
func _find_spot(anchor: Vector3, rmin: float, rmax: float, ang: float, spread: float, ok: Callable) -> Vector3:
	for tries in 50:
		var a := ang + rng.randf_range(-spread, spread) * (0.35 + 0.65 * float(tries) / 50.0)
		var d := rng.randf_range(rmin, rmax)
		var p := ground(Vector3(anchor.x + sin(a) * d, 0, anchor.z + cos(a) * d))
		if not ok.call(p):
			continue
		var free := true
		for c in cats:
			if c.home.distance_to(p) < 2.5:
				free = false
				break
		if free:
			return p
	return Vector3.INF


## Spot on the sunny side of house building `b` (outside its footprint, off the lanes), or INF.
func _house_site(b: Node3D) -> Vector3:
	var c := b.global_position
	var sun := sun_angle()
	for off in [0.0, 0.55, -0.55, 1.1, -1.1, 1.7, -1.7, PI]:
		var a: float = sun + float(off)
		var dir := Vector3(sin(a), 0, cos(a))
		# March out of the footprint, then a little further.
		var p := c
		for step in 40:
			p = c + dir * (1.0 + float(step) * 0.15)
			if island.spot_sd_at(p.x, p.z) > 1.75:
				break
		p += dir * rng.randf_range(0.0, 0.4)
		p = ground(p)
		if cat_rest_ok(p):
			var clash := false
			for o in cats:
				if o.home_house != b and o.home.distance_to(p) < 2.2:
					clash = true
					break
			if not clash:
				return p
	return Vector3.INF


## Gives every standing house a cat (house cats move in from the village sites, nearest first) and sends the
## cats of vanished houses back to the village. `instant` places them at once (new game, title screen).
func _update_houses(instant: bool = false) -> void:
	var houses: Array[Node3D] = []
	for u in Game.units[0]:
		if is_instance_valid(u) and u is Building and (u as Building).type == "house" and (u as Building).is_inside_tree() \
				and not (u as Building).is_queued_for_deletion():
			houses.append(u)
	# Cats whose house is gone go back to a village site.
	for c in cats:
		if c.home_house != null and (not is_instance_valid(c.home_house) or not houses.has(c.home_house)):
			c.home_house = null
			var si := _free_village_site(c.pos)
			if si >= 0:
				village_sites[si][1] = c
				c.set_home(village_sites[si][0], instant or not on_screen(c.pos))
	for h in houses:
		var taken := false
		for c in cats:
			if c.home_house == h:
				taken = true
				break
		if taken:
			continue
		var best: AmbientCat = null
		var bd := INF
		for c in cats:
			if not c.house_cat or c.home_house != null:
				continue
			var d := c.pos.distance_to(h.global_position)
			if d < bd:
				bd = d
				best = c
		if best == null:
			continue
		var site := _house_site(h)
		if not site.is_finite():
			continue
		for s in village_sites:
			if s[1] == best:
				s[1] = null
		best.home_house = h
		best.set_home(site, instant or (not on_screen(best.pos) and not on_screen(site)))


func _on_phase(p: int) -> void:
	# A new game (the first day, or a day straight after the title) starts with every cat at home, once the
	# title village is gone and any test village is up (next frame).
	if p == Game.Phase.DAY and (not _started or _last_phase == Game.Phase.TITLE):
		_rehome = true
		_started = true
	_last_phase = p


func _rehome_all() -> void:
	_rehome = false
	_sync_dynamic(true)
	_update_houses(true)
	for c in cats:
		c.reset_at_home()


# --- goats -------------------------------------------------------------------------------------------------

func _spawn_goats() -> void:
	# Score candidate herd centres on the wild hills: roomy, near a granite outcrop, away from the village.
	var outcrops: Array = []
	if props != null:
		var oc: Variant = props.get("outcrops")
		if oc is Array:
			outcrops = oc
	var cands: Array = []
	var step := 3.0
	var x := -66.0
	while x <= 66.0:
		var z := -66.0
		while z <= 66.0:
			var c := ground(Vector3(x, 0, z))
			if goat_ok(c):
				var room := 0
				for k in 12:
					var a := TAU * float(k) / 12.0
					for rr in [2.5, 5.0]:
						if goat_ok(ground(c + Vector3(cos(a), 0, sin(a)) * float(rr))):
							room += 1
				if room >= 8:
					var near_rock := INF
					for o in outcrops:
						near_rock = minf(near_rock, (o as Vector2).distance_to(Vector2(c.x, c.z)))
					var score := float(room) * 0.5 + (3.0 if near_rock < 9.0 else 0.0) + rng.randf() * 2.0
					cands.append([score, c, room])
			z += step
		x += step
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	# Roomy pastures first; a smaller patch will do for the last (smallest) herd.
	var herds: Array[Vector3] = []
	for pass_i in 2:
		for cd in cands:
			if herds.size() == HERDS.size() or (pass_i == 0 and int(cd[2]) < 14):
				continue
			var c: Vector3 = cd[1]
			var far := true
			for h in herds:
				if h.distance_to(c) < 26.0:
					far = false
			if far:
				herds.append(c)
	for hi in herds.size():
		var center := herds[hi]
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
				var q := ground(center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 4.0))
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
			var goat := AmbientGoat.new(self, coat, p, center, rng.randi(), kid)
			if kid:
				goat.mother = mother
			elif mother == null:
				mother = goat
			goats.append(goat)


# --- per frame ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ok:
		return
	var t0 := Time.get_ticks_usec() if _perf else 0
	var dt := minf(delta, 0.1)
	_cam = get_viewport().get_camera_3d()
	_vp = get_viewport().get_visible_rect().size
	_dyn_timer -= dt
	if _dyn_timer <= 0.0:
		_dyn_timer = 0.5
		_sync_dynamic()
	if _rehome:
		_rehome_all()
	_house_timer -= dt
	if _house_timer <= 0.0:
		_house_timer = 2.0
		_update_houses()
	var t1 := Time.get_ticks_usec() if _perf else 0
	for c in cats:
		c.tick(dt)
	var t2 := Time.get_ticks_usec() if _perf else 0
	for c in cats:
		c.rig.step(dt, on_screen(c.pos))
	var t3 := Time.get_ticks_usec() if _perf else 0
	for g in goats:
		g.tick(dt)
	var t4 := Time.get_ticks_usec() if _perf else 0
	for g in goats:
		g.rig.step(dt, on_screen(g.pos))
	if _perf:
		var t5 := Time.get_ticks_usec()
		_perf_acc[0] += t1 - t0
		_perf_acc[1] += t2 - t1
		_perf_acc[2] += t3 - t2
		_perf_acc[3] += t4 - t3
		_perf_acc[4] += t5 - t4
		_perf_n += 1
		if _perf_n == 300:
			var vis := 0
			for c in cats:
				if on_screen(c.pos):
					vis += 1
			print("Ambient ms/frame: misc %.3f cat-tick %.3f cat-pose %.3f goat-tick %.3f goat-pose %.3f (cats on screen %d)" % [_perf_acc[0] / 300000.0, _perf_acc[1] / 300000.0, _perf_acc[2] / 300000.0, _perf_acc[3] / 300000.0, _perf_acc[4] / 300000.0, vis])
			_perf_acc.fill(0)
			_perf_n = 0
