// Windows and Yard entries (GDD §5.4, §5.9): frames per window style, the six scenery-flat boards of every
// boarded window with animated tear/repair, the fence-climb spots and the ajar chain-link vehicle gate.
// Boards are instanced (GDD §3.9): one InstancedMesh per scenery slice (sky, brick, fence, stars, sunset,
// hedge), one instance per boarded window, so all 78 boards cost 6 draw calls. Board k of a window is present
// iff k < boards: tearing removes the top-most present board, repairing puts back the lowest missing one.
//
// buildWindows(ctx) → { list: Win[], boards: BoardSet }   ctx = { game, surf, group(areaId), root }
// Win (becomes level.windows[id]): every layout field (inside/outside/spawn stay arrays) plus
//   boards (live count), pos (Vector3 inside point at 1 m), spawnPos, outsidePos (Vector3),
//   boardMeshes: 6 handles { slice, present, position:Vector3, quaternion } (instanced, not Meshes),
//   breakBoard() → bool (emits barricade:break {id, boards}, sound board_tear), breakAll() → count,
//   repairBoard() → bool (emits barricade:repair {id, boards}, sound board_repair), reset().
// Fence climbs and the gate are Win objects with 0 boards (their break/repair calls return false).

import * as THREE from 'three';
import * as geo from '../core/geo.js';
import { WINDOWS, WALL_T, FENCE_H } from './layout.js';
import { AREA_STYLE } from './surfaces.js';

const H = WALL_T / 2;
const SLICES = 6;
const BOARD_H = 0.22;
const BOARD_T = 0.05;
const TEAR_TIME = 0.95;
const REPAIR_TIME = 0.3;
const rnd = (a, b) => a + Math.random() * (b - a);

const _m = new THREE.Matrix4();
const _p = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _e = new THREE.Euler();
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);

export function buildWindows(ctx) {
  const boarded = WINDOWS.filter((w) => w.type === 'boarded');
  const boards = new BoardSet(ctx, boarded.length);
  const list = WINDOWS.map((w) => new Win(ctx, w, boards, boarded.indexOf(w)));
  boards.commit();
  return { list, boards };
}

// ------------------------------------------------------------------------------------------ board instances
class BoardSet {
  constructor(ctx, count) {
    this.meshes = [];
    const mat = ctx.surf.plain('boards');
    for (let k = 0; k < SLICES; k++) {
      const len = k < 4 ? 2.05 : 2.15;
      const im = new THREE.InstancedMesh(boardGeometry(len, k), mat, Math.max(1, count));
      im.name = `boards:${k}`;
      im.castShadow = true;
      im.receiveShadow = true;
      im.frustumCulled = false;
      im.userData.dynamic = true;
      ctx.root.add(im);
      this.meshes.push(im);
    }
    this.active = new Set();
  }

  set(slice, index, matrix) {
    this.meshes[slice].setMatrixAt(index, matrix);
    this.meshes[slice].instanceMatrix.needsUpdate = true;
  }

  commit() {
    for (const m of this.meshes) m.instanceMatrix.needsUpdate = true;
  }

  update(dt) {
    for (const w of this.active) if (!w.animate(dt)) this.active.delete(w);
  }
}

// A plank with the scenery slice on its two big faces and raw plywood on the edges (texture band 6).
function boardGeometry(len, slice) {
  const g = geo.roundedBox(len, BOARD_H, BOARD_T, 0.015, 2).clone();
  const uv = g.attributes.uv, n = g.attributes.normal;
  for (let i = 0; i < uv.count; i++) {
    const face = Math.abs(n.getZ(i)) > 0.7;
    const band = face ? slice : 6;
    uv.setY(i, 1 - (band + 1) / 7 + (0.06 + uv.getY(i) * 0.88) / 7);
  }
  return g;
}

// --------------------------------------------------------------------------------------------------- window
class Win {
  constructor(ctx, data, set, index) {
    Object.assign(this, data);
    this.game = ctx.game;
    this.set = set;
    this.index = index;
    const nIn = new THREE.Vector3(data.inside[0] - data.outside[0], 0, data.inside[2] - data.outside[2]).normalize();
    this.pivot = new THREE.Object3D();
    this.pivot.position.set(data.wall[0], 0, data.wall[1]);
    this.pivot.rotation.y = Math.atan2(nIn.x, nIn.z);
    this.pivot.updateMatrixWorld(true);
    this.pos = new THREE.Vector3(data.inside[0], data.inside[1] + 1.0, data.inside[2]);
    this.spawnPos = new THREE.Vector3(...data.spawn);
    this.outsidePos = new THREE.Vector3(...data.outside);
    this.boardMeshes = [];
    this._anim = new Array(SLICES).fill(null);
    if (data.type === 'boarded') {
      buildFrame(ctx, this);
      this._layoutBoards();
    } else if (data.type === 'fence') buildClimb(ctx, this);
    else buildGate(ctx, this);
  }

