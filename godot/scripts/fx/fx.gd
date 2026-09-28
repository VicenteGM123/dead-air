# FX (port of src/fx/fx.js; ARCHITECTURE §10/§12, GDD §3.7): big readable cartoon VFX, all pooled (no allocation per
# effect).
#   burst(pos, {count, color|colors, speed, size, life, gravity, shape, dir, cone, drag}) — shapes:
#     'spark' (additive streaks along velocity), 'puff' (lit toon sphere clouds), 'confetti' (tumbling bars
#     colors), 'goo' (glossy blobs), 'static' (TV-snow chips), 'star' (spinning glow stars).
#   tracer(from, to, color, width), muzzle(pos, dir, color), impact(point, normal, kind), decal(point, normal,
#   kind, size) (kinds: 'hole' | 'scorch' | 'splat' | 'goo'), lightPool(pos, radius, color, intensity) -> handle
#   ({set_({pos, radius, color, intensity}), remove()}), blob(node3d, radius) -> handle ({remove(), visible}),
#   text3d(pos, str, color), flashLight(pos, color, intensity, duration) (pooled light slot), shake(amount, dur).
# Every pool is a MultiMeshInstance3D (the JS InstancedMesh: one draw call each, none while empty: pools hide
# themselves). Particles use world dt (they freeze with time.scale=0); blobs follow their nodes every frame regardless.
#
# Port notes (engine plumbing only):
#  * RENAME (§3.2): the lightPool handle's set() is set_() (Object.set collides).
#  * The pools are built in init() (the JS builds them in the constructor; game.scene / mats / tex are ready by then).
#  * JS colours are sRGB hex converted to linear by THREE.Color.set: instance colours here are linear floats
#    (MultiMesh colours are float, so the HDR multipliers survive).
#  * Canvas textures (flash star, decals) are drawn with the Canvas2D emulation (DACanvas, SPEC §6), line by line.
#  * The FX particle meshes are the same three.js primitives, generated here (ports of three's Plane / Box /
#    Octahedron / Icosahedron / Cylinder generators); the extruded star particle is a Blender runtime asset
#    (blender/runtime/weapons_fx.py -> res://assets/runtime/weapons_fx/fx_star.glb).
#  * The scale curves are a match instead of per-pool closures (same numbers).
extends RefCounted

const ASSET_DIR := "res://assets/runtime/weapons_fx/"

var game
var pools := {}
var tracers := {}
var flashes := {}
var decals := {}
var pools2 := {}
var blobs := {}
var texts: Array = []
var _textHead := 0
var _ready := false
var _root: Node3D = null

const DEFAULTS := {
	"spark": {"count": 10, "speed": 7, "size": 0.05, "life": 0.35, "gravity": 14, "drag": 2, "colors": ["#FFE8A0", "#FFC23A", "#FFFFFF"]},
	"puff": {"count": 7, "speed": 1.6, "size": 0.22, "life": 0.7, "gravity": -0.6, "drag": 3, "colors": ["#F4F1E8", "#E6DCCB"]},
	"confetti": {"count": 16, "speed": 4.5, "size": 0.07, "life": 1.4, "gravity": 7, "drag": 1.4, "colors": Config.BARS},
	"goo": {"count": 8, "speed": 3.5, "size": 0.09, "life": 0.8, "gravity": 12, "drag": 1, "colors": ["#1E5BFF", "#4F86FF"]},
	"static": {"count": 14, "speed": 2.8, "size": 0.1, "life": 0.9, "gravity": 2, "drag": 2, "colors": ["#ffffff"]},
	"star": {"count": 5, "speed": 2.4, "size": 0.14, "life": 0.8, "gravity": 1, "drag": 2, "colors": ["#FFC23A", "#FFF3B0"]},
}

static var ZERO_T := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
const _UP := Vector3(0, 1, 0)
const _Z := Vector3(0, 0, 1)

