# Room dressing: MASTER CONTROL (GDD §5.7 "Master Control", §3.3 lighting, §10.0/§10.1 screens, §13 step 5 + toys,
# §18.13/§18.14 ids). Port of src/world/rooms/master_control.js. build(game, area, root) runs once from level.build()
# after the graybox. Uses the room toolkit of rooms/newsroom.gd (runtime: world tickers + power-wave switches; obj,
# place, pool, toy, setLamp, setClockHands ...).
#
# Layout (world metres; inner wall faces x 23.15 / 34.85, z -13.85 (north) / -2.15 (south); ceiling 3.6):
#   north wall  the 4 x 3 monitor wall x 28.2..34.6 (middle row scr_mc_feeds at eye level, top + bottom rows
#               scr_mc_canned; bottom corners are the screen spawns ss_mc_w / ss_mc_e), two tall patch-bay racks in the
#               NW corner, D7 kept clear
#   west wall   ee_rundown_board (6 slots) under a brass picture light, three patch bays + a WZTV clock at 11:59,
#               D5 kept clear
#   south wall  three quad VTRs (#1 and #3 spin their reels after power; ee_vtr2 with bare spindles, a blinking
#               amber lamp, the 13-detent ee_tracking_knob and its scr_vtr2 monitor) under a QUAD VTR BAY sign, the
#               quad-tape library shelf (one empty slot labelled SIGN OFF) under the master clock at 11:59 with a tape
#               cart beside it, the oscillating floor fan in the SE corner, B13 kept clear
#   east wall   TRANSMITTER remote meter panel, waveform/vectorscope cart, DANGER sign, fire extinguisher, the opened
#               Perpetua-Tube crate with the "NEVER SIGN OFF AGAIN!" ad taped above it (SE corner), DY kept clear
#   centre      the console island + Sign-On lever belong to signon.gd (left clear); flanking the lever sit the
#               Laff-O-Matic cart (toy_laff_o_matic) and the routing switcher cart (toy_switcher); rolling chairs;
#               dark anti-static floor mats (console, VTR aisle, monitor wall); overhead ladder cable trays with looms
#               into the racks, the wall, the console and the VTRs; floor cable runs, tape boxes, spilled coffee
#
# Power (GDD §3.3 / §10.1): before Sign-On the monitor wall glows faint static cyan and VTR #2's amber lamp blinks;
# as the colour wave passes: VTR #1/#3 lamps go green and their reels/VU needles run, the scopes light their green
# traces, the rack LED speckle starts blinking (one live-canvas mesh), the transmitter meters swing up, the fan
# spins, the rundown picture light and the wall's cyan wash come up. A new game with the power off reverts all.
#
# game.level.objects entries (world space):
#   mc_monitor_wall { group, screens:[12 meshes], byId:{ mcwall_r{row}c{col} | ss_mc_w | ss_mc_e -> mesh } }
#   ss_mc_w / ss_mc_e { group, screen }
#   ee_vtr2 { group, parts:{ spindleL, spindleR, lamp, trackingKnob, reelL, reelR, tape, monitor, needleL, needleR },
#             screen (scr_vtr2 CRT), loaded, lamp:'amber'|'green'|..., setLamp(color|'off', blink = color==='amber'),
#             loadTape(seconds = 1.5) (reels pop onto the spindles, tape threads, reels spin), unloadTape(),
#             spin(on), knobPos:Vector3 }
#   ee_tracking_knob { group (the knob part), parts:{ knob }, detents:13, detent, set(k, animate = true), turn(dir = 1)
#             -> detent, pos:Vector3 }
#   vtr_1 / vtr_3 { group, parts, spin(on) }
#   ee_rundown_board { group, parts:{ card_1..card_6 }, slots:[Vector3 x6], cards:[bool x6], setCard(n, on = true,
#             animate = true) }  (also automatic: egg:step {step} pins card <step>, egg:complete pins card 6; a new game
#             clears them)
#   perpetua_crate { group }   mc_clocks { parts:{ west, master } }   laff_o_matic { group, parts, play() }
#   mc_switcher { group, parts, play() }
# Toys (GDD §13, key-only [E]): toy_laff_o_matic ('toy_laff' from its speaker, 10 s cooldown: the big red button
#   squashes, the LAUGH / APPLAUSE lamps flash, the needle dances), toy_switcher ('toy_switcher': after power the
#   whole wall shows one indoor feed tiled 12x for 5 s via screens.override(feed_<area>, ['scr_mc_feeds',
#   'scr_mc_canned'], 5, 7.5); before power the wall blinks). Each emits 'toy:use' {id}.
#
# PORT NOTES (Godot)
# * The local builders of the JS (laffCart, routerCart, scopeCart, tapeShelf, cableTray, pictureLight, extinguisher,
#   floorFan, tapeCart, tapeStack, meterPanel) are Blender props (blender/props/rooms_newsroom_mc.py, ids mc_*, built
#   with game.props.build); `put` = game.props.place (same world colliders from the rotated local boxes). The meshes
#   the JS added straight under root (signs, the Perpetua ad + clips, decals, papers, the tipped mug, cable looms,
#   floor mats, the LED strip bars and LED mesh, VTR #2's tape bands, the monitor wall's dark steel material) are
#   blender/runtime/rooms_newsroom_mc.py -> res://assets/runtime/rooms_newsroom_mc/master_control.glb.
# * The live canvases (switcher key colours 64x64, LED speckle N x 1) are DACanvas textures set on a per-mesh clone
#   of their glow material (the GLB spec marks them "runtime").
# * mesh.material = m -> material_override. JS `this` in the object methods -> the captured Dictionary.
# * Renames (SPEC §3.2): hash -> hash_ (GDScript global); the objects' JS `set` is stored under "set" and "set_".
#   ensureColors (vertex colour fix for meshes outside K.finish) is done in Blender.
extends Node

