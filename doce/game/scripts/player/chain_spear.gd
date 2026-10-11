class_name ChainSpear
extends Node3D
## Heracles' chain spear (CORE): the thrown spear, the bronze chain it trails and the aim assist.
##   BACK       strapped on the hero's back (the rig draws it there)
##   FLYING     thrown at SPEED towards its target's chain_point() (homing on a moving target) or a free aim
##              point; the first anchor it touches on the way is the one it bites; a wall or the ground sends it
##              back with a clink; with nothing to bite it flies RANGE metres and comes back
##   STUCK      bitten into an anchor (follows it): the hero works the chain (Hero.on_spear_stuck); released by
##              the hero, by the anchor's death, or beyond KEEP_RANGE
##   RETURNING  reeled back to the left hand (butt first), then BACK
## The chain: real links (one MultiMesh, MAX_LINKS) from the left fist (RigHeracles.chain_origin) to the spear's
## butt ring, sagging and whipping while slack, drawn straight and trembling when taut (`taut`, set by the hero);
## links further than ~6 m from the view are drawn up to 2.6 times thicker so the chain still reads as a line.
## Aim (find_candidate): the best node in group chain_anchor within RANGE, inside a cone round the camera's view
## (AIM_CONE degrees, AIM_CONE_NEAR more for close targets), in line of sight; the hero marks it with a glint.

enum { BACK, FLYING, STUCK, RETURNING }

const SPEED := 50.0
const RETURN_SPEED := 40.0
const RANGE := 22.0
const KEEP_RANGE := 26.0
const AIM_CONE := 12.0
const AIM_CONE_NEAR := 25.0
## Spear geometry (RigHeracles.spear_meshes grip space): the tip and the butt ring along -Z / +Z.
const TIP_Z := 0.58
const BUTT_Z := 0.79
## How deep the head goes into what it bites.
const BURY := 0.22
## A bronze ring: the spear goes through the ring straight into the rock behind it (along -chain_normal()) this deep,
## so only the last ~0.4 m of the shaft and the butt ring stick out of the wall: never a shaft hanging down through
## the hero who zips up to hang under the ring.
const RING_BURY := 0.95
const LINK_STEP := 0.095
## The self-lit face of every link (alpha 0.5 = self-lit in lowpoly.gdshader; x2.4 there: a bright bronze).
const LINK_GLINT := Color(0.75, 0.55, 0.25, 0.5)
## Links are drawn this many times thicker per metre from the view, between these bounds (a real link is under a
## pixel at range: the chain must stay a line).
const THICK_K := 0.16
const THICK_MIN := 1.4
const THICK_MAX := 3.0
## While taut, a thin bright line (TAUT_PX pixels wide) runs along the chain: it reads at any range and in shadow.
const TAUT_PX := 1.6
const TAUT_COLOR := Color(1.0, 0.82, 0.48)
const MAX_LINKS := 260

