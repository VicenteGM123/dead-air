extends "res://scripts/main.gd"
## Integration test (integrator, not shipped): the title / pause flow through main.gd's real InputGate with the
## real UI, and the HUD's reactions to the Game signals. Prints "UIFLOW PASS|FAIL <check>" and a summary.

var fails := 0


func _ready() -> void:
	super._ready()
	_run.call_deferred()


func _check(what: String, ok: bool, info: String = "") -> void:
	print("UIFLOW %s %s %s" % ["PASS" if ok else "FAIL", what, info])
	if not ok:
		fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _key(k: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(k: Key) -> void:
	_key(k, true)
	await _wait(0.05)
	_key(k, false)
	await _wait(0.05)


func _click(p: Vector2) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = p
	m.global_position = p
	m.pressed = true
	Input.parse_input_event(m)
	await _wait(0.05)
	var m2 := m.duplicate() as InputEventMouseButton
	m2.pressed = false
	Input.parse_input_event(m2)
	await _wait(0.05)


func _touch(p: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = p
	t.pressed = true
	Input.parse_input_event(t)
	await _wait(0.05)
	var t2 := t.duplicate() as InputEventScreenTouch
	t2.pressed = false
	Input.parse_input_event(t2)
	await _wait(0.05)


func _run() -> void:
	await _wait(1.0)
	# Input events are in window pixels (the canvas is stretched from 1280x720 to the window).
	var ws := Vector2(DisplayServer.window_get_size())
	var empty := Vector2(ws.x * 0.85, ws.y * 0.12)
	_check("boot -> title", Game.phase == Game.Phase.TITLE, Game.phase_name())
	_check("title menu open", bool(ui.menus.call("is_title_open")))
	await _tap(KEY_X)
	await _wait(0.3)
	_check("a random key keeps the title menu", Game.phase == Game.Phase.TITLE, Game.phase_name())
	await _click(empty)
	await _wait(0.3)
	_check("a click on empty space keeps the title menu", Game.phase == Game.Phase.TITLE, Game.phase_name())
	await _touch(empty)
	await _wait(0.3)
	_check("a touch on empty space keeps the title menu", Game.phase == Game.Phase.TITLE, Game.phase_name())
	await _tap(KEY_ENTER)
	await _wait(1.0)
	_check("Enter on Comenzar -> PLAY (show_play)", Game.phase == Game.Phase.PLAY, Game.phase_name())
	_check("title menu closed in play", not bool(ui.menus.call("is_open")))
	await _wait(0.5)
	_check("HUD visible in play", float(ui.hud.modulate.a) > 0.5, "a=%.2f" % ui.hud.modulate.a)
	# pause through main.gd's gate (Esc = pause): show_pause(true) / show_pause(false)
	await _tap(KEY_ESCAPE)
	await _wait(0.4)
	_check("Esc pauses (Game.paused)", Game.paused)
	_check("pause menu open (show_pause)", bool(ui.menus.call("is_pause_open")))
	await _tap(KEY_ESCAPE)
	await _wait(0.4)
	_check("Esc again resumes", not Game.paused and not bool(ui.menus.call("is_open")))
	# HUD reads hero hp / stamina
	hero.hp = hero.max_hp * 0.5
	hero.stamina = hero.max_stamina * 0.3
	await _wait(1.2)
	var vit = ui.hud.get("_vitals")
	_check("HUD health follows hero.hp", absf(float(vit.get("hp")) - 0.5) < 0.05, "hud hp=%.2f" % float(vit.get("hp")))
	var real_st: float = hero.stamina / hero.max_stamina
	_check("HUD stamina follows hero.stamina", absf(float(ui.hud.get("_stam_val")) - real_st) < 0.08, "hud stam=%.2f hero=%.2f" % [float(ui.hud.get("_stam_val")), real_st])
	# lock_changed
	var target := Node3D.new()
	add_child(target)
	target.global_position = hero.global_position + Vector3(0, 1, -6)
	Game.lock_changed.emit(target)
	await _wait(0.2)
	_check("lock_changed(target) -> reticle target", ui.hud.get("_lock") == target)
	Game.lock_changed.emit(null)
	await _wait(0.2)
	_check("lock_changed(null) -> no reticle", ui.hud.get("_lock") == null)
	# boss_started / boss_ended
	var boss := Node.new()
	boss.set_script(null)
	add_child(boss)
	Game.boss_started.emit("El León de Nemea", boss)
	await _wait(0.3)
	_check("boss_started -> boss bar", bool(ui.hud.call("boss_active")))
	Game.boss_ended.emit(false)
	await _wait(1.5)
	_check("boss_ended -> boss bar gone", not bool(ui.hud.call("boss_active")))
	# message
	Game.say("Altar de Zeus", "Cura y guarda el camino", "altar")
	await _wait(0.5)
	var toasts: Node = ui.banners.get("_toasts")
	_check("message -> banner or toast", float(ui.banners.call("presence")) > 0.0 or toasts.get_child_count() > 0, "presence=%.2f toasts=%d" % [float(ui.banners.call("presence")), toasts.get_child_count()])
	# labor_card
	Game.labor_card.emit(2, "La Hidra de Lerna")
	await _wait(0.5)
	_check("labor_card -> frieze card", bool(ui.cards.call("is_showing")) and String(ui.cards.get("mode")) == "labor")
	ui.cards.call("reset")
	# hero_died -> death card (main.gd moves to DEAD and respawns after 3 s)
	Game.hero_died.emit()
	await _wait(0.6)
	_check("hero_died -> death card", float(ui.cards.get("_death")) > 0.0 or bool(ui.cards.get("_death_on")), "phase=%s" % Game.phase_name())
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_process_frames()
	while Game.phase != Game.Phase.PLAY and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	print("UIFLOW info respawn after %.1f s real, %d frames, time_scale %.2f paused %s" % [(Time.get_ticks_msec() - t0) / 1000.0, Engine.get_process_frames() - f0, Engine.time_scale, str(get_tree().paused)])
	await _wait(0.5)
	_check("respawn -> PLAY again, death card hidden", Game.phase == Game.Phase.PLAY and not bool(ui.cards.get("_death_on")), Game.phase_name())
	print("UIFLOW SUMMARY fails=%d" % fails)
	get_tree().quit()
