# Room dressing: LOBBY & RECEPTION (port of src/world/rooms/lobby.js; GDD §5.7 "Lobby", §3.3 lighting, §2 story
# props, §13 toys + step-1 objects, §18.13 ids). This file also holds the small room kit green_room.gd uses.
#
# build(game, area, root) — called by level.gd after the graybox (root = the area's 'dressing' node, in the tree).
#
# game.level.objects entries registered here (world space, all nodes live under the lobby area root). They are
# Dictionaries whose methods are Callables under the JS names (callers: _oc(o, "setOpen", [...]) / o.setOpen.call()):
#   ee_chime_rack  { group, parts:{ ee_bar_red, ee_bar_yellow, ee_bar_green, ee_bar_blue } (pivot nodes, swing =
#                    rotation.x), bars:{ red|yellow|green|blue: { part, note, hz, len, top():Vector3, bottom():Vector3 } },
#                    swing(color, strength=1, dir?:Vector3), raycast(origin, dir, maxDist, color?) -> { color, id, dist,
#                    point } | null (capsule r 0.055 per bar, first hit), ring(color) (swing + no sound) }
#   ee_trophy_case { group, parts:{ door }, dudley:Vector3 (empty middle-shelf spot), dropPoint:Vector3,
#                    setOpen(open, instant=false) }
#   neon_logo      { group, parts:{ W, Z, T, V, 13 } (tube meshes), state 'dark'|'broken'|'lit', setState(state),
#                    setLetter(key, level 0..1), fix() (stutter Z+T back to full glow, 'ee_neon_stutter') }
#                    Automatic: dark before power, 'broken' (W V 13 lit, Z T dead + buzzing) when the color wave
#                    reaches it, fix() on egg:step >= 1. Idempotent, so the EE may also call it.
#   booth_on_air   { group, set(on) }   (lights permanently on egg:step >= 1)
#   letter_board   { group, parts:{ face }, letters:[MeshInstance3D] (fallen SIGN OFF letters), signOff(on) } (on egg:complete)
#   lobby_clock    { group, parts:{ hour, minute, second }, setMidnight(on) }  (11:59, second hand twitching :58<->:59;
#                    egg:complete -> ticks to 12:00 and plays the station motif)
#   reception_desk { group, parts:{ bell, magazine } }    exhibit_camera { group, parts, setTally(on) }
#   mon_lobby_exhibit / mon_lobby_booth { group, screen } (screens registered as scr_feed_lobby)
# Toys (GDD §13): toy_desk_bell ('toy_bell', bell squash-hop), toy_exhibit_camera ('toy_camera_zoom', tally toggle +
#   head nod; asks game.screens.zoomFeed('lobby', 5) and emits 'toy:exhibit_zoom' {area:'lobby', seconds:5}).
#   All toys use a key-only prompt (prompt() -> {}). Every toy emits 'toy:use' {id}.
#
# Room kit (used by green_room.gd): roomKit(game, area, root) -> RoomKit (a Node added under root) with
#   place(id, pos, rotY, opts, o), put(group, pos, rotY, o), anchor({...pre, post}), pool(pos, r, color, pre, post),
#   onPower(pos, apply(on, instant)), glowSwap(mesh, onMat, offMat), toy(id, pos, use, radius), obj(id, fields),
#   sound(id, pos), hook(mesh), mergeInto(meshes, material, name), ticks[] (fn(dt, t, realDt)), resets[] (fn on
#   game:start).
#   Power: every onPower entry switches when the Sign-On color wave (15 m/s from the lever) reaches it, with the
#   level's 3-flash flicker; a new game with the power off switches everything back instantly.
#
# PORT NOTES (Godot)
# * The room-local geometry (the shared decal atlas, cellPlane/decal, velvetRopes, wallShelf, exitSign, plinth,
#   signPost, announcerDesk, doormat, the moonlight slats and every loose mesh build() added to the area root) is
#   built by blender/runtime/rooms_lobby_green.py into res://assets/runtime/rooms_lobby/*.glb (same code, numbers
#   and canvas drawing) and loaded here (loadAsset); kit.put places the local builders exactly like the JS.
#   moonSlats(game, kit, pos, rotY, opts, mesh) takes the Blender-built slat mesh and wires its power switch.
# * kit.hook: the JS ran the room's per-frame work from the onBeforeRender of one always-drawn mesh; here the kit is
#   a Node whose _process runs that work once per game frame while the hook mesh is visible in the tree.
# * kit.mergeInto: the static merge is engine plumbing (not ported): it returns a node that keeps the source meshes
#   in place (shadows off, like the merged mesh) and swaps all their materials through its `material` property.
# * setNeon (props/sets.js) and setLamp (props/broadcast.js) are the JS prop runtime helpers the lobby calls; they
#   are ported here as static functions (setLamp: 'on' / 'off' only, the states this room uses).
# * mesh.material = m -> material_override. JS `this` in the object methods -> the captured Dictionary.
# * Renames (SPEC §3.2): hash -> hash_ (GDScript global); booth_on_air.set is stored under "set" and "set_".
extends RefCounted

const ASSETS := "res://assets/runtime/rooms_lobby/"
const LEVER := Vector3(29, 1, -7.6)
const WAVE := 15.0
const FLICKER := [[0.0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]]
const WALL := {"n": -5.85, "s": 5.85, "w": -6.85, "e": 6.85}
# kit.js MAT presets (K.mat(game, preset, color, extra) = mats.toon(color, {...preset, vertexColors: true, ...extra}))
const MAT := {
	"lacquer": {"rough": 0.36, "rim": 0.22, "env": 0.12},
	"walnut": {"rough": 0.42, "rim": 0.2, "env": 0.08},
	"teak": {"rough": 0.5, "rim": 0.2, "env": 0.05},
	"vinyl": {"rough": 0.36, "rim": 0.32, "env": 0.1},
	"chrome": {"rough": 0.2, "metal": 1, "rim": 0.18, "env": 0.55},
	"brass": {"rough": 0.3, "metal": 1, "rim": 0.2, "env": 0.45},
	"plastic": {"rough": 0.34, "rim": 0.3, "env": 0.12},
	"fabric": {"rough": 0.95, "rim": 0.5, "wrap": 0.7, "rimPower": 1.8},
	"felt": {"rough": 1, "rim": 0.55, "wrap": 0.75, "rimPower": 1.6},
	"crt": {"rough": 0.06, "rim": 0.55, "env": 0.5},
	"rubber": {"rough": 0.85, "rim": 0.12},
	"paint": {"rough": 0.6, "rim": 0.2},
	"metal": {"rough": 0.42, "metal": 0.7, "rim": 0.2, "env": 0.35},
	"ceramic": {"rough": 0.22, "rim": 0.3, "env": 0.15},
	"soil": {"rough": 1, "rim": 0.05},
	"leaf": {"rough": 0.55, "rim": 0.4, "wrap": 0.8, "side": 2, "rimColor": "#EFFFB0"},
}

