# Studio B — "HOOTIE'S HULLABALOO" (the kids' show) set dressing (GDD §5.7 "Studio B", lighting §3.3, toys §13,
# EE step 2 theater §13 / §18.13). Port of src/world/rooms/studio_b.js; uses the shared studio kit of studio_a.gd.
#
# build(game, area, root)  called by level.gd after the graybox (root = the area's 'dressing' node, in the tree).
#
# Layout (GDD §5.6/§5.7 + layout ANCHORS): cardboard rocket [22,0,-21] (the loop pillar, porthole facing D7 / the
# shot camera), treehouse facade [25.5,0,-27.6] with Hootie's giant TV = screen spawn ss_studio_b (scr_decor, loops
# 'hullabaloo'), the striped puppet theater (ee_puppet_theater, apron slots on the GDD sill line z -25.5), the blue
# chroma-key cyclorama on the east wall (narrowed to 3.3 m so it clears the treehouse), three 1 m ABC blocks, the
# rainbow arch FRAMING THE D6 ELEPHANT DOOR, the toy train loop (toy_train, x0.85, centre [18.95,-20.45]), the
# xylophone (toy_xylophone), giant crayons, a rainbow story rug + bean bags, the feed camera + stand monitor
# (scr_feed_studio_b), a painted "Hullabaloo Hills" flat, a toy piano, a toy chest, sunflower cut-outs, Hootie's
# costume rack by D7, the Sockettes' clothesline, balloon clusters, star/planet/cloud mobiles, bunting, fairy lights,
# wall cut-outs, star confetti, kid drawings, signage.
#
# Power (GDD §3.3): before Sign-On the room is lit by the moon night-light in the treehouse window, a glowing paper-moon
# lantern and dim fairy lights (+ a blue moon pool). When the Sign-On colour wave reaches each item: pastel gel
# Fresnels light (pink / lilac / yellow / cyan) with soft beams on the theater and Hootie's TV, pink + lilac fill
# anchors, pastel floor pools, brighter fairy lights, the cyc floods. (The level owns the grid key light #FFF1C9.)
#
# game.level.objects (world space). Dictionaries with Callables under the JS names; JS getters are fields kept in sync
# (open, running):
#   ee_puppet_theater { group, parts:{ curtain (Node3D: both halves), curtain_l, curtain_r, slot_owl, slot_sock,
#                       slot_dragon, sil_owl, sil_sock, sil_dragon }, slots:{ owl|sock|dragon: Vector3 },
#                       stage:{ owl|sock|dragon: Vector3 }, puppetOf, keyOf, interact:Vector3, interactR:1.5,
#                       filled:{ owl, sock, dragon }, open (0..1), setOpen(k, seconds = 0.8), setSlot(key, on),
#                       reset() }   (the EE registers the [E] interaction itself)
#   ss_studio_b { group, screen }   cardboard_rocket { group }   treehouse { group, parts }   chroma_cyc { group, mark }
#   rainbow_arch { group }   alpha_blocks { groups:[g1,g2,g3] }
#   toy_train     { group, parts:{ train }, running, run(laps = 2) }
#   toy_xylophone { group, parts:{ bars, mallets }, play(barIndices?) -> seconds }
#   feed_cam_studio_b { group, parts:{ head, tilt, tally, lensTip } }   mon_studio_b_stand { group, screen }
#   studio_b { rt, root, dyn, theater }  (debug)
# Toys (key-only [E] prompts, GDD §13): toy_train ('toy_train'), toy_xylophone ('toy_xylophone' with 3 random
#   pentatonic bars). Both emit 'toy:use' {id}.
#
# PORT NOTES (Godot)
# * Room-local geometry (countdown sign, launch-pad ring, tree-feet mushrooms, easel, the Hullabaloo Hills flat, toy
#   piano, toy chest, sunflowers, banners, drawings board, cue card, costume rack, wall cut-outs, confetti, spike
#   marks, the sock clothesline, bunting, fairy-light wire + bulbs, mobiles, balloon clusters, the golden puppet
#   silhouettes, the beam cone; the sb_atlas_v1 / hills / silhouette canvases) is built by
#   blender/runtime/rooms_studios_yard.py into res://assets/runtime/rooms_studios_yard/studio_b.glb.
# * HDR material colours the glTF cannot carry (fairy bulbs x2.2, glowCut / silhouette tints > 1) are re-applied here.
# * The JS step() try/catch wrappers are straight code (GDScript aborts only the failing function).
# * The xylophone's InstancedMesh bars are the prop's per-instance nodes (bars_<i>): their transforms bounce.
extends RefCounted

