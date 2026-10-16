extends "res://scripts/main.gd"
## Sea and boats lab (fix2 lane B): fixed cameras on the sea and on every boat, at a fixed shader time, so a before
## and an after render show the same waves; plus a short sequence for the flash analysis. Needs a window:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     --fixed-fps 30 res://tools/sea_lab.tscn --quit-after 20000 -- shots=sea_pier,sea_coast outdir=/abs/dir
## Args: shots=<names> outdir=<dir> [settle=4] [tt=<shader time, s>] [tod=<mood>] [tag=<suffix>] [hero=1];
##       seq=<camera name> seqn=<frames> seqdt=<s between frames> seqdir=<dir> [seqcrop=x,y,w,h] (PNG frames);
##       list=1 prints the names.
## Camera entries: [position, look-at, fov, hero visible (bool)]. The gameplay shots use the follow camera behind the
## hero (as world_tour does): [&"follow", hero xz, facing deg, yaw offset, pitch, distance, fov].

const L := preload("res://scripts/world/nemea_layout.gd")

const CAMS := {
	# --- the sea ---------------------------------------------------------------------------------------------------
	# from the pier's end over the open sea (south), low and a little higher
	"sea_pier": [Vector3(14.0, 3.4, 140.0), Vector3(14.0, -4.0, 215.0), 60.0, false],
	"sea_pier_wide": [Vector3(14.0, 4.0, 141.0), Vector3(-20.0, -3.0, 215.0), 70.0, false],
	# the gameplay camera on the pier's end, the hero facing the open sea (south): what the player sees of the sea
	"sea_game": [&"follow", Vector2(14.0, 139.0), 180.0, 0.0, -7.0, 5.2, 62.0],
	"sea_game_low": [&"follow", Vector2(14.0, 139.0), 180.0, 28.0, -3.0, 5.2, 62.0],
	# the village plaza (the paving's look: the merge's render checks) from the gameplay camera, the hero walking north into it
	"plaza_game": [&"follow", Vector2(0.0, 86.0), 0.0, 0.0, -13.0, 6.0, 62.0],
	"plaza_game_b": [&"follow", Vector2(9.0, 70.0), 215.0, 0.0, -10.0, 6.0, 62.0],
	# the coast and the beach, seen from the water
	"sea_coast": [Vector3(-34.0, 5.0, 150.0), Vector3(-10.0, 0.0, 100.0), 62.0, false],
	"sea_coast2": [Vector3(60.0, 6.0, 150.0), Vector3(20.0, 0.0, 105.0), 62.0, false],
	# the title orbit (radius 150, 48 up, centre (0, ~h, 40)), at its starting yaw and from the south
	"title_start": [Vector3(0, 0, 0), Vector3(0, 0, 0), 60.0, false],
	"title_south": [Vector3(0, 0, 0), Vector3(0, 0, 0), 60.0, false],
	# a high overview of the south sea
	"sea_high": [Vector3(20.0, 90.0, 200.0), Vector3(10.0, 0.0, 120.0), 55.0, false],
	"sea_high2": [Vector3(-40.0, 60.0, 190.0), Vector3(0.0, 0.0, 100.0), 62.0, false],
	# looking at where the sun_golden mirror image sits on the water (view elevation = the light's elevation, 11.1 m ahead of the camera)
	"sun_golden": [Vector3(14.0, 3.4, 140.0), Vector3(3.12, 0.0, 142.31), 60.0, false],
	# looking at where the sun_day mirror image sits on the water (view elevation = the light's elevation, 3.2 m ahead of the camera)
	"sun_day": [Vector3(14.0, 3.4, 140.0), Vector3(11.31, 0.0, 141.68), 60.0, false],
	# looking at where the sun_dawn mirror image sits on the water (view elevation = the light's elevation, 21.5 m ahead of the camera)
	"sun_dawn": [Vector3(14.0, 3.4, 140.0), Vector3(34.42, 0.0, 146.63), 60.0, false],
	# looking at where the sun_dusk mirror image sits on the water (view elevation = the light's elevation, 64.9 m ahead of the camera)
	"sun_dusk": [Vector3(14.0, 3.4, 140.0), Vector3(-50.72, 0.0, 144.53), 60.0, false],
	# looking at where the moon_night mirror image sits on the water (view elevation = the light's elevation, 3.3 m ahead of the camera)
	"moon_night": [Vector3(14.0, 3.4, 140.0), Vector3(15.54, 0.0, 142.90), 60.0, false],
	# the dock pack's fishing boat at (30, 0, 150) (dockboat=1)
	"dock_high": [Vector3(31.0, 5.5, 154.5), Vector3(30.0, 0.3, 150.0), 52.0, false],
	"dock_low": [Vector3(33.6, 0.75, 153.4), Vector3(30.0, 0.4, 150.0), 56.0, false],
	"dock_top": [Vector3(30.0, 7.0, 150.4), Vector3(30.0, 0.2, 150.0), 50.0, false],
	# --- the boats ---------------------------------------------------------------------------------------------------
	# gameplay camera on the pier (hero start): the ships on both sides
	"boat_game": [&"follow", Vector2(14.0, 130.0), 0.0, 0.0, -12.0, 5.5, 60.0],
	"boat_game_back": [&"follow", Vector2(14.0, 128.0), 180.0, 0.0, -14.0, 5.5, 60.0],
	"boat_game_gal": [&"follow", Vector2(14.0, 136.0), -90.0, 0.0, -18.0, 5.0, 60.0],
	"boat_game_ler": [&"follow", Vector2(13.4, 132.0), 90.0, 0.0, -18.0, 5.0, 60.0],
	# high angles into each ship
	"gal_high": [Vector3(18.6, 9.0, 146.0), Vector3(18.6, 0.2, 135.0), 52.0, false],
	"gal_top": [Vector3(21.0, 11.0, 135.0), Vector3(18.6, 0.2, 135.0), 52.0, false],
	"ler_high": [Vector3(8.6, 9.0, 143.0), Vector3(8.6, 0.2, 132.0), 52.0, false],
	"ler_top": [Vector3(5.0, 11.0, 132.0), Vector3(8.6, 0.2, 132.0), 52.0, false],
	# low from the water, at the waterline
	"gal_low": [Vector3(23.5, 0.55, 141.0), Vector3(18.6, 0.6, 135.0), 58.0, false],
	"gal_low2": [Vector3(24.0, 0.45, 133.0), Vector3(18.6, 0.6, 135.0), 58.0, false],
	"ler_low": [Vector3(3.5, 0.55, 138.0), Vector3(8.6, 0.6, 132.0), 58.0, false],
	"ler_low2": [Vector3(3.2, 0.45, 130.0), Vector3(8.6, 0.6, 132.0), 58.0, false],
	"ships_low": [Vector3(14.0, 0.6, 152.0), Vector3(14.0, 1.0, 134.0), 62.0, false],
	"ships_high": [Vector3(14.0, 14.0, 156.0), Vector3(14.0, 0.0, 134.0), 58.0, false],
	# from the pier deck, hero height, looking down into the ships
	"pier_gal": [Vector3(15.4, 3.1, 133.5), Vector3(18.6, 0.4, 136.0), 60.0, false],
	"pier_ler": [Vector3(12.6, 3.1, 133.5), Vector3(8.6, 0.4, 131.0), 60.0, false],
	# a swimmer next to the Lerna ship (camera just over the water)
	"swim_ler": [Vector3(11.6, 0.9, 139.5), Vector3(8.6, 0.5, 131.0), 62.0, false],
	"swim_gal": [Vector3(16.2, 0.9, 140.5), Vector3(18.6, 0.5, 134.0), 62.0, false],
	# the deck check (deckcheck=<cam>): both decks from above, and each ship from the side away from the pier
	"dc_top": [Vector3(13.6, 13.0, 137.0), Vector3(13.6, 0.3, 134.0), 78.0, false],
	"dc_ler": [Vector3(1.0, 8.5, 134.0), Vector3(8.6, 0.3, 132.0), 62.0, false],
	"dc_gal": [Vector3(26.5, 8.5, 137.0), Vector3(18.6, 0.3, 135.0), 62.0, false],
	# the beached boats on the sand
	"beach1": [Vector3(-1.5, 2.6, 111.0), Vector3(-6.0, 1.2, 106.0), 55.0, false],
	"beach1_low": [Vector3(-2.0, 1.5, 112.0), Vector3(-6.0, 1.3, 106.0), 55.0, false],
	"beach1_sea": [Vector3(-20.0, 2.6, 128.0), Vector3(-6.0, 1.3, 106.0), 55.0, false],
	"beach2": [Vector3(34.0, 2.6, 112.0), Vector3(30.0, 1.2, 107.0), 55.0, false],
	"beach2_low": [Vector3(34.5, 1.6, 113.0), Vector3(30.0, 1.3, 107.0), 55.0, false],
	"beach2_sea": [Vector3(48.0, 2.6, 128.0), Vector3(30.0, 1.3, 107.0), 55.0, false],
	"beach_wide": [Vector3(12.0, 5.0, 122.0), Vector3(12.0, 0.8, 100.0), 78.0, false],
}

