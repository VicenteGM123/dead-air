extends Object
## Static helpers so tools/preview.tscn can show the bestiary rigs (RigWolf, RigBoar, RigLion) in the toon look.
##   FRAMES=20 preview.sh <proj> out.png script=res://tools/preview_beasts.gd fns=wolf_pack cam=game
## Args read here (besides preview.gd's cam/yaw/zoom/tod):
##   beast=wolf|boar|lion  variant=N      which rig (wolf_* / beast_* helpers)
##   act=<action> at=<seconds>             frozen pose at that time of the action (beast_pose)
##   move=<m/s> at=<seconds>               frozen locomotion frame (beast_pose with no act)
##   strip=<action> frames=N               a row of N frozen frames across the action (beast_strip)
##   alert=0..1                            menacing stance (wolves circling, the lion's stalk) on frozen rigs
##   human=1                               adds the 1.9 m human silhouette next to it
##   toon=0                                no toon outlines / post (raw shading; the game's own ToonScreen, when the
##                                         preview scene has one, is left alone)
##   campos=x,y,z camat=x,y,z fov=deg      a fixed camera instead of the auto-framed one (close-ups)
##   views=0,45,90                         (fn views) copies of the beast turned by these yaws, side by side

const BEASTS := {
	"wolf": "res://scripts/gfx/rig_wolf.gd",
	"boar": "res://scripts/gfx/rig_boar.gd",
	"lion": "res://scripts/gfx/rig_lion.gd",
}


static func _arg(k: String, d: String) -> String:
	return String(Game.arg(k, d))


## A new rig of `kind` (variant for wolves).
static func make(kind: String, variant: int = 0) -> Rig:
	var path: String = BEASTS.get(kind, BEASTS["wolf"])
	if not ResourceLoader.exists(path):
		return null
	var scr: Script = load(path)
	var r: Rig = scr.new(variant) if kind == "wolf" else scr.new()
	return r


## Freezes `r` at `at` seconds into `act` (or a locomotion frame at speed `mv`) once it is in the tree.
static func freeze(r: Rig, act: String, at: float, mv: float) -> void:
	r.ready.connect(func() -> void:
		if _arg("alert", "") != "" and r.has_method("set_alert"):
			r.call("set_alert", float(_arg("alert", "0")))
		r.debug_seek(act, at, mv)
		r.process_mode = Node.PROCESS_MODE_DISABLED)


static func _root_with_toon() -> Node3D:
	var root := Node3D.new()
	if _arg("toon", "1") != "0":
		root.add_child(ToonView.new())
	root.add_child(HaloRefresh.new())
	if _arg("campos", "") != "":
		var cam := Camera3D.new()
		cam.fov = float(_arg("fov", "30"))
		cam.current = true
		root.add_child(cam)
		var cp := _vec(_arg("campos", "0,1,4"))
		var ca := _vec(_arg("camat", "0,0.8,0"))
		cam.ready.connect(func() -> void:
			cam.global_position = cp
			cam.look_at(ca, Vector3.UP)
			cam.make_current())
	return root


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]) if p.size() > 1 else 0.0, float(p[2]) if p.size() > 2 else 0.0)


