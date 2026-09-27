// BIG SHOT (`big_shot`, the camera operator fused with his studio pedestal) type module — GDD §8.4, §5.9, §10.0.
// Owned by the zombies-specials agent. Contract: the TYPE MODULE CONTRACT in src/actors/zombieTypes.js (id, hp,
// speed, build, release, update -> true, updateEntry, entryFilter/entry, hitTest, onDamage, onDeath/updateDeath,
// warmup, points, oneTakeMul).
//
// Look: the sculpted z_bigshot (custom rig base -> column -> torso -> head + arms), baked. Runtime parts: caster wheels
//   that roll and swivel, the red tally lamp (blinks), a lens iris + glow at 'lensFront', a flash sprite, and the
//   trailing CABLE (verlet rope, one dynamic tube) ending in a PLUG with glowing prongs (his weak point).
// Behaviour (T.zombies.bigShot):
//   - Rolls at 1.6 m/s (heavy turning, bs_roll loop). Enters through boarded windows / the gate: blows every board out
//     at once (the manager's 'blast' entry + a flashbulb pop here) and squeezes through like toothpaste (1.5 s).
//   - DOLLY RUSH (within 12 m with line of sight, 8 s cooldown): 1.0 s telegraph (wheels screech and spin in place,
//     tally blinks, he rears back, dust), then charges straight at 9 m/s for up to 1.5 s: 70 damage + 4 m knockback
//     (zombie:attack {z, dmg, kind:'rush'}), bowls other zombies aside. Hitting a wall: bs_wall_bonk, DIZZY 2 s (the
//     camera head spins, stars; manager stun) and ×1.5 damage from every side meanwhile. Otherwise a smoking skid.
//   - FLASH (9 s cooldown, 20 m, line of sight): 1.0 s wind-up (the lens iris opens with the rising whine), then POP:
//     if the player's camera forward is within 60° of the direction to him, a 1.5 s whiteout (hud.whiteout, else
//     render.post.whiteout) + 20 damage, and every decorative TV freezes on the flinch frame for 3 s
//     (screens.override('flinch', …, 3)). Looking away fully negates it. Emits 'zombie:flash' { z, pos, hit }.
//   - Close bump (not in the GDD list, keeps him dangerous when hugged): 0.5 s rear-back, lurch, 35 damage, 2 s cd.
// Damage (onDamage): shots from his front (the camera housing faces the shot, within 60°) ×0.4, sides/back ×1, the
//   PLUG ×3 (its own shootable 'bs_plug_<z.id>' routed into zombies.damage with zone 'plug', head:true = gold
//   hitmarker), dizzy ×1.5 from every side. ONE TAKE ×5 (oneTakeMul, applied by the manager).
// Death (onDeath -> 2.4 s): the camera head pops in a giant flashbulb burst (bs_death, flash light, mild screen flash,
//   glass sparks), film unspools everywhere as tube spaghetti (12 simulated film strips), the pedestal telescopes down
//   and tips over, static dissolve. +500 (points.killBonus). His FIRST death each game drops FULL REEL
//   (powerups.dropGuaranteed('full_reel', pos), else powerups.drop).
// Debug: z.def.forceRush(game, z), z.def.forceFlash(game, z), z.def.plugOf(z) -> world position of the plug.

import * as THREE from 'three';
import { T, LAYERS } from '../../core/config.js';
import { Spring } from '../../core/rig.js';
import { skinRig } from '../../core/geo.js';
import * as geo from '../../core/geo.js';
import * as charRuntime from '../../art/charRuntime.js';
import BAKED from '../../../assets/baked/registry.js';
import bsDef from '../../art/chars/z_bigshot.js';
import { zombieEyeMaterial } from '../zombieTypes.js';
import { registerSpecialTint } from './sock_hopper.js';

const B = T.zombies.bigShot;
const RU = B.rush, FL = B.flash;
const R = T.rounds;
const G = 22;
const TURN = 2.6;             // rad/s max yaw rate while rolling (heavy)
const RADIUS = 0.55;
const HEIGHT = 2.2;
const WHEEL_R = 0.062;
const BUMP = { range: 1.7, windup: 0.5, dmg: Math.round(RU.dmg / 2), cd: 2.0 };
const ABILITY_GAP = 1.6;
const CABLE_N = 11, CABLE_SEG = 0.13, CABLE_R = 0.022;
const FILM_N = 12, FILM_P = 9;
const DEATH = 2.4;

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _d = new THREE.Vector3();
const _e = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _m4 = new THREE.Matrix4();
const _up = new THREE.Vector3(0, 1, 0);
const _hit = { dist: 0, zone: 'torso', head: false, mul: 1 };

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (x) => { x = clamp01(x); return x * x * (3 - 2 * x); };
const lerp = (a, b, t) => a + (b - a) * t;
const easeOutBack = (x) => { x = clamp01(x); const c = 1.7; return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2; };
const easeOutCubic = (x) => 1 - (1 - clamp01(x)) ** 3;
const easeOutBounce = (x) => {
  x = clamp01(x);
  const n = 7.5625, d = 2.75;
  if (x < 1 / d) return n * x * x;
  if (x < 2 / d) return n * (x -= 1.5 / d) * x + 0.75;
  if (x < 2.5 / d) return n * (x -= 2.25 / d) * x + 0.9375;
  return n * (x -= 2.625 / d) * x + 0.984375;
};
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const yawTo = (dx, dz) => Math.atan2(-dx, -dz);
const hpAt = (r) => (r <= 9 ? R.hpEarlyBase + R.hpEarlyStep * (Math.max(1, r) - 1)
  : Math.min(R.hpCap, Math.round((R.hpEarlyBase + R.hpEarlyStep * 8) * R.hpMul ** (r - 9))));

// Ray helpers (o origin, d unit dir) -> distance or Infinity.
function raySphere(o, d, c, r) {
  _e.subVectors(o, c);
  const b = _e.dot(d), q = _e.lengthSq() - r * r, disc = b * b - q;
  if (disc < 0) return Infinity;
  const t = -b - Math.sqrt(disc);
  return t >= 0 ? t : (q < 0 ? 0 : Infinity);
}
const _ba = new THREE.Vector3(), _oa = new THREE.Vector3();
function rayCapsule(o, d, a, b, r) {
  _ba.subVectors(b, a); _oa.subVectors(o, a);
  const baba = _ba.lengthSq(), bard = _ba.dot(d), baoa = _ba.dot(_oa), rdoa = d.dot(_oa), oaoa = _oa.lengthSq();
  const qa = baba - bard * bard, qb = baba * rdoa - baoa * bard, qc = baba * oaoa - baoa * baoa - r * r * baba;
  if (qa < 1e-9) return raySphere(o, d, a, r);
  const h = qb * qb - qa * qc;
  if (h < 0) return Infinity;
  const t = (-qb - Math.sqrt(h)) / qa;
  const y = baoa + t * bard;
  if (y > 0 && y < baba) return t >= 0 ? t : (qc < 0 ? 0 : Infinity);
  return raySphere(o, d, y <= 0 ? a : b, r);
}

function weaponHeadMul(g, weaponId) {
  if (!weaponId) return 1;
  const w = g.weapons;
  const d = w && w.defs && w.defs[weaponId];
  const h = d && Number(d.head);
  return h > 0 ? h : 1;
}

// ------------------------------------------------------------------------------------------------ shared assets
let flareTex = null, filmTex = null, filmMat = null, bladeGeo = null, plugAssets = null;
let warned = false;
const pool = [];
const games = new WeakMap();   // game -> { reelDropped }

function gameState(game) {
  let s = games.get(game);
  if (!s) {
    s = { reelDropped: false };
    games.set(game, s);
    game.events.on('game:start', () => { s.reelDropped = false; });
    // rolling loops go quiet while the zombies are frozen (PLEASE STAND BY) or the game is paused
    try {
      game.render.addPrePass(() => {
        const Zs = game.zombies;
        if (!Zs || !(Zs.frozen || !(game.time.dt > 0))) return;
        for (const z of Zs.alive) if (z.type === 'big_shot' && z.flags.rollSnd && z.flags.rollSnd.setVol) { try { z.flags.rollSnd.setVol(0, 0.1); } catch (err) { /* optional */ } }
      });
    } catch (err) { /* optional */ }
  }
  return s;
}

