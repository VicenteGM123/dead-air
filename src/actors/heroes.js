// Heroes (ARCHITECTURE §10/§12, GDD §4): HEROES data + buildHero(). DEFAULT_HERO = 'duke' (GDD §4: default /
// first hero, preselected in character select and used by test=1).
//   HEROES = [{ id, name, role, rig, colors }] (GDD §4, rig spec overrides from the §4 table),
//   buildHero(heroId, game = window.__game) -> { group, rig, animator, parts:{ head, torso, handL, handR },
//     slots:{ head, handL, handR, footL, footR, back, wristL, wristR, neck, belt }, hairBounds, def, baked, art }.
// Art adapter: if src/art/charRuntime.js exports buildCharacter and a baked character exists for the hero id
// (charRuntime.characterIds()), the sculpted SkinnedMesh character is used (same engine rig + Animator, §12 slots,
// face API in result.art.face); `baked` is true and the caller must NOT merge its joints (face attachments animate).
// Otherwise (or if the art build throws) the placeholder below is built: a chunky big-head toy made of primitives
// with the right silhouette cue (cap, afro, long hair, feathered hair + mustache). URL param art=0 forces placeholders.

import * as THREE from 'three';
import { createRig, Animator } from '../core/rig.js';
import * as geo from '../core/geo.js';
import { plaid, stripes } from '../core/textures.js';
import { PAL } from '../core/config.js';
import * as charRuntime from '../art/charRuntime.js';

export const DEFAULT_HERO = 'duke';

export const HEROES = [
  { id: 'skip', name: 'Skip Kowalski', role: 'Floor runner', rig: { height: 1.60, headScale: 1.10, shoulderW: 0.38, hipW: 0.24, legLen: 0.70 },
    colors: { skin: '#F2BE98', hair: '#6B3A1E', top: PAL.wztvBlue, sleeve: PAL.wztvBlue, pants: '#B5703A', shoes: PAL.wztvBlue, iris: '#6B3A1E' } },
  { id: 'roxy', name: 'Roxy Rivers', role: 'Dance-show host', rig: { height: 1.70, headScale: 1.05, shoulderW: 0.40, hipW: 0.27, legLen: 0.80 },
    colors: { skin: '#8A5A3C', hair: '#3A2418', top: '#F7F0E4', sleeve: null, pants: '#D8322B', shoes: PAL.cream, iris: '#4A2A18' } },
  { id: 'penny', name: 'Penny Watts', role: 'Broadcast engineer', rig: { height: 1.68, headScale: 1.05, shoulderW: 0.38, hipW: 0.26, legLen: 0.78 },
    colors: { skin: '#F4C3A0', hair: '#5A3320', top: '#F0641E', sleeve: '#F0641E', pants: '#4A2A24', shoes: PAL.cream, iris: '#5A3320' } },
  { id: 'duke', name: 'Duke Dalton', role: 'Cop-show star', rig: { height: 1.80, headScale: 1.00, shoulderW: 0.46, hipW: 0.27, legLen: 0.82 },
    colors: { skin: '#E9AE86', hair: '#5A3320', top: '#F07A1E', sleeve: '#F07A1E', pants: '#3A4FA0', shoes: '#6B3A1E', iris: '#3A2418' } },
];

// True when a sculpted/baked character is available for this id (and art is not disabled with ?art=0).
export function hasBakedHero(heroId, game = window.__game) {
  if (game && game.params && game.params.art === 0) return false;
  try {
    return typeof charRuntime.buildCharacter === 'function' && typeof charRuntime.characterIds === 'function'
      && charRuntime.characterIds().includes(heroId);
  } catch (err) {
    return false;
  }
}

export function buildHero(heroId, game = window.__game) {
  const def = HEROES.find((h) => h.id === heroId) || HEROES.find((h) => h.id === DEFAULT_HERO);
  if (hasBakedHero(def.id, game)) {
    try {
      return buildBakedHero(def, game);
    } catch (err) {
      console.warn(`[heroes] baked '${def.id}' failed, using the placeholder`, err);
    }
  }
  return buildPlaceholderHero(def, game);
}

