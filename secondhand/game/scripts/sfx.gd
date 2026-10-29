extends Node
## Música, ambiente y efectos de sonido.
## --- SS SEED: copiado de Midnight Cauldron (scripts/sfx.gd), con lo que importa para la web:
##   - los buses Music y SFX se crean agrandando AudioServer.bus_count (NUNCA AudioServer.add_bus(): en la web,
##     con los sonidos como "samples" del navegador, add_bus() desordena los buses y no se oye nada);
##   - los bucles son AudioStreamOggVorbis con loop = true (tools/export_web.sh arregla además el bucle web);
##   - un grupo fijo de reproductores para los efectos (sin crear nodos por sonido).
## Lo nuevo: los nombres son los del contrato de audio de Secondhand Stars y TODO es opcional: si un archivo todavía
## no existe (la línea AUDIO trabaja en paralelo), no suena y no hay error en la consola. Se busca primero en
## res://assets/audio/<nombre>.ogg y luego en res://audio/<nombre>.ogg.
##   música:    music_title, music_shop, music_market      -> Sfx.music("title" | "shop" | "market" | "")
##   ambiente:  amb_wind, amb_port                         -> Sfx.ambience("wind" | "port" | "")
##   efectos:   sfx_bell, sfx_whistle, sfx_blip1..3, sfx_ratchet, sfx_sizzle, sfx_coins, sfx_pod, sfx_good, sfx_bad,
##              sfx_takeoff, sfx_tea                       -> Sfx.play("sfx_bell") o un alias de ALIASES
## Volúmenes: Game.music_volume y Game.sfx_volume (0..1) con apply_volumes().

const SFX := ["sfx_bell", "sfx_whistle", "sfx_blip1", "sfx_blip2", "sfx_blip3", "sfx_ratchet", "sfx_sizzle",
	"sfx_coins", "sfx_pod", "sfx_good", "sfx_bad", "sfx_takeoff", "sfx_tea"]
## Nombres cortos (y los que usa el código copiado de Midnight Cauldron: click, hover, coin, step...).
const ALIASES := {
	"click": "sfx_blip1", "hover": "sfx_blip3", "blip": "sfx_blip2", "bell": "sfx_bell", "whistle": "sfx_whistle",
	"ratchet": "sfx_ratchet", "sizzle": "sfx_sizzle", "coin": "sfx_coins", "coins": "sfx_coins", "pod": "sfx_pod",
	"good": "sfx_good", "bad": "sfx_bad", "takeoff": "sfx_takeoff", "tea": "sfx_tea", "door": "sfx_bell",
}
const MUSIC_DB := -6.0
const AMB_DB := -12.0
const FADE := 1.2

var _streams := {}
var _missing := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_name := ""
var _amb: AudioStreamPlayer
var _amb_name := ""
var _music_tw: Tween
var _amb_tw: Tween
var _music_bus := 0
var _sfx_bus := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "SFX"
	add_child(_amb)
	apply_volumes()
	# --- BOOT: la precarga de los bucles ya no corre sola aquí: era un solo bloque de ~0.6 s dentro del primer cuadro
	# (con la página congelada). main.gd llama a prewarm_one() de a un bucle por cuadro: los del título mientras carga,
	# los demás después, con el título ya en pantalla (ver prewarm() al final).

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

## El archivo de un sonido (o "" si todavía no existe).
func path_of(name: String) -> String:
	for p in ["res://assets/audio/%s.ogg" % name, "res://audio/%s.ogg" % name]:
		if ResourceLoader.exists(p):
			return p
	return ""

func has_sound(name: String) -> bool:
	return _stream(ALIASES.get(name, name)) != null

func _stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	if _missing.has(name):
		return null
	var p := path_of(name)
	if p == "":
		_missing[name] = true
		return null
	var st: AudioStream = load(p)
	_streams[name] = st
	return st

func _loop_stream(name: String) -> AudioStream:
	var st := _stream(name)
	if st is AudioStreamOggVorbis:
		st.loop = true
	return st

func apply_volumes() -> void:
	var mv: float = Game.music_volume
	var sv: float = Game.sfx_volume
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(mv, 0.0001)))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(sv, 0.0001)))
	AudioServer.set_bus_mute(_music_bus, mv <= 0.001)
	AudioServer.set_bus_mute(_sfx_bus, sv <= 0.001)

