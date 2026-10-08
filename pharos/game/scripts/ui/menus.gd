extends Control
## Menu screens: title, pause, options, controls and the end of the island. Screens stack (options over pause,
## controls over title…); keyboard, gamepad, mouse and touch all work. Fades are short and quiet.

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

var ui: Node = null
var _stack: Array = []
var _title: Control
var _title_col: VBoxContainer
var _title_text: W.TrackedText
var _title_items: Array = []
var _pause: Control
var _pause_status: Label
var _options: Control
var _controls: Control
var _end: Control
var _end_built_for := -1


## A full-screen backdrop drawn in code: "dim" (flat veil + vignette), "left" (title gradient) or "end".
class Backdrop extends Control:
	var style := "dim"
	var tint := Color(0.045, 0.038, 0.085)
	var amount := 0.5
	var band := 0.0 # width of a soft dark column in the middle (menus that float without a panel)

	func _init(st: String, a: float = 0.5, t: Color = Color(0.045, 0.038, 0.085), band_w: float = 0.0) -> void:
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
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.3, 0), Vector2(w * 0.3, h), Vector2(0, h)]), PackedColorArray([a, mid, mid, a]))
			draw_polygon(PackedVector2Array([Vector2(w * 0.3, 0), Vector2(w * 0.62, 0), Vector2(w * 0.62, h), Vector2(w * 0.3, h)]), PackedColorArray([mid, clear, clear, mid]))
			draw_polygon(PackedVector2Array([Vector2(0, h * 0.72), Vector2(w, h * 0.72), Vector2(w, h), Vector2(0, h)]), PackedColorArray([clear, clear, Color(tint, amount * 0.5), Color(tint, amount * 0.7)]))
			return
		draw_rect(Rect2(0, 0, w, h), Color(tint, amount))
		# Vignette: darker corners, a lighter centre.
		var e := Color(tint, minf(0.85, amount * 0.9))
		var bands := [[Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.22), Vector2(0, h * 0.22), e, e, clear, clear],
			[Vector2(0, h * 0.78), Vector2(w, h * 0.78), Vector2(w, h), Vector2(0, h), clear, clear, e, e],
			[Vector2(0, 0), Vector2(w * 0.18, 0), Vector2(w * 0.18, h), Vector2(0, h), e, clear, clear, e],
			[Vector2(w * 0.82, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.82, h), clear, e, e, clear]]
		for b in bands:
			draw_polygon(PackedVector2Array([b[0], b[1], b[2], b[3]]), PackedColorArray([b[4], b[5], b[6], b[7]]))
		if band > 0.0:
			var bw := minf(band, w * 0.9)
			S.draw_soft_band(self, Rect2((w - bw) * 0.5, -10.0, bw, h + 20.0), Color(tint, 0.34), 0.32, 0.12)


## "[Esc] Volver" under a screen; fades out (keeping its space) when the device in use has no such key.
class FooterHint extends HBoxContainer:
	var action := ""
	var _rev := -1

	func _process(_d: float) -> void:
		if _rev != G.revision:
			_rev = G.revision
			modulate.a = 0.0 if G.caps_for(action).is_empty() else 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refit)


## Small screens (phones in landscape): each screen's content block shrinks as one piece until it fits. The
## scale goes on the full-screen CenterContainer that holds the block (containers reset their children's scale).
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


func top() -> Control:
	return _stack.back() if not _stack.is_empty() else null


func is_pause_open() -> bool:
	return _stack.has(_pause) and _pause != null


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
		var below: Control = _stack.back()
		_fade(below, false, 0.18)
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
	get_viewport().gui_release_focus()


func _focus_first(c: Control) -> void:
	var f: Control = c.get_meta("focus") if c.has_meta("focus") else null
	if f and is_instance_valid(f):
		S.focus_quiet.call_deferred(f)


