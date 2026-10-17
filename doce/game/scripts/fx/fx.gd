class_name Fx
extends Node3D
## Pooled effects (Game.fx). Particles live in fixed-size packed arrays (no allocation per particle or per frame)
## and are drawn with one MultiMesh per kind, written in a single buffer upload:
##   puff    lit low-poly puffs (dust, smoke, splashes), cast shadows
##   spark   additive four-point anime sparkles (hit sparks, motes, glints)
##   streak  additive soft streaks laid in the camera plane along their velocity (impact lines, sword sparks)
##   coin    gold coins (kept from PHAROS)
##   flash   the impact stars, as spark but pulled FLASH_PULL m towards the camera (never hidden by the hero)
##   slash   the cut flashes (slash_mark): thin crescents (or a thrust's pierce ring) in the camera plane, pulled like
##           the flashes; this pool runs in REAL time, so a flash snaps open and thins away during a blow's hit-stop
##   chunk   lit low-poly lumps of earth / stone chips (slam): tumble, hop on the ground, shrink away
##   dust    flat two-tone toon puffs in the camera plane (shaders/dust.gdshader): the slam's dust ring and cloud
## Rings, ground marks and lightning are pooled / short-lived meshes. API (positions in world space):
##   dust(at, n, spread)  smoke(at, n, col)  splash(at, size)  hit_spark(at, dir, scale)  motes(at, n, col)
##   impact(at, dir, power, col, star = 1.0)  the blow-lands burst: a white star flash, radial streaks, sparks
##                                 (power 0.5..2; `star` scales the star alone; smaller with a slash_mark())
##   slash_mark(at, cut_dir, size = 1.0, col = warm white)  the anime cut flash where a blade bites (goes with
##                                 impact(); size 1 light, 1.5 finisher, 1.8 heavy): a long thin crescent along the
##                                 cut, snapping open, thinning away in ~0.14 s; a pierce ring for a thrust
##   slam(at, power = 1.0, surface = "")  a ground impact (a chop into the ground, the dash's landing): shock ring, dust ring
##                                 rolling out, ground streaks, hopping chunks, cracks on stone / a dent on sand
##                                 (power 0.6 landing .. 1 chop .. 1.5)
##   glint(at, size, col, dur)     a star that swells and fades (telegraphs, a charged blow, the chain target)
##   daze(node, height, seconds)   little stars circling over a stunned head
##   ring(at, radius, col, dur, thin = false)  lightning(at, big, col)  flash_screen(col, dur)  coin_fly  coin_burst

