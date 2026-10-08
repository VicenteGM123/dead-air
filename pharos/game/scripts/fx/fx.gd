class_name Fx
extends Node3D
## Lightweight effects. Particles are drawn with three MultiMeshes (lit puffs, additive sparks, gold coins) so
## a screen full of dust, smoke and sparks costs three draw calls. Rings and lightning are pooled meshes.

const MAX := {"puff": 320, "spark": 320, "coin": 64}

var _mm := {}
var _parts := {"puff": [], "spark": [], "coin": []}
var _rings: Array = []
var _ring_pool: Array = []
var _bolts: Array = []
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _ring_mesh: ArrayMesh


func _ready() -> void:
	var puff := MeshBuilder.new(51)
	puff.ico(Vector3.ZERO, 0.5, Color.WHITE, 0, 0.12)
	_add_mm("puff", puff.commit(), Materials.lowpoly(), true)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_add_mm("spark", q, Materials.glow_add(), false)
	var coin := MeshBuilder.new(53)
	coin.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	coin.cyl(Vector3(0, -0.03, 0), 0.06, 0.16, 0.16, 10, Pal.GOLD, true, 0.0, Pal.GOLD.lightened(0.15))
	coin.pop()
	_add_mm("coin", coin.commit(), Materials.lowpoly(), true)
	var rb := MeshBuilder.new(55)
	rb.ring(Vector3.ZERO, 1.0, 0.86, 0.02, 40, Color.WHITE)
	_ring_mesh = rb.commit()
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(0.75, 0.85, 1.0)
	_flash_light.omni_range = 18.0
	_flash_light.light_energy = 0.0
	_flash_light.visible = false
	add_child(_flash_light)


func _add_mm(kind: String, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MAX[kind]
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 1000.0
	add_child(mmi)
	_mm[kind] = mm


func _emit(kind: String, pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, col: Color, grav: float = 0.0, drag: float = 1.0, spin: float = 0.0) -> void:
	var arr: Array = _parts[kind]
	if arr.size() >= MAX[kind]:
		arr.pop_front()
	arr.append([pos, vel, 0.0, life, size0, size1, col, grav, drag, spin, randf() * TAU])


# --- public effects ----------------------------------------------------------------------------------------

func dust(at: Vector3, n: int = 6, spread: float = 0.6) -> void:
	for i in n:
		var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var p := at + d * randf() * spread + Vector3(0, 0.15, 0)
		var c := Pal.SAND.lerp(Pal.PATH, randf()).lightened(0.05)
		_emit("puff", p, d * randf_range(0.6, 1.8) + Vector3(0, randf_range(0.4, 1.2), 0), randf_range(0.45, 0.8), randf_range(0.18, 0.3), 0.0, c, -0.5, 2.5)


func smoke(at: Vector3, n: int = 4, col: Color = Color(0.55, 0.52, 0.5)) -> void:
	for i in n:
		var p := at + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.3), randf_range(-0.4, 0.4))
		_emit("puff", p, Vector3(randf_range(-0.3, 0.3), randf_range(0.8, 1.6), randf_range(-0.3, 0.3)), randf_range(0.9, 1.5), randf_range(0.25, 0.45), 0.05, col, 0.0, 0.6)


func splash(at: Vector3, size: float = 1.0) -> void:
	for i in int(10 * size):
		var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_emit("puff", at + d * 0.3 * size, d * randf_range(0.8, 2.2) * size + Vector3(0, randf_range(2.5, 4.5), 0), randf_range(0.5, 0.8), randf_range(0.1, 0.2) * size, 0.02, Color(0.92, 0.97, 1.0), -9.0, 0.6)
	ring(at + Vector3(0, 0.05, 0), 1.6 * size, Color(0.92, 0.97, 1.0, 0.75), 0.6)


func hit_spark(at: Vector3, dir: Vector3, scale_k: float = 1.0) -> void:
	_emit("spark", at, Vector3.ZERO, 0.12, 1.4 * scale_k, 0.3 * scale_k, Color(1.0, 0.95, 0.8, 1.0))
	for i in int(6 * scale_k) + 2:
		var d := (dir + Vector3(randf_range(-0.8, 0.8), randf_range(-0.2, 0.9), randf_range(-0.8, 0.8))).normalized()
		_emit("spark", at, d * randf_range(3.0, 7.0), randf_range(0.15, 0.3), 0.28 * scale_k, 0.0, Color(1.0, 0.82, 0.45, 1.0), -6.0, 4.0)


func motes(at: Vector3, n: int, col: Color) -> void:
	for i in n:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		_emit("spark", at + d * 0.2, d * randf_range(0.8, 2.5) + Vector3(0, 0.8, 0), randf_range(0.5, 1.1), randf_range(0.2, 0.4), 0.0, Color(col.r, col.g, col.b, 1.0), 0.3, 1.5)


func coin_fly(from: Vector3, to: Vector3) -> void:
	var dur := 0.45
	var v := (to - from) / dur + Vector3(0, 0.5 * 14.0 * dur, 0)
	_emit("coin", from, v, dur, 1.0, 0.7, Color.WHITE, -14.0, 0.0, 14.0)


