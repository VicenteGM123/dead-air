extends Object
## Preview helpers for RigHeracles (art review through tools/preview.tscn):
##   godot --path . res://tools/preview.tscn -- script=res://tools/preview_heracles.gd fns=hero view=back tod=day
## Every function returns a Stage: it adds the toon passes (ink outlines + rim, final grade) to the preview
## camera, places the camera (view=back|tq|side|front|close|closeback|top, yaw=, dist=, fov=, height=) and poses
## the rigs deterministically (pre-simulated with a fixed step, then frozen).
##   fns=hero            one rig; act=<action> at=<0..1> poses it mid-action, speed=<m/s> runs it, outfit=lion
##   fns=strip           act=<action> frames=<n>: the action at n evenly spaced moments, laid out left to right
##   fns=loco            speed=<m/s> frames=<n>: one locomotion cycle
##   fns=lineup          idle, run, guard and the lion outfit side by side
## STOW: armed=1|0 puts the sword and the shield in his hands or away (on his back, in the scabbard) before the pose (default: as the
## rig starts, armed); ready=<0..1> how close a foe is (the armed idle's ready stance). Action rows of a draw start stowed and of a
## sheathe armed by themselves.


class Stage extends Node3D:
	var rigs: Array[RigHeracles] = []
	## Per rig: [action, t (s), speed, state, outfit, guard, vy, phase]
	var setups: Array = []
	var spacing := 1.7
	var _done := false
	var _edges_mat: ShaderMaterial
	var _post_mat: ShaderMaterial

	func add_rig(setup: Array) -> void:
		var r := RigHeracles.new()
		add_child(r)
		_stow_args(r, String(setup[0]))
		rigs.append(r)
		setups.append(setup)

	## STOW: the carrying state the preview asks for (armed=, ready=); a draw starts stowed, a sheathe armed.
	func _stow_args(rig: RigHeracles, act: String) -> void:
		var a := String(Game.arg("armed", ""))
		if act.begins_with("draw"):
			a = "0"
		elif act.begins_with("sheathe"):
			a = "1"
		if a != "":
			rig.set_armed(a == "1", true)
		var rd := String(Game.arg("ready", ""))
		if rd != "":
			rig.alert = float(rd)
			rig._alert = float(rd)

	func _process(_delta: float) -> void:
		if not _done:
			_done = true
			_layout_and_pose()
			_attach_toon()
		_update_toon()

	func _arg(k: String, d: String) -> String:
		return String(Game.arg(k, d))

	func _layout_and_pose() -> void:
		var view := _arg("view", "back")
		var yaw := deg_to_rad(float(_arg("yaw", str(_view_yaw(view)))))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var n := rigs.size()
		for i in n:
			var r := rigs[i]
			r.position = right * (float(i) - float(n - 1) * 0.5) * spacing
			var s: Array = setups[i]
			# FINAL: brush=<0..1> [brushh=<wrist height>] poses the free hand brushing the wheat (RigHeracles.set_brush)
			if _arg("brush", "") != "":
				r.set_brush(float(_arg("brush", "1")), float(_arg("brushh", "1.06")))
			r.preview_pose(s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7])
		_place_camera(view, yaw, n)

	func _view_yaw(view: String) -> float:
		match view:
			"tq":
				return 35.0
			"side":
				return 90.0
			"front", "close":
				return 160.0
			"closeback":
				return 15.0
		return 0.0

	func _place_camera(view: String, yaw: float, n: int) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var width := float(n - 1) * spacing
		var fov := 55.0
		var dist := 5.0
		var height := 2.3
		var look_y := 1.35
		match view:
			"close", "closeback":
				fov = 30.0
				dist = 2.6
				height = 1.75
				look_y = 1.5
			"side", "front", "tq":
				fov = 40.0
				dist = 5.0
				height = 1.6
				look_y = 1.1
			"top":
				fov = 40.0
				dist = 3.0
				height = 5.0
				look_y = 0.5
		if n > 1:
			fov = 30.0
			dist = maxf(dist, (width * 0.5 + 1.2) / tan(deg_to_rad(fov * 0.5)) * 0.62)
			height = 1.4 + dist * 0.12
			look_y = 1.05
		fov = float(_arg("fov", str(fov)))
		dist = float(_arg("dist", str(dist)))
		height = float(_arg("height", str(height)))
		look_y = float(_arg("look", str(look_y)))
		cam.fov = fov
		var back := Vector3(sin(yaw), 0, cos(yaw))
		cam.global_position = back * dist + Vector3(0, height, 0)
		cam.look_at(Vector3(0, look_y, 0), Vector3.UP)

	func _attach_toon() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or _arg("notoon", "0") == "1":
			return
		var edges := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		edges.mesh = qm
		edges.extra_cull_margin = 16384.0
		edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_edges_mat = ShaderMaterial.new()
		_edges_mat.shader = load("res://shaders/toon_edges.gdshader")
		_edges_mat.render_priority = 100
		edges.material_override = _edges_mat
		edges.position = Vector3(0, 0, -1.0)
		cam.add_child(edges)
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_post_mat = ShaderMaterial.new()
		_post_mat.shader = load("res://shaders/toon_post.gdshader")
		rect.material = _post_mat
		layer.add_child(rect)

	func _update_toon() -> void:
		if _edges_mat == null:
			return
		var tod: TimeOfDay = null
		for ch in get_parent().get_children():
			if ch is TimeOfDay:
				tod = ch
		if tod == null:
			return
		var m: Dictionary = tod.current()
		if m.is_empty():
			return
		var to_light := TimeOfDay.dir_from(m["elev"], m["azim"])
		_edges_mat.set_shader_parameter("light_dir", to_light)
		_edges_mat.set_shader_parameter("rim_color", m["rim"])
		_edges_mat.set_shader_parameter("rim_strength", m["rim_k"])
		_edges_mat.set_shader_parameter("line_tint", m["line"])
		_post_mat.set_shader_parameter("bloom", m["bloom"])
		_post_mat.set_shader_parameter("sat", m["sat"])