function flareTexture() {
  if (flareTex) return flareTex;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const grd = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grd.addColorStop(0, 'rgba(255,255,255,1)');
  grd.addColorStop(0.2, 'rgba(255,250,235,0.9)');
  grd.addColorStop(0.5, 'rgba(255,236,200,0.35)');
  grd.addColorStop(1, 'rgba(255,230,190,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, 128, 128);
  // 6-point star streaks
  g.globalCompositeOperation = 'lighter';
  g.strokeStyle = 'rgba(255,255,255,0.55)';
  g.lineWidth = 3;
  for (let i = 0; i < 3; i++) {
    const a = (i * Math.PI) / 3;
    g.beginPath(); g.moveTo(64 - Math.cos(a) * 62, 64 - Math.sin(a) * 62); g.lineTo(64 + Math.cos(a) * 62, 64 + Math.sin(a) * 62); g.stroke();
  }
  flareTex = new THREE.CanvasTexture(c);
  flareTex.colorSpace = THREE.SRGBColorSpace;
  return flareTex;
}

function filmAssets() {
  if (filmMat) return;
  const c = document.createElement('canvas');
  c.width = 64; c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#3A2418'; g.fillRect(0, 0, 64, 256);
  g.fillStyle = '#6B4A30';
  for (let y = 0; y < 256; y += 64) g.fillRect(14, y + 6, 36, 52);           // frames
  g.fillStyle = '#E8D8B8';
  for (let y = 4; y < 256; y += 16) { g.fillRect(3, y, 6, 8); g.fillRect(55, y, 6, 8); }   // sprocket holes
  filmTex = new THREE.CanvasTexture(c);
  filmTex.colorSpace = THREE.SRGBColorSpace;
  filmTex.wrapT = THREE.RepeatWrapping;
  filmMat = new THREE.MeshStandardMaterial({ map: filmTex, side: THREE.DoubleSide, roughness: 0.35, metalness: 0.1 });
  filmMat.name = 'bsFilm';
}

function bladeGeometry() {
  if (bladeGeo) return bladeGeo;
  const parts = [];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    const g = new THREE.BoxGeometry(0.075, 0.016, 0.004);
    g.translate(0, 0.075, 0);
    g.rotateZ(a + 0.5);
    parts.push(g);
  }
  bladeGeo = mergeSimple(parts);
  return bladeGeo;
}

function mergeSimple(list) {
  let nv = 0, ni = 0;
  for (const g of list) { nv += g.attributes.position.count; ni += g.index.count; }
  const pos = new Float32Array(nv * 3), nrm = new Float32Array(nv * 3), idx = new Uint32Array(ni);
  let ov = 0, oi = 0;
  for (const g of list) {
    pos.set(g.attributes.position.array, ov * 3);
    nrm.set(g.attributes.normal.array, ov * 3);
    const I = g.index.array;
    for (let k = 0; k < I.length; k++) idx[oi + k] = I[k] + ov;
    ov += g.attributes.position.count; oi += I.length;
    g.dispose();
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  return out;
}

function getPlugAssets(game) {
  if (plugAssets) return plugAssets;
  const M = game.mats;
  plugAssets = {
    body: geo.roundedBox(0.075, 0.062, 0.1, 0.02, 2),
    prong: mergeSimple([-1, 1].map((s) => new THREE.BoxGeometry(0.012, 0.028, 0.05).translate(s * 0.018, 0, -0.07))),
    rubber: M.toon('#26232A', { rough: 0.6, keepColor: true, rim: 0.35 }),
    cable: M.toon('#1F1C22', { rough: 0.55, keepColor: true, rim: 0.3, name: 'bsCable' }),
  };
  return plugAssets;
}

// ------------------------------------------------------------------------------------------------ model
function hasBaked(game) {
  return !(game.params && game.params.art === 0) && !!BAKED.z_bigshot && typeof charRuntime.buildCharacter === 'function';
}

function buildBakedRig(game) {
  const M = game.mats;
  const c = charRuntime.buildCharacter(bsDef, { envMap: M.envMap, globals: M.uniforms, layer: LAYERS.ZOMBIES, animator: false });
  const eyes = zombieEyeMaterial();
  const wheels = [], casters = [];
  let tally = null, lens = null;
  c.group.traverse((o) => {
    if (o.isMesh && o.userData.staticEye) o.material = eyes;
    if (o.isMesh) o.castShadow = !!o.isSkinnedMesh;
    if (o.userData.wheel) { wheels.push(o); o.userData.noMerge = true; }
    if (o.userData.caster) { casters.push(o); o.userData.noMerge = true; }
    if (o.userData.tally) { tally = o; o.userData.noMerge = true; }
    if (o.name === 'lensFront') lens = o;
  });
  // Casters (swivel) and wheels (spin) join the body's skeleton as extra bones: 9 caster meshes -> 3 skinned draws,
  // one skeleton per Big Shot. charOpt.merge off: the older geo.skinRig (own skeleton, A/B).
  const extra = {};
  casters.forEach((o, i) => { extra['caster' + i] = o; });
  wheels.forEach((o, i) => { extra['wheel' + i] = o; });
  try {
    if (charRuntime.charOpt && charRuntime.charOpt.merge) charRuntime.mergeAttachments(c, { bones: Object.values(extra) });
    else skinRig({ root: c.rig.root, joints: { ...c.rig.joints, ...extra }, dims: c.rig.dims });
  } catch (err) { if (!warned) { warned = true; console.warn('[big_shot] attachment merge failed', err); } }
  const bodies = [];
  c.group.traverse((o) => { if (o.isSkinnedMesh) { if (o === c.skinnedMesh) bodies.push(o); else o.castShadow = false; } });
  if (c.skinnedMesh) registerSpecialTint(game, c.skinnedMesh.material);
  return { group: c.group, rig: c.rig, J: c.rig.joints, wheels, casters, tally, lens, bodies, baked: true };
}

// art=0 / no bake: a chunky primitive pedestal + boxy camera on the same joints.
function buildPlaceholderRig(game) {
  const M = game.mats;
  const toy = (c, o = {}) => M.toon(c, { rough: 0.5, rim: 0.4, rimColor: '#8FF3FF', keepColor: true, ...o });
  const root = new THREE.Group();
  root.name = 'rig';
  const J = {};
  const mk = (n, parent, p) => { const o = new THREE.Object3D(); o.name = n; o.position.set(...p); parent.add(o); J[n] = o; return o; };
  mk('base', root, [0, 0, 0]); mk('column', J.base, [0, 0.2, 0]); mk('torso', J.column, [0, 0.74, 0]); mk('head', J.torso, [0, 0.56, 0]);
  for (const s of [-1, 1]) { const S = s < 0 ? 'L' : 'R'; mk('shoulder' + S, J.torso, [s * 0.3, 0.42, 0.02]); mk('elbow' + S, J['shoulder' + S], [s * 0.08, -0.22, -0.1]); mk('hand' + S, J['elbow' + S], [-s * 0.06, -0.04, -0.22]); }
  J.base.add(geo.mesh(geo.cylinder(0.45, 0.5, 0.08, 3), toy('#40464F'), { pos: [0, 0.12, 0] }));
  J.column.add(geo.mesh(geo.cylinder(0.09, 0.1, 0.7, 12), toy('#40464F'), { pos: [0, 0.35, 0] }));
  J.torso.add(geo.mesh(geo.sphere(0.3, 16, 12), toy('#E0532C'), { pos: [0, 0.25, 0], scale: [1, 0.9, 0.85] }));
  J.head.add(geo.mesh(geo.roundedBox(0.44, 0.45, 0.6, 0.08, 2), toy('#5C7E97'), { pos: [0, 0.29, 0.03] }));
  J.head.add(geo.mesh(geo.cylinder(0.11, 0.11, 0.3, 16), toy('#232126'), { pos: [0, 0.2, -0.4], rot: [Math.PI / 2, 0, 0] }));
  const tallyMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#FF2A1E').multiplyScalar(1.6) });
  const tally = geo.mesh(geo.sphere(0.055, 12, 8), tallyMat, { pos: [0, 0.535, -0.02], cast: false });
  J.head.add(tally);
  const lens = new THREE.Object3D(); lens.name = 'lensFront'; lens.position.set(0, 0.205, -0.57); J.head.add(lens);
  const wheels = [], casters = [];
  for (let i = 0; i < 3; i++) {
    const a = Math.PI + (i * Math.PI * 2) / 3;
    const sw = new THREE.Group(); sw.position.set(Math.sin(a) * 0.4, 0.062, Math.cos(a) * 0.4); J.base.add(sw); casters.push(sw);
    const w = new THREE.Group(); sw.add(w); wheels.push(w);
    w.add(geo.mesh(new THREE.CylinderGeometry(0.062, 0.062, 0.042, 14).rotateZ(Math.PI / 2), toy('#1E1C20'), { cast: false }));
  }
  const group = new THREE.Group();
  group.add(root);
  const bodies = [];
  root.traverse((o) => { if (o.isMesh && o.castShadow) bodies.push(o); });
  return { group, rig: { root, joints: J, dims: { height: HEIGHT, headH: 0.5 } }, J, wheels, casters, tally, lens, bodies, baked: false };
}

function buildModel(game, baked) {
  const b = baked ? buildBakedRig(game) : buildPlaceholderRig(game);
  const m = { ...b, def: { id: 'big_shot' }, variant: baked ? 'z_bigshot' : 'placeholder', cards: [] };
  const J = m.J;
  // head centre (stars ring, generic queries)
  const head = new THREE.Object3D();
  head.name = 'part:headCenter';
  head.position.set(0, 0.27, -0.05);
  J.head.add(head);
  m.head = head;
  m.headR = 0.3;
  m.tallyMat = m.tally ? m.tally.material : null;
  if (m.tallyMat) m.tallyBase = m.tallyMat.color.clone();
  // Lens: glow disc + iris blades (open with the flash wind-up) + a flash sprite.
  const lens = m.lens || J.head;
  const glowMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.05, 0.07, 0.1), transparent: true, opacity: 0.95, depthWrite: false, fog: false });
  glowMat.name = 'bsLensGlow';
  m.glow = new THREE.Mesh(new THREE.CircleGeometry(0.098, 28), glowMat);
  m.glow.rotation.y = Math.PI;
  m.glow.position.z = -0.012;
  lens.add(m.glow);
  const bladeMat = game.mats.toon('#14171F', { rough: 0.35, metal: 0.4, keepColor: true, rim: 0.2 });
  m.blades = new THREE.Mesh(bladeGeometry(), bladeMat);
  m.blades.position.z = -0.016;
  m.blades.rotation.y = Math.PI;
  lens.add(m.blades);
  const flareMat = new THREE.MeshBasicMaterial({ map: flareTexture(), transparent: true, depthWrite: false, depthTest: true, blending: THREE.AdditiveBlending, fog: false });
  flareMat.color.setScalar(3);
  flareMat.name = 'bsFlare';
  m.flare = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), flareMat);
  m.flare.visible = false;
  m.flare.renderOrder = 5;
  // Cable + plug (world space while alive).
  const P = getPlugAssets(game);
  const rings = (CABLE_N - 1) * 2 + 1, rad = 6;
  const cg = new THREE.BufferGeometry();
  cg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(rings * rad * 3), 3));
  cg.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(rings * rad * 3), 3));
  const idx = [];
  for (let i = 0; i < rings - 1; i++) for (let k = 0; k < rad; k++) {
    const a = i * rad + k, b2 = i * rad + ((k + 1) % rad), c2 = a + rad, d2 = b2 + rad;
    idx.push(a, c2, b2, b2, c2, d2);
  }
  cg.setIndex(idx);
  m.cable = new THREE.Mesh(cg, P.cable);
  m.cable.frustumCulled = false;
  m.cable.castShadow = false;
  m.cable.name = 'bs:cable';
  m.plug = new THREE.Group();
  m.plug.name = 'bs:plug';
  m.plug.add(new THREE.Mesh(P.body, P.rubber));
  const prongMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#FFB23A').multiplyScalar(2.6) });
  prongMat.name = 'bsProng';
  m.prongMat = prongMat;
  m.plug.add(new THREE.Mesh(P.prong, prongMat));   // both prongs, one draw
  const haloMat = new THREE.MeshBasicMaterial({ map: flareTexture(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false });
  haloMat.color.set('#FFA030').multiplyScalar(1.2);
  m.halo = new THREE.Mesh(new THREE.PlaneGeometry(0.32, 0.32), haloMat);
  m.halo.position.z = -0.08;
  m.plug.add(m.halo);
  m.plug.traverse((o) => { if (o.isMesh) o.castShadow = false; });
  m.cablePts = Array.from({ length: CABLE_N }, () => new THREE.Vector3());
  m.cablePrev = Array.from({ length: CABLE_N }, () => new THREE.Vector3());
  // Film spaghetti (death): one dynamic ribbon mesh.
  filmAssets();
  const fv = FILM_N * FILM_P * 2;
  const fg = new THREE.BufferGeometry();
  fg.setAttribute('position', new THREE.BufferAttribute(new Float32Array(fv * 3), 3));
  fg.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(fv * 3), 3));
  const fuv = new Float32Array(fv * 2);
  const fidx = [];
  for (let s = 0; s < FILM_N; s++) for (let i = 0; i < FILM_P; i++) {
    const k = (s * FILM_P + i) * 2;
    fuv[k * 2] = 0; fuv[k * 2 + 1] = i * 0.5; fuv[k * 2 + 2] = 1; fuv[k * 2 + 3] = i * 0.5;
    if (i < FILM_P - 1) fidx.push(k, k + 1, k + 2, k + 1, k + 3, k + 2);
  }
  fg.setAttribute('uv', new THREE.BufferAttribute(fuv, 2));
  fg.setIndex(fidx);
  m.film = new THREE.Mesh(fg, filmMat);
  m.film.frustumCulled = false;
  m.film.castShadow = false;
  m.film.visible = false;
  m.film.name = 'bs:film';
  m.strips = Array.from({ length: FILM_N }, () => ({ p: Array.from({ length: FILM_P }, () => new THREE.Vector3()), q: Array.from({ length: FILM_P }, () => new THREE.Vector3()) }));
  for (const o of [m.flare, m.cable, m.plug, m.film]) game.render.setLayerRecursive(o, LAYERS.ZOMBIES);
  game.render.setLayerRecursive(m.group, LAYERS.ZOMBIES);
  m.group.name = 'zombie:big_shot';
  m.rest = new Map();
  for (const j of Object.values(J)) m.rest.set(j, j.position.clone());
  return m;
}

