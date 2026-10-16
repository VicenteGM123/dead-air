extends AnimatableBody3D
## A hull that floats: a ship whose model has its origin on the WATERLINE amidships (ModelsBuildings.ship) riding the
## sea's swell, with the collision and the mooring lines that go with it.
##
## The sea plane (shaders/water.gdshader) is opaque and drawn over everything that lies under its surface, so a boat
## has to be BUILT to float (keel under the waterline, the deck above the highest wave: the sea can never be seen
## inside it) and it has to stay on the water it floats on. Every physics tick this node puts its origin on the
## swell, Sea.surface_y(), and tilts the hull the way the swell tilts under it (a plane fitted to five samples of the
## swell under the hull), so the draft, the waterline and the freeboard never change, whatever the sea does.
## Sea.surface_y() is the same sum of waves as the shader's vertex displacement (within 4 cm of the 2 m facets the
## shader draws), and the deck has 24 cm to spare over the highest crest, so the margin is never used up.
##
## The body is an AnimatableBody3D (layer 1, the world): the hull is a convex shape up to the deck, so the hero swims
## into it, and what stands on the deck (a hero who jumped aboard) is carried by the moving platform. The mooring
## lines are thin top-level meshes stretched every tick between a fixed point on the pier (a bollard) and a cleat on
## the ship, so they never come off either end however the ship heaves.
##
##   var b := BoatFloat.new(); world.add_child(b)
##   b.setup(hull_mesh, fittings_mesh, Vector3(x, 0, z), yaw, length, beam, depth_fn, hull_points, lines)
##   (depth_fn: Callable(x, z) -> m of water there; hull_points: the convex collision shape in model space;
##    lines: [[pier end in world space, cleat in the ship's frame], ...])

const LINE_RADIUS := 0.025
const LINE_COLOR := Color("D6BE88")

## The model's own axes: bow +Z, origin on the waterline amidships.
var length := 10.0
var beam := 3.0
var yaw := 0.0
var base := Vector3.ZERO
## 0 = the hull stays where it was put (tools), 1 = full swell.
var ride := 1.0

var _depths := PackedFloat32Array([6.0, 6.0, 6.0, 6.0, 6.0])
var _samples: Array[Vector2] = []
var _hull: MeshInstance3D
var _fittings: MeshInstance3D
## One entry per mooring line: {mi: MeshInstance3D, a: Vector3 (the pier end, world), b: Vector3 (the cleat, ship frame)}.
var _lines: Array = []


func setup(hull_mesh: Mesh, fittings_mesh: Mesh, at: Vector3, yaw_rad: float, len: float, bm: float, depth_fn: Callable, hull_points: PackedVector3Array, lines: Array = []) -> void:
	length = len
	beam = bm
	yaw = yaw_rad
	base = at
	collision_layer = 1
	collision_mask = 0
	_hull = MeshInstance3D.new()
	_hull.name = "Hull"
	_hull.mesh = hull_mesh
	_hull.material_override = Materials.lowpoly()
	add_child(_hull)
	if fittings_mesh != null:
		_fittings = MeshInstance3D.new()
		_fittings.name = "Fittings"
		_fittings.mesh = fittings_mesh
		_fittings.material_override = Materials.lowpoly()
		add_child(_fittings)
	if hull_points.size() >= 4:
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull_points
		cs.shape = shape
		add_child(cs)
	# the five places on the water the pose is fitted to (bow, stern, the two sides, the middle), in the rest frame
	var yb := Basis(Vector3.UP, yaw)
	var hl := length * 0.4
	var hb := beam * 0.4
	var local: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, hl), Vector3(0, 0, -hl), Vector3(hb, 0, 0), Vector3(-hb, 0, 0)]
	_samples.clear()
	for i in 5:
		var w: Vector3 = base + yb * local[i]
		_samples.append(Vector2(w.x, w.z))
		_depths[i] = maxf(0.0, float(depth_fn.call(w.x, w.z))) if depth_fn.is_valid() else 6.0
	# the mooring lines: a unit-length limb along +Z, stretched between its two ends every tick
	if not lines.is_empty():
		var lb := MeshBuilder.new(95)
		lb.limb(Vector3.ZERO, Vector3(0, 0, 1), LINE_RADIUS, LINE_RADIUS, 4, LINE_COLOR, false)
		var line_mesh := lb.commit()
		for ln in lines:
			var mi := MeshInstance3D.new()
			mi.name = "Line"
			mi.mesh = line_mesh
			mi.material_override = Materials.lowpoly()
			mi.top_level = true
			add_child(mi)
			_lines.append({"mi": mi, "a": ln[0] as Vector3, "b": ln[1] as Vector3})
	# placed BEFORE the body is synced to the physics frame (a synced body hands its node back to the last transform
	# the physics server knew whenever the node is moved), then driven from _physics_process
	var p0 := pose()
	global_transform = p0
	_stretch_lines(p0)
	sync_to_physics = true


## The pose on the swell right now (the origin on the water, the hull tilted with it).
func pose() -> Transform3D:
	var yb := Basis(Vector3.UP, yaw)
	var sea = Game.sea
	if ride <= 0.0 or sea == null or not is_instance_valid(sea):
		return Transform3D(yb, base)
	var ys := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	for i in 5:
		ys[i] = float(sea.surface_y(_samples[i].x, _samples[i].y, _depths[i]))
	var sl := float(sea.sea_level)
	for i in 5:
		ys[i] = sl + (ys[i] - sl) * ride
	var hl := length * 0.4
	var hb := beam * 0.4
	var y := (ys[0] * 2.0 + ys[1] + ys[2] + ys[3] + ys[4]) / 6.0
	var pitch := -atan2(ys[1] - ys[2], 2.0 * hl) # the bow up when the swell rises towards it
	var roll := atan2(ys[3] - ys[4], 2.0 * hb)
	return Transform3D(yb * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll), Vector3(base.x, y, base.z))


## Each mooring line from its fixed pier end to its cleat on the ship (`ship` is the pose the cleats ride on).
func _stretch_lines(ship: Transform3D) -> void:
	for ln in _lines:
		var a: Vector3 = ln["a"]
		var b: Vector3 = ship * (ln["b"] as Vector3)
		var d := b - a
		var n := d.length()
		if n < 0.01:
			continue
		var mi: MeshInstance3D = ln["mi"]
		mi.global_transform = Transform3D(Basis.looking_at(-d, Vector3.UP) * Basis.from_scale(Vector3(1.0, 1.0, n)), a)


func _physics_process(_delta: float) -> void:
	var p := pose()
	global_transform = p
	_stretch_lines(p)
