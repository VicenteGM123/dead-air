extends Control
class_name BenchBubble
## Un globo de diálogo (el de ART: assets/ui/bubble9.png + bubble_tail.png; sin el arte, una caja crema).
## --- SS BENCH (nuevo). Se apunta con point_at(p): la punta de la cola queda en p (la cola va abajo; tail_x = dónde
## cae a lo ancho, 0..1). say(texto, acotación) lo muestra con un saltito; dur > 0 lo esconde solo.

var max_width := 230.0
var tail_x := 0.25
var font_size := 18
var _panel: PanelContainer
var _label: Label
var _cap: Label
var _tail: TextureRect
var _anchor := Vector2.ZERO
var _hide_at := -1.0
var _t := 0.0
var _tw: Tween

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBox = UIKit.nine("bubble9.png", 14, 18)
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color("f4ead2")
		f.border_color = Color("2a2024")
		f.set_border_width_all(3)
		f.set_corner_radius_all(8)
		f.content_margin_left = 14
		f.content_margin_right = 14
		f.content_margin_top = 10
		f.content_margin_bottom = 10
		sb = f
	else:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 11
		sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	_label = UIKit.label("", font_size, BenchKit.INK, UIKit.font_bold)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_label)
	_cap = UIKit.label("", font_size - 3, Color("6a5a50"), UIKit.font_italic)
	_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap.visible = false
	v.add_child(_cap)
	_tail = TextureRect.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tail.texture = BenchKit.tex("res://assets/ui/bubble_tail.png")
	_tail.size = Vector2(24, 18)
	add_child(_tail)

## Muestra el globo. caption: una acotación en cursiva debajo ("*snorts*"). dur > 0: se esconde a los dur s.
func say(text: String, caption := "", dur := 0.0) -> void:
	_label.text = text
	_label.visible = text != ""
	_cap.text = caption
	_cap.visible = caption != ""
	_fit()
	_hide_at = (_t + dur) if dur > 0.0 else -1.0
	if _tw and _tw.is_valid():
		_tw.kill()
	if not visible or modulate.a < 0.99:
		visible = true
		modulate.a = 0.0
		scale = Vector2(0.9, 0.9)
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "modulate:a", 1.0, 0.12)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_place()

func hide_now() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	visible = false
	modulate.a = 1.0
	scale = Vector2.ONE
	_hide_at = -1.0

## La punta de la cola en p (coordenadas del padre).
func point_at(p: Vector2) -> void:
	_anchor = p
	_place()

func text() -> String:
	return _label.text

func _fit() -> void:
	# ancho: el del texto en una línea, sin pasar de max_width (después el contenedor calcula el alto)
	var f: Font = UIKit.font_bold
	var w := f.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if _cap.visible:
		w = maxf(w, UIKit.font_italic.get_string_size(_cap.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3).x)
	var inner := clampf(ceilf(w) + 2.0, 40.0, max_width - 32.0)
	_label.custom_minimum_size = Vector2(inner, 0)
	_cap.custom_minimum_size = Vector2(inner, 0)
	_panel.size = Vector2.ZERO
	_panel.reset_size()

func _place() -> void:
	var ps := _panel.get_combined_minimum_size()
	_panel.size = ps
	size = ps + Vector2(0, 15)
	_panel.position = Vector2.ZERO
	var tx := roundf(clampf(ps.x * tail_x - 12.0, 10.0, maxf(10.0, ps.x - 34.0)))
	_tail.position = Vector2(tx, ps.y - 3.0)
	position = (_anchor - Vector2(tx + 12.0, ps.y + 15.0)).round()
	pivot_offset = Vector2(tx + 12.0, ps.y + 15.0)

func _process(delta: float) -> void:
	_t += delta
	if visible:
		_place()
		if _hide_at > 0.0 and _t >= _hide_at:
			_hide_at = -1.0
			if _tw and _tw.is_valid():
				_tw.kill()
			_tw = create_tween()
			_tw.tween_property(self, "modulate:a", 0.0, 0.2)
			_tw.tween_callback(func(): visible = false)
