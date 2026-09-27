// THE FORECASTER (`forecaster`, "Stormy Stu" clones) type module — GDD §8.3, §5.9, §13 step 4. Owned by the
// zombies-specials agent. Contract: the TYPE MODULE CONTRACT in src/actors/zombieTypes.js (id, hp, speed, build,
// release, update, updateEntry, onDamage, onDeath/updateDeath, warmup, points, spawnMode 'screen').
//
// Look: the sculpted z_forecaster (humanoid, baked) with a showman strut (Animator style: zombie gait, swinging arms,
//   a lighter wobble) + animator.override poses (pointer twirl, conducting the storm, jab, sob, umbrella dangle).
//   His baked 'cloud' part is detached into the scene: it floats 0.6 m over his head on a spring, flies, locks, strikes.
//   Static-snow eyes (the shared zombie eye material), telescoping pointer ('pointerRod' scales along its length).
// Behaviour (T.zombies.forecaster):
//   - Emerges from screen spawns (fence climbs in the Yard). Keeps 8–14 m from the player, strafing at 2.8 m/s
//     (flips side every 1.5–3 s or when blocked, backs off when closer than 8 m, closes in without line of sight).
//   - LOCAL FORECAST every 6 s, line of sight only: 0.8 s pointer twirl (fc_twirl, sparkles), the cloud flies at 9 m/s
//     to hover 3 m over where the player stood at the cast (below the ceiling), LOCKS: 1.0 s telegraph (it darkens,
//     shakes, drizzles, flickers, fc_rumble, a 1.5 m shadow circle grows on the floor), then a lightning bolt strikes the
//     circle: 40 damage + a 0.5 s static overlay when the player is inside (moving out always dodges it), flash light,
//     scorch, sparks; the cloud flies home at 6 m/s. He points at his cloud the whole time (readable).
//   - Pointer jab (40 dmg, 1.5 m, 0.35 s wind-up) when cornered; zombie:attack {z, dmg}.
//   - THE CLOUD is its own shootable (game.weapons.registerShootable, id 'fc_cloud_<z.id>', HP 50 + 10·round; bullets,
//     melee, grenades within 5 m). Popping it (anywhere, mid-cast too): a mini rainbow + colour confetti (fc_cloud_pop),
//     he SOBS for 3 s (hands on face, tears, fc_sob), then takes ×2 damage for the rest of his life, never casts again
//     and becomes a jogging melee chaser (2.4 m/s; the manager steers, he jabs).
//   - Tiny Tele lure: the manager walks him over (the cloud keeps floating).
// Death (onDeath -> 2.5 s): a polka-dot umbrella pops out of his back (fc_umbrella), snaps open over his head, he floats
//   up 3 m swinging and kicking, then pops into confetti with the harp "ta-da". +100 (points.killBonus).
//   EE (§13): killed with the cloud intact -> emits 'zombie:forecaster_storm' { pos (the cloud), z } and the cloud drifts
//   up and fades (the easter egg may spawn the Stray Storm there).
// Debug: z.def.popCloud(game, z), z.def.castNow(game, z), z.def.cloudOf(z) -> { state, hp, pos }.

import * as THREE from 'three';
import { T, LAYERS } from '../../core/config.js';
import { skinRig } from '../../core/geo.js';
import * as geo from '../../core/geo.js';
import * as charRuntime from '../../art/charRuntime.js';
import BAKED from '../../../assets/baked/registry.js';
import fcDef from '../../art/chars/z_forecaster.js';
import { acquireModel, humanoidHitZones, zombieEyeMaterial } from '../zombieTypes.js';
import { registerSpecialTint } from './sock_hopper.js';

// Clone for warmup samples without deep-copying userData (Object3D.copy JSON-stringifies it; ours hold Object3D refs).
function cloneBare(o) {
  const saved = [];
  o.traverse((x) => { saved.push(x, x.userData); x.userData = {}; });
  try { return o.clone(); } finally { for (let i = 0; i < saved.length; i += 2) saved[i].userData = saved[i + 1]; }
}


const F = T.zombies.forecaster;
const R = T.rounds;
const G = 22;
const TWIRL = 0.8;
const RETURN_SPEED = 6;
const CHASE_SPEED = 2.4;
const JAB = { windup: 0.35, strike: 0.12, recover: 0.4, range: 1.5, dmg: F.strikeDmg, cd: 1.4 };
const DEATH = 2.5;
const FLOAT_H = 3;
const STRAFE_ACCEL = 6;
const SOB_TIME = F.sobStun;
const FC_STYLE = { base: 'zombie', arms: 'swing', arm: 0.34, armRun: 0.22, elbow: 0.28, lean: 0.07, sway: 0.07, wobble: 0.45,
  headLag: 1.2, cycle: 1.05, legSwing: 0.36, knee: 0.4, bob: 0.04 };

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _d = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _up = new THREE.Vector3(0, 1, 0);

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (x) => { x = clamp01(x); return x * x * (3 - 2 * x); };
const lerp = (a, b, t) => a + (b - a) * t;
const easeOutBack = (x) => { x = clamp01(x); const c = 1.7; return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2; };
const easeOutCubic = (x) => 1 - (1 - clamp01(x)) ** 3;
const easeInOut = (x) => { x = clamp01(x); return x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2; };
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const yawTo = (dx, dz) => Math.atan2(-dx, -dz);
const hpAt = (r) => (r <= 9 ? R.hpEarlyBase + R.hpEarlyStep * (Math.max(1, r) - 1)
  : Math.min(R.hpCap, Math.round((R.hpEarlyBase + R.hpEarlyStep * 8) * R.hpMul ** (r - 9))));
const RAINBOW = ['#E4473A', '#F08A24', '#F4E03A', '#52D24A', '#3FA8E0', '#8A5AD6'];

// ------------------------------------------------------------------------------------------------ shared FX assets
let discTex = null, dotsTex = null, rainbowGeo = null, umbrellaParts = null, boltMat = null, glowMat = null;
let serial = 0;
let warned = false;

