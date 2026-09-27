// Zombie type registry + model builders (GDD §8, §18.8; ARCHITECTURE §10). Owned by the zombies agent.
//
// ZOMBIE_TYPES[typeId] = the type module of ./types/<typeId>.js merged over FALLBACK[typeId] (so a stub module still
// spawns a playable placeholder). getType(id) -> type (unknown ids -> tuned_in).
//
// ---------------------------------------------------------------------------------------------------------------
// TYPE MODULE CONTRACT (./types/<id>.js `export default { ... }`; every field optional unless marked *):
//   id*                      'tuned_in' | 'sock_hopper' | 'forecaster' | 'big_shot'
//   height, radius           metres (body capsule for collision / boids / fallback hit zones)
//   dmg, range, windup, cd   generic melee used by the manager when update() does not handle movement
//   spawnMode                'window' (entries) | 'screen' (screen spawns; in the Yard: fence climbs) | 'both'
//   entryFilter(win) -> bool restrict entries (Big Shot: boarded windows + gate)
//   entry(game, z, win) -> { tear:bool=true, time:s, style:'vault'|'squeeze'|'toothpaste'|'blast' } | null
//                            called when the zombie reaches the outside point of its entry. tear:false skips the
//                            boards (Sock Hopper in Hullabaloo: squeeze under them, time 1.0); style 'blast' blows out
//                            every board at once then squeezes (Big Shot toothpaste, time 1.5).
//   hp(round, game) -> number        (the manager may override it with spawn opts.hp, e.g. Hullabaloo socks)
//   speed(round, game) -> m/s
//   build(game, z)*          create z.group (Object3D, feet at y 0, facing -z; the manager adds it to the scene and
//                            moves/rotates it), z.rig, z.animator ({update(dt, state), kick(amount)}), z.head
//                            (Object3D at the head centre), z.headR, optional z.hitZones (format below), z.model
//                            (anything; handed back to release). Put every mesh on LAYERS.ZOMBIES (render.setLayerRecursive).
//                            acquireModel()/releaseModel() below pool models by variant.
//   release(game, z)         give z.model back to a pool / free extra objects (clouds, shootables...)
//   update(game, z, dt) -> bool  called every frame in 'chase'/'attack' states; return true when the type moved and
//                            attacked by itself this frame (the manager then skips its steering + melee; it still does
//                            collision-free bookkeeping: area, anti-stuck, animation of z.anim, LOD, separation).
//   updateEntry(game, z, dt) optional flavour during approach/tear/vault/screen states (the manager moves the body).
//   warmup(game) -> Object3D[]  samples of the type's meshes for Game.precompile (real modules; stubs are warmed here).
//   onDamage(game, z, amount, info) -> amount   (info.zone / info.dir / info.head available; ×2 screen and ONE TAKE
//                            are applied by the manager after this hook)
//   onDeath(game, z, info) -> seconds | undefined   return a duration to play a custom death: the manager then calls
//                            updateDeath(game, z, dt, t) each frame for that long (skipping the default topple + static
//                            dissolve) and finally release + removal. undefined = default Tuned-In death.
//   points: { killBonus }    extra points on a scoring kill (Forecaster 100, Big Shot 500)
//   oneTakeMul               ONE TAKE damage multiplier instead of the one-hit kill (Big Shot: 5)
//
// z (the zombie record, see zombies.js): { id, type, def (this type), pos, vel, yaw, hp, maxHp, state, area, group,
//   rig, animator, radius, height, speed, flags, head, headR, hitZones, model, anim (animator state object: speed,
//   attack, hurt, climb, dead, down...), cd, stun, stagger, round, fromRound, entry }.
//
// HIT ZONES  z.hitZones = [ { shape:'sphere'|'capsule', bone:Object3D, offset:[x,y,z] (bone-local),
//   bone2:Object3D, offset2:[x,y,z] (capsule end, bone2 defaults to bone), r (m), zone:'head'|'torso'|'limb'|<custom>,
//   head:bool (the weapon's head multiplier applies), mul (damage multiplier applied by zombies.damage; limb 0.8) } ]
//   or z.hitTest(origin, dir, maxDist) -> { dist, zone, head, mul } | null for custom shapes. Missing -> humanoid
//   zones (head sphere on z.head, torso capsule, limb capsules) or, without a rig, one head sphere + body capsule.
// ---------------------------------------------------------------------------------------------------------------
//
// Builders: buildZombie(typeId, game, variant?) -> { group, rig, animator, head, headR, def, baked, art, variant,
//   cards, bodies, details } (placeholder or sculpted art; cards / details = meshes hidden by distance LOD); acquireModel(game, typeId, variant?) / releaseModel(model) pool
//   them; humanoidHitZones(model) -> zones; bakedZombieIds(typeId) -> baked art ids.
// ART HOOK: ZOMBIE_ART maps a type to src/art character ids. Ids that are defined (src/art/chars/index.js, or the two
//   Tuned-In variants imported below) AND baked (assets/baked) are used, a random variant per spawn; otherwise the
//   primitive placeholder. Baked zombies: engine rig + 'zombie' Animator, LAYERS.ZOMBIES, static-snow eyes (one
//   shared material, see setEyeMode), static attachments merged per material (charRuntime.mergeAttachments: plain
//   meshes on the head joint, no second skeleton), cards (ticket stub, patch) listed in model.cards for distance LOD,
//   only the skinned body casts shadows. URL art=0 disables it. Crowd batches (bottom of this file): the Tuned-In
//   attachments of all live zombies are drawn as one batch per look and material (updateCrowd / resetCrowd /
//   crowdWarmup / crowdStats, driven by zombies.js).
// Looks shared by every zombie: setEyeMode('static'|'stars') (ONE TAKE star eyes), setZombieTint(null|'standby')
// (PLEASE STAND BY test-card grey) and setFeedLook(bool) (feed passes: peach skin + plain eyes, GDD §8 common).

