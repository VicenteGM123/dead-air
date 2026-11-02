extends Control
class_name RankScreens
## --- SS2 RANK: las pantallas del Lantern Board (SS2_DESIGN §3.8, §3.9, §8.8, §8.12). Reemplaza el stub de la línea S.
##   open_night(move)  el tablero de la noche: marco de latón, la línea de Rosa Reverb, los 3 primeros fijos y una
##                     ventana de 9 filas alrededor de Nell que gira como un cartel de persianas (split-flap) desde la
##                     tabla de anoche; el desglose de esta noche bajo la fila de Nell; a quién pasó; el hito nuevo;
##                     "Next: ..." y lo de mañana. E / Enter / A siguen (después de 1.5 s); Esc / B saltan la animación
##                     (y después cierran). Nunca más de ~4 s de animación.
##   open_board()      el tablero entero: 2 columnas x 15 filas (filas = botones: el cursor del mando salta con
##                     LB / RB), la ficha de la tienda elegida con su mundo en la carta. ↑↓ / W S eligen fila, ← → / A D
##                     cambian de columna, ratón (pasar / clic / rueda); Esc / R / B / Y cierran.
##   open_report(rep)  la cinta de papel del Lantern Report (480 px): la radio la imprime línea a línea; las notas de
##                     lápiz de Nell en el margen ("us!" en un círculo). E / A terminan de imprimir y después cierran;
##                     Esc / B cierran.
## Se arma una vez (main._boot_background -> _make_rank, escondido) con todas sus texturas cargadas en _ready (nada se
## carga en un camino caliente) y se reusa: abrir solo rellena textos y muestra. auto = los bots (cada pantalla avanza
## sola). Los sonidos se piden con su nombre completo (sfx_flap, sfx_tape...): suenan con o sin los alias de Sfx.

signal done

const AMBER := Color(1.0, 0.72, 0.30)
const AMBER_HI := Color(1.0, 0.86, 0.52)
const PINK := Color(1.0, 0.56, 0.75)
const TEAL := Color(0.45, 0.88, 0.78)
const RED := Color(1.0, 0.45, 0.38)
const INK := Color(0.17, 0.13, 0.11)
const PENCIL := Color(0.72, 0.18, 0.14)
const MUTED := Color(0.76, 0.71, 0.63)
const ROW_H := 30.0
const WINDOW := 9                # filas alrededor de Nell
const ACTIVE_AFTER := 1.5        # E / A siguen recién después de esto
## Las coordenadas de los mundos en chart.png (160x90 nativos, x2 en pantalla): como CHART_WORLDS de ss_rank_art.py.
const CHART_XY := {"saffra": Vector2(34, 60), "brindle": Vector2(18, 34), "ochre": Vector2(56, 30),
	"patina": Vector2(82, 52), "thimble": Vector2(98, 22), "hollowmere": Vector2(118, 44), "teasel": Vector2(136, 66),
	"brineflat": Vector2(106, 74), "hitchpost": Vector2(66, 70), "shoals": Vector2(146, 24), "moving": Vector2(60, 48)}

var auto := false                # los bots: cada pantalla avanza sola
var _mode := ""                  # "" | "night" | "board" | "report"
var _t := 0.0                    # segundos desde que se abrió
var _animating := false
var _pad_was := false

# texturas (todas en _ready)
var _tex := {}
var _lantern_at: Array = []      # 7 AtlasTexture
var _crest_at: Array = []        # 30 AtlasTexture
var _sb_board: StyleBox
var _sb_flap: StyleBox
var _sb_flap_flip: StyleBox
var _sb_tape: StyleBox
var _sb_row_me: StyleBox
var _sb_row_rival: StyleBox
var _sb_row_sel: StyleBox
var _sb_empty: StyleBox

var _dim: ColorRect
# --- el tablero de la noche
var _night: PanelContainer
var _n_rosa: Label
var _n_rows: Array = []          # [{"box", "pos", "lantern", "crest", "name", "world", "score", "arrow", "late"}]
var _n_gap: Label
var _n_list: VBoxContainer
var _n_breakdown: Label
var _n_special: FlapText         # "THE SECONDHAND STAR passes SHINE AGAIN"
var _n_passed: Label
var _n_milestone: Label
var _n_next: Label
var _n_preview: Label
var _n_btn: Button
var _n_key: HBoxContainer
var _n_hint: Label
var _n_move := {}
var _n_flip_end := 0.0
# --- el tablero entero
var _board: PanelContainer
var _b_rows: Array = []          # [{"btn", "pos", "lantern", "crest", "name", "score", "arrow"}]
var _b_sel := 0
var _b_ids: Array = []
var _b_crest: TextureRect
var _b_name: Label
var _b_owner: Label
var _b_world: Label
var _b_line: Label
var _b_stats: Label
var _b_chart: TextureRect
var _b_mark: ChartMark
var _b_path: Label
var _b_rosa: Label
var _b_hint: Label
var _b_close: Button
var _b_close_key: HBoxContainer
# --- el Lantern Report
var _report: Control
var _r_tape: VBoxContainer
var _r_body: Control             # recorta mientras imprime
var _r_inner: VBoxContainer
var _r_lines: Array = []         # 7 Label
var _r_seps: Array = []
var _r_edition: Label
var _r_notes: Control            # las notas de lápiz (encima de todo)
var _r_note_list: Array = []     # [{"label", "ring", "line"}]
var _r_btn: Button
var _r_key: HBoxContainer
var _r_print_t := 0.0
var _r_print_len := 1.8
var _r_rep := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	UIKit.load_fonts()
	_load_textures()
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.05, 0.42)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)
	_build_night()
	_build_board()
	_build_report()
	visible = false
	set_process(false)