var hero: Hero
var mode := BACK
var target: Node3D = null
var kind: StringName = &""
## 0 slack .. 1 taut (the hero sets it while it pulls).
var taut := 0.0
var _tip := Vector3.ZERO
var _tip_prev := Vector3.ZERO
var _dir := Vector3.FORWARD
var _aim := Vector3.ZERO
var _travel := 0.0
var _speed := SPEED
var _stuck_local := Transform3D.IDENTITY
var _stuck_vis: Node3D = null
var _wave := 0.0
var _t := 0.0
var _taut_vis := 0.0
var _spear: Node3D
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _marker: MeshInstance3D
var _cand_n: Array[Node3D] = []
var _fly_q: PhysicsRayQueryParameters3D = null
var _cand_s := PackedFloat32Array()
## A ribbon of light behind the flying spear (the throw reads even when it flies straight away from the camera).
var _trail: MotionTrail
## The taut chain's line (an ImmediateMesh ribbon facing the view).
var _line: MeshInstance3D
var _line_im: ImmediateMesh
var _line_pts := PackedVector3Array()
## Where the chain bends round the world this frame (a pillar between the hero and a slammed beast, the lip of a
## ledge he climbed over): Vector3.INF when the straight line from the fist to the butt ring is clear. The chain is
## drawn as two lengths meeting there, and the spear flying home goes by it.
var _wrap := Vector3.INF
var _wrap_q: PhysicsRayQueryParameters3D = null
## 0..1: how much of the sag and the whip is taken out because the curve would dip into the world where the straight
## line is clear (at once when it would, back over a quarter of a second).
var _flat_k := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 20 # after the rig has posed the hand this frame
	_spear = Node3D.new()
	_spear.name = "Spear"
	add_child(_spear)
	var sp: Array = RigHeracles.spear_meshes(false)
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = sp[i]
		mi.material_override = Materials.lowpoly()
		if i == 1:
			Materials.set_param(mi, &"metal", 1.0)
		_spear.add_child(mi)
	_spear.visible = false
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _link_mesh()
	_mm.instance_count = MAX_LINKS
	_mm.visible_instance_count = 0
	_buf.resize(MAX_LINKS * 12)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Chain"
	_mmi.multimesh = _mm
	_mmi.material_override = Materials.lowpoly()
	Materials.set_param(_mmi, &"metal", 1.0)
	_mmi.extra_cull_margin = 64.0
	add_child(_mmi)
	_mmi.visible = false
	_marker = MeshInstance3D.new()
	_marker.name = "AimGlint"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_marker.mesh = q
	_marker.material_override = Materials.glow_star()
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Materials.set_param(_marker, &"tint_color", Vector3(1.0, 0.86, 0.55))
	add_child(_marker)
	_marker.visible = false
	_trail = MotionTrail.new()
	_trail.name = "Trail"
	add_child(_trail)
	_line_im = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.name = "TautLine"
	_line.mesh = _line_im
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.extra_cull_margin = 64.0
	var lm := ShaderMaterial.new()
	lm.shader = load("res://shaders/fx.gdshader") as Shader
	lm.set_shader_parameter("view_pull", 0.06)
	_line.material_override = lm
	add_child(_line)


## One bronze link: an elongated ring along local Z (length 0.12 m, width 0.07 m, wire 0.026 m thick).
static func _link_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(91)
	var seg := 10
	var rz := 0.047
	var rx := 0.024
	var w := 0.013
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(Vector3(cos(a) * rx, 0.0, sin(a) * rz))
		nrm.append(Vector3(cos(a) * rz, 0.0, sin(a) * rx).normalized())
	for i in seg:
		var j := (i + 1) % seg
		var q0 := [pts[i] + nrm[i] * w, pts[i] + Vector3(0, w, 0), pts[i] - nrm[i] * w, pts[i] - Vector3(0, w, 0)]
		var q1 := [pts[j] + nrm[j] * w, pts[j] + Vector3(0, w, 0), pts[j] - nrm[j] * w, pts[j] - Vector3(0, w, 0)]
		for k in 4:
			var k2 := (k + 1) % 4
			# one face of the wire is self-lit (vertex alpha 0.5: lowpoly.gdshader's glow, dim): a thin bronze glint
			# that keeps the chain readable in shadow and against dark rock, where shaded bronze disappears
			var col := LINK_GLINT if k == 0 else (RigHeracles.BRONZE_DARK if k == 1 else RigHeracles.CHAIN_DARK)
			mb.quad(q0[k], q0[k2], q1[k2], q1[k], col)
	return mb.commit()


# --- control (the hero) ------------------------------------------------------------------------------------

## Throws the spear from `from` (the left hand) at `tgt` (an anchor, or null) / the point `aim`.
func launch(from: Vector3, tgt: Node3D, aim: Vector3) -> void:
	mode = FLYING
	target = tgt
	kind = &""
	_aim = aim
	var goal := _goal()
	_dir = (goal - from).normalized() if goal.distance_to(from) > 0.01 else hero.forward()
	# the shaft leaves the hand butt last: its butt ring starts in the fist, the head 1.37 m ahead (never back
	# through his head and shoulder); a wall closer than that: the head starts at the wall
	var lead := TIP_Z + BUTT_Z
	if _fly_q == null:
		_fly_q = PhysicsRayQueryParameters3D.new()
		_fly_q.collision_mask = 1 | 4 | 8
		_fly_q.exclude = [hero.get_rid()]
	_fly_q.from = from
	_fly_q.to = from + _dir * lead
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(_fly_q)
	if not hit.is_empty() and anchor_of(hit["collider"]) == null:
		lead = maxf(0.0, from.distance_to(hit["position"]) - 0.06)
	_tip = from + _dir * lead
	_tip_prev = _tip
	_travel = 0.0
	_wrap = Vector3.INF
	_wave = 1.0
	taut = 0.0
	_taut_vis = 0.0
	Sfx.play("chain_throw", from, -1.0, randf_range(0.96, 1.04))


