# Transmitter Yard dressing (GDD §5.7 "TRANSMITTER YARD", §3.3 lighting, §13 toy_van_radio, §18.13 ids).
# Port of src/world/rooms/yard.js. build(game, area, root) is called by level.gd after the graybox.
#
# Placed (GDD §5.6/§5.7, layout ANCHORS):
#   yd_tower [45,0,-12] (replaces the exterior placeholder tower at runtime and takes over level.beacons, so the
#   level's 1 Hz power blink drives the real beacons), kill_switch_cage = ee_kill_switch on its south face, yd_hut
#   (tube window + 2 scr_feed_yard monitors + SkyCam 13; shifted 1 m east of prop_hut, scaled 0.85 and SkyCam moved to
#   the roof's back-east corner so the cam_yard anchor view is clear — see buildHut), yd_news_van (rear TV
#   scr_feed_yard; its radio sits on a crate beside the cab = toy_van_radio), two sodium posts, the pink/blue WZTV 13
#   neon on the MC wall above DY, drums / crates / film cans, the crew's break corner (lawn chair, cooler, cones), the
#   DY landing apron, wall packs + service panel + posters on the MC wall, the coax trench hut -> tower, fence signs,
#   puddles / gravel / stones / weeds, fireflies and moths. Beyond the fence: a billboard, utility poles with wires,
#   skyline strips, a car. Left clear for other agents: uplink_* (dish r 2.5, cradle, crank, booth: x 35–41.5,
#   z −20…−11.8), set_roller_boogie (NE 3×3 + its camera), and 2 m in front of DY, C1–C3 and G1.
#
# game.level.objects (created if missing):
#   tower          { group, parts:{ upper, beacons[], beaconTop } }
#   tower_beacons  Beacons object: { group, parts:{ beacons[] (top -> bottom) }, mode, color, set_(on),
#                    setMode('blink'|'on'|'off'|'rainbow'), setColor(hex), offSequence(seconds = 1.5), tick(dt) }.
#                    'blink' follows level.beacons (1 Hz after power). Automatic: egg:step {step:4} -> 'rainbow';
#                    machine:boss_start -> offSequence(1.5); game:start -> 'blink'.
#   ee_kill_switch { group, parts:{ door, switch }, pos, stand:Vector3, handle:Vector3, interact:Vector3 }
#                    (door: open = rotation.y ≈ -1.7; switch: thrown = rotation.x ≈ +1.9; the EE/boss code animates them)
#   yard_hut       { group, parts:{ skycam, skycamTilt, skycamTally, doorLight, ceilingLight, windowGlass,
#                    tubes_glowOrange, tubes_glowGreen } }
#   feed_cam_yard_prop { group, parts:{ pan, tilt, tally } }  SkyCam 13: pans ±20° over 8 s (follows the screens'
#                    feed camera when one is exposed); tally lit while powered
#   news_van       { group, parts:{ doorL, doorR, mast, mastHead, domeLight, headlights } }
#   yard_neon      { group, parts:{ neonPink, neonBlue, haloPink, haloBlue }, set_(on) (also "set") }  lights up when
#                    the Sign-On colour wave reaches it (signon.waveReached(pos) if exposed, else lever distance / 15 m/s)
#   sodium_posts   { groups:[g1, g2], parts:{ lamp1, lamp2, beam1, beam2 } }
#   toy_van_radio  { group, parts:{ radio }, playing }      yard_meta { buildMs, fails }
# Toy: toy_van_radio (key-only [E] prompt): 20 s funk loop 'toy_radio' from the radio, which bounces to the beat
# (pressing again stops it).
# Runtime: one render pre-pass tick (skipped while the yard is culled) animates the SkyCam, beacons, neon, radio,
# fireflies and moths.
#
# PORT NOTES (Godot)
# * The yard_* registered props are blender/props/rooms_studios_yard.py (godot/assets/props/yard_*.glb); the loose
#   meshes (DY apron + decal, wheat-pasted posters, hose bib + coil, coax trench covers + cables, the crew cable, the
#   utility wires, SkyCam's roof mast) are blender/runtime/rooms_studios_yard.py -> yard.glb.
# * The fireflies/moths THREE.Points (per-frame positions/colours, additive, size 0.14 with size attenuation) are a
#   MultiMesh of camera-facing quads whose clip-space size reproduces three's point size (size * (H/2) / depth px).
# * put(): the JS try/catch per prop -> a null check (a missing prop is logged by props.gd and recorded in fails).
# * Renames (SPEC §3.2): tower_beacons.set / yard_neon.set -> set_ (yard_neon also under "set").
extends RefCounted

const Kit := preload("res://scripts/world/rooms/studio_a.gd")
const TAU := PI * 2.0
const WAVE_SPEED := 15.0
const HUT_DX := 1.0          # hut shifted east of prop_hut and scaled: keeps the cam_yard anchor clear (see buildHut)
const HUT_S := 0.85
const RAINBOW := ["#FF3B30", "#FFB347", "#FFD23A", "#52E04A", "#3FD6E0", "#3A7BFF", "#D64FD6"]

var game
var area: Dictionary
var root: Node3D
var rand: Callable
var objects: Dictionary
var fails: Array = []
var asset: Node3D = null

