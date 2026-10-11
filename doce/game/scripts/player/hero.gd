class_name Hero
extends CharacterBody3D
## Heracles (CORE): movement, combat, the chain spear, the wrestle. docs/COMBAT.md has every number and contract.
##
## State machine (`state`, St.*):
##   MOVE     free locomotion on the ground / in the air / swimming; guard (hold), sprint, jump, interact
##   ATTACK   a light blow of the 3-hit combo (HeroMelee): wind-up, active frames (blade sweep), recovery
##   CHARGE   attack held: the heavy blow winds up (slow walk); released charged -> HEAVY, early -> a light blow
##   HEAVY    the charged spin slash
##   DODGE    roll (with a direction) or backstep (without): i-frames, stamina
##   STAGGER  hit reactions, guard break, a deflected blade's recoil, the end of a wrestle
##   THROW    the chain spear's throw until the rig's "release" event
##   CHAIN    the spear is stuck in something and works: zip (ring), pulled to (heavy), yank (light), brace and
##            yank (beast), haul (boulder), hop over a ledge after a zip
##   HANG     hanging from a bronze ring with no ledge to climb (throw to the next ring, jump or dodge to drop)
##   GRAPPLE  wrestling a stunned beast (the target drives the rhythm: grapple_cue / grapple_thrash / release)
##   DEAD
## Movement (first pass kept from the skeleton): camera-relative, walk / run / sprint, jump with coyote time and a
## buffer, slopes, step-ups, wading and swimming. Locked on (CameraRig.lock_target) the hero faces the target and
## strafes round it; guarding he faces where the camera looks.
## Physics: hero layer 2, capsule 1.8 x 0.36 with its origin at the feet; collides with world, enemies, movables.
## The visual (`rig`, RigHeracles, top level) is drawn interpolated between physics ticks.

signal interact_target_changed(target: Node)
signal hurt(hit: Dictionary)
signal died
signal landed(fall_speed: float)
## The anchor the chain spear would hit now (UI highlight), or null.
signal chain_candidate_changed(target: Node)
## A blow of the hero hurt `target`.
signal blow_landed(target: Node, hit: Dictionary)
signal parried(attacker: Node)
signal guard_broken
signal perfect_dodge
signal state_changed(state_name: StringName)


# --- movement ----------------------------------------------------------------------------------------------
const WALK_SPEED := 2.2
const RUN_SPEED := 6.2
const SPRINT_SPEED := 9.0
const LOCK_RUN_SPEED := 5.0
const GUARD_SPEED := 2.6
const CHARGE_SPEED := 1.5
const HAUL_SPEED := 2.0
const SWIM_SPEED := 2.8
const SWIM_SPRINT_SPEED := 4.2
const ACCEL := 40.0
const DECEL := 48.0
const AIR_ACCEL := 11.0
const TURN_RATE := 13.0 # rad/s while running; quicker standing still
const GRAVITY := 24.0
const FALL_MULT := 1.55
const MAX_FALL := 45.0
const JUMP_SPEED := 8.0
const JUMP_CUT := 0.45
const COYOTE := 0.12
const JUMP_BUFFER := 0.14
const STEP_HEIGHT := 0.42
const HARD_LANDING := 13.0
## Water depth (m) where the hero starts swimming, and how deep the feet hang while swimming.
const SWIM_DEPTH := 1.3
const SWIM_FLOAT := 1.2
const CAPSULE_R := 0.36
const CAPSULE_H := 1.8

# --- defence and stamina -------------------------------------------------------------------------------------
## Out of a fight, a press of Shift / B shorter than this rolls (on the release), longer sprints. In a fight (locked
## on, or the camera's combat weight past 0.5: foes within 11 m) the roll starts on the press; holding on through
## the roll then sprints.
const DODGE_TAP := 0.15
const ROLL_TIME := 0.55
const ROLL_DIST := 4.0
const ROLL_IFRAMES := Vector2(0.05, 0.35)
## The roll's displacement against its rig time (RigHeracles "dodge", 0.62 s authored): the crouch, the tumble
## (the 360 degrees end at 0.45) and the rise; metres as a fraction of ROLL_DIST, eased between the keys.
const ROLL_PATH := [Vector2(0.0, 0.0), Vector2(0.08, 0.0625), Vector2(0.45, 0.9), Vector2(0.55, 1.0)]
const BACKSTEP_TIME := 0.42
const BACKSTEP_DIST := 2.2
const BACKSTEP_IFRAMES := Vector2(0.03, 0.24)
const DODGE_COST := 22.0
const SPRINT_COST := 16.0 # stamina per second
const HEAVY_COST := 22.0
const STAMINA_REGEN := 34.0
const STAMINA_DELAY := 0.7
## Exhausted (stamina hit 0): no sprint, roll or heavy blow until stamina is back to this fraction.
const EXHAUST_RECOVER := 0.35
const GUARD_ARC := 70.0 # degrees either side of the facing the shield covers
const PARRY_WINDOW := 0.18
const PARRY_REARM := 0.4 # a new parry window opens only this long after the last one
const BLOCK_COST := 6.0
const BLOCK_COST_K := 0.9 # + this per point of damage
const HIT_INVULN := 0.35
## Input buffers (s): how long a press waits for the state that can use it. They run down only while the hero
## is free (MOVE...); while a blow, a roll, a throw, the chain or a stagger runs out on its own they wait (a press
## is never lost to a long recovery), up to BUF_CAP s after the press.
const BUF_ATTACK := 0.3
const BUF_CHAIN := 0.25
const BUF_DODGE := 0.25
const BUF_CAP := 0.6
const BUF_CAP_DODGE := 0.45

# --- the chain spear ---------------------------------------------------------------------------------------
const THROW_SPEED := 1.75 # rig speed of the throw: the spear leaves the hand 0.27 s after the press
const ZIP_SPEED := 20.0
const ZIP_ACCEL := 70.0
## A beat of tension (s) between the bite and the zip.
const ZIP_TENSION := 0.05
const HANG_MAX := 6.0
## Walkable ground at most this far under where he would hang from a ring: the zip lands him on it instead.
const ZIP_LAND_DROP := 1.9
## A ring under a walkable lip (a ledge): the zip ends with his feet MANTLE_DROP m under the lip and his body's axis
## MANTLE_STANDOFF m out from the wall, then he climbs up and over (rig "climb", MANTLE_TIME s): both hands on the
## lip at 0.12 s, the press with the chest over the edge at 0.3 s, a knee up, standing on the top at 0.5 s.
const MANTLE_DROP := 1.15
const MANTLE_STANDOFF := 0.45
const MANTLE_TIME := 0.5
## The body's rise (m, the last key = MANTLE_DROP) against the climb's time (s); forward over the edge from 0.36 s.
const MANTLE_RISE := [Vector2(0.0, 0.0), Vector2(0.12, 0.1), Vector2(0.3, 0.8), Vector2(0.4, 1.17), Vector2(0.5, 1.15)]
const MANTLE_OVER := Vector2(0.36, 0.5)
## On a zip to a ledge he lets go of the chain when his feet are this far under the ring (his hand level with it).
const MANTLE_LET_GO := 1.5
## The left fist relative to the rig origin while hanging (rig space): the hero hangs so the fist is on the ring.
const HANG_HAND := RigHeracles.HANG_GRIP
const HAUL_MIN := 2.8
const HAUL_REEL := 0.9 # m/s the chain shortens while the button is held
const GRAPPLE_RANGE := 3.0
## threat(): foes telegraphing within this range (m) and this angle of the view (degrees), held this long (s).
const THREAT_RANGE := 7.0
const THREAT_VIEW := 110.0
const THREAT_HOLD := 0.8

enum St { MOVE, ATTACK, CHARGE, HEAVY, DODGE, STAGGER, THROW, CHAIN, HANG, GRAPPLE, DEAD }
const ST_NAMES: Array[StringName] = [&"move", &"attack", &"charge", &"heavy", &"dodge", &"stagger", &"throw", &"chain", &"hang", &"grapple", &"dead"]

# --- contract fields -----------------------------------------------------------------------------------------
var team := 0
var max_hp := 100.0
var hp := 100.0
var max_stamina := 100.0
var stamina := 100.0
var interact_target: Node = null
var alive := true
## Stamina ran out: no sprint, roll or heavy blow until it is back to EXHAUST_RECOVER (the UI reads it).
var exhausted := false
## &"helmet" or &"lion" (the lion's pelt: blades hurt 40 % less).
var outfit: StringName = &"helmet"

# --- state -----------------------------------------------------------------------------------------------------
var input_enabled := true
var rig: RigHeracles
## Yaw the hero faces (model forward = -Z rotated by facing).
var facing := 0.0
## &"ground", &"air", &"swim", &"zip" or &"hang" (fed to the rig).
var motion_state: StringName = &"ground"
var sprinting := false
var dodging := false
var guarding := false
var invulnerable := 0.0
## Debug / test input: when non-zero it replaces the stick (x right, y back), e.g. the arena bot.
var debug_move := Vector2.ZERO
var state := St.MOVE
var state_t := 0.0
var inp := HeroInput.new()
var melee: HeroMelee
var spear: ChainSpear
## The anchor the spear would fly to now (see chain_candidate_changed).
var chain_candidate: Node3D = null
## Chain mode while state == CHAIN: &"zip", &"to", &"hop", &"yank", &"beast", &"haul".
var chain_mode: StringName = &""
## The wrestled beast while state == GRAPPLE.
var grapple_target: Node3D = null

var _coyote := 0.0
var _jump_buf := 0.0
var _jump_held := false
var _air_time := 0.0
var _fall_speed := 0.0
var _land_lock := 0.0
var _iframes := 0.0
var _dodge_t := 0.0
var _dodge_len := ROLL_TIME
var _dodge_dist := ROLL_DIST
var _dodge_if := ROLL_IFRAMES
var _dodge_dir := Vector3.ZERO
var _dodge_rewarded := false
## The dodge is a roll (ROLL_PATH), not a backstep.
var _dodge_roll := false
var _buf_dodge := 0.0
var _buf_chain := 0.0
var _buf_attack := 0.0
## Seconds since the press each buffer holds (the BUF_CAP limit while busy).
var _buf_dodge_age := 0.0
var _buf_chain_age := 0.0
var _buf_attack_age := 0.0
## The current press of Shift / B already rolled (combat: roll on press): its release rolls no more, and the
## sprint waits until it has been held through the roll.
var _dodge_on_press := false
var _sprint_toggle := false
var _stamina_wait := 0.0
var _interacting := false
var _parry_open := 0.0
var _parry_last := -9.0
## When (_clock) guard was last pressed: a shield raised by a cancel within PARRY_WINDOW of it still parries.
var _guard_press := -9.0
## Game seconds since the hero spawned (parry re-arm, ...).
var _clock := 0.0
var _stagger_t := 0.0
var _stagger_len := 0.0
var _kb := Vector3.ZERO
## The knockback added to velocity in the last _locomote (taken back out of it the next tick).
var _kb_last := Vector3.ZERO
var _kb_tick := -10
var _throw_target: Node3D = null
var _throw_aim := Vector3.ZERO
var _throw_released := false
var _throw_rel_t := 0.0
## Thrown from a ring: the hero keeps his grip (no fall) until the new throw bites or misses.
var _throw_hang := false
var _anchor: Node3D = null
var _zip_from := Vector3.ZERO
var _zip_ctrl := Vector3.ZERO
var _zip_end := Vector3.ZERO
var _zip_len := 1.0
var _zip_u := 0.0
var _zip_speed := 0.0
var _zip_delay := 0.0
var _zip_stuck := 0
var _zip_ledge := Vector3.INF
## The zip ends on the ground at the foot of the ring's stone (see ZIP_LAND_DROP).
var _zip_land := false
## The ledge climb (chain_mode &"climb"): from, to (on the top), the way in (horizontal), its length, its clock, and
## whether the spear has been let go (the hands are on the lip).
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_in := Vector3.FORWARD
var _mantle_dist := 0.0
var _mantle_t := 0.0
var _mantle_free := false
var _zip_strike := false
var _pull_fired := false
var _pull_fire_t := 0.0
var _haul_len := 0.0
var _haul_grace := 0.0
var _hang_pos := Vector3.ZERO
var _cue_left := 0.0
var _grapple_xf := Transform3D.IDENTITY
## The sword and the shield laid on the ground during a wrestle (_lay_weapons), or null.
var _aside: Node3D = null
## Seconds left of the don_skin action (the weapons come back when it ends).
var _don_left := 0.0
var _grap_scan := 0.0
var _grap_cand: Node3D = null
var _cand_t := 0.0
var _threat: Node3D = null
var _threat_until := -1.0
var _threat_scan := -1.0
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _vis_yaw := 0.0
var _step_t := 0.0
var _ripple_t := 0.0
var _world = null
var _cam_sprint := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	max_slides = 6
	add_to_group("hero")
	add_to_group("damageable")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_R
	cap.height = CAPSULE_H
	cs.shape = cap
	cs.position = Vector3(0, CAPSULE_H * 0.5, 0)
	add_child(cs)
	rig = RigHeracles.new()
	rig.name = "Rig"
	add_child(rig)
	rig.top_level = true
	rig.event.connect(_on_rig_event)
	melee = HeroMelee.new(self)
	spear = ChainSpear.new()
	spear.name = "ChainSpear"
	spear.hero = self
	add_child(spear)
	_curr_pos = global_position
	_prev_pos = _curr_pos


