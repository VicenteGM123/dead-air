# Windows and Yard entries (GDD §5.4, §5.9): frames per window style, the six scenery-flat boards of every
# boarded window with animated tear/repair, the fence-climb spots and the ajar chain-link vehicle gate.
# (Port of src/world/windows.js.) The frames, fence climbs and the gate are static geometry built by
# blender/world/windows.py into the architecture GLB (under each window's area root: window_<id>, climb_<id>,
# gate_<id>); the six board meshes (one per scenery slice, UVs on the board atlas) come from
# res://assets/world/boards.glb (nodes boards_0..boards_5).
# Boards are instanced (GDD §3.9): one MultiMeshInstance3D per scenery slice (sky, brick, fence, stars, sunset,
# hedge), one instance per boarded window, so all 78 boards cost 6 draw calls. Board k of a window is present
# iff k < boards: tearing removes the top-most present board, repairing puts back the lowest missing one.
#
# buildWindows(ctx) -> { list: Win[], boards: BoardSet }   ctx = { game, surf, root (the 'boards' group) }
# Win (becomes level.windows[id]): every layout field (inside/outside/spawn stay arrays) plus
#   boards (live count), pos (Vector3 inside point at 1 m), spawnPos, outsidePos (Vector3),
#   boardMeshes: 6 handles { slice, present, local:{pos, rot}, position:Vector3, quaternion:Quaternion }
#   (instanced, not meshes), breakBoard() -> bool (emits barricade:break {id, boards}, sound board_tear),
#   breakAll() -> count, repairBoard() -> bool (emits barricade:repair {id, boards}, sound board_repair), reset().
# Fence climbs and the gate are Win objects with 0 boards (their break/repair calls return false).
#
# Renames (SPEC §3.2): Win.set (the BoardSet) -> Win.set_; BoardSet.set(slice, index, matrix) -> set_().
extends RefCounted

const Surf = preload("res://scripts/world/surfaces.gd")
const BOARDS_GLB := "res://assets/world/boards.glb"
const SLICES := 6
const BOARD_H := 0.22
const BOARD_T := 0.05
const TEAR_TIME := 0.95
const REPAIR_TIME := 0.3
const FRAME_PROUD := 0.05
const ZERO := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

static func buildWindows(ctx: Dictionary) -> Dictionary:
	var boarded := Layout.WINDOWS.filter(func(w): return w.type == "boarded")
	var boards := BoardSet.new(ctx, boarded.size())
	var list := []
	for w in Layout.WINDOWS:
		list.append(Win.new(ctx, w, boards, boarded.find(w)))
	boards.commit()
	return {"list": list, "boards": boards}


# ------------------------------------------------------------------------------------------ board instances
class BoardSet extends RefCounted:
	var meshes: Array = []
	var active := {}       # Win -> true (a Set)

	func _init(ctx: Dictionary, count: int) -> void:
		var src := {}
		if ResourceLoader.exists(BOARDS_GLB):
			var scn = load(BOARDS_GLB)
			if scn is PackedScene:
				var inst: Node = scn.instantiate()
				Surf.applyDa(ctx.get("game"), inst, ctx.get("surf"))
				for k in SLICES:
					var mi := inst.find_child("boards_%d" % k, true, false) as MeshInstance3D
					if mi != null:
						src[k] = [mi.mesh, Surf.meshMat(mi)]
				inst.free()
		for k in SLICES:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "boards_%d" % k
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			if src.has(k):
				mm.mesh = src[k][0]
				mmi.material_override = src[k][1]
			mm.instance_count = maxi(1, count)
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			DAU.ud(mmi).dynamic = true
			ctx.root.add_child(mmi)
			meshes.append(mmi)

	func set_(slice: int, index: int, m: Transform3D) -> void:
		meshes[slice].multimesh.set_instance_transform(index, m)

	func commit() -> void:
		pass   # MultiMesh uploads on change (three's instanceMatrix.needsUpdate)

	func update(dt: float) -> void:
		for w in active.keys():
			if not w.animate(dt):
				active.erase(w)


