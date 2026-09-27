// Economy + purchasable interactables (ARCHITECTURE §10, GDD §5.3 doors, §5.4 barricades, §6.3–§6.4, §9.1
// wall-buys, §14 prompt rules). Owner: econ.
//
// POINTS
//   economy.points (int, never negative)   economy.earned / economy.spent (run totals)
//   economy.multiplier   1, or 2 during SWEEPS WEEK. Plain read/write (powerups.js writes it); reads also return 2
//                        while powerups.active.sweeps_week > 0, so either side can drive it.
//   add(n, reason='misc') -> points actually added (n × multiplier, rounded, >= 0)
//   canAfford(n) -> bool       spend(n, reason='buy') -> bool (short: emits points:denied {cost}, nothing spent)
//   Every change emits points:change {points, delta, reason} and calls hud.pointsPopup(delta).
//   Start points: params.points, else T.player.startPoints.
//
// PURCHASES (each also reachable without the interact prompt — used by tests / other systems)
//   buyDoor(doorId) -> bool          spend T.doors[id] then level.openDoor(id) (the door plays its own beat: poof,
//                                    chain snap, D5 keypad motif, crowd ooh). Short: bzzt + the door rattles.
//   buyWallbuy(anchorId) -> bool     wb_pump / wb_mp7 / wb_m16: first buy pops the prop gun off the poster into the
//                                    hands (0.3 s arc; weapons.give(id, {source:'wallbuy'}) on the catch -> boing) and
//                                    Duke winks (poster canvas swap, kept while the gun is owned). Owned: ammo refill
//                                    (T.wallbuys[id][1], or T.wallbuys.upgradedAmmo when upgraded); no prompt while full.
//                                    wb_grenades ("Tube-O-Matic" case, T.wallbuys.grenades): the missing tubes hop out
//                                    into the hands, +1 grenade per tube caught (up to T.player.grenadesMax).
//   repairWindow(windowId) -> bool   level.windows[id].repairBoard() (+ T.points.board, capped T.points.boardCap per round)
//   priceOf(interactId | doorId | anchorId) -> cost | null (what the prompt would show now)
//
// INTERACTABLES (game.interact; prompts are only {cost} / {} + hold ring, never names — GDD §14)
//   econ:door:<doorId>:<areaId>  one per face of every closed paid door (DY has none: it opens itself at power);
//                                each declares its face normal
//   econ:wb:<anchorId>           wall-buys and the grenade case, facing = anchor rotY (front side of the wall only)
//   interact.js also requires line of sight from the player's head (architecture colliders): no buying through walls
//   econ:win:<windowId>          boarded windows missing boards: hold E, one board per 0.6 s while E stays down
//
// EVENTS emitted: points:change, points:denied (canonical) and economy:buy {kind:'door'|'wallbuy'|'ammo'|
//   'grenades', id, cost}. Listens: round:start (resets the board-points cap).
// SOUNDS: ui_buy (ka-ching) / ui_denied (bzzt) / wallbuy_boing come from audio.js hookups (spend, points:denied,
//   weapon:acquire source 'wallbuy' on the catch); door beats + crowd_ooh from level/doors (D5: door_keypad_motif);
//   board_repair from windows.js. Played here: pump ammo reload_shell x2 + wpn_pump_rack, other ammo reload_mag x2,
//   dry_fire as the spring-clip / glass-flap clicks, grenade_bounce per caught tube + wallbuy_boing (tube refill).
// FEEL: door buy = gold stars + confetti + small shake, denied = the blocker rattles; wall-buy = poster wobble on
//   its top edge, wink sparkle, clips spring open, cubic-bezier hop with a barrel roll, stretch and a star trail,
//   catch sparkle + cam kick, gun pops back (easeOutBack) and the clips snap shut; ammo = gun hops on its clips +
//   brass confetti; denied = the gun shivers. Tube-O-Matic: marquee chase (all lit while busy), glass flap swings up,
//   tubes pop out one by one into the hands, rise back into the sockets. Barricade: dust puff + sparks + tiny shake.
//
// Frame driver: Game's UPDATE_ORDER has no 'economy' entry, so update(dt) is also driven from a render pre-pass
// (skipped on frames where Game already called update, and outside 'playing' / 'down'). World dt: every tween
// freezes with time.scale = 0 / hitStop. The barricade hold loop re-arms interact's one-completion-per-press latch
// (interact._holdDone) while E stays down, so a held E keeps repairing.

import * as THREE from 'three';
import { T, PAL } from '../core/config.js';
import { getCard } from '../gfx/cards.js';
import { buildWeapon } from '../props/weapons.js';
import * as K from '../props/kit.js';
import { mergeByMaterial } from '../core/geo.js';

const WIN_BOARDS = 6;
const REPAIR_HOLD = 0.6;       // s per board (GDD §5.4 task spec)
const FLIGHT = 0.3;            // wall-buy pop-off arc (GDD §9.1)
const RESTOCK = 1.4;           // s after a buy until the poster gun / case tubes come back
const GLINT_EVERY = 6;         // GDD §6.7: the Pump poster's chrome glints every 6 s
const DOOR_R = 2.3, WB_R = 1.9, WIN_R = 2.1;

const TAU = Math.PI * 2;
const clamp = THREE.MathUtils.clamp;
const easeOutBack = (t, s = 2.2) => 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2;
const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2);
const easeOutBounce = (t) => {
  const n = 7.5625, d = 2.75;
  if (t < 1 / d) return n * t * t;
  if (t < 2 / d) return n * (t -= 1.5 / d) * t + 0.75;
  if (t < 2.5 / d) return n * (t -= 2.25 / d) * t + 0.9375;
  return n * (t -= 2.625 / d) * t + 0.984375;
};

const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _v3 = new THREE.Vector3();
const _q2 = new THREE.Quaternion();
const _qRoll = new THREE.Quaternion();
const _X = new THREE.Vector3(1, 0, 0);
const _m = new THREE.Matrix4();
const _sc = new THREE.Vector3();
const _box = new THREE.Box3();
const _size = new THREE.Vector3();

export class Economy {
  constructor(game) {
    this.game = game;
    this.points = 0;
    this._mult = 1;
    this.earned = 0;
    this.spent = 0;
    this.doors = {};        // doorId -> { door, cost, items: [interactId] }
    this.wallbuys = {};     // anchorId -> wall-buy state (poster or case)
    this.windows = {};      // windowId -> { win, itemId }
    this._items = new Map(); // interactId -> { kind, id }
    this._boardPts = 0;
    this._fx = [];          // live cosmetic tweens { t, dur, fn(k, dt), done? }
    this._rattles = [];
    this._built = false;
    this._frameSeen = -1;
    this._time = 0;
    this._starTex = null;
  }

  // ================================================================================================ points
  get multiplier() {
    const pu = this.game.powerups;
    const sweeps = pu && pu.active && pu.active.sweeps_week > 0 ? 2 : 1;
    return Math.max(this._mult, sweeps);
  }

  set multiplier(v) {
    this._mult = Number.isFinite(v) && v > 0 ? v : 1;
  }

  add(n, reason = 'misc') {
    if (!Number.isFinite(n) || n <= 0) return 0;
    const delta = Math.max(0, Math.round(n * this.multiplier));
    if (delta === 0) return 0;
    this.points += delta;
    this.earned += delta;
    this._changed(delta, reason);
    return delta;
  }

  canAfford(n) {
    return this.points >= n;
  }

  spend(n, reason = 'buy') {
    if (!Number.isFinite(n) || n <= 0) return true;
    n = Math.round(n);
    if (this.points < n) {
      this.game.events.emit('points:denied', { cost: n });
      return false;
    }
    this.points = Math.max(0, this.points - n);
    this.spent += n;
    this._changed(-n, reason);
    return true;
  }

  _changed(delta, reason) {
    const g = this.game;
    g.events.emit('points:change', { points: this.points, delta, reason });
    if (g.hud && g.hud.pointsPopup) g.hud.pointsPopup(delta);
  }

  // ============================================================================================= lifecycle
  init() {
    const g = this.game;
    g.events.on('round:start', () => { this._boardPts = 0; });
    if (!g.level || !g.level.built) return;
    this._safe('doors', () => this._setupDoors());
    this._safe('wallbuys', () => this._setupWallbuys());
    this._safe('windows', () => this._setupWindows());
    this._built = true;
    if (g.render && g.render.addPrePass) this._unsub = g.render.addPrePass(() => this._drive());
  }

