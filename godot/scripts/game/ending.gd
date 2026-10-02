# THE SIGN-OFF ENDING + THE MORNING SHOW (GDD §13 step 6 "Defeat and ending", "Rewards"). Port of src/game/ending.js.
# Owner: boss + ending engineer. Constructed and driven by scripts/actors/boss.gd (game.ending); game.gd does not know
# this file.
#
# TIMELINE (seconds from the Baron's defeat; skippable after 5 s once it has been seen: Space / Enter / E / pad A)
#   0     he freezes; his screen shows the teary "goodnight" face and he waves (boss.goodnight); the Sign-Off hymn
#         swells (sting_signoff_hymn + boss_goodnight); a slow cinematic push-in on the gameplay camera.
#   3.0   his TV head collapses into a white line, then a dot (boss.collapseHead); 3.4 the WHOLE view collapses
#         (render.post.collapse 0 -> 1).
#   4–7   black; the dot lingers, grows two tiny eyes and winks.
#   7–17  the cozy 1977 living room at night (menu.getLivingRoom(), the character-select room): a kid asleep on the
#         couch in the WZTV "13" cap with a popcorn bowl; the camera dollies back from the console TV (the sign-off
#         film on its screen): it's Telly. Its rabbit ears twitch, a tiny sleepy hop, the glove waves goodnight,
#         and it switches itself off to a white dot.
#   17–20 3.0 s of total silence (audio.stopAll + music 'silence').
#   20–32 a 70s end-credit crawl over a chrome "13" ident ("Starring <your hero>", the other three, the guests,
#         "and WZTV Channel 13"), funk end theme (music 'credits').
#   31–35 your hero in their commercial pose on their show's backdrop -> at 32.0 a SEPIA FREEZE-FRAME.
#   35    STAY TUNED?  (Y / N)  -> game.victory() (emits game:victory {round}; the menu stays out of the way while
#         ending.active).  Y = the Morning Show, N = menu.showResults(summary, 'GOOD NIGHT') then the title.
# PERSISTENT UNLOCK: "deadair.signoff" = "1" in user://deadair.cfg (localStorage in the JS; set when the ending starts).
# MORNING SHOW (Y): back in the Yard at dawn (sky #FF7E5F -> #FFE3A3, warm low sun from the east with long shadows,
#   warmer ambient in every area, warm light pools under every window), every clock reads 12:00, music
#   'morning'; all five sponsors free + permanent in gold leaf (perks.morningShow), both held weapons uplinked for
#   free (or refilled if already upgraded), +13,013 points, Telly never signs off again and pulls cost 13 (the
#   machine_telly interactable is wrapped: 13-point prompt, forced non-sign-off outcomes), the run continues from the
#   next round. Emits game:morning {round}.
# API (game.ending)
#   active (from play() until the Y/N choice)  playing (alias)  running  stage  t  seen  morning (bool)
#   play({ round })  update(realDt) (boss.update calls it)  stop()  reset()  morningShow()  results()
#   timeScale (tests: 0 holds the sequence on one frame)  debugPlay({ round })  debugSeek(t)  debugChoose('y'|'n')
#   debugState()
#   padButton(name) -> used (input.gd, Xbox pad): A skips (same rule as the keys); on the card A = YES, B = NO. The
#   card's key caps read A / B while the pad is the last input device (input:device).
#
# PORT NOTES
#   The DOM overlay (.de-end: the 2D canvas, warm vignette, photo frame, white flash, the STAY TUNED? card) is a
#   CanvasLayer (layer 18 = the CSS z-index) with Controls; CSS transitions are replayed by the Overlay control
#   (same durations and timing functions). The 2D canvas is a DACanvas (scripts/gfx/canvas2d.gd); canvas code is a
#   line-by-line port. The window keydown listener (capture) is a KeyCatcher node (_input) living while the sequence
#   runs. The CSS sepia filter on the WebGL canvas is a screen-reading ColorRect under the overlay (same filter math).
#   The portrait scene (JS: render.renderPass.scene/camera swapped) renders in its own World3D: an HDR SubViewport
#   like render.view that feeds render.grade (tDiffuse) while it shows, so it gets the same post (bloom, grade,
#   grain, saturation); its camera carries render.gd's CAM_FULLCOLOR flag (the JS full-colour uniforms uSatEnv 1,
#   uAmber 0, uWaveRadius -1, uHeroFade 1) and CAM_NOFOG. setTimeout -> SceneTreeTimer. localStorage -> ConfigFile (section "",
#   key "deadair.signoff"). The kid's popcorn bowl, Telly's side-arm hatch and the portrait's backdrop/floor are the
#   Blender runtime asset blender/runtime/ending.py -> assets/runtime/ending/ending.glb.
# MP (online co-op, RECONCILE R14/R20; guarded by _mp(), solo unchanged): every peer plays the whole sequence LOCALLY
#   for its own player (its own hero stars in the credits and the portrait; the local skip rule stays per peer). The
#   host's boss sends net.teamSummary() with the defeat (play({round, summary})): the results card shows the team.
#   Credits add an "AT THE CONTROLS" block (each player's name as their hero); CO-STARRING lists the session's heroes
#   first. The local player is held with player.lock / protect("ending") (keyed MP locks).
#   STAY TUNED? is the HOST's call: a client reaching its card sends net_atCard; the host's YES / NO light up once every
#   connected peer is at its card or CARD_GRACE s after the host's own card; until then (and always on clients) the
#   buttons are dimmed with a caption. The host's choice goes to everyone (net_choose) and applies at ANY stage (a
#   client still in its cinematic jumps to the result). Y = the Morning Show on every peer: each player teleports to
#   its MORNING_SPOTS slot, heal / perks / uplinks locally, economy.add(13013, "morning") (a team reason: the host's
#   call pays everybody, clients' calls are ignored), only the host starts the next round; the wrapped Telly pull
#   passes cost 13 (mp-machines turns it into the host request and re-rolls on the host). N = menu.showResults(team
#   summary, GOOD NIGHT); dismissing it returns the session to the lobby (mp-menu / net.endGame).
#   MESSAGES (sys "ending"): client -> host: atCard () · host -> everyone: choose (c: 'y' | 'n'). No game.victory()
#   broadcast: it stays a local state change on each peer at its card.
extends RefCounted

const KEY := "deadair.signoff"
const CFG := "user://deadair.cfg"
const CFG_SECTION := ""
const E := {
	"head": 3.0, "view": 3.4, "black": 4.0, "eyes": 4.8, "wink": 5.8, "room": 7.0, "face": 10.4, "ears": 10.9, "hop": 11.8, "glove": 12.6,
	"wave": 12.9, "waveEnd": 15.0, "gloveIn": 15.15, "off": 15.6, "roomOut": 16.7, "silence": 17.0, "credits": 20.0, "portrait": 30.6,
	"freeze": 32.0, "card": 35.0, "skipAfter": 5.0,
}
const MORNING_BONUS := 13013
const TELLY_MORNING_COST := 13
const SIGNALS := ["hot_mic", "laugh_track", "cold_open"]
const CARD_GRACE := 25.0             # MP: the host's buttons light up at the latest this long after its own card
const MORNING_SPOTS := [Vector2(41.2, -9.6), Vector2(41.2, -8.4), Vector2(41.2, -10.8), Vector2(40.0, -9.6)]
const TAU := PI * 2.0
const ENDING_GLB := "res://assets/runtime/ending/ending.glb"
const FONT_FILES := {"logo": "res://assets/fonts/Shrikhand.woff", "hud": "res://assets/fonts/TitanOne.woff"}
const FONTS_JS := {"hud": "\"Titan One\", \"Arial Black\", sans-serif", "logo": "\"Shrikhand\", \"Georgia\", serif"}

