extends Object
## Heracles' animations filmed for the client's GIFs: tools/anim_gifs.py writes the clips' spec, runs this twice per GIF (mode=measure,
## then the pictures), slices the strips and builds the GIFs (tools/anim_gifs.sh wraps it).
##   godot --path . --rendering-driver opengl3 --resolution 160x120 res://tools/preview.tscn -- script=res://tools/anim_gifs.gd \
##     fns=clips spec=<clips.json> out=<dir> [mode=measure] [tod=golden] [sun_azim= sun_elev=] [msaa=1] [settle=1] [only=<id>,..]
## A clip is ONE rig living through a short timeline at the game's own pace (fixed steps of 1/60 s or less), filmed every 1/fps s by
## one camera per view. Nothing is re-simulated per frame: the cloak, the kilt and the scabbard move on as they do in the game (the
## preview's sheets pose every tile from scratch instead). Every camera follows the rig over the ground (the hero stays in the middle
## of his tile; a jump rises in it). Before anything is rendered every clip is run once without pictures to measure it (the bones,
## the cloak's particles and the visible props over all its frames); each view's camera is then aimed and zoomed so that all of it
## fits the tile with a margin, one zoom per `group` and view (the heroes of one GIF the same size). The shaders' clock is stopped
## (the clouds stay put) and the preview's ground is widened (and lowered for the `deep` prop).
## mode=measure renders nothing: per clip "DUR <id> n=<frames> t0= t1=" (how long it lasts by itself) and, for a clip with
## "extent": true, per view "EXT <id> <view> kx= ky= h=": the half width and half height (tangents, margin included) that hold
## everything the clip shows over all its frames when the aim is centred on it, and h, the height (tangent) of the hero standing
## (feet to the top of the hair) in that view: tools/anim_gifs.py sizes the tiles of a GIF from them so that the hero is the same
## number of pixels tall in every tile and the long blade stays inside through the whole swing.
## Else out: <out>/<id>@<view>.png, the frames left to right (one tile wide each); on stdout "FRAMING ...", "EVENTS <id> [[name, s],
## ...]" and "CLIP ..." per clip; "CLIPS done" at the end.
##
## Spec (JSON) {"clips": [clip, ...]}; a clip:
##   id, tile [w, h], views [name | {name, yaw, pitch, dist, look, fov, tile [w, h]}] (names: VIEWS; a view's own tile overrides the
##   clip's), extent (measure), group, one_zoom (the group's zoom shared by
##   all its views), follow "xz" (default) | "xyz", margin (of the tile, each side, 0.06), sun [azimuth, elevation] (deg, this clip),
##   cap {fps 15, n frames (none: until all is over plus `tail` s, 0.25), t0 (s after the pre-roll, or "blow:<k>": when the k-th blow
##     starts), cyclic "" | "gait" | "swim" | <period s>}: a cyclic clip spreads its n frames over a whole number of cycles (it loops
##     without a seam; the pace within a few % of the real one),
##   setup {outfit, armed 1|0, ready 0..1, guard, state, y, vy, speed (m/s), heading (deg: 0 ahead, 90 his right, 180 back), vel
##     [x, y, z] (rig-space velocity instead: the zip), loco (m/s fed to the gait instead of the real speed), pre (s, 1.6), spear (on
##     the back) 1|0, aside 1|0, brush 0..1, brushh, set {rig var: value}, props [ledge, water, chain, chainup, deep]},
##   events [[t, cmd, args...], ...] (t in s after the pre-roll), cmd:
##     play <action> [speed 1] [upper 0]   hold <s | -1>   at <s>   stop [blend]   speed <m/s> [heading]   ramp <m/s> <m/s2>
##     guard 0|1   state <s>   vy <m/s>   armed 0|1 [instant 0]   aside 0|1   spear 0|1   set <var> <value>   impact <k>   loco <m/s>
##     move <m> <s> [deg 0] [sine|lin|smooth|quad|roll|back]   (the node carried over the ground)
##   and, read from Hero / HeroMelee / RigHeracles so they stay what the game does:
##     blow <a1..dash> [skip]   a blow as HeroMelee starts it with nobody in reach: the 0.3 m step into it, the dash's leap out of
##                              the sprint, a run over 3 m/s carried on under it and slowing
##     chain <a1,a2,...>        the blows of a string, each at the `open` key of the one before
##     entry <blow>             the quick draw that leads into the blow (RigHeracles.DRAW_INTO), then the blow
##     heavy <s held>           the charge coil (legs on the gait), held trembling, released into the spin
##     roll [deg] | backstep    Hero's dodges: the action at its game speed and the travel along ROLL_PATH / the backstep's ease
##     knock <m/s> [deg 180]    a knock-back dying at 18 m/s2
##     throw [speed] [upper]    the spear thrown at THROW_SPEED (it leaves the back for good at the release); catch [upper 1]
##     jump [m/s 8] | fall      the arc under Hero's gravity, "land" played on a hard landing; climb [m over] (the mantle, MANTLE_*)

const RUN_SPEED := 6.2 # Hero.RUN_SPEED (the rig's speed_max, as Hero feeds it)
const GRAVITY := 24.0 # Hero.GRAVITY, Hero.FALL_MULT
const FALL_MULT := 1.55
const DT := 1.0 / 60.0
## Render layers 11..19 carry the views' edge quads (one per camera), layer 20 the preview's own (seen by no tile).
const EDGE_LAYER0 := 10
const EDGE_LAYERS := 0x3FF << 10
const EDGE_LAYER_OFF := 1 << 19

