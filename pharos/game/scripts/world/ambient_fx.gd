class_name AmbientFx
extends Node3D
## Small particle pools for the ambient life: hearts and warm sparkles when a cat is petted, sea splashes for the
## dolphins. Each pool is one MultiMesh driven from code with fixed-size arrays (no per-frame allocations); a
## pool with nothing alive is hidden, so idle pools cost nothing.

enum { HEART, SPARK, DROP }

const FOAM := Color(0.95, 0.98, 1.0, 0.92)
const WARM := Color(1.0, 0.80, 0.46, 1.0)

var hearts_pool: Pool
var sparks_pool: Pool
var drops_pool: Pool


class Pool:
	var mm: MultiMesh
	var mmi: MultiMeshInstance3D
	var cap := 0
	var kind := 0
	var gravity := 0.0
	var drag := 0.0
	var alive := 0
	var next := 0
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var size := PackedFloat32Array()
	var seed := PackedFloat32Array()
	var col := PackedColorArray()

	func _init(parent: Node3D, mesh: Mesh, mat: Material, capacity: int, k: int, grav: float, drg: float) -> void:
		cap = capacity
		kind = k
		gravity = grav
		drag = drg
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = cap
		mmi = MultiMeshInstance3D.new()
		mmi.name = ["Hearts", "Sparkles", "Splash"][k]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 60, 300))
		mmi.visible = false
		parent.add_child(mmi)
		pos.resize(cap)
		vel.resize(cap)
		age.resize(cap)
		life.resize(cap)
		size.resize(cap)
		seed.resize(cap)
		col.resize(cap)
		life.fill(0.0)
		var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
		for i in cap:
			mm.set_instance_transform(i, zero)
			mm.set_instance_color(i, Color(1, 1, 1, 0))

	func emit(p: Vector3, v: Vector3, l: float, s: float, c: Color) -> void:
		var i := next
		next = (next + 1) % cap
		if life[i] <= 0.0:
			alive += 1
		pos[i] = p
		vel[i] = v
		age[i] = 0.0
		life[i] = l
		size[i] = s
		seed[i] = randf() * TAU
		col[i] = c
		mmi.visible = true

	func update(dt: float) -> void:
		if alive == 0:
			return
		var n := 0
		var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
		for i in cap:
			if life[i] <= 0.0:
				continue
			var a := age[i] + dt
			age[i] = a
			var k := a / life[i]
			var v := vel[i]
			v.y -= gravity * dt
			v /= 1.0 + drag * dt
			vel[i] = v
			var p := pos[i] + v * dt
			pos[i] = p
			if k >= 1.0 or (kind == DROP and p.y < -0.2 and v.y < 0.0):
				life[i] = 0.0
				mm.set_instance_transform(i, zero)
				continue
			n += 1
			var s := size[i]
			var alpha := 1.0
			var draw := p
			match kind:
				HEART:
					var x := minf(k / 0.18, 1.0) - 1.0
					s *= 1.0 + 2.70158 * x * x * x + 1.70158 * x * x # ease-out-back pop
					alpha = 1.0 - smoothstep(0.62, 1.0, k)
					draw.x += sin(a * 4.5 + seed[i]) * 0.06
				SPARK:
					s *= sin(minf(k * 1.4, 1.0) * PI * 0.5) * (1.0 - k * 0.6)
					alpha = (0.65 + 0.35 * sin(a * 18.0 + seed[i])) * (1.0 - smoothstep(0.5, 1.0, k))
				DROP:
					s *= 1.0 - 0.45 * k
					alpha = 1.0 - smoothstep(0.65, 1.0, k)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), draw))
			var c := col[i]
			c.a *= alpha
			mm.set_instance_color(i, c)
		alive = n
		if n == 0:
			mmi.visible = false


func _ready() -> void:
	hearts_pool = Pool.new(self, ModelsAnimals.heart_mesh(), ModelsAnimals.fx_billboard(false), 24, HEART, 0.0, 1.6)
	sparks_pool = Pool.new(self, ModelsAnimals.quad_mesh(), Materials.glow_add(), 48, SPARK, -0.2, 2.0)
	drops_pool = Pool.new(self, ModelsAnimals.quad_mesh(), ModelsAnimals.fx_billboard(true), 96, DROP, 9.8, 0.3)


## Hearts rising from `p` (petting feedback), with a pinch of warm sparkles. n > 1 fans them out (a burst).
func hearts(p: Vector3, n: int = 1) -> void:
	if hearts_pool == null:
		return
	for i in n:
		var fan := (float(i) - float(n - 1) * 0.5) * 0.45
		var v := Vector3(fan + randf_range(-0.12, 0.12), randf_range(0.95, 1.2) - absf(fan) * 0.3, randf_range(-0.12, 0.12))
		hearts_pool.emit(p + Vector3(fan * 0.25, 0, randf_range(-0.06, 0.06)), v, randf_range(1.5, 1.8), randf_range(0.42, 0.5), Color.WHITE)
	sparkles(p, 2 + n)


func sparkles(p: Vector3, n: int = 3, c: Color = WARM) -> void:
	if sparks_pool == null:
		return
	for i in n:
		var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.1, 0.3)
		sparks_pool.emit(p + d, d * 0.6 + Vector3(0, randf_range(0.3, 0.8), 0), randf_range(0.7, 1.1), randf_range(0.14, 0.22), c)


## Spray of droplets where something breaks the sea surface. strength ~1 for a dolphin.
func splash(p: Vector3, strength: float = 1.0) -> void:
	if drops_pool == null:
		return
	var n := int(14.0 * strength)
	for i in n:
		var a := randf() * TAU
		var h := randf_range(0.5, 2.0) * strength
		var v := Vector3(cos(a) * h, randf_range(2.4, 4.8) * sqrt(strength), sin(a) * h)
		drops_pool.emit(Vector3(p.x, 0.05, p.z) + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 0.35), v, randf_range(0.7, 1.1), randf_range(0.11, 0.22) * (0.7 + 0.3 * strength), FOAM)
	# A few slow, larger puffs of spray.
	for i in 4:
		var a2 := randf() * TAU
		drops_pool.emit(Vector3(p.x, 0.1, p.z), Vector3(cos(a2) * 0.6, randf_range(1.2, 2.0), sin(a2) * 0.6), randf_range(0.45, 0.7), randf_range(0.35, 0.5) * strength, Color(1, 1, 1, 0.45))


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	hearts_pool.update(dt)
	sparks_pool.update(dt)
	drops_pool.update(dt)
