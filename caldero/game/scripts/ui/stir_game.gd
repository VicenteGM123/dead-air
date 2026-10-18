extends Control
class_name StirGame
## Minijuego: un cucharón da vueltas por el caldero; acierta la zona dorada para una poción más potente.
# --- R3 BENCH: dos modos con la misma API (speed, press(), finished, done; se pulsa solo a los 7 s):
#   embedded = true: en el banco del caldero (brew_ui.gd). La pista es una elipse sobre el líquido del caldero grande
#     (center / radii en px locales) y el cucharón de madera (assets/ui/bench_ladle.png) se mueve por ella, en pixel
#     art a la escala px.
#   embedded = false: suelto (Overlays.show_stir): un círculo con su fondo, como antes, con los mismos colores.

signal finished(perfect: bool)

var speed := 1.8          # vueltas por segundo (radianes * TAU)
var angle := 0.0
var zone_start := 0.0
var zone_size := 0.9      # radianes
var done := false
var embedded := false            # --- R3 BENCH
var center := Vector2.ZERO       # --- R3 BENCH: centro de la pista (cero: el centro del control)
var radii := Vector2.ZERO        # --- R3 BENCH: radios de la elipse (cero: un círculo según el tamaño)
var px := 4.0                    # --- R3 BENCH: un píxel del arte
var liquid := Color(0.35, 0.28, 0.5)   # --- R3 BENCH: color del líquido (modo suelto)
var _flash := 0.0
var _timer := 0.0
var _result := false
var _ladle: Texture2D
var _sparks: Array = []   # [pos, vel, edad]