function acquire(game) {
  const want = hasBaked(game);
  // pooled models built under another charOpt.gen (A/B tools toggled a build-time flag) are dropped
  for (let i = pool.length - 1; i >= 0; i--) if ((pool[i].gen || 0) !== (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0)) pool.splice(i, 1);
  for (let i = pool.length - 1; i >= 0; i--) if (pool[i].baked === want) return pool.splice(i, 1)[0];
  if (want) {
    try { const m = buildModel(game, true); m.gen = (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0); return m; } catch (err) { if (!warned) { warned = true; console.warn('[big_shot] baked model failed, using the placeholder', err); } }
  }
  const m = buildModel(game, false);
  m.gen = (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0);
  return m;
}

function resetModel(m) {
  const g = m.group;
  g.visible = true;
  g.position.set(0, 0, 0); g.rotation.set(0, 0, 0); g.scale.set(1, 1, 1);
  m.rig.root.position.set(0, 0, 0); m.rig.root.rotation.set(0, 0, 0); m.rig.root.scale.set(1, 1, 1);
  for (const [j, p] of m.rest) { j.position.copy(p); j.rotation.set(0, 0, 0); j.scale.set(1, 1, 1); }
  for (const o of [m.flare, m.cable, m.plug, m.film]) { o.removeFromParent(); }
  m.flare.visible = false; m.film.visible = false; m.cable.visible = true; m.plug.visible = true;
  m.glow.scale.setScalar(1); m.glow.material.color.setRGB(0.05, 0.07, 0.1);
  m.blades.scale.setScalar(1);
  if (m.tallyMat && m.tallyBase) m.tallyMat.color.copy(m.tallyBase);
  m.prongMat.color.set('#FFB23A').multiplyScalar(2.6);
  m.halo.visible = true;
}

// ------------------------------------------------------------------------------------------------ cable
function cableAnchor(z, out) {
  const s = z.scale || 1;
  const sy = Math.sin(z.yaw), cy = Math.cos(z.yaw);
  // behind the base: local (0, 0.14, +0.4) rotated by yaw
  return out.set(z.pos.x + sy * 0.4 * s, z.pos.y + 0.14 * s, z.pos.z + cy * 0.4 * s);
}

function initCable(z) {
  const m = z.model;
  cableAnchor(z, _a);
  const bx = Math.sin(z.yaw), bz = Math.cos(z.yaw);
  for (let i = 0; i < CABLE_N; i++) {
    m.cablePts[i].set(_a.x + bx * CABLE_SEG * i, z.pos.y + CABLE_R + 0.01, _a.z + bz * CABLE_SEG * i);
    m.cablePrev[i].copy(m.cablePts[i]);
  }
  m.cablePts[0].copy(_a);
  m.cablePrev[0].copy(_a);
}

