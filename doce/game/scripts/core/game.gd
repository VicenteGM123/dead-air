extends Node
## Global game state (autoload "Game"): phase, pause, feel helpers (hit-stop, camera shake, slow motion), the
## signals the UI listens to, references to the live scene, and the debug arguments.
##
## Contracts (docs/ARCHITECTURE.md): phase_changed, message, boss_started / boss_ended, labor_card, hero_died and
## lock_changed are the UI hooks; hitstop() and shake() are the combat feel helpers. set_phase() prints
## "DOCE phase <NAME>" and world_ready() prints "DOCE world ready in N ms" once: tools/web_test.mjs waits for them.
##
## Debug arguments: `godot --path . -- play=1 tod=day cam=fly pos=0,40,90 yaw=180 pitch=-20` (everything after
## "--"); on the web the page URL's query (?dev=1&play=1...) is read only when it contains dev=1, so players
## cannot change anything from the address bar.

signal phase_changed(phase: int)
signal message(text: String, sub: String, kind: String)
signal boss_started(boss_name: String, boss: Node)
signal boss_ended(victory: bool)
signal labor_card(index: int, title: String)
signal hero_died
signal lock_changed(target: Node)
signal paused_changed(paused: bool)

enum Phase { BOOT, TITLE, PLAY, DEAD, VICTORY }

## Engine.time_scale during a hit-stop: not 0, so code that divides by delta keeps working, but low enough that
## nothing visibly moves (a physics tick would need ~0.8 s of wall-clock time).
const HITSTOP_SCALE := 0.02

var args := {}
var phase := Phase.BOOT
var paused := false

# --- live scene (filled by main.gd; null in tools that do not create them) ----------------------------------
# Untyped on purpose: each stream's classes are called duck-typed through these (World API, Hero fields, ...).
var main = null # main.gd (or the arena)
var world = null # World (scripts/world/world.gd) or anything with the World API (tools/arena_world.gd)
var hero = null # Hero (scripts/player/hero.gd)
var camera = null # CameraRig (scripts/camera/camera_rig.gd)
var fx = null # Fx (scripts/fx/fx.gd)
var ui = null # root of the UI (scripts/ui/...), may be null
var hud = null # whatever answers screen_flash(color, seconds) (Fx.flash_screen), may be null
var tod = null # TimeOfDay
## Last altar the hero used (checkpoint), or null.
var checkpoint = null
## Time (Time.get_ticks_msec) of the last click that only captured the mouse: the hero ignores it as an attack.
var capture_msec := -100000

## Normal Engine.time_scale (slow motion, debug speed=N); hit-stop overrides it for a moment.
var time_scale_target := 1.0
var _hitstop_until_us := 0
var _slowmo_until_us := 0
var _slowmo_scale := 1.0
var _world_ready_done := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.has_feature("web"):
		_parse_web_args()
	if args.has("speed"):
		time_scale_target = clampf(float(args["speed"]), 0.1, 8.0)


## URL query arguments (?dev=1&play=1&tod=day...) are test switches, honoured only when the query has dev=1.
func _parse_web_args() -> void:
	var q: Variant = JavaScriptBridge.eval("window.location.search", true)
	if not (q is String) or (q as String).length() <= 1:
		return
	var parsed := {}
	for part in (q as String).substr(1).split("&", false):
		var kv := part.split("=", true, 1)
		parsed[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else "1"
	if String(parsed.get("dev", "0")) != "1":
		return
	for k in parsed:
		args[k] = parsed[k]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- debug arguments ---------------------------------------------------------------------------------------

func arg(key: String, default: Variant = null) -> Variant:
	return args.get(key, default)


func has_arg(key: String) -> bool:
	return args.has(key)


func arg_f(key: String, default: float) -> float:
	return float(args[key]) if args.has(key) else default


## "x,y,z" -> Vector3 (missing or malformed: `default`).
func arg_vec3(key: String, default: Vector3 = Vector3.ZERO) -> Vector3:
	if not args.has(key):
		return default
	var p := String(args[key]).split(",")
	if p.size() < 3:
		return default
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func arg_on(key: String) -> bool:
	return String(args.get(key, "0")) in ["1", "true", "yes", "on"]


# --- phases ------------------------------------------------------------------------------------------------

func set_phase(p: int) -> void:
	phase = p
	# Stable marker for the automated web test (tools/web_test.mjs).
	print("DOCE phase %s" % phase_name(p))
	phase_changed.emit(p)


func phase_name(p: int = -1) -> String:
	return Phase.keys()[phase if p < 0 else p]


func is_playing() -> bool:
	return phase == Phase.PLAY and not paused


## Prints "DOCE world ready in N ms" (once per run; the web test and the shell wait for it).
func world_ready(ms: int) -> void:
	if _world_ready_done:
		return
	_world_ready_done = true
	print("DOCE world ready in %d ms" % ms)


func say(text: String, sub: String = "", kind: String = "info") -> void:
	message.emit(text, sub, kind)


func set_paused(on: bool) -> void:
	if on == paused:
		return
	paused = on
	get_tree().paused = on
	if on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_changed.emit(on)


# --- feel --------------------------------------------------------------------------------------------------

## Freezes the world for `seconds` of wall-clock time (heavy hits, parries). Overlapping calls extend it.
func hitstop(seconds: float) -> void:
	_hitstop_until_us = maxi(_hitstop_until_us, Time.get_ticks_usec() + int(seconds * 1e6))
	Engine.time_scale = HITSTOP_SCALE


## Camera shake: adds trauma (0..1) to the camera rig; the shake grows with trauma squared and decays by itself.
func shake(trauma: float) -> void:
	if camera and is_instance_valid(camera) and camera.has_method("add_trauma") and bool(Settings.get_v("shake")):
		camera.call("add_trauma", trauma)


## Slow motion at `scale` for `seconds` of wall-clock time (finishers, the lion's defeat).
func slowmo(scale: float, seconds: float) -> void:
	_slowmo_scale = clampf(scale, 0.05, 1.0)
	_slowmo_until_us = Time.get_ticks_usec() + int(seconds * 1e6)


func in_hitstop() -> bool:
	return Time.get_ticks_usec() < _hitstop_until_us


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ts := time_scale_target
	if now < _slowmo_until_us:
		ts *= _slowmo_scale
	if now < _hitstop_until_us:
		ts = HITSTOP_SCALE
	if not is_equal_approx(Engine.time_scale, ts):
		Engine.time_scale = ts
