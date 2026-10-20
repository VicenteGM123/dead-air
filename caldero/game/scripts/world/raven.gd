extends Node3D
class_name Raven
## --- R4 RAVEN: Graznido, el cuervo mensajero de Krápido (gorra roja de mensajero, cartera con el logo, muy chulo).
## Llega volando por la ventanilla hasta su percha, espera con un reloj encima (un aro que se vacía), agarra la botella
## con un saltito, la guarda en la cartera, suelta una rima y se va volando. Si nadie le da nada, se va enojado.
## Lo maneja scripts/krapido.gd. Arte: assets/props/raven.png (16 cuadros de 64x64, tools/arte/raven_art.py) y
## assets/props/raven_ring.png (16 cuadros de 20x20: el reloj).

signal landed
signal gone

const FRAME := 64
const PX := 0.0115            # tamaño de un píxel en el mundo (el cuervo mide ~0,6 m con la gorra)
const FEET := 3.5             # píxeles entre las patas y el borde de abajo del cuadro
## Los cuadros de la tira (ver RAVEN_POSES en raven_art.py).
const F := {"perch": 0, "blink": 1, "tilt_up": 2, "tilt_down": 3, "ruffle_a": 4, "ruffle_b": 5, "talk": 6,
	"crouch": 7, "hop": 8, "land": 9, "angry_a": 10, "angry_b": 11, "fly_up": 12, "fly_mid": 13, "fly_down": 14, "glide": 15}
## Puntos del dibujo (en píxeles del cuadro, posado): la punta del pico y la cartera.
const BEAK_PX := Vector2(57.0, 27.0)
const BAG_PX := Vector2(25.0, 49.0)
const RING_FRAMES := 16

var sprite: AnimatedSprite3D
var ring: Sprite3D
var shadow: MeshInstance3D
var state := "away"           # away | flying | perched | leaving
var _line: Label3D
var _fly_tw: Tween

func _ready() -> void:
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames = _frames()
	sprite.pixel_size = PX
	sprite.centered = false
	sprite.offset = Vector2(-FRAME / 2.0, -FEET)
	sprite.shaded = true
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	sprite.play("perch")
	# el reloj sobre su cabeza (se tiñe: verde, ámbar, rojo)
	ring = Sprite3D.new()
	ring.texture = load("res://assets/props/raven_ring.png")
	ring.hframes = RING_FRAMES
	ring.pixel_size = 0.013
	ring.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ring.no_depth_test = true
	ring.render_priority = 9
	ring.shaded = false
	ring.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ring.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.74, 0.08)
	ring.visible = false
	add_child(ring)
	visible = false

## Las animaciones: posado (con parpadeos, cabeza ladeada y una sacudida de vez en cuando), hablar, agarrar, enojado
## y volar.
func _frames() -> SpriteFrames:
	var tex: Texture2D = load("res://assets/props/raven.png")
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var anims := {
		"perch": [8.0, true, [["perch", 6], ["blink", 1], ["perch", 5], ["tilt_up", 4], ["perch", 3], ["tilt_down", 5],
			["perch", 4], ["blink", 1], ["perch", 3], ["ruffle_a", 1], ["ruffle_b", 1], ["ruffle_a", 1], ["perch", 4]]],
		"talk": [7.0, true, [["talk", 1], ["tilt_up", 1], ["talk", 1], ["perch", 1]]],
		"grab": [10.0, false, [["crouch", 2], ["hop", 3], ["land", 2], ["perch", 1]]],
		"angry": [6.0, true, [["angry_a", 2], ["angry_b", 2]]],
		"fly": [12.0, true, [["fly_up", 1], ["fly_mid", 1], ["fly_down", 1], ["fly_mid", 1]]],
		"glide": [4.0, true, [["glide", 1]]],
	}
	for name in anims:
		var a: Array = anims[name]
		sf.add_animation(name)
		sf.set_animation_speed(name, a[0])
		sf.set_animation_loop(name, a[1])
		for fr in a[2]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(int(F[fr[0]]) * FRAME, 0, FRAME, FRAME)
			sf.add_frame(name, at, float(fr[1]))
	return sf

func face(dir: int) -> void:
	sprite.flip_h = dir < 0

## Dónde está la punta del pico (para que la botella vuele hasta ahí).
func beak_position() -> Vector3:
	var dx := (BEAK_PX.x - FRAME / 2.0) * PX * (-1.0 if sprite.flip_h else 1.0)
	return global_position + Vector3(dx, (FRAME - FEET - BEAK_PX.y) * PX, 0.04)

func bag_position() -> Vector3:
	var dx := (BAG_PX.x - FRAME / 2.0) * PX * (-1.0 if sprite.flip_h else 1.0)
	return global_position + Vector3(dx, (FRAME - FEET - BAG_PX.y) * PX, 0.05)

