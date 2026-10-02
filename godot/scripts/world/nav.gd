# Navigation (ARCHITECTURE §7, GDD §5.10): a 0.5 m grid over the whole footprint and an 8-neighbour Dijkstra
# flow field toward the player (or a goal override), recomputed at most every 0.25 s when the goal changes
# cell (or a door opens), time-sliced so a solve never costs more than BUDGET_MS in one frame.
# Port of src/world/nav.js (the `nav` system: game.nav).
#
# Cell = walkable when a walkable top exists under its centre and a 0.35 m agent standing there is not
# blocked (same rule as Collision.moveCircle). Door cells (within the agent radius of a door blocker) stay
# blocked until setDoor(id, true). Moves between cells climb ≤ STEP_UP and drop ≤ DROP; diagonals may not cut
# corners; cells hugging obstacles cost a little more so paths keep off the walls.
#
# API: build() (lazy on first use; call again after adding colliders), reset(), update(dt),
#      setDoor(id, open), setGoalOverride(pos|null), localField(x, z, maxDist) → { dist, dir } (bounded 2nd field),
#      dir(x, z) → Vector3 (unit XZ toward the goal, ZERO if unreachable; the JS filled an `out` vector:
#      `nav.dir(x, z, _d)` becomes `_d = nav.dir(x, z)`), dist(x, z) → metres | INF,
#      walkable(x, z) → bool, heightAt(x, z) → floor y | -INF, solveNow(x, z) (complete solve: tests, debug views),
#      debugImage(mode='dist'|'height') → { width, height, data: PackedByteArray RGBA, x0, z0, cell }
#      (row 0 = north edge z0; column 0 = west edge x0; Image.create_from_data(width, height, false,
#      Image.FORMAT_RGBA8, data) makes it an image).
# localField returns a LocalField object (one shared instance: a new call re-solves it) with `goal`, `field` and
#      the methods dist(x, z) → float and dir(x, z) → Vector3 (same conventions as Nav.dist/dir).
# Reads game.level.col (DACollision), game.player.pos (Vector3) and FOOTPRINT from scripts/world/layout.gd
# (Layout.FOOTPRINT; falls back to the JS constant {x0:-7, z0:-30, x1:51, z1:6} if the layout is not loaded).
# Engine notes (no gameplay change; the fields, dir/dist answers and debug images are bit-identical to the JS,
# verified by tools/test_collision_nav.gd):
#   * per-cell caches: `_openC` (= _open(idx); refreshed by build/reset/setDoor), `_rin` (bit n: the move from
#     neighbour n into the cell is inside the grid and passes the height rule of _link), `_wc` (near ? WALL_COST : 0);
#   * the Dijkstra loop (_run) is unrolled and shared by the player field and localField;
#   * a bucket queue (0.5 m buckets) replaces the binary heap: the field is the unique fixed point
#     back[v] = min over legal neighbours u of f32(back[u] + step + near cost), so the pop order does not change
#     it (see _push); `heap`/`heapKey`/`heapN` keep their JS names as the queue entries;
#   * the time budget is checked every 16 pops instead of 128 (GDScript pops are slower): a full station solve
#     with every door open takes ~5-10 ms of GDScript, i.e. a few 1.5 ms slices (one frame in the JS);
#   * distances are stored in PackedFloat32Array exactly like the JS Float32Array (same rounding), and
#     Math.hypot is reproduced bit-exactly (DACollision.hypot2);
#   * Nav.build uses DACollision._navGrid (a bulk floorAt + blockedAt, same results).
# The JS `_pop` is inlined in _run.
# MP: on the host of an online game (game.net.inGame) the field is seeded from EVERY target (zombies.targetsList())
#   and each cell remembers which target reached it (frontOwn / goals): ownerAt(x, z) -> goal index, goalIdAt(x, z)
#   -> peer id (0 none); dir() heads straight for the owning target; dist() = path to the nearest target. Clients run
#   no solve (update() returns; queries still work). Solo / lure override: the single-goal code above, unchanged.
extends RefCounted