  // Rest pose of the six boards (window-local): 4 near-horizontal slats + 2 crossing diagonals in front.
  _layoutBoards() {
    const h = this.top - this.sill;
    const diag = Math.min(0.62, Math.atan2(h * 0.55, 1.9));
    for (let k = 0; k < SLICES; k++) {
      const horiz = k < 4;
      const y = horiz ? this.sill + (h * (k + 0.5)) / 4 + rnd(-0.03, 0.03) : this.sill + h * 0.5 + (k === 4 ? 0.05 : -0.05);
      const rz = horiz ? rnd(0.035, 0.12) * (k % 2 ? 1 : -1) : (k === 4 ? diag : -diag);
      // In front of the frame (FRAME_PROUD): the lowest layer's back clears the frame face by 2 mm.
      const local = { pos: new THREE.Vector3(rnd(-0.06, 0.06), y, H + FRAME_PROUD + 0.027 + k * 0.012), rot: new THREE.Euler(0, 0, rz) };
      const handle = { slice: k, present: true, local, position: new THREE.Vector3(), quaternion: new THREE.Quaternion() };
      _m.compose(local.pos, _q.setFromEuler(local.rot), _s.set(1, 1, 1)).premultiply(this.pivot.matrixWorld);
      _m.decompose(handle.position, handle.quaternion, _s);
      this.boardMeshes.push(handle);
    }
    this.reset();
  }

  _place(k, pos, quat, scale) {
    _m.compose(pos, quat, _s.setScalar(scale)).premultiply(this.pivot.matrixWorld);
    this.set.set(k, this.index, _m);
  }

  breakBoard() {
    if (this.boards <= 0) return false;
    const k = --this.boards;
    const b = this.boardMeshes[k];
    b.present = false;
    this._anim[k] = {
      type: 'tear', t: 0,
      v: new THREE.Vector3(rnd(-1, 1), rnd(1.5, 3), -rnd(2.5, 4)),
      w: new THREE.Vector3(rnd(-6, 6), rnd(-3, 3), rnd(-9, 9)),
      p: b.local.pos.clone(), r: b.local.rot.clone(),
    };
    this.set.active.add(this);
    this.game.events && this.game.events.emit('barricade:break', { id: this.id, boards: this.boards });
    if (this.game.audio) this.game.audio.play('board_tear', { pos: this.pos });
    return true;
  }

  breakAll() {
    let n = 0;
    while (this.breakBoard()) n++;
    return n;
  }

  repairBoard() {
    if (this.type !== 'boarded' || this.boards >= SLICES) return false;
    const k = this.boards++;
    const b = this.boardMeshes[k];
    b.present = true;
    this._anim[k] = {
      type: 'repair', t: 0,
      p: new THREE.Vector3(rnd(-0.5, 0.5), 0.05, H + 0.9),
      q: new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, rnd(-0.6, 0.6))),
    };
    this.set.active.add(this);
    this.game.events && this.game.events.emit('barricade:repair', { id: this.id, boards: this.boards });
    if (this.game.audio) this.game.audio.play('board_repair', { pos: this.pos });
    return true;
  }

  reset() {
    if (this.type !== 'boarded') { this.boards = 0; return; }
    this.boards = SLICES;
    this._anim.fill(null);
    this.boardMeshes.forEach((b, k) => {
      b.present = true;
      this._place(k, b.local.pos, _q.setFromEuler(b.local.rot), 1);
    });
  }

  // Advances board animations; returns true while any is running.
  animate(dt) {
    let busy = false;
    for (let k = 0; k < SLICES; k++) {
      const a = this._anim[k];
      if (!a) continue;
      a.t += dt;
      const b = this.boardMeshes[k];
      if (a.type === 'tear') {
        const t = Math.min(a.t, TEAR_TIME);
        _p.copy(a.p).addScaledVector(a.v, t);
        _p.y += -7 * t * t;
        if (_p.y < 0.05) _p.y = 0.05;
        _e.set(a.r.x + a.w.x * t, a.w.y * t, a.r.z + a.w.z * t);
        const s = 1 - THREE.MathUtils.smoothstep(t, TEAR_TIME * 0.65, TEAR_TIME);
        if (a.t >= TEAR_TIME) { this.set.set(k, this.index, ZERO); this._anim[k] = null; continue; }
        this._place(k, _p, _q.setFromEuler(_e), s);
      } else {
        const k01 = Math.min(1, a.t / REPAIR_TIME);
        const e = 1 + 2.2 * (k01 - 1) ** 3 + 1.2 * (k01 - 1) ** 2;
        _p.lerpVectors(a.p, b.local.pos, e);
        _p.y += Math.sin(Math.PI * k01) * 0.45;
        _q.slerpQuaternions(a.q, _q2.setFromEuler(b.local.rot), Math.min(1, e));
        this._place(k, _p, _q, 1);
        if (k01 >= 1) { this._anim[k] = null; continue; }
      }
      busy = true;
    }
    return busy;
  }
}

