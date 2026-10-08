extends Control
## "Los dioses te ofrecen un don": three cards after each dawn. Mouse hover / click, keys 1-2-3, arrows or the
## stick plus A / Enter. Cards rise in one after another; the chosen one glows in its god's colour.

const S := preload("res://scripts/ui/style.gd")
const W := preload("res://scripts/ui/widgets.gd")
const G := preload("res://scripts/ui/glyphs.gd")

const CARD_W := 250.0
const CARD_GAP := 26.0
const MEDAL_R := 42.0

var _ids: Array = []
var _cards: Array = []
var _deck: Control # header, "Elige uno" and the cards; scaled as one piece on small screens
var _header: Control
var _sub: Control
var _veil: Control
var _open := false
var _chosen := -1


## One god's card. Drawn in code; the texts are labels so they wrap and shape properly.
class Card extends Control:
	signal picked(card: Card)
	var id := ""
	var index := 0
	var god_color := Color.WHITE
	var icon := "sun"
	var k := 0.0 # focus amount
	var enter := 0.0 # entrance 0..1
	var glow := 0.0 # chosen flash
	var base_pos := Vector2.ZERO
	var _col: VBoxContainer
	var _god: Label
	var _title: Label
	var _desc: Label
	var _key: Control
	var _tw: Tween

	func _init(bid: String, i: int) -> void:
		id = bid
		index = i
		var b: Dictionary = Data.BLESSINGS[bid]
		god_color = b["color"]
		icon = b["icon"]
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		_col = VBoxContainer.new()
		_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_col.add_theme_constant_override("separation", 4)
		add_child(_col)
		_god = S.label(String(b["god"]).to_upper(), S.CINZEL_BOLD, 23, god_color.lerp(Color.WHITE, 0.35), 4, 4)
		_god.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(_god)
		_title = S.label(String(b["title"]), S.ITALIC, 23, S.IVORY, 0, 4)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(_title)
		var orn := W.Ornament.new("rule", 150.0, Color(god_color, 0.7))
		orn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_col.add_child(orn)
		_desc = S.label(S.nb(String(b["desc"])), S.GARAMOND, 18, Color(S.IVORY, 0.86), 0, 3)
		_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(_desc)
		_key = G.new().setup_caps([["key", str(i + 1)]], 26.0)
		add_child(_key)
		mouse_entered.connect(_on_hover)
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))

	## Where the text column starts: below the medallion.
	static func text_top() -> float:
		return 30.0 + MEDAL_R * 2.0 + 26.0

	## Height this card needs at width `w` for all of its text (measured with the fonts, not guessed).
	func needed_height(w: float) -> float:
		var tw := w - 36.0
		var hh := 0.0
		for l in [_god, _title]:
			var ls: LabelSettings = (l as Label).label_settings
			hh += ls.font.get_height(ls.font_size)
		hh += 9.0
		var ds: LabelSettings = _desc.label_settings
		hh += ds.font.get_multiline_string_size(_desc.text, HORIZONTAL_ALIGNMENT_CENTER, tw, ds.font_size).y
		hh += 4.0 * 3.0
		return text_top() + hh + 64.0

	func layout(w: float, h: float) -> void:
		custom_minimum_size = Vector2(w, h)
		size = Vector2(w, h)
		var pad := 18.0
		var top := text_top()
		_col.position = Vector2(pad, top)
		_col.size = Vector2(w - pad * 2.0, h - top - 52.0)
		_desc.custom_minimum_size = Vector2(w - pad * 2.0, 0)
		_key.position = Vector2((w - _key.get_combined_minimum_size().x) * 0.5, h - 42.0)
		pivot_offset = Vector2(w * 0.5, h * 0.6)

	func _on_hover() -> void:
		if not has_focus() and focus_mode != Control.FOCUS_NONE:
			grab_focus()

	func _on_focus(on: bool) -> void:
		if on and not S.is_quiet():
			S.sfx("ui_move")
		if _tw:
			_tw.kill()
		_tw = S.tween(self)
		_tw.tween_method(_set_k, k, 1.0 if on else 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _set_k(v: float) -> void:
		k = v
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_accept"):
			accept_event()
			picked.emit(self)
		elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit(self)

	func show_key(on: bool) -> void:
		_key.visible = on

	func _process(_d: float) -> void:
		position = base_pos + Vector2(0, 70.0 * (1.0 - S.ease_out(enter)) - 12.0 * k)
		modulate.a = S.ease_out(enter)
		if glow > 0.0 or k > 0.0:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var t := S.now()
		var gc := god_color
		# Halo behind the card when focused or chosen.
		var halo := maxf(k * 0.6, glow)
		if halo > 0.01:
			for i in 4:
				var sb0 := S.box(Color(gc, (0.06 - i * 0.012) * halo), 18 + i * 5)
				draw_style_box(sb0, Rect2(Vector2.ZERO, size).grow(4.0 + i * 5.0))
		var sb := S.panel(0.74, 14, Color(gc, 0.3 + 0.55 * k + 0.3 * glow), 0.0)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# Accent line on top.
		draw_line(Vector2(w * 0.2, 1.5), Vector2(w * 0.8, 1.5), Color(gc, 0.55 + 0.4 * k), 2.0, true)
		# Medallion with the god's symbol.
		var r := MEDAL_R
		var c := Vector2(w * 0.5, 30.0 + r)
		var pulse := 0.5 + 0.5 * sin(t * 2.4 + index)
		for i in 5:
			draw_circle(c, r + 4.0 + i * 5.0, Color(gc, (0.05 + 0.04 * k) * (1.0 - i / 5.0) * (0.8 + 0.2 * pulse)))
		draw_circle(c, r, Color(S.PANEL, 0.9))
		draw_arc(c, r, 0.0, TAU, 48, Color(gc, 0.8), 1.5, true)
		draw_arc(c, r - 5.0, 0.0, TAU, 48, Color(gc, 0.25), 1.0, true)
		var isz := r * 1.15
		Icons.draw(self, icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), gc.lerp(Color.WHITE, 0.15 + 0.2 * glow))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_veil = Control.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.draw.connect(_draw_veil)
	add_child(_veil)
	_deck = Control.new()
	_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deck)
	_header = W.TrackedText.new("LOS DIOSES TE OFRECEN UN DON", S.CINZEL, 32, 9.0, S.GOLD, 1)
	_deck.add_child(_header)
	_sub = HBoxContainer.new()
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_sub as HBoxContainer).add_theme_constant_override("separation", 10)
	_deck.add_child(_sub)
	resized.connect(_layout)