const CELL := 0.5
const AGENT_R := 0.35
const AGENT_H := 1.7
const STEP_UP := 0.45
const DROP := 0.9
const WALL_COST := 0.25
const PERIOD := 0.25
const BUDGET_MS := 1.5
const SEED_R := 1.0
const SQRT2 := 1.4142135623730951   # Math.SQRT2
const DIAG := CELL * SQRT2
const IGNORE := ["door"]

const DI := [1, -1, 0, 0, 1, 1, -1, -1]
const DK := [0, 0, 1, -1, 1, -1, 1, -1]
const OPP := [1, 0, 3, 2, 7, 6, 5, 4]

const FOOTPRINT_DEFAULT := {"x0": -7.0, "z0": -30.0, "x1": 51.0, "z1": 6.0}
const LAYOUT_PATH := "res://scripts/world/layout.gd"
const CHECK_EVERY := 15             # budget check mask (every 16 pops)
const Col := preload("res://scripts/world/collision.gd")

# The bounded second field returned by localField (JS: L.api = { goal, dist, dir }).
class LocalField extends RefCounted:
	var goal := {"x": 0.0, "z": 0.0, "cell": -1}
	var field := PackedFloat32Array()
	var heap := PackedInt32Array()
	var key := PackedFloat32Array()
	var next := PackedInt32Array()
	var bucket := PackedInt32Array()
	var _nav: WeakRef
	func _init(nav) -> void:
		_nav = weakref(nav)
	func dist(px: float, pz: float) -> float:
		var nav = _nav.get_ref()
		return nav.dist(px, pz, field) if nav != null else INF
	func dir(px: float, pz: float) -> Vector3:
		var nav = _nav.get_ref()
		return nav.dir(px, pz, field, goal) if nav != null else Vector3.ZERO

var game
var cell := CELL
var x0: float
var z0: float
var w: int
var h: int
var height := PackedFloat64Array()
var base := PackedByteArray()          # 1 = walkable ignoring doors
var doorOf := PackedInt32Array()       # door index per cell, -1 = none
var near := PackedByteArray()          # 1 = next to an obstacle (extra cost)
var front := PackedFloat32Array()
var back := PackedFloat32Array()
var heap := PackedInt32Array()        # queue entries: cell   (bucket queue, see _push)
var heapKey := PackedFloat32Array()    # queue entries: key (Float32 like the JS heapKey)
var heapN := 0                         # live entries
var _next := PackedInt32Array()        # queue entries: next entry in the same bucket
var _bucket := PackedInt32Array()      # first entry per 0.5 m key bucket (-1 = empty)
var _cur := 0                          # lowest possibly non-empty bucket
var _entN := 0                         # entries used
var doorIds: Array = []
var doorOpen := {}
var built := false
var override = null                    # Vector3 | null
var goal := {"x": 0.0, "z": 0.0, "cell": -1}        # goal of the `front` field
var _pending := {"x": 0.0, "z": 0.0, "cell": -1}
var _solving := false
var _dirty := true
var _t := PERIOD
var _lf: LocalField = null
# caches (see the header)
var _openC := PackedByteArray()        # _open(idx) per cell
var _doorCells := PackedInt32Array()   # cells with doorOf >= 0
var _rin := PackedByteArray()          # bit n: the move neighbour n → idx is legal by bounds + height rule
var _wc := PackedFloat64Array()        # near[idx] ? WALL_COST : 0
# MP (multi-target field, host only; see the MP paragraph in the header)
var goals: Array = []                  # [{x, z, cell, id}] the targets the current `front` was seeded from
var frontOwn := PackedByteArray()      # per cell: index in goals of the target that reached it (255 = none)
var backOwn := PackedByteArray()
var _lab := false                      # the running solve labels its cells
var _multiFront := false               # `front` is a labelled multi-target field
var _seedOwn := 0
var _pendingGoals: Array = []
var _di := PackedInt32Array(DI)
var _dk := PackedInt32Array(DK)
var _opp := PackedInt32Array(OPP)

