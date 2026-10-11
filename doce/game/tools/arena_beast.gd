extends Enemy
## The beast dummy (tools/arena.tscn): a heavy straw bull on a sled, the test bed for the Nemean Lion's rules on
## the hero's side, and the reference implementation of the grapple protocol (docs/COMBAT.md):
##   chain kind &"beast": a yank slides it chain_slide m towards the hero (Enemy base); slamming into a pillar or a
##   rock on the way stuns it (stun_on_slam s, stars over its head);
##   stunned, it is "grapplable": the hero presses interact to wrestle it. While wrestled it opens a squeeze window
##   every BEAT s (hero.grapple_cue) and thrashes every THRASH s after a short warning (hero.grapple_thrash: the
##   hero holds guard to brace). SQUEEZES good presses beat it (it topples over and rights itself after a while);
##   MISSES bad presses or WRESTLE_MAX s and it breaks free.
## Blades do it no harm (like the lion): hit["deflected"] = true. Counters for the bot: slams, wins, losses.

const BEAT := 1.25
const WINDOW := 0.5
const THRASH := 2.4
const THRASH_WARN := 0.45
const THRASH_COST := 24.0
const SQUEEZES := 3
const MISSES := 3
const WRESTLE_MAX := 14.0

var slams := 0
var wins := 0
var losses := 0
var squeezes := 0
var misses := 0
var grappled := false
var _hero: Node = null
var _beat_t := 0.0
var _thrash_t := 0.0
var _warned := false
var _wrestle_t := 0.0
var _down_t := 0.0


func _init() -> void:
	display_name = "Toro de paja"
	max_hp = 999.0
	radius = 0.75
	height = 1.55
	lock_height = 1.1
	chain_weight = &"beast"
	knockback_resist = 0.9
	corpse_time = -1.0
	chain_slide = 3.6
	stun_on_slam = 4.5


func _build() -> void:
	rig = BullRig.new()
	add_child(rig)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.05, 1.35, 2.5)
	cs.shape = b
	cs.position = Vector3(0, 0.75, -0.15)
	add_child(cs)
	add_to_group("grapplable")


func hurt_volumes() -> Array:
	var f := forward()
	var p := global_position + Vector3(0, 0.95, 0)
	return [[p - f * 0.7, p + f * 0.75, 0.55]]


func chain_point() -> Vector3:
	return global_position + Vector3(0, 1.25, 0) + forward() * 0.45


## Blades bounce off the straw bull, as off the lion: the hero recoils.
func _modify_damage(hit: Dictionary, amount: float) -> float:
	if hit.get("kind", &"") == &"blade":
		hit["deflected"] = true
		if Game.fx and hit.has("point"):
			Game.fx.call("dust", hit["point"], 2, 0.2)
		return 0.0
	return amount


func _on_slam(collider: Object, speed: float) -> void:
	slams += 1
	super._on_slam(collider, speed)
	(rig as BullRig).slam()
	print("BEAST slam speed %.1f stunned %.1f s" % [speed, stun_on_slam])


func _on_stunned(_seconds: float) -> void:
	(rig as BullRig).dazed = true


# --- the grapple protocol (the target's side) ---------------------------------------------------------------

func can_grapple(_hero_node: Node) -> bool:
	return alive and stun > 0.0 and not grappled and _down_t <= 0.0


## Where the hero stands to wrestle: his arms locked round its head (RigHeracles.GRAPPLE_HOLD is 0.43 m in front of
## the hero at 1.17 m: the head goes there), in front of the bull or, when that spot is taken (the pillar it was
## stunned against), round the side of its head (45 or 90 degrees either way), always facing the head. Chosen
## once per wrestle with a capsule query (the hero slides onto it with collision, so a spot that is not quite free
## only leaves him short of it, never inside the pillar).
func grapple_anchor(_hero_node: Node) -> Transform3D:
	if not _anchor_set:
		_anchor_set = true
		_anchor_ang = _pick_anchor_angle()
	var f := forward()
	var head := global_position + f * 1.05
	var from_dir := f.rotated(Vector3.UP, deg_to_rad(_anchor_ang))
	var at := head + from_dir * 0.45
	at.y = global_position.y
	var z := from_dir # the hero faces -Z of this basis: towards the head
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), at)


