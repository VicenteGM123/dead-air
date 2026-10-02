# DEAD AIR — ScreenManager (ARCHITECTURE §12, GDD §10.0 / §18.14): every CRT in the station is live.
# Port of src/game/screens.js.
#
# GROUPS AND SOURCES
#   Every CRT mesh is registered once with register(mesh, groupId = 'scr_decor', { id, slot }) (props do it through
#   game.props.place; meshes under the level flagged userData.screenGroup that nobody registered are picked up at init).
#   Each screen shows one SOURCE, resolved every frame (first match wins):
#     1. a screen-spawn telegraph on that one screen (priority 1: static + a growing silhouette),
#     2. a per-screen effect (the Sign-On warm-up dot -> line -> picture, blink),
#     3. the highest-priority active override covering its group (scr_telly / scr_vtr2 / scr_preview: never),
#     4. a source pinned with setSource(groupId, sourceId) (null unpins),
#     5. the GDD §10.0 default of its group, before / after power, per slot: the MC wall is 4 x 3 big CRTs (client
#        request: bigger screens, the live row at eye level): its MIDDLE row (scr_mc_feeds) = lobby, newsroom,
#        studio A, studio B feeds left to right (pass B); the 8 canned (top + bottom rows) = 3 bars / 3 station ID /
#        2 static, the static ones being the two screen-spawn CRTs (bottom corners); Hootie's TV (ss_studio_b) loops
#        hullabaloo; scr_feed_<area> = its live feed while the player is in <area>, else station_id (the lobby
#        exhibit is live before power too); scr_telly has no default (Telly owns its face).
#   Source ids: static, color_bars, station_id, right_back, stand_by, hullabaloo, baron, signoff_film,
#   feed_<lobby|newsroom|studio_a|studio_b|yard>, satellite, flinch, plus 'black', 'white', any gfx card id
#   (game.cards.ids()) or a Texture2D. Animated cards are shared handles ticked only while on camera.
#
# RENDER PASSES (hard cap 2 extra scene renders per frame: A + B)
#   Pass A "program feed": the feed camera of the player's area, 384x288, 15 fps, 2-RT swap chain (screens show the
#     front buffer while the back one renders: a monitor in its own shot is a live infinite mirror). Runs only when
#     (power is on or the player is in the lobby) and a screen of that area's scr_feed_* group showing the feed is in
#     the view frustum within 20 m. Layers 0+1+2, zombies in human skin (below). While a 'satellite' screen is on
#     camera, pass A renders the Uplink insert camera (layer 3).
#   Pass B "MC wall": in master_control after power, one indoor feed per frame at 256x192, round robin, <= 24/s,
#     only while a feed-row CRT is on camera. Elsewhere the feed row keeps the last frames.
#   setFeedSize('A'|'B', w, h) rebuilds that pass's targets at another size (stats.feedSize).
#   Each feed render draws the scene into an MSAA HDR target, then a quad pass grades it into a display-referred TV
#     picture (auto-gain, ACES, video saturation/contrast, S-curve, warm tube cast, chroma smear) so feeds read as
#     vividly as the gfx cards on the CRTs.
#   Feed cameras stand at the feed_cam_* anchors (at the lens of a bc_pedestal_camera / bc_eng_camera prop placed
#     there), FOV from the anchor (GDD §5.6; 55 if missing), pan over 8 s (the prop head pans with it and its tally
#     lights when the power / colour wave reaches it). The pan is +-20 deg at most, and never more than PAN.keep of
#     the camera's horizontal half-FOV, so the shot's subject stays inside the middle ~45 % of the frame.
#     feedCams[area] is a Camera3D (DAU.ud(cam).feed = { id, area, pos, target, panAmp, ... }).
#   Human skin on feeds (GDD §8): zombie materials get feed variants (_variant) that turn the mint skin peach
#     #E8B896 and the static-snow eyes into normal eyes, only in feed renders.
#
# CRT ORIENTATION: mats.screen's shader takes local +z as the glass normal (bulge + fresnel/glint). kit.screen()
#   builds its domed plane facing -z (rotateY(PI) baked in), so register() re-bakes such meshes to face local +z
#   (mesh turned by PI, node turned back by PI: identical world surface and picture). userData.screenFlip = bool.
#
# API (game.screens)
#   register(mesh, groupId, {id, slot}) -> entry        unregister(meshOrId) -> bool   entries(groupIds?) -> entry[]
#   setSource(groupId, sourceId|null)                   sourceOf(groupId) -> what that group shows now
#   override(sourceId, groupIds = by source, seconds = INF, priority = by source)
#     -> handle { id, source, groups, priority, active, cancel(), extend(seconds) }. Group ids accept the GDD
#     wildcards 'scr_feed_*' / 'scr_mc_*'; without a list the GDD table applies (satellite / station_id / baron:
#     decor + canned + feeds; flinch / stand_by / hullabaloo / right_back: decor + canned; others: everything).
#     Identical calls within 0.25 s share one override. Emits machine:screen_override { source, groups, duration }.
#     PRIORITY (lower wins): sequence 0 (Sign-On), telegraph 1, boss 2, signoff 3, uplink 4, ee 5, flinch 6,
#     stand_by 7, hullabaloo 8, intermission 9.
#   telegraph(screenSpawnId, seconds = 2.2, { sound = true }) -> handle { cancel(), active }: chunky cyan-cast snow,
#     a dark figure pushing up to the glass with glowing snow eyes, palms slapping the glass from 45 %, tearing
#     scan lines + a flash at the end, glass jitter/bulge, on the CRT of that screen spawn (entry id == spawn id,
#     else the nearest registered screen within 1.3 m), and screen_telegraph through its TV speaker.
#   feedTexture(areaId) -> Texture2D|null (the latest live frame of that area)
#   setInsert(node3d|null): the Uplink insert studio content, parented to insertRoot (a turntable at
#     [200, 1.05, 200] spinning at insertSpin rad/s, default 0.9; set 0 to drive it yourself), layer 3.
#     insertCamera is the insert camera; the 'satellite' source = its view + the LIVE VIA SATELLITE super.
#   freezeFlinch() -> Texture2D: freezes pass A's last frame with a film-frame border for the 'flinch' source
#     (override('flinch', ...) calls it itself; the 'flinch' card is the fallback when pass A never ran).
#   zoomFeed(area, seconds = 5, { zoom = 2.6 }) -> bool: crash-zooms that feed camera toward its target (lobby
#     exhibit toy), then eases back.
#   warmUp(entries = the MC wall in snake order, { start, end, settle }) -> count, blink(entriesOrGroupIds,
#     { delay, spread, from }): CRT power-on effects (Sign-On). wallOrder() -> the 12 wall entries, snake order.
#   speaker(soundId, { near = 1, groups, source, ...audio opts }) -> voice: plays a cue "from the TVs": TV-speaker
#     filter, positional, at the nearest matching screens to the listener (audio.play(id, { tv:true, pos })).
#   feedPass, stats { passA, passB, sat, flinch, maxPerFrame, feedDraws, redraws, tickMs }, feedCams, groups, byId,
#   overrides,
#   timeScale (debug/tests: 0 holds every CRT effect, feed pan and override timer on one frame).
# MP (design/mp-machines.md, RECONCILE R9): no shared state and no messages — every screen is local presentation of
#   the replicated power flag (machines.powerOn), the replicated events below (round:start / round:end {next},
#   powerup:grab, machine:boss_start, egg:complete, game:victory, game:over, zombie:spawn of client puppets, power:on)
#   and the local camera / local player's area (game.player rides along with the spectated teammate while off-air,
#   so the program feed follows the view). Owners call override / telegraph / setSource / zoomFeed / speaker /
#   setInsert locally on every peer from their own replicated actions (zombies' screen entries call telegraph on
#   clients too); nothing here is replicated generically. round:end in MP reads payload.next.special.
# Automatic overrides (only while powered): round:end -> right_back for the intermission (hullabaloo when the next
# round is Hullabaloo Hour: rounds.nextSpecial / isHullabaloo(n) / specialFor(n)), round:start {special:
# 'hullabaloo'} -> hullabaloo for that round, powerup:grab {type:'please_stand_by'} -> stand_by 8 s. Always:
# machine:boss_start -> static on every overridable group but scr_feed_yard until egg:complete / game:over /
# game:victory / newGame.
#
# GODOT IMPLEMENTATION NOTES (engine plumbing; behaviour as the JS)
# * Passes: every feed target is a SubViewport sharing game.scene's World3D. An "HDR" target (_target(w, h, 4)) is a
#   3D SubViewport (MSAA 4x, use_hdr_2d, its own Camera3D; the feed camera's transform / fov / near / far / cull
#   mask are copied into it before each render) rendering game.scene's World3D with render.envFeed (the world
#   environment: linear tone mapper at exposure 1, no bloom), so it holds the scene-linear HDR picture; the grade's
#   exposure is GRADE.feed x the main tone-mapping exposure (JS renderer.toneMappingExposure, 1.05). A "picture" target
#   (_target(w, h, 0, false)) is a 2D SubViewport whose full-rect ColorRect runs the grade (or flinch) canvas shader on
#   an HDR target's texture and writes an 8-bit sRGB-encoded picture (like the DACanvas card textures, so the CRT
#   material treats feeds and cards alike). Targets render with UPDATE_ONCE when a job is issued; HDR targets are
#   created first so they render before the pictures that read them (Godot renders sibling viewports in activation
#   order). _prePass() runs from render.addPrePass like the JS (at the end of lateUpdate when render has none); a
#   job's result is committed (swap chain front, maps, frame counters) on the next frame, once the viewports have
#   rendered.
# * Godot renders every viewport from one scene state, so what the JS toggled around a feed render cannot differ
#   between the feed and the main view. _isolate(area) keeps the part that matters: it forces the feed's area root
#   (+ its doors) visible for the frame the feed renders (the level's portal culling hides areas the player cannot
#   see; the MC wall shows the other rooms) and _restoreVis() puts the level's culling back once the frame is drawn
#   (RenderingServer.frame_post_draw). Not ported: hiding the other area roots / building shell / street (a draw-call
#   saving; walls hide them anyway), moving the sky dome to the feed camera, and uHeroFade = 1 / uFeedSkin = 1
#   around the render (feedPass stays false here). Instead every feed
#   camera also carries the FEED_LAYER bit (17) in its cull mask (no node is on that layer; render.gd uses bits 18
#   / 19 as camera flags the same way), so a shader can tell a feed render with (CAMERA_VISIBLE_LAYERS & (1u << 17u))
#   != 0u. The zombie human-skin variants (_variant) use exactly
#   that: at zombie:spawn a zombie ShaderMaterial gets a copy of its shader with the JS skin swap applied to ALBEDO
#   at the end of fragment() on feed cameras only (the material object, and every parameter other systems set on
#   it, stays the same), and the static-snow eye meshes get a material_overlay that draws the normal eye on feed
#   cameras only. A shader that wants the JS uHeroFade-off-on-feeds behaviour can test the same bit.
# * Screen materials: the map is written through `mat.map` when the material exposes it, else the ShaderMaterial
#   parameter tScreen (+ uTexel), else albedo_texture; uBright / uBulge / uWobble are shader parameters. A screen
#   whose material lives on its (shared) mesh resource, or that another registered screen already uses, gets its
#   own duplicate first (JS: mats.screen() is never cached).
# * Renamed: the JS `_ready` flag is `_isReady` (Node virtual name). JS `undefined` sources (scr_telly: no default)
#   are null here; _texFor returns KEEP for them.
extends RefCounted

const SCREEN_GROUPS := ["scr_feed_lobby", "scr_feed_newsroom", "scr_feed_studio_a", "scr_feed_studio_b",
	"scr_feed_yard", "scr_mc_feeds", "scr_mc_canned", "scr_decor", "scr_telly", "scr_vtr2", "scr_preview"]
const NEVER_OVERRIDDEN := ["scr_telly", "scr_vtr2", "scr_preview"]
const NEVER := NEVER_OVERRIDDEN
const OVERRIDE_GROUPS := ["scr_feed_lobby", "scr_feed_newsroom", "scr_feed_studio_a", "scr_feed_studio_b",
	"scr_feed_yard", "scr_mc_feeds", "scr_mc_canned", "scr_decor"]
