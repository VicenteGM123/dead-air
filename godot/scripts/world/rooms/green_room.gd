# Room dressing: GREEN ROOM HALL (port of src/world/rooms/green_room.js; GDD §5.7 "Green Room", §3.3 lighting, §2
# story props, §13 toys, §18.13 ids). build(game, area, root) runs once from level.build() after the graybox;
# animated / switchable parts are flagged noMerge. Uses the room kit of lobby.gd (roomKit: colliders, power-wave
# switches, frame hook) and a few local builders (ids gm_*), which are Blender assets here.
#
# Layout (world metres; inner wall faces x -6.85 / 16.85, z -11.85 (north) / -6.15 (south); ceiling 3.5):
#   west end   cigarette + Fizz-Up vending machines (north wall x -6.8..-4.9), trash can, lava lamp on a drum table
#              (toy_lava_lamp), coat rail + plant hanger (west wall), rotary payphone with a hanging phone book and
#              a stool (toy_payphone, west wall z -7.5), moonlight slats through the boarded B6 window
#   south wall five dressing-room doors x -6.8..-1.8 (Baron / Penny / Roxy / Skip / Duke; the Baron's has the
#              porthole and leaks a purple Channel-0 glow under it) under a backstage clock at 11:59; EXIT boxes over
#              D2 / D3; the Hollywood vanity x 2.9..7.7 (4.8 m, clear of D2's swinging east leaf)
#              (3 bulb-ringed mirrors, wig head + afro, cucumber plate, make-up kit, boa) with Duke's reclining
#              make-up chair and two director's chairs; call board + ash urn + fern east of D3
#   north wall ss_green built-in wall TV at [-0.8, 1.2] (screen spawn), garment rack of costumes + steamer trunk
#              with the Hootie costume head beside D4, QUIET PLEASE sign, water cooler + Hootie poster, hi-fi
#              console behind the T1 couch; framed test card above the Telly home (east wall)
#   kept clear Tube-O-Matic (wb_grenades, economy), Jump Cut set x 8..11 (sponsors), T1 Telly home x 12.4..16.85
#              (telly), 2 m in front of B6 / D2 / D3 / D4 / the wall-buy.
#
# Power (GDD §3.3): before Sign-On only the lava lamp, the vending machines, the EXIT boxes and the moonlight;
# when the colour wave reaches them the make-up mirror bulbs + dressing-room sconces switch on (one switchable
# group, 3-flash flicker) with their light anchors / floor pools.
#
# game.level.objects entries (world space):
#   ss_green      { group, screen }                        the screen-spawn wall TV (screen id 'ss_green', scr_decor)
#   gr_vanity     { group, parts:{ bulbs } , setBulbs(on) } bulbs = every switchable bulb of the room (vanity + doors)
#   gr_makeup_chair { group }   gr_dressing_doors { doors:[Node3D], baron:Node3D }   gr_clock { group, parts }
#   toy_lava_lamp { group, parts:{ blobs, glow }, play() }  toy_payphone { group, play() }
# Toys (GDD §13, key-only [E]): toy_lava_lamp ('toy_lava': the wax bloops 4x faster for 10 s),
#   toy_payphone ('toy_payphone': busy tone, the phone rattles on the wall). Each emits 'toy:use' {id}.
#
# PORT NOTES (Godot)
# * The local builders (gmAtlas, vanity, makeupChair, directorChair, wallTV, coatRail, garmentRack, trunkAndHead,
#   hifi, phoneShelf, barStool, the leak strip texture, boaGeo, bulbGeo, mirrorMat …) and every loose mesh build()
#   adds under the area root (bottle caps, floor decals, MAKE-UP / QUIET PLEASE / CALL BOARD signs + backers, the
#   Baron's leak strip, the cup, the make-up cable, the moonlight slats) are Blender assets built by
#   blender/runtime/rooms_lobby_green.py into res://assets/runtime/rooms_green_room/ (gm_*.glb +
#   green_room_dressing.glb); the EXIT box is the lobby's lg_exit.glb. They are placed here with kit.put exactly
#   like the JS.
# * The door-sconce bulbs are found like the JS (material === K.glow(game, '#FFD08A', 2.4)); the imported glow
#   material is compared by identity first, then by kind / colour / intensity.
# * ensureColors (white vertex colours for loose meshes) is done at export time by the Blender script.
# * JS `this` in the object methods -> the captured Dictionary. mesh.material = m -> material_override.
extends RefCounted