function discTexture() {
  if (discTex) return discTex;
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  const grd = g.createRadialGradient(128, 128, 10, 128, 128, 124);
  grd.addColorStop(0, 'rgba(30,22,52,0.78)');
  grd.addColorStop(0.72, 'rgba(34,26,62,0.62)');
  grd.addColorStop(0.86, 'rgba(60,44,110,0.5)');
  grd.addColorStop(0.9, 'rgba(210,200,255,0.95)');
  grd.addColorStop(0.95, 'rgba(160,140,255,0.55)');
  grd.addColorStop(1, 'rgba(120,100,220,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, 256, 256);
  // dashed inner ring
  g.strokeStyle = 'rgba(200,190,255,0.55)';
  g.lineWidth = 5;
  g.setLineDash([14, 12]);
  g.beginPath(); g.arc(128, 128, 70, 0, Math.PI * 2); g.stroke();
  discTex = new THREE.CanvasTexture(c);
  discTex.colorSpace = THREE.SRGBColorSpace;
  return discTex;
}

function dotsTexture() {
  if (dotsTex) return dotsTex;
  const c = document.createElement('canvas');
  c.width = 256; c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#E23B3B';
  g.fillRect(0, 0, 256, 128);
  g.fillStyle = '#FFF4DE';
  for (let y = 0; y < 5; y++) for (let x = 0; x < 9; x++) {
    g.beginPath(); g.arc(x * 30 + (y % 2) * 15 + 6, y * 28 + 12, 6.5 - y * 0.6, 0, Math.PI * 2); g.fill();
  }
  // scalloped darker hem band
  g.fillStyle = '#B8262A';
  g.fillRect(0, 118, 256, 10);
  dotsTex = new THREE.CanvasTexture(c);
  dotsTex.colorSpace = THREE.SRGBColorSpace;
  dotsTex.wrapS = THREE.RepeatWrapping;
  dotsTex.repeat.set(2, 1);
  return dotsTex;
}

function rainbowGeometry() {
  if (rainbowGeo) return rainbowGeo;
  const parts = RAINBOW.map((col, i) => {
    const g = new THREE.TorusGeometry(0.62 - i * 0.07, 0.036, 6, 36, Math.PI);
    const c = new THREE.Color(col);
    const n = g.attributes.position.count;
    const arr = new Float32Array(n * 3);
    for (let k = 0; k < n; k++) { arr[k * 3] = c.r; arr[k * 3 + 1] = c.g; arr[k * 3 + 2] = c.b; }
    g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
    return g;
  });
  rainbowGeo = mergeList(parts);
  return rainbowGeo;
}

function mergeList(list) {
  // Tiny local merge (position/normal/uv/color, indexed) to avoid another import path.
  let nv = 0, ni = 0;
  for (const g of list) { nv += g.attributes.position.count; ni += g.index.count; }
  const pos = new Float32Array(nv * 3), nrm = new Float32Array(nv * 3), col = new Float32Array(nv * 3), uv = new Float32Array(nv * 2);
  const idx = new Uint32Array(ni);
  let ov = 0, oi = 0;
  for (const g of list) {
    const n = g.attributes.position.count;
    pos.set(g.attributes.position.array, ov * 3);
    nrm.set(g.attributes.normal.array, ov * 3);
    if (g.attributes.color) col.set(g.attributes.color.array, ov * 3); else col.fill(1, ov * 3, (ov + n) * 3);
    if (g.attributes.uv) uv.set(g.attributes.uv.array, ov * 2);
    const I = g.index.array;
    for (let k = 0; k < I.length; k++) idx[oi + k] = I[k] + ov;
    ov += n; oi += I.length;
    g.dispose();
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  out.setAttribute('color', new THREE.BufferAttribute(col, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  return out;
}

function umbrellaAssets(game) {
  if (umbrellaParts) return umbrellaParts;
  const M = game.mats;
  const prof = [[0.0, 0.34], [0.12, 0.33], [0.25, 0.29], [0.36, 0.22], [0.44, 0.13], [0.5, 0.03], [0.51, 0.0]];
  const canopy = new THREE.LatheGeometry(prof.map(([x, y]) => new THREE.Vector2(x, y)), 16);
  umbrellaParts = {
    canopy,
    canopyMat: M.toon('#ffffff', { map: dotsTexture(), side: THREE.DoubleSide, rough: 0.5, rim: 0.4, keepColor: true, name: 'fcUmbrella' }),
    shaft: new THREE.CylinderGeometry(0.011, 0.011, 0.82, 8),
    hook: new THREE.TorusGeometry(0.05, 0.012, 6, 14, Math.PI),
    tip: new THREE.SphereGeometry(0.022, 10, 8),
    wood: M.toon('#8A5A36', { rough: 0.45, keepColor: true }),
    chrome: M.toon('#D9DDE3', { metal: 1, rough: 0.2, keepColor: true }),
  };
  return umbrellaParts;
}

function buildUmbrella(game) {
  const U = umbrellaAssets(game);
  const g = new THREE.Group();
  g.name = 'fc:umbrella';
  const canopy = new THREE.Group();
  canopy.position.y = 0.42;
  g.add(canopy);
  canopy.add(new THREE.Mesh(U.canopy, U.canopyMat));
  const tip = new THREE.Mesh(U.tip, U.chrome);
  tip.position.y = 0.36;
  canopy.add(tip);
  const shaft = new THREE.Mesh(U.shaft, U.chrome);
  g.add(shaft);
  const hook = new THREE.Mesh(U.hook, U.wood);
  hook.position.set(0.05, -0.41, 0);
  hook.rotation.z = Math.PI;
  g.add(hook);
  g.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.layers.set(LAYERS.ZOMBIES); } });
  g.userData.canopy = canopy;
  return g;
}

// Jagged lightning ribbon (two crossed planes per segment) from a to b.
function boltGeometry(a, b, jitter = 0.28, n = 9, width = 0.07) {
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const p = new THREE.Vector3().lerpVectors(a, b, t);
    if (i > 0 && i < n) { p.x += (Math.random() - 0.5) * jitter * 2; p.z += (Math.random() - 0.5) * jitter * 2; }
    pts.push(p);
  }
  const pos = [], idx = [];
  for (const [ax, az] of [[1, 0], [0, 1]]) {
    const base = pos.length / 3;
    for (let i = 0; i <= n; i++) {
      const w = width * (i === n ? 0.4 : 1 - 0.35 * (i / n));
      const p = pts[i];
      pos.push(p.x - ax * w, p.y, p.z - az * w, p.x + ax * w, p.y, p.z + az * w);
      if (i < n) { const k = base + i * 2; idx.push(k, k + 1, k + 2, k + 1, k + 3, k + 2); }
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  return g;
}

function boltMaterials() {
  if (boltMat) return;
  boltMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 2.7, 3.2), side: THREE.DoubleSide, depthWrite: false, fog: false });
  boltMat.name = 'fcBoltCore';
  glowMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.9, 0.85, 2.2), side: THREE.DoubleSide, transparent: true, opacity: 0.55,
    blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
  glowMat.name = 'fcBoltGlow';
}

// ------------------------------------------------------------------------------------------------ model
const pool = [];

function hasBaked(game) {
  return !(game.params && game.params.art === 0) && !!BAKED.z_forecaster && typeof charRuntime.buildCharacter === 'function';
}

function buildModel(game) {
  const M = game.mats;
  const c = charRuntime.buildCharacter(fcDef, { envMap: M.envMap, globals: M.uniforms, layer: LAYERS.ZOMBIES, animator: FC_STYLE });
  if (!c.animator) throw new Error('z_forecaster has no animator');
  if (typeof c.animator.kick !== 'function') c.animator.kick = () => {};
  const J = c.rig.joints;
  const eyes = zombieEyeMaterial();
  let rod = null;
  c.group.traverse((o) => {
    if (o.isMesh && o.userData.staticEye) o.material = eyes;
    if (o.isMesh) o.castShadow = !!o.isSkinnedMesh;
    if (o.name === 'pointerRod') { rod = o; o.userData.noMerge = true; }
  });
  const cloudPivot = c.parts && c.parts.cloud;
  if (cloudPivot) cloudPivot.userData.noMerge = true;
  // The telescoping rod is a driving node of its own: its segments merge per material (a plain mesh on the rod, so
  // they still scale with it), the eyes / veils / rims into plain head meshes; one skeleton per forecaster.
  // charOpt.merge off: the older geo.skinRig (own skeleton, A/B).
  const extra = rod ? { pointerRod: rod } : {};
  try {
    if (charRuntime.charOpt && charRuntime.charOpt.merge) charRuntime.mergeAttachments(c, { bones: Object.values(extra) });
    else skinRig({ root: c.rig.root, joints: { ...c.rig.joints, ...extra }, dims: c.rig.dims });
  } catch (err) { if (!warned) { warned = true; console.warn('[forecaster] attachment merge failed', err); } }
  const bodies = [];
  c.group.traverse((o) => { if (o.isSkinnedMesh) { if (o === c.skinnedMesh) bodies.push(o); else o.castShadow = false; } });
  const m = baseModel(game, c.group, c.rig, c.animator, true);
  m.bodies = bodies;
  // the lapel ticket stub (multi-material card) is hidden at distance by the manager's card LOD
  c.group.traverse((o) => { if (o.isMesh && Array.isArray(o.material)) m.cards.push(o); });
  if (c.skinnedMesh) registerSpecialTint(game, c.skinnedMesh.material);
  m.rod = rod;
  if (cloudPivot) setupCloud(game, m, cloudPivot);
  return m;
}

// Placeholder (art=0 / no bake): the manager's humanoid placeholder + a toy cloud of spheres.
function buildPlaceholder(game) {
  const pm = acquireModel(game, 'forecaster', 'placeholder');
  const m = baseModel(game, pm.group, pm.rig, pm.animator, false);
  m.placeholder = pm;
  m.head = pm.head; m.headR = pm.headR;
  const pivot = new THREE.Group();
  pivot.name = 'part:cloud';
  const mat = game.mats.toon('#9AA3B2', { rough: 0.85, rim: 0.4, keepColor: true });
  for (const [x, y, z, r] of [[0, 0.03, 0, 0.12], [-0.12, -0.02, 0, 0.09], [0.125, -0.015, 0, 0.095], [0.06, 0.07, 0.05, 0.09]]) {
    pivot.add(geo.mesh(geo.sphere(r, 14, 10), mat, { pos: [x, y, z], cast: false }));
  }
  pivot.position.set(0, (pm.headR || 0.3) * 2 + 0.6, 0);
  pm.rig.joints.head.add(pivot);
  setupCloud(game, m, pivot);
  return m;
}