## The views: yaw (deg round the hero: 0 behind him, 90 his right, 180 in front), pitch (deg, looking down), distance (m) and the
## height (m) the camera aims at before the framing centres it.
const VIEWS := {
	"tq": {"yaw": 140.0, "pitch": 9.0, "dist": 4.8, "look": 1.0},
	"tql": {"yaw": -140.0, "pitch": 9.0, "dist": 4.8, "look": 1.0},
	"side": {"yaw": 90.0, "pitch": 6.0, "dist": 4.8, "look": 1.0},
	"sidel": {"yaw": -90.0, "pitch": 6.0, "dist": 4.8, "look": 1.0},
	"front": {"yaw": 170.0, "pitch": 8.0, "dist": 4.8, "look": 1.0},
	"back": {"yaw": 0.0, "pitch": 10.0, "dist": 4.8, "look": 1.0},
	"tqb": {"yaw": 35.0, "pitch": 11.0, "dist": 4.8, "look": 1.0},
	# the gameplay camera in a fight (scripts/camera/camera_rig.gd: 5.5 m behind, PITCH_COMBAT 24 degrees down, a little to his
	# right), zoomed to the hero
	"game": {"yaw": 7.0, "pitch": 24.0, "dist": 5.5, "look": 1.2},
}


static func clips(_seed: int) -> Node3D:
	return ClipStage.new()


