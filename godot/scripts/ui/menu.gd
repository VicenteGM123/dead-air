# DEAD AIR — menus (GDD §14 menus, §4 character select, §6.5 game over, §13 results). Port of src/ui/menu.js.
# Text is allowed here (menus only); gameplay controls are shown ONLY on the pause menu's Controls card.
#
# THE LIVING ROOM (title + character select): a cozy 1977 living room at night (shag, wood paneling, the moon in the
#   window, a lamp, a lava lamp, a cloud sofa) built lazily from the prop kit around Telly's walnut console TV (the
#   'telly' prop with its face switched off: the ending reveals it is Telly). While a menu shows it, the render
#   pipeline draws this scene with the menu camera (full post: bloom, grade, collapse); the station scene is not
#   drawn. The TV picture is a render target composited every frame (snow, vertical roll, hold jitter, the picture,
#   an overlay canvas with the OSD channel number and the chyron) and mapped onto the TV's CRT glass.
#   - Title: the TV tunes from snow to the DEAD AIR logo (cards.gd logo_dead_air); "PRESS ANY KEY". With the
#     persistent unlock (deadair.signoff = "1") the TV shows a sunrise instead of snow.
#   - Character select: the camera dollies in; the VHF dial (A/D, arrows, mouse wheel, click on the dial or the
#     arrows) clacks through the promo channels 2 Skip / 4 Roxy / 5 Penny / 7 Duke (Duke preselected, or char=).
#     Each channel shows the hero (heroes.gd buildHero) posed on their show's set (promo_<hero> backdrop + a few
#     props), a chyron with name and role, and the hero's leitmotif (audio.music('select:<id>')). E / Enter / Space /
#     a click on the screen "tunes in": the camera dives into the screen, white flash, game.newGame(heroId). Esc goes
#     back to the title. With the unlock every hero wears a gold 13.
# PAUSE: the PLEASE STAND BY card (sleepy Telly, animated) on a TV, with Resume / Options / Controls / Quit.
#   Options (persisted in user://deadair.cfg, key deadair.options, applied at boot): mouse sensitivity, gamepad look
#   sensitivity, invert Y (mouse + pad), FOV 60-90, hold/toggle aim and sprint, pad aim assist, pad vibration, volume
#   buses (master, music, sfx, ambience, tv, ui), quality preset (pixel-ratio cap), CRT vignette (hud.setCrt).
#   Keyboard (W/S, A/D, Enter/E, Esc), mouse and Xbox pad. Quit asks twice, then goes to the title. The Controls card
#   lists the keyboard/mouse and the Xbox layout side by side (the column of the last used device is highlighted).
# GAMEPAD: input.gd calls padButton(name) for every pad press while a menu shows (names: a b x y lb rb lt rt start
#   back l3 r3 up down left right; D-pad and left stick repeat). Title / game over / results: any button. Select:
#   left/right (or LB/RB) change channel, A (or Start) tunes in, B back to the title. Pause: up/down + A, left/right
#   on options, B backs out / resumes, Start / View resume. Glyphs follow input.device ('input:device' event):
#   PRESS ANY BUTTON, the select Dymo shows a round green A instead of E.
# GAME OVER (GDD §6.5): sting_gameover (tape-stop, hum, silence, 1 kHz), the picture drains and rolls, CRT collapse
#   (render.post.collapse: white line, dot), black, then at 2.9 s (with the 1 kHz) the PLEASE STAND BY test card with
#   Telly asleep, the round in big split-flap digits, kills and points small. After 2 s any key -> character select.
# RESULTS (for the ending team): showResults({round, kills, points}, {title, onDone}) -> the same card layout, awake
#   Telly; after 2 s any key -> onDone() (default: the title).
#
# API (game.menu)
#   selected                      preselected hero id (params.char if valid, else DEFAULT_HERO = duke); updated by select
#   mode                          null | 'title' | 'select' | 'tunein' | 'pause' | 'over' | 'results'
#   showLoading() (real boot, before the room exists)  showTitle() showSelect() showPause() hidePause() showGameOver({round, kills, points}) showVictory({round})
#   showResults(summary, { title = 'GOOD NIGHT', onDone }) hideAll()
#   tune(dir) (+1 / -1 channel)  tuneIn()  options (Dictionary) setOption(key, value) (persists + applies)
#   getLivingRoom() -> { scene, camera, telly, parts, root, setPicture(texture|null), activate(camera?), deactivate() }
#       the character-select room for the ending (build it lazily, draw it through the normal pipeline with
#       activate(); setPicture puts any texture on the TV glass, null gives it back to the menu). A Dictionary whose
#       functions are Callables.
#   update(dt) (real dt, every state)  reset() (newGame)  preloadSteps() (coroutine: await it)
# showVictory: when an ending system is running (game.ending.active / .playing) the menu stays out of its way;
#   otherwise it shows the results card ("SIGN-OFF"). test=1 never shows a menu before play (Game auto-starts).
#
# Godot port notes (engine plumbing): the living room is a Node3D under render.view (the HDR SubViewport the grade
#   pass reads) next to game.scene; while it shows, game.scene is hidden and the room camera (cull_mask flags
#   CAM_FULLCOLOR + CAM_NOFOG = the JS _fullColor and a fog that never reaches this small room) is the current
#   camera, so the frame goes through the same bloom + grade + collapse. The room's static geometry (shell, window,
#   night sky, curtains, popcorn, TV guide) and the sets' backdrops / floors / gold badge are the Blender runtime
#   asset blender/runtime/menu.py -> res://assets/runtime/menu/{room,sets}.glb. The hero sets render in their own
#   SubViewport (own World3D, HDR) and the TV compositor is a 2D HDR SubViewport running the COMP_FRAG port; its
#   texture is the Telly screen's map. The dust motes are a points mesh with the DUST shaders. The DOM/CSS surfaces
#   are a CanvasLayer (layer 20) painted like hud.gd (SVG-rasterized CSS boxes, bundled fonts, CSS timing functions);
#   canvases (TV overlay, title logo, sunrise, stand-by cards) are DACanvas (scripts/gfx/canvas2d.gd).
#   localStorage -> ConfigFile user://deadair.cfg (section "", the JS keys). setTimeout -> timers ticked by update().
# Not ported (SPEC §0.2): renderer.compileAsync / game.warmSteps shader warm-up of the sets.
#
# MP (online co-op, MP_SPEC §0 §3.4 §3.5; the screens live in menu_front.gd and menu_lobby.gd, helpers of this object):
#   MAIN MENU (mode 'main', menu_front.gd): the title's any key now opens it (camera pose 'main': the TV on the left,
#     still showing the logo; the pause card's walnut pills on the right): SINGLE PLAYER (-> showSelect(), the dial
#     exactly as before) / MULTIPLAYER (TV GUIDE cards: host, join with the LAN listings and an address keypad, the
#     player name) / OPTIONS / CONTROLS (the pause menu's own cards) / QUIT (asks once, powers the set off, quits).
#     Esc on the dial now returns to the main menu (it returned to the title).
#   LOBBY (menu_lobby.gd): the same dial while _lobby != null (null in solo: every solo path is unchanged). Each player
#     tunes locally; a channel whose hero another player claimed shows ON AIR: <NAME> on the chyron and denies the
#     tune-in; tuning in = net.setHero + net.setReady(true); Esc un-readies, Esc again leaves (net.leave) to the
#     MULTIPLAYER card. A TV GUIDE roster card lists the players (channel, name, hero, ON AIR = ready, ping) and, for
#     the host, the addresses to share (LAN + UPnP). Host START (Enter / Start / click) -> net.startGame(); the lobby
#     phase 'starting' shows a 3-2-1 film leader on every TV, then every peer does the dive and the game starts.
#   PAUSE in an MP game (net.inGame; game.mpPaused, the world keeps running): the same card with RESUME / OPTIONS /
#     CONTROLS / LEAVE GAME (armed twice like QUIT, then net.leave() -> the main menu).
#   SIGNAL LOST (mode 'lost'): the session ended under us (host left, connection lost): static, CRT collapse, then the
#     stand-by card family with snow + SIGNAL LOST; any key -> the main menu (or the MULTIPLAYER card from a lobby).
#   MP GAME OVER / RESULTS: the same cards; the right panel lists each player (name, kills, points) under the team
#     round; any key -> back to the lobby (same session). Solo keeps today's flow.
#   API added: showMain(screen = 'main' | 'mp'), showLobby(), showSignalLost(reason), mpStart(heroId) -> bool (mp-core
#   hook: the lobby plays the dive, then starts the game), mode values 'main' | 'lost'.
extends RefCounted

const HudScript = preload("res://scripts/ui/hud.gd")
const FontsScript = preload("res://scripts/ui/fonts.gd")
const Menu_ = preload("res://scripts/ui/menu.gd")   # self: inner classes reach the static helpers through it
const FrontScript = preload("res://scripts/ui/menu_front.gd")   # MP: main menu + MULTIPLAYER cards
const LobbyScript = preload("res://scripts/ui/menu_lobby.gd")   # MP: lobby on the dial, SIGNAL LOST / results glue

# ------------------------------------------------------------------------------------------------ constants
const REF_W := 1920.0
const REF_H := 1080.0
const CHANNELS := [
	{"ch": 2, "hero": "skip", "show": "BEHIND THE SCENES", "role": "FLOOR RUNNER · WZTV 13 CREW", "glow": "#FFB870", "rim": "#FFC98A", "bg": "#3A2A20"},
	{"ch": 4, "hero": "roxy", "show": "BOOGIE DOWN SATURDAY", "role": "HOST OF BOOGIE DOWN SATURDAY", "glow": "#FF6FB0", "rim": "#FF4FA0", "bg": "#3A1030"},
	{"ch": 5, "hero": "penny", "show": "ENGINEERING REPORT", "role": "NIGHT-SHIFT BROADCAST ENGINEER", "glow": "#7FD8FF", "rim": "#5FE3FF", "bg": "#10284A"},
	{"ch": 7, "hero": "duke", "show": "PRECINCT 13", "role": "STAR OF PRECINCT 13", "glow": "#8A9CFF", "rim": "#9FB6FF", "bg": "#161A40"},
]
const GAMEOVER := {"drain": 1.2, "collapse": 1.15, "card": 2.9, "lock": 2.0}
const OPT_KEY := "deadair.options"
const SIGNOFF_KEY := "deadair.signoff"
const CFG := "user://deadair.cfg"
const CFG_SECTION := ""
const QUALITY := {"low": 0.75, "medium": 1.0, "high": 1.5}
const VOL_ROWS := [["master", "MASTER VOLUME"], ["music", "MUSIC"], ["sfx", "SOUND EFFECTS"], ["ambience", "AMBIENCE"], ["tv", "TV SPEAKERS"], ["ui", "INTERFACE"]]
# [action, keyboard/mouse keys, note, Xbox glyphs, pad note]
const CONTROLS := [
	["MOVE", ["W", "A", "S", "D"], null, ["LS"]], ["LOOK", ["MOUSE"], null, ["RS"]], ["SPRINT", ["SHIFT"], null, ["L3"]],
	["JUMP", ["SPACE"], null, ["A"]],
	["AIM", ["RIGHT MOUSE"], null, ["LT"]], ["FIRE", ["LEFT MOUSE"], null, ["RT"]], ["RELOAD", ["R"], null, ["X"], "NO PROMPT"],
	["INTERACT · BUY", ["E"], null, ["X"]],
	["REPAIR · CRANK", ["HOLD E"], null, ["X"], "HOLD"], ["MELEE", ["V"], null, ["B"]],
	["TUBE GRENADE", ["G"], "HOLD TO COOK", ["RB"]], ["TINY TELE", ["Q"], null, ["LB"]],
	["SWAP WEAPON", ["1", "2", "WHEEL"], null, ["Y", "DL", "DR"]], ["SWAP SHOULDER", ["C"], null, ["DD"]], ["PAUSE", ["ESC"], null, ["MENU", "VIEW"]],
]
# Xbox glyphs for the Controls card: face buttons (coloured letters), bumpers, triggers, sticks, D-pad arms, Menu / View.
const DPAD_ARM := {"DL": "M4 14.5h11v11H4z", "DR": "M25 14.5h11v11H25z", "DD": "M14.5 25h11v11h-11z", "DU": "M14.5 4h11v11h-11z"}
const PAD_MENU := {"a": "Enter", "b": "Escape", "up": "ArrowUp", "down": "ArrowDown", "left": "ArrowLeft", "right": "ArrowRight"}
const XB_COL := {"a": "#7EDB5A", "b": "#FF6A5C", "x": "#6FA8FF", "y": "#FFD24A"}
const CREAM := "#F6E7C8"

static func clamp_(x: float, a: float, b: float) -> float:
	return a if x < a else (b if x > b else x)