func _init(game_ref) -> void:
	game = game_ref
	var fp := _footprint()
	x0 = float(fp.x0)
	z0 = float(fp.z0)
	w = int(roundf((float(fp.x1) - float(fp.x0)) / CELL))
	h = int(roundf((float(fp.z1) - float(fp.z0)) / CELL))
	var n := w * h
	height.resize(n)
	height.fill(-INF)
	base.resize(n)
	doorOf.resize(n)
	doorOf.fill(-1)
	near.resize(n)
	front.resize(n)
	front.fill(INF)
	back.resize(n)
	back.fill(INF)
	heap.resize(n * 8 + 64)
	heapKey.resize(n * 8 + 64)
	_next.resize(n * 8 + 64)
	_bucket.resize(1024)
	_bucket.fill(-1)
	_openC.resize(n)
	_rin.resize(n)
	_wc.resize(n)

static func _footprint() -> Dictionary:
	if ResourceLoader.exists(LAYOUT_PATH):
		var L = load(LAYOUT_PATH)
		if L != null:
			var fp = L.get("FOOTPRINT")
			if fp is Dictionary and fp.has("x0") and fp.has("z0") and fp.has("x1") and fp.has("z1"):
				return fp
	return FOOTPRINT_DEFAULT

# ------------------------------------------------------------------------------------------- building
func build() -> void:
	var lvl = game.get("level") if game != null else null
	var col = lvl.get("col") if lvl != null else null
	if col == null:
		return
	doorIds = []
	doorOf.fill(-1)
	if col.has_method("_navGrid"):
		var g: Array = col._navGrid(x0, z0, CELL, w, h, AGENT_R, STEP_UP, AGENT_H, IGNORE)
		height = g[0]
		base = g[1]
	else:
		for k in h:
			for i in w:
				var idx := k * w + i
				var x := x0 + (i + 0.5) * CELL
				var z := z0 + (k + 0.5) * CELL
				var y: float = col.floorAt(x, z, INF)
				height[idx] = y
				base[idx] = 1 if y > -INF and not col.blockedAt(x, z, AGENT_R, y, STEP_UP, AGENT_H, IGNORE) else 0
	# Door membership: cells whose agent disc touches a door blocker.
	for b in col.boxes:
		if b.tag != "door" or b.id == null:
			continue
		var d := doorIds.find(b.id)
		if d < 0:
			d = doorIds.size()
			doorIds.append(b.id)
		var c0 := _cellXY(b.minX - AGENT_R, b.minZ - AGENT_R)
		var c1 := _cellXY(b.maxX + AGENT_R, b.maxZ + AGENT_R)
		for k in range(maxi(0, c0[1]), mini(h - 1, c1[1]) + 1):
			for i in range(maxi(0, c0[0]), mini(w - 1, c1[0]) + 1):
				var x := x0 + (i + 0.5) * CELL
				var z := z0 + (k + 0.5) * CELL
				var dx: float = x - maxf(b.minX, minf(x, b.maxX))
				var dz: float = z - maxf(b.minZ, minf(z, b.maxZ))
				if dx * dx + dz * dz < AGENT_R * AGENT_R:
					doorOf[k * w + i] = d
	# near (JS loop) + caches: _rin[u] bit n = neighbour v = u + (DI[n], DK[n]) is inside the grid and the height
	# rule of _link allows the move v → u; _wc[u] = the wall-hugging extra cost of u.
	var hw := w
	var hh := h
	var up := STEP_UP + 0.01
	for k in hh:
		for i in hw:
			var u := k * hw + i
			var hu := height[u]
			var nr := 0
			var rin := 0
			for n in 8:
				var ii: int = i + _di[n]
				var kk: int = k + _dk[n]
				if ii < 0 or kk < 0 or ii >= hw or kk >= hh:
					nr = 1
					continue
				var v := kk * hw + ii
				if base[v] == 0:
					nr = 1
				var dh := hu - height[v]
				if not (dh > up or -dh > DROP):
					rin |= 1 << n
			near[u] = nr
			_rin[u] = rin
			_wc[u] = WALL_COST if nr != 0 else 0.0
	_doorCells = PackedInt32Array()
	for idx in w * h:
		if doorOf[idx] >= 0:
			_doorCells.append(idx)
	_refreshOpen(true)
	built = true
	_solving = false
	_dirty = true
	front.fill(INF)
	goal.cell = -1