## Wires up/down focus (with wrap-around) through a vertical list of controls.
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
	_title.add_child(Backdrop.new("left", 0.62))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ml := clampf(size.x * 0.075, 36.0, 120.0)
	margin.add_theme_constant_override("margin_left", int(ml))
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 44)
	_title.add_child(margin)
	_title_col = VBoxContainer.new()
	_title_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_col.add_theme_constant_override("separation", 6)
	margin.add_child(_title_col)
	var px := int(clampf(minf(size.x * 0.064, size.y * 0.13), 54.0, 92.0))
	_title_text = W.TrackedText.new("PHAROS", S.CINZEL, px, px * 0.26, S.IVORY, 0)
	_title_col.add_child(_title_text)
	var sub := S.label("La última luz", S.ITALIC, int(px * 0.36), Color("F0D9A8"), 0, 5)
	sub.custom_minimum_size = Vector2(0, px * 0.42)
	_title_col.add_child(sub)
	var orn := W.Ornament.new("meander", px * 3.6, Color(S.GOLD, 0.6))
	orn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_col.add_child(orn)
	_space(_title_col, clampf(size.y * 0.05, 14.0, 40.0))
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
		_title_col.add_child(b)
	_chain(items)
	_title_items = [_title_text, sub, orn] + items
	_title.set_meta("focus", start)
	var credits := S.label("Hecho con Godot Engine  ·  Tipografías Cinzel y EB Garamond (SIL OFL)", S.GARAMOND, 14, Color(S.IVORY, 0.5), 0, 3)
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
	tw.tween_method(_title_text.set_tracking, px * 0.55, px * 0.26, 2.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	_pause.add_child(Backdrop.new("dim", 0.38, Color(0.045, 0.038, 0.085), 760.0))
	var col := _centered_column(_pause, 8)
	var t := W.TrackedText.new("PAUSA", S.CINZEL, 48, 18.0, S.GOLD, 1)
	col.add_child(_center(t))
	_pause_status = S.label("", S.ITALIC, 20, Color(S.IVORY, 0.82), 0, 4)
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_pause_status)
	col.add_child(_center(W.Ornament.new("rule", 300.0)))
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
	var rs := W.Btn.new("Reiniciar", 25, false, "Reiniciar · ¿seguro?")
	rs.activated.connect(func() -> void:
		if ui:
			ui.call("restart", true))
	items.append(rs)
	var tt := W.Btn.new("Volver al título", 25, false, "Volver al título · ¿seguro?")
	tt.activated.connect(func() -> void:
		if ui:
			ui.call("restart", false))
	items.append(tt)
	for b in items:
		col.add_child(_center(b))
	_chain(items)
	_space(col, 10)
	_footer(col, "back", "Continuar")
	_pause.set_meta("focus", cont)
	_pause.set_meta("fit", col)


func _update_pause_status() -> void:
	var where := ""
	match Game.phase:
		Game.Phase.NIGHT:
			where = "Noche %d de %d" % [Game.night, Data.NIGHTS]
		Game.Phase.DUSK:
			where = "Cae la noche %d" % (Game.night + 1)
		_:
			where = "Día %d" % (Game.night + 1)
	_pause_status.text = "%s  ·  %d dracmas" % [where, Game.coins]


# --- options -----------------------------------------------------------------------------------------------

func open_options() -> void:
	if _options == null:
		_build_options()
	_push(_options)


func _panel_screen(name_s: String, title: String) -> Array:
	var scr := _screen(name_s)
	scr.add_child(Backdrop.new("dim", 0.3))
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(cc)
	scr.set_meta("fit_holder", cc)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := S.panel(0.72, 14, Color(S.GOLD, 0.4), 30.0)
	sb.content_margin_top = 24
	sb.content_margin_bottom = 22
	pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	pc.add_child(col)
	scr.set_meta("fit", pc)
	var t := W.TrackedText.new(title, S.CINZEL, 36, 13.0, S.GOLD, 1)
	col.add_child(_center(t))
	col.add_child(_center(W.Ornament.new("rule", 320.0)))
	_space(col, 6)
	return [scr, col]


