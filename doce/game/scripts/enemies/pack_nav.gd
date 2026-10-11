class_name PackNav
extends RefCounted
## Steering for the beasts of Nemea (ENCOUNTERS, lane P: wolf.gd, boar.gd): seek a goal, keep apart from the other
## beasts, step round trunks and rocks with two feelers (every third tick), never into the sea, and get unstuck:
## when the beast makes less than a third of the progress it wants for STUCK_T s (a trunk dead ahead, the two
## feelers cancelling the seek, a fence), it takes a DETOUR_T s detour ~70 degrees to the clearer side. Cheap: no
## allocation per tick, two rays every third tick, two more only when stuck.
## Use: v = nav.steer(goal, speed, arrive) inside _think(); nav.after_move(delta) after the body moved.
## The feet: rig.ground_fn = Callable(nav, "ground_y") and nav.scan_rocks() every tick: the rig plants the paws on
## the terrain, or on top of a low rock the beast stands against (a paw never sinks into a rock's flank), and
## steer() keeps the body clear_r m from trunks, rocks and walls (a paw striding sideways never reaches into one).

const STUCK_T := 0.45
const DETOUR_T := 1.1
const DETOUR_ANG := 1.2

var body: Enemy
## Radius of the separation from the other beasts (m).
var sep_r := 1.8
var _avoid_v := Vector3.ZERO
var _avoid_tick := 0
var _seek := Vector3.ZERO
var _goal := Vector3.ZERO
var _last_pos := Vector3.INF
var _stuck_t := 0.0
var _detour_t := 0.0
var _detour_sign := 1.0
var _ray: PhysicsRayQueryParameters3D = null
## Detours taken (tests).
var detours := 0
## Reach of the feet round the origin (m): rocks within it are scanned for ground_y().
var feet_reach := 1.3
## Clearance kept between the origin and the world's props at paw height (m; 0 = none): steer() never moves the
## body closer, and pushes it out.
var clear_r := 0.65
## Highest rock top a paw steps onto above the terrain (m): above it the paw stays on the terrain (the clearance
## keeps it out of a rock face).
var step_max := 0.4
## Nearest points (x, z) of the props round the feet (refreshed with the rocks).
var _obst := PackedFloat32Array()
var _cq: PhysicsShapeQueryParameters3D = null
## Rocks round the body (refreshed every ROCK_TICKS ticks): per rock its world centre x, z, squared xz reach and
## top height.
var _rocks := PackedFloat32Array()
var _rock_tick := 0
var _sq: PhysicsShapeQueryParameters3D = null
var _gray: PhysicsRayQueryParameters3D = null
var _world = null
## Local AABBs of the collision shapes met (per shape resource).
static var _aabbs := {}
## Rays cast by ground_y() so far, all beasts (tests: the cost of standing on rocks).
static var feet_rays := 0
const ROCK_TICKS := 2


func _init(b: Enemy, separation_r: float = 1.8) -> void:
	body = b
	sep_r = separation_r
	_avoid_tick = b.get_instance_id() % 3


