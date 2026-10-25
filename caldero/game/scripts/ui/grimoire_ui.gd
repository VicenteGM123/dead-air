extends Node
class_name GrimoireUI
## R3 MAGIC3 · El LIBRO DE RUNAS de la maestra, en el escritorio de la biblioteca (la estación "biblioteca").
## Un libro abierto de verdad (tapas de cuero, dos hojas de pergamino: assets/ui/grimoire_*.png, tools/arte/magic_art.py)
## con dos modos, que se cambian con los marcapáginas de arriba:
##  - RUNAS (hojear): a la izquierda las runas (las aprendidas con su glifo; las otras, un contorno en blanco) y tus
##    tintas; a la derecha la runa elegida en grande, la tinta que pide y lo que hace, en pocas palabras.
##  - ENCANTAR: a la izquierda el estante (elige la poción) y su etiqueta; a la derecha la runa, los cinco tinteros
##    (moja la pluma en la tinta de la runa) y «Trazar»: la runa se traza sobre la etiqueta (scripts/ui/rune_game.gd).
##    Trazo perfecto = 3 estrellas, a tiempo = 2, se acabó la vela = 1. La poción queda con "rune" / "rune_stars"
##    (Game.enchant). Si un cliente espera, su pedido está clavado en la hoja y «Entregar» se la lleva al mostrador.
## Ratón, teclado (flechas + Intro o Espacio; Esc cierra, o suelta la pluma) y mando (PadCursor: A / B / LB / RB).
## main.gd lo crea en _ready() y lo abre en _open_grimoire().

signal enchanted(potion: Dictionary, stars: int)

const BOOK := Vector2(1440, 870)          # el libro a 3x (grimoire_book.png mide 480x290)
const LEFT := Rect2(66, 54, 600, 738)      # zona útil de la hoja izquierda (coordenadas del libro)
const RIGHT := Rect2(774, 54, 600, 738)
const INK := Color("3a2618")
const INK_SOFT := Color("6b5236")
const INK_FAINT := Color(0.42, 0.32, 0.2, 0.5)
const CREAM := Color("f4e9cf")
const GREEN := Color("4e6b3a")
const WAX := Color("9e2b25")
const BRASS := Color("c9a15a")

var main                     # main.gd (customer_ready, current, _on_potion)
var ui: GameUI
var ov: Overlays
var world: ShopWorld
var busy := false            # la pluma está trazando
var demo_auto := -1.0        # capturas y bot: la runa se traza sola hasta esta fracción
var mode := "browse"         # "browse" (hojear) o "enchant" (encantar)
var _sel := ""               # runa elegida
var _pot_key := {}           # poción elegida (id, potencia y runas: se busca con Game.find_potion)
var _ink := ""               # tinta en la pluma
var _root: Control
var _left: Control
var _right: Control
var _tabs := {}
var _note: Control           # la nota de la maestra (la primera vez)
var _msg: Label              # un aviso corto en la hoja derecha
var _game: RuneGame
var _trace_rune := ""
var _trace_key := {}
var _trace_done := false
var _trace_stars := 1
var _status: Label           # la línea de estado de la hoja derecha (el aviso corto la tapa un momento)
var _last_enchanted := {}
var _kb := false             # se está usando el teclado (foco visible)
var _focus_key := ""
var _focus_sb: StyleBoxFlat
var _glow_t := 0.0
var _announcing := false
var _celebrate_stars := 0
var _tip_done := false
var bot_fail := ""           # por qué falló bot_enchant (pruebas)

func setup(m) -> void:
	main = m
	ui = m.ui
	ov = m.ov
	world = m.world
	ov.closed.connect(func(id: String):
		if id == "grimoire":
			_on_closed())

func _ready() -> void:
	Sfx.magic_load()
	UIKit.load_fonts()
	_focus_sb = StyleBoxFlat.new()
	_focus_sb.draw_center = false
	_focus_sb.border_color = Color("f0d58a")
	_focus_sb.set_border_width_all(4)
	_focus_sb.set_corner_radius_all(10)
	_focus_sb.expand_margin_left = 4
	_focus_sb.expand_margin_right = 4
	_focus_sb.expand_margin_top = 4
	_focus_sb.expand_margin_bottom = 4
	Game.level_up.connect(func(_lv): _announce_pages.call_deferred())
	Game.journal_changed.connect(func(): _announce_pages.call_deferred())
	Game.magic_changed.connect(func(): _announce_pages.call_deferred())

func _process(delta: float) -> void:
	# el escritorio suelta chispitas mientras el grimorio espera (sin abrir, o con páginas nuevas)
	_glow_t += delta
	if _glow_t >= 2.4:
		_glow_t = 0.0
		if world and world.visible and world.grimoire_sprite and Game.desk_glows() and not ov.is_open():
			world.spawn_sparkles(world.grimoire_sprite.global_position + Vector3(0, 0.3, 0.15), Color(1.3, 1.1, 1.9), 6)
	if busy and (not is_instance_valid(_game) or ov.current != "grimoire"):
		if _trace_done:
			_commit_trace()   # ya estaba trazada
		busy = false   # el libro se cerró por otro lado mientras trazaba: no se gastó nada
	if _ticket_was and ov.current != "grimoire":
		_hud_ticket(true)   # (cerrado sin avisar: close(false))

## Está abierto el libro.
func is_open() -> bool:
	return ov.current == "grimoire" and is_instance_valid(_root)

# ------------------------------------------------------------------ abrir

## Abre el libro (la alquimista ya está en el escritorio). La primera vez: la nota de la maestra y la runa de Prisa.
## Si un cliente espera una poción con runas y está en el estante, se abre en ENCANTAR con esa poción y esa runa.
func open() -> void:
	if ov.is_open() or busy:
		return
	Sfx.play("grimoire", 0.03, -3.0)
	var first := not Game.magic_unlocked
	if first:
		Game.unlock_magic()
	Game.new_rune_pages()
	var target := _order_target()
	if first:
		show_book("prisa", "browse")
		_show_note()
	elif not target.is_empty():
		show_book(target["rune"], "enchant", target["index"])
	elif not Game.order_runes(_order()).is_empty():
		show_book(Game.order_runes(_order())[0], "browse")   # la runa que pide el cliente (la poción aún no está)
	else:
		show_book("", "browse")