function tickCable(game, z, dt, limp = false) {
  const m = z.model;
  if (!m) return;
  const P = m.cablePts, Q = m.cablePrev;
  const floor = z.pos.y + CABLE_R + 0.005;
  if (!limp) {
    cableAnchor(z, _a);
    if (_a.distanceToSquared(P[0]) > 4) initCable(z);     // teleported (straggler re-entry, debug): re-lay the cable
    P[0].copy(_a);
  }
  Q[0].copy(P[0]);
  const h = Math.min(dt, 1 / 30);
  for (let i = 1; i < CABLE_N; i++) {
    const p = P[i], q = Q[i];
    const onFloor = p.y <= floor + 0.004;
    const damp = onFloor ? 0.72 : 0.985;
    const vx = (p.x - q.x) * damp, vy = (p.y - q.y) * 0.985, vz = (p.z - q.z) * damp;
    q.copy(p);
    p.x += vx; p.y += vy - G * h * h; p.z += vz;
    if (p.y < floor) p.y = floor;
  }
  for (let it = 0; it < 5; it++) {
    for (let i = 0; i < CABLE_N - 1; i++) {
      const a = P[i], b = P[i + 1];
      _d.subVectors(b, a);
      const l = _d.length() || 1e-6;
      const diff = (l - CABLE_SEG) / l;
      if (i === 0 && !limp) b.addScaledVector(_d, -diff);
      else { a.addScaledVector(_d, diff * 0.5); b.addScaledVector(_d, -diff * 0.5); }
    }
    for (let i = 1; i < CABLE_N; i++) if (P[i].y < floor) P[i].y = floor;
  }
  writeCable(m);
  // plug at the end, oriented along the last segment, prongs pointing away
  const a = P[CABLE_N - 2], b = P[CABLE_N - 1];
  _d.subVectors(b, a);
  if (_d.lengthSq() > 1e-8) {
    _d.normalize();
    m.plug.position.copy(b).addScaledVector(_d, 0.04);
    _m4.lookAt(_c.set(0, 0, 0), _d, _up);   // local -z (the prongs) along the cable end
    m.plug.quaternion.setFromRotationMatrix(_m4);
  }
  const t = z.flags.t || 0;
  const pulse = 0.85 + Math.sin(t * 7) * 0.15;
  m.halo.quaternion.copy(game.camera.quaternion).premultiply(_q.copy(m.plug.quaternion).invert());
  m.halo.scale.setScalar(limp ? 0.001 : pulse);
}

function writeCable(m) {
  const P = m.cablePts;
  const pos = m.cable.geometry.attributes.position.array, nrm = m.cable.geometry.attributes.normal.array;
  const rings = (CABLE_N - 1) * 2 + 1, rad = 6;
  let prevN = null;
  for (let r = 0; r < rings; r++) {
    const i = r >> 1, odd = r & 1;
    let c;
    if (!odd) c = _a.copy(P[i]);
    else {
      // midpoint pulled toward a Catmull-Rom position (smooth sag)
      const p0 = P[Math.max(0, i - 1)], p1 = P[i], p2 = P[i + 1], p3 = P[Math.min(CABLE_N - 1, i + 2)];
      c = _a.set(0, 0, 0).addScaledVector(p1, 0.5625).addScaledVector(p2, 0.5625).addScaledVector(p0, -0.0625).addScaledVector(p3, -0.0625);
    }
    const nA = P[Math.min(CABLE_N - 1, i + 1)], nB = P[Math.max(0, i - (odd ? 0 : 1))];
    _b.subVectors(nA, nB);
    if (_b.lengthSq() < 1e-10) _b.set(0, 0, 1);
    _b.normalize();
    let n = _c.crossVectors(_b, _up);
    if (n.lengthSq() < 1e-6) n.set(1, 0, 0);
    n.normalize();
    if (prevN && n.dot(prevN) < 0) n.negate();
    prevN = prevN || new THREE.Vector3();
    prevN.copy(n);
    const bi = _d.crossVectors(n, _b).normalize();
    for (let k = 0; k < rad; k++) {
      const ang = (k / rad) * Math.PI * 2;
      const cx = Math.cos(ang), sx = Math.sin(ang);
      const nx = n.x * cx + bi.x * sx, ny = n.y * cx + bi.y * sx, nz = n.z * cx + bi.z * sx;
      const o = (r * rad + k) * 3;
      pos[o] = c.x + nx * CABLE_R; pos[o + 1] = c.y + ny * CABLE_R; pos[o + 2] = c.z + nz * CABLE_R;
      nrm[o] = nx; nrm[o + 1] = ny; nrm[o + 2] = nz;
    }
  }
  m.cable.geometry.attributes.position.needsUpdate = true;
  m.cable.geometry.attributes.normal.needsUpdate = true;
}

function plugWorld(z, out) {
  const m = z.model;
  return m ? out.copy(m.plug.position) : out.copy(z.pos);
}

function registerPlug(game, z) {
  const W = game.weapons, f = z.flags;
  f.plugId = 'bs_plug_' + z.id;
  if (!W || typeof W.registerShootable !== 'function') return;
  try {
    W.registerShootable({
      id: f.plugId,
      raycast(o, d, max) {
        if (z.dead || z.removed || !z.model || z.state !== 'chase' && z.state !== 'attack') return null;
        const t = raySphere(o, d, z.model.plug.position, 0.12);
        return t <= max ? { dist: t, point: o.clone().addScaledVector(d, t) } : null;
      },
      onHit(info) {
        if (z.dead || !(info.damage > 0)) return;
        game.zombies.damage(z, info.damage, { zone: 'plug', head: true, point: info.point, dir: info.dir, weaponId: info.weaponId,
          upgraded: info.upgraded, cause: info.melee ? 'melee' : (info.cause || 'bullet') });
        game.fx.burst(info.point || z.model.plug.position, { shape: 'spark', count: 8, speed: 4, colors: ['#FFE08A', '#FFB23A', '#FFFFFF'] });
      },
      blocksBullet: true,
      melee: true,
    });
  } catch (err) { /* weapons is someone else's */ }
}

function unregisterPlug(game, z) {
  const f = z.flags;
  if (!f.plugId) return;
  try { game.weapons && game.weapons.unregisterShootable && game.weapons.unregisterShootable(f.plugId); } catch (err) { /* ignore */ }
  f.plugId = null;
}

// ------------------------------------------------------------------------------------------------ hit test
function makeHitTest(z) {
  return (o, d, max) => {
    const m = z.model;
    if (!m) return null;
    const J = m.J, s = z.scale || 1;
    let best = Infinity, zone = null;
    const test = (t, zn) => { if (t < best) { best = t; zone = zn; } };
    // camera housing + lens
    test(raySphere(o, d, J.head.localToWorld(_a.set(0, 0.28, 0.02)), 0.3 * s), 'camera');
    test(rayCapsule(o, d, J.head.localToWorld(_a.set(0, 0.205, -0.25)), J.head.localToWorld(_b.set(0, 0.205, -0.6)), 0.14 * s), 'camera');
    // torso + arms
    test(rayCapsule(o, d, J.torso.localToWorld(_a.set(0, 0.14, 0)), J.torso.localToWorld(_b.set(0, 0.42, 0.02)), 0.33 * s), 'torso');
    // column + base
    test(rayCapsule(o, d, J.base.localToWorld(_a.set(0, 0.18, 0)), J.column.localToWorld(_b.set(0, 0.62, 0)), 0.15 * s), 'body');
    test(rayCapsule(o, d, J.base.localToWorld(_a.set(0, 0.1, -0.25)), J.base.localToWorld(_b.set(0, 0.1, 0.25)), 0.3 * s), 'body');
    if (!zone || best > max) return null;
    _hit.dist = best; _hit.zone = zone; _hit.head = false; _hit.mul = 1;
    return _hit;
  };
}

// ------------------------------------------------------------------------------------------------ animator
function makeAnimator(z) {
  const f = z.flags;
  return {
    update(dt, st = {}) { poseBigShot(z, f, dt, st); },
    kick(amount = 1) { f.sq.kick(-2.2 * amount); f.lean.kick(2.5 * amount); },
  };
}

