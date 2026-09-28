# Level (ARCHITECTURE §7, §12; port of src/world/level.js): builds WZTV Channel 13 from layout.gd — collision shell
# (shell.gd), the graybox with per-area finishes (the Blender-built res://assets/world/architecture.glb, runtime
# fixture records in architecture.gd), doors and their opening beats (doors.gd), windows/boards/fence/gate
# (windows.gd), the street, skyline, night sky and tower (exterior.glb + exterior.gd) — then lets every
# rooms/<areaId>.gd dress its area. Owns portal culling, the Sign-On light switch-over and the level's animations.
#
# Scene graph: root 'level' -> area_<id> (walls, floor, fixtures, window frames, 'ceiling', 'dressing' -> rooms),
#   'shell' (exterior faces, copings, wall tops; 'roof'), 'doors' (door_<id>), 'boards' (6 MultiMeshInstance3D),
#   'exterior' (street, storefronts, skyline, tower), 'sky' (follows the camera). shell/exterior/boards/sky are
#   never culled; the boards and the always-visible exterior are occluded by walls.
#   (JS names 'area:<id>' / 'door:<id>' use '_' here: ':' is not allowed in Godot node names.)
#
# Public API (game.level)
#   col (Collision), areas {id -> layout area}, anchors {id -> { ...layout fields, id, pos:Vector3, rotY, area,
#   target:Vector3|null }}, doors {id -> Door (doors.gd): layout fields + open:bool, pos, approach, normal, meshes,
#   setOnAir(on)}, windows {id -> Win (windows.gd): layout fields + boards, boardMeshes, breakBoard(),
#   repairBoard(), breakAll(), pos}, screenSpawns {id -> { ...layout, pos:Vector3 }}, surf (surfaces.gd),
#   root, areaRoots {id -> Node3D}, groups {areaId, '<areaId>#ceil', shell, 'shell#roof', ext -> Node3D},
#   sky, beacons ({ mesh, set_: Callable(on) }), boardSet, objects {} (registry the rooms fill: game.level.objects),
#   powered (bool), built (bool), culling (bool, default true), shadowCull (bool, default true: only the
#   player/camera areas, and an area behind an open door within 6 m, cast shadows)
#   init() -> build(); listens to power:on        initSteps() the same as a coroutine (await game.frameYield())
#   reset() closes doors, re-boards windows, powers down
#   update(dt) door/board animations, Sign-On light sequence (real time), tower beacons
#   lateUpdate() portal culling + sky follow      cull(camera?) the same on demand
#   areaAt(x, z) -> area id | null                surfaceAt(x, z, y=0) -> 'carpet'|'tile'|'wood'|'gravel'|'metal'
#   openDoor(id, {instant}) -> bool  (animates, disables the collider, nav.setDoor, emits door:open)
#   openAllDoors({instant=true})                  setAreaVisible(id, bool)
#   renderWith(areaIds, fn) shows those areas (+ their door groups) while fn runs, then restores culling
#   setPower(on, {instant}) fixtures, light anchors and ON AIR boxes switch as the color wave (15 m/s from the
#     lever) reaches them, with a 3-flash flicker; tower beacons start blinking 3.4 s after power:on (t = 6 s)
#   setOnAir(on, doorId?)                         setCeilingsVisible(bool) (plan views / free camera)
# Sounds played here: crowd_ooh + the door look's cue on purchase, board_tear/board_repair, light_thunk,
# onair_clack. DY (requiresPower) is opened by machines/signon through openDoor (buzz-and-swing beat).
#
# Rooms: rooms/<areaId>.gd (optional) is loaded after the graybox and its build(game, area, root) is called with
# the layout area Dictionary and the area's 'dressing' Node3D (a static func, or an instance method: the instance
# is then kept in level._rooms[areaId]). A missing file is skipped; a runtime error aborts that room only.
#
# Not ported (engine plumbing, SPEC §0.2): the static merges (mergeByMaterial), staticopt.js (baked colours,
# shadow proxies, area batches), the render hooks of the per-object portal culling (portalBegin/portalEnd:
# main-pass-only hiding of objects outside the door view cones), matrix freezing. Area-level culling is kept.
extends RefCounted