# _openC[idx] = _open(idx) as the JS evaluates it (base, door cells follow doorOpen).
func _refreshOpen(all: bool) -> void:
	if _openC.size() != base.size():
		return
	if all:
		for idx in w * h:
			_openC[idx] = base[idx]
	for idx: int in _doorCells:
		var open := 0
		if base[idx] != 0:
			var v = doorOpen.get(doorIds[doorOf[idx]])
			open = 1 if (v is bool and v) else 0
		_openC[idx] = open

func reset() -> void:
	doorOpen.clear()
	override = null
	_multiFront = false
	_dirty = true
	if built:
		_refreshOpen(false)

func setDoor(id, open) -> void:
	doorOpen[id] = true if open else false
	_dirty = true
	if built:
		_refreshOpen(false)

func setGoalOverride(pos) -> void:
	if pos == null:
		override = null
	elif pos is Vector3:
		override = pos
	else:
		override = DAU.v3(pos)
	_dirty = true

# ----------------------------------------------------------------------------------------------- update
func update(dt: float) -> void:
	if not built:
		build()
		if not built:
			return
	var net = game.get("net") if game != null else null
	if net != null and net.inGame and net.isClient:
		return                          # MP client: no AI runs here (queries still work)
	_t += dt
	if not _solving and net != null and net.inGame and override == null:
		_updateMulti()
	elif not _solving:
		var g = override
		if g == null:
			var p = game.get("player") if game != null else null
			g = p.get("pos") if p != null else null
		if g == null:
			return
		var c := _cellIndex(g.x, g.z)
		if _t >= PERIOD and (_dirty or c != goal.cell):
			_t = 0.0
			_dirty = false
			_start(g.x, g.z, c)
	if _solving:
		_step(BUDGET_MS)

# Complete solve right now (tests, debug views).
func solveNow(x: float, z: float) -> void:
	if not built:
		build()
		if not built:
			return
	_start(x, z, _cellIndex(x, z))
	_step(INF)

func _open(idx: int) -> bool:
	return _openC[idx] != 0

# Can an agent step from cell a to neighbour b (direction n)?
func _link(a: int, b: int, n: int) -> bool:
	if _openC[b] == 0:
		return false
	var dh := height[b] - height[a]
	if dh > STEP_UP + 0.01 or -dh > DROP:
		return false
	if n >= 4:
		var ai := a % w
		var ak := (a - ai) / w
		var s1: int = ak * w + ai + _di[n]
		var s2: int = (ak + _dk[n]) * w + ai
		if _openC[s1] == 0 or _openC[s2] == 0:
			return false
	return true

# MP host: one field seeded from every target (zombies.targetsList()); re-solved like the single field.
func _updateMulti() -> void:
	var Z = game.get("zombies")
	var T: Array = Z.targetsList() if Z != null and Z.has_method("targetsList") else game.net.targets()
	if T.is_empty():
		return                          # nobody to chase: keep the last field
	var list: Array = []
	for p in T:
		if list.size() >= 254:
			break
		var pp: Vector3 = p.pos
		list.append({"x": pp.x, "z": pp.z, "cell": _cellIndex(pp.x, pp.z), "id": int(game.net.idOf(p))})
	var changed := _dirty or not _multiFront or list.size() != goals.size()
	if not changed:
		for i in list.size():
			if list[i].id != goals[i].id or list[i].cell != goals[i].cell:
				changed = true
				break
	if _t >= PERIOD and changed:
		_t = 0.0
		_dirty = false
		_startMulti(list)