function baseModel(game, group, rig, animator, baked) {
  const J = rig.joints;
  const headR = (rig.dims ? rig.dims.headH : 0.6) * 0.5;
  let head = group.getObjectByName('part:headCenter');
  if (!head) {
    head = new THREE.Object3D();
    head.name = 'part:headCenter';
    head.position.set(0, headR * 0.95, -0.02);
    J.head.add(head);
  }
  const m = { group, rig, J, animator, head, headR, baked, def: { id: 'forecaster' }, variant: baked ? 'z_forecaster' : 'placeholder', cards: [] };
  m.serial = ++serial;
  // Per-model FX: storm shell material, shadow disc, bolt meshes, rainbow.
  m.stormMat = game.mats.toon('#2C3046', { transparent: true, opacity: 0, rough: 0.9, rim: 0.5, rimColor: '#A8B4FF', keepColor: true, depthWrite: false, name: 'fcStorm' + m.serial });
  const discMat = new THREE.MeshBasicMaterial({ map: discTexture(), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4, fog: false });
  discMat.name = 'fcShadowDisc';
  m.disc = new THREE.Mesh(new THREE.CircleGeometry(1, 40).rotateX(-Math.PI / 2), discMat);
  m.disc.name = 'fc:shadowDisc';
  m.disc.renderOrder = 2;
  m.disc.layers.set(LAYERS.ZOMBIES);
  m.disc.visible = false;
  boltMaterials();
  m.boltCore = new THREE.Mesh(new THREE.BufferGeometry(), boltMat);
  m.boltGlow = new THREE.Mesh(new THREE.BufferGeometry(), glowMat);
  for (const b of [m.boltCore, m.boltGlow]) { b.frustumCulled = false; b.layers.set(LAYERS.ZOMBIES); b.visible = false; b.renderOrder = 3; }
  const rbMat = new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, opacity: 1, depthWrite: false, fog: false, side: THREE.DoubleSide });
  rbMat.color.setScalar(1.1);
  m.rainbow = new THREE.Mesh(rainbowGeometry(), rbMat);
  m.rainbow.name = 'fc:rainbow';
  m.rainbow.layers.set(LAYERS.ZOMBIES);
  m.rainbow.visible = false;
  game.render.setLayerRecursive(group, LAYERS.ZOMBIES);
  group.name = 'zombie:forecaster';
  return m;
}

function setupCloud(game, m, pivot) {
  const mesh = pivot.children.find((o) => o.isMesh) || null;
  const cl = { pivot, mesh, local: pivot.position.clone(), parent: pivot.parent, center: new THREE.Vector3() };
  if (mesh) {
    mesh.geometry.computeBoundingBox();
    mesh.updateMatrix();
    mesh.geometry.boundingBox.getCenter(cl.center).applyMatrix4(mesh.matrix);
    // Storm shell: the same cloud geometry, dark and translucent, a bit larger around the cloud's centre.
    const sg = new THREE.Group();
    sg.position.copy(cl.center);
    sg.scale.setScalar(1.08);
    const shell = new THREE.Mesh(mesh.geometry, m.stormMat);
    shell.position.copy(mesh.position).sub(cl.center);
    shell.quaternion.copy(mesh.quaternion);
    shell.scale.copy(mesh.scale);
    shell.castShadow = false;
    shell.renderOrder = 1;
    sg.add(shell);
    pivot.add(sg);
    cl.shellG = sg;
    cl.shell = shell;
    mesh.castShadow = false;
  }
  // Height of the cloud centre over the feet at rest (head joint world y + local offset), for the hover target.
  m.rig.root.updateMatrixWorld(true);
  const w = pivot.getWorldPosition(new THREE.Vector3());
  cl.restY = w.y - (m.group.getWorldPosition(new THREE.Vector3()).y);
  cl.aboveHead = w.y - m.J.head.getWorldPosition(new THREE.Vector3()).y;
  game.render.setLayerRecursive(pivot, LAYERS.ZOMBIES);
  m.cloud = cl;
}

function acquire(game) {
  const want = hasBaked(game);
  // pooled models built under another charOpt.gen (A/B tools toggled a build-time flag) are dropped
  for (let i = pool.length - 1; i >= 0; i--) if ((pool[i].gen || 0) !== (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0)) pool.splice(i, 1);
  for (let i = pool.length - 1; i >= 0; i--) if (pool[i].baked === want) return pool.splice(i, 1)[0];
  if (want) {
    try { const m = buildModel(game); m.gen = (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0); return m; } catch (err) { if (!warned) { warned = true; console.warn('[forecaster] baked model failed, using the placeholder', err); } }
  }
  const m = buildPlaceholder(game);
  m.gen = (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0);
  return m;
}

function reattachCloud(m) {
  const cl = m.cloud;
  if (!cl) return;
  cl.pivot.removeFromParent();
  cl.pivot.position.copy(cl.local);
  cl.pivot.rotation.set(0, 0, 0);
  cl.pivot.scale.set(1, 1, 1);
  cl.pivot.visible = true;
  if (cl.parent) cl.parent.add(cl.pivot);
  m.stormMat.opacity = 0;
  m.stormMat.emissive.setRGB(0, 0, 0);
}

function resetModel(m) {
  const g = m.group;
  g.visible = true;
  g.position.set(0, 0, 0);
  g.rotation.set(0, 0, 0);
  g.scale.set(1, 1, 1);
  if (m.rig) {
    for (const j of Object.values(m.rig.joints)) j.scale.set(1, 1, 1);
    m.rig.root.rotation.set(0, 0, 0);
    m.rig.root.scale.set(1, 1, 1);
  }
  if (m.animator) {
    m.animator.override = null;
    if (m.animator.p) m.animator.p.arms = 'swing';
  }
  if (m.rod) m.rod.scale.set(1, 1, 1);
  for (const c of m.cards) c.visible = true;
  for (const o of [m.disc, m.boltCore, m.boltGlow, m.rainbow]) { o.removeFromParent(); o.visible = false; }
  if (m.umbrella) { m.umbrella.removeFromParent(); }
  reattachCloud(m);
}

// ------------------------------------------------------------------------------------------------ cloud
function cloudWorldCenter(z, out) {
  const cl = z.model && z.model.cloud;
  if (!cl) return out.copy(z.pos);
  const s = cl.pivot.scale.x;
  return out.copy(cl.center).multiplyScalar(s).applyQuaternion(cl.pivot.quaternion).add(cl.pivot.position);
}

function hoverTarget(z, out) {
  const f = z.flags, cl = z.model.cloud;
  const s = z.scale || 1;
  if (z.state === 'screen' || z.state === 'vault') {
    // entries (taffy emerge, fence climb): follow the head itself, scaled with the body
    z.model.J.head.getWorldPosition(out);
    out.y += cl.aboveHead * s * Math.max(0.1, z.group.scale.y || 1);
    return out;
  }
  out.set(z.pos.x, z.pos.y + cl.restY * s + Math.sin(f.t * 2.1 + z.id) * 0.045, z.pos.z);
  // follow the head's lean a little
  out.x += -Math.sin(z.yaw) * 0.03;
  out.z += -Math.cos(z.yaw) * 0.03;
  return out;
}

function registerCloud(game, z) {
  const W = game.weapons;
  const f = z.flags;
  f.shootId = 'fc_cloud_' + z.id;
  if (!W || typeof W.registerShootable !== 'function') return;
  try {
    W.registerShootable({
      id: f.shootId,
      raycast(o, d, max) {
        const c = f.cloud;
        if (!c || c.state === 'popped' || c.state === 'gone' || z.removed || !z.model || !z.model.cloud.pivot.visible) return null;
        cloudWorldCenter(z, _c);
        _d.subVectors(o, _c);
        const r = 0.25 * (z.scale || 1);
        const b = _d.dot(d), q = _d.lengthSq() - r * r, disc = b * b - q;
        if (disc < 0) return null;
        const t = -b - Math.sqrt(disc);
        if (t < 0 || t > max) return null;
        return { dist: t, point: o.clone().addScaledVector(d, t) };
      },
      onHit(info) { hitCloud(game, z, info.damage || 0, info); },
      blocksBullet: true,
      melee: true,
    });
  } catch (err) { /* weapons is someone else's */ }
}

function unregisterCloud(game, z) {
  const f = z.flags;
  if (!f.shootId) return;
  try { game.weapons && game.weapons.unregisterShootable && game.weapons.unregisterShootable(f.shootId); } catch (err) { /* ignore */ }
  f.shootId = null;
}

