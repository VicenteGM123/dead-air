extends "res://scripts/main.gd"
## Does a hero standing still keep his body (and so the wind's pusher) perfectly still? Stands him on level ground and on
## slopes of the island for 6 s each and prints how far his body moves per physics tick and how far the pusher's tail
## (the lagged position the grass springs back along) still is from its head. Headless is fine:
##   godot --headless --path . res://tools/wind_stand_probe.tscn --fixed-fps 60 --quit-after 2600 -- play=1 enemies=0 | grep STAND
var _spots: Array = []
var _i := -1
var _t := 0
var _prev := Vector3.ZERO
var _dmax := 0.0
var _dsum := 0.0
var _n := 0
var _seam := 0.0


func _wants_title() -> bool:
	return false


func _ready() -> void:
	Game.args["noui"] = "1"
	Game.args["enemies"] = "0"
	Game.args["lion"] = "0"
	Game.args["fauna"] = "0"
	super._ready()
	# a level spot and the steepest walkable slopes of the meadow round the village
	var best := {}
	for x in range(-60, 80, 3):
		for z in range(-40, 100, 3):
			var w: Variant = world
			if not bool(w.call("is_walkable", float(x), float(z))):
				continue
			var s: float = w.call("slope_at", float(x), float(z))
			if absf(float(w.call("height_at", float(x), float(z)))) < 1.0:
				continue
			for lim in [0.02, 0.06, 0.12]:
				if s <= lim and (not best.has(lim) or s > best[lim][0]):
					best[lim] = [s, Vector2(x, z)]
	for lim in [0.02, 0.06, 0.12]:
		if best.has(lim):
			_spots.append(best[lim])
	_next_spot.call_deferred()


func _next_spot() -> void:
	_i += 1
	if _i >= _spots.size():
		get_tree().quit()
		return
	var xz: Vector2 = _spots[_i][1]
	hero.teleport(Transform3D(Basis(Vector3.UP, 0.0), world.ground(Vector3(xz.x, 0.0, xz.y))))
	_t = 0
	_dmax = 0.0
	_dsum = 0.0
	_n = 0
	_seam = 0.0
	_prev = hero.global_position


func _physics_process(_delta: float) -> void:
	if _i < 0 or _i >= _spots.size():
		return
	_t += 1
	var p := hero.global_position
	if _t > 60:   # (let him settle for a second)
		var d := p.distance_to(_prev)
		_dmax = maxf(_dmax, d)
		_dsum += d
		_n += 1
	_prev = p
	if _t == 360:
		var wd: Variant = world.get("wind")
		var tails: Array = wd.get("_tails4")
		var heads: Array = wd.get("_heads")
		var ab := Vector2(tails[0].x - heads[0].x, tails[0].z - heads[0].z).length()
		print("STAND spot %d at (%.0f, %.0f) slope %.3f: body moves per physics tick: mean %.2f um, max %.2f um | pusher tail - head after 6 s: %.3f mm" % [_i, _spots[_i][1].x, _spots[_i][1].y, _spots[_i][0], _dsum / maxf(_n, 1) * 1.0e6, _dmax * 1.0e6, ab * 1000.0])
		_next_spot.call_deferred()
