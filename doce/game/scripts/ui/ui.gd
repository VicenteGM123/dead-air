extends Node
## DOCE user interface (Game.ui, and Game.hud for screen flashes). Built entirely in code, each part on its own
## CanvasLayer: screen effects (vignette, hurt pulse, flash), the world prompt, the HUD (vitals, stamina ring,
## boss bar, lock-on reticle), messages (banners and toasts), the frieze cards (labours, victory, death) and the
## menus (title, pause, options, controls). Runs while the tree is paused and ignores hit-stop.
##
## Called by main.gd: show_title(), show_play(), show_pause(paused). By Fx: screen_flash(color, seconds).
## Also public: show_labor_card(index, title), show_victory(index, title, sub), hurt_flash(amount_0_1),
## auto_labor_card (labour I's card on first entering the Lion's arena, see _check_cave_entry),
## owns_title() (true: the title has a menu, main should not start the game on "any key").
## Listens to: Game.phase_changed, message, boss_started / boss_ended, labor_card, hero_died, lock_changed,
## paused_changed. Reads Game.hero (hp, max_hp, stamina, max_stamina, interact_target, alive, outfit).
## Sounds it plays: ui_* (menus, lock-on, toasts, the card), stinger_death with the death screen. The victory
## stinger is main.victory()'s.
##
## Debug: `uitest=title|hud|boss|wrestle|card|death|victory|pause|options|controls|warning|card2` forces a screen for
## screenshots (the game is started when the screen needs it); `pad=1` shows gamepad glyphs;
## `uishot=<file.png>` saves the window after `uishotf` frames (default 90) and quits;
## `uitour=<dir>` captures every screen in one run as <dir>/live_<screen>.png (`uitouronly=hud,card` for some).
## The title also swallows key / pad-button presses that are not menu input, so main.gd's "press any key" start
## cannot skip its menu (owns_title()).

