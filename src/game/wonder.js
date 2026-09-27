// Wonder weapons + signal colors: game.wonder (GDD §9.3 Tiny Tele, §9.4 Zapper / Boom Mic / Chroma-Key, §9.5 upgraded
// versions, §10.4 signal colors, §15 audio ids). Owned by the wonder engineer.
//
// INTEGRATION (one line for the integrator; game.js has no optional-system loader):
//     import { install as installWonder } from '../game/wonder.js';     // src/core/game.js
//     installWonder(this);                                               // Game constructor, after `this.weapons = ...`
//   or in src/main.js: `import { install } from './game/wonder.js';` + `install(game);` between `new Game()` and
//   `game.boot()` (exactly what tools/scenarios/wonder_entry.js does).
//   install(game) is idempotent and self-driving: it sets game.wonder, runs update() once per frame through
//   game.render.addPrePass (skipped when Game already called update() that frame, so adding 'wonder' to INIT_ORDER /
//   UPDATE_ORDER after 'weapons' is also fine), resets on 'game:start' and warms its shader programs after boot.
//   Until then the test harness (tools/scenarios/wonder_entry.js) installs it.
//
// API (weapons.js delegates every weapon whose def.fire is 'custom': zapper, boom_mic, chroma_key)
//   fire(weaponId, ctx) -> bool   every frame while the weapon is held (weapons.js ctx: { def, upgraded, signal, slot,
//       origin, dir (camera aim ray), muzzle, aimPoint, aimDist, triggerDown, triggerPressed, triggerReleased, ads, dt,
//       ready, model }). Returns true when a click / shot / playback went off this frame. Wonder owns its weapons'
//       ammo (slot.mag--, reload moves reserve -> mag), empty-mag reloads and dry fire, and emits weapon:fire /
//       weapon:reload / weapon:empty itself (weapons.js detects that and only adds the model spring + crosshair bloom).
//   reload(weaponId, ctx) -> seconds   starts the battery / reel-swap / goo-cartridge reload (0 = refused: full, no
//       reserve, recording); weapons.js mirrors reloading / reloadId / reloadProgress for the pose.
//   holster(weaponId) / equip(weaponId)   weapons.js hooks: holstering cancels a recording (charge lost) or a reload.
//   throwTele(ctx?) -> bool   Q. ctx = { origin (left hand), dir, velocity, aimPoint } from weapons.js, which already
//       took one from weapons.teles; without ctx (tests / self-drive) wonder consumes one itself. Plays tele_throw.
//   reloading, reloadId, reloadProgress (0..1), recording (Boom Mic held), charge (0..10), busy(weaponId) -> bool,
//   isWonder(id), applySignal(z, signal, {weaponId, splash}), teles (live Tiny Teles), warmup() -> Object3D[] (the
//   Game.precompile hook), init(), reset(), update(dt) (world dt).
//   debug: trigger(down|null) (a simulated trigger, also through weapons.js), step(seconds) (advances wonder + fx
//   with time.scale 0, for stepped screenshots), gag(z|id, name), key(z|id, world, upgraded), tumble(z|id),
//   tele(x, z), signal(z|id, s), burn/laugh/freeze(z|id), state() (actors, hidden, status, blobs, puddles, puddleAt,
//   teles [{state, pos, seated, sat (plopped down), live, yaw}], lastZap ...).
// Tests: bash tools/scenarios/wonder_all.sh (zapper boom chroma tele signals; header of tools/scenarios/wonder_lib.cjs).
// Numbers: ctx.def wins (weaponDefs.js: cone/spread, range, chain, chainR, killUpTo, dmg, bossDmg, stunPulse, record,
//   playback, blob, splash, puddle, worlds, mag, reload); the G table below mirrors GDD §9.3–9.5 as the fallback.
//
// Events emitted: weapon:fire {weaponId, upgraded} (audio.js voices wpn_zapper / wpn_chroma_fire; the Boom Mic plays
//   wpn_boom_playback itself), weapon:reload {weaponId}, weapon:empty {weaponId}, wonder:gag {z, gag},
//   wonder:key {z, world}, wonder:tele {state:'land'|'implode', pos}, wonder:signal {z, signal, weaponId, splash}.
// Listens: zombie:hit (x1.5 while laughing / frozen; signal-color roll of upgraded weapons: weapons.hit.primary only,
//   weapons.slots[].signal, half chance on splash targets, cooldown per weapon + color; wonder weapons roll too),
//   zombie:kill (Cold Open shatter), zombie:spawn (per-zombie-art shader warm-up), game:start (reset).
//
// Zombie contract used (defensive; ARCHITECTURE §10): zombies.alive [{ id, hp, maxHp, pos, yaw, group, head, height,
//   radius, speed, state, type, anim, animator {override, update, kick}, stun }], zombies.damage(z, amount, {
//   weaponId, cause, dir, point, upgraded }) -> killed, zombies.raycast, zombies.stun(z, s) (stars), zombies.setLure.
//   Wonder deaths: the zombie's pose is cloned (SkeletonUtils) and the original hidden BEFORE zombies.damage runs
//   (info.corpse = false, so the manager skips its own death visuals: topple, stars, confetti); the clone performs the five channel gags,
//   the keyed swirl, the playback tumble or the tele implosion. Status effects write temporary state and restore it:
//   z.speed (record slow 35 %, Cold Open on specials 50 %), z.stun (seated, laughing, frozen, panicking; direct
//   writes, no stars), z.animator.override (poses), z.animator.update (frozen solid), mesh materials (ice). Damage
//   bonuses lower z.hp directly unless lethal (then zombies.damage with cause 'signal_bonus').

import * as THREE from 'three';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { T, PAL } from '../core/config.js';
import * as geo from '../core/geo.js';
import { getCard, getAnimated } from '../gfx/cards.js';
import { buildWeapon } from '../props/weapons.js';

const TAU = Math.PI * 2;
const DEG = Math.PI / 180;
const WONDER = new Set(['zapper', 'boom_mic', 'chroma_key']);
const SPECIALS = new Set(['sock_hopper', 'forecaster', 'big_shot']);
const STANDERS = new Set(['forecaster', 'big_shot']);
const GAGS = ['cartoon', 'western', 'cooking', 'nature', 'signoff'];
const WORLDS = ['space', 'beach', 'volcano', 'underwater'];
const WORLDS_UP = ['desert', 'moon'];
const WORLD_TINT = { space: '#B9A8FF', beach: '#7FE7FF', volcano: '#FF8A3C', underwater: '#5FE3FF', desert: '#FFC98A', moon: '#E8E4F0' };
// Where the keyed silhouette looks into each world card (texture uv, y up): its most iconic bit, since a body is
// only ~0.35 card-heights wide (ringed planet, sun + sea + beach umbrella, the cone, the fish, the sliced sun, Earth).
const WORLD_FOCUS = { space: [0.66, 0.53], beach: [0.74, 0.5], volcano: [0.5, 0.52], underwater: [0.56, 0.52], desert: [0.31, 0.44], moon: [0.75, 0.52] };
const SIGNALS = ['hot_mic', 'laugh_track', 'cold_open'];
const SIG = T.uplink.signals;

// GDD §9.3–9.5 numbers. ctx.def wins when the weapons table carries the field (mag, reserve, reload, range, chain...).
const G = {
  zapper: { cone: [5, 2], range: [25, 40], rangeUp: [35, 50], chain: 3, chainUp: 6, hop: 4, interval: 0.45, killUpTo: 25,
    killUpToUp: 35, dmg: 6000, dmgUp: 12000, stun: 1, boss: 2000, pulseR: 2.5, pulseStun: 1.5, reload: 1.6 },
  boom: { rec: 3, recCone: 40, recRange: 12, slow: 0.35, base: 1, per: 2, bossCount: 3, max: 10, cone: 50, range: 15, killAt: 3,
    killUpTo: 30, killUpToUp: 40, late: 8000, weak: 500, knock: 4, weakStun: 1.5, boss: 700, recover: 0.8, reload: 2.5 },
  chroma: { r: 0.18, speed: 22, grav: 6, fuse: 2, splash: 3, splashUp: 4.5, puddleR: 3, puddleT: 4, puddleTUp: 8, puddleN: 6,
    puddleNUp: 10, killUpTo: 25, killUpToUp: 35, late: 6000, boss: 3000, interval: 0.7, reload: 2.2 },
  tele: { lure: 15, fuse: 6, killR: 4, killUpTo: 30, late: 20000, seatR: 2.2, speed: 10.5, up: 3.4, grav: 18, scale: 1.55 },
};
const MAGS = { zapper: [13, 52, 21, 126], boom_mic: [2, 12, 3, 18], chroma_key: [6, 36, 10, 60] };

// ------------------------------------------------------------------------------------------------ math helpers
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const lerp = (a, b, t) => a + (b - a) * t;
const seg = (t, a, b) => clamp01((t - a) / (b - a));
const E = {
  inQuad: (t) => t * t,
  outQuad: (t) => t * (2 - t),
  inCubic: (t) => t * t * t,
  outCubic: (t) => 1 - (1 - t) ** 3,
  inOutQuad: (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2),
  outBack: (t, s = 1.7) => 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2,
  inBack: (t, s = 1.7) => t * t * ((s + 1) * t - s),
  outElastic: (t) => (t <= 0 ? 0 : t >= 1 ? 1 : 2 ** (-10 * t) * Math.sin((t * 10 - 0.75) * (TAU / 3)) + 1),
};
const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _d = new THREE.Vector3();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _e = new THREE.Vector3();
const _up = new THREE.Vector3(0, 1, 0);
const _zAxis = new THREE.Vector3(0, 0, 1);
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _m = new THREE.Matrix4();
const _col = new THREE.Color();
const _v2 = new THREE.Vector2();
const ZERO_M = new THREE.Matrix4().makeScale(0, 0, 0);

function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ------------------------------------------------------------------------------------------------ fx shader
// MeshBasicMaterial patched per kind: 'flat' (solid color), 'static' (TV snow), 'bars' (SMPTE bars) and 'footage'
// (the Chroma-Key stock-footage window: a world_* card sampled with gl_FragCoord UVs), all with a fresnel rim.
// Works on skinned / morphing clones (three picks the skinning variant per object).
const FXU = { time: { value: 0 }, res: { value: new THREE.Vector2(1280, 720) } };
const FX_FRAG = /* glsl */`
uniform vec3 uFxColor;
uniform vec3 uFxRim;
uniform float uFxRimK;
uniform float uFxTime;
uniform vec2 uFxRes;
uniform sampler2D uFxMap;
uniform float uFxWorld;
uniform vec3 uFxFrame;
uniform vec2 uFxFocus;
varying vec3 vFxN;
float fxHash( vec2 p ) { return fract( sin( dot( p, vec2( 12.9898, 78.233 ) ) ) * 43758.5453 ); }
vec3 fxBar( float i ) {
  if ( i < 0.5 ) return vec3( 0.84, 0.84, 0.84 );
  if ( i < 1.5 ) return vec3( 0.9, 0.75, 0.05 );
  if ( i < 2.5 ) return vec3( 0.05, 0.67, 0.75 );
  if ( i < 3.5 ) return vec3( 0.08, 0.64, 0.06 );
  if ( i < 4.5 ) return vec3( 0.67, 0.08, 0.67 );
  if ( i < 5.5 ) return vec3( 0.78, 0.07, 0.05 );
  return vec3( 0.05, 0.1, 0.78 );
}
vec3 fxColor() {
  vec2 sc = gl_FragCoord.xy / uFxRes;
  vec3 c = uFxColor;
#ifdef FX_STATIC
  float n = fxHash( floor( gl_FragCoord.xy / 3.0 ) + floor( uFxTime * 30.0 ) * 17.31 );
  c = vec3( n * n ) * 1.8;
#endif
#ifdef FX_BARS
  c = fxBar( floor( mod( gl_FragCoord.x / max( 6.0, uFxRes.x / 56.0 ) + floor( uFxTime * 12.0 ), 7.0 ) ) ) * 1.35;
#endif
#ifdef FX_FOOTAGE
  // screen-space UVs framed on the keyed zombie (uFxFrame = its projected centre in px + its height in px), so the
  // silhouette is a window onto the world card around uFxFocus (its iconic bit) and the footage stays put while the body moves
  vec2 uv = ( gl_FragCoord.xy - uFxFrame.xy ) / max( uFxFrame.z, 8.0 );
  uv = vec2( uv.x * 0.7 / 1.7778, uv.y * 0.7 ) + uFxFocus;
  float w = uFxWorld;
  float t = uFxTime;
  if ( w < 0.5 ) uv += vec2( sin( t * 0.6 ), cos( t * 0.5 ) ) * 0.012;                          // space: slow drift
  else if ( w < 1.5 ) uv.x += sin( uv.y * 40.0 + t * 3.0 ) * 0.004 * step( uv.y, 0.45 );        // beach: waves
  else if ( w < 2.5 ) uv += vec2( sin( uv.y * 30.0 + t * 8.0 ), cos( uv.x * 24.0 + t * 7.0 ) ) * 0.004; // volcano heat
  else if ( w < 3.5 ) uv += vec2( sin( uv.y * 14.0 + t * 2.2 ), cos( uv.x * 12.0 + t * 1.8 ) ) * 0.01;  // underwater
  else if ( w < 4.5 ) uv.x += sin( uv.y * 50.0 + t * 6.0 ) * 0.003;                            // desert heat
  else uv.x += sin( t * 0.4 ) * 0.008;                                                         // moon
  c = texture2D( uFxMap, clamp( uv, 0.002, 0.998 ) ).rgb * 1.3;
  if ( w < 0.5 || w > 4.5 ) c += vec3( step( 0.994, fxHash( floor( gl_FragCoord.xy / 2.0 ) + floor( t * 6.0 ) ) ) ) * 1.5;
  if ( w > 1.5 && w < 2.5 ) c *= 1.0 + 0.25 * sin( t * 5.0 );
  if ( w > 2.5 && w < 3.5 ) c += vec3( 0.2, 0.35, 0.4 ) * pow( max( 0.0, sin( uv.x * 30.0 + t * 2.0 ) * sin( uv.y * 26.0 - t * 1.6 ) ), 6.0 );
  c *= 0.9 + 0.1 * sin( gl_FragCoord.y * 1.7 );
#endif
  float rim = pow( 1.0 - abs( normalize( vFxN ).z ), 2.2 ) * uFxRimK;
  return mix( c, uFxRim, clamp( rim, 0.0, 1.0 ) );
}
`;

function fxMaterial(kind, { color = '#ffffff', intensity = 1, rim = '#ffffff', rimK = 0.5, map = null, world = 0, focus = [0.5, 0.5] } = {}) {
  const mat = new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false });
  const u = {
    uFxColor: { value: new THREE.Color(color).multiplyScalar(intensity) },
    uFxRim: { value: new THREE.Color(rim) },
    uFxRimK: { value: rimK },
    uFxTime: FXU.time,
    uFxRes: FXU.res,
    uFxMap: { value: map },
    uFxWorld: { value: world },
    uFxFrame: { value: new THREE.Vector3(640, 360, 300) },
    uFxFocus: { value: new THREE.Vector2(focus[0], focus[1]) },
  };
  mat.userData.fx = u;
  mat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, u);
    sh.defines = sh.defines || {};
    sh.defines[`FX_${kind.toUpperCase()}`] = '';
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vFxN;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>
#if defined( USE_ENVMAP ) || defined( USE_SKINNING )
  vFxN = normalize( transformedNormal );
#else
  vFxN = normalize( normalMatrix * normal );
#endif`);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>\n${FX_FRAG}`)
      .replace('vec4 diffuseColor = vec4( diffuse, opacity );', 'vec4 diffuseColor = vec4( fxColor(), opacity );');
  };
  mat.customProgramCacheKey = () => `wonderfx_${kind}`;
  mat.name = `wonder:${kind}`;
  return mat;
}

// ------------------------------------------------------------------------------------------------ geometry builders
function tumbleweedGeo() {
  const r = rng(7);
  const geos = [];
  for (let k = 0; k < 10; k++) {
    const u = new THREE.Vector3(r() - 0.5, r() - 0.5, r() - 0.5).normalize();
    const v = new THREE.Vector3(r() - 0.5, r() - 0.5, r() - 0.5).cross(u).normalize();
    const pts = [];
    const ph = r() * TAU, rr = 0.3 + r() * 0.06;
    for (let i = 0; i < 28; i++) {
      const a = (i / 28) * TAU;
      const w = rr * (1 + 0.14 * Math.sin(a * 3 + ph) + 0.06 * Math.sin(a * 7 + k));
      pts.push(new THREE.Vector3().addScaledVector(u, Math.cos(a) * w).addScaledVector(v, Math.sin(a) * w)
        .add(new THREE.Vector3(r() - 0.5, r() - 0.5, r() - 0.5).multiplyScalar(0.05)));
    }
    geos.push(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts, true), 56, 0.013 + r() * 0.008, 4, true));
  }
  const g = mergeGeometries(geos, false);
  geos.forEach((x) => x.dispose());
  return g;
}

// A head-shaped, fluted gelatin mold (cooking gag), bottom at y=0, ~0.62 m tall.
function gelatinGeo() {
  const prof = [];
  const n = 22;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const y = t * 0.62;
    let r;
    if (t < 0.12) r = 0.26 + t * 0.5;                        // flared base
    else if (t < 0.3) r = 0.31 - (t - 0.12) * 0.25;           // first tier
    else r = 0.3 * Math.sqrt(Math.max(0, 1 - ((t - 0.3) / 0.7) ** 2)) * 1.02 + 0.001; // dome (the "head")
    prof.push(new THREE.Vector2(Math.max(0.001, r), y));
  }
  prof.push(new THREE.Vector2(0.0001, 0.62));
  const g = new THREE.LatheGeometry(prof, 40);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i), y = p.getY(i);
    const a = Math.atan2(z, x);
    const k = 1 + 0.07 * Math.cos(a * 10) * Math.min(1, y / 0.1) * (y < 0.55 ? 1 : 0.3);
    p.setX(i, x * k);
    p.setZ(i, z * k);
  }
  g.computeVertexNormals();
  return g;
}

function blobShapeGeo(seed, n = 26) {
  const r = rng(seed);
  const shape = new THREE.Shape();
  const ph = r() * TAU;
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * TAU;
    const rr = 1 + 0.12 * Math.sin(a * 3 + ph) + 0.07 * Math.sin(a * 5 + ph * 2) + (i < n ? (r() - 0.5) * 0.06 : 0);
    const x = Math.cos(a) * rr, y = Math.sin(a) * rr;
    if (i === 0) shape.moveTo(x, y);
    else if (i === n) shape.closePath();
    else shape.lineTo(x, y);
  }
  const g = new THREE.ShapeGeometry(shape, 4);
  g.rotateX(-Math.PI / 2);
  return g;
}

// Chroma-goo splat mark (drawn in its final colours, 256 px): dark goo rim, saturated body with a lighter core, a few
// satellite drops, a glossy sheen. Lives in the 'splat' pools (fades out with the puddle; fx decals never fade).
function splatTexture(up) {
  const S = 256, H = S / 2;
  const c = document.createElement('canvas');
  c.width = c.height = S;
  const x = c.getContext('2d');
  const r = rng(up ? 77 : 41);
  const body = up ? PAL.greenScreen : PAL.chromaBlue;
  const rim = up ? '#14803A' : '#0C2A8C';
  const core = up ? '#8CF08A' : '#4F86FF';
  const ph = r() * TAU;
  const lobes = [];
  for (let i = 0; i < 9; i++) {
    const a = (i / 9) * TAU + r() * 0.5, d = S * (0.21 + r() * 0.1);
    lobes.push([H + Math.cos(a) * d, H + Math.sin(a) * d, S * (0.05 + r() * 0.05)]);
  }
  const drops = [];
  for (let i = 0; i < 7; i++) {
    const a = r() * TAU, d = S * (0.36 + r() * 0.08);
    drops.push([H + Math.cos(a) * d, H + Math.sin(a) * d, S * (0.012 + r() * 0.018)]);
  }
  const shape = (grow) => {
    x.beginPath();
    for (let i = 0; i <= 48; i++) {
      const a = (i / 48) * TAU;
      const rr = S * 0.25 * (1 + 0.1 * Math.sin(a * 3 + ph) + 0.06 * Math.sin(a * 7 + ph * 2)) + grow;
      if (i === 0) x.moveTo(H + Math.cos(a) * rr, H + Math.sin(a) * rr); else x.lineTo(H + Math.cos(a) * rr, H + Math.sin(a) * rr);
    }
    x.closePath();
    x.fill();
    for (const [lx, ly, lr] of lobes) { x.beginPath(); x.arc(lx, ly, lr + grow, 0, TAU); x.fill(); }
    for (const [dx, dy, dr] of drops) { x.beginPath(); x.arc(dx, dy, dr + grow * 0.6, 0, TAU); x.fill(); }
  };
  x.fillStyle = rim;
  shape(S * 0.022);
  const gr = x.createRadialGradient(H - S * 0.05, H - S * 0.06, S * 0.02, H, H, S * 0.42);
  gr.addColorStop(0, core); gr.addColorStop(0.55, body); gr.addColorStop(1, body);
  x.fillStyle = gr;
  shape(0);
  x.fillStyle = up ? 'rgba(228,255,216,0.7)' : 'rgba(191,212,255,0.7)';
  x.beginPath(); x.ellipse(H - S * 0.09, H - S * 0.1, S * 0.08, S * 0.04, -0.6, 0, TAU); x.fill();
  for (const [dx, dy, dr] of drops) { x.beginPath(); x.arc(dx - dr * 0.3, dy - dr * 0.3, dr * 0.35, 0, TAU); x.fill(); }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

// Per-instance opacity for an instanced basic material: instanceColor.r scales alpha instead of tinting.
function alphaFromInstance(mat, key) {
  mat.onBeforeCompile = (s) => {
    s.fragmentShader = s.fragmentShader.replace('#include <color_fragment>', '#if defined( USE_COLOR ) || defined( USE_INSTANCING_COLOR )\n diffuseColor.a *= vColor.r;\n#endif');
  };
  mat.customProgramCacheKey = () => key;
  return mat;
}

function squiggleGeo() {
  const pts = [];
  for (let i = 0; i <= 16; i++) {
    const t = i / 16;
    pts.push(new THREE.Vector3(Math.sin(t * TAU * 1.5) * 0.045, Math.cos(t * TAU * 1.5) * 0.02, (t - 0.5) * 0.34));
  }
  return new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 32, 0.016, 5, false);
}

function flameGeo(scale = 1) {
  const pts = [[0, 0], [0.1, 0.03], [0.15, 0.12], [0.14, 0.22], [0.1, 0.33], [0.05, 0.45], [0.001, 0.58]]
    .map(([x, y]) => new THREE.Vector2(x * scale, y * scale));
  return new THREE.LatheGeometry(pts, 14);
}

