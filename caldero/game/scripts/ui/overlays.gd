extends CanvasLayer
class_name Overlays
## Pantallas grandes: título, libro de recetas, diario, mercado, resumen del día, ajustes, subida de nivel y minijuego de remover.

signal closed(id: String)
signal new_game
signal continue_game
signal open_shop
signal sleep
signal stir_done(perfect: bool)
signal to_title

var root: Control
var current := ""
var current_node: Control
var _book_sel := ""
var _market_tab := 0
var _market_mode := "day"   # "morning" o "day"

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)

func is_open() -> bool:
	return current != ""

func close(emit := true) -> void:
	var id := current
	if current_node:
		current_node.queue_free()
	current_node = null
	current = ""
	if emit and id != "":
		closed.emit(id)

func _open(id: String, panel: Control, dim := true) -> Control:
	close(false)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	if dim:
		holder.add_child(UIKit.dim_overlay())
	holder.add_child(UIKit.center(panel))
	current = id
	current_node = holder
	await get_tree().process_frame
	if is_instance_valid(panel):
		UIKit.pop_in(panel)
	return holder

func _unhandled_input(ev: InputEvent) -> void:
	if current == "" or current == "title" or current == "stir" or current == "summary" or current == "levelup":
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _title_row(text: String, size := 40) -> Label:
	return UIKit.shadow(UIKit.label(text, size, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER), 3)

func _close_button(text := "Cerrar") -> Button:
	var b := UIKit.button(text, func(): close(), 22)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

# ------------------------------------------------------------------ título