const NR := preload("res://scripts/world/rooms/newsroom.gd")
const DRESSING := "res://assets/runtime/rooms_newsroom_mc/master_control.glb"
const TAU_ := PI * 2.0
const HP := PI / 2.0
const WALL := {"n": -13.85, "s": -2.15, "w": 23.15, "e": 34.85}
const DETENT := TAU_ / 13.0

var game
var rt = null
var _keep: Array = []   # canvases / state objects kept alive for the room's lifetime

static func hash_(n: float) -> float:
	var s := sin(n * 127.1 + 311.7) * 43758.5453
	return s - floorf(s)

static func v3(a) -> Vector3:
	return DAU.v3(a)

func _process(_delta: float) -> void:
	if rt != null and not rt._hooked:
		rt.frame()

# JS (1 + a * (k - 1)^3 + b * (k - 1)^2) overshoot ease
static func _back(k: float, a: float, b: float) -> float:
	return 1.0 + a * pow(k - 1.0, 3.0) + b * pow(k - 1.0, 2.0)

# Key colours: idle pattern (one lit per row, like a real router) or the chase (col/row sweep).
static func paintKeys(canvas, mode: String, t := 0.0, powered := true) -> void:
	if canvas == null:
		return
	var ctx = canvas.getContext("2d")
	var cols := ["#52E04A", "#FFB347", "#FF3B30", "#5FE3FF"]
	for r in 4:
		for c in 4:
			var on := false
			var col := "#4A4450"
			if mode == "chase":
				var k := int(floorf(t * 10.0)) % 16
				on = (r * 4 + c) == k or c == int(floorf(t * 4.0)) % 4
				col = cols[(r + int(floorf(t * 3.0))) % 4] if on else "#4A4450"
			elif powered:
				on = c == [1, 3, 0, 2][r]
				col = cols[r] if on else "#5A5462"
			ctx.fillStyle = col if on else ("#D8D0BC" if powered else "#8A8478")
			ctx.fillRect(c * 16, r * 16, 16, 16)

# Status LED strips (JS ledSpeckle, runtime half): the merged LED mesh is in the dressing asset ('mc_leds', UVs index
# a N x 1 canvas, 1 px per LED); the canvas is drawn here. Returns { mesh, tick(real, powered) }.
func _ledSpeckle(g, mesh, strips: Array) -> Dictionary:
	var N := 0
	for s in strips:
		N += int(s.n)
	var canvas := DACanvas.new(maxi(1, N), 1)
	_keep.append(canvas)
	if mesh != null:
		var m = NR.matOf(mesh)
		if m is DAMaterial:
			var c: DAMaterial = m.clone()
			c.mapFilter = "nearest"
			c.map = canvas.texture
			mesh.material_override = c
	var cols: Array = []
	var k := 0
	for s in strips:
		for i in int(s.n):
			cols.append(["#52E04A", "#FFB347", "#52E04A", "#FF3B30", "#5FE3FF", "#52E04A", "#FFB347"][k % 7])
			k += 1
	var state: Array = []
	for i in cols.size():
		state.append({"on": hash_(i) > 0.4, "rate": 0.6 + hash_(i * 3.7) * 3.5, "t": hash_(i * 1.3)})
	var st := {"acc": 1.0, "wasOn": null}
	var paint := func(powered: bool) -> void:
		var ctx = canvas.getContext("2d")
		for i in state.size():
			ctx.fillStyle = cols[i] if (powered and state[i].on) else "#3A3440"
			ctx.fillRect(i, 0, 1, 1)
	paint.call(false)
	return {
		"mesh": mesh,
		"tick": func(real: float, powered: bool) -> void:
			st.acc += real
			if not powered:
				if st.wasOn != false:
					st.wasOn = false
					paint.call(false)
				return
			if st.acc < 0.1 and st.wasOn == true:
				return
			for s in state:
				s.t += st.acc * s.rate
				if s.t >= 1.0:
					s.t -= floorf(s.t)
					s.on = (not s.on) or hash_(s.rate * 10.0 + s.t) > 0.7
			st.acc = 0.0
			st.wasOn = true
			paint.call(true),
	}

