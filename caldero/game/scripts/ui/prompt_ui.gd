extends Control
class_name PromptUI
## --- R6 UI: los avisos de acción («E  Give potion · Space  Talk») sobre la gente y las estaciones. Cada aviso es una
## placa oscura con un hilo de latón (assets/ui/r6_plate9.png) y una colita que señala a quién o a qué; dentro, por
## cada acción, el glifo del botón que la hace (Glyphs: la tecla, el ratón o el botón del mando, según lo último que
## se usó) y una palabra corta. PromptBrain (scripts/ui/prompt_brain.gd) decide cada cuadro qué avisos hay y dónde
## apuntan; aquí se dibujan y se colocan: encima del punto, o corridos a un lado o más arriba si taparían algo de la
## lista «avoid» (las caras, el ticket, la fila, el cuervo, los paneles del HUD). Sin animaciones largas: aparecen y
## se van en una décima de segundo.

const VERB_SIZE := 26
const VERB_COL := Color("f6ead0")
const MARGIN := 14.0            # distancia mínima a los bordes de la pantalla
const GAP := 6.0                # aire alrededor de lo que no se debe tapar

var _plates := {}               # id -> _Plate
static var debug := false       # (--r6dbg) imprime dónde va cada placa y qué la empujó

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	# (dentro del árbol, set_anchors_preset conservaría el rectángulo vacío de antes: anclas y márgenes a la vez)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## specs: [{"id", "at": Vector2 (el punto al que señala la colita: la placa va encima), "acts": [[acción, palabra,
## icono opcional], ...]}]; avoid: [Rect2] en coordenadas de la interfaz.
func update_prompts(specs: Array, avoid: Array) -> void:
	var seen := {}
	for s in specs:
		var id := String(s["id"])
		seen[id] = true
		var p: _Plate = _plates.get(id)
		if p == null or not is_instance_valid(p):
			p = _Plate.new()
			add_child(p)
			_plates[id] = p
			p.appear()
		p.fill(s["acts"])
		_place(p, s.get("at", Vector2.ZERO), avoid)
	for id in _plates.keys():
		if not seen.has(id):
			var p: _Plate = _plates[id]
			_plates.erase(id)
			if is_instance_valid(p):
				p.vanish()

## Lo que hay en pantalla ahora (para las pruebas): [{"id", "rect", "text"}].
func visible_prompts() -> Array:
	var out := []
	for id in _plates:
		var p: _Plate = _plates[id]
		if is_instance_valid(p) and p.visible:
			out.append({"id": id, "rect": p.get_global_rect(), "text": p.sig, "glyphs": p.glyph_names()})
	return out

func clear_all() -> void:
	for id in _plates.keys():
		var p: _Plate = _plates[id]
		if is_instance_valid(p):
			p.queue_free()
	_plates.clear()

## La placa encima del punto; si tapa algo de avoid, prueba corrida a un lado, al otro o más arriba (y se queda con el
## lado que eligió mientras siga libre, para que no salte de un cuadro a otro).
func _place(p: _Plate, at: Vector2, avoid: Array) -> void:
	var sz := p.box_size()
	var area := get_parent_area_size() if size.x < 2.0 else size
	var vw := area.x
	var vh := area.y
	var th := p.tail_h()
	var cands := [
		Vector2(at.x - sz.x * 0.5, at.y - sz.y - th),
		Vector2(at.x - sz.x * 0.2, at.y - sz.y - th),
		Vector2(at.x - sz.x * 0.8, at.y - sz.y - th),
		Vector2(at.x - sz.x * 0.5, at.y - sz.y - th - 44.0),
		Vector2(at.x - sz.x * 0.05, at.y - sz.y - th - 20.0),
		Vector2(at.x - sz.x * 0.95, at.y - sz.y - th - 20.0),
		Vector2(at.x - sz.x * 0.5, at.y - sz.y - th - 96.0),
		Vector2(at.x + 40.0, at.y - sz.y * 0.5),
		Vector2(at.x - 40.0 - sz.x, at.y - sz.y * 0.5),
	]
	var best := -1
	var best_cost := INF
	for i in cands.size():
		var c: Vector2 = cands[i]
		c.x = clampf(c.x, MARGIN, maxf(MARGIN, vw - sz.x - MARGIN))
		c.y = clampf(c.y, MARGIN, maxf(MARGIN, vh - sz.y - MARGIN))
		cands[i] = c
		var r := Rect2(c, sz).grow(GAP)
		var cost := 0.0
		for a in avoid:
			var ar: Rect2 = a
			if r.intersects(ar):
				cost += r.intersection(ar).get_area() + 2000.0
		cost += float(i) * 0.5   # a igualdad, el primero (centrado encima)
		if i == p.side:
			cost -= 0.75         # y el de la vez anterior
		if cost < best_cost:
			best_cost = cost
			best = i
	if debug and Engine.get_process_frames() % 30 == 0:
		var hits := []
		var r0 := Rect2(cands[0], sz).grow(GAP)
		for a in avoid:
			if r0.intersects(a):
				hits.append(a)
		print("R6DBG plate at=", at, " size=", sz, " best=", best, " area=", area, " centered hits=", hits)
	p.side = best
	p.position = (cands[best] as Vector2).round()
	p.point_at(at)