## El pedido del cliente que espera, si le falta una runa a su poción del estante: {"index", "rune"} (o {}).
func _order_target() -> Dictionary:
	var req := _order()
	if req.is_empty() or Game.order_runes(req).is_empty():
		return {}
	for i in Game.potions.size():
		var p: Dictionary = Game.potions[i]
		if p["id"] != Story.wanted(req):
			continue
		var r := Game.next_rune_for(p, req)
		if r != "" and Game.enchant_problem(i, r) in ["", "ink"]:
			return {"index": i, "rune": r}
	return {}

## El pedido del cliente que espera en el mostrador ({} si no hay).
func _order() -> Dictionary:
	if main == null or not main.customer_ready or not is_instance_valid(main.customer):
		return {}
	var c: Dictionary = main.current
	if c.is_empty() or c.get("kind", "") == "return":
		return {}
	return c

## Abre el libro (o lo rehace si ya está abierto). sel: la runa; m: "browse" o "enchant"; potion: índice del estante.
func show_book(sel := "", m := "", potion := -1) -> void:
	if m != "":
		mode = m
	if sel != "" and Data.RUNES.has(sel):
		_sel = sel
	if _sel == "" or not Data.RUNES.has(_sel):
		_sel = _default_rune()
	if potion >= 0 and potion < Game.potions.size():
		_pot_key = Game.potions[potion].duplicate()
	_ink = ""
	if not is_open():
		_build_book()
		ov._open("grimoire", _root)
		_hud_ticket(false)
	_refresh()

func _default_rune() -> String:
	for id in Data.RUNE_ORDER:
		if Game.page_is_new(id):
			return id
	var known := Game.known_runes()
	return known[0] if not known.is_empty() else Data.RUNE_ORDER[0]

# ------------------------------------------------------------------ el libro (tapas, hojas, marcapáginas)

func _build_book() -> void:
	_root = Control.new()
	_root.custom_minimum_size = BOOK
	_root.size = BOOK
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# marcapáginas (asoman por arriba; las tapas tapan su base)
	_tabs.clear()
	var tx := 150.0
	for t in [["browse", "Runes", "res://assets/icons/rune_prisa.png"], ["enchant", "Enchant", "res://assets/icons/pot_sueno_profundo.png"]]:
		var b := TextureButton.new()
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.position = Vector2(tx, -58)
		b.size = Vector2(52, 24) * 3.0
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_stylebox_override("focus", _focus_sb)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.set_meta("fk", "tab_" + t[0])
		var kind: String = t[0]
		b.pressed.connect(func(): _set_mode(kind))
		b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
		var h := UIKit.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.position = Vector2(0, 6)
		h.size = Vector2(156, 44)
		b.add_child(h)
		h.add_child(UIKit.icon(t[2], 2.0))
		h.add_child(UIKit.shadow(UIKit.label(t[1], 26, CREAM, UIKit.font_sc_bold), 2))
		_root.add_child(b)
		_tabs[kind] = b
		tx += 186.0
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/grimoire_book.png")
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = BOOK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_left = Control.new()
	_left.position = LEFT.position
	_left.size = LEFT.size
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_left)
	_right = Control.new()
	_right.position = RIGHT.position
	_right.size = RIGHT.size
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_right)
	var close := TextureButton.new()
	close.texture_normal = load("res://assets/ui/grimoire_close.png")
	close.texture_hover = load("res://assets/ui/grimoire_close_hover.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_SCALE
	close.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	close.size = Vector2(54, 54)
	close.position = Vector2(BOOK.x - 40, -24)
	close.tooltip_text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_ALL
	close.add_theme_stylebox_override("focus", _focus_sb)
	close.set_meta("fk", "close")
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		if busy:
			_cancel_trace()
		ov.close())
	_root.add_child(close)
	_note = null

func _set_mode(m: String) -> void:
	if busy or m == mode:
		return
	Sfx.play("page", 0.08, -6.0)
	mode = m
	_ink = ""
	if m == "enchant":
		var t := _order_target()
		if not t.is_empty():
			_pot_key = Game.potions[t["index"]].duplicate()
			_sel = t["rune"]
		elif not Game.rune_known(_sel) and not Game.known_runes().is_empty():
			_sel = Game.known_runes()[0]
	_refresh()

## Rehace las dos hojas según el modo (sin cerrar el libro).
func _refresh() -> void:
	if not is_instance_valid(_root):
		return
	var fo := _root.get_viewport().gui_get_focus_owner() if _root.is_inside_tree() else null
	if fo and _root.is_ancestor_of(fo) and fo.has_meta("fk"):
		_focus_key = String(fo.get_meta("fk"))
	for page in [_left, _right]:
		for c in page.get_children():
			page.remove_child(c)
			c.queue_free()
	_msg = null
	_status = null
	for k in _tabs:
		var on: bool = k == mode
		var b: TextureButton = _tabs[k]
		b.texture_normal = load("res://assets/ui/grimoire_tab_%s.png" % ("on" if on else "off"))
		b.texture_hover = load("res://assets/ui/grimoire_tab_%s.png" % ("on" if on else "hover"))
		b.position.y = -64.0 if on else -54.0
		b.disabled = busy
	if mode == "enchant":
		_enchant_left()
		_enchant_right()
	else:
		_browse_left()
		_browse_right()
	if is_instance_valid(_note):
		_note.move_to_front()
	if _kb and not busy:
		_restore_focus.call_deferred()

# ------------------------------------------------------------------ piezas

