class_name HeroInput
extends RefCounted
## The hero's buttons, sampled once per physics tick (CORE), so every state reads the same consistent snapshot:
## held, pressed / released this tick, how long a button has been held and how long ago it was pressed.
## Tests and the arena bot drive the hero through `bot` (virtual buttons OR-ed with the real ones):
##   hero.inp.bot[&"attack"] = true   ... later ... hero.inp.bot[&"attack"] = false
## A press and its release can land in the same tick (a very short tap): pressed and released are then both true.
## The click that only captured the mouse (Game.capture_msec) never counts as an attack.

const ACTIONS: Array[StringName] = [&"attack", &"guard", &"chain", &"dodge", &"sprint", &"jump", &"interact", &"sprint_toggle"]

var held := {}
var pressed := {}
var released := {}
## Seconds the button has been held (0 while up).
var held_t := {}
## Seconds since the button was last pressed (large when never).
var since := {}
## Virtual buttons (tests, bot): action -> bool.
var bot := {}
var _bot_prev := {}
var _ignore_attack := false


func _init() -> void:
	for a in ACTIONS:
		held[a] = false
		pressed[a] = false
		released[a] = false
		held_t[a] = 0.0
		since[a] = 99.0
		bot[a] = false
		_bot_prev[a] = false


## `live`: real input counts (playing, not paused, the hero can act).
func sample(live: bool, delta: float) -> void:
	for a in ACTIONS:
		var real_held := live and Input.is_action_pressed(a)
		var real_p := live and Input.is_action_just_pressed(a)
		var real_r := Input.is_action_just_released(a)
		if a == &"attack":
			if real_p and Time.get_ticks_msec() - Game.capture_msec < 250:
				_ignore_attack = true
			if _ignore_attack:
				if not real_held:
					_ignore_attack = false
				real_held = false
				real_p = false
				real_r = false
		var b: bool = bot[a]
		var bp: bool = b and not _bot_prev[a]
		var br: bool = (not b) and _bot_prev[a]
		_bot_prev[a] = b
		var was: bool = held[a]
		var now := real_held or b
		var p := real_p or bp or (now and not was)
		var r := (was and not now) or (p and not now and (real_r or br))
		held[a] = now
		pressed[a] = p
		released[a] = r
		if p:
			since[a] = 0.0
			held_t[a] = 0.0
		else:
			since[a] = minf(float(since[a]) + delta, 99.0)
		if now:
			if not p:
				held_t[a] = float(held_t[a]) + delta
		elif not r:
			held_t[a] = 0.0


func is_held(a: StringName) -> bool:
	return held[a]


func just_pressed(a: StringName) -> bool:
	return pressed[a]


func just_released(a: StringName) -> bool:
	return released[a]


func hold_time(a: StringName) -> float:
	return held_t[a]


## Forget presses (state changes that must not inherit a stale press).
func consume(a: StringName) -> void:
	pressed[a] = false


## Releases every virtual button.
func bot_clear() -> void:
	for a in ACTIONS:
		bot[a] = false