func _startMulti(list: Array) -> void:
	back.fill(INF)
	if backOwn.size() != back.size():
		backOwn.resize(back.size())
		frontOwn.resize(back.size())
		frontOwn.fill(255)
	backOwn.fill(255)
	_clearQueue()
	_pending.x = list[0].x
	_pending.z = list[0].z
	_pending.cell = list[0].cell
	_pendingGoals = list
	_lab = true
	for i in list.size():
		_seedOwn = i
		_seed(list[i].x, list[i].z, list[i].cell)
	_solving = true

func _start(x: float, z: float, c: int) -> void:
	_lab = false
	back.fill(INF)
	_clearQueue()
	_pending.x = x
	_pending.z = z
	_pending.cell = c
	_seed(x, z, c)
	_solving = true

# Seed the goal cell, or (goal on a prop / in a wall-hugging cell) every open cell within SEED_R (into back/heap).
func _seed(x: float, z: float, c: int) -> void:
	if c >= 0 and _openC[c] != 0:
		back[c] = 0.0
		if _lab:
			backOwn[c] = _seedOwn
		_push(c, 0.0)
	else:
		var cc := _cellXY(x, z)
		var ci: int = cc[0]
		var ck: int = cc[1]
		var r := int(ceilf(SEED_R / CELL))
		for k in range(maxi(0, ck - r), mini(h - 1, ck + r) + 1):
			for i in range(maxi(0, ci - r), mini(w - 1, ci + r) + 1):
				var idx := k * w + i
				if _openC[idx] == 0:
					continue
				var d := Col.hypot2(x0 + (i + 0.5) * CELL - x, z0 + (k + 0.5) * CELL - z)
				if d <= SEED_R and d < back[idx]:
					back[idx] = d
					if _lab:
						backOwn[idx] = _seedOwn
					_push(idx, d)

func _step(budgetMs: float) -> void:
	if not _run(budgetMs, INF):
		return
	var tmp := front
	front = back
	back = tmp
	if _lab:
		var to := frontOwn
		frontOwn = backOwn
		backOwn = to
		goals = _pendingGoals
		_multiFront = true
		_lab = false
	else:
		_multiFront = false
	goal.x = _pending.x
	goal.z = _pending.z
	goal.cell = _pending.cell
	_solving = false

# The Dijkstra loop of _step (and of localField, which swaps its own arrays in): pops until the heap is empty
# (→ true) or the budget is spent (→ false). Cells popped farther than `limit` are not expanded (localField).
# JS per neighbour n of u: `if (!this._link(v, u, OPP[n])) continue;` = _open(u) (once per u), the height rule
# v → u (_rin[u] bit n, static, also encodes the grid bounds) and, for diagonals, both side cells open;
# nd = du + (n < 4 ? CELL : CELL * SQRT2) + (near[v] ? WALL_COST : 0)   (_wc[v] = that last term).
func _run(budgetMs: float, limit: float) -> bool:
	var t0 := Time.get_ticks_usec()
	var budgetUs := budgetMs * 1000.0
	var ww := w
	var pops := 0
	var lab := _lab
	var ou := 0
	while heapN > 0:
		pops += 1
		if (pops & CHECK_EVERY) == 0 and Time.get_ticks_usec() - t0 > budgetUs:
			return false
		# pop (inlined): the first entry of the lowest non-empty bucket
		while _bucket[_cur] < 0:
			_cur += 1
		var e := _bucket[_cur]
		_bucket[_cur] = _next[e]
		heapN -= 1
		var u := heap[e]
		var du := heapKey[e]
		if du > back[u] or du > limit:
			continue
		if _openC[u] == 0:
			continue
		var rin := _rin[u]
		if rin == 0:
			continue
		if lab:
			ou = backOwn[u]
		var v := 0
		var nd := 0.0
		var bk := 0
		# relax v → u for each legal neighbour (push inlined)
		if (rin & 1) != 0:	# n = 0 (1,0)
			v = u + 1
			nd = du + CELL + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 2) != 0:	# n = 1 (-1,0)
			v = u - 1
			nd = du + CELL + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 4) != 0:	# n = 2 (0,1)
			v = u + ww
			nd = du + CELL + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 8) != 0:	# n = 3 (0,-1)
			v = u - ww
			nd = du + CELL + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 16) != 0 and _openC[u + ww] != 0 and _openC[u + 1] != 0:	# n = 4 (1,1)
			v = u + ww + 1
			nd = du + DIAG + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 32) != 0 and _openC[u - ww] != 0 and _openC[u + 1] != 0:	# n = 5 (1,-1)
			v = u - ww + 1
			nd = du + DIAG + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 64) != 0 and _openC[u + ww] != 0 and _openC[u - 1] != 0:	# n = 6 (-1,1)
			v = u + ww - 1
			nd = du + DIAG + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
		if (rin & 128) != 0 and _openC[u - ww] != 0 and _openC[u - 1] != 0:	# n = 7 (-1,-1)
			v = u - ww - 1
			nd = du + DIAG + _wc[v]
			if nd < back[v]:
				back[v] = nd
				if lab:
					backOwn[v] = ou
				heap[_entN] = v
				heapKey[_entN] = nd
				bk = int(heapKey[_entN] * 2.0)
				if bk >= _bucket.size():
					_growBuckets(bk)
				_next[_entN] = _bucket[bk]
				_bucket[bk] = _entN
				_entN += 1
				heapN += 1
	return true