func _lbl(text: String, size: int, col := INK, font: Font = null, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	# --- R3 MERGE: lo que el libro dice «a mano» (la cursiva: efectos, avisos, la nota de la maestra) usa la letra de los
	# papeles (UI-PAPER: PaperKit.font_hand, Caveat), un poco más grande porque es más estrecha. Títulos y botones: Alegreya.
	if font != null and font == UIKit.font_italic:
		PaperKit.load_fonts()
		return UIKit.label(text, int(round(size * 1.18)), col, PaperKit.font_hand, align)
	# --- end R3 MERGE
	return UIKit.label(text, size, col, font if font else UIKit.font_bold, align)

## Pone un control en la hoja, en una posición (y un tamaño, si se da) de la hoja.
func _put(c: Control, page: Control, pos: Vector2, size := Vector2.ZERO) -> Control:
	page.add_child(c)
	c.position = pos
	if size != Vector2.ZERO:
		c.size = size
	return c

## Un texto centrado en una franja de la hoja.
func _text(page: Control, text: String, y: float, size: int, col := INK, font: Font = null, w := 600.0, x := 0.0) -> Label:
	var l := _lbl(text, size, col, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_put(l, page, Vector2(x, y), Vector2(w, 0))
	return l

## Un botón sin fondo (la figura la dibuja draw_fn): medallones, frascos, tinteros.
func _flat_button(key: String, size: Vector2, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.flat = true
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", _focus_sb)
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = size
	b.size = size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.set_meta("fk", key)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func():
		Sfx.play("hover", 0.05, -14.0)
		b.queue_redraw())
	b.mouse_exited.connect(func(): b.queue_redraw())
	return b

## Estilo de textura (piezas de 9 cortes de magic_art.py, ya a 3x).
func _sbt(name: String, m := 15) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/%s.png" % name)
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 12
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb

## Un botón de cuero con letras claras (una o dos palabras). kind "gold": de lacre rojo (la acción principal).
func _leather(key: String, text: String, cb: Callable, kind := "", icon_path := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_stylebox_override("normal", _sbt("grimoire_btn_gold" if kind == "gold" else "grimoire_btn"))
	b.add_theme_stylebox_override("hover", _sbt("grimoire_btn_hover"))
	b.add_theme_stylebox_override("pressed", _sbt("grimoire_btn_pressed"))
	b.add_theme_stylebox_override("hover_pressed", _sbt("grimoire_btn_pressed"))
	b.add_theme_stylebox_override("disabled", _sbt("grimoire_btn_off"))
	b.add_theme_stylebox_override("focus", _focus_sb)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color("ffe8a8"))
	b.add_theme_color_override("font_pressed_color", Color("ffe8a8"))
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.72, 0.7))
	b.add_theme_font_override("font", UIKit.font_sc_bold)
	b.add_theme_font_size_override("font_size", 30)
	if icon_path != "":
		b.icon = load(icon_path)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
	b.custom_minimum_size = Vector2(0, 66)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("fk", key)
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	return b

## Centra horizontalmente un botón en la hoja a una altura (cuando ya conoce su tamaño).
func _center_x(c: Control, page: Control, y: float, w := 0.0) -> void:
	page.add_child(c)
	var cw := w if w > 0.0 else maxf(c.get_combined_minimum_size().x, c.size.x)
	c.size.x = cw
	c.position = Vector2((page.size.x - cw) / 2.0, y)

## Un adorno de tinta (una raya con un rombo) para separar.
func _rule(page: Control, y: float, w := 360.0) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(c, page, Vector2((page.size.x - w) / 2.0, y), Vector2(w, 14))
	c.draw.connect(func():
		var m := w / 2.0
		c.draw_line(Vector2(0, 7), Vector2(m - 14, 7), INK_FAINT, 2.0)
		c.draw_line(Vector2(m + 14, 7), Vector2(w, 7), INK_FAINT, 2.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(m, 0), Vector2(m + 7, 7), Vector2(m, 14), Vector2(m - 7, 7)]), INK_SOFT))

## El retrato de un personaje: el primer cuadro de su animación de reposo.
func _portrait(id: String, h: float) -> TextureRect:
	var tr := TextureRect.new()
	var path := "res://assets/chars/%s_idle.png" % Story.sprite_id(id)
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(0, 0, tex.get_width() / 2, tex.get_height())
		tr.texture = at
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(h * 2.0 / 3.0, h)
	tr.size = tr.custom_minimum_size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Una palomita (la runa del pedido ya va en la etiqueta).
func _check(size := 28.0, ok := true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.size = c.custom_minimum_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		if ok:
			c.draw_polyline(PackedVector2Array([Vector2(size * 0.15, size * 0.55), Vector2(size * 0.42, size * 0.8), Vector2(size * 0.88, size * 0.2)]), GREEN, 5.0, true)
		else:
			c.draw_arc(Vector2(size, size) / 2.0, size * 0.32, 0.0, TAU, 24, INK_FAINT, 3.0, true))
	return c

## Las estrellas (1 a 3) en una fila.
func _stars(n: int, scale := 1.5) -> HBoxContainer:
	var s := UIKit.stars(n, scale)
	s.alignment = BoxContainer.ALIGNMENT_CENTER
	return s

## El glifo de una runa dibujado en grande sobre el pergamino: un círculo mágico tenue, el trazo en el color de su
## tinta (con su sombra de tinta oscura) y el punto donde empieza. Es la misma forma que se traza.
func _glyph(id: String, side: float, locked := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(side, side)
	c.size = c.custom_minimum_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pts: Array = Data.RUNES[id]["points"] if Data.RUNES.has(id) else []
	var col: Color = Data.INKS[Game.rune_ink(id)]["color"] if Data.RUNES.has(id) else INK_SOFT
	c.draw.connect(func():
		var ctr := Vector2(side, side) / 2.0
		var R := side * 0.47
		if locked:
			for k in 40:
				if k % 2 == 0:
					c.draw_arc(ctr, R * 0.8, k * TAU / 40.0, (k + 1) * TAU / 40.0, 4, INK_FAINT, 4.0, true)
			return
		c.draw_arc(ctr, R, 0.0, TAU, 96, INK_FAINT, 3.0, true)
		c.draw_arc(ctr, R - 14.0, 0.0, TAU, 96, Color(INK_FAINT, 0.3), 2.0, true)
		for k in 24:
			var a := k * TAU / 24.0
			var l := 10.0 if k % 3 == 0 else 5.0
			c.draw_line(ctr + Vector2(cos(a), sin(a)) * (R - 14.0), ctr + Vector2(cos(a), sin(a)) * (R - 14.0 + l), Color(INK_FAINT, 0.45), 2.0, true)
		var pad := side * 0.2
		var inner := side - pad * 2.0
		var q: Array = []
		for p in pts:
			q.append(Vector2(pad, pad) + p * inner)
		for i in range(1, q.size()):
			c.draw_line(q[i - 1], q[i], Color(INK, 0.9), side * 0.075, true)
		for p in q:
			c.draw_circle(p, side * 0.0375, Color(INK, 0.9))
		for i in range(1, q.size()):
			c.draw_line(q[i - 1], q[i], col, side * 0.045, true)
		for p in q:
			c.draw_circle(p, side * 0.0225, col)
		for i in range(1, q.size()):
			c.draw_line(q[i - 1], q[i], col.lightened(0.6), side * 0.012, true)
		if not q.is_empty():
			# por dónde se empieza
			c.draw_circle(q[0], side * 0.05, INK)
			c.draw_circle(q[0], side * 0.032, Color(1, 0.97, 0.88)))
	return c

## Un medallón de runa (botón): su icono, o el contorno en blanco si no se sabe; la elegida lleva un aro de latón.
func _medal(id: String, side: float, selected: bool, cb: Callable, show_new := true) -> Button:
	var known := Game.rune_known(id)
	var b := _flat_button("rune_" + id, Vector2(side, side), cb, Data.RUNES[id]["name"] if known else "")
	var ic_path := ("res://assets/icons/rune_%s.png" % id) if known else "res://assets/ui/grimoire_rune_locked.png"
	var ic := UIKit.icon(ic_path, (side - 30.0) / 24.0)
	ic.position = Vector2(15, 15)
	ic.size = Vector2(side - 30.0, side - 30.0)
	b.add_child(ic)
	var is_new := known and show_new and Game.page_is_new(id)
	b.draw.connect(func():
		var ctr := Vector2(side, side) / 2.0
		if selected:
			b.draw_circle(ctr, side * 0.5, Color(1.0, 0.86, 0.45, 0.28))
			b.draw_arc(ctr, side * 0.48, 0.0, TAU, 64, BRASS, 5.0, true)
		elif b.is_hovered():
			b.draw_arc(ctr, side * 0.47, 0.0, TAU, 64, Color(BRASS, 0.7), 3.0, true)
		if is_new:
			var p := Vector2(side - 14, 14)
			b.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(4, -4), p + Vector2(11, 0), p + Vector2(4, 4),
				p + Vector2(0, 11), p + Vector2(-4, 4), p + Vector2(-11, 0), p + Vector2(-4, -4)]), Color("d8a43a")))
	return b

