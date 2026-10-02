# The eight purchasable/powered doors (GDD §5.3): casing, the blocker art per `look` and its opening beat
# (port of src/world/doors.js; the geometry of every look is built by blender/world/doors.py into
# res://assets/world/doors/<doorId>.glb, this class finds its animated pieces by name and plays the beats).
#   glass_chained  D1 smoked glass double doors, "ACTION 13 NEWS", chained: the chain snaps, the doors swing
#   padded         D2 tufted red "EMPLOYEES ONLY" doors with brass studs: they burst open in a stuffing puff
#   debris_desk    D3 toppled desk, film-can stacks, chair and a moving blanket: everything tumbles away
#   soundstage     D4 padded plum soundstage doors with portholes and a dark ON AIR box: heavy swing
#   steel_keypad   D5 steel ENGINEERING doors + keypad: 4 keypad flashes (G4-C5-E5-G5 cue), LED green, swing
#   elephant       D6 plywood scene-dock door on a track: shudders, then rumbles sideways along the wall
#   debris_cables  D7 waterfall of patch cables over puppet crates: cables zip up, crates tumble away
#   fire_exit      DY red fire door with push bars and an EXIT sign: buzzes, then swings out to the Yard
# Door-local frame: origin at the opening centre on the floor, +x along the opening, +z toward areas[1]
# (every door opens toward areas[1]). ON AIR boxes hang over both faces of the doors flagged onAir.
#
# Door.new(ctx, data) — ctx = { game, surf }; the instance carries every layout field plus:
#   open (bool), group (Node3D added by Level, name door_<id>), pos (Vector3, opening centre at 1.3 m),
#   approach ({ areaId: Vector3 } 1.1 m in front of each face), normal (Vector3 toward areas[1]), meshes ([group]),
#   onAirBoxes ([{face, dark, lit}]), play(instant) (runs the beat; Level does colliders/nav/events), update(dt),
#   reset(), setOnAir(on), busy.
#
# GLB node names (door-local; see blender/world/doors.py): pivot / frame, blocker; blocker children: leaf_0
# (s = -1, hinge at x = -w) and leaf_1 (s = +1), chain_0..chain_2 + lock (D1), blanket + piece_0..piece_8 (D3:
# desk, 3 can stacks, 3 loose cans, chair, papers), panel (D6), cables + piece_0..piece_3 (D7 crates); frame
# children: onair_face_0 / onair_face_1 (+ their boxes; "da".mats {dark, lit}), keypad (D5: kp_btn_6, kp_btn_0,
# kp_btn_2, kp_btn_4, kp_led; "da".mats {off, on, ledOff, ledOn}), exit_sign (DY).
#
# Not ported (engine plumbing): _bake()/_unbake() (the merged draw-call copy of an open door's blocker).
extends RefCounted

const Anim = preload("res://scripts/world/anim.gd")
const Surf = preload("res://scripts/world/surfaces.gd")
const GLB_DIR := "res://assets/world/doors/"
const OPEN := 2.9

# layout fields (Object.assign(this, data))
var id: String
var label: String
var cost = 0
var areas: Array = []
var rect: Array = []
var y0 := 0.0
var y1 := 0.0
var width := 0.0
var height := 0.0
var line: Array = []
var span: Array = []
var center: Array = []
var look: String
var requiresPower := false
var keypad := false
var onAir := false

var game
var surf
var open := false
var busy := false
var normal := Vector3.ZERO
var pos := Vector3.ZERO
var approach := {}
var group: Node3D
var pivot: Node3D
var frame: Node3D
var blocker: Node3D
var meshes: Array = []
var onAirBoxes: Array = []
var _tl
var _debris
var _resets: Array = []
var _silent := false
var _rest: Array = []
var _beat: Callable = func(): pass
var _from = null                       # MP: the buyer's position for this beat (debris flies away from it)