import * as THREE from 'three';
import { createRig, Animator } from '../core/rig.js';
import * as geo from '../core/geo.js';
import { skinRig } from '../core/geo.js';
import { staticNoise } from '../core/textures.js';
import { T, PAL, LAYERS } from '../core/config.js';
import * as charRuntime from '../art/charRuntime.js';
import BAKED from '../../assets/baked/registry.js';
import zCrewDef from '../art/chars/z_crew.js';
import zReporterDef from '../art/chars/z_reporter.js';
import tunedIn from './types/tuned_in.js';
import sockHopper from './types/sock_hopper.js';
import forecaster from './types/forecaster.js';
import bigShot from './types/big_shot.js';

const Z = T.zombies;
const R = T.rounds;
const SHIRTS = ['#C9703A', '#6B8FD6', '#D6B04A', '#9A5AA8', '#5E9E7A', '#D65A5A'];
const LOCAL_DEFS = { z_crew: zCrewDef, z_reporter: zReporterDef };

// GDD §7.2 (duplicated from rounds.js on purpose: no import cycle rounds <-> types).
function hpAt(r) {
  if (r <= 9) return R.hpEarlyBase + R.hpEarlyStep * (Math.max(1, r) - 1);
  return Math.min(R.hpCap, Math.round((R.hpEarlyBase + R.hpEarlyStep * 8) * R.hpMul ** (r - 9)));
}

// Fallback data per type: used alone while a type module is a stub, and as defaults under a real module.
const FALLBACK = {
  tuned_in: {
    id: 'tuned_in', height: 1.62, radius: 0.36, dmg: Z.tunedIn.dmg, range: Z.tunedIn.range, windup: Z.tunedIn.windup,
    cd: Z.tunedIn.cd, spawnMode: 'window', rig: { height: 1.62, headScale: 1.25, shoulderW: 0.44, hipW: 0.28 }, shirts: SHIRTS,
    hp: (r) => hpAt(r), speed: () => R.speeds.walk,
  },
  sock_hopper: {
    id: 'sock_hopper', height: 1.0, radius: 0.3, dmg: Z.sock.dmg, range: 1.2, windup: 0.3, cd: Z.sock.cd, spawnMode: 'both',
    rig: { height: 1.0, headScale: 1.0, shoulderW: 0.3, hipW: 0.2, legLen: 0.5 }, shirts: [PAL.sockRed, PAL.sockYellow, PAL.sockBlue],
    hp: (r) => Math.round(Z.sock.hpMix * hpAt(r)), speed: (r) => (r >= 15 ? Z.sock.speed15 : Z.sock.speed),
    entry: (game) => (game.rounds && game.rounds.special === 'hullabaloo' ? { tear: false, time: 1.0, style: 'squeeze' } : null),
  },
  forecaster: {
    id: 'forecaster', height: 1.8, radius: 0.4, dmg: Z.forecaster.strikeDmg, range: 1.5, windup: 0.5, cd: 1.4, spawnMode: 'screen',
    rig: { height: 1.8, headScale: 1.2, shoulderW: 0.46 }, shirts: ['#3A6BB5'],
    hp: (r) => Math.round(Z.forecaster.hpMul * hpAt(r) + Z.forecaster.hpAdd), speed: () => Z.forecaster.strafe,
    points: { killBonus: T.points.forecaster },
  },
  big_shot: {
    id: 'big_shot', height: 2.2, radius: 0.6, dmg: Z.bigShot.rush.dmg, range: 1.7, windup: 0.6, cd: 1.6, spawnMode: 'window',
    rig: { height: 2.2, headScale: 1.3, shoulderW: 0.62, hipW: 0.36 }, shirts: ['#5A4A3A'],
    hp: (r) => Math.max(Z.bigShot.hpMul * hpAt(r), Z.bigShot.hpMin), speed: () => Z.bigShot.speed,
    entryFilter: (w) => w.type === 'boarded' || w.type === 'gate',
    entry: () => ({ tear: false, time: 1.5, style: 'blast' }),
    points: { killBonus: T.points.bigShot }, oneTakeMul: 5,
  },
};

const MODULES = { tuned_in: tunedIn, sock_hopper: sockHopper, forecaster, big_shot: bigShot };

// Generic build/release for stub types: a pooled placeholder (or baked art when it exists) with humanoid zones.
function genericBuild(game, z) {
  const m = acquireModel(game, z.type);
  z.model = m;
  z.group = m.group;
  z.rig = m.rig;
  z.animator = m.animator;
  z.head = m.head;
  z.headR = m.headR;
  z.hitZones = humanoidHitZones(m);
}
function genericRelease(game, z) {
  releaseModel(z.model);
  z.model = null;
}

export const ZOMBIE_TYPES = {};
for (const id of Object.keys(FALLBACK)) {
  const mod = MODULES[id];
  const real = mod && !mod.stub && typeof mod.build === 'function';
  ZOMBIE_TYPES[id] = real ? { ...FALLBACK[id], ...mod, fallback: false }
    : { ...FALLBACK[id], build: genericBuild, release: genericRelease, fallback: true };
}

export function getType(id) {
  return ZOMBIE_TYPES[id] || ZOMBIE_TYPES.tuned_in;
}

// Type -> sculpted character ids (src/art/chars/<id>.js), used when baked. See the ART HOOK note above.
export const ZOMBIE_ART = {
  tuned_in: ['z_crew', 'z_reporter', 'z_disco', 'z_mom'],
  sock_hopper: ['z_sock'],
  forecaster: ['z_forecaster'],
  big_shot: ['z_bigshot'],
};

let warned = false;

function artDef(id) {
  try {
    return (charRuntime.getDef && charRuntime.getDef(id)) || LOCAL_DEFS[id] || null;
  } catch (err) {
    return LOCAL_DEFS[id] || null;
  }
}

// Baked character ids available for a zombie type (empty when none, or with ?art=0).
export function bakedZombieIds(typeId, game = window.__game) {
  if (game && game.params && game.params.art === 0) return [];
  try {
    if (typeof charRuntime.buildCharacter !== 'function') return [];
    return (ZOMBIE_ART[typeId] || []).filter((id) => BAKED[id] && artDef(id));
  } catch (err) {
    return [];
  }
}

// ------------------------------------------------------------------------------------------ shared looks
let eyeMat = null;
let starTex = null;
let eyeMode = 'static';
let normalEyeTex = null;
const tinted = new Set();     // materials used by zombie bodies (for the stand-by tint / feed look)
const veils = new Set();      // baked eye-veil materials: full-disc UVs, so ONE TAKE draws its star on them
let tintMode = null;
let feedLook = false;