const Shell = preload("res://scripts/world/shell.gd")
const Surfaces = preload("res://scripts/world/surfaces.gd")
const Architecture = preload("res://scripts/world/architecture.gd")
const Exterior = preload("res://scripts/world/exterior.gd")
const Door = preload("res://scripts/world/doors.gd")
const Windows = preload("res://scripts/world/windows.gd")
const COLLISION := "res://scripts/world/collision.gd"
const ARCH_GLB := "res://assets/world/architecture.glb"
const EXT_GLB := "res://assets/world/exterior.glb"
const ROOMS_DIR := "res://scripts/world/rooms/"

const WAVE_SPEED := 15.0                 # GDD §10.1 color wave, m/s
const SHADOW_DOOR_R := 6.0               # m: an area seen through an open door casts shadows once the player or
										 # the camera is this close to that door (no pop when crossing it)
const BEACON_DELAY := 6.0 - 2.6          # beacons start with DY at t = 6.0 s; power:on fires at t = 2.6 s
const FLICKER := [[0.0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]]
const DOOR_NEAR := 2.5

var game
var col
var root: Node3D
var areas := {}
var anchors := {}
var doors := {}
var windows := {}
var screenSpawns := {}
var areaRoots := {}
var groups := {}
var objects := {}
var culling := true
var shadowCull := true
var powered := false
var built := false
var surf
var sky: Node3D
var beacons = null
var boardSet = null
var LEVER := Vector3.ZERO
var _visible := {}
var _shadowCast := {}
var _shadowOff := {}
var _switches: Array = []
var _powerT := 0.0
var _powerDone := true
var _beaconT := -1.0
var _rooms := {}

func _init(g) -> void:
	game = g
	if ResourceLoader.exists(COLLISION):
		var C = load(COLLISION)
		if C != null and C.can_instantiate():
			col = C.new()
	if col == null:
		push_warning("[level] collision.gd missing: colliders are not registered")
	root = DAU.node3d("level")
	var lp: Array = Layout.ANCHORS.sign_on_lever.pos
	LEVER = Vector3(lp[0], 1.0, lp[2])

func init() -> void:
	_buildSteps(false)
	_listen()

# init() as a coroutine that yields a frame between its heavy steps (architecture, exterior, doors + windows,
# each room): Game's progressive boot runs one step per frame behind the title.
func initSteps() -> void:
	await _buildSteps(true)
	_listen()

func _listen() -> void:
	if game.events != null:
		game.events.on("power:on", func(_p = null): setPower(true))

# ------------------------------------------------------------------------------------------------ build
func build() -> void:
	_buildSteps(false)

func _step(async: bool) -> void:
	if async:
		await game.frameYield()

