extends Control
class_name Dialogs
## --- SS CORE: las ventanas de diálogo del juego, todas con el mismo aspecto (placa clara remachada, texto oscuro,
## botones de tecla) y las mismas teclas:
##   E / Intro / Espacio = la opción principal (ámbar)   1..9 = cada opción   Esc = volver / cancelar
##   ratón: los botones   mando: A = la opción principal (o lo que apunta el cursor), B = cancelar
## Tipos (spec["kind"]):
##   "talk"   un personaje habla: retrato, nombre, su frase, una etiqueta de papel (el síntoma) y opciones
##   "parts"  el puesto de Mags: las 9 piezas con precio fijo (comprar varias sin cerrar)
##   "info"   el cajón de piezas o el estante (solo mirar)
##   "menu"   la pausa: volúmenes, seguir, volver al título
## --- SS2 SEASON:
##   "fittings" el patio de Dolly: las 8 mejoras (1-8 compran; cada fila dice lo que deja y la próxima cuota)
##   "calendar" el calendario de la temporada (el tablón de la calle, el menú)
##   "parts" con "stock" (lo de hoy, hasta 8: teclas 1-8) y "asis" (lo de "tal cual": teclas 9 y 0)
##   "talk" con "icon" (un icono en vez del retrato), "line2" (la segunda línea de un momento), "tag_head" ("A RIDDLE"),
##          "must_choose" (Esc / B no la cierra: avisa "Choose one: 1 or 2")
## open(spec, cb): cb(choice_id) al cerrar (choice "" = se cerró con Esc sin opción de cancelar). choose(id) elige
## por código (el bot).

signal closed(choice: String)
signal bought(part: String)
signal bought_fitting(id: String)   # --- SS2 SEASON

const W := 780.0

var spec := {}
var _cb := Callable()
var _opts: Array = []        # [{"id", "btn": Button, "primary"}]
var _cancel := ""
var _panel: PanelContainer
var _credits_lbl: Label
var _part_rows := {}          # part -> {"count": Label, "btn": Button}
var _open := false
# --- SS2 SEASON
var _fit_rows := {}           # fitting id -> {"btn": Button, "sub": Label, "panel"}
var _asis_rows: Array = []    # [{"btn": Button, "panel"}]
var _note_lbl: Label          # la línea de abajo (Dolly, Mags, "Choose one")
var _flash_tw: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	visible = false

func is_open() -> bool:
	return _open

func open(s: Dictionary, cb := Callable()) -> void:
	if _open:
		close_now()
	spec = s.duplicate(true)
	_cb = cb
	_opts = []
	_part_rows = {}
	_fit_rows = {}   # --- SS2 SEASON
	_asis_rows = []
	_note_lbl = null
	_cancel = String(spec.get("cancel", ""))
	_build()
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

func close_now() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in get_children():
		c.queue_free()
	_opts = []

## Elige una opción (como si se apretara su botón).
func choose(id: String) -> void:
	if not _open:
		return
	for o in _opts:
		if o["id"] == id:
			if (o["btn"] as Button).disabled:
				return
	_finish(id)

func option_ids() -> Array:
	var out := []
	for o in _opts:
		if not (o["btn"] as Button).disabled:
			out.append(o["id"])
	return out

func _finish(id: String) -> void:
	var cb := _cb
	close_now()
	closed.emit(id)
	if cb.is_valid():
		cb.call(id)

# ------------------------------------------------------------------ construcción

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, float(spec.get("dim", 0.35)))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _light_plate())
	add_child(_panel)
	match String(spec.get("kind", "talk")):
		"parts":
			_build_parts()
		"info":
			_build_info()
		"menu":
			_build_menu()
		"fittings":
			_build_fittings()   # --- SS2 SEASON
		"calendar":
			_build_calendar()
		_:
			_build_talk()
	# abajo al centro (diálogos) o al centro (menú, cajón, puesto)
	_panel.reset_size()
	var vs := get_viewport_rect().size
	var sz := _panel.get_combined_minimum_size()
	sz.x = maxf(sz.x, float(spec.get("width", W)))
	_panel.size = sz
	if String(spec.get("kind", "talk")) == "talk":
		_panel.position = Vector2((vs.x - sz.x) / 2.0, vs.y - sz.y - 64.0).round()
	else:
		_panel.position = ((vs - sz) / 2.0).round()
	UIKit.pop_in(_panel)