// ---------------------------------------------------------------------------------------------- frames
function frameMaterial(ctx, w) {
  const M = ctx.game.mats;
  if (w.style === 'glass_door') return M.toon('#6E5A44', { metal: 0.55, rough: 0.35, rimColor: '#FFC98A' });
  if (w.style === 'window') return ctx.surf.plain(AREA_STYLE[w.area].wall.baseboard);
  return ctx.surf.plain('trim_steel');
}

function shard(M, pts) {
  const s = new THREE.Shape();
  s.moveTo(pts[0], pts[1]);
  for (let i = 2; i < pts.length; i += 2) s.lineTo(pts[i], pts[i + 1]);
  return new THREE.Mesh(new THREE.ShapeGeometry(s), M.glass('#CFE8FF', { opacity: 0.35 }));
}

// Frame: jambs + head wrapping the wall ends, FRAME_PROUD proud of both faces (deeper than any wall trim), the
// inner faces FRAME_INSET inside the opening (architecture.js does not draw the jamb caps, soffit and sill top
// they cover: drawn in the same planes they z-fought). The jambs stand on the sill board and stop under the head
// (no overlapping, coplanar corner blocks).
const FRAME_PROUD = 0.05;
const FRAME_INSET = 0.005;
const FRAME_W = 0.12;

function buildFrame(ctx, w) {
  const M = ctx.game.mats;
  const g = new THREE.Group();
  g.position.copy(w.pivot.position);
  g.rotation.copy(w.pivot.rotation);
  const mat = frameMaterial(ctx, w);
  const I = FRAME_INSET, W = w.width, D = 2 * (H + FRAME_PROUD);
  const jy0 = w.sill, jy1 = w.top - I, jw = FRAME_W + I;
  for (const s of [-1, 1]) g.add(geo.mesh(geo.roundedBox(jw, jy1 - jy0, D, 0.02, 2), mat, { pos: [s * (W / 2 - I + jw / 2), (jy0 + jy1) / 2, 0] }));
  g.add(geo.mesh(geo.roundedBox(W + 2 * FRAME_W, FRAME_W + I, D, 0.02, 2), mat, { pos: [0, jy1 + (FRAME_W + I) / 2, 0] }));
  if (w.sill > 0) {
    g.add(geo.mesh(geo.roundedBox(W + 0.34, 0.06, D + 0.14, 0.02, 2), mat, { pos: [0, w.sill - 0.03, 0.07] }));
  } else {
    g.add(geo.mesh(geo.roundedBox(W - 2 * I, 0.04, D, 0.01, 1), mat, { pos: [0, 0.02, 0] }));
  }
  if (w.style === 'glass_door') {
    // Storefront door remains: the aluminium kick rail and broken glass along the frame.
    g.add(geo.mesh(geo.roundedBox(W - 2 * I, 0.3, 0.05, 0.02, 2), mat, { pos: [0, 0.2, -0.02] }));
  }
  if (w.style === 'loading' || w.style === 'dock') {
    // Hazard stripe decal under the sill, 6 mm off the wall (4 mm shimmered across Studio A).
    const hz = M.toon('#ffffff', { map: ctx.game.tex.stripes(['#F4C21E', '#231E24'], true, 12), rough: 0.6, rim: 0 });
    g.add(geo.mesh(geo.plane(W + 0.2, 0.14), hz, { pos: [0, w.sill - 0.13, H + 0.006], cast: false }));
  }
  if (w.style === 'dock') {
    const rubber = M.toon('#231E24', { rough: 0.9 });
    for (const s of [-1, 1]) g.add(geo.mesh(geo.roundedBox(0.25, 0.3, 0.14, 0.04, 2), rubber, { pos: [s * 0.62, w.sill - 0.2, -(H + 0.07)] }));
  }
  const x0 = -W / 2, x1 = W / 2, y0 = w.sill, y1 = w.top;
  for (const pts of [
    [x0, y1, x0 + 0.45, y1, x0, y1 - 0.35],
    [x1, y1, x1, y1 - 0.5, x1 - 0.22, y1],
    [x0, y0, x0, y0 + 0.3, x0 + 0.18, y0],
    [x1, y0 + 0.02, x1 - 0.4, y0 + 0.02, x1 - 0.1, y0 + 0.22],
  ]) {
    const m = shard(M, pts);
    m.position.z = -0.01;
    g.add(m);
  }
  ctx.group(w.area).add(g);
}