func _buildSteps(async: bool) -> void:
	if built:
		return
	built = true
	var g = game
	for a in Layout.AREAS:
		areas[a.id] = a
	for id in Layout.ANCHORS:
		var s: Dictionary = Layout.ANCHORS[id]
		var e := s.duplicate()
		e.id = id
		e.pos = DAU.v3(s.pos)
		e.rotY = s.get("rotY", 0.0) if s.get("rotY") != null else 0.0
		e.target = DAU.v3(s.target) if s.get("target") != null else null
		anchors[id] = e
	for s in Layout.SCREEN_SPAWNS:
		var e2: Dictionary = s.duplicate()
		e2.pos = DAU.v3(s.pos)
		screenSpawns[s.id] = e2
	if col != null:
		Shell.addShellColliders(col)
	# The level root joins the scene now (rooms may need world transforms while they build).
	var parent: Node = g.scene if g.scene != null else g
	parent.add_child(root)

	surf = Surfaces.createSurfaces(g)
	var arch := _instance(ARCH_GLB)
	for a in Layout.AREAS:
		var r := _take(arch, "area_" + a.id, root)
		areaRoots[a.id] = r
		groups[a.id] = r
		var c := _take(r, "ceiling_" + a.id, r)
		c.name = "ceiling"
		DAU.ud(c).noMerge = true
		groups[a.id + "#ceil"] = c
	groups.shell = _take(arch, "shell", root)
	var roof := _take(groups.shell, "roof", groups.shell)
	groups["shell#roof"] = roof
	var ext := _instance(EXT_GLB)
	groups.ext = _take(ext, "exterior", root)
	var skyNode := _take(ext, "sky", null)
	if arch != null:
		arch.free()
	var doorRoot := DAU.node3d("doors")
	root.add_child(doorRoot)
	var boardRoot := DAU.node3d("boards")
	root.add_child(boardRoot)
	for id in areaRoots:
		Surfaces.applyDa(g, areaRoots[id], surf)
	Surfaces.applyDa(g, groups.shell, surf)
	Surfaces.applyDa(g, groups.ext, surf)
	var ctx := {"game": g, "level": self, "surf": surf, "root": boardRoot}
	var fixtures := Architecture.buildFixtures(g, areaRoots)
	await _step(async)
	var ex := Exterior.buildExterior(g, groups.ext, skyNode)
	if ext != null:
		ext.free()
	sky = ex.sky
	beacons = ex.beacons
	root.add_child(sky)
	await _step(async)
	for d in Layout.DOORS:
		var door = Door.new(ctx, d)
		doors[d.id] = door
		doorRoot.add_child(door.group)
	var win := Windows.buildWindows(ctx)
	boardSet = win.boards
	for w in win.list:
		windows[w.id] = w
	await _step(async)

	for a in Layout.AREAS:
		var dressing := DAU.node3d("dressing")
		areaRoots[a.id].add_child(dressing)
		_buildRoom(a, dressing)
		await _step(async)

	_buildSwitches(fixtures)
	setPower(false, {"instant": true})

func _buildRoom(a: Dictionary, dressing: Node3D) -> void:
	var path: String = ROOMS_DIR + a.id + ".gd"
	if not ResourceLoader.exists(path):
		return
	var R = load(path)
	if R == null or not (R is Script):
		push_error("[rooms:%s] failed to load %s" % [a.id, path])
		return
	var isStatic := false
	var found := false
	for m in R.get_script_method_list():
		if m.name == "build":
			found = true
			isStatic = (int(m.flags) & METHOD_FLAG_STATIC) != 0
			break
	if not found:
		push_error("[rooms:%s] no build(game, area, root) in %s" % [a.id, path])
		return
	if isStatic:
		R.build(game, a, dressing)
	else:
		var inst = R.new()
		_rooms[a.id] = inst
		inst.build(game, a, dressing)

