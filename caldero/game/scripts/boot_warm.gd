extends Node
class_name BootWarm
## --- BOOT: los precalentamientos de la ronda 6 (antes: _warm_places, en negro y ANTES del título, en pocos cuadros
## enormes: en la web ~18 s de negro con cuadros de 1-5 s y la página sin responder) ahora van DESPUÉS de que el título
## responde, repartidos en cuadros y sin que se vea nada:
##  - una SubViewport pequeña que comparte el mundo 3D de la ventana, con su propia cámara que solo ve la capa
##    WARM_LAYER (capa 20; la cámara de la tienda no la ve). Lo que hay que compilar se pone en esa capa unos pocos
##    materiales por cuadro: la biblioteca y el lado de los clientes de la tienda (que la cámara del título no ve), y
##    los efectos que salen a mitad del juego (humo y destellos del caldero, salpicadura, corazones de Miga, confeti de
##    los eventos, el globo de emoción, la puerta abierta). Las mismas luces que en el juego: los mismos shaders.
##  - en el lienzo 2D de esa SubViewport (con el mismo «oversampling» de letras que la ventana): los trazos 2D
##    (PerfWarmup), las letras grandes de los eventos y las del banco (las páginas de letras se suben una vez).
##  - las texturas de los papeles (rank_*, evui_*), una por cuadro.
##  - el mercado: se lleva un momento a OTRA SubViewport con su propio mundo (sus luces no tocan la tienda del título),
##    se muestra por partes y se vuelve a su sitio. Si el jugador va al mercado antes, main.gd lo termina en el negro del
##    viaje (warm_market()).
## main.gd espera a que termine antes de empezar un evento (main._ev_run_day), como la ronda 6 suponía.
## --- BOOT2: el cliente apretó «Continue» con esto todavía en marcha y el juego se pegó: ahora el arranque del juego lo
## hace ENTERO bajo la pantalla de carga, antes del título (main._boot: start(main, p0, p1) y espera a que termine). La
## barra avanza paso a paso y, con una tarjeta rápida, entran más materiales por cuadro (_budget). Después del título ya
## no queda nada pendiente. (Las demos de medición siguen usándolo como antes: start(main) sin pantalla de carga.)

signal finished
signal market_finished

const WARM_LAYER := 1 << 19
const VP_SIZE := Vector2i(480, 270)

var main: Node
var done := false
var loading := false   # --- BOOT2: bajo la pantalla de carga (la barra va de _p0 a _p1)
var _p0 := 0.0
var _p1 := 1.0
var _budget := 1       # --- BOOT2: firmas de material nuevas por cuadro (bajo la pantalla de carga sube hasta 4 si los cuadros son cortos)
var market_done := false
var _market_busy := false
var _vp: SubViewport
var _cam: Camera3D
var _canvas: Control

static func start(m: Node, p0 := -1.0, p1 := -1.0) -> BootWarm:
	var w := BootWarm.new()
	w.name = "BootWarm"
	w.main = m
	# --- BOOT2: con p0/p1, bajo la pantalla de carga: sin esperar al título y moviendo la barra de p0 a p1
	if p0 >= 0.0:
		w.loading = true
		w._p0 = p0
		w._p1 = p1
	# --- end BOOT2
	m.get_tree().root.add_child(w)
	w._run()
	return w

func _run() -> void:
	if not loading:   # --- BOOT2
		await get_tree().create_timer(1.3).timeout   # el título termina de aparecer
	_bm("warm:start")
	_make_viewport()
	await _step_2d()
	_bm("warm:2d")
	_prog(0.05)
	await _step_shop_views()
	_bm("warm:shop_views")
	_prog(0.40)
	await _step_shop_hidden()
	_bm("warm:shop_hidden")
	_prog(0.52)
	await _step_shop_effects()
	_bm("warm:shop_effects")
	_prog(0.62)
	await _step_text()
	_bm("warm:text")
	_prog(0.71)
	await _step_ui_art()
	_bm("warm:ui_art")
	_prog(0.75)
	await warm_market()
	_bm("warm:market")
	_prog(1.0)
	_vp.queue_free()
	done = true
	_bm("warm:done")
	finished.emit()