## Places the hero (start, respawn) without interpolating the jump; resets motion and every action.
func teleport(xf: Transform3D) -> void:
	global_position = xf.origin
	var f := -xf.basis.z
	facing = atan2(-f.x, -f.z)
	_vis_yaw = facing
	velocity = Vector3.ZERO
	_kb = Vector3.ZERO
	_prev_pos = xf.origin
	_curr_pos = xf.origin
	motion_state = &"ground"
	_end_actions()
	_set_state(St.MOVE)
	_sync_visual(1.0)
	rig.reset_cloth()


## Where the hero is drawn this frame (interpolated); the camera follows this.
func visual_position() -> Vector3:
	return _prev_pos.lerp(_curr_pos, Engine.get_physics_interpolation_fraction())


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func is_alive() -> bool:
	return alive


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	stamina = max_stamina
	exhausted = false


## Back on its feet at `xf` with full health (respawn at an altar).
func revive(xf: Transform3D) -> void:
	alive = true
	hp = max_hp
	stamina = max_stamina
	exhausted = false
	invulnerable = 1.5
	dodging = false
	teleport(xf)
	rig.stop_action(0.0)


## The current state's name (&"move", &"attack", ...).
func state_name() -> StringName:
	return ST_NAMES[state]


## The camera's lock-on target when it is valid, else null.
func lock_target() -> Node3D:
	if Game.camera == null or not is_instance_valid(Game.camera):
		return null
	var t: Node3D = Game.camera.lock_target
	return t if Combat.is_alive(t) else null


## What the camera keeps in view beside the hero when not locked on (CameraRig): the foe being wrestled, the
## boulder on the chain, the foe or beast being yanked, the cat he strokes, the foe the sword is busy with
## (HeroMelee.focus_target: aimed at or hit in the last 1.6 s), else a foe winding up a blow at him (threat());
## null otherwise.
func camera_interest() -> Node3D:
	if state == St.GRAPPLE and Combat.is_alive(grapple_target):
		return grapple_target
	if state == St.CHAIN and (chain_mode == &"haul" or chain_mode == &"yank" or chain_mode == &"beast") and Combat.is_alive(_anchor):
		return _anchor
	if state == St.DEAD or state == St.HANG or motion_state == &"swim":
		return null
	# stroking a cat (interact held, the rig's "pet"): the view turns to show the cat beside him, not his back
	if _interacting and interact_target is Node3D and is_instance_valid(interact_target) and rig.action == "pet":
		return interact_target as Node3D
	var mt := melee.focus_target()
	if mt != null:
		return mt
	return threat()


## A foe within THREAT_RANGE telegraphing a blow (Enemy.telegraph_t > 0), kept for THREAT_HOLD s after its wind-up
## so the camera holds it through the strike; only foes within THREAT_VIEW degrees of the view's forward (the
## camera turns to show an attack it can almost see, never swings round to one behind the hero: sound and the
## telegraph glint warn of those). Refreshed every 0.1 s.
func threat() -> Node3D:
	if _clock - _threat_scan >= 0.1:
		_threat_scan = _clock
		var best: Node3D = null
		var best_d := THREAT_RANGE
		var cf := Vector3.ZERO
		if Game.camera and is_instance_valid(Game.camera) and Game.camera.has_method("yaw_basis"):
			cf = -(Game.camera.call("yaw_basis") as Basis).z
		for n in get_tree().get_nodes_in_group("enemy"):
			var e := n as Node3D
			if e == null or not Combat.is_alive(e) or not ("telegraph_t" in e) or float(e.get("telegraph_t")) <= 0.0:
				continue
			var d := Combat.flat(e.global_position - global_position)
			var dist := d.length()
			if dist >= best_d:
				continue
			if cf != Vector3.ZERO and dist > 0.5 and rad_to_deg(cf.angle_to(d)) > THREAT_VIEW:
				continue
			best_d = dist
			best = e
		if best != null:
			_threat = best
			_threat_until = _clock + THREAT_HOLD
	if _threat != null and (_clock > _threat_until or not Combat.is_alive(_threat)):
		_threat = null
	return _threat


## True while rolling or stepping back (the camera does not swing after a dodge).
func is_dodging() -> bool:
	return state == St.DODGE


## Where the chain runs to while the camera gives it its diagonal view (CameraRig): the throw's target (or the
## point aimed at), the flying spear's goal, the ring or anchor he is zipping to; Vector3.INF otherwise (a yank, a
## beast or the boulder are framed as camera_interest()).
func chain_focus() -> Vector3:
	if not alive:
		return Vector3.INF
	if state == St.THROW:
		if Combat.is_alive(_throw_target):
			return _throw_target.call("chain_point")
		return _throw_aim
	if state == St.CHAIN:
		if (chain_mode == &"zip" or chain_mode == &"to") and Combat.is_alive(_anchor):
			return _anchor.call("chain_point")
		return Vector3.INF
	if spear.mode == ChainSpear.FLYING:
		return spear.goal()
	return Vector3.INF


## The foe the raised shield turns to (not locked on): the one winding up a blow at him, else the one he fights.
func _guard_focus() -> Node3D:
	var t := threat()
	if t == null:
		t = melee.focus_target()
	return t


## A light blow now (tests): the next blow of the combo.
func attack() -> void:
	if alive and state in [St.MOVE, St.ATTACK]:
		melee.start_light()


## The lion's pelt: blades hurt 40 % less (the rig plays don_skin and changes the outfit itself). He lays his
## sword and shield down to put it on (the right hand pulls the hood over the helmet) and takes them back after.
func don_lion_skin() -> void:
	outfit = &"lion"
	if rig.has_method("play"):
		_lay_weapons(true)
		_don_left = rig.play("don_skin")


func _set_state(s: int) -> void:
	if s == state:
		state_t = 0.0
		return
	if s != St.THROW:
		_throw_hang = false
	var was := state
	state = s
	state_t = 0.0
	if was == St.DODGE:
		dodging = false
	state_changed.emit(ST_NAMES[s])


## Cancels whatever the hero was doing (attacks, throws, the chain, the wrestle): used by hits, teleports, death.
func _end_actions() -> void:
	melee.abort()
	if state == St.GRAPPLE:
		_end_grapple(false, false)
	if spear.mode != ChainSpear.BACK:
		if state == St.THROW and not _throw_released:
			spear.snap_back()
		else:
			spear.release()
	_anchor = null
	chain_mode = &""
	guarding = false
	dodging = false
	_iframes = 0.0
	rig.set_guard(false)
	rig.charge = 0.0
	if Game.camera and is_instance_valid(Game.camera) and Game.camera.has_method("set_zip"):
		Game.camera.call("set_zip", false)


# --- damage contract -------------------------------------------------------------------------------------------

func take_hit(hit: Dictionary) -> bool:
	if not alive:
		return false
	var amount := float(hit.get("amount", 0.0))
	# a push-only hit (amount 0, knockback > 0: the lion's roar wave) shoves him without hurting
	var shove := amount <= 0.0 and float(hit.get("knockback", 0.0)) > 0.0
	if amount <= 0.0 and not shove:
		return false
	var src := hit.get("source") as Node3D
	# rolling through it
	if _iframes > 0.0:
		hit["dodged"] = true
		_on_dodged(hit)
		return false
	if invulnerable > 0.0:
		return false
	var from := Vector3.ZERO
	if src and is_instance_valid(src):
		from = src.global_position
	else:
		from = global_position - (hit.get("dir", forward()) as Vector3)
	var frontal := Combat.in_front(global_position, forward(), from, GUARD_ARC)
	var guardable := not bool(hit.get("unblockable", false))
	if guarding and frontal and guardable and state == St.MOVE:
		if _parry_open > 0.0 and bool(hit.get("parryable", true)) and not shove:
			hit["parried"] = true
			_parry(hit, src)
			return false
		if shove:
			_shove(hit, true)
			return false
		return _block(hit, amount)
	if shove:
		_shove(hit, false)
		return false
	if outfit == &"lion" and hit.get("kind", &"") == &"blade":
		amount *= 0.6
	_hurt(hit, amount)
	return true


## A push without damage (hit amount 0, knockback > 0): knocked back and briefly off balance (the light flinch,
## no hurt sound, no red flash); on the raised shield only a short slide. Sets hit["shoved"].
func _shove(hit: Dictionary, braced: bool) -> void:
	hit["shoved"] = true
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	dir.y = 0.0
	var push := float(hit.get("knockback", 0.0)) * (0.4 if braced else 1.0)
	if dir.length_squared() > 1e-6:
		_kb = dir.normalized() * push
	if braced:
		rig.guard_impact(0.8)
		Game.shake(0.15)
		return
	_end_actions()
	if motion_state == &"zip" or motion_state == &"hang":
		motion_state = &"air"
	_stagger(maxf(rig.play("hit") * 0.7, float(hit.get("stagger", 0.0))), "shove")
	Game.shake(0.3)