func _build_options() -> void:
	var made := _panel_screen("Options", "OPCIONES")
	_options = made[0]
	var col: VBoxContainer = made[1]
	var music := W.OptionRow.new("Música", "slider")
	music.value = float(Settings.get_v("music"))
	music.changed.connect(func(v: Variant) -> void: Sfx.set_volume("Music", float(v)))
	music.committed.connect(func(v: Variant) -> void: Settings.set_v("music", float(v)))
	var sfx := W.OptionRow.new("Efectos", "slider")
	sfx.value = float(Settings.get_v("sfx"))
	sfx.changed.connect(func(v: Variant) -> void:
		Sfx.set_volume("SFX", float(v))
		Sfx.set_volume("Amb", float(v)))
	sfx.committed.connect(func(v: Variant) -> void:
		Settings.set_v("sfx", float(v))
		S.sfx("ui_select"))
	var quality := W.OptionRow.new("Calidad", "choice", ["Baja", "Media", "Alta"])
	quality.index = clampi(int(Settings.get_v("quality")), 0, 2)
	quality.committed.connect(func(v: Variant) -> void:
		Settings.set_v("quality", int(v))
		Settings.apply_quality(get_viewport()))
	var shake := W.OptionRow.new("Temblor de cámara", "choice", ["Sí", "No"])
	shake.index = 0 if bool(Settings.get_v("shake")) else 1
	shake.committed.connect(func(v: Variant) -> void: Settings.set_v("shake", int(v) == 0))
	var back_b := W.Btn.new("Volver", 23)
	back_b.activated.connect(back)
	var items: Array = [music, sfx, quality, shake]
	for it in items:
		col.add_child(it)
	_space(col, 8)
	col.add_child(_center(back_b))
	items.append(back_b)
	_chain(items)
	_footer(col, "back", "Volver")
	_options.set_meta("focus", music)


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
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 9)
	col.add_child(_center(grid))
	grid.add_child(Control.new())
	grid.add_child(S.label("TECLADO Y RATÓN", S.CINZEL, 14, S.GOLD, 3, 3))
	grid.add_child(S.label("MANDO", S.CINZEL, 14, S.GOLD, 3, 3))
	var rows := [
		["move", "Moverse", [["key", "WASD"], ["icon", "arrows"]], [["icon", "stick"], ["icon", "dpad"]]],
		["attack", "Atacar con el ancla", null, null],
		["bash", "Destello de la lente", null, null],
		["dodge", "Embestida de vapor", null, null],
		["power", "Haz del Faro", [["key", "Q"]], [["pill", "RB"], ["pill", "RT"]]],
		["interact", "Construir · usar (mantener)", null, null],
		["pause", "Pausa", null, null],
	]
	for r in rows:
		grid.add_child(S.label(r[1], S.GARAMOND, 19, S.IVORY, 0, 3))
		var kb: Control = G.new()
		if r[2] != null:
			kb.call("setup_caps", r[2], 26.0)
		else:
			kb.call("setup", r[0], 26.0, "kb")
		grid.add_child(kb)
		var pad: Control = G.new()
		if r[3] != null:
			pad.call("setup_caps", r[3], 26.0)
		else:
			pad.call("setup", r[0], 26.0, "pad")
		grid.add_child(pad)
	_space(col, 6)
	col.add_child(_center(W.Ornament.new("rule", 320.0, Color(S.GOLD, 0.45))))
	var note := S.label("En pantallas táctiles: arrastra el pulgar a la izquierda para moverte; los botones de la derecha atacan, destellan, embisten y lanzan el Haz. Mantén «Usar» para construir.", S.ITALIC, 17, Color(S.IVORY, 0.8), 0, 3)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size = Vector2(560, 0)
	col.add_child(_center(note))
	_space(col, 4)
	var back_b := W.Btn.new("Volver", 23)
	back_b.activated.connect(back)
	col.add_child(_center(back_b))
	_footer(col, "back", "Volver")
	_controls.set_meta("focus", back_b)