## Lets go of what the spear holds and reels it back to the hand.
func release() -> void:
	if mode == BACK or mode == RETURNING:
		return
	_detach()
	_start_return()


## Straight back on the back (a new throw from a ring, a teleport): no flight home.
func snap_back(sound: bool = false) -> void:
	if mode == BACK:
		return
	if sound:
		Sfx.play("chain_rattle", _tip, -6.0, 1.15)
		if Game.fx:
			Game.fx.call("hit_spark", _tip, -_dir, 0.5)
	_detach()
	_to_back()


func _detach() -> void:
	if mode == STUCK and target != null and is_instance_valid(target) and target.has_method("on_chain_release"):
		target.call("on_chain_release", hero)
	target = null
	_stuck_vis = null


func _start_return() -> void:
	mode = RETURNING
	target = null
	_speed = 10.0
	_wave = maxf(_wave, 0.7)
	taut = 0.0
	Sfx.play("chain_rattle", hero.global_position + Vector3(0, 1.4, 0), -4.0, randf_range(0.95, 1.05))
	hero.on_spear_missed()


func _to_back() -> void:
	mode = BACK
	target = null
	taut = 0.0
	_wrap = Vector3.INF
	_spear.visible = false
	_mmi.visible = false
	_mm.visible_instance_count = 0
	_line.visible = false
	hero.rig.set_spear_on_back(true)


func _goal() -> Vector3:
	if target != null and Combat.is_alive(target):
		return target.call("chain_point")
	return _aim


## Where the flying spear is going (its target's chain point, or the point aimed at).
func goal() -> Vector3:
	return _goal()


## The anchor a collider belongs to (itself or an ancestor in group chain_anchor), or null.
static func anchor_of(col: Object) -> Node3D:
	var n := col as Node
	while n != null:
		if n.is_in_group("chain_anchor") and n.has_method("chain_kind") and n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


# --- simulation (called from Hero._physics_process) -------------------------------------------------------

func physics(delta: float) -> void:
	_t += delta
	match mode:
		FLYING:
			_fly(delta)
		STUCK:
			_follow()
		RETURNING:
			_return(delta)


func _fly(delta: float) -> void:
	_tip_prev = _tip
	if target != null and not Combat.is_alive(target):
		target = null
	var goal := _goal()
	var to := goal - _tip
	var step := SPEED * delta
	if target != null and to.length() <= step + 0.05:
		if to.length() > 0.01:
			_dir = to.normalized()
		_stick(target, goal)
		return
	var nd := to.normalized() if to.length() > 0.001 else _dir
	_dir = nd
	var adv := minf(step, maxf(to.length(), 0.0)) if target == null else step
	var next := _tip + nd * adv
	if _fly_q == null:
		_fly_q = PhysicsRayQueryParameters3D.new()
		_fly_q.collision_mask = 1 | 4 | 8
		_fly_q.exclude = [hero.get_rid()]
	_fly_q.from = _tip
	_fly_q.to = next + nd * 0.06
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(_fly_q)
	if not hit.is_empty():
		var anchor := anchor_of(hit["collider"])
		if anchor != null and Combat.is_alive(anchor):
			_stick(anchor, anchor.call("chain_point") if anchor != target else goal)
			return
		# a wall or the ground: a clink, and back it comes
		_tip = (hit["position"] as Vector3) - nd * 0.05
		if Game.fx:
			Game.fx.call("hit_spark", hit["position"], hit["normal"], 0.6)
		Sfx.play("chain_stick", hit["position"], -9.0, 1.35)
		_start_return()
		return
	_tip = next
	_travel += adv
	if target == null and (to.length() <= step + 0.05 or _travel >= RANGE):
		_start_return()
	elif _travel > RANGE + 8.0:
		_start_return()