## Llega volando desde afuera (detrás de la pared) hasta la percha, por el hueco de la ventanilla.
func fly_in(perch: Vector3) -> void:
	_kill_fly()
	state = "flying"
	visible = true
	ring.visible = false
	var a := perch + Vector3(2.2, 1.1, -4.6)      # afuera, arriba a la derecha (lo tapa la pared)
	var b := perch + Vector3(0.35, 0.55, -1.2)    # justo detrás del hueco
	global_position = a
	face(-1)
	sprite.play("fly")
	Sfx.play("wings", 0.08, -9.0)
	_fly_tw = create_tween()
	_fly_tw.tween_method(func(t: float): global_position = _bez(a, b, perch, t), 0.0, 1.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _fly_tw.finished
	if state != "flying":
		return
	global_position = perch
	face(1)
	sprite.play("grab")   # se posa con un saltito
	await get_tree().create_timer(0.45).timeout
	if state != "flying":
		return
	state = "perched"
	sprite.play("perch")
	landed.emit()

## Se va volando por la ventanilla (con la botella en la cartera o de vacío).
func fly_off() -> void:
	_kill_fly()
	state = "leaving"
	ring.visible = false
	var p := global_position
	var b := p + Vector3(0.2, 0.5, -1.3)
	var c := p + Vector3(-2.6, 1.8, -5.0)
	face(-1)
	sprite.play("fly")
	Sfx.play("wings", 0.08, -9.0)
	_fly_tw = create_tween()
	_fly_tw.tween_method(func(t: float): global_position = _bez(p, b, c, t), 0.0, 1.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _fly_tw.finished
	visible = false
	state = "away"
	gone.emit()

## Lo esconde al instante (fin del día, título, demos).
func hide_now() -> void:
	_kill_fly()
	state = "away"
	visible = false
	ring.visible = false
	if is_instance_valid(_line):
		_line.queue_free()

## Lo pone posado al instante (capturas).
func perch_now(perch: Vector3) -> void:
	_kill_fly()
	global_position = perch
	visible = true
	face(1)
	state = "perched"
	sprite.play("perch")

## Agarra la botella (ya llegó volando a su pico): un saltito, la guarda en la cartera y brilla.
func catch(tex: Texture2D) -> void:
	sprite.play("grab")
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = 0.022
	s.shaded = false
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.render_priority = 6
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(s)
	s.global_position = beak_position()
	var tw := s.create_tween()
	tw.tween_property(s, "global_position", beak_position() + Vector3(0, 0.12, 0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "global_position", bag_position(), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s, "scale", Vector3.ONE * 0.3, 0.3)
	tw.tween_callback(s.queue_free)
	await tw.finished
	Sfx.play("plop", 0.05, -6.0)
	await get_tree().create_timer(0.2).timeout
	if state == "perched":
		sprite.play("perch")

## Enojado: se esponja y grazna (se queda así hasta que se va).
func angry() -> void:
	sprite.play("angry")
	Sfx.play("kraa", 0.04, -3.0)

## Habla un ratito (pico que se abre y se cierra) y vuelve a posarse.
func talk(secs := 1.2) -> void:
	if state != "perched":
		return
	sprite.play("talk")
	await get_tree().create_timer(secs).timeout
	if state == "perched" and sprite.animation == "talk":
		sprite.play("perch")

## El reloj sobre él: frac 1 = recién llegado, 0 = se va. frac < 0 lo esconde.
func set_wait(frac: float) -> void:
	if frac < 0.0 or state != "perched":
		ring.visible = false
		return
	ring.visible = true
	frac = clampf(frac, 0.0, 1.0)
	ring.frame = clampi(int(round((1.0 - frac) * (RING_FRAMES - 1))), 0, RING_FRAMES - 1)
	var col := Color(0.62, 0.95, 0.6)
	if frac < 0.25:
		col = Color(1.0, 0.45, 0.4)
	elif frac < 0.55:
		col = Color(1.0, 0.78, 0.38)
	if frac < 0.25:
		col = col.lerp(Color(1.4, 0.7, 0.6), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))
	ring.modulate = col

## Una rima (o lo que diga): letra a mano a la derecha de la ventanilla (sobre el estante), que sube un poco y se
## desvanece. Va a la derecha y no arriba del letrero porque arriba la pantalla se desenfoca (tilt-shift del post) y,
## desde el mostrador, la ventanilla queda en el borde izquierdo: así se lee en las dos vistas.
const LINE_SIZE := 50
const LINE_PX := 0.0056
func say(text: String, secs := 3.2) -> void:
	if is_instance_valid(_line):
		_line.queue_free()
	PaperKit.load_fonts()
	var font: Font = PaperKit.font_hand_bold
	var l := Label3D.new()
	l.text = two_lines(text)
	l.font = font
	l.font_size = LINE_SIZE
	l.pixel_size = LINE_PX
	l.outline_size = 18
	l.outline_modulate = Color(0.07, 0.04, 0.1)
	l.modulate = Color(1.0, 0.93, 0.78)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 9
	l.shaded = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	_line = l
	# el bloque empieza justo a la derecha del marco (x 0,42 m) y su borde de abajo queda a 0,5 m de sus patas
	var lines := l.text.split("\n")
	var w := 0.0
	for s in lines:
		w = maxf(w, font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, LINE_SIZE).x)
	var h := font.get_height(LINE_SIZE) * lines.size()
	var y0 := 0.5 + h * LINE_PX * 0.5
	l.position = Vector3(0.42 + w * LINE_PX * 0.5, y0, 0.12)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_property(l, "position:y", y0 + 0.06, secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(secs - 0.45)
	tw.chain().tween_callback(l.queue_free)
	talk(minf(1.4, secs * 0.5))

## Parte una frase larga en dos renglones por la pausa más cercana a la mitad (": ", ", ", "… ", ". ", "? ", "! ").
static func two_lines(text: String) -> String:
	if text.length() <= 26 or text.contains("\n"):
		return text
	var mid := text.length() * 0.5
	var best := -1
	for sep in [": ", ", ", "… ", ". ", "? ", "! "]:
		var i := text.find(sep)
		while i >= 0:
			if best < 0 or absf(i - mid) < absf(best - mid):
				best = i
			i = text.find(sep, i + 1)
	if best < 0:
		return text
	return text.substr(0, best + 1) + "\n" + text.substr(best + 2)

func _bez(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t

func _kill_fly() -> void:
	if _fly_tw and _fly_tw.is_valid():
		_fly_tw.kill()
