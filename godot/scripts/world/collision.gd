# Collision world (ARCHITECTURE §7): static + toggleable axis-aligned boxes in a 4 m XZ spatial hash, plus
# "ramp" floor shapes (a box whose top slopes down to its base over `inset` metres on every edge).
# Port of src/world/collision.js (Godot physics is NOT used: movement feel, zombie pathing and shots depend on this).
#
# Box flags (defaults come from the tag, explicit options win):
#   walkable  its top is standable (floors, platforms, stairs, props you may climb). A non-walkable box is a
#             pure obstacle: it blocks the circle whenever it rises above the feet.
#   solid     blocks moveCircle / nav            shots   blocks raycast / lineOfSight
#   camera    blocks sphereFree (camera collision)
# Tag defaults: window (player-only entry blockers) → not walkable, no shots (the camera does not pass: it would
# end up outside the building looking in through the boards); fence & lattice →
# not walkable, no shots; wall/door/glass/rail → not walkable. Any other tag (props, floors) → all true.
#
# API (JS names; GDScript conventions noted)
#   DACollision.new(opts := {bounds = [-128, -128, 192, 128]})   (level.gd: `col = DACollision.new()`)
#   addBox(min:[x,y,z]|Vector3, max:[x,y,z]|Vector3, {tag, id, walkable, solid, shots, camera}) → handle (a Box)
#   addRamp(rect:[x0,z0,x1,z1], y0, y1, inset, {tag, id}) → handle   (floor shape; never blocks sideways)
#   setEnabled(handleOrId, on)                     toggles one box or every box sharing that id
#   moveCircle(pos, delta, radius, height, stepUp=0.45, ignore=null, owner=null)
#       → { onGround, hitWall, groundY, normal, hitCeiling, pos }
#       JS mutated `pos` (feet); Vector3 is a value type here, so the moved feet position is returned in `res.pos`
#       and EVERY CALLER MUST WRITE IT BACK:   var r = col.moveCircle(z.pos, d, z.radius, z.height, 0.45, null, z)
#                                              z.pos = r.pos
#       Horizontal motion is sub-stepped (≤ 0.1 m) and pushed out of blockers (slides),
#       walkable boxes whose top is ≤ feet + stepUp are stepped onto (chains of steps climb, like stairs), and
#       ramps are followed. While grounded the feet snap down ≤ stepUp, so stairs and ramps are walked down
#       instead of fallen off; an airborne body lands when it reaches the floor.
#       "Grounded" was remembered per pos OBJECT in the JS (WeakMap). Here it is remembered per `owner`: pass the
#       object that owns `pos` (the zombie Dictionary `z`, the player object, telly's `walk` Dictionary …); the
#       flag is stored on it under the key/meta "_colGrounded" (Dictionary key, or Object meta). Every JS call that
#       passed the same pos object must pass the same owner (e.g. zombies pushing the player pass the player).
#       owner = null behaves like a fresh pos object (was grounded = true, nothing remembered).
#       The result Dictionary is reused between calls (like the JS). ignore = array of tags (or a mask from
#       maskOf()), e.g. ['window'] for a zombie climbing through its entry.
#   floorAt(x, z, yFrom=INF, stepUp=0.45) → highest walkable top at (x,z) that is ≤ yFrom + stepUp (-INF if none)
#   raycast(origin, dir, maxDist, {ignoreTags, camera}) → { dist, point, normal, tag, id } | null   (shots boxes;
#       camera:true tests the camera-blocking boxes instead: the third-person camera probe)
#   lineOfSight(a, b) → bool                       sphereFree(pos, r) → bool
#   blockedAt(x, z, r, floorY, stepUp, height, ignore?) → bool   (the moveCircle rule, for the nav grid)
#   maskOf(tags) → int                             boxes (Array of every Box record, read-only: change
#                                                  `enabled` with setEnabled; the setter also keeps the hash in sync)
#   DACollision.rampHeight(b, x, z)                (static)
# Engine notes (no gameplay change): the box data is mirrored in packed arrays (struct of arrays) for the hot
# loops; `cells` and `big` hold box INDICES (into `boxes`) instead of box records; the gather stamp lives in the
# packed `_stamps` array (Box has no `stamp` field). All maths runs on 64-bit floats like the JS; only the
# returned Vector3s are 32-bit. _navGrid() is a bulk floorAt + blockedAt for Nav.build (same results, one gather
# per hash cell instead of two per nav cell).
class_name DACollision
extends RefCounted