func _stick(anchor: Node3D, point: Vector3) -> void:
	target = anchor
	kind = anchor.call("chain_kind")
	mode = STUCK
	var bury := BURY
	if kind == &"ring" and anchor.has_method("chain_normal"):
		var nrm: Vector3 = anchor.call("chain_normal")
		if nrm.length_squared() > 1e-4:
			_dir = -nrm.normalized()
			bury = RING_BURY
	_tip = point + _dir * bury
	_tip_prev = _tip
	_stuck_vis = _visual_of(anchor)
	_stuck_local = _stuck_vis.global_transform.affine_inverse() * _spear_xf(_tip, _dir)
	_wave = 0.55
	Sfx.play("chain_stick", point, -1.0, randf_range(0.95, 1.05))
	if Game.fx:
		Game.fx.call("hit_spark", point, -_dir, 0.8)
	Game.shake(0.08)
	if anchor.has_method("on_chain_attach"):
		anchor.call("on_chain_attach", hero)
	hero.on_spear_stuck(anchor, kind)


## Drives the stuck spear `extra` m deeper along its line (Hero, a zip that ends with a climb: the butt ring then sits
## at the bronze ring, flush with the wall, so neither the shaft nor the chain can cross his body under the lip).
func sink(extra: float) -> void:
	if mode != STUCK or _stuck_vis == null or not is_instance_valid(_stuck_vis):
		return
	_tip += _dir * extra
	_tip_prev = _tip
	_stuck_local = _stuck_vis.global_transform.affine_inverse() * _spear_xf(_tip, _dir)


## What the stuck spear follows: an enemy's interpolated visual (its `rig`) when it has one, else the node itself.
static func _visual_of(n: Node3D) -> Node3D:
	if "rig" in n:
		var r = n.get("rig")
		if r is Node3D and (r as Node3D).is_inside_tree():
			return r
	return n


func _follow() -> void:
	if target == null or not Combat.is_alive(target) or _stuck_vis == null or not is_instance_valid(_stuck_vis):
		release()
		return
	var xf := _stuck_vis.global_transform * _stuck_local
	_dir = -xf.basis.z
	_tip = xf.origin + _dir * TIP_Z
	_tip_prev = _tip
	if hero.global_position.distance_to(_tip) > KEEP_RANGE:
		release()


func _return(delta: float) -> void:
	_tip_prev = _tip
	var hand := hero.rig.chain_origin()
	_speed = minf(RETURN_SPEED, _speed + 110.0 * delta)
	# butt first: the butt ring (1.37 m behind the head) flies into the fist, then the spear goes on the back
	var butt := _tip - _dir * (TIP_Z + BUTT_Z)
	var step := _speed * delta
	# round what the chain is bent over (a pillar, the lip of a ledge) rather than through it
	if _wrap != Vector3.INF and butt.distance_to(_wrap) > step + 0.1:
		var wn := (_wrap - butt).normalized()
		_dir = _dir.slerp(-wn, 0.35).normalized()
		_tip += wn * step
		return
	var to := hand - butt
	if to.length() <= step + 0.12:
		Sfx.play("chain_rattle", hand, -2.0, randf_range(1.05, 1.15))
		Game.shake(0.05)
		if Game.fx:
			Game.fx.call("hit_spark", hand, -to.normalized() if to.length() > 0.01 else Vector3.UP, 0.25)
		# the fist closes on it and swings it onto the back (upper body; not over another action)
		if hero.state == Hero.St.MOVE and hero.rig.action == "" and hero.is_alive():
			hero.rig.play_at("catch", 1.0, true)
		_to_back()
		return
	var n := to.normalized()
	_dir = _dir.slerp(-n, 0.35).normalized()
	_tip += n * step


## The spear's transform (grip space: head along -Z) for a tip position and a direction.
static func _spear_xf(tip: Vector3, d: Vector3) -> Transform3D:
	var z := -d.normalized()
	var up := Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x, y, z), tip + z * TIP_Z)


# --- aim assist -------------------------------------------------------------------------------------------