var tower: Node3D = null
var beacons = null
var hut: Node3D = null
var skycam = null
var van: Node3D = null
var radio: Node3D = null
var lamps: Array = []
var lampHeads: Array = []
var neon: Node3D = null
var neonIds: Array = []
var neonPools: Array = []
var neonSet = null            # Callable(pink, blue)
var neonPos := Vector3(35.4, 3.5, -8.0)
var wallPacks: Array = []
var critters = null
var radioToy = null
var unsub = null

var powerSeen := false
var powerT := 0.0
var neonState := 0            # 0 off, 1 flickering in, 2 on
var neonT := 0.0
var buzzT := 0.0
var clock := 0.0
var feedCamT := 0.0
var feedCam = null

static func lever() -> Vector3:
	return Kit.lever()

static func hexMul(hex, k: float) -> String:
	var c := DAU.color(hex).srgb_to_linear()
	return "#" + Color(c.r * k, c.g * k, c.b * k).linear_to_srgb().to_html(false)

# ------------------------------------------------------------------------------------------ build
func build(g, a: Dictionary, r: Node3D) -> void:
	game = g
	area = a
	root = r
	rand = Rng.mulberry32(0x9a2d13)
	if not (g.level.get("objects") is Dictionary):
		g.level.objects = {}
	objects = g.level.objects
	asset = Kit.loadAsset(g, "yard")
	var t0 := DAU.nowMs()
	buildTower()
	buildHut()
	buildVan()
	buildLamps()
	buildNeon()
	buildMcWall()
	buildClutter()
	buildGround()
	buildTrench()
	buildFenceSigns()
	buildBeyond()
	buildCritters()
	buildRadioToy()
	startRuntime()
	if asset != null:
		asset.free()
		asset = null
	objects["yard_meta"] = {"buildMs": int(roundf(DAU.nowMs() - t0)), "fails": fails}

func _A(name: String) -> Node3D:
	return Kit.take(asset, name)

# placeProp, isolated: one missing prop must not lose the rest of the room.
func put(id: String, pos, rotY: float = 0.0, opts: Dictionary = {}, o: Dictionary = {}) -> Node3D:
	var oo := {"pos": pos, "rotY": rotY, "opts": opts, "area": area.id}
	oo.merge(o, true)
	var parent: Node = o.get("parent") if o.get("parent") != null else root
	var P = game.get("props")
	var gr: Node3D = P.place(parent, id, oo) if P != null else null
	if gr == null:
		fails.append(id)
		push_warning("[rooms:yard] prop \"%s\" failed" % id)
	return gr

# world position of a prop-local point
func world(gr: Node3D, local) -> Vector3:
	return gr.global_transform * DAU.v3(local)

# registers a prop's local light anchors with ids (so they can be switched)
func anchors(gr: Node3D, prefix: String, extra: Dictionary = {}) -> Array:
	var ids: Array = []
	var las = DAU.ud(gr).get("lightAnchors")
	var L = game.get("lights")
	var i := 0
	for la in (las if las is Array else []):
		var id := "%s_%d" % [prefix, i]
		if L != null and L.has_method("addAnchor"):
			var o: Dictionary = la.duplicate()
			o.merge(extra, true)
			o["id"] = id
			o["pos"] = DAU.arr3(world(gr, la.pos))
			o["area"] = area.id
			L.addAnchor(o)
		ids.append(id)
		i += 1
	return ids

func pool(pos: Array, radius: float, color, intensity: float):
	return Kit.poolOf(game, Vector3(pos[0], pos[1] if pos[1] != null else 0.02, pos[2]), radius, color, intensity)

# ---------------------------------------------------------------------------------------- tower + cage
func buildTower() -> void:
	var g = game
	var tb = Layout.ANCHORS.tower_base
	tower = put("yd_tower", tb.pos, 0.0, {}, {"colliders": false, "lights": false})
	if tower == null:
		return
	# one see-through lattice blocker: stops bodies, lets bullets and the camera through the struts
	var rc: Array = tb.rect
	var col = g.level.get("col")
	if col != null:
		col.addBox([float(rc[0]) - 0.2, 0, float(rc[1]) - 0.2], [float(rc[2]) + 0.2, 3, float(rc[3]) + 0.2], {"tag": "lattice", "camera": false})
	var P := Kit.partsOf(tower)
	var list: Array = []
	for b in (P.get("beacons") if P.get("beacons") is Array else []):
		if b != null:
			list.append(b)
	list.sort_custom(func(x, y): return world(x, [0, 0, 0]).y > world(y, [0, 0, 0]).y)
	objects["tower"] = {"group": tower, "parts": {"upper": P.get("upper"), "beacons": list, "beaconTop": P.get("beaconTop")}}
	beacons = Beacons.new()
	beacons.setup(g, tower, list)
	objects["tower_beacons"] = beacons
	# replace the exterior placeholder tower and take over the level's beacon switch
	var ext = g.level.groups.get("ext") if g.level.get("groups") is Dictionary else null
	if ext != null:
		for nm in ["tower", "tower_beacons"]:
			var o = ext.find_child(nm, true, false)
			if o != null and o.get_parent() != null:
				o.get_parent().remove_child(o)
				o.queue_free()
	var B = beacons
	g.level.beacons = {"mesh": list[0] if not list.is_empty() else null, "set_": func(on): B._level(on)}
	beacons.set_(false)

	var ka = Layout.ANCHORS.ee_kill_switch
	var cage := put("kill_switch_cage", ka.pos, float(ka.rotY))
	if cage != null:
		var u := DAU.ud(cage)
		var cp := Kit.partsOf(cage)
		var an = u.get("anchors")
		var it = u.get("interact")
		objects["ee_kill_switch"] = {
			"group": cage, "parts": {"door": cp.get("door"), "switch": cp.get("switch")},
			"pos": DAU.v3(ka.pos),
			"stand": DAU.v3(ka.stand),
			"handle": world(cage, an.handle if an is Dictionary and an.get("handle") != null else [0, 1.6, 0.1]),
			"interact": world(cage, it.point if it is Dictionary and it.get("point") != null else [0, 1.2, -0.8]),
		}
		# a red work light clamped on the cage roof makes it read at night
		pool([45, 0.02, -9.0], 1.6, "#FF6A4A", 0.16)