func _load_textures() -> void:
	for n in ["board9", "flap_cell", "lanterns", "crests", "chart", "tape9", "tape_header", "rosa", "stamp_late"]:
		var p := "res://assets/ui/%s.png" % n
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	for i in 7:
		var at := AtlasTexture.new()
		at.atlas = _tex["lanterns"]
		at.region = Rect2(i * 16, 0, 16, 24)
		_lantern_at.append(at)
	for i in 30:
		var at2 := AtlasTexture.new()
		at2.atlas = _tex["crests"]
		at2.region = Rect2(i * 24, 0, 24, 24)
		_crest_at.append(at2)
	_sb_board = _nine(_tex["board9"], 18, 22)
	_sb_flap = _nine_region(_tex["flap_cell"], Rect2(0, 0, 48, 32), 6, 0)
	_sb_flap_flip = _nine_region(_tex["flap_cell"], Rect2(48, 0, 48, 32), 6, 0)
	_sb_tape = _nine(_tex["tape9"], 16, 0)
	if _sb_tape is StyleBoxTexture:
		var st := _sb_tape as StyleBoxTexture
		st.texture_margin_top = 8
		st.texture_margin_bottom = 16
		st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		st.content_margin_left = 30
		st.content_margin_right = 30
		st.content_margin_top = 10
		st.content_margin_bottom = 26
	_sb_row_me = _flat(Color(1.0, 0.72, 0.3, 0.16), Color(1.0, 0.72, 0.3, 0.55))
	_sb_row_rival = _flat(Color(1.0, 0.56, 0.75, 0.08), Color(0, 0, 0, 0))
	_sb_row_sel = _flat(Color(1.0, 0.86, 0.52, 0.14), Color(1.0, 0.72, 0.3, 0.8))
	_sb_empty = StyleBoxEmpty.new()

func _nine(tex: Texture2D, margin: int, content: int) -> StyleBox:
	if tex == null:
		return UIKit.panel_style(Color(0.11, 0.1, 0.09, 0.96), UIKit.ACCENT, 3, 6, content)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb

func _nine_region(tex: Texture2D, region: Rect2, margin_x: int, content: int) -> StyleBox:
	if tex == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.13, 0.12, 0.11)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.region_rect = region
	sb.texture_margin_left = margin_x
	sb.texture_margin_right = margin_x
	sb.texture_margin_top = 0
	sb.texture_margin_bottom = 0
	sb.set_content_margin_all(content)
	return sb

func _flat(bg: Color, border: Color) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = bg
	f.border_color = border
	f.set_border_width_all(1 if border.a > 0 else 0)
	f.set_corner_radius_all(3)
	f.content_margin_left = 4
	f.content_margin_right = 4
	return f

func _lbl(text: String, size: int, col: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return UIKit.label(text, size, col, font if font else UIKit.font_regular, align)

func _primary(b: Button) -> void:
	for pair in [["normal", "btn_primary9.png"], ["hover", "btn_primary_hover9.png"], ["pressed", "btn_primary_pressed9.png"],
			["disabled", "btn_disabled9.png"]]:
		var sb := UIKit.nine(pair[1], 12, 15)
		if sb:
			sb.content_margin_left = maxf(sb.content_margin_left, 18.0)
			sb.content_margin_right = maxf(sb.content_margin_right, 18.0)
			b.add_theme_stylebox_override(pair[0], sb)

func _button(text: String, primary: bool, cb: Callable, w := 180.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(w, 46)
	if primary:
		_primary(b)
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	return b

## La tecla del aparato en uso al lado de un botón (se rehace al cambiar de aparato).
func _set_key(box: HBoxContainer, key_kb: String, key_pad: String) -> void:
	for c in box.get_children():
		c.queue_free()
	var k := key_pad if PadCursor.pad_in_use else key_kb
	if k == "":
		return
	var kc := UIKit.keycap(k, 16)
	kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(kc)

# ================================================================== el tablero de la noche

func _build_night() -> void:
	_night = PanelContainer.new()
	_night.add_theme_stylebox_override("panel", _sb_board)
	UIKit.place(_night, Vector2(1.0, 0.5), Vector2(-812, 0), Vector2(780, 0), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH)
	_night.mouse_filter = Control.MOUSE_FILTER_STOP
	_night.gui_input.connect(_on_dim_input)   # un clic (o la A del mando sin apuntar) en el tablero = seguir
	add_child(_night)
	var v := UIKit.vbox(4)
	_night.add_child(v)
	# cabecera: farol, título, la carta
	var head := UIKit.hbox(12)
	var ic := UIKit.ui_icon("rank", 3.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var hv := UIKit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(_lbl("LANTERN BOARD", 28, AMBER, UIKit.font_mono))
	hv.add_child(_lbl(Ranking.BOARD_SUB, 18, MUTED))
	head.add_child(hv)
	var chart := TextureRect.new()
	chart.texture = _tex["chart"]
	chart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chart.stretch_mode = TextureRect.STRETCH_SCALE
	chart.custom_minimum_size = Vector2(96, 54)
	chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(chart)
	v.add_child(head)
	# la línea de Rosa
	var rosa_row := UIKit.hbox(10)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _flat(Color(0.08, 0.06, 0.05, 1.0), Color(0.79, 0.6, 0.28, 1.0)))
	var rosa := TextureRect.new()
	rosa.texture = _tex["rosa"]
	rosa.custom_minimum_size = Vector2(32, 32)
	rosa.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rp.add_child(rosa)
	rp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rosa_row.add_child(rp)
	var rv := UIKit.vbox(-2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_lbl("Rosa Reverb · the Drift Signal", 16, MUTED, UIKit.font_bold))
	_n_rosa = _lbl("", 19, UIKit.TEXT, UIKit.font_italic)
	_n_rosa.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_n_rosa.custom_minimum_size = Vector2(640, 0)
	rv.add_child(_n_rosa)
	rosa_row.add_child(rv)
	v.add_child(rosa_row)
	v.add_child(_divider())
	# las filas
	_n_list = UIKit.vbox(1)
	v.add_child(_n_list)
	for i in 13:
		var r := _night_row()
		_n_rows.append(r)
		_n_list.add_child(r["box"])
	_n_gap = _lbl("·  ·  ·", 18, MUTED, UIKit.font_mono, HORIZONTAL_ALIGNMENT_CENTER)
	_n_gap.custom_minimum_size = Vector2(0, 16)
	_n_list.add_child(_n_gap)
	_n_list.move_child(_n_gap, 3)
	_n_breakdown = _lbl("", 17, AMBER_HI, UIKit.font_regular)
	_n_breakdown.custom_minimum_size = Vector2(0, 22)
	_n_list.add_child(_n_breakdown)
	# la fila especial, a quién pasó, el hito (juntos, sin separación)
	var news := UIKit.vbox(0)
	v.add_child(news)
	_n_special = FlapText.new()
	_n_special.setup(38, 18, _sb_flap, _sb_flap_flip, PINK)
	_n_special.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	news.add_child(_n_special)
	_n_passed = _lbl("", 18, TEAL, UIKit.font_bold)
	_n_passed.clip_text = true
	_n_passed.custom_minimum_size = Vector2(700, 0)
	news.add_child(_n_passed)
	_n_milestone = _lbl("", 18, AMBER_HI, UIKit.font_bold)
	news.add_child(_n_milestone)
	# pie: el siguiente, mañana, seguir
	var foot := UIKit.hbox(12)
	var fv := UIKit.vbox(0)
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_n_next = _lbl("", 18, UIKit.TEXT, UIKit.font_bold)
	_n_preview = _lbl("", 17, MUTED)
	_n_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_n_preview.custom_minimum_size = Vector2(480, 0)
	fv.add_child(_n_next)
	fv.add_child(_n_preview)
	foot.add_child(fv)
	_n_hint = _lbl("", 16, MUTED, UIKit.font_regular, HORIZONTAL_ALIGNMENT_RIGHT)
	_n_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_n_hint)
	_n_key = UIKit.hbox(0)
	_n_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_n_key)
	_n_btn = _button("Continue", true, func(): _advance(), 170)
	_n_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_n_btn)
	v.add_child(foot)
	_night.visible = false