## The velocity that takes the body towards `goal` at `speed` (easing in within `arrive` m).
func steer(goal: Vector3, speed: float, arrive: float) -> Vector3:
	var p := body.global_position
	var d := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
	var dist := d.length()
	var v := Vector3.ZERO
	if dist > 0.01:
		v = d / dist * speed * clampf(dist / maxf(arrive, 0.01), 0.0, 1.0)
	_seek = v
	_goal = goal
	if _detour_t > 0.0 and v.length() > 0.1:
		v = v.rotated(Vector3.UP, _detour_sign * DETOUR_ANG)
	v += body.separation(sep_r) * maxf(speed, 1.5) * 0.9
	if v.length() > 0.2:
		_avoid_tick -= 1
		if _avoid_tick <= 0:
			_avoid_tick = 3
			_avoid_v = body._avoid(v)
			# round it, never back on itself: the feelers' push loses its backward part (a trunk dead ahead would
			# otherwise turn the beast round for three ticks, then the seek turns it back: an endless shuffle)
			var f := v.normalized()
			var back := _avoid_v.dot(f)
			if back < 0.0:
				_avoid_v -= f * back * 0.85
		v += _avoid_v * maxf(speed, 1.0)
	else:
		_avoid_v = Vector3.ZERO
	v = v.limit_length(maxf(speed, 1.2))
	# clearance round the feet: never closer to a trunk, a rock or a wall, pushed out when closer
	var no := _obst.size()
	var oi := 0
	while oi < no:
		var ox := p.x - _obst[oi]
		var oz := p.z - _obst[oi + 1]
		var ol := sqrt(ox * ox + oz * oz)
		if ol < clear_r and ol > 0.001:
			var away := Vector3(ox / ol, 0.0, oz / ol)
			var into := -v.dot(away)
			if into > 0.0:
				v += away * into
			v += away * (clear_r - ol) / clear_r * 4.0
		oi += 2
	var w = Game.world
	if w != null and v.length() > 0.1 and w.has_method("is_water"):
		var ahead := p + v.normalized() * 0.9
		if bool(w.call("is_water", ahead.x, ahead.z)):
			return Vector3.ZERO
	return v


## After the body moved this tick: how much of the wanted progress it made; stuck for STUCK_T s -> a detour.
func after_move(delta: float) -> void:
	var p := body.global_position
	if _last_pos == Vector3.INF or delta <= 0.0:
		_last_pos = p
		_seek = Vector3.ZERO
		return
	# progress made towards the goal this tick (m/s): not distance covered (a beast shuffling back and forth in
	# front of a trunk covers plenty of it)
	var g := Vector2(_goal.x, _goal.z)
	var made := (g.distance_to(Vector2(_last_pos.x, _last_pos.z)) - g.distance_to(Vector2(p.x, p.z))) / delta
	_last_pos = p
	var want := _seek.length()
	_seek = Vector3.ZERO
	_detour_t = maxf(0.0, _detour_t - delta)
	if want > 0.9 and made < want * 0.33 and _detour_t <= 0.0:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta * 2.0)
	if _stuck_t >= STUCK_T and _detour_t <= 0.0:
		_stuck_t = 0.0
		_detour_t = DETOUR_T
		detours += 1
		_detour_sign = _clearer_side()


## The side (+1 or -1: the sign of the detour's turn about +Y from the body's forward) with more room: two rays of
## 2.5 m on the world, beast and movable layers.
func _clearer_side() -> float:
	if not body.is_inside_tree():
		return -_detour_sign
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = 1 | 4 | 8
		_ray.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	var f := body.forward()
	var from := body.global_position + Vector3(0, 0.5, 0)
	var room := [2.5, 2.5]
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		_ray.from = from
		_ray.to = from + f.rotated(Vector3.UP, s * DETOUR_ANG) * 2.5
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			room[k] = from.distance_to(hit["position"])
	if absf(float(room[0]) - float(room[1])) < 0.2:
		return -_detour_sign # as clear either way: the other side from last time
	return 1.0 if float(room[0]) > float(room[1]) else -1.0


# --- the feet ----------------------------------------------------------------------------------------------------

