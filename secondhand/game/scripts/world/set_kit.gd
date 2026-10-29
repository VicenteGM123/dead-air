extends Node3D
class_name SetKit
## --- SS CORE: la base de los dos escenarios (la tienda, ShopWorld, y la calle, StreetWorld): geometría 3D hecha por
## código con texturas pixel art (triplanar, sin suavizar), los props de assets/props con el px y el ancla de
## props.json (Sprite3D), la cámara HD-2D que sigue a Nell, su propio Environment (cada escenario lo pone en SU
## cámara: así no hay dos WorldEnvironment en la escena), estaciones con zona y clic (Walker), el cielo (día / noche,
## estrellas), la lluvia de chatarra (estrellas fugaces), naves que pasan y Kettle que sigue a Nell.
## Todo funciona con el renderizador Compatibility (WebGL 2): sin SSAO, sin niebla volumétrica, sin DOF de cámara.

signal station_clicked(id: String)

const KETTLE_GAP := 0.95        # Kettle camina a esta distancia detrás de Nell
const KETTLE_DZ := 0.42         # y un poco más cerca de la cámara (se ve entero: es chiquito)

var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var fill: OmniLight3D
var walker: Walker
var nell: Actor
var kettle: Actor
var kettle_follow := true       # false: Kettle hace otra cosa (servir el té)
var station_nodes := {}         # id -> Node3D (el punto del aviso y del cursor del mando)
var station_defs := {}          # id -> {"x", "face", "zone", "name", "y", "ax", "az"}
var cam_x0 := -2.0
var cam_x1 := 2.0
var cam_height := 3.5
var cam_dist := 8.0
var cam_look_y := 1.25
var cam_look_z := -1.6
var cam_fixed := false          # true: la cámara no sigue a Nell (capturas, la noche)
var cam_bias := 0.0             # la cámara mira un poco hacia un lado de Nell (en la tienda: hacia los clientes)
var props_info := {}
var night := false
var _mats := {}
var _cam_x := 0.0
var _t := 0.0
var _sky_mats: Array = []
var _streaks: Array = []        # [{"s": Sprite3D, "v": Vector3, "life": float, "t": float}]
var _streak_area := AABB()
var _flyers: Array = []         # naves que pasan: {"s", "flame", "from", "to", "dur", "t", "wait", "every"}
var _anim_sprites: Array = []   # [Sprite3D, frames, fps] (tiras animadas: ventilador, llamas)
var _kettle_walking := false