class Beacons extends RefCounted:
	var game
	var group: Node3D
	var parts := {}
	var list: Array = []
	var mode := "blink"
	var color: String = Config.PAL.onAirRed
	var _lv := false
	var _state := ""
	var _t := 0.0
	var _seq := 0.0
	var _rk = null
	var _cache := {}

	func setup(g, tower: Node3D, l: Array) -> void:
		game = g
		group = tower
		list = l
		parts = {"beacons": l}

	static func hexMul(hex, k: float) -> String:
		var c := DAU.color(hex).srgb_to_linear()
		return "#" + Color(c.r * k, c.g * k, c.b * k).linear_to_srgb().to_html(false)

	func matOf(on: bool, c) -> Material:
		var key := "%s|%s" % [on, c]
		var m = _cache.get(key)
		if m == null:
			m = game.mats.glow(c, 2.6) if on else Kit.kmat(game, "crt", hexMul(c, 0.35), {"rough": 0.15, "rim": 0.5})
			_cache[key] = m
		return m

	func apply(on: bool) -> void:
		var key := "%s|%s" % [on, color]
		if key == _state:
			return
		_state = key
		for b in list:
			Kit.setMat(b, matOf(on, color))

	func set_(on) -> void:
		apply(Kit.truthy(on))

	func _level(on) -> void:
		_lv = Kit.truthy(on)
		if mode == "blink":
			apply(_lv)

	func setMode(m) -> void:
		mode = str(m)
		_state = ""
		if mode == "on":
			apply(true)
		elif mode == "off":
			apply(false)
		elif mode == "blink":
			apply(_lv)

	func setColor(hex = null) -> void:
		color = str(hex) if Kit.truthy(hex) else Config.PAL.onAirRed
		_state = ""
		if mode != "rainbow":
			setMode(mode)

	func offSequence(seconds = 1.5) -> void:
		mode = "seq"
		_seq = maxf(0.05, float(seconds))
		_t = 0.0
		_state = ""

	func tick(dt: float) -> void:
		if mode == "rainbow":
			_t += dt
			var k := int(floor(_t * 5.0))
			if _rk != null and k == _rk:
				return
			_rk = k
			for i in list.size():
				Kit.setMat(list[i], matOf(true, RAINBOW[(k + i) % RAINBOW.size()]))
			_state = ""
		elif mode == "seq":
			_t += dt
			var n := list.size()
			for i in n:
				Kit.setMat(list[i], matOf(_t < (float(i) / maxf(1.0, n - 1.0)) * _seq, color))
			if _t > _seq:
				mode = "off"
				_state = ""
				apply(false)

# ---------------------------------------------------------------------------------------- hut + SkyCam
func buildHut() -> void:
	# cam_yard [36,3,-3] used to sit INSIDE the hut's roof slab (y 2.85–3.05) with SkyCam 13 filling its lens. The hut
	# is now HUT_DX east of the layout rect and scaled HUT_S (x 36.7–39.5, roof top 2.59): the anchor looks over the
	# roof edge at the yard, and SkyCam rides a mast on the roof's back-east corner, outside that frustum (the virtual
	# feed camera stays at feed_cam_yard; the old centre mast stub stays as a cable mast).
	var a = Layout.ANCHORS.prop_hut
	hut = put("yd_hut", [float(a.pos[0]) + HUT_DX, 0, a.pos[2]], float(a.rotY), {"camYaw": feedYaw(), "camTilt": -0.05}, {"colliders": false, "lights": false})
	if hut == null:
		return
	hut.scale = Vector3(HUT_S, HUT_S, HUT_S)
	var M: Transform3D = hut.global_transform
	var u := DAU.ud(hut)
	var col = game.level.get("col")
	for c in (u.get("colliders") if u.get("colliders") is Array else []):
		var mn := DAU.v3(c.min)
		var mx := DAU.v3(c.max)
		var bb := AABB()
		for i in 8:
			var v := M * Vector3(mx.x if i & 1 else mn.x, mx.y if i & 2 else mn.y, mx.z if i & 4 else mn.z)
			if i == 0:
				bb = AABB(v, Vector3.ZERO)
			else:
				bb = bb.expand(v)
		var copts := {"tag": "prop"}
		if c.get("opts") is Dictionary:
			copts.merge(c.opts, true)
		if col != null:
			col.addBox(DAU.arr3(bb.position), DAU.arr3(bb.end), copts)
	var L = game.get("lights")
	for la in (u.get("lightAnchors") if u.get("lightAnchors") is Array else []):
		if L != null and L.has_method("addAnchor"):
			var o: Dictionary = la.duplicate()
			o["pos"] = DAU.arr3(world(hut, la.pos))
			o["area"] = area.id
			L.addAnchor(o)
	var P := Kit.partsOf(hut)
	if P.get("skycam") != null:
		var sc: Node3D = P.skycam
		sc.position = Vector3(1.5, sc.position.y, 0.95)
		var mast := _A("yd_hut_mast")         # hut-local coordinates (RT = 3.05 roof top)
		if mast != null:
			hut.add_child(mast)
	objects["yard_hut"] = {"group": hut, "parts": P.duplicate()}
	skycam = {"pan": P.get("skycam"), "tilt": P.get("skycamTilt"), "tally": P.get("skycamTally"), "base": feedYaw()}
	objects["feed_cam_yard_prop"] = {"group": P.get("skycam"), "parts": {"pan": P.get("skycam"), "tilt": P.get("skycamTilt"), "tally": P.get("skycamTally")}}
	# warm spill from the window and the door bulb on the gravel
	pool([37.1 + HUT_DX, 0.02, -5.45], 1.4, "#FFD9A0", 0.14)
	pool([39.9, 0.02, -3.4], 1.4, Config.PAL.tungsten, 0.18)