var _cur := ""


func _wants_title() -> bool:
	return false


func _ready() -> void:
	if not Game.has_arg("noui"):
		Game.args["noui"] = "1"
	if not Game.has_arg("enemies"):
		Game.args["enemies"] = "0"
	if not Game.has_arg("lion"):
		Game.args["lion"] = "0"
	super._ready()
	_water_variant()
	if Game.arg_on("dockboat"):
		# the dock pack's fishing boat (ModelsBuildings.boat, not placed in DOCE) on the open sea, static at the waterline
		var mi := MeshInstance3D.new()
		mi.name = "DockBoat"
		mi.mesh = ModelsBuildings.boat(5)
		mi.material_override = Materials.lowpoly()
		world.add_child(mi)
		mi.global_transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(30.0, 0.0, 150.0))
	if Game.arg_on("list"):
		print("SEALAB cameras: ", ", ".join(CAMS.keys()))
		get_tree().quit()
		return
	if String(Game.arg("shots", "")) != "":
		_shots.call_deferred(String(Game.arg("shots")).split(",", false))
	elif String(Game.arg("seq", "")) != "":
		_seq.call_deferred(String(Game.arg("seq")))
	elif String(Game.arg("deckcheck", "")) != "":
		_deckcheck.call_deferred(String(Game.arg("deckcheck")))