const MAX := {"puff": 384, "spark": 384, "streak": 160, "coin": 64, "flash": 48, "slash": 24, "chunk": 48, "dust": 96}
## The pools stepped in real time (Game.real_delta): they play through the hit-stop.
const REAL_TIME := {"slash": true}
## Seconds a cut flash takes to open to its full length.
const SLASH_OPEN := 0.03
## A cut whose direction crosses the view less than this (0..1: the share of it in the screen's plane) is driving
## into the screen (a thrust seen from behind): slash_mark draws the pierce ring instead of the line.
const SLASH_PIERCE := 0.35
## impact() and slash_mark() at the same point in the same frame: the star is drawn this much smaller (the cut's
## line is the moment; the star backs it up).
const STAR_WITH_SLASH := 0.5
## Cracks left by a slam on stone: how many at once, how long they stay (s; the last third fades).
const CRACK_MAX := 4
const CRACK_LIFE := 1.5
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
## FX lane: the slam's cracks ([MeshInstance3D, age]) and the spare ones.
var _cracks: Array = []
var _crack_pool: Array = []
## FX lane: the last cut flash and the last impact star (point and process frame), so the two tone each other.
var _slash_at := Vector3(INF, INF, INF)
var _slash_frame := -1
var _star_at := Vector3(INF, INF, INF)
var _star_frame := -1
var _ring_thin_mesh: ArrayMesh


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

	## FX lane: scales the sizes of the particles born in the last `max_age` s within `radius` m of `at` by `k`
	## (slash_mark tones down the star impact() has just drawn at the same point).
	func scale_recent(at: Vector3, radius: float, max_age: float, k: float) -> void:
		for i in n:
			var o := i * NF
			if f[o] <= max_age and pos[i].distance_squared_to(at) <= radius * radius:
				f[o + 2] *= k
				f[o + 3] *= k

	func step(delta: float, cb: Basis) -> void:
		if n == 0:
			if mm.visible_instance_count != 0:
				mm.visible_instance_count = 0
			return
		var still := kind == "slash"
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
			var p := pos[i]
			if not still:
				v.y += f[o + 4] * delta
				v *= maxf(0.0, 1.0 - f[o + 5] * delta)
				vel[i] = v
				p += v * delta
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
				"slash":
					# a cut flash, laid in the camera plane; it stays put. `stretch` slot = the shape (slash.gdshader:
					# the instance's z scale carries it): 1 the cut, along `vel` (its direction), always pointing right
					# so it bows upwards; it snaps open from 15 % to its full length (size0) in SLASH_OPEN s, keeps
					# its width (size1) a moment, then thins away while it fades. 2 the pierce: a ring (size0 across)
					# that bursts from a third of its size to the full size and fades.
					if f[o + 8] < 1.5:
						var sx := cb.x.dot(v)
						var sy := cb.y.dot(v)
						var sa := atan2(sy, sx) if (absf(sx) + absf(sy)) > 1e-4 else 0.0
						if sx < 0.0:
							sa += PI
						var op := minf(age / SLASH_OPEN, 1.0)
						var sl := maxf(f[o + 2] * (0.15 + 0.85 * (1.0 - (1.0 - op) * (1.0 - op))), 0.001)
						var sw := maxf(f[o + 3] * (1.0 - 0.85 * smoothstep(0.25, 1.0, k)), 0.001)
						b = cb * Basis(Vector3.BACK, sa) * Basis.from_scale(Vector3(sl, sw, 1.0))
						c.a *= 1.0 - smoothstep(0.55, 1.0, k)
					else:
						var rs := maxf(f[o + 2] * lerpf(0.35, 1.0, 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)), 0.001)
						b = cb * Basis(Vector3.BACK, f[o + 7]) * Basis.from_scale(Vector3(rs, rs, 2.0))
						c.a *= 1.0 - smoothstep(0.45, 1.0, k)
				"dust":
					# a flat toon puff in the camera plane, unrotated (its shading stays lit from above); its lobes'
					# seed rides in the z scale (dust.gdshader). It swells from 45 % to its full size (size0) in the
					# first third of its life, then shrinks towards size1 while it fades over the last 40 %.
					var gr := 1.0 - (1.0 - minf(k * 3.0, 1.0)) * (1.0 - minf(k * 3.0, 1.0))
					var ds := lerpf(f[o + 2] * 0.45, f[o + 2], gr)
					ds = maxf(lerpf(ds, f[o + 3], smoothstep(0.35, 1.0, k)), 0.001)
					b = cb * Basis.from_scale(Vector3(ds, ds, 1.0 + fposmod(f[o + 7], 1.0)))
					c.a *= 1.0 - smoothstep(0.6, 1.0, k)
				"chunk":
					# a lump of earth / a stone chip: hops off the ground (its height in the `stretch` slot), tumbles,
					# shrinks away at the end of its life
					if p.y < f[o + 8] and v.y < 0.0:
						p.y = f[o + 8]
						v = Vector3(v.x * 0.5, -v.y * 0.36, v.z * 0.5)
						vel[i] = v
						pos[i] = p
						f[o + 6] *= 0.55
					var r := f[o + 7]
					var cs := maxf(sz * (1.0 - smoothstep(0.7, 1.0, k)), 0.001)
					b = Basis.from_euler(Vector3(r, r * 0.7, r * 0.4)) * Basis.from_scale(Vector3.ONE * cs)
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
	# FX lane: the cut flashes and the slam's chunks
	var qs := QuadMesh.new()
	qs.size = Vector2.ONE
	var slash_mat := ShaderMaterial.new()
	slash_mat.shader = load("res://shaders/slash.gdshader") as Shader
	slash_mat.set_shader_parameter("pull", FLASH_PULL)
	slash_mat.render_priority = 11
	_add_mm("slash", qs, slash_mat, false)
	var qd := QuadMesh.new()
	qd.size = Vector2.ONE
	var dust_mat := ShaderMaterial.new()
	dust_mat.shader = load("res://shaders/dust.gdshader") as Shader
	_add_mm("dust", qd, dust_mat, false)
	var chunk := MeshBuilder.new(57)
	chunk.ico(Vector3.ZERO, 0.5, Color.WHITE, 0, 0.28, Vector3(1.0, 0.72, 0.9))
	_add_mm("chunk", chunk.commit(), Materials.lowpoly(), true)
	var rb := MeshBuilder.new(55)
	rb.ring(Vector3.ZERO, 1.0, 0.86, 0.02, 40, Color.WHITE)
	_ring_mesh = rb.commit()
	var rt := MeshBuilder.new(56)
	rt.ring(Vector3.ZERO, 1.0, 0.955, 0.02, 48, Color.WHITE)
	_ring_thin_mesh = rt.commit()
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
## light blow, 1 for a finisher, 1.5 for a heavy one; `dir` the blow's direction (the sparks fly along it). FX lane:
## `star` scales the star alone (1 = as before); with a slash_mark() at the same point in the same frame (either
## order) the star is drawn STAR_WITH_SLASH smaller.
func impact(at: Vector3, dir: Vector3, power: float = 1.0, col: Color = Color(1.0, 0.96, 0.86), star: float = 1.0) -> void:
	var fk := _flash_k(at) * maxf(star, 0.0)
	var now := Engine.get_process_frames()
	if _slash_frame == now and _slash_at.distance_to(at) < 0.6:
		fk *= STAR_WITH_SLASH
	_star_at = at
	_star_frame = now
	# the star: about the size of a torso for a light blow, a body for the heavy one (it must not hide them)
	if fk > 0.0:
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