// Sculpted character from src/art (charRuntime.buildCharacter) mapped onto the buildHero contract.
function buildBakedHero(def, game) {
  const M = game.mats;
  // merge: brows join the body mesh and the face / glasses / costume attachments merge per material (animated eye
  // nodes become extra bones of the body skeleton): Duke 23 -> 7 draws, same image (charRuntime.mergeCharacter).
  const c = charRuntime.buildCharacter(def.id, { envMap: M.envMap, globals: M.uniforms, heroFade: true, merge: true });
  const J = c.rig.joints, D = c.rig.dims;
  const missing = SLOT_NAMES.filter((k) => !c.slots || !c.slots[k]);
  if (missing.length) throw new Error(`charRuntime result lacks slots ${missing.join(', ')}`);
  if (!c.animator) throw new Error('charRuntime result lacks an animator');
  // parts.head = head centre (hit tests, look-at, head costumes); torso = the chest joint.
  const head = new THREE.Object3D();
  head.name = 'part:headCenter';
  head.position.set(0, D.headH * 0.5, 0);
  J.head.add(head);
  c.group.name = `hero:${def.id}`;
  return {
    group: c.group, rig: c.rig, animator: c.animator,
    parts: { head, torso: J.chest, handL: J.handL, handR: J.handR },
    slots: c.slots, hairBounds: c.hairBounds, def, baked: true, art: c,
  };
}

const SLOT_NAMES = ['head', 'handL', 'handR', 'footL', 'footR', 'back', 'wristL', 'wristR', 'neck', 'belt'];

