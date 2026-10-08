class_name WaveDirector
extends Node
## Spawns each night's creatures from the sea, following Data.NIGHT_WAVES, and reports when the night is won.

signal night_cleared
signal boss_spawned(boss: Node3D)

var night := 0
var active := false
var t := 0.0
var _groups: Array = []
var _streams: Array = []
var total := 0
var spawned := 0
var units_root: Node3D
var boss: Node3D = null


func start_night(n: int) -> void:
	night = n
	t = 0.0
	active = true
	spawned = 0
	total = 0
	_groups.clear()
	_streams.clear()
	boss = null
	var waves: Array = Data.NIGHT_WAVES[clampi(n - 1, 0, Data.NIGHT_WAVES.size() - 1)]
	for w in waves:
		var comp: Dictionary = w[2]
		for type in comp:
			_groups.append([float(w[0]), int(w[1]), String(type), int(comp[type])])
			total += int(comp[type])
	_groups.sort_custom(func(a, b): return a[0] < b[0])


func stop() -> void:
	active = false
	_groups.clear()
	_streams.clear()


func remaining() -> int:
	return (total - spawned) + Game.enemy_count()


func _physics_process(delta: float) -> void:
	if not active or Game.paused:
		return
	t += delta
	while not _groups.is_empty() and _groups[0][0] <= t:
		var g: Array = _groups.pop_front()
		var interval := 0.55
		if g[2] == "cyclops" or g[2] == "hydra":
			interval = 2.0
		elif g[2] == "ker":
			interval = 0.35
		_streams.append({"lane": g[1], "type": g[2], "left": g[3], "interval": interval, "timer": 0.0})
	for i in range(_streams.size() - 1, -1, -1):
		var st: Dictionary = _streams[i]
		st["timer"] -= delta
		if st["timer"] <= 0.0:
			st["timer"] = st["interval"]
			spawn(st["type"], st["lane"])
			st["left"] -= 1
			if st["left"] <= 0:
				_streams.remove_at(i)
	if _groups.is_empty() and _streams.is_empty() and Game.enemy_count() == 0 and t > 3.0:
		active = false
		night_cleared.emit()


func spawn(type: String, lane: int) -> Node3D:
	var e: Enemy
	if type == "hydra":
		e = Hydra.new()
	else:
		e = Enemy.new()
	var lat := randf_range(-1.4, 1.4)
	if type == "cyclops" or type == "hydra":
		lat = 0.0
	e.setup(type, lane, lat)
	units_root.add_child(e)
	spawned += 1
	if type == "hydra":
		boss = e
		boss_spawned.emit(e)
	return e