func show_title(has_save: bool) -> void:
	close(false)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.01, 0.05, 0.85))
	g.set_color(1, Color(0.02, 0.01, 0.05, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.75, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(grad)
	var v := UIKit.vbox(6)
	UIKit.place(v, Vector2(0, 0.5), Vector2(120, -300), Vector2(700, 600))
	holder.add_child(v)
	var t := UIKit.shadow(UIKit.label("Caldero", 120, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold), 4)
	v.add_child(t)
	var t2 := UIKit.shadow(UIKit.label("Nocturno", 120, Color(0.82, 0.78, 1.0), UIKit.font_sc_bold), 4)
	t.add_theme_constant_override("line_spacing", -40)
	t.custom_minimum_size = Vector2(0, 120)
	t2.custom_minimum_size = Vector2(0, 120)
	v.add_child(t2)
	v.add_child(UIKit.shadow(UIKit.label("una tiendita de pociones al pie de la montaña", 28, UIKit.TEXT, UIKit.font_italic)))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	v.add_child(sp)
	var btns := UIKit.vbox(12)
	v.add_child(btns)
	if has_save:
		var c := UIKit.button("Continuar", func(): close(false); continue_game.emit(), 28)
		c.custom_minimum_size = Vector2(320, 60)
		c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btns.add_child(c)
	var n := UIKit.button("Nueva partida" if has_save else "Empezar", func(): _confirm_new(has_save), 28)
	n.custom_minimum_size = Vector2(320, 60)
	n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btns.add_child(n)
	var q := UIKit.button("Salir", func(): get_tree().quit(), 24)
	q.custom_minimum_size = Vector2(320, 52)
	q.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btns.add_child(q)
	var credit := UIKit.label("Ratón para todo · Espacio para avanzar diálogos", 18, UIKit.MUTED, UIKit.font_italic)
	UIKit.place(credit, Vector2(0, 1), Vector2(120, -60), Vector2(800, 30))
	holder.add_child(credit)
	current = "title"
	current_node = holder
	holder.modulate.a = 0.0
	var tw := holder.create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 1.2)

func _confirm_new(has_save: bool) -> void:
	if not has_save:
		close(false)
		new_game.emit()
		return
	var p := UIKit.fancy_panel()
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(_title_row("¿Empezar de nuevo?", 36))
	var r := UIKit.rich(24)
	r.custom_minimum_size = Vector2(560, 0)
	r.text = "[center]Tu partida guardada se borrará y la tienda volverá a abrir desde el primer día.[/center]"
	v.add_child(r)
	var h := UIKit.hbox(16)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(UIKit.button("Sí, empezar", func(): close(false); new_game.emit(), 24))
	h.add_child(UIKit.button("Volver", func(): show_title(true), 24))
	_open("confirm", p)

# ------------------------------------------------------------------ libro de recetas

func show_book() -> void:
	Sfx.play("page", 0.05, -4.0)
	var p := UIKit.fancy_panel(Color(0.11, 0.085, 0.07, 0.97), 28)
	p.custom_minimum_size = Vector2(1300, 760)
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(_title_row("Libro de recetas"))
	var tabs := TabBar.new()
	tabs.add_tab("Pociones")
	tabs.add_tab("Ingredientes")
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.focus_mode = Control.FOCUS_NONE
	v.add_child(tabs)
	var body := Control.new()
	body.custom_minimum_size = Vector2(1240, 560)
	v.add_child(body)
	var rule := UIKit.rich(20)
	rule.custom_minimum_size = Vector2(1240, 0)
	rule.text = "[center][color=#d9c79f]La poción la deciden las [b]dos esencias más fuertes[/b] del caldero. Si empatan, manda este orden: [color=#ff9a6a]Fuego[/color] › [color=#9fdcff]Escarcha[/color] › [color=#9eea9f]Vida[/color] › [color=#c9a8ff]Sombra[/color] › [color=#ffe27a]Luz[/color].[/color][/center]"
	v.add_child(rule)
	v.add_child(_close_button())
	var fill_body := func(tab: int):
		for c in body.get_children():
			c.queue_free()
		if tab == 0:
			body.add_child(_book_potions())
		else:
			body.add_child(_book_ingredients())
	tabs.tab_changed.connect(func(i): Sfx.play("page", 0.05, -6.0); fill_body.call(i))
	fill_body.call(0)
	_open("book", p)

func _book_potions() -> Control:
	var h := UIKit.hbox(30)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 10)
	list.add_theme_constant_override("v_separation", 8)
	list.custom_minimum_size = Vector2(620, 0)
	h.add_child(list)
	var detail := UIKit.vbox(12)
	detail.custom_minimum_size = Vector2(580, 540)
	h.add_child(detail)
	if _book_sel == "":
		_book_sel = Data.POTION_ORDER[0]
	var show_detail := func(pid: String):
		_book_sel = pid
		for c in detail.get_children():
			c.queue_free()
		var known := Game.discovered.has(pid)
		var d: Dictionary = Data.POTIONS[pid]
		var top := UIKit.hbox(18)
		detail.add_child(top)
		top.add_child(UIKit.icon("res://assets/icons/pot_%s.png" % (pid if known else "desconocida"), 7.0))
		var tv := UIKit.vbox(6)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tv)
		tv.add_child(UIKit.label(d["name"], 38, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
		var eff := UIKit.rich(24)
		eff.custom_minimum_size = Vector2(440, 0)
		eff.text = "[i]%s[/i]" % d["effect"]
		tv.add_child(eff)
		detail.add_child(UIKit.divider())
		if known:
			var r := UIKit.hbox(14)
			detail.add_child(r)
			r.add_child(UIKit.label("Esencias:", 24, UIKit.MUTED))
			r.add_child(UIKit.essence_chip(d["pair"][0], 0, 24))
			r.add_child(UIKit.label("+", 24, UIKit.MUTED))
			r.add_child(UIKit.essence_chip(d["pair"][1], 0, 24))
			var best: int = Game.discovered[pid]
			if best > 0:
				var b := UIKit.hbox(10)
				detail.add_child(b)
				b.add_child(UIKit.label("Mejor preparación:", 24, UIKit.MUTED))
				b.add_child(UIKit.stars(Game.stars_for(best), 1.8))
				b.add_child(UIKit.label("(potencia %d)" % best, 22, UIKit.MUTED))
			else:
				detail.add_child(UIKit.label("Receta anotada por tu maestra. Aún no la preparas.", 22, UIKit.MUTED, UIKit.font_italic))
			var price := UIKit.label("Precio base: %d oro" % d["base"], 22, Color(1.0, 0.86, 0.45))
			detail.add_child(price)
		else:
			var r2 := UIKit.rich(23)
			r2.custom_minimum_size = Vector2(560, 0)
			r2.text = "[color=#b8aecb]Aún no descubres esta receta. Escucha bien a tus clientes: suelen dar pistas sobre las esencias que necesitan. Prueba mezclas en el caldero.[/color]"
			detail.add_child(r2)
		if not Game.brewable_potions().has(pid):
			detail.add_child(UIKit.label("Necesitarás ingredientes que aún no vende el mercado.", 20, Color(1.0, 0.7, 0.55), UIKit.font_italic))
	for pid in Data.POTION_ORDER:
		var known := Game.discovered.has(pid)
		var b := Button.new()
		b.text = Data.POTIONS[pid]["name"]
		if not known:
			b.add_theme_color_override("font_color", Color(0.6, 0.56, 0.68))
		b.icon = load("res://assets/icons/pot_%s.png" % (pid if known else "desconocida"))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(300, 56)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): Sfx.play("page", 0.08, -10.0); show_detail.call(pid))
		list.add_child(b)
	show_detail.call(_book_sel)
	return h

