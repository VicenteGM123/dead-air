// BARON VON STATIC — the easter-egg boss (GDD §8.5, §13 step 6, §18.8 'boss_baron', T.boss). Owner: boss + ending
// engineer (with src/game/ending.js and src/art/chars/boss_baron.js). Constructs game.ending (the defeat sequence,
// credits and the Morning Show, src/game/ending.js) and drives its lifecycle from here (game.js does not know it).
//
// MODEL (~6 m, floating): the sculpted SDF body (src/art/chars/boss_baron.js, baked; ×2.5) — tux with plum lapels,
//   jabot, gold "13" medallion, the tall Dracula collar, long arms, huge white four-finger gloves — plus, built here:
//   the walnut console-TV head (1.6 × 1.3 × 1.2 m: rubber-glass bulging screen showing cards.js 'baron' at 20 fps,
//   bezel, knobs, grille, rabbit-ear antenna horns with glowing tips), the black cape (cloth sheet with a vertex
//   wobble, plum lining) and the noise-textured static tornado the body trails into. Damage shows on the model: the
//   screen cracks at 66 % (crack_overlay), the antennas spark at 33 %, the face goes frantic. No health bar.
// FIGHT (GDD §13 step 6, numbers from T.boss):
//   start(round)  THUNK (ee_switch_thunk), machine:boss_start {round} (screens -> snow, tower lights off one by one
//     (yard.js), uplink disabled), 2.0 s of total silence (audio.stopAll + music 'silence'), round paused
//     (rounds reads boss.active), zombies dissolve into static (no points, requeued), DY slams shut behind a wall of
//     static (door reset + collider + nav), Telly flagged unavailable; static swirls down from the tower top and forms
//     the Baron (4 s intro, the player keeps control; sting_boss_intro, boss_form), then music 'boss:1'.
//   Phase 1 CHANNEL HOPPING (100–66 %): hovers 4 m up; every 7 s teleports on the 9 m ring around the tower (CRT
//     dot-out / dot-in 0.6 s each); volleys of 3 homing static balls every 3.5 s (12 m/s, 15°/s, 35 dmg); 3 Tuned-Ins
//     over the fence climbs every 12 s (<= 10 adds).
//   Phase 2 TEST PATTERN SWEEP (66–33 %): colour bars on his screen; every 9 s a 1.2 s telegraph (1 kHz rise, bars
//     glow, the 180° sector lights on the gravel) then a 7-colour beam band 0.0–0.6 m high sweeps 180° (radius 16 m)
//     in 2.5 s, through props: jump it (60 dmg); one Forecaster at a time, 6 Sock Hoppers every 15 s, balls every 7 s.
//   Phase 3 DEAD AIR (33–0 %): the moon dims to 30 % and static fog rolls in; he drifts at 2.2 m/s toward the player;
//     GRAB within 2.5 m (0.8 s arm wind-up, 80 dmg + 5 m throw); Tuned-Ins every 10 s (<= 8); OFF-AIR every 15 s for
//     4 s: layer TV_ONLY (invisible but a 10 % shimmer + a static crackle), fully visible on the Yard monitors (the
//     yard feed camera auto-tracks him); any hit reveals him 1.5 s.
//   A FULL REEL drops at the tower base at each phase transition (powerups.dropGuaranteed).
//   Defeat: adds dissolve, egg:step {step:6} + egg:complete (via the egg API when it is at step 5), then
//   game.ending.play() (goodnight face + wave, head collapse, CRT collapse, living room, credits, STAY TUNED?).
// DAMAGE: HP = T.boss.hpBase + hpPerRound · round. Zones: screen ×2, antenna tips ×3, body ×0.5 (cabinet, torso,
//   arms, gloves). Bullets/melee through weapons.registerShootable('boss_baron'); grenades call boss.damage directly
//   (already ×0.5); wonder weapons pass fixed amounts (Zapper 2000 / Boom Mic 700·charge / Chroma-Key 3000: no zone
//   multiplier). +10 points per damaging hit event, a hitmarker (weak spots = head style). CANCELLED / ONE TAKE never
//   touch him, PLEASE STAND BY freezes only his adds.
// WONDER ADAPTER: the wonder weapons (src/game/wonder.js) look for the boss in zombies.alive (type 'boss_baron') and
//   damage it through zombies.damage / zombies.raycast. While the fight runs this file wraps zombies.raycast /
//   zombies.damage and wonder._zombies() so a zombie-like proxy (boss.proxy: type 'boss_baron', boss:true, pos, hp,
//   hitZones...) is found and routed to boss.damage; everything is restored when the fight ends.
// API (game.boss)
//   active (bool: intro .. end of the ending)  running (alias)  phase (0 | 1..3)  hp  maxHp  round  state
//   ('idle' | 'intro' | 'fight' | 'defeated')  pos (Vector3, waist)  offAir  proxy  root (Group)
//   start(round = rounds.round)  end({ keepEnding })  damage(amount, info) -> killed  raycast(origin, dir, max) ->
//   { dist, point, zone, mul, head:false } | null  inArena(x, z) (Instant Replay keeps samples inside)  warmup()
//   goodnight() / collapseHead(k 0..1) / cleanupAfterEnding()   (ending.js beats)
//   debugStart({ round, teleport = true, skipIntro })  debugPhase(n)  debugKill()  debugHit(zone, amount)
//   debugOffAir(on)  debugSweep()  debugGrab()  debugState()
// EVENTS: machine:boss_start {round}, machine:boss_phase {phase}, machine:boss_offair {on}, egg:step {step:6},
//   egg:complete {} (when the egg does not emit them itself), boss:defeated {round}.
// SOUNDS: ee_switch_thunk, ee_tower_off, sting_boss_intro, boss_form, boss_voice, boss_teleport, boss_static_ball,
//   boss_sweep_warn, boss_sweep, boss_grab, boss_offair, boss_hurt, baron_laugh, ee_baron_scream, crt_power_off.
// TESTS: tools/scenarios/boss_*.cjs (see boss_run.sh), shots in _shots/boss/.

import * as THREE from 'three';
import { T, PAL, LAYERS } from '../core/config.js';
import * as K from '../props/kit.js';
import { buildCharacter } from '../art/charRuntime.js';
import BAKED from '../../assets/baked/registry.js';
import baronDef from '../art/chars/boss_baron.js';
import { Ending } from '../game/ending.js';

const B = T.boss;
const S = 2.5;                                   // model units -> meters (boss_baron.js is sculpted at 1/2.5)
const HEAD_SCALE = 1.3;                          // the GDD's 1.6 × 1.3 × 1.2 m TV, exaggerated ×1.3 (a cartoon big head)
const TOWER = new THREE.Vector3(45, 0, -12);     // layout tower_base
const ARENA = { x0: 35.2, z0: -19.8, x1: 50.8, z1: -2.2 };   // yard rect (layout AREAS yard), a little inset
const HOVER = { 1: 4.0, 2: 3.4, 3: 2.45 };       // waist height per phase (the gloves reach ~0.8 m below it)
const FENCE = ['f_yard_north', 'f_yard_east_n', 'f_yard_east_s', 'g_yard_gate'];
const INTRO = { silence: B.p1 ? 2.0 : 2.0, swirl: 2.0, form: 4.6, laugh: 5.4, end: 6.0 };
const HOP = { out: 0.6, in: 0.6 };
const TRANSITION = 2.2;
const DY = { id: 'dy_mc_yard', rect: [34.8, -9.2, 35.2, -6.8], h: 2.6 };
const TAU = Math.PI * 2;
const ZONE_MUL = { screen: B.screenMul, antenna: B.antennaMul, body: B.bodyMul };
const FIXED_CAUSES = new Set(['zapper', 'boom_mic', 'chroma_key', 'wonder', 'grenade', 'explosion', 'tele', 'tiny_tele', 'burn', 'hot_mic', 'signal', 'gag']);