const S := preload("res://scripts/ui/style.gd")
const G := preload("res://scripts/ui/glyphs.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const PromptScript := preload("res://scripts/ui/prompt.gd")
const BannersScript := preload("res://scripts/ui/banners.gd")
const CardsScript := preload("res://scripts/ui/cards.gd")
const MenusScript := preload("res://scripts/ui/menus.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform float vignette = 0.2;
uniform float hurt = 0.0;
uniform float aspect = 1.7778;
uniform vec4 ink : source_color = vec4(0.075, 0.052, 0.042, 1.0);
uniform vec4 blood : source_color = vec4(0.55, 0.08, 0.05, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= mix(1.0, aspect, 0.3);
	float d = length(p);
	float v = smoothstep(0.75, 1.8, d) * vignette;
	float h = smoothstep(0.45, 1.45, d) * hurt;
	float a = clamp(v + h * 0.8, 0.0, 0.9);
	vec3 col = mix(ink.rgb, blood.rgb, clamp(h / max(v + h, 0.0001), 0.0, 1.0));
	COLOR = vec4(col, a);
}
"""

var hud: Control
var prompt: Control
var banners: Control
var cards: Control
var menus: Control
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _flash: ColorRect
var _flash_t := 0.0
var _flash_dur := 0.0
var _flash_col := Color.WHITE
var _hurt := 0.0
var _last_hp := -1.0
var _starting := false
var _modal := false
var _shot_frames := -1
var _debug_death := false
var _victory_shown := false
## The labour card shows by itself the first time the hero walks into the Lion's arena (within arena_radius + 4 m of
## World.cave().arena_center, inside the cave by the world's cave_amount(pos) when it has one: not at a mouth, where it
## would hide the boulder being hauled into mouth B), unless Game.labor_card(1, ...) came first. Off: only
## Game.labor_card shows it.
var auto_labor_card := true
var _labors_shown := {}
var _cave_check := 0.0


class MockBoss extends Node:
	var hp := 64.0
	var max_hp := 100.0
	var display_name := "El León de Nemea"

	func is_alive() -> bool:
		return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -10
	if "hud" in Game:
		Game.hud = self # screen_flash() for Fx (a reload replaces the previous UI, so always take it over)
	if Game.arg("pad", "0") == "1":
		G.set_device("pad")
	_setup_menu_input()
	_build()
	_connect("phase_changed", _on_phase)
	_connect("message", _on_message)
	_connect("labor_card", _on_labor_card)
	_connect("hero_died", _on_hero_died)
	_connect("paused_changed", _on_paused_changed)
	_connect("boss_ended", _on_boss_ended)
	var mode := String(Game.arg("uitest", ""))
	if String(Game.arg("uitour", "")) != "":
		_tour.call_deferred(String(Game.arg("uitour")))
	elif mode != "":
		_debug.call_deferred(mode)
	if String(Game.arg("uishot", "")) != "":
		_shot_frames = int(Game.arg("uishotf", "90"))
	_on_phase(int(Game.phase))


func _exit_tree() -> void:
	if "hud" in Game and Game.hud == self:
		Game.hud = null


func _connect(sig: String, c: Callable) -> void:
	if Game.has_signal(sig) and not Game.is_connected(sig, c):
		Game.connect(sig, c)


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


func _layer(n: String, order: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = n
	l.layer = order
	add_child(l)
	return l


func _build() -> void:
	var fx_layer := _layer("ScreenFx", 50)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vignette.material = _vig_mat
	fx_layer.add_child(_vignette)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	fx_layer.add_child(_flash)
	var world := _layer("WorldUI", 52)
	prompt = PromptScript.new()
	world.add_child(prompt)
	var hl := _layer("HUD", 54)
	hud = HudScript.new()
	hl.add_child(hud)
	prompt.set("hud", hud)
	banners = BannersScript.new()
	banners.set("hud", hud)
	hl.add_child(banners)
	var cl := _layer("Cards", 57)
	cards = CardsScript.new()
	cl.add_child(cards)
	var ml := _layer("Menus", 60)
	menus = MenusScript.new()
	menus.ui = self
	ml.add_child(menus)


# --- API used by the game ----------------------------------------------------------------------------------

func owns_title() -> bool:
	return true


func show_title() -> void:
	hud.call("show_hud", false)
	banners.call("clear")
	menus.call("open_title")


func show_play() -> void:
	if menus.call("is_title_open"):
		menus.call("close_all")
	_starting = false
	_victory_shown = false
	_last_hp = -1.0
	_refresh_visibility()


func show_pause(on: bool) -> void:
	if on:
		if not menus.call("is_pause_open"):
			S.sfx("ui_select")
			menus.call("open_pause")
	elif menus.call("is_pause_open"):
		menus.call("close_all")
		S.sfx("ui_back")
	_refresh_visibility()


func show_labor_card(index: int, title: String) -> void:
	_labors_shown[index] = true
	cards.call("show_labor", index, title)


## Game.labor_card: each labour's card once per run (the cave entry may have shown it already).
func _on_labor_card(index: int, title: String) -> void:
	if not _labors_shown.has(index):
		show_labor_card(index, title)


## Labour I's card on entering the cave (once per run), for as long as nothing emits Game.labor_card for it.
func _check_cave_entry(rd: float) -> void:
	_cave_check -= rd
	if _cave_check > 0.0 or not auto_labor_card or _labors_shown.has(1) or not _gameplay():
		return
	_cave_check = 0.3
	var h = Game.hero
	var w = Game.world
	if h == null or w == null or not is_instance_valid(h) or not is_instance_valid(w) or not (h is Node3D):
		return
	# not while his hands are full (hauling the boulder into mouth B's crack, a wrestle): the card waits
	if h.has_method("state_name") and not (StringName(h.call("state_name")) in [&"move", &"attack", &"dodge"]):
		return
	var p: Vector3 = (h as Node3D).global_position
	var inside := false
	if w.has_method("cave_amount"):
		inside = float(w.call("cave_amount", p)) > 0.5
	# (merge) in the lion's arena itself, not at a mouth: the card would cover the boulder being hauled into mouth B
	if w.has_method("cave"):
		var c: Dictionary = w.call("cave")
		if c.has("arena_center") and c["arena_center"] is Vector3:
			var r := float(c.get("arena_radius", 13.5)) + 4.0
			var near := p.distance_to(c["arena_center"]) < r
			inside = near and (inside or not w.has_method("cave_amount"))
	if inside:
		show_labor_card(1, "El León de Nemea")


func show_victory(index: int = 1, title: String = "La piel del León", sub: String = "Las armas cortantes apenas te hieren") -> void:
	_victory_shown = true
	cards.call("show_victory", index, title, sub)


func screen_flash(col: Color, dur: float) -> void:
	_flash_col = col
	_flash_dur = maxf(0.05, dur)
	_flash_t = _flash_dur
	_flash.visible = true


func hurt_flash(amount: float) -> void:
	_hurt = maxf(_hurt, clampf(0.32 + amount * 2.6, 0.32, 1.0))


# --- flow --------------------------------------------------------------------------------------------------

## Title "Comenzar".
func begin_game() -> void:
	if _starting:
		return
	_starting = true
	menus.call("close_all")
	await get_tree().create_timer(0.25, true, false, true).timeout
	_starting = false
	if Game.phase == Game.Phase.TITLE and Game.main and Game.main.has_method("start_game"):
		Game.main.call("start_game")


## Pause "Continuar" (and B on the pad).
func resume() -> void:
	if Game.has_method("set_paused"):
		Game.call("set_paused", false)
	else:
		get_tree().paused = false
	show_pause(false)


## Pause "Volver al título": reload the island scene; main.gd shows the title again.
func to_title() -> void:
	for k in ["play", "uitest", "uishot"]:
		Game.args.erase(k)
	if Game.has_method("set_paused"):
		Game.call("set_paused", false)
	get_tree().paused = false
	menus.call("close_all")
	get_tree().reload_current_scene.call_deferred()


func _phase_name() -> String:
	if Game.has_method("phase_name"):
		return String(Game.call("phase_name", int(Game.phase)))
	return str(Game.phase)


func _gameplay() -> bool:
	return _phase_name() == "PLAY"


func _refresh_visibility() -> void:
	var modal: bool = menus.call("is_open")
	var p := _phase_name()
	hud.call("show_hud", (p == "PLAY" or p == "DEAD") and not modal)
	prompt.set("enabled", p == "PLAY" and not modal)


# --- events ------------------------------------------------------------------------------------------------

func _on_phase(_p: int) -> void:
	var p := _phase_name()
	if p != "TITLE" and menus.call("is_title_open"):
		menus.call("close_all")
	if p == "PLAY":
		if not _debug_death:
			cards.call("hide_death")
	elif p == "VICTORY":
		if not _victory_shown:
			_victory_shown = true
			get_tree().create_timer(1.6, true, false, true).timeout.connect(func() -> void:
				cards.call("show_victory", 1, "La piel del León", "Las armas cortantes apenas te hieren"))
	_refresh_visibility()


func _on_message(text: String, sub: String, kind: String) -> void:
	var p := _phase_name()
	if p == "TITLE" or p == "BOOT":
		return
	banners.call("post", text, sub, kind)


func _on_hero_died() -> void:
	cards.call("show_death")


func _on_paused_changed(on: bool) -> void:
	# keep the menu in step if something else paused or unpaused the game
	if not on and menus.call("is_pause_open"):
		menus.call("close_all")
	_refresh_visibility()


func _on_boss_ended(victory: bool) -> void:
	if victory and Game.main and not Game.main.has_method("victory"):
		show_victory()


const MENU_NAV := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_select", "ui_focus_next", "ui_focus_prev"]


func _input(e: InputEvent) -> void:
	G.observe(e)
	if not menus.call("is_open"):
		return
	var is_pause: bool = e.is_action_pressed("pause")
	var cancel: bool = e.is_action_pressed("ui_cancel")
	if not is_pause and not cancel:
		_guard_title(e)
		return
	# A sub-screen (options, controls) goes back one level and keeps the event from main's pause toggle.
	if menus.call("depth") > 1:
		menus.call("back")
		get_viewport().set_input_as_handled()
		return
	# Only the pause screen: the pause key itself is main.gd's (it unpauses and calls show_pause(false));
	# ui_cancel on its own (B on the pad) resumes here.
	if menus.call("is_pause_open") and cancel and not is_pause:
		resume()
		get_viewport().set_input_as_handled()
	elif menus.call("is_title_open"):
		get_viewport().set_input_as_handled() # Esc / B on the title itself: nothing to go back to


## The title is a menu (Comenzar, Controles, Opciones), not "press any key": key and pad-button presses that are
## not menu input stop here, so main.gd's any-key start cannot skip it. Navigating with nothing focused (after a
## click on empty space) focuses the first item instead of falling through.
func _guard_title(e: InputEvent) -> void:
	if not menus.call("is_title_open"):
		return
	if not (e is InputEventKey or e is InputEventJoypadButton) or not e.is_pressed():
		return
	for a: String in MENU_NAV:
		if InputMap.has_action(a) and e.is_action_pressed(a, true):
			if get_viewport().gui_get_focus_owner() == null:
				menus.call("focus_top")
				get_viewport().set_input_as_handled()
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var rd := S.rdelta(delta)
	_check_cave_entry(rd)
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			_save_shot()
	var modal: bool = menus.call("is_open")
	if modal != _modal:
		_modal = modal
		_refresh_visibility()
	banners.modulate.a = move_toward(banners.modulate.a, 0.0 if (modal or cards.call("is_showing")) else 1.0, rd * 6.0)
	prompt.set("dim", maxf(float(banners.call("presence")), 1.0 if cards.call("is_showing") else 0.0))
	# hurt: a red pulse at the edges when hp drops, a slow throb when it is low
	var low := 0.0
	var h = Game.hero
	if h != null and is_instance_valid(h) and "hp" in h:
		var hp := float(h.get("hp"))
		var mx := maxf(1.0, float(h.get("max_hp")))
		if _last_hp >= 0.0 and hp < _last_hp - 0.01:
			hurt_flash((_last_hp - hp) / mx)
		_last_hp = hp
		var ratio := hp / mx
		if ratio < 0.3 and _gameplay() and hp > 0.0:
			low = (0.3 - ratio) / 0.3 * (0.22 + 0.1 * sin(S.now() * 5.0))
	_hurt = maxf(0.0, _hurt - rd * 1.7)
	_vig_mat.set_shader_parameter("vignette", 0.2 if _gameplay() else 0.12)
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
	var m = Game.main
	if mode == "title":
		return
	if Game.phase == Game.Phase.TITLE and m and m.has_method("start_game"):
		menus.call("close_all")
		m.call("start_game")
		await get_tree().process_frame
	var hero = Game.hero
	match mode:
		"hud":
			if hero:
				hero.set("hp", float(hero.get("max_hp")) * 0.64)
				hero.set("stamina", float(hero.get("max_stamina")) * 0.42)
			hud.set("sim_stamina", 0.42)
			hud.set("sim_lock_pos", get_viewport().get_visible_rect().size * Vector2(0.62, 0.42))
			hud.set("sim_chain_pos", get_viewport().get_visible_rect().size * Vector2(0.8, 0.3))
			prompt.set("sim_info", {"title": "Altar de Zeus", "verb": "Rezar", "desc": "Cura y guarda el camino", "progress": -1.0})
			prompt.set("sim_point", get_viewport().get_visible_rect().size * Vector2(0.36, 0.5))
			await get_tree().create_timer(0.4).timeout
			banners.call("post", "Lanza la cadena con {chain}", "Lo pequeño viene a ti; lo grande te lleva a ti", "hint")
		"boss":
			if hero:
				hero.set("hp", float(hero.get("max_hp")) * 0.48)
			var mb := MockBoss.new()
			add_child(mb)
			Game.emit_signal("boss_started", "El León de Nemea", mb)
			hud.set("sim_lock_pos", get_viewport().get_visible_rect().size * Vector2(0.55, 0.4))
			await get_tree().create_timer(0.5).timeout
			banners.call("post", "Su piel no la corta el bronce", "Hazlo chocar contra las columnas", "warning")
		"warning":
			banners.call("post", "Su piel no la corta el bronce", "Hazlo chocar contra las columnas", "warning")
		"wrestle":
			# the wrestle's prompt over the struggle (prompt.gd): a squeeze window open, one squeeze of three done
			prompt.set("sim_info", {"title": "El León de Nemea", "verb": "¡Aprieta!", "desc": "", "progress": 1.0 / 3.0,
				"action": "interact", "accent": "gold"})
			prompt.set("sim_point", get_viewport().get_visible_rect().size * Vector2(0.5, 0.42))
		"card":
			show_labor_card(1, "El León de Nemea")
		"card2":
			show_labor_card(2, "La Hidra de Lerna")
		"victory":
			show_victory()
		"death":
			_debug_death = true
			cards.call("show_death")
		"pause", "options", "controls":
			if Game.has_method("set_paused"):
				Game.call("set_paused", true)
			show_pause(true)
			if mode == "options":
				menus.call("open_options")
			elif mode == "controls":
				menus.call("open_controls")


## Debug `uitour=<dir>`: every screen in one run (one island build), each saved as <dir>/live_<screen>.png once
## its animations have settled (seconds of game time, so `--fixed-fps 10` renders a third of the frames of 30);
## then quits. `hud_pad` is the HUD with gamepad glyphs.
const TOUR := [["title", 2.7], ["hud", 2.7], ["hud_pad", 1.0], ["boss", 1.7], ["wrestle", 1.0], ["card", 2.8], ["victory", 3.0],
	["death", 2.7], ["pause", 0.6], ["options", 0.6], ["controls", 0.6]]


func _tour(dir: String) -> void:
	var only := String(Game.arg("uitouronly", "")).split(",", false)
	for st: Array in TOUR:
		var mode: String = st[0]
		if not only.is_empty() and not only.has(mode):
			continue
		_tour_reset()
		G.set_device("pad" if mode == "hud_pad" else "kb")
		await _debug("hud" if mode == "hud_pad" else mode)
		var waited := 0.0
		while waited < float(st[1]):
			await get_tree().process_frame
			waited += S.rdelta(get_process_delta_time())
		var path := dir.path_join("live_%s.png" % mode)
		if DisplayServer.get_name() != "headless": # no frames are drawn headless (logic test only)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img != null and not img.is_empty():
				img.save_png(path)
		print("UI tour: ", path)
	get_tree().quit()


func _tour_reset() -> void:
	banners.call("clear")
	cards.call("reset")
	hud.call("reset_debug")
	prompt.set("sim_info", {})
	prompt.set("sim_point", Vector2.INF)
	_debug_death = false
	_victory_shown = false
	if menus.call("is_open") and not menus.call("is_title_open"):
		menus.call("close_all")
	for c in get_children():
		if c is MockBoss:
			c.queue_free()


## Debug `uishot=<file.png>`: saves the window as it really is after `uishotf` frames, then quits.
func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(String(Game.arg("uishot")))
	get_tree().quit()