function hitCloud(game, z, dmg, info = {}) {
  const f = z.flags, c = f.cloud;
  if (!c || c.state === 'popped' || c.state === 'gone' || z.dead || !(dmg > 0)) return;
  c.hp -= dmg;
  c.punch = 1;
  cloudWorldCenter(z, _a);
  game.fx.burst(info.point || _a, { shape: 'puff', count: 3, size: 0.08, speed: 1.4, life: 0.4, colors: ['#AEB6C4', '#8C94A6'] });
  game.audio.play('zmb_hit', { pos: _a, rate: 1.35, vol: 0.6 });
  if (c.hp <= 0) popCloud(game, z);
  else if (game.hud && typeof game.hud.hitmarker === 'function') game.hud.hitmarker(false, false);
}

function popCloud(game, z) {
  const f = z.flags, c = f.cloud, m = z.model;
  if (!c || c.state === 'popped' || c.state === 'gone') return false;
  cloudWorldCenter(z, _a);
  c.state = 'popped';
  c.hp = 0;
  m.cloud.pivot.visible = false;
  m.disc.visible = false;
  unregisterCloud(game, z);
  // Mini rainbow + colour confetti + a white puff.
  game.fx.burst(_a, { shape: 'confetti', count: 26, speed: 4, colors: RAINBOW });
  game.fx.burst(_a, { shape: 'star', count: 6, speed: 2.6 });
  game.fx.burst(_a, { shape: 'puff', count: 6, size: 0.075, speed: 2.2, life: 0.5, colors: ['#F4F6FA', '#D8DEE8'] });
  game.audio.play('fc_cloud_pop', { pos: _a });
  if (game.hud && typeof game.hud.hitmarker === 'function') game.hud.hitmarker(false, true);
  const rb = m.rainbow;
  rb.position.copy(_a);
  rb.visible = true;
  rb.scale.setScalar(0.01);
  rb.material.opacity = 1;
  game.scene.add(rb);
  f.rainbowT = 0;
  // He sobs, then chases for the rest of his (doubled-damage) life.
  f.sobbed = true;
  if (!z.dead) {
    f.mode = 'sob';
    f.mt = 0;
    f.jab = null;
    f.tearT = 0;
    z.vel.set(0, 0, 0);
    game.audio.play('fc_sob', { pos: z.pos });
    if (z.animator && z.animator.kick) z.animator.kick(0.8);
  }
  return true;
}

// Cloud state machine: home (hover) -> fly -> lock (telegraph) -> strike -> return -> home. Runs every frame.
function tickCloud(game, z, dt) {
  const f = z.flags, c = f.cloud, m = z.model;
  if (!c || !m.cloud) return;
  f.cloudFrame = game.time.frame;
  const cl = m.cloud, piv = cl.pivot;
  // rainbow fades whatever the cloud does
  if (f.rainbowT !== undefined && m.rainbow.visible) {
    f.rainbowT += dt;
    const k = f.rainbowT;
    m.rainbow.scale.setScalar(Math.max(0.01, 0.72 * easeOutBack(k / 0.35) * (1 + k * 0.15)));
    m.rainbow.position.y += dt * 0.25;
    m.rainbow.rotation.y = Math.atan2(game.camera.position.x - m.rainbow.position.x, game.camera.position.z - m.rainbow.position.z);
    m.rainbow.material.opacity = 1 - smooth((k - 1.0) / 0.6);
    if (k > 1.6) { m.rainbow.visible = false; m.rainbow.removeFromParent(); }
  }
  if (c.state === 'popped' || c.state === 'gone') return;
  piv.visible = z.group.visible || c.state !== 'home';
  c.t += dt;
  c.punch = Math.max(0, (c.punch || 0) - dt * 5);
  let dark = 0, shake = 0, s = 1 + Math.sin(f.t * 3.3 + z.id) * 0.03;
  const yawWant = c.state === 'home' ? z.yaw : c.faceYaw ?? z.yaw;
  if (c.state === 'home') {
    hoverTarget(z, _b);
    const k = 1 - Math.exp(-dt * 9);
    c.pos.lerp(_b, k);
    // hard clamp: never trail more than 0.5 m (fast knockbacks, teleports)
    if (c.pos.distanceToSquared(_b) > 0.25) c.pos.copy(_b).addScaledVector(_d.subVectors(c.pos, _b).normalize(), 0.5);
  } else if (c.state === 'fly') {
    const dist = c.from.distanceTo(c.target);
    const dur = Math.max(0.15, dist / F.cloudSpeed);
    const u = clamp01(c.t / dur);
    const e = easeInOut(u);
    c.pos.lerpVectors(c.from, c.target, e);
    c.pos.y += Math.sin(u * Math.PI) * Math.min(1.2, dist * 0.08);
    c.faceYaw = yawTo(c.target.x - c.from.x, c.target.z - c.from.z);
    s *= 1 + Math.sin(u * Math.PI) * 0.12;
    if (u >= 1) { c.state = 'lock'; c.t = 0; beginLock(game, z); }
  } else if (c.state === 'lock') {
    const u = clamp01(c.t / F.telegraph);
    dark = smooth(u / 0.5);
    shake = 0.015 + 0.035 * u;
    s *= 1 + 0.12 * smooth(u / 0.3) + Math.sin(c.t * 40) * 0.02 * u;
    c.pos.copy(c.target);
    const d = m.disc;
    const grow = easeOutBack(c.t / 0.35);
    const pulse = 1 + Math.sin(c.t * 18) * 0.03 * u;
    d.scale.setScalar(Math.max(0.05, F.strikeR * grow * pulse));
    d.material.opacity = 0.55 + 0.45 * u;
    // drizzle, then flicker inside the cloud
    c.rainT = (c.rainT || 0) - dt;
    if (c.rainT <= 0) {
      c.rainT = lerp(0.12, 0.035, u);
      _a.set(c.pos.x + (Math.random() - 0.5) * 0.35, c.pos.y - 0.12, c.pos.z + (Math.random() - 0.5) * 0.2);
      game.fx.burst(_a, { shape: 'goo', count: 1, size: 0.025, speed: 0.4, life: 0.6, gravity: 16, dir: _d.set(0, -1, 0), cone: 0.1, colors: ['#7FC4FF', '#B8E2FF'] });
    }
    if (u > 0.55) {
      const fl = Math.random() < 0.35 ? 1.4 : 0;
      m.stormMat.emissive.setRGB(fl * 0.8, fl * 0.85, fl * 1.2);
    }
    if (c.t >= F.telegraph) strike(game, z);
  } else if (c.state === 'strike') {
    dark = 1 - smooth(c.t / 0.5) * 0.6;
    c.pos.copy(c.target);
    const u = clamp01(c.t / 0.28);
    const vis = u < 1 && (c.t < 0.06 || Math.floor(c.t * 40) % 3 !== 0);
    m.boltCore.visible = vis;
    m.boltGlow.visible = vis;
    m.stormMat.emissive.setRGB(vis ? 1.2 : 0, vis ? 1.25 : 0, vis ? 1.6 : 0);
    m.disc.material.opacity = Math.max(0, 1 - c.t / 0.35);
    m.disc.scale.setScalar(F.strikeR * (1 + c.t * 0.3));
    if (c.t >= 0.5) {
      m.disc.visible = false; m.boltCore.visible = false; m.boltGlow.visible = false;
      m.stormMat.emissive.setRGB(0, 0, 0);
      c.state = 'return'; c.t = 0;
    }
  } else if (c.state === 'return') {
    dark = Math.max(0, 0.4 - c.t);
    hoverTarget(z, _b);
    _d.subVectors(_b, c.pos);
    const d = _d.length();
    const step = RETURN_SPEED * dt;
    c.faceYaw = yawTo(_d.x, _d.z);
    if (d <= step + 0.02) { c.pos.copy(_b); c.state = 'home'; c.t = 0; c.punch = 0.8; }
    else c.pos.addScaledVector(_d, step / d);
  } else if (c.state === 'drift') {
    // his owner is gone: drift up and fade (the EE may take over from here)
    c.pos.y += dt * 0.9;
    c.pos.x += Math.sin(c.t * 1.7) * dt * 0.3;
    s *= 1 - smooth((c.t - 0.6) / 0.6);
    dark = 0.3;
    if (c.t > 1.2) { c.state = 'gone'; piv.visible = false; return; }
  }
  // write the transform
  piv.position.copy(c.pos);
  if (shake) { piv.position.x += (Math.random() - 0.5) * shake * 2; piv.position.y += (Math.random() - 0.5) * shake; piv.position.z += (Math.random() - 0.5) * shake * 2; }
  c.yaw += angDiff(yawWant, c.yaw) * Math.min(1, dt * 6);
  piv.rotation.set(Math.sin(f.t * 1.3 + z.id) * 0.06, c.yaw, Math.sin(f.t * 1.7) * 0.05);
  const punch = 1 + Math.sin((1 - c.punch) * Math.PI * 3) * 0.18 * c.punch;
  const entryS = c.state === 'home' && (z.state === 'screen' || z.state === 'vault') ? Math.max(0.1, z.group.scale.y || 1) / (z.scale || 1) : 1;
  const sc = (z.scale || 1) * s * punch * entryS;
  piv.scale.set(sc * (1 + 0.1 * c.punch), sc * (1 - 0.08 * c.punch), sc);
  c.dark += (dark - c.dark) * Math.min(1, dt * 10);
  m.stormMat.opacity = c.dark * 0.8;   // the grumpy face still shows through
  if (cl.shellG) cl.shellG.visible = c.dark > 0.02;
  if (c.state !== 'lock' && c.state !== 'strike') m.stormMat.emissive.setRGB(0, 0, 0);
}

