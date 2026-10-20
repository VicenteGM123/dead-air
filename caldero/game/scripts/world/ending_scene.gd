extends Node
class_name EndingScene
## --- R4 RANK: el final del puesto 1 del Escalafón. Esa noche, en la tienda: guirnaldas y farolillos, Pip entra con el
## caldero de oro del Gremio, llega el pueblo a celebrar (y Fizz, a regañadientes), Miga salta al mostrador, confeti y
## unas pocas líneas; luego los créditos con el elenco y «Seguir jugando» (main.gd sigue con la mañana siguiente).
## Se juega una vez (Ranking.ending_seen). Después, el caldero de oro queda en el mostrador (place_trophy).
## main.gd lo crea en _sleep(): var e := EndingScene.new(); add_child(e); await e.play(self). auto = true (demos, bot):
## las líneas y los créditos avanzan solos.

const TROPHY_POS := Vector3(ShopWorld.COUNTER_X, ShopWorld.COUNTER_TOP, -2.05)   # sobre el mostrador, detrás de donde se atiende
const TROPHY_PX := 0.0145
## Quién viene a celebrar (sprite id) y dónde se para (del lado de los clientes, de cara a ella).
const CROWD := [
	["panadera", Vector3(2.35, 0, -0.85)], ["bram", Vector3(3.15, 0, -0.7)], ["fizz", Vector3(3.95, 0, -0.8)],
	["granjero", Vector3(4.75, 0, -0.75)], ["anciano", Vector3(1.95, 0, -2.15)], ["lirien", Vector3(2.75, 0, -2.25)],
	["mabel", Vector3(3.55, 0, -2.2)], ["nyra", Vector3(4.35, 0, -2.25)], ["borin", Vector3(5.15, 0, -2.15)],
	["tobias", Vector3(5.95, 0, -2.25)],
]
const PIP_SPOT := Vector3(1.5, 0, -0.65)

var auto := false
var main
var world: ShopWorld
var ui: GameUI
var _added: Array = []        # nodos que se agregan a la tienda (se borran al terminar)
var _actors := {}             # sprite id -> Actor
var _trophy: Sprite3D
var _cat_pos := Vector3.ZERO
var _walking := 0             # cuántos del pueblo siguen entrando (un contador de la escena: las lambdas copian las variables locales)
var _cam_base := Vector3.ZERO
var _cam_target := Vector3.ZERO

## El caldero de oro en el mostrador de la tienda (desde que se jugó el final). Lo llama main.gd cada mañana.
static func place_trophy(w: ShopWorld) -> void:
	var old := w.get_node_or_null("RankTrophy")
	if not Ranking.ending_seen:
		if old:
			old.queue_free()
		return
	if old:
		return
	var s := _trophy_sprite()
	s.name = "RankTrophy"
	s.position = TROPHY_POS
	w.add_child(s)

static func _trophy_sprite() -> Sprite3D:
	var s := Sprite3D.new()
	var t: Texture2D = load("res://assets/ui/rank_trophy.png")
	s.texture = t
	s.pixel_size = TROPHY_PX
	s.centered = false
	s.offset = Vector2(-t.get_width() / 2.0, 0)
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s

