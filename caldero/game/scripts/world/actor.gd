extends Node3D
class_name Actor
## Personaje 2D en el mundo 3D: animaciones, caminar, saltitos y emociones.

const FRAME_W := 32
const FRAME_H := 48

var char_id := ""
var sprite: AnimatedSprite3D
var shadow: MeshInstance3D
var emote_sprite: Sprite3D
var facing := 1
var _walking := false
var _step_timer := 0.0
var _hop_tween: Tween
var _emote_tween: Tween

static var _shadow_mat: StandardMaterial3D

func setup(id: String, pixel := 0.04) -> void:
	char_id = id
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames = _build_frames(id)
	sprite.pixel_size = pixel
	sprite.centered = false
	sprite.offset = Vector2(-FRAME_W / 2.0, -2.0)
	sprite.shaded = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.double_sided = true
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
	shadow.position = Vector3(0, 0.012, 0.02)
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
	var idle_tex: Texture2D = load("res://assets/chars/%s_idle.png" % id)
	var walk_tex: Texture2D = load("res://assets/chars/%s_walk.png" % id)
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 1.6)
	sf.set_animation_loop("idle", true)
	for i in 2:
		var at := AtlasTexture.new()
		at.atlas = idle_tex
		at.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("idle", at)
	sf.add_animation("walk")
	sf.set_animation_speed("walk", 7.0)
	sf.set_animation_loop("walk", true)
	for i in 4:
		var at2 := AtlasTexture.new()
		at2.atlas = walk_tex
		at2.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("walk", at2)
	return sf

func height() -> float:
	return FRAME_H * sprite.pixel_size

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
			if char_id != "":
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
	emote_sprite.texture = load("res://assets/icons/emote_%s.png" % name)
	emote_sprite.position = Vector3(0, height() + 0.05, 0.05)
	emote_sprite.visible = true
	emote_sprite.scale = Vector3.ONE * 0.2
	if _emote_tween and _emote_tween.is_valid():
		_emote_tween.kill()
	_emote_tween = create_tween()
	_emote_tween.tween_property(emote_sprite, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tween.tween_property(emote_sprite, "scale", Vector3.ONE, 0.08)
	_emote_tween.parallel().tween_property(emote_sprite, "position:y", height() + 0.15, 0.2)
	if duration > 0.0:
		_emote_tween.tween_interval(duration)
		_emote_tween.tween_property(emote_sprite, "scale", Vector3.ZERO, 0.12)
		_emote_tween.tween_callback(func(): emote_sprite.visible = false)

func clear_emote() -> void:
	if _emote_tween and _emote_tween.is_valid():
		_emote_tween.kill()
	emote_sprite.visible = false