func _hurt(hit: Dictionary, amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	dir.y = 0.0
	var heavy := float(hit.get("stagger", 0.0)) >= 0.5 or amount >= 25.0
	if dir.length_squared() > 1e-6:
		_kb = dir.normalized() * float(hit.get("knockback", 0.0))
	# a strong flash, not a white silhouette: the reaction must still read
	rig.hit_flash(Rig.FLASH_HEAVY if heavy else Rig.FLASH_LIGHT)
	_end_actions()
	if motion_state == &"zip" or motion_state == &"hang":
		motion_state = &"air"
	var react := "hit_heavy" if heavy else "hit"
	var st := rig.play(react) * (0.62 if heavy else 0.7)
	_stagger(st, react)
	# no second blow before he can act again (a pack must not stun-lock him)
	invulnerable = maxf(HIT_INVULN, st + 0.1)
	Game.shake(0.45 if heavy else 0.25)
	Game.hitstop(0.08 if heavy else 0.05)
	if Game.fx:
		Game.fx.call("flash_screen", Color(0.9, 0.15, 0.1, 0.35), 0.18)
	Sfx.play("hero_hurt", global_position, -2.0)
	hurt.emit(hit)
	if hp <= 0.0:
		_die()


## Shield up in front: the blow costs stamina instead of health; with too little stamina the guard breaks.
func _block(hit: Dictionary, amount: float) -> bool:
	hit["blocked"] = true
	var cost := BLOCK_COST + amount * BLOCK_COST_K * (1.4 if float(hit.get("stagger", 0.0)) >= 0.5 else 1.0)
	var at := global_position + Vector3(0, 1.3, 0) + forward() * 0.6
	if Game.fx:
		Game.fx.call("hit_spark", at, forward(), 0.9)
		Game.fx.call("impact", at + Vector3(0, 0.15, 0), forward(), 0.55, Color(1.0, 0.92, 0.75))
	if not bool(hit.get("sound_done", false)):
		Sfx.play("shield_block", at, -1.0, randf_range(0.93, 1.05))
	_stamina_wait = STAMINA_DELAY
	if stamina >= cost and not bool(hit.get("guard_break", false)):
		stamina -= cost
		var dir: Vector3 = hit.get("dir", -forward())
		dir.y = 0.0
		if dir.length_squared() > 1e-6:
			_kb = dir.normalized() * float(hit.get("knockback", 0.0)) * 0.6
		rig.guard_impact(clampf(amount / 18.0, 0.4, 1.3))
		Game.hitstop(0.04)
		Game.shake(0.12)
		return false
	# guard break: stamina gone, half the blow comes through, staggered
	stamina = 0.0
	exhausted = true
	guarding = false
	rig.set_guard(false)
	guard_broken.emit()
	Game.shake(0.35)
	_hurt(hit, amount * 0.5)
	return true


## A perfect parry: no damage, the attacker is thrown open (on_parried), a ring of sparks and a beat of slow motion.
func _parry(_hit: Dictionary, src: Node3D) -> void:
	_parry_open = 0.0
	var at := global_position + Vector3(0, 1.3, 0) + forward() * 0.6
	rig.play_at("parry", 1.0, true)
	Sfx.play("parry", at, 0.0)
	if Game.fx:
		Game.fx.call("impact", at, forward(), 1.3, Color(1.0, 0.95, 0.75))
		Game.fx.call("ring", global_position, 2.2, Color(1.0, 0.9, 0.6, 0.8), 0.35)
	Game.hitstop(0.1)
	Game.slowmo(0.25, 0.12 + 0.1)
	Game.shake(0.2)
	stamina = minf(max_stamina, stamina + 8.0)
	if src and is_instance_valid(src) and src.has_method("on_parried"):
		src.call("on_parried", self)
	parried.emit(src)


## A blow went through the roll's i-frames: the first one per roll is a perfect dodge (a flash of slow motion).
func _on_dodged(_hit: Dictionary) -> void:
	if _dodge_rewarded:
		return
	_dodge_rewarded = true
	Game.slowmo(0.3, 0.28)
	if Game.fx:
		Game.fx.call("ring", global_position, 1.8, Color(0.85, 0.95, 1.0, 0.7), 0.3)
		Game.fx.call("glint", global_position + Vector3(0, 1.2, 0), 1.2, Color(0.9, 0.97, 1.0), 0.25)
	Sfx.play("dodge", global_position, -4.0, 1.35)
	perfect_dodge.emit()


func _die() -> void:
	alive = false
	_end_actions()
	_release_interaction()
	_set_state(St.DEAD)
	rig.play("death")
	# the blow that fells him weighs more than a scratch: a longer freeze, then the fall in slow motion
	Game.hitstop(0.12)
	Game.slowmo(0.35, 0.12 + 0.6)
	Game.shake(0.5)
	Sfx.play("hero_down", global_position)
	died.emit()
	Game.hero_died.emit()


# --- per physics tick ------------------------------------------------------------------------------------------

func _can_act() -> bool:
	return alive and input_enabled and Game.is_playing() and not (Game.camera != null and Game.camera.is_fly())


func _input_vector() -> Vector2:
	if debug_move != Vector2.ZERO:
		return debug_move.limit_length(1.0)
	if not _can_act():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.2)


## Input in world space (XZ), relative to the camera's yaw (which faces the target when locked on); length 0..1.
func _move_dir(iv: Vector2) -> Vector3:
	var b: Basis = Game.camera.yaw_basis() if Game.camera != null else Basis.IDENTITY
	var d := b.x * iv.x + b.z * iv.y
	d.y = 0.0
	return d


func _physics_process(delta: float) -> void:
	_prev_pos = _curr_pos
	_world = Game.world
	inp.sample(_can_act(), delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	_iframes = maxf(0.0, _iframes - delta)
	_land_lock = maxf(0.0, _land_lock - delta)
	_parry_open = maxf(0.0, _parry_open - delta)
	_tick_buffers(delta)
	state_t += delta
	_clock += delta
	if _don_left > 0.0:
		_don_left -= delta
		if _don_left <= 0.0 or rig.action != "don_skin":
			_don_left = 0.0
			_lay_weapons(false)
	if not alive:
		_physics_dead(delta)
		return
	var iv := _input_vector()
	var dir := _move_dir(iv)
	var mag := minf(dir.length(), 1.0)
	_update_buttons(delta, mag)
	_update_water()
	match state:
		St.MOVE:
			_st_move(delta, dir, mag)
		St.ATTACK, St.HEAVY, St.CHARGE:
			_st_melee(delta, dir, mag)
		St.DODGE:
			_st_dodge(delta)
		St.STAGGER:
			_st_stagger(delta)
		St.THROW:
			_st_throw(delta, dir, mag)
		St.CHAIN:
			_st_chain(delta, dir, mag)
		St.HANG:
			_st_hang(delta)
		St.GRAPPLE:
			_st_grapple(delta)
	_update_stamina(delta)
	_update_interaction(delta)
	_update_candidate(delta)
	spear.physics(delta)
	_update_ripples(delta)
	_curr_pos = global_position
	_feed_rig()


func _physics_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
	velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)
	velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	move_and_slide()
	_curr_pos = global_position
	rig.set_locomotion(0.0, RUN_SPEED)


## The states that run out on their own: a press made during them waits (see BUF_CAP).
func _busy() -> bool:
	return state == St.ATTACK or state == St.HEAVY or state == St.CHARGE or state == St.CHAIN or state == St.STAGGER \
		or state == St.THROW or state == St.DODGE


func _tick_buffers(delta: float) -> void:
	_buf_attack_age += delta
	_buf_chain_age += delta
	_buf_dodge_age += delta
	if _busy():
		if _buf_attack_age > BUF_CAP:
			_buf_attack = 0.0
		if _buf_chain_age > BUF_CAP:
			_buf_chain = 0.0
		if _buf_dodge_age > BUF_CAP_DODGE:
			_buf_dodge = 0.0
	else:
		_buf_attack = maxf(0.0, _buf_attack - delta)
		_buf_chain = maxf(0.0, _buf_chain - delta)
		_buf_dodge = maxf(0.0, _buf_dodge - delta)


func _queue_dodge() -> void:
	_buf_dodge = BUF_DODGE
	_buf_dodge_age = 0.0


## In a fight: locked on, or foes close enough for the camera's combat framing.
func _in_fight() -> bool:
	if lock_target() != null:
		return true
	return Game.camera != null and is_instance_valid(Game.camera) and float(Game.camera.get("_combat_k")) > 0.5


## Shift / B (tap: roll, hold: sprint; in a fight the roll starts on the press), guard (and its parry window), and
## the action buffers.
func _update_buttons(delta: float, mag: float) -> void:
	if inp.just_pressed(&"sprint_toggle"):
		_sprint_toggle = true
	if mag < 0.2:
		_sprint_toggle = false
	if inp.just_pressed(&"dodge"):
		_dodge_on_press = false
		if _in_fight():
			# a fight: the roll goes at once (its latency must not be the length of the tap)
			_dodge_on_press = true
			_queue_dodge()
	if inp.just_released(&"dodge"):
		if not _dodge_on_press and inp.hold_time(&"dodge") < DODGE_TAP:
			_queue_dodge()
		_dodge_on_press = false
	if inp.just_pressed(&"chain"):
		_buf_chain = BUF_CHAIN
		_buf_chain_age = 0.0
	if inp.just_pressed(&"attack"):
		_buf_attack = BUF_ATTACK
		_buf_attack_age = 0.0
	# sprint: Shift / B held (after a roll on the press: held on through the roll)
	var hold_need := DODGE_TAP if not _dodge_on_press else ROLL_TIME + DODGE_TAP
	var held := inp.is_held(&"sprint") and inp.hold_time(&"sprint") >= hold_need
	var can_sprint := state == St.MOVE and motion_state == &"ground" and not guarding
	var want := (held or _sprint_toggle) and mag > 0.5 and can_sprint
	if exhausted and stamina >= max_stamina * EXHAUST_RECOVER:
		exhausted = false
	sprinting = want and not exhausted and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - SPRINT_COST * delta)
		_stamina_wait = STAMINA_DELAY
		if stamina <= 0.0:
			exhausted = true
	# guard: up while held in MOVE on the ground; a fresh press opens the parry window, also when the shield only
	# comes up a moment later (a blow's recovery or a roll cancelled into the guard): the window is counted from the
	# press
	if inp.just_pressed(&"guard"):
		_guard_press = _clock
	var can_guard := state == St.MOVE and motion_state == &"ground"
	var g := inp.is_held(&"guard") and can_guard
	if g and not guarding:
		var age := _clock - _guard_press
		if age < PARRY_WINDOW and _guard_press - _parry_last >= PARRY_REARM:
			_parry_open = PARRY_WINDOW - age
			_parry_last = _guard_press
	elif g and inp.just_pressed(&"guard") and _clock - _parry_last >= PARRY_REARM:
		# (pressed again while still up: a fresh window)
		_parry_open = PARRY_WINDOW
		_parry_last = _clock
	if g != guarding:
		guarding = g
		rig.set_guard(g)


func _update_stamina(delta: float) -> void:
	rig.tired = move_toward(rig.tired, 1.0 if exhausted else 0.0, delta * 2.0)
	if _stamina_wait > 0.0:
		_stamina_wait -= delta
		return
	if guarding or state == St.GRAPPLE or state == St.CHARGE:
		return
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + STAMINA_REGEN * delta)


func _spend(cost: float) -> void:
	stamina = maxf(0.0, stamina - cost)
	_stamina_wait = STAMINA_DELAY
	if stamina <= 0.0:
		exhausted = true


# --- MOVE ------------------------------------------------------------------------------------------------------

