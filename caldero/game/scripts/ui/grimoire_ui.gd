extends Node
class_name GrimoireUI
## El grimorio de la maestra, en el escritorio de la biblioteca (la estación "biblioteca" de la tienda).
## Páginas de hechizos (como el libro de recetas), los materiales (papel, vitela y tintas) y el minijuego de la runa
## (scripts/ui/rune_game.gd) para inscribir pergaminos, que van al estante de pergaminos y se entregan como pociones.
## main.gd lo crea en _ready() y lo abre en _open_grimoire(). Todo funciona con ratón, teclado y el cursor del mando.

signal inscribed(scroll: Dictionary, perfect: bool)

const PAGE_BG := Color(0.11, 0.085, 0.07, 0.97)

var main                     # main.gd (customer_ready, current)
var ui: GameUI
var ov: Overlays
var world: ShopWorld
var busy := false            # la runa está abierta
var demo_auto := -1.0        # capturas: la runa se traza sola hasta esta fracción
var _sel := ""               # página elegida
var _paper := "papel"
var _glow_t := 0.0
var _list: GridContainer
var _detail: VBoxContainer
var _mats: HBoxContainer
var _stats: RichTextLabel

func setup(m) -> void:
	main = m
	ui = m.ui
	ov = m.ov
	world = m.world

func _ready() -> void:
	Sfx.magic_load()
	Game.level_up.connect(func(_lv): _announce_pages.call_deferred())
	Game.journal_changed.connect(func(): _announce_pages.call_deferred())

func _process(delta: float) -> void:
	# si hay páginas nuevas sin leer, el grimorio del escritorio suelta chispitas de vez en cuando
	_glow_t += delta
	if _glow_t < 2.4:
		return
	_glow_t = 0.0
	if world and world.visible and world.grimoire_sprite and Game.has_new_pages() and not ov.is_open():
		world.spawn_sparkles(world.grimoire_sprite.global_position + Vector3(0, 0.3, 0.15), Color(1.3, 1.1, 1.9), 6)

## Abre el grimorio (la alquimista ya está en el escritorio). La primera vez, la nota de la maestra.
func open() -> void:
	if ov.is_open() or busy:
		return
	Sfx.play("grimoire", 0.03, -3.0)
	if not Game.magic_unlocked:
		_show_intro()
	else:
		show_book()

# ------------------------------------------------------------------ la primera vez

