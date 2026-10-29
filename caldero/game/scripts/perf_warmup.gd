extends Control
class_name PerfWarmup
## --- R6 PERF: precalentar los shaders 2D. En el renderizador Compatibility (la web), cada clase de dibujo 2D usa una
## variante del shader de lienzo que se compila la primera vez que se dibuja: las líneas gruesas y los rectángulos de
## borde del mapa del viaje, las líneas y arcos suavizados del grimorio, los polígonos... Si esa primera vez es a la
## vista, la pantalla se traba un momento (el mapa del viaje al empezar un evento, el grimorio al abrirlo). Dibuja una
## vez cada clase de trazo que usa el juego, en pequeño, y se borra solo después de dos cuadros. No se ve nunca.
## --- BOOT: antes main.gd lo ponía con la pantalla en negro al arrancar (_warm_places); ahora lo pone BootWarm
## (scripts/boot_warm.gd) después del título, en el lienzo de su SubViewport (no en la pantalla).

var _frames := 0
var _tex: Texture2D
var _sb: StyleBoxTexture

## Materiales de partículas que se guardan toda la partida (keep_particles).
static var _kept: Array = []

## Las partículas que se crean y se borran a cada rato (el humo y los destellos del caldero al embotellar, la
## salpicadura, el confeti de los eventos, los destellos de nivel, los corazones de Miga) estrenan cada vez materiales
## nuevos. Godot comparte el shader entre los materiales con las mismas opciones, pero lo borra cuando se borra el
## último: la vez siguiente lo vuelve a compilar. En escritorio no se nota (caché de programas), en WebGL sí: cada poción
## embotellada y cada aplauso enlazaban 2-4 programas otra vez. Guardar una vez sus materiales (los de la primera vez,
## en el negro del arranque) deja vivo el shader de cada combinación: después ya no se compila nada.
static func keep_particles(p: GPUParticles3D) -> void:
	if p == null:
		return
	var mats: Array = [p.process_material]
	if p.draw_pass_1:
		for i in p.draw_pass_1.get_surface_count():
			mats.append(p.draw_pass_1.surface_get_material(i))
	for m in mats:
		if m != null and not _kept.has(m):
			_kept.append(m)

## Lo agrega (en una capa por debajo del fundido) y se quita solo.
static func run(parent: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "PerfWarmup"
	layer.layer = 19
	parent.add_child(layer)
	var w := PerfWarmup.new()
	w.position = Vector2(8, 8)
	w.size = Vector2(160, 160)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(w)

func _ready() -> void:
	_tex = load("res://icon.png")
	# los paneles de papel y madera (StyleBoxTexture / NinePatchRect) usan otra variante: la primera nota de consejo o
	# el banco la compilaban a la vista
	_sb = StyleBoxTexture.new()
	_sb.texture = _tex
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_sb.set_texture_margin(side, 8)

func _process(_d: float) -> void:
	_frames += 1
	queue_redraw()
	if _frames > 2:
		get_parent().queue_free()

func _draw() -> void:
	var c := Color(0.9, 0.8, 0.6, 0.9)
	# trazos sin suavizar (el mapa del viaje, los paneles)
	draw_line(Vector2(0, 0), Vector2(40, 10), c, 5.0)
	draw_line(Vector2(0, 4), Vector2(40, 14), c, 1.0)
	draw_rect(Rect2(2, 20, 30, 20), c, false, 3.0)
	draw_rect(Rect2(36, 20, 30, 20), c, false, 1.0)
	draw_rect(Rect2(70, 20, 30, 20), c)
	draw_dashed_line(Vector2(0, 46), Vector2(60, 46), c, 2.0, 4.0)
	draw_polyline(PackedVector2Array([Vector2(0, 50), Vector2(20, 60), Vector2(40, 50)]), c, 4.0)
	draw_arc(Vector2(80, 60), 10.0, 0.0, TAU, 16, c, 3.0)
	draw_circle(Vector2(110, 60), 8.0, c)
	draw_colored_polygon(PackedVector2Array([Vector2(120, 0), Vector2(150, 0), Vector2(135, 20)]), c)
	# trazos suavizados (el grimorio y la runa)
	draw_line(Vector2(0, 70), Vector2(40, 90), c, 2.0, true)
	draw_line(Vector2(0, 76), Vector2(40, 96), c, 6.0, true)
	draw_polyline(PackedVector2Array([Vector2(50, 70), Vector2(70, 90), Vector2(90, 70)]), c, 5.0, true)
	draw_arc(Vector2(120, 90), 12.0, 0.0, TAU, 24, c, 3.0, true)
	draw_arc(Vector2(120, 90), 6.0, 0.0, PI, 8, c, 1.0, true)
	# texturas (normal, volteada y por región) y texto
	if _tex:
		draw_texture_rect(_tex, Rect2(0, 110, 24, 24), false)
		draw_texture_rect(_tex, Rect2(52, 110, -24, 24), false)
		draw_texture_rect_region(_tex, Rect2(56, 110, 24, 24), Rect2(0, 0, 32, 32))
		draw_texture_rect(_tex, Rect2(84, 110, 24, 24), true)
		draw_style_box(_sb, Rect2(112, 104, 44, 36))
	var f := get_theme_default_font()
	if f:
		draw_string(f, Vector2(0, 150), "Ag", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