function launchCloud(game, z) {
  const f = z.flags, c = f.cloud, p = game.player, col = game.level.col;
  c.from = c.pos.clone();
  const target = new THREE.Vector3(p.pos.x, p.pos.y + FLOAT_H, p.pos.z);
  // stay under the ceiling
  const hit = col.raycast(_a.set(p.pos.x, p.pos.y + 1.2, p.pos.z), _up, FLOAT_H + 0.5);
  if (hit) target.y = Math.min(target.y, hit.point.y - 0.4);
  target.y = Math.max(target.y, p.pos.y + 1.9);
  c.target = target;
  const fy = col.floorAt(p.pos.x, p.pos.z, p.pos.y + 0.5);
  c.floor = new THREE.Vector3(p.pos.x, (fy > -Infinity ? fy : p.pos.y) + 0.03, p.pos.z);
  c.state = 'fly';
  c.t = 0;
  game.audio.play('zmb_swipe', { pos: c.pos, rate: 0.7, vol: 0.6 });
}

function beginLock(game, z) {
  const f = z.flags, c = f.cloud, m = z.model;
  const d = m.disc;
  d.position.copy(c.floor);
  d.scale.setScalar(0.05);
  d.material.opacity = 0.5;
  d.visible = true;
  game.scene.add(d);
  game.audio.play('fc_rumble', { pos: c.target });
}

function strike(game, z) {
  const f = z.flags, c = f.cloud, m = z.model, p = game.player;
  c.state = 'strike';
  c.t = 0;
  const top = _a.copy(c.target).setY(c.target.y - 0.12);
  const bot = _b.copy(c.floor);
  // bolt geometry (regenerated per strike)
  m.boltCore.geometry.dispose();
  m.boltGlow.geometry.dispose();
  const core = boltGeometry(top, bot, 0.26, 9, 0.05);
  m.boltCore.geometry = core;
  m.boltGlow.geometry = boltGeometry(top, bot, 0.3, 9, 0.2);
  m.boltGlow.geometry.setAttribute('position', core.attributes.position.clone());
  // widen the glow copy around the same zig-zag
  {
    const P = m.boltGlow.geometry.attributes.position.array;
    const n = P.length / 6;
    for (let i = 0; i < n; i++) {
      const k = i * 6;
      const cx = (P[k] + P[k + 3]) / 2, cz = (P[k + 2] + P[k + 5]) / 2;
      P[k] = cx + (P[k] - cx) * 3.6; P[k + 2] = cz + (P[k + 2] - cz) * 3.6;
      P[k + 3] = cx + (P[k + 3] - cx) * 3.6; P[k + 5] = cz + (P[k + 5] - cz) * 3.6;
    }
  }
  for (const b of [m.boltCore, m.boltGlow]) { b.visible = true; game.scene.add(b); }
  game.audio.play('fc_lightning', { pos: bot });
  game.fx.flashLight(_c.copy(bot).setY(bot.y + 1.0), '#C8D4FF', 16, 0.14);
  game.fx.burst(bot, { shape: 'spark', count: 18, speed: 8, colors: ['#FFFFFF', '#C8D4FF', '#9FB6FF'] });
  game.fx.burst(bot, { shape: 'static', count: 12, speed: 2.6, size: 0.08 });
  game.fx.burst(bot, { shape: 'puff', count: 5, size: 0.16, speed: 1.6, colors: ['#5A5F72', '#8A8FA2'] });
  try { game.fx.decal(bot, _up, 'scorch', 1.3); } catch (err) { /* optional */ }
  const dCam = game.camera.position.distanceTo(bot);
  if (dCam < 14) game.fx.shake(0.35 * (1 - dCam / 14) + 0.05, 0.3);
  // Damage: inside the circle (horizontally) and roughly on that floor.
  const hd = Math.hypot(p.pos.x - bot.x, p.pos.z - bot.z);
  const dy = p.pos.y - bot.y;
  if (p.alive && hd <= F.strikeR && dy > -0.8 && dy < 1.8) {
    if (p.hurt(F.strikeDmg, bot)) {
      game.events.emit('zombie:attack', { z, dmg: F.strikeDmg, kind: 'lightning' });
      // 0.5 s static overlay (the HUD owns the post knobs and decays them itself)
      try { if (game.hud && game.hud.glitch) game.hud.glitch(1, 0.5); if (game.hud && game.hud.tear) game.hud.tear('top'); } catch (err) { /* optional */ }
    }
  }
}

// ------------------------------------------------------------------------------------------------ poses
function makeOverride(z) {
  return (rig, dt) => {
    const f = z.flags;
    const g = f && f.game;
    if (!f || !z.model) return;
    if (g && f.cloudFrame !== g.time.frame && !z.dead) { try { tickCloud(g, z, dt); } catch (err) { /* keep animating */ } }
    poseForecaster(z, rig, dt);
  };
}

function aimArm(J, pitch, yawOff, k) {
  // right arm points along (pitch up from horizontal, yaw offset from the body facing)
  J.shoulderR.rotation.x = lerp(J.shoulderR.rotation.x, Math.PI / 2 + pitch, k);
  J.shoulderR.rotation.y = lerp(J.shoulderR.rotation.y, 0, k);
  J.shoulderR.rotation.z = lerp(J.shoulderR.rotation.z, -0.15 + yawOff, k);
  J.elbowR.rotation.x = lerp(J.elbowR.rotation.x, 0.08, k);
  J.handR.rotation.x = lerp(J.handR.rotation.x, 1.1, k);
}

