class_name RankUI
## --- R4 RANK: los papeles del Escalafón del Gremio de Boticarios de Arvendal (los abre overlays.gd):
##   - board(ov): el tablón del Gremio: las 30 tiendas en dos hojas clavadas, su fila subrayada, flechas de cambio,
##     y abajo la ficha de la tienda elegida (su pueblo en una línea) y su camino en el Escalafón.
##     Ratón (pasar por una fila), teclado (↑ ↓ ← →, W S A D; G o Esc cierran) y mando (LB / RB saltan de fila, B cierra).
##   - gaceta(ov): la Gaceta del Gremio (cada 5 días, con el correo): cabecera, los diez mejores, su fila y dos titulares.
##   - mail_strip(): la línea del Escalafón del correo de la mañana (puesto, flecha, a quién pasó).
##   - summary_row(): la fila «Escalafón» de la hoja de cuentas de la noche.
##   - credits(ov, done): los créditos del final (el elenco) y «Seguir jugando».
## El arte sale de tools/arte/rank_art.py (assets/ui/rank_*.png). Los datos, de scripts/ranking.gd (autoload Ranking).

const ROW_H := 44.0
const SHEET_W := 830.0
const SEL_COL := Color(0.37, 0.28, 0.2, 0.16)
const UP_COL := Color("3e7a2e")
const DOWN_COL := Color("a3261f")

# ------------------------------------------------------------------ piezas

