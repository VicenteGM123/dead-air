// Collision world (ARCHITECTURE §7): static + toggleable axis-aligned boxes in a 4 m XZ spatial hash, plus
// "ramp" floor shapes (a box whose top slopes down to its base over `inset` metres on every edge).
//
// Box flags (defaults come from the tag, explicit options win):
//   walkable  its top is standable (floors, platforms, stairs, props you may climb). A non-walkable box is a
//             pure obstacle: it blocks the circle whenever it rises above the feet.
//   solid     blocks moveCircle / nav            shots   blocks raycast / lineOfSight
//   camera    blocks sphereFree (camera collision)
// Tag defaults: window (player-only entry blockers) → not walkable, no shots (the camera does not pass: it would
// end up outside the building looking in through the boards); fence & lattice →
// not walkable, no shots; wall/door/glass/rail → not walkable. Any other tag (props, floors) → all true.
//
// API
//   addBox(min:[x,y,z], max:[x,y,z], {tag, id, walkable, solid, shots, camera}) → handle
//   addRamp(rect:[x0,z0,x1,z1], y0, y1, inset, {tag, id}) → handle   (floor shape; never blocks sideways)
//   setEnabled(handleOrId, on)                     toggles one box or every box sharing that id
//   moveCircle(pos, delta, radius, height, stepUp=0.45, ignore?) → { onGround, hitWall, groundY, normal, hitCeiling }
//       mutates pos (feet). Horizontal motion is sub-stepped (≤ 0.1 m) and pushed out of blockers (slides),
//       walkable boxes whose top is ≤ feet + stepUp are stepped onto (chains of steps climb, like stairs), and
//       ramps are followed. While grounded (remembered per pos object) the feet snap down ≤ stepUp, so stairs
//       and ramps are walked down instead of fallen off; an airborne body lands when it reaches the floor.
//       The result object is reused between calls. ignore = array of tags (or a mask from maskOf()), e.g.
//       ['window'] for a zombie climbing through its entry.
//   floorAt(x, z, yFrom=Infinity, stepUp=0.45) → highest walkable top at (x,z) that is ≤ yFrom + stepUp
//   raycast(origin, dir, maxDist, {ignoreTags, camera}) → { dist, point, normal, tag, id } | null   (shots boxes;
//       camera:true tests the camera-blocking boxes instead: the third-person camera probe)
//   lineOfSight(a, b) → bool                       sphereFree(pos, r) → bool
//   blockedAt(x, z, r, floorY, stepUp, height, ignore?) → bool   (the moveCircle rule, for the nav grid)
//   maskOf(tags) → int                             boxes (array of every box record, read-only)
// Hot paths (moveCircle, floorAt, lineOfSight, sphereFree) allocate nothing.

import * as THREE from 'three';

const CELL = 4;
const EPS = 1e-4;
const MAX_SUBSTEP = 0.1;
const SUPPORT = 0.5;       // ground support radius as a fraction of the body radius
const BIG_CELLS = 64;      // boxes covering more cells than this live in an always-tested list

const TAG_DEFAULTS = {
  window: { walkable: false, shots: false, camera: true },
  fence: { walkable: false, shots: false },
  lattice: { walkable: false, shots: false },
  wall: { walkable: false },
  door: { walkable: false },
  glass: { walkable: false },
  rail: { walkable: false },
};

const _res = { onGround: false, hitWall: false, groundY: -Infinity, hitCeiling: false, normal: new THREE.Vector3() };
const _grounded = new WeakMap();
const _dir = new THREE.Vector3();
const _hit = { t: 0, box: null, nx: 0, ny: 0, nz: 0 };

export class Collision {
  constructor({ bounds = [-128, -128, 192, 128] } = {}) {
    this.boxes = [];
    this.bx0 = bounds[0];
    this.bz0 = bounds[1];
    this.nx = Math.ceil((bounds[2] - bounds[0]) / CELL);
    this.nz = Math.ceil((bounds[3] - bounds[1]) / CELL);
    this.cells = Array.from({ length: this.nx * this.nz }, () => []);
    this.big = [];
    this._stamp = 1;
    this._tagBits = new Map();
    this._maskCache = new WeakMap();
    this._byId = new Map();
    this._list = [];
    this._n = 0;
  }

