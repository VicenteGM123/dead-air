// DEAD AIR — perks: the 5 sponsors' effects, costumes and INSTANT REPLAY (ARCHITECTURE §10, GDD §4 costume slots, §11,
// §14 "costume = perk display", §18.9). Owned by the sponsors agent (with src/game/sponsors.js, src/ui/commercial.js).
//
// API (game.perks)
//   list (owned perk ids, purchase order) · max (T.perks.limit = 4; Infinity after the Morning Show) · gold (bool)
//   has(id) · give(id, { pop = true, emit = true, costume = true }) -> bool   (debug.perk(id) = give: instant, no commercial)
//   remove(id, { poof = true }) -> bool (alias lose(id))   emits perk:lose {perkId}
//   onLethal() -> bool   called by player.hurt at 0 HP: with Replay-Ade (or the gold one, once per round) it plays
//                        INSTANT REPLAY and returns true; otherwise false (the player dies)
//   attachCostume(id, { pop }) / detachCostume(id, { poof })   costume pieces on the hero slots (sponsors.js pops it
//                        during the commercial's star wipe, then calls give(id, { costume:false, pop:false }))
//   setGold(on) · morningShow()  (Sign-Off reward: every sponsor free + permanent, gold-leaf costumes, no limit, the
//                        gold Replay-Ade triggers once per round and is never consumed)
//   replayActive (bool) · debugReplay() (forces an Instant Replay now, owned or not) · warmup() (precompile samples)
// EFFECTS (exact, GDD §11) are written into game.player.mods (composable: multiplicative mods are divided back out on loss):
//   wobble_up      maxHealth 300 (T.player.hpWobble), knockback ×0.5, noFlinch (hit flinch replaced by a damped jelly
//                  squash-stretch of the whole hero + helmet, "bwoing" by audio.js), faint green jelly rim light on the
//                  hero materials. Tube-grenade self-damage ×0.5 is applied by weapons.js (perks.has).
//   jump_cut       reloadSpeed ×0.5 and swapSpeed ×0.5 (time multipliers), throwSpeed 1.3 (weapons.js also reads has()).
//   roller_boogie  unlimitedSprint (+ unlimitedStamina alias), moveSpeed/sprintSpeed ×1.08 (4.97 / 7.34 m/s),
//                  sprintToFire 0.10, reloadWhileSprinting; the sprint becomes skating strides (push and glide, the
//                  hero rides 0.118 m higher on the wheels) with a faint sparkle trail and the skate_roll loop.
//   double_vision  fireRate ×1.2, ghostBullets (weapons.js does the +50 % ghost image, doubled tracers, the cyan/magenta
//                  gun fringe and the Zapper chain), a smile "ting" + glint on the toothbrush every 6 s.
//   replay_ade     INSTANT REPLAY (below). At most 3 purchases per game (sponsors.js counts purchases, sold-out set).
// INSTANT REPLAY: 0.3 s world pause + the sports-replay "13" wipe (commercial.js) and the HUD "◀◀" bug (replay:start /
//   replay:end); the hero rewinds along player.history (newest -> the oldest walkable sample, up to 4 s) at 4× (1.0 s)
//   with cyan afterimage ghosts, VHS tracking lines, health rewinding 0 -> full, while the world runs at time.scale 0.1;
//   lands at full HP with a shockwave (zombies within 5 m knocked back 3 m + stunned 2 s), invulnerable from the trigger
//   until 2 s after landing; Replay-Ade is consumed (wristbands vanish in a puff, the whistle drops and bounces) unless
//   gold. Emits player:revive {selfRevive:true} and perk:lose {perkId:'replay_ade'}. Carried EE items are untouched.
//   TEMPORARY STATE: the replay's VHS look is a render fx layer (render.setFx('replay', ...) refreshed every frame with
//   a short ttl), never a write to render.post; time.scale is restored only while it still holds the value the replay
//   wrote. _endReplay() is the ONE cleanup path (fx layer, time.scale, overlay, ghosts, control, replay:end) and runs
//   on landing, reset, menu/game over/victory, an exception inside the replay and a stuck-replay watchdog.
// Also exported: PERK_IDS, COSTUMES, Sparkles (a tiny real-dt particle pool: world FX freeze at time.scale 0),
//   cloneHero(hero, skip) / copyPose(hero, ghost) (frozen pose copies for ghosts and duplicates).

import * as THREE from 'three';
import { T, PAL } from '../core/config.js';
import { buildProp } from '../props/index.js';
import { getOverlay } from '../ui/commercial.js';

export const PERK_IDS = ['replay_ade', 'wobble_up', 'jump_cut', 'roller_boogie', 'double_vision'];
export const COSTUMES = {
  replay_ade: 'costume_wristbands', wobble_up: 'costume_jelly_helmet', jump_cut: 'costume_oven_mitt',
  roller_boogie: 'costume_skates', double_vision: 'costume_toothbrush',
};
const TP = T.perks;
const SKATE_LIFT = 0.118;
const REWIND_SCALE = 0.1;            // world speed during the rewind (only the replay ever uses it)
const REPLAY_FX = 'replay';          // render fx layer owner
const REPLAY_FX_TTL = 0.25;          // s: the layer drops by itself if the replay stops refreshing it
const REPLAY_WATCHDOG = 6;           // s: a replay still running after this (no debug hold) is force-finished
const JELLY_RIM = new THREE.Color('#6CFF8A');
const TAU = Math.PI * 2;
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const easeOutBack = (x, k = 2.2) => 1 + (k + 1) * (x - 1) ** 3 + k * (x - 1) ** 2;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _m = new THREE.Matrix4();
const _s = new THREE.Vector3();
const _c = new THREE.Color();
const _q2 = new THREE.Quaternion();

// ============================================================================================ Sparkles
// Real-dt particle pool (camera-facing quads): 'star' (additive glow stars) and 'puff' (soft discs). Used by the
// commercial gags (the world is frozen there, so fx.js particles would not move) and the costume pops.
function starTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const x = c.getContext('2d');
  const g = x.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.18, 'rgba(255,255,255,0.85)'); g.addColorStop(0.45, 'rgba(255,255,255,0.12)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = g; x.fillRect(0, 0, 64, 64);
  x.fillStyle = 'rgba(255,255,255,0.95)';
  x.beginPath();
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * TAU - Math.PI / 2, r = i % 2 ? 5 : 31;
    const px = 32 + Math.cos(a) * r, py = 32 + Math.sin(a) * r;
    if (i) x.lineTo(px, py); else x.moveTo(px, py);
  }
  x.closePath(); x.fill();
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
function puffTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const x = c.getContext('2d');
  const g = x.createRadialGradient(28, 26, 2, 32, 32, 31);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.6, 'rgba(240,236,228,0.9)'); g.addColorStop(0.85, 'rgba(220,214,204,0.5)'); g.addColorStop(1, 'rgba(220,214,204,0)');
  x.fillStyle = g; x.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