function poseForecaster(z, rig, dt) {
  const f = z.flags, J = rig.joints, m = z.model;
  f.t += dt;
  const t = f.t;
  let rod = 0.38;
  const mode = f.mode;
  if (mode === 'twirl') {
    const u = clamp01(f.mt / TWIRL);
    const up = easeOutBack(u / 0.25);
    // arm up over the head, forearm spinning the pointer in circles
    J.shoulderR.rotation.x = lerp(J.shoulderR.rotation.x, 2.75, up);
    J.shoulderR.rotation.z = lerp(J.shoulderR.rotation.z, -0.25, up);
    J.elbowR.rotation.x = 0.35 + Math.sin(t * 26) * 0.35 * up;
    J.elbowR.rotation.y = Math.cos(t * 26) * 0.45 * up;
    J.handR.rotation.x = 0.9 + Math.sin(t * 26 + 1) * 0.3;
    J.spine.rotation.x += 0.12 * up;
    J.head.rotation.x += 0.28 * up;
    J.shoulderL.rotation.x = lerp(J.shoulderL.rotation.x, 0.5, up);
    J.shoulderL.rotation.z = lerp(J.shoulderL.rotation.z, 0.9, up);
    J.elbowL.rotation.x = lerp(J.elbowL.rotation.x, 1.2, up);
    rod = lerp(0.38, 1, smooth(u / 0.3));
    // finale: snap the pointer at the player
    if (u > 0.8) aimArm(J, 0.35, 0, smooth((u - 0.8) / 0.2));
  } else if (mode === 'conduct' || (f.cloud && (f.cloud.state === 'fly' || f.cloud.state === 'lock' || f.cloud.state === 'strike') && !f.sobbed && mode !== 'jab')) {
    // point at the cloud
    const c = f.cloud;
    const tgt = c && c.pos ? c.pos : z.pos;
    const dx = tgt.x - z.pos.x, dz = tgt.z - z.pos.z, dy = tgt.y - (z.pos.y + 1.45);
    const pitch = Math.atan2(dy, Math.hypot(dx, dz));
    const yawOff = THREE.MathUtils.clamp(angDiff(yawTo(dx, dz), z.yaw), -0.8, 0.8);
    aimArm(J, THREE.MathUtils.clamp(pitch, -0.4, 1.3), -yawOff * 0.8, 0.85);
    J.chest.rotation.y += yawOff * 0.4;
    J.head.rotation.x += THREE.MathUtils.clamp(pitch, -0.3, 0.8) * 0.4;
    const strikeK = c && c.state === 'strike' ? Math.max(0, 1 - c.t / 0.3) : 0;
    J.spine.rotation.x += 0.18 * strikeK;
    rod = 1;
  } else if (mode === 'jab' && f.jab) {
    const j = f.jab, tt = j.t;
    if (tt < JAB.windup) {
      const k = smooth(tt / JAB.windup);
      J.shoulderR.rotation.x = lerp(J.shoulderR.rotation.x, -0.55, k);
      J.elbowR.rotation.x = lerp(J.elbowR.rotation.x, 1.5, k);
      J.chest.rotation.y += 0.35 * k;
      rod = lerp(0.38, 0.6, k);
    } else if (tt < JAB.windup + JAB.strike) {
      const k = easeOutCubic((tt - JAB.windup) / JAB.strike);
      J.shoulderR.rotation.x = lerp(-0.55, 1.55, k);
      J.elbowR.rotation.x = lerp(1.5, 0.02, k);
      J.handR.rotation.x = 1.2;
      J.chest.rotation.y += lerp(0.35, -0.3, k);
      J.spine.rotation.x -= 0.15 * k;
      rod = 1;
    } else {
      const k = smooth((tt - JAB.windup - JAB.strike) / JAB.recover);
      J.shoulderR.rotation.x = lerp(1.55, J.shoulderR.rotation.x, k);
      J.elbowR.rotation.x = lerp(0.02, J.elbowR.rotation.x, k);
      J.handR.rotation.x = lerp(1.2, 0, k);
      J.chest.rotation.y += -0.3 * (1 - k);
      rod = lerp(1, 0.38, k);
    }
  } else if (mode === 'sob') {
    const k = smooth(f.mt / 0.25) * (1 - smooth((f.mt - SOB_TIME + 0.3) / 0.3));
    const shake = Math.sin(t * 22) * 0.06;
    J.shoulderL.rotation.set(lerp(J.shoulderL.rotation.x, 2.1, k), 0, lerp(J.shoulderL.rotation.z, -0.35, k));
    J.shoulderR.rotation.set(lerp(J.shoulderR.rotation.x, 2.1, k), 0, lerp(J.shoulderR.rotation.z, 0.35, k));
    J.elbowL.rotation.x = lerp(J.elbowL.rotation.x, 2.3, k);
    J.elbowR.rotation.x = lerp(J.elbowR.rotation.x, 2.3, k);
    J.spine.rotation.x -= 0.25 * k;
    J.chest.rotation.x += shake * k;
    J.head.rotation.x -= (0.35 + shake) * k;
    J.kneeL.rotation.x -= 0.25 * k; J.kneeR.rotation.x -= 0.25 * k;
    J.hipL.rotation.x += 0.12 * k; J.hipR.rotation.x += 0.12 * k;
    rod = 0.38;
  } else if (mode === 'dying') {
    // hanging from the umbrella: both arms up, legs dangling and kicking
    const d = f.death || {};
    const k = smooth(((d.t || 0) - 0.15) / 0.25);
    J.shoulderL.rotation.set(lerp(J.shoulderL.rotation.x, 3.0, k), 0, lerp(J.shoulderL.rotation.z, -0.12, k));
    J.shoulderR.rotation.set(lerp(J.shoulderR.rotation.x, 3.0, k), 0, lerp(J.shoulderR.rotation.z, 0.12, k));
    J.elbowL.rotation.x = lerp(J.elbowL.rotation.x, 0.2, k);
    J.elbowR.rotation.x = lerp(J.elbowR.rotation.x, 0.2, k);
    const kick = Math.sin(t * 9) * 0.45 * k;
    J.hipL.rotation.x = 0.1 + kick; J.hipR.rotation.x = 0.1 - kick;
    J.kneeL.rotation.x = -0.3 - Math.max(0, kick); J.kneeR.rotation.x = -0.3 - Math.max(0, -kick);
    J.footL.rotation.x = 0.4; J.footR.rotation.x = 0.4;
    J.head.rotation.x += 0.25 * k;
    rod = 0.38;
  } else if (f.cloud && f.cloud.state === 'home' && !f.sobbed) {
    // idle showmanship: now and then an open-palm "and here's the weather" sweep with the left hand
    const ph = (t + z.id * 1.7) % 7;
    if (ph < 1.2) {
      const k = Math.sin((ph / 1.2) * Math.PI);
      J.shoulderL.rotation.x += 0.9 * k;
      J.shoulderL.rotation.z += 0.7 * k;
      J.elbowL.rotation.x += 0.2 * k;
      J.handL.rotation.z -= 0.4 * k;
    }
  }
  if (m.rod) {
    f.rod = f.rod === undefined ? rod : f.rod + (rod - f.rod) * Math.min(1, dt * 14);
    m.rod.scale.set(1, Math.max(0.3, f.rod), 1);
  }
}

// ------------------------------------------------------------------------------------------------ behaviour
function losTo(game, z, p) {
  _a.set(z.pos.x, z.pos.y + 1.5, z.pos.z);
  _b.set(p.pos.x, p.pos.y + 1.4, p.pos.z);
  try { return game.level.col.lineOfSight(_a, _b); } catch (err) { return true; }
}

function startJab(game, z) {
  const f = z.flags;
  f.prevMode = f.mode;
  f.mode = 'jab';
  f.jab = { t: 0, hit: false };
  game.audio.play('zmb_swipe', { pos: z.pos, rate: 1.2, vol: 0.7 });
}

function doJab(game, z, dt) {
  const f = z.flags, j = f.jab, p = game.player;
  j.t += dt;
  const dx = p.pos.x - z.pos.x, dz = p.pos.z - z.pos.z;
  const dist = Math.hypot(dx, dz);
  if (j.t < JAB.windup) z.yaw += angDiff(yawTo(dx, dz), z.yaw) * Math.min(1, dt * 10);
  if (!j.hit && j.t >= JAB.windup + JAB.strike * 0.6) {
    j.hit = true;
    z.cd = JAB.cd;
    const fwd = (-Math.sin(z.yaw) * dx - Math.cos(z.yaw) * dz) / Math.max(1e-3, dist);
    if (p.alive && dist < JAB.range + 0.35 && Math.abs(p.pos.y - z.pos.y) < 1.3 && fwd > 0.4) {
      if (p.hurt(JAB.dmg, z.pos)) {
        game.events.emit('zombie:attack', { z, dmg: JAB.dmg, kind: 'jab' });
        _a.set(dx, 0, dz).normalize().multiplyScalar(3);
        if (p.knockback) p.knockback(_a);
      }
      game.audio.play('zmb_hit', { pos: p.pos, rate: 1.5, vol: 0.7 });
    }
  }
  z.vel.multiplyScalar(Math.exp(-dt * 10));
  fall(game, z, dt);
  if (j.t >= JAB.windup + JAB.strike + JAB.recover) { f.mode = f.sobbed ? 'chase' : 'strafe'; f.jab = null; }
}

function fall(game, z, dt) {
  z.vy -= G * dt;
  _d.set(z.vel.x * dt, z.vy * dt, z.vel.z * dt);
  const r = game.level.col.moveCircle(z.pos, _d, z.radius, z.height, 0.45);
  if (r.onGround) z.vy = 0;
  return r;
}