const DECOR_CANNED := ["scr_decor", "scr_mc_canned"]
const PRIORITY := {"sequence": 0, "telegraph": 1, "boss": 2, "signoff": 3, "uplink": 4, "ee": 5, "flinch": 6, "stand_by": 7, "hullabaloo": 8, "intermission": 9}
const SOURCE_PRIORITY := {"static": 2, "signoff_film": 3, "satellite": 4, "station_id": 5, "baron": 5, "flinch": 6, "stand_by": 7, "hullabaloo": 8, "right_back": 9}
# GDD §10.0 override table: the groups a source covers when override() gets no group list.
const EE_GROUPS := ["scr_decor", "scr_mc_canned", "scr_feed_*"]
const SOURCE_GROUPS := {
	"satellite": EE_GROUPS, "station_id": EE_GROUPS, "baron": EE_GROUPS, "flinch": DECOR_CANNED, "stand_by": DECOR_CANNED,
	"hullabaloo": DECOR_CANNED, "right_back": DECOR_CANNED,
}
const FEED_AREAS := ["lobby", "newsroom", "studio_a", "studio_b", "yard"]
const MC_FEEDS := ["lobby", "newsroom", "studio_a", "studio_b"]
const GROUP_AREA := {"scr_feed_lobby": "lobby", "scr_feed_newsroom": "newsroom", "scr_feed_studio_a": "studio_a", "scr_feed_studio_b": "studio_b", "scr_feed_yard": "yard"}
# MC canned rows (every wall row but the feeds row, top to bottom), left to right as seen from the room: a
# checkerboard of bars / station ID; the bottom corners are ss_mc_w / ss_mc_e (always static).
const CANNED_GRID := [
	["color_bars", "station_id", "color_bars", "station_id"],
	["static", "color_bars", "station_id", "static"],
]
const GRADE := {"feed": 1.5, "sat": 1.32, "contrast": 1.08, "insert": 1.2}
# pan: +-amp, capped at keep x the horizontal half-FOV (4:3 feeds) so the look target stays mid-frame
const PAN := {"amp": 0.3490658503988659, "period": 8.0, "keep": 0.42}
const VIS := {"every": 0.2, "range": 32.0}
const TICK := {"near": 6.0, "farDist": 14.0, "mid": 8.0, "far": 4.0}
const TELE := {"w": 128, "h": 96, "fps": 20.0}
const ZOOM := {"factor": 2.6, "in": 0.45, "out": 0.6}
const CAM_PROPS := ["bc_pedestal_camera", "bc_eng_camera"]
const INSERT := {"pos": Vector3(200, 0, 200), "eye": [0.0, 1.34, 1.62], "look": [0.0, 1.13, 0.0], "fov": 34.0}
const UP := Vector3(0, 1, 0)
# Godot only: marker bit of the feed cameras' cull mask (see the header). No node lives on this layer.
const FEED_LAYER := 17
const KEEP := "__keep__"
const CANVAS_PATH := "res://scripts/gfx/canvas2d.gd"
const INSERT_GLB := "res://assets/runtime/screens/insert_studio.glb"

# Zombie human-skin swap (feed renders only): mint #A9C7A4 / shadow #7FA08A -> peach #E8B896 (same luminance).
# Works on linear or sRGB-baked colours: it keys on "grey-green" hue (g above r ~ b), not on exact values.
const SKIN_SWAP := """
vec3 da_feed_skin( vec3 daFc ) {
	float daFl = max( dot( daFc, vec3( 0.2126, 0.7152, 0.0722 ) ), 1e-4 );
	float daFg = ( daFc.g - 0.5 * ( daFc.r + daFc.b ) ) / daFl;
	float daFrb = abs( daFc.r - daFc.b ) / daFl;
	float daFk = smoothstep( 0.07, 0.13, daFg ) * ( 1.0 - smoothstep( 0.42, 0.6, daFg ) ) * ( 1.0 - smoothstep( 0.14, 0.26, daFrb ) );
	return mix( daFc, daFl * vec3( 1.5, 0.9, 0.57 ) * 1.05, daFk );
}
"""
# Injection points (JS injectSkin): before the char shader's `daAlbedo = diffuseColor.rgb;` (the albedo before
# lighting), else at the end of fragment() on ALBEDO.
const SKIN_AT := "daAlbedo = diffuseColor.rgb;"
const SKIN_DIFFUSE := "\tif ( ( CAMERA_VISIBLE_LAYERS & ( 1u << 17u ) ) != 0u ) { diffuseColor.rgb = da_feed_skin( diffuseColor.rgb ); } // DA feed skin (screens.gd)\n"
const SKIN_CALL := "\n\t{ // DA feed skin (screens.gd)\n\t\tif ( ( CAMERA_VISIBLE_LAYERS & ( 1u << 17u ) ) != 0u ) { ALBEDO = da_feed_skin( ALBEDO ); }\n\t}\n"

# The zombie eyes on feeds: the normal eye drawn over the static snow, on feed cameras only.
const EYE_OVERLAY := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform sampler2D tEye : source_color, filter_linear;
void fragment() {
	if ( ( CAMERA_VISIBLE_LAYERS & ( 1u << 17u ) ) == 0u ) { discard; }
	ALBEDO = texture( tEye, UV ).rgb;
}
"""

# Film-frame freeze (flinch): pass A's frame, over-exposed flashbulb grade, sprocket bars top and bottom.
# (canvas_item: reads / writes the sRGB-encoded pictures, works in linear like the JS)
const FLINCH_FRAG := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D tSrc : filter_linear, repeat_disable;
vec3 daToLin( vec3 c ) { return mix( c / 12.92, pow( ( c + 0.055 ) / 1.055, vec3( 2.4 ) ), step( vec3( 0.04045 ), c ) ); }
vec3 daToSrgb( vec3 c ) { return mix( c * 12.92, 1.055 * pow( c, vec3( 1.0 / 2.4 ) ) - 0.055, step( vec3( 0.0031308 ), c ) ); }
void fragment() {
	vec2 uv = vec2( UV.x, 1.0 - UV.y );
	float gate = 0.085;
	vec2 suv = vec2( 0.5 + ( uv.x - 0.5 ) * 0.94, 0.5 + ( uv.y - 0.5 ) * ( 1.0 - 2.0 * gate ) * 1.08 );
	vec3 c = daToLin( texture( tSrc, vec2( suv.x, 1.0 - suv.y ) ).rgb );
	c = c * 1.35 + vec3( 0.14, 0.1, 0.05 );
	float L = dot( c, vec3( 0.2126, 0.7152, 0.0722 ) );
	c = mix( vec3( L ), c, 0.5 ) * vec3( 1.12, 1.0, 0.8 );
	vec2 q = uv - 0.5;
	c *= 1.0 - 1.4 * dot( q * vec2( 1.0, 1.3 ), q * vec2( 1.0, 1.3 ) );
	float bar = step( uv.y, gate ) + step( 1.0 - gate, uv.y );
	float hy = uv.y < 0.5 ? uv.y / gate : ( 1.0 - uv.y ) / gate;
	vec2 hp = vec2( fract( uv.x * 8.0 ) - 0.5, hy - 0.5 );
	float hole = 1.0 - smoothstep( 0.16, 0.2, max( abs( hp.x ) * 1.1, abs( hp.y ) * 0.62 ) );
	vec3 barC = mix( vec3( 0.03, 0.022, 0.035 ), vec3( 1.1, 1.0, 0.86 ), hole );
	float edge = 1.0 - smoothstep( 0.0, 0.012, min( abs( uv.y - gate ), abs( uv.y - 1.0 + gate ) ) );
	c = mix( c, barC, clamp( bar, 0.0, 1.0 ) );
	c = mix( c, vec3( 0.02 ), edge * 0.8 );
	COLOR = vec4( daToSrgb( clamp( c, vec3( 0.0 ), vec3( 1.0 ) ) ), 1.0 );
}
"""