// Fence climb: a pallet leaning on the chain-link outside and an oil drum to step on.
function buildClimb(ctx, w) {
  const M = ctx.game.mats;
  const g = new THREE.Group();
  g.position.copy(w.pivot.position);
  g.rotation.copy(w.pivot.rotation);
  const wood = M.toon('#A8784A', { map: ctx.game.tex.woodPanel('#A8784A'), rough: 0.7 });
  const pallet = new THREE.Group();
  for (let i = 0; i < 5; i++) pallet.add(geo.mesh(geo.roundedBox(0.16, 1.2, 0.03, 0.01, 1), wood, { pos: [-0.48 + i * 0.24, 0, 0] }));
  for (const y of [-0.5, 0, 0.5]) pallet.add(geo.mesh(geo.roundedBox(1.1, 0.1, 0.1, 0.02, 1), wood, { pos: [0, y, -0.06] }));
  pallet.position.set(-0.2, 0.62, -0.3);
  pallet.rotation.set(-0.28, 0, 0.04);
  g.add(pallet);
  const drum = M.toon('#B5472A', { metal: 0.4, rough: 0.5 });
  g.add(geo.mesh(geo.cylinder(0.29, 0.29, 0.88, 18), drum, { pos: [0.55, 0.44, -0.55] }));
  for (const y of [0.25, 0.63]) g.add(geo.mesh(geo.torus(0.295, 0.02, 6, 24), drum, { pos: [0.55, y, -0.55], rot: [Math.PI / 2, 0, 0] }));
  ctx.group(w.area).add(g);
  w.boards = 0;
}

// Vehicle gate: two chain-link leaves; the east leaf hangs ajar into the Yard leaving a squeeze gap.
function buildGate(ctx, w) {
  const M = ctx.game.mats;
  const g = new THREE.Group();
  g.position.copy(w.pivot.position);
  g.rotation.copy(w.pivot.rotation);
  const steel = ctx.surf.plain('galvanized');
  const link = ctx.surf.plain('chainlink');
  const W = w.width, lw = W / 2 - 0.08, lh = FENCE_H - 0.25;
  for (const s of [-1, 1]) g.add(geo.mesh(geo.cylinder(0.075, 0.075, FENCE_H + 0.25, 12), steel, { pos: [s * W / 2, (FENCE_H + 0.25) / 2, 0] }));
  const leaf = (s) => {
    const hinge = new THREE.Group();
    hinge.position.set(s * (W / 2 - 0.05), 0, 0);
    const c = -s * lw / 2;
    const tube = (len, pos, rot) => hinge.add(geo.mesh(geo.cylinder(0.035, 0.035, len, 8), steel, { pos, rot }));
    tube(lh, [-s * 0.02, 0.1 + lh / 2, 0]);
    tube(lh, [-s * lw, 0.1 + lh / 2, 0]);
    for (const y of [0.1, 0.1 + lh]) tube(lw, [c, y, 0], [0, 0, Math.PI / 2]);
    tube(Math.hypot(lw, lh), [c, 0.1 + lh / 2, 0], [0, 0, s * Math.atan2(lw, lh)]);
    const cl = new THREE.PlaneGeometry(lw, lh);
    const uv = cl.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * lw / 0.5, uv.getY(i) * lh / 0.5);
    hinge.add(geo.mesh(cl, link, { pos: [c, 0.1 + lh / 2, 0], cast: false }));
    g.add(hinge);
    return hinge;
  };
  leaf(-1);
  leaf(1).rotation.y = 0.42;
  const chain = M.toon('#9AA0A8', { metal: 0.85, rough: 0.3 });
  for (let i = 0; i < 7; i++) {
    const m = geo.mesh(geo.torus(0.035, 0.009, 6, 10), chain, { pos: [-0.03, 1.25 - i * 0.07, 0.04], cast: false });
    m.rotation.y = i % 2 ? Math.PI / 2 : 0;
    g.add(m);
  }
  ctx.group(w.area).add(g);
  w.boards = 0;
}