export function zombieEyeMaterial() {
  if (!eyeMat) {
    eyeMat = new THREE.MeshBasicMaterial({ map: staticNoise(), color: new THREE.Color(1.35, 1.4, 1.45) });
    eyeMat.name = 'zombieEyes';
  }
  return eyeMat;
}

function makeStarTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#3B2340';
  g.fillRect(0, 0, 128, 128);
  const star = (r0, r1, col) => {
    g.beginPath();
    for (let i = 0; i < 10; i++) {
      const a = -Math.PI / 2 + (i * Math.PI) / 5, r = i % 2 ? r1 : r0;
      g.lineTo(64 + Math.cos(a) * r, 64 + Math.sin(a) * r);
    }
    g.closePath();
    g.fillStyle = col;
    g.fill();
  };
  star(60, 26, '#FFC23A');
  star(40, 17, '#FFF3B0');
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function makeNormalEyeTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#F7F4EC';
  g.fillRect(0, 0, 128, 128);
  g.fillStyle = '#5A3A22';
  g.beginPath(); g.arc(64, 64, 26, 0, Math.PI * 2); g.fill();
  g.fillStyle = '#1B1420';
  g.beginPath(); g.arc(64, 64, 13, 0, Math.PI * 2); g.fill();
  g.fillStyle = '#ffffff';
  g.beginPath(); g.arc(56, 55, 6, 0, Math.PI * 2); g.fill();
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// 'static' (default) | 'stars' (ONE TAKE). Shared materials, so this is free. Baked eyes map only a small patch of
// the static texture across the disc, so the star goes on their veil (a full-disc overlay) instead.
export function setEyeMode(mode) {
  const m = zombieEyeMaterial();
  eyeMode = mode === 'stars' ? 'stars' : 'static';
  if (feedLook) return;
  if (eyeMode === 'stars') {
    if (!starTex) starTex = makeStarTexture();
    m.map = starTex;
    m.color.setRGB(1.6, 1.5, 1.2);
  } else {
    m.map = staticNoise();
    m.color.setRGB(1.35, 1.4, 1.45);
  }
  applyVeils();
}

function applyVeils() {
  const stars = eyeMode === 'stars' && !feedLook;
  for (const v of veils) {
    const base = v.userData.zVeil || (v.userData.zVeil = { map: v.map, color: v.color.clone() });
    if (stars) { v.map = starTex; v.color.setRGB(1.5, 1.4, 1.15); }
    else { v.map = base.map; v.color.copy(base.color); }
  }
}

function registerVeil(mat) {
  if (!mat || veils.has(mat) || !mat.color) return;
  veils.add(mat);
  if (eyeMode === 'stars') applyVeils();
}

function applyTint() {
  for (const mat of tinted) {
    const base = mat.userData.zBase || (mat.userData.zBase = { color: mat.color.clone(), emissive: mat.emissive ? mat.emissive.clone() : null });
    mat.color.copy(base.color);
    if (mat.emissive && base.emissive) mat.emissive.copy(base.emissive);
    if (feedLook) {
      mat.color.multiply(new THREE.Color(1.34, 0.93, 0.93));
    } else if (tintMode === 'standby') {
      // Test-card grey with a faint colour-bar tint: darken + lift toward a cool lilac grey.
      mat.color.multiplyScalar(0.5);
      if (mat.emissive) mat.emissive.setRGB(0.2, 0.2, 0.25);
    }
  }
}

// null | 'standby' (PLEASE STAND BY freeze look). Every zombie body material, so all zombies change at once.
export function setZombieTint(mode) {
  tintMode = mode || null;
  applyTint();
}

// Feed-camera look (GDD §8 common): human peach skin + plain eyes. Call around a feed render: on, render, off.
export function setFeedLook(on) {
  on = !!on;
  if (on === feedLook) return;
  feedLook = on;
  applyTint();
  const m = zombieEyeMaterial();
  if (on) {
    if (!normalEyeTex) normalEyeTex = makeNormalEyeTexture();
    m.userData.prev = { map: m.map, color: m.color.clone() };
    m.map = normalEyeTex;
    m.color.setRGB(1, 1, 1);
  } else if (m.userData.prev) {
    m.map = m.userData.prev.map;
    m.color.copy(m.userData.prev.color);
  }
  applyVeils();
}

function registerTint(mat) {
  if (!mat || tinted.has(mat) || !mat.color) return;
  tinted.add(mat);
  if (tintMode || feedLook) applyTint();
}

// ------------------------------------------------------------------------------------------ builders
// variant = index into the type's baked art ids (default: random). Returns the model record (see header).
export function buildZombie(typeId, game, variant = -1) {
  const def = getType(typeId);
  const ids = bakedZombieIds(def.id, game);
  if (ids.length) {
    const k = variant >= 0 ? variant % ids.length : Math.floor(Math.random() * ids.length);
    try {
      return buildBakedZombie(def, ids[k], game);
    } catch (err) {
      if (!warned) { warned = true; console.warn('[zombies] baked zombie failed, using placeholders', err); }
    }
  }
  return buildPlaceholderZombie(def, game);
}

