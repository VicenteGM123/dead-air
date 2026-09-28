# DEAD AIR — sponsor spots: the 5 sponsor sets and THE COMMERCIAL (port of src/game/sponsors.js; GDD §10.3, §11, §14,
# §15, §18.9/§18.10). Owned by the sponsors agent (with scripts/game/perks.gd and scripts/ui/commercial.gd).
# Constructed by machines.gd as game.sponsors; Game drives init/reset/update right after `machines`.
#
# SETS  sponsor_set_<perkId> prefabs (the Blender port of src/props/sponsors.js: riser, painted flat, neon sign,
#   turntable + giant product, softboxes, gaffer-tape X, speaker, brand dressing) at the set_* anchors (layout: mark X,
#   pedestal, camera), each with its own tally camera prop (pedestal camera; Replay-Ade: the ENG camera on a tripod) at
#   the anchor's camera spot, aimed at the X. A set that would poke through a wall, a platform or a door/window lane
#   slides toward its camera (and turns a little) until it fits: `sets[perkId].fit` reports the shift.
#   Before power a set is dark and its tally is off (Replay-Ade is lit from the start); the colour wave
#   (signon.waveReached) wakes it with a 3-flash flicker. After power the product plays its 1 s teaser (sound + a
#   hop and spin) when the player comes within 5 m, at most every 8 s. The camera head follows the player on the mark.
# INTERACTION  within T.perks.markRadius (1.0 m) of the X, no facing needed: [E] cost; unpowered [E] + plug
#   (Replay-Ade works unpowered); no prompt when owned, sold out, or at the perk limit — at the limit, stepping onto
#   the X makes the camera shake its head (pans left-right twice), blink its tally and "bzzt" (at most every 3 s).
# THE COMMERCIAL (4.2 s, real time; world frozen: time.scale 0, player invulnerable, no control). GDD §10.3 says 3.2 s;
#   player feedback: the logo card was gone before its product name could be read, so the card holds 1 s longer.
#   0.00  ka-ching + one-frame white flash, hard cut: render.setCameraOverride(sponsor camera, {aspect: 4/3}) +
#         render.post.crt, the wood-grain bezel (commercial.gd), zombies invisible (the sponsor camera renders layer
#         0 only), world audio ducked by audio.gd on machine:commercial_start, round music cut, sponsor jingle.
#   0.00–2.20  YOUR hero's pantomime of the perk with temporary gag props (animator.override): Replay-Ade drink ->
#         banana-peel back-flip -> freeze + VHS rewind -> lands, thumbs up; Wobble-Up spoonful -> boxing glove on an
#         accordion spring from frame left -> gelatin jiggle -> thumbs up; Jump Cut sip from a steaming pot -> three
#         tape-snip jump cuts (arms crossed / finger guns with a prop revolver that reloads itself / wink); Roller
#         Boogie blurs out frame left, skates back in from the right spinning with a sparkle trail, disco point;
#         Double Vision brushes, grins with a star glint "ting", splits into cyan + magenta duplicates striking poses.
#   2.20–3.80  logo card (cards sponsor_logo_<perkId>) slides in on its starburst: commercial_ding + announcer_wahwah;
#         it then holds (slow push-in + one sheen sweep, commercial.gd) while the jingle tails off, and at 3.20 the
#         product's own teaser motif plays once on the music bus as the ad's button-up sting.
#   3.80–4.20  STAR WIPE out of the product back to the gameplay camera; the costume pops onto its hero slot
#         (perks.attachCostume) with sparkles + costume_pop.
#   4.20  world resumes; zombies within 3 m shoved 2 m back by a flash of the studio lights; perk:gain; commercial_end.
#   The world-audio duck audio.gd starts on machine:commercial_start (3.2 s) is re-issued here for the full 4.2 s.
#   Replay-Ade: at most 3 purchases per game; after the 3rd commercial the ENG camera tips over with a thud and the
#   gaffer-tape X covers the bottle (sold out, no prompt ever again).
# API (game.sponsors)
#   inCommercial (bool) · sets { perkId -> set runtime } · replayBought (0..3)
#   buy(perkId) -> bool       spend T.perks[perkId] and play the commercial (false: owned / limit / sold out / broke)
#   playCommercial(perkId, { free = true }) -> bool   debug / scripted (no cost; still needs a free slot)
#   debugCommercial(perkId) (alias), debugSkip() (jumps a running commercial to its end), setPowered(perkId, on)
# EVENTS  machine:commercial_start {perkId}, machine:commercial_end {perkId}; perk:gain comes from perks.gd.
# SOUNDS  sponsor_teaser_<id>, sponsor_jingle_<id>, commercial_cut, commercial_ding, announcer_wahwah, star_wipe,
#   costume_pop, sponsor_denied, studio_flash, replay_rewind, jumpcut_snip, smile_ting, jelly_bwoing, skate_push, light_thunk.
# Also here (ported from src/props/sponsors.js, the runtime helpers this system uses): setSponsorSetPower(set, on),
#   setTally(obj, on), animateProduct(obj, t).
#
# PORT NOTES
#   * The gag props (banana peel, spoon + jelly, boxing glove on its scissor lattice, coffee pot, toothbrush, fallback
#     gun) are Blender assets: blender/runtime/sponsors.py -> res://assets/runtime/sponsors/gag_<name>.glb.
#   * warmup() (Game.precompile samples) and mergeByMaterial (draw-call merging) are engine plumbing: not ported.
#   * JS try/catch around the per-frame commercial update: GDScript cannot catch, so a commercial still running
#     AD + 1 s after its start is aborted (the explicit guard the catch stood for).
#   * innerWidth/innerHeight -> CommercialOverlay.innerSize() (the overlay's canvas-unit screen size).
#   * No renames were needed (§3.2).
extends RefCounted

const PerksLib = preload("res://scripts/game/perks.gd")
const Commercial = preload("res://scripts/ui/commercial.gd")

const RUNTIME_DIR := "res://assets/runtime/sponsors/"

# T.perks.adLength (config, 3.2 s) is the GDD length; the logo card holds CARD_HOLD longer so the product name reads
# (config is not the sponsors agent's file, so the extra second lives here).
const CARD_HOLD := 1.0
const T_CARD := 2.2
const T_CLEAN := 2.46
const T_SETTLE := T_CARD + 0.24      # the card has slid in; it holds from here to T_WIPE
const T_BUTTON := T_CARD + 1.0       # 3.2 s: the jingles end ~2.9-3.4 s -> the product's teaser motif buttons up the ad
const DUCK := {"db": -18, "lowpass": 800}   # same world-audio duck as audio.gd's machine:commercial_start hook
const FLICKER := [[0.0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]]
const TAU := PI * 2.0
# Disco point to the sky (right arm up and out), left hand on the hip.
const DISCO := {"shoulderR": [2.72, 0, 0.28], "elbowR": [0.12, 0, 0], "shoulderL": [-0.2, 0, -0.55], "elbowL": [1.75, 0, 0], "hips": [0, 0, 0.1], "spine": [0, 0, -0.08], "head": [0.25, 0, 0.12]}
# Commercial-shot cheats per set (see _makeCamera): orbit (rad) around the mark, max lens distance.
const SHOT := {"wobble_up": {"orbit": -0.42, "maxD": 2.8}}
const WAH := {"replay_ade": [1.1, 0.95, 1.05, 0.85], "wobble_up": [0.9, 1.05, 0.8], "jump_cut": [1.15, 1, 1.1, 0.9], "roller_boogie": [1, 1.2, 0.95, 1.1, 0.85], "double_vision": [1.05, 1.15, 0.9]}
const REST := {"shoulderL": [0.05, 0, 0.1], "shoulderR": [0.05, 0, -0.1], "elbowL": [0.25, 0, 0], "elbowR": [0.25, 0, 0], "spine": [0, 0, 0], "head": [0, 0, 0]}
var game
var inCommercial := false
var sets := {}
var replayBought := 0
var _ad = null
var _t := 0.0
var _gags = null
var _dups = null
var _dupHero = null
var _built := false
var _unsubPre = null
var debugHoldAt = null
var _matCache := {}

static func AD() -> float:
	return float(Config.T.perks.adLength) + CARD_HOLD   # 4.2 s

static func T_WIPE() -> float:
	return 2.8 + CARD_HOLD

static func _clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func _smooth(a: float, b: float, x: float) -> float:
	var t := _clamp01((x - a) / (b - a))
	return t * t * (3.0 - 2.0 * t)

static func _lerp(a: float, b: float, k: float) -> float:
	return a + (b - a) * k

static func _easeOut(x: float) -> float:
	return 1.0 - pow(1.0 - _clamp01(x), 3.0)

static func _easeIn(x: float) -> float:
	return pow(_clamp01(x), 3.0)

static func _easeOutBack(x: float, k: float = 1.8) -> float:
	x = _clamp01(x)
	return 1.0 + (k + 1.0) * pow(x - 1.0, 3.0) + k * pow(x - 1.0, 2.0)

static func _yawTo(fx: float, fz: float, tx: float, tz: float) -> float:
	return atan2(-(tx - fx), -(tz - fz))