func coin_burst(at: Vector3, n: int) -> void:
	for i in n:
		var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_emit("coin", at, d * randf_range(1.0, 2.5) + Vector3(0, randf_range(4.0, 6.5), 0), randf_range(0.7, 1.0), 1.0, 0.6, Color.WHITE, -14.0, 0.2, 12.0)
		if i % 2 == 0:
			_emit("spark", at + Vector3(0, 0.5, 0), d * 1.5 + Vector3(0, 2.0, 0), 0.6, 0.35, 0.0, Color(1.0, 0.85, 0.4, 1.0), 0.0, 1.0)


func ring(at: Vector3, radius: float, col: Color, dur: float = 0.5) -> void:
	var mi: MeshInstance3D
	if _ring_pool.is_empty():
		mi = MeshInstance3D.new()
		mi.mesh = _ring_mesh
		mi.material_override = Materials.glow_flat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		mi = _ring_pool.pop_back()
		mi.visible = true
	mi.global_position = at + Vector3(0, 0.08, 0)
	Materials.set_param(mi, "tint_color", Vector3(col.r, col.g, col.b))
	_rings.append([mi, 0.0, dur, radius, col.a])


func lightning(at: Vector3, big: bool, col: Color = Color(0.82, 0.9, 1.0)) -> void:
	var mb := MeshBuilder.new(randi())
	var top := at + Vector3(randf_range(-2, 2), 22.0, randf_range(-2, 2))
	var pts: Array[Vector3] = [top]
	var segs := 9
	for i in range(1, segs + 1):
		var k := float(i) / segs
		var p := top.lerp(at + Vector3(0, 0.2, 0), k)
		if i < segs:
			p += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * (1.2 * (1.0 - k) + 0.3)
		pts.append(p)
	var w := 0.16 if big else 0.1
	for i in pts.size() - 1:
		mb.limb(pts[i] - at, pts[i + 1] - at, w, w * 0.8, 4, Color(col.r, col.g, col.b, 0.5))
	# A couple of forks.
	for f in 2:
		var j := randi_range(2, segs - 3)
		var a := pts[j]
		var b := a + Vector3(randf_range(-2.5, 2.5), randf_range(-3.0, -1.5), randf_range(-2.5, 2.5))
		mb.limb(a - at, b - at, w * 0.6, 0.0, 4, Color(col.r, col.g, col.b, 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	_bolts.append([mi, 0.0, 0.28 if big else 0.22])
	_emit("spark", at + Vector3(0, 0.6, 0), Vector3.ZERO, 0.25, 5.0 if big else 3.2, 1.0, Color(col.r, col.g, col.b, 1.0))
	for i in 10:
		var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		_emit("spark", at + Vector3(0, 0.3, 0), d * randf_range(3.0, 8.0), randf_range(0.2, 0.45), 0.3, 0.0, Color(0.85, 0.92, 1.0, 1.0), -8.0, 3.0)
	dust(at, 8, 1.0)
	_flash_light.global_position = at + Vector3(0, 3.0, 0)
	_flash_light.light_color = col
	_flash_t = 0.25


func flash_screen(col: Color, dur: float) -> void:
	if Game.hud and Game.hud.has_method("screen_flash"):
		Game.hud.screen_flash(col, dur)


# --- update ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	for kind in _parts:
		var arr: Array = _parts[kind]
		var mm: MultiMesh = _mm[kind]
		var i := 0
		while i < arr.size():
			var p: Array = arr[i]
			p[2] += delta
			if p[2] >= p[3]:
				arr.remove_at(i)
				continue
			var v: Vector3 = p[1]
			v.y += p[7] * delta
			v *= maxf(0.0, 1.0 - p[8] * delta)
			p[1] = v
			p[0] += v * delta
			p[10] += p[9] * delta
			i += 1
		var n := arr.size()
		mm.visible_instance_count = n
		for j in n:
			var p: Array = arr[j]
			var k: float = p[2] / p[3]
			var sz: float
			if kind == "puff":
				# Grow quickly, then shrink away.
				sz = lerpf(p[4], p[5], k) * (Rig.ease_out(minf(k * 4.0, 1.0)))
			else:
				sz = lerpf(p[4], p[5], k)
			var b := Basis.from_scale(Vector3.ONE * maxf(sz, 0.001))
			if kind == "coin":
				b = Basis(Vector3.UP, p[10]) * Basis.from_scale(Vector3.ONE * maxf(sz, 0.001))
			mm.set_instance_transform(j, Transform3D(b, p[0]))
			var c: Color = p[6]
			if kind == "spark":
				c.a = c.a * (1.0 - k * k)
			mm.set_instance_color(j, c)
	for i in range(_rings.size() - 1, -1, -1):
		var r: Array = _rings[i]
		r[1] += delta
		var k: float = r[1] / r[2]
		var mi: MeshInstance3D = r[0]
		if k >= 1.0:
			mi.visible = false
			_ring_pool.append(mi)
			_rings.remove_at(i)
			continue
		var rad: float = lerpf(r[3] * 0.3, r[3], Rig.ease_out(k))
		mi.scale = Vector3(rad, 1.0, rad)
		Materials.set_param(mi, "intensity", (1.0 - k) * r[4] * 2.0)
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Array = _bolts[i]
		b[1] += delta
		var mi2: MeshInstance3D = b[0]
		mi2.visible = fmod(b[1], 0.08) < 0.06
		if b[1] >= b[2]:
			mi2.queue_free()
			_bolts.remove_at(i)
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash_light.visible = true
		_flash_light.light_energy = maxf(0.0, _flash_t / 0.25) * 6.0
	elif _flash_light.visible:
		_flash_light.visible = false
