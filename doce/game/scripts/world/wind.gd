class_name Wind
extends Node
## DOCE's one wind (shaders/wind.gdshaderinc): sets the wind's global shader uniforms every frame so the meadow, the
## flowers, the wheat and the foliage of every tree and shrub move together, and feeds the "pushers" that part the
## grass and the wheat (the hero and, later, the beasts).
##
## Global shader uniforms (project.godot [shader_globals]):
##   g_wind       float  overall strength (TimeOfDay's mood sets it: day 1.0, golden 1.2, dusk 1.3...); multiplied
##                       here by `strength`
##   g_wind_dir   vec2   unit XZ direction the wind blows towards (default east-south-east, with the clouds)
##   g_wind_gust  vec4   (gust strength, gust wavelength m, gust speed m/s, tip sway amount)
##   g_push_a     mat4   pusher heads: column i = (x, y, z, radius); radius 0 = slot unused
##   g_push_b     mat4   pusher tails: column i = (x, y, z, strength at the tail)
##
## Pushers: slot 0 is Game.hero; slots 1-3 the nearest nodes (to the camera) in the group "grass_pushers" (beasts:
## add_to_group("grass_pushers"); optional meta "push_radius", default 0.9 m). Each pusher's tail is its position
## a moment ago (an exponential lag of `trail_time` seconds), so the stalks it went through spring back along a
## soft trail and settle when it stops.
##
##   var wind := Wind.new(); add_child(wind)     # once, anywhere in the tree (World does it)

const GROUP := &"grass_pushers"

## Direction the wind blows towards (XZ, normalised on use).
@export var direction := Vector2(0.94, 0.34)
## Extra multiplier on top of the mood's g_wind.
@export var strength := 1.0
@export var gust_strength := 1.0
@export var gust_wavelength := 14.0
@export var gust_speed := 3.8
@export var flutter := 1.0
@export var hero_radius := 0.95
@export var trail_time := 1.0

var _tails := {} # node -> Vector3 (lagged position)
var _wobble := 0.0


func _ready() -> void:
	_apply_static()


func _apply_static() -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("g_wind_dir", direction.normalized())
	rs.global_shader_parameter_set("g_wind_gust", Vector4(gust_strength, gust_wavelength, gust_speed, flutter))


func _process(delta: float) -> void:
	_wobble += delta
	# The direction breathes a little (a few degrees over half a minute), never jumps.
	var d := direction.normalized().rotated(sin(_wobble * 0.21) * 0.06 + sin(_wobble * 0.053) * 0.05)
	var rs := RenderingServer
	rs.global_shader_parameter_set("g_wind_dir", d)
	rs.global_shader_parameter_set("g_wind_gust", Vector4(gust_strength * strength, gust_wavelength, gust_speed, flutter))
	_update_pushers(delta)


func _update_pushers(delta: float) -> void:
	var hero: Node3D = null
	var h: Variant = Game.get("hero")
	if h != null and is_instance_valid(h) and (h as Node3D).is_inside_tree():
		hero = h as Node3D
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cp := Vector3.ZERO
	if cam != null:
		cp = cam.global_position
	elif hero != null:
		cp = hero.global_position
	# FINAL: slots 1-3 go to the nearest (to the camera) of the group's nodes and the live beasts (group "enemy",
	# radius from their body: the wolves and boars part the grass and the wheat too), within BEAST_RANGE of the camera;
	# picked without sorting or temporary arrays
	for i in 4:
		_pick[i] = null
		_pick_d[i] = INF
	_pick[0] = hero
	_consider(get_tree().get_nodes_in_group(GROUP), hero, cp, false)
	_consider(get_tree().get_nodes_in_group(&"enemy"), hero, cp, true)
	var k := 1.0 - exp(-delta / maxf(trail_time, 0.01))
	for i in 4:
		var n: Node3D = _pick[i]
		if n == null:
			_heads[i] = Vector4.ZERO
			_tails4[i] = Vector4.ZERO
			continue
		var p := _visual_pos(n)
		var r := 0.0
		if i == 0:
			# the hero: his own meta while his free hand brushes the wheat (Hero._feed_brush), else hero_radius
			r = float(n.get_meta(&"push_radius", hero_radius))
		elif n.has_meta(&"push_radius"):
			r = float(n.get_meta(&"push_radius"))
		elif "radius" in n:
			r = clampf(float(n.get("radius")) * 2.2, 0.8, 1.4)
		else:
			r = 0.9
		var tail: Vector3 = _tails.get(n, p)
		# a teleport (respawn, cutscene) starts a fresh trail instead of dragging one across the island
		if tail.distance_squared_to(p) > 36.0:
			tail = p
		tail = tail.lerp(p, k)
		_tails[n] = tail
		_heads[i] = Vector4(p.x, p.y, p.z, r)
		_tails4[i] = Vector4(tail.x, tail.y, tail.z, 0.6)
	# forget the trails of nodes no longer picked or freed (a beast's body dissolves): at most a few entries, no
	# allocation in the common case
	if _tails.size() > 4 or _tails_check <= 0:
		_tails_check = 30
		for n in _tails.keys():
			if not is_instance_valid(n) or not _pick.has(n):
				_tails.erase(n)
	_tails_check -= 1
	var rs := RenderingServer
	rs.global_shader_parameter_set("g_push_a", Projection(_heads[0], _heads[1], _heads[2], _heads[3]))
	rs.global_shader_parameter_set("g_push_b", Projection(_tails4[0], _tails4[1], _tails4[2], _tails4[3]))


const BEAST_RANGE := 40.0
var _tails_check := 0
var _pick: Array[Node3D] = [null, null, null, null]
var _pick_d := PackedFloat32Array([INF, INF, INF, INF])
var _heads: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _tails4: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]


## Where a pusher is DRAWN this frame: the hero's and the beasts' bodies move in 60 Hz physics ticks and their rigs are
## drawn interpolated between them; a pusher that followed the body would hop from tick to tick (and from 0 to 2 ticks
## in a frame whenever the frame rate and the physics rate beat against each other) while the model glides, and the
## stalks round it would jitter. Hero.visual_position() is the interpolated position; a beast's rig (top level) sits there.
func _visual_pos(n: Node3D) -> Vector3:
	if n.has_method("visual_position"):
		return n.call("visual_position")
	var rg: Variant = n.get("rig")
	if rg is Node3D and (rg as Node3D).is_inside_tree() and (rg as Node3D).top_level:
		return (rg as Node3D).global_position
	return n.global_position


## Keeps the nodes of `list` nearest to the camera in slots 1-3 (insertion into a 3-long sorted list).
func _consider(list: Array, hero: Node3D, cp: Vector3, beasts: bool) -> void:
	for o in list:
		var n := o as Node3D
		if n == null or n == hero or not n.is_inside_tree():
			continue
		if beasts and not (n.has_method("is_alive") and bool(n.call("is_alive"))):
			continue
		var d := _visual_pos(n).distance_squared_to(cp)
		if beasts and d > BEAST_RANGE * BEAST_RANGE:
			continue
		if d >= _pick_d[3]:
			continue
		var j := 3
		while j > 1 and d < _pick_d[j - 1]:
			_pick[j] = _pick[j - 1]
			_pick_d[j] = _pick_d[j - 1]
			j -= 1
		_pick[j] = n
		_pick_d[j] = d
