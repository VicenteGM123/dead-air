extends Control
class_name BenchScope
## La pantalla CRT ámbar del banco (columna derecha): lo que lee cada herramienta.
##   LISTEN: un osciloscopio con la forma de la onda de la pieza rota (BenchData.WAVES; con pista turbia, "mixed")
##   TAP:    cuánto traquetea cada zócalo (4 barras, 1-4)
##   SCAN:   la temperatura de cada zócalo (4 barras; frío en azul, caliente en naranja)
##   y en los otros pasos: las uniones de la soldadura, el test. Debajo, una línea de texto (mono, con saltos).
## --- SS BENCH (nuevo).

var mode := "idle"          # idle | listen | tap | scan | solder | test | info
var title := "BENCH SCOPE"
var data := {}              # listen/tap/scan: BenchData.clue(); solder: {"lit", "n", "acc"}; test: {"verdict"}
var _t := 0.0
var _style: StyleBox
var _text: Label
var _bars_t := 0.0

const GRAPH_TOP := 58.0
const GRAPH_H := 92.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_style = UIKit.screen_style(12)
	_text = UIKit.label("", 17, BenchKit.AMBER, UIKit.font_mono)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_text)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_text.position = Vector2(26, GRAPH_TOP + GRAPH_H + 14)
	_text.size = Vector2(size.x - 52, size.y - (GRAPH_TOP + GRAPH_H + 14) - 22)

func show_mode(m: String, ttl: String, text: String, d := {}) -> void:
	mode = m
	title = ttl
	data = d
	_text.text = text
	_bars_t = 0.0
	queue_redraw()

func set_text(text: String) -> void:
	_text.text = text

func _process(delta: float) -> void:
	_t += delta
	_bars_t += delta
	queue_redraw()

func _draw() -> void:
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var f: Font = UIKit.font_mono
	# barrido de líneas de la pantalla (muy suave)
	var inner := Rect2(Vector2(22, 22), size - Vector2(44, 44))
	var y := inner.position.y + fmod(_t * 40.0, 4.0)
	while y < inner.end.y:
		draw_rect(Rect2(inner.position.x, y, inner.size.x, 1), Color(0, 0, 0, 0.12))
		y += 4.0
	draw_string(f, Vector2(26, 46), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 52, 16, BenchKit.AMBER)
	if fmod(_t, 1.0) < 0.6:
		draw_rect(Rect2(size.x - 40, 36, 10, 10), BenchKit.AMBER if mode != "idle" else BenchKit.AMBER_DIM)
	var g := Rect2(26, GRAPH_TOP, size.x - 52, GRAPH_H)
	# marco del gráfico
	draw_rect(g, Color(1.0, 0.7, 0.3, 0.06))
	for k in 5:
		var gx := g.position.x + g.size.x * k / 4.0
		draw_rect(Rect2(gx, g.position.y, 1, g.size.y), Color(1.0, 0.7, 0.3, 0.1))
	draw_rect(Rect2(g.position.x, g.get_center().y, g.size.x, 1), Color(1.0, 0.7, 0.3, 0.16))
	match mode:
		"listen":
			_draw_wave(g, String(data.get("wave", "hum")))
		"tap":
			_draw_bars(g, data.get("strength", []), false)
		"scan":
			_draw_bars(g, data.get("heat", []), true)
		"solder":
			_draw_joints(g)
		"test":
			_draw_test(g)
		_:
			_draw_idle(g)

func _wave_y(kind: String, x: float, t: float) -> float:
	# x 0..1 a lo ancho; devuelve -1..1
	match kind:
		"flat":
			return sin(x * 80.0 + t * 30.0) * 0.03
		"hiss":
			return sin(x * 18.0 + t * 6.0) * 0.35 + (randf() - 0.5) * 1.2
		"drone":
			return sin(x * TAU * 3.0 + t * 8.0) * 0.75
		"reverse":
			var ph := fmod(x * 3.0 - t * 1.2, 1.0)
			if ph < 0.0:
				ph += 1.0
			return sin(x * 60.0) * ph * 0.95
		"grind":
			var s := fmod(x * 7.0 + t * 3.0, 1.0)
			return (s * 2.0 - 1.0) * 0.7 + (randf() - 0.5) * 0.15
		"whine":
			return sin(x * TAU * 11.0 + t * 20.0) * 0.4
		"buzz":
			return 0.7 if sin(x * TAU * 6.0 + t * 14.0) > 0.0 else -0.7
		"sputter":
			var b := fmod(x * 2.5 - t * 1.5, 1.0)
			if b < 0.0:
				b += 1.0
			return sin(x * 90.0) * (0.9 if b < 0.22 else 0.05)
		"slow":
			return sin(x * TAU * 1.2 + t * 2.0) * 0.45
		"mixed":
			return (sin(x * 23.0 + t * 7.0) * 0.3 + sin(x * 61.0 - t * 5.0) * 0.2) + (randf() - 0.5) * 0.35
		_:
			return sin(x * TAU * 2.0 + t * 4.0) * 0.3

