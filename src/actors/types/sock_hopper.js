// SOCK HOPPER (`sock_hopper`, Hootie's "Sockettes") type module — GDD §8.2, §5.9, §7.5. Owned by the zombies-specials
// agent. Contract: the TYPE MODULE CONTRACT in src/actors/zombieTypes.js (this module keeps it: id, hp, speed, build,
// release, update -> true (moves + attacks itself), updateEntry, onDamage, onDeath/updateDeath, warmup, entry).
//
// Look: the sculpted z_sock (src/art/chars/z_sock.js, custom 5-joint chain root -> s1 -> s2 -> s3 -> head (+ jaw)),
//   baked in assets/baked; ?art=0 or a missing bake -> a small procedural sock on the same joints. Googly pupils
//   jiggle on springs (k 120, d 12), the body squash/stretches, bends into the hop, the jaw flaps.
// Behaviour:
//   - HOPS: one hop per 0.33 s (T.zombies.sock.speed 4.5 m/s, speed15 from round 15 -> ~1.5 m hops): 24 % of the cycle
//     on the floor (landing squash 0.7 -> anticipation crouch), the rest in the air (stretch 1.3). When music plays
//     (audio music.beat()), the hop period snaps to the closest eighth/quarter note and the phase locks to the beat, so
//     every sock lands on the beat (quarter-note hoppers alternate by id). Without music, socks within 2.2 m phase-lock
//     to their neighbour: packs hop in unison. Packs also keep together (cohesion) until close to the player.
//   - LEAP-BITE (T.zombies.sock: leap 2.5 m, dmg 25, cd 0.9): 0.3 s crouch-squash telegraph (tremble, jaw clamps,
//     eyes widen, giggle), then a 0.36 s leap at the spot where the player stood at launch (0.45 m arc: sidestep it or
//     jump over it). A bite chomps, knocks back and bounces the sock off you.
//   - Close but cooling down: hops around you instead of stacking into you.
//   - Entry: always squeezes UNDER boards (1.0 s, no tearing; GDD §5.9 in Hullabaloo Hour, and a 0.7 m sock fits
//     under boards any time). Screen spawns: the manager's taffy emerge.
//   - Weak point: the eyes (hit zone 'eyes' = the top 40 % of the body). It is flagged head:true (gold hitmarker,
//     headshot kill points), and onDamage normalises the weapon's own head multiplier so the eyes deal exactly ×2.
//   - Tiny Tele lure: returns false and lets the manager walk it over (the animator hops, then it sits and sways).
// Death (onDeath -> 2.3 s): puffs up, "pfffft" (sock_deflate), zig-zags through the air like a let-go balloon
//   (shrinking, air jets), flops flat on the floor, a single button clinks away, then a small static puff.
// Sounds: sock_boing (takeoff, nearest socks only, global limiter), sock_giggle (random, spotted, telegraph, after a
//   bite), sock_leap, sock_deflate. Events: zombie:attack {z, dmg} on a bite (the manager emits the others).
// Debug: z.def.debugBite(game, z) forces a leap now.

import * as THREE from 'three';
import { T, LAYERS } from '../../core/config.js';
import { Spring } from '../../core/rig.js';
import * as geo from '../../core/geo.js';
import { skinRig } from '../../core/geo.js';
import * as charRuntime from '../../art/charRuntime.js';
import BAKED from '../../../assets/baked/registry.js';
import sockDef from '../../art/chars/z_sock.js';

const S = T.zombies.sock;
const R = T.rounds;
const G = 22;                 // m/s² (same as the manager)
const C = 0.24;               // floor fraction of the hop cycle
const BASE_P = 0.33;          // s per hop (GDD)
const CROUCH = 0.3;           // leap telegraph
const LEAP_T = 0.36;          // leap flight
const LEAP_H = 0.45;          // leap arc
const HEAR = 15;
const DEATH = 2.3;

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _d = new THREE.Vector3();
const _v = new THREE.Vector3();

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (x) => { x = clamp01(x); return x * x * (3 - 2 * x); };
const lerp = (a, b, t) => a + (b - a) * t;
const easeOutBack = (x) => { x = clamp01(x); const c = 1.7; return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2; };
const easeOutCubic = (x) => 1 - (1 - clamp01(x)) ** 3;
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const yawTo = (dx, dz) => Math.atan2(-dx, -dz);
const wrapHalf = (x) => x - Math.round(x);
const hpAt = (r) => (r <= 9 ? R.hpEarlyBase + R.hpEarlyStep * (Math.max(1, r) - 1)
  : Math.min(R.hpCap, Math.round((R.hpEarlyBase + R.hpEarlyStep * 8) * R.hpMul ** (r - 9))));

// ------------------------------------------------------------------------------------------------ shared helpers
// Music beat ({ bpm, beat }) while a real music state plays, cached per frame.
let beatFrame = -1, beatVal = null;
function musicBeat(g) {
  if (beatFrame === g.time.frame) return beatVal;
  beatFrame = g.time.frame;
  beatVal = null;
  try {
    const m = g.audio && (g.audio.musicBeat ? { beat: () => g.audio.musicBeat(), state: 'x' } : g.audio._music);
    const st = m && m.state;
    if (m && typeof m.beat === 'function' && st && st !== 'ambient' && st !== 'silence' && st !== 'title') {
      const b = m.beat();
      if (b && b.bpm > 0 && Number.isFinite(b.beat)) beatVal = b;
    }
  } catch (err) { beatVal = null; }
  return beatVal;
}

// Global sound limiter (the audio engine has a voice budget; a pack of 10 socks would boing 30 times a second).
const budget = { boing: 0, t: 0, giggle: 0 };
function refill(g) {
  const now = g.time.now;
  if (now - budget.t > 0.11) { budget.t = now; budget.boing = Math.min(2, budget.boing + 1); budget.giggle = Math.min(1, budget.giggle + 0.05); }
}

// The weapon's own head multiplier (weapons pre-multiply it into the amount for head hits).
function weaponHeadMul(g, weaponId) {
  if (!weaponId) return 1;
  const w = g.weapons;
  const d = (w && w.defs && w.defs[weaponId]) || (w && typeof w.def === 'function' ? w.def(weaponId) : null);
  const h = d && Number(d.head);
  return h > 0 ? h : 1;
}