## Nine-patch de una textura propia (rank_newsprint9, rank_board9, rank_mark9: guardadas a x2).
static func nine(tex: String, margin: Vector4, content := Vector2(-1, -1), stretch := false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = PaperKit.tex(tex)
	sb.texture_margin_left = margin.x
	sb.texture_margin_top = margin.y
	sb.texture_margin_right = margin.z
	sb.texture_margin_bottom = margin.w
	var mode := StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH if stretch else StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_horizontal = mode
	sb.axis_stretch_vertical = mode
	var c := content
	if c.x < 0:
		c = Vector2(margin.x + 8, margin.y + 4)
	sb.content_margin_left = c.x
	sb.content_margin_right = c.x
	sb.content_margin_top = c.y
	sb.content_margin_bottom = c.y
	return sb

static func panel9(tex: String, margin: Vector4, content := Vector2(-1, -1)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", nine(tex, margin, content))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

## El escudo de una tienda (o el del Gremio si falta el suyo).
static func crest(id: String, scale := 2.0) -> TextureRect:
	var path := "res://assets/ui/rank_crest_%s.png" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/rank_crest_gremio.png"
	var t := PaperKit.pic(path, scale)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t

## --- R5 EN-UI: miles con coma (1,284): UIKit.num.
static func fmt(n: int) -> String:
	return UIKit.num(n)

## --- R5 EN-UI: el pueblo al empezar una casilla o un renglón va con mayúscula («the Grey Mountain» -> «The Grey Mountain»)
static func cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)

## La flecha de cambio: ▲3 verde, ▼2 roja o una raya gris.
static func arrow(delta: int, size := 24, show_same := true) -> HBoxContainer:
	var h := UIKit.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if delta == 0 and not show_same:
		return h
	var ic := PaperKit.pic("rank_up" if delta > 0 else ("rank_down" if delta < 0 else "rank_same"), 3.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	if delta != 0:
		var l := PaperKit.hand(str(absi(delta)), size, UP_COL if delta > 0 else DOWN_COL, true)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	return h

static func medal_icon(medal: String, scale := 2.0) -> TextureRect:
	return PaperKit.pic("rank_medal_%s" % medal, scale)

## El retrato de una noticia, como un grabado (sepia) en un marquito.
static func engraving(sprite: String, scale := 2.0) -> Control:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("efe8d4")
	sb.border_color = Color("2a1d14")
	sb.set_border_width_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PaperKit.portrait(Story.sprite_id(sprite) if sprite != "alquimista" else "alquimista", scale)
	var mat := ShaderMaterial.new()
	mat.shader = _sepia()
	p.material = mat
	frame.add_child(p)
	return frame

static var _sepia_shader: Shader
static func _sepia() -> Shader:
	if _sepia_shader == null:
		_sepia_shader = Shader.new()
		_sepia_shader.code = """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	g = floor(g * 5.0 + 0.5) / 5.0;
	COLOR = vec4(mix(vec3(0.16, 0.11, 0.07), vec3(0.93, 0.87, 0.74), g), c.a);
}
"""
	return _sepia_shader

## Envuelve un papel grande para que quepa en pantallas estrechas (4:3, ventana del navegador angosta): si no cabe, lo
## achica entero (su escala), sin cambiar su diseño. Los clics y el cursor del mando siguen funcionando (escala normal).
static func fit(c: Control) -> Control:
	var f := FitBox.new()
	f.add_child(c)
	return f

class FitBox extends Container:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().size_changed.connect(func():
			update_minimum_size()
			queue_sort())

	func _k(s: Vector2) -> float:
		var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
		return clampf(minf((vp.x - 36.0) / maxf(1.0, s.x), (vp.y - 20.0) / maxf(1.0, s.y)), 0.3, 1.0)

	func _get_minimum_size() -> Vector2:
		for c in get_children():
			if c is Control:
				var s: Vector2 = c.get_combined_minimum_size()
				return s * _k(s)
		return Vector2.ZERO

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					var s: Vector2 = c.get_combined_minimum_size()
					fit_child_in_rect(c, Rect2(Vector2.ZERO, s))
					c.scale = Vector2.ONE * _k(s)

# ------------------------------------------------------------------ el tablón del Gremio

static func board(ov) -> Control:
	return Board.new(ov)

## El tablón: madera del Gremio, la tablilla tallada, dos hojas clavadas (1-15 y 16-30) y la ficha de abajo.
class Board extends PanelContainer:
	var ov
	var rows: Array = []          # [{"btn": Button, "id": String}]
	var sel := -1
	var me_index := 0
	var detail: HBoxContainer

	func _init(o) -> void:
		ov = o
		add_theme_stylebox_override("panel", RankUI.nine("rank_board9", Vector4(24, 24, 24, 24), Vector2(34, 22)))
		mouse_filter = Control.MOUSE_FILTER_STOP
		var v := UIKit.vbox(8)
		add_child(v)
		# arriba: el escudo del Gremio, la tablilla tallada con el título y Cerrar
		var top := UIKit.hbox(14)
		v.add_child(top)
		var gc := RankUI.crest("gremio", 3.0)
		top.add_child(gc)
		var tv := UIKit.vbox(0)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tv)
		var plq := PaperKit.pic("rank_plaque", 3.0)
		tv.add_child(plq)
		var title := UIKit.label("Guild Rankings", 40, Color("f4e4bd"), UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER)
		title.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.02, 0.9))
		title.add_theme_constant_override("outline_size", 6)
		title.set_anchors_preset(Control.PRESET_FULL_RECT)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.offset_top = -4
		plq.add_child(title)
		var sub := UIKit.shadow(PaperKit.hand("Arvendal Apothecaries · Day %d" % Game.day, 28, Color("eadbb8")), 2)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(sub)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(sp)
		var me := Ranking.row(Ranking.ME)
		var you := UIKit.vbox(-6)
		you.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(you)
		var yl := UIKit.shadow(PaperKit.hand("Your place", 26, Color("eadbb8")), 2)
		yl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		you.add_child(yl)
		var yh := UIKit.hbox(8)
		yh.alignment = BoxContainer.ALIGNMENT_END
		you.add_child(yh)
		var yp := UIKit.label(UIKit.ordinal(int(me["pos"])), 52, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold)
		yp.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.02, 0.9))
		yp.add_theme_constant_override("outline_size", 6)
		yh.add_child(yp)
		var yof := UIKit.shadow(PaperKit.hand("of %d" % Ranking.size(), 28, Color("eadbb8")), 2)
		yof.size_flags_vertical = Control.SIZE_SHRINK_END
		yh.add_child(yof)
		top.add_child(PaperKit.gap(0, 12))
		var cb := PaperKit.button("Close", func(): ov.close(), 30)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(cb)
		ov.set_default(cb)   # --- R6 UI
		# las dos hojas
		var sheets := UIKit.hbox(22)
		v.add_child(sheets)
		var t: Array = Ranking.table()
		for half in 2:
			var sh := PaperKit.panel("sheet", Vector2(22, 14))
			sh.custom_minimum_size = Vector2(RankUI.SHEET_W, 0)
			sh.mouse_filter = Control.MOUSE_FILTER_PASS
			sheets.add_child(sh)
			var col := UIKit.vbox(0)
			sh.add_child(col)
			for i in range(half * 15, mini(t.size(), half * 15 + 15)):
				col.add_child(_row(t[i], i))
			PaperKit.decor(sh, "paper_pin_red" if half == 0 else "paper_pin_brass", Vector2(0.5, 0.0), Vector2(-10, -12))
		# abajo: la ficha de la tienda elegida y su camino
		var bottom := UIKit.hbox(18)
		v.add_child(bottom)
		var card := PaperKit.panel("card", Vector2(22, 10))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		bottom.add_child(card)
		detail = UIKit.hbox(16)
		card.add_child(detail)
		bottom.add_child(RankUI.my_path_note())
		_select(me_index, false)

	## Una fila del tablón: un botón plano (el mando salta de fila con LB / RB) con el puesto, el escudo, el nombre,
	## el dueño y su pueblo, los puntos y la flecha.
	func _row(r: Dictionary, i: int) -> Control:
		var b := Button.new()
		b.flat = false   # (un botón plano no dibuja sus estilos: el subrayado y el resalte al pasar)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(RankUI.SHEET_W - 44, RankUI.ROW_H)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var mine: bool = r["me"]
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _row_style(mine, st == "hover" or st == "hover_pressed" or st == "pressed"))
		var h := UIKit.hbox(8)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 6
		h.offset_right = -6
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var ink := PaperKit.RED_INK if mine else PaperKit.INK
		var pos := PaperKit.hand("%d." % int(r["pos"]), 28, ink, true, HORIZONTAL_ALIGNMENT_RIGHT)
		pos.custom_minimum_size = Vector2(44, 0)
		pos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pos)
		var cr := RankUI.crest(String(r["id"]), 2.0)
		h.add_child(cr)
		var nm := PaperKit.hand(String(r["name"]), 27, ink, true)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_stretch_ratio = 2.0
		h.add_child(nm)
		var tw := PaperKit.hand(RankUI.cap(String(r["town_name"])), 22, PaperKit.INK_SOFT)   # --- R5 EN-UI: «The Grey Mountain» en su casilla
		tw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tw.size_flags_stretch_ratio = 1.0
		tw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tw.clip_text = true
		tw.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(tw)
		if int(r["pos"]) <= 3:
			var md := RankUI.medal_icon(["oro", "plata", "bronce"][int(r["pos"]) - 1], 1.5)
			md.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(md)
		var sc := PaperKit.hand(RankUI.fmt(int(r["score"])), 25, ink, true, HORIZONTAL_ALIGNMENT_RIGHT)
		sc.custom_minimum_size = Vector2(76, 0)
		sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sc)
		var ar := RankUI.arrow(int(r["delta"]), 22)
		ar.custom_minimum_size = Vector2(48, 0)
		ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ar)
		if mine:
			me_index = i
			PaperKit.decor(b, "paper_pin_red", Vector2(0.0, 0.5), Vector2(-16, -14), 2.0)
		b.tooltip_text = "%s · %s" % [String(r["owner"]), String(r["town_name"])]
		var idx := i
		b.mouse_entered.connect(func(): _select(idx, false))
		b.pressed.connect(func(): _select(idx, false))
		rows.append({"btn": b, "id": String(r["id"]), "mine": mine})
		return b

	func _row_style(mine: bool, hot: bool) -> StyleBox:
		if mine:
			var sb := RankUI.nine("rank_mark9", Vector4(16, 12, 16, 12), Vector2(0, 0), true)
			if hot:
				sb.modulate_color = Color(1.0, 0.92, 0.8)
			return sb
		if hot:
			var f := StyleBoxFlat.new()
			f.bg_color = RankUI.SEL_COL
			f.set_corner_radius_all(6)
			return f
		return StyleBoxEmpty.new()

	## Elige una fila (la ficha de abajo muestra esa tienda). keys: vino del teclado (se marca la fila).
	func _select(i: int, keys := true) -> void:
		if rows.is_empty():
			return
		i = clampi(i, 0, rows.size() - 1)
		if keys and sel >= 0 and sel < rows.size():
			var old: Dictionary = rows[sel]
			old["btn"].add_theme_stylebox_override("normal", _row_style(old["mine"], false))
		sel = i
		if keys:
			var cur: Dictionary = rows[i]
			cur["btn"].add_theme_stylebox_override("normal", _row_style(cur["mine"], true))
			Sfx.play("hover", 0.05, -14.0)
		_fill_detail(String(rows[i]["id"]))

	## La ficha: escudo grande, nombre, dueño (y su relación con alguien del pueblo), el pueblo y una línea de él.
	func _fill_detail(id: String) -> void:
		for c in detail.get_children():
			detail.remove_child(c)
			c.queue_free()
		var r := Ranking.row(id)
		detail.add_child(RankUI.crest(id, 4.0))
		var v := UIKit.vbox(-4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		detail.add_child(v)
		var name := String(r["name"]) + ("  (you)" if r["me"] else "")
		v.add_child(PaperKit.head(name, 32, PaperKit.RED_INK if r["me"] else PaperKit.INK))
		var who := String(r["owner"])
		if String(r["note"]) != "":
			who += ", " + String(r["note"])
		if r["rival"]:
			who += " · your rival"
		v.add_child(PaperKit.hand(who, 27, PaperKit.INK_SOFT))
		var lore := Ranking.town_lore(String(r["town"]))
		var tname := String(r["town_name"])
		tname = tname.left(1).to_upper() + tname.substr(1)
		v.add_child(PaperKit.hand("%s — %s" % [tname, lore], 25, PaperKit.INK_SOFT, false, HORIZONTAL_ALIGNMENT_LEFT, 640))
		var rv := UIKit.vbox(0)
		rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		detail.add_child(rv)
		var pts := PaperKit.hand("%s pts" % RankUI.fmt(int(r["score"])), 30, PaperKit.INK, true, HORIZONTAL_ALIGNMENT_RIGHT)
		rv.add_child(pts)
		var ah := UIKit.hbox(6)
		ah.alignment = BoxContainer.ALIGNMENT_END
		rv.add_child(ah)
		ah.add_child(PaperKit.hand(UIKit.ordinal(int(r["pos"])), 30, PaperKit.INK, true))
		ah.add_child(RankUI.arrow(int(r["delta"]), 24, false))

	func _unhandled_input(ev: InputEvent) -> void:
		if not (ev is InputEventKey) or not ev.pressed:
			return
		var step := 0
		match ev.keycode:
			KEY_UP, KEY_W:
				step = -1
			KEY_DOWN, KEY_S:
				step = 1
			KEY_LEFT, KEY_A:
				step = -15
			KEY_RIGHT, KEY_D:
				step = 15
			KEY_G:
				if not ev.echo:
					ov.close()
					get_viewport().set_input_as_handled()
				return
		if step != 0:
			var from := sel if sel >= 0 else me_index
			var to := from + step
			if absi(step) == 15 and (to < 0 or to >= rows.size()):
				to = from
			_select(clampi(to, 0, rows.size() - 1), true)
			get_viewport().set_input_as_handled()

## Su camino en el Escalafón: una nota amarilla con los puestos día a día (una línea de tinta) y lo que sumó ayer.
static func my_path_note() -> Control:
	var n := PaperKit.panel("note", Vector2(22, 8))
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.custom_minimum_size = Vector2(430, 0)
	var v := UIKit.vbox(0)
	n.add_child(v)
	var hd := UIKit.hbox(8)
	v.add_child(hd)
	hd.add_child(PaperKit.head("Your climb", 28))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(sp)
	var mv: Dictionary = Ranking.last_move
	if not mv.is_empty():
		hd.add_child(PaperKit.hand("yesterday +%d" % int(mv.get("points", 0)), 28, UP_COL, true))
	var ch := PathChart.new()
	ch.custom_minimum_size = Vector2(380, 74)
	v.add_child(ch)
	# lo que sumó ayer, en iconos: ventas, estrellas, renombre, medalla
	if not mv.is_empty():
		var parts: Dictionary = mv.get("parts", {})
		var row := UIKit.hbox(12)
		v.add_child(row)
		var pairs := [["paper_i_bag", int(parts.get("ventas", 0)) + int(parts.get("krapido", 0))],
			["res://assets/icons/emote_star.png", int(parts.get("calidad", 0))],
			["res://assets/icons/emote_gem.png", int(parts.get("renombre", 0)) + int(parts.get("fama", 0))]]
		for p in pairs:
			var it := PaperKit.icon_text(p[0], str(p[1]), 26, PaperKit.INK_SOFT, 2.0 if String(p[0]).begins_with("res://") else 3.0)
			row.add_child(it)
		var md := String(mv.get("medal", ""))
		if md in ["oro", "plata", "bronce"]:
			var mi := medal_icon(md, 1.5)
			row.add_child(mi)
	PaperKit.decor(n, "paper_pin_green", Vector2(0.5, 0.0), Vector2(-10, -12))
	return n

## La línea de sus puestos (1 arriba, el último abajo) en los últimos días.
class PathChart extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var h: Array = Ranking.hist.slice(maxi(0, Ranking.hist.size() - 30))
		var n := Ranking.size()
		var w := size.x
		var hh := size.y
		var ink := PaperKit.INK
		draw_line(Vector2(0, hh - 1), Vector2(w, hh - 1), Color(ink, 0.25), 2.0)
		draw_line(Vector2(0, 2), Vector2(w, 2), Color(RankUI.UP_COL, 0.35), 2.0)
		var pts := PackedVector2Array()
		var all: Array = [n]   # empieza última
		for e in h:
			all.append(int(e["pos"]))
		var steps := maxi(1, all.size() - 1)
		for i in all.size():
			var x := 6.0 + (w - 12.0) * float(i) / float(steps)
			var y := 4.0 + (hh - 10.0) * float(int(all[i]) - 1) / float(maxi(1, n - 1))
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, ink, 3.0)
		for i in pts.size():
			draw_circle(pts[i], 4.0 if i == pts.size() - 1 else 2.5, PaperKit.RED_INK if i == pts.size() - 1 else ink)