## Un efecto. name: "sfx_bell" o un alias ("click", "coin"...). Sin archivo: nada.
func play(name: String, pitch_var := 0.06, db := 0.0) -> void:
	play_pitched(name, 1.0 + randf_range(-pitch_var, pitch_var), db)

## Como play(), pero con un tono exacto.
func play_pitched(name: String, pitch: float, db := 0.0) -> void:
	var st := _stream(ALIASES.get(name, name))
	if st == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = st
			p.pitch_scale = pitch
			p.volume_db = db
			p.play()
			return

## Uno de los tres blips de los bots (al azar).
func blip(db := -6.0) -> void:
	play("sfx_blip%d" % (1 + randi() % 3), 0.08, db)

## Pasos: el contrato de audio no trae pasos; si algún día existen sfx_step1..3, suenan.
func step() -> void:
	play("sfx_step%d" % (1 + randi() % 3), 0.1, -12.0)

## La música en bucle: "title", "shop", "market" (music_<nombre>.ogg) o "" para callar. Cambia con un fundido.
func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	if _music_tw and _music_tw.is_valid():
		_music_tw.kill()
	_music_tw = create_tween()
	if _music.playing:
		_music_tw.tween_property(_music, "volume_db", -60.0, FADE * 0.5)
	_music_tw.tween_callback(func():
		_music.stop()
		var st: AudioStream = null
		if name != "":
			st = _loop_stream("music_" + name)
		if st:
			_music.stream = st
			_music.volume_db = -60.0
			_music.play())
	if name != "":
		_music_tw.tween_property(_music, "volume_db", MUSIC_DB, FADE)

## El ambiente en bucle: "wind", "port" (amb_<nombre>.ogg) o "" para callar.
func ambience(name: String) -> void:
	if name == _amb_name:
		return
	_amb_name = name
	if _amb_tw and _amb_tw.is_valid():
		_amb_tw.kill()
	_amb_tw = create_tween()
	if _amb.playing:
		_amb_tw.tween_property(_amb, "volume_db", -60.0, FADE * 0.5)
	_amb_tw.tween_callback(func():
		_amb.stop()
		var st: AudioStream = null
		if name != "":
			st = _loop_stream("amb_" + name)
		if st:
			_amb.stream = st
			_amb.volume_db = -60.0
			_amb.play())
	if name != "":
		_amb_tw.tween_property(_amb, "volume_db", AMB_DB, FADE)

func music_name() -> String:
	return _music_name

# --- SS AUDIO: precarga de los bucles en la web.
## En la web (Godot 4.7 reproduce los sonidos como "samples" del navegador) cada sonido se decodifica ENTERO, en el
## hilo principal, la primera vez que suena: con bucles de 24-60 s es un tirón justo al cambiar de música o de
## ambiente (lo que el cliente notó como "lagazo" en Midnight Cauldron). prewarm() los registra al arrancar, mientras
## carga, y deja lo que tardó cada uno en prewarm_ms (la prueba web lo lee en la consola: "SS AUDIO prewarm").
## Se salta los que ya están registrados (registrar dos veces es un error). En escritorio no hace nada: allí los
## bucles se leen del archivo poco a poco.
const PREWARM := ["music_title", "amb_wind", "music_market", "amb_port", "music_shop"]
var prewarm_ms := {}

func prewarm() -> void:
	if not OS.has_feature("web"):
		return
	for n in PREWARM:
		prewarm_one(n)
	prewarm_report()

## --- BOOT: precarga UN bucle (si hace falta). Devuelve los ms que tardó (0 si ya estaba, si no existe o fuera de la
## web). Cada uno se decodifica entero en el hilo principal: por eso main.gd los hace en cuadros distintos.
func prewarm_one(n: String) -> float:
	if not OS.has_feature("web"):
		return 0.0
	var st := _loop_stream(n)
	if st == null or AudioServer.is_stream_registered_as_sample(st):
		return 0.0
	var t0 := Time.get_ticks_usec()
	AudioServer.register_stream_as_sample(st)
	prewarm_ms[n] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return prewarm_ms[n]

## La línea de la consola que leen las pruebas web ("SS AUDIO prewarm ms: {...} total N").
func prewarm_report() -> void:
	if not OS.has_feature("web"):
		return
	var total := 0.0
	for n in prewarm_ms:
		total += float(prewarm_ms[n])
	print("SS AUDIO prewarm ms: %s total %.0f" % [prewarm_ms, total])
# --- end SS AUDIO