const CELL := 4.0
const EPS := 1e-4
const MAX_SUBSTEP := 0.1
const SUPPORT := 0.5       # ground support radius as a fraction of the body radius
const BIG_CELLS := 64      # boxes covering more cells than this live in an always-tested list

const TAG_DEFAULTS := {
	"window": {"walkable": false, "shots": false, "camera": true},
	"fence": {"walkable": false, "shots": false},
	"lattice": {"walkable": false, "shots": false},
	"wall": {"walkable": false},
	"door": {"walkable": false},
	"glass": {"walkable": false},
	"rail": {"walkable": false},
}

# packed flag bits (_flags)
const F_WALKABLE := 1
const F_SOLID := 2
const F_SHOTS := 4
const F_CAMERA := 8
const F_ENABLED := 16
const F_RAMP := 32

const GROUNDED_KEY := "_colGrounded"

# A box record (the JS plain object). Fields as JS; `index` = position in `boxes`.
class Box extends RefCounted:
	var tag: String = "prop"
	var id = null
	var bit: int = 0
	var minX: float = 0.0
	var minY: float = 0.0
	var minZ: float = 0.0
	var maxX: float = 0.0
	var maxY: float = 0.0
	var maxZ: float = 0.0
	var walkable: bool = true
	var solid: bool = true
	var shots: bool = true
	var camera: bool = true
	var ramp: float = 0.0
	var index: int = -1
	var _col: WeakRef = null
	var enabled: bool = true:
		set(v):
			enabled = v
			if _col != null:
				var c = _col.get_ref()
				if c != null:
					c._syncEnabled(index, v)

var boxes: Array[Box] = []
var bx0: float
var bz0: float
var nx: int
var nz: int
var cells: Array[PackedInt32Array] = []   # box indices per 4 m cell
var big := PackedInt32Array()              # box indices of the always-tested list
var _stamp := 1
var _tagBits := {}
var _byId := {}
var _list := PackedInt32Array()            # gather output (box indices) [0.._n)
var _n := 0

# struct-of-arrays mirror of the box records (hot loops)
var _mnx := PackedFloat64Array()
var _mny := PackedFloat64Array()
var _mnz := PackedFloat64Array()
var _mxx := PackedFloat64Array()
var _mxy := PackedFloat64Array()
var _mxz := PackedFloat64Array()
var _ramp := PackedFloat64Array()
var _flags := PackedInt32Array()
var _bits := PackedInt32Array()
var _stamps := PackedInt64Array()

# moveCircle scratch (JS: module-level _res; pos mutated by _resolve)
var _res := {"onGround": false, "hitWall": false, "groundY": -INF, "hitCeiling": false, "normal": Vector3.ZERO, "pos": Vector3.ZERO}
var _px := 0.0
var _pz := 0.0
# ray cast scratch (JS: module-level _hit)
var _hitT := 0.0
var _hitBox := -1
var _hitNx := 0.0
var _hitNy := 0.0
var _hitNz := 0.0

func _init(opts = null) -> void:
	var bounds = [-128.0, -128.0, 192.0, 128.0]
	if opts is Dictionary and opts.get("bounds") != null:
		bounds = opts.bounds
	bx0 = float(bounds[0])
	bz0 = float(bounds[1])
	nx = int(ceilf((float(bounds[2]) - float(bounds[0])) / CELL))
	nz = int(ceilf((float(bounds[3]) - float(bounds[1])) / CELL))
	cells.resize(nx * nz)
	for i in nx * nz:
		cells[i] = PackedInt32Array()

# ------------------------------------------------------------------------------------------ building
static func _c(v, i: int) -> float:
	return float(v[i])

static func _opt(opts: Dictionary, d: Dictionary, key: String) -> bool:
	var v = opts.get(key)
	if v == null:
		v = d.get(key)
	if v == null:
		return true
	return true if v else false