  reset() {
    const p = this.game.params.points;
    this.points = Number.isFinite(p) ? Math.max(0, Math.floor(p)) : T.player.startPoints;
    this._mult = 1;
    this.earned = 0;
    this.spent = 0;
    this._boardPts = 0;
    this._fx.length = 0;
    for (const r of this._rattles) r.restore();
    this._rattles.length = 0;
    for (const w of Object.values(this.wallbuys)) this._safe('reset:' + w.id, () => w.reset());
    this.game.events.emit('points:change', { points: this.points, delta: 0, reason: 'start' });
  }

  update(dt) {
    this._frameSeen = this.game.time.frame;
    this._tick(dt);
  }

  _drive() {
    const g = this.game;
    if (this._frameSeen === g.time.frame) return;
    if (g.state !== 'playing' && g.state !== 'down') return;
    this._frameSeen = g.time.frame;
    this._tick(g.time.dt);
  }

  _tick(dt) {
    if (!this._built) return;
    try {
      this._step(dt);
    } catch (err) {
      const now = performance.now();
      if (!(now - (this._errT || -1e9) < 5000)) { this._errT = now; console.error('[system:economy]', err); }
    }
  }

  _step(dt) {
    this._time += dt;
    this._keepRepairing();
    for (const w of Object.values(this.wallbuys)) w.update(dt, this._time);
    for (let i = this._rattles.length - 1; i >= 0; i--) if (!this._rattles[i].step(dt)) this._rattles.splice(i, 1);
    for (let i = this._fx.length - 1; i >= 0; i--) {
      const f = this._fx[i];
      f.t += dt;
      const k = Math.min(1, f.t / f.dur);
      f.fn(k, dt);
      if (k >= 1) this._fx.splice(i, 1);
    }
  }

  _safe(name, fn) {
    try {
      return fn();
    } catch (err) {
      console.error(`[economy:${name}]`, err);
      return undefined;
    }
  }

  _tween(dur, fn) {
    this._fx.push({ t: 0, dur, fn });
  }

  // ================================================================================================= doors
  _setupDoors() {
    const g = this.game, L = g.level;
    for (const d of Object.values(L.doors)) {
      if (d.requiresPower) continue;
      const cost = T.doors[d.id] ?? d.cost;
      if (!(cost > 0)) continue;
      const entry = { door: d, cost, items: [] };
      const [cx, cz] = d.center;
      for (const areaId of d.areas) {
        const sign = areaId === d.areas[1] ? 1 : -1;
        const floorY = L.areas[areaId] ? L.areas[areaId].floorY || 0 : 0;
        const id = `econ:door:${d.id}:${areaId}`;
        const pos = new THREE.Vector3(cx + d.normal.x * sign * 0.35, floorY + 1.1, cz + d.normal.z * sign * 0.35);
        // one item per face (usable from both sides); normal = that face, so interact's front-side + line-of-sight
        // tests keep it from being bought through any other wall (the item sits 0.15 m clear of the door blocker)
        g.interact.register({
          id, pos, radius: DOOR_R, normal: [d.normal.x * sign, 0, d.normal.z * sign], facingSlack: 0.4,
          enabled: () => !d.open && !d.busy && this._onSide(d, sign),
          prompt: () => ({ cost }),
          use: () => this.buyDoor(d.id),
        });
        this._items.set(id, { kind: 'door', id: d.id });
        entry.items.push(id);
      }
      this.doors[d.id] = entry;
    }
  }

  _onSide(d, sign) {
    const p = this.game.player;
    if (!p || !p.pos) return false;
    const s = (p.pos.x - d.center[0]) * d.normal.x + (p.pos.z - d.center[1]) * d.normal.z;
    return s * sign > -0.05;
  }

  buyDoor(doorId) {
    const g = this.game, e = this.doors[doorId];
    if (!e || e.door.open || e.door.busy) return false;
    if (!this.spend(e.cost, 'door')) {
      this._rattleDoor(e.door);
      return false;
    }
    g.level.openDoor(doorId);
    g.events.emit('economy:buy', { kind: 'door', id: doorId, cost: e.cost });
    if (g.cam && g.cam.shake) g.cam.shake(0.12, 0.3);
    if (g.fx) {
      g.fx.burst(e.door.pos, { count: 10, shape: 'star', colors: [PAL.marqueeGold, '#FFF3B0'], speed: 3.4, size: 0.12, life: 0.9, gravity: 5 });
      g.fx.burst(e.door.pos, { count: 14, shape: 'confetti', speed: 4, life: 1.2 });
    }
    return true;
  }

  // Denied: the blocker gives a short "nuh-uh" shake (chain rattle). Restores its exact rest transform.
  _rattleDoor(d) {
    if (!d.blocker || d.open || d.busy || this._rattles.some((r) => r.key === d)) return;
    const o = d.blocker, px = o.position.x, rz = o.rotation.z;
    let t = 0;
    this._rattles.push({
      key: d,
      step: (dt) => {
        t += dt;
        const k = Math.min(1, t / 0.32);
        if (d.open || k >= 1) { o.position.x = px; o.rotation.z = rz; return false; }
        const a = Math.sin(t * 70) * (1 - k);
        o.position.x = px + a * 0.018;
        o.rotation.z = rz + a * 0.006;
        return true;
      },
      restore: () => { o.position.x = px; o.rotation.z = rz; },
    });
  }

  // ============================================================================================= wall-buys
  _setupWallbuys() {
    const g = this.game, L = g.level;
    for (const a of Object.values(L.anchors)) {
      if (!a.id || !a.id.startsWith('wb_') || !a.gives) continue;
      const w = this._safe('build:' + a.id, () => (a.gives === 'tube_grenade' ? new GrenadeCase(this, a) : new WallBuy(this, a)));
      if (!w) continue;
      this.wallbuys[a.id] = w;
      const id = `econ:wb:${a.id}`;
      // facing = the anchor's rotY: only usable from the poster's side of the wall (never through it)
      g.interact.register({
        id, pos: w.interactPos, radius: WB_R, height: 1.8, facing: a.rotY,
        enabled: () => !w.busy,
        prompt: () => { const c = w.price(); return c === null ? null : { cost: c }; },
        use: () => this.buyWallbuy(a.id),
      });
      this._items.set(id, { kind: 'wallbuy', id: a.id });
      w.itemId = id;
    }
  }

  buyWallbuy(anchorId) {
    const w = this.wallbuys[anchorId];
    if (!w || w.busy) return false;
    const cost = w.price();
    if (cost === null) return false;
    if (!this.spend(cost, w.kindOf())) {
      w.denied();
      return false;
    }
    const kind = w.kindOf();
    w.buy();
    this.game.events.emit('economy:buy', { kind, id: anchorId, cost });
    return true;
  }

  // Finds the wall surface in front of an anchor (anchors sit 0.1 m off the wall centre line, i.e. inside it).
  _wallFace(anchor) {
    const col = this.game.level.col;
    const fwd = _v3.set(-Math.sin(anchor.rotY), 0, -Math.cos(anchor.rotY));
    const o = _v.copy(anchor.pos).addScaledVector(fwd, 1.2);
    const d = _v2.copy(fwd).negate();
    const hit = col.raycast(o, d, 2.0);
    const out = anchor.pos.clone();
    if (hit && hit.dist < 1.6) out.copy(o).addScaledVector(d, hit.dist);
    else out.addScaledVector(fwd, 0.06);
    return out;
  }

  // Hand position of the hero (target of the pop-off arcs).
  _handPos(out) {
    const p = this.game.player;
    const slot = p && p.hero && p.hero.slots && p.hero.slots.handR;
    if (slot) return slot.getWorldPosition(out);
    return out.copy(p.pos).setY(p.pos.y + 1.2);
  }

  _handMatrix(out) {
    const p = this.game.player;
    const slot = p && p.hero && p.hero.slots && p.hero.slots.handR;
    if (slot) { slot.updateWorldMatrix(true, false); return out.copy(slot.matrixWorld); }
    return out.makeRotationY(p ? p.yaw : 0).setPosition(this._handPos(_v2));
  }

