class_name Glyphs
## --- R6 UI: qué botón hay que pulsar. Sigue el último dispositivo que se usó (teclado, ratón o mando) y dibuja su
## glifo: una tecla de pergamino con su letra (E, Space, Esc...), el ratón con el botón que se pulsa en dorado, o el
## botón del mando con su color (A verde, B rojo, X azul, Y ámbar, LB / RB, Vista, Menú, la cruceta). Lo usan los
## avisos de acción sobre la gente y las estaciones (PromptUI), los botones del HUD (HudButton), las respuestas del
## diálogo, el estante (elegir una poción) y los botones principales de los papeles. El arte sale de
## tools/arte/ui_art.py --r6 (assets/ui/r6_key9*.png, r6_pad_*.png, r6_mouse_*.png).
## Quién cuenta: GlyphWatcher (abajo; main.gd lo pone como su último hijo, así ve cada evento antes que nadie).

const PAD_DEVICE := 77            # = PadCursor.PAD_DEVICE: los eventos que inventa el mando no cuentan como teclado
const INK := Color("3a2618")

static var device := "keys"       # "keys" | "mouse" | "pad"
static var gen := 0               # sube cada vez que cambia el dispositivo (los glifos se rehacen)
static var forced := ""           # (capturas y pruebas) --glyphs=keys|mouse|pad fija el dispositivo
static var _acc := 0.0
static var _acc_t := 0

## Cada acción: [tecla, botón del mando ("" = ninguno), botón del ratón ("left" / "right" / "" = ninguno)].
const ACTIONS := {
	"interact": ["E", "a", "left"],       # usar lo que hay delante (hablar, dar la poción, preparar, comprar...)
	"alt": ["Space", "x", "left"],        # la segunda acción del mismo sitio (hablar mientras hay pociones)
	"back": ["Esc", "b", ""],
	"confirm": ["Enter", "a", ""],        # el botón principal de un papel (Dormir, Siguiente, Listo...)
	"pick": ["E", "a", "left"],           # elegir en el estante
	"choose": ["← →", "dpad_lr", ""],
	"shelf": ["Tab", "", "left"],         # el estante con el banco abierto
	"open": ["O", "", ""],
	"market": ["M", "", ""],
	"recipes": ["R", "y", ""],
	"journal": ["J", "view", ""],
	"rankings": ["G", "", ""],
	"settings": ["Esc", "menu", ""],
	"choice1": ["1", "a", ""],
	"choice2": ["2", "", ""],
	"choice3": ["3", "", ""],
	"stir": ["Space", "x", ""],
	"bench": ["E", "a", ""],
}

## El nombre corto de cada botón del mando (para los textos).
const PAD_NAMES := {"a": "A", "b": "B", "x": "X", "y": "Y", "view": "View", "menu": "Menu", "lb": "LB", "rb": "RB",
	"dpad_lr": "D-pad"}

static func set_device(d: String) -> void:
	if forced != "":
		d = forced
	if d != device:
		device = d
		gen += 1

## Lo llama GlyphWatcher con cada evento de entrada.
static func note(ev: InputEvent) -> void:
	if forced != "":
		return
	if ev is InputEventJoypadButton:
		if ev.pressed:
			set_device("pad")
		return
	if ev is InputEventJoypadMotion:
		if absf(ev.axis_value) > 0.55:
			set_device("pad")
		return
	if ev.device == PAD_DEVICE:
		return   # lo inventó el mando (PadCursor): ya contó como mando
	if ev is InputEventKey:
		if ev.pressed and not ev.echo and not ev.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			_acc = 0.0
			set_device("keys")
	elif ev is InputEventMouseButton:
		if ev.pressed:
			set_device("mouse")
	elif ev is InputEventMouseMotion:
		# un ratón de verdad que se mueve un poco (no un temblor de la mano)
		var t := Time.get_ticks_msec()
		if t - _acc_t > 400:
			_acc = 0.0
		_acc_t = t
		_acc += ev.relative.length()
		if _acc > 28.0:
			set_device("mouse")
	elif ev is InputEventScreenTouch:
		set_device("mouse")

static func key_of(action: String) -> String:
	return String(ACTIONS.get(action, ["", "", ""])[0])

static func pad_of(action: String) -> String:
	return String(ACTIONS.get(action, ["", "", ""])[1])

## El glifo de una acción para el dispositivo dev ("" = el de ahora), o null si ese dispositivo no tiene botón para ella.
## small: el tamaño de los botones (arte a 2x). keys_on_mouse: con el ratón muestra la tecla (los botones del HUD, que
## ya se ven tocables) en vez del ratón (los avisos sobre la gente y las estaciones).
static func make(action: String, dev := "", small := false, keys_on_mouse := false) -> Control:
	if dev == "":
		dev = device
	# "key:<tecla>": una tecla suelta (los frascos del banco: 1-8; ← → en la bola), solo con teclado y ratón
	if action.begins_with("key:"):
		return key_cap(action.substr(4), small) if dev != "pad" else null
	var a: Array = ACTIONS.get(action, ["", "", ""])
	var sfx := "_2x" if small else ""
	match dev:
		"pad":
			if String(a[1]) == "":
				return null
			return _pic("r6_pad_%s%s" % [a[1], sfx], String(PAD_NAMES.get(a[1], a[1])))
		"mouse":
			if not keys_on_mouse and String(a[2]) != "":
				return _pic("r6_mouse_%s%s" % [a[2], sfx], "Click")
			if keys_on_mouse and String(a[0]) != "":
				return key_cap(String(a[0]), small)
			return null
		_:
			if String(a[0]) == "":
				return null
			return key_cap(String(a[0]), small)

