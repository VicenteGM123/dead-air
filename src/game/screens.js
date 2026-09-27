// DEAD AIR — ScreenManager (ARCHITECTURE §12, GDD §10.0 / §18.14): every CRT in the station is live.
//
// GROUPS AND SOURCES
//   Every CRT mesh is registered once with register(mesh, groupId = 'scr_decor', { id, slot }) (props do it through
//   placeProp; meshes under the level flagged userData.screenGroup that nobody registered are picked up at init).
//   Each screen shows one SOURCE, resolved every frame (first match wins):
//     1. a screen-spawn telegraph on that one screen (priority 1: static + a growing silhouette),
//     2. a per-screen effect (the Sign-On warm-up dot -> line -> picture, blink),
//     3. the highest-priority active override covering its group (scr_telly / scr_vtr2 / scr_preview: never),
//     4. a source pinned with setSource(groupId, sourceId) (null unpins),
//     5. the GDD §10.0 default of its group, before / after power, per slot: the MC wall is 4 x 3 big CRTs (client
//        request: bigger screens, the live row at eye level): its MIDDLE row (scr_mc_feeds) = lobby, newsroom,
//        studio A, studio B feeds left to right (pass B); the 8 canned (top + bottom rows) = 3 bars / 3 station ID /
//        2 static, the static ones being the two screen-spawn CRTs (bottom corners); Hootie's TV (ss_studio_b) loops
//        hullabaloo; scr_feed_<area> = its live feed while the player is in <area>, else station_id (the lobby
//        exhibit is live before power too); scr_telly has no default (Telly owns its face).
//   Source ids: static, color_bars, station_id, right_back, stand_by, hullabaloo, baron, signoff_film,
//   feed_<lobby|newsroom|studio_a|studio_b|yard>, satellite, flinch, plus 'black', 'white', any gfx card id
//   (game.cards.ids()) or a THREE.Texture. Animated cards are shared handles ticked only while on camera.
//
// RENDER PASSES (render.addPrePass; hard cap 2 extra scene renders per frame: A + B)
//   Pass A "program feed": the feed camera of the player's area, 384x288 (was 256x192: the EE puppets must read on
//     the small monitors), 15 fps, 2-RT swap chain (screens show the front buffer while the back one renders: a
//     monitor in its own shot is a live infinite mirror). Runs only when (power is on or the player is in the lobby)
//     and a screen of that area's scr_feed_* group showing the feed is in the view frustum within 20 m. Layers
//     0+1+2, shadows not re-rendered, hero fade off, zombies in human skin (below). While a 'satellite' screen is on
//     camera, pass A renders the Uplink insert camera (layer 3).
//   Pass B "MC wall": in master_control after power, one indoor feed per frame at 256x192 (was 128x96), round robin,
//     <= 24/s, only while a feed-row CRT is on camera. Elsewhere the feed row keeps the last frames.
//   setFeedSize('A'|'B', w, h) rebuilds that pass's targets at another size (A/B measurements; stats.feedSize).
//   Every feed render draws only the camera's own area (other area roots, the building shell and the street are
//     hidden for the render; ~100-160 draw calls instead of the main pass's 400-1100) into an MSAA HDR target,
//     then a quad pass grades it into a display-referred TV picture (auto-gain, ACES, video saturation/contrast,
//     S-curve, warm tube cast, chroma smear) so feeds read as vividly as the gfx cards on the CRTs.
//   Feed cameras stand at the feed_cam_* anchors (at the lens of a bc_pedestal_camera / bc_eng_camera prop placed
//     there), FOV from the anchor (GDD §5.6; 55 if missing), pan over 8 s (the prop head pans with it and its tally
//     lights when the power / colour wave reaches it). The pan is +-20 deg at most, and never more than PAN.keep of
//     the camera's horizontal half-FOV, so the shot's subject (the look target: the EE puppets sit on the lobby,
//     newsroom and studio A targets) stays inside the middle ~45 % of the frame, clear of the CRT barrel and
//     vignette, through the whole pan (studio A 35 deg: +-9.6 deg; lobby 40: +-10.9; newsroom 50: +-13.4). feedCams[area] is the THREE.PerspectiveCamera itself
//     (its userData.feed = { id, area, pos, target, panAmp }).
//   Human skin on feeds (GDD §8): during a feed render screens.feedPass is true and mats.uniforms.uFeedSkin = 1;
//     zombie meshes (game.zombies.alive) are swapped to cached variants of their materials that turn the mint skin
//     peach #E8B896 and the static-snow eyes into normal eyes. Variants are pre-compiled on zombie:spawn.
//
// CRT ORIENTATION: mats.screen's shader takes local +z as the glass normal (bulge + fresnel/glint). kit.screen()
//   builds its domed plane facing -z (rotateY(PI) baked in), so register() re-bakes such meshes to face local +z
//   (geometry turned by PI, mesh turned back by PI: identical world surface and picture). Before this every prop
//   CRT drew a full-strength fresnel veil over its picture and bulged into the cabinet. userData.screenFlip = bool.
//
// API (game.screens)
//   register(mesh, groupId, {id, slot}) -> entry        unregister(meshOrId) -> bool   entries(groupIds?) -> entry[]
//   setSource(groupId, sourceId|null)                   sourceOf(groupId) -> what that group shows now
//   override(sourceId, groupIds = by source, seconds = Infinity, priority = by source)
//     -> handle { id, source, groups, priority, active, cancel(), extend(seconds) }. Group ids accept the GDD
//     wildcards 'scr_feed_*' / 'scr_mc_*'; without a list the GDD table applies (satellite / station_id / baron:
//     decor + canned + feeds; flinch / stand_by / hullabaloo / right_back: decor + canned; others: everything).
//     Identical calls within 0.25 s share one override. Emits machine:screen_override { source, groups, duration }. PRIORITY (lower wins): sequence 0 (Sign-On), telegraph 1,
//     boss 2, signoff 3, uplink 4, ee 5, flinch 6, stand_by 7, hullabaloo 8, intermission 9.
//   telegraph(screenSpawnId, seconds = 2.2, { sound = true }) -> handle { cancel(), active }: chunky cyan-cast snow,
//     a dark figure pushing up to the glass with glowing snow eyes, palms slapping the glass from 45 %, tearing
//     scan lines + a flash at the end, glass jitter/bulge, on the CRT of that screen spawn (entry id == spawn id,
//     else the nearest registered screen within 1.3 m), and screen_telegraph through its TV speaker.
//   feedTexture(areaId) -> Texture|null (the latest live frame of that area)
//   setInsert(object3d|null): the Uplink insert studio content, parented to insertRoot (a turntable at
//     [200, 1.05, 200] spinning at insertSpin rad/s, default 0.9; set 0 to drive it yourself), layer 3.
//     insertCamera is the insert camera; the 'satellite' source = its view + the LIVE VIA SATELLITE super.
//   freezeFlinch() -> Texture: freezes pass A's last frame with a film-frame border for the 'flinch' source
//     (override('flinch', ...) calls it itself; the 'flinch' card is the fallback when pass A never ran).
//   zoomFeed(area, seconds = 5, { zoom = 2.6 }) -> bool: crash-zooms that feed camera toward its target (lobby
//     exhibit toy), then eases back.
//   warmUp(entries = the MC wall in snake order, { start, end, settle }) -> count, blink(entriesOrGroupIds,
//     { delay, spread, from }): CRT power-on effects (Sign-On). wallOrder() -> the 12 wall entries, snake order.
//   speaker(soundId, { near = 1, groups, source, ...audio opts }) -> voice: plays a cue "from the TVs": TV-speaker
//     filter, positional, at the nearest matching screens to the listener (audio.play(id, { tv:true, pos })).
//   feedPass, stats { passA, passB, sat, flinch, maxPerFrame, feedDraws, redraws, tickMs }, feedCams, groups, byId,
//   overrides,
//   timeScale (debug/tests: 0 holds every CRT effect, feed pan and override timer on one frame).
// Automatic overrides (only while powered): round:end -> right_back for the intermission (hullabaloo when the next
// round is Hullabaloo Hour: rounds.nextSpecial / isHullabaloo(n) / specialFor(n)), round:start {special:
// 'hullabaloo'} -> hullabaloo for that round, powerup:grab {type:'please_stand_by'} -> stand_by 8 s. Always:
// machine:boss_start -> static on every overridable group but scr_feed_yard until egg:complete / game:over /
// game:victory / newGame.

import * as THREE from 'three';
import { PAL, T } from '../core/config.js';
import { staticNoise } from '../core/textures.js';

export const SCREEN_GROUPS = ['scr_feed_lobby', 'scr_feed_newsroom', 'scr_feed_studio_a', 'scr_feed_studio_b',
  'scr_feed_yard', 'scr_mc_feeds', 'scr_mc_canned', 'scr_decor', 'scr_telly', 'scr_vtr2', 'scr_preview'];
