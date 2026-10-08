class_name Interactables
## Registry of things the hero can interact with (build spots, the night horn, cats).
## Duck-typed interface: can_interact(hero) -> bool, interact_position() -> Vector3, interact_range() -> float,
## interact_hold(delta, hero), interact_release(hero), interact_info() -> Dictionary (for the HUD prompt).

static var list: Array = []


static func add(n: Object) -> void:
	if not list.has(n):
		list.append(n)


static func remove(n: Object) -> void:
	list.erase(n)


static func clear() -> void:
	list.clear()