static func _label(parent: Node3D, text: String, pos: Vector3, size: float = 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = 0.0045 * size
	l.font_size = 48
	l.outline_size = 12
	l.modulate = Color("FFF6E3")
	l.outline_modulate = Color("1E1A2B")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	# deferred: labels may be added from a child's ready callback, while the parent is still busy
	parent.add_child.call_deferred(l)


# --- single rigs -------------------------------------------------------------------------------------------

static func wolf(_seed: int) -> Node3D:
	return _single("wolf", int(_arg("variant", "0")))


static func boar(_seed: int) -> Node3D:
	return _single("boar", 0)


static func lion(_seed: int) -> Node3D:
	return _single("lion", 0)


static func beast(_seed: int) -> Node3D:
	return _single(_arg("beast", "wolf"), int(_arg("variant", "0")))


static func _single(kind: String, variant: int) -> Node3D:
	var root := _root_with_toon()
	var r := make(kind, variant)
	root.add_child(r)
	var act := _arg("act", "")
	var mv := float(_arg("move", "0"))
	if act != "" or mv > 0.0 or _arg("at", "") != "":
		freeze(r, act, float(_arg("at", "0.5")), mv)
	if _arg("human", "0") == "1":
		var h := human(0)
		h.position = Vector3(0, 0, float(_arg("hz", "1.3")))
		root.add_child(h)
	if _arg("face", "0") == "1":
		face_cam(root, r)
	return root


## Close-up camera on the head of `r` once it is posed (face=1): seen from fyaw degrees around the beast
## (0 = straight in front of it, 90 = its right side, 180 = behind), fpitch degrees above the head, fdist
## metres away, ffov degrees; fup raises the aim point. Becomes the current camera (preview.gd's stays idle).
static func face_cam(root: Node3D, r: Rig) -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = float(_arg("ffov", "30"))
	root.add_child(cam)
	r.ready.connect(func() -> void:
		var h: Node3D = r.call("head")
		var target := root.to_local(h.global_position) + Vector3(0, float(_arg("fup", "0")), 0)
		var a := deg_to_rad(float(_arg("fyaw", "0")))
		var p := deg_to_rad(float(_arg("fpitch", "8")))
		var d := Vector3(sin(a) * cos(p), sin(p), -cos(a) * cos(p))
		cam.look_at_from_position(root.to_global(target + d * float(_arg("fdist", "2.6"))), root.to_global(target), Vector3.UP))


## Same as beast() but the rig is not frozen (it animates: idle, or set_locomotion(move)).
static func beast_live(_seed: int) -> Node3D:
	var root := _root_with_toon()
	var r := make(_arg("beast", "wolf"), int(_arg("variant", "0")))
	root.add_child(r)
	r.set_locomotion(float(_arg("move", "0")), 8.0)
	return root


## Copies of one beast side by side along X, turned by the yaws in views= (degrees; 0 = facing +Z, i.e. looking
## at a camera placed on +Z), all frozen at the same pose (act= at= or move=). gap= spacing.
static func views(_seed: int) -> Node3D:
	var root := _root_with_toon()
	var yaws := _arg("views", "180,135,90").split(",")
	var gap := float(_arg("gap", "1.6"))
	for i in yaws.size():
		var r := make(_arg("beast", "lion"), int(_arg("variant", "0")))
		r.position = Vector3((float(i) - float(yaws.size() - 1) * 0.5) * gap, 0, 0)
		r.rotation.y = deg_to_rad(float(yaws[i]))
		root.add_child(r)
		freeze(r, _arg("act", ""), float(_arg("at", "1.0")), float(_arg("move", "0")))
	return root


## The three wolf coats side by side (grey, dark alpha, pale), frozen at a common idle moment.
static func wolf_pack(_seed: int) -> Node3D:
	var root := _root_with_toon()
	for v in 3:
		var r := make("wolf", v)
		r.position = Vector3(float(v - 1) * 1.25, 0, float(v % 2) * 0.6)
		r.rotation.y = 0.35 - 0.3 * float(v)
		root.add_child(r)
		freeze(r, "", 1.3 + float(v) * 0.7, 0.0)
	return root


## A row of frozen frames across one action (strip=<action> frames=N), or locomotion (strip=walk|trot|run|stalk|
## charge_run). times=0,0.3,0.5 picks the frames as fractions of the action (default: evenly spaced); side=1|-1 is
## the side a hit / stagger / death comes from (the same for every frame); alert= as for beast(). Labels give the
## time in seconds.
static func beast_strip(_seed: int) -> Node3D:
	var root := _root_with_toon()
	var kind := _arg("beast", "wolf")
	var act := _arg("strip", "bite")
	var gap := float(_arg("gap", "1.5"))
	var loco := {"walk": 1.3, "trot": 3.4, "run": 8.0, "stalk": 0.9, "charge_run": 7.0}
	var length := float(_arg("span", "0"))
	var side := float(_arg("side", "1"))
	var fr: Array = []
	if _arg("times", "") != "":
		for t in _arg("times", "").split(","):
			fr.append(float(t))
	else:
		var n := int(_arg("frames", "6"))
		for i in n:
			fr.append(float(i) / float(maxi(n - 1, 1)))
	var mv := 0.0
	if loco.has(act):
		mv = float(_arg("speed", str(loco[act])))
		if length <= 0.0:
			length = 0.6
	for i in fr.size():
		var r := make(kind, int(_arg("variant", "0")))
		var along := Vector3(1, 0, 0) if _arg("axis", "z") == "x" else Vector3(0, 0, 1)
		r.position = along * (float(i) * gap)
		root.add_child(r)
		var frac: float = fr[i]
		var lp := r.position + Vector3(0, float(_arg("ly", "1.35")), 0)
		if mv > 0.0:
			if act == "stalk" and r.has_method("set_alert"):
				r.call("set_alert", 1.0)
			freeze(r, "", 1.5 + frac * length, mv)
			_label(root, "%.2f s" % (frac * length), lp)
		else:
			var rr := r
			r.ready.connect(func() -> void:
				# the action table exists once the rig is ready: its length (one cycle for loops) sets the span
				var full := rr.play(act)
				rr.action = ""
				var span := length if length > 0.0 else full
				if rr.has_method("set_hit_dir"):
					rr.call("set_hit_dir", Vector3(side, 0, 0))
				if _arg("alert", "") != "" and rr.has_method("set_alert"):
					rr.call("set_alert", float(_arg("alert", "0")))
				rr.debug_seek(act, frac * span, 0.0)
				rr.process_mode = Node.PROCESS_MODE_DISABLED
				_label(root, "%.2f s" % (frac * span), lp))
	return root


## Telegraph check: copies of a beast facing the camera, frozen at poses=act:seconds,... (empty act = idle), seen
## exactly like the game's follow camera (CameraRig: 5.5 m behind a 1.55 m shoulder pivot, pitch -14, fov 60) with
## the beasts dist= metres (default 10) from the camera, and a 1.9 m hero stand-in where the hero would stand.
static func telegraph(_seed: int) -> Node3D:
	var root := _root_with_toon()
	var kind := _arg("beast", "wolf")
	var poses := _arg("poses", ":0,bite:0.34,lunge:0.38").split(",")
	var gap := float(_arg("gap", "2.6"))
	var dist := float(_arg("dist", "10"))
	var n := poses.size()
	for i in n:
		var pp := poses[i].split(":")
		var r := make(kind, int(_arg("variant", "0")))
		r.position = Vector3((float(i) - float(n - 1) * 0.5) * gap, 0, 0)
		r.rotation.y = PI
		root.add_child(r)
		freeze(r, pp[0], float(pp[1]) if pp.size() > 1 else 1.0, 0.0)
		_label(root, pp[0] if pp[0] != "" else "idle", r.position + Vector3(0, float(_arg("ly", "1.5")), 0), 2.2)
	var arm := 5.5
	var pitch := deg_to_rad(-14.0)
	var cam_z := dist
	var hero_z := cam_z - arm * cos(pitch)
	if _arg("human", "1") == "1":
		var h := human(0)
		h.position = Vector3(float(_arg("hx", "-3.6")), 0, hero_z)
		root.add_child(h)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.current = true
	root.add_child(cam)
	cam.ready.connect(func() -> void:
		cam.global_position = Vector3(0, 1.55 + arm * sin(-pitch), cam_z)
		cam.rotation = Vector3(pitch, 0, 0)
		cam.make_current())
	return root


## All beasts next to a 1.9 m human silhouette, lined up nose to tail along -Z (side view: cam=low yaw=90).
static func size_compare(_seed: int) -> Node3D:
	var root := _root_with_toon()
	var h := human(0)
	root.add_child(h)
	_label(root, "1.9 m", Vector3(0, 2.15, 0), 0.8)
	var z := -0.7
	for kind in ["wolf", "boar", "lion"]:
		var r := make(kind, 0)
		if r == null:
			continue
		# half length nose to rump, and the tail behind it (the beasts face -Z, tails towards the previous one)
		var half := {"wolf": 0.85, "boar": 0.8, "lion": 1.9}[kind] as float
		var tail := {"wolf": 0.45, "boar": 0.25, "lion": 1.0}[kind] as float
		z -= tail
		r.position = Vector3(0, 0, z - half)
		root.add_child(r)
		freeze(r, "", 1.0, 0.0)
		z -= half * 2.0 + 0.5
	return root


## 1.9 m neutral human silhouette (for scale): legs, torso, arms, head.
static func human(_seed: int) -> Node3D:
	var mb := MeshBuilder.new(5)
	var c := Color("5E5650")
	for s in [-1.0, 1.0]:
		mb.limb(Vector3(0.11 * s, 0.0, 0.0), Vector3(0.11 * s, 0.92, 0.0), 0.075, 0.095, 10, c)
		mb.limb(Vector3(0.26 * s, 1.5, 0.0), Vector3(0.3 * s, 0.82, 0.02), 0.06, 0.045, 10, c)
	mb.lathe([Vector2(0.17, 0.88), Vector2(0.21, 1.05), Vector2(0.25, 1.35), Vector2(0.27, 1.5), Vector2(0.12, 1.58), Vector2(0.06, 1.62)], 12, c)
	mb.sphere(Vector3(0, 1.76, 0), 0.13, c, 12, 8, Vector3(0.95, 1.12, 1.0))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	return mi


## Frozen rigs are posed before the preview camera exists, so their eye halos could not fade towards the camera
## (the game updates them every frame): once the camera is live, pose every frozen rig again (dt 0, same pose).
class HaloRefresh extends Node:
	var _frames := 0

	func _process(_delta: float) -> void:
		_frames += 1
		if _frames < 2 or get_viewport().get_camera_3d() == null:
			return
		for r in _rigs(get_parent()):
			if r.process_mode == Node.PROCESS_MODE_DISABLED and r.has_method("_animate"):
				r.call("_animate", 0.0)
		queue_free()

	func _rigs(n: Node) -> Array:
		var out: Array = []
		for c in n.get_children():
			if c is Rig:
				out.append(c)
			out.append_array(_rigs(c))
		return out


## Adds the game's toon screen passes (ink outlines + rim, bloom/grade) to the preview camera, configured from
## the preview's TimeOfDay mood, like tools/style_toon.gd does in the game.
class ToonView extends Node:
	var _done := false

	func _process(_delta: float) -> void:
		if _done:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		_done = true
		# the game's preview scene may already run its own ToonScreen: never stack a second set of passes
		for n in get_tree().current_scene.get_children():
			var sc: Script = n.get_script()
			if sc and sc.get_global_name() == &"ToonScreen":
				return
		var tod: TimeOfDay = null
		for n in get_tree().current_scene.get_children():
			if n is TimeOfDay:
				tod = n
		var m: Dictionary = tod.current() if tod else {}
		var edges := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		edges.mesh = qm
		edges.extra_cull_margin = 16384.0
		edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var em := ShaderMaterial.new()
		em.shader = load("res://shaders/toon_edges.gdshader")
		em.render_priority = 100
		edges.material_override = em
		edges.position = Vector3(0, 0, -1.0)
		cam.add_child(edges)
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pm := ShaderMaterial.new()
		pm.shader = load("res://shaders/toon_post.gdshader")
		rect.material = pm
		layer.add_child(rect)
		if m.is_empty():
			return
		var to_light := TimeOfDay.dir_from(m["elev"], m["azim"])
		em.set_shader_parameter("light_dir", to_light)
		em.set_shader_parameter("rim_color", m["rim"])
		em.set_shader_parameter("rim_strength", m["rim_k"])
		em.set_shader_parameter("line_tint", m["line"])
		pm.set_shader_parameter("bloom", m["bloom"])
		pm.set_shader_parameter("sat", m["sat"])


## Colour calibration: smooth spheres in the given colours (swatch=hex,hex,...), labelled, in rows of 6.
static func swatches(_seed: int) -> Node3D:
	var root := _root_with_toon()
	var cols := _arg("swatch", "7D7B80,9A979A,E2DCD0").split(",")
	for i in cols.size():
		var mb := MeshBuilder.new(1)
		mb.sphere(Vector3(0, 0.45, 0), 0.4, Color(cols[i]), 24, 14)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = Materials.lowpoly()
		mi.position = Vector3(float(i % 6) * 1.1, 0, float(i / 6) * 1.3)
		root.add_child(mi)
		_label(root, cols[i], mi.position + Vector3(0, 1.05, 0), 0.6)
	return root