function poseBigShot(z, f, dt, st) {
  const m = z.model;
  if (!m) return;
  const g = f.game;
  const J = m.J, root = m.rig.root;
  f.t += dt;
  const t = f.t;
  for (const [j, p] of m.rest) { j.position.copy(p); j.rotation.set(0, 0, 0); }
  J.column.scale.set(1, 1, 1);
  J.head.scale.setScalar(1);
  let lean = 0, headYaw = 0, headPitch = 0, jitter = 0, wheelSpin = 0, colScale = 1;
  const speed = st.speed || 0;
  const mode = f.mode;
  // aim the camera head at the player
  if (g && g.player) {
    const p = g.player.pos;
    headYaw = THREE.MathUtils.clamp(angDiff(yawTo(p.x - z.pos.x, p.z - z.pos.z), z.yaw), -0.9, 0.9);
    const dh = Math.hypot(p.x - z.pos.x, p.z - z.pos.z);
    headPitch = THREE.MathUtils.clamp(Math.atan2(p.y + 1.3 - (z.pos.y + 1.75), Math.max(0.5, dh)), -0.4, 0.3);
  }
  let blink = 1;
  if (mode === 'rushTele') {
    const k = clamp01(f.mt / RU.tele);
    lean = 0.26 * smooth(k / 0.3);
    jitter = 0.012 + 0.02 * k;
    wheelSpin = 38;
    blink = Math.floor(t * 18) % 2;
    colScale = 1 - 0.06 * k;
  } else if (mode === 'rush') {
    lean = -0.3;
    colScale = 0.92;
    headYaw *= 0.2;
    blink = Math.floor(t * 18) % 2;
  } else if (mode === 'skid') {
    lean = 0.22 * (1 - clamp01(f.mt / 0.45));
    jitter = 0.01;
    blink = Math.floor(t * 10) % 2;
  } else if (mode === 'flashWind') {
    const k = clamp01(f.mt / FL.windup);
    lean = 0.08 * k;
    blink = Math.floor(t * (6 + k * 10)) % 2;
  } else if (mode === 'bump') {
    const k = f.mt / BUMP.windup;
    lean = k < 1 ? 0.2 * smooth(k) : -0.35 * Math.sin(clamp01((f.mt - BUMP.windup) / 0.3) * Math.PI);
  }
  const dizzy = z.stun > 0;
  if (dizzy) { blink = Math.random() < 0.3 ? 1 : 0; headPitch = -0.15; }
  // springs
  const sq = f.sq.update(dt, 0);
  const lz = f.lean.update(dt, lean + (speed > 0.3 ? -0.04 : 0));
  const sy = 1 + sq;
  root.scale.set(1 / Math.sqrt(sy), sy, 1 / Math.sqrt(sy));
  root.position.x = jitter ? Math.sin(t * 90) * jitter : 0;
  root.position.y = speed > 0.3 && mode === 'roll' ? Math.abs(Math.sin(t * 9)) * 0.006 : 0;
  J.column.scale.y = colScale;
  J.torso.rotation.x = lz * 0.8;
  J.torso.rotation.z = Math.sin(t * 1.3 + z.id) * 0.025;
  const breathe = 1 + Math.sin(t * Math.PI * 2 * 0.3) * 0.015;
  J.torso.scale.set(breathe, 1 + (breathe - 1) * 0.5, breathe);
  // head: aim (lagged), dizzy spin, hurt jolt
  f.hy += (headYaw - f.hy) * Math.min(1, dt * 5);
  f.hp += (headPitch - f.hp) * Math.min(1, dt * 5);
  if (dizzy) f.spin += dt * (6 + 10 * clamp01(z.stun / 2)); else f.spin *= Math.exp(-dt * 6);
  J.head.rotation.set(f.hp - lz * 0.5 - (st.hurt || 0) * 0.15, f.hy + f.spin, Math.sin(t * 1.1) * 0.02 + (dizzy ? Math.sin(t * 8) * 0.12 : 0));
  // arms grip the pan handles: follow the head a little
  J.shoulderL.rotation.x = -f.hp * 0.3 + lz * 0.3; J.shoulderR.rotation.x = -f.hp * 0.3 + lz * 0.3;
  J.shoulderL.rotation.y = f.hy * 0.25; J.shoulderR.rotation.y = f.hy * 0.25;
  // wheels roll / screech; casters swivel toward the travel direction
  const roll = (speed + wheelSpin) * dt / WHEEL_R;
  for (const w of m.wheels) w.rotation.x -= roll;
  const vx = z.vel.x, vz = z.vel.z;
  if (vx * vx + vz * vz > 0.04) {
    const travel = angDiff(yawTo(vx, vz), z.yaw);
    f.caster += angDiff(travel, f.caster) * Math.min(1, dt * 6);
  }
  for (const c of m.casters) c.rotation.y = f.caster;
  // tally lamp
  if (m.tallyMat && m.tallyBase) {
    const on = z.dead ? 0 : blink;
    m.tallyMat.color.copy(m.tallyBase).multiplyScalar(on ? 1 : 0.12);
  }
  // flash sprite / lens glow decay (here: the animator also runs while he is stunned)
  if (f.flareT >= 0 && g) {
    f.flareT += dt;
    const k = f.flareT / 0.28;
    lensWorld(z, m.flare.position);
    m.flare.quaternion.copy(g.camera.quaternion);
    m.flare.scale.setScalar(Math.max(0.01, 3.2 * easeOutCubic(k * 2) * (1 - smooth(k))));
    if (k >= 1) { f.flareT = -1; m.flare.visible = false; m.flare.removeFromParent(); }
  }
  if (f.mode !== 'flashWind') { f.iris += (0 - f.iris) * Math.min(1, dt * 3); f.glow += (0 - f.glow) * Math.min(1, dt * 2.5); }
  // lens iris / glow
  const ir = f.iris;
  m.blades.visible = ir > 0.02 || (z.camDist || 0) < 12;
  m.blades.scale.setScalar(lerp(0.42, 1.28, ir));
  m.blades.rotation.z = ir * 1.4;
  const gl = f.glow;
  m.glow.scale.setScalar(lerp(0.35, 1.0, ir));
  m.glow.material.color.setRGB(lerp(0.05, 3.2, gl), lerp(0.07, 3.0, gl), lerp(0.1, 2.6, gl));
  // cable follows (when update() did not already tick it this frame)
  if (g && f.cableFrame !== g.time.frame) tickCable(g, z, dt);
}

// ------------------------------------------------------------------------------------------------ behaviour
function losTo(game, z, from, p) {
  _a.copy(from);
  _b.set(p.pos.x, p.pos.y + 1.4, p.pos.z);
  try { return game.level.col.lineOfSight(_a, _b); } catch (err) { return true; }
}

function lensWorld(z, out) {
  const m = z.model;
  if (m && m.lens) return m.lens.getWorldPosition(out);
  return out.set(z.pos.x, z.pos.y + 1.7, z.pos.z);
}

function move(game, z, dt, radius = RADIUS) {
  z.vy -= G * dt;
  _d.set(z.vel.x * dt, z.vy * dt, z.vel.z * dt);
  const r = game.level.col.moveCircle(z.pos, _d, radius, HEIGHT, 0.35);
  if (r.onGround) z.vy = 0;
  return r;
}

function turnToward(z, want, rate, dt) {
  const d = angDiff(want, z.yaw);
  const step = THREE.MathUtils.clamp(d, -rate * dt, rate * dt);
  z.yaw += step;
  z.anim.turn = dt > 0 ? step / dt : 0;
}

function startRush(game, z) {
  const f = z.flags;
  f.mode = 'rushTele';
  f.mt = 0;
  f.dustT = 0;
  game.audio.play('bs_rush', { pos: z.pos });
}

function startFlash(game, z) {
  const f = z.flags;
  f.mode = 'flashWind';
  f.mt = 0;
  game.audio.play('bs_flash_charge', { pos: z.pos });
}

function flashPop(game, z) {
  const f = z.flags, m = z.model, p = game.player;
  lensWorld(z, _a);
  game.audio.play('bs_flash_pop', { pos: _a });
  game.fx.flashLight(_a, '#FFF4E0', 28, 0.16);
  game.fx.burst(_a, { shape: 'star', count: 6, speed: 3, colors: ['#FFFFFF', '#FFF3B0'] });
  f.flareT = 0;
  f.glow = 1;
  m.flare.visible = true;
  m.flare.position.copy(_a);
  game.scene.add(m.flare);
  // Does it land? camera forward within 60° of the direction to him, line of sight, in range.
  const cam = game.camera;
  cam.getWorldDirection(_b);
  _c.subVectors(_a, cam.position);
  const dist = _c.length();
  _c.normalize();
  const ang = Math.acos(THREE.MathUtils.clamp(_b.dot(_c), -1, 1));
  let hit = false;
  if (p.alive && dist <= FL.range + 2 && ang <= THREE.MathUtils.degToRad(FL.cone)) {
    try { hit = game.level.col.lineOfSight(_a, cam.position) || game.level.col.lineOfSight(_a, _d.set(p.pos.x, p.pos.y + 1.5, p.pos.z)); } catch (err) { hit = true; }
  }
  if (hit) {
    if (game.hud && typeof game.hud.whiteout === 'function') game.hud.whiteout(FL.white, 1);
    else if (game.render && game.render.post) game.render.post.whiteout = 1;
    if (p.hurt(FL.dmg, z.pos)) game.events.emit('zombie:attack', { z, dmg: FL.dmg, kind: 'flash' });
    try { if (game.screens && typeof game.screens.override === 'function') game.screens.override('flinch', undefined, 3); } catch (err) { /* screens is someone else's */ }
  }
  game.events.emit('zombie:flash', { z, pos: _a.clone(), hit });
  f.lastFlashHit = hit;
}

