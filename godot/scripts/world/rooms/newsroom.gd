# Newsroom "ACTION 13 NEWS" set dressing (GDD §5.7, §3.3, §13 toys; ARCHITECTURE §7/§12). Port of
# src/world/rooms/newsroom.js. build(game, area, root) runs once from level.build() after the graybox. Props come from
# the prop library (game.props.place registers their colliders, light anchors and screens); the room-only props
# (nm_*) are Blender props (blender/props/rooms_newsroom_mc.py) and the meshes the JS added straight under the room
# root are one Blender asset (blender/runtime/rooms_newsroom_mc.py -> res://assets/runtime/rooms_newsroom_mc/newsroom.glb:
# nr_wash, nr_slats_0/1, nr_map_slats + the merged static dressing).
#
# Layout (world metres; walls inner faces x 7.15 / 22.85, z -5.85 / 3.85):
#   anchor riser x 18..22 z -2..2 (0.4 m): curved anchor desk (ee_anchor_desk) facing west, empty anchor chair
#   (ee_anchor_chair), floor globe (toy_globe), two Fresnels on a batten; skyline backdrop + 3 world clocks at 11:59
#   on the east wall; reporter desks 2 x 3 (north row faces the aisle from z -3.55, south row from z 1.05, 0.9 m
#   weave gaps); central aisle z ~-2.3..0 from D1 to the riser; teletype (toy_teletype) in the NW corner with its
#   work lamp (lit before power); weather map (ee_weather_map) on the north wall; coffee cart + water cooler;
#   ss_newsroom monitor bank in the SE corner; feed camera + cart monitor (scr_feed_newsroom); T2 Telly nook (SW,
#   left empty for the Telly agent); moonlight slats under B4/B5 (strong before power).
#
# game.level.objects (created if missing) — ids registered here:
#   ee_anchor_desk  { group, parts:{hairspray}, top:[x,y,z] (puppet seat), drop:[x,y,z] }
#   ee_anchor_chair { group }
#   ee_weather_map  { group, parts:{magnet_sun_a, magnet_sun_b, magnet_cloud, magnet_rain, magnet_bolt, magnet_storm},
#                     anchors (local), towerIcon:Vector3 (world), showMagnet(name, [x,y]|null) (local face coords),
#                     slide(name, [x,y], seconds) (eased slide, world time), flash(on) (map hood light boost) }
#   ss_newsroom     { group, screen (the screen-spawn CRT), screens[] }         mon_newsroom_cart { group, screen }
#   feed_cam_newsroom { group, parts:{head, tilt, tally, lensTip}, setTally(on) }  (head pans ±20° / 8 s here)
#   toy_typewriter / toy_globe / toy_teletype { group, parts, play() }
#   clocks_newsroom { parts:{ny, london, tokyo}, set(h, m, s) (also set_) }       skyline_backdrop { group, wash }
# Toys (GDD §13): key-only [E] prompts via game.interact, cues toy_typewriter / toy_globe / toy_teletype.
# Power: lights, washes, lamps and tallies switch as the Sign-On colour wave reaches them (signon.waveReached(pos)
# when available, else distance-from-lever / 15 m/s after power:on) with the level's 3-flash flicker; a machines
# power reset (new game) switches everything back off.
#
# Shared room toolkit (also used by master_control.gd, static): runtime(game, areaId) -> RoomRuntime, obj(game, id, o),
# place(...), pool(...), yawTo(a, b), setClockHands(...), toy(...), dimmable(mesh) / setLevel(mat, lv) (JS
# dimmableGlow / m.setLevel), additive(mesh) (JS additive), swapGlow(group, color, intensity, to) (JS swapMat),
# plus the prop helpers the JS imported from the prop modules: setLamp (props/broadcast.js), showMagnet
# (props/sets.js), lampMat (a lampMats entry -> material).
#
# Renames (SPEC §3.2): the objects' JS `set` is exposed as both "set" and "set_" Dictionary keys; handle.set -> set_
# (fx light pools). JS try/catch guards around prop placement and switch callbacks are explicit null checks.
# Engine plumbing not ported: the level merge flags (noMerge = the JS merge hints are still written to DAU.ud),
# polygonOffset of the decals / washes (they sit a few mm above their surface).
extends Node

const TAU_ := PI * 2.0
const HP := PI / 2.0
const WAVE_SPEED := 15.0
const FLICKER := [[0.0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]]
const DESK_TOP := 0.76
const DRESSING := "res://assets/runtime/rooms_newsroom_mc/newsroom.glb"

# props/broadcast.js LIT colours (swatch atlas row 2): setLamp(prop, color) rewrites the lamp's UVs to that cell.
const LIT_KEYS := ["red", "amber", "green", "blue", "white", "yellow", "cyan", "magenta", "orange", "tungsten", "purple", "softWhite"]
const AS := 1024.0
const SWS := 32.0