## FX lane. The anime cut flash where a blade bites. It goes WITH impact() (the star: this adds none; called at the
## same point in the same frame, either order, the star is drawn STAR_WITH_SLASH smaller). A long thin crescent laid
## across `at` along `cut_dir` (the blade's motion at the contact, world; it bows a little like the swing's arc):
## it snaps open in SLASH_OPEN s, holds its width a moment and thins away by ~0.13 s of REAL time (it plays through
## the blow's hit-stop: the freeze frame shows it whole), a white core inside a rim of `col`, with a few short
## streaks flying on along the cut. A cut that drives into the screen (a thrust seen from behind: less than
## SLASH_PIERCE of it across the view) draws the pierce instead: a thin ring with four spikes bursting open round
## the point, streaks all round. Pulled FLASH_PULL m towards the camera like the stars (the hero's own body never
## hides it). `size`: 1 a light blow (the line about 2 m long), 1.5 a finisher, 1.8 the heavy spin.
func slash_mark(at: Vector3, cut_dir: Vector3, size: float = 1.0, col: Color = Color(1.0, 0.88, 0.62)) -> void:
	if size <= 0.0:
		return
	var d := cut_dir.normalized() if cut_dir.length_squared() > 1e-8 else Vector3.RIGHT
	var s := maxf(size, 0.1)
	var fk := _flash_k(at)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var vb := cam.global_transform.basis if cam else Basis.IDENTITY
	var across := Vector2(vb.x.dot(d), vb.y.dot(d)).length()
	var c := Color(col.r, col.g, col.b, 1.0)
	var hot := Color(1.0, 0.97, 0.88, 1.0)
	if across < SLASH_PIERCE:
		_emit("slash", at, d, 0.15 + 0.02 * s, 0.9 * s * fk, 0.0, c, 0.0, 0.0, 0.0, 2.0)
		for i in int(5.0 + 2.0 * s):
			var a := TAU * (float(i) + randf_range(-0.25, 0.25)) / (5.0 + 2.0 * s)
			var sd := (vb.x * cos(a) + vb.y * sin(a) + d * 0.3).normalized()
			_emit("streak", at + sd * 0.12 * s, sd * randf_range(5.0, 8.0) * (0.8 + 0.2 * s), randf_range(0.07, 0.12),
				0.045 * (0.8 + 0.2 * s), 0.0, hot, 0.0, 5.0, 0.0, 8.0)
	else:
		_emit("slash", at, d, 0.12 + 0.02 * s, 2.0 * s * fk, 0.26 * s * fk, c, 0.0, 0.0, 0.0, 1.0)
		for i in int(3.0 + 2.0 * s):
			var sd2 := (d + Vector3(randf_range(-0.2, 0.2), randf_range(-0.12, 0.22), randf_range(-0.2, 0.2))).normalized()
			_emit("streak", at + d * randf_range(0.2, 0.55) * s, sd2 * randf_range(6.0, 10.0) * (0.8 + 0.2 * s),
				randf_range(0.07, 0.12), 0.04 * (0.8 + 0.2 * s), 0.0, hot, 0.0, 5.0, 0.0, 10.0)
	var now := Engine.get_process_frames()
	if _star_frame == now and _star_at.distance_to(at) < 0.6 and not (_slash_frame == now and _slash_at.distance_to(at) < 0.6):
		(_pools["flash"] as Pool).scale_recent(_star_at, 0.05, 0.02, STAR_WITH_SLASH)
	_slash_at = at
	_slash_frame = now