function updateBigShot(game, z, dt) {
  const f = z.flags, p = game.player, Zs = game.zombies;
  z.gawkT = 0;
  f.rushCd -= dt; f.flashCd -= dt; f.gap -= dt;
  const m = z.model;
  // rolling sound follows him
  if (f.rollSnd) {
    try { f.rollSnd.setPos && f.rollSnd.setPos(z.pos); f.rollSnd.setVol && f.rollSnd.setVol(clamp01(Math.hypot(z.vel.x, z.vel.z) / 3) * 0.8 + (f.mode === 'rush' ? 0.4 : 0), 0.1); } catch (err) { /* optional */ }
  }
  const dx = p.pos.x - z.pos.x, dz = p.pos.z - z.pos.z;
  const dist = Math.max(1e-3, Math.hypot(dx, dz));
  f.losT -= dt;
  if (f.losT <= 0) { f.losT = 0.25; f.los = dist < 24 ? losTo(game, z, _e.set(z.pos.x, z.pos.y + 1.7, z.pos.z), p) : false; }
  if (Zs.lure && z.lured && (f.mode === 'roll' || f.mode === 'skid')) { f.mode = 'roll'; tickCable(game, z, dt); f.cableFrame = game.time.frame; return false; }

  switch (f.mode) {
    case 'rushTele': {
      f.mt += dt;
      z.vel.multiplyScalar(Math.exp(-dt * 10));
      move(game, z, dt);
      if (f.mt < RU.tele - 0.12) turnToward(z, yawTo(dx, dz), 5, dt);
      f.dustT -= dt;
      if (f.dustT <= 0) {
        f.dustT = 0.07;
        for (const c of m.casters) {
          c.getWorldPosition(_a);
          game.fx.burst(_a, { shape: 'puff', count: 1, size: 0.04, speed: 1.4, life: 0.3, colors: ['#D8CDB8', '#BFB3A0'] });
        }
      }
      z.anim.speed = 0;
      z.navBest = Infinity;
      if (f.mt >= RU.tele) {
        f.mode = 'rush';
        f.mt = 0;
        f.rushDir = new THREE.Vector3(-Math.sin(z.yaw), 0, -Math.cos(z.yaw));
        f.rushHit = false;
        if (z.animator) z.animator.kick(0.6);
      }
      break;
    }
    case 'rush': {
      f.mt += dt;
      const sp = RU.speed * smooth(f.mt / 0.12);
      z.vel.set(f.rushDir.x * sp, 0, f.rushDir.z * sp);
      const before = _e.copy(z.pos);
      const bx = before.x, bz = before.z;
      const r = move(game, z, dt);
      const moved = Math.hypot(z.pos.x - bx, z.pos.z - bz);
      z.anim.speed = sp;
      f.trailT = (f.trailT || 0) - dt;
      if (f.trailT <= 0) { f.trailT = 0.06; for (const c of m.casters) { c.getWorldPosition(_a); game.fx.burst(_a, { shape: 'puff', count: 1, size: 0.045, speed: 0.8, life: 0.3, colors: ['#D8CDB8', '#BFB3A0'] }); } }
      const dCam = game.camera.position.distanceTo(z.pos);
      if (dCam < 9) game.fx.shake(0.06 * (1 - dCam / 9), 0.1);
      // bowl other zombies aside
      for (const o of Zs.alive) {
        if (o === z || o.type === 'big_shot') continue;
        const ox = o.pos.x - z.pos.x, oz = o.pos.z - z.pos.z;
        if (ox * ox + oz * oz < 1.3 * 1.3 && Math.abs(o.pos.y - z.pos.y) < 1.2) {
          const side = Math.sign(ox * -f.rushDir.z + oz * f.rushDir.x) || 1;
          Zs.knockback(o, _a.set(f.rushDir.x * 0.4 - f.rushDir.z * side * 0.5, 0, f.rushDir.z * 0.4 + f.rushDir.x * side * 0.5));
          if (o.animator && o.animator.kick) o.animator.kick(0.8);
        }
      }
      // the player
      const pd = Math.hypot(p.pos.x - z.pos.x, p.pos.z - z.pos.z);
      if (!f.rushHit && p.alive && pd < RADIUS + (p.radius || 0.38) + 0.2 && Math.abs(p.pos.y - z.pos.y) < 1.5) {
        f.rushHit = true;
        if (p.hurt(RU.dmg, z.pos)) {
          game.events.emit('zombie:attack', { z, dmg: RU.dmg, kind: 'rush' });
          const kx = p.pos.x - z.pos.x, kz = p.pos.z - z.pos.z, kl = Math.hypot(kx, kz) || 1;
          // 4 m of knockback: the player's knock decays at exp(-6 t) -> v0 = 6 * 4
          _a.set(f.rushDir.x * 0.7 + (kx / kl) * 0.3, 0, f.rushDir.z * 0.7 + (kz / kl) * 0.3).normalize().multiplyScalar(RU.knock * 6);
          if (p.knockback) p.knockback(_a);
        }
        game.audio.play('bs_wall_bonk', { pos: z.pos, rate: 1.25, vol: 0.8 });
        game.fx.shake(0.35, 0.3);
        f.mode = 'skid'; f.mt = 0; f.skidV = sp * 0.35;
        game.audio.play('bs_squeak', { pos: z.pos });
        break;
      }
      // a wall: dizzy
      if (r.hitWall && moved < sp * dt * 0.5 && f.mt > 0.1) {
        f.mode = 'roll';
        f.rushCd = RU.cd;
        f.gap = ABILITY_GAP + RU.dizzy;
        z.vel.set(0, 0, 0);
        f.dizzyUntil = game.time.now + RU.dizzy;
        Zs.stun(z, RU.dizzy);
        game.audio.play('bs_wall_bonk', { pos: z.pos });
        if (z.animator) z.animator.kick(1.4);
        lensWorld(z, _a);
        game.fx.burst(_a, { shape: 'star', count: 7, speed: 2.4 });
        game.fx.burst(_a, { shape: 'spark', count: 10, speed: 5 });
        const dC = game.camera.position.distanceTo(z.pos);
        game.fx.shake(dC < 12 ? 0.3 * (1 - dC / 12) + 0.08 : 0.05, 0.35);
        // bounce back a little
        z.knock.set(-f.rushDir.x * 2.5, 0, -f.rushDir.z * 2.5);
        break;
      }
      if (f.mt >= RU.time) { f.mode = 'skid'; f.mt = 0; f.skidV = sp; game.audio.play('bs_squeak', { pos: z.pos }); }
      z.navBest = Infinity;
      break;
    }
    case 'skid': {
      f.mt += dt;
      const k = clamp01(f.mt / 0.45);
      const sp = f.skidV * (1 - k) * (1 - k);
      z.vel.set(f.rushDir.x * sp, 0, f.rushDir.z * sp);
      move(game, z, dt);
      z.anim.speed = sp;
      f.trailT = (f.trailT || 0) - dt;
      if (f.trailT <= 0 && sp > 0.5) { f.trailT = 0.05; for (const c of m.casters) { c.getWorldPosition(_a); game.fx.burst(_a, { shape: 'puff', count: 1, size: 0.05, speed: 1.0, life: 0.35, colors: ['#CFC6B6', '#AFA595'] }); } }
      if (k >= 1) { f.mode = 'roll'; f.rushCd = RU.cd; f.gap = ABILITY_GAP; }
      z.navBest = Infinity;
      break;
    }
    case 'flashWind': {
      f.mt += dt;
      z.vel.multiplyScalar(Math.exp(-dt * 8));
      move(game, z, dt);
      turnToward(z, yawTo(dx, dz), 3, dt);
      const k = clamp01(f.mt / FL.windup);
      f.iris = smooth(k);
      f.glow = 0.15 + 0.55 * k * k;
      z.anim.speed = 0;
      z.navBest = Infinity;
      if (f.mt >= FL.windup) { flashPop(game, z); f.mode = 'roll'; f.flashCd = FL.cd; f.gap = ABILITY_GAP; }
      break;
    }
    case 'bump': {
      f.mt += dt;
      if (f.mt < BUMP.windup) { turnToward(z, yawTo(dx, dz), 4, dt); z.vel.multiplyScalar(Math.exp(-dt * 10)); }
      else if (f.mt < BUMP.windup + 0.25) {
        const fx = -Math.sin(z.yaw), fz = -Math.cos(z.yaw);
        z.vel.set(fx * 2.6, 0, fz * 2.6);
        if (!f.bumped && f.mt >= BUMP.windup + 0.08) {
          f.bumped = true;
          const fwd = (fx * dx + fz * dz) / dist;
          if (p.alive && dist < BUMP.range + 0.4 && fwd > 0.3 && Math.abs(p.pos.y - z.pos.y) < 1.4) {
            if (p.hurt(BUMP.dmg, z.pos)) {
              game.events.emit('zombie:attack', { z, dmg: BUMP.dmg, kind: 'bump' });
              _a.set(dx / dist, 0, dz / dist).multiplyScalar(12);
              if (p.knockback) p.knockback(_a);
            }
            game.audio.play('bs_wall_bonk', { pos: z.pos, rate: 1.4, vol: 0.6 });
          }
        }
      } else z.vel.multiplyScalar(Math.exp(-dt * 10));
      move(game, z, dt);
      z.anim.speed = Math.hypot(z.vel.x, z.vel.z);
      if (f.mt >= BUMP.windup + 0.6) { f.mode = 'roll'; z.cd = BUMP.cd; }
      break;
    }
    default: {
      // roll: abilities first
      if (p.alive && f.gap <= 0 && z.spawnT <= 0 && f.los) {
        const canRush = f.rushCd <= 0 && dist <= RU.range && dist > 2.4;
        const canFlash = f.flashCd <= 0 && dist <= FL.range;
        if (canRush && canFlash) { if (dist > 7 || Math.random() < 0.5) startFlash(game, z); else startRush(game, z); break; }
        if (canRush) { startRush(game, z); break; }
        if (canFlash) { startFlash(game, z); break; }
      }
      if (p.alive && dist < BUMP.range && z.cd <= 0 && Math.abs(p.pos.y - z.pos.y) < 1.4) { f.mode = 'bump'; f.mt = 0; f.bumped = false; game.audio.play('bs_squeak', { pos: z.pos, rate: 1.2 }); break; }
      // steer: straight when visible and close, else the flow field
      if (f.los && dist < 10) _d.set(dx / dist, 0, dz / dist);
      else {
        game.nav.dir(z.pos.x, z.pos.z, _d);
        if (_d.lengthSq() < 1e-6) _d.set(dx / dist, 0, dz / dist);
      }
      _d.x += (z.sepX || 0) * 0.6; _d.z += (z.sepZ || 0) * 0.6;
      const want = yawTo(_d.x, _d.z);
      turnToward(z, want, TURN, dt);
      // rolls forward along his facing (a dolly does not strafe); slows while turning hard
      const align = Math.max(0, Math.cos(angDiff(want, z.yaw)));
      const sp = (dist < 1.6 ? 0 : z.speed) * (0.35 + 0.65 * align);
      const k = 1 - Math.exp(-dt * 3);
      z.vel.x += (-Math.sin(z.yaw) * sp - z.vel.x) * k;
      z.vel.z += (-Math.cos(z.yaw) * sp - z.vel.z) * k;
      move(game, z, dt);
      z.anim.speed = Math.hypot(z.vel.x, z.vel.z);
    }
  }
  tickCable(game, z, dt);
  f.cableFrame = game.time.frame;
  return true;
}