# --------------------------------------------------------------------------------------------------- window
class Win extends RefCounted:
	# layout fields
	var id: String
	var label: String
	var area: String
	var type: String
	var style: String
	var boards := 0
	var inside: Array
	var outside: Array
	var spawn: Array
	var spawns: Array
	var rotY := 0.0
	var width := 0.0
	var sill := 0.0
	var top := 0.0
	var line: Array
	var span: Array
	var wall: Array
	var entryTime = 0.0

	var game
	var set_: BoardSet
	var index := -1
	var pivot := Transform3D.IDENTITY      # the JS pivot Object3D's matrixWorld
	var pos := Vector3.ZERO
	var spawnPos := Vector3.ZERO
	var outsidePos := Vector3.ZERO
	var boardMeshes: Array = []
	var _anim: Array = []
	var _bulk := false               # MP: breakAll sends one message for all its boards

	static func rnd(a: float, b: float) -> float:
		return a + randf() * (b - a)

	static func H() -> float:
		return Layout.WALL_T / 2.0

	static func eulerQuat(e: Vector3) -> Quaternion:
		return Basis.from_euler(e, EULER_ORDER_XYZ).get_rotation_quaternion()

	func _init(ctx: Dictionary, data: Dictionary, bset: BoardSet, idx: int) -> void:
		for k in data:
			if k in self:
				set(k, data[k])
		game = ctx.get("game")
		set_ = bset
		index = idx
		var nIn := Vector3(data.inside[0] - data.outside[0], 0, data.inside[2] - data.outside[2]).normalized()
		pivot = Transform3D(Basis(Vector3.UP, atan2(nIn.x, nIn.z)), Vector3(data.wall[0], 0, data.wall[1]))
		pos = Vector3(data.inside[0], data.inside[1] + 1.0, data.inside[2])
		spawnPos = DAU.v3(data.spawn)
		outsidePos = DAU.v3(data.outside)
		boardMeshes = []
		_anim = []
		_anim.resize(SLICES)
		if type == "boarded":
			_layoutBoards()
		else:
			boards = 0     # buildClimb / buildGate (their geometry is static, in the architecture GLB)

	# Rest pose of the six boards (window-local): 4 near-horizontal slats + 2 crossing diagonals in front.
	func _layoutBoards() -> void:
		var h := top - sill
		var diag := minf(0.62, atan2(h * 0.55, 1.9))
		for k in SLICES:
			var horiz := k < 4
			var y := sill + (h * (k + 0.5)) / 4.0 + rnd(-0.03, 0.03) if horiz else sill + h * 0.5 + (0.05 if k == 4 else -0.05)
			var rz := rnd(0.035, 0.12) * (1.0 if k % 2 else -1.0) if horiz else (diag if k == 4 else -diag)
			# In front of the frame (FRAME_PROUD): the lowest layer's back clears the frame face by 2 mm.
			var local := {"pos": Vector3(rnd(-0.06, 0.06), y, H() + FRAME_PROUD + 0.027 + k * 0.012), "rot": Vector3(0, 0, rz)}
			var wm := pivot * Transform3D(Basis(eulerQuat(local.rot)), local.pos)
			var handle := {"slice": k, "present": true, "local": local, "position": wm.origin, "quaternion": wm.basis.get_rotation_quaternion()}
			boardMeshes.append(handle)
		reset()

	func _place(k: int, p: Vector3, q: Quaternion, scale: float) -> void:
		var m := pivot * Transform3D(Basis(q).scaled(Vector3(scale, scale, scale)), p)
		set_.set_(k, index, m)

	# MP: on a client only the host's board messages (level.net_boards) may change boards.
	func _netBlocked() -> bool:
		var n = game.get("net") if game != null else null
		return n != null and n.inGame and n.isClient and not (game.level != null and game.level.get("_netApply") == true)

	# MP host: the new count to every client (level.net_boards(id, boards, op) op 0 tear / 1 repair / 2 blast).
	func _netSend(op: int) -> void:
		var n = game.get("net") if game != null else null
		if not _bulk and n != null and n.inGame and n.isHost:
			n.toAll("level", "boards", [id, boards, op])

	func breakBoard() -> bool:
		if boards <= 0 or _netBlocked():
			return false
		boards -= 1
		var k := boards
		var b: Dictionary = boardMeshes[k]
		b.present = false
		_anim[k] = {
			"type": "tear", "t": 0.0,
			"v": Vector3(rnd(-1, 1), rnd(1.5, 3), -rnd(2.5, 4)),
			"w": Vector3(rnd(-6, 6), rnd(-3, 3), rnd(-9, 9)),
			"p": b.local.pos, "r": b.local.rot,
		}
		set_.active[self] = true
		if game != null and game.events != null:
			game.events.emit("barricade:break", {"id": id, "boards": boards})
		if game != null and game.audio != null:
			game.audio.play("board_tear", {"pos": pos})
		_netSend(0)
		return true

	func breakAll() -> int:
		var n := 0
		_bulk = true
		while breakBoard():
			n += 1
		_bulk = false
		if n > 0:
			_netSend(2)
		return n

	func repairBoard() -> bool:
		if type != "boarded" or boards >= SLICES or _netBlocked():
			return false
		var k := boards
		boards += 1
		var b: Dictionary = boardMeshes[k]
		b.present = true
		_anim[k] = {
			"type": "repair", "t": 0.0,
			"p": Vector3(rnd(-0.5, 0.5), 0.05, H() + 0.9),
			"q": eulerQuat(Vector3(-PI / 2.0, 0, rnd(-0.6, 0.6))),
		}
		set_.active[self] = true
		if game != null and game.events != null:
			game.events.emit("barricade:repair", {"id": id, "boards": boards})
		if game != null and game.audio != null:
			game.audio.play("board_repair", {"pos": pos})
		_netSend(1)
		return true

	func reset() -> void:
		if type != "boarded":
			boards = 0
			return
		boards = SLICES
		_anim.fill(null)
		for k in boardMeshes.size():
			var b: Dictionary = boardMeshes[k]
			b.present = true
			_place(k, b.local.pos, eulerQuat(b.local.rot), 1.0)

	# Advances board animations; returns true while any is running.
	func animate(dt: float) -> bool:
		var busy := false
		for k in SLICES:
			var a = _anim[k]
			if a == null:
				continue
			a.t += dt
			var b: Dictionary = boardMeshes[k]
			if a.type == "tear":
				var t: float = minf(a.t, TEAR_TIME)
				var p: Vector3 = a.p + a.v * t
				p.y += -7.0 * t * t
				if p.y < 0.05:
					p.y = 0.05
				var e := Vector3(a.r.x + a.w.x * t, a.w.y * t, a.r.z + a.w.z * t)
				var s := 1.0 - DAU.smoothstep3(t, TEAR_TIME * 0.65, TEAR_TIME)
				if a.t >= TEAR_TIME:
					set_.set_(k, index, ZERO)
					_anim[k] = null
					continue
				_place(k, p, eulerQuat(e), s)
			else:
				var k01: float = minf(1.0, a.t / REPAIR_TIME)
				var e := 1.0 + 2.2 * pow(k01 - 1.0, 3.0) + 1.2 * pow(k01 - 1.0, 2.0)
				var p: Vector3 = (a.p as Vector3).lerp(b.local.pos, e)
				p.y += sin(PI * k01) * 0.45
				var q: Quaternion = (a.q as Quaternion).slerp(eulerQuat(b.local.rot), minf(1.0, e))
				_place(k, p, q, 1.0)
				if k01 >= 1.0:
					_anim[k] = null
					continue
			busy = true
		return busy