function strafe(game, z, dt, dist, dx, dz) {
  const f = z.flags, nav = game.nav;
  const [near, far] = F.keep;
  let mx = 0, mz = 0;
  const ux = dx / dist, uz = dz / dist;
  f.sideT -= dt;
  if (f.sideT <= 0) { f.side = -f.side; f.sideT = 1.5 + Math.random() * 1.5; }
  if (!f.los || dist > far) {
    if (f.los && dist < far + 6) { mx = ux; mz = uz; } else { nav.dir(z.pos.x, z.pos.z, _d); mx = _d.x; mz = _d.z; if (!mx && !mz) { mx = ux; mz = uz; } }
  } else if (dist < near) {
    mx = -ux * 0.85 + -uz * f.side * 0.5;
    mz = -uz * 0.85 + ux * f.side * 0.5;
  } else {
    const radial = THREE.MathUtils.clamp((dist - (near + far) / 2) / 3, -1, 1) * 0.35;
    mx = -uz * f.side + ux * radial;
    mz = ux * f.side + uz * radial;
  }
  mx += (z.sepX || 0) * 1.2; mz += (z.sepZ || 0) * 1.2;
  const l = Math.hypot(mx, mz) || 1;
  const sp = z.speed;
  const k = 1 - Math.exp(-dt * STRAFE_ACCEL);
  z.vel.x += ((mx / l) * sp - z.vel.x) * k;
  z.vel.z += ((mz / l) * sp - z.vel.z) * k;
  const r = fall(game, z, dt);
  if (r.hitWall && f.blockT <= 0) { f.side = -f.side; f.sideT = 1.2 + Math.random(); f.blockT = 0.5; }
  f.blockT -= dt;
  // face the player (when visible), legs toward the movement
  const faceYaw = f.los ? yawTo(dx, dz) : (z.vel.lengthSq() > 0.05 ? yawTo(z.vel.x, z.vel.z) : z.yaw);
  const prev = z.yaw;
  z.yaw += angDiff(faceYaw, z.yaw) * Math.min(1, dt * 7);
  z.anim.turn = (z.yaw - prev) / Math.max(dt, 1e-4);
  const spd = Math.hypot(z.vel.x, z.vel.z);
  z.anim.speed = spd;
  if (spd > 0.2) {
    const moveYaw = yawTo(z.vel.x, z.vel.z);
    let rel = angDiff(moveYaw, z.yaw);
    const back = Math.abs(rel) > Math.PI * 0.6;
    if (back) rel = angDiff(moveYaw + Math.PI, z.yaw);
    z.anim.back = back;
    z.anim.legYaw = THREE.MathUtils.clamp(rel, -1.1, 1.1);
  } else { z.anim.back = false; z.anim.legYaw = 0; }
  // Holding range on purpose is not being stuck (the manager's anti-stuck watches nav distance).
  if (f.los && dist < far + 3) z.navBest = Infinity;
}

function updateForecaster(game, z, dt) {
  const f = z.flags, p = game.player, Zs = game.zombies;
  z.gawkT = 0;
  tickCloud(game, z, dt);
  const dx = p.pos.x - z.pos.x, dz = p.pos.z - z.pos.z;
  const dist = Math.max(1e-3, Math.hypot(dx, dz));
  f.losT -= dt;
  if (f.losT <= 0) { f.losT = 0.25; f.los = dist < 30 ? losTo(game, z, p) : false; }
  f.castT -= dt;
  // flavour: cheesy humming
  f.humT -= dt;
  if (f.humT <= 0) {
    f.humT = 5 + Math.random() * 5;
    if (dist < 16 && !f.sobbed && f.mode === 'strafe') game.audio.play('fc_hum', { pos: z.pos, rate: 0.95 + Math.random() * 0.1, vol: 0.7 });
  }
  if (Zs.lure && z.lured && f.mode !== 'sob' && f.mode !== 'jab') { if (f.mode === 'twirl') f.mode = 'strafe'; z.anim.legYaw = 0; z.anim.back = false; return false; }

  switch (f.mode) {
    case 'sob': {
      f.mt += dt;
      z.vel.multiplyScalar(Math.exp(-dt * 10));
      fall(game, z, dt);
      z.anim.speed = 0; z.anim.legYaw = 0; z.anim.back = false;
      f.tearT -= dt;
      if (f.tearT <= 0 && z.head) {
        f.tearT = 0.09;
        z.head.getWorldPosition(_a);
        _a.y += 0.02;
        for (const s of [-1, 1]) {
          _b.set(-Math.cos(z.yaw) * 0.08 * s, 0, Math.sin(z.yaw) * 0.08 * s).add(_a);
          _b.x += -Math.sin(z.yaw) * 0.14; _b.z += -Math.cos(z.yaw) * 0.14;
          game.fx.burst(_b, { shape: 'goo', count: 1, size: 0.03, speed: 1.6, life: 0.5, gravity: 14, dir: _d.set(-Math.cos(z.yaw) * s, 0.6, Math.sin(z.yaw) * s), cone: 0.4, colors: ['#6FC0FF', '#B8E6FF'] });
        }
      }
      if (f.mt > 1.5 && !f.sob2) { f.sob2 = true; game.audio.play('fc_sob', { pos: z.pos, rate: 1.08, vol: 0.8 }); }
      z.navBest = Infinity;
      if (f.mt >= SOB_TIME) {
        f.mode = 'chase';
        z.speed = CHASE_SPEED;
        if (z.animator && z.animator.p) z.animator.p.arms = 'forward';
        game.audio.play('zmb_groan_chase', { pos: z.pos, rate: 0.9 });
      }
      return true;
    }
    case 'jab':
      doJab(game, z, dt);
      return true;
    case 'chase':
      z.anim.legYaw = 0; z.anim.back = false;
      if (p.alive && dist < JAB.range && z.cd <= 0 && Math.abs(p.pos.y - z.pos.y) < 1.2) { startJab(game, z); doJab(game, z, 0); return true; }
      return false;
    case 'twirl': {
      f.mt += dt;
      z.vel.multiplyScalar(Math.exp(-dt * 8));
      fall(game, z, dt);
      z.yaw += angDiff(yawTo(dx, dz), z.yaw) * Math.min(1, dt * 8);
      z.anim.speed = 0; z.anim.legYaw = 0; z.anim.back = false;
      z.navBest = Infinity;
      f.sparkT -= dt;
      if (f.sparkT <= 0 && z.model.rod) {
        f.sparkT = 0.06;
        z.model.rod.localToWorld(_a.set(0, -0.52, 0));
        game.fx.burst(_a, { shape: 'star', count: 1, size: 0.06, speed: 0.8, life: 0.45, colors: ['#FFF3B0', '#9FD8FF', '#FFC23A'] });
      }
      if (f.mt >= TWIRL) {
        if (f.cloud.state === 'home') launchCloud(game, z);
        f.mode = 'strafe';
      }
      return true;
    }
    default: {
      // strafe (casting happens from here)
      if (p.alive && dist < JAB.range && z.cd <= 0 && Math.abs(p.pos.y - z.pos.y) < 1.2) { startJab(game, z); doJab(game, z, 0); return true; }
      if (!f.sobbed && f.castT <= 0 && f.cloud.state === 'home' && f.los && dist < 24 && z.spawnT <= 0 && p.alive) {
        f.mode = 'twirl';
        f.mt = 0;
        f.sparkT = 0;
        f.castT = F.castCd;
        game.audio.play('fc_twirl', { pos: z.pos });
        return updateForecaster(game, z, 0);
      }
      strafe(game, z, dt, dist, dx, dz);
      return true;
    }
  }
}

// ------------------------------------------------------------------------------------------------ death
function startDeath(game, z) {
  const f = z.flags, m = z.model;
  f.mode = 'dying';
  f.death = { t: 0, popped: false, y0: z.pos.y, x0: z.pos.x, z0: z.pos.z, sway: (Math.random() < 0.5 ? -1 : 1) };
  m.disc.visible = false;
  m.boltCore.visible = false; m.boltGlow.visible = false;
  unregisterCloud(game, z);
  const c = f.cloud;
  if (c && c.state !== 'popped' && c.state !== 'gone') {
    // EE §13: killed with the cloud intact -> the Stray Storm may spawn where the cloud is.
    cloudWorldCenter(z, _a);
    game.events.emit('zombie:forecaster_storm', { pos: _a.clone(), z });
    c.state = 'drift';
    c.t = 0;
  }
  if (!m.umbrella) m.umbrella = buildUmbrella(game);
  const u = m.umbrella;
  u.visible = true;
  u.scale.setScalar(0.01);
  z.group.add(u);
  game.audio.play('fc_umbrella', { pos: z.pos });
  game.fx.burst(_a.copy(z.pos).setY(z.pos.y + 1.3), { shape: 'puff', count: 5, size: 0.12, speed: 1.6 });
  if (z.animator && z.animator.kick) z.animator.kick(0.9);
}

