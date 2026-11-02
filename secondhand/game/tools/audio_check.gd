extends SceneTree
## --- SS AUDIO: comprobación headless del audio de Secondhand Stars (archivo propio de la línea AUDIO).
##  1. los 18 archivos existen donde los busca Sfx (res://assets/audio o res://audio) y se cargan como OGG Vorbis;
##  2. la duración es la esperada y los 5 bucles salen con loop = true (Sfx._loop_stream);
##  3. los bucles DAN LA VUELTA: suenan a pitch 4 (cuatro veces más rápido) y la posición vuelve al principio sin que
##     el reproductor se pare (con el driver Dummy de --headless el mezclador avanza en tiempo real);
##  4. el camino real del juego: Sfx.music("title") + ambience("wind") -> music("shop") + ambience("port") ->
##     music("market"): después del fundido suena el archivo correcto al volumen de Sfx (MUSIC_DB / AMB_DB);
##  5. cada efecto con Sfx.play(nombre) queda sonando en el grupo de reproductores, y también los alias.
##  --- SS2 RANK: también el audio nuevo de la ronda 2 (SS2_DESIGN §7): los bucles music_festival y amb_storm (y
##  music_gala, que no es bucle), los 11 efectos nuevos, cada uno sonando por su nombre completo (así suenan con o sin
##  los alias de Sfx.ALIASES2) y, si Sfx ya trae ALIASES2 (el árbol del JOIN), también por su alias corto.
## Uso:  godot --headless --path game -s res://tools/audio_check.gd      (sale con código 1 si algo falla)

const LOOPS := {"music_title": 60.0, "music_shop": 60.0, "music_market": 57.6, "amb_wind": 24.0, "amb_port": 36.0,
	"music_festival": 50.526, "amb_storm": 30.0, "music_night": 48.0}   # --- SS2 RANK: + los bucles nuevos
const ONCE := {"music_gala": 60.2}   # --- SS2 RANK: la gala no es un bucle (suena una vez y después la música de la noche)
const SFX2 := ["sfx_flap", "sfx_signal", "sfx_tape", "sfx_stamp", "sfx_upgrade", "sfx_cheer", "sfx_rumble", "sfx_gust",
	"sfx_comet", "sfx_rank_up", "sfx_rank_down"]   # --- SS2 RANK
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
	for n in LOOPS.keys() + ONCE.keys() + SFX + SFX2:
		var p: String = sfx.path_of(n)
		var st: AudioStream = load(p) if p != "" else null
		var ok := st is AudioStreamOggVorbis
		check(ok, "%-13s %s  %.3f s" % [n, p, st.get_length() if st else -1.0])
		if ok and LOOPS.has(n):
			var ls: AudioStream = sfx._loop_stream(n)
			check(ls.loop and absf(ls.get_length() - float(LOOPS[n])) < 0.01,
				"%-13s loop=%s, %.3f s (esperado %.2f)" % [n, ls.loop, ls.get_length(), LOOPS[n]])
		if ok and ONCE.has(n):
			check(absf(st.get_length() - float(ONCE[n])) < 0.5, "%-13s %.2f s (esperado ~%.1f, sin bucle)" % [n, st.get_length(), ONCE[n]])
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
	# --- SS2 RANK: los caminos nuevos: el festival y la tormenta en bucle, la gala UNA vez (Sfx.ONCE) y después la
	# noche (music_night, P1), los alias de LATE_LOOPS (music_race todavía no existe: su respaldo music_shop)
	if sfx.get("ONCE") != null:
		for step in [["festival", "storm", "music_festival", "amb_storm", true], ["gala", "storm", "music_gala", "amb_storm", false],
				["night", "", "music_night", "", true]]:
			sfx.music(step[0])
			sfx.ambience(step[1])
			await wait(2.2)
			var m2: AudioStreamPlayer = sfx._music
			check(m2.playing and m2.stream != null and m2.stream.resource_path.ends_with(String(step[2]) + ".ogg")
				and bool(m2.stream.loop) == bool(step[4]),
				"music(%s): suena %s loop=%s" % [step[0], m2.stream.resource_path.get_file() if m2.stream else "-",
				m2.stream.loop if m2.stream else "-"])
			if String(step[3]) != "":
				var a2: AudioStreamPlayer = sfx._amb
				check(a2.playing and a2.stream != null and a2.stream.resource_path.ends_with(String(step[3]) + ".ogg") and a2.stream.loop,
					"ambience(%s): suena %s en bucle" % [step[1], a2.stream.resource_path.get_file() if a2.stream else "-"])
		for al in sfx.LATE_LOOPS:
			var full := String(sfx.LATE_LOOPS[al])
			check(sfx.path_of(full) != "" or sfx.LOOP_FALLBACK.has(full), "LATE_LOOPS %s -> %s (%s)" % [al, full,
				"existe" if sfx.path_of(full) != "" else "respaldo " + String(sfx.LOOP_FALLBACK.get(full, ""))])
		check(sfx.has_sound("flap") and sfx.has_sound("comet") and not sfx.has_sound("whoosh"), "has_sound con ALIASES2 (whoosh es P1: sin archivo)")
	sfx.music("")
	sfx.ambience("")
	await wait(1.0)
	check(not sfx._music.playing and not sfx._amb.playing, "music('') y ambience('') callan")
	print("== 5. efectos (y alias)")
	var short2: Array = []   # --- SS2 RANK: los alias cortos si este Sfx ya los tiene (el árbol del JOIN)
	var al2 = sfx.get("ALIASES2")
	if al2 is Dictionary:
		short2 = (al2 as Dictionary).keys().filter(func(k): return String(al2[k]) in SFX2)
	for n in SFX + ["click", "hover", "coin", "door", "tea"] + SFX2 + short2:
		await wait(0.05)
		sfx.play(n)
		await process_frame
		var real: String = sfx.ALIASES.get(n, (al2 as Dictionary).get(n, n) if al2 is Dictionary else n)
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