function buildPlaceholderHero(def, game) {
  const heroId = def.id;
  const M = game.mats;
  const C = def.colors;
  const rig = createRig(def.rig);
  const J = rig.joints, D = rig.dims;
  const toy = (color, o = {}) => M.toon(color, { rough: 0.5, rim: 0.35, rimColor: PAL.rimHero, keepColor: true, ...o });
  const skin = M.skin(C.skin);
  const add = (parent, g, mat, pos, rot, scale) => {
    const m = geo.mesh(g, mat, { pos, rot, scale });
    parent.add(m);
    return m;
  };

  // --- Head -------------------------------------------------------------------------------------------
  const R = D.headH / 2;
  const head = new THREE.Group();
  head.position.y = R * 0.92;
  J.head.add(head);
  add(head, geo.sphere(R, 32, 24), skin, [0, 0, 0], null, [1, 1, 0.96]);
  add(head, geo.sphere(R * 0.8, 24, 16), skin, [0, -R * 0.28, -R * 0.1], null, [1.05, 0.9, 1]);
  for (const s of [-1, 1]) {
    add(head, geo.sphere(R * 0.2, 12, 10), skin, [s * R * 0.96, -R * 0.05, R * 0.02], null, [0.55, 1, 0.8]);
    const ex = s * R * 0.37;
    add(head, geo.sphere(R * 0.22, 18, 14), toy('#FFFFFF', { rough: 0.2 }), [ex, R * 0.06, -R * 0.78], null, [1, 1.15, 0.62]);
    add(head, geo.sphere(R * 0.13, 16, 12), toy(C.iris, { rough: 0.2 }), [ex, R * 0.04, -R * 0.9], null, [1, 1.1, 0.45]);
    add(head, geo.sphere(R * 0.07, 12, 10), toy('#1E1422', { rough: 0.15 }), [ex, R * 0.04, -R * 0.955], null, [1, 1.1, 0.4]);
    add(head, geo.sphere(R * 0.035, 8, 6), M.glow('#FFFFFF', 1.6), [ex + R * 0.05, R * 0.12, -R * 0.99]);
    add(head, geo.capsule(R * 0.035, R * 0.2, 4, 8), toy(C.hair), [ex, R * 0.4, -R * 0.84], [0, 0, Math.PI / 2 + s * (heroId === 'duke' ? 0.25 : -0.12)]);
  }
  add(head, geo.sphere(R * 0.13, 12, 10), M.skin(shade(C.skin, -0.08)), [0, -R * 0.14, -R * 0.98]);
  const smile = add(head, geo.torus(R * 0.2, R * 0.032, 8, 18, Math.PI * 0.62), toy('#6B2E3A', { rough: 0.4 }),
    [0, -R * 0.3, -R * 0.9], [0.2, 0, -Math.PI / 2 - Math.PI * 0.31]);
  if (heroId === 'duke') smile.scale.set(0.8, 0.5, 1);

  // --- Torso, neck, hips ----------------------------------------------------------------------------
  add(J.neck, geo.cylinder(R * 0.3, R * 0.32, 0.12, 14), skin, [0, 0.03, 0]);
  const torsoW = D.shoulderW / 0.34;
  const topMat = heroId === 'duke' ? toy('#ffffff', { map: stripes(['#F07A1E', '#F7C531', PAL.cream, '#F7C531'], true, 12), rough: 0.6 }) : toy(C.top, { rough: 0.6 });
  const torsoLen = heroId === 'roxy' ? D.torso * 0.42 : D.torso * 0.62;
  const torso = add(J.chest, geo.capsule(0.16, torsoLen, 8, 18), topMat, [0, heroId === 'roxy' ? D.torso * 0.2 : D.torso * 0.08, 0], null, [torsoW, 1, 0.74]);
  if (heroId === 'roxy') add(J.spine, geo.capsule(0.13, D.torso * 0.3, 6, 14), skin, [0, D.torso * 0.28, 0], null, [torsoW * 0.95, 1, 0.72]);
  if (heroId === 'skip') {
    add(J.chest, geo.roundedBox(0.13, D.torso * 0.85, 0.05, 0.02, 2), toy('#FFFFFF', { rough: 0.7 }), [0, D.torso * 0.02, -0.112]);
    add(J.chest, geo.roundedBox(0.08, 0.1, 0.012, 0.008, 1), toy('#FFFFFF', { rough: 0.4 }), [-0.1, D.torso * 0.18, -0.12], [0, 0, 0.05]);
  }
  if (heroId === 'penny') add(J.neck, geo.torus(R * 0.36, 0.045, 10, 20), toy(C.top, { rough: 0.8 }), [0, -0.01, 0], [Math.PI / 2, 0, 0]);
  if (heroId === 'duke') {
    for (const s of [-1, 1]) add(J.chest, geo.roundedBox(0.12, 0.02, 0.1, 0.01, 1), toy('#F7C531', { rough: 0.5 }), [s * 0.07, D.torso * 0.5, -0.1], [0.6, s * 0.5, s * 0.5]);
  }
  const pantsMat = heroId === 'skip'
    ? toy('#ffffff', { map: plaid(C.pants, [['#D98A4E', 0.2, 0.05], [PAL.cream, 0.05, 0.5], ['#7A4A2A', 0.07, 0.72]], 2), rough: 0.85 })
    : toy(C.pants, { rough: heroId === 'duke' ? 0.8 : 0.6 });
  add(J.hips, geo.sphere(D.hipW * 0.78, 18, 12), heroId === 'penny' ? toy('#6B4226', { rough: 0.85 }) : pantsMat, [0, 0.02, 0], null, [1.3, 0.85, 0.95]);
  add(J.hips, geo.cylinder(D.hipW * 0.98, D.hipW * 0.98, 0.055, 20), toy('#5A3A22', { rough: 0.5 }), [0, 0.1, 0], null, [1.02, 1, 0.78]);
  add(J.hips, geo.roundedBox(0.07, 0.05, 0.02, 0.01, 1), M.toon(heroId === 'skip' ? '#C9CED6' : PAL.marqueeGold, { metal: 1, rough: 0.25, keepColor: true }), [0, 0.1, -D.hipW * 0.77]);

  // --- Legs -----------------------------------------------------------------------------------------
  const flare = { skip: 0.16, roxy: 0.2, duke: 0.17, penny: 0 }[heroId] ?? 0.15;
  for (const side of ['L', 'R']) {
    const legMat = heroId === 'penny' ? toy(C.pants, { rough: 0.7 }) : pantsMat;
    add(J['hip' + side], geo.capsule(0.078, D.upperLeg - 0.06, 6, 12), legMat, [0, -D.upperLeg / 2, 0]);
    const L = D.lowerLeg;
    if (flare) {
      add(J['knee' + side], geo.lathe([[0.001, -L - 0.035], [flare, -L - 0.035], [flare * 0.72, -L * 0.72], [0.084, -L * 0.36], [0.078, 0.04], [0.001, 0.06]], 20), legMat);
    } else {
      add(J['knee' + side], geo.capsule(0.066, L - 0.05, 6, 12), legMat, [0, -L / 2, 0]);
      add(J['knee' + side], geo.cylinder(0.085, 0.078, L * 0.72, 16), toy(C.shoes, { rough: 0.3 }), [0, -L * 0.62, 0]);
    }
    const shoe = heroId === 'roxy' ? 0.13 : 0.1;
    add(J['foot' + side], geo.roundedBox(0.13, shoe, 0.27, 0.045, 2), toy(C.shoes, { rough: 0.4 }), [0, -0.02, -0.05]);
    add(J['foot' + side], geo.roundedBox(0.14, 0.04, 0.285, 0.018, 2), toy(heroId === 'skip' ? '#F4F1E8' : '#6B3A1E', { rough: 0.6 }), [0, -0.07, -0.05]);
  }
  if (heroId === 'penny') {
    add(J.hips, geo.lathe([[0.26, -0.24], [0.2, -0.02], [0.17, 0.12], [0.001, 0.13]], 20), toy('#6B4226', { rough: 0.85 }), [0, 0, 0], null, [1, 1, 0.82]);
    for (let i = 0; i < 3; i++) add(J.hips, geo.sphere(0.018, 8, 6), M.toon(PAL.marqueeGold, { metal: 1, rough: 0.25, keepColor: true }), [0, 0.02 - i * 0.07, -0.2 - i * 0.012]);
  }

  // --- Arms -----------------------------------------------------------------------------------------
  const sleeveMat = C.sleeve ? (heroId === 'duke' ? topMat : toy(C.sleeve, { rough: 0.6 })) : null;
  const longSleeves = heroId === 'penny' || heroId === 'duke';
  for (const side of ['L', 'R']) {
    const sh = J['shoulder' + side], el = J['elbow' + side], ha = J['hand' + side];
    add(sh, geo.sphere(0.078, 14, 10), sleeveMat || topMat, [0, -0.01, 0]);
    add(sh, geo.capsule(0.055, D.upperArm - 0.07, 6, 10), longSleeves ? sleeveMat : skin, [0, -D.upperArm / 2, 0]);
    if (sleeveMat && !longSleeves) {
      add(sh, geo.cylinder(0.078, 0.072, 0.15, 14), sleeveMat, [0, -0.07, 0]);
      add(sh, geo.cylinder(0.075, 0.075, 0.03, 14), toy('#FFFFFF', { rough: 0.6 }), [0, -0.145, 0]);
    }
    add(el, geo.capsule(0.05, D.foreArm - 0.06, 6, 10), longSleeves ? sleeveMat : skin, [0, -D.foreArm / 2, 0]);
    if (longSleeves) add(el, geo.cylinder(0.062, 0.062, 0.05, 14), heroId === 'duke' ? toy('#F7C531', { rough: 0.5 }) : sleeveMat, [0, -D.foreArm + 0.04, 0]);
    add(ha, geo.sphere(0.068, 14, 10), skin, [0, -0.05, 0], null, [0.85, 1.1, 0.72]);
    add(ha, geo.capsule(0.022, 0.035, 4, 8), skin, [side === 'L' ? 0.045 : -0.045, -0.035, -0.035], [0.4, 0, side === 'L' ? -0.6 : 0.6]);
  }

  // --- Hair & signature pieces ----------------------------------------------------------------------
  const hairMat = toy(C.hair, { rough: 0.8, rim: 0.3 });
  let hairBounds = R * 1.25;
  if (heroId === 'skip') buildSkipHead(head, R, add, toy, hairMat, M);
  else if (heroId === 'roxy') hairBounds = buildRoxyHead(head, R, add, toy, hairMat, M);
  else if (heroId === 'penny') buildPennyHead(head, R, add, toy, hairMat, M, J);
  else buildDukeHead(head, R, add, toy, hairMat, M);

  // --- Slots (ARCHITECTURE §12) ----------------------------------------------------------------------
  const slot = (parent, name, pos) => {
    const o = new THREE.Object3D();
    o.name = `slot:${name}`;
    o.position.set(pos[0], pos[1], pos[2]);
    parent.add(o);
    return o;
  };
  const slots = {
    head: slot(head, 'head', [0, R * 0.95, 0]),
    handL: slot(J.handL, 'handL', [0, -0.06, 0]),
    handR: slot(J.handR, 'handR', [0, -0.06, 0]),
    footL: slot(J.footL, 'footL', [0, -0.04, -0.05]),
    footR: slot(J.footR, 'footR', [0, -0.04, -0.05]),
    back: slot(J.chest, 'back', [0, D.torso * 0.15, 0.14]),
    wristL: slot(J.elbowL, 'wristL', [0, -D.foreArm * 0.85, 0]),
    wristR: slot(J.elbowR, 'wristR', [0, -D.foreArm * 0.85, 0]),
    neck: slot(J.neck, 'neck', [0, 0, 0]),
    belt: slot(J.hips, 'belt', [0, 0.08, -D.hipW * 0.75]),
  };

  const group = new THREE.Group();
  group.name = `hero:${def.id}`;
  group.add(rig.root);
  const animator = new Animator(rig, 'hero');
  // parts are Object3Ds that survive merging (player.setHero skin-merges the meshes): head = head group, torso = chest.
  return { group, rig, animator, parts: { head, torso: J.chest, handL: J.handL, handR: J.handR }, slots, hairBounds, def, baked: false, art: null };
}