  _slot(id) {
    const w = this.game.weapons;
    if (w && typeof w.slotOf === 'function') return w.slotOf(id);
    return w && w.slots ? w.slots.find((s) => s && s.id === id) || null : null;
  }

  _def(id, upgraded) {
    const w = this.game.weapons;
    if (w && typeof w.defOf === 'function') return w.defOf(id, upgraded);
    const d = w && w.defs ? w.defs[id] : null;
    if (!d) return null;
    return upgraded && d.upgraded ? { ...d, ...d.upgraded } : d;
  }

  _ammoFull(id) {
    const s = this._slot(id);
    if (!s) return true;
    const def = this._def(id, s.upgraded);
    if (!def) return true;
    return s.mag >= def.mag && s.reserve >= def.reserve;
  }

  _refillAmmo(id) {
    const w = this.game.weapons;
    if (!w) return false;
    if (typeof w.refill === 'function') return w.refill(id);
    if (typeof w.refillAmmo === 'function') return w.refillAmmo(id);
    const s = this._slot(id);
    if (!s) return false;
    const def = this._def(id, s.upgraded);
    if (!def) return false;
    s.mag = def.mag;
    s.reserve = def.reserve;
    return true;
  }

  _grenades() {
    const w = this.game.weapons;
    return w && typeof w.grenades === 'number' ? w.grenades : 0;
  }

  // Silent top-up, one tube per catch (the case plays its own boing + glass tocks; weapons.give would emit
  // weapon:acquire -> a second boing). Clamped to T.player.grenadesMax by weapons.addGrenades.
  _addGrenades(n) {
    const w = this.game.weapons;
    if (!w || !(n > 0)) return;
    if (typeof w.addGrenades === 'function') w.addGrenades(n);
    else if (typeof w.grenades === 'number') w.grenades = Math.min(T.player.grenadesMax, w.grenades + n);
    else if (w.give) w.give('tube_grenade', { source: 'wallbuy_case' });
  }

  _starTexture() {
    if (this._starTex) return this._starTex;
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const x = c.getContext('2d');
    const gr = x.createRadialGradient(32, 32, 0, 32, 32, 30);
    gr.addColorStop(0, 'rgba(255,255,255,1)');
    gr.addColorStop(0.2, 'rgba(255,245,210,0.7)');
    gr.addColorStop(1, 'rgba(255,230,160,0)');
    x.fillStyle = gr;
    x.beginPath();
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU, r = i % 2 ? 6 : 31;
      x.lineTo(32 + Math.cos(a) * r, 32 + Math.sin(a) * r);
    }
    x.closePath();
    x.fill();
    this._starTex = new THREE.CanvasTexture(c);
    this._starTex.colorSpace = THREE.SRGBColorSpace;
    return this._starTex;
  }

  _glint() {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({
      map: this._starTexture(), color: new THREE.Color(2.2, 2.0, 1.6), transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, fog: false,
    }));
    s.scale.setScalar(1e-3);
    s.renderOrder = 5;
    return s;
  }

  // ============================================================================================ barricades
  _setupWindows() {
    const g = this.game, L = g.level;
    for (const w of Object.values(L.windows)) {
      if (w.type !== 'boarded') continue;
      const id = `econ:win:${w.id}`;
      const max = (w.boardMeshes && w.boardMeshes.length) || WIN_BOARDS;
      g.interact.register({
        id, pos: w.pos, radius: WIN_R, hold: REPAIR_HOLD,
        enabled: () => w.boards < max,
        prompt: () => ({}),
        use: () => this.repairWindow(w.id),
      });
      this._items.set(id, { kind: 'window', id: w.id });
      this.windows[w.id] = { win: w, itemId: id, max };
    }
  }

  repairWindow(windowId) {
    const g = this.game, e = this.windows[windowId];
    if (!e || e.win.boards >= e.max) return false;
    if (!e.win.repairBoard()) return false;
    const pts = T.points.board;
    if (this._boardPts + pts <= T.points.boardCap) {
      this._boardPts += pts;
      this.add(pts, 'board');
    }
    const b = e.win.boardMeshes && e.win.boardMeshes[e.win.boards - 1];
    const at = b ? b.position : e.win.pos;
    if (g.fx) {
      // sawdust puffs blown into the room + hammer sparks
      const inward = e.win.outsidePos ? _v2.copy(e.win.pos).sub(e.win.outsidePos).setY(0).normalize() : null;
      g.fx.burst(at, { count: 5, shape: 'puff', colors: ['#EFE0C4', '#D8C29C'], speed: 1.7, size: 0.075, life: 0.4, gravity: -0.3, dir: inward, cone: 1.2 });
      g.fx.burst(at, { count: 6, shape: 'spark', colors: ['#FFE8A0', '#FFFFFF'], speed: 3.8, size: 0.035, life: 0.2, dir: inward, cone: 1.4 });
    }
    if (g.cam && g.cam.shake) g.cam.shake(0.05, 0.12);
    return true;
  }

  // interact.js completes a hold once per press; keep repairing one board per REPAIR_HOLD while E stays down.
  _keepRepairing() {
    const it = this.game.interact;
    const cur = it && it.current;
    if (!cur || !cur.id || !cur.id.startsWith('econ:win:')) return;
    const e = this.windows[cur.id.slice(9)];
    if (!e || e.win.boards >= e.max) return;
    if (this.game.input.down('interact') && it._holdDone === true) it._holdDone = false;
  }

  // ================================================================================================= misc
  priceOf(key) {
    const hit = this._items.get(key);
    const kind = hit ? hit.kind : this.doors[key] ? 'door' : this.wallbuys[key] ? 'wallbuy' : null;
    const id = hit ? hit.id : key;
    if (kind === 'door') { const e = this.doors[id]; return e && !e.door.open ? e.cost : null; }
    if (kind === 'wallbuy') return this.wallbuys[id] ? this.wallbuys[id].price() : null;
    return null;
  }

  // Precompile samples: the glint sprite material (posters and case are already in the scene at boot).
  warmup() {
    return this._built ? [this._glint()] : null;
  }
}

// ================================================================================================ wall-buy
// A promo lightbox poster (cards.js poster_<gun>, Duke Dalton's show) with the real chunky prop gun clipped on it.
class WallBuy {
  constructor(eco, anchor) {
    this.eco = eco;
    this.game = eco.game;
    this.id = anchor.id;
    this.anchor = anchor;
    this.weaponId = anchor.gives;
    this.busy = false;
    this.itemId = null;
    this.winked = false;
    this._state = 'idle';     // idle | flying | away | restock
    this._t = 0;
    this._wobble = 1;
    this._glintPhase = (Object.keys(eco.wallbuys).length * 1.7) % GLINT_EVERY;
    this._build();
  }

  kindOf() {
    return this.game.weapons && this.game.weapons.has && this.game.weapons.has(this.weaponId) ? 'ammo' : 'wallbuy';
  }

  price() {
    if (this.busy) return null;
    const costs = T.wallbuys[this.weaponId];
    if (!costs) return null;
    const w = this.game.weapons;
    if (!w || !w.has || !w.has(this.weaponId)) return costs[0];
    if (this.eco._ammoFull(this.weaponId)) return null;
    const s = this.eco._slot(this.weaponId);
    return s && s.upgraded ? T.wallbuys.upgradedAmmo : costs[1];
  }