func _init(ctx: Dictionary, data: Dictionary) -> void:
	for k in data:
		if k in self:
			set(k, data[k])
	game = ctx.get("game")
	surf = ctx.get("surf")
	open = false
	busy = false
	var cx: float = data.center[0]
	var cz: float = data.center[1]
	var axis: String = data.line[0]
	var at: float = data.line[1]
	var n := [1.0, 0.0] if axis == "x" else [0.0, 1.0]
	if Layout.areaAt(cx + n[0] * 0.5, cz + n[1] * 0.5) != data.areas[1]:
		n[0] = -n[0]
		n[1] = -n[1]
	normal = Vector3(n[0], 0, n[1])
	pos = Vector3(at if axis == "x" else cx, 1.3, at if axis == "z" else cz)
	approach = {
		data.areas[0]: Vector3(cx - n[0] * 1.1, 0, cz - n[1] * 1.1),
		data.areas[1]: Vector3(cx + n[0] * 1.1, 0, cz + n[1] * 1.1),
	}
	group = DAU.node3d("door_" + id)
	_load()
	pivot.position = Vector3(cx, 0, cz)
	pivot.rotation_order = EULER_ORDER_XYZ
	pivot.rotation = Vector3(0, atan2(n[0], n[1]), 0)
	meshes = [group]
	onAirBoxes = []
	_tl = Anim.Timeline.new()
	_debris = Anim.Debris.new()
	_resets = []
	_silent = false
	if has_method("_look_" + look):
		call("_look_" + look)
	if onAir:
		for i in 2:
			_onAirBox(i)
	_rest = []
	DAU.traverse(blocker, func(o):
		if o != blocker and o is Node3D:
			o.rotation_order = EULER_ORDER_XYZ
			_rest.append([o, o.transform, o.visible])
	)

# Instantiates the door GLB and moves its pivot (frame + blocker) under `group`; empty stand-ins if missing.
func _load() -> void:
	var path := GLB_DIR + id + ".glb"
	var inst: Node = null
	if ResourceLoader.exists(path):
		var scn = load(path)
		if scn is PackedScene:
			inst = scn.instantiate()
	if inst != null:
		pivot = inst.find_child("pivot", true, false) as Node3D
	if pivot == null:
		pivot = DAU.node3d("pivot")
	else:
		pivot.get_parent().remove_child(pivot)
		DAU.traverse(pivot, func(o): o.owner = null)
	if inst != null:
		inst.free()
	pivot.transform = Transform3D.IDENTITY
	group.add_child(pivot)
	frame = pivot.get_node_or_null("frame") as Node3D
	if frame == null:
		frame = DAU.node3d("frame")
		pivot.add_child(frame)
	blocker = pivot.get_node_or_null("blocker") as Node3D
	if blocker == null:
		blocker = DAU.node3d("blocker")
		pivot.add_child(blocker)
	DAU.ud(blocker).dynamic = true
	Surf.applyDa(game, pivot, surf)

# from: the position of whoever opened it (MP: the buyer; null = the local player).
func play(instant: bool = false, from = null) -> void:
	_tl.clear()
	_debris.clear()
	_silent = instant
	_from = from if from is Vector3 else null
	_beat.call()
	_from = null
	if instant:
		_tl.finish()
		_debris.finish()
		busy = false
	else:
		busy = true
	_silent = false

func update(dt: float) -> void:
	if not busy:
		return
	var a: bool = _tl.update(dt)
	var b: bool = _debris.update(dt)
	busy = a or b

func reset() -> void:
	_tl.clear()
	_debris.clear()
	busy = false
	for r in _rest:
		r[0].transform = r[1]
		r[0].visible = r[2]
	for fn in _resets:
		fn.call()
	open = false

func setOnAir(on: bool) -> void:
	for b in onAirBoxes:
		b.face.material_override = b.lit if on else b.dark

# ---------------------------------------------------------------------------------------- beat helpers
func sound(sid: String) -> void:
	if not _silent and game != null and game.audio != null:
		game.audio.play(sid, {"pos": pos})

func puff(colors: Array) -> void:
	var fx = game.fx if game != null else null
	if _silent or fx == null or not fx.has_method("burst"):
		return
	fx.burst(pos, {"count": 22, "colors": colors, "speed": 3.2, "size": 0.28, "life": 0.8, "gravity": -0.6, "shape": "puff"})

