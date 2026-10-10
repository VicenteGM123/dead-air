extends RefCounted
## The story the island tells without words: the lion came down from the ridge, broke into the goat pen at the
## forest's edge and dragged its kill back up to the cave.
##   - huge paw prints (L.PAW_TRAIL): from the smashed pen through the forest to the foot of the escarpment, then
##     on the ridge meadow to cave mouth A; each print a dark pressed pad and four toes, draped on the ground (they
##     follow the terrain's triangles), toes towards the cave, the stride of a beast twice a man's size; the grass
##     keeps off them;
##   - what is left of goats: bones, a skull and tufts of white wool where the trail leaves the forest and on the
##     meadow below the cave.
## One merged mesh (lowpoly, no shadows); everything flat sits 2-3 cm over the ground.

const L := preload("res://scripts/world/nemea_layout.gd")
const PRINT_COL := Color("5E4A3A")
const PRINT_RIM := Color("7E6650")
const WOOL := Color("F2EEE4")
const STRIDE := 1.55 # metres between successive prints of the same side
const PRINT_LEN := 0.5

var world: Node3D
var t: RefCounted
var props: RefCounted
var rng := RandomNumberGenerator.new()
var prints := 0
var _mb: MeshBuilder


func build(w: Node3D, terrain: RefCounted, pr: RefCounted) -> void:
	world = w
	t = terrain
	props = pr
	rng.seed = 4401
	_mb = MeshBuilder.new(4401)
	_mb.vary = 0.0
	for leg in L.PAW_TRAIL:
		_trail(leg)
	# The kills: where the trail leaves the forest, and on the meadow below the cave.
	_remains(Vector2(17.5, 13.0), 2)
	_remains(Vector2(-14.0, -79.0), 1)
	_remains(Vector2(6.5, -47.0), 1)
	var mi := MeshInstance3D.new()
	mi.name = "StoryProps"
	mi.mesh = _mb.commit()
	mi.material_override = Materials.lowpoly()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)


## Height of the ground under (x, z) plus a lift.
func _g(x: float, z: float, lift: float = 0.025) -> Vector3:
	return Vector3(x, t.height_at(x, z) + lift, z)


## Prints along a polyline: left and right paws alternate, a little off the line, toes pointing along it.
func _trail(pts: Array) -> void:
	var dist := 0.0
	var next := 0.6
	var side := 1.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var seg := b - a
		var l := seg.length()
		var dir := seg / l
		var perp := Vector2(-dir.y, dir.x)
		while next <= dist + l:
			var u := next - dist
			var p: Vector2 = a + dir * u + perp * side * 0.32 + Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06))
			# Skip prints on water, in the cave, on steep ground (the lion leapt up the escarpment).
			if t.height_at(p.x, p.y) > 0.4 and t.normal_at(p.x, p.y).y > 0.8:
				_print(p, dir.rotated(rng.randf_range(-0.12, 0.12)), side)
			next += STRIDE * 0.5
			side = -side
		dist += l


## One paw print at p (XZ) pointing along `dir`: a three-lobed main pad and four oval toes in an arc in front.
func _print(p: Vector2, dir: Vector2, side: float) -> void:
	var fwd := dir
	var right := Vector2(-dir.y, dir.x)
	var s := PRINT_LEN
	# Main pad: a rounded trapezoid, wider at the back, a notch-free fan of 10 points.
	var pad_c := p - fwd * s * 0.12
	var ring: Array[Vector2] = []
	for i in 10:
		var a := TAU * float(i) / 10.0
		var w := 0.26 * s * (1.0 + 0.18 * cos(a)) # wider towards the back (-fwd)
		var lng := 0.21 * s
		ring.append(pad_c + right * cos(a) * w - fwd * sin(a) * lng)
	_disc(pad_c, ring, PRINT_COL)
	# Toes: four ovals in an arc, the outer ones set back; the inner toe on the paw's side a little forward.
	var toes := [[-0.27, 0.2], [-0.09, 0.3], [0.09, 0.31], [0.27, 0.21]]
	for td in toes:
		var c: Vector2 = p + right * float(td[0]) * s * side + fwd * float(td[1]) * s
		var tr: Array[Vector2] = []
		for i in 8:
			var a := TAU * float(i) / 8.0
			tr.append(c + right * cos(a) * 0.06 * s * 1.3 + fwd * sin(a) * 0.08 * s * 1.3)
		_disc(c, tr, PRINT_COL)
	# A faint rim of pressed earth round the whole print, and no grass over it.
	t.splat_soil(p + fwd * 0.05, s * 0.75, 0.35)
	t.splat_nograss(p + fwd * 0.05, s * 0.62)
	prints += 1


## A flat polygon draped on the ground (centre fan, every vertex at the terrain's height).
func _disc(c: Vector2, ring: Array[Vector2], col: Color) -> void:
	var cv := _g(c.x, c.y, 0.022)
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var va := _g(a.x, a.y, 0.03)
		var vb := _g(b.x, b.y, 0.03)
		# Face up whichever way the ring runs.
		if (vb - cv).cross(va - cv).y > 0.0:
			_mb.tri(cv, vb, va, col)
		else:
			_mb.tri(cv, va, vb, col)


## Bones, a goat's skull and tufts of wool, with a patch of trampled earth.
func _remains(c: Vector2, n: int) -> void:
	for i in n:
		var p := c + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
		_mb.push(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _g(p.x, p.y, 0.0)))
		ModelsNature.add_bones(_mb, rng, i == 0)
		_mb.pop()
	for k in 7:
		var a := rng.randf() * TAU
		var q := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.5, 2.6)
		_mb.ico(_g(q.x, q.y, 0.06), rng.randf_range(0.07, 0.12), WOOL, 0, 0.25, Vector3(1.0, 0.6, 1.0))
	t.splat_soil(c, 2.2, 0.55)
	t.splat_nograss(c, 1.6)
	props.reserve(c, 2.5)