func _process(delta: float) -> void:
	super._process(delta)
	# freeze the shader clock at the wanted time (TimeOfDay adds this frame's delta after us)
	if Game.has_arg("tt") and tod != null and _hold:
		_set_clock(float(Game.arg("tt")) - delta)


var _hold := true


## Pins the shaders' clock at t. Since the wind lane (fix2) the clock is smoothed and pulled back to the raw sum of the frame
## deltas, so writing TimeOfDay._time alone no longer sticks: set_shader_time() sets both. (The pre-fix TimeOfDay, which the
## BEFORE renders use, has only _time.)
func _set_clock(t: float) -> void:
	if tod.has_method("set_shader_time"):
		tod.call("set_shader_time", t)
	else:
		tod.set("_time", t)


## Measurement variants of the sea shader, so the white marks (or the sparkles, or the sun glints) of any version of
## the shader can be isolated exactly as the difference of two renders of the same camera and time:
##   wsh=<abs path of a water.gdshader to use instead of the project's>   wpatch=nomarks+nospark+noglint
func _water_variant() -> void:
	var path := String(Game.arg("wsh", ""))
	var patch := String(Game.arg("wpatch", ""))
	if path == "" and patch == "":
		return
	var src := FileAccess.get_file_as_string(path if path != "" else "res://shaders/water.gdshader")
	if src == "":
		push_error("SEALAB: cannot read the water shader %s" % path)
		return
	for p in patch.split("+", false):
		match p:
			"nomarks":
				# crest_marks() returns nothing: the arcs (both layers) are gone, everything else is the same
				src = src.replace("float thick) {\n", "float thick) {\n\treturn 0.0;\n")
				src = src.replace("float keep_cut) {\n", "float keep_cut) {\n\treturn 0.0;\n")
			"nospark":
				src = src.replace("emit_extra += spark_col * sparkle * mix(1.6, 1.3, g_night);", "")
			"noglint":
				src = src.replace("SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);", "")
			"nofoamring":
				src = src.replace("float foam = ring * dash * zone;", "float foam = 0.0;")
			"noscroll":
				# the reflection streaks do not scroll with time
				src = src.replace("ph_noise(sq + vec2(t * 0.05, -t * 0.25))", "ph_noise(sq)")
			"notone":
				# no light / shade toggling of the wave faces
				src = src.replace("float tone = smoothstep(0.06, 0.1, wn.x * L.x + wn.z * L.z);", "float tone = 0.5;")
			"nostreak":
				# no ripple streaks in the sky reflection
				src = src.replace("fstep *= mix(0.45, 1.0, streak);", "fstep *= 0.8;")
			"flatn":
				# the shading normal flattens with distance (the swell cannot be resolved there)
				src = src.replace("vec3 wn = normalize(vec3(-fgr.x, 1.0, -fgr.y));", "float nk = smoothstep(150.0, 40.0, length(VERTEX));\n\tvec3 wn = normalize(vec3(-fgr.x * nk, 1.0, -fgr.y * nk));")
			"flatstreak":
				src = src.replace("fstep *= mix(0.45, 1.0, streak);", "fstep *= mix(0.45, 1.0, mix(1.0, streak, smoothstep(120.0, 30.0, dist)));")
			"streaknotone":
				# the ripple streaks no longer follow the wave faces' light / shade toggle
				src = src.replace(" + (tone - 0.5) * 0.25);", ");")
			"softstreak":
				src = src.replace("float streak = smoothstep(0.32, 0.5,", "float streak = smoothstep(0.2, 0.62,")
			"aastreak":
				# the streak noise fades to its mean where a pixel spans more than half a noise cell (aliasing)
				src = src.replace("float streak = smoothstep(0.32, 0.5,", "float streak_raw = smoothstep(0.32, 0.5,")
				src = src.replace("fstep *= mix(0.45, 1.0, streak);", "fstep *= mix(0.45, 1.0, mix(1.0, streak_raw, 1.0 - smoothstep(0.3, 0.9, fwidth(sq.y))));")
			"magenta":
				# the sea drawn pure magenta (with noedges=1 nopost=1 the pixels keep it): the deck check looks for it
				src = src.replace("ALBEDO = ph_out(col);", "ALBEDO = vec3(0.0);")
				src = src.replace("EMISSION = ph_out(mix(base, g_fog_color, f));", "EMISSION = vec3(1.0, 0.0, 1.0);")
			"noreflect":
				# no sky reflection at all
				src = src.replace("col = mix(col, refl, fstep);", "")
	var sh := Shader.new()
	sh.code = src
	(Materials.water() as ShaderMaterial).shader = sh
	print("SEALAB water shader: %s patch=%s" % [path if path != "" else "project", patch])