## FX lane. A ground impact (a chop that bites into the ground, the dash's landing): a thin shock ring racing out
## low over the ground, a ring of big light dust puffs rolling outwards and settling, a low cloud where it hit,
## streaks racing out along the ground, chunks of earth / stone chips hopping, and a mark that fades within
## CRACK_LIFE s: dark cracks on stone, a dent on sand (none on grass: the meadow's blades would hide it). `at`: where
## it hits (dropped onto the ground below it, world layer); `power`: ~0.6 the dash's landing, 1 a chop, 1.5 the
## heaviest. The dust and the chunks take the ground's kind (World.surface_at: grass, sand, stone; stone where the
## world cannot say; `surface` "grass" / "sand" / "stone" overrides it). The caller adds the shake / kick and the
## sound (`slam`).
func slam(at: Vector3, power: float = 1.0, surface: String = "") -> void:
	if power <= 0.0:
		return # (a move table's `slam` 0 = none)
	var p := clampf(power, 0.2, 2.5)
	var g := _ground_point(at)
	var surf := surface if surface != "" else _surface(g)
	var tint := _dust_tint(surf)
	ring(g + Vector3(0, 0.03, 0), 1.5 + 1.0 * p, Color(1.0, 0.97, 0.9, 0.15), 0.16, true)
	# the dust ring rolling out: flat toon puffs that swell as they roll a metre or two, overlap into a bank of dust,
	# and shrink away
	var n := int(14.0 + 6.0 * p)
	for i in n:
		var a := TAU * (float(i) + randf() * 0.5) / float(n)
		var d := Vector3(cos(a), 0.0, sin(a))
		var c := tint.lerp(Color.WHITE, randf_range(0.0, 0.18))
		var sz := randf_range(0.62, 0.86) * (0.75 + 0.3 * p)
		_emit("dust", g + d * randf_range(0.3, 0.5) + Vector3(0, sz * 0.35, 0), d * randf_range(3.6, 5.0) * (0.75 + 0.25 * p)
			+ Vector3(0, randf_range(0.2, 0.6), 0), randf_range(0.55, 0.8), sz, sz * 0.4, c, -0.4, 4.0, 0.0, 1.0)
	# the cloud where it hit: a few bigger puffs rising slowly, and some kicked up higher
	for i in int(3.0 + 2.0 * p):
		var d2 := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var sz2 := randf_range(0.8, 1.05) * (0.8 + 0.2 * p)
		_emit("dust", g + d2 * 0.3 + Vector3(0, 0.35, 0), d2 * 0.7 + Vector3(0, randf_range(0.9, 1.6), 0),
			randf_range(0.7, 0.95), sz2, sz2 * 0.5, tint.lerp(Color.WHITE, 0.12), -0.2, 2.4, 0.0, 1.0)
	for i in int(2.0 + 2.0 * p):
		var d5 := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_emit("dust", g + d5 * 0.4 + Vector3(0, 0.3, 0), d5 * 1.6 + Vector3(0, randf_range(2.6, 3.6), 0),
			randf_range(0.5, 0.7), 0.42, 0.15, tint.lerp(Color.WHITE, 0.2), -4.0, 2.0, 0.0, 1.0)
	# streaks racing out along the ground
	var ns := int(6.0 + 5.0 * p)
	for i in ns:
		var a2 := TAU * (float(i) + randf() * 0.7) / float(ns)
		var d3 := Vector3(cos(a2), 0.0, sin(a2))
		_emit("streak", g + d3 * 0.3 + Vector3(0, 0.08, 0), (d3 + Vector3(0, 0.08, 0)) * randf_range(8.0, 12.0) * (0.8 + 0.2 * p),
			randf_range(0.1, 0.16), 0.06 + 0.02 * p, 0.0, tint.lerp(Color.WHITE, 0.7), 0.0, 4.0, 0.0, 7.0)
	# chunks hopping (on grass: clods of earth and a few green tufts; on sand: wet clumps; on stone: chips)
	var nc := int(4.0 + 5.0 * p)
	for i in nc:
		var a3 := TAU * (float(i) + randf() * 0.8) / float(nc)
		var d4 := Vector3(cos(a3), 0.0, sin(a3))
		var cc := _chunk_color(surf, i)
		var sz3 := randf_range(0.12, 0.22) * (0.8 + 0.25 * p)
		_emit("chunk", g + d4 * randf_range(0.15, 0.4) + Vector3(0, 0.1, 0), d4 * randf_range(1.2, 2.8) * (0.8 + 0.2 * p)
			+ Vector3(0, randf_range(4.0, 6.0) * (0.75 + 0.25 * p), 0), randf_range(0.9, 1.2), sz3, sz3, cc, -17.0, 0.4,
			randf_range(-14.0, 14.0), g.y + sz3 * 0.3)
	if surf == "stone" or surf == "sand":
		_mark(g, p, surf)


