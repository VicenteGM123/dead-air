extends Node
## Música, ambiente y efectos de sonido.

const SOUNDS := ["brew", "bubble_0", "bubble_1", "bubble_2", "click", "coin", "door", "doorbell", "hover",
	"levelup", "page", "plop", "purr", "sad", "sparkle", "step_0", "step_1", "step_2", "stir"]

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var fire: AudioStreamPlayer
var night: AudioStreamPlayer
var _music_bus := 0
var _sfx_bus := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for s in SOUNDS:
		_streams[s] = load("res://assets/audio/%s.ogg" % s)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	music = _make_loop("music_tienda", "Music", -4.0)
	fire = _make_loop("fire_loop", "SFX", -16.0)
	night = _make_loop("crickets_loop", "SFX", -60.0)
	apply_volumes()

func _setup_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, "SFX")
		AudioServer.set_bus_send(j, "Master")
	_music_bus = AudioServer.get_bus_index("Music")
	_sfx_bus = AudioServer.get_bus_index("SFX")

func _make_loop(name: String, bus: String, db: float) -> AudioStreamPlayer:
	var st = load("res://assets/audio/%s.ogg" % name)
	if st is AudioStreamOggVorbis:
		st.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = db
	add_child(p)
	return p

func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(Game.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(Game.sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(_music_bus, Game.music_volume <= 0.001)
	AudioServer.set_bus_mute(_sfx_bus, Game.sfx_volume <= 0.001)

func start_ambience() -> void:
	if not music.playing:
		music.play()
	if not fire.playing:
		fire.play()
	if not night.playing:
		night.play()

func set_night_amount(t: float) -> void:
	# t: 0 = día, 1 = noche cerrada
	night.volume_db = lerpf(-60.0, -20.0, clampf(t, 0.0, 1.0))

func play(name: String, pitch_var := 0.06, db := 0.0) -> void:
	if not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.volume_db = db
			p.play()
			return

func bubble() -> void:
	play("bubble_%d" % (randi() % 3), 0.15, -6.0)

func step() -> void:
	play("step_%d" % (randi() % 3), 0.1, -10.0)