function shade(hex, amt) {
  const c = new THREE.Color(hex);
  c.multiplyScalar(1 + amt);
  return '#' + c.getHexString();
}

function buildSkipHead(head, R, add, toy, hairMat, M) {
  // Curly hair bulging under the cap.
  for (let i = 0; i < 16; i++) {
    const a = -Math.PI * 0.82 + (i / 15) * Math.PI * 1.64; // around the back (+z), clear of the face
    const r = 0.07 + ((i * 37) % 5) * 0.006;
    add(head, geo.sphere(r, 12, 10), hairMat, [Math.sin(a) * R * 0.98, R * (0.12 + 0.18 * ((i * 13) % 3) / 2), Math.cos(a) * R * 0.92]);
  }
  // Lower row covering the nape, then the curls over the ears.
  for (let i = 0; i < 9; i++) {
    const a = -Math.PI * 0.55 + (i / 8) * Math.PI * 1.1;
    add(head, geo.sphere(0.075 + (i % 3) * 0.008, 12, 10), hairMat, [Math.sin(a) * R * 0.82, -R * (0.22 + (i % 2) * 0.12), Math.cos(a) * R * 0.8]);
  }
  for (const s of [-1, 1]) add(head, geo.sphere(0.065, 10, 8), hairMat, [s * R * 1.02, -R * 0.2, R * 0.05]);
  // Cap: blue crown, white front panel, visor, button, "13" badge.
  const blue = toy(PAL.wztvBlue, { rough: 0.45 });
  add(head, new THREE.SphereGeometry(R * 1.06, 28, 14, 0, Math.PI * 2, 0, Math.PI / 2), blue, [0, R * 0.22, 0], null, [1, 0.92, 1]);
  add(head, new THREE.SphereGeometry(R * 1.075, 20, 12, Math.PI * 0.72, Math.PI * 0.56, 0.12, Math.PI * 0.38), toy(PAL.capWhite, { rough: 0.5 }), [0, R * 0.22, 0], null, [1, 0.92, 1]);
  add(head, geo.roundedBox(R * 1.35, 0.035, R * 0.95, 0.016, 2), blue, [0, R * 0.26, -R * 1.02], [0.12, 0, 0]);
  add(head, geo.sphere(0.028, 8, 6), blue, [0, R * 1.2, 0]);
  add(head, geo.cylinder(R * 0.24, R * 0.24, 0.012, 20), toy(PAL.capWhite, { rough: 0.4 }), [0, R * 0.66, -R * 0.97], [Math.PI / 2 - 0.55, 0, 0]);
  add(head, geo.torus(R * 0.24, 0.012, 6, 20), toy(PAL.channelRed, { rough: 0.4 }), [0, R * 0.66, -R * 0.975], [-0.55, 0, 0]);
  // Big square glasses.
  const frame = toy('#1E1624', { rough: 0.3 });
  for (const s of [-1, 1]) add(head, geo.torus(R * 0.27, R * 0.04, 6, 4), frame, [s * R * 0.37, R * 0.05, -R * 0.93], [0, 0, Math.PI / 4], [1, 0.85, 1]);
  add(head, geo.capsule(R * 0.03, R * 0.12, 4, 6), frame, [0, R * 0.1, -R * 0.97], [0, 0, Math.PI / 2]);
  // Headphones around the neck.
  add(head, geo.torus(R * 0.62, 0.022, 8, 24, Math.PI * 1.1), toy('#2A2230', { rough: 0.35 }), [0, -R * 1.05, 0.02], [Math.PI / 2, 0, Math.PI * 0.95]);
  for (const s of [-1, 1]) add(head, geo.cylinder(0.055, 0.055, 0.05, 16), toy('#2A2230', { rough: 0.35 }), [s * R * 0.58, -R * 1.1, -R * 0.2], [0, 0, Math.PI / 2]);
}