function losTo(g, z, p) {
  _a.set(z.pos.x, z.pos.y + 0.5, z.pos.z);
  _b.set(p.pos.x, p.pos.y + 1.0, p.pos.z);
  try { return g.level.col.lineOfSight(_a, _b); } catch (err) { return true; }
}

// ------------------------------------------------------------------------------------------------ model
const pool = [];
let buttonGeo = null, buttonMats = null;
const buttons = [];            // flying buttons { mesh, vel, spin, t, floor, bounces }
let bakedWarned = false;

function hasBaked(game) {
  return !(game.params && game.params.art === 0) && !!BAKED.z_sock && typeof charRuntime.buildCharacter === 'function';
}

function buildBakedModel(game) {
  const M = game.mats;
  const c = charRuntime.buildCharacter(sockDef, { envMap: M.envMap, globals: M.uniforms, layer: LAYERS.ZOMBIES, animator: false });
  const J = c.rig.joints;
  const eyes = {};
  c.group.traverse((o) => {
    if (o.userData && o.userData.googlyPupil && !o.isMesh) { o.userData.noMerge = true; eyes[o.userData.googlyPupil] = { pivot: o, base: o.position.clone() }; }
    if (o.isMesh) o.castShadow = !!o.isSkinnedMesh;
  });
  const whites = [];
  c.group.traverse((o) => { if (o.name && o.name.startsWith('googly') && !o.isMesh && !o.userData.googlyPupil) whites.push(o); });
  // The pupil pivots join the skeleton as extra bones: both pupils merge into one skinned mesh (bound to the body's
  // skeleton: one skeleton per sock), the domes / rims into plain head meshes; one draw per material, and the
  // pivots still move on their springs. charOpt.merge off: the older geo.skinRig (own skeleton, A/B).
  const extra = {};
  for (const [side, e] of Object.entries(eyes)) extra['pupil' + side] = e.pivot;
  try {
    if (charRuntime.charOpt && charRuntime.charOpt.merge) charRuntime.mergeAttachments(c, { bones: Object.values(extra) });
    else skinRig({ root: c.rig.root, joints: { ...c.rig.joints, ...extra }, dims: c.rig.dims });
  } catch (err) { if (!bakedWarned) { bakedWarned = true; console.warn('[sock_hopper] attachment merge failed', err); } }
  const bodies = [];
  c.group.traverse((o) => { if (o.isSkinnedMesh) { if (o === c.skinnedMesh) bodies.push(o); else o.castShadow = false; } });
  if (c.skinnedMesh) registerSpecialTint(game, c.skinnedMesh.material);
  return finishModel(game, c.group, c.rig, J, eyes, whites, bodies, true);
}

// Procedural stand-in on the same joints (art=0 / no bake): a striped tube, a head, googly eyes.
function buildPlaceholderModel(game) {
  const M = game.mats;
  const root = new THREE.Group();
  root.name = 'rig';
  const mk = (name, parent, y) => { const o = new THREE.Object3D(); o.name = name; o.position.set(0, y, 0); parent.add(o); return o; };
  const J = {};
  J.root = mk('root', root, 0); J.s1 = mk('s1', J.root, 0.13); J.s2 = mk('s2', J.s1, 0.13); J.s3 = mk('s3', J.s2, 0.13);
  J.head = mk('head', J.s3, 0.14); J.jaw = mk('jaw', J.head, -0.012);
  const toy = (c, o = {}) => M.toon(c, { rough: 0.8, rim: 0.4, rimColor: '#8FF3FF', keepColor: true, ...o });
  const cols = ['#EDE0C4', '#E0392F', '#F7C630', '#2F63D8'];
  [J.root, J.s1, J.s2, J.s3].forEach((j, i) => j.add(geo.mesh(geo.cylinder(0.1, 0.105, 0.135, 16), toy(cols[i]), { pos: [0, 0.065, 0] })));
  J.head.add(geo.mesh(geo.sphere(0.14, 18, 12), toy('#EDE0C4'), { pos: [0, 0.07, -0.1], scale: [1, 0.72, 1.15] }));
  J.jaw.add(geo.mesh(geo.sphere(0.12, 16, 10), toy('#E0392F'), { pos: [0, -0.02, -0.11], scale: [1, 0.4, 1.2] }));
  const eyes = {};
  const whites = [];
  for (const s of [1, -1]) {
    const side = s > 0 ? 'L' : 'R';
    const g = new THREE.Group();
    g.name = 'googly' + side;
    g.position.set(-s * 0.064, 0.158, -0.118);
    g.rotation.set(0.42, -s * 0.16, 0);
    J.head.add(g);
    g.add(geo.mesh(geo.sphere(0.06, 16, 10), toy('#F4F4F0', { rough: 0.2 }), { scale: [1, 1, 0.6], cast: false }));
    const pv = new THREE.Group();
    pv.position.set(0, -0.007, -0.034);
    g.add(pv);
    pv.add(geo.mesh(geo.sphere(0.033, 12, 8), toy('#050305', { rough: 0.3 }), { scale: [1, 1, 0.35], cast: false }));
    eyes[side] = { pivot: pv, base: pv.position.clone() };
    whites.push(g);
  }
  const group = new THREE.Group();
  group.add(root);
  const rig = { root, joints: J, dims: { height: 0.72, headH: 0.2 } };
  const bodies = [];
  root.traverse((o) => { if (o.isMesh && o.castShadow) bodies.push(o); });
  return finishModel(game, group, rig, J, eyes, whites, bodies, false);
}

function finishModel(game, group, rig, J, eyes, whites, bodies, baked) {
  const head = new THREE.Object3D();
  head.name = 'part:headCenter';
  head.position.set(0, 0.06, -0.07);
  J.head.add(head);
  group.name = 'zombie:sock_hopper';
  game.render.setLayerRecursive(group, LAYERS.ZOMBIES);
  return { group, rig, J, eyes, whites, bodies, head, headR: 0.17, baked, cards: [], def: { id: 'sock_hopper' }, variant: baked ? 'z_sock' : 'placeholder' };
}

