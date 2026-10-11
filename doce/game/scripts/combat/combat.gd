class_name Combat
## Shared combat helpers (CORE): the hit dictionary, hurt volumes and target queries, the blade-sweep geometry.
## Everything is static and duck-typed, so enemies of any stream can use it. The contracts (hit keys, deflect,
## parry, chain kinds, grapple) are documented in docs/COMBAT.md.
##
## hit = {amount, kind, dir, knockback, stagger, source}  (docs/ARCHITECTURE.md 5.1) plus optional keys:
##   point: Vector3        where the blow touched (sparks, deflect sparks)
##   attack: StringName    &"attack1" &"attack2" &"attack3" &"heavy" &"chain" &"grapple" or the enemy's own name
##   guard_break: bool     the hero's heavy blow: breaks shields and guards
##   unblockable: bool     (enemy blows) the hero's shield cannot stop it (and it cannot be parried)
##   parryable: bool       (enemy blows, default true) false: can be blocked but not parried
## Written back by the target inside take_hit (the attacker reads them after the call):
##   deflected: bool       the target is immune to this kind (the Nemean Lion vs blades): returned false
##   blocked: bool         stopped on a shield or guard: returned false (or true with chip damage)
##   parried: bool         (the hero) a perfect parry: returned false; the hero calls attacker.on_parried(hero)
##   dodged: bool          (the hero) went through it during a roll's i-frames: returned false
##   sound_done: bool      the target already played the contact sound (blade_bounce, shield_block)

const TEAM_HERO := 0
const TEAM_ENEMY := 1


## A hit dictionary with the contract's keys, plus `extra` (see the header).
static func make_hit(amount: float, kind: StringName, dir: Vector3, knockback: float, stagger: float, source: Node, extra: Dictionary = {}) -> Dictionary:
	var h := {"amount": amount, "kind": kind, "dir": dir, "knockback": knockback, "stagger": stagger, "source": source}
	if not extra.is_empty():
		h.merge(extra, true)
	return h


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Untyped on purpose: a reference to a freed node (a dead foe that was queue_free'd while someone still held it)
## must answer false, and a typed `Object` parameter would raise a script error on it instead.
static func is_alive(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is Node and not (n as Node).is_inside_tree():
		return false
	return not n.has_method("is_alive") or bool(n.call("is_alive"))


## Damageables of the other team(s) than `team` (alive, in the tree). Allocates: call once per swing, not per tick.
static func foes(tree: SceneTree, team: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in tree.get_nodes_in_group("damageable"):
		var n3 := n as Node3D
		if n3 == null or not is_alive(n3):
			continue
		if "team" in n3 and int(n3.get("team")) == team:
			continue
		out.append(n3)
	return out


## Hurt volumes of a damageable: capsules [a: Vector3, b: Vector3, r: float] in world space. Nodes may define
## hurt_volumes() (the lion: a few capsules along its body); otherwise a vertical capsule from `radius` and `height`.
static func hurt_volumes(n: Node3D) -> Array:
	if n.has_method("hurt_volumes"):
		return n.call("hurt_volumes")
	var r := float(n.get("radius")) if "radius" in n else 0.4
	var h := float(n.get("height")) if "height" in n else 1.7
	var p := n.global_position
	return [[p + Vector3(0.0, r, 0.0), p + Vector3(0.0, maxf(h - r, r), 0.0), r]]


## Body radius (XZ) of a node for spacing (lunges, landing spots).
static func body_radius(n: Node3D) -> float:
	if "radius" in n:
		return float(n.get("radius"))
	return 0.45


## The best target in a horizontal cone: closest in angle and distance. `from` the attacker's centre, `fwd` the
## aim (horizontal), `max_dist` measured to the target's surface, `half_angle` in degrees.
static func best_in_cone(cands: Array, from: Vector3, fwd: Vector3, max_dist: float, half_angle: float) -> Node3D:
	var best: Node3D = null
	var best_s := INF
	var f := flat(fwd).normalized()
	var cosl := cos(deg_to_rad(half_angle))
	for n in cands:
		var t := n as Node3D
		if t == null or not is_alive(t):
			continue
		var d := flat(t.global_position - from)
		var dist := d.length() - body_radius(t)
		if dist > max_dist:
			continue
		if absf(t.global_position.y - from.y) > 2.5:
			continue
		var c := 1.0 if d.length() < 0.05 else f.dot(d.normalized())
		if c < cosl and dist > 0.4:
			continue
		var s := maxf(dist, 0.0) + (1.0 - c) * 2.5
		if s < best_s:
			best_s = s
			best = t
	return best


## Squared distance between the segments p1-q1 and p2-q2; `out` (if given, size >= 2) receives the closest points.
## (Ericson, Real-Time Collision Detection 5.1.9)
static func seg_seg_dist2(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3, out: PackedVector3Array = PackedVector3Array()) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		s = 0.0
		t = 0.0
	elif a <= 1e-9:
		s = 0.0
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 1e-9:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			else:
				s = 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	if out.size() >= 2:
		out[0] = c1
		out[1] = c2
	return c1.distance_squared_to(c2)


## True when `from` is in front of a body at `pos` facing `fwd` within `half_angle` degrees (horizontal).
static func in_front(pos: Vector3, fwd: Vector3, from: Vector3, half_angle: float) -> bool:
	var d := flat(from - pos)
	if d.length_squared() < 1e-6:
		return true
	return flat(fwd).normalized().dot(d.normalized()) >= cos(deg_to_rad(half_angle))


## Line of sight on the world (and movable) layers between two points; `ignore` (a node or its collider ancestry)
## and anything within `slack` metres of `to` do not block.
static func clear_line(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, ignore: Node = null, slack: float = 0.5, exclude: Array[RID] = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	if (hit["position"] as Vector3).distance_to(to) <= slack:
		return true
	if ignore != null:
		var c := hit["collider"] as Node
		while c != null:
			if c == ignore:
				return true
			c = c.get_parent()
	return false
