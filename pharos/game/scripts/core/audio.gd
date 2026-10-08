extends Node
## Audio manager (autoload "Sfx").
##   Sfx.play(name, pos := Vector3.INF, vol_db := 0.0, pitch := 1.0)   one-shot SFX (distance-attenuated if pos)
##   Sfx.music(name)                                                    crossfade to a looping track ("" = silence)
##   Sfx.loop(name, node, vol_db)                                       looping emitter following a node
## Files live in res://assets/audio/{sfx,music,amb}/<name>.ogg; missing files are ignored silently.

const POOL := 22

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _recent := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer = null
var _music_name := ""
var _stinger: AudioStreamPlayer
var _amb := {}
var _night := 0.0
var _fade_jobs: Array = []
## Web: sounds still to be decoded ahead of their first play() (see _web_preload).
var _sample_queue: Array[String] = []
var _sample_wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("Music", Settings.get_v("music"))
	_make_bus("SFX", Settings.get_v("sfx"))
	_make_bus("Amb", Settings.get_v("sfx"))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music_a = _new_player("Music")
	_music_b = _new_player("Music")
	_stinger = _new_player("Music")
	for n in ["sea", "day", "night"]:
		var p := _new_player("Amb")
		p.volume_db = -80.0
		_amb[n] = p
	# A little headroom: the busiest night fights summed above full scale.
	AudioServer.set_bus_volume_db(0, -2.5)
	if OS.has_feature("web"):
		_web_preload()


## On the web every sound is a Web Audio sample, decoded whole on its first play(): a 60 s track blocks the main
## thread for 0.3-1.2 s. Decode what the title and the first day need now (under the loading screen), the short
## effects a few at a time while the title shows, and the night and boss music when dusk falls (hidden by the fade).
func _web_preload() -> void:
	for key in ["music/title", "music/day", "amb/sea", "amb/day", "amb/night"]:
		_register_sample(key)
	for f in ResourceLoader.list_directory("res://assets/audio/sfx"):
		if f.ends_with(".ogg"):
			_sample_queue.append("sfx/" + f.get_basename())
	_sample_queue.append_array(["amb/fire", "music/stinger_dawn", "music/stinger_defeat", "music/stinger_victory"])
	Game.phase_changed.connect(_on_phase_samples)


func _on_phase_samples(p: int) -> void:
	if p == Game.Phase.DUSK:
		_register_sample("music/night")
		if Game.night + 1 >= Data.NIGHTS:
			_register_sample("music/boss")


func _register_sample(key: String) -> void:
	var parts := key.split("/")
	var s := _stream(parts[0], parts[1], parts[0] != "sfx" and not parts[1].begins_with("stinger_"))
	if s and not AudioServer.is_stream_registered_as_sample(s):
		AudioServer.register_stream_as_sample(s)


func _new_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _make_bus(bus_name: String, vol: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	# Not add_bus(): with the web's Sample playback Godot 4.7 then loops the sample buses with Master and nothing is
	# heard. Growing bus_count appends the bus the same way on every platform.
	var i := AudioServer.bus_count
	AudioServer.bus_count = i + 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(vol, 0.0001)))


func set_volume(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func _stream(dir: String, sound: String, looped: bool = false) -> AudioStream:
	var key := dir + "/" + sound
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/audio/%s/%s.ogg" % [dir, sound]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if looped and s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


func _listener() -> Vector3:
	if Game.rig and is_instance_valid(Game.rig):
		return Game.rig.focus
	return Vector3.ZERO


func play(sound: String, pos: Vector3 = Vector3.INF, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var dir := "sfx"
	if sound.begins_with("stinger_"):
		var st := _stream("music", sound)
		if st:
			_stinger.stream = st
			_stinger.volume_db = vol_db
			_stinger.play()
		return
	var s := _stream(dir, sound)
	if s == null:
		return
	var now := Time.get_ticks_msec()
	if _recent.get(sound, -1000) > now - 35:
		return
	_recent[sound] = now
	if pos.is_finite():
		var d := Vector2(pos.x - _listener().x, pos.z - _listener().z).length()
		vol_db -= clampf((d - 10.0) * 0.55, 0.0, 40.0)
		if vol_db < -38.0:
			return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.play()


func music(track: String, fade: float = 1.6) -> void:
	if track == _music_name:
		return
	_music_name = track
	var old := _music_cur
	if old:
		_fade(old, -60.0, fade, true)
	if track == "":
		_music_cur = null
		return
	var s := _stream("music", track, true)
	if s == null:
		_music_cur = null
		return
	var p := _music_a if old != _music_a else _music_b
	p.stream = s
	p.volume_db = -40.0
	p.play()
	_fade(p, -4.0, fade, false)
	_music_cur = p


func _fade(p: AudioStreamPlayer, to_db: float, dur: float, stop_after: bool) -> void:
	for j in _fade_jobs:
		if j[0] == p:
			_fade_jobs.erase(j)
			break
	_fade_jobs.append([p, p.volume_db, to_db, 0.0, maxf(dur, 0.01), stop_after])


## Ambience mix: sea always, cicadas by day, crickets by night.
func set_ambience(night: float, active: bool = true) -> void:
	_night = night
	for n in _amb:
		var p: AudioStreamPlayer = _amb[n]
		if p.stream == null:
			p.stream = _stream("amb", n, true)
			if p.stream:
				p.play()
		var target := -80.0
		if active:
			match n:
				"sea":
					target = -14.0
				"day":
					target = lerpf(-17.0, -60.0, night)
				"night":
					target = lerpf(-60.0, -16.0, night)
		p.volume_db = lerpf(p.volume_db, target, 0.05)


func loop(sound: String, node: Node3D, vol_db: float = 0.0) -> Node:
	var s := _stream("amb", sound, true)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.bus = "Amb"
	p.unit_size = 6.0
	node.add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if not _sample_queue.is_empty():
		_sample_wait -= delta
		if _sample_wait <= 0.0:
			_register_sample(_sample_queue.pop_front())
			_sample_wait = 0.05
	for i in range(_fade_jobs.size() - 1, -1, -1):
		var j: Array = _fade_jobs[i]
		j[3] += delta
		var k: float = clampf(j[3] / j[4], 0.0, 1.0)
		var p: AudioStreamPlayer = j[0]
		p.volume_db = lerpf(j[1], j[2], k)
		if k >= 1.0:
			if j[5]:
				p.stop()
			_fade_jobs.remove_at(i)
	if Game.main and Game.main.tod:
		set_ambience(Game.main.tod.night_amount(), Game.phase != Game.Phase.BOOT)
