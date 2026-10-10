extends Control
## Menu screens: title, pause, options and controls. Screens stack (options over pause, controls over the
## title...); keyboard, gamepad and mouse all work. Fades are short and quiet.

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

var ui: Node = null
var _stack: Array = []
var _title: Control
var _title_text: W.TrackedText
var _title_items: Array = []
var _pause: Control
var _pause_status: Label
var _options: Control
var _controls: Control


## A full-screen backdrop drawn in code: "dim" (flat veil + vignette) or "left" (title gradient).
class Backdrop extends Control:
	var style := "dim"
	var tint := Color(0.075, 0.052, 0.042)
	var amount := 0.5
	var band := 0.0

	func _init(st: String, a: float = 0.5, t: Color = Color(0.075, 0.052, 0.042), band_w: float = 0.0) -> void:
		style = st
		amount = a
		tint = t
		band = band_w
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var clear := Color(tint, 0.0)
		if style == "left":
			var a := Color(tint, amount)
			var mid := Color(tint, amount * 0.55)
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.28, 0), Vector2(w * 0.28, h), Vector2(0, h)]), PackedColorArray([a, mid, mid, a]))
			draw_polygon(PackedVector2Array([Vector2(w * 0.28, 0), Vector2(w * 0.6, 0), Vector2(w * 0.6, h), Vector2(w * 0.28, h)]), PackedColorArray([mid, clear, clear, mid]))
			draw_polygon(PackedVector2Array([Vector2(0, h * 0.74), Vector2(w, h * 0.74), Vector2(w, h), Vector2(0, h)]), PackedColorArray([clear, clear, Color(tint, amount * 0.45), Color(tint, amount * 0.65)]))
			return
		draw_rect(Rect2(0, 0, w, h), Color(tint, amount))
		var e := Color(tint, minf(0.85, amount * 0.9))
		var bands := [[Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.22), Vector2(0, h * 0.22), e, e, clear, clear],
			[Vector2(0, h * 0.78), Vector2(w, h * 0.78), Vector2(w, h), Vector2(0, h), clear, clear, e, e],
			[Vector2(0, 0), Vector2(w * 0.18, 0), Vector2(w * 0.18, h), Vector2(0, h), e, clear, clear, e],
			[Vector2(w * 0.82, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.82, h), clear, e, e, clear]]
		for b in bands:
			draw_polygon(PackedVector2Array([b[0], b[1], b[2], b[3]]), PackedColorArray([b[4], b[5], b[6], b[7]]))
		if band > 0.0:
			var bw := minf(band, w * 0.9)
			S.draw_soft_band(self, Rect2((w - bw) * 0.5, -10.0, bw, h + 20.0), Color(tint, 0.36), 0.32, 0.12)


## "[Esc] Volver" under a screen; fades out (keeping its space) when the device in use has no such key.
class FooterHint extends HBoxContainer:
	var action := ""
	var _rev := -1

	func _process(_d: float) -> void:
		if _rev != G.revision:
			_rev = G.revision
			modulate.a = 0.0 if G.caps_for(action).is_empty() else 1.0


