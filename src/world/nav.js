// Navigation (ARCHITECTURE §7, GDD §5.10): a 0.5 m grid over the whole footprint and an 8-neighbour Dijkstra
// flow field toward the player (or a goal override), recomputed at most every 0.25 s when the goal changes
// cell (or a door opens), time-sliced so a solve never costs more than BUDGET_MS in one frame.
//
// Cell = walkable when a walkable top exists under its centre and a 0.35 m agent standing there is not
// blocked (same rule as Collision.moveCircle). Door cells (within the agent radius of a door blocker) stay
// blocked until setDoor(id, true). Moves between cells climb ≤ STEP_UP and drop ≤ DROP; diagonals may not cut
// corners; cells hugging obstacles cost a little more so paths keep off the walls.
//
// API: build() (lazy on first use; call again after adding colliders), reset(), update(dt),
//      setDoor(id, open), setGoalOverride(pos|null), localField(x, z, maxDist) → { dist, dir } (bounded 2nd field),
//      dir(x, z, out) → out (unit XZ toward the goal, 0 if unreachable), dist(x, z) → metres | Infinity,
//      walkable(x, z) → bool, heightAt(x, z) → floor y | -Infinity,
//      debugImage(mode='dist'|'height') → { width, height, data:Uint8ClampedArray RGBA, x0, z0, cell }
//      (row 0 = north edge z0; column 0 = west edge x0).

import * as THREE from 'three';
import { FOOTPRINT } from './layout.js';

const CELL = 0.5;
const AGENT_R = 0.35;
const AGENT_H = 1.7;
const STEP_UP = 0.45;
const DROP = 0.9;
const WALL_COST = 0.25;
const PERIOD = 0.25;
const BUDGET_MS = 1.5;
const SEED_R = 1.0;
const SQRT2 = Math.SQRT2;
const IGNORE = ['door'];

const DI = [1, -1, 0, 0, 1, 1, -1, -1];
const DK = [0, 0, 1, -1, 1, -1, 1, -1];
const OPP = [1, 0, 3, 2, 7, 6, 5, 4];

const _goal = new THREE.Vector3();

export class Nav {
  constructor(game) {
    this.game = game;
    this.cell = CELL;
    this.x0 = FOOTPRINT.x0;
    this.z0 = FOOTPRINT.z0;
    this.w = Math.round((FOOTPRINT.x1 - FOOTPRINT.x0) / CELL);
    this.h = Math.round((FOOTPRINT.z1 - FOOTPRINT.z0) / CELL);
    const n = this.w * this.h;
    this.height = new Float64Array(n).fill(-Infinity);
    this.base = new Uint8Array(n);         // 1 = walkable ignoring doors
    this.doorOf = new Int16Array(n).fill(-1);
    this.near = new Uint8Array(n);         // 1 = next to an obstacle (extra cost)
    this.front = new Float32Array(n).fill(Infinity);
    this.back = new Float32Array(n).fill(Infinity);
    this.heap = new Int32Array(n * 8);
    this.heapKey = new Float32Array(n * 8);
    this.heapN = 0;
    this.doorIds = [];
    this.doorOpen = new Map();
    this.built = false;
    this.override = null;
    this.goal = { x: 0, z: 0, cell: -1 };        // goal of the `front` field
    this._pending = { x: 0, z: 0, cell: -1 };
    this._solving = false;
    this._dirty = true;
    this._t = PERIOD;
  }