export const NEVER_OVERRIDDEN = ['scr_telly', 'scr_vtr2', 'scr_preview'];
const NEVER = new Set(NEVER_OVERRIDDEN);
export const OVERRIDE_GROUPS = SCREEN_GROUPS.filter((g) => !NEVER.has(g));
export const DECOR_CANNED = ['scr_decor', 'scr_mc_canned'];
export const PRIORITY = { sequence: 0, telegraph: 1, boss: 2, signoff: 3, uplink: 4, ee: 5, flinch: 6, stand_by: 7, hullabaloo: 8, intermission: 9 };
const SOURCE_PRIORITY = { static: 2, signoff_film: 3, satellite: 4, station_id: 5, baron: 5, flinch: 6, stand_by: 7, hullabaloo: 8, right_back: 9 };
// GDD §10.0 override table: the groups a source covers when override() gets no group list.
const EE_GROUPS = ['scr_decor', 'scr_mc_canned', 'scr_feed_*'];
const SOURCE_GROUPS = {
  satellite: EE_GROUPS, station_id: EE_GROUPS, baron: EE_GROUPS, flinch: DECOR_CANNED, stand_by: DECOR_CANNED,
  hullabaloo: DECOR_CANNED, right_back: DECOR_CANNED,
};
export const FEED_AREAS = ['lobby', 'newsroom', 'studio_a', 'studio_b', 'yard'];
const MC_FEEDS = ['lobby', 'newsroom', 'studio_a', 'studio_b'];
const GROUP_AREA = { scr_feed_lobby: 'lobby', scr_feed_newsroom: 'newsroom', scr_feed_studio_a: 'studio_a', scr_feed_studio_b: 'studio_b', scr_feed_yard: 'yard' };
// MC canned rows (every wall row but the feeds row, top to bottom), left to right as seen from the room: a
// checkerboard of bars / station ID; the bottom corners are ss_mc_w / ss_mc_e (always static).
const CANNED_GRID = [
  ['color_bars', 'station_id', 'color_bars', 'station_id'],
  ['static', 'color_bars', 'station_id', 'static'],
];
const PASS_A = { w: 384, h: 288, fps: 15, range: 20 };
const PASS_B = { w: 256, h: 192, rate: 24 };
const GRADE = { feed: 1.5, sat: 1.32, contrast: 1.08, insert: 1.2 };
// pan: +-amp, capped at keep x the horizontal half-FOV (4:3 feeds) so the look target stays mid-frame
const PAN = { amp: THREE.MathUtils.degToRad(20), period: 8, keep: 0.42 };
const VIS = { every: 0.2, range: 32 };
const TICK = { near: 6, farDist: 14, mid: 8, far: 4 };
const TELE = { w: 128, h: 96, fps: 20 };
const ZOOM = { factor: 2.6, in: 0.45, out: 0.6 };
const CAM_PROPS = new Set(['bc_pedestal_camera', 'bc_eng_camera']);
const INSERT = { pos: new THREE.Vector3(200, 0, 200), eye: [0, 1.34, 1.62], look: [0, 1.13, 0], fov: 34 };
const TAU = Math.PI * 2;
const UP = new THREE.Vector3(0, 1, 0);

const _v = new THREE.Vector3();
const _d = new THREE.Vector3();
const _t = new THREE.Vector3();
const _cp = new THREE.Vector3();
const _m = new THREE.Matrix4();
const _frustum = new THREE.Frustum();

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const easeOutCubic = (x) => 1 - (1 - x) ** 3;
const easeOutBack = (x, s = 2.2) => 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2;

function solidTexture(r, g, b) {
  const t = new THREE.DataTexture(new Uint8Array([r, g, b, 255]), 1, 1);
  t.colorSpace = THREE.SRGBColorSpace;
  t.needsUpdate = true;
  return t;
}
const WHITE = solidTexture(255, 250, 240);

// The CRT shader (mats.screen) takes local +z as the glass normal: its bulge pushes along +z and its fresnel / glint
// use (0,0,1). kit.screen() bakes rotateY(PI) into its domed plane so the prop front faces -z, which left every prop
// CRT with an inverted normal (full-strength fresnel = a milky veil over the picture, glints in the wrong place) and a
// bulge that sank into the cabinet. register() re-bakes such screens: geometry turned by PI (cached per source
// geometry) and the mesh turned back by PI locally, so the world surface, UVs and picture are identical but local +z
// now faces the viewer.
const _qFlip = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.PI);
const FLIPPED = new WeakMap();
function faceFront(mesh) {
  const g = mesh.geometry;
  if (!g || mesh.userData.screenFlip !== undefined) return;
  const n = g.attributes && g.attributes.normal;
  let z = 0;
  if (n) for (let i = 0; i < n.count; i++) z += n.getZ(i);
  const back = !!n && n.count > 0 && z / n.count < -0.5;
  mesh.userData.screenFlip = back;
  if (!back) return;
  let f = FLIPPED.get(g);
  if (!f) { f = g.clone().rotateY(Math.PI); FLIPPED.set(g, f); }
  mesh.geometry = f;
  mesh.quaternion.multiply(_qFlip);
  mesh.updateMatrix();
}

// Zombie human-skin swap (feed passes only): mint #A9C7A4 / shadow #7FA08A -> peach #E8B896 (same luminance).
// Works on linear or sRGB-baked vertex colours: it keys on "grey-green" hue (g above r ~ b), not on exact values.
const SKIN_SWAP = /* glsl */`
{
  vec3 daFc = diffuseColor.rgb;
  float daFl = max( dot( daFc, vec3( 0.2126, 0.7152, 0.0722 ) ), 1e-4 );
  float daFg = ( daFc.g - 0.5 * ( daFc.r + daFc.b ) ) / daFl;
  float daFrb = abs( daFc.r - daFc.b ) / daFl;
  float daFk = smoothstep( 0.07, 0.13, daFg ) * ( 1.0 - smoothstep( 0.42, 0.6, daFg ) ) * ( 1.0 - smoothstep( 0.14, 0.26, daFrb ) );
  diffuseColor.rgb = mix( daFc, daFl * vec3( 1.5, 0.9, 0.57 ) * 1.05, daFk );
}`;
function injectSkin(fs) {
  if (fs.includes('daAlbedo = diffuseColor.rgb;')) return fs.replace('daAlbedo = diffuseColor.rgb;', `${SKIN_SWAP}\ndaAlbedo = diffuseColor.rgb;`);
  if (fs.includes('#include <color_fragment>')) return fs.replace('#include <color_fragment>', `#include <color_fragment>\n${SKIN_SWAP}`);
  return fs;
}

// Film-frame freeze (flinch): pass A's frame, over-exposed flashbulb grade, sprocket bars top and bottom.
const FLINCH_VERT = 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4( position.xy, 0.0, 1.0 ); }';
const FLINCH_FRAG = /* glsl */`
uniform sampler2D tSrc;
varying vec2 vUv;
void main() {
  vec2 uv = vUv;
  float gate = 0.085;
  vec2 suv = vec2( 0.5 + ( uv.x - 0.5 ) * 0.94, 0.5 + ( uv.y - 0.5 ) * ( 1.0 - 2.0 * gate ) * 1.08 );
  vec3 c = texture2D( tSrc, suv ).rgb;
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
  gl_FragColor = vec4( max( c, vec3( 0.0 ) ), 1.0 );
}`;

// Studio-camera grade: feeds render in scene-linear HDR, then this quad pass turns the frame into a display-referred
// TV picture stored linear (like a decoded gfx card, so the CRT shows it as vividly as the cards): auto-gain,
// ACES, video saturation + contrast in display space, a warm tube tint and a little analog chroma smear.
const GRADE_FRAG = /* glsl */`
uniform sampler2D tSrc;
uniform vec2 uTexel;
uniform float uExposure;
uniform float uSat;
uniform float uContrast;
varying vec2 vUv;
vec3 daAces( vec3 x ) { return clamp( ( x * ( 2.51 * x + 0.03 ) ) / ( x * ( 2.43 * x + 0.59 ) + 0.14 ), 0.0, 1.0 ); }
void main() {
  vec3 c = texture2D( tSrc, vUv ).rgb;
  c.r = mix( c.r, texture2D( tSrc, vUv + vec2( uTexel.x * 1.5, 0.0 ) ).r, 0.4 );
  c.b = mix( c.b, texture2D( tSrc, vUv - vec2( uTexel.x * 1.5, 0.0 ) ).b, 0.4 );
  c = pow( daAces( max( c, vec3( 0.0 ) ) * uExposure ), vec3( 1.0 / 2.2 ) );
  float L = dot( c, vec3( 0.299, 0.587, 0.114 ) );
  c = mix( vec3( L ), c, uSat );
  c = clamp( ( c - 0.5 ) * uContrast + 0.5 + vec3( 0.014, 0.004, -0.012 ), 0.0, 1.0 );
  c = mix( c, c * c * ( 3.0 - 2.0 * c ), 0.45 ); // S-curve: punchy mids, crisp blacks under the CRT glass and bloom
  gl_FragColor = vec4( pow( c, vec3( 2.2 ) ), 1.0 );
}`;

export class ScreenManager {
  constructor(game) {
    this.game = game;
    this.groups = {};
    for (const id of SCREEN_GROUPS) this.groups[id] = [];
    this.sources = {};          // pinned by setSource
    this.byId = new Map();
    this.overrides = [];        // sorted: priority asc, newest first on ties
    this.feedCams = {};         // area -> THREE.PerspectiveCamera (userData.feed)
    this.feedPass = false;
    this.insertRoot = null;
    this.insertCamera = null;
    this.insertSpin = 0.9;
    this.clock = 0;
    this.timeScale = 1;         // debug / tests: 0 holds every screen effect, pan and override timer on a frame
    this.stats = { passA: 0, passB: 0, sat: 0, flinch: 0, maxPerFrame: 0, frames: 0, feedDraws: 0, redraws: 0, tickMs: 0,
      feedSize: { A: [PASS_A.w, PASS_A.h], B: [PASS_B.w, PASS_B.h] } };
    this._ready = false;
    this._uid = 0;
    this._ovUid = 0;
    this._area = null;
    this._lastArea = undefined;
    this._wall = null;
    this._visT = 0;
    this._posDirty = true;
    this._aAcc = 1;
    this._bAcc = 1;
    this._bNext = 0;
    this._jobA = null;
    this._jobB = null;
    this._rtA = null;
    this._aFront = 0;
    this._aFrames = 0;
    this._aArea = null;
    this._rtB = {};
    this._bFront = {};
    this._rtSat = null;
    this._satFrames = 0;
    this._rtFlinch = null;
    this._flinchTex = null;
    this._flinchPending = false;
    this._teles = new Set();
    this._telePool = [];
    this._inUse = new Map();   // animated card handle -> nearest on-camera distance this frame
    this._handles = new Map();
    this._cardCache = new Map();  // card id -> { anim, tex } (static textures resolved once)
    this._variants = new Map();
    this._swapped = [];
    this._camProps = [];
    this._visSave = [];
    this._auto = { inter: null, hull: null, boss: null };
    // Other shaders may read this during feed renders (1 while a feed camera renders). Added before any program
    // compiles so every toon program receives it.
    const U = game.mats && game.mats.uniforms;
    if (U && !U.uFeedSkin) U.uFeedSkin = { value: 0 };
  }