function acquire(game) {
  const want = hasBaked(game);
  // pooled models built under another charOpt.gen (A/B tools toggled a build-time flag) are dropped
  for (let i = pool.length - 1; i >= 0; i--) if ((pool[i].gen || 0) !== (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0)) pool.splice(i, 1);
  for (let i = pool.length - 1; i >= 0; i--) if (pool[i].baked === want) return pool.splice(i, 1)[0];
  if (want) {
    try { const m = buildBakedModel(game); m.gen = (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0); return m; } catch (err) {
      if (!bakedWarned) { bakedWarned = true; console.warn('[sock_hopper] baked sock failed, using the placeholder', err); }
    }
  }
  const m = buildPlaceholderModel(game);
  m.gen = (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0);
  return m;
}

function resetPose(m) {
  const g = m.group;
  g.visible = true;
  g.position.set(0, 0, 0);
  g.rotation.set(0, 0, 0);
  g.scale.set(1, 1, 1);
  m.rig.root.position.set(0, 0, 0);
  m.rig.root.rotation.set(0, 0, 0);
  m.rig.root.scale.set(1, 1, 1);
  for (const j of Object.values(m.J)) { j.rotation.set(0, 0, 0); j.scale.set(1, 1, 1); }
  for (const e of Object.values(m.eyes)) { e.pivot.position.copy(e.base); e.pivot.rotation.set(0, 0, 0); e.pivot.scale.set(1, 1, 1); }
  for (const w of m.whites) w.scale.set(1, 1, 1);
}

// ------------------------------------------------------------------------------------------------ buttons (death)
function buttonAssets(game) {
  if (buttonGeo) return;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const x = c.getContext('2d');
  x.fillStyle = '#E8A92E'; x.fillRect(0, 0, 64, 64);
  x.strokeStyle = '#B97A14'; x.lineWidth = 6; x.beginPath(); x.arc(32, 32, 24, 0, Math.PI * 2); x.stroke();
  x.fillStyle = '#6B4A12';
  for (const [dx, dy] of [[-7, -7], [7, -7], [-7, 7], [7, 7]]) { x.beginPath(); x.arc(32 + dx, 32 + dy, 4, 0, Math.PI * 2); x.fill(); }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const side = game.mats.toon('#D99A22', { rough: 0.35, keepColor: true, rim: 0.4 });
  const cap = game.mats.toon('#ffffff', { rough: 0.35, keepColor: true, map: tex, rim: 0.3, name: 'sockButtonCap' });
  buttonGeo = new THREE.CylinderGeometry(0.03, 0.03, 0.01, 18);
  buttonMats = [side, cap, cap];
}

function popButton(game, pos, dir) {
  buttonAssets(game);
  let b = buttons.find((q) => !q.live);
  if (!b) {
    if (buttons.length >= 6) b = buttons[0];
    else {
      const mesh = new THREE.Mesh(buttonGeo, buttonMats);
      mesh.name = 'sock:button';
      mesh.castShadow = false;
      mesh.layers.set(LAYERS.ZOMBIES);
      b = { mesh, vel: new THREE.Vector3(), spin: new THREE.Vector3() };
      buttons.push(b);
    }
  }
  b.live = true; b.t = 0; b.bounces = 0;
  b.mesh.position.copy(pos);
  b.mesh.scale.setScalar(1);
  b.vel.set(dir.x * 1.6 + (Math.random() - 0.5) * 0.8, 2.6 + Math.random(), dir.z * 1.6 + (Math.random() - 0.5) * 0.8);
  b.spin.set(8 + Math.random() * 8, Math.random() * 4, 6 + Math.random() * 6);
  const fy = game.level.col.floorAt(pos.x, pos.z, pos.y + 0.3);
  b.floor = (fy > -Infinity ? fy : pos.y) + 0.005;
  game.scene.add(b.mesh);
}

// PLEASE STAND BY look for the specials' own materials (zombieTypes' setZombieTint only knows the materials it built):
// the same test-card grey (colour ×0.5 + a lilac emissive lift) while zombies are frozen by the power-up. Shared by the
// three special modules (forecaster.js / big_shot.js import it).
const tintMats = new Set();
const tintGames = new WeakSet();
let tintOn = false;
export function registerSpecialTint(game, mat) {
  if (!mat || !mat.color || tintMats.has(mat)) return;
  tintMats.add(mat);
  mat.userData.zsBase = { color: mat.color.clone(), emissive: mat.emissive ? mat.emissive.clone() : null };
  if (tintOn) applySpecialTint(mat, true);
  if (tintGames.has(game)) return;
  tintGames.add(game);
  try {
    game.render.addPrePass(() => {
      const pu = game.powerups, Zs = game.zombies;
      const on = !!(Zs && Zs.frozen && pu && (typeof pu.isActive === 'function' ? pu.isActive('please_stand_by') : pu.active && pu.active.please_stand_by > 0));
      if (on === tintOn) return;
      tintOn = on;
      for (const m of tintMats) applySpecialTint(m, on);
    });
  } catch (err) { /* optional */ }
}
function applySpecialTint(mat, on) {
  const b = mat.userData.zsBase;
  if (!b) return;
  mat.color.copy(b.color);
  if (mat.emissive && b.emissive) mat.emissive.copy(b.emissive);
  if (on) { mat.color.multiplyScalar(0.5); if (mat.emissive) mat.emissive.setRGB(0.2, 0.2, 0.25); }
}

// Buttons outlive their sock: one per-game ticker (render pre-pass, world dt) moves them; cleared on a new game.
const tickers = new WeakSet();
function ensureTicker(game) {
  if (tickers.has(game)) return;
  tickers.add(game);
  try {
    game.render.addPrePass(() => { try { updateButtons(game, game.time.dt || 0); } catch (err) { /* keep rendering */ } });
    game.events.on('game:start', () => { for (const b of buttons) { b.live = false; b.mesh.removeFromParent(); } });
  } catch (err) { /* optional */ }
}