# ------------------------------------------------------------------ la Gaceta del Gremio

static func gaceta(ov) -> Control:
	var g: Dictionary = Ranking.gaceta()
	var p := panel9("rank_newsprint9", Vector4(24, 24, 24, 24), Vector2(46, 30))
	p.custom_minimum_size = Vector2(1360, 0)
	var v := UIKit.vbox(6)
	p.add_child(v)
	var mh := PaperKit.pic("rank_masthead", 3.0)
	mh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(mh)
	# las «orejas» del periódico
	var ears := UIKit.hbox(10)
	v.add_child(ears)
	ears.add_child(PaperKit.hand("Arvendal · Day %d" % int(g["day"]), 28, PaperKit.INK))
	var s1 := Control.new()
	s1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ears.add_child(s1)
	ears.add_child(PaperKit.hand("Issue No. %d" % int(g["edition"]), 28, PaperKit.INK, true))
	var s2 := Control.new()
	s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ears.add_child(s2)
	ears.add_child(PaperKit.hand("One copper", 28, PaperKit.INK))
	v.add_child(PaperKit.ink_rule(1260, Color("2a1d14")))
	var cols := UIKit.hbox(30)
	v.add_child(cols)
	# columna izquierda: los diez mejores y su fila
	var left := UIKit.vbox(2)
	left.custom_minimum_size = Vector2(640, 0)
	cols.add_child(left)
	left.add_child(PaperKit.head("The Top Ten", 32, Color("2a1d14")))
	for r in g["top"]:
		left.add_child(_gaceta_row(r))
	var me: Dictionary = g["me"]
	if int(me["pos"]) > 10:
		left.add_child(PaperKit.hand("· · ·", 28, PaperKit.INK_FAINT, true, HORIZONTAL_ALIGNMENT_CENTER))
		left.add_child(_gaceta_row(me))
	var vr := ColorRect.new()
	vr.color = Color("2a1d14")
	vr.custom_minimum_size = Vector2(2, 0)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(vr)
	# columna derecha: los titulares
	var right := UIKit.vbox(8)
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	var hl: Array = g["headlines"]
	for i in hl.size():
		var h: Dictionary = hl[i]
		var t := PaperKit.head(String(h["title"]), 38 if i == 0 else 30, Color("2a1d14"))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.add_theme_constant_override("line_spacing", -12 if i == 0 else -9)
		t.custom_minimum_size = Vector2(560, 0)
		right.add_child(t)
		var body := UIKit.hbox(16)
		right.add_child(body)
		var has_pic := i == 0 or String(h.get("who", "")) != ""
		if has_pic:
			var pic: Control
			if String(h.get("who", "")) != "":
				pic = engraving(String(h["who"]), 2.0 if i == 0 else 1.4)
			else:
				pic = crest(String(h.get("crest", "gremio")), 5.0)
			pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			body.add_child(pic)
		var tx := PaperKit.hand(String(h["text"]), 29, PaperKit.INK, false, HORIZONTAL_ALIGNMENT_LEFT, (380.0 if i == 0 else 430.0) if has_pic else 540.0)
		tx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(tx)
		if i < hl.size() - 1:
			right.add_child(PaperKit.ink_rule(540, Color(0.16, 0.11, 0.07, 0.5)))
	var btns := UIKit.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	var b := PaperKit.wood_button("Continue", func(): ov.close(), 32)
	b.custom_minimum_size = Vector2(260, 64)
	btns.add_child(b)
	ov.set_default(b)   # --- R6 UI: Intro / Espacio / A (su tecla, dibujada)
	PaperKit.decor(p, "paper_pin_brass", Vector2(0.5, 0.0), Vector2(-10, -12))
	return p