// Clones a hierarchy (skinned or not) without JSON-copying userData (props keep Object3D refs there).
function safeClone(src, skinned = true) {
  const saved = [];
  src.traverse((o) => { saved.push([o, o.userData]); o.userData = {}; });
  try {
    return skinned ? SkeletonUtils.clone(src) : src.clone(true);
  } finally {
    for (const [o, u] of saved) o.userData = u;
  }
}

// ------------------------------------------------------------------------------------------------ instanced pools
// Tiny instanced effect pools (rings, squiggles, debris): one draw call each, hidden while empty.
class Pool {
  constructor(scene, geometry, material, cap, makeItem) {
    this.mesh = new THREE.InstancedMesh(geometry, material, cap);
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = false;
    this.mesh.receiveShadow = false;
    this.mesh.count = 0;
    this.mesh.visible = false;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.setColorAt(0, _col.set(1, 1, 1));
    this.mesh.name = `wonder:pool:${material.name || 'fx'}`;
    scene.add(this.mesh);
    this.items = [];
    for (let i = 0; i < cap; i++) this.items.push({ alive: false, c: new THREE.Color(), m: new THREE.Matrix4(), ...makeItem() });
    this.head = 0;
  }

  spawn() {
    const it = this.items[this.head];
    this.head = (this.head + 1) % this.items.length;
    it.alive = true;
    return it;
  }

  // fn(item, dt) -> bool alive; the item writes item.m / item.c.
  update(dt, fn) {
    let n = 0;
    const mesh = this.mesh;
    for (const it of this.items) {
      if (!it.alive) continue;
      if (!fn(it, dt)) { it.alive = false; continue; }
      mesh.setMatrixAt(n, it.m);
      mesh.setColorAt(n, it.c);
      n++;
    }
    mesh.count = n;
    mesh.visible = n > 0;
    if (n) {
      mesh.instanceMatrix.needsUpdate = true;
      mesh.instanceColor.needsUpdate = true;
    }
  }

  clear() {
    for (const it of this.items) it.alive = false;
    this.mesh.count = 0;
    this.mesh.visible = false;
  }
}

// ------------------------------------------------------------------------------------------------ Wonder
export class Wonder {
  constructor(game) {
    this.game = game;
    this.reloading = false;
    this.reloadId = null;
    this.reloadProgress = 0;
    this.recording = false;
    this.charge = 0;
    this.teles = [];
    this.debug = this._makeDebug();
    this._ready = false;
    this._frame = -1;
    this._delegated = false;
    this._dbgTrigger = null;
    this._dbgPrev = false;
    this._sdPrev = false;
    this._actors = [];       // gag / keyed / tumble / implode corpse actors + misc effects: { update(dt) -> bool, dispose() }
    this._hidden = new Map(); // z -> { group, t } originals hidden while their clone performs
    this._claimed = new Set(); // zombies already doomed by a wonder effect this frame (no double targeting)
    this._status = new Map();  // z -> status record (slow, panic, laugh, frozen, seat...)
    this._st = {};             // per-weapon state
    this._blobs = [];          // chroma goo blobs in flight
    this._puddles = [];
    this._sigCd = new Map();
    this._warmedArt = new Set();
    this._tele0 = null;        // Tiny Tele prototype (built lazily)
    this._teleCheck = null;
    this._lastTeles = null;
    this._applying = 0;
    this._kick = { x: 0, v: 0 };
    this._micTip = new THREE.Vector3();
    this._recLoop = null;
    this._ctxSD = { def: null, upgraded: false, slot: null, origin: new THREE.Vector3(), dir: new THREE.Vector3(), muzzle: new THREE.Vector3(),
      triggerDown: false, triggerPressed: false, triggerReleased: false, ads: false, dt: 0 };
  }

  // ------------------------------------------------------------------------------------------ lifecycle
  init() {
    if (this._ready) return;
    this._ready = true;
    const g = this.game;
    this._buildResources();
    const ev = g.events;
    ev.on('zombie:hit', (p) => this._onHit(p));
    ev.on('zombie:kill', (p) => this._onKill(p));
    ev.on('zombie:spawn', (p) => this._warmZombie(p && p.z));
    ev.on('game:start', () => this.reset());
    this._registerCues();
  }

  reset() {
    if (!this._ready) return;
    for (const a of this._actors) a.dispose?.();
    this._actors.length = 0;
    for (const [, h] of this._hidden) h.group.visible = true;
    this._hidden.clear();
    this._claimed.clear();
    for (const z of [...this._status.keys()]) this._clearStatus(z);
    this._status.clear();
    for (const b of this._blobs) b.mesh.removeFromParent();
    this._blobs.length = 0;
    for (const p of this._puddles) this._disposePuddle(p);
    this._puddles.length = 0;
    for (const t of this.teles) this._disposeTele(t);
    this.teles.length = 0;
    this._stopRecording(false);
    for (const k of ['rings', 'bold', 'squig', 'debris', 'splat', 'splatUp']) this.pools[k].clear();
    this._sigCd.clear();
    this._st = {};
    this.reloading = false;
    this.reloadId = null;
    this.reloadProgress = 0;
    this.charge = 0;
    this._teleCheck = null;
    this._lastTeles = null;
    this._kick.x = this._kick.v = 0;
    if (!this._warmedStatic) {
      this._warmedStatic = true;
      setTimeout(() => this._warmStatic(), 200);
    }
    try { this.game.zombies?.setLure?.(null); } catch (err) { /* zombies stub may be mid-rewrite */ }
  }

  // Game.precompile hook: throw-away samples of every mesh/material wonder spawns later.
  warmup() {
    if (!this._ready) this.init();
    const R = this.res, out = [];
    const add = (geo0, mat) => out.push(new THREE.Mesh(geo0, mat));
    add(R.tumble, R.mTumble);
    add(R.gel, R.mGel);
    add(R.blobGeo, R.mGoo);
    add(R.blobGeo, R.mGooUp);
    for (const m of [R.mPuddle, R.mPuddleUp, R.mPuddleRim, R.mPuddleRimUp, R.mPuddleSheen, R.mPuddleSheenUp]) add(R.puddle, m);
    add(R.flameOuter, R.mFlame);
    add(R.dot, R.mWhite);
    add(R.dot, R.mWhiteBody);
    add(R.cube, R.mIce);
    for (const k of ['flat', 'flatUp', 'static', 'bars']) add(R.cube, R.fx[k]);
    for (const w of [...WORLDS, ...WORLDS_UP]) add(R.cube, R.foot[w]);
    out.push(this._buildBunny());
    const tele = this._teleProto();
    if (tele) out.push(safeClone(tele, false));
    return out;
  }

  // Once per frame: from Game's UPDATE_ORDER when registered there, else from the render pre-pass hook.
  update(dt) {
    const g = this.game;
    if (!this._ready) this.init();
    if (this._frame === g.time.frame) return;
    this._frame = g.time.frame;
    FXU.time.value = g.time.realNow;
    g.renderer.getDrawingBufferSize(_v2);
    FXU.res.value.copy(_v2);
    if (g.state !== 'playing' && g.state !== 'down') dt = 0;
    this._claimed.clear();
    this._selfDrive(dt);
    this._updateReload(dt);
    this._updateWeaponState(dt);
    this._updateHeldModel(dt);
    this._updateBlobs(dt);
    this._updatePuddles(dt);
    this._updateTeles(dt);
    this._updateStatus(dt);
    this._updateActors(dt);
    this._updateHidden(dt);
    this._updatePools(dt);
    this._updateTeleCount();
  }

  // ------------------------------------------------------------------------------------------ public API
  isWonder(id) { return WONDER.has(id); }

  busy(weaponId) {
    return (this.reloading && this.reloadId === weaponId) || (weaponId === 'boom_mic' && this.recording);
  }

  fire(weaponId, ctx) {
    this._delegated = true;
    if (ctx && this._dbgTrigger !== null) {
      // tests: the simulated trigger replaces the mouse (still gated by weapons' ready flag)
      const d = !!this._dbgTrigger && ctx.ready !== false;
      ctx.triggerDown = d;
      ctx.triggerPressed = d && !this._dbgPrev;
      ctx.triggerReleased = !d && this._dbgPrev;
      if (ctx.triggerPressed) this._dbgPresses = (this._dbgPresses || 0) + 1;
      this._dbgPrev = d;
    }
    return this._fire(weaponId, ctx);
  }

  // weapons.js hooks (optional): the held wonder weapon was put away / raised.
  holster(weaponId) {
    if (weaponId === 'boom_mic' && this.recording) this._stopRecording(false);
    if (this.reloading && this.reloadId === weaponId) this._cancelReload();
    return true;
  }

  equip(weaponId) {
    const st = this._state(weaponId);
    st.buffer = 0;
    st.needle = undefined;
    return true;
  }

  reload(weaponId, ctx = {}) {
    if (!WONDER.has(weaponId)) return 0;
    const slot = ctx.slot || this._slotOf(weaponId);
    const def = ctx.def || this._defOf(weaponId, slot && slot.upgraded);
    return this._startReload(weaponId, slot, def);
  }

  // ctx (from weapons.js) = { origin (left hand), dir, velocity, aimPoint }: weapons already took one from
  // weapons.teles. Without ctx (self-drive / tests) wonder consumes one itself.
  throwTele(ctx = null) {
    if (!this._ready) this.init();
    const g = this.game, w = g.weapons, p = g.player;
    if (!p || !p.alive || p.downed) return false;
    const st = this._state('tele');
    if (st.cool > 0) return false;
    const fromWeapons = !!(ctx && ctx.origin && ctx.velocity);
    let consume = false;
    if (!fromWeapons && w && typeof w.teles === 'number') {
      const last = this._lastTeles ?? w.teles;
      if (w.teles < last) consume = false;          // the caller already took one this frame
      else if (w.teles > 0) consume = true;
      else return false;                             // none left
    }
    st.cool = 0.3;
    if (!this._spawnTele(fromWeapons ? ctx : null)) return false;
    if (consume) this._teleCheck = { value: w.teles, frame: g.time.frame };
    return true;
  }

  // Forces a signal-color proc on z (weapons may call it; also the debug path). signal: hot_mic|laugh_track|cold_open.
  applySignal(z, signal, { weaponId = null, splash = false } = {}) {
    signal = String(signal || '').replace(/^signal_/, '');
    if (!z || !SIGNALS.includes(signal) || !this._alive(z)) return false;
    if (signal === 'hot_mic') this._ignite(z, 1, weaponId);
    else if (signal === 'laugh_track') this._laughTrack(z, weaponId);
    else this._coldOpen(z, weaponId);
    this.game.events.emit('wonder:signal', { z, signal, weaponId, splash });
    return true;
  }

  // ------------------------------------------------------------------------------------------ helpers
  _state(id) {
    return this._st[id] || (this._st[id] = { cool: 0, buffer: 0, recover: 0, rec: 0, playT: 0 });
  }

  _slotOf(id) {
    const w = this.game.weapons;
    return (w && w.slots && w.slots.find((s) => s && s.id === id)) || null;
  }

  _defOf(id, upgraded) {
    const w = this.game.weapons;
    const cur = w && w.slots && w.slots[w.current];
    if (cur && cur.id === id && typeof w.currentDef === 'function') {
      try { const d = w.currentDef(); if (d) return d; } catch (err) { /* stub */ }
    }
    const d = w && w.defs && w.defs[id];
    if (d && upgraded && d.upgraded) return { ...d, ...d.upgraded, isUpgraded: true };
    return d || null;
  }

  _mag(id, def, up) {
    const m = MAGS[id];
    return (def && def.mag) || (m ? m[up ? 2 : 0] : 1);
  }

  _round() {
    const r = this.game.rounds;
    return Math.max(1, (r && r.round) || 1);
  }

  _isBoss(z) {
    return !!z && (z.type === 'boss_baron' || z.boss === true || (z.flags && z.flags.boss));
  }

  _alive(z) {
    return !!z && z.state !== 'dying' && z.state !== 'dead' && !(z.hp <= 0) && !this._claimed.has(z);
  }

  _zombies() {
    const zm = this.game.zombies;
    return (zm && zm.alive) || [];
  }

  // Chest aim point of a zombie.
  _chest(z, out) {
    const h = z.height || 1.6;
    return out.set(z.pos.x, z.pos.y + h * 0.58, z.pos.z);
  }

  _headPos(z, out) {
    if (z.head && z.head.getWorldPosition) return z.head.getWorldPosition(out);
    return out.set(z.pos.x, z.pos.y + (z.height || 1.6) * 0.85, z.pos.z);
  }

  _los(a, b) {
    const col = this.game.level && this.game.level.col;
    return !col || col.lineOfSight(a, b);
  }

  _damage(z, amount, weaponId, cause, extra = {}) {
    const zm = this.game.zombies;
    if (!zm || !zm.damage) return false;
    const prev = this._dmgCtx;
    this._dmgCtx = { weaponId, cause, splash: !!extra.splash, upgraded: !!extra.upgraded };
    this._applying++;
    try {
      // inside _doom a lethal hit must not play the manager's own death (the clone animates it): corpse false
      const info = this._dooming ? { head: false, weaponId, cause, corpse: false, ...extra } : { head: false, weaponId, cause, ...extra };
      return !!zm.damage(z, amount, info);
    } catch (err) {
      console.warn('[wonder] zombies.damage failed', err);
      return false;
    } finally {
      this._applying--;
      this._dmgCtx = prev;
    }
  }

  // Kills z (for a corpse wonder animates). Returns true when it died.
  _kill(z, weaponId, cause, extra = {}) {
    const killed = this._damage(z, 1e7, weaponId, cause, { corpse: false, knockback: 0, ...extra });
    return killed || z.hp <= 0 || z.state === 'dying';
  }

  // Damages z through fn() with its corpse clone already built and the original hidden, so the zombie manager's
  // own death visuals (stun stars, static dissolve) stay invisible and wonder's death animation replaces them.
  // Returns the corpse (or true without a model) when z died, else null (the original is shown again).
  _doom(z, fn) {
    const P = this._corpse(z);
    let killed = false;
    this._dooming = (this._dooming || 0) + 1;
    try { killed = !!fn(); } catch (err) { console.warn('[wonder] damage failed', err); } finally { this._dooming--; }
    killed = killed || !(z.hp > 0) || z.state === 'dying' || z.dead === true;
    if (!killed) {
      if (P) P.dispose();
      this._unhide(z);
      return null;
    }
    return P || true;
  }

  // Real stun (stars over the head): zombies.stun when available.
  _stun(z, s) {
    const zm = this.game.zombies;
    if (zm && typeof zm.stun === 'function') {
      try { zm.stun(z, s); return; } catch (err) { /* fall through */ }
    }
    this._hold(z, s);
  }

  // Keeps the zombie AI idle for s seconds (no walking, no attacks).
  _hold(z, s) {
    if (typeof z.stun === 'number' || z.stun === undefined) z.stun = Math.max(z.stun || 0, s);
    else if (typeof this.game.zombies?.stun === 'function') this.game.zombies.stun(z, s);
  }

  _stunRadius(pos, r, s, except = null) {
    for (const z of this._zombies()) {
      if (z === except || !this._alive(z) || this._isBoss(z)) continue;
      if (z.pos.distanceTo(pos) <= r) {
        this._stun(z, s);
        z.animator?.kick?.(0.8);
      }
    }
  }

  _play(id, opts) {
    try { return this.game.audio?.play?.(id, opts) || null; } catch (err) { return null; }
  }

  _emit(name, payload) {
    this.game.events.emit(name, payload);
  }

  _floorY(x, z, yFrom) {
    const col = this.game.level && this.game.level.col;
    const f = col ? col.floorAt(x, z, yFrom) : 0;
    return f > -Infinity ? f : null;
  }

  // Keeps a moving effect out of walls: returns the allowed travel distance from `from` along dir (xz).
  _clearDist(from, dir, dist, margin = 0.35) {
    const col = this.game.level && this.game.level.col;
    if (!col) return dist;
    _a.copy(from).setY(from.y + 0.4);
    const hit = col.raycast(_a, _b.copy(dir).setY(0).normalize(), dist + margin);
    return hit ? Math.max(0, hit.dist - margin) : dist;
  }