# --- end of the island -------------------------------------------------------------------------------------

func open_end(victory: bool) -> void:
	if _end != null:
		_end.queue_free()
	_build_end(victory)
	close_all()
	_stack.append(_end)
	_fit_screen(_end)
	_end.visible = true
	_end.modulate.a = 0.0
	var tw := S.tween(_end)
	tw.tween_interval(0.3)
	tw.tween_property(_end, "modulate:a", 1.0, 0.8)
	_focus_first(_end)


func _build_end(victory: bool) -> void:
	_end = _screen("End")
	var tint := Color(0.09, 0.06, 0.04) if victory else Color(0.03, 0.025, 0.07)
	_end.add_child(Backdrop.new("dim", 0.4 if victory else 0.56, tint, 980.0))
	var col := _centered_column(_end, 6)
	var icon := W.IconView.new("sun" if victory else "flame_out", S.GOLD if victory else Color(S.IVORY, 0.7), 46.0)
	col.add_child(_center(icon))
	var px := int(clampf(size.x * 0.045, 40.0, 60.0))
	var title := W.TrackedText.new("LA LUZ PERDURA" if victory else "LA LUZ SE HA APAGADO", S.CINZEL, px, px * 0.2, S.GOLD if victory else S.IVORY, 1)
	col.add_child(_center(title))
	var sub_t := "Delos ha resistido las siete noches. Nyx retrocede hacia el mar." if victory else "Nyx ha devorado la última luz del Egeo."
	var sub := S.label(sub_t, S.ITALIC, 22, Color(S.IVORY, 0.86), 0, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_space(col, 4)
	col.add_child(_center(W.Ornament.new("meander", 380.0, Color(S.GOLD, 0.55))))
	_space(col, 6)
	var nights := Game.night if victory else maxi(0, Game.night - 1)
	var stats := [
		["moon", "Noches superadas", "%d / %d" % [nights, Data.NIGHTS]],
		["enemy", "Criaturas abatidas", str(Game.stats.get("kills", 0))],
		["house", "Edificios levantados", str(Game.stats.get("built", 0))],
		["cat", "Gatos acariciados", str(Game.stats.get("cats", 0))],
		["flame_out", "Veces que la llama se apagó", str(Game.stats.get("deaths", 0))],
	]
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(440, 0)
	col.add_child(_center(box))
	var i := 0
	for s in stats:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		var iv := W.IconView.new(s[0], Color(S.GOLD, 0.85), 22.0)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(iv)
		var l := S.label(s[1], S.GARAMOND, 21, Color(S.IVORY, 0.9), 0, 3)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(S.label(s[2], S.CINZEL_BOLD, 22, S.IVORY, 1, 4))
		box.add_child(row)
		row.modulate.a = 0.0
		var tw := S.tween(row)
		tw.tween_interval(0.9 + 0.12 * i)
		tw.tween_property(row, "modulate:a", 1.0, 0.4)
		i += 1
	_space(col, 8)
	col.add_child(_center(W.Ornament.new("rule", 380.0, Color(S.GOLD, 0.5))))
	_space(col, 8)
	var btns := HBoxContainer.new()
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 18)
	col.add_child(_center(btns))
	var again := W.Btn.new("Jugar de nuevo", 24)
	again.activated.connect(func() -> void:
		if ui:
			ui.call("restart", true))
	btns.add_child(again)
	var to_title := W.Btn.new("Título", 24)
	to_title.activated.connect(func() -> void:
		if ui:
			ui.call("restart", false))
	btns.add_child(to_title)
	again.focus_neighbor_right = again.get_path_to(to_title)
	to_title.focus_neighbor_left = to_title.get_path_to(again)
	again.focus_neighbor_left = again.get_path_to(to_title)
	to_title.focus_neighbor_right = to_title.get_path_to(again)
	_end.set_meta("focus", again)
	_end.set_meta("fit", col)
