extends SceneTree
## --- SS AUDIO: comprobación headless del audio de Secondhand Stars (archivo propio de la línea AUDIO).
##  1. los 18 archivos existen donde los busca Sfx (res://assets/audio o res://audio) y se cargan como OGG Vorbis;
##  2. la duración es la esperada y los 5 bucles salen con loop = true (Sfx._loop_stream);
##  3. los bucles DAN LA VUELTA: suenan a pitch 4 (cuatro veces más rápido) y la posición vuelve al principio sin que
##     el reproductor se pare (con el driver Dummy de --headless el mezclador avanza en tiempo real);
##  4. el camino real del juego: Sfx.music("title") + ambience("wind") -> music("shop") + ambience("port") ->
##     music("market"): después del fundido suena el archivo correcto al volumen de Sfx (MUSIC_DB / AMB_DB);
##  5. cada efecto con Sfx.play(nombre) queda sonando en el grupo de reproductores, y también los alias.
## Uso:  godot --headless --path game -s res://tools/audio_check.gd      (sale con código 1 si algo falla)

const LOOPS := {"music_title": 60.0, "music_shop": 60.0, "music_market": 57.6, "amb_wind": 24.0, "amb_port": 36.0}
const SFX := ["sfx_bell", "sfx_whistle", "sfx_blip1", "sfx_blip2", "sfx_blip3", "sfx_ratchet", "sfx_sizzle",
	"sfx_coins", "sfx_pod", "sfx_good", "sfx_bad", "sfx_takeoff", "sfx_tea"]

var fails := 0
var sfx: Node


func _initialize() -> void:
	_run()


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    ", msg)
	else:
		print("  FAIL  ", msg)
		fails += 1


func wait(s: float) -> void:
	await create_timer(s).timeout


## Si el modo -s no cargó los autoloads, se crean igual que los crea el proyecto (Game antes que Sfx).
func _ensure_autoloads() -> void:
	for nm in ["Game", "Data", "BenchData", "Sfx"]:
		if root.get_node_or_null(nm) != null:
			continue
		var path := str(ProjectSettings.get_setting("autoload/" + nm, "")).trim_prefix("*")
		if path == "":
			continue
		var n: Node = load(path).new()
		n.name = nm
		root.add_child(n)
		print("  (autoload %s creado a mano: %s)" % [nm, path])


func _run() -> void:
	await process_frame
	_ensure_autoloads()
	await process_frame
	sfx = root.get_node_or_null("Sfx")
	check(sfx != null, "autoload Sfx")
	check(ClassDB.class_has_method("AudioServer", "register_stream_as_sample"),
		"AudioServer.register_stream_as_sample existe (para precargar los bucles en la web)")
	if sfx == null:
		quit(1)
		return
	print("== 1-2. archivos, duración, loop")
	for n in LOOPS.keys() + SFX:
		var p: String = sfx.path_of(n)
		var st: AudioStream = load(p) if p != "" else null
		var ok := st is AudioStreamOggVorbis
		check(ok, "%-13s %s  %.3f s" % [n, p, st.get_length() if st else -1.0])
		if ok and LOOPS.has(n):
			var ls: AudioStream = sfx._loop_stream(n)
			check(ls.loop and absf(ls.get_length() - float(LOOPS[n])) < 0.01,
				"%-13s loop=%s, %.3f s (esperado %.2f)" % [n, ls.loop, ls.get_length(), LOOPS[n]])
	print("== 3. los bucles dan la vuelta (pitch 4, 20 s)")
	var players := {}
	for n in LOOPS:
		var pl := AudioStreamPlayer.new()
		pl.stream = sfx._loop_stream(n)
		pl.pitch_scale = 4.0
		pl.volume_db = -80.0
		root.add_child(pl)
		pl.play()
		players[n] = {"p": pl, "last": 0.0, "wraps": 0, "max": 0.0}
	var t := 0.0
	while t < 20.0:
		await wait(0.2)
		t += 0.2
		for n in players:
			var d: Dictionary = players[n]
			var pos: float = d["p"].get_playback_position()
			if pos + 1.0 < float(d["last"]):
				d["wraps"] = int(d["wraps"]) + 1
			d["max"] = maxf(float(d["max"]), pos)
			d["last"] = pos
	for n in players:
		var d: Dictionary = players[n]
		# el driver Dummy mezcla un poco más lento que el tiempo real: se pide al menos una vuelta completa
		check(int(d["wraps"]) >= 1 and float(d["max"]) > float(LOOPS[n]) - 1.5 and d["p"].playing,
			"%-13s %d vuelta(s) en 20 s, llegó a %.1f s de %.1f y sigue sonando=%s" % [n, d["wraps"], d["max"],
			LOOPS[n], d["p"].playing])
		d["p"].queue_free()
	print("== 4. el camino real (Sfx.music / Sfx.ambience con sus fundidos)")
	for step in [["title", "wind"], ["shop", "port"], ["market", "port"]]:
		sfx.music(step[0])
		sfx.ambience(step[1])
		await wait(2.2)
		var m: AudioStreamPlayer = sfx._music
		var a: AudioStreamPlayer = sfx._amb
		check(m.playing and m.stream != null and m.stream.resource_path.ends_with("music_%s.ogg" % step[0])
			and absf(m.volume_db - sfx.MUSIC_DB) < 0.5,
			"music(%s): suena %s a %.1f dB" % [step[0], m.stream.resource_path.get_file() if m.stream else "-", m.volume_db])
		check(a.playing and a.stream != null and a.stream.resource_path.ends_with("amb_%s.ogg" % step[1])
			and absf(a.volume_db - sfx.AMB_DB) < 0.5,
			"ambience(%s): suena %s a %.1f dB" % [step[1], a.stream.resource_path.get_file() if a.stream else "-", a.volume_db])
	sfx.music("")
	sfx.ambience("")
	await wait(1.0)
	check(not sfx._music.playing and not sfx._amb.playing, "music('') y ambience('') callan")
	print("== 5. efectos (y alias)")
	for n in SFX + ["click", "hover", "coin", "door", "tea"]:
		await wait(0.05)
		sfx.play(n)
		await process_frame
		var real: String = sfx.ALIASES.get(n, n)
		var found := false
		for pl in sfx._pool:
			if pl.playing and pl.stream and pl.stream.resource_path.ends_with(real + ".ogg"):
				found = true
		check(found, "play(%s) -> %s" % [n, real])
		for pl in sfx._pool:
			pl.stop()
	print("== %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	# soltar los sonidos antes de salir (sin avisos de recursos en uso)
	for pl in sfx._pool:
		pl.stream = null
	sfx._music.stream = null
	sfx._amb.stream = null
	sfx._streams.clear()
	await wait(0.3)          # el servidor de audio suelta las reproducciones paradas en su hilo
	quit(1 if fails else 0)
