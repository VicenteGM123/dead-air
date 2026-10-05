# Game: owns every system, the frame loop, the state machine, launch params and time (port of src/core/game.js;
# ARCHITECTURE §0/§3, GDD §18.12). It is the script of the root node of res://main.tscn.
#
# Construction order = the §3 field list; init() runs once in INIT_ORDER, reset() on every newGame(), update(dt)
# in UPDATE_ORDER while the state is 'playing' or 'down'. Each call is isolated by name: a missing system (file
# absent or failing to load) or a missing method is simply skipped, and a GDScript runtime error inside a system
# aborts only that call (Godot logs it and the game keeps running).
#
# time = { now, dt, realNow, realDt, frame, scale }: realDt is the clamped (<= 1/20 s) frame time; world systems
#   get dt = realDt * scale (0 while paused, during hitStop() or when scale = 0 for commercials / Instant Replay).
#   The player's animation, the camera, audio and UI use realDt. REAL_DT lists the systems updated with realDt.
# API: boot(), newGame(heroId), setState(s), pause(), resume(), gameOver(summary?), victory(), hitStop(seconds), rand(),
#   frameYield() (await it inside a system's initSteps() coroutine to give a frame back), loaded (false while the
#   real boot still loads the station behind the title), loadProgress (0..1 estimate of that load, the title's
#   loading bar), events 'game:loaded', params, state, time, ready, stats { fps, frameMs, drawCalls, triangles,
#   zombies, pixelRatio } (every 0.5 s), cards (the broadcast-card namespace, set by scripts/gfx/cards.gd),
#   mpPaused (MP pause overlay is up), net_gameOver(summary) (MP game over, sent by the host).
# Systems are plain objects (extends RefCounted) built as <script>.new(game); they may expose initSteps() as a
# coroutine (await game.frameYield() between steps) to split a long init across frames (level does).
# Machines constructs the machine sub-systems (screens, signon, telly, sponsors, uplink); Game drives each of
# their lifecycles as its own isolated system right after `machines`. The Boss constructs game.ending.
# Launch params (the JS URL params, e.g. ?test=1&char=roxy&power=1): pass them after `--` on the command line
#   godot --path godot -- test=1 char=roxy power=1
# or put them in the project setting application/run/da_params (same "k=v k2=v2" syntax) while testing in the editor.
# Three.js engine plumbing that Godot does itself (shader precompile / warm-up draws, render stats) is not ported.
# MP: `net` (scripts/net/net.gd, online co-op, MP_SPEC §3) is a system right after `input`; Game calls net.update()
#   FIRST and net.lateUpdate() LAST every frame, in every state. Every MP path below is guarded by net.inGame /
#   net.active, so with no session (net.active false) the solo game runs exactly the old code.
#   Time (§3.4): in an MP game (net.inGame) every system gets dt = realDt — time.scale and hitStop() are local
#   presentation then and never freeze the shared world (time.dt / time.now follow realDt).
#   Pause: pause() in an MP game only sets mpPaused (input / player read it), releases the mouse and shows the pause
#   card; game.state stays 'playing'; resume() clears it. Leaving / losing the session clears it too.
#   newGame(hero) in MP (net.inGame is already true while the systems reset): net.onNewGame() moves the local player
#   to its spawn slot and builds the remote players before 'playing' / game:start. Clients run with the host's world
#   params (power, doors, round, nozombies, points, area: net.gd applies them to `params`).
#   gameOver(summary = null): in MP host-only — broadcasts net_gameOver(summary) (default net.teamSummary()) to every
#   peer; a client's call is ignored. victory() stays a local state change.
#   Test boot (test=1 + mp=host|join, §9): everything is initialized, then net.autoBoot() hosts / joins, every peer
#   auto-readies and the host starts at mpstart=N players; no menus.
class_name DAGame
extends Node

static var inst: DAGame = null

const MAX_DT := 1.0 / 20.0
const STATS_EVERY := 0.5
const WORLD_STATES := ["playing", "down"]