func addBox(min_v, max_v, opts = null) -> Box:
	if not (opts is Dictionary):
		opts = {}
	var tag = opts.get("tag")
	if not tag:
		tag = "prop"
	tag = String(tag)
	var d: Dictionary = TAG_DEFAULTS.get(tag, {})
	var b := Box.new()
	b.tag = tag
	b.id = opts.get("id")
	b.bit = _bit(tag)
	b.minX = minf(_c(min_v, 0), _c(max_v, 0))
	b.minY = minf(_c(min_v, 1), _c(max_v, 1))
	b.minZ = minf(_c(min_v, 2), _c(max_v, 2))
	b.maxX = maxf(_c(min_v, 0), _c(max_v, 0))
	b.maxY = maxf(_c(min_v, 1), _c(max_v, 1))
	b.maxZ = maxf(_c(min_v, 2), _c(max_v, 2))
	b.walkable = _opt(opts, d, "walkable")
	b.solid = _opt(opts, d, "solid")
	b.shots = _opt(opts, d, "shots")
	b.camera = _opt(opts, d, "camera")
	b.ramp = 0.0
	return _insert(b)

func addRamp(rect, y0: float, y1: float, inset: float, opts = null) -> Box:
	if not (opts is Dictionary):
		opts = {}
	var tag = opts.get("tag")
	if not tag:
		tag = "platform"
	tag = String(tag)
	var b := Box.new()
	b.tag = tag
	b.id = opts.get("id")
	b.bit = _bit(tag)
	b.minX = float(rect[0])
	b.minY = y0
	b.minZ = float(rect[1])
	b.maxX = float(rect[2])
	b.maxY = y1
	b.maxZ = float(rect[3])
	b.walkable = true
	b.solid = false
	b.shots = true
	b.camera = false
	b.ramp = inset
	return _insert(b)

func setEnabled(handleOrId, on) -> void:
	var v := true if on else false
	if handleOrId is Box:
		handleOrId.enabled = v
		return
	if handleOrId == null:
		return
	var list = _byId.get(handleOrId)
	if list != null:
		for b in list:
			b.enabled = v

# Box.enabled setter → packed flags.
func _syncEnabled(i: int, on: bool) -> void:
	if i < 0 or i >= _flags.size():
		return
	if on:
		_flags[i] |= F_ENABLED
	else:
		_flags[i] &= ~F_ENABLED

func maskOf(tags) -> int:
	if tags == null:
		return 0
	if tags is int:
		return tags
	if tags is float:
		return int(tags)
	if not tags and not (tags is Array):
		return 0
	var m := 0
	for t in tags:
		m |= _bit(String(t))
	return m

func _bit(tag: String) -> int:
	var bit = _tagBits.get(tag)
	if bit == null:
		bit = 1 << mini(30, _tagBits.size())
		_tagBits[tag] = bit
	return bit

func _cellI(x: float) -> int:
	var f := floorf((x - bx0) / CELL)
	return 0 if f < 0.0 else (nx - 1 if f >= nx else int(f))

func _cellK(z: float) -> int:
	var f := floorf((z - bz0) / CELL)
	return 0 if f < 0.0 else (nz - 1 if f >= nz else int(f))

func _insert(b: Box) -> Box:
	var idx := boxes.size()
	b.index = idx
	boxes.append(b)
	_mnx.append(b.minX)
	_mny.append(b.minY)
	_mnz.append(b.minZ)
	_mxx.append(b.maxX)
	_mxy.append(b.maxY)
	_mxz.append(b.maxZ)
	_ramp.append(b.ramp)
	_flags.append((F_WALKABLE if b.walkable else 0) | (F_SOLID if b.solid else 0) | (F_SHOTS if b.shots else 0)
		| (F_CAMERA if b.camera else 0) | (F_ENABLED if b.enabled else 0) | (F_RAMP if b.ramp != 0.0 else 0))
	_bits.append(b.bit)
	_stamps.append(0)
	b._col = weakref(self)
	if b.id != null:
		if not _byId.has(b.id):
			_byId[b.id] = []
		_byId[b.id].append(b)
	var i0 := _cellI(b.minX)
	var i1 := _cellI(b.maxX)
	var k0 := _cellK(b.minZ)
	var k1 := _cellK(b.maxZ)
	if (i1 - i0 + 1) * (k1 - k0 + 1) > BIG_CELLS:
		big.append(idx)
	else:
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1):
				cells[k * nx + i].append(idx)
	if _list.size() < boxes.size():
		_list.resize(boxes.size() + 64)
	return b