function updateButtons(game, dt) {
  if (!(dt > 0)) return;
  for (const b of buttons) {
    if (!b.live) continue;
    b.t += dt;
    const m = b.mesh;
    if (b.bounces < 3) {
      b.vel.y -= G * dt;
      m.position.addScaledVector(b.vel, dt);
      m.rotation.x += b.spin.x * dt; m.rotation.y += b.spin.y * dt; m.rotation.z += b.spin.z * dt;
      if (m.position.y < b.floor && b.vel.y < 0) {
        m.position.y = b.floor;
        b.bounces++;
        b.vel.y *= -0.42; b.vel.x *= 0.6; b.vel.z *= 0.6;
        b.spin.multiplyScalar(0.5);
        game.audio.play('grenade_bounce', { pos: m.position, rate: 1.9 + b.bounces * 0.25, vol: 0.45 / b.bounces });
        if (b.bounces >= 3) { m.rotation.set(0, m.rotation.y, 0); m.position.y = b.floor + 0.005; }
      }
    }
    if (b.t > 3.2) {
      m.scale.setScalar(Math.max(0.001, 1 - (b.t - 3.2) / 0.3));
      if (b.t > 3.5) { b.live = false; m.removeFromParent(); }
    }
  }
}

// ------------------------------------------------------------------------------------------------ animator
// The manager calls animator.update(dt, z.anim) every (LOD) frame and animator.kick(amount) on hits. The pose reads
// the hop state the behaviour keeps in z.flags; when the behaviour does not run (approach, stun, lure), it advances
// a hop cycle from z.anim.speed itself.
function makeAnimator(z) {
  const f = z.flags;
  return {
    update(dt, st = {}) { poseSock(z, f, dt, st); },
    kick(amount = 1) {
      f.sq.kick(-3.2 * amount);
      f.bend.kick(3 * amount);
      for (const e of f.eyeS) { e.y.kick(-7 * amount); e.x.kick((Math.random() - 0.5) * 9 * amount); }
    },
  };
}

function poseSock(z, f, dt, st) {
  const m = z.model;
  if (!m) return;
  const J = m.J, root = m.rig.root;
  f.t += dt;
  let u = f.ph, arc = 0, sy = 1, lean = 0, jaw = 0.06, inAir = false;
  const speed = st.speed || 0;
  if (!f.driven) {
    // Not driven by update(): hop from the manager's movement speed (approach, lure, emerge...) or idle bounce.
    if (speed > 0.3) { f.ph = (f.ph + dt / BASE_P) % 1; u = f.ph; } else u = -1;
  }
  f.driven = false;
  const H = f.H || 0.26;
  if (f.mode === 'crouch') {
    const k = clamp01(f.mt / CROUCH);
    sy = lerp(0.9, 0.58, easeOutCubic(k));
    lean = 0.28 * k;
    jaw = 0.0;
    root.position.x = Math.sin(f.t * 70) * 0.012 * k;
  } else if (f.mode === 'leap') {
    const k = clamp01(f.mt / LEAP_T);
    arc = f.leapArc;
    sy = k < 0.15 ? lerp(0.6, 1.38, easeOutCubic(k / 0.15)) : lerp(1.38, 1.12, (k - 0.15) / 0.85);
    lean = -0.42;
    jaw = f.bit ? Math.max(0, 0.9 - f.bitT * 9) : 0.95;
    inAir = true;
  } else if (f.mode === 'recover') {
    const k = clamp01(f.mt / 0.26);
    sy = lerp(0.62, 1, easeOutBack(k));
    lean = 0.1 * (1 - k);
    jaw = 0.1;
  } else if (u >= 0) {
    if (u < C) {
      const k = u / C;
      sy = k < 0.45 ? lerp(0.7, 1.03, easeOutBack(k / 0.45)) : lerp(1.03, 0.86, smooth((k - 0.45) / 0.55));
      lean = 0.08 * (1 - k);
    } else {
      const s = (u - C) / (1 - C);
      arc = H * 4 * s * (1 - s);
      sy = s < 0.12 ? lerp(0.86, 1.3, easeOutCubic(s / 0.12)) : s < 0.55 ? lerp(1.3, 1.04, smooth((s - 0.12) / 0.43)) : lerp(1.04, 1.16, ((s - 0.55) / 0.45) ** 2);
      lean = -0.13 * Math.min(1, speed / 3 + 0.4);
      jaw = 0.06 + 0.22 * Math.sin(s * Math.PI);
      inAir = true;
    }
  } else {
    // Idle: a slow breathing bob and a curious sway.
    sy = 1 + Math.sin(f.t * 3.1 + z.id) * 0.03;
    jaw = 0.05 + Math.max(0, Math.sin(f.t * 4.3 + z.id)) * 0.1;
  }
  if (st.down) { sy = 0.86 + Math.sin(f.t * 2.4) * 0.03; lean = 0.12; jaw = 0.3; }
  if ((st.climb || 0) > 0) { lean = -0.2 * Math.sin(f.t * 12); jaw = 0.4; }
  // Springs: squash (hits/landings), bend (whip), googly pupils.
  const sq = f.sq.update(dt, 0);
  const bend = f.bend.update(dt, lean);
  sy *= 1 + sq;
  sy = Math.max(0.4, sy);
  const sx = 1 / Math.sqrt(sy);
  if (f.mode !== 'crouch') root.position.x = 0;
  root.position.y = arc;
  root.scale.set(sx, sy, sx);
  const turn = THREE.MathUtils.clamp(st.turn || 0, -6, 6);
  const hurt = st.hurt || 0;
  const wob = Math.sin(f.t * 5.3 + z.id * 1.7) * 0.05;
  for (const n of ['s1', 's2', 's3']) {
    J[n].rotation.x = bend * 0.34 + hurt * 0.1;
    J[n].rotation.z = -turn * 0.018 + wob * 0.5;
  }
  J.head.rotation.x = -bend * 0.55 + (inAir ? -0.08 : 0.04) - hurt * 0.2;
  J.head.rotation.z = wob + (st.down ? Math.sin(f.t * 2.4) * 0.2 : 0);
  J.jaw.rotation.x = jaw;
  // Googly eyes: gravity pulls the pupils down, flight floats them, turns fling them sideways.
  const k = 0.024;
  let i = 0;
  for (const side of ['L', 'R']) {
    const e = m.eyes[side], s = f.eyeS[i++];
    if (!e) continue;
    const ty = inAir ? 0.25 : -0.55;
    const tx = THREE.MathUtils.clamp(-turn * 0.12, -0.8, 0.8) + (st.down ? Math.cos(f.t * 3 + i) * 0.6 : 0);
    let px = s.x.update(dt, tx), py = s.y.update(dt, st.down ? Math.sin(f.t * 3 + i) * 0.6 : ty);
    const l = Math.hypot(px, py);
    if (l > 1) { px /= l; py /= l; s.x.x = px; s.y.x = py; s.x.v *= -0.4; s.y.v *= -0.4; }
    e.pivot.position.set(e.base.x + px * k, e.base.y + py * k, e.base.z);
    const ps = f.mode === 'crouch' ? 0.7 : 1;
    e.pivot.scale.set(ps, ps, 1);
  }
  const ws = f.mode === 'crouch' ? 1.14 : 1;
  for (const w of m.whites) w.scale.setScalar(ws);
}