  // ------------------------------------------------------------------------------------------- building
  build() {
    const col = this.game.level.col;
    const { w, h } = this;
    this.doorIds = [];
    this.doorOf.fill(-1);
    for (let k = 0; k < h; k++) {
      for (let i = 0; i < w; i++) {
        const idx = k * w + i;
        const x = this.x0 + (i + 0.5) * CELL, z = this.z0 + (k + 0.5) * CELL;
        const y = col.floorAt(x, z, Infinity);
        this.height[idx] = y;
        this.base[idx] = y > -Infinity && !col.blockedAt(x, z, AGENT_R, y, STEP_UP, AGENT_H, IGNORE) ? 1 : 0;
      }
    }
    // Door membership: cells whose agent disc touches a door blocker.
    for (const b of col.boxes) {
      if (b.tag !== 'door' || b.id === null) continue;
      let d = this.doorIds.indexOf(b.id);
      if (d < 0) { d = this.doorIds.length; this.doorIds.push(b.id); }
      const [i0, k0] = this._cellXY(b.minX - AGENT_R, b.minZ - AGENT_R);
      const [i1, k1] = this._cellXY(b.maxX + AGENT_R, b.maxZ + AGENT_R);
      for (let k = Math.max(0, k0); k <= Math.min(h - 1, k1); k++) {
        for (let i = Math.max(0, i0); i <= Math.min(w - 1, i1); i++) {
          const x = this.x0 + (i + 0.5) * CELL, z = this.z0 + (k + 0.5) * CELL;
          const dx = x - Math.max(b.minX, Math.min(x, b.maxX));
          const dz = z - Math.max(b.minZ, Math.min(z, b.maxZ));
          if (dx * dx + dz * dz < AGENT_R * AGENT_R) this.doorOf[k * w + i] = d;
        }
      }
    }
    for (let k = 0; k < h; k++) {
      for (let i = 0; i < w; i++) {
        const idx = k * w + i;
        let near = 0;
        for (let n = 0; n < 8 && !near; n++) {
          const ii = i + DI[n], kk = k + DK[n];
          if (ii < 0 || kk < 0 || ii >= w || kk >= h || !this.base[kk * w + ii]) near = 1;
        }
        this.near[idx] = near;
      }
    }
    this.built = true;
    this._solving = false;
    this._dirty = true;
    this.front.fill(Infinity);
    this.goal.cell = -1;
  }

  reset() {
    this.doorOpen.clear();
    this.override = null;
    this._dirty = true;
  }

  setDoor(id, open) {
    this.doorOpen.set(id, !!open);
    this._dirty = true;
  }

  setGoalOverride(pos) {
    this.override = pos ? _goal.copy(pos) : null;
    this._dirty = true;
  }

  // ----------------------------------------------------------------------------------------------- update
  update(dt) {
    if (!this.built) this.build();
    this._t += dt;
    if (!this._solving) {
      const g = this.override || (this.game.player && this.game.player.pos);
      if (!g) return;
      const c = this._cellIndex(g.x, g.z);
      if (this._t >= PERIOD && (this._dirty || c !== this.goal.cell)) {
        this._t = 0;
        this._dirty = false;
        this._start(g.x, g.z, c);
      }
    }
    if (this._solving) this._step(BUDGET_MS);
  }

  // Complete solve right now (tests, debug views).
  solveNow(x, z) {
    if (!this.built) this.build();
    this._start(x, z, this._cellIndex(x, z));
    this._step(Infinity);
  }

  _open(idx) {
    if (!this.base[idx]) return false;
    const d = this.doorOf[idx];
    return d < 0 || this.doorOpen.get(this.doorIds[d]) === true;
  }

  // Can an agent step from cell a to neighbour b (direction n)?
  _link(a, b, n) {
    if (!this._open(b)) return false;
    const dh = this.height[b] - this.height[a];
    if (dh > STEP_UP + 0.01 || -dh > DROP) return false;
    if (n >= 4) {
      const { w } = this;
      const ai = a % w, ak = (a - ai) / w;
      const s1 = ak * w + ai + DI[n], s2 = (ak + DK[n]) * w + ai;
      if (!this._open(s1) || !this._open(s2)) return false;
    }
    return true;
  }