  // ------------------------------------------------------------------------------------------------ lifecycle
  init() {
    const g = this.game;
    this._adoptUnregistered();
    this._buildFeedCams();
    this._buildInsert();
    this._buildTargets();
    if (g.render && g.render.addPrePass) this._unPre = g.render.addPrePass((r) => this._prePass(r));
    const ev = g.events;
    ev.on('round:end', (p) => this._onRoundEnd(p));
    ev.on('round:start', (p) => this._onRoundStart(p));
    ev.on('powerup:grab', (p) => {
      if (p && p.type === 'please_stand_by' && this._powered()) this.override('stand_by', DECOR_CANNED, T.drops.freeze, PRIORITY.stand_by);
    });
    ev.on('machine:boss_start', () => {
      if (this._auto.boss) this._auto.boss.cancel();
      this._auto.boss = this.override('static', OVERRIDE_GROUPS.filter((id) => id !== 'scr_feed_yard'), Infinity, PRIORITY.boss);
    });
    for (const name of ['egg:complete', 'game:victory', 'game:over']) {
      ev.on(name, () => { if (this._auto.boss) this._auto.boss.cancel(); this._auto.boss = null; });
    }
    ev.on('zombie:spawn', (p) => { if (p && p.z) this._prepZombie(p.z); });
    ev.on('power:on', () => { this._aAcc = 1; this._bAcc = 1; });
    this._ready = true;
    this._posDirty = true;
  }

  reset() {
    for (const ov of this.overrides.slice()) this._cancel(ov);
    for (const tl of [...this._teles]) this._endTele(tl);
    for (const e of this._all()) this._clearFx(e);
    this.sources = {};
    this._auto = { inter: null, hull: null, boss: null };
    this._aFrames = 0;
    this._aArea = null;
    this._satFrames = 0;
    this._flinchTex = null;
    this._aAcc = 1;
    this._bAcc = 1;
    this._lastArea = undefined;
    this.clock = 0;
    for (const cam of Object.values(this.feedCams)) { const f = cam.userData.feed; f.zoom = null; f.zf = 1; }
    this._posDirty = true;
    if (!this._camProps.length) this._findCamProps();
  }

  update() {
    const dt = (this.game.time.realDt || 0) * this.timeScale;
    this.clock += dt;
    for (let i = this.overrides.length - 1; i >= 0; i--) if (this.clock >= this.overrides[i].until) this._cancel(this.overrides[i]);
  }

  lateUpdate() {
    const g = this.game;
    const dt = (g.time.realDt || 0) * this.timeScale;
    this._area = this._playerArea();
    this._visT -= dt;
    if (this._visT <= 0 || this._posDirty) { this._visT = VIS.every; this._updateVisibility(); }
    this._inUse.clear();
    for (const id of SCREEN_GROUPS) {
      const list = this.groups[id];
      for (let i = 0; i < list.length; i++) this._refresh(list[i]);
    }
    const now = g.time.realNow;
    const t0 = performance.now();
    // Cheap ticking: a card redraws its canvas + re-uploads only when its frame index changes; far away (small on
    // screen) the time is quantised so it redraws at most TICK.mid / TICK.far times per second.
    for (const [h, d] of this._inUse) {
      const t = h === this._filmHandle ? this.clock - this._filmT0 : now;
      const rate = d < TICK.near ? 0 : d < TICK.farDist ? TICK.mid : TICK.far;
      if (h.tick(rate ? Math.floor(t * rate) / rate : t)) this.stats.redraws++;
    }
    this.stats.tickMs += performance.now() - t0;
    this._updateFeedProps();
    if (this.insertRoot && this.insertSpin) this.insertRoot.rotation.y += this.insertSpin * dt;
    this._schedule(dt);
  }

  // ------------------------------------------------------------------------------------------------ registry
  register(mesh, groupId = 'scr_decor', opts = {}) {
    if (!mesh) return null;
    const group = this.groups[groupId] ? groupId : 'scr_decor';
    const old = this._entryOfMesh(mesh);
    if (old) this._remove(old);
    faceFront(mesh);
    let id = opts.id || (mesh.userData && mesh.userData.screenId) || `screen_${++this._uid}`;
    if (this.byId.has(id)) id = `${id}#${++this._uid}`;
    const mat = mesh.material && !Array.isArray(mesh.material) && 'map' in mesh.material ? mesh.material : null;
    const entry = {
      id, mesh, group, mat, slot: opts.slot ?? null, source: null, tex: undefined, fx: null, tele: null,
      visible: false, near: false, dist: Infinity, pos: new THREE.Vector3(), baseScale: mesh.scale.clone(), basePos: mesh.position.clone(),
      baseBright: mat && mat.uniforms && mat.uniforms.uBright ? mat.uniforms.uBright.value : null, touched: false,
    };
    mesh.userData.screenEntry = id;
    this.groups[group].push(entry);
    this.byId.set(id, entry);
    this._wall = null;
    this._posDirty = true;
    if (mesh.parent) { mesh.updateWorldMatrix(true, false); mesh.getWorldPosition(entry.pos); }
    this._refresh(entry);
    return entry;
  }

  unregister(meshOrId) {
    const e = typeof meshOrId === 'string' ? this.byId.get(meshOrId) : this._entryOfMesh(meshOrId);
    if (!e) return false;
    this._remove(e);
    return true;
  }

  entries(groupIds = null) {
    if (!groupIds) return this._all();
    const out = [];
    for (const id of this._expand(groupIds)) out.push(...(this.groups[id] || []));
    return out;
  }

  setSource(groupId, sourceId) {
    if (!this.groups[groupId]) return false;
    if (sourceId === null || sourceId === undefined) delete this.sources[groupId];
    else this.sources[groupId] = sourceId;
    for (const e of this.groups[groupId]) this._refresh(e);
    return true;
  }

  sourceOf(groupId) {
    const e = this.groups[groupId] && this.groups[groupId][0];
    if (e) return e.source ?? this._resolve(e) ?? null;
    if (!NEVER.has(groupId)) for (const ov of this.overrides) if (ov.groups.has(groupId)) return ov.source;
    return this.sources[groupId] ?? null;
  }

  // ------------------------------------------------------------------------------------------------ overrides
  override(sourceId, groupIds = null, seconds = Infinity, priority) {
    const pr = Number.isFinite(priority) ? priority : SOURCE_PRIORITY[sourceId] ?? PRIORITY.ee;
    const list = groupIds || (typeof sourceId === 'string' && SOURCE_GROUPS[sourceId]) || OVERRIDE_GROUPS;
    const groups = new Set(this._expand(list).filter((id) => this.groups[id] && !NEVER.has(id)));
    const dur = Number.isFinite(seconds) ? Math.max(0, seconds) : Infinity;
    const key = `${typeof sourceId === 'string' ? sourceId : sourceId && sourceId.uuid}|${pr}|${[...groups].sort().join(',')}`;
    const dupe = this.overrides.find((o) => o.key === key && this.clock - o.t0 < 0.25);
    if (dupe) { dupe.until = Math.max(dupe.until, this.clock + dur); return dupe.handle; }
    const ov = { id: ++this._ovUid, source: sourceId, groups, priority: pr, t0: this.clock, until: this.clock + dur, key, handle: null };
    const self = this;
    ov.handle = {
      id: ov.id, source: sourceId, priority: pr, groups: [...groups],
      get active() { return self.overrides.includes(ov); },
      cancel() { self._cancel(ov); },
      extend(s) { ov.until = Math.max(ov.until, self.clock + (Number.isFinite(s) ? s : Infinity)); },
    };
    this.overrides.push(ov);
    this.overrides.sort((a, b) => a.priority - b.priority || b.t0 - a.t0 || b.id - a.id);
    if (sourceId === 'flinch') this.freezeFlinch();
    if (sourceId === 'signoff_film') { this._filmT0 = this.clock; this._filmHandle = this._filmHandle || this.game.cards.animated('signoff_film', { owner: 'screens' }); }
    if (sourceId === 'satellite') this._aAcc = 1;
    for (const e of this._all()) if (groups.has(e.group)) this._refresh(e);
    this.game.events.emit('machine:screen_override', { source: sourceId, groups: [...groups], duration: dur });
    return ov.handle;
  }

  _cancel(ov) {
    const i = this.overrides.indexOf(ov);
    if (i < 0) return;
    this.overrides.splice(i, 1);
    if (this._ready) for (const e of this._all()) if (ov.groups.has(e.group)) this._refresh(e);
  }

  // Screen-spawn telegraph (GDD §5.5 / §10.0 priority 1): only that one CRT.
  telegraph(screenSpawnId, seconds = 2.2, opts = {}) {
    const inert = { cancel() {}, active: false };
    const e = this._entryForSpawn(screenSpawnId);
    if (!e) return inert;
    if (e.tele) this._endTele(e.tele);
    if (this._posDirty) this._updateVisibility();
    const tl = this._telePool.pop() || this._makeTele();
    Object.assign(tl, { entry: e, t0: this.clock, dur: Math.max(0.2, seconds || 2.2), last: -1, seed: (Math.random() * 0xffffffff) >>> 0 || 1 });
    e.tele = tl;
    this._teles.add(tl);
    const self = this;
    tl.handle = { cancel() { self._endTele(tl); }, get active() { return self._teles.has(tl); } };
    if (opts.sound !== false && this.game.audio) this.game.audio.play('screen_telegraph', { pos: e.pos.clone(), tv: true });
    this._refresh(e);
    return tl.handle;
  }

  // Latest live frame of an area (pass A when it is the program area, else the MC wall buffer), or null.
  feedTexture(areaId, preferWall = false) {
    const a = this._aFrames > 0 && this._aArea === areaId ? this._rtA[this._aFront].texture : null;
    const b = this._rtB[areaId] && this._rtB[areaId].frames > 0 ? this._rtB[areaId].rt[this._bFront[areaId]].texture : null;
    return preferWall ? (b || a) : (a || b);
  }

  setInsert(object3d) {
    if (!this.insertRoot) this._buildInsert();
    if (this._insertObj && this._insertObj !== object3d) this.insertRoot.remove(this._insertObj);
    this._insertObj = object3d || null;
    if (object3d) {
      this.insertRoot.add(object3d);
      this.game.render.setLayerRecursive(object3d, 3);
    }
    return this.insertRoot;
  }

