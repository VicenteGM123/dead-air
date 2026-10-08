extends Node
## PHAROS user interface (Game.hud). Built entirely in code: screen effects, HUD, world prompt, banners and
## toasts, touch controls, menus and the blessing picker, each on its own CanvasLayer. Runs while the tree is
## paused and ignores hit-stop.
##
## Called by the game: show_title(), show_blessings(ids), show_end(victory), screen_flash(color, dur),
## hurt_flash(amount_0_1).
## Debug: `uitest=title|hud|night|boss|blessing|pause|options|controls|victory|defeat|touch|down|hurt|deny` forces a
## screen for screenshots (the game is started when the screen needs it); `uiids=zeus,ares,hermes` picks the
## blessings shown; `touch=1` forces the touch layout; `uiscale=1.3` forces the UI scale.

const S := preload("res://scripts/ui/style.gd")
const G := preload("res://scripts/ui/glyphs.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const PromptScript := preload("res://scripts/ui/prompt.gd")
const BannersScript := preload("res://scripts/ui/banners.gd")
const MenusScript := preload("res://scripts/ui/menus.gd")
const BlessingsScript := preload("res://scripts/ui/blessings.gd")
const TouchScript := preload("res://scripts/ui/touch.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform float vignette = 0.25;
uniform float hurt = 0.0;
uniform float aspect = 1.7778;
uniform vec4 ink : source_color = vec4(0.045, 0.038, 0.085, 1.0);
uniform vec4 blood : source_color = vec4(0.58, 0.07, 0.05, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= mix(1.0, aspect, 0.3);
	float d = length(p);
	float v = smoothstep(0.7, 1.8, d) * vignette;
	float h = smoothstep(0.42, 1.45, d) * hurt;
	float a = clamp(v + h * 0.8, 0.0, 0.9);
	vec3 col = mix(ink.rgb, blood.rgb, clamp(h / max(v + h, 0.0001), 0.0, 1.0));
	COLOR = vec4(col, a);
}
"""

const GAMEPLAY := [Game.Phase.DAY, Game.Phase.DUSK, Game.Phase.NIGHT, Game.Phase.DAWN]

var hud: Control
var prompt: Control
var banners: Control
var menus: Control
var picker: Control
var touch: Control
var _fx_layer: CanvasLayer
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _flash: ColorRect
var _flash_t := 0.0
var _flash_dur := 0.0
var _flash_col := Color.WHITE
var _hurt := 0.0
var _touch_forced := false
var _dev_rev := -1
var _starting := false
var _hero_input_locked := false
var _modal := false
var _shot_frames := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run before the camera rig each frame, so "Temblor de cámara: No" can cancel the shake before it is used.
	process_priority = -10
	if Game.arg("shadows", "") == "": # tests that force shadows keep their choice
		Settings.apply_quality(get_viewport())
	_touch_forced = Game.arg("touch", "0") == "1"
	if _touch_forced:
		G.set_device("touch")
	elif OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		G.set_device("touch")
	_setup_menu_input()
	_apply_ui_scale()
	_build()
	Game.phase_changed.connect(_on_phase)
	Game.message.connect(_on_message)
	var mode := String(Game.arg("uitest", ""))
	if mode != "":
		_debug.call_deferred(mode)
	if String(Game.arg("uishot", "")) != "":
		_shot_frames = int(Game.arg("uishotf", "90"))


## Menus must answer to the pad and to WASD as well as to the arrows: add what Godot's ui_* actions lack.
func _setup_menu_input() -> void:
	var add_joy := func(action: String, button: JoyButton) -> void:
		if not InputMap.has_action(action):
			return
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
				return
		var j := InputEventJoypadButton.new()
		j.button_index = button
		j.device = -1
		InputMap.action_add_event(action, j)
	add_joy.call("ui_accept", JOY_BUTTON_A)
	add_joy.call("ui_cancel", JOY_BUTTON_B)
	var add_key := func(action: String, key: Key) -> void:
		if not InputMap.has_action(action):
			return
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == key:
				return
		var k := InputEventKey.new()
		k.physical_keycode = key
		InputMap.action_add_event(action, k)
	add_key.call("ui_up", KEY_W)
	add_key.call("ui_down", KEY_S)
	add_key.call("ui_left", KEY_A)
	add_key.call("ui_right", KEY_D)


## Phones get a larger UI so text stays readable on a small screen.
func _apply_ui_scale() -> void:
	var forced := float(Game.arg("uiscale", "0"))
	var s := 1.0
	if forced > 0.0:
		s = forced
	elif G.device == "touch":
		var win := get_window()
		var css_h := float(win.size.y) / maxf(1.0, DisplayServer.screen_get_scale())
		if css_h < 480.0:
			s = 1.3
		elif css_h < 760.0:
			s = 1.15
	if not is_equal_approx(get_window().content_scale_factor, s):
		get_window().content_scale_factor = s


func _layer(n: String, order: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = n
	l.layer = order
	add_child(l)
	return l


func _build() -> void:
	_fx_layer = _layer("ScreenFx", 50)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vignette.material = _vig_mat
	_fx_layer.add_child(_vignette)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	_fx_layer.add_child(_flash)
	var world := _layer("WorldUI", 52)
	prompt = PromptScript.new()
	world.add_child(prompt)
	var hl := _layer("HUD", 54)
	hud = HudScript.new()
	hl.add_child(hud)
	prompt.set("hud", hud)
	banners = BannersScript.new()
	hl.add_child(banners)
	var tl := _layer("Touch", 56)
	touch = TouchScript.new()
	touch.ui = self
	touch.modulate.a = 0.0
	tl.add_child(touch)
	var ml := _layer("Menus", 60)
	picker = BlessingsScript.new()
	ml.add_child(picker)
	menus = MenusScript.new()
	menus.ui = self
	ml.add_child(menus)
	_update_touch()


# --- API used by the game ----------------------------------------------------------------------------------

func show_title() -> void:
	hud.call("show_hud", false)
	banners.call("clear")
	menus.call("open_title")
	_update_touch()


func show_blessings(ids: Array) -> void:
	_lock_hero(true)
	picker.call("open", ids)
	_update_touch()


func show_end(victory: bool) -> void:
	_lock_hero(false)
	if picker.call("is_open"):
		picker.call("close")
	if get_tree().paused:
		get_tree().paused = false
		Game.paused = false
	hud.call("show_hud", false)
	banners.call("clear")
	menus.call("open_end", victory)
	_update_touch()


func screen_flash(col: Color, dur: float) -> void:
	_flash_col = col
	_flash_dur = maxf(0.05, dur)
	_flash_t = _flash_dur
	_flash.visible = true


func hurt_flash(amount: float) -> void:
	_hurt = maxf(_hurt, clampf(0.32 + amount * 2.6, 0.32, 1.0))


# --- flow --------------------------------------------------------------------------------------------------

func begin_game() -> void:
	if _starting:
		return
	_starting = true
	menus.call("close_all")
	await get_tree().create_timer(0.3, true, false, true).timeout
	_starting = false
	if Game.phase == Game.Phase.TITLE and Game.main and Game.main.has_method("start_game"):
		Game.main.start_game()


func can_pause() -> bool:
	return GAMEPLAY.has(Game.phase) and not menus.call("is_open") and not picker.call("is_open") and not _starting


func open_pause() -> void:
	if not can_pause():
		return
	get_tree().paused = true
	Game.paused = true
	S.sfx("ui_select")
	menus.call("open_pause")
	_update_touch()


func resume() -> void:
	menus.call("close_all")
	get_tree().paused = false
	Game.paused = false
	S.sfx("ui_back")
	_update_touch()


## Reloads the island: straight into a new game (`play`) or back to the title.
func restart(play: bool) -> void:
	if play:
		Game.args["play"] = "1"
	else:
		for k in ["play", "bot", "test"]:
			Game.args.erase(k)
	Game.args.erase("uitest")
	if Game.main and Game.main.has_method("restart"):
		Game.main.restart()


## Defeat screen, "Reintentar la noche": back to the day before the lost night (Game.main.retry_night()).
func retry_night() -> void:
	if _starting:
		return
	menus.call("close_all")
	get_tree().paused = false
	Game.paused = false
	banners.call("clear")
	if Game.main and Game.main.has_method("retry_night"):
		Game.main.retry_night()
	_update_touch()


func _lock_hero(on: bool) -> void:
	var h := Game.hero
	if h == null or not is_instance_valid(h):
		return
	if on and h.input_enabled:
		h.input_enabled = false
		_hero_input_locked = true
	elif not on and _hero_input_locked:
		h.input_enabled = true
		_hero_input_locked = false


# --- events ------------------------------------------------------------------------------------------------

func _on_phase(p: int) -> void:
	var gameplay := GAMEPLAY.has(p)
	hud.call("set_phase", p)
	hud.call("show_hud", gameplay and not _modal)
	prompt.set("enabled", p == Game.Phase.DAY and not _modal)
	if p != Game.Phase.BLESSING:
		if picker.call("is_open"):
			picker.call("close")
		_lock_hero(false)
	if p == Game.Phase.DEFEAT:
		banners.call("clear")
	_update_touch()


func _on_message(text: String, sub: String, kind: String) -> void:
	if Game.phase == Game.Phase.TITLE or Game.phase == Game.Phase.VICTORY or Game.phase == Game.Phase.DEFEAT:
		return
	banners.call("post", text, sub, kind)


func _input(e: InputEvent) -> void:
	G.observe(e)
	if picker.call("is_open"):
		return
	var pause_key := e.is_action_pressed("pause")
	var cancel := e.is_action_pressed("ui_cancel")
	if not pause_key and not cancel:
		return
	if menus.call("is_open"):
		if menus.call("back"):
			get_viewport().set_input_as_handled()
		elif menus.call("is_pause_open"):
			resume()
			get_viewport().set_input_as_handled()
	elif pause_key and can_pause():
		open_pause()
		get_viewport().set_input_as_handled()


func _update_touch() -> void:
	var touch_mode := _touch_forced or G.device == "touch"
	var want: bool = touch_mode and GAMEPLAY.has(Game.phase) and not menus.call("is_open") and not picker.call("is_open") and not get_tree().paused
	touch.call("set_active", want)
	hud.call("set_touch_layout", touch_mode)
	# Toasts sit above the bottom chevrons (and, on touch, above the thumb buttons).
	banners.call("set_toast_bottom", 98.0 if not touch_mode else 156.0)


func _process(delta: float) -> void:
	var rd := S.rdelta(delta)
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			_save_shot()
	if _dev_rev != G.revision:
		_dev_rev = G.revision
		_update_touch()
	# A menu or the blessing picker owns the screen: the HUD, banners and the world prompt step back.
	var modal: bool = menus.call("is_open") or picker.call("is_open")
	if modal != _modal:
		_modal = modal
		hud.call("show_hud", GAMEPLAY.has(Game.phase) and not modal)
		prompt.set("enabled", Game.phase == Game.Phase.DAY and not modal)
		_update_touch()
	banners.modulate.a = move_toward(banners.modulate.a, 0.0 if modal else 1.0, rd * 6.0)
	var presence: float = banners.call("presence")
	hud.set("hint_dim", presence)
	if prompt.call("has_target"):
		banners.call("hurry")
	prompt.set("dim", presence)
	if Game.rig and "trauma" in Game.rig and not bool(Settings.get_v("shake")):
		Game.rig.trauma = 0.0
	# Screen effects: permanent soft vignette (a touch deeper at night), red hurt pulse, full-screen flash.
	var night := 0.0
	if Game.main and Game.main.tod:
		night = Game.main.tod.night_amount()
	var low := 0.0
	var h := Game.hero
	if h and is_instance_valid(h) and h.alive and GAMEPLAY.has(Game.phase):
		var ratio: float = h.hp / maxf(1.0, h.max_hp)
		if ratio < 0.3:
			low = (0.3 - ratio) / 0.3 * (0.22 + 0.1 * sin(S.now() * 5.0))
	_hurt = maxf(0.0, _hurt - rd * 1.7)
	var gameplay := GAMEPLAY.has(Game.phase)
	_vig_mat.set_shader_parameter("vignette", (0.24 + 0.16 * night) if gameplay else 0.16)
	_vig_mat.set_shader_parameter("hurt", clampf(_hurt + low, 0.0, 1.0))
	var vs := _vignette.size
	_vig_mat.set_shader_parameter("aspect", vs.x / maxf(1.0, vs.y))
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - rd)
		var k := _flash_t / _flash_dur
		_flash.color = Color(_flash_col, 0.55 * k * k)
		_flash.visible = _flash_t > 0.0


# --- debug screens (screenshots) ---------------------------------------------------------------------------

func _debug(mode: String) -> void:
	await get_tree().process_frame
	var m: Node = Game.main
	if m == null:
		return
	if mode == "title":
		return
	if Game.phase == Game.Phase.TITLE:
		menus.call("close_all")
		m.start_game()
		await get_tree().process_frame
	match mode:
		"hud", "day", "touch", "deny":
			_debug_prompt(mode)
		"night":
			Game.night = maxi(Game.night, 2)
			Game.args["nearfight"] = "1"
			Game.time_scale_target = 3.0
			m.call_night()
			await get_tree().create_timer(4.6).timeout
			Game.time_scale_target = 1.0
		"boss":
			Game.night = Data.NIGHTS - 1
			Game.time_scale_target = 3.0
			m.call_night()
			await get_tree().create_timer(9.0).timeout
			Game.time_scale_target = 1.0
		"blessing":
			if Game.arg("uiids", "") != "":
				Game.set_phase(Game.Phase.BLESSING)
				show_blessings(String(Game.arg("uiids")).split(","))
			else:
				m.offer_blessings()
		"pause":
			open_pause()
		"options":
			open_pause()
			menus.call("open_options")
		"controls":
			open_pause()
			menus.call("open_controls")
		"victory", "defeat":
			var win := mode == "victory"
			Game.night = Data.NIGHTS if win else 4
			Game.stats["kills"] = 187 if win else 64
			Game.stats["built"] = 14 if win else 9
			Game.stats["cats"] = 5 if win else 2
			Game.stats["deaths"] = 2 if win else 3
			Game.set_phase(Game.Phase.VICTORY if win else Game.Phase.DEFEAT)
			show_end(win)
		"down":
			await get_tree().create_timer(1.0).timeout
			Game.hero.take_damage(9999.0)
		"hurt":
			await get_tree().create_timer(1.0).timeout
			Game.hero.hp = Game.hero.max_hp * 0.2
			hurt_flash(0.3)


## Debug `uishot=<file.png>`: saves the window as it really is after `uishotf` frames, then quits (the movie
## writer always encodes at the project size, which distorts phone-sized windows).
func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(String(Game.arg("uishot")))
	get_tree().quit()


## Puts Fanós next to an empty tower plot and pays part of it, so the prompt shows its hold ring and price.
func _debug_prompt(mode: String) -> void:
	var m: Node = Game.main
	var best: Node3D = null
	for sp in m.spots:
		if sp.type == "tower" and sp.is_unlocked() and sp.level() == 0:
			if best == null or sp.global_position.distance_to(Game.hero.global_position) < best.global_position.distance_to(Game.hero.global_position):
				best = sp
	if best:
		# On the camera side of the plot, so the card floats over the plot and not over Fanós.
		Game.hero.teleport(best.global_position + Vector3(0.9, 0.0, 2.0))
		m.rig.snap()
	Game.hero.favor = Game.hero.favor_max() * (0.62 if mode == "deny" else 1.0)
	Game.hero.favor_changed.emit(Game.hero.favor, Game.hero.favor_max())
	if mode == "touch":
		_touch_forced = true
		G.set_device("touch")
		_update_touch()
	if mode == "deny":
		Game.coins = 0
		Game.coins_changed.emit(0, 0)
	await get_tree().create_timer(0.6).timeout
	Input.action_press("interact")
	await get_tree().create_timer(0.45).timeout
	if mode != "deny":
		Input.action_release("interact")