static func _gaceta_row(r: Dictionary) -> Control:
	var mine: bool = r["me"]
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	if mine:
		pc.add_theme_stylebox_override("panel", nine("rank_mark9", Vector4(16, 12, 16, 12), Vector2(8, 2), true))
	else:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 8
		e.content_margin_right = 8
		pc.add_theme_stylebox_override("panel", e)
	var h := UIKit.hbox(8)
	pc.add_child(h)
	var ink := PaperKit.RED_INK if mine else Color("2a1d14")
	var pos := PaperKit.hand("%d." % int(r["pos"]), 28, ink, true, HORIZONTAL_ALIGNMENT_RIGHT)
	pos.custom_minimum_size = Vector2(42, 0)
	pos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pos)
	h.add_child(crest(String(r["id"]), 2.0))
	var nm := PaperKit.hand(String(r["name"]) + ("  (you)" if mine else ""), 27, ink, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var tw := PaperKit.hand(RankUI.cap(String(r["town_name"])), 22, PaperKit.INK_SOFT)   # --- R5 EN-UI: «The Grey Mountain» en su casilla
	tw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tw)
	var sc := PaperKit.hand(fmt(int(r["score"])), 25, ink, true, HORIZONTAL_ALIGNMENT_RIGHT)
	sc.custom_minimum_size = Vector2(70, 0)
	sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sc)
	var ar := arrow(int(r["delta"]), 22)
	ar.custom_minimum_size = Vector2(44, 0)
	ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ar)
	pc.tooltip_text = "%s · %s" % [String(r["owner"]), String(r["town_name"])]
	return pc