  _build() {
    const g = this.game, M = g.mats, a = this.anchor;
    const face = this.eco._wallFace(a);
    const parent = g.level.areaRoots[a.area] || g.scene;
    const root = new THREE.Group();
    root.name = `wallbuy:${a.id}`;
    root.userData.noMerge = true;
    parent.add(root);
    parent.updateMatrixWorld(true);
    root.position.copy(parent.worldToLocal(face.clone()));
    root.rotation.y = a.rotY;
    this.root = root;

    // Gun in 'wall' pose: side-on, back at z = 0, barrel toward -x. Measure it to size the poster.
    const gun = buildWeapon(this.weaponId, { pose: 'wall' }, g);
    gun.updateMatrixWorld(true);
    _box.setFromObject(gun).getSize(_size);
    const len = _size.x, gh = _size.y, gd = _size.z;
    const gcx = (_box.min.x + _box.max.x) / 2;
    // Sheet width from the gun length; long rifles may overhang the walnut frame by a few cm, never the wall.
    let W = clamp(len / 0.8, 0.95, 1.3);
    if (len > W + 0.12) W = len - 0.12;
    const H = W * 4 / 3;
    this.W = W;
    this.H = H;
    // The poster's painted mount sits 73% down the sheet: put it at the anchor height (gun centre = anchor y).
    const top = (0.73) * H;
    const board = new THREE.Group();          // hangs from the top edge (wobble pivot)
    board.position.set(0, top, 0);
    root.add(board);
    this.board = board;
    const inner = new THREE.Group();          // poster space: origin at the anchor, z = 0 on the wall
    inner.position.set(0, -top, 0);
    board.add(inner);
    this.inner = inner;

    // Lightbox: walnut frame, chrome lip, backlit poster (unlit glow material so it reads in dark studios).
    const cy = top - H / 2;
    const wood = M.toon(PAL.walnut, { rough: 0.45, rim: 0.25 });
    const chrome = M.toon('#C9CED8', { metal: 1, rough: 0.22, rim: 0.3 });
    const fw = 0.075, fd = 0.085;
    const frame = new THREE.Group();          // static lightbox parts, merged per material below
    frame.name = 'frame';
    inner.add(frame);
    const bar = (w, h, x, y, mat, d = fd, z = -fd / 2) => {
      const m = new THREE.Mesh(roundedBox(w, h, d, 0.018), mat);
      m.position.set(x, y, z);
      m.castShadow = true;
      m.receiveShadow = true;
      frame.add(m);
      return m;
    };
    bar(W + fw * 2, fw, 0, cy + H / 2 + fw / 2, wood);
    bar(W + fw * 2, fw, 0, cy - H / 2 - fw / 2, wood);
    bar(fw, H, -W / 2 - fw / 2, cy, wood);
    bar(fw, H, W / 2 + fw / 2, cy, wood);
    const lip = 0.014;
    bar(W, lip, 0, cy + H / 2 - lip / 2, chrome, 0.02, -fd + 0.012);
    bar(W, lip, 0, cy - H / 2 + lip / 2, chrome, 0.02, -fd + 0.012);
    bar(lip, H, -W / 2 + lip / 2, cy, chrome, 0.02, -fd + 0.012);
    bar(lip, H, W / 2 - lip / 2, cy, chrome, 0.02, -fd + 0.012);
    const back = new THREE.Mesh(new THREE.PlaneGeometry(W + fw, H + fw), M.toon('#2A1D2E', { rough: 0.9, rim: 0 }));
    back.rotation.y = Math.PI;
    back.position.set(0, cy, -0.004);
    frame.add(back);

    const card = `poster_${this.weaponId}`;
    this.matNormal = M.glow('#ffffff', 0.92, { map: getCard(card) });
    this.matWinked = M.glow('#ffffff', 0.92, { map: getCard(card, { winked: true }) });
    const poster = new THREE.Mesh(new THREE.PlaneGeometry(W, H), this.matNormal);
    poster.rotation.y = Math.PI;             // face -z (into the room)
    poster.position.set(0, cy, -0.04);
    poster.name = 'poster';
    inner.add(poster);
    this.poster = poster;

    // Picture light: brass bar lamp over the lightbox on two arms, glowing underside.
    const brass = M.toon('#C8963C', { metal: 1, rough: 0.3, rim: 0.3 });
    const lampY = cy + H / 2 + fw + 0.06;
    const lamp = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, W * 0.62, 18, 1), brass);
    lamp.rotation.z = Math.PI / 2;
    lamp.position.set(0, lampY, -0.2);
    lamp.castShadow = true;
    frame.add(lamp);
    const tube = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.022, W * 0.58, 10, 1), M.glow(PAL.tungsten, 2.2));
    tube.rotation.z = Math.PI / 2;
    tube.position.set(0, lampY - 0.03, -0.215);
    frame.add(tube);
    for (const s of [-1, 1]) {
      const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.22, 8, 1), brass);
      arm.rotation.x = Math.PI / 2;
      arm.position.set(s * W * 0.22, lampY, -0.1);
      arm.castShadow = true;
      frame.add(arm);
    }
    mergeByMaterial(frame);                   // 13 meshes -> 5 draws

    // The gun, clipped just in front of the poster, plus two chrome spring clips over it.
    this.gunZ = -0.055;
    gun.position.set(0, 0, this.gunZ);
    inner.add(gun);
    this.gun = gun;
    this.gunRest = { pos: gun.position.clone(), quat: gun.quaternion.clone() };
    // The prop's body is merged in wall-pose space; its 'wpn' group keeps the pose matrix (hand pose = identity).
    // Flight target = hand matrix x inverse(pose) so the gun lands exactly as it will be held.
    const wpn = gun.getObjectByName('wpn');
    this.poseInv = wpn ? wpn.matrix.clone().invert() : new THREE.Matrix4();
    const shadow = new THREE.Mesh(new THREE.PlaneGeometry(len * 1.12, Math.max(0.16, gh * 1.25)), new THREE.MeshBasicMaterial({
      map: gunShadowTex(), transparent: true, depthWrite: false, color: '#ffffff',
    }));
    shadow.rotation.y = Math.PI;
    shadow.position.set(len * 0.03, -gh * 0.32, -0.043);
    shadow.renderOrder = 1;
    inner.add(shadow);
    this.shadow = shadow;
    // Brass bulldog clips (plain chrome read as black slabs against the backlit sheet: no bright env to reflect),
    // each hinged just above the gun's real silhouette at its x (a rifle's barrel sits lower than its carry handle).
    const clipMat = g.mats.toon('#C8942F', { metal: 0, rough: 0.5, rim: 0.28, rimColor: '#FFE7B0', emissive: '#4A300A', emissiveIntensity: 0.12 });
    this.clips = [];
    for (const s of [-1, 1]) {
      const cx = gcx + s * len * 0.24;
      const prof = sliceProfile(gun, cx - 0.03, cx + 0.03);
      const topY = Number.isFinite(prof.top) ? prof.top : gh / 2;
      const frontZ = Number.isFinite(prof.front) ? prof.front : -gd;
      const hinge = new THREE.Group();
      hinge.position.set(cx, topY + 0.03, this.gunZ + frontZ - 0.006);
      const tab = new THREE.Mesh(roundedBox(0.05, 0.1, 0.014, 0.006), clipMat);
      tab.position.set(0, -0.045, -0.007);
      tab.castShadow = true;
      const roll = new THREE.Mesh(new THREE.CylinderGeometry(0.011, 0.011, 0.058, 10, 1), clipMat);
      roll.rotation.z = Math.PI / 2;
      roll.position.set(0, 0.002, -0.004);
      roll.castShadow = true;
      hinge.add(tab, roll);
      mergeByMaterial(hinge);                 // spring roll + jaw: 1 draw per clip
      inner.add(hinge);
      this.clips.push(hinge);
    }
    this.normal = new THREE.Vector3(-Math.sin(a.rotY), 0, -Math.cos(a.rotY));
    this.gunLen = len;
    this.gunFront = this.gunZ - gd;
    flattenMerge(gun);                        // after the clip silhouette probe and poseInv (they read the parts)

    // Chrome glint (GDD §6.7) sweeping along the barrel every GLINT_EVERY s.
    this.glint = this.eco._glint();
    inner.add(this.glint);
    this.glintRange = [len * 0.3, -len * 0.42];
    this.glintY = gh * 0.18;

    this.interactPos = face.clone();
    this.interactPos.y = a.pos.y;
    root.updateMatrixWorld(true);
  }

  // Eye of the winking Duke on the poster (card space: head at 0.5/0.45, wink sparkle at +0.62·s / −0.18·s).
  _eyeWorld(out) {
    const u = (192 + 56 * 0.62) / 384, v = (0.45 * 512 - 56 * 0.18) / 512;
    const cy = 0.73 * this.H - this.H / 2;
    out.set((0.5 - u) * this.W, cy + (0.5 - v) * this.H, -0.06);
    return this.inner.localToWorld(out);
  }

  _setWink(on, pop) {
    if (on === this.winked) return;
    this.winked = on;
    this.poster.material = on ? this.matWinked : this.matNormal;
    if (pop) {
      this._wobble = 0;
      const fx = this.game.fx;
      if (on && fx) fx.burst(this._eyeWorld(_v), { count: 5, shape: 'star', colors: ['#FFFFFF', PAL.marqueeGold], speed: 1.6, size: 0.1, life: 0.7, gravity: 0.5 });
    }
  }

  denied() {
    // Nope: the gun shivers on its clips.
    if (this._state !== 'idle') return;
    const gun = this.gun, base = this.gunRest.pos;
    this.eco._tween(0.3, (k) => {
      if (this._state !== 'idle') return;
      const a = Math.sin(k * 30) * (1 - k);
      gun.position.set(base.x + a * 0.012, base.y, base.z);
      gun.rotation.z = a * 0.03;
      if (k >= 1) { gun.position.copy(base); gun.quaternion.copy(this.gunRest.quat); }
    });
  }

  buy() {
    if (this.kindOf() === 'ammo') { this._buyAmmo(); return; }
    const g = this.game;
    this.busy = true;
    this._state = 'flying';
    this._t = 0;
    this._setWink(true, true);
    this._wobble = 0;
    // Pop: the clips spring open, the gun is handed to the scene root keeping its world transform and arcs into
    // the hero's hands (ka-ching from the spend now, boing from weapon:acquire on the catch).
    this._clipsOpen(FLIGHT + RESTOCK + 0.2);
    g.scene.attach(this.gun);
    this._from = this.gun.position.clone();
    this._fromQ = this.gun.quaternion.clone();
    this._fromS = this.gun.scale.x;
    this._trail = 0;
    g.audio && g.audio.play('dry_fire', { pos: this._from, vol: 0.45, rate: 1.5 });
    if (g.fx) {
      g.fx.burst(this._from, { count: 5, shape: 'puff', colors: ['#FFF4DC', '#F6E7C8'], speed: 1.9, size: 0.065, life: 0.32, gravity: -0.4, dir: this.normal, cone: 0.9 });
      g.fx.burst(this._from, { count: 7, shape: 'spark', colors: ['#FFF3B0', '#FFFFFF'], speed: 4.2, size: 0.03, life: 0.18, dir: this.normal, cone: 1.1 });
    }
  }

  _buyAmmo() {
    const g = this.game;
    this.eco._refillAmmo(this.weaponId);
    const def = this.eco._def(this.weaponId, false);
    const a = g.audio;
    if (a && def && def.shellReload) {
      // pump: two shells thumbed in, then the rack
      a.play('reload_shell', { pos: this.interactPos });
      a.play('reload_shell', { pos: this.interactPos, delay: 0.13, rate: 1.06 });
      a.play('wpn_pump_rack', { pos: this.interactPos, delay: 0.32, vol: 0.8 });
    } else if (a) {
      a.play('reload_mag', { pos: this.interactPos });
      a.play('reload_mag', { pos: this.interactPos, delay: 0.25, vol: 0.6, rate: 1.1 });
    }
    // The gun hops off the clips and settles; brass spills toward the player.
    const gun = this.gun, base = this.gunRest.pos;
    this.eco._tween(0.45, (k) => {
      if (this._state !== 'idle') return;
      const hop = Math.sin(Math.PI * k) * (1 - k * 0.3);
      gun.position.set(base.x, base.y + hop * 0.06, base.z - hop * 0.05);
      gun.rotation.z = Math.sin(k * TAU * 1.5) * 0.08 * (1 - k);
      if (k >= 1) { gun.position.copy(base); gun.quaternion.copy(this.gunRest.quat); }
    });
    this._clipsOpen(0.5);
    if (g.fx) {
      gun.getWorldPosition(_v);
      const dir = this.eco._handPos(_v2).sub(_v).normalize();
      g.fx.burst(_v, { count: 12, shape: 'confetti', colors: ['#E8B84A', '#C8963C', '#FFE09A'], speed: 3.2, size: 0.05, life: 0.9, gravity: 9, dir, cone: 0.7 });
    }
  }

  _clipsOpen(hold) {
    const clips = this.clips;
    this.eco._tween(hold + 0.35, (k) => {
      const t = k * (hold + 0.35);
      let a;
      if (t < 0.12) a = easeOutBack(t / 0.12, 3) * 1.25;
      else if (t < hold) a = 1.25;
      else a = 1.25 * (1 - easeOutBack(Math.min(1, (t - hold) / 0.35), 1.6));
      for (const c of clips) c.rotation.x = -a;
    });
  }

  reset() {
    this.busy = false;
    this._state = 'idle';
    this._wobble = 1;
    this._setWink(false, false);
    this._restoreGun();
    this.gun.scale.setScalar(1);
    this.gun.visible = true;
    for (const c of this.clips) c.rotation.x = 0;
    this.board.rotation.set(0, 0, 0);
  }

  _restoreGun() {
    if (this.gun.parent !== this.inner) this.inner.add(this.gun);
    this.gun.position.copy(this.gunRest.pos);
    this.gun.quaternion.copy(this.gunRest.quat);
    this.gun.scale.setScalar(1);
  }

  update(dt, time) {
    const g = this.game;
    // Duke keeps winking while the player owns this gun.
    if (this._state === 'idle' || this._state === 'restock') {
      const owned = !!(g.weapons && g.weapons.has && g.weapons.has(this.weaponId));
      this._setWink(owned, true);
    }
    // Poster wobble on its top edge (paper-on-spring), decaying.
    if (this._wobble < 1) {
      this._wobble = Math.min(1, this._wobble + dt / 0.7);
      const k = this._wobble;
      this.board.rotation.z = Math.sin(k * 22) * 0.035 * (1 - k) ** 2;
      this.board.rotation.x = Math.sin(k * 17) * 0.02 * (1 - k) ** 2;
    }
    this._updateGlint(dt, time);

    if (this._state === 'flying') {
      this._t += dt;
      const k = Math.min(1, this._t / FLIGHT);
      // fast pop off the sheet, a hang at the apex, a snap into the hand
      const e = clamp(k + 0.12 * Math.sin(TAU * k), 0, 1);
      // landing frame = hand x inverse(wall pose): the gun arrives exactly as it will be held
      this.eco._handMatrix(_m).multiply(this.poseInv).decompose(_v3, _q2, _sc);
      const to = _v3, from = this._from, n = this.normal;
      // cubic bezier: out of the poster along its normal and up, over the top, then down into the hand
      const up = 0.35 + 0.25 * clamp(from.distanceTo(to) - 0.8, 0, 1.5);
      const p1 = _v.copy(from).addScaledVector(n, 0.45).setY(from.y + up);
      const p2 = _v2.copy(to).setY(Math.max(to.y, from.y) + up * 1.3);
      const u = 1 - e, gun = this.gun;
      gun.position.set(0, 0, 0)
        .addScaledVector(from, u * u * u)
        .addScaledVector(p1, 3 * u * u * e)
        .addScaledVector(p2, 3 * u * e * e)
        .addScaledVector(to, e * e * e);
      // wall pose -> hand pose, with one barrel roll (local x) on the way
      gun.quaternion.slerpQuaternions(this._fromQ, _q2, easeInOut(k)).multiply(_qRoll.setFromAxisAngle(_X, TAU * easeInOut(k)));
      // stretch along the barrel in flight, squash on the catch frames
      const s = 1 + Math.sin(Math.PI * Math.min(1, k * 1.15)) * 0.2;
      const sc = THREE.MathUtils.lerp(this._fromS, _sc.x, e);
      gun.scale.set(sc * s, sc * (2 - s), sc * (2 - s) * 0.5 + sc * 0.5);
      // sparkle trail
      this._trail += dt;
      if (g.fx && this._trail > 0.04 && k < 0.92) {
        this._trail = 0;
        g.fx.burst(gun.position, { count: 1, shape: 'star', colors: ['#FFF3B0', '#FFFFFF'], speed: 0.3, size: 0.055, life: 0.3, gravity: 0 });
      }
      if (k >= 1) this._catch();
    } else if (this._state === 'away') {
      this._t += dt;
      if (this._t >= RESTOCK) {
        this._state = 'restock';
        this._t = 0;
        this._restoreGun();
        this.gun.visible = true;
        this.gun.scale.setScalar(1e-3);
        this.gun.getWorldPosition(_v);
        if (g.fx) g.fx.burst(_v, { count: 5, shape: 'puff', colors: ['#FFF4DC'], speed: 1.2, size: 0.06, life: 0.35, gravity: -0.3, dir: this.normal, cone: 1 });
        g.audio && g.audio.play('dry_fire', { pos: _v, vol: 0.3, rate: 1.25, delay: 0.2 });
      }
    } else if (this._state === 'restock') {
      this._t += dt;
      const k = Math.min(1, this._t / 0.38);
      this.gun.scale.setScalar(Math.max(1e-3, easeOutBack(k, 2.6)));
      if (k >= 1) {
        this.gun.scale.setScalar(1);
        this._state = 'idle';
        this.busy = false;
      }
    }
  }

  _catch() {
    const g = this.game;
    this.gun.visible = false;
    this.gun.scale.setScalar(1);
    this._restoreGun();
    this._state = 'away';
    this._t = 0;
    const w = g.weapons;
    if (w && w.give) w.give(this.weaponId, { source: 'wallbuy' });
    this._setWink(true, false);
    if (g.fx) g.fx.burst(this.eco._handPos(_v), { count: 6, shape: 'star', colors: ['#FFFFFF', PAL.marqueeGold], speed: 2.2, size: 0.07, life: 0.45, gravity: 2 });
    if (g.cam && g.cam.kick) g.cam.kick(0.01, 0);
  }

  _updateGlint(dt, time) {
    const s = this.glint;
    const period = (time + this._glintPhase) % GLINT_EVERY;
    const dur = 0.5;
    if (this._state !== 'idle' || period > dur) { s.visible = false; return; }
    s.visible = true;
    const k = period / dur;
    const [x0, x1] = this.glintRange;
    s.position.set(THREE.MathUtils.lerp(x0, x1, easeInOut(k)), this.glintY, this.gunFront - 0.02);
    const sz = Math.sin(Math.PI * k) ** 1.5 * 0.26;
    s.scale.setScalar(Math.max(1e-3, sz));
    s.material.rotation = k * 2.4;
  }
}