# The glTF scene's root instance (or null when the asset is missing: the level still runs without it).
func _instance(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_warning("[level] %s missing (run blender/build_all.py --only world)" % path)
		return null
	var scn = load(path)
	return scn.instantiate() if scn is PackedScene else null

# Detaches the child `name` of `src` (searched recursively) and adds it to `parent`; a new empty Node3D (named
# `name`) when missing. Imported nodes are switched to three's Euler order (XYZ).
func _take(src: Node, name: String, parent: Node) -> Node3D:
	var n: Node3D = src.find_child(name, true, false) as Node3D if src != null else null
	if n == null:
		n = DAU.node3d(name)
	elif n.get_parent() != null:
		n.get_parent().remove_child(n)
		DAU.traverse(n, func(o): o.owner = null)
	n.rotation_order = EULER_ORDER_XYZ
	if parent != null and n.get_parent() != parent:
		parent.add_child(n)
	return n

# Sign-On switch list: fixtures + their anchors per area, ON AIR boxes per door (by wave arrival time).
func _buildSwitches(fixtures: Array) -> void:
	var lights = game.lights
	for f in fixtures:
		_switches.append({
			"delay": f.dist / WAVE_SPEED, "pos": f.center, "sound": "light_thunk",
			"apply": func(on):
				f.mesh.material_override = f.post.mat if on else f.pre.mat
				if lights != null and lights.has_method("setAnchor"):
					for a in f.anchors:
						lights.setAnchor(a.id, a.post if on else a.pre),
		})
	for d in doors.values():
		if d.onAirBoxes.is_empty():
			continue
		_switches.append({
			"delay": LEVER.distance_to(d.pos) / WAVE_SPEED, "pos": d.pos, "sound": "onair_clack",
			"apply": func(on): d.setOnAir(on),
		})

# ----------------------------------------------------------------------------------------------- lifecycle
func reset() -> void:
	for d in doors.values():
		d.reset()
		if col != null:
			col.setEnabled(d.id, true)
		if game.nav != null and game.nav.has_method("setDoor"):
			game.nav.setDoor(d.id, false)
	for w in windows.values():
		w.reset()
	setPower(false, {"instant": true})

func update(dt: float) -> void:
	if not built:
		return
	for id in doors:
		doors[id].update(dt)
	if boardSet != null:
		boardSet.update(dt)
	var t = game.time
	var real: float = t.realDt if t != null and t.has("realDt") else dt
	_updatePower(real)
	if _beaconT >= 0.0:
		_beaconT += real
		if _beaconT >= BEACON_DELAY:
			_setBeacons(fmod(_beaconT - BEACON_DELAY, 1.0) < 0.5)

func lateUpdate(_dt = 0.0) -> void:
	cull()

func _setBeacons(on: bool) -> void:
	if beacons == null:
		return
	if beacons is Dictionary:
		var fn = beacons.get("set_", beacons.get("set"))
		if fn is Callable and fn.is_valid():
			fn.call(on)
	elif beacons is Object and beacons.has_method("set_"):
		beacons.set_(on)

# ------------------------------------------------------------------------------------------------- queries
func areaAt(x: float, z: float):
	return Layout.areaAt(x, z)

func surfaceAt(x: float, z: float, y: float = 0.0) -> String:
	for p in Layout.PLATFORMS:
		var r: Array = p.rect
		if x >= r[0] and x < r[2] and z >= r[1] and z < r[3] and y >= p.top - 0.25:
			return p.surface
	for p in Layout.FLOOR_PATCHES:
		var r: Array = p.rect
		if x >= r[0] and x < r[2] and z >= r[1] and z < r[3]:
			return p.surface
	var a = Layout.areaAt(x, z)
	return areas[a].floor if a != null else "gravel"

# --------------------------------------------------------------------------------------------------- doors
func openDoor(id: String, opts: Dictionary = {}) -> bool:
	var instant: bool = opts.get("instant", false)
	var d = doors.get(id)
	if d == null or d.open:
		return false
	var g = game
	d.open = true
	if col != null:
		col.setEnabled(id, false)
	if g.nav != null and g.nav.has_method("setDoor"):
		g.nav.setDoor(id, true)
	d.play(instant)
	if not instant and d.cost > 0 and g.audio != null:
		g.audio.play("crowd_ooh", {"pos": d.pos})
	if g.events != null:
		g.events.emit("door:open", {"doorId": id})
	return true

func openAllDoors(opts: Dictionary = {}) -> void:
	var instant: bool = opts.get("instant", true)
	for id in doors:
		openDoor(id, {"instant": instant})

func setOnAir(on: bool, doorId = null) -> void:
	for d in doors.values():
		if doorId == null or d.id == doorId:
			d.setOnAir(on)

# ------------------------------------------------------------------------------------------------- culling
func setAreaVisible(id: String, visible: bool) -> void:
	var r: Node3D = areaRoots.get(id)
	if r == null:
		return
	r.visible = visible
	for d in doors.values():
		if d.areas.has(id):
			d.group.visible = areaRoots[d.areas[0]].visible or areaRoots[d.areas[1]].visible

# Visible = the areas of the player and of the camera, every area behind one of their open doors, and a
# second area when its open door can be seen through the first open door from the camera.
func cull(camera = null) -> void:
	if not built:
		return
	if camera == null:
		camera = game.camera
	var eye := Vector3.ZERO
	if camera != null and is_instance_valid(camera):
		eye = camera.global_position if camera.is_inside_tree() else camera.position
		if sky != null:
			sky.position = eye
	else:
		camera = null
	var vis := _visible
	vis.clear()
	var p = game.player
	var ppos = p.get("pos") if p != null else null
	var here := []
	var ap = Layout.areaAt(ppos.x, ppos.z) if ppos is Vector3 else null
	if ap != null:
		here.append(ap)
	var ac = Layout.areaAt(eye.x, eye.z) if camera != null else null
	if ac != null:
		here.append(ac)
	var hop := []
	var culled := culling and here.size() > 0
	if not culled:
		for id in areaRoots:
			vis[id] = true
	else:
		for a in here:
			vis[a] = true
		# An area behind an open door is drawn only when that doorway is inside the view frustum (or the player /
		# camera stands right at it).
		var fr = null
		if camera != null and camera is Camera3D and camera.is_inside_tree():
			fr = (camera as Camera3D).get_frustum()
		var hop1 := []
		for a in here:
			for id in areas[a].doors:
				var d = doors[id]
				var b: String = d.areas[1] if d.areas[0] == a else d.areas[0]
				if not d.open or here.has(b):
					continue
				if fr != null and not _doorInView(fr, d, ppos if ppos is Vector3 else null, eye):
					continue
				hop1.append([b, d])
				if vis.has(b):
					continue
				vis[b] = true
				hop.append([b, d])
		if camera != null:
			for pair in hop1:
				var b: String = pair[0]
				var d1 = pair[1]
				for id in areas[b].doors:
					var d2 = doors[id]
					var c: String = d2.areas[1] if d2.areas[0] == b else d2.areas[0]
					if d2 == d1 or not d2.open or here.has(c):
						continue
					if not _seenThrough(eye, d1, d2) or (fr != null and not _doorInView(fr, d2, null, eye)):
						continue
					vis[c] = true
	for id in areaRoots:
		areaRoots[id].visible = vis.has(id)
	for d in doors.values():
		d.group.visible = vis.has(d.areas[0]) or vis.has(d.areas[1])
	_cullShadows(here, hop if culled else null, ppos if ppos is Vector3 else null, eye if camera != null else null)

# Shadow casters: only the player's and the camera's areas (plus an area behind an open door when the player
# or camera is within SHADOW_DOOR_R of that door) cast. Areas merely seen through a door still draw, without
# casting. cast_shadow is flipped only on meshes this method turned off, and only when an area's state changes;
# areas not drawn this frame keep their state.
func _cullShadows(here: Array, hop, ppos, eye) -> void:
	var all: bool = not shadowCull or hop == null
	var on := _shadowCast
	on.clear()
	if not all:
		for a in here:
			on[a] = true
		for pair in hop:
			var b: String = pair[0]
			var d = pair[1]
			if not on.has(b) and (_nearDoor(ppos, d) or _nearDoor(eye, d)):
				on[b] = true
	for id in areaRoots:
		if not all and not _visible.has(id):
			continue
		var cast: bool = all or on.has(id)
		var off = _shadowOff.get(id)
		if cast and off != null:
			for m in off:
				if is_instance_valid(m):
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_shadowOff[id] = null
		elif not cast and off == null:
			var list := []
			DAU.traverse(areaRoots[id], func(o):
				if o is GeometryInstance3D and o.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					list.append(o)
			)
			_shadowOff[id] = list

func _nearDoor(v, d) -> bool:
	return v is Vector3 and Vector2(v.x - d.pos.x, v.z - d.pos.z).length() < SHADOW_DOOR_R

# Door d's (grown) opening box against the camera frustum; true right at the door.
func _doorInView(fr: Array, d, ppos, eye) -> bool:
	var cx: float = d.center[0]
	var cz: float = d.center[1]
	if ppos is Vector3 and Vector2(ppos.x - cx, ppos.z - cz).length() < DOOR_NEAR:
		return true
	if eye is Vector3 and Vector2(eye.x - cx, eye.z - cz).length() < DOOR_NEAR:
		return true
	var r: Array = d.rect
	var mn := Vector3(r[0] - 0.3, (d.y0 if d.y0 else 0.0) - 0.1, r[1] - 0.3)
	var mx := Vector3(r[2] + 0.3, (d.y1 if d.y1 else 3.0) + 0.3, r[3] + 0.3)
	# THREE.Frustum.intersectsBox: outside when the box's most-inside corner is beyond any plane
	# (Godot's frustum planes point outward).
	for pl in fr:
		var n: Vector3 = pl.normal
		var c := Vector3(mn.x if n.x > 0 else mx.x, mn.y if n.y > 0 else mx.y, mn.z if n.z > 0 else mx.z)
		if pl.distance_to(c) > 0.0:
			return false
	return true

# True if the camera sees door d2's opening through door d1's opening (2D, on d1's wall line).
func _seenThrough(eye: Vector3, d1, d2) -> bool:
	var axis: String = d1.line[0]
	var at: float = d1.line[1]
	var s0: float = d1.span[0]
	var s1: float = d1.span[1]
	var c2x: float = d2.center[0]
	var c2z: float = d2.center[1]
	var half: float = d2.width * 0.45
	var alongX2: bool = d2.line[0] == "z"
	for o in [0.0, -half, half]:
		var px: float = c2x + o if alongX2 else c2x
		var pz: float = c2z if alongX2 else c2z + o
		var ea: float = eye.x if axis == "x" else eye.z
		var pa: float = px if axis == "x" else pz
		if (ea - at) * (pa - at) >= 0.0:
			continue
		var t := (at - ea) / (pa - ea)
		var s: float = eye.z + t * (pz - eye.z) if axis == "x" else eye.x + t * (px - eye.x)
		if s >= s0 - 0.1 and s <= s1 + 0.1:
			return true
	return false

func renderWith(areaIds: Array, fn: Callable):
	var saved := []
	for id in areaRoots:
		saved.append(areaRoots[id].visible)
	var doorSaved := []
	for d in doors.values():
		doorSaved.append(d.group.visible)
	for id in areaIds:
		setAreaVisible(id, true)
	var res = fn.call()
	var i := 0
	for id in areaRoots:
		areaRoots[id].visible = saved[i]
		i += 1
	i = 0
	for d in doors.values():
		d.group.visible = doorSaved[i]
		i += 1
	return res

func setCeilingsVisible(visible: bool) -> void:
	for a in Layout.AREAS:
		groups[a.id + "#ceil"].visible = visible
	groups["shell#roof"].visible = visible

# --------------------------------------------------------------------------------------------------- power
func setPower(on: bool, opts: Dictionary = {}) -> void:
	var instant: bool = opts.get("instant", false)
	powered = on
	_powerT = 0.0
	for s in _switches:
		s.done = false
		s.sounded = false
		s.state = null
	if not on or instant:
		for s in _switches:
			s.apply.call(on)
			s.state = on
			s.done = true
		_powerDone = true
	else:
		_powerDone = false
	_beaconT = (BEACON_DELAY if instant else 0.0) if on else -1.0
	_setBeacons(false)

func _updatePower(dt: float) -> void:
	if _powerDone:
		return
	_powerT += dt
	var pending := false
	for s in _switches:
		if s.done:
			continue
		var t: float = _powerT - s.delay
		if t < 0.0:
			pending = true
			continue
		var on := true
		for f in FLICKER:
			if t >= f[0]:
				on = f[1]
		if on != s.state:
			s.apply.call(on)
			s.state = on
		if not s.sounded:
			s.sounded = true
			if game.audio != null:
				game.audio.play(s.sound, {"pos": s.pos})
		if t >= FLICKER[FLICKER.size() - 1][0]:
			s.done = true
		else:
			pending = true
	_powerDone = not pending