func _show_intro() -> void:
	var p := UIKit.fancy_panel(PAGE_BG, 30)
	p.custom_minimum_size = Vector2(920, 0)
	var v := UIKit.vbox(14)
	p.add_child(v)
	var ic := UIKit.icon("res://assets/icons/spell_pergamino_luz.png", 6.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(_title("El grimorio de tu maestra", 44))
	var r := UIKit.rich(24)
	r.custom_minimum_size = Vector2(840, 0)
	r.text = "[center][color=#c9bfd9]Entre las páginas hay una nota con la letra de tu maestra:[/color]\n[i]«Las pociones se beben; los hechizos se escriben. Con una hoja, tinta hecha de una esencia y un trazo firme, la magia se queda quieta en el papel hasta que alguien la necesite. Traza las runas sin miedo: la magia perdona a quien escribe con cariño.\nEn el cajón te dejé hojas y dos frascos de tinta. Tobías, el del mercado, vende más.»[/i][/center]"
	v.add_child(r)
	v.add_child(UIKit.divider())
	var gifts := UIKit.hbox(26)
	gifts.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(gifts)
	for id in Game.MAGIC_STARTER:
		var h := UIKit.hbox(6)
		h.add_child(UIKit.icon("res://assets/icons/%s.png" % id, 3.0))
		h.add_child(UIKit.label("%s ×%d" % [Data.MAGIC_ITEMS[id]["name"], Game.MAGIC_STARTER[id]], 21, UIKit.TEXT, UIKit.font_bold))
		gifts.add_child(h)
	var b := UIKit.button("Abrir el grimorio", func():
		Game.unlock_magic()
		Sfx.play("page", 0.05, -4.0)
		show_book(), 26)
	b.custom_minimum_size = Vector2(340, 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	ov._open("grimoire_intro", p)

# ------------------------------------------------------------------ el libro

func _title(text: String, size := 40) -> Label:
	return UIKit.shadow(UIKit.label(text, size, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold, HORIZONTAL_ALIGNMENT_CENTER), 3)

## Las páginas del grimorio. sel: la página que se abre (si no, la última vista, o la primera nueva).
func show_book(sel := "") -> void:
	if sel != "":
		_sel = sel
	if _sel == "" or not Data.SPELLS.has(_sel):
		_sel = Data.SPELL_ORDER[0]
		for id in Data.SPELL_ORDER:
			if Game.page_is_new(id):
				_sel = id
				break
	if ov.current == "grimoire" and is_instance_valid(_detail):
		_refresh_book()
		return
	var p := UIKit.fancy_panel(PAGE_BG, 28)
	p.custom_minimum_size = Vector2(1320, 800)
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(_title("Grimorio"))
	v.add_child(UIKit.label("Una hoja, tinta de una esencia y el trazo de la runa: un pergamino. Se entregan a los clientes como las pociones.",
		20, UIKit.MUTED, UIKit.font_italic, HORIZONTAL_ALIGNMENT_CENTER))
	var h := UIKit.hbox(28)
	h.custom_minimum_size = Vector2(1260, 530)
	v.add_child(h)
	var left := UIKit.vbox(18)
	left.custom_minimum_size = Vector2(620, 0)
	h.add_child(left)
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override("h_separation", 10)
	_list.add_theme_constant_override("v_separation", 8)
	left.add_child(_list)
	left.add_child(UIKit.divider())
	_stats = UIKit.rich(21)
	_stats.custom_minimum_size = Vector2(620, 0)
	left.add_child(_stats)
	_detail = UIKit.vbox(10)
	_detail.custom_minimum_size = Vector2(612, 530)
	h.add_child(_detail)
	v.add_child(UIKit.divider())
	_mats = UIKit.hbox(18)
	_mats.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_mats)
	var rule := UIKit.rich(19)
	rule.custom_minimum_size = Vector2(1260, 0)
	rule.text = "[center][color=#d9c79f]¿Sin tinta? Cómprala a [b]Tobías[/b] en el mercado, o prepárala en el caldero con el botón [b]Tinta[/b]: la decide la [b]esencia más fuerte[/b] de la mezcla.[/color][/center]"
	v.add_child(rule)
	var close := UIKit.button("Cerrar", func(): ov.close(), 22)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
	_refresh_book()
	ov._open("grimoire", p)

## Vuelve a llenar la lista de páginas, la página elegida y los materiales (sin cerrar el libro).
func _refresh_book() -> void:
	for box in [_list, _detail, _mats]:
		for c in box.get_children():
			c.visible = false   # deja de ocupar sitio ya; se borra al final del cuadro
			c.queue_free()
	_fill_detail(_detail, _sel)
	for id in Data.SPELL_ORDER:
		var known := Game.spell_known(id)
		var b := Button.new()
		b.text = Data.SPELLS[id]["name"] if known else "Página en blanco"
		if Game.page_is_new(id):
			b.text += "  ✦"
			b.add_theme_color_override("font_color", UIKit.GOLD_BRIGHT)
		if not known:
			b.add_theme_color_override("font_color", Color(0.6, 0.56, 0.68))
		b.icon = load("res://assets/icons/spell_%s.png" % (id if known else "desconocido"))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(305, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if id == _sel:
			b.add_theme_stylebox_override("normal", UIKit.button_style(Color(0.3, 0.22, 0.14, 0.98), UIKit.GOLD_BRIGHT))
		b.pressed.connect(func():
			Sfx.play("page", 0.08, -8.0)
			show_book(id))
		b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
		_list.add_child(b)
	var n_known := Game.known_spells().size()
	_stats.text = "[center][color=#d9c79f]Páginas que sabes leer: [b]%d de %d[/b]\nPergaminos inscritos: [b]%d[/b]   ·   Trazos perfectos: [b]%d[/b]   ·   Tinta preparada: [b]%d[/b][/color]\n\n[color=#a99fbf][i]«La magia perdona a quien escribe con cariño.»[/i]\n— nota de tu maestra[/color][/center]" % [
		n_known, Data.SPELL_ORDER.size(), Game.magic_stats["scrolls"], Game.magic_stats["perfect"], Game.magic_stats["inks"]]
	_mats.add_child(UIKit.label("Tus materiales:", 21, UIKit.MUTED, UIKit.font_italic))
	for id in Data.MAGIC_ITEM_ORDER:
		var n := Game.item_count(id)
		var m := UIKit.hbox(4)
		m.tooltip_text = Data.MAGIC_ITEMS[id]["name"]
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := UIKit.icon("res://assets/icons/%s.png" % id, 2.4)
		if n <= 0:
			ic.modulate = Color(0.45, 0.42, 0.5)
		m.add_child(ic)
		m.add_child(UIKit.label("×%d" % n, 21, UIKit.TEXT if n > 0 else UIKit.MUTED, UIKit.font_bold))
		_mats.add_child(m)

func _fill_detail(detail: VBoxContainer, id: String) -> void:
	var d: Dictionary = Data.SPELLS[id]
	var known := Game.spell_known(id)
	var top := UIKit.hbox(18)
	detail.add_child(top)
	top.add_child(UIKit.icon("res://assets/icons/spell_%s.png" % (id if known else "desconocido"), 6.0))
	var tv := UIKit.vbox(4)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tv)
	if not known:
		tv.add_child(UIKit.label("Página en blanco", 36, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
		var r := UIKit.rich(22)
		r.custom_minimum_size = Vector2(470, 0)
		var txt := "[color=#b8aecb]Las letras aparecerán cuando tu renombre llegue a «%s»." % Game.level_name(int(d["level"]))
		if d.has("gift"):
			txt += " O quizá algún viajero te regale esta página…"
		r.text = txt + "[/color]"
		tv.add_child(r)
		return
	Game.mark_page_read(id)
	tv.add_child(UIKit.label(d["name"], 36, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	tv.add_child(UIKit.label(d["kind"], 20, UIKit.MUTED, UIKit.font_italic))
	var eff := UIKit.rich(22)
	eff.custom_minimum_size = Vector2(470, 0)
	eff.text = "[i]%s[/i]" % d["effect"]
	tv.add_child(eff)
	detail.add_child(UIKit.divider())
	# materiales del hechizo
	var row := UIKit.hbox(14)
	detail.add_child(row)
	row.add_child(UIKit.label("Tinta:", 22, UIKit.MUTED))
	var inks: Dictionary = d["inks"]
	for ink in inks:
		var have := Game.item_count(ink)
		var need: int = inks[ink]
		var chip := UIKit.hbox(4)
		chip.add_child(UIKit.icon("res://assets/icons/%s.png" % ink, 2.4))
		chip.add_child(UIKit.label("%s ×%d" % [Data.INKS[ink]["name"], need], 21, UIKit.TEXT if have >= need else UIKit.BAD, UIKit.font_bold))
		chip.add_child(UIKit.label("(tienes %d)" % have, 18, UIKit.MUTED))
		row.add_child(chip)
	# la hoja: papel o vitela (la vitela da una estrella más)
	var prow := UIKit.hbox(10)
	detail.add_child(prow)
	prow.add_child(UIKit.label("Hoja:", 22, UIKit.MUTED))
	if Game.item_count(_paper) <= 0:
		for alt in Data.PAPER_ORDER:
			if Game.item_count(alt) > 0:
				_paper = alt
				break
	for pid in Data.PAPER_ORDER:
		var n := Game.item_count(pid)
		var label := "%s ×%d" % [Data.PAPERS[pid]["name"], n]
		if pid == "vitela":
			label += "  (+1 ★)"
		var pb := UIKit.button(label, func():
			_paper = pid
			_refresh_book(), 19)
		pb.icon = load("res://assets/icons/%s.png" % pid)
		pb.expand_icon = true
		pb.add_theme_constant_override("icon_max_width", 30)
		pb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pb.custom_minimum_size = Vector2(0, 48)
		if pid == _paper:
			pb.add_theme_stylebox_override("normal", UIKit.button_style(Color(0.3, 0.22, 0.14, 0.98), UIKit.GOLD_BRIGHT))
			pb.add_theme_color_override("font_color", UIKit.GOLD_BRIGHT)
		elif n <= 0:
			pb.add_theme_color_override("font_color", Color(0.6, 0.56, 0.68))
		prow.add_child(pb)
	# la runa y lo que vale
	var mid := UIKit.hbox(20)
	detail.add_child(mid)
	mid.add_child(RuneGame.preview(d["rune"], _ink_color(id), 150.0))
	var info := UIKit.vbox(6)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(info)
	info.add_child(UIKit.label("Runa de %d puntos" % d["rune"].size(), 22, UIKit.TEXT, UIKit.font_bold))
	info.add_child(UIKit.label("Precio base: %d oro" % d["base"], 21, Color(1.0, 0.86, 0.45)))
	var stars_now := Game.stars_for(Game.scroll_potency(_paper, false))
	var sh := UIKit.hbox(8)
	info.add_child(sh)
	sh.add_child(UIKit.label("Con esta hoja:", 19, UIKit.MUTED))
	sh.add_child(UIKit.stars(stars_now, 1.2))
	sh.add_child(UIKit.label("(+1 con trazo perfecto)", 18, UIKit.MUTED, UIKit.font_italic))
	if Game.spells_made.has(id):
		var bh := UIKit.hbox(8)
		info.add_child(bh)
		bh.add_child(UIKit.label("Tu mejor pergamino:", 19, UIKit.MUTED))
		bh.add_child(UIKit.stars(Game.stars_for(int(Game.spells_made[id])), 1.2))
	# inscribir
	var why := Game.inscribe_problem(id, _paper)
	var go := UIKit.button("Inscribir pergamino", func(): _inscribe(id), 26)
	go.custom_minimum_size = Vector2(360, 62)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.disabled = why != ""
	detail.add_child(go)
	if why != "":
		var w := UIKit.label(why, 19, UIKit.BAD, UIKit.font_italic, HORIZONTAL_ALIGNMENT_CENTER)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size = Vector2(600, 0)
		detail.add_child(w)

## Color de la tinta principal del hechizo (para la runa).
func _ink_color(id: String) -> Color:
	var inks: Dictionary = Data.SPELLS[id]["inks"]
	for k in inks:
		return Data.INKS[k]["color"]
	return Data.SPELLS[id]["color"]

# ------------------------------------------------------------------ inscribir: la runa

func _inscribe(id: String) -> void:
	if busy:
		return
	var why := Game.inscribe_problem(id, _paper)
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	busy = true
	var col := _ink_color(id)
	ov.close(false)
	if world.grimoire_sprite:
		world.grimoire_sprite.modulate = Color(1.5, 1.4, 1.8)
	Sfx.play("quill", 0.05, -3.0)
	var res: int = await _rune(id, col)
	if world.grimoire_sprite:
		world.grimoire_sprite.modulate = Color.WHITE
	busy = false
	if res < 0:
		ui.toast("Guardaste la pluma. No se gastó nada.")
		return
	var perfect := res == 1
	var s := Game.inscribe(id, _paper, perfect)
	if s.is_empty():
		return
	_celebrate(s, perfect, col)
	inscribed.emit(s, perfect)

## Abre la runa y espera: 1 trazo perfecto, 0 trazada, -1 cancelada (Esc, B o «Guardar la pluma»).
func _rune(id: String, col: Color) -> int:
	var d: Dictionary = Data.SPELLS[id]
	var v := UIKit.vbox(8)
	v.add_child(_title(d["name"], 42))
	var how := "Pasa el cursor (o usa las flechas) por los puntos, en orden, antes de que se consuma la vela."
	if ov.pad_hint != "":
		how = "Mueve el cursor con el stick por los puntos, en orden, antes de que se consuma la vela."
	var hint := UIKit.shadow(UIKit.label(how, 22, UIKit.TEXT, UIKit.font_italic, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(hint)
	var game := RuneGame.new()
	game.points = d["rune"]
	game.ink = col
	game.time_limit = 3.5 + 1.3 * d["rune"].size()
	game.auto_until = demo_auto
	game.custom_minimum_size = Vector2(600, 600)
	game.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(game)
	var cancel := UIKit.button("Guardar la pluma", func(): ov.close(), 20)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cancel)
	ov._open("rune", v)
	var result := [-2]
	game.finished.connect(func(perfect: bool):
		result[0] = 1 if perfect else 0
		cancel.visible = false
		if perfect:
			hint.text = "¡Trazo perfecto! El pergamino tendrá una estrella más."
			hint.add_theme_color_override("font_color", UIKit.GOLD_BRIGHT)
		elif game.completed:
			hint.text = "¡Runa trazada!"
		else:
			hint.text = "La vela se consumió… pero la runa quedó escrita.")
	var on_close := func(cid: String):
		if cid == "rune" and result[0] == -2:
			result[0] = -1
	ov.closed.connect(on_close)
	while result[0] == -2:
		await get_tree().process_frame
		if not is_instance_valid(game) and result[0] == -2:
			result[0] = -1
	ov.closed.disconnect(on_close)
	if result[0] >= 0:
		await get_tree().create_timer(1.2).timeout
		if ov.current == "rune":
			ov.close(false)
	return result[0]

func _celebrate(s: Dictionary, perfect: bool, col: Color) -> void:
	var d: Dictionary = Data.SPELLS[s["id"]]
	var stars := Game.stars_for(int(s["potency"]))
	if world.grimoire_sprite:
		world.spawn_sparkles(world.grimoire_sprite.global_position + Vector3(0, 0.45, 0.2), Color(col.r * 1.6, col.g * 1.6, col.b * 1.6), 26)
	world.alchemist.hop(1)
	_fly_to_rack(s)
	if perfect:
		ui.show_banner("¡Trazo perfecto!", "%s · %d %s" % [d["name"], stars, "estrella" if stars == 1 else "estrellas"])
	else:
		ui.toast("Inscribiste %s (%d %s)." % [d["name"], stars, "estrella" if stars == 1 else "estrellas"], UIKit.GOLD_BRIGHT, 3.0)
	if Game.magic_stats["scrolls"] == 1:
		# --- PREP: los pergaminos son una pestaña del estante de abajo a la derecha
		ui.show_tip("¡Tu primer pergamino! Está en tu estante (abajo a la derecha), en la pestaña [b]Pergaminos[/b].\nAlgunos clientes piden pergaminos: tócalo allí para entregarlo, como una poción.")
	elif main.customer_ready and main.current.get("scroll", "") == s["id"]:
		ui.toast("Justo lo que pidió %s: tócalo en el estante para entregarlo." % Data.CHARACTERS[main.current["who"]]["name"], UIKit.GOOD, 3.5)
	# --- INTEGRATE: la corazonada (STORY), como con las pociones: si un cliente espera un pergamino, Miga ronronea
	# y ella piensa «Esto debería funcionar…» (o duda, si no es el que pidió)
	if main.has_method("intuition_after_craft"):
		main.intuition_after_craft("scroll", String(s["id"]))
	# --- end INTEGRATE

## El pergamino vuela (en la pantalla) hasta su lugar en el estante de pergaminos.
func _fly_to_rack(s: Dictionary) -> void:
	# el estante se acaba de rehacer: sus huecos tienen posición después de que el contenedor los acomode
	await get_tree().process_frame
	await get_tree().process_frame
	var idx := Game.scroll_index(s["id"], int(s["potency"]))
	var tex: Texture2D = load("res://assets/icons/spell_%s.png" % s["id"])
	var c := TextureRect.new()
	c.texture = tex
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.size = Vector2(64, 64)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 40
	ui.root.add_child(c)
	var from := ui.root.size / 2.0 - Vector2(32, 32)
	var to := ui.scroll_slot_center(idx) - Vector2(32, 32)
	c.position = from
	var mid := from.lerp(to, 0.5) + Vector2(0, -160)
	var tw := c.create_tween()
	tw.tween_property(c, "position", mid, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		Sfx.play("plop", 0.1, -6.0)
		c.queue_free())

# ------------------------------------------------------------------ páginas nuevas

## Al subir de nivel o al terminar un capítulo de un viajero: anuncia las páginas recién aprendidas.
func _announce_pages() -> void:
	# --- INTEGRATE: nada de avisos tapados por un panel (el correo de la mañana, una subida de nivel...): espera a que
	# no quede ninguno abierto durante un momento (al cerrarse el correo puede abrirse justo la subida de nivel)
	var calm := 0.0
	while calm < 0.35:
		await get_tree().process_frame
		calm = 0.0 if ov.is_open() else calm + get_process_delta_time()
	# --- end INTEGRATE
	var news := Game.new_spell_pages()
	if news.is_empty():
		return
	for id in news:
		var d: Dictionary = Data.SPELLS[id]
		var g: Dictionary = d.get("gift", {})
		if not g.is_empty() and Game.level() < int(d["level"]):
			ui.toast(g["text"], UIKit.GOLD_BRIGHT, 4.5)
	var names := []
	for id in news:
		names.append(Data.SPELLS[id]["name"])
	var what: String = names[0] if names.size() == 1 else ", ".join(names.slice(0, names.size() - 1)) + " y " + names[-1]
	if Game.magic_unlocked:
		ui.toast("Nueva página en el grimorio: %s." % what, UIKit.GOLD_BRIGHT, 4.0)
	else:
		ui.toast("En la biblioteca, el grimorio de tu maestra empezó a brillar…", UIKit.GOLD_BRIGHT, 4.0)
	if world and world.grimoire_sprite:
		world.spawn_sparkles(world.grimoire_sprite.global_position + Vector3(0, 0.4, 0.15), Color(1.4, 1.2, 1.9), 20)