func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(0.79, 0.6, 0.28, 0.45)
	d.custom_minimum_size = Vector2(0, 2)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

func _night_row() -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _sb_empty)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIKit.hbox(7)
	box.add_child(h)
	var pos := FlapText.new()
	pos.setup(2, 18, _sb_flap, _sb_flap_flip, AMBER)
	pos.right_align = true
	h.add_child(pos)
	var lan := TextureRect.new()
	lan.custom_minimum_size = Vector2(16, 24)
	lan.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	lan.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lan)
	var cr := TextureRect.new()
	cr.custom_minimum_size = Vector2(24, 24)
	cr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cr)
	var nm := FlapText.new()
	nm.setup(22, 18, _sb_flap, _sb_flap_flip, AMBER)
	h.add_child(nm)
	var wl := _lbl("", 16, MUTED)
	wl.custom_minimum_size = Vector2(96, 0)
	wl.clip_text = true
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(wl)
	var sc := FlapText.new()
	sc.setup(4, 18, _sb_flap, _sb_flap_flip, AMBER)
	sc.right_align = true
	h.add_child(sc)
	var ar := _lbl("", 17, TEAL, UIKit.font_bold)
	ar.custom_minimum_size = Vector2(42, 0)
	ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ar)
	var late := TextureRect.new()
	late.texture = _tex["stamp_late"]
	late.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	late.stretch_mode = TextureRect.STRETCH_SCALE
	late.custom_minimum_size = Vector2(48, 24)
	late.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	late.rotation = -0.12
	late.pivot_offset = Vector2(24, 12)
	late.visible = false
	h.add_child(late)
	return {"box": box, "pos": pos, "lantern": lan, "crest": cr, "name": nm, "world": wl, "score": sc, "arrow": ar,
		"late": late}

func _fill_night_row(r: Dictionary, row: Dictionary, now: bool, delay := 0.0) -> bool:
	var p := int(row.get("pos", 0))
	var nm := String(row.get("name", "")).to_upper()
	var sc := str(int(row.get("score", 0)))
	var me := bool(row.get("me", false))
	var rival := bool(row.get("rival", false))
	var col := AMBER_HI if me else (PINK if rival else AMBER)
	for k in ["pos", "name", "score"]:
		(r[k] as FlapText).color = col
	var changed := false
	if now:
		(r["pos"] as FlapText).set_now(str(p))
		(r["name"] as FlapText).set_now(nm)
		(r["score"] as FlapText).set_now(sc)
	else:
		changed = (r["name"] as FlapText).flip_to(nm, delay)
		changed = (r["score"] as FlapText).flip_to(sc, delay + 0.05) or changed
		(r["pos"] as FlapText).flip_to(str(p), delay)
	var li := int(row.get("lantern", 0))
	if p >= 1 and p <= 3:
		li = 3 + p
	(r["lantern"] as TextureRect).texture = _lantern_at[clampi(li, 0, 6)]
	(r["crest"] as TextureRect).texture = _crest_at[clampi(int(row.get("crest", 29)), 0, 29)]
	(r["world"] as Label).text = String(row.get("world_name", ""))
	(r["box"] as PanelContainer).add_theme_stylebox_override("panel", _sb_row_me if me else (_sb_row_rival if rival else _sb_empty))
	(r["late"] as TextureRect).visible = me and bool(row.get("late", false)) and now
	return changed

func _set_arrow(r: Dictionary, delta: int) -> void:
	var a := r["arrow"] as Label
	if delta > 0:
		a.text = "▲%d" % delta
		a.add_theme_color_override("font_color", TEAL)
	elif delta < 0:
		a.text = "▼%d" % -delta
		a.add_theme_color_override("font_color", RED)
	else:
		a.text = "–"
		a.add_theme_color_override("font_color", MUTED)

## Qué puestos se ven: los 3 primeros y 9 alrededor de Nell (si Nell está entre los 12 primeros, del 1 al 12).
func _slots(pos: int) -> Array:
	var out: Array = []
	if pos <= 12:
		for i in range(1, 13):
			out.append(i)
		return out
	out = [1, 2, 3]
	var lo := pos - WINDOW / 2
	var hi := lo + WINDOW - 1
	if hi > 30:
		hi = 30
		lo = hi - WINDOW + 1
	lo = maxi(lo, 4)
	for i in range(lo, hi + 1):
		out.append(i)
	return out