func _light_plate() -> StyleBox:
	var sb := UIKit.nine("plate_light9.png", 22, 12)
	if sb:
		sb.content_margin_left = 30
		sb.content_margin_right = 30
		sb.content_margin_top = 24
		sb.content_margin_bottom = 24
		return sb
	var f := UIKit.panel_style(Color(0.85, 0.79, 0.66, 0.98), Color(0.45, 0.4, 0.34), 2, 4, 24)
	return f

const INK := Color(0.165, 0.125, 0.14)
const INK_SOFT := Color(0.32, 0.27, 0.24)

func _ink(text: String, size := 20, font: Font = null, col := INK) -> Label:
	var l := UIKit.label(text, size, col, font if font else UIKit.font_regular)
	return l

## Retrato de un personaje: el primer cuadro de su hoja, x2 (o x1.6 si es muy alto).
func _portrait(id: String, scale := 2.0) -> Control:
	var path := "res://assets/chars/%s_idle.png" % id
	var holder := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.17, 0.15, 0.18)
	sb.set_corner_radius_all(6)
	holder.add_theme_stylebox_override("panel", sb)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var at := AtlasTexture.new()
		at.atlas = tex
		# recorta lo vacío de arriba (los personajes bajos se ven más grandes)
		var top := 8
		var img := tex.get_image()
		if img:
			top = clampi(img.get_used_rect().position.y - 6, 0, 40)
		var fw := tex.get_width() / 2
		at.region = Rect2(0, top, fw, tex.get_height() - top)
		tr.texture = at
		tr.custom_minimum_size = Vector2(fw, tex.get_height() - top) * scale
	else:
		tr.custom_minimum_size = Vector2(64, 96) * scale
	holder.add_child(tr)
	return holder

## Una opción: [tecla] (Botón). primary: ámbar, con la tecla de interactuar del aparato.
func _option(o: Dictionary, index: int) -> Control:
	var h := UIKit.hbox(8)
	var primary := bool(o.get("primary", false))
	var key := ""
	if primary:
		key = UIKit.interact_key()
	elif String(o.get("id", "")) == _cancel and _cancel != "":
		key = "B" if PadCursor.pad_in_use else "Esc"
	elif not PadCursor.pad_in_use:
		key = str(index + 1)
	if key != "":
		var kc := UIKit.keycap(key, 16)
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kc)
	var b := Button.new()
	b.text = String(o.get("text", "?"))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 19)
	b.custom_minimum_size = Vector2(float(o.get("min_w", 0.0)), 46)
	b.disabled = bool(o.get("disabled", false))
	if primary:
		_style_primary(b)
	var id := String(o.get("id", ""))
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		_finish(id))
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	h.add_child(b)
	_opts.append({"id": id, "btn": b, "primary": primary})
	return h

func _style_primary(b: Button) -> void:
	for pair in [["normal", "btn_primary9.png"], ["hover", "btn_primary_hover9.png"], ["pressed", "btn_primary_pressed9.png"]]:
		var sb := UIKit.nine(pair[1], 12, 15)
		if sb:
			sb.content_margin_left = maxf(sb.content_margin_left, 18.0)
			sb.content_margin_right = maxf(sb.content_margin_right, 18.0)
			b.add_theme_stylebox_override(pair[0], sb)

## La fila de opciones (se parte en dos filas si son muchas).
func _options_box(options: Array) -> Control:
	var v := UIKit.vbox(8)
	var row := UIKit.hbox(14)
	v.add_child(row)
	var n := 0
	for i in options.size():
		if n >= int(spec.get("per_row", 3)):
			row = UIKit.hbox(14)
			v.add_child(row)
			n = 0
		row.add_child(_option(options[i], i))
		n += 1
	return v

# ------------------------------------------------------------------ "talk": un personaje habla

