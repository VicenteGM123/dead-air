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
	_new_bus("Music")
	_new_bus("SFX")
	_music_bus = AudioServer.get_bus_index("Music")
	_sfx_bus = AudioServer.get_bus_index("SFX")

## Añade un bus al final que envía a Master. Ojo: no usar AudioServer.add_bus(). En la web (Godot 4.7 reproduce
## los sonidos como "samples" del navegador) add_bus() desordena los buses del navegador: Master termina enviando
## al bus nuevo y el nuevo a Master, en círculo, y no se oye nada. Agrandar bus_count funciona igual en todas partes.
func _new_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var i := AudioServer.bus_count
	AudioServer.bus_count = i + 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")

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

# --- WORLD: el mercado tiene su propio ambiente (gente, pájaros, la fuente) y su música. La tienda se pausa.
const SHOP_MUSIC_DB := -4.0
const SHOP_FIRE_DB := -16.0
const MARKET_AMB_DB := -7.0
const MARKET_MUSIC_DB := -7.0
var market_amb: AudioStreamPlayer
var market_music: AudioStreamPlayer
var _place := "shop"
var _place_tween: Tween

## "market": suenan la calle y la música del mercado; "shop": vuelven la música, el fuego y los grillos de la tienda.
func set_place(place: String) -> void:
	if place == _place:
		return
	_place = place
	if market_amb == null:
		market_amb = _make_loop("market_loop", "SFX", -60.0)
		market_music = _make_loop("music_mercado", "Music", -60.0)
	if _place_tween and _place_tween.is_valid():
		_place_tween.kill()
	_place_tween = create_tween().set_parallel(true)
	if place == "market":
		for p in [market_amb, market_music]:
			p.stream_paused = false
			if not p.playing:
				p.play()
		_place_tween.tween_property(market_amb, "volume_db", MARKET_AMB_DB, 0.8)
		_place_tween.tween_property(market_music, "volume_db", MARKET_MUSIC_DB, 1.2)
		_place_tween.tween_property(music, "volume_db", -50.0, 0.6)
		_place_tween.tween_property(fire, "volume_db", -60.0, 0.6)
		_place_tween.chain().tween_callback(func():
			music.stream_paused = true
			fire.stream_paused = true
			night.stream_paused = true)
	else:
		music.stream_paused = false
		fire.stream_paused = false
		night.stream_paused = false
		_place_tween.tween_property(music, "volume_db", SHOP_MUSIC_DB, 1.0)
		_place_tween.tween_property(fire, "volume_db", SHOP_FIRE_DB, 0.8)
		_place_tween.tween_property(market_amb, "volume_db", -60.0, 0.6)
		_place_tween.tween_property(market_music, "volume_db", -60.0, 0.6)
		_place_tween.chain().tween_callback(func():
			market_amb.stream_paused = true
			market_music.stream_paused = true)
# --- end WORLD

# --- MAGIC: sonidos del grimorio (tools/arte/magic_audio.py). Se cargan la primera vez que se usan (magic_load).
const MAGIC_SOUNDS := ["rune_node", "rune_done", "quill", "grimoire"]

func magic_load() -> void:
	for s in MAGIC_SOUNDS:
		if not _streams.has(s) and ResourceLoader.exists("res://assets/audio/%s.ogg" % s):
			_streams[s] = load("res://assets/audio/%s.ogg" % s)

## Como play(), pero con un tono exacto (los puntos de la runa suenan cada vez más agudos).
func play_pitched(name: String, pitch: float, db := 0.0) -> void:
	if not _streams.has(name):
		magic_load()
	if not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.pitch_scale = pitch
			p.volume_db = db
			p.play()
			return
# --- end MAGIC
