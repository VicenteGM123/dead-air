extends Control
class_name BenchPodView
## La cápsula de chatarra sobre su pie (assets/items/pod_closed.png / pod_open.png a x4) y la animación de abrirla:
## tiembla (tres golpecitos), estalla (destello + polvo + la tapa salta) y lo de adentro sale volando en arco, una
## cosa por vez, hasta su tarjeta del cajón (landed(i) avisa cuando llega). Cubre todo el lienzo (dibuja los vuelos
## por encima de todo) y no atrapa el ratón.
## --- SS BENCH (nuevo).

signal landed(i: int)
signal burst
signal all_landed

const SCALE := 4.0
const SHAKE := 0.8              # cuánto tiembla antes de abrirse
const GAP := 0.34               # entre una cosa y la siguiente
const FLY := 0.5

var pod_center := Vector2(640, 260)    # el centro de la cápsula (en el lienzo)
var targets: Array = []                # dónde aterriza cada cosa (centros, en el lienzo)
var icons: Array = []                  # [Texture2D, escala]
var state := "closed"                  # closed | opening | done
var _t := 0.0
var _anim := 0.0
var _landed := 0
var _dust: Array = []                  # [pos, vel, vida]
var _closed_tex: Texture2D
var _open_tex: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_closed_tex = BenchKit.tex("res://assets/items/pod_closed.png")
	_open_tex = BenchKit.tex("res://assets/items/pod_open.png")

func reset(center: Vector2, tgts: Array, ics: Array) -> void:
	pod_center = center
	targets = tgts
	icons = ics
	state = "closed"
	_t = 0.0
	_landed = 0
	_dust.clear()

func crack() -> void:
	if state != "closed":
		return
	state = "opening"
	_t = 0.0
	Sfx.play("ratchet", 0.1, -4.0)

## Termina la animación de una vez (todo aterrizado).
func skip() -> void:
	if state == "done":
		return
	if state == "closed":
		state = "opening"
		emit_signal("burst")
	while _landed < targets.size():
		landed.emit(_landed)
		_landed += 1
	state = "done"
	_t = SHAKE + GAP * targets.size() + FLY
	all_landed.emit()

func _process(delta: float) -> void:
	_anim += delta
	if state == "opening":
		var before := _t
		_t += delta
		# los golpecitos
		for k in [0.3, 0.55]:
			if before < k and _t >= k:
				Sfx.play("ratchet", 0.1, -6.0)
		if before < SHAKE and _t >= SHAKE:
			_burst()
		while _landed < targets.size() and _t >= SHAKE + 0.15 + GAP * _landed + FLY:
			landed.emit(_landed)
			Sfx.play_pitched("blip", 1.0 + 0.15 * _landed, -6.0)
			_landed += 1
		if _landed >= targets.size() and _t >= SHAKE + 0.15 + GAP * maxi(0, targets.size() - 1) + FLY:
			state = "done"
			all_landed.emit()
	for d in _dust:
		d[0] += d[1] * delta
		d[1] *= 0.9
		d[2] -= delta
	_dust = _dust.filter(func(d): return d[2] > 0.0)
	queue_redraw()

func _burst() -> void:
	Sfx.play("pod", 0.03, -2.0)
	burst.emit()
	for k in 18:
		var ang := randf_range(-PI, 0.0)
		_dust.append([pod_center + Vector2(0, -20), Vector2(cos(ang), sin(ang)) * randf_range(120.0, 320.0), randf_range(0.4, 0.9)])

func _draw() -> void:
	var size_px := Vector2(64, 64) * SCALE
	var base := pod_center + Vector2(0, size_px.y / 2.0)
	# el pie (una base de metal remachada) y la sombra
	draw_rect(Rect2(base + Vector2(-112, -8), Vector2(224, 16)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(base + Vector2(-96, -12), Vector2(192, 22)), Color(0.33, 0.31, 0.29))
	draw_rect(Rect2(base + Vector2(-96, -12), Vector2(192, 4)), Color(0.55, 0.52, 0.48))
	for x in [-84.0, 76.0]:
		draw_rect(Rect2(base + Vector2(x, -4), Vector2(8, 8)), Color(0.7, 0.66, 0.6))
	var opened := state == "done" or (state == "opening" and _t >= SHAKE)
	var tex: Texture2D = _open_tex if opened else _closed_tex
	var off := Vector2.ZERO
	if state == "closed":
		off.y = -roundf((0.5 + 0.5 * sin(_anim * 2.0)) * 2.0) * 2.0
	elif state == "opening" and _t < SHAKE:
		var amp := 2.0 + 6.0 * (_t / SHAKE)
		off.x = roundf(sin(_t * 70.0) * amp / 2.0) * 2.0
	if tex:
		draw_texture_rect(tex, Rect2((pod_center - size_px / 2.0 + off).round(), size_px), false)
	else:
		draw_circle(pod_center, 100.0, Color(0.5, 0.52, 0.55))
	# destello al abrirse
	if state == "opening" and _t >= SHAKE and _t < SHAKE + 0.35:
		var k := (_t - SHAKE) / 0.35
		draw_circle(pod_center + Vector2(0, -40), 40.0 + 160.0 * k, Color(1.0, 0.95, 0.75, 0.55 * (1.0 - k)))
	for d in _dust:
		var a: float = clampf(d[2] / 0.9, 0.0, 1.0)
		draw_rect(Rect2((d[0] as Vector2).round(), Vector2(8, 8)), Color(0.86, 0.78, 0.62, a))
	# lo que vuela
	if state == "opening":
		for i in targets.size():
			var t0 := SHAKE + 0.15 + GAP * i
			var k := (_t - t0) / FLY
			if k <= 0.0 or k >= 1.0 or i < _landed:
				continue
			var from := pod_center + Vector2(0, -70)
			var to: Vector2 = targets[i]
			var p := from.lerp(to, k) + Vector2(0, -150.0 * sin(k * PI))
			var ic: Array = icons[i] if i < icons.size() else [null, 3.0]
			var t2: Texture2D = ic[0]
			if t2:
				var s := Vector2(t2.get_width(), t2.get_height()) * float(ic[1])
				draw_texture_rect(t2, Rect2((p - s / 2.0).round(), s), false)