const Kit := preload("res://scripts/world/rooms/studio_a.gd")
const TAU := PI * 2.0
const HP := PI / 2.0
const AREA := "studio_b"
const GRID_Y := 5.0                       # surfaces.js studio_b gridY (pipes along x at 5.0, along z at 5.09)
const GX := [16.67, 18.8, 20.93, 23.07, 25.2, 27.33]      # z-running pipes (x fixed)
const GZ := [-26.33, -24.2, -22.07, -19.93, -17.8, -15.67] # x-running pipes (z fixed)
const W := {"w": 15.155, "e": 28.845, "n": -27.845, "s": -14.155} # inner wall faces
const PASTEL := ["#FF8FB8", "#FFB347", "#FFE45C", "#8CE07A", "#6FD3F0", "#9E8CFF", "#FF6F91"]

var game
var rt
var asset: Node3D

func _A(name: String) -> Node3D:
	return Kit.take(asset, name)

func _P(id, o: Dictionary) -> Node3D:
	var oo := {"area": AREA}
	oo.merge(o, true)
	return Kit.place(game, rt.root, id, oo)

func _box(mn: Array, mx: Array, tag := "prop") -> void:
	var col = game.level.get("col") if game.level != null else null
	if col != null:
		col.addBox(mn, mx, {"tag": tag})

func sfx(id: String, pos, o: Dictionary = {}):
	var A = game.get("audio")
	if A == null or not A.has_method("play"):
		return null
	var opts := {"pos": DAU.v3(pos)}
	opts.merge(o, true)
	return A.play(id, opts)

# A clone of every material named `nm` under node, recoloured with a LINEAR colour (THREE.Color(r, g, b) > 1).
static func _tint(node: Node, nm: String, lin: Color, cache: Dictionary) -> void:
	DAU.traverse(node, func(o):
		if o is MeshInstance3D:
			var m := Kit.getMat(o)
			if m is DAMaterial and (m as DAMaterial).name == nm:
				var c = cache.get(nm)
				if c == null:
					c = (m as DAMaterial).clone()
					c.color = lin.linear_to_srgb()
					cache[nm] = c
				(o as MeshInstance3D).material_override = c)