func _draw_wave(g: Rect2, kind: String) -> void:
	var n := int(g.size.x / 3.0)
	var prev := Vector2.ZERO
	for i in n + 1:
		var x := float(i) / float(n)
		var v := clampf(_wave_y(kind, x, _t), -1.0, 1.0)
		var p := Vector2(g.position.x + x * g.size.x, g.get_center().y - v * g.size.y * 0.45)
		p = p.round()
		if i > 0:
			draw_line(prev, p, Color(1.0, 0.78, 0.36, 0.95), 2.0)
			draw_line(prev, p, Color(1.0, 0.7, 0.3, 0.18), 6.0)
		prev = p

func _draw_bars(g: Rect2, vals: Array, heat: bool) -> void:
	var n := maxi(vals.size(), 4)
	var f: Font = UIKit.font_mono
	var bw := floorf(g.size.x / n) - 10.0
	var grow := minf(_bars_t / 0.5, 1.0)
	for i in n:
		var v := float(vals[i]) if i < vals.size() else 0.0
		var x := g.position.x + i * (bw + 10.0) + 5.0
		var h := 0.0
		var col := BenchKit.AMBER
		if heat:
			h = absf(v)
			col = BenchKit.COLD if v < -0.05 else (Color(1.0, 0.42, 0.14) if v > 0.9 else Color(1.0, 0.7, 0.3))
			h = maxf(h, 0.12)
		else:
			h = v
			if v > 0.01:
				h *= 0.75 + 0.25 * sin(_t * 30.0 + i)   # el traqueteo hace saltar la barra
		h = clampf(h, 0.0, 1.0) * grow
		var bh := roundf((g.size.y - 20.0) * h)
		var r := Rect2(x, g.end.y - 18.0 - bh, bw, bh)
		draw_rect(Rect2(x, g.position.y + 4, bw, g.size.y - 22), Color(1.0, 0.7, 0.3, 0.06))
		var seg := r.position.y
		while seg < r.end.y:
			draw_rect(Rect2(x, seg, bw, 4), col)
			seg += 6.0
		draw_string(f, Vector2(x + bw / 2.0 - 5, g.end.y), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, BenchKit.AMBER)

func _draw_joints(g: Rect2) -> void:
	var n := int(data.get("n", 4))
	var lit := int(data.get("lit", 0))
	var f: Font = UIKit.font_mono
	var step := g.size.x / maxf(1.0, n)
	for i in n:
		var c := Vector2(g.position.x + step * (i + 0.5), g.position.y + 34)
		var on := i < lit
		draw_circle(c, 14.0, Color(1.0, 0.7, 0.3, 0.12))
		draw_arc(c, 14.0, 0, TAU, 20, BenchKit.AMBER_DIM, 2.0)
		if on:
			draw_circle(c, 10.0, Color(1.0, 0.82, 0.45))
			draw_circle(c + Vector2(-3, -3), 3.0, Color(1, 1, 0.9))
	var acc := float(data.get("acc", -1.0))
	var line := "JOINTS %d/%d" % [lit, n]
	if acc >= 0.0:
		line += "   CLEAN %d%%" % int(round(acc * 100.0))
	draw_string(f, Vector2(g.position.x, g.end.y - 10), line, HORIZONTAL_ALIGNMENT_LEFT, g.size.x, 16, BenchKit.AMBER)

func _draw_test(g: Rect2) -> void:
	var f: Font = UIKit.font_mono
	var v := String(data.get("verdict", ""))
	var big := "READY" if v == "" else v.to_upper()
	var col := BenchKit.AMBER
	match v:
		"perfect", "good":
			col = Color(0.62, 0.95, 0.5)
		"ok":
			col = Color(1.0, 0.8, 0.35)
		"miss":
			col = BenchKit.RED
	if v == "" and fmod(_t, 0.8) > 0.5:
		col = BenchKit.AMBER_DIM
	var w := f.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, Vector2(g.get_center().x - w / 2.0, g.get_center().y + 10), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)

func _draw_idle(g: Rect2) -> void:
	# una línea que respira, esperando
	var n := int(g.size.x / 4.0)
	var prev := Vector2.ZERO
	for i in n + 1:
		var x := float(i) / float(n)
		var p := Vector2(g.position.x + x * g.size.x, g.get_center().y - sin(x * TAU * 2.0 + _t * 2.0) * 6.0).round()
		if i > 0:
			draw_line(prev, p, Color(1.0, 0.7, 0.3, 0.55), 2.0)
		prev = p
