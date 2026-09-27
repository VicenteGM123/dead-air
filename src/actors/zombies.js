// ZombieManager (ARCHITECTURE §10, GDD §5.9–5.10, §7.4, §8 common, §8.1). Owned by the zombies agent.
//
// API (game.zombies)
//   alive                     living zombies (every state but dying): { id, type, def, pos, vel, yaw, hp, maxHp, state,
//                             area, group, rig, animator, radius, height, speed, flags, head, headR, hitZones, anim,
//                             stun, fromRound, entry }. state: 'approach' | 'queue' | 'tear' | 'vault' | 'screen' |
//                             'chase' | 'attack'  (then 'dying' once killed; z.dead = true).
//   dying                     zombies playing their death (not targetable).
//   maxAlive                  spawn cap (T.rounds.maxAlive; Rounds lowers it to 10 in Hullabaloo Hour).
//   spawn(typeId, entryId|null, pos|null, opts?) -> z | null (null at the cap). entryId = a window/fence/gate id
//                             (level.windows) or a screen spawn id 'ss_*'; both null = pick a spawner per GDD §5.9
//                             (active areas, 8 m rule, first spawn of a game through B3). opts: { hp, speed, fromRound, silent (no static
//                             pop-in burst for pos spawns), variant (Tuned-In art id, e.g. 'z_mom': that look instead of a
//                             random one) }. A pos is snapped to the nav floor (nearest cell within 3 m).
//   damage(z, amount, info) -> killed:bool   info = { head, zone, weaponId, point, dir, knockback (m of shove),
//                             cause ('bullet'|'melee'|'grenade'|'wonder'|'tele'|...), points (false = no points),
//                             hitmarker (false = no hud.hitmarker), upgraded, corpse (false = the caller animates a clone
//                             of the body, e.g. wonder weapons: no death visuals here, removed next frame) }.
//                             Applies the zone multiplier (limb ×0.8;
//                             pass the raycast's zone, do not pre-multiply), ×2 while in a screen's glass, the type's
//                             onDamage, ONE TAKE (one hit, Big Shot ×5). Awards ALL zombie points (GDD §6.3): +10 per
//                             damaging hit (deduped per zombie per frame + weapon: a shotgun volley / ghost bullet
//                             counts once), kills 50 / head 100 / melee 130 / grenade-wonder-tele 50, + type kill bonus.
//                             Hit reaction (squash, head-spring, 0.15 s stagger), confetti + felt fluff, zmb_hit.
//   kill(z, info)             kill now (same points rules; cause 'cancelled' / 'debug' / 'boss' / 'script' give none).
//   raycast(origin, dir, maxDist) -> { z, head, dist, point, zone } | null   head sphere, torso + limb capsules
//                             (or the type's hitZones / hitTest). Screen telegraph: a sphere on the screen itself.
//   inRadius(pos, r, out=[]) -> out   (distance to the zombie's feet-to-head segment)
//   killAll(cause='cancelled') stunAll(seconds)  stun(z, s)  freezeAll(bool)  setLure(pos|null)  knockback(z, vec)
//   despawn(z, requeue=true)  despawnAll({fx})  nearest(pos, maxDist) -> z|null  count(typeId?)  roundAlive(token)
//   warmup() -> samples (Game.precompile hook)
// Events: zombie:spawn {z}, zombie:hit {z, dmg, head, weaponId, point, zone, cause}, zombie:kill {z, weaponId, head,
//   melee, pos, cause}, zombie:attack {z, dmg}, zombie:despawn {z}.
// Behaviour: window entry (walk to the outside point, queue, tear 1 board / 1.2 s, vault 1.2 s; fence climb 1.5 s;
//   gate squeeze 0.8 s; screen telegraph 1.2 s via screens.telegraph + taffy emerge 1.0 s, ×2 damage in the glass),
//   flow field (nav.dir) + boid separation 0.6 m + direct chase with line of sight when close, the Tuned-In swipe
//   (0.4 s wind-up, player.hurt, 1.2 s cooldown), zombies block the player, anti-stuck (8 s neither closer on the
//   path nor walking -> silent despawn + requeue), straggler rule (last zombie > 40 m of path for 20 s -> re-enters near you), lure
//   (Tiny Tele: gather and kneel, mesmerized), stun stars, PLEASE STAND BY freeze look, ONE TAKE star eyes, the
//   Sign-On gawk (stop and look at the nearest TV for 1.5 s), death = topple back with a bounce + circling stars,
//   then 30 static quads + 12 colour-bar confetti + a fluttering ticket stub; headshot kill = the head pops off
//   like a cork (30 ms hit-stop), bounces twice and vanishes in static.
// Performance: models pooled per art variant; distance/frustum LOD for animation (far/off-screen: every 3rd frame),
//   body shadows (8 nearest on screen; the rest keep their blob), ticket/patch cards (< 7 m) and the eye veil + rim
//   (< 13 m); FX are two instanced pools. Every mesh is on LAYERS.ZOMBIES. Measured (Iris Xe, lobby, 24 baked
//   zombies): ~6.7 draw calls and ~20k triangles per zombie including shadows, update + lateUpdate ~1.7 ms.
//   Characters perf pass: one skeleton per baked Tuned-In (attachments are plain head meshes), and lateUpdate lays out
//   the crowd batches (zombieTypes.js): the attachments of every live Tuned-In are drawn as one draw per look and
//   material, i.e. a crowd costs ~1 body draw per zombie + ~5-7 draws per look on screen. crowdInfo() = counters.
//   charOpt (this.charOpt, src/art/charRuntime.js) holds the live A/B flags (merge, crowd, dedupe).

import * as THREE from 'three';
import { T, PAL, LAYERS } from '../core/config.js';
import { ZOMBIE_TYPES, getType, buildZombie, buildVariant, bakedZombieIds, releaseModel, prewarmModels,
  humanoidHitZones, setEyeMode, setZombieTint, updateCrowd, resetCrowd, crowdWarmup, crowdStats, CROWD_LAYER } from './zombieTypes.js';
import { zombieHp } from '../game/rounds.js';
import { charOpt } from '../art/charRuntime.js';

const Z = T.zombies;
const P = T.points;
const TURN = 7;               // rad/s-ish yaw easing
const ACCEL = 7;              // 1/s velocity easing
const SEP_R = 0.6;            // GDD §5.10 boid separation radius
const LOS_NEAR = 7.5;         // direct chase within this distance when the path is straight and visible
const GRAVITY = 22;
const STUCK_TIME = 8;
const STRAGGLER_DIST = 40;
const STRAGGLER_TIME = 20;
const RULE_8M = 8;
const DIE_TOPPLE = 0.55;
const DIE_LIE = 1.0;
const DIE_POP = 0.14;
const STAGGER = 0.15;
const SHADOW_MAX = 8;
const CARD_LOD = 7;            // ticket stub / patch cards drawn within this camera distance
const DETAIL_LOD = 13;         // eye veil + rim drawn within this distance (the static eye discs always)
const ANIM_NEAR = 24;
const GAWK = 1.5;
const LEVER = new THREE.Vector3(34, 1, -7);

const NO_POINTS = new Set(['cancelled', 'debug', 'despawn', 'boss', 'script', 'egg']);
const SPECIAL_CAUSES = new Set(['grenade', 'explosion', 'wonder', 'zapper', 'boom_mic', 'chroma_key', 'tele', 'tiny_tele', 'gag']);
const SPECIAL_WEAPONS = new Set(['zapper', 'boom_mic', 'chroma_key', 'tiny_tele', 'tube_grenade']);

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _c = new THREE.Vector3();
const _d = new THREE.Vector3();
const _ba = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _delta = new THREE.Vector3();
const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _e = new THREE.Euler();
const _sphere = new THREE.Sphere();
const _frustum = new THREE.Frustum();
const _pv = new THREE.Matrix4();
const _hit = { dist: 0, zone: 'torso', head: false, mul: 1 };
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const smooth = (x) => { x = clamp01(x); return x * x * (3 - 2 * x); };
const easeOutCubic = (x) => 1 - (1 - clamp01(x)) ** 3;
const easeOutBack = (x) => { x = clamp01(x); const c = 1.9; return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2; };
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const yawTo = (dx, dz) => Math.atan2(-dx, -dz);

// Ray (o, d normalized) vs sphere (c, r) -> distance or Infinity.
function raySphere(o, d, c, r) {
  _c.subVectors(o, c);
  const b = _c.dot(d);
  const q = _c.lengthSq() - r * r;
  const disc = b * b - q;
  if (disc < 0) return Infinity;
  const t = -b - Math.sqrt(disc);
  return t >= 0 ? t : (q < 0 ? 0 : Infinity);
}

// Ray vs capsule (segment a..b, radius r) -> distance or Infinity (after Inigo Quilez).
function rayCapsule(o, d, a, b, r) {
  _ba.subVectors(b, a);
  _d.subVectors(o, a);
  const baba = _ba.lengthSq(), bard = _ba.dot(d), baoa = _ba.dot(_d), rdoa = d.dot(_d), oaoa = _d.lengthSq();
  const qa = baba - bard * bard, qb = baba * rdoa - baoa * bard, qc = baba * oaoa - baoa * baoa - r * r * baba;
  if (qa < 1e-9) return raySphere(o, d, a, r);
  const h = qb * qb - qa * qc;
  if (h < 0) return Infinity;
  const t = (-qb - Math.sqrt(h)) / qa;
  const y = baoa + t * bard;
  if (y > 0 && y < baba) return t >= 0 ? t : (qc < 0 ? 0 : Infinity);
  return raySphere(o, d, y <= 0 ? a : b, r);
}

function killPoints(cause, head, weaponId) {
  if (NO_POINTS.has(cause)) return 0;
  if (cause === 'melee' || weaponId === 'melee') return P.melee;
  if (SPECIAL_CAUSES.has(cause) || SPECIAL_WEAPONS.has(weaponId)) return P.special;
  return head ? P.head : P.kill;
}