func _st_move(delta: float, dir: Vector3, mag: float) -> void:
	if motion_state == &"swim":
		_physics_swim(delta, dir, mag)
		return
	var on_floor := is_on_floor()
	var grounded := on_floor and motion_state == &"ground"
	# actions
	if _can_act():
		if _buf_dodge > 0.0 and grounded and _land_lock <= 0.0:
			if _start_dodge(dir, mag):
				return
		if _buf_chain > 0.0 and motion_state != &"swim":
			if _try_throw():
				return
		if _buf_attack > 0.0 and grounded and _land_lock <= 0.0:
			# (from the guard too: the shield drops for the blow and comes back if guard is still held)
			_buf_attack = 0.0
			melee.start_light()
			return
		if grounded and _land_lock <= 0.0 and not guarding and melee.wants_charge():
			# attack held on (through a recoil, a roll, a landing): the heavy blow coils from the stance
			melee.start_charge(false)
			return
		if inp.just_pressed(&"interact") and grounded and _try_grapple():
			return
	# speed
	var wade := _wade()
	var lock := lock_target()
	var top := (SPRINT_SPEED if sprinting else RUN_SPEED) * wade
	if mag < 0.55:
		top = lerpf(0.0, WALK_SPEED, mag / 0.55) * wade
	if lock and not sprinting:
		top = minf(top, LOCK_RUN_SPEED * wade)
	if guarding:
		top = minf(top, GUARD_SPEED * wade)
	if exhausted:
		top = minf(top, RUN_SPEED * 0.8 * wade)
	if _land_lock > 0.0:
		top *= 0.25
	var want := dir.normalized() * top if mag > 0.01 else Vector3.ZERO
	# facing: the lock target; guarding: the foe that threatens him or the one he fights (else the camera's
	# forward); else where we go
	if lock and not sprinting:
		_turn_to(lock.global_position - global_position, delta, TURN_RATE * 1.3)
	elif guarding:
		var foe := _guard_focus()
		if foe != null:
			_turn_to(foe.global_position - global_position, delta, 12.0)
		else:
			_turn_to(-(Game.camera.yaw_basis() as Basis).z if Game.camera else forward(), delta, 10.0)
	elif mag > 0.05:
		var hs := Vector2(velocity.x, velocity.z).length()
		var rate := TURN_RATE * lerpf(1.6, 1.0, clampf(hs / RUN_SPEED, 0.0, 1.0))
		if sprinting:
			rate *= 0.6
		if not on_floor:
			rate *= 0.5
		_turn_to(dir, delta, rate)
	_locomote(delta, want, -1.0, _land_lock <= 0.0)


## Turns `facing` towards a horizontal direction at `rate` (rad/s, exponential).
func _turn_to(d: Vector3, delta: float, rate: float) -> void:
	if Vector2(d.x, d.z).length_squared() < 1e-6:
		return
	facing = lerp_angle(facing, atan2(-d.x, -d.z), 1.0 - exp(-delta * rate))


func _wade() -> float:
	if _world == null:
		return 1.0
	var depth: float = float(_world.sea_level) - global_position.y
	return lerpf(1.0, 0.55, clampf(depth / SWIM_DEPTH, 0.0, 1.0))


## Common ground / air physics: horizontal velocity towards `want` (accel < 0: the default ramps), knockback,
## gravity, jumping (when allowed), move_and_slide, step-ups and landing.
func _locomote(delta: float, want: Vector3, accel: float, allow_jump: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE
	else:
		_coyote -= delta
	if allow_jump and _can_act() and inp.just_pressed(&"jump"):
		_jump_buf = JUMP_BUFFER
	else:
		_jump_buf -= delta
	if inp.is_held(&"jump"):
		_jump_held = true
	elif _jump_held:
		_jump_held = false
		if velocity.y > 0.0 and motion_state == &"air":
			velocity.y *= JUMP_CUT
	# the hero's own horizontal velocity: what he moved with last tick minus the knockback that was added to it
	# (only what is left of it along its direction: a wall may have taken some), so a shove never feeds back into
	# his run speed and snowballs
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var tick := Engine.get_physics_frames()
	if _kb_last.length_squared() > 1e-6 and _kb_tick == tick - 1:
		var kd := _kb_last.normalized()
		hv -= kd * clampf(hv.dot(kd), 0.0, _kb_last.length())
	var a := accel
	if a < 0.0:
		a = ACCEL if want.length() > hv.length() else DECEL
		if not on_floor:
			a = AIR_ACCEL
	hv = hv.move_toward(want, a * delta)
	velocity.x = hv.x + _kb.x
	velocity.z = hv.z + _kb.z
	_kb_last = _kb
	_kb_tick = tick
	_kb = _kb.move_toward(Vector3.ZERO, 18.0 * delta)
	if allow_jump and _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		_jump_buf = 0.0
		_coyote = 0.0
		_jump_held = true
		motion_state = &"air"
		on_floor = false
		rig.play("jump")
		Sfx.play("jump", global_position, -6.0, randf_range(0.95, 1.05))
	elif not on_floor:
		var g := GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -MAX_FALL)
	var was_air := motion_state == &"air"
	if not on_floor:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	var pre_vel := velocity
	move_and_slide()
	# knockback is part of velocity this tick only
	if is_on_floor() or (on_floor and velocity.y <= 0.0):
		_try_step(pre_vel, delta)
	if is_on_floor():
		if was_air or _air_time > 0.15:
			_on_landed(_fall_speed)
		_air_time = 0.0
		_fall_speed = 0.0
		if motion_state == &"air" or motion_state == &"zip" or motion_state == &"hang":
			motion_state = &"ground"
	else:
		_air_time += delta
		if _air_time > 0.12 and motion_state == &"ground":
			motion_state = &"air"
	_slide_off_creatures()
	if is_on_floor() and hv.length() > 1.0:
		_step_t -= delta * hv.length()
		if _step_t <= 0.0:
			_step_t = 1.7
			_footstep(_wade() < 0.95)


# --- water -----------------------------------------------------------------------------------------------------

## Swimming starts where the sea is deeper than SWIM_DEPTH and the hero's feet are down at floating depth; it
## ends where the ground comes back up (wading out).
func _update_water() -> void:
	if _world == null:
		return
	var sea: float = _world.sea_level
	var depth: float = sea - float(_world.height_at(global_position.x, global_position.z))
	if motion_state == &"swim":
		if depth < SWIM_DEPTH - 0.25:
			motion_state = &"ground"
	elif depth > SWIM_DEPTH and global_position.y < sea - SWIM_FLOAT + 0.3 and motion_state != &"zip" and motion_state != &"hang":
		if motion_state == &"air" and _fall_speed > 6.0 and Game.fx:
			Game.fx.call("splash", Vector3(global_position.x, sea, global_position.z), 1.2)
			Sfx.play("splash", global_position, -2.0)
		_end_actions()
		if state != St.MOVE:
			_set_state(St.MOVE)
		motion_state = &"swim"
		velocity.y = minf(velocity.y, 0.0) * 0.2


## The sea surface over the hero right now (waves included); sea_level when there is no Sea.
func _surface_y() -> float:
	var level: float = _world.sea_level
	if Game.sea == null or not is_instance_valid(Game.sea):
		return level
	var depth: float = level - float(_world.height_at(global_position.x, global_position.z))
	return Game.sea.surface_y(global_position.x, global_position.z, depth)


## Ripple rings on the water round the legs while wading and round the body while swimming.
func _update_ripples(delta: float) -> void:
	if _world == null or Game.fx == null or motion_state == &"air" or motion_state == &"zip" or motion_state == &"hang" or not alive:
		return
	var surf := _surface_y()
	var depth := surf - global_position.y
	if depth < 0.06 or depth > 2.5:
		_ripple_t = minf(_ripple_t, 0.15)
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	_ripple_t -= delta * (1.0 + hs * 0.8)
	if _ripple_t <= 0.0:
		_ripple_t = 1.0
		var r := 1.15 if motion_state == &"swim" else 0.8
		Game.fx.call("ring", Vector3(global_position.x, surf - 0.05, global_position.z), r, Color(1.0, 1.0, 1.0, 0.5), 1.1)


func _physics_swim(delta: float, dir: Vector3, mag: float) -> void:
	var top := SWIM_SPRINT_SPEED if sprinting else SWIM_SPEED
	var want := dir.normalized() * top * mag if mag > 0.01 else Vector3.ZERO
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.move_toward(want, (ACCEL * 0.35 if want != Vector3.ZERO else DECEL * 0.25) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	var sea: float = _world.sea_level
	var target_y := _surface_y() - SWIM_FLOAT
	velocity.y = clampf((target_y - global_position.y) * 6.0, -3.0, 3.0)
	if mag > 0.05:
		facing = lerp_angle(facing, atan2(-dir.x, -dir.z), 1.0 - exp(-delta * TURN_RATE * 0.5))
	_jump_buf = 0.0
	move_and_slide()
	_step_t -= delta * hv.length()
	if _step_t <= 0.0 and hv.length() > 0.5:
		_step_t = 2.2
		if Game.fx:
			Game.fx.call("splash", Vector3(global_position.x, sea, global_position.z) + forward() * 0.4, 0.35)


## Step-up: after a slide into a low wall while moving, try raising the capsule STEP_HEIGHT, moving on and dropping
## back onto a walkable surface.
func _try_step(pre_vel: Vector3, delta: float) -> void:
	if not is_on_wall():
		return
	var hmove := Vector3(pre_vel.x, 0.0, pre_vel.z)
	if hmove.length() < 0.5:
		return
	var wall_n := get_wall_normal()
	if wall_n.dot(hmove.normalized()) > -0.2:
		return
	var fwd := hmove.normalized() * maxf(hmove.length() * delta, 0.12)
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP_HEIGHT):
		return
	var up_xf := xf.translated(Vector3.UP * STEP_HEIGHT)
	if test_move(up_xf, fwd):
		return
	var fwd_xf := up_xf.translated(fwd)
	var col := KinematicCollision3D.new()
	if not test_move(fwd_xf, Vector3.DOWN * (STEP_HEIGHT + 0.05), col):
		return
	if col.get_normal().y < cos(floor_max_angle):
		return
	global_position = fwd_xf.origin + col.get_travel()
	velocity.y = 0.0


## Never stand on an enemy's head: slip off sideways.
func _slide_off_creatures() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider()
		if o is CollisionObject3D and ((o as CollisionObject3D).collision_layer & 4) != 0 and c.get_normal().y > 0.5:
			var away := global_position - (o as Node3D).global_position
			away.y = 0.0
			if away.length_squared() < 1e-4:
				away = Vector3.RIGHT
			velocity += away.normalized() * 4.0
			velocity.y = minf(velocity.y, -2.0)


func _on_landed(fall: float) -> void:
	landed.emit(fall)
	if fall > 4.0:
		if Game.fx:
			Game.fx.call("dust", global_position, int(clampf(fall * 0.6, 3.0, 12.0)), 0.5 + fall * 0.04)
		Sfx.play("land", global_position, -6.0 + minf(fall * 0.4, 6.0), clampf(1.1 - fall * 0.015, 0.75, 1.1))
	if fall > 9.0 and state == St.MOVE:
		rig.play("land")
	if fall > HARD_LANDING:
		_land_lock = 0.3
		Game.shake(clampf((fall - HARD_LANDING) * 0.04, 0.1, 0.35))


func _footstep(wet: bool) -> void:
	if wet and Game.fx:
		Game.fx.call("splash", global_position + forward() * 0.3, 0.3)
	if wet or _world == null:
		Sfx.play("footstep", global_position, -14.0, randf_range(0.9, 1.1))
		return
	# surface: sand near the sea, stone on the arena / paths, grass elsewhere
	var surf := "grass"
	if global_position.y < float(_world.sea_level) + 1.2:
		surf = "sand"
	if _world.has_method("surface_at"):
		surf = String(_world.call("surface_at", global_position))
	Sfx.play("step_%s_%d" % [surf, randi_range(1, 3)], global_position, -12.0, randf_range(0.92, 1.08))


func _on_rig_event(ev_name: String) -> void:
	match ev_name:
		"step":
			_step_t = 99.0 # the rig drives footsteps from now on
			if is_on_floor() and motion_state == &"ground":
				var wet := _world != null and global_position.y < float(_world.sea_level) - 0.05
				_footstep(wet)
			elif motion_state == &"swim":
				Sfx.play("swim", global_position, -10.0, randf_range(0.92, 1.08))
		"swing", "impact":
			melee.on_rig_event(ev_name)
		"release":
			if state == St.THROW and not _throw_released:
				_release_spear()
		"pull":
			if state == St.CHAIN and not _pull_fired:
				_fire_pull()


# --- DODGE -----------------------------------------------------------------------------------------------------