func _init() -> void:
	var f := FileAccess.open("res://assets/props/props.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			props_info = d

# ------------------------------------------------------------------ materiales y piezas

## Material triplanar en el mundo (pixel art sin suavizar). scale: repeticiones por metro.
func mat(albedo: String, scale := 0.5, tint := Color.WHITE, rough := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [albedo, scale, tint, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if albedo != "" and ResourceLoader.exists(albedo):
		m.albedo_texture = load(albedo)
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 20.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = rough
	_mats[key] = m
	return m

func flat(col: Color, unshaded := false) -> StandardMaterial3D:
	var key := "flat|%s|%s" % [col, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if col.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

## Caja por sus límites (más cómodo para paredes y muebles).
func box_b(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, m: Material, parent: Node3D = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x1 - x0, y1 - y0, z1 - z0)
	mi.mesh = bm
	mi.material_override = m
	mi.position = Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi

## Un cilindro de pie (tanques, postes, cúpulas bajas).
func cylinder(pos: Vector3, radius: float, height: float, m: Material, parent: Node3D = null, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos + Vector3(0, height / 2.0, 0)
	(parent if parent else self).add_child(mi)
	return mi

## Un cuadro plano mirando a la cámara (+z), centrado en pos.
func quad(size: Vector2, pos: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi

## Un sprite de una textura cualquiera (px = metros por píxel). anchor: "bottom" (apoyado), "top" (colgado),
## "center" (en la pared o en el cielo).
func sprite(path: String, px: float, pos: Vector3, anchor := "bottom", parent: Node3D = null, shaded := true, frames := 1, frame := 0) -> Sprite3D:
	var s := Sprite3D.new()
	if ResourceLoader.exists(path):
		s.texture = load(path)
	var w := 16.0
	var h := 16.0
	if s.texture:
		w = s.texture.get_width() / float(maxi(1, frames))
		h = float(s.texture.get_height())
	if frames > 1:
		s.hframes = frames
		s.frame = frame
	s.pixel_size = px
	s.centered = false
	match anchor:
		"top":
			s.offset = Vector2(-w / 2.0, -h)
		"center":
			s.offset = Vector2(-w / 2.0, -h / 2.0)
		_:
			s.offset = Vector2(-w / 2.0, 0.0)
	s.position = pos
	s.shaded = shaded
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	(parent if parent else self).add_child(s)
	return s

## Un prop de assets/props con su px, su ancla y sus cuadros de props.json (o los dados).
func prop(name_: String, pos: Vector3, px := -1.0, anchor := "", frame := 0, shaded := true, parent: Node3D = null) -> Sprite3D:
	var info: Dictionary = props_info.get(name_, {})
	var p := px if px > 0.0 else float(info.get("px", 0.03))
	var a := anchor if anchor != "" else String(info.get("anchor", "bottom"))
	return sprite("res://assets/props/%s.png" % name_, p, pos, a, parent, shaded, int(info.get("frames", 1)), frame)

## Una tira animada (ventilador, llamas): avanza de cuadro en _process.
func animate(s: Sprite3D, fps: float) -> void:
	if s and s.hframes > 1:
		_anim_sprites.append([s, s.hframes, fps, randf() * 10.0])

func omni(pos: Vector3, color: Color, energy: float, rng: float, shadows := false, parent: Node3D = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = shadows
	(parent if parent else self).add_child(l)
	return l

## Una zona clicable (Area3D) que llama a on_click con el botón izquierdo.
func pick(parent: Node3D, size: Vector3, offset: Vector3, on_click: Callable) -> Area3D:
	var a := Area3D.new()
	a.monitoring = false
	a.monitorable = false
	a.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	a.add_child(cs)
	a.input_event.connect(func(_cam, ev, _p, _n, _i):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	parent.add_child(a)
	return a

func make_actor(id: String, pos: Vector3, facing := 1, parent: Node3D = null) -> Actor:
	var a := Actor.new()
	a.name = id.capitalize()
	(parent if parent else self).add_child(a)
	a.setup(id)
	a.position = pos
	a.face(facing)
	return a

# ------------------------------------------------------------------ cámara, luz y cielo

## La cámara HD-2D (FOV 35, desde delante y arriba) con su propio Environment.
func setup_camera_env(interior: bool) -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 35.0
	camera.near = 0.1
	camera.far = 160.0
	add_child(camera)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.035, 0.03) if interior else Color(0.98, 0.8, 0.56)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.55, 0.62) if interior else Color(0.78, 0.7, 0.66)
	env.ambient_light_energy = 0.55 if interior else 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	camera.environment = env
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.7 if interior else 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0 if interior else 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation_degrees = Vector3(-38.0, 152.0, 0.0)
	add_child(sun)
	fill = OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(0.0, 3.2, 4.0)
	fill.omni_range = 14.0
	fill.omni_attenuation = 0.8
	fill.light_color = Color(1.0, 0.82, 0.66)
	fill.light_energy = 0.45
	add_child(fill)

## El cielo: un telón con degradé (día ámbar / noche violeta con estrellas que titilan). night_mix 0..1.
func sky_backdrop(size: Vector2, pos: Vector3) -> MeshInstance3D:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float night = 0.0;
uniform vec3 day_top = vec3(0.93, 0.62, 0.40);
uniform vec3 day_hor = vec3(1.0, 0.87, 0.64);
uniform vec3 night_top = vec3(0.045, 0.04, 0.13);
uniform vec3 night_hor = vec3(0.26, 0.15, 0.30);
uniform float bright = 1.2;
uniform float horizon = 2.0;
uniform vec3 dune_col = vec3(0.86, 0.6, 0.38);
uniform vec3 dune_night = vec3(0.12, 0.09, 0.16);
uniform vec2 star_grid = vec2(420.0, 120.0);   // celdas de estrellas (el telón grande de la calle: más celdas)
uniform float star_size = 0.16;                 // radio de la estrella dentro de su celda (puntitos, no cuadros)
void fragment() {
	vec2 uv = UV;
	vec3 dayc = mix(day_hor, day_top, smoothstep(0.82, 0.08, uv.y));
	vec3 nightc = mix(night_hor, night_top, smoothstep(0.95, 0.15, uv.y));
	vec3 col = mix(dayc * bright, nightc, night);
	float hz = horizon + 0.010 * sin(uv.x * 37.0) + 0.006 * sin(uv.x * 91.0 + 1.3);
	float dune = step(hz, uv.y);
	col = mix(col, mix(dune_col, dune_night, night), dune);
	// estrellas: un punto chico (y no siempre en el centro) en algunas celdas; unas pocas más grandes y más blancas
	vec2 cell = uv * star_grid;
	vec2 g = floor(cell);
	float h = fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453);
	float h2 = fract(sin(dot(g, vec2(39.3468, 11.135))) * 24634.6345);
	vec2 c = vec2(0.25 + 0.5 * h2, 0.25 + 0.5 * fract(h * 7.31));
	float big = step(0.996, h);
	float r = star_size * (1.0 + 0.9 * big);
	float d = length(fract(cell) - c);
	float dot_ = 1.0 - smoothstep(r * 0.55, r, d);
	float star = step(0.978, h) * dot_ * night * smoothstep(0.92, 0.3, uv.y) * (1.0 - dune);
	float tw = 0.6 + 0.4 * sin(TIME * (0.8 + h * 2.5) + h * 40.0);
	col += mix(vec3(1.0, 0.86, 0.7), vec3(1.0, 0.97, 0.92), big) * star * tw * (1.2 + big);
	ALBEDO = col;
}
"""
	sm.shader = sh
	_sky_mats.append(sm)
	var mi := quad(size, pos, sm)
	mi.name = "Sky"
	return mi

## La lluvia de chatarra (de noche): estrellas fugaces que cruzan en diagonal hacia abajo a la izquierda (la cabeza
## adelante), dentro de una caja del cielo.
func setup_streaks(area: AABB, count := 6, px := 0.06) -> void:
	_streak_area = area
	for i in count:
		var s := prop("starfall", Vector3.ZERO, px, "center", 0, false)
		s.name = "Streak%d" % i
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		_streaks.append({"s": s, "v": Vector3.ZERO, "life": 0.0, "t": randf_range(0.0, 3.0)})

func _update_streaks(delta: float) -> void:
	for st in _streaks:
		var s: Sprite3D = st["s"]
		if not night:
			s.visible = false
			continue
		st["t"] = float(st["t"]) - delta
		if float(st["t"]) > 0.0 and not s.visible:
			continue
		if not s.visible:
			# nace arriba a la derecha de la caja y cae hacia abajo a la izquierda
			var a := _streak_area
			s.position = Vector3(randf_range(a.position.x + a.size.x * 0.25, a.end.x), randf_range(a.position.y + a.size.y * 0.45, a.end.y),
				randf_range(a.position.z, a.end.z))
			var sp := randf_range(4.0, 7.0) * (a.size.x / 30.0 + 0.5)
			st["v"] = Vector3(-1.0, -0.42, 0.0).normalized() * sp
			st["life"] = randf_range(0.9, 1.6)
			s.visible = true
			s.modulate = Color(1.4, 1.2, 0.9, 0.0)
		st["life"] = float(st["life"]) - delta
		s.position += st["v"] * delta
		var life := float(st["life"])
		s.modulate.a = clampf(minf(life * 2.0, 1.0), 0.0, 1.0)
		if life <= 0.0:
			s.visible = false
			st["t"] = randf_range(0.3, 2.6)

## Una nave que cruza (o despega) cada `every` segundos: sprite + llama opcional (thrust_flame, 3 cuadros).
## from / to: dónde aparece y a dónde llega en `dur` segundos. flame_off: dónde va la llama respecto de la nave.
func add_flyer(tex: String, px: float, from: Vector3, to: Vector3, dur: float, every: float, flame_off := Vector3.ZERO, flame_rot := 0.0, first_wait := -1.0, sound := "") -> Dictionary:
	var s := prop(tex, from, px, "center", 0, false)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.flip_h = to.x < from.x
	var flame: Sprite3D = null
	if flame_off != Vector3.ZERO:
		flame = prop("thrust_flame", Vector3.ZERO, px * 0.85, "center", 0, false, s)
		flame.position = flame_off
		flame.rotation_degrees = Vector3(0, 0, flame_rot)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.modulate = Color(1.5, 1.25, 1.0)
		animate(flame, 12.0)
	var d := {"s": s, "flame": flame, "from": from, "to": to, "dur": dur, "t": 0.0,
		"wait": first_wait if first_wait >= 0.0 else randf_range(1.0, every), "every": every, "sound": sound}
	s.visible = false
	_flyers.append(d)
	return d

func _update_flyers(delta: float) -> void:
	for f in _flyers:
		var s: Sprite3D = f["s"]
		if night:
			s.visible = false
			continue
		if float(f["wait"]) > 0.0:
			f["wait"] = float(f["wait"]) - delta
			if float(f["wait"]) <= 0.0:
				f["t"] = 0.0
				s.visible = true
				if String(f["sound"]) != "" and is_visible_in_tree():
					Sfx.play(f["sound"], 0.05, -10.0)
			continue
		f["t"] = float(f["t"]) + delta
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		# despegue: arranca despacio (ease in)
		var e := k * k * (0.6 + 0.4 * k) if Vector3(f["to"]).y > Vector3(f["from"]).y + 2.0 else k
		s.position = Vector3(f["from"]).lerp(f["to"], e)
		if k >= 1.0:
			s.visible = false
			f["wait"] = float(f["every"]) * randf_range(0.8, 1.25)

## Una frase corta sobre la cabeza de alguien, que sube y se desvanece (quien se va, quien vende, quien agradece).
func blurt(a: Node3D, text: String, col := Color(1.0, 0.95, 0.85), secs := 2.6) -> void:
	if not is_instance_valid(a) or text == "":
		return
	UIKit.load_fonts()
	var l := Label3D.new()
	l.text = text
	l.font = UIKit.font_bold
	l.font_size = 38
	l.pixel_size = 0.0042
	l.outline_size = 12
	l.outline_modulate = Color(0.1, 0.06, 0.05)
	l.modulate = Color(col.r, col.g, col.b, 0.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 9
	l.shaded = false
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(l)
	var head: float = a.call("top_height") if a.has_method("top_height") else 1.6
	var y0 := head + 0.55 + _blurt_lift(a)
	l.position = Vector3(0.0, y0, 0.12)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_property(l, "position:y", y0 + 0.22, secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(secs - 0.45)
	tw.chain().tween_callback(l.queue_free)

## Cuánto más arriba va la frase de alguien (cada escenario decide: p. ej. si ahí ya va un aviso).
func _blurt_lift(_a: Node3D) -> float:
	return 0.0

# ------------------------------------------------------------------ Nell, Kettle, el carril y las estaciones

## Nell y su carril (Walker), con las estaciones (defs: id -> {"x", "face", "zone", "name", "y", "ax", "az"}).
func setup_nell(lane: Array, defs: Dictionary, start_x: float) -> void:
	station_defs = defs
	nell = make_actor("nell", Vector3(start_x, 0.0, 0.0), 1)
	nell.name = "Nell"
	walker = Walker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.stations = defs
	walker.setup(nell, lane, start_x, 1)
	for id in defs:
		var s: Dictionary = defs[id]
		var anchor := Node3D.new()
		anchor.name = "Station_" + id
		anchor.position = Vector3(float(s.get("ax", s["x"])), 0.0, float(s.get("az", -2.6)))
		add_child(anchor)
		station_nodes[id] = anchor
		var sid: String = id
		var sz: Vector3 = s.get("pick", Vector3(1.4, 2.2, 1.2))
		pick(anchor, sz, Vector3(0, sz.y / 2.0, 0), func(): station_clicked.emit(sid))

func setup_kettle(pos: Vector3) -> void:
	kettle = make_actor("kettle", pos, 1)
	kettle.name = "Kettle"

## Kettle va detrás de Nell (si kettle_follow).
func _update_kettle(delta: float) -> void:
	if kettle == null or nell == null or not kettle_follow:
		return
	var target := Vector3(nell.position.x - float(nell.facing) * KETTLE_GAP, 0.0, nell.position.z + KETTLE_DZ)
	target.x = clampf(target.x, walker.x_min() - 0.3, walker.x_max() + 0.3)
	var to := target - kettle.position
	to.y = 0.0
	var d := to.length()
	if d > 0.18:
		var sp := clampf(d * 2.4, 0.8, 3.6) * delta
		kettle.position += to / d * minf(sp, d)
		if absf(to.x) > 0.05:
			kettle.face(1 if to.x > 0.0 else -1)
		if not _kettle_walking:
			_kettle_walking = true
			kettle.set_walking(true)
	elif _kettle_walking:
		_kettle_walking = false
		kettle.set_walking(false)
		kettle.face(nell.facing)

## Lo tocable para el cursor del mando: [[Node3D, alto], ...]
func pad_picks() -> Array:
	var out := []
	for id in station_nodes:
		out.append([station_nodes[id], 1.2])
	return out

## El punto (en 3D) sobre el que va el aviso de una estación.
func prompt_point(id: String) -> Vector3:
	var n: Node3D = station_nodes.get(id)
	if n == null:
		return Vector3.ZERO
	return n.global_position + Vector3(0, float(station_defs.get(id, {}).get("y", 1.8)), 0)

## La x del suelo bajo un punto de la pantalla (para caminar con un clic). NAN si no da en el suelo.
func floor_x_at(screen_pos: Vector2, z_min := -6.0, z_max := 3.5) -> float:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return NAN
	var t := -from.y / dir.y
	if t <= 0.0:
		return NAN
	var p := from + dir * t
	if p.z < z_min or p.z > z_max:
		return NAN
	return p.x

func screen_pos(p: Vector3) -> Vector2:
	return camera.unproject_position(p)

func is_on_screen(p: Vector3) -> bool:
	return not camera.is_position_behind(p) and get_viewport().get_visible_rect().has_point(camera.unproject_position(p))

## La cámara: x sigue a Nell (entre cam_x0 y cam_x1).
func place_camera(x: float) -> void:
	camera.position = Vector3(x, cam_height, cam_dist)
	camera.look_at(Vector3(x, cam_look_y, cam_look_z), Vector3.UP)

func snap_camera() -> void:
	if nell:
		_cam_x = clampf(nell.position.x + cam_bias, cam_x0, cam_x1)
	place_camera(_cam_x)

## Activa o apaga el escenario entero (visible, su cámara, su proceso).
func activate(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if camera:
		camera.current = on
	if on:
		snap_camera()

## Noche (true) o día: el cielo, las estrellas fugaces, las naves. Cada escenario agrega lo suyo (set_night override).
func set_night(on: bool) -> void:
	night = on
	for sm in _sky_mats:
		(sm as ShaderMaterial).set_shader_parameter("night", 1.0 if on else 0.0)

func _process(delta: float) -> void:
	_t += delta
	for a in _anim_sprites:
		var s: Sprite3D = a[0]
		if is_instance_valid(s) and s.is_visible_in_tree():
			a[3] = float(a[3]) + delta * float(a[2])
			s.frame = int(a[3]) % int(a[1])
	_update_streaks(delta)
	_update_flyers(delta)
	_update_kettle(delta)
	if camera and nell and not cam_fixed:
		var target := clampf(nell.position.x + cam_bias, cam_x0, cam_x1)
		_cam_x = lerpf(_cam_x, target, 1.0 - exp(-3.0 * delta))
		place_camera(_cam_x)
		camera.position.y += sin(_t * 0.6) * 0.008   # la cámara HD-2D respira