func open_night(move: Dictionary) -> void:
	# (web) la música de la noche se decodifica aquí la primera vez, al abrir el tablero (una pantalla quieta); hasta
	# entonces Sfx toca su respaldo (music_title). En escritorio no hace nada.
	Sfx.prewarm_late("night")
	_begin("night")
	_n_move = move.duplicate(true)
	var now: Array = Ranking.table()
	var before: Array = Ranking.table(true)
	var pos := Ranking.position()
	var slots := _slots(pos)
	var animate := not move.is_empty() and Ranking.committed > 0
	_n_rosa.text = "“%s”" % String(move.get("line", "The Lantern Board. Thirty lanterns, one sky."))
	_n_gap.visible = slots.size() > 3 and int(slots[3]) > 4
	var row_i := 0
	var t_end := 0.0
	var me_row := -1
	for i in _n_rows.size():
		var r: Dictionary = _n_rows[i]
		if i >= slots.size():
			(r["box"] as Control).visible = false
			continue
		(r["box"] as Control).visible = true
		var slot := int(slots[i])
		var nrow: Dictionary = now[slot - 1]
		if bool(nrow["me"]):
			me_row = i
		if animate:
			var prow: Dictionary = before[slot - 1]
			_fill_night_row(r, prow, true)
			(r["late"] as TextureRect).visible = false
			(r["arrow"] as Label).text = ""
			var delay := 0.15 + 0.22 * row_i
			if _fill_night_row(r, nrow, false, delay):
				_flap_sound_at(delay)
				t_end = delay + 0.75
				# el escudo, el farol y el mundo cambian cuando la fila empieza a girar
				_set_row_looks(r, prow)
				_row_looks_at(r, nrow, delay + 0.12)
			row_i += 1
		else:
			_fill_night_row(r, nrow, true)
			_set_arrow(r, int(nrow.get("delta", 0)))
	# el desglose, bajo la fila de Nell
	_n_breakdown.visible = me_row >= 0 and not move.is_empty()
	_n_breakdown.text = "      " + Ranking.breakdown(move) if not move.is_empty() else ""
	if me_row >= 0:
		var idx := (_n_rows[me_row]["box"] as Control).get_index()
		_n_list.move_child(_n_breakdown, idx + 1)
	# lo de abajo aparece cuando el cartel termina de girar
	_n_special.visible = false
	_n_passed.text = ""
	_n_milestone.text = ""
	var nx: Dictionary = Ranking.next_above()
	if nx.is_empty():
		_n_next.text = "Nobody above you. Keep the lanterns lit."
	else:
		_n_next.text = "Next: %s, %d ★ above you." % [String(nx["name"]), int(nx["gap"])]
	_n_preview.text = _tomorrow()
	_n_preview.visible = _n_preview.text != ""
	_n_flip_end = t_end if animate else 0.0
	_animating = animate and t_end > 0.0
	if not _animating:
		_after_flips()
	_night.visible = true
	_n_btn.disabled = true
	_refresh_keys()
	UIKit.pop_in(_night)

func _tomorrow() -> String:
	var s := get_node_or_null("/root/Season")
	if s != null and s.has_method("night_preview"):
		return String(s.call("night_preview", Game.day))
	return ""

func _set_row_looks(r: Dictionary, row: Dictionary) -> void:
	var p := int(row.get("pos", 0))
	var li := int(row.get("lantern", 0))
	if p >= 1 and p <= 3:
		li = 3 + p
	(r["lantern"] as TextureRect).texture = _lantern_at[clampi(li, 0, 6)]
	(r["crest"] as TextureRect).texture = _crest_at[clampi(int(row.get("crest", 29)), 0, 29)]
	(r["world"] as Label).text = String(row.get("world_name", ""))

func _row_looks_at(r: Dictionary, row: Dictionary, delay: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if _mode == "night":
			_set_row_looks(r, row))

func _flap_sound_at(delay: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if _mode == "night":
			Sfx.play("sfx_flap", 0.08, -7.0))

## El cartel terminó de girar (o se saltó): flechas, LATE, a quién pasó, el hito, la fila especial, el sonido.
func _after_flips() -> void:
	_animating = false
	var now: Array = Ranking.table()
	for r in _n_rows:
		if not (r["box"] as Control).visible:
			continue
		(r["pos"] as FlapText).settle()
		(r["name"] as FlapText).settle()
		(r["score"] as FlapText).settle()
	var slots := _slots(Ranking.position())
	for i in mini(slots.size(), _n_rows.size()):
		var row: Dictionary = now[int(slots[i]) - 1]
		_set_row_looks(_n_rows[i], row)
		_set_arrow(_n_rows[i], int(row.get("delta", 0)))
		(_n_rows[i]["late"] as TextureRect).visible = bool(row.get("me", false)) and bool(row.get("late", false))
	var mv := _n_move
	if mv.is_empty():
		return
	var passed: Array = mv.get("passed", [])
	var by: Array = mv.get("passed_by", [])
	if Ranking.RIVAL in passed:
		_n_special.visible = true
		_n_special.set_now("")
		_n_special.flip_to("THE SECONDHAND STAR passes SHINE AGAIN".to_upper(), 0.05)
	elif Ranking.RIVAL in by:
		_n_special.visible = true
		_n_special.set_now("")
		_n_special.flip_to("SHINE AGAIN passes THE SECONDHAND STAR".to_upper(), 0.05)
	if not passed.is_empty():
		var names: Array = []
		for id in passed.slice(0, 2):
			names.append("%s (%s)" % [Ranking.shop_name(String(id)), Ranking.world_name(Ranking.world_of(String(id)))])
		var more := passed.size() - 2
		_n_passed.text = "Passed: " + ", ".join(names) + (" and %d more" % more if more > 0 else "")
	var mn := int(mv.get("milestone_new", 0))
	if mn > 0:
		_n_milestone.text = "★ " + Ranking.milestone_line(mn)
	var d := int(mv.get("delta", 0))
	if d > 0:
		Sfx.play("sfx_rank_up", 0.0, -4.0)
	elif d < 0:
		Sfx.play("sfx_rank_down", 0.0, -5.0)
	if bool(Ranking.row(Ranking.ME).get("late", false)):
		Sfx.play("sfx_stamp", 0.04, -4.0)

# ================================================================== el tablero entero