## Una poción del estante (botón): su frasco y el glifo de sus runas.
func _potion_button(i: int, side: Vector2, selected: bool) -> Button:
	var p: Dictionary = Game.potions[i]
	var tip := String(Data.POTIONS[p["id"]]["name"])
	for r in Game.potion_runes(p):
		tip += " · " + String(Data.RUNES[r["id"]]["name"])
	var b := _flat_button("pot_%d" % i, side, func(): _pick_potion(i), tip)
	var ic := UIKit.icon("res://assets/icons/pot_%s.png" % p["id"], 4.0)
	ic.position = Vector2((side.x - 64.0) / 2.0, 8)
	b.add_child(ic)
	var runes := Game.potion_runes(p)
	for k in runes.size():
		var r := UIKit.icon("res://assets/icons/rune_%s.png" % runes[k]["id"], 1.25)
		r.position = Vector2(side.x - 32.0, 2.0 + k * 28.0)
		b.add_child(r)
	var st := _stars(Game.stars_for(int(p["potency"])), 1.0)
	st.position = Vector2((side.x - 48.0) / 2.0, side.y - 22.0)
	st.size = Vector2(48, 16)
	b.add_child(st)
	b.draw.connect(func():
		var r := Rect2(Vector2(2, 2), side - Vector2(4, 4))
		if selected:
			b.draw_rect(r, Color(1.0, 0.86, 0.45, 0.25))
			b.draw_rect(r, BRASS, false, 4.0)
		elif b.is_hovered():
			b.draw_rect(r, Color(BRASS, 0.6), false, 3.0))
	return b

## Un tintero (botón): el icono de la tinta y cuántos frascos quedan. El elegido tiene la pluma mojada.
func _ink_button(ink: String, picked: bool, cb: Callable) -> Button:
	var n := Game.item_count(ink)
	var b := _flat_button("ink_" + ink, Vector2(104, 112), cb, String(Data.INKS[ink]["name"]))
	var ic := UIKit.icon("res://assets/icons/%s.png" % ink, 4.0)
	ic.position = Vector2(20, 4 if picked else 12)
	if n <= 0:
		ic.modulate = Color(0.55, 0.5, 0.48, 0.75)
	b.add_child(ic)
	var cnt := _lbl("×%d" % n, 26, INK if n > 0 else INK_FAINT)
	cnt.position = Vector2(0, 78)
	cnt.size = Vector2(104, 30)
	b.add_child(cnt)
	b.draw.connect(func():
		var ctr := Vector2(52, 44)
		if picked:
			b.draw_circle(ctr, 48, Color(1.0, 0.86, 0.45, 0.25))
			b.draw_arc(ctr, 48, 0.0, TAU, 48, BRASS, 4.0, true)
		elif b.is_hovered():
			b.draw_arc(ctr, 46, 0.0, TAU, 48, Color(BRASS, 0.6), 3.0, true))
	return b

## El pedido del cliente que espera, clavado en la hoja: su cara, la poción y las runas (con palomita las que ya van
## en la etiqueta de la poción elegida). w: ancho de la nota.
func _order_card(page: Control, pos: Vector2, w: float, p: Dictionary) -> Control:
	var req := _order()
	if req.is_empty():
		return null
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sbt("grimoire_note", 21))
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(w, 0)
	var h := UIKit.hbox(14)
	card.add_child(h)
	h.add_child(_portrait(String(req["who"]), 104.0))
	var v := UIKit.vbox(6)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	v.add_child(_lbl(Story.char_name(String(req["who"])), 26, INK, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_LEFT))
	var row := UIKit.hbox(8)
	v.add_child(row)
	var want := Story.wanted(req)
	row.add_child(UIKit.icon("res://assets/icons/pot_%s.png" % want, 3.0) if Game.discovered.has(want) else UIKit.icon("res://assets/icons/pot_desconocida.png", 3.0))
	var have := Game.potion_rune_ids(p) if not p.is_empty() and p.get("id", "") == want else []
	for r in Game.order_runes(req):
		row.add_child(_lbl("+", 30, INK_SOFT))
		row.add_child(UIKit.icon("res://assets/icons/rune_%s.png" % r, 2.0))
		row.add_child(_check(26.0, have.has(r)))
	_put(card, page, pos)
	_put(UIKit.icon("res://assets/ui/grimoire_pin.png", 3.0), page, pos + Vector2(w / 2.0 - 12.0, -16.0))
	return card