## La escena entera. Empieza con la pantalla en negro (main._sleep ya fundió) y termina en negro.
func play(m) -> void:
	main = m
	world = m.world
	ui = m.ui
	_setup()
	await m._fade_to(0.0, 1.0)
	Sfx.play("doorbell", 0.02, -4.0)
	# 1) Pip entra corriendo con el caldero de oro del Gremio
	var pip := _spawn("pip", ShopWorld.P_OUTSIDE)
	_trophy = _trophy_sprite()
	_trophy.pixel_size = TROPHY_PX * 0.85
	_trophy.position = Vector3(0, 0.62, 0.12)
	pip.add_child(_trophy)
	world.open_door()
	await pip.walk_to(ShopWorld.P_DOOR_IN, 2.6)
	await pip.walk_to(ShopWorld.P_DOOR_FRONT, 2.6)
	await pip.walk_to(Vector3(ShopWorld.P_CUSTOMER.x, 0, -1.75), 2.6)
	pip.face(-1)
	pip.hop(2)
	await _line(Story.char_name("pip"), "¡Correo urgente del Gremio! ¡Y pesa una barbaridad!")
	await _place_trophy_from(pip)
	await _line("", "[color=#ffd987]El Gremio de Boticarios de Arvendal:[/color] «Caldero Nocturno, primera del Escalafón».")
	# 2) llega el pueblo a celebrar
	pip.walk_to(PIP_SPOT, 1.8)
	_walking = 0
	for i in CROWD.size():
		var id: String = CROWD[i][0]
		var a := _spawn(id, ShopWorld.P_OUTSIDE)
		_walking += 1
		_walk_in(a, CROWD[i][1])
		await get_tree().create_timer(0.45).timeout
	var waited := 0.0
	while _walking > 0 and waited < 9.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	world.close_door()
	_cheer(["panadera"], "heart")
	await _line(Story.char_name("panadera"), "¡Lo sabía! ¡La mejor tienda de Arvendal es la nuestra!")
	_cheer(["bram"], "excl")
	await _line(Story.char_name("bram"), "¡Ja! ¡Que se entere toda la Montaña Gris!")
	_cheer(["fizz"], "sweat")
	await _line(Story.char_name("fizz"), "Felicidades. Lo digo sin desdén… casi. El año que viene, el caldero es mío.")
	# 3) la fiesta: confeti, todos saltan, Miga sube al mostrador
	_confetti()
	Sfx.play("levelup", 0.0, -2.0)
	Sfx.play("sparkle", 0.02, -3.0)
	var k := 0
	for id in _actors:
		var a2: Actor = _actors[id]
		a2.hop(3, 0.22)
		if k % 2 == 0:   # (la mitad: diez emociones a la vez tapan las caras)
			a2.emote(["heart", "note", "star"][(k / 2) % 3], 2.2)
		k += 1
	world.alchemist.hop(2, 0.22)
	_miga_party()
	world.spawn_sparkles(TROPHY_POS + Vector3(0, 0.45, 0.1), Color(1.8, 1.5, 0.8), 30)
	await get_tree().create_timer(1.2).timeout
	await _line("", "[i]Gracias, Valdelago. Gracias, Miga.[/i]")
	await get_tree().create_timer(1.0).timeout
	ui.hide_dialog()
	# 4) los créditos (el elenco) y «Seguir jugando»
	main.ov.show_credits()
	if auto:
		get_tree().create_timer(3.5).timeout.connect(func():
			if main.ov.current == "credits":
				main.ov.close())
	while main.ov.current == "credits":
		await get_tree().process_frame
	await m._fade_to(1.0, 0.7)
	_cleanup()

## Todo listo con la pantalla en negro: noche, guirnaldas, farolillos, la cámara mirando el mostrador y la sala.
func _setup() -> void:
	ui.set_gameplay_visible(false)
	ui.hide_dialog()
	ui.hide_tip()
	world.set_time(1.0, false)
	world.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1)
	world.alchemist.face(1)
	_cam_base = world._cam_base
	_cam_target = world._cam_target
	world._cam_base = Vector3(0.0, 3.3, 7.9)
	world._cam_target = Vector3(0.0, 1.25, -2.0)
	world.cam_fixed_x = 2.55
	world.snap_camera()
	world.block_hover(true)
	_cat_pos = world.cat.position
	# guirnaldas de banderines bajo la viga del fondo
	for b in [["bunting_a", -0.4], ["bunting_b", 4.0]]:
		_sprite("res://assets/props/%s.png" % b[0], 0.035, Vector3(b[1], 4.42, -3.86), "top")
	# farolillos de papel rojo con luz cálida
	for x in [-2.0, 0.2, 2.92, 5.5]:
		var l := _sprite("res://assets/ui/rank_lantern.png", 0.042, Vector3(x, 3.75, -3.6), "top", false)
		l.modulate = Color(1.5, 1.3, 1.1)
		var o := OmniLight3D.new()
		o.position = Vector3(x, 2.75, -3.2)
		o.light_color = Color(1.0, 0.58, 0.36)
		o.light_energy = 1.1
		o.omni_range = 3.8
		o.omni_attenuation = 1.3
		o.shadow_enabled = false
		world.add_child(o)
		_added.append(o)
	# luz cálida de frente para la gente del pueblo (la fila de delante queda lejos de los farolillos)
	var f := OmniLight3D.new()
	f.position = Vector3(3.2, 2.4, 1.2)
	f.light_color = Color(1.0, 0.78, 0.55)
	f.light_energy = 0.9
	f.omni_range = 6.5
	f.omni_attenuation = 1.2
	world.add_child(f)
	_added.append(f)
	# una luz dorada sobre el mostrador (el caldero de oro brilla)
	var g := OmniLight3D.new()
	g.position = TROPHY_POS + Vector3(0.2, 1.3, 1.0)
	g.light_color = Color(1.0, 0.85, 0.55)
	g.light_energy = 0.9
	g.omni_range = 4.0
	world.add_child(g)
	_added.append(g)