const GOLD := Color(1.0, 0.84, 0.4)
const DOT := Color(1, 1, 1, 0.38)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_start = randf_range(0.6, TAU - 0.6 - zone_size)
	angle = 0.0
	if ResourceLoader.exists("res://assets/ui/bench_ladle.png"):
		_ladle = load("res://assets/ui/bench_ladle.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		var p := _point(angle)
		for i in 16:
			var d := Vector2.from_angle(randf() * TAU)
			_sparks.append([p, d * randf_range(60.0, 190.0) + Vector2(0, -60), 0.0])
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
	for s in _sparks:
		s[2] += delta
		s[1].y += 260.0 * delta
		s[0] += s[1] * delta
	_sparks = _sparks.filter(func(s): return s[2] < 0.8)
	queue_redraw()

## --- R3 BENCH: centro y radios de la pista (elipse en el banco, círculo suelto).
func _c() -> Vector2:
	return center if center != Vector2.ZERO else size / 2.0

func _r() -> Vector2:
	if radii != Vector2.ZERO:
		return radii
	var r := minf(size.x, size.y) * 0.4
	return Vector2(r, r)

## Punto de la pista para un ángulo (0 = arriba / al fondo del caldero, en el sentido de las agujas del reloj).
func _point(a: float) -> Vector2:
	var r := _r()
	return _c() + Vector2(sin(a) * r.x, -cos(a) * r.y)

func _snap(p: Vector2) -> Vector2:
	return (p / px).floor() * px

func _draw() -> void:
	if embedded:
		_draw_embedded()
	else:
		_draw_framed()

func _draw_embedded() -> void:
	var glow := 0.75 + 0.25 * sin(_timer * 7.0)
	var u := Vector2(px, px)
	# la zona dorada: una banda gruesa con halo (se dibuja primero, la pista pasa por encima)
	var zs := 40
	for i in zs + 1:
		var a := zone_start + zone_size * float(i) / float(zs)
		var p := _snap(_point(a))
		draw_rect(Rect2(p - u * 1.5, u * 4.0), Color(1.0, 0.75, 0.25, 0.22 * glow))
	for i in zs + 1:
		var a := zone_start + zone_size * float(i) / float(zs)
		var p := _snap(_point(a))
		draw_rect(Rect2(p - u * 0.5 + Vector2(0, px), u * 2.0), Color(0.45, 0.25, 0.05, 0.7))
		draw_rect(Rect2(p - u * 0.5, u * 2.0), Color(GOLD.r, GOLD.g, GOLD.b, glow))
		draw_rect(Rect2(p, u), Color(1.0, 0.97, 0.78, glow))
	# la pista: puntitos con sombra (se leen sobre cualquier color de líquido)
	var steps := 60
	for i in steps:
		var a := TAU * float(i) / float(steps)
		if a >= zone_start and a <= zone_start + zone_size:
			continue
		var p := _snap(_point(a))
		draw_rect(Rect2(p + Vector2(0, px), u), Color(0.05, 0.03, 0.08, 0.45))
		draw_rect(Rect2(p, u), Color(1, 1, 1, 0.7))
	# el cucharón: entra en el líquido en el punto de la pista (más pequeño al fondo) y una marca brillante allí
	var tip := _snap(_point(angle))
	var depth := lerpf(0.82, 1.0, (1.0 - cos(angle)) / 2.0)
	var rr := _r()
	for i in 8:
		var a := TAU * float(i) / 8.0 + _timer * 2.5
		var q := _snap(tip + Vector2(cos(a) * rr.x * 0.14, sin(a) * rr.y * 0.32))
		draw_rect(Rect2(q, u), Color(1, 1, 1, 0.35))
	if _ladle:
		var lean := sin(angle) * 0.3
		var lw := float(_ladle.get_width())
		var lh := float(_ladle.get_height())
		draw_set_transform(tip, lean, Vector2(px, px) * depth)
		draw_texture(_ladle, Vector2(-lw / 2.0, -lh + 2.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_line(tip, tip + Vector2(sin(angle) * 20.0, -110.0), Color(0.62, 0.42, 0.26), 10.0)
	# la marca: un rombo claro que late (es lo que hay que meter en el oro)
	var pulse := 1.0 + 0.25 * sin(_timer * 12.0)
	var d := px * 1.5 * pulse
	var pts := PackedVector2Array([tip + Vector2(0, -d - px), tip + Vector2(d + px, 0), tip + Vector2(0, d + px), tip + Vector2(-d - px, 0)])
	draw_colored_polygon(pts, Color(0.12, 0.07, 0.04, 0.85))
	pts = PackedVector2Array([tip + Vector2(0, -d), tip + Vector2(d, 0), tip + Vector2(0, d), tip + Vector2(-d, 0)])
	var in_zone := fposmod(angle, TAU) >= zone_start and fposmod(angle, TAU) <= zone_start + zone_size
	draw_colored_polygon(pts, Color(1.0, 0.95, 0.6) if in_zone else Color(1, 1, 1))
	_draw_sparks()
	if _flash > 0.0 and not _result:
		var r := _r()
		draw_set_transform(_c(), 0.0, Vector2(1.0, r.y / r.x))
		draw_circle(Vector2.ZERO, r.x * 1.1, Color(1, 1, 1, _flash * 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_framed() -> void:
	var c := _c()
	var r := _r().x
	# fondo: la boca del caldero vista desde arriba (líquido, borde de hierro y un filete de latón)
	draw_circle(c, r + 34, Color(0.07, 0.06, 0.1, 0.92))
	draw_circle(c, r + 22, liquid.darkened(0.25))
	draw_circle(c, r + 8, liquid)
	draw_arc(c, r + 28, 0, TAU, 96, Color(0.24, 0.24, 0.3), 12.0, true)
	draw_arc(c, r + 34, 0, TAU, 96, Color(0.79, 0.63, 0.35, 0.9), 3.0, true)
	# burbujas
	for i in 6:
		var t := _timer * 1.3 + i * 1.7
		var p := c + Vector2(sin(t * 1.3 + i) * r * 0.35, cos(t * 0.9 + i * 2.0) * r * 0.25)
		draw_circle(p, 5 + 3 * sin(t * 3.0), Color(1, 1, 1, 0.22))
	# pista y zona dorada (ángulos desde arriba, en el sentido de las agujas del reloj)
	draw_arc(c, r, 0, TAU, 96, Color(1, 1, 1, 0.28), 14.0, true)
	var z0 := zone_start - PI / 2.0
	var glow := 0.75 + 0.25 * sin(_timer * 6.0)
	draw_arc(c, r, z0, z0 + zone_size, 32, Color(GOLD.r, GOLD.g, GOLD.b, glow), 20.0, true)
	# cucharón de madera
	var a := angle - PI / 2.0
	var tip := c + Vector2(cos(a), sin(a)) * (r + 4)
	var base := c + Vector2(cos(a), sin(a)) * (r * 0.2)
	draw_line(base, tip, Color(0.29, 0.18, 0.1), 12.0, true)
	draw_line(base, tip, Color(0.69, 0.52, 0.32), 7.0, true)
	draw_circle(tip, 13, Color(0.29, 0.18, 0.1))
	draw_circle(tip, 10, Color(0.57, 0.42, 0.25))
	draw_circle(tip + Vector2(-3, -3), 4, Color(0.76, 0.6, 0.4))
	_draw_sparks()
	if _flash > 0.0:
		var col := Color(1.0, 0.9, 0.5, _flash * 0.6) if _result else Color(1, 1, 1, _flash * 0.3)
		draw_circle(c, r + 34, col)

func _draw_sparks() -> void:
	for s in _sparks:
		var a: float = 1.0 - s[2] / 0.8
		var p: Vector2 = _snap(s[0])
		draw_rect(Rect2(p, Vector2(px, px)), Color(1.0, 0.92, 0.6, a))
		if s[2] < 0.3:
			draw_rect(Rect2(p - Vector2(px, 0), Vector2(px * 3, px)), Color(1.0, 0.85, 0.4, a * 0.5))
			draw_rect(Rect2(p - Vector2(0, px), Vector2(px, px * 3)), Color(1.0, 0.85, 0.4, a * 0.5))