const ANCHOR_ANGLES: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0, 22.5, -22.5, 67.5, -67.5]
var _anchor_set := false
var _anchor_ang := 0.0


## The best free spot round the head (ANCHOR_ANGLES from the front: the front first, then the side away from the
## pillar it slammed into - Enemy.slam_normal - so the hero and the camera have room), else the one with the most room.
func _pick_anchor_angle() -> float:
	var f := forward()
	var head := global_position + f * 1.05
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1 | 8
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 1 | 8
	var best := 0.0
	var best_room := -1.0
	var free_best := 0.0
	var free_score := -INF
	for ang: float in ANCHOR_ANGLES:
		var from_dir := f.rotated(Vector3.UP, deg_to_rad(ang))
		var at := head + from_dir * 0.45
		at.y = global_position.y + 0.95
		q.transform = Transform3D(Basis.IDENTITY, at)
		if space.intersect_shape(q, 1).is_empty():
			# free: prefer the front, and the side away from the slam pillar
			var sc := -absf(ang) / 90.0 * 0.6
			if slam_normal != Vector3.ZERO:
				sc += from_dir.dot(slam_normal)
			if sc > free_score:
				free_score = sc
				free_best = ang
			continue
		# room: how far out from the head the way is clear at waist height
		ray.from = Vector3(head.x, global_position.y + 0.95, head.z)
		ray.to = ray.from + from_dir * 1.5
		var hit := space.intersect_ray(ray)
		var room := 1.5 if hit.is_empty() else ray.from.distance_to(hit["position"])
		if room > best_room + 0.05:
			best_room = room
			best = ang
	if free_score > -INF:
		return free_best
	return best


## As the wrestle starts, a beast stunned against a pillar is hauled DRAG_OFF m off it (along slam_normal): the
## struggle moves out into the open, where it has room and the camera can see the hold (the pillar no longer hides
## the head locked in his arms). The hero holding the head is no obstacle meanwhile (layer 2 off the beast's mask).
const DRAG_OFF := 1.3


func grapple_begin(hero_node: Node) -> void:
	if slam_normal != Vector3.ZERO:
		_kb = slam_normal * sqrt(2.0 * KNOCKBACK_DECAY * DRAG_OFF)
		_rest_ticks = 0
	collision_mask &= ~2
	grappled = true
	_hero = hero_node
	squeezes = 0
	misses = 0
	_beat_t = 0.7
	_thrash_t = THRASH
	_warned = false
	_wrestle_t = 0.0
	stun = maxf(stun, WRESTLE_MAX + 1.0)
	stagger = maxf(stagger, WRESTLE_MAX + 1.0)
	(rig as BullRig).wrestled = true
	print("BEAST grapple begin")


func grapple_input(_hero_node: Node, timing_ok: bool) -> void:
	if not grappled:
		return
	if timing_ok:
		squeezes += 1
		Sfx.play("wrestle_squeeze", global_position + Vector3(0, 1.2, 0), -2.0)
		(rig as BullRig).squeeze()
		if rig.has_method("hit_flash"):
			rig.call("hit_flash", 0.6)
		Game.shake(0.15)
		print("BEAST squeeze %d" % squeezes)
		if squeezes >= SQUEEZES:
			_hero.call("grapple_release", true)
	else:
		misses += 1
		Sfx.play("wrestle_strain", global_position + Vector3(0, 1.2, 0), -6.0, 0.9)
		print("BEAST miss %d" % misses)
		if misses >= MISSES:
			_hero.call("grapple_release", false)


