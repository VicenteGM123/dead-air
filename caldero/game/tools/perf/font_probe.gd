extends SceneTree
## R6 PERF (prueba, no es del juego): cuánto cuesta dibujar por primera vez las letras grandes con contorno de la
## cuenta atrás y el «+3 ★». Mide la CPU del hilo principal (schedstat) en cada cuadro.
var _last := 0
func _cpu() -> float:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	var c := int(f.get_line().split(" ")[0])
	var d := (c - _last) / 1e6
	_last = c
	return d

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var font: Font = load("res://assets/fonts/AlegreyaSC-Bold.ttf")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	for i in 5:
		await process_frame
	_cpu()
	await process_frame
	print("idle frame cpu=%.1f" % _cpu())
	var tests := [["big 120/24 '3'", "3", 120, 24], ["big 120/24 '2 1'", "2 1", 120, 24], ["big 120/24 'Go!'", "Go!", 120, 24],
		["big 120/24 'Time! Done!'", "Time! Done!", 120, 24], ["pop 40/8 '+0123456789'", "+0123456789", 40, 8],
		["pop 40/8 '★'", "★", 40, 8], ["pop 40/8 'time'", "time", 40, 8], ["120 no outline 'ABC'", "ABC", 120, 0]]
	for t in tests:
		var l := Label.new()
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", t[2])
		if t[3] > 0:
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", t[3])
		l.text = t[1]
		layer.add_child(l)
		_cpu()
		await process_frame
		await process_frame
		print("%s: cpu=%.1f ms" % [t[0], _cpu()])
	quit()