  // ------------------------------------------------------------------------------------------ building
  addBox(min, max, opts = {}) {
    const tag = opts.tag || 'prop';
    const d = TAG_DEFAULTS[tag] || {};
    return this._insert({
      tag, id: opts.id ?? null, bit: this._bit(tag),
      minX: Math.min(min[0], max[0]), minY: Math.min(min[1], max[1]), minZ: Math.min(min[2], max[2]),
      maxX: Math.max(min[0], max[0]), maxY: Math.max(min[1], max[1]), maxZ: Math.max(min[2], max[2]),
      walkable: opts.walkable ?? d.walkable ?? true,
      solid: opts.solid ?? d.solid ?? true,
      shots: opts.shots ?? d.shots ?? true,
      camera: opts.camera ?? d.camera ?? true,
      ramp: 0, enabled: true, stamp: 0,
    });
  }

  addRamp(rect, y0, y1, inset, opts = {}) {
    const tag = opts.tag || 'platform';
    return this._insert({
      tag, id: opts.id ?? null, bit: this._bit(tag),
      minX: rect[0], minY: y0, minZ: rect[1], maxX: rect[2], maxY: y1, maxZ: rect[3],
      walkable: true, solid: false, shots: true, camera: false,
      ramp: inset, enabled: true, stamp: 0,
    });
  }

  setEnabled(handleOrId, on) {
    if (handleOrId && typeof handleOrId === 'object') { handleOrId.enabled = !!on; return; }
    const list = this._byId.get(handleOrId);
    if (list) for (const b of list) b.enabled = !!on;
  }

  maskOf(tags) {
    if (!tags) return 0;
    if (typeof tags === 'number') return tags;
    let m = this._maskCache.get(tags);
    if (m === undefined) {
      m = 0;
      for (const t of tags) m |= this._bit(t);
      this._maskCache.set(tags, m);
    }
    return m;
  }

  _bit(tag) {
    let bit = this._tagBits.get(tag);
    if (bit === undefined) {
      bit = 1 << Math.min(30, this._tagBits.size);
      this._tagBits.set(tag, bit);
    }
    return bit;
  }

  _cellI(x) { const i = Math.floor((x - this.bx0) / CELL); return i < 0 ? 0 : i >= this.nx ? this.nx - 1 : i; }
  _cellK(z) { const k = Math.floor((z - this.bz0) / CELL); return k < 0 ? 0 : k >= this.nz ? this.nz - 1 : k; }

  _insert(b) {
    this.boxes.push(b);
    if (b.id !== null) {
      if (!this._byId.has(b.id)) this._byId.set(b.id, []);
      this._byId.get(b.id).push(b);
    }
    const i0 = this._cellI(b.minX), i1 = this._cellI(b.maxX), k0 = this._cellK(b.minZ), k1 = this._cellK(b.maxZ);
    if ((i1 - i0 + 1) * (k1 - k0 + 1) > BIG_CELLS) this.big.push(b);
    else for (let k = k0; k <= k1; k++) for (let i = i0; i <= i1; i++) this.cells[k * this.nx + i].push(b);
    return b;
  }

  // Collect every enabled box overlapping the XZ rect into this._list[0.._n) (each box once).
  _gather(minX, minZ, maxX, maxZ) {
    const out = this._list;
    let n = 0;
    const stamp = ++this._stamp;
    for (let j = 0; j < this.big.length; j++) {
      const b = this.big[j];
      if (b.enabled && b.maxX >= minX && b.minX <= maxX && b.maxZ >= minZ && b.minZ <= maxZ) out[n++] = b;
    }
    const i0 = this._cellI(minX), i1 = this._cellI(maxX), k0 = this._cellK(minZ), k1 = this._cellK(maxZ);
    for (let k = k0; k <= k1; k++) {
      for (let i = i0; i <= i1; i++) {
        const list = this.cells[k * this.nx + i];
        for (let j = 0; j < list.length; j++) {
          const b = list[j];
          if (b.stamp === stamp) continue;
          b.stamp = stamp;
          if (b.enabled && b.maxX >= minX && b.minX <= maxX && b.maxZ >= minZ && b.minZ <= maxZ) out[n++] = b;
        }
      }
    }
    this._n = n;
    return n;
  }