// ------------------------------------------------------------------------------------------------ behaviour
function beginLeap(g, z, f) {
  const p = g.player;
  f.mode = 'leap';
  f.mt = 0;
  f.bit = false;
  f.bitT = 0;
  const dx = p.pos.x - z.pos.x, dz = p.pos.z - z.pos.z;
  const d = Math.max(0.3, Math.hypot(dx, dz));
  const dist = Math.min(d + 0.6, S.leap + 0.6);
  f.leapV = new THREE.Vector3((dx / d) * dist / LEAP_T, 0, (dz / d) * dist / LEAP_T);
  z.yaw = yawTo(dx, dz);
  f.leapArc = 0;
  g.audio.play('sock_leap', { pos: z.pos, rate: 0.95 + Math.random() * 0.15 });
  g.audio.play('zmb_swipe', { pos: z.pos, rate: 1.4, vol: 0.6 });
  g.fx.burst(_a.copy(z.pos).setY(z.pos.y + 0.04), { shape: 'puff', count: 3, size: 0.055, speed: 1.6, life: 0.3, colors: ['#EDE6D6', '#D8CDB8'] });
}

function doLeap(g, z, f, dt) {
  const p = g.player, col = g.level.col;
  f.mt += dt;
  const k = clamp01(f.mt / LEAP_T);
  f.leapArc = LEAP_H * 4 * k * (1 - k);
  if (f.bit) f.bitT += dt;
  _d.copy(f.leapV).multiplyScalar(dt);
  z.vy -= G * dt;
  _d.y = z.vy * dt;
  col.moveCircle(z.pos, _d, 0.22, 0.72, 0.45);
  const fy = col.floorAt(z.pos.x, z.pos.z, z.pos.y + 0.3);
  if (fy > -Infinity && z.pos.y <= fy + 0.001) z.vy = 0;
  // Bite: the mouth against the player's body capsule (feet +0.25 .. +1.5).
  if (!f.bit && p.alive) {
    const mouthY = z.pos.y + f.leapArc + 0.55;
    const mx = z.pos.x - Math.sin(z.yaw) * 0.22, mz = z.pos.z - Math.cos(z.yaw) * 0.22;
    const hd = Math.hypot(p.pos.x - mx, p.pos.z - mz);
    const lo = p.pos.y + 0.2, hi = p.pos.y + 1.5;
    const vy = mouthY < lo ? lo - mouthY : mouthY > hi ? mouthY - hi : 0;
    if (Math.hypot(hd, vy) < (p.radius || 0.38) + 0.2) {
      f.bit = true;
      f.bitT = 0;
      if (p.hurt(S.dmg, z.pos)) {
        g.events.emit('zombie:attack', { z, dmg: S.dmg });
        _v.set(p.pos.x - z.pos.x, 0, p.pos.z - z.pos.z).normalize().multiplyScalar(6);
        if (p.knockback) p.knockback(_v);
      }
      g.audio.play('zmb_hit', { pos: z.pos, rate: 1.7, vol: 0.8 });
      f.leapV.multiplyScalar(-0.35);        // bounce off
      f.sq.kick(-2.5);
      if (budget.giggle >= 0.5) { budget.giggle -= 0.5; g.audio.play('sock_giggle', { pos: z.pos, rate: 1.1, delay: 0.25 }); }
    }
  }
  if (f.mt >= LEAP_T) {
    f.mode = 'recover';
    f.mt = 0;
    f.leapArc = 0;
    z.cd = S.cd;
    f.sq.kick(-2);
    g.fx.burst(_a.copy(z.pos).setY(z.pos.y + 0.04), { shape: 'puff', count: 3, size: 0.05, speed: 1.3, life: 0.3, colors: ['#EDE6D6', '#D8CDB8'] });
  }
}

// Hop direction chosen at takeoff: straight at the player when visible, else the flow field; separation, pack
// cohesion, and circling when close but cooling down.
function chooseHop(g, z, f, dist, dx, dz) {
  const nav = g.nav;
  if (f.los && dist < 9) _d.set(dx / dist, 0, dz / dist);
  else {
    nav.dir(z.pos.x, z.pos.z, _d);
    if (_d.lengthSq() < 1e-6) _d.set(dx / Math.max(1e-3, dist), 0, dz / Math.max(1e-3, dist));
  }
  if (dist < 1.7 && z.cd > 0) {
    const side = f.side;
    _d.set(-dz / dist * side - dx / dist * 0.35, 0, dx / dist * side - dz / dist * 0.35);
  }
  // Pack cohesion (far from the player): steer a little toward nearby socks.
  if (dist > 5) {
    let cx = 0, cz = 0, n = 0;
    for (const o of g.zombies.alive) {
      if (o === z || o.type !== 'sock_hopper') continue;
      const ox = o.pos.x - z.pos.x, oz = o.pos.z - z.pos.z;
      const d2 = ox * ox + oz * oz;
      if (d2 > 0.8 && d2 < 12) { cx += ox; cz += oz; n++; }
    }
    if (n) { const l = Math.hypot(cx, cz) || 1; _d.x += (cx / l) * 0.25; _d.z += (cz / l) * 0.25; }
  }
  _d.x += (z.sepX || 0) * 0.9;
  _d.z += (z.sepZ || 0) * 0.9;
  const l = Math.hypot(_d.x, _d.z) || 1;
  _d.x /= l; _d.z /= l;
  // Hop length: average speed = z.speed; do not land on the player's toes when a bite is not ready.
  let L = z.speed * f.P;
  if (dist < 1.7 + L && z.cd <= 0) L = Math.max(0.35, Math.min(L, dist - 1.4));
  f.H = THREE.MathUtils.clamp(0.12 + 0.12 * L, 0.15, 0.34);
  const air = f.P * (1 - C);
  f.vx = _d.x * L / air;
  f.vz = _d.z * L / air;
  f.face = yawTo(_d.x, _d.z);
}