# ================================================================================================ particle pool
# One particle shape = one MultiMeshInstance3D + struct-of-arrays simulation.
class ParticlePool extends RefCounted:
	var cap := 0
	var n := 0
	var align := false
	var fade := false
	var bounce := true
	var curve := ""
	var mesh: MultiMeshInstance3D
	var mm: MultiMesh
	var pos := PackedFloat32Array()
	var vel := PackedFloat32Array()
	var col := PackedFloat32Array()
	var life := PackedFloat32Array()
	var max_ := PackedFloat32Array()   # JS 'max'
	var size := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var spin := PackedFloat32Array()
	var grav := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var floor_ := PackedFloat32Array()   # JS 'floor'

	func _init(scene: Node, geometry: Mesh, material: Material, cap_: int, opts := {}, curve_ := "") -> void:
		cap = cap_
		align = opts.get("align", false)
		fade = opts.get("fade", false)
		bounce = opts.get("bounce", true)
		curve = curve_
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = geometry
		mm.instance_count = cap
		mm.visible_instance_count = 0
		mm.set_instance_color(0, Color(1, 1, 1))
		mesh = MultiMeshInstance3D.new()
		mesh.multimesh = mm
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))   # frustumCulled = false
		mesh.visible = false
		scene.add_child(mesh)
		for a in ["pos", "vel", "col"]:
			var arr := PackedFloat32Array()
			arr.resize(cap * 3)
			set(a, arr)
		for a in ["life", "max_", "size", "rot", "spin", "grav", "drag", "floor_"]:
			var arr := PackedFloat32Array()
			arr.resize(cap)
			set(a, arr)

	func spawn(x: float, y: float, z: float, vx: float, vy: float, vz: float, color: Color, sz: float, lf: float, gv: float, dg: float, fl: float) -> void:
		var i := n
		if i >= cap:
			i = int(floor(randf() * cap))   # recycle a random live particle
		else:
			n += 1
		pos[i * 3] = x; pos[i * 3 + 1] = y; pos[i * 3 + 2] = z
		vel[i * 3] = vx; vel[i * 3 + 1] = vy; vel[i * 3 + 2] = vz
		col[i * 3] = color.r; col[i * 3 + 1] = color.g; col[i * 3 + 2] = color.b
		size[i] = sz; life[i] = lf; max_[i] = lf
		rot[i] = randf() * PI * 2.0; spin[i] = (randf() - 0.5) * 16.0
		grav[i] = gv; drag[i] = dg; floor_[i] = fl
		mm.set_instance_color(i, Color(color.r, color.g, color.b, 1.0))

	func _kill(i: int) -> void:
		n -= 1
		var j := n
		if i == j:
			return
		for k in 3:
			pos[i * 3 + k] = pos[j * 3 + k]
			vel[i * 3 + k] = vel[j * 3 + k]
			col[i * 3 + k] = col[j * 3 + k]
		life[i] = life[j]; max_[i] = max_[j]; size[i] = size[j]; rot[i] = rot[j]; spin[i] = spin[j]
		grav[i] = grav[j]; drag[i] = drag[j]; floor_[i] = floor_[j]

	func update(dt: float) -> void:
		var i := 0
		while i < n:
			life[i] -= dt
			if life[i] <= 0.0:
				_kill(i)
				continue
			var i3 := i * 3
			var k := maxf(0.0, 1.0 - drag[i] * dt)
			vel[i3] *= k; vel[i3 + 2] *= k
			vel[i3 + 1] = vel[i3 + 1] * k - grav[i] * dt
			pos[i3] += vel[i3] * dt; pos[i3 + 1] += vel[i3 + 1] * dt; pos[i3 + 2] += vel[i3 + 2] * dt
			if bounce and pos[i3 + 1] < floor_[i]:
				pos[i3 + 1] = floor_[i]
				vel[i3 + 1] = absf(vel[i3 + 1]) * 0.3
				vel[i3] *= 0.6; vel[i3 + 2] *= 0.6
				spin[i] *= 0.5
			rot[i] += spin[i] * dt
			var t := 1.0 - life[i] / max_[i]
			var sc: float = size[i] * _scaleCurve(curve, t)
			var p := Vector3(pos[i3], pos[i3 + 1], pos[i3 + 2])
			var b: Basis
			if align:
				var v := Vector3(vel[i3], vel[i3 + 1], vel[i3 + 2])
				var sp := v.length()
				var q := quatFromUnitVectors(_Z, v / sp) if sp > 1e-4 else Quaternion.IDENTITY
				b = Basis(q) * Basis.from_scale(Vector3(sc, sc, sc * (1.0 + minf(sp, 12.0) * 0.9)))
			else:
				b = Basis.from_euler(Vector3(rot[i], rot[i] * 0.7, rot[i] * 0.3), EULER_ORDER_XYZ).scaled(Vector3(sc, sc, sc))
			mm.set_instance_transform(i, Transform3D(b, p))
			if fade:
				var f := 1.0 - t * t
				mm.set_instance_color(i, Color(col[i3] * f, col[i3 + 1] * f, col[i3 + 2] * f, 1.0))
			i += 1
		mm.visible_instance_count = n
		mesh.visible = n > 0   # an empty MultiMesh still costs a draw call + state changes

	static func _scaleCurve(c: String, t: float) -> float:
		match c:
			"spark": return 1.0 - t
			"puff": return (0.35 + 0.9 * (1.0 - pow(1.0 - t, 3.0))) * (1.0 - pow(t, 4.0))
			"confetti": return (1.0 - t) / 0.15 if t > 0.85 else 1.0
			"goo": return (1.0 - pow(t, 3.0)) * (t / 0.1 if t < 0.1 else 1.0)
			"static": return 1.0 - t * 0.6
			"star": return (t / 0.15 if t < 0.15 else 1.0 - (t - 0.15) / 0.85) * 1.1
		return 1.0