// ============================================================================================ grenade case
// "Tube-O-Matic": a 70s drugstore tube-tester style wall cabinet. Four glowing Tube grenades stand behind the glass.
class GrenadeCase {
  constructor(eco, anchor) {
    this.eco = eco;
    this.game = eco.game;
    this.id = anchor.id;
    this.anchor = anchor;
    this.weaponId = 'tube_grenade';
    this.busy = false;
    this.itemId = null;
    this._restock = -1;
    this._owed = 0;
    this._time = 0;
    this._build();
  }

  kindOf() { return 'grenades'; }

  price() {
    if (this.busy) return null;
    return this.eco._grenades() < T.player.grenadesMax ? T.wallbuys.grenades : null;
  }

  _build() {
    const g = this.game, a = this.anchor;
    const face = this.eco._wallFace(a);
    const floorY = g.level.areas[a.area] ? g.level.areas[a.area].floorY || 0 : 0;
    const parent = g.level.areaRoots[a.area] || g.scene;
    const root = new THREE.Group();
    root.name = `wallbuy:${a.id}`;
    root.userData.noMerge = true;
    parent.add(root);
    parent.updateMatrixWorld(true);
    root.position.copy(parent.worldToLocal(face.clone().setY(floorY)));
    root.rotation.y = a.rotY;
    this.root = root;

    // Floor-standing cabinet against the wall. Local: floor y = 0, back on z = 0, front toward -z. The display
    // window is centred near the anchor height (1.4 m); the base holds the coin plate, the push button and a chute.
    const body = K.prop('tube_o_matic');
    const walnut = K.mat(g, 'walnut', '#ffffff', { map: K.tex.wood(PAL.walnut, { dark: 0.4 }) });
    const chrome = K.mat(g, 'chrome', '#A8B0BA');
    const orange = K.mat(g, 'lacquer', PAL.burntOrange);
    const gold = K.mat(g, 'lacquer', PAL.harvestGold);
    const W = 0.96, D = 0.5, baseH = 1.02, winY0 = 1.06, winY1 = 1.74, Dw = 0.42;
    const add = (geo, mat, pos) => body.add(K.m(geo, mat, { pos }));
    // base cabinet: walnut box, orange lacquer front panel, chrome kick plate, gold pinstripes
    add(K.box(W, baseH, D, 'lg', { uv: 1.1 }), walnut, [0, baseH / 2, -D / 2]);
    add(K.box(W - 0.14, baseH - 0.26, 0.03, 'md'), orange, [0, baseH / 2 + 0.05, -D - 0.005]);
    add(K.box(W + 0.02, 0.1, 0.03, 'sm'), chrome, [0, 0.07, -D - 0.005]);
    for (const y of [0.3, 0.86]) add(K.box(W - 0.1, 0.025, 0.02, 'xs'), gold, [0, y, -D - 0.022]);
    // chute (dark mouth with a chrome lip), coin plate, red button
    add(K.box(0.36, 0.16, 0.04, 'sm'), chrome, [0, 0.45, -D - 0.02]);
    add(K.box(0.3, 0.1, 0.03, 'sm'), K.mat(g, 'rubber', '#2A2233'), [0, 0.45, -D - 0.035]);
    add(K.box(0.2, 0.2, 0.03, 'sm'), chrome, [0, 0.7, -D - 0.022]);
    add(K.box(0.05, 0.012, 0.01, 'xs'), K.mat(g, 'plastic', '#2A2233'), [-0.04, 0.74, -D - 0.04]);
    add(K.cyl(0.04, 0.044, 0.035, { bevel: 0.01, seg: 18 }).clone().rotateX(-Math.PI / 2), K.mat(g, 'plastic', PAL.channelRed), [0.045, 0.67, -D - 0.04]);
    // display box: walnut shell (the backlit sunburst panel is added after K.finish), chrome shelf + sockets, chrome bezel around the glass
    const dy = (winY0 + winY1) / 2, dh = winY1 - winY0 + 0.1;
    add(K.box(W - 0.02, 0.06, Dw, 'md', { uv: 1.1 }), walnut, [0, winY0 - 0.02, -Dw / 2]);
    add(K.box(W - 0.02, 0.07, Dw, 'md', { uv: 1.1 }), walnut, [0, winY1 + 0.03, -Dw / 2]);
    for (const sx of [-1, 1]) add(K.box(0.07, dh, Dw, 'md', { uv: 1.1 }), walnut, [sx * (W / 2 - 0.045), dy, -Dw / 2]);
    add(K.box(W - 0.14, 0.04, Dw - 0.08, 'sm'), chrome, [0, winY0 + 0.1, -Dw / 2 - 0.02]);
    this.sockets = [];
    for (let i = 0; i < 4; i++) {
      const x = -0.3 + i * 0.2;
      add(K.cyl(0.05, 0.056, 0.035, { bevel: 0.008, seg: 18 }), K.mat(g, 'plastic', '#3A2A40'), [x, winY0 + 0.12, -Dw / 2 - 0.02]);
      this.sockets.push(new THREE.Vector3(x, winY0 + 0.155, -Dw / 2 - 0.02));
    }
    for (const [w, h, x, y] of [[W - 0.06, 0.035, 0, winY1 - 0.005], [W - 0.06, 0.035, 0, winY0 + 0.02], [0.035, dh - 0.06, -(W / 2 - 0.05), dy], [0.035, dh - 0.06, W / 2 - 0.05, dy]]) {
      add(K.box(w, h, 0.03, 'sm'), chrome, [x, y, -Dw - 0.005]);
    }
    K.finish(g, body, { ao: { strength: 0.75, height: 0.25, rays: 12, res: 56 }, cast: 0.25 });
    root.add(body);

    // Backlit sunburst panel behind the tubes (unlit: the AO bake and the case's own shadow turned felt to mud).
    const panel = new THREE.Mesh(new THREE.PlaneGeometry(W - 0.12, dh - 0.02), g.mats.glow('#ffffff', 0.62, { map: sunburstTex() }));
    panel.rotation.y = Math.PI;
    panel.position.set(0, dy, -0.012);
    root.add(panel);

    // warm strip light inside the display (unlit tube along the top)
    const strip = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, W - 0.2, 10, 1), g.mats.glow(PAL.tungsten, 2.4));
    strip.rotation.z = Math.PI / 2;
    strip.position.set(0, winY1 - 0.04, -Dw + 0.06);
    root.add(strip);

    // Header sign (in-world signage is allowed; the prompt never names anything) with chasing marquee bulbs.
    const signY = winY1 + 0.25;
    const signBox = new THREE.Mesh(roundedBox(W + 0.08, 0.34, 0.12, 0.04), g.mats.toon(PAL.walnut, { rough: 0.45, rim: 0.25 }));
    signBox.position.set(0, signY, -Dw / 2 - 0.1);
    signBox.castShadow = true;
    root.add(signBox);
    const sign = new THREE.Mesh(
      new THREE.PlaneGeometry(W - 0.06, 0.24),
      g.mats.glow('#ffffff', 0.95, { map: K.tex.label('TUBE-O-MATIC', { sub: 'WZTV ENGINEERING', bg: '#FFE9B0', fg: PAL.chocolate, accent: PAL.burntOrange, w: 512, h: 128, wear: 0.15 }) }),
    );
    sign.rotation.y = Math.PI;
    sign.position.set(0, signY, -Dw / 2 - 0.161);
    root.add(sign);
    // 22 chasing marquee bulbs: one InstancedMesh (an unlit bulb is scaled to a dim pip, not hidden).
    const NB = 22;
    const bulbs = new THREE.InstancedMesh(new THREE.SphereGeometry(0.018, 10, 8), g.mats.glow(PAL.marqueeGold, 2.2), NB);
    bulbs.name = 'marquee';
    this.bulbPos = [];
    const bw = W + 0.02, bh = 0.3, perim = 2 * (bw + bh);
    for (let i = 0; i < NB; i++) {
      // walk the rectangle around the sign face
      const d = (i / NB) * perim;
      let x, y;
      if (d < bw) { x = -bw / 2 + d; y = bh / 2; } else if (d < bw + bh) { x = bw / 2; y = bh / 2 - (d - bw); } else if (d < 2 * bw + bh) { x = bw / 2 - (d - bw - bh); y = -bh / 2; } else { x = -bw / 2; y = -bh / 2 + (d - 2 * bw - bh); }
      this.bulbPos.push(new THREE.Vector3(x, signY + y, -Dw / 2 - 0.165));
    }
    root.add(bulbs);
    this.bulbs = bulbs;
    this._bulbLit = -1;
    this._setBulbs(0, false);

    // Cartoon glass front: no reflective sheet (it washed the display out), just two diagonal highlight streaks.
    const streak = g.mats.glow('#FFFFFF', 0.9, { transparent: true, opacity: 0.22 });
    // The glass is a flap hinged on its top edge: it swings up and out when the tubes pop (see buy()).
    const glass = new THREE.Group();
    const hingeY = winY1 - 0.01, hingeZ = -Dw - 0.012;
    glass.position.set(0, hingeY, hingeZ);
    for (const [w, x] of [[0.09, -0.18], [0.035, -0.05]]) {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(w, dh - 0.16), streak);
      m.rotation.set(0, Math.PI, -0.5);
      m.position.set(x, dy + 0.02 - hingeY, -Dw + 0.005 - hingeZ);
      m.renderOrder = 2;
      glass.add(m);
    }
    root.add(glass);
    mergeByMaterial(glass);
    this.glass = glass;
    this.normal = new THREE.Vector3(-Math.sin(a.rotY), 0, -Math.cos(a.rotY));

    // The four tubes (display pose, floor at y = 0), each an animatable part.
    // At rest the four tubes are one merged "rack" (about 4 draws instead of 20); the individual tubes only show
    // while a purchase plays (they fly, restock), then the rack takes over again.
    const rack = new THREE.Group();
    rack.name = 'rack';
    root.add(rack);
    this.tubes = this.sockets.map((p, i) => {
      const ry = (i % 2 ? 0.35 : -0.35);
      const t = buildWeapon('tube_grenade', { pose: 'display' }, g);
      flattenMerge(t);
      t.position.copy(p);
      t.rotation.y = ry;
      t.visible = false;
      root.add(t);
      const r = buildWeapon('tube_grenade', { pose: 'display' }, g);
      r.position.copy(p);
      r.rotation.y = ry;
      rack.add(r);
      return { obj: t, rest: p.clone(), restRot: ry, state: 'home', t: 0 };
    });
    flattenMerge(rack);
    this.rack = rack;
    this.rackGlow = null;                     // the merged filaments (a rare shared flicker, like a power dip)
    rack.traverse((o) => { if (o.isMesh && /^glow/.test((o.material && o.material.name) || '')) this.rackGlow = o; });

    // collider so the player does not walk into the cabinet
    root.updateMatrixWorld(true);
    _box.makeEmpty();
    for (const [x, y, z] of [[-W / 2, 0, 0], [W / 2, 0, 0], [-W / 2, signY + 0.2, -D - 0.04], [W / 2, signY + 0.2, -D - 0.04]]) {
      _box.expandByPoint(root.localToWorld(_v.set(x, y, z)));
    }
    g.level.col.addBox(_box.min.toArray(), _box.max.toArray(), { tag: 'prop', id: 'econ_tube_o_matic' });

    this.interactPos = face.clone();
    this.interactPos.y = floorY + 1.2;
    this.interactPos.add(_v.set(-Math.sin(a.rotY), 0, -Math.cos(a.rotY)).multiplyScalar(D));
  }

  // true: the merged rack shows the tubes at rest; false: the individual (animatable) tubes do.
  _rackOn(on) {
    this.rack.visible = on;
    for (const tb of this.tubes) if (tb.state === 'home') tb.obj.visible = !on;
  }

  denied() {
    if (this.rack.visible) {
      // the whole rack rattles in its sockets
      const r = this.rack;
      this.eco._tween(0.3, (k) => {
        const a = Math.sin(k * 34) * (1 - k);
        r.position.set(a * 0.005, Math.abs(a) * 0.008, 0);
        r.rotation.z = a * 0.015;
        if (k >= 1) { r.position.set(0, 0, 0); r.rotation.z = 0; }
      });
      return;
    }
    for (const tb of this.tubes) {
      if (tb.state !== 'home') continue;
      const o = tb.obj, rest = tb.rest;
      this.eco._tween(0.3, (k) => {
        if (tb.state !== 'home') return;
        const a = Math.sin(k * 34 + rest.x * 9) * (1 - k);
        o.position.set(rest.x + a * 0.006, rest.y + Math.abs(a) * 0.01, rest.z);
        o.rotation.z = a * 0.12;
        if (k >= 1) { o.position.copy(rest); o.rotation.z = 0; }
      });
    }
  }

  buy() {
    const g = this.game;
    const need = Math.max(1, Math.min(this.tubes.length, T.player.grenadesMax - this.eco._grenades()));
    this._owed = need;                        // granted one per tube caught (the HUD tubes light up in sync)
    this.busy = true;
    this._rackOn(false);
    this._restock = RESTOCK + 0.25;
    g.audio && g.audio.play('wallbuy_boing', { pos: this.interactPos });
    g.audio && g.audio.play('dry_fire', { pos: this.interactPos, vol: 0.4, rate: 0.85 });
    // The glass flap swings up (overshoot), stays open while the tubes fly and restock, then drops shut.
    const open = RESTOCK + 0.25 + 0.3, flap = this.glass;
    this.eco._tween(open + 0.4, (k) => {
      const t = k * (open + 0.4);
      let a;
      if (t < 0.14) a = easeOutBack(t / 0.14, 2.4) * 1.05;
      else if (t < open) a = 1.05 + Math.sin((t - 0.14) * 3) * 0.03;
      else a = 1.05 * (1 - easeOutBounce(Math.min(1, (t - open) / 0.4)));
      flap.rotation.x = a;
      if (k >= 1) flap.rotation.x = 0;
    });
    this.eco._tween(open + 0.12, (k) => {
      if (k >= 1) g.audio && g.audio.play('dry_fire', { pos: this.interactPos, vol: 0.35, rate: 1.1 });
    });
    // `need` tubes pop up out of their sockets, hop out through the open front and arc into the hero's hands.
    let n = 0;
    for (const tb of this.tubes) {
      if (n >= need) break;
      tb.state = 'wait';
      tb.t = -0.06 - n * 0.08;
      n++;
    }
    this._setBulbs(0, true);
  }

  // Marquee chase: every third bulb dark, stepping at 8 Hz; all lit (and a touch bigger) while a purchase plays.
  _setBulbs(step, all) {
    const key = all ? -2 : step % 3;
    if (key === this._bulbLit) return;
    this._bulbLit = key;
    const m = _m, n = this.bulbPos.length;
    for (let i = 0; i < n; i++) {
      const on = all || (i + step) % 3 !== 0;
      m.makeScale(on ? (all ? 1.25 : 1) : 0.45, on ? (all ? 1.25 : 1) : 0.45, on ? (all ? 1.25 : 1) : 0.45).setPosition(this.bulbPos[i]);
      this.bulbs.setMatrixAt(i, m);
    }
    this.bulbs.instanceMatrix.needsUpdate = true;
  }

  reset() {
    this.busy = false;
    this._restock = -1;
    this._owed = 0;
    this.glass.rotation.x = 0;
    this._setBulbs(0, false);
    for (const tb of this.tubes) this._home(tb);
    this.rack.position.set(0, 0, 0);
    this.rack.rotation.z = 0;
    this._rackOn(true);
  }

  _home(tb) {
    if (tb.obj.parent !== this.root) this.root.add(tb.obj);
    tb.obj.position.copy(tb.rest);
    tb.obj.rotation.set(0, tb.restRot, 0);
    tb.obj.scale.setScalar(1);
    tb.obj.visible = !this.rack.visible;
    tb.state = 'home';
  }

  update(dt, time) {
    const g = this.game;
    this._time += dt;
    // marquee chase + a rare filament flicker on the rack
    this._setBulbs(Math.floor(this._time * 8), this.busy);
    if (this.rackGlow) this.rackGlow.visible = Math.sin(this._time * 37) > -0.985 || Math.sin(this._time * 1.3) < 0.9;
    for (const tb of this.tubes) {
      const o = tb.obj;
      if (tb.state === 'home') continue;
      tb.t += dt;
      if (tb.state === 'wait') {
        if (tb.t < 0) continue;
        g.scene.attach(o);
        tb.from = o.position.clone();
        tb.state = 'fly';
        tb.t = 0;
      }
      if (tb.state === 'fly') {
        const k = Math.min(1, tb.t / FLIGHT);
        const e = clamp(k + 0.1 * Math.sin(TAU * k), 0, 1);
        const to = this.eco._handPos(_v3), from = tb.from;
        // cubic bezier: up out of the socket (staying under the display top), out through the open front, into the hand
        const p1 = _v.copy(from).addScaledVector(this.normal, 0.3).setY(from.y + 0.24);
        const p2 = _v2.copy(to).setY(Math.max(to.y, from.y) + 0.32);
        const u = 1 - e;
        o.position.set(0, 0, 0).addScaledVector(from, u * u * u).addScaledVector(p1, 3 * u * u * e)
          .addScaledVector(p2, 3 * u * e * e).addScaledVector(to, e * e * e);
        o.rotation.x += dt * 14;
        const s = 1 + Math.sin(Math.PI * k) * 0.25;
        o.scale.set(s, 2 - s, s);
        if (k >= 1) {
          tb.state = 'gone';
          o.visible = false;
          if (this._owed > 0) { this._owed--; this.eco._addGrenades(1); }
          g.audio && g.audio.play('grenade_bounce', { vol: 0.7, rate: 1.1 + this.tubes.indexOf(tb) * 0.08 });
          g.fx && g.fx.burst(to, { count: 3, shape: 'spark', colors: ['#FFB060', '#FFE8A0'], speed: 2, size: 0.03, life: 0.2 });
        }
      }
    }
    if (this._restock > 0) {
      this._restock -= dt;
      if (this._restock <= 0) {
        if (this._owed > 0) { this.eco._addGrenades(this._owed); this._owed = 0; }   // never short-change a buy
        // tubes rise back into the sockets with a pop
        for (const tb of this.tubes) {
          if (tb.state === 'home') continue;
          this._home(tb);
          tb.obj.scale.setScalar(1e-3);
          tb.state = 'rise';
          const o = tb.obj;
          this.eco._tween(0.35, (k) => {
            o.scale.setScalar(Math.max(1e-3, easeOutBack(k, 2.8)));
            if (k >= 1) { o.scale.setScalar(1); tb.state = 'home'; }
          });
        }
        this.eco._tween(0.36, (k) => { if (k >= 1) { this.busy = false; this._rackOn(true); } });
      }
    }
  }
}