## A roll along the input (camera / lock relative), a backstep without input. False when it cannot start.
func _start_dodge(dir: Vector3, mag: float) -> bool:
	_buf_dodge = 0.0
	if exhausted or stamina < DODGE_COST * 0.5 or motion_state != &"ground" or not is_on_floor():
		return false
	_end_actions()
	_spend(DODGE_COST)
	var back := mag < 0.2
	_dodge_roll = not back
	if back:
		_dodge_dir = -forward()
		_dodge_len = BACKSTEP_TIME
		_dodge_dist = BACKSTEP_DIST
		_dodge_if = BACKSTEP_IFRAMES
		rig.play_at("backstep", 0.5 / BACKSTEP_TIME)
	else:
		_dodge_dir = dir.normalized()
		facing = atan2(-_dodge_dir.x, -_dodge_dir.z)
		# the body faces the roll at once (it tucks in this very frame): never a sideways skate into the tumble
		_vis_yaw = facing
		_dodge_len = ROLL_TIME
		_dodge_dist = ROLL_DIST
		_dodge_if = ROLL_IFRAMES
		rig.play_at("dodge", 0.62 / ROLL_TIME)
	_dodge_t = 0.0
	_dodge_rewarded = false
	dodging = true
	_set_state(St.DODGE)
	dodging = true
	Sfx.play("dodge", global_position, -3.0, 1.0 if not back else 1.12)
	if Game.fx and not back:
		Game.fx.call("dust", global_position, 3, 0.3)
	return true


## Displacement of a backstep at normalised time u (0..1): fast start, soft end.
static func _dodge_s(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 2.2)


## Fraction (0..1) of the roll covered at rig time `rt` of the "dodge" action (ROLL_PATH): a short push in the
## crouch, then the distance goes with the tumble at an even speed (the body travels while it turns over, not
## before) and settles as he comes up. Cubic Hermite through the keys (no jumps in speed).
static func _roll_s(rt: float) -> float:
	var k: Array = ROLL_PATH
	if rt <= (k[0] as Vector2).x:
		return 0.0
	var last: Vector2 = k[k.size() - 1]
	if rt >= last.x:
		return last.y
	var lin := ((k[2] as Vector2).y - (k[1] as Vector2).y) / ((k[2] as Vector2).x - (k[1] as Vector2).x)
	var slopes := [0.0, lin, lin, 0.0]
	for i in k.size() - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		if rt <= b.x:
			var dt := b.x - a.x
			var u := (rt - a.x) / dt
			var m0: float = float(slopes[i]) * dt
			var m1: float = float(slopes[i + 1]) * dt
			var u2 := u * u
			var u3 := u2 * u
			return (2.0 * u3 - 3.0 * u2 + 1.0) * a.y + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * b.y + (u3 - u2) * m1
	return last.y


func _st_dodge(delta: float) -> void:
	var t0 := _dodge_t
	_dodge_t += delta
	_iframes = _dodge_if.y - _dodge_t if (_dodge_t >= _dodge_if.x and _dodge_t < _dodge_if.y) else 0.0
	var ds := 0.0
	if _dodge_roll:
		var k := 0.62 / ROLL_TIME # the rig's dodge action plays at this speed
		ds = (_roll_s(_dodge_t * k) - _roll_s(t0 * k)) * _dodge_dist
	else:
		var move_len := _dodge_len * 0.86
		ds = (_dodge_s(_dodge_t / move_len) - _dodge_s(t0 / move_len)) * _dodge_dist
	var want := _dodge_dir * (ds / maxf(delta, 1e-4)) * _wade()
	var lock := lock_target()
	if lock and _dodge_t > _dodge_len * 0.7:
		_turn_to(lock.global_position - global_position, delta, 14.0)
	_locomote(delta, want, 400.0, false)
	# the last part of a roll can flow into a blow, another roll or the guard
	if _dodge_t > _dodge_len * 0.72 and _can_act():
		if _buf_attack > 0.0:
			_buf_attack = 0.0
			dodging = false
			_set_state(St.MOVE)
			melee.start_light()
			return
		if _buf_dodge > 0.0:
			var iv := _input_vector()
			var d := _move_dir(iv)
			if _start_dodge(d, minf(d.length(), 1.0)):
				return
		if inp.is_held(&"guard"):
			dodging = false
			_iframes = 0.0
			_set_state(St.MOVE)
			rig.stop_action(0.12)
			return
	if _dodge_t >= _dodge_len:
		dodging = false
		_iframes = 0.0
		_set_state(St.MOVE)


# --- STAGGER ---------------------------------------------------------------------------------------------------

## Loses control for `seconds` (hit reactions, guard break, recoil, the end of a wrestle).
func _stagger(seconds: float, _why: String = "") -> void:
	_stagger_t = 0.0
	_stagger_len = seconds
	_set_state(St.STAGGER)


func _st_stagger(delta: float) -> void:
	_stagger_t += delta
	_locomote(delta, Vector3.ZERO, DECEL * 0.6, false)
	if _stagger_t >= _stagger_len:
		_set_state(St.MOVE)


# --- melee (HeroMelee drives it) ----------------------------------------------------------------------------------

func _st_melee(delta: float, dir: Vector3, mag: float) -> void:
	var r := melee.tick(delta, dir, mag)
	if state != St.ATTACK and state != St.HEAVY and state != St.CHARGE:
		return # the blow handed over (a deflect's recoil, ...)
	if r == HeroMelee.DONE:
		_set_state(St.MOVE)
		return
	# cancels allowed by the blow (its recovery)
	if melee.can_cancel():
		if _buf_dodge > 0.0 and _start_dodge(dir, mag):
			return
		if _buf_chain > 0.0 and _try_throw():
			return
		if inp.is_held(&"guard") and state != St.CHARGE:
			melee.abort()
			_set_state(St.MOVE)
			return
		if melee.can_move_out(mag):
			# the stick takes him out of the recovery into the run (no drifting to the end of the follow-through)
			melee.abort()
			rig.stop_action(0.12)
			_set_state(St.MOVE)
			_st_move(delta, dir, mag)
			return
	if state == St.CHARGE and _buf_dodge > 0.0 and _start_dodge(dir, mag):
		return
	_locomote(delta, melee.want_velocity(dir, mag), melee.accel(), false)


## Called by HeroMelee when a blow is deflected (the target is immune to blades): the arm is thrown back.
func recoil(point: Vector3, strong: bool) -> void:
	melee.abort()
	var l: float = rig.play("recoil")
	_stagger(l * (0.75 if strong else 0.5), "recoil")
	_kb = -forward() * (3.0 if strong else 1.5)


# --- THROW -------------------------------------------------------------------------------------------------------

## Starts the chain spear's throw at the current candidate (or freely along the camera), or calls it back when
## it is already out. False when nothing happened.
func _try_throw() -> bool:
	_buf_chain = 0.0
	var exclude: Node3D = null
	if state == St.HANG:
		exclude = _anchor
	elif spear.mode == ChainSpear.RETURNING:
		# still flying home: it snaps back into the hand and goes again at once (the press is never lost)
		spear.snap_back(true)
	elif spear.mode != ChainSpear.BACK:
		spear.release()
		if state == St.CHAIN:
			_finish_chain()
		return true
	if motion_state == &"swim":
		return false
	var tgt: Node3D = spear.find_candidate(exclude) if Game.camera and is_instance_valid(Game.camera) else null
	_throw_hang = state == St.HANG
	if _throw_hang:
		# from one ring to the next: the spear jerks free of the old ring and is thrown again; the hero keeps
		# his grip on the chain until the new throw bites (or misses: then he drops)
		spear.snap_back(true)
		_anchor = null
		velocity = Vector3.ZERO
	_throw_target = tgt
	_throw_aim = tgt.call("chain_point") if tgt else _free_aim_point()
	_throw_released = false
	melee.abort()
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0 or motion_state != &"ground"
	rig.play_at("throw", THROW_SPEED, moving)
	_throw_rel_t = RigHeracles.THROW_RELEASE / THROW_SPEED
	_set_state(St.THROW)
	return true


