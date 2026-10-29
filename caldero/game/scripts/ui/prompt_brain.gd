extends Node
class_name PromptBrain
## --- R6 UI: qué se puede hacer desde donde está ella y con qué botón. Cada cuadro mira el estado del juego (main.gd)
## y arma los avisos de acción (PromptUI dibuja las placas) y lo que hace cada botón:
##   "interact" = E / A del mando (o un clic en la persona o la estación) · "alt" = Espacio / X del mando.
## La tienda (según la estación en cuya zona está ella):
##   mostrador: de mañana «Open shop»; con un cliente: «Talk» o, si ya pidió y hay pociones, «Give potion» (E: si en el
##     estante hay una sola clase de poción se la da; si hay varias se abre el estante para elegir) + «Talk» (Espacio).
##     Con el ratón: «Talk» sobre el cliente y «Give potion» sobre el estante (se toca la poción).
##   caldero «Brew» · escritorio de la biblioteca «Enchant» (o «Grimoire») · puerta «Go to market» (de mañana) ·
##   ventanilla del cuervo «Hand over» (el cuervo espera: abre la bola, que tiene su bandeja) o «Read orders».
## El mercado: en un puesto «Buy», en la puerta de la tienda «Back to shop».
## Un evento: con el banco cerrado «Brew» (y en el concurso «Present»: el estante para elegir la poción del jurado).
## Con el banco abierto y alguien a quien darle una poción: «Tab  Give» / «Present» sobre el estante.
## main.gd llama press("interact") / press("alt") con E / Espacio, y PadCursor con A / X (cuando el cursor no está
## sobre algo tocable). Las placas nunca tapan las caras, el ticket, la fila ni al cuervo (ver _avoid_world).

## Cuánto aire (m) sobre lo alto de su dibujo va la colita de los avisos que salen encima de ella (su dibujo tiene un
## margen vacío sobre la punta del sombrero: con -0.08 la colita queda a unos 12 px del sombrero a 1280x720).
const HER_UP := -0.08

var main
var ui: GameUI
var _acts := {}             # "interact" / "alt" / "shelf" -> Callable
var _specs: Array = []
var _avoid: Array = []
var enabled := true

func setup(m) -> void:
	main = m
	ui = m.ui
	process_priority = 50   # después de que todo se movió en el cuadro (la cámara, la gente)

func _process(_d: float) -> void:
	_compute()
	if ui and ui.prompts:
		ui.prompts.update_prompts(_specs if enabled else [], _avoid)

## Hace la acción de ese botón si ahora hay una. true si la hizo (entonces el botón no hace nada más).
func press(slot: String) -> bool:
	_compute()
	if not enabled or not _acts.has(slot):
		return false
	var cb: Callable = _acts[slot]
	if cb.is_valid():
		cb.call()
		return true
	return false

## Si ahora ese botón tiene una acción (PadCursor lo pregunta antes de convertir A en un clic).
func has_action(slot: String) -> bool:
	return enabled and _acts.has(slot)

## Lo que dice ahora cada aviso (las pruebas): {id: [[acción, palabra], ...]}.
func current() -> Dictionary:
	var out := {}
	for s in _specs:
		out[String(s["id"])] = s["acts"]
	return out

# ------------------------------------------------------------------ qué hay

func _compute() -> void:
	_acts = {}
	_specs = []
	_avoid = []
	if main == null or ui == null or not is_instance_valid(main.world):
		return
	var ph: String = main.r6_phase()
	if ui.picker_open():
		_add("picker", _shelf_point(), [["choose", "Choose"], ["pick", ui.picker_verb()], ["back", "Back"]], {})
		_avoid_hud()
		return
	if ph == "EVENT":
		_event()
	elif ph == "MORNING" or ph == "OPEN":
		if main.in_market:
			_market()
		else:
			_shop(ph)
	if not _specs.is_empty():
		_avoid_hud()

## Nada abierto ni a medias: ni papeles, ni diálogo, ni banco, ni bola, ni viaje, ni el estante para elegir.
func _free() -> bool:
	return not main.ov.is_open() and not main.busy and not ui.dialog_open() and not main._brew_open() \
		and not main._ball_open() and not main._trip_busy and not ui.picker_open()