# ============================================================================================================ build
func build(g, _area: Dictionary, root: Node3D) -> void:
	game = g
	asset = Kit.loadAsset(g, "studio_b")
	rt = Kit.runtime(g, AREA, root, asset)
	var O: Dictionary = rt.objects
	var dyn := DAU.node3d("studio_b_dynamic")
	DAU.ud(dyn).noMerge = true
	root.add_child(dyn)
	var tints := {}

	# ------------------------------------------------------------------------------------------- hero props
	# rocket
	var ra = Layout.ANCHORS.prop_rocket
	var rocket := _P("cardboard_rocket", {"pos": ra.pos, "rotY": -3.0 * PI / 4.0, "colliders": false})
	# after the -135 deg turn the fins point along the world axes: body square + fin cross, axis-aligned
	var rx: float = float(ra.pos[0])
	var rz: float = float(ra.pos[2])
	_box([rx - 0.86, 0, rz - 0.86], [rx + 0.86, 5.5, rz + 0.86])
	_box([rx - 1.34, 0, rz - 0.2], [rx + 1.34, 1.9, rz + 0.2])
	_box([rx - 0.2, 0, rz - 1.34], [rx + 0.2, 1.9, rz + 1.34])
	O["cardboard_rocket"] = {"group": rocket}
	# painted launch-pad ring on the floor + the kid-lettered countdown sign on a stake
	var ring := _A("sb_launch")
	if ring != null:
		ring.position = Vector3(rx, 0.012, rz)
		root.add_child(ring)
	_P(null, {"group": _A("sb_countdown"), "pos": [23.2, 0, -19.8], "rotY": -3.0 * PI / 4.0 + 0.1})

	# treehouse
	var ta = Layout.ANCHORS.prop_treehouse
	var th := _P("treehouse_facade", {"pos": [ta.pos[0], 0, ta.pos[2]], "rotY": PI, "opts": {"card": "hullabaloo"}, "screenGroup": "scr_decor", "screenId": "ss_studio_b"})
	O["treehouse"] = {"group": th, "parts": Kit.partsOf(th)}
	var thScr = null
	if th != null and DAU.ud(th).get("screens") is Array and not DAU.ud(th).screens.is_empty():
		thScr = DAU.ud(th).screens[0].get("mesh")
	O["ss_studio_b"] = {"group": th, "screen": thScr}
	# cardboard mushrooms + flowers at the trunk's feet (clear of the TV spawn lane x 25..27)
	_P(null, {"group": _A("sb_tree_feet"), "pos": [ta.pos[0], 0, -26.75], "rotY": PI})

	var theaterObj := {}
	buildTheater(dyn, theaterObj, tints)

	# cyc
	var cyc := _P("chroma_cyc", {"pos": [28.35, 0, -25.0], "rotY": HP, "opts": {"width": 3.3, "height": 3.4}})
	# flood lenses stay dark until the Sign-On wave reaches the cyc
	var floods: Array = []
	if cyc != null:
		DAU.traverse(cyc, func(o):
			if o is MeshInstance3D:
				var m := Kit.getMat(o)
				if m is DAMaterial and ((m as DAMaterial).kind == "basic" or (m as DAMaterial).kind == "glow"):
					floods.append([o, (o as MeshInstance3D).material_override]))
	var off := Kit.kmat(g, "plastic", "#C8CCD8")
	for f in floods:
		DAU.ud(f[0]).noMerge = true
	var mark := Vector3(0, 0, -1)
	if cyc != null:
		var am = DAU.ud(cyc).get("anchors")
		mark = cyc.global_transform * DAU.v3(am.get("mark") if am is Dictionary and am.get("mark") != null else [0, 0, -1])
	O["chroma_cyc"] = {"group": cyc, "mark": mark}
	rt.anchor("sb_cyc", {"pos": [27.6, 3.0, -25.0], "color": "#DDE8FF", "intensity": 0, "distance": 5})
	var cycPool = rt.pool([27.35, 0.02, -24.8], 1.5, Config.PAL.gelCyan, 0)
	rt.onPower([28, 3, -25], func(on, _instant = false):
		for f in floods:
			f[0].material_override = f[1] if on else off
		rt.setAnchor("sb_cyc", {"intensity": 1.5 if on else 0.0})
		cycPool.set_({"intensity": 0.1 if on else 0.0}))

	# blocks
	var blocks := [
		_P("alphabet_block", {"pos": Layout.ANCHORS.prop_alpha_block_1.pos, "rotY": 0.35, "opts": {"variant": 0}}),
		_P("alphabet_block", {"pos": Layout.ANCHORS.prop_alpha_block_2.pos, "rotY": -0.2, "opts": {"variant": 1}}),
		_P("alphabet_block", {"pos": Layout.ANCHORS.prop_alpha_block_3.pos, "rotY": 0.1, "opts": {"variant": 2}}),
	]
	_P("alphabet_block", {"pos": [25.42, 1.0, -24.02], "rotY": 0.62, "scale": 0.5, "opts": {"variant": 2}, "colliders": false})
	O["alpha_blocks"] = {"groups": blocks}
	# little blocks tumbled around (0.28 m clones: no extra materials)
	for b in [[19.35, -22.0, 0.5, 1, 0.28], [19.55, -21.72, 1.2, 2, 0.26], [17.55, -21.95, 2.0, 0, 0.3],
			[24.9, -23.25, 0.9, 0, 0.28], [27.25, -24.05, 0.3, 1, 0.3], [20.35, -26.75, 1.4, 2, 0.26], [15.65, -26.95, 0.2, 0, 0.3]]:
		_P("alphabet_block", {"pos": [b[0], 0, b[1]], "rotY": b[2], "scale": b[4], "opts": {"variant": b[3]}, "colliders": false})
	_P("alphabet_block", {"pos": [19.45, 0.28, -21.86], "rotY": 0.2, "scale": 0.26, "opts": {"variant": 0}, "colliders": false})

	# rainbow: framing the D6 elephant door
	O["rainbow_arch"] = {"group": _P("rainbow_arch", {"pos": [16.95, 0, -20.1], "rotY": HP})}

	# ------------------------------------------------------------------------------------------- toys
	buildTrain(O)
	buildXylophone(O)

	# ------------------------------------------------------------------------------------------- feed camera
	Kit.feedCamera(g, rt, root, "feed_cam_studio_b", {"num": 1, "side": 0.9})
	Kit.standMonitor(g, rt, root, "mon_studio_b_stand")
	_P("bc_cable_spaghetti", {"pos": [21.3, 0, -15.05], "rotY": 0.2, "opts": {"w": 2.4, "d": 0.6, "count": 3, "seed": 4}})
	# cue-card easel beside the camera
	_P(null, {"group": _A("sb_easel"), "pos": [20.35, 0, -16.75], "rotY": 0.5})

	# ------------------------------------------------------------------------------------------- west wall corner
	_P(null, {"group": _A("sb_flat"), "pos": [W.w + 0.2, 0, -24.85], "rotY": -HP})
	_P(null, {"group": _A("sb_toy_piano"), "pos": [15.62, 0, -23.25], "rotY": -HP})
	_P("giant_crayons", {"pos": [16.0, 0, -25.55], "rotY": 0.08})
	_P("giant_crayon", {"pos": [17.2, 0, -21.95], "rotY": 2.6, "opts": {"color": 2}, "colliders": false})
	_P("giant_crayon", {"pos": [27.1, 0, -26.25], "rotY": 0.9, "opts": {"color": 4}, "colliders": false})
	# rainbow story rug + bean bags facing the puppet theater
	_P("rug_shag_round", {"pos": [18.0, 0.002, -24.05], "rotY": 0.3, "opts": {"r": 1.15, "rings": ["#FFE45C", "#FFB347", "#FF8FB8", "#B9A2FF", "#6FD3F0", "#8CE07A"]}})
	_P("bean_bag", {"pos": [16.62, 0, -24.05], "rotY": Kit.yawTo([16.62, 0, -24.05], [17.75, 0, -25.9]) + 0.2, "opts": {"color": "#FF8FB8", "seed": 3}})
	_P("bean_bag", {"pos": [27.55, 0, -26.3], "rotY": Kit.yawTo([27.55, 0, -26.3], [25.2, 0, -25.2]), "opts": {"color": "#6FD3F0", "seed": 5}})
	_P("bean_bag", {"pos": [28.12, 0, -14.9], "rotY": Kit.yawTo([28.12, 0, -14.9], [23, 0, -20]), "opts": {"color": "#FFD23A", "seed": 8}})

	# ------------------------------------------------------------------------------------------- north wall
	_P(null, {"group": _A("sb_sunflower_1"), "pos": [19.45, 0, -27.66], "rotY": PI + 0.06})
	_P(null, {"group": _A("sb_sunflower_2"), "pos": [20.72, 0, -27.7], "rotY": PI - 0.08})
	_P(null, {"group": _A("sb_toy_chest"), "pos": [20.1, 0, -27.22], "rotY": PI - 0.05})
	_P(null, {"group": _A("sb_banner_clap"), "pos": [22.0, 3.95, W.n + 0.03], "rotY": PI})
	# backstage behind the theater: puppet crate + stool
	_P("bc_flight_case", {"pos": [15.75, 0, -27.25], "rotY": 0.15, "opts": {"size": "md", "color": "#B05AD6"}})

	# ------------------------------------------------------------------------------------------- south + east walls
	_P(null, {"group": _A("sb_banner_logo"), "pos": [20.4, 3.85, W.s - 0.03], "rotY": 0.0})
	# kid drawings pinned on a pastel pin board
	_P(null, {"group": _A("sb_drawings"), "pos": [22.25, 1.55, W.s - 0.03], "rotY": 0.0})
	_P(null, {"group": _A("sb_banner_poster"), "pos": [28.15, 1.75, W.s - 0.03], "rotY": 0.0})
	_P(null, {"group": _A("sb_banner_peanut"), "pos": [W.e - 0.03, 2.72, -18.5], "rotY": HP})
	_P(null, {"group": _A("sb_banner_signB"), "pos": [W.w + 0.03, 3.75, -16.3], "rotY": -HP})
	# cut-outs pinned high on the walls + star confetti + floor spike marks (world coordinates)
	for nm in ["sb_cuts", "sb_confetti", "sb_spikes"]:
		var n := _A(nm)
		if n != null:
			root.add_child(n)
	# leaning cue card against block 1
	var cue := _P(null, {"group": _A("sb_cue"), "pos": [18.85, 0.22, -21.62], "rotY": PI + 0.35, "colliders": false})
	if cue != null:
		cue.rotation.x = 0.28

	_P(null, {"group": _A("sb_costume_rack"), "pos": [23.55, 0, -14.72], "rotY": 0.04})

	# ------------------------------------------------------------------------------------------- sockette clothesline
	var socks := _A("sb_socks")
	if socks != null:
		root.add_child(socks)

	# ------------------------------------------------------------------------------------------- overhead
	var bunting := _A("sb_bunting")
	if bunting != null:
		root.add_child(bunting)
	buildFairyLights(dyn)
	buildMobiles(dyn, tints)
	# balloons
	var spots := [[19.0, 2.35, -25.72, 11, 5, 1.0, true], [16.95, 1.25, -21.95, 23, 6, 0.9, true], [15.55, 1.36, -23.7, 5, 4, 0.8, false], [23.35, 3.45, -27.1, 17, 4, 0.55, false]]
	var blist: Array = []
	for i in spots.size():
		var sp: Array = spots[i]
		var bg := _A("sb_balloons_%d" % i)
		if bg == null:
			continue
		bg.rotation_order = EULER_ORDER_XYZ
		bg.position = Vector3(sp[0], sp[1], sp[2])
		if sp[6]:
			dyn.add_child(bg)
			blist.append({"g": bg, "ph": int(sp[3]) * 0.37})
		else:
			DAU.ud(bg).noMerge = false
			root.add_child(bg)
	rt.onTick(func(t, _dt, vis):
		if not vis:
			return
		for b in blist:
			var n: Node3D = b.g
			n.rotation = Vector3(sin(t * 0.53 + b.ph * 2.0) * 0.04, sin(t * 0.21 + b.ph) * 0.3, sin(t * 0.7 + b.ph) * 0.05))

	# ------------------------------------------------------------------------------------------- lighting
	buildLighting(dyn)

	if asset != null:
		asset.free()
		asset = null
	Kit.shadowHygiene(root)
	O["studio_b"] = {"rt": rt, "root": root, "dyn": dyn, "theater": theaterObj}