func build(g, area: Dictionary, root: Node3D):
	game = g
	var aid: String = area.id
	rt = NR.runtime(g, aid)
	var PAL: Dictionary = Config.PAL
	var ANCHORS: Dictionary = Layout.ANCHORS
	var lvl = g.level
	var L = g.lights
	var P := func(id: String, pos, rotY := 0.0, opts: Dictionary = {}, extra: Dictionary = {}) -> Node3D:
		var e := {"area": aid}
		e.merge(extra, true)
		return NR.place(g, root, id, pos, rotY, opts, e)
	# JS put(group, pos, rotY, colliders): the local builders are Blender props (ids mc_*): placed with their world
	# colliders (AABBs of the rotated local boxes, tag 'prop'), no area light anchors.
	var put := func(id: String, opts: Dictionary, pos, rotY := 0.0, colliders := true) -> Node3D:
		return NR.place(g, root, id, pos, rotY, opts, {"colliders": colliders, "lights": false, "screens": false})
	var anchor := func(id: String, pos, color: String, intensity: float, distance: float) -> void:
		if L != null and L.has_method("addAnchor"):
			L.addAnchor({"id": id, "pos": pos, "color": color, "intensity": intensity, "distance": distance, "area": aid})
	var setA := func(id: String, intensity: float) -> void:
		if L != null and L.has_method("setAnchor"):
			L.setAnchor(id, {"intensity": intensity})
	var powered := func() -> bool:
		return g.machines != null and bool(g.machines.powerOn)
	var ev = g.events
	var dr := NR.dressing(g, root, DRESSING)

	# ------------------------------------------------------------------------------------ the 4 x 3 monitor wall
	var wall: Node3D = P.call("bc_monitor_wall", [31.4, 0, WALL.n + 0.26], PI, {}, {"screens": false})
	var byId := {}
	if wall != null:
		# bright brushed aluminium (K.tex.brushed('#C4CAD2')) -> the darker steel (brushed '#707B8E', env 0.22, rim 0.16)
		var steelNode = NR.node(dr, "mc_wall_steel")
		var steel = NR.matOf(steelNode)
		if steel != null:
			DAU.traverse(wall, func(o):
				if not (o is MeshInstance3D) or o.mesh == null:
					return
				for si in o.mesh.get_surface_count():
					var m = o.get_active_material(si)
					if m is DAMaterial and m.kind == "toon" and m.map != null and m.map.resource_path.contains("brushed_C4CAD2"):
						o.set_surface_override_material(si, steel))
		var wscr: Array = DAU.ud(wall).get("screens", [])
		for s in wscr:
			var mesh = s.get("mesh")
			var id0 = s.get("id")
			if not id0 and mesh != null:
				id0 = DAU.ud(mesh).get("screenId", "")
			if id0 == null:
				id0 = ""
			var id: String = "ss_mc_w" if id0 == "mcwall_r2c0" else ("ss_mc_e" if id0 == "mcwall_r2c3" else str(id0)) # the prop already names them
			byId[id] = mesh
			if g.screens != null and g.screens.has_method("register"):
				g.screens.register(mesh, s.get("group") if s.get("group") else "scr_mc_canned", {"id": id} if id != "" else {})
		NR.obj(g, "mc_monitor_wall", {"area": aid, "group": wall, "screens": wscr.map(func(s): return s.get("mesh")), "byId": byId})
		NR.obj(g, "ss_mc_w", {"area": aid, "group": wall, "screen": byId.get("ss_mc_w")})
		NR.obj(g, "ss_mc_e", {"area": aid, "group": wall, "screen": byId.get("ss_mc_e")})
	anchor.call("mc_wall_glow", [31.4, 1.8, -12.1], "#9FDCFF", 1.5, 6.5)
	var wallPool = NR.pool(g, [31.4, 0.02, -12.3], 3.0, "#9FDCFF", 0.14)
	rt.power([31.4, 1.8, -13.2], func(on):
		setA.call("mc_wall_glow", 2.6 if on else 1.5)
		wallPool.set_({"intensity": 0.2 if on else 0.14}), {"flicker": false})
	# producer's chair parked in front of the wall + the floor cable run to it
	P.call("chair_office", [32.3, 0, -11.35], 2.75, {"color": PAL.burntOrange})
	P.call("bc_cable_spaghetti", [30.2, 0, -12.35], 0.05, {"w": 3.2, "d": 0.7, "count": 5, "seed": 13})

	# ------------------------------------------------------------------------------------ NW corner racks
	P.call("bc_patch_bay", [23.64, 0, WALL.n + 0.35], PI, {"seed": 21, "cords": 7, "color": "slate"})
	P.call("bc_patch_bay", [24.28, 0, WALL.n + 0.35], PI, {"seed": 5, "cords": 5})

	# ------------------------------------------------------------------------------------ west wall: rundown board
	var rb: Node3D = P.call("rundown_board", [WALL.w + 0.03, 0.1, -11.0], -HP)
	if rb != null:
		var parts: Dictionary = DAU.ud(rb).get("parts", {})
		for k in parts:
			if parts[k] != null:
				DAU.ud(parts[k])["noMerge"] = true
		var slots: Array = []
		var an = DAU.ud(rb).get("anchors")
		for s in (an.get("slots", []) if an is Dictionary else []):
			slots.append(rb.to_global(v3(s)))
		var pops: Array = []
		var board := {"area": aid, "group": rb, "parts": parts.duplicate(), "slots": slots, "cards": [false, false, false, false, false, false]}
		board["setCard"] = func(n, on = true, animate = true) -> void:
			var i: int = int(n) - 1
			if i < 0 or i > 5 or board.cards[i] == bool(on):
				return
			board.cards[i] = bool(on)
			# props/sets.js setRundownCard(prop, n, on)
			var cp = parts.get("card_%d" % int(n))
			if cp != null:
				cp.visible = bool(on)
			var c = parts.get("card_%d" % int(n))
			if c == null:
				return
			if on and animate:
				pops.append({"c": c, "t": 0.0})
				c.scale = Vector3.ONE * 0.01
				if i < slots.size() and g.fx != null and g.fx.has_method("burst"):
					g.fx.burst(slots[i], {"shape": "star", "count": 8, "speed": 1.6, "size": 0.06, "colors": ["#FFC23A", "#FFE3A3", "#FFFFFF"], "life": 0.8})
			else:
				c.scale = Vector3.ONE
		NR.obj(g, "ee_rundown_board", board)
		rt.tick(func(_dt, _t, real):
			for i in range(pops.size() - 1, -1, -1):
				var p: Dictionary = pops[i]
				p.t += real
				var k: float = minf(1.0, p.t / 0.45)
				var e := _back(k, 2.4, 1.4)
				p.c.scale = Vector3.ONE * maxf(0.01, e)
				p.c.rotation.z = sin(p.t * 20.0) * 0.1 * (1.0 - k)
				if k >= 1.0:
					p.c.scale = Vector3.ONE
					pops.remove_at(i))
		if ev != null:
			ev.on("egg:step", func(pl = null):
				var step: int = int(pl.get("step", 0)) if pl is Dictionary and pl.get("step") != null else 0
				for n in range(1, mini(6, step) + 1):
					board.setCard.call(n, true, n == step))
			ev.on("egg:complete", func(_pl = null): board.setCard.call(6, true))
			ev.on("game:start", func(_pl = null):
				for n in range(1, 7):
					board.setCard.call(n, false, false))
	var pl: Node3D = put.call("mc_picture_light", {}, [WALL.w, 2.47, -11.0], -HP, false)
	var plGlow = DAU.ud(pl).parts.get("glow") if pl != null else null
	var plOn = g.mats.glow("#FFE6B0", 2.2) if g.mats != null else null
	var plOff = NR.matOf(plGlow)
	anchor.call("mc_rundown_light", [23.9, 2.2, -11.0], "#FFE0A8", 0.0, 3.8)
	var rbPool = NR.pool(g, [23.9, 0.02, -11.0], 1.2, "#FFE0A8", 0.0)
	rt.power([23.4, 2.4, -11.0], func(on):
		if plGlow != null:
			plGlow.material_override = plOn if on else plOff
		setA.call("mc_rundown_light", 1.6 if on else 0.0)
		rbPool.set_({"intensity": 0.14 if on else 0.0}))

	# ------------------------------------------------------------------------------------ west wall: patch bays
	var bays := [[-9.3, 4, "#3B3645"], [-8.66, 9, "charcoal"], [-8.02, 17, "slate"]]
	for i in bays.size():
		var b: Array = bays[i]
		P.call("bc_patch_bay", [WALL.w + 0.35, 0, b[0]], -HP, {"seed": b[1], "cords": 6 + i, "color": "charcoal" if i == 0 else b[2]})
	var wclock: Node3D = P.call("clock_wall", [WALL.w, 2.22, -8.66], -HP, {"label": "WZTV", "size": 0.4}, {"colliders": false})
	# (NO SMOKING sign: dressing asset)

	# ------------------------------------------------------------------------------------ south wall: quad VTRs
	var vz: float = WALL.s - 0.43
	var vtr := {}
	for e in [[25.25, 1], [26.75, 2], [28.25, 3]]:
		var n: int = e[1]
		var ee := n == 2
		var vopts := {"num": 2, "reels": false, "lamp": "amber", "group": "scr_vtr2", "id": "ee_vtr2_monitor", "track": 3} if ee \
			else {"num": n, "lamp": "off", "reels": true, "group": "scr_decor", "id": "vtr%d_monitor" % n, "rec": n == 3}
		var vg: Node3D = P.call("bc_vtr_quad", [e[0], 0, vz], 0.0, vopts)
		if vg != null:
			vtr[n] = vg
	# (QUAD VTR BAY sign + backing: dressing asset)
	put.call("mc_tape_stack", {"n": 4, "seed": 2}, [24.1, 0, -2.45], 0.3)
	put.call("mc_tape_stack", {"n": 2, "seed": 5}, [28.95, 0, -3.35], -0.4)
	# VTR #1 / #3: lamps go green, reels spin and VU needles bounce after power
	for n in [1, 3]:
		var vg = vtr.get(n)
		if vg == null:
			continue
		var p: Dictionary = DAU.ud(vg).parts
		for k in ["spindleL", "spindleR", "trackingKnob"]:
			if p.get(k) != null:
				DAU.ud(p[k])["noMerge"] = false
		var st := {"spin": false, "w": 0.0}
		var o := {"area": aid, "group": vg, "parts": p.duplicate(), "spin": func(on): st.spin = bool(on)}
		NR.obj(g, "vtr_%d" % n, o)
		rt.power([vg.position.x, 1.9, vg.position.z], func(on):
			NR.setLamp(vg, "green" if on else "off")
			o.spin.call(on))
		var nl0: float = p.needleL.rotation.z if p.get("needleL") != null else 0.0
		var nr0: float = p.needleR.rotation.z if p.get("needleR") != null else 0.0
		var nn := float(n)
		rt.tick(func(dt, t, _real):
			st.w += ((3.2 if st.spin else 0.0) - st.w) * minf(1.0, dt * 1.5)
			if st.w < 1e-3:
				return
			if p.get("reelL") != null:
				p.reelL.rotation.z -= st.w * dt * (1.0 if n == 1 else 0.8)
			if p.get("reelR") != null:
				p.reelR.rotation.z -= st.w * dt * (1.35 if n == 1 else 1.1)
			var k: float = st.w / 3.2
			if p.get("needleL") != null:
				p.needleL.rotation.z = nl0 + (sin(t * 7.1 + nn) * 0.25 + sin(t * 17.3) * 0.1) * k
			if p.get("needleR") != null:
				p.needleR.rotation.z = nr0 + (sin(t * 6.3 + nn * 2.0) * 0.25 + sin(t * 13.7) * 0.12) * k)
	# VTR #2 (EE step 5): bare spindles, blinking amber lamp, TRACKING knob, loadable reels
	var v2 = vtr.get(2)
	if v2 != null:
		var p: Dictionary = DAU.ud(v2).parts
		for k in ["spindleL", "spindleR", "trackingKnob", "lamp"]:
			if p.get(k) != null:
				DAU.ud(p[k])["noMerge"] = true
		for k in ["needleL", "needleR"]:
			if p.get(k) != null:
				DAU.ud(p[k])["noMerge"] = false
		# reels to mount later: copies of VTR #1's (hidden), plus the threaded tape bands
		var src = DAU.ud(vtr[1]).parts if vtr.has(1) else null
		var mk := func(r, x: float, z0: float) -> Node3D:
			var c: Node3D
			if r != null and g.props != null and g.props.has_method("cloneProp"):
				c = g.props.cloneProp(r)
			elif r != null:
				c = r.duplicate()
			else:
				c = DAU.node3d("reel")
			c.position = Vector3(x, 1.3, -0.5)
			c.rotation.z = z0
			c.visible = false
			DAU.ud(c)["noMerge"] = true
			v2.add_child(c)
			return c
		var reelL: Node3D = mk.call(src.get("reelL") if src != null else null, -0.3, 0.2)
		var reelR: Node3D = mk.call(src.get("reelR") if src != null else null, 0.3, 1.1)
		var tape = NR.node(dr, "mc_vtr2_tape")
		if tape != null:
			tape.get_parent().remove_child(tape)
			v2.add_child(tape)   # VTR-local coordinates (built at the dressing origin)
			tape.visible = false
			DAU.ud(tape)["noMerge"] = true
		else:
			tape = DAU.node3d("mc_vtr2_tape")
			tape.visible = false
			v2.add_child(tape)
		var knob = p.get("trackingKnob")
		var kst := {"detent": 3, "from": 0.0, "to": 0.0, "t": 1.0}
		if knob != null:
			kst.from = knob.rotation.y
			kst.to = knob.rotation.y
		var knobPos: Vector3 = knob.global_position if knob != null and knob.is_inside_tree() else v3(ANCHORS.ee_tracking_knob.pos)
		var lampSt := {"color": "amber", "blink": true, "on": true, "t": 0.0}
		var reelSt := {"spin": false, "w": 0.0, "load": -1.0, "dur": 1.5}
		anchor.call("mc_vtr2_lamp", [26.75 + 0.42, 2.15, vz - 0.35], "#FFB347", 0.9, 3.2)
		var vscr: Array = DAU.ud(v2).get("screens", [])
		var vmon = vscr[0].get("mesh") if vscr.size() > 0 else null
		var vparts := p.duplicate()
		vparts.merge({"reelL": reelL, "reelR": reelR, "tape": tape, "monitor": vmon}, true)
		var vtrObj := {"area": aid, "group": v2, "screen": vmon, "loaded": false, "knobPos": knobPos, "parts": vparts, "lampColor": "amber"}
		vtrObj["setLamp"] = func(color, blink = null) -> void:
			var col := str(color)
			var bl: bool = (col == "amber") if blink == null else bool(blink)
			vtrObj.lampColor = col
			lampSt.color = col
			lampSt.blink = bl and col != "off"
			lampSt.t = 0.0
			lampSt.on = col != "off"
			NR.setLamp(v2, "off" if col == "off" else col)
			setA.call("mc_vtr2_lamp", 0.0 if col == "off" else 0.9)
			var c = {"amber": "#FFB347", "green": "#52E04A", "red": "#FF3B30", "purple": "#B070FF"}.get(col)
			if c != null and L != null and L.has_method("setAnchor"):
				L.setAnchor("mc_vtr2_lamp", {"color": c})
		vtrObj["loadTape"] = func(seconds = 1.5) -> void:
			if vtrObj.loaded:
				return
			vtrObj.loaded = true
			reelSt.load = 0.0
			reelSt.dur = maxf(0.2, float(seconds))
			reelL.visible = true
			reelR.visible = true
			reelL.scale = Vector3.ONE * 0.01
			reelR.scale = Vector3.ONE * 0.01
			for s in [p.get("spindleL"), p.get("spindleR")]:
				if s != null:
					s.scale = Vector3.ONE
		vtrObj["unloadTape"] = func() -> void:
			vtrObj.loaded = false
			reelSt.load = -1.0
			reelSt.spin = false
			reelSt.w = 0.0
			reelL.visible = false
			reelR.visible = false
			tape.visible = false
			for s in [p.get("spindleL"), p.get("spindleR")]:
				if s != null:
					s.scale = Vector3.ONE * 1.5
		vtrObj["spin"] = func(on) -> void:
			reelSt.spin = bool(on)
		NR.obj(g, "ee_vtr2", vtrObj)
		var knobObj := {"area": aid, "group": knob, "parts": {"knob": knob}, "detents": 13, "pos": knobPos, "detent": 3}
		var kset := func(k, animate = true) -> int:
			var n: int = posmod(int(floorf(float(k) + 0.5)) % 13 + 13, 13)
			var cur: float = knob.rotation.y if knob != null else 0.0
			var target: float = -n * DETENT
			while target - cur > PI:
				target -= TAU_
			while cur - target > PI:
				target += TAU_
			kst.detent = n
			knobObj.detent = n
			kst.from = cur
			kst.to = target
			kst.t = 0.0 if animate else 1.0
			if not animate and knob != null:
				knob.rotation.y = target
			return n
		knobObj["set"] = kset
		knobObj["set_"] = kset
		knobObj["turn"] = func(dir = 1) -> int:
			return kset.call(int(kst.detent) + (-1 if float(dir) < 0 else 1))
		NR.obj(g, "ee_tracking_knob", knobObj)
		kset.call(3, false)
		rt.tick(func(dt, _t, real):
			# amber lamp blink (1 Hz, all game) — lamp part + its pooled light
			if lampSt.blink:
				lampSt.t += real
				var on: bool = fmod(lampSt.t, 1.0) < 0.55
				if on != lampSt.on:
					lampSt.on = on
					NR.setLamp(v2, lampSt.color if on else "off")
					setA.call("mc_vtr2_lamp", 0.9 if on else 0.05)
			# knob detent click (overshoot ease)
			if kst.t < 1.0 and knob != null:
				kst.t = minf(1.0, kst.t + real / 0.16)
				var e := _back(kst.t, 2.6, 1.6)
				knob.rotation.y = kst.from + (kst.to - kst.from) * e
			# tape load: reels pop on (bounce), tape threads at 60 %, then they spin
			if reelSt.load >= 0.0:
				reelSt.load += real
				var k: float = minf(1.0, reelSt.load / reelSt.dur)
				var a: float = minf(1.0, k / 0.45)
				var e2 := _back(a, 2.2, 1.2)
				reelL.scale = Vector3.ONE * maxf(0.01, e2)
				var kr: float = (k - 0.15) / 0.45
				var er: float = _back(minf(1.0, kr), 2.2, 1.2) if kr > 0.0 else 0.01
				reelR.scale = Vector3.ONE * maxf(0.01, minf(1.2, er))
				if k > 0.6:
					tape.visible = true
				if k >= 1.0:
					reelSt.load = -1.0
					reelL.scale = Vector3.ONE
					reelR.scale = Vector3.ONE
					reelSt.spin = true
			reelSt.w += ((2.6 if reelSt.spin else 0.0) - reelSt.w) * minf(1.0, dt * 2.0)
			if reelSt.w > 1e-3:
				reelL.rotation.z -= reelSt.w * dt
				reelR.rotation.z -= reelSt.w * dt * 1.25)
		if ev != null:
			ev.on("game:start", func(_pl = null):
				vtrObj.unloadTape.call()
				vtrObj.setLamp.call("amber", true)
				kset.call(3, false))
		vtrObj.setLamp.call("amber", true)

	# ------------------------------------------------------------------------------------ south wall: tape library
	put.call("mc_tape_shelf", {}, [30.1, 0, WALL.s - 0.22], 0.0)
	var mclock: Node3D = P.call("clock_wall", [30.1, 2.52, WALL.s], 0.0, {"size": 0.5, "bezel": "#2A2231"}, {"colliders": false})
	var clocks := {"west": DAU.ud(wclock).parts if wclock != null else null, "master": DAU.ud(mclock).parts if mclock != null else null}
	for c in [wclock, mclock]:
		if c == null:
			continue
		for k in ["hour", "minute", "second"]:
			var hp = DAU.ud(c).parts.get(k)
			if hp != null:
				DAU.ud(hp)["noMerge"] = k == "second"
	var setClocks := func(h, m, s = 0) -> void:
		for k in clocks:
			NR.setClockHands(clocks[k], h, m, s)
	NR.obj(g, "mc_clocks", {"area": aid, "parts": clocks, "set": setClocks, "set_": setClocks})
	rt.tick(func(_dt, _t, _real):
		var ph: float = fmod(float(g.time.realNow) if g.time != null else 0.0, 1.6)
		var s: float = 58.0 + minf(1.0, ph / 0.06) if ph < 0.8 else 59.0 - minf(1.0, (ph - 0.8) / 0.08)
		for k in clocks:
			var cp = clocks[k]
			if cp != null and cp.get("second") != null:
				cp.second.rotation.z = (s / 60.0) * TAU_)

	# ------------------------------------------------------------------------------------ east wall: scopes, crate
	var scopes: Node3D = put.call("mc_scope_cart", {}, [WALL.e - 0.3, 0, -10.55], HP)
	if scopes != null:
		var su := DAU.ud(scopes)
		rt.power([34.3, 1.0, -10.55], func(on):
			su.parts.faces.material_override = NR.lampMat(g, su.lampMats, "on" if on else "off"))
	var scopePool = NR.pool(g, [33.9, 0.02, -10.55], 1.0, "#7CFF9A", 0.0)
	rt.power([34.3, 1.0, -10.6], func(on): scopePool.set_({"intensity": 0.1 if on else 0.0}), {"flicker": false})
	# (DANGER ENGINEERING sign: dressing asset)
	put.call("mc_extinguisher", {}, [WALL.e, 0.0, -5.95], HP)
	var crate: Node3D = P.call("perpetua_crate", [33.78, 0, -4.1], -HP)
	NR.obj(g, "perpetua_crate", {"area": aid, "group": crate})
	# (the "NEVER SIGN OFF AGAIN!" ad (card perpetua_ad), its tape clips and the floor copy: dressing asset)

	# ------------------------------------------------------------------------------------ centre: toys + chairs
	var laffPos: Array = ANCHORS.toy_laff_o_matic.pos
	var swPos: Array = ANCHORS.toy_switcher.pos
	var laff: Node3D = put.call("mc_laff_o_matic", {}, [float(laffPos[0]) + 0.1, 0, float(laffPos[2]) - 0.02], PI - 0.08)
	var sw: Node3D = put.call("mc_switcher", {}, [float(swPos[0]) - 0.05, 0, float(swPos[2]) - 0.02], PI + 0.08)
	P.call("chair_office", [27.1, 0, -7.35], 0.6, {"color": PAL.harvestGold})
	P.call("chair_office", [31.15, 0, -7.3], -0.45, {"color": PAL.burntOrange})
	# (spilled coffee, tipped mug, papers, scuff + tape-X decals: dressing asset)

	# ------------------------------------------------------------------------------------ overhead cable trays
	var ceil: float = float(area.get("ceilY")) if area.get("ceilY") != null else 3.6
	var trayY := ceil - 0.36
	put.call("mc_cable_tray", {"L": 11.2, "rod": 0.36}, [29.0, trayY, -11.2], 0.0, false)
	put.call("mc_cable_tray", {"L": 7.2, "rod": 0.36}, [23.75, trayY, -9.9], HP, false)
	# (cable looms from the trays: dressing asset)

	# ------------------------------------------------------------------------------------------------ toys
	if laff != null:
		var lu := DAU.ud(laff)
		var LM: Dictionary = lu.lampMats
		var lp: Dictionary = lu.parts
		var lst := {"t": -1.0, "next": 0.0}
		var laffPlay := func() -> void:
			var now: float = float(g.time.realNow) if g.time != null else 0.0
			if now < lst.next:
				return
			lst.next = now + 10.0
			lst.t = 0.0
			if g.audio != null:
				g.audio.play("toy_laff", {"pos": v3(laffPos), "tv": true})
			if ev != null:
				ev.emit("toy:use", {"id": "toy_laff_o_matic"})
		NR.toy(g, "toy_laff_o_matic", laffPos, laffPlay, {"radius": 1.4, "cooldown": 0.3})
		NR.obj(g, "laff_o_matic", {"area": aid, "group": laff, "parts": lp.duplicate(), "play": laffPlay})
		var n0: float = lp.needle.rotation.z
		var b0: float = lp.button.position.y
		rt.tick(func(_dt, _t, real):
			if lst.t < 0.0:
				return
			lst.t += real
			var k: float = lst.t
			var press: float = k / 0.08 if k < 0.08 else maxf(0.0, 1.0 - (k - 0.08) / 0.12)
			lp.button.position.y = b0 - press * 0.022
			lp.button.scale = Vector3(1.0 + press * 0.12, 1.0 - press * 0.3, 1.0 + press * 0.12)
			var on: bool = k < 2.6
			var f := int(floorf(k * 6.0))
			lp.lampL.material_override = NR.lampMat(g, LM, "on" if (on and f % 2 == 0) else "off")
			lp.lampR.material_override = NR.lampMat(g, LM, "onR" if (on and f % 2 == 1) else "offR")
			lp.needle.rotation.z = n0 - 0.6 - absf(sin(k * 11.0)) * 0.5 - sin(k * 23.0) * 0.15 if on else n0
			if not on and k > 2.7:
				lst.t = -1.0
				lp.button.position.y = b0
				lp.button.scale = Vector3.ONE)
		if ev != null:
			ev.on("game:start", func(_pl = null): lst.next = 0.0)

	if sw != null:
		var su := DAU.ud(sw)
		# the live 64 x 64 key canvas (JS document.createElement('canvas') + CanvasTexture, nearest filtering)
		var kc := DACanvas.new(64, 64)
		_keep.append(kc)
		su["keyCanvas"] = kc
		su["keyTex"] = kc.texture
		var keys = su.parts.get("keys")
		var km = NR.matOf(keys)
		if km is DAMaterial:
			var c: DAMaterial = km.clone()
			c.mapFilter = "nearest"
			c.map = kc.texture
			keys.material_override = c
		var sst := {"t": -1.0, "handle": null, "keyT": 0.0}
		paintKeys(kc, "idle", 0.0, false)
		rt.power([28.0, 1.0, -8.3], func(on):
			if sst.t < 0.0:
				paintKeys(kc, "idle", 0.0, on), {"flicker": false})
		var swPlay := func() -> void:
			sst.t = 0.0
			if g.audio != null:
				g.audio.play("toy_switcher", {"pos": v3(swPos)})
			var S = g.screens
			if S != null and powered.call():
				var feeds := ["lobby", "newsroom", "studio_a", "studio_b"]
				var a = S.get("_aArea")
				var pick := feeds.filter(func(f): return f != a)
				var f: String = pick[int(floorf(randf() * pick.size()))] if pick.size() > 0 else "lobby"
				if sst.handle != null and sst.handle.has_method("cancel"):
					sst.handle.cancel()
				sst.handle = S.override("feed_%s" % f, ["scr_mc_feeds", "scr_mc_canned"], 5, 7.5) if S.has_method("override") else null
			elif S != null and S.has_method("blink"):
				S.blink(["scr_mc_feeds", "scr_mc_canned"], {"spread": 0.4, "dur": 0.25})
			if ev != null:
				ev.emit("toy:use", {"id": "toy_switcher"})
		NR.toy(g, "toy_switcher", swPos, swPlay, {"radius": 1.4, "cooldown": 0.5})
		NR.obj(g, "mc_switcher", {"area": aid, "group": sw, "parts": (su.parts as Dictionary).duplicate(), "play": swPlay})
		rt.tick(func(_dt, _t, real):
			if sst.t < 0.0:
				return
			sst.t += real
			sst.keyT += real
			if sst.keyT > 0.08:
				sst.keyT = 0.0
				paintKeys(kc, "chase", sst.t, true)
			if sst.t > 5.0:
				sst.t = -1.0
				paintKeys(kc, "idle", 0.0, powered.call()))
		if ev != null:
			ev.on("game:start", func(_pl = null):
				if sst.handle != null and sst.handle.has_method("cancel"):
					sst.handle.cancel()
				sst.handle = null
				sst.t = -1.0)

	# ------------------------------------------------------------------------------------ floor mats + meter panel
	# (the three anti-static floor mats: dressing asset)
	var mp: Node3D = put.call("mc_meter_panel", {}, [WALL.e, 1.55, -12.35], HP, false)
	if mp != null:
		var mu := DAU.ud(mp)
		var mpn: Array = mu.parts.needles
		var mst := {"on": false, "k": 0.0}
		rt.power([34.8, 1.9, -12.35], func(on):
			mst.on = on
			mu.parts.lamps.material_override = NR.lampMat(g, mu.lampMats, "on" if on else "off"))
		rt.tick(func(dt, t, _real):
			mst.k += ((1.0 if mst.on else 0.0) - mst.k) * minf(1.0, dt * 1.2)
			for i in mpn.size():
				mpn[i].rotation.z = 1.05 - mst.k * (1.2 + i * 0.25) - (sin(t * (2.0 + i) + i) * 0.04 if mst.k > 0.5 else 0.0))

	# a tape cart parked by the library shelf + the oscillating floor fan in the SE corner (runs after power)
	put.call("mc_tape_cart", {}, [30.35, 0, -3.5], 0.08)
	var fan: Node3D = put.call("mc_floor_fan", {}, [33.2, 0, -2.58], PI / 4.0)
	if fan != null:
		var fp: Dictionary = DAU.ud(fan).parts
		var fst := {"on": false, "w": 0.0}
		rt.power([33.2, 1.1, -2.6], func(on): fst.on = on, {"flicker": false})
		rt.tick(func(dt, t, _real):
			fst.w += ((14.0 if fst.on else 0.0) - fst.w) * minf(1.0, dt * 0.8)
			if fst.w < 0.01:
				return
			fp.blades.rotation.z -= fst.w * dt
			fp.head.rotation.y = sin(t * 0.35) * 0.6 * minf(1.0, fst.w / 14.0))

	# status LED speckle on the racks + scope cart (blinks after power)
	var strips: Array = [
		{"pos": [23.64, 2.02, WALL.n + 0.6], "rot": PI, "len": 0.56, "n": 8},
		{"pos": [24.28, 2.02, WALL.n + 0.6], "rot": PI, "len": 0.56, "n": 8},
	]
	for z in [-9.3, -8.66, -8.02]:
		strips.append({"pos": [WALL.w + 0.6, 2.02, z], "rot": -HP, "len": 0.56, "n": 8})
	strips.append({"pos": [WALL.e - 0.42, 1.1, -10.55], "rot": HP, "len": 0.5, "n": 6})
	var leds := _ledSpeckle(g, NR.node(dr, "mc_leds"), strips)
	rt.tick(func(_dt, _t, real): leds.tick.call(real, powered.call()))
	return rt
