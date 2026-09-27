// Weapon models for the game (GDD §9.1 art rule, §9.5 Chromacast) — owned by the weapons engineer.
// Thin wrapper over the prop library (src/props/weapons.js, the modelled chunky toys) in the HAND convention:
// grip (palm centre of the right hand) at the origin, barrel along -Z, top +Y, a child Object3D named 'muzzle'
// at the barrel tip, userData.leftHand [x,y,z] support-hand point, userData.parts {drum, pump, mag, cover, battery,
// reelL, reelR, needle, goo, filament, antenna...} animatable sub-groups, userData.butt [x,y,z] (rear-most point:
// the stock end that sits on the shoulder), userData.weapon { id, upgraded, signal }.
//
//   buildModel(id, upgraded=false, signal=null, game=window.__game) -> Group   (a fresh clone each call; the
//     prop library caches the prototype, geometry and materials are shared). Upgraded = Chromacast finish + medal,
//     rabbit ears, tail fins, extra chrome (biased to the signal colour when given: hot_mic|laugh_track|cold_open).
//   buildWeaponModel(id, upgraded, game)   alias kept from the stub (same result, no signal).
//   buildMeleeProp(heroId, game) -> Group | null     hero melee prop (walkie / LP / wrench; Duke chops bare-handed)
//   buildGrenadeModel(game) -> Group                 tube grenade (filament part flickers)
//   buildTeleModel(game) -> Group                    Tiny Tele for the left hand during the Q wind-up
//   modelInfo(group) -> { muzzle:Vector3, leftHand:Vector3, butt:Vector3, parts }  (local, unscaled)
//   chromacast(game, signal|colour) -> Material      a standalone Chromacast toon material (world-space gradient)
//     for anything that is not a prop weapon (Uplink copies, Telly previews...). Installed as game.mats.chromacast
//     by weapons.js when the engine lacks it (ARCHITECTURE §12 assigns mats.chromacast to weapons).
// If the prop library throws (parallel development), a chunky primitive placeholder with the same convention is
// returned so the game keeps running.

import * as THREE from 'three';
import * as geo from '../core/geo.js';
import { PAL } from '../core/config.js';
import { buildWeapon } from '../props/weapons.js';
import { SIGNAL_COLORS } from './weaponDefs.js';

const _box = new THREE.Box3();
const _v = new THREE.Vector3();

function annotate(g, id, upgraded, signal) {
  const u = g.userData;
  if (!g.getObjectByName('muzzle')) {
    const m = new THREE.Object3D();
    m.name = 'muzzle';
    m.position.fromArray(u.muzzle || [0, 0.08, -0.3]);
    g.add(m);
  }
  if (!u.leftHand) u.leftHand = [0, 0, -0.15];
  if (!u.butt) {
    g.updateMatrixWorld(true);
    _box.makeEmpty();
    g.traverse((o) => { if (o.isMesh && !o.isInstancedMesh) _box.expandByObject(o); });
    const inv = new THREE.Matrix4().copy(g.matrixWorld).invert();
    const max = _v.copy(_box.max).applyMatrix4(inv);
    u.butt = [0, (u.muzzle ? u.muzzle[1] : 0.08) * 0.85, Math.max(0.02, max.z)];
  }
  u.parts = u.parts || {};
  u.weapon = { ...(u.weapon || {}), id, upgraded: !!upgraded, signal: signal || null };
  g.name = `weapon:${id}${upgraded ? ':up' : ''}`;
  return g;
}

export function buildModel(id, upgraded = false, signal = null, game = globalThis.__game) {
  let g;
  try {
    const opts = { upgraded: !!upgraded, pose: 'hand' };
    if (upgraded && signal) opts.signal = signal;
    g = buildWeapon(id, opts, game);
  } catch (err) {
    console.warn(`[weaponModels] prop '${id}' failed, using a placeholder`, err);
    g = placeholder(id, upgraded, game);
  }
  return annotate(g, id, upgraded, signal);
}

export function buildWeaponModel(id, upgraded = false, game = globalThis.__game) {
  return buildModel(id, upgraded, null, game);
}