func _build_talk() -> void:
	var h := UIKit.hbox(22)
	_panel.add_child(h)
	var who := String(spec.get("who", ""))
	if String(spec.get("icon", "")) != "":
		# --- SS2 SEASON: un icono en vez del retrato (la cuota, mientras Hesk no tiene su hoja)
		var ib := PanelContainer.new()
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0.2, 0.17, 0.15, 0.18)
		isb.set_corner_radius_all(6)
		isb.content_margin_left = 18
		isb.content_margin_right = 18
		isb.content_margin_top = 18
		isb.content_margin_bottom = 18
		ib.add_theme_stylebox_override("panel", isb)
		ib.add_child(UIKit.icon(String(spec["icon"]), 5.0))
		ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ib)
	elif who != "":
		var por := _portrait(who, float(spec.get("portrait_scale", 2.0)))
		por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(por)
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var head := UIKit.hbox(10)
	head.add_child(_ink(String(spec.get("title", Data.char_name(who))), 26, UIKit.font_bold))
	var sub := String(spec.get("sub", ""))
	if sub != "":
		var sl := _ink(sub, 16, UIKit.font_bold, INK_SOFT)
		sl.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(sl)
	v.add_child(head)
	var line := String(spec.get("line", ""))
	if line != "":
		var l := _ink(line, 21, UIKit.font_regular)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(float(spec.get("text_w", 470.0)), 0)
		v.add_child(l)
	var line2 := String(spec.get("line2", ""))   # --- SS2 SEASON: la segunda línea de un momento de historia
	if line2 != "":
		var l2 := _ink(line2, 21, UIKit.font_regular)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.custom_minimum_size = Vector2(float(spec.get("text_w", 470.0)), 0)
		v.add_child(l2)
	# la etiqueta de papel (el síntoma) con el icono de la cosa
	var tag_text := String(spec.get("tag", ""))
	if tag_text != "":
		var th := UIKit.hbox(10)
		var item := String(spec.get("item", ""))
		if item != "":
			var ic := UIKit.icon("res://assets/items/%s_closed.png" % item, 0.9)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			th.add_child(ic)
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UIKit.tag_style(10))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tcol := UIKit.kit_color("tag9.png", "text", UIKit.INK)
		if String(spec.get("tag_head", "")) != "":
			# --- SS2 SEASON: el rótulo del acertijo de Old Seven
			var tv := UIKit.vbox(-6)
			tv.add_child(UIKit.label(String(spec["tag_head"]), 15, Color(0.55, 0.3, 0.12), UIKit.font_bold))
			tv.add_child(UIKit.label(tag_text, 28, tcol, UIKit.font_hand))
			tag.add_child(tv)
		else:
			tag.add_child(UIKit.label(tag_text, 30, tcol, UIKit.font_hand))
		th.add_child(tag)
		v.add_child(th)
	var note := String(spec.get("note", ""))
	if note != "" or bool(spec.get("must_choose", false)):
		var nl := _ink(note, 17, UIKit.font_bold, INK_SOFT)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(float(spec.get("text_w", 470.0)), 0)
		nl.visible = note != ""
		v.add_child(nl)
		_note_lbl = nl   # --- SS2 SEASON: también para "Choose one: 1 or 2"
	var options: Array = spec.get("options", [])
	if not options.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(1, 2)
		v.add_child(gap)
		v.add_child(_options_box(options))

# ------------------------------------------------------------------ "parts": el puesto de Mags