  _start(x, z, cell) {
    const { back, w, h } = this;
    back.fill(Infinity);
    this.heapN = 0;
    this._pending.x = x; this._pending.z = z; this._pending.cell = cell;
    // Seed the goal cell, or (goal on a prop / in a wall-hugging cell) every open cell within SEED_R.
    if (cell >= 0 && this._open(cell)) {
      back[cell] = 0;
      this._push(cell, 0);
    } else {
      const [ci, ck] = this._cellXY(x, z);
      const r = Math.ceil(SEED_R / CELL);
      for (let k = Math.max(0, ck - r); k <= Math.min(h - 1, ck + r); k++) {
        for (let i = Math.max(0, ci - r); i <= Math.min(w - 1, ci + r); i++) {
          const idx = k * w + i;
          if (!this._open(idx)) continue;
          const d = Math.hypot(this.x0 + (i + 0.5) * CELL - x, this.z0 + (k + 0.5) * CELL - z);
          if (d <= SEED_R && d < back[idx]) { back[idx] = d; this._push(idx, d); }
        }
      }
    }
    this._solving = true;
  }

  _step(budgetMs) {
    const t0 = performance.now();
    const { back, w, h } = this;
    let pops = 0;
    while (this.heapN > 0) {
      if ((++pops & 127) === 0 && performance.now() - t0 > budgetMs) return;
      this._pop();
      const u = _popOut[0], du = _popOut[1];
      if (du > back[u]) continue;
      const ui = u % w, uk = (u - ui) / w;
      for (let n = 0; n < 8; n++) {
        const vi = ui + DI[n], vk = uk + DK[n];
        if (vi < 0 || vk < 0 || vi >= w || vk >= h) continue;
        const v = vk * w + vi;
        // Agents at v walk toward u: the move v → u must be legal.
        if (!this._link(v, u, OPP[n])) continue;
        const nd = du + (n < 4 ? CELL : CELL * SQRT2) + (this.near[v] ? WALL_COST : 0);
        if (nd < back[v]) { back[v] = nd; this._push(v, nd); }
      }
    }
    const tmp = this.front; this.front = this.back; this.back = tmp;
    this.goal.x = this._pending.x; this.goal.z = this._pending.z; this.goal.cell = this._pending.cell;
    this._solving = false;
  }