  // --------------------------------------------------------------------------------------------- floor
  static rampHeight(b, x, z) {
    const e = Math.min(x - b.minX, b.maxX - x, z - b.minZ, b.maxZ - z);
    const k = e <= 0 ? 0 : e >= b.ramp ? 1 : e / b.ramp;
    return b.minY + (b.maxY - b.minY) * k;
  }

  floorAt(x, z, yFrom = Infinity, stepUp = 0.45) {
    const lim = yFrom + stepUp + EPS;
    let best = -Infinity;
    const n = this._gather(x, z, x, z);
    for (let j = 0; j < n; j++) {
      const b = this._list[j];
      if (!b.walkable) continue;
      const top = b.ramp ? Collision.rampHeight(b, x, z) : b.maxY;
      if (top <= lim && top > best) best = top;
    }
    return best;
  }

  // Highest walkable support under a disc among the gathered boxes (ramps sampled at the disc centre).
  _ground(x, z, r, lim, mask) {
    let best = -Infinity;
    for (let j = 0; j < this._n; j++) {
      const b = this._list[j];
      if (!b.walkable || (b.bit & mask)) continue;
      let top;
      if (b.ramp) {
        if (x < b.minX || x > b.maxX || z < b.minZ || z > b.maxZ) continue;
        top = Collision.rampHeight(b, x, z);
      } else {
        if (!circleHitsRect(x, z, r, b)) continue;
        top = b.maxY;
      }
      if (top <= lim && top > best) best = top;
    }
    return best;
  }

  // Does box b stop a body standing at `feet`? (shared by moveCircle and blockedAt)
  static _blocks(b, feet, stepUp, height) {
    if (!b.solid || b.ramp) return false;
    if (b.minY >= feet + height - EPS) return false;
    if (b.walkable) return b.maxY > feet + stepUp + EPS;
    return b.maxY > feet + 0.02;
  }

  // ------------------------------------------------------------------------------------------ movement
  moveCircle(pos, delta, radius, height, stepUp = 0.45, ignore = null) {
    const mask = this.maskOf(ignore);
    const res = _res;
    res.hitWall = false;
    res.hitCeiling = false;
    res.normal.set(0, 0, 0);
    const wasGrounded = _grounded.has(pos) ? _grounded.get(pos) : true;

    // One gather covers the whole swept disc (plus the jump height for ceilings).
    const reach = radius + 0.05;
    this._gather(Math.min(pos.x, pos.x + delta.x) - reach, Math.min(pos.z, pos.z + delta.z) - reach,
      Math.max(pos.x, pos.x + delta.x) + reach, Math.max(pos.z, pos.z + delta.z) + reach);

    const len = Math.hypot(delta.x, delta.z);
    const steps = Math.max(1, Math.ceil(len / Math.min(MAX_SUBSTEP, radius * 0.5)));
    const sx = delta.x / steps, sz = delta.z / steps;
    let feet = pos.y;
    for (let s = 0; s < steps; s++) {
      pos.x += sx;
      pos.z += sz;
      feet = this._resolve(pos, radius, height, feet, stepUp, mask, res);
    }

    // Vertical: support under the body (raised by any steps climbed this frame), ceilings when rising.
    const ground = this._ground(pos.x, pos.z, radius * SUPPORT, Math.max(feet, pos.y) + stepUp + EPS, mask);
    let y = pos.y + delta.y;
    if (delta.y > 0) {
      const head = pos.y + height;
      for (let j = 0; j < this._n; j++) {
        const b = this._list[j];
        if (!b.solid || b.ramp || (b.bit & mask) || b.minY < head - EPS || b.minY >= y + height) continue;
        if (!circleHitsRect(pos.x, pos.z, radius * 0.9, b)) continue;
        y = b.minY - height;
        res.hitCeiling = true;
      }
    }
    let onGround = false;
    if (y <= ground) { y = ground; onGround = true; }
    else if (wasGrounded && delta.y <= 0 && pos.y - ground <= stepUp + EPS) { y = ground; onGround = true; }
    pos.y = y;
    _grounded.set(pos, onGround);
    res.onGround = onGround;
    res.groundY = ground;
    return res;
  }