function buildBakedZombie(def, artId, game) {
  const M = game.mats;
  const c = charRuntime.buildCharacter(artDef(artId), { envMap: M.envMap, globals: M.uniforms, layer: LAYERS.ZOMBIES, animator: 'zombie' });
  if (!c.animator || typeof c.animator.update !== 'function') throw new Error(`'${artId}' has no animator`);
  if (typeof c.animator.kick !== 'function') c.animator.kick = () => {};
  const eyes = zombieEyeMaterial();
  const cards = [];
  const bodies = [];
  c.group.traverse((o) => {
    if (!o.isMesh) return;
    if (o.userData.staticEye) o.material = eyes;
    if (o.isSkinnedMesh) { bodies.push(o); registerTint(o.material); }
    o.castShadow = !!o.isSkinnedMesh;
    if (Array.isArray(o.material)) cards.push(o);
  });
  // Merge the static attachments (eye domes, veils, rims, glasses...) per material: 1 draw each instead of 1 per mesh.
  // charOpt.merge (default): charRuntime.mergeAttachments -> the head-only groups become plain meshes on the head
  // joint (no second skeleton, bone texture and skinning per zombie); off = the older geo.skinRig (A/B).
  try {
    if (charRuntime.charOpt && charRuntime.charOpt.merge) charRuntime.mergeAttachments(c);
    else skinRig(c.rig);
  } catch (err) {
    if (!warned) { warned = true; console.warn('[zombies] attachment merge failed', err); }
  }
  // Distance LOD: the eye veil and rim (merged per material above) are only drawn up close (model.details).
  const details = [];
  c.group.traverse((o) => {
    if (o.isSkinnedMesh && !bodies.includes(o)) o.castShadow = false;
    const mn = o.isMesh && !Array.isArray(o.material) && o.material ? o.material.name : '';
    if (o.isMesh && !bodies.includes(o) && (mn === 'zombieEyeVeil' || mn === 'zombieEyeRim')) details.push(o);
    if (mn === 'zombieEyeVeil') registerVeil(o.material);
  });
  const J = c.rig.joints;
  const headR = (c.rig.dims ? c.rig.dims.headH : 0.5) * 0.5;
  const head = new THREE.Object3D();
  head.name = 'part:headCenter';
  head.position.set(0, headR * 0.98, 0);
  (J.head || c.rig.root).add(head);
  c.group.name = `zombie:${def.id}:${artId}`;
  game.render.setLayerRecursive(c.group, LAYERS.ZOMBIES);
  const model = { group: c.group, rig: c.rig, animator: c.animator, head, headR, def, baked: true, art: c, variant: artId, cards, bodies, details, gen: modelGen() };
  // crowd batches (see "crowd batches" below): only on the merged layout (plain head / chest meshes)
  if (charRuntime.charOpt && charRuntime.charOpt.merge) {
    try { crowdRegister(model, c, game); } catch (err) { if (!warned) { warned = true; console.warn('[zombies] crowd batch setup failed', err); } }
  }
  return model;
}

function buildPlaceholderZombie(def, game) {
  const M = game.mats;
  const rig = createRig(def.rig);
  const J = rig.joints, D = rig.dims;
  const toy = (c, o = {}) => M.toon(c, { rough: 0.55, rim: 0.5, rimColor: PAL.rimZombie, keepColor: true, ...o });
  const skin = toy(PAL.zSkin, { wrap: 0.7 });
  const shirt = toy(def.shirts[Math.floor(Math.random() * def.shirts.length)], { rough: 0.7 });
  const pants = toy(PAL.chocolate, { rough: 0.8 });
  const add = (parent, g, mat, pos, rot, scale) => parent.add(geo.mesh(g, mat, { pos, rot, scale }));

  // Head: big mint sphere, snowy eyes, open "O" mouth with teeth.
  const R0 = D.headH / 2;
  const head = geo.mesh(geo.sphere(R0, 26, 18), skin, { pos: [0, R0 * 0.9, 0], scale: [1, 0.96, 0.95] });
  J.head.add(head);
  const eyes = zombieEyeMaterial();
  const rimMat = M.glow(PAL.zEyeRim, 1.8);
  const under = toy(PAL.zUnderEye, { rough: 0.7 });
  for (const s of [-1, 1]) {
    add(head, geo.sphere(R0 * 0.27, 14, 10), under, [s * R0 * 0.38, R0 * 0.02, -R0 * 0.78], null, [1.1, 1, 0.5]);
    add(head, geo.cylinder(R0 * 0.21, R0 * 0.21, 0.02, 18), eyes, [s * R0 * 0.38, R0 * 0.1, -R0 * 0.93], [Math.PI / 2, 0, 0]);
    add(head, geo.torus(R0 * 0.215, R0 * 0.03, 6, 18), rimMat, [s * R0 * 0.38, R0 * 0.1, -R0 * 0.945]);
  }
  add(head, geo.cylinder(R0 * 0.22, R0 * 0.2, 0.03, 18), toy(PAL.zMouth, { rough: 0.9, rim: 0 }), [0, -R0 * 0.42, -R0 * 0.83], [Math.PI / 2 - 0.35, 0, 0], [1, 1, 1.25]);
  for (const x of [-1, 0, 1]) add(head, geo.roundedBox(R0 * 0.12, R0 * 0.12, 0.03, 0.01, 1), toy('#F4F1E8', { rough: 0.4 }), [x * R0 * 0.14, -R0 * 0.26, -R0 * 0.9], [-0.35, 0, 0]);

  // Body.
  add(J.neck, geo.cylinder(R0 * 0.25, R0 * 0.28, 0.1, 12), skin, [0, 0.03, 0]);
  add(J.chest, geo.capsule(0.17, D.torso * 0.55, 6, 14), shirt, [0, D.torso * 0.08, 0], null, [D.shoulderW / 0.36, 1, 0.75]);
  add(J.chest, geo.roundedBox(0.1, 0.06, 0.02, 0.008, 1), toy('#F2E4B0', { rough: 0.8 }), [0.07, D.torso * 0.2, -0.13], [0.1, 0, 0.2]);
  add(J.hips, geo.sphere(D.hipW * 0.75, 14, 10), pants, [0, 0.02, 0], null, [1.3, 0.85, 0.95]);
  for (const side of ['L', 'R']) {
    add(J['shoulder' + side], geo.capsule(0.06, D.upperArm - 0.06, 5, 10), shirt, [0, -D.upperArm / 2, 0]);
    add(J['elbow' + side], geo.capsule(0.052, D.foreArm - 0.06, 5, 10), skin, [0, -D.foreArm / 2, 0]);
    add(J['hand' + side], geo.sphere(0.07, 12, 8), skin, [0, -0.05, 0], null, [0.9, 1.1, 0.7]);
    add(J['hip' + side], geo.capsule(0.08, D.upperLeg - 0.06, 5, 10), pants, [0, -D.upperLeg / 2, 0]);
    add(J['knee' + side], geo.capsule(0.07, D.lowerLeg - 0.06, 5, 10), pants, [0, -D.lowerLeg / 2, 0]);
    add(J['foot' + side], geo.roundedBox(0.13, 0.09, 0.26, 0.04, 2), toy('#4A3428', { rough: 0.5 }), [0, -0.02, -0.05]);
  }

  // Hit-test marker at the head centre (the head sphere itself is merged away below).
  const headMark = new THREE.Object3D();
  headMark.name = 'part:headCenter';
  headMark.position.copy(head.position);
  J.head.add(headMark);
  // Only the big masses cast shadows; then rigid-skinned meshes: every plain toon part in one vertex-coloured mesh
  // (+ the glow materials): ~4 draws + 1 shadow draw per zombie instead of ~50.
  rig.root.traverse((o) => { if (o.isMesh) o.castShadow = o.material === skin || o.material === shirt || o.material === pants; });
  const recolor = toy('#ffffff', { vertexColors: true, wrap: 0.65, rough: 0.6 });
  const merged = skinRig(rig, { recolor });
  registerTint(recolor);
  const bodies = merged.filter((m) => m.castShadow);

  // The animator owns rig.root's transform; the manager moves this wrapper.
  const group = new THREE.Group();
  group.name = `zombie:${def.id}`;
  group.add(rig.root);
  game.render.setLayerRecursive(group, LAYERS.ZOMBIES);
  return { group, rig, animator: new Animator(rig, 'zombie'), head: headMark, headR: R0, def, baked: false, art: null, variant: 'placeholder', cards: [], bodies, details: [], gen: modelGen() };
}