func _build_board() -> void:
	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", _sb_board)
	UIKit.place(_board, Vector2(0.5, 0.5), Vector2(-604, 0), Vector2(1208, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board)
	var v := UIKit.vbox(6)
	_board.add_child(v)
	var head := UIKit.hbox(12)
	var ic := UIKit.ui_icon("rank", 3.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var hv := UIKit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t1 := UIKit.hbox(14)
	t1.add_child(_lbl("LANTERN BOARD", 28, AMBER, UIKit.font_mono))
	var sub := _lbl(Ranking.BOARD_SUB, 18, MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	t1.add_child(sub)
	hv.add_child(t1)
	_b_rosa = _lbl("", 17, UIKit.TEXT, UIKit.font_italic)
	_b_rosa.clip_text = true
	_b_rosa.custom_minimum_size = Vector2(760, 0)
	hv.add_child(_b_rosa)
	head.add_child(hv)
	_b_close_key = UIKit.hbox(0)
	_b_close_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_b_close_key)
	_b_close = _button("Close", true, func(): close_now(), 120)
	_b_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_b_close)
	v.add_child(head)
	v.add_child(_divider())
	var body := UIKit.hbox(14)
	v.add_child(body)
	for col in 2:
		var cv := UIKit.vbox(2)
		cv.custom_minimum_size = Vector2(408, 0)
		body.add_child(cv)
		for i in 15:
			var r := _board_row(col * 15 + i)
			_b_rows.append(r)
			cv.add_child(r["btn"])
	# la ficha de la tienda elegida
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.05, 0.045, 0.75), Color(0.79, 0.6, 0.28, 0.5)))
	card.custom_minimum_size = Vector2(336, 0)
	body.add_child(card)
	var dv := UIKit.vbox(4)
	card.add_child(dv)
	var dh := UIKit.hbox(10)
	_b_crest = TextureRect.new()
	_b_crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_b_crest.stretch_mode = TextureRect.STRETCH_SCALE
	_b_crest.custom_minimum_size = Vector2(48, 48)
	_b_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dh.add_child(_b_crest)
	var dhv := UIKit.vbox(-2)
	dhv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_b_name = _lbl("", 21, UIKit.TEXT, UIKit.font_bold)
	_b_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_name.custom_minimum_size = Vector2(250, 0)
	_b_owner = _lbl("", 16, MUTED)
	_b_owner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_owner.custom_minimum_size = Vector2(250, 0)
	dhv.add_child(_b_name)
	dhv.add_child(_b_owner)
	dh.add_child(dhv)
	dv.add_child(dh)
	_b_stats = _lbl("", 20, AMBER, UIKit.font_mono)
	dv.add_child(_b_stats)
	_b_line = _lbl("", 17, UIKit.TEXT, UIKit.font_italic)
	_b_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_line.custom_minimum_size = Vector2(316, 0)
	dv.add_child(_b_line)
	_b_world = _lbl("", 17, MUTED)
	_b_world.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_world.custom_minimum_size = Vector2(316, 0)
	dv.add_child(_b_world)
	var chart_box := Control.new()
	chart_box.custom_minimum_size = Vector2(320, 180)
	chart_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_b_chart = TextureRect.new()
	_b_chart.texture = _tex["chart"]
	_b_chart.size = Vector2(320, 180)
	_b_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_box.add_child(_b_chart)
	_b_mark = ChartMark.new()
	_b_mark.size = Vector2(320, 180)
	chart_box.add_child(_b_mark)
	dv.add_child(chart_box)
	_b_path = _lbl("", 16, MUTED, UIKit.font_mono)
	_b_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_path.custom_minimum_size = Vector2(316, 0)
	dv.add_child(_b_path)
	_b_hint = _lbl("", 16, MUTED, UIKit.font_regular, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_b_hint)
	_board.visible = false

func _board_row(i: int) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(408, 32)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, _sb_empty)
	b.add_theme_stylebox_override("hover", _sb_row_sel)
	b.mouse_entered.connect(func(): _select(i, false))
	b.pressed.connect(func(): _select(i, true))
	var h := UIKit.hbox(7)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var pos := _lbl("", 18, AMBER, UIKit.font_mono, HORIZONTAL_ALIGNMENT_RIGHT)
	pos.custom_minimum_size = Vector2(28, 0)
	pos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pos)
	var lan := TextureRect.new()
	lan.custom_minimum_size = Vector2(16, 24)
	lan.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	lan.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(lan)
	var cr := TextureRect.new()
	cr.custom_minimum_size = Vector2(24, 24)
	cr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cr)
	var nm := _lbl("", 17, UIKit.TEXT, UIKit.font_regular)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.clip_text = true
	h.add_child(nm)
	var sc := _lbl("", 18, AMBER, UIKit.font_mono, HORIZONTAL_ALIGNMENT_RIGHT)
	sc.custom_minimum_size = Vector2(52, 0)
	sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sc)
	var ar := _lbl("", 16, TEAL, UIKit.font_bold)
	ar.custom_minimum_size = Vector2(36, 0)
	ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ar)
	return {"btn": b, "pos": pos, "lantern": lan, "crest": cr, "name": nm, "score": sc, "arrow": ar}

func open_board() -> void:
	_begin("board")
	var t: Array = Ranking.table()
	_b_ids = []
	for i in _b_rows.size():
		var r: Dictionary = _b_rows[i]
		var row: Dictionary = t[i]
		_b_ids.append(String(row["id"]))
		var me := bool(row["me"])
		var rival := bool(row["rival"])
		(r["pos"] as Label).text = str(int(row["pos"]))
		var li := int(row["lantern"])
		if i < 3:
			li = 4 + i
		(r["lantern"] as TextureRect).texture = _lantern_at[li]
		(r["crest"] as TextureRect).texture = _crest_at[int(row["crest"])]
		(r["name"] as Label).text = String(row["name"])
		(r["name"] as Label).add_theme_color_override("font_color", AMBER_HI if me else (PINK if rival else UIKit.TEXT))
		(r["name"] as Label).add_theme_font_override("font", UIKit.font_bold if me else UIKit.font_regular)
		(r["score"] as Label).text = str(int(row["score"]))
		_set_arrow(r, int(row["delta"]))
		(r["btn"] as Button).add_theme_stylebox_override("normal", _sb_row_me if me else _sb_empty)
		(r["btn"] as Button).tooltip_text = String(row["line"])
	_b_rosa.text = ("“%s”" % String(Ranking.last_move().get("line", ""))) if not Ranking.last_move().is_empty() else \
		"“Thirty lanterns, one sky. Every happy customer is a star.”"
	_select(Ranking.position() - 1, false)
	_board.visible = true
	_refresh_keys()
	UIKit.pop_in(_board)