function hopPeriod(g, z, f) {
  const b = musicBeat(g);
  if (b) {
    const beatDur = 60 / b.bpm;
    const perBeat = Math.abs(Math.log(beatDur / 2 / BASE_P)) < Math.abs(Math.log(beatDur / BASE_P)) ? 2 : 1;
    const off = perBeat === 1 && z.id % 2 ? 0.5 : 0;
    return { P: beatDur / perBeat, target: ((b.beat * perBeat + off) % 1 + 1) % 1, beat: true };
  }
  // No music: phase-lock to the nearest sock within 2.2 m that spawned earlier (packs hop in unison).
  let best = null, bd = 2.2 * 2.2;
  for (const o of g.zombies.alive) {
    if (o === z || o.type !== 'sock_hopper' || o.id > z.id || !o.flags || o.flags.ph === undefined) continue;
    const ox = o.pos.x - z.pos.x, oz = o.pos.z - z.pos.z;
    const d2 = ox * ox + oz * oz;
    if (d2 < bd) { bd = d2; best = o; }
  }
  return { P: f.freeP, target: best ? best.flags.ph : null };
}

function updateSock(g, z, dt) {
  const f = z.flags, p = g.player, col = g.level.col, Zs = g.zombies;
  refill(g);
  z.gawkT = 0;
  if (Zs.lure && z.lured) { f.mode = 'hop'; return false; }       // Tiny Tele: the manager walks it over and sits it down
  f.driven = true;
  const dx = p.pos.x - z.pos.x, dz = p.pos.z - z.pos.z;
  const dist = Math.max(1e-3, Math.hypot(dx, dz));
  const dy = p.pos.y - z.pos.y;
  f.losT -= dt;
  if (f.losT <= 0) { f.losT = 0.25; f.los = dist < 16 ? losTo(g, z, p) : false; }
  // Flavour: giggles.
  f.giggleT -= dt;
  if (!f.spotted && f.los && dist < 12) {
    f.spotted = true;
    if (budget.giggle >= 0.5) { budget.giggle -= 0.5; g.audio.play('sock_giggle', { pos: z.pos, rate: 0.95 + Math.random() * 0.25 }); }
  } else if (f.giggleT <= 0) {
    f.giggleT = 3 + Math.random() * 5;
    if (dist < HEAR && budget.giggle >= 1) { budget.giggle -= 1; g.audio.play('sock_giggle', { pos: z.pos, rate: 0.9 + Math.random() * 0.35, vol: 0.7 }); }
  }

  if (f.mode === 'crouch') {
    f.mt += dt;
    const want = yawTo(dx, dz);
    z.yaw += angDiff(want, z.yaw) * Math.min(1, dt * 16);
    stickToFloor(g, z, dt);
    if (f.mt >= CROUCH) beginLeap(g, z, f);
    return true;
  }
  if (f.mode === 'leap') { doLeap(g, z, f, dt); return true; }
  if (f.mode === 'recover') {
    f.mt += dt;
    stickToFloor(g, z, dt);
    if (f.mt >= 0.26) { f.mode = 'hop'; f.ph = C * 0.5; }
    return true;
  }

  // Hop cycle (phase-locked to the beat or the pack).
  const hp = hopPeriod(g, z, f);
  f.P = hp.P;
  const prev = f.ph;
  if (hp.beat) {
    // Music: the phase IS the beat grid (audio clock), so the lock holds even when game time lags real time;
    // switching into it blends the old phase away over ~0.25 s.
    if (!f.beatLock) { f.beatLock = true; f.beatOff = wrapHalf(f.ph - hp.target); }
    f.beatOff *= Math.exp(-dt * 4);
    f.ph = hp.target + f.beatOff;
  } else {
    f.beatLock = false;
    f.ph += dt / f.P;
    if (hp.target != null) f.ph += wrapHalf(hp.target - f.ph) * Math.min(1, dt * 3.5);
  }
  f.ph = ((f.ph % 1) + 1) % 1;
  const landed = prev > 0.75 && f.ph < 0.25;
  const tookOff = prev < C && f.ph >= C && prev > C * 0.25;
  if (landed) {
    f.sq.kick(-1.2);
    for (const e of f.eyeS) e.y.kick(-5);
    f.vx = 0; f.vz = 0;
  }
  const onFloor = f.ph < C;
  // Leap-bite: from the floor, in range, visible, cooled down.
  if (onFloor && p.alive && z.cd <= 0 && z.spawnT <= 0 && dist <= S.leap && Math.abs(dy) < 1.0 && f.los) {
    f.mode = 'crouch';
    f.mt = 0;
    f.vx = 0; f.vz = 0;
    f.side = Math.random() < 0.5 ? -1 : 1;
    if (budget.giggle >= 0.4) { budget.giggle -= 0.4; g.audio.play('sock_giggle', { pos: z.pos, rate: 1.25, vol: 0.8 }); }
    stickToFloor(g, z, dt);
    return true;
  }
  if (tookOff) {
    chooseHop(g, z, f, dist, dx, dz);
    if (dist < HEAR && budget.boing >= 1) { budget.boing--; g.audio.play('sock_boing', { pos: z.pos, rate: f.pitch, vol: 0.5 }); }
  }
  if (onFloor) {
    const want = f.face ?? yawTo(dx, dz);
    z.yaw += angDiff(dist < 3 ? yawTo(dx, dz) : want, z.yaw) * Math.min(1, dt * 12);
    z.anim.turn = 0;
    stickToFloor(g, z, dt);
    z.anim.speed = 0;
  } else {
    const prevYaw = z.yaw;
    z.yaw += angDiff(f.face ?? z.yaw, z.yaw) * Math.min(1, dt * 8);
    z.anim.turn = (z.yaw - prevYaw) / Math.max(dt, 1e-4);
    z.vy -= G * dt;
    _d.set(f.vx * dt, z.vy * dt, f.vz * dt);
    const r = col.moveCircle(z.pos, _d, 0.22, 0.72, 0.45);
    if (r.onGround) z.vy = 0;
    if (r.hitWall) { f.vx *= 0.5; f.vz *= 0.5; }
    z.anim.speed = Math.hypot(f.vx, f.vz);
  }
  // Anti-stuck bookkeeping is the manager's (nav distance); circling close to the player counts as progress there.
  return true;
}