class Pool {
  constructor(scene, mat, cap) {
    this.cap = cap;
    this.n = 0;
    this.mesh = new THREE.InstancedMesh(new THREE.PlaneGeometry(1, 1), mat, cap);
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = this.mesh.receiveShadow = false;
    this.mesh.count = 0;
    this.mesh.visible = false;
    this.mesh.renderOrder = 5;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.setColorAt(0, _c.set('#ffffff'));
    this.p = new Float32Array(cap * 3); this.v = new Float32Array(cap * 3);
    this.life = new Float32Array(cap); this.age = new Float32Array(cap); this.size = new Float32Array(cap);
    this.grav = new Float32Array(cap); this.drag = new Float32Array(cap); this.spin = new Float32Array(cap);
    this.grow = new Float32Array(cap);
    this.col = Array.from({ length: cap }, () => new THREE.Color());
    scene.add(this.mesh);
  }
  add(x, y, z, vx, vy, vz, life, size, grav, drag, color, spin, grow) {
    let i = this.n < this.cap ? this.n++ : Math.floor(Math.random() * this.cap);
    this.p[i * 3] = x; this.p[i * 3 + 1] = y; this.p[i * 3 + 2] = z;
    this.v[i * 3] = vx; this.v[i * 3 + 1] = vy; this.v[i * 3 + 2] = vz;
    this.life[i] = life; this.age[i] = 0; this.size[i] = size; this.grav[i] = grav; this.drag[i] = drag;
    this.col[i].set(color); this.spin[i] = spin; this.grow[i] = grow;
  }
  update(dt, cam, additive) {
    if (!this.n) { if (this.mesh.visible) { this.mesh.visible = false; this.mesh.count = 0; } return; }
    const q = cam.quaternion;
    for (let i = 0; i < this.n; i++) {
      this.age[i] += dt;
      if (this.age[i] >= this.life[i]) {
        const j = --this.n;
        if (i !== j) {
          for (let k = 0; k < 3; k++) { this.p[i * 3 + k] = this.p[j * 3 + k]; this.v[i * 3 + k] = this.v[j * 3 + k]; }
          this.life[i] = this.life[j]; this.age[i] = this.age[j]; this.size[i] = this.size[j]; this.grav[i] = this.grav[j];
          this.drag[i] = this.drag[j]; this.col[i].copy(this.col[j]); this.spin[i] = this.spin[j]; this.grow[i] = this.grow[j];
        }
        i--;
        continue;
      }
      const d = Math.exp(-this.drag[i] * dt);
      this.v[i * 3] *= d; this.v[i * 3 + 1] = this.v[i * 3 + 1] * d - this.grav[i] * dt; this.v[i * 3 + 2] *= d;
      this.p[i * 3] += this.v[i * 3] * dt; this.p[i * 3 + 1] += this.v[i * 3 + 1] * dt; this.p[i * 3 + 2] += this.v[i * 3 + 2] * dt;
    }
    for (let i = 0; i < this.n; i++) {
      const k = this.age[i] / this.life[i];
      const fade = additive ? (1 - k) * Math.min(1, k * 8 + 0.3) : 1;
      const s = this.size[i] * (additive ? (0.6 + 0.4 * Math.sin(Math.min(1, k * 3) * Math.PI * 0.5)) * (1 - k * 0.3) : (1 + this.grow[i] * k) * (1 - smooth(0.6, 1, k)));
      _q.copy(q);
      if (this.spin[i]) _q.multiply(_q2.setFromAxisAngle(_w.set(0, 0, 1), this.spin[i] * this.age[i]));
      _m.compose(_v.set(this.p[i * 3], this.p[i * 3 + 1], this.p[i * 3 + 2]), _q, _s.set(s, s, s));
      this.mesh.setMatrixAt(i, _m);
      _c.copy(this.col[i]).multiplyScalar(fade);
      this.mesh.setColorAt(i, _c);
    }
    this.mesh.count = this.n;
    this.mesh.visible = true;
    this.mesh.instanceMatrix.needsUpdate = true;
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
  }
  clear() { this.n = 0; this.mesh.count = 0; this.mesh.visible = false; }
}

export class Sparkles {
  constructor(game, cap = 180) {
    const star = new THREE.MeshBasicMaterial({ map: starTexture(), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false, toneMapped: false });
    const puff = new THREE.MeshBasicMaterial({ map: puffTexture(), transparent: true, depthWrite: false, fog: false });
    this.star = new Pool(game.scene, star, cap);
    this.puff = new Pool(game.scene, puff, Math.round(cap / 2));
  }
  // o: { count, color|colors, speed, size, life, gravity, drag, kind:'star'|'puff', dir:Vector3, cone (0..1), spread (m), spin, grow }
  emit(pos, o = {}) {
    const pool = o.kind === 'puff' ? this.puff : this.star;
    const n = o.count ?? 8, cols = o.colors || [o.color || '#FFE27A'];
    for (let i = 0; i < n; i++) {
      let dx = Math.random() * 2 - 1, dy = Math.random() * 2 - 1, dz = Math.random() * 2 - 1;
      const L = Math.hypot(dx, dy, dz) || 1; dx /= L; dy /= L; dz /= L;
      if (o.dir) {
        const c = o.cone ?? 0.4;
        dx = o.dir.x + dx * c; dy = o.dir.y + dy * c; dz = o.dir.z + dz * c;
        const L2 = Math.hypot(dx, dy, dz) || 1; dx /= L2; dy /= L2; dz /= L2;
      }
      const sp = (o.speed ?? 2) * (0.5 + Math.random() * 0.7);
      const sr = o.spread ?? 0;
      pool.add(pos.x + (Math.random() - 0.5) * sr, pos.y + (Math.random() - 0.5) * sr, pos.z + (Math.random() - 0.5) * sr,
        dx * sp, dy * sp, dz * sp, (o.life ?? 0.7) * (0.7 + Math.random() * 0.6), (o.size ?? 0.12) * (0.7 + Math.random() * 0.6),
        o.gravity ?? 1.5, o.drag ?? 2.2, cols[i % cols.length], o.spin ?? (Math.random() - 0.5) * 6, o.grow ?? 1.2);
    }
  }
  update(dt, cam) { this.star.update(dt, cam, true); this.puff.update(dt, cam, false); }
  clear() { this.star.clear(); this.puff.clear(); }
}

// ============================================================================================ hero clones
function parallel(a, b, fn) {
  fn(a, b);
  for (let i = 0; i < a.children.length; i++) parallel(a.children[i], b.children[i], fn);
}