## The twelve labours as twelve small marks under the title; the first is lit (this is the first island).
class Labours extends Control:
	var done := 0
	var current := 1

	func _init() -> void:
		custom_minimum_size = Vector2(12 * 30.0, 28.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := S.font(S.CINZEL_BOLD)
		for i in 12:
			var c := Vector2(10.0 + i * 30.0, size.y * 0.4)
			var lit := i + 1 == current
			var col := S.CLAY_LIGHT if lit else Color(S.IVORY, 0.32)
			if i < done:
				col = S.GOLD
			S.draw_diamond(self, c, 8.0 if lit else 5.5, Color(S.INK, 0.5))
			S.draw_diamond(self, c, 6.5 if lit else 4.2, col)
			if lit:
				var t := "I"
				var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(f, c + Vector2(-tw * 0.5, 21.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(S.CLAY_LIGHT, 0.95))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refit)


## Small windows: each screen's content block shrinks as one piece until it fits.
func _fit_screen(scr: Control) -> void:
	if scr == null or not scr.has_meta("fit") or not scr.has_meta("fit_holder"):
		return
	var c: Control = scr.get_meta("fit")
	var holder: Control = scr.get_meta("fit_holder")
	if not is_instance_valid(c) or not is_instance_valid(holder):
		return
	var ms := c.get_combined_minimum_size()
	var avail := size - Vector2(40.0, 32.0)
	var f := 1.0
	if ms.x > 1.0 and ms.y > 1.0:
		f = minf(1.0, minf(avail.x / ms.x, avail.y / ms.y))
	holder.pivot_offset = size * 0.5
	holder.scale = Vector2(f, f)


func _refit() -> void:
	for scr in _stack:
		_fit_screen(scr)


func is_open() -> bool:
	return not _stack.is_empty()


func is_title_open() -> bool:
	return _title != null and _stack.has(_title)


func is_pause_top() -> bool:
	return _pause != null and not _stack.is_empty() and _stack.back() == _pause


func is_pause_open() -> bool:
	return _pause != null and _stack.has(_pause)


func depth() -> int:
	return _stack.size()


func _screen(name_s: String) -> Control:
	var c := Control.new()
	c.name = name_s
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	c.modulate.a = 0.0
	add_child(c)
	return c


func _fade(c: Control, on: bool, dur: float = 0.22) -> void:
	if c == null:
		return
	if c.has_meta("tw"):
		var old: Tween = c.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var tw := S.tween(c)
	c.set_meta("tw", tw)
	if on:
		c.visible = true
		tw.tween_property(c, "modulate:a", 1.0, dur)
	else:
		tw.tween_property(c, "modulate:a", 0.0, dur * 0.8)
		tw.tween_callback(func() -> void: c.visible = false)


func _push(c: Control) -> void:
	if not _stack.is_empty():
		_fade(_stack.back(), false, 0.18)
	_stack.append(c)
	_fit_screen(c)
	_fade(c, true)
	_focus_first(c)


## Back one level. Returns false when there is nothing to go back to (the caller decides what that means).
func back() -> bool:
	if _stack.size() <= 1:
		return false
	var c: Control = _stack.pop_back()
	_fade(c, false, 0.18)
	var below: Control = _stack.back()
	_fade(below, true)
	_focus_first(below)
	S.sfx("ui_back")
	return true


func close_all() -> void:
	for c in _stack:
		_fade(c, false, 0.2)
	_stack.clear()
	if get_viewport():
		get_viewport().gui_release_focus()


## Focuses the first item of the screen on top (keys pressed when nothing has focus).
func focus_top() -> void:
	if not _stack.is_empty():
		_focus_first(_stack.back())


func _focus_first(c: Control) -> void:
	var f: Control = c.get_meta("focus") if c.has_meta("focus") else null
	if f and is_instance_valid(f):
		S.focus_quiet.call_deferred(f)


func _chain(items: Array) -> void:
	for i in items.size():
		var a: Control = items[i]
		var b: Control = items[(i + 1) % items.size()]
		a.focus_neighbor_bottom = a.get_path_to(b)
		b.focus_neighbor_top = b.get_path_to(a)
		a.focus_next = a.get_path_to(b)
		b.focus_previous = b.get_path_to(a)


func _footer(parent: Control, action: String, text: String) -> Control:
	var h := FooterHint.new()
	h.action = action
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	h.add_child(G.new().setup(action, 22.0, "", Color(S.IVORY, 0.8)))
	h.add_child(S.label(text, S.ITALIC, 17, Color(S.IVORY, 0.75), 0, 3))
	parent.add_child(h)
	return h


func _centered_column(parent: Control, sep: int = 10) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cc)
	parent.set_meta("fit_holder", cc)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", sep)
	cc.add_child(col)
	return col