function stickToFloor(g, z, dt) {
  z.vy -= G * dt;
  _d.set(0, z.vy * dt, 0);
  const r = g.level.col.moveCircle(z.pos, _d, 0.22, 0.72, 0.45);
  if (r.onGround) z.vy = 0;
}

// ------------------------------------------------------------------------------------------------ death
function startDeath(g, z) {
  const f = z.flags;
  const d = f.death = {
    vel: new THREE.Vector3((Math.random() - 0.5) * 2, 5.2, (Math.random() - 0.5) * 2),
    heading: Math.random() * Math.PI * 2, zigT: 0.1, spin: 16 * (Math.random() < 0.5 ? -1 : 1), roll: 0,
    phase: 'fly', flopT: 0, jetT: 0, button: false, yaw: z.yaw, floor: z.pos.y, pitch: 0,
  };
  const fy = g.level.col.floorAt(z.pos.x, z.pos.z, z.pos.y + 0.3);
  d.floor = fy > -Infinity ? fy : z.pos.y;
  g.audio.play('sock_deflate', { pos: z.pos, rate: 0.95 + Math.random() * 0.15 });
  g.fx.burst(_a.copy(z.pos).setY(z.pos.y + 0.5), { shape: 'confetti', count: 8, speed: 3, colors: ['#E0392F', '#F7C630', '#2F63D8', '#EDE0C4'] });
}

function updateDeath(g, z, dt, t) {
  const f = z.flags, d = f.death, m = z.model;
  if (!d || !m) return;
  const G0 = z.group, root = m.rig.root, J = m.J, col = g.level.col;
  let s = 1, sy = 1, sx = 1;
  if (d.phase === 'fly') {
    // 0-0.12 s: puff up; then zig-zag like a let-go balloon, shrinking, jets from the cuff.
    const inflate = t < 0.12 ? easeOutBack(t / 0.12) : 1;
    s = t < 0.12 ? 1 + 0.25 * inflate : lerp(1.25, 0.55, clamp01((t - 0.12) / 0.95));
    if (t >= 0.12) {
      d.zigT -= dt;
      if (d.zigT <= 0) {
        d.zigT = 0.1 + Math.random() * 0.07;
        d.heading += (Math.random() < 0.5 ? -1 : 1) * (1.0 + Math.random() * 1.1);
        const up = t < 0.75 ? 2.6 + Math.random() * 2.2 : -1.5 - Math.random();
        const sp = 3.6 + Math.random() * 1.6;
        d.vel.set(Math.cos(d.heading) * sp, up, Math.sin(d.heading) * sp);
        if (Math.random() < 0.6) g.audio.play('sock_boing', { pos: z.pos, rate: 1.6 + Math.random() * 0.5, vol: 0.25 });
      }
      d.jetT -= dt;
      if (d.jetT <= 0) {
        d.jetT = 0.05;
        _a.copy(z.pos).addScaledVector(d.vel, -0.05);
        _a.y += 0.12;
        g.fx.burst(_a, { shape: 'puff', count: 1, size: 0.045, speed: 0.6, life: 0.3, colors: ['#F4F1E8', '#E6DCCB'] });
      }
    }
    if (t > 0.9) d.vel.y -= G * 0.8 * dt;
    if (z.pos.y > d.floor + 2.8 && d.vel.y > 0) d.vel.y = 0;
    // moveCircle with the vertical step too (a zero delta.y would snap it back onto the floor).
    _d.set(d.vel.x * dt, d.vel.y * dt, d.vel.z * dt);
    const r = col.moveCircle(z.pos, _d, 0.15, 0.3, 0.05);
    if (r.hitWall) { d.heading += Math.PI; d.vel.x *= -1; d.vel.z *= -1; }
    if (r.hitCeiling && d.vel.y > 0) d.vel.y = -0.5;
    if (r.groundY > -Infinity) d.floor = r.groundY;
    d.yaw += d.spin * dt * (t < 0.9 ? 1 : 0.4);
    d.roll = Math.sin(t * 17) * 0.7;
    d.pitch = Math.sin(t * 11) * 0.6;
    if (t > 0.5 && r.onGround && d.vel.y <= 0) {
      z.pos.y = d.floor;
      d.phase = 'flop';
      d.flopT = 0;
      g.audio.play('zmb_hit', { pos: z.pos, rate: 0.55, vol: 0.45 });
      g.fx.burst(_a.copy(z.pos).setY(d.floor + 0.05), { shape: 'puff', count: 4, size: 0.06, speed: 1.5, life: 0.35, colors: ['#EDE6D6', '#D8CDB8'] });
    }
    root.position.set(0, 0, 0);
    root.scale.set(s, s, s);
    G0.rotation.set(d.pitch, d.yaw, d.roll, 'YXZ');
    for (const n of ['s1', 's2', 's3']) { J[n].rotation.x = Math.sin(t * 20 + n.length) * 0.25; J[n].rotation.z = Math.cos(t * 17 + n.length) * 0.2; }
    J.jaw.rotation.x = 0.6;
    for (const side of ['L', 'R']) { const e = m.eyes[side]; if (e) { const a = t * 30 * (side === 'L' ? 1 : -1); e.pivot.position.set(e.base.x + Math.cos(a) * 0.02, e.base.y + Math.sin(a) * 0.02, e.base.z); } }
  } else {
    // Flat on the floor like a deflated sock (lying along its length), a little bounce, then static.
    d.flopT += dt;
    const k = d.flopT;
    const bounce = k < 0.25 ? Math.sin((k / 0.25) * Math.PI) * 0.06 * (1 - k / 0.25) : 0;
    const flat = k < 0.12 ? lerp(0.8, 0.28, easeOutCubic(k / 0.12)) : 0.28;
    s = 0.62;
    sx = s * (k < 0.12 ? 1.1 : 1.22);
    sy = s * 1.05;
    root.position.set(0, 0, 0);
    root.scale.set(sx, sy, s * flat);
    G0.rotation.set(Math.PI / 2 - 0.05, d.yaw, 0, 'YXZ');   // on its back: googly eyes up
    z.pos.y = d.floor + 0.02 + bounce;
    for (const n of ['s1', 's2', 's3']) { J[n].rotation.x = 0; J[n].rotation.z = 0.12; }
    J.jaw.rotation.x = 0.35;
    if (!d.button && k > 0.05) {
      d.button = true;
      _a.copy(z.pos).setY(d.floor + 0.08);
      popButton(g, _a, _b.set(Math.sin(d.yaw), 0, Math.cos(d.yaw)));
    }
    if (k > 0.85 && !d.dissolved) {
      d.dissolved = true;
      g.fx.burst(_a.copy(z.pos).setY(d.floor + 0.1), { shape: 'static', count: 14, speed: 1.6, size: 0.08, life: 0.7 });
      g.audio.play('zmb_death_static', { pos: z.pos, vol: 0.5 });
    }
    if (k > 0.85) {
      const q = 1 - smooth((k - 0.85) / 0.15);
      root.scale.multiplyScalar(Math.max(0.001, q));
    }
  }
  G0.position.copy(z.pos);
  const zs = z.scale || 1;
  G0.scale.set(zs, zs, zs);
}