function updateDeath(game, z, dt, t) {
  const f = z.flags, m = z.model, d = f.death;
  if (!d || !m) return;
  d.t = t;
  // cloud keeps drifting / rainbow keeps fading
  tickCloud(game, z, dt);
  const u = m.umbrella;
  const H = (m.rig.dims ? m.rig.dims.height : 1.74);
  // umbrella: springs out of his back (0-0.2), swings up over his head and snaps open (0.2-0.45)
  if (t < 0.2) {
    const k = easeOutBack(t / 0.2);
    u.position.set(0, H * 0.72, 0.28);
    u.rotation.set(-0.9, 0, 0);
    u.scale.set(k * 0.4, k, k * 0.4);
  } else {
    const k = smooth((t - 0.2) / 0.25);
    u.position.set(0, lerp(H * 0.72, H + 0.52, k), lerp(0.28, 0.02, k));
    u.rotation.set(lerp(-0.9, 0, k), 0, 0);
    const open = t < 0.45 ? 0.4 : 0.4 + 0.72 * easeOutBack((t - 0.45) / 0.22);
    u.scale.set(open, 1, open);
    if (t >= 0.45 && !d.opened) { d.opened = true; game.audio.play('zmb_hit', { pos: z.pos, rate: 1.8, vol: 0.5 }); game.fx.burst(_a.copy(z.pos).setY(z.pos.y + H + 0.9), { shape: 'star', count: 4, speed: 1.6 }); }
  }
  // float up 3 m with a pendulum sway
  const rise = t < 0.45 ? 0 : FLOAT_H * easeInOut((t - 0.45) / 1.6);
  z.pos.set(d.x0 + Math.sin(t * 1.3) * 0.25 * d.sway * clamp01(t - 0.45), d.y0 + rise, d.z0);
  const G0 = z.group;
  G0.position.copy(z.pos);
  const sway = Math.sin((t - 0.45) * 3.1) * 0.14 * clamp01((t - 0.45) * 2);
  G0.rotation.set(0, z.yaw + t * 0.4 * d.sway, sway * d.sway, 'YXZ');
  const s = z.scale || 1;
  G0.scale.set(s, s, s);
  if (z.animator) {
    try { z.animator.update(dt, { speed: 0, grounded: false, hurt: 0 }); } catch (err) { /* keep dying */ }
  }
  if (t >= 2.1 && !d.popped) {
    d.popped = true;
    _a.copy(z.pos).setY(z.pos.y + H * 0.6);
    game.fx.burst(_a, { shape: 'confetti', count: 40, speed: 5.5 });
    game.fx.burst(_a, { shape: 'star', count: 8, speed: 3.5 });
    game.fx.burst(_a, { shape: 'puff', count: 8, size: 0.2, speed: 2 });
    game.fx.burst(_b.copy(z.pos).setY(z.pos.y + H + 0.9), { shape: 'confetti', count: 16, speed: 3, colors: ['#E23B3B', '#FFF4DE'] });
    game.audio.play('fc_umbrella', { pos: _a, rate: 1.22 });
    game.audio.play('zmb_death_static', { pos: _a, vol: 0.4 });
    G0.visible = false;
  }
}

// ------------------------------------------------------------------------------------------------ module
let grenadeHooked = new WeakSet();

function hookGrenades(game) {
  if (grenadeHooked.has(game)) return;
  grenadeHooked.add(game);
  game.events.on('weapon:grenade', (e) => {
    const pos = e && e.pos;
    if (!pos) return;
    for (const z of game.zombies.alive) {
      if (z.type !== 'forecaster' || !z.flags.cloud) continue;
      cloudWorldCenter(z, _a);
      const d = _a.distanceTo(pos);
      if (d <= 5) hitCloud(game, z, (300 + 60 * (game.rounds ? game.rounds.round : 1)) * (1 - d / 5 * 0.6), { point: _a.clone() });
    }
  });
}

export default {
  id: 'forecaster',
  height: 1.8,
  radius: 0.38,
  dmg: JAB.dmg,
  range: JAB.range,
  windup: JAB.windup,
  cd: JAB.cd,
  spawnMode: 'screen',
  points: { killBonus: T.points.forecaster },

  hp(round) {
    return Math.round(F.hpMul * hpAt(Math.max(1, round)) + F.hpAdd);
  },

  speed() {
    return F.strafe;
  },

  build(game, z) {
    const m = acquire(game);
    resetModel(m);
    z.model = m;
    z.group = m.group;
    z.rig = m.rig;
    z.animator = m.animator;
    z.head = m.head;
    z.headR = m.headR;
    z.height = m.rig.dims ? m.rig.dims.height : 1.8;
    z.scale = 0.97 + Math.random() * 0.06;
    z.hitZones = humanoidHitZones({ rig: m.rig, head: m.head, headR: m.headR });
    const f = z.flags;
    f.mode = 'strafe';
    f.mt = 0;
    f.t = Math.random() * 10;
    f.side = Math.random() < 0.5 ? -1 : 1;
    f.sideT = 1.5 + Math.random() * 1.5;
    f.blockT = 0;
    f.los = false;
    f.losT = Math.random() * 0.25;
    f.castT = 2.2 + Math.random() * 1.2;
    f.humT = 2 + Math.random() * 4;
    f.sobbed = false;
    f.game = game;
    f.rod = 0.38;
    const round = Math.max(1, (game.rounds && game.rounds.round) || 1);
    f.cloud = { state: 'home', hp: F.cloudHp[0] + F.cloudHp[1] * round, pos: new THREE.Vector3(), t: 0, dark: 0, yaw: z.yaw, punch: 0 };
    m.animator.override = makeOverride(z);
    if (m.cloud) {
      // detach the cloud into the world; it follows on a spring
      const piv = m.cloud.pivot;
      piv.removeFromParent();
      game.scene.add(piv);
      piv.visible = false;
      f.cloud.pos.set(z.pos.x, z.pos.y + m.cloud.restY, z.pos.z);
      f.cloudInit = false;
    }
    registerCloud(game, z);
    hookGrenades(game);
  },

  release(game, z) {
    const m = z.model;
    if (!m) return;
    unregisterCloud(game, z);
    m.group.removeFromParent();
    resetModel(m);
    if ((m.gen || 0) === (charRuntime.charOpt ? charRuntime.charOpt.gen || 0 : 0) && pool.length < 6) pool.push(m);
    z.model = null;
  },

  update(game, z, dt) {
    if (!z.flags.cloudInit && z.model && z.model.cloud) { z.flags.cloudInit = true; hoverTarget(z, z.flags.cloud.pos); }
    return updateForecaster(game, z, dt);
  },

  updateEntry(game, z, dt) {
    const f = z.flags;
    if (!f.cloudInit && z.model && z.model.cloud) { f.cloudInit = true; hoverTarget(z, f.cloud.pos); }
    tickCloud(game, z, dt);
  },

  onDamage(game, z, amount) {
    return z.flags.sobbed ? amount * F.sobMul : amount;
  },

  onDeath(game, z) {
    if (z.entry && z.entry.kind === 'screen' && z.entry.phase === 'tele') {
      unregisterCloud(game, z);
      if (z.model && z.model.cloud) z.model.cloud.pivot.visible = false;
      return undefined;
    }
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
      const m = pool[0];
      out.push(m.group);
      if (!m.umbrella) m.umbrella = buildUmbrella(game);
      const u = cloneBare(m.umbrella);
      const disc = m.disc.clone(); disc.visible = true;
      const rb = m.rainbow.clone(); rb.visible = true;
      const bolt = new THREE.Mesh(boltGeometry(new THREE.Vector3(0, 3, 0), new THREE.Vector3(0, 0, 0)), boltMat);
      const glow = new THREE.Mesh(bolt.geometry, glowMat);
      if (m.cloud && m.cloud.shellG) m.cloud.shellG.visible = true;
      out.push(u, disc, rb, bolt, glow);
    } catch (err) { console.warn('[forecaster] warmup', err); }
    return out;
  },

  // ---- debug / EE helpers
  popCloud(game, z) { return popCloud(game, z); },
  castNow(game, z) { if (!z || z.dead) return false; z.flags.castT = 0; z.flags.los = true; return true; },
  cloudOf(z) { const c = z && z.flags && z.flags.cloud; return c ? { state: c.state, hp: c.hp, pos: z.model && z.model.cloud ? cloudWorldCenter(z, new THREE.Vector3()) : null } : null; },
};