# Collect every enabled box overlapping the XZ rect into _list[0.._n) (each box once).
func _gather(minX: float, minZ: float, maxX: float, maxZ: float) -> int:
	var n := 0
	_stamp += 1
	var stamp := _stamp
	for bi in big:
		if (_flags[bi] & F_ENABLED) != 0 and _mxx[bi] >= minX and _mnx[bi] <= maxX and _mxz[bi] >= minZ and _mnz[bi] <= maxZ:
			_list[n] = bi
			n += 1
	var i0 := _cellI(minX)
	var i1 := _cellI(maxX)
	var k0 := _cellK(minZ)
	var k1 := _cellK(maxZ)
	for k in range(k0, k1 + 1):
		for i in range(i0, i1 + 1):
			for bi in cells[k * nx + i]:
				if _stamps[bi] == stamp:
					continue
				_stamps[bi] = stamp
				if (_flags[bi] & F_ENABLED) != 0 and _mxx[bi] >= minX and _mnx[bi] <= maxX and _mxz[bi] >= minZ and _mnz[bi] <= maxZ:
					_list[n] = bi
					n += 1
	_n = n
	return n

# --------------------------------------------------------------------------------------------- floor
static func rampHeight(b, x: float, z: float) -> float:
	var e := minf(minf(x - b.minX, b.maxX - x), minf(z - b.minZ, b.maxZ - z))
	var k := 0.0 if e <= 0.0 else (1.0 if e >= b.ramp else e / b.ramp)
	return b.minY + (b.maxY - b.minY) * k

func _rampH(bi: int, x: float, z: float) -> float:
	var e := minf(minf(x - _mnx[bi], _mxx[bi] - x), minf(z - _mnz[bi], _mxz[bi] - z))
	var r := _ramp[bi]
	var k := 0.0 if e <= 0.0 else (1.0 if e >= r else e / r)
	return _mny[bi] + (_mxy[bi] - _mny[bi]) * k

func floorAt(x: float, z: float, yFrom: float = INF, stepUp: float = 0.45) -> float:
	var lim := yFrom + stepUp + EPS
	var best := -INF
	var n := _gather(x, z, x, z)
	for j in n:
		var bi := _list[j]
		var f := _flags[bi]
		if (f & F_WALKABLE) == 0:
			continue
		var top: float = _rampH(bi, x, z) if (f & F_RAMP) != 0 else _mxy[bi]
		if top <= lim and top > best:
			best = top
	return best

# Highest walkable support under a disc among the gathered boxes (ramps sampled at the disc centre).
func _ground(x: float, z: float, r: float, lim: float, mask: int) -> float:
	var best := -INF
	var rr := r * r
	for j in _n:
		var bi := _list[j]
		var f := _flags[bi]
		if (f & F_WALKABLE) == 0 or (_bits[bi] & mask) != 0:
			continue
		var top: float
		if (f & F_RAMP) != 0:
			if x < _mnx[bi] or x > _mxx[bi] or z < _mnz[bi] or z > _mxz[bi]:
				continue
			top = _rampH(bi, x, z)
		else:
			# circleHitsRect
			var a := _mnx[bi]
			var b := _mxx[bi]
			var dx := x - (a if x < a else (b if x > b else x))
			a = _mnz[bi]
			b = _mxz[bi]
			var dz := z - (a if z < a else (b if z > b else z))
			if not (dx * dx + dz * dz < rr):
				continue
			top = _mxy[bi]
		if top <= lim and top > best:
			best = top
	return best

# Does box b stop a body standing at `feet`? (shared by moveCircle and blockedAt)
static func _blocks(b, feet: float, stepUp: float, height: float) -> bool:
	if not b.solid or b.ramp:
		return false
	if b.minY >= feet + height - EPS:
		return false
	if b.walkable:
		return b.maxY > feet + stepUp + EPS
	return b.maxY > feet + 0.02

func _blocksI(bi: int, feet: float, stepUp: float, height: float) -> bool:
	var f := _flags[bi]
	if (f & F_SOLID) == 0 or (f & F_RAMP) != 0:
		return false
	if _mny[bi] >= feet + height - EPS:
		return false
	if (f & F_WALKABLE) != 0:
		return _mxy[bi] > feet + stepUp + EPS
	return _mxy[bi] > feet + 0.02

func _getGrounded(owner) -> bool:
	if owner == null:
		return true
	if owner is Dictionary:
		return owner.get(GROUNDED_KEY, true)
	if owner is Object:
		return owner.get_meta(GROUNDED_KEY, true)
	return true