# ============================================================================================ puppet theater (EE)
func buildTheater(dyn: Node3D, out: Dictionary, tints: Dictionary) -> void:
	var g = game
	var a = Layout.ANCHORS.ee_puppet_theater
	# placed so the playboard ledge (the "sill") sits on the GDD slot line z -25.5
	var th := Kit.place(g, rt.root, "puppet_theater", {"area": AREA, "pos": [a.pos[0], 0, -26.1], "rotY": PI})
	if th == null:
		return
	var u := DAU.ud(th)
	var M: Transform3D = th.global_transform
	# curtain: both halves under one pivot node (parts stay valid)
	var curtain := DAU.node3d("curtain")
	DAU.ud(curtain).noMerge = true
	th.add_child(curtain)
	var cl: Node3D = Kit.partsOf(th).get("curtain_l")
	var cr: Node3D = Kit.partsOf(th).get("curtain_r")
	for c in [cl, cr]:
		if c != null:
			Kit.attach(curtain, c)
	# slot seats on the ledge above each painted silhouette + golden silhouette overlays on the apron (hidden)
	var AW := 2.1
	var AH := 1.05
	var AY := 0.72
	var D := 0.9
	var keys := ["owl", "sock", "dragon"]
	var parts := {"curtain": curtain, "curtain_l": cl, "curtain_r": cr}
	var slots := {}
	var stage := {}
	var sils := {}
	for i in keys.size():
		var k: String = keys[i]
		var cxPx: float = [0.18, 0.5, 0.82][i] * 512.0
		var cyPx := 0.55 * 256.0
		var lx := AW / 2.0 - (cxPx / 512.0) * AW
		var ly := AY + AH / 2.0 - (cyPx / 256.0) * AH
		var sil := _A("sb_sil_" + k)
		if sil != null:
			sil.name = "sil_" + k
			sil.position = M * Vector3(lx, ly, -D / 2.0 - 0.058)
			sil.rotation = Vector3.ZERO
			sil.visible = false
			dyn.add_child(sil)
			_tint(sil, "sb_silmat", Color(1.15, 1.02, 0.78), tints)
		sils[k] = sil
		parts["sil_" + k] = sil
		var seat := DAU.node3d("slot_" + k)
		seat.position = M * Vector3(lx, 1.36, -D / 2.0 - 0.08)
		dyn.add_child(seat)
		parts["slot_" + k] = seat
		slots[k] = seat.position
		var an = u.get("anchors")
		stage[k] = M * DAU.v3(an["stage_" + k]) if an is Dictionary and an.get("stage_" + k) != null else seat.position + Vector3(0, 0, -0.5)
	var state := {"open": 0.0, "from": 0.0, "to": 0.0, "t": 0.0, "dur": 0.0, "filled": {"owl": false, "sock": false, "dragon": false}}
	var obj := {
		"group": th, "parts": parts, "slots": slots, "stage": stage,
		"puppetOf": {"owl": "ee_puppet_hootie", "sock": "ee_puppet_sockrates", "dragon": "ee_puppet_dudley"},
		"keyOf": {"ee_puppet_hootie": "owl", "ee_puppet_sockrates": "sock", "ee_puppet_dudley": "dragon"},
		"interact": DAU.v3(a.interact), "interactR": float(a.get("interactR")) if a.get("interactR") != null else 1.5,
		"filled": state.filled, "open": 0.0,
	}
	var applyOpen := func(k: float):
		state.open = k
		obj.open = k
		var sx := 1.0 - 0.75 * k
		if cl != null:
			cl.scale.x = sx
		if cr != null:
			cr.scale.x = sx
	obj["setOpen"] = func(k, seconds = 0.8):
		var kk := clampf(float(k), 0.0, 1.0)
		if float(seconds) <= 0.0:
			state.dur = 0.0
			applyOpen.call(kk)
			return
		state.merge({"from": state.open, "to": kk, "t": 0.0, "dur": float(seconds)}, true)
	obj["setSlot"] = func(key, on = true):
		if not state.filled.has(key):
			return
		state.filled[key] = Kit.truthy(on)
		var s: Node3D = sils[key]
		if s != null:
			s.visible = Kit.truthy(on)
		if Kit.truthy(on) and s != null and g.get("fx") != null:
			g.fx.burst(s.global_position, {"count": 18, "shape": "star", "colors": ["#FFE45C", "#FFFFFF", "#FF8FB8"], "speed": 2.2, "size": 0.07, "life": 0.8, "gravity": 2})
	obj["reset"] = func():
		for k in keys:
			obj.setSlot.call(k, false)
		obj.setOpen.call(0, 0)
	rt.onTick(func(_t, dt, _vis):
		if state.dur > 0.0:
			state.t += dt
			var k := minf(1.0, state.t / state.dur)
			var e := 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0
			applyOpen.call(state.from + (state.to - state.from) * e)
			if k >= 1.0:
				state.dur = 0.0)
	rt.onReset(func(): obj.reset.call())
	rt.objects["ee_puppet_theater"] = obj
	out.merge(obj, true)
	# a soft pink pool on the story rug in front of the playhouse (after power) is added by buildLighting