// A geometry sharing the source's attributes minus its morph targets (ghost materials need no face morphs; the
// baked body's colour morphs also break the stock Lambert/Basic morph path).
const _shells = new WeakMap();
function staticShell(geo) {
  let g = _shells.get(geo);
  if (g) return g;
  g = new THREE.BufferGeometry();
  for (const [k, v] of Object.entries(geo.attributes)) g.setAttribute(k, v);
  g.setIndex(geo.index);
  for (const gr of geo.groups) g.addGroup(gr.start, gr.count, gr.materialIndex);
  g.boundingSphere = geo.boundingSphere ? geo.boundingSphere.clone() : null;
  g.boundingBox = geo.boundingBox ? geo.boundingBox.clone() : null;
  _shells.set(geo, g);
  return g;
}

// Frozen copy of the hero model (own joints, skinned meshes rebound to them). skip: objects left out (held weapon).
// Returns { group, root, joints{name->Object3D}, meshes[] } with the source materials (swap them yourself).
export function cloneHero(hero, skip = []) {
  const src = hero.group;
  const stash = [];
  const detached = [];
  for (const s of skip) if (s && s.parent) { detached.push([s, s.parent]); s.parent.remove(s); }
  src.traverse((o) => { stash.push([o, o.userData]); o.userData = {}; });
  let group, map;
  try {
    group = src.clone(true);
    map = new Map();
    parallel(src, group, (a, b) => map.set(a, b));
  } finally {
    for (const [o, u] of stash) o.userData = u;
    for (const [s, p] of detached) p.add(s);
  }
  const meshes = [];
  for (const [a, b] of map) {
    if (b.isSkinnedMesh && a.skeleton) {
      b.skeleton = a.skeleton.clone();
      b.bindMatrix.copy(a.bindMatrix);
      b.skeleton.bones = a.skeleton.bones.map((bone) => map.get(bone) || bone);
      b.bind(b.skeleton, b.bindMatrix);
    }
    if (b.isMesh) {
      b.castShadow = false; b.receiveShadow = false; b.frustumCulled = false; b.layers.set(0);
      if (b.geometry && b.geometry.morphAttributes && Object.keys(b.geometry.morphAttributes).length) {
        b.geometry = staticShell(b.geometry);
        b.morphTargetInfluences = undefined;
        b.morphTargetDictionary = undefined;
      }
      meshes.push(b);
    }
  }
  const joints = {};
  for (const [name, j] of Object.entries(hero.rig.joints)) joints[name] = map.get(j);
  return { group, root: map.get(hero.rig.root), joints, meshes, hero };
}

export function copyPose(hero, ghost) {
  const J = hero.rig.joints;
  for (const n in ghost.joints) {
    const a = J[n], b = ghost.joints[n];
    if (!a || !b) continue;
    b.position.copy(a.position); b.quaternion.copy(a.quaternion); b.scale.copy(a.scale);
  }
  const r = hero.rig.root;
  ghost.root.position.copy(r.position); ghost.root.quaternion.copy(r.quaternion); ghost.root.scale.copy(r.scale);
  ghost.group.position.copy(hero.group.position); ghost.group.scale.copy(hero.group.scale); ghost.group.quaternion.copy(hero.group.quaternion);
}

// ============================================================================================ Perks
export class Perks {
  constructor(game) {
    this.game = game;
    this.list = [];
    this.max = TP.limit;
    this.gold = false;
    this.replayActive = false;
    this._costumes = new Map();      // perkId -> { pieces:[{obj, slot, scale}], gold }
    this._applied = { move: 1, sprint: 1, fire: 1, reload: 1, swap: 1, knock: 1 };
    this._rim = new Map();           // material -> { color, strength }
    this._rimHero = null;
    this._jelly = { x: 0, v: 0 };
    this._skate = { w: 0, phase: 0, sparkT: 0, loop: null };
    this._wrapped = new WeakSet();
    this._ting = 3;
    this._pops = [];                 // costume pop animations { obj, base, t }
    this._whistles = [];
    this._rings = [];
    this._ghosts = [];               // replay afterimages (pool)
    this._ghostHero = null;
    this._invulnT = 0;
    this._goldReplayRound = -1;
    this._scaleSet = null;           // the time.scale value the replay wrote last (null: it holds none)
    this._fxKnobs = { roll: 0, chroma: 0, scanlines: 0, saturation: 1 };   // the replay's render fx layer
    this.sparkles = null;
    this.debugHoldAt = null;
  }

  init() {
    const g = this.game, ev = g.events;
    this.sparkles = new Sparkles(g);
    ev.on('player:hurt', () => this._onHurt());
    ev.on('player:land', (p) => { if (this.has('wobble_up')) this._jelly.v -= Math.min(4, (p?.speed ?? 6) * 0.35); });
    ev.on('player:jump', () => { if (this.has('wobble_up')) this._jelly.v += 1.6; });
    ev.on('state', (e) => { if (e && (e.to === 'menu' || e.to === 'gameover' || e.to === 'victory')) this._endReplay(true); });
  }

  reset() {
    this._endReplay(true);
    for (const id of [...this._costumes.keys()]) this.detachCostume(id, { poof: false });
    this._restoreRim();
    this.list.length = 0;
    this.max = TP.limit;
    this.gold = false;
    this._goldReplayRound = -1;
    this._applied = { move: 1, sprint: 1, fire: 1, reload: 1, swap: 1, knock: 1 };
    this._jelly.x = this._jelly.v = 0;
    this._skate.w = 0;
    this._skateLoop(false);
    this._ting = 3;
    this._pops.length = 0;
    for (const w of this._whistles) w.obj.parent?.remove(w.obj);
    this._whistles.length = 0;
    for (const r of this._rings) r.mesh.parent?.remove(r.mesh);
    this._rings.length = 0;
    this._invulnT = 0;
    this.sparkles?.clear();
    const hero = this.game.player?.hero;
    if (hero) { hero.group.position.y = 0; hero.group.scale.set(1, 1, 1); }
  }

  // ------------------------------------------------------------------------------------------ ownership
  has(perkId) {
    return this.list.includes(perkId);
  }

  give(perkId, { pop = true, emit = true, costume = true } = {}) {
    if (!PERK_IDS.includes(perkId) || this.has(perkId) || this.list.length >= this.max) return false;
    this.list.push(perkId);
    if (costume && !this._costumes.has(perkId)) this.attachCostume(perkId, { pop });
    this._applyMods();
    if (perkId === 'wobble_up') this._tintRim(true);
    if (emit) this.game.events.emit('perk:gain', { perkId });
    return true;
  }

  remove(perkId, { poof = true } = {}) {
    const i = this.list.indexOf(perkId);
    if (i < 0) return false;
    this.list.splice(i, 1);
    this.detachCostume(perkId, { poof });
    this._applyMods();
    if (perkId === 'wobble_up') this._restoreRim();
    if (perkId === 'roller_boogie') this._skateLoop(false);
    this.game.events.emit('perk:lose', { perkId });
    return true;
  }