func _setGrounded(owner, on: bool) -> void:
	if owner == null:
		return
	if owner is Dictionary:
		owner[GROUNDED_KEY] = on
	elif owner is Object:
		owner.set_meta(GROUNDED_KEY, on)

# ------------------------------------------------------------------------------------------ movement
# Returns the reused result Dictionary; the moved feet position is res.pos (write it back: see the header).
func moveCircle(pos: Vector3, delta: Vector3, radius: float, height: float, stepUp: float = 0.45, ignore = null, owner = null) -> Dictionary:
	var mask := maskOf(ignore)
	var res := _res
	res.hitWall = false
	res.hitCeiling = false
	res.normal = Vector3.ZERO
	var wasGrounded := _getGrounded(owner)
	var px: float = pos.x
	var py: float = pos.y
	var pz: float = pos.z
	var ddx: float = delta.x
	var ddy: float = delta.y
	var ddz: float = delta.z

	# One gather covers the whole swept disc (plus the jump height for ceilings).
	var reach := radius + 0.05
	_gather(minf(px, px + ddx) - reach, minf(pz, pz + ddz) - reach, maxf(px, px + ddx) + reach, maxf(pz, pz + ddz) + reach)

	var len := sqrt(ddx * ddx + ddz * ddz)
	var steps := maxi(1, int(ceilf(len / minf(MAX_SUBSTEP, radius * 0.5))))
	var sx := ddx / steps
	var sz := ddz / steps
	var feet := py
	_px = px
	_pz = pz
	for s in steps:
		_px += sx
		_pz += sz
		feet = _resolve(radius, height, feet, stepUp, mask, res)
	px = _px
	pz = _pz

	# Vertical: support under the body (raised by any steps climbed this frame), ceilings when rising.
	var ground := _ground(px, pz, radius * SUPPORT, maxf(feet, py) + stepUp + EPS, mask)
	var y := py + ddy
	if ddy > 0.0:
		var head := py + height
		var r9 := radius * 0.9
		for j in _n:
			var bi := _list[j]
			var f := _flags[bi]
			var mnY := _mny[bi]
			if (f & F_SOLID) == 0 or (f & F_RAMP) != 0 or (_bits[bi] & mask) != 0 or mnY < head - EPS or mnY >= y + height:
				continue
			var a := _mnx[bi]
			var b := _mxx[bi]
			var cdx := px - (a if px < a else (b if px > b else px))
			a = _mnz[bi]
			b = _mxz[bi]
			var cdz := pz - (a if pz < a else (b if pz > b else pz))
			if not (cdx * cdx + cdz * cdz < r9 * r9):
				continue
			y = mnY - height
			res.hitCeiling = true
	var onGround := false
	if y <= ground:
		y = ground
		onGround = true
	elif wasGrounded and ddy <= 0.0 and py - ground <= stepUp + EPS:
		y = ground
		onGround = true
	py = y
	_setGrounded(owner, onGround)
	res.onGround = onGround
	res.groundY = ground
	res.pos = Vector3(px, py, pz)
	return res