// ------------------------------------------------------------------------------------------ model pool
// Models are pooled per type + variant (building a sculpted zombie costs a few ms and allocates GPU buffers).
// Every model carries the charOpt.gen it was built under; A/B tools bump charOpt.gen after toggling a build-time
// flag and stale pooled models are dropped instead of reused.
const pools = new Map();
export function modelGen() { return (charRuntime.charOpt && charRuntime.charOpt.gen) || 0; }

function poolKey(typeId, variant) { return `${typeId}|${variant}`; }

// A brand-new model of one variant name ('placeholder' or an art id), bypassing the pool.
export function buildVariant(game, typeId, name) {
  const def = getType(typeId);
  if (name === 'placeholder') return buildPlaceholderZombie(def, game);
  const ids = bakedZombieIds(def.id, game);
  const k = ids.indexOf(name);
  return k >= 0 ? buildZombie(def.id, game, k) : buildPlaceholderZombie(def, game);
}

// variant: art id / index, or -1 = random among the baked ones. Returns a model ready to be added to the scene.
export function acquireModel(game, typeId, variant = -1) {
  const def = getType(typeId);
  const ids = bakedZombieIds(def.id, game);
  let name = 'placeholder';
  if (ids.length) name = typeof variant === 'string' ? variant : ids[variant >= 0 ? variant % ids.length : Math.floor(Math.random() * ids.length)];
  const list = pools.get(poolKey(def.id, name));
  while (list && list.length) { const m = list.pop(); if ((m.gen || 0) === modelGen()) return m; }
  if (name === 'placeholder') return buildPlaceholderZombie(def, game);
  const k = ids.indexOf(name);
  return buildZombie(def.id, game, k);
}

export function releaseModel(model) {
  if (!model || !model.group) return;
  model.group.removeFromParent();
  resetModelPose(model);
  const key = poolKey(model.def.id, model.variant);
  let list = pools.get(key);
  if (!list) pools.set(key, (list = []));
  if (list.length < 30 && (model.gen || 0) === modelGen()) list.push(model);
}

// Pre-builds n models per variant of a type into the pool (called once per game so the first wave never hitches).
export function prewarmModels(game, typeId, n = 3) {
  const def = getType(typeId);
  const ids = bakedZombieIds(def.id, game);
  const names = ids.length ? ids : ['placeholder'];
  for (const name of names) {
    const key = poolKey(def.id, name);
    let list = pools.get(key);
    if (!list) pools.set(key, (list = []));
    for (let i = list.length - 1; i >= 0; i--) if ((list[i].gen || 0) !== modelGen()) list.splice(i, 1);
    while (list.length < n) {
      const m = name === 'placeholder' ? buildPlaceholderZombie(def, game) : buildZombie(def.id, game, ids.indexOf(name));
      list.push(m);
    }
  }
}

export function resetModelPose(model) {
  const g = model.group;
  g.visible = true;
  g.scale.set(1, 1, 1);
  g.rotation.set(0, 0, 0);
  g.position.set(0, 0, 0);
  if (model.rig && model.rig.joints) {
    for (const j of Object.values(model.rig.joints)) j.scale.set(1, 1, 1);
    model.rig.root.rotation.set(0, 0, 0);
    model.rig.root.scale.set(1, 1, 1);
  }
  if (model.animator) model.animator.override = null;
  for (const c of model.cards || []) c.visible = true;
  for (const c of model.details || []) c.visible = true;
}

// Humanoid hit zones for a rig model (see HIT ZONES in the header).
export function humanoidHitZones(model) {
  const J = model.rig && model.rig.joints;
  if (!J || !J.hips) return null;
  const D = model.rig.dims || {};
  const sw = D.shoulderW || 0.42;
  const zones = [
    { shape: 'sphere', bone: model.head, offset: [0, 0, 0], r: model.headR * 0.98, zone: 'head', head: true, mul: 1 },
    { shape: 'capsule', bone: J.hips, offset: [0, -0.02, 0], bone2: J.neck, offset2: [0, -0.02, 0], r: Math.max(0.16, sw * 0.44), zone: 'torso', head: false, mul: 1 },
  ];
  for (const s of ['L', 'R']) {
    zones.push({ shape: 'capsule', bone: J['shoulder' + s], offset: [0, 0, 0], bone2: J['hand' + s], offset2: [0, -0.07, 0], r: 0.085, zone: 'limb', head: false, mul: 0.8 });
    zones.push({ shape: 'capsule', bone: J['hip' + s], offset: [0, 0, 0], bone2: J['foot' + s], offset2: [0, 0, 0], r: 0.1, zone: 'limb', head: false, mul: 0.8 });
  }
  return zones;
}