## The anchor the spear would fly to now: in group chain_anchor, alive, within RANGE of the hero's shoulder,
## inside the aim cone round the camera's forward (wider when close), with a clear line on the world and
## movable layers. `exclude`: the ring the hero hangs from.
func find_candidate(exclude: Node3D = null) -> Node3D:
	if Game.camera == null or not is_instance_valid(Game.camera):
		return null
	var cam: Camera3D = Game.camera.cam
	var cxf := cam.global_transform
	var cf := -cxf.basis.z
	var cp := cxf.origin
	var origin := hero.global_position + Vector3(0, 1.5, 0)
	_cand_n.clear()
	_cand_s.resize(0)
	for n in hero.get_tree().get_nodes_in_group("chain_anchor"):
		var a := n as Node3D
		if a == null or a == exclude or not a.has_method("chain_point") or not Combat.is_alive(a):
			continue
		var p: Vector3 = a.call("chain_point")
		var dist := origin.distance_to(p)
		if dist > RANGE or dist < 1.2:
			continue
		var v := p - cp
		if cf.dot(v) <= 0.0:
			continue
		var ang := rad_to_deg(cf.angle_to(v))
		var cone := AIM_CONE + AIM_CONE_NEAR * (1.0 - smoothstep(3.0, 14.0, dist))
		if ang > cone:
			continue
		var score := ang / cone + dist / RANGE * 0.3
		var at := _cand_s.size()
		for i in _cand_s.size():
			if score < _cand_s[i]:
				at = i
				break
		_cand_n.insert(at, a)
		_cand_s.insert(at, score)
	if _cand_n.is_empty():
		return null
	var space := hero.get_world_3d().direct_space_state
	var ex: Array[RID] = [hero.get_rid()]
	for i in mini(_cand_n.size(), 4):
		var a := _cand_n[i]
		if Combat.clear_line(space, origin, a.call("chain_point"), 1 | 8, a, 0.6, ex):
			return a
	return null


# --- drawing --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_marker()
	if mode == BACK:
		_trail.active = false
		return
	var tip := _tip
	if mode == FLYING or mode == RETURNING:
		tip = _tip_prev.lerp(_tip, Engine.get_physics_interpolation_fraction())
	elif mode == STUCK and _stuck_vis != null and is_instance_valid(_stuck_vis):
		var xf := _stuck_vis.global_transform * _stuck_local
		tip = xf.origin - xf.basis.z * TIP_Z
	_spear.visible = true
	_mmi.visible = true
	var sx := _spear_xf(tip, _dir)
	_spear.global_transform = sx
	var butt := sx.origin + sx.basis.z * BUTT_Z
	var hand := hero.rig.chain_origin()
	_wrap = _find_wrap(hand, butt) if mode != FLYING else Vector3.INF
	_draw_chain(hand, butt, delta)
	# the light trail: thrown (bright, wide) and coming back (fainter)
	_trail.active = mode == FLYING or mode == RETURNING
	_trail.width = 0.075 if mode == FLYING else 0.045
	_trail.add_point(tip)


func _update_marker() -> void:
	var c := hero.chain_candidate
	var show := c != null and is_instance_valid(c) and c.is_inside_tree() and (mode == BACK or hero.state == Hero.St.HANG) and hero.is_alive()
	# not on a foe the sword is already busy with: the glint is for what the chain is about to reach
	var swinging := hero.state == Hero.St.ATTACK or hero.state == Hero.St.HEAVY or hero.state == Hero.St.CHARGE
	if show and (swinging or hero.global_position.distance_to(c.global_position) < 3.2):
		show = false
	if not show:
		if _marker.visible:
			_marker.visible = false
		return
	var p: Vector3 = c.call("chain_point")
	var cam := get_viewport().get_camera_3d()
	if cam:
		p += (cam.global_position - p).normalized() * 0.25
	_marker.visible = true
	var k := 0.36 + 0.06 * sin(_t * 7.0)
	_marker.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * k), p)
	Materials.set_param(_marker, &"intensity", 0.75 + 0.2 * sin(_t * 7.0))


## A point the chain from `a` (the fist) to `b` (the butt ring) can bend round so that neither length passes through
## the world (layer 1): the first spot clear of both, stepping out from where the straight line meets the world
## (along that surface's normal, then up, then to either side); Vector3.INF when the line is clear (or no such spot).
## The last WRAP_END m at either end are not tested (the fist against a wall, the butt ring flush with a ring's stone).
const WRAP_END := 0.25
const WRAP_STEPS := [0.12, 0.25, 0.4, 0.6, 0.85, 1.2, 1.7]