  lose(perkId) { return this.remove(perkId); }

  // Sign-Off reward (GDD §13 Morning Show): all five, gold leaf, permanent, no limit.
  morningShow() {
    this.max = Infinity;
    this.setGold(true);
    for (const id of PERK_IDS) this.give(id, { pop: true });
    return this.list.slice();
  }

  setGold(on) {
    this.gold = !!on;
    for (const id of [...this._costumes.keys()]) {
      this.detachCostume(id, { poof: false });
      this.attachCostume(id, { pop: true });
    }
  }

  // ------------------------------------------------------------------------------------------ player.mods
  _applyMods() {
    const p = this.game.player;
    if (!p || !p.mods) return;
    const m = p.mods, A = this._applied;
    const has = (id) => this.has(id);
    const mul = (key, field, want) => {
      const cur = Number.isFinite(m[field]) && m[field] > 0 ? m[field] : 1;
      m[field] = (cur / A[key]) * want;
      A[key] = want;
    };
    const roller = has('roller_boogie'), jump = has('jump_cut'), dv = has('double_vision'), wob = has('wobble_up');
    mul('move', 'moveSpeed', roller ? TP.roller.speedMul : 1);
    mul('sprint', 'sprintSpeed', roller ? TP.roller.speedMul : 1);
    mul('fire', 'fireRate', dv ? TP.doubleVision.fireRate : 1);
    mul('reload', 'reloadSpeed', jump ? TP.jumpCut.reload : 1);
    mul('swap', 'swapSpeed', jump ? TP.jumpCut.swap : 1);
    mul('knock', 'knockback', wob ? 0.5 : 1);
    const newMax = wob ? T.player.hpWobble : T.player.hp, oldMax = m.maxHealth || T.player.hp;
    m.maxHealth = newMax;
    // the extra jelly HP comes filled (no 'signal loss' flash when you buy it); losing it clamps
    if (newMax > oldMax && p.alive) { p.maxHealth = newMax; p.health = Math.min(newMax, p.health + (newMax - oldMax)); }
    m.noFlinch = wob;
    m.unlimitedSprint = roller;
    m.unlimitedStamina = roller;
    m.reloadWhileSprinting = roller;
    m.sprintToFire = roller ? TP.roller.sprintToFire : T.player.sprintToFire;
    m.ghostBullets = dv;
    m.ghostMul = dv ? TP.doubleVision.ghost : 0;
    m.throwSpeed = jump ? 1.3 : 1;
    if (roller) p.stamina = T.player.stamina;
  }

  // ------------------------------------------------------------------------------------------ costumes
  _slotFit(perkId, slot, hero) {
    if (perkId === 'wobble_up' && slot === 'head') {
      const hb = Number.isFinite(hero.hairBounds) && hero.hairBounds > 0 ? hero.hairBounds : 0.27;
      return THREE.MathUtils.clamp(((hb * 1.05) / 0.25) * 0.82, 0.95, 1.45);
    }
    if (perkId === 'replay_ade' && slot === 'neck') return 1.4;     // the lanyard + whistle sit outside the collar
    return 1;
  }

  attachCostume(perkId, { pop = true } = {}) {
    const g = this.game, hero = g.player?.hero;
    if (!hero || !COSTUMES[perkId]) return false;
    if (this._costumes.has(perkId)) this.detachCostume(perkId, { poof: false });
    let prop;
    try {
      prop = buildProp(COSTUMES[perkId] + (this.gold ? '_gold' : ''), g, {});
    } catch (err) {
      console.warn('[perks] costume build failed', perkId, err);
      return false;
    }
    const parts = prop.userData.parts || {};
    const pieces = [];
    for (const [slot, obj] of Object.entries(parts)) {
      const target = hero.slots?.[slot];
      if (!target || !obj || !obj.isObject3D) continue;
      obj.parent?.remove(obj);
      obj.position.set(0, slot === 'head' ? -0.045 : 0, slot === 'neck' ? -0.035 : 0);   // helmet onto the hair, lanyard out of the shirt
      obj.rotation.set(0, 0, 0);
      const s = this._slotFit(perkId, slot, hero);
      obj.scale.setScalar(s);
      g.mats.applyHeroFade?.(obj);
      obj.traverse((o) => { if (o.isMesh) { o.receiveShadow = false; o.userData.costume = perkId; } });
      target.add(obj);
      pieces.push({ obj, slot, scale: s });
      if (pop) {
        this._pops.push({ obj, base: s, t: 0 });
        obj.scale.setScalar(0.001);
      }
    }
    if (perkId === 'roller_boogie') hero.group.position.y = SKATE_LIFT;
    this._costumes.set(perkId, { pieces, gold: this.gold });
    if (pop) {
      for (const pc of pieces) {
        pc.obj.updateWorldMatrix(true, false);
        pc.obj.getWorldPosition(_v);
        this.sparkles?.emit(_v, { count: 14, colors: ['#FFE27A', '#FFFFFF', '#FF9EDB', '#7FE7FF'], speed: 2.4, size: 0.13, life: 0.7, gravity: 0.8 });
      }
    }
    return true;
  }

  detachCostume(perkId, { poof = true } = {}) {
    const c = this._costumes.get(perkId);
    if (!c) return false;
    this._costumes.delete(perkId);
    const g = this.game;
    for (const pc of c.pieces) {
      if (poof && pc.obj.parent) {
        pc.obj.updateWorldMatrix(true, false);
        pc.obj.getWorldPosition(_v);
        const cols = perkId === 'replay_ade' ? ['#F4C81E', '#2F5BD3', '#FFFFFF'] : ['#F4F1E8', '#FFE27A'];
        g.fx?.burst?.(_v, { shape: 'puff', count: 6, colors: cols, speed: 1.4, size: 0.1, life: 0.5 });
        this.sparkles?.emit(_v, { kind: 'puff', count: 5, colors: cols, speed: 1.2, size: 0.12, life: 0.45, gravity: -0.5 });
      }
      pc.obj.parent?.remove(pc.obj);
      const i = this._pops.findIndex((p) => p.obj === pc.obj);
      if (i >= 0) this._pops.splice(i, 1);
    }
    if (perkId === 'roller_boogie' && g.player?.hero) g.player.hero.group.position.y = 0;
    return true;
  }