# ============================================================================================ toys
func buildTrain(O: Dictionary) -> void:
	var g = game
	var a = Layout.ANCHORS.toy_train
	# Loop (x0.85) in the gap between the D6 rainbow, block 1, the rocket and the Wobble-Up sponsor camera (whose
	# footprint covers the GDD toy anchor): centre [18.95,-20.45], tunnel on the east side. The [E] point is the centre.
	var C := [18.95, 0, -20.45]
	var tg := Kit.place(g, rt.root, "toy_train_loop", {"area": AREA, "pos": C, "rotY": PI, "scale": 0.85})
	if tg == null:
		return
	var train: Node3D = Kit.partsOf(tg).get("train")
	var st := {"running": false, "t": 0.0, "dur": 0.0, "from": 0.0, "to": 0.0, "puff": 0.0}
	var obj := {"group": tg, "parts": {"train": train}, "running": false}
	obj["run"] = func(laps = 2) -> float:
		if st.running:
			return 0.0
		st.merge({"running": true, "t": 0.0, "dur": 1.6 * float(laps), "from": train.rotation.y, "to": train.rotation.y + float(laps) * TAU, "puff": 0.0}, true)
		obj.running = true
		return st.dur
	O["toy_train"] = obj
	rt.onTick(func(_t, dt, _vis):
		if not st.running:
			return
		st.t += dt
		var k := minf(1.0, st.t / st.dur)
		var ease := 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0   # pull away, cruise, brake
		train.rotation.y = st.from + (st.to - st.from) * ease
		st.puff -= dt
		if st.puff <= 0.0 and k < 0.95:
			st.puff = 0.22
			var chimney: Vector3 = train.global_transform * Vector3(1.1, 0.5, -0.14)
			if g.get("fx") != null:
				g.fx.burst(chimney, {"count": 2, "shape": "puff", "colors": ["#FFFFFF", "#EDE6FF"], "speed": 0.45, "size": 0.1, "life": 0.7, "gravity": -1.2, "drag": 3})
		if k >= 1.0:
			st.running = false
			obj.running = false
			train.rotation.y = fmod(st.to, TAU))
	rt.onReset(func():
		st.running = false
		obj.running = false
		train.rotation.y = 0.0)
	var I = g.get("interact")
	if I != null and I.has_method("register"):
		I.register({
			"id": "toy_train", "pos": [C[0], a.pos[1], C[2]], "radius": 1.6, "prompt": func() -> Dictionary: return {},
			"use": func() -> void:
				if float(obj.run.call(2)) != 0.0:
					sfx("toy_train", [C[0], 0.4, C[2]])
					if g.get("events") != null:
						g.events.emit("toy:use", {"id": "toy_train"}),
		})