# +1 / -1: the local z side away from the player (debris flies away from whoever bought the door).
func away() -> int:
	var p = _from if _from != null else (game.player.pos if game != null and game.player != null and game.player.get("pos") != null else null)
	if p == null:
		return 1
	var xf: Transform3D = pivot.global_transform if pivot.is_inside_tree() else pivot.transform
	return -1 if (xf.affine_inverse() * (p as Vector3)).z > 0.0 else 1

func swing(leaf: Node3D, s: float, start: float, dur: float, back: float = 1.4) -> void:
	if leaf == null:
		return
	_tl.span(start, dur, func(k): leaf.rotation.y = s * OPEN * Anim.ease_.outBack(k, back))

func tumble(pieces: Array, opts: Dictionary = {}) -> void:
	var start: float = opts.get("start", 0.0)
	var spread: float = opts.get("spread", 0.25)
	var up: Array = opts.get("up", [2.5, 5.0])
	var out: Array = opts.get("out", [2.0, 4.0])
	var life: Array = opts.get("life", [0.8, 1.2])
	var side := away()
	for i in pieces.size():
		_debris.launch(pieces[i], [rnd(-1.5, 1.5), rnd(up[0], up[1]), side * rnd(out[0], out[1])],
			[rnd(-8, 8), rnd(-6, 6), rnd(-8, 8)],
			{"delay": start + (spread * i) / maxf(1.0, pieces.size() - 1), "life": rnd(life[0], life[1]), "radius": 0.12})

static func rnd(a: float, b: float) -> float:
	return a + randf() * (b - a)

# ON AIR box `i` (0 = the areas[0] face, 1 = the areas[1] face): its face mesh swaps dark/lit.
func _onAirBox(i: int) -> void:
	var face := frame.find_child("onair_face_%d" % i, true, false) as MeshInstance3D
	if face == null:
		return
	DAU.ud(face).noMerge = true
	var m := _mats(face)
	var dark: Material = m.get("dark", Surf.meshMat(face))
	var lit: Material = m.get("lit", dark)
	face.material_override = dark
	onAirBoxes.append({"face": face, "dark": dark, "lit": lit})

# The node's alternate materials ("da".mats {name: spec}) built with the node's imported texture.
func _mats(n: Node) -> Dictionary:
	var out := {}
	var da = Surf.nodeDa(n)
	if da == null or not (da.get("mats") is Dictionary):
		return out
	var base: Material = Surf.importedMat(n as MeshInstance3D) if n is MeshInstance3D else null
	for k in da.mats:
		out[k] = Surf.matFromSpec(game, da.mats[k], base)
	return out

func _node(name: String) -> Node3D:
	return pivot.find_child(name, true, false) as Node3D

func _leaves() -> Array:
	return [blocker.get_node_or_null("leaf_0"), blocker.get_node_or_null("leaf_1")]

func _pieces(prefix: String, n: int) -> Array:
	var out := []
	for i in n:
		var p := blocker.get_node_or_null("%s%d" % [prefix, i]) as Node3D
		if p != null:
			out.append(p)
	return out

# ---------------------------------------------------------------------------------------------------- looks
func _look_glass_chained() -> void:
	var lv := _leaves()
	var pieces := _pieces("chain_", 3)
	var lock := blocker.get_node_or_null("lock") as Node3D
	if lock != null:
		pieces.append(lock)
	_beat = func():
		sound("door_chain_snap")
		var side := away()
		for p in pieces:
			_debris.launch(p, [rnd(-2.5, 2.5), rnd(1.5, 4), -side * rnd(0.6, 2)], [rnd(-14, 14), rnd(-14, 14), rnd(-14, 14)],
				{"life": rnd(0.5, 0.9), "radius": 0.04})
		swing(lv[0], -1, 0.18, 0.75, 1.2)
		swing(lv[1], 1, 0.22, 0.75, 1.2)

func _look_padded() -> void:
	var lv := _leaves()
	_beat = func():
		sound("door_poof")
		swing(lv[0], -1, 0, 0.55, 1.7)
		swing(lv[1], 1, 0.03, 0.55, 1.7)
		puff(["#F6E7C8", "#FFFFFF", "#B5472A"])