func _find_wrap(a: Vector3, b: Vector3) -> Vector3:
	var l := a.distance_to(b)
	if l < 1.0 or not is_inside_tree():
		return Vector3.INF
	if _wrap_q == null:
		_wrap_q = PhysicsRayQueryParameters3D.new()
		_wrap_q.collision_mask = 1
		_wrap_q.hit_back_faces = false
	var space := get_world_3d().direct_space_state
	var hit := _ray_hit(space, a, b)
	if hit.is_empty():
		return Vector3.INF
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var d := (b - a) / l
	var n_perp := n - d * n.dot(d)
	var up := Vector3.UP - d * d.y
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var dirs: Array[Vector3] = []
	if n_perp.length() > 0.05:
		dirs.append(n_perp.normalized())
	if up.length() > 0.05:
		dirs.append(up.normalized())
	if side.dot(n_perp) >= 0.0:
		dirs.append(side)
		dirs.append(-side)
	else:
		dirs.append(-side)
		dirs.append(side)
	# (the previous frame's bend first: no flicker between equally good spots)
	if _wrap != Vector3.INF and _ray_hit(space, a, _wrap).is_empty() and _ray_hit(space, _wrap, b).is_empty() \
			and _wrap.distance_to(p) < 2.0:
		return _wrap
	for k in WRAP_STEPS:
		for dv in dirs:
			var w: Vector3 = p + dv * float(k)
			if _ray_hit(space, a, w).is_empty() and _ray_hit(space, w, b).is_empty():
				return w
	return Vector3.INF


## Whether the sagging, waving curve leaves the straight line (or its bend) for the world anywhere along it (short
## rays on layer 1 from the line to the curve at every tenth of its length).
func _curve_blocked(a: Vector3, b: Vector3, side: Vector3, sag: float, amp: float) -> bool:
	if not is_inside_tree():
		return false
	if _wrap_q == null:
		_wrap_q = PhysicsRayQueryParameters3D.new()
		_wrap_q.collision_mask = 1
		_wrap_q.hit_back_faces = false
	var space := get_world_3d().direct_space_state
	for k in range(1, 10):
		var u := float(k) * 0.1
		var p0 := _chain_at(a, b, side, 0.0, 0.0, u)
		var p1 := _chain_at(a, b, side, sag, amp, u)
		if p0.distance_squared_to(p1) < 1e-4:
			continue
		_wrap_q.from = p0
		_wrap_q.to = p1 + (p1 - p0).normalized() * 0.05
		if not space.intersect_ray(_wrap_q).is_empty():
			return true
	return false