func feedYaw() -> float:
	var F = Layout.ANCHORS.feed_cam_yard
	var p = F.pos
	var t = F.target
	return atan2(-(float(t[0]) - float(p[0])), -(float(t[2]) - float(p[2])))

# ---------------------------------------------------------------------------------------- news van
func buildVan() -> void:
	var a = Layout.ANCHORS.prop_van
	van = put("yd_news_van", a.pos, 0.0, {})
	if van == null:
		return
	var P := Kit.partsOf(van)
	radio = P.get("radio")
	objects["news_van"] = {"group": van, "parts": {"doorL": P.get("doorL"), "doorR": P.get("doorR"), "mast": P.get("mast"), "mastHead": P.get("mastHead"),
		"domeLight": P.get("domeLight"), "headlights": P.get("headlights")}}
	pool([46.2, 0.02, -3.7], 1.7, Config.PAL.tungsten, 0.2)

# ---------------------------------------------------------------------------------------- sodium posts
func buildLamps() -> void:
	var p1 := put("yd_sodium_post", Layout.ANCHORS.prop_lamp_post_1.pos, PI)
	var p2 := put("yd_sodium_post", Layout.ANCHORS.prop_lamp_post_2.pos, PI / 2.0)
	var groups: Array = []
	for p in [p1, p2]:
		if p != null:
			groups.append(p)
	var parts := {}
	for i in groups.size():
		var gr: Node3D = groups[i]
		parts["lamp%d" % (i + 1)] = Kit.partsOf(gr).get("lamp")
		parts["beam%d" % (i + 1)] = Kit.partsOf(gr).get("beam")
		var head := world(gr, [0, 0, -1.94])
		pool([head.x, 0.02, head.z], 4.2, Config.PAL.sodium, 0.34)
		pool([head.x, 0.02, head.z], 1.8, "#FFD08A", 0.2)
	lamps = groups
	objects["sodium_posts"] = {"groups": groups, "parts": parts}
	lampHeads = []
	for gr in groups:
		lampHeads.append(world(gr, [0, 6.35, -1.94]))

# ---------------------------------------------------------------------------------------- neon on the MC wall
func buildNeon() -> void:
	neon = put("yd_neon_wztv", [35.16, 2.95, -8.0], -PI / 2.0, {}, {"lights": false})
	if neon == null:
		return
	neonIds = anchors(neon, "yard_neon")
	neonPools = [pool([36.4, 0.02, -8.7], 2.6, Config.PAL.neonPink, 0.0), pool([36.3, 0.02, -6.9], 2.0, "#3F76FF", 0.0)]
	var M := {
		"pinkOn": game.mats.glow(Config.PAL.neonPink, 2.6), "blueOn": game.mats.glow("#3F76FF", 2.6),
		"pinkOff": Kit.kmat(game, "plastic", "#E8B8C8", {"transparent": true, "opacity": 0.7}),
		"blueOff": Kit.kmat(game, "plastic", "#B8C8E8", {"transparent": true, "opacity": 0.7}),
	}
	var P := Kit.partsOf(neon)
	var S := {"pink": null, "blue": null}
	neonSet = func(pink: bool, blue: bool):
		if pink == S.pink and blue == S.blue:
			return
		S.pink = pink
		S.blue = blue
		if P.get("neonPink") != null:
			Kit.setMat(P.neonPink, M.pinkOn if pink else M.pinkOff)
		if P.get("neonBlue") != null:
			Kit.setMat(P.neonBlue, M.blueOn if blue else M.blueOff)
		if P.get("haloPink") != null:
			P.haloPink.visible = pink
		if P.get("haloBlue") != null:
			P.haloBlue.visible = blue
		var L = game.get("lights")
		if L != null and L.has_method("setAnchor"):
			for i in neonIds.size():
				L.setAnchor(neonIds[i], {"enabled": pink if i == 0 else blue})
		neonPools[0].set_({"intensity": 0.16 if pink else 0.0})
		neonPools[1].set_({"intensity": 0.14 if blue else 0.0})
	neonSet.call(false, false)
	neonPos = Vector3(35.4, 3.5, -8.0)
	var ns: Callable = neonSet
	var setFn := func(on): ns.call(Kit.truthy(on), Kit.truthy(on))
	objects["yard_neon"] = {"group": neon, "parts": P.duplicate(), "set_": setFn, "set": setFn}

