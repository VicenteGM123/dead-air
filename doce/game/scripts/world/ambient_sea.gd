class_name AmbientSea
extends Node3D
## Dolphins: every so often in daytime a pod of 2-3 surfaces offshore (preferably where the camera can see it),
## each dolphin leaping in 2-3 arcs along the coast with a splash in and out, then they dive and are gone.

const LEAP_TIME := 1.3 # seconds in one arc (from below the surface back below it)
const GAP_TIME := 0.7 # seconds underwater between arcs
const LEAP_LEN := 4.8 # metres covered by one arc
const GAP_LEN := 2.4
const BASE_Y := -0.9 # body centre at the start / end of an arc
const PEAK := 2.25 # rise above BASE_Y at the top of the arc

class Leaper:
	var rig: ModelsAnimals.DolphinRig
	var delay := 0.0
	var jumps := 3
	var lateral := 0.0
	var up_done := -1 # index of the last arc that splashed on the way up
	var down_done := -1
	var roll := 0.0

var amb: Ambient
var rng := RandomNumberGenerator.new()
var pod: Array[Leaper] = []
var active := false
var timer := 0.0
var t := 0.0
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var side := Vector3.RIGHT
var count := 0


func setup(ambient: Ambient) -> void:
	amb = ambient
	rng.seed = ambient.rng.randi()
	for i in 3:
		var l := Leaper.new()
		l.rig = ModelsAnimals.DolphinRig.new(i)
		l.rig.visible = false
		l.rig.set_process(false)
		add_child(l.rig)
		pod.append(l)
	timer = rng.randf_range(5.0, 10.0)


## Starts a pod right away (if it is daytime and a spot is found). Handy for tests and cut-scenes.
func show_pod() -> bool:
	return _start()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	if not active:
		timer -= dt
		if timer <= 0.0:
			if amb.night > 0.25 or not _start():
				timer = rng.randf_range(6.0, 12.0)
		return
	t += dt
	var cycle := LEAP_TIME + GAP_TIME
	var running := 0
	for i in count:
		var l := pod[i]
		var lt := t - l.delay
		var total := cycle * float(l.jumps)
		if lt < 0.0 or lt >= total:
			l.rig.visible = false
			l.rig.set_process(false)
			if lt < total:
				running += 1
			continue
		running += 1
		var k := int(lt / cycle)
		var ct := lt - float(k) * cycle
		var s := float(k) * (LEAP_LEN + GAP_LEN)
		if ct >= LEAP_TIME:
			l.rig.visible = false
			l.rig.set_process(false)
			continue
		var u := ct / LEAP_TIME
		s += u * LEAP_LEN
		var y := BASE_Y + PEAK * sin(PI * u)
		var p := origin + dir * s + side * l.lateral
		p.y = y
		var slope := PEAK * PI * cos(PI * u) / LEAP_LEN
		l.rig.visible = true
		l.rig.set_process(true)
		l.rig.play("leap")
		l.rig.position = p
		l.rig.rotation = Vector3(-atan(slope), atan2(dir.x, dir.z), l.roll * sin(PI * u))
		# Splashes where the arc crosses the surface.
		var cross := asin(clampf(-BASE_Y / PEAK, 0.0, 1.0)) / PI
		if u >= cross and l.up_done < k:
			l.up_done = k
			_splash(p, 0.8)
		if u >= 1.0 - cross and l.down_done < k:
			l.down_done = k
			_splash(p + dir * 0.4, 1.0)
	if running == 0:
		active = false
		timer = rng.randf_range(18.0, 45.0)
		for l in pod:
			l.rig.visible = false
			l.rig.set_process(false)


func _splash(p: Vector3, strength: float) -> void:
	amb.fx.splash(Vector3(p.x, 0.0, p.z), strength)
	Sfx.play("splash", Vector3(p.x, 0.0, p.z), -2.0 if strength > 0.9 else -5.0, rng.randf_range(0.9, 1.1))


func _start() -> bool:
	var h := amb.hero_pos()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var base_deg := Ambient.angle_of(h.x, h.z) if h.is_finite() else rng.randf() * 360.0
	var best_score := -1.0
	var best_origin := Vector3.ZERO
	var best_dir := Vector3.FORWARD
	var jumps := rng.randi_range(2, 3)
	var run := float(jumps) * (LEAP_LEN + GAP_LEN)
	for tries in 24:
		var deg := base_deg + rng.randf_range(-70.0, 70.0)
		var off := rng.randf_range(7.0, 20.0)
		var ar := deg_to_rad(deg)
		var outward := Vector3(sin(ar), 0, cos(ar))
		var start := outward * (amb.island.coast_at(deg) + off)
		var tangent := Vector3(outward.z, 0, -outward.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var d := (tangent + outward * rng.randf_range(-0.2, 0.25)).normalized()
		var deep := true
		for f in [0.0, 0.5, 1.0]:
			var q: Vector3 = start + d * run * float(f)
			for lat in [-2.0, 2.0]:
				var w := q + d.cross(Vector3.UP) * float(lat)
				if amb.island.height_at(w.x, w.z) > -1.5:
					deep = false
		if not deep:
			continue
		var score := 1.0
		if cam != null:
			var mid := start + d * run * 0.5
			for f in [0.0, 0.5, 1.0]:
				if cam.is_position_in_frustum(start + d * run * float(f) + Vector3(0, 1.0, 0)):
					score += 1.0
			score -= cam.global_position.distance_to(mid) * 0.01
		if score > best_score:
			best_score = score
			best_origin = start
			best_dir = d
	if best_score < 0.0:
		return false
	origin = best_origin
	dir = best_dir
	side = dir.cross(Vector3.UP).normalized()
	count = rng.randi_range(2, 3)
	var lats := [0.0, -1.5, 1.6]
	for i in count:
		var l := pod[i]
		l.delay = float(i) * rng.randf_range(0.22, 0.38)
		l.jumps = jumps if i == 0 else maxi(2, jumps - rng.randi_range(0, 1))
		l.lateral = lats[i] + rng.randf_range(-0.3, 0.3)
		l.up_done = -1
		l.down_done = -1
		l.roll = rng.randf_range(-0.35, 0.35)
	t = 0.0
	active = true
	return true