# One horizontal sub-step over the gathered boxes: climb overlapped steps, then push the disc out of
# blockers. Moves (_px, _pz); returns the stand height used for blocking.
func _resolve(r: float, height: float, feet: float, stepUp: float, mask: int, res: Dictionary) -> float:
	var n := _n
	var rr2 := r * r
	# Step-up fixpoint: every walkable top ≤ stand + stepUp under the disc raises the stand height.
	var stand := feet
	for pass_i in 3:
		var before := stand
		for j in n:
			var bi := _list[j]
			var f := _flags[bi]
			if (f & F_WALKABLE) == 0 or (f & F_RAMP) != 0 or (f & F_SOLID) == 0 or (_bits[bi] & mask) != 0:
				continue
			var mxY := _mxy[bi]
			if mxY <= stand + EPS or mxY > stand + stepUp + EPS or _mny[bi] >= stand + height:
				continue
			var a := _mnx[bi]
			var b := _mxx[bi]
			var dx := _px - (a if _px < a else (b if _px > b else _px))
			a = _mnz[bi]
			b = _mxz[bi]
			var dz := _pz - (a if _pz < a else (b if _pz > b else _pz))
			if dx * dx + dz * dz < rr2:
				stand = mxY
		if stand == before:
			break
	# Push-out iterations (axis-aligned corners converge in two; four is headroom, no jitter).
	for it in 4:
		var moved := false
		for j in n:
			var bi := _list[j]
			if (_bits[bi] & mask) != 0:
				continue
			# Collision._blocks(b, stand, stepUp, height)
			var f := _flags[bi]
			if (f & F_SOLID) == 0 or (f & F_RAMP) != 0:
				continue
			if _mny[bi] >= stand + height - EPS:
				continue
			if (f & F_WALKABLE) != 0:
				if not (_mxy[bi] > stand + stepUp + EPS):
					continue
			elif not (_mxy[bi] > stand + 0.02):
				continue
			var mnX := _mnx[bi]
			var mxX := _mxx[bi]
			var mnZ := _mnz[bi]
			var mxZ := _mxz[bi]
			var cx := mnX if _px < mnX else (mxX if _px > mxX else _px)
			var cz := mnZ if _pz < mnZ else (mxZ if _pz > mxZ else _pz)
			var dx := _px - cx
			var dz := _pz - cz
			var d2 := dx * dx + dz * dz
			if d2 >= rr2:
				continue
			var push: float
			if d2 > 1e-12:
				var d := sqrt(d2)
				dx /= d
				dz /= d
				push = r - d
			else:
				# Centre inside the box: leave through the nearest face.
				var l := _px - mnX
				var rr := mxX - _px
				var nn := _pz - mnZ
				var s := mxZ - _pz
				var m := minf(minf(l, rr), minf(nn, s))
				dx = -1.0 if m == l else (1.0 if m == rr else 0.0)
				dz = 0.0 if dx != 0.0 else (-1.0 if m == nn else 1.0)
				push = m + r
			_px += dx * (push + EPS)
			_pz += dz * (push + EPS)
			res.hitWall = true
			res.normal = Vector3(dx, 0.0, dz)
			moved = true
		if not moved:
			break
	return stand

# The moveCircle blocking rule evaluated for a disc standing at floorY (nav grid clearance).
func blockedAt(x: float, z: float, r: float, floorY: float, stepUp: float, height: float, ignore = null) -> bool:
	var mask := maskOf(ignore)
	var n := _gather(x - r, z - r, x + r, z + r)
	for j in n:
		var bi := _list[j]
		if (_bits[bi] & mask) == 0 and _blocksI(bi, floorY, stepUp, height) and _circleHits(x, z, r, bi):
			return true
	return false

func _circleHits(x: float, z: float, r: float, bi: int) -> bool:
	var a := _mnx[bi]
	var b := _mxx[bi]
	var dx := x - (a if x < a else (b if x > b else x))
	a = _mnz[bi]
	b = _mxz[bi]
	var dz := z - (a if z < a else (b if z > b else z))
	return dx * dx + dz * dz < r * r

# Nav.build helper (engine optimisation, no JS counterpart): for every cell centre (x0 + (i + 0.5) * cell,
# z0 + (k + 0.5) * cell) of a w × h grid returns [heights, base] with
#   heights[idx] = floorAt(x, z, INF)
#   base[idx]    = 1 if heights[idx] > -INF and not blockedAt(x, z, r, heights[idx], stepUp, height, ignore) else 0
# evaluated with one gather per 4 m hash cell (a superset, filtered with the exact per-query overlap tests, so the
# results are identical to the per-cell calls).
func _navGrid(x0: float, z0: float, cell: float, w: int, h: int, r: float, stepUp: float, height: float, ignore) -> Array:
	var mask := maskOf(ignore)
	var heights := PackedFloat64Array()
	heights.resize(w * h)
	var base := PackedByteArray()
	base.resize(w * h)
	# group the cells by the hash cell of their centre
	var groups := {}
	for k in h:
		var z := z0 + (k + 0.5) * cell
		var hk := _cellK(z)
		for i in w:
			var x := x0 + (i + 0.5) * cell
			var key := hk * nx + _cellI(x)
			if not groups.has(key):
				groups[key] = PackedInt32Array()
			var g: PackedInt32Array = groups[key]
			g.append(k * w + i)
			groups[key] = g
	for key in groups:
		var idxs: PackedInt32Array = groups[key]
		# bounds of the member centres (plus the disc) → one gather
		var gx0 := INF
		var gx1 := -INF
		var gz0 := INF
		var gz1 := -INF
		for idx in idxs:
			var x := x0 + (idx % w + 0.5) * cell
			var z := z0 + (idx / w + 0.5) * cell
			gx0 = minf(gx0, x)
			gx1 = maxf(gx1, x)
			gz0 = minf(gz0, z)
			gz1 = maxf(gz1, z)
		var n := _gather(gx0 - r - 1.0, gz0 - r - 1.0, gx1 + r + 1.0, gz1 + r + 1.0)
		var cand := _list.slice(0, n)
		for idx in idxs:
			var i := idx % w
			var k := idx / w
			var x := x0 + (i + 0.5) * cell
			var z := z0 + (k + 0.5) * cell
			# floorAt(x, z, INF)
			var best := -INF
			for bi in cand:
				if not (_mxx[bi] >= x and _mnx[bi] <= x and _mxz[bi] >= z and _mnz[bi] <= z):
					continue
				var f := _flags[bi]
				if (f & F_WALKABLE) == 0:
					continue
				var top: float = _rampH(bi, x, z) if (f & F_RAMP) != 0 else _mxy[bi]
				if top <= INF and top > best:
					best = top
			heights[idx] = best
			if best == -INF:
				base[idx] = 0
				continue
			# blockedAt(x, z, r, best, stepUp, height, ignore)
			var blocked := false
			var qx0 := x - r
			var qx1 := x + r
			var qz0 := z - r
			var qz1 := z + r
			for bi in cand:
				if not (_mxx[bi] >= qx0 and _mnx[bi] <= qx1 and _mxz[bi] >= qz0 and _mnz[bi] <= qz1):
					continue
				if (_bits[bi] & mask) == 0 and _blocksI(bi, best, stepUp, height) and _circleHits(x, z, r, bi):
					blocked = true
					break
			base[idx] = 0 if blocked else 1
	return [heights, base]