func _title_pose(yaw_deg: float) -> Array:
	var c: Vector3 = world.ground(Vector3(0, 0, 40)) + Vector3(0, 6, 0)
	var y := deg_to_rad(yaw_deg)
	var p := c + Vector3(sin(y), 0, cos(y)) * 150.0 + Vector3(0, 48.0, 0)
	return [p, c]


func _place(name_s: String) -> void:
	var s: Array = CAMS[name_s]
	hero.visible = true
	if s[0] is StringName and s[0] == &"follow":
		var xz: Vector2 = s[1]
		var face: float = s[2]
		var p: Vector3 = world.ground(Vector3(xz.x, 0.0, xz.y))
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(xz.x, 120.0, xz.y), Vector3(xz.x, -20.0, xz.y), 1))
		if not hit.is_empty():
			p = hit["position"]
		hero.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(face)), p))
		cam.follow(hero)
		cam.yaw = face + float(s[3])
		cam.pitch = float(s[4])
		cam.distance = float(s[5])
		cam.cam.fov = float(s[6])
		cam.snap()
		return
	var pos: Vector3 = s[0]
	var at: Vector3 = s[1]
	if name_s == "title_start":
		var tp := _title_pose(160.0)
		pos = tp[0]
		at = tp[1]
	elif name_s == "title_south":
		var tp2 := _title_pose(12.0)
		pos = tp2[0]
		at = tp2[1]
	var d := at - pos
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	cam.set_fly(pos, yaw, pitch)
	cam.cam.fov = float(s[2])
	if not bool(s[3]):
		hero.visible = false