## Where the spear flies without a target: what the camera centre looks at (the first surface within range), or
## the end of the range along the view.
func _free_aim_point() -> Vector3:
	var origin := global_position + Vector3(0, 1.5, 0)
	if Game.camera == null or not is_instance_valid(Game.camera):
		return origin + forward() * ChainSpear.RANGE
	var cam: Camera3D = Game.camera.cam
	var cf := -cam.global_transform.basis.z
	var cp := cam.global_transform.origin
	var far := cp + cf * (ChainSpear.RANGE + cp.distance_to(origin))
	var q := PhysicsRayQueryParameters3D.create(cp, far, 1 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3 = hit["position"] if not hit.is_empty() else far
	var d := p - origin
	if d.length() > ChainSpear.RANGE:
		p = origin + d.normalized() * ChainSpear.RANGE
	# never behind the hero
	if Combat.flat(p - origin).dot(forward()) < -0.5 and lock_target() == null:
		p = origin + forward() * ChainSpear.RANGE
	return p


func _st_throw(delta: float, dir: Vector3, mag: float) -> void:
	var goal: Vector3 = _throw_target.call("chain_point") if Combat.is_alive(_throw_target) else _throw_aim
	_turn_to(goal - global_position, delta, 18.0)
	if not _throw_released and state_t >= _throw_rel_t + 0.08:
		_release_spear() # the rig event never came (the action was replaced): throw anyway
	if _throw_hang:
		velocity = Vector3.ZERO
		motion_state = &"hang"
		if _throw_released and spear.mode != ChainSpear.FLYING:
			# it missed: let go of the chain
			_throw_hang = false
			motion_state = &"air"
			_set_state(St.MOVE)
		return
	var top := WALK_SPEED * 0.8 if motion_state == &"ground" else 0.0
	var want := dir.normalized() * top * mag if mag > 0.05 and motion_state == &"ground" else Vector3.ZERO
	if motion_state == &"ground":
		_locomote(delta, want, -1.0, false)
	else:
		_locomote(delta, Vector3(velocity.x, 0.0, velocity.z), 0.0, false)
	if _throw_released and state_t >= _throw_rel_t + 0.12:
		_set_state(St.MOVE)


func _release_spear() -> void:
	_throw_released = true
	var from: Vector3 = rig.chain_origin()
	var tgt := _throw_target if Combat.is_alive(_throw_target) else null
	var aim: Vector3 = tgt.call("chain_point") if tgt else _throw_aim
	spear.launch(from, tgt, aim)
	rig.set_spear_on_back(false)


## ChainSpear: the spearhead bit `target` (an anchor of `kind`).
func on_spear_stuck(target: Node3D, kind: StringName) -> void:
	if not alive:
		spear.release()
		return
	if state in [St.STAGGER, St.DODGE, St.GRAPPLE, St.DEAD]:
		spear.release()
		return
	_anchor = target
	melee.abort()
	_pull_fired = false
	_zip_strike = false
	match kind:
		&"ring":
			_start_zip(target, true)
		&"heavy":
			_start_zip(target, false)
		&"light":
			_start_pull(&"yank")
		&"beast":
			_start_pull(&"beast")
		&"boulder":
			_start_haul()
		_:
			spear.release()


## ChainSpear: the spear came back without biting anything (a miss, a bounce).
func on_spear_missed() -> void:
	pass


# --- CHAIN: zip to a ring / pulled to a heavy anchor ------------------------------------------------------------

func _start_zip(target: Node3D, ring: bool) -> void:
	var cp: Vector3 = target.call("chain_point")
	var away := Combat.flat(global_position - cp)
	if target.has_method("chain_normal"):
		away = Combat.flat(target.call("chain_normal"))
	if away.length_squared() < 1e-4:
		away = -forward()
	away = away.normalized()
	facing = atan2(away.x, away.z) # face the anchor
	_zip_ledge = Vector3.INF
	_zip_land = false
	_mantle_free = false
	if ring:
		# hang by a short length of chain under the ring, the body clear of the stone it is set in
		var right := Basis(Vector3.UP, facing) * Vector3.RIGHT
		_zip_end = cp + away * (CAPSULE_R + 0.14) + right * (-HANG_HAND.x) - Vector3(0, HANG_HAND.y + 0.3, 0)
		for i in 6:
			if not test_move(Transform3D(Basis.IDENTITY, _zip_end), Vector3(0, 0.02, 0)):
				break
			_zip_end += away * 0.15
		_zip_ledge = _find_ledge(cp, -away)
		if _zip_ledge != Vector3.INF:
			# a ledge: the zip ends under its lip, against the wall, ready to climb over (_start_climb)
			var face := _wall_face(cp, away, _zip_ledge.y)
			_zip_end = Vector3(face.x, _zip_ledge.y - MANTLE_DROP, face.z) + away * MANTLE_STANDOFF
			# the spear goes in up to its butt ring (the shaft would stand out of the wall into his legs)
			spear.sink(ChainSpear.TIP_Z + ChainSpear.BUTT_Z - ChainSpear.RING_BURY - 0.05)
			for i in 6:
				if not test_move(Transform3D(Basis.IDENTITY, _zip_end), Vector3(0, 0.02, 0)):
					break
				_zip_end += away * 0.1
		else:
			# a ring on a standing stone (or low on a wall) with walkable ground just under where he would hang:
			# the zip ends on that ground at the foot of the stone instead of dangling with his feet over it
			var g := _ground_below(_zip_end, ZIP_LAND_DROP, away)
			if g != Vector3.INF:
				_zip_end = g
				_zip_land = true
	else:
		var r := Combat.body_radius(target)
		var p := target.global_position + away * (r + 1.05)
		_zip_end = Game.world.ground(p) if Game.world else Vector3(p.x, target.global_position.y, p.z)
	_zip_from = global_position
	var dist := _zip_from.distance_to(_zip_end)
	_zip_ctrl = (_zip_from + _zip_end) * 0.5 + Vector3(0, 0.08 * dist + (0.5 if not ring else 0.25), 0)
	if _zip_ledge != Vector3.INF:
		# to a ledge: in low, towards the ring (no higher than hanging from it), and up the wall in the last couple of
		# metres, where he lets go and is flung up to the lip (MANTLE_LET_GO): never pulled past the ring on a chain
		# hanging down from his fist, and no long float before the wall
		var low := clampf(cp.y - HANG_HAND.y - 0.4, minf(_zip_from.y, _zip_end.y), _zip_end.y)
		var out := Combat.flat(_zip_from - _zip_end)
		var reach := minf(2.0, out.length() * 0.3)
		_zip_ctrl = Vector3(_zip_end.x, low, _zip_end.z) + (out.normalized() * reach if out.length() > 0.01 else Vector3.ZERO)
	_zip_len = maxf(0.1, _zip_from.distance_to(_zip_ctrl) + _zip_ctrl.distance_to(_zip_end)) * 0.94
	_zip_u = 0.0
	_zip_speed = 3.0
	_zip_delay = ZIP_TENSION
	_zip_stuck = 0
	chain_mode = &"zip" if ring else &"to"
	spear.taut = 1.0
	_set_state(St.CHAIN)
	motion_state = &"zip"
	velocity = Vector3.ZERO
	Sfx.play("chain_taut", global_position + Vector3(0, 1.5, 0), -2.0)
	Sfx.play("chain_zip", Vector3.INF, -3.0)
	if Game.camera and Game.camera.has_method("set_zip"):
		Game.camera.call("set_zip", true)
	Game.shake(0.12)


## The wall face just under a ledge's lip at height `lip_y` (a ray in from `away` of the ring at `cp`); the ring's
## own plane when the ray finds nothing.
func _wall_face(cp: Vector3, away: Vector3, lip_y: float) -> Vector3:
	var at := Vector3(cp.x, lip_y - 0.3, cp.z)
	var q := PhysicsRayQueryParameters3D.create(at + away * 1.2, at - away * 1.5, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
		return hit["position"]
	return at


## Walkable ground (world layer) under the feet position `p` within `max_drop` m, with room for the capsule there
## (pushed out along `away` when the spot is tight); Vector3.INF when there is none.
func _ground_below(p: Vector3, max_drop: float, away: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p - Vector3(0, max_drop, 0), 1, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.72:
		return Vector3.INF
	var g: Vector3 = (hit["position"] as Vector3) + Vector3(0, 0.04, 0)
	for i in 5:
		if not test_move(Transform3D(Basis.IDENTITY, g + Vector3(0, 0.06, 0)), Vector3(0, 0.05, 0)):
			return g
		g += away * 0.15
	return Vector3.INF


static func _bezier(a: Vector3, c: Vector3, b: Vector3, u: float) -> Vector3:
	var v := 1.0 - u
	return a * (v * v) + c * (2.0 * v * u) + b * (u * u)


## A walkable top within reach over a ring (a ledge to climb onto after the zip): rays down just behind the ring.
## Returns Vector3.INF when there is none.
func _find_ledge(cp: Vector3, into: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for k in [0.5, 0.8, 1.1, 1.5]:
		var top := cp + into * float(k) + Vector3(0, 2.6, 0)
		var q := PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 4.4, 0), 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		var p: Vector3 = hit["position"]
		if n.y < 0.75 or p.y < cp.y - 0.9 or p.y > cp.y + 1.9:
			continue
		# room for the capsule up there, and a real top (not the narrow head of a standing stone)?
		var land := p + into * 0.35
		var xf := Transform3D(Basis.IDENTITY, land + Vector3(0, 0.05, 0))
		if test_move(xf, Vector3(0, 0.1, 0)):
			continue
		var side := into.cross(Vector3.UP).normalized()
		var roomy := true
		for o in [into * 0.6, side * 0.6, -side * 0.6]:
			var a: Vector3 = land + o + Vector3(0, 1.0, 0)
			var hq := PhysicsRayQueryParameters3D.create(a, a - Vector3(0, 1.6, 0), 1, [get_rid()])
			var h2 := space.intersect_ray(hq)
			if h2.is_empty() or absf((h2["position"] as Vector3).y - p.y) > 0.35:
				roomy = false
				break
		if not roomy:
			continue
		return land
	return Vector3.INF


func _st_chain(delta: float, dir: Vector3, mag: float) -> void:
	if not Combat.is_alive(_anchor) and chain_mode != &"hop" and chain_mode != &"climb":
		_finish_chain(true)
		return
	if _buf_attack > 0.0 and chain_mode == &"to":
		_zip_strike = true
	match chain_mode:
		&"zip", &"to":
			_tick_zip(delta)
		&"hop":
			_tick_hop(delta)
		&"climb":
			_tick_climb(delta)
		&"yank", &"beast":
			_tick_pull(delta)
		&"haul":
			_tick_haul(delta, dir, mag)


func _tick_zip(delta: float) -> void:
	var goal_cp: Vector3 = _anchor.call("chain_point")
	if _zip_delay > 0.0:
		# the chain snaps taut: a beat of tension before the pull
		_zip_delay -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		return
	_zip_speed = minf(ZIP_SPEED, _zip_speed + ZIP_ACCEL * delta)
	var remaining := (1.0 - _zip_u) * _zip_len
	# a ring: the last metre eases down to 2.5 m/s (no dead stop, no swing on arrival) and the body comes upright;
	# pulled to a heavy anchor: he arrives fast, ready to strike
	var ring := chain_mode == &"zip"
	var ledge := ring and _zip_ledge != Vector3.INF
	var spd := minf(_zip_speed, maxf(2.5, remaining * 5.0)) if (ring and not ledge) else minf(_zip_speed, maxf(6.0, remaining * 7.0))
	rig.zip_upright = clampf(1.0 - remaining / 1.6, 0.0, 1.0) if ring else 0.0
	if ledge and not _mantle_free and global_position.y + MANTLE_LET_GO >= goal_cp.y:
		# a ledge over the ring: as his hand comes level with the ring he lets go of the chain and his momentum
		# carries him up the last metre to the lip (never pulled up past the ring on a chain hanging down from him)
		_mantle_free = true
		spear.release()
		# and reaches for the lip while he rises: the climb's first key (both arms up) held until the zip ends
		rig.play("climb")
		rig.action_hold = 0.0
	_zip_u = minf(1.0, _zip_u + spd * delta / _zip_len)
	var goal := _bezier(_zip_from, _zip_ctrl, _zip_end, _zip_u)
	var before := global_position
	velocity = (goal - before) / maxf(delta, 1e-4)
	move_and_slide()
	var expected := before.distance_to(goal)
	var moved := before.distance_to(global_position)
	if expected > 0.03 and moved < expected * 0.35:
		_zip_stuck += 1
	else:
		_zip_stuck = 0
	_turn_to(goal_cp - global_position, delta, 12.0)
	if _zip_stuck >= 4:
		# blocked on the way: let go
		_finish_chain(true)
		return
	if _zip_u >= 1.0 or global_position.distance_to(_zip_end) < 0.12:
		_arrive_zip()


func _arrive_zip() -> void:
	if Game.camera and Game.camera.has_method("set_zip"):
		Game.camera.call("set_zip", false)
	if chain_mode == &"to":
		# pulled to a heavy target: land in front of it, maybe striking on arrival
		spear.release()
		chain_mode = &""
		_anchor = null
		motion_state = &"air"
		velocity = forward() * 2.0
		_set_state(St.MOVE)
		if _zip_strike:
			melee.start_light(3)
		return
	if _zip_land:
		# a ring with ground under it: the zip set him down at the foot of its stone
		spear.release()
		chain_mode = &""
		_anchor = null
		_zip_land = false
		motion_state = &"air"
		velocity = Combat.flat(_zip_end - _zip_ctrl).normalized() * 1.2
		_set_state(St.MOVE)
		rig.play("land")
		if Game.fx:
			Game.fx.call("dust", global_position, 4, 0.45)
		Sfx.play("land", global_position, -8.0, 1.05)
		return
	if _zip_ledge != Vector3.INF:
		_start_climb()
		return
	# nothing to climb: hang from the ring
	_hang_pos = global_position
	chain_mode = &""
	_set_state(St.HANG)
	motion_state = &"hang"
	velocity = Vector3.ZERO
	spear.taut = 1.0


## Up and over the ledge (chain_mode &"climb"): the body follows MANTLE_RISE up the wall and goes over the edge in
## the last part (MANTLE_OVER), with the rig's "climb" (hands on the lip, the press, a knee up, standing).
func _start_climb() -> void:
	chain_mode = &"climb"
	_mantle_t = 0.0
	_mantle_from = global_position
	_mantle_to = _zip_ledge
	var d := Combat.flat(_mantle_to - _mantle_from)
	_mantle_in = d.normalized() if d.length() > 0.01 else forward()
	_mantle_dist = d.length()
	_mantle_free = false
	_zip_stuck = 0
	motion_state = &"air"
	velocity = Vector3.ZERO
	facing = atan2(-_mantle_in.x, -_mantle_in.z)
	if rig.action == "climb":
		rig.action_hold = -1.0 # (reaching since he let go of the chain: on from there)
	else:
		rig.play("climb")


## The rise (m) of the climb at `t` s: MANTLE_RISE through Catmull-Rom tangents (flat at both ends).
static func _mantle_rise(t: float) -> float:
	var k: Array = MANTLE_RISE
	var n := k.size()
	if t <= (k[0] as Vector2).x:
		return (k[0] as Vector2).y
	if t >= (k[n - 1] as Vector2).x:
		return (k[n - 1] as Vector2).y
	for i in n - 1:
		var a: Vector2 = k[i]
		var b: Vector2 = k[i + 1]
		if t > b.x:
			continue
		var m0 := 0.0
		var m1 := 0.0
		if i > 0:
			var pa: Vector2 = k[i - 1]
			m0 = (b.y - pa.y) / (b.x - pa.x)
		if i + 2 < n:
			var nb: Vector2 = k[i + 2]
			m1 = (nb.y - a.y) / (nb.x - a.x)
		var h := b.x - a.x
		var u := (t - a.x) / h
		var u2 := u * u
		var u3 := u2 * u
		return (2.0 * u3 - 3.0 * u2 + 1.0) * a.y + (u3 - 2.0 * u2 + u) * h * m0 + (-2.0 * u3 + 3.0 * u2) * b.y + (u3 - u2) * h * m1
	return (k[n - 1] as Vector2).y


func _tick_climb(delta: float) -> void:
	_mantle_t += delta
	# (the rig keeps the hands of its grip keys on the lip, whatever the body's rise does in between)
	rig.climb_lip = _mantle_to.y - global_position.y
	if not _mantle_free and _mantle_t >= 0.1:
		# both hands on the lip: the spear jerks out of the ring and flies home
		_mantle_free = true
		spear.release()
		_anchor = null
		Sfx.play("step_stone_%d" % randi_range(1, 3), _mantle_from + Vector3.UP * (MANTLE_DROP + 0.05) + _mantle_in * 0.5, -6.0, 0.9)
	var over := smoothstep(MANTLE_OVER.x, MANTLE_OVER.y, _mantle_t)
	var goal := _mantle_from + Vector3.UP * _mantle_rise(_mantle_t) + _mantle_in * (_mantle_dist * over)
	var before := global_position
	velocity = (goal - before) / maxf(delta, 1e-4)
	move_and_slide()
	var expected := before.distance_to(goal)
	if expected > 0.02 and before.distance_to(global_position) < expected * 0.3:
		_zip_stuck += 1
	else:
		_zip_stuck = 0
	_turn_to(_mantle_in, delta, 20.0)
	if _mantle_t >= MANTLE_TIME or _zip_stuck >= 8:
		# on the top (snapped there if the lip's rough crown held him back and the spot is free)
		var to := _mantle_to + Vector3(0, 0.03, 0)
		if global_position.distance_to(to) > 0.3 and not test_move(Transform3D(Basis.IDENTITY, to), Vector3(0, 0.05, 0)):
			global_position = to
		if not _mantle_free:
			spear.release()
		chain_mode = &""
		_anchor = null
		rig.climb_lip = -99.0
		velocity = _mantle_in * 1.2 + Vector3.DOWN
		_set_state(St.MOVE)


func _tick_hop(delta: float) -> void:
	var spd := 7.5
	_zip_u = minf(1.0, _zip_u + spd * delta / _zip_len)
	var goal := _bezier(_zip_from, _zip_ctrl, _zip_end, _zip_u)
	var before := global_position
	velocity = (goal - before) / maxf(delta, 1e-4)
	move_and_slide()
	var expected := before.distance_to(goal)
	if expected > 0.03 and before.distance_to(global_position) < expected * 0.3:
		_zip_stuck += 1
	else:
		_zip_stuck = 0
	if _zip_u >= 1.0 or _zip_stuck >= 6:
		chain_mode = &""
		_anchor = null
		velocity = Vector3(velocity.x, 0.0, velocity.z).limit_length(2.0)
		_set_state(St.MOVE)


func _st_hang(delta: float) -> void:
	if not Combat.is_alive(_anchor) or spear.mode != ChainSpear.STUCK:
		_drop_from_hang(false)
		return
	motion_state = &"hang"
	velocity = (_hang_pos - global_position) / maxf(delta, 1e-4)
	move_and_slide()
	velocity = Vector3.ZERO
	if not _can_act():
		return
	if _buf_chain > 0.0:
		_try_throw()
		return
	if inp.just_pressed(&"jump") or _buf_dodge > 0.0 or state_t > HANG_MAX:
		_drop_from_hang(inp.just_pressed(&"jump"))


func _drop_from_hang(hop: bool) -> void:
	spear.release()
	_anchor = null
	motion_state = &"air"
	velocity = -forward() * (2.5 if hop else 0.8) + Vector3(0, 3.5 if hop else 0.0, 0)
	_buf_dodge = 0.0
	_set_state(St.MOVE)


## Ends any chain mode (released, blocked, the target gone); `drop` lets the hero fall if he was airborne.
func _finish_chain(drop: bool = false) -> void:
	if spear.mode == ChainSpear.STUCK:
		spear.release()
	if rig.action == "pull":
		rig.action_hold = -1.0 # the braced haul pose lets go and recovers
	if Game.camera and Game.camera.has_method("set_zip"):
		Game.camera.call("set_zip", false)
	chain_mode = &""
	_anchor = null
	if motion_state == &"zip" or motion_state == &"hang":
		motion_state = &"air"
		velocity = velocity.limit_length(6.0) if drop else Vector3.ZERO
	if state == St.CHAIN or state == St.HANG:
		_set_state(St.MOVE)


# --- CHAIN: yank a light target / brace against a beast ------------------------------------------------------

func _start_pull(mode: StringName) -> void:
	chain_mode = mode
	_pull_fired = false
	_set_state(St.CHAIN)
	_turn_to(_anchor.global_position - global_position, 1.0, 50.0)
	var spd := 1.15 if mode == &"yank" else 0.9
	var l: float = rig.play_at("pull", spd, false)
	_pull_fire_t = 0.24 / spd + 0.06
	spear.taut = 0.6
	if l <= 0.0:
		_fire_pull()


func _fire_pull() -> void:
	if _pull_fired or not Combat.is_alive(_anchor):
		return
	_pull_fired = true
	_pull_fire_t = state_t
	var d := Combat.flat(global_position - _anchor.global_position)
	d = d.normalized() if d.length_squared() > 1e-4 else forward()
	spear.taut = 1.0
	Sfx.play("chain_taut", _anchor.global_position + Vector3(0, 1, 0), -1.0)
	if chain_mode == &"beast":
		Game.shake(0.35)
		Game.hitstop(0.05)
		_kb = -d * 2.5 # the beast's weight jerks the hero forward a little
	else:
		Game.shake(0.15)
	_anchor.call("on_chain_pull", self, d)


func _tick_pull(delta: float) -> void:
	_locomote(delta, Vector3.ZERO, DECEL, false)
	if Combat.is_alive(_anchor):
		_turn_to(_anchor.global_position - global_position, delta, 10.0)
	if not _pull_fired:
		if state_t >= _pull_fire_t:
			_fire_pull()
		return
	var since := state_t - _pull_fire_t
	# the foe is in the air on its way to him: a blow or a roll ends the pull pose at once (meet it with the sword)
	if chain_mode == &"yank" and _can_act() and (_buf_attack > 0.0 or _buf_dodge > 0.0):
		var flying := Combat.is_alive(_anchor) and _anchor.has_method("is_yanked") and bool(_anchor.call("is_yanked"))
		if flying or since > 0.12:
			_finish_chain()
			rig.stop_action(0.08)
			if _buf_attack > 0.0:
				_buf_attack = 0.0
				melee.start_light()
			else:
				var d := _move_dir(_input_vector())
				_start_dodge(d, minf(d.length(), 1.0))
			return
	var close := Combat.is_alive(_anchor) and Combat.flat(_anchor.global_position - global_position).length() < 2.6
	if (chain_mode == &"yank" and (close or since > 0.9)) or (chain_mode == &"beast" and since > 0.5):
		_finish_chain()


# --- CHAIN: haul the boulder ----------------------------------------------------------------------------------------

func _start_haul() -> void:
	chain_mode = &"haul"
	_set_state(St.CHAIN)
	_haul_len = Combat.flat(_anchor.global_position - global_position).length()
	_haul_grace = 0.0 if inp.is_held(&"chain") else 1.0
	spear.taut = 0.5
	rig.play_at("pull", 1.0, true)
	rig.action_hold = 0.5


func _tick_haul(delta: float, dir: Vector3, mag: float) -> void:
	var held := inp.is_held(&"chain")
	if held:
		_haul_grace = 0.0
	elif _haul_grace > 0.0:
		_haul_grace -= delta
		if _haul_grace <= 0.0:
			_finish_chain()
			return
	else:
		_finish_chain()
		return
	var to_b := Combat.flat(_anchor.global_position - global_position)
	var dist := to_b.length()
	if dist > ChainSpear.KEEP_RANGE:
		_finish_chain()
		return
	if held:
		_haul_len = maxf(HAUL_MIN, minf(_haul_len, dist) - HAUL_REEL * delta)
	var taut := dist > _haul_len
	var want := dir.normalized() * HAUL_SPEED * mag if mag > 0.05 else Vector3.ZERO
	if taut:
		var away := -to_b.normalized()
		var out := want.dot(away)
		if out > 0.0 and dist > _haul_len + 0.5:
			want -= away * out * 0.7 # the chain holds the hero back
		_anchor.call("on_chain_pull", self, away)
		spear.taut = move_toward(spear.taut, 1.0, delta * 6.0)
	else:
		spear.taut = move_toward(spear.taut, 0.35, delta * 3.0)
	_turn_to(to_b, delta, 9.0)
	_locomote(delta, want, -1.0, false)


# --- GRAPPLE (the hero's side of the wrestle; docs/COMBAT.md) -------------------------------------------------

## The grapplable beast within reach that allows a wrestle now, or null.
func _grapple_candidate() -> Node3D:
	var best: Node3D = null
	var best_d := GRAPPLE_RANGE
	for n in get_tree().get_nodes_in_group("grapplable"):
		var t := n as Node3D
		if t == null or not Combat.is_alive(t) or not t.has_method("can_grapple"):
			continue
		if not bool(t.call("can_grapple", self)):
			continue
		var d := Combat.flat(t.global_position - global_position).length() - Combat.body_radius(t)
		if d < best_d:
			best_d = d
			best = t
	return best


func _try_grapple() -> bool:
	var g := _grapple_candidate()
	if g == null:
		return false
	_end_actions()
	grapple_target = g
	_grapple_xf = g.call("grapple_anchor", self) if g.has_method("grapple_anchor") else Transform3D(Basis.IDENTITY, global_position)
	collision_mask = 1 | 8 # the beast's body is held, not collided with
	_cue_left = 0.0
	_set_state(St.GRAPPLE)
	rig.play("grapple_start")
	# bare hands, as with the lion: the sword and the shield are laid on the ground beside him (the shield would
	# cut into the beast's head)
	_lay_weapons(true)
	Sfx.play("chain_taut", global_position, -8.0, 0.7)
	g.call("grapple_begin", self)
	return true


## The sword and the shield laid on the ground at his side for the wrestle (`down`), or back in his hands.
func _lay_weapons(down: bool) -> void:
	rig.set_weapons_aside(down)
	if not down:
		if _aside != null and is_instance_valid(_aside):
			if Game.fx:
				Game.fx.call("dust", _aside.global_position, 2, 0.25)
			_aside.queue_free()
		_aside = null
		return
	if _aside != null and is_instance_valid(_aside):
		_aside.queue_free()
	_aside = Node3D.new()
	_aside.name = "WeaponsAside"
	_aside.top_level = true
	add_child(_aside)
	var b := Basis(Vector3.UP, facing)
	var right := b * Vector3.RIGHT
	var back := b * Vector3.BACK
	# the shield face up behind him to one side, the sword flat beside it: the first placement with room on flat
	# ground (never into a pillar, a rock or the beast); with none, they are simply out of sight
	var spots := [
		[right * 0.75 + back * 0.55, right * 1.25 - back * 0.1],
		[-right * 0.75 + back * 0.55, -right * 1.25 - back * 0.1],
		[back * 1.05, back * 1.6 + right * 0.45],
	]
	var pick := -1
	for i in spots.size():
		var sp: Array = spots[i]
		if _room_for(global_position + (sp[0] as Vector3), 0.4) and _room_for(global_position + (sp[1] as Vector3), 0.3):
			pick = i
			break
	if pick < 0:
		return
	var sh_at: Vector3 = global_position + (spots[pick][0] as Vector3)
	var sw_at: Vector3 = global_position + (spots[pick][1] as Vector3)
	var el := RigHeracles.mx(RigHeracles.P_ELBOW, -1.0)
	var wr := RigHeracles.mx(RigHeracles.P_WRIST, -1.0)
	var dfa := (wr - el).normalized()
	var ny := Vector3(-1, 0, 0)
	var nx := RigHeracles.perp(dfa, ny).normalized()
	var sh_frame := Transform3D(Basis(nx, ny, nx.cross(ny)), el + dfa * 0.13 + Vector3(-0.085, 0, 0))
	_aside_piece(RigHeracles.shield_meshes(), sh_frame.affine_inverse(), sh_at, facing + 0.7)
	_aside_piece(RigHeracles.sword_meshes(), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), sw_at, facing + 1.9)
	if Game.fx:
		Game.fx.call("dust", sh_at, 3, 0.35)
	Sfx.play("shield_block", sh_at, -14.0, 0.75)


## Room on the ground at `p` (feet height) for something of radius `r`: a sphere just over the ground touches
## nothing of the world, movables or enemies, and the ground there is within 0.5 m of his feet.
func _room_for(p: Vector3, r: float) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p - Vector3(0, 1.5, 0), 1, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty() or absf((hit["position"] as Vector3).y - global_position.y) > 0.5 or (hit["normal"] as Vector3).y < 0.8:
		return false
	var sp := SphereShape3D.new()
	sp.radius = r
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = sp
	sq.collision_mask = 1 | 4 | 8
	sq.exclude = [get_rid()]
	# (lifted by the slope's rise over the radius, so the ground itself never counts)
	var ny: float = (hit["normal"] as Vector3).y
	var rise := r * sqrt(maxf(0.0, 1.0 - ny * ny)) / maxf(ny, 0.1)
	sq.transform = Transform3D(Basis.IDENTITY, (hit["position"] as Vector3) + Vector3(0, r + 0.06 + rise, 0))
	return space.intersect_shape(sq, 1).is_empty()


## One laid-down piece: `meshes` [soft, metal] placed by `local` in a holder whose origin sits on the ground at `at`
## (rays on the world layer), turned `yaw`, its lowest point on the ground.
func _aside_piece(meshes: Array, local: Transform3D, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	_aside.add_child(holder)
	var lo := INF
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.material_override = Materials.lowpoly()
		if i == 1:
			Materials.set_param(mi, &"metal", 1.0)
		mi.transform = local
		holder.add_child(mi)
		var bb: AABB = (meshes[i] as Mesh).get_aabb()
		for c in 8:
			lo = minf(lo, (local * bb.get_endpoint(c)).y)
	var gy := at.y
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.0, 0), at - Vector3(0, 2.0, 0), 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		gy = (hit["position"] as Vector3).y
	holder.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, gy - lo + 0.004, at.z))