func _look_debris_desk() -> void:
	var pieces := _pieces("piece_", 9)
	var blanket := blocker.get_node_or_null("blanket") as Node3D
	var h := height
	_beat = func():
		sound("door_poof")
		tumble(pieces, {"spread": 0.3})
		_tl.span(0.05, 0.4, func(k):
			if blanket == null:
				return
			var s := maxf(0.02, 1.0 - k)
			blanket.scale.y = s
			blanket.position.y = (h * s) / 2.0
			if k >= 1.0:
				blanket.visible = false
		)
		_tl.at(0.9, func(): puff(["#C9C2B0", "#F4F1E8"]))

func _look_soundstage() -> void:
	var lv := _leaves()
	_beat = func():
		sound("door_poof")
		swing(lv[0], -1, 0, 0.95, 0.9)
		swing(lv[1], 1, 0.05, 0.95, 0.9)

func _look_steel_keypad() -> void:
	var lv := _leaves()
	var kp := frame.find_child("keypad", true, false)
	var m := _mats(kp) if kp != null else {}
	var seq := []
	for i in [6, 0, 2, 4]:
		var b := frame.find_child("kp_btn_%d" % i, true, false) as MeshInstance3D
		if b != null:
			seq.append(b)
	var led := frame.find_child("kp_led", true, false) as MeshInstance3D
	var base: Material = Surf.importedMat(seq[0]) if seq.size() > 0 else null
	var off: Material = m.get("off", Surf.meshMat(seq[0]) if seq.size() > 0 else base)
	var on: Material = m.get("on", off)
	var ledOff: Material = m.get("ledOff", Surf.meshMat(led))
	var ledOn: Material = m.get("ledOn", ledOff)
	for b in seq:
		b.material_override = off
	if led != null:
		led.material_override = ledOff
	_resets.append(func():
		for b in seq:
			b.material_override = off
		if led != null:
			led.material_override = ledOff
	)
	_beat = func():
		sound("door_keypad_motif")
		for i in seq.size():
			var b: MeshInstance3D = seq[i]
			_tl.at(i * 0.2, func(): b.material_override = on)
			_tl.at(i * 0.2 + 0.16, func(): b.material_override = off)
		_tl.at(0.75, func():
			if led != null:
				led.material_override = ledOn
		)
		swing(lv[0], -1, 0.85, 0.6, 1.3)
		swing(lv[1], 1, 0.88, 0.6, 1.3)

func _look_elephant() -> void:
	var panel := blocker.get_node_or_null("panel") as Node3D
	var W := width
	_beat = func():
		sound("door_elephant")
		if panel == null:
			return
		_tl.span(0, 0.35, func(k): panel.position.x = sin(k * 42.0) * 0.025 * (1.0 - k))
		_tl.span(0.35, 1.8, func(k): panel.position.x = (W + 0.2) * Anim.ease_.inOutSine(k))

func _look_debris_cables() -> void:
	var cables := blocker.get_node_or_null("cables") as Node3D
	var pieces := _pieces("piece_", 4)
	_beat = func():
		sound("door_poof")
		_tl.span(0, 0.35, func(k):
			if cables == null:
				return
			cables.scale.y = maxf(0.01, 1.0 - Anim.ease_.outCubic(k))
			if k >= 1.0:
				cables.visible = false
		)
		tumble(pieces, {"start": 0.1, "spread": 0.2})
		_tl.at(0.95, func(): puff(["#C9C2B0", "#B98A57"]))

func _look_fire_exit() -> void:
	var lv := _leaves()
	_beat = func():
		sound("door_buzz")
		_tl.span(0, 0.5, func(k):
			var j: float = sin(k * 90.0) * 0.018 * (1.0 - k)
			if lv[0] != null:
				lv[0].rotation.y = j
			if lv[1] != null:
				lv[1].rotation.y = -j
		)
		swing(lv[0], -1, 0.5, 0.7, 1.4)
		swing(lv[1], 1, 0.52, 0.7, 1.4)