func _book_ingredients() -> Control:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 26)
	g.add_theme_constant_override("v_separation", 14)
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	for id in Data.INGREDIENT_ORDER:
		var d: Dictionary = Data.INGREDIENTS[id]
		var unlocked := Game.ingredient_unlocked(id)
		var h := UIKit.hbox(14)
		h.custom_minimum_size = Vector2(600, 0)
		g.add_child(h)
		var ic := UIKit.icon("res://assets/icons/ing_%s.png" % id, 4.0)
		if not unlocked:
			ic.modulate = Color(0.2, 0.18, 0.25)
		h.add_child(ic)
		var v := UIKit.vbox(4)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		v.add_child(UIKit.label(d["name"] if unlocked else "???", 26, UIKit.GOLD_BRIGHT, UIKit.font_bold))
		if unlocked:
			var chips := UIKit.hbox(14)
			v.add_child(chips)
			for e in d["ess"]:
				chips.add_child(UIKit.essence_chip(e, d["ess"][e], 21))
		else:
			v.add_child(UIKit.label("Llega al renombre «%s»." % Game.level_name(d["level"]), 20, UIKit.MUTED, UIKit.font_italic))
	return g

# ------------------------------------------------------------------ diario

func show_journal() -> void:
	Sfx.play("page", 0.05, -4.0)
	var p := UIKit.fancy_panel(Color(0.11, 0.085, 0.07, 0.97), 28)
	p.custom_minimum_size = Vector2(1300, 760)
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(_title_row("Diario de viajeros"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1240, 580)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UIKit.vbox(16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for hid in Data.HERO_ORDER:
		var ch: Dictionary = Data.CHARACTERS[hid]
		var done: int = Game.hero_progress.get(hid, 0)
		var row := UIKit.hbox(20)
		list.add_child(row)
		var port := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = load("res://assets/chars/%s_idle.png" % hid)
		at.region = Rect2(0, 0, 32, 48)
		port.texture = at
		port.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		port.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		port.custom_minimum_size = Vector2(96, 144)
		port.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if done == 0:
			port.modulate = Color(0.08, 0.07, 0.12)
		row.add_child(port)
		var col := UIKit.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var head := UIKit.hbox(14)
		col.add_child(head)
		head.add_child(UIKit.label(ch["name"] if done > 0 else "Viajero desconocido", 30, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
		if done > 0:
			head.add_child(UIKit.label(ch["title"], 22, UIKit.MUTED, UIKit.font_italic))
		var dots := UIKit.hbox(6)
		dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(dots)
		for i in 3:
			var d := ColorRect.new()
			d.custom_minimum_size = Vector2(12, 12)
			d.color = UIKit.GOLD_BRIGHT if i < done else Color(1, 1, 1, 0.12)
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dots.add_child(d)
		var text := UIKit.rich(22)
		text.custom_minimum_size = Vector2(1080, 0)
		if done == 0:
			text.text = "[color=#8f86a3][i]Todavía no ha pasado por la tienda.[/i][/color]"
		else:
			var lines := []
			for e in Game.journal:
				if e["hero"] == hid:
					lines.append("[color=#d9c79f]Día %d.[/color] %s" % [e["day"], e["text"]])
			if done < 3:
				lines.append("[color=#8f86a3][i]Quizá vuelva pronto…[/i][/color]")
			else:
				lines.append("[color=#ffd987][i]Historia completa.[/i][/color]")
			text.text = "\n".join(lines)
		col.add_child(text)
	var stats := UIKit.label("Pociones preparadas: %d   ·   Vendidas: %d   ·   Oro ganado: %d   ·   Remezclas perfectas: %d" % [Game.stats["brewed"], Game.stats["sold"], Game.stats["earned"], Game.stats["perfect"]], 20, UIKit.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(stats)
	v.add_child(_close_button())
	_open("journal", p)

# ------------------------------------------------------------------ mercado y mejoras

func show_market(mode := "day") -> void:
	_market_mode = mode
	var p := UIKit.fancy_panel(UIKit.BG, 28)
	p.custom_minimum_size = Vector2(1300, 780)
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(_title_row("Mercado de la mañana" if mode == "morning" else "Mercado"))
	var gold := UIKit.hbox(8)
	gold.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(gold)
	gold.add_child(UIKit.icon("res://assets/icons/emote_coin.png", 2.0))
	var gl := UIKit.label(str(Game.gold), 30, Color(1.0, 0.86, 0.45), UIKit.font_bold)
	gold.add_child(gl)
	gold.add_child(UIKit.label("oro", 22, UIKit.MUTED))
	var tabs := TabBar.new()
	tabs.add_tab("Ingredientes")
	tabs.add_tab("Mejoras")
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.current_tab = _market_tab
	v.add_child(tabs)
	var body := Control.new()
	body.custom_minimum_size = Vector2(1240, 520)
	v.add_child(body)
	var btns := UIKit.hbox(16)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	if mode == "morning":
		var o := UIKit.button("Abrir la tienda", func(): close(false); open_shop.emit(), 28)
		o.custom_minimum_size = Vector2(340, 62)
		btns.add_child(o)
		var k := UIKit.button("Preparar antes de abrir", func(): close(), 22)
		k.custom_minimum_size = Vector2(0, 62)
		btns.add_child(k)
	else:
		btns.add_child(_close_button())
	_mk_body = body
	_mk_gold = gl
	tabs.tab_changed.connect(func(i): _refill_market(i))
	_refill_market(_market_tab)
	_open("market", p)

var _mk_body: Control
var _mk_gold: Label

func _refill_market(tab: int) -> void:
	_market_tab = tab
	if not is_instance_valid(_mk_body):
		return
	_mk_gold.text = str(Game.gold)
	for c in _mk_body.get_children():
		c.queue_free()
	var refresh := func(): _refill_market(_market_tab)
	_mk_body.add_child(_market_ingredients(refresh) if tab == 0 else _market_upgrades(refresh))

func _market_ingredients(refresh: Callable) -> Control:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 12)
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	for id in Data.INGREDIENT_ORDER:
		var d: Dictionary = Data.INGREDIENTS[id]
		var unlocked := Game.ingredient_unlocked(id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_SOFT, UIKit.GOLD, 1, 6, 12))
		card.custom_minimum_size = Vector2(610, 112)
		g.add_child(card)
		var h := UIKit.hbox(14)
		card.add_child(h)
		var ic := UIKit.icon("res://assets/icons/ing_%s.png" % id, 4.5)
		if not unlocked:
			ic.modulate = Color(0.2, 0.18, 0.25)
		h.add_child(ic)
		var v := UIKit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		v.add_child(UIKit.label(d["name"] if unlocked else "???", 25, UIKit.GOLD_BRIGHT, UIKit.font_bold))
		if unlocked:
			var chips := UIKit.hbox(12)
			v.add_child(chips)
			for e in d["ess"]:
				chips.add_child(UIKit.essence_chip(e, d["ess"][e], 19))
			v.add_child(UIKit.label("Tienes %d   ·   %d oro c/u" % [Game.stock.get(id, 0), d["price"]], 19, UIKit.MUTED))
			var bv := UIKit.vbox(6)
			bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(bv)
			for q in [1, 5]:
				var cost: int = d["price"] * q
				var b := UIKit.button("+%d  (%d)" % [q, cost], func():
					if Game.buy_ingredient(id, q):
						Sfx.play("coin", 0.1, -8.0)
					refresh.call(), 19)
				b.custom_minimum_size = Vector2(130, 40)
				b.disabled = Game.gold < cost
				bv.add_child(b)
		else:
			v.add_child(UIKit.label("Disponible con renombre «%s»." % Game.level_name(d["level"]), 19, UIKit.MUTED, UIKit.font_italic))
	return g

func _market_upgrades(refresh: Callable) -> Control:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 12)
	sc.add_child(g)
	for id in Data.UPGRADE_ORDER:
		var u: Dictionary = Data.UPGRADES[id]
		var owned := Game.has_upgrade(id)
		var locked: bool = Game.level() < u["level"]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG_SOFT, UIKit.GOLD_BRIGHT if owned else UIKit.GOLD, 1, 6, 14))
		card.custom_minimum_size = Vector2(605, 120)
		g.add_child(card)
		var h := UIKit.hbox(14)
		card.add_child(h)
		var v := UIKit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.label(u["name"], 25, UIKit.GOLD_BRIGHT if not locked else UIKit.MUTED, UIKit.font_bold))
		var desc := UIKit.rich(19)
		desc.custom_minimum_size = Vector2(400, 0)
		desc.text = "[color=#c9bfd9]%s[/color]" % u["desc"]
		v.add_child(desc)
		var b: Button
		if owned:
			b = UIKit.button("Comprada", func(): pass, 20)
			b.disabled = true
		elif locked:
			b = UIKit.button("Renombre:\n%s" % Game.level_name(u["level"]), func(): pass, 17)
			b.disabled = true
		else:
			b = UIKit.button("%d oro" % u["cost"], func():
				if Game.buy_upgrade(id):
					Sfx.play("levelup", 0.02, -6.0)
				refresh.call(), 21)
			b.disabled = Game.gold < u["cost"]
		b.custom_minimum_size = Vector2(150, 56)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	return sc