## Elige una fila del tablero entero (0..29) y llena la ficha.
func select_row(i: int) -> void:
	_select(i, false)

func _select(i: int, clicked: bool) -> void:
	if _mode != "board" or _b_ids.is_empty():
		return
	_b_sel = clampi(i, 0, _b_ids.size() - 1)
	for k in _b_rows.size():
		var me := String(_b_ids[k]) == Ranking.ME
		var st: StyleBox = _sb_row_sel if k == _b_sel else (_sb_row_me if me else _sb_empty)
		(_b_rows[k]["btn"] as Button).add_theme_stylebox_override("normal", st)
	var row: Dictionary = Ranking.row(String(_b_ids[_b_sel]))
	_b_crest.texture = _crest_at[int(row["crest"])]
	_b_name.text = String(row["name"])
	_b_owner.text = "%s · %s" % [String(row["owner"]), String(row["species"])]
	var d := int(row["delta"])
	var arrow := (" ▲%d" % d) if d > 0 else ((" ▼%d" % -d) if d < 0 else "")
	_b_stats.text = "#%d · %d ★%s" % [int(row["pos"]), int(row["score"]), arrow]
	_b_line.text = "“%s”" % String(row["line"])
	_b_world.text = "%s: %s" % [String(row["world_name"]).capitalize() if String(row["world_name"]).begins_with("the ") else String(row["world_name"]), String(row["world_line"])]
	_b_mark.world = String(row["world"])
	_b_mark.colour = Color.html(String(row["colour"]))
	_b_mark.chart_xy = CHART_XY
	_b_mark.queue_redraw()
	if bool(row["me"]):
		var p: Array = Ranking.path()
		var bits: Array = []
		for h in p.slice(maxi(0, p.size() - 10)):
			bits.append("#%d" % int(h["pos"]))
		_b_path.text = ("Your nights: " + " · ".join(bits)) if not bits.is_empty() else "Your first night is tonight."
	elif bool(row["rival"]):
		var gap := Ranking.score(Ranking.RIVAL) - Ranking.score()
		_b_path.text = ("Shine Again leads you by %d ★." % gap) if gap > 0 else (("You lead Shine Again by %d ★." % -gap) if gap < 0 else "Neck and neck with Shine Again.")
	else:
		var gap2 := int(row["score"]) - Ranking.score()
		_b_path.text = ("%d ★ above you." % gap2) if gap2 > 0 else ("%d ★ below you." % -gap2 if gap2 < 0 else "Level with you.")
	if clicked:
		Sfx.play("click", 0.05, -6.0)

# ================================================================== el Lantern Report

func _build_report() -> void:
	_report = Control.new()
	_report.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_report.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_report)
	_r_tape = UIKit.vbox(0)
	UIKit.place(_r_tape, Vector2(0.5, 0.0), Vector2(-240, 28), Vector2(480, 0), Control.GROW_DIRECTION_BOTH)
	_r_tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report.add_child(_r_tape)
	# cabecera: la banda de tinta, Rosa en su marquito, DRIFT SIGNAL
	var head := Control.new()
	head.custom_minimum_size = Vector2(480, 48)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ht := TextureRect.new()
	ht.texture = _tex["tape_header"]
	ht.size = Vector2(480, 48)
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ht)
	var rosa := TextureRect.new()
	rosa.texture = _tex["rosa"]
	rosa.position = Vector2(25, 6)
	rosa.size = Vector2(32, 32)
	rosa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(rosa)
	var t1 := _lbl("DRIFT SIGNAL", 19, Color(0.94, 0.89, 0.78), UIKit.font_mono)
	t1.position = Vector2(70, 4)
	t1.add_theme_constant_override("outline_size", 0)
	head.add_child(t1)
	_r_edition = _lbl("", 14, AMBER, UIKit.font_mono)
	_r_edition.position = Vector2(71, 21)
	head.add_child(_r_edition)
	_r_tape.add_child(head)
	# el cuerpo: papel con perforaciones y borde rasgado; se recorta mientras imprime
	_r_body = Control.new()
	_r_body.clip_contents = true
	_r_body.custom_minimum_size = Vector2(480, 0)
	_r_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_r_tape.add_child(_r_body)
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", _sb_tape)
	paper.custom_minimum_size = Vector2(480, 0)
	paper.mouse_filter = Control.MOUSE_FILTER_STOP
	paper.gui_input.connect(_on_dim_input)
	_r_body.add_child(paper)
	_r_inner = UIKit.vbox(6)
	paper.add_child(_r_inner)
	for i in 7:
		var l := _lbl("", 18, INK, UIKit.font_mono)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		_r_lines.append(l)
		_r_inner.add_child(l)
		if i < 6:
			var sep := DotRule.new()
			sep.custom_minimum_size = Vector2(420, 6)
			_r_seps.append(sep)
			_r_inner.add_child(sep)
	# las notas de lápiz de Nell (en el margen, a la derecha de la cinta)
	_r_notes = Control.new()
	_r_notes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_r_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report.add_child(_r_notes)
	for i in 3:
		var nl := _lbl("", 30, PENCIL, UIKit.font_hand)
		nl.rotation = -0.12
		nl.visible = false
		_r_notes.add_child(nl)
		var ring := PencilRing.new()
		ring.visible = false
		_r_notes.add_child(ring)
		_r_note_list.append({"label": nl, "ring": ring, "line": -1})
	# abajo a la derecha: cerrar
	var foot := UIKit.hbox(10)
	UIKit.place(foot, Vector2(1.0, 1.0), Vector2(-300, -76), Vector2(268, 50), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	foot.alignment = BoxContainer.ALIGNMENT_END
	_r_key = UIKit.hbox(0)
	_r_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_r_key)
	_r_btn = _button("Continue", true, func(): _advance(), 170)
	foot.add_child(_r_btn)
	_report.add_child(foot)
	_report.visible = false