function buildRoxyHead(head, R, add, toy, hairMat, M) {
  // Huge afro: spheres on an ellipsoid, clear of the face.
  const n = 44;
  const c = new THREE.Vector3(0, R * 0.45, R * 0.12);
  for (let i = 0; i < n; i++) {
    const y = 1 - (i / (n - 1)) * 2;
    const r = Math.sqrt(1 - y * y);
    const phi = i * 2.39996;
    const x = Math.cos(phi) * r, z = Math.sin(phi) * r;
    if (z < -0.35 && y < 0.35) continue;
    if (y < -0.75) continue;
    const s = 0.12 + ((i * 7) % 5) * 0.01;
    add(head, geo.sphere(s, 14, 10), hairMat, [c.x + x * 0.3, c.y + y * 0.3, c.z + z * 0.28]);
  }
  // Core mass sits back and up so the face stays clear (it used to cover the eyes from the front).
  add(head, geo.sphere(R * 1.2, 20, 16), hairMat, [c.x, c.y + R * 0.12, c.z + R * 0.42]);
  add(head, geo.torus(R * 1.02, 0.035, 8, 28), toy('#F08A1E', { rough: 0.5 }), [0, R * 0.42, 0], [Math.PI / 2 + 0.35, 0, 0]);
  const gold = M.toon(PAL.marqueeGold, { metal: 1, rough: 0.2, keepColor: true });
  for (const s of [-1, 1]) add(head, geo.torus(0.045, 0.009, 6, 18), gold, [s * R * 1.0, -R * 0.35, 0], [0, Math.PI / 2, 0]);
  return 0.42;
}