# ------------------------------------------------------------------------------------------- queries
func raycast(origin: Vector3, dir: Vector3, maxDist: float, opts = null) -> Variant:
	var ignoreTags = null
	var cam := false
	if opts is Dictionary:
		ignoreTags = opts.get("ignoreTags")
		cam = true if opts.get("camera") else false
	var ox: float = origin.x
	var oy: float = origin.y
	var oz: float = origin.z
	var dx: float = dir.x
	var dy: float = dir.y
	var dz: float = dir.z
	if not _cast(ox, oy, oz, dx, dy, dz, maxDist, maskOf(ignoreTags), F_CAMERA if cam else F_SHOTS, false):
		return null
	var t := _hitT
	var b: Box = boxes[_hitBox]
	return {
		"dist": t,
		"point": Vector3(ox + dx * t, oy + dy * t, oz + dz * t),
		"normal": Vector3(_hitNx, _hitNy, _hitNz),
		"tag": b.tag,
		"id": b.id,
	}

func lineOfSight(a: Vector3, b: Vector3) -> bool:
	var ax: float = a.x
	var ay: float = a.y
	var az: float = a.z
	var dx: float = b.x - ax
	var dy: float = b.y - ay
	var dz: float = b.z - az
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-6:
		return true
	return not _cast(ax, ay, az, dx / d, dy / d, dz / d, d - 1e-3, 0, F_SHOTS, true)

func sphereFree(pos: Vector3, r: float) -> bool:
	var px: float = pos.x
	var py: float = pos.y
	var pz: float = pos.z
	var n := _gather(px - r, pz - r, px + r, pz + r)
	for j in n:
		var bi := _list[j]
		var f := _flags[bi]
		if (f & F_CAMERA) == 0 or (f & F_RAMP) != 0:
			continue
		var cx := maxf(_mnx[bi], minf(px, _mxx[bi])) - px
		var cy := maxf(_mny[bi], minf(py, _mxy[bi])) - py
		var cz := maxf(_mnz[bi], minf(pz, _mxz[bi])) - pz
		if cx * cx + cy * cy + cz * cz < r * r:
			return false
	return true