  freezeFlinch() {
    this._flinchPending = true;
    return this._aFrames > 0 && this._rtFlinch ? this._rtFlinch.texture : this.game.cards.get('flinch');
  }

  // Rebuilds pass A ('A': program feed + satellite + flinch targets) or pass B ('B': the MC wall buffers) at w x h
  // (A/B measurements). Returns false when the size is unchanged.
  setFeedSize(pass, w, h) {
    const P = pass === 'B' ? PASS_B : PASS_A;
    w = Math.max(64, Math.round(w));
    h = Math.max(48, Math.round(h));
    if (P.w === w && P.h === h) return false;
    P.w = w;
    P.h = h;
    if (pass === 'B') {
      if (this._hdrB) this._hdrB.dispose();
      this._hdrB = this._target(w, h, 4);
      for (const b of Object.values(this._rtB)) for (const rt of b.rt) rt.dispose();
      this._rtB = {};
      this._bFront = {};
    } else {
      for (const rt of [this._hdrA, ...(this._rtA || []), this._rtSat, this._rtFlinch]) if (rt) rt.dispose();
      this._hdrA = this._target(w, h, 4);
      this._rtA = [this._target(w, h, 0, false), this._target(w, h, 0, false)];
      this._rtSat = this._target(w, h, 0, false);
      this._rtFlinch = this._target(w, h, 0, false);
      this._aFrames = 0;
      this._satFrames = 0;
      this._flinchTex = null;
    }
    for (const e of this._all()) { e.tex = undefined; this._refresh(e); }
    this.stats.feedSize = { A: [PASS_A.w, PASS_A.h], B: [PASS_B.w, PASS_B.h] };
    return true;
  }

  // Crash-zooms an area's feed camera toward its look target for `seconds` (the lobby exhibit toy): 0.45 s zoom-in
  // with a little overshoot + focus hunt, hold, 0.6 s ease back out. Returns false if that area has no feed camera.
  zoomFeed(area, seconds = 5, { zoom = ZOOM.factor } = {}) {
    const cam = this.feedCams[area];
    if (!cam) return false;
    const f = cam.userData.feed;
    f.zoom = { t0: this.clock, dur: Math.max(ZOOM.in + ZOOM.out, seconds || 5), k: Math.max(1, zoom) };
    this._aAcc = 1;
    return true;
  }

  // -------------------------------------------------------------------------------------- Sign-On CRT effects
  // Snake order over the MC wall (top row left -> right, next row right -> left, ...), as the viewer sees it.
  wallOrder() {
    const w = this._wallLayout();
    const out = [];
    w.rows.forEach((row, i) => out.push(...(i % 2 ? row.slice().reverse() : row)));
    return out;
  }

  // Each CRT warms up in turn: black -> white dot -> line -> picture (overshoot), settling on `settle`.
  warmUp(entries = null, { start = 0.3, end = 1.8, settle = 'color_bars', sound = 'crt_ping' } = {}) {
    const list = entries || this.wallOrder();
    const n = list.length;
    if (!n) return 0;
    const span = Math.max(0, end - start - 0.45);
    list.forEach((e, i) => {
      e.fx = { kind: 'warm', t0: this.clock + start + (n > 1 ? (span * i) / (n - 1) : 0), until: this.clock + end, settle, sound, pinged: false };
    });
    return n;
  }

  // Quick "line opens" blink on channel change. target: entries or group ids (default every overridable screen).
  blink(target = null, { delay = 0, spread = 0, from = null, dur = 0.2, except = null } = {}) {
    let list = target;
    if (!list) list = this.entries(OVERRIDE_GROUPS);
    else if (typeof list[0] === 'string') list = this.entries(list);
    if (this._posDirty) this._updateVisibility();
    for (const e of list) {
      if (except && except.includes(e)) continue;
      const lag = from ? Math.min(spread, e.pos.distanceTo(from) / 60) : Math.random() * spread;
      const t0 = this.clock + delay + lag;
      e.fx = { kind: 'blink', t0, until: t0 + dur + 0.02, dur };
    }
    return list.length;
  }

  // Plays a cue from the nearest matching TV speakers (GDD §10.0 "TV speaker").
  speaker(id, { near = 1, groups = null, source = null, ...opts } = {}) {
    const a = this.game.audio;
    if (!a) return null;
    if (this._posDirty) this._updateVisibility();
    const cam = this.game.render.cameraOverride || this.game.camera;
    _cp.setFromMatrixPosition(cam.matrixWorld);
    const list = this.entries(groups || OVERRIDE_GROUPS).filter((e) => (!source || e.source === source) && this._attached(e.mesh));
    list.sort((x, y) => x.pos.distanceToSquared(_cp) - y.pos.distanceToSquared(_cp));
    const k = Math.min(Math.max(1, near), list.length);
    let first = null;
    for (let i = 0; i < k; i++) {
      const v = a.play(id, { ...opts, pos: list[i].pos.clone(), tv: true, vol: (opts.vol ?? 1) / Math.sqrt(k) });
      if (!first) first = v;
    }
    if (!k) first = a.play(id, { ...opts, tv: true });
    return first;
  }

  // ------------------------------------------------------------------------------------------------ resolution
  _resolve(e) {
    if (e.tele) return 'telegraph';
    if (e.fx && e.fx.kind === 'warm') {
      const k = this.clock - e.fx.t0;
      return k < 0 ? 'black' : k < 0.17 ? 'white' : e.fx.settle;
    }
    if (!NEVER.has(e.group)) for (const ov of this.overrides) if (ov.groups.has(e.group)) return ov.source;
    const pin = this.sources[e.group];
    if (pin !== undefined && pin !== null) return pin;
    return this._defaultSource(e);
  }

  _defaultSource(e) {
    const on = this._powered();
    switch (e.group) {
      case 'scr_telly': return undefined;
      case 'scr_preview': return 'color_bars';
      case 'scr_vtr2': return 'static';
      case 'scr_mc_feeds': return on ? (this._slot(e) || 'station_id') : 'static';
      case 'scr_mc_canned': return on ? (this._slot(e) || 'station_id') : 'static';
      case 'scr_decor': return on ? (this._slot(e) || 'station_id') : 'static';
      default: {
        const area = GROUP_AREA[e.group];
        if (!area) return on ? 'station_id' : 'static';
        if (!on) return area === 'lobby' ? 'feed_lobby' : 'static';
        return this._area === area ? `feed_${area}` : 'station_id';
      }
    }
  }

  _slot(e) {
    if (e.slot) return e.slot;
    if (e.group === 'scr_mc_feeds' || e.group === 'scr_mc_canned') return this._wallLayout().slots.get(e) || null;
    if (e.group === 'scr_decor') return e.id === 'ss_studio_b' || e.hootie ? 'hullabaloo' : null;
    return null;
  }

  _texFor(src, e) {
    if (src === undefined) return undefined;
    if (src && src.isTexture) return src;
    switch (src) {
      case null: case 'black': return null;
      case 'telegraph': return e.tele ? e.tele.tex : null;
      case 'white': return WHITE;
      case 'static': return staticNoise();
      case 'satellite': return this._satFrames > 0 ? this._rtSat.texture : this._card('color_bars', e);
      case 'flinch': return this._flinchTex || this._card('flinch', e);
      case 'signoff_film':
        if (!this._filmHandle) { this._filmHandle = this.game.cards.animated('signoff_film', { owner: 'screens' }); this._filmT0 = this.clock; }
        if (e.visible) this._use(this._filmHandle, e);
        return this._filmHandle.texture;
      default: break;
    }
    if (typeof src === 'string' && src.startsWith('feed_')) {
      const t = this.feedTexture(src.slice(5), e.group === 'scr_mc_feeds');
      return t || this._card(e.group === 'scr_mc_feeds' ? 'station_id' : 'static', e);
    }
    return this._card(src, e);
  }

  _card(id, e) {
    if (id === 'static') return staticNoise();
    const cards = this.game.cards;
    let c = this._cardCache.get(id);
    if (c === undefined) {
      const info = cards.info(id);
      c = !info ? null : info.fps ? { anim: true, tex: null } : { anim: false, tex: cards.get(id) };
      this._cardCache.set(id, c);
    }
    if (!c) return staticNoise();
    if (!c.anim) return c.tex;
    let h = this._handles.get(id);
    if (!h) this._handles.set(id, (h = cards.animated(id, { owner: 'screens' })));
    if (e && e.visible) this._use(h, e);
    return h.texture;
  }

  _use(h, e) {
    const d = this._inUse.get(h);
    if (d === undefined || e.dist < d) this._inUse.set(h, e.dist);
  }

  _refresh(e) {
    this._applyFx(e);
    const src = this._resolve(e);
    e.source = src;
    const tex = this._texFor(src, e);
    if (tex === undefined) return;
    this._setMap(e, tex);
  }

  _setMap(e, tex) {
    if (e.tex === tex) return;
    e.tex = tex;
    const m = e.mat;
    if (!m) return;
    const had = !!m.map;
    m.map = tex;
    if (!m.isShaderMaterial && had !== !!tex) m.needsUpdate = true;
  }