const MIDI := [72, 74, 76, 77, 79, 81, 83, 84]      # bar 0 = longest (C5) ... bar 7 = shortest (C6)
const PENTA := [0, 1, 2, 4, 5, 7]                   # C D E G A C (the audio cue's pentatonic pool)

func buildXylophone(O: Dictionary) -> void:
	var g = game
	var a = Layout.ANCHORS.toy_xylophone
	var xg := Kit.place(g, rt.root, "xylophone", {"area": AREA, "pos": [a.pos[0], 0, a.pos[2]], "rotY": PI})
	if xg == null:
		return
	var bars: Node3D = Kit.partsOf(xg).get("bars")
	var mallets: Node3D = Kit.partsOf(xg).get("mallets")
	var barNodes: Array = []
	var base: Array = []
	if bars != null:
		var n := int(DAU.ud(bars).get("count", bars.get_child_count()))
		for i in n:
			var bn := Kit.instanceNode(bars, i)
			barNodes.append(bn)
			base.append(bn.transform if bn != null else Transform3D.IDENTITY)
	var hits: Array = []                                # { bar, t0 }
	var st := {"t": 0.0, "busy": 0.0, "mallet": 0.0}
	var obj := {"group": xg, "parts": {"bars": bars, "mallets": mallets}}
	obj["play"] = func(list = null) -> float:
		if st.busy > 0.0:
			return 0.0
		var notes: Array = list if list is Array else [PENTA[int(floor(randf() * PENTA.size()))], PENTA[int(floor(randf() * PENTA.size()))], PENTA[int(floor(randf() * PENTA.size()))]]
		for k in notes.size():
			hits.append({"bar": int(notes[k]), "t0": st.t + k * 0.18})
		st.busy = notes.size() * 0.18 + 0.35
		var midi: Array = []
		for b in notes:
			midi.append(MIDI[int(b)])
		sfx("toy_xylophone", [a.pos[0], 0.7, a.pos[2]], {"notes": midi})
		return st.busy
	O["toy_xylophone"] = obj
	rt.onTick(func(_t, dt, _vis):
		st.t += dt
		if st.busy > 0.0:
			st.busy -= dt
		if hits.is_empty():
			return
		var bump: Array = []
		bump.resize(16)
		bump.fill(0.0)
		var mal := 0.0
		for i in range(hits.size() - 1, -1, -1):
			var h: Dictionary = hits[i]
			var k: float = st.t - h.t0
			if k > -0.12 and k < 0.0:
				mal = maxf(mal, sin(((k + 0.12) / 0.12) * PI))
			if k < 0.0:
				continue
			if k > 0.5:
				hits.remove_at(i)
				continue
			bump[h.bar] = maxf(bump[h.bar], sin(minf(1.0, k / 0.5) * PI) * exp(-k * 5.0))
		for i in barNodes.size():
			if barNodes[i] != null:
				var tf: Transform3D = base[i]
				barNodes[i].transform = Transform3D(tf.basis, tf.origin + Vector3(0, -0.02 * float(bump[i]), 0))
		if mallets != null:
			mallets.position.y = 0.07 * mal
		if hits.is_empty():
			for i in barNodes.size():
				if barNodes[i] != null:
					barNodes[i].transform = base[i]
			if mallets != null:
				mallets.position.y = 0.0)
	var I = g.get("interact")
	if I != null and I.has_method("register"):
		I.register({
			"id": "toy_xylophone", "pos": [a.pos[0], a.pos[1], a.pos[2]], "radius": 1.4, "prompt": func() -> Dictionary: return {},
			"use": func() -> void:
				if float(obj.play.call()) != 0.0 and g.get("events") != null:
					g.events.emit("toy:use", {"id": "toy_xylophone"}),
		})