# ------------------------------------------------------------------ resumen del día

func show_summary(day: int, today: Dictionary) -> void:
	var p := UIKit.fancy_panel(UIKit.BG, 30)
	p.custom_minimum_size = Vector2(820, 0)
	var v := UIKit.vbox(12)
	p.add_child(v)
	v.add_child(_title_row("Fin del día %d" % day, 46))
	v.add_child(UIKit.label("La tienda se queda en silencio. Miga se estira junto al fuego.", 22, UIKit.MUTED, UIKit.font_italic, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.divider())
	var rows := [
		["Oro ganado", "+%d" % today["earned"], Color(1.0, 0.86, 0.45)],
		["Renombre", "+%d" % today["renombre"], Color(0.85, 0.78, 1.0)],
		["Pociones vendidas", str(today["sold"]), UIKit.TEXT],
	]
	for r in rows:
		var h := UIKit.hbox(10)
		v.add_child(h)
		var l := UIKit.label(r[0], 26, UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UIKit.label(r[1], 28, r[2], UIKit.font_bold))
	if today["new_recipes"].size() > 0:
		var h2 := UIKit.hbox(10)
		v.add_child(h2)
		var l2 := UIKit.label("Recetas nuevas", 26)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h2.add_child(l2)
		for pid in today["new_recipes"]:
			h2.add_child(UIKit.icon("res://assets/icons/pot_%s.png" % pid, 3.0))
	if today["journal"].size() > 0:
		v.add_child(UIKit.divider())
		v.add_child(UIKit.label("Nuevas páginas en el diario", 26, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER))
		for e in today["journal"]:
			var r := UIKit.rich(22)
			r.custom_minimum_size = Vector2(760, 0)
			r.text = "[b][color=#ffd987]%s:[/color][/b] %s" % [Data.CHARACTERS[e["hero"]]["name"], e["text"]]
			v.add_child(r)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	v.add_child(sp)
	var b := UIKit.button("Dormir hasta mañana", func(): close(false); sleep.emit(), 26)
	b.custom_minimum_size = Vector2(360, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	_open("summary", p)

# ------------------------------------------------------------------ subida de nivel

func show_level_up(lv: int) -> void:
	Sfx.play("levelup", 0.0, -2.0)
	var p := UIKit.fancy_panel(UIKit.BG, 30)
	p.custom_minimum_size = Vector2(700, 0)
	var v := UIKit.vbox(14)
	p.add_child(v)
	var gem := UIKit.icon("res://assets/icons/emote_gem.png", 5.0)
	gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(gem)
	v.add_child(_title_row("¡Tu renombre crece!", 44))
	v.add_child(UIKit.label("Ahora eres: %s" % Game.level_name(lv), 30, Color(0.85, 0.78, 1.0), UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	var r := UIKit.rich(24)
	r.custom_minimum_size = Vector2(640, 0)
	r.text = "[center]%s[/center]" % Data.LEVEL_REWARDS.get(lv, "")
	v.add_child(r)
	var b := UIKit.button("¡Qué bien!", func(): close(), 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	_open("levelup", p)

# ------------------------------------------------------------------ ajustes

func show_settings() -> void:
	var p := UIKit.fancy_panel(UIKit.BG, 30)
	p.custom_minimum_size = Vector2(640, 0)
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(_title_row("Ajustes"))
	for s in [["Música", "music_volume"], ["Efectos", "sfx_volume"]]:
		var h := UIKit.hbox(16)
		v.add_child(h)
		var l := UIKit.label(s[0], 26)
		l.custom_minimum_size = Vector2(160, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Game.get(s[1])
		sl.custom_minimum_size = Vector2(360, 30)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		sl.value_changed.connect(func(val):
			Game.set(s[1], val)
			Sfx.apply_volumes())
		h.add_child(sl)
	var fs := CheckButton.new()
	fs.text = "Pantalla completa"
	fs.add_theme_font_size_override("font_size", 24)
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.focus_mode = Control.FOCUS_NONE
	fs.toggled.connect(func(on):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	v.add_child(fs)
	v.add_child(UIKit.divider())
	var h2 := UIKit.hbox(16)
	h2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h2)
	h2.add_child(UIKit.button("Guardar y volver al título", func(): close(false); Game.save_game(); to_title.emit(), 21))
	h2.add_child(UIKit.button("Cerrar", func(): Game.save_game(); close(), 21))
	_open("settings", p)

# ------------------------------------------------------------------ minijuego: remover

func show_stir(difficulty := 1.0) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(holder)
	close(false)
	current = "stir"
	current_node = holder
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(dim)
	var game := StirGame.new()
	game.speed = 1.6 + 0.3 * difficulty
	UIKit.place(game, Vector2(0.5, 0.5), Vector2(-180, -250), Vector2(360, 360))
	holder.add_child(game)
	var info := UIKit.shadow(UIKit.label("¡Remueve!  Haz clic (o pulsa Espacio) cuando la cuchara pase por la zona dorada.", 26, UIKit.TEXT, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	UIKit.place(info, Vector2(0.5, 0.5), Vector2(-600, 130), Vector2(1200, 40))
	holder.add_child(info)
	holder.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game.press())
	game.finished.connect(func(perfect: bool):
		info.text = "¡Perfecto! +1 de potencia" if perfect else "¡Bien removido!"
		info.add_theme_color_override("font_color", UIKit.GOLD_BRIGHT if perfect else UIKit.TEXT)
		await get_tree().create_timer(0.7).timeout
		close(false)
		stir_done.emit(perfect))

func stir_key() -> void:
	if current == "stir" and current_node:
		for c in current_node.get_children():
			if c is StirGame:
				c.press()

func _input(ev: InputEvent) -> void:
	if current == "stir" and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE:
		stir_key()
		get_viewport().set_input_as_handled()
