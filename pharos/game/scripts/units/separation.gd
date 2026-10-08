class_name Separation
## Soft crowd separation between non-building units of the same team (cheap O(n) per unit).

static func apply(u: Unit, p: Vector3, team: int, strength: float = 0.5) -> Vector3:
	var push := Vector3.ZERO
	for o in Game.units[team]:
		if o == u or not is_instance_valid(o) or not o.alive or o.is_building:
			continue
		if o.is_flying != u.is_flying:
			continue
		var dx: float = p.x - o.global_position.x
		var dz: float = p.z - o.global_position.z
		var rr: float = u.radius + o.radius
		var d2 := dx * dx + dz * dz
		if d2 < rr * rr and d2 > 0.000001:
			var d := sqrt(d2)
			var k := (rr - d) / rr
			push.x += dx / d * k
			push.z += dz / d * k
	return p + push * strength * rr_scale(u)


static func rr_scale(u: Unit) -> float:
	return clampf(u.radius * 0.8, 0.2, 1.0)
