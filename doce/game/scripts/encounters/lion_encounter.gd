class_name LionEncounter
extends Node
## Trabajo I · El León de Nemea (ENCOUNTERS lane L; docs/ENCOUNTERS.md). main.gd adds it (spawn_boss()) on the
## island. It puts the lion (scripts/enemies/lion.gd) in its den at the back of the cave (World.cave()) and runs the
## fight's flow:
##   IDLE     the lion paces in its den; the hero walking into the arena (or hitting / hooking the lion) wakes it
##   INTRO    labour I's card (Game.labor_card(1, ...): the UI shows it once per run, and maybe already did on the
##            way in) while the lion stalks out of the dark; when the card has rolled up, the roar: Game.boss_started
##            (the boss bar, the boss_lion music) and the fight
##   FIGHT    the lion's own brain (phases, perches, the escape through mouth B when the boulder does not seal it);
##            the rule is said once per run, the first time a blade bounces off it ("Su piel no la corta el bronce")
##   the hero falls: the lion goes back to its den at full health (Game.boss_ended(false)); the boulder stays where
##            it is; he comes back from his altar and the fight starts again (no card the second time)
##   the hero leaves the cave mid-fight: the lion goes back to its den, healed up to the start of its phase
##   VICTORY  the last squeeze: the lion dies (slow motion, lion_death), Game.boss_ended(true); Heracles takes its
##            pelt (hero.don_lion_skin(): rig don_skin, outfit &"lion", blades hurt him 50 % less) while the body
##            fades; main.victory() (stinger, the UI's victory card); then free roam (main.gd: back to PLAY) and the
##            boat to Lerna at the pier sails (world/nemea_boat.gd: the teaser card, then the title).
## Debug: lionbot=<tests> loads tools/lion_bot.gd (see there); liondebug=1 prints the lion's state changes.

signal fight_started
signal fight_reset(full: bool)
signal victory_done

enum F { IDLE, INTRO, FIGHT, RESET, VICTORY, DONE }
const F_NAMES := ["idle", "intro", "fight", "reset", "victory", "done"]

## The hero this far (m) from the arena's centre, inside the cave, wakes the lion.
const WAKE_R := 14.5
## Mid-fight, the hero this far from the centre (out through a tunnel) for LEASH_T s ends the fight; while the lion is
## away (fled through mouth B) only beyond LEASH_AWAY_R (he may follow it out onto the apron and come back).
const LEASH_R := 31.0
const LEASH_AWAY_R := 60.0
const LEASH_T := 3.0
## A fight this long without a stun shows the hint once ("make it hit the stone").
const STUCK_HINT_T := 40.0
## The intro: at least this long between waking the lion and its roar (s, real time); the card waits at most CARD_MAX.
const INTRO_MIN := 2.2
const CARD_MAX := 9.0

var lion: Lion = null
var world = null
var cave := {}
var hero: Hero = null
var state := F.IDLE
var fights := 0
var resets := 0
## The rule ("no bronze cuts its hide") is said once per run.
var rule_said := false
var rule_says := 0
var outcrops: Array = []
var _t := 0.0
var _leash_t := 0.0
var _vt := 0.0
var _victory_step := 0
var _corpse_fade := -1.0
var _boss_on := false
## One-shot hints of this run: the first stun (grab it), a fight going nowhere (the pillars), the first escape.
var _hinted := {}
var _since_stun := 0.0
var _idle_check := 0.0


func _ready() -> void:
	world = Game.world
	if world == null or not world.has_method("cave"):
		queue_free()
		return
	cave = world.call("cave")
	if cave.is_empty():
		queue_free()
		return
	if world.get("cave_builder") != null and world.cave_builder.has_method("perches"):
		outcrops = world.cave_builder.call("perches")
	lion = Lion.new()
	lion.name = "NemeanLion"
	add_child(lion)
	lion.setup(self, cave, outcrops)
	lion.reset_to_den(true)
	lion.blade_bounced.connect(_on_blade_bounced)
	lion.died.connect(_on_lion_died)
	lion.slammed.connect(_on_lion_slammed)
	if Game.arg_on("liondebug"):
		lion.lion_state.connect(func(s: StringName) -> void:
			print("LION state %s hp=%.0f phase=%d t=%.2f" % [s, lion.hp, lion.phase, Time.get_ticks_msec() / 1000.0]))
	Game.hero_died.connect(_on_hero_died)
	if Game.has_arg("lionbot") and ResourceLoader.exists("res://tools/lion_bot.gd"):
		var bot: Node = load("res://tools/lion_bot.gd").new()
		bot.name = "LionBot"
		bot.set("encounter", self)
		add_child(bot)


func state_name() -> String:
	return F_NAMES[state]


## Mouth B is open: the boulder has not been hauled into the crack (the lion can flee that way).
func mouth_b_open() -> bool:
	var b = cave.get("boulder")
	if b == null or not is_instance_valid(b) or not b.has_method("is_blocking") or not cave.has("seal_b"):
		return true
	return not bool(b.call("is_blocking", cave["seal_b"], 1.2))