  // ------------------------------------------------------------------------------------------ resources
  _buildResources() {
    const g = this.game, M = g.mats, S = g.scene;
    const R = (this.res = {});
    R.ring = new THREE.RingGeometry(0.88, 1, 48);
    R.ringBold = new THREE.RingGeometry(0.7, 1, 48);
    R.tumble = tumbleweedGeo();
    R.gel = gelatinGeo();
    R.blobGeo = geo.sphere(1, 20, 14);
    R.puddle = blobShapeGeo(11);
    R.squig = squiggleGeo();
    R.flameOuter = flameGeo(1);
    R.flameInner = flameGeo(0.62);
    R.dot = geo.sphere(0.06, 12, 8);
    R.cube = geo.roundedBox(1, 1, 1, 0.18, 2);
    const keep = { keepColor: true };
    R.mTumble = M.toon('#C79A55', { ...keep, rough: 0.85, rim: 0.5, rimColor: '#FFE2A8' });
    R.mGel = M.toon('#38C850', { ...keep, rough: 0.05, transparent: true, opacity: 0.86, rim: 0.7, rimColor: '#DFFFD8', rimPower: 2.2,
      emissive: '#1B7A2E', emissiveIntensity: 0.12, env: 0.7, name: 'wonder_gel' });
    R.mGelEye = M.toon('#1E7A30', { ...keep, rough: 0.2, rim: 0.4 });
    R.mPlate = M.toon('#F4F1E8', { ...keep, rough: 0.25, rim: 0.3, env: 0.4 });
    R.mCherry = M.toon('#E23B3B', { ...keep, rough: 0.15, rim: 0.6, env: 0.6 });
    R.mBunny = M.toon('#FFFFFF', { ...keep, rough: 0.95, rim: 0.75, rimColor: '#FFFFFF', wrap: 0.8 });
    R.mPink = M.toon('#FF9EC4', { ...keep, rough: 0.7, rim: 0.4 });
    R.mInk = M.toon('#2A1D3A', { ...keep, rough: 0.3, rim: 0.2 });
    R.mGoo = M.toon(PAL.chromaBlue, { ...keep, rough: 0.08, rim: 0.9, rimColor: '#BFD4FF', emissive: PAL.chromaBlue, emissiveIntensity: 0.5, env: 0.9 });
    R.mGooUp = M.toon(PAL.greenScreen, { ...keep, rough: 0.08, rim: 0.9, rimColor: '#E4FFD8', emissive: PAL.greenScreen, emissiveIntensity: 0.5, env: 0.9 });
    // puddle = dark goo rim + saturated body + a glossy sheen blob (three stacked flat layers, polygon offset)
    R.mPuddle = M.toon('#1440D0', { ...keep, rough: 0.34, rim: 0.2, emissive: PAL.chromaBlue, emissiveIntensity: 0.26, env: 0.1, name: 'wonder_puddle' });
    R.mPuddleUp = M.toon('#2CC24E', { ...keep, rough: 0.34, rim: 0.2, emissive: PAL.greenScreen, emissiveIntensity: 0.2, env: 0.1, name: 'wonder_puddle_up' });
    R.mPuddleRim = M.toon('#0C2A8C', { ...keep, rough: 0.4, rim: 0.1, emissive: '#0C2A8C', emissiveIntensity: 0.2, name: 'wonder_puddle_rim' });
    R.mPuddleRimUp = M.toon('#14803A', { ...keep, rough: 0.4, rim: 0.1, emissive: '#14803A', emissiveIntensity: 0.15, name: 'wonder_puddle_rim_up' });
    R.mPuddleSheen = M.toon('#4F7BFF', { ...keep, rough: 0.12, rim: 0.3, emissive: '#3E6BFF', emissiveIntensity: 0.32, env: 0.3, name: 'wonder_puddle_sheen' });
    R.mPuddleSheenUp = M.toon('#8CF08A', { ...keep, rough: 0.12, rim: 0.3, emissive: '#6CE86A', emissiveIntensity: 0.26, env: 0.3, name: 'wonder_puddle_sheen_up' });
    R.puddleSheen = blobShapeGeo(23, 18);
    [[R.mPuddleRim, -1], [R.mPuddleRimUp, -1], [R.mPuddle, -2], [R.mPuddleUp, -2], [R.mPuddleSheen, -3], [R.mPuddleSheenUp, -3]].forEach(([m, k]) => {
      m.polygonOffset = true; m.polygonOffsetFactor = k; m.polygonOffsetUnits = k;
    });
    R.mFlame = M.glow('#FF7A2E', 2.6, { additive: true });
    R.mFlameIn = M.glow('#FFE14D', 3.2, { additive: true });
    R.mWhite = M.glow('#FFFFFF', 3.2);
    R.mWhiteBody = M.glow('#FFFFFF', 1.25);
    R.mIce = M.toon('#5DB8EC', { ...keep, rough: 0.3, rim: 0.45, rimColor: '#E6F7FF', rimPower: 2.2, emissive: '#16508A', emissiveIntensity: 0.1, env: 0.3, steps: 3, name: 'wonder_ice' });
    R.mBattery = M.toon('#F4C81E', { ...keep, rough: 0.35, rim: 0.4 });
    R.fx = {
      flat: fxMaterial('flat', { color: PAL.chromaBlue, intensity: 1.25, rim: '#9DB9FF', rimK: 0.55 }),
      flatUp: fxMaterial('flat', { color: PAL.greenScreen, intensity: 1.1, rim: '#E4FFD8', rimK: 0.55 }),
      static: fxMaterial('static', { rim: '#FFFFFF', rimK: 0.3 }),
      bars: fxMaterial('bars', { rim: '#FFFFFF', rimK: 0.25 }),
    };
    R.foot = {};
    [...WORLDS, ...WORLDS_UP].forEach((w, i) => {
      let map = null;
      try { map = getCard(`world_${w}`); } catch (err) { map = null; }
      const fo = { map, world: i, rim: WORLD_TINT[w], rimK: 0.4, focus: WORLD_FOCUS[w] };
      R.foot[w] = fxMaterial('footage', fo);
      R.foot[w].userData.fxOpts = fo;
    });
    const add = (gm, mat) => {
      mat.transparent = true;
      mat.depthWrite = false;
      mat.blending = THREE.AdditiveBlending;
      mat.side = THREE.DoubleSide;
      mat.toneMapped = true;
      mat.name = mat.name || 'wonder_add';
      return mat;
    };
    const ringMat = add(null, new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false }));
    ringMat.name = 'wonder_rings';
    const boldMat = add(null, new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false }));
    boldMat.name = 'wonder_bold';
    const squigMat = add(null, new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false }));
    squigMat.name = 'wonder_squig';
    const debrisMat = M.toon('#FFFFFF', { ...keep, rough: 0.18, rim: 0.55, rimColor: '#EAF8FF', env: 0.55, emissive: '#3E86C8', emissiveIntensity: 0.12, name: 'wonder_debris' });
    const ringItem = () => ({ from: new THREE.Vector3(), to: new THREE.Vector3(), q: new THREE.Quaternion(), t: 0, delay: 0, dur: 0.2, s0: 0.1, s1: 0.4, base: new THREE.Color(), flat: false });
    this.pools = {
      rings: new Pool(S, R.ring, ringMat, 96, ringItem),
      bold: new Pool(S, R.ringBold, boldMat, 64, ringItem),
      squig: new Pool(S, R.squig, squigMat, 64, () => ({ from: new THREE.Vector3(), t: 0, dur: 0.45, base: new THREE.Color(), seed: 0, side: new THREE.Vector3() })),
      debris: new Pool(S, R.cube, debrisMat, 96, () => ({ pos: new THREE.Vector3(), vel: new THREE.Vector3(), rot: new THREE.Euler(), spin: new THREE.Vector3(), t: 0, life: 1, size: 0.1, floor: 0 })),
    };
    this.pools.debris.mesh.castShadow = true;
    // chroma splat marks on walls / floors: fade out with the puddle (fixed pools, one draw each, hidden while empty)
    R.splatGeo = new THREE.PlaneGeometry(1, 1);
    const splatMat = (up) => {
      const m = new THREE.MeshBasicMaterial({ map: splatTexture(up), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 });
      m.name = up ? 'wonder_splat_up' : 'wonder_splat';
      return alphaFromInstance(m, 'wonderSplatAlpha');
    };
    const splatItem = () => ({ pos: new THREE.Vector3(), q: new THREE.Quaternion(), size: 1.1, t: 0, dur: 4 });
    this.pools.splat = new Pool(S, R.splatGeo, splatMat(false), 24, splatItem);
    this.pools.splatUp = new Pool(S, R.splatGeo, splatMat(true), 24, splatItem);
    this._screenTex = this._makeCartoon();
  }

  _registerCues() {
    const A = this.game.audio;
    if (!A || typeof A.registerCues !== 'function' || !A.cues) return;
    const table = {};
    if (!A.cues.wonder_fwoomp) table.wonder_fwoomp = (a, dest, o) => {
      const t = o.t;
      a.noise(dest, t, { type: 'lowpass', f: 900, f1: 2600, q: 1.2, glide: 0.25, dur: 0.45, a: 0.02, peak: 0.9 });
      a.tone(dest, t, { f: 90, f1: 55, glide: 0.3, dur: 0.35, peak: 0.5 });
      for (let i = 0; i < 6; i++) a.click(dest, t + 0.1 + i * 0.07 * Math.random(), { f: 1800 + Math.random() * 2400, peak: 0.25 });
      return t + 0.6;
    };
    if (!A.cues.wonder_yeowch) table.wonder_yeowch = (a, dest, o) => a.formant(dest, o.t, { base: 190 * (o.pitch || 1), syl: [{ d: 0.12, p: 1.3, p1: 1.9, v: 'i' }, { d: 0.28, p: 1.9, p1: 1.1, v: 'o' }], peak: 0.45, vib: 18 }) || o.t + 0.5;
    if (!A.cues.wonder_freeze) table.wonder_freeze = (a, dest, o) => {
      const t = o.t;
      a.noise(dest, t, { type: 'highpass', f: 5000, f1: 2500, dur: 0.35, peak: 0.5 });
      for (let i = 0; i < 5; i++) a.tone(dest, t + i * 0.045, { f: 2400 + i * 520, dur: 0.18, peak: 0.12, a: 0.002, curve: 'fast' });
      a.tone(dest, t, { f: 220, f1: 140, glide: 0.2, dur: 0.25, peak: 0.25 });
      return t + 0.5;
    };
    if (!A.cues.wonder_shatter) table.wonder_shatter = (a, dest, o) => {
      const t = o.t;
      a.noise(dest, t, { type: 'highpass', f: 2200, dur: 0.18, peak: 0.9, curve: 'fast' });
      for (let i = 0; i < 12; i++) a.tone(dest, t + Math.random() * 0.4, { f: 2600 + Math.random() * 3800, dur: 0.08, peak: 0.1, a: 0.001, curve: 'fast' });
      return t + 0.6;
    };
    if (Object.keys(table).length) A.registerCues(table, { bus: 'sfx' });
  }

  // The Tiny Tele's bouncy cartoon: a private 160x120 canvas redrawn at 12 fps while a tele is live.
  _makeCartoon() {
    const cv = document.createElement('canvas');
    cv.width = 160;
    cv.height = 120;
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.generateMipmaps = false;
    tex.minFilter = THREE.LinearFilter;
    this._cartoon = { cv, ctx: cv.getContext('2d'), tex, frame: -1 };
    this._drawCartoon(0);
    return tex;
  }

  _drawCartoon(time) {
    const C = this._cartoon;
    const f = Math.floor(time * 12);
    if (f === C.frame) return;
    C.frame = f;
    const ctx = C.ctx, w = 160, h = 120, t = f / 12;
    const sky = ctx.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0, '#FFB3D9');
    sky.addColorStop(1, '#FFE3A3');
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);
    // spinning sunburst
    ctx.save();
    ctx.translate(w / 2, h * 0.55);
    ctx.rotate(t * 0.8);
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    for (let i = 0; i < 12; i++) {
      ctx.rotate(TAU / 12);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(120, -14);
      ctx.lineTo(120, 14);
      ctx.fill();
    }
    ctx.restore();
    // checker floor in color bars
    const bars = ['#EDEDED', '#F4E03A', '#3FD6E0', '#52D24A', '#D64FD6', '#E4473A', '#3A58E4'];
    for (let i = 0; i < 7; i++) {
      ctx.fillStyle = bars[(i + f) % 7];
      ctx.fillRect(i * (w / 7), h * 0.82, w / 7 + 1, h * 0.18);
    }
    // bouncing blob buddy (squash & stretch)
    const ph = (t * 2.5) % 1;
    const hop = Math.sin(ph * Math.PI);
    const squash = ph < 0.12 || ph > 0.88 ? 0.75 : 1 + hop * 0.12;
    const bx = w / 2 + Math.sin(t * 1.3) * 34, by = h * 0.82 - 4 - hop * 46;
    ctx.save();
    ctx.translate(bx, by);
    ctx.scale(1 / Math.sqrt(squash), squash);
    ctx.fillStyle = '#E3662B';
    ctx.strokeStyle = '#2A1D3A';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.ellipse(0, -18, 20, 18, 0, 0, TAU);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#FFFFFF';
    for (const s of [-1, 1]) { ctx.beginPath(); ctx.ellipse(s * 7, -22, 5, 6.5, 0, 0, TAU); ctx.fill(); ctx.stroke(); }
    ctx.fillStyle = '#2A1D3A';
    for (const s of [-1, 1]) { ctx.beginPath(); ctx.arc(s * 7 + 1.5, -21, 2.4, 0, TAU); ctx.fill(); }
    ctx.beginPath();
    ctx.arc(0, -13, 6, 0.15 * Math.PI, 0.85 * Math.PI);
    ctx.stroke();
    ctx.restore();
    // twinkles
    ctx.fillStyle = '#FFFFFF';
    for (let i = 0; i < 5; i++) {
      const a = (f * 0.7 + i * 1.7) % 6.28;
      const x = 18 + ((i * 37 + f * 3) % 124), y = 12 + ((i * 23) % 40);
      const r = 2 + Math.abs(Math.sin(a)) * 2.5;
      ctx.beginPath();
      ctx.moveTo(x, y - r * 2); ctx.lineTo(x + r * 0.5, y); ctx.lineTo(x, y + r * 2); ctx.lineTo(x - r * 0.5, y); ctx.fill();
      ctx.beginPath();
      ctx.moveTo(x - r * 2, y); ctx.lineTo(x, y + r * 0.5); ctx.lineTo(x + r * 2, y); ctx.lineTo(x, y - r * 0.5); ctx.fill();
    }
    // the channel 9 bug
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.font = 'bold 14px "Titan One", sans-serif';
    ctx.fillText('9', w - 16, 18);
    C.tex.needsUpdate = true;
  }

  // Compiles the programs of `holder` (added far below the map) against the HDR scene target, then drops it.
  _compile(holder) {
    const g = this.game;
    holder.position.set(0, -500, 0);
    g.scene.add(holder);
    holder.updateMatrixWorld(true);
    const r = g.renderer, prev = r.getRenderTarget();
    let pending = null;
    try {
      r.setRenderTarget(g.render.composer.readBuffer);
      pending = r.compileAsync ? r.compileAsync(holder, g.camera, g.scene) : (r.compile(holder, g.camera, g.scene), null);
    } catch (err) {
      console.warn('[wonder] compile failed', err);
    } finally {
      r.setRenderTarget(prev);
    }
    const done = () => holder.removeFromParent();
    if (pending && pending.then) pending.then(done, done);
    else done();
  }

  // After boot: build the Tiny Tele prop once (AO bake) and compile every wonder material.
  _warmStatic() {
    try {
      const holder = new THREE.Group();
      for (const o of this.warmup()) holder.add(o);
      this._compile(holder);
    } catch (err) {
      console.warn('[wonder] warm-up failed', err);
    }
  }

  // Shader warm-up per zombie art: the fx materials on a clone of the first zombie of each look.
  _warmZombie(z) {
    if (!z || !z.group || !this._ready) return;
    const key = z.group.name || z.type || 'z';
    if (this._warmedArt.has(key)) return;
    this._warmedArt.add(key);
    setTimeout(() => {
      try {
        if (!z.group) return;
        const R = this.res;
        const holder = new THREE.Group();
        const mats = [R.fx.flat, R.fx.flatUp, R.fx.static, R.fx.bars, R.mWhiteBody, R.mIce, R.foot.space];
        for (const mat of mats) {
          const c = safeClone(z.group, true);
          c.visible = true;
          c.position.set(0, 0, 0);
          c.traverse((o) => { if (o.isMesh) { o.material = mat; o.visible = true; } });
          holder.add(c);
        }
        this._compile(holder);
      } catch (err) {
        console.warn('[wonder] warm-up failed', err);
      }
    }, 0);
  }

  // ------------------------------------------------------------------------------------------ self drive / fallback
  _selfDrive(dt) {
    if (this._delegated) return;
    const g = this.game, w = g.weapons, p = g.player;
    const slot = w && w.slots && w.slots[w.current];
    const input = g.input;
    if (input && dt > 0 && input.pressed && input.pressed('tactical') && !(w && w._handlesTele)) this.throwTele();
    if (!slot || !WONDER.has(slot.id)) { this._sdPrev = false; return; }
    const ctx = this._ctxSD;
    const down = this._dbgTrigger !== null ? !!this._dbgTrigger : !!(input && input.down && input.down('fire'));
    const canFire = p && p.alive && !p.downed && !p.sprinting && dt > 0;
    ctx.triggerDown = down && canFire;
    ctx.triggerPressed = ctx.triggerDown && !this._sdPrev;
    ctx.triggerReleased = !ctx.triggerDown && this._sdPrev;
    this._sdPrev = ctx.triggerDown;
    ctx.slot = slot;
    ctx.upgraded = !!slot.upgraded;
    ctx.def = this._defOf(slot.id, slot.upgraded);
    ctx.ads = !!(p && p.ads);
    ctx.dt = dt;
    if (p) {
      p.aimRay(ctx.origin, ctx.dir);
      p.muzzle(ctx.muzzle);
    }
    if (input && input.pressed && input.pressed('reload') && this._dbgTrigger === null) this._startReload(slot.id, slot, ctx.def);
    this._fire(slot.id, ctx);
  }

  // ------------------------------------------------------------------------------------------ firing
  _fire(weaponId, ctx) {
    if (!this._ready) this.init();
    if (!WONDER.has(weaponId) || !ctx) return false;
    const st = this._state(weaponId);
    st.lastFire = this.game.time.now;
    st.ctx = ctx;
    const slot = ctx.slot || this._slotOf(weaponId);
    if (!slot) return false;
    ctx.slot = slot;
    if (!ctx.def) ctx.def = this._defOf(weaponId, ctx.upgraded ?? slot.upgraded);
    if (ctx.upgraded === undefined) ctx.upgraded = !!slot.upgraded;
    if (this.reloading) {
      if (this.reloadId === weaponId) return false;
    }
    if (weaponId === 'zapper') return this._zapperFire(ctx, st, slot);
    if (weaponId === 'boom_mic') return this._boomFire(ctx, st, slot);
    return this._chromaFire(ctx, st, slot);
  }

  // Empty mag: auto-reload, or dry fire on the press.
  _empty(weaponId, ctx, slot) {
    if (slot.mag > 0) return false;
    if (slot.reserve > 0) this._startReload(weaponId, slot, ctx.def);
    else if (ctx.triggerPressed) this._emit('weapon:empty', { weaponId });
    return true;
  }

  _recoil(amount, weaponId) {
    const g = this.game, p = g.player;
    if (p && p.anim) p.anim.recoil = 1;
    g.cam?.kick?.(amount, (Math.random() - 0.5) * amount * 0.3);
    this._kick.v -= amount * 60;
  }

  _startReload(weaponId, slot, def) {
    if (!slot || !WONDER.has(weaponId)) return 0;
    if (this.reloading && this.reloadId === weaponId) return this._reloadT;
    const up = !!slot.upgraded;
    const mag = this._mag(weaponId, def, up);
    if (slot.mag >= mag || !(slot.reserve > 0)) return 0;
    if (weaponId === 'boom_mic' && this.recording) return 0;
    const base = (def && def.reload) || (weaponId === 'zapper' ? G.zapper.reload : weaponId === 'boom_mic' ? G.boom.reload : G.chroma.reload);
    const mods = this.game.player && this.game.player.mods;
    this.reloading = true;
    this.reloadId = weaponId;
    this.reloadProgress = 0;
    this._reloadT = base * ((mods && mods.reloadSpeed) || 1);
    this._reloadEl = 0;
    this._reloadSlot = slot;
    this._reloadMag = mag;
    this._reloadFx = 0;
    this._reloadCue = (def && def.reloadCue) || (weaponId === 'zapper' ? 'reload_battery' : weaponId === 'boom_mic' ? 'reload_reel' : 'reload_goo');
    this._reloadBeat = 1;
    this._emit('weapon:reload', { weaponId });
    this._play(this._reloadCue, { vol: 0.9, rate: 0.9 });
    return this._reloadT;
  }

  _updateReload(dt) {
    if (!this.reloading) return;
    const g = this.game, w = g.weapons;
    const cur = w && w.slots && w.slots[w.current];
    if (!cur || cur.id !== this.reloadId) { this._cancelReload(); return; }
    this._reloadEl += dt;
    const k = clamp01(this._reloadEl / Math.max(0.05, this._reloadT));
    this.reloadProgress = k;
    if (g.player && g.player.anim) g.player.anim.reload = Math.min(0.999, k);
    if (this.reloadId === 'zapper' && this._reloadFx === 0 && k > 0.08) {
      this._reloadFx = 1;
      this._popBattery();
    }
    // second beat: the fresh battery / reels / goo cartridge clicks home
    if (this._reloadBeat === 1 && k > 0.66) {
      this._reloadBeat = 2;
      this._play(this._reloadCue, { vol: 0.9, rate: 1.15 });
      if (this.reloadId === 'chroma_key') {
        const m = this._heldParts()?.goo;
        if (m) g.fx?.burst?.(m.getWorldPosition(_a), { shape: 'goo', count: 5, speed: 1.6, size: 0.04, life: 0.4, colors: this._reloadSlot?.upgraded ? [PAL.greenScreen, '#E4FFD8'] : [PAL.chromaBlue, '#BFD4FF'] });
      }
    }
    if (k >= 1) {
      const s = this._reloadSlot;
      if (s && s.mag < this._reloadMag) {
        const n = Math.min(this._reloadMag - s.mag, s.reserve);
        s.mag += n;
        s.reserve -= n;
      }
      this._cancelReload();
    }
  }

  _cancelReload() {
    this.reloading = false;
    this.reloadId = null;
    this.reloadProgress = 0;
    const p = this.game.player;
    if (p && p.anim) p.anim.reload = 0;
  }

  // The spent battery springs out of the Zapper's rear and clatters on the floor.
  _popBattery() {
    const g = this.game, p = g.player;
    if (!p) return;
    const parts = this._heldParts();
    const src = parts && parts.battery;
    if (src) src.getWorldPosition(_a);
    else p.muzzle(_a);
    const R = this.res;
    const bat = new THREE.Group();
    bat.add(geo.mesh(geo.cylinder(0.02, 0.02, 0.1, 12), R.mBattery, { rot: [Math.PI / 2, 0, 0] }));
    bat.add(geo.mesh(geo.cylinder(0.021, 0.021, 0.025, 12), R.mInk, { pos: [0, 0, -0.05], rot: [Math.PI / 2, 0, 0] }));
    bat.position.copy(_a);
    g.scene.add(bat);
    p.forward(_b);
    const vel = new THREE.Vector3(-_b.z * 1.2 + (Math.random() - 0.5), 3.2, _b.x * 1.2).addScaledVector(_b, -1.4);
    const spin = new THREE.Vector3(9, 4, 6);
    let t = 0, bounces = 0;
    const floor = this._floorY(_a.x, _a.z, _a.y) ?? p.pos.y;
    this._actors.push({
      update: (dt) => {
        t += dt;
        vel.y -= 16 * dt;
        bat.position.addScaledVector(vel, dt);
        bat.rotation.x += spin.x * dt;
        bat.rotation.y += spin.y * dt;
        if (bat.position.y < floor + 0.03 && vel.y < 0) {
          bat.position.y = floor + 0.03;
          if (bounces++ < 2) {
            vel.y *= -0.38;
            vel.x *= 0.5;
            vel.z *= 0.5;
            spin.multiplyScalar(0.5);
            this._play('grenade_bounce', { pos: bat.position, vol: 0.4, rate: 1.6 });
          } else vel.set(0, 0, 0), spin.set(0, 0, 0);
        }
        if (t > 2.2) bat.scale.setScalar(Math.max(0.001, 1 - (t - 2.2) / 0.3));
        return t < 2.5;
      },
      dispose: () => bat.removeFromParent(),
    });
  }

  _updateWeaponState(dt) {
    for (const id in this._st) {
      const st = this._st[id];
      st.cool = Math.max(0, st.cool - dt);
      st.buffer = Math.max(0, st.buffer - dt);
      st.recover = Math.max(0, st.recover - dt);
    }
    const w = this.game.weapons;
    const cur = w && w.slots && w.slots[w.current];
    // Boom Mic: stop recording when put away or no longer driven (sprint, swap, down).
    if (this.recording) {
      const st = this._state('boom_mic');
      const stale = this.game.time.now - (st.lastFire ?? 0) > 0.3;
      if (!cur || cur.id !== 'boom_mic' || stale) this._stopRecording(false);
      else this._updateRecording(dt, st);
    }
    this._kick.v += (-this._kick.x * 260 - this._kick.v * 18) * dt;
    this._kick.x += this._kick.v * dt;
  }

  // Held-model parts: VU needle, reels, battery, keys, goo (src/props/weapons.js userData.parts).
  _heldModel() {
    const p = this.game.player;
    return (p && p.weaponModel) || null;
  }

  _heldParts() {
    const m = this._heldModel();
    if (!m) return null;
    if (m.userData.__wonderParts && m.userData.__wonderParts.model === m) return m.userData.__wonderParts.parts;
    let parts = m.userData.parts && Object.keys(m.userData.parts).length ? m.userData.parts : null;
    if (!parts) {
      m.traverse((o) => { if (!parts && o.userData && o.userData.parts && Object.keys(o.userData.parts).length) parts = o.userData.parts; });
    }
    if (!parts) {
      parts = {};
      for (const n of ['needle', 'reelL', 'reelR', 'battery', 'keys', 'goo', 'mic']) { const o = m.getObjectByName(n); if (o) parts[n] = o; }
    }
    for (const k in parts) {
      const o = parts[k];
      if (o && !o.userData.__wbase) o.userData.__wbase = { p: o.position.clone(), r: o.rotation.clone(), s: o.scale.clone() };
    }
    m.userData.__wonderParts = { model: m, parts };
    return parts;
  }

  _updateHeldModel(dt) {
    const g = this.game, w = g.weapons;
    const cur = w && w.slots && w.slots[w.current];
    const m = this._heldModel();
    if (!m || !cur) return;
    const inner = m.getObjectByName('wpn') || m.children[0];
    if (inner && WONDER.has(cur.id)) {
      if (inner.userData.__wrx === undefined) inner.userData.__wrx = inner.rotation.x;
      inner.rotation.x = inner.userData.__wrx - this._kick.x;
    }
    if (!WONDER.has(cur.id)) return;
    const parts = this._heldParts();
    if (!parts) return;
    const t = g.time.now;
    const rel = this.reloading && this.reloadId === cur.id ? this.reloadProgress : -1;
    if (cur.id === 'zapper') {
      if (parts.keys) {
        const st = this._state('zapper');
        const b = parts.keys.userData.__wbase;
        parts.keys.position.y = b.p.y - (st.cool > 0.33 ? 0.004 : 0);
      }
      if (parts.battery) {
        const b = parts.battery.userData.__wbase;
        let z = 0, vis = true;
        if (rel >= 0) {
          if (rel < 0.1) z = E.outBack(rel / 0.1) * 0.09;
          else if (rel < 0.55) vis = false;
          else if (rel < 0.85) z = (1 - E.outCubic(seg(rel, 0.55, 0.85))) * 0.09;
        }
        parts.battery.position.z = b.p.z + z;
        parts.battery.visible = vis;
      }
    } else if (cur.id === 'boom_mic') {
      const spin = this.recording ? (cur.upgraded ? 18 : 10) : 1.2;
      const st = this._state('boom_mic');
      st.reelA = (st.reelA || 0) + dt * spin;
      let rs = 1;
      if (rel >= 0) rs = rel < 0.3 ? 1 - E.inBack(rel / 0.3) : rel < 0.5 ? 0 : E.outBack(seg(rel, 0.5, 0.8));
      for (const [k, f] of [['reelL', 1], ['reelR', 0.8]]) {
        const o = parts[k];
        if (!o) continue;
        o.rotation.y = st.reelA * f;
        o.scale.setScalar(Math.max(0.001, rs) * o.userData.__wbase.s.x);
      }
      if (parts.needle) {
        const target = this.recording ? this.charge / 10 : (st.playT > 0 ? st.playT : 0.05 + 0.04 * Math.sin(t * 5));
        st.needle = st.needle === undefined ? target : lerp(st.needle, target + (this.recording ? Math.sin(t * 31) * 0.035 : 0), 1 - Math.exp(-dt * 18));
        parts.needle.rotation.x = 0.7 - clamp01(st.needle) * 1.4;
      }
      if (parts.mic) {
        const s = 1 + (this.recording ? Math.sin(t * 22) * 0.04 : 0) + (st.playT > 0 ? st.playT * 0.25 : 0);
        parts.mic.scale.setScalar(s);
      }
      st.playT = Math.max(0, (st.playT || 0) - dt * 1.4);
    } else if (cur.id === 'chroma_key') {
      if (parts.goo) {
        let fill = 1;
        if (rel >= 0) fill = rel < 0.4 ? 1 - E.inQuad(rel / 0.4) : rel < 0.55 ? 0.05 : E.outElastic(seg(rel, 0.55, 1));
        const st = this._state('chroma_key');
        const wob = Math.sin(t * 7) * 0.035 + (st.cool > 0.45 ? Math.sin(t * 40) * 0.08 * (st.cool - 0.45) * 4 : 0);
        const b = parts.goo.userData.__wbase.s;
        parts.goo.scale.set(b.x * (1 + wob), b.y * Math.max(0.05, fill) * (1 - wob), b.z * (1 + wob));
      }
    }
  }

  // ------------------------------------------------------------------------------------------ ZAPPER
  _zapperFire(ctx, st, slot) {
    if (ctx.triggerPressed) st.buffer = 0.16;
    if (st.cool > 0 || st.buffer <= 0) return false;
    if (this._empty('zapper', ctx, slot)) { st.buffer = 0; return false; }
    st.buffer = 0;
    const def = ctx.def || {}, up = !!ctx.upgraded;
    const mods = this.game.player && this.game.player.mods;
    st.cool = (def.rpm ? 60 / def.rpm : G.zapper.interval) / ((mods && mods.fireRate) || 1);
    slot.mag--;
    this._zap(ctx, up, def);
    return true;
  }

  _zap(ctx, up, def) {
    const g = this.game, Z = G.zapper;
    const ads = !!ctx.ads;
    const range = (def.range && def.range[ads ? 1 : 0]) || (up ? Z.rangeUp : Z.range)[ads ? 1 : 0];
    const cone = (def.cone && def.cone[ads ? 1 : 0]) || (def.spread && def.spread[ads ? 1 : 0]) || Z.cone[ads ? 1 : 0];
    const chain = def.chain ?? (up ? Z.chainUp : Z.chain);
    const muzzle = _c.copy(ctx.muzzle);
    const first = this._pickTarget(ctx.origin, ctx.dir, cone * DEG, range);
    const victims = [];
    if (first) {
      victims.push(first);
      let prev = first;
      const hit = new Set([first]);
      for (let i = 0; i < chain; i++) {
        const next = this._nearest(prev.pos, def.chainR ?? Z.hop, hit, true);
        if (!next) break;
        hit.add(next);
        victims.push(next);
        prev = next;
      }
    }
    // visuals: concentric ultrasonic rings along the ray, then along every jump
    const cols = up ? ['#FF5FA2', '#FFE14D', '#5FE3FF', '#9CFF57'] : ['#7FE7FF', '#D64FD6', '#F4E03A'];
    let end;
    if (first) end = this._chest(first, new THREE.Vector3());
    else {
      const col = g.level && g.level.col;
      const hit = col && col.raycast(ctx.origin, ctx.dir, range);
      end = hit ? hit.point : ctx.origin.clone().addScaledVector(ctx.dir, range);
    }
    this._ringTrail(muzzle, end, cols, 0, up ? 9 : 7, 0.14);
    g.fx?.muzzle?.(muzzle, _d.subVectors(end, muzzle).normalize(), cols[0]);
    g.fx?.flashLight?.(muzzle, cols[0], 6, 0.1);
    if (!first) g.fx?.burst?.(end, { shape: 'static', count: 8, size: 0.06, life: 0.4 });
    let delay = 0.07;
    for (let i = 0; i < victims.length; i++) {
      const z = victims[i];
      this._claimed.add(z);
      if (i > 0) {
        const a = this._chest(victims[i - 1], new THREE.Vector3()), b = this._chest(z, new THREE.Vector3());
        this._ringTrail(a, b, cols, delay - 0.06, 5, 0.1);
      }
      this._later(delay, () => this._zapHit(z, up, def));
      delay += 0.075;
    }
    this._lastZap = { t: g.time.now, first: first ? first.id ?? true : null, victims: victims.length, round: this._round() };
    this._recoil(0.018, 'zapper');
    this._emit('weapon:fire', { weaponId: 'zapper', upgraded: up });
  }

  _zapHit(z, up, def) {
    const g = this.game, Z = G.zapper;
    if (!z || z.state === 'dying' || z.dead || !(z.hp > 0)) return;
    this._chest(z, _p);
    const point = _p.clone();
    g.fx?.burst?.(point, { shape: 'static', count: 10, size: 0.08, life: 0.35 });
    g.fx?.burst?.(point, { shape: 'spark', count: 6, size: 0.04, speed: 4, life: 0.25, colors: up ? ['#FF5FA2', '#FFE14D', '#5FE3FF'] : ['#7FE7FF', '#FFFFFF'] });
    if (this._isBoss(z)) {
      this._damage(z, def.bossDmg ?? Z.boss, 'zapper', 'zapper', { upgraded: up, point });
      return;
    }
    const killUpTo = def.killUpTo ?? (up ? Z.killUpToUp : Z.killUpTo);
    const instant = this._round() <= killUpTo;
    const P = this._doom(z, () => (instant
      ? this._kill(z, 'zapper', 'zapper', { upgraded: up, point })
      : this._damage(z, def.dmg ?? (up ? Z.dmgUp : Z.dmg), 'zapper', 'zapper', { upgraded: up, point })));
    if (P) {
      const gag = GAGS[Math.floor(Math.random() * GAGS.length)];
      this._gag(z, gag, up, P);
      const pulse = def.stunPulse || (up ? { r: Z.pulseR, s: Z.pulseStun } : null);
      if (pulse) this._stunPulse(z.pos, pulse.r, pulse.s, z);
    } else {
      this._stun(z, def.stun ?? Z.stun);
      z.animator?.kick?.(1);
      this._flashLive(z);
    }
  }

  // The zombie closest to the aim ray inside the cone (half-angle): the angle is measured to the nearest point of
  // its body axis (feet to head), so aiming at the head, the chest or just past the shoulder all count. A direct
  // hit (zombies.raycast) always wins. Line of sight from the player's eyes.
  _pickTarget(origin, dir, cone, range) {
    const g = this.game, p = g.player;
    let best = null, bestScore = Infinity;
    const eye = _d.copy(p ? p.pos : origin);
    if (p) eye.y += 1.35;
    const zm = g.zombies;
    const direct = zm && zm.raycast ? zm.raycast(origin, dir, range + 4) : null;
    for (const z of this._zombies()) {
      if (!this._alive(z)) continue;
      const hgt = z.height || 1.6;
      // closest point of the body axis to the ray (segment vs ray, clamped)
      const y0 = z.pos.y + 0.25, y1 = z.pos.y + hgt * 0.95;
      _a.set(z.pos.x - origin.x, 0, z.pos.z - origin.z);
      const tRay = (_a.x * dir.x + _a.z * dir.z) / Math.max(1e-6, dir.x * dir.x + dir.z * dir.z);
      const rayY = origin.y + dir.y * tRay;
      _p.set(z.pos.x, Math.min(y1, Math.max(y0, rayY)), z.pos.z);
      _a.subVectors(_p, origin);
      const d = _a.length();
      if (d < 1e-3) continue;
      if (p && Math.hypot(z.pos.x - p.pos.x, z.pos.z - p.pos.z) > range) continue;
      const cos = _a.dot(dir) / d;
      if (cos <= 0) continue;
      const ang = Math.acos(Math.min(1, cos)) - Math.atan2((z.radius || 0.4) * 0.9, d);
      const isDirect = !!(direct && direct.z === z);
      if (ang > cone && !isDirect) continue;
      if (!this._los(eye, this._chest(z, _e)) && !this._los(eye, _e.set(z.pos.x, y1, z.pos.z))) continue;
      const score = isDirect ? -1 : ang;
      if (score < bestScore) { bestScore = score; best = z; }
    }
    return best;
  }

  _nearest(pos, r, exclude, los = false) {
    let best = null, bd = r;
    for (const z of this._zombies()) {
      if (exclude.has(z) || !this._alive(z)) continue;
      const d = z.pos.distanceTo(pos);
      if (d > bd) continue;
      if (los && !this._los(_a.copy(pos).setY(pos.y + 1.0), _b.copy(z.pos).setY(z.pos.y + 1.0))) continue;
      bd = d;
      best = z;
    }
    return best;
  }

  _ringTrail(from, to, cols, delay, n, dur) {
    const len = from.distanceTo(to);
    if (len < 0.05) return;
    _d.subVectors(to, from).normalize();
    _q.setFromUnitVectors(_zAxis, _d);
    for (let i = 0; i < n; i++) {
      const it = this.pools.rings.spawn();
      it.from.copy(from);
      it.to.copy(to);
      it.q.copy(_q);
      it.t = 0;
      it.delay = delay + i * (dur / n) * 0.9;
      it.dur = dur + len * 0.004;
      it.s0 = 0.06 + i * 0.012;
      it.s1 = 0.3 + (i % 3) * 0.07;
      it.base.set(cols[i % cols.length]).multiplyScalar(1.6);
      it.flat = false;
      it.kind = 'trail';
    }
  }

  // An expanding flat ring on the floor (Channel Surfer stun pulse, tele implosion, splash).
  _floorRing(pos, r, color, dur = 0.45, bold = true, gain = 1.4) {
    const it = (bold ? this.pools.bold : this.pools.rings).spawn();
    it.from.copy(pos).setY(pos.y + 0.06);
    it.to.copy(it.from);
    it.q.setFromAxisAngle(_b.set(1, 0, 0), -Math.PI / 2);
    it.t = 0;
    it.delay = 0;
    it.dur = dur;
    it.s0 = r * 0.15;
    it.s1 = r;
    it.base.set(color).multiplyScalar(gain);
    it.kind = 'grow';
  }

  _stunPulse(pos, r, s, except) {
    this._floorRing(pos, r, '#7FE7FF', 0.4, false, 0.75);
    this._floorRing(pos, r * 0.7, '#FF5FA2', 0.3, false, 0.6);
    this._stunRadius(pos, r, s, except);
  }

  _later(delay, fn) {
    let t = 0;
    this._actors.push({ update: (dt) => { t += dt; if (t >= delay) { fn(); return false; } return true; } });
  }

  // A surviving zombie flickers static for a moment (late-round zapper hit).
  _flashLive(z) {
    const meshes = [];
    z.group.traverse((o) => { if (o.isMesh && o.visible) meshes.push([o, o.material]); });
    const R = this.res;
    let t = 0;
    const restore = () => { for (const [o, m] of meshes) if (o.material === R.fx.static || o.material === R.fx.bars) o.material = m; };
    this._actors.push({
      update: (dt) => {
        t += dt;
        const mat = t < 0.06 ? R.fx.static : t < 0.12 ? R.fx.bars : null;
        if (!mat) { restore(); return false; }
        for (const [o] of meshes) if (!this._iced(o)) o.material = mat;
        return true;
      },
      dispose: restore,
    });
  }

  _iced(mesh) {
    return mesh.material === this.res.mIce;
  }

  // ------------------------------------------------------------------------------------------ corpses (clones)
  // A frozen clone of the zombie's current pose: pivot (world pos + yaw) -> tilt -> body. The original is hidden.
  _corpse(z) {
    const g = this.game;
    const src = z.group;
    if (!src) return null;
    src.updateMatrixWorld(true);
    let body;
    try {
      const vis = src.visible;
      src.visible = true;
      body = safeClone(src, true);
      src.visible = vis;
    } catch (err) {
      body = new THREE.Group();
      body.add(geo.mesh(geo.capsule(0.3, (z.height || 1.6) - 0.6), this.res.mGel, { pos: [0, (z.height || 1.6) / 2, 0] }));
    }
    const pivot = new THREE.Group();
    pivot.name = 'wonder:corpse';
    src.matrixWorld.decompose(pivot.position, pivot.quaternion, _s);
    const tilt = new THREE.Group();
    pivot.add(tilt);
    tilt.add(body);
    body.position.set(0, 0, 0);
    body.quaternion.identity();
    body.scale.copy(_s);
    const meshes = [];
    body.traverse((o) => {
      if (o.isMesh) {
        meshes.push(o);
        o.frustumCulled = false;
        o.userData.__wmat = o.material;
      }
    });
    g.scene.add(pivot);
    this._hide(z);
    const h = z.height || 1.6;
    const blob = g.fx?.blob?.(tilt, (z.radius || 0.4) * 1.1) || null;
    const pos0y = pivot.position.y;
    return {
      pivot, tilt, body, meshes, h, blob,
      setMat(mat) { for (const o of meshes) o.material = mat || o.userData.__wmat; },
      // the contact blob follows the body while it is visible and not shrunk away
      sync() {
        if (!blob) return;
        const s = Math.min(tilt.scale.x, tilt.scale.y, tilt.scale.z > 0.05 ? 1 : tilt.scale.x) * pivot.scale.x;
        blob.visible = pivot.visible && s > 0.25 && pivot.position.y - pos0y < 0.8;
      },
      dispose() { pivot.removeFromParent(); if (blob) blob.remove(); },
    };
  }

  _hide(z) {
    if (!z.group) return;
    if (!this._hidden.has(z)) this._hidden.set(z, { group: z.group, t: 0 });
    z.group.visible = false;
  }

  _unhide(z) {
    const h = this._hidden.get(z);
    if (h) h.group.visible = true;
    else if (z.group) z.group.visible = true;
    this._hidden.delete(z);
  }

  _updateHidden(dt) {
    const alive = this._zombies();
    for (const [z, h] of this._hidden) {
      h.t += dt;
      const grp = h.group;
      const dead = !(z.hp > 0) || z.state === 'dying' || z.state === 'dead';
      let reused = false;
      for (const o of alive) if (o !== z && o.group === grp) { reused = true; break; }
      if (grp.parent && dead && !reused && h.t < 4) grp.visible = false;
      else {
        grp.visible = true;
        this._hidden.delete(z);
      }
    }
  }

  _updateActors(dt) {
    const A = this._actors;
    let n = 0;
    for (let i = 0; i < A.length; i++) {
      const a = A[i];
      let alive = false;
      try { alive = a.update(dt); } catch (err) { console.warn('[wonder] effect failed', err); alive = false; }
      if (alive) A[n++] = a;
      else a.dispose?.();
    }
    A.length = n;
  }

  // Away-from-player direction on the floor plane.
  _away(pos, out) {
    const p = this.game.player;
    out.set(pos.x - (p ? p.pos.x : 0), 0, pos.z - (p ? p.pos.z : 0));
    if (out.lengthSq() < 1e-4) out.set(0, 0, 1);
    return out.normalize();
  }

  // ------------------------------------------------------------------------------------------ channel gags
  // The victim flashes 2 frames of static and 2 of color bars, then one of the five channel gags (GDD §9.4).
  _gag(z, gag, up = false, pre = null) {
    const P = pre && pre !== true ? pre : this._corpse(z);
    if (!P) return;
    const g = this.game, R = this.res;
    const pos = P.pivot.position.clone();
    const away = this._away(pos, new THREE.Vector3());
    const INTRO = 0.1;
    const intro = (t) => {
      if (t < 0.05) P.setMat(R.fx.static);
      else if (t < INTRO) P.setMat(R.fx.bars);
      else if (!P._restored) { P._restored = true; P.setMat(null); }
    };
    this._emit('wonder:gag', { z, gag });
    let t = 0, cued = false;
    const cue = () => { if (!cued && t >= INTRO) { cued = true; this._play(`gag_${gag}`, { pos }); } };
    const S = { t: 0 };
    const upd = {
      cartoon: (dt) => this._gagCartoon(P, t, S),
      western: (dt) => this._gagWestern(P, t, S, pos, away),
      cooking: (dt) => this._gagCooking(P, t, S, pos),
      nature: (dt) => this._gagNature(P, t, S, pos, away, dt),
      signoff: (dt) => this._gagSignoff(P, t, S, pos),
    }[gag];
    this._actors.push({
      update: (dt) => {
        t += dt;
        if (gag !== 'signoff' || t < INTRO) intro(t);
        cue();
        const alive = upd(dt);
        P.sync();
        return alive;
      },
      dispose: () => { P.dispose(); S.dispose?.(); },
    });
  }

  // CARTOON: paper-flat in 0.15 s, twists like a cardboard cutout (so the thin profile reads from the front), tips
  // over backward with a flutter, slaps the floor, poofs.
  _gagCartoon(P, t, S) {
    const g = this.game;
    const k1 = seg(t, 0.1, 0.25);
    const sz = lerp(1, 0.02, E.outCubic(k1));
    const bulge = 1 + Math.sin(k1 * Math.PI) * 0.12;
    P.tilt.scale.set(bulge, 1 / bulge, sz);
    if (k1 > 0 && !S.flat) {
      S.flat = true;
      _a.set(0, P.h * 0.55, 0).applyQuaternion(P.pivot.quaternion).add(P.pivot.position);
      g.fx?.burst?.(_a, { shape: 'puff', count: 4, size: 0.12, speed: 1.4, life: 0.35, colors: ['#FFFFFF', '#F4F1E8'] });
    }
    // the cutout swings edge-on (you see it is paper-thin) and flaps back
    const k2 = seg(t, 0.25, 0.58);
    P.tilt.rotation.y = Math.sin(k2 * Math.PI) * 1.25 + Math.sin(k2 * TAU * 2) * 0.18 * (1 - k2);
    const k3 = seg(t, 0.58, 0.9);
    let ang = (Math.PI / 2) * E.inQuad(k3);
    P.tilt.rotation.z = Math.sin(k3 * Math.PI * 3) * 0.12 * (1 - k3);
    const k4 = seg(t, 0.9, 1.08);
    if (k4 > 0) ang = Math.PI / 2 - Math.sin(k4 * Math.PI) * 0.16;
    P.tilt.rotation.x = ang;
    if (t >= 0.9 && !S.slap) {
      S.slap = true;
      _a.set(0, 0, P.h * 0.5).applyQuaternion(P.pivot.quaternion).add(P.pivot.position);
      g.fx?.burst?.(_a, { shape: 'puff', count: 8, size: 0.2, speed: 2.4, colors: ['#F4F1E8', '#E6DCCB'], life: 0.5 });
      this._play('telly_clonk', { pos: _a, vol: 0.7, rate: 0.7 });
    }
    const k5 = seg(t, 1.12, 1.3);
    if (k5 > 0) {
      const s = 1 - E.inBack(k5);
      P.pivot.scale.setScalar(Math.max(0.001, s));
      if (!S.poof) {
        S.poof = true;
        _a.set(0, 0.1, P.h * 0.5).applyQuaternion(P.pivot.quaternion).add(P.pivot.position);
        g.fx?.burst?.(_a, { shape: 'confetti', count: 16, colors: ['#F4F1E8', '#FFFFFF', '#E8E1D0'], speed: 3 });
        g.fx?.burst?.(_a, { shape: 'puff', count: 6, size: 0.18 });
      }
    }
    return t < 1.3;
  }

  // WESTERN: shrinks into a tumbleweed of tangled tubes that rolls 4 m, hopping, and poofs.
  _gagWestern(P, t, S, pos, away) {
    const g = this.game, R = this.res;
    if (!S.weed) {
      const weed = new THREE.Mesh(R.tumble, R.mTumble);
      weed.castShadow = true;
      const holder = new THREE.Group();
      holder.add(weed);
      holder.position.copy(pos);
      holder.scale.setScalar(0.001);
      g.scene.add(holder);
      const yaw = (Math.random() - 0.5) * 0.9;
      S.dir = away.clone().applyAxisAngle(_up, yaw);
      S.dist = this._clearDist(pos, S.dir, 4, 0.45);
      S.weed = weed;
      S.holder = holder;
      S.blob = g.fx?.blob?.(holder, 0.32) || null;
      S.axis = new THREE.Vector3().crossVectors(_up, S.dir).normalize();
      S.bounce = 0;
      S.dispose = () => { holder.removeFromParent(); S.blob?.remove(); };
    }
    const k1 = seg(t, 0.1, 0.35);
    P.tilt.scale.setScalar(Math.max(0.001, 1 - E.inBack(k1, 1.2) * 0.999));
    P.tilt.rotation.y = k1 * TAU;
    const grow = E.outBack(seg(t, 0.18, 0.42));
    const k2 = seg(t, 0.35, 1.25);
    const d = S.dist * E.outQuad(k2);
    const hops = Math.abs(Math.sin(k2 * Math.PI * 3)) * 0.5 * (1 - k2 * 0.7);
    S.holder.position.copy(pos).addScaledVector(S.dir, d);
    S.holder.position.y = pos.y + 0.36 + hops;
    const b = Math.floor(k2 * 3);
    if (k2 > 0 && b > S.bounce && b < 3) {
      S.bounce = b;
      g.fx?.burst?.(_a.copy(S.holder.position).setY(pos.y + 0.05), { shape: 'puff', count: 4, size: 0.12, colors: ['#E0C48E', '#CDAE78'], life: 0.5 });
    }
    S.weed.quaternion.setFromAxisAngle(S.axis, d / 0.34 + t * 2);
    const k3 = seg(t, 1.25, 1.42);
    S.holder.scale.setScalar(Math.max(0.001, grow * (1 - E.inBack(k3))));
    if (k3 > 0 && !S.poof) {
      S.poof = true;
      g.fx?.burst?.(S.holder.position, { shape: 'puff', count: 10, size: 0.2, colors: ['#E0C48E', '#F4E3BF'], speed: 2.2 });
      g.fx?.burst?.(S.holder.position, { shape: 'confetti', count: 10, colors: ['#C79A55', '#8A6334', '#E0C48E'], speed: 3 });
    }
    return t < 1.45;
  }

  // COOKING: a jiggly green head-shaped gelatin mold (with a cherry) that wobbles and melts.
  _gagCooking(P, t, S, pos) {
    const g = this.game, R = this.res;
    if (!S.mold) {
      const mold = new THREE.Group();
      const jelly = new THREE.Mesh(R.gel, R.mGel);
      jelly.castShadow = true;
      mold.add(jelly);
      for (const s of [-1, 1]) mold.add(geo.mesh(geo.sphere(0.055, 12, 8), R.mGelEye, { pos: [s * 0.1, 0.4, -0.235], scale: [1, 1.2, 0.5] }));
      mold.add(geo.mesh(geo.torus(0.05, 0.016, 6, 14), R.mGelEye, { pos: [0, 0.27, -0.27], rot: [0.25, 0, 0], scale: [1, 0.7, 1] }));
      mold.add(geo.mesh(geo.sphere(0.05, 14, 10), R.mCherry, { pos: [0, 0.655, 0] }));
      mold.add(geo.mesh(geo.cylinder(0.005, 0.005, 0.08, 5), R.mInk, { pos: [0.015, 0.72, 0], rot: [0, 0, -0.4] }));
      const plate = geo.mesh(geo.cylinder(0.42, 0.36, 0.03, 28), R.mPlate, { pos: [0, 0.015, 0] });
      const holder = new THREE.Group();
      holder.add(plate);
      const wob = new THREE.Group();
      wob.position.y = 0.03;
      wob.add(mold);
      holder.add(wob);
      holder.position.copy(pos);
      holder.quaternion.copy(P.pivot.quaternion);
      holder.scale.setScalar(0.001);
      g.scene.add(holder);
      S.mold = mold;
      S.holder = holder;
      S.wob = wob;
      S.plate = plate;
      S.blob = g.fx?.blob?.(holder, 0.45) || null;
      S.dispose = () => { holder.removeFromParent(); S.blob?.remove(); };
    }
    const k1 = seg(t, 0.1, 0.28);
    P.tilt.scale.set(1 + k1 * 0.3, Math.max(0.001, 1 - E.inBack(k1, 1.2)), 1 + k1 * 0.3);
    if (k1 >= 1) P.pivot.visible = false;
    const pop = E.outElastic(seg(t, 0.16, 0.7));
    S.holder.scale.setScalar(Math.max(0.001, pop));
    const tw = Math.max(0, t - 0.2);
    let sy = 1 + 0.2 * Math.sin(tw * 19) * Math.exp(-tw * 2.4);
    const k3 = seg(t, 0.95, 1.32);
    let sxz = 1 / Math.sqrt(sy);
    if (k3 > 0) {
      sy *= lerp(1, 0.07, E.inQuad(k3));
      sxz *= lerp(1, 1.75, E.outQuad(k3));
      if (!S.melt) {
        S.melt = true;
        this._play('jelly_bwoing', { pos, vol: 0.8, rate: 0.8 });
      }
      if (Math.random() < 0.3) g.fx?.burst?.(_a.copy(pos).setY(pos.y + 0.1), { shape: 'goo', count: 1, colors: ['#4FE06A', '#8CFF9A'], speed: 1.5, size: 0.06 });
    }
    S.wob.scale.set(sxz, sy, sxz);
    S.wob.rotation.z = Math.sin(tw * 13) * 0.12 * Math.exp(-tw * 2);
    S.wob.rotation.x = Math.cos(tw * 11) * 0.08 * Math.exp(-tw * 2);
    if (t > 1.32 && !S.splat) {
      S.splat = true;
      g.fx?.burst?.(_a.copy(pos).setY(pos.y + 0.1), { shape: 'goo', count: 10, colors: ['#4FE06A', '#8CFF9A'], speed: 2.5 });
    }
    const k4 = seg(t, 1.32, 1.5);
    if (k4 > 0) S.holder.scale.setScalar(Math.max(0.001, 1 - E.inQuad(k4)));
    return t < 1.5;
  }

  _buildBunny() {
    const R = this.res;
    const b = new THREE.Group();
    const body = new THREE.Group();
    b.add(body);
    const m = (gm, mat, o) => { const x = geo.mesh(gm, mat, o); body.add(x); return x; };
    m(geo.sphere(0.2, 18, 14), R.mBunny, { pos: [0, 0.2, 0.02], scale: [1, 0.88, 1.12] });
    m(geo.sphere(0.15, 18, 14), R.mBunny, { pos: [0, 0.4, -0.15] });
    m(geo.sphere(0.075, 12, 10), R.mBunny, { pos: [0, 0.22, 0.24] });
    for (const s of [-1, 1]) {
      m(geo.sphere(0.075, 12, 10), R.mBunny, { pos: [s * 0.12, 0.05, -0.08], scale: [0.8, 0.55, 1.3] });
      m(geo.sphere(0.026, 10, 8), R.mInk, { pos: [s * 0.065, 0.44, -0.28] });
      m(geo.sphere(0.036, 10, 8), R.mPink, { pos: [s * 0.085, 0.36, -0.27], scale: [1, 0.6, 0.4] });
      const ear = new THREE.Group();
      ear.position.set(s * 0.06, 0.52, -0.13);
      ear.rotation.z = -s * 0.2;
      ear.name = s < 0 ? 'earL' : 'earR';
      ear.add(geo.mesh(geo.capsule(0.045, 0.17), R.mBunny, { pos: [0, 0.12, 0] }));
      ear.add(geo.mesh(geo.capsule(0.022, 0.13), R.mPink, { pos: [0, 0.12, -0.03] }));
      body.add(ear);
    }
    m(geo.sphere(0.022, 10, 8), R.mPink, { pos: [0, 0.39, -0.3] });
    return b;
  }

  // NATURE: a fluffy bunny that hops away 3 times and poofs into sparkles.
  _gagNature(P, t, S, pos, away) {
    const g = this.game;
    if (!S.bunny) {
      const bunny = this._buildBunny();
      bunny.position.copy(pos);
      bunny.rotation.y = Math.atan2(-away.x, -away.z);
      bunny.scale.setScalar(0.001);
      g.scene.add(bunny);
      S.bunny = bunny;
      S.body = bunny.children[0];
      S.ears = [bunny.getObjectByName('earL'), bunny.getObjectByName('earR')];
      S.dir = away.clone();
      S.dist = this._clearDist(pos, S.dir, 2.7, 0.4);
      S.blob = g.fx?.blob?.(bunny, 0.25) || null;
      S.dispose = () => { bunny.removeFromParent(); S.blob?.remove(); };
    }
    const k1 = seg(t, 0.1, 0.22);
    P.tilt.scale.setScalar(Math.max(0.001, 1 - E.inBack(k1, 1.3)));
    if (k1 > 0 && !S.poof1) {
      S.poof1 = true;
      g.fx?.burst?.(_a.copy(pos).setY(pos.y + 0.8), { shape: 'puff', count: 10, size: 0.22, colors: ['#FFFFFF', '#F4F1E8'], speed: 2 });
    }
    if (k1 >= 1) P.pivot.visible = false;
    const pop = E.outBack(seg(t, 0.14, 0.34));
    const HOP0 = 0.34, HOP = 0.3;
    const hk = (t - HOP0) / HOP;
    const i = Math.floor(hk);
    let y = 0, sq = 1, d = 0;
    if (hk >= 0 && i < 3) {
      const f = hk - i;
      y = Math.sin(f * Math.PI) * 0.42;
      sq = f < 0.15 ? 1 - (0.15 - f) * 2 : f > 0.85 ? 1 - (f - 0.85) * 2 : 1 + Math.sin(f * Math.PI) * 0.18;
      d = ((i + E.inOutQuad(f)) / 3) * S.dist;
      if (i > (S.lastHop ?? -1)) {
        S.lastHop = i;
        if (i > 0) g.fx?.burst?.(_a.copy(S.bunny.position).setY(pos.y + 0.03), { shape: 'puff', count: 3, size: 0.08, life: 0.4 });
      }
    } else if (hk >= 3) d = S.dist;
    S.bunny.position.copy(pos).addScaledVector(S.dir, d);
    S.bunny.position.y = pos.y + y;
    S.body.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));
    const earLag = hk >= 0 && i < 3 ? Math.cos((hk - i) * Math.PI) * 0.5 : 0;
    for (const e of S.ears) if (e) e.rotation.x = earLag;
    const k3 = seg(t, 1.28, 1.48);
    S.bunny.scale.setScalar(Math.max(0.001, pop * (1 - E.inBack(k3))));
    if (k3 > 0 && !S.poof2) {
      S.poof2 = true;
      _a.copy(S.bunny.position).setY(S.bunny.position.y + 0.3);
      g.fx?.burst?.(_a, { shape: 'star', count: 10, speed: 2.8, colors: ['#FFF3B0', '#FFC23A', '#FFFFFF'] });
      g.fx?.burst?.(_a, { shape: 'confetti', count: 12, colors: ['#FF9EC4', '#BFE8FF', '#FFF3B0', '#C8F7C5'], speed: 2.5 });
    }
    return t < 1.5;
  }

  // SIGN-OFF: squashes into a horizontal white line, then a dot, then gone (a CRT switching off).
  _gagSignoff(P, t, S, pos) {
    const g = this.game, R = this.res;
    if (!S.init) {
      S.init = true;
      const mid = P.h * 0.5;
      P.tilt.position.y = mid;
      P.body.position.y = -mid;
      S.dot = new THREE.Mesh(R.dot, R.mWhite);
      S.dot.position.copy(pos).setY(pos.y + mid);
      S.dot.scale.setScalar(0.001);
      g.scene.add(S.dot);
      for (const o of P.meshes) o.castShadow = false;   // a glowing white line casts no shadow (and no stale one)
      S.dispose = () => S.dot.removeFromParent();
    }
    if (t < 0.05) P.setMat(R.fx.static);
    else if (t < 0.1) P.setMat(R.fx.bars);
    else P.setMat(R.mWhiteBody);
    const k1 = seg(t, 0.1, 0.34);
    const k2 = seg(t, 0.34, 0.56);
    const sy = lerp(1, 0.012, E.inCubic(k1));
    const sx = k2 > 0 ? lerp(1.9, 0.02, E.inCubic(k2)) : lerp(1, 1.9, E.outQuad(k1));
    const sz = k2 > 0 ? lerp(1, 0.02, E.inCubic(k2)) : 1;
    P.tilt.scale.set(sx, Math.max(0.001, sy), sz);
    if (k2 >= 1) P.pivot.visible = false;
    const k3 = seg(t, 0.46, 1.0);
    const ds = k3 <= 0 ? 0 : k3 < 0.2 ? E.outBack(k3 / 0.2) : 1 - E.inQuad((k3 - 0.2) / 0.8);
    S.dot.scale.setScalar(Math.max(0.001, ds * 1.1));
    if (k2 >= 1 && !S.flash) {
      S.flash = true;
      g.fx?.flashLight?.(S.dot.position, '#FFFFFF', 5, 0.2);
    }
    return t < 1.02;
  }

  // ------------------------------------------------------------------------------------------ BOOM MIC
  _boomFire(ctx, st, slot) {
    const g = this.game;
    this._micTip.copy(ctx.muzzle);
    if (this.recording) {
      st.ctx = ctx;
      if (!ctx.triggerDown || ctx.triggerReleased || st.rec >= ((ctx.def && ctx.def.record && ctx.def.record.max) ?? G.boom.rec)) {
        this._playback(ctx, st);
        return true;
      }
      return false;
    }
    if (st.recover > 0) return false;
    if (!ctx.triggerDown) return false;
    if (!ctx.triggerPressed) return false;
    if (this._empty('boom_mic', ctx, slot)) return false;
    this.recording = true;
    this.charge = 0;
    st.rec = 0;
    st.ctx = ctx;
    st.up = !!ctx.upgraded;
    st.squigT = 0;
    try { this._recLoop = g.audio?.loop?.('wpn_boom_record', {}) || null; } catch (err) { this._recLoop = null; }
    return false;
  }

  _updateRecording(dt, st) {
    const B = G.boom, ctx = st.ctx;
    if (!ctx || dt <= 0) return;
    const RC = (ctx.def && ctx.def.record) || {};
    const maxT = RC.max ?? B.rec;
    st.rec += dt;
    const zs = this._inCone(ctx.origin, ctx.dir, RC.range ?? B.recRange, ((RC.cone ?? B.recCone) / 2) * DEG, this._recList || (this._recList = []));
    let count = 0;
    const now = new Set(zs);
    for (const z of zs) count += this._isBoss(z) ? RC.bossCounts ?? B.bossCount : 1;
    const rate = ((RC.chargeBase ?? B.base) + (RC.chargePerZombie ?? B.per) * count) * (RC.rate ?? (st.up ? 2 : 1));
    this.charge = Math.min(RC.chargeMax ?? B.max, this.charge + rate * dt);
    // slow everyone in the cone to 35 %; restore the ones that left
    for (const z of zs) this._slow(z, 'rec', RC.slow ?? B.slow);
    for (const z of [...this._status.keys()]) {
      const s = this._status.get(z);
      if (s && s.slows && s.slows.rec && !now.has(z)) this._unslow(z, 'rec');
    }
    // sound squiggles fly from their mouths into the mic
    st.squigT -= dt;
    if (st.squigT <= 0 && zs.length) {
      st.squigT = 0.07;
      const z = zs[Math.floor(Math.random() * zs.length)];
      this._squiggle(z);
    }
    if (st.rec >= maxT) this._playback(ctx, st);
  }

  _inCone(origin, dir, range, half, out) {
    out.length = 0;
    const cosH = Math.cos(half);
    const p = this.game.player;
    const eye = _d.copy(p ? p.pos : origin);
    if (p) eye.y += 1.3;
    for (const z of this._zombies()) {
      if (!this._alive(z)) continue;
      this._chest(z, _p);
      _a.subVectors(_p, eye);
      const d = _a.length();
      if (d > range || d < 1e-3) continue;
      _b.copy(dir).setY(dir.y * 0.35).normalize();
      _a.divideScalar(d);
      const cos = _a.dot(_b);
      const pad = Math.atan2(z.radius || 0.4, d);
      if (Math.acos(Math.min(1, cos)) > half + pad && d > 1.4) continue;
      if (!this._los(eye, _p)) continue;
      out.push(z);
    }
    return out;
  }

  _squiggle(z) {
    const it = this.pools.squig.spawn();
    this._headPos(z, it.from);
    const face = z.yaw !== undefined ? _a.set(-Math.sin(z.yaw), 0, -Math.cos(z.yaw)) : _a.set(0, 0, 0);
    it.from.addScaledVector(face, 0.2).y -= 0.08;
    it.t = 0;
    it.dur = 0.34 + Math.random() * 0.14;
    it.seed = Math.random() * TAU;
    it.base.set(['#7FE7FF', '#FF5FA2', '#FFE14D', '#9CFF57'][Math.floor(Math.random() * 4)]).multiplyScalar(1.25);
  }

  _stopRecording(keep) {
    if (this._recLoop) {
      try { this._recLoop.stop?.(0.08); } catch (err) { /* ignore */ }
      this._recLoop = null;
    }
    if (this.recording && !keep) this.charge = 0;
    this.recording = false;
    for (const z of [...this._status.keys()]) this._unslow(z, 'rec');
  }

  _playback(ctx, st) {
    const g = this.game, B = G.boom;
    const slot = ctx.slot;
    const charge = this.charge;
    const up = !!st.up;
    this._stopRecording(true);
    if (slot) slot.mag = Math.max(0, slot.mag - 1);
    st.recover = B.recover;
    st.playT = clamp01(charge / 10);
    this.charge = 0;
    const origin = ctx.origin;
    const fwd = new THREE.Vector3().copy(ctx.dir).setY(0);
    if (fwd.lengthSq() < 1e-4) fwd.set(0, 0, -1);
    fwd.normalize();
    const cones = [[fwd, charge]];
    if (up) {
      const back = fwd.clone().negate();
      const left = new THREE.Vector3(-fwd.z, 0, fwd.x);
      const right = left.clone().negate();
      for (const d of [back, left, right]) cones.push([d, charge / 2]);
    }
    const killUpTo = ctx.def?.killUpTo ?? (up ? B.killUpToUp : B.killUpTo);
    const PB = (ctx.def && ctx.def.playback) || {};
    const done = new Set();
    let victims = 0;
    for (const [dir, ch] of cones) {
      const full = dir === fwd;
      const aim = full ? ctx.dir : dir;
      this._shockwave(this._micTip, dir, ch, full);
      const list = this._inCone(origin, aim, B.range, (B.cone / 2) * DEG, []);
      for (const z of list) {
        if (done.has(z)) continue;
        done.add(z);
        if (this._isBoss(z)) {
          this._damage(z, (PB.bossPerCharge ?? B.boss) * ch, 'boom_mic', 'boom_mic', { upgraded: up });
          continue;
        }
        if (ch >= (PB.killCharge ?? B.killAt)) {
          const instant = this._round() <= killUpTo;
          const P = this._doom(z, () => (instant
            ? this._kill(z, 'boom_mic', 'boom_mic', { upgraded: up, dir })
            : this._damage(z, (PB.dmgAfter ?? B.late) * (ch / 10), 'boom_mic', 'boom_mic', { upgraded: up, dir })));
          if (P) this._tumble(z, dir, victims++, P);
          else this._knock(z, dir, (PB.knock ?? B.knock) * 0.5, PB.stun ?? B.weakStun);
        } else {
          const P = this._doom(z, () => this._damage(z, PB.weakDmg ?? B.weak, 'boom_mic', 'boom_mic', { upgraded: up, dir }));
          if (P) this._tumble(z, dir, victims++, P);
          else this._knock(z, dir, PB.knock ?? B.knock, PB.stun ?? B.weakStun);
        }
      }
    }
    this._play('wpn_boom_playback', { upgraded: up });
    if (up) this._play('wpn_upgraded_sparkle');
    this._recoil(0.035, 'boom_mic');
    g.cam?.shake?.(0.18 + charge * 0.02, 0.35);
    g.fx?.flashLight?.(this._micTip, '#FF5FA2', 5 + charge, 0.15);
    this._emit('weapon:fire', { weaponId: 'boom_mic', upgraded: up });
  }

  // Translucent sound rings expanding along a 50° cone.
  _shockwave(from, dir, charge, full) {
    const n = full ? 7 : 4;
    const B = G.boom;
    const len = this._clearDist(from, dir, B.range, 0.2) + 0.5;
    _q.setFromUnitVectors(_zAxis, _d.copy(dir).normalize());
    const cols = ['#FF5FA2', '#FFE14D', '#7FE7FF', '#FFFFFF'];
    const strength = 0.6 + clamp01(charge / 10) * 0.9;
    for (let i = 0; i < n; i++) {
      const it = this.pools.bold.spawn();
      it.from.copy(from);
      it.to.copy(from).addScaledVector(dir, len);
      it.q.copy(_q);
      it.t = 0;
      it.delay = i * 0.05;
      it.dur = 0.5;
      it.s0 = 0.18;
      it.s1 = Math.tan((B.cone / 2) * DEG) * len * (full ? 1 : 0.8);
      it.base.set(cols[i % cols.length]).multiplyScalar(0.42 * strength * (full ? 1 : 0.7));
      it.kind = 'cone';
    }
  }

  _knock(z, dir, dist, stun) {
    this._stun(z, stun);
    z.animator?.kick?.(1.2);
    const col = this.game.level && this.game.level.col;
    if (!col || !z.pos) return;
    let t = 0;
    const d = dir.clone().setY(0).normalize();
    this._actors.push({
      update: (dt) => {
        if (!this._alive(z) && z.state !== 'dying') return false;
        t += dt;
        const k = Math.max(0, 1 - t / 0.28);
        _a.copy(d).multiplyScalar(dist * 3.6 * k * dt);
        col.moveCircle(z.pos, _a, z.radius || 0.35, z.height || 1.6, 0.45);
        if (z.group) z.group.position.copy(z.pos);
        return t < 0.28;
      },
    });
  }

  // Playback death: tumbles backward head over heels, then pops into confetti (while its groan replays at 2x).
  _tumble(z, dir, i, pre = null) {
    const P = pre && pre !== true ? pre : this._corpse(z);
    if (!P) return;
    const g = this.game;
    const pos = P.pivot.position.clone();
    const d = dir.clone().setY(0).normalize();
    const dist = this._clearDist(pos, d, 3.2 + Math.random() * 1.6, 0.5);
    const mid = P.h * 0.5;
    P.tilt.position.y = mid;
    P.body.position.y = -mid;
    // spin backward relative to the zombie's own facing
    const local = d.clone().applyQuaternion(_q.copy(P.pivot.quaternion).invert());
    const axis = new THREE.Vector3(local.z, 0, -local.x).normalize();
    const turns = 1 + Math.random() * 0.6;
    const dur = 0.72 + Math.random() * 0.12;
    let t = 0, popped = false;
    if (i < 4) this._later(0.05 + i * 0.07, () => this._play('zmb_groan', { pos, rate: 2, vol: 0.8 }));
    this._actors.push({
      update: (dt) => {
        t += dt;
        const k = clamp01(t / dur);
        P.pivot.position.copy(pos).addScaledVector(d, dist * E.outQuad(k));
        P.pivot.position.y = pos.y + Math.sin(k * Math.PI) * (1.1 + dist * 0.12);
        P.tilt.quaternion.setFromAxisAngle(axis, -k * TAU * turns);
        const sq = 1 + Math.sin(k * Math.PI * 3) * 0.08;
        P.tilt.scale.set(1 / sq, sq, 1 / sq);
        if (k >= 1 && !popped) {
          popped = true;
          _a.copy(P.pivot.position).setY(P.pivot.position.y + mid);
          g.fx?.burst?.(_a, { shape: 'confetti', count: 26, speed: 5 });
          g.fx?.burst?.(_a, { shape: 'puff', count: 6, size: 0.2 });
          g.fx?.burst?.(_a, { shape: 'star', count: 4 });
          this._play('zmb_head_pop', { pos: _a, rate: 1.3, vol: 0.8 });
        }
        P.sync();
        return !popped;
      },
      dispose: () => P.dispose(),
    });
  }

  // ------------------------------------------------------------------------------------------ CHROMA-KEY
  _chromaFire(ctx, st, slot) {
    if (ctx.triggerPressed) st.buffer = 0.16;
    if (st.cool > 0 || st.buffer <= 0) return false;
    if (this._empty('chroma_key', ctx, slot)) { st.buffer = 0; return false; }
    st.buffer = 0;
    const def = ctx.def || {}, up = !!ctx.upgraded;
    const mods = this.game.player && this.game.player.mods;
    st.cool = (def.rpm ? 60 / def.rpm : G.chroma.interval) / ((mods && mods.fireRate) || 1);
    slot.mag--;
    this._launchBlob(ctx, up, def);
    this._recoil(0.03, 'chroma_key');
    this._emit('weapon:fire', { weaponId: 'chroma_key', upgraded: up });
    return true;
  }

  _launchBlob(ctx, up, def) {
    const g = this.game, C = G.chroma, R = this.res;
    // aim point: first zombie / wall along the camera ray
    const col = g.level && g.level.col;
    const wall = col ? col.raycast(ctx.origin, ctx.dir, 60) : null;
    const zh = g.zombies && g.zombies.raycast ? g.zombies.raycast(ctx.origin, ctx.dir, wall ? wall.dist : 60) : null;
    const target = zh ? zh.point : wall ? wall.point : _a.copy(ctx.origin).addScaledVector(ctx.dir, 40);
    const from = ctx.muzzle.clone();
    const B = (def && def.blob) || {};
    const speed = B.speed ?? C.speed, grav = B.gravity ?? C.grav;
    const vel = this._ballistic(from, target, speed, grav) || _b.subVectors(target, from).normalize().multiplyScalar(speed).clone();
    const mesh = new THREE.Mesh(R.blobGeo, up ? R.mGooUp : R.mGoo);
    mesh.scale.setScalar(B.r ?? C.r);
    mesh.position.copy(from);
    mesh.castShadow = true;
    g.scene.add(mesh);
    this._blobs.push({ pos: from, vel: vel.clone(), t: 0, up, def, mesh, bounces: B.bounces ?? (up ? 1 : 0), r: B.r ?? C.r, grav,
      life: B.life ?? C.fuse, trail: 0, seed: Math.random() * 10 });
    g.fx?.burst?.(from, { shape: 'goo', count: 6, dir: _c.copy(vel).normalize(), cone: 0.5, speed: 4, size: 0.07, colors: up ? [PAL.greenScreen, '#9CFF57'] : [PAL.chromaBlue, '#4F86FF'] });
  }

  // Low-arc launch velocity reaching `to` at `speed` under gravity g (null when out of range).
  _ballistic(from, to, speed, grav) {
    const dx = to.x - from.x, dz = to.z - from.z, dy = to.y - from.y;
    const x = Math.hypot(dx, dz);
    if (x < 0.5) return null;
    const v2 = speed * speed;
    const disc = v2 * v2 - grav * (grav * x * x + 2 * dy * v2);
    if (disc < 0) return null;
    const ang = Math.atan2(v2 - Math.sqrt(disc), grav * x);
    const h = Math.cos(ang) * speed;
    return new THREE.Vector3((dx / x) * h, Math.sin(ang) * speed, (dz / x) * h);
  }

  _updateBlobs(dt) {
    if (!this._blobs.length || dt <= 0) return;
    const g = this.game, C = G.chroma, col = g.level && g.level.col;
    const zm = g.zombies;
    for (let i = this._blobs.length - 1; i >= 0; i--) {
      const b = this._blobs[i];
      b.t += dt;
      let burst = null, direct = null, normal = null;
      const steps = Math.max(1, Math.ceil((b.vel.length() * dt) / 0.3));
      const h = dt / steps;
      for (let s = 0; s < steps && !burst; s++) {
        b.vel.y -= b.grav * h;
        const len = b.vel.length() * h;
        _d.copy(b.vel).normalize();
        const zh = zm && zm.raycast ? zm.raycast(b.pos, _d, len + b.r) : null;
        const wh = col ? col.raycast(b.pos, _d, len + b.r) : null;
        if (zh && (!wh || zh.dist <= wh.dist) && this._alive(zh.z)) {
          burst = zh.point.clone();
          direct = zh.z;
          normal = _d.clone().negate();
          break;
        }
        if (wh) {
          if (b.bounces > 0) {
            b.bounces--;
            b.squash = 1;
            b.pos.copy(wh.point).addScaledVector(wh.normal, b.r + 0.02);
            b.vel.reflect(wh.normal).multiplyScalar(0.62);
            this._play('grenade_bounce', { pos: b.pos, rate: 0.6, vol: 0.6 });
            g.fx?.burst?.(b.pos, { shape: 'goo', count: 6, colors: [PAL.greenScreen, '#9CFF57'], dir: wh.normal, speed: 3 });
            continue;
          }
          burst = wh.point.clone();
          normal = wh.normal.clone();
          break;
        }
        b.pos.addScaledVector(b.vel, h);
        const f = this._floorY(b.pos.x, b.pos.z, b.pos.y + 0.3);
        if (f !== null && b.pos.y - b.r < f) {
          if (b.bounces > 0) {
            b.bounces--;
            b.squash = 1;
            b.pos.y = f + b.r;
            b.vel.y = Math.abs(b.vel.y) * 0.6;
            b.vel.x *= 0.75;
            b.vel.z *= 0.75;
            this._play('grenade_bounce', { pos: b.pos, rate: 0.6, vol: 0.6 });
            continue;
          }
          burst = b.pos.clone().setY(f + 0.02);
          normal = new THREE.Vector3(0, 1, 0);
        }
      }
      if (!burst && b.t >= b.life) { burst = b.pos.clone(); normal = new THREE.Vector3(0, 1, 0); }
      // goo wobble (+ a bounce squash) stretched along the flight, trail
      b.squash = Math.max(0, (b.squash || 0) - dt * 5);
      const w = Math.sin(b.t * 30 + b.seed) * 0.12;
      const sp = Math.min(0.35, b.vel.length() * 0.012);
      b.mesh.position.copy(b.pos);
      b.mesh.quaternion.setFromUnitVectors(_zAxis, _d.copy(b.vel).normalize());
      const sq = b.squash * 0.45;
      b.mesh.scale.set(b.r * (1 + w + sq), b.r * (1 - w + sq), b.r * (1 + sp - sq * 1.2));
      b.trail -= dt;
      if (b.trail <= 0) {
        b.trail = 0.035;
        g.fx?.burst?.(b.pos, { shape: 'goo', count: 1, speed: 0.4, size: 0.05, life: 0.4, colors: b.up ? [PAL.greenScreen] : [PAL.chromaBlue] });
      }
      if (burst) {
        b.mesh.removeFromParent();
        this._blobs.splice(i, 1);
        this._splash(burst, normal, b.up, b.def, direct);
      }
    }
  }

  _splash(pos, normal, up, def, direct) {
    const g = this.game, C = G.chroma;
    const r = (def && def.splash && def.splash.r) || (up ? C.splashUp : C.splash);
    const cols = up ? [PAL.greenScreen, '#9CFF57', '#E4FFD8'] : [PAL.chromaBlue, '#4F86FF', '#BFD4FF'];
    this._play('wpn_chroma_splat', { pos });
    g.fx?.burst?.(pos, { shape: 'goo', count: 22, colors: cols, dir: normal, cone: 1.1, speed: 5.5, size: 0.1 });
    g.fx?.burst?.(pos, { shape: 'spark', count: 10, colors: cols, speed: 6 });
    // walls / floor only (a body would leave it mid-air); fades out with the puddle (the old fx decal never went away)
    if (!direct) this._splat(pos, normal, up, (def && def.puddle && def.puddle.life) ?? (up ? C.puddleTUp : C.puddleT));
    g.fx?.flashLight?.(pos, cols[0], 7, 0.25);
    // the splash ring and the puddle sit on the floor below the burst (a body hit bursts at chest height)
    const f = this._splashFloor(pos, r);
    const onFloor = f !== null && pos.y - f < 2.6;
    this._floorRing(onFloor ? _d.set(pos.x, f, pos.z) : pos, r, cols[0], 0.35, true, 0.8);
    if (direct && this._isBoss(direct)) this._damage(direct, def?.bossDmg ?? C.boss, 'chroma_key', 'chroma_key', { upgraded: up });
    const eye = _c.copy(pos).addScaledVector(normal || _up, 0.3);
    for (const z of this._zombies().slice()) {
      if (!this._alive(z) || this._isBoss(z)) continue;
      this._chest(z, _p);
      if (_p.distanceTo(pos) > r + (z.radius || 0.4) && z.pos.distanceTo(pos) > r) continue;
      if (!this._los(eye, _p) && !this._los(eye, _a.copy(z.pos).setY(z.pos.y + 0.3))) continue;
      this._keyZombie(z, up, def, z !== direct);
    }
    if (onFloor) this._spawnPuddle(new THREE.Vector3(pos.x, f, pos.z), up, def);
  }

  // Goo splat mark on the surface hit (normal), gone after `dur` s (= the puddle's lifetime): pops in, then fades
  // and shrinks a little over its last second, together with the puddle's shrink (see _updatePools).
  _splat(pos, normal, up, dur) {
    const it = (up ? this.pools.splatUp : this.pools.splat).spawn();
    const n = normal || _up;
    it.q.setFromUnitVectors(_zAxis, n).multiply(_q2.setFromAxisAngle(_zAxis, Math.random() * TAU));
    it.pos.copy(pos).addScaledVector(n, 0.006);
    it.size = 1.1;
    it.t = 0;
    it.dur = Math.max(0.5, dur || G.chroma.puddleT);
    it.m.copy(ZERO_M);
    it.c.setRGB(0, 0, 0);
    return it;
  }

  // Floor height for a splash: the most common floor among the burst point and 8 samples around it, so a blob
  // that bursts on a stool, a crate or a desk corner spills its puddle onto the floor around it (the prop hides
  // part of it) instead of a 3 m disc floating at the prop's top; on a riser or the stage it stays up there.
  _splashFloor(pos, r) {
    const yFrom = pos.y + 0.2;
    const hs = this._floorSamples || (this._floorSamples = []);
    hs.length = 0;
    const f0 = this._floorY(pos.x, pos.z, yFrom);
    if (f0 !== null) hs.push(f0);
    const rr = Math.min(1.8, r * 0.6);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU;
      const f = this._floorY(pos.x + Math.cos(a) * rr, pos.z + Math.sin(a) * rr, yFrom);
      if (f !== null) hs.push(f);
    }
    if (!hs.length) return null;
    let best = hs[0], bestN = 0;
    for (const h of hs) {
      let n = 0;
      for (const o of hs) if (Math.abs(o - h) < 0.15) n++;
      if (n > bestN || (n === bestN && h < best)) { best = h; bestN = n; }
    }
    return best;
  }

  // Keyed: instant kill up to r25 (r35 upgraded), else 6,000 damage; the keyed swirl plays on the corpse.
  _keyZombie(z, up, def, splash = false) {
    const C = G.chroma;
    this._claimed.add(z);
    const killUpTo = def?.killUpTo ?? (up ? C.killUpToUp : C.killUpTo);
    const instant = this._round() <= killUpTo;
    const extra = { upgraded: up, splash };
    const P = this._doom(z, () => (instant
      ? this._kill(z, 'chroma_key', 'chroma_key', extra)
      : this._damage(z, def?.dmg ?? C.late, 'chroma_key', 'chroma_key', extra)));
    if (P) this._keyed(z, up, null, P, def);
    else { this._claimed.delete(z); this._flashLive(z); }
    return !!P;
  }

  // Flat chroma color (0.3 s) -> a zombie-shaped window onto stock footage (0.8 s) -> swirls into a point (0.4 s).
  _keyed(z, up, forceWorld = null, pre = null, def = null) {
    const P = pre && pre !== true ? pre : this._corpse(z);
    if (!P) return;
    const g = this.game, R = this.res;
    const fromDef = def && Array.isArray(def.worlds) ? def.worlds.map((w) => String(w).replace(/^world_/, '')).filter((w) => R.foot[w]) : null;
    const worlds = fromDef && fromDef.length ? fromDef : up ? [...WORLDS, ...WORLDS_UP] : WORLDS;
    const world = forceWorld || worlds[Math.floor(Math.random() * worlds.length)];
    const pos = P.pivot.position.clone();
    const mid = P.h * 0.5;
    P.tilt.position.y = mid;
    P.body.position.y = -mid;
    this._emit('wonder:key', { z, world });
    this._play('wpn_chroma_key', { pos });
    let t = 0, sounded = false, flashed = false;
    const tint = WORLD_TINT[world];
    // own footage material (same program): its uFxFrame follows this body on screen
    const foot = fxMaterial('footage', R.foot[world].userData.fxOpts);
    const frame = foot.userData.fx.uFxFrame.value;
    this._actors.push({
      update: (dt) => {
        t += dt;
        _p.copy(P.pivot.position).setY(P.pivot.position.y + mid);
        this._screenFrame(_p, P.h * Math.max(0.3, P.tilt.scale.y), frame);
        if (t < 0.3) {
          P.setMat(up ? R.fx.flatUp : R.fx.flat);
          const k = t / 0.3;
          const s = 1 + Math.sin(k * Math.PI) * 0.07;
          P.tilt.scale.set(1 / s, s, 1 / s);
        } else if (t < 1.1) {
          P.setMat(foot);
          if (!sounded) { sounded = true; this._play(`world_${world}`, { pos }); }
          P.pivot.position.y = pos.y + Math.sin((t - 0.3) * 5) * 0.03 + (t - 0.3) * 0.08;
          if (Math.random() < 0.35) {
            _a.set((Math.random() - 0.5) * 0.7, Math.random() * P.h, (Math.random() - 0.5) * 0.7).add(pos);
            g.fx?.burst?.(_a, { shape: 'star', count: 1, size: 0.07, speed: 0.6, life: 0.5, colors: [tint, '#FFFFFF'] });
          }
        } else {
          const k = seg(t, 1.1, 1.5);
          P.tilt.rotation.y += dt * (8 + k * 40);
          const sxz = 1 - E.inCubic(k);
          const sy = 1 - E.inQuad(k) * 0.98;
          P.tilt.scale.set(Math.max(0.001, sxz), Math.max(0.001, sy), Math.max(0.001, sxz));
          P.pivot.position.y = pos.y + 0.064 + k * 0.5;
          if (Math.random() < 0.6) {
            const a = t * 20;
            _a.set(Math.cos(a) * 0.5 * sxz, mid + (Math.random() - 0.5) * P.h * sy, Math.sin(a) * 0.5 * sxz).add(P.pivot.position);
            g.fx?.burst?.(_a, { shape: 'spark', count: 1, speed: 0.5, size: 0.04, life: 0.25, colors: [tint] });
          }
          if (k >= 1 && !flashed) {
            flashed = true;
            _a.copy(P.pivot.position).setY(P.pivot.position.y + mid);
            g.fx?.burst?.(_a, { shape: 'star', count: 6, speed: 2.2, colors: [tint, '#FFFFFF'] });
            g.fx?.flashLight?.(_a, tint, 4, 0.12);
          }
        }
        P.sync();
        return t < 1.5;
      },
      dispose: () => { P.dispose(); foot.dispose(); },
    });
  }

  // Projected centre (px, drawing-buffer space = gl_FragCoord) and on-screen height (px) of a body of height h.
  _screenFrame(center, h, out) {
    const cam = this.game.camera, res = FXU.res.value;
    _a.copy(center).project(cam);
    _b.copy(center).setY(center.y + h * 0.5).project(cam);
    _c.copy(center).setY(center.y - h * 0.5).project(cam);
    out.set((_a.x * 0.5 + 0.5) * res.x, (_a.y * 0.5 + 0.5) * res.y, Math.max(8, Math.abs(_b.y - _c.y) * 0.5 * res.y));
    return out;
  }

  _spawnPuddle(pos, up, def = null) {
    const g = this.game, C = G.chroma, R = this.res;
    const PD = (def && def.puddle) || {};
    const r = PD.r ?? C.puddleR;
    const mesh = new THREE.Mesh(R.puddle, up ? R.mPuddleUp : R.mPuddle);
    mesh.position.copy(pos).setY(pos.y + 0.012);
    mesh.rotation.y = Math.random() * TAU;
    mesh.scale.set(0.001, 1, 0.001);
    mesh.receiveShadow = true;
    mesh.castShadow = false;
    mesh.renderOrder = 1;
    const rim = new THREE.Mesh(R.puddle, up ? R.mPuddleRimUp : R.mPuddleRim);
    rim.scale.set(1.08, 1, 1.08);
    rim.position.y = -0.004;
    rim.receiveShadow = true;
    const sheen = new THREE.Mesh(R.puddleSheen, up ? R.mPuddleSheenUp : R.mPuddleSheen);
    sheen.scale.set(0.34, 1, 0.22);
    sheen.position.set(0.22, 0.003, -0.2);
    sheen.rotation.y = 0.6;
    mesh.add(rim, sheen);
    g.scene.add(mesh);
    const pool = g.fx?.lightPool?.(pos, r * 1.2, up ? PAL.greenScreen : PAL.chromaBlue, 0.0) || null;
    this._puddles.push({ pos: pos.clone(), r, t: 0, dur: PD.life ?? (up ? C.puddleTUp : C.puddleT), keys: PD.keys ?? (up ? C.puddleNUp : C.puddleN), up, def, mesh, pool, bub: 0 });
  }

  _disposePuddle(p) {
    p.mesh.removeFromParent();
    p.pool?.remove?.();
  }

  _updatePuddles(dt) {
    const g = this.game;
    for (let i = this._puddles.length - 1; i >= 0; i--) {
      const p = this._puddles[i];
      p.t += dt;
      const kIn = E.outElastic(clamp01(p.t / 0.5));
      const kOut = 1 - E.inQuad(seg(p.t, p.dur - 0.5, p.dur));
      const wob = 1 + Math.sin(p.t * 5) * 0.02;
      const s = p.r * Math.max(0.001, kIn * kOut);
      p.mesh.scale.set(s * wob, 1, s / wob);
      p.pool?.set?.({ intensity: 0.22 * kIn * kOut });
      p.bub -= dt;
      if (p.bub <= 0) {
        p.bub = 0.12;
        const a = Math.random() * TAU, rr = Math.sqrt(Math.random()) * p.r * 0.8 * kOut;
        _a.set(p.pos.x + Math.cos(a) * rr, p.pos.y + 0.05, p.pos.z + Math.sin(a) * rr);
        g.fx?.burst?.(_a, { shape: 'goo', count: 1, speed: 1.2, size: 0.05, life: 0.35, gravity: 6, dir: _up, cone: 0.2, colors: p.up ? [PAL.greenScreen, '#E4FFD8'] : [PAL.chromaBlue, '#BFD4FF'] });
      }
      if (p.keys > 0 && p.t < p.dur - 0.3) {
        for (const z of this._zombies().slice()) {
          if (p.keys <= 0) break;
          if (!this._alive(z) || this._isBoss(z)) continue;
          const dx = z.pos.x - p.pos.x, dz = z.pos.z - p.pos.z;
          if (dx * dx + dz * dz > (p.r * 0.92) ** 2 || Math.abs(z.pos.y - p.pos.y) > 0.8) continue;
          if (this._keyZombie(z, p.up, p.def)) p.keys--;
        }
      }
      if (p.t >= p.dur) {
        this._disposePuddle(p);
        this._puddles.splice(i, 1);
      }
    }
  }

  // ------------------------------------------------------------------------------------------ TINY TELE
  _teleProto() {
    if (this._tele0 !== null) return this._tele0 || null;
    try {
      const g = this.game;
      const proto = buildWeapon('tiny_tele', { pose: 'display', unique: true }, g);
      this._tele0 = proto;
    } catch (err) {
      console.warn('[wonder] tiny_tele prop unavailable, using a placeholder', err);
      const g = new THREE.Group();
      const R = this.res;
      const box = geo.mesh(geo.roundedBox(0.3, 0.23, 0.22, 0.05, 2), this.game.mats.toon(PAL.burntOrange, { keepColor: true, rough: 0.4 }), { pos: [0, 0.13, 0] });
      g.add(box);
      const scr = new THREE.Mesh(geo.plane(0.18, 0.14), this.game.mats.screen(null, { w: 0.18, h: 0.14 }));
      scr.name = 'screen';
      scr.position.set(-0.03, 0.13, -0.112);
      scr.rotation.y = Math.PI;
      g.add(scr);
      const ant = new THREE.Group();
      ant.name = 'antenna';
      ant.position.set(0.08, 0.25, 0.05);
      ant.add(geo.mesh(geo.cylinder(0.005, 0.005, 0.25, 6), R.mInk, { pos: [0, 0.12, 0] }));
      g.add(ant);
      this._tele0 = g;
    }
    return this._tele0;
  }

  _spawnTele(ctx = null) {
    const g = this.game, p = g.player, TT = this._teleDef();
    const proto = this._teleProto();
    if (!proto || !p) return null;
    const root = new THREE.Group();
    root.name = 'wonder:tiny_tele';
    const model = safeClone(proto, false);
    model.scale.setScalar(TT.scale);
    const spin = new THREE.Group();
    spin.add(model);
    root.add(spin);
    const screen = model.getObjectByName('screen');
    const screenMat = g.mats.screen(this._screenTex, { w: 0.18, h: 0.142, bright: 1.1 });
    if (screen) screen.material = screenMat;
    screenMat.map = this._snowTex() || this._screenTex;
    const parts = { ant: model.getObjectByName('antenna'), ant2: model.getObjectByName('ant2'), ant3: model.getObjectByName('ant3') };
    // weapons.js hands over the throw (left hand + velocity); otherwise lob it from the right hand along the aim
    let vel;
    if (ctx) {
      _a.copy(ctx.origin);
      vel = ctx.velocity.clone();
    } else {
      const hand = p.hero && p.hero.slots && p.hero.slots.handR;
      if (hand) hand.getWorldPosition(_a);
      else _a.copy(p.pos).setY(p.pos.y + 1.3);
      p.aimRay(_c, _d);
      vel = _d.clone().setY(0).normalize().multiplyScalar(TT.speed * Math.max(0.35, Math.cos(Math.asin(Math.max(-1, Math.min(1, _d.y))))));
      vel.y = TT.up + _d.y * TT.speed * 0.8;
    }
    root.position.copy(_a);
    g.scene.add(root);
    const tele = {
      root, spin, model, screen, screenMat, parts, pos: root.position, vel, state: 'fly', t: 0, live: 0, bounces: 0,
      tumble: new THREE.Vector3(6 + Math.random() * 4, 3, 2), seats: [], seated: new Set(), yaw: 0, blob: g.fx?.blob?.(root, 0.32) || null,
      loop: null,
    };
    this.teles.push(tele);
    this._play('tele_throw', { pos: root.position });
    if (p.anim) p.anim.recoil = 1;
    return tele;
  }

  // Tiny Tele numbers: weaponDefs.tiny_tele (fuse, killR, killUpTo, dmgAfter) over the GDD fallback table.
  _teleDef() {
    const d = this.game.weapons?.defs?.tiny_tele;
    if (!d) return G.tele;
    if (this._teleDefSrc !== d) {
      this._teleDefSrc = d;
      this._teleDefC = { ...G.tele, fuse: d.fuse ?? G.tele.fuse, killR: d.killR ?? G.tele.killR, killUpTo: d.killUpTo ?? G.tele.killUpTo,
        late: d.dmgAfter ?? G.tele.late, lure: d.lure ?? G.tele.lure };
    }
    return this._teleDefC;
  }

  // Animated TV snow (gfx card) shown while a tele flies and lands, before the cartoon flips on.
  _snowTex() {
    if (this._snow === undefined) {
      try { this._snow = getAnimated('snow'); } catch (err) { this._snow = null; }
    }
    return this._snow ? this._snow.texture : null;
  }

  _disposeTele(t) {
    t.root.removeFromParent();
    t.blob?.remove?.();
    try { t.loop?.stop?.(0.05); } catch (err) { /* ignore */ }
    try { t.tick?.stop?.(0.05); } catch (err) { /* ignore */ }
    for (const z of t.seated) this._unseat(z);
    t.seated.clear();
  }

  _updateTeles(dt) {
    if (!this.teles.length) return;
    const g = this.game, TT = this._teleDef();
    let anyLive = false;
    for (let i = this.teles.length - 1; i >= 0; i--) {
      const t = this.teles[i];
      t.t += dt;
      if (t.state === 'fly') this._teleFly(t, dt);
      else if (t.state === 'land') this._teleLand(t, dt);
      else if (t.state === 'live') { anyLive = true; this._teleLive(t, dt); }
      else if (t.state === 'implode' && this._teleImplode(t, dt)) {
        this._disposeTele(t);
        this.teles.splice(i, 1);
        this._relure();
      }
    }
    if (anyLive) this._drawCartoon(g.time.now);
    if (this._snow && this.teles.some((x) => x.state === 'fly' || x.state === 'land')) {
      try { this._snow.tick(g.time.realNow); } catch (err) { /* card failed: keep the last frame */ }
    }
  }

  _teleFly(t, dt) {
    const g = this.game, TT = this._teleDef(), col = g.level && g.level.col;
    if (dt <= 0) return;
    t.vel.y -= TT.grav * dt;
    const len = t.vel.length() * dt;
    if (col && len > 1e-4) {
      _d.copy(t.vel).normalize();
      const hit = col.raycast(_a.copy(t.pos).setY(t.pos.y + 0.2), _d, len + 0.25);
      if (hit && Math.abs(hit.normal.y) < 0.5) {
        t.vel.reflect(hit.normal).multiplyScalar(0.45);
        this._play('grenade_bounce', { pos: t.pos, rate: 0.5, vol: 0.7 });
      }
    }
    t.pos.addScaledVector(t.vel, dt);
    t.spin.rotation.x += t.tumble.x * dt;
    t.spin.rotation.z += t.tumble.z * dt;
    const f = this._floorY(t.pos.x, t.pos.z, t.pos.y + 0.3);
    if (f !== null && t.pos.y <= f && t.vel.y < 0) {
      t.pos.y = f;
      if (t.bounces < 1 && Math.abs(t.vel.y) > 3) {
        t.bounces++;
        t.vel.y = Math.abs(t.vel.y) * 0.32;
        t.vel.x *= 0.45;
        t.vel.z *= 0.45;
        t.tumble.multiplyScalar(0.5);
        this._play('telly_clonk', { pos: t.pos, vol: 0.9 });
        g.fx?.burst?.(t.pos, { shape: 'puff', count: 4, size: 0.12, life: 0.4 });
      } else {
        t.state = 'land';
        t.t = 0;
        t.vel.set(0, 0, 0);
        t.floor = f;
        const p = g.player;
        t.yaw = p ? Math.atan2(p.pos.x - t.pos.x, p.pos.z - t.pos.z) + Math.PI : 0; // screen (-z) toward the thrower
        t.q0 = t.spin.quaternion.clone();
        t.q1 = new THREE.Quaternion().setFromAxisAngle(_up, t.yaw);
        this._play('telly_clonk', { pos: t.pos, vol: 1, rate: 0.85 });
        g.fx?.burst?.(t.pos, { shape: 'puff', count: 6, size: 0.15, life: 0.5 });
      }
    }
    if (t.t > 3 && t.state === 'fly') {
      // lost in the void: land where it is
      t.state = 'land';
      t.t = 0;
      t.floor = t.pos.y;
      t.q0 = t.spin.quaternion.clone();
      t.q1 = new THREE.Quaternion();
    }
  }

  // Rights itself (squash on landing), telescopes the antenna, flips on with a burst of snow.
  _teleLand(t, dt) {
    const g = this.game;
    const k = clamp01(t.t / 0.28);
    t.spin.quaternion.slerpQuaternions(t.q0, t.q1, E.outBack(k, 1.2));
    const sq = t.t < 0.4 ? 1 - Math.sin(clamp01(t.t / 0.4) * Math.PI) * 0.22 : 1;
    t.spin.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));
    const ka = seg(t.t, 0.28, 0.62);
    if (t.parts.ant2) t.parts.ant2.position.y = 0.08 * E.outBack(ka, 2.2);
    if (t.parts.ant3) t.parts.ant3.position.y = 0.078 * E.outBack(seg(t.t, 0.36, 0.7), 2.2);
    if (t.t >= 0.7) {
      t.state = 'live';
      t.t = 0;
      t.live = 0;
      t.screenMat.map = this._screenTex;
      g.zombies?.setLure?.(t.pos.clone(), t.lure ?? this._teleDef().lure ?? 15);
      this._lureTele = t;
      try { t.loop = g.audio?.loop?.('tele_cartoon', { pos: t.pos.clone() }) || null; } catch (err) { t.loop = null; }
      t.tick = this._play('tele_tick', { pos: t.pos.clone(), dur: this._teleDef().fuse });
      this._play('crt_ping', { pos: t.pos });
      this._emit('wonder:tele', { state: 'land', pos: t.pos.clone() });
    }
  }

  _teleLive(t, dt) {
    const g = this.game, TT = this._teleDef();
    t.live += dt;
    const beat = g.time.now * 2.5 * TAU;
    const hop = Math.max(0, Math.sin(beat)) * 0.05;
    const late = seg(t.live, TT.fuse - 1.5, TT.fuse);
    const shake = late * 0.03;
    t.spin.position.set((Math.random() - 0.5) * shake, hop * (1 - late) + Math.random() * shake, (Math.random() - 0.5) * shake);
    const sq = 1 + Math.sin(beat) * 0.05;
    t.spin.scale.set(1 / Math.sqrt(sq), sq, 1 / Math.sqrt(sq));
    if (t.parts.ant) t.parts.ant.rotation.z = Math.sin(beat * 0.5) * 0.25;
    if (t.screenMat.uniforms && t.screenMat.uniforms.uBright) t.screenMat.uniforms.uBright.value = 1.1 + (late > 0 && Math.sin(t.live * 40) > 0.4 ? 0.8 : 0);
    this._seatZombies(t, dt);
    if (t.live >= TT.fuse) {
      t.state = 'implode';
      t.t = 0;
      this._teleBoom(t);
    }
  }

  // Zombies that reach the tele sit cross-legged in a semicircle (r 2.2 m) facing it, mesmerized. Seats must be
  // walkable and in sight of the tele and of the zombie; otherwise it stands and sways where it is.
  _seatZombies(t, dt) {
    const TT = this._teleDef();
    for (const z of this._zombies()) {
      if (!this._alive(z) || this._isBoss(z) || t.seated.has(z)) continue;
      // only zombies already inside (not tearing boards / vaulting / emerging from a screen) and in sight of the TV
      if (z.state && z.state !== 'chase' && z.state !== 'attack') continue;
      const d = Math.hypot(z.pos.x - t.pos.x, z.pos.z - t.pos.z);
      if (d > TT.seatR + 1.4 || Math.abs(z.pos.y - t.pos.y) > 1.2) continue;
      if (this._seatOf(z)) continue;
      if (!this._los(_a.copy(z.pos).setY(z.pos.y + 0.8), _b.copy(t.pos).setY(t.pos.y + 0.4))) continue;
      const seat = STANDERS.has(z.type) ? null : this._findSeat(t, z);
      t.seated.add(z);
      const s = this._stat(z);
      const walk = seat ? Math.hypot(seat.x - z.pos.x, seat.z - z.pos.z) : 0;
      s.seat = { tele: t, pos: seat || z.pos.clone(), from: z.pos.clone(), t: 0, stand: !seat, dur: seat ? Math.min(1.6, Math.max(0.3, walk / 1.7)) : 0,
        yaw0: z.yaw || 0, plopped: false };
      s.t = 0;
      this._applyPose(z);
    }
  }

  _findSeat(t, z) {
    const TT = this._teleDef(), nav = this.game.nav;
    const face = _c.set(-Math.sin(t.yaw), 0, -Math.cos(t.yaw)); // the screen side
    t.free = t.free || [];
    const reach = (seat) => this._los(_a.copy(z.pos).setY(z.pos.y + 0.6), _b.copy(seat).setY(seat.y + 0.6));
    for (let i = 0; i < t.free.length; i++) {
      if (reach(t.free[i])) return t.free.splice(i, 1)[0];
    }
    t.seatIdx = t.seatIdx || 0;
    while (t.seatIdx < 24) {
      const idx = t.seatIdx++;
      const row = idx < 9 ? 0 : 1;
      const n = row ? idx - 9 : idx;
      const step = row ? 16 : 20;
      const a = ((n % 2 ? 1 : -1) * Math.ceil(n / 2) * step + (row ? 8 : 0)) * DEG;
      const r = TT.seatR + row * 0.85;
      const dir = face.clone().applyAxisAngle(_up, a);
      const seat = new THREE.Vector3(t.pos.x + dir.x * r, t.pos.y, t.pos.z + dir.z * r);
      if (nav && nav.walkable && !nav.walkable(seat.x, seat.z)) continue;
      const f = this._floorY(seat.x, seat.z, t.pos.y + 0.5);
      if (f === null || Math.abs(f - t.pos.y) > 0.5) continue;
      seat.y = f;
      if (!this._los(_a.copy(t.pos).setY(t.pos.y + 0.5), _b.copy(seat).setY(seat.y + 0.5))) continue;
      if (reach(seat)) return seat;
      t.free.push(seat);
    }
    return null;
  }

  _seatOf(z) {
    const s = this._status.get(z);
    return s && s.seat;
  }

  _unseat(z) {
    const s = this._status.get(z);
    if (!s || !s.seat) return;
    const st = s.seat;
    if (!st.stand && st.tele && st.tele.state === 'live') (st.tele.free = st.tele.free || []).push(st.pos);
    s.seat = null;
    this._releaseHold(z);
    this._applyPose(z);
    this._maybeDrop(z);
  }

  _teleBoom(t) {
    const g = this.game, TT = this._teleDef();
    const center = t.pos.clone().setY(t.pos.y + 0.25);
    try { t.loop?.stop?.(0.05); } catch (err) { /* ignore */ }
    t.loop = null;
    this._play('tele_implode', { pos: center });
    g.fx?.flashLight?.(center, '#BFE8FF', 10, 0.3);
    g.fx?.burst?.(center, { shape: 'static', count: 24, speed: 4 });
    g.fx?.burst?.(center, { shape: 'spark', count: 16, colors: ['#FFFFFF', '#7FE7FF', '#FF5FA2'], speed: 7 });
    this._floorRing(t.pos, TT.killR, '#7FE7FF', 0.42, false, 0.8);
    this._floorRing(t.pos, TT.killR * 0.55, '#FF5FA2', 0.3, false, 0.7);
    g.cam?.shake?.(0.2, 0.3);
    const late = this._round() > TT.killUpTo;
    for (const z of this._zombies().slice()) {
      if (!this._alive(z) || this._isBoss(z)) continue;
      if (z.pos.distanceTo(t.pos) > TT.killR) continue;
      const P = this._doom(z, () => (late ? this._damage(z, TT.late, 'tiny_tele', 'tiny_tele') : this._kill(z, 'tiny_tele', 'tiny_tele')));
      if (P) this._suckIn(z, center, P);
    }
    for (const z of t.seated) this._unseat(z);
    t.seated.clear();
    this._emit('wonder:tele', { state: 'implode', pos: t.pos.clone() });
  }

  // The TV crushes inward (anticipation swell), the screen collapses to a line and a dot.
  _teleImplode(t, dt) {
    const k = clamp01(t.t / 0.35);
    const swell = k < 0.3 ? 1 + E.outQuad(k / 0.3) * 0.18 : (1.18) * (1 - E.inBack((k - 0.3) / 0.7, 2));
    t.spin.scale.set(Math.max(0.001, swell), Math.max(0.001, swell * (k < 0.3 ? 1 : 1 - (k - 0.3) * 0.6)), Math.max(0.001, swell));
    t.spin.rotation.y += dt * 12 * k;
    return t.t >= 0.36;
  }

  _suckIn(z, center, pre = null) {
    const P = pre && pre !== true ? pre : this._corpse(z);
    if (!P) return;
    const from = P.pivot.position.clone();
    const mid = P.h * 0.5;
    P.tilt.position.y = mid;
    P.body.position.y = -mid;
    let t = 0;
    const dur = 0.32 + Math.random() * 0.08;
    this._actors.push({
      update: (dt) => {
        t += dt;
        const k = clamp01(t / dur);
        if (t < 0.05) P.setMat(this.res.fx.static);
        else P.setMat(null);
        P.pivot.position.lerpVectors(from, _a.copy(center).setY(center.y - mid * 0.3), E.inBack(k, 1.4));
        P.tilt.rotation.y += dt * 18;
        const s = Math.max(0.001, 1 - E.inQuad(k));
        P.tilt.scale.set(s, Math.max(0.001, s * (1 + k * 0.8)), s);
        P.sync();
        return k < 1;
      },
      dispose: () => P.dispose(),
    });
  }

  // After an implosion the lure moves to the next live tele, or clears.
  _relure() {
    const next = this.teles.find((x) => x.state === 'live');
    this._lureTele = next || null;
    try { this.game.zombies?.setLure?.(next ? next.pos.clone() : null, next ? (next.lure ?? this._teleDef().lure ?? 15) : Infinity); } catch (err) { /* ignore */ }
  }

  _updateTeleCount() {
    const w = this.game.weapons;
    if (!w || typeof w.teles !== 'number') { this._lastTeles = null; return; }
    if (this._teleCheck) {
      if (w.teles === this._teleCheck.value && this.game.time.frame > this._teleCheck.frame) {
        w.teles = Math.max(0, w.teles - 1);
        this._teleCheck = null;
      } else if (w.teles !== this._teleCheck.value) this._teleCheck = null;
    }
    this._lastTeles = w.teles;
  }

  // ------------------------------------------------------------------------------------------ status effects
  _stat(z) {
    let s = this._status.get(z);
    if (!s) {
      s = { z, slows: null, baseSpeed: null, panic: 0, burn: 0, burnGen: 0, burnLeft: 0, burnCap: 0, laugh: 0, frozen: 0, slowT: 0,
        seat: null, holdT: 0, pose: null, prevOverride: undefined, prevUpdate: undefined, iced: null, flame: null, dmgMul: 1, t: 0, seed: Math.random() * TAU, fire: 0 };
      this._status.set(z, s);
    }
    return s;
  }

  _slow(z, key, mul) {
    const s = this._stat(z);
    if (!s.slows) s.slows = {};
    if (s.baseSpeed === null && typeof z.speed === 'number') s.baseSpeed = z.speed;
    s.slows[key] = mul;
    this._applySpeed(z, s);
  }

  _unslow(z, key) {
    const s = this._status.get(z);
    if (!s || !s.slows || !(key in s.slows)) return;
    delete s.slows[key];
    this._applySpeed(z, s);
    this._maybeDrop(z);
  }

  _applySpeed(z, s) {
    if (s.baseSpeed === null) return;
    let m = 1;
    for (const k in s.slows) m = Math.min(m, s.slows[k]);
    z.speed = s.baseSpeed * m;
    if (!Object.keys(s.slows).length) { z.speed = s.baseSpeed; s.baseSpeed = null; }
  }

  _releaseHold(z) {
    if (typeof z.stun === 'number') z.stun = Math.min(z.stun, 0.05);
  }

  _maybeDrop(z) {
    const s = this._status.get(z);
    if (!s) return;
    const busy = (s.slows && Object.keys(s.slows).length) || s.panic > 0 || s.burn > 0 || s.laugh > 0 || s.frozen > 0 || s.seat || s.slowT > 0;
    if (!busy) this._clearStatus(z);
  }

  _clearStatus(z) {
    const s = this._status.get(z);
    if (!s) return;
    if (s.baseSpeed !== null) z.speed = s.baseSpeed;
    s.slows = null;
    s.baseSpeed = null;
    this._unfreeze(z, s);
    s.pose = null;
    this._setOverride(z, s, null);
    if (s.flame) { s.flame.removeFromParent(); s.flame = null; }
    this._status.delete(z);
  }

  _setOverride(z, s, fn) {
    const an = z.animator;
    if (!an || !('override' in an)) return;
    if (fn) {
      if (an.override !== s.overrideFn) {
        if (s.prevOverride === undefined) s.prevOverride = an.override;
        if (!s.overrideFn) s.overrideFn = (rig, dt) => this._pose(z, s, rig, dt);
        an.override = s.overrideFn;
      }
    } else if (s.prevOverride !== undefined || an.override === s.overrideFn) {
      if (an.override === s.overrideFn) an.override = s.prevOverride ?? null;
      s.prevOverride = undefined;
    }
  }

  _applyPose(z) {
    const s = this._status.get(z);
    if (!s) return;
    const pose = s.frozen > 0 ? null : s.laugh > 0 ? 'laugh' : s.panic > 0 ? 'panic' : s.seat ? (s.seat.stand ? 'sway' : 'sit') : null;
    s.pose = pose;
    this._setOverride(z, s, pose ? true : null);
  }

  // Joint poses (rig conventions: shoulder/hip.x > 0 swings forward, knee.x < 0 bends back, spine.x < 0 leans forward).
  _pose(z, s, rig, dt) {
    const J = rig && rig.joints;
    if (!J || !J.hips) return;
    const D = rig.dims || { hipsY: 0.8 };
    const t = (s.t += dt) + s.seed;
    const set = (j, x, y, zr) => { if (J[j]) J[j].rotation.set(x, y, zr); };
    if (s.pose === 'laugh') {
      const shake = Math.sin(t * 22) * 0.12;
      J.hips.position.y = D.hipsY * 0.3;
      set('hips', 1.32 + shake * 0.3, 0, Math.sin(t * 5) * 0.1);
      set('spine', -0.15 + shake, 0, 0);
      set('chest', -0.2 + shake * 0.6, 0, 0);
      set('neck', -0.25, 0, 0);
      set('head', -0.35 + Math.sin(t * 22 + 1) * 0.15, Math.sin(t * 3) * 0.3, 0);
      for (const [sd, k] of [['L', 1], ['R', -1]]) {
        set(`shoulder${sd}`, 0.9 + shake, 0, k * 0.35);
        set(`elbow${sd}`, 1.9, 0, 0);
        set(`hip${sd}`, 0.9 + Math.sin(t * 13 + (k > 0 ? 0 : Math.PI)) * 0.55, 0, k * 0.25);
        set(`knee${sd}`, -1.3 - Math.max(0, Math.sin(t * 13 + (k > 0 ? 0 : Math.PI))) * 0.6, 0, 0);
      }
    } else if (s.pose === 'panic') {
      const w = t * 16;
      J.hips.position.y += Math.abs(Math.sin(w)) * 0.07;
      set('spine', 0.12, Math.sin(w * 0.5) * 0.2, 0);
      set('head', -0.35, Math.sin(t * 9) * 0.5, 0);
      for (const [sd, k] of [['L', 1], ['R', -1]]) {
        const ph = k > 0 ? 0 : Math.PI;
        set(`shoulder${sd}`, 2.7 + Math.sin(w * 1.3 + ph) * 0.45, 0, k * (0.35 + Math.sin(w + ph) * 0.2));
        set(`elbow${sd}`, 0.5 + Math.sin(w * 1.7 + ph) * 0.4, 0, 0);
        set(`hip${sd}`, Math.sin(w + ph) * 0.95, 0, 0);
        set(`knee${sd}`, -0.2 - Math.max(0, Math.cos(w + ph)) * 1.3, 0, 0);
      }
    } else if (s.pose === 'sit') {
      const st = s.seat || { t: 1, dur: 0 };
      const walking = st.dur > 0 && st.t < st.dur;
      if (walking) {
        // mesmerized shuffle toward the seat: arms up, stiff little steps
        const w = st.t * 10;
        J.hips.position.y += Math.abs(Math.sin(w)) * 0.03;
        set('spine', -0.12, Math.sin(w) * 0.08, 0);
        set('head', 0.15, 0, Math.sin(w * 0.5) * 0.1);
        for (const [sd, k] of [['L', 1], ['R', -1]]) {
          const ph = k > 0 ? 0 : Math.PI;
          set(`shoulder${sd}`, 1.35 + Math.sin(w + ph) * 0.1, 0, k * 0.08);
          set(`elbow${sd}`, 0.25, 0, 0);
          set(`hip${sd}`, Math.sin(w + ph) * 0.45, 0, 0);
          set(`knee${sd}`, -Math.max(0, Math.cos(w + ph)) * 0.7, 0, 0);
        }
        return;
      }
      // sit down: blend from the standing pose (outBack plop), then sway to the cartoon's beat
      const k = E.outBack(seg(st.t, st.dur, st.dur + 0.32), 1.3);
      const blend = (j, x, y, zr) => {
        const o = J[j];
        if (!o) return;
        o.rotation.set(lerp(o.rotation.x, x, k), lerp(o.rotation.y, y, k), lerp(o.rotation.z, zr, k));
      };
      J.hips.position.y = lerp(J.hips.position.y, D.hipsY * 0.27, clamp01(k));
      const sway = Math.sin(t * 2.6) * 0.09 * clamp01(k);
      blend('hips', -0.08, 0, 0);
      blend('spine', 0.05, 0, sway);
      blend('chest', 0, 0, sway * 0.5);
      blend('head', Math.sin(t * 5.2) * 0.1 - 0.05, sway * 1.5, sway);
      for (const [sd, kk] of [['L', 1], ['R', -1]]) {
        blend(`hip${sd}`, 1.45, 0, kk * 0.95);
        blend(`knee${sd}`, -2.3, 0, 0);
        blend(`foot${sd}`, 0.3, 0, -kk * 0.6);
        blend(`shoulder${sd}`, 0.55, 0, kk * 0.15);
        blend(`elbow${sd}`, 0.9, 0, 0);
      }
    } else if (s.pose === 'sway') {
      const sway = Math.sin(t * 2.2) * 0.14;
      set('spine', 0, 0, sway);
      set('head', Math.sin(t * 4.4) * 0.1, sway, sway * 0.6);
    }
  }

  _unfreeze(z, s) {
    if (s.iced) {
      for (const [o, m] of s.iced) if (o.material === this.res.mIce) o.material = m;
      s.iced = null;
    }
    if (s.prevUpdate !== undefined && z.animator) {
      if (s.prevUpdate === null) delete z.animator.update;
      else z.animator.update = s.prevUpdate;
      s.prevUpdate = undefined;
    }
  }

  _updateStatus(dt) {
    if (!this._status.size) return;
    const g = this.game;
    for (const [z, s] of this._status) {
      if (!z || !(z.hp > 0) || z.state === 'dying' || z.state === 'dead' || !this._zombies().includes(z)) {
        this._clearStatus(z);
        continue;
      }
      if (dt <= 0) continue;
      // timers
      if (s.slowT > 0) { s.slowT -= dt; if (s.slowT <= 0) this._unslow(z, 'cold'); }
      if (s.frozen > 0) {
        s.frozen -= dt;
        this._hold(z, 0.2);
        if (s.frozen <= 0) {
          this._unfreeze(z, s);
          this._releaseHold(z);
          g.fx?.burst?.(this._chest(z, _a), { shape: 'star', count: 5, colors: ['#DDF6FF', '#FFFFFF'], speed: 2 });
          this._applyPose(z);
        }
      }
      if (s.laugh > 0) {
        s.laugh -= dt;
        this._hold(z, 0.2);
        if (s.laugh <= 0) { this._releaseHold(z); this._applyPose(z); }
      }
      if (s.burn > 0) this._updateBurn(z, s, dt);
      if (s.panic > 0) this._updatePanic(z, s, dt);
      if (s.seat) this._updateSeat(z, s, dt);
      if (s.pose) this._setOverride(z, s, true);
      if (this._status.has(z)) this._maybeDrop(z);
    }
  }

  // Walks to its seat (a shuffle cycle in the pose override), turns to the screen, plops down cross-legged.
  _updateSeat(z, s, dt) {
    const st = s.seat;
    const t = st.tele;
    if (!t || t.state !== 'live') { this._unseat(z); return; }
    this._hold(z, 0.2);
    st.t += dt;
    const k = st.dur > 0 ? clamp01(st.t / st.dur) : 1;
    z.pos.lerpVectors(st.from, st.pos, E.inOutQuad(k));
    const face = Math.atan2(-(t.pos.x - z.pos.x), -(t.pos.z - z.pos.z));
    let want = face;
    if (k < 1 && st.dur > 0) {
      const walkYaw = Math.atan2(-(st.pos.x - st.from.x), -(st.pos.z - st.from.z));
      const turn = seg(k, 0.6, 1);
      want = walkYaw + Math.atan2(Math.sin(face - walkYaw), Math.cos(face - walkYaw)) * E.inOutQuad(turn);
    }
    z.yaw = want;
    if (z.group) {
      z.group.position.copy(z.pos);
      z.group.rotation.y = want;
    }
    if (z.anim) { z.anim.speed = 0; z.anim.down = false; }
    if (!st.plopped && !st.stand && st.t >= st.dur + 0.18) {
      st.plopped = true;
      z.animator?.kick?.(0.7);
      this.game.fx?.burst?.(_a.copy(z.pos).setY(z.pos.y + 0.05), { shape: 'puff', count: 3, size: 0.12, life: 0.45, speed: 0.8 });
    }
  }

  // ------------------------------------------------------------------------------------------ signal colors
  // zombie:hit -> x1.5 damage while laughing / frozen, then the signal-color roll of upgraded weapons (GDD §10.4):
  // primary hits only (weapons.hit.primary; Double Vision ghosts don't roll), half chance for splash targets,
  // a cooldown per weapon + color. Wonder weapons roll too (their non-lethal late-round hits).
  _onHit(p) {
    if (!p || !p.z) return;
    const z = p.z;
    const internal = p.cause === 'signal_bonus' || p.cause === 'burn';
    if (internal) return;
    const s = this._status.get(z);
    if (s && (s.laugh > 0 || s.frozen > 0) && p.dmg > 0 && z.hp > 0) {
      const bonus = p.dmg * ((s.frozen > 0 ? SIG.cold_open.mul : SIG.laugh_track.mul) - 1);
      if (z.hp - bonus > 0) z.hp -= bonus;
      else this._damage(z, bonus + 1, p.weaponId, 'signal_bonus');
    }
    if (!p.weaponId || p.ghost || p.cause === 'ghost') return;
    if (!(z.hp > 0) || z.state === 'dying' || z.dead) return;
    const wh = this.game.weapons && this.game.weapons.hit;
    const dc = this._applying ? this._dmgCtx : null;
    if (wh && wh.primary === false) return;
    const slot = this._slotOf(p.weaponId);
    const upgraded = (wh && wh.weaponId === p.weaponId ? wh.upgraded : null) ?? (dc ? dc.upgraded : null) ?? p.upgraded ?? (slot && slot.upgraded);
    if (!upgraded) return;
    const signal = String((wh && wh.signal) || p.signal || (slot && slot.signal) || '').replace(/^signal_/, '');
    if (!SIGNALS.includes(signal)) return;
    const S = SIG[signal];
    const key = `${p.weaponId}|${signal}`;
    const now = this.game.time.now;
    if ((this._sigCd.get(key) ?? -1e9) > now) return;
    const splash = !!(p.splash || p.cause === 'splash' || (wh && wh.cause === 'splash') || (dc && dc.splash));
    const chance = S.p * (splash ? 0.5 : 1);
    if (this.game.rand() >= chance) return;
    this._sigCd.set(key, now + S.cd);
    this.applySignal(z, signal, { weaponId: p.weaponId, splash });
  }

  _onKill(p) {
    const z = p && p.z;
    if (!z) return;
    const s = this._status.get(z);
    if (s && s.frozen > 0) this._shatter(z, s);
  }

  // HOT MIC: bursts into cartoon flame and panics (runs away, can't attack), 35 % max HP per second for 3 s.
  _ignite(z, gen, weaponId) {
    const S = SIG.hot_mic, g = this.game;
    const s = this._stat(z);
    const special = SPECIALS.has(z.type), boss = this._isBoss(z);
    if (s.burn > 0 && s.burnGen <= gen) { s.burn = Math.max(s.burn, S.dur); return; }
    s.burn = S.dur;
    s.burnGen = gen;
    s.burnLeft = gen === 1 ? 2 : 0;
    s.burnCap = special || boss ? 1500 : Infinity;
    s.burnWeapon = weaponId;
    if (!special && !boss) {
      s.panic = S.dur;
      this._applyPose(z);
    }
    if (!s.flame) {
      const R = this.res;
      const fl = new THREE.Group();
      fl.add(new THREE.Mesh(R.flameOuter, R.mFlame), new THREE.Mesh(R.flameInner, R.mFlameIn));
      fl.children[1].position.y = 0.02;
      fl.name = 'wonder:flame';
      g.scene.add(fl);
      s.flame = fl;
    }
    this._headPos(z, _a);
    this._play('wonder_fwoomp', { pos: _a });
    const at = _a.clone();
    this._later(0.12, () => this._play('wonder_yeowch', { pos: at, rate: 1 + Math.random() * 0.3 }));
    g.fx?.burst?.(_a, { shape: 'spark', count: 14, colors: [PAL.hotMic, '#FFE14D', '#FFB347'], speed: 5 });
    g.fx?.burst?.(_a, { shape: 'puff', count: 5, colors: ['#FFB347', '#FF7A2E'], size: 0.18 });
  }

  _updateBurn(z, s, dt) {
    const g = this.game, S = SIG.hot_mic;
    s.burn -= dt;
    const per = Math.min((z.maxHp || z.hp || 100) * S.burn, s.burnCap);
    const dmg = per * dt;
    if (z.hp - dmg > 0) z.hp -= dmg;
    else {
      this._applying++;
      try { g.zombies?.damage?.(z, dmg + 1, { weaponId: s.burnWeapon || 'signal_hot_mic', cause: 'burn' }); } finally { this._applying--; }
    }
    if (s.flame) {
      this._headPos(z, _a);
      s.flame.position.copy(_a).setY(_a.y + 0.05);
      const f = 0.9 + Math.sin(g.time.now * 31 + s.seed) * 0.12 + Math.random() * 0.08;
      const fade = Math.min(1, s.burn / 0.3);
      s.flame.scale.set(f * 1.3 * fade, (2 - f) * 1.5 * fade, f * 1.3 * fade);
      s.flame.rotation.y += dt * 3;
    }
    s.fire -= dt;
    if (s.fire <= 0) {
      s.fire = 0.07;
      this._chest(z, _a).x += (Math.random() - 0.5) * 0.3;
      g.fx?.burst?.(_a, { shape: 'spark', count: 2, colors: [PAL.hotMic, '#FFE14D'], speed: 1.6, gravity: -3, life: 0.5, dir: _up, cone: 0.4 });
      if (Math.random() < 0.3) g.fx?.burst?.(_a.setY(_a.y + 0.6), { shape: 'puff', count: 1, colors: ['#5A4A5A', '#7A6A70'], size: 0.12, gravity: -1.5, life: 0.8 });
    }
    // spread: touches up to 2 zombies (one generation)
    if (s.burnLeft > 0) {
      for (const o of this._zombies()) {
        if (o === z || !this._alive(o) || this._isBoss(o)) continue;
        const os = this._status.get(o);
        if (os && os.burn > 0) continue;
        if (o.pos.distanceTo(z.pos) > (z.radius || 0.4) + (o.radius || 0.4) + 0.25) continue;
        this._ignite(o, 2, s.burnWeapon);
        if (--s.burnLeft <= 0) break;
      }
    }
    if (s.burn <= 0) {
      s.burn = 0;
      if (s.flame) { s.flame.removeFromParent(); s.flame = null; }
    }
  }

  _updatePanic(z, s, dt) {
    const g = this.game, col = g.level && g.level.col;
    s.panic -= dt;
    this._hold(z, 0.2);
    if (s.panic <= 0) {
      s.panic = 0;
      this._releaseHold(z);
      this._applyPose(z);
      return;
    }
    // run away from the player along the reversed flow field (fallback: straight away), zig-zagging
    const nav = g.nav;
    if (nav && nav.dir) nav.dir(z.pos.x, z.pos.z, _d);
    else _d.set(0, 0, 0);
    _d.negate();
    if (_d.lengthSq() < 1e-3) this._away(z.pos, _d);
    _d.applyAxisAngle(_up, Math.sin(g.time.now * 3 + s.seed) * 0.6).normalize();
    const speed = 3.4;
    if (col) {
      _a.copy(_d).multiplyScalar(speed * dt);
      _a.y = -dt;
      col.moveCircle(z.pos, _a, z.radius || 0.35, z.height || 1.6, 0.45);
    }
    const want = Math.atan2(-_d.x, -_d.z);
    z.yaw = want;
    if (z.group) {
      z.group.position.copy(z.pos);
      z.group.rotation.y = want;
    }
  }

  // LAUGH TRACK: the target and its 3 nearest zombies within 4 m fall down laughing for 4 s (x1.5 damage).
  _laughTrack(z, weaponId) {
    const S = SIG.laugh_track, g = this.game;
    const group = [z];
    const near = this._zombies().filter((o) => o !== z && this._alive(o) && !this._isBoss(o) && o.pos.distanceTo(z.pos) <= 4)
      .sort((a, b) => a.pos.distanceTo(z.pos) - b.pos.distanceTo(z.pos)).slice(0, 3);
    group.push(...near);
    this._play('crowd_laugh', { dur: 2.5, vol: 0.9 });
    for (const o of group) {
      if (this._isBoss(o)) continue;
      if (SPECIALS.has(o.type)) { this._hold(o, 1); o.animator?.kick?.(1.2); continue; }
      const s = this._stat(o);
      s.laugh = S.dur;
      s.t = 0;
      this._applyPose(o);
      this._chest(o, _a);
      g.fx?.burst?.(_a, { shape: 'star', count: 4, colors: [PAL.laughTrack, '#FFF3B0'], speed: 2.4 });
      g.fx?.text3d?.(_a.setY(_a.y + 0.9), 'HA!', PAL.laughTrack);
    }
  }

  // COLD OPEN: the target and everyone within 3 m freeze solid in ice blue for 3 s (+50 % damage).
  _coldOpen(z, weaponId) {
    const S = SIG.cold_open, g = this.game;
    const list = this._zombies().filter((o) => this._alive(o) && !this._isBoss(o) && (o === z || o.pos.distanceTo(z.pos) <= S.r));
    this._play('wonder_freeze', { pos: z.pos });
    this._floorRing(z.pos, S.r, PAL.coldOpen, 0.4, true, 0.8);
    for (const o of list) {
      if (SPECIALS.has(o.type)) {
        const s = this._stat(o);
        s.slowT = S.dur;
        this._slow(o, 'cold', 0.5);
        continue;
      }
      this._freeze(o, S.dur);
    }
  }

  _freeze(z, dur) {
    const g = this.game, R = this.res;
    const s = this._stat(z);
    s.frozen = dur;
    s.laugh = 0;
    s.panic = 0;
    this._hold(z, dur);
    if (!s.iced) {
      s.iced = [];
      z.group?.traverse((o) => { if (o.isMesh && o.material !== R.mIce) { s.iced.push([o, o.material]); o.material = R.mIce; } });
    }
    if (s.prevUpdate === undefined && z.animator && typeof z.animator.update === 'function') {
      s.prevUpdate = Object.prototype.hasOwnProperty.call(z.animator, 'update') ? z.animator.update : null;
      z.animator.update = () => {};
    }
    this._applyPose(z);
    this._chest(z, _a);
    g.fx?.burst?.(_a, { shape: 'puff', count: 6, colors: ['#E6F8FF', '#BFEFFF'], size: 0.2, life: 0.6 });
    g.fx?.burst?.(_a, { shape: 'star', count: 4, colors: ['#FFFFFF', PAL.coldOpen], speed: 2 });
  }

  // Frozen zombies that die shatter into ice cubes.
  _shatter(z, s) {
    const g = this.game;
    this._unfreeze(z, s);
    this._hide(z);
    this._chest(z, _a);
    const h = z.height || 1.6;
    for (let i = 0; i < 22; i++) {
      const it = this.pools.debris.spawn();
      it.pos.set(z.pos.x + (Math.random() - 0.5) * 0.6, z.pos.y + 0.2 + Math.random() * h * 0.9, z.pos.z + (Math.random() - 0.5) * 0.6);
      it.vel.set((Math.random() - 0.5) * 5, 2 + Math.random() * 4, (Math.random() - 0.5) * 5);
      it.rot.set(Math.random() * TAU, Math.random() * TAU, 0);
      it.spin.set((Math.random() - 0.5) * 14, (Math.random() - 0.5) * 14, 0);
      it.t = 0;
      it.life = 1.2 + Math.random() * 0.6;
      it.size = 0.07 + Math.random() * 0.1;
      it.floor = z.pos.y;
      it.c.set(['#BFE6FF', '#8FCBF2', '#DDF3FF'][Math.floor(Math.random() * 3)]).multiplyScalar(0.85);
    }
    this._play('wonder_shatter', { pos: _a });
    g.fx?.burst?.(_a, { shape: 'star', count: 8, colors: ['#FFFFFF', PAL.coldOpen], speed: 4 });
    g.fx?.burst?.(_a, { shape: 'puff', count: 6, colors: ['#E6F8FF'], size: 0.22 });
    this._clearStatus(z);
  }

  // ------------------------------------------------------------------------------------------ pools
  _updatePools(dt) {
    const P = this.pools;
    const ring = (it, d) => {
      it.t += d;
      const t = it.t - it.delay;
      if (t < 0) { it.m.copy(ZERO_M); it.c.setRGB(0, 0, 0); return true; }
      const k = clamp01(t / it.dur);
      if (it.kind === 'grow') {
        const s = lerp(it.s0, it.s1, E.outCubic(k));
        it.m.compose(it.from, it.q, _s.set(s, s, s));
      } else {
        _p.lerpVectors(it.from, it.to, it.kind === 'cone' ? E.outQuad(k) : k);
        const s = lerp(it.s0, it.s1, it.kind === 'cone' ? E.outQuad(k) : k);
        it.m.compose(_p, it.q, _s.set(s, s, s));
      }
      const f = it.kind === 'cone' ? (1 - k) * (1 - k) * Math.min(1, k / 0.18) : (1 - k * k);
      it.c.copy(it.base).multiplyScalar(f);
      return k < 1;
    };
    P.rings.update(dt, ring);
    P.bold.update(dt, ring);
    const tip = this._micTip;
    P.squig.update(dt, (it, d) => {
      it.t += d;
      const k = clamp01(it.t / it.dur);
      const e = E.inQuad(k);
      _p.lerpVectors(it.from, tip, e);
      _a.subVectors(tip, it.from);
      const len = _a.length() || 1;
      _a.divideScalar(len);
      _b.crossVectors(_a, _up).normalize();
      _p.addScaledVector(_b, Math.sin(k * Math.PI) * 0.35 * Math.sin(it.seed)).y += Math.sin(k * Math.PI) * 0.25;
      _q.setFromUnitVectors(_zAxis, _a);
      _q.multiply(_q2.setFromAxisAngle(_zAxis, it.t * 14 + it.seed));
      const s = (k < 0.15 ? k / 0.15 : 1 - E.inQuad(seg(k, 0.6, 1)) * 0.8) * 1.4;
      it.m.compose(_p, _q, _s.set(s, s, s * (0.8 + Math.sin(it.t * 30) * 0.2)));
      it.c.copy(it.base).multiplyScalar(k > 0.85 ? (1 - k) / 0.15 : 1);
      return k < 1;
    });
    P.debris.update(dt, (it, d) => {
      it.t += d;
      it.vel.y -= 14 * d;
      it.pos.addScaledVector(it.vel, d);
      if (it.pos.y < it.floor + it.size * 0.5) {
        it.pos.y = it.floor + it.size * 0.5;
        it.vel.y = Math.abs(it.vel.y) * 0.35;
        it.vel.x *= 0.6;
        it.vel.z *= 0.6;
        it.spin.multiplyScalar(0.6);
      }
      it.rot.x += it.spin.x * d;
      it.rot.y += it.spin.y * d;
      _q.setFromEuler(it.rot);
      const s = it.size * (it.t > it.life - 0.3 ? Math.max(0.001, (it.life - it.t) / 0.3) : 1);
      it.m.compose(it.pos, _q, _s.set(s, s, s));
      return it.t < it.life;
    });
    const splat = (it, d) => {
      it.t += d;
      const fadeT = Math.min(1, it.dur * 0.3);
      const out = seg(it.t, it.dur - fadeT, it.dur);
      const a = 1 - out * out * (3 - 2 * out);
      const s = it.size * (0.55 + 0.45 * E.outBack(clamp01(it.t / 0.14), 2.2)) * (1 - 0.12 * out);
      it.m.compose(it.pos, it.q, _s.set(s, s, 1));
      it.c.setRGB(a, a, a);                    // instanceColor.r = opacity (alphaFromInstance)
      return it.t < it.dur;
    };
    P.splat.update(dt, splat);
    P.splatUp.update(dt, splat);
  }

  // ------------------------------------------------------------------------------------------ debug
  _makeDebug() {
    const self = this;
    const find = (z) => (typeof z === 'number' ? self._zombies().find((o) => o.id === z) : z) || null;
    return {
      trigger(down) {
        self._dbgTrigger = down === null || down === undefined ? null : !!down;
        if (self._dbgTrigger === null) self._dbgPrev = false;
      },
      gag(z, name = 'cartoon') {
        const zz = find(z);
        if (!zz || !self._alive(zz)) return false;
        const P = self._doom(zz, () => self._kill(zz, 'zapper', 'zapper'));
        if (!P) return false;
        self._gag(zz, GAGS.includes(name) ? name : 'cartoon', false, P);
        return true;
      },
      key(z, world = 'beach', up = false) {
        const zz = find(z);
        if (!zz || !self._alive(zz)) return false;
        const P = self._doom(zz, () => self._kill(zz, 'chroma_key', 'chroma_key'));
        if (!P) return false;
        self._keyed(zz, up, world, P);
        return true;
      },
      tumble(z) {
        const zz = find(z);
        if (!zz || !self._alive(zz)) return false;
        const P = self._doom(zz, () => self._kill(zz, 'boom_mic', 'boom_mic'));
        if (!P) return false;
        self._tumble(zz, self._away(zz.pos, new THREE.Vector3()), 0, P);
        return true;
      },
      tele(x, z) {
        const t = self._spawnTele();
        if (t && x !== undefined) {
          t.pos.set(x, (self._floorY(x, z, 50) ?? 0) + 1.5, z);
          t.vel.set(0, 0, 0);
        }
        return !!t;
      },
      // Advances wonder's effects (and game.fx) by `seconds` in fixed steps: deterministic screenshots with time.scale 0.
      step(seconds = 0.1, h = 1 / 60) {
        const g = self.game;
        for (let t = 0; t < seconds - 1e-6; t += h) {
          const d = Math.min(h, seconds - t);
          FXU.time.value += d;
          self._updateWeaponState(d);
          self._updateBlobs(d);
          self._updatePuddles(d);
          self._updateTeles(d);
          self._updateStatus(d);
          self._updateActors(d);
          self._updateHidden(d);
          self._updatePools(d);
          g.fx?.update?.(d);
        }
        g.fx?.lateUpdate?.(0);
        return self.debug.state();
      },
      signal(z, s) { return self.applySignal(find(z), s, { weaponId: 'debug' }); },
      burn(z) { return self.applySignal(find(z), 'hot_mic'); },
      laugh(z) { return self.applySignal(find(z), 'laugh_track'); },
      freeze(z) { return self.applySignal(find(z), 'cold_open'); },
      state() {
        return {
          delegated: self._delegated, reloading: self.reloading, reloadId: self.reloadId, recording: self.recording, charge: +self.charge.toFixed(2),
          actors: self._actors.length, hidden: self._hidden.size, status: self._status.size, blobs: self._blobs.length, puddles: self._puddles.length,
          teles: self.teles.map((t) => ({ state: t.state, pos: t.pos.toArray().map((n) => +n.toFixed(2)), seated: t.seated.size, live: +t.live.toFixed(2),
            yaw: +t.yaw.toFixed(3), sat: [...t.seated].filter((z) => { const s = self._seatOf(z); return s && (s.plopped || s.stand); }).length })),
          lastZap: self._lastZap || null,
          puddleAt: self._puddles.map((p) => p.pos.toArray().map((n) => +n.toFixed(2))),
          splats: self.pools.splat.items.filter((i) => i.alive).length + self.pools.splatUp.items.filter((i) => i.alive).length,
        };
      },
    };
  }
}

// One-line hook for Game (see the header). Returns game.wonder.
export function install(game) {
  if (game.wonder && game.wonder instanceof Wonder) return game.wonder;
  const w = new Wonder(game);
  game.wonder = w;
  const hook = () => {
    try { w.update(game.time.dt); } catch (err) {
      const now = performance.now();
      if (!w._errT || now - w._errT > 5000) { w._errT = now; console.error('[system:wonder]', err); }
    }
  };
  const attach = () => {
    if (w._hooked || !game.render || typeof game.render.addPrePass !== 'function') return false;
    w._hooked = true;
    try { w.init(); } catch (err) { console.error('[system:wonder]', err); }
    game.render.addPrePass(hook);
    return true;
  };
  if (!attach()) setTimeout(attach, 0);
  return w;
}