  _push(idx, key) {
    let i = this.heapN++;
    const { heap, heapKey } = this;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heapKey[p] <= key) break;
      heap[i] = heap[p]; heapKey[i] = heapKey[p];
      i = p;
    }
    heap[i] = idx; heapKey[i] = key;
  }

  _pop() {
    const { heap, heapKey } = this;
    const top = heap[0], topKey = heapKey[0];
    const n = --this.heapN;
    const last = heap[n], lastKey = heapKey[n];
    let i = 0;
    for (;;) {
      let c = 2 * i + 1;
      if (c >= n) break;
      if (c + 1 < n && heapKey[c + 1] < heapKey[c]) c++;
      if (heapKey[c] >= lastKey) break;
      heap[i] = heap[c]; heapKey[i] = heapKey[c];
      i = c;
    }
    heap[i] = last; heapKey[i] = lastKey;
    _popOut[0] = top; _popOut[1] = topKey;
  }

  // ---------------------------------------------------------------------------------------------- queries
  _cellXY(x, z) {
    return [Math.floor((x - this.x0) / CELL), Math.floor((z - this.z0) / CELL)];
  }

  _cellIndex(x, z) {
    const i = Math.floor((x - this.x0) / CELL), k = Math.floor((z - this.z0) / CELL);
    return i < 0 || k < 0 || i >= this.w || k >= this.h ? -1 : k * this.w + i;
  }

  // Best reached cell for a position: its own cell, else the cheapest reached neighbour.
  _bestCell(x, z, front = this.front) {
    const c = this._cellIndex(x, z);
    if (c < 0) return -1;
    if (front[c] < Infinity) return c;
    const { w, h } = this;
    const ci = c % w, ck = (c - ci) / w;
    let best = -1, bd = Infinity;
    for (let n = 0; n < 8; n++) {
      const i = ci + DI[n], k = ck + DK[n];
      if (i < 0 || k < 0 || i >= w || k >= h) continue;
      const v = k * w + i;
      if (front[v] < bd) { bd = front[v]; best = v; }
    }
    return best;
  }

  dist(x, z, front = this.front) {
    if (!this.built) this.build();
    const c = this._bestCell(x, z, front);
    if (c < 0) return Infinity;
    const ci = c % this.w, ck = (c - ci) / this.w;
    const off = Math.hypot(this.x0 + (ci + 0.5) * CELL - x, this.z0 + (ck + 0.5) * CELL - z);
    return front[c] + (c === this._cellIndex(x, z) ? 0 : off);
  }

  dir(x, z, out, front = this.front, goal = this.goal) {
    out.set(0, 0, 0);
    if (!this.built) this.build();
    const c = this._bestCell(x, z, front);
    if (c < 0) return out;
    const { w, h } = this;
    const ci = c % w, ck = (c - ci) / w;
    const cx = this.x0 + (ci + 0.5) * CELL, cz = this.z0 + (ck + 0.5) * CELL;
    const d0 = front[c];
    const gx = goal.x - x, gz = goal.z - z;
    const straight = Math.hypot(goal.x - cx, goal.z - cz);
    // Goal cell, or the path is (nearly) the straight line: head straight for the goal (no 45° zig-zag).
    if (d0 === 0 || d0 <= straight * 1.06 + 0.3) {
      const l = Math.hypot(gx, gz);
      if (l > 1e-4) out.set(gx / l, 0, gz / l);
      return out;
    }
    let best = -1, bd = d0;
    for (let n = 0; n < 8; n++) {
      const i = ci + DI[n], k = ck + DK[n];
      if (i < 0 || k < 0 || i >= w || k >= h) continue;
      const v = k * w + i;
      if (front[v] < bd && this._link(c, v, n)) { bd = front[v]; best = v; }
    }
    if (best < 0) return out;
    const bi = best % w, bk = (best - bi) / w;
    const tx = this.x0 + (bi + 0.5) * CELL - x, tz = this.z0 + (bk + 0.5) * CELL - z;
    const l = Math.hypot(tx, tz);
    if (l > 1e-4) out.set(tx / l, 0, tz / l);
    return out;
  }

  // Bounded second field toward (x, z), solved synchronously (Tiny Tele lure: only zombies within `maxDist` metres
  // of PATH distance are lured; the others keep the player's field). Returns { dist(x, z), dir(x, z, out), goal }.
  // One shared instance: a new call re-solves it.
  localField(x, z, maxDist = 15) {
    if (!this.built) this.build();
    const { w, h } = this;
    const n = w * h;
    if (!this._lf) {
      const f = new Float32Array(n);
      this._lf = { field: f, heap: new Int32Array(n * 8), key: new Float32Array(n * 8), goal: { x: 0, z: 0, cell: -1 } };
      const nav = this, L = this._lf;
      L.api = {
        goal: L.goal,
        dist: (px, pz) => nav.dist(px, pz, L.field),
        dir: (px, pz, out) => nav.dir(px, pz, out, L.field, L.goal),
      };
    }
    const L = this._lf, field = L.field, heap = L.heap, key = L.key;
    field.fill(Infinity);
    let hn = 0;
    const push = (idx, k) => {
      let i = hn++;
      while (i > 0) { const p = (i - 1) >> 1; if (key[p] <= k) break; heap[i] = heap[p]; key[i] = key[p]; i = p; }
      heap[i] = idx; key[i] = k;
    };
    const pop = () => {
      const top = heap[0], tk = key[0];
      const lastI = heap[--hn], lastK = key[hn];
      let i = 0;
      for (;;) {
        let c = 2 * i + 1;
        if (c >= hn) break;
        if (c + 1 < hn && key[c + 1] < key[c]) c++;
        if (key[c] >= lastK) break;
        heap[i] = heap[c]; key[i] = key[c]; i = c;
      }
      if (hn > 0) { heap[i] = lastI; key[i] = lastK; }
      _popOut[0] = top; _popOut[1] = tk;
    };
    const cell = this._cellIndex(x, z);
    L.goal.x = x; L.goal.z = z; L.goal.cell = cell;
    if (cell >= 0 && this._open(cell)) { field[cell] = 0; push(cell, 0); }
    else {
      const [ci, ck] = this._cellXY(x, z);
      const r = Math.ceil(SEED_R / CELL);
      for (let k = Math.max(0, ck - r); k <= Math.min(h - 1, ck + r); k++) {
        for (let i = Math.max(0, ci - r); i <= Math.min(w - 1, ci + r); i++) {
          const idx = k * w + i;
          if (!this._open(idx)) continue;
          const d = Math.hypot(this.x0 + (i + 0.5) * CELL - x, this.z0 + (k + 0.5) * CELL - z);
          if (d <= SEED_R && d < field[idx]) { field[idx] = d; push(idx, d); }
        }
      }
    }
    const limit = maxDist + 2;
    while (hn > 0) {
      pop();
      const u = _popOut[0], du = _popOut[1];
      if (du > field[u] || du > limit) continue;
      const ui = u % w, uk = (u - ui) / w;
      for (let nn = 0; nn < 8; nn++) {
        const vi = ui + DI[nn], vk = uk + DK[nn];
        if (vi < 0 || vk < 0 || vi >= w || vk >= h) continue;
        const v = vk * w + vi;
        if (!this._link(v, u, OPP[nn])) continue;
        const nd = du + (nn < 4 ? CELL : CELL * SQRT2) + (this.near[v] ? WALL_COST : 0);
        if (nd < field[v]) { field[v] = nd; push(v, nd); }
      }
    }
    return L.api;
  }

  walkable(x, z) {
    if (!this.built) this.build();
    const c = this._cellIndex(x, z);
    return c >= 0 && this._open(c);
  }

  heightAt(x, z) {
    if (!this.built) this.build();
    const c = this._cellIndex(x, z);
    return c >= 0 && this.base[c] ? this.height[c] : -Infinity;
  }

  // ------------------------------------------------------------------------------------------------ debug
  debugImage(mode = 'dist') {
    if (!this.built) this.build();
    const { w, h } = this;
    const data = new Uint8ClampedArray(w * h * 4);
    let maxD = 1;
    for (let i = 0; i < w * h; i++) if (this.front[i] < Infinity && this.front[i] > maxD) maxD = this.front[i];
    const col = new THREE.Color();
    for (let i = 0; i < w * h; i++) {
      const o = i * 4;
      const door = this.doorOf[i];
      if (door >= 0 && this.base[i]) {
        const open = this.doorOpen.get(this.doorIds[door]) === true;
        data.set(open ? [80, 230, 120, 220] : [235, 60, 50, 230], o);
        continue;
      }
      if (!this.base[i]) { data.set([20, 12, 28, 170], o); continue; }
      if (mode === 'height') {
        const v = Math.min(1, Math.max(0, this.height[i] / 1.5));
        col.setHSL(0.62 - v * 0.62, 0.8, 0.45 + v * 0.2);
      } else if (this.front[i] === Infinity) {
        col.setRGB(0.45, 0.45, 0.5);
      } else {
        const v = this.front[i] / maxD;
        col.setHSL(0.33 - v * 0.33 + (Math.floor(this.front[i]) % 2) * 0.02, 0.85, 0.5);
      }
      data[o] = col.r * 255; data[o + 1] = col.g * 255; data[o + 2] = col.b * 255; data[o + 3] = 150;
    }
    return { width: w, height: h, data, x0: this.x0, z0: this.z0, cell: CELL };
  }
}

const _popOut = [0, 0];