func _hero() -> Hero:
	if hero == null or not is_instance_valid(hero):
		hero = Game.hero as Hero
	return hero


func _hero_in_arena(r: float) -> bool:
	var h := _hero()
	if h == null or not h.is_alive():
		return false
	var c: Vector3 = cave["arena_center"]
	var p := h.global_position
	if Vector2(p.x - c.x, p.z - c.z).length() > r or absf(p.y - c.y) > 6.0:
		return false
	if world.has_method("cave_amount"):
		return float(world.call("cave_amount", p)) > 0.5
	return true


func _hero_dist() -> float:
	var h := _hero()
	if h == null:
		return INF
	var c: Vector3 = cave["arena_center"]
	return Vector2(h.global_position.x - c.x, h.global_position.z - c.z).length()


## Tests: the fight on now (no intro), the lion placed at `p` facing `yaw` (lion.debug_place).
func debug_fight(p: Vector3, yaw: float, cool: float = 2.5) -> void:
	if state != F.FIGHT:
		state = F.FIGHT
		fights += 1
		_leash_t = 0.0
		if not _boss_on:
			_boss_on = true
			Game.boss_started.emit(lion.display_name, lion)
		fight_started.emit()
	lion.debug_place(p, yaw, cool)


## Tests: back to the start (the lion in its den at full health, the fight off).
func debug_reset() -> void:
	_end_fight(true)


## The lion was hit or hooked before the fight began: no more waiting.
func lion_provoked() -> void:
	if state == F.IDLE:
		_start_intro(true)
	elif state == F.INTRO:
		_start_fight()


func _physics_process(delta: float) -> void:
	var rd := Game.real_delta(delta)
	_t += rd
	match state:
		F.IDLE:
			_idle_check -= rd
			if _idle_check <= 0.0:
				_idle_check = 0.2
				if Game.phase == Game.Phase.PLAY and _hero_in_arena(WAKE_R):
					_start_intro(false)
		F.INTRO:
			_tick_intro()
		F.FIGHT:
			_tick_fight(rd)
		F.VICTORY:
			_tick_victory(rd)


func _start_intro(provoked: bool) -> void:
	state = F.INTRO
	_t = 0.0
	lion.wake(_hero())
	# labour I's card: the UI shows it once per run (it may have shown it already on the way in)
	if fights == 0:
		Game.labor_card.emit(1, "El León de Nemea")
	if provoked:
		_start_fight()


func _card_showing() -> bool:
	var ui = Game.ui
	if ui == null or not is_instance_valid(ui) or not ("cards" in ui):
		return false
	var cards = ui.get("cards")
	return cards != null and is_instance_valid(cards) and cards.has_method("is_showing") and bool(cards.call("is_showing"))


func _tick_intro() -> void:
	var need := INTRO_MIN if fights == 0 else 1.2
	if _t < need:
		return
	if _card_showing() and _t < CARD_MAX:
		return
	_start_fight()


func _start_fight() -> void:
	if state == F.FIGHT:
		return
	state = F.FIGHT
	fights += 1
	_leash_t = 0.0
	_since_stun = 0.0
	lion.begin_fight()
	_boss_on = true
	Game.boss_started.emit(lion.display_name, lion)
	fight_started.emit()


func _tick_fight(rd: float) -> void:
	if not lion.alive:
		return
	# the hero walked out of the cave: the lion keeps its den (healed up to the start of its phase)
	var away := lion.state == Lion.S.AWAY or lion.state == Lion.S.ESCAPE
	var hd := _hero_dist()
	if hd > (LEASH_AWAY_R if away else LEASH_R):
		_leash_t += rd
		# (it goes back to its rock out of his sight: never popping from the arena onto its den in view)
		if _leash_t > LEASH_T and (away or hd > LEASH_R + 14.0 or lion._hidden_from_view()):
			_end_fight(false)
			return
	else:
		_leash_t = 0.0
	# a fight going nowhere: say once how the lion is beaten
	if lion.state != Lion.S.STUNNED and lion.state != Lion.S.GRAPPLED and not away:
		_since_stun += rd
	if _since_stun > STUCK_HINT_T and not _hinted.has("stone") and Game.is_playing() and not _card_showing():
		_hinted["stone"] = true
		Game.say("Que choque contra la piedra", "Esquiva su salto junto a una columna, o tira de él con la cadena", "hint")


## The fight stops without a winner: the hero fell (`full`: the lion back at full health) or left the cave.
func _end_fight(full: bool) -> void:
	if _boss_on:
		_boss_on = false
		Game.boss_ended.emit(false)
	resets += 1
	state = F.IDLE
	lion.reset_to_den(full)
	fight_reset.emit(full)