static func lerp_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func easeOut(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

static func easeIn(x: float) -> float:
	return x * x

static func easeInCubic(x: float) -> float:
	return x * x * x

static func easeInOut(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

static func easeOutBack(x: float, k: float = 1.70158) -> float:
	return 1.0 + (k + 1.0) * pow(x - 1.0, 3.0) + k * pow(x - 1.0, 2.0)

static func storeGet(key: String):
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return null
	if not cf.has_section_key(CFG_SECTION, key):
		return null   # get_value with a null default logs an error for a missing key
	var v = cf.get_value(CFG_SECTION, key)
	return str(v) if v != null else null

static func storeSet(key: String, v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value(CFG_SECTION, key, v)
	cf.save(CFG)

# Xbox glyph of the Controls card -> a paint descriptor (padGlyph of the JS returned HTML).
static func padGlyph(g: String) -> Dictionary:
	if g.length() == 1:
		return {"kind": "face", "text": g, "w": 40.0}
	if g == "LB" or g == "RB":
		return {"kind": "bump", "text": g, "w": 50.0}
	if g == "LT" or g == "RT":
		return {"kind": "trig", "text": g, "w": 44.0}
	if g == "LS" or g == "RS" or g == "L3":
		return {"kind": "stick", "text": g, "w": 40.0}
	if DPAD_ARM.has(g):
		return {"kind": "dpad", "arm": g, "w": 40.0}
	if g == "MENU" or g == "VIEW":
		return {"kind": "sys", "text": g, "w": 40.0}
	return {"kind": "kc", "text": g}

# ------------------------------------------------------------------------------------------------ TV compositor
# COMP_FRAG of the JS (three's vUv: y up). Pictures: tPicL = linear HDR (the sets' render target), tPicS = sRGB
# canvases (logo card, sunrise, ending pictures): uPicLin picks. tUI = the overlay canvas (sRGB).
const COMP_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D tPicL : filter_linear, repeat_enable;
uniform sampler2D tPicS : source_color, filter_linear, repeat_enable;
uniform float uPicLin = 0.0;
uniform sampler2D tUI : source_color, filter_linear, repeat_enable;
uniform float uTime;
uniform float uSnow;
uniform float uRoll;
uniform float uJitter;
uniform float uPic;
uniform float uUI;
uniform float uBright;
uniform float uSeam;
float h12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// Compatibility (web): a 3D view arrives sRGB-encoded (the scene shader's linear_to_srgb approximation): decode it.
vec3 daDec(vec3 c) { return mix(vec3(0.0), pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), vec3(greaterThan(c, vec3(0.0)))); }
#else
vec3 daDec(vec3 c) { return c; }
#endif
vec4 tex(sampler2D s, vec2 uv) { return texture(s, vec2(uv.x, 1.0 - uv.y)); }
void fragment() {
	vec2 vUv = vec2(UV.x, 1.0 - UV.y);
	vec2 uv = vUv;
	float ry = uv.y + uRoll;
	float seam = 1.0 - smoothstep(0.0, 0.045, min(fract(ry), 1.0 - fract(ry)));
	uv.y = fract(ry);
	float line = floor(uv.y * 240.0);
	float tj = floor(uTime * 30.0);
	uv.x += (h12(vec2(line, tj)) - 0.5) * uJitter * 0.05 + sin(uv.y * 26.0 + uTime * 19.0) * uJitter * 0.012;
	vec3 pic = (uPicLin > 0.5 ? daDec(tex(tPicL, uv).rgb) : tex(tPicS, uv).rgb) * uPic;
	vec4 ui = tex(tUI, uv);
	pic = mix(pic, ui.rgb, ui.a * uUI);
	float n = h12(floor(vUv * vec2(220.0, 165.0)) + tj * vec2(17.3, 91.7));
	float by = fract(vUv.y * 0.7 - uTime * 0.41);
	float band = smoothstep(0.0, 0.3, by) * smoothstep(0.62, 0.3, by);
	vec3 snow = vec3(n * n) * (0.75 + 0.45 * band) * vec3(0.95, 1.0, 1.08) + vec3(0.015, 0.018, 0.03);
	vec3 col = mix(pic, snow, uSnow);
	col *= 1.0 - seam * uSeam;
	COLOR = vec4(col * uBright, 1.0);
}
"""

# Floating dust in the TV light: points drifting on slow sine paths (uTime), additive (DUST_VERT / DUST_FRAG).
const DUST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
global uniform float uTime;
uniform float uSize = 11.0;
uniform vec3 uColor : source_color = vec3(1.0, 0.886, 0.722);
uniform float uAlpha = 0.22;
varying float vA;
void vertex() {
	vec4 seed = CUSTOM0;
	vec3 p = VERTEX;
	float t = uTime * (0.05 + seed.w * 0.07);
	p.x += sin(t * 2.1 + seed.x * 6.3) * 0.22;
	p.y += fract(t * 0.35 + seed.y) * 0.9 - 0.45;
	p.z += cos(t * 1.7 + seed.z * 6.3) * 0.18;
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	POSITION = PROJECTION_MATRIX * mv;
	POINT_SIZE = uSize * (0.6 + seed.w) / -mv.z;
	vA = 0.5 + 0.5 * sin(uTime * (0.7 + seed.x) + seed.z * 9.0);
}
void fragment() {
	vec2 c = POINT_COORD - 0.5;
	float a = smoothstep(0.5, 0.0, length(c));
	ALBEDO = uColor * a * vA * uAlpha;
	ALPHA = 1.0;
}
"""

# .mn-bg: radial-gradient(ellipse at 50% 42%, #2A2150, #140E26 60%, #07050C) + ::after scanlines (rgba(0,0,0,.18) 0 2px /
# 4px); black: the game over's black phase. .mn-dim: radial-gradient(ellipse at 50% 50%, rgba(34,20,52,.55),
# rgba(10,6,18,.86) 80%) + scanlines rgba(0,0,0,.16).
const BG_SHADER := """
shader_type canvas_item;
uniform vec2 size_px = vec2(1920.0, 1080.0);
uniform float black = 0.0;
uniform float dim = 0.0;
uniform float alpha = 1.0;
vec3 lin(vec3 c) { return c; }
void fragment() {
	vec2 p = UV * size_px;
	// ellipse farthest-corner: radii proportional to the closest-side ellipse through the farthest corner
	vec2 c = dim > 0.5 ? vec2(0.5, 0.5) * size_px : vec2(0.5, 0.42) * size_px;
	vec2 cs = vec2(min(c.x, size_px.x - c.x), min(c.y, size_px.y - c.y));
	vec2 far = max(c, size_px - c);
	float k = length(far / cs);
	vec2 R = cs * k;
	float d = length((p - c) / R);
	vec4 col;
	if (dim > 0.5) {
		vec4 a0 = vec4(34.0, 20.0, 52.0, 0.55 * 255.0) / 255.0;
		vec4 a1 = vec4(10.0, 6.0, 18.0, 0.86 * 255.0) / 255.0;
		float t = clamp(d / 0.8, 0.0, 1.0);
		vec4 pa = mix(vec4(a0.rgb * a0.a, a0.a), vec4(a1.rgb * a1.a, a1.a), t);
		col = vec4(pa.rgb / max(pa.a, 1e-4), pa.a);
	} else {
		vec3 c0 = vec3(42.0, 33.0, 80.0) / 255.0;
		vec3 c1 = vec3(20.0, 14.0, 38.0) / 255.0;
		vec3 c2 = vec3(7.0, 5.0, 12.0) / 255.0;
		vec3 g = d < 0.6 ? mix(c0, c1, d / 0.6) : mix(c1, c2, clamp((d - 0.6) / 0.4, 0.0, 1.0));
		col = vec4(g, 1.0);
	}
	if (black > 0.5) col = vec4(0.0, 0.0, 0.0, 1.0);
	// ::after scanlines: repeating-linear-gradient(0deg, rgba(0,0,0,a) 0 2px, transparent 2px 4px) from the bottom
	float sl = mod(floor(size_px.y - p.y), 4.0) < 2.0 ? (dim > 0.5 ? 0.16 : 0.18) : 0.0;
	col.rgb = mix(col.rgb, vec3(0.0), sl / max(col.a + sl * (1.0 - col.a), 1e-4));
	col.a = col.a + sl * (1.0 - col.a);
	COLOR = vec4(col.rgb, col.a * alpha);
}
"""

# ================================================================================================ transitions
# A CSS transition on one number: set_(target) restarts from the current value toward target over dur (after
# delay) with a cubic-bezier timing function.
class Tr extends RefCounted:
	var v := 0.0
	var from := 0.0
	var to := 0.0
	var t := -1.0
	var dur := 0.2
	var delay := 0.0
	var ease: Array = [0.25, 0.1, 0.25, 1.0]
	func _init(v0: float, d: float, e: Array = [0.25, 0.1, 0.25, 1.0], dl: float = 0.0) -> void:
		v = v0
		from = v0
		to = v0
		dur = d
		ease = e
		delay = dl
	func set_(target: float, instant: bool = false) -> void:
		if instant:
			v = target
			to = target
			t = -1.0
			return
		if target == to and (t >= 0.0 or v == target):
			return
		from = v
		to = target
		t = 0.0
	func tick(dt: float) -> void:
		if t < 0.0:
			return
		t += dt
		var p := clampf((t - delay) / maxf(1e-4, dur), 0.0, 1.0)
		v = lerpf(from, to, HudScript.cubicBezier(ease[0], ease[1], ease[2], ease[3], p))
		if p >= 1.0:
			v = to
			t = -1.0

# Receives the engine's input events for the menu (the JS window listeners, capture phase for keydown / mousedown).
class MenuHook extends Node:
	var sys
	func _init(s) -> void:
		sys = s
		name = "MenuHook"
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _input(event: InputEvent) -> void:
		if sys._onEvent(event):
			get_viewport().set_input_as_handled()

# ================================================================================================ Menu
var game
var mode = null
var _t := 0.0
var selected := "duke"
var _chIdx := 0
var options = null
var _room = null
var _sets = null
var _pause := {"sub": "main", "sel": 0, "osel": 0, "quitArm": -1.0}
var _over = null
var _unlocked := false
var _loadT := 0.0
var _ldP := -1.0
var _camFrom := "title"
var _camTo := "title"
var _camBlend := 1.0
var _ch := {"t": 0.0, "osd": 0.0, "chy": -1.0, "drawn": "", "pose": 0.0, "dir": 1}
var _tvState := ""
var _hover = null
var _dialPunch := 0.0
var _wheelAt := 0.0
var _drag = null
var _cardT := 0.0
var _titlePing := false
var _flipAt := 0.0
var _sldSnd := 0.0
var _cursor := ""
var _unPre = null
var _musicT = null
var _timers: Array = []
var _board
var _hits: Array = []           # clickable regions of the stage (DOM elements with listeners)
var _mouse := Vector2(-1, -1)
var _press = null               # region pressed (JS click = press + release on the same element)

# DOM (CanvasLayer + Controls) and the CSS state of each element
var layer: CanvasLayer
var root: Control
var stage: Control
var scale := 1.0
var stageOff := Vector2.ZERO
var pn := {}                    # panel name -> Control (.mn-pn)
var dom := {}
var _hook: MenuHook
var _fonts := {}
var _tex := {}                  # SVG textures cached per key (cleared when the rasterizing density changes)
var _css := {
	"press": {"text": "PRESS ANY KEY", "on": false, "t": 0.0},
	"ldbar": {"on": Tr.new(0.0, 0.5), "scale": Tr.new(0.0, 0.8, [0.0, 0.0, 1.0, 1.0])},
	"selttl": {"on": Tr.new(0.0, 0.4)},
	"selbar": {"on": Tr.new(0.0, 0.4)},
	"dim": Tr.new(0.0, 0.22),
	"bg": {"on": false, "black": false},
	"flash": Tr.new(0.0, 0.6, [0.2, 0.7, 0.3, 1.0], 0.12),
	"anykey": {"text": "PRESS ANY KEY", "on": false, "t": 0.0},
	"arrowL": {"s": Tr.new(1.0, 0.12, [0.3, 1.8, 0.5, 1.0]), "hit": 0.0},
	"arrowR": {"s": Tr.new(1.0, 0.12, [0.3, 1.8, 0.5, 1.0]), "hit": 0.0},
	"dymo": {"go": -1.0, "pad": false},
	"ovHdr": "", "sk": "0", "sp": "0",
}
var _pauseCanvas = null
var _overCanvas = null
# MP
var _front = null               # menu_front.gd: MAIN menu + MULTIPLAYER cards (mode 'main')
var _lobbyMod = null            # menu_lobby.gd
var _lobby = null               # == _lobbyMod while the dial is the MP lobby; null in solo
var _camDur := 1.25             # camera blend duration of _camGo()

func _init(g) -> void:
	game = g
	mode = null
	_t = 0.0
	var H = _heroesLib()
	var want = game.params.get("char")
	var ids: Array = []
	var def_hero := "duke"
	if H != null:
		for h in H.HEROES:
			ids.append(h.id)
		def_hero = H.DEFAULT_HERO
	else:
		ids = ["skip", "roxy", "penny", "duke"]
	selected = want if ids.has(want) else def_hero
	_chIdx = maxi(0, _chanIndex(selected))
	options = null
	_room = null
	_sets = null
	_over = null
	_unlocked = storeGet(SIGNOFF_KEY) == "1"
	FontsScript.loadFonts()
	_fonts = {"hud": FontsScript.family(FontsScript.FONTS.hud), "tape": FontsScript.family(FontsScript.FONTS.tape),
		"logo": FontsScript.family(FontsScript.FONTS.logo), "sign": FontsScript.family(FontsScript.FONTS.sign)}
	_front = FrontScript.new(self)
	_lobbyMod = LobbyScript.new(self)
	_buildDom()
	_resize()

static func _chanIndex(hero) -> int:
	for i in CHANNELS.size():
		if CHANNELS[i].hero == hero:
			return i
	return -1

func _heroesLib():
	if ResourceLoader.exists("res://scripts/actors/heroes.gd"):
		return load("res://scripts/actors/heroes.gd")
	return null

# -------------------------------------------------------------------------------------------- lifecycle
func init() -> void:
	_loadOptions()
	_applyOptions()
	_hook = MenuHook.new(self)
	game.add_child(_hook)
	game.events.on("state", func(p): _onState(p if p else {}))
	game.events.on("input:device", func(_p): _refreshGlyphs())
	# MP: the session's events (scripts/net, mp-core) drive the front cards, the lobby and SIGNAL LOST
	for ev in ["net:lobby", "net:peer", "net:status", "net:lan", "net:upnp", "net:hero"]:
		var evn: String = ev
		game.events.on(evn, func(p): _onNet(evn, p))

# ------------------------------------------------------------------------------------------- gamepad
# input.gd calls this for every pad press while a menu shows (see the header). Returns true when it was used.
func padButton(btn: String) -> bool:
	var m = mode
	if not m or m == "tunein":
		return false
	var key := func(code: String) -> void: _onKey({"code": code, "repeat": false, "shiftKey": false, "stop": false, "char": ""})
	if m == "title" or m == "over" or m == "results" or m == "lost":
		key.call("Enter")   # any button
		return true
	if m == "main":
		return _front.pad(btn)
	if m == "select" and _lobby != null and _lobby.pad(btn):
		return true
	if m == "select":
		var code = "ArrowLeft" if btn == "lb" else ("ArrowRight" if btn == "rb" else ("Enter" if btn == "start" else PAD_MENU.get(btn)))
		if code and code != "ArrowUp" and code != "ArrowDown":
			key.call(code)
		return true
	if m == "pause":
		if btn == "start" or btn == "back":
			_play("ui_menu_clack", {"vol": 0.7})
			game.resume()
			return true
		if PAD_MENU.has(btn):
			key.call(PAD_MENU[btn])
		return true
	return true

func _padMode() -> bool:
	return game.input != null and game.input.get("device") == "pad"

func _anyText() -> String:
	return "PRESS ANY BUTTON" if _padMode() else "PRESS ANY KEY"

# Keyboard or Xbox glyphs on the menu surfaces (input:device).
func _refreshGlyphs() -> void:
	var pad := _padMode()
	_css.dymo.pad = pad
	_css.anykey.text = _anyText()
	if mode == "select":
		_hits = _hits.filter(func(h): return not ["arrowL", "arrowR", "dymo"].has(h.id))
		_selectHits()
	if (mode == "pause" and _pause.sub == "controls") or (mode == "main" and _front.screen == "controls"):
		_renderPause()
	elif mode == "main":
		_front._hitsFor()
	_redraw()

func reset() -> void:
	# newGame: the run starts; every menu surface goes away (the tune-in flash keeps fading on its own).
	hideAll()

func hideAll() -> void:
	if mode == "main":
		_front.leaveScreen()
	mode = null
	_use3D(false)
	for k in pn:
		pn[k].visible = false
	_css.dim.set_(0.0)
	_css.bg.on = false
	_css.press.on = false
	_css.selttl.on.set_(0.0)
	_css.selbar.on.set_(0.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setCursor("")
	_hits.clear()
	_redraw()

# -------------------------------------------------------------------------------------------- public screens
# Real boot, before the living room exists (Game.boot, right after the fonts): the title's prompt slot reads
# PLEASE STAND BY over the dark page.
func showLoading() -> void:
	pn.title.visible = true
	_css.press.text = "PLEASE STAND BY"
	_setPressOn(true)
	_css.ldbar.on.set_(1.0)
	_loadT = 1.0
	_redraw()

func showTitle() -> void:
	var g = game
	hideAll()
	if g.loaded == false and _loadT > 0.6:
		_css.press.text = "PLEASE STAND BY"
		_setPressOn(true)
	mode = "title"
	_t = 0.0
	_ensureRoom()
	_use3D(true)
	_resetPost()
	_camFrom = "title"
	_camTo = "title"
	_camBlend = 1.0
	_tvMode("title")
	pn.title.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if g.audio and g.audio.has_method("music"):
		g.audio.music("title")
	_redraw()

func showSelect() -> void:
	_lobby = null
	_showDial()

# MP: the dial as the lobby of the current session (menu_lobby.gd; HOST GAME / a successful join / back from results).
func showLobby() -> void:
	_lobby = _lobbyMod
	_showDial()
	pn.lobby.visible = true
	_lobby.enter()

# MAIN menu (menu_front.gd); screen 'mp' opens straight on the MULTIPLAYER card (leaving a lobby).
func showMain(screen: String = "main") -> void:
	var g = game
	var from = mode
	hideAll()
	_lobby = null
	_session = false
	if _mpSession():
		_net().leave()   # the main menu is outside any session
	if g.state != "menu":
		g.setState("menu")
	mode = "main"
	_t = 0.0
	_ensureRoom()
	_use3D(true)
	_resetPost()
	_css.bg.on = false
	_css.bg.black = false
	_tvMode("title")
	_camGo("main" if screen == "main" else "card", 1.25)
	pn.front.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if g.audio and g.audio.has_method("music"):
		g.audio.music("title")
	_front.enter(screen, from)
	_redraw()

# mp-core hook (net:start on every peer): true when the lobby takes over the start (the dive into the screen, then
# _startGame() starts the game itself); false when no lobby shows (test boots auto-start), the caller starts it.
func mpStart(heroId) -> bool:
	if _lobby == null or (mode != "select" and mode != "tunein"):
		return false
	return _lobby.goLive(heroId)

# Camera: blend from wherever it is now (the room's last pose) to a named pose over dur seconds.
func _camGo(to: String, dur: float = 1.25) -> void:
	var R = _room
	if R == null:
		return
	if R.get("cur") is Dictionary:
		R.poses["cur"] = (R.cur as Dictionary).duplicate()
		_camFrom = "cur"
	else:
		_camFrom = _camTo
	_camTo = to
	_camBlend = 0.0
	_camDur = dur

func _showDial() -> void:
	var g = game
	var from = mode
	var fromTitle: bool = from == "title" or from == "main"
	hideAll()
	if g.state != "menu":
		g.setState("menu")
	mode = "select"
	_t = 0.0
	_ensureRoom()
	_use3D(true)
	_resetPost()
	if from == "main" or (_lobby != null and from != "select"):
		_camGo("select", 1.25)   # from the main menu's pose (or back from a game: out of the screen)
		fromTitle = true
	else:
		_camFrom = "title" if fromTitle else "select"
		_camTo = "select"
		_camBlend = 0.0 if fromTitle else 1.0
	pn.select.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_later(0.7 if fromTitle else 0.15, func():
		if mode == "select":
			_css.selttl.on.set_(1.0)
			_css.selbar.on.set_(1.0))
	_chIdx = maxi(0, _chanIndex(selected))
	_tvMode("channel")
	_tuneTo(_chIdx, true)
	_refreshGlyphs()

func tune(dir: int) -> void:
	if mode != "select" or _camBlend < 0.35:
		return
	if _lobby != null and not _lobby.canTune():
		return
	_tuneTo((_chIdx + (-1 if dir < 0 else 1) + CHANNELS.size()) % CHANNELS.size(), false, dir)

func tuneIn() -> void:
	if mode != "select" or _camBlend < 0.6:
		return
	if _lobby != null:
		_lobby.tuneIn()   # MP: claim the hero + READY (the dive comes with the host's start)
		return
	_dive()

# The tune-in transition: the camera dives into the screen, white flash, then _startGame().
func _dive() -> void:
	mode = "tunein"
	_t = 0.0
	_css.selttl.on.set_(0.0)
	_css.selbar.on.set_(0.0)
	_css.dymo.go = 0.0
	_play("ui_tune_in")
	var h = _heroOnSet()
	if h:
		var an = h.get("animator")
		if an and an.has_method("kick"):
			an.kick(1.2)
		_faceExpr(h, "smile", 1.0)

func showPause() -> void:
	hideAll()
	mode = "pause"
	var P := _pause
	P.sub = "main"
	P.sel = 0
	P.osel = 0
	P.quitArm = -1.0
	_css.dim.set_(1.0)
	pn.pause.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_renderPause()
	_drawCard(_pauseCanvas, "stand_by", 0.0, true)
	_play("ui_menu_clack", {"vol": 0.8})

func hidePause() -> void:
	if mode != "pause":
		return
	hideAll()

func showGameOver(summary = {}) -> void:
	var g = game
	if not (summary is Dictionary):
		summary = {}
	hideAll()
	if g.hud and g.hud.has_method("hide"):
		g.hud.hide()
	mode = "over"
	_t = 0.0
	_over = {"summary": {"round": int(summary.get("round", 0)), "kills": int(summary.get("kills", 0)), "points": int(summary.get("points", 0))},
		"phase": "drain", "title": null, "onDone": null, "results": false}
	_mpOver(summary)
	_play("sting_gameover")

func showVictory(summary = {}) -> void:
	var g = game
	if not (summary is Dictionary):
		summary = {}
	if g.hud and g.hud.has_method("hide"):
		g.hud.hide()
	var end = g.ending
	if end and (end.get("active") or end.get("playing") or end.get("running")):
		return # the ending sequence owns the screen
	var rnd = summary.get("round")
	if rnd == null:
		rnd = g.rounds.get("round") if g.rounds else 0
	var kills = summary.get("kills")
	if kills == null:
		kills = g.rounds.get("totalKills") if g.rounds else 0
	var pts = summary.get("points")
	if pts == null:
		pts = g.economy.get("points") if g.economy else 0
	showResults({"round": rnd if rnd != null else 0, "kills": kills if kills != null else 0, "points": pts if pts != null else 0}, {"title": "SIGN-OFF"})

func showResults(summary = {}, opts = {}) -> void:
	if not (summary is Dictionary):
		summary = {}
	if not (opts is Dictionary):
		opts = {}
	var title = opts.get("title", "GOOD NIGHT")
	var onDone = opts.get("onDone", null)
	hideAll()
	if game.hud and game.hud.has_method("hide"):
		game.hud.hide()
	mode = "results"
	_t = 0.0
	_over = {"summary": {"round": int(summary.get("round", 0)), "kills": int(summary.get("kills", 0)), "points": int(summary.get("points", 0))},
		"phase": "card", "title": title, "onDone": onDone, "results": true}
	_mpOver(summary)
	_showOverCard()

# -------------------------------------------------------------------------------------------- MP (sessions)
# net:status values that end a session under us (net.leave() reports 'left': our own choice, never SIGNAL LOST)
const LOST_STATUS := ["lost", "rejected", "failed"]
const LOST_TEXT := {"host_left": "THE HOST ENDED THE BROADCAST", "lost": "THE CONNECTION WAS LOST", "disconnected": "THE CONNECTION WAS LOST",
	"timeout": "THE SIGNAL TIMED OUT", "kicked": "THE HOST TOOK YOU OFF THE AIR"}
var _session := false           # we were in an MP lobby / game (a disconnect status then means SIGNAL LOST)

func _net():
	return game.get("net")

# An MP session exists (lobby or game).
func _mpSession() -> bool:
	var n = _net()
	return n != null and n.get("active") == true

# An MP game runs (pause card items, game over flow).
func _mpGame() -> bool:
	var n = _net()
	return n != null and n.get("active") == true and n.get("inGame") == true

# game.events net:* (mp-core) -> the front cards, the lobby, SIGNAL LOST.
func _onNet(ev: String, p) -> void:
	var d: Dictionary = p if p is Dictionary else {}
	if mode == "main":
		_front.onNet(ev, p)   # connecting / LAN listings / a join attempt that failed
		return
	if ev == "net:status":
		var st := str(d.get("status", ""))
		if LOST_STATUS.has(st) and _session and mode != "lost":
			var why := str(d.get("reason", ""))
			showSignalLost(why if LOST_TEXT.has(why) else st)
		return
	if _lobby != null:
		_lobby.onNet(ev, p)

# LEAVE GAME (MP pause) / leaving a lobby: our own disconnect, never a SIGNAL LOST.
func _leaveSession(screen: String = "main") -> void:
	var n = _net()
	_session = false
	if game.get("mpPaused") == true:
		game.set("mpPaused", false)
	if n != null and n.has_method("leave"):
		n.leave()
	hideAll()
	game.setState("menu")
	showMain(screen)

# SIGNAL LOST (mode 'lost'): the session ended under us. In a game: the picture tears into static and collapses, then
# the stand-by card family with snow + SIGNAL LOST; from a lobby the card comes at once. Any key -> the main menu
# (the MULTIPLAYER card when it cut a lobby).
func showSignalLost(reason: String = "") -> void:
	var g = game
	var fromLobby := _lobby != null
	var inGame: bool = mode == null or mode == "pause" or g.state == "playing" or g.state == "down" or g.state == "paused"
	_session = false
	if g.get("mpPaused") == true:
		g.set("mpPaused", false)
	hideAll()
	_lobby = null
	if g.hud and g.hud.has_method("hide"):
		g.hud.hide()
	var inp = g.input
	if inp and inp.has_method("exitLock"):
		inp.exitLock()
	if g.state != "menu":
		g.setState("menu")   # the world stops behind the static
	mode = "lost"
	_t = 0.0
	var txt: String = LOST_TEXT.get(reason, reason.to_upper().replace("_", " ") if reason != "" else "THE CONNECTION WAS LOST")
	_over = {"summary": {"round": 0, "kills": 0, "points": 0}, "phase": "static" if inGame and not fromLobby else "black", "title": "Signal Lost",
		"onDone": null, "results": false, "lost": true, "why": txt, "fromLobby": fromLobby, "mp": false}
	_play("uplink_lost")
	if not inGame or fromLobby:
		_t = GAMEOVER.card - 0.35   # straight to the card after a beat of black

# MP game over / results: the card lists every player and any key returns to the lobby (_overGo).
func _mpOver(summary: Dictionary) -> void:
	if not _mpSession():
		return
	_over.mp = true
	_over.players = _mpPlayers(summary)
	if game.get("mpPaused") == true:
		game.set("mpPaused", false)   # the pause card (if it was up) is gone

# Host: the MP game is over (the game-over card is up / a results card was dismissed): net.endGame() -> every peer back
# to the lobby phase (inGame false, ready flags cleared, state 'menu'). Clients wait for it in their lobby.
func _mpEndGame(reason: String) -> void:
	var n = _net()
	if n != null and n.get("isHost") == true and n.get("inGame") == true and n.has_method("endGame"):
		n.endGame(reason)

# Rows of the MP results card: [{id, name, hero, kills, points, me}], best score first. From the host's summary
# (net.teamSummary(): players = [{id, name, hero, color, kills, points, downs, revives}], or {id: row}) or else
# net.peers + economy.statsOf(id).
func _mpPlayers(summary: Dictionary) -> Array:
	var n = _net()
	var peers = n.get("peers") if n != null else null
	var me = n.get("localId") if n != null else 1
	var rows: Array = []
	var src = summary.get("players", summary.get("team"))
	if src is Dictionary:
		for id in src:
			var r: Dictionary = (src[id] as Dictionary).duplicate() if src[id] is Dictionary else {}
			r.id = int(id)
			rows.append(r)
	elif src is Array:
		for r in src:
			if r is Dictionary:
				rows.append((r as Dictionary).duplicate())
	elif peers is Dictionary:
		var eco = game.economy
		for id in peers:
			var pi = peers[id]
			var st = eco.statsOf(int(id)) if eco != null and eco.has_method("statsOf") else null
			if not (st is Dictionary):
				st = pi if pi is Dictionary else {}
			rows.append({"id": int(id), "name": pi.get("name") if pi is Dictionary else null, "hero": pi.get("hero") if pi is Dictionary else null,
				"kills": st.get("kills", 0), "points": st.get("points", 0)})
	for r in rows:
		var id := int(r.get("id", 0))
		var pi = peers.get(id) if peers is Dictionary else null
		if r.get("name") == null:
			r.name = pi.get("name", "PLAYER %d" % id) if pi is Dictionary else ("PLAYER %d" % id)
		if r.get("hero") == null and pi is Dictionary:
			r.hero = pi.get("hero")
		r.me = id == int(me) if me != null else false
		if r.me and r.get("kills") == null:
			r.kills = summary.get("kills", 0)
		if r.me and r.get("points") == null:
			r.points = summary.get("points", 0)
		r.kills = int(r.get("kills", 0) if r.get("kills") != null else 0)
		r.points = int(r.get("points", 0) if r.get("points") != null else 0)
	rows.sort_custom(func(a, b): return a.points > b.points)
	return rows.slice(0, 4)

# Ending hook: the character-select room, drawn through the normal pipeline while activated.
func getLivingRoom():
	_ensureRoom()
	var R = _room
	if R == null:
		return null
	if R.get("api") == null:
		R.api = {
			"scene": R.scene, "camera": R.camera, "telly": R.telly, "parts": R.parts, "root": R.root,
			"setPicture": func(tex = null) -> void:
				R.external = tex
				if R.screenMat:
					R.screenMat.map = tex if tex != null else R.tv.tex,
			"activate": func(camera = null) -> void:
				R.externalCam = camera
				_use3D(true, camera),
			"deactivate": func() -> void:
				R.externalCam = null
				_use3D(false),
		}
	return R.api

func setOption(key: String, value) -> void:
	if options == null:
		_loadOptions()
	if key.begins_with("vol."):
		options.vol[key.substr(4)] = value
	else:
		options[key] = value
	_applyOptions()
	storeSet(OPT_KEY, JSON.stringify(options))

# -------------------------------------------------------------------------------------------- DOM
func _buildDom() -> void:
	layer = CanvasLayer.new()
	layer.name = "Menu"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "mn"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var bg := ColorRect.new()
	bg.name = "mn-bg"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bm := ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = BG_SHADER
	bm.shader = bs
	bg.material = bm
	bg.visible = false
	root.add_child(bg)
	var dim := ColorRect.new()
	dim.name = "mn-dim"
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dm := ShaderMaterial.new()
	dm.shader = bs
	dm.set_shader_parameter("dim", 1.0)
	dim.material = dm
	dim.visible = false
	root.add_child(dim)
	stage = Control.new()
	stage.name = "mn-st"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = Vector2(REF_W, REF_H)
	root.add_child(stage)
	var flash := ColorRect.new()
	flash.name = "mn-flash"
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color("#FFF8EC")
	flash.modulate.a = 0.0
	root.add_child(flash)
	# panels
	for n in ["title", "select", "pause", "over", "front", "lobby"]:
		var p := HudScript.DrawCtl.new(Callable(), "pn-" + n)
		p.size = Vector2(REF_W, REF_H)
		p.visible = false
		stage.add_child(p)
		pn[n] = p
	pn.title.draw_fn = _drawTitle
	pn.select.draw_fn = _drawSelect
	pn.pause.draw_fn = _drawPause
	pn.over.draw_fn = _drawOver
	pn.front.draw_fn = _drawFront   # MP: main menu + cards
	pn.lobby.draw_fn = _drawLobby   # MP: roster + countdown over the dial
	# the over card's split-flap board (a flex row inside .ovpan .board)
	var boardRow := HBoxContainer.new()
	boardRow.name = "board"
	boardRow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boardRow.add_theme_constant_override("separation", 12)
	pn.over.add_child(boardRow)
	dom = {"bg": bg, "dim": dim, "flash": flash, "board": boardRow}
	_board = HudScript.FlipBoard.new(boardRow, 2, {"cls": "board", "speed": 0.55, "onFlip": func(_i): _flipSound()})
	_board.set_("00", true)
	_pauseCanvas = _canvas(1024, 768)
	_overCanvas = _canvas(1024, 768)
	game.add_child(layer)
	var vp: Viewport = game.get_viewport()
	if vp:
		vp.size_changed.connect(_resize)

func _drawFront(ci: Control) -> void:
	_front.draw(ci)

func _drawLobby(ci: Control) -> void:
	if _lobby != null:
		_lobby.draw(ci)

func _resize() -> void:
	var vp: Viewport = game.get_viewport() if game and game.is_inside_tree() else null
	var vis := Vector2(REF_W, REF_H)
	if vp:
		vis = vp.get_visible_rect().size
	var s := minf(vis.x / REF_W, vis.y / REF_H)
	scale = s
	stageOff = Vector2((vis.x - REF_W * s) / 2.0, (vis.y - REF_H * s) / 2.0)
	stage.position = stageOff
	stage.scale = Vector2(s, s)
	for k in ["bg", "dim"]:
		(dom[k].material as ShaderMaterial).set_shader_parameter("size_px", vis)
	var dev := 1.0
	if vp:
		dev = vp.get_final_transform().get_scale().y * s
	if HudScript.setSvgScale(dev):
		_tex.clear()
	_tex.clear()
	_redraw()

func _redraw() -> void:
	for k in pn:
		pn[k].queue_redraw()

func _setCursor(c: String) -> void:
	if _cursor != c:
		_cursor = c
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if c == "pointer" else Input.CURSOR_ARROW)

func _setPressOn(on: bool) -> void:
	if on and not _css.press.on:
		_css.press.t = 0.0
	_css.press.on = on

func _later(sec: float, fn: Callable) -> Dictionary:
	var h := {"t": sec, "fn": fn, "dead": false}
	_timers.append(h)
	return h

func _play(id: String, opts: Dictionary = {}) -> void:
	var a = game.audio
	if a and a.has_method("play"):
		a.play(id, opts)

# -------------------------------------------------------------------------------------------- options
func _loadOptions() -> void:
	var g = game
	var vol := {}
	for r in VOL_ROWS:
		var v = g.audio.getBusVolume(r[0]) if g.audio and g.audio.has_method("getBusVolume") else null
		vol[r[0]] = float(v) if v != null else 1.0
	var def := {"sensitivity": 1.0, "padSens": 1.0, "invertY": false, "fov": 70.0, "aim": "hold", "sprint": "hold", "aimAssist": true, "rumble": true, "vol": vol, "quality": "high", "crt": false}
	var saved = null
	var raw = storeGet(OPT_KEY)
	if raw != null:
		saved = JSON.parse_string(str(raw))
	var o := def.duplicate(true)
	if saved is Dictionary:
		for k in saved:
			o[k] = saved[k]
	var v2 := vol.duplicate()
	if saved is Dictionary and saved.get("vol") is Dictionary:
		for k in saved.vol:
			v2[k] = saved.vol[k]
	o.vol = v2
	options = o

func _num(v, d: float) -> float:
	if v is int or v is float:
		return float(v) if float(v) != 0.0 else d
	if v is String and v.is_valid_float():
		return float(v) if float(v) != 0.0 else d
	return d

func _applyOptions() -> void:
	var g = game
	var o = options
	if o == null:
		return
	var inp = g.input
	if inp and inp.get("options") != null:
		var io = inp.options
		io.sensitivity = clamp_(_num(o.get("sensitivity"), 1.0), 0.1, 5.0)
		io.invertY = bool(o.get("invertY"))
		io.padSensitivity = clamp_(_num(o.get("padSens"), 1.0), 0.3, 2.5)
		io.aimAssist = o.get("aimAssist") != false
		io.rumble = o.get("rumble") != false
		if not io.rumble:
			var pad = inp.get("pad")
			if pad and pad.has_method("stopRumble"):
				pad.stopRumble()
		if io.get("holdToggle") is Dictionary:
			io.holdToggle.aim = "toggle" if o.get("aim") == "toggle" else "hold"
			io.holdToggle.sprint = "toggle" if o.get("sprint") == "toggle" else "hold"
	if g.cam:
		g.cam.fovBase = clamp_(_num(o.get("fov"), 70.0), 60.0, 90.0)
	for r in VOL_ROWS:
		var vv = o.vol.get(r[0]) if o.get("vol") is Dictionary else null
		if (vv is float or vv is int) and is_finite(float(vv)) and g.audio and g.audio.has_method("setBusVolume"):
			g.audio.setBusVolume(r[0], float(vv))
	var rr = g.render
	if rr:
		# JS devicePixelRatio caps CSS pixels; Godot's pixelRatio is relative to physical pixels (JS ratio / dpr)
		var dpr := DisplayServer.screen_get_scale()
		if dpr <= 0.0:
			dpr = 1.0
		var cap := minf(dpr, float(QUALITY.get(o.get("quality"), 1.5))) / dpr
		if rr.get("maxPixelRatio") != null and rr.maxPixelRatio != cap:
			rr.maxPixelRatio = cap
			if rr.has_method("setPixelRatio"):
				rr.setPixelRatio(cap if o.get("quality") == "high" else minf(float(rr.pixelRatio), cap))
	if g.hud and g.hud.has_method("setCrt"):
		g.hud.setCrt(bool(o.get("crt")))

# -------------------------------------------------------------------------------------------- input routing
func _onState(p: Dictionary) -> void:
	# A run started from anywhere (debug, test harness): no menu surface may stay up.
	if (p.get("to") == "playing" or p.get("to") == "down") and mode and mode != "tunein":
		if mode == "pause" and _mpGame():
			return   # MP pause is an overlay over a running world: the local player going down keeps it up
		hideAll()

# Engine events -> the JS listeners. Returns true when the event must stop here (stopImmediatePropagation).
func _onEvent(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed:
			return false
		var code := _domCode(k)
		if code == "":
			return false
		var e := {"code": code, "repeat": k.echo, "shiftKey": k.shift_pressed, "stop": false,
			"char": String.chr(k.unicode) if k.unicode >= 32 else ""}   # typed text (the MP name / address cards)
		_onKey(e)
		return e.stop
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_onWheel(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
			return false
		var btn := 0 if mb.button_index == MOUSE_BUTTON_LEFT else (1 if mb.button_index == MOUSE_BUTTON_MIDDLE else (2 if mb.button_index == MOUSE_BUTTON_RIGHT else 3))
		_mouse = mb.position
		if mb.pressed:
			var used := _onMouseDown(btn, mb.position)
			return used
		_drag = null
		_onMouseUp(btn, mb.position)
		return false
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		_onMouseMove(_mouse)
	return false

func _domCode(k: InputEventKey) -> String:
	var inp = game.input
	if inp and inp.has_method("domCode"):
		return inp.domCode(k)
	var s := "res://scripts/core/input.gd"
	if ResourceLoader.exists(s):
		var I = load(s)
		if I:
			return I.domCode(k)
	return OS.get_keycode_string(k.physical_keycode)

func _onKey(e: Dictionary) -> void:
	var m = mode
	if not m or e.repeat:
		return
	var c: String = e.code
	if m == "title":
		if c.begins_with("Shift") or c.begins_with("Control") or c.begins_with("Alt") or c.begins_with("Meta") or c.begins_with("Escape") or c.begins_with("Tab") or _t < 0.35 or game.loaded == false:
			return
		_titleGo()
	elif m == "main":
		_front.key(e)
	elif m == "select":
		if _lobby != null and _lobby.key(e):
			return   # MP lobby: Esc un-readies / leaves, Enter starts (host), the dial is locked while counting down
		if c == "KeyA" or c == "ArrowLeft":
			tune(-1)
			_arrowHit("l")
		elif c == "KeyD" or c == "ArrowRight":
			tune(1)
			_arrowHit("r")
		elif c == "KeyE" or c == "Enter" or c == "Space" or c == "NumpadEnter":
			tuneIn()
		elif c == "Escape":
			_play("ui_menu_clack", {"vol": 0.7})
			showMain()
	elif m == "pause":
		_pauseKey(e)
	elif m == "over" or m == "results" or m == "lost":
		if c.begins_with("Shift") or c.begins_with("Control") or c.begins_with("Alt") or c.begins_with("Meta") or c.begins_with("Tab"):
			return
		if c == "Escape":
			e.stop = true
		_overGo()

# Stage coordinates of a viewport (canvas) position.
func _toStage(p: Vector2) -> Vector2:
	return (p - stageOff) / scale

func _hitAt(p: Vector2):
	var sp := _toStage(p)
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if (h.rect as Rect2).has_point(sp):
			return h
	return null

func _onMouseDown(button: int, pos: Vector2) -> bool:
	var m = mode
	if not m:
		return false
	if m == "title":
		if _t >= 0.35 and game.loaded != false:
			_titleGo()
		return true
	if m == "over" or m == "results" or m == "lost":
		_overGo()
		return true
	var h = _hitAt(pos)
	_press = h
	if h and h.get("down") is Callable:
		h.down.call(pos)
	if m == "select" and button == 0 and h == null:
		var hit = _pick(pos)
		if hit == "dial":
			tune(1)
			_dialPunch = 1.0
		elif hit == "screen":
			tuneIn()
	return h != null or m == "select" or m == "pause" or m == "main"

func _onMouseUp(button: int, pos: Vector2) -> void:
	var h = _hitAt(pos)
	var p = _press
	_press = null
	if button != 0 or h == null or p == null or h.get("id") != p.get("id"):
		return
	if h.get("click") is Callable:
		h.click.call()

func _onMouseMove(pos: Vector2) -> void:
	if mode == "select":
		var hit = _pick(pos)
		_hover = hit
		var h = _hitAt(pos)
		_setCursor("pointer" if hit or h else "")
		var ov: String = h.get("id", "") if h else ""
		_css.arrowL.s.set_(0.88 if (_press and _press.get("id") == "arrowL" and ov == "arrowL") else (1.1 if ov == "arrowL" else 1.0))
		_css.arrowR.s.set_(0.88 if (_press and _press.get("id") == "arrowR" and ov == "arrowR") else (1.1 if ov == "arrowR" else 1.0))
	elif mode == "pause" or mode == "main":
		var h2 = _hitAt(pos)
		if h2 and h2.get("enter") is Callable:
			h2.enter.call()
		if mode == "main":
			_setCursor("pointer" if h2 else "")
	if _drag:
		_dragTo(pos)

func _onWheel(deltaY: float) -> void:
	if mode != "select" or deltaY == 0.0:
		return
	var now := DAU.nowMs()
	if now - _wheelAt < 130.0:
		return
	_wheelAt = now
	tune(1 if deltaY > 0.0 else -1)

func _arrowHit(side: String) -> void:
	var a: Dictionary = _css.arrowL if side == "l" else _css.arrowR
	a.hit = 0.11
	a.s.set_(0.88)

func _titleGo() -> void:
	if mode != "title":
		return
	_play("ui_menu_clack")
	showMain()

func _overGo() -> void:
	var O = _over
	if O == null or O.phase != "card" or _t < (1.0 if O.get("lost") else GAMEOVER.lock):
		return
	_play("ui_menu_clack")
	if O.get("lost"):
		# SIGNAL LOST -> the main menu (the MULTIPLAYER card when it cut a lobby)
		_over = null
		hideAll()
		_resetPost()
		showMain("mp" if O.get("fromLobby") else "main")
		return
	if O.get("mp") and _mpSession():
		# MP game over / results -> back to the lobby of the same session (the host sends everyone there)
		_mpEndGame("results")
		_over = null
		hideAll()
		_resetPost()
		game.setState("menu")
		showLobby()
		return
	if O.onDone is Callable and O.onDone.is_valid():
		var fn: Callable = O.onDone
		hideAll()
		_over = null
		_resetPost()
		fn.call()
		return
	_over = null
	if O.results:
		game.setState("menu")
		showTitle()
	else:
		showSelect()

# -------------------------------------------------------------------------------------------- per frame
func update(dt: float) -> void:
	_t += dt
	for i in range(_timers.size() - 1, -1, -1):
		var tm: Dictionary = _timers[i]
		if tm.dead:
			_timers.remove_at(i)
			continue
		tm.t -= dt
		if tm.t <= 0.0:
			_timers.remove_at(i)
			(tm.fn as Callable).call()
	_tickCss(dt)
	var m = mode
	if not m:
		return
	if (m == "title" or m == "select" or m == "tunein") and _room == null:
		if m == "tunein" and _t > 0.3:
			_startGame()
		return
	if m == "title" or m == "select" or m == "tunein" or m == "main":
		_updateRoom(dt)
	if m == "title":
		_updateTitle(dt)
	elif m == "main":
		_front.update(dt)
	elif m == "select":
		_updateSelect(dt)
		if _lobby != null and mode == "select":
			_lobby.update(dt)
	elif m == "tunein":
		_updateTuneIn(dt)
	elif m == "pause":
		_updatePause(dt)
	elif m == "over" or m == "results" or m == "lost":
		_updateOver(dt)

# CSS transitions / animations of the DOM surfaces.
func _tickCss(dt: float) -> void:
	var C := _css
	C.press.t += dt
	C.anykey.t += dt
	C.ldbar.on.tick(dt)
	C.ldbar.scale.tick(dt)
	C.selttl.on.tick(dt)
	C.selbar.on.tick(dt)
	C.dim.tick(dt)
	C.flash.tick(dt)
	for k in ["arrowL", "arrowR"]:
		var a: Dictionary = C[k]
		if a.hit > 0.0:
			a.hit -= dt
			if a.hit <= 0.0:
				a.s.set_(1.0)
		a.s.tick(dt)
	if C.dymo.go >= 0.0:
		C.dymo.go += dt
		if C.dymo.go > 0.28:
			C.dymo.go = -1.0
	var dim: ColorRect = dom.dim
	dim.visible = C.dim.v > 0.001
	dim.modulate.a = C.dim.v
	var bg: ColorRect = dom.bg
	bg.visible = C.bg.on
	(bg.material as ShaderMaterial).set_shader_parameter("black", 1.0 if C.bg.black else 0.0)
	(dom.flash as ColorRect).modulate.a = C.flash.v
	if mode or C.press.on or C.ldbar.on.v > 0.0 or pn.title.visible:
		_redraw()

func _resetPost() -> void:
	var p = game.render.get("post") if game.render else null
	if not (p is Dictionary):
		return
	var z := {"collapse": 0.0, "saturation": 1.0, "static": 0.0, "roll": 0.0, "damage": 0.0, "whiteout": 0.0, "crt": 0.0, "chroma": 0.0, "scanlines": 0.0, "vignette": 0.0}
	for k in z:
		p[k] = z[k]

# -------------------------------------------------------------------------------------------- title
func _updateTitle(dt: float = 0.0) -> void:
	# While the station still loads behind the title (game.loaded == false, real boot only) the TV holds its
	# first beat (snow, or the sunrise with the unlock) and the prompt reads PLEASE STAND BY; the tune-in to the
	# logo and PRESS ANY KEY start once everything is loaded (input is ignored until then).
	var loading: bool = game.loaded == false
	if loading:
		_t = 0.0
		_loadT += dt
	var P: Dictionary = _css.press
	if loading:
		if _loadT > 0.6 and not P.on:
			P.text = "PLEASE STAND BY"
			_setPressOn(true)
	elif P.text != _anyText():
		var wasLoading: bool = P.text == "PLEASE STAND BY"
		P.text = _anyText() # PRESS ANY BUTTON while the pad is the last device
		if wasLoading:
			_setPressOn(false)
	# loading bar under PLEASE STAND BY (game.loadProgress; the transition keeps it gliding through long steps)
	var B: Dictionary = _css.ldbar
	var pr: float = float(game.loadProgress) if loading else 1.0
	if pr != _ldP:
		_ldP = pr
		B.scale.set_(snappedf(pr, 0.001))
	var on := loading and _loadT > 0.6
	B.on.set_(1.0 if on else 0.0)
	var t := _t
	var TV: Dictionary = _room.tv
	var u: Dictionary = TV.u
	if _unlocked:
		# sunrise instead of snow, then the logo tunes in
		TV.pic = TV.sunrise if t < 0.9 else TV.titleTex
		u.uPic = 1.0
		u.uSnow = 0.08 if t < 0.9 else (lerp_(0.9, 0.04, easeOut((t - 0.9) / 0.65)) if t < 1.55 else 0.03)
	else:
		TV.pic = TV.titleTex
		u.uPic = 0.0 if t < 0.8 else 1.0
		u.uSnow = 1.0 if t < 0.8 else (lerp_(1.0, 0.04, easeOut((t - 0.8) / 0.8)) * (0.85 + 0.15 * sin(t * 60.0)) if t < 1.6 else 0.035)
	var tn := clamp_((t - 0.8) / 0.9, 0.0, 1.0)
	u.uRoll = 0.0 if t < 0.8 else (1.0 - easeOut(tn)) * 1.35
	u.uSeam = 0.9 if tn < 1.0 else 0.0
	# hold hiccup every few seconds once stable
	var hic := maxf(0.0, sin(t * 0.9) - 0.985) * 60.0 if t > 2.0 else 0.0
	u.uJitter = 0.2 if t < 0.8 else lerp_(1.0, 0.02, easeOut(tn)) + hic * 0.4
	u.uUI = 0.0
	u.uBright = 1.0
	if t > 0.8 and not _titlePing:
		_titlePing = true
		_play("crt_ping", {"vol": 0.6})
	if t < 0.1:
		_titlePing = false
	if not loading and t > 1.7 and not P.on:
		_setPressOn(true)
	_tvGlow("#B8D0FF" if t < 0.8 else "#FFB070", 1.3 + randf() * 0.5 if t < 0.8 else 1.7 + hic)

# -------------------------------------------------------------------------------------------- select
func _tuneTo(idx: int, instant: bool = false, dir: int = 1) -> void:
	var g = game
	_chIdx = idx
	var C: Dictionary = CHANNELS[idx]
	selected = C.hero
	_ch = {"t": 0.1 if instant else 0.0, "osd": 0.0, "chy": -1.0, "drawn": "", "pose": 0.0, "dir": dir}
	_showSet(idx)
	if not instant:
		_play("ui_menu_clack", {"vol": 0.75, "rate": 0.95 + randf() * 0.1})
	_play("telly_zip", {"vol": 0.3})
	if _musicT:
		_musicT.dead = true
	var hero: String = C.hero
	_musicT = _later(0.0 if instant else 0.09, func():
		if (mode == "select" or mode == "tunein") and g.audio and g.audio.has_method("music"):
			g.audio.music("select:%s" % hero))
	var R = _room
	if R:
		var det = R.parts.get("dialDetents", {})
		if det is Dictionary:
			var v = det.get(str(C.ch), det.get(C.ch))
			if v != null:
				R.dialTarget = float(v)

func _updateSelect(dt: float) -> void:
	var R: Dictionary = _room
	var TV: Dictionary = R.tv
	var u: Dictionary = TV.u
	var S := _ch
	if _camBlend < 1.0:
		_camBlend = minf(1.0, _camBlend + dt / 1.25)
	S.t += dt
	var t: float = S.t
	# snow burst -> rolling picture that settles
	var settle := clamp_((t - 0.16) / 0.45, 0.0, 1.0)
	TV.pic = _sets.tex if _sets else TV.titleTex
	u.uPic = 0.0 if t < 0.16 else 1.0
	u.uSnow = 1.0 if t < 0.16 else lerp_(0.85, 0.025, easeOut(settle))
	u.uRoll = 0.0 if t < 0.16 else (1.0 - easeOut(settle)) * 0.6 * float(S.dir if S.dir else 1)
	u.uSeam = 0.9 if settle < 1.0 else 0.0
	u.uJitter = lerp_(0.8, 0.012, easeOut(settle))
	u.uUI = 1.0
	u.uBright = 1.0
	_updateSetScene(dt, t)
	_drawUI(t)
	_prebuild(t)
	var C: Dictionary = CHANNELS[_chIdx]
	_tvGlow("#C8D8FF" if t < 0.16 else C.glow, 1.4 + randf() * 0.6 if t < 0.16 else 1.9)

func _updateTuneIn(dt: float) -> void:
	var R: Dictionary = _room
	var u: Dictionary = R.tv.u
	var t := _t
	_ch.t += dt
	_updateSetScene(dt, _ch.t)
	_drawUI(_ch.t)
	# the camera dives into the glass, the picture blows out to white, the flash covers the load
	var k := clamp_(t / 1.0, 0.0, 1.0)
	_camFrom = "select"
	_camTo = "screen"
	_camBlend = easeInCubic(k)
	u.uBright = 1.0 + easeIn(clamp_((t - 0.45) / 0.5, 0.0, 1.0)) * 5.0
	_css.flash.set_(easeIn(clamp_((t - 0.72) / 0.28, 0.0, 1.0)), true)
	_tvGlow(CHANNELS[_chIdx].glow, 1.9 + u.uBright)
	if t >= 1.0:
		_startGame()

func _startGame() -> void:
	var g = game
	var hero := selected
	hideAll()
	_css.flash.set_(1.0, true)
	_camBlend = 1.0
	if _lobby != null:
		var L = _lobby
		_lobby = null           # the dial is no longer the lobby (in-game net events are not the lobby's)
		L.startNow(hero)        # MP: the session's start (seed set by mp-core), same newGame(hero)
	else:
		g.newGame(hero)
	# transition 'opacity .6s cubic-bezier(.2,.7,.3,1) .12s' (a real-time transition, not the world clock)
	_css.flash.set_(0.0)

# -------------------------------------------------------------------------------------------- living room
func _ensureRoom() -> void:
	if _room != null:
		return
	_buildRoom()

func _use3D(on: bool, camera = null) -> void:
	var r = game.render
	if r == null:
		return
	var R = _room
	if on and R != null:
		R.scene.visible = true
		if game.scene:
			game.scene.visible = false   # the station is not drawn while the room shows
		var cam: Camera3D = camera if camera is Camera3D else R.camera
		if cam != R.camera:
			_fullColor(cam)
			if cam.environment == null:
				cam.environment = R.env   # the room's background (THREE scene.background of this scene)
		cam.current = true
		R.tvVp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		R.active = true
	elif R != null and R.active:
		R.scene.visible = false
		if game.scene:
			game.scene.visible = true
		var back = r.get("cameraOverride")
		if back is Camera3D and is_instance_valid(back):
			back.current = true
		elif game.camera:
			game.camera.current = true
		R.tvVp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _sets:
			_sets.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		R.active = false

# Loads a runtime GLB of blender/runtime/menu.py and gives every surface its DEAD AIR material from the "da" spec
# (SPEC §5.5), plus the node flags (castShadow, visible) of the node "da" extras.
func _asset(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("[menu] missing asset %s (run blender/build_all.py --only runtime)" % path)
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var inst: Node = (ps as PackedScene).instantiate()
	_applySpecs(inst)
	return inst as Node3D

func _applySpecs(n: Node) -> void:
	var M = game.mats
	var fn := func(o: Node) -> void:
		var ex = o.get_meta("extras") if o.has_meta("extras") else null
		if ex is Dictionary and ex.get("da") != null:
			var da = ex.da
			if da is String:
				da = JSON.parse_string(da)
			if da is Dictionary:
				var ud := DAU.ud(o)
				for k in da:
					ud[k] = da[k]
				if o is GeometryInstance3D and da.has("castShadow"):
					(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if da.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if da.get("visible") == false and o is Node3D:
					(o as Node3D).visible = false
		if o is MeshInstance3D and M != null and M.has_method("fromSpec"):
			var mi := o as MeshInstance3D
			if mi.mesh == null:
				return
			for i in mi.mesh.get_surface_count():
				var mat = mi.mesh.surface_get_material(i)
				if mat == null:
					continue
				var mex = mat.get_meta("extras") if mat.has_meta("extras") else null
				if mex is Dictionary and mex.get("da") != null:
					var m2 = M.fromSpec(mex.da, mat)
					if m2 != null:
						mi.set_surface_override_material(i, m2)
		if o is Node3D:
			(o as Node3D).rotation_order = EULER_ORDER_XYZ
	DAU.traverse(n, fn)

func _buildRoom() -> void:
	var g = game
	var M = g.mats
	var r = g.render
	var R := {"active": false, "dialAngle": 0.0, "dialVel": 0.0, "dialTarget": 0.0, "glow": Color("#FFB070").srgb_to_linear(), "glowI": 1.5,
		"external": null, "externalCam": null, "api": null, "parts": {}, "telly": null, "lava": null, "beacon": null, "screenMat": null, "seat": null}
	var scene := DAU.node3d("menu_livingRoom")
	scene.visible = false
	var host: Node = r.get("view") if r and r.get("view") is Node else g
	host.add_child(scene)
	R.env = _makeEnv("#0B0814", true)
	R.lights = _lightRig(scene, {"sky": "#6A78C8", "ground": "#3A2418", "hemi": 0.42, "key": "#A8BCFF", "keyI": 0.55, "fill": "#FFB070", "fillI": 0.1})
	_aim(R.lights.key, Vector3(-5.5, 3.6, -1.2), Vector3(0.5, 0.4, 0.6))
	var root_n := DAU.node3d("livingRoom")
	scene.add_child(root_n)
	R.scene = scene
	R.root = root_n

	# ---- shell (shag floor, paneled walls with the window hole, baseboards, ceiling), the window (walnut frame,
	# sill, glass bars, the night outside, the tower beacon, curtains, rod), the popcorn bowl and the TV guide:
	# the Blender runtime asset (blender/runtime/menu.py).
	var shell := _asset("res://assets/runtime/menu/room.glb")
	if shell:
		root_n.add_child(shell)
		R.beacon = shell.find_child("beacon", true, false)

	# ---- props (the kit's own AO + shadows); Telly's TV at the back wall
	var put := func(id: String, pos: Array, rotY: float = 0.0, opts: Dictionary = {}):
		var P0 = g.props
		if P0 == null or not P0.has_method("build"):
			return null
		var p = P0.build(id, opts)
		if not (p is Node3D):
			push_warning("[menu] prop %s failed" % id)
			return null
		p.position = Vector3(pos[0], pos[1], pos[2])
		p.rotation.y = rotY
		root_n.add_child(p)
		return p
	var telly = put.call("telly", [0, 0, 1.55], 0.0, {"card": null, "pose": "hidden", "legs": 0, "channel": 7})
	R.telly = telly
	put.call("telly_rug", [0, 0, 1.25])
	var lamp = put.call("telly_lamp", [-1.4, 0, 1.62], 0.4)
	if lamp:
		_propFn("setLampLevel", [g, lamp, 1])
	put.call("table_side_tulip", [1.38, 0, 1.66])
	var lava = put.call("lamp_lava", [1.38, 0.54, 1.66], 0.3)
	R.lava = lava
	put.call("plant_rubber", [2.45, 0, 1.62], 0.6)
	put.call("bookshelf", [-3.0 + 0.2, 0, 1.05], -PI / 2.0)
	put.call("clock_sunburst", [1.45, 1.3, 2.1 - 0.045])   # prop centre is 0.4 m above its origin -> hangs at ~1.7 m, above the lava lamp
	put.call("macrame_owl", [-2.25, 0.25, 2.1 - 0.07])
	# frame_picture's origin is the frame bottom (wall prop): hang both at ~1.25 m like real pictures
	put.call("frame_picture", [2.35, 1.25, 2.1 - 0.03], 0.0, {"card": "poster_precinct13", "style": "walnut"})
	put.call("frame_picture", [3.0 - 0.03, 1.25, -0.2], -PI / 2.0, {"card": "poster_boogie_down", "style": "gold"})
	put.call("sofa_cloud", [0.05, 0, -1.95], PI)
	put.call("table_coffee", [0.05, 0, -0.55], PI)

	# ---- Telly's glass: our composited picture
	var tud: Dictionary = DAU.ud(telly) if telly else {}
	var P: Dictionary = tud.get("parts", {}) if tud.get("parts") is Dictionary else {}
	var rig = tud.get("rig", {})
	var parts := P.duplicate()
	parts.dialDetents = rig.get("dial", {}).get("detents", {}) if rig is Dictionary and rig.get("dial") is Dictionary else {}
	R.parts = parts
	for k in ["dial", "earL", "earR", "screen", "body"]:
		if P.get(k) is Node3D:
			(P[k] as Node3D).rotation_order = EULER_ORDER_XYZ
	R.screenMat = _meshMat(P.get("screen"))
	_room = R
	R.tv = _buildTv()
	R.tvVp = R.tv.vp
	if R.screenMat:
		R.screenMat.map = R.tv.tex
	R.dialAngle = (P.dial as Node3D).rotation.z if P.get("dial") is Node3D else 0.0
	R.dialTarget = R.dialAngle
	var glowFrom: Vector3 = (P.screen as Node3D).global_position if P.get("screen") is Node3D else Vector3(0.12, 0.9, 1.45) # lighting keeps the prop's anchor
	_seatScreen(R, telly)
	R.screenWorld = (P.screen as Node3D).global_position if P.get("screen") is Node3D else Vector3(0.12, 0.9, 1.45)

	# ---- lights: TV glow, lamp, lava, moon spill (the rest of the pool stays dark)
	var L: Array = R.lights.points
	L[0].position = glowFrom + Vector3(0, -0.45, -1.35)
	L[0].omni_range = 4.5
	if P.get("glass") is Node3D:
		(P.glass as Node3D).visible = false # the rubber membrane's env reflection washes the picture out at this range
	var la = null
	if lamp:
		var las = DAU.ud(lamp).get("lightAnchors")
		if las is Array and not las.is_empty():
			la = las[0]
	if lamp and la is Dictionary and la.get("pos") != null:
		L[1].position = (lamp as Node3D).global_transform * DAU.v3(la.pos)
	else:
		L[1].position = Vector3(-1.4, 1.5, 1.62)
	L[1].light_color = Color("#FFC98A")
	L[1].light_energy = 2.4
	L[1].omni_range = 5.5
	L[2].position = Vector3(1.38, 0.85, 1.5)
	L[2].light_color = Color("#FF7A5A")
	L[2].light_energy = 0.7
	L[2].omni_range = 2.2
	L[3].position = Vector3(-3.0 + 0.5, 1.42, -0.55)
	L[3].light_color = Color("#7C94FF")
	L[3].light_energy = 1.1
	L[3].omni_range = 3.2
	L[4].position = Vector3(0.3, 1.9, -2.6)
	L[4].light_color = Color("#FF9A50")
	L[4].light_energy = 0.35
	L[4].omni_range = 4.0

	# ---- dust motes in the TV light (random each run: a points mesh with the DUST shaders)
	var N := 90
	var pos := PackedVector3Array()
	var seed := PackedFloat32Array()
	for i in N:
		pos.append(Vector3((randf() - 0.5) * 1.6, 0.45 + randf() * 1.2, -0.6 + randf() * 1.5))
		for k in 4:
			seed.append(randf())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_CUSTOM0] = seed
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var dm := ShaderMaterial.new()
	var dsh := Shader.new()
	dsh.code = DUST_SHADER
	dm.shader = dsh
	dm.set_shader_parameter("uSize", 11.0 * minf(1.5, maxf(1.0, DisplayServer.screen_get_scale())))
	dm.set_shader_parameter("uColor", Color("#FFE2B8"))
	dm.set_shader_parameter("uAlpha", 0.22)
	var dust := MeshInstance3D.new()
	dust.name = "dust"
	dust.mesh = am
	dust.material_override = dm
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.extra_cull_margin = 16384.0
	root_n.add_child(dust)
	R.dust = dm

	# ---- cameras
	var cam := Camera3D.new()
	cam.name = "menuCam"
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 60.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.environment = R.env
	cam.cull_mask = 1 << int(Config.LAYERS.WORLD)
	_fullColor(cam)
	R.camera = cam
	var sw: Vector3 = R.screenWorld
	R.poses = {
		"title": {"pos": Vector3(0.5, 1.42, -2.35), "target": Vector3(0.02, 1.0, 1.4), "fov": 42.0},
		"select": {"pos": Vector3(-0.06, 1.02, -0.95), "target": Vector3(-0.1, 0.9, 1.5), "fov": 38.0},
		"screen": {"pos": Vector3(sw.x, sw.y, sw.z - 0.34), "target": sw, "fov": 44.0},
		"review": {"pos": Vector3(sw.x, sw.y, sw.z - 1.25), "target": sw, "fov": 34.0},
		# MP: the main menu (the TV on the left, the pills on the right) and its cards (the TV a little further left)
		"main": {"pos": Vector3(0.1, 1.3, -1.3), "target": Vector3(-0.55, 1.0, 1.45), "fov": 42.0},
		"card": {"pos": Vector3(0.0, 1.3, -1.3), "target": Vector3(-0.75, 1.0, 1.45), "fov": 42.0},
	}
	scene.add_child(cam)

# The DEAD AIR environment of a scene background (render.makeEnvironment: flat colour, the grade does the rest).
func _makeEnv(bg: String, glow: bool) -> Environment:
	var r = game.render
	if r and r.has_method("makeEnvironment"):
		# render.gd's settings for other worlds (the bloom is render's UnrealBloom chain over the whole view)
		return r.makeEnvironment(Color(bg))
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(bg)
	return e

# While this scene renders: full colour (no pre-power grade, no Sign-On wave), heroes never dither-fade; the room
# is too small for the station's fog (THREE.Fog 40..90 m never reaches it): the camera flags of render.gd.
func _fullColor(cam: Camera3D) -> void:
	var r = game.render
	var full: int = r.CAM_FULLCOLOR if r and r.get("CAM_FULLCOLOR") != null else (1 << 19)
	var nofog: int = r.CAM_NOFOG if r and r.get("CAM_NOFOG") != null else (1 << 18)
	cam.cull_mask |= full | nofog

# Points a directional light from `pos` toward `target` (three: light.position + light.target).
static func _aim(l: Node3D, pos: Vector3, target: Vector3) -> void:
	l.position = pos
	var d := target - pos
	if d.length_squared() < 1e-12:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.999 else Vector3.FORWARD
	l.basis = Basis.looking_at(d, up)

# Same light counts as core/lights.gd (1 hemisphere, 2 directional with 1 shadow, 8 points).
func _lightRig(scene: Node3D, o: Dictionary) -> Dictionary:
	var hemi: Node3D = null
	if ResourceLoader.exists("res://scripts/core/lights.gd"):
		var LS = load("res://scripts/core/lights.gd")
		if LS and LS.get("DAHemi") != null:
			hemi = LS.DAHemi.new(o.sky, o.ground, float(o.hemi))
	if hemi == null:
		hemi = Node3D.new()
		hemi.name = "HemisphereLight"
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(o.key)
	key.light_energy = float(o.keyI)
	key.light_specular = 1.0
	key.shadow_enabled = not DAU.isCompat()   # web: a shadowed light is an extra pass that Compatibility adds in sRGB (too bright)
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 9.0     # the JS shadow camera box -4.5..4.5
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.0
	key.shadow_blur = 1.5
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(o.fill)
	fill.light_energy = float(o.fillI)
	fill.light_specular = 1.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_aim(fill, Vector3(1.5, 1.2, -2), Vector3.ZERO)
	var points: Array = []
	for i in 8:
		var p := OmniLight3D.new()
		p.name = "PointLight%d" % i
		p.light_color = Color("#ffffff")
		p.light_energy = 0.0
		p.omni_range = 6.0
		p.omni_attenuation = 1.5
		p.light_specular = 1.0
		p.shadow_enabled = false
		points.append(p)
		scene.add_child(p)
	scene.add_child(hemi)
	scene.add_child(key)
	scene.add_child(fill)
	return {"hemi": hemi, "key": key, "fill": fill, "points": points}

func _card(id: String, opts: Dictionary = {}):
	return _cardsCall("get_", [id, opts])   # cards.get (renamed get_ by cards.gd)

# game.cards: the broadcast-card namespace (cards.gd installs it on first use: make sure it is loaded).
func _cardsCall(m: String, args: Array):
	if game.cards == null and ResourceLoader.exists("res://scripts/gfx/cards.gd"):
		var CS = load("res://scripts/gfx/cards.gd")
		if CS and CS.has_method("install"):
			CS.install(game)
	var C = game.cards
	if C == null:
		return null
	if C is Object:
		if C.has_method(m):
			return C.callv(m, args)
		var v = C.get(m)
		if v is Callable and v.is_valid():
			return v.callv(args)
		return null
	if C is Dictionary:
		var f = C.get(m)
		if f is Callable and f.is_valid():
			return f.callv(args)
	return null

# props/machines helpers (setLampLevel …): on game.props or on the machines prop script.
func _propFn(name: String, args: Array):
	var P = game.props
	if P and P.has_method(name):
		return P.callv(name, args)
	for path in ["res://scripts/props/machines.gd", "res://scripts/props/props_machines.gd"]:
		if ResourceLoader.exists(path):
			var S = load(path)
			if S and S.has_method(name):
				return S.callv(name, args)
	return null

func _meshMat(n):
	if not (n is MeshInstance3D):
		return null
	var mi := n as MeshInstance3D
	if mi.material_override:
		return mi.material_override
	if mi.mesh and mi.mesh.get_surface_count() > 0:
		var m = mi.get_surface_override_material(0)
		if m:
			return m
		return mi.mesh.surface_get_material(0)
	return null

func _updateRoom(dt: float) -> void:
	var R = _room
	if R == null:
		return
	var t: float = game.time.realNow
	# camera: blend between poses + a slow handheld drift
	var A: Dictionary = R.poses.get(_camFrom, R.poses.title)
	var B: Dictionary = R.poses.get(_camTo, R.poses.title)
	var k := _camBlend if mode == "tunein" else easeInOut(clamp_(_camBlend, 0.0, 1.0))
	var cam: Camera3D = R.camera
	var p: Vector3 = (A.pos as Vector3).lerp(B.pos, k)
	var v: Vector3 = (A.target as Vector3).lerp(B.target, k)
	var drift := 0.2 if mode == "tunein" else 1.0
	p.x += sin(t * 0.37) * 0.018 * drift
	p.y += sin(t * 0.53 + 1.3) * 0.012 * drift
	if mode == "title":
		p.z += minf(_t, 30.0) * 0.008
	v.x += sin(t * 0.29 + 0.7) * 0.01 * drift
	cam.position = p
	if not p.is_equal_approx(v):
		cam.look_at(v, Vector3.UP)
	var vsz := _viewSize()
	var aspect := vsz.x / maxf(1.0, vsz.y)
	var fov := lerp_(A.fov, B.fov, k)
	if R.get("cur") is Dictionary:   # where the camera is now (MP: _camGo blends start here)
		R.cur.pos = p
		R.cur.target = v
		R.cur.fov = fov
	else:
		R.cur = {"pos": p, "target": v, "fov": fov}
	# keep the TV framed on narrow screens (fit the horizontal field instead)
	if aspect < 1.6:
		fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) / 2.0) * 1.6 / aspect))
	if cam.fov != fov:
		cam.fov = fov
	# dial spring toward its detent (overshoot = the clack), plus a punch when clicked
	var P: Dictionary = R.parts
	if P.get("dial") is Node3D:
		R.dialVel += ((R.dialTarget - R.dialAngle) * 420.0 - R.dialVel * 24.0) * dt
		R.dialAngle += R.dialVel * dt
		var dial: Node3D = P.dial
		dial.rotation.z = R.dialAngle
		var hov := 1.0 if _hover == "dial" else 0.0
		_dialPunch = maxf(0.0, _dialPunch - dt * 5.0)
		dial.scale = Vector3.ONE * (1.0 + hov * 0.06 + sin(_dialPunch * PI) * 0.1)
	# rabbit ears breathe a little
	if P.get("earL") is Node3D:
		(P.earL as Node3D).rotation.x = 0.06 + sin(t * 1.3) * 0.02
	if P.get("earR") is Node3D:
		(P.earR as Node3D).rotation.x = 0.2 + sin(t * 1.1 + 1.0) * 0.02
	if R.beacon is Node3D:
		(R.beacon as Node3D).visible = fmod(t, 1.6) < 0.8
	# lava blobs drift if the prop exposes them
	var lp = DAU.ud(R.lava).get("parts") if R.lava is Node3D else null
	var blobs = lp.get("blobs") if lp is Dictionary else null
	if blobs is Node:
		var i := 0
		for b in (blobs as Node).get_children():
			if b is Node3D:
				var bud := DAU.ud(b)
				if bud.get("y0") == null:
					bud.y0 = (b as Node3D).position.y
				(b as Node3D).position.y = float(bud.y0) + sin(t * 0.4 + i * 2.1) * 0.05
			i += 1
	var L: Array = R.lights.points
	var cur: Color = (L[0] as OmniLight3D).light_color.srgb_to_linear()
	(L[0] as OmniLight3D).light_color = cur.lerp(R.glow, 1.0 - exp(-dt * 8.0)).linear_to_srgb()
	L[0].light_energy = lerp_(L[0].light_energy, R.glowI, 1.0 - exp(-dt * 12.0))
	L[1].light_energy = 2.4 + sin(t * 7.3) * 0.03

func _viewSize() -> Vector2:
	var r = game.render
	var v = r.get("view") if r else null
	if v is SubViewport:
		return Vector2((v as SubViewport).size)
	var vp: Viewport = game.get_viewport()
	return vp.get_visible_rect().size if vp else Vector2(1920, 1080)

func _tvGlow(color: String, intensity: float) -> void:
	var R = _room
	if R == null:
		return
	R.glow = Color(color).srgb_to_linear().lerp(Color("#FFE8D0").srgb_to_linear(), 0.45) # a soft wash: the picture tints the room, it does not repaint the TV
	R.glowI = intensity * 0.8

# Picks what the mouse is over in the select view: 'dial' | 'screen' | null.
func _pick(pos: Vector2):
	var R = _room
	if R == null or not R.active:
		return null
	var cam: Camera3D = R.camera
	var vp: Viewport = game.get_viewport()
	var vis: Vector2 = vp.get_visible_rect().size if vp else Vector2(1920, 1080)
	var vpos := pos / vis * _viewSize()
	var o := cam.project_ray_origin(vpos)
	var d := cam.project_ray_normal(vpos)
	var P: Dictionary = R.parts
	if P.get("dial") is Node3D:
		var w: Vector3 = (P.dial as Node3D).global_position
		var q: Vector3 = w - o
		var tt := maxf(0.0, q.dot(d))
		if (o + d * tt).distance_squared_to(w) < 0.11 * 0.11:
			return "dial"
	if P.get("screen") is Node3D:
		var rig = DAU.ud(R.telly).get("rig", {}) if R.telly else {}
		var sr = rig.get("screen", {}) if rig is Dictionary else {}
		var sw: float = float(sr.get("w", 0.8)) + 0.04
		var sh: float = float(sr.get("h", 0.6)) + 0.04
		for n in [P.get("glass"), P.get("screen")]:
			if not (n is Node3D):
				continue
			var xf: Transform3D = (n as Node3D).global_transform
			var inv := xf.affine_inverse()
			var lo: Vector3 = inv * o
			var ld: Vector3 = inv.basis * d
			if absf(ld.z) < 1e-6:
				continue
			var s := -lo.z / ld.z
			if s <= 0.0:
				continue
			var hp := lo + ld * s
			if absf(hp.x) <= sw / 2.0 and absf(hp.y) <= sh / 2.0:
				return "screen"
	return null

# -------------------------------------------------------------------------------------------- TV compositing
func _buildTv() -> Dictionary:
	var W := 640
	var H := 480
	var vp := SubViewport.new()
	vp.name = "menu_tv"
	vp.size = Vector2i(W, H)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(W, H)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = COMP_SHADER
	mat.shader = sh
	rect.material = mat
	vp.add_child(rect)
	game.add_child(vp)
	var ui = _canvas(W, H)
	var titleCv = _titleCanvas(W, H)
	var sunriseCv = _sunriseCanvas(W, H)
	var TV := {"vp": vp, "tex": vp.get_texture(), "mat": mat, "ui": ui, "uiCtx": ui.getContext("2d") if ui else null,
		"uiTex": ui.texture if ui else null, "titleTex": titleCv.texture if titleCv else null, "sunrise": sunriseCv.texture if sunriseCv else null,
		"titleCv": titleCv, "sunriseCv": sunriseCv, "uiKey": "",
		"u": {"uSnow": 1.0, "uRoll": 0.0, "uJitter": 0.0, "uPic": 0.0, "uUI": 0.0, "uBright": 1.0, "uSeam": 0.0}, "pic": null}
	TV.pic = TV.titleTex
	var r = game.render
	if r and r.has_method("addPrePass"):
		_unPre = r.addPrePass(func(_rr): _prePass())
	return TV

func _tvMode(m: String) -> void:
	_tvState = m

# DACanvas (scripts/gfx/canvas2d.gd) of w x h, or null while the canvas port is missing.
func _canvas(w: int, h: int):
	var path := "res://scripts/gfx/canvas2d.gd"
	if not ResourceLoader.exists(path):
		return null
	var C = load(path)
	if C == null or not C.can_instantiate():
		return null
	return C.new(w, h)

# Seats Telly's CRT canvas in the bezel opening (title, select and the ending's room). The telly prop builds it as a
# diorama for the glove: the canvas sits ~0.21 m behind the cream faceplate. From the title's three-quarter view that
# tunnel showed as grey/black bands beside and under the picture, so the picture looked shifted out of its frame.
# And the dark tunnel liner's front ring was coplanar with the faceplate front (same plane, same merged draw):
# z-fighting, the jagged black flicker just outside the brass lip. Here, on the menu's own Telly only:
#   - the liner's front ring is tucked 1 cm back, inside the faceplate (nothing coplanar is left on show);
#   - the canvas sits just behind the bezel (its overscan edge hidden in the faceplate/liner, the visible edge under
#     the brass lip) with a shallow dome that stays behind the lip;
#   - while the glove is out (ending) it eases back to the diorama depth + dome so the arm still comes out of the
#     tunnel (_seatUpdate, every frame from _prePass).
func _seatScreen(R: Dictionary, telly) -> void:
	var P: Dictionary = R.parts
	var scr = P.get("screen")
	var rig = DAU.ud(telly).get("rig", {}) if telly is Node3D else {}
	var srig = rig.get("screen") if rig is Dictionary else null
	var body = P.get("body")
	if not (scr is Node3D) or not (srig is Dictionary) or not (body is Node3D):
		return
	var c: Array = srig.center
	var sx: float = float(c[0])
	var sy: float = float(c[1])
	var cz: float = float(c[2])
	var hw: float = float(srig.w) / 2.0
	var hh: float = float(srig.h) / 2.0
	var ring := func(x: float, y: float) -> float: return maxf(absf(x - sx) - hw, absf(y - sy) - hh) # box distance to the window edge
	# the liner: dark vertex-coloured faces around the window, in body space
	var front := INF
	var hits: Array = []
	var meshes: Array = []
	DAU.traverse(body, func(o: Node) -> void:
		if o is MeshInstance3D and o != scr and (o as MeshInstance3D).mesh is ArrayMesh:
			meshes.append(o))
	for mi in meshes:
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		var toBody: Transform3D = (body as Node3D).global_transform.affine_inverse() * (mi as Node3D).global_transform
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var pa: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ca = arr[Mesh.ARRAY_COLOR]
			if not (ca is PackedColorArray) or (ca as PackedColorArray).size() != pa.size():
				continue
			var idx: Array = []
			for i in pa.size():
				var bp: Vector3 = toBody * pa[i]
				var d: float = ring.call(bp.x, bp.y)
				if d < -0.05 or d > 0.03 or bp.z > cz - 0.05:
					continue
				var col: Color = ca[i]
				if col.r + col.g + col.b > 0.3 or col.b <= col.r:
					continue # dark + blue-leaning: the plum liner, not cream/walnut
				idx.append(i)
				front = minf(front, bp.z)
			if not idx.is_empty():
				hits.append([mi, si, idx, toBody])
	if not is_finite(front):
		return
	# per mesh: the moved vertices of each hit surface, then a rebuilt copy of the mesh (the prop's buffers stay untouched)
	var byMesh := {}
	for hit in hits:
		var mi2: MeshInstance3D = hit[0]
		if not byMesh.has(mi2):
			byMesh[mi2] = {}
		var am := mi2.mesh as ArrayMesh
		var si: int = hit[1]
		var arr := am.surface_get_arrays(si)
		var pa2: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var tb: Transform3D = hit[3]
		var inv := tb.affine_inverse()
		var n := 0
		for i in hit[2]:
			var bp2: Vector3 = tb * pa2[i]
			if bp2.z < front + 0.0045:
				bp2.z += 0.01 # front cap + bevel
				pa2[i] = inv * bp2
				n += 1
		arr[Mesh.ARRAY_VERTEX] = pa2
		byMesh[mi2][si] = arr
		R.linerTucked = int(R.get("linerTucked", 0)) + n
	for mi3 in byMesh:
		_rebuildMesh(mi3, byMesh[mi3])
	var sm = _meshMat(scr)
	var U = sm.get("uniforms") if sm is Object else null
	var b0: float = 0.0
	if U is Dictionary and U.get("uBulge") != null:
		b0 = float(U.uBulge.value)
	R.seat = {
		"diorama": (scr as Node3D).position.z, "flush": front + 0.0085, # faceplate front + 8.5 mm: just in front of the faceplate/liner hole walls
		"bulge0": b0, "bulge": 0.012, # dome apex 3.5 mm proud of the faceplate, 7.5 mm behind the lip
		"k": 1.0, "last": -1.0,
	}
	_seatUpdate(R, true)

# A copy of mi's ArrayMesh with some surfaces' arrays replaced ({surface index: arrays}), materials kept.
static func _rebuildMesh(mi: MeshInstance3D, repl: Dictionary) -> void:
	var am := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	var custom := 0
	for c in 4:
		custom |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	for bs in am.get_blend_shape_count():
		out.add_blend_shape(am.get_blend_shape_name(bs))
	out.blend_shape_mode = am.blend_shape_mode
	var overrides: Array = []
	for s in am.get_surface_count():
		overrides.append(mi.get_surface_override_material(s))
		var arr: Array = repl[s] if repl.has(s) else am.surface_get_arrays(s)
		out.add_surface_from_arrays(am.surface_get_primitive_type(s), arr, am.surface_get_blend_shape_arrays(s), {}, am.surface_get_format(s) & custom)
		out.surface_set_material(s, am.surface_get_material(s))
		out.surface_set_name(s, am.surface_get_name(s))
	mi.mesh = out
	for s in overrides.size():
		if overrides[s] != null:
			mi.set_surface_override_material(s, overrides[s])

func _seatUpdate(R: Dictionary, snap: bool = false) -> void:
	var S = R.get("seat")
	var P: Dictionary = R.parts
	var scr = P.get("screen")
	if S == null or not (scr is Node3D):
		return
	var armOut: bool = (P.get("arm") is Node3D and (P.arm as Node3D).visible) or (P.get("glove") is Node3D and (P.glove as Node3D).visible)
	var want := 0.0 if armOut else 1.0
	var now: float = game.time.realNow if game.time else 0.0
	var dt := 0.0 if S.last < 0.0 else minf(0.1, maxf(0.0, now - S.last))
	S.last = now
	if snap:
		S.k = want
	elif S.k != want:
		S.k = minf(1.0, S.k + dt / 0.25) if want > S.k else maxf(0.0, S.k - dt / 0.12)
	var e := easeInOut(S.k)
	(scr as Node3D).position.z = lerp_(S.diorama, S.flush, e)
	var sm = _meshMat(scr)
	var U = sm.get("uniforms") if sm is Object else null
	if U is Dictionary and U.get("uBulge") != null:
		U.uBulge.value = lerp_(S.bulge0, S.bulge, e)

func _prePass() -> void:
	var R = _room
	if R == null or not R.active or (not mode and R.externalCam == null):
		return
	_seatUpdate(R)
	var TV: Dictionary = R.tv
	if _sets:
		var want: bool = _tvState == "channel" and (mode == "select" or mode == "tunein")
		_sets.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if want else SubViewport.UPDATE_DISABLED
	var pic = TV.pic if TV.pic != null else TV.titleTex
	var m: ShaderMaterial = TV.mat
	var lin: bool = pic is ViewportTexture
	m.set_shader_parameter("uPicLin", 1.0 if lin else 0.0)
	if lin:
		m.set_shader_parameter("tPicL", pic)
	else:
		m.set_shader_parameter("tPicS", pic)
	m.set_shader_parameter("tUI", TV.uiTex)
	m.set_shader_parameter("uTime", _uTime())
	for k in TV.u:
		m.set_shader_parameter(k, TV.u[k])

# materials' uTime (the global shader clock).
func _uTime() -> float:
	var M = game.mats
	var U = M.get("uniforms") if M else null
	if U is Dictionary and U.get("uTime") != null:
		return float(U.uTime.value)
	return float(game.time.realNow)

func _titleCanvas(W: int, H: int):
	var c = _canvas(W, H)
	if c == null:
		return null
	var x = c.getContext("2d")
	var bg = x.createRadialGradient(W / 2.0, H * 0.45, 20, W / 2.0, H * 0.5, W * 0.7)
	bg.addColorStop(0, "#4A2A6E")
	bg.addColorStop(0.55, "#24164A")
	bg.addColorStop(1, "#0E0A22")
	x.fillStyle = bg
	x.fillRect(0, 0, W, H)
	x.save()
	x.translate(W / 2.0, H * 0.46)
	for i in 24:
		x.rotate(PI / 12.0)
		x.fillStyle = "rgba(255,120,60,.10)" if i % 2 else "rgba(255,200,90,.07)"
		x.beginPath()
		x.moveTo(0, 0)
		x.lineTo(W, -46)
		x.lineTo(W, 46)
		x.closePath()
		x.fill()
	x.restore()
	var barsY := H * 0.86
	var BARS: Array = Config.BARS
	for i in BARS.size():
		x.fillStyle = BARS[i]
		x.globalAlpha = 0.85
		x.fillRect((i * W) / float(BARS.size()), barsY, W / float(BARS.size()) + 1, H * 0.035)
	x.globalAlpha = 1
	# cards.drawTo draws at 0,0 scaled to w x h: translate into place first
	x.save()
	x.translate(W * 0.03, H * 0.12)
	_cardsCall("drawTo", [x, "logo_dead_air", W * 0.94, W * 0.47, 0.0, {}]) # cards missing: the gradient stays
	x.restore()
	return c

func _sunriseCanvas(W: int, H: int):
	var c = _canvas(W, H)
	if c == null:
		return null
	var x = c.getContext("2d")
	var gr = x.createLinearGradient(0, 0, 0, H)
	gr.addColorStop(0, "#FF7E5F")
	gr.addColorStop(0.55, "#FFB36B")
	gr.addColorStop(1, "#FFE3A3")
	x.fillStyle = gr
	x.fillRect(0, 0, W, H)
	x.save()
	x.translate(W / 2.0, H * 0.78)
	for i in 18:
		x.rotate(PI / 9.0)
		x.fillStyle = "rgba(255,255,255,.12)"
		x.beginPath()
		x.moveTo(0, 0)
		x.lineTo(W, -40)
		x.lineTo(W, 40)
		x.closePath()
		x.fill()
	x.restore()
	x.fillStyle = "#FFF4D6"
	x.beginPath()
	x.arc(W / 2.0, H * 0.78, H * 0.2, PI, 0)
	x.fill()
	x.fillStyle = "#8A3A2A"
	x.fillRect(0, H * 0.78, W, H * 0.22)
	x.strokeStyle = "#5A2218"
	x.lineWidth = 5
	x.beginPath()
	x.moveTo(W * 0.72, H * 0.78)
	x.lineTo(W * 0.76, H * 0.3)
	x.lineTo(W * 0.8, H * 0.78)
	x.stroke()
	return c

# Overlay drawn into the TV picture: the OSD channel number (fades after 2.5 s), the station bug and the chyron.
func _drawUI(t: float) -> void:
	var TV: Dictionary = _room.tv
	var x = TV.uiCtx
	if x == null:
		return
	var W: float = TV.ui.width
	var H: float = TV.ui.height
	var C: Dictionary = CHANNELS[_chIdx]
	var hero = null
	var HL = _heroesLib()
	if HL:
		for h in HL.HEROES:
			if h.id == C.hero:
				hero = h
	var osd := 1.0 if t < 2.4 else clamp_(1.0 - (t - 2.4) / 0.5, 0.0, 1.0)
	var cp := clamp_((t - 0.38) / 0.42, 0.0, 1.0)
	var chyX := -1.0 if t < 0.38 else 1.0 - easeOutBack(cp, 1.3)
	var key := "%d|%s|%s" % [_chIdx, String.num(osd, 2), String.num(chyX, 3)]
	var claim := ""
	var LD := {}
	if _lobby != null:
		# MP: the claim tab (ON AIR: <NAME>) and the countdown's film leader are part of the picture
		claim = _lobby.claimText(C.hero)
		LD = _lobby.leader()
		key += "|%s|%s|%d" % [claim, String.num(LD.get("frac", -1.0), 2), LD.get("n", 0)]
		if claim != "":
			key += "|%d" % (int(game.time.realNow * 2.0) % 2)
	if key == TV.uiKey:
		return
	TV.uiKey = key
	x.clearRect(0, 0, W, H)
	# OSD channel number, top right (VT323 green with a dark drop)
	if osd > 0.0 and t > 0.05:
		x.globalAlpha = osd
		x.font = "92px " + FontsScript.FONTS.tape
		x.textAlign = "right"
		x.textBaseline = "top"
		x.fillStyle = "rgba(10,20,10,.75)"
		x.fillText(str(C.ch), W - 34 + 4, 22 + 4)
		x.fillStyle = "#5CFF6E"
		x.fillText(str(C.ch), W - 34, 22)
		x.globalAlpha = 1
	# station bug bottom right
	x.globalAlpha = 0.55
	x.beginPath()
	x.arc(W - 46, H - 44, 20, 0, 7)
	x.fillStyle = "#F4F1E8"
	x.fill()
	x.lineWidth = 4
	x.strokeStyle = "#E23B3B"
	x.stroke()
	x.font = "18px " + FontsScript.FONTS.hud
	x.textAlign = "center"
	x.textBaseline = "middle"
	x.fillStyle = "#2F5BD3"
	x.fillText("13", W - 46, H - 43)
	x.globalAlpha = 1
	# chyron (lower third)
	if chyX > -1.0:
		x.save()
		x.translate(chyX * (W * 0.9), 0)
		var y0 := H - 148
		var bw := W * 0.8
		var gr = x.createLinearGradient(0, y0, 0, y0 + 64)
		gr.addColorStop(0, "#F59A48")
		gr.addColorStop(0.5, "#D9602B")
		gr.addColorStop(1, "#A8401E")
		x.fillStyle = "rgba(20,8,4,.35)"
		_rr(x, 30, y0 + 6, bw, 64, 32)
		x.fill()
		x.fillStyle = gr
		_rr(x, 24, y0, bw, 64, 32)
		x.fill()
		x.fillStyle = "rgba(255,255,255,.28)"
		x.fillRect(48, y0 + 5, bw - 60, 3)
		x.fillStyle = "#4A2616"
		_rr(x, 60, y0 + 60, bw * 0.78, 30, 12)
		x.fill()
		x.font = "40px " + FontsScript.FONTS.logo
		x.textAlign = "left"
		x.textBaseline = "middle"
		x.lineJoin = "round"
		x.lineWidth = 6
		x.strokeStyle = "#5A2210"
		var nm: String = hero.name if hero else C.hero
		x.strokeText(nm, 50, y0 + 31)
		x.fillStyle = "#FFFBEA"
		x.fillText(nm, 50, y0 + 31)
		x.font = "17px " + FontsScript.FONTS.sign
		x.fillStyle = "#FFD27A"
		x.fillText(C.role, 76, y0 + 76)
		if claim != "":
			_drawClaimTab(x, 24.0, y0 - 52.0, claim)
		x.restore()
	if not LD.is_empty():
		_drawLeader(x, W, H, int(LD.n), float(LD.frac))
	if TV.ui.has_method("redraw"):
		TV.ui.redraw()

# MP: the red ON AIR tab over the chyron of a claimed channel (a blinking tally light + the claimant's name).
func _drawClaimTab(x, px: float, py: float, s: String) -> void:
	x.font = "22px " + FontsScript.FONTS.sign
	var tw: float = x.measureText(s).width
	var w := tw + 62.0
	x.fillStyle = "rgba(20,8,4,.4)"
	_rr(x, px + 5, py + 5, w, 42, 12)
	x.fill()
	var gr = x.createLinearGradient(0, py, 0, py + 42)
	gr.addColorStop(0, "#FF5A48")
	gr.addColorStop(1, "#B0102A")
	x.fillStyle = gr
	_rr(x, px, py, w, 42, 12)
	x.fill()
	x.lineWidth = 3
	x.strokeStyle = "#FFF4E8"
	_rr(x, px, py, w, 42, 12)
	x.stroke()
	var on: bool = int(game.time.realNow * 2.0) % 2 == 0
	x.beginPath()
	x.arc(px + 24, py + 21, 8, 0, TAU)
	x.fillStyle = "#FFF4E8" if on else "rgba(255,244,232,.35)"
	x.fill()
	x.textAlign = "left"
	x.textBaseline = "middle"
	x.fillStyle = "#FFF4E8"
	x.fillText(s, px + 42, py + 22)

# MP: the 3-2-1 film leader over the picture (rings, crosshair, the sweeping hand, the number).
func _drawLeader(x, W: float, H: float, n: int, frac: float) -> void:
	var cx := W / 2.0
	var cy := H / 2.0
	var R := H * 0.36
	x.fillStyle = "rgba(26,20,14,.66)"
	x.fillRect(0, 0, W, H)
	x.beginPath()
	x.moveTo(cx, cy)
	x.arc(cx, cy, R * 1.9, -PI / 2.0, -PI / 2.0 + TAU * clamp_(frac, 0.0, 1.0))
	x.closePath()
	x.fillStyle = "rgba(255,244,214,.20)"
	x.fill()
	x.strokeStyle = "rgba(244,241,232,.9)"
	x.lineWidth = 3
	x.beginPath()
	x.moveTo(0, cy)
	x.lineTo(W, cy)
	x.moveTo(cx, 0)
	x.lineTo(cx, H)
	x.stroke()
	x.lineWidth = 7
	x.beginPath()
	x.arc(cx, cy, R, 0, TAU)
	x.stroke()
	x.lineWidth = 3
	x.beginPath()
	x.arc(cx, cy, R * 0.8, 0, TAU)
	x.stroke()
	x.font = "190px " + FontsScript.FONTS.hud
	x.textAlign = "center"
	x.textBaseline = "middle"
	x.fillStyle = "rgba(20,10,4,.6)"
	x.fillText(str(n), cx + 5, cy + 13)
	x.fillStyle = "#F4F1E8"
	x.fillText(str(n), cx, cy + 8)

func _rr(x, px: float, py: float, w: float, h: float, r: float) -> void:
	x.beginPath()
	x.moveTo(px + r, py)
	x.lineTo(px + w - r, py)
	x.quadraticCurveTo(px + w, py, px + w, py + r)
	x.lineTo(px + w, py + h - r)
	x.quadraticCurveTo(px + w, py + h, px + w - r, py + h)
	x.lineTo(px + r, py + h)
	x.quadraticCurveTo(px, py + h, px, py + h - r)
	x.lineTo(px, py + r)
	x.quadraticCurveTo(px, py, px + r, py)
	x.closePath()

# -------------------------------------------------------------------------------------------- hero sets (on TV)
func _ensureSets() -> Dictionary:
	if _sets != null:
		return _sets
	var vp := SubViewport.new()
	vp.name = "menu_sets"
	vp.size = Vector2i(640, 480)
	vp.own_world_3d = true
	vp.use_hdr_2d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	game.add_child(vp)
	var scene := DAU.node3d("menu_sets")
	vp.add_child(scene)
	var env := _makeEnv("#1E1530", false)
	var lights := _lightRig(scene, {"sky": "#FFE8D0", "ground": "#4A3048", "hemi": 0.85, "key": "#FFE4C2", "keyI": 1.9, "fill": "#9FB6FF", "fillI": 0.35})
	_aim(lights.key, Vector3(2.2, 4.5, 4), Vector3(0, 0.8, 0))
	var cam := Camera3D.new()
	cam.name = "setCam"
	cam.fov = 25.0
	cam.near = 0.1
	cam.far = 40.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.environment = env
	cam.cull_mask = 1 << int(Config.LAYERS.WORLD)
	_fullColor(cam)
	scene.add_child(cam)
	cam.position = Vector3(0.12, 1.3, 4.5)
	cam.look_at(Vector3(0.04, 1.02, 0), Vector3.UP)
	cam.current = true
	_sets = {"vp": vp, "scene": scene, "lights": lights, "tex": vp.get_texture(), "cam": cam, "env": env, "groups": {}, "heroes": {}, "cur": -1,
		"disco": null, "discoStep": -1, "discoMaps": [], "prebuilt": false, "lastBuild": 0.0, "asset": null}
	return _sets

# Builds the other channels' sets one at a time while the viewer watches a settled channel (no hitch later).
func _prebuild(t: float) -> void:
	var S = _sets
	if S == null or t < 0.9 or S.prebuilt:
		return
	var now: float = game.time.realNow
	if now - S.lastBuild < 0.35:
		return
	var next = null
	for c in CHANNELS:
		if not S.groups.has(c.hero):
			next = c
			break
	if next == null:
		S.prebuilt = true
		return
	S.lastBuild = now
	var grp = _buildSet(next)
	S.groups[next.hero] = grp
	S.scene.add_child(grp)
	grp.visible = false

# Game's progressive boot (behind the title): builds every channel's set (hero, promo card, props) one per frame,
# so the title -> select press and the channel flips no longer build anything. A coroutine: await it.
# (The JS also started the WebGL compile of each set and drew it once, alone: engine plumbing, not ported.)
func preloadSteps() -> void:
	var S := _ensureSets()
	for C in CHANNELS:
		if not S.groups.has(C.hero):
			var grp = _buildSet(C)
			S.groups[C.hero] = grp
			S.scene.add_child(grp)
		await game.frameYield()
		for id in S.groups:
			S.groups[id].visible = false
	S.prebuilt = true

func _showSet(idx: int) -> void:
	var S := _ensureSets()
	var C: Dictionary = CHANNELS[idx]
	if not S.groups.has(C.hero):
		var grp = _buildSet(C)
		S.groups[C.hero] = grp
		S.scene.add_child(grp)
	for id in S.groups:
		S.groups[id].visible = id == C.hero
	S.cur = idx
	(S.env as Environment).background_color = Color(C.bg)
	var L: Array = S.lights.points
	for p in L:
		p.light_energy = 0.0
	L[0].position = Vector3(-1.6, 2.6, -1.0)
	L[0].light_color = Color(C.rim)
	L[0].light_energy = 5.0
	L[0].omni_range = 6.0
	L[1].position = Vector3(1.9, 1.6, 1.6)
	L[1].light_color = Color("#FFD8B0")
	L[1].light_energy = 1.6
	L[1].omni_range = 6.0
	L[2].position = Vector3(0, 3.2, -1.6)
	L[2].light_color = Color(C.glow)
	L[2].light_energy = 3.0
	L[2].omni_range = 5.0
	var h = S.heroes.get(C.hero)
	if h:
		h.poseT = 0.0
		_faceExpr(h, "neutral", 1.0)

func _setAsset() -> Node3D:
	var S := _ensureSets()
	if S.asset == null:
		S.asset = _asset("res://assets/runtime/menu/sets.glb")
	return S.asset

# A node of the sets asset, duplicated (the asset keeps the originals).
func _setPart(name: String) -> Node3D:
	var a := _setAsset()
	if a == null:
		return null
	var n = a.find_child(name, true, false)
	if not (n is Node3D):
		return null
	var d: Node3D = n.duplicate()
	d.transform = (n as Node3D).transform
	_copyUd(n, d)
	return d

func _copyUd(a: Node, b: Node) -> void:
	if a.has_meta("userData"):
		b.set_meta("userData", (a.get_meta("userData") as Dictionary).duplicate(true))
	for i in mini(a.get_child_count(), b.get_child_count()):
		_copyUd(a.get_child(i), b.get_child(i))

func _buildSet(C: Dictionary) -> Node3D:
	var g = game
	var S := _ensureSets()
	var grp := DAU.node3d("set_%s" % C.hero)
	# backdrop: the show's promo art, gently curved like a cyclorama flat (Blender asset set_back, a basic
	# material tinted (0.82, 0.8, 0.86) with the promo_<hero> card, fog off)
	var back := _setPart("set_back_%s" % C.hero)
	if back:
		grp.add_child(back)
	# floor per show
	var floor := _setPart("set_floor_%s" % C.hero)
	if floor:
		grp.add_child(floor)
		if C.hero == "roxy":
			S.disco = _meshMat(_firstMesh(floor))
			_discoMaps(S)
	var put := func(id: String, pos: Array, rotY: float = 0.0, opts: Dictionary = {}):
		var P0 = g.props
		if P0 == null or not P0.has_method("build"):
			return null
		var q = P0.build(id, opts)
		if not (q is Node3D):
			push_warning("[menu] set prop %s" % id)
			return null
		q.position = Vector3(pos[0], pos[1], pos[2])
		q.rotation.y = rotY
		grp.add_child(q)
		return q
	if C.hero == "skip":
		put.call("bc_flight_case_stack", [-1.75, 0, -0.9], 0.35)
		put.call("bc_cable_coil", [1.1, 0, 0.3], -0.4)
	elif C.hero == "roxy":
		var b = put.call("disco_ball", [0.3, 2.35, -0.9], 0.0)
		if b:
			b.scale = Vector3.ONE * 0.7
	elif C.hero == "penny":
		put.call("hut_tubes", [1.75, 0, -0.9], -0.4)
	elif C.hero == "duke":
		put.call("st_hydrant", [1.5, 0, -0.4], -0.5)
		put.call("st_mailbox", [-1.7, 0, -0.8], 0.4)
	# the hero
	var HL = _heroesLib()
	var hero = HL.buildHero(C.hero, g) if HL else null
	if hero is Dictionary and hero.get("group") is Node3D:
		var hg: Node3D = hero.group
		hg.position = Vector3(0, 0, 0.2)
		hg.rotation.y = PI - 0.28
		DAU.traverse(hg, func(o: Node) -> void:
			if o is GeometryInstance3D:
				(o as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				(o as GeometryInstance3D).extra_cull_margin = 16384.0)
		if _unlocked:
			_goldBadge(hero)
		grp.add_child(hg)
		hero.poseT = 0.0
		S.heroes[C.hero] = hero
	else:
		push_warning("[menu] hero %s failed" % C.hero)
	return grp

func _firstMesh(n: Node):
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m = _firstMesh(c)
		if m:
			return m
	return null

func _heroOnSet():
	var S = _sets
	return S.heroes.get(CHANNELS[_chIdx].hero) if S else null

func _faceExpr(h, expr: String, amt: float) -> void:
	var art = h.get("art") if h is Dictionary else null
	var face = art.get("face") if art is Object else (art.get("face") if art is Dictionary else null)
	if face and face.has_method("setExpression"):
		face.setExpression(expr, amt)

func _updateSetScene(dt: float, t: float) -> void:
	var S = _sets
	if S == null:
		return
	var h = S.heroes.get(CHANNELS[_chIdx].hero)
	if h:
		h.poseT = float(h.get("poseT", 0.0)) + dt
		# idle a beat, then snap into the signature pose (overshoot), hold it with a breathing idle
		var pt := clamp_((h.poseT - 0.35) / 0.38, 0.0, 1.0)
		var w := 0.0 if pt <= 0.0 else minf(1.08, easeOutBack(pt, 2.2))
		var an = h.get("animator")
		if an:
			if an.has_method("pose"):
				an.pose("commercial_%s" % CHANNELS[_chIdx].hero, w)
			if an.has_method("update"):
				an.update(dt, {"speed": 0.0, "grounded": true, "aimPitch": 0.0})
			if h.poseT > 0.35 and not h.get("kicked", false):
				h.kicked = true
				if an.has_method("kick"):
					an.kick(0.8)
				_faceExpr(h, "smile", 1.0)
		if h.poseT < 0.1:
			h.kicked = false
		var art = h.get("art")
		var face = art.get("face") if art is Object else (art.get("face") if art is Dictionary else null)
		if face and face.has_method("lookAt"):
			face.lookAt((S.cam as Camera3D).global_position)
	if S.disco and not S.discoMaps.is_empty():
		var step := int(floorf(game.time.realNow * 2.2))
		if step != S.discoStep:
			S.discoStep = step
			S.disco.map = S.discoMaps[step % 4]   # map.offset.x = (step % 4) * 0.25 (repeat 2): pre-shifted copies

# The disco floor's texture offset animation: four copies of the (repeating) texture shifted by 0.25 of its width.
func _discoMaps(S: Dictionary) -> void:
	var m = S.disco
	if m == null or m.get("map") == null:
		return
	var tex: Texture2D = m.map
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var out: Array = []
	for k in 4:
		var sh := Image.create(w, h, false, img.get_format())
		var dx := int(roundf(k * 0.25 * w))
		sh.blit_rect(img, Rect2i(dx, 0, w - dx, h), Vector2i(0, 0))
		if dx > 0:
			sh.blit_rect(img, Rect2i(0, 0, dx, h), Vector2i(w - dx, 0))
		sh.generate_mipmaps()
		var it := ImageTexture.create_from_image(sh)
		it.set_meta("wrap", "repeat")
		for mk in ["flipY", "filter"]:
			if tex.has_meta(mk):
				it.set_meta(mk, tex.get_meta(mk))
		out.append(it)
	S.discoMaps = out

func _goldBadge(hero: Dictionary) -> void:
	var m := _setPart("goldBadge")
	if m == null:
		return
	var parts = hero.get("parts", {})
	var slots = hero.get("slots", {})
	var anchor = parts.get("torso") if parts is Dictionary else null
	if anchor == null and slots is Dictionary:
		anchor = slots.get("neck")
	if not (anchor is Node3D):
		return
	m.position = Vector3(0.08, 0.02, -0.17)
	m.rotation = Vector3(0, PI, 0)
	(anchor as Node3D).add_child(m)

# -------------------------------------------------------------------------------------------- pause
func _pauseItems() -> Array:
	if _mpGame():
		# MP: the world keeps running behind the card; leaving ends our part of the session
		return [
			{"ch": 2, "label": "RESUME", "act": func(): game.resume()},
			{"ch": 4, "label": "OPTIONS", "act": func(): _pauseSub("options")},
			{"ch": 5, "label": "CONTROLS", "act": func(): _pauseSub("controls")},
			{"ch": 7, "label": "LEAVE GAME", "warn": "LEAVE? SURE", "act": func(): _quit()},
		]
	return [
		{"ch": 2, "label": "RESUME", "act": func(): game.resume()},
		{"ch": 4, "label": "OPTIONS", "act": func(): _pauseSub("options")},
		{"ch": 5, "label": "CONTROLS", "act": func(): _pauseSub("controls")},
		{"ch": 7, "label": "QUIT", "act": func(): _quit()},
	]

func _quit() -> void:
	var P := _pause
	if P.quitArm < 0.0:
		P.quitArm = 2.5
		_play("ui_denied", {"vol": 0.5})
		_renderPause()
		return
	_play("ui_menu_clack")
	var inp = game.input
	if inp and inp.has_method("exitLock"):
		inp.exitLock()
	if _mpGame():
		_leaveSession()
		return
	hideAll()
	game.setState("menu")
	showTitle()

func _pauseSub(sub: String) -> void:
	if sub == "main" and mode == "main":
		_front.backFromCard()   # the main menu's Options / Controls card: back to its pills
		return
	var P := _pause
	P.sub = sub
	P.osel = 0
	_play("ui_menu_clack", {"vol": 0.7})
	_renderPause()

func _optRows() -> Array:
	var o: Dictionary = options
	var rows := [
		{"key": "sensitivity", "label": "MOUSE SENSITIVITY", "type": "slider", "min": 0.2, "max": 3.0, "step": 0.05, "fmt": func(v): return String.num(float(v), 2).pad_decimals(2)},
		{"key": "padSens", "label": "PAD SENSITIVITY", "type": "slider", "min": 0.3, "max": 2.5, "step": 0.05, "fmt": func(v): return String.num(float(v), 2).pad_decimals(2)},
		{"key": "invertY", "label": "INVERT Y", "type": "toggle"},
		{"key": "fov", "label": "FIELD OF VIEW", "type": "slider", "min": 60.0, "max": 90.0, "step": 1.0, "fmt": func(v): return "%d°" % int(floorf(float(v) + 0.5))},
		{"key": "aim", "label": "AIM", "type": "seg", "opts": [["hold", "HOLD"], ["toggle", "TOGGLE"]]},
		{"key": "sprint", "label": "SPRINT", "type": "seg", "opts": [["hold", "HOLD"], ["toggle", "TOGGLE"]]},
		{"key": "aimAssist", "label": "PAD AIM ASSIST", "type": "toggle"},
		{"key": "rumble", "label": "PAD VIBRATION", "type": "toggle"},
	]
	for vr in VOL_ROWS:
		rows.append({"key": "vol.%s" % vr[0], "label": vr[1], "type": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": func(v): return "%d" % int(floorf(float(v) * 100.0 + 0.5))})
	rows.append({"key": "quality", "label": "PICTURE QUALITY", "type": "seg", "opts": [["low", "LOW"], ["medium", "MED"], ["high", "HIGH"]]})
	rows.append({"key": "crt", "label": "CRT VIGNETTE", "type": "toggle"})
	rows.append({"key": "back", "label": "◀ BACK", "type": "back"})
	for r in rows:
		r.value = o.vol.get(r.key.substr(4)) if r.key.begins_with("vol.") else o.get(r.key)
	return rows

# The pause card's DOM (JS innerHTML): here the clickable regions; the paint is _drawPause.
func _renderPause() -> void:
	var P := _pause
	_hits.clear()
	if P.sub == "main":
		var items := _pauseItems()
		for i in items.size():
			var y := 250.0 + i * (104.0 + 22.0)
			var x := 1120.0 + (26.0 if i == P.sel else 0.0)
			var ii := i
			_hits.append({"id": "pitem%d" % i, "rect": Rect2(x, y, 640, 104),
				"enter": func(): if ii != _pause.sel:
					_pause.sel = ii
					_tick()
					_renderPause(),
				"click": func():
					_pause.sel = ii
					_pauseItems()[_pause.sel].act.call()})
		_redraw()
		return
	if P.sub == "controls":
		var L := _controlsLayout()
		_hits.append({"id": "back", "rect": L.back, "click": func(): _pauseSub("main")})
		_redraw()
		return
	var rows := _optRows()
	var lay := _optionsLayout(rows)
	for i in rows.size():
		var R: Dictionary = lay.rows[i]
		var ii := i
		var h := {"id": "orow%d" % i, "rect": R.rect, "enter": func(): if _pause.osel != ii:
			_pause.osel = ii
			_highlightRow()}
		if rows[i].type == "back":
			h.click = func(): _pauseSub("main")
		_hits.append(h)
		if R.has("segs"):
			for sg in R.segs:
				var v = sg.v
				_hits.append({"id": "seg%d_%s" % [i, v], "rect": sg.rect, "enter": h.enter, "click": func():
					var rr: Dictionary = _optRows()[ii]
					_setRow(rr, (v == "1") if rr.type == "toggle" else v)})
		if R.has("sld"):
			var srect: Rect2 = R.sld
			_hits.append({"id": "sld%d" % i, "rect": srect, "enter": h.enter, "down": func(pos: Vector2):
				_drag = {"row": ii, "rect": srect}
				_dragTo(pos)})
	_redraw()

func _highlightRow() -> void:
	_redraw()
	_tick()

func _dragTo(clientPos: Vector2) -> void:
	var D = _drag
	if D == null:
		return
	var rect: Rect2 = D.rect
	var sp := _toStage(clientPos)
	var f := clamp_((sp.x - rect.position.x) / maxf(1.0, rect.size.x), 0.0, 1.0)
	var r: Dictionary = _optRows()[D.row]
	var v: float = floorf((r.min + f * (r.max - r.min)) / r.step + 0.5) * r.step
	_setRow(r, clamp_(v, r.min, r.max), true)

func _setRow(r: Dictionary, v, fromDrag: bool = false) -> void:
	var cur = options.vol.get(r.key.substr(4)) if r.key.begins_with("vol.") else options.get(r.key)
	if cur == v or (cur is float and v is float and is_equal_approx(cur, v)):
		return
	setOption(r.key, v)
	if r.type == "slider":
		var now := DAU.nowMs()
		if now - _sldSnd > 70.0:
			_sldSnd = now
			_play("ui_points_flip", {"vol": 0.5})
	else:
		_play("ui_prompt")
	# refresh this card (the drag keeps its row)
	var P := _pause
	var keep: int = P.osel
	if fromDrag and _drag:
		_redraw()
		return
	_renderPause()
	P.osel = keep

func _pauseKey(e: Dictionary) -> void:
	var P := _pause
	var c: String = e.code
	var up := c == "KeyW" or c == "ArrowUp"
	var down := c == "KeyS" or c == "ArrowDown"
	var left := c == "KeyA" or c == "ArrowLeft"
	var right := c == "KeyD" or c == "ArrowRight"
	var ok := c == "Enter" or c == "KeyE" or c == "Space" or c == "NumpadEnter"
	if c == "Escape":
		# Esc backs out of a sub-card; on the main card it resumes (Input would too; we own it here)
		e.stop = true
		if P.sub != "main":
			_pauseSub("main")
		else:
			game.resume()
		return
	if P.sub == "main":
		var n := _pauseItems().size()
		if up or down:
			P.sel = (P.sel + (-1 if up else 1) + n) % n
			_tick()
			_renderPause()
		elif ok:
			_pauseItems()[P.sel].act.call()
		return
	if P.sub == "controls":
		if ok:
			_pauseSub("main")
		return
	var rows := _optRows()
	if up or down:
		P.osel = (P.osel + (-1 if up else 1) + rows.size()) % rows.size()
		_highlightRow()
		return
	if P.osel < 0 or P.osel >= rows.size():
		return
	var r: Dictionary = rows[P.osel]
	if r.type == "back":
		if ok:
			_pauseSub("main")
		return
	if r.type == "slider" and (left or right):
		var stepv: float = r.step * (4.0 if e.shiftKey else 1.0)
		_setRow(r, clamp_(floorf((float(r.value) + (stepv if right else -stepv)) / r.step + 0.5) * r.step, r.min, r.max))
	elif r.type == "toggle" and (left or right or ok):
		_setRow(r, not bool(r.value))
	elif r.type == "seg" and (left or right or ok):
		var i := -1
		for j in r.opts.size():
			if r.opts[j][0] == r.value:
				i = j
		var n2: int = r.opts.size()
		_setRow(r, r.opts[(i + (-1 if left else 1) + n2) % n2][0])

func _tick() -> void:
	_play("ui_prompt", {"vol": 0.6})

func _updatePause(dt: float) -> void:
	var P := _pause
	if P.quitArm > 0.0:
		P.quitArm -= dt
		if P.quitArm <= 0.0:
			P.quitArm = -1.0
			_renderPause()
	# sleepy Telly breathes on the stand-by card (~8 fps redraw)
	_cardT += dt
	if _cardT > 0.125:
		_cardT = 0.0
		_drawCard(_pauseCanvas, "stand_by", game.time.realNow)

func _drawCard(cv, id: String, time: float, sleepy: bool = true, opts: Dictionary = {}) -> void:
	if cv == null:
		return
	var x = cv.getContext("2d")
	var o := opts.duplicate()
	if not sleepy:
		o["variant"] = "awake"
	if _cardsCall("ids", []) != null:
		_cardsCall("drawTo", [x, id, cv.width, cv.height, time, o])
	else:
		x.fillStyle = "#1E1830"
		x.fillRect(0, 0, cv.width, cv.height)
		x.font = "80px " + FontsScript.FONTS.logo
		x.textAlign = "center"
		x.fillStyle = "#FFE9B8"
		x.fillText("Please Stand By", cv.width / 2.0, cv.height / 2.0)
	if cv.has_method("redraw"):
		cv.redraw()

# -------------------------------------------------------------------------------------------- game over
func _updateOver(dt: float) -> void:
	var O = _over
	var g = game
	var post = g.render.get("post") if g.render else null
	if O == null:
		return
	var t := _t
	if O.phase == "static":
		# SIGNAL LOST: the picture tears into static and rolls, then collapses
		var ks := clamp_(t / 0.45, 0.0, 1.0)
		if post is Dictionary:
			post.static = ks * 0.9
			post.roll = ks * 0.35
			post.saturation = 1.0 - ks * 0.6
			post.whiteout = 0.0
		if t >= 0.45:
			O.phase = "lcollapse"
	elif O.phase == "lcollapse":
		var kc := clamp_((t - 0.45) / 0.5, 0.0, 1.0)
		if post is Dictionary:
			post.collapse = easeIn(kc) * 0.55 + kc * 0.45
			post.static = 0.9 * (1.0 - kc)
			post.roll = 0.35 * (1.0 - kc)
		if kc >= 1.0:
			O.phase = "black"
			if post is Dictionary:
				post.collapse = 1.0
			_css.bg.on = true
			_css.bg.black = true
	elif O.phase == "drain":
		# the picture drains and the vertical hold slips while the tape stops
		var k := clamp_(t / GAMEOVER.drain, 0.0, 1.0)
		if post is Dictionary:
			post.saturation = 1.0 - k * 0.85
			post.roll = k * 0.22
			post.static = k * 0.045
			post.damage = maxf(0.0, float(post.get("damage", 0.0)) * 0.95)
			post.whiteout = 0.0
		if t >= GAMEOVER.drain:
			O.phase = "collapse"
	elif O.phase == "collapse":
		var k2 := clamp_((t - GAMEOVER.drain) / GAMEOVER.collapse, 0.0, 1.0)
		if post is Dictionary:
			post.collapse = easeIn(k2) * 0.55 + k2 * 0.45
			post.roll = 0.22 * (1.0 - k2)
			post.static = 0.045 * (1.0 - k2)
		if k2 >= 1.0:
			O.phase = "black"
			if post is Dictionary:
				post.collapse = 1.0
			_css.bg.on = true
			_css.bg.black = true
	elif O.phase == "black":
		if t >= (1.5 if O.get("lost") else GAMEOVER.card):
			_showOverCard()
			_t = 0.0
	elif O.phase == "card":
		_board.update(dt)
		_cardT += dt
		if O.get("lost"):
			if _cardT > 0.05:
				_cardT = 0.0
				_drawLostCard(_overCanvas, g.time.realNow)
			if _t > 1.0 and not _css.anykey.on:
				_css.anykey.on = true
				_css.anykey.t = 0.0
			return
		if _cardT > 0.125:
			_cardT = 0.0
			_drawCard(_overCanvas, "stand_by", g.time.realNow, not O.results)
		if _t > GAMEOVER.lock and not _css.anykey.on:
			_css.anykey.on = true
			_css.anykey.t = 0.0
		# count kills/points up
		var k3 := clamp_((_t - 0.35) / 1.1, 0.0, 1.0)
		var e := easeOut(k3)
		_css.sk = str(int(floorf(O.summary.kills * e + 0.5)))
		_css.sp = _thousands(int(floorf(O.summary.points * e + 0.5)))

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

func _showOverCard() -> void:
	var O = _over
	O.phase = "card"
	_resetPost()
	var post = game.render.get("post") if game.render else null
	if post is Dictionary:
		post.collapse = 1.0 # keep the world hidden behind the card (the next screen resets it)
	_css.bg.on = true
	_css.bg.black = false
	pn.over.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_css.anykey.on = false
	_css.anykey.text = _anyText()
	_css.ovHdr = str(O.title) if O.title else ""
	_css.sk = "0"
	_css.sp = "0"
	(dom.board as Control).visible = not O.get("lost", false)
	if O.get("mp") and not O.results:
		_mpEndGame("gameover")   # MP game over: the host takes the session back to the lobby behind the card
	if O.get("lost"):
		_drawLostCard(_overCanvas, game.time.realNow)
		_redraw()
		return
	_drawCard(_overCanvas, "stand_by", 0.0, not O.results)
	var r := int(clamp_(float(O.summary.round), 0.0, 999.0))
	var n := 3 if r > 99 else 2
	if _board.cards.size() != n:
		for c in _board.cards:
			(c.el as Node).queue_free()
		_board = HudScript.FlipBoard.new(dom.board, n, {"cls": "board", "speed": 0.55, "onFlip": func(_i): _flipSound()})
	_board.set_("0".repeat(n), true)
	_board.set_(str(r).lpad(n, "0"))
	_redraw()

func _flipSound() -> void:
	var now := DAU.nowMs()
	if now - _flipAt < 45.0:
		return
	_flipAt = now
	_play("ui_points_flip", {"vol": 0.7})

# ================================================================================================ painting (CSS)
# A CSS box texture (HudScript.cssBoxSvg) cached per key and rasterizing density.
func _box(key: String, w: float, h: float, spec: Dictionary) -> Array:
	var k := "%s|%s|%s" % [key, w, h]
	if _tex.has(k):
		return _tex[k]
	var r := HudScript.cssBoxSvg(w, h, spec)
	var out := [HudScript.svgTexture(r[0]), float(r[1])]
	_tex[k] = out
	return out

func _paintBox(ci: CanvasItem, key: String, x: float, y: float, w: float, h: float, spec: Dictionary, alpha: float = 1.0) -> void:
	var b := _box(key, w, h, spec)
	if b[0]:
		var pad: float = b[1]
		ci.draw_texture_rect(b[0], Rect2(x - pad, y - pad, w + pad * 2.0, h + pad * 2.0), false, Color(1, 1, 1, alpha))

func _svgTex(key: String, fn: Callable) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var t: Texture2D = fn.call()
	_tex[key] = t
	return t

func _lh(f: Font, size: float) -> float:
	return f.get_height(int(size))

func _txt(ci: CanvasItem, fk: String, size: float, x: float, cy: float, s: String, col, ls: float = 0.0, shadows: Array = [], alpha: float = 1.0) -> void:
	var f: Font = _fonts[fk]
	var c: Color = col if col is Color else DAU.color(col)
	c.a *= alpha
	var sh: Array = []
	for s0 in shadows:
		var sc: Color = DAU.color(s0[3]) if not (s0[3] is Color) else s0[3]
		sh.append([s0[0], s0[1], s0[2], Color(sc.r, sc.g, sc.b, sc.a * alpha)])
	HudScript.drawText(ci, f, x, HudScript.baselineAt(f, size, cy), s, size, c, ls, sh)

func _tw(fk: String, size: float, s: String, ls: float = 0.0) -> float:
	return HudScript.textWidth(_fonts[fk], s, size, ls)

# @keyframes mnpress (1.6s ease-in-out infinite): 0%,100% { opacity 1 } 55% { opacity .18 }
static func _mnpress(t: float) -> float:
	return HudScript.keyframe2(t / 1.6, 1.0, 0.18, 0.55, func(x): return HudScript.cssEaseInOut(x))

# ---- title
func _drawTitle(ci: Control) -> void:
	# .pn-title::before: the bottom 300 px darken
	var g := _svgTex("titleGrad", func(): return HudScript.svgTexture(HudScript.svgDoc(0, 0, REF_W, 300, '<rect width="%s" height="300" fill="url(#g)"/>' % REF_W,
		HudScript.linGrad("g", 0, 0, REF_W, 300, 0, [["rgba(12,6,20,.62)", 0.0], ["rgba(12,6,20,0)", 1.0]]))))
	if g:
		ci.draw_texture_rect(g, Rect2(0, REF_H - 300, REF_W, 300), false)
	# .press (bottom 92, 40px, letter-spacing .28em)
	var P: Dictionary = _css.press
	if P.on:
		var a := _mnpress(P.t)
		var lh := _lh(_fonts.hud, 40)
		var ls := 40.0 * 0.28
		var tw := _tw("hud", 40, P.text, ls)
		_txt(ci, "hud", 40, (REF_W - tw) / 2.0, REF_H - 92 - lh / 2.0, P.text, "#FFF4DC", ls,
			[[0.0, 3.0, 0.0, "#5A2210"], [0.0, 0.0, 18.0, "rgba(255,170,90,.55)"]], a)
	# .ldbar (280 x 4 at bottom 66) + its bar (scaleX = loadProgress)
	var B: Dictionary = _css.ldbar
	if B.on.v > 0.001:
		var x0 := REF_W / 2.0 - 140.0
		var y0 := REF_H - 66.0 - 4.0
		_paintBox(ci, "ldbar", x0, y0, 280, 4, {"r": 2, "bg": "rgba(255,244,220,.13)", "shadows": [[0, 2, 0, 0, "rgba(90,34,16,.55)"]]}, B.on.v)
		var w := 280.0 * clampf(B.scale.v, 0.0, 1.0)
		if w > 0.5:
			var bw := 280.0
			var b := _box("ldbarI", bw, 4, {"r": 2, "bg": "#FFF4DC", "shadows": [[0, 0, 12, 0, "rgba(255,170,90,.6)"]]})
			if b[0]:
				var pad: float = b[1]
				# transform-origin 0 50%: scale the whole painted bar (glow included) along x
				ci.draw_set_transform(Vector2(x0, y0), 0.0, Vector2(w / bw, 1.0))
				ci.draw_texture_rect(b[0], Rect2(-pad, -pad, bw + pad * 2.0, 4 + pad * 2.0), false, Color(1, 1, 1, B.on.v))
				ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ---- select
func _selbarLayout() -> Dictionary:
	var pad := _padMode()
	var ls := 36.0 * 0.08
	# CHANNEL [E] TUNE IN; the MP lobby swaps the words (TAKEN BY <NAME>, START THE SHOW, ...)
	var D: Dictionary = _lobby.dymo() if _lobby != null else {"w1": "CHANNEL", "kc": "A" if pad else "E", "w2": "TUNE IN"}
	var t1: String = D.w1
	var t2: String = D.w2
	var kcText: String = D.kc
	var kcPad: bool = pad and kcText.length() == 1   # a round Xbox button (a key name like ESC stays a key cap)
	var kcW := 0.0 if kcText == "" else (46.0 if kcPad else maxf(46.0, 16.0 + _tw("hud", 28, kcText, ls)))
	var w1 := _tw("hud", 36, t1, ls)
	var w2 := _tw("hud", 36, t2, ls)
	var dw: float
	if t1 != "" and kcText != "" and t2 != "":
		dw = ceilf(20.0 + w1 + 16.0 + kcW + 16.0 + w2 + 30.0)
	else:
		var sum := 0.0
		var nparts := 0
		for pw in [w1 if t1 != "" else -1.0, kcW if kcText != "" else -1.0, w2 if t2 != "" else -1.0]:
			if pw >= 0.0:
				sum += pw
				nparts += 1
		dw = ceilf(20.0 + sum + 16.0 * maxf(0.0, nparts - 1.0) + 30.0)
	var total := 84.0 + 26.0 + dw + 26.0 + 84.0
	var x0 := (REF_W - total) / 2.0
	var y0 := REF_H - 44.0 - 84.0
	return {"arrowL": Rect2(x0, y0, 84, 84), "dymo": Rect2(x0 + 84 + 26, y0 + 10, dw, 64), "arrowR": Rect2(x0 + 84 + 26 + dw + 26, y0, 84, 84),
		"kcW": kcW, "kcText": kcText, "w1": w1, "w2": w2, "ls": ls, "pad": pad, "t1": t1, "t2": t2, "kcPad": kcPad,
		"kcCol": XB_COL.get(kcText.to_lower(), "#7EDB5A") if kcPad else "#F2F0EA"}

func _selectHits() -> void:
	var L := _selbarLayout()
	_hits.append({"id": "arrowL", "rect": L.arrowL, "click": func(): tune(-1)})
	_hits.append({"id": "arrowR", "rect": L.arrowR, "click": func(): tune(1)})
	_hits.append({"id": "dymo", "rect": L.dymo, "click": func(): tuneIn()})

func _drawSelect(ci: Control) -> void:
	# .selttl "Who's on tonight?" (top 46, Shrikhand 58, rotate(-2deg))
	var a1: float = _css.selttl.on.v
	if a1 > 0.001:
		var lh := _lh(_fonts.logo, 58)
		var cy := 46.0 + lh / 2.0
		var s := "Who's on tonight?"
		var tw := _tw("logo", 58, s)
		ci.draw_set_transform(Vector2(REF_W / 2.0, cy), deg_to_rad(-2.0), Vector2.ONE)
		_txt(ci, "logo", 58, -tw / 2.0, 0.0, s, "#FFE9B8", 0.0, [[0.0, 4.0, 0.0, "#8A2E14"], [0.0, 8.0, 16.0, "rgba(0,0,0,.5)"]], a1)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var a2: float = _css.selbar.on.v
	if a2 <= 0.001:
		return
	var L := _selbarLayout()
	for side in ["arrowL", "arrowR"]:
		var r: Rect2 = L[side]
		var sc: float = _css[side].s.v
		ci.draw_set_transform(r.get_center(), 0.0, Vector2(sc, sc))
		_paintBox(ci, "arrow", -42, -42, 84, 84, {"r": 42, "bg": {"rad": [0.4, 0.32], "stops": [["#8A5A36", 0.0], ["#5A3A22", 0.6], ["#3A2414", 1.0]]},
			"shadows": [[0, 0, 0, 4, "#E8A92E"], [0, 6, 14, 0, "rgba(0,0,0,.5)"]], "insets": [[0, 3, 0, 0, "rgba(255,220,170,.25)"]]}, a2)
		var dirn := -1 if side == "arrowL" else 1
		var at := _svgTex("arrowSvg%d" % dirn, func(): return HudScript.svgTexture(HudScript.svgDoc(0, 0, 40, 40,
			'<path d="%s" fill="#FFE9B8" stroke="#3A1E0E" stroke-width="3" stroke-linejoin="round"/>' % ("M27 6L9 20l18 14z" if dirn < 0 else "M13 6l18 14-18 14z"))))
		if at:
			ci.draw_texture_rect(at, Rect2(-20, -20, 40, 40), false, Color(1, 1, 1, a2))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	# .dymo (rotate(-1.5deg); .go: mnthump .28s, 40% { scale(1.12) })
	var d: Rect2 = L.dymo
	var th := 1.0
	if _css.dymo.go >= 0.0:
		var p: float = _css.dymo.go / 0.28
		th = lerpf(1.0, 1.12, HudScript.cubicBezier(0.3, 1.8, 0.5, 1.0, p / 0.4)) if p < 0.4 else lerpf(1.12, 1.0, HudScript.cubicBezier(0.3, 1.8, 0.5, 1.0, (p - 0.4) / 0.6))
	var shake := 0.0
	if _lobby != null and _lobby.deny > 0.0:
		shake = sin(_lobby.deny * 70.0) * 7.0 * (_lobby.deny / 0.3)   # MP: a denied tune-in rattles the label
	ci.draw_set_transform(d.get_center() + Vector2(shake, 0.0), deg_to_rad(-1.5), Vector2(th, th))
	var dw := d.size.x
	var dt := _svgTex("dymo%d" % int(dw), func(): return HudScript.svgTexture(_dymoSvg(dw, 64.0)))
	if dt:
		ci.draw_texture_rect(dt, Rect2(-dw / 2.0 - 14, -32 - 10, dw + 28, 64 + 30), false, Color(1, 1, 1, a2))
	var emb := [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 1.0, 0.0, "rgba(255,255,255,.35)"], [0.0, 2.0, 3.0, "rgba(0,0,0,.5)"]]
	var x := -dw / 2.0 + 20.0
	if L.t1 != "":
		_txt(ci, "hud", 36, x, 0.0, L.t1, "#F2F0EA", L.ls, emb, a2)
		x += L.w1 + 16.0
	if L.kcText != "":
		var kw: float = L.kcW
		var kp: bool = L.kcPad
		var kt := _svgTex("dymoKc%s%d" % [kp, int(kw)], func(): return HudScript.svgTexture(HudScript.cssBoxSvg(kw, 46, {"r": 23 if kp else 10,
			"bg": {"rad": [0.42, 0.34], "stops": [["#34343C", 0.0], ["#18181D", 0.7]]} if kp else null,
			"insets": [[0, 0, 0, 3, "rgba(242,240,234,.9)"], [0, 3, 0, 3, "rgba(0,0,0,.35)"]]})[0]))
		if kt:
			ci.draw_texture_rect(kt, Rect2(x - 2, -23 - 2, kw + 4, 46 + 4), false, Color(1, 1, 1, a2))
		var ktw := _tw("hud", 28, L.kcText, L.ls)
		_txt(ci, "hud", 28, x + (kw - ktw) / 2.0, 0.0, L.kcText, L.kcCol, L.ls, emb, a2)
		x += kw + 16.0
	if L.t2 != "":
		_txt(ci, "hud", 36, x, 0.0, L.t2, "#F2F0EA", L.ls, emb, a2)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

func _dymoSvg(w: float, h: float) -> String:
	# .mn .dymo clip-path polygon, gradient, filter drop-shadow(0 5px 6px rgba(0,0,0,.45))
	var pts := [[0, 8], [1, 0], [99, 0], [100, 9], [99.3, 22], [100, 36], [99.3, 50], [100, 64], [99.3, 78], [100, 91], [99, 100], [1, 100], [0, 92], [0.7, 78], [0, 64], [0.7, 50], [0, 36], [0.7, 22]]
	var d := "M"
	for i in pts.size():
		d += "%s %s%s" % [HudScript.n_(pts[i][0] / 100.0 * w), HudScript.n_(pts[i][1] / 100.0 * h), "L" if i < pts.size() - 1 else "Z"]
	var defs := HudScript.linGrad("g", 0, 0, w, h, 180, [["#3A3A40", 0.0], ["#1C1C21", 0.16], ["#121216", 0.55], ["#1E1E24", 0.88], ["#34343C", 1.0]])
	defs += HudScript.blurFilter("sh", 6.0)
	var body := '<path d="%s" fill="#000" fill-opacity=".45" transform="translate(0 5)" filter="url(#sh)"/>' % d
	body += '<path d="%s" fill="url(#g)"/>' % d
	return HudScript.svgDoc(-14, -10, w + 28, h + 30, body, defs)

# ---- the TV boxes (.tvbox: walnut cabinet, cream-rimmed screen, knob column)
func _tvboxSpec(W: float, H: float, knob2: float) -> Dictionary:
	var extra := ""
	var defs := ""
	# ::before: repeating-linear-gradient(88deg, rgba(255,220,170,.06) 0 3px, transparent 3px 11px, rgba(40,16,4,.08) 11px 14px, transparent 14px 23px), opacity .5
	var a := deg_to_rad(88.0)
	var dir := Vector2(sin(a), -cos(a))
	var L := absf(W * sin(a)) + absf(H * cos(a))
	var c := Vector2(W / 2.0, H / 2.0)
	var start := c - dir * L / 2.0
	var nrm := Vector2(-dir.y, dir.x) * 2000.0
	var grain := ""
	var k := 0.0
	while k < L:
		for band in [[0.0, 3.0, "#FFDCAA", 0.06], [11.0, 14.0, "#281004", 0.08]]:
			var p0: Vector2 = start + dir * (k + float(band[0]))
			var p1: Vector2 = start + dir * (k + float(band[1]))
			grain += '<path d="M%s %sL%s %sL%s %sL%s %sZ" fill="%s" fill-opacity="%s"/>' % [HudScript.n_(p0.x - nrm.x), HudScript.n_(p0.y - nrm.y), HudScript.n_(p0.x + nrm.x), HudScript.n_(p0.y + nrm.y),
				HudScript.n_(p1.x + nrm.x), HudScript.n_(p1.y + nrm.y), HudScript.n_(p1.x - nrm.x), HudScript.n_(p1.y - nrm.y), band[2], HudScript.n_(band[3])]
		k += 23.0
	extra += '<g clip-path="url(#bx)" opacity=".5">%s</g>' % grain
	# .scr rings (0 0 0 6px #F3E3C0 over 0 0 0 9px #C8963C) + #0A0810 face (the canvas covers it)
	var sw := W - 34.0 - 170.0
	var sh := H - 68.0
	extra += '<path d="%s" fill="#C8963C"/>' % HudScript.rrd(34 - 9, 34 - 9, sw + 18, sh + 18, 39)
	extra += '<path d="%s" fill="#F3E3C0"/>' % HudScript.rrd(34 - 6, 34 - 6, sw + 12, sh + 12, 36)
	extra += '<path d="%s" fill="#0A0810"/>' % HudScript.rrd(34, 34, sw, sh, 30)
	# .knobs column
	var kx := W - 34.0 - 110.0
	var ky := 40.0
	var kh := H - 80.0
	var kd := HudScript.rrd(kx, ky, 110, kh, 24)
	defs += HudScript.linGrad("kg", kx, ky, 110, kh, 180, [["#F3E3C0", 0.0], ["#E0C898", 1.0]]) + HudScript.clipDef("kc", kd)
	extra += '<path d="%s" fill="url(#kg)"/>' % kd
	var tmp: Array = []
	extra += HudScript.insetShadow(tmp, "ki1", "kc", kx, ky, 110, kh, 24, 0, -4, 0, 0, "rgba(0,0,0,.12)")
	extra += HudScript.insetShadow(tmp, "ki2", "kc", kx, ky, 110, kh, 24, 0, 0, 0, 3, "#C8963C")
	defs += "".join(tmp)
	# justify-content: space-around over knob (74), knob (74), grille (80), pilot (16)
	var items := [74.0, 74.0, 80.0, 16.0]
	var free := kh - 244.0
	var gap := free / 4.0
	var y := ky + gap / 2.0
	var cx := kx + 55.0
	for i in items.size():
		var s: float = items[i]
		var cy := y + s / 2.0
		if i < 2:
			extra += _knobSvgFrag(cx, cy, 0.0 if i == 0 else knob2, "k%d" % i)
			defs += HudScript.blurFilter("k%ds" % i, 8.0)
		elif i == 2:
			# .grille: repeating-radial-gradient(circle, #C8963C 0 3px, #8A6428 3px 7px), 0 0 0 4px #C8963C
			extra += '<circle cx="%s" cy="%s" r="44" fill="#C8963C"/>' % [HudScript.n_(cx), HudScript.n_(cy)]
			var rr := 40.0
			var ring := ""
			var base := floorf(40.0 / 7.0) * 7.0
			ring += '<circle cx="%s" cy="%s" r="40" fill="#8A6428"/>' % [HudScript.n_(cx), HudScript.n_(cy)]
			var q := base + 7.0
			while q > 0.0:
				# band [q-7, q-4) dark, [q-7 ... ] the repeating period starts at 0: gold 0..3, dark 3..7
				ring += '<circle cx="%s" cy="%s" r="%s" fill="#8A6428"/>' % [HudScript.n_(cx), HudScript.n_(cy), HudScript.n_(minf(rr, q))]
				ring += '<circle cx="%s" cy="%s" r="%s" fill="#C8963C"/>' % [HudScript.n_(cx), HudScript.n_(cy), HudScript.n_(minf(rr, q - 4.0))]
				q -= 7.0
			extra += ring
		else:
			# .pilot: #FF3B30, box-shadow 0 0 12px 3px rgba(255,60,40,.8)
			defs += HudScript.blurFilter("pg", 12.0)
			extra += '<circle cx="%s" cy="%s" r="11" fill="#FF3C28" fill-opacity=".8" filter="url(#pg)"/>' % [HudScript.n_(cx), HudScript.n_(cy)]
			extra += '<circle cx="%s" cy="%s" r="8" fill="#FF3B30"/>' % [HudScript.n_(cx), HudScript.n_(cy)]
		y += s + gap
	return {"r": 46, "bg": {"lin": 135, "stops": [["#8A5530", 0.0], ["#6A3C20", 0.4], ["#4E2A14", 1.0]]},
		"shadows": [[0, 0, 0, 5, "#2E1A0C"], [0, 26, 50, 0, "rgba(0,0,0,.6)"]],
		"insets": [[0, 4, 0, 0, "rgba(255,210,160,.22)"], [0, -6, 0, 0, "rgba(0,0,0,.35)"]], "extra": extra, "extraDefs": defs}

# .knob: 74 px, repeating-conic-gradient(#5A3420 0 12deg, #3E2414 12deg 24deg), 0 5px 8px rgba(0,0,0,.4),
# inset 0 0 0 7px rgba(0,0,0,.15), ::after pointer 8x22 at top 6 (#F3E3C0, r 4); rotate(deg) with its shadow.
func _knobSvgFrag(cx: float, cy: float, deg: float, id: String) -> String:
	var s := '<g transform="rotate(%s %s %s)">' % [HudScript.n_(deg), HudScript.n_(cx), HudScript.n_(cy)]
	s += '<circle cx="%s" cy="%s" r="37" fill="#000" fill-opacity=".4" filter="url(#%ss)"/>' % [HudScript.n_(cx), HudScript.n_(cy + 5), id]
	for i in 30:
		var a0 := deg_to_rad(i * 12.0)
		var a1 := deg_to_rad((i + 1) * 12.0)
		var p0 := Vector2(cx + sin(a0) * 37.0, cy - cos(a0) * 37.0)
		var p1 := Vector2(cx + sin(a1) * 37.0, cy - cos(a1) * 37.0)
		s += '<path d="M%s %sL%s %sA37 37 0 0 1 %s %sZ" fill="%s"/>' % [HudScript.n_(cx), HudScript.n_(cy), HudScript.n_(p0.x), HudScript.n_(p0.y), HudScript.n_(p1.x), HudScript.n_(p1.y), "#5A3420" if i % 2 == 0 else "#3E2414"]
	s += '<circle cx="%s" cy="%s" r="33.5" fill="none" stroke="#000" stroke-opacity=".15" stroke-width="7"/>' % [HudScript.n_(cx), HudScript.n_(cy)]
	s += '<path d="%s" fill="#F3E3C0"/>' % HudScript.rrd(cx - 4, cy - 37 + 6, 8, 22, 4)
	return s + "</g>"

# .scr::after: radial-gradient(ellipse at 30% 18%, rgba(255,255,255,.2), transparent 40%), scanlines rgba(0,0,0,.12)
# 0 2px / 4px, box-shadow inset 0 0 70px rgba(10,4,20,.65) — over the canvas.
func _scrOverlaySpec(sw: float, sh: float) -> Dictionary:
	var lines := ""
	var y := sh
	while y > 0.0:
		lines += '<rect x="0" y="%s" width="%s" height="2" fill="#000" fill-opacity=".12"/>' % [HudScript.n_(y - 2.0), HudScript.n_(sw)]
		y -= 4.0
	return {"r": 30, "bg": {"rad": [0.3, 0.18], "shape": "ellipse", "stops": [["rgba(255,255,255,.2)", 0.0], ["transparent", 0.4]]},
		"insets": [[0, 0, 70, 0, "rgba(10,4,20,.65)"]], "extra": '<g clip-path="url(#bx)">%s</g>' % lines}

func _drawTvbox(ci: Control, key: String, x: float, y: float, sw: float, sh: float, knob2: float, cv) -> void:
	var W := 34.0 + sw + 170.0
	var H := 34.0 + sh + 34.0
	var b := _box(key, W, H, _tvboxSpec(W, H, knob2))
	if b[0]:
		var pad: float = b[1]
		ci.draw_texture_rect(b[0], Rect2(x - pad, y - pad, W + pad * 2.0, H + pad * 2.0), false)
	# the canvas (display block, 100% of the rounded .scr, overflow hidden)
	if cv != null and cv.texture != null:
		_roundTex(ci, cv.texture, Rect2(x + 34, y + 34, sw, sh), 30.0)
	_paintBox(ci, key + "Scr", x + 34, y + 34, sw, sh, _scrOverlaySpec(sw, sh))

# A texture drawn into a rounded rect (overflow: hidden; border-radius).
static func _roundTex(ci: CanvasItem, tex: Texture2D, r: Rect2, rad: float) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI, 1.5 * PI], [Vector2(r.end.x - rad, r.position.y + rad), 1.5 * PI, 2.0 * PI],
		[r.end - Vector2(rad, rad), 0.0, 0.5 * PI], [Vector2(r.position.x + rad, r.end.y - rad), 0.5 * PI, PI]]
	for c in corners:
		for i in 9:
			var a: float = lerpf(c[1], c[2], i / 8.0)
			var p: Vector2 = c[0] + Vector2(cos(a), sin(a)) * rad
			pts.append(p)
			uvs.append((p - r.position) / r.size)
	ci.draw_colored_polygon(pts, Color.WHITE, uvs, tex)

# ---- pause
func _drawPause(ci: Control) -> void:
	_drawTvbox(ci, "tvPause", 130, 215, 640, 480, 130.0, _pauseCanvas)
	var P := _pause
	if P.sub == "main":
		var items := _pauseItems()
		for i in items.size():
			var it: Dictionary = items[i]
			var quit: bool = (it.label == "QUIT" or it.label == "LEAVE GAME") and P.quitArm > 0.0
			_drawPill(ci, 1120.0, 250.0 + i * (104.0 + 22.0), str(it.ch), it.get("warn", "QUIT? SURE") if quit else it.label, i == P.sel, quit)
		return
	if P.sub == "controls":
		_drawControls(ci)
		return
	_drawOptions(ci)

# One walnut channel pill (.pitem) at its resting top-left (x, y), 640 x 104: the channel badge (.chn) and the label.
# sel: highlighted (orange, translateX(26px) rotate(-1deg)); warn: armed (red). alpha: the main menu's slide-in.
func _drawPill(ci: Control, x: float, y: float, ch: String, label: String, sel: bool, warn: bool, alpha: float = 1.0) -> void:
	var bg: Dictionary = {"lin": 180, "stops": [["rgba(90,58,34,.92)", 0.0], ["rgba(58,34,20,.92)", 1.0]]}
	if sel:
		bg = {"lin": 180, "stops": [["#F59A48", 0.0], ["#D9602B", 0.55], ["#A8401E", 1.0]]}
	if warn:
		bg = {"lin": 180, "stops": [["#E8483A", 0.0], ["#A82018", 1.0]]}
	# .pitem.sel: translateX(26px) rotate(-1deg) (origin: centre)
	var cx := x + 320.0 + (26.0 if sel else 0.0)
	var cy := y + 52.0
	ci.draw_set_transform(Vector2(cx, cy), deg_to_rad(-1.0) if sel else 0.0, Vector2.ONE)
	_paintBox(ci, "pitem%s%s" % [sel, warn], -320, -52, 640, 104, {"r": 52, "bg": bg,
		"shadows": [[0, 0, 0, 4, "#2E1A0C"], [0, 8, 16, 0, "rgba(0,0,0,.45)"]], "insets": [[0, 3, 0, 0, "rgba(255,210,160,.18)"]]}, alpha)
	# .chn 76x76 at padding-left 18
	var chIns: Array = [[0, 0, 0, 7, "#E23B3B"]]
	var chSh: Array = [[0, 3, 0, 0, "rgba(0,0,0,.35)"]]
	if sel:
		chSh = [[0, 0, 18, 4, "rgba(255,210,90,.75)"]]
	_paintBox(ci, "chn%s" % sel, -320 + 18, -38, 76, 76, {"r": 38, "bg": "#F4F1E8", "insets": chIns, "shadows": chSh}, alpha)
	_txt(ci, "hud", 40, -320 + 18 + 38 - _tw("hud", 40, ch) / 2.0, 0.0, ch, "#2F5BD3", 0.0, [], alpha)
	var col := "#FFFBEA" if (sel or warn) else "#F6E7C8"
	var shc := "#6A2410" if sel else "#2A140A"
	_txt(ci, "hud", 50, -320 + 18 + 76 + 22, 0.0, label, col, 50.0 * 0.08, [[0.0, 3.0, 0.0, shc]], alpha)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# .gpanel (left 1000, top 110, width 820, padding 24 34 26) and its h2 (Shrikhand 52 + the blue tag).
func _gpanel(ci: Control, h: float, title: String, tag: String) -> float:
	_paintBox(ci, "gpanel%d" % int(h), 1000, 110, 820, h, {"r": 36, "bg": {"lin": 180, "stops": [["#F6E7C8", 0.0], ["#EAD3A4", 1.0]]},
		"shadows": [[0, 0, 0, 6, "#5A3A22"], [0, 0, 0, 10, "#E8A92E"], [0, 24, 48, 0, "rgba(0,0,0,.55)"]]})
	var lh := _lh(_fonts.logo, 52)
	var cy := 110.0 + 24.0 + lh / 2.0
	var x := 1000.0 + 34.0
	_txt(ci, "logo", 52, x, cy, title, "#B5472A", 0.0, [[0.0, 3.0, 0.0, "rgba(90,40,20,.25)"]])
	x += _tw("logo", 52, title) + 18.0
	var tls := 18.0 * 0.12
	var tw := _tw("sign", 18, tag, tls) + 24.0
	var th := _lh(_fonts.sign, 18) + 12.0
	ci.draw_set_transform(Vector2(x + tw / 2.0, cy), deg_to_rad(-3.0), Vector2.ONE)
	_paintBox(ci, "tag%d" % int(tw), -tw / 2.0, -th / 2.0, tw, th, {"r": 8, "bg": "#2F5BD3"})
	_txt(ci, "sign", 18, -tw / 2.0 + 12.0, 0.0, tag, "#F6E7C8", tls)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return 110.0 + 24.0 + lh + 14.0

func _optionsLayout(rows: Array) -> Dictionary:
	var lh := _lh(_fonts.logo, 52)
	var y := 110.0 + 24.0 + lh + 14.0
	var x0 := 1000.0 + 34.0
	var W := 752.0
	var out: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		if r.type == "back":
			y += 12.0
		var R := {"rect": Rect2(x0, y, W, 45)}
		var right := x0 + W - 16.0
		if r.type == "slider":
			var val: String = r.fmt.call(r.value)
			var vw := maxf(84.0, _tw("tape", 32, val))
			R.val = Rect2(right - vw, y, vw, 45)
			R.valText = val
			R.sld = Rect2(right - vw - 16.0 - 300.0, y + 7.5, 300, 30)
		elif r.type == "toggle" or r.type == "seg":
			var opts: Array = [["0", "OFF"], ["1", "ON"]] if r.type == "toggle" else r.opts
			var segs: Array = []
			var tot := 0.0
			for o in opts:
				tot += _tw("hud", 20, o[1], 20.0 * 0.06) + 32.0
			var sh := _lh(_fonts.hud, 20) + 12.0
			var sx := right - tot
			for o in opts:
				var bw := _tw("hud", 20, o[1], 20.0 * 0.06) + 32.0
				var on: bool = (o[0] == "1") == bool(r.value) if r.type == "toggle" else r.value == o[0]
				segs.append({"rect": Rect2(sx, y + (45.0 - sh) / 2.0, bw, sh), "v": o[0], "label": o[1], "on": on})
				sx += bw
			R.segs = segs
			R.segBox = Rect2(right - tot, y + (45.0 - sh) / 2.0, tot, sh)
		out.append(R)
		y += 45.0
	return {"rows": out, "bottom": y + 26.0}

func _drawOptions(ci: Control) -> void:
	var rows := _optRows()
	var L := _optionsLayout(rows)
	_gpanel(ci, L.bottom - 110.0, "Options", "ADJUST YOUR SET")
	var P := _pause
	for i in rows.size():
		var r: Dictionary = rows[i]
		var R: Dictionary = L.rows[i]
		var rect: Rect2 = R.rect
		var sel: bool = i == P.osel
		if sel:
			_paintBox(ci, "orowSel", rect.position.x, rect.position.y, rect.size.x, 45, {"r": 24, "bg": "#2F5BD3", "shadows": [[0, 0, 0, 3, "#E8A92E"]]})
		elif (i + 2) % 2 == 1:
			_paintBox(ci, "orowOdd", rect.position.x, rect.position.y, rect.size.x, 45, {"r": 24, "bg": "rgba(90,58,34,.08)"})
		var col := "#F6E7C8" if sel else "#3A2414"
		var cy := rect.position.y + 22.5
		if r.type == "back":
			var bw := _tw("hud", 28, r.label, 28.0 * 0.06)
			_txt(ci, "hud", 28, rect.position.x + (rect.size.x - bw) / 2.0, cy, r.label, col, 28.0 * 0.06)
			continue
		_txt(ci, "hud", 24, rect.position.x + 16.0, cy, r.label, col, 24.0 * 0.06)
		if R.has("sld"):
			var s: Rect2 = R.sld
			var f: float = (float(r.value) - r.min) / (r.max - r.min)
			_paintBox(ci, "sldTr", s.position.x, s.position.y + 11, 300, 8, {"r": 4, "bg": "#5A3A22", "insets": [[0, 2, 2, 0, "rgba(0,0,0,.5)"]]})
			var fw := 300.0 * clampf(f, 0.0, 1.0)
			if fw > 0.5:
				_paintBox(ci, "sldFi%d" % int(fw), s.position.x, s.position.y + 11, fw, 8, {"r": 4, "bg": {"lin": 90, "stops": [["#E8A92E", 0.0], ["#E3662B", 1.0]]}})
			_paintBox(ci, "sldKn", s.position.x + fw - 11.0, s.position.y, 22, 30, {"r": 6, "bg": {"lin": 180, "stops": [["#F4F1E8", 0.0], ["#B8B0A0", 1.0]]},
				"shadows": [[0, 2, 3, 0, "rgba(0,0,0,.5)"]], "insets": [[0, -3, 0, 0, "rgba(0,0,0,.2)"]]})
			var v: Rect2 = R.val
			var vt: String = R.valText
			_txt(ci, "tape", 32, v.end.x - _tw("tape", 32, vt), cy, vt, col)
		if R.has("segs"):
			var sb: Rect2 = R.segBox
			_paintBox(ci, "segRing%s%d" % [sel, int(sb.size.x)], sb.position.x, sb.position.y, sb.size.x, sb.size.y, {"r": 18, "bg": "#E0C898", "shadows": [[0, 0, 0, 3, "#F6E7C8" if sel else "#5A3A22"]]})
			var nseg: int = R.segs.size()
			for j in nseg:
				var sg: Dictionary = R.segs[j]
				var sr: Rect2 = sg.rect
				if sg.on:
					var rr := [18.0 if j == 0 else 0.0, 18.0 if j == nseg - 1 else 0.0, 18.0 if j == nseg - 1 else 0.0, 18.0 if j == 0 else 0.0]
					_paintBox(ci, "segOn%d_%d_%d" % [int(sr.size.x), j, nseg], sr.position.x, sr.position.y, sr.size.x, sr.size.y, {"r": rr, "bg": "#E3662B"})
				_txt(ci, "hud", 20, sr.position.x + 16.0, sr.get_center().y, sg.label, "#FFFBEA" if sg.on else "#5A3A22", 20.0 * 0.06)

func _controlsLayout() -> Dictionary:
	var ls := 24.0 * 0.06
	var x0 := 1000.0 + 34.0
	var W := 752.0
	var lh := _lh(_fonts.logo, 52)
	var y := 110.0 + 24.0 + lh + 14.0
	# column widths: 1fr | auto (keys) | auto (pad, min 128 incl. its 14 px padding and 2 px border)
	var kW := 0.0
	var pW := 128.0
	var rows: Array = []
	for i in CONTROLS.size():
		var c: Array = CONTROLS[i]
		var keys: Array = c[1]
		var kw := 0.0
		for k in keys:
			kw += maxf(44.0, _tw("hud", 20, k, ls) + 20.0) + 8.0
		kw -= 8.0
		var pads: Array = c[3] if c.size() > 3 and c[3] != null else []
		var pw := 0.0
		if c.size() > 4 and c[4] != null:
			pw += _tw("sign", 12, c[4]) + 2.0 + 6.0
		for gname in pads:
			var gd := padGlyph(gname)
			pw += (gd.w if gd.has("w") else maxf(44.0, _tw("hud", 20, gname, ls) + 20.0)) + 6.0
		pw -= 6.0
		kW = maxf(kW, kw)
		pW = maxf(pW, pw + 16.0)
		rows.append({"kw": kw, "pw": pw})
	# the grid's auto columns also fit their header cells (KEYBOARD · MOUSE / XBOX CONTROLLER, Bungee 14, .14em)
	kW = maxf(kW, _tw("sign", 14, "KEYBOARD · MOUSE", 14.0 * 0.14))
	pW = maxf(pW, _tw("sign", 14, "XBOX CONTROLLER", 14.0 * 0.14))
	var hdH := _lh(_fonts.sign, 14) + 2.0
	var c1W := W - 40.0 - kW - pW
	var out := {"x0": x0, "c1W": c1W, "kW": kW, "pW": pW, "hdY": y, "hdH": hdH, "rows": [], "seps": []}
	y += hdH + 5.0
	for i in CONTROLS.size():
		if i > 0 and i % 4 == 0:
			out.seps.append(y)
			y += 2.0 + 5.0
		out.rows.append({"y": y, "h": 42.0 if CONTROLS[i][3].has("LT") or CONTROLS[i][3].has("RT") else 40.0, "kw": rows[i].kw, "pw": rows[i].pw})
		y += out.rows[-1].h + 5.0
	y -= 5.0
	y += 12.0
	out.back = Rect2(x0, y, W, 45)
	out.bottom = y + 45.0 + 26.0
	return out

func _drawControls(ci: Control) -> void:
	var L := _controlsLayout()
	_gpanel(ci, L.bottom - 110.0, "Controls", "WZTV TV GUIDE")
	var pad := _padMode()
	var ls := 24.0 * 0.06
	var x0: float = L.x0
	var c2x: float = x0 + L.c1W + 20.0
	var c3x: float = c2x + L.kW + 20.0
	var c2r: float = c2x + L.kW
	var c3r: float = c3x + L.pW
	# headers (Bungee 14, .14em, right-aligned; the current device's in blue)
	var hy: float = L.hdY + L.hdH / 2.0 - 1.0
	var h1 := "KEYBOARD · MOUSE"
	var h2 := "XBOX CONTROLLER"
	_txt(ci, "sign", 14, c2r - _tw("sign", 14, h1, 14.0 * 0.14), hy, h1, "#8A6428" if pad else "#2F5BD3", 14.0 * 0.14)
	_txt(ci, "sign", 14, c3r - _tw("sign", 14, h2, 14.0 * 0.14), hy, h2, "#2F5BD3" if pad else "#8A6428", 14.0 * 0.14)
	for sy in L.seps:
		var sep := _svgTex("ctlSep", func():
			var s := ""
			var x := 0.0
			while x < 752.0:
				s += '<rect x="%s" y="0" width="%s" height="2" fill="#C8963C"/>' % [HudScript.n_(x), HudScript.n_(minf(8.0, 752.0 - x))]
				x += 14.0
			return HudScript.svgTexture(HudScript.svgDoc(0, 0, 752, 2, s)))
		if sep:
			ci.draw_texture_rect(sep, Rect2(x0, sy, 752, 2), false, Color(1, 1, 1, 0.6))
	for i in CONTROLS.size():
		var c: Array = CONTROLS[i]
		var R: Dictionary = L.rows[i]
		var cy: float = R.y + R.h / 2.0
		# action (+ note)
		_txt(ci, "hud", 24, x0, cy, c[0], "#3A2414", ls)
		if c[2] != null:
			var nx := x0 + _tw("hud", 24, c[0], ls) + 6.0
			_txt(ci, "sign", 13, nx, cy, c[2], "#B5472A")
		# keyboard caps (right-aligned, gap 8)
		var x := c2r - float(R.kw)
		for k in c[1]:
			var kw := maxf(44.0, _tw("hud", 20, k, ls) + 20.0)
			_paintBox(ci, "kc%d" % int(kw), x, cy - 20.0, kw, 40, {"r": 9, "bg": {"lin": 180, "stops": [["#4A3A30", 0.0], ["#2A1E18", 1.0]]},
				"shadows": [[0, 3, 0, 0, "#140C08"]], "insets": [[0, 1, 0, 0, "rgba(255,255,255,.2)"]]})
			_txt(ci, "hud", 20, x + (kw - _tw("hud", 20, k, ls)) / 2.0, cy, k, "#F6E7C8", ls)
			x += kw + 8.0
		# pad column: dashed left border, note, glyphs (right-aligned, gap 6)
		var dash := _svgTex("ctlDash", func():
			var s := ""
			var yy := 0.0
			while yy < 44.0:
				s += '<rect x="0" y="%s" width="2" height="6" fill="#C8963C" fill-opacity=".55"/>' % HudScript.n_(yy)
				yy += 12.0
			return HudScript.svgTexture(HudScript.svgDoc(0, 0, 2, 44, s)))
		if dash:
			ci.draw_texture_rect(dash, Rect2(c3x, R.y, 2, R.h), false)
		var px := c3r - float(R.pw)
		if c.size() > 4 and c[4] != null:
			_txt(ci, "sign", 12, px, cy, c[4], "#B5472A")
			px += _tw("sign", 12, c[4]) + 2.0 + 6.0
		for gname in c[3]:
			px += _drawPadGlyph(ci, gname, px, cy) + 6.0
	# ◀ BACK (selected)
	var b: Rect2 = L.back
	_paintBox(ci, "orowSel", b.position.x, b.position.y, b.size.x, 45, {"r": 24, "bg": "#2F5BD3", "shadows": [[0, 0, 0, 3, "#E8A92E"]]})
	var bt := "◀ BACK"
	_txt(ci, "hud", 28, b.position.x + (b.size.x - _tw("hud", 28, bt, 28.0 * 0.06)) / 2.0, b.get_center().y, bt, "#F6E7C8", 28.0 * 0.06)

# One Xbox glyph of the Controls card at (x, centre y); returns its width.
func _drawPadGlyph(ci: Control, g: String, x: float, cy: float) -> float:
	var d := padGlyph(g)
	var ls := 24.0 * 0.06
	var cap := {"bg": {"lin": 180, "stops": [["#4A3A30", 0.0], ["#2A1E18", 1.0]]}, "shadows": [[0, 3, 0, 0, "#140C08"]], "insets": [[0, 1, 0, 0, "rgba(255,255,255,.2)"]]}
	match d.kind:
		"face":
			_paintBox(ci, "xbFace", x, cy - 20, 40, 40, {"r": 20, "bg": {"rad": [0.42, 0.34], "stops": [["#4A4048", 0.0], ["#1E1A20", 0.72]]}, "shadows": cap.shadows, "insets": cap.insets})
			_txt(ci, "hud", 22, x + 20 - _tw("hud", 22, g, ls) / 2.0, cy, g, XB_COL.get(g.to_lower(), CREAM), ls)
			return 40.0
		"bump":
			var sp := cap.duplicate()
			sp.r = [14, 14, 7, 7]
			_paintBox(ci, "xbBump", x, cy - 20, 50, 40, sp)
			_txt(ci, "hud", 17, x + 25 - _tw("hud", 17, g, ls) / 2.0, cy, g, CREAM, ls)
			return 50.0
		"trig":
			var sp2 := cap.duplicate()
			sp2.r = [16, 16, 8, 8]
			_paintBox(ci, "xbTrig", x, cy - 21, 44, 42, sp2)
			_txt(ci, "hud", 17, x + 22 - _tw("hud", 17, g, ls) / 2.0, cy, g, CREAM, ls)
			return 44.0
		"stick":
			_paintBox(ci, "xbStick", x, cy - 20, 40, 40, {"r": 20, "bg": cap.bg, "shadows": cap.shadows, "insets": [[0, 0, 0, 3, "#6A5A50"], [0, 1, 0, 0, "rgba(255,255,255,.2)"]]})
			_txt(ci, "hud", 15, x + 20 - _tw("hud", 15, g, ls) / 2.0, cy, g, CREAM, ls)
			return 40.0
		"dpad":
			_paintBox(ci, "xbDpad", x, cy - 20, 40, 40, {"r": 10, "bg": cap.bg, "shadows": cap.shadows, "insets": cap.insets})
			var arm: String = d.arm
			var t := _svgTex("dpad" + arm, func(): return HudScript.svgTexture(HudScript.svgDoc(0, 0, 40, 40,
				'<path d="M14.5 4h11v10.5H36v11H25.5V36h-11V25.5H4v-11h10.5z" fill="#F6E7C8" fill-opacity=".3"/><path d="%s" fill="#FFC23A"/>' % DPAD_ARM[arm])))
			if t:
				ci.draw_texture_rect(t, Rect2(x + 4, cy - 16, 32, 32), false)
			return 40.0
		"sys":
			_paintBox(ci, "xbSys", x, cy - 20, 40, 40, {"r": 20, "bg": cap.bg, "shadows": cap.shadows, "insets": cap.insets})
			var sv := '<path d="M5 6h10M5 10h10M5 14h10" stroke="#F6E7C8" stroke-width="2" stroke-linecap="round"/>' if g == "MENU" else '<rect x="4" y="4" width="8" height="8" rx="1.5" fill="none" stroke="#F6E7C8" stroke-width="1.8"/><rect x="8" y="8" width="8" height="8" rx="1.5" fill="#2A1E18" stroke="#F6E7C8" stroke-width="1.8"/>'
			var t2 := _svgTex("sys" + g, func(): return HudScript.svgTexture(HudScript.svgDoc(0, 0, 20, 20, sv)))
			if t2:
				ci.draw_texture_rect(t2, Rect2(x + 9, cy - 11, 22, 22), false)
			return 40.0
	var kw := maxf(44.0, _tw("hud", 20, g, ls) + 20.0)
	_paintBox(ci, "kc%d" % int(kw), x, cy - 20.0, kw, 40, {"r": 9, "bg": cap.bg, "shadows": cap.shadows, "insets": cap.insets})
	_txt(ci, "hud", 20, x + (kw - _tw("hud", 20, g, ls)) / 2.0, cy, g, CREAM, ls)
	return kw

# ---- game over / results
func _drawOver(ci: Control) -> void:
	_drawTvbox(ci, "tvOver", 110, 160, 800, 600, 200.0, _overCanvas)
	var O = _over
	if O != null and O.get("lost"):
		_drawLostPanel(ci)
		return
	var mp: bool = O != null and O.get("mp") == true
	# .ovpan (left 1180, top 210, width 640, column, centred)
	var cx := 1180.0 + 320.0
	var y := 210.0
	if mp:
		# MP: the player table makes the column taller; keep it centred on the TV (centre y 494)
		var nr: int = (O.players as Array).size()
		var hh := (100.0 if _css.ovHdr != "" else 0.0) + 72.0 + 274.0 + 34.0 + nr * 54.0 + 24.0 + 40.0
		y = maxf(70.0, 494.0 - hh / 2.0)
	var hdr: String = _css.ovHdr
	if hdr != "":
		var lh := _lh(_fonts.logo, 64)
		ci.draw_set_transform(Vector2(cx, y + lh / 2.0), deg_to_rad(-2.0), Vector2.ONE)
		_txt(ci, "logo", 64, -_tw("logo", 64, hdr) / 2.0, 0.0, hdr, "#FFE9B8", 0.0, [[0.0, 4.0, 0.0, "#8A2E14"]])
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		y += lh + 10.0
	var lls := 46.0 * 0.2
	var llh := _lh(_fonts.sign, 46)
	_txt(ci, "sign", 46, cx - _tw("sign", 46, "ROUND", lls) / 2.0, y + llh / 2.0, "ROUND", "#FFC23A", lls, [[0.0, 4.0, 0.0, "#6A2410"]])
	y += llh + 16.0
	var n: int = _board.cards.size()
	var bw := 26.0 * 2.0 + n * 132.0 + (n - 1) * 12.0
	var bh := 22.0 * 2.0 + 196.0
	_paintBox(ci, "board%d" % n, cx - bw / 2.0, y, bw, bh, {"r": 30, "bg": {"lin": 180, "stops": [["#6A4428", 0.0], ["#4A2E1A", 0.45], ["#3A2214", 1.0]]},
		"shadows": [[0, 0, 0, 4, "#2A170E"], [0, 10, 24, 0, "rgba(0,0,0,.5)"]], "insets": [[0, 3, 0, 0, "rgba(255,220,170,.18)"], [0, -5, 0, 0, "rgba(0,0,0,.35)"]]})
	var row: HBoxContainer = dom.board
	row.position = Vector2(cx - bw / 2.0 + 26.0, y + 22.0)
	row.size = Vector2(bw - 52.0, 196.0)
	y += bh + 34.0
	if mp:
		y = _drawMpRows(ci, y, O.players)
		var A2: Dictionary = _css.anykey
		if A2.on:
			var als2 := 30.0 * 0.26
			var alh2 := _lh(_fonts.hud, 30)
			_txt(ci, "hud", 30, cx - _tw("hud", 30, A2.text, als2) / 2.0, y + alh2 / 2.0, A2.text, "#FFF4DC", als2, [[0.0, 3.0, 0.0, "#5A2210"]], _mnpress(A2.t))
		return
	# .stats: KILLS<span>n</span> POINTS<span>n</span> (gap 44; spans VT323 46, margin-left 12)
	var sls := 34.0 * 0.12
	var vls := 46.0 * 0.04
	var sk: String = _css.sk
	var sp: String = _css.sp
	var w1 := _tw("hud", 34, "KILLS", sls) + 12.0 + _tw("tape", 46, sk, vls)
	var w2 := _tw("hud", 34, "POINTS", sls) + 12.0 + _tw("tape", 46, sp, vls)
	var tot := w1 + 44.0 + w2
	var asc := maxf(_fonts.hud.get_ascent(34), _fonts.tape.get_ascent(46))
	var desc := maxf(_fonts.hud.get_descent(34), _fonts.tape.get_descent(46))
	var base := y + asc
	var x := cx - tot / 2.0
	for pair in [["KILLS", sk], ["POINTS", sp]]:
		HudScript.drawText(ci, _fonts.hud, x, base, pair[0], 34, DAU.color("#F6E7C8"), sls, [[0.0, 3.0, 0.0, "#2A140A"]])
		x += _tw("hud", 34, pair[0], sls) + 12.0
		HudScript.drawText(ci, _fonts.tape, x, base, pair[1], 46, DAU.color("#FFE08A"), vls, [[0.0, 3.0, 0.0, "#2A140A"]])
		x += _tw("tape", 46, pair[1], vls) + 44.0
	y += asc + desc + 56.0
	# .anykey
	var A: Dictionary = _css.anykey
	if A.on:
		var als := 30.0 * 0.26
		var alh := _lh(_fonts.hud, 30)
		_txt(ci, "hud", 30, cx - _tw("hud", 30, A.text, als) / 2.0, y + alh / 2.0, A.text, "#FFF4DC", als, [[0.0, 3.0, 0.0, "#5A2210"]], _mnpress(A.t))

# MP results table under the team round: channel badge + hero colour pip + name, kills and points counting up
# (the solo KILLS / POINTS stats, one row per player; ours in gold). Returns the y below it.
func _drawMpRows(ci: Control, y: float, rows: Array) -> float:
	var x0 := 1180.0
	var kR := 1600.0   # right edge of the kills column
	var pR := 1810.0   # right edge of the points column
	var hls := 16.0 * 0.14
	_txt(ci, "sign", 16, kR - _tw("sign", 16, "KILLS", hls), y + 12.0, "KILLS", "#FFC23A", hls, [[0.0, 2.0, 0.0, "#6A2410"]])
	_txt(ci, "sign", 16, pR - _tw("sign", 16, "POINTS", hls), y + 12.0, "POINTS", "#FFC23A", hls, [[0.0, 2.0, 0.0, "#6A2410"]])
	y += 34.0
	var e := easeOut(clamp_((_t - 0.35) / 1.1, 0.0, 1.0))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var cy := y + 24.0
		if r.get("me"):
			_paintBox(ci, "mpRowMe", x0 - 6.0, y, 646.0, 48.0, {"r": 24, "bg": "rgba(255,194,58,.12)", "shadows": [[0, 0, 0, 2, "rgba(255,194,58,.45)"]]})
		var ci2 := _chanIndex(r.get("hero"))
		var chs := str(CHANNELS[ci2].ch) if ci2 >= 0 else "?"
		_paintBox(ci, "mpChn", x0 + 4.0, cy - 20.0, 40.0, 40.0, {"r": 20, "bg": "#F4F1E8", "insets": [[0, 0, 0, 4, "#E23B3B"]], "shadows": [[0, 2, 0, 0, "rgba(0,0,0,.35)"]]})
		_txt(ci, "hud", 22, x0 + 24.0 - _tw("hud", 22, chs) / 2.0, cy, chs, "#2F5BD3")
		var glow: String = str(r.color) if r.get("color") is String and str(r.color).begins_with("#") else (CHANNELS[ci2].glow if ci2 >= 0 else "#F6E7C8")
		_paintBox(ci, "mpPip%s" % glow, x0 + 56.0, cy - 6.0, 12.0, 12.0, {"r": 6, "bg": glow, "shadows": [[0, 0, 8, 1, glow]]})
		var nm: String = str(r.get("name", "?")).to_upper()
		_txt(ci, "hud", 30, x0 + 80.0, cy, nm, "#FFE08A" if r.get("me") else "#F6E7C8", 30.0 * 0.06, [[0.0, 3.0, 0.0, "#2A140A"]])
		var k := str(int(floorf(float(r.get("kills", 0)) * e + 0.5)))
		var pts := _thousands(int(floorf(float(r.get("points", 0)) * e + 0.5)))
		_txt(ci, "tape", 44, kR - _tw("tape", 44, k), cy, k, "#FFE08A", 0.0, [[0.0, 3.0, 0.0, "#2A140A"]])
		_txt(ci, "tape", 44, pR - _tw("tape", 44, pts), cy, pts, "#FFE08A", 0.0, [[0.0, 3.0, 0.0, "#2A140A"]])
		y += 54.0
	return y + 24.0

# SIGNAL LOST: the right column (Shrikhand header, the reason, the classic apology, PRESS ANY KEY).
func _drawLostPanel(ci: Control) -> void:
	var O = _over
	var cx := 1180.0 + 320.0
	var y := 300.0
	var hdr := "Signal Lost"
	var lh := _lh(_fonts.logo, 76)
	ci.draw_set_transform(Vector2(cx, y + lh / 2.0), deg_to_rad(-2.0), Vector2.ONE)
	_txt(ci, "logo", 76, -_tw("logo", 76, hdr) / 2.0, 0.0, hdr, "#FFE9B8", 0.0, [[0.0, 5.0, 0.0, "#8A2E14"], [0.0, 10.0, 18.0, "rgba(0,0,0,.5)"]])
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	y += lh + 26.0
	var why: String = str(O.get("why", ""))
	var wls := 26.0 * 0.12
	var wlh := _lh(_fonts.sign, 26)
	_txt(ci, "sign", 26, cx - _tw("sign", 26, why, wls) / 2.0, y + wlh / 2.0, why, "#FFC23A", wls, [[0.0, 3.0, 0.0, "#6A2410"]])
	y += wlh + 22.0
	var note := "PLEASE DO NOT ADJUST YOUR SET"
	var nls := 26.0 * 0.08
	var nlh := _lh(_fonts.hud, 26)
	_txt(ci, "hud", 26, cx - _tw("hud", 26, note, nls) / 2.0, y + nlh / 2.0, note, "#F6E7C8", nls, [[0.0, 3.0, 0.0, "#2A140A"]])
	y += nlh + 70.0
	var A: Dictionary = _css.anykey
	if A.on:
		var als := 30.0 * 0.26
		var alh := _lh(_fonts.hud, 30)
		_txt(ci, "hud", 30, cx - _tw("hud", 30, A.text, als) / 2.0, y + alh / 2.0, A.text, "#FFF4DC", als, [[0.0, 3.0, 0.0, "#5A2210"]], _mnpress(A.t))

# The SIGNAL LOST picture: the snow source with the stand-by card's banner, red, reading SIGNAL LOST.
func _drawLostCard(cv, time: float) -> void:
	if cv == null:
		return
	var x = cv.getContext("2d")
	var w: float = cv.width
	var h: float = cv.height
	if _cardsCall("ids", []) != null:
		_cardsCall("drawTo", [x, "snow", w, h, time, {}])
	else:
		x.fillStyle = "#1E1830"
		x.fillRect(0, 0, w, h)
	var bw: float = w * 0.84
	var bh: float = h * 0.2
	var bx: float = (w - bw) / 2.0
	var by: float = h * 0.4
	x.save()
	x.shadowColor = "rgba(20,10,40,0.6)"
	x.shadowBlur = 16
	x.shadowOffsetY = 5
	DACards.rr(x, bx, by, bw, bh, bh * 0.28)
	DACards.fill(x, DACards.linear(x, 0, by, 0, by + bh, ["#E8483A", "#A82018"]))
	x.restore()
	DACards.rr(x, bx, by, bw, bh, bh * 0.28)
	DACards.stroke(x, "#F4F1E8", 4)
	DACards.rr(x, bx + 7, by + 7, bw - 14, bh - 14, bh * 0.2)
	DACards.stroke(x, DACards.alpha("#F4E03A", 0.9), 2)
	DACards.label(x, "SIGNAL LOST", w / 2.0, by + bh * 0.47, {
		"fam": DACards.FONT.groovy, "px": bh * 0.62, "maxW": bw * 0.88, "fill": DACards.vgrad(["#FFFBEA", "#FFE28A"]),
		"stroke": DACards.C.ink, "lw": bh * 0.07, "depth": 4, "depthFill": "#6A1410", "dx": 0.6, "dy": 1,
	})
	if cv.has_method("redraw"):
		cv.redraw()