# ============================================================================================ fairy lights
func buildFairyLights(dyn: Node3D) -> void:
	# the green wire runs (static, merged by the level in the JS) + the two alternating bulb meshes
	var wire := _A("sb_fairy_wire")
	if wire != null:
		rt.root.add_child(wire)
	var mats: Array = []
	for i in 2:
		var mesh := _A("sb_fairy_%d" % i)
		if mesh == null:
			continue
		dyn.add_child(mesh)
		var m0 := Kit.getMat(mesh)
		var m: DAMaterial = (m0 as DAMaterial).clone() if m0 is DAMaterial else game.mats.basic("#ffffff", {"vertexColors": true}).clone()
		# JS: vertex colours = cols[n] x 2.2 (the glTF COLOR_0 is normalized: the x2.2 is the material intensity)
		m.setParam("uIntensity", 2.2)
		(mesh as MeshInstance3D).material_override = m
		mats.append(m)
	var lv := {"level": 0.55}
	rt.onPower([22, 4, -21], func(on, _instant = false): lv.level = 0.95 if on else 0.55)
	rt.onTick(func(t, _dt, vis):
		if not vis or mats.size() < 2:
			return
		var k1: float = lv.level * (0.78 + 0.22 * sin(t * 2.3))
		var k2: float = lv.level * (0.78 + 0.22 * sin(t * 2.3 + PI))
		mats[0].color = Color(k1, k1, k1).linear_to_srgb()
		mats[1].color = Color(k2, k2, k2).linear_to_srgb())

# ============================================================================================ mobiles
func buildMobiles(dyn: Node3D, tints: Dictionary) -> void:
	var at := [[17.55, GRID_Y, GZ[1]], [GX[3], GRID_Y + 0.09, -23.3], [GX[0], GRID_Y + 0.09, -20.1]]
	var list: Array = []
	for i in at.size():
		var m := _A("sb_mobile_%d" % i)
		if m == null:
			continue
		m.position = Vector3(at[i][0], at[i][1], at[i][2])
		dyn.add_child(m)
		_tint(m, "sb_glowcut", Color(0.95, 1.0, 1.15), tints)
		var spin: Node3D = m.find_child("sb_mobile_%d_spin" % i, true, false)
		if spin != null:
			spin.rotation_order = EULER_ORDER_XYZ
			list.append({"m": spin, "sp": 0.12 + i * 0.05, "ph": i * 1.3})
	rt.onTick(func(t, _dt, vis):
		if not vis:
			return
		for L in list:
			L.m.rotation = Vector3(L.m.rotation.x, L.ph + t * L.sp, sin(t * 0.6 + L.ph) * 0.02))