  // One horizontal sub-step over the gathered boxes: climb overlapped steps, then push the disc out of
  // blockers. Returns the stand height used for blocking.
  _resolve(pos, r, height, feet, stepUp, mask, res) {
    const list = this._list, n = this._n;
    // Step-up fixpoint: every walkable top ≤ stand + stepUp under the disc raises the stand height.
    let stand = feet;
    for (let pass = 0; pass < 3; pass++) {
      const before = stand;
      for (let j = 0; j < n; j++) {
        const b = list[j];
        if (!b.walkable || b.ramp || !b.solid || (b.bit & mask)) continue;
        if (b.maxY <= stand + EPS || b.maxY > stand + stepUp + EPS || b.minY >= stand + height) continue;
        if (circleHitsRect(pos.x, pos.z, r, b)) stand = b.maxY;
      }
      if (stand === before) break;
    }
    // Push-out iterations (axis-aligned corners converge in two; four is headroom, no jitter).
    for (let it = 0; it < 4; it++) {
      let moved = false;
      for (let j = 0; j < n; j++) {
        const b = list[j];
        if ((b.bit & mask) || !Collision._blocks(b, stand, stepUp, height)) continue;
        const cx = pos.x < b.minX ? b.minX : pos.x > b.maxX ? b.maxX : pos.x;
        const cz = pos.z < b.minZ ? b.minZ : pos.z > b.maxZ ? b.maxZ : pos.z;
        let dx = pos.x - cx, dz = pos.z - cz;
        const d2 = dx * dx + dz * dz;
        if (d2 >= r * r) continue;
        let push;
        if (d2 > 1e-12) {
          const d = Math.sqrt(d2);
          dx /= d; dz /= d;
          push = r - d;
        } else {
          // Centre inside the box: leave through the nearest face.
          const l = pos.x - b.minX, rr = b.maxX - pos.x, nn = pos.z - b.minZ, s = b.maxZ - pos.z;
          const m = Math.min(l, rr, nn, s);
          dx = m === l ? -1 : m === rr ? 1 : 0;
          dz = dx !== 0 ? 0 : m === nn ? -1 : 1;
          push = m + r;
        }
        pos.x += dx * (push + EPS);
        pos.z += dz * (push + EPS);
        res.hitWall = true;
        res.normal.set(dx, 0, dz);
        moved = true;
      }
      if (!moved) break;
    }
    return stand;
  }

  // The moveCircle blocking rule evaluated for a disc standing at floorY (nav grid clearance).
  blockedAt(x, z, r, floorY, stepUp, height, ignore = null) {
    const mask = this.maskOf(ignore);
    const n = this._gather(x - r, z - r, x + r, z + r);
    for (let j = 0; j < n; j++) {
      const b = this._list[j];
      if (!(b.bit & mask) && Collision._blocks(b, floorY, stepUp, height) && circleHitsRect(x, z, r, b)) return true;
    }
    return false;
  }

  // ------------------------------------------------------------------------------------------- queries
  raycast(origin, dir, maxDist, opts = {}) {
    const hit = this._cast(origin, dir, maxDist, this.maskOf(opts.ignoreTags), opts.camera ? 'camera' : 'shots', false);
    if (!hit) return null;
    return {
      dist: hit.t,
      point: new THREE.Vector3().copy(origin).addScaledVector(dir, hit.t),
      normal: new THREE.Vector3(hit.nx, hit.ny, hit.nz),
      tag: hit.box.tag,
      id: hit.box.id,
    };
  }

  lineOfSight(a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z;
    const d = Math.hypot(dx, dy, dz);
    if (d < 1e-6) return true;
    _dir.set(dx / d, dy / d, dz / d);
    return !this._cast(a, _dir, d - 1e-3, 0, 'shots', true);
  }

  sphereFree(pos, r) {
    const n = this._gather(pos.x - r, pos.z - r, pos.x + r, pos.z + r);
    for (let j = 0; j < n; j++) {
      const b = this._list[j];
      if (!b.camera || b.ramp) continue;
      const cx = Math.max(b.minX, Math.min(pos.x, b.maxX)) - pos.x;
      const cy = Math.max(b.minY, Math.min(pos.y, b.maxY)) - pos.y;
      const cz = Math.max(b.minZ, Math.min(pos.z, b.maxZ)) - pos.z;
      if (cx * cx + cy * cy + cz * cz < r * r) return false;
    }
    return true;
  }