## Un aviso corto en la hoja derecha (sale y se va).
func _flash_msg(text: String, col := WAX) -> void:
	if not is_instance_valid(_right):
		return
	if is_instance_valid(_msg):
		_msg.queue_free()
	_msg = _lbl(text, 30, col, UIKit.font_italic)
	var y := 592.0
	var st := _status
	if is_instance_valid(st):
		y = st.position.y
		st.visible = false
	_put(_msg, _right, Vector2(0, y), Vector2(600, 36))
	_msg.modulate.a = 0.0
	var tw := _msg.create_tween()
	tw.tween_property(_msg, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(_msg, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		if is_instance_valid(st):
			st.visible = true)

func _shake(c: Control) -> void:
	if not is_instance_valid(c):
		return
	var x0 := c.position.x
	var tw := c.create_tween()
	for k in 3:
		tw.tween_property(c, "position:x", x0 + 7.0, 0.04)
		tw.tween_property(c, "position:x", x0 - 7.0, 0.04)
	tw.tween_property(c, "position:x", x0, 0.04)

# ------------------------------------------------------------------ RUNAS (hojear)

func _browse_left() -> void:
	_text(_left, "Runes", 6, 46, INK, UIKit.font_sc_bold)
	_text(_left, "%d / %d" % [Game.known_runes().size(), Data.RUNE_ORDER.size()], 60, 24, INK_SOFT, UIKit.font_italic)
	for i in Data.RUNE_ORDER.size():
		var id: String = Data.RUNE_ORDER[i]
		var col := i % 4
		var row := i / 4
		var pos := Vector2(14 + col * 146, 104 + row * 196)
		var b := _medal(id, 132.0, id == _sel, func(): _pick_rune(id))
		_put(b, _left, pos)
		var known := Game.rune_known(id)
		var nm := _lbl(String(Data.RUNES[id]["name"]) if known else "?", 24, INK if known else INK_FAINT)
		_put(nm, _left, pos + Vector2(-8, 134), Vector2(148, 30))
	_rule(_left, 478)
	# tus tintas
	for k in Data.INK_ORDER.size():
		var ink: String = Data.INK_ORDER[k]
		var n := Game.item_count(ink)
		var ic := UIKit.icon("res://assets/icons/%s.png" % ink, 4.0)
		ic.tooltip_text = String(Data.INKS[ink]["name"])
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		if n <= 0:
			ic.modulate = Color(0.55, 0.5, 0.48, 0.75)
		_put(ic, _left, Vector2(36 + k * 112, 500))
		_put(_lbl("×%d" % n, 26, INK if n > 0 else INK_FAINT), _left, Vector2(18 + k * 112, 566), Vector2(100, 30))
	_order_card(_left, Vector2(90, 612), 420.0, {})

func _browse_right() -> void:
	var d: Dictionary = Data.RUNES[_sel]
	var known := Game.rune_known(_sel)
	if not known:
		_text(_right, "Blank page", 14, 44, INK_FAINT, UIKit.font_sc_bold)
		_put(_glyph(_sel, 300.0, true), _right, Vector2(150, 110))
		var y := 450.0
		for way in _unlock_ways(_sel):
			var h := UIKit.hbox(14)
			h.alignment = BoxContainer.ALIGNMENT_CENTER
			h.add_child(way[0])
			h.add_child(_lbl(way[1], 30, INK_SOFT, UIKit.font_italic))
			_put(h, _right, Vector2(0, y), Vector2(600, 100))
			y += 120.0
		return
	Game.mark_page_read(_sel)
	_text(_right, String(d["name"]), 6, 56, INK, UIKit.font_sc_bold)
	_put(_glyph(_sel, 340.0), _right, Vector2(130, 88))
	# la tinta que pide (icono) y cuánta tienes
	var ink := Game.rune_ink(_sel)
	var h2 := UIKit.hbox(10)
	h2.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UIKit.icon("res://assets/icons/%s.png" % ink, 4.0)
	ic.tooltip_text = String(Data.INKS[ink]["name"])
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	h2.add_child(ic)
	h2.add_child(_lbl("×%d" % Game.item_count(ink), 30, INK if Game.item_count(ink) > 0 else WAX))
	_put(h2, _right, Vector2(0, 440), Vector2(600, 70))
	_text(_right, String(d["effect"]), 528, 34, INK, UIKit.font_italic, 540.0, 30.0)
	var go := _leather("go_enchant", "Enchant", func():
		_sel = _sel
		_set_mode("enchant"), "gold", "res://assets/icons/pot_sueno_profundo.png")
	_center_x(go, _right, 640, 300)

## Cómo se aprende una runa que todavía no se sabe: [[icono, unas palabras], ...].
func _unlock_ways(id: String) -> Array:
	var d: Dictionary = Data.RUNES[id]
	var out := []
	if d.has("shop"):
		var item: Dictionary = Data.MAGIC_ITEMS.get(String(d["shop"]), {})
		out.append([_portrait("tobias", 96.0), "Tobias · %d gold" % int(item.get("price", 0))])
	if d.has("gift"):
		var g: Dictionary = d["gift"]
		out.append([_portrait(String(g["hero"]), 96.0), "Gift from %s" % Story.char_name(String(g["hero"]))])
	if int(d.get("level", 99)) < Data.LEVELS.size():
		out.append([UIKit.icon("res://assets/icons/emote_gem.png", 4.0), "Renown: %s" % Game.level_name(int(d["level"]))])
	return out

func _pick_rune(id: String) -> void:
	if busy:
		return
	Sfx.play("page", 0.08, -8.0)
	_sel = id
	_ink = ""
	_refresh()

# ------------------------------------------------------------------ ENCANTAR

## La poción elegida (índice en el estante, -1 si no hay): la última elegida, o la que pide el cliente, o la primera.
func _pot_index() -> int:
	if not _pot_key.is_empty():
		var i := Game.find_potion(_pot_key)
		if i >= 0:
			return i
	var t := _order_target()
	if not t.is_empty():
		return t["index"]
	for i in Game.potions.size():
		if Game.potion_runes(Game.potions[i]).is_empty():
			return i
	return 0 if not Game.potions.is_empty() else -1

func _pick_potion(i: int) -> void:
	if busy or i < 0 or i >= Game.potions.size():
		return
	Sfx.play("click", 0.06, -6.0)
	_pot_key = Game.potions[i].duplicate()
	var r := Game.next_rune_for(Game.potions[i], _order())
	if r != "" and Game.rune_known(r) and Game.potions[i]["id"] == Story.wanted(_order()):
		_sel = r
	_ink = ""
	_refresh()

## Moja la pluma en un tintero. Tiene que ser la tinta de la runa (si no, el tintero tiembla y no se gasta nada).
func pick_ink(ink: String) -> void:
	if busy or mode != "enchant":
		return
	var b := _find_button("ink_" + ink)
	if Game.item_count(ink) <= 0:
		Sfx.play("sad", 0.0, -8.0)
		_shake(b)
		_flash_msg("No ink: Tobias or the cauldron")
		return
	if ink != Game.rune_ink(_sel):
		Sfx.play("sad", 0.0, -8.0)
		_shake(b)
		_flash_msg("That ink won't take on this rune")
		return
	Sfx.play("plop", 0.08, -4.0)
	_ink = ink
	_refresh()

func _find_button(key: String) -> Control:
	for page in [_left, _right]:
		if not is_instance_valid(page):
			continue
		for c in page.get_children():
			if c.has_meta("fk") and String(c.get_meta("fk")) == key:
				return c
	return null

func _enchant_left() -> void:
	_text(_left, "Enchant", 6, 46, INK, UIKit.font_sc_bold)
	var idx := _pot_index()
	if Game.potions.is_empty():
		_text(_left, "The shelf is empty.", 200, 32, INK_SOFT, UIKit.font_italic)
		_put(UIKit.icon("res://assets/icons/pot_desconocida.png", 8.0), _left, Vector2(236, 270))
		_order_card(_left, Vector2(90, 600), 420.0, {})
		return
	# el estante: 6 por fila
	var n := Game.potions.size()
	var per := 6
	var bw := Vector2(94, 112)
	for i in n:
		var row := i / per
		var col := i % per
		var in_row := mini(per, n - row * per)
		var x0 := (600.0 - in_row * (bw.x + 4.0)) / 2.0
		_put(_potion_button(i, bw, i == idx), _left, Vector2(x0 + col * (bw.x + 4.0), 72 + row * (bw.y + 6)))
	var top := 72.0 + ceili(n / float(per)) * (bw.y + 6) + 12.0
	if idx < 0:
		return
	var p: Dictionary = Game.potions[idx]
	# el frasco elegido, en grande, con su etiqueta colgando (centrado entre el estante y el pedido clavado)
	var big := UIKit.icon("res://assets/icons/pot_%s.png" % p["id"], 8.0)
	var by := top + maxf(0.0, (586.0 - top - 244.0) / 2.0)
	_put(big, _left, Vector2(56, by))
	_text(_left, String(Data.POTIONS[p["id"]]["name"]), by + 130, 28, INK, UIKit.font_sc_bold, 260.0, -10.0)
	_put(_tag(p), _left, Vector2(300, by - 4))
	var string := Control.new()
	string.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(string, _left, Vector2.ZERO, Vector2(600, 700))
	string.draw.connect(func():
		var a := Vector2(120, by + 28)
		var b := Vector2(300 + 34, by - 4 + 78)
		string.draw_polyline(PackedVector2Array([a, a.lerp(b, 0.5) + Vector2(0, 26), b]), Color("8a6e4a"), 3.0, true))
	string.move_to_front()
	# entregar, si el cliente espera (de lacre si la poción ya es justo lo que pidió)
	var req := _order()
	if not req.is_empty():
		var ready: bool = p["id"] == Story.wanted(req) and Game.next_rune_for(p, req) == ""
		var give := _leather("give", "Hand over", func(): _deliver(), "gold" if ready else "", "res://assets/icons/pot_%s.png" % p["id"])
		_put(give, _left, Vector2(330, by + 168))
		give.size = Vector2(250, 66)
	_order_card(_left, Vector2(90, 600), 420.0, p)

## La etiqueta de la poción: sus huecos (1, o 2 desde «Maestra de pociones") con las runas que ya lleva y sus estrellas.
func _tag(p: Dictionary) -> Control:
	var tag := TextureRect.new()
	tag.texture = load("res://assets/ui/grimoire_tag.png")
	tag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tag.stretch_mode = TextureRect.STRETCH_SCALE
	tag.size = Vector2(64, 40) * 4.0
	tag.custom_minimum_size = tag.size
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slots := Game.label_slots()
	var runes := Game.potion_runes(p)
	var side := 92.0 if slots == 1 else 70.0
	for k in slots:
		var cx := 146.0 if slots == 1 else 110.0 + k * 80.0
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = Vector2(cx - side / 2.0, 20)
		holder.size = Vector2(side, side + 30)
		tag.add_child(holder)
		if k < runes.size():
			var ic := UIKit.icon("res://assets/icons/rune_%s.png" % runes[k]["id"], side / 24.0)
			holder.add_child(ic)
			var st := _stars(int(runes[k]["stars"]), 1.0)
			st.position = Vector2((side - 48.0) / 2.0, side + 2)
			st.size = Vector2(48, 16)
			holder.add_child(st)
			if _celebrate_stars > 0 and k == runes.size() - 1:
				_pop(ic)
		else:
			var e := UIKit.icon("res://assets/ui/grimoire_rune_locked.png", side / 24.0)
			holder.add_child(e)
	return tag

func _pop(c: Control) -> void:
	c.pivot_offset = c.custom_minimum_size / 2.0
	c.scale = Vector2(1.6, 1.6)
	c.modulate = Color(2.0, 1.8, 1.2)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate", Color.WHITE, 0.6)

func _enchant_right() -> void:
	var known := Game.known_runes()
	if not Game.rune_known(_sel) and not known.is_empty():
		_sel = known[0]
	# las runas que sabes, en fila
	var n := known.size()
	var x0 := (600.0 - n * 74.0) / 2.0
	for i in n:
		var id: String = known[i]
		var b := _medal(id, 70.0, id == _sel, func(): _pick_rune(id), false)
		b.disabled = busy
		_put(b, _right, Vector2(x0 + i * 74.0, 2))
	var d: Dictionary = Data.RUNES[_sel]
	var ink := Game.rune_ink(_sel)
	var head := UIKit.hbox(12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(_lbl(String(d["name"]), 44, INK, UIKit.font_sc_bold))
	var need := UIKit.icon("res://assets/icons/%s.png" % ink, 3.0)
	need.tooltip_text = String(Data.INKS[ink]["name"])
	need.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(need)
	_put(head, _right, Vector2(0, 80), Vector2(600, 56))
	var idx := _pot_index()
	if busy:
		# la etiqueta en grande: aquí se traza la runa
		_game = RuneGame.new()
		_game.look = "label"
		_game.points = d["points"]
		_game.ink = Data.INKS[ink]["color"]
		_game.time_limit = 3.5 + 1.3 * d["points"].size()
		_game.auto_until = demo_auto
		_game.custom_minimum_size = Vector2(460, 460)
		_put(_game, _right, Vector2(70, 142), Vector2(460, 460))
		_game.finished.connect(_on_trace_finished)
		var how := "Join the dots in order"
		_status = _text(_right, how, 612, 28, INK_SOFT, UIKit.font_italic)
		var cancel := _leather("cancel", "Put down", func(): _cancel_trace())
		cancel.focus_mode = Control.FOCUS_NONE
		_center_x(cancel, _right, 662, 220)
		return
	_put(_glyph(_sel, 300.0), _right, Vector2(150, 140))
	_text(_right, String(d["effect"]), 446, 30, INK_SOFT, UIKit.font_italic, 560.0, 20.0)
	# los cinco tinteros
	for k in Data.INK_ORDER.size():
		var ik: String = Data.INK_ORDER[k]
		var b2 := _ink_button(ik, ik == _ink, func(): pick_ink(ik))
		_put(b2, _right, Vector2(26 + k * 112, 494))
	# trazar, o por qué todavía no
	var why := Game.enchant_problem(idx, _sel) if idx >= 0 else "none"
	var reason := {"none": "Brew a potion first", "same": "Already has it", "full": "Label full", "ink": "No ink: Tobias or the cauldron",
		"page": "Blank page"}
	if why == "" and _ink == "":
		_status = _text(_right, "Dip the quill", 614, 30, INK_SOFT, UIKit.font_italic)
	elif why != "":
		_status = _text(_right, String(reason.get(why, why)), 614, 30, WAX, UIKit.font_italic)
	else:
		_status = _text(_right, "", 614, 30, INK_SOFT, UIKit.font_italic)
	var go := _leather("trace", "Trace", func(): start_trace(), "gold", "res://assets/icons/%s.png" % ink)
	go.disabled = why != "" or _ink == ""
	_center_x(go, _right, 664, 280)

func _deliver() -> void:
	var idx := _pot_index()
	if busy or idx < 0:
		return
	ov.close()
	main._on_potion(idx)

# ------------------------------------------------------------------ trazar

## Empieza a trazar la runa elegida en la etiqueta de la poción elegida (con la pluma ya mojada en su tinta).
func start_trace() -> void:
	if busy or mode != "enchant" or not is_open():
		return
	var idx := _pot_index()
	var why := Game.enchant_problem(idx, _sel) if idx >= 0 else "none"
	if why != "":
		Sfx.play("sad", 0.0, -8.0)
		_flash_msg("Can't do that")
		return
	if _ink != Game.rune_ink(_sel):
		Sfx.play("sad", 0.0, -8.0)
		_flash_msg("Dip the quill")
		return
	busy = true
	_trace_done = false
	_trace_rune = _sel
	_trace_key = Game.potions[idx].duplicate()
	_pot_key = _trace_key.duplicate()
	if _root.is_inside_tree():
		_root.get_viewport().gui_release_focus()
	Sfx.play("quill", 0.05, -3.0)
	if world.grimoire_sprite:
		world.grimoire_sprite.modulate = Color(1.5, 1.4, 1.8)
	_refresh()

## Inscribe la runa ya trazada (gasta la tinta) y deja de trazar. Devuelve la poción encantada ({} si no se pudo).
func _commit_trace() -> Dictionary:
	if not busy or not _trace_done:
		return {}
	var idx := Game.find_potion(_trace_key)
	var p := Game.enchant(idx, _trace_rune, _trace_stars) if idx >= 0 else {}
	busy = false
	_game = null
	if world.grimoire_sprite:
		world.grimoire_sprite.modulate = Color.WHITE
	if not p.is_empty():
		_last_enchanted = p.duplicate()
		_pot_key = p.duplicate()
		_ink = ""
	return p

## Soltó la pluma (Esc, B o «Soltar»): no se gasta nada.
func _cancel_trace() -> void:
	if not busy or _trace_done:
		return
	busy = false
	_game = null
	if world.grimoire_sprite:
		world.grimoire_sprite.modulate = Color.WHITE
	_refresh()
	_flash_msg("Nothing was used up", INK_SOFT)

func _on_trace_finished(_perfect: bool) -> void:
	if not busy or _trace_done or not is_instance_valid(_game):
		return
	_trace_done = true
	_trace_stars = _game.stars()
	await get_tree().create_timer(0.9).timeout   # que se vea el destello de la runa
	if not busy:
		return   # (el libro se cerró en ese momento: _commit_trace ya la inscribió)
	var stars := _trace_stars
	var p := _commit_trace()
	if p.is_empty():
		_refresh()
		return
	# si el pedido pide otra runa, esa queda elegida
	var nxt := Game.next_rune_for(p, _order()) if p["id"] == Story.wanted(_order()) else ""
	if nxt != "" and Game.rune_known(nxt):
		_sel = nxt
	_celebrate_stars = stars
	_refresh()
	_celebrate_stars = 0
	Sfx.play("sparkle", 0.0, -3.0)
	if world.grimoire_sprite:
		world.spawn_sparkles(world.grimoire_sprite.global_position + Vector3(0, 0.45, 0.2), Color(1.6, 1.4, 2.0), 22)
	_flash_msg(["", "The rune came out weak", "Rune inscribed!", "Perfect stroke!"][clampi(stars, 1, 3)], GREEN if stars >= 2 else INK_SOFT)
	enchanted.emit(p, stars)

## Al cerrar el libro: si la poción encantada ya es lo que pide el cliente, Miga ronronea (la corazonada).
## El ticket del pedido (GameUI) se esconde mientras el libro está abierto: el pedido va clavado en la hoja.
var _ticket_was := false
func _hud_ticket(on: bool) -> void:
	var card = ui.get("order_card")
	if not (card is Control):
		return
	if not on:
		_ticket_was = card.visible
		card.visible = false
	elif _ticket_was:
		card.visible = true
		_ticket_was = false

func _on_closed() -> void:
	_hud_ticket(true)
	if busy and _trace_done:
		_commit_trace()   # se cerró justo después de trazar: la runa queda inscrita igual
	busy = false
	_game = null
	if world and world.grimoire_sprite:
		world.grimoire_sprite.modulate = Color.WHITE
	if not _last_enchanted.is_empty() and main.has_method("intuition_after_enchant"):
		main.intuition_after_enchant(_last_enchanted)
	_last_enchanted = {}
	if not Game.magic_unlocked:
		return
	if Game.magic_stats["runes"] == 1 and _order().is_empty() and not _tip_done:
		_tip_done = true
		ui.show_tip("It has its rune: hand it over from the [b]shelf[/b].")   # --- R3 MERGE: corto

# ------------------------------------------------------------------ la nota de la maestra (la primera vez)

func _show_note() -> void:
	if is_instance_valid(_note):
		_note.queue_free()
	_note = Control.new()
	_note.mouse_filter = Control.MOUSE_FILTER_STOP
	_note.position = Vector2(0, 0)
	_note.size = BOOK
	_root.add_child(_note)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.06, 0.04, 0.25)
	shade.size = BOOK
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.add_child(shade)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sbt("grimoire_note", 21))
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.custom_minimum_size = Vector2(560, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.rotation = deg_to_rad(-2.0)
	_note.add_child(card)
	card.position = Vector2(RIGHT.position.x + 20, 170)
	var v := UIKit.vbox(14)
	card.add_child(v)
	v.add_child(_lbl("From your teacher", 30, INK_SOFT, UIKit.font_sc_bold))
	var t := _lbl(String(Data.RUNE_TEXT["note"]), 30, INK, UIKit.font_italic)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(500, 0)
	v.add_child(t)
	var h := UIKit.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(UIKit.icon("res://assets/icons/rune_prisa.png", 3.0))
	h.add_child(_lbl("+", 32, INK_SOFT))
	for id in Game.MAGIC_STARTER:
		h.add_child(UIKit.icon("res://assets/icons/%s.png" % id, 4.0))
		h.add_child(_lbl("×%d" % int(Game.MAGIC_STARTER[id]), 30, INK))
	var ok := _leather("note_ok", "Got it", func(): dismiss_note(), "gold")
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ok)
	var pin := UIKit.icon("res://assets/ui/grimoire_pin.png", 3.0)
	pin.position = card.position + Vector2(266, -16)
	_note.add_child(pin)

