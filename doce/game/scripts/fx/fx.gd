class_name Fx
extends Node3D
## Pooled effects (Game.fx). Particles live in fixed-size packed arrays (no allocation per particle or per frame)
## and are drawn with one MultiMesh per kind, written in a single buffer upload:
##   puff    lit low-poly puffs (dust, smoke, splashes), cast shadows
##   spark   additive four-point anime sparkles (hit sparks, motes, glints)
##   streak  additive soft streaks laid in the camera plane along their velocity (impact lines, sword sparks)
##   coin    gold coins (kept from PHAROS)
##   flash   the impact stars, as spark but pulled FLASH_PULL m towards the camera (never hidden by the hero)
## Rings and lightning are pooled / short-lived meshes. API (positions in world space):
##   dust(at, n, spread)  smoke(at, n, col)  splash(at, size)  hit_spark(at, dir, scale)  motes(at, n, col)
##   impact(at, dir, power, col)   the blow-lands burst: a white star flash, radial streaks, sparks (power 0.5..2)
##   glint(at, size, col, dur)     a star that swells and fades (telegraphs, a charged blow, the chain target)
##   daze(node, height, seconds)   little stars circling over a stunned head
##   ring(at, radius, col, dur)  lightning(at, big, col)  flash_screen(col, dur)  coin_fly  coin_burst

const MAX := {"puff": 384, "spark": 384, "streak": 160, "coin": 64, "flash": 48}
## The impact flashes ("flash" pool: the white star where a blow lands) are pulled this far towards the camera, so
## the hero's own body (between the camera and the contact when seen from behind) never hides the moment a blow
## lands; their size is cut in proportion so they still read as being at the contact point.
const FLASH_PULL := 1.9
## Per-particle floats: age, life, size0, size1, grav, drag, spin, rot, stretch
const NF := 9

var _pools := {}
var _rings: Array = []
var _ring_pool: Array = []
var _bolts: Array = []
var _dazes: Array = []
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _ring_mesh: ArrayMesh


## One particle kind: fixed-size packed arrays mutated in place (members of this object, so no copy-on-write)
## and the MultiMesh they are uploaded to in one buffer write per frame.
class Pool:
	var kind := ""
	var cap := 0
	var n := 0
	var ovr := 0
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var col := PackedColorArray()
	var f := PackedFloat32Array()
	var buf := PackedFloat32Array()
	var mm: MultiMesh

	func _init(k: String, capacity: int, multimesh: MultiMesh) -> void:
		kind = k
		cap = capacity
		mm = multimesh
		pos.resize(cap)
		vel.resize(cap)
		col.resize(cap)
		f.resize(cap * NF)
		buf.resize(cap * 16)

	func emit(p: Vector3, v: Vector3, life: float, size0: float, size1: float, c: Color, grav: float, drag: float, spin: float, stretch: float) -> void:
		var i := n
		if i >= cap:
			i = ovr
			ovr = (ovr + 1) % cap
		else:
			n += 1
		pos[i] = p
		vel[i] = v
		col[i] = c
		var o := i * NF
		f[o] = 0.0
		f[o + 1] = maxf(life, 0.01)
		f[o + 2] = size0
		f[o + 3] = size1
		f[o + 4] = grav
		f[o + 5] = drag
		f[o + 6] = spin
		f[o + 7] = randf() * TAU
		f[o + 8] = stretch

	func step(delta: float, cb: Basis) -> void:
		if n == 0:
			if mm.visible_instance_count != 0:
				mm.visible_instance_count = 0
			return
		var i := 0
		while i < n:
			var o := i * NF
			var age := f[o] + delta
			if age >= f[o + 1]:
				# swap-remove: the last particle takes this slot
				n -= 1
				if i != n:
					pos[i] = pos[n]
					vel[i] = vel[n]
					col[i] = col[n]
					var on := n * NF
					for j in NF:
						f[o + j] = f[on + j]
				continue
			f[o] = age
			var v := vel[i]
			v.y += f[o + 4] * delta
			v *= maxf(0.0, 1.0 - f[o + 5] * delta)
			vel[i] = v
			var p := pos[i] + v * delta
			pos[i] = p
			f[o + 7] += f[o + 6] * delta
			var k := age / f[o + 1]
			var sz := lerpf(f[o + 2], f[o + 3], k)
			var b: Basis
			var c := col[i]
			match kind:
				"puff":
					sz *= Rig.ease_out(minf(k * 4.0, 1.0))
					b = Basis.from_scale(Vector3.ONE * maxf(sz, 0.001))
				"coin":
					b = Basis(Vector3.UP, f[o + 7]) * Basis.from_scale(Vector3.ONE * maxf(sz, 0.001))
				"streak":
					# laid in the camera plane along the velocity's projection, `stretch` times longer than wide
					var vx := cb.x.dot(v)
					var vy := cb.y.dot(v)
					var ang := atan2(vy, vx) if (absf(vx) + absf(vy)) > 1e-4 else 0.0
					var w := maxf(sz, 0.001) * (1.0 - k * 0.5)
					var l := w * f[o + 8] * (0.5 + 0.5 * clampf(v.length() / 6.0, 0.0, 1.0))
					b = cb * Basis(Vector3.BACK, ang) * Basis.from_scale(Vector3(l, w, 1.0))
					c.a *= 1.0 - k * k
				_:
					b = Basis.from_scale(Vector3.ONE * maxf(sz, 0.001))
					c.a *= 1.0 - k * k
			var q := i * 16
			buf[q] = b.x.x
			buf[q + 1] = b.y.x
			buf[q + 2] = b.z.x
			buf[q + 3] = p.x
			buf[q + 4] = b.x.y
			buf[q + 5] = b.y.y
			buf[q + 6] = b.z.y
			buf[q + 7] = p.y
			buf[q + 8] = b.x.z
			buf[q + 9] = b.y.z
			buf[q + 10] = b.z.z
			buf[q + 11] = p.z
			buf[q + 12] = c.r
			buf[q + 13] = c.g
			buf[q + 14] = c.b
			buf[q + 15] = c.a
			i += 1
		mm.buffer = buf
		mm.visible_instance_count = n