var game
var rt: RoomRuntime = null

# ============================================================================================ runtime
# Room runtime: per-frame tickers (world dt, via render.addPrePass since rooms have no update hook) and power
# switches that fire as the Sign-On colour wave reaches their position.
class RoomRuntime extends RefCounted:
	var game
	var area := ""
	var tickers: Array = []          # Callable(dt, t, real)
	var switches: Array = []
	var powered := false
	var powerT := -1.0
	var t := 0.0
	var _warned := false
	var _noEvent := 0.0
	var _hooked := false
	var LEVER := Vector3.ZERO

	func _init(g, areaId: String) -> void:
		game = g
		area = areaId
		var lp: Array = Layout.ANCHORS.sign_on_lever.pos
		LEVER = Vector3(float(lp[0]), 1.0, float(lp[2]))

	func tick(fn: Callable) -> Callable:
		tickers.append(fn)
		return fn

	# fn(on) is called with the 3-flash flicker (flicker:false -> one switch) when the wave reaches pos.
	func power(pos, fn: Callable, opts: Dictionary = {}) -> Dictionary:
		var p := DAU.v3(pos)
		var s := {"pos": p, "fn": fn, "flicker": opts.get("flicker", true), "sound": opts.get("sound"),
			"delay": LEVER.distance_to(p) / WAVE_SPEED, "state": false, "done": true, "t0": -1.0}
		fn.call(false)
		switches.append(s)
		return s

	func _setAll(on: bool) -> void:
		for s in switches:
			if s.state != on:
				s.fn.call(on)
			s.state = on
			s.done = true
			s.t0 = -1.0

	func start(_p = null) -> void:
		powered = true
		powerT = 0.0
		for s in switches:
			s.done = false
			s.t0 = -1.0

	func frame(_r = null) -> void:
		var tm = game.time if game.time != null else {}
		var dt: float = float(tm.get("dt", 0.0))
		var real: float = float(tm.get("realDt", 0.0))
		var M = game.machines
		var on: bool = M != null and bool(M.powerOn)
		if powered and not on and M != null:
			powered = false
			powerT = -1.0
			_setAll(false)
			_noEvent = 0.0
		if not powered and on:
			_noEvent += real
			if _noEvent > 4.0:
				start()
		else:
			_noEvent = 0.0
		if powered and powerT >= 0.0:
			powerT += real
			var pending := false
			var wr = game.signon if game.signon != null and game.signon.has_method("waveReached") else null
			for s in switches:
				if s.done:
					continue
				if s.t0 < 0.0:
					var reached: bool = powerT >= s.delay
					if wr != null:
						reached = bool(wr.waveReached(s.pos)) or powerT >= s.delay + 3.0
					if not reached:
						pending = true
						continue
					s.t0 = powerT
					if s.sound and game.audio != null:
						game.audio.play(s.sound, {"pos": s.pos})
				var k: float = powerT - s.t0
				var want := true
				if s.flicker:
					for f in FLICKER:
						if k >= f[0]:
							want = f[1]
				if want != s.state:
					s.fn.call(want)
					s.state = want
				if not s.flicker or k >= FLICKER[FLICKER.size() - 1][0]:
					s.done = true
				else:
					pending = true
			if not pending:
				powerT = -1.0
		t += dt
		for f in tickers:
			f.call(dt, t, real)

static func runtime(g, areaId: String) -> RoomRuntime:
	var r := RoomRuntime.new(g, areaId)
	if g.events != null:
		g.events.on("power:on", r.start)
	if g.render != null and g.render.has_method("addPrePass"):
		g.render.addPrePass(r.frame)
		r._hooked = true
	return r

# ============================================================================================ toolkit
static func yawTo(from, to) -> float:
	return atan2(-(float(to[0]) - float(from[0])), -(float(to[2]) - float(from[2])))

# Registers a named object for other systems (GDD §18.13 ids). The Dictionary itself is stored (so Callables made
# before the call can capture it); `id` and `parts` default like the JS { id, parts: {}, ...o }.
static func obj(g, id: String, o: Dictionary) -> Dictionary:
	var lv = g.level
	if lv == null:
		return o
	if not o.has("parts") or o.parts == null:
		o["parts"] = {}
	o["id"] = id
	if lv.get("objects") == null:
		lv.objects = {}
	lv.objects[id] = o
	return o

# placeProp wrapper: area tag + a guard so a missing prop never kills the room.
static func place(g, root: Node, id: String, pos, rotY := 0.0, opts: Dictionary = {}, extra: Dictionary = {}) -> Node3D:
	if g.props == null:
		return null
	var o := {"pos": pos, "rotY": rotY, "opts": opts, "area": extra.get("area")}
	o.merge(extra, true)
	var r = g.props.place(root, id, o)
	if r == null:
		push_warning("[rooms] prop %s failed" % id)
	return r