# ---------------------------------------------------------------------------------------- MC exterior wall (x = 35)
func buildMcWall() -> void:
	var WX := 35.15
	# DY landing apron: concrete slab with the hazard band and a KEEP CLEAR stencil (+ its top decal plane)
	var apron := _A("yd_apron")
	if apron != null:
		root.add_child(apron)
	# wall packs flanking DY and the service panel north of it
	var wp1 := put("yard_wallpack", [WX, 3.0, -11.0], -PI / 2.0)
	var wp2 := put("yard_wallpack", [WX, 3.0, -5.6], -PI / 2.0)
	wallPacks = []
	for w in [wp1, wp2]:
		if w != null:
			wallPacks.append(w)
	pool([36.3, 0.02, -11.0], 2.8, Config.PAL.sodium, 0.22)
	pool([36.3, 0.02, -5.6], 2.4, Config.PAL.sodium, 0.2)
	put("yard_service_panel", [WX, 0, -12.6], -PI / 2.0)
	# wheat-pasted posters on the block wall ('poster_spooktacular', 'poster_boogie_down' cards)
	var posters := _A("yd_posters")
	if posters != null:
		root.add_child(posters)
	# hose bib + coiled garden hose under the south wall pack
	var hose := _A("yd_hose")
	if hose != null:
		root.add_child(hose)

# ---------------------------------------------------------------------------------------- props with colliders
func buildClutter() -> void:
	# oil drums on a pallet against the MC wall, north of DY (clear of the uplink crank zone)
	put("yd_drum_group", [36.35, 0, -10.75], -PI / 2.0 + 0.12, {"set": "a"})
	# crate stack on the north fence between C1 and the roller rink
	put("yd_crate_stack", [45.55, 0, -19.1], PI + 0.06)
	put("yd_film_cans", [46.95, 0, -18.95], 0.4, {}, {"colliders": false})
	# loose drums
	put("yd_oil_drum", [50.45, 0, -11.55], 0.6, {"color": "red", "seed": 3})
	put("yd_oil_drum", [49.85, 0, -8.2], 1.2, {"color": "yellow", "tipped": true, "seed": 4})
	put("yd_oil_drum", [39.3, 0, -5.75], 2.1, {"color": "green", "seed": 5})
	# the shifted hut leaves a 1.3 m alley along the MC wall: a drum + crate close its mouth (no dead-end camp spot)
	put("yd_oil_drum", [35.5, 0, -5.2], 0.4, {"color": "blue", "seed": 9})
	put("yd_crate", [36.22, 0, -5.28], 0.18, {"size": "md", "seed": 11})
	# crew break corner beside the van's cab: crate with the radio, lawn chair, cooler
	put("yd_crate", [41.0, 0, -5.45], 0.12, {"size": "md", "seed": 7})
	put("yd_crate", [41.05, 0.7, -5.5], -0.25, {"size": "sm", "seed": 8}, {"colliders": false})
	put("yard_lawn_chair", [42.35, 0, -5.75], PI + 0.55)
	put("yard_cooler", [43.35, 0, -5.3], 0.2)
	put("bc_cable_coil", [46.3, 0, -5.05], 0.3, {}, {"colliders": false})
	# cones: one by the gate, two marking the van's open rear, one knocked over near the trench
	put("yard_cone", [46.75, 0, -2.45], 0.2)
	put("yard_cone", [46.55, 0, -5.0], 0.8)
	put("yard_cone", [40.32, 0, -2.3], -0.4)
	var fallen := put("yard_cone", [44.4, 0.16, -7.3], 0.0, {}, {"colliders": false})
	if fallen != null:
		fallen.rotation_order = EULER_ORDER_XYZ
		fallen.rotation = Vector3(0, 0.9, PI / 2.0 - 0.1)
		fallen.position.y = 0.16

# ---------------------------------------------------------------------------------------- ground detail (no colliders)
static func jsRound(x: float) -> int:
	return int(floor(x + 0.5))