# Priority queue. The JS uses a binary heap; this is a bucket queue with 0.5 m buckets (= the smallest step
# cost): a cell popped from bucket b can only push keys >= (b + 1) * 0.5, so every pop order the buckets allow
# settles each cell at the same value as the heap order (the field is the unique fixed point
# back[v] = min over legal neighbours u of f32(back[u] + step + near cost)). Identical results, no sift loops.
func _push(idx: int, key: float) -> void:
	var e := _entN
	_entN += 1
	heap[e] = idx
	heapKey[e] = key
	var b := int(heapKey[e] * 2.0)
	if b >= _bucket.size():
		_growBuckets(b)
	if b < _cur:
		_cur = b
	_next[e] = _bucket[b]
	_bucket[b] = e
	heapN += 1

func _growBuckets(b: int) -> void:
	var old := _bucket.size()
	_bucket.resize(maxi(b + 1, old * 2))
	for i in range(old, _bucket.size()):
		_bucket[i] = -1

func _clearQueue() -> void:
	_bucket.fill(-1)
	heapN = 0
	_entN = 0
	_cur = 0

# ---------------------------------------------------------------------------------------------- queries
func _cellXY(x: float, z: float) -> Array:
	return [int(floorf((x - x0) / CELL)), int(floorf((z - z0) / CELL))]

func _cellIndex(x: float, z: float) -> int:
	var fi := floorf((x - x0) / CELL)
	var fk := floorf((z - z0) / CELL)
	if not (fi >= 0.0 and fk >= 0.0 and fi < w and fk < h):
		return -1
	return int(fk) * w + int(fi)

# Best reached cell for a position: its own cell, else the cheapest reached neighbour.
func _bestCell(x: float, z: float, fr: PackedFloat32Array) -> int:
	var c := _cellIndex(x, z)
	if c < 0:
		return -1
	if fr[c] < INF:
		return c
	var ci := c % w
	var ck := (c - ci) / w
	var best := -1
	var bd := INF
	for n in 8:
		var i: int = ci + _di[n]
		var k: int = ck + _dk[n]
		if i < 0 or k < 0 or i >= w or k >= h:
			continue
		var v := k * w + i
		if fr[v] < bd:
			bd = fr[v]
			best = v
	return best