# ------------------------------------------------------------------------------------------ cross-system glue
# Field of a Dictionary or Object (null / default when missing): the JS `a?.b`.
static func _f(o, k: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		return o.get(k, def)
	if o is Object:
		var v = o.get(k)
		return def if v == null else v
	return def

# Method call on an Object (or a Callable field of a Dictionary): the JS `a?.m?.(...)`.
static func _m(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Object:
		if o.has_method(m):
			return o.callv(m, args)
		var c = o.get(m)
		if c is Callable and c.is_valid():
			return c.callv(args)
		return null
	if o is Dictionary and o.get(m) is Callable:
		return o[m].callv(args)
	return null

func _play(id: String, opts: Dictionary = {}):
	return _m(game.audio, "play", [id, opts])

# rig.js POSES (scripts/core/rig.gd, Rig.POSES).
static func _POSES() -> Dictionary:
	return Rig.POSES

# The station layout tables (layout.js AREAS / PLATFORMS / DOORS / WINDOWS): data/layout.json written by the Blender
# world pipeline (the single source of truth, same shapes as the JS), else the world port's layout.gd.
static var _layoutCache = null
static func _layout() -> Dictionary:
	if _layoutCache != null:
		return _layoutCache
	var out := {"AREAS": [], "PLATFORMS": [], "DOORS": [], "WINDOWS": [], "WALL_T": 0.3}
	var json_path := "res://data/layout.json"
	var loaded := false
	if FileAccess.file_exists(json_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if data is Dictionary:
			for k in out.keys():
				if data.has(k):
					out[k] = data[k]
			loaded = true
	if not loaded and ResourceLoader.exists("res://scripts/world/layout.gd"):
		var L = load("res://scripts/world/layout.gd")
		if L != null:
			var cm: Dictionary = L.get_script_constant_map()
			for k in out.keys():
				if cm.has(k):
					out[k] = cm[k]
				else:
					var v = L.get(k)
					if v != null:
						out[k] = v
	_layoutCache = out
	return out

# World transform of a node, in or out of the tree (object.matrixWorld).
static func _gxf(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.global_transform
	var x := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

static func _wpos(n: Node3D) -> Vector3:
	return _gxf(n).origin

# three's Quaternion.setFromEuler(new Euler(x, y, z)) (order XYZ: this module's own Euler never changes order).
static func _qe(e) -> Quaternion:
	return Rig.quatXYZ(float(e[0]), float(e[1]), float(e[2]))

# ------------------------------------------------------------------------------------------ placement fitting
# Rotated rectangle (center c, half extents hx/hz along axes X/Z) vs axis-aligned rect: separating axis test.
static func obbHitsRect(cx: float, cz: float, X: Array, Z: Array, hx: float, hz0: float, hz1: float, r: Array) -> bool:
	var corners := []
	for lx in [-hx, hx]:
		for lz in [hz0, hz1]:
			corners.append([cx + X[0] * lx + Z[0] * lz, cz + X[1] * lx + Z[1] * lz])
	var axes := [[1.0, 0.0], [0.0, 1.0], X, Z]
	var rc := [[r[0], r[1]], [r[2], r[1]], [r[0], r[3]], [r[2], r[3]]]
	for ax in axes:
		var a0 := INF
		var a1 := -INF
		var b0 := INF
		var b1 := -INF
		for p in corners:
			var d: float = p[0] * ax[0] + p[1] * ax[1]
			a0 = minf(a0, d)
			a1 = maxf(a1, d)
		for p in rc:
			var d: float = float(p[0]) * ax[0] + float(p[1]) * ax[1]
			b0 = minf(b0, d)
			b1 = maxf(b1, d)
		if a1 <= b0 or b1 <= a0:
			return false
	return true

static func fitSet(anchor: Dictionary) -> Dictionary:
	var L := _layout()
	var mark: Vector3 = anchor.mark
	var cam: Vector3 = anchor.camera
	var area = null
	for a in L.AREAS:
		if a.id == anchor.area:
			area = a
			break
	var rect: Array = area.rect if area != null else [-1000.0, -1000.0, 1000.0, 1000.0]
	var x0 := float(rect[0])
	var z0 := float(rect[1])
	var x1 := float(rect[2])
	var z1 := float(rect[3])
	var inset := 0.14
	var hard := []                                     # stage / risers / bleachers
	var soft := []                                     # door and window lanes (kept clear when possible)
	for p in L.PLATFORMS:
		if p.get("area") == anchor.area:
			hard.append(p.rect)
	for d in L.DOORS:
		var das = d.get("areas")
		if das is Array and das.has(anchor.area):
			var r: Array = d.rect
			var alongX: bool = (float(r[2]) - float(r[0])) > (float(r[3]) - float(r[1]))
			soft.append([r[0] - 0.3, r[1] - 1.5, r[2] + 0.3, r[3] + 1.5] if alongX else [r[0] - 1.5, r[1] - 0.3, r[2] + 1.5, r[3] + 0.3])
	for w in L.WINDOWS:
		if w.get("area") == anchor.area and w.get("inside") and w.get("line"):
			var ww = w.get("width")
			var half: float = (float(ww) if ww else 1.6) / 2.0 + 0.2
			var ax: String = w.line[0]
			var c := float(w.line[1])
			var dIn := float(w.inside[2 if ax == "z" else 0])
			var lo := minf(c, dIn + signf(dIn - c) * 0.8)
			var hi := maxf(c, dIn + signf(dIn - c) * 0.8)
			soft.append([float(w.inside[0]) - half, lo, float(w.inside[0]) + half, hi] if ax == "z" else [lo, float(w.inside[2]) - half, hi, float(w.inside[2]) + half])
	var dx := cam.x - mark.x
	var dz := cam.z - mark.z
	var rot0 := atan2(-dx, -dz)
	# local footprint: riser 3x3 (+ bumper), backdrop to z 1.46
	var HX := 1.56
	var HZ0 := -1.56
	var HZ1 := 1.47
	var best = null
	for dr in [0.0, 0.07, -0.07, 0.14, -0.14, 0.22, -0.22, 0.32, -0.32, 0.45, -0.45]:
		var th: float = rot0 + dr
		var Z := [sin(th), cos(th)]
		var X := [cos(th), -sin(th)]
		var si := 0
		while si * 0.05 <= 2.0 + 1e-9:
			var s := si * 0.05
			si += 1
			for l in [0.0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45]:
				var cost: float = s + absf(l) * 1.4 + absf(dr) * 2.6
				if best != null and cost >= best.cost:
					continue
				var mx: float = mark.x - Z[0] * s + X[0] * l
				var mz: float = mark.z - Z[1] * s + X[1] * l
				var ox: float = mx + Z[0] * 0.75
				var oz: float = mz + Z[1] * 0.75
				var ok := true
				for lx in [-HX, HX]:
					for lz in [HZ0, HZ1]:
						var px: float = ox + X[0] * lx + Z[0] * lz
						var pz: float = oz + X[1] * lx + Z[1] * lz
						if px < x0 + inset or px > x1 - inset or pz < z0 + inset or pz > z1 - inset:
							ok = false
				if ok:
					for r in hard:
						if obbHitsRect(ox, oz, X, Z, HX, HZ0, HZ1, r):
							ok = false
							break
				if ok:
					for r in soft:
						if obbHitsRect(ox, oz, X, Z, HX, HZ0, HZ1, r):
							cost += 2.5
				if ok and (best == null or cost < best.cost):
					best = {"cost": cost, "rotY": th, "origin": [ox, oz], "mark": [mx, mz], "shift": s, "lateral": l, "turn": dr}
	if best == null:
		best = {"cost": 99, "rotY": rot0, "origin": [mark.x + sin(rot0) * 0.75, mark.z + cos(rot0) * 0.75], "mark": [mark.x, mark.z], "shift": 0, "lateral": 0, "turn": 0}
	# tally camera: the anchor spot (just clear of the riser), kept inside the room
	var cx := cam.x
	var cz := cam.z
	var ddx: float = cx - best.mark[0]
	var ddz: float = cz - best.mark[1]
	var Ld := Vector2(ddx, ddz).length()
	if Ld == 0.0:
		Ld = 1.0
	ddx /= Ld
	ddz /= Ld
	if Ld < 1.4:
		Ld = 1.4
	var px2: float = best.mark[0] + ddx * Ld
	var pz2: float = best.mark[1] + ddz * Ld
	px2 = clampf(px2, x0 + 0.55, x1 - 0.55)
	pz2 = clampf(pz2, z0 + 0.55, z1 - 0.55)
	best.camera = [px2, pz2]
	best.bounds = [x0, z0, x1, z1]
	return best

# ------------------------------------------------------------------------------------------ gag props
# The gag props are Blender assets (blender/runtime/sponsors.py). Loads one and converts its material specs.
func _loadRuntime(name: String) -> Node3D:
	var path := RUNTIME_DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("[sponsors] missing runtime asset " + path)
		return null
	var ps = load(path)
	if ps == null or not (ps is PackedScene):
		return null
	var root: Node3D = ps.instantiate()
	_convertRuntime(game, root)
	return root

# Node "da" extras -> userData, material "da" specs -> game.mats.fromSpec (what props.gd does for props).
static func _convertRuntime(g, root: Node) -> void:
	var fix := func(n: Node) -> void:
		if n is Node3D:
			(n as Node3D).rotation_order = EULER_ORDER_XYZ
			if n.has_meta("extras"):
				var ex = n.get_meta("extras")
				if ex is Dictionary and ex.has("da"):
					var d = JSON.parse_string(str(ex.da)) if ex.da is String else ex.da
					if d is Dictionary:
						var u := DAU.ud(n)
						u.merge(d, true)
						if d.get("visible") == false:
							(n as Node3D).visible = false
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				return
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if m == null or not m.has_meta("extras"):
					continue
				var ex = m.get_meta("extras")
				if not (ex is Dictionary and ex.has("da")):
					continue
				var spec = JSON.parse_string(str(ex.da)) if ex.da is String else ex.da
				if spec is Dictionary and g != null and g.mats != null and g.mats.has_method("fromSpec"):
					var nm = g.mats.fromSpec(spec, m)
					if nm is Material:
						mi.set_surface_override_material(i, nm)
	DAU.traverse(root, fix)

func buildPeel() -> Node3D:
	return _loadRuntime("gag_peel")

func buildSpoon():
	var grp := _loadRuntime("gag_spoon")
	if grp == null:
		return null
	var jelly := DAU.byName(grp, "jelly")
	return {"grp": grp, "jelly": jelly}

func buildGlove():
	var grp := _loadRuntime("gag_glove")
	if grp == null:
		return null
	var slats := []
	for i in 14:
		var s := DAU.byName(grp, "slat_%d" % i)
		if s != null:
			slats.append(s)
	return {"grp": grp, "glove": DAU.byName(grp, "glove"), "slats": slats, "box": DAU.byName(grp, "box")}

# Lays the accordion out along +x from the box (x = 0) to the glove at `len` metres.
static func setExtend(G: Dictionary, len: float) -> void:
	var n := int(G.slats.size() / 2)
	if n <= 0:
		return
	var cell := maxf(0.03, (len - 0.2) / n)
	var rod := 0.36
	var dy := sqrt(maxf(0.0004, rod * rod - cell * cell)) * 0.5
	var ang := atan2(dy * 2.0, cell)
	for i in n:
		var x := 0.11 + cell * (i + 0.5)
		var a: Node3D = G.slats[i * 2]
		var b: Node3D = G.slats[i * 2 + 1]
		a.position = Vector3(x, 0, 0.012)
		b.position = Vector3(x, 0, -0.012)
		a.rotation = Vector3(0, 0, ang)
		b.rotation = Vector3(0, 0, -ang)
		var L := Vector2(cell, dy * 2.0).length() + 0.01
		a.scale.x = L
		b.scale.x = L
	if G.glove:
		G.glove.position = Vector3(0.11 + cell * n + 0.2, 0, 0)
	if G.box:
		G.box.position = Vector3.ZERO

func buildPot() -> Node3D:
	return _loadRuntime("gag_pot")

func buildBrush() -> Node3D:
	return _loadRuntime("gag_brush")

func fallbackGun() -> Node3D:
	return _loadRuntime("gag_gun")

# ------------------------------------------------------------------------------------------ keyframes
# k(t, keys) with keys = [[t0, v0], [t1, v1], ...] (numbers or arrays): smoothstep between neighbours.
static func key(t: float, keys: Array):
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		var v1 = keys[i][1]
		if t <= t1:
			var t0: float = keys[i - 1][0]
			var v0 = keys[i - 1][1]
			var s := _smooth(t0, t1, t)
			if v0 is Array:
				var out := []
				for j in v0.size():
					out.append(v0[j] + (v1[j] - v0[j]) * s)
				return out
			return float(v0) + (float(v1) - float(v0)) * s
	return keys[keys.size() - 1][1]

# ============================================================================================ Sponsors
func _init(g) -> void:
	game = g

func init() -> void:
	var g = game
	_buildSets()
	g.events.on("power:on", func(_p = null):
		for S in sets.values():
			if not S.powered and S.waveT < 0:
				S.pendingPower = true)
	# leaving play mid-commercial (quit to the title, game over, victory): restore the camera and drop the overlay
	g.events.on("state", func(e = null):
		if e and (e.to == "menu" or e.to == "gameover" or e.to == "victory"):
			_abortCommercial())
	# During a commercial nothing may dither the hero (the main camera still runs behind the scenes).
	if g.render and g.render.has_method("addPrePass"):
		_unsubPre = g.render.addPrePass(func(_r = null):
			if _ad == null or not _f(game.render, "cameraOverride"):
				return
			var U = _f(game.mats, "uniforms")
			if U is Dictionary and U.has("uHeroFade"):
				var h = U.uHeroFade
				if h is Dictionary:
					h.value = 1.0
			# (the JS uniform object is read at draw time; the Godot global is uploaded by materials.gd before this
			# pre-pass, so it is written here too for this frame's draw)
			if RenderingServer.global_shader_parameter_get_list().has(&"uHeroFade"):
				RenderingServer.global_shader_parameter_set(&"uHeroFade", 1.0)
			var pl = game.player
			var m = _f(pl, "model")
			if m and _f(pl, "_hidden"):
				DAU.traverse(m, func(o):
					if DAU.ud(o).get("daHideOnFade") and o is Node3D:
						o.visible = true))

func reset() -> void:
	_abortCommercial()
	replayBought = 0
	for S in sets.values():
		S.soldOut = false
		var parts = DAU.ud(S.root).get("parts", {})
		if parts is Dictionary and parts.get("soldOut"):
			parts.soldOut.visible = false
		S.tip = null
		S.camProp.rotation = Vector3(0, S.camYaw, 0)
		S.camProp.position = S.camPos
		S.shakeT = -1.0
		S.teaseT = -1.0
		S.limitT = 0.0
		S.teaserCd = 0.0
		S.near = false
		S.onMark = false
		_power(S, S.id == "replay_ade", true)

# ------------------------------------------------------------------------------------------ building
func _buildSets() -> void:
	var g = game
	var lv = g.level
	var anchors = _f(lv, "anchors")
	if not (anchors is Dictionary) or g.props == null:
		return
	for perkId in PerksLib.PERK_IDS:
		var a = anchors.get("set_" + perkId)
		if a == null:
			continue
		var apos: Vector3 = DAU.v3(a.pos)
		var src := {"mark": DAU.v3(a.mark) if a.get("mark") != null else Vector3(apos.x, 0, apos.z), "camera": DAU.v3(a.camera), "area": a.area}
		var fit := fitSet(src)
		var areaRoots = _f(lv, "areaRoots", {})
		var parent = areaRoots.get(a.area) if areaRoots is Dictionary and areaRoots.get(a.area) else g.scene
		var root: Node3D = g.props.place(parent, "sponsor_set_" + perkId, {
			"pos": [fit.origin[0], 0, fit.origin[1]], "rotY": fit.rotY, "area": a.area, "opts": {"camera": false}, "tag": "sponsor_set"})
		if root == null:
			continue
		root.name = "set_" + perkId
		var camId := "sponsor_camera_eng" if perkId == "replay_ade" else "sponsor_camera_pedestal"
		var camYaw := _yawTo(fit.camera[0], fit.camera[1], fit.mark[0], fit.mark[1])
		var camProp: Node3D = g.props.place(parent, camId, {"pos": [fit.camera[0], 0, fit.camera[1]], "rotY": camYaw, "area": a.area, "tag": "sponsor_cam", "colliders": false})
		camProp.rotation_order = EULER_ORDER_XYZ
		# slim collider (the tripod / pedestal core, not its whole footprint: the lobby and green-room lanes stay open)
		var cr := 0.28 if perkId == "replay_ade" else 0.34
		_m(_f(lv, "col"), "addBox", [[fit.camera[0] - cr, 0, fit.camera[1] - cr], [fit.camera[0] + cr, 1.8, fit.camera[1] + cr], {"tag": "sponsor_cam"}])
		camProp.name = "set_%s_camera" % perkId
		var u := DAU.ud(root)
		var anc = u.get("anchors", {})
		var markLocal = anc.get("mark") if anc is Dictionary and anc.get("mark") != null else [0, 0.2, -0.75]
		var mark: Vector3 = _gxf(root) * DAU.v3(markLocal)
		var fy = _m(_f(lv, "col"), "floorAt", [mark.x, mark.z, 3.0])
		mark.y = float(fy) if fy != null else INF
		if not is_finite(mark.y):
			mark.y = 0.2
		var fwd := Vector3(fit.camera[0] - mark.x, 0, fit.camera[1] - mark.z).normalized()   # mark -> camera
		var right := Vector3(fwd.z, 0, -fwd.x)                                                 # the viewer's right
		var parts = u.get("parts", {})
		var turntable = parts.get("turntable") if parts is Dictionary else null
		var product := Vector3.ZERO
		if turntable is Node3D:
			product = _wpos(turntable)
			product.y += 0.75
		else:
			product = mark + fwd * -1.2
			product.y = 1.2
		var lights := []
		for l in u.get("lightAnchors", []):
			lights.append({"id": l.get("id"), "intensity": l.get("intensity", 0.0)})
		var cparts = DAU.ud(camProp).get("parts", {})
		var S := {
			"id": perkId, "area": a.area, "root": root, "camProp": camProp, "camHead": cparts.get("head") if cparts is Dictionary else null, "camYaw": camYaw,
			"camPos": camProp.position, "fit": fit, "mark": mark, "fwd": fwd, "right": right, "product": product,
			"powered": false, "waveT": -1.0, "pendingPower": false, "teaseT": -1.0, "teaserCd": 0.0, "near": false, "onMark": false,
			"limitT": 0.0, "shakeT": -1.0, "soldOut": false, "tip": null, "lights": lights,
			"headYaw": 0.0, "_fi": -1,
		}
		S.cam = _makeCamera(S)
		S.item = _m(g.interact, "register", [{
			"id": "set_" + perkId, "pos": mark, "radius": Config.T.perks.markRadius, "height": 1.6,
			"enabled": func(): return _ad == null and not _f(game.perks, "replayActive", false) and game.state == "playing",
			"prompt": func(): return _prompt(S),
			"use": func(): _use(S),
		}])
		if S.item == null:
			S.item = {"pos": mark}
		var objs = _f(lv, "objects")
		if objs is Dictionary:
			objs["set_" + perkId] = {"group": root, "parts": parts, "camera": camProp, "set": S}
		_optimize(S)
		sets[perkId] = S
		_power(S, perkId == "replay_ade", true)
	if g.nav and _f(g.nav, "built"):
		g.nav.build()
	_built = true

# Shadow diet: only the product (on the turntable) and the camera body cast into the key shadow map; the AO bake
# grounds the rest. (The JS draw-call merge, mergeByMaterial, is engine plumbing: not ported.)
func _optimize(S: Dictionary) -> void:
	var u := DAU.ud(S.root)
	var parts = u.get("parts", {})
	var keep := {}
	if parts is Dictionary and parts.get("turntable") is Node:
		DAU.traverse(parts.turntable, func(o): keep[o] = true)
	DAU.traverse(S.root, func(o):
		if o is GeometryInstance3D and not keep.has(o):
			(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	DAU.traverse(S.camProp, func(o):
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null:
			return
		var r: float = (o as MeshInstance3D).mesh.get_aabb().size.length() * 0.5
		(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if r > 0.3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

# Points a camera from `pos` at `target` (camera.position.copy + lookAt), in or out of the tree.
static func _camLook(cam: Camera3D, pos: Vector3, target: Vector3) -> void:
	var xf := Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)
	if cam.is_inside_tree():
		cam.global_transform = xf
	else:
		cam.transform = xf

# The commercial camera: along the tally camera's axis, pulled back to frame the whole pantomime (the prop hides
# during the shot), a little to the viewer's right so the product shows beside the hero.
func _makeCamera(S: Dictionary) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "sponsor_cam_" + S.id
	cam.fov = 44
	cam.near = 0.05
	cam.far = 90
	cam.cull_mask = 1 << Config.LAYERS.WORLD      # layer 0 only: the zombies vanish from the ad
	var b: Array = S.fit.bounds
	var x0 := float(b[0])
	var z0 := float(b[1])
	var x1 := float(b[2])
	var z1 := float(b[3])
	var col = _f(game.level, "col")
	S.spot = S.mark + S.right * 0.32                                                  # the hero performs right of the X
	var look: Vector3 = S.mark + S.right * -0.1 + S.fwd * -0.35
	look.y = S.mark.y + 1.12
	# per-set cheat (a big prop with no collider right beside a lens): orbit the shot around the mark / cap its distance
	var cheat: Dictionary = SHOT.get(S.id, {})
	var ca := cos(float(cheat.get("orbit", 0.0)))
	var sa := sin(float(cheat.get("orbit", 0.0)))
	var dir := Vector3(S.fwd.x * ca + S.fwd.z * sa, 0, -S.fwd.x * sa + S.fwd.z * ca)
	var side := Vector3(dir.z, 0, -dir.x)
	var at := func(d: float) -> Vector3:
		var bb: Vector3 = S.mark + dir * d + side * -0.28
		bb.y = S.mark.y + 1.3
		return bb
	var within := func(p: Vector3) -> bool:
		return p.x > x0 + 0.25 and p.x < x1 - 0.25 and p.z > z0 + 0.25 and p.z < z1 - 0.25
	# occlusion: rays from the lens to the subject (feet, belly, head, both frame sides, the product)
	var targets := [[0, 0.35, 0], [0, 1.2, 0], [0, 2.05, 0], [1.25, 1.2, 0], [-1.35, 1.2, 0], [-0.3, 1.7, -1.2],
		[1.8, 0.5, 0], [1.8, 1.9, 0], [-1.9, 0.5, 0], [-1.9, 1.9, 0], [1.5, 1.2, 0.8], [-1.6, 1.2, 0.8]]
	var blocked := func(bp: Vector3) -> int:
		if col == null or not col.has_method("raycast"):
			return 0
		var n := 0
		for tr in targets:
			var u: Vector3 = S.spot + S.right * float(tr[0]) + S.fwd * float(tr[2])
			u.y = S.mark.y + float(tr[1])
			var w := bp - u                      # subject -> lens (a lens inside a prop box is caught too)
			var L := w.length()
			w /= L
			var hit = col.raycast(u, w, maxf(0.1, L - 0.25), {"ignoreTags": ["sponsor_set", "sponsor_cam"]})
			if hit:
				n += 1
		return n
	var D := 3.0
	var bestN := INF
	var d := minf(3.1, float(cheat.get("maxD", 3.1)))
	while d >= 1.85:
		var bp: Vector3 = at.call(d)
		if within.call(bp):
			var n: int = blocked.call(bp)
			if n < bestN:
				bestN = n
				D = d
			if n == 0:
				break
		d -= 0.1
	var base: Vector3 = at.call(D)
	S.occluded = bestN
	S.camBase = base
	S.camLook = look
	S.camD = D
	cam.fov = rad_to_deg(2.0 * atan(1.36 / D))
	if game.scene:
		game.scene.add_child(cam)
		cam.current = false
	_camLook(cam, base, look)
	return cam

# ------------------------------------------------------------------------------------------ power & tally
func _power(S: Dictionary, on: bool, instant: bool = false) -> void:
	setSponsorSetPower(S.root, on)
	setTally(S.camProp, on and not S.soldOut)
	for l in S.lights:
		_m(game.lights, "setAnchor", [l.id, {"intensity": l.intensity if on else 0.0}])
	if instant:
		S.powered = on
		S.waveT = -1.0
		S.pendingPower = false

func _updatePower(S: Dictionary, rdt: float) -> void:
	var g = game
	if S.pendingPower and not S.powered and S.waveT < 0:
		var reached = g.signon.waveReached(S.mark) if g.signon and g.signon.has_method("waveReached") else true
		if reached or not _f(g.machines, "powerOn", false):
			S.waveT = 0.0
			S.pendingPower = false
			S._fi = -1
			_play("light_thunk", {"pos": S.product})
	if S.waveT < 0:
		return
	S.waveT += rdt
	var idx := -1
	for i in FLICKER.size():
		if S.waveT >= FLICKER[i][0]:
			idx = i
	if idx != S._fi:
		S._fi = idx
		_power(S, FLICKER[idx][1])
	if S.waveT > 0.35:
		S.waveT = -1.0
		S.powered = true
		_power(S, true, true)

func setPowered(perkId: String, on) -> void:
	var S = sets.get(perkId)
	if S:
		_power(S, bool(on), true)

func _live(S: Dictionary) -> bool:
	return S.powered or S.id == "replay_ade"

# ------------------------------------------------------------------------------------------ interaction
func _prompt(S: Dictionary):
	var P = game.perks
	if P == null or S.soldOut or P.has(S.id) or _ad != null:
		return null
	if P.list.size() >= P.max:
		return null
	if not _live(S):
		return {"plug": true}
	return {"cost": Config.T.perks[S.id]}

func _use(S: Dictionary) -> void:
	if not _live(S):
		_play("ui_denied")
		return
	buy(S.id)

func buy(perkId: String) -> bool:
	var g = game
	var P = g.perks
	var S = sets.get(perkId)
	if P == null or _ad != null or P.has(perkId) or P.list.size() >= P.max:
		return false
	if S != null and (S.soldOut or not _live(S)):
		return false
	if perkId == "replay_ade" and replayBought >= int(Config.T.perks.replayMax):
		return false
	var cost = Config.T.perks.get(perkId)
	if not (cost is int or cost is float) or g.economy == null or not g.economy.has_method("spend") or not g.economy.spend(cost, "perk"):
		return false
	if perkId == "replay_ade":
		replayBought += 1
	if S == null:
		return P.give(perkId)
	_startCommercial(S)
	return true

func playCommercial(perkId: String, opts: Dictionary = {}) -> bool:
	var free: bool = opts.get("free", true)
	if not free:
		return buy(perkId)
	var P = game.perks
	var S = sets.get(perkId)
	if S == null or P == null or _ad != null or P.has(perkId) or P.list.size() >= P.max:
		return false
	_startCommercial(S)
	return true

func debugCommercial(perkId: String) -> bool:
	return playCommercial(perkId, {"free": true})

func debugSkip() -> void:
	debugHoldAt = null
	if _ad != null:
		_ad.t = maxf(_ad.t, AD() - 0.01)

# Tests: the running (or next) commercial will not advance past t seconds (null releases it).
func debugHold(t):
	debugHoldAt = t
	return _ad.t if _ad != null else null

# ------------------------------------------------------------------------------------------ the commercial
func _startCommercial(S: Dictionary) -> void:
	var g = game
	var p = g.player
	var r = g.render
	_ensureGags()
	var post = _f(r, "post", {})
	var ad := {
		"S": S, "id": S.id, "t": 0.0, "fired": {}, "cleaned": false, "wiped": false,
		"scale": g.time.scale, "invul": p.invulnerable, "music": _f(g.audio, "_musicState"),
		# chroma restores to 0, never a snapshot: at purchase time it usually holds the HUD's hurt pulse, and writing
		# that back makes the HUD's knob mixer keep it forever (a permanent colour fringe after the commercial).
		"post": {"crt": post.get("crt", 0.0), "saturation": post.get("saturation", 1.0), "vignette": post.get("vignette", 0.0), "grain": post.get("grain", 0.0), "chroma": 0.0},
		"faceYaw": _yawTo(S.spot.x, S.spot.z, S.camBase.x, S.camBase.z),
		"starAt": null, "props": [], "lastCut": -1,
	}
	_ad = ad
	inCommercial = true
	g.time.scale = 0.0
	p.invulnerable = true
	p.controlLocked = true
	p.vel = Vector3.ZERO
	p.sprinting = false
	p.ads = false
	p.teleport(S.spot.x, S.spot.z)
	if _f(p, "weaponModel"):
		ad.weaponVis = p.weaponModel.visible
		p.weaponModel.visible = false
	S.camProp.visible = false
	_camLook(S.cam, S.camBase, S.camLook)
	S.cam.fov = rad_to_deg(2.0 * atan(1.36 / S.camD))
	_m(r, "setCameraOverride", [S.cam, {"aspect": 4.0 / 3.0}])
	if post is Dictionary:
		post.crt = 1.0
		post.saturation = maxf(float(post.get("saturation", 1.0)), 1.12)
		post.grain = 0.06
	# key light up for the shoot
	for l in S.lights:
		_m(g.lights, "setAnchor", [l.id, {"intensity": l.intensity * 2.2, "enabled": true}])
	_setupPantomime(ad)
	var an = _f(p, "animator")
	if an:
		an.set("override", _pose)
	_m(g.audio, "music", ["silence"])
	_play("commercial_cut")
	_play("sponsor_jingle_" + S.id, {"delay": 0.05})
	g.events.emit("machine:commercial_start", {"perkId": S.id})
	# audio.gd ducks the world for 3.2 s on that event; keep it ducked for the whole (longer) commercial
	_m(g.audio, "duck", [DUCK.db, DUCK.lowpass, AD()])

func _abortCommercial() -> void:
	var ad = _ad
	if ad == null:
		return
	_cleanupPantomime(ad)
	_finishRender(ad)
	_ad = null
	inCommercial = false
	Commercial.getOverlay().clear()

func _finishRender(ad: Dictionary) -> void:
	var r = game.render
	if _f(r, "cameraOverride"):
		_m(r, "setCameraOverride", [null])
	var post = _f(r, "post")
	if post is Dictionary:
		post.crt = ad.post.crt
		post.saturation = ad.post.saturation
		post.grain = ad.post.grain
		post.chroma = ad.post.chroma

func _once(ad: Dictionary, t: float, k: String, at: float, fn: Callable) -> void:
	if t >= at and not ad.fired.has(k):
		ad.fired[k] = true
		fn.call()

func _updateCommercial(rdt: float) -> void:
	var g = game
	var ad: Dictionary = _ad
	var S: Dictionary = ad.S
	ad.t += rdt
	if debugHoldAt != null and ad.t > debugHoldAt:
		ad.t = float(debugHoldAt)
	var t: float = ad.t
	# (the JS try/catch around this update: a commercial stuck past its end is aborted)
	if t > AD() + 1.0:
		push_error("[sponsors] commercial stuck at %.2f s: aborted" % t)
		_abortCommercial()
		return
	var ov = Commercial.getOverlay()
	var st := {"mode": "commercial", "t": t, "perkId": S.id, "flash": 0.0, "cut": _clamp01(t / 0.3), "osd": null, "tracking": 0.0, "splice": 0.0, "card": -1.0, "star": null}
	if t < 0.07:
		st.flash = 1.0 - t / 0.07
	if not ad.cleaned:
		_beats(ad, t, st)
	# logo card
	if t >= T_CARD:
		st.card = _clamp01((t - T_CARD) / (T_SETTLE - T_CARD))
		st.cardHold = _clamp01((t - T_SETTLE) / (T_WIPE() - T_SETTLE))   # 0..1 across the held card (commercial.gd)
		_once(ad, t, "ding", T_CARD, func(): _play("commercial_ding"))
		_once(ad, t, "wah", T_CARD + 0.14, func(): _play("announcer_wahwah", {"rhythm": WAH.get(S.id)}))
		_once(ad, t, "starAt", T_CARD, func(): ad.starAt = _project(S.product, S.cam))
		# button-up sting: the product's 1 s teaser motif (same key as its jingle), unducked on the music bus
		_once(ad, t, "button", T_BUTTON, func(): _play("sponsor_teaser_" + S.id, {"bus": "music", "vol": 0.85}))
	if t >= T_CLEAN and not ad.cleaned:
		ad.cleaned = true
		_cleanupPantomime(ad)
	# star wipe back to the game + costume pop
	if t >= T_WIPE():
		if not ad.wiped:
			ad.wiped = true
			_finishRender(ad)
			S.camProp.visible = true
			_play("star_wipe")
			_m(g.perks, "attachCostume", [S.id, {"pop": true}])
			_play("costume_pop", {"delay": 0.06})
			for l in S.lights:
				_m(g.lights, "setAnchor", [l.id, {"intensity": l.intensity}])
		var k := _clamp01((t - T_WIPE()) / (AD() - T_WIPE()))
		var scr: Vector2 = ov.innerSize()
		var at = ad.starAt if ad.starAt != null else {"x": scr.x / 2.0, "y": scr.y / 2.0}
		var ax: float = at.x
		var ay: float = at.y
		var far := maxf(maxf(Vector2(ax, ay).length(), Vector2(scr.x - ax, ay).length()), maxf(Vector2(ax, scr.y - ay).length(), Vector2(scr.x - ax, scr.y - ay).length()))
		st.star = {"x": ax, "y": ay, "r": (far / 0.4 + 60.0) * (0.03 + 0.97 * pow(k, 2.1)), "rot": k * 0.9}
	if t >= AD():
		_endCommercial()
		return
	ov.draw(st)

func _endCommercial() -> void:
	var g = game
	var ad: Dictionary = _ad
	var S: Dictionary = ad.S
	var p = g.player
	if not ad.cleaned:
		_cleanupPantomime(ad)
	if not ad.wiped:
		_finishRender(ad)
		S.camProp.visible = true
		_m(g.perks, "attachCostume", [S.id, {"pop": false}])
	Commercial.getOverlay().clear()
	_ad = null
	inCommercial = false
	g.time.scale = ad.scale if ad.scale > 0 else 1.0
	p.controlLocked = false
	p.invulnerable = bool(_f(g.perks, "replayActive", false)) or float(_f(g.perks, "_invulnT", 0.0)) > 0.0
	if ad.music:
		_m(g.audio, "music", [ad.music])
	# the studio lights flash and shove the zombies within 3 m back 2 m
	var zs = _m(g.zombies, "inRadius", [p.pos, 3.0, []])
	if zs is Array:
		for z in zs:
			var v: Vector3 = z.pos - p.pos
			v.y = 0.0
			if v.length_squared() < 1e-4:
				v = Vector3(randf() - 0.5, 0, randf() - 0.5)
			_m(g.zombies, "knockback", [z, v.normalized() * 2.0])
	var fp: Vector3 = S.product + S.fwd * 1.2
	_m(g.lights, "flash", [fp, "#FFF2D8", 10, 0.3, 10])
	_m(g.hud, "whiteout", [0.45, 0.28])
	_play("studio_flash")
	# the perk itself
	var ok = _m(g.perks, "give", [S.id, {"costume": false, "pop": false, "emit": true}])
	if not ok and g.perks and not g.perks.has(S.id):
		_m(g.perks, "detachCostume", [S.id, {"poof": false}])
	if S.id == "replay_ade" and replayBought >= int(Config.T.perks.replayMax):
		_soldOut(S)
	g.events.emit("machine:commercial_end", {"perkId": S.id})

# THREE Vector3.project(camera) for the ad's 4:3 perspective camera -> overlay (CSS px) coordinates.
func _project(pos: Vector3, cam: Camera3D) -> Dictionary:
	var xf := _gxf(cam)
	var c := xf.affine_inverse() * pos
	var tanH := tan(deg_to_rad(cam.fov) * 0.5)
	var aspect := 4.0 / 3.0
	var nx := 0.0
	var ny := 0.0
	if absf(c.z) > 1e-6:
		nx = (c.x / -c.z) / (tanH * aspect)
		ny = (c.y / -c.z) / tanH
	var vp: Dictionary = Commercial.getOverlay().viewport(4.0 / 3.0)
	return {"x": vp.x + (nx * 0.5 + 0.5) * vp.w, "y": vp.y + (1.0 - (ny * 0.5 + 0.5)) * vp.h}

# ------------------------------------------------------------------------------------------ sold out (Replay-Ade)
func _soldOut(S: Dictionary) -> void:
	S.soldOut = true
	S.tip = {"t": -0.35, "a": 0.0, "v": 0.0, "bounced": 0, "done": false}
	setTally(S.camProp, false)

func _updateTip(S: Dictionary, rdt: float) -> void:
	var tip = S.tip
	if tip == null:
		return
	tip.t += rdt
	if tip.t < 0:
		S.camProp.rotation.z = sin(tip.t * 60.0) * 0.02
		return
	var g = game
	if not tip.done:
		tip.v += (4.0 + sin(tip.a) * 14.0) * rdt
		tip.a += tip.v * rdt
		if tip.a >= 1.42:
			tip.a = 1.42
			if tip.bounced < 2:
				tip.v = -tip.v * (0.2 if tip.bounced else 0.32)
				tip.bounced += 1
				_play("land", {"pos": S.camPos, "rate": 0.55, "vol": 1})
				if tip.bounced == 1:
					var bp: Vector3 = S.camPos + S.fwd * -0.9
					bp.y = 0.1
					_m(g.fx, "burst", [bp, {"shape": "puff", "count": 10, "speed": 1.6, "size": 0.25, "life": 0.8}])
					var parts = DAU.ud(S.root).get("parts", {})
					if parts is Dictionary and parts.get("soldOut"):
						parts.soldOut.visible = true
						parts.soldOut.scale = Vector3.ONE * 0.01
						tip.tape = 0.0
			else:
				tip.v = 0.0
				tip.done = true
	# tip toward the mark (around the base's front edge)
	S.camProp.rotation_order = EULER_ORDER_YXZ
	S.camProp.rotation = Vector3(-tip.a, S.camYaw, 0)
	S.camProp.position = Vector3(S.camPos.x, S.camPos.y + sin(tip.a) * 0.22, S.camPos.z)
	if tip.has("tape") and tip.tape < 1:
		tip.tape = minf(1.0, tip.tape + rdt / 0.3)
		DAU.ud(S.root).parts.soldOut.scale = Vector3.ONE * maxf(0.01, _easeOutBack(tip.tape, 2.4))

# ------------------------------------------------------------------------------------------ per frame
func update(dt: float) -> void:
	var g = game
	var rdt: float = g.time.realDt if g.time.realDt else 0.0
	_t += rdt
	if _ad != null:
		_updateCommercial(rdt)
	var p = g.player
	var P = g.perks
	if p == null:
		return
	for S in sets.values():
		_updatePower(S, rdt)
		_updateTip(S, rdt)
		var dx: float = p.pos.x - S.mark.x
		var dz: float = p.pos.z - S.mark.z
		var d := Vector2(dx, dz).length()
		# [E] anywhere within the mark radius, no facing requirement: the item rides along with the player
		if d <= Config.T.perks.markRadius and _ad == null:
			S.item.pos = p.pos
		else:
			S.item.pos = S.mark
		var par = S.root.get_parent()
		var visible: bool = par.visible if par is Node3D else true
		if visible:
			animateProduct(S.root, _t)
		_updateTeaser(S, d, dt, rdt)
		# perk limit: the camera shakes its head when you step onto the X
		var onMark: bool = d <= Config.T.perks.markRadius
		S.limitT = maxf(0.0, S.limitT - rdt)
		if onMark and not S.onMark and P and _ad == null and not S.soldOut and not P.has(S.id) and P.list.size() >= P.max and _live(S) and S.limitT <= 0:
			S.limitT = 3.0
			S.shakeT = 0.0
			_play("sponsor_denied", {"pos": S.camPos})
		S.onMark = onMark
		_updateCameraHead(S, d, rdt)

func _updateTeaser(S: Dictionary, d: float, dt: float, rdt: float) -> void:
	S.teaserCd = maxf(0.0, S.teaserCd - rdt)
	var near := d <= 5.0
	if near and not S.near and S.teaserCd <= 0 and _live(S) and not S.soldOut and _ad == null and dt > 0:
		S.teaserCd = 8.0
		S.teaseT = 0.0
		_play("sponsor_teaser_" + S.id, {"pos": S.product})
	S.near = near
	var parts = DAU.ud(S.root).get("parts", {})
	var tt = parts.get("turntable") if parts is Dictionary else null
	if S.teaseT >= 0:
		S.teaseT += rdt
		var k: float = S.teaseT
		var prod = parts.get("product") if parts is Dictionary else null
		if prod is Node3D:
			var hop := maxf(0.0, sin(minf(1.0, k / 0.45) * PI)) * 0.14 + maxf(0.0, sin(_clamp01((k - 0.45) / 0.3) * PI)) * 0.05
			prod.position.y = 0.045 + hop
			var sq := 1.0 + sin(k * 26.0) * 0.06 * maxf(0.0, 1.0 - k)
			prod.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
		if tt is Node3D:
			tt.rotation.y += rdt * 7.0 * maxf(0.0, 1.0 - k)
		if k > 1.05:
			S.teaseT = -1.0
			if prod is Node3D:
				prod.position.y = 0.045
				prod.scale = Vector3.ONE

func _updateCameraHead(S: Dictionary, d: float, rdt: float) -> void:
	var H = S.camHead
	if not (H is Node3D):
		return
	var p = game.player
	var yaw := 0.0
	if S.shakeT >= 0:
		S.shakeT += rdt
		var k: float = S.shakeT / 1.2
		yaw = sin(k * TAU * 2.0) * 0.5 * (1.0 - k * 0.5)
		var blink := int(floorf(S.shakeT / 0.1)) % 2 == 0
		setTally(S.camProp, blink and _live(S) and not S.soldOut)
		if k >= 1:
			S.shakeT = -1.0
			setTally(S.camProp, _live(S) and not S.soldOut)
	elif d < 3.5 and _live(S) and not S.soldOut and _ad == null:
		# follow the player around the mark
		var want: float = atan2(-(p.pos.x - S.camPos.x), -(p.pos.z - S.camPos.z)) - S.camYaw
		yaw = clampf(atan2(sin(want), cos(want)), -0.6, 0.6)
	else:
		yaw = sin(_t * 0.35 + S.id.length()) * 0.06
	if S.tip != null:
		yaw = 0.0
	S.headYaw += (yaw - S.headYaw) * (1.0 if S.shakeT >= 0 else 1.0 - exp(-rdt * 4.0))
	H.rotation.y = S.headYaw

# ------------------------------------------------------------------------------------------ gag props
func _ensureGags() -> void:
	var g = game
	if _gags == null:
		var G := {}
		var b = _m(g.props, "build", ["product_replay_ade", {}])
		if b is Node3D:
			b.scale = Vector3.ONE * 0.19
			G.bottle = b
		var peel := buildPeel()
		if peel:
			G.peel = peel
		var spoon = buildSpoon()
		if spoon:
			G.spoon = spoon
		var glove = buildGlove()
		if glove:
			G.glove = glove
		var pot := buildPot()
		if pot:
			G.pot = pot
		var brush := buildBrush()
		if brush:
			brush.scale = Vector3.ONE * 1.7
			G.brush = brush
		var gun = _m(g.weapons, "buildModel", ["revolver_38", false])
		if not (gun is Node3D):
			gun = fallbackGun()
		if gun:
			G.gun = gun
		var sk = _m(g.props, "build", ["costume_skates", {}])
		if sk is Node3D:
			G.skates = sk
		for o in G.values():
			var root = o.grp if o is Dictionary else o
			if root is Node3D:
				root.rotation_order = EULER_ORDER_XYZ
				DAU.traverse(root, func(m):
					if m is GeometryInstance3D:
						(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		_gags = G
	var hero = _f(g.player, "hero")
	if hero and _dupHero != hero:
		if _dups != null:
			for d in _dups:
				DAU.detach(d.holder)
		_dups = []
		_dupHero = hero
		for col in [Config.PAL.gelCyan, Config.PAL.gelMagenta]:
			var c: Dictionary = PerksLib.cloneHero(hero, [_f(g.player, "weaponModel")])
			var c3 := Color(col)
			# flat tinted Lambert (no vertex colours)
			var mat := StandardMaterial3D.new()
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.albedo_color = Color(c3.r, c3.g, c3.b, 0.8)
			mat.emission_enabled = true
			mat.emission = c3 * 0.5
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			mat.disable_fog = true
			for m in c.meshes:
				m.material_override = mat
				if not PerksLib._isSkinned(m) and PerksLib._radius(m) < 0.025:
					m.visible = false
			var holder := DAU.node3d("dup")
			holder.add_child(c.group)
			var e := c.duplicate()
			e.holder = holder
			e.color = col
			_dups.append(e)

# ------------------------------------------------------------------------------------------ pantomimes
func _setupPantomime(ad: Dictionary) -> void:
	var p = game.player
	var G: Dictionary = _gags if _gags != null else {}
	var hero = _f(p, "hero")
	var add := func(obj):
		if obj == null:
			return null
		var root = obj.grp if obj is Dictionary else obj
		DAU.detach(root)
		p.model.add_child(root)
		root.visible = true
		ad.props.append(root)
		return obj
	var art = _f(hero, "art")
	ad.face = _f(art, "face")
	match ad.id:
		"replay_ade":
			add.call(G.get("bottle"))
			add.call(G.get("peel"))
		"wobble_up":
			add.call(G.get("spoon"))
			if G.get("spoon") and G.spoon.jelly:
				G.spoon.jelly.visible = true
			if G.get("glove"):
				add.call(G.glove)
				setExtend(G.glove, 0.2)
		"jump_cut":
			add.call(G.get("pot"))
			if G.get("gun"):
				add.call(G.gun)
				G.gun.visible = false
		"roller_boogie":
			var sk = G.get("skates")
			var parts = DAU.ud(sk).get("parts") if sk else null
			var slots = _f(hero, "slots")
			if parts is Dictionary and slots:
				ad.skates = []
				for side in ["footL", "footR"]:
					var part = parts.get(side)
					var slot = _f(slots, side)
					if not (part is Node3D) or slot == null:
						continue
					part.position = Vector3.ZERO
					part.rotation = Vector3.ZERO
					DAU.detach(part)
					slot.add_child(part)
					ad.skates.append(part)
		"double_vision":
			add.call(G.get("brush"))

func _cleanupPantomime(ad: Dictionary) -> void:
	var g = game
	var p = g.player
	var an = _f(p, "animator")
	if an and an.get("override"):
		an.set("override", null)
	for o in ad.props:
		DAU.detach(o)
	ad.props.clear()
	if ad.get("skates") != null:
		for part in ad.skates:
			DAU.detach(part)
		ad.skates = null
	if _dups != null:
		for d in _dups:
			DAU.detach(d.holder)
	var wm = _f(p, "weaponModel")
	if wm:
		wm.visible = ad.get("weaponVis", true)
	var model = _f(p, "model")
	if model:
		model.visible = true
	if ad.get("face") != null:
		_m(ad.face, "setExpression", ["neutral", 1])
	var S: Dictionary = ad.S
	S.camProp.visible = not _f(g.render, "cameraOverride")
	var post = _f(g.render, "post")
	if post is Dictionary:
		post.chroma = ad.post.chroma

# probability helper for per-frame emission at `rate` per second
func rdtChance(rate: float) -> float:
	var rdt: float = game.time.realDt if game.time.realDt else 0.016
	return minf(1.0, rdt * rate)

func _heroId() -> String:
	var id = _f(game.player, "heroId")
	return id if id else "duke"

func _setChroma(v: float) -> void:
	var post = _f(game.render, "post")
	if post is Dictionary:
		post.chroma = v

# Camera beats, overlay FX, particles and sounds of each pantomime (sponsors.update, real time).
func _beats(ad: Dictionary, t: float, st: Dictionary) -> void:
	var g = game
	var S: Dictionary = ad.S
	var cam: Camera3D = S.cam
	var sp = _f(g.perks, "sparkles")
	var p = g.player
	var hero = _f(p, "hero")
	var worldOf := func(obj) -> Vector3: return _wpos(obj)
	# default framing (jump cut changes it)
	var frame := func(dIn: float = 0.0, side: float = 0.0, up: float = 0.0, fovMul: float = 1.0, lookUp: float = 0.0) -> void:
		var pos: Vector3 = S.camBase + S.fwd * -dIn + S.right * side
		pos.y += up
		var w: Vector3 = S.camLook
		w.y += lookUp
		_camLook(cam, pos, w)
		var f: float = rad_to_deg(2.0 * atan(1.36 / S.camD)) * fovMul
		if absf(cam.fov - f) > 1e-3:
			cam.fov = f
	match ad.id:
		"replay_ade":
			frame.call(0.0, 0.0, 0.0, 1.0)
			if t >= 1.25 and t < 1.4:
				st.osd = "pause"
				st.tracking = 0.25
			if t >= 1.4 and t < 1.86:
				st.osd = "rew"
				st.tracking = 0.9
				_setChroma(3.0)
			else:
				_setChroma(ad.post.chroma)
			_once(ad, t, "glug", 0.3, func():
				if sp and ad.props.size() > 0:
					sp.emit(worldOf.call(ad.props[0]), {"count": 6, "colors": ["#FFE14D", "#7FB8FF"], "speed": 0.8, "size": 0.05, "life": 0.4, "gravity": 3}))
			_once(ad, t, "slip", 0.86, func():
				_play("telly_boing", {"vol": 0.8})
				if sp:
					var sv: Vector3 = S.spot
					sv.y = S.mark.y + 0.15
					sp.emit(sv, {"kind": "puff", "count": 5, "speed": 1.2, "size": 0.12, "life": 0.4, "gravity": -0.4}))
			_once(ad, t, "freeze", 1.25, func(): _play("commercial_cut", {"vol": 0.6}))
			_once(ad, t, "rew", 1.4, func(): _play("replay_rewind"))
			_once(ad, t, "land", 1.86, func(): _play("land", {"vol": 0.8}))
			_once(ad, t, "thumb", 1.98, func():
				if sp and hero:
					sp.emit(worldOf.call(hero.slots.handR), {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.34, "life": 0.5, "gravity": 0, "spin": 4})
				_play("smile_ting", {"vol": 0.6}))
		"wobble_up":
			var shake := sin(t * 90.0) * 0.03 * (1.0 - (t - 0.72) / 0.28) if t > 0.72 and t < 1.0 else 0.0
			frame.call(0.0, shake, 0.0, 1.0)
			_once(ad, t, "gulp", 0.45, func():
				if _gags.get("spoon") and _gags.spoon.jelly:
					_gags.spoon.jelly.visible = false)
			_once(ad, t, "pow", 0.72, func():
				_play("melee_hit_skip", {"vol": 0.9})
				_play("jelly_bwoing", {"delay": 0.05})
				if sp and hero:
					sp.emit(worldOf.call(hero.parts.head), {"count": 12, "colors": ["#FFE27A", "#FFFFFF", "#52E04A"], "speed": 3, "size": 0.12, "life": 0.55, "gravity": 0.5}))
			_once(ad, t, "thumb", 1.85, func():
				if sp and hero:
					sp.emit(worldOf.call(hero.slots.handR), {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.34, "life": 0.5, "gravity": 0, "spin": 4})
				_play("smile_ting", {"vol": 0.6}))
		"jump_cut":
			var cuts := [0.7, 1.2, 1.7]
			var c := -1
			for i in 3:
				if t >= cuts[i]:
					c = i
			if c == -1:
				frame.call(0.0, 0.0, 0.0, 1.0)
			elif c == 0:
				frame.call(0.55, -0.35, -0.05, 0.86, 0.08)
			elif c == 1:
				frame.call(-0.2, 0.45, 0.1, 1.04, 0.0)
			else:
				frame.call(1.05, 0.12, 0.18, 0.72, 0.42)
			for i in 3:
				var dtc: float = t - cuts[i]
				if dtc >= 0 and dtc < 0.06:
					st.splice = 1.0 - dtc / 0.06
				_once(ad, t, "cut%d" % i, cuts[i], func():
					_play("commercial_cut")
					_play("jumpcut_snip", {"delay": 0.02}))
			if t < 0.7 and sp and _gags.get("pot") and randf() < rdtChance(22):
				var pp: Vector3 = worldOf.call(_gags.pot) + Vector3(0, 0.22, 0)
				sp.emit(pp, {"kind": "puff", "count": 1, "colors": ["#FFFFFF", "#F2EEE6"], "speed": 0.3, "size": 0.045, "life": 0.9, "gravity": -0.35, "dir": Vector3(0, 1, 0), "cone": 0.35, "grow": 2.6})
			_once(ad, t, "reload", 1.45, func():
				_play("reload_speedloader", {"vol": 0.8})
				if sp and _gags.get("gun"):
					sp.emit(worldOf.call(_gags.gun), {"count": 8, "colors": ["#FFE27A", "#FFFFFF"], "speed": 1.6, "size": 0.08, "life": 0.4, "gravity": 0}))
			_once(ad, t, "wink", 1.8, func():
				if sp and hero:
					var wp: Vector3 = worldOf.call(hero.parts.head) + Vector3(0, 0.05, 0) + S.fwd * 0.2
					sp.emit(wp, {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.3, "life": 0.45, "gravity": 0, "spin": 5})
				_play("smile_ting", {"vol": 0.55}))
		"roller_boogie":
			frame.call(0.0, 0.0, 0.0, 1.0)
			_once(ad, t, "whoosh", 0.14, func(): _play("melee_whoosh", {"rate": 0.6, "vol": 0.9}))
			_once(ad, t, "push1", 0.64, func(): _play("skate_push"))
			_once(ad, t, "push2", 0.92, func(): _play("skate_push"))
			_once(ad, t, "disco", 1.52, func():
				if sp and hero:
					sp.emit(worldOf.call(hero.slots.handR), {"count": 16, "colors": ["#FF9EDB", "#7FE7FF", "#FFE27A", "#FFFFFF"], "speed": 2.6, "size": 0.1, "life": 0.7, "gravity": 0.3})
				_play("smile_ting", {"vol": 0.5}))
			if sp and hero and ((t > 0.12 and t < 0.4) or (t > 0.62 and t < 1.35)) and randf() < rdtChance(70):
				for side in ["footL", "footR"]:
					sp.emit(worldOf.call(hero.slots[side]), {"count": 1, "colors": ["#FF9EDB", "#7FE7FF", "#FFE27A"], "speed": 0.3, "size": 0.07, "life": 0.5, "gravity": -0.2})
		"double_vision":
			frame.call(0.0, 0.0, 0.0, 1.0)
			if t < 0.8 and sp and hero and randf() < rdtChance(16):
				var hp: Vector3 = worldOf.call(hero.parts.head) + S.fwd * 0.22 + Vector3(0, -0.08, 0)
				sp.emit(hp, {"kind": "puff", "count": 1, "colors": ["#FFFFFF", "#DFF8FF"], "speed": 0.4, "size": 0.045, "life": 0.5, "gravity": 0.6, "grow": 1.5})
			_once(ad, t, "ting", 0.95, func():
				_play("smile_ting")
				if sp and hero:
					var hp2: Vector3 = worldOf.call(hero.parts.head) + S.fwd * 0.24 + Vector3(0.03, -0.06, 0)
					sp.emit(hp2, {"count": 1, "color": "#FFFFFF", "speed": 0.01, "size": 0.46, "life": 0.55, "gravity": 0, "spin": 6}))
			_once(ad, t, "split", 1.2, func():
				var mp = p.model.get_parent()
				if _dups != null and mp:
					for d in _dups:
						DAU.detach(d.holder)
						mp.add_child(d.holder)
				_play("commercial_cut", {"vol": 0.5}))
			if t >= 1.2:
				_setChroma(2.0 + 5.0 * maxf(0.0, 1.0 - (t - 1.2) / 0.5))
		_:
			frame.call()

# animator.override: the pantomime pose (real dt), after the procedural pose. Also places the hero and gag props.
func _pose(rig, _dt: float = 0.0) -> void:
	var ad = _ad
	if ad == null:
		return
	var g = game
	var p = g.player
	var J = rig.joints
	var t: float = ad.t
	var S: Dictionary = ad.S
	var m: Node3D = p.model
	var G: Dictionary = _gags if _gags != null else {}
	var POSES := _POSES()
	var W := _smooth(0.0, 0.1, t)
	var root: Node3D = rig.root
	var dims = _f(rig, "dims", {})
	var setJ := func(name: String, e, w: float = 1.0) -> void:
		var j = J.get(name) if J is Dictionary else _f(J, name)
		if j == null or e == null:
			return
		j.quaternion = Rig.slerp(Rig.quatOf(j), _qe(e), w * W)
	var pose := func(P: Dictionary, w: float = 1.0) -> void:
		for n in P:
			setJ.call(n, P[n], w)
	m.position = S.spot
	m.rotation.y = ad.faceYaw
	var face = ad.get("face")
	var expr := func(name: String, w: float = 1.0) -> void:
		if face != null and ad.get("_expr") != name:
			_m(face, "setExpression", [name, w])
			ad._expr = name
	var ID := _heroId()
	match ad.id:
		"replay_ade":
			# logical time: play -> freeze at 1.25 -> rewind back to 0.65 by 1.86 -> land
			var tau := t
			if t >= 1.25 and t < 1.4:
				tau = 1.25
			elif t >= 1.4 and t < 1.86:
				tau = 1.25 - ((t - 1.4) / 0.46) * 0.6
			elif t >= 1.86:
				tau = 0.65
			var drink: float = key(tau, [[0, 0], [0.18, 1], [0.58, 1], [0.72, 0]])
			var step: float = key(tau, [[0.62, 0], [0.84, 1]])
			var slip := _smooth(0.84, 1.25, tau)
			pose.call(REST)
			setJ.call("shoulderR", [_lerp(0.2, 1.25, drink), 0, _lerp(-0.1, -0.45, drink)])
			setJ.call("elbowR", [_lerp(0.4, 2.15, drink), 0, 0])
			setJ.call("head", [0.42 * drink * _smooth(0.2, 0.35, tau), 0, 0])
			setJ.call("spine", [0.1 * drink, 0, 0])
			setJ.call("shoulderL", [0.1, 0, 0.1 + 0.25 * drink])
			# step onto the peel
			setJ.call("hipR", [0.45 * step * (1.0 - slip), 0, 0])
			setJ.call("kneeR", [-0.5 * step * (1.0 - step), 0, 0])
			# slip: legs fly up, body goes over backward, arms flail
			if slip > 0:
				var a := slip * 1.6
				var h: float = float(_f(dims, "hipsY", 0.9))
				if h == 0.0:
					h = 0.9
				root.rotation.x = a
				root.position = Vector3(0, h - h * cos(a) + sin(minf(1.0, slip * 1.15) * PI * 0.5) * 0.7, -h * sin(a) * 0.4)
				setJ.call("hipL", [1.2 * slip, 0, 0])
				setJ.call("hipR", [1.5 * slip, 0, 0])
				setJ.call("kneeL", [-0.6 * slip, 0, 0])
				setJ.call("kneeR", [-0.3 * slip, 0, 0])
				setJ.call("shoulderL", [2.6 * slip, 0, 0.7 * slip])
				setJ.call("shoulderR", [2.4 * slip + 0.4, 0, -0.8 * slip])
				setJ.call("elbowL", [0.3, 0, 0])
				setJ.call("elbowR", [0.4, 0, 0])
				setJ.call("head", [-0.4 * slip, 0, 0])
				expr.call("o_mouth")
			else:
				expr.call("smile" if drink > 0.5 else "neutral")
			m.position += S.fwd * (0.22 * step)
			if t >= 1.86:
				var k := _smooth(1.86, 2.02, t)
				var land := maxf(0.0, sin(_clamp01((t - 1.86) / 0.22) * PI))
				root.scale = Vector3(1.0 + land * 0.07, 1.0 - land * 0.12, 1.0 + land * 0.07)
				setJ.call("shoulderR", [1.05, 0, -0.2], k)
				setJ.call("elbowR", [1.4, 0, 0], k)
				setJ.call("shoulderL", [0.85, 0, 0.35], k)
				setJ.call("elbowL", [1.25, 0, 0], k)
				setJ.call("head", [0.12, 0, 0.14], k)
				expr.call("wink")
			# the bottle rides the right hand; the peel lies ahead and shoots away on the slip (and back on rewind)
			if t < 1.86:
				_propAtHand(G.get("bottle"), p, "handR", m, [0, 0.02, -0.03], [-(0.2 + 1.75 * drink * _smooth(0.18, 0.4, tau)), 0, 0], 1)
			else:
				_propAtHand(G.get("bottle"), p, "handL", m, [0, 0.03, -0.03], [0.15, 0, 0.25], 1)
			if G.get("peel"):
				var pl: Node3D = G.peel
				pl.position = Vector3(-0.05, sin(slip * PI) * 0.4, -0.36 - slip * 1.4)
				pl.rotation = Vector3(slip * 5.0, slip * 3.0, 0)
		"wobble_up":
			var eat: float = key(t, [[0, 0], [0.16, 1], [0.48, 1], [0.62, 0]])
			var hit := _smooth(0.66, 0.72, t) * (1.0 - _smooth(0.95, 1.2, t))
			pose.call(REST)
			setJ.call("shoulderR", [_lerp(0.25, 1.2, eat), 0, _lerp(-0.1, -0.42, eat)])
			setJ.call("elbowR", [_lerp(0.5, 2.2, eat), 0, 0])
			setJ.call("shoulderL", [0.1, 0, 0.1])
			setJ.call("head", [0.1 * eat - 0.05 * hit, -0.55 * hit, -0.45 * hit])
			setJ.call("spine", [0, -0.25 * hit, -0.28 * hit])
			expr.call(("o_mouth" if eat > 0.5 else "neutral") if t < 0.5 else ("smile" if t < 0.72 else ("o_mouth" if t < 1.6 else "smile")))
			# gelatin jiggle after the punch
			if t > 0.72:
				var tt := t - 0.72
				var amp := 0.42 * exp(-2.1 * tt)
				var y := 1.0 + amp * sin(tt * 21.0)
				var xz := 1.0 / sqrt(maxf(0.4, y))
				root.scale = Vector3(xz * (1.0 + amp * 0.25 * sin(tt * 17.0)), y, xz)
				var sway := amp * sin(tt * 18.0 + 1.0) * 0.8
				setJ.call("spine", [0, 0, sway], 1)
				setJ.call("chest", [0, 0, -sway * 0.7], 1)
				setJ.call("head", [0, 0, sway * 1.2], 1)
			if t > 1.72:
				pose.call(POSES.thumbsup, _smooth(1.72, 1.9, t))
			_propAtHand(G.get("spoon"), p, "handR", m, [0, 0.0, -0.02], [-(0.3 + 1.1 * eat), 0, 0], 1)
			if G.get("glove"):
				var out: float = key(t, [[0.5, 0], [0.72, 1], [0.86, 1], [1.2, 0]])
				var len := _lerp(0.18, 2.3, _easeOut(out))
				setExtend(G.glove, len)
				# box sits off frame (the hero's right = frame left), the glove punches toward the cheek
				var height: float = float(_f(dims, "height", 1.75))
				if height == 0.0:
					height = 1.75
				var headY := height * 0.87
				G.glove.grp.position = Vector3(2.75, headY - 0.06, -0.1)
				G.glove.grp.rotation = Vector3(0, PI, 0)
				G.glove.grp.visible = t > 0.45 and t < 1.25
		"jump_cut":
			var cuts := [0.7, 1.2, 1.7]
			pose.call(REST)
			if t < cuts[0]:
				var sip: float = key(t, [[0, 0], [0.18, 1], [0.55, 1], [0.7, 0.8]])
				setJ.call("shoulderR", [_lerp(0.3, 1.15, sip), 0, _lerp(-0.1, -0.4, sip)])
				setJ.call("elbowR", [_lerp(0.6, 2.05, sip), 0, 0])
				setJ.call("head", [0.18 * sip, 0, 0])
				setJ.call("shoulderL", [0.2, 0, 0.12])
				expr.call("o_mouth" if sip > 0.6 and t > 0.35 else "smile")
				_propAtHand(G.get("pot"), p, "handR", m, [0, -0.06, -0.02], [-(0.15 + 0.6 * sip * _smooth(0.2, 0.4, t)), 0, 0], 1)
				if G.get("gun"):
					G.gun.visible = false
			elif t < cuts[1]:
				# arms crossed, chin up
				if G.get("pot"):
					G.pot.visible = false
				# upper arms down, forearms folded across the chest (the shoulder's y twist aims the elbow bend inward)
				setJ.call("shoulderL", [0.42, -1.0, 0.12])
				setJ.call("elbowL", [1.95, 0, 0])
				setJ.call("shoulderR", [0.34, 1.0, -0.12])
				setJ.call("elbowR", [1.85, 0, 0])
				setJ.call("head", [0.18, 0.2, 0.08])
				setJ.call("spine", [0.08, 0, 0])
				expr.call("smile")
			elif t < cuts[2]:
				# finger guns (the prop revolver in the right hand reloads itself)
				pose.call(POSES.fingerguns)
				setJ.call("head", [0.05, 0.15, -0.12])
				expr.call("smile")
				if G.get("gun"):
					G.gun.visible = true
					var spin := _smooth(1.42, 1.56, t)
					_propAtHand(G.gun, p, "handR", m, [0, -0.02, -0.04], [0, 0, 0], 1, spin * TAU)
			else:
				# wink + point at the viewer
				if G.get("gun"):
					G.gun.visible = false
				setJ.call("shoulderR", [1.45, 0, -0.15])
				setJ.call("elbowR", [0.15, 0, 0])
				setJ.call("shoulderL", [0.1, 0, 0.1])
				setJ.call("head", [0.1, 0, 0.22])
				setJ.call("spine", [0, 0.12, 0])
				expr.call("wink")
		"roller_boogie":
			var lift := 0.118
			var outK := _easeIn(_clamp01((t - 0.12) / 0.28))
			var inK := _easeOut(_clamp01((t - 0.62) / 0.68))
			var x := 0.0
			var spin := 0.0
			var smear := 0.0
			if t < 0.12:
				x = 0.0
			elif t < 0.4:
				x = 3.8 * outK
				smear = outK
			elif t < 0.62:
				x = 99.0
			else:
				x = -3.8 * (1.0 - inK)
				spin = (1.0 - inK) * TAU * 2.2
				smear = (1.0 - inK) * 0.7
			m.position += S.right * -x           # model +x (hero's right) = the viewer's left
			m.rotation.y = ad.faceYaw + spin
			m.visible = x != 99.0
			root.position.y += lift
			var crouch := _smooth(0.0, 0.12, t) if t < 0.12 else (1.0 if t < 1.35 else 1.0 - _smooth(1.35, 1.55, t))
			setJ.call("kneeL", [-0.7 * crouch, 0, 0])
			setJ.call("kneeR", [-0.35 * crouch, 0, 0])
			setJ.call("hipL", [0.45 * crouch, 0, -0.1])
			setJ.call("hipR", [-0.2 * crouch, 0, 0.18 * crouch])
			setJ.call("spine", [-0.3 * crouch, 0, 0])
			setJ.call("shoulderL", [0.4, 0, -0.9 * crouch])
			setJ.call("shoulderR", [0.2, 0, 0.9 * crouch])
			setJ.call("elbowL", [0.3, 0, 0])
			setJ.call("elbowR", [0.3, 0, 0])
			if smear > 0:
				var k := smear
				root.scale = Vector3(1.0 + 1.4 * k, 1.0 - 0.18 * k, 1.0 - 0.2 * k)
			if t > 1.5:
				var k := _smooth(1.5, 1.66, t)
				pose.call(DISCO, k)
				setJ.call("hipL", [0, 0, -0.12 * k])
				var pop := sin(_clamp01((t - 1.5) / 0.3) * PI) * 0.06
				root.position.x += pop
			expr.call("smile" if t > 1.45 else "neutral")
		"double_vision":
			var brush: float = key(t, [[0, 0], [0.12, 1], [0.78, 1], [0.92, 0]])
			pose.call(REST)
			var scrub := sin(t * 52.0) * 0.12 * brush
			setJ.call("shoulderR", [_lerp(0.25, 1.3, brush), 0, _lerp(-0.1, -0.5, brush) + scrub])
			setJ.call("elbowR", [_lerp(0.5, 2.25, brush), 0, 0])
			setJ.call("shoulderL", [0.1, 0, 0.1])
			setJ.call("head", [0.05 * brush, sin(t * 26.0) * 0.03 * brush, 0])
			expr.call("o_mouth" if t < 0.8 else "smile")
			_propAtHand(G.get("brush"), p, "handR", m, [-0.1, -0.05, -0.06], [0, 0, 1.5708 + sin(t * 52.0) * 0.1 * brush], 1 if brush > 0.05 else 0)
			if G.get("brush"):
				G.brush.visible = t < 0.92
			if t >= 0.92:
				var k := _smooth(0.92, 1.05, t)
				var sig = POSES.get("commercial_" + ID)
				pose.call(sig if sig != null else POSES.thumbsup, k)
				setJ.call("head", [0.12, 0, 0.1], k)
			# the duplicates drift apart striking their own poses
			if t >= 1.2 and _dups != null:
				var k := _easeOut(_clamp01((t - 1.2) / 0.35))
				var poses := [DISCO, POSES.fingerguns]
				for i in _dups.size():
					var d: Dictionary = _dups[i]
					PerksLib.copyPose(p.hero, d)
					var DJ: Dictionary = d.joints
					for n in poses[i]:
						var e = poses[i][n]
						if DJ.get(n):
							DJ[n].quaternion = _qe(e)
					var hpos: Vector3 = m.position + S.right * ((1.0 if i else -1.0) * 0.34 * k) + S.fwd * -0.05
					hpos.y += sin((t - 1.2) * 9.0 + i * 2.0) * 0.02
					d.holder.position = hpos
					d.holder.rotation = Vector3(0, ad.faceYaw + (-0.25 if i else 0.25) * k, 0)
					d.holder.visible = true

# Places a gag prop at a hand slot (model space), oriented upright in the model frame then tilted by `tilt` (euler).
func _propAtHand(obj, p, slot: String, m: Node3D, offset: Array, tilt: Array, vis = 1, roll: float = 0.0) -> void:
	if obj == null:
		return
	var root: Node3D = obj.grp if obj is Dictionary else obj
	var s = _f(_f(p.hero, "slots"), slot)
	if not (s is Node3D):
		return
	root.visible = vis > 0
	var v: Vector3 = _gxf(m).affine_inverse() * _wpos(s)
	root.position = Vector3(v.x + offset[0], v.y + offset[1], v.z + offset[2])
	root.rotation = Vector3(tilt[0], tilt[1], tilt[2] + roll)

# ------------------------------------------------------------------------------------------ prop runtime helpers
# (src/props/sponsors.js exports, used only here.) A power material may arrive as a Material, a material spec
# Dictionary (the Blender "da" spec; built with game.mats.fromSpec) or a node reference (its material is used).
func _asMat(mat):
	if mat == null:
		return null
	if mat is Material:
		return mat
	if mat is MeshInstance3D:
		var mi := mat as MeshInstance3D
		if mi.material_override:
			return mi.material_override
		if mi.mesh and mi.mesh.get_surface_count() > 0:
			var so := mi.get_surface_override_material(0)
			return so if so else mi.mesh.surface_get_material(0)
		return null
	if mat is Dictionary:
		var k := JSON.stringify(mat)
		if _matCache.has(k):
			return _matCache[k]
		var out = null
		if game.mats and game.mats.has_method("fromSpec"):
			out = game.mats.fromSpec(mat, null)
		_matCache[k] = out
		return out
	return null

func _swapMat(list, mat) -> void:
	var m = _asMat(mat)
	if m == null:
		return
	var items: Array = list if list is Array else [list]
	for o in items:
		if o is MeshInstance3D:
			(o as MeshInstance3D).material_override = m
		elif o is Node:
			# a group where the JS had a mesh (a merged part): every mesh under it
			DAU.traverse(o, func(c):
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = m)

# Dark set before Sign-On (Replay-Ade is lit from the start): swaps sign / tally / softbox / bulb materials.
func setSponsorSetPower(set_node: Node3D, on: bool) -> void:
	if set_node == null:
		return
	var u := DAU.ud(set_node)
	var P = u.get("power")
	if not (P is Dictionary):
		return
	var M = P.get("on" if on else "off", {})
	var parts = u.get("parts", {})
	if not (M is Dictionary) or not (parts is Dictionary):
		return
	_swapMat(parts.get("sign"), M.get("sign"))
	_swapMat(parts.get("tally"), M.get("tally"))
	_swapMat(parts.get("diffuser"), M.get("soft"))
	_swapMat(parts.get("bulbs"), M.get("bulbs"))
	u.powered = on

# Tally light of a set or a camera prop.
func setTally(obj: Node3D, on: bool) -> void:
	if obj == null:
		return
	var u := DAU.ud(obj)
	var P = u.get("power")
	if not (P is Dictionary) or not (P.get("on") is Dictionary) or not P.on.get("tally"):
		return
	var parts = u.get("parts", {})
	if not (parts is Dictionary):
		return
	_swapMat(parts.get("tally", []), P.on.tally if on else P.get("off", {}).get("tally"))

# Idle life for a product (standalone or inside a set): jelly wobble, cap spin; the set's turntable + mirror ball.
static func animateProduct(obj: Node3D, t: float) -> void:
	var p = DAU.ud(obj).get("parts", {})
	if not (p is Dictionary):
		return
	var pp = p.get("productParts") if p.get("productParts") is Dictionary else p
	var jelly = pp.get("jelly")
	if jelly is Node3D:
		var w := sin(t * 7.0) * 0.025
		jelly.scale = Vector3(1.0 + w * 0.6, 1.0 - w, 1.0 + w * 0.6)
		jelly.rotation.z = sin(t * 5.3) * 0.02
	var cap = pp.get("cap")
	if cap is Node3D:
		cap.rotation.y = t * 1.6
	var tt = p.get("turntable")
	if tt is Node3D:
		tt.rotation.y = t * 0.35
	var mb = p.get("mirrorball")
	if mb is Node3D:
		mb.rotation.y = t * 0.8
