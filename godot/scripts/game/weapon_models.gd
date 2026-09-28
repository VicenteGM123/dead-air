# Weapon models for the game (GDD §9.1 art rule, §9.5 Chromacast) — port of src/game/weaponModels.js (owned by the
# weapons engineer), plus the runtime helper animateWeapon of src/props/weapons.js.
# Thin wrapper over the prop library (the Blender-built chunky toys, game.props.build) in the HAND convention:
# grip (palm centre of the right hand) at the origin, barrel along -Z, top +Y, a child Node3D named 'muzzle'
# at the barrel tip, userData.leftHand [x,y,z] support-hand point, userData.parts {drum, pump, mag, cover, battery,
# reelL, reelR, needle, goo, filament, antenna...} animatable sub-groups, userData.butt [x,y,z] (rear-most point:
# the stock end that sits on the shoulder), userData.weapon { id, upgraded, signal } (userData = DAU.ud(node)).
#
#   buildModel(id, upgraded=false, signal=null, game=DAGame.inst) -> Node3D   (a fresh instance each call; the
#     prop library caches the prototype). Upgraded = Chromacast finish + medal, rabbit ears, tail fins, extra chrome
#     (biased to the signal colour when given: hot_mic|laugh_track|cold_open).
#   buildWeaponModel(id, upgraded, game)   alias kept from the stub (same result, no signal).
#   buildMeleeProp(heroId, game) -> Node3D | null     hero melee prop (walkie / LP / wrench; Duke chops bare-handed)
#   buildGrenadeModel(game) -> Node3D                 tube grenade (filament part flickers)
#   buildTeleModel(game) -> Node3D                    Tiny Tele for the left hand during the Q wind-up
#   modelInfo(group) -> { muzzle:Vector3, leftHand:Vector3, butt:Vector3, parts }  (local, unscaled)
#   chromacast(game, signal|colour) -> Material      a standalone Chromacast toon material (object-space gradient)
#     for anything that is not a prop weapon (Uplink copies, Telly previews...). Installed as game.mats.chromacast
#     (a Callable field: game.mats.chromacast.call(signal)) by weapons.gd when the engine lacks it.
#   animateWeapon(group, t, state)   (src/props/weapons.js) optional per-frame helper: spins reels, bobs the VU needle,
#     wobbles goo, flickers the filament. state: { firing, recording, charge (0..1), reloading } — t in seconds.
# If the prop library has no model (parallel development), a chunky primitive placeholder with the same convention
# is returned (Blender runtime assets: res://assets/runtime/weapons_fx/placeholder_<id>[_up].glb, fallback_grenade.glb,
# fallback_tele.glb, built by blender/runtime/weapons_fx.py) so the game keeps running.
#
# Port notes: the JS try/catch around buildWeapon becomes "props.build returned null"; node names cannot hold ':'
# in Godot, so the root is named weapon_<id>[_up] (JS 'weapon:<id>[:up]'). All functions are static.
extends RefCounted

const WD = preload("res://scripts/game/weapon_defs.gd")
const ASSET_DIR := "res://assets/runtime/weapons_fx/"

static func _game(game) -> Variant:
	return game if game != null else DAGame.inst