const INIT_ORDER := ["render", "tex", "mats", "lights", "input", "net", "audio", "fx", "props", "level", "nav", "player", "cam",
	"weapons", "wonder", "zombies", "rounds", "economy", "machines", "screens", "signon", "telly", "sponsors", "uplink", "perks",
	"powerups", "egg", "boss", "interact", "hud", "menu", "debug"]
const UPDATE_ORDER := ["input", "player", "nav", "weapons", "wonder", "zombies", "rounds", "level", "machines", "screens",
	"signon", "telly", "sponsors", "uplink", "perks", "powerups", "egg", "boss", "interact", "fx", "cam", "audio", "hud"]
const LATE_ORDER := ["player", "weapons", "zombies", "level", "screens", "fx", "hud"]
const REAL_DT := ["input", "cam", "audio", "hud"]
# Updated in every state (real dt): UI and debug cameras keep working in menus, pause and game over.
const ALWAYS := ["menu", "debug"]

# system name -> script path. Order = construction order (game.js constructor). `props` (the prop library loader,
# scripts/props/props.gd) and `wonder` (installed by main.js in the web build) are ordinary systems here.
const SYSTEMS := [
	["render", "res://scripts/core/render.gd"],
	["tex", "res://scripts/core/textures.gd"],
	["mats", "res://scripts/core/materials.gd"],
	["lights", "res://scripts/core/lights.gd"],
	["input", "res://scripts/core/input.gd"],
	["net", "res://scripts/net/net.gd"],
	["audio", "res://scripts/audio/audio.gd"],
	["fx", "res://scripts/fx/fx.gd"],
	["props", "res://scripts/props/props.gd"],
	["level", "res://scripts/world/level.gd"],
	["nav", "res://scripts/world/nav.gd"],
	["interact", "res://scripts/core/interact.gd"],
	["player", "res://scripts/actors/player.gd"],
	["cam", "res://scripts/actors/camera.gd"],
	["weapons", "res://scripts/game/weapons.gd"],
	["wonder", "res://scripts/game/wonder.gd"],
	["zombies", "res://scripts/actors/zombies.gd"],
	["rounds", "res://scripts/game/rounds.gd"],
	["economy", "res://scripts/game/economy.gd"],
	["machines", "res://scripts/game/machines.gd"],
	["perks", "res://scripts/game/perks.gd"],
	["powerups", "res://scripts/game/powerups.gd"],
	["egg", "res://scripts/game/easteregg.gd"],
	["boss", "res://scripts/actors/boss.gd"],
	["hud", "res://scripts/ui/hud.gd"],
	["menu", "res://scripts/ui/menu.gd"],
	["debug", "res://scripts/core/debug.gd"],
]

var params := {}
var seed_value := 0
var _rng: Callable
var events
var state := "boot"
var time := {"now": 0.0, "dt": 0.0, "realNow": 0.0, "realDt": 0.0, "frame": 0, "scale": 1.0}
var ready_flag := false          # game.js `ready` (first frame rendered)
var loaded := false              # every system initialized (see boot())
var loadProgress := 0.0          # 0..1 estimate of the real boot's load behind the title (menu's loading bar)
var loadStats := {"steps": []}
var stats := {"fps": 0, "frameMs": 0.0, "drawCalls": 0, "triangles": 0, "zombies": 0, "pixelRatio": 1.0}
var heroId = null
var cards = null                 # set by scripts/gfx/cards.gd (the broadcast-card namespace)

# systems (null until constructed; any of them may be missing while the port is incomplete)
var render
var scene: Node3D                # render.scene (the 3D world root)
var camera: Camera3D             # render.camera (the gameplay camera)
var tex
var mats
var lights
var input
var net
var audio
var fx
var props
var level
var nav
var interact
var player
var cam
var weapons
var wonder
var zombies
var rounds
var economy
var machines
var screens
var signon
var telly
var sponsors
var uplink
var perks
var powerups
var egg
var boss
var ending
var hud
var menu
var debug

var _loading := false
var _inited := {}
var _hitStop := 0.0
var _statT := 0.0
var _statFrames := 0
var _statMs := 0.0
var _pausedFrom := "playing"
var _booted := false
var mpPaused := false            # MP pause overlay (pause() in an MP game; game.state stays 'playing')
var _profOn := false
var _hitchMs := 0.0              # QA param hitch=<ms>: log every frame longer than that (see _hitch)
var _hitchLast := 0
var _hitchCalls := {}
var _hitchScript := 0.0