class NullPool extends RefCounted:
	func set_(_o := {}) -> void:
		pass
	func remove() -> void:
		pass

# Additive floor glow (fx light pool) with a safe fallback.
static func pool(g, pos, radius: float, color, intensity: float):
	var h = null
	if g.fx != null and g.fx.has_method("lightPool"):
		h = g.fx.lightPool(pos, radius, color, intensity)
	return h if h != null else NullPool.new()

# Clock hands to a time (the furniture clocks use rotation.z = fraction of a turn).
static func setClockHands(parts, h, m, s = 0) -> void:
	if parts == null:
		return
	var hh := float(h)
	var mm := float(m)
	var ss := float(s) if s != null else 0.0
	if parts.get("hour") != null:
		parts.hour.rotation.z = ((fmod(hh, 12.0) + mm / 60.0) / 12.0) * TAU_
	if parts.get("minute") != null:
		parts.minute.rotation.z = ((mm + ss / 60.0) / 60.0) * TAU_
	if parts.get("second") != null:
		parts.second.rotation.z = (ss / 60.0) * TAU_

# Key-only toy prompt ([E]) with a cooldown; use() gets called on E.
static func toy(g, id: String, pos, use: Callable, opts: Dictionary = {}):
	if g.interact == null or not g.interact.has_method("register"):
		return null
	var radius: float = opts.get("radius", 1.5)
	var cooldown: float = opts.get("cooldown", 0.4)
	var st := {"last": -1e9}
	return g.interact.register({
		"id": id, "pos": DAU.v3(pos), "radius": radius,
		"prompt": func() -> Dictionary: return {},
		"use": func() -> void:
			var now: float = float(g.time.realNow) if g.time != null else DAU.nowMs() / 1000.0
			if now - st.last < cooldown:
				return
			st.last = now
			use.call(),
	})

# The material a MeshInstance3D draws with (override first, like three's mesh.material).
static func matOf(mesh) -> Material:
	if mesh == null or not (mesh is MeshInstance3D):
		return null
	if mesh.material_override != null:
		return mesh.material_override
	return mesh.get_active_material(0)

# Materials we mutate at runtime (never the shared caches): a lamp glow that can dim (JS dimmableGlow: the Blender
# spec is the glow colour x intensity; this gives the mesh its own copy). Returns the copy.
static func dimmable(mesh) -> Material:
	var m = matOf(mesh)
	if m == null:
		return null
	if m is DAMaterial and m.userData.get("dimmable") == true:
		return m
	var c = m.clone() if m is DAMaterial else m.duplicate()
	if c is DAMaterial:
		c.userData["dimmable"] = true
		c.userData["base"] = c.color
		c.userData["level"] = c.intensity
	mesh.material_override = c
	return c

# JS m.setLevel(lv): colour x level (glow / basic uIntensity multiplies the linear colour, like three).
static func setLevel(m, lv: float) -> void:
	if m is DAMaterial:
		m.userData["level"] = lv
		m.intensity = lv
		if m.twin != null:
			m.twin.set_shader_parameter("uIntensity", lv)

# JS additive(map, color, level): the Blender spec is the MeshBasicMaterial (additive, map, base colour); the mesh
# gets its own copy whose level is set by setLevel (renderOrder -> render_priority).
static func additive(mesh, level: float, renderOrder := 0) -> Material:
	var m = matOf(mesh)
	if m == null:
		return null
	var c = m.clone() if m is DAMaterial else m.duplicate()
	if c is DAMaterial:
		c.userData["base"] = c.color
	c.render_priority = clampi(renderOrder, -128, 127)
	mesh.material_override = c
	setLevel(c, level)
	return c

# Replaces every use of the glow(color, intensity) material inside a placed prop by `to` (JS swapMat).
static func swapGlow(group: Node, color: String, intensity: float, to: Material) -> void:
	var want := color.to_lower()
	DAU.traverse(group, func(o):
		if not (o is MeshInstance3D) or o.mesh == null:
			return
		for i in o.mesh.get_surface_count():
			var m = o.get_active_material(i)
			if m is DAMaterial and m.kind == "glow" and DAU.hex(m.color).to_lower() == want and absf(m.intensity - intensity) < 1e-4:
				o.set_surface_override_material(i, to))

# A lampMats entry ({"__material": spec} from the GLB, or a material) -> material (converted once, cached in place).
static func lampMat(g, holder: Dictionary, key: String) -> Material:
	var v = holder.get(key)
	if v is Material:
		return v
	if v is Dictionary and v.has("__material") and g.mats != null:
		var m = g.mats.fromSpec(v.__material)
		holder[key] = m
		return m
	return null