static func _a(k: String, d: String) -> String:
	return String(Game.arg(k, d))


static func _setup_from_args(t_norm: float) -> Array:
	var act := _a("act", "")
	return [act, t_norm, float(_a("speed", "0")), StringName(_a("state", "ground")), StringName(_a("outfit", "helmet")),
		_a("guard", "0") == "1", float(_a("vy", "0")), float(_a("phase", "0"))]


static func hero(_seed: int) -> Node3D:
	var st := Stage.new()
	st.add_rig(_setup_from_args(float(_a("at", "0.5"))))
	return st


static func strip(_seed: int) -> Node3D:
	var st := Stage.new()
	var n := int(_a("frames", "6"))
	st.spacing = float(_a("spacing", "1.5"))
	for i in n:
		st.add_rig(_setup_from_args(float(i) / float(maxi(n - 1, 1))))
	return st


static func loco(_seed: int) -> Node3D:
	var st := Stage.new()
	var n := int(_a("frames", "6"))
	st.spacing = float(_a("spacing", "1.5"))
	for i in n:
		var s := _setup_from_args(0.0)
		s[0] = ""
		s[7] = float(i) / float(n)
		st.add_rig(s)
	return st


static func lineup(_seed: int) -> Node3D:
	var st := Stage.new()
	st.spacing = 1.6
	st.add_rig(["", 0.0, 0.0, &"ground", &"helmet", false, 0.0, 0.0])
	st.add_rig(["", 0.0, 5.5, &"ground", &"helmet", false, 0.0, 0.3])
	st.add_rig(["", 0.0, 0.0, &"ground", &"helmet", true, 0.0, 0.0])
	st.add_rig(["", 0.0, 0.0, &"ground", &"lion", false, 0.0, 0.0])
	return st