# ------------------------------------------------------------------ el correo y la noche

## La línea del Escalafón en el correo de la mañana: escudo del Gremio, puesto, flecha y a quién pasó (o quién la pasó).
static func mail_strip() -> Control:
	var m: Dictionary = Ranking.morning_line()
	if m.is_empty():
		return null
	var p := PaperKit.panel("card", Vector2(22, 6))
	p.custom_minimum_size = Vector2(1060, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIKit.hbox(14)
	p.add_child(h)
	h.add_child(crest("gremio", 2.0))
	var tv := UIKit.vbox(-8)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tv)
	tv.add_child(PaperKit.head("Guild Rankings", 24, PaperKit.INK_SOFT))
	var ph := UIKit.hbox(8)
	tv.add_child(ph)
	var pos := int(m["pos"])
	ph.add_child(PaperKit.hand(UIKit.ordinal(pos), 44, PaperKit.RED_INK if pos <= 3 else PaperKit.INK, true))
	var of := PaperKit.hand("of %d" % int(m.get("size", 30)), 26, PaperKit.INK_SOFT)
	of.size_flags_vertical = Control.SIZE_SHRINK_END
	ph.add_child(of)
	var ar := arrow(int(m["delta"]), 30)
	ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ar)
	if pos <= 3:
		var md := medal_icon(["oro", "plata", "bronce"][pos - 1], 2.0)
		md.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(md)
	var line := PaperKit.hand(morning_text(m), 29, PaperKit.INK, false, HORIZONTAL_ALIGNMENT_LEFT, 560.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	var evm := String(m.get("medal", ""))   # --- R4 MERGE: la medalla del evento de ayer, junto a los puntos
	if evm in ["oro", "plata", "bronce"]:
		var em := medal_icon(evm, 2.0)
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		em.tooltip_text = "Event medal"
		em.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(em)
	var pts := PaperKit.hand("+%d" % int(m.get("points", 0)), 32, UP_COL, true)
	pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pts.tooltip_text = "Yesterday's Guild points"
	pts.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(pts)
	PaperKit.decor(p, "paper_pin_brass", Vector2(0.0, 0.0), Vector2(14, -10))
	return p

## La frase de la mañana (corta): a quién pasó, quién la pasó o que sigue igual.
static func morning_text(m: Dictionary) -> String:
	var passed: Array = m.get("passed", [])
	var by: Array = m.get("passed_by", [])
	var pos := int(m.get("pos", 30))
	if pos == 1 and int(m.get("delta", 0)) > 0:
		return "The best shop in Arvendal!"
	if not passed.is_empty():
		if passed.size() == 1:
			return "You passed %s." % passed[0]
		if passed.size() == 2:
			return "You passed %s and %s." % [passed[0], passed[1]]
		return "You passed %s and %d more." % [passed[0], passed.size() - 1]
	if not by.is_empty():
		return "%s passed you." % by[0] if by.size() == 1 else "%s and %d more passed you." % [by[0], by.size() - 1]
	if pos == 1:
		return "Still on top."
	return "Still in %s place." % UIKit.ordinal(pos)   # --- R5 EN-UI: «Still in 12th place.»

## La fila «Escalafón» de la hoja de cuentas de la noche (lo que acaba de pasar hoy).
static func summary_row() -> Control:
	var mv: Dictionary = Ranking.last_move
	if mv.is_empty() or int(mv.get("day", 0)) != Game.day:
		return null
	var h := UIKit.hbox(12)
	h.custom_minimum_size = Vector2(0, 60)
	var i := crest("gremio", 1.6)
	i.custom_minimum_size = Vector2(48, 48)
	h.add_child(i)
	var l := PaperKit.hand("Rankings", 32, PaperKit.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	h.add_child(arrow(int(mv.get("delta", 0)), 28, false))
	var n := PaperKit.hand(UIKit.ordinal(int(mv.get("pos", 30))), 38, PaperKit.INK, true)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	return h

# ------------------------------------------------------------------ los créditos del final

## Los créditos: el caldero de oro, el título y el elenco (retrato, nombre y oficio) que sube solo; «Seguir jugando»
## siempre a la vista (botón, Espacio / Intro, A o B en el mando).
static func credits(ov, done: Callable) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = Vector2(1500, 980)
	var tr := PaperKit.pic("rank_trophy", 4.0)
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(tr)
	var t := UIKit.shadow(UIKit.label("Midnight Cauldron", 72, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER), 4)
	root.add_child(t)
	var st := UIKit.shadow(PaperKit.hand("Number One in the Arvendal Apothecaries' Guild Rankings", 40, Color("eadbb8"), false, HORIZONTAL_ALIGNMENT_CENTER), 2)
	root.add_child(st)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1500, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(sc)
	var inner := UIKit.vbox(18)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	inner.add_child(PaperKit.gap(380))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(grid)
	for c in cast_list():
		grid.add_child(_credit(c[0], c[1], c[2]))
	inner.add_child(PaperKit.gap(30))
	var thanks := UIKit.shadow(PaperKit.hand("Thanks for playing", 52, UIKit.GOLD_BRIGHT, true, HORIZONTAL_ALIGNMENT_CENTER), 3)
	inner.add_child(thanks)
	inner.add_child(PaperKit.gap(300))
	var b := PaperKit.wood_button("Keep playing", func():
		ov.close(false)
		done.call(), 38)
	b.custom_minimum_size = Vector2(420, 78)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(b)
	ov.set_default(b)   # --- R6 UI
	# los créditos suben solos (la rueda del ratón o el stick derecho también los mueven)
	sc.ready.connect(func():
		var tw := sc.create_tween()
		tw.tween_interval(1.2)
		tw.tween_method(func(y: float): sc.scroll_vertical = int(y), 0.0, 2600.0, 34.0))
	return root

## El elenco para los créditos: [sprite, nombre, oficio]. Ella y Miga primero; Fizz, al final.
static func cast_list() -> Array:
	var out: Array = [["alquimista", "You", "alchemist of Lakevale"], ["miga", "Miga", "sleepy cat"]]
	for id in Data.CHARACTERS:
		if id == "fizz":
			continue
		var ch: Dictionary = Data.CHARACTERS[id]
		out.append([Story.sprite_id(id), String(ch.get("name", id)), String(ch.get("title", ""))])
	out.append(["fizz", "Fizz", "gnome alchemist, your rival (and Spark)"])
	return out

static func _credit(sprite: String, name: String, title: String) -> Control:
	var v := UIKit.vbox(0)
	v.custom_minimum_size = Vector2(220, 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PaperKit.portrait(sprite, 1.6)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(p)
	v.add_child(UIKit.shadow(UIKit.label(name, 28, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER), 2))
	var tl := UIKit.shadow(PaperKit.hand(title, 24, Color("d8ccb0"), false, HORIZONTAL_ALIGNMENT_CENTER, 210.0), 2)
	v.add_child(tl)
	return v