# ============================================================================================ lighting
func buildLighting(dyn: Node3D) -> void:
	var g = game
	# pre-power night-lights (GDD §3.3): the treehouse moon window + the paper-moon lantern, fairy glow
	rt.anchor("sb_moon", {"pos": [26.2, 3.6, -26.2], "color": "#BFD4FF", "intensity": 3.2, "distance": 9})
	rt.anchor("sb_lantern", {"pos": [17.55, 3.7, -24.2], "color": "#BFD4FF", "intensity": 2.0, "distance": 7.5})
	rt.anchor("sb_fairy", {"pos": [16.0, 3.3, -25.2], "color": "#FFB6C8", "intensity": 1.0, "distance": 5.5})
	var moonPool = rt.pool([26.0, 0.02, -25.3], 2.6, "#BFD4FF", 0.17)
	var lanternPool = rt.pool([17.6, 0.03, -24.2], 1.8, "#BFD4FF", 0.1)
	# post-power pastel fills (pink west, lilac east) + pastel pools
	rt.anchor("sb_fill_pink", {"pos": [18.4, 3.3, -21.2], "color": "#FFB6C8", "intensity": 0, "distance": 10})
	rt.anchor("sb_fill_lilac", {"pos": [25.8, 3.3, -20.8], "color": "#C9A7FF", "intensity": 0, "distance": 10})
	var pools := [
		rt.pool([17.75, 0.035, -24.6], 2.2, "#FF8FB8", 0),
		rt.pool([25.9, 0.02, -25.4], 2.3, "#C9A7FF", 0),
		rt.pool([19.3, 0.02, -18.4], 1.9, "#FFE45C", 0),
		rt.pool([26.0, 0.02, -17.6], 2.0, "#FF8FB8", 0),
		rt.pool([22.0, 0.02, -21.0], 2.6, "#FFF1C9", 0),
	]
	rt.onPower([22, 3, -21], func(on, _instant = false):
		rt.setAnchor("sb_moon", {"intensity": 1.0 if on else 3.2})
		rt.setAnchor("sb_lantern", {"intensity": 0.7 if on else 2.0})
		rt.setAnchor("sb_fairy", {"intensity": 0.5 if on else 1.0})
		rt.setAnchor("sb_fill_pink", {"intensity": 2.4 if on else 0.0})
		rt.setAnchor("sb_fill_lilac", {"intensity": 2.4 if on else 0.0})
		moonPool.set_({"intensity": 0.05 if on else 0.17})
		lanternPool.set_({"intensity": 0.03 if on else 0.1})
		var I := [0.15, 0.13, 0.12, 0.12, 0.06]
		for i in pools.size():
			pools[i].set_({"intensity": I[i] if on else 0.0}))

	# pastel gel Fresnels on the grid (lenses swap at power) + soft beams on the theater and Hootie's TV
	var lensGroup: Array = []
	var specs := [
		{"pos": [17.9, GZ[1]], "rotY": 0.0, "gel": "magenta", "tilt": 1.15, "beam": [17.75, 1.5, -25.6], "color": "#FF8FB8"},
		{"pos": [25.9, GZ[1]], "rotY": 0.0, "gel": "purple", "tilt": 0.85, "beam": [26.0, 1.1, -26.9], "color": "#C9A7FF"},
		{"pos": [19.6, GZ[3]], "rotY": PI, "gel": "yellow", "tilt": 1.0},
		{"pos": [24.6, GZ[3]], "rotY": PI, "gel": "magenta", "tilt": 0.95},
		{"pos": [GX[5], -25.0], "rotY": -HP, "gel": "cyan", "tilt": 1.15, "zpipe": true},
	]
	var lights: Array = []
	for s in specs:
		var f := Kit.place(g, rt.root, "bc_light_fresnel", {"area": AREA, "pos": [s.pos[0], 0, s.pos[1]], "rotY": s.rotY,
			"opts": {"gel": s.gel, "tilt": s.tilt, "lit": false}, "colliders": false})
		if f != null:
			f.position.y = (GRID_Y + 0.09 if s.get("zpipe") else GRID_Y) - float(DAU.ud(f).hang.pipeY)
			var lens = Kit.partsOf(f).get("lens")
			if lens != null:
				lensGroup.append(lens)
		lights.append(f)
	var lm = DAU.ud(lights[0]).get("lampMats") if lights[0] != null else null
	var lampOn: Material = Kit.udMat(g, lm.get("on")) if lm is Dictionary else null
	var lampOff: Material = Kit.udMat(g, lm.get("off")) if lm is Dictionary else null
	if lampOn != null and lampOff != null:
		rt.onPower([22, 5, -22], func(on, _instant = false):
			for l in lensGroup:
				Kit.setMat(l, lampOn if on else lampOff))
	var beamSrc := _A("sb_beam")
	var beams: Array = []
	for i in specs.size():
		var s: Dictionary = specs[i]
		if s.get("beam") == null or lights[i] == null or beamSrc == null:
			continue
		var f: Node3D = lights[i]
		var aim = DAU.ud(f).get("aim")
		var lens: Vector3 = f.global_transform * DAU.v3(aim.pos if aim is Dictionary and aim.get("pos") != null else [0, -0.36, -0.2])
		var tgt := DAU.v3(s.beam)
		var ln := lens.distance_to(tgt)
		var m: MeshInstance3D = beamSrc.duplicate()
		m.material_override = Kit.beamMaterial(s.color, 0.2)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 16384.0            # frustumCulled = false
		m.position = lens
		m.basis = Basis.looking_at(tgt - lens, Vector3.UP, true) * Basis.from_scale(Vector3(1, 1, ln))
		m.visible = false
		dyn.add_child(m)
		beams.append(m)
	if beamSrc != null:
		beamSrc.free()
	rt.onPower([22, 5, -24], func(on, _instant = false):
		for b in beams:
			b.visible = on)
