class_name Obstacles
## Static circular obstacles (buildings, big rocks). Units are pushed out of them.

static var list: Array = [] # [Vector3 centre (y ignored), radius, owner]


static func add(center: Vector3, r: float, owner: Object) -> void:
	list.append([center, r, owner])


static func remove_owner(owner: Object) -> void:
	for i in range(list.size() - 1, -1, -1):
		if list[i][2] == owner:
			list.remove_at(i)


static func clear() -> void:
	list.clear()


static func push_out(p: Vector3, r: float, ignore: Object = null) -> Vector3:
	for o in list:
		if o[2] == ignore:
			continue
		var c: Vector3 = o[0]
		var dx := p.x - c.x
		var dz := p.z - c.z
		var rr: float = o[1] + r
		var d2 := dx * dx + dz * dz
		if d2 < rr * rr:
			var d := sqrt(d2)
			if d < 0.001:
				dx = 1.0
				dz = 0.0
				d = 1.0
			p.x = c.x + dx / d * rr
			p.z = c.z + dz / d * rr
	return p