  // Wobble-Up: a faint green jelly rim on every hero material (restored on loss / new game).
  _tintRim(on) {
    const hero = this.game.player?.hero;
    if (!on || !hero) return;
    this._restoreRim();
    this._rimHero = hero;
    hero.group.traverse((o) => {
      if (!o.isMesh || o.userData.costume) return;
      for (const mat of [].concat(o.material)) {
        const u = mat?.userData?.uniforms;
        if (!u || !u.uRimColor || this._rim.has(mat)) continue;
        this._rim.set(mat, { color: u.uRimColor.value.clone(), strength: u.uRimStrength ? u.uRimStrength.value : null });
        u.uRimColor.value.lerp(JELLY_RIM, 0.42);
      }
    });
  }

  _restoreRim() {
    for (const [mat, s] of this._rim) {
      const u = mat.userData.uniforms;
      u.uRimColor.value.copy(s.color);
      if (u.uRimStrength && s.strength !== null) u.uRimStrength.value = s.strength;
    }
    this._rim.clear();
    this._rimHero = null;
  }

  // ------------------------------------------------------------------------------------------ hits
  _onHurt() {
    const p = this.game.player;
    if (!this.has('wobble_up') || !p) return;
    p.anim.hurt = 0;                 // no hit flinch: the jelly wobble replaces it
    this._jelly.v -= 5.5;
  }

  // ------------------------------------------------------------------------------------------ lethal
  onLethal() {
    if (this.replayActive) return true;
    const g = this.game, round = g.rounds?.round ?? 0;
    const goldOk = this.gold && this.has('replay_ade') && this._goldReplayRound !== round;
    if (!this.has('replay_ade') && !goldOk) return false;
    if (this.gold) this._goldReplayRound = round;
    this._startReplay(!this.gold);
    return true;
  }

  // Tests: freeze the replay at t seconds into phase ('pause' | 'rewind' | 'land'); null releases it.
  debugHold(phase, t) { this.debugHoldAt = phase ? { phase, t } : null; return this._rp ? { phase: this._rp.phase, t: this._rp.t } : null; }

  debugReplay() {
    if (this.replayActive) return false;
    this._startReplay(this.has('replay_ade') && !this.gold);
    return true;
  }

  _startReplay(consume) {
    const g = this.game, p = g.player;
    const R = TP.replay;
    // path: current position, then history samples newest -> the oldest walkable one (<= 4 s)
    const pts = [{ x: p.pos.x, y: p.pos.y, z: p.pos.z, yaw: p.yaw }];
    const h = p.history;
    const n = Math.min(h?.count ?? 0, Math.round(R.rewind / 0.1));
    let target = -1;
    const valid = (s) => {
      if (!s) return false;
      if (g.nav?.walkable && !g.nav.walkable(s.x, s.z)) return false;
      const boss = g.boss;
      if (boss && boss.active && typeof boss.inArena === 'function' && !boss.inArena(s.x, s.z)) return false;
      return true;
    };
    for (let i = n - 1; i >= 0; i--) if (valid(h.get(i))) { target = i; break; }
    for (let i = 0; i <= target; i++) { const s = h.get(i); pts.push({ x: s.x, y: s.y, z: s.z, yaw: s.yaw }); }
    const steps = Math.max(1, pts.length - 1);
    // Nothing of render.post is snapshotted: the replay's look is its own fx layer (render.setFx), so ending it can
    // never write back somebody else's transient (the HUD's hurt pulse made the vertical roll stick forever).
    const s0 = g.time.scale;
    this._rp = {
      t: 0, age: 0, phase: 'pause', consume, pts, landed: false,
      dur: Math.max(0.6, (steps * 0.1) / R.speed),
      prev: new THREE.Vector3().copy(p.pos), ghostT: 0, yaw: p.yaw,
      scale0: s0 > 0 && s0 !== REWIND_SCALE ? s0 : 1,     // world speed to resume at landing
      health0: Math.max(0, p.health),
    };
    this.replayActive = true;
    p.invulnerable = true;
    p.controlLocked = true;
    p.vel.set(0, 0, 0);
    this._setScale(0);
    this._replayFx(1, 0, 0, 0);
    g.events.emit('replay:start', {});
    g.audio?.play?.('replay_wipe');
    g.cam?.shake?.(0.25, 0.3);
    this._ensureGhosts();
  }

  // time.scale writes of the replay are remembered, so the replay only ever restores a value it still owns.
  _setScale(v) {
    this.game.time.scale = v;
    this._scaleSet = v;
  }

  _restoreScale(to) {
    const g = this.game;
    if (this._scaleSet !== null && g.time.scale === this._scaleSet) g.time.scale = to > 0 ? to : 1;
    this._scaleSet = null;
  }

  // The replay's VHS look as a render fx layer, refreshed every frame (short ttl: it drops by itself if the replay
  // ever stops refreshing it). saturation multiplies render.post.saturation; the others combine with max().
  _replayFx(sat, roll, chroma, scanlines) {
    const r = this.game.render;
    if (!r?.setFx) return;
    const k = this._fxKnobs;
    k.saturation = sat; k.roll = roll; k.chroma = chroma; k.scanlines = scanlines;
    r.setFx(REPLAY_FX, k, { ttl: REPLAY_FX_TTL });
  }

  _updateReplay(rdt) {
    const rp = this._rp;
    if (!rp) { this._endReplay(false); return; }
    try {
      rp.age += rdt;
      if (!this.debugHoldAt && rp.age > REPLAY_WATCHDOG) {
        console.warn('[perks] Instant Replay watchdog: force-finished after', rp.age.toFixed(1), 's in', rp.phase);
        this._finishReplay();
        return;
      }
      this._stepReplay(rdt);
    } catch (err) {
      console.error('[perks] Instant Replay failed, finishing it', err);
      this._finishReplay();
    }
  }