func _shots(names: PackedStringArray) -> void:
	var out_dir := String(Game.arg("outdir", OS.get_user_data_dir()))
	var settle := int(Game.arg("settle", "4"))
	var tag := String(Game.arg("tag", ""))
	if Game.has_arg("tod"):
		tod.call("set_state", Game.arg("tod", "golden"))
	# let the world settle (shaders compile, the meadow builds its rings)
	for i in 6:
		await get_tree().process_frame
	for n in names:
		_cur = n
		_place(n)
		for i in settle:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out_dir.path_join(n + tag + ".png"))
		if err != OK:
			push_error("SEALAB: cannot save %s (error %d): outdir must be an existing absolute path" % [out_dir.path_join(n + tag + ".png"), err])
		print("SEALAB shot %s -> %s (g_time %.3f)" % [n, n + tag + ".png", tod.shader_time()])
	get_tree().quit()


## A sequence from one camera: frames at the engine's own clock (fixed fps), saved as PNG (optionally cropped).
func _seq(name_s: String) -> void:
	var out_dir := String(Game.arg("seqdir", OS.get_user_data_dir()))
	var n := int(Game.arg("seqn", "60"))
	var every := int(Game.arg("seqevery", "1"))
	if Game.has_arg("tod"):
		tod.call("set_state", Game.arg("tod", "golden"))
	for i in 6:
		await get_tree().process_frame
	_hold = false
	_place(name_s)
	if Game.has_arg("tt"):
		_set_clock(float(Game.arg("tt")))
	var crop := Rect2i()
	if Game.has_arg("seqcrop"):
		var p := String(Game.arg("seqcrop")).split(",")
		crop = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	var saved := 0
	for f in n * every:
		await get_tree().process_frame
		if f % every != 0:
			continue
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if crop.size.x > 0:
			img = img.get_region(crop)
		img.save_png(out_dir.path_join("s%04d.png" % saved))
		saved += 1
	print("SEALAB seq %s: %d frames to %s, g_time now %.3f" % [name_s, saved, out_dir, tod.shader_time()])
	get_tree().quit()