// ---------------------------------------------------------------------------------------------- helpers
// Plum velvet back panel with an orange / gold 70s sunburst (the Tube-O-Matic display).
function sunburstTex() {
  return K.tex.canvas('econ.sunburst', 256, 256, (ctx, w, h) => {
    ctx.fillStyle = '#4A2A52';
    ctx.fillRect(0, 0, w, h);
    const cx = w / 2, cy = h * 0.72;
    for (let i = 0; i < 18; i++) {
      const a0 = (i / 18) * TAU, a1 = a0 + TAU / 36;
      ctx.fillStyle = i % 2 ? '#E3662B' : '#E8A92E';
      ctx.globalAlpha = 0.55;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + Math.cos(a0) * w, cy + Math.sin(a0) * w);
      ctx.lineTo(cx + Math.cos(a1) * w, cy + Math.sin(a1) * w);
      ctx.closePath();
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    const gr = ctx.createRadialGradient(cx, cy, 4, cx, cy, w * 0.75);
    gr.addColorStop(0, 'rgba(255,220,150,0.55)');
    gr.addColorStop(1, 'rgba(40,20,50,0.6)');
    ctx.fillStyle = gr;
    ctx.fillRect(0, 0, w, h);
  }, { repeat: false });
}

// Merges every visible static mesh of a display prop per material, ignoring the prop's own noMerge/dynamic part
// groups (a gun on a poster or a tube on a shelf never animates its slide / magazine / filament there). Meshes are
// re-parented into one 'flat' group (world transforms kept) and merged: 5-8 draws -> 2-4. `keep` stays untouched.
// Only this clone is modified (the prop cache prototypes keep their flags).
function flattenMerge(root, keep = null) {
  root.updateMatrixWorld(true);
  const flat = new THREE.Group();
  flat.name = 'flat';
  root.add(flat);
  flat.updateMatrixWorld(true);
  const list = [];
  root.traverse((o) => {
    if (!o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || !o.visible || o.userData.noMerge) return;
    for (let p = o; p && p !== root; p = p.parent) if (p === keep || !p.visible) return;
    list.push(o);
  });
  for (const m of list) flat.attach(m);
  mergeByMaterial(flat);
  return flat;
}