const Lobby := preload("res://scripts/world/rooms/lobby.gd")
const ASSETS := "res://assets/runtime/rooms_green_room/"
const LOBBY_ASSETS := "res://assets/runtime/rooms_lobby/"
const HP := PI / 2
const WALL := {"n": -11.85, "s": -6.15, "w": -6.85, "e": 16.85}

# bulbMats(game): { on: K.glow(game, '#FFD08A', 2.3), off: K.mat(game, 'ceramic', '#E9DDC6', { rim: 0.35 }) }
static func bulbMats(game) -> Dictionary:
	return {"on": game.mats.glow("#FFD08A", 2.3), "off": Lobby.kmat(game, "ceramic", "#E9DDC6", {"rim": 0.35})}

static func _asset(game, name: String) -> Node3D:
	return Lobby.loadAsset(game, ASSETS + name + ".glb")

# o.material === K.glow(game, '#FFD08A', 2.4) (the dressing-room door sconce bulb)
static func _isSconceBulb(game, o: Node) -> bool:
	if not (o is MeshInstance3D):
		return false
	var m := Lobby.getMaterial(o)
	if m == null:
		return false
	if m == game.mats.glow("#FFD08A", 2.4):
		return true
	if m is DAMaterial and (m as DAMaterial).kind == "glow":
		var dm: DAMaterial = m
		var c = dm.get("color")
		var it = dm.get("intensity")
		return c is Color and (c as Color).is_equal_approx(Color("#FFD08A")) and it != null and absf(float(it) - 2.4) < 1e-4 \
			and not Lobby.truthy(dm.get("additive"))
	return false