// ------------------------------------------------------------------------------------------ crowd batches
// Perf (characters pass): the rigid attachments of every live baked Tuned-In zombie (static-snow eye domes, veils,
// rims, Mom's glasses, ticket stub / patch cards) are drawn as ONE skinned draw per (look, material) for the whole
// crowd instead of one draw per zombie. A batch is a SkinnedMesh whose geometry holds `cap` copies of the look's part
// (baked in its joint's space); copy k is bound 100 % to bone 2k (the k-th zombie's head) or 2k+1 (its chest) of the
// look's range in ONE shared crowd skeleton (one bone texture for every batch). three reads the joints' world
// matrices while it renders, so the copies never lag. Every frame (zombies.lateUpdate, after the LOD) the zombies of
// a look are sorted by camera distance: the LOD flags are distance rules, so the copies a batch draws are a prefix
// (drawRange). The per-zombie meshes a batch draws for move to LAYERS.TV_ONLY: the main camera skips them, the
// screens' feed cameras still draw them (with their feed-look material swaps); batches live on CROWD_LAYER, which only
// the main camera renders (zombies.init enables it). Anything unusual keeps drawing its own mesh: a hidden zombie or
// part (LOD), a part whose material was swapped (wonder flashes / ice), an out-of-order LOD flag, more zombies of one
// look than CROWD_CAP. Clones of a zombie group (wonder corpses) get those meshes back on LAYERS.ZOMBIES.
// charOpt.crowd = false: no batching (live A/B).
export const CROWD_LAYER = 4;
const CROWD_CAP = 32;                   // zombies of one look per batch; bones reserved per look = 2 x CROWD_CAP
const TV_BIT = 1 << LAYERS.TV_ONLY;
const Z_BIT = 1 << LAYERS.ZOMBIES;
const crowd = { looks: new Map(), skeleton: null, scene: null, excl: new Set(), excl2: new Set() };
const _cn = new THREE.Matrix3();
const _cv = new THREE.Vector3();

function crowdLookIndex(artId) { return ZOMBIE_ART.tuned_in.indexOf(artId); }

// One skeleton for every batch: 2 x CROWD_CAP bones per Tuned-In look, identity inverses (a bone matrix is the joint's
// world matrix). Its update only walks the bone ranges in use and flags the texture when a matrix changed.
function crowdSkeleton() {
  if (crowd.skeleton) return crowd.skeleton;
  const n = ZOMBIE_ART.tuned_in.length * CROWD_CAP * 2;
  const dummy = new THREE.Object3D();
  dummy.matrixWorld.makeScale(0, 0, 0);
  const sk = new THREE.Skeleton(new Array(n).fill(dummy), Array.from({ length: n }, () => new THREE.Matrix4()));
  sk.update = function crowdSkeletonUpdate() {
    const out = this.boneMatrices, bones = this.bones;
    let changed = false;
    for (const L of crowd.looks.values()) {
      const end = L.base + 2 * L.active;
      for (let i = L.base; i < end; i++) {
        const e = bones[i].matrixWorld.elements, o = i * 16;
        for (let k = 0; k < 16; k++) {
          const v = Math.fround(e[k]);
          if (out[o + k] !== v) { out[o + k] = v; changed = true; }
        }
      }
    }
    if (changed && this.boneTexture !== null) this.boneTexture.needsUpdate = true;
  };
  crowd.skeleton = sk;
  return sk;
}

// A part's geometry in its joint's space: the (group's) triangles only, compacted and welded (identical vertices of
// non-indexed parts shared), with only the attributes its material reads: position, normal (lit materials), uv
// (textured), color (vertexColors). Vertex values are copied exactly, so the batch draws the same triangles.
function crowdTemplate(mesh, rel, group, mat) {
  const src = mesh.geometry, P = src.attributes.position, N = src.attributes.normal, U = src.attributes.uv, C = src.attributes.color;
  const wantN = !(mat.isMeshBasicMaterial && !mat.envMap) && !!N;
  const wantU = !!mat.map && !!U;
  const wantC = !!mat.vertexColors;
  const full = src.index ? src.index.array : null;
  const total = full ? full.length : P.count;
  const start = group ? group.start : 0;
  const end = group ? Math.min(group.start + group.count, total) : total;
  const remap = new Int32Array(P.count).fill(-1);
  const weld = new Map();
  const idx = new Uint32Array(end - start);
  const keyOf = (v) => {
    let k = `${P.getX(v)},${P.getY(v)},${P.getZ(v)}`;
    if (wantN) k += `|${N.getX(v)},${N.getY(v)},${N.getZ(v)}`;
    if (wantU) k += `|${U.getX(v)},${U.getY(v)}`;
    if (wantC && C) k += `|${C.getX(v)},${C.getY(v)},${C.getZ(v)}`;
    return k;
  };
  const first = [];
  for (let i = start; i < end; i++) {
    const v = full ? full[i] : i;
    if (remap[v] < 0) {
      const k = keyOf(v);
      let d = weld.get(k);
      if (d === undefined) { d = first.length; first.push(v); weld.set(k, d); }
      remap[v] = d;
    }
    idx[i - start] = remap[v];
  }
  const nv = first.length;
  const pos = new Float32Array(nv * 3), nrm = wantN ? new Float32Array(nv * 3) : null;
  const uv = wantU ? new Float32Array(nv * 2) : null, col = wantC ? new Float32Array(nv * 3).fill(1) : null;
  _cn.getNormalMatrix(rel);
  for (let d = 0; d < nv; d++) {
    const v = first[d];
    _cv.fromBufferAttribute(P, v).applyMatrix4(rel);
    pos[d * 3] = _cv.x; pos[d * 3 + 1] = _cv.y; pos[d * 3 + 2] = _cv.z;
    if (nrm) { _cv.fromBufferAttribute(N, v).applyMatrix3(_cn).normalize(); nrm[d * 3] = _cv.x; nrm[d * 3 + 1] = _cv.y; nrm[d * 3 + 2] = _cv.z; }
    if (uv) { uv[d * 2] = U.getX(v); uv[d * 2 + 1] = U.getY(v); }
    if (col && C) { col[d * 3] = C.getX(v); col[d * 3 + 1] = C.getY(v); col[d * 3 + 2] = C.getZ(v); }
  }
  if (rel.determinant() < 0) for (let i = 0; i < idx.length; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  return { nv, pos, nrm, uv, col, idx };
}

// cap copies of a template, copy k skinned 100 % to bone base + 2k + owner (0 head, 1 chest). 8-bit bone indices
// (the crowd skeleton has 4 looks x CROWD_CAP x 2 = 256 bones).
function crowdGeometry(T, cap, base, owner) {
  const nv = T.nv, ni = T.idx.length;
  const pos = new Float32Array(nv * cap * 3), nrm = T.nrm ? new Float32Array(nv * cap * 3) : null;
  const uv = T.uv ? new Float32Array(nv * cap * 2) : null, col = T.col ? new Float32Array(nv * cap * 3) : null;
  const si = new Uint8Array(nv * cap * 4), sw = new Uint8Array(nv * cap * 4), idx = new Uint32Array(ni * cap);
  for (let k = 0; k < cap; k++) {
    pos.set(T.pos, k * nv * 3);
    if (nrm) nrm.set(T.nrm, k * nv * 3);
    if (uv) uv.set(T.uv, k * nv * 2);
    if (col) col.set(T.col, k * nv * 3);
    const bone = base + 2 * k + owner;
    for (let v = 0; v < nv; v++) { si[(k * nv + v) * 4] = bone; sw[(k * nv + v) * 4] = 255; }
    for (let i = 0; i < ni; i++) idx[k * ni + i] = T.idx[i] + k * nv;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  if (nrm) g.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  if (uv) g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  if (col) g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4));
  g.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4, true));
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  g.setDrawRange(0, 0);
  return g;
}