## --- BOOT2: la barra de la pantalla de carga (f = cuánto va del precalentamiento, 0..1; los pesos de cada paso salen
## de lo que tardaban en la web)
func _prog(f: float) -> void:
	if loading:
		BootScreen.progress(lerpf(_p0, _p1, f))

static func _bm(step: String) -> void:
	if PerfLog.on:
		PerfLog.mark("boot:%s ticks=%d" % [step, Time.get_ticks_msec()])

func _frame() -> void:
	await get_tree().process_frame

## Espera a que la tienda se vea (en el mercado o en un evento la tienda está escondida: no se puede dibujar).
func _shop_ready() -> void:
	while not (is_instance_valid(main.world) and main.world.is_visible_in_tree()):
		await _frame()

func _make_viewport() -> void:
	_vp = SubViewport.new()
	_vp.name = "WarmView"
	_vp.size = VP_SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# las letras se guardan por tamaño Y por «oversampling» (la escala de la ventana): el mismo que la ventana, para
	# que lo que se dibuja aquí sirva allá
	_vp.oversampling_override = get_viewport().get_oversampling()
	add_child(_vp)   # sin mundo propio: comparte el World3D de la ventana (la tienda, sus luces, su entorno)
	_cam = Camera3D.new()
	_cam.cull_mask = WARM_LAYER
	_vp.add_child(_cam)
	_cam.current = true
	_canvas = Control.new()
	_canvas.size = Vector2(VP_SIZE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(_canvas)
	main.world.camera.cull_mask &= ~WARM_LAYER

## La cámara de precalentar en el sitio de la cámara de la tienda cuando sigue a la alquimista hasta x.
func _shop_cam(x: float) -> void:
	var w: ShopWorld = main.world
	_cam.fov = w.camera.fov
	_cam.near = w.camera.near
	_cam.far = w.camera.far
	_cam.attributes = w.camera.attributes
	var base: Vector3 = w._cam_base
	var target: Vector3 = w._cam_target
	_cam.global_position = Vector3(x, base.y, base.z)
	_cam.look_at(Vector3(x, target.y, target.z), Vector3.UP)

## Dibuja n cuadros de la SubViewport.
func _render(n := 1) -> void:
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in n:
		var t := Time.get_ticks_usec()
		await _frame()
		_adapt(Time.get_ticks_usec() - t)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

## --- BOOT2: como _boot_reveal_world: bajo la pantalla de carga, si el cuadro fue corto (tarjeta rápida) entran más
## materiales nuevos en el siguiente; si no, uno. Después del título siempre uno (cuadros cortos mientras se juega).
func _adapt(usec: int) -> void:
	if loading:
		_budget = mini(_budget + 1, 4) if usec < 50000 else 1

## Pone (o quita) la capa de precalentar en todo lo visible de n. only: SOLO esa capa (lo que no debe verse en la
## cámara del juego: copias y cosas de prueba); si no, se suma a la que ya tiene. Las copias tampoco dan sombra: las
## sombras se calculan por luz, no por cámara, y una copia la dejaría ver en la tienda del título (las partículas sí la
## dan: el humo del caldero, dos cuadros dentro del caldero).
static func _set_warm(n: Node, on: bool, only := false) -> void:
	if n is VisualInstance3D and not n is Light3D:
		var v := n as VisualInstance3D
		if only:
			v.layers = WARM_LAYER
			if n is GeometryInstance3D and not n is GPUParticles3D:
				if not n.has_meta("warm_cs"):
					n.set_meta("warm_cs", (n as GeometryInstance3D).cast_shadow)
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif on:
			v.layers |= WARM_LAYER
		else:
			v.layers &= ~WARM_LAYER
	for c in n.get_children():
		_set_warm(c, on, only)

# ------------------------------------------------------------------ 2D

func _step_2d() -> void:
	PerfWarmup.run(_canvas)   # cada clase de trazo 2D (el mapa del viaje, el grimorio, los papeles); se borra sola
	await _render(4)

# ------------------------------------------------------------------ la tienda: lo que la cámara del título no ve

## Los nodos 3D de la tienda en grupos con pocos materiales nuevos por cuadro, vistos desde los dos extremos del carril
## de la cámara (la biblioteca y el lado de la puerta).
func _step_shop_views() -> void:
	for xi in 2:
		var x: float = [ShopWorld.CAM_X0, ShopWorld.CAM_X1][xi]
		await _shop_ready()
		_shop_cam(x)
		# lo que la cámara del juego ya ve (el título) ya está compilado: solo lo de fuera de su vista
		var cam: Camera3D = main.world.camera
		var items := BootWarm.items_of(main.world).filter(func(it): return not _seen_by(cam, it[0]))
		var seen := {}
		var total := maxf(1.0, items.size())
		while not items.is_empty():
			await _shop_ready()
			_prog(lerpf(0.05, 0.40, (xi + 1.0 - items.size() / total) / 2.0))   # --- BOOT2
			var group := BootWarm.take_group(items, seen, _budget, 32 * _budget)
			for n in group:
				if is_instance_valid(n):
					_set_warm(n, true)
			await _render(1)
			for n in group:
				if is_instance_valid(n):
					_set_warm(n, false)

## A lo que la cámara del juego no ve (la biblioteca, la ventanilla del cuervo) le devuelve su sombra: ahí no se nota y
## su variante de sombra también queda compilada.
func _shadow_back_if_unseen(n: Node) -> void:
	if n is GeometryInstance3D and n.has_meta("warm_cs") and not _seen_by(main.world.camera, n):
		(n as GeometryInstance3D).cast_shadow = n.get_meta("warm_cs")
	for c in n.get_children():
		_shadow_back_if_unseen(c)

## Lo que en el título está escondido y sale más tarde (las mejoras compradas: la alfombra, el cojín, el caldero de
## cobre...; los trofeos; las pociones del estante; Graznido): una copia de cada cosa, sin luces, sonidos ni clics, en su
## mismo sitio y solo en la capa de precalentar. Si no, al continuar una partida con mejoras la mañana enlazaba sus
## programas a la vista (8 de golpe en la web con la alfombra y el cojín).
func _step_shop_hidden() -> void:
	await _shop_ready()
	var w: ShopWorld = main.world
	var roots: Array = []
	_hidden_roots(w, roots)
	var copies: Array = []
	for r in roots:
		var c := (r as Node3D).duplicate(0) as Node3D
		_strip(c)
		c.visible = true
		(r.get_parent() as Node).add_child(c)
		c.transform = (r as Node3D).transform
		BootWarm.hide_layers(c, {})
		copies.append(c)
	var items: Array = []
	for c in copies:
		var k := {}
		BootWarm.keys_of(c, k)
		if not k.is_empty():
			items.append([c, k.keys()])
	var seen := {}
	while not items.is_empty():
		await _shop_ready()
		var group := BootWarm.take_group(items, seen, _budget, 16 * _budget)
		var x := 0.0
		for n in group:
			_set_warm(n, true, true)
			_shadow_back_if_unseen(n)
			x += BootWarm._box_of(n).get_center().x
		_shop_cam(clampf(x / maxf(1.0, group.size()), ShopWorld.CAM_X0, ShopWorld.CAM_X1))
		await _render(1)
		for n in group:
			BootWarm.hide_layers(n, {})
	for c in copies:
		c.queue_free()

## Las raíces de lo escondido (visible = false) que tienen algo que dibujar.
static func _hidden_roots(n: Node, out: Array) -> void:
	for c in n.get_children():
		if not (c is Node3D) or c is Light3D or c is Camera3D:
			continue
		if not (c as Node3D).visible:
			if _draws(c):
				out.append(c)
			continue
		_hidden_roots(c, out)

static func _draws(n: Node) -> bool:
	if n is VisualInstance3D and not n is Light3D:
		return true
	for c in n.get_children():
		if _draws(c):
			return true
	return false

## Quita de una copia lo que no es dibujo: luces (alumbrarían la tienda del título), sonidos, cámaras y lo que se toca.
static func _strip(n: Node) -> void:
	for c in n.get_children():
		if c is Light3D or c is Camera3D or c is CollisionObject3D or c is AudioStreamPlayer3D or c is AudioStreamPlayer:
			n.remove_child(c)
			c.free()
		else:
			_strip(c)

## Si alguna esquina de lo que se dibuja de n está dentro de lo que ve cam.
static func _seen_by(cam: Camera3D, n: Node) -> bool:
	if not (n is Node3D) or not is_instance_valid(cam):
		return false
	var b := _box_of(n as Node3D)
	for i in 8:
		if cam.is_position_in_frustum(b.get_endpoint(i)):
			return true
	return false

## Los hijos 3D de root que tienen algo que dibujar, con sus firmas: [[nodo, [firmas]], ...]. Una firma es el material
## (EventScenes._keys_of) más qué clase de luces lo tocan (omni / foco, con o sin sombras): en Compatibility cada
## combinación es otro programa (la pasada base sin o con luces de cada tipo y una pasada aditiva por cada luz con
## sombras), así que un mismo material bajo otras luces también cuesta.
static func items_of(root: Node) -> Array:
	var lights: Array = []   # [posición, alcance, clase]
	_lights_in(root, lights)
	var out: Array = []
	for c in root.get_children():
		if not (c is Node3D) or c is Light3D or c is Camera3D:
			continue
		var k := {}
		BootWarm.keys_of(c, k)
		if k.is_empty():
			continue
		var box := _box_of(c as Node3D)
		var lit := [0, 0, 0, 0]   # omni, foco, omni con sombras, foco con sombras
		if box.has_volume() or box.size != Vector3.ZERO:
			for l in lights:
				var p: Vector3 = l[0]
				var q := p.clamp(box.position, box.end)
				if p.distance_to(q) < float(l[1]):
					lit[int(l[2])] = 1
		var sig := "|L%d%d%d%d" % lit
		var keys: Array = []
		for x in k:
			keys.append(String(x) + sig)
		out.append([c, keys])
	return out

## Las firmas de shader de lo visible dentro de n (como EventScenes._keys_of, la de la ronda 6, pero el material por TODAS
## sus opciones que cambian el shader: un StandardMaterial3D genera un shader distinto por cada combinación de banderas,
## modos y texturas presentes, p. ej. triplanar en el mundo o en el objeto; los números y colores no cuentan).
static func keys_of(n: Node, out: Dictionary) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		var sh := "s%d" % int(g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if g.material_override:
			out[sh + mat_key(g.material_override)] = true
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				out[sh + mat_key(mi.get_active_material(i))] = true
		elif n is SpriteBase3D or n is Label3D:
			var parts := PackedStringArray()
			for prop in SPRITE_FLAGS:
				parts.append(str(n.get(prop)))
			out[sh + n.get_class() + "".join(parts)] = true
		elif n is GPUParticles3D:
			var gp := n as GPUParticles3D
			var dk := ""
			if gp.draw_pass_1 and gp.draw_pass_1.get_surface_count() > 0:
				dk = mat_key(gp.draw_pass_1.surface_get_material(0))
			out["gp" + mat_key(gp.process_material) + dk] = true
		else:
			out[sh + n.get_class()] = true
	for c in n.get_children():
		keys_of(c, out)

const SPRITE_FLAGS := ["shaded", "double_sided", "transparent", "alpha_cut", "billboard", "no_depth_test", "fixed_size",
	"texture_filter"]   # (Label3D no tiene «transparent»: get() da null)
static var _mat_keys := {}   # instance_id -> firma (los materiales no cambian de banderas después de armarse)

static func mat_key(m: Material) -> String:
	if m == null:
		return "nil"
	if m is ShaderMaterial:
		var shd := (m as ShaderMaterial).shader
		return "sh%d" % (shd.get_instance_id() if shd else 0)
	var id := m.get_instance_id()
	if not _mat_keys.has(id):
		var k := m.get_class() + _flags_key(m)
		if m is BaseMaterial3D and (m as BaseMaterial3D).next_pass:
			k += "+" + mat_key((m as BaseMaterial3D).next_pass)
		_mat_keys[id] = k
	return _mat_keys[id]

## Las propiedades guardadas de o que eligen variantes del shader: booleanas, enteras (modos) y si hay o no textura.
static func _flags_key(o: Object) -> String:
	var parts := PackedStringArray()
	for p in o.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var t := int(p["type"])
		if t == TYPE_BOOL or t == TYPE_INT:
			parts.append(str(o.get(p["name"])))
		elif t == TYPE_OBJECT and String(p["name"]) != "script" and String(p["name"]) != "next_pass":
			parts.append("1" if o.get(p["name"]) != null else "0")
	return "".join(parts)

static func _lights_in(n: Node, out: Array) -> void:
	if n is OmniLight3D or n is SpotLight3D:
		var l := n as Light3D
		if l.is_visible_in_tree() or l.visible:
			var spot := n is SpotLight3D
			var rng: float = (n as SpotLight3D).spot_range if spot else (n as OmniLight3D).omni_range
			out.append([l.global_position, rng, int(spot) + 2 * int(l.shadow_enabled)])
	for c in n.get_children():
		_lights_in(c, out)

## La caja (en coordenadas del mundo) de lo visible dentro de n.
static func _box_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is Node3D and not (x as Node3D).visible:
			continue
		if x is VisualInstance3D and not x is Light3D:
			var vi := x as VisualInstance3D
			var b := vi.global_transform * vi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(x.get_children())
	return box

## Saca de items los que se dibujan este cuadro: hasta `budget` firmas nuevas (al menos un nodo con firmas nuevas) y,
## de los que solo traen firmas ya vistas, hasta `free_max` nodos. Devuelve sus nodos.
static func take_group(items: Array, seen: Dictionary, budget: int, free_max := 12) -> Array:
	var group: Array = []
	var later: Array = []
	var fresh := 0
	var free := 0
	for it in items:
		var nk: Array = (it[1] as Array).filter(func(x): return not seen.has(x))
		var wgt := 0
		for x in nk:
			wgt += 1 + int(String(x).contains("sh")) + int(String(x).begins_with("gp"))
		var take := false
		if nk.is_empty():
			take = free < free_max
			free += int(take)
		else:
			take = fresh == 0 or fresh + wgt <= budget
		if take:
			group.append(it[0])
			for x in nk:
				seen[x] = true
			fresh += wgt
		else:
			later.append(it)
	items.assign(later)
	return group

# ------------------------------------------------------------------ los efectos de la tienda (ronda 6: _warm_shop_effects)

func _step_shop_effects() -> void:
	await _shop_ready()
	var w: ShopWorld = main.world
	# alguien (con su globo de emoción) por donde camina ella, con las luces de cada sitio: la biblioteca, la ventanilla
	# del cuervo y la puerta (su sprite bajo otras luces = otras variantes; antes salían al llevarla allí)
	for x in [float(ShopWorld.STATIONS["biblioteca"]["x"]), ShopWorld.KRAPIDO_STATION["x"], float(ShopWorld.STATIONS["puerta"]["x"])]:
		await _shop_ready()
		var walker := Actor.new()
		w.add_child(walker)
		walker.setup(Story.sprite_id("pip"), 0.04)
		walker.position = w.walker.point(x)
		walker.emote("note", 0.0)
		_set_warm(walker, true, true)
		_shadow_back_if_unseen(walker)
		_shop_cam(clampf(x, ShopWorld.CAM_X0, ShopWorld.CAM_X1))
		await _render(2)
		walker.queue_free()
	# la puerta abierta (abierta entra en la luz con sombras del mostrador: otra variante de su material) y un globo de
	# emoción sobre alguien frente al mostrador: copias que solo ve la cámara de precalentar
	_shop_cam(ShopWorld.CAM_X1)
	var door := w.door_pivot.duplicate(0) as Node3D
	door.rotation.y = deg_to_rad(-105.0)
	w.add_child(door)
	_set_warm(door, true, true)
	var guest := Actor.new()
	w.add_child(guest)
	guest.setup(Story.sprite_id("pip"), 0.04)
	guest.position = ShopWorld.P_CUSTOMER
	guest.emote("heart", 0.0)
	_set_warm(guest, true, true)
	await _render(2)
	door.queue_free()
	guest.queue_free()
	await _shop_ready()
	# junto al caldero: el humo y los destellos al embotellar, la salpicadura, los destellos de subir de nivel, los
	# corazones de Miga, el globo de emoción con esas luces, y el confeti de los eventos (el shader de partículas más
	# grande del juego). Sus shaders quedan vivos toda la partida (PerfWarmup.keep_particles: si no, se liberan y se
	# vuelven a compilar cada vez).
	var cau: Cauldron = w.cauldron
	_shop_cam(ShopWorld.CAULDRON_POS.x + 1.0)
	var had := {}
	for n in [w, cau]:
		for c in n.get_children():
			had[c.get_instance_id()] = true
	var cook := Actor.new()
	w.add_child(cook)
	cook.setup(Story.sprite_id("pip"), 0.04)
	cook.position = ShopWorld.P_ALCH_CAULDRON
	cook.emote("heart", 0.0)
	cau.brew_burst(Color(0.6, 0.9, 0.5))
	cau.splash(Color(0.6, 0.9, 0.5))
	cau._flash = 0.0   # (sin el destello de luz del caldero: el título lo vería)
	var at := cau.global_position + Vector3(0.6, 1.2, 0.4)
	w.spawn_sparkles(at, Color(1.6, 1.5, 1.0), 8)
	w.spawn_hearts(at + Vector3(0.5, 0.0, 0.0))
	var evc := EventScenes.new()
	w.add_child(evc)
	evc.position = at - Vector3(2.0, 2.6, 0.2)   # (_confetti sale 2 / 2,6 / 0,2 por encima de su «Player»)
	var conf := evc._confetti()
	for n in [w, cau]:
		for c in n.get_children():
			if not had.has(c.get_instance_id()):
				_set_warm(c, true, true)
	PerfWarmup.keep_particles(conf)
	await _render(2)
	evc.queue_free()
	cook.queue_free()
	for n in [w, cau]:
		for c in n.get_children():
			if c is GPUParticles3D and not had.has(c.get_instance_id()):
				PerfWarmup.keep_particles(c as GPUParticles3D)
				(c as GPUParticles3D).emitting = false
				(c as GPUParticles3D).visible = false

# ------------------------------------------------------------------ letras (ronda 6: _warm_event_text)

## Las letras grandes de los eventos («3 2 1 Go!», «Time!», los «+3 ★») y las del banco (font_sc_bold 34 px con
## contorno 10): cada letra nueva se dibuja en la caché de la fuente y su página se sube a la GPU; aquí una vez, un
## texto por cuadro, en el lienzo de la SubViewport.
func _step_text() -> void:
	var eui = main.events_ui
	var labels: Array = []
	if is_instance_valid(eui) and eui.has_method("_outlined"):
		labels.append(eui.call("_outlined", "3 2 1 Go! Time! Done!", 120, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
		labels.append(eui.call("_outlined", "+0123456789 ★ time", 40, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold))
	var bench := UIKit.label("ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 !?.,'’+-%:()",
		34, UIKit.GOLD_BRIGHT, UIKit.font_sc_bold)
	bench.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.12))
	bench.add_theme_constant_override("outline_size", 10)
	labels.append(bench)
	for l in labels:
		var c := l as Control
		c.scale = Vector2(0.25, 0.25)   # que quepa en la SubViewport (la caché va por tamaño de letra, no por escala)
		_canvas.add_child(c)
		await _render(2)
		c.queue_free()

# ------------------------------------------------------------------ texturas de los papeles (ronda 6: _preload_ui_art)

func _step_ui_art() -> void:
	var t := Time.get_ticks_usec()
	for f in ResourceLoader.list_directory("res://assets/ui"):
		var n := String(f)
		if n.ends_with(".png") and (n.begins_with("rank_") or n.begins_with("evui_")):
			PaperKit.tex("res://assets/ui/" + n)
			if Time.get_ticks_usec() - t > 8000:
				await _frame()
				t = Time.get_ticks_usec()

# ------------------------------------------------------------------ el mercado (ronda 6: el mercado en _warm_places)

## Precalienta el mercado (una vez). Lo llama _run() y, si el jugador va antes, main._go_market en el negro del viaje.
func warm_market() -> void:
	if market_done:
		return
	if _market_busy:
		await market_finished
		return
	_market_busy = true
	var m: MarketWorld = main.market
	var parent := m.get_parent()
	var idx := m.get_index()
	var vp := SubViewport.new()
	vp.name = "WarmMarket"
	vp.own_world_3d = true   # su propio mundo: las luces del mercado no tocan la tienda (ni las de la tienda al mercado)
	vp.size = VP_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	parent.remove_child(m)
	vp.add_child(m)
	m.process_mode = Node.PROCESS_MODE_INHERIT
	m.enter(false)
	# lo que se dibuja, escondido (capa 0) y después mostrado por partes: pocos materiales nuevos por cuadro
	var hidden := {}
	BootWarm.hide_layers(m, hidden)
	m.visible = true
	var items := BootWarm.items_of(m)
	var seen := {}
	var total := maxf(1.0, items.size())
	while not items.is_empty():
		_prog(lerpf(0.75, 0.95, 1.0 - items.size() / total))   # --- BOOT2
		var group := BootWarm.take_group(items, seen, _budget, 32 * _budget)
		for n in group:
			BootWarm.restore_layers(n, hidden)
		var t := Time.get_ticks_usec()
		await _frame()
		_adapt(Time.get_ticks_usec() - t)
	BootWarm.restore_layers(m, hidden)
	# el saludo de los vendedores (globo de emoción) con las luces del mercado, en los tres sitios donde para la cámara
	for v in m.vendors:
		(m.vendors[v] as Actor).emote("heart", 0.0)
	m.alchemist.emote("note", 0.0)
	for x in [MarketWorld.SHOP_DOOR_X, MarketWorld.X0, MarketWorld.FOUNTAIN_POS.x, MarketWorld.X1]:
		m.walker.teleport(x, 1)
		m.snap_camera()
		await _frame()
		await _frame()
	for v in m.vendors:
		(m.vendors[v] as Actor).clear_emote()
	m.alchemist.clear_emote()
	m.leave()
	m.visible = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.camera.current = false
	vp.remove_child(m)
	parent.add_child(m)
	parent.move_child(m, idx)
	vp.queue_free()
	market_done = true
	_market_busy = false
	market_finished.emit()

## Esconde (capa 0) todo lo que se dibuja dentro de n y guarda sus capas en hidden (instance_id -> capas).
static func hide_layers(n: Node, hidden: Dictionary) -> void:
	if n is VisualInstance3D and not n is Light3D:
		hidden[n.get_instance_id()] = (n as VisualInstance3D).layers
		(n as VisualInstance3D).layers = 0
	for c in n.get_children():
		hide_layers(c, hidden)

static func restore_layers(n: Node, hidden: Dictionary) -> void:
	if not is_instance_valid(n):
		return
	var id := n.get_instance_id()
	if hidden.has(id):
		(n as VisualInstance3D).layers = hidden[id]
		hidden.erase(id)
	for c in n.get_children():
		restore_layers(c, hidden)

## Espera a que termine (como mucho max_s segundos; si no, sigue igual: lo que falte se compila al verse).
func wait_done(max_s := 20.0) -> void:
	var t := Time.get_ticks_msec()
	while not done and Time.get_ticks_msec() - t < int(max_s * 1000.0):
		await _frame()