func dist(x: float, z: float, fr = null) -> float:
	if not built:
		build()
	var f: PackedFloat32Array = front if fr == null else fr
	var c := _bestCell(x, z, f)
	if c < 0:
		return INF
	var ci := c % w
	var ck := (c - ci) / w
	var off := Col.hypot2(x0 + (ci + 0.5) * CELL - x, z0 + (ck + 0.5) * CELL - z)
	return f[c] + (0.0 if c == _cellIndex(x, z) else off)

func dir(x: float, z: float, fr = null, gl = null) -> Vector3:
	if not built:
		build()
	var f: PackedFloat32Array = front if fr == null else fr
	var g: Dictionary = goal if gl == null else gl
	var c := _bestCell(x, z, f)
	if c < 0:
		return Vector3.ZERO
	if fr == null and gl == null and _multiFront:
		var o := frontOwn[c]
		if o < goals.size():
			g = goals[o]                # MP: head straight for the target that owns this cell
	var ci := c % w
	var ck := (c - ci) / w
	var cx := x0 + (ci + 0.5) * CELL
	var cz := z0 + (ck + 0.5) * CELL
	var d0 := f[c]
	var gx: float = g.x - x
	var gz: float = g.z - z
	var straight := Col.hypot2(g.x - cx, g.z - cz)
	# Goal cell, or the path is (nearly) the straight line: head straight for the goal (no 45° zig-zag).
	if d0 == 0.0 or d0 <= straight * 1.06 + 0.3:
		var l := Col.hypot2(gx, gz)
		if l > 1e-4:
			return Vector3(gx / l, 0.0, gz / l)
		return Vector3.ZERO
	var best := -1
	var bd := d0
	for n in 8:
		var i: int = ci + _di[n]
		var k: int = ck + _dk[n]
		if i < 0 or k < 0 or i >= w or k >= h:
			continue
		var v := k * w + i
		if f[v] < bd and _link(c, v, n):
			bd = f[v]
			best = v
	if best < 0:
		return Vector3.ZERO
	var bi := best % w
	var bk := (best - bi) / w
	var tx := x0 + (bi + 0.5) * CELL - x
	var tz := z0 + (bk + 0.5) * CELL - z
	var l := Col.hypot2(tx, tz)
	if l > 1e-4:
		return Vector3(tx / l, 0.0, tz / l)
	return Vector3.ZERO

# Bounded second field toward (x, z), solved synchronously (Tiny Tele lure: only zombies within `maxDist` metres
# of PATH distance are lured; the others keep the player's field). Returns the LocalField { goal, dist(x, z),
# dir(x, z) }. One shared instance: a new call re-solves it.
func localField(x: float, z: float, maxDist: float = 15.0) -> LocalField:
	if not built:
		build()
	var n := w * h
	if _lf == null:
		_lf = LocalField.new(self)
		_lf.field.resize(n)
		_lf.heap.resize(n * 8 + 64)
		_lf.key.resize(n * 8 + 64)
		_lf.next.resize(n * 8 + 64)
		_lf.bucket.resize(1024)
		_lf.bucket.fill(-1)
	var L := _lf
	var labSave := _lab
	_lab = false
	# Solve into L's arrays with the shared loop: the (possibly half-done, time-sliced) player solve state is
	# parked meanwhile. The arrays are detached from L while in use (no copy-on-write).
	var park := [back, heap, heapKey, _next, _bucket, heapN, _entN, _cur]
	back = L.field
	heap = L.heap
	heapKey = L.key
	_next = L.next
	_bucket = L.bucket
	L.field = PackedFloat32Array()
	L.heap = PackedInt32Array()
	L.key = PackedFloat32Array()
	L.next = PackedInt32Array()
	L.bucket = PackedInt32Array()
	back.fill(INF)
	_clearQueue()
	var c := _cellIndex(x, z)
	L.goal.x = x
	L.goal.z = z
	L.goal.cell = c
	_seed(x, z, c)
	_run(INF, maxDist + 2.0)
	L.field = back
	L.heap = heap
	L.key = heapKey
	L.next = _next
	L.bucket = _bucket
	back = park[0]
	heap = park[1]
	heapKey = park[2]
	_next = park[3]
	_bucket = park[4]
	heapN = park[5]
	_entN = park[6]
	_cur = park[7]
	_lab = labSave
	return L