  _stepReplay(rdt) {
    const g = this.game, p = g.player, rp = this._rp;
    rp.t += rdt;
    const H = this.debugHoldAt;
    if (H && H.phase === rp.phase && rp.t > H.t) rp.t = H.t;
    const ov = getOverlay();
    if (rp.phase === 'pause') {
      const k = rp.t / 0.3;
      ov.draw({ mode: 'replay', t: rp.t, wipe: clamp01(k), tracking: smooth(0.5, 1, k) * 0.6, flash: rp.t < 0.05 ? 0.5 : 0 });
      this._replayFx(1 - 0.35 * smooth(0, 0.3, rp.t), 0, 0, 0);
      if (rp.t >= 0.3) {
        rp.phase = 'rewind';
        rp.t = 0;
        this._setScale(REWIND_SCALE);
        g.audio?.play?.('replay_rewind');
      }
      return;
    }
    if (rp.phase === 'rewind') {
      const u = clamp01(rp.t / rp.dur);
      const e = u < 0.5 ? 2 * u * u : 1 - (-2 * u + 2) ** 2 / 2;
      const f = e * (rp.pts.length - 1);
      const i = Math.min(rp.pts.length - 2, Math.floor(f)), k = f - i;
      const a = rp.pts[i], b = rp.pts[Math.min(rp.pts.length - 1, i + 1)];
      p.pos.set(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k);
      rp.yaw += wrap(a.yaw + wrap(b.yaw - a.yaw) * k - rp.yaw) * (1 - Math.exp(-rdt * 10));
      p.yaw = rp.yaw;
      if (rdt > 0) p.vel.subVectors(p.pos, rp.prev).divideScalar(rdt).clampLength(0, 14);
      p.vel.y = 0;
      rp.prev.copy(p.pos);
      p.model.position.copy(p.pos);
      p.grounded = true;
      p.health = rp.health0 + (p.maxHealth - rp.health0) * smooth(0, 0.55, u);   // the damage rewinds too
      p.area = g.level.areaAt(p.pos.x, p.pos.z) || p.area;
      rp.ghostT -= rdt;
      if (rp.ghostT <= 0) { rp.ghostT = 0.085; this._spawnGhost(); }
      this._replayFx(0.72, 0.16 * (1 - u), 2.6, 0.7);
      ov.draw({ mode: 'replay', t: rp.t, wipe: -1, tracking: 0.75 + 0.25 * Math.sin(rp.t * 17) });
      if (u >= 1) this._landReplay();
      return;
    }
    if (rp.phase === 'land') {
      const k = rp.t / 0.35;
      ov.draw({ mode: 'replay', t: rp.t, wipe: -1, tracking: 0.4 * (1 - k), flash: 0.75 * (1 - clamp01(k * 1.6)) });
      if (rp.t >= 0.35) this._endReplay(false);
    }
  }

  // Interrupted (exception / watchdog): land now if it has not landed yet (full HP, shockwave, perk consumed),
  // then the normal cleanup.
  _finishReplay() {
    const rp = this._rp;
    if (rp && !rp.landed) {
      try { this._landReplay(); } catch (err) { console.error('[perks] Instant Replay landing failed', err); }
      const p = this.game.player;
      if (p) { p.health = p.maxHealth; p.alive = true; }
    }
    this._endReplay(false);
  }

  _landReplay() {
    const g = this.game, p = g.player, R = TP.replay, rp = this._rp;
    rp.phase = 'land';
    rp.t = 0;
    rp.landed = true;
    this._restoreScale(rp.scale0);
    g.render?.clearFx?.(REPLAY_FX);
    p.vel.set(0, 0, 0);
    p.health = p.maxHealth;
    p.alive = true;
    p.controlLocked = false;
    p.history?.clear?.();
    p.history?.push?.(p.pos, p.yaw, p.area);
    this._invulnT = R.invuln;
    // shockwave: zombies within 5 m knocked back 3 m and stunned 2 s
    const zs = g.zombies?.inRadius ? g.zombies.inRadius(p.pos, R.knock, []) : [];
    for (const z of zs) {
      _v.subVectors(z.pos, p.pos).setY(0);
      if (_v.lengthSq() < 1e-4) _v.set(Math.random() - 0.5, 0, Math.random() - 0.5);
      _v.normalize().multiplyScalar(3);
      g.zombies.knockback?.(z, _v);
      g.zombies.stun?.(z, R.stun);
    }
    this._ring(p.pos, R.knock);
    _v.copy(p.pos).setY(p.pos.y + 1);
    g.fx?.burst?.(_v, { shape: 'star', count: 14, speed: 5, size: 0.16, life: 0.8, colors: ['#FFE27A', '#FFFFFF', '#7FE7FF'] });
    g.fx?.burst?.(p.pos, { shape: 'puff', count: 12, speed: 3.5, size: 0.3, life: 0.7, dir: new THREE.Vector3(0, 0.2, 0), cone: 1 });
    g.cam?.shake?.(0.55, 0.45);
    g.audio?.play?.('studio_flash');
    g.audio?.play?.('crowd_ooh', { vol: 0.6 });
    if (rp.consume && this.has('replay_ade')) {
      this._dropWhistle();
      this.remove('replay_ade', { poof: true });
    }
    g.events.emit('player:revive', { selfRevive: true });
  }

  // THE cleanup path: every temporary state the replay may hold, whatever phase it reached. Idempotent. hard = the
  // run is over (reset / menu / game over / victory): a world speed the replay still holds goes back to 1.
  _endReplay(hard) {
    const g = this.game, rp = this._rp;
    const was = this.replayActive || !!rp;
    this._rp = null;
    this.replayActive = false;
    g.render?.clearFx?.(REPLAY_FX);
    if (hard) { if (this._scaleSet !== null || g.time.scale === REWIND_SCALE) g.time.scale = 1; this._scaleSet = null; }
    else this._restoreScale(rp ? rp.scale0 : 1);
    for (const gh of this._ghosts) { gh.t = -1; gh.group.visible = false; }
    if (!was) return;
    if (g.player) g.player.controlLocked = false;
    if (!g.sponsors?.inCommercial) getOverlay().clear();   // a running commercial redraws its own bezel every frame
    g.events.emit('replay:end', {});
  }