# Grid DDA over the XZ hash; slab test per box. anyHit=true returns at the first hit (line of sight).
# Returns true on a hit (details in _hitT/_hitBox/_hitN*).
func _cast(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, maxDist: float, mask: int, flag: int, anyHit: bool) -> bool:
	_hitT = maxDist
	_hitBox = -1
	_stamp += 1
	var stamp := _stamp
	for bi in big:
		if (_flags[bi] & F_ENABLED) != 0 and (_flags[bi] & flag) != 0 and (_bits[bi] & mask) == 0 and _slab(ox, oy, oz, dx, dy, dz, bi, _hitT) and anyHit:
			return true
	var i := int(floorf((ox - bx0) / CELL))
	var k := int(floorf((oz - bz0) / CELL))
	var stepI := 1 if dx > 0.0 else -1
	var stepK := 1 if dz > 0.0 else -1
	var tDeltaI := CELL / absf(dx) if absf(dx) > 1e-9 else INF
	var tDeltaK := CELL / absf(dz) if absf(dz) > 1e-9 else INF
	var tMaxI := (bx0 + (i + (1 if stepI > 0 else 0)) * CELL - ox) / dx if absf(dx) > 1e-9 else INF
	var tMaxK := (bz0 + (k + (1 if stepK > 0 else 0)) * CELL - oz) / dz if absf(dz) > 1e-9 else INF
	var tCell := 0.0
	while tCell <= _hitT:
		if i >= 0 and i < nx and k >= 0 and k < nz:
			for bi in cells[k * nx + i]:
				if _stamps[bi] == stamp:
					continue
				_stamps[bi] = stamp
				var f := _flags[bi]
				if (f & F_ENABLED) != 0 and (f & flag) != 0 and (_bits[bi] & mask) == 0 and _slab(ox, oy, oz, dx, dy, dz, bi, _hitT) and anyHit:
					return true
		if tMaxI < tMaxK:
			tCell = tMaxI
			tMaxI += tDeltaI
			i += stepI
		else:
			tCell = tMaxK
			tMaxK += tDeltaK
			k += stepK
		if tCell == INF:
			break
		if (i < 0 and stepI < 0) or (i >= nx and stepI > 0) or (k < 0 and stepK < 0) or (k >= nz and stepK > 0):
			break
	return _hitBox >= 0

# Ray/AABB slab test; ramps are tested as their flat plateau. Records into _hit* when nearer than tMax.
# Boxes containing the origin are skipped so rays can leave a volume. (JS slab + slabAxis, inlined.)
func _slab(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, bi: int, tMax: float) -> bool:
	var ins := _ramp[bi]
	var minX := _mnx[bi] + ins
	var maxX := _mxx[bi] - ins
	var minZ := _mnz[bi] + ins
	var maxZ := _mxz[bi] - ins
	var minY := _mny[bi]
	var maxY := _mxy[bi]
	if ox >= minX and ox <= maxX and oy >= minY and oy <= maxY and oz >= minZ and oz <= maxZ:
		return false
	var t0 := 0.0
	var t1 := tMax
	var axis := -1
	var sign := 0.0
	# x
	if absf(dx) < 1e-12:
		if not (ox >= minX and ox <= maxX):
			return false
	else:
		var inv := 1.0 / dx
		var ta := (minX - ox) * inv
		var tb := (maxX - ox) * inv
		var s := -1.0
		if ta > tb:
			var t := ta
			ta = tb
			tb = t
			s = 1.0
		if ta > t0:
			t0 = ta
			axis = 0
			sign = s
		if tb < t1:
			t1 = tb
		if not (t0 <= t1):
			return false
	# y
	if absf(dy) < 1e-12:
		if not (oy >= minY and oy <= maxY):
			return false
	else:
		var inv := 1.0 / dy
		var ta := (minY - oy) * inv
		var tb := (maxY - oy) * inv
		var s := -1.0
		if ta > tb:
			var t := ta
			ta = tb
			tb = t
			s = 1.0
		if ta > t0:
			t0 = ta
			axis = 1
			sign = s
		if tb < t1:
			t1 = tb
		if not (t0 <= t1):
			return false
	# z
	if absf(dz) < 1e-12:
		if not (oz >= minZ and oz <= maxZ):
			return false
	else:
		var inv := 1.0 / dz
		var ta := (minZ - oz) * inv
		var tb := (maxZ - oz) * inv
		var s := -1.0
		if ta > tb:
			var t := ta
			ta = tb
			tb = t
			s = 1.0
		if ta > t0:
			t0 = ta
			axis = 2
			sign = s
		if tb < t1:
			t1 = tb
		if not (t0 <= t1):
			return false
	if axis < 0 or t0 >= tMax:
		return false
	_hitT = t0
	_hitBox = bi
	_hitNx = sign if axis == 0 else 0.0
	_hitNy = sign if axis == 1 else 0.0
	_hitNz = sign if axis == 2 else 0.0
	return true