# Studio-camera grade: feeds render in scene-linear HDR, then this quad pass turns the frame into a display-referred
# TV picture (like a decoded gfx card, so the CRT shows it as vividly as the cards): auto-gain, ACES, video
# saturation + contrast in display space, a warm tube tint and a little analog chroma smear. The JS stored
# pow(c, 2.2) linear; here the same value is stored sRGB-encoded in an 8-bit picture.
const GRADE_FRAG := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D tSrc : filter_linear, repeat_disable;
uniform vec2 uTexel;
uniform float uExposure;
uniform float uSat;
uniform float uContrast;
vec3 daAces( vec3 x ) { return clamp( ( x * ( 2.51 * x + 0.03 ) ) / ( x * ( 2.43 * x + 0.59 ) + 0.14 ), 0.0, 1.0 ); }
vec3 daToSrgb( vec3 c ) { return mix( c * 12.92, 1.055 * pow( c, vec3( 1.0 / 2.4 ) ) - 0.055, step( vec3( 0.0031308 ), c ) ); }
void fragment() {
	vec2 vUv = UV;
	vec3 c = texture( tSrc, vUv ).rgb;
	c.r = mix( c.r, texture( tSrc, vUv + vec2( uTexel.x * 1.5, 0.0 ) ).r, 0.4 );
	c.b = mix( c.b, texture( tSrc, vUv - vec2( uTexel.x * 1.5, 0.0 ) ).b, 0.4 );
	c = pow( daAces( max( c, vec3( 0.0 ) ) * uExposure ), vec3( 1.0 / 2.2 ) );
	float L = dot( c, vec3( 0.299, 0.587, 0.114 ) );
	c = mix( vec3( L ), c, uSat );
	c = clamp( ( c - 0.5 ) * uContrast + 0.5 + vec3( 0.014, 0.004, -0.012 ), 0.0, 1.0 );
	c = mix( c, c * c * ( 3.0 - 2.0 * c ), 0.45 ); // S-curve: punchy mids, crisp blacks under the CRT glass and bloom
	COLOR = vec4( daToSrgb( pow( c, vec3( 2.2 ) ) ), 1.0 );
}
"""

# ---------------------------------------------------------------------------------------------------- records
# A registered screen (JS entry object).
class Entry extends RefCounted:
	var id := ""
	var mesh: Node3D = null
	var group := "scr_decor"
	var mat = null
	var slot = null
	var source = null
	var tex = null
	var texSet := false          # JS e.tex !== undefined
	var fx = null                # { kind: 'warm'|'blink', t0, until, ... }
	var tele = null              # Tele
	var visible := false
	var near := false
	var dist := INF
	var pos := Vector3.ZERO
	var baseScale := Vector3.ONE
	var basePos := Vector3.ZERO
	var baseBright = null
	var baseBulge = null
	var touched := false
	var scaled := false
	var jittered := false
	var bulged := false
	var hootie := false

# An override: the JS `ov` record and its handle in one object ({ id, source, groups, priority, active, cancel(),
# extend(seconds) }). It keeps only a weak reference to the manager.
class Override extends RefCounted:
	var id := 0
	var source = null
	var groups: Array = []
	var gset := {}
	var priority := 0.0
	var t0 := 0.0
	var until := INF
	var key := ""
	var _sm: WeakRef = null
	var active: bool:
		get:
			var sm = _sm.get_ref() if _sm != null else null
			return sm != null and sm._ovIndex(self) >= 0
	var handle:
		get:
			return self
	func cancel() -> void:
		var sm = _sm.get_ref() if _sm != null else null
		if sm != null:
			sm._cancel(self)
	func extend(s = INF) -> void:
		var sm = _sm.get_ref() if _sm != null else null
		if sm == null:
			return
		var sec: float = float(s) if s != null and is_finite(float(s)) else INF
		until = maxf(until, sm.clock + sec)

# A pooled telegraph canvas.
class Tele extends RefCounted:
	var canvas = null
	var ctx = null
	var img = null
	var buf := PackedByteArray()
	var tex = null
	var entry = null
	var t0 := 0.0
	var dur := 1.0
	var last := -1.0
	var seed := 1

class TeleHandle extends RefCounted:
	var _sm: WeakRef = null
	var _tl: Tele = null
	var active: bool:
		get:
			var sm = _sm.get_ref() if _sm != null else null
			return sm != null and _tl != null and sm._teles.has(_tl)
	func cancel() -> void:
		var sm = _sm.get_ref() if _sm != null else null
		if sm != null and _tl != null:
			sm._endTele(_tl)

# ---------------------------------------------------------------------------------------------------- state
var game
var groups := {}
var sources := {}               # pinned by setSource
var byId := {}
var overrides: Array = []       # sorted: priority asc, newest first on ties
var feedCams := {}              # area -> Camera3D (DAU.ud(cam).feed)
var feedPass := false
var insertRoot: Node3D = null
var insertCamera: Camera3D = null
var insertSpin := 0.9
var clock := 0.0
var timeScale := 1.0            # debug / tests: 0 holds every screen effect, pan and override timer on a frame
var PASS_A := {"w": 384, "h": 288, "fps": 15.0, "range": 20.0}
var PASS_B := {"w": 256, "h": 192, "rate": 24.0}
var stats := {"passA": 0, "passB": 0, "sat": 0, "flinch": 0, "maxPerFrame": 0, "frames": 0, "feedDraws": 0, "redraws": 0, "tickMs": 0.0,
	"feedSize": {"A": [384, 288], "B": [256, 192]}}
var _isReady := false
var _uid := 0
var _ovUid := 0
var _area = null
var _lastArea = KEEP             # JS undefined
var _wall = null
var _visT := 0.0
var _posDirty := true
var _aAcc := 1.0
var _bAcc := 1.0
var _bNext := 0
var _jobA = null
var _jobB = null
var _hdrA = null
var _hdrB = null
var _rtA: Array = []
var _aFront := 0
var _aFrames := 0
var _aArea = null
var _rtB := {}
var _bFront := {}
var _rtSat = null
var _satFrames := 0
var _rtFlinch = null
var _flinchTex = null
var _flinchPending := false
var _teles: Array = []
var _telePool: Array = []
var _inUse := {}                 # animated card key -> [handle, nearest on-camera distance this frame]
var _handles := {}               # card id -> animated handle
var _cardCache := {}             # card id -> { anim, tex } | null (static textures resolved once)
var _variants := {}              # material -> feed variant | null
var _skinShaders := {}           # Shader -> feed-skin Shader | null
var _camProps: Array = []
var _auto := {"inter": null, "hull": null, "boss": null}
var _filmHandle = null
var _filmT0 := 0.0
var _insertObj = null
var _insertSet = null
var _eyeMat = null
var _eyeCanvas = null
var _gradeShader: Shader = null
var _flinchShader: Shader = null
var _holder: Node = null         # parent of the pass SubViewports
var _camHolder: SubViewport = null # never-rendered viewport holding the feed cameras + the insert camera
var _pending: Array = []         # jobs issued last frame, committed once rendered
var _env = null
var _envAt := -INF
var _exposure := 1.0
var _white: ImageTexture = null
var _black: ImageTexture = null
var _flipped := {}               # source Mesh -> the same mesh turned by PI (faceFront)
var _visSave: Array = []         # [node, visible, ...] forced visible by _isolate until the frame is drawn
var _unPre = null                # render.addPrePass unsubscribe (null: _prePass runs from lateUpdate)
var _uniformNames := {}          # Shader -> { uniform name: true }

func _init(g) -> void:
	game = g
	for id in SCREEN_GROUPS:
		groups[id] = []
	_white = _solidTexture(255, 250, 240)
	_black = _solidTexture(0, 0, 0)
	# Other shaders may read this during feed renders (JS: 1 while a feed camera renders; see the header).
	var M = game.mats
	var U = M.get("uniforms") if M != null else null
	if U is Dictionary and not U.has("uFeedSkin"):
		U["uFeedSkin"] = {"value": 0.0}

static func _solidTexture(r: int, g: int, b: int) -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(r, g, b, 255))
	return ImageTexture.create_from_image(img)

static func clamp01(x: float) -> float:
	return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)

static func easeOutCubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

static func easeOutBack(x: float, s: float = 2.2) -> float:
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

# ------------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	var g = game
	_buildHolder()
	_adoptUnregistered()
	_buildFeedCams()
	_buildInsert()
	_buildTargets()
	var r = g.render
	if r != null and r.has_method("addPrePass"):
		_unPre = r.addPrePass(func(_r = null): _prePass())
	var ev = g.events
	ev.on("round:end", func(p): _onRoundEnd(p))
	ev.on("round:start", func(p): _onRoundStart(p))
	ev.on("powerup:grab", func(p):
		if p is Dictionary and _same(p.get("type"), "please_stand_by") and _powered():
			override("stand_by", DECOR_CANNED, Config.T.drops.freeze, PRIORITY.stand_by))
	ev.on("machine:boss_start", func():
		if _auto.boss != null:
			_auto.boss.cancel()
		_auto.boss = override("static", OVERRIDE_GROUPS.filter(func(id): return id != "scr_feed_yard"), INF, PRIORITY.boss))
	for name in ["egg:complete", "game:victory", "game:over"]:
		ev.on(name, func():
			if _auto.boss != null:
				_auto.boss.cancel()
			_auto.boss = null)
	ev.on("zombie:spawn", func(p):
		if p is Dictionary and p.get("z") != null:
			_prepZombie(p.z))
	ev.on("power:on", func():
		_aAcc = 1.0
		_bAcc = 1.0)
	_isReady = true
	_posDirty = true

func reset() -> void:
	for ov in overrides.duplicate():
		_cancel(ov)
	for tl in _teles.duplicate():
		_endTele(tl)
	for e in _all():
		_clearFx(e)
	sources = {}
	_auto = {"inter": null, "hull": null, "boss": null}
	_aFrames = 0
	_aArea = null
	_satFrames = 0
	_flinchTex = null
	_aAcc = 1.0
	_bAcc = 1.0
	_lastArea = KEEP
	clock = 0.0
	_pending.clear()
	for cam in feedCams.values():
		var f: Dictionary = DAU.ud(cam).feed
		f.zoom = null
		f.zf = 1.0
	_posDirty = true
	if _camProps.is_empty():
		_findCamProps()

func update(_dt = 0.0) -> void:
	var dt: float = float(game.time.realDt) * timeScale
	clock += dt
	for i in range(overrides.size() - 1, -1, -1):
		if i < overrides.size() and clock >= overrides[i].until:
			_cancel(overrides[i])

func lateUpdate(_dt = 0.0) -> void:
	var g = game
	var dt: float = float(g.time.realDt) * timeScale
	_area = _playerArea()
	_visT -= dt
	if _visT <= 0.0 or _posDirty:
		_visT = VIS.every
		_updateVisibility()
	_inUse.clear()
	for id in SCREEN_GROUPS:
		var list: Array = groups[id]
		for i in list.size():
			_refresh(list[i])
	var now: float = float(g.time.realNow)
	var t0 := Time.get_ticks_usec()
	# Cheap ticking: a card redraws its canvas + re-uploads only when its frame index changes; far away (small on
	# screen) the time is quantised so it redraws at most TICK.mid / TICK.far times per second.
	for key in _inUse:
		var pair: Array = _inUse[key]
		var h = pair[0]
		var d: float = pair[1]
		var t: float = clock - _filmT0 if key == "__film" else now
		var rate: float = 0.0 if d < TICK.near else (TICK.mid if d < TICK.farDist else TICK.far)
		if _tickHandle(h, floorf(t * rate) / rate if rate > 0.0 else t):
			stats.redraws += 1
	stats.tickMs += (Time.get_ticks_usec() - t0) / 1000.0
	_updateFeedProps()
	if insertRoot != null and insertSpin != 0.0:
		insertRoot.rotation.y += insertSpin * dt
	_schedule(dt)
	if _unPre == null:
		_prePass()

# ------------------------------------------------------------------------------------------------ registry
func register(mesh, groupId = "scr_decor", opts = {}):
	if mesh == null or not (mesh is Node3D):
		return null
	if opts == null:
		opts = {}
	var group: String = groupId if groupId is String and groups.has(groupId) else "scr_decor"
	var old = _entryOfMesh(mesh)
	if old != null:
		_remove(old)
	faceFront(mesh)
	var id = opts.get("id")
	if not id:
		id = _udGet(mesh, "screenId")
	if not id:
		_uid += 1
		id = "screen_%d" % _uid
	id = str(id)
	if byId.has(id):
		_uid += 1
		id = "%s#%d" % [id, _uid]
	var e := Entry.new()
	e.id = id
	e.mesh = mesh
	e.group = group
	e.mat = _screenMat(mesh)
	e.slot = opts.get("slot")
	e.baseScale = mesh.scale
	e.basePos = mesh.position
	e.baseBright = _uGet(e.mat, "uBright") if e.mat != null and _uHas(e.mat, "uBright") else null
	DAU.ud(mesh)["screenEntry"] = id
	groups[group].append(e)
	byId[id] = e
	_wall = null
	_posDirty = true
	if mesh.get_parent() != null:
		e.pos = DAU.worldPos(mesh)
	_refresh(e)
	return e

func unregister(meshOrId) -> bool:
	var e = byId.get(meshOrId) if meshOrId is String else _entryOfMesh(meshOrId)
	if e == null:
		return false
	_remove(e)
	return true

func entries(groupIds = null) -> Array:
	if groupIds == null:
		return _all()
	var out: Array = []
	for id in _expand(groupIds):
		out.append_array(groups.get(id, []))
	return out

func setSource(groupId, sourceId) -> bool:
	if not groups.has(groupId):
		return false
	if sourceId == null:
		sources.erase(groupId)
	else:
		sources[groupId] = sourceId
	for e in groups[groupId]:
		_refresh(e)
	return true

func sourceOf(groupId):
	var list = groups.get(groupId)
	var e = list[0] if list is Array and not list.is_empty() else null
	if e != null:
		return e.source if e.source != null else _resolve(e)
	if not NEVER.has(groupId):
		for ov in overrides:
			if ov.gset.has(groupId):
				return ov.source
	return sources.get(groupId)

# ------------------------------------------------------------------------------------------------ overrides
func override(sourceId, groupIds = null, seconds = INF, priority = null) -> Override:
	var pr: float
	if (priority is int or priority is float) and is_finite(float(priority)):
		pr = float(priority)
	elif sourceId is String and SOURCE_PRIORITY.has(sourceId):
		pr = SOURCE_PRIORITY[sourceId]
	else:
		pr = PRIORITY.ee
	var list = groupIds
	if list == null:
		list = SOURCE_GROUPS[sourceId] if sourceId is String and SOURCE_GROUPS.has(sourceId) else OVERRIDE_GROUPS
	var gl: Array = []
	var gset := {}
	for id in _expand(list):
		if groups.has(id) and not NEVER.has(id) and not gset.has(id):
			gset[id] = true
			gl.append(id)
	var dur: float = maxf(0.0, float(seconds)) if (seconds is int or seconds is float) and is_finite(float(seconds)) else INF
	var sorted := gl.duplicate()
	sorted.sort()
	var srcKey: String = sourceId if sourceId is String else (str(sourceId.get_instance_id()) if sourceId is Object else str(sourceId))
	var key := "%s|%s|%s" % [srcKey, pr, ",".join(sorted)]
	for o in overrides:
		if o.key == key and clock - o.t0 < 0.25:
			o.until = maxf(o.until, clock + dur)
			return o
	_ovUid += 1
	var ov := Override.new()
	ov.id = _ovUid
	ov.source = sourceId
	ov.groups = gl
	ov.gset = gset
	ov.priority = pr
	ov.t0 = clock
	ov.until = clock + dur
	ov.key = key
	ov._sm = weakref(self)
	overrides.append(ov)
	overrides.sort_custom(func(a, b):
		if a.priority != b.priority:
			return a.priority < b.priority
		if a.t0 != b.t0:
			return a.t0 > b.t0
		return a.id > b.id)
	if _same(sourceId, "flinch"):
		freezeFlinch()
	if _same(sourceId, "signoff_film"):
		_filmT0 = clock
		if _filmHandle == null:
			_filmHandle = _cardsCall("animated", ["signoff_film", {"owner": "screens"}])
	if _same(sourceId, "satellite"):
		_aAcc = 1.0
	for e in _all():
		if gset.has(e.group):
			_refresh(e)
	game.events.emit("machine:screen_override", {"source": sourceId, "groups": gl.duplicate(), "duration": dur})
	return ov

func _cancel(ov) -> void:
	var i := _ovIndex(ov)
	if i < 0:
		return
	overrides.remove_at(i)
	if _isReady:
		for e in _all():
			if ov.gset.has(e.group):
				_refresh(e)

func _ovIndex(ov) -> int:
	for i in overrides.size():
		if overrides[i] == ov:
			return i
	return -1

# Screen-spawn telegraph (GDD §5.5 / §10.0 priority 1): only that one CRT.
func telegraph(screenSpawnId, seconds = 2.2, opts = {}) -> TeleHandle:
	var inert := TeleHandle.new()
	var e = _entryForSpawn(screenSpawnId)
	if e == null:
		return inert
	if e.tele != null:
		_endTele(e.tele)
	if _posDirty:
		_updateVisibility()
	var tl: Tele = _telePool.pop_back() if not _telePool.is_empty() else _makeTele()
	tl.entry = e
	tl.t0 = clock
	tl.dur = maxf(0.2, float(seconds) if seconds else 2.2)
	tl.last = -1.0
	var sd := randi() & 0xFFFFFFFF
	tl.seed = sd if sd != 0 else 1
	e.tele = tl
	_teles.append(tl)
	var h := TeleHandle.new()
	h._sm = weakref(self)
	h._tl = tl
	if (opts == null or opts.get("sound") != false) and game.audio != null:
		game.audio.play("screen_telegraph", {"pos": e.pos, "tv": true})
	_refresh(e)
	return h

# Latest live frame of an area (pass A when it is the program area, else the MC wall buffer), or null.
func feedTexture(areaId, preferWall = false):
	var a = _rtA[_aFront].texture if _aFrames > 0 and _aArea == areaId and not _rtA.is_empty() else null
	var bb = _rtB.get(areaId)
	var b = bb.rt[_bFront[areaId]].texture if bb != null and bb.frames > 0 else null
	if preferWall:
		return b if b != null else a
	return a if a != null else b

func setInsert(object3d) -> Node3D:
	if insertRoot == null:
		_buildInsert()
	if insertRoot == null:
		return null
	if _insertObj != null and _insertObj != object3d and is_instance_valid(_insertObj) and _insertObj.get_parent() == insertRoot:
		insertRoot.remove_child(_insertObj)
	_insertObj = object3d
	if object3d is Node3D:
		if object3d.get_parent() != null and object3d.get_parent() != insertRoot:
			object3d.get_parent().remove_child(object3d)
		if object3d.get_parent() == null:
			insertRoot.add_child(object3d)
		DAU.setLayerRecursive(object3d, 3)
	return insertRoot

func freezeFlinch():
	_flinchPending = true
	if _aFrames > 0 and _rtFlinch != null:
		return _rtFlinch.texture
	return _cardGet("flinch")

# Rebuilds pass A ('A': program feed + satellite + flinch targets) or pass B ('B': the MC wall buffers) at w x h
# (A/B measurements). Returns false when the size is unchanged.
func setFeedSize(pass_id: String, w: float, h: float) -> bool:
	var P: Dictionary = PASS_B if pass_id == "B" else PASS_A
	var wi := maxi(64, roundi(w))
	var hi := maxi(48, roundi(h))
	if P.w == wi and P.h == hi:
		return false
	P.w = wi
	P.h = hi
	if pass_id == "B":
		_resizeTarget(_hdrB, wi, hi)
		for b in _rtB.values():
			for rt in b.rt:
				_disposeTarget(rt)
		_rtB = {}
		_bFront = {}
	else:
		for rt in [_hdrA, _rtSat, _rtFlinch] + _rtA:
			_resizeTarget(rt, wi, hi)
		_aFrames = 0
		_satFrames = 0
		_flinchTex = null
	_pending.clear()
	for e in _all():
		e.texSet = false
		_refresh(e)
	stats.feedSize = {"A": [PASS_A.w, PASS_A.h], "B": [PASS_B.w, PASS_B.h]}
	return true

# Crash-zooms an area's feed camera toward its look target for `seconds` (the lobby exhibit toy): 0.45 s zoom-in
# with a little overshoot + focus hunt, hold, 0.6 s ease back out. Returns false if that area has no feed camera.
func zoomFeed(area, seconds = 5, opts = {}) -> bool:
	var cam = feedCams.get(area)
	if cam == null:
		return false
	var zoom: float = float(opts.get("zoom", ZOOM.factor)) if opts is Dictionary else ZOOM.factor
	var f: Dictionary = DAU.ud(cam).feed
	f.zoom = {"t0": clock, "dur": maxf(ZOOM["in"] + ZOOM.out, float(seconds) if seconds else 5.0), "k": maxf(1.0, zoom)}
	_aAcc = 1.0
	return true

# -------------------------------------------------------------------------------------- Sign-On CRT effects
# Snake order over the MC wall (top row left -> right, next row right -> left, ...), as the viewer sees it.
func wallOrder() -> Array:
	var w = _wallLayout()
	var out: Array = []
	for i in w.rows.size():
		var row: Array = w.rows[i]
		if i % 2:
			var r := row.duplicate()
			r.reverse()
			out.append_array(r)
		else:
			out.append_array(row)
	return out

# Each CRT warms up in turn: black -> white dot -> line -> picture (overshoot), settling on `settle`.
func warmUp(list_in = null, opts = {}) -> int:
	if opts == null:
		opts = {}
	var start: float = opts.get("start", 0.3)
	var end: float = opts.get("end", 1.8)
	var settle = opts.get("settle", "color_bars")
	var sound = opts.get("sound", "crt_ping")
	var list: Array = list_in if list_in != null else wallOrder()
	var n := list.size()
	if n == 0:
		return 0
	var span := maxf(0.0, end - start - 0.45)
	for i in n:
		var e = list[i]
		e.fx = {"kind": "warm", "t0": clock + start + ((span * i) / (n - 1) if n > 1 else 0.0), "until": clock + end, "settle": settle, "sound": sound, "pinged": false}
	return n

# Quick "line opens" blink on channel change. target: entries or group ids (default every overridable screen).
func blink(target = null, opts = {}) -> int:
	if opts == null:
		opts = {}
	var delay: float = opts.get("delay", 0.0)
	var spread: float = opts.get("spread", 0.0)
	var from = opts.get("from")
	var dur: float = opts.get("dur", 0.2)
	var except = opts.get("except")
	var list = target
	if list == null:
		list = entries(OVERRIDE_GROUPS)
	elif list is String or (list is Array and not list.is_empty() and list[0] is String):
		list = entries(list)
	if _posDirty:
		_updateVisibility()
	var skip := {}
	if except is Array:
		for x in except:
			if x is Entry:
				skip[x.id] = true
	for e in list:
		if skip.has(e.id):
			continue
		var lag: float = minf(spread, e.pos.distance_to(from) / 60.0) if from is Vector3 else randf() * spread
		var t0: float = clock + delay + lag
		e.fx = {"kind": "blink", "t0": t0, "until": t0 + dur + 0.02, "dur": dur}
	return list.size()

# Plays a cue from the nearest matching TV speakers (GDD §10.0 "TV speaker").
func speaker(id, opts = {}):
	var a = game.audio
	if a == null:
		return null
	if opts == null:
		opts = {}
	var near = opts.get("near", 1)
	var gr = opts.get("groups")
	var source = opts.get("source")
	var rest: Dictionary = opts.duplicate()
	rest.erase("near")
	rest.erase("groups")
	rest.erase("source")
	if _posDirty:
		_updateVisibility()
	var cam = _cam()
	var cp: Vector3 = DAU.worldPos(cam) if cam != null else Vector3.ZERO
	var list: Array = entries(gr if gr != null else OVERRIDE_GROUPS).filter(func(e): return (source == null or _same(e.source, source)) and _attached(e.mesh))
	list.sort_custom(func(x, y): return x.pos.distance_squared_to(cp) < y.pos.distance_squared_to(cp))
	var k := mini(maxi(1, int(near)), list.size())
	var first = null
	for i in k:
		var o := rest.duplicate()
		o.pos = list[i].pos
		o.tv = true
		o.vol = float(rest.get("vol", 1.0)) / sqrt(k)
		var v = a.play(id, o)
		if first == null:
			first = v
	if k == 0:
		var o := rest.duplicate()
		o.tv = true
		first = a.play(id, o)
	return first

# ------------------------------------------------------------------------------------------------ resolution
func _resolve(e: Entry):
	if e.tele != null:
		return "telegraph"
	if e.fx != null and e.fx.kind == "warm":
		var k: float = clock - e.fx.t0
		return "black" if k < 0.0 else ("white" if k < 0.17 else e.fx.settle)
	if not NEVER.has(e.group):
		for ov in overrides:
			if ov.gset.has(e.group):
				return ov.source
	var pin = sources.get(e.group)
	if pin != null:
		return pin
	return _defaultSource(e)

func _defaultSource(e: Entry):
	var on := _powered()
	match e.group:
		"scr_telly":
			return null
		"scr_preview":
			return "color_bars"
		"scr_vtr2":
			return "static"
		"scr_mc_feeds", "scr_mc_canned", "scr_decor":
			if not on:
				return "static"
			var s = _slot(e)
			return s if s else "station_id"
		_:
			var area = GROUP_AREA.get(e.group)
			if area == null:
				return "station_id" if on else "static"
			if not on:
				return "feed_lobby" if area == "lobby" else "static"
			return "feed_%s" % area if _area == area else "station_id"

func _slot(e: Entry):
	if e.slot:
		return e.slot
	if e.group == "scr_mc_feeds" or e.group == "scr_mc_canned":
		return _wallLayout().slots.get(e)
	if e.group == "scr_decor":
		return "hullabaloo" if e.id == "ss_studio_b" or e.hootie else null
	return null

func _texFor(src, e: Entry):
	if src == null:
		return KEEP
	if src is Texture2D:
		return src
	if not (src is String or src is StringName):
		return _staticNoise()
	match str(src):
		"black":
			return null
		"telegraph":
			return e.tele.tex if e.tele != null else null
		"white":
			return _white
		"static":
			return _staticNoise()
		"satellite":
			return _rtSat.texture if _satFrames > 0 and _rtSat != null else _card("color_bars", e)
		"flinch":
			return _flinchTex if _flinchTex != null else _card("flinch", e)
		"signoff_film":
			if _filmHandle == null:
				_filmHandle = _cardsCall("animated", ["signoff_film", {"owner": "screens"}])
				_filmT0 = clock
			if _filmHandle == null:
				return _staticNoise()
			if e.visible:
				_use("__film", _filmHandle, e)
			return _filmHandle.texture
	var s := str(src)
	if s.begins_with("feed_"):
		var t = feedTexture(s.substr(5), e.group == "scr_mc_feeds")
		return t if t != null else _card("station_id" if e.group == "scr_mc_feeds" else "static", e)
	return _card(s, e)

func _card(id: String, e):
	if id == "static":
		return _staticNoise()
	var cards = game.cards
	if cards == null:
		return _staticNoise()
	if not _cardCache.has(id):
		var info = _cardsCall("info", [id])
		var c = null
		if info != null:
			var fps = info.get("fps") if (info is Dictionary or info is Object) else null
			c = {"anim": true, "tex": null} if fps else {"anim": false, "tex": _cardGet(id)}
		_cardCache[id] = c
	var cc = _cardCache[id]
	if cc == null:
		return _staticNoise()
	if not cc.anim:
		return cc.tex
	var h = _handles.get(id)
	if h == null:
		h = _cardsCall("animated", [id, {"owner": "screens"}])
		if h == null:
			return _staticNoise()
		_handles[id] = h
	if e != null and e.visible:
		_use(id, h, e)
	return h.texture

func _use(key, h, e: Entry) -> void:
	var d = _inUse.get(key)
	if d == null or e.dist < d[1]:
		_inUse[key] = [h, e.dist]

func _refresh(e: Entry) -> void:
	_applyFx(e)
	var src = _resolve(e)
	e.source = src
	var tex = _texFor(src, e)
	if tex is String:
		return
	_setMap(e, tex)

func _setMap(e: Entry, tex) -> void:
	if e.texSet and e.tex == tex:
		return
	e.tex = tex
	e.texSet = true
	var m = e.mat
	if m == null:
		return
	_matSetMap(m, tex)

func _applyFx(e: Entry) -> void:
	var sx := 1.0
	var sy := 1.0
	var br := 1.0
	var jitter := 0.0
	var bulge := 0.0
	var fx = e.fx
	if fx != null:
		var k: float = clock - fx.t0
		if clock >= fx.until:
			e.fx = null
		elif fx.kind == "warm" and k >= 0.0:
			if not fx.pinged:
				fx.pinged = true
				if fx.sound and game.audio != null:
					game.audio.play(fx.sound, {"pos": e.pos, "vol": 0.6})
			if k < 0.07:
				var u := k / 0.07
				sx = 0.02 + 0.035 * easeOutCubic(u)
				sy = sx
				br = 5.0
			elif k < 0.17:
				sx = 0.055 + 1.0 * easeOutCubic((k - 0.07) / 0.1)
				sy = 0.03
				br = 3.5
			elif k < 0.45:
				var u := (k - 0.17) / 0.28
				sx = 1.055 - 0.055 * easeOutCubic(u)
				sy = 0.03 + 0.97 * easeOutBack(u)
				br = 1.0 + 2.4 * (1.0 - u) * (1.0 - u)
		elif fx.kind == "blink" and k >= 0.0:
			var u := clamp01(k / float(fx.dur))
			sy = 0.03 + 0.97 * easeOutBack(u)
			sx = 1.0 + 0.05 * (1.0 - u)
			br = 1.0 + 2.0 * (1.0 - u) * (1.0 - u)
	var tl = e.tele
	if tl != null:
		var k: float = (clock - tl.t0) / tl.dur
		if k >= 1.0:
			_endTele(tl)
		else:
			if clock - tl.last >= 1.0 / TELE.fps:
				tl.last = clock
				_drawTele(tl, k)
			var ramp := k * k
			jitter = 0.0015 + 0.006 * ramp
			bulge = 0.012 + 0.05 * ramp * (0.6 + 0.4 * sin(clock * 23.0))
			br = 1.0 + 0.6 * ramp
	var mesh := e.mesh
	if not is_instance_valid(mesh):
		return
	var scaled := sx != 1.0 or sy != 1.0
	if scaled or e.scaled:
		mesh.scale = Vector3(e.baseScale.x * sx, e.baseScale.y * sy, e.baseScale.z)
		e.scaled = scaled
	if jitter != 0.0 or e.jittered:
		var p := e.basePos
		if jitter != 0.0:
			p += Vector3((randf() - 0.5) * jitter, (randf() - 0.5) * jitter, 0.0)
		mesh.position = p
		e.jittered = jitter != 0.0
	var m = e.mat
	if m != null:
		if e.baseBright != null and (br != 1.0 or e.touched) and _uHas(m, "uBright"):
			_uSet(m, "uBright", float(e.baseBright) * br)
			e.touched = br != 1.0
		if (bulge != 0.0 or e.bulged) and _uHas(m, "uBulge"):
			if e.baseBulge == null:
				var bb = _uGet(m, "uBulge")
				e.baseBulge = float(bb) if bb != null else 0.0
			_uSet(m, "uBulge", maxf(e.baseBulge, bulge) if bulge != 0.0 else e.baseBulge)
			if _uHas(m, "uWobble"):
				_uSet(m, "uWobble", 0.6 if bulge != 0.0 else 0.0)
			e.bulged = bulge != 0.0

func _clearFx(e: Entry) -> void:
	e.fx = null
	if e.tele != null:
		_endTele(e.tele)
	_applyFx(e)

# ------------------------------------------------------------------------------------------------ telegraph
func _makeTele() -> Tele:
	var tl := Tele.new()
	var cv = _newCanvas(TELE.w, TELE.h)
	if cv != null:
		tl.canvas = cv
		tl.ctx = cv.getContext("2d")
		tl.img = tl.ctx.createImageData(TELE.w, TELE.h)
		tl.tex = cv.texture
	tl.buf.resize(TELE.w * TELE.h * 4)
	return tl

# One telegraph frame (k = 0..1 of the telegraph): chunky contrasty snow with a rolling band, a sickly cyan pulse,
# a dark figure already filling the lower half and pushing up toward the glass (it sways and grows), two glowing
# snow eyes, palms slapping flat on the glass from k 0.45, and tearing scan lines + a flash over the last quarter.
# Drawn at 2x2 texel grain so it reads as "something in the static" from across a room.
func _drawTele(tl: Tele, k: float) -> void:
	var ctx = tl.ctx
	if ctx == null:
		return
	var W: int = TELE.w
	var H: int = TELE.h
	var s: int = tl.seed
	var band: float = fmod(clock * 55.0, H + 24) - 12.0
	var pulse := 0.5 + 0.5 * sin(clock * (9.0 + 10.0 * k))
	var tint := 0.25 + 0.5 * k * pulse # cyan-green cast grows
	var buf := tl.buf
	var tearOn := k > 0.72
	var ct := int(clock * 40.0)
	for by in range(0, H, 2):
		var inBand: bool = by >= band and by < band + 12.0
		var tear: bool = tearOn and ((by * 7 + ct) % 23) < 2
		for bx in range(0, W, 2):
			s ^= (s << 13) & 0xFFFFFFFF
			s ^= s >> 17
			s ^= (s << 5) & 0xFFFFFFFF
			var r: float = ((s >> 24) & 0xff) / 255.0
			var v: float = r * r * 225.0 + 14.0
			if inBand:
				v *= 0.45
			if tear:
				v = 240.0
			var R8 := int(minf(255.0, v * (1.0 - 0.35 * tint)))
			var G8 := int(minf(255.0, v * (1.0 + 0.1 * tint)))
			var B8 := int(minf(255.0, v * (1.0 + 0.18 * tint) + 6.0))
			var c := 0xff000000 | (B8 << 16) | (G8 << 8) | R8
			var i := (by * W + bx) * 4
			buf.encode_u32(i, c)
			buf.encode_u32(i + 4, c)
			buf.encode_u32(i + W * 4, c)
			buf.encode_u32(i + W * 4 + 4, c)
	tl.seed = s if s != 0 else 1
	tl.img.data = buf
	ctx.putImageData(tl.img, 0, 0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	var sc := 0.55 + 0.6 * e                       # already big, then presses in
	var sway := sin(clock * 5.5) * 6.0 * (1.0 - 0.5 * k)
	var cx := W / 2.0 + sway
	var base := H + 6.0
	var R := 21.0 * sc
	var hy := base - 58.0 * sc
	ctx.save()
	ctx.globalAlpha = 0.72 + 0.26 * minf(1.0, k * 2.0)
	ctx.fillStyle = "#0B0714"
	ctx.beginPath()
	ctx.ellipse(cx, hy, R * 1.06, R * 1.02, sin(clock * 3.1) * 0.12, 0, TAU)
	ctx.moveTo(cx - 46.0 * sc, base)
	ctx.quadraticCurveTo(cx - 40.0 * sc, hy + R * 0.95, cx, hy + R * 0.72)
	ctx.quadraticCurveTo(cx + 40.0 * sc, hy + R * 0.95, cx + 46.0 * sc, base)
	ctx.closePath()
	ctx.fill()
	# palms slap flat on the glass, fingers spread (they wobble as it shoves)
	if k > 0.45:
		var r := minf(1.0, (k - 0.45) / 0.18)
		var shove := 1.0 + 0.06 * sin(clock * 21.0)
		for side in [-1.0, 1.0]:
			var hx: float = W / 2.0 + side * W * 0.3
			var hh: float = H * 0.42 + side * 3.0
			var pr := (11.0 * r + 2.0) * shove
			ctx.beginPath()
			ctx.ellipse(hx, hh, pr, pr * 1.15, side * 0.25, 0, TAU)
			ctx.fill()
			for f in 4:
				var a: float = -PI / 2.0 + side * (-0.75 + f * 0.5)
				ctx.beginPath()
				ctx.ellipse(hx + cos(a) * pr * 1.45, hh + sin(a) * pr * 1.45, 2.8 * r + 0.6, 6.5 * r + 0.8, a + PI / 2.0, 0, TAU)
				ctx.fill()
			ctx.beginPath()
			ctx.ellipse(hx - side * pr * 1.1, hh + pr * 0.35, 2.8 * r + 0.6, 6.0 * r + 0.8, side * 1.1, 0, TAU)
			ctx.fill()
	# glowing snow eyes: halo, cyan rim, white core
	var ey := hy - R * 0.05
	var er := R * 0.3 + 1.0
	for side in [-1.0, 1.0]:
		var ex: float = cx + side * R * 0.42
		ctx.globalAlpha = 0.35 + 0.35 * pulse
		var gr = ctx.createRadialGradient(ex, ey, 0, ex, ey, er * 2.6)
		gr.addColorStop(0, Config.PAL.zEyeRim)
		gr.addColorStop(1, "rgba(143,243,255,0)")
		ctx.fillStyle = gr
		ctx.beginPath()
		ctx.arc(ex, ey, er * 2.6, 0, TAU)
		ctx.fill()
		ctx.globalAlpha = 1
		ctx.fillStyle = Config.PAL.zEyeRim
		ctx.beginPath()
		ctx.arc(ex, ey, er, 0, TAU)
		ctx.fill()
		ctx.fillStyle = Config.PAL.zEye
		ctx.beginPath()
		ctx.arc(ex, ey, er * 0.62, 0, TAU)
		ctx.fill()
	ctx.restore()
	# last quarter: horizontal tear slices + a white flash right before it breaks through
	if k > 0.75:
		var q := (k - 0.75) / 0.25
		for i in 3:
			s ^= (s << 13) & 0xFFFFFFFF
			s ^= s >> 17
			s ^= (s << 5) & 0xFFFFFFFF
			var y: int = (s >> 8) % (H - 8)
			var hgt: int = 3 + ((s >> 4) % 6)
			var dx: float = (((s >> 16) % 17) - 8) * (1.0 + 2.0 * q)
			ctx.drawImage(tl.canvas, 0, y, W, hgt, dx, y, W, hgt)
		tl.seed = s if s != 0 else 1
		if q > 0.8:
			ctx.fillStyle = "rgba(235,255,250,%s)" % str((q - 0.8) * 3.0)
			ctx.fillRect(0, 0, W, H)
	if tl.canvas != null and tl.canvas.has_method("redraw"):
		tl.canvas.redraw()

func _endTele(tl) -> void:
	var i := _teles.find(tl)
	if i < 0:
		return
	_teles.remove_at(i)
	var e = tl.entry
	tl.entry = null
	_telePool.append(tl)
	if e != null and e.tele == tl:
		e.tele = null
		if _isReady:
			_refresh(e)

func _entryForSpawn(ssId):
	var direct = byId.get(ssId)
	if direct != null:
		return direct
	var lv = game.level
	var sss = lv.get("screenSpawns") if lv != null else null
	var ss = sss.get(ssId) if sss is Dictionary else null
	if ss == null:
		return null
	if _posDirty:
		_updateVisibility()
	var sp: Vector3 = DAU.v3(ss.pos)
	var best = null
	var bd := 1.3
	for e in _all():
		if NEVER.has(e.group):
			continue
		var d: float = e.pos.distance_to(sp)
		if d < bd:
			bd = d
			best = e
	return best

# ------------------------------------------------------------------------------------------------ wall layout
# Rows of the MC wall (top first), each left -> right as seen from the room; slot sources for its CRTs.
func _wallLayout() -> Dictionary:
	if _wall != null:
		return _wall
	if _posDirty:
		_updateVisibility()
	var list: Array = groups.scr_mc_feeds + groups.scr_mc_canned
	var w := {"rows": [], "slots": {}}
	if not list.is_empty():
		# viewer's right = (-normal) x up, normal = the CRT's facing (local +z once register() ran faceFront)
		var m0: Node3D = list[0].mesh
		var gb: Basis = m0.global_transform.basis if m0.is_inside_tree() else m0.transform.basis
		var n := (gb * Vector3(0, 0, 1)).normalized()
		var right := (-n).cross(UP).normalized()
		if right.length_squared() < 0.5:
			right = Vector3(1, 0, 0)
		var byY := list.duplicate()
		byY.sort_custom(func(a, b): return a.pos.y > b.pos.y)
		for e in byY:
			var row = w.rows.back() if not w.rows.is_empty() else null
			if row != null and absf(row[0].pos.y - e.pos.y) < 0.25:
				row.append(e)
			else:
				w.rows.append([e])
		for row in w.rows:
			row.sort_custom(func(a, b): return a.pos.dot(right) < b.pos.dot(right))
		var feeds: Array = groups.scr_mc_feeds.duplicate()
		feeds.sort_custom(func(a, b): return a.pos.dot(right) < b.pos.dot(right))
		for i in feeds.size():
			w.slots[feeds[i]] = "feed_%s" % MC_FEEDS[i % MC_FEEDS.size()]
		var lv = game.level
		var ss: Array = []
		var sss = lv.get("screenSpawns") if lv != null else null
		if sss is Dictionary:
			for sid in ["ss_mc_w", "ss_mc_e"]:
				if sss.get(sid) != null:
					ss.append(DAU.v3(sss[sid].pos))
		# canned rows count top to bottom skipping the feeds row (the middle one on the 4 x 3 wall)
		var k := 0
		for row in w.rows:
			if not row.any(func(x): return x.group == "scr_mc_canned"):
				continue
			var grid: Array = CANNED_GRID[mini(k, CANNED_GRID.size() - 1)]
			k += 1
			for ci in row.size():
				var e = row[ci]
				if e.group != "scr_mc_canned":
					continue
				var isSpawn: bool = e.id == "ss_mc_w" or e.id == "ss_mc_e" or ss.any(func(p): return p.distance_to(e.pos) < 0.6)
				w.slots[e] = "static" if isSpawn else grid[ci % grid.size()]
	_wall = w
	return w

# ------------------------------------------------------------------------------------------------ visibility
func _updateVisibility() -> void:
	var g = game
	var cam = _cam()
	var wasDirty := _posDirty
	_posDirty = false
	var planes: Array = []
	var cp := Vector3.ZERO
	if cam != null and cam.is_inside_tree():
		planes = cam.get_frustum()
		cp = cam.global_position
	var lv = g.level
	var sss = lv.get("screenSpawns") if lv != null else null
	var hoot = sss.get("ss_studio_b") if sss is Dictionary else null
	var hootPos = DAU.v3(hoot.pos) if hoot != null else null
	for e in _all():
		var mesh: Node3D = e.mesh
		if not is_instance_valid(mesh) or mesh.get_parent() == null:
			e.visible = false
			e.near = false
			continue
		e.pos = DAU.worldPos(mesh)
		var d: float = e.pos.distance_to(cp)
		e.dist = d
		var on: bool = not planes.is_empty() and d < VIS.range and _attached(mesh) and _inFrustum(mesh, planes)
		e.visible = on
		e.near = on and d < PASS_A.range
		if wasDirty and e.group == "scr_decor":
			e.hootie = hootPos != null and e.pos.distance_to(hootPos) < 1.2
	if wasDirty:
		_wall = null

# THREE Frustum.intersectsObject: the mesh's bounding sphere against the six planes.
static func _inFrustum(mesh: Node3D, planes: Array) -> bool:
	var c := DAU.worldPos(mesh)
	var r := 0.5
	if mesh is VisualInstance3D:
		var bb: AABB = (mesh as VisualInstance3D).get_aabb()
		var gt := mesh.global_transform
		c = gt * bb.get_center()
		var sc := gt.basis.get_scale().abs()
		r = bb.size.length() * 0.5 * maxf(sc.x, maxf(sc.y, sc.z))
	for p in planes:
		var pl: Plane = p
		if pl.distance_to(c) > r:
			return false
	return true

func _attached(o) -> bool:
	var scene = game.scene
	if scene == null or not is_instance_valid(o) or not o.is_inside_tree():
		return false
	if o is Node3D and not o.is_visible_in_tree():
		return false
	return scene == o or scene.is_ancestor_of(o)

func _anyNear(group: String, source = null) -> bool:
	for e in groups[group]:
		if e.near and (source == null or _same(e.source, source)):
			return true
	return false

# ------------------------------------------------------------------------------------------------ passes
func _schedule(dt: float) -> void:
	var powered := _powered()
	var area = _area
	# pass A (or the satellite insert)
	_jobA = null
	_aAcc = minf(1.0, _aAcc + dt * PASS_A.fps)
	if not _same(area, _lastArea):
		_lastArea = area
		_aAcc = 1.0
	var sat := false
	for o in overrides:
		if _same(o.source, "satellite"):
			sat = true
			break
	if sat:
		sat = OVERRIDE_GROUPS.any(func(id): return _anyNear(id, "satellite"))
	if _aAcc >= 1.0:
		if sat:
			_jobA = "satellite"
		elif area != null and feedCams.has(area) and GROUP_AREA.has("scr_feed_%s" % area) and (powered or area == "lobby") \
				and _anyNear("scr_feed_%s" % area, "feed_%s" % area):
			_jobA = area
		if _jobA != null:
			_aAcc = 0.0
	# pass B (MC wall feed row)
	_jobB = null
	if powered and area == "master_control" and _anyNear("scr_mc_feeds"):
		_bAcc = minf(1.0, _bAcc + dt * PASS_B.rate)
		if _bAcc >= 1.0:
			for i in MC_FEEDS.size():
				var a: String = MC_FEEDS[(_bNext + i) % MC_FEEDS.size()]
				if not feedCams.has(a):
					continue
				_jobB = a
				_bNext = (_bNext + i + 1) % MC_FEEDS.size()
				break
			if _jobB != null:
				_bAcc -= 1.0
	else:
		_bAcc = 1.0

# JS render.addPrePass callback: runs at the end of lateUpdate. Commits last frame's renders, then issues this
# frame's (the SubViewports render before the main view at the end of the frame).
func _prePass() -> void:
	_commit()
	if _jobA == null and _jobB == null and not _flinchPending:
		return
	var st = game.state
	if st != "playing" and st != "down":
		_jobA = null
		_jobB = null
		return
	if _hdrA == null:
		_jobA = null
		_jobB = null
		_flinchPending = false
		return
	var n := 0
	if _same(_jobA, "satellite"):
		_renderSat()
		n += 1
	elif _jobA != null:
		_renderA(_jobA)
		n += 1
	if _jobB != null:
		_renderB(_jobB)
		n += 1
	if _flinchPending:
		_composeFlinch()
	_jobA = null
	_jobB = null
	stats.maxPerFrame = maxi(stats.maxPerFrame, n)

func _commit() -> void:
	if _pending.is_empty():
		return
	var jobs := _pending
	_pending = []
	for p in jobs:
		match p.kind:
			"A":
				var back: int = p.back
				_aFront = back
				_aArea = p.area
				_aFrames += 1
				stats.passA += 1
				stats.feedDraws = _drawCalls(_hdrA)
				var tex = _rtA[back].texture
				var src := "feed_%s" % p.area
				for e in _all():
					if _same(e.source, src) and e.group != "scr_mc_feeds":
						_setMap(e, tex)
			"B":
				var b = _rtB.get(p.area)
				if b == null:
					continue
				_bFront[p.area] = p.back
				b.frames += 1
				stats.passB += 1
				stats.feedDraws = _drawCalls(_hdrB)
				var src := "feed_%s" % p.area
				for e in groups.scr_mc_feeds:
					if _same(e.source, src):
						_setMap(e, b.rt[p.back].texture)
			"sat":
				_satFrames += 1
				stats.sat += 1
				for e in _all():
					if _same(e.source, "satellite"):
						_setMap(e, _rtSat.texture)
			"flinch":
				_flinchTex = _rtFlinch.texture
				stats.flinch += 1
				for e in _all():
					if _same(e.source, "flinch"):
						_setMap(e, _flinchTex)

func _renderA(area: String) -> void:
	var cam = feedCams[area]
	var back := 1 - _aFront
	_renderFeed(cam, _rtA[back], _hdrA)
	_pending.append({"kind": "A", "area": area, "back": back})

func _renderB(area: String) -> void:
	var cam = feedCams[area]
	var b = _rtB.get(area)
	if b == null:
		b = {"rt": [_target(PASS_B.w, PASS_B.h, 0, false), _target(PASS_B.w, PASS_B.h, 0, false)], "frames": 0}
		_rtB[area] = b
		_bFront[area] = 0
	var back: int = 1 - _bFront[area]
	_renderFeed(cam, b.rt[back], _hdrB)
	_pending.append({"kind": "B", "area": area, "back": back})

# One feed-camera render into `hdr`, graded into `rt`. (See the header for what the JS also toggled around it.)
func _renderFeed(cam: Camera3D, rt: Dictionary, hdr: Dictionary) -> void:
	_isolate(DAU.ud(cam).feed.area)
	_aimFeed(cam)
	_swapZombies(true)
	var c: Camera3D = hdr.cam
	c.global_transform = cam.global_transform if cam.is_inside_tree() else cam.transform
	c.fov = cam.fov
	c.near = cam.near
	c.far = cam.far
	c.cull_mask = cam.cull_mask
	c.environment = _feedEnv()
	hdr.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_grade(hdr, rt, GRADE.feed * _exposure)

# Shows `area` (its root + its doors: level.setAreaVisible when the level has it) for this frame's renders (see the
# header); it runs from the render pre-pass, after level.lateUpdate's culling. null (the insert studio, layer 3
# only) changes nothing. _restoreVis() runs once the frame has been drawn.
func _isolate(area) -> void:
	var lv = game.level
	if lv == null or area == null:
		return
	var saved := _visSave
	var show := func(o):
		if o is Node3D and not o.visible:
			saved.append(o)
			saved.append(o.visible)
			o.visible = true
	var roots = lv.get("areaRoots")
	if roots is Dictionary:
		show.call(roots.get(area))
	if lv.has_method("setAreaVisible") and roots is Dictionary and roots.has(area):
		# the level's own switch also shows the door groups of that area (their states were saved just below)
		var doors0 = lv.get("doors")
		if doors0 is Dictionary:
			for d in doors0.values():
				var dg = d.get("group") if d != null else null
				if dg is Node3D and not dg.visible and (d.get("areas") is Array and d.areas.has(area)):
					saved.append(dg)
					saved.append(false)
		lv.setAreaVisible(area, true)
	var areas = lv.get("areas")
	var ar = areas.get(area) if areas is Dictionary else null
	var doorIds = ar.get("doors") if ar is Dictionary else null
	var doors = lv.get("doors")
	if doorIds is Array and doors is Dictionary:
		for id in doorIds:
			var d = doors.get(id)
			if d != null:
				show.call(d.get("group"))
	if not saved.is_empty() and not RenderingServer.frame_post_draw.is_connected(_restoreVis):
		RenderingServer.frame_post_draw.connect(_restoreVis, CONNECT_ONE_SHOT)

func _restoreVis() -> void:
	var saved := _visSave
	var i := saved.size() - 2
	while i >= 0:
		if is_instance_valid(saved[i]):
			saved[i].visible = saved[i + 1]
		i -= 2
	saved.clear()

func _grade(src: Dictionary, out: Dictionary, exposure: float) -> void:
	var m: ShaderMaterial = out.mat
	m.set_shader_parameter("tSrc", src.texture)
	m.set_shader_parameter("uTexel", Vector2(1.0 / src.width, 1.0 / src.height))
	m.set_shader_parameter("uExposure", exposure)
	m.set_shader_parameter("uSat", GRADE.sat)
	m.set_shader_parameter("uContrast", GRADE.contrast)
	_blit(out)

func _blit(out: Dictionary) -> void:
	out.vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _renderSat() -> void:
	if insertCamera == null:
		return
	var c: Camera3D = _hdrA.cam
	c.global_transform = insertCamera.global_transform if insertCamera.is_inside_tree() else insertCamera.transform
	c.fov = insertCamera.fov
	c.near = insertCamera.near
	c.far = insertCamera.far
	c.cull_mask = insertCamera.cull_mask
	c.environment = _feedEnv()
	_hdrA.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_grade(_hdrA, _rtSat, GRADE.insert * _exposure)
	_pending.append({"kind": "sat"})

func _composeFlinch() -> void:
	_flinchPending = false
	if _aFrames == 0 or _rtFlinch == null:
		_flinchTex = null
		return
	var m: ShaderMaterial = _rtFlinch.mat
	m.set_shader_parameter("tSrc", _rtA[_aFront].texture)
	_blit(_rtFlinch)
	_pending.append({"kind": "flinch"})

# samples > 0: an HDR scene target (3D SubViewport + camera); else a graded picture (2D SubViewport + quad).
# -> { vp, texture, width, height, cam | rect + mat }
func _target(w: int, h: int, samples: int, depth: bool = true, shader: Shader = null) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.gui_disable_input = true
	vp.transparent_bg = false
	var out := {"vp": vp, "width": w, "height": h}
	if samples > 0 and depth:
		vp.name = "screens_hdr_%d" % _holder.get_child_count()
		vp.use_hdr_2d = true
		vp.msaa_3d = Viewport.MSAA_4X
		if game.scene != null and game.scene.is_inside_tree():
			vp.world_3d = game.scene.get_world_3d()
		var mainView = game.render.get("view") if game.render != null else null
		if mainView is SubViewport:
			vp.positional_shadow_atlas_size = mainView.positional_shadow_atlas_size
		var cam := Camera3D.new()
		cam.name = "cam"
		cam.current = true
		vp.add_child(cam)
		out.cam = cam
	else:
		vp.name = "screens_pic_%d" % _holder.get_child_count()
		vp.disable_3d = true
		var rect := ColorRect.new()
		rect.color = Color.BLACK
		rect.position = Vector2.ZERO
		rect.size = Vector2(w, h)
		var m := ShaderMaterial.new()
		m.shader = shader if shader != null else _gradeShader
		rect.material = m
		vp.add_child(rect)
		out.rect = rect
		out.mat = m
	_holder.add_child(vp)
	out.texture = vp.get_texture()
	return out

func _resizeTarget(t, w: int, h: int) -> void:
	if t == null:
		return
	t.vp.size = Vector2i(w, h)
	t.width = w
	t.height = h
	if t.has("rect"):
		t.rect.size = Vector2(w, h)

func _disposeTarget(t) -> void:
	if t != null and is_instance_valid(t.vp):
		t.vp.queue_free()

func _buildTargets() -> void:
	if _holder == null or _hdrA != null:
		return
	_gradeShader = Shader.new()
	_gradeShader.code = GRADE_FRAG
	_flinchShader = Shader.new()
	_flinchShader.code = FLINCH_FRAG
	# scene renders (MSAA HDR) -> graded display-referred pictures the CRTs sample (2-deep swap chains).
	# The HDR targets are created first: they render before the pictures that read them.
	_hdrA = _target(PASS_A.w, PASS_A.h, 4)
	_hdrB = _target(PASS_B.w, PASS_B.h, 4)
	_rtA = [_target(PASS_A.w, PASS_A.h, 0, false), _target(PASS_A.w, PASS_A.h, 0, false)]
	_rtSat = _target(PASS_A.w, PASS_A.h, 0, false)
	_rtFlinch = _target(PASS_A.w, PASS_A.h, 0, false, _flinchShader)
	for t in _rtA + [_rtSat]:
		t.mat.set_shader_parameter("tSrc", _hdrA.texture)

func _buildHolder() -> void:
	if _holder != null:
		return
	_holder = Node.new()
	_holder.name = "screens_passes"
	var host: Node = game if game is Node else null
	if host == null:
		return
	host.add_child(_holder)
	_camHolder = SubViewport.new()
	_camHolder.name = "screens_cams"
	_camHolder.size = Vector2i(4, 4)
	_camHolder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camHolder.gui_disable_input = true
	if game.scene != null and game.scene.is_inside_tree():
		_camHolder.world_3d = game.scene.get_world_3d()
	_holder.add_child(_camHolder)

# The feed cameras' Environment: render.envFeed (the shared World3D's environment: linear tone mapping at exposure
# 1, no bloom). Without it, a copy of the world's Environment with those settings (re-synced once a second).
# _exposure = the main tone-mapping exposure (JS renderer.toneMappingExposure).
func _feedEnv():
	var r = game.render
	var ef = r.get("envFeed") if r != null else null
	if ef is Environment:
		_exposure = _toneExposure()
		return ef
	var now: float = float(game.time.realNow)
	if _env != null and now - _envAt < 1.0 and now >= _envAt:
		return _env
	_envAt = now
	var src: Environment = null
	if game.scene != null and game.scene.is_inside_tree():
		var w: World3D = game.scene.get_world_3d()
		if w != null:
			src = w.environment if w.environment != null else w.fallback_environment
	if src == null:
		_env = null
		_exposure = 1.0
		return null
	_exposure = src.tonemap_exposure * _toneExposure()
	var env: Environment = src.duplicate()
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.glow_enabled = false
	env.adjustment_enabled = false
	_env = env
	return env

# JS renderer.toneMappingExposure (render.js: 1.05; render.gd applies it in its grade shader, uExposure).
func _toneExposure() -> float:
	var r = game.render
	if r == null:
		return 1.05
	var te = r.get("toneMappingExposure")
	if te is float or te is int:
		return float(te)
	var gr = r.get("grade")
	if gr is ShaderMaterial:
		var v = gr.get_shader_parameter("uExposure")
		if v is float or v is int:
			return float(v)
	return 1.05

static func _drawCalls(t) -> int:
	if t == null or not is_instance_valid(t.vp):
		return 0
	return RenderingServer.viewport_get_render_info(t.vp.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)

# ------------------------------------------------------------------------------------------------ feed cameras
func _buildFeedCams() -> void:
	var lv = game.level
	var anchors = lv.get("anchors") if lv != null else null
	if not (anchors is Dictionary):
		anchors = {}
	var i := 0
	for id in anchors:
		var a = anchors[id]
		if not (id is String or id is StringName) or not str(id).begins_with("feed_cam_") or a == null or not a.get("area"):
			continue
		var area := str(a.area)
		var fov: float = float(a.get("fov")) if a.get("fov") else 55.0
		var cam := Camera3D.new()
		cam.name = "feedcam_%s" % area
		cam.fov = fov
		cam.near = 0.08
		cam.far = 120.0 if area == "yard" else 40.0
		cam.cull_mask = 0b111 | (1 << FEED_LAYER) # world + zombies + on-TV-only (+ the feed marker bit)
		var apos: Vector3 = DAU.v3(a.pos)
		var ry: float = float(a.get("rotY")) if a.get("rotY") else 0.0
		var target: Vector3 = DAU.v3(a.target) if a.get("target") != null else apos + Vector3(-sin(ry), 0, -cos(ry))
		var hHalf := atan(tan(deg_to_rad(fov) / 2.0) * (float(PASS_A.w) / PASS_A.h))
		var panAmp := minf(PAN.amp, PAN.keep * hHalf)
		DAU.ud(cam)["feed"] = {"id": str(id), "area": area, "pos": apos, "target": target, "fov": fov, "panAmp": panAmp, "zf": 1.0, "zoom": null,
			"phase": i * 1.7, "prop": null, "head": null, "headBase": 0.0, "lens": null, "tally": null, "tallyOn": null, "lamps": null, "restDir": null}
		i += 1
		cam.transform = _lookAt(apos, target)
		if _camHolder != null:
			_camHolder.add_child(cam)
		feedCams[area] = cam
	_findCamProps()

# Camera transform at `eye` looking at `at` (three's camera.lookAt).
static func _lookAt(eye: Vector3, at: Vector3) -> Transform3D:
	var d := at - eye
	if d.length_squared() < 1e-12:
		return Transform3D(Basis(), eye)
	var up := UP if absf(d.normalized().dot(UP)) < 0.9999 else Vector3(0, 0, 1)
	return Transform3D(Basis.looking_at(d, up), eye)

# Physical feed-camera props placed by the rooms at the feed_cam_* anchors: lens position, pan head, tally.
func _findCamProps() -> void:
	var lv = game.level
	var root = lv.get("root") if lv != null else null
	if not (root is Node):
		return
	var found: Array = []
	DAU.traverse(root, func(o):
		if CAM_PROPS.has(_udGet(o, "id")):
			found.append(o))
	_camProps = found
	for cam in feedCams.values():
		var f: Dictionary = DAU.ud(cam).feed
		var best = null
		var bd := 1.6
		for p in found:
			var v := DAU.worldPos(p)
			var d := Vector2(v.x - f.pos.x, v.z - f.pos.z).length()
			if d < bd:
				bd = d
				best = p
		if best == null:
			continue
		var bu := DAU.ud(best)
		var P = bu.get("parts") if bu.get("parts") is Dictionary else {}
		f.prop = best
		f.head = P.get("head") if P.get("head") is Node3D else null
		if f.head != null:
			f.head.rotation_order = EULER_ORDER_XYZ
		f.headBase = f.head.rotation.y if f.head != null else 0.0
		f.lens = P.get("lensTip") if P.get("lensTip") is Node3D else null
		f.tally = P.get("tally")
		f.lamps = _lampMats(bu.get("lampMats"))
		f.tallyOn = null
		# rest aim from the lens (head at its base yaw) through the look target: the lens sits up to ~1.3 m off the
		# anchor, and aiming along anchor -> target from there left the subject (the EE puppets) well off-centre
		f.restDir = null
		if f.lens != null:
			if f.head != null:
				f.head.rotation.y = f.headBase
			f.restDir = f.target - DAU.worldPos(f.lens)

func _zoomOf(f: Dictionary) -> float:
	var z = f.zoom
	if z == null:
		return 1.0
	var k: float = clock - z.t0
	if k >= z.dur:
		f.zoom = null
		return 1.0
	var u: float
	if k < ZOOM["in"]:
		u = easeOutBack(k / ZOOM["in"], 1.4)
	elif k > z.dur - ZOOM.out:
		var v: float = (z.dur - k) / ZOOM.out
		u = v * v * (3.0 - 2.0 * v)
	else:
		u = 1.0 + 0.025 * sin((k - ZOOM["in"]) * 7.0) * exp(-(k - ZOOM["in"]) * 2.5) # focus hunt
	return 1.0 + (z.k - 1.0) * u

func _pan(f: Dictionary) -> float:
	var amp: float = f.panAmp if f.get("panAmp") != null else PAN.amp
	var zf: float = f.zf if f.get("zf") else 1.0
	return (amp / zf) * sin((clock / PAN.period) * TAU + f.phase)

func _aimFeed(cam: Camera3D) -> void:
	var f: Dictionary = DAU.ud(cam).feed
	if f.get("zf") == null:
		f.zf = _zoomOf(f)
	var fov: float = f.fov / f.zf
	if absf(cam.fov - fov) > 1e-3:
		cam.fov = fov
	var ang := _pan(f)
	if f.head != null and is_instance_valid(f.head):
		f.head.rotation.y = f.headBase + ang
	var v: Vector3 = DAU.worldPos(f.lens) if f.lens != null and is_instance_valid(f.lens) else f.pos
	var d: Vector3 = f.restDir if f.restDir != null else f.target - f.pos
	d = d.rotated(UP, ang)
	cam.transform = _lookAt(v, v + d)

func _updateFeedProps() -> void:
	var powered := _powered()
	var so = game.signon
	for cam in feedCams.values():
		var f: Dictionary = DAU.ud(cam).feed
		f.zf = _zoomOf(f)
		if f.prop == null:
			continue
		if f.head != null and is_instance_valid(f.head):
			f.head.rotation.y = f.headBase + _pan(f)
		if f.tally != null and f.lamps != null:
			var on: bool = f.area == "lobby"
			if powered:
				on = bool(so.waveReached(f.pos)) if so != null and so.has_method("waveReached") else true
			if f.tallyOn == null or on != f.tallyOn:
				f.tallyOn = on
				_setMat(f.tally, f.lamps.on if on else f.lamps.off)
				if on and powered and f.area != "lobby" and game.audio != null:
					game.audio.play("onair_clack", {"pos": f.pos, "vol": 0.4})

# ------------------------------------------------------------------------------------------------ insert studio
# The set (cyclorama dome, chrome turntable drum, red top, glowing rim, floor disc) is the Blender asset
# blender/runtime/screens.py -> res://assets/runtime/screens/insert_studio.glb (static geometry, SPEC §4); the
# LIVE VIA SATELLITE super glued in front of the camera is a quad.
func _buildInsert() -> void:
	if insertRoot != null:
		return
	var g = game
	if g.scene == null:
		return
	var set_ := DAU.node3d("insert_studio")
	set_.position = INSERT.pos
	if ResourceLoader.exists(INSERT_GLB):
		var ps = load(INSERT_GLB)
		if ps is PackedScene:
			var inst: Node = ps.instantiate()
			_convertMaterials(inst)
			set_.add_child(inst)
	else:
		push_warning("[screens] %s missing (run blender/build_all.py --only runtime)" % INSERT_GLB)
	var spin := DAU.node3d("insert_turntable")
	spin.position.y = 1.05
	set_.add_child(spin)
	# insert camera + the LIVE VIA SATELLITE super glued in front of it
	var cam := Camera3D.new()
	cam.name = "insert_cam_uplink"
	cam.fov = INSERT.fov
	cam.near = 0.05
	cam.far = 30.0
	var eye := Vector3(INSERT.pos.x + INSERT.eye[0], INSERT.eye[1], INSERT.pos.z + INSERT.eye[2])
	var look := Vector3(INSERT.pos.x + INSERT.look[0], INSERT.look[1], INSERT.pos.z + INSERT.look[2])
	cam.transform = _lookAt(eye, look)
	var d := 0.3
	var hh := 2.0 * d * tan(deg_to_rad(INSERT.fov / 2.0))
	var superMat := StandardMaterial3D.new()
	superMat.resource_name = "screens:satellite_super"
	superMat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	superMat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	superMat.no_depth_test = true
	superMat.disable_fog = true
	superMat.render_priority = Material.RENDER_PRIORITY_MAX
	superMat.albedo_texture = _cardGet("satellite_super")
	var q := QuadMesh.new()
	q.size = Vector2(hh * (4.0 / 3.0), hh)
	var sup := MeshInstance3D.new()
	sup.name = "satellite_super"
	sup.mesh = q
	sup.material_override = superMat
	sup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sup.position.z = -d
	cam.add_child(sup)
	DAU.setLayerRecursive(set_, 3)
	DAU.setLayerRecursive(cam, 3)
	cam.cull_mask = 1 << 3
	g.scene.add_child(set_)
	if _camHolder != null:
		_camHolder.add_child(cam)
	insertRoot = spin
	insertCamera = cam
	_insertSet = set_

# A Blender runtime asset: node "da" extras -> userData (+ visible / castShadow), Euler order XYZ, and every material
# spec (material "extras" meta, key "da") built through game.mats.fromSpec (SPEC §5.4 / §5.5).
func _convertMaterials(root: Node) -> void:
	var M = game.mats
	DAU.traverse(root, func(o):
		if o is Node3D:
			o.rotation_order = EULER_ORDER_XYZ
		var nx = o.get_meta("extras") if o.has_meta("extras") else null
		if nx is Dictionary and nx.has("da"):
			var da = JSON.parse_string(nx.da) if nx.da is String else nx.da
			if da is Dictionary:
				DAU.ud(o).merge(da, true)
				if da.get("visible") == false and o is Node3D:
					o.visible = false
				if da.has("castShadow") and o is GeometryInstance3D:
					o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if da.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not (o is MeshInstance3D) or o.mesh == null or M == null or not M.has_method("fromSpec"):
			return
		for si in o.mesh.get_surface_count():
			var m = o.mesh.surface_get_material(si)
			if m == null or not m.has_meta("extras"):
				continue
			var ex = m.get_meta("extras")
			var spec = ex.get("da") if ex is Dictionary else null
			if spec is String:
				spec = JSON.parse_string(spec)
			if spec is Dictionary:
				var nm = M.fromSpec(spec, m)
				if nm != null:
					o.set_surface_override_material(si, nm))

# ------------------------------------------------------------------------------------------------ human skin
# The feed variant of a zombie material (see the header): { kind: 'shader', shader } for a ShaderMaterial (its
# shader with the skin swap on feed cameras), { kind: 'overlay', mat } for the static-snow eye material, or null.
func _variant(mat):
	if mat == null or not (mat is Material):
		return null
	if _variants.has(mat):
		return _variants[mat]
	var v = null
	if _isStaticNoiseMat(mat):
		var em = _eyeMaterial()
		if em != null:
			v = {"kind": "overlay", "mat": em}
	elif mat is ShaderMaterial and mat.shader != null:
		var sh = _skinShader(mat.shader)
		if sh != null:
			v = {"kind": "shader", "shader": sh}
	_variants[mat] = v
	return v

func _skinShader(sh: Shader):
	if _skinShaders.has(sh):
		return _skinShaders[sh]
	for other in _skinShaders.values():
		if other == sh:
			return sh # already a feed variant
	var out = null
	var code := sh.code
	if code.find("shader_type spatial") >= 0 and code.find("da_feed_skin") < 0:
		var fi := code.find("void fragment()")
		var at := code.find(SKIN_AT, fi) if fi >= 0 else -1
		if at >= 0:
			var ls := code.rfind("\n", at) + 1
			out = Shader.new()
			out.code = code.substr(0, fi) + SKIN_SWAP + "\n" + code.substr(fi, ls - fi) + SKIN_DIFFUSE + code.substr(ls)
		elif fi >= 0:
			var open := code.find("{", fi)
			var depth := 0
			var close := -1
			for i in range(open, code.length()):
				var ch := code[i]
				if ch == "{":
					depth += 1
				elif ch == "}":
					depth -= 1
					if depth == 0:
						close = i
						break
			if open >= 0 and close > open:
				var nc := code.substr(0, fi) + SKIN_SWAP + "\n" + code.substr(fi, close - fi) + SKIN_CALL + code.substr(close)
				out = Shader.new()
				out.code = nc
	_skinShaders[sh] = out
	return out

func _isStaticNoiseMat(mat: Material) -> bool:
	var sn = _staticNoise()
	if sn == null:
		return false
	if mat is BaseMaterial3D:
		return mat.albedo_texture == sn
	if mat is ShaderMaterial and mat.shader != null:
		for u in mat.shader.get_shader_uniform_list():
			var val = mat.get_shader_parameter(u.name)
			if val is Texture2D and val == sn:
				return true
	return false

func _eyeMaterial():
	if _eyeMat != null:
		return _eyeMat
	var cv = _newCanvas(64, 64)
	if cv == null:
		return null
	var c = cv.getContext("2d")
	c.fillStyle = "#F6F3EC"
	c.fillRect(0, 0, 64, 64)
	c.fillStyle = "#6B4A2A"
	c.beginPath()
	c.arc(32, 34, 15, 0, TAU)
	c.fill()
	c.fillStyle = "#1E1624"
	c.beginPath()
	c.arc(32, 34, 8, 0, TAU)
	c.fill()
	c.fillStyle = "#FFFFFF"
	c.beginPath()
	c.arc(27, 28, 4, 0, TAU)
	c.fill()
	if cv.has_method("redraw"):
		cv.redraw()
	_eyeCanvas = cv
	var sh := Shader.new()
	sh.code = EYE_OVERLAY
	var m := ShaderMaterial.new()
	m.resource_name = "zombie_eye:feed"
	m.shader = sh
	m.set_shader_parameter("tEye", cv.texture)
	_eyeMat = m
	return _eyeMat

# JS swapped the variants in around each feed render. Here the variants are permanent (they only differ on feed
# cameras); this makes sure every live zombie has them (zombies built before init / re-dressed ones).
func _swapZombies(on: bool) -> void:
	if not on:
		return
	var zs = game.zombies.get("alive") if game.zombies != null else null
	if not (zs is Array) or zs.is_empty():
		return
	for z in zs:
		_prepZombie(z)

# Applies the feed variants of a new zombie's materials.
func _prepZombie(z) -> void:
	if z == null:
		return
	var grp = z.get("group")
	if not (grp is Node) or grp.has_meta("da_feedskin"):
		return
	grp.set_meta("da_feedskin", true)
	DAU.traverse(grp, func(o):
		if not (o is MeshInstance3D) or o.mesh == null:
			return
		for si in o.mesh.get_surface_count():
			var m = o.get_active_material(si)
			var v = _variant(m)
			if v == null:
				continue
			if v.kind == "shader":
				if m.shader != v.shader:
					m.shader = v.shader
			elif v.kind == "overlay" and o.material_overlay == null:
				o.material_overlay = v.mat)

# ------------------------------------------------------------------------------------------------ automatic
func _onRoundEnd(p) -> void:
	if _auto.hull != null:
		_auto.hull.cancel()
		_auto.hull = null
	if not _powered():
		return
	var rnd: int = int(p.get("round", 0)) if p is Dictionary and p.get("round") else 0
	var nx = p.get("next") if p is Dictionary else null
	var n = game.get("net")
	# MP: a client's rounds mirror may lag; the host's round:end payload carries the next round's special
	var hull := _same(nx.get("special"), "hullabaloo") if n != null and n.inGame and nx is Dictionary else _nextIsHullabaloo(rnd)
	var R: Dictionary = Config.T.rounds
	if _auto.inter != null:
		_auto.inter.cancel()
	_auto.inter = override("hullabaloo", DECOR_CANNED, R.hullabaloo.intermission, PRIORITY.hullabaloo) if hull \
		else override("right_back", DECOR_CANNED, R.intermission, PRIORITY.intermission)

func _onRoundStart(p) -> void:
	if _auto.inter != null:
		_auto.inter.cancel()
		_auto.inter = null
	if p is Dictionary and _same(p.get("special"), "hullabaloo") and _powered():
		if _auto.hull != null:
			_auto.hull.cancel()
		_auto.hull = override("hullabaloo", DECOR_CANNED, INF, PRIORITY.hullabaloo)

func _nextIsHullabaloo(round_n: int) -> bool:
	var r = game.rounds
	if r == null:
		return false
	var ns = r.nextSpecial() if r.has_method("nextSpecial") else r.get("nextSpecial")
	if ns != null:
		return _same(ns, "hullabaloo")
	if r.has_method("isHullabaloo"):
		return bool(r.isHullabaloo(round_n + 1))
	if r.has_method("specialFor"):
		return _same(r.specialFor(round_n + 1), "hullabaloo")
	return false

# ------------------------------------------------------------------------------------------------ helpers
func _powered() -> bool:
	return game.machines != null and bool(game.machines.powerOn)

func _playerArea():
	var p = game.player
	if p == null:
		return null
	var pp = p.get("pos")
	if not (pp is Vector3):
		return null
	var a = p.get("area")
	if a:
		return a
	var lv = game.level
	return lv.areaAt(pp.x, pp.z) if lv != null and lv.has_method("areaAt") else null

func _expand(ids) -> Array:
	var out: Array = []
	var list: Array = ids if ids is Array else ([ids] if ids != null else [])
	for id in list:
		if not (id is String or id is StringName):
			continue
		var s := str(id)
		if s.ends_with("*"):
			var pre := s.substr(0, s.length() - 1)
			for g in SCREEN_GROUPS:
				if g.begins_with(pre):
					out.append(g)
		else:
			out.append(s)
	return out

func _all() -> Array:
	var out: Array = []
	for id in SCREEN_GROUPS:
		out.append_array(groups[id])
	return out

func _entryOfMesh(mesh):
	var id = _udGet(mesh, "screenEntry")
	var e = byId.get(id) if id != null else null
	return e if e != null and e.mesh == mesh else null

func _remove(e: Entry) -> void:
	var list: Array = groups[e.group]
	var i := list.find(e)
	if i >= 0:
		list.remove_at(i)
	byId.erase(e.id)
	if e.tele != null:
		_endTele(e.tele)
	e.fx = null
	if is_instance_valid(e.mesh):
		if e.scaled:
			e.mesh.scale = e.baseScale
		if e.jittered:
			e.mesh.position = e.basePos
		if e.mat != null and e.baseBright != null and e.touched and _uHas(e.mat, "uBright"):
			_uSet(e.mat, "uBright", e.baseBright)
		if e.mesh.has_meta("userData"):
			e.mesh.get_meta("userData").erase("screenEntry")
	_wall = null

# CRTs built without game.props.place (userData.screenGroup) are registered here so nothing stays dark.
func _adoptUnregistered() -> void:
	var lv = game.level
	var root = lv.get("root") if lv != null else null
	if not (root is Node):
		return
	var known := {}
	for e in _all():
		known[e.mesh] = true
	var todo: Array = []
	DAU.traverse(root, func(o):
		if not (o is MeshInstance3D) or known.has(o):
			return
		var sg = _udGet(o, "screenGroup")
		if not sg:
			return
		todo.append(o))
	for o in todo:
		var m = _meshMaterial(o)
		if m == null or not _hasMap(m):
			continue
		register(o, _udGet(o, "screenGroup"), {"id": _udGet(o, "screenId")})

# ------------------------------------------------------------------------------------------------ Godot glue
# The mesh's single material (JS mesh.material; multi-material meshes -> null).
static func _meshMaterial(mesh):
	if not (mesh is GeometryInstance3D):
		return null
	if mesh.material_override != null:
		return mesh.material_override
	if mesh is MeshInstance3D and mesh.mesh != null:
		if mesh.mesh.get_surface_count() != 1:
			return null
		var m = mesh.get_surface_override_material(0)
		return m if m != null else mesh.mesh.surface_get_material(0)
	return null

# The material register() drives (JS: mesh.material when it has a `map`), made unique to this screen when it
# lives on the shared mesh resource or another registered screen already uses it.
func _screenMat(mesh):
	var m = _meshMaterial(mesh)
	if m == null or not _hasMap(m):
		return null
	var shared: bool = mesh.material_override == null and mesh is MeshInstance3D and mesh.get_surface_override_material(0) == null
	if not shared:
		for e in _all():
			if e.mat == m and e.mesh != mesh:
				shared = true
				break
	if shared:
		m = m.clone() if m.has_method("clone") else m.duplicate()
		if mesh.material_override != null:
			mesh.material_override = m
		else:
			mesh.set_surface_override_material(0, m)
	return m

func _hasMap(m) -> bool:
	if m == null:
		return false
	if "map" in m:
		return true
	if m is ShaderMaterial:
		return _uHas(m, "tScreen") or _uHas(m, "map")
	return m is BaseMaterial3D

func _matSetMap(m, tex) -> void:
	if "map" in m:
		m.map = tex
		return
	if m is ShaderMaterial:
		var name := "tScreen" if _uHas(m, "tScreen") else "map"
		m.set_shader_parameter(name, tex if tex != null else _black)
		if tex != null and _uHas(m, "uTexel"):
			var sz: Vector2 = tex.get_size()
			if sz.x > 0.0 and sz.y > 0.0:
				m.set_shader_parameter("uTexel", Vector2(1.0 / sz.x, 1.0 / sz.y))
	elif m is BaseMaterial3D:
		m.albedo_texture = tex

# Material uniforms: the DAMaterial facade (mat.uniforms.uX.value, like the JS) first, else shader parameters.
func _uHas(m, name: String) -> bool:
	if m == null:
		return false
	var F = m.get("uniforms")
	if F is Dictionary and F.has(name):
		return true
	if m is ShaderMaterial:
		var sh: Shader = m.shader
		if sh == null:
			return false
		var names = _uniformNames.get(sh)
		if names == null:
			names = {}
			for u in sh.get_shader_uniform_list():
				names[u.name] = true
			_uniformNames[sh] = names
		return names.has(name)
	return false

func _uGet(m, name: String):
	var F = m.get("uniforms")
	if F is Dictionary and F.has(name):
		var u = F[name]
		return u.get("value") if (u is Dictionary or u is Object) else u
	if m is ShaderMaterial:
		var v = m.get_shader_parameter(name)
		if v == null and m.shader != null:
			v = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), name)
		return v
	return null

func _uSet(m, name: String, v) -> void:
	var F = m.get("uniforms")
	if F is Dictionary and F.has(name):
		var u = F[name]
		if u is Dictionary:
			u["value"] = v
			if m is ShaderMaterial:
				m.set_shader_parameter(name, v)
		elif u is Object:
			u.set("value", v)
		return
	if m is ShaderMaterial:
		m.set_shader_parameter(name, v)

# The CRT shader's local +z is the glass normal (see the header): meshes whose normals face -z are turned by PI
# (mesh cached per source mesh) and the node turned back by PI, so the world surface and picture are identical.
func faceFront(mesh) -> void:
	if not (mesh is MeshInstance3D) or mesh.mesh == null:
		return
	var ud := DAU.ud(mesh)
	if ud.has("screenFlip"):
		return
	var am: Mesh = mesh.mesh
	var z := 0.0
	var count := 0
	for s in am.get_surface_count():
		var arrs := am.surface_get_arrays(s)
		var nrm = arrs[Mesh.ARRAY_NORMAL]
		if nrm is PackedVector3Array:
			for v in nrm:
				z += v.z
			count += nrm.size()
	var back := count > 0 and z / count < -0.5
	ud["screenFlip"] = back
	if not back:
		return
	var f = _flipped.get(am)
	if f == null:
		f = _flipMesh(am)
		_flipped[am] = f
	mesh.mesh = f
	mesh.basis = mesh.basis * Basis(UP, PI)

static func _flipMesh(am: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in am.get_surface_count():
		var arrs := am.surface_get_arrays(s)
		var V = arrs[Mesh.ARRAY_VERTEX]
		if V is PackedVector3Array:
			for i in V.size():
				V[i] = Vector3(-V[i].x, V[i].y, -V[i].z)
			arrs[Mesh.ARRAY_VERTEX] = V
		var N = arrs[Mesh.ARRAY_NORMAL]
		if N is PackedVector3Array:
			for i in N.size():
				N[i] = Vector3(-N[i].x, N[i].y, -N[i].z)
			arrs[Mesh.ARRAY_NORMAL] = N
		var Tg = arrs[Mesh.ARRAY_TANGENT]
		if Tg is PackedFloat32Array:
			for i in range(0, Tg.size(), 4):
				Tg[i] = -Tg[i]
				Tg[i + 2] = -Tg[i + 2]
			arrs[Mesh.ARRAY_TANGENT] = Tg
		out.add_surface_from_arrays(am.surface_get_primitive_type(s), arrs)
		out.surface_set_material(s, am.surface_get_material(s))
		out.surface_set_name(s, am.surface_get_name(s))
	out.resource_name = am.resource_name
	return out

# userData.lampMats {on, off}: Materials, or the Blender export's {"__material": spec} refs (built with
# game.mats.fromSpec). null when missing.
func _lampMats(lm):
	if not (lm is Dictionary) or lm.get("on") == null or lm.get("off") == null:
		return null
	var out := {}
	for k in ["on", "off"]:
		var v = lm[k]
		if v is Dictionary and v.has("__material"):
			v = game.mats.fromSpec(v.__material) if game.mats != null and game.mats.has_method("fromSpec") else null
		if not (v is Material):
			return null
		out[k] = v
	return out

static func _setMat(n, m) -> void:
	if m == null:
		return
	if n is MeshInstance3D and n.mesh != null and n.material_override == null:
		for i in n.mesh.get_surface_count():
			n.set_surface_override_material(i, m)
	elif n is GeometryInstance3D:
		n.material_override = m

static func _udGet(o, key: String):
	if o == null or not (o is Object) or not is_instance_valid(o) or not o.has_meta("userData"):
		return null
	var u = o.get_meta("userData")
	return u.get(key) if u is Dictionary else null

# Equality that never compares mismatched Variant types (sources are Strings or Textures).
static func _same(a, b) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	if typeof(a) != typeof(b):
		return false
	return a == b

func _cam():
	var r = game.render
	var co = r.get("cameraOverride") if r != null else null
	if co is Camera3D:
		return co
	return game.camera

func _staticNoise():
	var t = game.tex
	if t != null and t.has_method("staticNoise"):
		return t.staticNoise()
	return null

# game.cards.get(id, opts) (the JS namespace's `get`; a GDScript object exposes it as get_ (SPEC §3.2) or getCard).
func _cardGet(id: String, opts = {}):
	var c = game.cards
	if c == null:
		return null
	if c is Dictionary:
		var fn = c.get("get")
		return fn.call(id, opts) if fn is Callable else null
	if c.has_method("get_"):
		return c.get_(id, opts)
	if c.has_method("getCard"):
		return c.getCard(id, opts)
	return null

# game.cards.<name>(...args) whether game.cards is an object or a Dictionary of Callables.
func _cardsCall(name: String, args: Array):
	var c = game.cards
	if c == null:
		return null
	if c is Dictionary:
		var fn = c.get(name)
		return fn.callv(args) if fn is Callable else null
	if c.has_method(name):
		return c.callv(name, args)
	return null

static func _tickHandle(h, t: float) -> bool:
	if h == null:
		return false
	if h is Object and h.has_method("tick"):
		return bool(h.tick(t))
	if h is Dictionary and h.get("tick") is Callable:
		return bool(h.tick.call(t))
	return false

func _newCanvas(w: int, h: int):
	if not ResourceLoader.exists(CANVAS_PATH):
		return null
	var S = load(CANVAS_PATH)
	if S == null or not S.can_instantiate():
		return null
	return S.new(w, h)