export function buildMeleeProp(heroId, game = globalThis.__game) {
  const id = { skip: 'melee_walkie', roxy: 'melee_lp', penny: 'melee_wrench' }[heroId];
  if (!id) return null;
  try {
    return buildWeapon(id, { pose: 'hand' }, game);
  } catch (err) {
    return null;
  }
}

export function buildGrenadeModel(game = globalThis.__game) {
  try {
    return buildWeapon('tube_grenade', { pose: 'hand' }, game);
  } catch (err) {
    const g = new THREE.Group();
    g.add(geo.mesh(geo.capsule(0.035, 0.07, 6, 10), game.mats.glass('#DDEEFF', { opacity: 0.4 }), { pos: [0, 0.07, 0] }));
    g.add(geo.mesh(geo.sphere(0.018, 8, 6), game.mats.glow('#FF8A2E', 3), { pos: [0, 0.07, 0] }));
    g.userData.parts = {};
    return g;
  }
}

// Tiny Tele held in the left hand during the Q wind-up (antenna folded). Placeholder: an orange box TV.
export function buildTeleModel(game = globalThis.__game) {
  try {
    return buildWeapon('tiny_tele', { pose: 'hand' }, game);
  } catch (err) {
    const g = new THREE.Group();
    g.add(geo.mesh(geo.roundedBox(0.2, 0.16, 0.16, 0.03, 2), game.mats.toon('#F08A2E', { keepColor: true }), { pos: [0, 0.08, 0] }));
    g.add(geo.mesh(geo.roundedBox(0.14, 0.1, 0.01, 0.01, 1), game.mats.glow('#CFE8FF', 1.2), { pos: [0, 0.09, -0.081] }));
    g.userData.parts = {};
    return g;
  }
}

export function modelInfo(group) {
  const u = group.userData || {};
  const m = group.getObjectByName('muzzle');
  return {
    muzzle: m ? m.position.clone() : new THREE.Vector3(0, 0.08, -0.3),
    leftHand: new THREE.Vector3().fromArray(u.leftHand || [0, 0, -0.15]),
    butt: new THREE.Vector3().fromArray(u.butt || [0, 0.08, 0.05]),
    parts: u.parts || {},
  };
}

// ------------------------------------------------------------------------------------------ placeholder model
const LOOKS = {
  revolver_38: { len: 0.3, body: '#3A4A6B', stock: PAL.walnut, h: 0.08 },
  pump_37: { len: 0.78, body: '#3A4A6B', stock: PAL.teak, h: 0.07 },
  mp7: { len: 0.42, body: '#62703A', stock: '#4B5530', h: 0.09 },
  m16a1: { len: 0.82, body: '#39405C', stock: '#62868A', h: 0.09 },
  m60: { len: 1.0, body: '#5E6838', stock: '#3A3A2A', h: 0.12 },
  zapper: { len: 0.4, body: '#EBDCBC', stock: PAL.walnut, h: 0.06 },
  boom_mic: { len: 1.1, body: '#C9CED6', stock: '#2A2230', h: 0.05 },
  chroma_key: { len: 0.55, body: '#D6D0C4', stock: '#5A3A22', h: 0.14 },
};

function placeholder(id, upgraded, game) {
  const M = game.mats;
  const look = LOOKS[id] || LOOKS.revolver_38;
  const g = new THREE.Group();
  const tone = (c) => M.toon(c, { keepColor: true, rough: 0.45 });
  const L = look.len, h = look.h;
  g.add(geo.mesh(geo.roundedBox(0.05, 0.12, 0.06, 0.02, 2), tone(look.stock), { pos: [0, -0.03, 0.01], rot: [-0.25, 0, 0] }));
  g.add(geo.mesh(geo.roundedBox(0.07, h, L * 0.45, 0.025, 2), upgraded ? chromacast(game, null) : tone(look.body), { pos: [0, 0.06, -L * 0.12] }));
  g.add(geo.mesh(geo.cylinder(0.022, 0.022, L * 0.5, 12), tone('#3A4A6B'), { pos: [0, 0.07, -L * 0.55], rot: [Math.PI / 2, 0, 0] }));
  if (L > 0.6) g.add(geo.mesh(geo.roundedBox(0.06, 0.09, L * 0.3, 0.025, 2), tone(look.stock), { pos: [0, 0.03, L * 0.2] }));
  g.userData.muzzle = [0, 0.07, -L * 0.8];
  g.userData.leftHand = L > 0.5 ? [0, 0.03, -L * 0.45] : [-0.03, -0.02, 0];
  return g;
}