## Every physics tick while the rig animates (the query itself runs every ROCK_TICKS ticks): the rocks, walls and
## low props (world layer, not the terrain) within feet_reach of the body, for ground_y().
func scan_rocks() -> void:
	_rock_tick -= 1
	if _rock_tick > 0:
		return
	_rock_tick = ROCK_TICKS
	if not _rocks.is_empty():
		_rocks.resize(0)
	if not _obst.is_empty():
		_obst.resize(0)
	if not body.is_inside_tree():
		return
	if _sq == null:
		_world = Game.world
		_sq = PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = feet_reach
		_sq.shape = sph
		_sq.collision_mask = 1
		_gray = PhysicsRayQueryParameters3D.new()
		_gray.collision_mask = 1
		# a band round the feet (8 to 58 cm above them) for the clearance, wider than it: a running beast (up to
		# 0.5 m between two scans) sees a trunk before it is too near
		_cq = PhysicsShapeQueryParameters3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(clear_r, 0.05) + 0.4
		cyl.height = 0.5
		_cq.shape = cyl
		_cq.collision_mask = 1
		var tb = _world.get("terrain_body") if _world != null else null
		if tb is CollisionObject3D:
			_sq.exclude = [(tb as CollisionObject3D).get_rid()]
			_gray.exclude = _sq.exclude
			_cq.exclude = _sq.exclude
	var space := body.get_world_3d().direct_space_state
	if clear_r > 0.0:
		_cq.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3(0, 0.33, 0))
		var pairs := space.collide_shape(_cq, 6)
		var k := 1
		while k < pairs.size():
			var q: Vector3 = pairs[k]
			_obst.append(q.x)
			_obst.append(q.z)
			k += 2
	_sq.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3(0, 0.3, 0))
	var res := space.intersect_shape(_sq, 6)
	for r in res:
		var co := r.get("collider") as CollisionObject3D
		if co == null:
			continue
		var cs := co.shape_owner_get_owner(co.shape_find_owner(int(r.get("shape", 0)))) as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var bb: AABB = cs.global_transform * _local_aabb(cs.shape)
		if bb.end.y > body.global_position.y + 1.6:
			continue # a trunk, a wall or a big rock: the body's capsules keep it out, no paw goes over it
		var c := bb.get_center()
		var hx := bb.size.x * 0.5
		var hz := bb.size.z * 0.5
		_rocks.append(c.x)
		_rocks.append(c.z)
		_rocks.append(hx * hx + hz * hz)
		_rocks.append(bb.end.y)


## Ground height under (x, z) for the rig's feet: the terrain, or the top of a scanned rock there (a ray down).
func ground_y(x: float, z: float) -> float:
	if _world == null:
		_world = Game.world
		if _world == null:
			return 0.0
	var h: float = _world.height_at(x, z)
	var n := _rocks.size()
	var i := 0
	while i < n:
		var dx := x - _rocks[i]
		var dz := z - _rocks[i + 1]
		if dx * dx + dz * dz < _rocks[i + 2] and _rocks[i + 3] > h + 0.02 and body.is_inside_tree():
			_gray.from = Vector3(x, _rocks[i + 3] + 0.05, z)
			_gray.to = Vector3(x, h - 0.02, z)
			var hit := body.get_world_3d().direct_space_state.intersect_ray(_gray)
			feet_rays += 1
			if not hit.is_empty():
				var hy: float = (hit["position"] as Vector3).y
				if hy - h <= step_max:
					h = maxf(h, hy)
		i += 4
	return h


static func _local_aabb(sh: Shape3D) -> AABB:
	var id := sh.get_instance_id()
	if _aabbs.has(id):
		return _aabbs[id]
	var bb := AABB()
	if sh is ConvexPolygonShape3D:
		var pts := (sh as ConvexPolygonShape3D).points
		if not pts.is_empty():
			bb = AABB(pts[0], Vector3.ZERO)
			for p in pts:
				bb = bb.expand(p)
	elif sh is BoxShape3D:
		var e := (sh as BoxShape3D).size
		bb = AABB(-e * 0.5, e)
	elif sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		bb = AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
	elif sh is SphereShape3D:
		var rr := (sh as SphereShape3D).radius
		bb = AABB(-Vector3.ONE * rr, Vector3.ONE * rr * 2.0)
	elif sh is CapsuleShape3D:
		var cp := sh as CapsuleShape3D
		bb = AABB(Vector3(-cp.radius, -cp.height * 0.5, -cp.radius), Vector3(cp.radius * 2.0, cp.height, cp.radius * 2.0))
	else:
		var dm := sh.get_debug_mesh()
		bb = dm.get_aabb() if dm != null else AABB(-Vector3.ONE * 50.0, Vector3.ONE * 100.0)
	_aabbs[id] = bb
	return bb