func _build_parts() -> void:
	var v := UIKit.vbox(14)
	_panel.add_child(v)
	var top := UIKit.hbox(18)
	v.add_child(top)
	var por := _portrait("mags", 1.5)
	top.add_child(por)
	var tv := UIKit.vbox(6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_ink("Mags's parts", 26, UIKit.font_bold))
	var said := _ink(String(spec.get("line", Data.MARKET_LINES["mags_hello"])), 20)
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.custom_minimum_size = Vector2(420, 0)
	tv.add_child(said)
	_note_lbl = said   # --- SS2 SEASON: Mags contesta aquí
	var ch := UIKit.hbox(6)
	ch.add_child(UIKit.ui_icon("credits", 2.0))
	_credits_lbl = _ink("", 22, UIKit.font_bold)
	ch.add_child(_credits_lbl)
	ch.add_child(_ink("to spend", 16, UIKit.font_bold, INK_SOFT))
	tv.add_child(ch)
	top.add_child(tv)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var i := 0
	for part in _stock_parts():   # --- SS2 SEASON: el surtido de hoy (hasta 8) o, sin él, todas
		grid.add_child(_part_cell(String(part), i))
		i += 1
	# --- SS2 SEASON: el cajón de "tal cual" (cosas rotas baratas: van a lo roto, para reacondicionar y vender)
	var asis: Array = spec.get("asis", [])
	if not asis.is_empty():
		var ah := UIKit.hbox(12)
		var al := _ink("As-is bin", 18, UIKit.font_bold)
		al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ah.add_child(al)
		# (la víspera de Bronzemoon son 4: dos filas de 2 para que quepa a 1024x576)
		var ag := GridContainer.new()
		ag.columns = 2 if asis.size() == 4 else 3
		ag.add_theme_constant_override("h_separation", 12)
		ag.add_theme_constant_override("v_separation", 6)
		ah.add_child(ag)
		for k in asis.size():
			ag.add_child(_asis_cell(asis[k], k, 230.0 if asis.size() == 4 else 150.0))
		v.add_child(ah)
	# --- end SS2 SEASON
	var foot := UIKit.hbox(12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	var back := {"id": "close", "text": "Done", "primary": true, "min_w": 140}
	foot.add_child(_option(back, 9))
	v.add_child(foot)
	_refresh_parts()

func _part_cell(part: String, index: int) -> Control:
	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.18, 0.15, 0.12)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	cell.add_theme_stylebox_override("panel", sb)
	var h := UIKit.hbox(8)
	cell.add_child(h)
	if not PadCursor.pad_in_use:
		var kc := UIKit.keycap(str(index + 1), 14)
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kc)
	h.add_child(UIKit.icon("res://assets/parts/%s.png" % part, 1.5))
	var tv := UIKit.vbox(0)
	tv.custom_minimum_size = Vector2(108, 0)
	var nm := _ink(BenchData.part_name(part), 17, UIKit.font_bold)
	if _is_deal(part):
		nm.text += "  DEAL"   # --- SS2 SEASON (P1): la oferta del día de Mags
		nm.add_theme_color_override("font_color", Color(0.62, 0.22, 0.14))
	tv.add_child(nm)
	var cnt := _ink("", 14, UIKit.font_bold, INK_SOFT)
	tv.add_child(cnt)
	h.add_child(tv)
	var b := Button.new()
	b.text = "%d cr" % _price_of(part)   # --- SS2 SEASON: el precio de hoy (la rebaja de la Scour)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(76, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Buy one %s" % BenchData.part_name(part)
	b.pressed.connect(func(): buy_part(part))
	h.add_child(b)
	_part_rows[part] = {"count": cnt, "btn": b}
	return cell

## Compra una pieza en el puesto de Mags (precio fijo). true si alcanzó.
func buy_part(part: String) -> bool:
	if not _open or String(spec.get("kind", "")) != "parts":
		return false
	if not (part in _stock_parts()):
		return false
	var price := _price_of(part)   # --- SS2 SEASON
	if not Game.spend_credits(price):
		Sfx.play("bad", 0.04, -6.0)
		return false
	Game.add_part(part, 1)
	Sfx.play("coins", 0.06, -4.0)
	bought.emit(part)
	_refresh_parts()
	return true

func _refresh_parts() -> void:
	if _credits_lbl:
		_credits_lbl.text = UIKit.num(Game.credits)
	for part in _part_rows:
		var r: Dictionary = _part_rows[part]
		(r["count"] as Label).text = "In drawer: %d" % Game.part_count(part)
		(r["btn"] as Button).disabled = not Game.can_afford(_price_of(part))
	# --- SS2 SEASON: lo de "tal cual"
	var asis: Array = spec.get("asis", [])
	for k in _asis_rows.size():
		var row: Dictionary = _asis_rows[k]
		var sold := bool(row.get("sold", false))
		(row["btn"] as Button).disabled = sold or k >= asis.size() or not Game.can_afford(int(asis[k]["price"]))
		(row["btn"] as Button).text = "Sold" if sold else "%d cr" % int(asis[k]["price"])

# --- SS2 SEASON: el surtido de Mags de hoy, sus precios y el cajón de "tal cual"
func _stock_parts() -> Array:
	var st: Array = spec.get("stock", [])
	if st.is_empty():
		return BenchData.PART_ORDER.duplicate()
	var out: Array = []
	for e in st:
		out.append(String(e["part"]))
	return out

func _is_deal(part: String) -> bool:
	for e in spec.get("stock", []):
		if String(e["part"]) == part:
			return bool(e.get("deal", false))
	return false

func _price_of(part: String) -> int:
	for e in spec.get("stock", []):
		if String(e["part"]) == part:
			return int(e["price"])
	return BenchData.part_price(part)

