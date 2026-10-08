class_name AmbientSky
extends Node3D
## Seagulls gliding in wide circles 10-16 m above the coast, banking into the turn, with an occasional burst of
## wing beats. The circles drift slowly along the coastline. At dusk the gulls head out to sea and vanish; at
## dawn they come back.

class Gull:
	var rig: ModelsAnimals.GullRig
	var ang := 0.0 # position on its circle
	var coast_deg := 0.0 # where on the coast the circle is centred
	var out := 4.0 # circle centre offset seaward of the coastline (m)
	var radius := 9.0
	var dir := 1.0
	var speed := 5.0
	var alt := 12.0
	var lift := 0.0 # extra height gained while flapping
	var phase := 0.0
	var drift := 0.0 # deg/s along the coast
	var flap_timer := 3.0
	var yaw := 0.0
	var yaw_rate := 0.0
	var prev := Vector3.INF

var amb: Ambient
var gulls: Array[Gull] = []
var away := 1.0
var t := 0.0
var cry_timer := 8.0
var rng := RandomNumberGenerator.new()


func setup(ambient: Ambient, count: int = 5) -> void:
	amb = ambient
	rng.seed = ambient.rng.randi()
	away = smoothstep(0.3, 0.7, amb.night)
	var base := rng.randf() * 360.0
	for i in count:
		var g := Gull.new()
		g.rig = ModelsAnimals.GullRig.new(i)
		g.rig.scale = Vector3.ONE * rng.randf_range(0.95, 1.1)
		add_child(g.rig)
		# Pairs share a circle now and then; the rest spread around the island.
		if i % 3 == 1:
			var prev_g := gulls[i - 1]
			g.coast_deg = prev_g.coast_deg + rng.randf_range(-8.0, 8.0)
			g.radius = prev_g.radius * rng.randf_range(0.8, 1.2)
			g.dir = prev_g.dir
			g.ang = prev_g.ang + rng.randf_range(1.6, 3.2)
			g.alt = clampf(prev_g.alt + rng.randf_range(-1.5, 1.5), 10.8, 14.0)
		else:
			g.coast_deg = base + 360.0 * float(i) / float(count) + rng.randf_range(-20.0, 20.0)
			g.radius = rng.randf_range(6.5, 12.0)
			g.dir = 1.0 if rng.randf() < 0.5 else -1.0
			g.ang = rng.randf() * TAU
			g.alt = rng.randf_range(11.0, 13.8)
		g.out = rng.randf_range(-2.0, 6.0)
		g.speed = rng.randf_range(4.3, 5.8)
		g.phase = rng.randf() * TAU
		g.drift = rng.randf_range(-0.9, 0.9)
		g.flap_timer = rng.randf_range(0.5, 6.0)
		gulls.append(g)
	_update(0.0)


func _process(delta: float) -> void:
	_update(minf(delta, 0.1))


func _update(dt: float) -> void:
	t += dt
	var want := smoothstep(0.3, 0.7, amb.night)
	away = move_toward(away, want, dt * 0.07)
	var gone := away > 0.985
	for g in gulls:
		g.rig.visible = not gone
		g.rig.set_process(not gone)
	if gone:
		return
	cry_timer -= dt
	if cry_timer <= 0.0:
		cry_timer = rng.randf_range(7.0, 16.0)
		if Ambient.EXTRA_SFX and away < 0.3:
			var cg := gulls[rng.randi() % gulls.size()]
			Sfx.play("gull", cg.rig.global_position, -10.0, rng.randf_range(0.9, 1.15))
	for g in gulls:
		g.ang += g.dir * g.speed / g.radius * dt
		g.coast_deg += g.drift * dt
		g.flap_timer -= dt
		if g.flap_timer <= 0.0:
			g.flap_timer = rng.randf_range(4.0, 10.0)
			g.rig.flap(rng.randi_range(3, 6))
		g.lift = clampf(g.lift + (0.9 if g.rig.flap_k > 0.5 else -0.18) * dt, -0.3, 1.5)
		var ca := deg_to_rad(g.coast_deg)
		var outward := Vector3(sin(ca), 0, cos(ca))
		var c := outward * (amb.island.coast_at(g.coast_deg) + g.out)
		var p := c + Vector3(cos(g.ang), 0, sin(g.ang)) * g.radius
		p.y = g.alt + g.lift + 0.7 * sin(t * 0.33 + g.phase)
		# Leaving for the night: out to sea and up.
		var k := away * away
		p += outward * (k * 120.0) + Vector3(0, away * 12.0, 0)
		if g.prev.is_finite() and dt > 0.0:
			var v := p - g.prev
			if v.length_squared() > 1e-8:
				var ny := atan2(v.x, v.z)
				var dy := angle_difference(g.yaw, ny)
				g.yaw_rate = lerpf(g.yaw_rate, dy / dt, 1.0 - exp(-dt * 3.0))
				g.yaw = g.yaw + dy * (1.0 - exp(-dt * 6.0))
			var climb := v.y / dt
			var roll := clampf(-atan(g.speed * g.yaw_rate / 9.8) * 1.1, -0.6, 0.6)
			g.rig.rotation = Vector3(clampf(-climb * 0.12, -0.3, 0.3), g.yaw, roll)
		else:
			g.yaw = atan2(-sin(g.ang) * g.dir, cos(g.ang) * g.dir)
			g.rig.rotation = Vector3(0, g.yaw, 0)
		g.prev = p
		g.rig.position = p