func _init() -> void:
	inst = self
	if OS.has_feature("web"):
		_mountWebPacks()
	params = _parseParams()
	_profOn = params.has("prof")
	if params.has("hitch"):
		_hitchMs = float(params.hitch) if float(params.hitch) > 1.0 else 100.0
	seed_value = int(params.seed) if params.has("seed") and (params.seed is int or params.seed is float) else randi() % 2147483648
	_rng = Rng.mulberry32(seed_value)
	events = preload("res://scripts/core/events.gd").new()
	DACards.install(self)   # game.cards: the broadcast-card namespace (scripts/gfx/cards.gd)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(preload("res://scripts/core/vcolor_parity.gd").new())  # WebGL: vertexColors on colorless geometry reads black
	for entry in SYSTEMS:
		_make(entry[0], entry[1])
		if entry[0] == "render" and render != null:
			scene = render.get("scene")
			camera = render.get("camera")
	boot()

# Web build: the game data is split in two packs (GitHub Pages' 100 MB file limit, godot/web/export_web.sh): the
# HTML shell (godot/web/shell.html) copies <exe>.props.pck next to the main pack; mount it before anything loads.
func _mountWebPacks() -> void:
	for name in ["index.props.pck"]:
		var ok := false
		for path in [name, "/" + name, OS.get_executable_path().get_base_dir().path_join(name)]:
			if FileAccess.file_exists(path) and ProjectSettings.load_resource_pack(path):
				ok = true
				break
		if not ok:
			push_error("[web] resource pack %s missing: props won't load" % name)

func rand() -> float:
	return _rng.call()