  _applyFx(e) {
    let sx = 1, sy = 1, br = 1, jitter = 0, bulge = 0;
    const fx = e.fx;
    if (fx) {
      const k = this.clock - fx.t0;
      if (this.clock >= fx.until) {
        e.fx = null;
      } else if (fx.kind === 'warm' && k >= 0) {
        if (!fx.pinged) {
          fx.pinged = true;
          if (fx.sound && this.game.audio) this.game.audio.play(fx.sound, { pos: e.pos.clone(), vol: 0.6 });
        }
        if (k < 0.07) { const u = k / 0.07; sx = sy = 0.02 + 0.035 * easeOutCubic(u); br = 5; }
        else if (k < 0.17) { sx = 0.055 + 1.0 * easeOutCubic((k - 0.07) / 0.1); sy = 0.03; br = 3.5; }
        else if (k < 0.45) { const u = (k - 0.17) / 0.28; sx = 1.055 - 0.055 * easeOutCubic(u); sy = 0.03 + 0.97 * easeOutBack(u); br = 1 + 2.4 * (1 - u) * (1 - u); }
      } else if (fx.kind === 'blink' && k >= 0) {
        const u = clamp01(k / fx.dur);
        sy = 0.03 + 0.97 * easeOutBack(u);
        sx = 1 + 0.05 * (1 - u);
        br = 1 + 2 * (1 - u) * (1 - u);
      }
    }
    const tl = e.tele;
    if (tl) {
      const k = (this.clock - tl.t0) / tl.dur;
      if (k >= 1) {
        this._endTele(tl);
      } else {
        if (this.clock - tl.last >= 1 / TELE.fps) { tl.last = this.clock; this._drawTele(tl, k); }
        const ramp = k * k;
        jitter = 0.0015 + 0.006 * ramp;
        bulge = 0.012 + 0.05 * ramp * (0.6 + 0.4 * Math.sin(this.clock * 23));
        br = 1 + 0.6 * ramp;
      }
    }
    const scaled = sx !== 1 || sy !== 1;
    if (scaled || e.scaled) {
      e.mesh.scale.set(e.baseScale.x * sx, e.baseScale.y * sy, e.baseScale.z);
      e.scaled = scaled;
    }
    if (jitter || e.jittered) {
      e.mesh.position.copy(e.basePos);
      if (jitter) e.mesh.position.add(_v.set((Math.random() - 0.5) * jitter, (Math.random() - 0.5) * jitter, 0));
      e.jittered = !!jitter;
    }
    const U = e.mat && e.mat.uniforms;
    if (U) {
      if (U.uBright && e.baseBright !== null && (br !== 1 || e.touched)) {
        U.uBright.value = e.baseBright * br;
        e.touched = br !== 1;
      }
      if (U.uBulge && (bulge || e.bulged)) {
        if (e.baseBulge === undefined) e.baseBulge = U.uBulge.value;
        U.uBulge.value = bulge ? Math.max(e.baseBulge, bulge) : e.baseBulge;
        if (U.uWobble) U.uWobble.value = bulge ? 0.6 : 0;
        e.bulged = !!bulge;
      }
    }
  }

  _clearFx(e) {
    e.fx = null;
    if (e.tele) this._endTele(e.tele);
    this._applyFx(e);
  }

  // ------------------------------------------------------------------------------------------------ telegraph
  _makeTele() {
    const canvas = document.createElement('canvas');
    canvas.width = TELE.w;
    canvas.height = TELE.h;
    const ctx = canvas.getContext('2d');
    const img = ctx.createImageData(TELE.w, TELE.h);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.generateMipmaps = false;
    tex.minFilter = THREE.LinearFilter;
    tex.name = 'screens:telegraph';
    return { canvas, ctx, img, px: new Uint32Array(img.data.buffer), tex, entry: null, t0: 0, dur: 1, last: -1, seed: 1, handle: null };
  }

  // One telegraph frame (k = 0..1 of the telegraph): chunky contrasty snow with a rolling band, a sickly cyan pulse,
  // a dark figure already filling the lower half and pushing up toward the glass (it sways and grows), two glowing
  // snow eyes, palms slapping flat on the glass from k 0.45, and tearing scan lines + a flash over the last quarter.
  // Drawn at 2x2 texel grain so it reads as "something in the static" from across a room.
  _drawTele(tl, k) {
    const { ctx, img, px } = tl;
    const W = TELE.w, H = TELE.h;
    let s = tl.seed;
    const band = (this.clock * 55) % (H + 24) - 12;
    const pulse = 0.5 + 0.5 * Math.sin(this.clock * (9 + 10 * k));
    const tint = 0.25 + 0.5 * k * pulse; // cyan-green cast grows
    for (let by = 0; by < H; by += 2) {
      const inBand = by >= band && by < band + 12;
      const tear = k > 0.72 && ((by * 7 + ((this.clock * 40) | 0)) % 23) < 2;
      for (let bx = 0; bx < W; bx += 2) {
        s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
        const r = ((s >>> 24) & 0xff) / 255;
        let v = r * r * 225 + 14;
        if (inBand) v *= 0.45;
        if (tear) v = 240;
        const R8 = Math.min(255, v * (1 - 0.35 * tint)) | 0, G8 = Math.min(255, v * (1 + 0.1 * tint)) | 0, B8 = Math.min(255, v * (1 + 0.18 * tint) + 6) | 0;
        const c = 0xff000000 | (B8 << 16) | (G8 << 8) | R8;
        const i = by * W + bx;
        px[i] = c; px[i + 1] = c; px[i + W] = c; px[i + W + 1] = c;
      }
    }
    tl.seed = s || 1;
    ctx.putImageData(img, 0, 0);
    const e = 1 - (1 - k) ** 2;
    const sc = 0.55 + 0.6 * e;                       // already big, then presses in
    const sway = Math.sin(this.clock * 5.5) * 6 * (1 - 0.5 * k);
    const cx = W / 2 + sway, base = H + 6;
    const R = 21 * sc;
    const hy = base - 58 * sc;
    ctx.save();
    ctx.globalAlpha = 0.72 + 0.26 * Math.min(1, k * 2);
    ctx.fillStyle = '#0B0714';
    ctx.beginPath();
    ctx.ellipse(cx, hy, R * 1.06, R * 1.02, Math.sin(this.clock * 3.1) * 0.12, 0, TAU);
    ctx.moveTo(cx - 46 * sc, base);
    ctx.quadraticCurveTo(cx - 40 * sc, hy + R * 0.95, cx, hy + R * 0.72);
    ctx.quadraticCurveTo(cx + 40 * sc, hy + R * 0.95, cx + 46 * sc, base);
    ctx.closePath();
    ctx.fill();
    // palms slap flat on the glass, fingers spread (they wobble as it shoves)
    if (k > 0.45) {
      const r = Math.min(1, (k - 0.45) / 0.18);
      const shove = 1 + 0.06 * Math.sin(this.clock * 21);
      for (const side of [-1, 1]) {
        const hx = W / 2 + side * W * 0.3, hh = H * 0.42 + side * 3;
        const pr = (11 * r + 2) * shove;
        ctx.beginPath();
        ctx.ellipse(hx, hh, pr, pr * 1.15, side * 0.25, 0, TAU);
        ctx.fill();
        for (let f = 0; f < 4; f++) {
          const a = -Math.PI / 2 + side * (-0.75 + f * 0.5);
          ctx.beginPath();
          ctx.ellipse(hx + Math.cos(a) * pr * 1.45, hh + Math.sin(a) * pr * 1.45, 2.8 * r + 0.6, 6.5 * r + 0.8, a + Math.PI / 2, 0, TAU);
          ctx.fill();
        }
        ctx.beginPath();
        ctx.ellipse(hx - side * pr * 1.1, hh + pr * 0.35, 2.8 * r + 0.6, 6 * r + 0.8, side * 1.1, 0, TAU);
        ctx.fill();
      }
    }
    // glowing snow eyes: halo, cyan rim, white core
    const ey = hy - R * 0.05, er = R * 0.3 + 1;
    for (const side of [-1, 1]) {
      const ex = cx + side * R * 0.42;
      ctx.globalAlpha = 0.35 + 0.35 * pulse;
      const gr = ctx.createRadialGradient(ex, ey, 0, ex, ey, er * 2.6);
      gr.addColorStop(0, PAL.zEyeRim);
      gr.addColorStop(1, 'rgba(143,243,255,0)');
      ctx.fillStyle = gr;
      ctx.beginPath(); ctx.arc(ex, ey, er * 2.6, 0, TAU); ctx.fill();
      ctx.globalAlpha = 1;
      ctx.fillStyle = PAL.zEyeRim;
      ctx.beginPath(); ctx.arc(ex, ey, er, 0, TAU); ctx.fill();
      ctx.fillStyle = PAL.zEye;
      ctx.beginPath(); ctx.arc(ex, ey, er * 0.62, 0, TAU); ctx.fill();
    }
    ctx.restore();
    // last quarter: horizontal tear slices + a white flash right before it breaks through
    if (k > 0.75) {
      const q = (k - 0.75) / 0.25;
      for (let i = 0; i < 3; i++) {
        s ^= s << 13; s ^= s >>> 17; s ^= s << 5;
        const y = (s >>> 8) % (H - 8), hgt = 3 + ((s >>> 4) % 6), dx = (((s >>> 16) % 17) - 8) * (1 + 2 * q);
        ctx.drawImage(tl.canvas, 0, y, W, hgt, dx, y, W, hgt);
      }
      tl.seed = s || 1;
      if (q > 0.8) { ctx.fillStyle = `rgba(235,255,250,${(q - 0.8) * 3})`; ctx.fillRect(0, 0, W, H); }
    }
    tl.tex.needsUpdate = true;
  }

  _endTele(tl) {
    if (!this._teles.has(tl)) return;
    this._teles.delete(tl);
    const e = tl.entry;
    tl.entry = null;
    this._telePool.push(tl);
    if (e && e.tele === tl) {
      e.tele = null;
      if (this._ready) this._refresh(e);
    }
  }

