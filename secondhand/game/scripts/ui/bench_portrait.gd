extends Control
class_name BenchPortrait
## La cabina del regateo: el personaje (assets/chars/<id>_idle.png, 2 cuadros) a x3 detrás de un mostrador, con luz
## cálida, y las "señales" de cada especie dibujadas encima:
##   snort  (Hornback): dos bocanadas de vapor de la nariz y un pisotón (tiembla)
##   crest  (Quill): la cresta parpadea (farol) o queda quieta y apenas brilla (de verdad es su último precio)
##   glow   (Glimmerfolk): los pensamientos de la cúpula brillan cálidos (le gusta), tibios o fríos (azul)
##   hide   (Burrower): se esconde detrás del mostrador
##   watch  (pilot humano): mira la hora (un reloj que salta junto a la cabeza)
##   calc   (bot): una pantallita "CALC..." sobre la cabeza
##   tongue (Dune Raker): saca la lengua (rosada), rápido
## --- SS BENCH (nuevo). Los puntos de la cabeza de cada personaje salen de mirar sus hojas (en píxeles del cuadro).

const SCALE := 3.0
const FRAME := Vector2(64, 96)
## Dónde está cada cosa en el cuadro de 64x96 (mirando a la derecha).
const ANCHORS := {
	"gorrum": {"nose": Vector2(39, 31), "head": Vector2(30, 24)},
	"zib": {"crest": Rect2(20, 12, 19, 14), "head": Vector2(33, 26)},
	"oona": {"dome": Vector2(31, 36), "dome_r": 10.0, "head": Vector2(31, 36)},
	"pipip": {"goggles": Vector2(32, 57), "head": Vector2(32, 54)},
	"rook": {"head": Vector2(32, 33)},
	"clatter": {"head": Vector2(31, 19)},
	"raker": {"mouth": Vector2(45, 42), "head": Vector2(37, 38)},
	"mags": {"head": Vector2(32, 32)},
	"nell": {"head": Vector2(31, 36)},
	"kettle": {"head": Vector2(32, 72)},
}

var char_id := ""
var _frames: Array = []
var _t := 0.0
var _fx := {}            # efecto -> tiempo que queda
var _glow := Color(0, 0, 0, 0)
var _glow_target := Color(0, 0, 0, 0)
var _crest := ""         # "" | bluff | steady
var _hide := 0.0         # 0..1 cuánto se esconde
var _hide_on := false
var _counter_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true

func set_char(id: String) -> void:
	char_id = id
	_frames = []
	for i in 2:
		var a := BenchKit.frame("res://assets/chars/%s_idle.png" % id, i)
		if a == null:
			a = BenchKit.frame("res://assets/chars/nell_idle.png", i)
		_frames.append(a)
	_fx.clear()
	_glow = Color(0, 0, 0, 0)
	_glow_target = _glow
	_crest = ""
	_hide = 0.0
	_hide_on = false

## Una señal: snort | watch | calc | tongue | shake (dura secs).
func fx(name: String, secs := 1.2) -> void:
	_fx[name] = secs

func set_crest(mode: String) -> void:
	_crest = mode

## Brillo de la cúpula: "warm", "mild", "cool" o "" (apagado).
func set_glow(kind: String) -> void:
	match kind:
		"warm":
			_glow_target = Color(1.0, 0.5, 0.25, 0.85)
		"mild":
			_glow_target = Color(1.0, 0.86, 0.35, 0.6)
		"cool":
			_glow_target = Color(0.35, 0.55, 1.0, 0.8)
		_:
			_glow_target = Color(0.8, 0.75, 1.0, 0.2)

func set_hiding(on: bool) -> void:
	_hide_on = on

## Un punto del personaje (en píxeles del cuadro) en coordenadas de este control.
func to_local_px(p: Vector2) -> Vector2:
	return _origin() + p * SCALE

func head_point() -> Vector2:
	var a: Dictionary = ANCHORS.get(char_id, {})
	return to_local_px(a.get("head", Vector2(32, 30)))

## Lo más alto del personaje (para el globo), en coordenadas de este control.
func top_point() -> Vector2:
	var a: Dictionary = ANCHORS.get(char_id, {})
	var h: Vector2 = a.get("head", Vector2(32, 30))
	return to_local_px(Vector2(h.x, maxf(8.0, h.y - 16.0)))

func _origin() -> Vector2:
	# de la fila 76 del cuadro para abajo, detrás del mostrador (se ve de la cintura para arriba)
	var hide_px := roundf(_hide * (13.0 if char_id == "pipip" else 26.0)) * SCALE   # Pipip es bajito: quedan los gogles
	return Vector2(roundf((size.x - FRAME.x * SCALE) / 2.0), size.y - 70.0 - 76.0 * SCALE + hide_px)

func _process(delta: float) -> void:
	_t += delta
	for k in _fx.keys():
		_fx[k] -= delta
		if _fx[k] <= 0.0:
			_fx.erase(k)
	_glow = _glow.lerp(_glow_target, 1.0 - exp(-6.0 * delta))
	_hide = move_toward(_hide, 1.0 if _hide_on else 0.0, delta * 3.0)
	queue_redraw()

