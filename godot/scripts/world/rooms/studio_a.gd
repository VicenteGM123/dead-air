# Studio A — "13-HOUR SPOOKTACULAR TELETHON" set dressing (GDD §5.7, lighting §3.3, toys §13) + the small shared
# studio kit that rooms/studio_b.gd uses (place/placeFit/runtime/feedCamera/standMonitor helpers).
# Port of src/world/rooms/studio_a.js.
#
# build(game, area, root)  called by level.gd after the graybox (root = the area's 'dressing' node, in the tree).
#
# Power: rooms follow game.level.powered; each item switches when the Sign-On color wave reaches it (distance to the
# lever / 15 m/s, like level.gd fixtures). Before power: the ghost light + a faint tote board + candle pumpkins.
# After power: gel spots sweeping the stage (additive beams + moving light pools), marquee chase, disco ball + specks,
# ringing pledge phones, lit Fresnels, feed-camera tally.
#
# game.level.objects (other systems read these; all positions are world space). Dictionaries with Callables under the
# JS method names; JS getters are plain fields kept in sync by the room (spinning, value, lit, mode, on):
#   ee_prize_wheel    { group, parts:{ wheel (rot.z), flapper, lever, hub }, hub:Vector3, puppetSeat:Vector3,
#                       spinning, spin({ turns, duration }) -> seconds }        (toy_prize_wheel uses spin())
#   ee_tote_board     { group, parts:{ digits_0..3, thermo_0..3, bulbs, topper }, value, goal:13000,
#                       setValue(v) (flip digits + thermometers), setGlow(0..1) }
#   ee_applause_sign  { group, parts:{ lamp, bulbs }, lit, setLit(on) }   (also drives the red light anchor 'sa_applause')
#   marquee_arch      { group, parts:{ bulbs }, mode, setMode('chase'|'flash'|'on'|'off'|'sparkle'|null=auto) }
#   pledge_carousel   { group, parts:{ handsets, lamps } }      baron_throne { group, parts:{ lever }, seat:Vector3 }
#   ghost_light       { group, parts:{ bulb }, on, set_(on) (also under "set") }    disco_ball { group, parts:{ ball } }
#   feed_cam_studio_a { group, parts:{ head, tilt, tally, lensTip } }  (physical camera; screens.gd owns the feed camera)
#   mon_studio_a_stand / ss_studio_a_w / ss_studio_a_e { group, screen }   (screens registered with those ids)
#   contestant_podiums [{ group }]    studio_a { rt, root, dyn } (debug)
# Toys (key-only [E] prompts): toy_ghost_light (on/off, 'toy_ghost_light'), toy_prize_wheel (spin, 'toy_wheel').
#
# Shared kit (static, used by studio_b.gd): runtime(game, areaId, root, asset) -> Runtime, place(), placeFit(),
# feedCamera(), standMonitor(), yawTo(), beamMaterial(), kmat(), udMat(), setMat(), setInstanceColor(), shadowHygiene().
#
# PORT NOTES (Godot)
# * Room-local geometry (tombstones, pumpkins, fog machine, cue cards, curtain legs, valance, banners/posters with the
#   sa_atlas_v1 canvas atlas, bats + strings, cobwebs, pledge litter, the monitor stand, sandbags, the disco speck
#   disc/band, the gel beam cone) is built by blender/runtime/rooms_studios_yard.py into
#   res://assets/runtime/rooms_studios_yard/studio_a.glb and placed here with the JS positions/rotations/colliders.
# * The JS render pre-pass hook -> game.render.addPrePass (same per-frame semantics). rt.warmMat (shader precompile),
#   bakeInstanced / unlockParts / harvestLenses (static merges) are engine plumbing: the instanced bulbs stay the
#   prop's per-instance nodes, lenses stay in their props (a list swaps their materials like the JS lens group).
# * dyn.attach(x) (moving a part under the noMerge group, world transform kept) changes nothing visible: parts stay
#   where the props put them; the noMerge flags are set like the JS.
# * InstancedMesh.setColorAt / setMatrixAt -> the per-instance child nodes (<name>_<i>): "instanceColor" instance
#   shader parameter / node transform (props.gd convention).
# * The sets.js / broadcast.js helpers the room calls (marqueeChase, setGhostLight, setToteValue, setToteGlow,
#   ringPhone, setLamp) are ported below as static functions.
# * Renames (SPEC §3.2): ghost_light.set -> set_ (also stored under "set").
extends RefCounted

const ASSETS := "res://assets/runtime/rooms_studios_yard/"
const TAU := PI * 2.0
const HP := PI / 2.0
const WAVE := 15.0
const AREA := "studio_a"
const GRID_Y := 6.5

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

# ============================================================================================================ helpers
static func lever() -> Vector3:
	var a = Layout.ANCHORS.sign_on_lever.pos
	return Vector3(float(a[0]), 1.0, float(a[2]))

static func yawTo(a, b) -> float:
	return atan2(-(float(b[0]) - float(a[0])), -(float(b[2]) - float(a[2])))

static func v3(p) -> Vector3:
	return DAU.v3(p)

static func ss(id: String):
	for s in Layout.SCREEN_SPAWNS:
		if s.id == id:
			return s
	return null

# JS truthiness (`!!v`)
static func truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String or v is StringName:
		return v != ""
	return true

# K.mat(game, preset, color, extra) (props/kit.js)
static func kmat(game, preset: String = "plastic", color = "#ffffff", extra: Dictionary = {}) -> Material:
	var o: Dictionary = (MAT.get(preset, {}) as Dictionary).duplicate()
	o["vertexColors"] = true
	o.merge(extra, true)
	return game.mats.toon(color, o)

# A material from a Blender userData value ({"__material": spec}) or a Material.
static func udMat(game, v) -> Material:
	if v is Material:
		return v
	if v is Dictionary and v.get("__material") is Dictionary:
		return game.mats.fromSpec(v.__material)
	return null

# mesh.material = m (every mesh under a node)
static func setMat(node, m) -> void:
	if node == null:
		return
	DAU.traverse(node, func(o):
		if o is GeometryInstance3D:
			(o as GeometryInstance3D).material_override = m)

static func getMat(mesh) -> Material:
	if mesh is MeshInstance3D:
		var mi := mesh as MeshInstance3D
		if mi.material_override != null:
			return mi.material_override
		var m: Material = mi.get_surface_override_material(0)
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
		return m
	return null