func _on_hero_died() -> void:
	if state != F.FIGHT and state != F.INTRO:
		return
	state = F.RESET
	# (after a breath: the hero's fall plays out first; the boulder stays where it is)
	get_tree().create_timer(1.4, true, false, true).timeout.connect(func() -> void:
		if state == F.RESET:
			_end_fight(true))


## The lion slammed into stone (or fell off its rock) and lies dazed: the first time in a run, how to wrestle it.
## (Only if he has not grabbed it 1.2 s after it went down: a player who knows needs no toast over the wrestle.)
func _on_lion_slammed(_why: StringName) -> void:
	_since_stun = 0.0
	if _hinted.has("grab") or lion.wrestles_won + lion.wrestles_lost > 0:
		return
	get_tree().create_timer(1.2, false).timeout.connect(func() -> void:
		var h := _hero()
		if _hinted.has("grab") or lion == null or not is_instance_valid(lion) or not lion.is_stunned() or lion.grappled:
			return
		if h != null and h.is_grappling():
			return
		_hinted["grab"] = true
		Game.say("¡Aturdido! Agárralo con {interact}", "Aprieta en el destello · el escudo aguanta sus sacudidas", "hint"))


## The lion breaks off and runs for mouth B (the boulder does not seal it).
func lion_escaping() -> void:
	var first := not _hinted.has("escape")
	_hinted["escape"] = true
	Game.say("¡Huye por la grieta!", "Con la roca en la grieta no habría podido escapar" if first else "", "warning")


func _on_blade_bounced() -> void:
	if rule_said:
		return
	rule_said = true
	rule_says += 1
	Game.say("Su piel no la corta el bronce", "Hazlo chocar contra las columnas", "warning")


# --- victory ---------------------------------------------------------------------------------------------------------

func _on_lion_died(_e: Enemy) -> void:
	state = F.VICTORY
	_vt = 0.0
	_victory_step = 0
	Game.hitstop(0.16)
	Game.slowmo(0.3, 1.6)
	Game.shake(0.6)
	Sfx.play("lion_death", lion.lock_point(), 2.0)
	if Game.fx:
		Game.fx.call("impact", lion.lock_point(), Vector3.UP, 1.6, Color(1.0, 0.9, 0.65))
	var h := _hero()
	if h:
		h.input_enabled = false


func _tick_victory(rd: float) -> void:
	_vt += rd
	var h := _hero()
	match _victory_step:
		0:
			if _vt >= 1.8:
				_victory_step = 1
				if _boss_on:
					_boss_on = false
					Game.boss_ended.emit(true)
		1:
			# the pelt: once the lion lies on its side and he stands free (not in the wrestle's last stagger); after
			# 6 s whatever he is doing
			var ready := h != null and h.is_alive() and h.state == Hero.St.MOVE and _lion_down()
			if _vt >= 2.4 and h != null and h.is_alive() and (ready or _vt >= 6.0):
				_victory_step = 2
				var late := h.state != Hero.St.MOVE
				_vt = 0.0
				var to := Combat.flat(lion.global_position - h.global_position)
				if to.length() > 0.1:
					h.facing = atan2(-to.x, -to.z)
				h.don_lion_skin()
				# (no time for the gesture: an action of his would cut the rig's don_skin short, outfit and all)
				if late and h.rig:
					h.rig.set_outfit(&"lion")
		2:
			# the body fades once the pelt is on his shoulders (RigHeracles.DON_SWAP)
			if _vt >= RigHeracles.DON_SWAP and _corpse_fade < 0.0:
				_corpse_fade = 0.0
			if _vt >= 2.5:
				_victory_step = 3
				if h:
					h.input_enabled = true
				if Game.main and Game.main.has_method("victory"):
					Game.main.call("victory")
				victory_done.emit()
				state = F.DONE
	if _corpse_fade >= 0.0 and lion != null and is_instance_valid(lion):
		_corpse_fade = minf(1.0, _corpse_fade + rd / 1.4)
		if lion.rig and lion.rig.has_method("set_dissolve"):
			lion.rig.call("set_dissolve", _corpse_fade)
		if Game.fx and Engine.get_process_frames() % 6 == 0:
			Game.fx.call("motes", lion.global_position + Vector3(randf_range(-1.0, 1.0), 0.6, randf_range(-1.0, 1.0)), 2, Color(1.0, 0.85, 0.5))
		if _corpse_fade >= 1.0:
			lion.queue_free()
			_corpse_fade = -1.0


## The lion's death fall has played out (the pelt is taken from a body lying on its side, never a standing one).
func _lion_down() -> bool:
	if lion == null or not is_instance_valid(lion) or lion.rig == null:
		return true
	return String(lion.rig.get("action")) != "death"


func _process(_delta: float) -> void:
	# (the corpse keeps fading after the victory hands over to main)
	if state == F.DONE and _corpse_fade >= 0.0:
		_tick_victory(Game.real_delta(_delta))