func note_visible() -> bool:
	return is_instance_valid(_note)

func dismiss_note() -> void:
	if is_instance_valid(_note):
		Sfx.play("page", 0.05, -5.0)
		_note.queue_free()
		_note = null

# ------------------------------------------------------------------ teclado

func _input(ev: InputEvent) -> void:
	if not is_open() or not (ev is InputEventKey) or not ev.pressed:
		return
	if busy:
		if ev.keycode == KEY_ESCAPE and not ev.echo:
			_cancel_trace()
			get_viewport().set_input_as_handled()
		return
	if ev.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB]:
		_kb = true
		var fo := _root.get_viewport().gui_get_focus_owner()
		if fo == null or not _root.is_ancestor_of(fo):
			_restore_focus()
			get_viewport().set_input_as_handled()

## Pone el foco del teclado en el botón de antes (o en el principal de la hoja).
func _restore_focus() -> void:
	if not is_open() or busy:
		return
	if is_instance_valid(_note):
		var okb := _find_in(_note, "note_ok")
		if okb:
			okb.grab_focus()
		return
	var b := _find_in(_root, _focus_key) if _focus_key != "" else null
	if b == null:
		b = _find_in(_root, "trace" if mode == "enchant" else "rune_" + _sel)
	if b == null or (b is BaseButton and b.disabled):
		b = _find_in(_root, "rune_" + _sel)
	if b == null:
		b = _find_in(_root, "close")
	if b:
		b.grab_focus()

