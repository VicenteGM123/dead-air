extends Node3D
class_name Actor
## Personaje 2D en el mundo 3D: animaciones, caminar, saltitos y emociones.
## --- SS SEED: copiado de Midnight Cauldron (scripts/world/actor.gd) sin cambios de comportamiento. Lo nuevo:
## si falta la hoja de un personaje (assets/chars/<id>_idle.png / _walk.png) usa la de PLACEHOLDER_ID en vez de
## romperse, y emote() no hace nada si falta su icono (assets/icons/emote_<nombre>.png).
const PLACEHOLDER_ID := "nell"

## Alto de cuadro de referencia: `pixel` en setup() es el tamaño de un píxel para un cuadro de 48 px de alto.
## Los sprites pueden tener otra resolución (los actuales son de 64x96): se ven del mismo tamaño en el mundo.
const REF_H := 48.0
## Escala del arte (pasada 4, estilo Octopath): los personajes se dibujan más chicos dentro del cuadro de 64x96
## (un adulto mide 60-64 px en vez de ~70), con píxeles más gruesos; este único factor los agranda en el mundo para
## que un adulto mida lo mismo que antes (mostradores, puertas y estantes se hacen para esa altura). Igual para todos.
const ART_SCALE := 1.11

var char_id := ""
var frame_w := 64
var frame_h := 96
var _top_px := 0
var sprite: AnimatedSprite3D
var shadow: MeshInstance3D
var emote_sprite: Sprite3D
var facing := 1
var _walking := false
var _step_timer := 0.0
var _hop_tween: Tween
var _emote_tween: Tween

static var _shadow_mat: StandardMaterial3D
# --- R5 WORLD: dos personajes nunca en el mismo plano. Los sprites miran todos a la cámara; si dos quedan a la misma
# profundidad y se tapan (una fila de clientes, la gente de la calle en su carril), el búfer de profundidad
# no sabe cuál va delante y su borde tiembla (z-fighting). Cada personaje nuevo corre su dibujo unos milímetros hacia
# atrás (-z, lejos de la cámara), distinto del anterior: de 0 a 3,5 cm en pasos de 7 mm. La sombra sigue en los pies.
const Z_BIAS := [0.0, -0.021, -0.007, -0.028, -0.014, -0.035]
static var _z_seq := 0
## La sombra de mancha va 2,4 cm sobre el suelo (era 1,2 cm: la misma altura que las alfombras y las manchas de luz
## del suelo, y temblaba sobre ellas).
const SHADOW_Y := 0.024
# --- end R5 WORLD

func setup(id: String, pixel := 0.04) -> void:
	char_id = id
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames = _build_frames(id)
	sprite.pixel_size = pixel * REF_H / float(frame_h) * ART_SCALE
	sprite.centered = false
	sprite.offset = Vector2(-frame_w / 2.0, -2.0 * frame_h / REF_H)
	sprite.shaded = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.double_sided = true
	sprite.position.z = Z_BIAS[_z_seq % Z_BIAS.size()]   # --- R5 WORLD
	_z_seq += 1   # --- R5 WORLD
	add_child(sprite)
	sprite.play("idle")
	sprite.speed_scale = randf_range(0.9, 1.1)

	shadow = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.75, 0.32)
	shadow.mesh = pm
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.albedo_texture = load("res://assets/tex/blob_shadow.png")
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_shadow_mat.albedo_color = Color(1, 1, 1, 0.85)
	shadow.material_override = _shadow_mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position = Vector3(0, SHADOW_Y, 0.02)   # --- R5 WORLD: (era 0.012)
	add_child(shadow)

	emote_sprite = Sprite3D.new()
	emote_sprite.pixel_size = 0.04
	emote_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	emote_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	emote_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	emote_sprite.shaded = false
	emote_sprite.no_depth_test = true
	emote_sprite.render_priority = 10
	emote_sprite.visible = false
	emote_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emote_sprite)

