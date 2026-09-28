# Tiny animation kit for the level's set pieces (doors, windows): easing curves, a timeline of spans, and a
# ballistic debris simulator (pieces fly, spin, bounce once or twice on the floor, shrink away and hide).
# Everything runs in the parent's local space and is driven by the owner's update(dt).
# (Port of src/world/anim.js.)
#
#   ease_.outBack(t, s) ease_.inOutSine(t) ease_.outCubic(t)
#   Timeline.new(): span(start, dur, fn(k)), at(time, fn), update(dt) -> busy, finish(), clear(), t
#   Debris.new(): launch(obj, vel[3], spin[3], {delay, life, gravity, floorY, radius}), update(dt) -> busy,
#                 finish() (hides every piece now), clear()
# Usage: const Anim = preload("res://scripts/world/anim.gd"); Anim.ease_.outBack(k), Anim.Timeline.new() ...
#
# Renames (SPEC §3.2): the JS `ease` object -> inner class `ease_` (GDScript has a global ease() function).
# Debris drives obj.rotation as three.js does (Euler XYZ): launch() switches the node to EULER_ORDER_XYZ first
# (the node's orientation is kept).
extends RefCounted

class ease_:
	static func outBack(t: float, s: float = 1.70158) -> float:
		var u := t - 1.0
		return 1.0 + (s + 1.0) * u * u * u + s * u * u

	static func inOutSine(t: float) -> float:
		return 0.5 - 0.5 * cos(PI * t)

	static func outCubic(t: float) -> float:
		return 1.0 - pow(1.0 - t, 3.0)


class Timeline extends RefCounted:
	var items: Array = []
	var t := 0.0

	func span(start: float, dur: float, fn: Callable) -> Timeline:
		items.append({"start": start, "dur": dur, "fn": fn, "done": false})
		return self

	func at(time: float, fn: Callable) -> Timeline:
		return span(time, 0.0, func(_k): fn.call())

	func update(dt: float) -> bool:
		t += dt
		var busy := false
		for it in items:
			if it.done:
				continue
			if t < it.start:
				busy = true
				continue
			var k: float = minf(1.0, (t - it.start) / it.dur) if it.dur > 0.0 else 1.0
			it.fn.call(k)
			if k >= 1.0:
				it.done = true
			else:
				busy = true
		return busy

	# Jump to the end state: every pending item runs once with k = 1, in start order.
	func finish() -> void:
		var pending := items.filter(func(it): return not it.done)
		pending.sort_custom(func(a, b): return a.start < b.start)
		for it in pending:
			it.fn.call(1.0)
			it.done = true

	func clear() -> void:
		items.clear()
		t = 0.0


const SHRINK := 0.22

class Debris extends RefCounted:
	var items: Array = []

	func launch(obj: Node3D, vel: Array, spin: Array, opts: Dictionary = {}) -> void:
		obj.rotation_order = EULER_ORDER_XYZ
		items.append({
			"obj": obj, "vx": float(vel[0]), "vy": float(vel[1]), "vz": float(vel[2]),
			"wx": float(spin[0]), "wy": float(spin[1]), "wz": float(spin[2]),
			"delay": float(opts.get("delay", 0.0)), "life": float(opts.get("life", 1.0)),
			"gravity": float(opts.get("gravity", 18.0)), "floorY": float(opts.get("floorY", 0.0)),
			"radius": float(opts.get("radius", 0.1)), "t": 0.0, "s0": obj.scale, "done": false,
		})

	func update(dt: float) -> bool:
		var busy := false
		for d in items:
			if d.done:
				continue
			busy = true
			d.t += dt
			if d.t < d.delay:
				continue
			var o: Node3D = d.obj
			d.vy -= d.gravity * dt
			o.position.x += d.vx * dt
			o.position.y += d.vy * dt
			o.position.z += d.vz * dt
			o.rotation.x += d.wx * dt
			o.rotation.y += d.wy * dt
			o.rotation.z += d.wz * dt
			if o.position.y < d.floorY + d.radius and d.vy < 0.0:
				o.position.y = d.floorY + d.radius
				d.vy *= -0.35
				d.vx *= 0.6
				d.vz *= 0.6
				d.wx *= 0.5
				d.wy *= 0.5
				d.wz *= 0.5
			var age: float = d.t - d.delay
			if age > d.life:
				var k: float = 1.0 - minf(1.0, (age - d.life) / SHRINK)
				o.scale = d.s0 * maxf(1e-3, k)
				if k <= 0.0:
					o.visible = false
					d.done = true
		return busy

	func finish() -> void:
		for d in items:
			d.obj.visible = false
			d.done = true

	func clear() -> void:
		items.clear()