## Ella va caminando sola hacia un sitio (un clic): los avisos esperan a que llegue (no parpadean al pasar).
func _auto_walking(w: Walker) -> bool:
	return w == null or w.frozen or w._has_target

func _shop(ph: String) -> void:
	var w: ShopWorld = main.world
	if not _free() or _auto_walking(w.walker):
		if ph == "OPEN" and main._brew_open() and not main.ov.is_open() and not ui.dialog_open() and not ui.picker_open():
			_bench_shelf_hint()
		return
	var cam: Camera3D = w.camera
	var st := w.current_station()
	match st:
		"mostrador":
			if ph == "MORNING":
				# (con el ratón no: tocar el mostrador no abre la tienda; para eso está el botón de arriba)
				if Glyphs.device != "mouse" and not _thinking():   # --- R6 SHIP: (_thinking, abajo)
					_add("counter", _over(w.alchemist, cam, HER_UP), [["interact", "Open shop"]], {})
				_acts["interact"] = main._open_shop
			else:
				_counter(w, cam)
		"caldero":
			_add("cauldron", _pt(cam, ShopWorld.CAULDRON_POS + Vector3(0.0, 1.32, 0.0)), [["interact", "Brew"]],
				{"interact": func(): w.use_station("caldero")})
		"biblioteca":
			var verb := "Grimoire"
			if Game.magic_unlocked and not Game.potions.is_empty() and not Game.known_runes().is_empty():
				verb = "Enchant"
			_add("desk", _pt(cam, ShopWorld.DESK_POS + Vector3(0.0, 1.7, 0.15)), [["interact", verb]],
				{"interact": func(): w.use_station("biblioteca")})
		"puerta":
			if ph == "MORNING":
				_add("door", _pt(cam, Vector3(4.0, 2.75, -3.8)), [["interact", "Go to market"]], {"interact": main._go_market})
		"ventanilla":
			if ph == "OPEN" and main.krapido and main.krapido.active():
				var verb := "Hand over" if main.krapido.raven_waiting() else "Read orders"
				# --- R6 SHIP: mientras piensa en voz alta (p. ej. «Hope it goes well…» al darle la poción al cuervo) la placa
				# no sale (su colita cruzaba las palabras); E sigue funcionando
				if _thinking():
					_acts["interact"] = func(): w.use_station("ventanilla")
				else:
					_add("window", _over(w.alchemist, cam, HER_UP), [["interact", verb]], {"interact": func(): w.use_station("ventanilla")})
				# --- end R6 SHIP
	if not _specs.is_empty():
		_avoid_world(w, cam)

# --- R6 SHIP: ella está pensando en voz alta (main._think: unas palabras en cursiva justo encima de su cabeza, ~3,6 s).
# Las placas que salen encima de ella («Open shop» de mañana, la ventanilla del cuervo) esperan a que se borren.
func _thinking() -> bool:
	var th = main.get("_thought")
	return th != null and is_instance_valid(th) and th is Label3D and (th as Label3D).visible
# --- end R6 SHIP

## El mostrador con la tienda abierta: hablar con quien espera o darle su poción.
func _counter(w: ShopWorld, cam: Camera3D) -> void:
	if not main.customer_ready or not is_instance_valid(main.customer):
		return
	var cur: Dictionary = main.current
	var cv: Dictionary = main._counter_v
	var head := _over(main.customer, cam, 0.66)   # por encima de su reloj de arena
	var ordered := bool(cv.get("ordered", false)) and String(cur.get("kind", "")) != "return"
	if ordered and not Game.potions.is_empty():
		var give := _give_spec()
		if Glyphs.device == "mouse" and ui.potion_panel.is_visible_in_tree():
			# con el ratón: se habla tocando a la persona y se da la poción tocándola en el estante
			_add("counter", head, [["alt", "Talk"]], {})
			_add("shelf", _shelf_point(), [give], {})
		else:
			_add("counter", head, [give, ["alt", "Talk"]], {})
		_acts["interact"] = _give
		_acts["alt"] = main._on_customer_clicked
	else:
		_add("counter", head, [["interact", "Talk"]], {"interact": main._on_customer_clicked})