# ================================================================================================= helpers
static func v3(p) -> Vector3:
	return DAU.v3(p)

static func hash_(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453
	return s - floorf(s)

# JS truthiness (`!!v`)
static func truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0 and not is_nan(float(v))
	if v is String or v is StringName:
		return v != ""
	return true

# JS `a ?? b`
static func nn(v, d):
	return d if v == null else v

# K.mat(game, preset, color, extra) (props/kit.js)
static func kmat(game, preset: String = "plastic", color = "#ffffff", extra: Dictionary = {}) -> Material:
	if not MAT.has(preset):
		push_warning("[props] unknown material preset \"%s\"" % preset)
	var o: Dictionary = (MAT.get(preset, {}) as Dictionary).duplicate()
	o["vertexColors"] = true
	o.merge(extra, true)
	return game.mats.toon(color, o)

# A material from a Blender userData value ({"__material": spec}) or a Material.
static func mat(game, v) -> Material:
	if v is Material:
		return v
	if v is Dictionary and v.get("__material") is Dictionary:
		return game.mats.fromSpec(v.__material)
	return null

# game.cards.get(id, opts) (the gfx card texture)
static func card(game, id: String, opts: Dictionary = {}) -> Texture2D:
	var C = game.get("cards")
	if C == null:
		return null
	if C is Object and C.has_method("get_"):
		return C.get_(id, opts)
	if C is Object and C.has_method("getCard"):
		return C.getCard(id, opts)
	return null

# A Blender-built room asset (res://assets/runtime/rooms_*/<name>.glb), materials + userData converted.
static func loadAsset(game, path: String) -> Node3D:
	if game.props == null or not game.props.has_method("loadRuntime"):
		return null
	return game.props.loadRuntime(path)

static func partsOf(n) -> Dictionary:
	if n == null:
		return {}
	var p = DAU.ud(n).get("parts")
	return p if p is Dictionary else {}

static func setMaterial(mesh, m) -> void:
	if mesh is GeometryInstance3D:
		(mesh as GeometryInstance3D).material_override = m
	elif mesh != null and mesh.has_method("setMaterial"):
		mesh.setMaterial(m)

static func getMaterial(mesh) -> Material:
	if mesh is MeshInstance3D:
		var mi := mesh as MeshInstance3D
		if mi.material_override != null:
			return mi.material_override
		var m: Material = mi.get_surface_override_material(0)
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
		return m
	return null

# ---------------------------------------------------------------------------------- prop runtime helpers
# props/sets.js setNeon(prop, game, key, level): the tube (and its halo) of one letter of the neon logo at a level.
const NEON := {"W": "#FF3B30", "Z": "#FFD23A", "T": "#52E04A", "V": "#3A7BFF", "13": "#FFF6E8"}

static func neonLevelMat(game, key: String, level: float) -> Material:
	var q := floorf(clampf(level, 0.0, 1.0) * 20.0 + 0.5) / 20.0
	return game.mats.glow(NEON[key], (0.12 + pow(q, 1.5) * 2.9) * (0.62 if key == "13" else 1.0))

static func haloMat(game, key: String, level: float, map) -> Material:
	var q := floorf(clampf(level, 0.0, 1.0) * 20.0 + 0.5) / 20.0
	return game.mats.glow(NEON[key], (0.01 + pow(q, 2) * 0.76) * (0.35 if key == "13" else 1.0), {"map": map, "additive": true})

static func setNeon(prop, game, key: String, level: float = 1.0) -> void:
	var p := partsOf(prop)
	if p.is_empty() or game == null:
		return
	var tube = p.get("neon_" + key)
	if tube != null:
		setMaterial(tube, neonLevelMat(game, key, level))
	if key == "13" and p.get("neon_ring") != null:
		setMaterial(p.neon_ring, neonLevelMat(game, "W", level))
	var hl = p.get("halo_" + key)
	if hl != null:
		var cur = getMaterial(hl)
		setMaterial(hl, haloMat(game, key, level, cur.get("map") if cur is DAMaterial else null))

# props/broadcast.js setLamp(prop, state, partName = 'lamp'): swaps the lamp part to userData.lampMats.on / .off.
static func setLamp(prop, state: String, partName: String = "lamp") -> bool:
	if prop == null:
		return false
	var u := DAU.ud(prop)
	var mesh = partsOf(prop).get(partName)
	var lm = u.get("lampMats")
	if mesh == null or not (lm is Dictionary):
		return false
	var game = DAGame.inst
	if state == "off":
		setMaterial(mesh, mat(game, lm.get("off")))
		return true
	if state != "on":
		push_warning("[rooms] setLamp: state '%s' (LITUV swatches) not supported here" % state)
		return false
	setMaterial(mesh, mat(game, lm.get("on")))
	return true

# ============================================================================================================ kit
static func roomKit(game, area: Dictionary, root: Node3D) -> RoomKit:
	var kit := RoomKit.new()
	kit.setup(game, area, root)
	return kit

# kit.mergeInto result: the meshes stay where they are; `material` switches them all.
class MergedMesh extends Node3D:
	var meshes: Array = []
	var material: Material:
		set(v):
			material = v
			for m in meshes:
				if is_instance_valid(m):
					m.material_override = v

class RoomKit extends Node:
	const LEVER := Vector3(29, 1, -7.6)
	const WAVE := 15.0
	const FLICKER := [[0.0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]]
	var game
	var area: Dictionary
	var root: Node3D
	var level
	var aid := ""
	var ticks: Array = []
	var switches: Array = []
	var resets: Array = []
	var powered := false
	var t := 0.0
	var _uid := 0
	var _powerT0 := -1.0
	var _pending := false
	var _warned := false
	var _hookMesh: Node = null
	var _hookLast := -1

	func setup(g, a: Dictionary, r: Node3D) -> void:
		game = g
		area = a
		root = r
		level = g.level
		aid = str(a.id)
		name = "room_kit"
		r.add_child(self)
		if game.events != null:
			game.events.on("power:on", func(_p = null):
				_powerT0 = now()
				_pending = true
				powered = true
				for s in switches:
					s.done = false)
			game.events.on("game:start", func(_p = null):
				if not _powerOn():
					_setAll(false)
				for fn in resets:
					fn.call())

	func now() -> float:
		var tm = game.get("time")
		if tm is Dictionary and tm.get("realNow") != null:
			return float(tm.realNow)
		return DAU.nowMs() / 1000.0

	func _powerOn() -> bool:
		var M = game.get("machines")
		return M != null and truthy(M.get("powerOn"))

	static func truthy(v) -> bool:
		if v == null:
			return false
		if v is bool:
			return v
		if v is int or v is float:
			return v != 0
		return true

	# Positions a built group, registers its colliders / light anchors / screens (placeProp semantics + scale,
	# tilt, anchor power modes, screen ids).
	func put(g: Node3D, pos: Array, rotY: float = 0.0, o: Dictionary = {}) -> Node3D:
		if g == null:
			return null
		g.position = Vector3(float(pos[0]), float(pos[1]) if pos.size() > 1 and pos[1] != null else 0.0, float(pos[2]))
		var tilt = o.get("tilt")
		g.rotation_order = EULER_ORDER_XYZ
		g.rotation = Vector3(float(tilt[0]) if tilt is Array else 0.0, rotY, float(tilt[1]) if tilt is Array else 0.0)
		var sc = o.get("scale")
		if sc != null:
			if sc is int or sc is float:
				g.scale = Vector3(sc, sc, sc)
			else:
				g.scale = Vector3(sc[0], sc[1], sc[2])
		var parent: Node = o.get("parent") if o.get("parent") != null else root
		parent.add_child(g)
		var M: Transform3D = g.global_transform
		var u := DAU.ud(g)
		var col = level.get("col") if level != null else null
		if o.get("colliders") != false and col != null:
			var boxes = o.get("boxes")
			if not truthy(boxes):
				boxes = u.get("colliders")
			if boxes == null:
				boxes = []
			for c in boxes:
				var mn := DAU.v3(c.min)
				var mx := DAU.v3(c.max)
				var bb := AABB()
				for i in 8:
					var v := M * Vector3(mx.x if i & 1 else mn.x, mx.y if i & 2 else mn.y, mx.z if i & 4 else mn.z)
					if i == 0:
						bb = AABB(v, Vector3.ZERO)
					else:
						bb = bb.expand(v)
				var copts := {"tag": o.get("tag") if truthy(o.get("tag")) else "prop"}
				if c.get("opts") is Dictionary:
					copts.merge(c.opts, true)
				col.addBox(DAU.arr3(bb.position), DAU.arr3(bb.end), copts)
		u["anchorIds"] = []
		if o.get("lights") != false:
			var las = u.get("lightAnchors")
			for a in (las if las is Array else []):
				var p: Vector3 = M * DAU.v3(a.pos)
				u.anchorIds.append(anchor({
					"pos": DAU.arr3(p), "color": a.get("color"),
					"intensity": float(a.get("intensity") if a.get("intensity") != null else 1.5) * float(o.get("lightMul") if o.get("lightMul") != null else 1.0),
					"distance": a.get("distance"), "flicker": a.get("flicker"),
					"pre": o.get("pre") if o.get("pre") != null else 1.0, "post": o.get("post") if o.get("post") != null else 1.0,
				}))
		var S = game.get("screens")
		if o.get("screens") != false and S != null and S.has_method("register"):
			var scr = u.get("screens")
			var i := 0
			for s in (scr if scr is Array else []):
				var ids = o.get("screenIds")
				var id = ids[i] if ids is Array and i < ids.size() and truthy(ids[i]) else s.get("id")
				var grp = o.get("screenGroup")
				if not truthy(grp):
					grp = s.get("group")
				if not truthy(grp):
					grp = "scr_decor"
				S.register(s.get("mesh"), grp, {"id": id} if truthy(id) else {})
				i += 1
		if truthy(o.get("noMerge")):
			u["noMerge"] = true
		return g

	func place(id: String, pos: Array, rotY: float = 0.0, opts: Dictionary = {}, o: Dictionary = {}) -> Node3D:
		var P = game.get("props")
		var g: Node3D = P.build(id, opts) if P != null else null
		if g == null:
			push_warning("[rooms:%s] prop \"%s\" failed" % [aid, id])
			return null
		return put(g, pos, rotY, o)

	# Pooled light anchor with power states: intensity x pre before Sign-On, x post after.
	func anchor(a: Dictionary) -> String:
		var pos = a.get("pos")
		var color = a.get("color") if a.get("color") != null else Config.PAL.tungsten
		var intensity := float(a.get("intensity") if a.get("intensity") != null else 1.5)
		var distance := float(a.get("distance") if a.get("distance") != null else 5.0)
		var flicker = a.get("flicker") if a.get("flicker") != null else 0
		var pre := float(a.get("pre") if a.get("pre") != null else 1.0)
		var post := float(a.get("post") if a.get("post") != null else 1.0)
		var id = a.get("id")
		var aidStr: String
		if truthy(id):
			aidStr = str(id)
		else:
			_uid += 1
			aidStr = "%s_dress_%d" % [aid, _uid]
		var L = game.get("lights")
		if L == null or not L.has_method("addAnchor"):
			return aidStr
		var p: Array = DAU.arr3(pos) if pos is Vector3 else pos
		var fl := float(flicker) if (flicker is float or flicker is int) else (0.5 if truthy(flicker) else 0.0)
		L.addAnchor({"id": aidStr, "pos": p, "color": color, "intensity": intensity * pre, "distance": distance, "area": aid, "flicker": fl})
		if pre != post:
			onPower(p, func(on, _instant = false): L.setAnchor(aidStr, {"intensity": intensity * (post if on else pre)}))
		return aidStr

	# Additive floor light pool (fx.lightPool) with power states.
	func pool(pos, radius: float, color, pre: float, post = null):
		var F = game.get("fx")
		if F == null or not F.has_method("lightPool"):
			return null
		var h = F.lightPool(DAU.v3(pos), radius, color, pre)
		if h == null:
			return null
		var po: float = pre if post == null else float(post)
		if pre != po:
			onPower(pos, func(on, _instant = false): h.set_({"intensity": po if on else pre}))
		return h

	func onPower(pos, apply: Callable) -> void:
		var p := DAU.v3(pos)
		switches.append({"pos": p, "delay": LEVER.distance_to(p) / WAVE, "apply": apply, "state": false, "done": true})

	func glowSwap(mesh: Node3D, onMat: Material, offMat: Material, pos = null) -> void:
		if mesh == null:
			return
		var p: Vector3 = DAU.v3(pos) if pos != null else mesh.global_position
		mesh.material_override = offMat
		onPower(p, func(on, _instant = false): mesh.material_override = onMat if on else offMat)

	func toy(id: String, pos, use: Callable, radius: float = 1.5):
		var I = game.get("interact")
		if I == null or not I.has_method("register"):
			return null
		var ev = game.get("events")
		return I.register({
			"id": id, "pos": DAU.v3(pos), "radius": radius, "prompt": func() -> Dictionary: return {},
			"use": func() -> void:
				use.call()
				if ev != null:
					ev.emit("toy:use", {"id": id}),
		})

	func obj(id: String, fields: Dictionary) -> Dictionary:
		var o := {"id": id, "area": aid}
		o.merge(fields, true)
		if not (level.get("objects") is Dictionary):
			level.objects = {}
		level.objects[id] = o
		return o

	func sound(id: String, pos, o: Dictionary = {}):
		var A = game.get("audio")
		if A == null or not A.has_method("play"):
			return null
		var opts := {"pos": DAU.v3(pos)}
		opts.merge(o, true)
		return A.play(id, opts)

	# (JS: merges static meshes into one noMerge mesh whose material can be swapped at runtime.) Here the meshes
	# stay separate (merging is engine plumbing); the returned node swaps all their materials at once.
	func mergeInto(meshes: Array, material: Material, nm: String = "merged_parts") -> MergedMesh:
		var list: Array = []
		for m in meshes:
			if m == null or not is_instance_valid(m):
				continue
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			list.append(m)
		if list.is_empty():
			return null
		var node := MergedMesh.new()
		node.name = nm
		node.meshes = list
		node.material = material
		DAU.ud(node).noMerge = true
		root.add_child(node)
		return node

	# Frame hook: the room's per-frame work runs while this node is drawn (visible in the tree), once per frame.
	func hook(mesh: Node) -> void:
		if mesh == null:
			return
		_hookMesh = mesh
		_hookLast = -1

	func _process(_delta: float) -> void:
		if _hookMesh == null or not is_instance_valid(_hookMesh) or not (_hookMesh as Node3D).is_visible_in_tree():
			return
		var tm = game.get("time")
		var f := int(tm.frame) if tm is Dictionary and tm.get("frame") != null else 0
		if f == _hookLast:
			return
		_hookLast = f
		run()

	func _setAll(on: bool) -> void:
		for s in switches:
			s.apply.call(on, true)
			s.state = on
			s.done = true
		_pending = false
		powered = on

	func powerStep() -> void:
		var powerOn := _powerOn()
		if not powerOn and powered:
			_setAll(false)
			return
		if not _pending:
			return
		var el := now() - _powerT0
		var busy := false
		for s in switches:
			if s.done:
				continue
			var tt: float = el - s.delay
			if tt < 0.0:
				busy = true
				continue
			var on := true
			if tt < 1.2:     # overdue: switch without flicker
				for f in FLICKER:
					if tt >= f[0]:
						on = f[1]
			if on != s.state:
				s.apply.call(on, false)
				s.state = on
			if tt >= FLICKER[FLICKER.size() - 1][0]:
				s.done = true
			else:
				busy = true
		_pending = busy

	func run() -> void:
		var tm = game.get("time")
		var dt := minf(0.05, float(tm.get("dt", 0.0)) if tm is Dictionary else 0.0)
		var rdt := minf(0.05, float(tm.get("realDt", 0.0)) if tm is Dictionary else 0.0)
		t += dt
		powerStep()
		for fn in ticks:
			fn.call(dt, t, rdt)

# ================================================================================================== assets
# moonSlats(game, kit, pos, rotY, opts): moonlight through the boarded front doors: additive floor slats (board
# gaps), fading into the room. The sheared plane + its two glow materials are Blender-built (m = the 'moon_slats_<n>'
# mesh of the room's dressing GLB, userData onMat / offMat); here: off material now, on material when the wave
# reaches pos.
static func moonSlats(game, kit: RoomKit, pos: Array, _rotY: float, _opts: Dictionary, m: MeshInstance3D) -> MeshInstance3D:
	if m == null:
		return null
	var u := DAU.ud(m)
	var onM := mat(game, u.get("onMat"))
	var offM := mat(game, u.get("offMat"))
	m.material_override = offM
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	u["noMerge"] = true
	kit.onPower(pos, func(on, _instant = false): m.material_override = onM if on else offM)
	return m

static func _child(n: Node, nm: String):
	return n.find_child(nm, true, false) if n != null else null

# ================================================================================================== build
static func build(game, area: Dictionary, root: Node3D) -> RoomKit:
	var kit := roomKit(game, area, root)
	var A := Layout.ANCHORS
	var PAL := Config.PAL
	var lvl = game.level
	# the loose meshes lobby.js added to the area root (floor papers, letters, glass lettering, cable, moon slats)
	var dress := loadAsset(game, ASSETS + "lobby_dressing.glb")
	if dress != null:
		root.add_child(dress)

	# ------------------------------------------------------------------------------------ island: desk + neon
	var desk := kit.place("desk_reception", [0, 0, -0.42], PI)
	var neon := kit.place("neon_logo_partition", [0, 0, -1.4], PI, {"state": "dark"}, {"lights": false})
	kit.obj("reception_desk", {"group": desk, "parts": partsOf(desk)})

	# four globe pendants over the desk (off before Sign-On), merged into one switchable draw
	var globeOn := kmat(game, "ceramic", "#FFF1D8", {"emissive": "#FFD9A0", "emissiveIntensity": 0.95, "rim": 0.5, "rimColor": "#FFFFFF"})
	var globeOff := kmat(game, "ceramic", "#E9DCC4", {"rim": 0.4})
	var globes := []
	var gi := 0
	for xz in [[-1.55, -0.3], [-0.52, -0.46], [0.52, -0.46], [1.55, -0.3]]:
		var p := kit.place("lamp_globe_pendant", [xz[0], 4.0, xz[1]], 0.0, {"drop": 0.95 + (gi % 2) * 0.12, "r": 0.21}, {"lights": false})
		if p != null and partsOf(p).get("glow") != null:
			globes.append(partsOf(p).glow)
		gi += 1
	var globeMesh := kit.mergeInto(globes, globeOff, "lobby_globes")
	kit.onPower([0, 2.8, -0.4], func(on, _i = false):
		if globeMesh != null:
			globeMesh.material = globeOn if on else globeOff)
	kit.anchor({"pos": [-1.0, 2.5, -0.1], "color": PAL.tungsten, "intensity": 2.2, "distance": 6.5, "pre": 0, "post": 1})
	kit.anchor({"pos": [1.0, 2.5, -0.1], "color": PAL.tungsten, "intensity": 2.2, "distance": 6.5, "pre": 0, "post": 1})
	kit.pool([0, 0.02, 0.9], 2.9, "#FFC98A", 0, 0.2)

	# neon logo: dark tubes before power, W V 13 lit + Z T dead after Sign-On, all lit after EE step 1
	var _neonLight := kit.anchor({"pos": [0, 1.9, -0.25], "color": "#FF8AC0", "intensity": 1.6, "distance": 5.5, "pre": 0.1, "post": 1})
	kit.pool([0, 0.02, -0.2], 2.2, "#FF6FB0", 0.03, 0.14)
	var NEON_KEYS := ["W", "Z", "T", "V", "13"]
	var neonParts := {}
	if neon != null:
		for k in NEON_KEYS:
			neonParts[k] = partsOf(neon).get("neon_" + k)
	var neonObj := kit.obj("neon_logo", {
		"group": neon, "parts": neonParts, "state": "dark",
		"levels": {"W": 0.2, "Z": 0.2, "T": 0.2, "V": 0.2, "13": 0.2}, "fixT": -1.0,
	})
	neonObj.setLetter = func(key: String, lv: float) -> void:
		var q := floorf(clampf(lv, 0.0, 1.0) * 20.0 + 0.5) / 20.0
		if neonObj.levels[key] == q:
			return
		neonObj.levels[key] = q
		if neon != null:
			setNeon(neon, game, key, q)
	neonObj.setState = func(state: String) -> void:
		neonObj.state = state
		neonObj.fixT = -1.0
		for k in NEON_KEYS:
			neonObj.setLetter.call(k, 0.2 if state == "dark" else (0.2 if state == "broken" and (k == "Z" or k == "T") else 1.0))
	neonObj.fix = func() -> void:
		if neonObj.state == "lit" or neonObj.fixT >= 0.0:
			return
		neonObj.fixT = 0.0
		kit.sound("ee_neon_stutter", [0, 1.9, -1.2])
	if neon != null:
		kit.onPower([0, 1.9, -1.3], func(on, _i = false):
			var step = game.egg.get("step") if game.get("egg") != null else null
			neonObj.setState.call(("lit" if float(nn(step, 0)) >= 1 else "broken") if on else "dark"))
		var STUTTER := [0.2, 1, 0.2, 0.2, 1, 0.35, 1, 0.2, 0.2, 1, 1, 0.3, 1]
		kit.ticks.append(func(_dt, _t, rdt):
			var o: Dictionary = neonObj
			if o.fixT >= 0.0:
				o.fixT += rdt
				var i := int(floor(o.fixT / 0.11))
				if i >= STUTTER.size():
					o.setState.call("lit")
					return
				o.setLetter.call("Z", float(STUTTER[i]))
				o.setLetter.call("T", float(STUTTER[(i + 3) % STUTTER.size()]))
				return
			if o.state != "broken":
				return
			# dead tubes: a low flickering buzz with rare sputters (still clearly colored)
			var f := floorf(float(game.time.realNow) * 12.0)
			for ks in [["Z", 3.1], ["T", 7.7]]:
				var h := hash_(f * 0.37 + ks[1])
				o.setLetter.call(ks[0], 0.45 if h > 0.93 else (0.25 if h > 0.6 else 0.15)))
		kit.hook(partsOf(neon).get("neon_W"))

	# ------------------------------------------------------------------------------------ announce booth (NW)
	var rack := kit.place("chime_rack", [-6.55, 0, -4.5], -PI / 2)
	if rack != null:
		setupChimes(game, kit, rack)
	kit.put(loadAsset(game, ASSETS + "lg_announcer_desk.glb"), [-5.5, 0, -5.52], PI)
	kit.place("chair_office", [-5.35, 0, -4.78], 0.35)
	kit.put(loadAsset(game, ASSETS + "lg_wall_shelf.glb"), [-5.6, 1.69, WALL.n], PI, {"colliders": false})
	var prog := kit.place("bc_rack_monitor", [-5.6, 1.69, WALL.n + 0.27], PI, {"size": 14, "card": "station_id", "group": "scr_feed_lobby"},
		{"screenGroup": "scr_feed_lobby", "screenIds": ["mon_lobby_booth"], "colliders": false})
	if prog != null:
		kit.obj("mon_lobby_booth", {"group": prog, "screen": _screenMesh(prog)})
	kit.anchor({"pos": [-5.6, 1.9, -5.1], "color": "#8FD8FF", "intensity": 0.7, "distance": 3.2})
	var onAir := kit.place("bc_on_air", [-5.6, 2.32, WALL.n + 0.065], PI, {"lit": false})
	var onAirLight := kit.anchor({"pos": [-5.6, 2.3, -5.3], "color": PAL.onAirRed, "intensity": 1.0, "distance": 3, "pre": 0, "post": 0})
	var boothOnAir := kit.obj("booth_on_air", {"group": onAir, "on": false})
	boothOnAir["set"] = func(on) -> void:
		boothOnAir.on = truthy(on)
		if onAir != null:
			setLamp(onAir, "on" if truthy(on) else "off")
		var L = game.get("lights")
		if L != null and L.has_method("setAnchor"):
			L.setAnchor(onAirLight, {"intensity": 1.0 if truthy(on) else 0.0})
	boothOnAir["set_"] = boothOnAir["set"]
	if onAir != null and partsOf(onAir).get("lamp") != null:
		DAU.ud(partsOf(onAir).lamp).noMerge = true
	kit.place("bc_headphones_hook", [-4.78, 0.8, WALL.n + 0.05], PI, {}, {"colliders": false})
	kit.place("plant_snake", [-4.95, 0, -3.45], 0.4, {"seed": 3})
	# gold lettering on the booth glass (lobby side): lobby_dressing.glb 'glass_announce'

	# ------------------------------------------------------------------------------------ trophy case (west wall)
	var tc := kit.place("trophy_case", [-6.5, 0, -2.0], -PI / 2, {}, {"pre": 0.8, "post": 1})
	if tc != null:
		var door = partsOf(tc).get("door")
		var anc = DAU.ud(tc).get("anchors")
		if not (anc is Dictionary):
			anc = {}
		var M: Transform3D = tc.global_transform
		var dud: Vector3 = M * DAU.v3(anc.get("dudley") if anc.get("dudley") != null else [0, 1.3, 0])
		var drop: Vector3 = M * DAU.v3(anc.get("door_drop") if anc.get("door_drop") != null else [0.6, 0, -0.9])
		var trophy := kit.obj("ee_trophy_case", {"group": tc, "parts": {"door": door}, "dudley": dud, "dropPoint": drop, "open": false, "_k": 0.0})
		trophy.setOpen = func(open, instant = false) -> void:
			trophy.open = truthy(open)
			if truthy(instant):
				trophy._k = 1.0 if truthy(open) else 0.0
				if door != null:
					door.rotation.y = -1.9 * trophy._k
		kit.ticks.append(func(_dt, _t, rdt):
			var target := 1.0 if trophy.open else 0.0
			if trophy._k == target or door == null:
				return
			trophy._k = clampf(trophy._k + signf(target - trophy._k) * rdt / 0.7, 0.0, 1.0)
			var k: float = trophy._k
			door.rotation.y = -1.9 * ((1.0 - pow(1.0 - k, 3)) if target != 0.0 else k * k))
		kit.resets.append(func(): trophy.setOpen.call(false, true))
		kit.pool([-5.7, 0.02, -2.0], 1.5, "#FFE6B8", 0.1, 0.14)

	# ------------------------------------------------------------------------------------ studio-tour exhibit (SE)
	var fc: Dictionary = A.feed_cam_lobby
	var cam := kit.place("bc_pedestal_camera", [fc.pos[0], 0, fc.pos[2]], float(fc.rotY), {"num": 1, "tally": true, "color": "cream", "accent": "wztvBlue"})
	kit.put(loadAsset(game, ASSETS + "lg_velvet_ropes.glb"), [0, 0, 0], 0.0)
	kit.put(loadAsset(game, ASSETS + "lg_sign_post.glb"), [5.0, 0, 3.4], 1.5)
	kit.put(loadAsset(game, ASSETS + "lg_plinth.glb"), [4.62, 0, 5.3], PI / 4)
	var mon := kit.place("bc_tv_19", [4.62, 1.22, 5.3], PI / 4, {"legs": "none", "card": "station_id", "group": "scr_feed_lobby"},
		{"screenGroup": "scr_feed_lobby", "screenIds": ["mon_lobby_exhibit"], "colliders": false})
	if mon != null:
		kit.obj("mon_lobby_exhibit", {"group": mon, "screen": _screenMesh(mon)})
	kit.anchor({"pos": [4.1, 1.4, 4.8], "color": "#9FE0FF", "intensity": 0.8, "distance": 3.5})
	kit.pool([5.55, 0.02, 4.75], 1.6, "#FFD8A0", 0.14, 0.18)
	# camera cable snaking to a wall box: lobby_dressing.glb 'camera_cable'
	if cam != null:
		var parts := partsOf(cam)
		for k in ["head", "tilt", "tally"]:
			if parts.get(k) != null:
				DAU.ud(parts[k]).noMerge = true
		var camObj := kit.obj("exhibit_camera", {"group": cam, "parts": parts, "tally": true, "nod": -1.0})
		camObj.setTally = func(on) -> void:
			camObj.tally = truthy(on)
			setLamp(cam, "on" if truthy(on) else "off", "tally")
		var tilt = parts.get("tilt")
		var tilt0: float = tilt.rotation.x if tilt != null else 0.0
		kit.toy("toy_exhibit_camera", A.toy_exhibit_camera.pos, func():
			camObj.setTally.call(not camObj.tally)
			camObj.nod = 0.0
			kit.sound("toy_camera_zoom", fc.pos)
			var S = game.get("screens")
			if S != null and S.has_method("zoomFeed"):
				S.zoomFeed("lobby", 5)
			if game.events != null:
				game.events.emit("toy:exhibit_zoom", {"area": "lobby", "seconds": 5, "tally": camObj.tally}), 2.1)
		kit.ticks.append(func(_dt, _t, rdt):
			if camObj.nod < 0.0 or tilt == null:
				return
			camObj.nod += rdt
			var k: float = camObj.nod
			tilt.rotation.x = tilt0 + sin(k * 9.0) * 0.12 * maxf(0.0, 1.0 - k / 0.9)
			if k > 0.9:
				camObj.nod = -1.0
				tilt.rotation.x = tilt0)
		kit.resets.append(func(): camObj.setTally.call(true))

	# ------------------------------------------------------------------------------------ desk bell toy + clutter
	var bell = partsOf(desk).get("bell")
	if bell != null:
		var bellPos: Vector3 = (bell as Node3D).global_position
		var bellState := {"t": -1.0}
		kit.toy("toy_desk_bell", A.toy_desk_bell.pos, func():
			bellState.t = 0.0
			kit.sound("toy_bell", bellPos), 1.6)
		var s0: Vector3 = bell.scale
		var y0: float = bell.position.y
		kit.ticks.append(func(_dt, _t, rdt):
			if bellState.t < 0.0:
				return
			bellState.t += rdt
			var k: float = bellState.t
			var sq: float = (1.0 - k / 0.08 * 0.3) if k < 0.08 else 0.7 + 0.3 * (1.0 - exp(-(k - 0.08) * 9.0) * cos((k - 0.08) * 30.0))
			bell.scale = Vector3(s0.x * pow(2.0 - sq, 0.5), s0.y * sq, s0.z * pow(2.0 - sq, 0.5))
			bell.position.y = y0 + maxf(0.0, sin((k - 0.08) * 12.0)) * 0.03 * exp(-k * 4.0)
			if k > 0.8:
				bellState.t = -1.0
				bell.scale = s0
				bell.position.y = y0)
	# papers + pledge cards around the desk and booth: lobby_dressing.glb

	# ------------------------------------------------------------------------------------ conversation corners (E wall)
	kit.place("sofa_cloud", [6.36, 0, -3.72], PI / 2, {})
	kit.place("rug_shag_round", [5.25, 0, -3.72], 0.0, {"r": 1.05})
	kit.place("table_coffee", [5.02, 0, -3.72], PI / 2)
	kit.place("table_side_tulip", [6.42, 0, -5.42], 0.0)
	kit.place("lamp_arc", [5.55, 0, -5.52], 2.85, {}, {"pre": 0, "post": 0.75})
	kit.pool([5.1, 0.02, -4.3], 1.7, "#FFD49A", 0, 0.2)
	kit.place("sofa_cloud", [6.36, 0, 2.12], PI / 2, {})
	kit.place("lamp_tripod", [6.5, 0, 0.52], 0.3, {}, {"pre": 0, "post": 0.75})
	kit.pool([6.1, 0.02, 0.9], 1.4, "#FFD49A", 0, 0.18)
	# portrait wall above the sofas: the Baron, Stormy Stu, the crew
	for e in [
		["portrait_stormy_stu", -4.62, 0.56, "walnut"], ["portrait_baron", -3.72, 0.72, "gold"], ["hero_portrait_duke", -2.84, 0.56, "gold"],
		["hero_portrait_skip", 1.26, 0.56, "gold"], ["hero_portrait_roxy", 2.12, 0.56, "gold"], ["hero_portrait_penny", 2.98, 0.56, "gold"],
	]:
		var z: float = e[1]
		kit.place("frame_picture", [WALL.e, 1.24 if e[0] == "portrait_baron" else 1.36, z], PI / 2, {"card": e[0], "style": e[3], "h": e[2]},
			{"colliders": false, "tilt": [0, (hash_(z * 3.1) - 0.5) * 0.05]})

	# ------------------------------------------------------------------------------------ north wall
	var clock := kit.place("clock_sunburst", [0, 2.8, WALL.n], PI, {}, {"colliders": false})
	if clock != null:
		setupClock(game, kit, clock, [0, 3.29, WALL.n])
	kit.place("plant_rubber", [-3.95, 0, -5.38], 0.6, {"seed": 2})
	for e in [["sponsor_poster_wobble_up", -3.05], ["sponsor_poster_jump_cut", 2.35], ["sponsor_poster_roller_boogie", 6.05]]:
		var x: float = e[1]
		kit.place("frame_picture", [x, 1.28, WALL.n], PI, {"card": e[0], "style": "chrome", "h": 0.74},
			{"colliders": false, "tilt": [0, (hash_(x) - 0.5) * 0.05]})

	# ------------------------------------------------------------------------------------ south wall / front doors
	# (player_spawn sits left of this board so the shoulder camera, pulled in against the south wall, is not behind it)
	var lb := kit.place("letter_board", [1.2, 0, 5.08], -0.12)
	var letters := []
	for i in 7:
		var m = _child(dress, "letter_%d" % i)
		if m != null:
			letters.append(m)
	var letterObj := kit.obj("letter_board", {"group": lb, "parts": {"face": partsOf(lb).get("face")}, "letters": letters, "signed": false})
	letterObj.signOff = func(on) -> void:
		letterObj.signed = truthy(on)
		var face = letterObj.parts.face
		if face != null:
			setMaterial(face, kmat(game, "felt", "#ffffff", {"map": card(game, "letter_board", {"signOff": truthy(on)}), "mapWrap": "clamp", "rim": 0.12}))
		for m in letters:
			m.visible = not truthy(on)
	if partsOf(lb).get("face") != null:
		DAU.ud(partsOf(lb).face).noMerge = true
	for m in letters:
		DAU.ud(m).noMerge = true
	kit.resets.append(func():
		if letterObj.signed:
			letterObj.signOff.call(false))
	kit.place("plant_rubber", [-1.75, 0, 5.36], 2.2, {"seed": 5})
	kit.place("frame_picture", [-1.3, 1.25, WALL.s], 0.0, {"card": "sponsor_poster_replay_ade", "style": "chrome", "h": 0.74}, {"colliders": false})
	kit.place("frame_picture", [6.2, 1.34, WALL.s], 0.0, {"card": "sponsor_poster_double_vision", "style": "chrome", "h": 0.66}, {"colliders": false})
	var ms := 0
	for x in [-3.0, 3.0]:
		kit.put(loadAsset(game, ASSETS + "lg_exit.glb"), [x, 2.62, WALL.s], 0.0, {"colliders": false})
		kit.put(loadAsset(game, ASSETS + "lg_doormat.glb"), [x, 0, 4.95], 0.0)
		kit.pool([x, 0.02, 5.2], 1.1, "#FF4A3A", 0.12, 0.06)
		moonSlats(game, kit, [x, 0, WALL.s], 0.0, {"w": 1.7, "d": 2.7, "shear": 0.28 if x < 0 else -0.28}, _child(dress, "moon_slats_%d" % ms))
		ms += 1
	moonSlats(game, kit, [WALL.w, 0, 0], -PI / 2, {"w": 1.7, "d": 2.4, "shear": 0.22, "pre": 0.4, "post": 0.22}, _child(dress, "moon_slats_%d" % ms))
	kit.anchor({"pos": [0, 2.2, 4.6], "color": "#9FB6FF", "intensity": 1.6, "distance": 7, "pre": 1, "post": 0.45})
	kit.anchor({"pos": [-5.4, 1.8, 0], "color": "#9FB6FF", "intensity": 1.0, "distance": 5, "pre": 1, "post": 0.4})

	# ------------------------------------------------------------------------------------ west wall
	kit.place("plant_fern", [-6.35, 0, 1.45], 0.8, {"seed": 4})
	kit.place("macrame_owl", [WALL.w, 1.2, 2.25], -PI / 2, {}, {"colliders": false})

	# ------------------------------------------------------------------------------------ ceiling cans: floor pools
	for x in [-14.0 / 3.0, 0.0, 14.0 / 3.0]:
		for z in [-3.0, 3.0]:
			kit.pool([x, 0.02, z], 1.9, "#FFB45A", 0.2, 0.12)

	# ------------------------------------------------------------------------------------ EE / story hooks
	if game.events != null:
		game.events.on("egg:step", func(p = null):
			var step = p.get("step") if p is Dictionary else null
			if (step is int or step is float) and step >= 1:
				neonObj.fix.call()
				boothOnAir["set"].call(true))
		game.events.on("egg:complete", func(_p = null):
			letterObj.signOff.call(true)
			var lc = _levelClock(lvl)
			if lc != null:
				lc.setMidnight.call(true))
	kit.resets.append(func():
		boothOnAir["set"].call(false)
		var step = game.egg.get("step") if game.get("egg") != null else null
		if float(nn(step, 0)) < 1 and neonObj.state == "lit":
			neonObj.setState.call("broken" if kit._powerOn() else "dark")
		var lc = _levelClock(lvl)
		if lc != null:
			lc.setMidnight.call(false))
	boothOnAir["set"].call(false)
	return kit

static func _levelClock(lvl):
	if lvl == null or not (lvl.get("objects") is Dictionary):
		return null
	return lvl.objects.get("lobby_clock")

static func _screenMesh(g) -> Variant:
	var s = DAU.ud(g).get("screens")
	if s is Array and s.size() > 0 and s[0] is Dictionary:
		return s[0].get("mesh")
	return null

# Chime rack (EE step 1): springy pendulum bars, capsule raycasts, swing API.
static func setupChimes(game, kit: RoomKit, rack: Node3D) -> Dictionary:
	var COLORS := ["red", "yellow", "green", "blue"]
	var u := DAU.ud(rack)
	var info: Dictionary = u.get("chimes") if u.get("chimes") is Dictionary else {}
	var parts := {}
	var bars := {}
	var front: Vector3 = rack.quaternion * Vector3(0, 0, -1)   # toward the booth opening (east)
	for c in COLORS:
		var part = partsOf(rack).get("bar_" + c)
		if part == null:
			continue
		DAU.ud(part).noMerge = true
		part.rotation_order = EULER_ORDER_XYZ
		parts["ee_bar_" + c] = part
		var ci: Dictionary = info.get(c) if info.get(c) is Dictionary else {}
		var len_: float = float(ci.get("len")) if ci.get("len") != null else 1.0
		var pn: Node3D = part
		bars[c] = {
			"part": part, "note": ci.get("note"), "hz": ci.get("hz"), "len": len_, "th": 0.0, "w": 0.0,
			"top": func() -> Vector3: return pn.global_transform * Vector3(0, 0, 0),
			"bottom": func() -> Vector3: return pn.global_transform * Vector3(0, -len_, 0),
		}
	var R := 0.055
	var obj := kit.obj("ee_chime_rack", {"group": rack, "parts": parts, "bars": bars})
	obj.swing = func(color, strength = 1.0, dir = null) -> void:
		var b = bars.get(color)
		if b == null:
			return
		var s := -1.0
		if dir != null:
			s = signf(DAU.v3(dir).dot(front))
			if s == 0.0 or is_nan(s):
				s = -1.0
		b.w += s * 2.6 * float(strength)
	obj.ring = func(color) -> void:
		obj.swing.call(color, 1.0)
	# Ray vs. each bar capsule (current swing pose); returns the nearest hit.
	obj.raycast = func(origin: Vector3, dir: Vector3, maxDist = 100.0, only = null):
		var best = null
		for c in COLORS:
			if truthy(only) and c != only:
				continue
			var b = bars.get(c)
			if b == null:
				continue
			var a: Vector3 = b.top.call()
			var e: Vector3 = b.bottom.call()
			var seg := e - a
			var w0 := origin - a
			var A := dir.dot(dir)
			var B := dir.dot(seg)
			var C := seg.dot(seg)
			var D := dir.dot(w0)
			var E := seg.dot(w0)
			var den := A * C - B * B
			var t := (B * E - C * D) / den if den > 1e-8 else 0.0
			var s := (A * E - B * D) / den if den > 1e-8 else 0.0
			s = clampf(s, 0.0, 1.0)
			t = maxf(0.0, (B * s - D) / A)
			var pr := origin + dir * t
			var ps := a + seg * s
			var d := pr.distance_to(ps)
			if d > R:
				continue
			var hit := t - sqrt(maxf(0.0, R * R - d * d))
			if hit < 0.0 or hit > float(maxDist):
				continue
			if best == null or hit < best.dist:
				best = {"color": c, "id": "ee_bar_" + c, "dist": hit, "point": origin + dir * hit}
		return best
	kit.ticks.append(func(dt, _t, _rdt):
		var h := minf(dt, 1.0 / 30.0)
		if h <= 0.0:
			return
		for c in COLORS:
			var b = bars.get(c)
			if b == null or (absf(b.th) < 1e-4 and absf(b.w) < 1e-4):
				continue
			var k: float = 9.8 / (0.55 * b.len)
			b.w += (-k * b.th - 1.1 * b.w) * h
			b.th += b.w * h
			b.th = clampf(b.th, -0.5, 0.5)
			b.part.rotation.x = b.th)
	kit.resets.append(func():
		for c in COLORS:
			if bars.has(c):
				bars[c].th = 0.0
				bars[c].w = 0.0
				bars[c].part.rotation.x = 0.0)
	# listen to the canonical chime event too (so the EE only needs to emit egg:chime)
	if game.events != null:
		game.events.on("egg:chime", func(p = null):
			var bar = p.get("bar") if p is Dictionary else null
			var c := str(bar if truthy(bar) else "").replace("ee_bar_", "")
			if bars.has(c):
				obj.swing.call(c, 0.8))
	return obj

# 11:59 sunburst clock: the second hand twitches :58 -> :59 -> :58; after the easter egg it ticks to 12:00.
static func setupClock(game, kit: RoomKit, clock: Node3D, center: Array) -> Dictionary:
	var parts := partsOf(clock)
	for k in ["hour", "minute", "second"]:
		if parts.get(k) != null:
			DAU.ud(parts[k]).noMerge = true
			parts[k].rotation_order = EULER_ORDER_XYZ
	var ang := func(h: float, m: float, s: float) -> Array:
		return [(fmod(h, 12.0) + m / 60.0 + s / 3600.0) / 12.0 * TAU, (m + s / 60.0) / 60.0 * TAU, s / 60.0 * TAU]
	var obj := kit.obj("lobby_clock", {"group": clock, "parts": parts, "midnight": false, "mt": -1.0})
	obj.pose = func(h: float, m: float, s: float) -> void:
		var a: Array = ang.call(h, m, s)
		if parts.get("hour") != null:
			parts.hour.rotation.z = a[0]
		if parts.get("minute") != null:
			parts.minute.rotation.z = a[1]
		if parts.get("second") != null:
			parts.second.rotation.z = a[2]
	obj.setMidnight = func(on) -> void:
		if on == obj.midnight:
			return
		obj.midnight = truthy(on)
		obj.mt = 0.0 if truthy(on) else -1.0
		if not truthy(on):
			obj.pose.call(11.0, 59.0, 58.0)
		if truthy(on):
			var i := 0
			for id in ["ee_chime_red", "ee_chime_yellow", "ee_chime_green", "ee_chime_blue"]:
				kit.sound(id, center, {"delay": 0.6 + i * 0.45})
				i += 1
	kit.ticks.append(func(_dt, _t, rdt):
		if obj.midnight:
			if obj.mt < 0.0:
				return
			obj.mt += rdt
			var k := minf(1.0, obj.mt / 0.5)
			var e := 1.0 + 2.2 * pow(k - 1.0, 3) + 1.2 * pow(k - 1.0, 2)      # back-out ease
			obj.pose.call(11.0, 59.0 + e, 58.0 + 2.0 * e)
			if k >= 1.0:
				obj.pose.call(12.0, 0.0, 0.0)
				obj.mt = -1.0
			return
		var now := float(game.time.get("realNow", 0.0))
		var ph := fmod(now, 1.6)
		var s := 58.0 + minf(1.0, ph / 0.06) if ph < 0.8 else 59.0 - minf(1.0, (ph - 0.8) / 0.08)
		obj.pose.call(11.0, 59.0, s + (sin((ph - 0.06) * 40.0) * 0.08 * exp(-(ph - 0.06) * 10.0) if ph < 0.8 and ph > 0.06 else 0.0)))
	return obj