## END-TO-END deck check (FIX2): does the sea plane ever get drawn over a ship's deck? The sea is magenta (wpatch=magenta,
## and noedges=1 nopost=1 so the pixels keep it), the camera `cam_name` looks at the ships for dcn frames while they heave,
## and every frame the deck points of both ships (a grid 20 cm inside the deck's outline, 1 cm over the planks) are
## projected to the screen: a magenta pixel there means the sea was drawn in FRONT of the deck at that point. In the
## original ships the deck is the plank platform at y = -0.02 (the sea covers it 60-65 % of the time); the fixed ones have
## a deck at +0.34. Prints `SEALAB deckcheck ...`. Needs a window:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 480x270 --fixed-fps 20 res://tools/sea_lab.tscn
##     --quit-after 3000 -- play=1 deckcheck=dc_top dcn=900 wpatch=magenta noedges=1 nopost=1 grass=0 wheat=0 shadows=0
func _deckcheck(cam_name: String) -> void:
	var n := int(Game.arg("dcn", "900"))
	if Game.has_arg("tod"):
		tod.call("set_state", Game.arg("tod", "golden"))
	for i in 6:
		await get_tree().process_frame
	_hold = false
	_place(cam_name)
	_set_clock(float(Game.arg("tt", "0")))
	var defs := [["ShipHeracles", 0, 21, L.BOAT_HERACLES, 0.04], ["ShipLerna", 1, 33, L.BOAT_LERNA, PI - 0.05]]
	var ships: Array = []
	for e in defs:
		var d: Dictionary = ModelsBuildings.ship(int(e[1]), int(e[2]))
		var length: float = d["length"]
		var beam: float = d["beam"]
		var pts: Array[Vector3] = []
		if d.has("deck"):
			# the fixed ships: the deck outline, 20 cm inside the inner walls
			var deck: float = d["deck"]
			var zz := -length * 0.44
			while zz <= length * 0.44:
				var tn := zz / (length * 0.5)
				var wd: float = float(Callable(ModelsNature, "hull_width_at").call(tn, beam, float(d["depth"]), float(d["draft"]) + deck)) - 0.27 # (by name: the original tree has no such function)
				var xx := -wd
				while xx <= wd + 0.001:
					pts.append(Vector3(xx, deck + 0.01, zz))
					xx += 0.3
				zz += 0.4
		else:
			# the original ships: the plank platform (a box beam * 0.55 x length * 0.62, its top at y = -0.02)
			var hx := beam * 0.55 * 0.5 - 0.15
			var hz := length * 0.62 * 0.5 - 0.15
			var zz2 := -hz
			while zz2 <= hz + 0.001:
				var xx2 := -hx
				while xx2 <= hx + 0.001:
					pts.append(Vector3(xx2, -0.02 + 0.01, zz2))
					xx2 += 0.3
				zz2 += 0.4
		ships.append({"name": e[0], "node": world.get_node_or_null(String(e[0])), "static": Transform3D(Basis(Vector3.UP, float(e[4])), e[3] as Vector3), "pts": pts, "tested": 0, "hits": 0, "frames_hit": 0, "min_clear": INF, "worst": Vector3.ZERO})
	var sea = Game.sea
	var vr := get_viewport().get_visible_rect().size
	var frames_any := 0
	for f in n:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var sz := Vector2(img.get_size())
		var any := false
		for s in ships:
			var node = s["node"]
			var xf: Transform3D = (node as Node3D).global_transform if node != null else (s["static"] as Transform3D)
			var hit_here := false
			for p in (s["pts"] as Array[Vector3]):
				var w := xf * p
				if cam.cam.is_position_behind(w):
					continue
				var sp := cam.cam.unproject_position(w)
				var px := int(sp.x * sz.x / vr.x)
				var py := int(sp.y * sz.y / vr.y)
				if px < 2 or py < 2 or px >= int(sz.x) - 2 or py >= int(sz.y) - 2:
					continue
				s["tested"] = int(s["tested"]) + 1
				var depth: float = float(world.sea_level) - float(world.height_at(w.x, w.z))
				var clear: float = w.y - float(sea.call("surface_y", w.x, w.z, maxf(depth, 0.0)))
				if clear < float(s["min_clear"]):
					s["min_clear"] = clear
					s["worst"] = w
				var c := img.get_pixel(px, py)
				if c.r > 0.8 and c.b > 0.8 and c.g < 0.25:
					s["hits"] = int(s["hits"]) + 1
					hit_here = true
				if f == n - 1 and Game.has_arg("dcshot"):
					img.set_pixel(px, py, Color(1.0, 1.0, 0.0) if c.r > 0.8 and c.b > 0.8 and c.g < 0.25 else Color(0.0, 1.0, 0.0))
			if hit_here:
				s["frames_hit"] = int(s["frames_hit"]) + 1
				any = true
		if any:
			frames_any += 1
		if f == n - 1 and Game.has_arg("dcshot"):
			img.save_png(String(Game.arg("dcshot")))
	for s in ships:
		print("SEALAB deckcheck %s %s: %d deck-point samples over %d frames (%.0f s), the SEA drawn in front of the deck in %d samples (%.2f%%), in %d frames; the lowest clearance of a sampled deck point over the water (Sea.surface_y) %.3f m" % [
			cam_name, s["name"], s["tested"], n, float(n) / 20.0, s["hits"], 100.0 * float(s["hits"]) / maxf(1.0, float(s["tested"])), s["frames_hit"], s["min_clear"]])
	print("SEALAB deckcheck %s: frames with the sea over a deck: %d of %d" % [cam_name, frames_any, n])
	get_tree().quit()