func _px(v: Vector2) -> Vector2:
	return (v / SCALE).floor() * SCALE

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# fondo: pared cálida del puesto, con una lámpara arriba
	draw_rect(r, Color(0.16, 0.11, 0.08))
	for k in 6:
		var a := 0.06 - k * 0.009
		draw_rect(Rect2(size.x * 0.5 - 60 - k * 30, 0, 120 + k * 60, size.y - 70), Color(1.0, 0.72, 0.4, a))
	var y := 22.0
	while y < size.y - 70:
		draw_rect(Rect2(0, y, size.x, 2), Color(0, 0, 0, 0.18))
		y += 42.0
	# el personaje (respira: 2 cuadros)
	var o := _origin()
	if _fx.has("snort") or _fx.has("shake"):
		o.x += (3.0 if fmod(_t, 0.1) < 0.05 else -3.0)
	if not _frames.is_empty() and _frames[0]:
		var fr: Texture2D = _frames[0 if fmod(_t, 1.2) < 0.8 else 1]
		draw_texture_rect(fr, Rect2(o, FRAME * SCALE), false)
	var a2: Dictionary = ANCHORS.get(char_id, {})
	# la cúpula de Oona
	if _glow.a > 0.02 and a2.has("dome"):
		var c := o + (a2["dome"] as Vector2) * SCALE
		var rad: float = float(a2.get("dome_r", 10.0)) * SCALE
		var pulse := 0.85 + 0.15 * sin(_t * 4.0)
		for k in 4:
			draw_circle(c, rad * (1.0 + k * 0.25), Color(_glow.r, _glow.g, _glow.b, _glow.a * pulse * (0.45 - k * 0.1)))
	# la cresta de Zib
	if _crest != "" and a2.has("crest"):
		var cr: Rect2 = a2["crest"]
		var rr := Rect2(o + cr.position * SCALE, cr.size * SCALE)
		var fr2: Texture2D = _frames[0 if fmod(_t, 1.2) < 0.8 else 1] if not _frames.is_empty() else null
		if _crest == "bluff":
			var on := fmod(_t, 0.16) < 0.08
			# la cresta parpadea: se vuelven a dibujar SOLO sus píxeles, encendidos (sin cuadro alrededor)
			if on and fr2:
				draw_texture_rect_region(fr2, rr, cr, Color(1.9, 1.8, 0.9, 1.0))
			if on:
				for k in 3:
					var sp := _px(rr.position + Vector2(rr.size.x * (0.2 + k * 0.3), -8.0 - k * 4.0))
					draw_rect(Rect2(sp, Vector2(6, 6)), Color(1.0, 0.95, 0.6, 0.9))
		elif fr2:
			draw_texture_rect_region(fr2, rr, cr, Color(0.85, 1.0, 1.25, 1.0))   # quieta: un brillo frío y parejo
	# el vapor de Gorrum
	if _fx.has("snort") and a2.has("nose"):
		var n := o + (a2["nose"] as Vector2) * SCALE
		var k2: float = 1.2 - float(_fx["snort"])
		for i in 2:
			var p := _px(n + Vector2(10 + k2 * 60.0, 6 + i * 10 + k2 * 24.0))
			var s := 12.0 + k2 * 26.0
			draw_rect(Rect2(p, Vector2(s, s * 0.7)), Color(0.95, 0.95, 0.92, clampf(0.85 - k2 * 0.7, 0.0, 1.0)))
	# la lengua del Raker
	if _fx.has("tongue") and a2.has("mouth"):
		var m := o + (a2["mouth"] as Vector2) * SCALE
		var ph := fmod(_t * 6.0, 1.0)
		var out := 0.0 if ph > 0.6 else sin(ph / 0.6 * PI)
		var len := roundf(out * 7.0) * SCALE
		if len > 0.0:
			draw_rect(Rect2(m, Vector2(len, SCALE)), Color(0.95, 0.45, 0.55))
			draw_rect(Rect2(m + Vector2(len, -SCALE), Vector2(SCALE, SCALE)), Color(0.95, 0.45, 0.55))
			draw_rect(Rect2(m + Vector2(len, SCALE), Vector2(SCALE, SCALE)), Color(0.95, 0.45, 0.55))
	# el reloj del piloto
	if _fx.has("watch"):
		var hp := head_point() + Vector2(46, -40)
		var bob := -roundf(absf(sin(_t * 8.0)) * 4.0)
		var tex := BenchKit.tex("res://assets/ui/icon_clock.png")
		if tex:
			draw_texture_rect(tex, Rect2(_px(hp + Vector2(0, bob)), Vector2(48, 48)), false)
	# el bot calcula
	if _fx.has("calc"):
		var hp2 := head_point() + Vector2(34, -20)      # a la derecha de la cabeza (el globo va arriba)
		draw_rect(Rect2(hp2, Vector2(80, 28)), Color(0.08, 0.06, 0.03))
		draw_rect(Rect2(hp2, Vector2(80, 28)), Color(1.0, 0.72, 0.3), false, 2.0)
		var dots := ".".repeat(1 + int(_t * 4.0) % 3)
		draw_string(UIKit.font_mono, hp2 + Vector2(8, 20), "CALC" + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.72, 0.3))
	# el mostrador adelante (tapa los pies; detrás se esconde Pipip)
	var top := size.y - 70.0
	draw_rect(Rect2(0, top, size.x, 70), Color(0.36, 0.22, 0.13))
	draw_rect(Rect2(0, top, size.x, 8), Color(0.62, 0.42, 0.25))
	draw_rect(Rect2(0, top + 8, size.x, 3), Color(0.2, 0.12, 0.07))
	var x := 12.0
	while x < size.x:
		draw_rect(Rect2(x, top + 18, 2, 52), Color(0.25, 0.15, 0.09))
		x += 64.0