func _find_in(n: Node, key: String) -> Control:
	for c in n.get_children():
		if c is Control and c.has_meta("fk") and String(c.get_meta("fk")) == key and c.is_visible_in_tree():
			return c
		var r := _find_in(c, key)
		if r:
			return r
	return null

# ------------------------------------------------------------------ páginas nuevas

## Al subir de nivel, al terminar un capítulo de un viajero o al comprar la página de Tobías: anuncia las runas
## recién aprendidas (cuando no hay ningún panel abierto).
func _announce_pages() -> void:
	if _announcing or not Game.magic_unlocked:
		return
	_announcing = true
	var calm := 0.0
	while calm < 0.35:
		await get_tree().process_frame
		calm = 0.0 if ov.is_open() else calm + get_process_delta_time()
	_announcing = false
	var news := Game.new_rune_pages()
	if news.is_empty():
		return
	for id in news:
		var g: Dictionary = Data.RUNES[id].get("gift", {})
		if not g.is_empty() and Game.level() < int(Data.RUNES[id].get("level", 99)) and int(Game.hero_progress.get(g["hero"], 0)) >= int(g["chapter"]):
			ui.toast(String(g["text"]), UIKit.GOLD_BRIGHT, 4.5)
	var names: Array = news.map(func(id): return String(Data.RUNES[id]["name"]))
	var what: String = names[0] if names.size() == 1 else ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]
	ui.toast("New rune in the grimoire: %s" % what, UIKit.GOLD_BRIGHT, 4.0)
	if world and world.grimoire_sprite:
		world.spawn_sparkles(world.grimoire_sprite.global_position + Vector3(0, 0.4, 0.15), Color(1.4, 1.2, 1.9), 20)

