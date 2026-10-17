extends Control
class_name StirGame
## Minijuego: una cuchara gira alrededor del caldero; acierta la zona dorada para una poción más potente.

signal finished(perfect: bool)

var speed := 1.8          # vueltas por segundo (radianes * TAU)
var angle := 0.0
var zone_start := 0.0
var zone_size := 0.9      # radianes
var done := false
var _flash := 0.0
var _timer := 0.0
var _result := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_start = randf_range(0.6, TAU - 0.6 - zone_size)
	angle = 0.0
	Sfx.play("stir", 0.05, -6.0)

func press() -> void:
	if done:
		return
	done = true
	var a := fposmod(angle, TAU)
	_result = a >= zone_start and a <= zone_start + zone_size
	_flash = 1.0
	if _result:
		Sfx.play("sparkle", 0.05, -2.0)
	else:
		Sfx.play("stir", 0.05, -4.0)
	finished.emit(_result)

func _process(delta: float) -> void:
	_timer += delta
	if not done:
		angle += delta * speed * 1.4
		if _timer > 7.0:
			press()
	_flash = maxf(0.0, _flash - delta * 2.0)
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.4
	# fondo
	draw_circle(c, r + 34, Color(0.05, 0.04, 0.09, 0.85))
	draw_arc(c, r + 34, 0, TAU, 96, Color(0.88, 0.74, 0.46, 0.7), 3.0, true)
	# pista
	draw_arc(c, r, 0, TAU, 96, Color(1, 1, 1, 0.12), 18.0, true)
	# zona dorada (ángulos medidos desde arriba, sentido horario)
	var z0 := zone_start - PI / 2.0
	var glow := 0.75 + 0.25 * sin(_timer * 6.0)
	draw_arc(c, r, z0, z0 + zone_size, 32, Color(1.0, 0.84, 0.4, glow), 22.0, true)
	# cuchara
	var a := angle - PI / 2.0
	var tip := c + Vector2(cos(a), sin(a)) * (r + 20)
	var base := c + Vector2(cos(a), sin(a)) * (r * 0.25)
	draw_line(base, tip, Color(0.62, 0.42, 0.26), 10.0, true)
	draw_circle(tip, 14, Color(0.78, 0.55, 0.34))
	draw_circle(tip, 8, Color(0.95, 0.75, 0.5))
	# centro: burbujas
	for i in 6:
		var t := _timer * 1.3 + i * 1.7
		var p := c + Vector2(sin(t * 1.3 + i) * r * 0.35, cos(t * 0.9 + i * 2.0) * r * 0.25)
		draw_circle(p, 5 + 3 * sin(t * 3.0), Color(0.8, 1.0, 0.95, 0.25))
	if _flash > 0.0:
		var col := Color(1.0, 0.9, 0.5, _flash * 0.6) if _result else Color(1, 1, 1, _flash * 0.3)
		draw_circle(c, r + 34, col)