# props/broadcast.js setLamp(prop, state, partName = 'lamp'): state 'on' | 'off' | a LIT color name. Color changes
# rewrite the lamp's UVs on its own mesh copy.
static func setLamp(prop, state: String, partName := "lamp") -> bool:
	if prop == null:
		return false
	var u := DAU.ud(prop)
	var parts = u.get("parts")
	var mesh = parts.get(partName) if parts is Dictionary else null
	var lm = u.get("lampMats")
	if mesh == null or not (lm is Dictionary):
		return false
	var g = DAGame.inst if DAGame.inst != null else null
	if state == "off":
		mesh.material_override = lampMat(g, lm, "off")
		return true
	if state != "on":
		var i := LIT_KEYS.find(state)
		if i < 0:
			return false
		var cu := (i * SWS + SWS / 2.0) / AS
		var cv := 1.0 - (2.0 * SWS + SWS / 2.0) / AS
		if mesh is MeshInstance3D and mesh.mesh != null:
			var mu := DAU.ud(mesh)
			if not mu.get("ownGeo", false):
				mesh.mesh = mesh.mesh.duplicate()
				mu["ownGeo"] = true
			_fillUV(mesh, cu, cv)
	mesh.material_override = lampMat(g, lm, "on")
	return true

static func _fillUV(mi: MeshInstance3D, u: float, v: float) -> void:
	var src: Mesh = mi.mesh
	if not (src is ArrayMesh):
		return
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var uv := PackedVector2Array()
		uv.resize(n)
		uv.fill(Vector2(u, v))
		arrays[Mesh.ARRAY_TEX_UV] = uv
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, src.surface_get_material(s))
	mi.mesh = out

# props/sets.js showMagnet(prop, name, pos): pos [x,y] on the face (local) or null to hide.
static func showMagnet(prop, name: String, pos) -> void:
	if prop == null:
		return
	var parts = DAU.ud(prop).get("parts")
	var m = parts.get("magnet_%s" % name) if parts is Dictionary else null
	if m == null:
		return
	if pos == null:
		m.visible = false
		return
	m.visible = true
	m.position.x = float(pos[0])
	m.position.y = float(pos[1])
	m.position.z = float(DAU.ud(prop).anchors.face_z) - 0.004
	m.rotation.x = 0.0

# The room's Blender dressing (the meshes the JS added straight under root), added under root at the origin.
static func dressing(g, root: Node, path: String) -> Node3D:
	var d: Node3D = null
	if g.props != null and g.props.has_method("loadRuntime") and ResourceLoader.exists(path):
		d = g.props.loadRuntime(path)
	if d == null:
		push_warning("[rooms] %s missing (run blender/runtime/rooms_newsroom_mc.py)" % path)
		return null
	root.add_child(d)
	return d

static func node(parent: Node, name: String) -> Node:
	return parent.find_child(name, true, false) if parent != null else null

# ============================================================================================ room dressing
func _process(_delta: float) -> void:
	if rt != null and not rt._hooked:
		rt.frame()