func grapple_progress() -> float:
	return float(squeezes) / float(SQUEEZES)


func grapple_end(_hero_node: Node, won: bool) -> void:
	if not grappled:
		return
	grappled = false
	collision_mask |= 2
	_anchor_set = false # chosen afresh for the next wrestle
	_hero = null
	(rig as BullRig).wrestled = false
	(rig as BullRig).dazed = false
	stagger = 0.0
	if won:
		wins += 1
		stun = 3.0
		stagger = 3.0
		_down_t = 3.0
		(rig as BullRig).topple()
		Game.shake(0.3)
		Sfx.play("body_fall", global_position, -2.0, 0.8)
	else:
		losses += 1
		stun = 0.0
		(rig as BullRig).thrash()
	print("BEAST grapple end won=%s" % str(won))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_down_t = maxf(0.0, _down_t - delta)
	if stun <= 0.0 and not grappled and _down_t <= 0.0:
		(rig as BullRig).dazed = false
	if not grappled or _hero == null or not is_instance_valid(_hero):
		return
	_wrestle_t += delta
	_beat_t -= delta
	_thrash_t -= delta
	if _beat_t <= 0.0:
		_beat_t = BEAT
		_hero.call("grapple_cue", WINDOW)
		Sfx.play("wrestle_strain", global_position + Vector3(0, 1.2, 0), -8.0, 1.1)
	if not _warned and _thrash_t <= THRASH_WARN:
		_warned = true
		telegraph(THRASH_WARN, global_position + Vector3(0, 1.8, 0), "", 1.2)
	if _thrash_t <= 0.0:
		_thrash_t = THRASH
		_warned = false
		(rig as BullRig).thrash()
		Sfx.play("lion_thrash", global_position, -4.0, 1.25)
		_hero.call("grapple_thrash", THRASH_COST)
	if grappled and _wrestle_t >= WRESTLE_MAX:
		_hero.call("grapple_release", false)