func _asis_cell(e: Dictionary, index: int, text_w := 150.0) -> Control:
	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.26, 0.12, 0.14)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", sb)
	var h := UIKit.hbox(8)
	cell.add_child(h)
	if not PadCursor.pad_in_use:
		var kc := UIKit.keycap(["9", "0", "-", "="][mini(index, 3)], 14)   # (la víspera de Bronzemoon hay 4)
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kc)
	h.add_child(UIKit.icon("res://assets/items/%s_closed.png" % String(e["item"]), 0.75))
	var tv := UIKit.vbox(-2)
	tv.custom_minimum_size = Vector2(text_w, 0)
	tv.add_child(_ink(BenchData.item_name(String(e["item"])), 16, UIKit.font_bold))
	var sym := UIKit.label("\"%s\"" % String(e.get("symptom", "")), 19, UIKit.kit_color("tag9.png", "text", UIKit.INK), UIKit.font_hand)
	sym.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sym.custom_minimum_size = Vector2(text_w, 0)
	tv.add_child(sym)
	h.add_child(tv)
	var b := Button.new()
	b.text = "%d cr" % int(e["price"])
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(76, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Buy it as-is (broken)"
	b.pressed.connect(func(): buy_asis(index))
	h.add_child(b)
	_asis_rows.append({"btn": b, "panel": cell, "sold": false})
	return cell

## Compra la cosa i del cajón de "tal cual" (Season la pasa a lo roto). true si alcanzó.
func buy_asis(i: int) -> bool:
	if not _open or String(spec.get("kind", "")) != "parts" or i < 0 or i >= _asis_rows.size():
		return false
	if bool(_asis_rows[i].get("sold", false)):
		return false
	# Season guarda la lista sin lo vendido: el índice de esta ventana pasa al de la lista de ahora
	var live := Season.asis_for()
	var want: Dictionary = (spec.get("asis", []) as Array)[i]
	var li := -1
	for k in live.size():
		if String(live[k]["item"]) == String(want["item"]) and String(live[k]["fault"]) == String(want["fault"]):
			li = k
			break
	if li < 0 or not Season.buy_asis(li):
		Sfx.play("bad", 0.04, -6.0)
		return false
	_asis_rows[i]["sold"] = true
	Sfx.play("coins", 0.06, -4.0)
	_say(String(SeasonData.TEXT["mags_asis"]))
	_refresh_parts()
	return true

## La línea de quien vende (Mags, Dolly) o el aviso de abajo.
func _say(text: String) -> void:
	if _note_lbl and is_instance_valid(_note_lbl):
		_note_lbl.text = text
		_note_lbl.visible = true
# --- end SS2 SEASON

# ------------------------------------------------------------------ "info": el cajón, el estante

func _build_info() -> void:
	var v := UIKit.vbox(12)
	_panel.add_child(v)
	v.add_child(_ink(String(spec.get("title", "")), 26, UIKit.font_bold))
	var sub := String(spec.get("sub", ""))
	if sub != "":
		var sl := _ink(sub, 18, UIKit.font_regular, INK_SOFT)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(560, 0)
		v.add_child(sl)
	var rows: Array = spec.get("rows", [])
	if rows.is_empty():
		v.add_child(_ink(String(spec.get("empty", "Nothing here yet.")), 20, UIKit.font_bold, INK_SOFT))
	else:
		var grid := GridContainer.new()
		grid.columns = int(spec.get("columns", 3))
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 8)
		v.add_child(grid)
		for r in rows:
			var h := UIKit.hbox(8)
			var icon := String(r.get("icon", ""))
			if icon != "":
				h.add_child(UIKit.icon(icon, float(r.get("scale", 1.5))))
			var tv := UIKit.vbox(0)
			tv.add_child(_ink(String(r.get("text", "")), 18, UIKit.font_bold))
			var s2 := String(r.get("sub", ""))
			if s2 != "":
				tv.add_child(_ink(s2, 15, UIKit.font_bold, Color(0.55, 0.36, 0.12) if r.get("warm", false) else INK_SOFT))
			h.add_child(tv)
			grid.add_child(h)
	var foot := UIKit.hbox(12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(_option({"id": "close", "text": String(spec.get("close_text", "Close")), "primary": true, "min_w": 130}, 0))
	v.add_child(foot)

# ------------------------------------------------------------------ "menu": la pausa

func _build_menu() -> void:
	var v := UIKit.vbox(14)
	_panel.add_child(v)
	v.add_child(_ink(String(spec.get("title", "Paused")), 30, UIKit.font_bold))
	v.add_child(_ink(String(spec.get("sub", "The clock stops while this is open.")), 17, UIKit.font_bold, INK_SOFT))
	v.add_child(_slider_row("Music", Game.music_volume, func(x: float):
		Game.music_volume = x
		Sfx.apply_volumes()
		Game.save_settings()))
	v.add_child(_slider_row("Sound", Game.sfx_volume, func(x: float):
		Game.sfx_volume = x
		Sfx.apply_volumes()
		Game.save_settings()
		Sfx.play("blip", 0.02, -6.0)))
	var note := _ink("Your game saves every morning and when the shop opens.", 16, UIKit.font_regular, INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 0)
	v.add_child(note)
	var opts: Array = [{"id": "resume", "text": String(spec.get("resume_text", "Resume")), "primary": true, "min_w": 150}]
	if bool(spec.get("calendar", false)):
		opts.append({"id": "calendar", "text": "Calendar", "min_w": 150})   # --- SS2 SEASON
	if bool(spec.get("can_quit", true)):
		opts.append({"id": "title", "text": "Quit to title", "min_w": 170})
	_cancel = "resume"
	v.add_child(_options_box(opts))

func _slider_row(label: String, value: float, on_change: Callable) -> Control:
	var h := UIKit.hbox(14)
	var l := _ink(label, 20, UIKit.font_bold)
	l.custom_minimum_size = Vector2(80, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(300, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := _ink("%d%%" % int(round(value * 100.0)), 18, UIKit.font_bold, INK_SOFT)
	pct.custom_minimum_size = Vector2(56, 0)
	s.value_changed.connect(func(x: float):
		pct.text = "%d%%" % int(round(x * 100.0))
		on_change.call(x))
	h.add_child(s)
	h.add_child(pct)
	return h

# ------------------------------------------------------------------ --- SS2 SEASON: el patio de Dolly

func _build_fittings() -> void:
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	var top := UIKit.hbox(16)
	v.add_child(top)
	top.add_child(_portrait("vendor", 1.0))
	var tv := UIKit.vbox(6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UIKit.hbox(10)
	head.add_child(_ink("Dolly's Fittings", 26, UIKit.font_bold))
	var hs := _ink(String(SeasonData.DOLLY["sub"]), 16, UIKit.font_bold, INK_SOFT)
	hs.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(hs)
	tv.add_child(head)
	var rows := Season.fittings_on_sale()
	var all_owned := true
	for f in rows:
		if not bool(f["owned"]):
			all_owned = false
	var said := _ink(String(SeasonData.DOLLY["all" if all_owned else "hello"]), 18)
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.custom_minimum_size = Vector2(470, 0)
	tv.add_child(said)
	_note_lbl = said
	var ch := UIKit.hbox(6)
	ch.add_child(UIKit.ui_icon("credits", 2.0))
	_credits_lbl = _ink("", 22, UIKit.font_bold)
	ch.add_child(_credits_lbl)
	ch.add_child(_ink("to spend · installed when you open", 16, UIKit.font_bold, INK_SOFT))
	tv.add_child(ch)
	top.add_child(tv)
	# "Done" arriba a la derecha (así entra entero en 1024x576)
	var done := _option({"id": "close", "text": "Done", "primary": true, "min_w": 130}, 9)
	done.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(done)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for i in rows.size():
		grid.add_child(_fitting_cell(rows[i], i))
	_refresh_fittings()

func _fitting_cell(f: Dictionary, index: int) -> Control:
	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.18, 0.15, 0.12)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	cell.add_theme_stylebox_override("panel", sb)
	cell.custom_minimum_size = Vector2(368, 0)
	var h := UIKit.hbox(8)
	cell.add_child(h)
	if not PadCursor.pad_in_use:
		var kc := UIKit.keycap(str(index + 1), 14)
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kc)
	var tv := UIKit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_ink(String(f["name"]), 17, UIKit.font_bold))
	var d := _ink(String(f["detail"]), 14, UIKit.font_regular, INK)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(220, 0)
	tv.add_child(d)
	var sub := _ink("", 14, UIKit.font_bold, INK_SOFT)
	tv.add_child(sub)
	h.add_child(tv)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(84, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := String(f["id"])
	b.pressed.connect(func(): buy_fitting(id))
	h.add_child(b)
	_fit_rows[id] = {"btn": b, "sub": sub, "panel": cell, "sb": sb}
	return cell

## Compra una mejora en el patio de Dolly (precio fijo). true si se pudo.
func buy_fitting(id: String) -> bool:
	if not _open or String(spec.get("kind", "")) != "fittings":
		return false
	var row := {}
	for f in Season.fittings_on_sale():
		if String(f["id"]) == id:
			row = f
	if row.is_empty():
		return false
	if bool(row["locked"]):
		Sfx.play("bad", 0.04, -6.0)
		_say(String(SeasonData.DOLLY["locked"]))
		return false
	if bool(row["owned"]):
		return false
	if not Season.buy_fitting(id):
		Sfx.play("bad", 0.04, -6.0)
		_say(String(SeasonData.DOLLY["broke"]))
		return false
	Sfx.play("coins", 0.06, -4.0)
	Sfx.play("squeak", 0.05, -8.0)
	_say(String(SeasonData.DOLLY["bought"]))
	bought_fitting.emit(id)
	_refresh_fittings()
	return true

func _refresh_fittings() -> void:
	if _credits_lbl:
		_credits_lbl.text = UIKit.num(Game.credits)
	for f in Season.fittings_on_sale():
		var r: Dictionary = _fit_rows.get(String(f["id"]), {})
		if r.is_empty():
			continue
		var b: Button = r["btn"]
		var sub: Label = r["sub"]
		var sb: StyleBoxFlat = r["sb"]
		if bool(f["owned"]):
			b.text = "Owned"
			b.disabled = true
			sub.text = "Installed in the shop"
			sub.add_theme_color_override("font_color", Color(0.2, 0.42, 0.14))
			sb.bg_color = Color(0.3, 0.5, 0.25, 0.14)
		elif bool(f["locked"]):
			b.text = "%d cr" % int(f["cost"])
			b.disabled = true
			sub.text = String(f["why"])
			sub.add_theme_color_override("font_color", INK_SOFT)
			sb.bg_color = Color(0.22, 0.18, 0.15, 0.06)
		else:
			b.text = "%d cr" % int(f["cost"])
			b.disabled = not bool(f["can_buy"])
			sub.text = Season.tradeoff_line(int(f["cost"])) if bool(f["can_buy"]) else "Needs %d cr more" % (int(f["cost"]) - Game.credits)
			sub.add_theme_color_override("font_color", Color(0.5, 0.32, 0.06) if bool(f["can_buy"]) else Color(0.6, 0.22, 0.14))
			sb.bg_color = Color(0.22, 0.18, 0.15, 0.12)

# ------------------------------------------------------------------ --- SS2 SEASON: el calendario de la temporada

func _build_calendar() -> void:
	var v := UIKit.vbox(10)
	_panel.add_child(v)
	var head := UIKit.hbox(10)
	head.add_child(UIKit.ui_icon("calendar", 2.5))
	var hv := UIKit.vbox(-4)
	hv.add_child(_ink("THE STARFALL SEASON" if Game.is_campaign() else "KEEP TRADING", 14, UIKit.font_bold, INK_SOFT))
	hv.add_child(_ink("Notice board", 26, UIKit.font_bold))
	head.add_child(hv)
	v.add_child(head)
	var nd := Season.next_dues()
	var sub := ""
	if int(nd["night"]) > 0:
		sub = "%s %d cr on night %d. You have %d cr." % ["Upkeep" if bool(nd.get("upkeep", false)) else "Next dues:",
			int(nd["amount"]) + int(nd["debt"]), int(nd["night"]), Game.credits]
	v.add_child(_ink(sub, 17, UIKit.font_bold, INK_SOFT))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var first := 1 if Game.day <= SeasonData.LAST_DAY else Game.day
	var last := SeasonData.LAST_DAY if Game.day <= SeasonData.LAST_DAY else Game.day + 9
	for d in range(first, last + 1):
		grid.add_child(_day_cell(d))
	var foot := UIKit.hbox(12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	var line := _ink("Every happy customer is a star on the Lantern Board.", 15, UIKit.font_regular, INK_SOFT)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(line)
	foot.add_child(_option({"id": "close", "text": "Close", "primary": true, "min_w": 130}, 0))
	v.add_child(foot)

func _day_cell(d: int) -> Control:
	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var today := d == Game.day
	var past := d < Game.day
	sb.bg_color = Color(0.95, 0.72, 0.3, 0.32) if today else (Color(0.22, 0.18, 0.15, 0.06) if past else Color(0.22, 0.18, 0.15, 0.13))
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.62, 0.38, 0.1)
	sb.set_border_width_all(2 if today else 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", sb)
	cell.custom_minimum_size = Vector2(142, 104)
	var tv := UIKit.vbox(0)
	cell.add_child(tv)
	var top := UIKit.hbox(4)
	top.add_child(_ink("DAY %d" % d + ("  ✓" if past else ""), 14, UIKit.font_bold, INK_SOFT if past else INK))
	tv.add_child(top)
	var ev := Season.event(d)
	var tl := _ink(Season.title(d), 15, UIKit.font_bold, INK_SOFT if past else INK)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(128, 0)
	tv.add_child(tl)
	var bh := UIKit.hbox(4)
	if ev != "":
		var ip := "res://assets/ui/%s.png" % String(SeasonData.EVENTS[ev].get("icon", "event_" + ev))
		if ResourceLoader.exists(ip):
			bh.add_child(UIKit.icon(ip, 1.0))
	var du := Season.dues_of(d)
	if du > 0:
		var dl := _ink("Dues %d" % du if SeasonData.DUES.has(d) else "Upkeep %d" % du, 14, UIKit.font_bold,
			Color(0.2, 0.42, 0.14) if d in Game.dues_paid else Color(0.6, 0.22, 0.14))
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bh.add_child(dl)
	tv.add_child(bh)
	if past:
		cell.modulate.a = 0.75
	return cell

# ------------------------------------------------------------------ teclado

func _input(ev: InputEvent) -> void:
	if not _open or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode
	var handled := true
	var kind := String(spec.get("kind", ""))
	if k == KEY_ESCAPE:
		if bool(spec.get("must_choose", false)):
			flash_choose()   # --- SS2 SEASON: un momento con dos opciones no se cierra con Esc / B
		elif _cancel != "":
			_finish(_cancel)
		elif kind in ["info", "parts", "fittings", "calendar"]:
			_finish("close")
		else:
			handled = false
	elif k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		var done := false
		for o in _opts:
			if o["primary"] and not (o["btn"] as Button).disabled:
				_finish(o["id"])
				done = true
				break
		handled = done
	elif k == KEY_0 and kind == "parts":
		buy_asis(1)   # --- SS2 SEASON: la segunda cosa de "tal cual"
	elif k == KEY_MINUS and kind == "parts":
		buy_asis(2)   # --- SS2 SEASON: la tercera y la cuarta (la víspera de Bronzemoon)
	elif k == KEY_EQUAL and kind == "parts":
		buy_asis(3)
	elif k >= KEY_1 and k <= KEY_9:
		var i := k - KEY_1
		if kind == "parts":
			# --- SS2 SEASON: 1-8 el surtido de hoy, 9 la primera cosa de "tal cual"
			var stock := _stock_parts()
			if i < stock.size() and (i < 8 or (spec.get("asis", []) as Array).is_empty()):
				buy_part(String(stock[i]))
			elif i == 8:
				buy_asis(0)
		elif kind == "fittings":
			if i < SeasonData.FITTING_ORDER.size():
				buy_fitting(String(SeasonData.FITTING_ORDER[i]))
		elif i < _opts.size() and not (_opts[i]["btn"] as Button).disabled:
			_finish(_opts[i]["id"])
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

## --- SS2 SEASON: "Choose one: 1 or 2" parpadea en la nota (Esc / B sobre un momento con dos opciones).
func flash_choose() -> void:
	if _note_lbl == null or not is_instance_valid(_note_lbl):
		return
	_note_lbl.text = String(SeasonData.TEXT["choose_one_pad" if PadCursor.pad_in_use else "choose_one"])
	_note_lbl.visible = true
	_note_lbl.add_theme_color_override("font_color", Color(0.62, 0.22, 0.14))
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_property(_note_lbl, "modulate:a", 0.25, 0.12)
	_flash_tw.tween_property(_note_lbl, "modulate:a", 1.0, 0.12)
	_flash_tw.tween_property(_note_lbl, "modulate:a", 0.25, 0.12)
	_flash_tw.tween_property(_note_lbl, "modulate:a", 1.0, 0.12)
	Sfx.play("bad", 0.04, -10.0)