func _make(name: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("[game] system '%s' missing (%s)" % [name, path])
		return
	var script = load(path)
	if script == null or not script.can_instantiate():
		push_error("[game] system '%s' failed to load (%s)" % [name, path])
		return
	set(name, script.new(self))

# JS URL params: "k=v" pairs from the command line (after --) or the application/run/da_params project setting.
# Numeric values become numbers, a bare key (or "k=") is 1, like game.js parseParams.
func _parseParams() -> Dictionary:
	var out := {}
	var items: Array = []
	var extra = ProjectSettings.get_setting("application/run/da_params", "")
	if extra is String and extra != "":
		items.append_array(extra.split(" ", false))
	items.append_array(OS.get_cmdline_user_args())
	for raw in items:
		var s: String = raw.trim_prefix("--").trim_prefix("?")
		for kv in s.split("&", false):
			var k := kv
			var v := ""
			var i := kv.find("=")
			if i >= 0:
				k = kv.substr(0, i)
				v = kv.substr(i + 1)
			if v == "":
				out[k] = 1
			elif v.is_valid_int():
				out[k] = int(v)
			elif v.is_valid_float():
				out[k] = float(v)
			else:
				out[k] = v
	return out

# Resolves after the next frame (the title keeps animating between load steps).
func frameYield() -> void:
	await get_tree().process_frame

func _prog(p: float) -> void:
	if p > loadProgress:
		loadProgress = minf(1.0, p)

# Real boot (no test/shot param): the title shows as soon as the living room is built, and the station loads
# BEHIND it, one step per frame (_load). Meanwhile `loaded` is false and the menu ignores input ('PLEASE STAND
# BY'); systems not initialized yet are not updated. test/shot boots load everything first and start straight
# into play.
func boot() -> void:
	if params.get("test") or params.get("shot"):
		for name in INIT_ORDER:
			_initSystem(name)
		setState("menu")
		# MP test boot (MP_SPEC §9): no menus — net hosts / joins, every peer auto-readies, the host starts the game at
		# mpstart=N players (the first newGame comes with the start message). The zombie model pools are built now (as
		# _load does) so the start frame stays short.
		if params.get("test") and params.get("mp") != null and net != null:
			_call("zombies", "reset")
			loaded = true
			_booted = true
			net.autoBoot()
			return
		newGame(params.get("char"))
		loaded = true
		_booted = true
		return
	_loading = true
	_call("menu", "showLoading")
	for name in INIT_ORDER.slice(0, INIT_ORDER.find("level")):
		_initSystem(name)
	setState("menu")
	_call("menu", "showTitle")
	_booted = true
	await _load()
	_loading = false
	_prog(1.0)
	loaded = true
	events.emit("game:loaded", {})

func _initSystem(name: String) -> void:
	_call(name, "init")
	_inited[name] = true

func _load() -> void:
	var rest := INIT_ORDER.filter(func(n): return not _inited.has(n))
	_prog(0.02)
	for name in rest:
		await frameYield()
		var sys = get(name)
		if name != "level":
			_prog(0.25 + 0.08 * (float(rest.find(name)) / rest.size()))
		if sys != null and sys.has_method("initSteps"):
			await sys.initSteps()
			_inited[name] = true
		else:
			_initSystem(name)
		if name == "level":
			_prog(0.25)
	# zombies.reset() fills the model pools that newGame's reset would otherwise build; it is idempotent.
	await frameYield()
	_call("zombies", "reset")
	_prog(0.35)
	# The character-select channel sets (heroes, promo cards, props), built once now instead of on the key press.
	if menu != null and menu.has_method("preloadSteps"):
		await menu.preloadSteps()
	_prog(0.9)
	# Compatibility renderer (web): compile every shader the game will draw now, behind the title (warmup.gd)
	var Warm = load("res://scripts/gfx/warmup.gd") if ResourceLoader.exists("res://scripts/gfx/warmup.gd") else null
	if Warm != null and Warm.wanted(self):
		await frameYield()
		await Warm.new(self).run()
	_prog(0.95)

# Resets every system and starts a run (Rounds schedules round 1, or params.round, T.rounds.firstRoundDelay later).
func newGame(requested = null) -> void:
	var hero_ids: Array = []
	var default_hero := "duke"
	if ResourceLoader.exists("res://scripts/actors/heroes.gd"):
		var H = load("res://scripts/actors/heroes.gd")
		if H != null:
			for h in H.HEROES:
				hero_ids.append(h.id)
			default_hero = H.DEFAULT_HERO
	var id = requested if hero_ids.has(requested) else default_hero
	heroId = id
	_rng = Rng.mulberry32(seed_value)
	time.now = 0.0
	time.dt = 0.0
	time.scale = 1.0
	_hitStop = 0.0
	if player != null and player.has_method("setHero"):
		player.setHero(id)
	for name in INIT_ORDER:
		_call(name, "reset")
	if params.get("power"):
		if machines != null:
			machines.setPower(true)
	if params.get("doors"):
		if level != null:
			level.openAllDoors()
	if params.get("nozombies"):
		if rounds != null:
			rounds.pauseSpawning(true)
	mpPaused = false
	if net != null and net.inGame:
		net.onNewGame()   # MP: spawn slot + remote players (scripts/net/net.gd)
	setState("playing")
	events.emit("game:start", {"heroId": id})
	if input != null:
		input.requestLock()

func setState(s: String) -> void:
	if s == state:
		return
	var from := state
	state = s
	events.emit("state", {"from": from, "to": s})

func pause() -> void:
	if net != null and net.inGame:
		# MP: the pause card is an overlay; the shared world keeps running and game.state does not change
		if mpPaused or not WORLD_STATES.has(state):
			return
		mpPaused = true
		if input != null:
			input.exitLock()
		_call("menu", "showPause")
		return
	if not WORLD_STATES.has(state):
		return
	_pausedFrom = state
	setState("paused")
	if input != null:
		input.exitLock()
	_call("menu", "showPause")

func resume() -> void:
	if mpPaused:
		mpPaused = false
		_call("menu", "hidePause")
		if input != null and WORLD_STATES.has(state):
			input.requestLock()
		return
	if state != "paused":
		return
	_call("menu", "hidePause")
	setState(_pausedFrom)
	if input != null:
		input.requestLock()

# Lethal damage without Instant Replay (GDD §6.5). The menu plays the tape-stop / CRT collapse / stand-by card.
# MP: the host decides (every player down / off-air: mp-players) and every peer runs net_gameOver with its summary.
func gameOver(summary = null) -> void:
	if state == "gameover" or state == "victory":
		return
	if net != null and net.inGame:
		if net.isHost:
			net.everyone("game", "gameOver", [summary if summary is Dictionary else net.teamSummary()])
		return
	_gameOver({"round": rounds.round if rounds else 0, "kills": rounds.totalKills if rounds else 0, "points": economy.points if economy else 0})

# MP game over broadcast by the host (net.everyone("game", "gameOver", [summary])).
func net_gameOver(summary = null) -> void:
	if net == null or net.sender != 1 or state == "gameover" or state == "victory":
		return
	_gameOver(summary if summary is Dictionary else {})

func _gameOver(summary: Dictionary) -> void:
	mpPaused = false
	setState("gameover")
	if input != null:
		input.exitLock()
	events.emit("game:over", summary)
	_call("menu", "showGameOver", summary)

func victory() -> void:
	if state == "gameover" or state == "victory":
		return
	var summary := {"round": rounds.round if rounds else 0}
	setState("victory")
	if input != null:
		input.exitLock()
	events.emit("game:victory", summary)
	_call("menu", "showVictory", summary)

# Freezes world systems for `seconds` of real time (headshot pops, big hits). Overlapping calls keep the longest.
func hitStop(seconds: float) -> void:
	_hitStop = maxf(_hitStop, seconds)

# Exit: break the systems' reference cycles and static caches and free the off-tree Node pools so the engine quits
# fast and without leak reports (scripts/core/teardown.gd).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if net != null and net.has_method("shutdown"):
			net.shutdown()   # MP: bye + close the transport, join the UPnP thread
		var t0 := Time.get_ticks_msec()
		var st: Dictionary = preload("res://scripts/core/teardown.gd").run(self)
		print_verbose("[game] teardown: %d objects scrubbed, %d orphan nodes freed in %d ms" % [st.objects, st.orphans, Time.get_ticks_msec() - t0])
		if inst == self:
			inst = null

func _process(delta: float) -> void:
	if not _booted:
		return
	_tick(delta)

func _tick(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _hitchMs > 0.0:
		_hitch(t0)
	var realDt := clampf(delta, 0.0, MAX_DT)
	time.realDt = realDt
	time.realNow += realDt
	time.frame += 1
	# MP: receive first, in every state (a handler may start or end the game this very frame)
	_call("net", "update", realDt)
	var world := WORLD_STATES.has(state)
	var scale: float = time.scale
	if _hitStop > 0.0:
		_hitStop = maxf(0.0, _hitStop - realDt)
		scale = 0.0
	var dt := realDt * scale if world else 0.0
	# MP (MP_SPEC §3.4): the shared world never freezes — time.scale / hitStop stay local presentation
	if world and net != null and net.inGame:
		dt = realDt
	time.dt = dt
	time.now += dt

	if world:
		for name in UPDATE_ORDER:
			_call(name, "update", realDt if REAL_DT.has(name) else dt)
		for name in LATE_ORDER:
			_call(name, "lateUpdate", dt)
	else:
		_call("input", "update", realDt)
		if _inited.has("hud"):
			_call("hud", "update", realDt)
	# while the station loads behind the title only the systems initialized so far are updated (the menu always)
	for name in ALWAYS:
		if name == "menu" or _inited.has(name):
			_call(name, "update", realDt)
	_call("lights", "update", realDt)
	_call("mats", "update", realDt)
	_call("tex", "update", realDt)
	_call("net", "lateUpdate", realDt)   # MP: send (the local player's state stream)
	if _call("render", "frame", realDt):
		ready_flag = true
	_updateStats(realDt, (Time.get_ticks_usec() - t0) / 1000.0)
	if _hitchMs > 0.0:
		_hitchScript = (Time.get_ticks_usec() - t0) / 1000.0
	if _profOn:
		_prof["_tick"] = _prof.get("_tick", 0.0) + float(Time.get_ticks_usec() - t0)
		_profReport(realDt)

func _updateStats(realDt: float, ms: float) -> void:
	_statT += realDt
	_statFrames += 1
	_statMs += ms
	if _statT < STATS_EVERY:
		return
	stats.fps = int(round(_statFrames / _statT))
	stats.frameMs = round((_statMs / _statFrames) * 100.0) / 100.0
	stats.drawCalls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	stats.triangles = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	stats.zombies = zombies.alive.size() if zombies != null and zombies.get("alive") != null else 0
	_statT = 0.0
	_statFrames = 0
	_statMs = 0.0

# QA param prof=<s> (Godot-only): accumulates the wall time of every system call and prints, every <s> seconds
# (default 5) of real time, fps / frame time / draw calls / zombies and the costliest system calls in ms per frame.
var _prof := {}
var _profWall0 := 0
var _profFrames := 0

func _profReport(_realDt: float) -> void:
	# wall-clock frame time (time.realDt is clamped to MAX_DT, so it cannot measure slow frames)
	var now := Time.get_ticks_usec()
	if _profWall0 == 0:
		_profWall0 = now
	_profFrames += 1
	var wall := float(now - _profWall0) / 1e6
	var every := float(params.prof) if float(params.prof) >= 1.0 else 5.0
	if wall < every:
		return
	var rows: Array = []
	for k in _prof:
		rows.append([k, _prof[k] / 1000.0 / _profFrames])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var parts: PackedStringArray = []
	for r in rows.slice(0, 14):
		parts.append("%s %.2f" % [r[0], r[1]])
	print("[prof] t=%.0f fps=%.2f frameMs=%.2f scriptMs=%.2f draws=%d tris=%d zombies=%d | %s" % [Time.get_ticks_msec() / 1000.0,
		_profFrames / wall, 1000.0 * wall / _profFrames, _prof.get("_tick", 0.0) / 1000.0 / _profFrames, stats.drawCalls,
		stats.triangles, stats.zombies, ", ".join(parts)])
	_prof.clear()
	_profWall0 = now
	_profFrames = 0

# QA param hitch=<ms> (Godot-only, also in the web build: ?hitch=<ms>): prints every frame whose wall time (tick to
# tick) exceeds <ms>, with the previous tick's script time and its costliest system calls; the rest of the frame is
# the engine (drawing: first-use shader / pipeline compiles, texture uploads, other nodes' _process).
func _hitch(nowUs: int) -> void:
	if _hitchLast > 0:
		var d := (nowUs - _hitchLast) / 1000.0
		if d > _hitchMs:
			var rows: Array = []
			for k in _hitchCalls:
				rows.append([k, _hitchCalls[k] / 1000.0])
			rows.sort_custom(func(a, b): return a[1] > b[1])
			var parts: PackedStringArray = []
			for r in rows.slice(0, 6):
				if r[1] >= 1.0:
					parts.append("%s %.0f" % [r[0], r[1]])
			print("[hitch] t=%.2f frame=%d ms=%.0f script=%.0f state=%s menu=%s | %s" % [nowUs / 1e6, time.frame, d,
				_hitchScript, state, str(menu.get("mode")) if menu != null else "-", ", ".join(parts)])
	_hitchLast = nowUs
	_hitchCalls.clear()

# Calls system[method](arg) if it exists. Returns true when the method exists and was called.
func _call(name: String, method: String, arg = null) -> bool:
	var sys = get(name)
	if sys == null or not (sys is Object) or not sys.has_method(method):
		return false
	if _profOn or _hitchMs > 0.0:
		var t0 := Time.get_ticks_usec()
		_callRaw(sys, method, arg)
		var k := name + "." + method
		var us := float(Time.get_ticks_usec() - t0)
		if _profOn:
			_prof[k] = _prof.get(k, 0.0) + us
		if _hitchMs > 0.0:
			_hitchCalls[k] = _hitchCalls.get(k, 0.0) + us
		return true
	_callRaw(sys, method, arg)
	return true

func _callRaw(sys, method: String, arg) -> void:
	if arg == null:
		if sys.get_method_argument_count(method) > 0:
			sys.call(method, null)
		else:
			sys.call(method)
	else:
		sys.call(method, arg)