// Highest y and front-most z (most negative) of a prop's vertices with x in [x0, x1], in the prop's own space.
function sliceProfile(root, x0, x1) {
  let top = -Infinity, front = Infinity;
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const m = new THREE.Matrix4(), p = new THREE.Vector3();
  root.traverse((o) => {
    if (!o.isMesh || !o.geometry || !o.geometry.attributes.position) return;
    m.multiplyMatrices(inv, o.matrixWorld);
    const pos = o.geometry.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      p.fromBufferAttribute(pos, i).applyMatrix4(m);
      if (p.x < x0 || p.x > x1) continue;
      if (p.y > top) top = p.y;
      if (p.z < front) front = p.z;
    }
  });
  return { top, front };
}

// Soft contact shadow for a prop gun clipped on a lit poster (the lightbox is unlit, so no real shadow lands).
let _shadowTex = null;
function gunShadowTex() {
  if (_shadowTex) return _shadowTex;
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 64;
  const x = c.getContext('2d');
  x.filter = 'blur(9px)';
  x.fillStyle = 'rgba(42,20,52,0.85)';
  x.beginPath();
  x.roundRect(22, 18, 212, 28, 14);
  x.fill();
  _shadowTex = new THREE.CanvasTexture(c);
  _shadowTex.colorSpace = THREE.SRGBColorSpace;
  return _shadowTex;
}

const _rbCache = new Map();
function roundedBox(w, h, d, r) {
  const key = `${w.toFixed(4)}|${h.toFixed(4)}|${d.toFixed(4)}|${r}`;
  let g = _rbCache.get(key);
  if (!g) {
    g = K.box(w, h, d, r);
    _rbCache.set(key, g);
  }
  return g;
}
