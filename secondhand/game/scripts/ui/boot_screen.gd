extends Control
class_name BootScreen
## --- BOOT: la pantalla de carga de Secondhand Stars (lo primero que dibuja el juego, en su primer cuadro).
## Es la continuación exacta de la imagen de arranque (assets/ui/boot_splash.png, que el HTML de la versión web muestra
## mientras baja el juego y que Godot muestra en escritorio): el mismo fondo con estrellas (assets/ui/boot_bg.png),
## el logo en el mismo sitio y una barra de progreso donde estaba la del navegador (abajo, al 90 % del alto, la mitad
## del ancho; tools/export_web.sh le da al HTML los mismos colores). Debajo, una línea corta de lo que se está
## preparando. Todo 2D y sin shaders propios: se puede dibujar antes de compilar nada del juego.
## La barra se acerca sola a su objetivo cada cuadro (set_progress): se mueve aunque un paso tarde.
## Al terminar, reveal() lleva el logo volando a su sitio en el título mientras el fondo se desvanece.
## mini = true: solo la barra y la línea (sobre el fundido negro), para cuando el jugador elige algo en el título antes
## de que termine lo que se prepara de fondo (main.gd, _wait_boot).

const BG := Color8(28, 20, 38)              # = application/boot_splash/bg_color (#1c1426)
const LOGO_RECT := Rect2(238, 196, 804, 261) # dónde está el logo en la imagen de 1280x720 (ss_boot_splash.py)
const BAR_FRAME := Color8(90, 70, 84)
const BAR_BACK := Color8(16, 11, 22)
const BAR_FILL := Color(1.0, 0.69, 0.27)    # el ámbar de la interfaz (UIKit.ACCENT)
const TEXT_COL := Color(1.0, 0.82, 0.46, 0.85)
## En la web, la barra del HTML ya llenó hasta aquí mientras bajaba el juego (export_presets.cfg, html/head_include:
## la descarga es el primer 70 %): la del juego sigue desde ahí, sin volver a empezar.
const WEB_START := 0.7

var _bg: ColorRect
var _stars: TextureRect
var _logo: TextureRect
var _bar: Control
var _fill: ColorRect
var _label: Label
var _target := 0.0
var _shown := 0.0
var _t := 0.0
var _spark: Control
var mini := false
var _base := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not mini:
		_build_splash()
		if OS.has_feature("web"):
			_base = WEB_START
	_shown = _base
	_target = _base
	_build_bar()
	_layout()
	resized.connect(_layout)

func _build_splash() -> void:
	_bg = ColorRect.new()
	_bg.color = BG
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	# el fondo con estrellas, ajustado como el HTML («contain»: entero y centrado)
	_stars = TextureRect.new()
	_stars.texture = load("res://assets/ui/boot_bg.png")
	_stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stars)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/ui/logo.png")
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_SCALE
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

func _build_bar() -> void:
	# la barra: 50 % del ancho, el borde de abajo al 90 % del alto (como <progress> en el HTML de Godot)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_left = 0.25
	_bar.anchor_right = 0.75
	_bar.anchor_top = 0.9
	_bar.anchor_bottom = 0.9
	_bar.offset_top = -14
	add_child(_bar)
	var frame := ColorRect.new()
	frame.color = BAR_FRAME
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.add_child(frame)
	var back := ColorRect.new()
	back.color = BAR_BACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.offset_left = 2
	back.offset_top = 2
	back.offset_right = -2
	back.offset_bottom = -2
	_bar.add_child(back)
	_fill = ColorRect.new()
	_fill.color = BAR_FILL
	_fill.position = Vector2(2, 2)
	_bar.add_child(_fill)
	# (solo la fuente mono: las demás las carga el título; el primer cuadro hace lo mínimo)
	_label = Label.new()
	_label.add_theme_font_override("font", load("res://assets/fonts/SecondhandMono-Bold.ttf"))
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", TEXT_COL)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.25
	_label.anchor_right = 0.75
	_label.anchor_top = 0.9
	_label.anchor_bottom = 0.9
	_label.offset_top = 8
	_label.offset_bottom = 30
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# un destello que late al final de la barra (con líneas: así la interfaz ya tiene compilado su programa de líneas
	# cuando el HUD dibuje las suyas)
	_spark = Sparkle.new()
	_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spark.size = Vector2(16, 16)
	_bar.add_child(_spark)

## El logo en el mismo sitio que en la imagen de arranque (que se ve «contain»: escala = la que entra entera).
func _layout() -> void:
	if _logo == null:
		return
	var s := minf(size.x / 1280.0, size.y / 720.0)
	var off := (size - Vector2(1280, 720) * s) * 0.5
	_logo.position = off + LOGO_RECT.position * s
	_logo.size = LOGO_RECT.size * s

## f de 0 a 1 (la barra nunca retrocede); text: lo que se prepara ahora ("" = no cambia).
func set_progress(f: float, text := "") -> void:
	_target = maxf(_target, _base + (1.0 - _base) * clampf(f, 0.0, 1.0))
	if text != "":
		_label.text = text

func _process(delta: float) -> void:
	_t += delta
	# la barra se acerca a su objetivo (rápido, pero se ve moverse) y el texto respira: algo vivo en cada cuadro
	_shown = move_toward(_shown, _target, maxf(delta * 0.9, (_target - _shown) * minf(1.0, delta * 6.0)))
	var w := maxf(0.0, _bar.size.x - 4.0)
	_fill.size = Vector2(w * _shown, maxf(0.0, _bar.size.y - 4.0))
	_label.modulate.a = 0.65 + 0.35 * sin(_t * 3.0)
	if _spark:
		_spark.position = Vector2(2.0 + w * _shown - 8.0, _bar.size.y * 0.5 - 8.0)
		_spark.modulate.a = 0.55 + 0.45 * sin(_t * 7.0)

## Termina: el fondo se desvanece (se ve el título detrás) y el logo vuela hasta to_rect (el del título, en
## coordenadas de esta pantalla). Devuelve cuando terminó; después se puede borrar.
func reveal(to_rect: Rect2, secs := 0.7) -> void:
	_target = 1.0
	resized.disconnect(_layout)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_IN_OUT)
	for c in [_bg, _stars, _bar, _label]:
		if c:
			tw.tween_property(c, "modulate:a", 0.0, secs * 0.8)
	if _logo:
		tw.tween_property(_logo, "position", to_rect.position, secs)
		tw.tween_property(_logo, "size", to_rect.size, secs)
	await tw.finished

## El destello: una cruz de cuatro puntas (draw_line).
class Sparkle extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1.0, 0.93, 0.75)
		draw_line(c - Vector2(7, 0), c + Vector2(7, 0), col, 2.0)
		draw_line(c - Vector2(0, 7), c + Vector2(0, 7), col, 2.0)
		draw_line(c - Vector2(3, 3), c + Vector2(3, 3), col, 1.0)
		draw_line(c - Vector2(3, -3), c + Vector2(3, -3), col, 1.0)