// ------------------------------------------------------------------------------------------------ death
function startDeath(game, z, info) {
  const f = z.flags, m = z.model;
  f.mode = 'dying';
  unregisterPlug(game, z);
  if (f.rollSnd) { try { f.rollSnd.stop(0.2); } catch (err) { /* ignore */ } f.rollSnd = null; }
  const d = f.death = { t: 0, tip: Math.random() < 0.5 ? -1 : 1, dissolved: false };
  m.group.updateMatrixWorld(true);
  m.head.getWorldPosition(_a);
  d.headPos = _a.clone();
  // flashbulb burst
  game.audio.play('bs_death', { pos: _a });
  game.fx.flashLight(_a, '#FFF6E6', 34, 0.22);
  game.fx.burst(_a, { shape: 'spark', count: 22, speed: 7, colors: ['#FFFFFF', '#DDF6FF', '#9FE0FF'] });
  game.fx.burst(_a, { shape: 'static', count: 18, speed: 3, size: 0.09 });
  game.fx.burst(_a, { shape: 'star', count: 8, speed: 3.4 });
  game.fx.burst(_a, { shape: 'confetti', count: 14, speed: 4, colors: ['#5C7E97', '#EADFC4', '#E2452F', '#232126'] });
  f.flareT = 0;
  m.flare.visible = true;
  m.flare.position.copy(_a);
  game.scene.add(m.flare);
  const cam = game.camera;
  if (cam.position.distanceTo(_a) < 26) {
    let see = true;
    try { see = game.level.col.lineOfSight(_a, cam.position); } catch (err) { see = true; }
    if (see && game.hud && typeof game.hud.whiteout === 'function') game.hud.whiteout(0.45, 0.55);
  }
  game.fx.shake(0.25, 0.3);
  // film spaghetti
  for (let s = 0; s < FILM_N; s++) {
    const st = m.strips[s];
    const a = (s / FILM_N) * Math.PI * 2 + Math.random() * 0.4;
    const up = 3.5 + Math.random() * 3.5, out = 2.4 + Math.random() * 2.8;
    st.v = new THREE.Vector3(Math.cos(a) * out, up, Math.sin(a) * out);
    st.w = 0.045 + Math.random() * 0.012;
    st.curl = (Math.random() - 0.5) * 6;
    for (let i = 0; i < FILM_P; i++) { st.p[i].copy(_a); st.p[i].y -= i * 0.01; st.q[i].copy(st.p[i]); }
  }
  m.film.visible = true;
  game.scene.add(m.film);
  m.prongMat.color.setRGB(0.25, 0.2, 0.15);
  m.halo.visible = false;
  // FULL REEL on his first death this game
  const gs = gameState(game);
  if (!gs.reelDropped) {
    gs.reelDropped = true;
    const pu = game.powerups;
    const pos = new THREE.Vector3(z.pos.x, z.pos.y + 0.6, z.pos.z);
    try {
      if (pu && typeof pu.dropGuaranteed === 'function') pu.dropGuaranteed('full_reel', pos);
      else if (pu && typeof pu.drop === 'function') pu.drop('full_reel', pos);
    } catch (err) { console.warn('[big_shot] full reel drop failed', err); }
  }
}

function updateFilm(game, z, dt, t) {
  const m = z.model;
  const floor = z.pos.y + 0.012;
  const h = Math.min(dt, 1 / 30);
  const segL = 0.16;
  for (const st of m.strips) {
    const P = st.p, Q = st.q;
    // head: explicit velocity (frame-rate independent flight), bounces and slides on the floor
    {
      const p = P[0], v = st.v;
      v.y -= 14 * dt;
      p.addScaledVector(v, dt);
      if (p.y < floor) { p.y = floor; if (v.y < 0) v.y *= -0.25; v.x *= Math.exp(-dt * 7); v.z *= Math.exp(-dt * 7); }
      Q[0].copy(p);
    }
    for (let i = 1; i < FILM_P; i++) {
      const p = P[i], q = Q[i];
      const onF = p.y <= floor + 0.003;
      const damp = onF ? 0.6 : 0.99;
      const vx = (p.x - q.x) * damp, vy = (p.y - q.y) * 0.99, vz = (p.z - q.z) * damp;
      q.copy(p);
      p.x += vx; p.y += vy - 16 * h * h; p.z += vz;
      if (p.y < floor) p.y = floor;
    }
    for (let it = 0; it < 3; it++) {
      for (let i = 0; i < FILM_P - 1; i++) {
        const a = P[i], b = P[i + 1];
        _d.subVectors(b, a);
        const l = _d.length() || 1e-6;
        if (l <= segL) continue;          // film can bunch up (curls) but not stretch
        const diff = (l - segL) / l;
        if (i > 0) a.addScaledVector(_d, diff * 0.3);
        b.addScaledVector(_d, -diff * (i > 0 ? 0.7 : 1));
      }
    }
  }
  // write ribbons (flat strips twisting with a curl)
  const pos = m.film.geometry.attributes.position.array, nrm = m.film.geometry.attributes.normal.array;
  const shrink = 1 - smooth((t - 1.9) / 0.4);
  for (let s = 0; s < FILM_N; s++) {
    const st = m.strips[s];
    for (let i = 0; i < FILM_P; i++) {
      const p = st.p[i];
      const nA = st.p[Math.min(FILM_P - 1, i + 1)], nB = st.p[Math.max(0, i - 1)];
      _b.subVectors(nA, nB);
      if (_b.lengthSq() < 1e-10) _b.set(0, 0, 1);
      _b.normalize();
      const tw = st.curl * i * 0.18 + t * st.curl * 0.3;
      _c.set(Math.cos(tw), 0.35, Math.sin(tw)).normalize();
      _e.crossVectors(_b, _c);
      if (_e.lengthSq() < 1e-6) _e.set(1, 0, 0);
      _e.normalize();
      const w = st.w * shrink;
      const k = (s * FILM_P + i) * 2;
      pos[k * 3] = p.x - _e.x * w; pos[k * 3 + 1] = p.y - _e.y * w + 0.003; pos[k * 3 + 2] = p.z - _e.z * w;
      pos[k * 3 + 3] = p.x + _e.x * w; pos[k * 3 + 4] = p.y + _e.y * w + 0.003; pos[k * 3 + 5] = p.z + _e.z * w;
      const nn = _d.crossVectors(_e, _b).normalize();
      nrm[k * 3] = nn.x; nrm[k * 3 + 1] = nn.y; nrm[k * 3 + 2] = nn.z;
      nrm[k * 3 + 3] = nn.x; nrm[k * 3 + 4] = nn.y; nrm[k * 3 + 5] = nn.z;
    }
  }
  m.film.geometry.attributes.position.needsUpdate = true;
  m.film.geometry.attributes.normal.needsUpdate = true;
}