const clamp = THREE.MathUtils.clamp;
const lerp = THREE.MathUtils.lerp;
const smooth = (x) => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
const easeOutBack = (x, s = 1.8) => { x = clamp(x, 0, 1); return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2; };
const easeInOut = (x) => { x = clamp(x, 0, 1); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const yawTo = (dx, dz) => Math.atan2(-dx, -dz);

const _v = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3(), _v4 = new THREE.Vector3();
const _o = new THREE.Vector3(), _d = new THREE.Vector3();
const _m = new THREE.Matrix4(), _mi = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _ray = new THREE.Ray();
const _box = new THREE.Box3();
const _sph = new THREE.Sphere();

// ------------------------------------------------------------------------------------------------ geometry tests
// Ray (o, d normalized) vs capsule a..b radius r -> distance or Infinity.
function rayCapsule(o, d, a, b, r) {
  const ba = _v3.subVectors(b, a), oa = _v4.subVectors(o, a);
  const baba = ba.dot(ba), bard = ba.dot(d), baoa = ba.dot(oa), rdoa = d.dot(oa), oaoa = oa.dot(oa);
  const qa = baba - bard * bard, qb = baba * rdoa - baoa * bard, qc = baba * oaoa - baoa * baoa - r * r * baba;
  if (qa > 1e-9) {
    const h = qb * qb - qa * qc;
    if (h < 0) return Infinity;
    const t = (-qb - Math.sqrt(h)) / qa;
    const y = baoa + t * bard;
    if (y > 0 && y < baba) return t >= 0 ? t : Infinity;
    return raySphereT(o, d, y <= 0 ? a : b, r);
  }
  return raySphereT(o, d, a, r);
}
function raySphereT(o, d, c, r) {
  const ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
  const b = ox * d.x + oy * d.y + oz * d.z, q = ox * ox + oy * oy + oz * oz - r * r;
  const disc = b * b - q;
  if (disc < 0) return Infinity;
  const t = -b - Math.sqrt(disc);
  return t >= 0 ? t : (q < 0 ? 0 : Infinity);
}

// ------------------------------------------------------------------------------------------------ shaders
const NOISE_GLSL = /* glsl */`
float bh( vec2 p ) { vec3 p3 = fract( vec3( p.xyx ) * 0.1031 ); p3 += dot( p3, p3.yzx + 33.33 ); return fract( ( p3.x + p3.y ) * p3.z ); }
float vn( vec2 p ) { vec2 i = floor( p ), f = fract( p ); f = f * f * ( 3.0 - 2.0 * f );
  return mix( mix( bh( i ), bh( i + vec2( 1.0, 0.0 ) ), f.x ), mix( bh( i + vec2( 0.0, 1.0 ) ), bh( i + vec2( 1.0, 1.0 ) ), f.x ), f.y ); }`;

// Static tornado: spiral-scrolling noise bands + TV snow flecks, soft top/tip fade, fresnel edges; the tip sways.
const TORNADO_VERT = /* glsl */`
uniform float uTime, uSway, uReach;
varying vec2 vUv; varying float vFres;
void main() {
  vUv = uv;
  vec3 p = position;
  float v = uv.y;
  p.y *= mix( 1.0, uReach, v );
  p.x += sin( uTime * 1.3 + v * 3.1 ) * uSway * v * v;
  p.z += cos( uTime * 1.07 + v * 2.6 ) * uSway * v * v;
  vec4 mv = modelViewMatrix * vec4( p, 1.0 );
  vec3 n = normalize( normalMatrix * normal );
  vFres = 1.0 - abs( dot( n, normalize( -mv.xyz ) ) );
  gl_Position = projectionMatrix * mv;
}`;
const TORNADO_FRAG = /* glsl */`
uniform float uTime, uAlpha, uGain, uSpin;
uniform vec3 uA, uB;
varying vec2 vUv; varying float vFres;
${NOISE_GLSL}
void main() {
  float v = vUv.y;
  vec2 sp = vec2( vUv.x * 5.0 + v * 2.4 - uTime * uSpin, v * 5.0 - uTime * 1.7 );
  float bands = vn( sp ) * 0.62 + vn( sp * 2.3 + 7.1 ) * 0.38;
  float frame = floor( uTime * 24.0 );
  float sn = bh( floor( vUv * vec2( 160.0, 110.0 ) ) + frame * vec2( 13.1, 7.7 ) );
  vec3 col = mix( uA, uB, smoothstep( 0.32, 0.78, bands ) );
  col += vec3( 0.9, 0.88, 1.0 ) * step( 0.94, sn ) * 0.7;
  float a = uAlpha * ( 0.18 + 0.62 * smoothstep( 0.28, 0.82, bands ) + 0.3 * step( 0.95, sn ) );
  a *= smoothstep( 1.0, 0.7, v ) * smoothstep( 0.0, 0.08, v );
  a *= 0.5 + 0.6 * vFres;
  gl_FragColor = vec4( col * uGain, clamp( a, 0.0, 1.0 ) );
}`;

// Static ball / generic static blob: bright snow core, violet rim.
const BALL_VERT = /* glsl */`
varying vec3 vN; varying vec3 vV; varying vec3 vP;
void main() { vP = position; vec4 mv = modelViewMatrix * vec4( position, 1.0 ); vN = normalize( normalMatrix * normal ); vV = normalize( -mv.xyz ); gl_Position = projectionMatrix * mv; }`;
const BALL_FRAG = /* glsl */`
uniform float uTime; uniform vec3 uCol;
varying vec3 vN; varying vec3 vV; varying vec3 vP;
${NOISE_GLSL}
void main() {
  float f = 1.0 - abs( dot( vN, vV ) );
  float frame = floor( uTime * 24.0 );
  float sn = bh( floor( ( vP.xy + vP.z * 0.7 ) * 26.0 ) + frame * vec2( 3.7, 9.1 ) );
  vec3 col = mix( vec3( 0.9, 0.9, 1.0 ) * ( 0.55 + 0.9 * sn ), uCol * 2.2, smoothstep( 0.25, 0.95, f ) );
  gl_FragColor = vec4( col, 1.0 );
}`;

// Wall of static (DY), off-air shimmer, static fog: scrolling snow with scanlines, alpha edges.
const WALL_VERT = /* glsl */`varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 ); }`;
const WALL_FRAG = /* glsl */`
uniform float uTime, uAlpha, uReveal;
varying vec2 vUv;
${NOISE_GLSL}
void main() {
  if ( vUv.y > uReveal ) discard;
  float frame = floor( uTime * 24.0 );
  float sn = bh( floor( vUv * vec2( 90.0, 110.0 ) ) + frame * vec2( 11.3, 5.9 ) );
  float band = 0.75 + 0.25 * sin( vUv.y * 140.0 + uTime * 30.0 );
  float roll = smoothstep( 0.0, 0.08, abs( fract( vUv.y * 0.6 - uTime * 0.35 ) - 0.5 ) );
  vec3 col = vec3( sn * sn * 1.3 + 0.08 ) * band * vec3( 0.86, 0.84, 1.08 ) * ( 0.8 + 0.2 * roll );
  float edge = smoothstep( 0.0, 0.06, vUv.x ) * smoothstep( 1.0, 0.94, vUv.x ) * smoothstep( 0.0, 0.03, vUv.y );
  float lip = smoothstep( uReveal - 0.04, uReveal, vUv.y ) * 1.6;
  gl_FragColor = vec4( col + lip, uAlpha * edge );
}`;
const FOG_FRAG = /* glsl */`
uniform float uTime, uAlpha;
varying vec2 vUv;
${NOISE_GLSL}
void main() {
  vec2 p = vUv * 9.0;
  float n = vn( p + vec2( uTime * 0.13, uTime * 0.07 ) ) * 0.6 + vn( p * 2.1 - vec2( uTime * 0.21, -uTime * 0.05 ) ) * 0.4;
  float frame = floor( uTime * 20.0 );
  float sn = bh( floor( vUv * 420.0 ) + frame * vec2( 7.1, 3.3 ) );
  float r = length( vUv - 0.5 ) * 2.0;
  float a = uAlpha * smoothstep( 0.3, 0.85, n ) * smoothstep( 1.0, 0.55, r ) * ( 0.88 + 0.24 * sn );
  gl_FragColor = vec4( vec3( 0.5, 0.46, 0.68 ) * ( 0.8 + 0.3 * sn ), a );
}`;

// Sweep blade: 7 colour-bar bands along its length, hot core line, soft top edge.
const BLADE_FRAG = /* glsl */`
uniform float uTime, uAlpha; uniform vec3 uBars[ 7 ];
varying vec2 vUv;
void main() {
  float idx = clamp( floor( vUv.x * 7.0 ), 0.0, 6.0 );
  vec3 c = uBars[ 0 ];
  for ( int i = 0; i < 7; i++ ) if ( float( i ) == idx ) c = uBars[ i ];
  float top = smoothstep( 1.0, 0.72, vUv.y );
  float core = exp( -abs( vUv.y - 0.45 ) * 9.0 ) * 0.9;
  float scan = 0.85 + 0.15 * sin( vUv.y * 60.0 - uTime * 40.0 );
  gl_FragColor = vec4( c * ( 1.4 + core * 2.2 ) * scan, uAlpha * top );
}`;
// Floor sector (telegraph + afterimage fan): concentric colour-bar rings, fading with angle from the blade.
const FAN_FRAG = /* glsl */`
uniform float uTime, uAlpha, uSweep, uPulse; uniform vec3 uBars[ 7 ];
varying vec2 vUv;
void main() {
  float r = vUv.y;
  float idx = clamp( floor( r * 7.0 ), 0.0, 6.0 );
  vec3 c = uBars[ 0 ];
  for ( int i = 0; i < 7; i++ ) if ( float( i ) == idx ) c = uBars[ i ];
  float a = vUv.x;                                     // 0 = start angle .. 1 = end angle
  float trail = uSweep < 0.0 ? 1.0 : smoothstep( uSweep - 0.35, uSweep, a ) * step( a, uSweep );
  float ring = 0.65 + 0.35 * smoothstep( 0.4, 0.5, abs( fract( r * 7.0 ) - 0.5 ) );
  float edge = smoothstep( 0.0, 0.015, a ) * smoothstep( 1.0, 0.985, a );
  gl_FragColor = vec4( c * ( 0.9 + uPulse ), uAlpha * trail * ring * edge * smoothstep( 0.02, 0.06, r ) );
}`;

let _glowTex = null;
function glowTexture() {
  if (_glowTex) return _glowTex;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const x = c.getContext('2d');
  const g = x.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.25, 'rgba(255,255,255,0.55)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = g; x.fillRect(0, 0, 128, 128);
  _glowTex = new THREE.CanvasTexture(c);
  _glowTex.colorSpace = THREE.SRGBColorSpace;
  return _glowTex;
}

let _lineTex = null;
// A CRT power-off line: hot white core, soft top/bottom falloff, tapered ends.
function lineTexture() {
  if (_lineTex) return _lineTex;
  const c = document.createElement('canvas');
  c.width = 256; c.height = 64;
  const x = c.getContext('2d');
  const gv = x.createLinearGradient(0, 0, 0, 64);
  gv.addColorStop(0, 'rgba(255,255,255,0)'); gv.addColorStop(0.42, 'rgba(235,240,255,0.55)'); gv.addColorStop(0.5, 'rgba(255,255,255,1)');
  gv.addColorStop(0.58, 'rgba(235,240,255,0.55)'); gv.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = gv;
  x.fillRect(0, 0, 256, 64);
  x.globalCompositeOperation = 'destination-in';
  const gh = x.createLinearGradient(0, 0, 256, 0);
  gh.addColorStop(0, 'rgba(0,0,0,0)'); gh.addColorStop(0.12, 'rgba(0,0,0,1)'); gh.addColorStop(0.88, 'rgba(0,0,0,1)'); gh.addColorStop(1, 'rgba(0,0,0,0)');
  x.fillStyle = gh;
  x.fillRect(0, 0, 256, 64);
  _lineTex = new THREE.CanvasTexture(c);
  _lineTex.colorSpace = THREE.SRGBColorSpace;
  return _lineTex;
}

function barColors() { return PAL.BARS.map((h) => new THREE.Color(h)); }

// ================================================================================================ the Boss
export class Boss {
  constructor(game) {
    this.game = game;
    this.active = false;
    this.phase = 0;
    this.hp = 0;
    this.maxHp = 0;
    this.round = 0;
    this.state = 'idle';
    this.pos = new THREE.Vector3(TOWER.x, HOVER[1], TOWER.z - 9);
    this.yaw = 0;
    this.offAir = false;
    this.root = null;
    this.built = false;
    this.debug = false;
    this._t = 0;
    this._adds = new Set();
    this._balls = [];
    this._saved = null;
    this._adapted = null;
    this.proxy = this._makeProxy();
    try {
      this.ending = new Ending(game, this);
    } catch (err) {
      console.error('[boss] ending failed to construct', err);
      this.ending = null;
    }
    game.ending = this.ending;
  }

  get running() { return this.active; }
  get fighting() { return this.active && (this.state === 'intro' || this.state === 'fight'); }

  // ------------------------------------------------------------------------------------------ lifecycle
  init() {
    const g = this.game;
    const ev = g.events;
    ev.on('zombie:kill', ({ z } = {}) => { if (z) this._adds.delete(z); });
    ev.on('zombie:despawn', ({ z } = {}) => { if (z) this._adds.delete(z); });
    ev.on('game:over', () => { if (this.active) this.end({ quiet: true }); });
    try { this.ending?.init?.(); } catch (err) { console.error('[boss] ending.init', err); }
  }

  reset() {
    if (this.active || this.state !== 'idle') this.end({ quiet: true });
    try { this.ending?.reset?.(); } catch (err) { console.error('[boss] ending.reset', err); }
    this.phase = 0;
    this.hp = this.maxHp = 0;
    this.state = 'idle';
  }

  // Precompile hook: the real model is built once here (compiled with the scene, then kept for the fight), plus
  // throw-away samples of everything spawned later (static ball, sweep blade + fan, DY wall, static fog, CRT line),
  // so the first volley / sweep / off-air never stalls on a shader compile.
  warmup() {
    if (this.active) return null;
    try {
      this._ensureBuilt();
      this.root.visible = true;
      this.root.position.set(0, 0, 0);
      const out = [this.root];
      this._ballPool();
      const ball = new THREE.Mesh(this._ballGeo, this._ballMat);
      ball.add(new THREE.Sprite(this._ballHalo));
      out.push(ball);
      this._sweepAssets();
      out.push(new THREE.Mesh(this._blade.blade.geometry, this._bladeMat), new THREE.Mesh(this._blade.fan.geometry, this._fanMat));
      this._closeDYWallOnly();
      out.push(new THREE.Mesh(this._wall.geometry, this._wall.material));
      const fog = new THREE.ShaderMaterial({ uniforms: { uTime: { value: 0 }, uAlpha: { value: 0.2 } }, vertexShader: WALL_VERT, fragmentShader: FOG_FRAG, transparent: true, depthWrite: false, fog: false });
      out.push(new THREE.Mesh(new THREE.PlaneGeometry(1, 1), fog));
      const dot = this.dot.clone(), line = this.line.clone();
      dot.visible = line.visible = true;
      out.push(dot, line);
      for (const s of this._shimmer) if (!s.isSkinnedMesh) { const c = s.clone(); c.visible = true; out.push(c); }
      return out;
    } catch (err) {
      console.warn('[boss] warmup build failed', err);
      return null;
    }
  }

  // The DY wall mesh without closing anything (warmup sample).
  _closeDYWallOnly() {
    if (this._wall) return;
    const [, z0, , z1] = DY.rect;
    const m = new THREE.ShaderMaterial({ uniforms: { uTime: { value: 0 }, uAlpha: { value: 0.92 }, uReveal: { value: 0 } }, vertexShader: WALL_VERT,
      fragmentShader: WALL_FRAG.replace('if ( vUv.y > uReveal ) discard;', 'if ( 1.0 - vUv.y > uReveal ) discard;').replace('smoothstep( uReveal - 0.04, uReveal, vUv.y )', 'smoothstep( uReveal - 0.04, uReveal, 1.0 - vUv.y )'),
      transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false });
    this._wall = new THREE.Mesh(new THREE.PlaneGeometry(z1 - z0 + 0.3, DY.h + 0.1), m);
    this._wall.rotation.y = Math.PI / 2;
    this._wall.renderOrder = 3;
  }

  // ------------------------------------------------------------------------------------------ start / end
  start(round) {
    const g = this.game;
    if (this.active) return false;
    if (!Number.isFinite(round)) round = g.rounds?.round || 1;
    this._ensureBuilt();
    this.round = Math.max(1, round | 0);
    this.maxHp = this.hp = B.hpBase + B.hpPerRound * this.round;
    this.active = true;
    this.state = 'intro';
    this.phase = 0;
    this._t = 0;
    this._introT = 0;
    this._introFlags = {};
    this._phaseT = 0;
    this._transT = 0;
    this._hurtT = 0;
    this._voiceT = 0;
    this._revealT = 0;
    this._grab = null;
    this._hop = null;
    this._sweep = null;
    this._offAirT = 0;
    this._offAirTimer = B.p3.offAirEvery;
    this.offAir = false;
    this._cracked = false;
    this._sparking = false;
    this._pointsFrame = -1;
    this._hmFrame = -1;
    this._drops = {};
    this._saved = { round: g.rounds?.round };
    // position: the ring point with the best view from the player (7–11 m away, not behind the tower)
    const p = g.player?.pos || TOWER;
    const a0 = this._pickRingAngle(p, null);
    this._ringA = a0;
    this._ringPoint(a0, this.pos, HOVER[1]);
    this._hoverY = HOVER[1];
    this.yaw = yawTo(p.x - this.pos.x, p.z - this.pos.z);
    const root = this.root;
    root.position.copy(this.pos);
    root.rotation.set(0, this.yaw, 0);
    root.scale.setScalar(1);
    root.visible = false;
    if (root.parent !== g.scene) g.scene.add(root);      // (warmup() leaves it under the precompile group)
    if (this.fxRoot.parent !== g.scene) g.scene.add(this.fxRoot);
    this._setLayers(LAYERS.WORLD);
    this._setFace('laugh');
    this.head.crack.visible = false;
    this.head.group.visible = true;
    this.head.group.scale.setScalar(1);
    for (const o of [this.head._flash, this.head._dot]) if (o) { o.visible = false; if (o.parent) o.parent.remove(o); }
    this.tornado.group.scale.setScalar(0.001);
    this.tornado.mats.forEach((m) => { m.uniforms.uAlpha.value = m.userData.alpha; m.uniforms.uReach.value = 1; });
    this.head.antennaSpark = 0;

    // t = 0: THUNK, tower lights off (yard.js on machine:boss_start), TVs to snow (screens.js), dead air
    try { g.audio.stopAll(); } catch { /* optional */ }
    g.audio?.music?.('silence');
    g.audio?.play?.('ee_switch_thunk', { pos: this._switchPos() });
    g.audio?.play?.('ee_tower_off', { pos: new THREE.Vector3(TOWER.x, 12, TOWER.z), delay: 0.2 });
    if (!((g.egg?.step ?? 0) >= 5)) this._throwSwitch();   // the egg throws the knife switch itself at step 5
    g.events.emit('machine:boss_start', { round: this.round });
    // round paused (rounds reads boss.active) + every living zombie dissolves (no points; requeued for later)
    try { g.zombies?.despawnAll?.({ fx: true, requeue: true }); } catch (err) { console.warn('[boss] despawnAll', err); }
    this._adds.clear();
    this._closeDY();
    if (g.telly) g.telly.disabled = true;
    this._installAdapters();
    this._registerShootable();
    this._trackFeed(true);
    g.cam?.shake?.(0.25, 0.4);
    return true;
  }

  // Stops everything and restores the world. keepEnding: the ending sequence keeps running (it calls
  // cleanupAfterEnding() when it is done).
  end({ quiet = false, keepEnding = false } = {}) {
    const g = this.game;
    this._clearBalls();
    this._stopSweep();
    if (this._offAirLoop) { try { this._offAirLoop.stop(0.2); } catch { /* optional */ } this._offAirLoop = null; }
    this._despawnAdds(!quiet);
    this._uninstallAdapters();
    this._unregisterShootable();
    this._trackFeed(false);
    this._restoreEnv();
    this._openDY(quiet);
    if (g.telly) g.telly.disabled = false;
    if (this.root) { this.root.visible = false; if (this.root.parent) this.root.parent.remove(this.root); }
    if (this.fxRoot && this.fxRoot.parent) this.fxRoot.parent.remove(this.fxRoot);
    this.offAir = false;
    if (!keepEnding) {
      this.active = false;
      this.state = 'idle';
      this.phase = 0;
      try { if (!quiet) this.ending?.stop?.(); } catch { /* optional */ }
    }
  }

  // ------------------------------------------------------------------------------------------ update
  update(dt) {
    const g = this.game;
    const rdt = g.time?.realDt ?? dt;
    if (this.ending && (this.ending.active || this.ending.playing)) {
      try { this.ending.update(rdt); } catch (err) { this._err('ending', err); }
    }
    if (!this.active || !this.built) return;
    if (this.state === 'defeated') { if (this.root.parent) this._animateModel(rdt, true); return; }
    if (!(dt > 0)) { this._animateModel(0, false); return; }
    this._t += dt;
    if (this.state === 'intro') this._updateIntro(dt);
    else if (this.state === 'fight') this._updateFight(dt);
    this._updateBalls(dt);
    this._updateSweep(dt);
    this._updateAddsTick(dt);
    this._animateModel(dt, false);
    this._syncProxy();
    this._updateFeedTarget(dt);
    this._updateEnv(dt);
    this._updateWall(dt);
  }

  // The wall of static in the DY doorway unrolls from the top in 0.3 s, then keeps crawling.
  _updateWall(dt) {
    const w = this._wall;
    if (!w || !w.parent) return;
    this._wallT = (this._wallT || 0) + dt;
    const U = w.material.uniforms;
    U.uTime.value = this._t;
    U.uReveal.value = Math.min(1, this._wallT / 0.3);
  }

  _err(tag, err) {
    const now = performance.now();
    if (!this._errT || now - this._errT > 5000) { this._errT = now; console.error(`[boss:${tag}]`, err); }
  }

  // ------------------------------------------------------------------------------------------ intro
  _updateIntro(dt) {
    const g = this.game, F = this._introFlags;
    this._introT += dt;
    const t = this._introT;
    const top = _v.set(TOWER.x, 30, TOWER.z);
    if (t >= INTRO.swirl && !F.swirl) {
      F.swirl = true;
      g.audio?.play?.('sting_boss_intro');
      g.audio?.play?.('boss_form', { pos: top, vol: 1.2 });
    }
    // static swirls above the tower, then spirals down to where he forms
    if (t >= INTRO.swirl && t < INTRO.form + 0.3) {
      const u = clamp((t - INTRO.swirl) / (INTRO.form - INTRO.swirl), 0, 1);
      const e = easeInOut(u);
      for (let i = 0; i < 5; i++) {
        const a = t * 7.5 + i * (TAU / 5);
        const r = lerp(3.8, 1.3, e) * (0.8 + 0.3 * Math.random());
        const cx = lerp(TOWER.x, this.pos.x, e), cz = lerp(TOWER.z, this.pos.z, e), cy = lerp(31, this.pos.y + 1.5, e);
        _v2.set(cx + Math.cos(a) * r, cy + (Math.random() - 0.5) * 2.4, cz + Math.sin(a) * r);
        g.fx?.burst?.(_v2, { shape: 'static', count: 3, speed: 1.4, size: 0.3, life: 0.7 });
      }
      if (Math.random() < dt * 6) g.fx?.burst?.(_v2, { shape: 'spark', count: 3, speed: 5, size: 0.05, colors: ['#C9A0FF', '#FFFFFF'], life: 0.3 });
    }
    // the tornado grows first, then the body warms up out of a CRT dot
    if (t >= INTRO.form - 1.0) {
      const k = smooth((t - (INTRO.form - 1.0)) / 1.0);
      this.tornado.group.scale.setScalar(Math.max(0.001, k));
    }
    if (t >= INTRO.form && !F.form) {
      F.form = true;
      this.root.visible = true;
      g.fx?.flashLight?.(_v2.copy(this.pos).setY(this.pos.y + 1.5), '#D9B8FF', 14, 0.5);
      g.fx?.burst?.(_v2, { shape: 'static', count: 40, speed: 6, size: 0.3, life: 0.8 });
      g.fx?.burst?.(_v2, { shape: 'confetti', count: 24, colors: PAL.BARS, speed: 6, size: 0.14 });
      g.cam?.shake?.(0.45, 0.5);
      if (g.render?.post) this._whiteout = 0.22;
    }
    if (t >= INTRO.form) {
      const k = clamp((t - INTRO.form) / 0.6, 0, 1);
      this._dotScale(k, true);
    }
    if (t >= INTRO.laugh && !F.laugh) {
      F.laugh = true;
      this._voice('baron_laugh', 1.2);
      g.audio?.play?.('boss_voice', { pos: this.pos, syllables: 5 });
    }
    if (t >= INTRO.end) {
      this._dotScale(1, true);
      this._beginPhase(1);
    }
  }

  // ------------------------------------------------------------------------------------------ fight
  _beginPhase(n) {
    const g = this.game;
    const prev = this.phase;
    this.phase = n;
    this.state = 'fight';
    this._phaseT = 0;
    this._hopT = B.p1.hopEvery;
    this._ballT = n === 1 ? 1.6 : B.p2.sweepEvery * 0.5;
    this._addsT = n === 1 ? 3.0 : n === 2 ? 4.0 : 3.0;
    this._socksT = 6.0;
    this._fcT = 2.0;
    this._sweepT = n === 2 ? 2.0 : Infinity;
    this._grabCd = 1.5;
    this._offAirTimer = B.p3.offAirEvery * 0.6;
    g.audio?.music?.(`boss:${n}`);
    if (n === 2) this._setFace('bars');
    else if (n === 3) this._setFace('frantic');
    else this._setFace('laugh');
    if (n === 3) this._enterDeadAir();
    g.events.emit('machine:boss_phase', { phase: n });
    if (prev > 0) this._dropReel();
  }

  _updateFight(dt) {
    const g = this.game;
    this._phaseT += dt;
    if (this._transT > 0) {
      // phase-change recoil: screen static, scream, no attacks; the FULL REEL already dropped
      this._transT -= dt;
      if (this._transT <= 0) this._beginPhase(this._nextPhase);
      return;
    }
    const n = this.phase;
    const p = g.player;
    if (n === 1 || n === 2) {
      // channel hopping (phase 2: only between sweeps)
      if (!this._hop) {
        this._hopT -= dt;
        const sweeping = this._sweep && this._sweep.phase !== 'done';
        if (this._hopT <= 0 && !sweeping) this._startHop();
      }
      if (this._hop) this._updateHop(dt);
      // static balls
      this._ballT -= dt;
      const every = n === 1 ? B.p1.ballEvery : B.p1.ballEvery * 2;
      if (this._ballT <= 0 && !this._hop && !(this._sweep && this._sweep.phase === 'sweep')) {
        this._ballT = every;
        this._volley();
      }
      if (n === 2) {
        this._sweepT -= dt;
        if (this._sweepT <= 0 && !this._hop && !this._sweep) { this._sweepT = B.p2.sweepEvery; this._startSweep(); }
      }
    } else if (n === 3) {
      this._updateDrift(dt);
      this._updateGrab(dt);
      this._updateOffAir(dt);
    }
    // adds
    this._updateAdds(dt, n);
    // face the player (smoothly)
    if (p && !this._hop) {
      const want = yawTo(p.pos.x - this.pos.x, p.pos.z - this.pos.z);
      this.yaw += angDiff(want, this.yaw) * (1 - Math.exp(-dt * 3.2));
    }
    // hover height eases to the phase height
    const hy = HOVER[n] || HOVER[1];
    this._hoverY += (hy - this._hoverY) * (1 - Math.exp(-dt * 1.2));
    this.pos.y = this._hoverY + Math.sin(this._t * 1.3) * 0.18;
  }

  // HP thresholds: a single hit never skips a phase (HP is clamped at the threshold until the transition).
  _checkPhase() {
    if (this.state !== 'fight' || this._transT > 0) return;
    const f = this.hp / this.maxHp;
    let next = 0;
    if (this.phase === 1 && f <= 2 / 3) next = 2;
    else if (this.phase === 2 && f <= 1 / 3) next = 3;
    if (!next) return;
    const g = this.game;
    this._nextPhase = next;
    this._transT = TRANSITION;
    this._hop = null;
    this._stopSweep();
    this._restoreScale();
    if (next === 2) { this.head.crack.visible = true; this._cracked = true; }
    if (next === 3) this._sparking = true;
    this._setFace('frantic');
    this._voice('ee_baron_scream', 1);
    g.audio?.play?.('boss_hurt', { pos: this.pos, vol: 1.3 });
    _v.copy(this.head.screenWorld());
    g.fx?.burst?.(_v, { shape: 'static', count: 36, speed: 7, size: 0.28, life: 0.9 });
    g.fx?.burst?.(_v, { shape: 'spark', count: 30, speed: 9, size: 0.06, colors: ['#FFFFFF', '#C9A0FF', '#FFE27A'] });
    g.fx?.flashLight?.(_v, '#E0C8FF', 12, 0.4);
    g.cam?.shake?.(0.4, 0.5);
    this.head.wobble = 1;
    this._dropReel();
  }

  _dropReel() {
    const g = this.game;
    if (this._drops[this.phase]) return;
    this._drops[this.phase] = true;
    const p = g.player?.pos || TOWER;
    _v.set(p.x - TOWER.x, 0, p.z - TOWER.z);
    if (_v.lengthSq() < 1e-4) _v.set(0, 0, 1);
    _v.normalize().multiplyScalar(3.0).add(TOWER);
    _v.y = 0;
    try {
      const pu = g.powerups;
      if (pu && typeof pu.dropGuaranteed === 'function') pu.dropGuaranteed('full_reel', _v.clone());
      else pu?.drop?.('full_reel', _v.clone());
    } catch (err) { console.warn('[boss] FULL REEL drop failed', err); }
  }

  // ------------------------------------------------------------------------------------------ helpers
  _ringPoint(a, out, y) {
    out.set(TOWER.x + Math.cos(a) * B.p1.ring, y, TOWER.z + Math.sin(a) * B.p1.ring);
    out.x = clamp(out.x, ARENA.x0 + 1.5, ARENA.x1 - 1.5);
    out.z = clamp(out.z, ARENA.z0 + 1.5, ARENA.z1 - 1.5);
    return out;
  }

  // Ring angle scored for readability: 7–11 m from the player, never hidden behind the tower, and (for hops) at
  // least 5 m from where he is now. A little randomness keeps the hops unpredictable.
  _pickRingAngle(p, from) {
    let best = 0, bestS = -Infinity;
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * TAU + (Math.random() - 0.5) * 0.3;
      this._ringPoint(a, _v3, 0);
      const dx = _v3.x - p.x, dz = _v3.z - p.z, d = Math.hypot(dx, dz);
      let s = -Math.abs(d - 9) + Math.random() * 1.5;
      // tower occlusion: distance from the tower axis to the player->point segment
      const L2 = dx * dx + dz * dz || 1;
      const k = clamp(((TOWER.x - p.x) * dx + (TOWER.z - p.z) * dz) / L2, 0, 1);
      const ox = p.x + dx * k - TOWER.x, oz = p.z + dz * k - TOWER.z;
      if (Math.hypot(ox, oz) < 2.8 && k > 0.05 && k < 0.95) s -= 12;
      if (from && Math.hypot(_v3.x - from.x, _v3.z - from.z) < 5) s -= 20;
      if (s > bestS) { bestS = s; best = a; }
    }
    return best;
  }

  inArena(x, z) {
    return x >= ARENA.x0 - 0.3 && x <= ARENA.x1 + 0.3 && z >= ARENA.z0 - 0.3 && z <= ARENA.z1 + 0.3;
  }

  _switchPos() {
    const ks = this.game.level?.objects?.ee_kill_switch;
    return ks && ks.pos ? ks.pos : new THREE.Vector3(45, 1.2, -9.7);
  }

  // The knife switch goes THUNK (if the egg did not already throw it).
  _throwSwitch() {
    const ks = this.game.level?.objects?.ee_kill_switch;
    const sw = ks?.parts?.switch;
    if (!sw) return;
    if (sw.rotation.x < 1.5) this._switchAnim = { part: sw, from: sw.rotation.x, t: 0 };
  }

  _voice(id, vol = 1) {
    const g = this.game;
    g.audio?.play?.(id, { pos: this.head?.screenWorld?.() || this.pos, vol, tv: true });
  }

  _floorY(x = this.pos.x, z = this.pos.z) {
    const f = this.game.level?.col?.floorAt?.(x, z, 6);
    return Number.isFinite(f) ? f : 0;
  }

  // ============================================================================================ model
  _ensureBuilt() {
    if (this.built) return;
    const g = this.game;
    const root = new THREE.Group();
    root.name = 'boss_baron';
    this.root = root;
    // ---- body (baked SDF, else a primitive stand-in)
    let char = null;
    try {
      if (BAKED.boss_baron && !(g.params && g.params.art === 0)) {
        char = buildCharacter(baronDef, { envMap: g.mats.envMap, globals: g.mats.uniforms, animator: false, shadows: true });
      }
    } catch (err) {
      console.warn('[boss] baked Baron body unavailable, using the stand-in', err);
      char = null;
    }
    if (!char) char = this._standInBody();
    char.group.scale.setScalar(S);
    root.add(char.group);
    this.char = char;
    this.J = char.rig.joints;
    this._restPose = {};
    for (const [n, j] of Object.entries(this.J)) this._restPose[n] = j.rotation.clone();
    // ---- head (world units under a 1/S holder on the head joint)
    const holder = new THREE.Group();
    holder.name = 'baron_head_holder';
    holder.scale.setScalar(HEAD_SCALE / S);
    this.J.head.add(holder);
    this.head = this._buildHead();
    holder.add(this.head.group);
    // ---- cape (model units on the chest joint)
    this.cape = this._buildCape();
    this.J.chest.add(this.cape.group);
    // ---- tornado (world units on the root)
    this.tornado = this._buildTornado();
    root.add(this.tornado.group);
    // ---- CRT dot / line glows for teleports and the goodnight collapse
    const dotMat = new THREE.SpriteMaterial({ map: glowTexture(), color: new THREE.Color('#F4EEFF').multiplyScalar(3), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false });
    this.dot = new THREE.Sprite(dotMat);
    this.dot.visible = false;
    this.fxRoot = new THREE.Group();
    this.fxRoot.name = 'boss_baron_fx';
    this.fxRoot.add(this.dot);
    const lineMat = new THREE.MeshBasicMaterial({ map: lineTexture(), color: new THREE.Color('#F4EEFF').multiplyScalar(3), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false, side: THREE.DoubleSide });
    this.line = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), lineMat);
    this.line.visible = false;
    this.fxRoot.add(this.line);
    // ---- off-air shimmer (a 10 % additive copy of the silhouette, on layer 0)
    this._buildShimmer();
    root.traverse((o) => { if (o.isMesh || o.isSprite) o.frustumCulled = o.isSkinnedMesh ? false : o.frustumCulled; });
    this.built = true;
  }

  // Primitive stand-in body (only when the bake is missing or ?art=0): same joints and proportions.
  _standInBody() {
    const g = this.game;
    const joints = {};
    const rootJ = new THREE.Group();
    const mk = (name, parent, pos) => { const o = new THREE.Object3D(); o.name = name; o.position.set(...pos); (parent ? joints[parent] : rootJ).add(o); joints[name] = o; return o; };
    mk('base', null, [0, 0, 0]); mk('chest', 'base', [0, 0.3, 0]); mk('head', 'chest', [0, 0.34, 0.01]);
    mk('shoulderL', 'chest', [-0.31, 0.275, 0.01]); mk('elbowL', 'shoulderL', [-0.15, -0.295, -0.03]); mk('handL', 'elbowL', [-0.09, -0.28, -0.05]);
    mk('shoulderR', 'chest', [0.31, 0.275, 0.01]); mk('elbowR', 'shoulderR', [0.15, -0.295, -0.03]); mk('handR', 'elbowR', [0.09, -0.28, -0.05]);
    const tux = g.mats.toon('#1A1A2E', { rough: 0.45, keepColor: true, rim: 0.4, rimColor: '#C9A0FF' });
    const white = g.mats.toon('#F7F4EC', { rough: 0.5, keepColor: true });
    joints.base.add(K.m(new THREE.SphereGeometry(0.22, 20, 14), tux, { pos: [0, 0.3, 0], scale: [1.15, 1.5, 0.75] }));
    for (const s of ['L', 'R']) {
      joints['shoulder' + s].add(K.m(new THREE.CapsuleGeometry(0.07, 0.25, 6, 10), tux, { pos: [s === 'L' ? -0.075 : 0.075, -0.15, 0] }));
      joints['elbow' + s].add(K.m(new THREE.CapsuleGeometry(0.06, 0.22, 6, 10), tux, { pos: [s === 'L' ? -0.045 : 0.045, -0.14, -0.02] }));
      joints['hand' + s].add(K.m(new THREE.SphereGeometry(0.12, 16, 12), white, { pos: [0, -0.1, 0] }));
    }
    const group = new THREE.Group();
    group.add(rootJ);
    return { group, rig: { root: rootJ, joints }, skinnedMesh: null, standIn: true };
  }

  // The walnut console-TV head. Local frame: origin at the neck, y up, front = -z. World units (1.6 × 1.3 × 1.2 m).
  _buildHead() {
    const g = this.game;
    const W = 1.6, H = 1.3, D = 1.2, Y0 = 0.08, CY = Y0 + H / 2;
    const SCR = { w: 0.98, h: 0.76, x: 0.17, y: CY + 0.03 };      // local +x = the viewer's left: screen left, controls right
    const grp = K.prop('baron_head');
    const kc = { keepColor: true };
    const walnut = K.mat(g, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.45 }), ...kc });
    const cream = K.mat(g, 'plastic', '#EEDFC0', { rough: 0.38, ...kc });
    const liner = K.mat(g, 'plastic', '#241A2C', { rough: 0.3, ...kc });
    const chrome = K.mat(g, 'chrome', '#B9C1CB', kc);
    const brass = K.mat(g, 'brass', '#C8963C', kc);
    const backMat = K.mat(g, 'paint', '#3A2A22', kc);
    const grille = K.mat(g, 'fabric', '#ffffff', { map: K.tex.weave('#B88A4A', { pattern: 'cord' }), ...kc });
    // carcass: a pillowy walnut box + a puffy lid overhang + a brass pinstripe band
    grp.add(K.m(K.cushion(W, H, D, { r: 0.17, puff: 0.022, uv: 1.2 }), walnut, { pos: [0, CY, 0] }));
    grp.add(K.m(K.box(W + 0.05, 0.08, D + 0.05, 0.04, { uv: 1.2, swap: true }), walnut, { pos: [0, Y0 + H - 0.01, 0] }));
    for (const y of [Y0 + 0.07, Y0 + H - 0.075]) grp.add(K.m(K.box(W + 0.012, 0.018, D + 0.012, 0.008), brass, { pos: [0, y, 0] }));
    // cream bezel (hole = the screen window) + dark liner tunnel
    const bez = K.roundRect(1.48, 1.14, 0.12);
    const hole = new THREE.Path();
    const hx = -SCR.x, hy = SCR.y - CY, hw = SCR.w / 2 + 0.03, hh = SCR.h / 2 + 0.03, hr = 0.1;
    hole.moveTo(hx - hw + hr, hy - hh); hole.lineTo(hx + hw - hr, hy - hh); hole.quadraticCurveTo(hx + hw, hy - hh, hx + hw, hy - hh + hr);
    hole.lineTo(hx + hw, hy + hh - hr); hole.quadraticCurveTo(hx + hw, hy + hh, hx + hw - hr, hy + hh); hole.lineTo(hx - hw + hr, hy + hh);
    hole.quadraticCurveTo(hx - hw, hy + hh, hx - hw, hy + hh - hr); hole.lineTo(hx - hw, hy - hh + hr); hole.quadraticCurveTo(hx - hw, hy - hh, hx - hw + hr, hy - hh);
    bez.holes.push(hole);
    const bezel = K.m(K.extrude(bez, 0.05, { bevel: 0.018 }), cream, { pos: [0, CY, -D / 2 + 0.035], rot: [0, Math.PI, 0] });
    grp.add(bezel);
    grp.add(K.m(K.box(SCR.w + 0.1, SCR.h + 0.1, 0.06, 0.09), liner, { pos: [SCR.x, SCR.y, -D / 2 - 0.005] }));
    // the screen: rubber glass bulging out of the bezel, showing the Baron's face
    const face = g.cards.animated('baron', { owner: 'boss' });
    const scrMat = g.mats.rubberGlass(face.texture, { w: SCR.w, h: SCR.h, bright: 1.18, bulge: 0.07 });
    const screen = new THREE.Mesh(g.mats.screenGeometry(SCR.w, SCR.h), scrMat);
    screen.name = 'baron_screen';
    screen.position.set(SCR.x, SCR.y, -D / 2 - 0.045);
    screen.rotation.y = Math.PI;
    screen.userData.noMerge = true; screen.userData.noAO = true; screen.userData.noOcclude = true;
    screen.castShadow = false;
    grp.add(screen);
    const crackMat = new THREE.MeshBasicMaterial({ map: g.cards.get('crack_overlay'), transparent: true, depthWrite: false, toneMapped: false, color: new THREE.Color(1.25, 1.25, 1.3) });
    const crack = new THREE.Mesh(new THREE.PlaneGeometry(SCR.w * 0.98, SCR.h * 0.98), crackMat);
    crack.position.set(SCR.x, SCR.y, -D / 2 - 0.13);
    crack.rotation.y = Math.PI;
    crack.renderOrder = 3;
    crack.visible = false;
    crack.userData.noMerge = true; crack.userData.noAO = true; crack.userData.noOcclude = true;
    grp.add(crack);
    // control column: channel knob (stuck on "0"), volume knob, the CH 0 window, a brass speaker grille
    const kx = -0.53, kz = -D / 2 - 0.02;
    const knob = (r, y) => {
      const k = K.m(K.cyl(r * 0.92, r, 0.075, { bevel: 0.015, seg: 24 }), chrome, { pos: [kx, y, kz], rot: [-Math.PI / 2, 0, 0] });
      grp.add(k);
      grp.add(K.m(K.box(r * 0.2, r * 1.3, 0.03, 0.006), liner, { pos: [kx, y + r * 0.2, kz - 0.085] }));
      grp.add(K.m(K.cyl(r * 1.18, r * 1.18, 0.012, { bevel: 0.004, seg: 24 }), brass, { pos: [kx, y, kz + 0.01], rot: [-Math.PI / 2, 0, 0] }));
    };
    knob(0.12, CY + 0.2);
    knob(0.085, CY - 0.06);
    const lab = K.m(new THREE.PlaneGeometry(0.2, 0.1), K.mat(g, 'plastic', '#ffffff', { map: K.tex.label('CH 0', { bg: '#161826', fg: '#5CFF6E', accent: '#3A2A22', w: 256, h: 128, wear: 0 }), rough: 0.3, ...kc }),
      { pos: [kx, CY + 0.4, -D / 2 - 0.028], rot: [0, Math.PI, 0] });
    grp.add(lab);
    grp.add(K.m(K.box(0.27, 0.27, 0.03, 0.03, { uv: 4 }), grille, { pos: [kx, CY - 0.33, -D / 2 - 0.012] }));
    for (let i = 0; i < 5; i++) grp.add(K.m(K.box(0.27, 0.012, 0.012, 0.004), brass, { pos: [kx, CY - 0.45 + i * 0.06, -D / 2 - 0.03] }));
    // back panel with vents; brass swivel collar under the cabinet
    grp.add(K.m(K.box(1.28, 0.98, 0.05, 0.03), backMat, { pos: [0, CY, D / 2 + 0.01] }));
    for (let i = 0; i < 6; i++) grp.add(K.m(K.box(0.9, 0.035, 0.03, 0.012), liner, { pos: [0, CY - 0.28 + i * 0.1, D / 2 + 0.035] }));
    grp.add(K.m(K.cyl(0.27, 0.33, 0.1, { bevel: 0.02, seg: 24 }), brass, { pos: [0, Y0 - 0.1, 0.02] }));
    // antenna horns: telescoping chrome rods from a dome, glowing tips (+ halo sprites)
    const top = Y0 + H + 0.03;
    grp.add(K.m(new THREE.SphereGeometry(0.14, 20, 10, 0, TAU, 0, Math.PI / 2), chrome, { pos: [0, top, 0.14] }));
    const tipMat = g.mats.glow('#D46BFF', 3.2);
    const halos = [], tips = [], ants = [];
    for (const s of [-1, 1]) {
      const ant = new THREE.Group();
      ant.name = s < 0 ? 'antennaR' : 'antennaL';
      ant.position.set(s * 0.05, top + 0.05, 0.14);
      ant.rotation.z = -s * 0.62;
      ant.rotation.x = 0.1;
      ant.userData.noMerge = true;
      ant.userData.baseRot = ant.rotation.clone();
      const segs = [[0, 0.5, 0.042], [0.47, 0.95, 0.031], [0.92, 1.36, 0.022]];
      for (const [a, b, r] of segs) {
        ant.add(K.m(K.cyl(r * 0.9, r, b - a, { bevel: r * 0.4, seg: 10 }), chrome, { pos: [0, a, 0] }));
        ant.add(K.m(new THREE.SphereGeometry(r * 1.25, 10, 8), chrome, { pos: [0, a, 0] }));
      }
      const tip = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 12), tipMat);
      tip.position.set(0, 1.42, 0);
      tip.castShadow = false;
      tip.userData.noAO = true; tip.userData.noOcclude = true;
      ant.add(tip);
      const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(), color: new THREE.Color('#C95BFF').multiplyScalar(1.6), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false }));
      halo.position.copy(tip.position);
      halo.scale.setScalar(0.75);
      ant.add(halo);
      grp.add(ant);
      ants.push(ant); tips.push(tip); halos.push(halo);
    }
    K.finish(g, grp, { ao: { res: 40, strength: 0.75, floor: false, height: 0, skip: (m) => m === screen || m === crack || tips.includes(m) } });
    const api = {
      group: grp, screen, crack, face, scrMat, tips, halos, ants, W, H, D, Y0, CY, SCR,
      wobble: 0, antennaSpark: 0, faceMode: 'laugh',
      screenWorld: () => screen.getWorldPosition(_v2),
    };
    return api;
  }

  // Cape: a curved cloth sheet hanging from behind the shoulders (chest-local, model units). The vertex hook wobbles
  // it (amplitude grows toward the hem) and drags it against the motion. Outside black satin, plum lining inside.
  _buildCape() {
    const g = this.game;
    const NU = 22, NV = 26, L = 1.02;
    const pos = new Float32Array((NU + 1) * (NV + 1) * 3), ca = new Float32Array((NU + 1) * (NV + 1) * 2);
    let k = 0;
    for (let j = 0; j <= NV; j++) {
      const v = j / NV;
      for (let i = 0; i <= NU; i++) {
        const u = i / NU;
        const th = lerp(-1.95 + 3.9 * u, -1.55 + 3.1 * u, v);
        let r = lerp(0.27, 0.56, Math.pow(v, 0.8)) + 0.034 * v * Math.sin(th * 6.2 + 0.6);
        const cz = lerp(0.05, 0.2, v);
        const x = Math.sin(th) * r * 1.12;
        const z = cz + Math.cos(th) * r * 0.78;
        const y = 0.255 - L * v + 0.03 * Math.pow(v, 4) * Math.sin(th * 6.2 + 1.4);
        pos[k * 3] = x; pos[k * 3 + 1] = y; pos[k * 3 + 2] = z;
        ca[k * 2] = u; ca[k * 2 + 1] = v;
        k++;
      }
    }
    const idx = [];
    for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) {
      const a = j * (NU + 1) + i, b = a + 1, c = a + NU + 1, d = c + 1;
      idx.push(a, c, b, b, c, d);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('aCape', new THREE.BufferAttribute(ca, 2));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    geo.computeBoundingSphere();
    geo.boundingSphere.radius += 0.3;
    // the front side must face away from the body (+z, behind): check the middle vertex normal
    const mid = Math.floor(NV / 2) * (NU + 1) + Math.floor(NU / 2);
    const outward = geo.attributes.normal.getZ(mid) > 0;
    const U = { uCapeT: { value: 0 }, uCapeAmp: { value: 0.05 }, uCapeDrag: { value: new THREE.Vector3() } };
    const make = (color, side, name) => {
      const m = g.mats.toon(color, { rough: 0.42, rim: 0.5, rimColor: '#C9A0FF', keepColor: true, side, name, wrap: 0.6 });
      const orig = m.onBeforeCompile;
      m.onBeforeCompile = (sh, r) => {
        orig(sh, r);
        Object.assign(sh.uniforms, U);
        sh.vertexShader = sh.vertexShader
          .replace('#include <common>', '#include <common>\nattribute vec2 aCape;\nuniform float uCapeT;\nuniform float uCapeAmp;\nuniform vec3 uCapeDrag;')
          .replace('#include <begin_vertex>', `#include <begin_vertex>
{
  float cu = aCape.x, cv = aCape.y, th = ( cu - 0.5 ) * 3.4;
  float w = pow( cv, 1.45 ) * uCapeAmp;
  transformed.x += w * ( sin( uCapeT * 1.9 + th * 2.6 + cv * 5.0 ) * 0.7 + sin( uCapeT * 3.7 + th * 5.1 ) * 0.25 );
  transformed.z += w * ( cos( uCapeT * 1.6 + th * 1.8 + cv * 4.0 ) * 0.8 + 0.45 );
  transformed.y += w * 0.3 * sin( uCapeT * 1.3 + cv * 3.0 + th );
  transformed += uCapeDrag * pow( cv, 1.6 );
}`);
      };
      m.customProgramCacheKey = () => 'datoon1-cape';
      return m;
    };
    const outer = new THREE.Mesh(geo, make('#1C1628', outward ? THREE.FrontSide : THREE.BackSide, 'baronCapeOuter'));
    const inner = new THREE.Mesh(geo, make('#7E2250', outward ? THREE.BackSide : THREE.FrontSide, 'baronCapeInner'));
    outer.castShadow = true; inner.castShadow = false;
    outer.frustumCulled = inner.frustumCulled = false;
    const group = new THREE.Group();
    group.name = 'baron_cape';
    group.add(outer, inner);
    return { group, U, outer, inner };
  }

  // Static tornado: two nested open cones (world units) with the spiral static shader.
  _buildTornado() {
    const group = new THREE.Group();
    group.name = 'baron_tornado';
    const cone = (rTop, len, NU = 30, NV = 18) => {
      const pos = [], uv = [], idx = [];
      for (let j = 0; j <= NV; j++) {
        const v = j / NV;
        const r = lerp(rTop, 0.04, Math.pow(v, 0.8)) * (1 + 0.12 * Math.sin(v * 9.0));
        for (let i = 0; i <= NU; i++) {
          const a = (i / NU) * TAU;
          pos.push(Math.cos(a) * r, 0.34 - len * v, Math.sin(a) * r);
          uv.push(i / NU, v);
        }
      }
      for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) {
        const a = j * (NU + 1) + i, b = a + 1, c = a + NU + 1, d = c + 1;
        idx.push(a, b, c, b, d, c);
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      return geo;
    };
    const mk = (alpha, gain, spin, a, b) => {
      const m = new THREE.ShaderMaterial({
        uniforms: { uTime: { value: 0 }, uAlpha: { value: alpha }, uGain: { value: gain }, uSpin: { value: spin }, uSway: { value: 0.35 }, uReach: { value: 1 },
          uA: { value: new THREE.Color(a) }, uB: { value: new THREE.Color(b) } },
        vertexShader: TORNADO_VERT, fragmentShader: TORNADO_FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false,
      });
      m.userData.alpha = alpha;
      return m;
    };
    const outerMat = mk(0.7, 1.2, 0.8, '#1E1630', '#6C5A9C');
    const innerMat = mk(0.55, 1.35, 1.7, '#2E2250', '#A898D8');
    const outer = new THREE.Mesh(cone(0.82, 3.4), outerMat);
    const inner = new THREE.Mesh(cone(0.5, 3.1), innerMat);
    outer.renderOrder = 1; inner.renderOrder = 2;
    outer.frustumCulled = inner.frustumCulled = false;
    group.add(outer, inner);
    return { group, mats: [outerMat, innerMat], outer, inner };
  }

  _buildShimmer() {
    const mat = new THREE.MeshBasicMaterial({ color: '#B9C6FF', transparent: true, opacity: 0.1, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
    this._shimmerMat = mat;
    this._shimmer = [];
    const sm = this.char.skinnedMesh;
    if (sm) {
      const s = new THREE.SkinnedMesh(sm.geometry, mat);
      s.bind(sm.skeleton, sm.bindMatrix);
      s.frustumCulled = false;
      s.visible = false;
      s.name = 'baron_shimmer_body';
      sm.parent.add(s);
      this._shimmer.push(s);
    }
    const h = this.head;
    const hb = new THREE.Mesh(K.box(h.W, h.H, h.D, 0.15), mat);
    hb.position.set(0, h.CY, 0);
    hb.visible = false;
    hb.name = 'baron_shimmer_head';
    h.group.add(hb);
    this._shimmer.push(hb);
    const cone = new THREE.Mesh(new THREE.ConeGeometry(0.6, 3.2, 16, 1, true), mat);
    cone.rotation.x = Math.PI;
    cone.position.y = -1.4;
    cone.visible = false;
    this.root.add(cone);
    this._shimmer.push(cone);
  }

  _setLayers(layer) {
    if (!this.root) return;
    this.game.render?.setLayerRecursive?.(this.root, layer);
    for (const s of this._shimmer || []) s.layers.set(LAYERS.WORLD);
    this.dot.layers.set(LAYERS.WORLD);
    this.line.layers.set(LAYERS.WORLD);
    this._layer = layer;
  }

  _setFace(mode) {
    const h = this.head;
    if (!h) return;
    h.faceMode = mode;
    if (mode === 'bars') {
      h.scrMat.map = this.game.cards.get('color_bars');
      return;
    }
    h.scrMat.map = h.face.texture;
    const variant = mode === 'laugh' ? 'laugh' : mode;
    if (h.face.opts?.variant !== variant) h.face.set({ variant });
  }

  // CRT warm-up / power-off of the whole figure: k = 0 dot, 0.45 line, 1 full. The glowing dot and line live in the
  // unscaled fxRoot (placed at his chest every frame).
  _dotScale(k) {
    const root = this.root;
    k = clamp(k, 0, 1);
    let sx, sy;
    if (k < 0.45) { sx = Math.max(0.002, smooth(k / 0.45)); sy = 0.012; } else { sx = 1; sy = lerp(0.012, 1, easeOutBack((k - 0.45) / 0.55, 1.2)); }
    root.scale.set(sx, sy, sx);
    const show = k < 0.999;
    this.dot.visible = show && k < 0.32;
    this.line.visible = show && k > 0.04 && k < 0.78;
    if (this.dot.visible) {
      const s = k < 0.12 ? lerp(0.5, 1.7, k / 0.12) : lerp(1.7, 0.4, (k - 0.12) / 0.2);
      this.dot.scale.set(s, s, 1);
    }
    if (this.line.visible) {
      this.line.quaternion.copy(this.game.camera.quaternion);
      this.line.scale.set(Math.max(0.05, 4.4 * sx), 0.22, 1);
      this.line.material.opacity = k < 0.45 ? 1 : 1 - (k - 0.45) / 0.33;
    }
  }

  _restoreScale() {
    if (!this.root) return;
    this.root.scale.setScalar(1);
    this.dot.visible = false;
    this.line.visible = false;
  }

  // ============================================================================================ animation
  // Idle hover sway + gestures (volley throw, sweep spread, grab, wave) + the head, cape and tornado effects.
  _animateModel(dt, real) {
    const g = this.game, J = this.J, R = this._restPose, h = this.head;
    const t = real ? (this._rt = (this._rt || this._t) + dt) : this._t;
    const root = this.root;
    if (!root) return;
    root.position.copy(this.pos);
    root.rotation.set(0, this.yaw, 0);
    if (this.fxRoot) this.fxRoot.position.set(this.pos.x, this.pos.y + 1.1, this.pos.z);
    if (this._shake > 0) {
      this._shake = Math.max(0, this._shake - dt * 3);
      root.position.x += (Math.random() - 0.5) * this._shake * 0.3;
      root.position.y += (Math.random() - 0.5) * this._shake * 0.2;
    }
    // ---- joints (rest + offsets)
    for (const [n, j] of Object.entries(J)) if (R[n]) j.rotation.copy(R[n]);
    J.chest.rotation.z += Math.sin(t * 0.9) * 0.045;
    J.chest.rotation.x += -0.05 + Math.sin(t * 0.7) * 0.03;
    J.head.rotation.z += Math.sin(t * 1.1 + 0.4) * 0.05;
    J.head.rotation.x += Math.sin(t * 0.8) * 0.03 - 0.04;
    let armL = { x: 0.25 + Math.sin(t * 1.2) * 0.1, z: -0.12 + Math.sin(t * 1.05) * 0.08, e: 0.45 + Math.sin(t * 1.4) * 0.12, h: 0 };
    let armR = { x: 0.25 + Math.sin(t * 1.2 + 1.1) * 0.1, z: 0.12 - Math.sin(t * 1.05 + 0.7) * 0.08, e: 0.45 + Math.sin(t * 1.4 + 0.9) * 0.12, h: 0 };
    const ge = this._gesture;
    if (ge) {
      ge.t += dt;
      if (ge.kind === 'throw') {
        const u = ge.t / 0.7;
        const up = u < 0.45 ? smooth(u / 0.45) : 1 - smooth((u - 0.45) / 0.55);
        armR = { x: 0.25 + up * 1.6, z: 0.35 * up, e: 0.2 + up * 0.3, h: -0.4 * up };
        if (u >= 1) this._gesture = null;
      } else if (ge.kind === 'spread') {
        const u = Math.min(1, ge.t / 0.4);
        const s = smooth(u);
        armL = { x: 0.5 * s + 0.2, z: -0.9 * s, e: 0.25, h: 0.4 * s };
        armR = { x: 0.5 * s + 0.2, z: 0.9 * s, e: 0.25, h: -0.4 * s };
        if (ge.t > (ge.dur || 3.7)) this._gesture = null;
      } else if (ge.kind === 'wave') {
        const w = Math.sin(ge.t * 7.5);
        armR = { x: 1.1, z: 1.25 + w * 0.22, e: 1.2 + w * 0.2, h: 0.2 };
        armL = { x: 0.45, z: -0.25, e: 0.9, h: 0 };
      } else if (ge.kind === 'hurt') {
        const k = Math.max(0, 1 - ge.t / 0.45);
        J.chest.rotation.x -= 0.22 * k;
        J.head.rotation.x -= 0.18 * k;
        if (ge.t > 0.45) this._gesture = null;
      }
    }
    const gr = this._grab;
    if (gr) {
      if (gr.phase === 'windup') {
        const s = smooth(gr.t / B.p3.grabWindup);
        armL = { x: 0.3 + 1.9 * s, z: -0.35 * s, e: 0.15, h: 0.5 * s };
        armR = { x: 0.3 + 1.9 * s, z: 0.35 * s, e: 0.15, h: -0.5 * s };
      } else if (gr.phase === 'strike' || gr.phase === 'recover') {
        const s = gr.phase === 'strike' ? smooth(gr.t / 0.18) : 1 - smooth(gr.t / 0.8);
        armL = { x: lerp(0.3, 1.1, s), z: lerp(-0.1, 0.25, s), e: 0.6 * s, h: -0.9 * s };
        armR = { x: lerp(0.3, 1.1, s), z: lerp(0.1, -0.25, s), e: 0.6 * s, h: 0.9 * s };
      }
    }
    if (this._transT > 0) {
      const k = Math.min(1, (TRANSITION - this._transT) / 0.3);
      armL = { x: 1.2 * k, z: -1.1 * k, e: 1.4 * k, h: 0.5 };
      armR = { x: 1.2 * k, z: 1.1 * k, e: 1.4 * k, h: -0.5 };
      J.chest.rotation.x -= 0.2 * k;
    }
    J.shoulderL.rotation.x += armL.x; J.shoulderL.rotation.z += armL.z; J.elbowL.rotation.x += armL.e; J.handL.rotation.z += armL.h;
    J.shoulderR.rotation.x += armR.x; J.shoulderR.rotation.z += armR.z; J.elbowR.rotation.x += armR.e; J.handR.rotation.z += armR.h;
    // ---- head: face card, bulge, wobble, antennas (twitch, glow, sparks)
    if (h) {
      try { h.face.tick(real ? g.time.realNow : this._t); } catch { /* optional */ }
      const u = h.scrMat.uniforms;
      h.wobble = Math.max(0, h.wobble - dt * 2.2);
      if (u.uWobble) u.uWobble.value = h.wobble;
      if (u.uBulge) u.uBulge.value = 0.07 + 0.03 * Math.sin(t * 2.3) + h.wobble * 0.08 + (this._sweep && this._sweep.phase === 'tele' ? 0.05 : 0);
      if (u.uBright) u.uBright.value = 1.18 + (this._sweep && this._sweep.phase === 'tele' ? 0.9 * (0.5 + 0.5 * Math.sin(t * 30)) : 0);
      for (let i = 0; i < h.ants.length; i++) {
        const a = h.ants[i], br = a.userData.baseRot;
        const tw = (this._sparking ? 0.12 : 0.04) * Math.sin(t * (i ? 9.1 : 7.3)) + (Math.random() < dt * 2 ? (Math.random() - 0.5) * 0.25 : 0);
        a.rotation.set(br.x + Math.sin(t * 1.7 + i) * 0.05, br.y, br.z + tw);
        const glow = this._sparking ? 0.6 + Math.random() * 1.2 : 1 + 0.25 * Math.sin(t * 4 + i * 2);
        h.halos[i].scale.setScalar(0.75 * glow);
        if (this._sparking && Math.random() < dt * 5) {
          h.tips[i].getWorldPosition(_v3);
          g.fx?.burst?.(_v3, { shape: 'spark', count: 6, speed: 5, size: 0.05, life: 0.35, colors: ['#FFFFFF', '#E7B8FF', '#FFE27A'] });
          if (Math.random() < 0.3) g.audio?.play?.('hurt_static', { pos: _v3, vol: 0.35, rate: 1.6 });
        }
      }
    }
    // ---- cape: wobble + drag against the motion (chest-local, model units)
    if (this.cape) {
      const U = this.cape.U;
      U.uCapeT.value = t;
      const vel = this._vel || _v3.set(0, 0, 0);
      const sp = Math.min(3, vel.length());
      U.uCapeAmp.value = 0.05 + sp * 0.025;
      _v4.copy(vel).multiplyScalar(-0.035);
      _q.copy(root.quaternion).invert();
      _v4.applyQuaternion(_q);
      U.uCapeDrag.value.lerp(_v4, 1 - Math.exp(-(dt || 0.016) * 3));
    }
    // ---- tornado
    if (this.tornado) {
      const ms = this.tornado.mats;
      const reach = this._sweep && this._sweep.phase !== 'done' ? Math.max(1, (this.pos.y - this._floorY()) / 3.1) : 1;
      for (const m of ms) {
        m.uniforms.uTime.value = t;
        m.uniforms.uSway.value = 0.35 + Math.min(1, (this._vel ? this._vel.length() : 0) * 0.2);
        m.uniforms.uReach.value += (reach - m.uniforms.uReach.value) * (1 - Math.exp(-(dt || 0.016) * 6));
      }
      this._staticT = (this._staticT || 0) - dt;
      if (this._staticT <= 0 && root.visible && this._layer !== LAYERS.TV_ONLY) {
        this._staticT = 0.08;
        const a = Math.random() * TAU, v = Math.random();
        _v3.set(this.pos.x + Math.cos(a) * (0.6 - v * 0.5), this.pos.y - v * 3.0, this.pos.z + Math.sin(a) * (0.6 - v * 0.5));
        g.fx?.burst?.(_v3, { shape: 'static', count: 1, speed: 0.8, size: 0.14, life: 0.5 });
      }
    }
    // ---- knife switch THUNK
    const sa = this._switchAnim;
    if (sa) {
      sa.t += real ? dt : dt;
      const k = Math.min(1, sa.t / 0.22);
      sa.part.rotation.x = lerp(sa.from, 1.9, easeOutBack(k, 2.2));
      if (k >= 1) this._switchAnim = null;
    }
    // ---- whiteout pulse (intro)
    if (this._whiteout > 0 && g.render?.post) {
      this._whiteout = Math.max(0, this._whiteout - (dt || 0.016) * 1.2);
      g.render.post.whiteout = Math.max(g.render.post.whiteout || 0, this._whiteout);
    }
    // ---- off-air shimmer flicker
    if (this._shimmerMat && this._layer === LAYERS.TV_ONLY) this._shimmerMat.opacity = 0.07 + 0.05 * Math.random();
  }

  // ============================================================================================ attacks
  // ---- channel hopping: CRT dot-out, jump along the ring, dot-in
  _startHop() {
    const g = this.game;
    const a = this._pickRingAngle(g.player?.pos || TOWER, this.pos);
    this._ringA = a;
    this._hop = { t: 0, to: this._ringPoint(a, new THREE.Vector3(), this._hoverY), moved: false };
    g.audio?.play?.('boss_teleport', { pos: this.pos });
    this._vel = null;
  }

  _updateHop(dt) {
    const g = this.game, h = this._hop;
    h.t += dt;
    if (h.t < HOP.out) {
      this._dotScale(1 - h.t / HOP.out);
    } else if (!h.moved) {
      h.moved = true;
      _v.copy(this.pos).setY(this.pos.y + 1.2);
      g.fx?.burst?.(_v, { shape: 'static', count: 22, speed: 4, size: 0.22, life: 0.5 });
      this.pos.x = h.to.x; this.pos.z = h.to.z;
      const p = g.player;
      if (p) this.yaw = yawTo(p.pos.x - this.pos.x, p.pos.z - this.pos.z);
      this._dotScale(0);
      this.root.visible = false;
      this.dot.visible = this.line.visible = false;
    } else if (h.t < HOP.out + 0.12) {
      this.root.visible = false;
      this.dot.visible = this.line.visible = false;
    } else {
      this.root.visible = true;
      const k = (h.t - HOP.out - 0.12) / HOP.in;
      this._dotScale(k);
      if (k >= 1) {
        this._restoreScale();
        this._hop = null;
        this._hopT = B.p1.hopEvery;
        _v.copy(this.pos).setY(this.pos.y + 1.2);
        g.fx?.burst?.(_v, { shape: 'confetti', count: 10, colors: PAL.BARS, speed: 4, size: 0.12 });
      }
    }
  }

  // ---- static balls: volleys of 3, weakly homing
  _volley() {
    const g = this.game, p = g.player;
    if (!p || !p.alive) return;
    this._gesture = { kind: 'throw', t: 0 };
    this.J.handR.getWorldPosition(_o);
    _o.y += 0.2;
    const target = _v.set(p.pos.x, p.pos.y + 1.1, p.pos.z);
    _d.subVectors(target, _o).normalize();
    const spread = 0.24;
    for (let i = -1; i <= 1; i++) {
      const dir = _v2.copy(_d).applyAxisAngle(_v3.set(0, 1, 0), i * spread);
      dir.y += Math.abs(i) * 0.04;
      dir.normalize();
      this._spawnBall(_o, dir.multiplyScalar(B.p1.ballSpeed), i * 0.06);
    }
    if (Math.random() < 0.35 && this._voiceT <= 0) { this._voiceT = 3; g.audio?.play?.('boss_voice', { pos: this.pos, syllables: 3 }); }
  }

  _ballPool() {
    if (this._ballMat) return;
    this._ballGeo = new THREE.IcosahedronGeometry(0.28, 2);
    this._ballMat = new THREE.ShaderMaterial({ uniforms: { uTime: { value: 0 }, uCol: { value: new THREE.Color('#B574FF') } }, vertexShader: BALL_VERT, fragmentShader: BALL_FRAG, fog: false });
    this._ballHalo = new THREE.SpriteMaterial({ map: glowTexture(), color: new THREE.Color('#A86BFF').multiplyScalar(1.1), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false });
  }

  _spawnBall(from, vel, delay = 0) {
    const g = this.game;
    this._ballPool();
    let b = this._balls.find((x) => !x.alive);
    if (!b) {
      if (this._balls.length >= 14) return null;
      const mesh = new THREE.Mesh(this._ballGeo, this._ballMat);
      const halo = new THREE.Sprite(this._ballHalo);
      halo.scale.setScalar(1.05);
      mesh.add(halo);
      mesh.castShadow = false;
      b = { mesh, halo, pos: new THREE.Vector3(), vel: new THREE.Vector3(), alive: false };
      this._balls.push(b);
    }
    b.alive = true;
    b.life = 5.5;
    b.delay = delay;
    b.trail = 0;
    b.pos.copy(from);
    b.vel.copy(vel);
    b.mesh.position.copy(from);
    b.mesh.visible = delay <= 0;
    b.mesh.scale.setScalar(0.2);
    b.age = 0;
    if (!b.mesh.parent) g.scene.add(b.mesh);
    b.loop = null;
    try { b.loop = g.audio?.loop?.('boss_static_ball', { pos: from, vol: 0.55 }) || null; } catch { b.loop = null; }
    return b;
  }

  _popBall(b, hitPlayer = false) {
    const g = this.game;
    b.alive = false;
    b.mesh.visible = false;
    if (b.loop) { try { b.loop.stop(0.05); } catch { /* optional */ } b.loop = null; }
    g.fx?.burst?.(b.pos, { shape: 'static', count: hitPlayer ? 26 : 14, speed: hitPlayer ? 5 : 3, size: 0.2, life: 0.5 });
    g.fx?.burst?.(b.pos, { shape: 'spark', count: 8, speed: 5, size: 0.05, colors: ['#FFFFFF', '#C9A0FF'], life: 0.3 });
    if (hitPlayer) g.fx?.flashLight?.(b.pos, '#B77BFF', 6, 0.25);
  }

  _clearBalls() {
    for (const b of this._balls) if (b.alive) this._popBall(b);
  }

  _updateBalls(dt) {
    const g = this.game, p = g.player, col = g.level?.col;
    if (this._ballMat) this._ballMat.uniforms.uTime.value = this._t;
    const maxTurn = THREE.MathUtils.degToRad(15) * dt;
    for (const b of this._balls) {
      if (!b.alive) continue;
      if (b.delay > 0) { b.delay -= dt; if (b.delay > 0) continue; b.mesh.visible = true; }
      b.age += dt;
      b.life -= dt;
      if (b.life <= 0) { this._popBall(b); continue; }
      // weak homing toward the player's chest
      if (p && p.alive) {
        _v.set(p.pos.x, p.pos.y + 1.0, p.pos.z).sub(b.pos).normalize();
        _v2.copy(b.vel).normalize();
        const ang = _v2.angleTo(_v);
        if (ang > 1e-4) {
          _v3.crossVectors(_v2, _v).normalize();
          b.vel.applyAxisAngle(_v3, Math.min(ang, maxTurn));
        }
      }
      const step = b.vel.length() * dt;
      _d.copy(b.vel).normalize();
      const hit = col?.raycast?.(b.pos, _d, step + 0.25);
      b.pos.addScaledVector(b.vel, dt);
      b.mesh.position.copy(b.pos);
      b.mesh.rotation.x += dt * 5; b.mesh.rotation.y += dt * 7;
      const s = Math.min(1, b.age / 0.15) * (1 + 0.12 * Math.sin(b.age * 40));
      b.mesh.scale.setScalar(s);
      b.halo.material.rotation = b.age * 3;
      if (b.loop) try { b.loop.setPos(b.pos); } catch { /* optional */ }
      b.trail -= dt;
      if (b.trail <= 0) { b.trail = 0.04; g.fx?.burst?.(b.pos, { shape: 'static', count: 1, speed: 0.4, size: 0.12, life: 0.35 }); }
      if (hit && hit.dist <= step + 0.25) { this._popBall(b); continue; }
      // player capsule (feet+0.3 .. feet+1.5)
      if (p && p.alive) {
        const cy = clamp(b.pos.y, p.pos.y + 0.3, p.pos.y + 1.5);
        const dx = b.pos.x - p.pos.x, dy = b.pos.y - cy, dz = b.pos.z - p.pos.z;
        if (dx * dx + dy * dy + dz * dz < (0.28 + (p.radius || 0.38)) ** 2) {
          p.hurt?.(B.p1.ballDmg, b.pos.clone());
          g.audio?.play?.('hurt_static', { pos: b.pos, vol: 0.8 });
          this._popBall(b, true);
          continue;
        }
      }
      if (b.pos.y < this._floorY(b.pos.x, b.pos.z) + 0.15) this._popBall(b);
    }
  }

  // ---- phase 2: the test-pattern sweep
  _sweepAssets() {
    if (this._blade) return;
    const g = this.game;
    const bars = barColors();
    const len = B.p2.beamR - 0.4;
    const bg = new THREE.PlaneGeometry(len, B.p2.beamTop, 28, 1);
    bg.translate(0.4 + len / 2, B.p2.beamTop / 2, 0);
    this._bladeMat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 }, uAlpha: { value: 1 }, uBars: { value: bars } },
      vertexShader: WALL_VERT, fragmentShader: BLADE_FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, fog: false,
    });
    const blade = new THREE.Mesh(bg, this._bladeMat);
    blade.frustumCulled = false;
    // glow wall above the blade (soft)
    const NU = 48, NV = 8, pos = [], uv = [], idx = [];
    for (let j = 0; j <= NV; j++) for (let i = 0; i <= NU; i++) {
      const u = i / NU, v = j / NV, a = u * Math.PI, r = lerp(0.5, B.p2.beamR, v);
      pos.push(Math.cos(a) * r, 0, Math.sin(a) * r);
      uv.push(u, v);
    }
    for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) {
      const a = j * (NU + 1) + i, b = a + 1, c = a + NU + 1, d = c + 1;
      idx.push(a, b, c, b, d, c);
    }
    const fg = new THREE.BufferGeometry();
    fg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    fg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    fg.setIndex(idx);
    this._fanMat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 }, uAlpha: { value: 0 }, uSweep: { value: -1 }, uPulse: { value: 0 }, uBars: { value: bars } },
      vertexShader: WALL_VERT, fragmentShader: FAN_FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, fog: false,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
    });
    const fan = new THREE.Mesh(fg, this._fanMat);
    fan.frustumCulled = false;
    fan.renderOrder = 2;
    const group = new THREE.Group();
    group.name = 'baron_sweep';
    const bladeHolder = new THREE.Group();
    bladeHolder.add(blade);
    group.add(fan, bladeHolder);
    group.visible = false;
    this._blade = { group, fan, blade, bladeHolder };
    g.scene.add(group);
  }

  _startSweep() {
    const g = this.game, p = g.player;
    if (!p) return;
    this._sweepAssets();
    const fy = this._floorY();
    const center = new THREE.Vector3(this.pos.x, fy + 0.03, this.pos.z);
    const aP = Math.atan2(p.pos.z - center.z, p.pos.x - center.x);
    const dir = Math.random() < 0.5 ? 1 : -1;
    const a0 = aP - dir * Math.PI / 2;
    this._sweep = { phase: 'tele', t: 0, center, a0, dir, prevA: a0, hit: false };
    const bl = this._blade;
    bl.group.position.copy(center);
    bl.fan.rotation.set(0, -a0, 0);
    bl.fan.scale.set(1, 1, dir);
    bl.bladeHolder.visible = false;
    bl.group.visible = true;
    this._fanMat.uniforms.uSweep.value = -1;
    this._gesture = { kind: 'spread', t: 0, dur: B.p2.tele + B.p2.sweepTime + 0.2 };
    g.audio?.play?.('boss_sweep_warn', { pos: this.pos, vol: 1.1 });
    g.audio?.play?.('tone_1khz', { pos: this.pos, vol: 0.35 });
  }

  _updateSweep(dt) {
    const s = this._sweep;
    if (!s || !this._blade) return;
    const g = this.game, P = B.p2, U = this._fanMat.uniforms, bl = this._blade;
    s.t += dt;
    U.uTime.value = this._t;
    this._bladeMat.uniforms.uTime.value = this._t;
    if (s.phase === 'tele') {
      U.uAlpha.value = 0.16 + 0.14 * (0.5 + 0.5 * Math.sin(s.t * 18));
      U.uPulse.value = 0.4 * (s.t / P.tele);
      if (s.t >= P.tele) {
        s.phase = 'sweep'; s.t = 0;
        bl.bladeHolder.visible = true;
        this._bladeMat.uniforms.uAlpha.value = 1;
        g.audio?.play?.('boss_sweep', { pos: this.pos, vol: 1.2 });
        g.cam?.shake?.(0.12, P.sweepTime);
        g.input?.rumble?.(0.26, 0.08, P.sweepTime * 1000); // the beam's hum on the gamepad (weak motor)
      }
    } else if (s.phase === 'sweep') {
      const u = Math.min(1, s.t / P.sweepTime);
      const a = s.a0 + s.dir * Math.PI * u;
      bl.bladeHolder.rotation.y = -a;
      U.uSweep.value = u;
      U.uAlpha.value = 0.55;
      U.uPulse.value = 0.2;
      // damage: did the blade pass the player's angle this frame, with the feet below the beam top?
      const p = g.player;
      if (p && p.alive && !s.hit) {
        const dx = p.pos.x - s.center.x, dz = p.pos.z - s.center.z, r = Math.hypot(dx, dz);
        if (r > 0.4 && r < P.beamR + (p.radius || 0.38)) {
          const ap = Math.atan2(dz, dx);
          const d0 = angDiff(ap, s.prevA) * s.dir, d1 = angDiff(ap, a) * s.dir;
          const crossed = d0 >= -0.02 && d1 <= 0.02 + (p.radius || 0.38) / Math.max(1, r);
          const feet = p.pos.y - this._floorY(p.pos.x, p.pos.z);
          if (crossed && feet < P.beamTop) {
            s.hit = true;
            if (p.hurt?.(P.dmg, s.center.clone())) {
              g.fx?.burst?.(_v.set(p.pos.x, p.pos.y + 0.3, p.pos.z), { shape: 'confetti', count: 14, colors: PAL.BARS, speed: 5, size: 0.1 });
              p.knockback?.(_v2.set(dx, 0, dz).normalize().multiplyScalar(6));
            }
          }
        }
      }
      s.prevA = a;
      if (u >= 1) { s.phase = 'fade'; s.t = 0; }
    } else if (s.phase === 'fade') {
      const k = 1 - s.t / 0.45;
      U.uAlpha.value = 0.55 * Math.max(0, k);
      this._bladeMat.uniforms.uAlpha.value = Math.max(0, k);
      if (k <= 0) { this._stopSweep(); this._hopT = Math.min(this._hopT, 0.6); }
    }
  }

  _stopSweep() {
    if (this._blade) this._blade.group.visible = false;
    if (this._sweep) this._sweep.phase = 'done';
    this._sweep = null;
    if (this._gesture && this._gesture.kind === 'spread') this._gesture = null;
  }

  // ---- adds (over the fence climbs and the gate)
  _updateAdds(dt, n) {
    const alive = this._adds.size;
    if (n === 1) {
      this._addsT -= dt;
      if (this._addsT <= 0) { this._addsT = B.p1.addsEvery; this._spawnAdds('tuned_in', Math.min(3, B.p1.addsMax - alive)); }
    } else if (n === 2) {
      if (!this._hasAdd('forecaster')) {
        this._fcT -= dt;
        if (this._fcT <= 0) { this._fcT = 4; this._spawnAdds('forecaster', 1); }
      }
      this._socksT -= dt;
      if (this._socksT <= 0) { this._socksT = B.p2.socksEvery; this._spawnAdds('sock_hopper', Math.min(6, 14 - alive)); }
    } else if (n === 3) {
      this._addsT -= dt;
      if (this._addsT <= 0) { this._addsT = B.p3.addsEvery; this._spawnAdds('tuned_in', Math.min(3, B.p3.addsMax - alive)); }
    }
  }

  _updateAddsTick(dt) {
    this._voiceT = Math.max(0, (this._voiceT || 0) - dt);
    for (const z of this._adds) if (!z || z.dead || z.removed) this._adds.delete(z);
  }

  _hasAdd(type) {
    for (const z of this._adds) if (z.type === type && !z.dead) return true;
    return false;
  }

  _spawnAdds(type, count) {
    const Z = this.game.zombies;
    if (!Z || typeof Z.spawn !== 'function' || count <= 0) return 0;
    let n = 0;
    this._fenceI = this._fenceI || 0;
    for (let i = 0; i < count; i++) {
      const entry = FENCE[this._fenceI++ % FENCE.length];
      let z = null;
      try { z = Z.spawn(type, entry, null, {}); } catch (err) { this._err('spawn', err); }
      if (z) { this._adds.add(z); n++; }
    }
    return n;
  }

  _despawnAdds(fx = true) {
    const Z = this.game.zombies;
    for (const z of [...this._adds]) {
      if (!z || z.dead || z.removed) continue;
      try {
        if (fx) this.game.fx?.burst?.(_v.set(z.pos.x, z.pos.y + 0.8, z.pos.z), { shape: 'static', count: 14, speed: 2 });
        Z?.despawn?.(z, false);
      } catch { /* optional */ }
    }
    this._adds.clear();
  }

  // ---- phase 3: drift toward the player
  _updateDrift(dt) {
    const p = this.game.player;
    if (!p) return;
    const slow = this._grab ? (this._grab.phase === 'windup' ? 0.25 : 0) : 1;
    const dx = p.pos.x - this.pos.x, dz = p.pos.z - this.pos.z, d = Math.hypot(dx, dz);
    const want = 1.4;
    const prev = _v4.copy(this.pos);
    if (d > want && slow > 0) {
      const step = Math.min(d - want, B.p3.drift * slow * dt);
      this.pos.x += (dx / d) * step;
      this.pos.z += (dz / d) * step;
    }
    this.pos.x = clamp(this.pos.x, ARENA.x0 + 0.8, ARENA.x1 - 0.8);
    this.pos.z = clamp(this.pos.z, ARENA.z0 + 0.8, ARENA.z1 - 0.8);
    this._vel = (this._vel || new THREE.Vector3()).subVectors(this.pos, prev).divideScalar(Math.max(1e-4, dt));
  }

  // ---- phase 3: the grab
  _updateGrab(dt) {
    const g = this.game, p = g.player;
    if (!p) return;
    const dx = p.pos.x - this.pos.x, dz = p.pos.z - this.pos.z, d = Math.hypot(dx, dz);
    const gr = this._grab;
    if (!gr) {
      this._grabCd -= dt;
      if (this._grabCd <= 0 && d < B.p3.grabR && p.alive) {
        this._grab = { phase: 'windup', t: 0 };
        g.audio?.play?.('boss_grab', { pos: this.pos, vol: 1.1 });
        if (this.offAir) this._revealT = Math.max(this._revealT, B.p3.grabWindup + 0.5);
        this._voice('baron_laugh', 0.8);
      }
      return;
    }
    gr.t += dt;
    if (gr.phase === 'windup' && gr.t >= B.p3.grabWindup) {
      gr.phase = 'strike'; gr.t = 0;
      if (d < B.p3.grabR + 0.7 && p.alive) {
        if (p.hurt?.(B.p3.grabDmg, this.pos.clone())) {
          const l = d || 1;
          p.knockback?.(_v.set(dx / l, 0, dz / l).multiplyScalar(B.p3.throw * 6));
          if (p.vel) p.vel.y = Math.max(p.vel.y, 6.5);
          g.cam?.shake?.(0.6, 0.5);
          g.fx?.burst?.(_v.set(p.pos.x, p.pos.y + 1.2, p.pos.z), { shape: 'static', count: 30, speed: 5, size: 0.2 });
          g.audio?.play?.('boss_hurt', { pos: this.pos, vol: 0.6, rate: 1.4 });
        }
      } else {
        g.fx?.burst?.(_v.set(this.pos.x + dx * 0.4, this._floorY() + 0.2, this.pos.z + dz * 0.4), { shape: 'puff', count: 8, speed: 2, size: 0.3 });
      }
    } else if (gr.phase === 'strike' && gr.t >= 0.2) {
      gr.phase = 'recover'; gr.t = 0;
    } else if (gr.phase === 'recover' && gr.t >= 0.8) {
      this._grab = null;
      this._grabCd = 2.4;
    }
  }

  // ---- phase 3: OFF-AIR (TV only) with the 10 % shimmer
  _updateOffAir(dt) {
    if (this.offAir) {
      this._offAirT -= dt;
      if (this._offAirT <= 0) this._setOffAir(false);
    } else {
      this._offAirTimer -= dt;
      if (this._offAirTimer <= 0 && !this._grab) this._setOffAir(true);
    }
    if (this._revealT > 0) this._revealT -= dt;
    const hidden = this.offAir && this._revealT <= 0;
    if (hidden !== this._hidden) {
      this._hidden = hidden;
      this._setLayers(hidden ? LAYERS.TV_ONLY : LAYERS.WORLD);
      for (const s of this._shimmer) s.visible = hidden;
    }
    if (this.offAir) {
      if (this._offAirLoop) try { this._offAirLoop.setPos(this.pos); } catch { /* optional */ }
      if (hidden && Math.random() < dt * 9) {
        _v.set(this.pos.x + (Math.random() - 0.5) * 1.6, this.pos.y + Math.random() * 3.2 - 1.5, this.pos.z + (Math.random() - 0.5) * 1.6);
        this.game.fx?.burst?.(_v, { shape: 'static', count: 1, speed: 0.5, size: 0.16, life: 0.4 });
      }
    }
  }

  _setOffAir(on) {
    const g = this.game;
    if (this.offAir === on) return;
    this.offAir = on;
    if (on) {
      this._offAirT = B.p3.offAir;
      g.audio?.play?.('boss_offair', { pos: this.pos, vol: 1.1 });
      try { this._offAirLoop = g.audio?.loop?.('boss_static_ball', { pos: this.pos, vol: 0.45 }) || null; } catch { this._offAirLoop = null; }
    } else {
      this._offAirTimer = B.p3.offAirEvery;
      this._revealT = 0;
      if (this._offAirLoop) { try { this._offAirLoop.stop(0.2); } catch { /* optional */ } this._offAirLoop = null; }
      g.audio?.play?.('crt_ping', { pos: this.pos, vol: 0.7 });
      if (this._hidden) { this._hidden = false; this._setLayers(LAYERS.WORLD); for (const s of this._shimmer) s.visible = false; }
    }
    g.events.emit('machine:boss_offair', { on });
  }

  // ============================================================================================ environment
  _enterDeadAir() {
    const g = this.game, L = g.level;
    if (this._env) return;
    const env = { t: 0, moon: null, moonColor: null, stars: null, starOp: 1, amb: null, fog: undefined, fogPlanes: null };
    // the moon (a textured plane in the sky dome) and the stars
    L?.sky?.traverse?.((o) => {
      if (o.isMesh && o.material && o.material.map && o.renderOrder === -8) { env.moon = o; env.moonColor = o.material.color.clone(); }
      if (o.isPoints) env.stars = o;
    });
    const yard = L?.areas?.yard;
    if (yard) {
      env.amb = yard.ambient ? { ...yard.ambient } : null;
      env.fog = yard.fog ? { ...yard.fog } : null;
      if (yard.ambient) yard.ambient = { ...yard.ambient };
    }
    // ground-hugging static fog: three stacked noise discs over the arena
    const planes = new THREE.Group();
    planes.name = 'baron_static_fog';
    const mats = [];
    for (const [y, a, s] of [[0.22, 0.26, 1], [0.65, 0.17, 0.92], [1.25, 0.1, 0.8]]) {
      const m = new THREE.ShaderMaterial({ uniforms: { uTime: { value: 0 }, uAlpha: { value: 0 } }, vertexShader: WALL_VERT, fragmentShader: FOG_FRAG, transparent: true, depthWrite: false, fog: false });
      m.userData.alpha = a;
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(22 * s, 22 * s), m);
      mesh.rotation.x = -Math.PI / 2;
      mesh.position.set(43, y, -11);
      mesh.renderOrder = 4;
      planes.add(mesh);
      mats.push(m);
    }
    g.scene.add(planes);
    env.fogPlanes = planes;
    env.fogMats = mats;
    this._env = env;
  }

  _updateEnv(dt) {
    const env = this._env;
    if (!env) return;
    env.t += dt;
    const k = smooth(env.t / 3);
    if (env.moon) env.moon.material.color.copy(env.moonColor).multiplyScalar(lerp(1, 0.3, k));
    const yard = this.game.level?.areas?.yard;
    if (yard && env.amb && yard.ambient) yard.ambient.intensity = env.amb.intensity * lerp(1, 0.55, k);
    if (yard) yard.fog = { color: '#2A2140', near: lerp(60, 7, k), far: lerp(140, 40, k) };
    for (const m of env.fogMats || []) { m.uniforms.uTime.value = this._t; m.uniforms.uAlpha.value = m.userData.alpha * k; }
  }

  _restoreEnv() {
    const env = this._env;
    if (!env) return;
    if (env.moon) env.moon.material.color.copy(env.moonColor);
    const yard = this.game.level?.areas?.yard;
    if (yard) {
      if (env.amb) yard.ambient = env.amb;
      if (env.fog !== undefined) yard.fog = env.fog;
    }
    if (env.fogPlanes && env.fogPlanes.parent) env.fogPlanes.parent.remove(env.fogPlanes);
    this._env = null;
  }

  // The yard feed camera (SkyCam 13) auto-tracks him during the fight.
  _trackFeed(on) {
    const cam = this.game.screens?.feedCams?.yard;
    const f = cam?.userData?.feed;
    if (!f) return;
    if (on) { if (!this._feedSaved) this._feedSaved = { target: f.target.clone(), phase: f.phase }; }
    else if (this._feedSaved) { f.target.copy(this._feedSaved.target); f.phase = this._feedSaved.phase; this._feedSaved = null; }
  }

  _updateFeedTarget(dt) {
    const s = this.game.screens;
    const f = s?.feedCams?.yard?.userData?.feed;
    if (!f || !this._feedSaved) return;
    _v.set(this.pos.x, this.pos.y + 0.6, this.pos.z);
    f.target.lerp(_v, 1 - Math.exp(-dt * 4));
    if (Number.isFinite(s.clock)) f.phase = -(s.clock / 8) * TAU;     // cancel the ±20° idle pan (screens PAN.period)
  }

  // ---- DY slams shut behind a wall of static (and reopens after the fight)
  _closeDY() {
    const g = this.game, L = g.level;
    const d = L?.doors?.[DY.id];
    this._dy = { wasOpen: !!(d && d.open) };
    if (d && d.open) {
      try { d.reset(); } catch (err) { console.warn('[boss] DY reset', err); }
      d.open = false;
      try { L.col?.setEnabled?.(DY.id, true); } catch { /* optional */ }
      try { g.nav?.setDoor?.(DY.id, false); } catch { /* optional */ }
    }
    const [x0, z0, x1, z1] = DY.rect;
    this._closeDYWallOnly();
    this._wall.position.set(x1 + 0.06, DY.h / 2, (z0 + z1) / 2);
    this._wall.material.uniforms.uReveal.value = 0;
    this._wallT = 0;
    if (!this._wall.parent) g.scene.add(this._wall);
    const c = new THREE.Vector3((x0 + x1) / 2, 1.3, (z0 + z1) / 2);
    g.audio?.play?.('door_poof', { pos: c, vol: 1.2 });
    g.audio?.play?.('crt_ping', { pos: c, vol: 0.8, delay: 0.05 });
    g.fx?.burst?.(c, { shape: 'static', count: 30, speed: 4, size: 0.24 });
  }

  _openDY(quiet) {
    const g = this.game;
    if (this._wall && this._wall.parent) this._wall.parent.remove(this._wall);
    if (this._dy && this._dy.wasOpen) {
      try { g.level?.openDoor?.(DY.id, { instant: !!quiet }); } catch (err) { console.warn('[boss] DY reopen', err); }
    }
    this._dy = null;
  }

  // ============================================================================================ damage
  _hittable() {
    return this.active && this.state === 'fight' && !this._hop && !!this.root && this.root.visible;
  }

  // Nearest hit zone along a ray: screen slab, cabinet, antenna tips (head space), torso + arms + gloves (world).
  raycast(origin, dir, maxDist = 80) {
    if (!this._hittable() || !this.built) return null;
    const h = this.head;
    let best = null, bestT = maxDist;
    const consider = (t, zone) => { if (t >= 0 && t < bestT) { bestT = t; best = zone; } };
    // head space (holder HEAD_SCALE/S × body S; hit points go back to world space before measuring)
    h.group.updateWorldMatrix(true, false);
    _mi.copy(h.group.matrixWorld).invert();
    _ray.origin.copy(origin).applyMatrix4(_mi);
    _ray.direction.copy(dir).transformDirection(_mi);
    const S2 = h.SCR;
    _box.min.set(S2.x - S2.w / 2 - 0.03, S2.y - S2.h / 2 - 0.03, -h.D / 2 - 0.2);
    _box.max.set(S2.x + S2.w / 2 + 0.03, S2.y + S2.h / 2 + 0.03, -h.D / 2 + 0.02);
    if (_ray.intersectBox(_box, _v)) consider(_v.applyMatrix4(h.group.matrixWorld).distanceTo(origin), 'screen');
    _box.min.set(-h.W / 2, h.Y0 - 0.12, -h.D / 2 - 0.05);
    _box.max.set(h.W / 2, h.Y0 + h.H + 0.08, h.D / 2 + 0.05);
    if (_ray.intersectBox(_box, _v)) consider(_v.applyMatrix4(h.group.matrixWorld).distanceTo(origin) + 0.01, 'body');
    for (const tip of h.tips) {
      tip.getWorldPosition(_v2);
      consider(raySphereT(origin, dir, _v2, 0.34 * HEAD_SCALE), 'antenna');
    }
    // body (world)
    const J = this.J;
    J.base.getWorldPosition(_v); J.head.getWorldPosition(_v2);
    _v.y += 0.35; _v2.y -= 0.05;
    consider(rayCapsule(origin, dir, _v, _v2, 0.2 * S), 'body');
    for (const s of ['L', 'R']) {
      J['shoulder' + s].getWorldPosition(_o); J['elbow' + s].getWorldPosition(_v);
      consider(rayCapsule(origin, dir, _o, _v, 0.085 * S), 'body');
      J['hand' + s].getWorldPosition(_v2);
      consider(rayCapsule(origin, dir, _v, _v2, 0.075 * S), 'body');
      _d.subVectors(_v2, _v).normalize();
      _v2.addScaledVector(_d, 0.12 * S);
      consider(raySphereT(origin, dir, _v2, 0.13 * S), 'body');
    }
    if (!best) return null;
    return { dist: bestT, point: new THREE.Vector3().copy(origin).addScaledVector(dir, bestT), zone: best, mul: ZONE_MUL[best], head: false };
  }

  // Zone of a hit point (re-cast a short ray through it).
  _zoneAt(point, dir) {
    if (!point) return 'body';
    if (dir) {
      _o.copy(point).addScaledVector(dir, -0.8);
      const h = this.raycast(_o, dir, 1.6);
      if (h) return h.zone;
    }
    return 'body';
  }

  damage(amount, info = {}) {
    const g = this.game;
    if (!this.active || this.state !== 'fight' || !(amount > 0)) return false;
    const cause = info.cause || (info.melee ? 'melee' : 'bullet');
    let zone = ZONE_MUL[info.zone] ? info.zone : null;
    let mul = 1;
    if (!FIXED_CAUSES.has(cause) && !FIXED_CAUSES.has(info.weaponId)) {
      if (!zone) zone = this._zoneAt(info.point, info.dir);
      mul = ZONE_MUL[zone] || 1;
    }
    const frame = g.time.frame;
    const point = info.point || this.head.screenWorld();
    // off-air: any hit reveals him
    if (this.offAir) this._revealT = B.p3.reveal;
    // invulnerable while he recoils between phases (the static shields him): sparks only
    if (this._transT > 0) {
      g.fx?.burst?.(point, { shape: 'spark', count: 4, speed: 4, size: 0.04, colors: ['#C9A0FF', '#FFFFFF'] });
      return false;
    }
    let dmg = amount * mul;
    const minHp = this.phase === 1 ? this.maxHp * (2 / 3) : this.phase === 2 ? this.maxHp / 3 : 0;
    this.hp = Math.max(minHp, this.hp - dmg);
    const killed = this.phase === 3 && this.hp <= 0;
    // feedback
    if (this._fxFrame !== frame) {
      this._fxFrame = frame;
      g.fx?.burst?.(point, { shape: 'static', count: 3, speed: 2.5, size: 0.12, life: 0.35 });
      g.fx?.burst?.(point, { shape: 'spark', count: zone === 'body' ? 3 : 6, speed: 5, size: 0.045, life: 0.25, colors: zone === 'antenna' ? ['#FFE27A', '#FFFFFF'] : ['#FFFFFF', '#C9A0FF'] });
      this.head.wobble = Math.min(1, this.head.wobble + (zone === 'screen' ? 0.35 : 0.12));
      this._shake = Math.min(1, (this._shake || 0) + 0.15);
    }
    if (dmg > this.maxHp * 0.012 || zone !== 'body') {
      this._hurtT = (this._hurtT || 0) - 0;
      if (!this._gesture || this._gesture.kind === 'hurt') this._gesture = { kind: 'hurt', t: 0 };
    }
    if (this._voiceT <= 0 && Math.random() < 0.25) { this._voiceT = 1.6; g.audio?.play?.('boss_hurt', { pos: this.pos, vol: 0.9 }); }
    if (this.phase === 1 && this.head.faceMode === 'laugh' && zone === 'screen' && Math.random() < 0.3) {
      this._setFace('angry');
      clearTimeout(this._faceTo);
      this._faceTo = setTimeout(() => { if (this.phase === 1 && this.head.faceMode === 'angry' && this.state === 'fight') this._setFace('laugh'); }, 650);
    }
    // points: +10 per damaging hit event (one per frame + weapon)
    if (info.points !== false) {
      const key = `${frame}|${info.weaponId || cause}`;
      if (this._ptKey !== key) { this._ptKey = key; try { g.economy?.add?.(T.points.hit, 'hit'); } catch { /* optional */ } }
    }
    if (info.hitmarker !== false && this._hmFrame !== frame) {
      this._hmFrame = frame;
      try { g.hud?.hitmarker?.(zone === 'screen' || zone === 'antenna', killed); } catch { /* optional */ }
    }
    g.events.emit('boss:hit', { dmg, zone, point, cause, weaponId: info.weaponId || null, hp: this.hp });
    if (killed) { this._defeat(); return true; }
    this._checkPhase();
    return false;
  }

  // ---- shootable (bullets + melee through weapons.js)
  _registerShootable() {
    const w = this.game.weapons;
    if (!w || typeof w.registerShootable !== 'function') return;
    w.registerShootable({
      id: 'boss_baron', blocksBullet: true, melee: true, bullets: true,
      raycast: (o, d, max) => { const h = this.raycast(o, d, max); return h ? { dist: h.dist, point: h.point } : null; },
      onHit: (info) => {
        const zone = this._zoneAt(info.point, info.dir);
        this.damage(info.damage || 0, { ...info, zone, cause: info.melee ? 'melee' : (info.cause === 'bullet' || !info.cause ? 'bullet' : info.cause) });
      },
    });
    this._shootable = true;
  }

  _unregisterShootable() {
    if (!this._shootable) return;
    this._shootable = false;
    try { this.game.weapons?.unregisterShootable?.('boss_baron'); } catch { /* optional */ }
  }

  // ---- the wonder-weapon adapter (see header)
  _makeProxy() {
    return {
      id: 'boss_baron', type: 'boss_baron', boss: true, flags: { boss: true }, def: { id: 'boss_baron' },
      pos: new THREE.Vector3(), vel: new THREE.Vector3(), knock: new THREE.Vector3(), yaw: 0, hp: 1, maxHp: 1, state: 'dead',
      dead: false, removed: false, radius: 1.1, height: 5.0, speed: 0, scale: 1, group: null, head: null, headR: 0.6,
      hitZones: [{ zone: 'screen', mul: B.screenMul }, { zone: 'antenna', mul: B.antennaMul }, { zone: 'body', mul: B.bodyMul }],
      anim: {}, stun: 0, area: 'yard', entry: null,
    };
  }

  _syncProxy() {
    const P = this.proxy;
    P.pos.set(this.pos.x, this.pos.y - 1.9, this.pos.z);
    P.hp = Math.max(0, this.hp);
    P.maxHp = this.maxHp;
    P.state = this._hittable() ? 'chase' : 'dead';
    P.yaw = this.yaw;
    P.group = this.root;
    P.head = this.head ? this.head.screen : null;
  }

  _installAdapters() {
    const g = this.game, zm = g.zombies;
    if (this._adapted || !zm) return;
    const self = this, proxy = this.proxy;
    const A = { zm, damage: zm.damage, raycast: zm.raycast, wonder: null, wonderFn: null };
    if (typeof A.damage === 'function') {
      zm.damage = function (z, amount, info) {
        if (z === proxy) return self.damage(amount, { ...(info || {}), zone: info && info.zone, cause: (info && info.cause) || 'wonder' });
        return A.damage.call(this, z, amount, info);
      };
    }
    if (typeof A.raycast === 'function') {
      zm.raycast = function (o, d, max = 80) {
        const h = A.raycast.call(this, o, d, max);
        const b = self._hittable() ? self.raycast(o, d, h ? h.dist : max) : null;
        if (b) return { z: proxy, head: false, dist: b.dist, point: b.point, zone: b.zone, mul: b.mul };
        return h;
      };
    }
    const w = g.wonder;
    if (w && typeof w._zombies === 'function') {
      A.wonder = w;
      A.wonderFn = w._zombies;
      w._zombies = function () { const L = A.wonderFn.call(this); return self._hittable() ? L.concat([proxy]) : L; };
    }
    this._adapted = A;
  }

  _uninstallAdapters() {
    const A = this._adapted;
    if (!A) return;
    if (A.damage) A.zm.damage = A.damage;
    if (A.raycast) A.zm.raycast = A.raycast;
    if (A.wonder && A.wonderFn) A.wonder._zombies = A.wonderFn;
    // instance overrides shadow the prototype methods: drop them so nothing of ours stays behind
    if (A.zm.damage === A.damage && Object.prototype.hasOwnProperty.call(A.zm, 'damage') && Object.getPrototypeOf(A.zm).damage === A.damage) delete A.zm.damage;
    if (A.zm.raycast === A.raycast && Object.prototype.hasOwnProperty.call(A.zm, 'raycast') && Object.getPrototypeOf(A.zm).raycast === A.raycast) delete A.zm.raycast;
    if (A.wonder && Object.prototype.hasOwnProperty.call(A.wonder, '_zombies') && Object.getPrototypeOf(A.wonder)._zombies === A.wonderFn) delete A.wonder._zombies;
    this._adapted = null;
  }

  // ============================================================================================ defeat
  _defeat() {
    const g = this.game;
    this.hp = 0;
    this.state = 'defeated';
    this._clearBalls();
    this._stopSweep();
    this._grab = null;
    this._hop = null;
    if (this.offAir) this._setOffAir(false);
    this._restoreScale();
    this._despawnAdds(true);
    this._unregisterShootable();
    this._uninstallAdapters();
    this._completeEgg();
    g.events.emit('boss:defeated', { round: this.round });
    if (this.ending && typeof this.ending.play === 'function') {
      try { this.ending.play({ round: this.round }); return; } catch (err) { console.error('[boss] ending.play failed', err); }
    }
    this.end({ quiet: true });
    g.victory?.();
  }

  // egg:step {step:6} + egg:complete: through the egg's own API when it reached step 5 (a debug fight started from
  // an earlier step leaves the egg alone).
  _completeEgg() {
    const g = this.game, e = g.egg;
    if (!e || e.done || !(e.step >= 5)) return;
    try {
      if (typeof e.onBossDefeated === 'function') { e.onBossDefeated(); if (e.done) return; }
      else if (typeof e.bossDefeated === 'function') { e.bossDefeated(); if (e.done) return; }
      else if (typeof e.setStep === 'function') { e.setStep(6); if (e.done) return; }
    } catch (err) { console.warn('[boss] egg completion hook failed', err); }
    if (!e.done) {
      e.step = 6;
      e.done = true;
      g.events.emit('egg:step', { step: 6 });
      g.events.emit('egg:complete', {});
    }
  }

  // ---- ending beats (driven by ending.js) --------------------------------------------------------------------
  // t = 0: he freezes, his screen shows the teary goodnight face, he waves.
  goodnight() {
    if (!this.built) return;
    this.state = 'defeated';
    this._setLayers(LAYERS.WORLD);
    for (const s of this._shimmer) s.visible = false;
    this._hidden = false;
    this.head.crack.visible = false;
    this._sparking = false;
    this._setFace('goodnight');
    this._gesture = { kind: 'wave', t: 0 };
    this._rt = this._t;
    this.root.visible = true;
    this.head.group.visible = true;
    this.head.group.scale.setScalar(1);
    this.game.audio?.play?.('boss_goodnight', { pos: this.head.screenWorld(), vol: 1.1 });
  }

  // k 0..1: his TV head collapses into a white line (k < 0.5), then a dot, then nothing. The glowing line/dot sit
  // in the unscaled fxRoot at the screen's world position (the head itself squashes flat under them).
  collapseHead(k) {
    if (!this.built) return;
    const h = this.head, g = this.game;
    if (!h._flash) {
      const m = new THREE.MeshBasicMaterial({ map: lineTexture(), color: new THREE.Color('#F6F1FF').multiplyScalar(4), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false, side: THREE.DoubleSide });
      h._flash = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), m);
      h._flash.renderOrder = 5;
      const d = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(), color: new THREE.Color('#F6F1FF').multiplyScalar(4), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false }));
      h._dot = d;
    }
    const f = h._flash, dot = h._dot;
    if (f.parent !== g.scene) g.scene.add(f, dot);
    if (!h._collapseAt || k <= 0.02) h._collapseAt = h.screenWorld().clone();
    f.position.copy(h._collapseAt);
    dot.position.copy(h._collapseAt);
    f.quaternion.copy(g.camera.quaternion);
    k = clamp(k, 0, 1);
    const W = h.W * HEAD_SCALE;
    if (k < 0.5) {
      const u = k / 0.5;
      h.group.scale.set(1, Math.max(0.02, 1 - easeInOut(u)), 1);
      h.group.visible = u < 0.9;
      f.visible = true; dot.visible = false;
      f.scale.set(W * (1 + 0.1 * u), lerp(1.2, 0.18, easeInOut(u)), 1);
      f.material.opacity = Math.min(1, u * 3);
    } else if (k < 1) {
      const u = (k - 0.5) / 0.5;
      h.group.visible = false;
      f.visible = u < 0.85;
      f.scale.set(Math.max(0.1, W * (1 - easeInOut(u))), 0.18, 1);
      dot.visible = true;
      const s = lerp(0.6, 1.4, Math.sin(u * Math.PI));
      dot.scale.set(s, s, 1);
    } else {
      h.group.visible = false;
      f.visible = false;
      dot.visible = false;
    }
  }

  // Once the view has collapsed (t = 4 s): remove the model, reopen DY, restore the world. The boss stays `active`
  // (rounds stay paused) until the ending calls finish().
  cleanupAfterEnding() {
    if (this.head) {
      this.head.group.visible = true;
      this.head.group.scale.setScalar(1);
      this.head._collapseAt = null;
      for (const o of [this.head._flash, this.head._dot]) if (o) { o.visible = false; if (o.parent) o.parent.remove(o); }
    }
    this.end({ quiet: true, keepEnding: true });
  }

  // The ending is over (Y or N): the fight is fully finished, rounds may run again.
  finish() {
    this.end({ quiet: true });
  }

  // ============================================================================================ debug
  debugStart({ round, teleport = true, skipIntro = false } = {}) {
    const g = this.game;
    this.debug = true;
    if (!g.machines?.powerOn) { try { g.machines?.setPower?.(true); } catch { /* optional */ } }
    const d = g.level?.doors?.[DY.id];
    if (d && !d.open) { try { g.level.openDoor(DY.id, { instant: true }); } catch { /* optional */ } }
    if (teleport && g.player && g.player.area !== 'yard') g.player.teleport(45, -8.6, Math.PI);
    const ok = this.start(round ?? g.rounds?.round ?? 1);
    if (ok && skipIntro) {
      this._introT = INTRO.end - 1e-3;
      this._introFlags = { swirl: true, form: true, laugh: true };
      this.root.visible = true;
      this.tornado.group.scale.setScalar(1);
    }
    return this.debugState();
  }

  debugPhase(n = 2) {
    if (!this.active) this.debugStart({ skipIntro: true });
    if (this.state === 'intro') { this._introT = INTRO.end; this._updateIntro(0); }
    n = clamp(n | 0, 1, 3);
    this._transT = 0;
    this._hop = null;
    this._restoreScale();
    this.root.visible = true;
    this.hp = n === 1 ? this.maxHp : n === 2 ? this.maxHp * (2 / 3) : this.maxHp / 3;
    this._cracked = n >= 2; this.head.crack.visible = n >= 2;
    this._sparking = n >= 3;
    this._drops[n - 1] = true;
    this._beginPhase(n);
    return this.debugState();
  }

  debugKill() {
    if (!this.active) return false;
    if (this.state === 'intro') { this._introT = INTRO.end; this._updateIntro(0); }
    if (this.state !== 'fight') return false;
    this._transT = 0;
    if (this.phase < 3) this.debugPhase(3);
    this.hp = 1;
    return this.damage(10, { cause: 'debug', points: false, hitmarker: false });
  }

  debugHit(zone = 'screen', amount = 100) {
    if (!this._hittable()) return null;
    const h = this.head;
    let point;
    if (zone === 'antenna') point = h.tips[0].getWorldPosition(new THREE.Vector3());
    else if (zone === 'screen') point = h.screenWorld().clone();
    else point = this.J.chest.getWorldPosition(new THREE.Vector3());
    const before = this.hp;
    this.damage(amount, { zone, cause: 'bullet', point, weaponId: 'debug', points: false });
    return { zone, dealt: before - this.hp, hp: this.hp };
  }

  debugOffAir(on = true) {
    if (this.phase !== 3) this.debugPhase(3);
    this._setOffAir(!!on);
    this._updateOffAir(0.0001);
    return { offAir: this.offAir, layer: this._layer };
  }

  debugSweep() {
    if (this.phase !== 2) this.debugPhase(2);
    this._hop = null;
    this._restoreScale();
    this._stopSweep();
    this._startSweep();
    return !!this._sweep;
  }

  debugGrab() {
    if (this.phase !== 3) this.debugPhase(3);
    const p = this.game.player;
    this.pos.x = p.pos.x + 1.2; this.pos.z = p.pos.z - 1.2;
    this._grabCd = 0;
    this._grab = null;
    return true;
  }

  debugState() {
    return {
      active: this.active, state: this.state, phase: this.phase, hp: Math.round(this.hp), maxHp: this.maxHp, round: this.round,
      pos: this.pos.toArray().map((v) => +v.toFixed(2)), offAir: this.offAir, hidden: !!this._hidden, adds: this._adds.size,
      balls: this._balls.filter((b) => b.alive).length, sweep: this._sweep ? this._sweep.phase : null, grab: this._grab ? this._grab.phase : null,
      hop: !!this._hop, trans: +(this._transT || 0).toFixed(2), baked: !!(this.char && this.char.skinnedMesh), face: this.head ? this.head.faceMode : null,
      adapted: !!this._adapted, ending: this.ending ? { active: !!this.ending.active, t: +(this.ending.t || 0).toFixed(2), stage: this.ending.stage || null } : null,
    };
  }
}