func is_open() -> bool:
	return _open


func _draw_veil() -> void:
	var w := _veil.size.x
	var h := _veil.size.y
	var a := 0.5
	var ink := S.INK
	_veil.draw_rect(Rect2(0, 0, w, h), Color(ink, 0.22))
	var clear := Color(ink, 0.0)
	_veil.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.35), Vector2(0, h * 0.35)]), PackedColorArray([Color(ink, a), Color(ink, a), clear, clear]))
	_veil.draw_polygon(PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)]), PackedColorArray([clear, clear, Color(ink, a), Color(ink, a)]))


func open(ids: Array) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_ids = ids.duplicate()
	_chosen = -1
	_open = true
	visible = true
	modulate.a = 1.0
	_fill_sub()
	var i := 0
	for id in _ids:
		if not Data.BLESSINGS.has(id):
			continue
		var c := Card.new(String(id), i)
		c.picked.connect(_on_picked)
		_deck.add_child(c)
		_cards.append(c)
		i += 1
	for j in _cards.size():
		var a: Card = _cards[j]
		var b: Card = _cards[(j + 1) % _cards.size()]
		a.focus_neighbor_right = a.get_path_to(b)
		b.focus_neighbor_left = b.get_path_to(a)
		a.focus_neighbor_top = a.get_path_to(a)
		a.focus_neighbor_bottom = a.get_path_to(a)
	_layout()
	_veil.modulate.a = 0.0
	_header.modulate.a = 0.0
	_sub.modulate.a = 0.0
	var tw := S.tween(self)
	tw.set_parallel(true)
	tw.tween_property(_veil, "modulate:a", 1.0, 0.5)
	tw.tween_property(_header, "modulate:a", 1.0, 0.6).set_delay(0.15)
	tw.tween_method((_header as W.TrackedText).set_tracking, 22.0, 9.0, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.5).set_delay(0.5)
	for j in _cards.size():
		var c: Card = _cards[j]
		c.enter = 0.0
		c.focus_mode = Control.FOCUS_NONE
		tw.tween_property(c, "enter", 1.0, 0.65).set_delay(0.3 + 0.11 * j).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_ready_to_pick)