  _entryForSpawn(ssId) {
    const direct = this.byId.get(ssId);
    if (direct) return direct;
    const ss = this.game.level && this.game.level.screenSpawns && this.game.level.screenSpawns[ssId];
    if (!ss) return null;
    if (this._posDirty) this._updateVisibility();
    let best = null, bd = 1.3;
    for (const e of this._all()) {
      if (NEVER.has(e.group)) continue;
      const d = e.pos.distanceTo(ss.pos);
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }

  // ------------------------------------------------------------------------------------------------ wall layout
  // Rows of the MC wall (top first), each left -> right as seen from the room; slot sources for its CRTs.
  _wallLayout() {
    if (this._wall) return this._wall;
    if (this._posDirty) this._updateVisibility();
    const list = [...this.groups.scr_mc_feeds, ...this.groups.scr_mc_canned];
    const w = { rows: [], slots: new Map() };
    if (list.length) {
      // viewer's right = (-normal) x up, normal = the CRT's facing (local +z once register() ran faceFront)
      const m0 = list[0].mesh;
      const n = _d.set(0, 0, 1).transformDirection(m0.matrixWorld);
      const right = _t.copy(n).negate().cross(UP).normalize();
      if (right.lengthSq() < 0.5) right.set(1, 0, 0);
      const byY = list.slice().sort((a, b) => b.pos.y - a.pos.y);
      for (const e of byY) {
        const row = w.rows[w.rows.length - 1];
        if (row && Math.abs(row[0].pos.y - e.pos.y) < 0.25) row.push(e); else w.rows.push([e]);
      }
      for (const row of w.rows) row.sort((a, b) => a.pos.dot(right) - b.pos.dot(right));
      const feeds = this.groups.scr_mc_feeds.slice().sort((a, b) => a.pos.dot(right) - b.pos.dot(right));
      feeds.forEach((e, i) => w.slots.set(e, `feed_${MC_FEEDS[i % MC_FEEDS.length]}`));
      const lv = this.game.level;
      const ss = lv && lv.screenSpawns ? [lv.screenSpawns.ss_mc_w, lv.screenSpawns.ss_mc_e].filter(Boolean) : [];
      // canned rows count top to bottom skipping the feeds row (the middle one on the 4 x 3 wall)
      let k = 0;
      w.rows.forEach((row) => {
        if (!row.some((e) => e.group === 'scr_mc_canned')) return;
        const grid = CANNED_GRID[Math.min(k++, CANNED_GRID.length - 1)];
        row.forEach((e, ci) => {
          if (e.group !== 'scr_mc_canned') return;
          const isSpawn = e.id === 'ss_mc_w' || e.id === 'ss_mc_e' || ss.some((s) => s.pos.distanceTo(e.pos) < 0.6);
          w.slots.set(e, isSpawn ? 'static' : grid[ci % grid.length]);
        });
      });
    }
    this._wall = w;
    return w;
  }

  // ------------------------------------------------------------------------------------------------ visibility
  _updateVisibility() {
    const g = this.game;
    const cam = g.render.cameraOverride || g.camera;
    cam.updateMatrixWorld();
    _m.multiplyMatrices(cam.projectionMatrix, cam.matrixWorldInverse);
    _frustum.setFromProjectionMatrix(_m);
    _cp.setFromMatrixPosition(cam.matrixWorld);
    const wasDirty = this._posDirty;
    this._posDirty = false;
    const hoot = g.level && g.level.screenSpawns && g.level.screenSpawns.ss_studio_b;
    for (const e of this._all()) {
      const mesh = e.mesh;
      if (!mesh.parent) { e.visible = e.near = false; continue; }
      mesh.updateWorldMatrix(true, false);
      mesh.getWorldPosition(e.pos);
      const d = e.pos.distanceTo(_cp);
      e.dist = d;
      const on = d < VIS.range && this._attached(mesh) && _frustum.intersectsObject(mesh);
      e.visible = on;
      e.near = on && d < PASS_A.range;
      if (wasDirty && e.group === 'scr_decor') e.hootie = !!hoot && e.pos.distanceTo(hoot.pos) < 1.2;
    }
    if (wasDirty) this._wall = null;
  }

  _attached(o) {
    const scene = this.game.scene;
    let top = o;
    for (let p = o; p; p = p.parent) { if (!p.visible) return false; top = p; }
    return top === scene;
  }

  _anyNear(group, source) {
    for (const e of this.groups[group]) if (e.near && (!source || e.source === source)) return true;
    return false;
  }

  // ------------------------------------------------------------------------------------------------ passes
  _schedule(dt) {
    const powered = this._powered();
    const area = this._area;
    // pass A (or the satellite insert)
    this._jobA = null;
    this._aAcc = Math.min(1, this._aAcc + dt * PASS_A.fps);
    if (area !== this._lastArea) { this._lastArea = area; this._aAcc = 1; }
    const sat = this.overrides.some((o) => o.source === 'satellite') && OVERRIDE_GROUPS.some((id) => this._anyNear(id, 'satellite'));
    if (this._aAcc >= 1) {
      if (sat) this._jobA = 'satellite';
      else if (area && this.feedCams[area] && GROUP_AREA[`scr_feed_${area}`] && (powered || area === 'lobby')
        && this._anyNear(`scr_feed_${area}`, `feed_${area}`)) this._jobA = area;
      if (this._jobA) this._aAcc = 0;
    }
    // pass B (MC wall top row)
    this._jobB = null;
    if (powered && area === 'master_control' && this._anyNear('scr_mc_feeds')) {
      this._bAcc = Math.min(1, this._bAcc + dt * PASS_B.rate);
      if (this._bAcc >= 1) {
        for (let i = 0; i < MC_FEEDS.length; i++) {
          const a = MC_FEEDS[(this._bNext + i) % MC_FEEDS.length];
          if (!this.feedCams[a]) continue;
          this._jobB = a;
          this._bNext = (this._bNext + i + 1) % MC_FEEDS.length;
          break;
        }
        if (this._jobB) this._bAcc -= 1;
      }
    } else {
      this._bAcc = 1;
    }
  }

  _prePass(renderer) {
    if (!this._jobA && !this._jobB && !this._flinchPending) return;
    const st = this.game.state;
    if (st !== 'playing' && st !== 'down') { this._jobA = this._jobB = null; return; }
    let n = 0;
    const prevTarget = renderer.getRenderTarget();
    const sm = renderer.shadowMap;
    const auto = sm.autoUpdate, needs = sm.needsUpdate;
    // Reuse the main pass's shadow map, except before it exists (first frame / after newGame): an unallocated map
    // makes three bind its compare-less empty depth texture to directionalShadowMap[] (GL_INVALID_OPERATION).
    const key = this.game.lights && this.game.lights.key;
    const haveMap = !key || !key.castShadow || !!(key.shadow && key.shadow.map);
    sm.autoUpdate = !haveMap;
    sm.needsUpdate = false;
    try {
      if (this._jobA === 'satellite') { this._renderSat(renderer); n++; }
      else if (this._jobA) { this._renderA(renderer, this._jobA); n++; }
      if (this._jobB) { this._renderB(renderer, this._jobB); n++; }
      if (this._flinchPending) this._composeFlinch(renderer);
    } finally {
      sm.autoUpdate = auto;
      sm.needsUpdate = needs;
      renderer.setRenderTarget(prevTarget);
      this._jobA = this._jobB = null;
    }
    this.stats.maxPerFrame = Math.max(this.stats.maxPerFrame, n);
  }

  _renderA(renderer, area) {
    const cam = this.feedCams[area];
    const back = 1 - this._aFront;
    this._renderFeed(renderer, cam, this._rtA[back], this._hdrA);
    this._aFront = back;
    this._aArea = area;
    this._aFrames++;
    this.stats.passA++;
    const tex = this._rtA[back].texture;
    const src = `feed_${area}`;
    for (const e of this._all()) if (e.source === src && e.group !== 'scr_mc_feeds') this._setMap(e, tex);
  }

  _renderB(renderer, area) {
    const cam = this.feedCams[area];
    let b = this._rtB[area];
    if (!b) {
      b = this._rtB[area] = { rt: [this._target(PASS_B.w, PASS_B.h, 0, false), this._target(PASS_B.w, PASS_B.h, 0, false)], frames: 0 };
      this._bFront[area] = 0;
    }
    const back = 1 - this._bFront[area];
    this._renderFeed(renderer, cam, b.rt[back], this._hdrB);
    this._bFront[area] = back;
    b.frames++;
    this.stats.passB++;
    const src = `feed_${area}`;
    for (const e of this.groups.scr_mc_feeds) if (e.source === src) this._setMap(e, b.rt[back].texture);
  }

  // One feed-camera render: only the area the camera stands in is drawn (every other area root hidden, plus the
  // building shell and the street/skyline for indoor cameras; the yard keeps them), shadows are reused, hero fade
  // off, zombies in human skin. Draw calls of the last feed render: stats.feedDraws.
  _renderFeed(renderer, cam, rt, hdr) {
    const g = this.game;
    const U = g.mats.uniforms;
    const fade = U.uHeroFade.value;
    const lv = g.level;
    const sky = lv && lv.sky;
    const skyPos = sky ? _t.copy(sky.position) : null;
    const area = cam.userData.feed.area;
    this._isolate(area);
    this._aimFeed(cam);
    U.uHeroFade.value = 1;
    if (U.uFeedSkin) U.uFeedSkin.value = 1;
    if (sky) sky.position.copy(cam.position);
    this.feedPass = true;
    this._swapZombies(true);
    try {
      renderer.setRenderTarget(hdr);
      renderer.clear();
      renderer.render(g.scene, cam);
      this.stats.feedDraws = renderer.info.render.calls;
    } finally {
      this._restoreVis();
      this._swapZombies(false);
      this.feedPass = false;
      if (U.uFeedSkin) U.uFeedSkin.value = 0;
      U.uHeroFade.value = fade;
      if (sky) sky.position.copy(skyPos);
    }
    this._grade(renderer, hdr, rt, GRADE.feed * (renderer.toneMappingExposure || 1));
  }

  // Shows only `area` (its root + its doors; building shell and street hidden unless it is the yard); null hides
  // every area (the insert studio render). _restoreVis() puts the level's own culling back.
  _isolate(area) {
    const lv = this.game.level;
    const saved = this._visSave;
    saved.length = 0;
    if (!lv) return;
    const hide = (o, v) => { if (o) { saved.push(o, o.visible); o.visible = v; } };
    if (lv.areaRoots) for (const id in lv.areaRoots) hide(lv.areaRoots[id], id === area);
    if (lv.groups && area !== 'yard') { hide(lv.groups.ext, false); hide(lv.groups.shell, false); }
    const doors = area && lv.areas && lv.areas[area] && lv.areas[area].doors;
    if (doors && lv.doors) for (const id of doors) if (lv.doors[id] && lv.doors[id].group) hide(lv.doors[id].group, true);
  }

  _restoreVis() {
    const saved = this._visSave;
    for (let i = saved.length - 2; i >= 0; i -= 2) saved[i].visible = saved[i + 1];
    saved.length = 0;
  }

  _grade(renderer, src, out, exposure) {
    const U = this._gradeMat.uniforms;
    U.tSrc.value = src.texture;
    U.uTexel.value.set(1 / src.width, 1 / src.height);
    U.uExposure.value = exposure;
    this._blit(renderer, this._gradeMat, out);
  }

  _blit(renderer, mat, out) {
    this._quad.material = mat;
    renderer.setRenderTarget(out);
    renderer.render(this._quadScene, this._quadCam);
  }

  _renderSat(renderer) {
    if (!this.insertCamera) return;
    renderer.setRenderTarget(this._hdrA);
    renderer.clear();
    this._isolate(null);
    try { renderer.render(this.game.scene, this.insertCamera); } finally { this._restoreVis(); }
    this._grade(renderer, this._hdrA, this._rtSat, GRADE.insert * (renderer.toneMappingExposure || 1));
    this._satFrames++;
    this.stats.sat++;
    for (const e of this._all()) if (e.source === 'satellite') this._setMap(e, this._rtSat.texture);
  }

  _composeFlinch(renderer) {
    this._flinchPending = false;
    if (!this._aFrames || !this._rtFlinch) { this._flinchTex = null; return; }
    this._flinchMat.uniforms.tSrc.value = this._rtA[this._aFront].texture;
    this._blit(renderer, this._flinchMat, this._rtFlinch);
    this._flinchTex = this._rtFlinch.texture;
    this.stats.flinch++;
    for (const e of this._all()) if (e.source === 'flinch') this._setMap(e, this._flinchTex);
  }

  _target(w, h, samples, depth = true) {
    const rt = new THREE.WebGLRenderTarget(w, h, { type: THREE.HalfFloatType, samples, depthBuffer: depth });
    rt.texture.name = 'screens:feed';
    rt.texture.generateMipmaps = false;
    rt.texture.minFilter = THREE.LinearFilter;
    return rt;
  }

  _buildTargets() {
    // scene renders (MSAA HDR) -> graded display-referred pictures the CRTs sample (2-deep swap chains)
    this._hdrA = this._target(PASS_A.w, PASS_A.h, 4);
    this._hdrB = this._target(PASS_B.w, PASS_B.h, 4);
    this._rtA = [this._target(PASS_A.w, PASS_A.h, 0, false), this._target(PASS_A.w, PASS_A.h, 0, false)];
    this._rtSat = this._target(PASS_A.w, PASS_A.h, 0, false);
    this._rtFlinch = this._target(PASS_A.w, PASS_A.h, 0, false);
    const quadMat = (frag, uniforms) => new THREE.ShaderMaterial({ uniforms, vertexShader: FLINCH_VERT, fragmentShader: frag, depthTest: false, depthWrite: false });
    this._flinchMat = quadMat(FLINCH_FRAG, { tSrc: { value: null } });
    this._gradeMat = quadMat(GRADE_FRAG, {
      tSrc: { value: null }, uTexel: { value: new THREE.Vector2(1 / PASS_A.w, 1 / PASS_A.h) }, uExposure: { value: GRADE.feed },
      uSat: { value: GRADE.sat }, uContrast: { value: GRADE.contrast },
    });
    this._quadScene = new THREE.Scene();
    this._quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this._gradeMat);
    this._quad.frustumCulled = false;
    this._quadScene.add(this._quad);
    this._quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  }