function buildPennyHead(head, R, add, toy, hairMat, M, J) {
  add(head, geo.sphere(R * 1.1, 24, 18), hairMat, [0, R * 0.12, R * 0.14], null, [1.02, 1.05, 0.95]);
  add(head, new THREE.SphereGeometry(R * 1.1, 20, 10, Math.PI * 0.6, Math.PI * 0.8, 0, Math.PI * 0.32), hairMat, [0, R * 0.14, 0.0], [0, 0, -0.15]);
  for (let i = 0; i < 6; i++) {
    const a = Math.PI * 0.55 + (i / 5) * Math.PI * 0.9;
    add(head, geo.capsule(0.06, 0.34, 6, 10), hairMat, [Math.sin(a) * R * 0.85, -R * 0.75, Math.cos(a) * R * 0.75 + R * 0.1], [0.12 * Math.cos(a), 0, -0.12 * Math.sin(a)]);
  }
  add(head, geo.torus(R * 1.04, 0.03, 8, 28, Math.PI * 1.1), toy('#F0641E', { rough: 0.5 }), [0, R * 0.55, 0], [Math.PI / 2 + 0.5, 0, Math.PI * 0.95]);
  const frame = toy('#1E1624', { rough: 0.3 });
  for (const s of [-1, 1]) add(head, geo.torus(R * 0.24, R * 0.035, 8, 20), frame, [s * R * 0.37, R * 0.05, -R * 0.93]);
  add(head, geo.capsule(R * 0.03, R * 0.1, 4, 6), frame, [0, R * 0.1, -R * 0.97], [0, 0, Math.PI / 2]);
  const gold = M.toon(PAL.marqueeGold, { metal: 1, rough: 0.2, keepColor: true });
  for (const s of [-1, 1]) add(head, geo.torus(0.04, 0.009, 6, 18), gold, [s * R * 1.0, -R * 0.35, 0], [0, Math.PI / 2, 0]);
  add(J.chest, geo.cylinder(0.045, 0.045, 0.012, 18), gold, [0, 0.02, -0.125], [Math.PI / 2, 0, 0]);
}