func _space(parent: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


func _center(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


# --- title -------------------------------------------------------------------------------------------------

func open_title() -> void:
	if _title == null:
		_build_title()
	close_all()
	_stack.append(_title)
	_title.visible = true
	_title.modulate.a = 1.0
	_intro_title()
	_focus_first(_title)


func _build_title() -> void:
	_title = _screen("Title")
	_title.add_child(Backdrop.new("left", 0.74))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ml := clampf(size.x * 0.075, 36.0, 120.0)
	margin.add_theme_constant_override("margin_left", int(ml))
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 44)
	_title.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)
	var px := int(clampf(minf(size.x * 0.085, size.y * 0.17), 70.0, 128.0))
	_title_text = W.TrackedText.new("DOCE", S.CINZEL_BOLD, px, px * 0.3, S.IVORY, 0)
	_title_text.outline = 9
	col.add_child(_title_text)
	var orn := W.Ornament.new("band", px * 3.1, Color(S.CLAY_LIGHT, 0.95))
	orn.custom_minimum_size.y = 26.0
	orn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(orn)
	var sub := S.label("Los trabajos de Heracles", S.ITALIC, int(px * 0.3), Color("F3DDB5"), 0, 5)
	sub.custom_minimum_size = Vector2(0, px * 0.42)
	col.add_child(sub)
	var labours := Labours.new()
	labours.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(labours)
	_space(col, clampf(size.y * 0.06, 16.0, 44.0))
	var items: Array = []
	var start := W.Btn.new("Comenzar", 26, true)
	start.activated.connect(_on_start)
	items.append(start)
	var ctl := W.Btn.new("Controles", 26, true)
	ctl.activated.connect(open_controls)
	items.append(ctl)
	var opt := W.Btn.new("Opciones", 26, true)
	opt.activated.connect(open_options)
	items.append(opt)
	if not OS.has_feature("web"):
		var quit := W.Btn.new("Salir", 26, true)
		quit.activated.connect(func() -> void: get_tree().quit())
		items.append(quit)
	for b in items:
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(b)
	_chain(items)
	_title_items = [_title_text, orn, sub, labours] + items
	_title.set_meta("focus", start)
	var credits := S.label("Hecho con Godot Engine  ·  Tipografías Cinzel y EB Garamond (SIL OFL)  ·  Todo generado con código", S.GARAMOND, 14, Color(S.IVORY, 0.5), 0, 3)
	credits.anchor_top = 1.0
	credits.anchor_bottom = 1.0
	credits.offset_left = ml
	credits.offset_top = -34.0
	_title.add_child(credits)