## «Give» con el icono de la poción si en el estante hay una sola clase (E se la da enseguida); si hay varias,
## «Give potion» (E abre el estante para elegir).
func _give_spec() -> Array:
	var one := _one_kind()
	if one >= 0:
		return ["interact", "Give", "res://assets/icons/pot_%s.png" % String(Game.potions[one]["id"])]
	return ["interact", "Give potion"]

## El índice de la poción si todas las del estante son iguales (misma poción, estrellas y runas); si no, -1.
func _one_kind() -> int:
	if Game.potions.is_empty():
		return -1
	var k0 := _pkey(Game.potions[0])
	for p in Game.potions:
		if _pkey(p) != k0:
			return -1
	return 0

func _pkey(p: Dictionary) -> String:
	return "%s|%d|%s|%s" % [p.get("id", ""), Game.stars_for(int(p.get("potency", 0))), p.get("rune", ""), p.get("rune2", "")]

func _give() -> void:
	if Game.potions.is_empty():
		return
	var one := _one_kind()
	if one >= 0:
		ui.potion_pressed.emit(one)
	else:
		ui.open_picker("Give")

## Con el banco abierto, si hay a quién darle (o presentarle) una poción: el aviso va sobre el estante.
func _bench_shelf_hint() -> void:
	if Game.potions.is_empty() or not ui.potion_panel.is_visible_in_tree():
		return
	var verb := ""
	if main.r6_phase() == "EVENT":
		var g = main.ev_game
		if is_instance_valid(g) and g.running and not g.over and String(g.kind) == "concurso":
			verb = "Present"
	elif main.customer_ready and is_instance_valid(main.customer) and bool(main._counter_v.get("ordered", false)) \
			and String(main.current.get("kind", "")) != "return":
		verb = "Give"
	if verb == "":
		return
	_add("shelf", _shelf_point(), [["shelf", verb]], {"shelf": func(): ui.open_picker(verb)})

func _market() -> void:
	var m: MarketWorld = main.market
	if not _free() or _auto_walking(m.walker):
		return
	var cam: Camera3D = m.camera
	var st: String = m.walker.current
	if st == "":
		return
	if st == "tienda":
		var door: Node3D = m.station_nodes.get("tienda")
		# (sobre la parte de arriba de la puerta, debajo del letrero «Midnight Cauldron»: a 2.45 m lo tapaba)
		var at := _over(m.alchemist, cam, HER_UP) if door == null else _pt(cam, door.global_position + Vector3(0.0, 1.95, 0.35))
		_add("shopdoor", at, [["interact", "Back to shop"]], {"interact": main._leave_market})
	else:
		_add("stall", _over(m.alchemist, cam, HER_UP), [["interact", "Buy"]], {"interact": func(): m.use_station(st)})
		# las caras de los vendedores y de la gente que pasa no se tapan
		for v in m.vendors.values():
			_avoid.append(_face(v, cam))
	_avoid.append(_face(m.alchemist, cam))

func _event() -> void:
	var g = main.ev_game
	if not is_instance_valid(g) or not g.running or g.over or not is_instance_valid(g.her):
		return
	if main.ov.is_open() or ui.dialog_open() or main.events_ui.modal_open() or ui.picker_open():
		return
	if main._brew_open():
		_bench_shelf_hint()
		return
	# el banco cerrado: su botón de abajo («Cauldron», con la tecla E dibujada) es el aviso; E y A del mando lo abren
	_acts["interact"] = main._ev_open_bench
	if String(g.kind) == "concurso" and not Game.potions.is_empty() and ui.potion_panel.is_visible_in_tree():
		_add("shelf", _shelf_point(), [["alt", "Present"]], {"alt": func(): ui.open_picker("Present")})

func _ev_camera() -> Camera3D:
	if not is_instance_valid(main.ev_scene):
		return null
	return main.ev_scene.get_node_or_null("Camera") as Camera3D

# ------------------------------------------------------------------ dónde y qué no tapar

func _add(id: String, at: Vector2, acts: Array, cbs: Dictionary) -> void:
	_specs.append({"id": id, "at": at, "acts": acts})
	for k in cbs:
		_acts[k] = cbs[k]

func _pt(cam: Camera3D, p: Vector3) -> Vector2:
	if cam == null or cam.is_position_behind(p):
		return Vector2(-1000, -1000)
	return cam.unproject_position(p)