function crowdMesh(P, cap, base, skeleton, name) {
  const m = new THREE.SkinnedMesh(crowdGeometry(P.T, cap, base, P.owner), P.mat);
  m.name = name;
  m.bind(skeleton, new THREE.Matrix4());
  m.boundingSphere = new THREE.Sphere();
  m.castShadow = false;
  m.receiveShadow = false;
  m.renderOrder = P.renderOrder;
  m.layers.set(CROWD_LAYER);
  m.visible = false;
  return m;
}

// The per-zombie meshes a batch can replace: rigid meshes whose nearest joint is the head or the chest.
// Returns [{ mesh, parent, owner, parts: [{ group, mat }], rel, multi }] in traversal order.
function crowdSlots(c) {
  const J = c.rig.joints, head = J.head, chest = J.chest;
  if (!head || !chest) return null;
  const joints = new Set(Object.values(J));
  c.rig.root.updateMatrixWorld(true);
  const out = [];
  c.group.traverse((o) => {
    if (!o.isMesh || o.isSkinnedMesh || o.isInstancedMesh || o.isBatchedMesh || !o.material || o.morphTargetInfluences) return;
    let p = o.parent;
    for (; p && !joints.has(p); p = p.parent) if (p.userData.dynamic || p.userData.noMerge) return;
    if (p !== head && p !== chest) return;
    const parts = [];
    if (Array.isArray(o.material)) {
      if (!o.geometry.groups.length) return;
      for (const gr of o.geometry.groups) { const mat = o.material[gr.materialIndex]; if (!mat) return; parts.push({ group: gr, mat }); }
    } else parts.push({ group: null, mat: o.material });
    const rel = new THREE.Matrix4().copy(p.matrixWorld).invert().multiply(o.matrixWorld);
    out.push({ mesh: o, parent: o.parent, owner: p === head ? 0 : 1, parts, rel, multi: Array.isArray(o.material) });
  });
  return out;
}

const slotSig = (s) => s.parts.map((p) => p.mat.uuid).join(',') + '|' + s.mesh.geometry.attributes.position.count;

// Called for every baked Tuned-In model at build time: registers the look (templates + batch meshes) on its first
// model; later models must match it (same parts, same materials) or they simply draw their own meshes.
function crowdRegister(model, c, game) {
  if (crowdLookIndex(model.variant) < 0 || !game || !game.scene) return;
  const slots = crowdSlots(c);
  if (!slots || !slots.length) return;
  let L = crowd.looks.get(model.variant);
  if (!L) {
    const sk = crowdSkeleton();
    crowd.scene = game.scene;
    L = { id: model.variant, base: crowdLookIndex(model.variant) * CROWD_CAP * 2, cap: 8, active: 0, list: [], slots: [], sphere: new THREE.Sphere() };
    for (const s of slots) {
      const S = { parts: [], sig: slotSig(s) };
      for (const pr of s.parts) {
        const P = { T: crowdTemplate(s.mesh, s.rel, pr.group, pr.mat), mat: pr.mat, owner: s.owner, renderOrder: s.mesh.renderOrder };
        P.idx = P.T.idx.length;
        P.mesh = crowdMesh(P, L.cap, L.base, sk, `crowd:${model.variant}:${pr.mat.name || pr.mat.type}`);
        game.scene.add(P.mesh);
        S.parts.push(P);
      }
      L.slots.push(S);
    }
    crowd.looks.set(model.variant, L);
  }
  if (L.slots.length !== slots.length) return;
  for (let i = 0; i < slots.length; i++) if (L.slots[i].sig !== slotSig(slots[i])) return;
  model.crowd = {
    look: L, head: c.rig.joints.head, chest: c.rig.joints.chest,
    slots: slots.map((s) => ({ mesh: s.mesh, parent: s.parent, mats: s.parts.map((p) => p.mat), multi: s.multi })),
  };
  // wonder-weapon corpses (SkeletonUtils.clone -> group.clone()): the clone's meshes draw on the zombie layer
  model.group.clone = function crowdClone(recursive) {
    const cl = THREE.Object3D.prototype.clone.call(this, recursive);
    cl.traverse((o) => { if (o.isMesh && o.layers.mask === TV_BIT) o.layers.mask = Z_BIT; });
    return cl;
  };
}

// Grows a look's batches to at least n copies (x2 steps, up to CROWD_CAP): rebuilt geometry, same programs.
function crowdGrow(L, n) {
  let cap = L.cap;
  while (cap < n && cap < CROWD_CAP) cap *= 2;
  cap = Math.min(cap, CROWD_CAP);
  if (cap === L.cap) return;
  L.cap = cap;
  for (const S of L.slots) for (const P of S.parts) {
    const old = P.mesh.geometry;
    P.mesh.geometry = crowdGeometry(P.T, cap, L.base, P.owner);
    old.dispose();
  }
}

function crowdVisible(o) { for (; o; o = o.parent) { if (!o.visible) return false; if (o === crowd.scene) return true; } return false; }