func _sprite(path: String, px: float, pos: Vector3, anchor := "bottom", shaded := true) -> Sprite3D:
	var s := Sprite3D.new()
	var t: Texture2D = load(path)
	s.texture = t
	s.pixel_size = px
	s.centered = false
	s.offset = Vector2(-t.get_width() / 2.0, -t.get_height() if anchor == "top" else 0.0)
	s.position = pos
	s.shaded = shaded
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(s)
	_added.append(s)
	return s

func _spawn(id: String, pos: Vector3) -> Actor:
	var a := Actor.new()
	world.add_child(a)
	a.setup(Story.sprite_id(id), 0.04)
	a.global_position = pos
	a.quiet = true
	_actors[id] = a
	return a

func _walk_in(a: Actor, spot: Vector3) -> void:
	await a.walk_to(ShopWorld.P_DOOR_IN, 2.4)
	await a.walk_to(ShopWorld.P_DOOR_FRONT, 2.4)
	await a.walk_to(spot, 2.2)
	if is_instance_valid(a):
		a.face(-1)
	_walking -= 1

## Una línea de diálogo: espera a que el jugador avance (Espacio, clic o A); en auto, avanza sola.
func _line(who: String, text: String) -> void:
	ui.say(who, text)
	if auto:
		await get_tree().create_timer(1.7).timeout
		ui._advance()
		ui._advance()
		return
	await ui.dialog_advanced

func _cheer(ids: Array, emote: String) -> void:
	for id in ids:
		if _actors.has(id):
			var a: Actor = _actors[id]
			a.hop(1)
			a.emote(emote, 1.8)

## Pip deja el caldero de oro sobre el mostrador (vuela de sus manos al mostrador) y brilla.
func _place_trophy_from(pip: Actor) -> void:
	var from := _trophy.global_position
	pip.remove_child(_trophy)
	world.add_child(_trophy)
	_added.append(_trophy)
	_trophy.global_position = from
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := from.lerp(TROPHY_POS, t)
		p.y += sin(t * PI) * 0.6
		_trophy.global_position = p
		_trophy.pixel_size = lerpf(TROPHY_PX * 0.85, TROPHY_PX, t), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	await tw.finished
	Sfx.play("plop", 0.05, -2.0)
	Sfx.play("sparkle", 0.0, -3.0)
	world.spawn_sparkles(TROPHY_POS + Vector3(0, 0.4, 0.1), Color(1.8, 1.5, 0.8), 24)
	world.alchemist.hop(1)
	world.alchemist.emote("sparkle", 2.0)

## Miga sube de un salto al mostrador, junto al caldero, ronronea y suelta corazones.
func _miga_party() -> void:
	var cat: AnimatedSprite3D = world.cat
	var to := Vector3(ShopWorld.COUNTER_X - 0.05, ShopWorld.COUNTER_TOP, -1.3)
	var from := cat.position
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := from.lerp(to, t)
		p.y += sin(t * PI) * 0.9
		cat.position = p, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	await tw.finished
	cat.play("happy")
	Sfx.play("purr", 0.05, -2.0)
	world.spawn_hearts(to + Vector3(0, 0.7, 0.1))

## Confeti de colores que cae sobre la sala.
func _confetti() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 5.0
	p.explosiveness = 0.15
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.6, 0.15, 1.3)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, -0.7, 0)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -260.0
	pm.angular_velocity_max = 260.0
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color("e0503a"), Color("ffd84d"), Color("7ee08a"), Color("7fd4ff"), Color("d77aa0"), Color("fff6e0")])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ui/rank_confetti.png")
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = mat
	p.draw_pass_1 = q
	p.position = Vector3(2.7, 3.4, -1.5)
	p.preprocess = 0.6
	p.visibility_aabb = AABB(Vector3(-5, -5, -3), Vector3(10, 7, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(p)
	_added.append(p)
	p.emitting = true
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false)

## Deja la tienda como estaba (y el caldero de oro en su sitio para siempre).
func _cleanup() -> void:
	for id in _actors:
		var a: Actor = _actors[id]
		if is_instance_valid(a):
			a.queue_free()
	_actors.clear()
	for n in _added:
		if is_instance_valid(n):
			n.queue_free()
	_added.clear()
	world.cat.position = _cat_pos
	world.cat.play("sleep")
	world.refresh_upgrades()
	world._cam_base = _cam_base
	world._cam_target = _cam_target
	world.cam_fixed_x = INF
	world.block_hover(false)
	world.close_door()
	ui.hide_dialog()
	Ranking.mark_ending_seen()
	place_trophy(world)
