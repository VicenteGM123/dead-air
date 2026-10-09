extends CanvasLayer
## PLACEHOLDER UI until the UI stream delivers scripts/ui/ui.gd (main.gd then loads that instead): the title text
## ("DOCE", "Pulsa para empezar") over the orbiting island, and "Pausa" while paused. No HUD.
## Hooks main.gd calls (the real UI implements the same): show_title(), show_play(), show_pause(paused).

const S := preload("res://scripts/ui/style.gd")

var _root: Control
var _title: Label
var _prompt: Label
var _pause: Label
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_title = S.label("DOCE", S.CINZEL, 120, S.IVORY, 24, 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.offset_left = 0.0
	_title.offset_right = 0.0
	_title.offset_top = 150.0
	_root.add_child(_title)
	_prompt = S.label("Pulsa para empezar", S.ITALIC, 36, S.IVORY, 0, 6)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -150.0
	_prompt.offset_bottom = -100.0
	_root.add_child(_prompt)
	_pause = S.label("Pausa", S.CINZEL, 54, S.IVORY, 12, 5)
	_pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	_title.visible = false
	_prompt.visible = false


func show_title() -> void:
	_title.visible = true
	_prompt.visible = true
	_title.modulate.a = 0.0
	_prompt.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.6).set_delay(0.3)
	tw.tween_property(_prompt, "modulate:a", 1.0, 0.8)


func show_play() -> void:
	if not _title.visible:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_title, "modulate:a", 0.0, 0.6)
	tw.tween_property(_prompt, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(func() -> void:
		_title.visible = false
		_prompt.visible = false)


func show_pause(paused: bool) -> void:
	_pause.visible = paused


func _process(delta: float) -> void:
	_t += delta
	if _prompt.visible and _prompt.modulate.a > 0.99:
		_prompt.self_modulate.a = 0.65 + 0.35 * sin(_t * 2.4)