func _ready() -> void:
	var puff := MeshBuilder.new(51)
	puff.ico(Vector3.ZERO, 0.5, Color.WHITE, 0, 0.12)
	_add_mm("puff", puff.commit(), Materials.lowpoly(), true)
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_add_mm("spark", q, Materials.glow_star(), false)
	var qf := QuadMesh.new()
	qf.size = Vector2.ONE
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = load("res://shaders/glow.gdshader") as Shader
	flash_mat.set_shader_parameter("star", true)
	flash_mat.set_shader_parameter("pull", FLASH_PULL)
	_add_mm("flash", qf, flash_mat, false)
	var q2 := QuadMesh.new()
	q2.size = Vector2.ONE
	var streak_mat := ShaderMaterial.new()
	streak_mat.shader = load("res://shaders/glow.gdshader") as Shader
	streak_mat.set_shader_parameter("billboard", false)
	streak_mat.set_shader_parameter("uv_falloff", true)
	streak_mat.set_shader_parameter("pull", 0.3)
	_add_mm("streak", q2, streak_mat, false)
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
	_pools[kind] = Pool.new(kind, MAX[kind], mm)


## One particle. `stretch` (streaks): length / width of the streak along its velocity.
func _emit(kind: String, pos: Vector3, vel: Vector3, life: float, size0: float, size1: float, col: Color, grav: float = 0.0, drag: float = 1.0, spin: float = 0.0, stretch: float = 1.0) -> void:
	(_pools[kind] as Pool).emit(pos, vel, life, size0, size1, col, grav, drag, spin, stretch)


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


## Size factor of a flash star at `at`: pulled FLASH_PULL m closer, it is drawn smaller in proportion.
func _flash_k(at: Vector3) -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 1.0
	var d := cam.global_position.distance_to(at)
	return clampf((d - FLASH_PULL) / maxf(d, 0.01), 0.15, 1.0)


func hit_spark(at: Vector3, dir: Vector3, scale_k: float = 1.0) -> void:
	var fk := _flash_k(at)
	_emit("flash", at, Vector3.ZERO, 0.12, 1.4 * scale_k * fk, 0.3 * scale_k * fk, Color(1.0, 0.95, 0.8, 1.0))
	for i in int(6 * scale_k) + 2:
		var d := (dir + Vector3(randf_range(-0.8, 0.8), randf_range(-0.2, 0.9), randf_range(-0.8, 0.8))).normalized()
		_emit("streak", at, d * randf_range(4.0, 8.0), randf_range(0.12, 0.24), 0.07 * scale_k, 0.0, Color(1.0, 0.82, 0.45, 1.0), -7.0, 3.0, 0.0, 6.0)


func motes(at: Vector3, n: int, col: Color) -> void:
	for i in n:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		_emit("spark", at + d * 0.2, d * randf_range(0.8, 2.5) + Vector3(0, 0.8, 0), randf_range(0.5, 1.1), randf_range(0.2, 0.4), 0.0, Color(col.r, col.g, col.b, 1.0), 0.3, 1.5)