static func smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func easeInOut(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

static func easeOutBack(x: float, s: float = 1.7) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

static func storeGet(k: String):
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return null
	if not cf.has_section_key(CFG_SECTION, k):
		return null   # get_value with a null default logs an error for a missing key
	var v = cf.get_value(CFG_SECTION, k)
	return null if v == null else str(v)

static func storeSet(k: String, v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value(CFG_SECTION, k, v)
	cf.save(CFG)

# JS FONTS (ui/fonts.js) as CSS font-family lists for the canvas (scripts/ui/fonts.gd when present).
static func fonts() -> Dictionary:
	if ResourceLoader.exists("res://scripts/ui/fonts.gd"):
		var F = load("res://scripts/ui/fonts.gd")
		if F != null:
			var c: Dictionary = F.get_script_constant_map()
			if c.get("FONTS") is Dictionary:
				return c.FONTS
	return FONTS_JS

# ------------------------------------------------------------------------------------------------ foreign glue
static func _gp(o, k: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		return o.get(k, def)
	if o is Object:
		if not is_instance_valid(o):
			return def
		var v = o.get(k)
		return def if v == null else v
	return def

static func _sp(o, k: String, v) -> void:
	if o is Dictionary:
		o[k] = v
	elif o is Object and is_instance_valid(o):
		o.set(k, v)

static func _path(o, keys: Array):
	for k in keys:
		o = _gp(o, k)
		if o == null:
			return null
	return o

static func _fc(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Object:
		if not is_instance_valid(o):
			return null
		if o.has_method(m):
			return o.callv(m, args)
		var v = o.get(m)
		if v is Callable and v.is_valid():
			return v.callv(args)
		return null
	if o is Dictionary:
		var f = o.get(m)
		if f is Callable and f.is_valid():
			return f.callv(args)
	return null

static func _hasFn(o, m: String) -> bool:
	if o == null:
		return false
	if o is Object:
		return is_instance_valid(o) and (o.has_method(m) or o.get(m) is Callable)
	if o is Dictionary:
		return o.get(m) is Callable
	return false

# Accumulated transform of a node (global_transform when it is inside the tree).
static func _xf(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.global_transform
	var t := n.transform
	var p := n.get_parent()
	while p != null:
		if p is Node3D:
			if (p as Node3D).is_inside_tree():
				return (p as Node3D).global_transform * t
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

# object3d.position = p; object3d.lookAt(target) (-Z toward the target, +Y up), as a local transform.
static func _lookXf(p: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - p, Vector3.UP), p)

# ------------------------------------------------------------------------------------------------ credits art
# Chrome "13" ident: extruded bronze layers, a thick ink outline, a mirror-chrome gradient face, star glints.
func chromeIdent():
	var W := 900
	var H := 640
	var c = _newCanvas(W, H, "now")
	var x = c.getContext("2d")
	var font := "470px %s" % FONTS.logo
	x.font = font
	x.textAlign = "center"
	x.textBaseline = "middle"
	var cx := W / 2.0
	var cy := H / 2.0 + 30.0
	for i in range(22, 0, -1):
		var k := i / 22.0
		x.fillStyle = "rgb(%d,%d,%d)" % [roundi(58 + 70 * (1 - k)), roundi(34 + 40 * (1 - k)), roundi(40 + 30 * (1 - k))]
		x.fillText("13", cx + i * 1.6, cy + i * 2.1)
	x.lineJoin = "round"
	x.lineWidth = 30
	x.strokeStyle = "#150E24"
	x.strokeText("13", cx, cy)
	var g = x.createLinearGradient(0, cy - 220, 0, cy + 220)
	g.addColorStop(0, "#FFFFFF")
	g.addColorStop(0.22, "#D6E4FF")
	g.addColorStop(0.46, "#7A88B4")
	g.addColorStop(0.5, "#262A48")
	g.addColorStop(0.53, "#F6DDAE")
	g.addColorStop(0.72, "#FFF7E8")
	g.addColorStop(1, "#B08A5A")
	x.fillStyle = g
	x.fillText("13", cx, cy)
	x.lineWidth = 5
	x.strokeStyle = "rgba(255,255,255,0.85)"
	x.strokeText("13", cx - 2, cy - 3)
	return c

static func star(x, cx: float, cy: float, r: float, a: float) -> void:
	x.save()
	x.translate(cx, cy)
	x.globalAlpha = a
	var g = x.createRadialGradient(0, 0, 0, 0, 0, r)
	g.addColorStop(0, "rgba(255,255,255,1)")
	g.addColorStop(0.3, "rgba(255,245,220,0.6)")
	g.addColorStop(1, "rgba(255,245,220,0)")
	x.fillStyle = g
	x.fillRect(-r, -r, 2 * r, 2 * r)
	x.fillStyle = "rgba(255,255,255,0.95)"
	x.beginPath()
	for i in 8:
		var rr := r * 0.12 if i % 2 else r
		var ang := (i / 8.0) * TAU
		x.lineTo(cos(ang) * rr, sin(ang) * rr)
	x.closePath()
	x.fill()
	x.restore()

# ================================================================================================ Ending
var game
var boss
var active := false
var stage = null
var t := 0.0
var seen := false
var morning := false
var timeScale := 1.0
var round := 0
var heroId := "duke"
var summary := {}
var FONTS: Dictionary = FONTS_JS

var playing: bool:
	get:
		return active and stage != "card"
var running: bool:
	get:
		return active

var _flags := {}
var _dom = null
var _camFrom = null
var _yard = null
var _room = null
var _tv = null
var _tellyRest = null
var _roomCamPath = null
var _roomCam: Camera3D = null
var _kid = null
var _sideArm = null
var _gloveOut := false
var _ident = null
var _glint = null
var _lines = null
var _portrait = null
var _savedPass = null
var _savedGrain = null
var _hot = null
var _dawn = null
var _tellyWrapped = null
var _lib: Node3D = null
var _canvasScript = null
var _bossLib = null
var _cardPeers := {}                 # MP host: peer ids whose ending reached the card
var _cardT := -1.0                   # MP host: real time since the host's card appeared (-1: not yet)

func _init(g, b) -> void:
	game = g
	boss = b

func init() -> void:
	FONTS = fonts()
	var dev := func(_p) -> void: _glyphs()
	game.events.on("input:device", dev)
	# quitting to the title (pause menu) in the middle of the ending: drop the sequence (its overlay would cover the menu)
	var st := func(p) -> void:
		if p is Dictionary and p.get("to") == "menu" and active:
			stop()
	game.events.on("state", st)

func reset() -> void:
	stop()
	_undoMorning()

# ------------------------------------------------------------------------------------------ helpers
func _play(id: String, opts: Dictionary = {}) -> void:
	if game.audio != null:
		_fc(game.audio, "play", [id, opts])

func _music(id: String) -> void:
	if game.audio != null:
		_fc(game.audio, "music", [id])

func _post():
	return _gp(game.render, "post") if game.render != null else null

# ------------------------------------------------------------------------------------------ MP helpers
func _net():
	return game.get("net")

func _mp() -> bool:
	var n = _net()
	return n != null and n.inGame

func _client() -> bool:
	return _mp() and _net().isClient

func _host() -> bool:
	return _mp() and _net().isHost

# The local player's ending hold: keyed MP locks (player.lock / protect) or the plain solo fields.
func _hold(p, on: bool) -> void:
	if p == null:
		return
	if _mp() and p.has_method("lock") and p.has_method("protect"):
		p.lock("ending", on)
		p.protect("ending", on)
		return
	_sp(p, "controlLocked", on)
	_sp(p, "invulnerable", on)

# MP host: every connected in-game peer reached its card (or the grace ran out).
func _cardReady() -> bool:
	if not _host():
		return true
	if _cardT >= CARD_GRACE:
		return true
	for id in _net().peers:
		if not _cardPeers.has(id):
			return false
	return true

# MP: the card's dimmed state + caption (called by the Card every frame while it shows).
func _cardTick(dt: float) -> void:
	if not _mp() or _dom == null or stage != "card":
		return
	var card = _dom.card
	if _host():
		if _cardT >= 0.0:
			_cardT += dt
		_cardPeers[_net().localId] = true
		var ready := _cardReady()
		card.waiting = not ready
		var n: int = 0
		for id in _net().peers:
			if _cardPeers.has(id):
				n += 1
		card.caption = "" if ready else "STANDING BY  %d / %d" % [n, _net().peers.size()]
	else:
		card.waiting = true
		card.caption = "%s IS AT THE DIAL" % _net().nameOf(1).to_upper()

# MP host: a client's ending reached its card.
func net_atCard() -> void:
	if not _host():
		return
	_cardPeers[int(_net().sender)] = true

# MP: the host's STAY TUNED? answer, on every peer, at any stage of the local sequence.
func net_choose(c) -> void:
	var n = _net()
	if n == null or not n.inGame or int(n.sender) != 1:
		return
	var b = boss
	if not active and not (b != null and b.get("state") == "defeated"):
		return
	_play("ui_tune_in", {"vol": 0.8})
	if active and stage != "card" and b != null and b.has_method("cleanupAfterEnding") and b.get("built"):
		b.cleanupAfterEnding()       # a client still in its cinematic: the Baron's collapse props go first
	if str(c) == "y":
		morningShow()
	else:
		results()

# document.createElement('canvas') -> DACanvas (bakeMode: "never" for canvases redrawn every frame, "now" for static
# ones; texture.needsUpdate is not needed: DACanvas presents what was drawn).
func _newCanvas(w: int, h: int, bake: String = "auto"):
	if _canvasScript == null and ResourceLoader.exists("res://scripts/gfx/canvas2d.gd"):
		_canvasScript = load("res://scripts/gfx/canvas2d.gd")
	if _canvasScript == null:
		return null
	var cv = _canvasScript.new(w, h)
	cv.bakeMode = bake
	return cv

func _B():
	if _bossLib == null:
		_bossLib = load("res://scripts/actors/boss.gd")
	return _bossLib

# The Blender runtime asset (kid's bowl, hatch, portrait backdrop + floor): one instance; parts are duplicated out.
func _asset(name: String) -> Node3D:
	if _lib == null:
		if not ResourceLoader.exists(ENDING_GLB):
			push_warning("[ending] runtime asset missing: %s (run blender/build_all.py --only runtime)" % ENDING_GLB)
			return null
		var ps = load(ENDING_GLB)
		if not (ps is PackedScene):
			return null
		_lib = ps.instantiate()
		DAU.traverse(_lib, func(n: Node) -> void: _convertImported(n))
	var n = _lib.find_child(name, true, false)
	if not (n is Node3D):
		return null
	var c: Node3D = n.duplicate()
	c.transform = (n as Node3D).transform
	var clear := func(o: Node) -> void:
		o.owner = null
	DAU.traverse(c, clear)
	return c

func _convertImported(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).rotation_order = EULER_ORDER_XYZ
	var ex = n.get_meta("extras") if n.has_meta("extras") else null
	if ex is Dictionary and ex.has("da"):
		var da = JSON.parse_string(ex.da) if ex.da is String else ex.da
		if da is Dictionary:
			DAU.ud(n).merge(da, true)
			if da.get("visible") == false and n is Node3D:
				n.visible = false
			if da.has("castShadow") and n is GeometryInstance3D:
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if da.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is MeshInstance3D and n.mesh != null and game.mats != null and game.mats.has_method("fromSpec"):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null or not m.has_meta("extras"):
				continue
			var mex = m.get_meta("extras")
			if mex is Dictionary and mex.has("da"):
				var spec = JSON.parse_string(mex.da) if mex.da is String else mex.da
				if spec is Dictionary:
					var conv = game.mats.fromSpec(spec, m)
					if conv is Material:
						mi.set_surface_override_material(i, conv)

func _heroes():
	return load("res://scripts/actors/heroes.gd") if ResourceLoader.exists("res://scripts/actors/heroes.gd") else null

func _buildHero(id: String):
	var H = _heroes()
	if H == null or not H.has_method("buildHero"):
		return null
	return H.buildHero(id, game)

func _toon(color: String, opts: Dictionary) -> Material:
	if game.mats != null and game.mats.has_method("toon"):
		return game.mats.toon(color, opts)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	return m

# ------------------------------------------------------------------------------------------ play
func play(o: Dictionary = {}) -> bool:
	var g = game
	if active:
		return false
	active = true
	stage = "yard"
	t = 0.0
	_flags = {}
	var r = o.get("round")
	round = int(r) if (r is int or r is float) else (int(_gp(g.rounds, "round", 0)) if _gp(g.rounds, "round", 0) else 1)
	var hid = _gp(g.player, "heroId")
	heroId = hid if hid else (g.heroId if g.heroId else "duke")
	summary = {"round": round, "kills": _gp(g.rounds, "totalKills", 0), "points": _gp(g.economy, "points", 0)}
	if _mp():
		var sm = o.get("summary")
		if not (sm is Dictionary) or sm.is_empty():
			sm = _net().teamSummary()
		summary = sm
		_cardPeers = {}
		_cardT = -1.0
		_lines = null
	seen = storeGet(KEY) == "1"
	storeSet(KEY, "1")
	var p = g.player
	if p != null:
		if _mp():
			_hold(p, true)
		else:
			_sp(p, "controlLocked", true)
			_sp(p, "invulnerable", true)
	if g.hud != null:
		_fc(g.hud, "hide")
	if g.cam != null:
		_sp(g.cam, "enabled", false)
	var cam: Camera3D = g.camera
	_camFrom = {"pos": cam.global_position, "quat": cam.global_basis.get_rotation_quaternion(), "fov": cam.fov} if cam != null else null
	_ensureDom()
	_show(true)
	_paintBlack(0)
	_dom.keys.enabled = true
	_music("silence")
	_play("sting_signoff_hymn", {"vol": 1})
	if boss != null:
		boss.goodnight()
	_setupYardCam()
	return true

# ------------------------------------------------------------------------------------------ update
func update(rdt: float) -> void:
	if morning:
		_tickMorning(rdt)
	if not active or stage == "card" or stage == "done":
		return
	var dt := rdt * (timeScale if is_finite(timeScale) else 1.0)
	t += dt
	var F := _flags
	var g = game
	var b = boss

	# ---- 0–4: the yard
	if t < E.black:
		_yardCam(t)
	if _once("headSnd", E.head):
		_play("crt_power_off", {"pos": b._screenWorld() if b != null else null, "vol": 1})
	if t >= E.head and t < E.black + 0.2 and b != null:
		b.collapseHead((t - E.head) / 0.6)
	if _once("viewSnd", E.view):
		_play("crt_power_off", {"vol": 1.2, "rate": 0.8})
	if t >= E.view and t < E.room:
		var post = _post()
		if post != null:
			post.collapse = clampf((t - E.view) / 0.6, 0.0, 1.0)
	if _once("black", E.black):
		stage = "dot"
		if b != null:
			b.cleanupAfterEnding()
		_paintBlack(1)
	# ---- 4–7: the dot winks
	if t >= E.black and t < E.room:
		_drawDot(t)
	if _once("wink", E.wink):
		_play("smile_ting", {"vol": 0.7})
	# ---- 7–17: the living room
	if _once("room", E.room):
		_enterRoom()
	if t >= E.room and t < E.silence:
		_updateRoom(t, dt)
	if _once("lullaby", E.room + 0.3):
		_play("telly_lullaby", {"vol": 0.75})
	if _once("wake", E.face):
		_play("telly_wake", {"vol": 0.45})
	if _once("boing", E.hop + 0.25):
		_play("telly_boing", {"vol": 0.45, "rate": 1.15})
	if _once("ploop", E.glove):
		_play("telly_ploop", {"vol": 0.6})
	if _once("giggle", E.wave + 0.5):
		_play("telly_giggle", {"vol": 0.45})
	if _once("zip", E.gloveIn):
		_play("telly_zip", {"vol": 0.5})
	if _once("offSnd", E.off):
		_play("crt_power_off", {"vol": 0.8})
	# ---- 17–20: dead air
	if _once("silence", E.silence):
		stage = "silence"
		_leaveRoom()
		_paintBlack(1)
		if g.audio != null:
			_fc(g.audio, "stopAll")
		_music("silence")
	# ---- 20–32: credits
	if _once("credits", E.credits):
		stage = "credits"
		_music("credits")
	if t >= E.credits and t < E.freeze + 0.5:
		_drawCredits(t)
	if _once("portrait", E.portrait):
		_enterPortrait()
	if t >= E.portrait and t < E.card:
		_updatePortrait(t, dt)
	if _once("freeze", E.freeze):
		_freeze()
	# ---- 35: STAY TUNED?
	if _once("card", E.card):
		_showCard()

# once(k, at, fn): true the first time t >= at (the caller runs the beat).
func _once(k: String, at: float) -> bool:
	if t >= at and not _flags.has(k):
		_flags[k] = true
		return true
	return false

# ------------------------------------------------------------------------------------------ the yard (0–4)
# A slow push-in on the Baron from the player's side, searching around him for a spot inside the yard with a clear
# line of sight (the tower lattice, the van, the hut).
func _setupYardCam() -> void:
	var g = game
	var b = boss
	var col = _gp(g.level, "col")
	var head: Vector3 = b._screenWorld() if (b != null and b.built) else Vector3(45, 6, -12)
	var pp = _gp(g.player, "pos")
	var p: Vector3 = pp if pp is Vector3 else Vector3(45, 0, -5)
	var target := Vector3(head.x, head.y - 1.0, head.z)
	var base := atan2(p.z - head.z, p.x - head.x)
	# the tower lattice is see-through for collisions above 3 m: test its footprint explicitly (2D segment vs rect)
	var TW := [42.4, -14.6, 47.6, -9.4]
	var hitsTower := func(a: Vector3, c: Vector3) -> bool:
		for i in 25:
			var u := i / 24.0
			var x := a.x + (c.x - a.x) * u
			var z := a.z + (c.z - a.z) * u
			if x > TW[0] and x < TW[2] and z > TW[1] and z < TW[3]:
				return true
		return false
	var clear := func(c: Vector3) -> bool:
		if c.x < 35.8 or c.x > 50.2 or c.z < -19.2 or c.z > -2.8:
			return false
		if hitsTower.call(c, target):
			return false
		var d := target - c
		var ln := d.length()
		d = d.normalized()
		var hit = _fc(col, "raycast", [c, d, ln])
		return not (hit != null and float(_gp(hit, "dist", INF)) < ln - 1.2)
	var pick = null
	var i := 0
	while i < 16 and pick == null:
		var a := base + (1.0 if i % 2 else -1.0) * ceili(i / 2.0) * (PI / 8.0)
		var dir := Vector3(cos(a), 0, sin(a))
		for row in [[9.5, 5.8], [8.0, 5.0], [6.5, 4.2]]:
			var from: Vector3 = head + dir * float(row[0])
			from.y = maxf(1.7, head.y - 1.7)
			var to: Vector3 = head + dir * float(row[1])
			to.y = maxf(1.9, head.y - 1.0)
			if clear.call(from) and clear.call(to):
				pick = {"from": from, "to": to}
				break
		i += 1
	if pick == null:
		var v := Vector3(p.x - head.x, 0, p.z - head.z).normalized()
		var from := head + v * 9.0
		from.y = 2.0
		var to := head + v * 5.5
		to.y = 2.4
		pick = {"from": from, "to": to}
	_yard = {"target": target, "from": pick.from, "to": pick.to}
	# he turns to face the camera for his goodnight
	if b != null:
		b.yaw = atan2(-(_yard.to.x - b.pos.x), -(_yard.to.z - b.pos.z))

func _yardCam(tt: float) -> void:
	var g = game
	var y = _yard
	if y == null or g.camera == null:
		return
	var k := easeInOut(tt / E.black)
	var cam: Camera3D = g.camera
	var p: Vector3 = (y.from as Vector3).lerp(y.to, k)
	cam.global_position = p
	if not p.is_equal_approx(y.target):
		cam.look_at(y.target, Vector3.UP)
	if absf(cam.fov - 50.0) > 0.01:
		cam.fov = 50.0

# ------------------------------------------------------------------------------------------ DOM overlay
func _ensureDom() -> void:
	if _dom != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "de-end"
	layer.layer = 18
	layer.visible = false
	var ov := Overlay.new()
	ov.name = "de-end-root"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ov)
	# (JS: the WebGL canvas) the portrait world + the CSS sepia filter on it
	var portrait := TextureRect.new()
	portrait.name = "portrait"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = false
	ov.add_child(portrait)
	var sepia := ColorRect.new()
	sepia.name = "sepia"
	sepia.set_anchors_preset(Control.PRESET_FULL_RECT)
	sepia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SEPIA_SHADER
	sm.set_shader_parameter("amount", 0.0)
	sepia.material = sm
	sepia.visible = false
	ov.add_child(sepia)
	# .de-main canvas
	var canvasRect := TextureRect.new()
	canvasRect.name = "de-main"
	canvasRect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvasRect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	canvasRect.stretch_mode = TextureRect.STRETCH_SCALE
	canvasRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(canvasRect)
	# .de-warm
	var warm := ColorRect.new()
	warm.name = "de-warm"
	warm.set_anchors_preset(Control.PRESET_FULL_RECT)
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wm := ShaderMaterial.new()
	wm.shader = Shader.new()
	wm.shader.code = WARM_SHADER
	warm.material = wm
	warm.modulate.a = 0.0
	ov.add_child(warm)
	# .de-frame
	var frame := ColorRect.new()
	frame.name = "de-frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FRAME_SHADER
	frame.material = fm
	frame.modulate.a = 0.0
	ov.add_child(frame)
	# .de-flash
	var flash := ColorRect.new()
	flash.name = "de-flash"
	flash.color = Color(1, 1, 1)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	ov.add_child(flash)
	# .de-card
	var card := Card.new()
	card.name = "de-card"
	card.ending = self
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.fontLogo = load(FONT_FILES.logo) if ResourceLoader.exists(FONT_FILES.logo) else ThemeDB.fallback_font
	card.fontHud = load(FONT_FILES.hud) if ResourceLoader.exists(FONT_FILES.hud) else ThemeDB.fallback_font
	card.modulate.a = 0.0
	card.scaleK = 0.6
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(card)
	var keys := KeyCatcher.new()
	keys.ending = self
	keys.enabled = false
	layer.add_child(keys)
	game.add_child(layer)
	_dom = {"root": layer, "ov": ov, "canvas": canvasRect, "cv": null, "ctx": null, "portrait": portrait, "sepia": sepia, "warm": warm,
		"frame": frame, "flash": flash, "card": card, "keys": keys, "on": false}

func _show(on: bool) -> void:
	if _dom == null:
		return
	_dom.root.visible = on

# {w, h, x}: the canvas fills the window (max 1920 wide), like the JS _fit().
func _fit() -> Dictionary:
	var vs: Vector2 = game.get_viewport().get_visible_rect().size
	var w := maxi(320, mini(1920, int(vs.x)))
	var h := roundi(w * vs.y / vs.x)
	if _dom.cv == null or _dom.cv.width != w or _dom.cv.height != h:
		var cv = _newCanvas(w, h, "never")
		_dom.cv = cv
		_dom.ctx = cv.getContext("2d") if cv != null else null
		(_dom.canvas as TextureRect).texture = cv.texture if cv != null else null
	return {"w": w, "h": h, "x": _dom.ctx}

# a = opacity of the black cover (0 = see the 3D scene)
func _paintBlack(a: float) -> void:
	if _dom == null:
		return
	var f := _fit()
	var x = f.x
	_dom.canvas.modulate.a = 1.0
	if x == null:
		# no DACanvas: a plain black cover keeps the sequence readable
		(_dom.canvas as TextureRect).texture = null
		_dom.ov.cover = a
		return
	_dom.ov.cover = 0.0
	x.clearRect(0, 0, f.w, f.h)
	if a > 0.0:
		x.fillStyle = "rgba(0,0,0,%s)" % str(a)
		x.fillRect(0, 0, f.w, f.h)

# 4–7: the lingering dot grows two tiny eyes and winks.
func _drawDot(tt: float) -> void:
	var f := _fit()
	var x = f.x
	if x == null:
		return
	var w: float = f.w
	var h: float = f.h
	x.fillStyle = "#000"
	x.fillRect(0, 0, w, h)
	var s := h / 720.0
	var u := tt - E.black
	var r := 5.0 * s
	if tt >= E.eyes:
		r = lerpf(5.0, 30.0, easeOutBack((tt - E.eyes) / 0.5, 2.0)) * s
	if tt > E.room - 0.45:
		r *= maxf(0.0, (E.room - tt) / 0.45)
	var cx := w / 2.0
	var cy := h / 2.0
	var glow = x.createRadialGradient(cx, cy, 0, cx, cy, r * 4 + 10 * s)
	glow.addColorStop(0, "rgba(235,240,255,0.9)")
	glow.addColorStop(0.3, "rgba(200,210,255,0.25)")
	glow.addColorStop(1, "rgba(200,210,255,0)")
	x.fillStyle = glow
	x.beginPath()
	x.arc(cx, cy, r * 4 + 10 * s, 0, TAU)
	x.fill()
	x.fillStyle = "#FBFBFF"
	x.beginPath()
	x.arc(cx, cy + sin(u * 3.0) * 1.5 * s, r, 0, TAU)
	x.fill()
	if tt >= E.eyes + 0.25 and r > 12.0 * s:
		var ey := cy - r * 0.12
		var ex := r * 0.34
		var er := r * 0.13
		var winking: bool = tt >= E.wink and tt < E.wink + 0.55
		x.fillStyle = "#1B1430"
		x.strokeStyle = "#1B1430"
		x.lineCap = "round"
		# left eye (viewer's left) always open; the right one winks
		x.beginPath()
		x.ellipse(cx - ex, ey, er, er * 1.35, 0, 0, TAU)
		x.fill()
		if winking:
			x.lineWidth = er * 0.8
			x.beginPath()
			x.arc(cx + ex, ey + er * 0.2, er * 1.1, PI * 1.15, PI * 1.85)
			x.stroke()
		else:
			x.beginPath()
			x.ellipse(cx + ex, ey, er, er * 1.35, 0, 0, TAU)
			x.fill()
		# a tiny smile
		x.lineWidth = er * 0.55
		x.beginPath()
		x.arc(cx, cy + r * 0.12, r * 0.28, PI * 0.2, PI * 0.8)
		x.stroke()

# ------------------------------------------------------------------------------------------ living room (7–17)
func _enterRoom() -> void:
	var g = game
	stage = "room"
	var post = _post()
	if post != null:
		post.collapse = 0.0
	var room = null
	if g.menu != null:
		room = _fc(g.menu, "getLivingRoom")
	_room = room
	if room == null:
		return
	# the TV picture: our own canvas (sign-off film -> Telly's face -> CRT power-off)
	if _tv == null:
		var c = _newCanvas(384, 288, "never")
		if c != null:
			_tv = {"canvas": c, "ctx": c.getContext("2d"), "tex": c.texture}
	if _tv != null:
		_fc(room, "setPicture", [_tv.tex])
	_buildKid(room)
	var telly = _gp(room, "telly")
	_tellyRest = null
	if telly is Node3D:
		var P: Dictionary = DAU.ud(telly).get("parts", {})
		var body = P.get("body")
		var earL = P.get("earL")
		var earR = P.get("earR")
		for n in [body, earL, earR]:
			if n is Node3D:
				n.rotation_order = EULER_ORDER_XYZ
		_tellyRest = {
			"bodyY": body.position.y if body is Node3D else 0.0, "bodySX": body.scale.x if body is Node3D else 1.0,
			"earL": earL.rotation if earL is Node3D else null, "earR": earR.rotation if earR is Node3D else null,
		}
		_attachSideArm(telly)
	var scr = DAU.ud(telly).get("parts", {}).get("screen") if telly is Node3D else null
	var sw: Vector3 = _xf(scr).origin if scr is Node3D else Vector3(0.12, 1.0, 1.2)
	_roomCamPath = {
		"screen": sw,
		"p0": sw + Vector3(0, 0.02, -0.42),
		"p1": Vector3(1.62, 1.62, -2.95),                     # over the sleeping kid's shoulder, behind the couch
		"p2": Vector3(0.45, 1.22, -0.55),                     # then in on Telly
		"look0": sw,
		"look1": Vector3(0.12, 0.5, 0.5),
		"look2": sw + Vector3(-0.05, -0.1, 0),
	}
	if _roomCam == null:
		_roomCam = Camera3D.new()
		_roomCam.name = "ending_room_cam"
		_roomCam.fov = 42.0
		_roomCam.near = 0.05
		_roomCam.far = 60.0
	var host = _gp(room, "scene")
	if not (host is Node):
		host = _gp(room, "root")
	if host is Node and _roomCam.get_parent() != host:
		DAU.detach(_roomCam)
		host.add_child(_roomCam)
	_fc(room, "activate", [_roomCam])

func _updateRoom(tt: float, dt: float) -> void:
	var room = _room
	var u := tt - E.room
	# black cover: fade in at 7.0, out at 16.7
	var cover := 0.0
	if tt < E.room + 0.55:
		cover = 1.0 - smooth(u / 0.55)
	elif tt > E.roomOut:
		cover = smooth((tt - E.roomOut) / (E.silence - E.roomOut))
	_paintBlack(cover)
	if room == null:
		return
	# camera: dolly back from the TV glass to reveal the room, then a slow push toward Telly
	var P = _roomCamPath
	var cam := _roomCam
	if P != null and cam != null and cam.is_inside_tree():
		var k1 := easeInOut((tt - (E.room + 0.3)) / 3.4)
		var k2 := easeInOut((tt - E.face) / 5.8)
		var p: Vector3 = (P.p0 as Vector3).lerp(P.p1, k1).lerp(P.p2, k2 * 0.85)
		var look: Vector3 = (P.look0 as Vector3).lerp(P.look1, k1).lerp(P.look2, k2 * 0.85)
		cam.fov = lerpf(40.0, 38.0, k1)
		cam.global_position = p
		if not p.is_equal_approx(look):
			cam.look_at(look, Vector3.UP)
	_drawTv(tt)
	_animateTelly(tt)
	_animateKid(tt, dt)

# The console TV's picture: the station's sign-off film, then Telly's sleepy face, then its CRT power-off dot.
func _drawTv(tt: float) -> void:
	var tv = _tv
	if tv == null:
		return
	var x = tv.ctx
	var w: float = tv.canvas.width
	var h: float = tv.canvas.height
	x.fillStyle = "#000"
	x.fillRect(0, 0, w, h)
	var draw := func(id: String, time: float, opts: Dictionary = {}) -> void:
		_fc(game.cards, "drawTo", [x, id, w, h, time, opts])
	if tt < E.face:
		draw.call("signoff_film", 3.2 + (tt - E.room) * 0.9)
	elif tt < E.off:
		var expr := "sleepy"
		if tt >= E.hop and tt < E.hop + 0.5:
			expr = "o_mouth"
		elif tt >= E.wave and tt < E.wave + 1.4:
			expr = "happy"
		elif tt >= E.wave + 1.4 and tt < E.waveEnd:
			expr = "wink"
		elif tt >= E.waveEnd:
			expr = "sleepy"
		draw.call("telly_face", tt, {"expr": expr, "look": [0.15, -0.1]})
		if tt < E.face + 0.18:
			x.fillStyle = "rgba(255,255,255,%s)" % str(1.0 - (tt - E.face) / 0.18)
			x.fillRect(0, 0, w, h)
	else:
		# CRT power-off: squash into a white line, shrink into a dot, fade
		var k := (tt - E.off) / 0.9
		if k < 0.35:
			draw.call("telly_face", tt, {"expr": "sleepy"})
			var sy := 1.0 - smooth(k / 0.35)
			x.fillStyle = "#000"
			var band := h * sy / 2.0
			x.fillRect(0, 0, w, h / 2.0 - band)
			x.fillRect(0, h / 2.0 + band, w, h / 2.0 - band)
			x.fillStyle = "rgba(255,255,255,%s)" % str(0.5 + k)
			x.fillRect(0, h / 2.0 - band, w, band * 2.0)
		elif k < 0.7:
			var sx := 1.0 - smooth((k - 0.35) / 0.35)
			var lw := maxf(6.0, w * sx)
			var gr = x.createLinearGradient(w / 2.0 - lw / 2.0, 0, w / 2.0 + lw / 2.0, 0)
			gr.addColorStop(0, "rgba(255,255,255,0)")
			gr.addColorStop(0.5, "rgba(255,255,255,1)")
			gr.addColorStop(1, "rgba(255,255,255,0)")
			x.fillStyle = gr
			x.fillRect(w / 2.0 - lw / 2.0, h / 2.0 - 3.0, lw, 6)
		else:
			var a := maxf(0.0, 1.0 - (tt - (E.off + 0.63)) / 0.9)
			var gr = x.createRadialGradient(w / 2.0, h / 2.0, 0, w / 2.0, h / 2.0, 14)
			gr.addColorStop(0, "rgba(255,255,255,%s)" % str(a))
			gr.addColorStop(1, "rgba(255,255,255,0)")
			x.fillStyle = gr
			x.fillRect(w / 2.0 - 16.0, h / 2.0 - 16.0, 32, 32)

func _animateTelly(tt: float) -> void:
	var telly = _gp(_room, "telly")
	var R = _tellyRest
	if not (telly is Node3D) or R == null:
		return
	var P: Dictionary = DAU.ud(telly).get("parts", {})
	# ears: two quick twitches after the face comes on, a sleepy droop otherwise
	var tw := func(at: float) -> float:
		var k := (tt - at) / 0.35
		return sin(k * PI * 3.0) * (1.0 - k) if k > 0.0 and k < 1.0 else 0.0
	var twitch: float = tw.call(E.ears) + tw.call(E.ears + 0.55) * 0.8 + tw.call(E.waveEnd + 0.1) * 0.5
	if P.get("earL") is Node3D and R.earL != null:
		P.earL.rotation = Vector3(R.earL.x, R.earL.y, R.earL.z + twitch * 0.35)
	if P.get("earR") is Node3D and R.earR != null:
		P.earR.rotation = Vector3(R.earR.x, R.earR.y, R.earR.z - twitch * 0.3)
	# the tiny sleepy hop (squash, up, land, settle)
	if P.get("body") is Node3D:
		var k := (tt - E.hop) / 0.9
		var dy := 0.0
		var sq := 1.0
		if k > 0.0 and k < 1.0:
			if k < 0.22:
				sq = 1.0 - 0.1 * sin((k / 0.22) * PI)
			elif k < 0.7:
				var a := (k - 0.22) / 0.48
				dy = sin(a * PI) * 0.11
				sq = 1.0 + 0.05 * sin(a * PI)
			else:
				var a := (k - 0.7) / 0.3
				sq = 1.0 - 0.07 * sin(a * PI) * (1.0 - a)
		var breathe := sin(tt * 2.1) * 0.006 if tt > E.face else 0.0
		P.body.position.y = R.bodyY + dy
		P.body.scale = Vector3(R.bodySX * (2.0 - sq), R.bodySX * (sq + breathe), R.bodySX * (2.0 - sq))
	# the glove: Telly's RIGHT hand (the viewer's left) reaches out of a little hatch in the cabinet's right side
	# wall, rises beside the screen, waves goodnight and tucks back in (the gameplay presentation, out of the screen
	# centre, is untouched: this is a local arm, see _attachSideArm)
	var A = _sideArm
	if A != null and A.rig.get_parent() != null:
		var on: bool = tt >= E.glove and tt < E.gloveIn + 0.35
		var out := 0.0
		if on:
			if tt < E.wave:
				out = easeOutBack((tt - E.glove) / 0.3)
			elif tt > E.gloveIn:
				out = 1.0 - smooth((tt - E.gloveIn) / 0.3)
			else:
				out = 1.0
		var show := out > 0.02
		A.arm.visible = show
		A.glove.visible = show
		A.hatch.visible = on
		if on:
			# the hatch pops open first and snaps shut after the glove is back in
			var hk := 1.0
			if tt < E.glove + 0.12:
				hk = easeOutBack((tt - E.glove) / 0.12, 2.5)
			elif tt > E.gloveIn + 0.24:
				hk = 1.0 - smooth((tt - E.gloveIn - 0.24) / 0.11)
			A.hatch.scale = Vector3.ONE * maxf(0.001, hk)
		if show:
			var k := clampf(out, 0.0, 1.2)
			var wave := sin((tt - E.wave) * 9.0) * 0.45 * minf(1.0, (tt - E.wave) / 0.15) if tt >= E.wave and tt < E.waveEnd else 0.0
			# out of the wall (fingers first, pointing away from the cabinet), then up beside the screen, palm to the viewer
			A.glove.position = Vector3(lerpf(-0.1, 0.2, k), 0.31 * pow(maxf(0.0, k), 1.6), lerpf(0.0, -0.14, k))
			A.glove.rotation = Vector3(0.1, -0.15, lerpf(-PI / 2.0, 0.0, clampf(k, 0.0, 1.0)) + wave)
			var s: float = A.scale * lerpf(0.55, 1.0, clampf(k, 0.0, 1.0))
			A.glove.scale = Vector3(-s, s, s)                        # mirrored: the prop's glove is a left hand
			A.ctrl.position = Vector3(lerpf(0.02, 0.2, k) + wave * 0.03, lerpf(0.0, 0.02, k), lerpf(0.0, -0.06, k))
			var up = _tellyFn("updateTellyArm")
			if up.is_valid():
				up.call(A.proxy)

# props/machines.js helpers (setTellyGlove / updateTellyArm) wherever the Godot port hosts them.
func _tellyFn(name: String) -> Callable:
	if game.props != null and game.props.has_method(name):
		return Callable(game.props, name)
	for path in ["res://scripts/props/machines.gd", "res://scripts/props/telly_rig.gd", "res://scripts/game/telly.gd"]:
		if ResourceLoader.exists(path):
			var s = load(path)
			if s != null and s.has_method(name):
				return Callable(s, name)
	if game.telly != null and game.telly.has_method(name):
		return Callable(game.telly, name)
	return Callable()

# Telly's goodnight arm for the ending (built once, parented to the living-room Telly's body while in the room):
# a copy of the prop's glove (shared meshes/materials, mirrored into a right hand) on a copy of its accordion arm,
# rooted inside the cabinet's right side wall behind a brass-ringed hatch found by raycasting that wall. The prop's
# own glove/arm stay hidden (no screen membrane parting, the menu keeps the picture seated at the front).
func _attachSideArm(telly: Node3D) -> void:
	var P: Dictionary = DAU.ud(telly).get("parts", {})
	if not (P.get("body") is Node3D) or not (P.get("glove") is Node3D) or not (P.get("arm") is MeshInstance3D):
		return
	if _sideArm == null:
		var glove: Node3D = P.glove.duplicate()
		var strip := func(o: Node) -> void:
			if o.has_meta("userData"):
				o.remove_meta("userData")
		DAU.traverse(glove, strip)
		glove.name = "ending_tellyGlove"
		glove.visible = true
		glove.position = Vector3.ZERO
		glove.quaternion = Quaternion.IDENTITY
		glove.rotation_order = EULER_ORDER_XYZ
		for n in ["index", "middle", "pinky"]:
			var f = glove.find_child("glove_" + n, true, false)
			if f is Node3D:
				f.rotation_order = EULER_ORDER_XYZ
				f.rotation.x = -0.12
		var th = glove.find_child("glove_thumb", true, false)
		if th is Node3D:
			th.rotation_order = EULER_ORDER_XYZ
			th.rotation.x = -0.45
		var src: MeshInstance3D = P.arm
		var armMat: Material = src.material_override if src.material_override != null else src.get_active_material(0)
		var arm := MeshInstance3D.new()
		arm.mesh = src.mesh.duplicate(true) if src.mesh != null else null
		arm.material_override = armMat
		arm.name = "ending_tellyArm"
		arm.extra_cull_margin = 4.0
		arm.cast_shadow = src.cast_shadow
		var ctrl := DAU.node3d("ending_tellyArmCtrl")
		# hatch: a dark hole in a brass ring, facing out of the wall (+x); vertex-coloured like the arm (same material)
		var hatch: Node3D = _asset("tellyHatch")
		if hatch == null:
			hatch = DAU.node3d("tellyHatch")
		hatch.name = "ending_tellyHatch"
		var tint := func(o: Node) -> void:
			if o is MeshInstance3D and armMat != null:
				o.material_override = armMat
		DAU.traverse(hatch, tint)
		hatch.rotation_order = EULER_ORDER_XYZ
		hatch.rotation = Vector3(0, PI / 2.0, 0)
		var rig := DAU.node3d("ending_tellySideArm")
		rig.add_child(arm)
		rig.add_child(glove)
		rig.add_child(ctrl)
		var proxy := Node3D.new()
		proxy.name = "ending_tellyArmProxy"
		DAU.ud(proxy).parts = {"arm": arm, "glove": glove, "armCtrl": ctrl}
		var gs: float = absf(P.glove.scale.x)
		_sideArm = {"rig": rig, "arm": arm, "glove": glove, "ctrl": ctrl, "hatch": hatch, "scale": gs if gs else 1.35, "proxy": proxy}
	var A = _sideArm
	_detachSideArm()
	# the right side wall (+x, body space) just below the screen centre, a little toward the front: the arm bends up
	var hy := 0.45
	var hz := -0.06
	var hx := 0.73
	var body: Node3D = P.body
	var bx := _xf(body)
	var o := bx * Vector3(1.6, hy, hz)
	var d := (bx * Vector3(0.6, hy, hz) - o).normalized()
	var meshes := []
	var coll := func(m: Node) -> void:
		if m is MeshInstance3D and m.visible and m != P.arm and not (m == P.glove or P.glove.is_ancestor_of(m)):
			meshes.append(m)
	DAU.traverse(body, coll)
	var hit = _rayMeshes(o, d, 1.2, meshes)
	if hit is Vector3:
		var lp: Vector3 = bx.affine_inverse() * hit
		if lp.x > 0.55 and lp.x < 0.9:
			hx = lp.x
	A.hatch.position = Vector3(hx + 0.003, hy, hz)
	A.rig.position = Vector3(hx - 0.035, hy, hz)              # tube root inside the wall
	A.arm.visible = false
	A.glove.visible = false
	A.hatch.visible = false
	body.add_child(A.rig)
	body.add_child(A.hatch)

# THREE.Raycaster(o, d, 0, far).intersectObjects(meshes)[0].point (nearest triangle hit; both faces).
static func _rayMeshes(o: Vector3, d: Vector3, far: float, meshes: Array):
	var best := far
	var hit = null
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _xf(mi)
		var f := mi.mesh.get_faces()
		for i in range(0, f.size(), 3):
			var p = Geometry3D.ray_intersects_triangle(o, d, xf * f[i], xf * f[i + 1], xf * f[i + 2])
			if p is Vector3:
				var dist := o.distance_to(p)
				if dist < best:
					best = dist
					hit = p
	return hit

func _detachSideArm() -> void:
	var A = _sideArm
	if A == null:
		return
	DAU.detach(A.rig)
	DAU.detach(A.hatch)

# A kid asleep on the couch in the WZTV "13" cap (Skip's sculpted model, kid-sized) hugging a popcorn bowl.
func _buildKid(room) -> void:
	var g = game
	if _kid == null:
		var hero = _buildHero("skip")
		if hero == null or not (_gp(hero, "group") is Node3D):
			push_warning("[ending] kid build failed")
			return
		var grp := DAU.node3d("ending_kid")
		var hg: Node3D = _gp(hero, "group")
		grp.add_child(hg)
		hg.scale = Vector3.ONE * 0.7
		# popcorn bowl in the lap (Blender asset: the red half-sphere bowl + 22 popcorn puffs)
		var bowl: Node3D = _asset("bowl")
		if bowl == null:
			bowl = DAU.node3d("bowl")
		var bm := bowl.find_child("bowl_shell", true, false)
		if bm is MeshInstance3D:
			bm.material_override = _toon("#E23B3B", {"rough": 0.35, "rim": 0.3, "keepColor": true, "side": "double"})
		var pop := _toon("#FFF3D0", {"rough": 0.9, "rim": 0.45, "rimColor": "#FFE6A0", "wrap": 0.8, "keepColor": true})
		var popm := func(o: Node) -> void:
			if o is MeshInstance3D and String(o.name).begins_with("popcorn"):
				o.material_override = pop
		DAU.traverse(bowl, popm)
		grp.add_child(bowl)
		# sleepy "z Z z" floating up from the kid
		var zs := []
		var zc = _newCanvas(96, 96, "now")
		var ztex: Texture2D = null
		if zc != null:
			var zx = zc.getContext("2d")
			zx.font = "78px %s" % FONTS.logo
			zx.textAlign = "center"
			zx.textBaseline = "middle"
			zx.lineWidth = 9
			zx.strokeStyle = "#2A1D3A"
			zx.lineJoin = "round"
			zx.strokeText("Z", 48, 52)
			zx.fillStyle = "#FFF1CC"
			zx.fillText("Z", 48, 52)
			ztex = zc.texture
		var BL = _B()
		for i in 3:
			var s: MeshInstance3D = BL.sprite(BL.spriteMat(ztex if ztex != null else BL.glowTexture(), Vector3.ONE, false, true, 6), "ending_z%d" % i)
			grp.add_child(s)
			zs.append(s)
		_kid = {"group": grp, "hero": hero, "bowl": bowl, "zs": zs, "zc": zc}
		var shadows := func(o: Node) -> void:
			if o is GeometryInstance3D:
				o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		DAU.traverse(hg, shadows)
	var K = _kid
	# the couch (sofa_cloud at z -1.95 facing the TV): the kid slumps in its right-hand corner
	K.group.position = Vector3(0.52, 0.2, -1.92)
	K.group.rotation = Vector3(0, PI, 0)
	var rr = _gp(room, "root")
	if K.group.get_parent() == null and rr is Node:
		rr.add_child(K.group)
	var hero = K.hero
	var face = _path(hero, ["art", "face"])
	if face != null:
		_sp(face, "auto", false)
		_fc(face, "setExpression", ["smile", 0.6])
	var anim = _gp(hero, "animator")
	if anim != null:
		_sp(anim, "override", Callable(self, "_kidPose"))

func _kidPose(rig, _dt = 0.0) -> void:   # rig.gd calls override(rig, dt)
	var Jn = _gp(rig, "joints")
	if not (Jn is Dictionary):
		return
	var br := sin(t * 1.6) * 0.03
	var set_ := func(n: String, x: float, y: float, z: float) -> void:
		var j = Jn.get(n)
		if j is Node3D:
			j.rotation = Vector3(x, y, z)
	set_.call("hips", -0.35, 0, 0)
	set_.call("spine", -0.12 + br * 0.5, 0, 0.05)
	set_.call("chest", -0.05 + br, 0, 0.04)
	set_.call("neck", 0.22, 0.35, 0.3)
	set_.call("head", 0.18, 0.55, 0.32 + sin(t * 0.8) * 0.02)
	set_.call("hipL", 1.65, 0.12, 0.08)
	set_.call("kneeL", -1.55, 0, 0)
	set_.call("footL", 0.2, 0, 0)
	set_.call("hipR", 1.6, -0.2, -0.12)
	set_.call("kneeR", -1.45, 0, 0)
	set_.call("footR", 0.25, 0, 0)
	set_.call("shoulderL", 0.75, 0, -0.35)
	set_.call("elbowL", 1.35, 0, 0)
	set_.call("handL", 0, 0, 0.2)
	set_.call("shoulderR", 0.55, 0, 0.45)
	set_.call("elbowR", 1.25, 0, 0)
	set_.call("handR", 0, 0, -0.2)

func _animateKid(tt: float, dt: float) -> void:
	var K = _kid
	if K == null or K.group.get_parent() == null:
		return
	var hero = K.hero
	var f = _path(hero, ["art", "face"])
	if f != null:
		_sp(f, "blinkPhase", 0.46 - (dt if dt else 0.016) / 0.16)       # eyes shut (held mid-blink)
	var anim = _gp(hero, "animator")
	if anim != null:
		_fc(anim, "update", [dt if dt else 0.016, {"speed": 0, "grounded": true}])
	# z Z z: three letters rising from the head, drifting and fading, staggered
	var Jn = _path(hero, ["rig", "joints"])
	var gx := _xf(K.group).affine_inverse()
	if Jn is Dictionary and Jn.get("head") is Node3D and K.zs:
		var v: Vector3 = gx * _xf(Jn.head).origin
		for i in K.zs.size():
			var s: MeshInstance3D = K.zs[i]
			var u := fmod(tt * 0.42 + i / 3.0, 1.0)
			s.position = Vector3(v.x - 0.08 - u * 0.25, v.y + 0.22 + u * 0.55, v.z + sin(u * 6.0 + i) * 0.05)
			var sc := 0.07 + u * 0.12
			s.scale = Vector3(sc, sc, 1)
			var m: ShaderMaterial = s.material_override
			m.set_shader_parameter("opacity", minf(1.0, u * 5.0) * (1.0 - smooth((u - 0.6) / 0.4)))
			m.set_shader_parameter("rotation", sin(u * 5.0 + i) * 0.3)
	# bowl rests on the lap (between the hands)
	if Jn is Dictionary and Jn.get("handL") is Node3D and Jn.get("handR") is Node3D:
		var mid: Vector3 = (_xf(Jn.handL).origin + _xf(Jn.handR).origin) * 0.5
		K.bowl.position = gx * mid + Vector3(0, 0.02, 0)

func _leaveRoom() -> void:
	var room = _room
	if _kid != null:
		DAU.detach(_kid.group)
	if room != null:
		var telly = _gp(room, "telly")
		var R = _tellyRest
		if telly is Node3D and R != null:
			var P: Dictionary = DAU.ud(telly).get("parts", {})
			if P.get("body") is Node3D:
				P.body.position.y = R.bodyY
				P.body.scale = Vector3.ONE * R.bodySX
			if P.get("earL") is Node3D and R.earL != null:
				P.earL.rotation = R.earL
			if P.get("earR") is Node3D and R.earR != null:
				P.earR.rotation = R.earR
			var sg := _tellyFn("setTellyGlove")
			if sg.is_valid():
				sg.call(telly, "hidden")
		_detachSideArm()
		_gloveOut = false
		_fc(room, "setPicture", [null])
		_fc(room, "deactivate")
		if _roomCam != null:
			DAU.detach(_roomCam)
	_room = null

# ------------------------------------------------------------------------------------------ credits (20–32)
func _creditLines() -> Array:
	var H = _heroes()
	var HEROES: Array = H.HEROES if H != null else [
		{"id": "skip", "name": "Skip Kowalski", "role": "Floor runner"}, {"id": "roxy", "name": "Roxy Rivers", "role": "Dance-show host"},
		{"id": "penny", "name": "Penny Watts", "role": "Broadcast engineer"}, {"id": "duke", "name": "Duke Dalton", "role": "Cop-show star"}]
	var me = HEROES[HEROES.size() - 1]
	for h in HEROES:
		if h.id == heroId:
			me = h
			break
	var others := HEROES.filter(func(h): return h != me)
	if _mp():
		# the session's heroes first
		var inSession := {}
		for id in _net().peers:
			inSession[_net().peers[id].get("hero")] = true
		var a1 := others.filter(func(h): return inSession.has(h.id))
		var a2 := others.filter(func(h): return not inSession.has(h.id))
		others = a1 + a2
	var L := []
	var add := func(text: String, kind: String, gap: float = 0.0) -> void:
		L.append({"text": text, "kind": kind, "gap": gap})
	add.call("STARRING", "head", 0)
	add.call(String(me.name).to_upper(), "star", 0.3)
	add.call("as %s of the night shift" % String(me.role).to_lower(), "role", 0.1)
	add.call("CO-STARRING", "head", 1.2)
	for h in others:
		add.call(String(h.name).to_upper(), "name", 0.35)
		add.call("as the %s" % String(h.role).to_lower(), "role", 0.05)
	if _mp():
		# AT THE CONTROLS: every player of the session, as their hero (host first)
		var ids: Array = _net().peers.keys()
		ids.sort_custom(func(a, c): return _net().slotOf(a) < _net().slotOf(c))
		add.call("AT THE CONTROLS", "head", 1.2)
		for id in ids:
			var hn := ""
			for h in HEROES:
				if h.id == _net().peers[id].get("hero"):
					hn = String(h.name)
			add.call(_net().nameOf(id).to_upper(), "name", 0.35)
			add.call("as %s" % hn, "role", 0.05)
	add.call("SPECIAL GUEST STAR", "head", 1.2)
	add.call("BARON VON STATIC", "name", 0.3)
	add.call("as himself", "role", 0.05)
	add.call("WITH", "head", 1.0)
	add.call("TELLY", "name", 0.3)
	add.call("as the television", "role", 0.05)
	add.call("THE TUNED-IN", "name", 0.35)
	add.call("as the studio audience", "role", 0.05)
	add.call("HOOTIE, DUDLEY & SOCKRATES", "name", 0.35)
	add.call("as the puppets", "role", 0.05)
	add.call("STORMY STU", "name", 0.35)
	add.call("as the weather", "role", 0.05)
	add.call("AND", "head", 1.3)
	add.call("WZTV CHANNEL 13", "big", 0.35)
	add.call("good night, and stay tuned", "role", 0.5)
	return L

func _drawCredits(tt: float) -> void:
	var f := _fit()
	var x = f.x
	if x == null:
		return
	var w: float = f.w
	var h: float = f.h
	var s := h / 720.0
	var u := tt - E.credits
	# backdrop: deep indigo, slow 70s sunburst, scanlines
	var bg = x.createRadialGradient(w / 2.0, h * 0.46, 0, w / 2.0, h * 0.46, h * 0.95)
	bg.addColorStop(0, "#3A2466")
	bg.addColorStop(0.55, "#1C1336")
	bg.addColorStop(1, "#0B0818")
	x.fillStyle = bg
	x.fillRect(0, 0, w, h)
	x.save()
	x.translate(w / 2.0, h * 0.46)
	x.rotate(u * 0.05)
	var rays := 18
	var cols := ["rgba(227,102,43,0.13)", "rgba(232,169,46,0.12)", "rgba(181,71,42,0.1)"]
	for i in rays:
		x.fillStyle = cols[i % 3]
		x.beginPath()
		x.moveTo(0, 0)
		x.arc(0, 0, h * 1.2, (float(i) / rays) * TAU, ((i + 0.5) / rays) * TAU)
		x.closePath()
		x.fill()
	x.restore()
	# chrome "13" ident, breathing, with a glint sweeping across
	if _ident == null:
		_ident = chromeIdent()
	var I = _ident
	var iw: float = h * 0.95 * (float(I.width) / I.height)
	var ih: float = h * 0.95
	var pulse := 1.0 + sin(u * 1.2) * 0.012
	var ix := w / 2.0 - (iw * pulse) / 2.0
	var iy := h * 0.46 - (ih * pulse) / 2.0
	x.globalAlpha = 0.9
	x.drawImage(I, ix, iy, iw * pulse, ih * pulse)
	x.globalAlpha = 1
	# glint sweeping across the chrome only (composited on a scratch copy of the ident)
	if _glint == null:
		_glint = _newCanvas(I.width, I.height, "never")
	var gc = _glint
	var gx2 = gc.getContext("2d")
	gx2.globalCompositeOperation = "source-over"
	gx2.clearRect(0, 0, gc.width, gc.height)
	gx2.drawImage(I, 0, 0)
	gx2.globalCompositeOperation = "source-in"
	var gp: float = (fmod(u * 0.3, 1.7) - 0.35) * gc.width
	var gl = gx2.createLinearGradient(gp - 90, 0, gp + 90, gc.height * 0.25)
	gl.addColorStop(0, "rgba(255,255,255,0)")
	gl.addColorStop(0.5, "rgba(255,252,240,0.85)")
	gl.addColorStop(1, "rgba(255,255,255,0)")
	gx2.fillStyle = gl
	gx2.fillRect(0, 0, gc.width, gc.height)
	x.save()
	x.globalCompositeOperation = "lighter"
	x.globalAlpha = 0.55
	x.drawImage(gc, ix, iy, iw * pulse, ih * pulse)
	x.restore()
	star(x, ix + iw * 0.22, iy + ih * 0.3, (22 + 10 * sin(u * 3.0)) * s, 0.8)
	star(x, ix + iw * 0.8, iy + ih * 0.62, (16 + 8 * sin(u * 2.3 + 1.0)) * s, 0.7)
	# dim the ident under the crawl
	x.fillStyle = "rgba(12,8,24,0.42)"
	x.fillRect(0, 0, w, h)
	# the crawl
	if _lines == null:
		_lines = _creditLines()
	var SZ := {"head": 26, "star": 64, "name": 44, "role": 24, "big": 62}
	var LH := {"head": 1.4, "star": 1.2, "name": 1.2, "role": 1.5, "big": 1.25}
	var total := 0.0
	for l in _lines:
		total += (l.gap * 60.0 + SZ[l.kind] * LH[l.kind]) * s
	var dur: float = E.portrait + 0.6 - E.credits
	var off := lerpf(h + 30.0 * s, -total - 30.0 * s, clampf(u / dur, 0.0, 1.0))
	var y := off
	x.textAlign = "center"
	x.textBaseline = "alphabetic"
	for l in _lines:
		y += l.gap * 60.0 * s
		var sz: float = SZ[l.kind] * s
		y += sz * LH[l.kind]
		if y < -40.0 * s or y > h + 60.0 * s:
			continue
		var fade := clampf(minf(y / (h * 0.12), (h - y) / (h * 0.12)), 0.0, 1.0)
		x.globalAlpha = fade
		if l.kind == "head" or l.kind == "role":
			x.font = "%spx %s" % [str(sz), FONTS.logo if l.kind == "head" else FONTS.hud]
			x.fillStyle = "#FFB347" if l.kind == "head" else "#E9D8BE"
			x.fillText(l.text, w / 2.0, y)
		else:
			x.font = "%spx %s" % [str(sz), FONTS.hud]
			x.fillStyle = "#7A2A4A"
			x.fillText(l.text, w / 2.0 + 4.0 * s, y + 4.0 * s)
			x.fillStyle = "#D9602B"
			x.fillText(l.text, w / 2.0 + 2.0 * s, y + 2.0 * s)
			x.fillStyle = "#FFF0C8" if (l.kind == "big" or l.kind == "star") else "#F6E7C8"
			x.fillText(l.text, w / 2.0, y)
	x.globalAlpha = 1
	# scanlines + vignette
	x.fillStyle = "rgba(0,0,0,0.12)"
	var yy := 0.0
	var stepY := 3.0 * maxf(1.0, roundf(s))
	while yy < h:
		x.fillRect(0, yy, w, 1)
		yy += stepY
	var vg = x.createRadialGradient(w / 2.0, h / 2.0, h * 0.35, w / 2.0, h / 2.0, h * 0.95)
	vg.addColorStop(0, "rgba(0,0,0,0)")
	vg.addColorStop(1, "rgba(0,0,0,0.55)")
	x.fillStyle = vg
	x.fillRect(0, 0, w, h)
	# the crawl gives way to the portrait (31.0–31.8)
	var k := clampf((tt - (E.portrait + 0.4)) / 0.8, 0.0, 1.0)
	_dom.canvas.modulate.a = 1.0 - k

# ------------------------------------------------------------------------------------------ portrait + freeze
func _enterPortrait() -> void:
	stage = "portrait"
	if _portrait == null:
		_portrait = _buildPortrait()
	var P = _portrait
	if P == null:
		return
	# JS: render.renderPass.scene / camera = the portrait's (full post: bloom, grade, collapse). Here the portrait's
	# own HDR SubViewport feeds the grade in place of render.view.
	var r = game.render
	var grade = _gp(r, "grade")
	var vp: SubViewport = P.viewport
	var view = _gp(r, "view")
	if view is SubViewport:
		vp.size = view.size
	if grade is ShaderMaterial:
		_savedPass = {"grade": grade, "tex": grade.get_shader_parameter("tDiffuse")}
		grade.set_shader_parameter("tDiffuse", vp.get_texture())
	else:
		_savedPass = {"grade": null}
		var tr: TextureRect = _dom.portrait
		tr.texture = vp.get_texture()
		tr.visible = true

func _buildPortrait():
	var g = game
	var R = g.render
	var vp := SubViewport.new()
	vp.name = "ending_portrait"
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	vp.size = g.get_tree().root.size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.use_hdr_2d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.positional_shadow_atlas_size = 0
	var scene := Node3D.new()
	scene.name = "ending:portrait"
	vp.add_child(scene)
	var env: Environment
	if R != null and R.has_method("makeEnvironment"):
		env = R.makeEnvironment(Color("#1A1226"))
	else:
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("#1A1226")
	# same light counts as lights.gd (hemisphere, key with shadow, fill, 8 points); energies are three intensities
	# THREE.HemisphereLight('#FFE8CC', '#4A3040', 0.9): the DAHemi pair (two specular-less directional lights, sky
	# from above, ground from below: da_common.gdshaderinc)
	for h in [[Color("#FFE8CC"), Vector3.DOWN], [Color("#4A3040"), Vector3.UP]]:
		var hl := DirectionalLight3D.new()
		hl.light_color = h[0]
		hl.light_energy = 0.9
		hl.light_specular = 0.0
		hl.shadow_enabled = false
		hl.transform = Transform3D(Basis.looking_at(h[1], Vector3.FORWARD), Vector3.ZERO)
		scene.add_child(hl)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#FFE2BE")
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.shadow_bias = 0.0006
	key.shadow_normal_bias = 0.03
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 20.0
	scene.add_child(key)
	key.transform = _lookXf(Vector3(-2.2, 4, -3.2), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#A8BCFF")
	fill.light_energy = 0.55
	scene.add_child(fill)
	fill.transform = _lookXf(Vector3(2.5, 1.5, -2), Vector3.ZERO)
	var pts := []
	for i in 8:
		var p := OmniLight3D.new()
		p.light_energy = 0.0
		p.omni_range = 6.0
		p.omni_attenuation = 1.5
		scene.add_child(p)
		pts.append(p)
	pts[0].position = Vector3(0.9, 2.2, -1.4)
	pts[0].light_color = Color("#FFC98A")
	pts[0].light_energy = 3.0
	pts[0].omni_range = 7.0
	pts[1].position = Vector3(-1.4, 1.2, 0.6)
	pts[1].light_color = Color("#FF7AB0")
	pts[1].light_energy = 1.6
	pts[1].omni_range = 5.0
	# the hero's show backdrop + a stage floor (Blender asset: portrait_back 6.4 × 4.8 plane, portrait_floor r 4 disc)
	var backTex = _fc(g.cards, "get", ["promo_%s" % heroId])
	var back: Node3D = _asset("portrait_back")
	if back != null:
		var bm: Material
		if g.mats != null and g.mats.has_method("basic"):
			bm = g.mats.basic("#ffffff" if backTex is Texture2D else "#3A2A5A", {"map": backTex, "fog": false} if backTex is Texture2D else {"fog": false})
		else:
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.albedo_texture = backTex if backTex is Texture2D else null
			sm.albedo_color = Color("#ffffff") if backTex is Texture2D else Color("#3A2A5A")
			bm = sm
		var setb := func(o: Node) -> void:
			if o is MeshInstance3D:
				o.material_override = bm
		DAU.traverse(back, setb)
		back.position = Vector3(0, 1.6, 2.2)
		back.rotation = Vector3(0, PI, 0)
		scene.add_child(back)
	var floor: Node3D = _asset("portrait_floor")
	if floor != null:
		var fmat := _toon("#6B4A3A", {"rough": 0.8, "rim": 0.1, "keepColor": true})
		var setf := func(o: Node) -> void:
			if o is MeshInstance3D:
				o.material_override = fmat
		DAU.traverse(floor, setf)
		floor.rotation = Vector3(-PI / 2.0, 0, 0)
		scene.add_child(floor)
	var hero = _buildHero(heroId)
	if hero != null and _gp(hero, "group") is Node3D:
		var hg: Node3D = _gp(hero, "group")
		scene.add_child(hg)
		hg.rotation_order = EULER_ORDER_XYZ
		hg.rotation.y = -0.4
		var shadows := func(o: Node) -> void:
			if o is GeometryInstance3D:
				o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		DAU.traverse(hg, shadows)
		var face = _path(hero, ["art", "face"])
		if face != null:
			_sp(face, "auto", false)
			_fc(face, "setExpression", ["smile", 1])
			_fc(face, "setLook", [0.1, 0.05])
	else:
		hero = null
	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.near = 0.05
	camera.far = 40.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.environment = env
	# full colour while this scene renders (no pre-power grade / colour wave, heroes never dither-fade: the render.gd
	# CAM_FULLCOLOR camera flag) and no game.scene fog (CAM_NOFOG)
	camera.cull_mask = 1 | (1 << 18) | (1 << 19)
	camera.current = true
	scene.add_child(camera)
	camera.transform = _lookXf(Vector3(0.35, 1.25, -3.1), Vector3(0, 1.0, 0))
	_dom.ov.add_child(vp)
	return {"scene": scene, "camera": camera, "hero": hero, "frozen": false, "t": 0.0, "viewport": vp}

func _updatePortrait(tt: float, dt: float) -> void:
	var P = _portrait
	if P == null or P.frozen or P.hero == null:
		return
	var h = P.hero
	P.t += dt
	var anim = _gp(h, "animator")
	if anim != null:
		_fc(anim, "pose", ["commercial_%s" % heroId, minf(1.0, P.t / 0.5)])
		_fc(anim, "update", [dt if dt else 0.016, {"speed": 0, "grounded": true}])
	var cam: Camera3D = P.camera
	var k := smooth((tt - E.portrait) / (E.freeze - E.portrait))
	var p := Vector3(lerpf(0.55, 0.3, k), lerpf(1.3, 1.22, k), lerpf(-3.4, -2.9, k))
	cam.transform = _lookXf(p, Vector3(0, 1.02, 0))

func _freeze() -> void:
	var D = _dom
	stage = "freeze"
	if _portrait != null:
		_portrait.frozen = true
	# sepia on the rendered picture itself (the CSS filter on the WebGL canvas, transition .45s ease)
	D.sepia.visible = true
	D.ov.tween(D.sepia.material, "shader_parameter/amount", 1.0, 0.45, "ease")
	D.ov.tween(D.warm, "modulate:a", 1.0, 0.45, "ease")
	D.ov.tween(D.frame, "modulate:a", 1.0, 0.45, "ease")
	D.canvas.modulate.a = 0.0
	D.flash.modulate.a = 0.85
	D.ov.tween(D.flash, "modulate:a", 0.0, 0.5, "ease", 0.85)
	var post = _post()
	if post != null:
		_savedGrain = post.get("grain")
		post.grain = 0.12
		post.saturation = 0.35
	_play("studio_flash", {"vol": 0.8})
	_play("commercial_cut", {"vol": 0.6, "delay": 0.05})

# ------------------------------------------------------------------------------------------ STAY TUNED?
func _showCard() -> void:
	var g = game
	stage = "card"
	g.victory()
	var D = _dom
	_glyphs()
	if _mp():
		if _host():
			_cardT = 0.0
			_cardPeers[_net().localId] = true
		else:
			_net().toHost("ending", "atCard", [])
		_cardTick(0.0)
	D.on = true
	var card: Card = D.card
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	D.ov.tween(card, "scaleK", 1.0, 0.5, [0.2, 1.4, 0.4, 1.0])
	D.ov.tween(card, "modulate:a", 1.0, 0.35, "ease")
	_play("ui_menu_clack", {"vol": 0.8})
	_hot = null

# Xbox pad (input.gd routes every pad press here first while the ending runs).
func padButton(btn: String) -> bool:
	if not active or game.state == "paused" or game.get("mpPaused") == true:
		return false
	if stage == "card":
		if btn == "a":
			_choose("y")
			return true
		if btn == "b":
			_choose("n")
			return true
		return false
	if btn != "a":
		return false
	_key({"code": "Enter"})
	return true

# STAY TUNED? key caps: Y / N on the keyboard, A / B (green / red) on the pad.
func _glyphs() -> void:
	var D = _dom
	if D == null:
		return
	var pad: bool = _gp(game.input, "device") == "pad"
	D.card.pad = pad
	D.card.queue_redraw()

# e = { code } (KeyboardEvent.code). Returns true when the key was consumed (preventDefault).
func _key(e: Dictionary) -> bool:
	if not active or game.state == "paused" or game.get("mpPaused") == true:
		return false
	var k: String = e.get("code", "")
	if stage == "card":
		if k == "KeyY":
			_choose("y")
			return true
		elif k == "KeyN":
			_choose("n")
			return true
		return false
	if (k == "Space" or k == "Enter" or k == "KeyE") and seen and t >= E.skipAfter and t < E.freeze:
		_skip()
		return true
	return false

func _skip() -> void:
	var g = game
	if boss != null:
		boss.cleanupAfterEnding()
	_leaveRoom()
	var post = _post()
	if post != null:
		post.collapse = 0.0
	if g.audio != null:
		_fc(g.audio, "stopAll")
	_music("credits")
	for k in ["headSnd", "viewSnd", "black", "wink", "room", "lullaby", "wake", "boing", "ploop", "giggle", "zip", "offSnd", "silence", "credits"]:
		_flags[k] = true
	_paintBlack(1)
	t = E.portrait
	_flags.portrait = true
	_enterPortrait()
	t = E.freeze - 0.4

func _choose(c: String, force := false) -> void:
	if not active or stage != "card":
		return
	if _mp():
		# MP: the host's call, once every peer reached its card (clients' buttons are dimmed)
		if _client() or (not force and not _cardReady()):
			_play("ui_denied", {"vol": 0.5})
			return
		_net().everyone("ending", "choose", [c])
		return
	_play("ui_tune_in", {"vol": 0.8})
	if c == "y":
		morningShow()
	else:
		results()

# N: the results card, then the title.
func results() -> void:
	var g = game
	var sm = summary if not summary.is_empty() else {"round": round, "kills": 0, "points": 0}
	if _mp() and not sm.has("players"):
		sm = _net().teamSummary()
	_finishSequence()
	if boss != null:
		boss.finish()
	if g.menu != null:
		var done := func() -> void:
			if game.menu != null:
				_fc(game.menu, "showTitle")
		_fc(g.menu, "showResults", [sm, {"title": "GOOD NIGHT", "onDone": done}])

# Tears the sequence down (overlay, render pass, camera, post) without touching the world state.
func _finishSequence() -> void:
	var g = game
	if _dom != null:
		_dom.keys.enabled = false
	_leaveRoom()
	if _savedPass != null:
		if _savedPass.grade != null:
			var view = _gp(g.render, "view")
			_savedPass.grade.set_shader_parameter("tDiffuse", view.get_texture() if view is SubViewport else _savedPass.tex)
		_dom.portrait.visible = false
		_dom.portrait.texture = null
	_savedPass = null
	var post = _post()
	if post != null:
		post.collapse = 0.0
		post.saturation = 1.0
		if _savedGrain != null:
			post.grain = _savedGrain
			_savedGrain = null
	if _dom != null:
		var D = _dom
		D.ov.stopAll()
		D.sepia.visible = false
		(D.sepia.material as ShaderMaterial).set_shader_parameter("amount", 0.0)
		D.on = false
		D.card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		D.card.modulate.a = 0.0
		D.card.scaleK = 0.6
		D.warm.modulate.a = 0.0
		D.frame.modulate.a = 0.0
		D.flash.modulate.a = 0.0
		_show(false)
	if g.cam != null:
		_sp(g.cam, "enabled", true)
	if _camFrom != null and g.camera != null:
		g.camera.fov = _camFrom.fov
	var p = g.player
	if p != null:
		if _mp() or (p.has_method("isLockKey") and p.isLockKey("ending")):
			_hold(p, false)
		else:
			_sp(p, "controlLocked", false)
			_sp(p, "invulnerable", false)
	active = false
	stage = "done"
	if _portrait != null:
		var vp: SubViewport = _portrait.viewport
		DAU.detach(vp)
		vp.queue_free()
	_portrait = null

func stop() -> void:
	if not active and stage != "done" and _dom == null:
		return
	if active:
		_finishSequence()
	stage = null
	t = 0.0

# ------------------------------------------------------------------------------------------ the Morning Show
func morningShow() -> void:
	var g = game
	var rnd: int = round if round else (int(_gp(g.rounds, "round", 0)) if _gp(g.rounds, "round", 0) else 1)
	_finishSequence()
	if boss != null:
		boss.finish()
	if g.menu != null:
		_fc(g.menu, "hideAll")
	g.setState("playing")
	var p = g.player
	if p != null and _mp():
		var s: Vector2 = MORNING_SPOTS[clampi(_net().slotOf(_net().localId), 0, MORNING_SPOTS.size() - 1)]
		_fc(p, "teleport", [s.x, s.y, -PI / 2.0 + 0.25])
	elif p != null:
		_fc(p, "teleport", [41.2, -9.6, -PI / 2.0 + 0.25])
	if p != null:
		_sp(p, "health", _gp(p, "maxHealth"))
		_sp(p, "invulnerable", true)
		var off := func() -> void:
			if is_same(game.player, p):
				_sp(p, "invulnerable", false)
		g.get_tree().create_timer(2.5).timeout.connect(off)
	if g.hud != null:
		_fc(g.hud, "show")
	morning = true
	_applyDawn()
	if g.perks != null:
		_fc(g.perks, "morningShow")
	var W = g.weapons
	var slots = _gp(W, "slots", [])
	if slots is Array:
		for s in slots.duplicate():
			var sid = _gp(s, "id")
			if s == null or not sid:
				continue
			if _gp(s, "upgraded", false):
				_fc(W, "refill", [sid])
			else:
				_fc(W, "upgrade", [sid, SIGNALS[int(floor(randf() * SIGNALS.size()))], "uplink"])
	if g.economy != null:
		_fc(g.economy, "add", [MORNING_BONUS, "morning"])
	_wrapTelly()
	var tb = _path(g.level, ["objects", "tower_beacons"])
	if tb != null:
		var eggStep = _gp(g.egg, "step", 0)
		_fc(tb, "setMode", ["rainbow" if float(eggStep if eggStep != null else 0) >= 4 else "blink"])
	_music("morning")
	if g.rounds != null and not _client():
		_fc(g.rounds, "startRound", [rnd + 1])     # MP: the host's round start replicates
	_music("morning")
	g.events.emit("game:morning", {"round": rnd + 1})
	if g.input != null:
		_fc(g.input, "requestLock")

func _applyDawn() -> void:
	var g = game
	var L = g.level
	if _dawn != null:
		return
	var D := {"sky": null, "stars": null, "moon": null, "areas": {}, "key": null, "fill": null, "keyDir": null, "pools": [], "sun": null, "clocks": []}
	# sky dome, stars, moon
	var BL = _B()
	var sky = _gp(L, "sky")
	var visit := func(o: Node) -> void:
		if o is MeshInstance3D:
			var m = (o as MeshInstance3D).material_override
			if m == null and (o as MeshInstance3D).mesh != null:
				m = (o as MeshInstance3D).get_active_material(0)
			if m is ShaderMaterial and m.shader != null:
				var names := {}
				for u in m.shader.get_shader_uniform_list():
					names[u.name] = true
				if names.has("uTop") and names.has("uHorizon"):
					D.sky = {"mesh": o, "mat": m, "top": m.get_shader_parameter("uTop"), "hor": m.get_shader_parameter("uHorizon"),
						"glow": m.get_shader_parameter("uGlow") if names.has("uGlow") else null, "ground": m.get_shader_parameter("uGround") if names.has("uGround") else null,
						"hasGlow": names.has("uGlow"), "hasGround": names.has("uGround")}
		if boss != null and boss._isStars(o):
			D.stars = o
		if boss != null and boss._isMoon(o):
			D.moon = o
	if sky is Node:
		DAU.traverse(sky, visit)
	if D.sky != null:
		var m: ShaderMaterial = D.sky.mat
		m.set_shader_parameter("uTop", Color(Config.PAL.dawn3))
		m.set_shader_parameter("uHorizon", Color(Config.PAL.dawn1))
		if D.sky.hasGlow:
			m.set_shader_parameter("uGlow", Color(Config.PAL.dawn2))
		if D.sky.hasGround:
			m.set_shader_parameter("uGround", Color("#4A2E36"))
	if D.stars != null:
		D.stars.visible = false
	if D.moon != null:
		D.moon.visible = false
	if sky is Node3D:
		var sun: MeshInstance3D = BL.sprite(BL.spriteMat(_sunTex(), BL.linColor("#FFE2A8", 2.2), true, true, -7), "ending_sun")
		sun.position = Vector3(1, 0.2, -0.18).normalized() * 120.0
		sun.scale = Vector3.ONE * 46.0
		sun.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		(sky as Node3D).add_child(sun)
		D.sun = sun
	# warm dawn ambient everywhere, a haze outside
	var warm := Color("#FFD6A8").srgb_to_linear()
	var warmG := Color("#8A5A3A").srgb_to_linear()
	var areas = _gp(L, "areas", {})
	if areas is Dictionary:
		for id in areas:
			var a = areas[id]
			var amb = _gp(a, "ambient")
			D.areas[id] = {"ambient": amb, "ambientPre": _gp(a, "ambientPre"), "fog": _gp(a, "fog")}
			if amb is Dictionary:
				var inten = amb.get("intensity")
				_sp(a, "ambient", {
					"sky": "#" + Color(amb.get("sky", "#ffffff")).srgb_to_linear().lerp(warm, 0.55).linear_to_srgb().to_html(false),
					"ground": "#" + Color(amb.get("ground", "#ffffff")).srgb_to_linear().lerp(warmG, 0.4).linear_to_srgb().to_html(false),
					"intensity": (float(inten) if inten != null else 0.8) * 1.12})
			if id == "yard":
				_sp(a, "fog", {"color": "#F2B08A", "near": 30, "far": 150})
	var lt = g.lights
	var lkey = _gp(lt, "key")
	var lfill = _gp(lt, "fill")
	if lkey is Light3D:
		D.key = lkey.light_color
		lkey.light_color = Color("#FFC48E")
	if lfill is Light3D:
		D.fill = lfill.light_color
		lfill.light_color = Color("#FFB0C8")
	var kd = _gp(lt, "keyDir")
	if kd is Vector3:
		D.keyDir = kd
		_sp(lt, "keyDir", Vector3(0.85, 0.52, 0.2).normalized())
	# dawn light through every window: warm pools on the floor inside
	var wins = _gp(L, "windows", {})
	if wins is Dictionary and g.fx != null:
		for wk in wins:
			var ins = _gp(wins[wk], "inside")
			if ins == null:
				continue
			var pos := Vector3(ins[0], 0.02, ins[2]) if ins is Array else Vector3(_gp(ins, "x", 0.0), 0.02, _gp(ins, "z", 0.0))
			var h = _fc(g.fx, "lightPool", [pos, 2.4, "#FFC48A", 0.5])
			if h != null:
				D.pools.append(h)
	# clocks: 12:00, ticking from now
	var lc = _path(L, ["objects", "lobby_clock"])
	if lc != null:
		_fc(lc, "setMidnight", [true])
	var seenPar := []
	var lroot = _gp(L, "root")
	var clk := func(o: Node) -> void:
		if String(o.name) != "minute" or seenPar.has(o.get_parent()):
			return
		var par := o.get_parent()
		var hour = par.find_child("hour", true, false)
		var sec = par.find_child("second", true, false)
		if not (hour is Node3D):
			return
		seenPar.append(par)
		for n in [hour, o, sec]:
			if n is Node3D:
				n.rotation_order = EULER_ORDER_XYZ
		D.clocks.append({"hour": hour, "minute": o, "second": sec, "rest": [hour.rotation.z, o.rotation.z, sec.rotation.z if sec is Node3D else 0.0]})
	if lroot is Node:
		DAU.traverse(lroot, clk)
	D.clockT = 0.0
	_dawn = D

# 128² sun: white-hot core, warm halo (radial gradient stops 0, 0.18, 0.22, 1).
func _sunTex() -> Texture2D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var st := [[0.0, Color(1, 1, 240 / 255.0, 1)], [0.18, Color(1, 240 / 255.0, 200 / 255.0, 1)], [0.22, Color(1, 200 / 255.0, 140 / 255.0, 0.55)], [1.0, Color(1, 160 / 255.0, 110 / 255.0, 0)]]
	for y in 128:
		for x in 128:
			var d := Vector2(x + 0.5 - 64.0, y + 0.5 - 64.0).length() / 64.0
			img.set_pixel(x, y, _B()._stops(minf(d, 1.0), st))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _tickMorning(rdt: float) -> void:
	var D = _dawn
	if D == null:
		return
	D.clockT += rdt
	var s: float = D.clockT
	var ang := func(h: float, m: float, sec: float) -> Array:
		return [(fmod(h, 12.0) + m / 60.0 + sec / 3600.0) / 12.0 * TAU, (m + sec / 60.0) / 60.0 * TAU, (sec / 60.0) * TAU]
	var m := floorf(s / 60.0)
	var sec := floorf(fmod(s, 60.0)) + minf(1.0, fmod(s, 1.0) / 0.08) - 1.0 + 1.0
	var A: Array = ang.call(12.0, m + floorf(sec / 60.0), fmod(sec, 60.0))
	for c in D.clocks:
		c.hour.rotation.z = A[0]
		c.minute.rotation.z = A[1]
		if c.second is Node3D:
			c.second.rotation.z = A[2]

# Telly in the Morning Show: never signs off again, 13-point pulls (wraps the machine_telly interactable).
func _wrapTelly() -> void:
	var g = game
	var telly = g.telly
	var items = _path(g.interact, ["items"])
	var it = null
	if items is Dictionary:
		it = items.get("machine_telly")
	elif items != null:
		it = _fc(items, "get_", ["machine_telly"])
	if it == null or telly == null or _gp(it, "_morning") != null:
		return
	var op = _gp(it, "prompt")
	var ou = _gp(it, "use")
	_sp(it, "_morning", {"prompt": op, "use": ou})
	var pr := func():
		var r = op.call() if op is Callable and op.is_valid() else null
		if r is Dictionary and r.has("cost"):
			var c: Dictionary = r.duplicate()
			c.cost = TELLY_MORNING_COST
			return c
		return r
	var use := func() -> void:
		var can: bool = bool(_fc(telly, "canPull")) if _hasFn(telly, "canPull") else false
		if not can or _gp(telly, "seq") != null:
			if ou is Callable and ou.is_valid():
				ou.call()
			return
		if _mp():
			# MP: telly.pull spends the 13 itself and turns it into the host request; the host rolls rollTelly(exclude)
			var owned := []
			for s in _gp(game.weapons, "slots", []):
				if _gp(s, "id"):
					owned.append(str(_gp(s, "id")))
			_fc(telly, "pull", [{"morning": true, "cost": TELLY_MORNING_COST, "exclude": owned}])
			return
		if not _fc(game.economy, "spend", [TELLY_MORNING_COST, "telly"]):
			return
		_fc(telly, "pull", [{"free": true, "forced": _rollTelly()}])
	_sp(it, "prompt", pr)
	_sp(it, "use", use)
	_sp(telly, "morning", true)
	_tellyWrapped = it

func _rollTelly() -> String:
	var g = game
	var telly = g.telly
	var W: Dictionary = Config.T.telly.weights
	var pool := []
	var total := 0.0
	for id in W:
		var ex := false
		if _hasFn(telly, "_excluded"):
			ex = bool(_fc(telly, "_excluded", [id]))
		else:
			ex = id != "tiny_tele" and bool(_fc(g.weapons, "has", [id]))
		if ex:
			continue
		pool.append([id, W[id]])
		total += W[id]
	var x := randf() * total
	for e in pool:
		x -= e[1]
		if x < 0.0:
			return e[0]
	return pool[pool.size() - 1][0] if pool.size() else "revolver_38"

# MP host (mp-machines' morning pull): the forced Morning Show item for a requester owning `owned` (weapon ids).
func rollTelly(owned = []) -> String:
	var W: Dictionary = Config.T.telly.weights
	var pool := []
	var total := 0.0
	for id in W:
		if id != "tiny_tele" and owned is Array and owned.has(id):
			continue
		pool.append([id, W[id]])
		total += W[id]
	var x := randf() * total
	for e in pool:
		x -= e[1]
		if x < 0.0:
			return e[0]
	return pool[pool.size() - 1][0] if pool.size() else "revolver_38"

func _undoMorning() -> void:
	var g = game
	var D = _dawn
	morning = false
	if _tellyWrapped != null:
		var it = _tellyWrapped
		var mo = _gp(it, "_morning")
		if mo != null:
			_sp(it, "prompt", mo.prompt)
			_sp(it, "use", mo.use)
			if it is Dictionary:
				it.erase("_morning")
			else:
				_sp(it, "_morning", null)
		if g.telly != null:
			_sp(g.telly, "morning", false)
		_tellyWrapped = null
	if D == null:
		return
	if D.sky != null:
		var m: ShaderMaterial = D.sky.mat
		m.set_shader_parameter("uTop", D.sky.top)
		m.set_shader_parameter("uHorizon", D.sky.hor)
		if D.sky.hasGlow:
			m.set_shader_parameter("uGlow", D.sky.glow)
		if D.sky.hasGround:
			m.set_shader_parameter("uGround", D.sky.ground)
	if D.stars != null and is_instance_valid(D.stars):
		D.stars.visible = true
	if D.moon != null and is_instance_valid(D.moon):
		D.moon.visible = true
	if D.sun != null:
		DAU.detach(D.sun)
		D.sun.queue_free()
	var areas = _gp(g.level, "areas", {})
	for id in D.areas:
		var a = areas.get(id) if areas is Dictionary else null
		if a != null:
			_sp(a, "ambient", D.areas[id].ambient)
			_sp(a, "fog", D.areas[id].fog)
	var lt = g.lights
	var lkey = _gp(lt, "key")
	var lfill = _gp(lt, "fill")
	if lkey is Light3D and D.key != null:
		lkey.light_color = D.key
	if lfill is Light3D and D.fill != null:
		lfill.light_color = D.fill
	if D.keyDir != null:
		_sp(lt, "keyDir", D.keyDir)
	for p in D.pools:
		_fc(p, "remove")
	for c in D.clocks:
		c.hour.rotation.z = c.rest[0]
		c.minute.rotation.z = c.rest[1]
		if c.second is Node3D:
			c.second.rotation.z = c.rest[2]
	var lc = _path(g.level, ["objects", "lobby_clock"])
	if lc != null:
		_fc(lc, "setMidnight", [false])
	_dawn = null

# ------------------------------------------------------------------------------------------ debug
func debugPlay(o: Dictionary = {}):
	var b = boss
	if active:
		return debugState()
	if b != null and not b.active:
		b.debugStart({"round": o.get("round"), "skipIntro": true})
	if b != null:
		b.debugKill()
	else:
		play(o)
	return debugState()

# Jump the timeline to t (every beat before t fires in order; continuous stages pick up at t).
func debugSeek(to: float):
	if not active:
		return null
	var target := maxf(t, to)
	var step := 0.05
	var ts := timeScale
	timeScale = 1.0
	while t < target - 1e-6 and stage != "card":
		update(minf(step, target - t))
	timeScale = ts
	return debugState()

func debugChoose(c: String):
	if stage != "card":
		debugSeek(E.card + 0.01)
	_choose("n" if c == "n" else "y", true)
	return debugState()

func debugState() -> Dictionary:
	return {"active": active, "stage": stage, "t": snappedf(t, 0.01), "seen": seen, "morning": morning, "hero": heroId if heroId else null,
		"unlock": storeGet(KEY), "room": _room != null, "portrait": _portrait != null, "card": _dom != null and _dom.on}

# ================================================================================================ overlay controls
# CSS filter: sepia(0.92) saturate(1.15) contrast(1.06) brightness(0.96) on the picture under the overlay; `amount`
# is the .45 s transition from none.
const SEPIA_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float s = 1.0 - 0.92 * amount;
	vec3 p = vec3(
		(0.393 + 0.607 * s) * c.r + (0.769 - 0.769 * s) * c.g + (0.189 - 0.189 * s) * c.b,
		(0.349 - 0.349 * s) * c.r + (0.686 + 0.314 * s) * c.g + (0.168 - 0.168 * s) * c.b,
		(0.272 - 0.272 * s) * c.r + (0.534 - 0.534 * s) * c.g + (0.131 + 0.869 * s) * c.b);
	p = clamp(p, 0.0, 1.0);
	float k = 1.0 + 0.15 * amount;
	p = vec3(
		(0.213 + 0.787 * k) * p.r + (0.715 - 0.715 * k) * p.g + (0.072 - 0.072 * k) * p.b,
		(0.213 - 0.213 * k) * p.r + (0.715 + 0.285 * k) * p.g + (0.072 - 0.072 * k) * p.b,
		(0.213 - 0.213 * k) * p.r + (0.715 - 0.715 * k) * p.g + (0.072 + 0.928 * k) * p.b);
	p = clamp(p, 0.0, 1.0);
	p = clamp((p - 0.5) * (1.0 + 0.06 * amount) + 0.5, 0.0, 1.0);
	p *= 1.0 - 0.04 * amount;
	COLOR = vec4(p, 1.0);
}
"""

# radial-gradient(ellipse at 50% 45%, rgba(255,230,190,0) 40%, rgba(40,22,8,.62) 100%) (farthest-corner ellipse).
const WARM_SHADER := """
shader_type canvas_item;
void fragment() {
	vec2 d = vec2((UV.x - 0.5) / 0.78962, (UV.y - 0.45) / 0.71066);
	float g = length(d);
	COLOR = vec4(vec3(40.0, 22.0, 8.0) / 255.0, 0.62 * clamp((g - 0.4) / 0.6, 0.0, 1.0));
}
"""

# inset 3.2vh 3.2vw; border 1.1vh solid #F2E6CC; inset 0 0 4vh rgba(60,30,10,.45); radius .6vh.
const FRAME_SHADER := """
shader_type canvas_item;
float sdRoundBox(vec2 p, vec2 b, float r) { vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = UV * size;
	float vh = size.y / 100.0;
	float vw = size.x / 100.0;
	vec2 half = size * 0.5 - vec2(3.2 * vw, 3.2 * vh);
	float d = sdRoundBox(px - size * 0.5, half, 0.6 * vh);
	float border = 1.1 * vh;
	vec4 col = vec4(0.0);
	if (d <= 0.0 && d >= -border) {
		col = vec4(242.0, 230.0, 204.0, 255.0) / 255.0;
	} else if (d < -border) {
		float e = (-d - border) / (2.0 * vh);
		float a = 0.45 * (1.0 - 1.0 / (1.0 + exp(-1.702 * e)));
		col = vec4(vec3(60.0, 30.0, 10.0) / 255.0, a);
	}
	COLOR = col;
}
"""

# The overlay root: the black fallback cover and the CSS transitions (property tweens with the CSS timing functions,
# driven in real time).
class Overlay extends Control:
	var cover := 0.0
	var _tw := []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	# CSS transition: animate node.prop from its current value to `to` over dur s (curve: "ease" or a cubic-bezier
	# [x1, y1, x2, y2]); `from` forces the start value.
	func tween(node: Object, prop: String, to: float, dur: float, curve, from = null) -> void:
		for i in range(_tw.size() - 1, -1, -1):
			if _tw[i].node == node and _tw[i].prop == prop:
				_tw.remove_at(i)
		var f: float = float(from) if from != null else float(node.get_indexed(prop) if node.get_indexed(prop) != null else 0.0)
		var bz: Array = [0.25, 0.1, 0.25, 1.0] if curve is String else curve
		_tw.append({"node": node, "prop": prop, "from": f, "to": to, "dur": dur, "t": 0.0, "bz": bz})
		node.set_indexed(prop, f)

	func stopAll() -> void:
		_tw.clear()

	func _process(dt: float) -> void:
		for i in range(_tw.size() - 1, -1, -1):
			var w = _tw[i]
			w.t += dt
			var u := clampf(w.t / w.dur, 0.0, 1.0) if w.dur > 0.0 else 1.0
			var k := cubicBezier(u, w.bz[0], w.bz[1], w.bz[2], w.bz[3])
			if is_instance_valid(w.node):
				w.node.set_indexed(w.prop, lerpf(w.from, w.to, k))
			if u >= 1.0:
				_tw.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		if cover > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, cover))

	# CSS cubic-bezier(x1, y1, x2, y2) timing function at progress x.
	static func cubicBezier(x: float, x1: float, y1: float, x2: float, y2: float) -> float:
		if x <= 0.0:
			return 0.0
		if x >= 1.0:
			return 1.0
		var tt := x
		for _i in 8:
			var cx := 3.0 * x1 * tt * (1.0 - tt) * (1.0 - tt) + 3.0 * x2 * tt * tt * (1.0 - tt) + tt * tt * tt - x
			var dx := 3.0 * x1 * (1.0 - tt) * (1.0 - tt) + 6.0 * (x2 - x1) * tt * (1.0 - tt) + 3.0 * (1.0 - x2) * tt * tt
			if absf(cx) < 1e-5:
				break
			if absf(dx) < 1e-6:
				break
			tt = clampf(tt - cx / dx, 0.0, 1.0)
		return 3.0 * y1 * tt * (1.0 - tt) * (1.0 - tt) + 3.0 * y2 * tt * tt * (1.0 - tt) + tt * tt * tt

# window keydown (capture) while the sequence runs: KeyboardEvent.code of the keys the ending listens to.
class KeyCatcher extends Node:
	var ending
	var enabled := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(ev: InputEvent) -> void:
		if not enabled or not (ev is InputEventKey) or not ev.pressed or ev.echo:
			return
		var code := ""
		match (ev as InputEventKey).physical_keycode:
			KEY_Y: code = "KeyY"
			KEY_N: code = "KeyN"
			KEY_E: code = "KeyE"
			KEY_SPACE: code = "Space"
			KEY_ENTER, KEY_KP_ENTER: code = "Enter"
		if code != "" and ending._key({"code": code}):
			get_viewport().set_input_as_handled()

# .de-card: STAY TUNED? with the YES / NO buttons (key caps Y / N, or the pad's A / B), laid out in vh like the CSS.
class Card extends Control:
	var ending
	var fontLogo: Font
	var fontHud: Font
	var pad := false
	var scaleK := 0.6:
		set(v):
			scaleK = v
			queue_redraw()
	var _hover := ""
	var waiting := false             # MP: the buttons are dimmed (not this peer's call / not everyone is here yet)
	var caption := ""                # MP: the line under the buttons
	var _hotK := {"y": 0.0, "n": 0.0}
	var _btn := {"y": Rect2(), "n": Rect2()}
	var _box := Rect2()
	var _padTex := {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(dt: float) -> void:
		if modulate.a <= 0.0:
			return
		if ending != null:
			var w0 := waiting
			var c0 := caption
			ending._cardTick(dt)
			if w0 != waiting or c0 != caption:
				queue_redraw()
		var changed := false
		for k in ["y", "n"]:
			var want := 1.0 if _hover == k else 0.0
			var v: float = _hotK[k]
			if v != want:
				_hotK[k] = move_toward(v, want, dt / 0.12)
				changed = true
		if changed:
			queue_redraw()

	func _vh() -> float:
		return size.y / 100.0

	func _has_point(p: Vector2) -> bool:
		return mouse_filter != MOUSE_FILTER_IGNORE and _toCard(p) != Vector2.INF and _box.has_point(_toCard(p))

	func _toCard(p: Vector2) -> Vector2:
		if scaleK <= 0.0:
			return Vector2.INF
		var c := size * 0.5
		return c + (p - c) / scaleK

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var q := _toCard(ev.position)
			var h := ""
			for k in ["y", "n"]:
				if (_btn[k] as Rect2).has_point(q):
					h = k
			if h != _hover:
				_hover = h
				queue_redraw()
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var q := _toCard(ev.position)
			for k in ["y", "n"]:
				if (_btn[k] as Rect2).has_point(q):
					ending._choose(k)
					accept_event()
					return

	static func rrPoly(r: Rect2, rad: float, seg: int = 8) -> PackedVector2Array:
		rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
		var pts := PackedVector2Array()
		var cs := [[r.position + Vector2(r.size.x - rad, rad), -PI / 2.0], [r.position + r.size - Vector2(rad, rad), 0.0],
			[r.position + Vector2(rad, r.size.y - rad), PI / 2.0], [r.position + Vector2(rad, rad), PI]]
		for c in cs:
			for i in seg + 1:
				var a: float = c[1] + (PI / 2.0) * i / seg
				pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
		return pts

	# rounded rect with a vertical linear gradient (exact: colour is linear in y)
	func _grad(r: Rect2, rad: float, top: Color, bot: Color) -> void:
		var pts := rrPoly(r, rad)
		var cols := PackedColorArray()
		for p in pts:
			cols.append(top.lerp(bot, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
		draw_polygon(pts, cols)

	func _rr(r: Rect2, rad: float, c: Color) -> void:
		draw_colored_polygon(rrPoly(r, rad), c)

	# radial-gradient(circle at 42% 34%, #4A4048, #1E1A20 72%) in a round cap (the pad's face button)
	func _padFace(sz: int) -> Texture2D:
		if _padTex.has(sz):
			return _padTex[sz]
		var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
		var c := Vector2(0.42, 0.34) * sz
		var far := maxf(maxf(c.length(), (Vector2(sz, 0) - c).length()), maxf((Vector2(0, sz) - c).length(), (Vector2(sz, sz) - c).length()))
		for y in sz:
			for x in sz:
				var p := Vector2(x + 0.5, y + 0.5)
				var inside := clampf(sz * 0.5 - p.distance_to(Vector2(sz, sz) * 0.5) + 0.5, 0.0, 1.0)
				var g := clampf(p.distance_to(c) / (far * 0.72), 0.0, 1.0)
				var col := Color("#4A4048").lerp(Color("#1E1A20"), g)
				col.a = inside
				img.set_pixel(x, y, col)
		var tex := ImageTexture.create_from_image(img)
		_padTex[sz] = tex
		return tex

	func _draw() -> void:
		var vh := _vh()
		if vh <= 0.0:
			return
		var c := size * 0.5
		draw_set_transform(c - c * scaleK, 0.0, Vector2(scaleK, scaleK))
		# layout (CSS): padding 4.2vh 6vh 4.6vh; h1 10.5vh (line-height 1, letter-spacing .2vh); row margin-top 3.6vh;
		# buttons: padding 1.2vh 2.6vh 1.2vh 1.2vh, kbd 7vh, gap 1.4vh, font 4.4vh; gap between buttons 4vh
		var h1Size := int(round(10.5 * vh))
		var title := "STAY TUNED?"
		var ls := 0.2 * vh
		var h1W := 0.0
		for ch in title:
			h1W += fontLogo.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, h1Size).x + ls
		var bSize := int(round(4.4 * vh))
		var labels := {"y": "YES", "n": "NO"}
		var bw := {}
		for k in ["y", "n"]:
			bw[k] = 1.2 * vh + 7.0 * vh + 1.4 * vh + fontHud.get_string_size(labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, bSize).x + 2.6 * vh
		var bh := 9.4 * vh
		var rowW: float = bw.y + 4.0 * vh + bw.n
		var innerW := maxf(h1W, rowW)
		var W := innerW + 12.0 * vh
		var H := (4.2 + 10.5 + 3.6 + 9.4 + 4.6) * vh
		var box := Rect2(c - Vector2(W, H) * 0.5, Vector2(W, H))
		_box = box
		# box-shadow: 0 2vh 6vh rgba(0,0,0,.6) (soft), 0 0 0 1.4vh #D9602B, 0 0 0 .7vh #F2C14E; radius 3vh
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = int(6.0 * vh)
		sb.shadow_offset = Vector2(0, 2.0 * vh)
		sb.set_corner_radius_all(int(3.0 * vh))
		draw_style_box(sb, box)
		_rr(box.grow(1.4 * vh), 4.4 * vh, Color("#D9602B"))
		_rr(box.grow(0.7 * vh), 3.7 * vh, Color("#F2C14E"))
		_grad(box, 3.0 * vh, Color("#3A2458"), Color("#1D1330"))
		# h1: #FFE9B8 with text-shadow .45vh .45vh #D9602B, .9vh .9vh #7A2A4A
		var asc := fontLogo.get_ascent(h1Size)
		var desc := fontLogo.get_descent(h1Size)
		var baseY := box.position.y + 4.2 * vh + (10.5 * vh - (asc + desc)) * 0.5 + asc
		var x0 := c.x - h1W * 0.5
		for layer in [[Vector2(0.9, 0.9), Color("#7A2A4A")], [Vector2(0.45, 0.45), Color("#D9602B")], [Vector2.ZERO, Color("#FFE9B8")]]:
			var x := x0
			for ch in title:
				draw_string(fontLogo, Vector2(x, baseY) + layer[0] * vh, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, h1Size, layer[1])
				x += fontLogo.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, h1Size).x + ls
		# the YES / NO buttons
		var rowY := box.position.y + (4.2 + 10.5 + 3.6) * vh
		var bx := c.x - rowW * 0.5
		for k in ["y", "n"]:
			var r := Rect2(Vector2(bx, rowY), Vector2(bw[k], bh))
			_btn[k] = r
			bx += bw[k] + 4.0 * vh
			var hk: float = _hotK[k]
			var bc := r.get_center()
			var sc := 1.0 + 0.06 * hk
			draw_set_transform(c - c * scaleK + bc * scaleK * (1.0 - sc), 0.0, Vector2(scaleK * sc, scaleK * sc))
			_rr(r, 1.6 * vh, Color(1, 1, 1, 0.06).lerp(Color(1, 210 / 255.0, 120 / 255.0, 0.18), hk))
			var kr := Rect2(r.position + Vector2(1.2 * vh, 1.2 * vh), Vector2(7.0 * vh, 7.0 * vh))
			var kSize := int(round(4.6 * vh))
			var glyph := ("A" if k == "y" else "B") if pad else ("Y" if k == "y" else "N")
			var gcol := Color("#2A1D3A")
			if pad:
				_rr(Rect2(kr.position + Vector2(0, 0.6 * vh), kr.size), kr.size.x * 0.5, Color("#0E0A10"))
				draw_texture_rect(_padFace(maxi(8, int(kr.size.x))), kr, false)
				gcol = Color("#7EDB5A") if k == "y" else Color("#FF6A5C")
			else:
				_rr(Rect2(kr.position + Vector2(0, 0.6 * vh), kr.size), 1.4 * vh, Color("#9A6A2A"))
				_grad(kr, 1.4 * vh, Color("#FFF3D6"), Color("#E8C98A"))
			var gs := fontHud.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, kSize)
			var ga := fontHud.get_ascent(kSize)
			var gd := fontHud.get_descent(kSize)
			draw_string(fontHud, Vector2(kr.get_center().x - gs.x * 0.5, kr.get_center().y - (ga + gd) * 0.5 + ga), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, kSize, gcol)
			var ta := fontHud.get_ascent(bSize)
			var td := fontHud.get_descent(bSize)
			draw_string(fontHud, Vector2(kr.end.x + 1.4 * vh, bc.y - (ta + td) * 0.5 + ta), labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, bSize, Color("#F6E7C8"))
			draw_set_transform(c - c * scaleK, 0.0, Vector2(scaleK, scaleK))
		# MP: not this peer's call (or not everyone tuned in yet): dimmed buttons + a caption under the card
		if waiting:
			for k in ["y", "n"]:
				_rr(_btn[k], 1.6 * vh, Color(29 / 255.0, 19 / 255.0, 48 / 255.0, 0.62))
		if caption != "":
			var cs := int(round(2.6 * vh))
			var cw := fontHud.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
			var cp := Vector2(c.x - cw * 0.5, box.end.y + 2.4 * vh + fontHud.get_ascent(cs))
			draw_string(fontHud, cp + Vector2(0.3, 0.3) * vh, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color("#7A2A4A"))
			draw_string(fontHud, cp, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color("#FFE9B8"))