func build(g, area: Dictionary, root: Node3D):
	game = g
	var aid: String = area.id
	rt = runtime(g, aid)
	var PAL: Dictionary = Config.PAL
	var A: Dictionary = Layout.ANCHORS
	var L = g.lights
	var hasL: bool = L != null and L.has_method("addAnchor")
	var P := func(id: String, pos, rotY := 0.0, opts: Dictionary = {}, extra: Dictionary = {}) -> Node3D:
		var e := {"area": aid}
		e.merge(extra, true)
		return place(g, root, id, pos, rotY, opts, e)
	var setA := func(id: String, o: Dictionary) -> void:
		if L != null and L.has_method("setAnchor"):
			L.setAnchor(id, o)
	var addA := func(o: Dictionary) -> void:
		if hasL:
			L.addAnchor(o)
	var dr := dressing(g, root, DRESSING)

	# -------------------------------------------------------------------------------- anchor riser (hero)
	var desk: Node3D = P.call("desk_anchor", [20.2, 0.4, 0.0], HP)
	var chair: Node3D = P.call("chair_office", [21.05, 0.4, 0.05], HP + 0.18, {"color": PAL.burntOrange})
	var globe: Node3D = P.call("nm_globe", [19.0, 0.4, 1.2], 0.4)
	obj(g, "ee_anchor_desk", {"group": desk, "parts": (DAU.ud(desk).get("parts", {}) as Dictionary).duplicate() if desk != null else {},
		"top": [20.2, 1.21, 0.0], "drop": [19.6, 0.4, 0.0]})
	obj(g, "ee_anchor_chair", {"group": chair, "parts": {}})
	# Fresnels on a short batten in front of the desk (lit after power); the drop rods are in the dressing asset
	var batY := 3.52
	var batten: Node3D = P.call("bc_grid_batten", [18.1, 0, 0], -HP, {"len": 3})
	if batten != null:
		batten.position.y = batY - float(DAU.ud(batten).hang.pipeY)
	var fresnels: Array = []
	for z in [-0.75, 0.75]:
		var f: Node3D = P.call("bc_light_fresnel", [18.1, 0, z], -HP, {"tilt": 0.72, "gel": "tungsten", "lit": false})
		if f == null:
			continue
		f.position.y = batY - float(DAU.ud(f).hang.pipeY)
		fresnels.append(f)
	var deskPool = pool(g, [20.0, 0.415, 0.0], 2.4, "#FFD9A0", 0.0)
	addA.call({"id": "nr_fresnel", "pos": [19.2, 2.6, 0], "color": "#FFD9A0", "intensity": 0, "distance": 7, "area": aid})
	rt.power([18.1, 3.2, 0], func(on):
		for f in fresnels:
			setLamp(f, "on" if on else "off", "lens")
		deskPool.set_({"intensity": 0.32 if on else 0.0})
		setA.call("nr_fresnel", {"intensity": 4.2 if on else 0.0}), {"sound": "light_thunk"})

	# ------------------------------------------------------------------------ skyline backdrop + world clocks
	var skyZ := 0.5
	var skyW := 4.2
	var sky: Node3D = P.call("nm_skyline", [22.85, 0, skyZ], HP, {"w": skyW, "h": 3.2})
	var wash = node(dr, "nr_wash")
	var washMat = additive(wash, 0.0, 2) if wash != null else null
	addA.call({"id": "nr_backdrop_wash", "pos": [21.9, 2.3, skyZ], "color": "#2E6BD9", "intensity": 0, "distance": 5.5, "area": aid})
	rt.power([22.2, 2, skyZ], func(on):
		setLevel(washMat, 0.55 if on else 0.0)
		setA.call("nr_backdrop_wash", {"intensity": 3.2 if on else 0.0}))
	var clocks := {}
	for e in [["ny", "NEW YORK", skyZ - 0.9], ["london", "LONDON", skyZ], ["tokyo", "TOKYO", skyZ + 0.9]]:
		var c: Node3D = P.call("clock_wall", [22.75, 2.28, e[2]], HP, {"label": e[1], "size": 0.34})
		if c != null:
			clocks[e[0]] = DAU.ud(c).parts
	var setClocks := func(h, m, s = 0) -> void:
		for k in clocks:
			setClockHands(clocks[k], h, m, s)
	obj(g, "clocks_newsroom", {"parts": clocks, "set": setClocks, "set_": setClocks})
	obj(g, "skyline_backdrop", {"group": sky, "wash": wash})

	# --------------------------------------------------------------------------------------- reporter desks
	var northZ := -3.55
	var southZ := 1.05
	var tw := [PAL.harvestGold, PAL.burntOrange, PAL.teal, PAL.avocado, PAL.channelRed]
	# north row faces the aisle (rotY π); the west desk is the toy desk (bare desk + toy typewriter)
	var _toyDesk: Node3D = P.call("nm_desk_bare", [10.6, 0, northZ], PI + 0.02)
	var typer: Node3D = P.call("nm_typewriter", [11.0, DESK_TOP, -3.52], PI - 0.06, {"color": PAL.burntOrange})
	P.call("phone_rotary", [10.1, DESK_TOP, -3.5], PI + 0.4, {"color": "#F4F1E8"})
	# (the paper stack on the toy desk is in the dressing asset)
	P.call("nm_desk_lamp", [11.15, DESK_TOP, -3.85], PI + 0.5, {"color": PAL.burntOrange})
	P.call("desk_reporter", [13.0, 0, northZ], PI - 0.015, {"typewriter": tw[1], "phone": "#E23B3B"})
	P.call("desk_reporter", [15.4, 0, northZ], PI + 0.02, {"typewriter": tw[2], "phone": "#F4F1E8", "color": "#9AA8B4"})
	# south row faces the aisle (rotY 0)
	P.call("desk_reporter", [11.1, 0, southZ], 0.02, {"typewriter": tw[3], "phone": "#2F5BD3", "color": "#9AA8B4"})
	P.call("desk_reporter", [13.5, 0, southZ], -0.01, {"typewriter": tw[0], "phone": "#F4F1E8"})
	P.call("desk_reporter", [15.9, 0, southZ], 0.015, {"typewriter": tw[4], "phone": "#E23B3B"})
	# chairs (pushed out, askew) + one toppled
	P.call("chair_office", [10.9, 0, -2.78], 0.35, {"color": PAL.burntOrange})
	P.call("chair_office", [13.2, 0, -2.72], -0.25, {"color": PAL.harvestGold})
	P.call("chair_office", [11.3, 0, 0.3], PI - 0.4, {"color": PAL.harvestGold})
	P.call("chair_office", [14.65, 0, 0.3], PI + 0.3, {"color": PAL.burntOrange})
	var tipped: Node3D = P.call("chair_office", [15.6, 0, -2.55], 0.0, {"color": PAL.avocado}, {"colliders": false})
	if tipped != null:
		tipped.rotation = Vector3(0, 1.1, HP * 0.98)
		tipped.position.y = 0.3
		var col = g.level.get("col") if g.level != null else null
		if col != null:
			col.addBox([15.0, 0, -3.0], [16.2, 0.62, -2.1], {"tag": "prop"})
	# desk lamps on a few desks (post power)
	var deskLamps: Array = [
		P.call("nm_desk_lamp", [15.72, DESK_TOP, -3.86], PI - 0.5, {"color": PAL.teal}),
		P.call("nm_desk_lamp", [10.75, DESK_TOP, 1.35], 0.4, {"color": PAL.mustard}),
		P.call("nm_desk_lamp", [15.55, DESK_TOP, 1.35], -0.3, {"color": PAL.avocado}),
	].filter(func(l): return l != null)
	var lampMats: Array = []
	for l in deskLamps:
		lampMats.append(dimmable(DAU.ud(l).parts.get("bulb")))
	var lampPools: Array = deskLamps.map(func(l):
		return pool(g, [l.position.x + sin(l.rotation.y) * -0.15, DESK_TOP + 0.01, l.position.z - cos(l.rotation.y) * 0.15], 0.55, "#FFD9A0", 0.0))
	rt.power([13.5, 1, -1], func(on):
		for m in lampMats:
			setLevel(m, 2.4 if on else 0.35)
		for p in lampPools:
			p.set_({"intensity": 0.35 if on else 0.0}))
	# floor clutter: papers, crumpled balls, a spilled folder (dressing asset), trash cans
	P.call("trash_can", [12.0, 0, -4.2], 0.3, {"color": PAL.burntOrange})
	P.call("trash_can", [14.55, 0, 1.6], -0.4, {"color": PAL.avocado})

	# ----------------------------------------------------------------------------- teletype corner (NW)
	var tele: Node3D = P.call("nm_teletype", [8.25, 0, -5.5], PI)
	var tpos: Vector3 = tele.to_global(DAU.v3(DAU.ud(tele).anchors.lamp)) if tele != null else Vector3(8.2, 1.1, -5.3)
	addA.call({"id": "nr_teletype_lamp", "pos": [tpos.x, tpos.y, tpos.z], "color": "#FFB45A", "intensity": 2.4, "distance": 4.5, "area": aid, "flicker": 0.04})
	pool(g, [8.25, 0.01, -4.95], 1.3, "#FFB45A", 0.3)
	# (fan-fold printout pile + newspaper bundles: dressing asset)
	var col2 = g.level.get("col") if g.level != null else null
	if col2 != null:
		col2.addBox([7.3, 0, -5.0], [7.9, 0.4, -4.25], {"tag": "prop"})
	# west wall: filing cabinet, cork board, assignment board (dressing asset), coat tree
	P.call("filing_cabinet", [7.55, 0, -3.75], -HP, {"color": "#C9A06A", "ajar": true})
	P.call("cork_board", [7.15, 1.05, -4.62], -HP, {"w": 1.2, "h": 0.8, "seed": 3})
	P.call("coat_rack", [7.5, 0, 0.65], 0.3)
	P.call("clock_wall", [7.16, 2.75, 1.1], -HP, {"label": "WZTV", "size": 0.42})

	# ------------------------------------------------------------------------------------- north wall
	P.call("water_cooler", [9.2, 0, -5.62], PI)
	P.call("nm_coffee_cart", [10.15, 0, -5.55], PI + 0.06)
	P.call("bookshelf", [14.1, 0, -5.67], PI, {"seed": 5})
	P.call("cork_board", [15.45, 1.1, -5.85], PI, {"w": 0.9, "h": 0.7, "seed": 8})
	# weather map (EE)
	var wmap: Node3D = P.call("weather_map", [17.5, 0.45, -5.9], PI, {}, {"lights": false})
	var hoodMat = g.mats.glow("#FFF2D8", 2.0).clone() if g.mats != null else null
	if hoodMat != null:
		hoodMat.userData["base"] = hoodMat.color
		hoodMat.userData["level"] = 2.0
	if wmap != null and hoodMat != null:
		swapGlow(wmap, "#FFF2D8", 2.0, hoodMat)
	var hood := {"mapHoodLevel": 0.0}
	if wmap != null:
		var u := DAU.ud(wmap)
		var tower: Vector3 = wmap.to_global(DAU.v3(u.anchors.tower_icon))
		var slides: Array = []
		obj(g, "ee_weather_map", {
			"group": wmap, "parts": (u.parts as Dictionary).duplicate(), "anchors": u.anchors, "towerIcon": tower,
			"showMagnet": func(name, pos): showMagnet(wmap, str(name), pos),
			"slide": func(name, to, seconds = 1.2):
				var m = u.parts.get("magnet_%s" % name)
				if m == null:
					return
				m.visible = true
				slides.append({"m": m, "from": [m.position.x, m.position.y], "to": to, "t": 0.0, "d": maxf(0.05, float(seconds))}),
			"flash": func(on): setA.call("nr_weather_hood", {"intensity": 3.5 if on else hood.mapHoodLevel}),
		})
		rt.tick(func(dt, _t, _real):
			for i in range(slides.size() - 1, -1, -1):
				var s: Dictionary = slides[i]
				s.t += dt
				var k: float = minf(1.0, s.t / s.d)
				var e: float = k * k * (3.0 - 2.0 * k)
				s.m.position.x = s.from[0] + (float(s.to[0]) - s.from[0]) * e
				s.m.position.y = s.from[1] + (float(s.to[1]) - s.from[1]) * e
				s.m.position.z = float(u.anchors.face_z) - 0.004
				s.m.rotation.x = 0.0
				if k >= 1.0:
					slides.remove_at(i))
	addA.call({"id": "nr_weather_hood", "pos": [17.5, 2.6, -5.0], "color": "#FFF2D8", "intensity": 0, "distance": 4, "area": aid})
	rt.power([17.5, 2.5, -5.3], func(on):
		hood.mapHoodLevel = 1.6 if on else 0.0
		setLevel(hoodMat, 2.0 if on else 0.2)
		setA.call("nr_weather_hood", {"intensity": hood.mapHoodLevel}))
	P.call("plant_snake", [19.55, 0, -5.55], 0.4, {"seed": 2})
	P.call("plant_rubber", [22.35, 0, -2.35], 1.2, {"seed": 4})

	# ------------------------------------------------------------------------------ south wall + camera
	P.call("bookshelf", [12.4, 0, 3.67], 0.0, {"seed": 9})
	P.call("plant_fern", [15.3, 0, 3.4], 0.6, {"seed": 3})
	P.call("filing_cabinet", [17.6, 0, 3.45], 0.0, {"color": "#8FA38A"})
	var _tv: Node3D = P.call("bc_tv_portable", [17.6, 1.4, 3.5], 0.25, {"color": "orange", "card": "snow"})
	P.call("frame_picture", [12.4, 2.0, 3.85], 0.0, {"card": "poster_precinct13", "style": "chrome", "h": 0.8})
	P.call("bc_teleprompter", [20.7, 0, 2.95], PI * 0.85)
	var cam: Node3D = P.call("bc_pedestal_camera", [16.8, 0, 2.0], yawTo([16.8, 0, 2.0], [20.2, 0, 0.0]), {"num": 2, "tally": false})
	var cart: Node3D = P.call("bc_cart_monitor", [16.4, 0, 3.35], 0.03, {"group": "scr_feed_newsroom", "id": "mon_newsroom_cart", "card": "snow"})
	if cam != null:
		var cp: Dictionary = DAU.ud(cam).parts
		var baseYaw: float = cp.head.rotation.y
		obj(g, "feed_cam_newsroom", {"group": cam, "parts": cp.duplicate(), "setTally": func(on): setLamp(cam, "on" if on else "off", "tally")})
		rt.tick(func(_dt, _t, _real): cp.head.rotation.y = baseYaw + 0.349 * sin((float(g.time.now) / 8.0) * TAU_))
		var cpos := cam.position
		cpos.y = 1.6
		rt.power(cpos, func(on): setLamp(cam, "on" if on else "off", "tally"), {"flicker": false})
	if cart != null:
		var cs: Array = DAU.ud(cart).screens
		obj(g, "mon_newsroom_cart", {"group": cart, "screen": cs[0].get("mesh") if cs.size() > 0 else null})
	pool(g, [16.4, 0.01, 2.75], 0.9, "#7FE7FF", 0.12)
	# ss_newsroom monitor bank in the SE corner (screen spawn = the middle lower CRT)
	var bank: Node3D = P.call("bc_monitor_bank", [22.05, 0, 3.08], PI / 4.0, {
		"cards": ["snow", "snow", "snow", "snow", "snow"], "groups": ["scr_decor", "scr_decor", "scr_decor", "scr_decor", "scr_decor"],
		"ids": ["nr_bank_0", "ss_newsroom", "nr_bank_2", "nr_bank_3", "nr_bank_4"],
	})
	if bank != null:
		var scr: Array = DAU.ud(bank).screens
		var spawn = null
		for s in scr:
			if s.get("id") == "ss_newsroom":
				spawn = s.get("mesh")
				break
		obj(g, "ss_newsroom", {"group": bank, "screen": spawn, "screens": scr.map(func(s): return s.get("mesh"))})
	pool(g, [21.4, 0.01, 2.4], 1.4, "#7FE7FF", 0.16)

	# ------------------------------------------------------------------------------ moonlight slats (B4/B5)
	var slatMats: Array = []
	for n in ["nr_slats_0", "nr_slats_1", "nr_map_slats"]:
		var sm = node(dr, n)
		if sm != null:
			slatMats.append(additive(sm, 0.5, 3 if n == "nr_map_slats" else 1))
	addA.call({"id": "nr_moon_w", "pos": [14, 1.6, 2.6], "color": "#9FB6FF", "intensity": 1.4, "distance": 5, "area": aid})
	addA.call({"id": "nr_moon_e", "pos": [19, 1.6, 2.6], "color": "#9FB6FF", "intensity": 1.4, "distance": 5, "area": aid})
	rt.power([16.5, 1.5, 3], func(on):
		for m in slatMats:
			setLevel(m, 0.16 if on else 0.5)
		setA.call("nr_moon_w", {"intensity": 0.4 if on else 1.4})
		setA.call("nr_moon_e", {"intensity": 0.4 if on else 1.4}), {"flicker": false})

	# ------------------------------------------------------------------------------------------ toys
	if typer != null:
		var p: Dictionary = DAU.ud(typer).parts
		var x0: float = p.carriage.position.x
		var st := {"t": -1.0}
		var play := func() -> void:
			st.t = 0.0
			if g.audio != null:
				g.audio.play("toy_typewriter", {"pos": typer.global_position})
		rt.tick(func(dt, _t, _real):
			if st.t < 0.0:
				return
			st.t += dt
			# two clacks (0.0, 0.25, 0.5), ding + return at 0.8 -> 1.15
			var steps: float = minf(3.0, floorf(st.t / 0.22) + 1.0)
			var inStep: float = fmod(st.t, 0.22) / 0.22
			p.keys.position.y = -0.008 if (st.t < 0.7 and inStep < 0.35) else 0.0
			if st.t < 0.8:
				p.carriage.position.x = x0 + steps * 0.03 - (0.01 if inStep < 0.2 else 0.0)
			else:
				p.carriage.position.x = x0 + 0.09 * (1.0 - minf(1.0, (st.t - 0.8) / 0.3))
			if st.t > 1.2:
				st.t = -1.0
				p.carriage.position.x = x0
				p.keys.position.y = 0.0)
		toy(g, "toy_typewriter", A.toy_typewriter.pos, play, {"cooldown": 1.2})
		obj(g, "toy_typewriter", {"group": typer, "parts": p.duplicate(), "play": play})
	if globe != null:
		var p: Dictionary = DAU.ud(globe).parts
		var st := {"spin": 0.0}
		var play := func() -> void:
			st.spin = 14.0
			if g.audio != null:
				g.audio.play("toy_globe", {"pos": DAU.v3(A.toy_globe.pos)})
		rt.tick(func(dt, _t, _real):
			if st.spin <= 0.001:
				return
			p.globe.rotation.y += st.spin * dt
			st.spin *= exp(-0.9 * dt)
			if st.spin < 0.05:
				st.spin = 0.0)
		toy(g, "toy_globe", A.toy_globe.pos, play, {"cooldown": 0.6})
		obj(g, "toy_globe", {"group": globe, "parts": p.duplicate(), "play": play})
	if tele != null:
		var p: Dictionary = DAU.ud(tele).parts
		var hx: float = p.head.position.x
		var bulbMat = dimmable(p.get("bulb"))
		var paperScale := {"v": 1.0}
		var st := {"t": -1.0}
		var play := func() -> void:
			st.t = 0.0
			if g.audio != null:
				g.audio.play("toy_teletype", {"pos": DAU.v3(A.toy_teletype.pos)})
		rt.tick(func(dt, time, _real):
			if st.t < 0.0:
				setLevel(bulbMat, 2.4 + sin(time * 9.1) * 0.05)
				return
			st.t += dt
			var on: bool = st.t < 3.0
			p.head.position.x = hx + sin(st.t * 38.0) * 0.18 * minf(1.0, st.t * 4.0) if on else hx
			p.keys.position.y = -0.008 if on and sin(st.t * 47.0) > 0.2 else 0.0
			paperScale.v = 1.0 + st.t * 0.12 if on else maxf(1.0, paperScale.v - dt * 0.5)
			p.paper.scale = Vector3(1.0, paperScale.v, paperScale.v)
			p.tape.scale = Vector3.ONE * (1.0 + 0.04 * sin(st.t * 30.0) if on else 1.0)
			if not on and paperScale.v <= 1.0:
				st.t = -1.0)
		toy(g, "toy_teletype", A.toy_teletype.pos, play, {"cooldown": 3.2})
		obj(g, "toy_teletype", {"group": tele, "parts": p.duplicate(), "play": play})

	# fluorescent flicker: one of the level's newsroom troffer anchors buzzes after power (GDD §3.3)
	rt.power([10, 3.5, -1], func(on): setA.call("lvl_newsroom_0", {"flicker": 0.22 if on else 0.0}), {"flicker": false})
	return rt