// a per-zombie mesh the batch may stand in for: still where it was, visible, with its own material(s)
function crowdDrawable(e) {
  const m = e.mesh;
  if (!m.visible || m.parent !== e.parent) return false;
  if (!e.multi) return m.material === e.mats[0];
  const a = m.material;
  if (!Array.isArray(a)) return false;
  for (let i = 0; i < e.mats.length; i++) if (a.indexOf(e.mats[i]) < 0) return false;
  return true;
}

const byCrowd = (a, b) => (b._crowdOk - a._crowdOk) || (a.camDist - b.camDist);

function crowdCollect(list) {
  for (let i = 0; i < list.length; i++) {
    const z = list[i], m = z.model;
    if (!m || !m.crowd || m.group !== z.group) continue;
    z._crowdOk = crowdVisible(z.group) ? 1 : 0;
    if (!(z.camDist >= 0)) z.camDist = 0;
    m.crowd.look.list.push(z);
  }
}

function crowdLayout(L, excl) {
  const list = L.list;
  list.sort(byCrowd);
  let n = 0;
  while (n < list.length && n < CROWD_CAP && list[n]._crowdOk) n++;
  if (n > L.cap) crowdGrow(L, n);
  n = Math.min(n, L.cap);
  const bones = crowd.skeleton.bones;
  let x0 = Infinity, y0 = Infinity, z0 = Infinity, x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
  for (let k = 0; k < n; k++) {
    const z = list[k], cr = z.model.crowd;
    bones[L.base + 2 * k] = cr.head;
    bones[L.base + 2 * k + 1] = cr.chest;
    // conservative bounds: a toppled zombie's head lies ~1.6 m from its feet
    const r = (z.height || 1.7) * 1.25 * (z.scale || 1);
    x0 = Math.min(x0, z.pos.x - r); y0 = Math.min(y0, z.pos.y - r); z0 = Math.min(z0, z.pos.z - r);
    x1 = Math.max(x1, z.pos.x + r); y1 = Math.max(y1, z.pos.y + r); z1 = Math.max(z1, z.pos.z + r);
  }
  L.active = n;
  const S0 = L.sphere;
  if (n) {
    S0.center.set((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    S0.radius = Math.hypot(x1 - x0, y1 - y0, z1 - z0) / 2;
  }
  for (let s = 0; s < L.slots.length; s++) {
    const S = L.slots[s];
    let cnt = 0;
    while (cnt < n && crowdDrawable(list[cnt].model.crowd.slots[s])) cnt++;
    for (let k = 0; k < cnt; k++) {
      const mesh = list[k].model.crowd.slots[s].mesh;
      mesh.layers.mask = TV_BIT;
      excl.add(mesh);
    }
    for (const P of S.parts) {
      P.mesh.geometry.drawRange.count = cnt * P.idx;
      P.mesh.visible = cnt > 0;
      if (cnt) P.mesh.boundingSphere.copy(S0);
    }
  }
}

function crowdHide(L) {
  L.active = 0;
  L.list.length = 0;
  for (const S of L.slots) for (const P of S.parts) { P.mesh.visible = false; P.mesh.geometry.drawRange.count = 0; }
}

// zombies.lateUpdate: lays out every batch for this frame's alive + dying zombies.
export function updateCrowd(alive, dying) {
  if (!crowd.looks.size) return;
  const excl = crowd.excl2;
  excl.clear();
  if (charRuntime.charOpt && charRuntime.charOpt.crowd === false) {
    for (const L of crowd.looks.values()) crowdHide(L);
  } else {
    for (const L of crowd.looks.values()) L.list.length = 0;
    crowdCollect(alive);
    crowdCollect(dying);
    for (const L of crowd.looks.values()) { if (L.list.length) crowdLayout(L, excl); else crowdHide(L); L.list.length = 0; }
  }
  // meshes no batch stands in for any more draw themselves again
  for (const m of crowd.excl) if (!excl.has(m)) m.layers.mask = Z_BIT;
  crowd.excl2 = crowd.excl;
  crowd.excl = excl;
}

// New game / reset: no batch draws until the next layout.
export function resetCrowd() {
  for (const L of crowd.looks.values()) crowdHide(L);
  for (const m of crowd.excl) m.layers.mask = Z_BIT;
  crowd.excl.clear();
}

// Game.precompile samples: one small batch per look and part (same materials, same vertex layout as the real
// batches), so the skinned program variants are compiled and first-drawn at load.
export function crowdWarmup() {
  const out = [];
  if (!crowd.looks.size) return out;
  const b0 = new THREE.Object3D(), b1 = new THREE.Object3D();
  const sk = new THREE.Skeleton([b0, b1], [new THREE.Matrix4(), new THREE.Matrix4()]);
  for (const L of crowd.looks.values()) for (const S of L.slots) for (const P of S.parts) {
    const m = new THREE.SkinnedMesh(crowdGeometry(P.T, 1, 0, P.owner), P.mat);
    m.geometry.setDrawRange(0, Infinity);
    m.bind(sk, new THREE.Matrix4());
    m.renderOrder = P.renderOrder;
    m.layers.set(CROWD_LAYER);
    m.frustumCulled = false;
    m.name = 'crowd:warmup';
    out.push(m);
  }
  return out;
}

// counters for perf tools: { looks, batches, active zombies, batches drawn, verts per zombie, vertex MB allocated }
export function crowdStats() {
  const s = { looks: crowd.looks.size, batches: 0, active: 0, drawn: 0, caps: {}, vertsPerZombie: {}, mb: 0 };
  for (const L of crowd.looks.values()) {
    s.active += L.active;
    s.caps[L.id] = L.cap;
    let nv = 0;
    for (const S of L.slots) for (const P of S.parts) {
      s.batches++;
      if (P.mesh.visible) s.drawn++;
      nv += P.T.nv;
      const g = P.mesh.geometry;
      for (const a of Object.values(g.attributes)) s.mb += a.array.byteLength / 1048576;
      if (g.index) s.mb += g.index.array.byteLength / 1048576;
    }
    s.vertsPerZombie[L.id] = nv;
  }
  s.mb = Math.round(s.mb * 10) / 10;
  return s;
}