  // Grid DDA over the XZ hash; slab test per box. anyHit=true returns at the first hit (line of sight).
  _cast(o, d, maxDist, mask, flag, anyHit) {
    const best = _hit;
    best.t = maxDist;
    best.box = null;
    const stamp = ++this._stamp;
    for (let j = 0; j < this.big.length; j++) {
      const b = this.big[j];
      if (b.enabled && b[flag] && !(b.bit & mask) && slab(o, d, b, best.t) && anyHit) return best;
    }
    let i = Math.floor((o.x - this.bx0) / CELL), k = Math.floor((o.z - this.bz0) / CELL);
    const stepI = d.x > 0 ? 1 : -1, stepK = d.z > 0 ? 1 : -1;
    const tDeltaI = Math.abs(d.x) > 1e-9 ? CELL / Math.abs(d.x) : Infinity;
    const tDeltaK = Math.abs(d.z) > 1e-9 ? CELL / Math.abs(d.z) : Infinity;
    let tMaxI = Math.abs(d.x) > 1e-9 ? (this.bx0 + (i + (stepI > 0 ? 1 : 0)) * CELL - o.x) / d.x : Infinity;
    let tMaxK = Math.abs(d.z) > 1e-9 ? (this.bz0 + (k + (stepK > 0 ? 1 : 0)) * CELL - o.z) / d.z : Infinity;
    let tCell = 0;
    while (tCell <= best.t) {
      if (i >= 0 && i < this.nx && k >= 0 && k < this.nz) {
        const list = this.cells[k * this.nx + i];
        for (let j = 0; j < list.length; j++) {
          const b = list[j];
          if (b.stamp === stamp) continue;
          b.stamp = stamp;
          if (b.enabled && b[flag] && !(b.bit & mask) && slab(o, d, b, best.t) && anyHit) return best;
        }
      }
      if (tMaxI < tMaxK) { tCell = tMaxI; tMaxI += tDeltaI; i += stepI; }
      else { tCell = tMaxK; tMaxK += tDeltaK; k += stepK; }
      if (tCell === Infinity) break;
      if ((i < 0 && stepI < 0) || (i >= this.nx && stepI > 0) || (k < 0 && stepK < 0) || (k >= this.nz && stepK > 0)) break;
    }
    return best.box ? best : null;
  }
}

function circleHitsRect(x, z, r, b) {
  const dx = x - (x < b.minX ? b.minX : x > b.maxX ? b.maxX : x);
  const dz = z - (z < b.minZ ? b.minZ : z > b.maxZ ? b.maxZ : z);
  return dx * dx + dz * dz < r * r;
}

// Ray/AABB slab test; ramps are tested as their flat plateau. Records into _hit when nearer than tMax.
// Boxes containing the origin are skipped so rays can leave a volume.
const _slab = { t0: 0, t1: 0, axis: -1, sign: 0 };

function slabAxis(o, d, lo, hi, a) {
  if (Math.abs(d) < 1e-12) return o >= lo && o <= hi;
  const inv = 1 / d;
  let ta = (lo - o) * inv, tb = (hi - o) * inv, s = -1;
  if (ta > tb) { const t = ta; ta = tb; tb = t; s = 1; }
  if (ta > _slab.t0) { _slab.t0 = ta; _slab.axis = a; _slab.sign = s; }
  if (tb < _slab.t1) _slab.t1 = tb;
  return _slab.t0 <= _slab.t1;
}

function slab(o, d, b, tMax) {
  const i = b.ramp;
  const minX = b.minX + i, maxX = b.maxX - i, minZ = b.minZ + i, maxZ = b.maxZ - i;
  if (o.x >= minX && o.x <= maxX && o.y >= b.minY && o.y <= b.maxY && o.z >= minZ && o.z <= maxZ) return false;
  _slab.t0 = 0; _slab.t1 = tMax; _slab.axis = -1; _slab.sign = 0;
  if (!slabAxis(o.x, d.x, minX, maxX, 0) || !slabAxis(o.y, d.y, b.minY, b.maxY, 1)
    || !slabAxis(o.z, d.z, minZ, maxZ, 2)) return false;
  if (_slab.axis < 0 || _slab.t0 >= tMax) return false;
  _hit.t = _slab.t0;
  _hit.box = b;
  _hit.nx = _slab.axis === 0 ? _slab.sign : 0;
  _hit.ny = _slab.axis === 1 ? _slab.sign : 0;
  _hit.nz = _slab.axis === 2 ? _slab.sign : 0;
  return true;
}