# ------------------------------------------------------------------ el bot (pruebas automáticas)

## Va al escritorio, abre el grimorio por primera vez (lee la nota) y lo cierra. true si quedó abierto.
func bot_open() -> bool:
	if not world.at_station("biblioteca"):
		if not await world.go_station("biblioteca"):
			return false
	open()
	for i in 3:
		await get_tree().process_frame
	dismiss_note()
	if ov.current == "grimoire":
		ov.close()
	return Game.magic_unlocked

## Va al escritorio y encanta la poción index con la runa: el libro en ENCANTAR, la tinta de la runa y el trazo (un
## cursor automático: trazo perfecto). Devuelve la poción encantada ({} si no se pudo).
func bot_enchant(index: int, rune: String) -> Dictionary:
	bot_fail = ""
	if index < 0 or index >= Game.potions.size() or Game.enchant_problem(index, rune) != "":
		bot_fail = "problema: " + (Game.enchant_problem(index, rune) if index >= 0 and index < Game.potions.size() else "índice")
		return {}
	var key: Dictionary = Game.potions[index].duplicate()
	for attempt in 3:   # si otra cosa la hace caminar (llega un cliente), vuelve a intentarlo
		if world.at_station("biblioteca"):
			break
		await world.go_station("biblioteca")
	if not world.at_station("biblioteca"):
		bot_fail = "no llegó al escritorio (estación=%s)" % world.current_station()
		return {}
	var idx := Game.find_potion(key)
	if idx < 0 or ov.is_open():
		bot_fail = "poción=%d panel=%s" % [idx, ov.current]
		return {}
	_last_enchanted = {}
	show_book(rune, "enchant", idx)
	for i in 3:
		await get_tree().process_frame
	pick_ink(Game.rune_ink(rune))
	var prev := demo_auto
	demo_auto = 1.0
	start_trace()
	demo_auto = prev
	var t := 0.0
	while busy and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var res := _last_enchanted.duplicate()
	if res.is_empty():
		bot_fail = "trazo: busy=%s panel=%s tinta=%s" % [busy, ov.current, _ink]
		if is_instance_valid(_game):
			bot_fail += " juego: auto=%s estado=%d punto=%d/%d tam=%s t=%.2f" % [_game.auto_until, _game._state, _game._next, _game._pts.size(), _game.size, _game._t]
	await get_tree().create_timer(0.3).timeout
	if ov.current == "grimoire":
		ov.close()
	return res