class ClipStage extends Node3D:
	var _ground: MeshInstance3D
	var _tod: TimeOfDay

	func _ready() -> void:
		_run.call_deferred()

	func _arg(k: String, d: String) -> String:
		return String(Game.arg(k, d))

	func _run() -> void:
		var spec_path := _arg("spec", "")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
		if not (parsed is Dictionary):
			push_error("anim_gifs: cannot read the spec " + spec_path)
			get_tree().quit(1)
			return
		var out_dir := _arg("out", "user://anim_gifs")
		DirAccess.make_dir_recursive_absolute(out_dir)
		for ch in get_parent().get_children():
			if ch is MeshInstance3D and ch != self:
				_ground = ch # (the preview's ground block: made wide enough for any travel, lowered for the deep props)
			elif ch is TimeOfDay:
				_tod = ch
			elif ch is ToonScreen and (ch as ToonScreen).edges:
				# the preview's own edge quad (on its window's camera) is in the world the tiles film: a full-screen pass,
				# every tile drew it on top of its own (lines and rim twice, and a bright band under the horizon)
				(ch as ToonScreen).edges.layers = EDGE_LAYER_OFF
		if _ground:
			_ground.scale = Vector3(30.0, 1.0, 30.0)
		if _tod:
			# the shaders' clock stopped (the clouds would drift between frames and jump back where the GIF loops)
			_tod.set_process(false)
			RenderingServer.global_shader_parameter_set("g_time", 8.0)
		var only := _arg("only", "").split(",", false)
		var list: Array = []
		for c in (parsed as Dictionary).get("clips", []):
			if only.is_empty() or only.has(String(c["id"])):
				list.append(c)
		await get_tree().process_frame
		if _arg("mode", "") == "measure":
			# how long each clip lasts by itself (tools/anim_gifs.py plans the GIFs' loops from it): "DUR <id> n=.. t0=.. t1=..";
			# with extent, what it needs on screen per view: "EXT <id> <view> kx=.. ky=.. h=.."
			var href := -1.0
			for c in list:
				var res := {}
				var ext := bool(c.get("extent", false))
				var pts: Array = []
				var cb := Callable()
				if ext:
					cb = func(rig: RigHeracles, _k: int, anchor: Vector3) -> void: _points(rig, anchor, pts)
					if href < 0.0:
						href = _hero_height()
				await _simulate(c, cb, res)
				print("DUR %s n=%d t0=%.4f t1=%.4f" % [c["id"], int(res["n"]), float(res["t0"]), float(res["t1"])])
				if ext:
					for v in c.get("views", ["tq"]):
						var vw := _view(v)
						var cs := _cam_space(pts, vw)
						var m := float(c.get("margin", 0.06))
						print("EXT %s %s kx=%.5f ky=%.5f h=%.5f" % [c["id"], vw["name"], _fit_axis(cs, 0) / (1.0 - 2.0 * m),
							_fit_axis(cs, 1) / (1.0 - 2.0 * m), _hero_tan(vw, href)])
			print("CLIPS done")
			get_tree().quit()
			return
		# 1: every clip run without pictures, measured; the zoom per group and view
		var t_meas := Time.get_ticks_msec()
		var need := {}
		var meas := {}
		var own := {}
		for c in list:
			var pts: Array = []
			await _simulate(c, func(rig: RigHeracles, _k: int, anchor: Vector3) -> void: _points(rig, anchor, pts))
			meas[c["id"]] = pts
			for v in c.get("views", ["tq"]):
				var vw := _view(v)
				var key := _zoom_key(c, vw)
				var t := _fit_tan(pts, vw, _aspect(c, vw), float(c.get("margin", 0.06)))
				own[String(c["id"]) + "|" + String(vw["name"])] = t
				need[key] = maxf(float(need.get(key, 0.0)), t)
		print("MEASURED %d clips in %.1f s" % [list.size(), (Time.get_ticks_msec() - t_meas) / 1000.0])
		# 2: the pictures
		for c in list:
			var t0 := Time.get_ticks_msec()
			var sun0 := _sun(c.get("sun", []))
			var cams: Array = []
			for v in c.get("views", ["tq"]):
				var vw := _view(v)
				var key := _zoom_key(c, vw)
				var fr := _frame(meas[c["id"]], vw, _aspect(c, vw), float(c.get("margin", 0.06)), float(need[key]))
				cams.append(_make_cam(c, vw, fr, cams.size()))
				var own_fov := rad_to_deg(2.0 * atan(float(own[String(c["id"]) + "|" + String(vw["name"])])))
				print("FRAMING %s %s fov=%.1f (alone %.1f) look=(%.2f, %.2f) group=%s%s" % [c["id"], vw["name"], fr["fov"], own_fov,
					fr["a"], fr["b"], key, "" if fr["ok"] else " (TIGHT: something leaves the tile)"])
			var n := _frames_n(c)
			var strips: Array[Image] = []
			for cm in cams:
				var vt: Vector2i = cm["tile"]
				var im := Image.create(vt.x * n, vt.y, false, Image.FORMAT_RGB8)
				im.fill(Color(0.1, 0.1, 0.12))
				strips.append(im)
			var settle := int(_arg("settle", "1"))
			var res := {}
			await _simulate(c, func(rig: RigHeracles, k: int, anchor: Vector3) -> void:
				for cm in cams:
					_place_cam(cm, anchor)
				_props_frame(rig)
				for i in settle:
					await RenderingServer.frame_post_draw
				for j in cams.size():
					var img: Image = (cams[j]["sv"] as SubViewport).get_texture().get_image()
					img.convert(Image.FORMAT_RGB8)
					var vt: Vector2i = cams[j]["tile"]
					strips[j].blit_rect(img, Rect2i(0, 0, vt.x, vt.y), Vector2i(k * vt.x, 0)), res)
			# the rig's events (impact, release, ...) in s from the first frame: the GIF's progress bar marks them
			print("EVENTS %s %s" % [c["id"], JSON.stringify(res.get("events", []))])
			for j in cams.size():
				var path := out_dir.path_join("%s@%s.png" % [c["id"], cams[j]["name"]])
				strips[j].save_png(path)
				(cams[j]["sv"] as SubViewport).queue_free()
			_sun(sun0)
			print("CLIP %s frames=%d views=%d %.1f s" % [c["id"], n, cams.size(), (Time.get_ticks_msec() - t0) / 1000.0])
		print("CLIPS done")
		get_tree().quit()

	## A clip's own sun [azimuth, elevation] (deg; [] keeps it): the light on the side the camera sees. Returns the one before.
	func _sun(ae: Array) -> Array:
		if _tod == null or ae.size() < 2:
			return []
		var cur: Dictionary = _tod.current()
		var before := [float(cur["azim"]), float(cur["elev"])]
		cur["azim"] = float(ae[0])
		cur["elev"] = float(ae[1])
		_tod._apply(cur)
		return before

	## The zoom is shared per group and view (one_zoom: per group whatever the view: the views at the same distance).
	func _zoom_key(c: Dictionary, vw: Dictionary) -> String:
		return String(c.get("group", c["id"])) + ("" if bool(c.get("one_zoom", false)) else "|" + String(vw["name"]))

	# --- the timeline -------------------------------------------------------------------------------------------------------

	## The clip's tile, or the view's own (a GIF whose rows of views are not equally tall).
	func _tile(c: Dictionary, vw: Dictionary = {}) -> Vector2i:
		var t: Array = vw.get("tile", c.get("tile", [300, 360]))
		return Vector2i(int(t[0]), int(t[1]))

	func _aspect(c: Dictionary, vw: Dictionary = {}) -> float:
		var t := _tile(c, vw)
		return float(t.x) / float(t.y)

	func _frames_n(c: Dictionary) -> int:
		return int((c.get("cap", {}) as Dictionary).get("n", 10))

	## The moments filmed (s after the pre-roll): n frames 1/fps apart from t0, or, cyclic, over a whole number of cycles.
	func _cap_times(c: Dictionary, t0: float) -> PackedFloat32Array:
		var cap: Dictionary = c.get("cap", {})
		var fps := float(cap.get("fps", 15.0))
		var n := _frames_n(c)
		var step := 1.0 / fps
		var cyc: Variant = cap.get("cyclic", "")
		var period := 0.0
		if cyc is String and cyc == "gait":
			var s: Dictionary = c.get("setup", {})
			var h := deg_to_rad(float(s.get("heading", 0.0)))
			var kd := lerpf(1.0, 0.62, absf(sin(h))) * lerpf(1.0, 0.75, clampf(-cos(h), 0.0, 1.0))
			period = 1.0 / maxf(RigHeracles._pl(float(s.get("speed", 0.0)), RigHeracles.T_F) / kd, 0.3)
		elif cyc is String and cyc == "swim":
			var mv := smoothstep(0.25, 1.6, float((c.get("setup", {}) as Dictionary).get("speed", 0.0)))
			period = 1.0 / lerpf(0.42, 0.8, mv)
		elif cyc is float or cyc is int:
			period = float(cyc)
		if period > 0.0:
			var cycles := maxf(1.0, roundf(float(n) / fps / period))
			step = cycles * period / float(n)
		var out := PackedFloat32Array()
		for k in n:
			out.append(t0 + step * float(k))
		return out

	## One clip's life: the rig set up and pre-rolled, then the events played and the node carried in fixed steps; `cb` is
	## called (and awaited) at every moment filmed with the rig, the frame's index and the point the cameras follow. Without
	## cap.n the clip lasts until all is over (every event fired, the action and the travel done, on the ground) plus cap.tail
	## (s, 0.25): `res` gets n, t0, t1 and the rig's events (name, s from t0).
	func _simulate(c: Dictionary, cb: Callable, res: Dictionary = {}) -> void:
		var s: Dictionary = c.get("setup", {})
		var cap: Dictionary = c.get("cap", {})
		var rig := RigHeracles.new()
		add_child(rig)
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		var sim := Sim.new()
		sim.stage = self
		sim.rig = rig
		sim.follow_y = String(c.get("follow", "xz")) == "xyz"
		sim.setup(s)
		_props_setup(rig, s)
		# the pre-roll: the gait (or the idle) settled, the cloak hanging as it does by then
		var pre := float(s.get("pre", 1.6))
		var steps := int(round(pre / DT))
		for i in steps:
			sim.step(DT)
		sim.tau = 0.0
		for e in c.get("events", []):
			sim.add(float(e[0]), String(e[1]), (e as Array).slice(2))
		# t0: s after the pre-roll, or "blow:<k>" the moment the k-th blow (0: the first) of the timeline starts
		var t0 := 0.0
		var t0v: Variant = cap.get("t0", 0.0)
		if t0v is String and String(t0v).begins_with("blow:"):
			t0 = sim.blow_time(int(String(t0v).substr(5)))
		else:
			t0 = float(t0v)
		var events: Array = []
		var on_event := func(nm: String) -> void: events.append([nm, snappedf(sim.tau - t0, 0.001)])
		rig.event.connect(on_event)
		var fps := float(cap.get("fps", 15.0))
		if cap.has("n"):
			var times := _cap_times(c, t0)
			for k in times.size():
				while sim.tau < times[k] - 1e-6:
					sim.fire()
					sim.step(minf(DT, times[k] - sim.tau))
				sim.fire()
				if cb.is_valid():
					await cb.call(rig, k, sim.anchor())
			res["n"] = times.size()
			res["t1"] = times[times.size() - 1] if times.size() > 0 else t0
		else:
			var tail := float(cap.get("tail", 0.25))
			var t_done := -1.0
			var k := 0
			var t := t0
			while true:
				while sim.tau < t - 1e-6:
					sim.fire()
					sim.step(minf(DT, t - sim.tau))
				sim.fire()
				if cb.is_valid():
					await cb.call(rig, k, sim.anchor())
				if t_done < 0.0 and sim.done():
					t_done = t
				if (t_done >= 0.0 and t >= t_done + tail - 1e-4) or t > t0 + 12.0:
					break
				k += 1
				t = t0 + float(k) / fps
			res["n"] = k + 1
			res["t1"] = t
		res["t0"] = t0
		res["events"] = events
		rig.event.disconnect(on_event)
		sim.rig = null
		sim.stage = null
		_clear_props()
		remove_child(rig)
		rig.free()

	# --- measuring and framing ----------------------------------------------------------------------------------------------

	## What must stay in the picture (anchor relative, with a radius): the bones, the cloak's particles, the head with its hair
	## and every visible rigid prop's box (sword, shield, spear, scabbard, hands).
	func _points(rig: RigHeracles, anchor: Vector3, out: Array) -> void:
		var gx := rig.global_transform
		for b in rig._bx:
			out.append([gx * b.origin - anchor, 0.12])
		for p in rig._cape_pos:
			out.append([p - anchor, 0.05])
		out.append([rig.head().global_position - anchor, 0.25])
		_rigid_boxes(rig, anchor, out)

	func _rigid_boxes(n: Node, anchor: Vector3, out: Array) -> void:
		for ch in n.get_children():
			if ch is MeshInstance3D:
				var mi := ch as MeshInstance3D
				if mi.skin == null and mi.mesh != null and mi.is_visible_in_tree() and not (mi.mesh is QuadMesh or mi.mesh is PlaneMesh):
					var ab := mi.get_aabb()
					var xf := mi.global_transform
					for k in 8:
						out.append([xf * ab.get_endpoint(k) - anchor, 0.0])
			if ch is Node3D and (ch as Node3D).visible:
				_rigid_boxes(ch, anchor, out)

	func _view(v: Variant) -> Dictionary:
		var out := {}
		if v is String:
			out = (VIEWS.get(v, VIEWS["tq"]) as Dictionary).duplicate()
			out["name"] = v
		else:
			var d: Dictionary = v
			var base := String(d.get("base", d.get("name", "tq")))
			out = (VIEWS.get(base, VIEWS["tq"]) as Dictionary).duplicate()
			out.merge(d, true)
		return out

	## The camera's back (from the aim towards the camera), right and up axes.
	static func _axes(vw: Dictionary) -> Array:
		var y := deg_to_rad(float(vw["yaw"]))
		var p := deg_to_rad(float(vw["pitch"]))
		var b := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
		var r := Vector3(cos(y), 0.0, -sin(y))
		return [b, r, b.cross(r)]

	## Every point in the nominal camera's space: [x, y, depth, radius].
	static func _cam_space(pts: Array, vw: Dictionary) -> Array:
		var ax := _axes(vw)
		var b: Vector3 = ax[0]
		var r: Vector3 = ax[1]
		var u: Vector3 = ax[2]
		var c0 := Vector3(0.0, float(vw["look"]), 0.0) + b * float(vw["dist"])
		var out: Array = []
		for p in pts:
			var rel: Vector3 = (p[0] as Vector3) - c0
			var z := -rel.dot(b)
			if z > 0.3:
				out.append([rel.dot(r), rel.dot(u), z, float(p[1])])
		return out

	## For the half-height tangent t: whether the points fit (with the margin) and where the aim then goes (the middle of
	## what is possible, along the camera's right and up): [ok, a, b].
	static func _feasible(cs: Array, t: float, aspect: float, m: float) -> Array:
		var ky := (1.0 - 2.0 * m) * t
		var kx := ky * aspect
		var alo := -INF
		var ahi := INF
		var blo := -INF
		var bhi := INF
		for q in cs:
			var x: float = q[0]
			var y: float = q[1]
			var z: float = q[2]
			var rr: float = q[3]
			alo = maxf(alo, x - (kx * z - rr))
			ahi = minf(ahi, x + (kx * z - rr))
			blo = maxf(blo, y - (ky * z - rr))
			bhi = minf(bhi, y + (ky * z - rr))
		return [alo <= ahi and blo <= bhi, (alo + ahi) * 0.5, (blo + bhi) * 0.5]

	static func _fit_tan(pts: Array, vw: Dictionary, aspect: float, m: float) -> float:
		if vw.has("fov"):
			return tan(deg_to_rad(float(vw["fov"]) * 0.5))
		var cs := _cam_space(pts, vw)
		var lo := 0.02
		var hi := 2.5
		for i in 40:
			var mid := (lo + hi) * 0.5
			if _feasible(cs, mid, aspect, m)[0]:
				hi = mid
			else:
				lo = mid
		return hi

	## One axis alone (0: across, 1: up): the smallest half extent (tangent, margin not included) that holds every point with
	## the aim centred on them along it (min over the aim of max |x - a| + r over depth).
	static func _fit_axis(cs: Array, axis: int) -> float:
		var lo := 0.0
		var hi := 4.0
		for i in 44:
			var k := (lo + hi) * 0.5
			var alo := -INF
			var ahi := INF
			for q in cs:
				var x: float = q[axis]
				var w: float = k * float(q[2]) - float(q[3])
				alo = maxf(alo, x - w)
				ahi = minf(ahi, x + w)
			if alo <= ahi:
				hi = k
			else:
				lo = k
		return hi

	## The standing hero's height (m, the ground to the top of the hair): a rig at rest, armed, measured once.
	func _hero_height() -> float:
		var rig := RigHeracles.new()
		add_child(rig)
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		rig.set_armed(true, true)
		rig.set_locomotion(0.0, RUN_SPEED)
		for i in 60:
			rig.advance(DT)
		var h := rig.head().global_position.y - rig.global_position.y + 0.22
		remove_child(rig)
		rig.free()
		print("HERO height %.3f m" % h)
		return h

	## The standing hero's height in a view (tangent: the top of the hair over the feet, seen by the view's nominal camera).
	static func _hero_tan(vw: Dictionary, h: float) -> float:
		var cs := _cam_space([[Vector3.ZERO, 0.0], [Vector3(0.0, h, 0.0), 0.0]], vw)
		if cs.size() < 2:
			return 0.4
		return absf(float(cs[1][1]) / float(cs[1][2]) - float(cs[0][1]) / float(cs[0][2]))

	func _frame(pts: Array, vw: Dictionary, aspect: float, m: float, t: float) -> Dictionary:
		var f := _feasible(_cam_space(pts, vw), t, aspect, m)
		# (a zoom fixed from outside that turns out a little tight still centres what is there: a little cut on both sides
		# rather than all of it on one)
		var a := float(f[1]) if is_finite(float(f[1])) else 0.0
		var b := float(f[2]) if is_finite(float(f[2])) else 0.0
		if vw.has("aim"):
			var am: Array = vw["aim"]
			a = float(am[0])
			b = float(am[1])
		return {"t": t, "fov": rad_to_deg(2.0 * atan(t)), "a": a, "b": b, "ok": bool(f[0])}

	# --- cameras --------------------------------------------------------------------------------------------------------------

	## A view's camera in its own SubViewport (the world shared), with the game's toon passes. `j`: the view's index in the clip,
	## the render layer of its edge quad (a full-screen pass: each camera sees its own quad only).
	func _make_cam(c: Dictionary, vw: Dictionary, fr: Dictionary, j: int) -> Dictionary:
		var tile := _tile(c, vw)
		var sv := SubViewport.new()
		sv.size = tile
		sv.world_3d = get_viewport().world_3d
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.msaa_3d = Viewport.MSAA_4X if _arg("msaa", "1") == "1" else Viewport.MSAA_DISABLED
		add_child(sv)
		var cam := Camera3D.new()
		sv.add_child(cam)
		cam.current = true
		cam.fov = float(fr["fov"])
		# the game's toon passes (ink outlines and rim, the grade), as the preview's sheets have them
		var edges := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		edges.mesh = qm
		edges.extra_cull_margin = 16384.0
		edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var edges_mat := ShaderMaterial.new()
		edges_mat.shader = load("res://shaders/toon_edges.gdshader")
		edges_mat.render_priority = 100
		edges.material_override = edges_mat
		edges.position = Vector3(0, 0, -1.0)
		edges.layers = 1 << (EDGE_LAYER0 + j)
		cam.cull_mask = (0xFFFFF & ~EDGE_LAYERS) | edges.layers
		cam.add_child(edges)
		var layer := CanvasLayer.new()
		sv.add_child(layer)
		var rect := ColorRect.new()
		rect.size = Vector2(tile)
		var post_mat := ShaderMaterial.new()
		post_mat.shader = load("res://shaders/toon_post.gdshader")
		rect.material = post_mat
		layer.add_child(rect)
		if _tod:
			var m: Dictionary = _tod.current()
			edges_mat.set_shader_parameter("light_dir", TimeOfDay.dir_from(m["elev"], m["azim"]))
			edges_mat.set_shader_parameter("rim_color", m["rim"])
			edges_mat.set_shader_parameter("rim_strength", m["rim_k"])
			edges_mat.set_shader_parameter("line_tint", m["line"])
			post_mat.set_shader_parameter("bloom", m["bloom"])
			post_mat.set_shader_parameter("sat", m["sat"])
		if c.has("line_far"):
			# (the ink lines and the rim light fade out from half this distance: on the flat ground seen low, the rim reads a
			# farther neighbour everywhere past ~10 m and paints a bright band under the horizon that stops in a straight
			# slant where the sun's direction on screen turns sideways; the bigger the tile, the nearer it starts)
			edges_mat.set_shader_parameter("line_far", float(c["line_far"]))
		var ax := _axes(vw)
		var aim := Vector3(0.0, float(vw["look"]), 0.0) + (ax[1] as Vector3) * float(fr["a"]) + (ax[2] as Vector3) * float(fr["b"])
		return {"sv": sv, "cam": cam, "name": String(vw["name"]), "aim": aim, "back": ax[0], "dist": float(vw["dist"]),
			"tile": tile}

	func _place_cam(cm: Dictionary, anchor: Vector3) -> void:
		var cam: Camera3D = cm["cam"]
		var aim: Vector3 = anchor + (cm["aim"] as Vector3)
		cam.global_position = aim + (cm["back"] as Vector3) * float(cm["dist"])
		cam.look_at(aim, Vector3.UP)

	# --- props: the ledge to climb, the sea to swim in, the chain hung from or zipped along; the ground lowered -------------

	var _props: Array[Node3D] = []
	var _chain: MeshInstance3D
	var _chain_to := Vector3.ZERO
	var _chain_mode := ""

	func _props_setup(rig: RigHeracles, s: Dictionary) -> void:
		var props: Array = s.get("props", [])
		if _ground:
			_ground.position.y = -3.0 if props.has("deep") else 0.0
		for p in props:
			match String(p):
				"ledge":
					var mb := MeshBuilder.new()
					mb.block(Vector3(0.0, -3.0, -0.45 - 1.6), Vector3(3.2, 3.0 + 1.15, 3.2), Color("8E7C68"), Color("A8957A"))
					var mi := MeshInstance3D.new()
					mi.mesh = mb.commit()
					mi.material_override = Materials.lowpoly()
					add_child(mi)
					mi.global_position = rig.global_position
					_props.append(mi)
				"water":
					var w := MeshInstance3D.new()
					var pm := PlaneMesh.new()
					pm.size = Vector2(9.0, 9.0)
					w.mesh = pm
					var mat := StandardMaterial3D.new()
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(0.16, 0.62, 0.72, 0.62)
					w.material_override = mat
					w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(w)
					w.global_position = rig.global_position + Vector3(0.0, rig.swim_waterline, 0.0)
					_props.append(w)
				"chain", "chainup":
					_chain = MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.022
					cm.bottom_radius = 0.022
					cm.height = 1.0
					cm.radial_segments = 6
					cm.rings = 1
					_chain.mesh = cm
					var smat := StandardMaterial3D.new()
					smat.albedo_color = RigHeracles.CHAIN_DARK
					_chain.material_override = smat
					add_child(_chain)
					_props.append(_chain)
					_chain_mode = String(p)

	## The chain from the left fist: straight up to the ring (hanging) or far ahead along the zip.
	func _props_frame(rig: RigHeracles) -> void:
		if _chain == null:
			return
		var a := rig.hand_l().global_position
		var b := a + Vector3(0.0, 2.2, 0.0)
		if _chain_mode == "chain":
			var v := rig.velocity_hint.normalized() if rig.velocity_hint.length() > 0.1 else Vector3(0.0, 0.3, -1.0).normalized()
			b = a + v * 9.0
		var d := b - a
		var mid := (a + b) * 0.5
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		_chain.global_transform = Transform3D(Basis(x, y * d.length(), z), mid)

	func _clear_props() -> void:
		for p in _props:
			p.queue_free()
		_props.clear()
		_chain = null
		_chain_mode = ""