func is_grappling() -> bool:
	return state == St.GRAPPLE


## Seconds left of the open squeeze window in a wrestle (0 when none is open): the UI's wrestle prompt.
func grapple_window_left() -> float:
	return _cue_left if state == St.GRAPPLE else 0.0


## Target -> hero: a squeeze window opens for `window` seconds (press attack or interact inside it).
func grapple_cue(window: float) -> void:
	if state != St.GRAPPLE:
		return
	_cue_left = window
	if Game.fx:
		Game.fx.call("glint", rig.grapple_point(), 1.3, Color(1.0, 0.9, 0.55), maxf(window, 0.25))


## Target -> hero: the beast thrashes: costs `cost` stamina (a fifth with the guard held); out of stamina the
## hero is thrown off.
func grapple_thrash(cost: float) -> void:
	if state != St.GRAPPLE:
		return
	var braced := inp.is_held(&"guard")
	var c := cost * (0.2 if braced else 1.0)
	stamina = maxf(0.0, stamina - c)
	_stamina_wait = STAMINA_DELAY
	Game.shake(0.12 if braced else 0.3)
	rig.hit_flash(0.15 if braced else 0.4)
	if stamina <= 0.0:
		exhausted = true
		_end_grapple(false, true)


## Target -> hero: the wrestle is over (`won`: the beast is beaten).
func grapple_release(won: bool) -> void:
	if state == St.GRAPPLE:
		_end_grapple(won, false)