## Contact sheet renderer: rows of tiles rendered off-screen (SubViewport sharing the preview's world, with the
## toon passes) and composited into one PNG, all in one run.
##   fns=sheet rows=<row>;<row>... cols=<n> tile=<w>x<h> view=tq out=<png> [label=1]
## A row is `attack1` (the action at n evenly spaced moments), `chain:a1,a2,a3,a4` (a combo string as HeroMelee chains it:
## each blow starts at the one before's `open` key, blended in like the game does; `chain:dash` after a run of SPEED m/s;
## lunge= moves the hero each blow as a lunge would), `loco:5.5` (a run cycle at 5.5 m/s), `idle`,
## `guard`, `air:<vy>`, `swim:<speed>`, `zip`, `hang`, `strafe:<speed>` / `strafel:<speed>` / `back:<speed>` (the gait going
## sideways right / left, backwards), `guardback:<speed>`, `guardstrafe:<speed>`, optionally followed by @view and @outfit, e.g. `attack1@back`,
## `idle@front@lion`. Tile views: back, tq, side, front, close, closeback, sidel, low.
## Per view, yaw_<view>= dist_<view>= height_<view>= look_<view>= fov_<view>= override its camera (e.g. `game` with fov_game=26
## is the gameplay camera cropped to the hero); the stage's sun_azim= / sun_elev= (tools/preview.gd) turn the sun.
class SheetStage extends Node3D:
	var _head_yaw := 160.0
	var sv: SubViewport
	var cam: Camera3D
	var edges_mat: ShaderMaterial
	var post_mat: ShaderMaterial

	## STOW: the carrying state the preview asks for (armed=, ready=); a draw starts stowed, a sheathe armed.
	func _stow_args(rig: RigHeracles, act: String) -> void:
		var a := String(Game.arg("armed", ""))
		if act.begins_with("draw"):
			a = "0"
		elif act.begins_with("sheathe"):
			a = "1"
		if a != "":
			rig.set_armed(a == "1", true)
		var rd := String(Game.arg("ready", ""))
		if rd != "":
			rig.alert = float(rd)
			rig._alert = float(rd)

	func _ready() -> void:
		_run.call_deferred()

	func _arg(k: String, d: String) -> String:
		return String(Game.arg(k, d))

	func _run() -> void:
		var ts := _arg("tile", "420x480").split("x")
		var tw := int(ts[0])
		var th := int(ts[1])
		var rows := _arg("rows", "attack1").split(";", false)
		var cols := int(_arg("cols", "6"))
		sv = SubViewport.new()
		sv.size = Vector2i(tw, th)
		sv.world_3d = get_viewport().world_3d
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.msaa_3d = Viewport.MSAA_4X if _arg("msaa", "1") == "1" else Viewport.MSAA_DISABLED
		add_child(sv)
		cam = Camera3D.new()
		sv.add_child(cam)
		cam.current = true
		var edges := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		edges.mesh = qm
		edges.extra_cull_margin = 16384.0
		edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		edges_mat = ShaderMaterial.new()
		edges_mat.shader = load("res://shaders/toon_edges.gdshader")
		edges_mat.render_priority = 100
		edges.material_override = edges_mat
		edges.position = Vector3(0, 0, -1.0)
		cam.add_child(edges)
		var layer := CanvasLayer.new()
		sv.add_child(layer)
		var rect := ColorRect.new()
		rect.size = Vector2(tw, th)
		post_mat = ShaderMaterial.new()
		post_mat.shader = load("res://shaders/toon_post.gdshader")
		rect.material = post_mat
		layer.add_child(rect)
		await get_tree().process_frame
		_toon_params()
		var sheet := Image.create(tw * cols, th * rows.size(), false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.1, 0.1, 0.12))
		for ri in rows.size():
			var spec := rows[ri].split("@")
			var what := spec[0]
			var view := spec[1] if spec.size() > 1 else _arg("view", "tq")
			var out_name := StringName(spec[2]) if spec.size() > 2 else &"helmet"
			for ci in cols:
				var rig := RigHeracles.new()
				add_child(rig)
				_stow_args(rig, what.split(":")[1] if what.begins_with("views") and what.split(":").size() > 1 else what.split(":")[0])
				var k := float(ci) / float(maxi(cols - 1, 1))
				var tile_view := view
				if what.begins_with("heads"):
					# (LOOK2) heads[:<outfit pose>]: the idle head up close, turning round it column by column (front, 3/4, side,
					# 3/4 back, back, the other side)
					var hy := [160.0, 205.0, 250.0, 300.0, 0.0, 90.0, 130.0, 30.0]
					_pose(rig, "idle", 0.0, 0.0, out_name)
					tile_view = "head"
					_head_yaw = hy[ci % hy.size()]
				elif what.begins_with("views"):
					# views:<action|idle|loco|guard>[:<t or speed>] one pose seen from every side
					var vp := what.split(":")
					var vlist := ["back", "tq", "side", "front", "close", "closeback", "tql", "low", "game"]
					tile_view = vlist[ci % vlist.size()]
					var act := vp[1] if vp.size() > 1 else "idle"
					var arg := float(vp[2]) if vp.size() > 2 else 0.5
					if act == "idle":
						_pose(rig, "idle", 0.0, 0.0, out_name)
					elif act == "loco":
						rig.preview_pose("", 0.0, arg, &"ground", out_name, false, 0.0, 0.3)
					elif act == "guard":
						rig.preview_pose("", 0.0, 0.0, &"ground", out_name, true, 0.0, 0.0)
					elif act == "hang":
						rig.preview_pose("", 0.0, 0.0, &"hang", out_name, false, 0.0, 0.0)
					else:
						rig.preview_pose(act, arg, 0.0, &"ground", out_name, false, 0.0, 0.0)
				else:
					_pose(rig, what, k, float(ci) / float(cols), out_name)
				_place(tile_view, rig)
				for f in int(_arg("settle", "2")):
					await RenderingServer.frame_post_draw
				var img := sv.get_texture().get_image()
				img.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i(ci * tw, ri * th))
				rig.queue_free()
				await get_tree().process_frame
		var out := _arg("out", "user://sheet.png")
		sheet.save_png(out)
		print("SHEET saved ", out)
		get_tree().quit()

	func _pose(rig: RigHeracles, what: String, k: float, ph: float, out_name: StringName) -> void:
		var p := what.split(":")
		var nm := p[0]
		var val := float(p[1]) if p.size() > 1 else 0.0
		match nm:
			"idle":
				rig.preview_pose("", 0.0, 0.0, &"ground", out_name, false, 0.0, ph)
				rig.t_offset(ph * 6.0)
			"guard":
				rig.preview_pose("", 0.0, val, &"ground", out_name, true, 0.0, ph)
			"loco":
				rig.preview_pose("", 0.0, val, &"ground", out_name, false, 0.0, ph)
			"strafe":
				# sideways to the right (a locked-on circle)
				rig.preview_pose("", 0.0, val, &"ground", out_name, false, 0.0, ph, PI * 0.5)
			"strafel":
				rig.preview_pose("", 0.0, val, &"ground", out_name, false, 0.0, ph, -PI * 0.5)
			"back":
				rig.preview_pose("", 0.0, val, &"ground", out_name, false, 0.0, ph, PI)
			"guardback":
				rig.preview_pose("", 0.0, val, &"ground", out_name, true, 0.0, ph, PI)
			"guardstrafe":
				rig.preview_pose("", 0.0, val, &"ground", out_name, true, 0.0, ph, -PI * 0.5)
			"air":
				rig.preview_pose("", 0.0, 3.0, &"air", out_name, false, lerpf(4.0, -6.0, k), 0.0)
			"swim":
				rig.preview_pose("", 0.0, val, &"swim", out_name, false, 0.0, ph)
				_add_water(rig)
			"zip":
				rig.preview_pose("", 0.0, 9.0, &"zip", out_name, false, 0.0, ph)
			"hang":
				rig.preview_pose("", 0.0, 0.0, &"hang", out_name, false, 0.0, ph)
				rig.t_offset(ph * 6.0)
			"idlelong":
				# STOW: standing on for `val` s more, simulated (the weight shifts, the hand comes to rest on the pommel)
				rig.preview_pose("", 0.0, 0.0, &"ground", out_name, false, 0.0, ph)
				for i in int(maxf(val, 0.0) * 60.0 * (0.4 + 0.6 * k)):
					rig.advance(1.0 / 60.0)
			"chain":
				_pose_chain(rig, p[1].split(","), k, out_name, float(p[2]) if p.size() > 2 else float(_arg("speed", "0")))
			"entry":
				# INTEGRATE: `entry:<blow>[:<speed>]` a blow pressed with the sword in its scabbard, as Hero plays it: the quick draw that
				# leads into it, then the blow from its `skip` (et0= / et1= the window shown, in seconds from the press)
				_pose_entry(rig, p[1], k, out_name, float(p[2]) if p.size() > 2 else 0.0)
			_:
				# (an action row may name the speed the hero runs at when it starts: `attack1:5.5`)
				# (INTEGRATE: guard=1 holds the guard through the pre-roll: the action starts from the P7 guard, as a parry does)
				rig.preview_pose(nm, _action_k(nm, k), val, &"ground", out_name, _arg("guard", "0") == "1", 0.0, 0.0, 0.0, float(_arg("lunge", "0")))

	## A combo string at the fraction k of its whole length: each blow is played at the time HeroMelee chains it (the blow
	## before's `open` key), the hero lunging `lunge` m into each (preview: the node moves, then is put back for the picture).
	func _pose_chain(rig: RigHeracles, names: PackedStringArray, k: float, out_name: StringName, spd: float = 0.0) -> void:
		var opens := {}
		for d in HeroMelee.COMBO_A + HeroMelee.COMBO_B + [HeroMelee.DASH, HeroMelee.HEAVY]:
			opens[String(d["anim"])] = float(d["open"])
		var starts: Array[float] = []
		var t := 0.0
		for i in names.size():
			starts.append(t)
			if names[i].begins_with("+"):
				# (INTEGRATE: `+<s>` nothing for that long after the blow before has ended: its recovery into the idle or the run)
				t += float(names[i].substr(1))
				continue
			var d := RigHeracles.act_def(names[i])
			var last := i == names.size() - 1 or names[i + 1].begins_with("+")
			t += float(d["len"]) if last else float(opens.get(names[i], d["len"]))
		var total := t
		var target := k * total * 0.999
		if _arg("ct1", "") != "":
			# (INTEGRATE: ct0= / ct1= the window shown, in seconds from the first blow's start)
			target = float(_arg("ct0", "0")) + k * (float(_arg("ct1", "0")) - float(_arg("ct0", "0")))
		rig.preview_pose("", 0.0, spd, &"ground", out_name, false, 0.0, 0.0)
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		var lunge := float(_arg("lunge", "0"))
		var base := rig.global_position
		var fwd := -rig.global_transform.basis.z
		var dt := 1.0 / 60.0
		var now := 0.0
		var cur := -1
		var done := 0.0
		var ln := 0.0
		while now <= target + 1e-6:
			var nxt := cur + 1
			if nxt < names.size() and now >= starts[nxt] - 1e-6 and names[nxt].begins_with("+"):
				cur = nxt
				done += ln
				ln = 0.0
			elif nxt < names.size() and now >= starts[nxt] - 1e-6:
				cur = nxt
				done += ln
				ln = lunge * (2.4 if names[cur] == "dash" else 1.0)
				rig.play(names[cur])
				rig.set_strike_run(spd > 2.5 and lunge <= 0.0)
				if cur == 0:
					rig._blend_t = 1.0
					rig._io_pending = false
					rig._io_on = false
			if cur >= 0 and lunge > 0.0:
				var d := RigHeracles.act_def(names[cur])
				var l_end := float(d["ev"].get("swing", 0.12)) + 0.04
				var u := clampf((now - starts[cur] - 0.02) / maxf(l_end - 0.02, 0.05), 0.0, 1.0)
				rig.global_position = base + fwd * (done + ln * sin(u * PI * 0.5))
			var step := minf(dt, target - now)
			if step <= 1e-6:
				break
			rig.advance(step)
			now += step
		rig.global_position = base

	## INTEGRATE: the press of a blow with the sword in its scabbard at the fraction k of the window et0..et1 (s from the press;
	## default the whole draw and blow): stowed (moving at `spd`), the draw that leads into `blow`, the blow from its `skip` at `go`.
	func _pose_entry(rig: RigHeracles, blow: String, k: float, out_name: StringName, spd: float) -> void:
		var e: Dictionary = RigHeracles.DRAW_INTO.get(blow, {"go": 0.15, "skip": 0.0})
		var go := float(e["go"])
		var skip := float(e["skip"])
		var total := go + float(RigHeracles.act_def(blow)["len"]) - skip
		var w0 := float(_arg("et0", "0"))
		var w1 := float(_arg("et1", str(total)))
		var target := w0 + k * (w1 - w0)
		rig.preview_pose("", 0.0, spd, &"ground", out_name, false, 0.0, 0.0, 0.0, 0.0, 0)
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		rig.draw_into = blow
		rig.play_at("draw_sword", 1.0, true)
		rig.draw_into = ""
		var dt := 1.0 / 60.0
		var now := 0.0
		var started := false
		while now < target - 1e-6:
			if not started and now >= go - 1e-6:
				started = true
				rig.play(blow)
				rig.action_t = skip
				rig.set_strike_run(spd > 2.5)
			var step := minf(dt, target - now)
			rig.advance(step)
			now += step

	## Action rows show the action's own seconds t0..t1 across the columns (t0=, t1= in the preview args; default the
	## whole action), so a blow's 0.2 s of contact can be looked at frame by frame.
	func _action_k(act: String, k: float) -> float:
		var t0s := _arg("t0", "")
		var t1s := _arg("t1", "")
		if t0s == "" and t1s == "":
			return k
		var d := RigHeracles.act_def(act)
		if d.is_empty():
			return k
		var alen := float(d["len"])
		var t0 := float(t0s) if t0s != "" else 0.0
		var t1 := float(t1s) if t1s != "" else alen
		return clampf((t0 + k * (t1 - t0)) / alen, 0.0, 1.0)

	## A sea surface at the rig's waterline (preview only: translucent so the stroke under it shows).
	func _add_water(rig: RigHeracles) -> void:
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(6.0, 6.0)
		w.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.16, 0.62, 0.72, 0.62)
		w.material_override = m
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = Vector3(0, rig.swim_waterline, 0)
		rig.add_child(w)

	func _place(view: String, rig: RigHeracles) -> void:
		var yaw := 35.0
		var dist := 3.9
		var height := 1.55
		var look := 1.0
		cam.fov = 38.0
		match view:
			"back":
				yaw = 0.0
				height = 2.0
				look = 1.15
			"side":
				yaw = 90.0
			"sidel":
				yaw = -90.0
			"front":
				yaw = 160.0
			"tql":
				yaw = -35.0
			"close":
				yaw = 155.0
				dist = 2.1
				height = 1.75
				look = 1.5
			"closeback":
				yaw = 20.0
				dist = 2.1
				height = 1.85
				look = 1.45
			"hand", "handf", "handb":
				# the sword hand's close-up (step 2, the strikes: the wrist, the blade's angle to the forearm): the camera follows the
				# hand from his right side (hand), from the front-right (handf) or from behind (handb)
				var hw: Vector3 = rig.global_transform * rig._bx[RigHeracles.HAND_R].origin
				var hr := deg_to_rad(90.0 if view == "hand" else (140.0 if view == "handf" else 15.0))
				cam.fov = 34.0
				cam.global_position = hw + Vector3(sin(hr), 0.18, cos(hr)) * 1.45
				cam.look_at(hw + Vector3(0, -0.02, 0), Vector3.UP)
				return
			"low":
				yaw = 45.0
				height = 0.5
				look = 0.8
			"head":
				# (LOOK2: the head and the hair up close; yaw_head= turns round it)
				yaw = _head_yaw
				dist = 1.05
				height = 1.82
				look = 1.74
			# STOW: close on the left hip from his left (hipl), from behind (hipb), on his back (backc)
			"hipl":
				yaw = -90.0
				dist = 2.4
				height = 1.05
				look = 0.75
			"hipb":
				yaw = -20.0
				dist = 2.6
				height = 1.3
				look = 0.85
			"backc":
				yaw = 10.0
				dist = 2.7
				height = 1.75
				look = 1.25
			"gamec":
				yaw = 0.0
				dist = 3.3
				height = 2.05
				look = 1.2
				cam.fov = 50.0
			"tqlc":
				yaw = -40.0
				dist = 2.9
				height = 1.5
				look = 1.1
			"top":
				yaw = 2.0
				dist = 0.5
				height = 4.6
				look = 1.0
			"game":
				yaw = 0.0
				dist = 5.0
				height = 2.3
				look = 1.35
				cam.fov = 55.0
		# (LOOK lane, local only: yaw_<view>=deg overrides a view's yaw)
		yaw = float(_arg("yaw_" + view, str(yaw)))
		# (SHIP, 2026-10-17) dist_/height_/look_/fov_<view> frame a view (the client's sheets: aspecto, poses, golpes)
		dist = float(_arg("dist_" + view, str(dist)))
		height = float(_arg("height_" + view, str(height)))
		look = float(_arg("look_" + view, str(look)))
		cam.fov = float(_arg("fov_" + view, str(cam.fov)))
		var r := deg_to_rad(yaw)
		cam.global_position = rig.global_position + Vector3(sin(r), 0, cos(r)) * dist + Vector3(0, height, 0)
		cam.look_at(rig.global_position + Vector3(0, look, 0), Vector3.UP)

	func _toon_params() -> void:
		var tod: TimeOfDay = null
		for ch in get_parent().get_children():
			if ch is TimeOfDay:
				tod = ch
		if tod == null:
			return
		var m: Dictionary = tod.current()
		var to_light := TimeOfDay.dir_from(m["elev"], m["azim"])
		edges_mat.set_shader_parameter("light_dir", to_light)
		edges_mat.set_shader_parameter("rim_color", m["rim"])
		edges_mat.set_shader_parameter("rim_strength", m["rim_k"])
		edges_mat.set_shader_parameter("line_tint", m["line"])
		post_mat.set_shader_parameter("bloom", m["bloom"])
		post_mat.set_shader_parameter("sat", m["sat"])


static func sheet(_seed: int) -> Node3D:
	return SheetStage.new()