  // Afterimage pool: frozen pose copies of the hero, additive cyan, fading.
  _ensureGhosts() {
    const p = this.game.player, hero = p?.hero;
    if (!hero) return;
    if (this._ghostHero === hero && this._ghosts.length) return;
    for (const gh of this._ghosts) gh.holder.parent?.remove(gh.holder);
    this._ghosts = [];
    this._ghostHero = hero;
    for (let i = 0; i < 7; i++) {
      const c = cloneHero(hero, [p.weaponModel]);
      const mat = new THREE.MeshBasicMaterial({ color: '#7FEFFF', transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
      for (const m of c.meshes) {
        m.material = mat;
        if (!m.geometry.boundingSphere) m.geometry.computeBoundingSphere();
        if (!m.isSkinnedMesh && m.geometry.boundingSphere.radius < 0.03) m.visible = false;
      }
      const holder = new THREE.Group();
      holder.add(c.group);
      holder.visible = false;
      this.game.scene.add(holder);
      this._ghosts.push({ ...c, holder, group: holder, mat, t: -1 });
    }
  }

  _spawnGhost() {
    const p = this.game.player;
    const gh = this._ghosts.find((x) => x.t < 0) || this._ghosts.reduce((a, b) => (a.t > b.t ? a : b), this._ghosts[0]);
    if (!gh) return;
    copyPose(p.hero, gh);
    gh.holder.position.copy(p.model.position);
    gh.holder.quaternion.copy(p.model.quaternion);
    gh.holder.visible = true;
    gh.t = 0;
    const hue = [PAL.gelCyan, '#FFFFFF', PAL.gelMagenta][Math.floor(Math.random() * 3)];
    gh.mat.color.set(hue);
  }

  _updateGhosts(rdt) {
    for (const gh of this._ghosts) {
      if (gh.t < 0) continue;
      gh.t += rdt;
      const k = gh.t / 0.5;
      gh.mat.opacity = 0.45 * (1 - k);
      if (k >= 1) { gh.t = -1; gh.holder.visible = false; }
    }
  }

  _ring(pos, radius) {
    const g = this.game;
    if (!this._ringMat) {
      const c = document.createElement('canvas');
      c.width = 256; c.height = 8;
      const x = c.getContext('2d');
      const gr = x.createLinearGradient(0, 0, 256, 0);
      gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(0.75, 'rgba(255,240,170,0.5)'); gr.addColorStop(0.93, 'rgba(255,255,255,1)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      x.fillStyle = gr; x.fillRect(0, 0, 256, 8);
      const tex = new THREE.CanvasTexture(c);
      tex.colorSpace = THREE.SRGBColorSpace;
      this._ringGeo = new THREE.RingGeometry(0.02, 1, 64, 1);
      const uv = this._ringGeo.attributes.uv, pa = this._ringGeo.attributes.position;
      for (let i = 0; i < uv.count; i++) uv.setXY(i, Math.hypot(pa.getX(i), pa.getY(i)), 0.5);
      this._ringGeo.rotateX(-Math.PI / 2);
      this._ringMat = tex;
    }
    const mat = new THREE.MeshBasicMaterial({ map: this._ringMat, color: '#FFE9A0', transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, fog: false });
    const mesh = new THREE.Mesh(this._ringGeo, mat);
    mesh.position.copy(pos).setY(pos.y + 0.06);
    mesh.renderOrder = 4;
    g.scene.add(mesh);
    this._rings.push({ mesh, t: 0, r: radius });
  }

  _updateRings(rdt) {
    for (let i = this._rings.length - 1; i >= 0; i--) {
      const r = this._rings[i];
      r.t += rdt;
      const k = r.t / 0.45;
      const s = 0.3 + (r.r - 0.3) * (1 - (1 - clamp01(k)) ** 3);
      r.mesh.scale.set(s, 1, s);
      r.mesh.material.opacity = 1 - smooth(0.5, 1, k);
      if (k >= 1) { r.mesh.parent?.remove(r.mesh); r.mesh.material.dispose(); this._rings.splice(i, 1); }
    }
  }

  // The referee whistle drops off the lanyard and bounces away (Replay-Ade consumed).
  _dropWhistle() {
    const g = this.game, hero = g.player?.hero;
    if (!hero?.slots?.neck) return;
    const chrome = g.mats.toon('#B8C0CA', { metal: 1, rough: 0.25, keepColor: true });
    const grp = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.05, 14).rotateZ(Math.PI / 2), chrome);
    const mouth = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.018, 0.06), chrome);
    mouth.position.set(0, 0.02, -0.04);
    const cord = new THREE.Mesh(new THREE.TorusGeometry(0.05, 0.006, 5, 16), g.mats.toon('#F4C81E', { keepColor: true }));
    cord.position.set(0, 0.06, 0);
    grp.add(body, mouth, cord);
    hero.slots.neck.updateWorldMatrix(true, false);
    hero.slots.neck.getWorldPosition(_v);
    grp.position.copy(_v).add(_w.set(0, -0.15, 0));
    g.scene.add(grp);
    const p = g.player;
    const fx = -Math.sin(p.model.rotation.y), fz = -Math.cos(p.model.rotation.y);
    this._whistles.push({ obj: grp, v: new THREE.Vector3(fx * 1.6 + (Math.random() - 0.5), 2.6, fz * 1.6 + (Math.random() - 0.5)), spin: new THREE.Vector3(7, 3, 5), t: 0, bounces: 0 });
  }

  _updateWhistles(rdt) {
    const col = this.game.level?.col;
    for (let i = this._whistles.length - 1; i >= 0; i--) {
      const w = this._whistles[i];
      w.t += rdt;
      w.v.y -= 18 * rdt;
      w.obj.position.addScaledVector(w.v, rdt);
      w.obj.rotation.x += w.spin.x * rdt; w.obj.rotation.y += w.spin.y * rdt; w.obj.rotation.z += w.spin.z * rdt;
      const floor = col ? col.floorAt(w.obj.position.x, w.obj.position.z, w.obj.position.y + 0.2) : 0;
      const fy = (Number.isFinite(floor) ? floor : 0) + 0.03;
      if (w.obj.position.y < fy && w.v.y < 0) {
        w.obj.position.y = fy;
        if (w.bounces < 3) {
          w.v.y = -w.v.y * 0.45; w.v.x *= 0.6; w.v.z *= 0.6; w.spin.multiplyScalar(0.6); w.bounces++;
          this.game.audio?.play?.('grenade_bounce', { pos: w.obj.position, rate: 1.9, vol: 0.5 });
        } else { w.v.set(0, 0, 0); w.spin.set(0, 0, 0); }
      }
      if (w.t > 3.2) {
        const s = Math.max(0.001, 1 - (w.t - 3.2) / 0.3);
        w.obj.scale.setScalar(s);
        if (w.t > 3.5) { w.obj.parent?.remove(w.obj); this._whistles.splice(i, 1); }
      }
    }
  }

  // ------------------------------------------------------------------------------------------ update
  update(dt) {
    const g = this.game, p = g.player;
    const rdt = g.time.realDt || 0;
    if (!p) return;
    if (this.replayActive) this._updateReplay(rdt);
    // Only the rewind ever runs the world at 0.1: without a replay that value is a leftover (e.g. an effect that
    // started mid-rewind saved it and restored it later), never a wanted state.
    else if (g.time.scale === REWIND_SCALE) { g.time.scale = 1; this._scaleSet = null; }
    if (this._invulnT > 0) {
      this._invulnT -= rdt;
      if (this._invulnT <= 0 && !this.replayActive && !g.sponsors?.inCommercial) p.invulnerable = false;
    }
    // Roller Boogie skating strides: wrap each hero animator once (legs after the procedural + weapon pose).
    if (p.animator && !this._wrapped.has(p.animator)) this._wrapAnimator(p.animator);
    if (this._rimHero && this._rimHero !== p.hero) { this._restoreRim(); if (this.has('wobble_up')) this._tintRim(true); }
    this._updateJelly(rdt);
    this._updateSkate(dt, rdt);
    this._updatePops(rdt);
    this._updateGhosts(rdt);
    this._updateRings(rdt);
    this._updateWhistles(rdt);
    if (this.has('double_vision') && dt > 0) {
      this._ting -= dt;
      if (this._ting <= 0) { this._ting = 6; this._smileTing(); }
    }
    const cam = g.render.cameraOverride || g.camera;
    this.sparkles?.update(rdt, cam);
  }

  _updatePops(rdt) {
    for (let i = this._pops.length - 1; i >= 0; i--) {
      const pp = this._pops[i];
      pp.t += rdt;
      const k = clamp01(pp.t / 0.38);
      pp.obj.scale.setScalar(Math.max(0.001, pp.base * easeOutBack(k, 2.6)));
      if (k >= 1) { pp.obj.scale.setScalar(pp.base); this._pops.splice(i, 1); }
    }
  }

  // Damped jelly spring on the whole hero (+ the helmet wobbles twice as much).
  _updateJelly(rdt) {
    const hero = this.game.player.hero;
    if (!hero) return;
    const J = this._jelly;
    if (!this.has('wobble_up') && Math.abs(J.x) < 1e-3 && Math.abs(J.v) < 1e-3) { if (hero.group.scale.y !== 1) hero.group.scale.set(1, 1, 1); return; }
    const n = Math.max(1, Math.ceil(rdt / (1 / 120))), h = rdt / n;
    for (let i = 0; i < n; i++) { J.v += (-190 * J.x - 7.5 * J.v) * h; J.x += J.v * h; }
    J.x = THREE.MathUtils.clamp(J.x, -0.35, 0.35);
    const y = 1 + J.x * 0.55, xz = 1 / Math.sqrt(Math.max(0.3, y));
    hero.group.scale.set(xz, y, xz);
    const helm = this._costumes.get('wobble_up');
    if (helm) for (const pc of helm.pieces) {
      if (this._pops.some((pp) => pp.obj === pc.obj)) continue;
      const hy = 1 + J.x * 1.3 + Math.sin(this.game.time.realNow * 9) * 0.012, hxz = 1 / Math.sqrt(Math.max(0.3, hy));
      pc.obj.scale.set(pc.scale * hxz, pc.scale * hy, pc.scale * hxz);
    }
  }

  _smileTing() {
    const g = this.game, c = this._costumes.get('double_vision');
    const p = g.player;
    g.audio?.play?.('smile_ting', { pos: p.pos, vol: 0.55 });
    const pc = c?.pieces?.[0];
    if (!pc) return;
    pc.obj.updateWorldMatrix(true, true);
    _v.set(-0.24, 0.36, 0.08).applyMatrix4(pc.obj.matrixWorld);
    this.sparkles?.emit(_v, { count: 1, color: '#FFFFFF', speed: 0.01, size: 0.42, life: 0.45, gravity: 0, spin: 5 });
    this.sparkles?.emit(_v, { count: 4, colors: [PAL.gelCyan, PAL.gelMagenta], speed: 0.6, size: 0.09, life: 0.5, gravity: 0 });
  }

  // ------------------------------------------------------------------------------------------ skating
  _wrapAnimator(a) {
    this._wrapped.add(a);
    const orig = a.update.bind(a);
    const self = this;
    a.update = function (dt, st) {
      orig(dt, st);
      try { self._skatePose(a.rig, dt); } catch (err) { /* cosmetic only */ }
    };
  }

  _skatePose(rig, dt) {
    const S = this._skate;
    const w = S.w;
    if (w <= 0.001) return;
    const J = rig.joints;
    const ph = S.phase;
    const s = Math.sin(ph), c = Math.cos(ph);
    const pushL = Math.max(0, s), pushR = Math.max(0, -s);
    // push-and-glide: the pushing leg extends back and out, the gliding leg bends and carries the weight
    J.hipL.rotation.set(THREE.MathUtils.lerp(J.hipL.rotation.x, 0.25 - pushL * 0.75, w), J.hipL.rotation.y, THREE.MathUtils.lerp(J.hipL.rotation.z, -pushL * 0.42, w));
    J.hipR.rotation.set(THREE.MathUtils.lerp(J.hipR.rotation.x, 0.25 - pushR * 0.75, w), J.hipR.rotation.y, THREE.MathUtils.lerp(J.hipR.rotation.z, pushR * 0.42, w));
    J.kneeL.rotation.x = THREE.MathUtils.lerp(J.kneeL.rotation.x, -0.55 + pushL * 0.35, w);
    J.kneeR.rotation.x = THREE.MathUtils.lerp(J.kneeR.rotation.x, -0.55 + pushR * 0.35, w);
    J.footL.rotation.x = THREE.MathUtils.lerp(J.footL.rotation.x, 0.3 - pushL * 0.1, w);
    J.footR.rotation.x = THREE.MathUtils.lerp(J.footR.rotation.x, 0.3 - pushR * 0.1, w);
    J.hips.position.y -= 0.07 * w;
    J.hips.position.x += c * 0.05 * w;
    J.hips.rotation.z += -c * 0.07 * w;
    rig.root.rotation.z += c * 0.06 * w;
  }

  _updateSkate(dt, rdt) {
    const g = this.game, p = g.player, S = this._skate;
    const on = this.has('roller_boogie') && p.sprinting && p.grounded && !g.sponsors?.inCommercial && !this.replayActive;
    S.w += ((on ? 1 : 0) - S.w) * (1 - Math.exp(-rdt * 9));
    if (on) S.phase += rdt * 5.2;
    this._skateLoop(on && dt > 0);
    if (!on || dt <= 0 || !p.hero) return;
    S.sparkT -= dt;
    if (S.sparkT > 0) return;
    S.sparkT = 0.06;
    const foot = Math.sin(S.phase) > 0 ? p.hero.slots.footL : p.hero.slots.footR;
    if (!foot) return;
    foot.updateWorldMatrix(true, false);
    foot.getWorldPosition(_v);
    _v.y = p.pos.y + 0.06;
    g.fx?.burst?.(_v, { shape: 'star', count: 1, speed: 0.4, size: 0.055, life: 0.45, gravity: -0.4, colors: ['#FF9EDB', '#7FE7FF', '#FFE27A'] });
  }

  _skateLoop(on) {
    const S = this._skate, a = this.game.audio;
    if (on && !S.loop && a?.loop) S.loop = a.loop('skate_roll', { vol: 0.45 });
    else if (!on && S.loop) { try { S.loop.stop(0.15); } catch (err) { /* ignore */ } S.loop = null; }
    if (S.loop && on) S.loop.setPos?.(this.game.player.pos);
  }

  // ------------------------------------------------------------------------------------------ precompile
  warmup() {
    const g = this.game, out = [];
    try {
      for (const id of PERK_IDS) {
        const prop = buildProp(COSTUMES[id], g, {});
        g.mats.applyHeroFade?.(prop);
        out.push(prop);
      }
      const hero = g.player?.hero;
      if (hero) {
        this._ensureGhosts();
        const c = cloneHero(hero, [g.player.weaponModel]);
        const mat = new THREE.MeshBasicMaterial({ color: '#7FEFFF', transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
        for (const m of c.meshes) m.material = mat;
        out.push(c.group);
      }
    } catch (err) {
      console.warn('[perks] warmup', err);
    }
    return out;
  }
}