// ------------------------------------------------------------------------------------------------ FX pools
function starGeometry() {
  const s = new THREE.Shape();
  for (let i = 0; i < 10; i++) {
    const a = Math.PI / 2 + (i * Math.PI) / 5, r = i % 2 ? 0.024 : 0.058;
    if (i === 0) s.moveTo(Math.cos(a) * r, Math.sin(a) * r); else s.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  s.closePath();
  const g = new THREE.ExtrudeGeometry(s, { depth: 0.016, bevelEnabled: true, bevelThickness: 0.006, bevelSize: 0.006, bevelSegments: 1 });
  g.center();
  return g;
}

function ticketTexture() {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 140;
  const g = c.getContext('2d');
  g.fillStyle = '#F6E7C8'; g.fillRect(0, 0, 256, 140);
  g.strokeStyle = '#E23B3B'; g.lineWidth = 7;
  g.strokeRect(14, 14, 228, 112);
  g.fillStyle = '#C9B48E';
  for (let y = 24; y < 120; y += 12) { g.beginPath(); g.arc(88, y, 2.5, 0, Math.PI * 2); g.fill(); }
  g.fillStyle = '#E23B3B';
  g.font = '900 64px "Arial Black", Impact, sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText('13', 52, 74);
  g.fillStyle = '#2B2238';
  g.font = '900 32px "Arial Black", Impact, sans-serif';
  g.fillText('ADMIT', 166, 52);
  g.fillText('ONE', 166, 92);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

class StarRings {
  constructor(scene) {
    const mat = new THREE.MeshBasicMaterial({ color: new THREE.Color(PAL.marqueeGold).multiplyScalar(1.8) });
    mat.name = 'zombieStars';
    this.mesh = new THREE.InstancedMesh(starGeometry(), mat, 96);
    this.mesh.name = 'zombie:stars';
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = false;
    this.mesh.count = 0;
    this.mesh.visible = false;
    this.mesh.layers.set(LAYERS.ZOMBIES);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    scene.add(this.mesh);
    this.rings = [];
  }
  // src: () => Vector3 (head position) ; life seconds ; n stars
  add(z, life, n = 3, r = 0.26) {
    for (const ring of this.rings) if (ring.z === z) { ring.life = Math.max(ring.life, life); ring.t = Math.min(ring.t, 0.2); return ring; }
    const ring = { z, t: 0, life, n, r, phase: Math.random() * 6 };
    this.rings.push(ring);
    return ring;
  }
  remove(z) {
    this.rings = this.rings.filter((r) => r.z !== z);
  }
  clear() { this.rings.length = 0; }
  update(dt) {
    let k = 0;
    for (let i = this.rings.length - 1; i >= 0; i--) {
      const ring = this.rings[i];
      ring.t += dt;
      const z = ring.z;
      if (ring.t >= ring.life || !z.head || (z.dead && !z.group.parent)) { this.rings.splice(i, 1); continue; }
      z.head.getWorldPosition(_a);
      _a.y += (z.headR || 0.25) * 0.95;
      const grow = easeOutBack(ring.t / 0.25) * (1 - smooth((ring.t - ring.life + 0.25) / 0.25));
      for (let s = 0; s < ring.n && k < 96; s++) {
        const ang = ring.phase + ring.t * 5.5 + (s * Math.PI * 2) / ring.n;
        _b.set(_a.x + Math.cos(ang) * ring.r, _a.y + Math.sin(ang * 2) * 0.04, _a.z + Math.sin(ang) * ring.r);
        _q.setFromEuler(_e.set(0, -ang + ring.t * 3, 0));
        _m.compose(_b, _q, _s.setScalar(Math.max(0.001, grow)));
        this.mesh.setMatrixAt(k++, _m);
      }
    }
    this.mesh.count = k;
    this.mesh.visible = k > 0;
    if (k) this.mesh.instanceMatrix.needsUpdate = true;
  }
}

class Tickets {
  constructor(scene) {
    const mat = new THREE.MeshBasicMaterial({ map: ticketTexture(), side: THREE.DoubleSide, color: new THREE.Color(0.9, 0.9, 0.9) });
    mat.name = 'zombieTicket';
    this.mesh = new THREE.InstancedMesh(new THREE.PlaneGeometry(0.1, 0.055), mat, 24);
    this.mesh.name = 'zombie:tickets';
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = false;
    this.mesh.count = 0;
    this.mesh.visible = false;
    this.mesh.layers.set(LAYERS.ZOMBIES);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    scene.add(this.mesh);
    this.list = [];
  }
  add(pos, floorY) {
    if (this.list.length >= 24) this.list.shift();
    this.list.push({ p: pos.clone(), floor: floorY + 0.01, t: 0, seed: Math.random() * 10, vx: (Math.random() - 0.5) * 0.8, vz: (Math.random() - 0.5) * 0.8, landed: false });
  }
  clear() { this.list.length = 0; }
  update(dt) {
    let k = 0;
    for (let i = this.list.length - 1; i >= 0; i--) {
      const t = this.list[i];
      t.t += dt;
      if (t.t > 4.5) { this.list.splice(i, 1); continue; }
      if (!t.landed) {
        t.p.y -= dt * (0.55 + 0.25 * Math.sin(t.t * 7 + t.seed));
        t.p.x += (t.vx + Math.sin(t.t * 4.2 + t.seed) * 0.9) * dt;
        t.p.z += (t.vz + Math.cos(t.t * 3.7 + t.seed) * 0.9) * dt;
        if (t.p.y <= t.floor) { t.p.y = t.floor; t.landed = true; }
      }
      const rx = t.landed ? -Math.PI / 2 : Math.sin(t.t * 6 + t.seed) * 0.9;
      const rz = t.landed ? 0 : Math.cos(t.t * 5 + t.seed) * 0.6;
      _q.setFromEuler(_e.set(rx, t.seed + t.t * (t.landed ? 0 : 2), rz));
      const s = 1 - smooth((t.t - 4) / 0.5);
      _m.compose(t.p, _q, _s.setScalar(Math.max(0.001, s)));
      this.mesh.setMatrixAt(k++, _m);
    }
    this.mesh.count = k;
    this.mesh.visible = k > 0;
    if (k) this.mesh.instanceMatrix.needsUpdate = true;
  }
}

// ------------------------------------------------------------------------------------------------ manager
export class ZombieManager {
  constructor(game) {
    this.game = game;
    this.alive = [];
    this.dying = [];
    this.frozen = false;
    this.lure = null;
    this.maxAlive = T.rounds.maxAlive;
    this._uid = 0;
    this._firstSpawn = true;
    this._entries = new Map();
    this._heads = new Map();     // variant -> [popped-head proxies]
    this._flying = [];           // active popped heads
    this._stars = null;
    this._tickets = null;
    this._oneTake = false;
    this._standby = false;
    this._hitSfx = 0;
    this._frame = 0;
    this._camPos = new THREE.Vector3();
    this._order = [];
    // Live character perf flags (src/art/charRuntime.js charOpt), reachable for A/B tools as __game.zombies.charOpt.
    this.charOpt = charOpt;
  }

  init() {
    const g = this.game;
    this._stars = new StarRings(g.scene);
    this._tickets = new Tickets(g.scene);
    g.events.on('power:on', () => this._signOnGawk());
    // crowd batches (zombieTypes.js) are drawn by the gameplay camera only (not the screens' feed cameras)
    if (g.camera && g.camera.layers) g.camera.layers.enable(CROWD_LAYER);
  }

  reset() {
    for (const z of this.alive.slice()) this._remove(z);
    for (const z of this.dying.slice()) this._remove(z);
    this.alive.length = 0;
    this.dying.length = 0;
    resetCrowd();
    for (const h of this._flying) this._releaseHead(h);
    this._flying.length = 0;
    this._entries.clear();
    this.frozen = false;
    this.lure = null; this._lureField = null;
    this.maxAlive = T.rounds.maxAlive;
    this._firstSpawn = true;
    this._oneTake = false;
    this._standby = false;
    setEyeMode('static');
    setZombieTint(null);
    if (this._stars) this._stars.clear();
    if (this._tickets) this._tickets.clear();
    // Pool a few models per variant so the first wave never hitches.
    try {
      prewarmModels(this.game, 'tuned_in', 4);
      const ids = bakedZombieIds('tuned_in', this.game);
      for (const id of ids.length ? ids : ['placeholder']) this._prewarmHeads(id, 1);
    } catch (err) {
      console.warn('[zombies] prewarm failed', err);
    }
  }

  // Game.precompile() hook: one throw-away model per zombie type (and per baked art variant) + the FX materials.
  warmup() {
    const g = this.game, out = [];
    for (const id of Object.keys(ZOMBIE_TYPES)) {
      const def = ZOMBIE_TYPES[id];
      if (def.fallback === false && id !== 'tuned_in') {
        // Real special modules provide their own samples (building one could register shootables etc.).
        if (typeof def.warmup === 'function') {
          try { out.push(...[].concat(def.warmup(g) || [])); } catch (err) { console.warn('[zombies] warmup', id, err); }
        }
        continue;
      }
      const n = Math.max(1, bakedZombieIds(id, g).length);
      for (let i = 0; i < n; i++) out.push(buildZombie(id, g, i).group);
    }
    if (this._stars) {
      const s = new THREE.Mesh(this._stars.mesh.geometry, this._stars.mesh.material);
      const t = new THREE.Mesh(this._tickets.mesh.geometry, this._tickets.mesh.material);
      out.push(s, t);
    }
    // the crowd batches' skinned program variants (the looks were registered by the models built above)
    try { out.push(...crowdWarmup()); } catch (err) { console.warn('[zombies] crowd warmup', err); }
    return out;
  }

  // Perf counters of the crowd batches: { looks, batches, active (zombies drawn by batches), drawn (batch draws) }.
  crowdInfo() { return crowdStats(); }

  // ---------------------------------------------------------------------------------------------- spawning
  spawn(typeId = 'tuned_in', entryId = null, pos = null, opts = {}) {
    const g = this.game;
    if (this.alive.length >= this.maxAlive) return null;
    const def = getType(typeId);
    const round = Math.max(1, (g.rounds && g.rounds.round) || 1);
    const z = {
      id: ++this._uid, type: def.id, def, pos: new THREE.Vector3(), vel: new THREE.Vector3(), yaw: 0, vy: 0,
      hp: 1, maxHp: 1, state: 'chase', area: null, group: null, rig: null, animator: null, model: null,
      radius: def.radius || 0.36, height: def.height || 1.6, speed: 1, scale: 1, flags: {}, head: null, headR: 0.25,
      hitZones: null, round, fromRound: opts.fromRound ?? null, dead: false,
      anim: { speed: 0, grounded: true, attack: 0, hurt: 0, climb: 0, dead: 0, down: false, turn: 0, clap: 0 },
      cd: 0, attackT: 0, swung: false, stun: 0, stagger: 0, dieT: 0, spawnT: 0, knock: new THREE.Vector3(),
      entry: null, los: false, losT: Math.random() * 0.25, navBest: Infinity, navT: 0, stuckT: 0, stragT: 0,
      gawkT: 0, gawkAt: null, lookYaw: 0, lod: 0, animAcc: 0, visible: true, camDist: 0, artVariant: opts.variant ?? -1,
    };
    try {
      def.build(g, z);
    } catch (err) {
      console.error('[zombies] build failed for', def.id, err);
      if (def.id !== 'tuned_in') return this.spawn('tuned_in', entryId, pos, opts);
      return null;
    }
    if (!z.group) return null;
    if (!z.head) { z.head = new THREE.Object3D(); z.head.position.set(0, z.height - z.headR, 0); z.group.add(z.head); }
    if (!z.hitZones && !z.hitTest) z.hitZones = humanoidHitZones({ rig: z.rig, head: z.head, headR: z.headR });
    const hp = Math.max(1, Math.round(opts.hp ?? (def.hp ? def.hp(round, g) : zombieHp(round))));
    z.hp = z.maxHp = hp;
    z.speed = opts.speed ?? (def.speed ? def.speed(round, g) : T.rounds.speeds.walk);
    z.group.traverse((o) => o.layers.set(LAYERS.ZOMBIES));

    // Where does it come in?
    if (pos) {
      this._standPos(pos, z.pos);
      z.yaw = yawTo(g.player.pos.x - z.pos.x, g.player.pos.z - z.pos.z);
      z.state = 'chase';
      z.area = g.level.areaAt(z.pos.x, z.pos.z);
      z.spawnT = 0.25;             // quick pop-in out of a burst of static
      if (!opts.silent) {
        _a.copy(z.pos).setY(z.pos.y + 0.8);
        g.fx.burst(_a, { shape: 'static', count: 12, speed: 1.8, size: 0.09, life: 0.6 });
      }
    } else {
      const sp = entryId ? this._spawnerById(entryId) : this._pickSpawner(def);
      if (!sp) {
        // Nothing sensible (should not happen): drop it near the player's area like a debug spawn.
        const p = g.player.pos;
        z.pos.set(p.x + 6, p.y, p.z);
        z.state = 'chase';
      } else if (sp.kind === 'screen') this._beginScreen(z, sp.ss);
      else this._beginEntry(z, sp.win);
      this._firstSpawn = false;
    }
    z.group.position.copy(z.pos);
    z.group.rotation.set(0, z.yaw, 0, 'YXZ');
    z.group.scale.setScalar(z.scale);
    g.scene.add(z.group);
    z.group.updateMatrixWorld(true);
    z.blob = g.fx.blob(z.group, z.radius * 1.15);
    this.alive.push(z);
    g.events.emit('zombie:spawn', { z });
    return z;
  }

  // Where a body given an explicit spawn pos can stand: the nav floor under it (debug.spawn may hand us the top of a
  // desk or a lamp), else the nearest nav cell within 3 m.
  _standPos(pos, out) {
    const nav = this.game.nav;
    out.copy(pos);
    if (!nav || typeof nav.heightAt !== 'function') return out;
    const h0 = nav.heightAt(pos.x, pos.z);
    if (h0 > -Infinity) { if (Math.abs(pos.y - h0) > 0.6) out.y = h0; return out; }
    for (let r = 0.5; r <= 3; r += 0.5) {
      const n = Math.max(8, Math.round(r * 12));
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2;
        const x = pos.x + Math.cos(a) * r, zz = pos.z + Math.sin(a) * r;
        const h = nav.heightAt(x, zz);
        if (h > -Infinity) return out.set(x, h, zz);
      }
    }
    return out;
  }

  _spawnerById(id) {
    const L = this.game.level;
    if (L.windows[id]) return { kind: 'entry', win: L.windows[id] };
    if (L.screenSpawns[id]) return { kind: 'screen', ss: L.screenSpawns[id] };
    return null;
  }

  // Areas the spawners are active in: the player's area (weight 1) + areas behind its open doors (0.5).
  _activeAreas() {
    const g = this.game, L = g.level;
    const here = g.player.area || L.areaAt(g.player.pos.x, g.player.pos.z) || this._lastArea || 'lobby';
    this._lastArea = here;
    const w = new Map([[here, 1]]);
    for (const d of Object.values(L.doors)) {
      if (!d.open || !d.areas || !d.areas.includes(here)) continue;
      const other = d.areas[0] === here ? d.areas[1] : d.areas[0];
      if (!w.has(other)) w.set(other, 0.5);
    }
    return w;
  }

  // GDD §5.9 spawner choice for a type. Returns { kind:'entry', win } | { kind:'screen', ss } | null.
  // opts.nearest: the nearest active spawner at least 8 m away (straggler rule) instead of a weighted pick.
  _pickSpawner(def, opts = {}) {
    const g = this.game, L = g.level, p = g.player.pos;
    const mode = def.spawnMode || 'window';
    if (this._firstSpawn && !opts.nearest && mode !== 'screen' && L.windows.w_lobby_west) return { kind: 'entry', win: L.windows.w_lobby_west };
    const areas = this._activeAreas();
    const cands = [];
    const wantEntries = mode === 'window' || mode === 'both';
    const wantScreens = mode === 'screen' || mode === 'both';
    const addEntries = (filterFn) => {
      for (const w of Object.values(L.windows)) {
        const wt = areas.get(w.area);
        if (!wt || (def.entryFilter && !def.entryFilter(w)) || (filterFn && !filterFn(w))) continue;
        const q = this._entries.get(w.id);
        const busy = q ? (q.front ? 1 : 0) + q.waiting.length : 0;
        cands.push({ kind: 'entry', win: w, pos: _a.set(w.inside[0], 0, w.inside[2]).clone(), weight: wt / (1 + busy * 0.8) });
      }
    };
    const addScreens = () => {
      for (const ss of Object.values(L.screenSpawns)) {
        const wt = areas.get(ss.area);
        if (!wt) continue;
        cands.push({ kind: 'screen', ss, pos: ss.pos, weight: wt });
      }
    };
    if (wantEntries) addEntries();
    if (wantScreens) {
      addScreens();
      // Forecasters in the Yard use the fence climbs (GDD §5.9).
      if (mode === 'screen') addEntries((w) => w.area === 'yard' && w.type === 'fence');
    }
    if (!cands.length) {
      if (!wantEntries) addEntries();
      if (!wantScreens) addScreens();
    }
    if (!cands.length) return null;
    const far = cands.filter((c) => Math.hypot(c.pos.x - p.x, c.pos.z - p.z) >= RULE_8M);
    if (!far.length) {
      let best = cands[0], bd = -1;
      for (const c of cands) { const d = Math.hypot(c.pos.x - p.x, c.pos.z - p.z); if (d > bd) { bd = d; best = c; } }
      return best;
    }
    if (opts.nearest) {
      let best = far[0], bd = Infinity;
      for (const c of far) { const d = Math.hypot(c.pos.x - p.x, c.pos.z - p.z); if (d < bd) { bd = d; best = c; } }
      return best;
    }
    let sum = 0;
    for (const c of far) sum += c.weight;
    let r = g.rand() * sum;
    for (const c of far) { r -= c.weight; if (r <= 0) return c; }
    return far[far.length - 1];
  }

  _entryQueue(id) {
    let q = this._entries.get(id);
    if (!q) this._entries.set(id, (q = { front: null, waiting: [] }));
    return q;
  }

  _beginEntry(z, win) {
    const g = this.game;
    const out = win.outsidePos || new THREE.Vector3(...win.outside);
    const sp = win.spawnPos || new THREE.Vector3(...win.spawn);
    // Scatter the spawn point a little sideways so a crowd does not stack.
    const ox = out.x - win.inside[0], oz = out.z - win.inside[2];
    const ol = Math.hypot(ox, oz) || 1;
    const side = (g.rand() - 0.5) * 2.2;
    z.pos.set(sp.x + (-oz / ol) * side, 0, sp.z + (ox / ol) * side);
    const fy = g.level.col.floorAt(z.pos.x, z.pos.z, 2);
    z.pos.y = fy > -Infinity ? fy : 0;
    z.yaw = win.rotY ?? yawTo(-ox, -oz);
    z.state = 'approach';
    z.area = null;
    z.entry = { kind: win.type === 'fence' ? 'fence' : win.type === 'gate' ? 'gate' : 'window', id: win.id, win, t: 0,
      out: new THREE.Vector3(out.x, 0, out.z), inw: new THREE.Vector3(-ox / ol, 0, -oz / ol), slot: -1, style: null, tearT: 0 };
    const fo = g.level.col.floorAt(out.x, out.z, 2);
    z.entry.out.y = fo > -Infinity ? fo : 0;
  }

  _beginScreen(z, ss) {
    const g = this.game;
    const fwd = _a.set(-Math.sin(ss.rotY), 0, -Math.cos(ss.rotY));
    z.yaw = ss.rotY;
    z.state = 'screen';
    z.area = ss.area;
    const land = new THREE.Vector3(ss.pos.x + fwd.x * 1.1, 0, ss.pos.z + fwd.z * 1.1);
    const fy = g.level.col.floorAt(land.x, land.z, ss.pos.y + 0.5);
    land.y = fy > -Infinity ? fy : 0;
    z.entry = { kind: 'screen', id: ss.id, ss, t: 0, phase: 'tele', fwd: fwd.clone(), land, inGlass: true };
    z.pos.copy(land);
    z.group.visible = false;
    // screens.telegraph flares that CRT (static + growing silhouette + glass bulge) and plays screen_telegraph
    // through its TV speaker; without it we play the cue ourselves.
    let tele = null;
    if (g.screens && typeof g.screens.telegraph === 'function') {
      try { tele = g.screens.telegraph(ss.id, Z.screenTelegraph); } catch (err) { tele = null; }
    }
    z.entry.tele = tele;
    if (!tele || tele.active === false) g.audio.play('screen_telegraph', { pos: ss.pos, tv: true });
    g.events.emit('zombie:telegraph', { z, screenId: ss.id, seconds: Z.screenTelegraph });
  }

  // ------------------------------------------------------------------------------------------------ update
  update(dt) {
    if (!(dt > 0)) return;
    const g = this.game;
    this._frame++;
    this._hitSfx = 0;
    const pu = g.powerups;
    const oneTake = !!(pu && (typeof pu.isActive === 'function' ? pu.isActive('one_take') : pu.active && pu.active.one_take > 0));
    if (oneTake !== this._oneTake) { this._oneTake = oneTake; setEyeMode(oneTake ? 'stars' : 'static'); }
    const standby = this.frozen && !!(pu && (typeof pu.isActive === 'function' ? pu.isActive('please_stand_by') : pu.active && pu.active.please_stand_by > 0));
    if (standby !== this._standby) { this._standby = standby; setZombieTint(standby ? 'standby' : null); }

    if (!this.frozen) this._separation();
    const list = this.alive;
    for (let i = list.length - 1; i >= 0; i--) {
      const z = list[i];
      if (!this.frozen) {
        this._think(z, dt, i);
        if (z.dead || z.removed) continue;
        this._animate(z, dt);
      }
    }
    if (!this.frozen) this._blockPlayer();
    this._updateDying(dt);
    this._updateHeads(dt);
    this._stars.update(dt);
    this._tickets.update(dt);
  }

  lateUpdate() {
    this._lod();
    updateCrowd(this.alive, this.dying);
  }

  // Boid separation (GDD §5.10: radius 0.6 m) among grounded zombies.
  _separation() {
    const L = this.alive;
    for (const z of L) { z.sepX = 0; z.sepZ = 0; }
    for (let i = 0; i < L.length; i++) {
      const a = L[i];
      if (a.state !== 'chase' && a.state !== 'attack') continue;
      for (let j = i + 1; j < L.length; j++) {
        const b = L[j];
        if (b.state !== 'chase' && b.state !== 'attack') continue;
        const dx = a.pos.x - b.pos.x, dz = a.pos.z - b.pos.z;
        const rr = Math.max(SEP_R, (a.radius + b.radius) * 0.95);
        const d2 = dx * dx + dz * dz;
        if (d2 >= rr * rr || Math.abs(a.pos.y - b.pos.y) > 1) continue;
        const d = Math.sqrt(d2) || 1e-3;
        const k = (rr - d) / rr;
        const nx = d2 > 1e-8 ? dx / d : Math.random() - 0.5, nz = d2 > 1e-8 ? dz / d : Math.random() - 0.5;
        a.sepX += nx * k; a.sepZ += nz * k;
        b.sepX -= nx * k; b.sepZ -= nz * k;
      }
    }
  }

  _think(z, dt, index) {
    const g = this.game;
    z.cd = Math.max(0, z.cd - dt);
    z.stagger = Math.max(0, z.stagger - dt);
    z.anim.hurt = Math.max(0, z.anim.hurt - dt / 0.25);
    if (z.spawnT > 0) z.spawnT = Math.max(0, z.spawnT - dt);
    // Knockback shove (decays).
    if (z.knock.lengthSq() > 1e-4 && (z.state === 'chase' || z.state === 'attack')) {
      _delta.copy(z.knock).multiplyScalar(dt);
      g.level.col.moveCircle(z.pos, _delta, z.radius, z.height, 0.45);
      z.knock.multiplyScalar(Math.exp(-dt * 9));
    }
    switch (z.state) {
      case 'approach': case 'queue': this._approach(z, dt); break;
      case 'tear': this._tear(z, dt); break;
      case 'vault': this._vault(z, dt); break;
      case 'screen': this._screen(z, dt); break;
      default: this._chase(z, dt); break;
    }
    if (z.dead || z.removed) return;
    if (z.state !== 'chase' && z.state !== 'attack' && z.def.updateEntry) {
      try { z.def.updateEntry(g, z, dt); } catch (err) { this._typeError(z, err); }
    }
  }

  _typeError(z, err) {
    const now = performance.now();
    if (!this._typeErrT || now - this._typeErrT > 5000) { this._typeErrT = now; console.error(`[zombies:${z.type}]`, err); }
  }

  // --- window / fence / gate entry --------------------------------------------------------------------
  _approach(z, dt) {
    const e = z.entry, q = this._entryQueue(e.id);
    // Target: the outside point when it is our turn, else a waiting slot further out.
    if (!q.front) q.front = z;
    if (q.front !== z && !q.waiting.includes(z)) q.waiting.push(z);
    const slot = q.front === z ? -1 : q.waiting.indexOf(z);
    const tgt = _b.copy(e.out);
    if (slot >= 0) {
      const back = 0.95 + slot * 0.75, side = (slot % 2 ? 1 : -1) * 0.45;
      tgt.addScaledVector(e.inw, -back);
      tgt.x += -e.inw.z * side; tgt.z += e.inw.x * side;
    }
    const dx = tgt.x - z.pos.x, dz = tgt.z - z.pos.z;
    const d = Math.hypot(dx, dz);
    const sp = Math.min(z.speed, 3.2);
    if (d > 0.06) {
      const step = Math.min(d, sp * dt);
      z.pos.x += (dx / d) * step; z.pos.z += (dz / d) * step;
      const fy = this.game.level.col.floorAt(z.pos.x, z.pos.z, z.pos.y + 0.5);
      if (fy > -Infinity) z.pos.y += (fy - z.pos.y) * Math.min(1, dt * 12);
      this._turnTo(z, d > 0.4 ? yawTo(dx, dz) : e.win.rotY, dt);
      z.anim.speed = d > 0.2 ? sp : sp * d / 0.2;
      z.state = slot >= 0 ? 'queue' : 'approach';
    } else {
      z.anim.speed = 0;
      this._turnTo(z, e.win.rotY, dt);
      if (slot < 0) this._arrive(z);
      else z.state = 'queue';
    }
    this._place(z);
  }

  // Reached the outside point: tear the boards, or the type's own entry style.
  _arrive(z) {
    const g = this.game, e = z.entry, win = e.win;
    let style = null;
    if (z.def.entry) {
      try { style = z.def.entry(g, z, win); } catch (err) { this._typeError(z, err); }
    }
    e.style = style || null;
    e.t = 0;
    if (style && style.style === 'blast' && win.type === 'boarded') {
      const n = win.breakAll ? win.breakAll() : 0;
      if (n > 0) {
        _a.copy(win.pos || e.out).setY((win.sill || 0) + 0.9);
        g.fx.burst(_a, { shape: 'confetti', count: 18, colors: [PAL.teak, PAL.walnut, PAL.cream, PAL.skyTop], speed: 5 });
        g.fx.burst(_a, { shape: 'puff', count: 8, size: 0.3 });
        g.fx.shake(0.25, 0.3);
      }
      z.state = 'vault';
      return;
    }
    if (win.type === 'boarded' && win.boards > 0 && !(style && style.tear === false)) {
      z.state = 'tear';
      e.tearT = 0;
      return;
    }
    z.state = 'vault';
    g.audio.play('window_vault', { pos: z.pos });
  }

  _tear(z, dt) {
    const g = this.game, e = z.entry, win = e.win;
    this._turnTo(z, win.rotY, dt);
    const T0 = Z.boardTear;
    const prev = e.tearT;
    e.tearT += dt;
    // One pull per board: arms rise (anticipation) and yank at 55 %.
    const ph = (e.tearT % T0) / T0, pph = (prev % T0) / T0;
    z.anim.attack = Math.min(0.99, ph);
    z.anim.speed = 0;
    if (pph < 0.55 && ph >= 0.55) {
      if (win.boards > 0 && win.breakBoard()) {
        if (z.animator && z.animator.kick) z.animator.kick(0.5);
        if (Math.random() < 0.35) g.audio.play('zmb_groan', { pos: z.pos, rate: 1.1 });
      }
    }
    if (win.boards <= 0 && ph < 0.2) {
      z.anim.attack = 0;
      z.state = 'vault';
      e.t = 0;
      g.audio.play('window_vault', { pos: z.pos });
    }
    this._place(z);
  }

  _vault(z, dt) {
    const g = this.game, e = z.entry, win = e.win, st = e.style;
    const kind = st && st.style ? st.style : e.kind === 'fence' ? 'fence' : e.kind === 'gate' ? 'gate' : 'vault';
    const dur = (st && st.time) || (kind === 'fence' ? Z.fence : kind === 'gate' ? Z.gate : kind === 'blast' ? 1.5 : Z.vault);
    e.t += dt;
    const u = clamp01(e.t / dur);
    const outP = e.out;
    if (!e.inP) {
      const fy = g.level.col.floorAt(win.inside[0], win.inside[2], (win.inside[1] || 0) + 0.8);
      e.inP = new THREE.Vector3(win.inside[0], fy > -Infinity ? fy : win.inside[1] || 0, win.inside[2]);
    }
    const inP = e.inP;
    const sill = win.sill || 0;
    let h, y, pitch = 0, sx = 1, sy = 1, climb = 0;
    if (kind === 'fence') {
      const top = outP.y + (win.top || 3) + 0.15;
      if (u < 0.6) { h = 0.45 * smooth(u / 0.6); y = outP.y + (top - outP.y) * easeOutCubic(u / 0.6); climb = 0.02 + u; }
      else if (u < 0.75) { const k = (u - 0.6) / 0.15; h = 0.45 + 0.3 * k; y = top + Math.sin(k * Math.PI) * 0.12; pitch = -0.5 * Math.sin(k * Math.PI); climb = 0.7; }
      else { const k = (u - 0.75) / 0.25; h = 0.75 + 0.25 * k; y = top + (inP.y - top) * k * k; }
    } else if (kind === 'gate' || kind === 'squeeze' || kind === 'toothpaste' || kind === 'blast') {
      h = smooth(u);
      const lift = kind === 'squeeze' ? Math.max(0, sill + 0.05) : 0;
      y = outP.y + (inP.y - outP.y) * h + Math.sin(u * Math.PI) * lift;
      const k = Math.sin(u * Math.PI);
      if (kind === 'gate') { sx = 1 - 0.45 * k; sy = 1 + 0.08 * k; }
      else if (kind === 'squeeze') { sy = 1 - 0.6 * k; sx = 1 + 0.35 * k; }
      else { sx = 1 - 0.5 * k; sy = 1 + 0.25 * k; }
      if (u >= 1 && !e.popped) { e.popped = true; if (z.animator && z.animator.kick) z.animator.kick(1.2); }
    } else {
      // Window vault: climb onto the sill, over, drop inside.
      const top = Math.max(outP.y, inP.y) + (sill > 0.05 ? sill + 0.12 : 0.28);
      if (u < 0.45) { h = 0.36 * smooth(u / 0.45); y = outP.y + (top - outP.y) * easeOutCubic(u / 0.45); climb = 0.05 + u; }
      else if (u < 0.7) { const k = (u - 0.45) / 0.25; h = 0.36 + 0.34 * k; y = top + Math.sin(k * Math.PI) * 0.1; pitch = -0.55 * Math.sin(k * Math.PI); climb = 0.5; }
      else { const k = (u - 0.7) / 0.3; h = 0.7 + 0.3 * k; y = top + (inP.y - top) * k * k; }
    }
    z.pos.set(outP.x + (inP.x - outP.x) * h, y, outP.z + (inP.z - outP.z) * h);
    z.anim.climb = climb;
    z.anim.speed = climb > 0 ? 0 : 1.2;
    z.anim.attack = 0;
    this._turnTo(z, win.rotY, dt);
    this._place(z, pitch, sx, sy);
    if (u >= 1) this._landInside(z);
  }

  _landInside(z) {
    const g = this.game, e = z.entry;
    const q = this._entries.get(e.id);
    if (q && q.front === z) {
      q.front = q.waiting.shift() || null;
      if (q.front) q.front.state = 'approach';
    }
    z.state = 'chase';
    z.anim.climb = 0;
    z.area = e.win.area;
    z.vy = 0;
    z.entry = null;
    z.navBest = Infinity;
    z.navT = 0;
    if (z.animator && z.animator.kick) z.animator.kick(1.0);
    g.fx.burst(_a.copy(z.pos).setY(z.pos.y + 0.05), { shape: 'puff', count: 4, size: 0.16, speed: 1.2, colors: ['#E8DCC8', '#CDBFA8'] });
    this._place(z);
  }

  // --- screen spawns: telegraph, taffy emerge, drop -----------------------------------------------------
  _screen(z, dt) {
    const g = this.game, e = z.entry, ss = e.ss;
    e.t += dt;
    const f = e.fwd;
    if (e.phase === 'tele') {
      if (e.t >= Z.screenTelegraph) {
        e.phase = 'emerge'; e.t = 0;
        e.tele = null;             // expired on the screens side (its handle may be pooled and reused)
        z.group.visible = true;
        g.audio.play('screen_emerge', { pos: ss.pos });
      }
      return;
    }
    if (e.phase === 'emerge') {
      const u = clamp01(e.t / Z.screenEmerge);
      const s = 0.1 + 0.9 * easeOutBack(u);
      const k = Math.sin(u * Math.PI);
      // Feet stay in the glass; the body leans out of the screen head-first and snaps back like taffy.
      z.pos.set(ss.pos.x - f.x * 0.05 + f.x * 0.25 * u, ss.pos.y - 0.25 * s, ss.pos.z - f.z * 0.05 + f.z * 0.25 * u);
      z.yaw = ss.rotY;
      this._place(z, -1.25 * (1 - 0.35 * u), s * (1 - 0.3 * k), s * (1 + 0.45 * k), s * (1 + 0.25 * k));
      z.anim.speed = 0;
      z.anim.climb = 0.3 + u * 0.6;
      if (u >= 1) { e.phase = 'drop'; e.t = 0; e.inGlass = false; e.from = z.pos.clone(); }
      return;
    }
    // drop: swing the feet out and down to the floor in front of the screen, landing squash.
    const u = clamp01(e.t / 0.42);
    const from = e.from, to = e.land;
    z.pos.set(from.x + (to.x - from.x) * smooth(u), from.y + (to.y - from.y) * u * u + Math.sin(u * Math.PI) * 0.25, from.z + (to.z - from.z) * smooth(u));
    z.anim.climb = 0;
    this._place(z, -1.25 * 0.65 * (1 - easeOutCubic(u)));
    if (u >= 1) {
      z.state = 'chase';
      z.entry = null;
      z.area = g.level.areaAt(z.pos.x, z.pos.z) || z.area;
      if (z.animator && z.animator.kick) z.animator.kick(1.2);
      g.fx.burst(_a.copy(z.pos).setY(z.pos.y + 0.05), { shape: 'static', count: 10, speed: 1.6 });
      this._place(z);
    }
  }

  // --- chase + attack -------------------------------------------------------------------------------------
  _chase(z, dt) {
    const g = this.game, p = g.player, col = g.level.col;
    if (z.stun > 0) {
      z.stun -= dt;
      z.anim.speed = 0; z.anim.attack = 0;
      if (z.state === 'attack') z.state = 'chase';
      this._fall(z, dt);
      this._place(z);
      return;
    }
    // Lure (Tiny Tele): only zombies within its PATH radius (GDD §9.3) are lured; once lured they stay lured.
    if (this.lure && !z.lured && this._lureField && this._lureField.dist(z.pos.x, z.pos.z) <= this.lureR) z.lured = true;
    // Type behaviour first (specials may take over).
    if (z.def.update) {
      let handled = false;
      try { handled = z.def.update(g, z, dt) === true; } catch (err) { this._typeError(z, err); }
      if (z.dead || z.removed) return;
      if (handled) { this._bookkeep(z, dt); this._place(z); return; }
    }
    if (z.gawkT > 0) {
      z.gawkT -= dt;
      if (z.gawkT < GAWK) { z.anim.speed = 0; z.vel.multiplyScalar(Math.exp(-dt * 8)); this._fall(z, dt); this._place(z); return; }
    }

    const lure = this.lure && z.lured ? this.lure : null;
    const goal = lure || p.pos;
    const dx = goal.x - z.pos.x, dz = goal.z - z.pos.z;
    const dist = Math.hypot(dx, dz);
    const dy = goal.y - z.pos.y;

    if (z.state === 'attack') { this._attack(z, dt, dist, dy); this._bookkeep(z, dt); this._place(z); return; }

    // Mesmerized by a lure (Tiny Tele): kneel in a ring around it.
    if (lure && dist < 2.3) {
      z.anim.down = true;
      z.anim.speed = 0;
      z.vel.multiplyScalar(Math.exp(-dt * 10));
      this._turnTo(z, yawTo(dx, dz), dt);
      this._fall(z, dt);
      this._place(z);
      return;
    }
    z.anim.down = false;

    // In reach and nothing solid in between (a thin wall between two rooms must not let a swipe through).
    if (!lure && p.alive && dist < z.def.range && Math.abs(dy) < 1.2 && z.cd <= 0 && z.spawnT <= 0 &&
        col.lineOfSight(_a.set(z.pos.x, z.pos.y + z.height * 0.6, z.pos.z), _b.set(p.pos.x, p.pos.y + 1.0, p.pos.z))) {
      z.state = 'attack';
      z.attackT = 0;
      z.swung = false;
      this._attack(z, dt, dist, dy);
      this._place(z);
      return;
    }

    // Line of sight (refreshed every 0.25 s, staggered).
    z.losT -= dt;
    if (z.losT <= 0) {
      z.losT = 0.25;
      if (dist < 16 && !lure) {
        _a.set(z.pos.x, z.pos.y + z.height * 0.85, z.pos.z);
        _b.set(p.pos.x, p.pos.y + 1.4, p.pos.z);
        z.los = col.lineOfSight(_a, _b);
        z.navStraight = z.los && g.nav.dist(z.pos.x, z.pos.z) < dist * 1.3 + 1.0;
      } else { z.los = false; z.navStraight = false; }
    }
    // Steering: straight at you when close and visible, else the flow field.
    if (!lure && z.los && z.navStraight && dist < LOS_NEAR && Math.abs(dy) < 0.7) _dir.set(dx, 0, dz).normalize();
    else {
      if (lure && this._lureField) this._lureField.dir(z.pos.x, z.pos.z, _dir);
      else g.nav.dir(z.pos.x, z.pos.z, _dir);
      if (_dir.lengthSq() < 1e-6 && dist > 1e-3) _dir.set(dx / dist, 0, dz / dist);
    }
    let speed = z.speed * (z.stagger > 0 ? 0.25 : 1) * (z.spawnT > 0 ? 0 : 1);
    if (!lure && dist < z.def.range * 0.78) speed = 0;
    // Desired velocity + separation.
    const sepW = Math.max(1.2, z.speed * 0.9);
    _c.set(_dir.x * speed + (z.sepX || 0) * sepW, 0, _dir.z * speed + (z.sepZ || 0) * sepW);
    const k = 1 - Math.exp(-dt * ACCEL);
    z.vel.x += (_c.x - z.vel.x) * k;
    z.vel.z += (_c.z - z.vel.z) * k;
    // Face the movement; face the player when close.
    const face = dist < 2.2 && !lure ? yawTo(dx, dz) : (z.vel.x * z.vel.x + z.vel.z * z.vel.z > 0.04 ? yawTo(z.vel.x, z.vel.z) : z.yaw);
    this._turnTo(z, face, dt);
    this._move(z, dt);
    z.anim.speed = Math.hypot(z.vel.x, z.vel.z);
    this._bookkeep(z, dt);
    this._place(z);
  }

  _move(z, dt) {
    z.vy -= GRAVITY * dt;
    _delta.set(z.vel.x * dt, z.vy * dt, z.vel.z * dt);
    const r = this.game.level.col.moveCircle(z.pos, _delta, z.radius, z.height, 0.45);
    if (r.onGround) z.vy = 0;
    z.anim.grounded = true;
  }

  _fall(z, dt) {
    z.vel.x *= Math.exp(-dt * 10); z.vel.z *= Math.exp(-dt * 10);
    this._move(z, dt);
  }

  _attack(z, dt, dist, dy) {
    const g = this.game, p = g.player;
    const wind = z.def.windup || Z.tunedIn.windup;
    const total = wind * 2.5;
    const prev = z.attackT;
    z.attackT += dt;
    z.anim.attack = Math.min(0.99, z.attackT / total);
    z.anim.speed = 0;
    z.vel.multiplyScalar(Math.exp(-dt * 10));
    if (z.attackT < wind) this._turnTo(z, yawTo(p.pos.x - z.pos.x, p.pos.z - z.pos.z), dt * 1.5);
    // Swipe: a small lunge while the arms come down.
    if (z.attackT >= wind && z.attackT < wind + 0.18) {
      _delta.set(-Math.sin(z.yaw) * 1.3 * dt, 0, -Math.cos(z.yaw) * 1.3 * dt);
      if (dist > 0.85) g.level.col.moveCircle(z.pos, _delta, z.radius, z.height, 0.45);
    }
    if (prev < wind && z.attackT >= wind) g.audio.play('zmb_swipe', { pos: z.pos });
    if (!z.swung && z.attackT >= wind + 0.06) {
      z.swung = true;
      z.cd = z.def.cd ?? Z.tunedIn.cd;
      const fwdDot = (-Math.sin(z.yaw) * (p.pos.x - z.pos.x) + -Math.cos(z.yaw) * (p.pos.z - z.pos.z)) / Math.max(1e-3, dist);
      if (!(this.lure && z.lured) && p.alive && dist < (z.def.range || 1.3) + 0.35 && Math.abs(dy) < 1.3 && fwdDot > 0.3) {
        const dmg = z.def.dmg ?? Z.tunedIn.dmg;
        if (p.hurt(dmg, z.pos)) {
          g.events.emit('zombie:attack', { z, dmg });
          _a.subVectors(p.pos, z.pos).setY(0).normalize().multiplyScalar(2.2);
          if (p.knockback) p.knockback(_a);
        }
      }
    }
    this._fall(z, dt);
    if (z.attackT >= total) { z.state = 'chase'; z.anim.attack = 0; }
  }

  // Area, anti-stuck and the straggler rule (chase states only).
  _bookkeep(z, dt) {
    const g = this.game, p = g.player;
    z.area = g.level.areaAt(z.pos.x, z.pos.z) || z.area;
    z.navT += dt;
    if (z.navT < 1) return;
    z.navT = 0;
    const nd = g.nav.dist(z.pos.x, z.pos.z);
    const near = Math.hypot(p.pos.x - z.pos.x, p.pos.z - z.pos.z) < 3;
    // Anti-stuck (GDD §5.10): nav distance has not decreased for 8 s while not attacking. A zombie that keeps walking
    // (>= 35 % of its speed over the last second) is chasing a kiting player, not stuck: training circles keep the
    // path length constant for much longer than 8 s.
    if (!z.stuckPos) z.stuckPos = z.pos.clone();
    const walked = Math.hypot(z.pos.x - z.stuckPos.x, z.pos.z - z.stuckPos.z) >= Math.max(0.25, 0.35 * z.speed);
    z.stuckPos.copy(z.pos);
    const lured = !!(this.lure && z.lured);
    if (nd < z.navBest - 0.4 || walked || near || lured || z.state === 'attack' || z.stun > 0 || z.gawkT > 0) {
      z.navBest = Math.min(z.navBest, nd);
      if (near || lured || walked) z.navBest = nd;
      z.stuckT = 0;
    } else {
      z.stuckT += 1;
      if (z.stuckT >= STUCK_TIME) { this.despawn(z, true); return; }
    }
    // Straggler rule: last zombie of a round, > 40 m of path away for 20 s -> re-enter near the player.
    const R = g.rounds;
    if (R && R.phase === 'active' && R.toSpawn === 0 && z.fromRound != null && this.roundAlive(z.fromRound) === 1 && nd > STRAGGLER_DIST) {
      z.stragT += 1;
      if (z.stragT >= STRAGGLER_TIME) this._restraggle(z);
    } else z.stragT = 0;
  }

  _restraggle(z) {
    const sp = this._pickSpawner(z.def.spawnMode === 'screen' ? { ...z.def, spawnMode: 'both' } : z.def, { nearest: true });
    z.stragT = 0;
    if (!sp) return;
    z.navBest = Infinity;
    z.vel.set(0, 0, 0);
    if (sp.kind === 'screen') this._beginScreen(z, sp.ss);
    else this._beginEntry(z, sp.win);
    this._place(z);
  }

  _turnTo(z, yaw, dt) {
    const d = angDiff(yaw, z.yaw);
    const step = d * Math.min(1, dt * TURN);
    z.yaw += step;
    z.anim.turn = dt > 0 ? step / dt : 0;
  }

  // Writes pos/yaw (+ entry pitch / squash) to the model.
  _place(z, pitch = 0, sx = 1, sy = 1, sz = 1) {
    const G = z.group;
    G.position.copy(z.pos);
    G.rotation.set(pitch, z.yaw, 0, 'YXZ');
    let s = z.scale;
    if (z.spawnT > 0) s *= easeOutBack(1 - z.spawnT / 0.25);
    G.scale.set(s * sx, s * sy, s * (sz === 1 ? sx : sz));
  }

  // Keep the player out of zombie bodies (shared push: zombies are solid, crowds can pin you).
  _blockPlayer() {
    const g = this.game, p = g.player;
    if (!p.alive) return;
    let px = 0, pz = 0;
    for (const z of this.alive) {
      if (z.state !== 'chase' && z.state !== 'attack') continue;
      if (Math.abs(p.pos.y - z.pos.y) > 1.2) continue;
      const dx = p.pos.x - z.pos.x, dz = p.pos.z - z.pos.z;
      const rr = (p.radius || 0.38) + z.radius * 0.9;
      const d2 = dx * dx + dz * dz;
      if (d2 >= rr * rr) continue;
      const d = Math.sqrt(d2) || 1e-3;
      const o = rr - d;
      px += (dx / d) * o * 0.6; pz += (dz / d) * o * 0.6;
      _delta.set(-(dx / d) * o * 0.4, 0, -(dz / d) * o * 0.4);
      g.level.col.moveCircle(z.pos, _delta, z.radius, z.height, 0.45);
      z.group.position.copy(z.pos);
    }
    if (px || pz) {
      _delta.set(px, 0, pz);
      g.level.col.moveCircle(p.pos, _delta, p.radius || 0.38, p.height || 1.75, 0.45);
    }
  }

  // --- animation ----------------------------------------------------------------------------------------
  _animate(z, dt) {
    const a = z.animator;
    if (!a) return;
    z.animAcc += dt;
    // LOD: far or off-screen zombies animate every 3rd frame (the spring integrator substeps the bigger dt).
    if (z.lod > 0 && (this._frame + z.id) % 3 !== 0) return;
    const step = z.animAcc;
    z.animAcc = 0;
    try {
      a.update(step, z.anim);
    } catch (err) {
      this._typeError(z, err);
      return;
    }
    const J = z.rig && z.rig.joints;
    if (!J || !J.shoulderL) return;
    // Clap (Tuned-In, every 4th step): hands swing together.
    const clap = z.anim.clap || 0;
    if (clap > 0) {
      J.shoulderL.rotation.z += clap * 0.32;
      J.shoulderR.rotation.z -= clap * 0.32;
      J.elbowL.rotation.x += clap * 0.25;
      J.elbowR.rotation.x += clap * 0.25;
    }
    // Gawk at the nearest TV (Sign-On), or look at the lure.
    if (z.gawkT > 0 && z.gawkT < GAWK && z.gawkAt && J.head) {
      const want = angDiff(yawTo(z.gawkAt.x - z.pos.x, z.gawkAt.z - z.pos.z), z.yaw);
      const w = Math.sin(clamp01(z.gawkT / GAWK) * Math.PI);
      J.head.rotation.y += THREE.MathUtils.clamp(want, -1.1, 1.1) * Math.min(1, w * 2);
      J.head.rotation.x -= 0.12 * w;
    }
    if (z.anim.down && this.lure && z.lured) {
      J.head.rotation.z += Math.sin(this.game.time.now * 3 + z.id) * 0.18;
    }
  }

  // --- LOD (after the camera moved) ----------------------------------------------------------------------
  _lod() {
    const g = this.game, cam = g.camera;
    this._camPos.copy(cam.position);
    _pv.multiplyMatrices(cam.projectionMatrix, cam.matrixWorldInverse);
    _frustum.setFromProjectionMatrix(_pv);
    const list = this.alive;
    // Shadows: the SHADOW_MAX nearest visible zombies keep their body shadow; the rest rely on the blob.
    const order = this._order;
    order.length = 0;
    for (const z of list) {
      z.camDist = z.pos.distanceTo(this._camPos);
      _sphere.center.set(z.pos.x, z.pos.y + z.height * 0.5, z.pos.z);
      _sphere.radius = z.height * 0.8;
      z.onScreen = _frustum.intersectsSphere(_sphere);
      z.lod = z.onScreen && z.camDist < ANIM_NEAR ? 0 : 1;
      if (z.onScreen) order.push(z);
    }
    order.sort((a, b) => a.camDist - b.camDist);
    for (let i = 0; i < list.length; i++) {
      const z = list[i];
      const bodies = z.model && z.model.bodies;
      if (bodies) {
        const cast = z.onScreen && order.indexOf(z) < SHADOW_MAX;
        for (const m of bodies) m.castShadow = cast;
      }
      const cards = z.model && z.model.cards;
      if (cards && cards.length) {
        const vis = z.camDist < CARD_LOD;
        for (const c of cards) c.visible = vis;
      }
      const det = z.model && z.model.details;
      if (det && det.length) {
        const vis = z.camDist < DETAIL_LOD || this._oneTake;      // ONE TAKE stars live on the veil
        for (const c of det) c.visible = vis;
      }
    }
    order.length = 0;
  }

  // ------------------------------------------------------------------------------------------------ damage
  damage(z, amount, info = {}) {
    const g = this.game;
    if (!z || z.dead || z.removed || !(amount > 0)) return false;
    const frame = g.time.frame;
    let zone = info.zone;
    let head = info.head;
    let mul = 1;
    let zoneMul;
    if (zone === undefined && z._rayFrame === frame) { zone = z._rayZone; zoneMul = z._rayMul; if (head === undefined) head = z._rayHead; }
    if (head === undefined) head = zone === 'head';
    head = !!head;
    if (zone === undefined) zone = head ? 'head' : 'torso';
    if (zoneMul === undefined) zoneMul = zone === 'limb' ? 0.8 : this._zoneMul(z, zone);
    mul *= zoneMul;
    if (z.state === 'screen' && z.entry && z.entry.inGlass) mul *= Z.screenMul;
    let dmg = amount * mul;
    const full = { ...info, head, zone };
    if (z.def.onDamage) {
      try { const r = z.def.onDamage(g, z, dmg, full); if (typeof r === 'number' && Number.isFinite(r)) dmg = r; } catch (err) { this._typeError(z, err); }
    }
    if (this._oneTake && z.type !== 'boss_baron') {
      if (z.def.oneTakeMul) dmg *= z.def.oneTakeMul;
      else dmg = Math.max(dmg, z.hp);
    }
    if (!(dmg > 0)) return false;
    z.hp -= dmg;
    const killed = z.hp <= 0;
    const weaponId = info.weaponId ?? null;
    const cause = info.cause || (weaponId === 'melee' ? 'melee' : 'bullet');

    // Reaction: squash + head spring, lean back, 0.15 s stagger, shove.
    if (!killed) {
      z.anim.hurt = 1;
      z.stagger = Math.max(z.stagger, STAGGER);
      if (z.animator && z.animator.kick) z.animator.kick(Math.min(1.2, 0.45 + dmg / Math.max(60, z.maxHp) * 1.5));
    }
    if (info.knockback && info.dir) {
      const kb = Math.min(3, info.knockback) * (z.type === 'big_shot' ? 0.25 : 1);
      z.knock.x += info.dir.x * kb * 9; z.knock.z += info.dir.z * kb * 9;
    }
    // Hit FX: confetti + felt fluff (never blood).
    if (info.point && z._fxFrame !== frame) {
      z._fxFrame = frame;
      const n = info.dir ? _a.copy(info.dir).negate() : null;
      g.fx.burst(info.point, { shape: 'confetti', count: 5, speed: 3, size: 0.055, dir: n || undefined, cone: 1.3, life: 0.9 });
      g.fx.burst(info.point, { shape: 'puff', count: 2, size: 0.09, life: 0.45, speed: 1.2, colors: ['#E4F2E6', '#F4F1E8'] });
    }
    if (!killed && this._hitSfx < 2) { this._hitSfx++; g.audio.play('zmb_hit', { pos: info.point || z.pos, rate: 0.9 + Math.random() * 0.25 }); }

    g.events.emit('zombie:hit', { z, dmg, head, weaponId, point: info.point || z.pos, zone, cause, upgraded: !!info.upgraded });
    // Points (GDD §6.3).
    if (info.points !== false && !NO_POINTS.has(cause)) {
      if (!killed) {
        const key = `${frame}|${weaponId}`;
        if (z._hitKey !== key) { z._hitKey = key; g.economy.add(P.hit, 'hit'); }
      }
    }
    if (info.hitmarker !== false && g.hud && typeof g.hud.hitmarker === 'function' && z._hmFrame !== frame) {
      z._hmFrame = frame;
      g.hud.hitmarker(head, killed);
    }
    if (killed) this._kill(z, { ...full, weaponId, cause }, info.points !== false);
    return killed;
  }

  _zoneMul(z, zone) {
    if (!z.hitZones) return 1;
    for (const hz of z.hitZones) if (hz.zone === zone) return hz.mul ?? 1;
    return 1;
  }

  kill(z, info = {}) {
    if (!z || z.dead || z.removed) return false;
    this._kill(z, { cause: 'script', ...info }, info.points !== false);
    return true;
  }

  _kill(z, info, award) {
    const g = this.game;
    const cause = info.cause || 'bullet';
    const head = !!info.head;
    const melee = cause === 'melee' || info.weaponId === 'melee';
    z.hp = 0;
    z.dead = true;
    z.state = 'dying';
    z.dieT = 0;
    z.anim.attack = 0; z.anim.climb = 0; z.anim.down = false; z.anim.hurt = 0.6;
    const i = this.alive.indexOf(z);
    if (i >= 0) this.alive.splice(i, 1);
    this.dying.push(z);
    this._leaveEntry(z);
    if (z.blob) { z.blob.remove(); z.blob = null; }
    this._stars.remove(z);
    if (award) {
      const pts = killPoints(cause, head, info.weaponId);
      if (pts > 0) {
        g.economy.add(pts, 'kill');
        const bonus = z.def.points && z.def.points.killBonus;
        if (bonus) g.economy.add(bonus, 'kill_bonus');
      }
    }
    // Custom death (specials) or the default topple. info.corpse === false: another system (wonder weapons) animates
    // a clone of the body, so no death visuals here (the type's onDeath still runs for its side effects).
    const corpse = info.corpse !== false;
    let dur;
    if (z.def.onDeath) {
      try { dur = z.def.onDeath(g, z, info); } catch (err) { this._typeError(z, err); }
    }
    const inTele = z.entry && z.entry.kind === 'screen' && z.entry.phase === 'tele';
    if (!corpse) z.deathDur = 0;
    else if (typeof dur === 'number' && dur >= 0) z.deathDur = dur;
    else if (inTele) {
      // Killed inside the screen during the telegraph: it fizzles out in the glass.
      z.deathDur = 0;
      try { if (z.entry.tele && z.entry.tele.cancel) z.entry.tele.cancel(); } catch (err) { /* screens is someone else's */ }
      g.fx.burst(z.entry.ss.pos, { shape: 'static', count: 24, speed: 2.2 });
      g.fx.burst(z.entry.ss.pos, { shape: 'confetti', count: 10, colors: PAL.BARS });
      g.audio.play('zmb_death_static', { pos: z.entry.ss.pos, tv: true });
    } else {
      z.deathDur = null;
      z.dieDir = info.dir ? new THREE.Vector3(info.dir.x, 0, info.dir.z).normalize() : new THREE.Vector3(Math.sin(z.yaw), 0, Math.cos(z.yaw));
      // Topple backward = away from the shooter: turn the body most of the way toward the shot.
      if (info.dir) z.yaw += angDiff(yawTo(-info.dir.x, -info.dir.z), z.yaw) * 0.6;
      z.vy = 0;
      if (head && cause !== 'cancelled') this._popHead(z);
      _a.copy(z.pos).setY(z.pos.y + z.height * 0.75);
      g.fx.burst(_a, { shape: 'confetti', count: 10, speed: 3.5 });
      if (z.group.visible) this._stars.add(z, DIE_LIE + 0.1, 3, 0.24 * z.scale);
      g.audio.play(head ? 'zmb_head_pop' : 'zmb_groan', { pos: z.pos, rate: head ? 1 : 0.7, vol: head ? 1 : 0.7 });
    }
    g.events.emit('zombie:kill', { z, weaponId: info.weaponId ?? null, head, melee, pos: z.pos.clone(), cause });
    if (g.rounds && typeof g.rounds.onZombieKilled === 'function') g.rounds.onZombieKilled(z);
  }

  _leaveEntry(z) {
    if (!z.entry || z.entry.kind === 'screen') return;
    const q = this._entries.get(z.entry.id);
    if (!q) return;
    if (q.front === z) {
      q.front = q.waiting.shift() || null;
      if (q.front && q.front.state === 'queue') q.front.state = 'approach';
    } else {
      const k = q.waiting.indexOf(z);
      if (k >= 0) q.waiting.splice(k, 1);
    }
  }

  _updateDying(dt) {
    const g = this.game;
    for (let i = this.dying.length - 1; i >= 0; i--) {
      const z = this.dying[i];
      z.dieT += dt;
      if (z.deathDur != null) {
        if (z.def.updateDeath) {
          try { z.def.updateDeath(g, z, dt, z.dieT); } catch (err) { this._typeError(z, err); }
        }
        if (z.dieT >= z.deathDur) { this.dying.splice(i, 1); this._remove(z); }
        continue;
      }
      const t = z.dieT;
      // Topple backward with a bounce, sliding a little with the hit.
      z.anim.dead = Math.min(1, t / DIE_TOPPLE);
      z.anim.speed = 0;
      z.anim.hurt = Math.max(0, z.anim.hurt - dt / 0.3);
      if (t < 0.3 && z.dieDir) {
        _delta.copy(z.dieDir).multiplyScalar((0.3 - t) * 2.2 * dt);
        _delta.y = 0;
        g.level.col.moveCircle(z.pos, _delta, z.radius * 0.6, 0.5, 0.45);
      }
      // Died mid-air (vault, fence, screen): fall to the floor below.
      const fy = g.level.col.floorAt(z.pos.x, z.pos.z, z.pos.y + 0.1);
      if (fy > -Infinity && z.pos.y > fy + 0.01) {
        z.vy -= GRAVITY * dt;
        z.pos.y = Math.max(fy, z.pos.y + z.vy * dt);
        if (z.pos.y <= fy && z.animator && z.animator.kick) z.animator.kick(0.8);
      } else z.vy = 0;
      if (z.animator) {
        try { z.animator.update(dt, z.anim); } catch (err) { /* keep dying */ }
      }
      let s = z.scale;
      if (t > DIE_LIE) {
        const k = clamp01((t - DIE_LIE) / DIE_POP);
        s *= 1 - smooth(k);
        if (!z.dissolved) this._dissolve(z);
      }
      z.group.position.copy(z.pos);
      z.group.rotation.set(0, z.yaw, 0, 'YXZ');
      z.group.scale.set(s * (1 + (t > DIE_LIE ? 0.3 : 0)), Math.max(0.001, s), s * (1 + (t > DIE_LIE ? 0.3 : 0)));
      if (t >= DIE_LIE + DIE_POP) { this.dying.splice(i, 1); this._remove(z); }
    }
  }

  // 30 static quads + 12 colour-bar confetti; the ticket stub flutters down.
  _dissolve(z) {
    const g = this.game;
    z.dissolved = true;
    if (!z.group.visible) return;
    _a.copy(z.pos).setY(z.pos.y + 0.35);
    g.fx.burst(_a, { shape: 'static', count: 30, speed: 2.4, size: 0.1, life: 0.9 });
    g.fx.burst(_a, { shape: 'confetti', count: 12, colors: PAL.BARS, speed: 3.2 });
    g.audio.play('zmb_death_static', { pos: z.pos });
    if (z.type === 'tuned_in') {
      _b.copy(z.pos).setY(z.pos.y + 0.55);
      const fy = g.level.col.floorAt(z.pos.x, z.pos.z, z.pos.y + 0.5);
      this._tickets.add(_b, fy > -Infinity ? fy : z.pos.y);
    }
  }

  _remove(z) {
    if (z.removed) return;
    z.removed = true;
    const g = this.game;
    this._leaveEntry(z);
    if (z.entry && z.entry.kind === 'screen' && z.entry.phase === 'tele' && z.entry.tele) {
      try { z.entry.tele.cancel(); } catch (err) { /* screens is someone else's */ }
    }
    if (z.blob) { z.blob.remove(); z.blob = null; }
    this._stars.remove(z);
    try {
      if (z.def.release) z.def.release(g, z);
      else if (z.model && z.model.group) releaseModel(z.model);
    } catch (err) { this._typeError(z, err); }
    if (z.group) z.group.removeFromParent();
  }

  // --- head cork-pop -------------------------------------------------------------------------------------
  _headProxy(variant) {
    const list = this._heads.get(variant);
    while (list && list.length) { const h = list.pop(); if ((h.model.gen || 0) === (charOpt.gen || 0)) return h; }
    return this._buildHead(variant);
  }

  _buildHead(variant) {
    const g = this.game;
    let m;
    try {
      m = buildVariant(g, 'tuned_in', variant);
    } catch (err) { return null; }
    if (!m || !m.rig || !m.rig.joints || !m.rig.joints.neck) return null;
    const J = m.rig.joints;
    // Collapse everything but the head: hips ~0, neck ×1/ε restores the head at full size.
    const EPS = 1e-3;
    J.hips.scale.setScalar(EPS);
    J.neck.scale.setScalar(1 / EPS);
    for (const c of m.cards || []) c.visible = false;
    for (const b of m.bodies || []) b.castShadow = false;
    m.group.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.frustumCulled = false; } });
    const pivot = new THREE.Group();
    pivot.name = 'zombie:poppedHead';
    pivot.add(m.group);
    m.group.updateMatrixWorld(true);
    const hc = m.head.getWorldPosition(new THREE.Vector3());
    m.group.position.sub(hc);
    this.game.render.setLayerRecursive(pivot, LAYERS.ZOMBIES);
    return { pivot, model: m, variant, vel: new THREE.Vector3(), spin: new THREE.Vector3(), t: 0, bounces: 0 };
  }

  _prewarmHeads(variant, n) {
    let list = this._heads.get(variant);
    if (!list) this._heads.set(variant, (list = []));
    for (let i = list.length - 1; i >= 0; i--) if ((list[i].model.gen || 0) !== (charOpt.gen || 0)) list.splice(i, 1);
    while (list.length < n) {
      const h = this._buildHead(variant);
      if (!h) break;
      list.push(h);
    }
  }

  _releaseHead(h) {
    h.pivot.removeFromParent();
    let list = this._heads.get(h.variant);
    if (!list) this._heads.set(h.variant, (list = []));
    if (list.length < 4 && (h.model.gen || 0) === (charOpt.gen || 0)) list.push(h);
  }

  _popHead(z) {
    const g = this.game;
    const J = z.rig && z.rig.joints;
    if (!J || !J.head || !z.model) {
      z.head && z.head.getWorldPosition(_a);
      g.fx.burst(_a, { shape: 'static', count: 14 });
      g.hitStop(0.03);
      return;
    }
    z.head.getWorldPosition(_a);
    z.group.updateMatrixWorld(true);
    J.head.getWorldQuaternion(_q);
    J.head.scale.setScalar(0.001);
    g.hitStop(0.03);
    g.fx.burst(_a, { shape: 'static', count: 12, speed: 2, size: 0.07 });
    g.fx.burst(_a, { shape: 'star', count: 5, speed: 3 });
    const h = z.model.variant ? this._headProxy(z.model.variant) : null;
    if (!h) return;
    h.pivot.position.copy(_a);
    h.pivot.quaternion.copy(_q);
    h.pivot.scale.setScalar(z.scale);
    const back = z.dieDir || _b.set(0, 0, 1);
    h.vel.set(back.x * 1.6 + (Math.random() - 0.5), 5.2 + Math.random() * 1.2, back.z * 1.6 + (Math.random() - 0.5));
    h.spin.set(-6 - Math.random() * 6, (Math.random() - 0.5) * 8, (Math.random() - 0.5) * 6);
    h.t = 0; h.bounces = 0; h.floor = g.level.col.floorAt(_a.x, _a.z, _a.y) ;
    if (!(h.floor > -Infinity)) h.floor = z.pos.y;
    h.r = z.headR * z.scale;
    g.scene.add(h.pivot);
    this._flying.push(h);
  }

  _updateHeads(dt) {
    const g = this.game;
    for (let i = this._flying.length - 1; i >= 0; i--) {
      const h = this._flying[i];
      h.t += dt;
      const P0 = h.pivot.position;
      h.vel.y -= 18 * dt;
      P0.addScaledVector(h.vel, dt);
      _e.set(h.spin.x * dt, h.spin.y * dt, h.spin.z * dt);
      h.pivot.quaternion.multiply(_q.setFromEuler(_e));
      const fy = h.floor + h.r * 0.9;
      if (P0.y < fy && h.vel.y < 0) {
        P0.y = fy;
        h.bounces++;
        h.vel.y = -h.vel.y * 0.45;
        h.vel.x *= 0.6; h.vel.z *= 0.6;
        h.spin.multiplyScalar(0.55);
        h.pivot.scale.multiply(_s.set(1.15, 0.8, 1.15));
        g.audio.play('zmb_hit', { pos: P0, rate: 1.5 + h.bounces * 0.2, vol: 0.6 });
      }
      // Squash recovers.
      h.pivot.scale.lerp(_s.setScalar(h.pivot.scale.x > 0 ? (h.baseS || (h.baseS = h.pivot.scale.y)) : 1), Math.min(1, dt * 10));
      if (h.bounces >= 2 && !h.endT) h.endT = h.t + 0.18;
      if ((h.endT && h.t >= h.endT) || h.t > 2.2) {
        g.fx.burst(P0, { shape: 'static', count: 18, speed: 1.8, size: 0.09 });
        g.fx.burst(P0, { shape: 'puff', count: 4, size: 0.14, colors: ['#DDE3EA', '#F4F1E8'] });
        g.audio.play('zmb_death_static', { pos: P0, vol: 0.6 });
        this._flying.splice(i, 1);
        h.baseS = 0;
        h.endT = 0;
        this._releaseHead(h);
      }
    }
  }

  // ------------------------------------------------------------------------------------------------ queries
  raycast(origin, dir, maxDist = 80) {
    const frame = this.game.time.frame;
    let best = null, bd = maxDist;
    for (const z of this.alive) {
      if (z.removed) continue;
      if (z.state === 'screen' && z.entry && z.entry.phase === 'tele') {
        const t = raySphere(origin, dir, z.entry.ss.pos, 0.42);
        if (t <= bd) { bd = t; best = z; best._tmp = { zone: 'torso', head: false, mul: 1 }; }
        continue;
      }
      _sphere.center.set(z.pos.x, z.pos.y + z.height * z.scale * 0.5, z.pos.z);
      const R = z.height * z.scale * 0.62 + 0.35;
      if (raySphere(origin, dir, _sphere.center, R) > bd) continue;
      const h = this._rayZombie(z, origin, dir, bd);
      if (h && h.dist <= bd) { bd = h.dist; best = z; best._tmp = { zone: h.zone, head: h.head, mul: h.mul }; }
    }
    if (!best) return null;
    const info = best._tmp;
    best._rayFrame = frame;
    best._rayZone = info.zone;
    best._rayHead = info.head;
    best._rayMul = info.mul;
    return { z: best, head: info.head, dist: bd, point: origin.clone().addScaledVector(dir, bd), zone: info.zone };
  }

  _rayZombie(z, o, d, max) {
    if (typeof z.hitTest === 'function') {
      try { return z.hitTest(o, d, max); } catch (err) { this._typeError(z, err); return null; }
    }
    const zones = z.hitZones;
    let bt = Infinity, be = Infinity, bz = null;
    if (!zones) {
      z.head.getWorldPosition(_a);
      const th = raySphere(o, d, _a, z.headR);
      _a.copy(z.pos).setY(z.pos.y + 0.25);
      _b.copy(z.pos).setY(z.pos.y + z.height - z.headR * 2);
      const tb = rayCapsule(o, d, _a, _b, z.radius * 0.75);
      if (th === Infinity && tb === Infinity) return null;
      _hit.dist = Math.min(th, tb); _hit.head = th <= tb; _hit.zone = _hit.head ? 'head' : 'torso'; _hit.mul = 1;
      return _hit;
    }
    for (const hz of zones) {
      if (!hz.bone) continue;
      const off = hz.offset;
      _a.set(off ? off[0] : 0, off ? off[1] : 0, off ? off[2] : 0);
      hz.bone.localToWorld(_a);
      let t;
      const r = hz.r * z.scale;
      if (hz.shape === 'capsule') {
        const o2 = hz.offset2;
        _b.set(o2 ? o2[0] : 0, o2 ? o2[1] : 0, o2 ? o2[2] : 0);
        (hz.bone2 || hz.bone).localToWorld(_b);
        t = rayCapsule(o, d, _a, _b, r);
      } else t = raySphere(o, d, _a, r);
      // Head wins near-ties (the head sphere overlaps the neck end of the torso).
      const te = hz.head ? t - 0.06 : t;
      if (te < be) { be = te; bt = t; bz = hz; }
    }
    if (!bz || bt > max) return null;
    _hit.dist = bt; _hit.zone = bz.zone; _hit.head = !!bz.head; _hit.mul = bz.mul ?? 1;
    return _hit;
  }

  inRadius(pos, r, out = []) {
    out.length = 0;
    for (const z of this.alive) {
      if (z.removed) continue;
      const y0 = z.pos.y, y1 = z.pos.y + z.height * z.scale;
      const dy = pos.y < y0 ? y0 - pos.y : pos.y > y1 ? pos.y - y1 : 0;
      const dx = pos.x - z.pos.x, dz = pos.z - z.pos.z;
      const d = Math.sqrt(dx * dx + dz * dz + dy * dy) - z.radius * 0.5;
      if (d <= r) out.push(z);
    }
    return out;
  }

  nearest(pos, maxDist = Infinity) {
    let best = null, bd = maxDist;
    for (const z of this.alive) {
      const d = z.pos.distanceTo(pos);
      if (d < bd) { bd = d; best = z; }
    }
    return best;
  }

  count(typeId = null) {
    if (!typeId) return this.alive.length;
    let n = 0;
    for (const z of this.alive) if (z.type === typeId) n++;
    return n;
  }

  // Living zombies spawned by the round with this token.
  roundAlive(token) {
    let n = 0;
    for (const z of this.alive) if (z.fromRound === token) n++;
    return n;
  }

  // ------------------------------------------------------------------------------------------------ control
  killAll(cause = 'cancelled') {
    for (const z of this.alive.slice()) if (z.type !== 'boss_baron') this._kill(z, { cause }, false);
  }

  stun(z, seconds) {
    if (!z || z.dead) return;
    z.stun = Math.max(z.stun, seconds);
    if (z.state === 'attack') { z.state = 'chase'; z.anim.attack = 0; }
    if (seconds > 0.4 && (z.state === 'chase' || z.state === 'attack')) this._stars.add(z, seconds, 3, 0.22 * z.scale);
  }

  stunAll(seconds) {
    for (const z of this.alive) this.stun(z, seconds);
  }

  knockback(z, vec) {
    if (!z || z.dead) return;
    z.knock.x += vec.x * 9; z.knock.z += vec.z * 9;
  }

  freezeAll(on) {
    this.frozen = !!on;
  }

  // setLure(pos|null, radius = Infinity): radius = PATH distance (metres) inside which zombies are lured (Tiny Tele 15);
  // Infinity keeps the old behaviour (every zombie, via nav.setGoalOverride).
  setLure(pos, radius = Infinity) {
    this.lure = pos ? (pos.isVector3 ? pos.clone() : new THREE.Vector3(pos[0], pos[1], pos[2])) : null;
    this.lureR = radius;
    this._lureField = null;
    const nav = this.game.nav;
    if (this.lure && Number.isFinite(radius) && nav.localField) {
      nav.setGoalOverride(null);
      this._lureField = nav.localField(this.lure.x, this.lure.z, radius);
      for (const z of this.alive) z.lured = this._lureField.dist(z.pos.x, z.pos.z) <= radius;
    } else {
      nav.setGoalOverride(this.lure);
      for (const z of this.alive) z.lured = !!this.lure;
    }
    if (!this.lure) for (const z of this.alive) { z.anim.down = false; z.lured = false; }
  }

  // Silent removal: no points, no kill event. requeue = the round spawns it again (anti-stuck).
  despawn(z, requeue = true) {
    if (!z || z.removed) return;
    const g = this.game;
    const i = this.alive.indexOf(z);
    if (i >= 0) this.alive.splice(i, 1);
    const j = this.dying.indexOf(z);
    if (j >= 0) this.dying.splice(j, 1);
    z.dead = true;
    this._remove(z);
    g.events.emit('zombie:despawn', { z });
    if (requeue && z.fromRound != null && g.rounds && typeof g.rounds.requeue === 'function') g.rounds.requeue(z);
  }

  // Everything dissolves into static without points (boss intro, game scripts).
  despawnAll({ fx = true, requeue = false } = {}) {
    for (const z of this.alive.slice()) {
      if (fx && z.group.visible) {
        _a.copy(z.pos).setY(z.pos.y + 0.8);
        this.game.fx.burst(_a, { shape: 'static', count: 16, speed: 2 });
      }
      this.despawn(z, requeue);
    }
  }

  // Sign-On (GDD §7.8): living zombies stop and turn their heads toward the nearest TV for 1.5 s as the wave passes.
  _signOnGawk() {
    const g = this.game, L = g.level;
    const lever = (L.anchors && L.anchors.sign_on_lever && L.anchors.sign_on_lever.pos) || LEVER;
    const screens = Object.values(L.screenSpawns || {});
    for (const z of this.alive) {
      if (z.state !== 'chase') continue;
      const delay = Math.max(0, z.pos.distanceTo(lever) / 15 - 2.6);
      z.gawkT = GAWK + Math.min(2.5, delay);
      let best = null, bd = Infinity;
      for (const s of screens) { const d = s.pos.distanceTo(z.pos); if (d < bd) { bd = d; best = s.pos; } }
      z.gawkAt = best || lever;
    }
  }
}
