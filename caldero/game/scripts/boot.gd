extends Node
## --- BOOT: la primera escena del juego (run/main_scene = scenes/boot.tscn). Es casi nada a propósito: en la web, el
## motor hace su primer cuadro dentro de la misma tarea larga en la que arranca (setup + autoloads + la escena
## principal + su _ready), y mientras tanto la página no responde. Antes esa escena era main.tscn: compilar main.gd y
## todo lo que arrastra (~31 000 líneas de GDScript, 0,6 s en la web) y armar la tienda entera iban ahí, y después
## venían ~18 s de negro con cuadros de varios segundos (los precalentamientos de la ronda 6). Ahora:
##  1. el primer cuadro es solo la pantalla de carga (BootScreen: la misma imagen que la de arranque, con su barra);
##  2. los scripts se cargan (compilan) unos pocos por cuadro, con la barra avanzando;
##  3. se instancia main.tscn, y main.gd arma el juego en pasos (ver «# --- BOOT» en main.gd).
## Con --demo=... (pruebas y capturas) todo va como antes: main.tscn entra en el primer cuadro, sin pantalla de carga.

const MAIN_SCENE := "res://scenes/main.tscn"
const SCRIPT_DIRS := ["res://scripts/ui", "res://scripts/world", "res://scripts"]
const SLICE_USEC := 30000   # cuánto cargar por cuadro (después de pasar este tiempo, espera al siguiente)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			_start_main.call_deferred()
			return
	BootScreen.open(self)
	_load_scripts.call_deferred()

func _load_scripts() -> void:
	var tree := get_tree()
	await tree.process_frame   # el primer cuadro: solo la pantalla de carga
	var files: Array[String] = []
	for d in SCRIPT_DIRS:
		for f in ResourceLoader.list_directory(d):
			if String(f).ends_with(".gd"):
				files.append(d + "/" + String(f))
	files.erase("res://scripts/main.gd")   # la última (lo demás ya está compilado cuando llega)
	files.append("res://scripts/main.gd")
	var trace := false   # (con --perflog: cuántos scripts y cuáles tardan)
	for a in OS.get_cmdline_user_args():
		trace = trace or a.begins_with("--perflog")
	if trace:
		print("BOOT scripts=%d ticks=%d" % [files.size(), Time.get_ticks_msec()])
	var t := Time.get_ticks_usec()
	for i in files.size():
		var t1 := Time.get_ticks_usec()
		load(files[i])
		if trace and Time.get_ticks_usec() - t1 > 20000:
			print("BOOT load %s %d ms" % [files[i].get_file(), (Time.get_ticks_usec() - t1) / 1000])
		BootScreen.progress(lerpf(BootScreen.WEB_START, 0.55, float(i + 1) / files.size()))
		if Time.get_ticks_usec() - t > SLICE_USEC:
			await tree.process_frame
			t = Time.get_ticks_usec()
	_start_main()

func _start_main() -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	queue_free()