# Transform of `node` in the frame of its ancestor `root` (root's own transform excluded).
static func _relXform(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

static func annotate(g: Node3D, id, upgraded, sig_) -> Node3D:
	var u := DAU.ud(g)
	if DAU.byName(g, "muzzle") == null:
		var m := DAU.node3d("muzzle")
		m.position = DAU.v3(u.muzzle) if u.get("muzzle") != null else Vector3(0, 0.08, -0.3)
		g.add_child(m)
	if u.get("leftHand") == null:
		u.leftHand = [0, 0, -0.15]
	if u.get("butt") == null:
		var box := AABB()
		var any := false
		var stack: Array = [g]
		while stack.size():
			var o: Node = stack.pop_back()
			for c in o.get_children():
				stack.append(c)
			if o is MeshInstance3D and (o as MeshInstance3D).mesh != null and not DAU.ud(o.get_parent()).get("instanced", false):
				var b: AABB = _relXform(o, g) * (o as MeshInstance3D).mesh.get_aabb()
				box = b if not any else box.merge(b)
				any = true
		var mz: float = u.muzzle[1] if u.get("muzzle") != null else 0.08
		u.butt = [0, mz * 0.85, maxf(0.02, box.end.z if any else -INF)]
	if not (u.get("parts") is Dictionary):
		u.parts = {}
	var w: Dictionary = (u.weapon as Dictionary).duplicate() if u.get("weapon") is Dictionary else {}
	w.id = id
	w.upgraded = upgraded == true
	w["signal"] = sig_ if sig_ else null
	u.weapon = w
	g.name = "weapon_%s%s" % [id, "_up" if upgraded else ""]
	return g

# The prop library's cached weapon build (JS buildWeapon(id, opts, game) = buildProp(id, game, opts)).
static func _buildWeapon(id: String, opts: Dictionary, game) -> Node3D:
	var g = _game(game)
	if g == null or g.props == null or not g.props.has_method("build"):
		return null
	var n = g.props.build(id, opts)
	return n as Node3D

static func buildModel(id, upgraded := false, sig_ = null, game = null) -> Node3D:
	var gm = _game(game)
	var opts := {"upgraded": upgraded == true, "pose": "hand"}
	if upgraded and sig_:
		opts["signal"] = sig_
	var g := _buildWeapon(id, opts, gm)
	if g == null:
		push_warning("[weaponModels] prop '%s' failed, using a placeholder" % id)
		g = placeholder(id, upgraded, gm)
	return annotate(g, id, upgraded, sig_)

static func buildWeaponModel(id, upgraded := false, game = null) -> Node3D:
	return buildModel(id, upgraded, null, game)

static func buildMeleeProp(heroId, game = null) -> Variant:
	var id = {"skip": "melee_walkie", "roxy": "melee_lp", "penny": "melee_wrench"}.get(heroId)
	if id == null:
		return null
	return _buildWeapon(id, {"pose": "hand"}, _game(game))

static func buildGrenadeModel(game = null) -> Node3D:
	var g := _buildWeapon("tube_grenade", {"pose": "hand"}, _game(game))
	if g != null:
		return g
	g = _loadRuntime("fallback_grenade.glb", _game(game))
	DAU.ud(g).parts = {}
	return g

# Tiny Tele held in the left hand during the Q wind-up (antenna folded). Placeholder: an orange box TV.
static func buildTeleModel(game = null) -> Node3D:
	var g := _buildWeapon("tiny_tele", {"pose": "hand"}, _game(game))
	if g != null:
		return g
	g = _loadRuntime("fallback_tele.glb", _game(game))
	DAU.ud(g).parts = {}
	return g

static func modelInfo(group: Node3D) -> Dictionary:
	var u := DAU.ud(group)
	var m = DAU.byName(group, "muzzle")
	return {
		"muzzle": (m as Node3D).position if m is Node3D else Vector3(0, 0.08, -0.3),
		"leftHand": DAU.v3(u.leftHand) if u.get("leftHand") != null else Vector3(0, 0, -0.15),
		"butt": DAU.v3(u.butt) if u.get("butt") != null else Vector3(0, 0.08, 0.05),
		"parts": u.parts if u.get("parts") is Dictionary else {},
	}

# ------------------------------------------------------------------------------------------ placeholder model
# (geometry: blender/runtime/weapons_fx.py LOOKS, same numbers as the JS placeholder())
const LOOKS := {
	"revolver_38": {"len": 0.3, "h": 0.08},
	"pump_37": {"len": 0.78, "h": 0.07},
	"mp7": {"len": 0.42, "h": 0.09},
	"m16a1": {"len": 0.82, "h": 0.09},
	"m60": {"len": 1.0, "h": 0.12},
	"zapper": {"len": 0.4, "h": 0.06},
	"boom_mic": {"len": 1.1, "h": 0.05},
	"chroma_key": {"len": 0.55, "h": 0.14},
}

static func placeholder(id, upgraded, game) -> Node3D:
	var key: String = id if LOOKS.has(id) else "revolver_38"
	var look: Dictionary = LOOKS[key]
	var g := _loadRuntime("placeholder_%s.glb" % key, game)
	if upgraded:
		# the body box wears the Chromacast finish
		var body = DAU.byName(g, "body")
		if body is MeshInstance3D and game != null and game.mats != null:
			(body as MeshInstance3D).material_override = chromacast(game, null)
	var L: float = look.len
	var u := DAU.ud(g)
	u.muzzle = [0, 0.07, -L * 0.8]
	u.leftHand = [0, 0.03, -L * 0.45] if L > 0.5 else [-0.03, -0.02, 0]
	return g

# Instantiates a runtime GLB of this system (material specs converted through game.mats.fromSpec, node "da" extras
# parsed into userData). An empty Node3D when the asset has not been built yet.
static func _loadRuntime(file: String, game) -> Node3D:
	var path := ASSET_DIR + file
	if not ResourceLoader.exists(path):
		push_warning("[weaponModels] missing runtime asset %s (run blender/build_all.py --only runtime)" % path)
		return DAU.node3d("placeholder")
	var ps = load(path)
	if not (ps is PackedScene):
		return DAU.node3d("placeholder")
	var root: Node3D = ps.instantiate()
	var stack: Array = [root]
	while stack.size():
		var o: Node = stack.pop_back()
		for c in o.get_children():
			stack.append(c)
		if o.has_meta("extras"):
			var ex = o.get_meta("extras")
			if ex is Dictionary and ex.get("da") is String:
				var d = JSON.parse_string(ex.da)
				if d is Dictionary:
					DAU.ud(o).merge(d, true)
		if o is MeshInstance3D and game != null and game.mats != null and game.mats.has_method("fromSpec"):
			var mi := o as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var im: Material = mi.get_active_material(si)
				if im != null and im.has_meta("extras"):
					var mex = im.get_meta("extras")
					if mex is Dictionary and mex.get("da") is String:
						var spec = JSON.parse_string(mex.da)
						if spec is Dictionary:
							mi.set_surface_override_material(si, game.mats.fromSpec(spec, im))
	return root

# ------------------------------------------------------------------------------------------ chromacast material
static var _ccCache := {}

# THREE.Color.getHSL hue (computed on the linear working-space components, like three's default).
static func _hue(c: Color) -> float:
	var r := DAU.srgbToLinear(c.r)
	var g := DAU.srgbToLinear(c.g)
	var b := DAU.srgbToLinear(c.b)
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	if mn == mx:
		return 0.0
	var delta := mx - mn
	var hue := 0.0
	if mx == r:
		hue = (g - b) / delta + (6.0 if g < b else 0.0)
	elif mx == g:
		hue = (b - r) / delta + 2.0
	else:
		hue = (r - g) / delta + 4.0
	return hue / 6.0

static func chromacast(game, sig_ = null) -> Material:
	var col = (WD.SIGNAL_COLORS.get(sig_, sig_)) if sig_ else null
	var key: String = col if col else "rainbow"
	if _ccCache.has(key):
		return _ccCache[key]
	var m = game.mats.toon("#ffffff", {"rough": 0.26, "metal": 0.18, "rim": 0.32, "rimColor": "#FFFFFF", "keepColor": true, "name": "chromacast|%s" % key})
	var u := {"uCcHue": {"value": _hue(DAU.color(col)) if col else 0.0}, "uCcSpread": {"value": 0.1 if col else 1.0}}
	patchCC(game, m, u)
	# the player swaps held materials to their heroFade variant: pre-patch that cached instance too
	patchCC(game, game.mats.variant(m, {"heroFade": true}), u)
	_ccCache[key] = m
	return m

static func patchCC(game, m, u: Dictionary) -> void:
	if m == null:
		return
	var ud = m.get("userData")
	if ud is Dictionary and ud.has("chromacast"):
		return
	if game.mats.has_method("patchShader"):
		game.mats.patchShader(m, "cc", {"uCcHue": u.uCcHue.value, "uCcSpread": u.uCcSpread.value})

# ------------------------------------------------------------------------------------------ animateWeapon (props)
# Optional per-frame helper. state: { firing, recording, charge (0..1), reloading } — t in seconds.
static func animateWeapon(group: Node3D, t: float, state := {}) -> void:
	var p = DAU.ud(group).get("parts")
	if not (p is Dictionary):
		p = {}
	if p.get("reelL") is Node3D:
		var w := 9.0 if state.get("recording") else 1.2
		p.reelL.rotation.y = t * w
		p.reelR.rotation.y = t * w * 0.8
	if p.get("needle") is Node3D:
		var ch = state.get("charge")
		p.needle.rotation.x = 0.7 - (float(ch) if ch != null else (0.25 + 0.15 * sin(t * 7.0) * sin(t * 2.3))) * 1.4
	if p.get("goo") is Node3D:
		var s := 1.0 + sin(t * 6.0) * 0.03
		p.goo.scale = Vector3(s, 2.0 - s, s)
	if p.get("filament") is Node3D:
		p.filament.visible = sin(t * 37.0) > -0.95