// ------------------------------------------------------------------------------------------ chromacast material
const CC_FRAG_PARS = /* glsl */`#include <common>
varying vec3 vCcPos;
uniform float uCcHue;
uniform float uCcSpread;
vec3 ccHue( float h ) {
  vec3 k = clamp( abs( mod( h * 6.0 + vec3( 0.0, 4.0, 2.0 ), 6.0 ) - 3.0 ) - 1.0, 0.0, 1.0 );
  return k * k * ( 3.0 - 2.0 * k );
}
float ccHash( vec3 p ) { p = fract( p * 0.3183099 + vec3( 0.71, 0.113, 0.419 ) ); p *= 17.0; return fract( p.x * p.y * p.z * ( p.x + p.y + p.z ) ); }`;
const CC_FRAG_COLOR = /* glsl */`#include <color_fragment>
vec3 ccEm = vec3( 0.0 );
{
  float t = dot( vCcPos, vec3( 0.7, 0.35, 0.6 ) ) * 2.2;
  float hue = uCcSpread > 0.9 ? t - uTime * 0.1 + uCcHue : uCcHue + uCcSpread * sin( t * 5.5 - uTime * 0.8 );
  vec3 cc = ccHue( fract( hue ) );
  float s = t * 22.0 - uTime * 2.0;
  float grp = mod( floor( s ), 17.0 );
  float band = step( grp, 6.5 ) * smoothstep( 0.0, 0.1, fract( s ) ) * ( 1.0 - smoothstep( 0.9, 1.0, fract( s ) ) );
  cc = mix( cc, uBars[ int( mod( grp, 7.0 ) ) ], band * 0.7 );
  diffuseColor.rgb *= cc;
  ccEm = cc * 0.3;
  float sp = ccHash( floor( vCcPos * 150.0 ) );
  ccEm += vec3( 1.0, 0.96, 0.88 ) * step( 0.972, sp ) * pow( max( 0.0, sin( uTime * 3.3 + sp * 91.0 ) ), 3.0 ) * 2.2;
}`;

const _ccCache = new Map();
export function chromacast(game, signal = null) {
  const col = signal ? (SIGNAL_COLORS[signal] || signal) : null;
  const key = col || 'rainbow';
  if (_ccCache.has(key)) return _ccCache.get(key);
  const m = game.mats.toon('#ffffff', { rough: 0.26, metal: 0.18, rim: 0.32, rimColor: '#FFFFFF', keepColor: true, name: `chromacast|${key}` });
  const hsl = { h: 0, s: 0, l: 0 };
  if (col) new THREE.Color(col).getHSL(hsl);
  const u = { uCcHue: { value: col ? hsl.h : 0 }, uCcSpread: { value: col ? 0.1 : 1 } };
  patchCC(m, u);
  // the player swaps held materials to their heroFade variant: pre-patch that cached instance too
  patchCC(game.mats.variant(m, { heroFade: true }), u);
  _ccCache.set(key, m);
  return m;
}

function patchCC(m, u) {
  if (!m || m.userData.chromacast) return;
  m.userData.chromacast = u;
  const orig = m.onBeforeCompile;
  m.onBeforeCompile = (sh, r) => {
    if (orig) orig.call(m, sh, r);
    Object.assign(sh.uniforms, u);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vCcPos;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvCcPos = position;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', CC_FRAG_PARS)
      .replace('#include <color_fragment>', CC_FRAG_COLOR)
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\ntotalEmissiveRadiance += ccEm;');
  };
  m.customProgramCacheKey = () => 'datoon1-chromacast1';
  m.needsUpdate = true;
}