## El punto justo encima de la cabeza de alguien (extra: metros de aire sobre lo que se ve de su dibujo).
func _over(a: Node3D, cam: Camera3D, extra := 0.3) -> Vector2:
	var top: float = a.call("top_height") if a.has_method("top_height") else 1.6
	return _pt(cam, a.global_position + Vector3(0.0, top + extra, 0.0))

## Lo que ocupa alguien en pantalla (de los pies a la cabeza, más up metros por encima: su reloj de arena).
func _body(a: Node3D, cam: Camera3D, up := 0.0) -> Rect2:
	var top: float = a.call("top_height") if a.has_method("top_height") else 1.6
	var p0 := _pt(cam, a.global_position)
	var p1 := _pt(cam, a.global_position + Vector3(0.0, top + up, 0.0))
	var h := absf(p0.y - p1.y)
	var w := maxf(40.0, h * 0.5)
	return Rect2(Vector2(p1.x - w * 0.5, p1.y), Vector2(w, h))

## Su cara (la parte de arriba de su dibujo).
func _face(a: Node3D, cam: Camera3D) -> Rect2:
	var r := _body(a, cam)
	return Rect2(r.position, Vector2(r.size.x, r.size.y * 0.42))

func _shelf_point() -> Vector2:
	var r: Rect2 = ui.potion_panel.get_global_rect()
	return Vector2(r.get_center().x, r.position.y - 2.0)

## En la tienda: las caras de ella y de quien está en el mostrador, la fila entera (con sus relojes de arena) y el
## cuervo (con lo que dice).
func _avoid_world(w: ShopWorld, cam: Camera3D) -> void:
	_avoid.append(_face(w.alchemist, cam))
	if is_instance_valid(main.customer):
		_avoid.append(_face(main.customer, cam))
	for v in main.line:
		var a = (v as Dictionary).get("actor")
		if is_instance_valid(a):
			_avoid.append(_body(a, cam, 0.62))
	var k = main.krapido
	if k and is_instance_valid(k.raven) and k.raven.visible and k.raven.state != "away":
		var rp: Vector3 = k.raven.global_position
		var a0 := _pt(cam, rp + Vector3(-0.45, -0.1, 0.0))
		var a1 := _pt(cam, rp + Vector3(0.45, 1.25, 0.0))
		_avoid.append(Rect2(a0, Vector2.ZERO).expand(a1))
	# --- R6 SHIP: lo que ella piensa (main._think: las palabras en cursiva que suben sobre su cabeza, p. ej. «This
	# should work.» al dar una poción) tampoco se tapa con las placas de al lado (la del cliente en el mostrador)
	var th = main.get("_thought")
	if th != null and is_instance_valid(th) and th is Label3D and (th as Label3D).visible:
		var lb: Label3D = th
		var tw := 400.0
		if lb.font != null:
			tw = lb.font.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.font_size).x
		var wm := 0.5 * lb.pixel_size * tw
		var hm := 0.5 * lb.pixel_size * lb.font_size * 1.3
		var c := lb.global_position
		var t0 := _pt(cam, c + Vector3(-wm, -hm, 0.0))
		var t1 := _pt(cam, c + Vector3(wm, hm, 0.0))
		_avoid.append(Rect2(t0, Vector2.ZERO).expand(t1))
	# --- end R6 SHIP

## Los paneles del HUD que estén a la vista.
func _avoid_hud() -> void:
	for c in [ui.hud_panel, ui.menu_box, ui.order_card, ui.tip_panel, main.top_box]:
		if c is Control and (c as Control).is_visible_in_tree():
			_avoid.append((c as Control).get_global_rect())
	if ui.potion_panel.is_visible_in_tree():
		_avoid.append(ui.potion_panel.get_global_rect())
	for t in ui.toast_box.get_children():
		if t is Control and t.visible:
			_avoid.append((t as Control).get_global_rect())
	var eui = main.events_ui
	if eui and eui.root.visible:
		for c in [eui.plate, eui.goal_card, eui.board, eui.line_box, eui.bench_btn]:
			if c is Control and (c as Control).is_visible_in_tree():
				_avoid.append((c as Control).get_global_rect())