# Handle of a light pool (additive floor glow). RENAME: set() -> set_().
class LightPoolHandle extends RefCounted:
	var fx
	var index := 0
	var pos := Vector3.ZERO
	var radius := 2.0
	var color := Color(1, 1, 1)     # linear
	var intensity := 0.3

	func set_(o := {}) -> void:
		if o.get("pos") != null:
			pos = DAU.v3(o.pos)
		if o.has("radius") and o.radius != null:
			radius = o.radius
		if o.has("color") and o.color != null:
			color = DAU.color(o.color).srgb_to_linear()
		if o.has("intensity") and o.intensity != null:
			intensity = o.intensity
		fx._writePool(self)

	func remove() -> void:
		var P: Dictionary = fx.pools2.light
		var last = P.handles.pop_back()
		if last != self:
			P.handles[index] = last
			last.index = index
			fx._writePool(last)
		var mm: MultiMesh = P.mm
		mm.set_instance_transform(P.handles.size(), Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		mm.visible_instance_count = P.handles.size()
		P.mesh.visible = P.handles.size() > 0

# Handle of a blob shadow: { remove(), visible }.
class BlobHandle extends RefCounted:
	var object: Node3D
	var radius := 0.45
	var visible := true
	var _list: Array

	func remove() -> void:
		var i := -1
		for k in _list.size():
			if _list[k] == self:
				i = k
				break
		if i >= 0:
			_list.remove_at(i)

# Inert handles returned when a pool is full.
class NullPoolHandle extends RefCounted:
	func set_(_o := {}) -> void:
		pass
	func remove() -> void:
		pass

class NullBlobHandle extends RefCounted:
	var visible := false
	func remove() -> void:
		pass

# ================================================================================================ system
func _init(g) -> void:
	game = g

func init() -> void:
	if _ready:
		return
	var scene: Node = game.scene if game.scene != null else (game.render.get("scene") if game.render != null else null)
	if scene == null:
		push_error("[fx] no game.scene")
		return
	_ready = true
	_root = Node3D.new()
	_root.name = "fx"
	scene.add_child(_root)
	var M = game.mats

	# Particles.
	var sparkGeo := octahedronMesh(1.0)
	var starGeo := _loadMesh("fx_star.glb")
	if starGeo == null:
		starGeo = _starFallbackMesh(1.0, 0.45, 5, 0.25)
	var staticMat := basicMaterial({"map": _tex("staticNoise"), "side": "double"})
	var puffMat = M.toon("#ffffff", {"rough": 0.8, "rim": 0.4, "keepColor": true, "wrap": 0.8, "name": "fx:puff"}) if M != null else basicMaterial({})
	var gooMat = M.toon("#ffffff", {"rough": 0.15, "rim": 0.5, "keepColor": true, "name": "fx:goo"}) if M != null else basicMaterial({})
	pools = {
		"spark": ParticlePool.new(_root, sparkGeo, additiveMaterial(Color(3, 3, 3), null, "front"), 400, {"align": true, "fade": true}, "spark"),
		"puff": ParticlePool.new(_root, icosahedronMesh(1.0, 2), puffMat, 300, {"bounce": false}, "puff"),
		"confetti": ParticlePool.new(_root, planeMesh(1.0, 1.7), basicMaterial({"side": "double"}), 500, {}, "confetti"),
		"goo": ParticlePool.new(_root, icosahedronMesh(1.0, 2), gooMat, 200, {}, "goo"),
		"static": ParticlePool.new(_root, planeMesh(1.0, 1.0), staticMat, 300, {}, "static"),
		"star": ParticlePool.new(_root, starGeo, additiveMaterial(Color(2.4, 2.4, 2.4), null, "front"), 150, {"fade": true}, "star"),
	}

	# Tracers: unit box along +z scaled per shot.
	var tracerGeo := boxMesh(1, 1, 1, Vector3(0, 0, 0.5))
	var tcols: Array = []
	for i in 32:
		tcols.append(Color(1, 1, 1))
	tracers = _instanced(tracerGeo, additiveMaterial(Color(2.5, 2.5, 2.5), null, "front"), 32)
	tracers.merge({"life": _floats(32), "max": _floats(32), "col": tcols, "head": 0})

	# Muzzle flashes: crossed star cards.
	var flashTex := _flashTexture()
	var fg := GeoData.plane(1, 1)
	var cross := GeoData.merge([fg, GeoData.plane(1, 1).rotateY(PI / 2), GeoData.plane(1, 1).rotateX(PI / 2)])
	var flashMat := additiveMaterial(Color(3, 3, 3), flashTex, "double")
	var fdata: Array = []
	for i in 12:
		fdata.append({"pos": Vector3.ZERO, "q": Quaternion.IDENTITY, "size": 0.3})
	flashes = _instanced(cross.toMesh(), flashMat, 12)
	flashes.merge({"life": _floats(12), "head": 0, "data": fdata})

	# Decals.
	var decalGeo := planeMesh(1, 1)
	decals = {}
	for kind in ["hole", "scorch", "splat", "goo"]:
		var mat := decalMaterial(_decalTexture(kind))
		decals[kind] = _instanced(decalGeo, mat, 96)
		decals[kind]["head"] = 0
		decals[kind].mesh.visible = false   # until the first decal of this kind

	# Light pools (additive floor glow) and blob shadows.
	var poolGeo := GeoData.plane(2, 2).rotateX(-PI / 2).toMesh()
	var poolMat := additiveMaterial(Color(1, 1, 1), _tex("radial", [[0, "rgba(255,255,255,1)"], [0.35, "rgba(255,255,255,0.55)"], [1, "rgba(255,255,255,0)"]]), "front", false)
	var lp := _instanced(poolGeo, poolMat, 256)
	pools2 = {"light": {"mesh": lp.mesh, "mm": lp.mm, "cap": 256, "handles": []}}
	lp.mm.visible_instance_count = 0   # count = live handles (swap-remove keeps them packed)
	lp.mesh.visible = false
	var blobMat := blobMaterial(Config.PAL.shadow, _tex("radial", [[0, "rgba(255,255,255,1)"], [0.5, "rgba(255,255,255,0.6)"], [1, "rgba(255,255,255,0)"]]), 0.5)
	var bl := _instanced(poolGeo, blobMat, 64)
	blobs = {"mesh": bl.mesh, "mm": bl.mm, "cap": 64, "list": []}

	# Floating text sprites.
	texts = []
	for i in 8:
		var s := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		s.mesh = q
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.no_depth_test = true
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		sm.billboard_keep_scale = true
		sm.disable_fog = true
		sm.render_priority = 10
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		s.material_override = sm
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		_root.add_child(s)
		texts.append({"sprite": s, "mat": sm, "life": 0.0, "max": 1.0, "base": Vector3.ZERO, "scale": 1.0})
	_textHead = 0

func reset() -> void:
	if not _ready:
		return
	for k in pools:
		pools[k].n = 0
		pools[k].mm.visible_instance_count = 0
	tracers.life.fill(0.0)
	flashes.life.fill(0.0)
	for k in decals:
		var mm: MultiMesh = decals[k].mm
		for i in mm.instance_count:
			mm.set_instance_transform(i, ZERO_T)
		decals[k].mesh.visible = false
		decals[k].head = 0
	for t in texts:
		t.life = 0.0
		t.sprite.visible = false

func _flashTexture() -> Texture2D:
	var cv = _canvas(128, 128)
	if cv == null:
		return _fallbackRadial()
	var g = cv.getContext("2d")
	var r = g.createRadialGradient(64, 64, 0, 64, 64, 64)
	r.addColorStop(0, "rgba(255,255,255,1)"); r.addColorStop(0.25, "rgba(255,230,160,0.9)"); r.addColorStop(1, "rgba(255,160,60,0)")
	g.fillStyle = r
	g.beginPath()
	for i in 17:
		var a := (i / 16.0) * PI * 2.0
		var rr := 22.0 if i % 2 else 62.0
		if i == 0:
			g.moveTo(64 + cos(a) * rr, 64 + sin(a) * rr)
		else:
			g.lineTo(64 + cos(a) * rr, 64 + sin(a) * rr)
	g.fill()
	return cv.texture

func _decalTexture(kind: String) -> Texture2D:
	var c = _canvas(128, 128)
	if c == null:
		return _fallbackRadial()
	var g = c.getContext("2d")
	var rg := func(stops: Array):
		var r = g.createRadialGradient(64, 64, 0, 64, 64, 64)
		for s in stops:
			r.addColorStop(s[0], s[1])
		return r
	if kind == "hole":
		g.fillStyle = rg.call([[0, "rgba(40,24,48,1)"], [0.22, "rgba(58,42,90,0.95)"], [0.32, "rgba(255,240,220,0.35)"], [0.42, "rgba(58,42,90,0.25)"], [1, "rgba(58,42,90,0)"]])
		g.fillRect(0, 0, 128, 128)
	elif kind == "scorch":
		g.fillStyle = rg.call([[0, "rgba(40,26,40,0.85)"], [0.5, "rgba(58,42,90,0.45)"], [1, "rgba(58,42,90,0)"]])
		g.fillRect(0, 0, 128, 128)
	else:
		# Splat / goo: blobby cartoon puddle drawn white, tinted per instance.
		g.fillStyle = "#ffffff"
		g.beginPath(); g.arc(64, 64, 34, 0, PI * 2); g.fill()
		for i in 9:
			var a := (i / 9.0) * PI * 2.0 + randf() * 0.4
			var d := 30.0 + randf() * 18.0
			var r := 8.0 + randf() * 10.0
			g.beginPath(); g.arc(64 + cos(a) * d, 64 + sin(a) * d, r, 0, PI * 2); g.fill()
		g.globalCompositeOperation = "source-atop"
		g.fillStyle = "rgba(255,255,255,0.6)"
		g.beginPath(); g.ellipse(50, 48, 14, 8, -0.6, 0, PI * 2); g.fill()
	return c.texture

func _floorBelow(pos: Vector3) -> float:
	var col = game.level.get("col") if game.level != null else null
	var f: float = col.floorAt(pos.x, pos.z, pos.y + 0.1) if col != null else 0.0
	return f + 0.03 if f > -INF else -1e3

static func _opt(o: Dictionary, k: String, d):
	var v = o.get(k)
	return d if v == null else v

func burst(pos: Vector3, opts := {}) -> void:
	if not _ready:
		return
	var shape: String = opts.get("shape") if opts.get("shape") else "puff"
	var pool: ParticlePool = pools.get(shape, pools.puff)
	var d: Dictionary = DEFAULTS.get(shape, DEFAULTS.puff)
	var count: int = int(_opt(opts, "count", d.count))
	var speed: float = _opt(opts, "speed", d.speed)
	var size: float = _opt(opts, "size", d.size)
	var life: float = _opt(opts, "life", d.life)
	var grav: float = _opt(opts, "gravity", d.gravity)
	var drag: float = _opt(opts, "drag", d.drag)
	var colors: Array = opts.colors if opts.get("colors") else ([opts.color] if opts.get("color") else d.colors)
	var dir = opts.get("dir")
	var cone: float = _opt(opts, "cone", 0.7)
	var floor_y := _floorBelow(pos)
	for i in count:
		var v := Vector3(randf() * 2 - 1, randf() * 2 - 1, randf() * 2 - 1)
		if v.length_squared() < 1e-4:
			v = Vector3(0, 1, 0)
		v = v.normalized()
		if dir != null:
			v = (v * cone + dir).normalized()
		elif shape == "confetti" or shape == "star":
			v.y = absf(v.y) * 1.3 + 0.3
		var sp := speed * (0.45 + randf() * 0.75)
		var c := lin(colors[int(floor(randf() * colors.size()))])
		pool.spawn(pos.x, pos.y, pos.z, v.x * sp, v.y * sp, v.z * sp, c,
			size * (0.7 + randf() * 0.6), life * (0.7 + randf() * 0.6), grav, drag, floor_y)

func tracer(from: Vector3, to: Vector3, color = "#FFE9A8", width := 0.025) -> void:
	if not _ready:
		return
	var T := tracers
	var i: int = T.head
	T.head = (T.head + 1) % T.life.size()
	var len := from.distance_to(to)
	if len < 1e-3:
		return
	T.life[i] = 0.08; T.max[i] = 0.08
	T.mesh.visible = true
	T.col[i] = lin(color)
	var v := (to - from) / len
	var q := quatFromUnitVectors(_Z, v)
	T.mm.set_instance_transform(i, compose(from, q, Vector3(width, width, len)))
	T.mm.set_instance_color(i, T.col[i])

func muzzle(pos: Vector3, dir: Vector3, color = "#FFD27A") -> void:
	if not _ready:
		return
	var F := flashes
	var i: int = F.head
	F.head = (F.head + 1) % F.life.size()
	F.life[i] = 0.055
	F.mesh.visible = true
	var d: Dictionary = F.data[i]
	d.pos = pos
	var v := dir.normalized()
	var q := quatFromUnitVectors(_Z, v)
	d.q = q * Quaternion(_Z, randf() * PI)
	d.size = 0.32 + randf() * 0.12
	F.mm.set_instance_color(i, lin(color))
	burst(pos, {"shape": "spark", "count": 4, "dir": v, "cone": 0.35, "speed": 6, "life": 0.12, "size": 0.03, "colors": [color, "#ffffff"]})
	flashLight(pos, color, 6, 0.06)

func impact(point: Vector3, normal, kind := "wall") -> void:
	var n: Vector3 = normal if normal != null else _UP
	match kind:
		"zombie":
			burst(point, {"shape": "confetti", "count": 10, "dir": n, "cone": 1.2, "speed": 3.5})
			burst(point, {"shape": "puff", "count": 3, "size": 0.1, "colors": ["#DDF3E4", "#BFE3CC"], "life": 0.4})
		"metal":
			burst(point, {"shape": "spark", "count": 12, "dir": n, "cone": 0.9, "speed": 8})
			decal(point, n, "hole", 0.12)
		"wood":
			burst(point, {"shape": "confetti", "count": 6, "dir": n, "cone": 0.9, "speed": 3, "size": 0.05, "colors": [Config.PAL.teak, Config.PAL.walnut, Config.PAL.cream]})
			burst(point, {"shape": "puff", "count": 3, "size": 0.09, "life": 0.45, "colors": ["#E8D6B8"]})
			decal(point, n, "hole", 0.14)
		"glass":
			burst(point, {"shape": "star", "count": 4, "dir": n, "speed": 2, "size": 0.07})
		"goo":
			burst(point, {"shape": "goo", "count": 10, "dir": n, "cone": 1})
			decal(point, n, "goo", 0.8)
		_:
			burst(point, {"shape": "puff", "count": 4, "size": 0.1, "life": 0.5, "dir": n, "cone": 1, "speed": 1.4, "colors": ["#EFE6D6", "#D9CDB8"]})
			burst(point, {"shape": "spark", "count": 5, "dir": n, "cone": 0.8, "speed": 6, "life": 0.2})
			decal(point, n, "hole", 0.14)

func decal(point: Vector3, normal, kind := "hole", size := 0.15, color = "#ffffff") -> void:
	if not _ready:
		return
	var D: Dictionary = decals.get(kind, decals.hole)
	var i: int = D.head
	D.head = (D.head + 1) % D.cap
	D.mesh.visible = true
	var n: Vector3 = normal if normal != null else _UP
	var q := quatFromUnitVectors(_Z, n) * Quaternion(_Z, randf() * PI * 2.0)
	var p := point + n * 0.006
	D.mm.set_instance_transform(i, compose(p, q, Vector3(size, size, size)))
	D.mm.set_instance_color(i, lin(Config.PAL.chromaBlue if kind == "goo" else color))

# Additive floor glow under fixtures. Returns a handle: { set_({pos, radius, color, intensity}), remove() }.
func lightPool(pos, radius := 2.0, color = "#FFC98A", intensity := 0.3):
	if not _ready:
		return NullPoolHandle.new()
	var P: Dictionary = pools2.light
	if P.handles.size() >= P.cap:
		return NullPoolHandle.new()
	var h := LightPoolHandle.new()
	h.fx = self
	h.index = P.handles.size()
	h.pos = DAU.v3(pos)
	h.radius = radius
	h.color = lin(color)
	h.intensity = intensity
	P.handles.append(h)
	P.mm.visible_instance_count = P.handles.size()
	P.mesh.visible = true
	_writePool(h)
	return h

func _writePool(h) -> void:
	var mm: MultiMesh = pools2.light.mm
	mm.set_instance_transform(h.index, compose(h.pos, Quaternion.IDENTITY, Vector3(h.radius, 1, h.radius)))
	var c: Color = h.color
	mm.set_instance_color(h.index, Color(c.r * h.intensity, c.g * h.intensity, c.b * h.intensity, 1.0))

# Soft tinted shadow that follows `object3d` on the floor. Handle: { remove(), visible }.
func blob(object3d: Node3D, radius := 0.45):
	if not _ready:
		return NullBlobHandle.new()
	var B := blobs
	if B.list.size() >= B.cap:
		return NullBlobHandle.new()
	var h := BlobHandle.new()
	h.object = object3d
	h.radius = radius
	h.visible = true
	h._list = B.list
	B.list.append(h)
	return h

func text3d(pos: Vector3, s: String, color = "#FFE14D") -> void:
	if not _ready:
		return
	var t: Dictionary = texts[_textHead]
	_textHead = (_textHead + 1) % texts.size()
	var tex = null
	if game.tex != null and game.tex.has_method("text"):
		tex = game.tex.text(s, {"font": "Titan One", "size": 96, "color": color, "w": 512, "h": 128})
	t.mat.albedo_texture = tex
	t.base = pos
	t.life = 0.9
	t.max = 0.9
	t.sprite.visible = true

func flashLight(pos: Vector3, color = "#FFD08A", intensity := 8.0, duration := 0.08):
	if game.lights != null and game.lights.has_method("flash"):
		return game.lights.flash(pos, color, intensity, duration)
	return null

func shake(amount := 0.3, duration := 0.4) -> void:
	if game.cam != null:
		game.cam.shake(amount, duration)

func update(dt: float) -> void:
	if not _ready:
		return
	for k in pools:
		pools[k].update(dt)
	# Tracers fade out.
	var T := tracers
	var dirty := false
	for i in T.life.size():
		if T.life[i] <= 0.0:
			continue
		T.life[i] -= dt
		dirty = true
		if T.life[i] <= 0.0:
			T.mm.set_instance_transform(i, ZERO_T)
			continue
		var f: float = T.life[i] / T.max[i]
		var c: Color = T.col[i]
		T.mm.set_instance_color(i, Color(c.r * f, c.g * f, c.b * f, 1.0))
	T.mesh.visible = dirty
	# Muzzle flashes.
	var F := flashes
	var fd := false
	for i in F.life.size():
		if F.life[i] <= 0.0:
			continue
		F.life[i] -= dt
		fd = true
		var d: Dictionary = F.data[i]
		if F.life[i] <= 0.0:
			F.mm.set_instance_transform(i, ZERO_T)
			continue
		var s: float = d.size * (0.6 + 0.4 * (F.life[i] / 0.055))
		F.mm.set_instance_transform(i, compose(d.pos, d.q, Vector3(s, s, s * 1.6)))
	F.mesh.visible = fd
	# Floating texts: pop, rise, fade.
	for t in texts:
		if t.life <= 0.0:
			continue
		t.life -= dt
		var k: float = 1.0 - t.life / t.max
		if t.life <= 0.0:
			t.sprite.visible = false
			continue
		var pop: float = k / 0.15 * 1.2 if k < 0.15 else 1.2 - minf(0.2, (k - 0.15))
		t.sprite.position = t.base + Vector3(0, k * 0.8, 0)
		t.sprite.scale = Vector3(1.2 * pop, 0.3 * pop, 1)
		t.mat.albedo_color = Color(1, 1, 1, (1.0 - k) / 0.3 if k > 0.7 else 1.0)

func lateUpdate(_dt = 0.0) -> void:
	if not _ready:
		return
	var B := blobs
	var mm: MultiMesh = B.mm
	var col = game.level.get("col") if game.level != null else null
	mm.visible_instance_count = B.list.size()
	B.mesh.visible = B.list.size() > 0
	for i in B.list.size():
		var h = B.list[i]
		if not is_instance_valid(h.object):
			mm.set_instance_transform(i, ZERO_T)
			continue
		var p: Vector3 = DAU.worldPos(h.object)
		var f: float = col.floorAt(p.x, p.z, p.y + 0.2) if col != null else 0.0
		if not h.visible or not h.object.visible or f == -INF:
			mm.set_instance_transform(i, ZERO_T)
			continue
		var height := maxf(0.0, p.y - f)
		var k := maxf(0.0, 1.0 - height / 3.0)
		var r: float = h.radius * (1.0 + height * 0.25)
		mm.set_instance_transform(i, compose(Vector3(p.x, f + 0.015, p.z), Quaternion.IDENTITY, Vector3(r, 1, r)))
		mm.set_instance_color(i, Color(k, k, k, 1.0))

# ================================================================================================ helpers
# '#hex' | 'rgb()' | Color (sRGB) -> linear Color (THREE.Color.set converts sRGB input to linear).
static func lin(c) -> Color:
	var s := DAU.color(c)
	return Color(DAU.srgbToLinear(s.r), DAU.srgbToLinear(s.g), DAU.srgbToLinear(s.b), 1.0)

# THREE.Quaternion.setFromUnitVectors (same degenerate-case axis).
static func quatFromUnitVectors(vFrom: Vector3, vTo: Vector3) -> Quaternion:
	var r := vFrom.dot(vTo) + 1.0
	var q: Quaternion
	if r < 1e-8:
		r = 0.0
		if absf(vFrom.x) > absf(vFrom.z):
			q = Quaternion(-vFrom.y, vFrom.x, 0.0, r)
		else:
			q = Quaternion(0.0, -vFrom.z, vFrom.y, r)
	else:
		var c := vFrom.cross(vTo)
		q = Quaternion(c.x, c.y, c.z, r)
	return q.normalized()

# THREE.Matrix4.compose(position, quaternion, scale).
static func compose(p: Vector3, q: Quaternion, s: Vector3) -> Transform3D:
	return Transform3D(Basis(q) * Basis.from_scale(s), p)

static func _floats(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(0.0)
	return a

# JS instanced(): all `cap` instances drawn, parked at a zero matrix until used.
func _instanced(geometry: Mesh, material: Material, cap: int) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = geometry
	mm.instance_count = cap
	for i in cap:
		mm.set_instance_transform(i, ZERO_T)
		mm.set_instance_color(i, Color(1, 1, 1))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_root.add_child(mi)
	return {"mesh": mi, "mm": mm, "cap": cap}

func _canvas(w: int, h: int):
	if not ResourceLoader.exists("res://scripts/gfx/canvas2d.gd"):
		return null
	var C = load("res://scripts/gfx/canvas2d.gd")
	if C == null:
		return null
	return C.new(w, h)

# game.tex helpers (textures.gd): radial(stops) / staticNoise(); a plain radial fallback while it is missing.
func _tex(name: String, arg = null) -> Texture2D:
	var T = game.tex
	if T != null and T.has_method(name):
		var t = T.call(name, arg) if arg != null else T.call(name)
		if t is Texture2D:
			return t
	return _fallbackRadial()

var _fbRadial: Texture2D = null
func _fallbackRadial() -> Texture2D:
	if _fbRadial != null:
		return _fbRadial
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5 - 32, y + 0.5 - 32).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	_fbRadial = ImageTexture.create_from_image(img)
	return _fbRadial

func _loadMesh(file: String) -> Mesh:
	var path := ASSET_DIR + file
	if not ResourceLoader.exists(path):
		push_warning("[fx] missing runtime asset %s (run blender/build_all.py --only runtime)" % path)
		return null
	var ps = load(path)
	if ps is PackedScene:
		var inst: Node = ps.instantiate()
		var found: Array = [null]
		DAU.traverse(inst, func(o):
			if found[0] == null and o is MeshInstance3D:
				found[0] = (o as MeshInstance3D).mesh)
		inst.free()
		return found[0]
	return ps as Mesh

# Flat star prism (no bevel): only used while the Blender star asset is missing.
func _starFallbackMesh(r: float, inner: float, n: int, depth: float) -> Mesh:
	var G := GeoData.new()
	var pts: Array = []
	for i in n * 2:
		var a := (float(i) / (n * 2)) * PI * 2.0 + PI / 2.0
		var rr := r * inner if i % 2 else r
		pts.append(Vector2(cos(a) * rr, sin(a) * rr))
	var zs := [depth / 2.0, -depth / 2.0]
	for s in 2:
		var c := G.pos.size()
		G.pos.append(Vector3(0, 0, zs[s])); G.nor.append(Vector3(0, 0, 1 if s == 0 else -1)); G.uv.append(Vector2(0.5, 0.5))
		for p in pts:
			G.pos.append(Vector3(p.x, p.y, zs[s])); G.nor.append(Vector3(0, 0, 1 if s == 0 else -1)); G.uv.append(Vector2(0.5, 0.5))
		for i in pts.size():
			var a := c + 1 + i
			var b := c + 1 + (i + 1) % pts.size()
			if s == 0:
				G.idx.append_array([c, a, b])
			else:
				G.idx.append_array([c, b, a])
	for i in pts.size():
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		var nn := Vector3(p1.y - p0.y, -(p1.x - p0.x), 0).normalized()
		var b0 := G.pos.size()
		for v in [Vector3(p0.x, p0.y, zs[0]), Vector3(p1.x, p1.y, zs[0]), Vector3(p1.x, p1.y, zs[1]), Vector3(p0.x, p0.y, zs[1])]:
			G.pos.append(v); G.nor.append(nn); G.uv.append(Vector2.ZERO)
		G.idx.append_array([b0, b0 + 3, b0 + 1, b0 + 1, b0 + 3, b0 + 2])
	return G.toMesh()

# ------------------------------------------------------------------------------------------------ FX materials
static var _shaderCache := {}

static func _shader(code: String) -> Shader:
	if _shaderCache.has(code):
		return _shaderCache[code]
	var s := Shader.new()
	s.code = code
	_shaderCache[code] = s
	return s

const _ADD_CODE := """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, %s;
uniform vec3 tint = vec3(1.0);
uniform sampler2D map : source_color, hint_default_white, filter_linear_mipmap;
void fragment() {
	vec4 t = texture(map, UV);
	ALBEDO = tint * COLOR.rgb * t.rgb;
	ALPHA = t.a;
}
"""

# MeshBasicMaterial({ color, map, blending: Additive, transparent, depthWrite: false, toneMapped: false, fog }) with
# per-instance colour (and vertex colours when the mesh has them). tint = the linear material colour.
static func additiveMaterial(tint: Color, map: Texture2D = null, side := "front", fog := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var cull := "cull_disabled" if side == "double" else ("cull_front" if side == "back" else "cull_back")
	m.shader = _shader(_ADD_CODE % [cull + ("" if fog else ", fog_disabled")])
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	if map != null:
		m.set_shader_parameter("map", map)
	return m

const _BASIC_CODE := """shader_type spatial;
render_mode blend_mix, unshaded, %s;
uniform sampler2D map : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
void fragment() {
	vec4 t = texture(map, UV);
	ALBEDO = COLOR.rgb * t.rgb;
}
"""

# Opaque MeshBasicMaterial({ map?, side }) with per-instance colour.
static func basicMaterial(o := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(_BASIC_CODE % ["cull_disabled" if o.get("side") == "double" else "cull_back"])
	if o.get("map") != null:
		m.set_shader_parameter("map", o.map)
	return m

const _DECAL_CODE := """shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_back;
uniform sampler2D map : source_color, filter_linear_mipmap, repeat_disable;
uniform float bias = 4.0;
void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += bias * 6e-8 * POSITION.w;   // polygonOffset toward the camera (reverse-Z)
}
void fragment() {
	vec4 t = texture(map, UV);
	ALBEDO = COLOR.rgb * t.rgb;
	ALPHA = t.a;
}
"""

# MeshBasicMaterial({ map, transparent, depthWrite: false, polygonOffset -4 }) with per-instance colour.
static func decalMaterial(map: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(_DECAL_CODE)
	m.set_shader_parameter("map", map)
	return m

const _BLOB_CODE := """shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_back;
uniform vec3 color : source_color;
uniform float opacity = 0.5;
uniform sampler2D alpha_map : filter_linear_mipmap, repeat_disable;
void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 3.0 * 6e-8 * POSITION.w;
}
void fragment() {
	vec4 t = texture(alpha_map, UV);
	// three reads alphaMap.g of the uploaded (un-premultiplied) canvas: 1 wherever the canvas alpha is non-zero
	float g = t.a > 0.0 ? 1.0 : 0.0;
	ALBEDO = color;
	ALPHA = opacity * g * COLOR.r;   // alphaFromInstance: instanceColor.r scales opacity
}
"""

# Blob shadow: MeshBasicMaterial({ color: PAL.shadow, alphaMap, transparent, depthWrite: false, opacity, polygonOffset -3 })
# + alphaFromInstance (per-instance alpha in instanceColor.r).
static func blobMaterial(color, alphaMap: Texture2D, opacity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(_BLOB_CODE)
	m.set_shader_parameter("color", DAU.color(color))
	m.set_shader_parameter("opacity", opacity)
	m.set_shader_parameter("alpha_map", alphaMap)
	return m

# ------------------------------------------------------------------------------------------------ three.js geometry
# Ports of the three.js primitive generators used by the FX pools (three conventions: CCW front faces, v up);
# toMesh() converts to Godot (CW front faces, v down).
class GeoData extends RefCounted:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	static func plane(w: float, h: float) -> GeoData:
		var G := GeoData.new()
		for iy in 2:
			var y := iy * h - h / 2.0
			for ix in 2:
				var x := ix * w - w / 2.0
				G.pos.append(Vector3(x, -y, 0)); G.nor.append(Vector3(0, 0, 1)); G.uv.append(Vector2(ix, 1 - iy))
		G.idx.append_array([0, 2, 1, 2, 3, 1])
		return G

	static func box(w: float, h: float, d: float) -> GeoData:
		var G := GeoData.new()
		G._buildPlane(2, 1, 0, -1, -1, d, h, w)
		G._buildPlane(2, 1, 0, 1, -1, d, h, -w)
		G._buildPlane(0, 2, 1, 1, 1, w, d, h)
		G._buildPlane(0, 2, 1, 1, -1, w, d, -h)
		G._buildPlane(0, 1, 2, 1, -1, w, h, d)
		G._buildPlane(0, 1, 2, -1, -1, w, h, -d)
		return G

	func _buildPlane(u: int, v: int, w: int, udir: float, vdir: float, width: float, height: float, depth: float) -> void:
		var base := pos.size()
		for iy in 2:
			var y := iy * height - height / 2.0
			for ix in 2:
				var x := ix * width - width / 2.0
				var p := Vector3.ZERO
				p[u] = x * udir; p[v] = y * vdir; p[w] = depth / 2.0
				pos.append(p)
				var nn := Vector3.ZERO
				nn[w] = 1.0 if depth > 0 else -1.0
				nor.append(nn)
				uv.append(Vector2(ix, 1 - iy))
		var a := base; var b := base + 2; var c := base + 3; var dd := base + 1
		idx.append_array([a, b, dd, b, c, dd])

	static func cylinder(rt: float, rb: float, h: float, radial: int, openEnded := false) -> GeoData:
		var G := GeoData.new()
		var half := h / 2.0
		var slope := (rb - rt) / h
		var rows: Array = []
		for y in 2:
			var row: Array = []
			var vv := float(y)
			var radius := vv * (rb - rt) + rt
			for x in radial + 1:
				var uu := float(x) / radial
				var theta := uu * PI * 2.0
				var s := sin(theta); var c := cos(theta)
				row.append(G.pos.size())
				G.pos.append(Vector3(radius * s, -vv * h + half, radius * c))
				G.nor.append(Vector3(s, slope, c).normalized())
				G.uv.append(Vector2(uu, 1 - vv))
			rows.append(row)
		for x in radial:
			var a: int = rows[0][x]; var b: int = rows[1][x]; var c2: int = rows[1][x + 1]; var d: int = rows[0][x + 1]
			G.idx.append_array([a, b, d, b, c2, d])
		if not openEnded:
			if rt > 0:
				G._cap(true, rt, half, radial)
			if rb > 0:
				G._cap(false, rb, half, radial)
		return G

	func _cap(top: bool, radius: float, half: float, radial: int) -> void:
		var sign := 1.0 if top else -1.0
		var cStart := pos.size()
		for x in radial:
			pos.append(Vector3(0, half * sign, 0)); nor.append(Vector3(0, sign, 0)); uv.append(Vector2(0.5, 0.5))
		var cEnd := pos.size()
		for x in radial + 1:
			var theta := float(x) / radial * PI * 2.0
			var c := cos(theta); var s := sin(theta)
			pos.append(Vector3(radius * s, half * sign, radius * c)); nor.append(Vector3(0, sign, 0))
			uv.append(Vector2(c * 0.5 + 0.5, s * 0.5 * sign + 0.5))
		for x in radial:
			var c3 := cStart + x
			var i := cEnd + x
			if top:
				idx.append_array([i, i + 1, c3])
			else:
				idx.append_array([i + 1, i, c3])

	# PolyhedronGeometry (non-indexed; detail 0 = flat normals, else normals = unit positions).
	static func polyhedron(verts: Array, indices: Array, radius: float, detail: int) -> GeoData:
		var G := GeoData.new()
		var buf: Array = []
		for i in range(0, indices.size(), 3):
			var a: Vector3 = verts[indices[i]]; var b: Vector3 = verts[indices[i + 1]]; var c: Vector3 = verts[indices[i + 2]]
			var cols := detail + 1
			var v: Array = []
			for ii in cols + 1:
				var aj := a.lerp(c, float(ii) / cols)
				var bj := b.lerp(c, float(ii) / cols)
				var rows := cols - ii
				var row: Array = []
				for j in rows + 1:
					if j == 0 and ii == cols:
						row.append(aj)
					else:
						row.append(aj.lerp(bj, float(j) / rows))
				v.append(row)
			for ii in cols:
				for j in 2 * (cols - ii) - 1:
					var k := j / 2
					if j % 2 == 0:
						buf.append_array([v[ii][k + 1], v[ii + 1][k], v[ii][k]])
					else:
						buf.append_array([v[ii][k + 1], v[ii + 1][k + 1], v[ii + 1][k]])
		for p in buf:
			var q: Vector3 = (p as Vector3).normalized() * radius
			G.pos.append(q)
			G.nor.append(q.normalized())
			G.uv.append(Vector2.ZERO)
			G.idx.append(G.pos.size() - 1)
		if detail == 0:
			for i in range(0, G.pos.size(), 3):
				var n := (G.pos[i + 2] - G.pos[i + 1]).cross(G.pos[i] - G.pos[i + 1]).normalized()
				G.nor[i] = n; G.nor[i + 1] = n; G.nor[i + 2] = n
		return G

	func rotateX(a: float) -> GeoData:
		return applyBasis(Basis(Vector3(1, 0, 0), a))

	func rotateY(a: float) -> GeoData:
		return applyBasis(Basis(Vector3(0, 1, 0), a))

	func rotateZ(a: float) -> GeoData:
		return applyBasis(Basis(Vector3(0, 0, 1), a))

	func applyBasis(b: Basis) -> GeoData:
		for i in pos.size():
			pos[i] = b * pos[i]
			nor[i] = (b * nor[i]).normalized()
		return self

	func translate(x: float, y: float, z: float) -> GeoData:
		for i in pos.size():
			pos[i] += Vector3(x, y, z)
		return self

	func setColor(c: Color) -> GeoData:
		col.resize(pos.size())
		for i in pos.size():
			col[i] = c
		return self

	static func merge(list: Array) -> GeoData:
		var G := GeoData.new()
		for g in list:
			var base := G.pos.size()
			G.pos.append_array(g.pos); G.nor.append_array(g.nor); G.uv.append_array(g.uv)
			if g.col.size() == g.pos.size():
				G.col.append_array(g.col)
			for i in g.idx:
				G.idx.append(i + base)
		if G.col.size() != G.pos.size():
			G.col = PackedColorArray()
		return G

	func toMesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		var uv2 := PackedVector2Array()
		uv2.resize(uv.size())
		for i in uv.size():
			uv2[i] = Vector2(uv[i].x, 1.0 - uv[i].y)
		arr[Mesh.ARRAY_TEX_UV] = uv2
		if col.size() == pos.size() and col.size() > 0:
			arr[Mesh.ARRAY_COLOR] = col
		var ix := PackedInt32Array()
		ix.resize(idx.size())
		for i in range(0, idx.size(), 3):
			ix[i] = idx[i]; ix[i + 1] = idx[i + 2]; ix[i + 2] = idx[i + 1]
		arr[Mesh.ARRAY_INDEX] = ix
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

static func planeMesh(w: float, h: float) -> ArrayMesh:
	return GeoData.plane(w, h).toMesh()

static func boxMesh(w: float, h: float, d: float, offset := Vector3.ZERO) -> ArrayMesh:
	return GeoData.box(w, h, d).translate(offset.x, offset.y, offset.z).toMesh()

static func octahedronMesh(r: float) -> ArrayMesh:
	var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var i := [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2]
	return GeoData.polyhedron(v, i, r, 0).toMesh()

static func icosahedronMesh(r: float, detail: int) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var i := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2,
		3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	return GeoData.polyhedron(v, i, r, detail).toMesh()