function updateDeath(game, z, dt, t) {
  const f = z.flags, m = z.model, d = f.death;
  if (!d || !m) return;
  d.t = t;
  const J = m.J, root = m.rig.root, G0 = z.group;
  // flare
  if (f.flareT >= 0) {
    f.flareT += dt;
    const k = f.flareT / 0.35;
    m.flare.quaternion.copy(game.camera.quaternion);
    m.flare.scale.setScalar(Math.max(0.01, 5.5 * easeOutCubic(k * 2.5) * (1 - smooth(k))));
    if (k >= 1) { f.flareT = -1; m.flare.visible = false; m.flare.removeFromParent(); }
  }
  // the camera head pops: swell, then gone
  const hs = t < 0.06 ? 1 + t / 0.06 * 0.35 : 0.001;
  J.head.scale.setScalar(hs);
  // slump: torso folds forward, arms drop, the column telescopes down
  const sl = smooth(t / 0.5);
  J.torso.rotation.x = 0.55 * sl;
  J.torso.rotation.z = 0.12 * sl * d.tip;
  for (const S of ['L', 'R']) { J['shoulder' + S].rotation.x = -0.5 * sl; J['elbow' + S].rotation.x = 0.4 * sl; }
  J.column.scale.y = 1 - 0.38 * smooth((t - 0.1) / 0.6);
  // tip over (bounce) at 0.8 s
  const tip = easeOutBounce((t - 0.8) / 0.55) * (Math.PI / 2 - 0.12);
  root.rotation.set(0, 0, 0);
  root.position.set(0, 0, 0);
  G0.position.copy(z.pos);
  G0.rotation.set(0, z.yaw, 0, 'YXZ');
  if (t > 0.8) {
    // pivot around the base edge: rotate about local z, lift the pivot so the base edge stays on the floor
    root.rotation.z = tip * d.tip;
    root.position.x = -Math.sin(tip) * 0.05 * d.tip;
    root.position.y = Math.sin(tip) * 0.42;
    if (!d.clunk && t > 1.05) { d.clunk = true; game.audio.play('bs_wall_bonk', { pos: z.pos, rate: 0.7, vol: 0.7 }); game.fx.burst(_a.copy(z.pos).setY(z.pos.y + 0.1), { shape: 'puff', count: 6, size: 0.07, speed: 2.0, life: 0.45 }); game.fx.shake(0.12, 0.2); }
  }
  let s = z.scale || 1;
  if (t > 1.95) {
    if (!d.dissolved) {
      d.dissolved = true;
      _a.copy(z.pos).setY(z.pos.y + 0.4);
      game.fx.burst(_a, { shape: 'static', count: 30, speed: 2.4, size: 0.1, life: 0.9 });
      game.fx.burst(_a, { shape: 'confetti', count: 12, speed: 3.2 });
      game.audio.play('zmb_death_static', { pos: z.pos });
    }
    s *= Math.max(0.001, 1 - smooth((t - 1.95) / 0.2));
  }
  G0.scale.set(s, s, s);
  for (const w of m.wheels) w.rotation.x -= dt * 4 * Math.max(0, 1 - t);
  if (m.tallyMat) m.tallyMat.color.setRGB(0.1, 0.02, 0.02);
  m.glow.material.color.setRGB(0.02, 0.02, 0.03);
  tickCable(game, z, dt, true);
  updateFilm(game, z, dt, t);
}

// ------------------------------------------------------------------------------------------------ module
export default {
  id: 'big_shot',
  height: HEIGHT,
  radius: RADIUS,
  dmg: RU.dmg,
  range: BUMP.range,
  windup: BUMP.windup,
  cd: BUMP.cd,
  spawnMode: 'window',
  points: { killBonus: T.points.bigShot },
  oneTakeMul: 5,

  hp(round) {
    return Math.max(B.hpMul * hpAt(Math.max(1, round)), B.hpMin);
  },

  speed() {
    return B.speed;
  },

  // Boarded windows and the gate only; every board blows out at once, then the toothpaste squeeze (1.5 s).
  entryFilter(w) {
    return w.type === 'boarded' || w.type === 'gate';
  },

  entry() {
    return { tear: false, time: 1.5, style: 'blast' };
  },

  build(game, z) {
    const m = acquire(game);
    resetModel(m);
    z.model = m;
    z.group = m.group;
    z.rig = m.rig;
    z.head = m.head;
    z.headR = m.headR;
    z.height = HEIGHT;
    z.radius = RADIUS;
    z.scale = 1;
    z.hitZones = null;
    z.hitTest = makeHitTest(z);
    const f = z.flags;
    f.game = game;
    f.mode = 'roll';
    f.mt = 0;
    f.t = Math.random() * 10;
    f.rushCd = 3 + Math.random() * 2;
    f.flashCd = 4.5 + Math.random() * 2;
    f.gap = 1.5;
    f.los = false;
    f.losT = Math.random() * 0.25;
    f.iris = 0; f.glow = 0; f.flareT = -1;
    f.hy = 0; f.hp = 0; f.spin = 0; f.caster = 0;
    f.sq = new Spring(200, 14);
    f.lean = new Spring(90, 11);
    f.cableInit = false;
    z.animator = makeAnimator(z);
    gameState(game);
    game.scene.add(m.cable);
    game.scene.add(m.plug);
    registerPlug(game, z);
    try { f.rollSnd = game.audio.loop('bs_roll', { pos: new THREE.Vector3(), vol: 0 }); } catch (err) { f.rollSnd = null; }
  },

  release(game, z) {
    const m = z.model;
    unregisterPlug(game, z);
    if (z.flags.rollSnd) { try { z.flags.rollSnd.stop(0.1); } catch (err) { /* ignore */ } z.flags.rollSnd = null; }
    if (!m) return;
    m.group.removeFromParent();
    resetModel(m);
    if ((m.gen || 0) === (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0) && pool.length < 4) pool.push(m);
    z.model = null;
  },

  update(game, z, dt) {
    if (!z.flags.cableInit) { z.flags.cableInit = true; initCable(z); }
    return updateBigShot(game, z, dt);
  },

  updateEntry(game, z, dt) {
    const f = z.flags;
    if (!f.cableInit) { f.cableInit = true; initCable(z); }
    if (f.rollSnd && f.rollSnd.setPos) { try { f.rollSnd.setPos(z.pos); f.rollSnd.setVol(z.state === 'approach' ? 0.6 : 0.2, 0.1); } catch (err) { /* optional */ } }
    // The blast: a flashbulb pop as every board blows out, a squeak for the toothpaste squeeze.
    if (z.state === 'vault' && !f.blasted) {
      f.blasted = true;
      const w = z.entry && z.entry.win;
      _a.set(w && w.pos ? w.pos.x : z.pos.x, (w && w.sill || 0) + 1.2, w && w.pos ? w.pos.z : z.pos.z);
      game.audio.play('bs_flash_pop', { pos: _a });
      game.audio.play('bs_squeak', { pos: _a, delay: 0.25 });
      game.fx.flashLight(_a, '#FFF4E0', 18, 0.14);
      f.glow = 1;
    }
    f.glow += (0 - f.glow) * Math.min(1, dt * 2.5);
    tickCable(game, z, dt);
    f.cableFrame = game.time.frame;
  },

  // front ×0.4 / sides+back ×1 / plug ×3 / dizzy ×1.5 from every side.
  onDamage(game, z, amount, info = {}) {
    const f = z.flags;
    if (info.zone === 'plug') return amount * B.plug;
    if (f.dizzyUntil && game.time.now < f.dizzyUntil) {
      const hm = info.head ? weaponHeadMul(game, info.weaponId) : 1;
      return (amount / hm) * RU.dizzyMul;
    }
    let dx, dz;
    if (info.dir) { dx = -info.dir.x; dz = -info.dir.z; } else { dx = game.player.pos.x - z.pos.x; dz = game.player.pos.z - z.pos.z; }
    const l = Math.hypot(dx, dz) || 1;
    const facing = z.yaw + (f.hy || 0);
    const fwd = (-Math.sin(facing) * dx - Math.cos(facing) * dz) / l;
    const hm = info.head ? weaponHeadMul(game, info.weaponId) : 1;   // no head multiplier on him (only the plug)
    return (amount / hm) * (fwd > 0.5 ? B.front : 1);
  },

  onDeath(game, z, info) {
    startDeath(game, z, info);
    return DEATH;
  },

  updateDeath(game, z, dt, t) {
    updateDeath(game, z, dt, t);
  },

  warmup(game) {
    const out = [];
    try {
      if (!pool.length) pool.push(acquire(game));
      const m = pool[0];
      out.push(m.group);
      const s = [m.flare.clone(), m.cable.clone(), m.plug.clone(), m.film.clone()];
      for (const o of s) o.visible = true;
      out.push(...s);
    } catch (err) { console.warn('[big_shot] warmup', err); }
    return out;
  },

  // ---- debug helpers
  forceRush(game, z) { if (!z || z.dead) return false; z.flags.rushCd = 0; z.flags.flashCd = Math.max(z.flags.flashCd, 3); z.flags.gap = 0; z.flags.los = true; return true; },
  forceFlash(game, z) { if (!z || z.dead) return false; z.flags.flashCd = 0; z.flags.rushCd = Math.max(z.flags.rushCd, 3); z.flags.gap = 0; z.flags.los = true; return true; },
  plugOf(z) { return z && z.model ? z.model.plug.position.clone() : null; },
};