func _ready_to_pick() -> void:
	if not _open:
		return
	for c in _cards:
		(c as Card).focus_mode = Control.FOCUS_ALL
	if not _cards.is_empty() and _chosen < 0:
		var mid: Card = _cards[mini(1, _cards.size() - 1)] if G.device != "kb" else _cards[0]
		if G.device != "touch":
			S.focus_quiet(mid)


func _fill_sub() -> void:
	for c in _sub.get_children():
		_sub.remove_child(c)
		c.queue_free()
	var l := S.label("Elige uno", S.ITALIC, 21, Color(S.IVORY, 0.85), 0, 4)
	_sub.add_child(l)
	var g: Control = G.new().setup("pick", 24.0)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sub.add_child(g)
	for c in _cards:
		(c as Card).show_key(G.device == "kb")


## Lays the deck out at its natural size, then scales it down as one piece if the screen is small.
func _layout() -> void:
	if _cards.is_empty():
		return
	var n := _cards.size()
	var cw := CARD_W
	var ch := 360.0
	for c in _cards:
		ch = maxf(ch, (c as Card).needed_height(cw))
	ch = ceilf(ch)
	var cards_w := cw * n + CARD_GAP * (n - 1)
	_header.size = _header.custom_minimum_size
	_sub.size = _sub.get_combined_minimum_size()
	var deck_w := maxf(cards_w, _header.size.x)
	var cards_y := _header.size.y + 18.0 + _sub.size.y + 30.0
	var deck_h := cards_y + ch + 16.0
	_header.position = Vector2((deck_w - _header.size.x) * 0.5, 0.0)
	_sub.position = Vector2((deck_w - _sub.size.x) * 0.5, _header.size.y + 14.0)
	var x0 := (deck_w - cards_w) * 0.5
	for j in n:
		var c: Card = _cards[j]
		c.layout(cw, ch)
		c.base_pos = Vector2(x0 + j * (cw + CARD_GAP), cards_y)
	_deck.size = Vector2(deck_w, deck_h)
	var vw := size.x
	var vh := size.y
	var f := minf(1.0, minf((vw - 40.0) / deck_w, (vh - 48.0) / deck_h))
	_deck.scale = Vector2(f, f)
	_deck.position = Vector2((vw - deck_w * f) * 0.5, maxf(16.0, (vh - deck_h * f) * 0.46)).round()


func _process(_d: float) -> void:
	if _open and _sub.get_child_count() > 0:
		var want_keys := G.device == "kb"
		if not _cards.is_empty() and (_cards[0] as Card)._key.visible != want_keys:
			_fill_sub()
			_layout()


func _input(e: InputEvent) -> void:
	if not _open or _chosen >= 0:
		return
	for j in 3:
		if e.is_action_pressed("pick_%d" % (j + 1)) and j < _cards.size():
			get_viewport().set_input_as_handled()
			_on_picked(_cards[j])
			return


func _on_picked(c: Card) -> void:
	if _chosen >= 0 or not _open or c.enter < 0.6:
		return
	_chosen = _cards.find(c)
	S.sfx("ui_select")
	var tw := S.tween(self)
	tw.set_parallel(true)
	c.focus_mode = Control.FOCUS_NONE
	tw.tween_property(c, "glow", 1.0, 0.25)
	tw.tween_property(c, "scale", Vector2(1.06, 1.06), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for o in _cards:
		if o != c:
			(o as Card).focus_mode = Control.FOCUS_NONE
			tw.tween_property(o, "enter", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_header, "modulate:a", 0.0, 0.4).set_delay(0.2)
	tw.tween_property(_sub, "modulate:a", 0.0, 0.3)
	tw.chain().tween_interval(0.35)
	tw.chain().tween_callback(func() -> void:
		var id: String = c.id
		close()
		if Game.main and Game.main.has_method("choose_blessing"):
			Game.main.choose_blessing(id))


func close() -> void:
	if not _open:
		return
	_open = false
	get_viewport().gui_release_focus()
	var tw := S.tween(self)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		if not _open:
			visible = false)