  // ------------------------------------------------------------------------------------------------ feed cameras
  _buildFeedCams() {
    const anchors = (this.game.level && this.game.level.anchors) || {};
    let i = 0;
    for (const [id, a] of Object.entries(anchors)) {
      if (!id.startsWith('feed_cam_') || !a.area) continue;
      const cam = new THREE.PerspectiveCamera(a.fov || 55, PASS_A.w / PASS_A.h, 0.08, a.area === 'yard' ? 120 : 40);
      cam.name = `feedcam:${a.area}`;
      cam.layers.mask = 0b111; // world + zombies + on-TV-only
      const target = a.target ? a.target.clone() : a.pos.clone().add(_v.set(-Math.sin(a.rotY || 0), 0, -Math.cos(a.rotY || 0)));
      const hHalf = Math.atan(Math.tan(THREE.MathUtils.degToRad(a.fov || 55) / 2) * (PASS_A.w / PASS_A.h));
      const panAmp = Math.min(PAN.amp, PAN.keep * hHalf);
      cam.userData.feed = { id, area: a.area, pos: a.pos.clone(), target, fov: a.fov || 55, panAmp, zf: 1, zoom: null, phase: i++ * 1.7, prop: null, head: null, headBase: 0, lens: null, tally: null, tallyOn: null, lamps: null };
      cam.position.copy(a.pos);
      cam.lookAt(target);
      cam.updateMatrixWorld();
      this.feedCams[a.area] = cam;
    }
    this._findCamProps();
  }

  // Physical feed-camera props placed by the rooms at the feed_cam_* anchors: lens position, pan head, tally.
  _findCamProps() {
    const root = this.game.level && this.game.level.root;
    if (!root) return;
    const props = [];
    root.traverse((o) => { if (o.userData && CAM_PROPS.has(o.userData.id)) props.push(o); });
    this._camProps = props;
    for (const cam of Object.values(this.feedCams)) {
      const f = cam.userData.feed;
      let best = null, bd = 1.6;
      for (const p of props) {
        p.getWorldPosition(_v);
        const d = Math.hypot(_v.x - f.pos.x, _v.z - f.pos.z);
        if (d < bd) { bd = d; best = p; }
      }
      if (!best) continue;
      const P = best.userData.parts || {};
      f.prop = best;
      f.head = P.head || null;
      f.headBase = f.head ? f.head.rotation.y : 0;
      f.lens = P.lensTip || null;
      f.tally = P.tally || null;
      f.lamps = best.userData.lampMats || null;
      f.tallyOn = null;
      // rest aim from the lens (head at its base yaw) through the look target: the lens sits up to ~1.3 m off the
      // anchor, and aiming along anchor -> target from there left the subject (the EE puppets) well off-centre
      f.restDir = null;
      if (f.lens) {
        if (f.head) f.head.rotation.y = f.headBase;
        best.updateWorldMatrix(true, true);
        f.lens.getWorldPosition(_v);
        f.restDir = new THREE.Vector3().subVectors(f.target, _v);
      }
    }
  }

  _zoomOf(f) {
    const z = f.zoom;
    if (!z) return 1;
    const k = this.clock - z.t0;
    if (k >= z.dur) { f.zoom = null; return 1; }
    let u;
    if (k < ZOOM.in) u = easeOutBack(k / ZOOM.in, 1.4);
    else if (k > z.dur - ZOOM.out) { const v = (z.dur - k) / ZOOM.out; u = v * v * (3 - 2 * v); }
    else u = 1 + 0.025 * Math.sin((k - ZOOM.in) * 7) * Math.exp(-(k - ZOOM.in) * 2.5); // focus hunt
    return 1 + (z.k - 1) * u;
  }

  _pan(f) {
    return ((f.panAmp ?? PAN.amp) / (f.zf || 1)) * Math.sin((this.clock / PAN.period) * TAU + f.phase);
  }

  _aimFeed(cam) {
    const f = cam.userData.feed;
    if (f.zf === undefined) f.zf = this._zoomOf(f);
    const fov = f.fov / f.zf;
    if (Math.abs(cam.fov - fov) > 1e-3) { cam.fov = fov; cam.updateProjectionMatrix(); }
    const ang = this._pan(f);
    if (f.head) { f.head.rotation.y = f.headBase + ang; f.head.updateWorldMatrix(true, true); }
    if (f.lens) f.lens.getWorldPosition(_v); else _v.copy(f.pos);
    if (f.restDir) _d.copy(f.restDir); else _d.subVectors(f.target, f.pos);
    _d.applyAxisAngle(UP, ang);
    cam.position.copy(_v);
    cam.lookAt(_v.add(_d));
    cam.updateMatrixWorld();
  }

  _updateFeedProps() {
    const powered = this._powered();
    const so = this.game.signon;
    for (const cam of Object.values(this.feedCams)) {
      const f = cam.userData.feed;
      f.zf = this._zoomOf(f);
      if (!f.prop) continue;
      if (f.head) f.head.rotation.y = f.headBase + this._pan(f);
      if (f.tally && f.lamps) {
        let on = f.area === 'lobby';
        if (powered) on = so && typeof so.waveReached === 'function' ? !!so.waveReached(f.pos) : true;
        if (on !== f.tallyOn) {
          f.tallyOn = on;
          f.tally.material = on ? f.lamps.on : f.lamps.off;
          if (on && powered && f.area !== 'lobby' && this.game.audio) this.game.audio.play('onair_clack', { pos: f.pos, vol: 0.4 });
        }
      }
    }
  }

