extends CanvasLayer
class_name BootScreen
## --- BOOT: la pantalla de carga. Es la misma imagen que la de arranque (application/boot_splash/image, la que la página
## web muestra mientras baja el juego) en el mismo sitio, con la barra de progreso donde la dibuja la página (al 90 % del
## alto, la mitad del ancho): de la página a esta pantalla y de esta al título no hay salto. Se dibuja casi sin shaders
## (un rectángulo, una imagen y la barra) y queda encima de todo (capa 100) hasta que el título está listo.
## Este script es chico a propósito y no usa UIKit ni nada grande: el primer cuadro del juego es solo esto.
##   BootScreen.open(nodo)        la crea (en la raíz del árbol, sobrevive al cambio de escena)
##   BootScreen.progress(0.5)     la barra va hacia ese valor (0..1; nunca para atrás)
##   BootScreen.close()           se funde y se borra

static var current: BootScreen

const BG := Color(0.05, 0.04, 0.09)        # = application/boot_splash/bg_color (project.godot)
const IMAGE := "res://assets/ui/boot_splash.png"
const BAR_W := 0.5                         # ancho de la barra / ancho de la pantalla (como la página: width 50 %)
const BAR_BOTTOM := 0.9                    # su borde de abajo, en fracción del alto (como la página: bottom 10 %)
const BAR_H := 0.0105                      # su alto / alto de la pantalla (como la página: 1.05vh)
const WEB_START := 0.42                    # la página llena la barra hasta aquí mientras baja el juego (shell.html)
const GOLD := Color(1.0, 0.86, 0.5)

var _root: Control
var _bar: Control
var _shown := 0.0     # lo que dibuja la barra
var _target := 0.0    # a dónde va
var _closing := false

## Crea la pantalla (si no está) como hija de la raíz. Llamable desde un _ready: se añade al final del cuadro, antes
## de dibujarlo.
static func open(from: Node) -> BootScreen:
	if is_instance_valid(current):
		return current
	var s := BootScreen.new()
	current = s
	from.get_tree().root.add_child.call_deferred(s)
	return s

static func progress(f: float) -> void:
	if is_instance_valid(current):
		current._target = maxf(current._target, clampf(f, 0.0, 1.0))

static func close(fade := 0.4) -> void:
	if is_instance_valid(current):
		current._close(fade)
	current = null

func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "BootScreen"
	_shown = WEB_START if OS.has_feature("web") else 0.0
	_target = _shown
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # mientras carga, los clics no llegan a lo que está debajo
	_root.add_child(bg)
	var pic := TextureRect.new()
	pic.texture = load(IMAGE)
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # como la página (la imagen escalada con suavizado)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pic)
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)

func _process(delta: float) -> void:
	# la barra se acerca a su valor con suavidad (los pasos del arranque no duran lo mismo) y nunca se para del todo
	var old := _shown
	_shown = move_toward(_shown, _target, maxf(0.02, (_target - _shown) * 6.0) * minf(delta, 0.1))
	if _shown != old:
		_bar.queue_redraw()

func _draw_bar() -> void:
	var vs := _bar.size
	var h := maxf(4.0, roundf(vs.y * BAR_H))
	var w := roundf(vs.x * BAR_W)
	var r := Rect2(roundf((vs.x - w) / 2.0), roundf(vs.y * BAR_BOTTOM - h), w, h)
	_bar.draw_rect(r.grow(2.0), Color(GOLD, 0.28), false, 1.0)      # el borde fino dorado
	_bar.draw_rect(r, Color(1, 1, 1, 0.07))                           # el riel
	if _shown > 0.0:
		_bar.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * _shown), r.size.y)), GOLD)

func _close(fade: float) -> void:
	if _closing:
		return
	_closing = true
	_target = 1.0
	_shown = 1.0
	_bar.queue_redraw()
	if fade <= 0.0 or not is_inside_tree():
		queue_free()
		return
	(_root.get_child(0) as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE   # el título ya responde
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, fade)
	tw.tween_callback(queue_free)