## The ground under `at` (a short ray down on the world layer), or `at` itself over nothing.
func _ground_point(at: Vector3) -> Vector3:
	if not is_inside_tree():
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.8, 0), at - Vector3(0, 2.5, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else at


func _surface(g: Vector3) -> String:
	var w = Game.world
	if w != null and is_instance_valid(w) and w.has_method("surface_at"):
		return String(w.call("surface_at", g + Vector3(0, 0.05, 0)))
	return "stone"


func _dust_tint(surf: String) -> Color:
	match surf:
		"sand":
			return Pal.SAND
		"grass":
			return Pal.PATH.lerp(Pal.SAND, 0.5).lightened(0.1)
	return Pal.ROCK.lightened(0.22)


func _chunk_color(surf: String, i: int) -> Color:
	match surf:
		"grass":
			return Pal.GRASS_DARK if i % 3 == 2 else Pal.PATH_DARK.darkened(randf_range(0.15, 0.3))
		"sand":
			return Pal.SAND_WET.darkened(randf_range(0.0, 0.12))
	return Pal.ROCK_DARK.lerp(Pal.ROCK, randf())


## The slam's mark on the ground at `g`, in the plane three short rays find around it (skipped on broken ground),
## held, then fading over the last third of CRACK_LIFE s: on stone dark jagged cracks out of a dark dent, on sand a
## shallow darker dent with a lighter rim of thrown sand.
func _mark(g: Vector3, p: float, surf: String) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var pts: Array[Vector3] = []
	var a0 := randf() * TAU
	for k in 3:
		var a := a0 + TAU * float(k) / 3.0
		var o := g + Vector3(cos(a), 0.0, sin(a)) * 0.6
		var q := PhysicsRayQueryParameters3D.create(o + Vector3(0, 0.5, 0), o - Vector3(0, 0.8, 0), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - g.y) > 0.25:
			return
		pts.append(hit["position"])
	var nrm := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	if nrm.y < 0.85:
		return
	var mi: MeshInstance3D
	var im: ImmediateMesh
	if _crack_pool.is_empty():
		if _cracks.size() >= CRACK_MAX:
			return
		mi = MeshInstance3D.new()
		im = ImmediateMesh.new()
		mi.mesh = im
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/fx.gdshader") as Shader
		m.set_shader_parameter("view_pull", 0.05)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
	else:
		mi = _crack_pool.pop_back()
		im = mi.mesh as ImmediateMesh
		mi.visible = true
	var x := nrm.cross(Vector3.FORWARD if absf(nrm.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(nrm).normalized()
	mi.global_transform = Transform3D(Basis(x, nrm, z), g + nrm * 0.015)
	if surf == "sand":
		_build_dent(im, p)
	else:
		_build_crack(im, p)
	(mi.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", 1.0)
	_cracks.append([mi, 0.0])


## The crack's mesh in its local ground plane (x, z): a dark dent and 5..7 jagged lines with a branch or two.
func _build_crack(im: ImmediateMesh, p: float) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.2, 0.16, 0.13, 0.78)
	# the dent: an irregular dark star in the middle
	var nd := 7
	var prev := Vector3.ZERO
	for i in nd + 1:
		var a := TAU * float(i % nd) / float(nd)
		var r := (0.12 + 0.07 * sin(float(i % nd) * 2.7)) * (0.8 + 0.25 * p)
		var v := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if i > 0:
			_crack_tri(im, Vector3.ZERO, prev, v, col)
		prev = v
	var lines := randi_range(5, 7)
	for l in lines:
		var a := TAU * (float(l) + randf_range(-0.3, 0.3)) / float(lines)
		var length := randf_range(0.45, 0.85) * (0.75 + 0.3 * p)
		_crack_line(im, Vector3(cos(a), 0, sin(a)) * 0.1, a, length, 0.055 * (0.8 + 0.2 * p), col, l % 2 == 0)
	im.surface_end()


## The sand's dent in its local ground plane: a darker irregular disc (wet sand pushed down) inside a ring of
## lighter thrown sand.
func _build_dent(im: ImmediateMesh, p: float) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Pal.SAND_WET.darkened(0.12)
	dark.a = 0.55
	var lite := Pal.SAND.lightened(0.18)
	lite.a = 0.5
	var nd := 14
	var r0 := 0.42 * (0.8 + 0.25 * p)
	var prev := Vector3.ZERO
	var prev_o := Vector3.ZERO
	var first := Vector3.ZERO
	var first_o := Vector3.ZERO
	for i in nd + 1:
		var a := TAU * float(i % nd) / float(nd)
		var r := r0 * (1.0 + 0.16 * sin(float(i % nd) * 2.3) + 0.08 * sin(float(i % nd) * 5.1))
		var v := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var vo := Vector3(cos(a), 0.0, sin(a)) * (r + 0.16 * (0.8 + 0.2 * p))
		if i == 0:
			first = v
			first_o = vo
		if i > 0:
			_crack_tri(im, Vector3.ZERO, prev, v, dark)
			_crack_tri(im, prev, prev_o, vo, lite)
			_crack_tri(im, prev, vo, v, lite)
		prev = v
		prev_o = vo
	im.surface_end()


func _crack_line(im: ImmediateMesh, from: Vector3, ang: float, length: float, w: float, col: Color, branch: bool) -> void:
	var segs := 4
	var p0 := from
	var a := ang
	for s in segs:
		a += randf_range(-0.45, 0.45)
		var step := length / float(segs)
		var p1 := p0 + Vector3(cos(a), 0, sin(a)) * step
		var w0 := w * (1.0 - float(s) / float(segs))
		var w1 := w * (1.0 - float(s + 1) / float(segs))
		var side0 := Vector3(-sin(a), 0, cos(a)) * w0 * 0.5
		var side1 := Vector3(-sin(a), 0, cos(a)) * w1 * 0.5
		_crack_tri(im, p0 - side0, p0 + side0, p1 + side1, col)
		_crack_tri(im, p0 - side0, p1 + side1, p1 - side1, col)
		if branch and s == 1:
			_crack_line(im, p1, a + randf_range(0.6, 1.0) * (1.0 if randf() < 0.5 else -1.0), length * 0.45, w1, col, false)
		p0 = p1


func _crack_tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(a)
	im.surface_set_color(col)
	im.surface_add_vertex(b)
	im.surface_set_color(col)
	im.surface_add_vertex(c)


func _step_cracks(delta: float) -> void:
	for i in range(_cracks.size() - 1, -1, -1):
		var cr: Array = _cracks[i]
		cr[1] = float(cr[1]) + delta
		var mi: MeshInstance3D = cr[0]
		var k := float(cr[1]) / CRACK_LIFE
		if k >= 1.0:
			mi.visible = false
			_crack_pool.append(mi)
			_cracks.remove_at(i)
			continue
		(mi.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", 1.0 - smoothstep(0.66, 1.0, k))


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


func ring(at: Vector3, radius: float, col: Color, dur: float = 0.5, thin: bool = false) -> void:
	var mi: MeshInstance3D
	if _ring_pool.is_empty():
		mi = MeshInstance3D.new()
		mi.material_override = Materials.glow_flat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		mi = _ring_pool.pop_back()
		mi.visible = true
	# FX lane: `thin` = a band a third as wide (the slam's shock ring)
	mi.mesh = _ring_thin_mesh if thin else _ring_mesh
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
	var real_dt := minf(Game.real_delta(delta), 0.1)
	for kind in _pools:
		(_pools[kind] as Pool).step(real_dt if REAL_TIME.has(kind) else delta, cb)
	_step_cracks(delta)
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