func buildGround() -> void:
	var nc := {"colliders": false}
	for p in [[40.6, -9.0, 0.3, 1.3], [48.0, -7.2, 1.9, 1], [44.2, -16.4, 0.7, 0.9], [38.6, -7.4, 2.4, 0.7]]:
		put("yd_puddle", [p[0], 0, p[1]], p[2], {"size": p[3], "seed": jsRound(p[0] * 3.0)}, nc)
	for p in [[42.0, -12.2, 1.2], [47.8, -13.0, 1.0], [45.0, -7.9, 1.4], [39.8, -15.8, 1], [48.8, -16.0, 0.9], [37.6, -9.6, 1.1], [43.0, -18.0, 1]]:
		put("yd_gravel_patch", [p[0], 0, p[1]], 0.0, {"size": p[2], "seed": jsRound(p[1] * 5.0)}, nc)
	for p in [[42.6, -9.6], [47.6, -14.5], [46.2, -6.2], [39.2, -11.6], [50.2, -17.0], [36.2, -13.0], [44.0, -3.0 - 1.9]]:
		put("yd_stones", [p[0], 0, p[1]], rand.call() * TAU, {"seed": jsRound(p[0] * 7.0 + p[1]), "count": 7}, nc)
	for p in [[35.5, -19.6], [50.6, -19.5], [50.6, -2.4], [42.9, -14.25], [47.1, -9.95], [40.2, -2.25], [50.6, -12.6], [35.4, -14.2], [44.1, -19.7]]:
		put("yd_weeds", [p[0], 0, p[1]], rand.call() * TAU, {"seed": jsRound(p[0] * 11.0 + p[1] * 3.0)}, nc)

# ---------------------------------------------------------------------------------------- coax trench hut -> tower
func buildTrench() -> void:
	# The covers, cables and the crew cable are yard.glb 'yd_trench' (world coordinates). The cover jitter drew 3
	# values per cover from the room stream: they are drawn here too so the stream stays in step (critters, buzz).
	var a := Vector2(39.95, -5.1)
	var b := Vector2(42.3, -9.3)
	var n := int(floor((b - a).length() / 0.52))
	for i in n:
		if i == 5:
			continue                         # one cover missing: the cables show
		rand.call()
		rand.call()
		rand.call()
	var tr := _A("yd_trench")
	if tr != null:
		root.add_child(tr)

# ---------------------------------------------------------------------------------------- fence signs
func buildFenceSigns() -> void:
	put("yard_sign", [38.2, 1.7, -19.93], PI, {"kind": "trespass"})
	put("yard_sign", [50.93, 1.8, -11.2], PI / 2.0, {"kind": "danger"})
	put("yard_sign", [45.9, 1.7, -2.07], 0.0, {"kind": "wztv"})
	put("yard_sign", [50.93, 1.5, -3.6], PI / 2.0, {"kind": "gate", "w": 0.5})

# ---------------------------------------------------------------------------------------- beyond the fence
func buildBeyond() -> void:
	var nc := {"colliders": false, "lights": false}
	put("sky_billboard", [44.5, 0, -31.5], PI - 0.08, {"ad": "wztv"}, nc)
	put("sky_skyline", [40, 0, -112], PI, {"seed": 5, "w": 100, "ad": "roller_boogie"}, nc)
	put("sky_skyline", [128, 0, -14], PI / 2.0, {"seed": 9, "w": 90, "ad": "double_vision"}, nc)
	put("st_car_70s", [55.2, 0, 2.6], 0.3, {"color": "#E8A92E"}, nc)
	put("st_hydrant", [52.4, 0, 0.8], 0.5, {}, nc)
	# utility poles with sagging wires along the north and east outside the fence
	for p in [[37.5, -24.5, 0.05, false], [47.0, -24.5, 0, true], [56.5, -18.5, PI / 2.0 - 0.5, false], [57.0, -6.0, PI / 2.0, false], [57.0, 6.5, PI / 2.0, true]]:
		put("yard_utility_pole", [p[0], 0, p[1]], p[2], {"transformer": p[3]}, nc)
	# the wires between the poles + the service drop to the tower: yard.glb 'yd_wires' (world coordinates)
	var wires := _A("yd_wires")
	if wires != null:
		root.add_child(wires)