## The state of one clip's timeline: the events still to fire, the node's travel (moves, a jump's arc, a climb), the run under
## the feet (the gait's speed and heading), the heavy blow's charge.
class Sim extends RefCounted:
	var stage: Node3D
	var rig: RigHeracles
	var tau := 0.0
	var follow_y := false
	var queue: Array = []
	var moves: Array = []
	var base := Vector3.ZERO
	var y := 0.0
	var vy := 0.0
	var air := false
	var fall_max := 0.0
	var climbing := false
	var climb_t := 0.0
	var climb_over := 0.8
	var climb_lip := 1.15
	var speed := 0.0
	var heading := 0.0
	var vel3: Variant = null
	var loco: Variant = null
	var ramp_to := -1.0
	var ramp_rate := 0.0
	var charging := false
	var charge_t := 0.0
	var _pos := Vector3.ZERO

	func setup(s: Dictionary) -> void:
		base = rig.position
		rig.set_outfit(StringName(s.get("outfit", "helmet")))
		if s.has("armed"):
			rig.set_armed(int(s["armed"]) == 1, true)
		if s.has("ready"):
			rig.alert = float(s["ready"])
			rig._alert = float(s["ready"])
		rig.set_guard(int(s.get("guard", 0)) == 1)
		rig.set_motion_state(StringName(s.get("state", "ground")))
		# (a body set up in the air hangs there through the pre-roll: `fall` or `jump` starts the arc)
		y = float(s.get("y", 0.0))
		vy = float(s.get("vy", 0.0))
		rig.set_vertical_speed(vy)
		speed = float(s.get("speed", 0.0))
		heading = deg_to_rad(float(s.get("heading", 0.0)))
		if s.has("vel"):
			var v: Array = s["vel"]
			vel3 = Vector3(float(v[0]), float(v[1]), float(v[2]))
		if s.has("loco"):
			loco = float(s["loco"])
		if s.has("spear"):
			rig.set_spear_on_back(int(s["spear"]) == 1)
		if int(s.get("aside", 0)) == 1:
			rig.set_weapons_aside(true)
		if s.has("brush"):
			rig.set_brush(float(s["brush"]), float(s.get("brushh", 1.06)))
		var sets: Dictionary = s.get("set", {})
		for k in sets:
			rig.set(k, sets[k])
		rig.position = base + Vector3(0.0, y, 0.0)
		_pos = rig.position
		var hv := _hint()
		rig.velocity_hint = hv
		var sp := _loco_speed(Vector3(hv.x, 0.0, hv.z).length())
		rig.set_locomotion(sp, RUN_SPEED)
		rig._spd = sp

	func _dir(h: float) -> Vector3:
		return Vector3(sin(h), 0.0, -cos(h))

	func _hint() -> Vector3:
		if vel3 != null:
			var v: Vector3 = vel3
			return rig.global_transform.basis * v if rig.is_inside_tree() else v
		return _dir(heading) * speed

	func _loco_speed(v: float) -> float:
		return float(loco) if loco != null else v

	func anchor() -> Vector3:
		var p := rig.global_position
		if not follow_y:
			p.y = stage.global_position.y
		return p

	## An event at t; a chain of blows and the quick draw into a blow are laid out at once (their moments are fixed: each blow at
	## the `open` key of the one before, the blow at the draw's `go`), so a clip can start at its k-th blow (blow_time).
	func add(t: float, cmd: String, args: Array) -> void:
		if cmd == "chain":
			var names := String(args[0]).split(",")
			var tc := t
			for nm in names:
				add(tc, "blow", [nm])
				var d := _melee(nm)
				tc += float(d["open"]) / float(d["speed"])
			return
		if cmd == "entry":
			var blow := String(args[0])
			var e: Dictionary = RigHeracles.DRAW_INTO.get(blow, {"go": 0.15, "skip": 0.0})
			add(t, "drawinto", [blow])
			add(t + float(e["go"]), "blow", [blow, float(e["skip"])])
			return
		var ev := [t, cmd, args]
		var i := 0
		while i < queue.size() and float(queue[i][0]) <= t:
			i += 1
		queue.insert(i, ev)

	## When the k-th blow of the timeline starts (s).
	func blow_time(k: int) -> float:
		var n := 0
		for e in queue:
			if String(e[1]) == "blow":
				if n == k:
					return float(e[0])
				n += 1
		return 0.0

	## All over: every event fired, the travel and the run's slowing done, on the ground, the action ended (or held at its end).
	func done() -> bool:
		if not queue.is_empty() or air or climbing or charging:
			return false
		if ramp_to >= 0.0 and absf(speed - ramp_to) > 1e-3:
			return false
		for m in moves:
			if tau < float(m["t0"]) + float(m["dur"]) - 1e-4:
				return false
		return rig.action == "" or (rig._hold and rig.action_t >= rig.action_len - 1e-3)

	## Every event due by now.
	func fire() -> void:
		while not queue.is_empty() and float(queue[0][0]) <= tau + 1e-6:
			var e: Array = queue.pop_front()
			_do(String(e[1]), e[2])

	func _a(args: Array, i: int, d: Variant) -> Variant:
		return args[i] if args.size() > i else d

	func _do(cmd: String, args: Array) -> void:
		match cmd:
			"play":
				rig.play_at(String(args[0]), float(_a(args, 1, 1.0)), int(_a(args, 2, 0)) == 1)
			"hold":
				rig.action_hold = float(args[0])
			"at":
				rig.action_t = float(args[0])
			"stop":
				rig.stop_action(float(_a(args, 0, 0.15)))
			"speed":
				speed = float(args[0])
				ramp_to = -1.0
				if args.size() > 1:
					heading = deg_to_rad(float(args[1]))
			"ramp":
				ramp_to = float(args[0])
				ramp_rate = float(args[1])
			"guard":
				rig.set_guard(int(args[0]) == 1)
			"state":
				rig.set_motion_state(StringName(args[0]))
			"vy":
				vy = float(args[0])
				rig.set_vertical_speed(vy)
			"armed":
				rig.set_armed(int(args[0]) == 1, int(_a(args, 1, 0)) == 1)
			"aside":
				rig.set_weapons_aside(int(args[0]) == 1)
			"spear":
				rig.set_spear_on_back(int(args[0]) == 1)
			"set":
				rig.set(String(args[0]), args[1])
			"impact":
				rig.guard_impact(float(args[0]))
			"loco":
				loco = args[0]
			"move":
				moves.append({"t0": tau, "dur": maxf(float(args[1]), 0.001), "dist": float(args[0]),
					"dir": _dir(deg_to_rad(float(_a(args, 2, 0.0)))), "prof": String(_a(args, 3, "sine")), "act": rig.action})
			"blow":
				_blow(String(args[0]), float(_a(args, 1, 0.0)))
			"drawinto":
				# (Hero: the quick draw for a blow pressed with the sword in its scabbard is the one that leads into it)
				rig.draw_into = String(args[0])
				rig.play_at("draw_sword", 1.0, true)
				rig.draw_into = ""
			"roll":
				# Hero._start_dodge with a direction: the roll (the rig's dodge at 0.62 / ROLL_TIME), ROLL_DIST along ROLL_PATH
				rig.play_at("dodge", 0.62 / Hero.ROLL_TIME)
				moves.append({"t0": tau, "dur": Hero.ROLL_TIME, "dist": Hero.ROLL_DIST, "dir": _dir(deg_to_rad(float(_a(args, 0, 0.0)))),
					"prof": "roll"})
			"backstep":
				rig.play_at("backstep", 0.5 / Hero.BACKSTEP_TIME)
				moves.append({"t0": tau, "dur": Hero.BACKSTEP_TIME, "dist": Hero.BACKSTEP_DIST, "dir": _dir(PI), "prof": "back"})
			"knock":
				# a knock-back of v m/s dying at 18 m/s2 (Hero._kb): v^2/36 m in v/18 s
				var v0 := float(args[0])
				moves.append({"t0": tau, "dur": maxf(v0 / 18.0, 0.02), "dist": v0 * v0 / 36.0,
					"dir": _dir(deg_to_rad(float(_a(args, 1, 180.0)))), "prof": "quad"})
			"throw":
				# Hero._start_throw: the throw at THROW_SPEED (upper body on the move); the spear leaves the back for good at the release
				var sp := float(_a(args, 0, Hero.THROW_SPEED))
				rig.play_at("throw", sp, int(_a(args, 1, 0)) == 1)
				add(tau + RigHeracles.THROW_RELEASE / sp, "spear", [0])
			"catch":
				# ChainSpear: the spear flies home into the left fist, which swings it onto the back
				rig.set_spear_on_back(true)
				rig.play_at("catch", 1.0, int(_a(args, 0, 1)) == 1)
			"heavy":
				# HeroMelee.start_charge from the stance, held, then _release_heavy
				rig.play_at("heavy", 1.0, true)
				rig.action_hold = float(HeroMelee.HEAVY["hold"])
				charging = true
				charge_t = 0.0
				add(tau + float(args[0]), "release", [])
			"release":
				charging = false
				rig.charge = 0.0
				rig.play_at("heavy", 1.0, false)
				rig.action_hold = -1.0
				rig.action_t = float(HeroMelee.HEAVY["hold"])
				rig.set_strike_run(false)
				speed = 0.0
			"jump":
				vy = float(_a(args, 0, 8.0))
				air = true
				fall_max = 0.0
				rig.set_motion_state(&"air")
				rig.set_vertical_speed(vy)
				rig.play("jump")
			"fall":
				air = true
				fall_max = 0.0
				rig.set_motion_state(&"air")
			"climb":
				climbing = true
				climb_t = 0.0
				climb_over = float(_a(args, 0, 0.8))
				climb_lip = float(_a(args, 1, Hero.MANTLE_DROP))
				rig.set_motion_state(&"air")
				rig.play("climb")
			_:
				push_warning("anim_gifs: unknown event " + cmd)

	static func _melee(nm: String) -> Dictionary:
		for d in HeroMelee.COMBO_A + HeroMelee.COMBO_B + [HeroMelee.DASH, HeroMelee.HEAVY]:
			if String(d["anim"]) == nm:
				return d
		return {"anim": nm, "speed": 1.0, "open": 0.3, "act0": 0.12, "lunge": 1.2}

	## A blow started as HeroMelee._begin / _aim start it with nobody in reach: the 0.3 m step into it (the dash: a leap that
	## carries the sprint), or, out of a run, the run carried on under it and slowing.
	func _blow(nm: String, skip: float) -> void:
		var d := _melee(nm)
		var spd := float(d["speed"])
		rig.play_at(String(d["anim"]), spd, false)
		if skip > 0.0:
			rig.action_t = skip
		var run := speed
		var dash := nm == "dash"
		var lunge_end := maxf((float(d.get("land", float(d["act0"]) + 0.04 * spd)) - skip) / spd, 0.08)
		var dist := float(HeroMelee.LUNGE_STEP)
		if dash:
			dist = clampf(run * lunge_end * HeroMelee.DASH_FREE, 1.2, float(d["lunge"]))
		var carry := run > HeroMelee.CARRY_MIN and nm != "heavy" and not dash
		rig.set_strike_run(carry)
		if carry:
			ramp_to = 0.0
			ramp_rate = HeroMelee.CARRY_DECEL
			return
		speed = 0.0
		ramp_to = -1.0
		moves.append({"t0": tau + HeroMelee.LUNGE_T0, "dur": maxf(lunge_end - HeroMelee.LUNGE_T0, 0.05), "dist": dist,
			"dir": _dir(0.0), "prof": "sine", "act": rig.action})

	## The share (0..1) of a move covered at u (0..1) of its time: sine (a lunge's ease-out), lin, smooth, quad (a knock-back
	## dying at a constant rate), roll (Hero._roll_s over the dodge's 0.62 action seconds), back (Hero._dodge_s, the backstep).
	static func _prof(p: String, u: float) -> float:
		match p:
			"lin":
				return u
			"smooth":
				return smoothstep(0.0, 1.0, u)
			"quad":
				return 1.0 - (1.0 - u) * (1.0 - u)
			"roll":
				return Hero._roll_s(u * 0.62)
			"back":
				return Hero._dodge_s(u / 0.86)
		return sin(clampf(u, 0.0, 1.0) * PI * 0.5)

	func _travel(at: float) -> Vector3:
		var off := Vector3.ZERO
		for m in moves:
			if at < float(m["t0"]):
				continue
			var u := clampf((at - float(m["t0"])) / float(m["dur"]), 0.0, 1.0)
			off += (m["dir"] as Vector3) * float(m["dist"]) * _prof(String(m["prof"]), u)
		return off

	## One step of h seconds: the run under the feet, the node carried, the gait fed, the rig advanced.
	func step(h: float) -> void:
		if ramp_to >= 0.0:
			speed = move_toward(speed, ramp_to, ramp_rate * h)
		if charging:
			charge_t += h
			var charged := charge_t >= HeroMelee.CHARGE_TIME
			rig.charge = clampf(charge_t / HeroMelee.CHARGE_TIME, 0.0, 1.0) * 0.5 + (0.5 if charged else 0.0)
		var t1 := tau + h
		var off := _travel(t1)
		var land := false
		if air:
			var g := GRAVITY * (FALL_MULT if vy < 0.0 else 1.0)
			vy -= g * h
			y += vy * h
			fall_max = maxf(fall_max, -vy)
			if y <= 0.0 and vy < 0.0:
				y = 0.0
				air = false
				land = true
			rig.set_vertical_speed(vy if air else 0.0)
		if climbing:
			climb_t += h
			y = Hero._mantle_rise(climb_t)
			off += _dir(0.0) * climb_over * smoothstep(Hero.MANTLE_OVER.x, Hero.MANTLE_OVER.y, climb_t)
			rig.climb_lip = climb_lip - y
			if climb_t >= Hero.MANTLE_TIME:
				climbing = false
				base += _dir(0.0) * climb_over
				off -= _dir(0.0) * climb_over
				rig.climb_lip = -99.0
				rig.set_motion_state(&"ground")
		var pos := base + off + Vector3(0.0, y, 0.0)
		var hv := _hint()
		var v := (pos - _pos) / maxf(h, 1e-5) + hv
		rig.velocity_hint = hv
		rig.set_locomotion(_loco_speed(Vector3(v.x, 0.0, v.z).length()), RUN_SPEED)
		rig.position = pos
		_pos = pos
		if land:
			rig.set_motion_state(&"ground")
			if fall_max > 9.0:
				rig.play("land")
		rig.advance(h)
		tau = t1