func open_report(rep: Dictionary) -> void:
	_begin("report")
	_r_rep = rep.duplicate(true)
	var lines: Array = rep.get("lines", [])
	_r_edition.text = "THE LANTERN REPORT · NO. %d · NIGHT %d" % [int(rep.get("edition", 1)), int(rep.get("night", Game.day))]
	for i in _r_lines.size():
		var l: Label = _r_lines[i]
		l.text = String(lines[i]["text"]) if i < lines.size() else ""
		l.add_theme_font_override("font", UIKit.font_mono)
	_r_body.custom_minimum_size.y = 0.0
	_r_print_t = 0.0
	_animating = true
	for n in _r_note_list:
		(n["label"] as Label).visible = false
		(n["ring"] as Control).visible = false
		n["line"] = -1
	var k := 0
	for i in mini(lines.size(), 7):
		var note := String(lines[i].get("note", ""))
		if note != "" and k < _r_note_list.size():
			_r_note_list[k]["line"] = i
			(_r_note_list[k]["label"] as Label).text = note
			k += 1
	_report.visible = true
	_r_btn.text = "Continue"
	_refresh_keys()
	Sfx.play("sfx_signal", 0.0, -3.0)
	get_tree().create_timer(0.35, false).timeout.connect(func():
		if _mode == "report" and _animating:
			Sfx.play("sfx_tape", 0.03, -5.0))

func _paper_height() -> float:
	var p := _r_body.get_child(0) as Control
	return p.get_combined_minimum_size().y

func _report_step(dt: float) -> void:
	if not _animating:
		return
	_r_print_t += dt
	var full := _paper_height()
	var k := clampf(_r_print_t / _r_print_len, 0.0, 1.0)
	_r_body.custom_minimum_size.y = roundf(full * k)
	if k >= 1.0:
		_finish_print()

func _finish_print() -> void:
	_animating = false
	_r_body.custom_minimum_size.y = _paper_height()
	_place_notes.call_deferred()

## Las notas de lápiz: a la derecha de la cinta, a la altura de su línea; "us!" con un círculo.
func _place_notes() -> void:
	for n in _r_note_list:
		var li := int(n["line"])
		if li < 0:
			continue
		var line: Label = _r_lines[li]
		var r := line.get_global_rect()
		var lbl: Label = n["label"]
		lbl.position = Vector2(r.position.x + 456, r.position.y - 6)
		lbl.visible = true
		var ring: PencilRing = n["ring"]
		if lbl.text == "us!":
			ring.position = lbl.position + Vector2(-10, 0)
			ring.size = Vector2(66, 40)
			ring.visible = true
		else:
			ring.visible = false

# ================================================================== común: abrir, avanzar, cerrar, entrada

func _begin(mode: String) -> void:
	_mode = mode
	_t = 0.0
	_animating = false
	visible = true
	_dim.visible = true
	_dim.color = Color(0.02, 0.02, 0.05, 0.42 if mode != "board" else 0.55)
	_night.visible = mode == "night"
	_board.visible = mode == "board"
	_report.visible = mode == "report"
	_pad_was = PadCursor.pad_in_use
	set_process(true)

func is_open() -> bool:
	return _mode != ""

func close_now() -> void:
	if _mode == "":
		return
	_mode = ""
	_animating = false
	visible = false
	set_process(false)
	done.emit()

## "next" (lo que haría E / A) | "close" (Esc / B). Para los bots y las pruebas.
func press(id := "") -> void:
	if id == "close":
		_back()
	else:
		_advance(true)

## E / Enter / A: en el tablero de la noche, seguir (recién después de 1.5 s, aunque todavía gire); en el Report,
## terminar de imprimir y después cerrar; en el tablero entero, cerrar.
func _advance(force := false) -> void:
	match _mode:
		"night":
			if force:
				# press("next") de los bots y las pruebas: primero termina el giro, después cierra
				if _animating:
					_skip_flips()
				else:
					close_now()
				return
			if _t < ACTIVE_AFTER:
				return   # (un E de más del libro de cuentas no se salta el tablero)
			close_now()
		"report":
			if _animating:
				_finish_print()
				return
			close_now()
		"board":
			close_now()

## Esc / B: saltan la animación; si ya terminó, cierran.
func _back() -> void:
	match _mode:
		"night":
			if _animating:
				_skip_flips()
			else:
				close_now()
		_:
			close_now()

func _skip_flips() -> void:
	_after_flips()

func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if _mode in ["night", "report"]:
			_advance()

func _input(ev: InputEvent) -> void:
	if _mode == "" or not visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		match k:
			KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_advance()
			KEY_ESCAPE:
				_back()
			KEY_R:
				if _mode == "board" and _t > 0.2:
					close_now()
			KEY_UP, KEY_W:
				if _mode == "board":
					_select(_b_sel - 1, false)
			KEY_DOWN, KEY_S:
				if _mode == "board":
					_select(_b_sel + 1, false)
			KEY_LEFT, KEY_A:
				if _mode == "board":
					_select(_b_sel - 15 if _b_sel >= 15 else _b_sel, false)
			KEY_RIGHT, KEY_D:
				if _mode == "board":
					_select(_b_sel + 15 if _b_sel < 15 else _b_sel, false)
			_:
				return
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and _mode == "board":
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select(_b_sel - 1, false)
			get_viewport().set_input_as_handled()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select(_b_sel + 1, false)
			get_viewport().set_input_as_handled()

func _refresh_keys() -> void:
	var pad := PadCursor.pad_in_use
	_set_key(_n_key, "E", "A")
	_set_key(_r_key, "E", "A")
	_set_key(_b_close_key, "Esc", "B")
	_n_hint.text = "B skip" if pad else "Esc skip"
	_b_hint.text = "LB / RB rows · A pick · B or Y close" if pad else "↑ ↓ ← → or mouse pick a shop · Esc or R close"