func _st_grapple(delta: float) -> void:
	if not Combat.is_alive(grapple_target):
		_end_grapple(false, false)
		return
	if grapple_target.has_method("grapple_anchor"):
		_grapple_xf = grapple_target.call("grapple_anchor", self)
	var k := 1.0 - exp(-delta * 14.0)
	var goal := _grapple_xf.origin
	# eases onto the anchor, sliding round the world on the way (never into a pillar the beast was stunned
	# against, whatever spot it offers): the beast itself is off the mask while he holds it
	var step := (goal - global_position) * k
	if step.length_squared() > 1e-8:
		var col := move_and_collide(step)
		if col != null:
			move_and_collide(col.get_remainder().slide(col.get_normal()))
	var f := -_grapple_xf.basis.z
	_turn_to(f, delta, 14.0)
	velocity = Vector3.ZERO
	if rig.action == "" and state_t > 0.3:
		rig.play("grapple_loop")
	_cue_left = maxf(0.0, _cue_left - delta)
	if _can_act() and (inp.just_pressed(&"attack") or inp.just_pressed(&"interact")):
		var ok := _cue_left > 0.0
		_cue_left = 0.0
		if ok and Game.fx:
			Game.fx.call("impact", rig.grapple_point(), forward(), 0.8, Color(1.0, 0.92, 0.7))
		grapple_target.call("grapple_input", self, ok)


func _end_grapple(won: bool, thrown: bool) -> void:
	var t := grapple_target
	grapple_target = null
	collision_mask = 1 | 4 | 8
	_lay_weapons(false)
	if t != null and is_instance_valid(t) and t.has_method("grapple_end"):
		t.call("grapple_end", self, won)
	if not alive:
		return
	if thrown:
		_kb = -forward() * 6.0
		_stagger(rig.play("hit_heavy") * 0.7, "thrown")
		Game.shake(0.4)
	else:
		_stagger(rig.play("grapple_end") * 0.75, "grapple_end")
		if won:
			Game.shake(0.3)


# --- interaction ---------------------------------------------------------------------------------------------------

func _update_interaction(delta: float) -> void:
	var it: Object = null
	if _can_act() and state == St.MOVE and motion_state == &"ground" and not dodging:
		# (the grapplable group is looked up 10 times a second, not every tick)
		_grap_scan -= delta
		if _grap_scan <= 0.0:
			_grap_scan = 0.1
			_grap_cand = _grapple_candidate()
		if _grap_cand != null and not Combat.is_alive(_grap_cand):
			_grap_cand = null
		it = _grap_cand
		if it == null:
			it = Interactables.pick(self, global_position, forward())
	if it != interact_target:
		_release_interaction()
		interact_target = it as Node
		interact_target_changed.emit(interact_target)
	if interact_target == null or not _can_act() or (interact_target.is_in_group("grapplable")):
		_release_interaction()
		return
	if inp.just_pressed(&"interact") and interact_target.has_method("interact_press"):
		interact_target.call("interact_press", self)
		var to := (interact_target as Node3D).global_position - global_position if interact_target is Node3D else forward()
		facing = atan2(-to.x, -to.z)
		rig.play("interact")
	elif inp.is_held(&"interact") and interact_target.has_method("interact_hold"):
		_interacting = true
		interact_target.call("interact_hold", delta, self)
	elif _interacting:
		_release_interaction()


func _release_interaction() -> void:
	if _interacting and interact_target != null and is_instance_valid(interact_target) and interact_target.has_method("interact_release"):
		interact_target.call("interact_release", self)
	_interacting = false


# --- chain aim assist ------------------------------------------------------------------------------------------

## Picks the anchor the spear would fly to (every few ticks, or now when `force`): in group chain_anchor, within
## ChainSpear.RANGE, inside a cone round the camera's forward that widens for close targets, in line of sight.
func _update_candidate(delta: float, force: bool = false) -> void:
	_cand_t -= delta
	if not force and _cand_t > 0.0:
		return
	_cand_t = 0.05
	var best: Node3D = null
	var can_aim := alive and _can_act() and motion_state != &"swim" and state != St.GRAPPLE and (spear.mode == ChainSpear.BACK or state == St.HANG)
	if can_aim and Game.camera and is_instance_valid(Game.camera):
		best = spear.find_candidate(_anchor if state == St.HANG else null)
	if best != chain_candidate:
		chain_candidate = best
		chain_candidate_changed.emit(best)


# --- rig and visual ----------------------------------------------------------------------------------------------

## Foot IK: the ground under each foot (two short rays on the world layer), fed to the rig.
func _probe_feet() -> void:
	var on := alive and motion_state == &"ground" and is_on_floor() and state != St.DODGE and state != St.GRAPPLE
	if not on:
		rig.set_ground(0.0, 0.0, Vector3.UP, false)
		return
	var space := get_world_3d().direct_space_state
	var b := Basis(Vector3.UP, _vis_yaw)
	var dy_r := 0.0
	var dy_l := 0.0
	var n := Vector3.ZERO
	for side in 2:
		var fl := rig.foot_local(side)
		var p := global_position + b * Vector3(fl.x, 0.0, fl.z)
		_foot_q.from = p + Vector3(0, 0.55, 0)
		_foot_q.to = p - Vector3(0, 0.6, 0)
		var hit := space.intersect_ray(_foot_q)
		if not hit.is_empty():
			var dy := (hit["position"] as Vector3).y - global_position.y
			if side == 0:
				dy_r = dy
			else:
				dy_l = dy
			n += hit["normal"]
	rig.set_ground(dy_r, dy_l, n.normalized() if n.length() > 0.01 else Vector3.UP, true)


var _foot_q := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, 1)


func _feed_rig() -> void:
	_probe_feet()
	var hs := Vector2(velocity.x, velocity.z).length()
	if state == St.GRAPPLE or state == St.HANG:
		hs = 0.0
	rig.set_locomotion(hs, RUN_SPEED)
	rig.set_motion_state(motion_state)
	rig.set_vertical_speed(velocity.y)


func _process(delta: float) -> void:
	# the body turns with the blow's wind-up (magnetism) almost at once: a blow at a foe behind lands square
	var turn := 40.0 if (state == St.ATTACK or state == St.HEAVY or state == St.CHARGE) else 18.0
	_vis_yaw = lerp_angle(_vis_yaw, facing, 1.0 - exp(-delta * turn))
	_sync_visual(Engine.get_physics_interpolation_fraction())
	if Game.camera and is_instance_valid(Game.camera) and Game.camera.has_method("set_sprint"):
		Game.camera.call("set_sprint", sprinting and Vector2(velocity.x, velocity.z).length() > RUN_SPEED + 0.5)


func _sync_visual(frac: float) -> void:
	if rig == null:
		return
	rig.global_position = _prev_pos.lerp(_curr_pos, frac)
	rig.global_rotation = Vector3(0.0, _vis_yaw, 0.0)