# ================================================================================================== build
static func build(game, area: Dictionary, root: Node3D) -> Lobby.RoomKit:
	var kit := Lobby.roomKit(game, area, root)
	var A := Layout.ANCHORS
	var PAL := Config.PAL
	var bm := bulbMats(game)
	var switchable := []                     # bulb meshes switched as one group at the end
	# the loose meshes green_room.js added straight under the area root (add(...)), world space
	var dress := _asset(game, "green_room_dressing")
	if dress != null:
		root.add_child(dress)

	# ---------------------------------------------------------------------------------- west end: vending corner
	kit.place("vending_cigarette", [-6.38, 0, WALL.n + 0.24], PI, {}, {"lightMul": 1.1})
	kit.place("vending_soda", [-5.4, 0, WALL.n + 0.4], PI - 0.035, {}, {"lightMul": 1.15})
	kit.pool([-5.85, 0.02, -10.7], 1.5, "#FFD2B0", 0.2, 0.12)
	kit.place("trash_can", [-4.62, 0, WALL.n + 0.3], 0.4, {"color": PAL.channelRed})
	# (three bottle caps on the floor: green_room_dressing.glb)
	# lava lamp on a drum table (toy_lava_lamp) — the pink key light before power
	var lp: Array = A.toy_lava_lamp.pos
	kit.place("table_side_drum", [lp[0] - 0.05, 0, lp[2] - 0.05], 0.2)
	var lava := kit.place("lamp_lava", [lp[0] - 0.05, 0.53, lp[2] - 0.05], 0.3, {"color": "#FF5FA2"}, {"lightMul": 1.6, "post": 0.7, "noMerge": true})
	kit.anchor({"pos": [lp[0] + 0.1, 1.2, lp[2] + 0.5], "color": "#FF5FA2", "intensity": 1.4, "distance": 5.5, "pre": 1, "post": 0.45})
	kit.pool([lp[0], 0.02, lp[2] + 0.35], 1.9, "#FF5FA2", 0.24, 0.1)
	# (boa decal: green_room_dressing.glb)
	# frame above the lava lamp
	kit.place("frame_picture", [-4.1, 1.48, WALL.n], PI, {"card": "poster_boogie_down", "style": "chrome", "h": 0.62}, {"colliders": false, "tilt": [0, 0.02]})
	kit.place("macrame_hanger", [-6.25, 3.5, -10.65], 0.6, {"drop": 1.05}, {"colliders": false})

	# ------------------------------------------------------------------------------------ west wall: coats, phone
	var payPos: Array = A.toy_payphone.pos
	kit.put(_asset(game, "gm_coat_rail"), [WALL.w, 1.68, -10.5], -HP, {"colliders": false})
	var pay := kit.place("payphone_rotary", [WALL.w, 0.95, payPos[2]], -HP, {}, {"noMerge": true})
	kit.put(_asset(game, "gm_phone_shelf"), [WALL.w, 0.8, payPos[2]], -HP, {"colliders": false})
	kit.put(_asset(game, "gm_stool"), [-6.25, 0, -7.05], 0.5)
	Lobby.moonSlats(game, kit, [WALL.w, 0, -9], -HP, {"w": 1.6, "d": 2.5, "shear": 0.2, "pre": 0.42, "post": 0.2}, Lobby._child(dress, "moon_slats_0"))
	kit.anchor({"pos": [-5.9, 1.7, -9.0], "color": "#9FB6FF", "intensity": 1.1, "distance": 5, "pre": 1, "post": 0.35})

	# ------------------------------------------------------------------------ south wall: five dressing-room doors
	var doors := []
	var i := 0
	for who in ["baron", "penny", "roxy", "skip", "duke"]:
		var d := kit.place("dressing_room_door", [-6.3 + i * 1.0, 0, WALL.s], 0.0, {"who": who}, {"scale": 0.87, "lights": false})
		i += 1
		if d == null:
			continue
		doors.append(d)
		DAU.traverse(d, func(o):
			if _isSconceBulb(game, o):
				switchable.append(o))
	kit.obj("gr_dressing_doors", {"doors": doors, "baron": doors[0] if doors.size() > 0 else null})
	# additive leak under the Baron's door (the strip mesh 'baron_leak': green_room_dressing.glb)
	var leak = Lobby._child(dress, "baron_leak")
	if leak != null:
		DAU.ud(leak).noMerge = true
		(leak as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.anchor({"pos": [-6.3, 0.35, -6.6], "color": "#B070FF", "intensity": 0.8, "distance": 2.6})
	for x in [-5.8, -3.0]:
		kit.anchor({"pos": [x, 2.3, -6.7], "color": "#FFD08A", "intensity": 1.4, "distance": 4.2, "pre": 0, "post": 1})
		kit.pool([x, 0.02, -6.75], 1.5, "#FFD08A", 0, 0.12)
	var clock := kit.place("clock_wall", [-4.3, 2.74, WALL.s], 0.0, {"label": "WZTV", "size": 0.36}, {"colliders": false})
	if clock != null:
		var cparts := Lobby.partsOf(clock)
		for k in ["hour", "minute", "second"]:
			if cparts.get(k) != null:
				DAU.ud(cparts[k]).noMerge = k == "second"
		kit.obj("gr_clock", {"group": clock, "parts": cparts})
		var sec = cparts.get("second")
		if sec != null:
			sec.rotation_order = EULER_ORDER_XYZ
		kit.ticks.append(func(_dt, _t, _rdt):
			if sec == null:
				return
			var tm = game.get("time")
			var ph := fmod(float(tm.get("realNow", 0.0)) if tm is Dictionary else 0.0, 1.6)
			var s := 58.0 + minf(1.0, ph / 0.06) if ph < 0.8 else 59.0 - minf(1.0, (ph - 0.8) / 0.08)
			sec.rotation.z = (s / 60.0) * TAU)
	# EXIT boxes over D2 / D3 (emergency circuit) + their red floor glow
	for x in [0.0, 12.0]:
		kit.put(Lobby.loadAsset(game, LOBBY_ASSETS + "lg_exit.glb"), [x, 2.74, WALL.s], 0.0, {"colliders": false})
		kit.pool([x, 0.02, -6.7], 1.1, "#FF4A3A", 0.1, 0.04)

	# ---------------------------------------------------------------------------- south wall: Hollywood vanity
	# 4.8 m counter centred at VX: its collider spans x 2.88..7.72. D2's east leaf swings into the room and rests
	# along this wall out to x 2.39 (hinge x 1.2, leaf 1.19 m), so the counter keeps 0.49 m to the swing and 1.54 m
	# to the D2 casing; the talent chair keeps 1.6 m to the Jump Cut tally camera (x 9.16) — everything shifted as one.
	var VX := 5.3
	var van := kit.put(_asset(game, "gm_vanity"), [VX, 0, WALL.s - 0.3], 0.0)
	var vanBulbs = Lobby.partsOf(van).get("bulbs")
	if vanBulbs != null:
		switchable.append(vanBulbs)
	kit.place("rug_shag_oval", [VX, 0, -7.55], 0.0, {"len": 4.1, "w": 1.5, "rings": ["#E8A92E", "#E3662B", "#B5472A", "#D9A520"]})
	var chair := kit.put(_asset(game, "gm_makeup_chair"), [VX, 0, -7.25], PI + 0.12)
	kit.obj("gr_makeup_chair", {"group": chair})
	kit.put(_asset(game, "gm_director_chair__roxy"), [VX - 1.68, 0, -7.2], PI - 0.35)
	kit.put(_asset(game, "gm_director_chair__talent"), [VX + 1.75, 0, -7.35], PI + 0.5)
	# (cucumber / towel / fan decals, the MAKE-UP sign + its backer: green_room_dressing.glb)
	kit.anchor({"pos": [VX - 1.4, 2.0, -7.0], "color": "#FFD08A", "intensity": 2.3, "distance": 5.5, "pre": 0, "post": 1})
	kit.anchor({"pos": [VX + 1.4, 2.0, -7.0], "color": "#FFD08A", "intensity": 2.3, "distance": 5.5, "pre": 0, "post": 1})
	kit.pool([VX, 0.02, -7.2], 2.9, "#FFD08A", 0, 0.2)

	# ------------------------------------------------------------------------- north wall: ss_green wall TV
	var tv := kit.put(_asset(game, "gm_wall_tv"), [-0.8, 1.2, WALL.n], PI, {"screenGroup": "scr_decor", "screenIds": ["ss_green"]})
	if tv != null:
		kit.obj("ss_green", {"group": tv, "screen": Lobby._screenMesh(tv)})
	kit.pool([-0.8, 0.02, -10.9], 1.2, "#9FDCFF", 0.07, 0.1)

	# ---------------------------------------------------------------- north wall: costumes beside D4, QUIET PLEASE
	kit.put(_asset(game, "gm_garment_rack"), [6.8, 0, WALL.n + 0.42], PI + 0.03)
	kit.put(_asset(game, "gm_trunk_hootie"), [6.3, 0, -10.55], PI - 0.45)
	# (QUIET PLEASE sign + backer, script2 / sheet decals: green_room_dressing.glb)

	# -------------------------------------------------------------- east of the Jump Cut set: cooler, poster, hi-fi
	kit.place("water_cooler", [11.72, 0, WALL.n + 0.2], PI)
	kit.place("frame_picture", [11.72, 1.62, WALL.n], PI, {"card": "poster_hootie", "style": "walnut", "h": 0.7}, {"colliders": false, "tilt": [0, -0.02]})
	# (dropped paper cup: green_room_dressing.glb)
	kit.put(_asset(game, "gm_hifi"), [13.75, 0, WALL.n + 0.25], PI)
	kit.place("plant_snake", [13.1, 0.62, WALL.n + 0.25], 0.3, {"seed": 7}, {"colliders": false})
	kit.place("macrame_hanger", [12.55, 3.5, -11.15], 1.2, {"drop": 0.95}, {"colliders": false})
	# framed WZTV test card above the Telly home (the mascot's own portrait)
	kit.place("frame_picture", [WALL.e, 2.08, -9.0], HP, {"card": "test_card", "style": "gold", "h": 0.62}, {"colliders": false})

	# ------------------------------------------------------------------------ south wall east of D3: call board
	kit.place("cork_board", [15.05, 1.1, WALL.s], 0.0, {"w": 1.2, "h": 0.8, "seed": 11}, {"colliders": false})
	# (CALL BOARD header: green_room_dressing.glb)
	kit.place("ash_urn", [13.8, 0, -6.48], 0.3, {"color": PAL.avocado})
	kit.place("plant_fern", [16.3, 0, -6.62], 0.9, {"seed": 6})

	# ------------------------------------------------------------------------------------- floor clutter
	# (papers, cup lid, memo, ticket and the make-up station cable: green_room_dressing.glb)

	# --------------------------------------------------------------------------------- switchable bulbs (power)
	var bulbMesh := kit.mergeInto(switchable, bm.off, "green_room_bulbs")
	var vanObj := kit.obj("gr_vanity", {"group": van, "parts": {"bulbs": bulbMesh}, "lit": false})
	vanObj.setBulbs = func(on) -> void:
		vanObj.lit = Lobby.truthy(on)
		if bulbMesh != null:
			bulbMesh.material = bm.on if Lobby.truthy(on) else bm.off
	kit.onPower([VX, 1.6, -6.4], func(on, _i = false): vanObj.setBulbs.call(on))
	kit.hook(bulbMesh if bulbMesh != null else vanBulbs)

	# ------------------------------------------------------------------------------------------------ toys
	if lava != null:
		var parts := Lobby.partsOf(lava)
		var blobs: Array = []
		if parts.get("blobs") != null:
			for c in (parts.blobs as Node).get_children():
				if c is Node3D:
					blobs.append(c)
		var base: Array = blobs.map(func(b): return {"y": b.position.y, "s": b.scale})
		var st := {"fast": 0.0, "phase": 0.0}
		var play := func() -> void:
			st.fast = 10.0
			kit.sound("toy_lava", lp)
		kit.toy("toy_lava_lamp", lp, play, 1.5)
		kit.obj("toy_lava_lamp", {"group": lava, "parts": parts, "play": play})
		kit.ticks.append(func(_dt, _t, rdt):
			var k := 4.0 if st.fast > 0.0 else 1.0
			if st.fast > 0.0:
				st.fast = maxf(0.0, st.fast - rdt)
			st.phase += rdt * 0.35 * k
			for bi in blobs.size():
				var b: Node3D = blobs[bi]
				var ph: float = st.phase * (1.0 + bi * 0.37) + bi * 1.7
				var u := 0.5 + 0.5 * sin(ph)
				b.position.y = base[bi].y + sin(ph * 0.5) * 0.008 if bi == 0 else 0.05 + u * 0.24
				var wob := 1.0 + sin(ph * 2.3) * 0.12
				var s0: Vector3 = base[bi].s
				b.scale = Vector3(s0.x * wob, s0.y / wob, s0.z * wob))
	if pay != null:
		var p0: Vector3 = pay.position
		var r0: Vector3 = pay.rotation
		var st := {"t": -1.0}
		var play := func() -> void:
			st.t = 0.0
			kit.sound("toy_payphone", payPos)
		kit.toy("toy_payphone", payPos, play, 1.5)
		kit.obj("toy_payphone", {"group": pay, "play": play})
		kit.ticks.append(func(_dt, _t, rdt):
			if st.t < 0.0:
				return
			st.t += rdt
			var k: float = st.t
			# busy tone: three rattles (0.25 s on / 0.25 s off), fading
			var on := k < 1.5 and fmod(k, 0.5) < 0.25
			var a := sin(k * 90.0) * 0.035 * (1.0 - k / 1.6) if on else 0.0
			pay.rotation = Vector3(r0.x + a, r0.y, r0.z + a * 0.6)
			pay.position = Vector3(p0.x + (0.004 if on else 0.0), p0.y + (absf(sin(k * 45.0)) * 0.006 if on else 0.0), p0.z)
			if k > 1.6:
				st.t = -1.0
				pay.rotation = r0
				pay.position = p0)
	return kit