func _build_frames(id: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	# --- SS SEED: hoja de reemplazo si todavía no existe la del personaje (el arte llega en otra línea de trabajo)
	var sheet_id := id
	if not ResourceLoader.exists("res://assets/chars/%s_idle.png" % id) or not ResourceLoader.exists("res://assets/chars/%s_walk.png" % id):
		push_warning("Actor: falta la hoja de '%s', uso la de '%s'" % [id, PLACEHOLDER_ID])
		sheet_id = PLACEHOLDER_ID
	var idle_tex: Texture2D = load("res://assets/chars/%s_idle.png" % sheet_id)
	var walk_tex: Texture2D = load("res://assets/chars/%s_walk.png" % sheet_id)
	# --- end SS SEED
	# tamaño de cuadro según la textura (idle = 2 cuadros, walk = 4 cuadros en fila)
	frame_h = idle_tex.get_height()
	frame_w = int(idle_tex.get_width() / 2.0)
	var walk_w := int(walk_tex.get_width() / 4.0)
	var img := idle_tex.get_image()
	_top_px = img.get_used_rect().position.y if img else 0
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 1.6)
	sf.set_animation_loop("idle", true)
	for i in 2:
		var at := AtlasTexture.new()
		at.atlas = idle_tex
		at.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		sf.add_frame("idle", at)
	sf.add_animation("walk")
	sf.set_animation_speed("walk", 7.0)
	sf.set_animation_loop("walk", true)
	for i in 4:
		var at2 := AtlasTexture.new()
		at2.atlas = walk_tex
		at2.region = Rect2(i * walk_w, 0, walk_w, frame_h)
		sf.add_frame("walk", at2)
	return sf

func height() -> float:
	return frame_h * sprite.pixel_size

## Alto de la parte visible del sprite (cabeza, sombrero...) sobre el suelo.
func top_height() -> float:
	return (frame_h - _top_px - 2.0 * frame_h / REF_H) * sprite.pixel_size

func face(dir: int) -> void:
	facing = 1 if dir >= 0 else -1
	sprite.flip_h = facing < 0

func face_towards(p: Vector3) -> void:
	if absf(p.x - global_position.x) > 0.05:
		face(1 if p.x > global_position.x else -1)

func walk_to(target: Vector3, speed := 1.7) -> void:
	var dist := global_position.distance_to(target)
	if dist < 0.02:
		return
	face_towards(target)
	_walking = true
	sprite.play("walk")
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, dist / speed)
	await tw.finished
	_walking = false
	sprite.play("idle")

func walk_path(points: Array, speed := 1.7) -> void:
	for p in points:
		await walk_to(p, speed)

func _process(delta: float) -> void:
	if _walking:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.32
			if char_id != "" and not quiet:   # --- WORLD: 'quiet' (gente de fondo, sin pasos)
				Sfx.step()

func hop(times := 1, h := 0.18) -> void:
	if _hop_tween and _hop_tween.is_valid():
		_hop_tween.kill()
	_hop_tween = create_tween()
	for i in times:
		_hop_tween.tween_property(sprite, "position:y", h, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hop_tween.tween_property(sprite, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func shake() -> void:
	var tw := create_tween()
	for i in 3:
		tw.tween_property(sprite, "position:x", 0.05, 0.05)
		tw.tween_property(sprite, "position:x", -0.05, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.05)

func emote(name: String, duration := 1.6) -> void:
	# --- SS SEED: sin icono, sin emoción (y sin error en la consola de la web)
	var path := "res://assets/icons/emote_%s.png" % name
	if not ResourceLoader.exists(path):
		return
	emote_sprite.texture = load(path)
	emote_sprite.position = Vector3(0, top_height() + 0.05, 0.05)
	emote_sprite.visible = true
	emote_sprite.scale = Vector3.ONE * 0.2
	if _emote_tween and _emote_tween.is_valid():
		_emote_tween.kill()
	_emote_tween = create_tween()
	_emote_tween.tween_property(emote_sprite, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tween.tween_property(emote_sprite, "scale", Vector3.ONE, 0.08)
	_emote_tween.parallel().tween_property(emote_sprite, "position:y", top_height() + 0.15, 0.2)
	if duration > 0.0:
		_emote_tween.tween_interval(duration)
		_emote_tween.tween_property(emote_sprite, "scale", Vector3.ZERO, 0.12)
		_emote_tween.tween_callback(func(): emote_sprite.visible = false)

func clear_emote() -> void:
	if _emote_tween and _emote_tween.is_valid():
		_emote_tween.kill()
	emote_sprite.visible = false

# --- WORLD: caminar controlado desde fuera (scripts/world/walker.gd) y gente que pasea sin ruido de pasos
var quiet := false

## Pone o quita la animación de caminar (y los pasos) sin mover al personaje: lo mueve Walker u otro código.
func set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	sprite.play("walk" if on else "idle")
	if on:
		_step_timer = 0.12
# --- end WORLD