func _process(dt: float) -> void:
	if _mode == "":
		return
	_t += dt
	if PadCursor.pad_in_use != _pad_was:
		_pad_was = PadCursor.pad_in_use
		_refresh_keys()
	match _mode:
		"night":
			if _animating and _t >= _n_flip_end:
				_after_flips()
			_n_btn.disabled = _t < ACTIVE_AFTER
			if auto and not _animating and _t > maxf(ACTIVE_AFTER, _n_flip_end) + 0.4:
				close_now()
		"report":
			_report_step(dt)
			if auto and not _animating and _t > 0.6:
				close_now()
		"board":
			if auto and _t > 0.5:
				close_now()

# ================================================================== piezas dibujadas

## Un campo del cartel de persianas: una celda por letra, cada una gira por letras al azar antes de asentarse.
class FlapText extends Control:
	const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789&#"
	var cells := 4
	var fsize := 18
	var color := Color(1.0, 0.72, 0.3)
	var right_align := false
	var sb: StyleBox
	var sb_flip: StyleBox
	var cw := 12.0
	var ch := 28.0
	var _shown: Array = []
	var _target: Array = []
	var _left: Array = []         # segundos de giro que le quedan a cada celda (< 0: espera)
	var _tick := 0.0
	var _rng := RandomNumberGenerator.new()

	func setup(n: int, size: int, style: StyleBox, style_flip: StyleBox, col: Color) -> void:
		cells = n
		fsize = size
		sb = style
		sb_flip = style_flip
		color = col
		UIKit.load_fonts()
		cw = ceilf(UIKit.font_mono.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x) + 2.0
		ch = 26.0
		custom_minimum_size = Vector2(cells * cw + 8.0, ch)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shown = []
		_target = []
		_left = []
		for i in cells:
			_shown.append(" ")
			_target.append(" ")
			_left.append(0.0)
		set_process(false)

	func _fit(t: String) -> Array:
		var s := t.substr(0, cells)
		if right_align:
			s = s.lpad(cells)
		else:
			s = s.rpad(cells)
		var out: Array = []
		for i in cells:
			out.append(s[i])
		return out

	func set_now(t: String) -> void:
		_target = _fit(t)
		_shown = _target.duplicate()
		for i in cells:
			_left[i] = 0.0
		set_process(false)
		queue_redraw()

	## Gira hacia t (empieza después de delay). Devuelve si algo cambia.
	func flip_to(t: String, delay := 0.0) -> bool:
		_target = _fit(t)
		var any := false
		for i in cells:
			if String(_shown[i]) != String(_target[i]):
				_left[i] = -(delay + 0.018 * i) - 0.0001
				any = true
			else:
				_left[i] = 0.0
		if any:
			set_process(true)
		return any

	func settle() -> void:
		_shown = _target.duplicate()
		for i in cells:
			_left[i] = 0.0
		set_process(false)
		queue_redraw()

	func _process(dt: float) -> void:
		_tick += dt
		var busy := false
		var roll := _tick >= 0.045
		if roll:
			_tick = 0.0
		for i in cells:
			var lf: float = _left[i]
			if lf == 0.0:
				continue
			busy = true
			if lf < 0.0:
				lf += dt
				if lf >= 0.0:
					lf = 0.22 + _rng.randf() * 0.12
				_left[i] = lf
				continue
			lf -= dt
			if lf <= 0.0:
				_left[i] = 0.0
				_shown[i] = _target[i]
			else:
				_left[i] = lf
				if roll:
					_shown[i] = CHARS[_rng.randi() % CHARS.length()]
		queue_redraw()
		if not busy:
			set_process(false)

	func _draw() -> void:
		if sb:
			draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(size.x, ch)))
		var f: Font = UIKit.font_mono
		var asc := f.get_ascent(fsize)
		for i in cells:
			var x := 4.0 + i * cw
			if i > 0:
				draw_line(Vector2(x, 3), Vector2(x, ch - 3), Color(0.03, 0.025, 0.02, 0.9), 1.0)
			var flipping: bool = float(_left[i]) > 0.0
			if flipping:
				draw_rect(Rect2(x + 1, 2, cw - 2, ch / 2 - 2), Color(0, 0, 0, 0.45))
				draw_line(Vector2(x + 1, ch * 0.3), Vector2(x + cw - 1, ch * 0.3), Color(0.5, 0.44, 0.36, 0.8), 1.0)
			var c := String(_shown[i])
			if c != " ":
				var w := f.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
				draw_string(f, Vector2(x + (cw - w) * 0.5, (ch - fsize) * 0.5 + asc - 1), c, HORIZONTAL_ALIGNMENT_LEFT, -1,
					fsize, color.darkened(0.25) if flipping else color)
		# la raya de las dos persianas, encima de las letras
		draw_line(Vector2(2, ch * 0.5), Vector2(size.x - 2, ch * 0.5), Color(0.02, 0.015, 0.01, 0.65), 1.0)

## La marca del mundo en la carta (un anillo que late).
class ChartMark extends Control:
	var world := ""
	var colour := Color.WHITE
	var chart_xy := {}
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		if not chart_xy.has(world):
			return
		var p: Vector2 = chart_xy[world] * 2.0
		var r := 11.0 + 2.0 * sin(_t * 4.0)
		draw_arc(p, r, 0, TAU, 28, Color(0.17, 0.12, 0.08, 0.9), 3.0)
		draw_arc(p, r, 0, TAU, 28, colour.lightened(0.2), 1.5)

## Una línea de puntitos de impresora entre las noticias.
class DotRule extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, size.y * 0.5, 2, 2), Color(0.55, 0.47, 0.36, 0.7))
			x += 6.0

## El círculo de lápiz alrededor de "us!".
class PencilRing extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for i in 34:
			var a := -0.4 + i * TAU / 30.0
			var rr := 1.0 + 0.06 * sin(i * 1.7)
			pts.append(c + Vector2(cos(a) * size.x * 0.5 * rr, sin(a) * size.y * 0.5 * rr))
		draw_polyline(pts, Color(0.72, 0.18, 0.14, 0.85), 2.0, true)