## Una placa: el fondo, la fila de acciones y la colita.
class _Plate extends Control:
	var panel: PanelContainer
	var row: HBoxContainer
	var tail: TextureRect
	var sig := ""
	var side := 0
	var _gen := -1
	var _dying := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel = PanelContainer.new()
		var sb := StyleBoxTexture.new()
		sb.texture = PaperKit.tex("r6_plate9")
		sb.texture_margin_left = 15
		sb.texture_margin_right = 15
		sb.texture_margin_top = 15
		sb.texture_margin_bottom = 15
		sb.content_margin_left = 12
		sb.content_margin_right = 16
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		panel.add_theme_stylebox_override("panel", sb)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		row = UIKit.hbox(10)
		panel.add_child(row)
		tail = PaperKit.pic("r6_plate_tail", 3.0)
		tail.size = tail.custom_minimum_size
		add_child(tail)

	## Rehace la fila si cambiaron las acciones o el dispositivo.
	func fill(acts: Array) -> void:
		var s := str(acts)
		if s == sig and _gen == Glyphs.gen:
			return
		sig = s
		_gen = Glyphs.gen
		for c in row.get_children():
			row.remove_child(c)
			c.queue_free()
		var first := true
		for a in acts:
			var g := Glyphs.make(String(a[0]))
			if g == null and Glyphs.device == "pad":
				continue   # ese botón no existe en el mando (esa acción se hace con el cursor): no se anuncia
			if not first:
				var dot := UIKit.label("·", 26, Color(0.79, 0.63, 0.35), UIKit.font_bold)
				dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(dot)
			first = false
			if g:
				g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(g)
			var l := UIKit.shadow(UIKit.label(String(a[1]), VERB_SIZE, VERB_COL, UIKit.font_bold), 2)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(l)
			if a.size() > 2 and String(a[2]) != "" and ResourceLoader.exists(String(a[2])):
				var ic := UIKit.icon(String(a[2]), 2.0)
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(ic)
		visible = row.get_child_count() > 0 and not _dying
		panel.reset_size()

	func box_size() -> Vector2:
		var s := panel.get_combined_minimum_size()
		panel.size = s
		size = s
		return s

	func tail_h() -> float:
		return tail.size.y - 3.0

	## La colita debajo de la placa, lo más cerca posible del punto (sin salirse de las esquinas).
	func point_at(at: Vector2) -> void:
		var w := panel.size.x
		var tx := clampf(at.x - position.x - tail.size.x * 0.5, 15.0, maxf(15.0, w - 15.0 - tail.size.x))
		tail.position = Vector2(roundf(tx), panel.size.y - 3.0)

	func glyph_names() -> Array:
		var out := []
		for c in row.get_children():
			if c.has_meta("glyph"):
				out.append(String(c.get_meta("glyph")))
		return out

	func appear() -> void:
		modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.12)

	func vanish() -> void:
		_dying = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.1)
		tw.tween_callback(queue_free)