// ------------------------------------------------------------------------------------------------ module
export default {
  id: 'sock_hopper',
  height: 0.75,
  radius: 0.26,
  dmg: S.dmg,
  range: 1.0,
  windup: CROUCH,
  cd: S.cd,
  spawnMode: 'both',

  hp(round) {
    return Math.round(S.hpMix * hpAt(Math.max(1, round)));
  },

  speed(round) {
    return round >= 15 ? S.speed15 : S.speed;
  },

  // A 0.7 m sock squeezes under the boards (1.0 s) instead of tearing them.
  entry(game, z, win) {
    if (win && win.type === 'boarded') return { tear: false, time: 1.0, style: 'squeeze' };
    return null;
  },

  build(game, z) {
    const m = acquire(game);
    resetPose(m);
    z.model = m;
    z.group = m.group;
    z.rig = m.rig;
    z.head = m.head;
    z.headR = m.headR;
    z.height = 0.75;
    z.scale = 0.95 + Math.random() * 0.1;
    const J = m.J;
    z.hitZones = [
      { shape: 'sphere', bone: J.head, offset: [0, 0.06, -0.07], r: 0.175, zone: 'eyes', head: true, mul: 1 },
      { shape: 'capsule', bone: J.root, offset: [0, 0.05, 0], bone2: J.s3, offset2: [0, 0.06, 0], r: 0.12, zone: 'torso', head: false, mul: 1 },
    ];
    const f = z.flags;
    f.ph = Math.random();
    f.freeP = BASE_P * (0.95 + Math.random() * 0.1);
    f.P = f.freeP;
    f.pitch = 0.9 + Math.random() * 0.3;
    f.mode = 'hop';
    f.mt = 0;
    f.t = Math.random() * 10;
    f.vx = 0; f.vz = 0; f.H = 0.26;
    f.los = false; f.losT = Math.random() * 0.25;
    f.giggleT = 2 + Math.random() * 5;
    f.side = Math.random() < 0.5 ? -1 : 1;
    f.sq = new Spring(260, 15);
    f.bend = new Spring(120, 12);
    f.eyeS = [0, 1].map(() => ({ x: new Spring(120, 12), y: new Spring(120, 12, -0.55) }));
    f.driven = false;
    z.animator = makeAnimator(z);
    ensureTicker(game);
    if (m.bodies) m.bodies.forEach((b) => { b.castShadow = true; });
    m.cards = [];
  },

  release(game, z) {
    const m = z.model;
    if (!m) return;
    m.group.removeFromParent();
    resetPose(m);
    if ((m.gen || 0) === (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0) && pool.length < 24) pool.push(m);
    z.model = null;
  },

  update(game, z, dt) {
    return updateSock(game, z, dt);
  },

  // Eyes (the top 40 %) deal exactly ×2: weapons pre-multiply their own head multiplier for head:true zones.
  onDamage(game, z, amount, info) {
    if (info && info.zone === 'eyes' && info.head) {
      const hm = info.cause === 'bullet' || !info.cause ? weaponHeadMul(game, info.weaponId) : 1;
      return (amount / hm) * 2;
    }
    return amount;
  },

  onDeath(game, z, info) {
    if (z.entry && z.entry.kind === 'screen' && z.entry.phase === 'tele') return undefined;
    startDeath(game, z);
    return DEATH;
  },

  updateDeath(game, z, dt, t) {
    updateDeath(game, z, dt, t);
  },

  warmup(game) {
    const out = [];
    try {
      if (!pool.length) pool.push(acquire(game));
      out.push(pool[0].group);
      buttonAssets(game);
      out.push(new THREE.Mesh(buttonGeo, buttonMats));
    } catch (err) { console.warn('[sock_hopper] warmup', err); }
    return out;
  },

  debugBite(game, z) {
    if (!z || z.dead) return false;
    z.cd = 0;
    z.flags.mode = 'crouch';
    z.flags.mt = 0;
    return true;
  },
};
