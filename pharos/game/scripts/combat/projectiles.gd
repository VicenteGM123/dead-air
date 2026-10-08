class_name Projectiles
extends Node3D
## Arrows (homing, arcing) from the towers and shadow orbs from the creatures (aimed, dodgeable).

var _items: Array = []
var _pool := {"arrow": [], "orb": []}
var _arrow_mesh: ArrayMesh
var _orb_mesh: ArrayMesh


func _ready() -> void:
	var mb := MeshBuilder.new(41)
	mb.limb(Vector3(0, 0, 0.45), Vector3(0, 0, -0.45), 0.018, 0.018, 4, Pal.WOOD_LIGHT)
	mb.limb(Vector3(0, 0, -0.45), Vector3(0, 0, -0.6), 0.04, 0.0, 4, Pal.BRONZE)
	mb.plate([Vector3(0, 0, 0.3), Vector3(0, 0.07, 0.42), Vector3(0, 0, 0.47)], Pal.CLOTH)
	mb.plate([Vector3(0, 0, 0.3), Vector3(0.07, 0, 0.42), Vector3(0, 0, 0.47)], Pal.CLOTH)
	_arrow_mesh = mb.commit()
	var ob := MeshBuilder.new(43)
	ob.ico(Vector3.ZERO, 0.22, Color(0.55, 0.45, 1.0, 0.5), 1, 0.1)
	ob.ico(Vector3.ZERO, 0.12, Color(0.9, 0.95, 1.0, 0.5), 0)
	_orb_mesh = ob.commit()


func _take(kind: String) -> Node3D:
	var pool: Array = _pool[kind]
	if not pool.is_empty():
		var n: Node3D = pool.pop_back()
		n.visible = true
		return n
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _arrow_mesh if kind == "arrow" else _orb_mesh
	mi.material_override = Materials.lowpoly()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if kind == "orb":
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.6)
		g.mesh = q
		g.material_override = Materials.glow_add()
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.set_instance_shader_parameter("tint_color", Vector3(0.6, 0.5, 1.0))
		g.set_instance_shader_parameter("intensity", 1.4)
		root.add_child(g)
	add_child(root)
	return root


func _give(kind: String, n: Node3D) -> void:
	n.visible = false
	_pool[kind].append(n)


func arrow(from: Vector3, target: Unit, dmg: float, source: Node3D) -> void:
	var dist := from.distance_to(target.global_position)
	var n := _take("arrow")
	n.global_position = from
	_items.append({"kind": "arrow", "node": n, "from": from, "target": target, "last": target.global_position + Vector3(0, 0.9, 0),
		"t": 0.0, "dur": clampf(dist / 28.0, 0.15, 0.75), "dmg": dmg, "source": source, "arc": dist * 0.1})


func orb(from: Vector3, target: Unit, dmg: float, source: Node3D) -> void:
	var to := target.global_position + Vector3(0, 0.8, 0)
	if not target.is_building and "vel" in target:
		to += (target.get("vel") as Vector3) * 0.35
	var dist := from.distance_to(to)
	var n := _take("orb")
	n.global_position = from
	_items.append({"kind": "orb", "node": n, "from": from, "to": to, "target": target, "t": 0.0, "dur": clampf(dist / 11.0, 0.2, 1.6),
		"dmg": dmg, "source": source, "arc": dist * 0.06})
	Sfx.play("hydra_spit", from, -10.0, randf_range(1.2, 1.5))


func clear() -> void:
	for it in _items:
		_give(it["kind"], it["node"])
	_items.clear()


func _physics_process(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		it["t"] += delta / it["dur"]
		var k: float = minf(it["t"], 1.0)
		var n: Node3D = it["node"]
		var to: Vector3
		if it["kind"] == "arrow":
			var tg: Unit = it["target"]
			if is_instance_valid(tg) and tg.alive:
				it["last"] = tg.global_position + Vector3(0, 0.9 + (0.0 if not tg.is_building else tg.radius * 0.5), 0)
			to = it["last"]
		else:
			to = it["to"]
		var p: Vector3 = (it["from"] as Vector3).lerp(to, k) + Vector3(0, sin(k * PI) * it["arc"], 0)
		var prev := n.global_position
		n.global_position = p
		var v := p - prev
		if v.length() > 0.0001:
			n.look_at(p + v, Vector3.UP)
		if it["kind"] == "orb":
			n.rotation.z += delta * 8.0
		if it["t"] >= 1.0:
			_impact(it)
			_give(it["kind"], n)
			_items.remove_at(i)


func _impact(it: Dictionary) -> void:
	if it["kind"] == "arrow":
		var tg: Unit = it["target"]
		if is_instance_valid(tg) and tg.alive:
			tg.take_damage(it["dmg"], it["source"], 0.25, "arrow")
			if randf() < 0.4:
				Sfx.play("arrow_hit", tg.global_position, -10.0, randf_range(0.9, 1.15))
			if Game.fx:
				Game.fx.hit_spark(it["last"], Vector3.UP, 0.4)
	else:
		var at: Vector3 = it["to"]
		var hit := false
		for u in Game.query(0, at, 0.7):
			if u is Hero and (u as Hero).invuln > 0.0:
				continue
			u.take_damage(it["dmg"], it["source"], 0.5, "orb")
			hit = true
			break
		Sfx.play("orb_hit", at, -8.0 if hit else -12.0, randf_range(0.9, 1.1))
		if Game.fx:
			Game.fx.motes(at, 8, Color(0.65, 0.55, 1.0))
			Game.fx.ring(Vector3(at.x, Game.island.height_at(at.x, at.z) + 0.05, at.z), 0.9, Color(0.6, 0.5, 1.0, 0.6), 0.3)