# MP: index in `goals` of the target whose path reaches (x, z) first (-1 without a labelled field / unreachable).
func ownerAt(x: float, z: float) -> int:
	if not _multiFront:
		return -1
	var c := _bestCell(x, z, front)
	if c < 0:
		return -1
	var o := frontOwn[c]
	return o if o < goals.size() else -1

# MP: peer id of that target (0 = none).
func goalIdAt(x: float, z: float) -> int:
	var o := ownerAt(x, z)
	return int(goals[o].id) if o >= 0 else 0

func walkable(x: float, z: float) -> bool:
	if not built:
		build()
	var c := _cellIndex(x, z)
	return c >= 0 and _openC[c] != 0

func heightAt(x: float, z: float) -> float:
	if not built:
		build()
	var c := _cellIndex(x, z)
	return height[c] if c >= 0 and base[c] != 0 else -INF

# ------------------------------------------------------------------------------------------------ debug
func debugImage(mode: String = "dist") -> Dictionary:
	if not built:
		build()
	var n := w * h
	var data := PackedByteArray()
	data.resize(n * 4)
	var maxD := 1.0
	for i in n:
		if front[i] < INF and front[i] > maxD:
			maxD = front[i]
	for i in n:
		var o := i * 4
		var door := doorOf[i]
		if door >= 0 and base[i] != 0:
			var v = doorOpen.get(doorIds[door])
			var open: bool = v is bool and v
			if open:
				_put(data, o, 80, 230, 120, 220)
			else:
				_put(data, o, 235, 60, 50, 230)
			continue
		if base[i] == 0:
			_put(data, o, 20, 12, 28, 170)
			continue
		var rgb: Array
		if mode == "height":
			var v := minf(1.0, maxf(0.0, height[i] / 1.5))
			rgb = _hsl(0.62 - v * 0.62, 0.8, 0.45 + v * 0.2)
		elif front[i] == INF:
			rgb = [0.45, 0.45, 0.5]
		else:
			var v := front[i] / maxD
			rgb = _hsl(0.33 - v * 0.33 + fmod(floorf(front[i]), 2.0) * 0.02, 0.85, 0.5)
		data[o] = _u8c(rgb[0] * 255.0)
		data[o + 1] = _u8c(rgb[1] * 255.0)
		data[o + 2] = _u8c(rgb[2] * 255.0)
		data[o + 3] = 150
	return {"width": w, "height": h, "data": data, "x0": x0, "z0": z0, "cell": CELL}

static func _put(data: PackedByteArray, o: int, r: int, g: int, b: int, a: int) -> void:
	data[o] = r
	data[o + 1] = g
	data[o + 2] = b
	data[o + 3] = a

# Uint8ClampedArray store (ToUint8Clamp: round half to even).
static func _u8c(v: float) -> int:
	if is_nan(v) or v <= 0.0:
		return 0
	if v >= 255.0:
		return 255
	var f := floorf(v)
	if f + 0.5 < v:
		return int(f) + 1
	if v < f + 0.5:
		return int(f)
	return int(f) if int(f) % 2 == 0 else int(f) + 1

# THREE.Color.setHSL (working colour space: no conversion) → [r, g, b].
static func _hsl(hh: float, s: float, l: float) -> Array:
	hh = fmod(fmod(hh, 1.0) + 1.0, 1.0)
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	if s == 0.0:
		return [l, l, l]
	var p := l * (1.0 + s) if l <= 0.5 else l + s - (l * s)
	var q := (2.0 * l) - p
	return [_hue2rgb(q, p, hh + 1.0 / 3.0), _hue2rgb(q, p, hh), _hue2rgb(q, p, hh - 1.0 / 3.0)]

static func _hue2rgb(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 1.0 / 2.0:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p
