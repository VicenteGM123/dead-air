extends Control
class_name BenchGauge
## PROBAR: una aguja barre un arco en una pantalla CRT; hay que pararla en la zona verde (el centro brillante es
## "perfecto"). Un solo botón: clic, Espacio / Intro / E, o A / X en el mando (BenchUI llama a press()).
## Si nadie la para en 9 s, se para sola donde esté.
## --- SS BENCH (nuevo).

signal stopped(verdict: String)      # perfect | good | ok | miss

const AMBER_W := 0.1                   # el ámbar a cada lado del verde
const DELAY := 0.5                     # la aguja arranca después de este rato (para ver la zona)
const TIMEOUT := 9.0

var speed := 0.8                       # recorridos por segundo
var zone_w := 0.22
var zone_c := 0.5
var auto := false                      # bot: la para en el centro
var auto_miss := 0.0                   # bot torpe: la para corrida (fracción del recorrido)
var verdict := ""
var _u := 0.0
var _t := 0.0
var _done := false
var _flash := 0.0
var _style: StyleBox

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = UIKit.screen_style(12)

func setup(sweep: float, zone: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	speed = sweep
	zone_w = zone
	zone_c = rng.randf_range(0.24 + zone_w / 2.0, 0.76 - zone_w / 2.0)
	verdict = ""
	_u = 0.0
	_t = 0.0
	_done = false
	_flash = 0.0
	auto = false
	auto_miss = 0.0

func is_done() -> bool:
	return _done

func press() -> void:
	if _done or _t < DELAY * 0.5:
		return
	_done = true
	_flash = 1.0
	var d := absf(_u - zone_c)
	if d <= zone_w * 0.17:
		verdict = "perfect"
	elif d <= zone_w * 0.5:
		verdict = "good"
	elif d <= zone_w * 0.5 + AMBER_W:
		verdict = "ok"
	else:
		verdict = "miss"
	Sfx.play("good" if verdict in ["perfect", "good"] else ("blip" if verdict == "ok" else "bad"), 0.03, -4.0)
	stopped.emit(verdict)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	if not _done:
		var prev := _u
		if _t > DELAY:
			var x := (_t - DELAY) * speed
			_u = pingpong(x, 1.0)
		# bot: la para justo donde quiere (si la aguja pasó por ahí en este cuadro, aunque el cuadro sea largo)
		var aim := clampf(zone_c + auto_miss, 0.0, 1.0)
		if auto and _t > DELAY + 0.2 and aim >= minf(prev, _u) - 0.001 and aim <= maxf(prev, _u) + 0.001:
			_u = aim
			press()
		elif _t > TIMEOUT:
			press()
	queue_redraw()

func _ang(u: float) -> float:
	return PI + u * PI

func _draw() -> void:
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var f: Font = UIKit.font_mono
	var c := Vector2(size.x / 2.0, size.y - 46.0)
	var rad := minf(size.x * 0.4, size.y - 90.0)
	draw_string(f, Vector2(30, 48), "POWER TEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, BenchKit.AMBER)
	# fondo del arco
	draw_arc(c, rad, PI, TAU, 64, Color(0.05, 0.03, 0.02), 38.0)
	# zonas: rojo, ámbar, verde (con el centro perfecto), ámbar, rojo
	var g0 := zone_c - zone_w / 2.0
	var g1 := zone_c + zone_w / 2.0
	var segs := [[0.0, g0 - AMBER_W, Color(0.62, 0.18, 0.12)], [g0 - AMBER_W, g0, Color(0.85, 0.6, 0.18)],
		[g0, g1, Color(0.3, 0.68, 0.28)], [zone_c - zone_w * 0.17, zone_c + zone_w * 0.17, Color(0.62, 0.95, 0.5)],
		[g1, g1 + AMBER_W, Color(0.85, 0.6, 0.18)], [g1 + AMBER_W, 1.0, Color(0.62, 0.18, 0.12)]]
	for s in segs:
		var a0 := clampf(float(s[0]), 0.0, 1.0)
		var a1 := clampf(float(s[1]), 0.0, 1.0)
		if a1 > a0:
			draw_arc(c, rad, _ang(a0), _ang(a1), maxi(4, int((a1 - a0) * 64)), s[2], 28.0)
	# marcas
	for k in 21:
		var u := k / 20.0
		var dir := Vector2.from_angle(_ang(u))
		var l := 12.0 if k % 5 == 0 else 6.0
		draw_line(c + dir * (rad - 26.0), c + dir * (rad - 26.0 - l), Color(1.0, 0.72, 0.3, 0.6), 2.0)
	# la aguja
	var nd := Vector2.from_angle(_ang(_u))
	var ncol := Color(1.0, 0.9, 0.7)
	if _done:
		ncol = Color(0.7, 1.0, 0.6) if verdict in ["perfect", "good"] else (Color(1.0, 0.8, 0.35) if verdict == "ok" else BenchKit.RED)
	draw_line(c, c + nd * (rad + 16.0), Color(0, 0, 0, 0.5), 8.0)
	draw_line(c, c + nd * (rad + 16.0), ncol, 4.0)
	draw_circle(c, 14.0, Color(0.2, 0.15, 0.1))
	draw_circle(c, 9.0, ncol)
	if _flash > 0.0:
		draw_circle(c + nd * rad, 30.0 * _flash + 10.0, Color(1, 1, 0.8, 0.35 * _flash))
	# el veredicto
	if _done:
		var txt: String = {"perfect": "PERFECT!", "good": "GOOD", "ok": "SO-SO", "miss": "MISSED"}.get(verdict, "")
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y - rad * 0.42), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ncol)
	elif _t < DELAY:
		var w2 := f.get_string_size("CHARGING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(f, Vector2(c.x - w2 / 2.0, c.y - rad * 0.42), "CHARGING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BenchKit.AMBER_DIM)