## The straw bull: a barrel of straw on four stubby stick legs standing on a sled, a straw head with curved wooden
## horns (no face), a red blanket strapped on its back.
class BullRig extends Rig:
	var dazed := false
	var wrestled := false
	var _tilt := Vector2.ZERO
	var _tilt_v := Vector2.ZERO
	var _roll := 0.0
	var _roll_goal := 0.0
	var _shake := 0.0
	var _down := 0.0

	func _ready() -> void:
		var straw := Color("D9C88E")
		var straw_dark := Color("BFA868")
		var sled := MeshBuilder.new(61)
		sled.vary = 0.03
		for sx in [-1.0, 1.0]:
			sled.block(Vector3(0.42 * sx, 0.0, 0.0), Vector3(0.1, 0.09, 2.2), Pal.WOOD_DARK)
			sled.block(Vector3(0.42 * sx, 0.04, -1.15), Vector3(0.1, 0.08, 0.16), Pal.WOOD_DARK)
		for i in 5:
			sled.block(Vector3(0, 0.09, -0.8 + 0.4 * i), Vector3(0.98, 0.05, 0.2), Pal.WOOD)
		add_part("sled", sled.commit())
		var body := MeshBuilder.new(62)
		body.vary = 0.05
		# legs: four stubby wooden posts from the sled to the barrel
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				body.limb(Vector3(0.3 * sx, 0.0, 0.62 * sz), Vector3(0.28 * sx, 0.5, 0.58 * sz), 0.07, 0.06, 6, Pal.WOOD)
		# the barrel of straw, lying along Z
		body.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.88, 0.0)))
		body.lathe([Vector2(0.22, -0.95), Vector2(0.42, -0.82), Vector2(0.5, -0.4), Vector2(0.52, 0.2), Vector2(0.47, 0.7), Vector2(0.3, 0.92), Vector2(0.12, 0.98)], 10,
			func(_c: Vector3, ring: int, side: int) -> Color: return straw if (ring + side) % 3 != 0 else straw_dark)
		for zz in [-0.5, 0.15, 0.6]:
			body.cyl(Vector3(0, zz, 0), 0.06, 0.53, 0.53, 10, Pal.WOOD_LIGHT) # rope bands
		body.pop()
		# the red blanket over the back with a dark border
		body.block(Vector3(0, 1.27, 0.05), Vector3(1.12, 0.04, 0.9), Pal.CREST, Pal.CREST)
		body.block(Vector3(0, 1.255, 0.05), Vector3(1.16, 0.03, 0.96), Color("4E2C1C"))
		# the tail: a twist of straw
		body.limb(Vector3(0, 0.95, 0.95), Vector3(0, 0.55, 1.15), 0.05, 0.03, 5, straw_dark)
		add_part("body", body.commit(), "sled", Vector3(0, 0.12, 0))
		var head := MeshBuilder.new(63)
		head.vary = 0.04
		head.sphere(Vector3(0, 0, 0), 0.3, straw, 8, 6, Vector3(0.9, 0.85, 1.15))
		head.sphere(Vector3(0, -0.06, -0.26), 0.17, straw_dark, 7, 5, Vector3(1.0, 0.8, 0.9))
		head.cyl(Vector3(0, -0.05, 0.15), 0.06, 0.3, 0.3, 8, Pal.WOOD_LIGHT) # a rope collar
		# horns: wooden, curving out and up
		for sx in [-1.0, 1.0]:
			var a := Vector3(0.2 * sx, 0.12, -0.02)
			var b := Vector3(0.48 * sx, 0.2, -0.1)
			var c := Vector3(0.58 * sx, 0.42, -0.22)
			head.limb(a, b, 0.07, 0.05, 6, Pal.WOOD_LIGHT)
			head.limb(b, c, 0.05, 0.015, 6, Pal.WOOD_LIGHT)
		add_part("head", head.commit(), "body", Vector3(0, 1.05, -1.05))

	func slam() -> void:
		_tilt_v += Vector2(-6.0, 0.0)
		_shake = 0.6

	func squeeze() -> void:
		_tilt_v += Vector2(0.0, 3.0)
		_shake = 0.25

	func thrash() -> void:
		_shake = 0.8
		_tilt_v += Vector2(randf_range(-4.0, 4.0), 5.0 * signf(randf() - 0.5))

	func topple() -> void:
		_down = 3.0

	func _animate(delta: float) -> void:
		var acc := -_tilt * 40.0 - _tilt_v * 4.0
		_tilt_v += acc * delta
		_tilt += _tilt_v * delta
		_tilt = _tilt.limit_length(0.45)
		_shake = maxf(0.0, _shake - delta * 1.5)
		_down = maxf(0.0, _down - delta)
		_roll_goal = 1.35 if _down > 0.4 else 0.0
		_roll = lerpf(_roll, _roll_goal, 1.0 - exp(-delta * (7.0 if _roll_goal > _roll else 2.5)))
		var wob := 0.0
		if dazed:
			wob = sin(t * 3.1) * 0.08
		if wrestled:
			wob += sin(t * 9.0) * 0.05
		var sh := sin(t * 47.0) * _shake * 0.12
		(parts["body"] as Node3D).rotation = Vector3(_tilt.x, sh, _tilt.y + wob)
		(parts["head"] as Node3D).rotation = Vector3(_tilt.x * 0.5 + (0.25 if dazed else 0.0), sin(t * 2.0) * 0.1 * (1.0 if dazed else 0.2) + sh * 2.0, wob)
		# toppled (beaten in the wrestle): the whole bull rolls onto its side, then rights itself
		(parts["sled"] as Node3D).rotation = Vector3(0.0, 0.0, _roll)
		(parts["sled"] as Node3D).position = Vector3(0.0, sin(_roll) * 0.55, 0.0)