static func firstMesh(node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	if node is Node:
		for c in node.get_children():
			var m := firstMesh(c)
			if m != null:
				return m
	return null

static func partsOf(n) -> Dictionary:
	if n == null:
		return {}
	var p = DAU.ud(n).get("parts")
	return p if p is Dictionary else {}

# InstancedMesh.setColorAt(i, c) with a LINEAR THREE.Color -> the "instanceColor" parameter (sRGB) of instance i
static func setInstanceColor(node: Node, lin: Color) -> void:
	if node == null:
		return
	var c := lin.linear_to_srgb()
	DAU.traverse(node, func(o):
		if o is GeometryInstance3D:
			DAU.setInstanceColor(o as GeometryInstance3D, c))

static func instanceNode(im: Node, i: int) -> Node3D:
	if im == null:
		return null
	var n = im.get_node_or_null("%s_%d" % [im.name, i])
	if n == null and i < im.get_child_count():
		n = im.get_child(i)
	return n

# sets.js hdr(color, k): THREE.Color(color) (linear) * k
static func hdr(color, k: float) -> Color:
	var c := DAU.color(color).srgb_to_linear()
	return Color(c.r * k, c.g * k, c.b * k)

# object.attach(child): reparent keeping the world transform
static func attach(parent: Node, child: Node) -> void:
	if parent == null or child == null:
		return
	if child.get_parent() == null:
		parent.add_child(child)
	elif child.get_parent() != parent:
		child.reparent(parent, true)

# Transform of `node` relative to `top` (inclusive of top's own transform) without needing the tree.
static func relXf(top: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		if n == top:
			break
		n = n.get_parent()
	return t

# A Blender-built room asset (materials + userData converted like the props).
static func loadAsset(game, name: String) -> Node3D:
	var P = game.get("props")
	if P == null or not P.has_method("loadRuntime"):
		return null
	return P.loadRuntime(ASSETS + name + ".glb")

# Takes a named child out of the room asset (removed from the asset root, ready to be placed).
static func take(asset: Node, name: String) -> Node3D:
	if asset == null:
		return null
	var n = asset.find_child(name, true, false)
	if n == null:
		push_warning("[rooms] asset node '%s' missing" % name)
		return null
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	return n

# The soft additive light-cone material (fresnel edge fade, fades along the cone). Per-beam color via uniforms.
static var _beamShader: Shader = null
static func beamMaterial(color = "#ffffff", intensity := 0.3) -> ShaderMaterial:
	if _beamShader == null:
		_beamShader = Shader.new()
		_beamShader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 uColor : source_color = vec3(1.0);
uniform float uI = 0.3;
varying float vT;
void vertex() { vT = UV.y; }
void fragment() {
	// pow() bases are clamped (MSAA extrapolated varyings outside the triangle)
	float e = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.8);
	float f = pow(clamp(1.0 - vT, 0.0, 1.0), 1.3) * 0.85 + 0.15;
	ALBEDO = uColor * uI * e * f;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _beamShader
	m.set_shader_parameter("uColor", DAU.color(color))
	m.set_shader_parameter("uI", intensity)
	return m

static func poolOf(game, pos, r: float, color, i: float):
	var F = game.get("fx")
	if F != null and F.has_method("lightPool"):
		var h = F.lightPool(DAU.v3(pos), r, color, i)
		if h != null:
			return h
	return NullPool.new()

class NullPool extends RefCounted:
	func set_(_o := {}) -> void:
		pass
	func remove() -> void:
		pass

# ======================================================================================================= shared kit
# Runtime: a per-room frame hook (render pre-pass, CPU only) with power switching, tickers and resets.
class Runtime extends RefCounted:
	var game
	var areaId := ""
	var root: Node3D
	var asset: Node3D = null            # the room's Blender asset (local builders are taken from it)
	var tickers: Array = []
	var power: Array = []
	var resets: Array = []
	var powered = null
	var waveT := 1e9
	var t := 0.0
	var objects: Dictionary
	var _lever: Vector3

	func setup(g, id: String, r: Node3D) -> void:
		game = g
		areaId = id
		root = r
		var la = Layout.ANCHORS.sign_on_lever.pos
		_lever = Vector3(float(la[0]), 1.0, float(la[2]))
		if not (g.level.get("objects") is Dictionary):
			g.level.objects = {}
		objects = g.level.objects
		var R = g.get("render")
		if R != null and R.has_method("addPrePass"):
			R.addPrePass(func(_r = null): update())
		var ev = g.get("events")
		if ev != null:
			ev.on("game:start", func(_p = null):
				for f in resets:
					f.call())

	# fn(on, instant) runs when the color wave reaches pos (instantly when powering off / at boot)
	func onPower(pos, fn: Callable) -> void:
		power.append({"d": _lever.distance_to(DAU.v3(pos)) / 15.0, "fn": fn, "on": null})

	func onTick(fn: Callable) -> void:      # fn(worldTime, worldDt, areaVisible)
		tickers.append(fn)

	func onReset(fn: Callable) -> void:
		resets.append(fn)

	func anchor(id: String, o: Dictionary):
		var L = game.get("lights")
		if L == null or not L.has_method("addAnchor"):
			return null
		var a := {"id": id, "area": areaId}
		a.merge(o, true)
		return L.addAnchor(a)

	func setAnchor(id: String, o: Dictionary) -> void:
		var L = game.get("lights")
		if L != null and L.has_method("setAnchor"):
			L.setAnchor(id, o)

	func pool(pos, r: float, color, i: float):
		var F = game.get("fx")
		if F != null and F.has_method("lightPool"):
			var h = F.lightPool(DAU.v3(pos), r, color, i)
			if h != null:
				return h
		return NullPool.new()

	func update() -> void:
		var tm = game.get("time")
		if not (tm is Dictionary):
			return
		var lv = game.get("level")
		var pw = lv.get("powered") if lv != null else null
		var want: bool = pw == true or ((pw is int or pw is float) and pw != 0)
		if powered == null or (not want and powered):
			for p in power:
				if p.on != want:
					p.on = want
					p.fn.call(want, true)
			powered = want
			waveT = 1e9
		elif want and not powered:
			powered = true
			waveT = 0.0
		if waveT < 1e8:
			waveT += minf(0.1, float(tm.get("realDt", 0.0)))
			var pending := false
			for p in power:
				if p.on == true:
					continue
				if waveT >= p.d:
					p.on = true
					p.fn.call(true, false)
				else:
					pending = true
			if not pending:
				waveT = 1e9
		var now := float(tm.get("now", 0.0))
		var dt := maxf(0.0, minf(0.1, now - t))
		t = now
		var vis := false
		if lv != null and lv.get("areaRoots") is Dictionary:
			var ar = lv.areaRoots.get(areaId)
			vis = ar != null and ar.visible
		for f in tickers:
			f.call(now, dt, vis)

static func runtime(game, areaId: String, root: Node3D, asset: Node3D = null) -> Runtime:
	var rt := Runtime.new()
	rt.setup(game, areaId, root)
	rt.asset = asset
	return rt

# Places a registered prop (like props.gd place) with scale, collider override, optional light anchors,
# screen group/id override. o.group = a prebuilt group. Returns the group.
static func place(game, parent: Node, id, o: Dictionary = {}) -> Node3D:
	var pos = o.get("pos", [0, 0, 0])
	var rotY := float(o.get("rotY", 0.0))
	var sc := float(o.get("scale", 1.0))
	var opts: Dictionary = o.get("opts") if o.get("opts") is Dictionary else {}
	var area = o.get("area")
	var colliders = o.get("colliders", true)
	var lights = o.get("lights", false)
	var screens = o.get("screens", true)
	var tag = o.get("tag", "prop")
	var g: Node3D = o.get("group")
	if g == null:
		g = game.props.build(str(id), opts) if id != null and game.get("props") != null else null
	if g == null:
		push_warning("[rooms] prop \"%s\" failed" % str(id))
		return null
	g.rotation_order = EULER_ORDER_XYZ
	g.position = Vector3(float(pos[0]), float(pos[1]) if pos.size() > 1 and pos[1] != null else 0.0, float(pos[2]))
	g.rotation = Vector3(0, rotY, 0)
	if sc != 1.0:
		g.scale = Vector3(sc, sc, sc)
	if g.get_parent() != null:
		g.get_parent().remove_child(g)
	parent.add_child(g)
	var M: Transform3D = g.global_transform
	var u := DAU.ud(g)
	var boxes: Array = []
	if colliders is Array:
		boxes = colliders
	elif truthy(colliders):
		boxes = u.get("colliders") if u.get("colliders") is Array else []
	var lv = game.get("level")
	var col = lv.get("col") if lv != null else null
	if not boxes.is_empty() and col != null:
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
			var copts := {"tag": tag}
			if c.get("opts") is Dictionary:
				copts.merge(c.opts, true)
			col.addBox(DAU.arr3(bb.position), DAU.arr3(bb.end), copts)
	var L = game.get("lights")
	if truthy(lights) and L != null and L.has_method("addAnchor"):
		for a in (u.get("lightAnchors") if u.get("lightAnchors") is Array else []):
			var la: Dictionary = a.duplicate()
			la["pos"] = DAU.arr3(M * DAU.v3(a.pos))
			la["area"] = a.get("area") if a.get("area") != null else area
			L.addAnchor(la)
	var S = game.get("screens")
	if truthy(screens) and S != null and S.has_method("register"):
		var i := 0
		for s in (u.get("screens") if u.get("screens") is Array else []):
			var screenId = o.get("screenId")
			var sid = (screenId if i == 0 else "%s_%d" % [screenId, i]) if truthy(screenId) else s.get("id")
			var grp = o.get("screenGroup")
			if not truthy(grp):
				grp = s.get("group")
			if not truthy(grp):
				grp = "scr_decor"
			S.register(s.get("mesh"), grp, {"id": sid} if truthy(sid) else {})
			i += 1
	return g

# Places a prop so that a local point of it (fit(g) -> Node3D | Vector3 in prop space) lands on `target`.
static func placeFit(game, parent: Node, id, o: Dictionary = {}) -> Node3D:
	var g: Node3D = o.get("group")
	if g == null:
		g = game.props.build(str(id), o.get("opts") if o.get("opts") is Dictionary else {})
	if g == null:
		push_warning("[rooms] prop \"%s\" failed" % str(id))
		return null
	var ref = (o.fit as Callable).call(g)
	var lp: Vector3 = relXf(g, ref).origin if ref is Node3D else DAU.v3(ref)
	var s := float(o.get("scale", 1.0))
	lp = (lp * s).rotated(Vector3.UP, float(o.get("rotY", 0.0)))
	var t := DAU.v3(o.target)
	var pos := [t.x - lp.x, float(o.floorY) if o.get("floorY") != null else t.y - lp.y, t.z - lp.z]
	var o2 := o.duplicate()
	o2["group"] = g
	o2["pos"] = pos
	return place(game, parent, id, o2)

static func hashPhase(s: String) -> float:
	var h := 0
	for i in s.length():
		h = (h * 31 + s.unicode_at(i)) % 997
	return (float(h) / 997.0) * TAU

# A studio feed camera (bc_pedestal_camera) whose lens sits near the feed anchor; the prop is shifted sideways by
# `side` metres (keeps lanes clear; the virtual feed camera stays at the anchor, the prop never enters its view).
static func feedCamera(game, rt: Runtime, parent: Node, anchorId: String, o: Dictionary = {}) -> Node3D:
	var num = o.get("num", 1)
	var side := float(o.get("side", 0.0))
	var colliders = o.get("colliders")
	var a = Layout.ANCHORS[anchorId]
	var yaw := yawTo(a.pos, a.target)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var org := v3(a.pos)
	org.y = 0.0
	org += fwd * -0.74 + right * side
	var g := place(game, parent, "bc_pedestal_camera", {
		"pos": DAU.arr3(org), "rotY": yaw, "opts": {"num": num, "tally": false},
		"colliders": colliders if colliders != null else [{"min": [-0.46, 0, -0.46], "max": [0.46, 1.9, 0.5]}],
	})
	if g == null:
		return null
	var P := partsOf(g)
	var head: Node3D = P.get("head")
	var tilt: Node3D = P.get("tilt")
	var tally = P.get("tally")
	var lensTip = P.get("lensTip")
	var lensY := 1.44
	var d := Vector2(float(a.target[0]) - float(a.pos[0]), float(a.target[2]) - float(a.pos[2])).length()
	if tilt != null:
		tilt.rotation_order = EULER_ORDER_XYZ
		tilt.rotation.x = atan2(float(a.target[1]) - lensY, d)
	var mats = DAU.ud(g).get("lampMats")
	var mOn := udMat(game, mats.get("on")) if mats is Dictionary else null
	var mOff := udMat(game, mats.get("off")) if mats is Dictionary else null
	rt.onPower(a.pos, func(on, _instant = false): setMat(tally, mOn if on else mOff))
	var phase := hashPhase(anchorId)
	rt.onTick(func(t, _dt, vis):
		# the feed camera (screens.gd) pans a head it drives in step with its picture: skip that one
		if vis and head != null and not head.has_meta(&"da_feed_head"):
			head.rotation.y = 0.349 * sin((t / 8.0) * TAU + phase))
	rt.objects[anchorId] = {"group": g, "parts": {"head": head, "tilt": tilt, "tally": tally, "lensTip": lensTip}}
	return g

# Feed monitor on a rolling AV stand; screen center lands on the anchor (faces the anchor's rotY).
# The stand is the Blender-built 'monitor_stand_<anchorId>' of the room asset (rt.asset).
static func standMonitor(game, rt: Runtime, parent: Node, anchorId: String) -> Node3D:
	var a = Layout.ANCHORS[anchorId]
	var size := 19.6
	var s := size / 14.0
	var topY: float = float(a.pos[1]) - (0.37 * s) * 0.57     # monitor base so the screen center is at a.pos.y
	var stand := take(rt.asset, "monitor_stand_" + anchorId)
	if stand != null:
		place(game, parent, null, {"group": stand, "pos": [a.pos[0], 0, a.pos[2]], "rotY": float(a.get("rotY", 0.0)),
			"colliders": [{"min": [-0.36, 0, -0.34], "max": [0.36, topY + 0.5, 0.34]}]})
	var mon := placeFit(game, parent, "bc_rack_monitor", {
		"opts": {"size": size, "card": "snow", "group": a.group, "id": anchorId}, "rotY": float(a.get("rotY", 0.0)), "colliders": false,
		"fit": func(g): return DAU.ud(g).screens[0].mesh, "target": a.pos, "screenGroup": a.group, "screenId": anchorId,
	})
	var scr = null
	if mon != null and DAU.ud(mon).get("screens") is Array and not DAU.ud(mon).screens.is_empty():
		scr = DAU.ud(mon).screens[0].get("mesh")
	rt.objects[anchorId] = {"group": mon, "screen": scr, "stand": stand}
	return mon

# Parts the level will not merge (under a noMerge / dynamic node) each cost a shadow draw: unlit glow (bulbs,
# candle faces) and parts under ~0.3 m never cast (ARCHITECTURE §5).
static func shadowHygiene(root: Node) -> void:
	_hyg(root, false)

static func _hyg(o: Node, unmerged: bool) -> void:
	var u = DAU.ud(o) if o.has_meta("userData") else {}
	var um: bool = unmerged or truthy(u.get("noMerge")) or truthy(u.get("dynamic"))
	if um and o is MeshInstance3D and (o as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		var mi := o as MeshInstance3D
		var bb := mi.get_aabb()
		var gs: Vector3 = mi.global_transform.basis.get_scale() if mi.is_inside_tree() else mi.scale
		var r: float = bb.size.length() * 0.5 * maxf(gs.x, maxf(gs.y, gs.z))
		var m := getMat(mi)
		var unlit: bool = m is DAMaterial and ((m as DAMaterial).kind == "glow" or (m as DAMaterial).kind == "basic")
		if r < 0.3 or unlit or (m is ShaderMaterial and not (m is DAMaterial)):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in o.get_children():
		_hyg(c, um)

# ---------------------------------------------------------------------------------- prop runtime helpers (sets.js)
# Chase the marquee bulbs. mode: 'chase' (every 3rd bulb runs), 'flash' (all blink), 'on', 'off' (dim), 'sparkle'
static func marqueeChase(prop, t: float = 0.0, mode = "chase", speed := 9.0, bright := 3.2) -> void:
	if prop == null:
		return
	var im = partsOf(prop).get("bulbs")
	var ch = DAU.ud(prop).get("chase")
	if im == null or not (ch is Dictionary):
		return
	var step := int(floor(t * speed))
	var on := DAU.color(ch.on).srgb_to_linear()
	var dim := DAU.color(ch.dim).srgb_to_linear()
	for i in int(ch.count):
		var k: float
		if mode == "off":
			k = 0.0
		elif mode == "on":
			k = 1.0
		elif mode == "flash":
			k = float(step % 2)
		elif mode == "sparkle":
			k = 1.0 if ((i * 7919 + step * 104729) % 11) < 4 else 0.25
		else:
			k = 1.0 if (i + step) % 3 == 0 else 0.18
		var c: Color
		if k <= 0.0:
			c = Color(dim.r * 0.5, dim.g * 0.5, dim.b * 0.5)
		else:
			c = Color(on.r * bright * k, on.g * bright * k, on.b * bright * k)
		setInstanceColor(instanceNode(im, i), c)

# on=false swaps the bulb to an unlit frosted-glass material (pass game the first time).
static func setGhostLight(prop, on: bool, game = null) -> void:
	var b = partsOf(prop).get("bulb")
	if b == null:
		return
	var u := DAU.ud(prop)
	if u.get("_bulbOn") == null:
		u["_bulbOn"] = getMat(firstMesh(b))
	if u.get("_bulbOff") == null and game != null:
		u["_bulbOff"] = kmat(game, "ceramic", "#E8E0D0")
	setMat(b, u._bulbOn if (on or u.get("_bulbOff") == null) else u._bulbOff)

# rattles handset i and blinks its lamp (call per frame while ringing; t = seconds)
static func ringPhone(prop, i: int, t: float = 0.0, ringing: bool = true) -> void:
	var u := DAU.ud(prop)
	var P := partsOf(prop)
	var hs = P.get("handsets")
	var lamps = P.get("lamps")
	var phones = u.get("phones")
	if hs == null or not (phones is Array) or i >= phones.size():
		return
	var ph = phones[i]
	var k := sin(t * 60.0) * 0.5 + 0.5 if ringing else 0.0
	var p := DAU.v3(ph.pos)
	p.y += k * 0.012
	var e := Vector3(0, float(ph.rotY) + (sin(t * 47.0) * 0.06 if ringing else 0.0), sin(t * 53.0) * 0.08 if ringing else 0.0)
	var n := instanceNode(hs, i)
	if n != null:
		n.transform = Transform3D(Basis.from_euler(e, EULER_ORDER_XYZ).scaled(Vector3(1.22, 1.22, 1.22)), p)
	if lamps != null:
		setInstanceColor(instanceNode(lamps, i), hdr(Config.PAL.onAirRed, 3.2 if ringing and int(floor(t * 6.0)) % 2 == 0 else 0.35))

static func fmtTote(v) -> String:
	if v is String:
		return v
	var n := int(floorf(float(v) + 0.5))
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	out = "$" + ("-" if n < 0 else "") + out
	while out.length() < 7:
		out = " " + out
	return out.substr(out.length() - 7)

# writeStripUV: the digit strip's quads (7 chars, pitch 0.162, 0.15 x 0.2) show the tote_digits atlas cells of str.
# Quads are identified by their vertex positions (the glTF may reorder vertices).
const TOTE_CHARS := "0123456789$,"
static func setStrip(mesh, s: String) -> void:
	var mi := firstMesh(mesh)
	if mi == null or mi.mesh == null:
		return
	var src: Mesh = mi.mesh
	var arrays := src.surface_get_arrays(0)
	var mat := getMat(mi)
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var n := 7
	var pitch := 0.162
	for vi in pos.size():
		var x := pos[vi].x
		var y := pos[vi].y
		var i := clampi(int(roundf((n - 1) / 2.0 - x / pitch)), 0, n - 1)
		var x0 := ((n - 1) / 2.0 - i) * pitch
		var ch := s[i] if i < s.length() else " "
		var r: Array
		if ch == " ":
			r = [0.001, 0.001, 0.002, 0.002]
		else:
			var ci := maxi(0, TOTE_CHARS.find(ch))
			var cc := ci % 4
			var rr := ci / 4
			r = [(cc * 128) / 512.0, 1.0 - ((rr + 1) * 168) / 504.0, ((cc + 1) * 128) / 512.0, 1.0 - (rr * 168) / 504.0]
		var e := 0.002
		var u0: float = r[0] + e
		var v0: float = r[1] + e
		var u1: float = r[2] - e
		var v1: float = r[3] - e
		# corners: [x0+tw/2,-th/2]=(u0,v0) [x0-tw/2,-th/2]=(u1,v0) [x0-tw/2,th/2]=(u1,v1) [x0+tw/2,th/2]=(u0,v1)
		var uu := u0 if x > x0 else u1
		var vv := v0 if y < 0.0 else v1
		uv[vi] = Vector2(uu, 1.0 - vv)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = am
	if mat != null and mi.material_override == null:
		mi.material_override = mat

static func setToteValue(prop, value) -> void:
	var P := partsOf(prop)
	if P.is_empty():
		return
	var u := DAU.ud(prop)
	var s := fmtTote(value)
	for i in 4:
		setStrip(P.get("digits_%d" % i), s)
	var goal := 13000.0
	if u.get("tote") is Dictionary and truthy(u.tote.get("goal")):
		goal = float(u.tote.goal)
	var k := clampf((float(value) if (value is float or value is int) else 0.0) / goal, 0.02, 1.0)
	for i in 4:
		var th = P.get("thermo_%d" % i)
		if th != null:
			th.scale.y = k
	if u.get("tote") is Dictionary:
		u.tote["value"] = value

# level 0..1: before power the digits only glow faintly (0.3)
static func setToteGlow(prop, game, level: float = 1.0) -> void:
	var P := partsOf(prop)
	if P.is_empty() or game == null:
		return
	var u := DAU.ud(prop)
	if u.get("_digitsMap") == null:
		var m0 := getMat(firstMesh(P.get("digits_0")))
		u["_digitsMap"] = m0.map if m0 is DAMaterial else null
	var tex = u.get("_digitsMap")
	if tex == null and game.get("cards") != null and game.cards.has_method("getCard"):
		tex = game.cards.getCard("tote_digits", {})
	var m: Material = game.mats.glow("#ffffff", 0.25 + 0.85 * clampf(level, 0.0, 1.0), {"map": tex})
	for i in 4:
		var d = P.get("digits_%d" % i)
		if d != null:
			setMat(d, m)

# props/broadcast.js setLamp(prop, state, partName = 'lamp'): swaps the lamp part to userData.lampMats.on / .off.
static func setLamp(prop, state: String, partName: String = "lamp") -> bool:
	if prop == null:
		return false
	var lm = DAU.ud(prop).get("lampMats")
	var mesh = partsOf(prop).get(partName)
	if mesh == null or not (lm is Dictionary):
		return false
	setMat(mesh, udMat(DAGame.inst, lm.get("off") if state == "off" else lm.get("on")))
	return true

# ============================================================================================================ build
var game
var rt: Runtime

func build(g, area: Dictionary, root: Node3D) -> void:
	game = g
	var asset := loadAsset(g, "studio_a")
	rt = runtime(g, AREA, root, asset)
	var O: Dictionary = rt.objects
	var dyn := DAU.node3d("studio_a_dynamic")     # animated / swapped at runtime: never merged by the level
	DAU.ud(dyn).noMerge = true
	root.add_child(dyn)
	var P := func(id, o: Dictionary) -> Node3D:
		var oo := {"area": AREA}
		oo.merge(o, true)
		return place(g, root, id, oo)
	var A := func(name: String) -> Node3D: return take(asset, name)

	# ---------------------------------------------------------------------------------------------- the stage
	var wheelA = Layout.ANCHORS.ee_prize_wheel
	var wheel: Node3D = P.call("pledge_wheel", {"pos": wheelA.pos, "rotY": wheelA.rotY})
	if wheel != null:
		DAU.ud(wheel).noMerge = true
		var hubObj := DAU.node3d("hub")
		hubObj.position = DAU.v3(DAU.ud(wheel).anchors.hub)
		wheel.add_child(hubObj)
		var seat: Vector3 = wheel.global_transform * DAU.v3(DAU.ud(wheel).anchors.puppet_seat)
		var wheelState := {"spinning": false, "t": 0.0, "dur": 0.0, "from": 0.0, "to": 0.0, "lastPeg": 0, "flap": 0.0}
		var wp := partsOf(wheel)
		var wW: Node3D = wp.get("wheel")
		var wF: Node3D = wp.get("flapper")
		var wL: Node3D = wp.get("lever")
		var wheelObj := {
			"group": wheel, "parts": {"wheel": wW, "flapper": wF, "lever": wL, "hub": hubObj},
			"hub": hubObj.global_position, "puppetSeat": seat, "spinning": false,
		}
		wheelObj["spin"] = func(o = {}) -> float:
			if wheelState.spinning:
				return 0.0
			var turns: float = float(o.turns) if o is Dictionary and o.get("turns") != null else 2.2 + randf() * 2.4
			var duration: float = float(o.duration) if o is Dictionary and o.get("duration") != null else 4.1
			wheelState.merge({"spinning": true, "t": 0.0, "dur": duration, "from": wW.rotation.z, "to": wW.rotation.z - turns * TAU}, true)
			wheelObj.spinning = true
			return duration
		O["ee_prize_wheel"] = wheelObj
		rt.onTick(func(t, dt, _vis):
			var s := wheelState
			if s.spinning:
				s.t += dt
				var k := minf(1.0, s.t / s.dur)
				var e := 1.0 - pow(1.0 - k, 2.6)
				wW.rotation.z = s.from + (s.to - s.from) * e
				var pull := minf(1.0, s.t / 0.15) * (1.0 - minf(1.0, maxf(0.0, s.t - 0.35) / 0.4))
				wL.rotation.z = -0.9 * pull
				var peg := int(floor(-wW.rotation.z / (TAU / 13.0)))
				if peg != s.lastPeg:
					s.lastPeg = peg
					s.flap = 1.0
				if k >= 1.0:
					s.spinning = false
					wheelObj.spinning = false
			if s.flap > 0.0:
				s.flap = maxf(0.0, s.flap - dt * 9.0)
				wF.rotation.z = 0.45 * s.flap * (sin(t * 60.0) * 0.3 + 0.7))
		rt.onReset(func():
			wheelState.spinning = false
			wheelObj.spinning = false
			wL.rotation.z = 0.0)

	var throne: Node3D = P.call("baron_throne", {"pos": Layout.ANCHORS.prop_throne.pos, "rotY": Layout.ANCHORS.prop_throne.rotY})
	if throne != null:
		O["baron_throne"] = {"group": throne, "parts": partsOf(throne), "seat": throne.global_transform * DAU.v3(DAU.ud(throne).anchors.seat)}

	# contestant podiums (front-east of the stage, facing the audience)
	var podiums := [[8.33, -26.62, PI + 0.1, "$130"], [9.4, -26.56, PI, "$250"], [10.45, -26.62, PI - 0.12, "$13"]]
	var podiumList: Array = []
	for i in podiums.size():
		var pd: Array = podiums[i]
		var pg: Node3D = P.call("contestant_podium", {"pos": [pd[0], 0.6, pd[1]], "rotY": pd[2], "opts": {"num": i + 1, "score": pd[3]}})
		podiumList.append({"group": pg})
	O["contestant_podiums"] = podiumList

	# ghost light (toy) — the only light before Sign-On
	var gl = Layout.ANCHORS.toy_ghost_light
	var ghost: Node3D = P.call("ghost_light", {"pos": gl.pos, "rotY": 0.4})
	var ghostPos := [float(gl.pos[0]), float(gl.pos[1]) + 1.75, float(gl.pos[2])]
	rt.anchor("sa_ghost", {"pos": ghostPos, "color": "#FFE0A8", "intensity": 5.5, "distance": 11})
	var ghostPool = rt.pool([gl.pos[0], 0.62, gl.pos[2]], 2.6, "#FFD9A0", 0.22)
	var ghostState := {"on": true, "powered": false}
	var ghostObj := {"group": ghost, "parts": {"bulb": partsOf(ghost).get("bulb")}, "on": true}
	if ghost != null:
		setGhostLight(ghost, false, g)
		setGhostLight(ghost, true)
	var applyGhost := func():
		if ghost != null:
			setGhostLight(ghost, ghostState.on)
		rt.setAnchor("sa_ghost", {"intensity": (2.6 if ghostState.powered else 5.5) if ghostState.on else 0.0, "distance": 8 if ghostState.powered else 11})
		ghostPool.set_({"intensity": (0.12 if ghostState.powered else 0.22) if ghostState.on else 0.0})
	var ghostSet := func(on):
		ghostState.on = truthy(on)
		ghostObj.on = ghostState.on
		applyGhost.call()
	ghostObj["set_"] = ghostSet
	ghostObj["set"] = ghostSet
	O["ghost_light"] = ghostObj
	rt.onPower(gl.pos, func(on, _instant = false):
		ghostState.powered = on
		applyGhost.call())
	rt.onReset(func():
		ghostState.on = true
		ghostObj.on = true
		applyGhost.call())
	var I = g.get("interact")
	if I != null and I.has_method("register"):
		I.register({
			"id": "toy_ghost_light", "pos": [gl.pos[0], float(gl.pos[1]) + 0.4, gl.pos[2]], "radius": 1.4, "prompt": func() -> Dictionary: return {},
			"use": func() -> void:
				ghostSet.call(not ghostState.on)
				if g.get("audio") != null:
					g.audio.play("toy_ghost_light", {"pos": v3(ghostPos)}),
		})
		var tw = Layout.ANCHORS.toy_prize_wheel
		I.register({
			"id": "toy_prize_wheel", "pos": [tw.pos[0], float(tw.pos[1]) + 0.4, tw.pos[2]], "radius": 1.3, "prompt": func() -> Dictionary: return {},
			"use": func() -> void:
				var W = O.get("ee_prize_wheel")
				if W != null and float(W.spin.call({})) != 0.0 and g.get("audio") != null:
					g.audio.play("toy_wheel", {"pos": W.hub}),
		})

	# stage monitors (screen spawns): big walnut CRTs, screen centers exactly on ss_studio_a_w / ss_studio_a_e
	for e in [["ss_studio_a_w", "splay"], ["ss_studio_a_e", "swivel"]]:
		var id: String = e[0]
		var s = ss(id)
		var tv := placeFit(g, root, "bc_tv_19", {
			"opts": {"legs": e[1], "card": "station_id", "group": "scr_decor", "unique": id}, "scale": 1.8, "rotY": s.rotY, "area": AREA,
			"fit": func(gg): return DAU.ud(gg).screens[0].mesh, "target": s.pos, "floorY": 0.6 if id == "ss_studio_a_e" else 0.0,
			"screenGroup": "scr_decor", "screenId": id,
		})
		var scr = null
		if tv != null and not DAU.ud(tv).screens.is_empty():
			scr = DAU.ud(tv).screens[0].get("mesh")
		O[id] = {"group": tv, "screen": scr}

	# spooky telethon stage dressing: tombstones, jack-o'-lanterns, fog machine, cue cards, curtains, backdrop
	P.call(null, {"group": A.call("sa_tomb1"), "pos": [-2.35, 0.6, -29.45], "rotY": PI - 0.15})
	P.call(null, {"group": A.call("sa_tomb2"), "pos": [6.85, 0.6, -29.55], "rotY": PI + 0.2})
	for pk in [[-2.55, 0.6, -26.45, 0.26, 1], [-1.95, 0.6, -26.3, 0.18, 2], [7.35, 0.6, -29.2, 0.2, 3],
			[-6.2, 0, -25.6, 0.22, 4], [-5.7, 0, -25.4, 0.16, 5], [11.6, 0, -24.9, 0.2, 6]]:
		var r: float = pk[3]
		var sd: int = pk[4]
		P.call(null, {"group": A.call("sa_pumpkin_%d" % sd), "pos": [pk[0], pk[1], pk[2]], "rotY": PI + (sd % 3 - 1) * 0.35,
			"colliders": [{"min": [-r, 0, -r], "max": [r, r * 1.6, r]}]})
	P.call(null, {"group": A.call("sa_fog"), "pos": [1.05, 0.6, -26.45], "rotY": PI - 0.3})
	var cue1: Node3D = P.call(null, {"group": A.call("sa_cue1"), "pos": [2.2, 0.62, -26.35], "rotY": PI + 0.1, "colliders": false})
	if cue1 != null:
		cue1.rotation.x = -HP + 0.02
	var cue2: Node3D = P.call(null, {"group": A.call("sa_cue2"), "pos": [-4.1, 0.25, -27.4], "rotY": -0.6, "colliders": false})
	if cue2 != null:
		cue2.rotation_order = EULER_ORDER_YXZ
		cue2.rotation = Vector3(-0.28, -0.6, 0.05)
	# curtain legs + valance frame the stage; painted backdrop on the back wall above it
	P.call(null, {"group": A.call("sa_leg1"), "pos": [-2.25, 0.6, -29.62], "colliders": false})
	P.call(null, {"group": A.call("sa_leg2"), "pos": [10.25, 0.6, -29.62], "colliders": false})
	P.call(null, {"group": A.call("sa_valance"), "pos": [4, 6.45, -29.55], "colliders": false})
	P.call(null, {"group": A.call("sa_backdrop"), "pos": [4, 4.55, -29.8], "colliders": false})
	# cobwebs in the stage back corners (alpha cut-out): world coordinates
	var webs: Node3D = A.call("sa_webs")
	if webs != null:
		root.add_child(webs)

	# ---------------------------------------------------------------------------------------------- marquee arch
	var mq: Node3D = P.call("marquee_arch", {"pos": [4, 0, -24.95], "rotY": 0.0, "opts": {"width": 14.4}})
	var mqState := {"mode": null, "powered": false, "step": -1, "last": "__none"}
	var mqObj := {"group": mq, "parts": partsOf(mq), "mode": "off"}
	var mqMode := func() -> String: return str(mqState.mode) if mqState.mode != null else ("chase" if mqState.powered else "off")
	mqObj["setMode"] = func(m = null):
		mqState.mode = m
		mqState.step = -1
		mqObj.mode = mqMode.call()
	O["marquee_arch"] = mqObj
	if mq != null:
		DAU.ud(mq).noMerge = true
		marqueeChase(mq, 0.0, "off")
	rt.anchor("sa_marquee_w", {"pos": [-1.8, 3.9, -24.2], "color": Config.PAL.marqueeGold, "intensity": 0, "distance": 8})
	rt.anchor("sa_marquee_e", {"pos": [9.8, 3.9, -24.2], "color": Config.PAL.marqueeGold, "intensity": 0, "distance": 8})
	var mqPools := [rt.pool([-1.2, 0.02, -24.2], 2.4, Config.PAL.marqueeGold, 0), rt.pool([9.2, 0.02, -24.2], 2.4, Config.PAL.marqueeGold, 0)]
	rt.onPower([4, 1, -24.95], func(on, _instant = false):
		mqState.powered = on
		mqState.step = -1
		mqObj.mode = mqMode.call()
		rt.setAnchor("sa_marquee_w", {"intensity": 2.4 if on else 0.0})
		rt.setAnchor("sa_marquee_e", {"intensity": 2.4 if on else 0.0})
		for p in mqPools:
			p.set_({"intensity": 0.16 if on else 0.0}))
	rt.onTick(func(t, _dt, vis):
		if not vis or mq == null:
			return
		var mode: String = mqMode.call()
		var step := 0 if mode == "off" or mode == "on" else int(floor(t * 9.0))
		if step == mqState.step and mqState.last == mode:
			return
		mqState.step = step
		mqState.last = mode
		marqueeChase(mq, t, mode))

	# ---------------------------------------------------------------------------------------------- carousel + tote
	var toteA = Layout.ANCHORS.ee_tote_board
	var car: Node3D = P.call("pledge_carousel", {"pos": toteA.pos, "rotY": 0.26})
	O["pledge_carousel"] = {"group": car, "parts": partsOf(car)}
	var tote: Node3D = P.call("tote_board_tower", {"pos": toteA.pos, "rotY": 0.26, "opts": {"value": 12987}})
	var toteState := {"value": 12987, "glow": 0.3}
	var toteObj := {"group": tote, "parts": partsOf(tote), "goal": 13000, "value": 12987}
	toteObj["setValue"] = func(v):
		toteState.value = v
		toteObj.value = v
		setToteValue(tote, v)
	toteObj["setGlow"] = func(k):
		toteState.glow = k
		setToteGlow(tote, g, float(k))
	O["ee_tote_board"] = toteObj
	if tote != null:
		DAU.ud(tote).noMerge = true
		setToteGlow(tote, g, 1.0)
		setToteGlow(tote, g, 0.3)
	rt.anchor("sa_tote", {"pos": [toteA.pos[0], 2.6, toteA.pos[2]], "color": Config.PAL.gelAmber, "intensity": 1.4, "distance": 6})
	var totePool = rt.pool([toteA.pos[0], 0.02, toteA.pos[2]], 3.4, Config.PAL.gelAmber, 0.07)
	rt.onPower(toteA.pos, func(on, _instant = false):
		toteObj.setGlow.call(1.0 if on else 0.3)
		rt.setAnchor("sa_tote", {"intensity": 2.4 if on else 1.4})
		totePool.set_({"intensity": 0.13 if on else 0.07}))
	rt.onReset(func(): toteObj.setValue.call(12987))
	# ringing pledge phones (after power): one phone rings for ~1.6 s every ~2.6 s
	var ringer := {"i": -1, "t0": 0.0, "next": 1.5}
	rt.onTick(func(t, _dt, vis):
		if car == null:
			return
		if not truthy(rt.powered) or not vis:
			if ringer.i >= 0:
				ringPhone(car, ringer.i, 0.0, false)
				ringer.i = -1
			return
		if ringer.i < 0 and t > ringer.next:
			ringer.i = int(floor(randf() * 12.0))
			ringer.t0 = t
		if ringer.i >= 0:
			var k: float = t - ringer.t0
			var on: bool = k < 1.6 and fmod(k, 0.8) < 0.5
			ringPhone(car, ringer.i, t, on)
			if k > 1.6:
				ringPhone(car, ringer.i, t, false)
				ringer.i = -1
				ringer.next = t + 1.0 + randf() * 2.2)
	# pledge litter around the desk (world coordinates)
	var litter: Node3D = A.call("sa_litter")
	if litter != null:
		root.add_child(litter)

	# ---------------------------------------------------------------------------------------------- bleachers
	for bl in [[-2.5, 1], [10.5, 2]]:
		P.call("bleacher_block", {"pos": [bl[0], 0.012, -13.262], "opts": {"width": 8, "depth": 2.5, "seed": bl[1]}, "colliders": false})

	# ---------------------------------------------------------------------------------------------- applause sign
	var ap = Layout.ANCHORS.ee_applause_sign
	var applause: Node3D = P.call("bc_applause", {"pos": [ap.pos[0], float(ap.pos[1]) - 0.21, float(ap.pos[2]) - 0.16], "rotY": 0.0,
		"opts": {"lit": false, "chain": 2.7}, "colliders": false})
	var bulbsOn: Material = g.mats.glow("#FFC98A", 2.2)
	var apBulbOff: Array = []
	if applause != null:
		DAU.ud(applause).noMerge = true
		DAU.traverse(partsOf(applause).get("bulbs"), func(o):
			if o is GeometryInstance3D:
				apBulbOff.append([o, (o as GeometryInstance3D).material_override]))
	rt.anchor("sa_applause", {"pos": [ap.pos[0], ap.pos[1], float(ap.pos[2]) - 1.2], "color": "#FF5A3C", "intensity": 0, "distance": 7})
	var apObj := {"group": applause, "parts": partsOf(applause), "lit": false}
	apObj["setLit"] = func(on):
		apObj.lit = truthy(on)
		setLamp(applause, "on" if truthy(on) else "off")
		for e in apBulbOff:
			e[0].material_override = bulbsOn if truthy(on) else e[1]
		rt.setAnchor("sa_applause", {"intensity": 2.2 if truthy(on) else 0.0})
	O["ee_applause_sign"] = apObj
	rt.onReset(func(): apObj.setLit.call(false))

	# ---------------------------------------------------------------------------------------------- disco ball
	var disco: Node3D = P.call("disco_ball", {"pos": [4, GRID_Y - 1.39, -21], "colliders": false})
	var ball: Node3D = partsOf(disco).get("ball")
	O["disco_ball"] = {"group": disco, "parts": {"ball": ball}}
	# specks: a rotating floor disc + a sliding band on the walls (additive), after power (Blender: sa_specks_*)
	var specksFloor: Node3D = A.call("sa_specks_floor")
	var specksWall: Node3D = A.call("sa_specks_wall")
	var wallMat: DAMaterial = null
	if specksFloor != null:
		specksFloor.position = Vector3(4, 0.025, -21)
		specksFloor.visible = false
		dyn.add_child(specksFloor)
	if specksWall != null:
		specksWall.visible = false
		dyn.add_child(specksWall)
		var wm := getMat(specksWall)
		if wm is DAMaterial:
			wallMat = (wm as DAMaterial).clone()
			wallMat.mapWrap = "repeat"
			wallMat.map = wallMat.map
			(specksWall as MeshInstance3D).material_override = wallMat
	rt.onPower([4, 3, -21], func(on, _instant = false):
		if specksFloor != null:
			specksFloor.visible = on
		if specksWall != null:
			specksWall.visible = on)
	rt.onTick(func(_t, dt, vis):
		if not truthy(rt.powered) or not vis:
			return
		if ball != null:
			ball.rotation.y += dt * 0.7
		if specksFloor != null:
			specksFloor.rotation.y -= dt * 0.12
		if wallMat != null:
			var o := wallMat.mapOffset
			o.x = fmod(o.x + dt * 0.012, 1.0)
			wallMat.mapOffset = o)

	# ---------------------------------------------------------------------------------------------- lighting grid
	var lensGroup: Array = []          # the JS noMerge lens group: the lens parts of the lights (materials swap at power)
	var lights: Array = []
	# warm Fresnels over the stage front (pipe z -25.8), gel spots on the pipe z -23.4
	for x in [-2.0, 1.0, 7.0, 10.0]:
		var f: Node3D = P.call("bc_light_fresnel", {"pos": [x, 0, -25.8], "opts": {"gel": "tungsten", "tilt": 1.05, "lit": false}, "colliders": false})
		if f != null:
			f.position.y = GRID_Y - float(DAU.ud(f).hang.pipeY)
			lights.append(f)
	var gels := [["magenta", Config.PAL.gelMagenta, -0.6], ["amber", Config.PAL.gelAmber, 4.0], ["cyan", Config.PAL.gelCyan, 8.6]]
	var gelProps: Array = []
	for gl2 in gels:
		var f: Node3D = P.call("bc_light_fresnel", {"pos": [gl2[2], 0, -23.4], "opts": {"gel": gl2[0], "tilt": 0.9, "lit": false}, "colliders": false})
		if f != null:
			f.position.y = GRID_Y - float(DAU.ud(f).hang.pipeY)
			lights.append(f)
		gelProps.append(f)
	# extra hardware: battens, clamps with dangling safety loops
	for bt in [[4, -28.2, 6], [-2.5, -16.2, 4], [10.5, -16.2, 4]]:
		var b: Node3D = P.call("bc_grid_batten", {"pos": [bt[0], 0, bt[1]], "opts": {"len": bt[2]}, "colliders": false})
		if b != null:
			b.position.y = GRID_Y - float(DAU.ud(b).hang.pipeY)
	for cl in [[-5.2, -18.6], [1.7, -13.8], [13.2, -21], [-0.6, -28.2]]:
		var c: Node3D = P.call("bc_grid_clamp", {"pos": [cl[0], 0, cl[1]], "colliders": false})
		if c != null:
			c.position.y = GRID_Y - float(DAU.ud(c).hang.pipeY)
	for f in lights:
		var lens = partsOf(f).get("lens")
		if lens != null:
			lensGroup.append(lens)
	var lampOn: Material = null
	var lampOff: Material = null
	if not lights.is_empty():
		var lm = DAU.ud(lights[0]).get("lampMats")
		if lm is Dictionary:
			lampOn = udMat(g, lm.get("on"))
			lampOff = udMat(g, lm.get("off"))
	rt.onPower([4, 6, -24], func(on, _instant = false):
		for l in lensGroup:
			setMat(l, lampOn if on else lampOff))

	# gel beams (after power): additive cones from the gel Fresnels sweeping across the stage, with moving light pools
	var beamSrc: Node3D = A.call("sa_beam")
	var beams: Array = []
	for i in gels.size():
		var f: Node3D = gelProps[i]
		if f == null or beamSrc == null:
			continue
		var color = gels[i][1]
		var x: float = gels[i][2]
		var lens: Vector3 = f.global_transform * DAU.v3(DAU.ud(f).aim.pos)
		var m: MeshInstance3D = beamSrc.duplicate()
		m.material_override = beamMaterial(color, 0.22)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 16384.0            # frustumCulled = false
		m.position = lens
		m.visible = false
		dyn.add_child(m)
		var pool = rt.pool([x, 0.62, -27.5], 1.5, color, 0)
		beams.append({"m": m, "pool": pool, "lens": lens, "color": color, "ph": i * 2.1, "x": x})
	var aimBeam := func(b: Dictionary, t: float):
		var cx: float = 4.0 + 5.4 * sin(t * 0.33 + b.ph) + (b.x - 4.0) * 0.25
		var cz: float = -27.7 + 1.2 * sin(t * 0.21 + b.ph * 1.7)
		var tgt := Vector3(cx, 0.6, cz)
		var ln: float = (b.lens as Vector3).distance_to(tgt)
		var mm: MeshInstance3D = b.m
		mm.basis = Basis.looking_at(tgt - mm.position, Vector3.UP, true) * Basis.from_scale(Vector3(1, 1, ln))
		tgt.y = 0.62
		b.pool.set_({"pos": tgt})
	rt.onPower([4, 6, -23.4], func(on, _instant = false):
		for b in beams:
			b.m.visible = on
			b.pool.set_({"intensity": 0.28 if on else 0.0}))
	rt.onTick(func(t, _dt, vis):
		if truthy(rt.powered) and vis:
			for b in beams:
				aimBeam.call(b, t))
	for b in beams:
		aimBeam.call(b, 0.0)
	if beamSrc != null:
		beamSrc.free()
	# gel wash anchors (after power)
	rt.anchor("sa_gel_w", {"pos": [0.5, 3.2, -27.2], "color": Config.PAL.gelMagenta, "intensity": 0, "distance": 9})
	rt.anchor("sa_gel_e", {"pos": [8.5, 3.2, -27.2], "color": Config.PAL.gelCyan, "intensity": 0, "distance": 9})
	rt.onPower([4, 3, -27], func(on, _instant = false):
		rt.setAnchor("sa_gel_w", {"intensity": 2.6 if on else 0.0})
		rt.setAnchor("sa_gel_e", {"intensity": 2.6 if on else 0.0}))

	# hanging bats over the audience + the carousel (same mulberry(77) stream as the Blender build)
	var rb := Rng.mulberry32(77)
	for i in 14:
		var x: float = -5.0 + rb.call() * 18.0
		var z: float = -27.0 + rb.call() * 12.0
		var y: float = 4.6 + rb.call() * 1.2
		if Vector2(x - 4.0, z + 21.0).length() < 1.2:
			continue
		rb.call()             # s = 1.4 + rb() * 1.2 (baked into sa_bat_<i>)
		var ry: float = rb.call() * TAU
		var bat: Node3D = P.call(null, {"group": A.call("sa_bat_%d" % i), "pos": [x, y, z], "rotY": ry, "colliders": false})
		var rz: float = (rb.call() - 0.5) * 0.4
		if bat != null:
			bat.rotation.z = rz
	# hanging telethon banner ("operators are standing by") over the east aisle
	P.call(null, {"group": A.call("sa_banner_operators"), "pos": [9.9, 4.9, -18.6], "rotY": PI, "colliders": false})

	# ---------------------------------------------------------------------------------------------- walls
	var rect: Array = area.rect
	var W := {"w": float(rect[0]) + 0.155, "e": float(rect[2]) - 0.155, "n": float(rect[1]) + 0.155, "s": float(rect[3]) - 0.155}
	P.call(null, {"group": A.call("sa_banner_pledge"), "pos": [W.w + 0.03, 4.6, -21], "rotY": -HP, "colliders": false})
	P.call(null, {"group": A.call("sa_banner_thanks"), "pos": [-2.5, 4.35, W.s - 0.03], "rotY": PI, "colliders": false})
	P.call(null, {"group": A.call("sa_banner_goal"), "pos": [10.5, 4.45, W.s - 0.03], "rotY": PI, "colliders": false})
	P.call(null, {"group": A.call("sa_banner_studio"), "pos": [W.e - 0.03, 4.6, -25.2], "rotY": HP, "colliders": false})
	P.call(null, {"group": A.call("sa_banner_quiet"), "pos": [W.e - 0.03, 3.7, -23.1], "rotY": HP, "colliders": false})
	# posters at eye level (framed, lacquer frames)
	for pe in [["poster1", [W.w + 0.03, 1.55, -27.6], -HP], ["poster2", [W.e - 0.03, 1.6, -24.2], HP], ["poster3", [W.w + 0.03, 1.55, -15.2], -HP]]:
		P.call(null, {"group": A.call("sa_banner_" + pe[0]), "pos": pe[1], "rotY": pe[2], "colliders": false})

	# ---------------------------------------------------------------------------------------------- floor gear
	# feed camera (camera 1) + its stand monitor; a parked camera 2 aimed at the stage; boom mic; lights; cases
	feedCamera(g, rt, root, "feed_cam_studio_a", {"num": 1, "side": 1.1})
	standMonitor(g, rt, root, "mon_studio_a_stand")
	P.call("bc_pedestal_camera", {"pos": [11.2, 0, -23.2], "rotY": yawTo([11.2, 0, -23.2], [4, 0, -28.2]), "opts": {"num": 2, "tally": false}})
	P.call("bc_boom_mic", {"pos": [-4.45, 0, -25.95], "rotY": yawTo([-4.45, 0, -25.95], [-1.2, 0, -28.6]), "opts": {"reach": 2.6, "raise": 0.1, "micTilt": 0.35}})
	var tri: Node3D = P.call("bc_light_tripod", {"pos": [-3.85, 0, -29.3], "rotY": yawTo([-3.85, 0, -29.3], [1.5, 0, -27.8]),
		"opts": {"gel": "amber", "height": 1.7, "tilt": 0.12, "lit": false, "anchor": false}})
	var soft: Node3D = P.call("bc_light_softbox", {"pos": [13.9, 0, -24.6], "rotY": yawTo([13.9, 0, -24.6], [8, 0, -27.5]), "opts": {"lit": false, "height": 1.25}})
	var softLens = null
	for lg in [tri, soft]:
		var lens = partsOf(lg).get("lens")
		if lens != null:
			lensGroup.append(lens)
			softLens = lens
	var softOn: Material = null
	if soft != null and DAU.ud(soft).get("lampMats") is Dictionary:
		softOn = udMat(g, DAU.ud(soft).lampMats.get("on"))
	rt.onPower([13.9, 1, -24.6], func(on, _instant = false):
		if softLens != null:
			setMat(softLens, softOn if on else lampOff))
	var sandbag: Node3D = A.call("sa_sandbag")
	for lg in [tri, soft]:
		if lg == null:
			continue
		for dd in [[0.3, 0.2], [-0.25, -0.28]]:
			var sb: Node3D = sandbag.duplicate() if sandbag != null else null
			P.call(null, {"group": sb, "pos": [lg.position.x + dd[0], 0, lg.position.z + dd[1]], "rotY": dd[0] * 5.0, "colliders": false})
	if sandbag != null:
		sandbag.free()
	P.call("bc_flight_case_stack", {"pos": [-6.35, 0, -26.9], "rotY": HP + 0.08})
	P.call("bc_flight_case", {"pos": [-6.3, 0, -29.35], "rotY": HP - 0.2, "opts": {"size": "tall", "color": "#2E2934"}})
	P.call("bc_flight_case", {"pos": [-5.35, 0, -29.55], "rotY": 0.1, "opts": {"size": "md", "color": "#7A2A26"}})
	P.call("bc_clapperboard", {"pos": [-6.4, 1.56, -26.75], "rotY": -1.1, "colliders": false})
	P.call("yd_film_cans", {"pos": [-4.55, 0, -29.55], "rotY": 0.5, "opts": {"seed": 3}})
	P.call("bc_cable_coil", {"pos": [-4.4, 0, -28.1], "rotY": 2.1})
	P.call("bc_cable_coil", {"pos": [13.8, 0, -22.4], "rotY": -0.8, "opts": {"color": "wztvBlue"}})
	P.call("bc_cable_spaghetti", {"pos": [-3.9, 0, -16.6], "rotY": 0.35, "opts": {"w": 3.6, "d": 0.9, "count": 4, "seed": 3}})
	P.call("bc_cable_spaghetti", {"pos": [2.0, 0, -25.05], "rotY": 0.02, "opts": {"w": 6.2, "d": 0.55, "count": 5, "seed": 8}})
	P.call("bc_cable_spaghetti", {"pos": [12.0, 0, -21.9], "rotY": 1.2, "opts": {"w": 2.6, "d": 0.8, "count": 3, "seed": 5}})
	P.call("bc_headphones_hook", {"pos": [W.e, 1.2, -25.9], "rotY": HP, "colliders": false})

	# ---------------------------------------------------------------------------------------------- light pools
	rt.pool([4, 0.62, -28.0], 4.2, "#FF6FB0", 0)
	var stagePools := [rt.pool([1.5, 0.62, -27.8], 3.2, "#FF5FA2", 0), rt.pool([7.8, 0.62, -27.8], 3.0, "#5FE3FF", 0)]
	rt.pool([-5.3, 0.02, -28.3], 1.3, Config.PAL.crtCyan, 0.08)
	rt.pool([1.2, 0.02, -16.4], 1.1, Config.PAL.crtCyan, 0.06)
	rt.pool([-2.3, 0.62, -26.2], 0.9, "#FFB347", 0.12)
	rt.pool([-6.0, 0.02, -25.4], 0.9, "#FFB347", 0.1)
	rt.onPower([4, 1, -27], func(on, _instant = false):
		for p in stagePools:
			p.set_({"intensity": 0.13 if on else 0.0}))

	if asset != null:
		asset.free()
	shadowHygiene(root)

	# expose a tiny debug helper for the harness
	O["studio_a"] = {"rt": rt, "root": root, "dyn": dyn}