## Una tecla de pergamino con su nombre escrito a tinta (nine-patch: crece a lo ancho para «Space», «Enter»...).
static func key_cap(label: String, small := false) -> Control:
	UIKit.load_fonts()
	var p := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	# la chica es otra tecla (7x8 px de arte) también a 3x: a 1280x720 cada píxel de arte son 2 px, nítida
	sb.texture = load("res://assets/ui/r6_key9_mini.png" if small else "res://assets/ui/r6_key9.png")
	var m := 6 if small else 9
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = 9 if small else 12
	sb.content_margin_left = 5 if small else 9
	sb.content_margin_right = 5 if small else 9
	sb.content_margin_top = 0 if small else 1
	sb.content_margin_bottom = 6 if small else 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(21, 24) if small else Vector2(33, 36)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := 17 if small else 23
	if label.length() > 1:
		fs = 15 if small else 19
	var l := UIKit.label(label, fs, INK, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.tooltip_text = ""
	p.set_meta("glyph", label)
	return p

## Pega un glifo a un botón (que se rehace solo con el dispositivo): "right" a la derecha y centrado (dejando aire en sus
## estilos propios para que el texto no lo pise), "corner" en la esquina de arriba a la derecha (los botones cuadrados
## del banco), "topleft" en la de arriba a la izquierda. Devuelve el Chip.
static func attach_chip(host: Control, action: String, where := "right", small := false, inset := Vector2(14, 0)) -> Chip:
	var chip := Chip.new(action, small, true)
	chip.name = "R6Key"
	chip.host = host
	chip.where = where
	chip.inset = inset
	host.add_child(chip)
	# (métodos del propio Chip, no una lambda: si el botón se libera en el mismo cuadro, por ejemplo al rehacerse la
	# hoja del correo, la llamada diferida se descarta sola en vez de dar «Lambda capture was freed»)
	host.resized.connect(chip.place)
	chip.rebuilt.connect(chip.place)
	chip.place.call_deferred()
	return chip

static func _pic(name: String, what: String) -> TextureRect:
	var t := PaperKit.pic(name, 1.0)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.set_meta("glyph", what)
	return t

## Un glifo que se rehace solo cuando cambia el dispositivo (o la acción). Se esconde si el dispositivo de ahora no
## tiene botón para esa acción. small / keys_on_mouse: como en Glyphs.make.
class Chip extends HBoxContainer:
	signal rebuilt
	var action := ""
	var small := false
	var keys_on_mouse := false
	var only := []                # si no está vacío: los dispositivos en los que se ve ("keys", "mouse", "pad")
	var host: Control             # (attach_chip) el botón que lo lleva: desactivado, el glifo se apaga
	var where := "right"          # (attach_chip) dónde va en el botón: "right", "corner" o "topleft"
	var inset := Vector2(14, 0)
	var _gen := -1

	func _init(a := "", sm := false, kom := false) -> void:
		action = a
		small = sm
		keys_on_mouse = kom
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 0)

	func _ready() -> void:
		_rebuild()

	func _process(_d: float) -> void:
		if _gen != Glyphs.gen:
			_rebuild()
		if host is BaseButton:
			modulate.a = 0.4 if (host as BaseButton).disabled else 1.0

	## (attach_chip) se coloca en su botón: "right" a la derecha y centrado, "corner" arriba a la derecha, "topleft"
	## arriba a la izquierda.
	func place() -> void:
		if not is_instance_valid(host):
			return
		reset_size()
		if where == "right":
			_fit_host()
		var s := size
		match where:
			"corner":
				position = Vector2(host.size.x - s.x + inset.x, inset.y)
			"topleft":
				position = Vector2(inset.x, inset.y)
			_:
				position = Vector2(host.size.x - s.x - inset.x, roundf((host.size.y - s.y) * 0.5) - 2.0 + inset.y)

	## "right": el texto del botón no debe quedar debajo de la tecla. Se deja a la derecha, en sus estilos propios, el
	## ancho de la tecla de ahora (no es lo mismo «Enter» que la A del mando) más el aire: el botón crece lo justo.
	func _fit_host() -> void:
		var extra := (size.x + inset.x + 8.0) if visible else 0.0
		var changed := false
		for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			if not host.has_theme_stylebox_override(st):
				continue
			var sb: StyleBox = host.get_theme_stylebox(st)
			if not sb.has_meta("r6_mr0"):
				sb.set_meta("r6_mr0", sb.get_margin(SIDE_RIGHT))
			var want: float = float(sb.get_meta("r6_mr0")) + extra
			if absf(sb.content_margin_right - want) > 0.5:
				sb.content_margin_right = want
				changed = true
		if changed:
			host.update_minimum_size()

	func set_action(a: String) -> void:
		if a != action:
			action = a
			_rebuild()

	func _rebuild() -> void:
		_gen = Glyphs.gen
		for c in get_children():
			remove_child(c)
			c.queue_free()
		var g: Control = null
		if only.is_empty() or Glyphs.device in only:
			g = Glyphs.make(action, "", small, keys_on_mouse)
		if g:
			add_child(g)
		visible = g != null
		reset_size()
		rebuilt.emit()

## El vigilante: un nodo sin nada más que mirar cada evento de entrada (main.gd lo agrega el último, así su _input
## llega antes que el de nadie: también ve los botones del mando antes de que PadCursor los dé por usados).
class GlyphWatcher extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(ev: InputEvent) -> void:
		Glyphs.note(ev)