func _intro_title() -> void:
	_title_text.reveal = 0.0
	var px := float(_title_text.px)
	var tw := S.tween(_title_text)
	tw.set_parallel(true)
	tw.tween_method(_title_text.set_reveal, 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_method(_title_text.set_tracking, px * 0.62, px * 0.3, 2.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(1, _title_items.size()):
		var c: Control = _title_items[i]
		c.modulate.a = 0.0
		var t2 := S.tween(c)
		t2.tween_interval(0.5 + 0.12 * i)
		t2.tween_property(c, "modulate:a", 1.0, 0.5)


func _on_start() -> void:
	if ui:
		ui.call("begin_game")


# --- pause -------------------------------------------------------------------------------------------------

func open_pause() -> void:
	if _pause == null:
		_build_pause()
	close_all()
	_update_pause_status()
	_push(_pause)


func _build_pause() -> void:
	_pause = _screen("Pause")
	_pause.add_child(Backdrop.new("dim", 0.4, Color(0.075, 0.052, 0.042), 760.0))
	var col := _centered_column(_pause, 8)
	var t := W.TrackedText.new("PAUSA", S.CINZEL, 48, 18.0, S.IVORY, 1)
	col.add_child(_center(t))
	_pause_status = S.label("", S.ITALIC, 20, Color(S.IVORY, 0.82), 0, 4)
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_pause_status)
	col.add_child(_center(W.Ornament.new("meander", 300.0, Color(S.CLAY_LIGHT, 0.85))))
	_space(col, 12)
	var items: Array = []
	var cont := W.Btn.new("Continuar", 25)
	cont.activated.connect(func() -> void:
		if ui:
			ui.call("resume"))
	items.append(cont)
	var opt := W.Btn.new("Opciones", 25)
	opt.activated.connect(open_options)
	items.append(opt)
	var ctl := W.Btn.new("Controles", 25)
	ctl.activated.connect(open_controls)
	items.append(ctl)
	var tt := W.Btn.new("Volver al título", 25, false, "Volver al título · ¿seguro?")
	tt.activated.connect(func() -> void:
		if ui:
			ui.call("to_title"))
	items.append(tt)
	for b in items:
		col.add_child(_center(b))
	_chain(items)
	_space(col, 10)
	_footer(col, "back", "Continuar")
	_pause.set_meta("focus", cont)
	_pause.set_meta("fit", col)


func _update_pause_status() -> void:
	var where := "Isla de Nemea  ·  Trabajo I"
	var h = Game.hero
	if h != null and is_instance_valid(h) and "outfit" in h and String(h.get("outfit")) == "lion":
		where = "Isla de Nemea  ·  Trabajo I completado"
	_pause_status.text = where


# --- options -----------------------------------------------------------------------------------------------

func open_options() -> void:
	if _options == null:
		_build_options()
	_push(_options)


func _panel_screen(name_s: String, title: String) -> Array:
	var scr := _screen(name_s)
	scr.add_child(Backdrop.new("dim", 0.32))
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(cc)
	scr.set_meta("fit_holder", cc)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := S.panel(0.78, 6, Color(S.CLAY, 0.6), 30.0)
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	pc.add_child(col)
	scr.set_meta("fit", pc)
	var t := W.TrackedText.new(title, S.CINZEL, 34, 13.0, S.IVORY, 1)
	col.add_child(_center(t))
	col.add_child(_center(W.Ornament.new("meander", 340.0, Color(S.CLAY_LIGHT, 0.85))))
	_space(col, 6)
	return [scr, col]


static func _opt(k: String, default: Variant) -> Variant:
	var v = Settings.get_v(k)
	return default if v == null else v


func _build_options() -> void:
	var made := _panel_screen("Options", "OPCIONES")
	_options = made[0]
	var col: VBoxContainer = made[1]
	var music := W.OptionRow.new("Música", "slider")
	music.value = float(_opt("music", 0.7))
	music.changed.connect(func(v: Variant) -> void: Sfx.set_volume("Music", float(v)))
	music.committed.connect(func(v: Variant) -> void: Settings.set_v("music", float(v)))
	var sfx := W.OptionRow.new("Efectos", "slider")
	sfx.value = float(_opt("sfx", 0.85))
	sfx.changed.connect(func(v: Variant) -> void:
		Sfx.set_volume("SFX", float(v))
		Sfx.set_volume("Amb", float(v)))
	sfx.committed.connect(func(v: Variant) -> void:
		Settings.set_v("sfx", float(v))
		S.sfx("ui_select"))
	# mouse sensitivity: the slider's 0..1 maps to a 0.25x..2.5x multiplier (0.5 on the slider = 1x)
	var sens := W.OptionRow.new("Sensibilidad del ratón", "slider")
	sens.value = clampf(_sens_to_slider(float(_opt("mouse_sens", 1.0))), 0.0, 1.0)
	sens.committed.connect(func(v: Variant) -> void: Settings.set_v("mouse_sens", _slider_to_sens(float(v))))
	var inv := W.OptionRow.new("Invertir eje Y", "choice", ["No", "Sí"])
	inv.index = 1 if bool(_opt("invert_y", false)) else 0
	inv.committed.connect(func(v: Variant) -> void: Settings.set_v("invert_y", int(v) == 1))
	var shake := W.OptionRow.new("Temblor de cámara", "choice", ["Sí", "No"])
	shake.index = 0 if bool(_opt("shake", true)) else 1
	shake.committed.connect(func(v: Variant) -> void: Settings.set_v("shake", int(v) == 0))
	var quality := W.OptionRow.new("Calidad", "choice", ["Baja", "Media", "Alta"])
	quality.index = clampi(int(_opt("quality", 2)), 0, 2)
	quality.committed.connect(func(v: Variant) -> void:
		Settings.set_v("quality", int(v))
		Settings.apply_quality(get_viewport()))
	var back_b := W.Btn.new("Volver", 23)
	back_b.activated.connect(back)
	var items: Array = [music, sfx, sens, inv, shake, quality]
	for it in items:
		col.add_child(it)
	_space(col, 8)
	col.add_child(_center(back_b))
	items.append(back_b)
	_chain(items)
	_footer(col, "back", "Volver")
	_options.set_meta("focus", music)


static func _slider_to_sens(v: float) -> float:
	# geometric on both halves, so each step feels the same: 0 -> 0.25x, 0.5 -> 1x, 1 -> 2.5x
	if v <= 0.5:
		return snappedf(0.25 * pow(4.0, v * 2.0), 0.01)
	return snappedf(pow(2.5, (v - 0.5) * 2.0), 0.01)


static func _sens_to_slider(s: float) -> float:
	if s <= 1.0:
		return clampf(log(maxf(s, 0.25) / 0.25) / (2.0 * log(4.0)), 0.0, 0.5)
	return clampf(0.5 + log(s) / log(2.5) * 0.5, 0.5, 1.0)


# --- controls ----------------------------------------------------------------------------------------------

func open_controls() -> void:
	if _controls == null:
		_build_controls()
	_push(_controls)


func _build_controls() -> void:
	var made := _panel_screen("Controls", "CONTROLES")
	_controls = made[0]
	var col: VBoxContainer = made[1]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 7)
	col.add_child(_center(grid))
	grid.add_child(Control.new())
	grid.add_child(S.label("TECLADO Y RATÓN", S.CINZEL, 14, S.CLAY_LIGHT, 3, 3))
	grid.add_child(S.label("MANDO", S.CINZEL, 14, S.CLAY_LIGHT, 3, 3))
	var rows := [
		["move", "Moverse", null, null],
		["camera", "Mirar", null, null],
		["sprint", "Correr", [["word", "mantener"], ["key", "Shift"]], [["pill", "L3"], ["word", "o mantener"], ["pad", "B"]]],
		["jump", "Saltar", null, null],
		["dodge", "Voltereta", [["word", "pulsar"], ["key", "Shift"]], null],
		["attack", "Golpe (combo de tres)", null, null],
		["heavy", "Golpe fuerte", null, null],
		["guard", "Escudo · parada a tiempo", null, null],
		["chain", "Lanza con cadena", [["key", "Q"]], null],
		["lock", "Fijar objetivo", [["key", "Tab"], ["icon", "mouse_m"]], null],
		["interact", "Usar · agarrar · acariciar", null, null],
		["pause", "Pausa", null, null],
	]
	for r in rows:
		grid.add_child(S.label(r[1], S.GARAMOND, 19, S.IVORY, 0, 3))
		var kb: Control = G.new()
		if r[2] != null:
			kb.call("setup_caps", r[2], 25.0)
		else:
			kb.call("setup", r[0], 25.0, "kb")
		grid.add_child(kb)
		var pad: Control = G.new()
		if r[3] != null:
			pad.call("setup_caps", r[3], 25.0)
		else:
			pad.call("setup", r[0], 25.0, "pad")
		grid.add_child(pad)
	_space(col, 4)
	col.add_child(_center(W.Ornament.new("rule", 320.0, Color(S.CLAY_LIGHT, 0.6))))
	var note := S.label("La lanza se clava en lo que miras: lo pequeño viene a ti; lo grande o lo fijo te lleva a ti hacia ello.", S.ITALIC, 17, Color(S.IVORY, 0.82), 0, 3)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size = Vector2(600, 0)
	col.add_child(_center(note))
	_space(col, 4)
	var back_b := W.Btn.new("Volver", 23)
	back_b.activated.connect(back)
	col.add_child(_center(back_b))
	_footer(col, "back", "Volver")
	_controls.set_meta("focus", back_b)