  // ------------------------------------------------------------------------------------------------ insert studio
  _buildInsert() {
    if (this.insertRoot) return;
    const g = this.game;
    const set = new THREE.Group();
    set.name = 'insert_studio';
    set.position.copy(INSERT.pos);
    // cyclorama dome: deep blue night gradient with a soft starburst behind the turntable
    const cv = document.createElement('canvas');
    cv.width = 512; cv.height = 256;
    const c = cv.getContext('2d');
    const grd = c.createLinearGradient(0, 0, 0, 256);
    grd.addColorStop(0, '#0B0A2A'); grd.addColorStop(0.55, '#1B2A7A'); grd.addColorStop(0.72, '#2F5BD3'); grd.addColorStop(1, '#101030');
    c.fillStyle = grd; c.fillRect(0, 0, 512, 256);
    c.save();
    c.translate(256, 150);
    for (let i = 0; i < 24; i++) {
      c.rotate(TAU / 24);
      c.fillStyle = i % 2 ? 'rgba(127,231,255,0.10)' : 'rgba(255,95,162,0.08)';
      c.beginPath(); c.moveTo(0, 0); c.lineTo(-18, -300); c.lineTo(18, -300); c.closePath(); c.fill();
    }
    c.restore();
    for (let i = 0; i < 90; i++) {
      const x = (i * 97.13) % 512, y = (i * 41.7) % 120, r = (i % 7 === 0) ? 1.8 : 0.9;
      c.fillStyle = `rgba(255,244,214,${0.35 + (i % 5) * 0.12})`;
      c.beginPath(); c.arc(x, y, r, 0, TAU); c.fill();
    }
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace;
    const dome = new THREE.Mesh(new THREE.SphereGeometry(7, 32, 16), new THREE.MeshBasicMaterial({ map: tex, side: THREE.BackSide, fog: false }));
    dome.rotation.y = Math.PI / 2;
    dome.position.y = 1;
    set.add(dome);
    // turntable: chrome drum, red bumper ring, a glowing rim
    const M = g.mats;
    const drum = new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.7, 0.9, 40), M.toon('#C9CED8', { metal: 0.7, rough: 0.28, keepColor: true }));
    drum.position.y = 0.45;
    const top = new THREE.Mesh(new THREE.CylinderGeometry(0.66, 0.66, 0.08, 40), M.toon('#E23B3B', { rough: 0.35, keepColor: true }));
    top.position.y = 0.94;
    const rim = new THREE.Mesh(new THREE.TorusGeometry(0.66, 0.018, 8, 48), M.glow(PAL.crtCyan, 2.2));
    rim.rotation.x = Math.PI / 2;
    rim.position.y = 0.98;
    const floor = new THREE.Mesh(new THREE.CircleGeometry(3.2, 40), M.toon('#1B1E4A', { rough: 0.2, keepColor: true }));
    floor.rotation.x = -Math.PI / 2;
    set.add(drum, top, rim, floor);
    const spin = new THREE.Group();
    spin.name = 'insert_turntable';
    spin.position.y = 1.05;
    set.add(spin);
    // insert camera + the LIVE VIA SATELLITE super glued in front of it
    const cam = new THREE.PerspectiveCamera(INSERT.fov, 4 / 3, 0.05, 30);
    cam.name = 'insert_cam_uplink';
    cam.position.set(INSERT.pos.x + INSERT.eye[0], INSERT.eye[1], INSERT.pos.z + INSERT.eye[2]);
    cam.lookAt(INSERT.pos.x + INSERT.look[0], INSERT.look[1], INSERT.pos.z + INSERT.look[2]);
    cam.layers.set(3);
    const d = 0.3, hh = 2 * d * Math.tan(THREE.MathUtils.degToRad(INSERT.fov / 2));
    const superMat = new THREE.MeshBasicMaterial({ map: g.cards.get('satellite_super'), transparent: true, depthTest: false, depthWrite: false, fog: false });
    const sup = new THREE.Mesh(new THREE.PlaneGeometry(hh * (4 / 3), hh), superMat);
    sup.position.z = -d;
    sup.renderOrder = 999;
    cam.add(sup);
    g.render.setLayerRecursive(set, 3);
    g.render.setLayerRecursive(cam, 3);
    cam.layers.set(3);
    g.scene.add(set, cam);
    this.insertRoot = spin;
    this.insertCamera = cam;
    this._insertSet = set;
  }

  // ------------------------------------------------------------------------------------------------ human skin
  _variant(mat) {
    if (!mat || Array.isArray(mat)) return null;
    let v = this._variants.get(mat);
    if (v !== undefined) return v;
    v = null;
    try {
      if (mat.map && mat.map.name === 'staticNoise') v = this._eyeMaterial();
      else if (mat.isMeshStandardMaterial && typeof mat.onBeforeCompile === 'function') {
        const ud = mat.userData;
        mat.userData = {};
        try { v = mat.clone(); } finally { mat.userData = ud; }
        v.userData = ud;
        v.defines = { ...(mat.defines || {}) };
        const base = mat.onBeforeCompile;
        const key = typeof mat.customProgramCacheKey === 'function' ? mat.customProgramCacheKey() : '';
        v.onBeforeCompile = (shader, renderer) => {
          base.call(mat, shader, renderer);
          shader.fragmentShader = injectSkin(shader.fragmentShader);
        };
        v.customProgramCacheKey = () => `${key}|feedskin`;
        v.name = `${mat.name}:feed`;
      }
    } catch (err) {
      v = null;
    }
    this._variants.set(mat, v);
    return v;
  }

  _eyeMaterial() {
    if (this._eyeMat) return this._eyeMat;
    const cv = document.createElement('canvas');
    cv.width = cv.height = 64;
    const c = cv.getContext('2d');
    c.fillStyle = '#F6F3EC'; c.fillRect(0, 0, 64, 64);
    c.fillStyle = '#6B4A2A'; c.beginPath(); c.arc(32, 34, 15, 0, TAU); c.fill();
    c.fillStyle = '#1E1624'; c.beginPath(); c.arc(32, 34, 8, 0, TAU); c.fill();
    c.fillStyle = '#FFFFFF'; c.beginPath(); c.arc(27, 28, 4, 0, TAU); c.fill();
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace;
    this._eyeMat = new THREE.MeshBasicMaterial({ map: tex, color: '#ffffff' });
    this._eyeMat.name = 'zombie_eye:feed';
    return this._eyeMat;
  }

  _swapZombies(on) {
    const list = this._swapped;
    if (!on) {
      for (let i = 0; i < list.length; i += 2) list[i].material = list[i + 1];
      list.length = 0;
      return;
    }
    const zs = this.game.zombies && this.game.zombies.alive;
    if (!zs || !zs.length) return;
    for (const z of zs) {
      if (!z || !z.group) continue;
      z.group.traverse((o) => {
        if (!o.isMesh) return;
        const v = this._variant(o.material);
        if (v) { list.push(o, o.material); o.material = v; }
      });
    }
  }

  // Creates (and compiles in the background) the feed variants of a new zombie's materials.
  _prepZombie(z) {
    if (!z || !z.group || !this._rtA) return;
    const fresh = [];
    z.group.traverse((o) => {
      if (!o.isMesh || this._variants.has(o.material)) return;
      const v = this._variant(o.material);
      if (v) fresh.push(o, o.material, v);
    });
    if (!fresh.length) return;
    const r = this.game.renderer;
    if (!r.compileAsync) return;
    const cam = Object.values(this.feedCams)[0] || this.game.camera;
    const prev = r.getRenderTarget();
    for (let i = 0; i < fresh.length; i += 3) fresh[i].material = fresh[i + 2];
    try {
      r.setRenderTarget(this._hdrA);
      const p = r.compileAsync(z.group, cam, this.game.scene);
      if (p && p.catch) p.catch(() => {});
    } catch (err) {
      /* compiled lazily on the first feed frame instead */
    } finally {
      for (let i = 0; i < fresh.length; i += 3) fresh[i].material = fresh[i + 1];
      r.setRenderTarget(prev);
    }
  }

  // ------------------------------------------------------------------------------------------------ automatic
  _onRoundEnd(p) {
    if (this._auto.hull) { this._auto.hull.cancel(); this._auto.hull = null; }
    if (!this._powered()) return;
    const hull = this._nextIsHullabaloo((p && p.round) || 0);
    const R = T.rounds;
    if (this._auto.inter) this._auto.inter.cancel();
    this._auto.inter = hull
      ? this.override('hullabaloo', DECOR_CANNED, R.hullabaloo.intermission, PRIORITY.hullabaloo)
      : this.override('right_back', DECOR_CANNED, R.intermission, PRIORITY.intermission);
  }

  _onRoundStart(p) {
    if (this._auto.inter) { this._auto.inter.cancel(); this._auto.inter = null; }
    if (p && p.special === 'hullabaloo' && this._powered()) {
      if (this._auto.hull) this._auto.hull.cancel();
      this._auto.hull = this.override('hullabaloo', DECOR_CANNED, Infinity, PRIORITY.hullabaloo);
    }
  }

  _nextIsHullabaloo(round) {
    const r = this.game.rounds;
    if (!r) return false;
    try {
      const ns = typeof r.nextSpecial === 'function' ? r.nextSpecial() : r.nextSpecial;
      if (ns !== undefined && ns !== null) return ns === 'hullabaloo';
      if (typeof r.isHullabaloo === 'function') return !!r.isHullabaloo(round + 1);
      if (typeof r.specialFor === 'function') return r.specialFor(round + 1) === 'hullabaloo';
    } catch (err) {
      return false;
    }
    return false;
  }

  // ------------------------------------------------------------------------------------------------ helpers
  _powered() {
    return !!(this.game.machines && this.game.machines.powerOn);
  }

  _playerArea() {
    const p = this.game.player;
    if (!p || !p.pos) return null;
    return p.area || (this.game.level && this.game.level.areaAt ? this.game.level.areaAt(p.pos.x, p.pos.z) : null);
  }

  _expand(ids) {
    const out = [];
    for (const id of [].concat(ids || [])) {
      if (typeof id !== 'string') continue;
      if (id.endsWith('*')) { const pre = id.slice(0, -1); for (const g of SCREEN_GROUPS) if (g.startsWith(pre)) out.push(g); }
      else out.push(id);
    }
    return out;
  }

  _all() {
    const out = [];
    for (const id of SCREEN_GROUPS) out.push(...this.groups[id]);
    return out;
  }

  _entryOfMesh(mesh) {
    const id = mesh && mesh.userData && mesh.userData.screenEntry;
    const e = id && this.byId.get(id);
    return e && e.mesh === mesh ? e : null;
  }

  _remove(e) {
    const list = this.groups[e.group];
    const i = list.indexOf(e);
    if (i >= 0) list.splice(i, 1);
    this.byId.delete(e.id);
    if (e.tele) this._endTele(e.tele);
    e.fx = null;
    if (e.scaled) e.mesh.scale.copy(e.baseScale);
    if (e.jittered) e.mesh.position.copy(e.basePos);
    const U = e.mat && e.mat.uniforms;
    if (U && U.uBright && e.touched) U.uBright.value = e.baseBright;
    if (e.mesh.userData) delete e.mesh.userData.screenEntry;
    this._wall = null;
  }

  // CRTs built without placeProp (userData.screenGroup) are registered here so nothing stays dark.
  _adoptUnregistered() {
    const root = this.game.level && this.game.level.root;
    if (!root) return;
    const known = new Set(this._all().map((e) => e.mesh));
    root.traverse((o) => {
      if (!o.isMesh || known.has(o) || !o.userData || !o.userData.screenGroup) return;
      if (!o.material || !('map' in o.material)) return;
      this.register(o, o.userData.screenGroup, { id: o.userData.screenId });
    });
  }
}