## The burst where a blow lands: a white star flash, radial impact streaks and a few hot sparks. `power` ~0.6 for a
## light blow, 1 for a finisher, 1.5 for a heavy one; `dir` the blow's direction (the sparks fly along it).
func impact(at: Vector3, dir: Vector3, power: float = 1.0, col: Color = Color(1.0, 0.96, 0.86)) -> void:
	var fk := _flash_k(at)
	# the star: about the size of a torso for a light blow, a body for the heavy one (it must not hide them)
	_emit("flash", at, Vector3.ZERO, 0.07 + 0.03 * power, (1.0 * power + 0.6) * fk, 0.35 * power * fk, Color(col.r, col.g, col.b, 1.0))
	_emit("flash", at, Vector3.ZERO, 0.16 + 0.04 * power, (0.4 * power + 0.25) * fk, (1.4 * power + 0.4) * fk, Color(1.0, 0.85, 0.55, 0.5))
	var n := int(5 + power * 5.0)
	for i in n:
		var a := TAU * (float(i) + randf() * 0.6) / float(n)
		var d := Vector3(cos(a), sin(a) * 0.8 + 0.15, sin(a * 1.7) * 0.5).normalized()
		d = (d + dir.normalized() * 0.6).normalized()
		_emit("streak", at + d * 0.15, d * randf_range(6.0, 10.0) * (0.7 + 0.3 * power), randf_range(0.08, 0.14), 0.06 + 0.03 * power, 0.0, Color(col.r, col.g, col.b, 1.0), 0.0, 6.0, 0.0, 7.0)
	for i in int(3 + power * 4.0):
		var d2 := (dir.normalized() + Vector3(randf_range(-0.9, 0.9), randf_range(-0.1, 1.0), randf_range(-0.9, 0.9))).normalized()
		_emit("streak", at, d2 * randf_range(3.0, 7.0), randf_range(0.18, 0.32), 0.05, 0.0, Color(1.0, 0.78, 0.4, 1.0), -9.0, 2.0, 0.0, 5.0)


## A four-point star that swells and fades at `at`: telegraph cues, a charged blow, the chain's target.
func glint(at: Vector3, size: float = 0.8, col: Color = Color(1.0, 0.92, 0.7), dur: float = 0.35) -> void:
	_emit("spark", at, Vector3.ZERO, dur, size * 0.15, size, Color(col.r, col.g, col.b, 1.0), 0.0, 0.0, 2.5)


## Little stars circling over a stunned head: follows `node` for `seconds` (`height` above its origin).
func daze(node: Node3D, height: float, seconds: float, radius: float = 0.35) -> void:
	for d in _dazes:
		if d[0] == node:
			d[1] = maxf(float(d[1]), seconds)
			return
	_dazes.append([node, seconds, height, radius, randf() * TAU])


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
		_emit("streak", at + Vector3(0, 0.3, 0), d * randf_range(3.0, 8.0), randf_range(0.2, 0.45), 0.08, 0.0, Color(0.85, 0.92, 1.0, 1.0), -8.0, 3.0, 0.0, 6.0)
	dust(at, 8, 1.0)
	_flash_light.global_position = at + Vector3(0, 3.0, 0)
	_flash_light.light_color = col
	_flash_t = 0.25


func flash_screen(col: Color, dur: float) -> void:
	if Game.hud and Game.hud.has_method("screen_flash"):
		Game.hud.screen_flash(col, dur)


# --- update ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var cb := cam.global_transform.basis if cam else Basis.IDENTITY
	_step_dazes(delta)
	for kind in _pools:
		(_pools[kind] as Pool).step(delta, cb)
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


func _step_dazes(delta: float) -> void:
	for i in range(_dazes.size() - 1, -1, -1):
		var d: Array = _dazes[i]
		var node := d[0] as Node3D
		d[1] = float(d[1]) - delta
		if node == null or not is_instance_valid(node) or not node.is_inside_tree() or float(d[1]) <= 0.0:
			_dazes.remove_at(i)
			continue
		d[4] = float(d[4]) + delta * 4.2
		var c := node.global_position + Vector3(0.0, float(d[2]), 0.0)
		var r := float(d[3])
		# three short-lived stars re-emitted every frame along the orbit (cheap and always in place)
		for k in 3:
			var a := float(d[4]) + TAU * float(k) / 3.0
			var p := c + Vector3(cos(a) * r, sin(a * 2.0) * 0.05, sin(a) * r)
			_emit("spark", p, Vector3.ZERO, delta * 1.6, 0.22, 0.22, Color(1.0, 0.9, 0.45, 1.0))