# ---------------------------------------------------------------------------------------- fireflies + moths
const POINTS_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D map : source_color, filter_linear_mipmap, repeat_disable;
uniform float size = 0.14;
void vertex() {
	// three PointsMaterial (sizeAttenuation): gl_PointSize = size * (H / 2) / depth -> clip-space half extent size / 2
	vec4 c = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vec2 corner = VERTEX.xy * 2.0;
	c.xy += corner * vec2(size * 0.5 * VIEWPORT_SIZE.y / VIEWPORT_SIZE.x, size * 0.5);
	POSITION = c;
}
void fragment() {
	vec4 t = texture(map, UV);
	ALBEDO = COLOR.rgb * t.rgb;
	ALPHA = t.a;
}
"""

func buildCritters() -> void:
	var rnd := rand
	var FF := 34
	var moths := lampHeads.size() * 6 + 5
	var n := FF + moths
	var home: Array = []
	var zones := [[38.5, -8.8, 3.5], [47.8, -7.4, 3], [44.5, -17.2, 3], [49.0, -12.8, 2], [41.0, -12.5, 2.5], [37.5, -18.8, 2]]
	for i in FF:
		var z: Array = zones[i % zones.size()]
		var a: float = rnd.call() * TAU
		var d: float = sqrt(rnd.call()) * float(z[2])
		home.append({"x": z[0] + cos(a) * d, "y": 0.4 + rnd.call() * 1.6, "z": z[1] + sin(a) * d, "ph": rnd.call() * 100.0,
			"sp": 0.4 + rnd.call() * 0.5, "blink": 0.25 + rnd.call() * 0.4, "kind": 0})
	var centers: Array = []
	for h in lampHeads:
		centers.append(Vector3(h.x, h.y - 0.2, h.z))
	centers.append(Vector3(39.8, 2.05, -3.4))
	for i in moths:
		var c: Vector3 = centers[i % centers.size()]
		home.append({"x": c.x, "y": c.y, "z": c.z, "ph": rnd.call() * 100.0, "sp": 2.5 + rnd.call() * 2.0, "r": 0.25 + rnd.call() * 0.4, "kind": 1})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = n
	var sh := Shader.new()
	sh.code = POINTS_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var T = game.get("tex")
	var tex = T.radial() if T != null and T.has_method("radial") else null
	mat.set_shader_parameter("map", tex)
	mat.set_shader_parameter("size", 0.14)
	var pts := MultiMeshInstance3D.new()
	pts.name = "yard_critters"
	pts.multimesh = mm
	pts.material_override = mat
	pts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pts.custom_aabb = AABB(Vector3(43 - 16, 3 - 16, -11 - 16), Vector3(32, 32, 32))   # the JS bounding sphere
	DAU.ud(pts).noMerge = true
	root.add_child(pts)
	critters = {"pts": pts, "mm": mm, "home": home, "n": n, "FF": FF}

# ---------------------------------------------------------------------------------------- toy: van radio
func buildRadioToy() -> void:
	var g = game
	var r := radio
	if r == null:
		return
	# the crew took the radio out of the van: it sits on the crates beside the cab (GDD toy_van_radio [41,1,-4.9])
	Kit.attach(root, r)
	r.rotation_order = EULER_ORDER_XYZ
	r.position = Vector3(41.02, 1.155, -5.5)
	r.rotation = Vector3(0, 0.42, 0)
	var T := {"playing": false, "t": 0.0, "voice": null, "beat": 0}
	radioToy = T
	var pos := Vector3(41.0, 1.2, -5.4)
	var obj := {"group": r, "parts": {"radio": r}, "playing": false}
	var stop := func():
		T.playing = false
		obj.playing = false
		if T.voice != null and T.voice is Object and T.voice.has_method("stop"):
			T.voice.stop(0.25)
		T.voice = null
		r.scale = Vector3(1, 1, 1)
		r.rotation.z = 0.0
	T["stop"] = stop
	var I = g.get("interact")
	if I != null and I.has_method("register"):
		I.register({
			"id": "toy_van_radio", "pos": pos, "radius": 1.6, "height": 2.0,
			"prompt": func() -> Dictionary: return {},
			"use": func() -> void:
				if T.playing:
					stop.call()
					return
				T.playing = true
				obj.playing = true
				T.t = 0.0
				T.beat = 0
				T.voice = g.audio.play("toy_radio", {"pos": pos}) if g.get("audio") != null else null
				if g.get("fx") != null:
					g.fx.burst(Vector3(pos.x, 1.45, pos.z), {"shape": "star", "count": 4, "size": 0.07, "speed": 1.4, "life": 0.6, "gravity": -1}),
		})
	objects["toy_van_radio"] = obj

# ---------------------------------------------------------------------------------------- runtime
func startRuntime() -> void:
	var g = game
	powerSeen = false
	powerT = 0.0
	neonState = 0
	neonT = 0.0
	buzzT = 4.0 + rand.call() * 6.0
	clock = 0.0
	feedCamT = 0.0
	var ev = g.get("events")
	if ev != null:
		ev.on("game:start", func(_p = null):
			if beacons != null:
				beacons.setColor(Config.PAL.onAirRed)
				beacons.setMode("blink")
			if radioToy != null:
				radioToy.stop.call()
			var cage = objects.get("ee_kill_switch")
			if cage != null:
				if cage.parts.get("door") != null:
					cage.parts.door.rotation.y = 0.0
				if cage.parts.get("switch") != null:
					cage.parts.switch.rotation.x = 0.0)
		ev.on("egg:step", func(e = null):
			if e is Dictionary and e.get("step") != null and int(e.step) == 4 and beacons != null:
				beacons.setMode("rainbow"))
		ev.on("machine:boss_start", func(_p = null):
			if beacons != null:
				beacons.offSequence(1.5))
	var R = g.get("render")
	if R != null and R.has_method("addPrePass"):
		unsub = R.addPrePass(func(_r = null): tick())

func tick() -> void:
	var t = game.time
	if not (t is Dictionary):
		return
	var real := float(t.get("realDt", 0.0))
	var dt := float(t.get("dt", 0.0))
	var lv = game.level
	clock += dt
	updatePower(real)
	if beacons != null:
		beacons.tick(dt)
	var rootVisible := true
	if lv.get("areaRoots") is Dictionary and lv.areaRoots.get("yard") != null:
		rootVisible = lv.areaRoots.yard.visible
	if not rootVisible:
		return
	updateSkycam(real)
	updateRadio(dt)
	updateCritters(dt)

func updatePower(dt: float) -> void:
	var g = game
	var M = g.get("machines")
	var on: bool = Kit.truthy(g.level.get("powered")) or (M != null and Kit.truthy(M.get("powerOn")))
	if not on:
		if powerSeen:
			powerSeen = false
			neonState = 0
			if neonSet != null:
				neonSet.call(false, false)
			setTally(false)
		return
	if not powerSeen:
		powerSeen = true
		powerT = 0.0
	powerT += dt
	if neonSet == null:
		return
	if neonState == 0:
		var S = g.get("signon")
		var reached: bool
		if S != null and S.has_method("waveReached"):
			reached = Kit.truthy(S.waveReached(neonPos))
		else:
			reached = powerT >= lever().distance_to(neonPos) / WAVE_SPEED
		if reached or powerT > 8.0:
			neonState = 1
			neonT = 0.0
			setTally(true)
	elif neonState == 1:
		neonT += dt
		var k := neonT
		var onNow := k < 0.06 or (k > 0.14 and k < 0.2) or k > 0.3
		neonSet.call(onNow, onNow if k > 0.18 else false)
		if k > 0.45:
			neonState = 2
			neonSet.call(true, true)
	else:
		# an occasional buzz: the pink tube stutters twice
		buzzT -= dt
		if buzzT < 0.0:
			var k := -buzzT
			neonSet.call(not (k < 0.05 or (k > 0.11 and k < 0.15)), true)
			if k > 0.2:
				buzzT = 5.0 + rand.call() * 9.0
				neonSet.call(true, true)

func setTally(on: bool) -> void:
	var tally = skycam.get("tally") if skycam is Dictionary else null
	if tally == null:
		return
	Kit.setMat(tally, game.mats.glow(Config.PAL.onAirRed, 2.6) if on else Kit.kmat(game, "crt", "#5A1A1A"))

func updateSkycam(dt: float) -> void:
	var S = skycam
	if not (S is Dictionary) or S.get("pan") == null:
		return
	# follow the screens' feed camera when it exposes one, else the GDD pan: ±20° over 8 s
	feedCamT -= dt
	if feedCam == null and feedCamT <= 0.0:
		feedCamT = 2.0
		feedCam = findFeedCam()
	var cam = feedCam
	if cam != null and is_instance_valid(cam) and cam is Node3D:
		# Object3D.getWorldDirection: cameras look down -z (the view direction); other objects +z
		var bz: Vector3 = (cam as Node3D).global_transform.basis.z.normalized()
		var v := -bz if cam is Camera3D else bz
		S.pan.rotation.y = atan2(-v.x, -v.z)
		if S.get("tilt") != null:
			S.tilt.rotation.x = asin(clampf(v.y, -1.0, 1.0))
		return
	S.pan.rotation.y = S.base + (20.0 * PI / 180.0) * sin((float(game.time.realNow) * TAU) / 8.0)

func findFeedCam():
	var s = game.get("screens")
	if s == null:
		return null
	var c = null
	for k in ["feedCams", "feedCameras", "cams", "cameras"]:
		var d = s.get(k)
		if d is Dictionary:
			c = d.get("yard")
			if c == null and k == "cameras":
				c = d.get("feed_cam_yard")
			if c != null:
				break
	if c == null:
		var f = s.get("feeds")
		if f is Dictionary:
			for k in ["yard", "feed_yard"]:
				var e = f.get(k)
				if e is Dictionary and e.get("camera") != null:
					c = e.camera
					break
	if c == null and s.has_method("feedCamera"):
		c = s.feedCamera("yard")
	return c if c is Node3D else null

func updateRadio(dt: float) -> void:
	var T = radioToy
	var r := radio
	if T == null or not T.playing or r == null:
		return
	T.t += dt
	var beat: float = T.t * (96.0 / 60.0)
	var ph := fmod(beat, 1.0)
	var bump := exp(-ph * 7.0)
	r.scale = Vector3(1.0 + bump * 0.05, 1.0 + bump * 0.12 - 0.03, 1.0 + bump * 0.05)
	r.rotation.z = sin(beat * PI) * 0.06
	if int(floor(beat / 2.0)) != T.beat:
		T.beat = int(floor(beat / 2.0))
		if game.get("fx") != null:
			game.fx.burst(Vector3(41.0, 1.45, -5.5), {"shape": "star", "count": 1, "size": 0.05, "speed": 0.9, "life": 0.7, "gravity": -1.2, "colors": [RAINBOW[T.beat % RAINBOW.size()]]})
	if T.t > 20.0:
		T.stop.call()

func updateCritters(_dt: float) -> void:
	var C = critters
	if C == null:
		return
	var time := float(game.time.realNow)
	var home: Array = C.home
	var mm: MultiMesh = C.mm
	for i in int(C.n):
		var h: Dictionary = home[i]
		var x: float
		var y: float
		var z: float
		var b: float
		var col: Color
		if h.kind == 0:
			var s: float = time * h.sp + h.ph
			x = h.x + sin(s * 0.7) * 0.9 + sin(s * 1.9) * 0.25
			y = h.y + sin(s * 1.1) * 0.35
			z = h.z + cos(s * 0.6) * 0.9 + cos(s * 2.3) * 0.2
			var bl := sin(time * TAU * h.blink + h.ph)
			b = (bl - 0.35) * 2.6 if bl > 0.35 else 0.0
			col = Color(0.9 * b, 1.25 * b, 0.25 * b)
		else:
			var s: float = time * h.sp + h.ph
			x = h.x + cos(s) * h.r + sin(s * 3.7) * 0.06
			y = h.y + sin(s * 1.7) * 0.18
			z = h.z + sin(s * 1.3) * h.r
			b = 0.35 + 0.15 * sin(s * 9.0)
			col = Color(1.1 * b, 0.95 * b, 0.7 * b)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
		mm.set_instance_color(i, col)