function buildDukeHead(head, R, add, toy, hairMat, M) {
  add(head, new THREE.SphereGeometry(R * 1.07, 24, 12, 0, Math.PI * 2, 0, Math.PI * 0.55), hairMat, [0, R * 0.05, R * 0.04]);
  for (let i = 0; i < 6; i++) {
    const s = i < 3 ? -1 : 1;
    const k = i % 3;
    add(head, geo.sphere(R * 0.5, 14, 10), hairMat, [s * R * (0.72 + k * 0.08), R * (0.35 - k * 0.3), R * (0.15 + k * 0.2)], [0, s * 0.4, s * (0.5 + k * 0.2)], [1.1, 0.45, 0.85]);
  }
  add(head, geo.sphere(R * 0.55, 14, 10), hairMat, [0, R * 0.2, R * 0.72], null, [1.3, 1.1, 0.7]);
  for (const s of [-1, 1]) {
    add(head, geo.capsule(0.022, 0.1, 4, 8), hairMat, [s * R * 0.93, -R * 0.28, -R * 0.12]);
    add(head, geo.capsule(0.032, 0.13, 4, 8), toy('#3A2418', { rough: 0.8 }), [s * R * 0.16, -R * 0.36, -R * 0.94], [0, 0, Math.PI / 2 + s * 0.45]);
    add(head, geo.cylinder(R * 0.24, R * 0.24, 0.01, 20), M.glass('#FF7A2E', { opacity: 0.6 }), [s * R * 0.37, R * 0.05, -R * 0.97], [Math.PI / 2, 0, 0], [1, 1, 0.85]);
    add(head, geo.torus(R * 0.24, 0.008, 6, 20), M.toon(PAL.marqueeGold, { metal: 1, rough: 0.2, keepColor: true }), [s * R * 0.37, R * 0.05, -R * 0.975], null, [1, 0.85, 1]);
  }
}
