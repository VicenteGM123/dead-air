class_name Interactables
## Registry of things the hero can use with "interact" (E / pad Y): altars, cats, the cave boulder, the boat...
## A node registers itself with Interactables.add(self) when it enters the tree and removes itself on exit.
##
## Duck-typed interface (implement what applies):
##   can_interact(hero) -> bool          may the hero use it now?
##   interact_position() -> Vector3      where it is (the prompt floats above it)
##   interact_range() -> float           metres (XZ) from interact_position()
##   interact_info() -> Dictionary       {title, verb, desc, progress (0..1, -1 none), anchor (Vector3, prompt pos)}
##   interact_press(hero)                one-shot use on press, or
##   interact_hold(delta, hero)          every physics frame while held, then
##   interact_release(hero)              when released or when the hero walks away / is interrupted

static var list: Array = []


static func add(n: Object) -> void:
	if not list.has(n):
		list.append(n)


static func remove(n: Object) -> void:
	list.erase(n)


static func clear() -> void:
	list.clear()


## The best interactable for `hero` at `pos` facing `forward` (XZ): in range, usable, preferring what is in front
## and close. Null when there is none.
static func pick(hero: Node, pos: Vector3, forward: Vector3) -> Object:
	var best: Object = null
	var best_score := INF
	var fwd := Vector2(forward.x, forward.z).normalized()
	for it in list:
		if not is_instance_valid(it):
			continue
		if not it.has_method("interact_position") or not it.has_method("can_interact"):
			continue
		var ip: Vector3 = it.call("interact_position")
		var d := Vector2(ip.x - pos.x, ip.z - pos.z)
		var dist := d.length()
		var rng: float = float(it.call("interact_range")) if it.has_method("interact_range") else 1.5
		if dist > rng or absf(ip.y - pos.y) > 2.5:
			continue
		if not bool(it.call("can_interact", hero)):
			continue
		var facing := fwd.dot(d / maxf(dist, 0.001)) if dist > 0.3 else 1.0
		var score := dist * (1.6 - 0.6 * facing)
		if score < best_score:
			best_score = score
			best = it
	return best