## The world (layer 1) between `a` and `b`, leaving out WRAP_END at each end; {} when clear.
func _ray_hit(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var l := a.distance_to(b)
	if l <= WRAP_END * 2.0 + 0.02:
		return {}
	var d := (b - a) / l
	_wrap_q.from = a + d * WRAP_END
	_wrap_q.to = b - d * WRAP_END
	return space.intersect_ray(_wrap_q)


## A point of the drawn chain at `u` (0 the fist .. 1 the butt): one sagging, waving curve from `a` to `b`, or two
## (a to the wrap point, the wrap point to b) when the chain is bent round the world.
func _chain_at(a: Vector3, b: Vector3, side: Vector3, sag: float, amp: float, u: float) -> Vector3:
	if _wrap == Vector3.INF:
		return _curve(a, b, side, sag, amp, u)
	var la := a.distance_to(_wrap)
	var lb := _wrap.distance_to(b)
	var u0 := la / maxf(la + lb, 1e-4)
	if u <= u0:
		return _curve(a, _wrap, side, sag * u0, amp * u0, u / maxf(u0, 1e-4))
	return _curve(_wrap, b, side, sag * (1.0 - u0), amp * (1.0 - u0), (u - u0) / maxf(1.0 - u0, 1e-4))


func _curve(a: Vector3, b: Vector3, side: Vector3, sag: float, amp: float, u: float) -> Vector3:
	var p := a.lerp(b, u)
	var bell := 4.0 * u * (1.0 - u)
	p.y -= sag * bell
	if amp > 0.0:
		var env := sin(PI * u)
		p += side * (sin(u * TAU * 1.5 - _t * 26.0) * amp * env)
		p.y += cos(u * TAU * 1.2 - _t * 21.0) * amp * 0.6 * env
	if _taut_vis > 0.75:
		p += side * (sin(u * TAU * 3.0 + _t * 95.0) * 0.012 * sin(PI * u) * (_taut_vis - 0.75) * 4.0)
	return p


func _draw_chain(a: Vector3, b: Vector3, delta: float) -> void:
	var d := b - a
	var l := d.length()
	if _wrap != Vector3.INF:
		l = a.distance_to(_wrap) + _wrap.distance_to(b)
	if l < 0.08:
		_mm.visible_instance_count = 0
		_line.visible = false
		return
	_taut_vis = move_toward(_taut_vis, taut, delta * (9.0 if taut > _taut_vis else 3.0))
	_wave = maxf(0.0, _wave - delta * 1.5)
	var slack := 1.0 - _taut_vis
	var sag := slack * clampf(0.06 * l + 0.1, 0.0, 1.4)
	if mode == FLYING:
		sag *= 0.55
	# never through the ground under the middle of the chain
	var mid := (a + b) * 0.5
	if Game.world != null and is_instance_valid(Game.world):
		var gy := float(Game.world.height_at(mid.x, mid.z))
		sag = minf(sag, maxf(0.0, mid.y - gy - 0.1))
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var amp := _wave * clampf(l * 0.035, 0.04, 0.45)
	# the sag and the whip never take the links into the world (a pillar beside the line, the wall a ring is set in)
	if (sag > 0.02 or amp > 0.02) and _curve_blocked(a, b, side, sag, amp):
		_flat_k = 1.0
	else:
		_flat_k = maxf(0.0, _flat_k - delta * 4.0)
	sag *= 1.0 - _flat_k
	amp *= 1.0 - _flat_k
	var step := maxf(LINK_STEP, l / float(MAX_LINKS))
	var n := clampi(int(ceil(l / step)), 1, MAX_LINKS)
	var stretch := (l / float(n)) / LINK_STEP
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else a
	var prev := _chain_at(a, b, side, sag, amp, 0.0)
	_line_pts.resize(0)
	for i in n:
		var p1 := _chain_at(a, b, side, sag, amp, float(i + 1) / float(n))
		var ax := p1 - prev
		var al := ax.length()
		ax = ax / al if al > 1e-5 else d / l
		var ref := Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT
		var x := ref.cross(ax).normalized()
		var y := ax.cross(x)
		if i % 2 == 1:
			var tx := x
			x = y
			y = -tx
		var c := (prev + p1) * 0.5
		if (i & 3) == 0:
			_line_pts.append(prev)
		# thicker with distance from the view: a real link is under a pixel at range; this keeps the chain a line
		var thick := clampf(eye.distance_to(c) * THICK_K, THICK_MIN, THICK_MAX)
		x *= thick
		y *= thick
		var z := ax * clampf(stretch, 1.0, 1.6) * sqrt(thick)
		var o := i * 12
		_buf[o] = x.x
		_buf[o + 1] = y.x
		_buf[o + 2] = z.x
		_buf[o + 3] = c.x
		_buf[o + 4] = x.y
		_buf[o + 5] = y.y
		_buf[o + 6] = z.y
		_buf[o + 7] = c.y
		_buf[o + 8] = x.z
		_buf[o + 9] = y.z
		_buf[o + 10] = z.z
		_buf[o + 11] = c.z
		prev = p1
	_line_pts.append(prev)
	_mm.buffer = _buf
	_mm.visible_instance_count = n
	_draw_line(cam, smoothstep(0.45, 1.0, _taut_vis))


## The taut chain's bright line: a ribbon through every fourth link's centre, TAUT_PX wide on screen, facing the
## view; `k` its strength (0 slack .. 1 taut).
func _draw_line(cam: Camera3D, k: float) -> void:
	_line_im.clear_surfaces()
	if k <= 0.01 or cam == null or _line_pts.size() < 2:
		_line.visible = false
		return
	_line.visible = true
	_line.global_transform = Transform3D.IDENTITY
	var eye := cam.global_position
	var px := 2.0 * tan(deg_to_rad(cam.fov * 0.5)) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var col := Color(TAUT_COLOR.r, TAUT_COLOR.g, TAUT_COLOR.b, 0.85 * k)
	_line_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _line_pts.size() - 1:
		var p0 := _line_pts[i]
		var p1 := _line_pts[i + 1]
		var ax := p1 - p0
		if ax.length_squared() < 1e-8:
			continue
		var w0 := eye.distance_to(p0) * px * TAUT_PX * 0.5
		var w1 := eye.distance_to(p1) * px * TAUT_PX * 0.5
		var s0 := ax.cross(eye - p0).normalized() * w0
		var s1 := ax.cross(eye - p1).normalized() * w1
		for v in [p0 - s0, p0 + s0, p1 + s1, p0 - s0, p1 + s1, p1 - s1]:
			_line_im.surface_set_color(col)
			_line_im.surface_add_vertex(v)
	_line_im.surface_end()
